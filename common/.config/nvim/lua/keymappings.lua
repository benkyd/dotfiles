    -- defaults
local opts = { noremap = true, silent = true }

-- paste in insert mode
vim.api.nvim_set_keymap('i', '<C-v>', '<Esc>"+pa', opts)

-- paste and keep the paste register
vim.api.nvim_set_keymap('', '<leader>p', '"_dP', opts)

-- vscode style quick peek at the tree
vim.api.nvim_set_keymap('n', '<C-b>', ":NvimTreeToggle<CR>", { noremap = true })

-- make ctrl-shift arrows line movement
vim.api.nvim_set_keymap('n', '<C-K>', 'ddkP', opts)
vim.api.nvim_set_keymap('v', '<C-K>', ':m \'<-2<CR>gv=gv', opts)
vim.api.nvim_set_keymap('n', '<C-J>', 'ddp', opts)
vim.api.nvim_set_keymap('v', '<C-J>', ':m \'>+1<CR>gv=gv', opts)

-- Mapping U to Redo.
vim.api.nvim_set_keymap('', 'U', '<C-r>', opts)
vim.api.nvim_set_keymap('', '<C-r>', '<NOP>', opts)

-- indent via Tab
vim.api.nvim_set_keymap('n', '<Tab>', '>>_', opts)
vim.api.nvim_set_keymap('n', '<S-Tab>', '<<_', opts)
vim.api.nvim_set_keymap('v', '<Tab>', '>>_', opts)
vim.api.nvim_set_keymap('v', '<S-Tab>', '<<_', opts)
vim.api.nvim_set_keymap('i', '<Tab>', '\t', opts)
vim.api.nvim_set_keymap('i', '<S-Tab>', '\b', opts)

