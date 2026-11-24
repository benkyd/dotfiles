-- Watches for choose-tree.py's choice and handles switching in app context.
-- rex.client.queue here is server→client, no Remote Control needed.
-- Called: rex -C CLIENT do choose-tree-watcher.lua --args '{"tmp":"...","client":"..."}'

local tmp = rex.args and rex.args.tmp
if not tmp then rex.stop(1); return end

local LOG = "/tmp/choose-tree-watcher.log"
local function log(s)
  local f = io.open(LOG, "a"); if f then f:write(s.."\n"); f:close() end
end

log("--- watcher start " .. tmp)

for _ = 1, 1200 do
  local f = io.open(tmp, "r")
  if f then
    local data = f:read("*a")
    f:close()
    pcall(os.remove, tmp)

    local ok, c = pcall(rex.json.decode, data)
    log("choice=" .. data)
    if ok and c and c.type and c.type ~= "done" then
      if c.type == "select" then
        local opts = { session_id = c.session_id }
        if c.window_id and c.window_id ~= "" then opts.window_id = c.window_id end
        local ok2, err = pcall(rex.client.queue, "session.select", opts)
        log("queue: " .. tostring(ok2) .. " " .. tostring(err))
      elseif c.type == "switch" then
        rex.client.queue("client.host.switch", {})
      elseif c.type == "new" then
        rex.client.queue("session.new", {})
      elseif c.type == "kill" and c.cmd then
        local parts = {}
        for _, p in ipairs(c.cmd) do
          parts[#parts + 1] = "'" .. tostring(p):gsub("'", "'\\''") .. "'"
        end
        os.execute(table.concat(parts, " "))
      end
      if c.was_zoomed then
        rex.client.queue("pane.zoom", {})
      end
    end

    rex.stop(0)
    return
  end
  rex.sleep(0.05)
end

rex.stop(1)
