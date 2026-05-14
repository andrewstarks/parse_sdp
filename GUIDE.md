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

Requires Lua 5.3–5.5 and LPEG. For CLI use, also install argparse: `luarocks install argparse`.

### Manual

Copy `parse_sdp.lua` into your project. Install LPEG, dkjson, and argparse separately.

### Docker

```sh
docker build -t parse_sdp .
```

The image includes Lua 5.5, LuaRocks, LPEG, dkjson, busted, and argparse.

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
local out = doc:to_sdp()
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

#### `doc:to_sdp()`

Converts the doc to a valid RFC 4566 SDP string.

- Line endings are `\r\n` per RFC 4566.
- Field order follows RFC 4566 §5 exactly.
- Output is not byte-identical to the original input, but it re-parses to an
  equivalent table (functional round-trip).

Returns a `string`. Raises `error()` if the doc is structurally malformed (missing
required fields) — call `doc:validate()` first if unsure.

```lua
local text = doc:to_sdp()
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

### `parse_sdp to_json`

Parse and validate an SDP file. Outputs JSON to stdout.

```text
parse_sdp to_json [--mode sdp|st2110|ipmx] [--pretty] [file]
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

On failure, prints an error message to stderr and exits `1`.

### `parse_sdp to_sdp`

Convert a JSON doc back to SDP text. Outputs to stdout.

```text
parse_sdp to_sdp [file.json]
```

```sh
parse_sdp to_sdp doc.json > session.sdp
cat doc.json | parse_sdp to_sdp
```

### Examples

```sh
# Validate a file as generic SDP
parse_sdp to_json session.sdp

# Validate as ST 2110 with pretty JSON output
parse_sdp to_json --mode st2110 --pretty session.sdp

# Pipe-friendly
cat session.sdp | parse_sdp to_json --mode ipmx

# Round-trip: SDP → JSON → SDP
parse_sdp to_json session.sdp | parse_sdp to_sdp > out.sdp
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
| `code` | string | Machine-readable code: `MISSING_FIELD`, `INVALID_VALUE`, `WRONG_ORDER`, `MALFORMED_LINE` |

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

#### ST 2022-7 redundancy grouping — `a=group:DUP` (ST 2110-10 §8.5)

When `a=group:DUP <mid1> <mid2> …` is present at session level, the library validates:

- Every named `mid` must correspond to a media block carrying a matching `a=mid` attribute.
- All legs in the DUP group must have the same media type (`video`, `audio`, etc.).
- A DUP group with fewer than 2 legs is rejected.
- Absence of `a=group:DUP` is not an error.
- More than two legs are allowed (RFC 7104 permits any number ≥ 2).
- Legs may use different destination addresses or ports (ST 2022-7 permits this).

### Connection address (`c=`)

When a `c=` line is present on a media block, the address is validated (ST 2110-10 §6.5):

- IPv4 multicast addresses (224.0.0.0–239.255.255.255) must include a TTL suffix (e.g. `239.100.0.1/64`).
- The Local Network Control Block (`224.0.0.0/24`) and Internetwork Control Block (`224.0.1.0/24`) are forbidden per RFC 5771.
- Unicast addresses must not carry a TTL suffix.

### Per media block

`a=ts-refclk` may appear at session level (applying to all media blocks) or at each media-block level; the library accepts either location. All other attributes in this table must be per-media.

| Attribute | Requirement |
| --- | --- |
| `a=ts-refclk` | Required. Accepted: `ptp=<version>:<gmid>[:<domain>]`; `localmac=<mac>`; `ntp=<addr>` (addr must be a valid IPv4, IPv6, or hostname); `gps`; `gal`; `glonass` |
| `a=mediaclk` | Required. Accepted: `direct=<integer>` (sample offset, may be negative); `sender` |
| `a=rtpmap` | Required. Clock rate validated: must be 90000 for video, `smpte291`, and `ST2110-41`; audio clock rate validated against known rates. Audio encoding name validated: must be `L16`, `L24`, or `AM824`. Payload type must match the payload type in `a=fmtp` |
| `a=fmtp` | Required. Key=value pairs validated per sub-standard |

### ST 2110-20 (video) `fmtp` parameters

ST 2110-20 §7.2 requires nine `fmtp` parameters. All nine are validated for both presence
and value format.

| Parameter | Example | Valid values |
| --- | --- | --- |
| `sampling` | `YCbCr-4:2:2` | `YCbCr-4:4:4`, `YCbCr-4:2:2`, `YCbCr-4:2:0`, `CLYCbCr-4:4:4`, `CLYCbCr-4:2:2`, `CLYCbCr-4:2:0`, `ICtCp-4:4:4`, `ICtCp-4:2:2`, `ICtCp-4:2:0`, `RGB`, `XYZ`, `KEY` |
| `width` | `1920` | positive integer |
| `height` | `1080` | positive integer |
| `exactframerate` | `30000/1001` | positive integer or `n/d` fraction (both parts positive) |
| `depth` | `10` | positive integer |
| `TCS` | `SDR` | `SDR`, `PQ`, `HLG`, `LINEAR`, `BT2100LINPQ`, `BT2100LINHLG`, `ST2065-1`, `ST428-1`, `DENSITY` |
| `colorimetry` | `BT709` | `BT601`, `BT709`, `BT2020`, `BT2100`, `ST2065-1`, `ST2065-3`, `UNSPECIFIED`, `ALPHA` |
| `PM` | `2110GPM` | `2110GPM`, `2110BPM` |
| `SSN` | `ST2110-20:2022` | must start with `ST2110-20:` |

Optional parameters validated when present:

| Parameter | Valid values | Spec ref |
| --- | --- | --- |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` | ST 2110-20 §7.2 |
| `TP` | `2110TPN`, `2110TPNL`, `2110TPW` | ST 2110-21 |
| `MAXUDP` | positive integer | ST 2110-20 §7.2 |
| `PAR` | `W:H` (both positive integers) | ST 2110-20 §7.2 |
| `TROFF` | non-negative integer | ST 2110-20 §7.2 |
| `CMAX` | positive integer | ST 2110-20 §7.2 |

Bare-flag parameters with no value (`interlace`, `segmented`) are accepted without restriction. Any other unrecognized key=value pairs pass through silently.

### ST 2110-30 (audio) `rtpmap` and `fmtp` parameters

The `a=rtpmap` encoding name is validated: must be `L16`, `L24`, or `AM824`. The clock
rate is validated against known audio sample rates: 32000, 44100, 48000, 88200, 96000,
176400, 192000 Hz. The channel count (third `/`-separated component in the rtpmap value,
e.g. `L24/48000/8`) is required and must be an integer in the range 1–16
(ST 2110-30 §7.1). `channel-order` is validated for presence and value format.

When `a=ptime` is present, its value must be a positive number (ST 2110-30 §7.2).

| Parameter | Example | Valid values |
| --- | --- | --- |
| `channel-order` | `SMPTE2110.(ST)` | must match `SMPTE2110.(<group>)` with a non-empty group |

### ST 2110-40 (smpte291 ancillary data) `fmtp` parameters

Ancillary data flows use rtpmap encoding name `smpte291` at clock rate 90000 (RFC 8331).

| Parameter | Example | Validated |
| --- | --- | --- |
| `DID_SDID` | `{0x61,0x02}` | yes — required; each octet must be exactly two hex digits |
| `VPID_Code` | `133` | yes — optional; must be a non-negative integer when present |

Multiple `DID_SDID` entries are allowed in the SDP; at least one must be present. All entries are validated — any entry with a malformed value is rejected.

### ST 2110-41 (fast metadata) `fmtp` parameters

Fast metadata flows use rtpmap encoding name `ST2110-41` at clock rate 90000. The clock rate is validated and must be exactly 90000.

| Parameter | Example | Validated |
| --- | --- | --- |
| `SSN` | `ST2110-41:2024` | yes — required; value must start with `ST2110-41:` |
| `DIT` | `100` | yes — required; must be a non-negative integer |

---

## IPMX Validation

`sdp.parse(text, "ipmx")` or `doc:validate("ipmx")` runs ST 2110 validation first
on all non-USB media blocks, then checks IPMX-specific requirements:

### Core requirements

| Check | Spec ref | Detail |
| --- | --- | --- |
| `a=extmap` present with valid URI | IPMX §6 / RFC 5285 | Must appear at session level or in at least one RTP media block; every `a=extmap` value must be in RFC 5285 format: `entry-count[/direction] URI` where direction is `sendonly`, `recvonly`, `sendrecv`, or `inactive` and URI has a scheme (e.g. `urn:`, `http:`) |
| `IPMX` bare flag in every `a=fmtp` | TR-10-1 §10.1 | Required in all non-USB media blocks |

### Optional extensions (validated when present)

#### HDCP Key Exchange — `a=hkep` (TR-10-5 §10)

When present at session or media level, the `a=hkep` attribute is validated against:

```text
a=hkep:<port> IN <IP4|IP6> <unicast-address> <node-id> <port-id>
```

| Field | Validation |
| --- | --- |
| `<port>` | Integer 0–65535 |
| nettype | Must be `IN` |
| addrtype | Must be `IP4` or `IP6` |
| `<node-id>` | UUID format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (hex digits) |
| `<port-id>` | Five hex-digit pairs: `xx-xx-xx-xx-xx` |

Multiple `a=hkep` lines are allowed (ordered by Sender preference). HKEP and PEP
may coexist in the same session.

#### Privacy Encryption Protocol — `a=privacy` (TR-10-13 §13)

When present (at session or media level), the `a=privacy` attribute is validated:

```text
a=privacy: protocol=<p>; mode=<m>; iv=<iv>; key_generator=<kg>; key_version=<kv>; key_id=<kid>
```

| Parameter | Valid values |
| --- | --- |
| `protocol` | `RTP` or `RTP_KV` |
| `mode` | Any of the 12 AES modes below |
| `iv`, `key_generator`, `key_version`, `key_id` | Hex strings (non-empty) |

**Valid `mode` values:**
`AES-128-CTR`, `AES-256-CTR`, `AES-128-CTR_CMAC-64`, `AES-256-CTR_CMAC-64`,
`AES-128-CTR_CMAC-64-AAD`, `AES-256-CTR_CMAC-64-AAD`,
`ECDH_AES-128-CTR`, `ECDH_AES-256-CTR`, `ECDH_AES-128-CTR_CMAC-64`,
`ECDH_AES-256-CTR_CMAC-64`, `ECDH_AES-128-CTR_CMAC-64-AAD`, `ECDH_AES-256-CTR_CMAC-64-AAD`

On **USB blocks** (`m=application` with TCP), only the four AAD variants are accepted
(TR-10-14 §12): `AES-128-CTR_CMAC-64-AAD`, `AES-256-CTR_CMAC-64-AAD`,
`ECDH_AES-128-CTR_CMAC-64-AAD`, `ECDH_AES-256-CTR_CMAC-64-AAD`.

#### USB transport — TR-10-14

Media blocks with `m=application … TCP …` are identified as USB blocks and bypass
ST 2110 media-block validation (they are not RTP streams). Any `a=privacy` on a USB
block is validated with the stricter AAD-only mode set.

#### FEC — `FECPROFILE` and latency parameters (TR-10-6 §7.6)

When the `FECPROFILE` key appears in a media block's `a=fmtp`, the library validates:

| Parameter | Validation |
| --- | --- |
| `FECPROFILE` | Must be `profile-a` |
| `FEC_ADD_LATENCY_VIDEO` | Non-negative integer (microseconds); `FECPROFILE` must also be present |
| `FEC_ADD_LATENCY_AUDIO` | Non-negative integer (microseconds); `FECPROFILE` must also be present |

#### ST 2022-7 DUP group — privacy consistency (TR-10-13 §13)

When `a=group:DUP` is present and any leg carries `a=privacy`, the library checks that
all legs in the group carry **identical** `a=privacy` values. A leg missing `a=privacy`
while another has it is also a violation.

#### RTCP port convention (TR-10-1 §8.7)

IPMX mandates that RTCP Sender Reports are sent to media port + 1. The library checks:

| Check | Result |
| --- | --- |
| `a=rtcp-mux` present on a media block | Rejected — RTCP must be on a separate port |
| `a=rtcp:<port>` present but `port ≠ media-port + 1` | Rejected |
| No `a=rtcp` present | Accepted (implicit port+1 convention) |

These checks apply at the **IPMX tier only**. ST 2110 mode accepts `a=rtcp-mux` and any
`a=rtcp` value.

---

## Serialization

`doc:to_sdp()` produces RFC 4566-compliant SDP text. Field order follows the
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
