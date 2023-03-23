local lsp = require('lsp-zero')

require('mason').setup({})
require('mason-lspconfig').setup({})

lsp.preset({
    name = 'recommended',
})

local rust_lsp = lsp.build_options('rust_analyzer', {})
lsp.ensure_installed({
  'tsserver',
  'clangd',
})

-- Fix Undefined global 'vim'
lsp.configure('lua-language-server', {
    settings = {
        Lua = {
            diagnostics = {
                globals = { 'vim' }
            }
        }
    }
})

lsp.configure('clangd', {
    capabilities = {
        offsetEncoding = { "utf-16" }
    }
})

local cmp = require('cmp')
local cmp_mode = { behavior = cmp.SelectBehavior.Replace }
local cmp_mappings = lsp.defaults.cmp_mappings({
    ["<Tab>"] = cmp.mapping.select_next_item(cmp_mode),
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

local cmp_config = lsp.defaults.cmp_config({
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered()
    },
})

cmp.setup(cmp_config)

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


lsp.on_attach(function(_, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', '<Leader>gD', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
    vim.keymap.set('n', '<Leader>gT', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    vim.keymap.set('n', '<Leader>gI', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
    vim.keymap.set('n', '<Leader>gR', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)

    vim.keymap.set('n', '<A-CR>', '<Cmd>lua vim.lsp.buf.code_action()<CR>', opts)

    -- Glance LSP
    vim.keymap.set('n', '<Leader>gd', '<CMD>Glance definitions<CR>', opts)
    vim.keymap.set('n', '<Leader>gt', '<CMD>Glance type_definitions<CR>', opts)
    vim.keymap.set('n', '<Leader>gi', '<CMD>Glance implementations<CR>', opts)
    vim.keymap.set('n', '<Leader>gr', '<CMD>Glance references<CR>', opts)
end)

lsp.setup()

require('rust-tools').setup({server = rust_lsp})


vim.diagnostic.config({
    virtual_text = true
})

-- completion symbols
vim.lsp.protocol.CompletionItemKind = {
    "   (Text) ",
    "   (Method)",
    "   (Function)",
    "   (Constructor)",
    " ﴲ  (Field)",
    "[] (Variable)",
    "   (Class)",
    " ﰮ  (Interface)",
    "   (Module)",
    " 襁 (Property)",
    "   (Unit)",
    "   (Value)",
    " 練 (Enum)",
    "   (Keyword)",
    "   (Snippet)",
    "   (Color)",
    "   (File)",
    "   (Reference)",
    "   (Folder)",
    "   (EnumMember)",
    " ﲀ  (Constant)",
    " ﳤ  (Struct)",
    "   (Event)",
    "   (Operator)",
    "   (TypeParameter)"
}

