-- Settings and keymaps shared with plain Vim live in ~/.vimrc
vim.cmd.source('~/.vimrc')

vim.g.loaded_netrw = 1 -- fyler and oil replace netrw
vim.g.loaded_netrwPlugin = 1
vim.o.colorcolumn = '80'
vim.o.winborder = 'rounded' -- hover, diagnostic and completion popups

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
    vim.fn.system({
        'git', 'clone', '--filter=blob:none', '--branch=stable',
        'https://github.com/folke/lazy.nvim.git', lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)
require('lazy').setup(require('plugins'))

-- Comments use the built-in gc; these keep the old leader keys working
vim.keymap.set({ 'n', 'x' }, '<leader>c', 'gc', { remap = true, desc = 'Comment' })
vim.keymap.set('n', '<leader>cc', 'gcc', { remap = true, desc = 'Comment line' })

-- Resize splits
vim.keymap.set('n', '<A-C-h>', '<Cmd>vertical resize -3<CR>', { desc = 'Narrower' })
vim.keymap.set('n', '<A-C-l>', '<Cmd>vertical resize +3<CR>', { desc = 'Wider' })
vim.keymap.set('n', '<A-C-j>', '<Cmd>resize -3<CR>', { desc = 'Shorter' })
vim.keymap.set('n', '<A-C-k>', '<Cmd>resize +3<CR>', { desc = 'Taller' })
