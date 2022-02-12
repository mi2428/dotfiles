FROM ubuntu:21.10
LABEL maintainer "mi2428 <mi2428782020@gmail.com>"

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

ARG USER shizk
ARG USERHOME /home/$USER
ARG WORKDIR /work

RUN apt-get update \
 && apt-get upgrade -y \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg-agent \
      iproute2 \
      locales \
      make \
      software-properties-common \
      sudo \
      toilet \
 && add-apt-repository ppa:neovim-ppa/unstable \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends neovim

USER $USER
WORKDIR $USERHOME

RUN git clone --depth 1 https://github.com/mi2428/dotfiles

USER root

RUN DEBIAN_FRONTEND=noninteractive \
    xargs apt-get install -y --no-install-recommends < $USERHOME/dotfiles/init/pkgs/apt.txt \
 && ln -sf /usr/bin/batcat /usr/bin/bat

USER $USER

RUN sh -c 'curl -fLo $HOME/.local/share/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' \
 && xargs pip3 install --upgrade < $USERHOME/dotfiles/init/pkgs/python3-pip.txt \
 && xargs cargo install < $USERHOME/dotfiles/init/pkgs/cargo.txt

RUN curl -fsSL https://deno.land/install.sh | sh \
 && mkdir -p $USERHOME/.local/share/zsh \
 && git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting $USERHOME/.local/share/zsh/zsh-syntax-highlighting \
 && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions $USERHOME/.local/share/zsh/zsh-autosuggestions \
 && git clone --depth 1 https://github.com/zsh-users/zsh-completions $USERHOME/.local/share/zsh/zsh-completions \
 && git clone --depth 1 https://github.com/junegunn/fzf.git .fzf \
 && ./.fzf/install --all

RUN chsh -s /bin/zsh

WORKDIR $WORKDIR
USER root

RUN cp $USERHOME/dotfiles/var/entrypoint.sh /sbin/entrypoint.sh \
 && chmod +x /sbin/entrypoint.sh

ENTRYPOINT ["/sbin/entrypoint.sh"]
