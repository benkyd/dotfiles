local lsp = require('lsp-zero');
local cmp = require('cmp')
local luasnip = require('luasnip')
local dap = require('dap')
local dapui = require('dapui')

dap.configurations = {
    cpp = {
        {
            name = "Launch",
            type = "codelldb",
            request = "launch",
            program = function()
                return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/build/', 'file')
            end,
            cwd = '${workspaceFolder}',
            stopOnEntry = true,
        },
    },
}

dap.adapters.codelldb = {
    type = 'server',
    port = '13000',
    host = '127.0.0.1',
    executable = {
        command = vim.fn.stdpath('data') .. '/mason/bin/codelldb',
        args = {"--port", "13000"}
    }
}

dapui.setup({
    icons = { expanded = "➡️", collapsed = "⬇️" },
    mappings = {
        open = "o",
        remove = "d",
        edit = "e",
        repl = "r",
        toggle = "t",
    },
    expand_lines = vim.fn.has("nvim-0.7"),
    layouts = {
        {
            elements = {
                "scopes",
                "stacks",
                "watches"
            },
            size = 0.17,
            position = "left"
        },
        {
            elements = {
                "repl",
                "console",
                "breakpoints",
            },
            size = 0.15,
            position = "bottom",
        },
    },
    floating = {
        max_height = nil,
        max_width = nil,
        border = "single",
        mappings = {
            close = { "q", "<Esc>" },
        },
    },
    windows = { indent = 1 },
    render = {
        max_type_length = nil,
    },
})

dap.listeners.after.event_initialized["dapui_config"]=function()
    dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"]=function()
    dapui.close()
end
dap.listeners.before.event_exited["dapui_config"]=function()
    dapui.close()
end
vim.keymap.set("n", "<leader>ds", function()
    dap.continue()
    dapui.toggle({})
end)
vim.keymap.set("n", "<leader>de", function()
    dapui.toggle({})
    dap.terminate()
    require("notify")("Debugger session ended", "warn")
end)
vim.keymap.set("n", "<leader>dC", function()
    require('dap').clear_breakpoints()
    require("notify")("Cleared breakpoints", "warn")
end)
vim.fn.sign_define('DapBreakpoint',{ text ='🔴', texthl ='', linehl ='', numhl =''})
vim.fn.sign_define('DapStopped',{ text ='▶️', texthl ='', linehl ='', numhl =''})

lsp.configure('clangd', {
    capabilities = {
        offsetEncoding = { "utf-16" }
    }
})

-- lsp.setup_nvim_cmp({
--     preselect = require('cmp').PreselectMode.None,
--     completion = {
--         completeopt = 'menu,menuone,noinsert,noselect'
--     },
--     mapping = cmp_mappings,
-- })

lsp.on_attach(function(client, bufnr)
    local opts = { buffer = bufnr }
    vim.keymap.set('n', 'gD', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
    vim.keymap.set('n', 'gT', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    vim.keymap.set('n', 'gR', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)

    -- diagnostics
    vim.keymap.set('n', 'gn', '<Cmd>lua vim.diagnostic.goto_next()<CR>', opts)
    vim.keymap.set('n', 'gN', '<Cmd>lua vim.diagnostic.goto_prev()<CR>', opts)

    -- action & rename
    vim.keymap.set('n', '<A-CR>', '<Cmd>Lspsaga code_action<CR>', opts)
    vim.keymap.set('n', '<Leader>gr', '<Cmd>Lspsaga rename<CR>', opts)

    -- overwrite the defaults
    vim.keymap.set('n', 'gi', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
    vim.keymap.set('n', 'K', '<Cmd>Lspsaga hover_doc<CR>', opts)

    -- jump forward/backward up/down the call list
    vim.keymap.set('n', 'gI', '<Cmd>Lspsaga incoming_calls<CR>', opts)
    vim.keymap.set('n', 'gO', '<Cmd>Lspsaga outgoing_calls<CR>', opts)

    -- Sexy LSP
    vim.keymap.set('n', 'gd', '<CMD>Lspsaga peek_definition<CR>', opts)
    vim.keymap.set('n', 'gt', '<CMD>Lspsaga peek_type_definition<CR>', opts)
    vim.keymap.set('n', 'gr', '<CMD>Lspsaga lsp_finder<CR>', opts)

    -- CLANGFORMATTTTT
    vim.keymap.set('n', 'gf', '<Cmd>lua vim.lsp.buf.format()<CR>', opts)
    vim.keymap.set('n', '<Leader>gg', '<Cmd>ClangdSwitchSourceHeader<CR>', opts)
    vim.keymap.set('n', 'gw', '<Cmd>StripWhitespace<CR>', opts)
end)


lsp.setup()

local cmp_kinds = {
    Text = "",
    Method = "",
    Function = "",
    Constructor = "",
    Field = "ﴲ",
    Variable = "",
    Class = "",
    Interface = "ﰮ",
    Module = "",
    Property = "襁",
    Unit = "",
    Value = "",
    Enum = "練",
    Keyword = "",
    Snippet = "",
    Color = "",
    File = "",
    Reference = "",
    Folder = "",
    EnumMember = "",
    Constant = "ﲀ",
    Struct = "ﳤ",
    Event = "",
    Operator = "",
    TypeParameter = ""
}


require('mason').setup({})
require('mason-lspconfig').setup({
    handlers = {
        lsp.default_setup,
    },
})

cmp.setup({
    sources = {
        { name = 'nvim_lsp' },
        { name = 'luasnip' },
        { name = 'buffer' },
        { name = 'path' },
    },
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered()
    },
    completion = {
        completeopt = "menu,menuone,preview,noselect",
    },
    snippet = {
        expand = function(args)
            luasnip.lsp_expand(args.body)
        end,
    },
    formatting = {
        fields = { "kind", "abbr", "menu" },
        format = function(entry, vim_item)
            vim_item.menu = ({
                buffer = "",
                nvim_lsp = "",
            })[entry.source.name]
                local kind = vim_item.kind
                vim_item.kind = " " .. (cmp_kinds[kind] or "?") .. ""
                local source = entry.source.name
                vim_item.menu = "[" .. source .. "]"
                return vim_item
        end,
    },
    sorting = {
        priority_weight = 1.0,
    },
    matching = {
        disallow_fuzzy_matching = true,
        disallow_fullfuzzy_matching = true,
        disallow_partial_fuzzy_matching = true,
        disallow_partial_matching = false,
        disallow_prefix_unmatching = true,
    },
    performance = {
        max_view_entries = 20,
    },
    mapping = {
        ["<Tab>"] = cmp.mapping(function(fallback)
            if (cmp.visible()) then
                cmp.select_next_item(cmp_mode)
            elseif luasnip.expand_or_jumpable() then
                luasnip.expand_or_jump()
            else
                fallback()
            end
            cmp.mapping.select_next_item(cmp_mode)
        end, { 'i', 's' }),
        ["<S-Tab>"] = cmp.mapping.select_prev_item(cmp_mode),
        ["<Up>"] = nil,
        ["<Down>"] = nil
    },
})

cmp.setup.cmdline('/', {
    sources = {
        { name = 'buffer' }
    }
})

cmp.setup.cmdline(':', {
    sources = cmp.config.sources({
        { name = 'path' }
    }, {
        { name = 'cmdline' }
    })
})

vim.api.nvim_set_hl(0, "CmpItemMenu", { italic = true })
vim.diagnostic.config({
    virtual_text = true,
    signs = {
        [vim.diagnostic.severity.ERROR] = '',
        [vim.diagnostic.severity.WARN] = '',
        [vim.diagnostic.severity.HINT] = '',
        [vim.diagnostic.severity.INFO] = ''
    }
})

