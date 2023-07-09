"augroup vimrc
    "autocmd!
    "autocmd BufWritePost plugins.lua PackerCompile
    "autocmd BufWritePost init.lua source <afile> | PackerCompile
"augroup END

let g:loaded_netrw = 1
let g:loaded_netrwPlugin = 1

augroup vimload
    autocmd!
    autocmd VimEnter * lua require('fsplash').open_window()
augroup END

