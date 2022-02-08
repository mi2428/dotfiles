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

autocmd InsertEnter * :set norelativenumber
autocmd InsertLeave * :set relativenumber

"" https://gist.github.com/atton/db007474075b47f6917933cc2aee924a
function! s:sudo_write_current_buffer() abort
  if has('nvim')
    let s:askpass_path = '/tmp/askpass'
    let s:password     = inputsecret("Enter Password: ")
    let $SUDO_ASKPASS  = s:askpass_path

    try
      call delete(s:askpass_path)
      call writefile(['#!/bin/sh'],                 s:askpass_path, 'a')
      call writefile(["echo '" . s:password . "'"], s:askpass_path, 'a')
      call setfperm(s:askpass_path, "rwx------")
      write ! sudo -A tee % > /dev/null
    finally
      unlet s:password
      call delete(s:askpass_path)
    endtry
  else
    write ! sudo tee % > /dev/null
  endif
endfunction
command! SudoWriteCurrentBuffer call s:sudo_write_current_buffer()


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

"" Dark deno-powered completion framework for neovim/Vim8
"" https://github.com/Shougo/ddc.vim
Plug 'Shougo/ddc.vim'
Plug 'vim-denops/denops.vim'
Plug 'Shougo/ddc-around'
Plug 'Shougo/ddc-matcher_head'
Plug 'Shougo/ddc-sorter_rank'

"" VimTeX is a modern Vim and Neovim filetype and syntax plugin for LaTeX files.
"" https://github.com/lervag/vimtex
Plug 'lervag/vimtex'

"" the latest version of the Jinja2 syntax file for vim with the ability to detect either HTML or Jinja.
"" https://github.com/Glench/Vim-Jinja2-Syntax
Plug 'Glench/Vim-Jinja2-Syntax'

"" fzf is a general-purpose command-line fuzzy finder.
"" https://github.com/junegunn/fzf
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }

call plug#end()


filetype plugin indent on
