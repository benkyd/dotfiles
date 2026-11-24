#!/usr/bin/env python3
"""tmux-style choose-tree for Rex, run in a floating pane by the tmux_choose_tree action.

argv: TREE_JSON CLIENT_ID
TREE_JSON is a list of sessions: {id, label, current, active, tabs: [{id, name}]}.

n makes a new session and H opens the switch-host dialog. j/k or arrows move, wrapping round at either end, h/l
or left/right fold and unfold a session, g/G go to the top or bottom, J/K move the session
or tab down or up the order, r renames it, x kills it after a y/n check, enter goes to it,
q or escape closes. It also closes when its pane loses focus, as tmux's tree does.
"""
import curses
import json
import os
import subprocess
import sys
import tempfile

REX = os.path.join(os.environ["REX_BIN_DIR"], "rex") if os.environ.get("REX_BIN_DIR") else "rex"

# Color pair indices (initialised in browse())
C_SESSION  = 1  # cyan   – session rows
C_ACTIVE   = 2  # green  – active tab
C_HERE     = 3  # yellow – attached/current session
C_HEADING  = 4  # blue   – host-group headings


def rx(s):
    return [REX, "-S", s["host"]] if s.get("host") else [REX]


FOCUS_IN, FOCUS_OUT = "focus_in", "focus_out"


def escape(scr):
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
    attached = any(s.get("at") for s in sessions)
    multi = attached or len({s.get("host") or "" for s in sessions}) > 1
    group = None
    for si, s in enumerate(sessions):
        host = s.get("host") or ""
        if multi and host != group:
            out.append(("heading", None, host or s.get("at") or "local"))
        group = host
        out.append(("session", si, None))
        if s["id"] not in folded:
            for ti in range(len(s["tabs"])):
                out.append(("tab", si, ti))
    if attached:
        out.append(("heading", None, "home"))
        out.append(("back", None, None))
    return out or [("empty", None, None)]


def draw(scr, sessions, folded, cursor, status=""):
    scr.erase()
    height, width = scr.getmaxyx()
    lines = rows(sessions, folded)
    top = max(0, cursor - height + 2)
    for y, (kind, si, ti) in enumerate(lines[top:top + height - 1]):
        s = sessions[si] if si is not None else None
        if kind == "empty":
            text = "no sessions: n makes one"
            attr = curses.A_DIM
        elif kind == "heading":
            text = f"── {ti} " + "─" * max(0, width - len(ti) - 5)
            attr = curses.color_pair(C_HEADING) | curses.A_DIM
        elif kind == "back":
            text = "⇄ switch host…"
            attr = curses.A_DIM
        elif kind == "session":
            mark = "+" if s["id"] in folded else "-"
            count = len(s["tabs"])
            n = next(i + 1 for i, sess in enumerate(sessions) if sess["id"] == s["id"])
            active_name = next((t["name"] for t in s["tabs"] if t["id"] == s["active"]), "")
            text = f"{mark} {n}: {s['label']}  · {active_name} ({count})"
            if s["current"]:
                text += " (attached)"
                attr = curses.color_pair(C_HERE) | curses.A_BOLD
            else:
                attr = curses.color_pair(C_SESSION) | curses.A_BOLD
        else:
            tab = s["tabs"][ti]
            branch = "└─>" if ti == len(s["tabs"]) - 1 else "├─>"
            text = f"  {branch} {ti + 1}: {tab['name']}"
            if tab["id"] == s["active"]:
                text += " ●"
                attr = curses.color_pair(C_ACTIVE)
            else:
                attr = curses.A_NORMAL
        if top + y == cursor:
            attr |= curses.A_REVERSE
        scr.addnstr(y, 0, text.ljust(width - 1), width - 1, attr)
    footer = status or "j/k move  1-9 session  J/K reorder  h/l fold  r rename  x kill  n new  H host  enter go  q quit"
    scr.addnstr(height - 1, 0, footer, width - 1, curses.A_DIM)
    scr.refresh()


class FocusLost(Exception):
    pass


def prompt(scr, label, value):
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
            elif key == "\x15":
                text = ""
            elif key == "\x17":
                text = text.rstrip().rpartition(" ")[0]
            elif isinstance(key, str) and key.isprintable():
                text += key
    finally:
        curses.curs_set(0)


def rename(scr, s, kind, ti):
    if kind == "session":
        label = prompt(scr, "rename session:", s["label"])
        if label and label != s["label"]:
            if subprocess.run(rx(s) + ["session", "rename", s["id"], label],
                              capture_output=True).returncode == 0:
                s["label"] = label
                return ""
            return "rename failed"
    else:
        tab = s["tabs"][ti]
        label = prompt(scr, "rename tab:", tab["name"])
        if label and label != tab["name"]:
            if subprocess.run(rx(s) + ["window", "rename", "-s", s["id"], tab["id"], label],
                              capture_output=True).returncode == 0:
                tab["name"] = label
                return ""
            return "rename failed"
    return ""


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


def reorder(sessions, s, kind, si, ti, step):
    if kind == "session":
        items, i, cmd = sessions, si, rx(s) + ["session", "move"]
    else:
        items, i, cmd = s["tabs"], ti, rx(s) + ["window", "move", "-s", s["id"]]
    row = (kind, si, ti)
    other = i + step
    if not 0 <= other < len(items):
        return "", row
    if kind == "session" and items[other].get("host") != items[i].get("host"):
        return "", row
    where = "--after" if step > 0 else "--before"
    if subprocess.run(cmd + [items[i]["id"], where, items[other]["id"]],
                      capture_output=True).returncode:
        return "move failed", row
    items[i], items[other] = items[other], items[i]
    return "", (kind, other, None) if kind == "session" else (kind, si, other)


def kill(scr, sessions, s, kind, ti):
    if kind == "session":
        if not confirm(scr, f"kill session {s['label']}?"):
            return "", False
        if s["current"]:
            return ("kill", [REX, "session", "kill", s["id"]]), True
        if subprocess.run(rx(s) + ["session", "kill", s["id"]], capture_output=True).returncode:
            return "kill failed", False
        sessions.remove(s)
        return "", not sessions
    tab = s["tabs"][ti]
    if not confirm(scr, f"kill tab {tab['name']}?"):
        return "", False
    if s["current"] and len(s["tabs"]) == 1:
        return ("kill", [REX, "session", "kill", s["id"]]), True
    if subprocess.run(rx(s) + ["window", "close", "-s", s["id"], tab["id"]],
                      capture_output=True).returncode:
        return "kill failed", False
    s["tabs"].pop(ti)
    if not s["tabs"]:
        sessions.remove(s)
    elif tab["id"] == s["active"]:
        s["active"] = s["tabs"][0]["id"]
    return "", not sessions


def choose(scr, sessions):
    try:
        return browse(scr, sessions)
    except FocusLost:
        return None


def browse(scr, sessions):
    curses.curs_set(0)
    curses.use_default_colors()
    if curses.has_colors():
        curses.start_color()
        curses.init_pair(C_SESSION, curses.COLOR_CYAN,   -1)
        curses.init_pair(C_ACTIVE,  curses.COLOR_GREEN,  -1)
        curses.init_pair(C_HERE,    curses.COLOR_YELLOW, -1)
        curses.init_pair(C_HEADING, curses.COLOR_BLUE,   -1)
    os.write(sys.stdout.fileno(), b"\x1b[?1004h")
    folded = set()
    lines = rows(sessions, folded)
    cursor = 0
    for i, (kind, si, ti) in enumerate(lines):
        if kind == "session" and sessions[si]["current"]:
            cursor = i
        elif kind == "tab":
            s = sessions[si]
            if s["current"] and s["tabs"][ti]["id"] == s["active"]:
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
                return None
        kind, si, ti = lines[cursor]
        s = sessions[si] if si is not None else None
        if key in (ord("j"), curses.KEY_DOWN):
            cursor = (cursor + 1) % len(lines)
        elif key in (ord("k"), curses.KEY_UP):
            cursor = (cursor - 1) % len(lines)
        elif key in (ord("q"), 27):
            return None
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
                sv = sessions[n]
                return sv["id"], sv["active"], sv.get("host"), sv["active"]
        elif kind in ("empty", "heading"):
            pass
        elif kind == "back":
            if key in (10, 13, curses.KEY_ENTER):
                return ("switch",)
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
            status, done = kill(scr, sessions, s, kind, ti)
            if done:
                return status if isinstance(status, tuple) else None
            if isinstance(status, tuple):
                status = ""
        elif key in (10, 13, curses.KEY_ENTER):
            window = s["tabs"][ti]["id"] if kind == "tab" else s["active"]
            return s["id"], window, s.get("host"), s["active"]


def _start_watcher(client):
    """Start the choice watcher as a background rex do script. Returns the tmp file path."""
    tmp = tempfile.mktemp(suffix=".json", prefix="rex-ct-")
    watcher = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "choose-tree-watcher.lua")
    args = json.dumps({"tmp": tmp, "rex": REX, "client": client})
    subprocess.Popen(
        [REX, "-C", client, "do", watcher, "--args", args],
        start_new_session=True,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return tmp


def _write_choice(tmp, result, orig):
    if orig and orig.get("was_zoomed"):
        result["was_zoomed"] = True
    with open(tmp, "w") as f:
        json.dump(result, f)


def main():
    if sys.argv[1] == "--go":
        # find-window's way to a remote row
        host, session_id, window_id, active, client = sys.argv[2:7]
        tmp = _start_watcher(client)
        _write_choice(tmp, {
            "type": "select",
            "session_id": session_id,
            "window_id": window_id,
            "host": host or "",
        }, None)
        return

    sessions = json.loads(sys.argv[1])
    client = sys.argv[2]
    os.environ.setdefault("ESCDELAY", "25")

    orig = next((s for s in sessions if s.get("current")), None)

    # Start watcher before the TUI so it's ready when the user picks
    tmp = _start_watcher(client)

    choice = curses.wrapper(choose, sessions)

    # Build the result dict — watcher does all rex calls in app context
    if choice and choice[0] == "switch":
        result = {"type": "switch"}
    elif choice and choice[0] == "new":
        result = {"type": "new"}
    elif choice and choice[0] == "kill":
        result = {"type": "kill", "cmd": list(choice[1])}
    elif choice:
        sid, wid, host, active = choice
        result = {"type": "select", "session_id": sid,
                  "window_id": wid or "", "host": host or ""}
    elif orig:
        # Cancel: restore original focus
        result = {"type": "select", "session_id": orig["id"],
                  "window_id": orig.get("active", ""), "host": ""}
    else:
        result = {}

    _write_choice(tmp, result, orig)
    # Python exits here → Rex auto-closes the pane


if __name__ == "__main__":
    main()
