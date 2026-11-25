-- choose-tree-watcher.lua: carries out what the choose-tree.c picker chose.
--
-- It's a `rex do` script, because its rex.client.queue reaches the app the way a key
-- binding does. The picker starts it with
-- `rex -C CLIENT do choose-tree-watcher.lua --args {...}` before drawing anything, so it's
-- connected by the time a choice is made. Each step logs to /tmp/choose-tree-watcher.log.
--
-- Focus goes back while the picker is still open, then the picker closes: closing a
-- floating layer that has focus makes Rex choose a block, which could be the wrong split.
-- Where focus goes back to comes from the server's focus history (focus_history.reverse,
-- "the last pane in this tab"), which records every move the app made, so it's right even
-- when the block C-b w reported lagged behind. The block C-b w reported is the fallback.
-- Focusing the picker ended any zoom in that window, so the block is zoomed again too.
-- After an escape, focus is checked for a moment and put back if something moved it.
--
-- Another tab in the same session is focused on the server (session.focus_block on its
-- block), so it works however the app is connected. Another session, a new session and switching host
-- need the app, which takes actions only through its home host: when it refuses, focus
-- goes back to the picker and the picker shows why.
local a = rex.args or {}
local LOG = os.getenv("REX_CHOOSE_TREE_LOG") or "/tmp/choose-tree-watcher.log"

local function log(msg)
  local f = io.open(LOG, "a")
  if f then
    local ok, stamp = pcall(os.date, "%H:%M:%S")
    f:write((ok and stamp or "") .. " lua: " .. msg .. "\n")
    f:close()
  end
end

-- A server call that logs instead of raising. rex.call may raise or return nil, err
local function call(method, params, quiet)
  local ok, res, err = pcall(rex.call, method, params)
  if ok and err == nil then
    return true, res
  end
  if not quiet then
    log(method .. " failed: " .. tostring(ok and err or res))
  end
  return false
end

local function set(s)
  return s ~= nil and s ~= ""
end

if not set(a.tmp) then
  log("no choice file given")
  rex.stop(1)
  return
end

local data
for _ = 1, 120000 do -- 10 minutes at 5 ms
  local f = io.open(a.tmp, "r")
  if f then
    data = f:read("*a")
    f:close()
    break
  end
  rex.sleep(0.005)
end
if not data then
  log("no choice after 10 minutes")
  rex.stop(1)
  return
end
pcall(os.remove, a.tmp)
log("choice " .. data)

local ok, c = pcall(rex.json.decode, data)
if not ok or type(c) ~= "table" then
  log("could not read the choice")
  rex.stop(1)
  return
end

-- The block a window has focused, read from the server
local function focused_in(session_id, window_id)
  if not (set(session_id) and set(window_id)) then
    return nil
  end
  local okv, view = call("session.view", { session_id = session_id }, true)
  if not okv or type(view) ~= "table" then
    return nil
  end
  for _, w in ipairs(view.windows or {}) do
    if w.window_id == window_id then
      return w.focused_block_id
    end
  end
end

local function zoom(block)
  if a.zoomed and set(block) then
    call("session.zoom_block", { session_id = a.session_id, block_id = block, zoom = true })
  end
end

-- Focus back where it was before the picker took it, with the picker still open. Returns
-- the block it went back to
local function put_back()
  if not set(a.session_id) then
    return nil
  end
  local back
  local okr, res = call("focus_history.reverse", set(a.window_id) and { window_id = a.window_id } or {}, true)
  if okr and type(res) == "table" and res.reversed and set(res.block_id)
      and (not set(res.session_id) or res.session_id == a.session_id) then
    back = res.block_id
    if set(a.block_id) and back ~= a.block_id then
      log("focus history says " .. back .. ", C-b w said " .. a.block_id)
    end
  elseif set(a.block_id) and call("session.focus_block", { session_id = a.session_id, block_id = a.block_id }) then
    back = a.block_id
  end
  zoom(back)
  return back
end

local function close_picker()
  if set(a.picker_block) then
    call("block.close", { session_id = a.picker_session, block_id = a.picker_block }, true)
  end
end

-- Keep focus on BLOCK for a moment after the picker closes, in case the app moves it
local function hold(block)
  if not set(block) then
    return
  end
  for _, wait in ipairs({ 0, 0.06, 0.15 }) do
    if wait > 0 then
      rex.sleep(wait)
    end
    local now = focused_in(a.session_id, a.window_id)
    if now and now ~= block then
      log("focus went to " .. now .. " as the picker closed; back to " .. block)
      call("session.focus_block", { session_id = a.session_id, block_id = block })
      zoom(block)
      return
    end
  end
end

-- Ask the app to do something. It raises when the app refuses
local function app(action, params)
  local okq, err = pcall(rex.client.queue, action, params or {})
  if not okq then
    log(action .. " refused: " .. tostring(err))
  end
  return okq, err
end

-- The app said no: give focus back to the picker and tell it why, and it carries on
local function refused(what, err)
  local e = tostring(err)
  local msg
  if e:find("other clients", 1, true) then
    msg = what .. ": the app takes that only from its home host. C-b W switches host"
  elseif e:find("Remote Control", 1, true) then
    msg = what .. ": turn on Remote Control in Rex Settings, under Rex Server"
  else
    msg = what .. " failed: " .. e:gsub("%s+", " ")
  end
  if set(a.picker_block) then
    call("session.focus_block", { session_id = a.picker_session, block_id = a.picker_block })
  end
  local part = a.tmp .. ".reply.part"
  local f = io.open(part, "w")
  if f then
    f:write(rex.json.encode({ error = msg }))
    f:close()
    if not pcall(os.rename, part, a.tmp .. ".reply") then
      local g = io.open(a.tmp .. ".reply", "w")
      if g then
        g:write(rex.json.encode({ error = msg }))
        g:close()
      end
    end
  end
  log("told the picker: " .. msg)
end

-- What needs the app goes the same way: focus back, ask, then close or explain
local function with_app(what, action, params)
  local back = put_back()
  local okq, err = app(action, params)
  if okq then
    close_picker()
  else
    refused(what, err)
  end
  return back
end

local back
if c.type == "cancel" then
  back = put_back()
  close_picker()
  if back then
    hold(back)
  elseif set(a.session_id) then
    -- nothing on the server worked: at least get back to the tab
    local opts = { session_id = a.session_id }
    if set(a.window_id) then
      opts.window_id = a.window_id
    end
    app("session.select", opts)
  end
elseif c.type == "lost" then
  close_picker() -- the person clicked elsewhere: leave focus there
elseif c.type == "select" and c.session_id == a.session_id and set(c.window_id) then
  back = put_back()
  close_picker()
  -- The tab's block first: focusing the window itself carried the picker's layer along to
  -- the other tab (v10 - v13), where focusing a block in it doesn't
  local done = set(c.block_id) and call("session.focus_block", { session_id = c.session_id, block_id = c.block_id })
  if not done then
    done = call("session.focus_window", { session_id = c.session_id, window_id = c.window_id })
  end
  if not done then
    app("session.select", { session_id = c.session_id, window_id = c.window_id })
  end
elseif c.type == "select" then
  local opts = { session_id = c.session_id }
  if set(c.window_id) then
    opts.window_id = c.window_id
  end
  back = with_app("can't switch to that session", "session.select", opts)
elseif c.type == "new" then
  back = with_app("can't make a session", "session.new", {})
elseif c.type == "switch" then
  back = with_app("can't switch host", "client.host.switch", {})
elseif c.type == "kill" and set(c.session_id) then
  close_picker()
  if not call("session.destroy", { session_id = c.session_id }) then
    local okx, err = pcall(rex.exec, { a.rex or "rex", "session", "kill", c.session_id })
    if not okx then
      log("session kill failed: " .. tostring(err))
    end
  end
end

log("done: " .. tostring(c.type) .. (back and (", focus back on " .. back) or ""))
rex.stop(0)
