-- Language servers. Neovim starts them itself once they're enabled at the
-- bottom of this file: nvim-lspconfig supplies the server definitions and
-- blink.cmp the completion. Rust is set up by rustaceanvim in plugins.lua.
--
-- Built-in keys: K hover, grn rename, gra code action, grr references,
-- gri implementation, grt type definition, gO symbols, ]d/[d diagnostics,
-- <C-s> signature help (insert mode).

vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(ev)
        local function map(lhs, rhs, desc)
            vim.keymap.set('n', lhs, rhs, { buffer = ev.buf, desc = desc })
        end
        map('gd', vim.lsp.buf.definition, 'Go to definition')
        map('gD', vim.lsp.buf.declaration, 'Go to declaration')
        map('<A-CR>', vim.lsp.buf.code_action, 'Code action')
        map('<leader>gr', vim.lsp.buf.rename, 'Rename')

        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client and client.name == 'clangd' then
            map('<leader>gg', '<Cmd>LspClangdSwitchSourceHeader<CR>', 'Switch header/source')
        end
    end,
})

-- C/C++: the clangd wrapper in ~/bin if there is one, else clangd from PATH
local clangd = vim.fn.expand('~/bin/clangd')
vim.lsp.config('clangd', {
    cmd = {
        vim.fn.executable(clangd) == 1 and clangd or 'clangd',
        '--background-index',
        '--limit-results=100',
        '-j=4',
    },
})

-- clangd crashes now and then, so restart it automatically.
-- :ClangdStop turns clangd off until :ClangdStart.
do
    local stopped, crashes, last_crash = false, 0, 0

    vim.api.nvim_create_autocmd('LspDetach', {
        callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            if stopped or not client or client.name ~= 'clangd' then return end

            -- Let every buffer detach, then check clangd has really gone
            vim.defer_fn(function()
                if stopped or #vim.lsp.get_clients({ name = 'clangd' }) > 0 then return end
                local now = vim.uv.now()
                if now - last_crash > 5 * 60 * 1000 then crashes = 0 end -- stable for 5 minutes
                crashes, last_crash = crashes + 1, now
                vim.notify(('clangd crashed, restarting (crash #%d, :ClangdStop to give up)'):format(crashes),
                    vim.log.levels.WARN)
                vim.lsp.enable('clangd') -- re-attaches every open C/C++ buffer
            end, 500)
        end,
    })

    vim.api.nvim_create_user_command('ClangdStop', function()
        stopped = true
        vim.lsp.enable('clangd', false)
        vim.notify('clangd stopped. :ClangdStart turns it back on.')
    end, {})

    vim.api.nvim_create_user_command('ClangdStart', function()
        stopped, crashes = false, 0
        vim.lsp.enable('clangd')
        vim.notify('clangd started.')
    end, {})
end

vim.lsp.config('lua_ls', {
    settings = {
        Lua = {
            runtime = { version = 'LuaJIT' },
            diagnostics = { globals = { 'vim' } },
            workspace = { library = { vim.env.VIMRUNTIME }, checkThirdParty = false },
        },
    },
})

-- Zig: real compiler errors need build-on-save, which runs `zig build check`
-- (add a `check` step to build.zig to get them in a project)
vim.lsp.config('zls', {
    settings = {
        zls = {
            enable_build_on_save = true,
            build_on_save_step = 'check',
            warn_style = true,
        },
    },
})

vim.lsp.enable({
    'clangd',
    'zls', -- must match the installed zig version
    'lua_ls',
    'pyright',
    'bashls',
    'cmake',
    'jsonls',
    'ts_ls',
    'cssls',
    'html',
})

vim.diagnostic.config({
    virtual_text = true,
    virtual_lines = false,
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = '\u{f057}',
            [vim.diagnostic.severity.WARN] = '\u{f071}',
            [vim.diagnostic.severity.HINT] = '\u{f0eb}',
            [vim.diagnostic.severity.INFO] = '\u{f05a}',
        },
    },
})

-- Switch between end-of-line diagnostics and full lines underneath
vim.keymap.set('n', '<leader>x', function()
    local config = vim.diagnostic.config()
    vim.diagnostic.config({
        virtual_text = not config.virtual_text,
        virtual_lines = not config.virtual_lines,
    })
end, { desc = 'Toggle line diagnostics' })
