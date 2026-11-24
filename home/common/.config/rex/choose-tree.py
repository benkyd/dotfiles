#!/usr/bin/env python3
"""tmux-style choose-tree for Rex, run in a floating pane by init.lua's tmux_choose_tree.

argv: CLIENT_ID TREE_JSON, in either order
TREE_JSON lists this server's sessions: {id, label, current, active, tabs: [{id, name}]}.
The current session also has block, the block that had focus, and zoomed, whether its
window was zoomed.

Keys: j/k or arrows move (wrapping round), 1-9 go straight to that session, enter goes to
the row, h/l fold and unfold, g/G top and bottom, J/K reorder, r rename, x kill (y/n),
n new session, H switch host, q or escape close. Losing focus closes it, as tmux's does.

The switch itself is done by choose-tree-watcher.lua, a `rex do` script started here
before the tree is drawn, so it's connected by the time a choice is made. Its
rex.client.queue reaches the app the way a key binding does, so Remote Control isn't
needed. This writes the choice to a file and keeps the tree on screen; the watcher closes
this pane, puts focus and zoom back on the block they were on, then switches.
"""
import curses
import json
import os
import signal
import sys
import time

VERSION = 8
WATCHER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "choose-tree-watcher.lua")
LOG = os.environ.get("REX_CHOOSE_TREE_LOG") or "/tmp/choose-tree-watcher.log"
REX = os.path.join(os.environ["REX_BIN_DIR"], "rex") if os.environ.get("REX_BIN_DIR") else "rex"

C_SESSION, C_ACTIVE, C_HERE = 1, 2, 3  # curses colour pairs: cyan, green, yellow
FOCUS_IN, FOCUS_OUT = "focus_in", "focus_out"
FOOTER = "j/k move  1-9 session  enter go  h/l fold  J/K order  r rename  x kill  n new  H host  q quit"


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} py: {msg}\n")
    except OSError:
        pass


def run(*argv):
    """Run a rex command that changes this server (rename, move, kill); True if it worked."""
    import subprocess  # only here: importing it costs startup time on every open
    r = subprocess.run([REX, *argv], capture_output=True, text=True)
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


def exited(pid):
    """None while the process runs, else its exit code."""
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        return 0
    return os.waitstatus_to_exitcode(status) if done else None


def hand_over(scr, tmp, result, pid, client, wargs):
    """Write the choice for the watcher, then wait for it to close this pane. The tree stays
    drawn meanwhile, so the switch looks like one step. A watcher that failed (as when this
    server doesn't know CLIENT_ID) is started again for the client found here."""
    part = tmp + ".part"
    with open(part, "w") as f:
        json.dump(result, f)
    os.replace(part, tmp)
    if scr is not None:
        height, width = scr.getmaxyx()
        scr.move(height - 1, 0)
        scr.clrtoeol()
        scr.addnstr(height - 1, 0, "…", width - 1, curses.A_DIM)
        scr.refresh()
    code = None if pid else 1
    retried = False
    taken = None
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if code is None and pid:
            code = exited(pid)  # reaped once, so keep the code
        if code == 0 or not os.path.exists(tmp):
            # The watcher has the choice. It closes this pane itself; if that doesn't
            # happen soon, leave, so the pane closes before it puts focus back
            taken = taken or time.monotonic()
            if time.monotonic() - taken > 0.1:
                return
        elif code is not None:
            if retried:
                return
            retried = True
            other = resolve_client(client)
            log(f"watcher exited {code}; client {client} -> {other}")
            if not other or other == client:
                return
            pid, code = spawn_watcher(other, wargs), None
            deadline = time.monotonic() + 2
        time.sleep(0.01)


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
    for si, s in enumerate(sessions):
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
    scr.addnstr(height - 1, 0, status or FOOTER, width - 1, curses.A_DIM)
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
            if not run("session", "rename", s["id"], label):
                return "rename failed"
            s["label"] = label
    else:
        tab = s["tabs"][ti]
        label = prompt(scr, "rename tab:", tab["name"])
        if label and label != tab["name"]:
            if not run("window", "rename", "-s", s["id"], tab["id"], label):
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
    where = "--after" if step > 0 else "--before"
    if not run(*cmd, items[i]["id"], where, items[other]["id"]):
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
        if not run("session", "kill", s["id"]):
            return "kill failed", None
        sessions.remove(s)
        return "", None if sessions else ("cancel",)
    tab = s["tabs"][ti]
    if not confirm(scr, f"kill tab {tab['name']}?"):
        return "", None
    if s["current"] and len(s["tabs"]) == 1:
        return "", ("kill", s["id"])
    if not run("window", "close", "-s", s["id"], tab["id"]):
        return "kill failed", None
    s["tabs"].pop(ti)
    if not s["tabs"]:
        sessions.remove(s)
    elif tab["id"] == s["active"]:
        s["active"] = s["tabs"][0]["id"]
    return "", None if sessions else ("cancel",)


def browse(scr, sessions):
    """Returns ("go", session_id, window_id), ("new",), ("switch",), ("kill", session_id),
    ("cancel",), or ("lost",) when the pane lost focus."""
    curses.curs_set(0)
    curses.use_default_colors()
    if curses.has_colors():
        curses.init_pair(C_SESSION, curses.COLOR_CYAN, -1)
        curses.init_pair(C_ACTIVE, curses.COLOR_GREEN, -1)
        curses.init_pair(C_HERE, curses.COLOR_YELLOW, -1)
    os.write(sys.stdout.fileno(), b"\x1b[?1004h")  # report focus changes
    folded = set()
    lines = rows(sessions, folded)
    cursor = 0
    for i, (kind, si, ti) in enumerate(lines):
        s = sessions[si] if si is not None else None
        if kind == "session" and s["current"]:
            cursor = i  # fallback: the current session's row
        elif kind == "tab" and s["current"] and s["tabs"][ti]["id"] == s["active"]:
            cursor = i
            break
    status = ""
    while True:
        lines = rows(sessions, folded)
        cursor = max(0, min(cursor, len(lines) - 1))
        draw(scr, sessions, folded, cursor, status)
        status = ""
        key = scr.getch()
        if key == 27:
            key = escape(scr)
            if key == FOCUS_IN:
                continue
            if key == FOCUS_OUT:
                return ("lost",)
        kind, si, ti = lines[cursor]
        s = sessions[si] if si is not None else None
        if key in (ord("j"), curses.KEY_DOWN):
            cursor = (cursor + 1) % len(lines)
        elif key in (ord("k"), curses.KEY_UP):
            cursor = (cursor - 1) % len(lines)
        elif key in (ord("q"), 27):
            return ("cancel",)
        elif key == ord("n"):
            return ("new",)
        elif key == ord("H"):
            return ("switch",)
        elif key == ord("g"):
            cursor = 0
        elif key == ord("G"):
            cursor = len(lines) - 1
        elif ord("1") <= key <= ord("9"):
            n = key - ord("1")
            if n < len(sessions):
                return ("go", sessions[n]["id"], sessions[n]["active"])
        elif kind == "empty":
            pass
        elif key in (ord("h"), curses.KEY_LEFT):
            if kind == "tab":
                cursor = lines.index(("session", si, None))
            else:
                folded.add(s["id"])
        elif key in (ord("l"), curses.KEY_RIGHT):
            folded.discard(s["id"])
        elif key in (ord("J"), ord("K")):
            status, row = reorder(sessions, s, kind, si, ti, 1 if key == ord("J") else -1)
            cursor = rows(sessions, folded).index(row)
        elif key == ord("r"):
            status = rename(scr, s, kind, ti)
        elif key == ord("x"):
            status, choice = kill(scr, sessions, s, kind, ti)
            if choice:
                return choice
        elif key in (10, 13, curses.KEY_ENTER):
            return ("go", s["id"], s["tabs"][ti]["id"] if kind == "tab" else s["active"])


def to_result(choice, orig):
    kind = choice[0]
    if kind == "go":
        _, session_id, window_id = choice
        if session_id == orig.get("id") and window_id == orig.get("active"):
            return {"type": "cancel"}  # already there: just put focus back
        return {"type": "select", "session_id": session_id, "window_id": window_id or ""}
    if kind == "kill":
        return {"type": "kill", "session_id": choice[1]}
    return {"type": kind}  # cancel, lost, new, switch


def main():
    # By content rather than position, so an init.lua from before this version (which put
    # the tree first) still works until the config is reloaded
    args = sys.argv[1:]
    client = next((a for a in args if a.startswith("client:")), "")
    sessions = json.loads(next((a for a in args if a.lstrip().startswith("[")), "[]"))
    orig = next((s for s in sessions if s.get("current")), {})
    tmp = f"/tmp/rex-ct-{os.getpid()}-{time.monotonic_ns()}.json"
    wargs = {
        "tmp": tmp,
        "rex": REX,
        "session_id": orig.get("id", ""),
        "window_id": orig.get("active", ""),
        "block_id": orig.get("block", ""),
        "zoomed": bool(orig.get("zoomed")),
        "picker_session": os.environ.get("REX_SESSION", ""),
        "picker_block": os.environ.get("REX_BLOCK", ""),
    }
    try:
        if os.path.getsize(LOG) > 512 * 1024:
            os.truncate(LOG, 0)
    except OSError:
        pass
    log(f"--- v{VERSION} client={client} session={wargs['session_id']} block={wargs['block_id']} zoomed={wargs['zoomed']}")
    pid = None
    try:
        pid = spawn_watcher(client, wargs)  # first, so it's connected before the tree is drawn
    except Exception as e:
        log(f"starting the watcher failed: {e!r}")

    # Rex closing this pane (the watcher does, once it has the choice) sends SIGHUP
    def leave(*_):
        raise SystemExit(0)
    signal.signal(signal.SIGHUP, leave)
    signal.signal(signal.SIGTERM, leave)

    os.environ.setdefault("ESCDELAY", "25")

    def picker(scr):
        try:
            choice = browse(scr, sessions)
        except FocusLost:
            choice = ("lost",)
        hand_over(scr, tmp, to_result(choice, orig), pid, client, wargs)

    try:
        curses.wrapper(picker)
    except SystemExit:
        raise
    except Exception as e:  # never leave the watcher waiting for a choice that won't come
        log(f"picker failed: {e!r}")
        if not os.path.exists(tmp):
            hand_over(None, tmp, {"type": "cancel"}, pid, client, wargs)


if __name__ == "__main__":
    main()
