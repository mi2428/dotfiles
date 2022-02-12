FROM ubuntu:21.10
LABEL maintainer "mi2428 <mi2428782020@gmail.com>"

ENV HOSTNAME dotfiles
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /root

RUN apt-get update \
 && apt-get upgrade -y \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg-agent \
      locales \
      make \
      iproute2 \
      software-properties-common \
      sudo \
      toilet

RUN locale-gen en_US.UTF-8  
RUN git clone --depth 1 https://github.com/mi2428/dotfiles

WORKDIR /root/dotfiles

RUN add-apt-repository ppa:neovim-ppa/unstable \
 && apt-get update \
 && apt-get install -y neovim

RUN make ubuntu-server

WORKDIR /root

RUN git clone --depth 1 https://github.com/junegunn/fzf.git .fzf \
 && ./.fzf/install --all

RUN chsh -s /bin/zsh \
 && cp dotfiles/var/entrypoint.sh /sbin/entrypoint.sh

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["--login"]
