if has('nvim')
    colorscheme kanagawa
else
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

set nolazyredraw
set timeoutlen=600

let g:netrw_banner=0
let g:netrw_liststyle=3
let g:netrw_browse_split=4
let g:netrw_altv=1
let g:netrw_winsize=25

set history=1000
set updatetime=69
set mouse=nvi
set cursorline

set splitbelow
set splitright

set completeopt=menu,menuone,preview,noinsert,noselect
set guicursor=a:block,i:ver20,v-r:hor20

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
nn <lader>r :Telescope registers<cr>

" Paste and keep the " register
nn <leader>p "_dP
