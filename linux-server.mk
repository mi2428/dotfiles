all:
	${PWD}/init/INSTALL -t linux-server
	ln -snf ${PWD}/bin ${HOME}/bin

install:
	${PWD}/init/INSTALL -t linux-server
	${PWD}/init/neobundle -f -v vim
	${PWD}/init/neobundle -f -v nvim
	${PWD}/init/zsh-plugin -f
	${PWD}/init/fzf -f
	ln -snf ${PWD}/bin ${HOME}/bin
