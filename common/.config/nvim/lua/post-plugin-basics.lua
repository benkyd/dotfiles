-- ################# Basic settings dependent on plugins ################ --

-- ================= Visualization ================= --

vim.o.termguicolors = true
vim.o.background = 'dark'

require('kanagawa').setup({
    undercurl = true,           -- enable undercurls
    commentStyle = { italic = true },
    functionStyle = {},
    keywordStyle = { italic = true},
    statementStyle = { bold = true },
    typeStyle = {},
    variablebuiltinStyle = { italic = true},
    transparent = false,        -- do not set background color
    dimInactive = false,        -- dim inactive window `:h hl-NormalNC`
    globalStatus = true,       -- adjust window separators highlight for laststatus=3
    terminalColors = true,      -- define vim.g.terminal_color_{0,17}
    colors = {
        bg = '#22222d',
    },
    overrides = {},
    theme = "default"           -- Load "default" theme or the experimental "light" theme
})

-- setup must be called before loading
vim.cmd("colorscheme kanagawa")

