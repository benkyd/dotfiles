require('obsidian').setup({
    dir = '~/Obsidian',
    completion = {
        nvim_cmp = true,  -- if using nvim-cmp, otherwise set to false
    },
    follow_url_func = function(url)
      -- Open the URL in the default web browser.
       vim.fn.jobstart({'xdg-open', url})  -- linux
    end,
})

vim.keymap.set('n', 'go', function()
    if require('obsidian').util.cursor_on_markdown_link() then
        return '<cmd>ObsidianFollowLink<CR>'
    else
        return 'go'
    end
end, { noremap = false, expr = true })

