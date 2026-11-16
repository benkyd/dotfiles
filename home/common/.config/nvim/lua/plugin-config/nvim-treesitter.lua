-- macOS: if a newer SDK than the active Xcode toolchain is installed (e.g. a macOS 27 SDK
-- under /Library/Developer/CommandLineTools with Xcode 26), plain `cc` picks that SDK and
-- the linker rejects it ("unknown architecture arm64e.x1"), so every parser build fails.
-- Pin builds spawned from nvim to the SDK that belongs to the active toolchain.
if vim.fn.has('mac') == 1 and (vim.env.SDKROOT or '') == '' then
    local out = vim.system({ 'xcrun', '--sdk', 'macosx', '--show-sdk-path' }, { text = true }):wait(5000)
    local sdk = out.code == 0 and vim.trim(out.stdout) or ''
    if sdk ~= '' then
        vim.env.SDKROOT = sdk
    end
end

-- nvim-treesitter `main` branch: it only installs parsers/queries now,
-- highlighting is neovim's own vim.treesitter.start().
-- Needs `tree-sitter-cli` (>= 0.26.1) and a C compiler to build parsers.
require('nvim-treesitter').install({
    "c",
    "cpp",
    "rust",
    "toml",
    "zig",
    "lua",
    "python",
    "javascript",
    "typescript",
    "html",
    "css",
    "bash",
    "json",
    "yaml",
    "markdown",
    "markdown_inline",
})

-- Highlight any filetype we have a parser for (bundled or installed)
vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('treesitter-start', { clear = true }),
    callback = function(args)
        pcall(vim.treesitter.start, args.buf)
    end,
})

require('nvim-treesitter-textobjects').setup({
    select = { lookahead = true },
    move = { set_jumps = true },
})

local select = require('nvim-treesitter-textobjects.select')
for keys, obj in pairs({
    ['af'] = '@function.outer',
    ['if'] = '@function.inner',
    ['ac'] = '@class.outer',
    ['ic'] = '@class.inner',
    ['aa'] = '@parameter.outer',
    ['ia'] = '@parameter.inner',
}) do
    vim.keymap.set({ 'x', 'o' }, keys, function()
        select.select_textobject(obj, 'textobjects')
    end)
end

local move = require('nvim-treesitter-textobjects.move')
for keys, m in pairs({
    [']m'] = { move.goto_next_start, '@function.outer' },
    [']]'] = { move.goto_next_start, '@class.outer' },
    ['[m'] = { move.goto_previous_start, '@function.outer' },
    ['[['] = { move.goto_previous_start, '@class.outer' },
}) do
    vim.keymap.set({ 'n', 'x', 'o' }, keys, function()
        m[1](m[2], 'textobjects')
    end)
end

local swap = require('nvim-treesitter-textobjects.swap')
vim.keymap.set('n', '<leader>a', function() swap.swap_next('@parameter.inner') end)
vim.keymap.set('n', '<leader>A', function() swap.swap_previous('@parameter.inner') end)
