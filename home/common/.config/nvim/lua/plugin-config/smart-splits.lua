require('smart-splits').setup({
  -- windows skipped when working out resize geometry
  ignored_buftypes = {
    'nofile',
    'quickfix',
    'prompt',
  },
  ignored_filetypes = { 'NvimTree' },
  resize = {
    -- the default number of lines/columns to resize by at a time
    amount = 3,
    -- ignore these autocmd events (via :h eventignore) while resizing,
    -- since it involves visiting different buffers and windows
    ignored_events = {
      'BufEnter',
      'WinEnter',
    },
  },
  move = {
    -- whether to wrap to opposite side when cursor is at an edge
    -- e.g. by default, moving left at the left edge will jump
    -- to the rightmost window, and vice versa, same for up/down.
    at_edge = 'wrap',
    -- when moving cursor between splits left or right,
    -- place the cursor on the same row of the *screen*
    -- regardless of line numbers.
    same_row = false,
  },
})

-- resize splits
vim.keymap.set('', '<A-C-h>', require('smart-splits').resize_left)
vim.keymap.set('', '<A-C-j>', require('smart-splits').resize_down)
vim.keymap.set('', '<A-C-k>', require('smart-splits').resize_up)
vim.keymap.set('', '<A-C-l>', require('smart-splits').resize_right)

