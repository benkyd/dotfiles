-- choose-tree-watcher.lua: carries out what choose-tree.py's picker chose.
--
-- It's a `rex do` script, because its rex.client.queue reaches the app the way a key
-- binding does, which needs no Remote Control (a plain `rex do session.select` does).
-- choose-tree.py starts it with `rex -C CLIENT do choose-tree-watcher.lua --args {...}`
-- before drawing the tree, so it's connected by the time a choice is made. It waits for
-- the choice file, closes the picker's pane, puts focus back on the block that had it
-- (focusing the picker ended any zoom in that window, so it zooms it again), then
-- switches. Each step logs to /tmp/choose-tree-watcher.log.
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
for _ = 1, 30000 do -- 10 minutes at 20 ms
  local f = io.open(a.tmp, "r")
  if f then
    data = f:read("*a")
    f:close()
    break
  end
  rex.sleep(0.02)
end
if not data then
  log("no choice after 10 minutes")
  rex.stop(1)
  return
end
pcall(os.remove, a.tmp) -- tells the picker its choice was taken
log("choice " .. data)

local ok, c = pcall(rex.json.decode, data)
if not ok or type(c) ~= "table" then
  log("could not read the choice")
  rex.stop(1)
  return
end

-- The picker's pane first, so Rex's own refocus when it goes comes before ours. If it
-- can't be closed from here, the picker leaves by itself; give that time to land
if set(a.picker_block) then
  if not call("block.close", { session_id = a.picker_session, block_id = a.picker_block }, true) then
    rex.sleep(0.25)
  end
end

-- Focus back where it was, and zoom again if it was zoomed. Not when the picker lost focus
-- (the person clicked elsewhere) or the session is being killed
local back = false
if c.type ~= "lost" and c.type ~= "kill" and set(a.session_id) and set(a.block_id) then
  back = call("session.focus_block", { session_id = a.session_id, block_id = a.block_id })
  if back and a.zoomed then
    call("session.zoom_block", { session_id = a.session_id, block_id = a.block_id, zoom = true })
  end
end

if c.type == "select" then
  local opts = { session_id = c.session_id }
  if set(c.window_id) then
    opts.window_id = c.window_id
  end
  rex.client.queue("session.select", opts)
elseif c.type == "cancel" then
  if not back and set(a.session_id) then
    -- focus_block didn't work: at least get back to the tab
    local opts = { session_id = a.session_id }
    if set(a.window_id) then
      opts.window_id = a.window_id
    end
    rex.client.queue("session.select", opts)
  end
elseif c.type == "new" then
  rex.client.queue("session.new", {})
elseif c.type == "switch" then
  rex.client.queue("client.host.switch", {})
elseif c.type == "kill" and set(c.session_id) then
  if not call("session.destroy", { session_id = c.session_id }) then
    local okx, err = pcall(rex.exec, { a.rex or "rex", "session", "kill", c.session_id })
    if not okx then
      log("session kill failed: " .. tostring(err))
    end
  end
end

log("done: " .. tostring(c.type) .. (back and ", focus restored" or ""))
rex.stop(0)
