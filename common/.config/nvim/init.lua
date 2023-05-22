DATA_PATH = vim.fn.stdpath('data')
CACHE_PATH = vim.fn.stdpath('cache')

vim.cmd('source ~/.vimrc')

vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })
vim.api.nvim_set_hl(0, "FloatBorder", { bg = "NONE" })
vim.api.nvim_set_hl(0, "CmpItemMenu", { bg = "NONE" })

require('plugins')

vim.cmd('source ~/.config/nvim/neovim.vim')

