-- Watches for choose-tree.py's choice and handles switching in app context.
-- rex.client.queue here is server→client and never needs Remote Control.
-- Called: rex -C CLIENT do choose-tree-watcher.lua --args '{"tmp":"...","rex":"..."}'

local tmp     = rex.args and rex.args.tmp
local REX_BIN = rex.args and rex.args.rex or "rex"

if not tmp then rex.stop(1); return end

local function q(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

for _ = 1, 1200 do          -- poll up to 60 s
  local f = io.open(tmp, "r")
  if f then
    local data = f:read("*a")
    f:close()
    pcall(os.remove, tmp)

    local ok, c = pcall(rex.json.decode, data)
    if ok and c and c.type then

      if c.type == "select" and (not c.host or c.host == "") then
        -- ── Local session ── direct queue, no Remote Control check ──────────
        local opts = { session_id = c.session_id }
        if c.window_id and c.window_id ~= "" then opts.window_id = c.window_id end
        rex.client.queue("session.select", opts)

      elseif c.type == "select" and c.host and c.host ~= "" then
        -- ── Remote session ── find the right app client on that host ─────────
        local target = nil
        local ok2, rc = pcall(function()
          return rex.server(c.host).call("client.ls")
        end)
        if ok2 and rc then
          local apps = {}
          for _, cl in ipairs(rc.clients or {}) do
            if cl.info and cl.info.kind == "app" then apps[#apps + 1] = cl end
          end
          table.sort(apps, function(a, b)
            return (a.connected_at or "") > (b.connected_at or "")
          end)
          if #apps > 0 then target = apps[1].client_id end
        end
        if target then
          local lua = string.format(
            'rex.client.queue("session.select",{session_id=%q,window_id=%q})',
            c.session_id, c.window_id or "")
          os.execute(table.concat({
            q(REX_BIN), "-S", q(c.host), "-C", q(target),
            "do", "-e", q(lua), ">/dev/null", "2>&1", "&"
          }, " "))
        end

      elseif c.type == "switch" then
        rex.client.queue("client.host.switch", {})

      elseif c.type == "new" then
        rex.client.queue("session.new", {})

      elseif c.type == "kill" and c.cmd then
        local parts = {}
        for _, p in ipairs(c.cmd) do parts[#parts + 1] = q(p) end
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
