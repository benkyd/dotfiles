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
rex.bind("ctrl+b>ctrl+h", "tmux_resize_repeat", { amount = 2, direction = "left" })
rex.bind("ctrl+b>ctrl+j", "tmux_resize_repeat", { amount = 2, direction = "down" })
rex.bind("ctrl+b>ctrl+k", "tmux_resize_repeat", { amount = 2, direction = "up" })
rex.bind("ctrl+b>ctrl+l", "tmux_resize_repeat", { amount = 2, direction = "right" })
rex.bind("repeat/ctrl+h", "pane.resize", { amount = 2, direction = "left" })
rex.bind("repeat/ctrl+j", "pane.resize", { amount = 2, direction = "down" })
rex.bind("repeat/ctrl+k", "pane.resize", { amount = 2, direction = "up" })
rex.bind("repeat/ctrl+l", "pane.resize", { amount = 2, direction = "right" })

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
-- choose-tree.py so it takes vim keys (j/k move, J/K reorder, h/l fold, enter goes, q
-- closes), with a new-session row on top.
-- find-window (C-b f): the same tree in Rex's picker, to filter by typing.
-- Tab name: use user-set label or fallback — skips block.call entirely for speed.
local function tab_name(window, index)
  if window.label and not window.label:match("^Window %x+$") then
    return window.label
  end
  return "tab " .. index
end

-- Every session, with its tabs. local_only=true skips remote hosts (choose-tree
-- filters them anyway; find-window passes false to include them).
local function session_tree(ctx, local_only)
  local tree = {}
  local list = rex.call("session.list")
  for _, s in ipairs(list and list.sessions or {}) do
    local ok, view = pcall(rex.call, "session.view", { session_id = s.session_id })
    if ok and view and view.windows then
      local here = s.session_id == ctx.session_id
      local focused_block = ""
      local was_zoomed = false
      local tabs = {}
      for i, w in ipairs(view.windows) do
        tabs[#tabs + 1] = { id = w.window_id, name = tab_name(w, i) }
        if w.window_id == (view.active_window_id or "") then
          focused_block = w.focused_block_id or ""
          was_zoomed = w.zoomed or false
        end
      end
      tree[#tree + 1] = {
        id = s.session_id,
        label = s.label,
        current = here,
        active = view.active_window_id or "",
        focused_block = focused_block,
        was_zoomed = was_zoomed,
        tabs = tabs,
      }
    end
  end

  if local_only then return tree end

  -- Remote hosts for find-window
  local seen = {}
  for _, t in ipairs(tree) do seen[t.id] = true end
  local ok_hosts, hosts = pcall(rex.servers)
  for _, label in ipairs(ok_hosts and hosts or {}) do
    pcall(function()
      local remote = rex.server(label)
      local rlist = remote.call("session.list")
      local here = false
      for _, s in ipairs(rlist and rlist.sessions or {}) do
        if seen[s.session_id] then here = true end
      end
      if here then
        for _, s in ipairs(rlist.sessions) do
          for _, t in ipairs(tree) do
            if t.id == s.session_id then t.at = label end
          end
        end
        return
      end
      for _, s in ipairs(rlist and rlist.sessions or {}) do
        local ok, view = pcall(remote.call, "session.view", { session_id = s.session_id })
        if ok and view and view.windows then
          local tabs = {}
          for i, w in ipairs(view.windows) do
            tabs[#tabs + 1] = { id = w.window_id, name = tab_name(w, i) }
          end
          tree[#tree + 1] = {
            id = s.session_id,
            label = s.label,
            host = label,
            current = false,
            active = view.active_window_id or "",
            tabs = tabs,
          }
        end
      end
    end)
  end
  return tree
end

-- choice file path set by tmux_choose_tree; read by the rex.on handler below
local _choose_tree_tmp = nil

-- Registered at load time (required). Fires on every block exit; processes the
-- choice only when our file is set and exists. Runs in app context so
-- rex.client.queue bypasses Remote Control entirely.
rex.on("block.exit", function(evt)
  if not _choose_tree_tmp then return end
  local tmp = _choose_tree_tmp
  local f = io.open(tmp, "r")
  if not f then return end
  _choose_tree_tmp = nil
  local data = f:read("*a"); f:close(); pcall(os.remove, tmp)
  local ok, c = pcall(rex.json.decode, data)
  if not (ok and c) then return end
  if c.type == "select" then
    local opts = { session_id = c.session_id }
    if c.window_id and c.window_id ~= "" then opts.window_id = c.window_id end
    rex.client.queue("session.select", opts)
  elseif c.type == "switch" then
    rex.client.queue("client.host.switch", {})
  elseif c.type == "new" then
    rex.client.queue("session.new", {})
  end
  if c.was_zoomed then rex.client.queue("pane.zoom", {}) end
end)

rex.action{
  name = "tmux_choose_tree",
  title = "choose-tree",
  run = function(ctx, args)
    local tmp = os.tmpname() .. ".json"
    _choose_tree_tmp = tmp
    local script = os.getenv("HOME") .. "/.config/rex/choose-tree.py"
    local tree = session_tree(ctx, true)
    rex.session.new_layer{
      bounds = { 0.2, 0.15, 0.6, 0.6 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        label = "choose-tree",
        options = {
          shell = "none",
          login = false,
          command = { "/usr/bin/python3", script, rex.json.encode(tree), tmp },
        },
      },
    }
  end,
}
rex.bind("ctrl+b>w", "tmux_choose_tree")
-- Switch host without going through the menu: Rex's own dialog, on the client that pressed it
rex.bind("ctrl+b>shift+w", "client.host.switch")

rex.action{
  name = "tmux_find_window",
  title = "find-window",
  run = function(ctx, args)
    local items = {}
    -- ids are "host|session|window|active|kind": remote rows need the host to be reached
    local function id(s, window, kind)
      return table.concat({ s.host or "", s.id, window, s.active, kind }, "|")
    end
    for _, s in ipairs(session_tree(ctx, false)) do
      local where = s.host and ("  @" .. s.host) or ""
      -- the session's row goes to its active tab; kind keeps its id apart from that tab's
      items[#items + 1] = { id = id(s, s.active, "s"), title = s.label .. where, icon = s.current and "star" or "folder" }
      for i, tab in ipairs(s.tabs) do
        items[#items + 1] = {
          id = id(s, tab.id, "t"),
          title = "  " .. i .. " " .. tab.name .. (tab.id == s.active and " *" or ""),
        }
      end
    end
    local choice = rex.ui.pick{ title = "find-window", placeholder = "Filter sessions and tabs", items = items }
    if not choice then
      return
    end
    local host, session_id, window_id, active = choice:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|")
    if host ~= "" then
      -- another host's session is reached through the app's client there, which the CLI
      -- finds: choose-tree.py --go does it, in a small pane that closes itself
      rex.session.new_layer{
        bounds = { 0.4, 0.45, 0.2, 0.1 },
        focus = false,
        layout = rex.layout.block{
          flavor = "com.superlogical.terminal.shell",
          label = "go",
          options = {
            shell = "none",
            login = false,
            command = { "/usr/bin/python3", os.getenv("HOME") .. "/.config/rex/choose-tree.py",
                        "--go", host, session_id, window_id, active, ctx.client_id },
          },
        },
      }
      return
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

-- tmux's short name for new-session, so "new" in the palette matches it exactly and it
-- comes above Rex's New Window and New Tab
rex.action{
  name = "tmux_new",
  title = "new",
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
    rex.client.queue("client.setting.terminal.typography.size", { value = 10.5 })
    -- Text pinned to the bottom of each pane, so nvim's statusline sits on the edge, with
    -- the leftover strip in the program's background colour
    rex.client.queue("client.setting.developer.experimental.terminal_anchor", { value = "bottom" })
    rex.client.queue("client.setting.interface.pane_padding.color", { value = "always" })
    -- A pink border on the focused pane instead of dimming the others, as tmux's
    -- pane-active-border-style fg=#f5bde6 (magenta is Catppuccin pink in the theme)
    rex.client.queue("client.setting.interface.active_panes.active_border", { value = true })
    rex.client.queue("client.setting.interface.active_panes.active_border_color", { value = "magenta" })
    rex.client.queue("client.setting.interface.active_panes.active_border_opacity", { value = 1 })
    rex.client.queue("client.setting.interface.active_panes.active_border_animation", { value = "off" })
    rex.client.queue("client.setting.interface.active_panes.fade", { value = "off" })
    rex.client.queue("client.setting.interface.active_panes.inactive_window", { value = false })
  end,
}

