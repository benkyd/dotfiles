-- Locate lldb-dap, the debug adapter used for C/C++/Rust.
-- On Arch it comes with the `lldb` package and is on PATH; on macOS it
-- ships with Xcode but isn't on PATH, so ask xcrun for it.
local M = {}

local cached

function M.path()
    if cached ~= nil then return cached or nil end
    local path = vim.fn.exepath('lldb-dap')
    if path == '' and vim.fn.has('mac') == 1 then
        path = vim.trim(vim.fn.system({ 'xcrun', '-f', 'lldb-dap' }))
        if vim.v.shell_error ~= 0 then path = '' end
    end
    cached = path ~= '' and path or false
    return cached or nil
end

-- nvim-dap / rustaceanvim executable adapter config, or nil if not found
function M.adapter()
    local path = M.path()
    if not path then return nil end
    return { type = 'executable', command = path, name = 'lldb' }
end

return M
