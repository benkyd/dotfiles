local lspconfig = require('lspconfig');

require('mason').setup()
require('mason-lspconfig').setup({
    ensure_installed = { 'clangd' }
})

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

local capabilities = require('cmp_nvim_lsp').default_capabilities(vim.lsp.protocol.make_client_capabilities())

local on_attatch = function(_, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
end

require('mason-lspconfig').setup_handlers({
    function(server)
        lspconfig[server].setup({
            on_attatch = on_attatch,
            capabilities = capabilities,
        })
    end,
})

require('rust-tools').setup {
    server = {
        on_attatch = on_attatch,
        capabilities = capabilities,
    }
}

-- diagnostic symbols
local signs = { Error = "", Warn = "", Hint = "", Info = "" }
for type, icon in pairs(signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

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
