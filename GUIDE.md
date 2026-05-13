# parse_sdp — Guide

## Contents

1. [Introduction](#introduction)
2. [Background: SDP, ST 2110, and IPMX](#background)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [API Reference](#api-reference)
6. [CLI Reference](#cli-reference)
7. [Parsed Table Structure](#parsed-table-structure)
8. [Error Handling](#error-handling)
9. [ST 2110 Validation](#st-2110-validation)
10. [IPMX Validation](#ipmx-validation)
11. [Serialization](#serialization)

---

## Introduction

`parse_sdp` is a Lua 5.5 library for parsing, validating, and serializing SDP
(Session Description Protocol) files used in professional media over IP workflows.
It is built with [LPEG](https://www.inf.puc-rio.br/~roberto/lpeg/) and has no
runtime dependencies beyond LPEG and [dkjson](https://github.com/LuaDist/dkjson).

**Strictness is a primary feature.** The library enforces RFC 4566 exactly: required
fields must be present, optional fields must appear in the correct position, and
values must conform to their specified formats. SDP files that are "mostly valid"
but technically non-conformant are rejected with a precise error message. The library
will never produce an invalid SDP file.

Three validation tiers:

| Mode | Standard | Accepts |
| --- | --- | --- |
| `"sdp"` (default) | RFC 4566 | Any well-formed SDP |
| `"st2110"` | SMPTE ST 2110 | ST 2110-compliant SDP only |
| `"ipmx"` | IPMX | IPMX-compliant SDP only |

Each tier is a strict superset of the previous.

---

## Background

### SDP (RFC 4566)

Session Description Protocol describes multimedia sessions in a plain-text format.
Each line has the form:

```text
<type>=<value>
```

Fields must appear in a mandatory order. A session description opens with a
session-level block (`v=` through `t=`), followed by zero or more media blocks
(each starting with `m=`).

Minimal valid SDP:

```text
v=0
o=- 1234567890 1 IN IP4 192.0.2.1
s=My Session
t=0 0
```

### SMPTE ST 2110

ST 2110 defines professional uncompressed media transport over IP using RTP. It
requires specific SDP attributes that fully describe the media format, removing
the need for out-of-band negotiation.

Key sub-standards:

| Standard | Covers |
| --- | --- |
| ST 2110-10 | System timing and synchronization |
| ST 2110-20 | Uncompressed video |
| ST 2110-21 | Traffic shaping and delivery timing |
| ST 2110-30 | Audio (PCM) |
| ST 2110-40 | Ancillary data (captions, timecode, etc.) |

### IPMX

IPMX (IP Media Experience) is an interoperability profile layered on ST 2110. It
adds RTP header extensions, capability negotiation, and device discovery for
plug-and-play professional AV over IP.

---

## Installation

### LuaRocks

```sh
luarocks install dkjson
luarocks install parse_sdp
```

Requires Lua 5.5 and LPEG.

### Manual

Copy `parse_sdp.lua` and the `lib/` directory into your project. Install LPEG and
dkjson separately.

### Docker

```sh
docker build -t parse_sdp .
```

The image includes Lua 5.5, LuaRocks, LPEG, dkjson, and busted.

---

## Quick Start

```lua
local sdp = require("parse_sdp")

local text = io.open("session.sdp"):read("*a")

-- Parse and validate as RFC 4566
local doc, err = sdp.parse(text)
if not doc then
  io.stderr:write(string.format(
    "Error at line %d col %d: %s\n  %s\n  %s\n",
    err.line, err.col, err.message,
    err.context,
    string.rep(" ", err.col - 1) .. "^"
  ))
  os.exit(1)
end

-- Access fields — doc is a plain table
print(doc.session.name)
print(doc.origin.unicast_address)
print(#doc.media)

-- Validate at a stricter tier
local ok, err2 = doc:validate("st2110")

-- Mutate and re-check
doc.session.name = "Updated Session"
print(doc:is_sdp())    -- still true
print(doc:is_st2110()) -- depends on content

-- Serialize back to SDP text
local out = doc:serialize()
io.open("out.sdp", "w"):write(out)

-- Or get JSON
print(doc:to_json())
```

---

## API Reference

### Module functions

#### `sdp.parse(text [, mode])`

Parses `text` and validates it.

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `text` | string | required | Raw SDP content |
| `mode` | string | `"sdp"` | `"sdp"`, `"st2110"`, or `"ipmx"` |

Returns `doc, nil` on success; `nil, err` on failure.

The returned `doc` is a plain Lua table with the [doc methods](#doc-methods)
attached via metatable.

```lua
local doc, err = sdp.parse(text)
local doc, err = sdp.parse(text, "st2110")
local doc, err = sdp.parse(text, "ipmx")
```

#### `sdp.new(table)`

Wraps an existing Lua table as a doc object by attaching the metatable. Does not
validate. Useful for building SDP documents programmatically.

Returns `doc` (never fails).

```lua
local doc = sdp.new({
  version = "0",
  origin  = { username="-", sess_id="1", sess_version="1",
               net_type="IN", addr_type="IP4", unicast_address="192.0.2.1" },
  session = { name="My Session", timing={ start=0, stop=0 },
               emails={}, phones={}, bandwidths={}, attributes={} },
  media   = {},
})
```

---

### Doc methods

#### `doc:validate([mode])`

Validates the doc against the given mode (`"sdp"`, `"st2110"`, or `"ipmx"`).
Defaults to `"sdp"`.

Returns `true` on success; `nil, err` on failure.

Re-runs validation each call — safe to use after mutating the doc.

```lua
local ok, err = doc:validate()
local ok, err = doc:validate("st2110")
```

#### `doc:is_sdp()` / `doc:is_st2110()` / `doc:is_ipmx()`

Convenience boolean checks. Each runs the corresponding validation and returns
`true` or `false`. Call `doc:validate(mode)` if you need the error detail.

```lua
if doc:is_st2110() then ... end
```

#### `doc:serialize()`

Converts the doc to a valid RFC 4566 SDP string.

- Line endings are `\r\n` per RFC 4566.
- Field order follows RFC 4566 §5 exactly.
- Output is not byte-identical to the original input, but it re-parses to an
  equivalent table (functional round-trip).

Returns a `string`. Raises `error()` if the doc is structurally malformed (missing
required fields) — call `doc:validate()` first if unsure.

```lua
local text = doc:serialize()
```

#### `doc:to_json()`

Returns a JSON string representation of the doc (via dkjson).

```lua
local json = doc:to_json()
```

---

## CLI Reference

```text
parse_sdp <subcommand> [options] [file]
```

If `file` is omitted, reads from stdin.

### `parse_sdp parse`

Parse and validate an SDP file. Outputs JSON to stdout.

```text
parse_sdp parse [--mode sdp|st2110|ipmx] [--pretty] [file]
```

| Flag | Description |
| --- | --- |
| `--mode MODE` | Validation mode (default: `sdp`) |
| `--pretty` | Pretty-print JSON output |

On success, prints a JSON object to stdout:

```json
{
  "version": "0",
  "origin": { "username": "-", "sess_id": "...", ... },
  "session": { "name": "My Session", ... },
  "media": [ { "type": "video", "port": 5004, ... } ]
}
```

On failure, prints a JSON error to stderr and exits `1`:

```json
{
  "error": true,
  "message": "missing required field 't='",
  "line": 4,
  "col": 1,
  "context": "a=recvonly"
}
```

### `parse_sdp serialize`

Convert a JSON doc back to SDP text. Outputs to stdout.

```text
parse_sdp serialize [file.json]
```

```sh
parse_sdp serialize doc.json > session.sdp
cat doc.json | parse_sdp serialize
```

### Examples

```sh
# Validate a file as generic SDP
parse_sdp parse session.sdp

# Validate as ST 2110 with pretty JSON output
parse_sdp parse --mode st2110 --pretty session.sdp

# Pipe-friendly
cat session.sdp | parse_sdp parse --mode ipmx

# Round-trip: SDP → JSON → SDP
parse_sdp parse session.sdp | parse_sdp serialize > out.sdp
```

---

## Parsed Table Structure

```lua
{
  version = "0",                   -- v=

  origin = {                       -- o=
    username        = "-",
    sess_id         = "1234567890",
    sess_version    = "1",
    net_type        = "IN",
    addr_type       = "IP4",
    unicast_address = "192.0.2.1",
  },

  session = {
    name        = "My Session",    -- s=  (required)
    info        = nil,             -- i=  (optional)
    uri         = nil,             -- u=  (optional)
    emails      = {},              -- e=  (array, zero or more)
    phones      = {},              -- p=  (array, zero or more)
    connection  = nil,             -- c=  (optional)
    bandwidths  = {},              -- b=  (array, zero or more)
    timing      = { start=0, stop=0 },  -- t=  (required)
    attributes  = {},              -- a=  (array, preserves order)
  },

  media = {                        -- one entry per m= block
    {
      media      = "video",        -- m=  media type
      port       = 5004,           -- m=  port
      port_count = nil,            -- m=  /count suffix, if present
      proto      = "RTP/AVP",      -- m=  transport protocol
      fmts       = { "96" },       -- m=  fmt list (array of strings)
      info       = nil,            -- i=  (optional)
      connection = nil,            -- c=  (optional)
      bandwidths = {},             -- b=  (array, zero or more)
      attributes = {               -- a=  (array, preserves order)
        { name = "rtpmap", value = "96 raw/90000" },
        { name = "fmtp",   value = "96 sampling=YCbCr-4:2:2; width=1920; ..." },
      },
    },
  },
}
```

All array fields (`emails`, `phones`, `bandwidths`, `attributes`, `media`) are always
present as tables, even when empty. Optional scalar fields absent from the source
SDP are `nil`.

`connection` (when present) is a table `{ net_type, addr_type, address }`.
`bandwidths` entries are tables `{ type, value }` where `value` is a number.
`attributes` entries are tables `{ name, value }` where `value` is `nil` for
flag-only attributes (e.g. `a=recvonly`).

---

## Error Handling

Errors are returned as values. The library never calls `error()` for parse or
validation failures.

| Field | Type | Description |
| --- | --- | --- |
| `message` | string | Human-readable description |
| `line` | integer | 1-based line number |
| `col` | integer | 1-based column number |
| `context` | string | The full text of the offending line |
| `code` | string | Machine-readable code: `MISSING_FIELD`, `INVALID_VALUE`, `WRONG_ORDER`, `UNKNOWN_FIELD` |

ST 2110 and IPMX errors also include:

| Field | Type | Description |
| --- | --- | --- |
| `field_path` | string | e.g. `"media[1].attributes.fmtp"` |
| `spec_ref` | string | e.g. `"ST 2110-20 §7.2"` |

### Rendering an error

```lua
local doc, err = sdp.parse(text)
if not doc then
  local pointer = string.rep(" ", err.col - 1) .. "^"
  io.stderr:write(string.format(
    "Error at line %d, col %d: %s\n  %s\n  %s\n",
    err.line, err.col, err.message, err.context, pointer
  ))
end
```

Output:

```text
Error at line 4, col 1: missing required field 't='
  a=recvonly
  ^
```

---

## ST 2110 Validation

`sdp.parse(text, "st2110")` or `doc:validate("st2110")` enforces:

### Session-level

- At least one `m=` block must be present.

### Per media block

| Attribute | Requirement |
| --- | --- |
| `a=ts-refclk` | Required. Format: `ptp=<profile>:<domain-or-gmid>` |
| `a=mediaclk` | Required. Typically `direct=0` |
| `a=rtpmap` | Required. Clock rate must match media type |
| `a=fmtp` | Required. Key=value pairs validated per sub-standard |

### ST 2110-20 (video) required `fmtp` parameters

| Parameter | Example |
| --- | --- |
| `sampling` | `YCbCr-4:2:2` |
| `width` | `1920` |
| `height` | `1080` |
| `exactframerate` | `30000/1001` |
| `depth` | `10` |
| `TCS` | `SDR` |
| `colorimetry` | `BT709` |
| `PM` | `2110GPM` |
| `SSN` | `ST2110-20:2022` |

### ST 2110-30 (audio) required `fmtp` parameters

| Parameter | Example |
| --- | --- |
| `channel-order` | `SMPTE2110.(ST)` |

---

## IPMX Validation

`sdp.parse(text, "ipmx")` or `doc:validate("ipmx")` runs ST 2110 validation first,
then checks IPMX-specific requirements:

- Required `a=extmap` entries for IPMX RTP header extensions are present.
- `a=ts-refclk` uses an IPMX-approved profile.
- Additional IPMX capability attributes are validated.

*(This section will be expanded as the IPMX validation layer is implemented.)*

---

## Serialization

`doc:serialize()` produces RFC 4566-compliant SDP text. Field order follows the
spec exactly (RFC 4566 §5):

```text
v=
o=
s=
[i=]
[u=]
[e=]*
[p=]*
[c=]
[b=]*
t=
[a=]*
[m=
  [i=]
  [c=]
  [b=]*
  [a=]*
]*
```

Line endings are `\r\n`. The serializer never emits optional fields that are `nil`.
Output is always a valid, strictly conformant SDP document.
