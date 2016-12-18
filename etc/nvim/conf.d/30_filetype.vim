augroup fileType
  autocmd BufRead,BufNewFile *.js setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.json setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.html setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.erb setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.rb setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.css setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.yml setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.tex setlocal commentstring=%%s
  autocmd BufRead,BufNewFile *.go setlocal tabstop=2 shiftwidth=2 softtabstop=2 noexpandtab
  autocmd BufRead,BufNewFile *.coffee setlocal ft=coffee
augroup end
