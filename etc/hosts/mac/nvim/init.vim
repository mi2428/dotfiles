set background=dark
if !has('gui_running')
  set t_Co=256
endif

set encoding=utf-8
set fileencoding=utf-8
set ttimeout
set ttimeoutlen=0
set history=1000

set number
set relativenumber
set cursorline
set showtabline=2
set noshowmode
set mouse=a

set autoindent
set smartindent
set expandtab
set tabstop=2
set shiftwidth=2
set laststatus=2
set scrolloff=8

set hlsearch
set incsearch
set smartcase
set expandtab
set ignorecase

set list
set listchars=tab:»-,trail:-,eol:↲,extends:»,precedes:«,nbsp:%

set foldmethod=marker
set foldlevel=1
set foldnestmax=2
set foldcolumn=1
set foldclose=all



call plug#begin()

"" A port of the Material color scheme for Vim/Neovim.
"" https://github.com/kaicataldo/material.vim
Plug 'kaicataldo/material.vim', { 'branch': 'main' }

"" A light and configurable statusline/tabline plugin for Vim
"" https://github.com/itchyny/lightline.vim
Plug 'itchyny/lightline.vim'

call plug#end()



let g:material_terminal_italics = 0
let g:material_theme_style = 'default'

"" Fix italics
if !has('nvim')
  let &t_ZH="\e[3m"
  let &t_ZR="\e[23m"
endif

autocmd ColorScheme * highlight CursorLineNr term=bold ctermfg=255 ctermbg=009
autocmd ColorScheme * highlight Comment ctermfg=244
autocmd ColorScheme * highlight NonText ctermfg=239 ctermbg=NONE
autocmd ColorScheme * highlight SpecialKey ctermfg=239 ctermbg=NONE

colorscheme material
syntax enable


autocmd InsertEnter * :set norelativenumber
autocmd InsertLeave * :set relativenumber


let g:lightline = {
  \ 'colorscheme': 'material_vim',
  \ 'active': {
  \   'left': [ [ 'mode', 'paste' ],
  \             [ 'gitbranch', 'readonly', 'filename', 'modified' ] ]
  \ },
  \ 'component_function': {
  \   'gitbranch': 'FugitiveHead'
  \ },
  \ }


