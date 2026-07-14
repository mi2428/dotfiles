# hadolint global ignore=DL3008
FROM ubuntu:26.04 AS runtime-base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      iproute2 \
      iputils-ping \
      locales \
      procps \
      sudo \
      toilet \
 && locale-gen en_US.UTF-8 ja_JP.UTF-8 \
 && groupadd --system wheel \
 && printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/wheel \
 && chmod 0440 /etc/sudoers.d/wheel \
 && rm -rf /var/lib/apt/lists/*

FROM runtime-base AS builder-base

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      curl \
      git \
      xz-utils \
 && rm -rf /var/lib/apt/lists/*

FROM builder-base AS builder

WORKDIR /src

ARG TARGETARCH

COPY . /src

RUN useradd --create-home --shell /bin/bash builder \
 && install -d -m 0755 -o builder -g builder /nix /tmp/skel

RUN case "${TARGETARCH:-amd64}" in \
      amd64) nix_system='x86_64-linux' ;; \
      arm64) nix_system='aarch64-linux' ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && su builder -c "HOME=/home/builder USER=builder /src/bootstrap/install-nix.sh" \
 && su builder -c ". /home/builder/.nix-profile/etc/profile.d/nix.sh && nix build --extra-experimental-features 'nix-command flakes' --impure --file /src/containers/dotfiles/skel-home.nix --argstr system ${nix_system} --out-link /tmp/home-manager-skel" \
 && su builder -c "PATH=/home/builder/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH} HOME=/tmp/skel USER=skel /tmp/home-manager-skel/activate"

FROM runtime-base AS runtime

LABEL org.opencontainers.image.source="https://github.com/mi2428/dotfiles"

ENV PATH=/etc/skel/.nix-profile/bin:/nix/var/nix/profiles/default/bin:${PATH}

WORKDIR /work

COPY --from=builder /nix /nix
COPY --from=builder /tmp/skel/ /etc/skel/
COPY --from=builder /src/containers/dotfiles/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && install -d -m 0755 /work

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/etc/skel/.nix-profile/bin/fish", "--login"]
