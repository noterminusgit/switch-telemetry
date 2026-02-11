# Build stage
ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.2.1
ARG DEBIAN_VERSION=bookworm-20240701-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Build argument for release type: web or collector
ARG RELEASE_TYPE=web

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build environment
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

# Compile assets if web release
COPY assets assets
RUN if [ "$RELEASE_TYPE" = "web" ]; then \
      mix assets.deploy; \
    fi

# Compile the project
RUN mix compile

# Copy runtime config
COPY config/runtime.exs config/

# Build the release
RUN mix release ${RELEASE_TYPE}

# Runner stage
FROM ${RUNNER_IMAGE}

ARG RELEASE_TYPE=web

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV=prod

# Copy the release
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/${RELEASE_TYPE} ./

USER nobody

# Set default command
CMD ["/app/bin/server"]
