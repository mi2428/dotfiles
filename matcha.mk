all:
	${PWD}/init/INSTALL -t linux
	${PWD}/init/INSTALL -t matcha
	ln -snf ${PWD}/bin ${HOME}/bin

install:
	${PWD}/init/INSTALL -t matcha
	${PWD}/init/neobundle -f -v vim
	${PWD}/init/neobundle -f -v nvim
	#${PWD}/init/zplug -f
	${PWD}/init/zsh-plugin -f
	${PWD}/init/fzf -f
	ln -snf ${PWD}/bin ${HOME}/bin

uninstall:
	${PWD}/init/UNINSTALL
