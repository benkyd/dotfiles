-- ################# Basic settings dependent on plugins ################ --
-- ==================== KEYS ======================= --

-- Harpoon
--vim.cmd('highlight! HarpoonNumberActive guibg=NONE guifg=#f5bde6')
--vim.cmd('highlight! HarpoonNumberInactive guibg=NONE guifg=#6e738d')
--vim.cmd('highlight! TabLineFill guibg=#24273a guifg=#cad3f5')

vim.keymap.set("n", "<leader>hh", require("harpoon.ui").toggle_quick_menu, { desc = "Toggle Harpoon Menu" })
vim.keymap.set("n", "<leader>hg", require("harpoon.mark").toggle_file, { desc = "Add file to harpoon list" })
for pos = 1, 9 do
    vim.keymap.set("n", "<leader>h" .. pos, function()
        require("harpoon.ui").nav_file(pos)
    end, { desc = "Move to harpoon mark #" .. pos })
end

-- Zen mode
vim.keymap.set("n", "<leader>z", function()
    require("zen-mode").toggle()
end, { desc = "Toggle Zen Mode" })

-- ================= Visualization ================= --

vim.o.termguicolors = true
vim.o.background = 'dark'

--require('kanagawa').setup({
    --undercurl = true,           -- enable undercurls
    --commentStyle = { italic = true },
    --functionStyle = {},
    --keywordStyle = { italic = true},
    --statementStyle = { bold = true },
    --typeStyle = {},
    --variablebuiltinStyle = { italic = true},
    --transparent = false,        -- do not set background color
    --dimInactive = false,        -- dim inactive window `:h hl-NormalNC`
    --globalStatus = true,       -- adjust window separators highlight for laststatus=3
    --terminalColors = true,      -- define vim.g.terminal_color_{0,17}
    --colors = {
        --bg = '#22222d',
    --},
    --overrides = {},
    --theme = "default"           -- Load "default" theme or the experimental "light" theme
--})

-- setup must be called before loading
vim.cmd("colorscheme kanagawa")

vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
vim.api.nvim_set_hl(0, "CmpItemMenu", { bg = "NONE" })

