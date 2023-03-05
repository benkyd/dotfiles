-- defaults
local opts = { noremap = true, silent = true }

-- copy
vim.api.nvim_set_keymap('', '<C-c>', '"+y', opts)
-- paste
vim.api.nvim_set_keymap('', '<C-v>', '"+p', opts)
-- cut
vim.api.nvim_set_keymap('', '<C-x>', '"+d', opts)
-- paste in insert mode
vim.api.nvim_set_keymap('i', '<C-v>', '<Esc>"+pa', opts)

-- vscode style quick peek at the tree
vim.api.nvim_set_keymap('n', '<C-b>', ":Lexplore<CR> :vertical resize 30<CR>", { noremap = true })

-- make ctrl-shift arrows line movement
vim.api.nvim_set_keymap('n', '<C-A-Up>', 'ddkP', opts)
vim.api.nvim_set_keymap('v', '<C-A-Up>', ':m \'<-2<CR>gv=gv', opts)
vim.api.nvim_set_keymap('n', '<C-A-Down>', 'ddp', opts)
vim.api.nvim_set_keymap('v', '<C-A-Down>', ':m \'>+1<CR>gv=gv', opts)

-- stay in normal mode after inserting a new line
vim.api.nvim_set_keymap('', 'o', 'o <Bs><Esc>', opts)
vim.api.nvim_set_keymap('', 'O', 'O <Bs><Esc>', opts)

-- mapping that opens .vimrc in a new tab for quick editing
vim.api.nvim_set_keymap('n', '<Leader>ev', '<Cmd>tabe $MYVIMRC<CR>', opts)

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

-- window movement
vim.api.nvim_set_keymap('', '<C-w><S-Left>', '<C-w><S-h>', opts)
vim.api.nvim_set_keymap('', '<C-w><S-Down>', '<C-w><S-j>', opts)
vim.api.nvim_set_keymap('', '<C-w><S-Up>', '<C-w><S-k>', opts)
vim.api.nvim_set_keymap('', '<C-w><S-Right>', '<C-w><S-l>', opts)

-- jumping back and forth
vim.api.nvim_set_keymap('', '<C-K>', '<C-O>', opts)
vim.api.nvim_set_keymap('', '<C-L>', '<C-I>', opts)

-- LSP
vim.api.nvim_set_keymap('n', 'gD', '<Cmd>lua vim.lsp.buf.definition()<CR>', opts)
vim.api.nvim_set_keymap('n', 'gT', '<Cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
vim.api.nvim_set_keymap('n', 'gI', '<Cmd>lua vim.lsp.buf.implementation()<CR>', opts)
vim.api.nvim_set_keymap('n', 'gR', '<Cmd>lua vim.lsp.buf.references()<CR>', opts)
-- Glance LSP
vim.api.nvim_set_keymap('n', 'gd', '<CMD>Glance definitions<CR>', opts)
vim.api.nvim_set_keymap('n', 'gt', '<CMD>Glance type_definitions<CR>', opts)
vim.api.nvim_set_keymap('n', 'gi', '<CMD>Glance implementations<CR>', opts)
vim.api.nvim_set_keymap('n', 'gr', '<CMD>Glance references<CR>', opts)

