# parse_sdp

[![Tests](https://github.com/andrewstarks/parse_sdp/actions/workflows/test.yml/badge.svg)](https://github.com/andrewstarks/parse_sdp/actions/workflows/test.yml)

parse_sdp is a Lua library that parses, validates, and serializes Session
Description Protocol (SDP) files. The library validates at three tiers:
RFC 8866 (generic SDP), SMPTE ST 2110 (Society of Motion Picture and
Television Engineers), and IPMX (Internet Protocol Media Experience, the
VSF TR-10 suite from the Video Services Forum). The library runs on Lua
5.1 through 5.5, is built on
[LPEG](https://www.inf.puc-rio.br/~roberto/lpeg/) (Parsing Expression
Grammars for Lua), and includes a command-line tool and a browser
playground.

## Who the library is for

- Field engineers who are troubleshooting an SDP file. Every error names
  the line and column, the spec clause the input violates, and a stable
  check id that can be searched for with `grep`.
- Compliance testers who verify a product against ST 2110 or IPMX. Every
  check has a `spec_ref` field that cites the primary specification. The
  check registry can be listed with `sdp.checks()`. No check is based on
  opinion; each check cites explicit normative text.
- Engineers who add SDP support to a product. The public API is stable,
  the parsed document is a plain table with decomposed attributes, the
  serializer round-trips, and findings are structured tables that a
  product can route into its own interface.

## Example error

```text
$ parse_sdp validate --mode st2110 04_bad_tsrefclk_gmid.sdp
error: [INVALID_VALUE] ts-refclk:ptp= value must be '<version>:<EUI-64>[:<domain>]' or '<version>:traceable' (EUI-64 = 8 hex octets, RFC 7273 §4.8)
 --> line 10, col 17
  |
10 | a=ts-refclk:ptp=IEEE1588-2008:AA-BB-CC-DD-EE:0
   |                 ^
  = note: required by RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF)
```

The Lua API returns the same error as a table with the fields `id`,
`message`, `code`, `line`, `col`, `field_path`, and `spec_ref`. The
command-line output and the library output are the same data.

## How much of a non-conforming file is checked

The parser does not stop at the first problem. By default, the parser
records every finding that it can reach and continues to the end of the
file. Only a structural failure ends the parse: lines out of order, an
unknown line letter, or a malformed `m=` or `o=` line, for example. The
error then has the code `PARSE_ERROR` and names the line where matching
stopped. A malformed value of a known attribute, such as `a=ptime:1.0`,
is recorded as a finding, and the parse continues.

`sdp.parse` and `parse_sdp validate` return only the first error, as a
pass-or-fail answer. To see every finding from one run, use
`parse_sdp validate --all-findings`, demote the error-severity checks
with a policy in Lua, or use the browser playground.
[GUIDE.md](GUIDE.md#how-much-of-a-non-conforming-file-is-checked) has
the details.

## Features

- Parses RFC 8866 SDP files into plain Lua tables. RFC 8866 obsoletes
  RFC 4566.
- Every check cites a primary-source spec clause through a stable id and
  a `spec_ref` field.
- Validates SMPTE ST 2110 and IPMX media session descriptions.
- Reports the line and column of a parse failure and prints the source
  line with a caret under the failure position.
- Round trip: parse a file, change the table, and serialize the table
  back to valid SDP text.
- A command-line tool with five subcommands: `validate` (pass or fail),
  `diagnose` (one verdict per tier), `to_json` and `to_sdp` (conversion
  in each direction), and `checks` (registry listing).

## Installation

### LuaRocks

```sh
luarocks install parse_sdp
```

LuaRocks installs `lpeg`, `dkjson`, and `argparse` as dependencies. Only
the command-line tool uses `argparse`; `require("parse_sdp")` does not
load it. No bit-manipulation rock is required on any Lua version: Lua 5.3
and later use the native bitwise operators, and Lua 5.1 and 5.2 use a
pure-Lua arithmetic implementation that is included with the library.

### Browser playground

The playground at <https://andrewstarks.github.io/parse_sdp/> runs the
same library compiled to WebAssembly. Nothing is installed. The page
accepts an SDP file, the JSON form of a parsed document, or a Lua table
literal; shows the three-tier compliance report; lets the user edit
fields with validation on each change; and downloads the result. The
page can also load an SDP file from a URL, for example the IS-05 `transportfile`
endpoint of an NMOS (Networked Media Open Specifications) device, so that the line endings are the ones
that the device sends. Everything runs in the page, and the page does not
upload the input. See
[web/MANUAL.md](web/MANUAL.md) for the user manual.

### Docker

```sh
docker build -t parse_sdp .
docker run --rm -v "$(pwd):/data" parse_sdp lua bin/parse_sdp to_json /data/session.sdp
```

The image contains Lua 5.5, LuaRocks, LPEG, dkjson, busted, and
argparse, with the repository copied to `/app`. The image has no entry
point, so the command names the interpreter and the script. The image's
default command runs the test suite (`busted spec/`).

## API example

```lua
local sdp = require("parse_sdp")

-- Parse. Any valid RFC 8866 SDP file is accepted.
local doc, err = sdp.parse(io.open("session.sdp"):read("*a"))
if not doc then
  io.stderr:write(err.message .. "\n")
  os.exit(1)
end

-- doc is a plain table. Fields are read directly.
print(doc.session.name)
print(doc.media[1].port)

-- Look up attributes by name instead of scanning the ordered array.
local rtpmap = sdp.attr_get(doc.media[1], "rtpmap")    -- first match, or nil
local all    = sdp.attrs_get(doc.media[1], "rtpmap")   -- every match, in order
local fmtp   = sdp.attr_get(doc.media[1], "fmtp")
local width  = fmtp and sdp.params_get(fmtp.params, "width")  -- inner fmtp param

-- doc also has methods.
local ok, err = doc:validate("st2110")   -- validate again after a change
local text     = doc:to_sdp()             -- SDP text string
local json     = doc:to_json()            -- JSON string
print(doc:is_st2110())                    -- boolean

-- Build a doc from a table.
local doc2 = sdp.new({ version="0", origin={...}, session={...}, media={} })
doc2:validate()
```

`examples/examples.lua` is a runnable walkthrough of the API that uses
the SDP files in `examples/`:

```sh
lua examples/examples.lua
# or inside the container:
docker compose run --rm test lua examples/examples.lua
```

## Command-line example

```sh
# Pass or fail
parse_sdp validate --mode st2110 session.sdp

# Which tiers does this SDP file pass? One row per tier; always exits 0.
parse_sdp diagnose customer.sdp

# SDP to JSON
parse_sdp to_json session.sdp
parse_sdp to_json --mode ipmx --pretty session.sdp
cat session.sdp | parse_sdp to_json --mode st2110

# An SDP file that a device serves over HTTP (the tool does not take a URL)
curl -s http://192.0.2.10/session.sdp | parse_sdp validate -

# JSON to SDP
parse_sdp to_sdp doc.json > out.sdp

# Every finding in one pass (errors and warnings)
parse_sdp validate --all-findings --mode st2110 customer.sdp

# List the validator's check registry (id, severity, spec_ref)
parse_sdp checks --filter ts-refclk
```

The exit code is `0` on success and `1` on a parse or validation
failure, with the detail on stderr. `parse_sdp diagnose` always exits
`0`; the verdict is in the output.

## Project layout

```text
parse_sdp/
├── bin/
│   └── parse_sdp                # command-line tool (`lua bin/parse_sdp ...`)
├── parse_sdp/
│   ├── init.lua                 # library entry point (`require("parse_sdp")`)
│   ├── errors.lua               # check registry and severity policy
│   ├── serialize.lua            # doc table to SDP text (CRLF line endings, RFC 8866 order)
│   └── grammar/
│       ├── patterns.lua         # shared numeric value-form patterns
│       ├── addresses.lua        # IPv4 and IPv6 grammars, multicast expansion
│       ├── bitops.lua, bitops_53.lua, bitops_compat.lua
│       │                        # bitwise helpers: native on 5.3+, arithmetic on 5.1/5.2
│       ├── accessors.lua        # params_get / attr_get / attrs_get over the doc shape
│       ├── codecs.lua           # payload-format RFC checks (H.264, H.265, AAC, MP2T) and decode helpers
│       ├── base.lua             # RFC 8866 base grammar and checks
│       ├── st2110.lua           # SMPTE ST 2110 overrides
│       └── ipmx.lua             # VSF TR-10 / IPMX overrides
├── spec/                        # busted test suite (hermetic; 1930 tests as of this commit)
│   ├── grammar_base_spec.lua    # RFC 8866 base SDP; every test cites a clause
│   ├── grammar_st2110_spec.lua  # SMPTE ST 2110; every test cites a clause
│   ├── grammar_ipmx_spec.lua    # VSF TR-10 / IPMX; every test cites a clause
│   ├── grammar_codecs_spec.lua  # payload-format RFC checks (H.264, H.265, AAC, MP2T); every test cites a clause
│   ├── grammar_patterns_spec.lua, grammar_addresses_spec.lua,
│   │     grammar_compose_spec.lua, grammar_bitops_spec.lua  # internal helper tests
│   ├── error_registry_spec.lua, errors_spec.lua
│   ├── roundtrip_spec.lua       # serializer and fixture-wide round trip
│   ├── library_spec.lua         # public API tests
│   ├── cli_spec.lua             # command-line subcommand tests
│   ├── examples_spec.lua        # every file in examples/ passes, or fails for its recorded reason
│   ├── mutation_spec.lua        # properties over mutated copies of every example
│   ├── web_fixtures_spec.lua    # the playground's recorded bridge responses match the native bridge
│   ├── check_coverage.lua       # script: every registered check fires in some spec
│   └── fixtures/                # sample .sdp files used by tests
├── spec_conformance/            # opt-in suite: pinned AMWA fixtures
├── examples/
│   ├── examples.lua             # runnable API walkthrough
│   ├── generic/                 # RFC 8866 SDP samples (valid/ and invalid/)
│   ├── st2110/                  # ST 2110 SDP samples (valid/ and invalid/)
│   └── ipmx/                    # IPMX SDP samples (valid/ and invalid/)
├── web/                         # browser playground: WebAssembly build (wasm/),
│   │                            # static page (src/), bridge contract, user manual
│   ├── MANUAL.md                # user manual for the playground
│   ├── manual/                  # manual screenshots (img/) and capture.mjs
│   ├── README.md                # developer notes for the playground
│   └── CONTRACT.md              # JSON request/response contract of the bridge
├── audits/                      # SPEC_INVENTORY, SPEC_COVERAGE, PHASE3_FINDINGS:
│                                # per-clause inventory and coverage memos
├── Dockerfile
├── docker-compose.yml
├── GUIDE.md                     # full documentation
├── .beads/                      # beads (bd) issue tracker: open work and decisions
└── CHANGELOG.md
```

## Documentation

- [GUIDE.md](GUIDE.md) is the full API reference and usage guide.
- [web/MANUAL.md](web/MANUAL.md) is the user manual for the browser
  playground.
- [CHANGELOG.md](CHANGELOG.md) lists the changes in each release.
- Open work and settled design decisions are tracked as beads with
  [bd](https://github.com/gastownhall/beads). Run `bd ready` for open work
  and `bd list --type decision --all` for the decisions.
- The [audits/](audits/) memos contain the per-clause coverage maps that
  the validation checks are grounded in.
