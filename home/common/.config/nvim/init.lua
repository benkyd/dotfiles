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

-- Resize splits: the border moves in the direction of the key, whichever
-- side of it you're on
local function resize(key)
    local sideways = key == 'h' or key == 'l'
    local has_next = vim.fn.winnr(sideways and 'l' or 'j') ~= vim.fn.winnr()
    local grow = (key == 'l' or key == 'j') == has_next
    vim.cmd((sideways and 'vertical ' or '') .. 'resize ' .. (grow and '+3' or '-3'))
end
for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
    vim.keymap.set('n', '<A-C-' .. key .. '>', function() resize(key) end, { desc = 'Move split border' })
end
