for f in glob('$HOME/.config/nvim/configs/*.vim', 0, 1)
  execute 'source' f
endfor
