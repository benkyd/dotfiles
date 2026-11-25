/* choose-tree.c: tmux-style choose-tree for Rex, compiled so it opens instantly.
 *
 * init.lua's tmux_choose_tree runs this in a floating pane once it's built. It draws its
 * first frame a millisecond or two after it starts, where Python takes 50 to 100, which
 * was most of the time between C-b w and the tree. choose-tree.py is the same picker in
 * Python: it stands in until this is built, and builds it in the background the first
 * time it runs, into ~/.cache/rex under a name init.lua takes from this file's contents.
 *
 * Arguments, in any order:
 *   client:ID            the app client that pressed C-b w
 *   RS...                this server's sessions as records (below)
 *   hosts:A<US>B...      other hosts, whose sessions are read in the background
 *   server:LABEL         this server's own label, left out of hosts
 *   watcher:PATH         choose-tree-watcher.lua
 * Records are separated by RS (0x1e) and fields by US (0x1f):
 *   S id label active_window current(0/1) focused_block zoomed(0/1)
 *   T id name focused_block          (a tab of the session before it)
 *
 * Keys, and the hand-over to choose-tree-watcher.lua, are as in choose-tree.py. Each frame
 * rewrites only the lines that changed, so a key costs a few bytes, which matters when the
 * tree runs on another host.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define VERSION "10"
#define RS '\x1e'
#define US '\x1f'

extern char **environ;

static const char *FOOTER =
    "j/k move  1-9 session  enter go  h/l fold  J/K order  r rename  x kill  n new  H host  q quit";

/* Another host's sessions, read with the CLI connected to that host directly, as records.
 * Tab names are labels only: a process lookup per tab would be a network round trip each. */
static const char *REMOTE_LUA =
    "local RS, US = string.char(30), string.char(31)\n"
    "local bad = '[' .. RS .. US .. ']'\n"
    "local function clean(s) return (tostring(s or ''):gsub(bad, ' ')) end\n"
    "local parts = {}\n"
    "local list = rex.call('session.list')\n"
    "for _, s in ipairs(type(list) == 'table' and list.sessions or {}) do\n"
    "  local ok, v = pcall(rex.call, 'session.view', { session_id = s.session_id })\n"
    "  if ok and type(v) == 'table' and v.windows then\n"
    "    parts[#parts + 1] = RS .. table.concat({ 'S', clean(s.session_id), clean(s.label), clean(v.active_window_id), '0', '', '0' }, US)\n"
    "    for i, w in ipairs(v.windows) do\n"
    "      local name = w.label\n"
    "      if not name or name:match('^Window %x+$') then name = 'tab ' .. i end\n"
    "      parts[#parts + 1] = RS .. table.concat({ 'T', clean(w.window_id), clean(name), clean(w.focused_block_id) }, US)\n"
    "    end\n"
    "  end\n"
    "end\n"
    "local text = string.char(2) .. table.concat(parts) .. string.char(3)\n"
    "if not pcall(io.write, text) then return text end\n";

/* The app's client on this server, when the one C-b w gave isn't known here: the app client
 * attached to this pane's session, the most recently connected first. */
static const char *RESOLVE_LUA =
    "local a = rex.args or {}\n"
    "local r = rex.call('client.list')\n"
    "local best, when = nil, ''\n"
    "for _, c in ipairs(type(r) == 'table' and r.clients or {}) do\n"
    "  if c.client_id == a.given then io.write(c.client_id) return end\n"
    "  if (c.info or {}).kind == 'app' then\n"
    "    local here = '0'\n"
    "    for _, s in ipairs(c.session_ids or {}) do if s == a.session then here = '1' end end\n"
    "    local key = here .. (c.connected_at or '')\n"
    "    if key > when then best, when = c.client_id, key end\n"
    "  end\n"
    "end\n"
    "io.write(best or '')\n";

/* ---- strings ------------------------------------------------------------------------ */

typedef struct { char *p; size_t n, cap; } Buf;

static void bput(Buf *b, const char *s, size_t n) {
    if (b->n + n + 1 > b->cap) {
        size_t cap = b->cap ? b->cap : 256;
        while (cap < b->n + n + 1) cap *= 2;
        b->p = realloc(b->p, cap);
        b->cap = cap;
    }
    memcpy(b->p + b->n, s, n);
    b->n += n;
    b->p[b->n] = 0;
}
static void bputs(Buf *b, const char *s) { bput(b, s, strlen(s)); }
static void bprintf(Buf *b, const char *fmt, ...) {
    char tmp[512];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof tmp, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if ((size_t)n < sizeof tmp) { bput(b, tmp, (size_t)n); return; }
    char *big = malloc((size_t)n + 1);
    va_start(ap, fmt);
    vsnprintf(big, (size_t)n + 1, fmt, ap);
    va_end(ap);
    bput(b, big, (size_t)n);
    free(big);
}
static void bjson(Buf *b, const char *s) { /* s as a JSON string */
    bputs(b, "\"");
    for (const unsigned char *p = (const unsigned char *)(s ? s : ""); *p; p++) {
        if (*p == '"' || *p == '\\') { char e[2] = {'\\', (char)*p}; bput(b, e, 2); }
        else if (*p < 0x20) bprintf(b, "\\u%04x", *p);
        else bput(b, (const char *)p, 1);
    }
    bputs(b, "\"");
}
static char *xstrdup(const char *s) { return strdup(s ? s : ""); }
static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}
static void sleep_ms(int ms) {
    struct timespec t = {ms / 1000, (long)(ms % 1000) * 1000000L};
    nanosleep(&t, NULL);
}
static int cells_of(const char *s) { /* a cell per UTF-8 character */
    int n = 0;
    for (const unsigned char *p = (const unsigned char *)s; *p; p++)
        if ((*p & 0xC0) != 0x80) n++;
    return n;
}

/* ---- the log ------------------------------------------------------------------------ */

static const char *LOG = "/tmp/choose-tree-watcher.log";

static void note(const char *fmt, ...) {
    FILE *f = fopen(LOG, "a");
    if (!f) return;
    time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    fprintf(f, "%02d:%02d:%02d c: ", tm.tm_hour, tm.tm_min, tm.tm_sec);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

/* ---- sessions ----------------------------------------------------------------------- */

typedef struct { char *id, *name, *block; } Tab;
typedef struct {
    char *id, *label, *active, *block, *host;
    int current, zoomed, folded, ntabs, captabs;
    Tab *tabs;
} Sess;

static Sess *S;
static int NS, CAPS;
static char *ORIG_ID = ""; /* the session C-b w was pressed in */

static Sess *orig(void) {
    for (int i = 0; i < NS; i++)
        if (!S[i].host && !strcmp(S[i].id, ORIG_ID)) return &S[i];
    return NULL;
}
static Sess *add_session(void) {
    if (NS == CAPS) { CAPS = CAPS ? CAPS * 2 : 16; S = realloc(S, (size_t)CAPS * sizeof *S); }
    Sess *s = &S[NS++];
    memset(s, 0, sizeof *s);
    return s;
}
static void add_tab(Sess *s, const char *id, const char *name, const char *block) {
    if (s->ntabs == s->captabs) {
        s->captabs = s->captabs ? s->captabs * 2 : 4;
        s->tabs = realloc(s->tabs, (size_t)s->captabs * sizeof *s->tabs);
    }
    Tab *t = &s->tabs[s->ntabs++];
    t->id = xstrdup(id);
    t->name = xstrdup(name);
    t->block = xstrdup(block);
}
static void remove_session(int i) {
    memmove(&S[i], &S[i + 1], (size_t)(NS - i - 1) * sizeof *S);
    NS--;
}
static int split(char *s, char sep, char **f, int max) {
    int n = 0;
    f[n++] = s;
    for (char *p = s; *p && n < max; p++)
        if (*p == sep) { *p = 0; f[n++] = p + 1; }
    return n;
}
/* Records into S. host is NULL for this server's. Returns how many sessions came. */
static int parse_records(const char *text, size_t len, const char *host) {
    char *s = malloc(len + 1);
    memcpy(s, text, len);
    s[len] = 0;
    int before = NS;
    for (char *rec = s; rec;) {
        char *next = strchr(rec, RS);
        if (next) *next++ = 0;
        if (*rec) {
            char *f[8];
            int nf = split(rec, US, f, 8);
            for (int i = nf; i < 8; i++) f[i] = "";
            if (f[0][0] == 'S' && nf >= 4) {
                Sess *x = add_session();
                x->id = xstrdup(f[1]);
                x->label = xstrdup(f[2]);
                x->active = xstrdup(f[3]);
                x->current = !host && f[4][0] == '1';
                x->block = xstrdup(f[5]);
                x->zoomed = f[6][0] == '1';
                x->host = host ? xstrdup(host) : NULL;
            } else if (f[0][0] == 'T' && nf >= 3 && NS > before) {
                add_tab(&S[NS - 1], f[1], f[2], f[3]);
            }
        }
        rec = next;
    }
    free(s);
    return NS - before;
}
static const char *tab_name_of(const Sess *s, const char *wid) {
    for (int i = 0; i < s->ntabs; i++)
        if (!strcmp(s->tabs[i].id, wid)) return s->tabs[i].name;
    return "";
}
static int same_host(const Sess *a, const Sess *b) {
    if (!a->host || !b->host) return !a->host && !b->host;
    return !strcmp(a->host, b->host);
}

/* ---- rows --------------------------------------------------------------------------- */

typedef struct { char kind; int si, ti; } Row; /* kind: s session, t tab, h heading, e empty */
static Row *R;
static int NR, CAPR, cursor;

static void add_row(char k, int si, int ti) {
    if (NR == CAPR) { CAPR = CAPR ? CAPR * 2 : 64; R = realloc(R, (size_t)CAPR * sizeof *R); }
    R[NR].kind = k;
    R[NR].si = si;
    R[NR].ti = ti;
    NR++;
}
static void build_rows(void) {
    NR = 0;
    const char *group = "";
    for (int si = 0; si < NS; si++) {
        const char *host = S[si].host ? S[si].host : "";
        if (*host && strcmp(host, group)) add_row('h', si, -1);
        group = host;
        add_row('s', si, -1);
        if (!S[si].folded)
            for (int ti = 0; ti < S[si].ntabs; ti++) add_row('t', si, ti);
    }
    if (!NR) add_row('e', -1, -1);
}
static int find_row(char k, int si, int ti) {
    for (int i = 0; i < NR; i++)
        if (R[i].kind == k && R[i].si == si && R[i].ti == ti) return i;
    return 0;
}

/* ---- the terminal ------------------------------------------------------------------- */

static struct termios saved;
static int raw_on;
static int W = 80, H = 24;
static volatile sig_atomic_t resized;
static const char ENTER_SEQ[] = "\x1b[?1049h\x1b[?25l\x1b[?1004h\x1b[H\x1b[2J";
static const char LEAVE_SEQ[] = "\x1b[?1004l\x1b[?25h\x1b[0m\x1b[?1049l";

static void out(const char *s, size_t n) {
    while (n) {
        ssize_t w = write(1, s, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return;
        }
        s += w;
        n -= (size_t)w;
    }
}
static void outs(const char *s) { out(s, strlen(s)); }
static void term_raw(void) {
    if (tcgetattr(0, &saved) == 0) {
        struct termios t = saved;
        t.c_iflag &= ~(tcflag_t)(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
        t.c_oflag &= ~(tcflag_t)OPOST;
        t.c_cflag |= CS8;
        t.c_lflag &= ~(tcflag_t)(ECHO | ICANON | IEXTEN | ISIG);
        t.c_cc[VMIN] = 1;
        t.c_cc[VTIME] = 0;
        tcsetattr(0, TCSANOW, &t);
    }
    raw_on = 1;
    out(ENTER_SEQ, sizeof ENTER_SEQ - 1);
}
static void term_restore(void) {
    if (!raw_on) return;
    out(LEAVE_SEQ, sizeof LEAVE_SEQ - 1);
    tcsetattr(0, TCSANOW, &saved);
    raw_on = 0;
}
static void on_winch(int sig) { (void)sig; resized = 1; }
static void on_leave(int sig) { /* Rex closing this pane: the watcher does, once it has the choice */
    (void)sig;
    if (raw_on) {
        if (write(1, LEAVE_SEQ, sizeof LEAVE_SEQ - 1) < 0) {}
        tcsetattr(0, TCSANOW, &saved);
    }
    _exit(0);
}
static void get_size(void) {
    struct winsize ws;
    if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 1) {
        W = ws.ws_col;
        H = ws.ws_row;
    }
}

/* ---- drawing ------------------------------------------------------------------------ */

static char **prev; /* the last frame's lines, to send only what changed */
static int prev_n, full_redraw = 1;

static void put_cells(Buf *b, const char *text, int width, int pad) { /* at most width cells */
    int cells = 0;
    const unsigned char *p = (const unsigned char *)text;
    while (*p && cells < width) {
        const unsigned char *q = p + 1;
        while ((*q & 0xC0) == 0x80) q++;
        bput(b, (const char *)p, (size_t)(q - p));
        cells++;
        p = q;
    }
    while (pad && cells++ < width) bput(b, " ", 1);
}
static void row_line(Buf *line, int r, int width) {
    Row *row = &R[r];
    Buf text = {0};
    const char *style = "";
    if (row->kind == 'e') {
        bputs(&text, "no sessions: n makes one");
        style = "\x1b[2m";
    } else if (row->kind == 'h') {
        bprintf(&text, "── %s ", S[row->si].host);
        for (int i = cells_of(text.p); i < width; i++) bputs(&text, "─");
        style = "\x1b[2m";
    } else if (row->kind == 's') {
        Sess *s = &S[row->si];
        bprintf(&text, "%c %d: %s  · %s (%d)", s->folded ? '+' : '-', row->si + 1, s->label,
                tab_name_of(s, s->active), s->ntabs);
        if (s->current) bputs(&text, " (attached)");
        style = s->current ? "\x1b[1;33m" : "\x1b[1;36m";
    } else {
        Sess *s = &S[row->si];
        Tab *t = &s->tabs[row->ti];
        bprintf(&text, "  %s %d: %s", row->ti == s->ntabs - 1 ? "└─>" : "├─>", row->ti + 1, t->name);
        if (!strcmp(t->id, s->active)) { bputs(&text, " ●"); style = "\x1b[32m"; }
    }
    bputs(line, style);
    if (r == cursor) bputs(line, "\x1b[7m");
    /* Only the highlighted row is padded out; the others end with erase-to-end-of-line */
    put_cells(line, text.p ? text.p : "", width, r == cursor);
    bputs(line, "\x1b[0m");
    free(text.p);
}
static void invalidate_footer(void) {
    if (prev && prev_n) { free(prev[prev_n - 1]); prev[prev_n - 1] = NULL; }
}
static void draw(const char *status) {
    if (resized) { resized = 0; full_redraw = 1; }
    get_size();
    build_rows();
    if (cursor >= NR) cursor = NR - 1;
    if (cursor < 0) cursor = 0;
    if (R[cursor].kind == 'h' && cursor + 1 < NR) cursor++;
    int body = H - 1, width = W - 1;
    if (width < 1) width = 1;
    int top = cursor - body + 1;
    if (top < 0) top = 0;
    if (prev_n != H) full_redraw = 1;
    char **lines = calloc((size_t)H, sizeof *lines);
    for (int y = 0; y < body; y++) {
        Buf l = {0};
        if (top + y < NR) row_line(&l, top + y, width);
        else bputs(&l, "");
        lines[y] = l.p;
    }
    {
        const char *text = status && *status ? status : FOOTER;
        Buf f = {0}, l = {0};
        bputs(&f, text);
        const char *tag = "v" VERSION;
        int fc = cells_of(text), tc = (int)strlen(tag);
        if (fc + tc + 2 < W) {
            for (int i = fc; i < width - tc; i++) bputs(&f, " ");
            bputs(&f, tag);
        }
        bputs(&l, status && *status ? "\x1b[1m" : "\x1b[2m");
        put_cells(&l, f.p, width, 0);
        bputs(&l, "\x1b[0m");
        free(f.p);
        lines[H - 1] = l.p;
    }
    Buf o = {0};
    if (full_redraw) bputs(&o, "\x1b[H\x1b[2J");
    for (int y = 0; y < H; y++) {
        if (!full_redraw && prev && y < prev_n && prev[y] && !strcmp(prev[y], lines[y])) continue;
        bprintf(&o, "\x1b[%d;1H", y + 1);
        bputs(&o, lines[y]);
        bputs(&o, "\x1b[K");
    }
    if (o.n) out(o.p, o.n);
    free(o.p);
    if (prev) {
        for (int i = 0; i < prev_n; i++) free(prev[i]);
        free(prev);
    }
    prev = lines;
    prev_n = H;
    full_redraw = 0;
}

/* ---- processes ---------------------------------------------------------------------- */

static char REX[4096] = "rex";
static char WATCHER[4096];

/* Start argv with stdin from /dev/null, stdout to out_fd (or the log) and stderr to the
 * log. new_session puts it in a session of its own, so closing this pane doesn't end it. */
static pid_t spawn_argv(char *const argv[], int out_fd, int new_session) {
    posix_spawn_file_actions_t fa;
    posix_spawnattr_t at;
    posix_spawn_file_actions_init(&fa);
    posix_spawnattr_init(&at);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    if (out_fd >= 0) posix_spawn_file_actions_adddup2(&fa, out_fd, 1);
    else posix_spawn_file_actions_addopen(&fa, 1, LOG, O_WRONLY | O_APPEND | O_CREAT, 0644);
    posix_spawn_file_actions_addopen(&fa, 2, LOG, O_WRONLY | O_APPEND | O_CREAT, 0644);
    short flags = POSIX_SPAWN_SETSIGDEF;
    sigset_t def;
    sigemptyset(&def);
    sigaddset(&def, SIGHUP);
    sigaddset(&def, SIGTERM);
    sigaddset(&def, SIGWINCH);
    posix_spawnattr_setsigdefault(&at, &def);
    if (new_session) flags |= POSIX_SPAWN_SETSID;
    posix_spawnattr_setflags(&at, flags);
    pid_t pid = -1;
    int rc = strchr(argv[0], '/') ? posix_spawn(&pid, argv[0], &fa, &at, argv, environ)
                                  : posix_spawnp(&pid, argv[0], &fa, &at, argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    posix_spawnattr_destroy(&at);
    if (rc) { note("starting %s failed: %s", argv[0], strerror(rc)); return -1; }
    return pid;
}
static int cloexec_pipe(int fds[2]) {
    if (pipe(fds)) return -1;
    fcntl(fds[0], F_SETFD, FD_CLOEXEC);
    fcntl(fds[1], F_SETFD, FD_CLOEXEC);
    return 0;
}
/* Run a rex command that changes a server (rename, move, kill) and wait; 1 if it worked. */
static int run_rex(const char *host, ...) {
    char *argv[20];
    int n = 0;
    argv[n++] = REX;
    if (host) { argv[n++] = "-S"; argv[n++] = (char *)host; }
    va_list ap;
    va_start(ap, host);
    char *a;
    while ((a = va_arg(ap, char *)) && n < 19) argv[n++] = a;
    va_end(ap);
    argv[n] = NULL;
    pid_t pid = spawn_argv(argv, -1, 0);
    if (pid < 0) return 0;
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    return WIFEXITED(st) && WEXITSTATUS(st) == 0;
}

/* ---- other hosts -------------------------------------------------------------------- */

typedef struct { char *host; pid_t pid; int fd; Buf buf; } Fetch;
static Fetch F[16];
static int NF;

static void start_fetch(const char *host) {
    int fds[2];
    if (NF >= 16 || cloexec_pipe(fds)) return;
    char *argv[] = {REX, "-S", (char *)host, "--timeout", "4s", "do", "-e", (char *)REMOTE_LUA, NULL};
    pid_t pid = spawn_argv(argv, fds[1], 0);
    close(fds[1]);
    if (pid < 0) { close(fds[0]); return; }
    fcntl(fds[0], F_SETFL, O_NONBLOCK);
    memset(&F[NF], 0, sizeof F[NF]);
    F[NF].host = xstrdup(host);
    F[NF].pid = pid;
    F[NF].fd = fds[0];
    NF++;
}
/* Read what fetch i sent; at its end, add its sessions. 1 if sessions were added. */
static int fetch_read(int i) {
    char tmp[8192];
    ssize_t n = read(F[i].fd, tmp, sizeof tmp);
    if (n > 0) { bput(&F[i].buf, tmp, (size_t)n); return 0; }
    if (n < 0 && (errno == EAGAIN || errno == EINTR)) return 0;
    close(F[i].fd);
    waitpid(F[i].pid, NULL, WNOHANG);
    int added = 0;
    char *b = F[i].buf.p, *stx = b ? memchr(b, 2, F[i].buf.n) : NULL;
    char *etx = stx ? memchr(stx, 3, F[i].buf.n - (size_t)(stx - b)) : NULL;
    if (!stx || !etx) {
        note("couldn't read %s's sessions", F[i].host);
    } else {
        int base = NS, got = parse_records(stx + 1, (size_t)(etx - stx - 1), F[i].host);
        int self = 0; /* a host that is this server: its sessions are already here */
        for (int x = base; x < NS && !self; x++)
            for (int l = 0; l < base; l++)
                if (!S[l].host && !strcmp(S[x].id, S[l].id)) { self = 1; break; }
        if (self) NS = base;
        else added = got > 0;
    }
    free(F[i].buf.p);
    memmove(&F[i], &F[i + 1], (size_t)(NF - i - 1) * sizeof *F);
    NF--;
    return added;
}

/* ---- keys --------------------------------------------------------------------------- */

enum { K_TIMEOUT = -1, K_DATA = -2, K_UP = 1000, K_DOWN, K_LEFT, K_RIGHT, K_ENTER, K_ESC, K_FIN, K_FOUT, K_BS };
static unsigned char ib[1024];
static int ilen, ipos;

/* Wait for typing or for another host's sessions. 1: typing read, 2: something to redraw,
 * 0: timed out. */
static int fill(int timeout_ms) {
    for (;;) {
        struct pollfd p[17];
        int n = 0;
        p[n].fd = 0; p[n].events = POLLIN; p[n].revents = 0; n++;
        for (int i = 0; i < NF; i++) { p[n].fd = F[i].fd; p[n].events = POLLIN; p[n].revents = 0; n++; }
        int r = poll(p, (nfds_t)n, timeout_ms);
        if (r < 0) {
            if (errno == EINTR) { if (resized) return 2; continue; }
            return 0;
        }
        if (r == 0) return 0;
        int changed = 0;
        for (int i = NF - 1; i >= 0; i--)
            if (p[i + 1].revents) changed |= fetch_read(i);
        if (p[0].revents & POLLIN) {
            if (ipos > 0) { memmove(ib, ib + ipos, (size_t)(ilen - ipos)); ilen -= ipos; ipos = 0; }
            ssize_t got = read(0, ib + ilen, sizeof ib - (size_t)ilen);
            if (got > 0) { ilen += (int)got; return 1; }
            if (got == 0 || (errno != EINTR && errno != EAGAIN)) { term_restore(); _exit(0); }
        } else if (p[0].revents & (POLLHUP | POLLERR | POLLNVAL)) {
            _exit(0); /* the pane is gone */
        }
        if (changed) return 2;
    }
}
static int byte_at(int k) { return ipos + k < ilen ? ib[ipos + k] : -1; }
static int next_key(int timeout_ms) {
    for (;;) {
        if (ipos >= ilen) {
            int r = fill(timeout_ms);
            if (r == 0) return K_TIMEOUT;
            if (r == 2) return K_DATA;
            continue;
        }
        int c = ib[ipos];
        if (c != 0x1b) {
            ipos++;
            if (c == '\r' || c == '\n') return K_ENTER;
            if (c == 0x7f || c == 0x08) return K_BS;
            return c;
        }
        /* escape alone, or the start of a sequence: arrows, or focus reports (mode 1004) */
        if (byte_at(1) < 0) {
            if (fill(10) != 1) { ipos++; return K_ESC; }
            continue;
        }
        int c1 = byte_at(1);
        if (c1 != '[' && c1 != 'O') { ipos++; return K_ESC; }
        int k = 2, key = 0;
        for (;;) {
            int ch = byte_at(k);
            if (ch < 0) {
                if (fill(10) != 1) { ipos = ilen; return K_ESC; }
                continue;
            }
            if (c1 == 'O' || (ch >= 0x40 && ch <= 0x7e)) {
                ipos += k + 1;
                if (ch == 'A') key = K_UP;
                else if (ch == 'B') key = K_DOWN;
                else if (ch == 'C') key = K_RIGHT;
                else if (ch == 'D') key = K_LEFT;
                else if (c1 == '[' && ch == 'I') key = K_FIN;
                else if (c1 == '[' && ch == 'O') key = K_FOUT;
                break;
            }
            if (++k > 32) { ipos += k; break; }
        }
        if (key) return key;
    }
}

/* ---- prompts ------------------------------------------------------------------------ */

/* Edit one line at the bottom. 1 entered, 0 escaped, -1 the pane lost focus. */
static int prompt(const char *label, const char *value, char *text, size_t size) {
    snprintf(text, size, "%s", value);
    outs("\x1b[?25h");
    int result = 1;
    for (;;) {
        Buf l = {0};
        bprintf(&l, "\x1b[%d;1H\x1b[0m\x1b[2K%s %s", H, label, text);
        out(l.p, l.n);
        free(l.p);
        int k = next_key(-1);
        if (k == K_DATA || k == K_TIMEOUT || k == K_FIN) continue;
        if (k == K_FOUT) { result = -1; break; }
        if (k == K_ENTER) break;
        if (k == K_ESC || k == 3) { result = 0; break; }
        size_t n = strlen(text);
        if (k == K_BS) {
            while (n > 0) { n--; if (((unsigned char)text[n] & 0xC0) != 0x80) break; }
            text[n] = 0;
        } else if (k == 0x15) { /* ctrl+u clears, as in a shell */
            text[0] = 0;
        } else if (k == 0x17) { /* ctrl+w deletes a word */
            while (n > 0 && text[n - 1] == ' ') n--;
            while (n > 0 && text[n - 1] != ' ') n--;
            text[n] = 0;
        } else if (k >= 0x20 && k < 0x100 && k != 0x7f && n + 1 < size) {
            text[n] = (char)k;
            text[n + 1] = 0;
        }
    }
    outs("\x1b[?25l");
    invalidate_footer();
    size_t n = strlen(text);
    while (n && text[n - 1] == ' ') text[--n] = 0;
    char *start = text;
    while (*start == ' ') start++;
    memmove(text, start, strlen(start) + 1);
    return result;
}
/* 1 yes, 0 no, -1 the pane lost focus. */
static int confirm(const char *question) {
    Buf l = {0};
    bprintf(&l, "\x1b[%d;1H\x1b[0m\x1b[2K\x1b[1m%s (y/n)\x1b[0m", H, question);
    out(l.p, l.n);
    free(l.p);
    for (;;) {
        int k = next_key(-1);
        if (k == K_DATA || k == K_TIMEOUT || k == K_FIN) continue;
        invalidate_footer();
        if (k == K_FOUT) return -1;
        return k == 'y' || k == 'Y';
    }
}

/* ---- browsing ----------------------------------------------------------------------- */

enum { CH_GO, CH_NEW, CH_SWITCH, CH_KILL, CH_CANCEL, CH_LOST };
static int CH_SI;
static const char *CH_WIN = "";
static char STATUS[512];

static void reorder(Row row, int step) {
    Sess *s = &S[row.si];
    if (row.kind == 's') {
        int i = row.si, o = i + step;
        if (o < 0 || o >= NS || !same_host(&S[o], s)) return;
        if (!run_rex(s->host, "session", "move", S[i].id, step > 0 ? "--after" : "--before", S[o].id, NULL)) {
            snprintf(STATUS, sizeof STATUS, "move failed");
            return;
        }
        Sess t = S[i];
        S[i] = S[o];
        S[o] = t;
        build_rows();
        cursor = find_row('s', o, -1);
    } else {
        int i = row.ti, o = i + step;
        if (o < 0 || o >= s->ntabs) return;
        if (!run_rex(s->host, "window", "move", "-s", s->id, s->tabs[i].id, step > 0 ? "--after" : "--before",
                     s->tabs[o].id, NULL)) {
            snprintf(STATUS, sizeof STATUS, "move failed");
            return;
        }
        Tab t = s->tabs[i];
        s->tabs[i] = s->tabs[o];
        s->tabs[o] = t;
        build_rows();
        cursor = find_row('t', row.si, o);
    }
}
/* 1 if the pane lost focus meanwhile. */
static int rename_row(Row row) {
    Sess *s = &S[row.si];
    char text[512];
    if (row.kind == 's') {
        int c = prompt("rename session:", s->label, text, sizeof text);
        if (c < 0) return 1;
        if (!c || !*text || !strcmp(text, s->label)) return 0;
        if (!run_rex(s->host, "session", "rename", s->id, text, NULL)) snprintf(STATUS, sizeof STATUS, "rename failed");
        else s->label = xstrdup(text);
    } else {
        Tab *t = &s->tabs[row.ti];
        int c = prompt("rename tab:", t->name, text, sizeof text);
        if (c < 0) return 1;
        if (!c || !*text || !strcmp(text, t->name)) return 0;
        if (!run_rex(s->host, "window", "rename", "-s", s->id, t->id, text, NULL)) snprintf(STATUS, sizeof STATUS, "rename failed");
        else t->name = xstrdup(text);
    }
    return 0;
}
/* Kill a session or tab, as tmux's choose-tree x does. A choice (>= 0) ends the tree: for
 * killing what this pane is in, which the watcher does. */
static int kill_row(Row row) {
    Sess *s = &S[row.si];
    char question[600];
    if (row.kind == 's') {
        snprintf(question, sizeof question, "kill session %s?", s->label);
        int c = confirm(question);
        if (c < 0) return CH_LOST;
        if (!c) return -1;
        if (s->current) { CH_SI = row.si; return CH_KILL; }
        if (!run_rex(s->host, "session", "kill", s->id, NULL)) { snprintf(STATUS, sizeof STATUS, "kill failed"); return -1; }
        remove_session(row.si);
        return NS ? -1 : CH_CANCEL;
    }
    Tab *t = &s->tabs[row.ti];
    snprintf(question, sizeof question, "kill tab %s?", t->name);
    int c = confirm(question);
    if (c < 0) return CH_LOST;
    if (!c) return -1;
    if (s->current && s->ntabs == 1) { CH_SI = row.si; return CH_KILL; }
    if (!run_rex(s->host, "window", "close", "-s", s->id, t->id, NULL)) { snprintf(STATUS, sizeof STATUS, "kill failed"); return -1; }
    int was_active = !strcmp(t->id, s->active);
    memmove(&s->tabs[row.ti], &s->tabs[row.ti + 1], (size_t)(s->ntabs - row.ti - 1) * sizeof *s->tabs);
    s->ntabs--;
    if (!s->ntabs) remove_session(row.si);
    else if (was_active) s->active = s->tabs[0].id;
    return NS ? -1 : CH_CANCEL;
}
static int browse(void) {
    int redraw = 1;
    for (;;) {
        if (redraw) { draw(STATUS); STATUS[0] = 0; }
        redraw = 1;
        int k = next_key(-1);
        if (k == K_TIMEOUT || k == K_FIN) { redraw = 0; continue; }
        if (k == K_DATA) continue;
        if (k == K_FOUT) return CH_LOST;
        build_rows();
        if (cursor >= NR) cursor = NR - 1;
        Row row = R[cursor];
        Sess *s = row.si >= 0 ? &S[row.si] : NULL;
        if (k == 'j' || k == K_DOWN || k == 'k' || k == K_UP) {
            int step = (k == 'j' || k == K_DOWN) ? 1 : -1, nx = (cursor + step + NR) % NR;
            while (R[nx].kind == 'h' && nx != cursor) nx = (nx + step + NR) % NR;
            cursor = nx;
        } else if (k == 'q' || k == K_ESC || k == 3) {
            return CH_CANCEL;
        } else if (k == 'n') {
            return CH_NEW;
        } else if (k == 'H') {
            return CH_SWITCH;
        } else if (k == 'g') {
            cursor = 0;
        } else if (k == 'G') {
            cursor = NR - 1;
        } else if (k >= '1' && k <= '9') {
            int i = k - '1';
            if (i < NS) { CH_SI = i; CH_WIN = S[i].active; return CH_GO; }
        } else if (row.kind == 'e' || row.kind == 'h') {
            /* nothing to act on */
        } else if (k == 'h' || k == K_LEFT) {
            if (row.kind == 't') cursor = find_row('s', row.si, -1);
            else s->folded = 1;
        } else if (k == 'l' || k == K_RIGHT) {
            s->folded = 0;
        } else if (k == 'J' || k == 'K') {
            reorder(row, k == 'J' ? 1 : -1);
        } else if (k == 'r') {
            if (rename_row(row)) return CH_LOST;
        } else if (k == 'x') {
            int ch = kill_row(row);
            if (ch >= 0) return ch;
        } else if (k == K_ENTER) {
            CH_SI = row.si;
            CH_WIN = row.kind == 't' ? s->tabs[row.ti].id : s->active;
            return CH_GO;
        } else {
            redraw = 0;
        }
    }
}

/* ---- the hand-over ------------------------------------------------------------------ */

static char *CLIENT = "";
static char *PICK_SESSION = "", *PICK_BLOCK = "";
static pid_t WPID = -1;
static char WTMP[512];
static Buf WARGS;

static void watcher_spawn(void) {
    char *argv[10];
    int n = 0;
    argv[n++] = REX;
    if (*CLIENT) { argv[n++] = "-C"; argv[n++] = CLIENT; }
    argv[n++] = "do";
    argv[n++] = WATCHER;
    argv[n++] = "--args";
    argv[n++] = WARGS.p;
    argv[n] = NULL;
    WPID = spawn_argv(argv, -1, 1);
}
static void watcher_start(void) { /* a watcher for one choice file */
    static int seq;
    snprintf(WTMP, sizeof WTMP, "/tmp/rex-ct-%d-%d-%lld.json", (int)getpid(), seq++, (long long)(now() * 1e6));
    Sess *o = orig();
    WARGS.n = 0;
    bputs(&WARGS, "{\"tmp\":");
    bjson(&WARGS, WTMP);
    bputs(&WARGS, ",\"rex\":");
    bjson(&WARGS, REX);
    bputs(&WARGS, ",\"session_id\":");
    bjson(&WARGS, o ? o->id : "");
    bputs(&WARGS, ",\"window_id\":");
    bjson(&WARGS, o ? o->active : "");
    bputs(&WARGS, ",\"block_id\":");
    bjson(&WARGS, o ? o->block : "");
    bputs(&WARGS, o && o->zoomed ? ",\"zoomed\":true" : ",\"zoomed\":false");
    bputs(&WARGS, ",\"picker_session\":");
    bjson(&WARGS, PICK_SESSION);
    bputs(&WARGS, ",\"picker_block\":");
    bjson(&WARGS, PICK_BLOCK);
    bputs(&WARGS, "}");
    watcher_spawn();
}
static char *resolve_client(void) {
    int fds[2];
    if (cloexec_pipe(fds)) return NULL;
    Buf args = {0};
    bputs(&args, "{\"given\":");
    bjson(&args, CLIENT);
    bputs(&args, ",\"session\":");
    bjson(&args, PICK_SESSION);
    bputs(&args, "}");
    char *argv[] = {REX, "--timeout", "4s", "do", "-e", (char *)RESOLVE_LUA, "--args", args.p, NULL};
    pid_t pid = spawn_argv(argv, fds[1], 0);
    close(fds[1]);
    Buf got = {0};
    char tmp[512];
    double end = now() + 5;
    for (;;) {
        int left = (int)((end - now()) * 1000);
        struct pollfd p = {fds[0], POLLIN, 0};
        if (left <= 0 || poll(&p, 1, left) <= 0) break;
        ssize_t n = read(fds[0], tmp, sizeof tmp);
        if (n <= 0) break;
        bput(&got, tmp, (size_t)n);
    }
    close(fds[0]);
    if (pid > 0) { kill(pid, SIGKILL); waitpid(pid, NULL, 0); }
    free(args.p);
    if (!got.p) return NULL;
    char *s = got.p, *e;
    while (*s == ' ' || *s == '\n' || *s == '\r') s++;
    for (e = s; *e && *e != '\n' && *e != '\r' && *e != ' '; e++) {}
    *e = 0;
    return strncmp(s, "client:", 7) ? NULL : xstrdup(s);
}
/* The "error" string of the watcher's reply, or NULL. */
static char *reply_error(const char *text) {
    const char *p = strstr(text, "\"error\"");
    if (!p || !(p = strchr(p + 7, '"'))) return NULL;
    Buf b = {0};
    for (p++; *p && *p != '"'; p++) {
        if (*p != '\\') { bput(&b, p, 1); continue; }
        p++;
        if (*p == 'n' || *p == 't') bputs(&b, " ");
        else if (*p == 'u' && p[1] && p[2] && p[3] && p[4]) {
            char hex[5] = {p[1], p[2], p[3], p[4], 0};
            unsigned v = (unsigned)strtoul(hex, NULL, 16);
            char u[4];
            if (v < 0x80) { u[0] = (char)v; bput(&b, u, 1); }
            else if (v < 0x800) { u[0] = (char)(0xC0 | (v >> 6)); u[1] = (char)(0x80 | (v & 0x3F)); bput(&b, u, 2); }
            else { u[0] = (char)(0xE0 | (v >> 12)); u[1] = (char)(0x80 | ((v >> 6) & 0x3F)); u[2] = (char)(0x80 | (v & 0x3F)); bput(&b, u, 3); }
            p += 4;
        } else if (*p) bput(&b, p, 1);
        else break;
    }
    return b.p;
}
/* Write the choice and keep the tree drawn until the watcher closes this pane, so the
 * switch looks like one step. NULL when the watcher has it, or the watcher's message when
 * the app refused (the tree then carries on). A watcher that failed to start, as when
 * this server doesn't know the client, is started again for the client found here. */
static char *hand_over(const char *json) {
    char part[600], reply[600];
    snprintf(part, sizeof part, "%s.part", WTMP);
    snprintf(reply, sizeof reply, "%s.reply", WTMP);
    FILE *f = fopen(part, "w");
    if (f) { fputs(json, f); fclose(f); rename(part, WTMP); }
    draw("…");
    int code = WPID > 0 ? -1 : 1, retried = 0; /* -1: running */
    double deadline = now() + 3;
    while (now() < deadline) {
        FILE *r = fopen(reply, "r");
        if (r) {
            char text[2048];
            size_t n = fread(text, 1, sizeof text - 1, r);
            fclose(r);
            text[n] = 0;
            unlink(reply);
            char *msg = reply_error(text);
            return msg && *msg ? msg : xstrdup("that couldn't be done from here");
        }
        if (code == -1) {
            int st = 0;
            pid_t w = waitpid(WPID, &st, WNOHANG);
            if (w == WPID) code = WIFEXITED(st) ? WEXITSTATUS(st) : 1;
            else if (w < 0) code = 0;
        }
        if (code == 0) return NULL; /* done, but it couldn't close this pane: leave */
        if (code > 0) {
            if (retried || access(WTMP, F_OK) != 0) return NULL;
            retried = 1;
            char *other = resolve_client();
            note("watcher exited %d; client %s -> %s", code, CLIENT, other ? other : "(none)");
            if (!other || !strcmp(other, CLIENT)) return NULL;
            CLIENT = other;
            watcher_spawn();
            code = WPID > 0 ? -1 : 1;
            deadline = now() + 3;
        }
        sleep_ms(5);
    }
    return NULL;
}
static char *result_json(int ch) {
    Buf b = {0};
    Sess *o = orig();
    if (ch == CH_GO) {
        Sess *s = &S[CH_SI];
        if (o && s == o && !strcmp(CH_WIN, o->active)) { /* already there: just put focus back */
            bputs(&b, "{\"type\":\"cancel\"}");
            return b.p;
        }
        bputs(&b, "{\"type\":\"select\",\"session_id\":");
        bjson(&b, s->id);
        bputs(&b, ",\"window_id\":");
        bjson(&b, CH_WIN);
        if (o && s == o) { /* another tab here: the watcher focuses it on the server */
            const char *blk = "";
            for (int i = 0; i < o->ntabs; i++)
                if (!strcmp(o->tabs[i].id, CH_WIN)) blk = o->tabs[i].block;
            bputs(&b, ",\"block_id\":");
            bjson(&b, blk);
        }
        if (s->host) { bputs(&b, ",\"host\":"); bjson(&b, s->host); }
        bputs(&b, "}");
    } else if (ch == CH_KILL) {
        bputs(&b, "{\"type\":\"kill\",\"session_id\":");
        bjson(&b, S[CH_SI].id);
        bputs(&b, "}");
    } else {
        bprintf(&b, "{\"type\":\"%s\"}", ch == CH_NEW ? "new" : ch == CH_SWITCH ? "switch" : ch == CH_LOST ? "lost" : "cancel");
    }
    return b.p;
}

/* ---- main --------------------------------------------------------------------------- */

int main(int argc, char **argv) {
    const char *tree = NULL, *hosts = NULL, *server = "";
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strncmp(a, "client:", 7)) CLIENT = (char *)a;
        else if (a[0] == RS) tree = a;
        else if (!strncmp(a, "hosts:", 6)) hosts = a + 6;
        else if (!strncmp(a, "server:", 7)) server = a + 7;
        else if (!strncmp(a, "watcher:", 8)) snprintf(WATCHER, sizeof WATCHER, "%s", a + 8);
    }
    const char *e;
    if ((e = getenv("REX_CHOOSE_TREE_LOG")) && *e) LOG = e;
    if ((e = getenv("REX_BIN_DIR")) && *e) snprintf(REX, sizeof REX, "%s/rex", e);
    if (!*WATCHER) snprintf(WATCHER, sizeof WATCHER, "%s/.config/rex/choose-tree-watcher.lua", getenv("HOME") ? getenv("HOME") : "");
    if ((e = getenv("REX_SESSION"))) PICK_SESSION = (char *)e;
    if ((e = getenv("REX_BLOCK"))) PICK_BLOCK = (char *)e;
    if (tree) parse_records(tree, strlen(tree), NULL);
    for (int i = 0; i < NS; i++)
        if (S[i].current) { ORIG_ID = S[i].id; break; }

    watcher_start(); /* first, so it's connected by the time a choice is made */

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_leave;
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sa.sa_handler = on_winch; /* no SA_RESTART: poll wakes up to redraw */
    sigaction(SIGWINCH, &sa, NULL);

    term_raw();
    build_rows();
    for (int i = 0; i < NR; i++) {
        Row *r = &R[i];
        if (r->kind == 's' && S[r->si].current) cursor = i; /* fallback: the current session's row */
        else if (r->kind == 't' && S[r->si].current && !strcmp(S[r->si].tabs[r->ti].id, S[r->si].active)) { cursor = i; break; }
    }
    draw(NULL);

    /* Other hosts only now, so starting them doesn't slow the first frame */
    Buf hostlist = {0};
    if (hosts && *hosts) {
        char *copy = xstrdup(hosts), *f[16];
        int n = split(copy, US, f, 16);
        for (int i = 0; i < n; i++)
            if (*f[i] && strcmp(f[i], server)) { start_fetch(f[i]); bprintf(&hostlist, "%s%s", hostlist.n ? "," : "", f[i]); }
    }
    {
        struct stat st;
        if (stat(LOG, &st) == 0 && st.st_size > 512 * 1024) truncate(LOG, 0);
        Sess *o = orig();
        note("--- v%s client=%s session=%s block=%s zoomed=%d hosts=%s", VERSION, CLIENT, o ? o->id : "",
             o ? o->block : "", o ? o->zoomed : 0, hostlist.p ? hostlist.p : "");
    }

    for (;;) {
        int ch = browse();
        char *json = result_json(ch);
        char *refused = hand_over(json);
        free(json);
        if (!refused) break;
        note("refused: %s", refused);
        snprintf(STATUS, sizeof STATUS, "%s", refused);
        free(refused);
        watcher_start(); /* that one has finished: a new one for the next choice */
    }
    term_restore();
    return 0;
}
