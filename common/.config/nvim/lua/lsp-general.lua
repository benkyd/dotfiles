local lsp = require('lsp-zero')
local cmp = require ('cmp')
lsp.preset("recommended")

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

local cmp = require('cmp')
local cmp_select = { behavior = cmp.SelectBehavior.Select }
local cmp_mappings = lsp.defaults.cmp_mappings({
    ["<Tab>"] = cmp.mapping.select_next_item(cmp_select),
    ["<S-Tab>"] = cmp.mapping.select_prev_item(cmp_select),
    ["<CR>"] = cmp.mapping.confirm({
        behavior = cmp.ConfirmBehavior.Replace,
        select = true,
    }),
})

lsp.setup_nvim_cmp({
    mapping = cmp_mappings,
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

lsp.set_preferences({
    suggest_lsp_servers = false,
    sign_icons = {
        error = '',
        warn = '',
        hint = '',
        info = ''
    }
})


require('mason').setup()
require('mason-lspconfig').setup({
    ensure_installed = { 'clangd'}
})


lsp.on_attach(function(_, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', '<Leader>gD', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
    vim.keymap.set('n', '<Leader>gT', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
    vim.keymap.set('n', '<Leader>gI', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
    vim.keymap.set('n', '<Leader>gR', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)
    -- Glance LSP
    vim.keymap.set('n', '<Leader>gd', '<CMD>Glance definitions<CR>', opts)
    vim.keymap.set('n', '<Leader>gt', '<CMD>Glance type_definitions<CR>', opts)
    vim.keymap.set('n', '<Leader>gi', '<CMD>Glance implementations<CR>', opts)
    vim.keymap.set('n', '<Leader>gr', '<CMD>Glance references<CR>', opts)
end)

lsp.setup()

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

