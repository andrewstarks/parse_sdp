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
- All legs must share the same rtpmap encoding name and clock rate.
- All legs must use the same RTP payload type number (ST 2022-7 §6 — *"Senders shall transmit on both flows the same RTP payload data and shall use the same payload type number"*).
- All legs must carry identical `a=fmtp` value strings (ST 2022-7 §6 — identical payload implies identical essence parameters).
- No two legs may use **both** the same destination address (`c=`) and the same source address (`a=source-filter` src). Distinct on at least one axis is required (ST 2110-10 §8.5).
- A DUP group with fewer than 2 legs is rejected.
- Absence of `a=group:DUP` is not an error.
- More than two legs are allowed (RFC 7104 permits any number ≥ 2).
- Legs may use different destination addresses or ports (ST 2022-7 permits this).

### Connection address (`c=`)

A connection address is required at either session level or media-block level (ST 2110-10 §6.3). A media block with no per-media `c=` and no session-level `c=` is rejected.

When a `c=` line is present (at either session or media level), the address is validated (ST 2110-10 §6.5 / RFC 4566 §5.7):

- IPv4 multicast addresses (224.0.0.0–239.255.255.255) must include a TTL suffix (e.g. `239.100.0.1/64`).
- IPv4 TTL must be an integer in the range 1–255.
- The Local Network Control Block (`224.0.0.0/24`) and Internetwork Control Block (`224.0.1.0/24`) are forbidden per RFC 5771.
- IPv4 unicast addresses must not carry a TTL suffix.
- IPv6 multicast addresses (`ff` prefix) may carry an optional `/<positive-integer>` scope suffix (e.g. `ff02::1/64`).
- IPv6 unicast addresses must not include any `/` suffix.

### Per media block

`a=ts-refclk` may appear at session level (applying to all media blocks) or at each media-block level; the library accepts either location. **All** `a=ts-refclk` attributes are validated individually — if multiple are present (at any combination of session and media level), each must be a recognized, well-formed clock source (ST 2110-10 §8.2). All other attributes in this table must be per-media.

| Attribute | Requirement |
| --- | --- |
| `a=ts-refclk` | Required. The `ptp=` version token is restricted to `IEEE1588-2008` (ST 2110-10:2022 §6.1 mandates PTPv2; TR-10-1 §10.4 confirms the same for IPMX). `IEEE1588-2002`, `IEEE1588-2019`, and bare `IEEE1588` are rejected at both tiers. Accepted: `ptp=IEEE1588-2008:<gmid>[:<domain>]` (domain 0–127); `ptp=IEEE1588-2008:traceable`; `localmac=<mac>`; `ntp=<addr>` (addr must be a valid IPv4, IPv6, or hostname); `gps`; `gal`; `glonass` |
| `a=mediaclk` | Required, **media-level only**. Accepted: `direct=0` (offset SHALL be zero per ST 2110-10 §7.3) or `sender`. Session-level `a=mediaclk` is rejected (ST 2110-10 §8.3) |
| `a=mid` | Optional. When present, value must be unique within the session (RFC 5888 §8.1) |
| `a=source-filter` | Optional. When present, must follow RFC 4570: `<incl\|excl> IN <IP4\|IP6> <dest> <src>+` |
| `a=rtpmap` | Required. RTP payload type must be in the dynamic range 96–127 (ST 2110-10 §6.2). Clock rate validated: must be 90000 for video, `smpte291`, and `ST2110-41`; audio clock rate validated against known rates. Audio encoding name validated: must be `L16`, `L24`, or `AM824`. Payload type must match the payload type in `a=fmtp` |
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
| `TCS` | `SDR` | `SDR`, `PQ`, `HLG`, `LINEAR`, `BT2100LINPQ`, `BT2100LINHLG`, `ST2065-1`, `ST428-1`, `DENSITY`, `UNSPECIFIED` |
| `colorimetry` | `BT709` | `BT601`, `BT709`, `BT2020`, `BT2100`, `ST2065-1`, `ST2065-3`, `UNSPECIFIED`, `ALPHA`, `XYZ` |
| `PM` | `2110GPM` | `2110GPM`, `2110BPM` |
| `SSN` | `ST2110-20:2022` | must be `ST2110-20:YYYY` where YYYY is a 4-digit year (e.g. `ST2110-20:2017`, `ST2110-20:2022`) |

Optional parameters validated when present:

| Parameter | Valid values | Spec ref |
| --- | --- | --- |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` | ST 2110-20 §7.2 |
| `TP` | `2110TPN`, `2110TPNL`, `2110TPW` | ST 2110-21 |
| `MAXUDP` | positive integer ≤ 8960 (Extended UDP Size Limit) | ST 2110-10 §6.4 |
| `PAR` | `W:H` (both positive integers, **in lowest terms** per ST 2110-20 §7.3 — e.g. `1:1`, `12:11`, `64:45`; `2:2` is rejected) | ST 2110-20 §7.3 |
| `TROFF` | non-negative integer (requires `TP` to also be present) | ST 2110-21 §8 |
| `CMAX` | positive integer (requires `TP` to also be present) | ST 2110-21 §8 |
| `TSMODE` | `SAMP`, `NEW`, `PRES` | ST 2110-10 §8.7 |
| `TSDELAY` | non-negative integer (microseconds) | ST 2110-10 §8.7 |

Bare-flag parameters `interlace` and `segmented` are accepted. `segmented` SHALL only appear together with `interlace` (ST 2110-20 §7.3); signaling `segmented` alone is rejected. Any other unrecognized key=value pairs pass through silently.

### ST 2110-30 (audio) `rtpmap` and `fmtp` parameters

The `a=rtpmap` encoding name is validated: must be `L16`, `L24`, or `AM824`. The clock
rate scope is mode-dependent:

- **`st2110` mode** — restricted to {44100, 48000, 96000} Hz per ST 2110-30 §6.1
  (*"Other sampling rates are out of scope"*).
- **`ipmx` mode** — additionally permits {32000, 88200, 176400, 192000} Hz to
  cover AES67-extended professional-audio configurations.

The channel count (third `/`-separated component in the rtpmap value,
e.g. `L24/48000/8`) is required and must be an integer in the range 1–16
(ST 2110-30 §7.1). `channel-order` is validated for presence and value format;
mono (`SMPTE2110.(M)`) is permitted.

When `a=ptime` is present, its value must be a positive number (ST 2110-30 §7.2).
The validator also enforces that the resulting RTP payload size
(`channels × samples-per-packet × bytes-per-sample`, where L16=2 B, L24=3 B,
AM824=4 B) fits within `MAXUDP − 12 B` of UDP payload (RTP header is 12 B).
Default MAXUDP is the Standard UDP Size Limit of 1460 octets per ST 2110-10 §6.4.

| Parameter | Example | Valid values |
| --- | --- | --- |
| `channel-order` | `SMPTE2110.(ST)` | must be `SMPTE2110.(<group>[,<group>...])` where each group is one of: `M`, `DM`, `ST`, `LtRt`, `51`, `71`, `222`, `SGRP`, or `U01`–`U64` (ST 2110-30:2017 §6.2.2 Table 1) |

### ST 2110-40 (smpte291 ancillary data) `fmtp` parameters

Ancillary data flows use rtpmap encoding name `smpte291` at clock rate 90000 (RFC 8331).

| Parameter | Example | Validated |
| --- | --- | --- |
| `DID_SDID` | `{0x61,0x02}` | yes — required; each octet must be exactly two hex digits |
| `VPID_Code` | `133` | yes — optional; must be a non-negative integer when present |

Multiple `DID_SDID` entries are allowed in the SDP; at least one must be present. All entries are validated — any entry with a malformed value is rejected.

### ST 2110-22 (JPEG-XS compressed video) `fmtp` parameters

Compressed video flows use rtpmap encoding name `jxsv` at clock rate 90000 (ST 2110-22 / TR-10-11). `TP` is restricted to `2110TPNL` or `2110TPW` — the uncompressed `2110TPN` packing is not valid for compressed video.

Required parameters (all must be present):

| Parameter | Example | Valid values |
| --- | --- | --- |
| `sampling` | `YCbCr-4:2:2` | same set as ST 2110-20 |
| `width` | `1920` | positive integer |
| `height` | `1080` | positive integer |
| `exactframerate` | `25` | positive integer or `n/d` fraction |
| `depth` | `10` | positive integer |
| `TCS` | `SDR` | same set as ST 2110-20 |
| `colorimetry` | `BT709` | same set as ST 2110-20 |
| `PM` | `2110GPM` | `2110GPM`, `2110BPM` |
| `SSN` | `ST2110-22:2019` | must be `ST2110-22:YYYY` (4-digit year) |
| `profile` | `High444.12` | enum (TR-10-15 §8 / TR-08 §8.1.1): `Unrestricted`, `Light422.10`, `Light444.12`, `LightSubline422.10`, `LightSubline444.12`, `Main422.10`, `Main444.12`, `High444.12`, `MLS.12`, `LightBayer`, `MainBayer`, `HighBayer`, `MLSBayer` |
| `level` | `2k-1` | enum (TR-10-15 §9 / ISO/IEC 21122-2): `Unrestricted`, `1k-1`, `2k-1`, `4k-1`, `4k-2`, `4k-3`, `8k-1`, `8k-2`, `8k-3`, `16k-1`, `16k-2`, `16k-3` |
| `sublevel` | `Sublev3bpp` | enum (TR-10-15 §7.1 / ISO/IEC 21122-2): `Unrestricted`, `Full`, `Sublev12bpp`, `Sublev9bpp`, `Sublev6bpp`, `Sublev4bpp`, `Sublev3bpp`, `Sublev2bpp` |
| `transmode` | `0` or `1` | 1-bit value (RFC 9134 / TR-10-15 §9) |
| `packetmode` | `0` or `1` | 1-bit value (RFC 9134 / TR-10-15 §9) |

Optional parameters validated when present:

| Parameter | Valid values | Spec ref |
| --- | --- | --- |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` | ST 2110-22 §7 |
| `TP` | `2110TPNL`, `2110TPW` | ST 2110-22 §7 (2110TPN is **not** valid) |
| `MAXUDP` | positive integer ≤ 8960 (Extended UDP Size Limit) | ST 2110-10 §6.4 |
| `CMAX` | positive integer | ST 2110-22 §7 |
| `fbblevel` | positive integer | TR-10-11 §12 |

A `b=AS:<positive integer>` bandwidth line is **required** on every `jxsv` media block (TR-10-7 §11 / ST 2110-22 §7.3).

### ST 2110-41 (fast metadata) `fmtp` parameters

Fast metadata flows use rtpmap encoding name `ST2110-41` at clock rate 90000. The clock rate is validated and must be exactly 90000.

| Parameter | Example | Validated |
| --- | --- | --- |
| `SSN` | `ST2110-41:2024` | yes — required; must be `ST2110-41:YYYY` (4-digit year) |
| `DIT` | `100` | yes — required; must be a non-negative integer |

---

## IPMX Validation

`sdp.parse(text, "ipmx")` or `doc:validate("ipmx")` runs ST 2110 validation first
on all non-USB media blocks, then checks IPMX-specific requirements:

### Core requirements

| Check | Spec ref | Detail |
| --- | --- | --- |
| `a=group:FID` forbidden | TR-10-1 §10 | FID (Flow Identification) semantics shall not be used; any session-level `a=group:FID` is rejected |
| Media port must be even and > 1024 | TR-10-1 §7 | Applies to all non-USB RTP media blocks |
| Media port must be ≤ 65535 | RFC 768 | Applies at the parser level to all `m=` blocks (rejected during parse, not validate) |
| `a=extmap` present with valid URI | IPMX §6 / RFC 5285 | Must appear at session level or in at least one RTP media block; every `a=extmap` value must be in RFC 5285 format: `entry-count[/direction] URI` where direction is `sendonly`, `recvonly`, `sendrecv`, or `inactive` and URI has a scheme (e.g. `urn:`, `http:`); ID must be 1–255; IDs must be unique within their scope (session scope and each media-block scope are checked separately) |
| PEP IV-Counter `a=extmap` direction must be `/sendonly` | TR-10-13 §20.1 | Applies when URI is `urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter` or `…:PEP-Short-IV-Counter` |
| `IPMX` bare flag in every `a=fmtp` | TR-10-1 §10.1 | Required in all non-USB media blocks |
| Audio encoding | TR-10-3 §8 / TR-10-12 | `L16`, `L24` (TR-10-3 PCM) or `AM824` (TR-10-12 AES3 transparent transport) |
| `a=ptime` required for audio blocks | TR-10-3 §8 | Must be present on every IPMX audio media block |
| `a=setup` enum | RFC 4145 §4 | `active`, `passive`, `actpass`, or `holdconn` (USB blocks further required to be `passive` per TR-10-14 §14) |
| `a=connection` enum | RFC 4145 §4 | `new` or `existing` |

### Required IPMX fmtp parameters

#### Baseband measurement params (TR-10-1 §10.2 / §10.3, TR-10-9 §10)

Every IPMX video and audio media block's `a=fmtp` must include these parameters
as positive integers. TR-10-1 specifies them for baseband senders; TR-10-9 §10
extends the requirement to non-baseband IPMX senders (with the values reflecting
the rtpmap signaling). The SDP-level validator therefore requires presence on
every IPMX video/audio fmtp.

| Parameter | Media type | Spec ref |
| --- | --- | --- |
| `measuredpixclk` | video | TR-10-1 §10.2 |
| `vtotal` | video | TR-10-1 §10.2 |
| `htotal` | video | TR-10-1 §10.2 |
| `TP` | video | TR-10-TP-1 §13.2 |
| `measuredsamplerate` | audio | TR-10-1 §10.3 |

### Optional extensions (validated when present)

#### HDCP Key Exchange — `a=hkep` (TR-10-5 §10)

`a=hkep` is a **session-level** attribute (TR-10-5 §10); media-level placement
is rejected. When present, the value is validated against:

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

A trailing semicolon after the last parameter is rejected (TR-10-13 §13).

A session-level `a=privacy` is the default for each media-level `a=privacy`
(TR-10-13 §13 line 859). For DUP-group consistency checks, the library compares
the *effective* (media-or-session) value across legs — a leg without a
media-level `a=privacy` inherits the session-level value.

| Parameter | Valid values |
| --- | --- |
| `protocol` | RTP blocks: `RTP` or `RTP_KV`. USB blocks: `USB_KV` (only) |
| `mode` | RTP blocks: any of the 12 AES modes below. USB blocks: AAD variants only |
| `iv` | 16 hex digits (64-bit) |
| `key_generator` | 32 hex digits (128-bit) |
| `key_version` | 8 hex digits (32-bit) |
| `key_id` | 16 hex digits (64-bit) |

**Valid `mode` values (RTP blocks):**
`AES-128-CTR`, `AES-256-CTR`, `AES-128-CTR_CMAC-64`, `AES-256-CTR_CMAC-64`,
`AES-128-CTR_CMAC-64-AAD`, `AES-256-CTR_CMAC-64-AAD`,
`ECDH_AES-128-CTR`, `ECDH_AES-256-CTR`, `ECDH_AES-128-CTR_CMAC-64`,
`ECDH_AES-256-CTR_CMAC-64`, `ECDH_AES-128-CTR_CMAC-64-AAD`, `ECDH_AES-256-CTR_CMAC-64-AAD`

On **USB blocks** (`m=application <port> TCP usb`), only the four AAD variants are accepted
(TR-10-14 §14): `AES-128-CTR_CMAC-64-AAD`, `AES-256-CTR_CMAC-64-AAD`,
`ECDH_AES-128-CTR_CMAC-64-AAD`, `ECDH_AES-256-CTR_CMAC-64-AAD`.

#### USB transport — TR-10-14

Strictly identified by `m=application <port> TCP usb` (per TR-10-14 §14). USB blocks
bypass ST 2110 media-block validation (they are not RTP streams) and additionally
require:

| Check | Spec ref |
| --- | --- |
| `a=setup:passive` is present (no other value accepted) | TR-10-14 §14 (RFC 4145) |
| `a=privacy` (when present) uses `protocol=USB_KV` and an AAD mode | TR-10-14 §14 |
| RTP-specific attributes (`a=rtpmap`, `a=fmtp`, `a=mediaclk`, `a=ts-refclk`) are rejected — RFC 4145 transport has no RTP layer | TR-10-14 §14 (RFC 4145) |

Other non-RTP application blocks (e.g. `m=application <port> TCP/MSRP *`) bypass
ST 2110 RTP-specific checks but are not subject to the TR-10-14 USB rules.

#### HDMI InfoFrame — `a=infoframe` (TR-10-10 §8)

`a=infoframe` is a **session-level** attribute; media-level placement is
rejected. When present, the value is validated:

```text
a=infoframe:<port> SSN=ST2110-41:YYYY;DIT=100100
```

| Field | Validation |
| --- | --- |
| `<port>` | Integer; SHALL equal some media block's UDP port + 3 (TR-10-10 §8). Multiple `a=infoframe` lines must use distinct ports. |
| `SSN` | Must be `ST2110-41:YYYY` (4-digit year) |
| `DIT` | Must be exactly `100100` (HDMI InfoFrame Data Item Type) |

Absence is fine (the attribute is optional).

#### Bit rate — `b=AS` (TR-10-7 §11)

When present on an RTP media block, the `b=AS` value (kbps) must be a positive integer. This is the maximum target bit rate of the stream including IP/UDP/RTP headers. Required for VBR compressed video flows (TR-10-7).

#### FEC — `FECPROFILE` and latency parameters (TR-10-6 §7.6)

When the `FECPROFILE` key appears in a media block's `a=fmtp`, the library validates:

| Parameter | Validation |
| --- | --- |
| `FECPROFILE` | Must be `profile-a` |
| `FEC_ADD_LATENCY_VIDEO` | Non-negative integer (microseconds); `FECPROFILE` must also be present |
| `FEC_ADD_LATENCY_AUDIO` | Non-negative integer (microseconds); `FECPROFILE` must also be present |

#### ST 2022-7 DUP group — privacy consistency (TR-10-13 §13)

When `a=group:DUP` is present, the library checks that all legs in the group
carry **identical** `a=privacy` values. Inheritance is applied first: a leg
without a media-level `a=privacy` inherits the session-level value (TR-10-13
§13 line 859) before legs are compared.

#### RTCP port convention (TR-10-1 §8.7)

IPMX mandates that RTCP Sender Reports are sent to media port + 1. The library checks:

| Check | Result |
| --- | --- |
| `a=rtcp-mux` present on a media block | Rejected — RTCP must be on a separate port |
| `a=rtcp:<port>` with `port > 65535` | Rejected (above UDP range, RFC 768) |
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
