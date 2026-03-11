if !has('nvim')
    colorscheme evening
endif

set confirm
set noswapfile
set termguicolors
set autoread

set clipboard=unnamedplus

augroup setup
  autocmd!
  " Triger `autoread` when files changes on disk
  autocmd FocusGained,BufEnter,CursorHold,CursorHoldI * if mode() != 'c' | checktime | endif
  " Notification after file change
  autocmd FileChangedShellPost *
    \ echohl WarningMsg | echo "File changed on disk. Buffer reloaded." | echohl None
augroup end

set scrolloff=4
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set smartindent
set autoindent
set smarttab
set wrap

set ignorecase
set smartcase
set incsearch
set hlsearch

set number
augroup numbertoggle
    autocmd!
    autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != "i" | set rnu   | endif
    autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
augroup END

" let g:netrw_banner=0
" let g:netrw_liststyle=3
" let g:netrw_browse_split=4
" let g:netrw_altv=1
" let g:netrw_winsize=25


set nolazyredraw
set updatetime=300
set ttimeoutlen=50
set timeoutlen=1000
set history=1000
set mouse=nv
set cursorline

set splitbelow
set splitright

set completeopt=menu,menuone,preview,noinsert,noselect
set guicursor=a:block,i:ver20,v-r:hor20

" The epico quickfix list
packadd cfilter
function! RemoveQFItem()
  let curqfidx = line('.') - 1
  let qfall = getqflist()
  call remove(qfall, curqfidx)
  call setqflist(qfall, 'r')
  execute curqfidx + 1 . "cfirst"
  :copen
endfunction
:command! RemoveQFItem :call RemoveQFItem()
" Use map <buffer> to only map dd in the quickfix window. Requires +localmap
autocmd FileType qf map <buffer> dd :RemoveQFItem<cr>

" The holy leader key
let g:mapleader=","
map <space> <leader>

" Drag lines
nn <C-K> ddkP
vn <C-K> :m '<-2<cr>gv=gv
nn <C-J> ddp
vn <C-J> :m '>+1<cr>gv=gv

" Take a peek at netrw
nn <C-b> :Lexplore<cr><C-w><S-l>:vertical resize 30<cr>

" Paste in insert mode
ino <C-v> <Esc>"+pa

" Clear search
nn <Esc> :nohlsearch<cr>

" Better redo
nn U <C-r>
nn <C-r> <nop>

" Peep the registers
nn <leader>r :Telescope registers<cr>
" Peep the marks
nn <leader>m :Telescope marks<cr>

" Paste and keep the " register
nn <leader>p "_dP

" on leader vs, run mksession! .vims
nn <leader>vs :mksession! .vims<cr>
nn <leader>vl :source .vims<cr>

