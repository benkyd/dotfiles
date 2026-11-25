-- Migrated from ~/.tmux.conf (prefix ctrl+b), plus tmux's own default bindings

-- The first action defined here to run after this file loads sends my settings first (see
-- "My settings" near the end). settings_once is set there; if Rex won't let rex.action be
-- wrapped, the actions are defined as they are and only that is lost
local settings_once
do
  local define = rex.action
  pcall(function()
    rex.action = function(t)
      local run = t.run
      if type(run) == "function" and t.name ~= "apply_my_settings" and t.name ~= "tmux_reload_config" then
        t.run = function(ctx, args)
          if settings_once then
            pcall(settings_once, ctx)
          end
          return run(ctx, args)
        end
      end
      return define(t)
    end
  end)
end

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

-- Reload config (~/.tmux.conf:69): tmux_reload_config, near the end, which also puts my
-- settings back

-- tmux defaults: sessions
rex.bind("ctrl+b>s", "session.switch")

-- choose-tree (C-b w) and find-window (C-b f) list this server's sessions with their tabs.
-- When the app is attached to another host, that host's server runs them, so they list its
-- sessions. choose-tree also lists the other hosts' sessions, read in the background once
-- it's open; jumping to one needs the app to agree, which it does only through its home
-- host, and the tree says so when it doesn't.
--
-- choose-tree is choose-tree.c in a floating pane, so it takes vim keys: j/k move, 1-9 go to
-- that session, enter goes, h/l fold, J/K reorder, r rename, x kill, n new, H switch host,
-- q closes. The switch is made by choose-tree-watcher.lua, which also puts focus and zoom back.
-- find-window is this server's list in Rex's picker, to filter by typing.

-- A tab's name: its label, or for an unnamed tab its program and folder
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

-- This server's sessions: { id, label, current, active, tabs = { { id, name, block } } }, block
-- being the tab's focused block. The current session also has block, the block that had
-- focus, and zoomed, whether its window was zoomed, so choose-tree can put both back.
-- session.view reads a session without attaching to it.
local function session_tree(ctx)
  local tree = {}
  local list = rex.call("session.list")
  for _, s in ipairs(list and list.sessions or {}) do
    local ok, view = pcall(rex.call, "session.view", { session_id = s.session_id })
    if ok and view and view.windows then
      local entry = {
        id = s.session_id,
        label = s.label,
        current = s.session_id == ctx.session_id,
        active = view.active_window_id or "",
        tabs = {},
      }
      for i, w in ipairs(view.windows) do
        entry.tabs[i] = { id = w.window_id, name = tab_name(s.session_id, w, i), block = w.focused_block_id or "" }
        if entry.current and w.window_id == entry.active then
          local zoomed = w.zoomed_block_id or ""
          entry.zoomed = zoomed ~= ""
          if zoomed ~= "" then
            entry.block = zoomed
          else
            entry.block = ctx.block_id or w.focused_block_id or ""
          end
        end
      end
      tree[#tree + 1] = entry
    end
  end
  return tree
end

local choose_tree_dir = os.getenv("HOME") .. "/.config/rex"
local choose_tree_source = choose_tree_dir .. "/choose-tree.c"
local choose_tree_watcher = choose_tree_dir .. "/choose-tree-watcher.lua"

-- The picker is choose-tree.c, built per machine into ~/.cache/rex under a name taken from
-- the source, so a changed source is built again rather than an old build run. When the
-- build isn't there yet, the pane builds it first (a second or two, once), then runs it
local choose_tree_bin
do
  local f = io.open(choose_tree_source, "r")
  if f then
    local src = f:read("*a")
    f:close()
    local h = 5381
    for i = 1, #src do
      h = (h * 33 + src:byte(i)) % 4294967296
    end
    choose_tree_bin = os.getenv("HOME") .. "/.cache/rex/choose-tree-" .. string.format("%.0f", h)
  end
end
local function exists(path)
  local f = path and io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- sh -c this SOURCE BINARY ARGS...: build BINARY from SOURCE, then run it with ARGS. On
-- macOS only with the developer tools installed, as without them cc offers to install them
local choose_tree_build = [[
src=$1 bin=$2
shift 2
stop() { printf '%s\r\n(press enter)' "$1"; read -r _; exit 1; }
if [ ! -x "$bin" ]; then
  printf 'building choose-tree...\r\n'
  if [ "$(uname)" = Darwin ]; then
    tools=$(xcode-select -p 2>/dev/null) && [ -d "$tools" ] || stop "choose-tree needs the developer tools: run xcode-select --install"
  fi
  command -v cc >/dev/null 2>&1 || stop "choose-tree needs a C compiler (cc)"
  dir=$(dirname "$bin")
  mkdir -p "$dir" || stop "can't make $dir"
  if cc -O2 -o "$bin.tmp.$$" "$src" 2>"$bin.log"; then
    mv -f "$bin.tmp.$$" "$bin"
    for old in "$dir"/choose-tree-*; do
      case $old in "$bin"|"$bin".*) ;; *) rm -rf "$old" ;; esac
    done
  else
    rm -f "$bin.tmp.$$"
    cat "$bin.log"
    stop "choose-tree didn't build: the errors are above, and in $bin.log"
  fi
fi
exec "$bin" "$@"
]]

-- choose-tree.c reads the tree as records: RS (30) before each, US (31) between fields
local RS, US = string.char(30), string.char(31)
local function clean(s)
  return (tostring(s or ""):gsub("[" .. RS .. US .. "]", " "))
end
local function tree_records(tree)
  local out = {}
  for _, s in ipairs(tree) do
    out[#out + 1] = RS .. table.concat({ "S", clean(s.id), clean(s.label), clean(s.active),
      s.current and "1" or "0", clean(s.block), s.zoomed and "1" or "0" }, US)
    for _, t in ipairs(s.tabs) do
      out[#out + 1] = RS .. table.concat({ "T", clean(t.id), clean(t.name), clean(t.block) }, US)
    end
  end
  return RS .. table.concat(out)
end

rex.action{
  name = "tmux_choose_tree",
  title = "choose-tree",
  run = function(ctx, args)
    -- The other hosts' labels only: the picker reads their sessions itself, in the
    -- background, as waiting on them here would hold up every key until they answered
    local ok_hosts, hosts = pcall(rex.servers)
    hosts = ok_hosts and type(hosts) == "table" and hosts or {}
    local labels = {}
    for i, h in ipairs(hosts) do
      labels[i] = clean(h)
    end
    local args = { ctx.client_id or "", tree_records(session_tree(ctx)),
                   "hosts:" .. table.concat(labels, US), "server:" .. clean(ctx.server),
                   "watcher:" .. choose_tree_watcher }
    local command
    if exists(choose_tree_bin) then
      command = { choose_tree_bin }
    elseif choose_tree_bin then
      command = { "/bin/sh", "-c", choose_tree_build, "sh", choose_tree_source, choose_tree_bin }
    else
      command = { "/bin/sh", "-c", "printf 'choose-tree.c is missing from ~/.config/rex\\r\\n(press enter)'; read -r _" }
      args = {}
    end
    for _, a in ipairs(args) do
      command[#command + 1] = a
    end
    rex.session.new_layer{
      bounds = { 0.2, 0.15, 0.6, 0.6 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        label = "choose-tree",
        options = { shell = "none", login = false, command = command },
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
    for _, s in ipairs(session_tree(ctx)) do
      -- a session's row goes to its active tab; s and t keep its id apart from that tab's
      items[#items + 1] = { id = "s|" .. s.id .. "|" .. s.active, title = s.label, icon = s.current and "star" or "folder" }
      for i, tab in ipairs(s.tabs) do
        items[#items + 1] = {
          id = "t|" .. s.id .. "|" .. tab.id,
          title = "  " .. i .. " " .. tab.name .. (tab.id == s.active and " *" or ""),
        }
      end
    end
    local choice = rex.ui.pick{ title = "find-window", placeholder = "Filter sessions and tabs", items = items }
    if not choice then
      return
    end
    local session_id, window_id = choice:match("^[st]|([^|]*)|([^|]*)$")
    if session_id then
      local opts = { session_id = session_id }
      if window_id ~= "" then
        opts.window_id = window_id
      end
      rex.client.queue("session.select", opts)
    end
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
-- Last pane (tmux's C-b ;): the pane of this tab that had focus before this one, from the
-- server's focus history, which records every focus move. Pressed again, it goes back, as
-- tmux's does. (Rex's own pane.focus_back.in_tab went in build 2116.)
rex.action{
  name = "tmux_last_pane",
  title = "last-pane",
  run = function(ctx, args)
    local ok, view = pcall(rex.call, "session.view", { session_id = ctx.session_id })
    local window = ok and type(view) == "table" and view.active_window_id
    if window then
      pcall(rex.call, "focus_history.reverse", { window_id = window })
    end
  end,
}
rex.bind("ctrl+b>;", "tmux_last_pane")
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

-- My settings. Rex can't hold app settings in init.lua or run anything when it loads, only an
-- action can send settings to the app, and reloading the config puts some of them, such as
-- the font size, back to Rex's defaults. So they're sent again by C-b r itself, right after
-- the reload, and by the first of my actions after any load of this file (C-b w, C-b f,
-- C-b ; ...), which also covers a new machine and a reload made some other way. The theme is
-- imported only when this device hasn't had this theme file yet (kept in
-- ~/.cache/rex/theme-DEVICE). "apply-my-settings" (C-b :) sends everything, theme included.
-- The theme file and shell are paths on this server's machine, which only the Mac app can
-- use when the server is the Mac itself; a Linux server starts the account's login shell,
-- so set that with chsh there.
local function on_macos()
  local f = io.open("/System/Library/CoreServices/SystemVersion.plist", "r")
  if f then
    f:close()
    return true
  end
  return false
end

local my_settings = {}
local function setting(action, args)
  my_settings[#my_settings + 1] = { action, args }
end
if on_macos() and machine.fish then
  setting("client.setting.terminal.shell.command", { value = machine.fish })
end
setting("client.setting.interface.toolbar.auto_hide_toolbar", { value = "always_show" })
setting("client.setting.developer.experimental.new_quick_switcher", { value = true })
setting("client.setting.terminal.typography.size", { value = 10.5 })
-- Text pinned to the bottom of each pane, so nvim's statusline sits on the edge, with the
-- leftover strip in the program's background colour
setting("client.setting.developer.experimental.terminal_anchor", { value = "bottom" })
setting("client.setting.interface.pane_padding.color", { value = "always" })
-- A pink border on the focused pane instead of dimming the others, as tmux's
-- pane-active-border-style fg=#f5bde6 (magenta is Catppuccin pink in the theme)
setting("client.setting.interface.active_panes.active_border", { value = true })
setting("client.setting.interface.active_panes.active_border_color", { value = "magenta" })
setting("client.setting.interface.active_panes.active_border_opacity", { value = 100 }) -- a percentage
setting("client.setting.interface.active_panes.active_border_animation", { value = "off" })
setting("client.setting.interface.active_panes.fade", { value = "off" })
setting("client.setting.interface.active_panes.inactive_window", { value = false })

local theme_path = os.getenv("HOME") .. "/.config/rex/themes/Catppuccin Mocha"
local theme_text
do
  local f = on_macos() and io.open(theme_path, "r")
  if f then
    theme_text = f:read("*a")
    f:close()
  end
end

-- Where a device's last imported theme is kept: by the app's label, so each device has its own
local function theme_file(ctx)
  local device = "app"
  local ok, list = pcall(rex.call, "client.list")
  if ok and type(list) == "table" then
    for _, c in ipairs(list.clients or {}) do
      if c.client_id == ctx.client_id and c.info and c.info.label then
        device = c.info.label
      end
    end
  end
  return os.getenv("HOME") .. "/.cache/rex/theme-" .. device:gsub("[^%w%-]", "_")
end

local function send_settings(ctx, with_theme)
  if theme_text then
    local path = theme_file(ctx)
    local f = io.open(path, "r")
    local last = f and f:read("*a")
    if f then
      f:close()
    end
    if with_theme or last ~= theme_text then
      rex.client.queue("client.theme.import", { path = theme_path })
      f = io.open(path, "w")
      if not f then
        pcall(rex.exec, { "/bin/mkdir", "-p", os.getenv("HOME") .. "/.cache/rex" })
        f = io.open(path, "w")
      end
      if f then
        f:write(theme_text)
        f:close()
      end
    end
  end
  for _, s in ipairs(my_settings) do
    rex.client.queue(s[1], s[2])
  end
end

-- Called by every action of mine (see the top of this file): the first one for each client
-- after this file loads sends the settings
local settings_sent = {}
settings_once = function(ctx)
  if not (ctx and ctx.client_id) or settings_sent[ctx.client_id] then
    return
  end
  settings_sent[ctx.client_id] = true
  send_settings(ctx, false)
end

rex.action{
  name = "apply_my_settings",
  title = "apply-my-settings",
  run = function(ctx, args)
    send_settings(ctx, true)
  end,
}

-- Reload the config (tmux's C-b r, ~/.tmux.conf:69), then put the settings back, as the
-- reload resets some of them. The app does the queued actions in order
rex.action{
  name = "tmux_reload_config",
  title = "reload-config",
  run = function(ctx, args)
    rex.client.queue("client.config.reload", {})
    send_settings(ctx, false)
  end,
}
rex.bind("ctrl+b>r", "tmux_reload_config")

