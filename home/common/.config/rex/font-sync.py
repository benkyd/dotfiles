#!/usr/bin/env python3
"""Make Rex's global font size match the focused pane's zoom (C-b =).

argv: CLIENT_ID SESSION_ID BLOCK_ID [TARGET_CELL_HEIGHT_PX]

Rex keeps a pane's zoom in the app and offers no action that sets another pane's, so
this sets the global Terminal Font Size instead: every pane that isn't zoomed on its own
follows it. The focused pane's cell height says how big its text is; changing the global
size clears that pane's own zoom, so the size is adjusted until its cells are as tall as
they were. Run detached by the tmux_font_sync action, since each step waits for the app.
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse

HOME = os.path.expanduser("~")
REX_DIR = os.environ.get("REX_BIN_DIR") or os.path.join(
    HOME, "Library/Application Support/com.superlogical.rex/RexServer/Versions/Current",
    "Rex Server.app/Contents/MacOS")
REX = [os.path.join(REX_DIR, "rex"), "-S", os.environ.get("REX_SERVER") or "unix://" +
       urllib.parse.quote(os.path.join(HOME, "Library/Application Support/rex/server.sock"))]


def cell_height(session_id, block_id):
    out = subprocess.run(REX + ["block", "call", "-s", session_id, "-b", block_id, "size"],
                         capture_output=True, text=True)
    return json.loads(out.stdout)["cell_height_px"]


def global_size():
    out = subprocess.run(["defaults", "read", "com.superlogical.rex",
                          "Workspace.terminalFontPointSize"], capture_output=True, text=True)
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 12.0


def set_global(client, size):
    subprocess.run(REX + ["-C", client, "do", "client.setting.terminal.typography.size",
                          f"value={size:g}"], capture_output=True)


def settle(session_id, block_id, before):
    """Wait for the app to lay the pane out again after a size change."""
    for _ in range(20):
        time.sleep(0.1)
        now = cell_height(session_id, block_id)
        if now != before:
            return now
    return cell_height(session_id, block_id)


def main():
    client, session_id, block_id = sys.argv[1:4]
    target = int(sys.argv[4]) if len(sys.argv) > 4 else cell_height(session_id, block_id)
    size = global_size()
    height = cell_height(session_id, block_id)
    tried = set()
    for _ in range(6):
        # cell height grows with the point size; the setting moves in 0.5pt steps
        size = round(size * target / height * 2) / 2
        if size in tried:
            break
        tried.add(size)
        set_global(client, size)
        height = settle(session_id, block_id, height)
        if height == target:
            break
    print(f"global font size {size:g}pt, cells {height}px (target {target}px)")


if __name__ == "__main__":
    main()
