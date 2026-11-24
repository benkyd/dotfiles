#!/usr/bin/env python3
"""tmux-style choose-tree for Rex, run in a floating pane by init.lua's tmux_choose_tree.

argv: CLIENT_ID TREE_JSON [HOSTS_JSON], in any order
TREE_JSON lists this server's sessions: {id, label, current, active, tabs: [{id, name, block}]}.
The current session also has block, the block that had focus, and zoomed, whether its
window was zoomed. HOSTS_JSON is {hosts: [label], server: label}: the other hosts, whose
sessions are read in the background once the tree is drawn and added under a heading each.

Keys: j/k or arrows move (wrapping round), 1-9 go straight to that session, enter goes to
the row, h/l fold and unfold, g/G top and bottom, J/K reorder, r rename, x kill (y/n),
n new session, H switch host, q or escape close. Losing focus closes it, as tmux's does.

The switch itself is done by choose-tree-watcher.lua, a `rex do` script started here
before anything else, so it's connected by the time a choice is made. Its
rex.client.queue reaches the app the way a key binding does. This writes the choice to a
file and keeps the tree on screen; the watcher puts focus and zoom back on the block they
were on, closes this pane, then switches. If the app refuses (it takes actions only through
its home host), the watcher says why and the tree carries on.
"""
import json
import os
import signal
import sys
import time

VERSION = 9
WATCHER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "choose-tree-watcher.lua")
LOG = os.environ.get("REX_CHOOSE_TREE_LOG") or "/tmp/choose-tree-watcher.log"
REX = os.path.join(os.environ["REX_BIN_DIR"], "rex") if os.environ.get("REX_BIN_DIR") else "rex"

C_SESSION, C_ACTIVE, C_HERE = 1, 2, 3  # curses colour pairs: cyan, green, yellow
FOCUS_IN, FOCUS_OUT = "focus_in", "focus_out"
FOOTER = "j/k move  1-9 session  enter go  h/l fold  J/K order  r rename  x kill  n new  H host  q quit"
curses = None  # imported once the watcher is on its way: see main


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} py: {msg}\n")
    except OSError:
        pass


def run(*argv, host=None):
    """Run a rex command that changes a server (rename, move, kill); True if it worked."""
    import subprocess  # only here: importing it costs startup time on every open
    r = subprocess.run([REX, *(["-S", host] if host else []), *argv], capture_output=True, text=True)
    if r.returncode:
        log(f"{' '.join(argv)} failed: {r.stderr.strip()}")
    return r.returncode == 0


# --- the watcher ---------------------------------------------------------------------

def spawn_watcher(client, args):
    """Start the watcher in its own session, so closing this pane doesn't end it.
    posix_spawn instead of subprocess keeps subprocess's import off the hot path."""
    argv = [REX, "-C", client, "do", WATCHER, "--args", json.dumps(args)]
    actions = [
        (os.POSIX_SPAWN_OPEN, 0, os.devnull, os.O_RDONLY, 0),
        (os.POSIX_SPAWN_OPEN, 1, LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644),
        (os.POSIX_SPAWN_DUP2, 1, 2),
    ]
    spawn = os.posix_spawn if os.sep in REX else os.posix_spawnp
    return spawn(REX, argv, os.environ, file_actions=actions, setsid=True)


def resolve_client(given):
    """The app's client on this server. CLIENT_ID is the one the action saw, which this
    server may not know: then take the app client attached to this pane's session, the most
    recently connected first (a remote app attaches after the local one)."""
    import subprocess
    try:
        out = subprocess.run([REX, "client", "ls", "--json"], capture_output=True,
                             text=True, timeout=5).stdout
        clients = json.loads(out).get("clients") or []
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        log(f"client ls failed: {e!r}")
        return None
    if any(c.get("client_id") == given for c in clients):
        return given
    apps = [c for c in clients if (c.get("info") or {}).get("kind") == "app"]
    here = [c for c in apps if os.environ.get("REX_SESSION") in (c.get("session_ids") or [])]
    pool = sorted(here or apps, key=lambda c: c.get("connected_at") or "")
    return pool[-1]["client_id"] if pool else None


# Another host's sessions, read with the CLI connected to that host directly. Tab names are
# labels only: a process lookup per tab would be a network round trip each
REMOTE_LUA = r"""
local out = {}
local list = rex.call("session.list")
for _, s in ipairs(list and list.sessions or {}) do
  local ok, v = pcall(rex.call, "session.view", { session_id = s.session_id })
  if ok and v and v.windows then
    local tabs = {}
    for i, w in ipairs(v.windows) do
      local name = w.label
      if not name or name:match("^Window %x+$") then name = "tab " .. i end
      tabs[#tabs + 1] = { id = w.window_id, name = name, block = w.focused_block_id or "" }
    end
    out[#out + 1] = { id = s.session_id, label = s.label, active = v.active_window_id or "", tabs = tabs }
  end
end
local text = rex.json.encode(out)
if not pcall(io.write, "CTJSON:" .. text .. "\n") then return text end
"""


def spawn_fetch(host):
    """Start reading HOST's sessions; poll_fetches collects them."""
    r, w = os.pipe()
    argv = [REX, "-S", host, "--timeout", "4s", "do", "-e", REMOTE_LUA]
    actions = [
        (os.POSIX_SPAWN_OPEN, 0, os.devnull, os.O_RDONLY, 0),
        (os.POSIX_SPAWN_DUP2, w, 1),
        (os.POSIX_SPAWN_OPEN, 2, LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644),
    ]
    spawn = os.posix_spawn if os.sep in REX else os.posix_spawnp
    try:
        pid = spawn(REX, argv, os.environ, file_actions=actions)
    except Exception as e:
        log(f"reading {host} failed: {e!r}")
        os.close(r)
        return None
    finally:
        os.close(w)
    os.set_blocking(r, False)
    return {"host": host, "pid": pid, "fd": r, "buf": b""}


def parse_remote(buf):
    text = buf.decode("utf-8", "replace")
    line = next((l[len("CTJSON:"):] for l in text.splitlines() if l.startswith("CTJSON:")), None)
    try:
        got = json.loads(line if line is not None else text.strip())
        if isinstance(got, str):  # the script returned its JSON as a string
            got = json.loads(got)
    except ValueError:
        return None
    return got if isinstance(got, list) else []  # an empty Lua table encodes as {}


def poll_fetches(fetches, sessions):
    """Add the sessions of each host that has answered. True if any were added."""
    added = False
    local_ids = {s["id"] for s in sessions if not s.get("host")}
    for f in list(fetches):
        try:
            chunk = os.read(f["fd"], 65536)
        except BlockingIOError:
            continue
        except OSError:
            chunk = b""
        if chunk:
            f["buf"] += chunk
            continue
        os.close(f["fd"])
        fetches.remove(f)
        exited(f["pid"])
        got = parse_remote(f["buf"])
        if got is None:
            log(f"couldn't read {f['host']}'s sessions: {f['buf'][:200]!r}")
            continue
        if any(s.get("id") in local_ids for s in got):
            continue  # that host is this server
        for s in got:
            s.update(host=f["host"], current=False)
            sessions.append(s)
        added = added or bool(got)
    return added


def exited(pid):
    """None while the process runs, else its exit code."""
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return 0
    return os.waitstatus_to_exitcode(status) if done else None


class Watcher:
    """One watcher, waiting on one choice file. A choice the app refused needs a new one."""

    def __init__(self, client, orig):
        self.client = client
        self.tmp = f"/tmp/rex-ct-{os.getpid()}-{time.monotonic_ns()}.json"
        self.args = {
            "tmp": self.tmp,
            "rex": REX,
            "session_id": orig.get("id", ""),
            "window_id": orig.get("active", ""),
            "block_id": orig.get("block", ""),
            "zoomed": bool(orig.get("zoomed")),
            "picker_session": os.environ.get("REX_SESSION", ""),
            "picker_block": os.environ.get("REX_BLOCK", ""),
        }
        self.pid = None
        try:
            self.pid = spawn_watcher(client, self.args)
        except Exception as e:
            log(f"starting the watcher failed: {e!r}")

    def hand_over(self, scr, result):
        """Write the choice and keep the tree drawn until the watcher closes this pane, so
        the switch looks like one step. Returns None when the watcher has it, or the
        watcher's message when the app refused (then the tree carries on). A watcher that
        failed to start (as when this server doesn't know CLIENT_ID) is started again for
        the client found here."""
        reply = self.tmp + ".reply"
        part = self.tmp + ".part"
        with open(part, "w") as f:
            json.dump(result, f)
        os.replace(part, self.tmp)
        if scr is not None:
            height, width = scr.getmaxyx()
            scr.move(height - 1, 0)
            scr.clrtoeol()
            scr.addnstr(height - 1, 0, "…", width - 1, curses.A_DIM)
            scr.refresh()
        code = None if self.pid else 1
        retried = False
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if os.path.exists(reply):
                try:
                    with open(reply) as f:
                        message = json.load(f).get("error") or ""
                except (OSError, ValueError):
                    message = ""
                try:
                    os.remove(reply)
                except OSError:
                    pass
                return message or "that couldn't be done from here"
            if code is None and self.pid:
                code = exited(self.pid)  # reaped once, so keep the code
            if code == 0:
                return None  # done, but it couldn't close this pane: leave, focus is already back
            if code is not None:
                if retried or not os.path.exists(self.tmp):
                    return None
                retried = True
                other = resolve_client(self.client)
                log(f"watcher exited {code}; client {self.client} -> {other}")
                if not other or other == self.client:
                    return None
                self.client = other
                self.pid, code = spawn_watcher(other, self.args), None
                deadline = time.monotonic() + 3
            time.sleep(0.005)
        return None


# --- the tree ------------------------------------------------------------------------

def escape(scr):
    """After an escape byte, tell a focus report (ESC [ I or ESC [ O, sent because this
    pane turned on mode 1004) from the escape key itself."""
    scr.nodelay(True)
    try:
        if scr.getch() == ord("["):
            follow = scr.getch()
            if follow == ord("I"):
                return FOCUS_IN
            if follow == ord("O"):
                return FOCUS_OUT
        return 27
    finally:
        scr.nodelay(False)


def rows(sessions, folded):
    out = []
    group = ""
    for si, s in enumerate(sessions):
        host = s.get("host") or ""
        if host and host != group:
            out.append(("heading", None, host))
        group = host
        out.append(("session", si, None))
        if s["id"] not in folded:
            out.extend(("tab", si, ti) for ti in range(len(s["tabs"])))
    return out or [("empty", None, None)]


def draw(scr, sessions, folded, cursor, status=""):
    scr.erase()
    height, width = scr.getmaxyx()
    lines = rows(sessions, folded)
    top = max(0, cursor - height + 2)
    for y, (kind, si, ti) in enumerate(lines[top:top + height - 1]):
        s = sessions[si] if si is not None else None
        if kind == "empty":
            text, attr = "no sessions: n makes one", curses.A_DIM
        elif kind == "heading":
            text, attr = f"── {ti} " + "─" * max(0, width - len(ti) - 5), curses.A_DIM
        elif kind == "session":
            mark = "+" if s["id"] in folded else "-"
            active = next((t["name"] for t in s["tabs"] if t["id"] == s["active"]), "")
            count = len(s["tabs"])
            text = f"{mark} {si + 1}: {s['label']}  · {active} ({count})"
            if s["current"]:
                text += " (attached)"
            attr = curses.color_pair(C_HERE if s["current"] else C_SESSION) | curses.A_BOLD
        else:
            tab = s["tabs"][ti]
            branch = "└─>" if ti == len(s["tabs"]) - 1 else "├─>"
            text = f"  {branch} {ti + 1}: {tab['name']}"
            attr = curses.A_NORMAL
            if tab["id"] == s["active"]:
                text += " ●"
                attr = curses.color_pair(C_ACTIVE)
        if top + y == cursor:
            attr |= curses.A_REVERSE
        scr.addnstr(y, 0, text.ljust(width - 1), width - 1, attr)
    footer = status or FOOTER
    tag = f"v{VERSION}"  # which version runs here: dot copies files, so a host can lag behind
    if len(footer) + len(tag) + 2 < width:
        footer = footer.ljust(width - 1 - len(tag)) + tag
    scr.addnstr(height - 1, 0, footer, width - 1, curses.A_BOLD if status else curses.A_DIM)
    scr.refresh()


class FocusLost(Exception):
    pass


def prompt(scr, label, value):
    """Edit one line at the bottom of the pane. Returns the text, or None on escape."""
    curses.curs_set(1)
    text = value
    try:
        while True:
            height, width = scr.getmaxyx()
            line = f"{label} {text}"
            scr.move(height - 1, 0)
            scr.clrtoeol()
            scr.addnstr(height - 1, 0, line, width - 1)
            scr.move(height - 1, min(len(line), width - 2))
            scr.refresh()
            key = scr.get_wch()
            if key in ("\n", "\r", curses.KEY_ENTER):
                return text.strip()
            if key == "\x1b":
                seen = escape(scr)
                if seen == FOCUS_IN:
                    continue
                if seen == FOCUS_OUT:
                    raise FocusLost
                return None
            if key in ("\x7f", "\b", curses.KEY_BACKSPACE):
                text = text[:-1]
            elif key == "\x15":  # ctrl+u clears, as in a shell
                text = ""
            elif key == "\x17":  # ctrl+w deletes a word
                text = text.rstrip().rpartition(" ")[0]
            elif isinstance(key, str) and key.isprintable():
                text += key
    finally:
        curses.curs_set(0)


def confirm(scr, question):
    height, width = scr.getmaxyx()
    scr.move(height - 1, 0)
    scr.clrtoeol()
    scr.addnstr(height - 1, 0, f"{question} (y/n)", width - 1, curses.A_BOLD)
    scr.refresh()
    while True:
        key = scr.getch()
        if key == 27:
            seen = escape(scr)
            if seen == FOCUS_IN:
                continue
            if seen == FOCUS_OUT:
                raise FocusLost
        return key in (ord("y"), ord("Y"))


def rename(scr, s, kind, ti):
    if kind == "session":
        label = prompt(scr, "rename session:", s["label"])
        if label and label != s["label"]:
            if not run("session", "rename", s["id"], label, host=s.get("host")):
                return "rename failed"
            s["label"] = label
    else:
        tab = s["tabs"][ti]
        label = prompt(scr, "rename tab:", tab["name"])
        if label and label != tab["name"]:
            if not run("window", "rename", "-s", s["id"], tab["id"], label, host=s.get("host")):
                return "rename failed"
            tab["name"] = label
    return ""


def reorder(sessions, s, kind, si, ti, step):
    """Swap the session or tab with its neighbour (step 1 is down, -1 up), stopping at
    either end. Returns (status, row) with the row it has moved to."""
    if kind == "session":
        items, i, cmd = sessions, si, ["session", "move"]
    else:
        items, i, cmd = s["tabs"], ti, ["window", "move", "-s", s["id"]]
    other = i + step
    if not 0 <= other < len(items):
        return "", (kind, si, ti)
    if kind == "session" and items[other].get("host") != items[i].get("host"):
        return "", (kind, si, ti)  # sessions stay with their host
    where = "--after" if step > 0 else "--before"
    if not run(*cmd, items[i]["id"], where, items[other]["id"], host=s.get("host")):
        return "move failed", (kind, si, ti)
    items[i], items[other] = items[other], items[i]
    return "", (kind, other, None) if kind == "session" else (kind, si, other)


def kill(scr, sessions, s, kind, ti):
    """Kill a session or tab, as tmux's choose-tree x does. Returns (status, choice): a
    choice ends the tree, for killing what this pane is in, which the watcher does."""
    if kind == "session":
        if not confirm(scr, f"kill session {s['label']}?"):
            return "", None
        if s["current"]:
            return "", ("kill", s["id"])
        if not run("session", "kill", s["id"], host=s.get("host")):
            return "kill failed", None
        sessions.remove(s)
        return "", None if sessions else ("cancel",)
    tab = s["tabs"][ti]
    if not confirm(scr, f"kill tab {tab['name']}?"):
        return "", None
    if s["current"] and len(s["tabs"]) == 1:
        return "", ("kill", s["id"])
    if not run("window", "close", "-s", s["id"], tab["id"], host=s.get("host")):
        return "kill failed", None
    s["tabs"].pop(ti)
    if not s["tabs"]:
        sessions.remove(s)
    elif tab["id"] == s["active"]:
        s["active"] = s["tabs"][0]["id"]
    return "", None if sessions else ("cancel",)


def start_ui(scr, sessions, ui):
    curses.curs_set(0)
    curses.use_default_colors()
    if curses.has_colors():
        curses.init_pair(C_SESSION, curses.COLOR_CYAN, -1)
        curses.init_pair(C_ACTIVE, curses.COLOR_GREEN, -1)
        curses.init_pair(C_HERE, curses.COLOR_YELLOW, -1)
    os.write(sys.stdout.fileno(), b"\x1b[?1004h")  # report focus changes
    lines = rows(sessions, ui["folded"])
    for i, (kind, si, ti) in enumerate(lines):
        s = sessions[si] if si is not None else None
        if kind == "session" and s["current"]:
            ui["cursor"] = i  # fallback: the current session's row
        elif kind == "tab" and s["current"] and s["tabs"][ti]["id"] == s["active"]:
            ui["cursor"] = i
            break


def browse(scr, sessions, ui):
    """Returns ("go", session_id, window_id), ("new",), ("switch",), ("kill", session_id),
    ("cancel",), or ("lost",) when the pane lost focus. ui keeps the cursor, the folds and a
    status line between calls."""
    folded = ui["folded"]
    fetches = ui["fetches"]
    redraw = True
    while True:
        lines = rows(sessions, folded)
        cursor = ui["cursor"] = max(0, min(ui["cursor"], len(lines) - 1))
        if lines[cursor][0] == "heading":
            cursor = ui["cursor"] = min(cursor + 1, len(lines) - 1)
        if redraw:
            draw(scr, sessions, folded, cursor, ui["status"])
            ui["status"] = ""
        redraw = True
        scr.timeout(40 if fetches else -1)  # wake up to add other hosts' sessions
        key = scr.getch()
        if key == -1:
            redraw = poll_fetches(fetches, sessions)
            continue
        if fetches:
            poll_fetches(fetches, sessions)
            lines = rows(sessions, folded)
        if key == 27:
            key = escape(scr)
            if key == FOCUS_IN:
                continue
            if key == FOCUS_OUT:
                return ("lost",)
        kind, si, ti = lines[cursor]
        s = sessions[si] if si is not None else None
        if key in (ord("j"), curses.KEY_DOWN, ord("k"), curses.KEY_UP):
            step = 1 if key in (ord("j"), curses.KEY_DOWN) else -1
            nxt = (cursor + step) % len(lines)
            while lines[nxt][0] == "heading" and nxt != cursor:
                nxt = (nxt + step) % len(lines)
            ui["cursor"] = nxt
        elif key in (ord("q"), 27):
            return ("cancel",)
        elif key == ord("n"):
            return ("new",)
        elif key == ord("H"):
            return ("switch",)
        elif key == ord("g"):
            ui["cursor"] = 0
        elif key == ord("G"):
            ui["cursor"] = len(lines) - 1
        elif ord("1") <= key <= ord("9"):
            n = key - ord("1")
            if n < len(sessions):
                return ("go", sessions[n]["id"], sessions[n]["active"])
        elif kind in ("empty", "heading"):
            pass
        elif key in (ord("h"), curses.KEY_LEFT):
            if kind == "tab":
                ui["cursor"] = lines.index(("session", si, None))
            else:
                folded.add(s["id"])
        elif key in (ord("l"), curses.KEY_RIGHT):
            folded.discard(s["id"])
        elif key in (ord("J"), ord("K")):
            ui["status"], row = reorder(sessions, s, kind, si, ti, 1 if key == ord("J") else -1)
            ui["cursor"] = rows(sessions, folded).index(row)
        elif key == ord("r"):
            ui["status"] = rename(scr, s, kind, ti)
        elif key == ord("x"):
            ui["status"], choice = kill(scr, sessions, s, kind, ti)
            if choice:
                return choice
        elif key in (10, 13, curses.KEY_ENTER):
            return ("go", s["id"], s["tabs"][ti]["id"] if kind == "tab" else s["active"])


def to_result(choice, orig, sessions):
    kind = choice[0]
    if kind == "go":
        _, session_id, window_id = choice
        if session_id == orig.get("id") and window_id == orig.get("active"):
            return {"type": "cancel"}  # already there: just put focus back
        result = {"type": "select", "session_id": session_id, "window_id": window_id or ""}
        host = next((s.get("host") for s in sessions if s["id"] == session_id), None)
        if host:
            result["host"] = host
        if session_id == orig.get("id"):
            # Another tab here: the watcher focuses its block on the server, no app needed
            tab = next((t for t in orig.get("tabs", []) if t["id"] == window_id), {})
            result["block_id"] = tab.get("block", "")
        return result
    if kind == "kill":
        return {"type": "kill", "session_id": choice[1]}
    return {"type": kind}  # cancel, lost, new, switch


def main():
    global curses
    # By content rather than position, so an init.lua from before this version (which put
    # the tree first) still works until the config is reloaded
    args = sys.argv[1:]
    client = next((a for a in args if a.startswith("client:")), "")
    sessions = json.loads(next((a for a in args if a.lstrip().startswith("[")), "[]"))
    others = json.loads(next((a for a in args if a.lstrip().startswith("{")), "{}"))
    hosts = [h for h in others.get("hosts") or [] if h and h != others.get("server")]
    orig = next((s for s in sessions if s.get("current")), {})
    try:
        if os.path.getsize(LOG) > 512 * 1024:
            os.truncate(LOG, 0)
    except OSError:
        pass

    watcher = Watcher(client, orig)  # before curses loads, so it connects sooner
    import curses as curses_module
    curses = curses_module
    log(f"--- v{VERSION} client={client} session={orig.get('id', '')} "
        f"block={orig.get('block', '')} zoomed={bool(orig.get('zoomed'))}")

    # Rex closing this pane (the watcher does, once it has the choice) sends SIGHUP
    def leave(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGHUP, leave)
    signal.signal(signal.SIGTERM, leave)

    os.environ.setdefault("ESCDELAY", "10")  # escape alone closes; sequences arrive whole

    def picker(scr):
        nonlocal watcher
        ui = {"cursor": 0, "folded": set(), "status": "", "fetches": []}
        start_ui(scr, sessions, ui)
        draw(scr, sessions, ui["folded"], ui["cursor"])
        # Other hosts only now, so starting them doesn't slow the first draw
        ui["fetches"] = [f for f in map(spawn_fetch, hosts) if f]
        while True:
            try:
                choice = browse(scr, sessions, ui)
            except FocusLost:
                choice = ("lost",)
            refused = watcher.hand_over(scr, to_result(choice, orig, sessions))
            if refused is None:
                return
            log(f"refused: {refused}")
            ui["status"] = refused
            watcher = Watcher(watcher.client, orig)

    try:
        curses.wrapper(picker)
    except SystemExit:
        raise
    except Exception as e:  # never leave the watcher waiting for a choice that won't come
        log(f"picker failed: {e!r}")
        if not os.path.exists(watcher.tmp):
            watcher.hand_over(None, {"type": "cancel"})


if __name__ == "__main__":
    main()
