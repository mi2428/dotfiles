let g:lightline={
\   'colorscheme':'solarized',
\   'active': {
\       'left': [
\           ['mode', 'paste'],
\           ['fugitive', 'filename'],
\           ['readonly', 'modified']
\       ],
\       'right': [
\           ['lineinfo', 'char_counter'],
\           ['percent'],
\           ['fileformat', 'fileencoding', 'filetype'],
\       ],
\   },
\   'component': {
\       'modified': '%{&filetype=="help"?"":&readonly?"(>_< )( >_<)":&modified?"〆(. . )":&modifiable?"(-_-)zzz":"(o_o?)"}',
\   },
\   'separator': { 'left':'', 'right':''},
\   'subseparator': { 'left':'|', 'right':'|'}
\}
