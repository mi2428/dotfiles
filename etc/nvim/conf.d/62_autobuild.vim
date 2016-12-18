command! Run call s:Run()
nmap <F12> :Run<CR>
function! s:Run()
	let e = expand("%:e")
	if e == "c"
		:Gcc
	elseif e == "py"
		:Python
	elseif e == "go"
		:Gccgo
	elseif e == "asciidoc"
		:Asciidoctor
	elseif e == "adoc"
		:Asciidoctor
	endif
endfunction

command! Asciidoctor call s:Asciidoctor()
function! s:Asciidoctor()
	:!asciidoctor %
endfunction

command! Gcc call s:Gcc()
function! s:Gcc()
	:!gcc % -o %:r.out
	":!%:r.out
	:!./%:r.out
endfunction

command! Python call s:Python()
function! s:Python()
	:!python %
endfunction

command! Gccgo call s:Gccgo()
function! s:Gccgo()
	:!go build %
	:!./%:r
endfunction

