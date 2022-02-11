FROM ubuntu:21.10
LABEL maintainer "mi2428 <mi2428782020@gmail.com>"

RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
      git \
      make

RUN git clone https://github.com/mi2428/dotfiles


