-- Watches for choose-tree.py's choice and handles switching in app context.
-- rex.client.queue here is server→client and never needs Remote Control.
-- Called: rex -C CLIENT do choose-tree-watcher.lua --args '{"tmp":"...","rex":"...","client":"..."}'

local tmp        = rex.args and rex.args.tmp
local our_client = rex.args and rex.args.client or ""
local LOG        = "/tmp/choose-tree-watcher.log"

if not tmp then rex.stop(1); return end

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(msg .. "\n"); f:close() end
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
        -- ── Local session ── direct queue, no Remote Control ────────────────
        log("local select " .. (c.session_id or ""))
        local opts = { session_id = c.session_id }
        if c.window_id and c.window_id ~= "" then opts.window_id = c.window_id end
        local ok2, err = pcall(rex.client.queue, "session.select", opts)
        log("queue result: " .. tostring(ok2) .. " " .. tostring(err))

      elseif c.type == "select" and c.host and c.host ~= "" then
        -- ── Remote session ── use rex.server() to reach the right host ──────
        log("remote select host=" .. c.host)
        local opts = { session_id = c.session_id }
        if c.window_id and c.window_id ~= "" then opts.window_id = c.window_id end

        -- Try queuing via the remote server (client context carries over)
        local ok2, err = pcall(function()
          rex.server(c.host).client.queue("session.select", opts)
        end)
        log("remote queue: " .. tostring(ok2) .. " " .. tostring(err))

        if not ok2 then
          -- Fallback: find the Mac app on the remote host by label matching,
          -- then open a tiny hidden pane there to do the switch
          log("trying new_layer fallback")
          local my_label = nil
          local ok3, lc = pcall(rex.call, "client.ls")
          if ok3 and lc then
            for _, cl in ipairs(lc.clients or {}) do
              if cl.client_id == our_client and cl.info then
                my_label = cl.info.label; break
              end
            end
          end
          log("our_label=" .. tostring(my_label))

          local ok4, rc = pcall(function()
            return rex.server(c.host).call("client.ls")
          end)
          if ok4 and rc then
            local target = nil
            local apps = {}
            for _, cl in ipairs(rc.clients or {}) do
              if cl.info and cl.info.kind == "app" then
                apps[#apps+1] = cl
                if my_label and cl.info.label == my_label then target = cl.client_id end
              end
            end
            if not target and #apps == 1 then target = apps[1].client_id end
            log("remote target=" .. tostring(target))

            if target then
              -- Open a tiny hidden pane on the remote host to dispatch the action
              local go_py = os.getenv("HOME") .. "/.config/rex/choose-tree.py"
              local ok5, err5 = pcall(function()
                rex.server(c.host).session.new_layer{
                  bounds = {0.45, 0.48, 0.1, 0.05},
                  focus = false,
                  layout = rex.layout.block{
                    flavor = "com.superlogical.terminal.shell",
                    label = "go",
                    options = {
                      shell = "none", login = false,
                      command = {
                        "/usr/bin/python3", go_py,
                        "--go", "", c.session_id, c.window_id or "",
                        c.session_id, target
                      }
                    }
                  }
                }
              end)
              log("new_layer: " .. tostring(ok5) .. " " .. tostring(err5))
            end
          else
            log("remote client.ls failed: " .. tostring(rc))
          end
        end

      elseif c.type == "switch" then
        log("switch host")
        rex.client.queue("client.host.switch", {})

      elseif c.type == "new" then
        log("new session")
        rex.client.queue("session.new", {})

      elseif c.type == "kill" and c.cmd then
        log("kill")
        local parts = {}
        for _, p in ipairs(c.cmd) do
          parts[#parts+1] = "'" .. tostring(p):gsub("'", "'\\''") .. "'"
        end
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
