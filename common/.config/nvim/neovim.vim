augroup vimrc
    autocmd!
    autocmd BufWritePost plugins.lua PackerCompile
    autocmd BufWritePost init.lua source <afile> | PackerCompile
augroup END

augroup vimload
    autocmd!
    autocmd VimEnter * lua require('fsplash').open_window()
augroup END

