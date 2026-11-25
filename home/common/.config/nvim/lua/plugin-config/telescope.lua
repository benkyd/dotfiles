local builtin = require('telescope.builtin')
local actions = require('telescope.actions')

vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Find files' })
vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Grep' })
vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Buffers' })
vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Help' })
vim.keymap.set('n', '<leader>r', builtin.registers, { desc = 'Registers' })
vim.keymap.set('n', '<leader>m', builtin.marks, { desc = 'Marks' })

local keys = {
    ['<C-j>'] = actions.move_selection_next,
    ['<C-k>'] = actions.move_selection_previous,
    ['<C-q>'] = actions.smart_send_to_qflist + actions.open_qflist,
    ['<C-d>'] = actions.delete_buffer,
}

require('telescope').setup({
    defaults = {
        prompt_prefix = ' ',
        selection_caret = ' ',
        sorting_strategy = 'ascending',
        layout_strategy = 'vertical',
        layout_config = {
            vertical = { mirror = true, preview_height = 0.5 }, -- prompt, results, preview top to bottom
        },
        file_ignore_patterns = { 'node_modules/.*' },
        borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
        mappings = {
            i = vim.tbl_extend('force', keys, { ['<CR>'] = actions.select_default + actions.center }),
            n = keys,
        },
    },
    pickers = {
        find_files = { hidden = true },
    },
    extensions = {
        ['ui-select'] = { require('telescope.themes').get_ivy({ layout_config = { height = 0.4 } }) },
    },
})

require('telescope').load_extension('ui-select')
