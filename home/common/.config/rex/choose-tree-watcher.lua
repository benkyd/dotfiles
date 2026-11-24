-- Watches for choose-tree.py's choice and handles switching in app context.
-- rex.client.queue here is server→client and never needs Remote Control.
-- Called: rex -C CLIENT do choose-tree-watcher.lua --args '{"tmp":"...","rex":"...","client":"..."}'

local tmp     = rex.args and rex.args.tmp
local REX_BIN = rex.args and rex.args.rex or "rex"
local our_client = rex.args and rex.args.client or ""
local LOG     = "/tmp/choose-tree-watcher.log"

if not tmp then rex.stop(1); return end

local function q(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(msg .. "\n"); f:close() end
end

local function pread(cmd)
  local h = io.popen(cmd .. " 2>/dev/null")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

-- Find the right app client on a remote host (matches our app by label)
local function remote_client(host)
  -- Get our label from local client list
  local my_label = nil
  local ok, lc = pcall(rex.json.decode, pread(q(REX_BIN) .. " client ls --json") or "")
  if ok and lc then
    for _, c in ipairs(lc.clients or {}) do
      if c.client_id == our_client and c.info then
        my_label = c.info.label; break
      end
    end
  end
  log("our_label=" .. tostring(my_label))

  -- Get clients on the remote host
  local ok2, rc = pcall(rex.json.decode,
    pread(q(REX_BIN) .. " -S " .. q(host) .. " client ls --json") or "")
  if not ok2 or not rc then log("client ls on " .. host .. " failed"); return nil end

  local apps, best = {}, nil
  for _, c in ipairs(rc.clients or {}) do
    if c.info and c.info.kind == "app" then
      apps[#apps + 1] = c
      if my_label and c.info.label == my_label then best = c.client_id end
    end
  end
  if not best and #apps == 1 then best = apps[1].client_id end
  log("remote target=" .. tostring(best) .. " (#apps=" .. #apps .. ")")
  return best
end

log("--- watcher start tmp=" .. tmp)

for _ = 1, 1200 do          -- poll up to 60 s
  local f = io.open(tmp, "r")
  if f then
    local data = f:read("*a")
    f:close()
    pcall(os.remove, tmp)
    log("choice=" .. data)

    local ok, c = pcall(rex.json.decode, data)
    if ok and c and c.type then

      if c.type == "select" and (not c.host or c.host == "") then
        -- ── Local session ── direct queue, no Remote Control check ──────────
        log("local select " .. (c.session_id or "") .. " " .. (c.window_id or ""))
        local opts = { session_id = c.session_id }
        if c.window_id and c.window_id ~= "" then opts.window_id = c.window_id end
        rex.client.queue("session.select", opts)

      elseif c.type == "select" and c.host and c.host ~= "" then
        -- ── Remote session ── find the right app client on that host ─────────
        log("remote select host=" .. c.host)
        local target = remote_client(c.host)
        if target then
          local lua = string.format(
            'rex.client.queue("session.select",{session_id=%q,window_id=%q})',
            c.session_id, c.window_id or "")
          local cmd = table.concat({
            q(REX_BIN), "-S", q(c.host), "-C", q(target),
            "do", "-e", q(lua), ">>" .. q(LOG), "2>&1"
          }, " ")
          log("running: " .. cmd)
          os.execute(cmd)
        end

      elseif c.type == "switch" then
        log("switch host")
        rex.client.queue("client.host.switch", {})

      elseif c.type == "new" then
        log("new session")
        rex.client.queue("session.new", {})

      elseif c.type == "kill" and c.cmd then
        local parts = {}
        for _, p in ipairs(c.cmd) do parts[#parts + 1] = q(p) end
        os.execute(table.concat(parts, " "))
      end

      if c.was_zoomed then
        log("restoring zoom")
        rex.client.queue("pane.zoom", {})
      end
    end

    rex.stop(0)
    return
  end
  rex.sleep(0.05)
end

log("watcher timed out")
rex.stop(1)
