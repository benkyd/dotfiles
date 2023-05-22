local lsp = require('lsp-zero')
local cmp = require('cmp')
local luasnip = require('luasnip')

require('mason').setup({})
require('mason-lspconfig').setup({})

lsp.preset({
    name = 'recommended',
})


lsp.ensure_installed({
    'tsserver',
    'clangd',
})

lsp.configure('clangd', {
    capabilities = {
        offsetEncoding = { "utf-16" }
    }
})

local cmp_mode = { behavior = cmp.SelectBehavior.Replace }
local cmp_mappings = lsp.defaults.cmp_mappings({
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
})

-- unmap arrow keys
cmp_mappings["<Up>"] = nil
cmp_mappings["<Down>"] = nil

lsp.setup_nvim_cmp({
    preselect = require('cmp').PreselectMode.None,
    completion = {
        completeopt = 'menu,menuone,noinsert,noselect'
    },
    mapping = cmp_mappings,
})

lsp.on_attach(function(_, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'gD', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
    vim.keymap.set('n', 'gT', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    vim.keymap.set('n', 'gR', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)

    -- diagnostics
    vim.keymap.set('n', 'gn', '<Cmd>lua vim.diagnostic.goto_next()<CR>', opts)
    vim.keymap.set('n', 'gp', '<Cmd>lua vim.diagnostic.goto_prev()<CR>', opts)

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
    vim.keymap.set('n', 'gw', '<Cmd>StripWhitespace<CR>', opts)
end)

local rust_lsp = lsp.build_options('rust_analyzer', {
      --cmd = { "/home/benk/programming/rust-analyzer/target/release/rust-analyzer" },
})

require('rust-tools').setup({
    server = rust_lsp,
    tools = {
        inlay_hints = {
            auto = false,
        }
    },
})

lsp.setup()


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

lsp.set_preferences({
    suggest_lsp_servers = false,
    sign_icons = {
        error = '',
        warn = '',
        hint = '',
        info = ''
    }
})

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

local cmp_config = {
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered()
    },
    formatting = {
        fields = { "kind", "abbr", "menu" },
        format = function(entry, vim_item)
            vim_item.menu = ({
                buffer = "",
                nvim_lsp = "",
            })[entry.source.name]

            -- add hints bc im stupid
            vim_item.menu = (vim_item.menu or ' ') .. ' ' .. vim_item.kind

            vim_item.kind = (cmp_kinds[vim_item.kind] or '')

            return vim_item
        end,
    }
}

cmp.setup(cmp_config)

vim.api.nvim_set_hl(0, "CmpItemMenu", { italic = true })
vim.diagnostic.config({
    virtual_text = true
})

