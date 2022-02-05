set termguicolors
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

nnoremap <silent>;; :tabnew<CR>
nnoremap <silent><Tab> :tabnext<CR>
nnoremap <silent><S-Tab> :tabprevious<CR>
nnoremap <silent><C-l> :<C-u>nohlsearch<CR>
xnoremap p "_xP


call plug#begin()

"" A port of the Material color scheme for Vim/Neovim.
"" https://github.com/kaicataldo/material.vim
Plug 'kaicataldo/material.vim', { 'branch': 'main' }

"" A light and configurable statusline/tabline plugin for Vim
"" https://github.com/itchyny/lightline.vim
Plug 'itchyny/lightline.vim'

"" This plugin adds indentation guides to all lines (including empty lines).
"" https://github.com/lukas-reineke/indent-blankline.nvim
Plug 'lukas-reineke/indent-blankline.nvim'


"" Defx is a dark powered plugin for Neovim/Vim to browse files. It replaces the deprecated vimfiler plugin.
"" https://github.com/Shougo/defx.nvim
Plug 'Shougo/defx.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'kristijanhusak/defx-icons'
Plug 'ryanoasis/vim-devicons'
Plug 'kristijanhusak/defx-git'


call plug#end()


let g:material_terminal_italics = 0
let g:material_theme_style = 'default'

"" Fix italics
if !has('nvim')
  let &t_ZH="\e[3m"
  let &t_ZR="\e[23m"
endif

autocmd ColorScheme * highlight Normal ctermbg=NONE guibg=NONE
autocmd ColorScheme * highlight LineNr ctermfg=246 guifg=#949494
autocmd ColorScheme * highlight CursorLineNr ctermfg=255 ctermbg=009 cterm=bold guifg=#eeeeee guibg=#ff5f00 gui=bold
autocmd ColorScheme * highlight Comment ctermfg=244 guifg=#808080
autocmd ColorScheme * highlight Visual ctermbg=033 guibg=#0087ff
autocmd ColorScheme * highlight NonText ctermfg=239 ctermbg=NONE guifg=#4e4e4e guibg=NONE
autocmd ColorScheme * highlight SpecialKey ctermfg=239 guifg=#4e4e4e

colorscheme material
syntax enable


autocmd InsertEnter * :set norelativenumber
autocmd InsertLeave * :set relativenumber


let g:lightline = {
  \ 'colorscheme': 'material',
  \ 'active': {
  \   'left': [ [ 'mode', 'paste' ],
  \             [ 'gitbranch', 'readonly', 'filename', 'modified' ] ],
  \   'right': [ [ 'lineinfo', 'char_counter' ],
  \              [ 'percent' ],
  \              [ 'fileformat', 'fileencoding', 'filetype' ] ],
  \ },
  \ 'component_function': {
  \   'gitbranch': 'FugitiveHead'
  \ },
  \ }




autocmd FileType defx call s:defx_my_settings()

function! s:defx_my_settings() abort
  nnoremap <silent><buffer><expr> <CR>
   \ defx#do_action('open')
  nnoremap <silent><buffer><expr> c
  \ defx#do_action('copy')
  nnoremap <silent><buffer><expr> m
  \ defx#do_action('move')
  nnoremap <silent><buffer><expr> p
  \ defx#do_action('paste')
  nnoremap <silent><buffer><expr> l
  \ defx#do_action('open')
  nnoremap <silent><buffer><expr> t
  \ defx#do_action('open','tabnew')
  nnoremap <silent><buffer><expr> E
  \ defx#do_action('open', 'vsplit')
  nnoremap <silent><buffer><expr> P
  \ defx#do_action('open', 'pedit')
  nnoremap <silent><buffer><expr> o
  \ defx#do_action('open_or_close_tree')
  nnoremap <silent><buffer><expr> K
  \ defx#do_action('new_directory')
  nnoremap <silent><buffer><expr> N
  \ defx#do_action('new_file')
  nnoremap <silent><buffer><expr> M
  \ defx#do_action('new_multiple_files')
  nnoremap <silent><buffer><expr> C
  \ defx#do_action('toggle_columns',
  \                'mark:indent:icon:filename:type:size:time')
  nnoremap <silent><buffer><expr> S
  \ defx#do_action('toggle_sort', 'time')
  nnoremap <silent><buffer><expr> d
  \ defx#do_action('remove')
  nnoremap <silent><buffer><expr> r
  \ defx#do_action('rename')
  nnoremap <silent><buffer><expr> !
  \ defx#do_action('execute_command')
  nnoremap <silent><buffer><expr> x
  \ defx#do_action('execute_system')
  nnoremap <silent><buffer><expr> yy
  \ defx#do_action('yank_path')
  nnoremap <silent><buffer><expr> .
  \ defx#do_action('toggle_ignored_files')
  nnoremap <silent><buffer><expr> ;
  \ defx#do_action('repeat')
  nnoremap <silent><buffer><expr> h
  \ defx#do_action('cd', ['..'])
  nnoremap <silent><buffer><expr> ~
  \ defx#do_action('cd')
  nnoremap <silent><buffer><expr> q
  \ defx#do_action('quit')
  nnoremap <silent><buffer><expr> <Space>
  \ defx#do_action('toggle_select') . 'j'
  nnoremap <silent><buffer><expr> *
  \ defx#do_action('toggle_select_all')
  nnoremap <silent><buffer><expr> j
  \ line('.') == line('$') ? 'gg' : 'j'
  nnoremap <silent><buffer><expr> k
  \ line('.') == 1 ? 'G' : 'k'
  nnoremap <silent><buffer><expr> <C-l>
  \ defx#do_action('redraw')
  nnoremap <silent><buffer><expr> <C-g>
  \ defx#do_action('print')
  nnoremap <silent><buffer><expr> cd
  \ defx#do_action('change_vim_cwd')
endfunction

call defx#custom#option('_', {
  \ 'winwidth': 40,
  \ 'split': 'vertical',
  \ 'direction': 'topleft',
  \ 'show_ignored_files': 1,
  \ 'buffer_name': 'exproler',
  \ 'toggle': 1,
  \ 'resume': 1,
  \ 'columns': 'indent:space:git:space:icons:space:filename:space:mark',
  \ })


call defx#custom#column('git', 'indicators', {
  \ 'Modified'  : '✹',
  \ 'Staged'    : '✚',
  \ 'Untracked' : '✭',
  \ 'Renamed'   : '➜',
  \ 'Unmerged'  : '═',
  \ 'Ignored'   : '☒',
  \ 'Deleted'   : '✖',
  \ 'Unknown'   : '?'
  \ })


nnoremap <silent>f :<C-u>Defx<CR>

autocmd BufWritePost * call defx#redraw()
autocmd BufEnter * call defx#redraw()

