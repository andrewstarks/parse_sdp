# parse_sdp

A Lua 5.5 library for parsing, validating, and serializing SDP (Session Description Protocol) files, with support for SMPTE ST 2110 and IPMX extensions.

Built with [LPEG](https://www.inf.puc-rio.br/~roberto/lpeg/) for precise, composable parsing and structured error reporting.

## Features

- Parses RFC 4566 SDP files into plain Lua tables
- Validates SMPTE ST 2110 and IPMX media session descriptions
- Reports exact line and column on parse failure, with a helpful message
- Round-trip support: parse → mutate → serialize back to valid SDP text
- CLI with JSON output and subcommands for both directions

## Install

**LuaRocks:**

```sh
luarocks install dkjson      # JSON dependency
luarocks install parse_sdp
```

**Docker:**

```sh
docker build -t parse_sdp .
docker run --rm -v "$(pwd):/data" parse_sdp parse /data/session.sdp
```

## API Example

```lua
local sdp = require("parse_sdp")

-- Parse — any valid RFC 4566 SDP accepted
local doc, err = sdp.parse(io.open("session.sdp"):read("*a"))
if not doc then
  io.stderr:write(err.message .. "\n")
  os.exit(1)
end

-- doc is a plain table — access fields directly
print(doc.session.name)
print(doc.media[1].port)

-- It also has methods
local ok, err = doc:validate("st2110")   -- re-validate after mutation
local text     = doc:serialize()          -- → valid SDP string
local json     = doc:to_json()            -- → JSON string
print(doc:is_st2110())                    -- bool

-- Build a doc from scratch
local doc2 = sdp.new({ version="0", origin={...}, session={...}, media={} })
doc2:validate()
```

## CLI Example

```sh
# SDP → JSON
parse_sdp parse session.sdp
parse_sdp parse --mode st2110 --pretty session.sdp
cat session.sdp | parse_sdp parse --mode ipmx

# JSON → SDP
parse_sdp serialize doc.json > out.sdp
```

Exit code `0` on success, `1` on error (detail on stderr as JSON).

## Project Layout

```text
parse_sdp/
├── parse_sdp.lua        # library entry point
├── lib/
│   ├── grammar.lua      # LPEG grammar (RFC 4566)
│   ├── st2110.lua       # ST 2110 validation layer
│   ├── ipmx.lua         # IPMX validation layer
│   ├── serialize.lua    # doc → SDP text
│   └── errors.lua       # error construction and formatting
├── cli.lua              # CLI entry point
├── spec/                # busted test suite
│   ├── sdp_spec.lua
│   ├── st2110_spec.lua
│   ├── ipmx_spec.lua
│   └── fixtures/        # sample .sdp files
├── Dockerfile
├── docker-compose.yml
├── GUIDE.md             # full documentation
├── PLAN.md              # implementation plan and milestones
└── CHANGELOG.md
```

See [GUIDE.md](GUIDE.md) for the full API reference and usage guide.
