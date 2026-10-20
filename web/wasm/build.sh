#!/usr/bin/env bash
# web/wasm/build.sh — build parse_sdp as a browser ES module.
#
# Downloads pinned Lua / LPeg / dkjson sources, assembles the embedded Lua
# tree, compiles everything with emcc, and writes web/dist/ (a complete
# static site once web/src/ is copied in). Runs smoke.mjs at the end
# unless SKIP_SMOKE=1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CACHE="$HERE/.cache"
BUILD="$HERE/build"
EMBED="$BUILD/root"
DIST="$ROOT/web/dist"

LUA_VER=5.5.1
LPEG_VER=1.1.0
DKJSON_VER=2.10
LUA_URL="https://www.lua.org/ftp/lua-$LUA_VER.tar.gz"
LPEG_URL="https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-$LPEG_VER.tar.gz"
DKJSON_URL="https://dkolf.de/dkjson-lua/dkjson-$DKJSON_VER.tar.gz"
LUA_SHA=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
LPEG_SHA=4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a
DKJSON_SHA=e8c79e06b5c485643396508f4c45e6d1eec685d08bfbe77042f41f38424d5b24

# fetch <url> <sha256> <dir>: download (if absent), verify, extract into an
# empty directory under .cache. Nothing is ever executed from there.
fetch() {
  local url=$1 sha=$2 dir=$3 tarball="$CACHE/$(basename "$1")"
  [ -f "$tarball" ] || curl -fsSL -o "$tarball" "$url"
  echo "$sha  $tarball" | shasum -a 256 -c --quiet
  rm -rf "$dir"; mkdir -p "$dir"
  tar xzf "$tarball" -C "$dir" --strip-components=1
}

mkdir -p "$CACHE"
fetch "$LUA_URL"    "$LUA_SHA"    "$CACHE/lua"
fetch "$LPEG_URL"   "$LPEG_SHA"   "$CACHE/lpeg"
fetch "$DKJSON_URL" "$DKJSON_SHA" "$CACHE/dkjson"

# Embed root: /lua in the wasm virtual FS.
rockspec="$(ls "$ROOT"/parse_sdp-*.rockspec | head -1)"
version="$(basename "$rockspec" .rockspec)"
version="${version#parse_sdp-}"; version="${version%-*}"

rm -rf "$EMBED"; mkdir -p "$EMBED"
(cd "$ROOT/parse_sdp" && find . -name '*.lua' | cpio -pdm --quiet "$EMBED/parse_sdp")
cp "$CACHE/dkjson/dkjson.lua" "$HERE/bridge.lua" "$EMBED/"
printf 'return "%s"\n' "$version" > "$EMBED/parse_sdp_version.lua"

# Compile. Lua's parser and LPeg's compiler recurse on the C stack, so the
# stack is kept generous.
lua_src=()
for f in "$CACHE"/lua/src/*.c; do
  case "$(basename "$f")" in lua.c|luac.c|onelua.c) ;; *) lua_src+=("$f") ;; esac
done

mkdir -p "$DIST"
emcc -O2 \
  -I"$CACHE/lua/src" -I"$CACHE/lpeg" \
  "${lua_src[@]}" "$CACHE"/lpeg/*.c "$HERE/bridge.c" \
  --embed-file "$EMBED@/lua" \
  -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createParseSdpModule \
  -sEXPORTED_FUNCTIONS=_sdp_request,_malloc,_free \
  -sEXPORTED_RUNTIME_METHODS=cwrap,ccall,UTF8ToString \
  -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=web,node -sSTACK_SIZE=2097152 \
  -o "$DIST/parse_sdp.js"

# Complete the static site.
if [ -d "$ROOT/web/src" ]; then cp -R "$ROOT/web/src/." "$DIST/"; fi

# GitHub Pages lets a browser cache each file for 10 minutes, so after a
# deploy a normal reload can run the old engine and the old modules. Add
# ?v=<version> to the page's script and style URLs, to every relative
# module import, and (through CACHE_KEY in engine.js) to the wasm URL, so
# each release loads new files. Every import of a module gets the same
# query, so the browser still loads each module once.
stamp="?v=$version"
sed -i.bak -E "s#(src|href)=\"(app\.js|styles\.css)\"#\1=\"\2$stamp\"#g" "$DIST/index.html"
for f in "$DIST"/*.js; do
  [ "$(basename "$f")" = parse_sdp.js ] && continue
  sed -i.bak -E "s#([\"']\./[A-Za-z0-9_]+\.js)([\"'])#\1$stamp\2#g" "$f"
done
sed -i.bak -E "s#^const CACHE_KEY = \"\";#const CACHE_KEY = \"$stamp\";#" "$DIST/engine.js"
rm -f "$DIST"/*.bak
grep -q "^const CACHE_KEY = \"$stamp\";" "$DIST/engine.js" || { echo "build.sh: CACHE_KEY not stamped in engine.js" >&2; exit 1; }

# Ship every example in the repo with a manifest the UI's example picker
# reads: examples/index.json = [{ "tier", "status", "name", "title", "path" },
# ...] in repo order (generic → st2110 → ipmx, valid before invalid).
# "title" is the file's own s= session name (RFC 8866 §5.3), so the
# display name lives in the SDP itself; empty when the file has no s=.
rm -rf "$DIST/examples"
# The mock engine (engine_mock.js) reads its three bundled fixtures from
# examples/*.sdp. Copy them back after the directory is cleared.
mkdir -p "$DIST/examples"
cp "$ROOT/web/src/examples/"*.sdp "$DIST/examples/"
example_paths=()
for tier in generic st2110 ipmx; do
  for status in valid invalid; do
    for f in "$ROOT/examples/$tier/$status"/*.sdp; do
      [ -f "$f" ] || continue
      mkdir -p "$DIST/examples/$tier/$status"
      cp "$f" "$DIST/examples/$tier/$status/"
      example_paths+=("examples/$tier/$status/$(basename "$f")")
    done
  done
done
(cd "$ROOT" && lua "$HERE/examples_manifest.lua" "${example_paths[@]}") > "$DIST/examples/index.json"

echo "built parse_sdp $version with Lua $LUA_VER, LPeg $LPEG_VER, dkjson $DKJSON_VER"
ls -l "$DIST/parse_sdp.js" "$DIST/parse_sdp.wasm" | awk '{ print $5, $9 }'

if [ "${SKIP_SMOKE:-0}" != "1" ]; then
  node "$HERE/smoke.mjs"
fi
