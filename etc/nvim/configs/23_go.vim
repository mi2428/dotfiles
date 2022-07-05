autocmd! BufNewFile,BufRead *.go setlocal noexpandtab tabstop=4 shiftwidth=4

let g:go_fmt_command    = "goimports"
let g:go_fmt_autosave   = 1
let g:go_rename_command = "gopls"

" improves Go syntax highlighting
let g:go_highlight_array_whitespace_error    = 1
let g:go_highlight_chan_whitespace_error     = 1
let g:go_highlight_extra_types               = 1
let g:go_highlight_space_tab_error           = 1
let g:go_highlight_trailing_whitespace_error = 1
let g:go_highlight_operators                 = 1
let g:go_highlight_functions                 = 1
let g:go_highlight_function_arguments        = 1
let g:go_highlight_function_calls            = 1
let g:go_highlight_fields                    = 1
let g:go_highlight_types                     = 1
let g:go_highlight_build_constraints         = 1
let g:go_highlight_generate_tags             = 1
let g:go_highlight_variable_assignments      = 1
let g:go_highlight_variable_declarations     = 1
