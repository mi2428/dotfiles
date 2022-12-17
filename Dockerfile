FROM ubuntu:22.04
LABEL maintainer "mi2428 <sh@mi2428.io>"
LABEL org.opencontainers.image.source https://github.com/mi2428/dotfiles

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

## only effective in x86_64 image
RUN sed -i".bak" -e 's/\/\/archive.ubuntu.com/\/\/ftp.jaist.ac.jp/g' /etc/apt/sources.list 

RUN apt-get update \
 && apt-get upgrade -y \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
      apt-utils \
      ca-certificates \
      language-pack-ja \
      locales \
      software-properties-common \
 && locale-gen en_US.UTF-8 ja_JP.UTF-8 \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
      curl \
      git \
      gnupg-agent \
      iproute2 \
      make \
      sudo \
      toilet \
 && add-apt-repository ppa:neovim-ppa/unstable \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y neovim

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > /tmp/rustup.sh \
 && chmod +x /tmp/rustup.sh \
 && HOME=/etc/skel \
    /tmp/rustup.sh -y

RUN groupadd wheel \
 && echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

WORKDIR /etc/skel
RUN git clone --depth 1 https://github.com/mi2428/dotfiles \
 && cd dotfiles \
 && HOME=/etc/skel \
    make ubuntu-docker

RUN cp ./dotfiles/var/docker/entrypoint.sh /sbin/entrypoint.sh \
 && chmod +x /sbin/entrypoint.sh

Run apt-get clean \
 && rm -rf /var/lib/apt/lists/*

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/bin/zsh", "--login"]
