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
12. [Test Suite Organization](#test-suite-organization)

---

## Introduction

`parse_sdp` is a Lua 5.5 library for parsing, validating, and serializing SDP
(Session Description Protocol) files used in professional media over IP workflows.
It is built with [LPEG](https://www.inf.puc-rio.br/~roberto/lpeg/). Runtime
dependencies: LPEG, [dkjson](https://github.com/LuaDist/dkjson), and argparse
(CLI only — never loaded by `require("parse_sdp")`).

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
luarocks install parse_sdp
```

`lpeg`, `dkjson`, and `argparse` are installed automatically. `argparse` is only
used by the CLI — `require("parse_sdp")` never loads it.

### Manual

Copy `parse_sdp.lua` into your project. Install `lpeg` and `dkjson` separately
(and `argparse` if you want the CLI).

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

## What this library validates (and what it doesn't)

Strictness here is grounded in spec text, not opinion. The rule:

> A check belongs in this library only if the relevant standard explicitly
> **requires** something (*shall*, *MUST*), explicitly **forbids** something
> (*shall not*, *MUST NOT*, *is forbidden*), or **defines the form** an
> optional value must take when present. Anything the spec leaves silent
> passes.

This boundary is intentional. The library's job is **conformance** — not "is
this a sensible product configuration." Many SDPs from real ST 2110 and IPMX
senders contain unusual but legal choices; rejecting them would make the
library a liability rather than a guard.

### What we do reject

- **Required fields that are missing or malformed.** Examples:
  - RFC 4566 §5 required lines (`v=`, `o=`, `s=`, `t=`, `m=`) missing or in the
    wrong order.
  - ST 2110-20 video `a=fmtp` missing `sampling`, `depth`, `width`, `height`,
    `exactframerate`, `colorimetry`, `PM`, or `SSN` — every one of these is a
    "shall be signaled" parameter under §7.2. (TCS lives in §7.3 and is
    optional; receivers assume `SDR` when absent per §7.6.)
  - Audio `a=rtpmap` missing the channel count field (RFC 4566 §6 — channels
    are required for audio).
  - Dynamic payload types (96–127) without a corresponding `a=rtpmap` to give
    them meaning (RFC 3551 §6).
- **Explicit prohibitions.** Examples:
  - `depth=14` (ST 2110-20 §7.4.2 enumerates `{8, 10, 12, 16, 16f}`).
  - `width=40000` (ST 2110-20 §7.2 — "integers between 1 and 32767 inclusive").
  - `segmented` without `interlace` (ST 2110-20 §7.3 — "is forbidden").
  - `MAXUDP` with `PM=2110BPM` (ST 2110-20 §6.3.3 — "shall not be used in the
    Block Packing Mode").
  - `mediaclk:direct=10` (ST 2110-10 §7.3 — direct offset SHALL be zero).
  - `TROFF=0` (ST 2110-21 §8 — "decimal positive integer").
  - IPMX `a=rtcp-mux` (TR-10-1 §8.7 — RTCP must be on port+1).
  - IPMX `m=` ports that are odd or ≤ 1024 (TR-10-12 §7).
- **Optional fields whose values are ill-formed when present.** Optional
  parameters that the spec defines a value form or value set for are validated
  when present — absence is fine, malformed presence is not. Examples:
  - `a=mediaclk:direct=N` where N ≠ 0 (mediaclk is optional in RFC 4566; ST
    2110-10 §7.3 constrains the value when used).
  - Unrecognized `a=fmtp` flags that overlap a defined name — e.g.
    `interlace=anything` and `segmented=anything` are rejected because ST
    2110-20 §7.1/§7.3 define these as flag-only.
- **Cross-stream consistency** that ST 2022-7 / RFC 7104 requires for
  `a=group:DUP` legs — identical essence parameters, identical payload type
  number, distinct addresses on at least one axis.

### What we do not reject

- Configurations the spec describes as **"out of scope"** or
  **"permitted but not required."** For example, ST 2110-30 §6.1 mandates 48 kHz
  audio and permits 44.1/96 kHz, then says *"Other sampling frequencies and
  resolutions are out of scope of this standard."* That is not the same as
  *"shall not."* The validator accepts any well-formed positive rate. The same
  applies to audio channel count — ST 2110-30 documents Conformance Levels up
  to 64 channels but contains no global upper bound, so neither does the
  validator.
- Combinations the spec doesn't address. The spec lists `sampling`,
  `colorimetry`, `TCS`, and `RANGE` value sets independently. It does not list
  forbidden combinations of those values, so the validator accepts any
  combination of valid individual values. Some combinations (e.g.
  `sampling=RGB` with `colorimetry=BT2020`) are unusual but the spec contains
  no "shall not" against them.
- **NMOS-level concerns.** The IPMX profile documents describe MUST-support
  requirements at the device level — Senders MUST expose BCP-004-02 Sender
  Capabilities; Receivers MUST support both required format combinations; IS-04
  / IS-05 / IS-11 must be wired up. These are device-certification concerns and
  require state beyond a single SDP file. They live in the NMOS APIs, not in
  SDP, so this library cannot and does not validate them.
- **RTCP and Info Blocks.** IPMX Media Info Blocks (uncompressed, JPEG-XS, PCM,
  AES3), PEP Media Info Blocks, HKEP HDCP exchanges, and HDR metadata travel
  in RTP / RTCP, not in SDP. They are out of scope here even though the
  TR-10 documents discuss them.
- **Sender/Receiver capability subsetting.** The fact that a sender implements
  only Format A (RGB 4:4:4 8-bit) and not Format B (YUV 4:2:2 10-bit) is
  signaled via NMOS Sender Capabilities, not via SDP. The library accepts any
  conformant single SDP and does not infer device-wide capability claims from
  it.

### A practical test

When considering whether to add a check, you should be able to point to a
specific clause in a spec PDF or RFC and quote normative language — either a
positive *"shall"* / *"MUST"*, a prohibitive *"shall not"* / *"MUST NOT"* /
*"is forbidden"*, or a defined value form / value set for an optional
parameter. If the case for the check is *"but obviously a device that sends X
is broken"*, that's an indicator the check is opinion, not conformance — and
it doesn't belong here. If the case is *"the spec says SHALL X"*, *"the spec
says SHALL NOT X"*, or *"the spec defines the legal values for X as {…}"*,
quote it in the code comment and as the `spec_ref` field on the error.

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

- The address (before any `/<ttl>` or `/<numaddr>` suffix) must parse as a literal IPv4 (RFC 791) or IPv6 (RFC 2460) address, depending on the declared `addr_type`. FQDNs and malformed addresses (e.g. `c=IN IP4 1.2.3`, `c=IN IP4 999.0.0.0`, `c=IN IP6 not-an-ipv6`) are rejected.
- IPv4 multicast addresses (224.0.0.0–239.255.255.255) must include a TTL suffix (e.g. `239.100.0.1/64`). Per RFC 8866 §9 ABNF (`IP4-multicast = m1 3("." decimal-uchar) "/" ttl [ "/" numaddr ]`) the layered/hierarchical-multicast form `<addr>/<ttl>/<numaddr>` is also accepted (spec example `c=IN IP4 233.252.0.1/127/3`).
- IPv4 TTL must be an integer in the range 0–255 (RFC 8866 §5.7: *"TTL values MUST be in the range 0-255"*; §9 ABNF explicitly admits `"0"`).
- IPv4 layered `<numaddr>` must be a positive integer (RFC 8866 §9: `numaddr = integer = POS-DIGIT *DIGIT`).
- The Local Network Control Block (`224.0.0.0/24`) and Internetwork Control Block (`224.0.1.0/24`) are forbidden per RFC 5771.
- IPv4 unicast addresses must not carry a TTL suffix.
- IPv6 multicast addresses (`ff` prefix) may carry an optional `/<numaddr>` suffix (e.g. `ff02::1/64`) per RFC 8866 §9 ABNF (`IP6-multicast = IP6-address [ "/" numaddr ]`). Note: this is a layered-address count, **not** a TTL — RFC 8866 §5.7 prohibits TTL on IPv6 multicast.
- IPv6 unicast addresses must not include any `/` suffix.

### Per media block

`a=ts-refclk` may appear at session level (applying to all media blocks) or at each media-block level; the library accepts either location. **All** `a=ts-refclk` attributes are validated individually — if multiple are present (at any combination of session and media level), each must be a recognized, well-formed clock source (ST 2110-10 §8.2). All other attributes in this table must be per-media.

| Attribute | Requirement |
| --- | --- |
| `a=ts-refclk` | Required. The `ptp=` version token is restricted to `IEEE1588-2008` (ST 2110-10:2022 §6.1 mandates PTPv2; TR-10-1 §10.4 confirms the same for IPMX). `IEEE1588-2002`, `IEEE1588-2019`, and bare `IEEE1588` are rejected at both tiers. Accepted: `ptp=IEEE1588-2008:<gmid>:<domain>` (gmid is EUI-64; domain is 0–127; domain is required per ST 2110-10:2022 §8.2 "shall signal either clockIdentity AND domain number, OR traceable"); `ptp=IEEE1588-2008:traceable`; `localmac=<mac>`; `ntp=<addr>`; `gps`; `gal`; `glonass` |
| `a=mediaclk` | Required, **media-level only**. Accepted: `direct=0` (offset SHALL be zero per ST 2110-10 §8.3), `direct=0 rate=<int>/<int>` (RFC 7273 §5.4 pull-down form), or `sender`. Session-level `a=mediaclk` is rejected (ST 2110-10 §8.3) |
| `a=mid` | Optional. When present, value must be unique within the session (RFC 5888 §8.1). RFC 5888 imposes no position requirement on `a=mid` within a media block |
| `a=source-filter` | At ST 2110 tier: optional. At IPMX tier: **required** on every RTP block, either media-level or session-level (TR-10-TP-1 §13.2). Format follows RFC 4570 §3: `<incl\|excl> IN <addrtype> <dest> <src>+` where `addrtype` is `IP4`, `IP6`, or `*` (the last per RFC 4570 §3 ABNF — `*` mode expects FQDN dest/src). For `IP4` / `IP6` the dest and every src must be a literal address of the declared family — malformed addresses are rejected (ST 2110-10 §6.5 / RFC 4570). |
| `a=rtpmap` | Required. RTP payload type must be in the dynamic range 96–127 per ST 2110-10 §6.2 — *"unless a fixed payload type designation exists for that RTP Stream within the IETF standard which specifies it."* The carve-out admits two RFC 3551 §6 statics that match ST 2110-30 essences: PT 10 with `L16/44100/2` and PT 11 with `L16/44100/1`. No other ST 2110 encoding has a static PT. Clock rate validated: must be 90000 for video and `smpte291`. For `ST2110-41`, the rate is Data-Item-defined per §5.3 — the parser checks only that it is a positive integer. Audio clock rate accepted for any positive integer (ST 2110-30 §6.1 puts non-{44.1, 48, 96} kHz "out of scope" but does not forbid). Audio encoding name validated: must be `L16`, `L24`, or `AM824`. Payload type must match the payload type in `a=fmtp` |
| `a=fmtp` | Required for encodings whose spec mandates fmtp parameters (`raw` per ST 2110-20 §7.2, `jxsv` per ST 2110-22 §7, `ST2110-41` per ST 2110-41:2024 §6 — `SSN` required, `DIT` optional). **Not** required for audio (`L16`/`L24`/`AM824`) or `smpte291` ancillary — ST 2110-10:2022 §8 imposes no universal fmtp requirement, and the per-encoding IANA registrations leave fmtp optional for these. Key=value pairs are validated per sub-standard when present. Payload type must match the payload type in `a=rtpmap` (RFC 4566 §6) |

### ST 2110-20 (video) `fmtp` parameters

ST 2110-20 §7.2 requires eight `fmtp` parameters; ST 2110-21:2022 §8.1 adds a
ninth required parameter (`TP`) for any video stream conforming to
ST 2110-20:2022 §6.1.1's compliance chain. All nine are validated for both
presence and value format. TCS lives in §7.3 ("Media Type Parameters with
default values") and is optional — §7.6 says receivers assume `SDR` when TCS
is not signaled.

| Parameter | Example | Valid values |
| --- | --- | --- |
| `sampling` | `YCbCr-4:2:2` | `YCbCr-4:4:4`, `YCbCr-4:2:2`, `YCbCr-4:2:0`, `CLYCbCr-4:4:4`, `CLYCbCr-4:2:2`, `CLYCbCr-4:2:0`, `ICtCp-4:4:4`, `ICtCp-4:2:2`, `ICtCp-4:2:0`, `RGB`, `XYZ`, `KEY` |
| `width` | `1920` | integer between 1 and 32767 inclusive (ST 2110-20 §7.2) |
| `height` | `1080` | integer between 1 and 32767 inclusive (ST 2110-20 §7.2) |
| `exactframerate` | `30000/1001` | positive integer or `n/d` fraction (both parts positive, **in lowest terms** — `60000/2002` is rejected because ST 2110-20:2022 §7.2 requires "the numerically smallest numerator value possible") |
| `depth` | `10` | one of `8`, `10`, `12`, `16`, `16f` (ST 2110-20 §7.4.2) |
| `colorimetry` | `BT709` | `BT601`, `BT709`, `BT2020`, `BT2100`, `ST2065-1`, `ST2065-3`, `UNSPECIFIED`, `ALPHA`, `XYZ` |
| `PM` | `2110GPM` | `2110GPM`, `2110BPM` |
| `SSN` | `ST2110-20:2022` | must be `ST2110-20:YYYY` where YYYY is a 4-digit year. Per ST 2110-20:2022 §7.2, `SSN=ST2110-20:2022` is **required** whenever `TCS=ST2115LOGS3` or `colorimetry=ALPHA` is signaled (those values aren't defined in :2017). The reverse direction ("default to :2017 unless a :2022-only value is used") is not enforced — see PLAN.md "Known Deferred Items". |
| `TP` | `2110TPN`, `2110TPNL`, `2110TPW` | ST 2110-21:2022 §8.1 — required for any video stream conforming to the ST 2110-20 §6.1.1 → ST 2110-21 chain (i.e. all raw video) |

Optional parameters validated when present:

| Parameter | Valid values | Spec ref |
| --- | --- | --- |
| `TCS` | `SDR`, `PQ`, `HLG`, `LINEAR`, `BT2100LINPQ`, `BT2100LINHLG`, `ST2065-1`, `ST428-1`, `DENSITY`, `ST2115LOGS3`, `UNSPECIFIED` (the full 11-value enum per ST 2110-20:2022 §7.6; `ST2115LOGS3` was added in :2022). Absent → receivers assume `SDR` per §7.6. | ST 2110-20:2022 §7.3 / §7.6 |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` | ST 2110-20 §7.2 |
| `MAXUDP` | positive integer ≤ 8960 (Extended UDP Size Limit). Must **not** be signaled when `PM=2110BPM` — ST 2110-20 §6.3.3 forbids the Extended UDP size in Block Packing Mode. | ST 2110-10 §6.4, ST 2110-20 §6.3.3 |
| `PAR` | `W:H` (both positive integers, **in lowest terms** per ST 2110-20 §7.3 — e.g. `1:1`, `12:11`, `64:45`; `2:2` is rejected) | ST 2110-20 §7.3 |
| `TROFF` | positive integer in microseconds (`TROFF=0` rejected per the §8.2 value-form SHALL — §6.2 separately permits the underlying TROFFSET to be zero) | ST 2110-21:2022 §8.2 |
| `CMAX` | any integer. §8.2 defines the SDP form as "expressed as an integer number" — zero and negative integers are accepted because the spec attaches no sign restriction; §7.1's `MAX(4, …)` / `MAX(16, …)` formula is an upper bound on `CINST` (§6.6.1), not a lower bound on the SDP value. | ST 2110-21:2022 §8.2 |
| `TSMODE` | `SAMP`, `NEW`, `PRES` | ST 2110-10 §8.7 |
| `TSDELAY` | positive integer (microseconds — ST 2110-10 §8.7 defines this as a decimal positive integer; `TSDELAY=0` is rejected) | ST 2110-10 §8.7 |

Bare-flag parameters `interlace` and `segmented` are accepted. `segmented` SHALL only appear together with `interlace` (ST 2110-20 §7.3); signaling `segmented` alone is rejected. Both are flag-only — `interlace=anything` and `segmented=anything` are rejected (ST 2110-20 §7.1/§7.3 define no value form for these names). Any other unrecognized key=value pairs pass through silently.

**Cross-parameter SHALLs (raw video only):**

- **§7.4.1 KEY-sampling.** When `sampling=KEY`, the stream **shall** signal `colorimetry=ALPHA` and **shall not** signal a `TCS` value. Both halves are enforced. (RFC 9134 §7.1 carries the `sampling` value set into jxsv but does not import these cross-parameter constraints, so jxsv is unaffected — see PLAN.md "Pre-1.0 Conformance Audit" jxsv-scope discussion.)
- **§6.2.5 4:2:0 progressive-only.** *"The 4:2:0 sampling system shall only be applied to progressive scan images transmitted in a progressive manner. This sampling system does not apply to PsF or interlaced video essence."* `sampling=YCbCr-4:2:0`, `CLYCbCr-4:2:0`, or `ICtCp-4:2:0` combined with the bare `interlace` flag is rejected. (§6.2.5 sits in the RTP-payload pgroup-construction chapter, which jxsv does not use; RFC 9134 §7.1 inherits the sampling values, not the §6 packaging constraints, so jxsv is unaffected.)

### ST 2110-30 (audio) `rtpmap` and `fmtp` parameters

The `a=rtpmap` encoding name is validated: must be `L16`, `L24`, or `AM824`
(ST 2110-30 §6.1 mandates L16/L24; ST 2110-31 adds AM824 for AES3 transparent
transport).

**For L16 / L24:** the clock rate is **not enumerated**. ST 2110-30 §6.1
mandates 48 kHz and permits 44.1/96 kHz, then says *"Other sampling
frequencies and resolutions are out of scope of this standard."* Out-of-scope
is not the same as forbidden (no "shall not"), so any well-formed positive
rate is accepted. This matches IPMX practice, which already permits
AES67-extended rates such as 32 kHz, 88.2 kHz, 176.4 kHz, and 192 kHz.

**For AM824 (ST 2110-31:2022):** the clock rate **SHALL** be one of `44100`,
`48000`, or `96000` (§5.5 / §6.1). Channel count **SHALL** be even (§6.1:
each AES3 signal contains two AES3 Subframe sequences). `a=ptime` is
**required** (§6.1) and its value **SHALL** be one of the Table 1 entries
for the prevailing clock rate:

| `<clock-rate>` (Hz) | Permitted `<packet-time>` (ms) |
| --- | --- |
| 44100 | 1.09, 0.14, 0.09 |
| 48000 | 1, 0.12, 0.08 |
| 96000 | 1, 0.12, 0.08 |

The channel count (third `/`-separated component in the rtpmap value,
e.g. `L24/48000/8`) is required and must be a positive integer (RFC 3551 §6).
ST 2110-30 §6.2.2 / Table 2 documents Conformance Levels with channel counts
up to 64; the spec contains no global upper bound, so the validator imposes
none. `channel-order` is **optional** per ST 2110-30:2017 §6.2.2 ("If the
channel-order parameter is not present, the audio channels shall be treated as
Undefined"). When present, its value format is validated; mono
(`SMPTE2110.(M)`) is permitted.

`a=ptime` is **required** for every audio stream — ST 2110-30:2025 §6.2.1
chains audio to AES67 (*"Digital audio streams shall conform to AES67,
including the Session Description Protocol (SDP) as described in IETF
RFC 8866"*), and AES67-2018 §8.1: *"Descriptions shall include a ptime
attribute indicating the desired packet time."* Value must be a positive
decimal (RFC 4566). For AM824, `<packet-time>` must additionally come from
ST 2110-31:2022 §6.1 Table 1.

The validator also enforces that the resulting RTP payload size
(`channels × samples-per-packet × bytes-per-sample`, where L16=2 B, L24=3 B,
AM824=4 B) fits within `1460 − 12 B = 1448 B` of UDP payload (Standard UDP
Size Limit per ST 2110-10 §6.3, minus the 12-octet RTP fixed header).
**MAXUDP must not be signaled on audio** (ST 2110-30:2025 §6.2.1 mandates
the Standard limit); raising it is rejected — see N11 in PLAN.md.

| Parameter | Example | Valid values |
| --- | --- | --- |
| `channel-order` | `SMPTE2110.(ST)` | RFC 3190 §6 form `<convention>.<order>`. The convention is **SHOULD** `SMPTE2110` per ST 2110-30:2025 §6.2.2 — other tokens are accepted structurally (spec defines no symbol set for them). When the convention **is** `SMPTE2110`, the order **SHALL** be `(<group>[,<group>...])` where each group is `M`, `DM`, `ST`, `LtRt`, `51`, `71`, `222`, `SGRP`, `U01`–`U64`, or — only on AM824 streams — `AES3` (ST 2110-31:2022 §6.2 Table 2) |

### ST 2110-22 (JPEG-XS / jxsv) `fmtp` parameters

Compressed video flows use rtpmap encoding name `jxsv` at clock rate 90000
(ST 2110-22 / TR-10-11). The media type **must** be `video` per
ST 2110-22:2022 §6.2 (*"The media type name shall be 'video'"*); `m=application
… jxsv` is rejected. `PM` is **not** an ST 2110-22 parameter — that is a
ST 2110-20 (uncompressed video) packing-mode marker; the analogous control
for jxsv is `packetmode` (IANA `video/jxsv` / RFC 9134 §4.3).

ST 2110-22:2022 §7.2 Table 1 lists `width`, `height`, and `TP` as the only
mandatory format-specific parameters; the IANA `video/jxsv` registration
(RFC 9134 §7.1) additionally requires `packetmode`. §7.3 Table 3 makes
`b=AS:<kbps>` REQUIRED on every jxsv media block (now enforced at the
ST 2110 tier — was previously IPMX-only). §7.4 Table 4 makes frame-rate
signaling REQUIRED via either `a=framerate:<rate>` or fmtp
`exactframerate=<rate>`. §7.2 also forbids a trailing semicolon after the
last fmtp item (the post-`;` whitespace, however, is OPTIONAL in -22 §7.2,
unlike in -20 §7.1).

Everything else defined by the spec — `sampling`, `depth`, `TCS`,
`colorimetry`, `profile`, `level`, `sublevel`, `transmode` — is optional
and validated only when present. The IPMX JPEG-XS Video Profile §6.1.4
references several of these fields for the RTCP **JPEG-XS Media Info
Block** (type 0x0003), not SDP fmtp, and Media Info Blocks are out of
scope for this validator.

`fbblevel` is **not** an SDP fmtp parameter in any spec the parser tracks.
It appears only in the RTCP JPEG-XS Media Info Block (TR-10-15-Part1 §12,
encoded in the Plev 16-bit field alongside `sublevel`). The parser
accepts `fbblevel=…` in fmtp without validating its value form — there is
no SDP value form to validate.

`TP` permits all three values `2110TPN`, `2110TPNL`, `2110TPW` per the 2022
revision (`2110TPN` was added in ST 2110-22:2022 §7.2 Table 1).

Required parameters (all must be present):

| Parameter | Example | Valid values |
| --- | --- | --- |
| `width` | `1920` | positive integer |
| `height` | `1080` | positive integer |
| `TP` | `2110TPN` | `2110TPN`, `2110TPNL`, `2110TPW` (per ST 2110-22:2022 §7.2 Table 1) |
| `packetmode` | `0` or `1` | 1-bit value (IANA `video/jxsv` / RFC 9134 §4.3) |

Optional parameters validated when present:

| Parameter | Valid values | Spec ref |
| --- | --- | --- |
| `sampling` | same set as ST 2110-20 (including `RGB`, `XYZ`, `KEY`) | RFC 9134 §7.1 |
| `depth` | positive integer | RFC 9134 §7.1 |
| `exactframerate` | positive integer or `n/d` fraction | RFC 9134 §7.1 |
| `TCS` | same set as ST 2110-20 | RFC 9134 §7.1 |
| `colorimetry` | same set as ST 2110-20 | RFC 9134 §7.1 |
| `SSN` | `ST2110-22:YYYY` (4-digit year) | ST 2110-22:2022 §7.2 Table 2 (not defined in 2019) |
| `profile` | enum (TR-10-15 §8 / TR-08 §8.1.1): `Unrestricted`, `Light422.10`, `Light444.12`, `LightSubline422.10`, `LightSubline444.12`, `Main422.10`, `Main444.12`, `High444.12`, `MLS.12`, `LightBayer`, `MainBayer`, `HighBayer`, `MLSBayer` | ST 2110-22:2022 §7.2 |
| `level` | enum (TR-10-15 §9 / ISO/IEC 21122-2): `Unrestricted`, `1k-1`, `2k-1`, `4k-1`, `4k-2`, `4k-3`, `8k-1`, `8k-2`, `8k-3`, `16k-1`, `16k-2`, `16k-3` | ST 2110-22:2022 §7.2 |
| `sublevel` | enum (TR-10-15 §7.1 / ISO/IEC 21122-2): `Unrestricted`, `Full`, `Sublev12bpp`, `Sublev9bpp`, `Sublev6bpp`, `Sublev4bpp`, `Sublev3bpp`, `Sublev2bpp` | ST 2110-22:2022 §7.2 |
| `transmode` | `0` or `1` (1-bit value) | IANA `video/jxsv` / TR-10-15 §9 |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` | RFC 9134 §7.1 |
| `MAXUDP` | positive integer ≤ 8960 (Extended UDP Size Limit) | ST 2110-10 §6.4 |
| `CMAX` | any integer (per ST 2110-21:2022 §8.2 — see uncompressed-video table above for the §7.1 upper-bound caveat) | ST 2110-21:2022 §8.2 (referenced by ST 2110-22:2022 §7.2 Table 2) |

Bare-flag parameters `interlace` and `segmented` are accepted on jxsv flows under the same rules as raw video (RFC 9134 §7.1 — same wording as ST 2110-20 §7.3): both are flag-only (`interlace=anything` / `segmented=anything` are rejected), and `segmented` SHALL only appear together with `interlace` (RFC 9134 §7.1: *"Signaling of this parameter without the interlace parameter is forbidden."*).

A `b=AS:<positive integer>` bandwidth line is **required** on every `jxsv` media block (TR-10-7 §11 / ST 2110-22 §7.3).

### ST 2110-40 (smpte291 ancillary data) `fmtp` parameters

Ancillary data flows use rtpmap encoding name `smpte291` at clock rate 90000 (RFC 8331). ST 2110-40:2023 §7 adds explicit SDP requirements on top of RFC 8331; the parser enforces the 2023 revision.

Required parameters (all must be present):

| Parameter | Example | Valid values |
| --- | --- | --- |
| `SSN` | `ST2110-40:2018` | `ST2110-40:2018` when `TM` is absent; `ST2110-40:2023` when `TM` is signaled (ST 2110-40:2023 §7) |
| `exactframerate` | `25` | positive integer or `n/d` fraction (ST 2110-20:2022 §7.2 form, per ST 2110-40:2023 §7) |

Optional parameters validated when present:

| Parameter | Valid values | Spec ref |
| --- | --- | --- |
| `TM` | `LLTM` or `CTM` | ST 2110-40:2023 §7 (LLTM required if sender implements the Low-Latency Transmission Model; CTM may be signaled; if absent, receivers default to CTM) |
| `TROFF` | positive integer (µs), per ST 2110-21 §8 form | ST 2110-40:2023 §7 (presence required only when the sender's TR_OFFSETANC differs from the prevailing video format's TRO_DEFAULT — a runtime property not observable from SDP, so only value form is validated here) |
| `DID_SDID` | `{0xHH,0xHH}` (two hex octets) | RFC 8331 §4 — optional; may appear multiple times; every entry is validated |
| `VPID_Code` | non-negative integer | ST 2110-40 §7.2 — optional |

`SSN=ST2110-40:2021` is not accepted from senders. Per ST 2110-40:2023 §7, receivers shall treat that value as equivalent to `ST2110-40:2023`, but senders shall signal `ST2110-40:2023` itself. Validating an SDP authored by a sender, this parser holds senders to the strict form.

ST 2110-40:2023 §7 also forbids `a=group:FID` semantics: *"Flow Identification ('FID') semantics shall not be used under this standard."* At the ST 2110 tier, the parser rejects session-level `a=group:FID` whenever any media block carries an `smpte291` rtpmap. (At the IPMX tier, TR-10-1 §10 broadens the prohibition: any `a=group:FID` is rejected regardless of essence.)

### ST 2110-41 (fast metadata) `fmtp` parameters

Fast metadata flows use rtpmap encoding name `ST2110-41`. The clock rate is
Data-Item-defined per ST 2110-41:2024 §5.3 (*"The RTP Clock rate and RTP
Timestamp requirements of each Data Item are defined in the document that
specifies the Data Item Package Contents"*), so the parser validates only
that the rate is a positive integer — it is **not** fixed at 90 kHz.

| Parameter | Example | Validated |
| --- | --- | --- |
| `SSN` | `ST2110-41:2024` | yes — required per ST 2110-41:2024 §6; must be `ST2110-41:YYYY` (4-digit year) |
| `DIT` | `100,2000A1,1013FC,3FFF00` | optional (SHOULD per §6; Optional Parameter per §9.2.3). When present: comma-separated uppercase hex tokens; no `0x` prefix; no whitespace |

---

## IPMX Validation

`sdp.parse(text, "ipmx")` or `doc:validate("ipmx")` runs ST 2110 validation first
on all non-USB media blocks, then checks IPMX-specific requirements:

### Core requirements

| Check | Spec ref | Detail |
| --- | --- | --- |
| `a=group:FID` forbidden | TR-10-1 §10 | FID (Flow Identification) semantics shall not be used; any session-level `a=group:FID` is rejected |
| At least one media block required | ST 2110-10 §7 | IPMX is built on ST 2110-10 §7/§8.1 SDP signaling; an SDP with zero `m=` blocks isn't describing any IPMX stream |
| Media port must be even and > 1024 | TR-10-2 §7 | "All IPMX Media streams shall have a UDP destination port value that is even and that is greater than 1024." Wording is repeated identically across every per-essence TR-10 (-2 §7, -3 §7, -4 §7, -11 §7, -12 §7); TR-10-2 cited as canonical. Applies to all non-USB RTP media blocks |
| Media port must be ≤ 65535 | RFC 768 | Applies at the parser level to all `m=` blocks (rejected during parse, not validate) |
| `a=extmap` format when present | RFC 5285 | `a=extmap` is **not required** at the IPMX baseline (M31 removed an unconditional requirement that had no spec basis). When present, every `a=extmap` value must be in RFC 5285 format: `entry-count[/direction] URI` where direction is `sendonly`, `recvonly`, `sendrecv`, or `inactive` and URI has a scheme (e.g. `urn:`, `http:`); ID must be 1–255; IDs must be unique within their scope. TR-10-13 §1.1.1 mandates `a=extmap` only when declaring RTP Extension Headers for PEP (privacy) |
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

#### HDCP Key Exchange — `a=hkep` (TR-10-5 §10 / §17)

`a=hkep` may appear at session level, at media level, or at both
(TR-10-5 §17 IANA Registration: *"its Usage Level is 'session, media'"* —
a session-level value acts as the default for media legs lacking an
explicit `a=hkep`). TR-10-5 §10 separately requires *at least one*
session-level `a=hkep` whenever the stream carries HDCP Content. When
present at either level, the value is validated against:

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

TR-10-1 §8.7 mandates that RTCP Sender Reports are sent to media port + 1. The library
checks:

| Check | Spec ref | Result |
| --- | --- | --- |
| `a=rtcp-mux` present on a media block | TR-10-1 §8.7 + RFC 5761 | Rejected — TR-10-1 §8.7 mandates port+1; RFC 5761 defines `rtcp-mux` as RTP/RTCP on the same port, which contradicts the §8.7 "shall" |
| `a=rtcp:<port>` with `port > 65535` | RFC 768 | Rejected (above UDP range) |
| `a=rtcp:<port>` present but `port ≠ media-port + 1` | TR-10-1 §8.7 | Rejected |
| No `a=rtcp` present | — | Accepted (implicit port+1 convention) |

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
(t= [r=]*)+
[z=]
[k=]
[a=]*
[m=
  [i=]
  [c=]
  [b=]*
  [k=]
  [a=]*
]*
```

Line endings are `\r\n`. The serializer never emits optional fields that are `nil`.
Output is always a valid, strictly conformant SDP document.

`session.time_descriptions` is a list of `{ start, stop, repeats=[…] }` entries
covering all `(t=, r=*)` blocks. `session.timing` mirrors the first entry's
`{start, stop}` for back-compat. `session.time_zones` is a list of
`{adjustment_time, offset}` pairs. `session.key` and `m.key` carry
`{method, value?}` per RFC 4566 §5.12.

## Test Suite Organization

The hermetic test suite (`busted spec/`) splits into seven files along a
single axis: **what kind of code each test exercises.** Every `it` block
falls into exactly one of four buckets.

| File | Bucket | What it tests |
| --- | --- | --- |
| `spec/sdp_spec.lua` | **standards** | RFC 4566 / RFC 8866 — base SDP behavior. Every test ties to a specific clause. |
| `spec/st2110_spec.lua` | **standards** | SMPTE ST 2110 (-10, -20, -21, -22, -30, -31, -40, -41). Every test cites the section. |
| `spec/ipmx_spec.lua` | **standards** | VSF TR-10 / IPMX. Every test cites the TR clause. |
| `spec/library_spec.lua` | **library API** | The public surface — `sdp.parse`, `sdp.new`, `doc:validate`, `doc:is_sdp` / `is_st2110` / `is_ipmx`, `doc:to_json`. Sanity, mode dispatch, predicate behavior, error-table shape. Not tied to any spec. |
| `spec/cli_spec.lua` | **library API** | The CLI surface — `parse_sdp to_json` / `to_sdp` subcommands, exit codes, `--help`, `--pretty`, `--mode`. Not tied to any spec. |
| `spec/grammar_spec.lua` | **internal helpers** | The LPEG primitive parsers exposed as `parse_sdp._grammar`. Internal-only (not in the public contract); useful for parser-dev iteration and sharp regression diagnostics. White-box: a refactor that inlined these helpers into `parser.parse` would fail them even with identical public-API behavior. |
| `spec/errors_spec.lua` | **internal helpers** | The error formatter exposed as `parse_sdp._errors`. Also internal-only and white-box. |

The split exists so that:

- A reader looking at `sdp_spec.lua` / `st2110_spec.lua` / `ipmx_spec.lua`
  knows every test is grounded in published spec text. There is no need
  to wonder whether a given check is opinion or convention.
- A reader looking at `library_spec.lua` / `cli_spec.lua` knows the tests
  cover the user-facing API contract and can be updated freely when the
  API evolves (as long as the spec-tied tests still pass).
- A reader looking at `grammar_spec.lua` / `errors_spec.lua` knows the
  tests are white-box characterization tests for internal helpers. If
  the parser or error formatter is ever rewritten, these tests may need
  to be rewritten or removed with no impact on observable behavior.

Tests in the non-standards files carry an inline comment marker on the
line above each `it`:

```lua
  -- NOT-SPEC: library         -- in library_spec / cli_spec
  -- NOT-SPEC: implementation  -- in grammar_spec / errors_spec
```

The markers exist so the boundary stays grep-able even if a test is
moved or copied between files.

### Running tests

```sh
busted spec/                  # full hermetic suite
busted spec/sdp_spec.lua      # one file
busted spec/library_spec.lua  # just the library API tests
```

There is also an opt-in conformance suite under `spec_conformance/` that
downloads pinned AMWA fixtures and parses them; see that directory's
README for details.
