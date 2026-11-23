#!/usr/bin/env python3
"""tmux-style choose-tree for Rex, run in a floating pane by the tmux_choose_tree action.

argv: TREE_JSON CLIENT_ID
TREE_JSON is a list of sessions: {id, label, current, active, tabs: [{id, name}]}.

The top row makes a new session. j/k or arrows move, wrapping round at either end, h/l
or left/right fold and unfold a session, g/G go to the top or bottom, J/K move the session
or tab down or up the order, r renames it, x kills it after a y/n check, enter goes to it,
q or escape closes. It also closes when its pane loses focus, as tmux's tree does.
"""
import curses
import json
import os
import subprocess
import sys

REX = os.path.join(os.environ["REX_BIN_DIR"], "rex") if os.environ.get("REX_BIN_DIR") else "rex"


FOCUS_IN, FOCUS_OUT = "focus_in", "focus_out"


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


NEW = ("new", None, None)


def rows(sessions, folded):
    out = [NEW]
    group = None
    for si, s in enumerate(sessions):
        host = s.get("host") or ""
        if host != group:
            group = host
            out.append(("heading", None, host or "local"))
        out.append(("session", si, None))
        if s["id"] not in folded:
            for ti in range(len(s["tabs"])):
                out.append(("tab", si, ti))
    return out


def draw(scr, sessions, folded, cursor, status=""):
    scr.erase()
    height, width = scr.getmaxyx()
    lines = rows(sessions, folded)
    top = max(0, cursor - height + 2)
    for y, (kind, si, ti) in enumerate(lines[top:top + height - 1]):
        s = sessions[si] if si is not None else None
        if kind == "new":
            text = "+ new session"
            attr = curses.A_DIM
        elif kind == "heading":
            text = f"── {ti} " + "─" * max(0, width - len(ti) - 5)
            attr = curses.A_DIM
        elif kind == "session":
            mark = "+" if s["id"] in folded else "-"
            count = len(s["tabs"])
            text = f"{mark} {s['label']}: {count} tab{'' if count == 1 else 's'}"
            if s["current"]:
                text += " (attached)"
            attr = curses.A_BOLD
        else:
            tab = s["tabs"][ti]
            branch = "└─>" if ti == len(s["tabs"]) - 1 else "├─>"
            text = f"  {branch} {ti + 1}: {tab['name']}"
            if tab["id"] == s["active"]:
                text += "*"
            attr = curses.A_NORMAL
        if top + y == cursor:
            attr |= curses.A_REVERSE
        scr.addnstr(y, 0, text.ljust(width - 1), width - 1, attr)
    footer = status or "j/k move  J/K reorder  h/l fold  r rename  x kill  enter go  q quit"
    scr.addnstr(height - 1, 0, footer, width - 1, curses.A_DIM)
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


def rename(scr, s, kind, ti):
    if kind == "session":
        label = prompt(scr, "rename session:", s["label"])
        if label and label != s["label"]:
            if subprocess.run([REX, "session", "rename", s["id"], label],
                              capture_output=True).returncode == 0:
                s["label"] = label
                return ""
            return "rename failed"
    else:
        tab = s["tabs"][ti]
        label = prompt(scr, "rename tab:", tab["name"])
        if label and label != tab["name"]:
            if subprocess.run([REX, "window", "rename", "-s", s["id"], tab["id"], label],
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
    """Swap the session or tab with its neighbour (step 1 is down, -1 up), stopping at
    either end. Returns (status, row) with the row it has moved to."""
    if kind == "session":
        items, i, cmd = sessions, si, [REX, "session", "move"]
    else:
        items, i, cmd = s["tabs"], ti, [REX, "window", "move", "-s", s["id"]]
    row = (kind, si, ti)
    other = i + step
    if not 0 <= other < len(items):
        return "", row
    if kind == "session" and items[other].get("host") != items[i].get("host"):
        return "", row  # sessions stay within their host's group
    where = "--after" if step > 0 else "--before"
    if subprocess.run(cmd + [items[i]["id"], where, items[other]["id"]],
                      capture_output=True).returncode:
        return "move failed", row
    items[i], items[other] = items[other], items[i]
    return "", (kind, other, None) if kind == "session" else (kind, si, other)


def kill(scr, sessions, s, kind, ti):
    """Kill a session or tab, as tmux's choose-tree x does. Returns (status, quit)."""
    if kind == "session":
        if not confirm(scr, f"kill session {s['label']}?"):
            return "", False
        # Killing the session this pane is in ends this pane too, so the caller does it last
        if s["current"]:
            return ("kill", [REX, "session", "kill", s["id"]]), True
        if subprocess.run([REX, "session", "kill", s["id"]], capture_output=True).returncode:
            return "kill failed", False
        sessions.remove(s)
        return "", not sessions
    tab = s["tabs"][ti]
    if not confirm(scr, f"kill tab {tab['name']}?"):
        return "", False
    if s["current"] and len(s["tabs"]) == 1:
        return ("kill", [REX, "session", "kill", s["id"]]), True
    if subprocess.run([REX, "window", "close", "-s", s["id"], tab["id"]],
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
    os.write(sys.stdout.fileno(), b"\x1b[?1004h")  # report focus changes
    folded = set()
    lines = rows(sessions, folded)
    cursor = 0
    for i, (kind, si, ti) in enumerate(lines):
        if kind == "session" and sessions[si]["current"]:
            cursor = i  # fallback: the current session's row
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
        elif key == ord("g"):
            cursor = 0
        elif key == ord("G"):
            cursor = len(lines) - 1
        elif kind == "heading":
            pass
        elif kind == "new":
            if key in (10, 13, curses.KEY_ENTER):
                return ("new",)
        elif key in (ord("h"), curses.KEY_LEFT):
            if kind == "tab":
                cursor = lines.index(("session", si, None))
            else:
                folded.add(s["id"])
        elif key in (ord("l"), curses.KEY_RIGHT):
            folded.discard(s["id"])
        elif s and s.get("host") and key in (ord("J"), ord("K"), ord("r"), ord("x"), 10, 13, curses.KEY_ENTER):
            status = f"remote session on {s['host']}: view only for now"
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
            return s["id"], window


def main():
    sessions = json.loads(sys.argv[1])
    client = sys.argv[2]
    os.environ.setdefault("ESCDELAY", "25")
    choice = curses.wrapper(choose, sessions)

    # Close this pane, then switch. A helper in its own process session does both, since
    # closing the pane ends this process.
    commands = []
    block, session = os.environ.get("REX_BLOCK"), os.environ.get("REX_SESSION")
    if block and session:
        commands.append([REX, "block", "close", "-s", session, block])
    if choice and choice[0] == "kill":
        commands.append(choice[1])
    elif choice and choice[0] == "new":
        commands.append([REX, "-C", client, "do", "session.new"])
    elif choice:
        session_id, window_id = choice
        commands.append([REX, "-C", client, "do", "session.select",
                         f"session_id={session_id}", f"window_id={window_id}"])
    script = " ; ".join(" ".join(f"'{part}'" for part in cmd) for cmd in commands)
    subprocess.Popen(["/bin/sh", "-c", script], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
