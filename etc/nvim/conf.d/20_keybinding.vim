nnoremap <C-j> <ESC>
inoremap <C-j> <ESC>
vnoremap <C-j> <ESC>
inoremap <silent><C-d> <DEL>
inoremap <expr><C-g> neocomplcache#undo_completion()
inoremap <expr><C-l> neocomplcache#complete_common_string()
" inoremap { {}<Left>
" inoremap [ []<Left>
" inoremap ( ()<Left>
" inoremap {<ENTER> {}<Left><CR><ESC><S-o>
" inoremap [<ENTER> []<Left><CR><ESC><S-o>
" inoremap (<ENTER> ()<Left><CR><ESC><S-o>

let mapleader = "\<Space>"
nnoremap <Leader>w :w<CR>
vmap <Leader>y "+y
vmap <Leader>d "+d
nmap <Leader>p "+p
nmap <Leader>P "+P
vmap <Leader>p "+p
vmap <Leader>P "+P

noremap <silent><S-Tab> :tabnew<CR>
noremap <Tab>k gT
noremap <Tab>j gt
noremap <silent><C-e> :NERDTreeToggle<CR>
noremap <C-n> :set relativenumber!<CR>
noremap <ESC><ESC> :nohlsearch<CR>
noremap <C-j><C-j> :nohlsearch<CR>
noremap x "_x
" noremap <C-j> :bnext<CR>
" noremap <C-k> :bprevious<CR>
" nnoremap qqq :QuickRun<CR>
