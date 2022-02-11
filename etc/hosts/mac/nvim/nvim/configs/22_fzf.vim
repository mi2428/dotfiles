let $FZF_DEFAULT_OPTS='--inline-info --preview-window=right:60%:wrap --color=fg:252,fg+:233,bg+:002,preview-fg:252,prompt:226,pointer:007,info:247,spinner:011,header:009,gutter:237,hl:220,hl+:231'
let $FZF_DEFAULT_COMMAND="rg --files --hidden --glob '!.git/**'"
let g:fzf_layout = {'up':'~90%', 'window': { 'width': 0.8, 'height': 0.8,'yoffset':0.5,'xoffset': 0.5, 'border': 'sharp' } }
let mapleader = "\<Space>"

nnoremap <silent> <leader>f :Files<CR>
nnoremap <silent> <leader>g :GFiles<CR>
nnoremap <silent> <leader>G :GFiles?<CR>
nnoremap <silent> <leader>b :Buffers<CR>
nnoremap <silent> <leader>h :History<CR>
nnoremap <silent> <leader>r :Rg<CR>
