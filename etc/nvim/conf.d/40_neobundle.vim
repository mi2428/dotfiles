set nocompatible
filetype off

if has('vim_starting')
  set runtimepath+=~/.config/nvim/bundle/neobundle.vim/
  call neobundle#begin(expand('~/.config/nvim/bundle'))
  NeoBundleFetch 'Shougo/neobundle.vim'
endif

NeoBundle 'Shougo/deoplete.nvim'
NeoBundle 'Shougo/neosnippet'
NeoBundle 'Shougo/neosnippet-snippets'
NeoBundle 'davidhalter/jedi-vim'
NeoBundle 'Shougo/unite.vim'
" NeoBundle 'plasticboy/vim-markdown'
NeoBundle 'vim-syntastic/syntastic'

NeoBundle 'itchyny/lightline.vim'
" NeoBundle 'vim-airline/vim-airline'
NeoBundle 'miyakogi/seiya.vim'
NeoBundle 'scrooloose/nerdtree'
NeoBundle 'Shougo/vimfiler'
NeoBundle 'sudo.vim'
" NeoBundle 'haya14busa/incsearch.vim'

NeoBundle 'altercation/vim-colors-solarized'
" NeoBundle 'w0ng/vim-hybrid'
" NeoBundle 'tomasr/molokai'
" NeoBundle 'nanotech/jellybeans.vim'

NeoBundle 'tyru/open-browser.vim'
NeoBundle 'kannokanno/previm'
NeoBundle 'jeffkreeftmeijer/vim-numbertoggle'

NeoBundle 'lervag/vimtex'
NeoBundle 'thinca/vim-quickrun'
NeoBundle 'mattn/emmet-vim'
NeoBundle 'tomtom/tcomment_vim'
NeoBundle 'majutsushi/tagbar'
" NeoBundle 'mrtazz/simplenote.vim'

" NeoBundle 'vim-jp/vim-go-extra'
NeoBundle 'fatih/vim-go'
NeoBundle 'garyburd/go-explorer'
NeoBundle 'zchee/deoplete-go'

NeoBundle 'szw/vim-tags'
" NeoBundle 'alvan/vim-closetag'
NeoBundle 'othree/html5.vim'
" NeoBundle 'hali2u/vim-css3-syntax'
NeoBundle 'jelera/vim-javascript-syntax'
NeoBundle 'kchmck/vim-coffee-script'
NeoBundle 'tpope/vim-fugitive'
" NeoBundle 'airblad/vim-gitgutter'
NeoBundle 'cespare/vim-toml'

" NeoBundle 'vimtaku/hl_matchit.vim'
" NeoBundle 'thinca/vim-splash'

" NeoBundle 'basyura/TweetVim'
" NeoBundle 'basyura/twibill.vim'
" NeoBundle 'basyura/bitly.vim'
" NeoBundle 'mattn/webapi-vim'
" NeoBundle 'h1mesuke/unite-outline'


NeoBundle 'Shougo/vimproc.vim', {
\ 'build' : {
\     'windows' : 'tools\\update-dll-mingw',
\     'cygwin' : 'make -f make_cygwin.mak',
\     'mac' : 'make',
\     'linux' : 'make',
\     'unix' : 'gmake',
\    },
\ }

NeoBundleCheck

if has('vim_starting')
    call neobundle#end()
endif

filetype plugin indent on
