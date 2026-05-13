FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl libreadline-dev unzip \
    && rm -rf /var/lib/apt/lists/*

ARG LUA_VERSION=5.5.0
RUN curl -fsSL "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" \
    | tar xz -C /tmp \
    && cd /tmp/lua-${LUA_VERSION} \
    && make linux install \
    && cd /tmp && rm -rf lua-${LUA_VERSION}

# LuaRocks HEAD: first version with Lua 5.5 support (not yet in a stable release)
ARG LUAROCKS_COMMIT=fc402072fca856f05e8ae09799cd6c2a2352dd17
RUN curl -fsSL "https://github.com/luarocks/luarocks/archive/${LUAROCKS_COMMIT}.tar.gz" \
    | tar xz -C /tmp \
    && cd /tmp/luarocks-${LUAROCKS_COMMIT} \
    && ./configure --with-lua=/usr/local \
    && make && make install \
    && cd /tmp && rm -rf luarocks-${LUAROCKS_COMMIT}

RUN luarocks install lpeg \
    && luarocks install dkjson \
    && luarocks install busted

WORKDIR /app
COPY . .

CMD ["busted", "spec/"]
