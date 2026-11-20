-- Migrated from ~/.tmux.conf (prefix ctrl+b), plus tmux's own default bindings

-- Let programs that use the prefix themselves still receive it
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- Repeat mode stands in for tmux's bind -r: a repeatable binding enters it, and its keys
-- then work without the prefix until enter or escape (Rex has no repeat-time timeout)
rex.mode("repeat", { exclusive = true })
rex.bind("ctrl+b>ctrl+r", "client.mode.enter", { name = "repeat" })
rex.bind("repeat/enter", "client.mode.exit")
rex.bind("repeat/escape", "client.mode.exit")

rex.action{
  name = "tmux_resize_repeat",
  title = "Resize Pane and Repeat",
  args = { direction = "string", amount = "number" },
  run = function(ctx, args)
    rex.client.queue("pane.resize", { direction = args.direction, amount = args.amount })
    rex.client.queue("client.mode.enter", { name = "repeat" })
  end,
}

rex.action{
  name = "tmux_focus_repeat",
  title = "Focus Pane and Repeat",
  args = { direction = "string" },
  run = function(ctx, args)
    rex.client.queue("pane.focus", { direction = args.direction })
    rex.client.queue("client.mode.enter", { name = "repeat" })
  end,
}

rex.action{
  name = "tmux_copy_mode_page_up",
  title = "Copy Mode, Page Up",
  run = function(ctx, args)
    rex.client.queue("pane.copy_mode.enter", {})
    rex.client.queue("pane.copy_mode.move", { to = "page_up" })
  end,
}

-- Pane focus (~/.tmux.conf:23-26)
rex.bind("ctrl+b>h", "pane.focus", { direction = "left" })
rex.bind("ctrl+b>j", "pane.focus", { direction = "down" })
rex.bind("ctrl+b>k", "pane.focus", { direction = "up" })
rex.bind("ctrl+b>l", "pane.focus", { direction = "right" })

-- Pane resize (~/.tmux.conf:29-32, bind -r)
rex.bind("ctrl+b>ctrl+h", "tmux_resize_repeat", { amount = 4, direction = "left" })
rex.bind("ctrl+b>ctrl+j", "tmux_resize_repeat", { amount = 2, direction = "down" })
rex.bind("ctrl+b>ctrl+k", "tmux_resize_repeat", { amount = 2, direction = "up" })
rex.bind("ctrl+b>ctrl+l", "tmux_resize_repeat", { amount = 4, direction = "right" })
rex.bind("repeat/ctrl+h", "pane.resize", { amount = 4, direction = "left" })
rex.bind("repeat/ctrl+j", "pane.resize", { amount = 2, direction = "down" })
rex.bind("repeat/ctrl+k", "pane.resize", { amount = 2, direction = "up" })
rex.bind("repeat/ctrl+l", "pane.resize", { amount = 4, direction = "right" })

-- Tabs (~/.tmux.conf:35-36)
rex.bind("ctrl+b>ctrl+p", "client.tab.previous")
rex.bind("ctrl+b>ctrl+n", "client.tab.next")

-- Splits (~/.tmux.conf:41-42)
rex.bind("ctrl+b>v", "pane.split", { direction = "right" })
rex.bind("ctrl+b>x", "pane.split", { direction = "down" })

-- Swap pane with its neighbour (~/.tmux.conf:48-51)
rex.bind("ctrl+b>shift+h", "pane.move", { direction = "left" })
rex.bind("ctrl+b>shift+j", "pane.move", { direction = "down" })
rex.bind("ctrl+b>shift+k", "pane.move", { direction = "up" })
rex.bind("ctrl+b>shift+l", "pane.move", { direction = "right" })

-- New tab (~/.tmux.conf:63); Rex opens it in the current pane's directory
rex.bind("ctrl+b>c", "client.tab.new")

-- SSH into a new tab named after the host (~/.tmux.conf:66)
rex.action{
  name = "tmux_ssh",
  title = "ssh",
  run = function(ctx, args)
    local host = rex.ui.input{ title = "ssh:", placeholder = "host", confirm = "Connect" }
    if host == nil or host == "" then
      return
    end
    rex.session.new_window{
      window_label = host,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        label = host,
        options = { command = { "ssh", host } },
      },
    }
  end,
}
rex.bind("ctrl+b>shift+s", "tmux_ssh")

-- Move the tab left or right, repeatable (~/.tmux.conf:54-55)
rex.action{
  name = "tmux_tab_move_repeat",
  title = "Move Tab and Repeat",
  args = { direction = "string" },
  run = function(ctx, args)
    rex.client.queue("client.tab.move", { direction = args.direction })
    rex.client.queue("client.mode.enter", { name = "repeat" })
  end,
}
rex.bind("ctrl+b>shift+,", "tmux_tab_move_repeat", { direction = "backward" })
rex.bind("ctrl+b>shift+.", "tmux_tab_move_repeat", { direction = "forward" })
rex.bind("repeat/shift+,", "client.tab.move", { direction = "backward" })
rex.bind("repeat/shift+.", "client.tab.move", { direction = "forward" })

-- Join pane (~/.tmux.conf:60): Rex moves this pane into a tab you pick, so after C-b !
-- go to the broken-out tab and press C-b @ to send it back
rex.bind("ctrl+b>shift+2", "pane.move_to_tab")

-- Reload config (~/.tmux.conf:69)
rex.bind("ctrl+b>r", "client.config.reload")

-- tmux defaults: sessions
rex.bind("ctrl+b>s", "session.switch")
-- choose-tree (C-b w): every session with its tabs underneath, in a floating pane run by
-- choose-tree.py so it takes vim keys (j/k move, h/l fold, enter goes, q closes).
-- find-window (C-b f): the same tree in Rex's picker, to filter by typing.
-- Unnamed tabs show their program and folder.
local function tab_name(session_id, window, index)
  if window.label and not window.label:match("^Window %x+$") then
    return window.label
  end
  local ok, proc = pcall(rex.block.call, "com.superlogical.terminal", "process",
    { session_id = session_id, block_id = window.focused_block_id })
  local fg = ok and proc and proc.foreground
  if not fg then
    return "tab " .. index
  end
  local dir = (fg.cwd or ""):match("([^/]+)/?$") or "~"
  if fg.cwd == os.getenv("HOME") then
    dir = "~"
  end
  return fg.name .. " · " .. dir
end

-- Every session, with its tabs: { id, label, current, active, tabs = { { id, name } } }.
-- An action runs as the app, so this never detaches: that would cut the app off from the
-- session, and switching back to it then fails with status 409.
local function session_tree(ctx)
  local tree = {}
  local list = rex.call("session.list")
  for _, s in ipairs(list and list.sessions or {}) do
    local attached = rex.call("session.attach", { session_id = s.session_id })
    local view = attached and attached.view
    if view then
      local here = s.session_id == ctx.session_id
      local tabs = {}
      for i, w in ipairs(view.windows) do
        tabs[#tabs + 1] = { id = w.window_id, name = tab_name(s.session_id, w, i) }
      end
      tree[#tree + 1] = {
        id = s.session_id,
        label = s.label,
        current = here,
        active = view.active_window_id or "",
        tabs = tabs,
      }
    end
  end
  return tree
end

rex.action{
  name = "tmux_choose_tree",
  title = "choose-tree",
  run = function(ctx, args)
    local script = os.getenv("HOME") .. "/.config/rex/choose-tree.py"
    rex.session.new_layer{
      bounds = { 0.2, 0.15, 0.6, 0.6 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        label = "choose-tree",
        options = {
          shell = "none",
          login = false,
          command = { "/usr/bin/python3", script, rex.json.encode(session_tree(ctx)), ctx.client_id },
        },
      },
    }
  end,
}
rex.bind("ctrl+b>w", "tmux_choose_tree")

rex.action{
  name = "tmux_find_window",
  title = "find-window",
  run = function(ctx, args)
    local items = {}
    for _, s in ipairs(session_tree(ctx)) do
      -- the session's row goes to its active tab; " session" keeps its id apart from that tab's
      items[#items + 1] = { id = s.id .. " " .. s.active .. " session", title = s.label, icon = s.current and "star" or "folder" }
      for i, tab in ipairs(s.tabs) do
        items[#items + 1] = {
          id = s.id .. " " .. tab.id,
          title = "  " .. i .. " " .. tab.name .. (tab.id == s.active and " *" or ""),
        }
      end
    end
    local choice = rex.ui.pick{ title = "find-window", placeholder = "Filter sessions and tabs", items = items }
    if not choice then
      return
    end
    local session_id, window_id = choice:match("^(%S+) ?(%S*)")
    if window_id == "" then
      window_id = nil
    end
    rex.client.queue("session.select", { session_id = session_id, window_id = window_id })
  end,
}
rex.bind("ctrl+b>f", "tmux_find_window")
rex.bind("ctrl+b>shift+4", "session.rename")
rex.bind("ctrl+b>shift+9", "session.previous")
rex.bind("ctrl+b>shift+0", "session.next")

-- Sessions mode (C-b C-s): j/k go down and up the sessions, h/l through the session's
-- tabs, r renames the session, enter or escape leaves
rex.action{
  name = "sessions_rename",
  title = "Rename Session and Leave Sessions Mode",
  run = function(ctx, args)
    rex.client.queue("client.mode.exit", {})
    rex.client.queue("session.rename", {})
  end,
}
rex.mode("sessions", { exclusive = true })
rex.bind("ctrl+b>ctrl+s", "client.mode.enter", { name = "sessions" })
rex.bind("sessions/j", "session.next")
rex.bind("sessions/k", "session.previous")
rex.bind("sessions/h", "client.tab.previous")
rex.bind("sessions/l", "client.tab.next")
rex.bind("sessions/r", "sessions_rename")
rex.bind("sessions/enter", "client.mode.exit")
rex.bind("sessions/escape", "client.mode.exit")

-- tmux defaults: windows (Rex tabs); base-index is 1
rex.bind("ctrl+b>n", "client.tab.next")
rex.bind("ctrl+b>p", "client.tab.previous")
rex.bind("ctrl+b>,", "client.tab.rename")
rex.bind("ctrl+b>shift+7", "client.tab.close")
for i = 1, 9 do
  rex.bind("ctrl+b>" .. i, "client.tab.goto", { index = i })
end

-- tmux defaults: panes
rex.bind("ctrl+b>o", "pane.focus_next")
rex.bind("ctrl+b>;", "pane.focus_back.in_tab")
rex.bind("ctrl+b>z", "pane.zoom")
rex.bind("ctrl+b>shift+1", "pane.move_to_new_tab")
rex.bind("ctrl+b>shift+e", "pane.balance")

-- tmux defaults: repeatable focus and resize (bind -r)
for _, d in ipairs({ "left", "right", "up", "down" }) do
  rex.bind("ctrl+b>" .. d, "tmux_focus_repeat", { direction = d })
  rex.bind("repeat/" .. d, "pane.focus", { direction = d })
  rex.bind("ctrl+b>ctrl+" .. d, "tmux_resize_repeat", { amount = 1, direction = d })
  rex.bind("repeat/ctrl+" .. d, "pane.resize", { amount = 1, direction = d })
  rex.bind("ctrl+b>alt+" .. d, "tmux_resize_repeat", { amount = 5, direction = d })
  rex.bind("repeat/alt+" .. d, "pane.resize", { amount = 5, direction = d })
end

-- tmux defaults: copy mode and paste
rex.bind("ctrl+b>[", "pane.copy_mode.enter")
rex.bind("ctrl+b>pageup", "tmux_copy_mode_page_up")
rex.bind("ctrl+b>]", "pane.paste")

-- tmux's command prompt (C-b :): the closest Rex has is the command palette
rex.bind("ctrl+b>shift+;", "client.palette.toggle")

-- tmux command names for the palette: tmux's windows are Rex tabs, so new-window opens a
-- tab, not a macOS window (Rex's "New Window")
rex.action{
  name = "tmux_new_window",
  title = "new-window",
  run = function(ctx, args)
    rex.client.queue("client.tab.new", {})
  end,
}

rex.action{
  name = "tmux_new_session",
  title = "new-session",
  run = function(ctx, args)
    rex.client.queue("session.new", {})
  end,
}

rex.action{
  name = "tmux_kill_session",
  title = "kill-session",
  run = function(ctx, args)
    rex.client.queue("session.close", {})
  end,
}
rex.bind("ctrl+b>shift+x", "tmux_kill_session")

rex.action{
  name = "tmux_kill_window",
  title = "kill-window",
  run = function(ctx, args)
    rex.client.queue("client.tab.close", {})
  end,
}

-- Per-OS settings from ~/.config/rex/local.lua, which the dotfiles keep in an OS layer
-- (common@macos sets Homebrew's fish). Without one, nothing OS-specific is set.
local machine = {}
do
  local path = os.getenv("HOME") .. "/.config/rex/local.lua"
  local f = io.open(path, "r")
  if f then
    f:close()
    machine = dofile(path) or {}
  end
end

-- One-off setup for settings init.lua cannot hold: run "apply-my-settings" from the
-- command palette (C-b :) on a new machine. The theme file and shell are paths on this
-- server's machine, which only the Mac app can use when the server is the Mac itself; a
-- Linux server starts the account's login shell, so set that with chsh there.
local function on_macos()
  local f = io.open("/System/Library/CoreServices/SystemVersion.plist", "r")
  if f then
    f:close()
    return true
  end
  return false
end

rex.action{
  name = "apply_my_settings",
  title = "apply-my-settings",
  run = function(ctx, args)
    if on_macos() then
      rex.client.queue("client.theme.import", { path = os.getenv("HOME") .. "/.config/rex/themes/Catppuccin Mocha" })
      if machine.fish then
        rex.client.queue("client.setting.terminal.shell.command", { value = machine.fish })
      end
    end
    rex.client.queue("client.setting.interface.toolbar.auto_hide_toolbar", { value = "always_show" })
    rex.client.queue("client.setting.developer.experimental.new_quick_switcher", { value = true })
    -- Text pinned to the bottom of each pane, so nvim's statusline sits on the edge, with
    -- the leftover strip in the program's background colour
    rex.client.queue("client.setting.developer.experimental.terminal_anchor", { value = "bottom" })
    rex.client.queue("client.setting.interface.pane_padding.color", { value = "always" })
  end,
}


-- C-b =: make the global font size match the focused pane's zoom (cmd+= / cmd+- zoom one
-- pane), so every pane that isn't zoomed on its own follows it. font-sync.py runs in the
-- background because each step waits for the app to redraw.
rex.action{
  name = "tmux_font_sync",
  title = "Sync Font Size to This Pane",
  run = function(ctx, args)
    local script = os.getenv("HOME") .. "/.config/rex/font-sync.py"
    rex.exec{ "/bin/sh", "-c", "nohup /usr/bin/python3 \"$0\" \"$1\" \"$2\" \"$3\" >/dev/null 2>&1 &",
      script, ctx.client_id, ctx.session_id, ctx.block_id }
  end,
}
rex.bind("ctrl+b>=", "tmux_font_sync")
