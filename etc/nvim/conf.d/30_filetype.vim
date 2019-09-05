augroup fileType
  autocmd BufRead,BufNewFile *.js setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.json setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.html setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.erb setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.rb setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.css setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.yml setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.yaml setlocal tabstop=2 shiftwidth=2 softtabstop=2
  autocmd BufRead,BufNewFile *.tex setlocal commentstring=%%s
  autocmd BufRead,BufNewFile *.go setlocal tabstop=2 shiftwidth=2 softtabstop=2 noexpandtab
  autocmd BufRead,BufNewFile *.coffee setlocal ft=coffee
augroup end

augroup binaryFile
  autocmd!
  autocmd BufReadPre  *.bin let &binary =1
  autocmd BufReadPre  *.img let &binary =1
  autocmd BufReadPost * if &binary | silent %!xxd -g 1
  autocmd BufReadPost * set ft=xxd | endif
  autocmd BufWritePre * if &binary | %!xxd -r | endif
  autocmd BufWritePost * if &binary | silent %!xxd -g 1
  autocmd BufWritePost * set nomod | endif
augroup END
