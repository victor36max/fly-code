# Find eligible builder and runner images at
# https://hub.docker.com/r/hexpm/elixir/tags
ARG ELIXIR_VERSION=1.18.3
ARG OTP_VERSION=27.3.4
ARG DEBIAN_VERSION=bookworm-20250428-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} as builder

# install build dependencies + Node.js for asset pipeline
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Install npm deps for asset pipeline
ENV CI=true
RUN cd assets && pnpm install --frozen-lockfile

# Compile the project
RUN mix compile

# compile assets (runs pnpm build via mix alias)
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel

RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y \
    # Runtime libs
    libstdc++6 openssl libncurses5 locales ca-certificates \
    # Dev tools
    git openssh-client curl sudo unzip wget zip \
    # Build essentials (native extensions, compilation)
    build-essential pkg-config libssl-dev \
    # Dev utilities AI agents rely on
    ripgrep fd-find jq tree htop \
    # Python 3
    python3 python3-pip python3-venv \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    # GitHub CLI
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    # Podman + podman-compose (daemonless container runtime, Docker CLI-compatible)
    podman podman-compose \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Symlink fd-find to fd (Debian packages it as fdfind)
RUN ln -s $(which fdfind) /usr/local/bin/fd

# Git defaults for AI agents
RUN git config --system init.defaultBranch main && \
    git config --system advice.detachedHead false

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Create non-root user (Claude CLI refuses --dangerously-skip-permissions as root)
RUN groupadd -r flycode && useradd -r -g flycode -m -d /home/flycode -s /bin/bash flycode && \
    echo "flycode ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/flycode && \
    # Rootless Podman needs subuid/subgid ranges for user namespace mapping
    usermod --add-subuids 100000-165535 --add-subgids 100000-165535 flycode && \
    # Allow Podman to resolve short image names (e.g. postgres:16-alpine → docker.io/...)
    mkdir -p /etc/containers && \
    echo 'unqualified-search-registries = ["docker.io"]' > /etc/containers/registries.conf

# Install CLIs as the non-root user
USER flycode

RUN curl -fsSL https://claude.ai/install.sh | bash
RUN curl -fsSL https://opencode.ai/install | bash

USER root

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

COPY --from=builder /app/_build/${MIX_ENV}/rel/fly_code ./

# Ensure app directory is accessible by flycode user
RUN chown -R flycode:flycode /app

USER flycode

ENV PATH="/home/flycode/.local/bin:/home/flycode/.opencode/bin:/home/flycode/bin:${PATH}"

CMD ["/bin/sh", "-c", "/app/bin/migrate && /app/bin/server"]
