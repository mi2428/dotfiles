FROM ubuntu:21.10
LABEL maintainer "mi2428 <sh@mi2428.io>"
LABEL org.opencontainers.image.source https://github.com/mi2428/dotfiles

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN apt-get update \
 && apt-get upgrade -y \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gnupg-agent \
      iproute2 \
      language-pack-ja \
      locales \
      make \
      software-properties-common \
      sudo \
      toilet \
 && add-apt-repository ppa:neovim-ppa/unstable \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y neovim

RUN groupadd wheel \
 && echo '%wheel ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers \
 && locale-gen en_US.UTF-8 ja_JP.UTF-8

WORKDIR /etc/skel
RUN git clone --depth 1 https://github.com/mi2428/dotfiles \
 && cd dotfiles \
 && HOME=/etc/skel \
    make ubuntu-server \
 && cd .. \
 && git clone --depth 1 https://github.com/junegunn/fzf.git .fzf \
 && HOME=/etc/skel \
    ./.fzf/install --all

RUN cp ./dotfiles/var/entrypoint.sh /sbin/entrypoint.sh \
 && chmod +x /sbin/entrypoint.sh

ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/bin/zsh", "--login"]
