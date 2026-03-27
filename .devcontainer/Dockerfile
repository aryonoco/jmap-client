FROM mcr.microsoft.com/devcontainers/base:2-trixie

# Stable apt cache layer — rarely-changing packages form a cached layer
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential gcc fzf fd-find jq curl wget xz-utils tree libssl-dev \
       ripgrep bat shellcheck shfmt git-delta python3 sd \
       eza du-dust hyperfine tokei bubblewrap socat \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Debian installs fd as "fdfind" and bat as "batcat"; symlink to standard names
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Docker named volumes inherit ownership from the mount-point at creation time.
# Pre-creating these directories ensures the vscode user owns them from the start.
RUN mkdir -p /home/vscode/.nimble \
             /home/vscode/.local/share/mise \
             /home/vscode/.local/share/mise/state \
             /home/vscode/.config/gh \
    && chown -R vscode:vscode /home/vscode/.nimble \
                               /home/vscode/.local \
                               /home/vscode/.config

# Antidote (zsh plugin manager) — pinned tag for reproducibility
RUN git clone --depth=1 --branch v2.0.3 https://github.com/mattmc3/antidote.git /home/vscode/.antidote \
    && chown -R vscode:vscode /home/vscode/.antidote

# Install Nim from source (only tool that requires source build)
ARG NIM_VERSION=2.2.8
USER vscode
WORKDIR /home/vscode
RUN curl -LO "https://nim-lang.org/download/nim-${NIM_VERSION}.tar.xz" \
    && tar xf "nim-${NIM_VERSION}.tar.xz" \
    && cd "nim-${NIM_VERSION}" && sh build.sh \
    && ./bin/nim c -d:release koch && ./koch boot -d:release \
    && ./koch nimble \
    && ./bin/nim c -d:release -o:bin/testament testament/testament.nim \
    && ./bin/nim c -d:release -o:bin/nimsuggest nimsuggest/nimsuggest.nim \
    && cd .. && rm -f "nim-${NIM_VERSION}.tar.xz" \
    && ln -s ~/nim-${NIM_VERSION} ~/nim

# PATH for mise shims, Nim, nimble, and locally installed binaries
ENV PATH="/home/vscode/.local/bin:/home/vscode/.local/share/mise/shims:/home/vscode/nim/bin:/home/vscode/.nimble/bin:${PATH}"

USER root
WORKDIR /workspaces/jmap-client
