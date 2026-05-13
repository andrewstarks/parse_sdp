FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl libreadline-dev \
    && rm -rf /var/lib/apt/lists/*

ARG LUA_VERSION=5.5.0
RUN curl -fsSL "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && cd /tmp/lua-${LUA_VERSION} \
    && make linux install \
    && cd /tmp && rm -rf lua-${LUA_VERSION}

ARG LUAROCKS_VERSION=3.11.1
RUN curl -fsSL "https://luarocks.org/releases/luarocks-${LUAROCKS_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && cd /tmp/luarocks-${LUAROCKS_VERSION} \
    && ./configure \
    && make && make install \
    && cd /tmp && rm -rf luarocks-${LUAROCKS_VERSION}

RUN luarocks install lpeg \
    && luarocks install dkjson \
    && luarocks install busted

WORKDIR /app
COPY . .

CMD ["busted", "spec/"]
