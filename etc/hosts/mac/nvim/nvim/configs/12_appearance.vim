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
