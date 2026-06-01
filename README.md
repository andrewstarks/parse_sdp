# parse_sdp

[![Tests](https://github.com/andrewstarks/parse_sdp/actions/workflows/test.yml/badge.svg)](https://github.com/andrewstarks/parse_sdp/actions/workflows/test.yml)

A Lua 5.1 - 5.5 library for parsing, validating, and serializing SDP (Session Description Protocol) files, with support for SMPTE ST 2110 and IPMX extensions.

Built with [LPEG](https://www.inf.puc-rio.br/~roberto/lpeg/) for precise, composable parsing and structured error reporting.

## Who is this for?

- **Field engineers troubleshooting an SDP file.** Every error names the
  exact line + column, the spec clause it violates, and a stable id you
  can grep for.
- **Compliance testers verifying a product against ST 2110 / IPMX.**
  Every check carries a primary-source `spec_ref`. The registry is
  introspectable (`sdp.checks()`); no opinion-based checks.
- **Engineers adding SDP support to a product.** Stable public API,
  decomposed doc shape, round-trip-guaranteed serializer, structured
  findings you can route into your own UX.

## What an error looks like

```text
$ parse_sdp validate --mode st2110 04_bad_tsrefclk_gmid.sdp
error: [INVALID_VALUE] ts-refclk:ptp= value must be '<version>:<EUI-64>[:<domain>]' or '<version>:traceable' (EUI-64 = 8 hex octets, RFC 7273 §4.8)
 --> line 10, col 17
  |
10 | a=ts-refclk:ptp=IEEE1588-2008:AA-BB-CC-DD-EE:0
   |                 ^
  = note: required by RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF)
```

The error carries the same `id`, `message`, `code`, `line`, `col`,
`field_path`, and `spec_ref` fields on the Lua-API side, so the CLI
output and library output are the same data.

## Features

- Parses RFC 8866 SDP files into plain Lua tables (RFC 8866 obsoletes RFC 4566)
- Every check cites a primary-source spec clause via stable id + `spec_ref`
- Validates SMPTE ST 2110 and IPMX media session descriptions
- Reports exact line and column on parse failure, with the offending source line highlighted
- Round-trip support: parse → mutate → serialize back to valid SDP text
- CLI with five subcommands: `validate` (yes/no), `diagnose` (tier ladder), `to_json` / `to_sdp` (round-trip), `checks` (registry dump)

## Install

**LuaRocks:**

```sh
luarocks install parse_sdp
```

`lpeg`, `dkjson`, and `argparse` are installed automatically as dependencies.
`argparse` is only used by the CLI binary — `require("parse_sdp")` never loads it.
No bit-manipulation rock is required on any Lua version: Lua 5.3+ uses
native bitwise operators, and Lua 5.1/5.2 use a pure-Lua arithmetic
implementation bundled with the library.

**Docker:**

```sh
docker build -t parse_sdp .
docker run --rm -v "$(pwd):/data" parse_sdp to_json /data/session.sdp
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

-- Look attributes up by name (no hand-rolled scan of the ordered array)
local rtpmap = sdp.attr_get(doc.media[1], "rtpmap")    -- first match, or nil
local all    = sdp.attrs_get(doc.media[1], "rtpmap")   -- every match, in order

-- It also has methods
local ok, err = doc:validate("st2110")   -- re-validate after mutation
local text     = doc:to_sdp()             -- → valid SDP string
local json     = doc:to_json()            -- → JSON string
print(doc:is_st2110())                    -- bool

-- Build a doc from scratch
local doc2 = sdp.new({ version="0", origin={...}, session={...}, media={} })
doc2:validate()
```

See `examples/examples.lua` for a full walkthrough of the API with real SDP files:

```sh
lua examples/examples.lua
# or inside the container:
docker compose run --rm test lua examples/examples.lua
```

## CLI Example

```sh
# Yes/no validation
parse_sdp validate --mode st2110 session.sdp

# Which tiers does this SDP pass? (ladder report, always exit 0)
parse_sdp diagnose customer.sdp

# SDP → JSON
parse_sdp to_json session.sdp
parse_sdp to_json --mode ipmx --pretty session.sdp
cat session.sdp | parse_sdp to_json --mode st2110

# JSON → SDP
parse_sdp to_sdp doc.json > out.sdp

# Every finding in one pass (errors + warnings)
parse_sdp validate --all-findings --mode st2110 customer.sdp

# Inspect the validator's check registry (id / severity / spec_ref)
parse_sdp checks --filter ts-refclk
```

Exit code `0` on success, `1` on parse / validation failure (human-readable detail on stderr). `parse_sdp diagnose` always exits `0` — the verdict is the output.

## Project Layout

```text
parse_sdp/
├── bin/
│   └── parse_sdp                # CLI shell (`lua bin/parse_sdp ...`)
├── parse_sdp/
│   ├── init.lua                 # library entry point (`require("parse_sdp")`)
│   ├── errors.lua               # error registry + severity policy
│   ├── serialize.lua            # doc → SDP text (CRLF, strict ordering)
│   └── grammar/
│       ├── patterns.lua         # shared numeric value-form patterns
│       ├── addresses.lua        # IPv4 / IPv6 grammars + multicast expansion
│       ├── base.lua             # RFC 8866 base grammar + checks
│       ├── st2110.lua           # SMPTE ST 2110 overrides
│       └── ipmx.lua             # VSF TR-10 / IPMX overrides
├── spec/                        # busted test suite (hermetic, 1192 tests)
│   ├── grammar_base_spec.lua    # RFC 8866 base SDP — standards-tied
│   ├── grammar_st2110_spec.lua  # SMPTE ST 2110 — standards-tied
│   ├── grammar_ipmx_spec.lua    # VSF TR-10 / IPMX — standards-tied
│   ├── grammar_patterns_spec.lua, grammar_addresses_spec.lua,
│   │     grammar_compose_spec.lua  # internal helper tests
│   ├── error_registry_spec.lua, errors_spec.lua
│   ├── roundtrip_spec.lua       # serializer + fixture-wide round-trip
│   ├── library_spec.lua         # public API tests
│   ├── cli_spec.lua             # CLI subcommand tests
│   └── fixtures/                # sample .sdp files used by tests
├── spec_conformance/            # opt-in: pinned AMWA fixtures
├── examples/
│   ├── examples.lua             # runnable API walkthrough
│   ├── generic/                 # RFC 8866 SDP samples (valid/ and invalid/)
│   ├── st2110/                  # ST 2110 SDP samples (valid/ and invalid/)
│   └── ipmx/                    # IPMX SDP samples (valid/ and invalid/)
├── audits/                      # SPEC_INVENTORY, SPEC_COVERAGE,
│                                # PHASE3_FINDINGS — the pre-1.0 audit
│                                # memos the 2.0 release built on.
├── Dockerfile
├── docker-compose.yml
├── GUIDE.md                     # full documentation
├── PLAN.md                      # guiding principles and known deferred items
└── CHANGELOG.md
```

See [GUIDE.md](GUIDE.md) for the full API reference and usage guide;
the [audits/](audits/) memos carry the per-clause coverage maps the
refactor was grounded in.
