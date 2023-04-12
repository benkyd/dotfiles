
require("nvim-tree").setup({
    hijack_unnamed_buffer_when_opening = true,
    --open_on_setup = false,
    --open_on_setup_file = false,
    update_focused_file = {
        enable = true,
    },
    view = {
        width = 35,
        side = "right",
    },
    git = {
        ignore = false,
    },
    filters = {
        dotfiles = false,
    }
})

