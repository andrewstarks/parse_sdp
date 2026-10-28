# parse_sdp guide

This guide is the full reference for `parse_sdp`, a Lua library that
parses, validates, and serializes Session Description Protocol (SDP)
files. [README.md](README.md) is the short introduction. This guide
covers the library API, the command-line tool, the shape of the parsed
document, and every validation check with the specification clause that
the check cites.

## Contents

1. [What the library does](#what-the-library-does)
2. [Background: SDP, ST 2110, and IPMX](#background-sdp-st-2110-and-ipmx)
3. [Installation](#installation)
4. [Quick start: parse, validate, serialize](#quick-start-parse-validate-serialize)
5. [Producer workflow: building an SDP file for a sender](#producer-workflow-building-an-sdp-file-for-a-sender)
6. [API reference](#api-reference)
7. [Command-line reference](#command-line-reference)
8. [Parsed Table Structure](#parsed-table-structure)
9. [Error and finding tables](#error-and-finding-tables)
10. [What this library validates (and what it doesn't)](#what-this-library-validates-and-what-it-doesnt)
11. [ST 2110 validation checks](#st-2110-validation-checks)
12. [IPMX validation checks](#ipmx-validation-checks)
13. [Serialization to SDP text](#serialization-to-sdp-text)
14. [Test suite organization](#test-suite-organization)

---

## What the library does

`parse_sdp` is a Lua library that parses, validates, and serializes
Session Description Protocol (SDP) files. In professional media over
Internet Protocol (IP), an SDP file describes one Real-time Transport
Protocol (RTP) stream that a sender transmits. The library runs on Lua
5.1, 5.2, 5.3, 5.4, and 5.5. The parser is built with
[LPEG](https://www.inf.puc-rio.br/~roberto/lpeg/) (Parsing Expression
Grammars for Lua). The runtime dependencies are LPEG and
[dkjson](https://github.com/LuaDist/dkjson). The command-line tool also
uses argparse; `require("parse_sdp")` does not load argparse. No
bit-manipulation rock is required on any Lua version: Lua 5.3 and later
use the native bitwise operators, and Lua 5.1 and 5.2 use a pure-Lua
arithmetic module that is included with the library.

The library validates at three tiers:

| Mode | Standard | Accepts |
| --- | --- | --- |
| `"sdp"` (default) | RFC 8866 | Any SDP file that conforms to RFC 8866 |
| `"st2110"` | SMPTE ST 2110 | SDP files that also conform to the SMPTE ST 2110 suite |
| `"ipmx"` | IPMX (VSF TR-10) | SDP files that also conform to the IPMX TR-10 suite |

Each tier runs every check of the tier below it and adds its own checks.
An SDP file that fails the `"sdp"` tier also fails the `"st2110"` and
`"ipmx"` tiers.

The library is strict, and the strictness is grounded in specification
text. An SDP file fails a tier's verdict when the relevant standard
explicitly requires, forbids, or defines the form of something and the
file violates that text. A configuration that the standard does not
address does not make a file fail. In this guide, "the check rejects X"
means that a file that contains X fails the tier's verdict. Every check
has a stable id and a `spec_ref` field that cites the clause. The section
[What this library validates (and what it doesn't)](#what-this-library-validates-and-what-it-doesnt)
states the rule and lists the RFC 8866 checks; the two sections after it
list the ST 2110 and IPMX checks. The library has no lenient mode.

At the RFC 8866 tier, the required lines must be present, the lines must
be in the order that RFC 8866 section 5 defines, and every value must
match the form the specification defines for it. A violation of one of
these rules produces a finding that names the line and column, or the
document field, and the check id. The serializer produces SDP text with
CRLF (carriage return and line feed) line endings in the RFC 8866 field
order.

### How much of a non-conforming file is checked

A file that fails the verdict is still checked to the end in most
cases. The parser records each finding and continues:

- By default (`opts.fail_on_first = false`), the parser records every
  finding that the parser can reach. The parse continues past semantic
  findings and soft-syntactic findings.
- The parse also continues past the registered hard-syntactic checks.
  Since version 1.7.0, these checks include the `.malformed` check of
  each known attribute (`sdp.a.<name>.malformed`, see
  [Malformed known attributes](#malformed-known-attributes)). The other
  registered hard-syntactic checks are `sdp.a.ts-refclk.ptp-malformed`
  and `st2110-20.a.fmtp.no-whitespace-around-equals`.
- Only a structural failure ends the parse. A structural failure is a
  grammar rule that has no check id: lines out of order, an unknown line
  letter, or a malformed `m=` or `o=` line, for example. The error then
  has `code = "PARSE_ERROR"` and names the line where matching stopped.
  The text after that line is not checked.

`sdp.parse` records every finding, but it returns only one of them.
When at least one finding has severity `error`, `sdp.parse` returns
`nil, err`, and `err` is the first error-severity finding. The other
findings are not returned. Three ways show every finding from one parse:

- Demote the error-severity checks to `"warn"` with `opts.policy`, then
  read `doc:findings()`. See [`sdp.parse`](#sdpparsetext--mode--opts).
- Run the command-line tool with `--all-findings`. See
  [All findings](#all-findings).
- Use the [browser playground](#browser-playground). The playground lists
  every finding at all three tiers.

`opts.fail_on_first = true` stops the parse at the first error-severity
finding.

---

## Background: SDP, ST 2110, and IPMX

### SDP (RFC 8866)

The Session Description Protocol describes multimedia sessions in a
plain-text format. RFC 8866 is the current definition of SDP and
obsoletes RFC 4566. Each line has the form:

```text
<type>=<value>
```

The lines must appear in the order that RFC 8866 section 5 defines. A
session description starts with a session-level section (`v=` through
the session-level `a=` lines), followed by zero or more media
descriptions. Each media description starts with an `m=` line.

Minimal valid SDP:

```text
v=0
o=- 1234567890 1 IN IP4 192.0.2.1
s=My Session
t=0 0
```

RFC 8866 does not require a media description, so the four lines above
are a valid SDP file at the `"sdp"` tier. SMPTE ST 2110 and IPMX require
at least one media description.

### SMPTE ST 2110

SMPTE ST 2110 is a suite of standards from the Society of Motion Picture
and Television Engineers (SMPTE) for professional media transport over
IP using RTP. Each stream is described by an SDP file that includes the
attributes a receiver needs to join the stream, so no other negotiation
is needed. The validator cites these parts of the suite:

| Standard | Subject |
| --- | --- |
| ST 2110-10 | System timing, the SDP requirements common to every stream, and ST 2022-7 redundancy grouping |
| ST 2110-20 | Uncompressed active video (`raw`) |
| ST 2110-21 | Traffic shaping and delivery timing of video |
| ST 2110-22 | Constant bit-rate compressed video, with RFC 9134 for the JPEG XS (`jxsv`) payload format |
| ST 2110-30 | PCM (pulse-code modulation) digital audio (`L16`, `L24`) |
| ST 2110-31 | AES3 transparent transport (`AM824`) |
| ST 2110-40 | Ancillary data (`smpte291`), with RFC 8331 |
| ST 2110-41 | Fast metadata (`ST2110-41`) |

### IPMX

IPMX (Internet Protocol Media Experience) is a set of specifications
from the Video Services Forum (VSF), published as the TR-10 series, for
professional audio-visual (AV) transport over IP. IPMX builds on ST 2110
and adds requirements of its own. The validator cites these TR-10
parts: TR-10-1 (system requirements), TR-10-2 (the UDP port rule for
media streams), TR-10-5 (HDCP key exchange, the `a=hkep` attribute),
TR-10-6 (forward error correction parameters), TR-10-10 (HDMI InfoFrame
transport, the `a=infoframe` attribute), TR-10-13 (privacy encryption,
the `a=privacy` attribute), and TR-10-14 (USB transport).

---

## Installation

### Supported Lua versions

The library supports Lua 5.1, 5.2, 5.3, 5.4, and 5.5. Continuous
integration runs the full test suite on each version. Lua 5.3 and later
use the native bitwise operators. Lua 5.1 and 5.2 use the pure-Lua
arithmetic module `parse_sdp.grammar.bitops_compat`, which the library
selects at `require` time. No additional rock is needed on any version.

### LuaRocks

```sh
luarocks install parse_sdp
```

LuaRocks installs `lpeg`, `dkjson`, and `argparse` as dependencies. Only
the command-line tool uses `argparse`; `require("parse_sdp")` does not
load it.

### Manual installation

Copy the `parse_sdp/` directory into the project's Lua module path. The
directory contains `init.lua`, `errors.lua`, `serialize.lua`, and the
`grammar/` modules; there is no single-file version of the library.
Install `lpeg` and `dkjson` separately. Install `argparse` and copy
`bin/parse_sdp` only when the command-line tool is needed.

### Docker

```sh
docker build -t parse_sdp .
docker run --rm -v "$(pwd):/data" parse_sdp lua bin/parse_sdp to_json /data/session.sdp
```

The image contains Lua 5.5, LuaRocks, LPEG, dkjson, busted, and
argparse, with the repository copied to `/app`. The image has no entry
point, so the command names the interpreter and the script. The image's
default command runs the test suite (`busted spec/`).

### Browser playground

The playground at <https://andrewstarks.github.io/parse_sdp/> is the
library compiled to WebAssembly (Lua 5.5, LPEG, and `parse_sdp`, built
with Emscripten) behind a static page. The page accepts SDP text, the
JSON form of a parsed document, or a Lua table literal in the same
shape. The page also loads an SDP file from a URL, and a link with
`?url=<address>` loads and checks that file when the page opens. The
page reports every finding at all three tiers, lets the user
edit the document field by field with `doc:validate` running on each
change, and downloads the serialized SDP or JSON. The page does not
upload the input. The only request that the page sends for an input is
the request for a URL that the user gives. [web/MANUAL.md](web/MANUAL.md) is the user manual for the page.
The JSON request and response format between the page and the library
is documented in [web/CONTRACT.md](web/CONTRACT.md), and
`web/wasm/build.sh` reproduces the build locally.

---

## Quick start: parse, validate, serialize

```lua
local sdp    = require("parse_sdp")
local errors = require("parse_sdp.errors")

local text = io.open("session.sdp"):read("*a")

-- Parse and validate at the RFC 8866 tier. On failure, doc is nil and
-- err is a finding table (see "Error and finding tables").
local doc, err = sdp.parse(text)
if not doc then
  io.stderr:write(errors.format(err) .. "\n")
  os.exit(1)
end

-- doc is a plain table. Read the fields directly.
print(doc.session.name)
print(doc.origin.unicast_address)
print(#doc.media)

-- Soft-syntactic findings (a bare LF line ending, trailing whitespace,
-- a byte order mark) are warnings. They do not fail the parse.
for _, w in ipairs(doc:warnings()) do
  io.stderr:write("warn: " .. w.id .. ": " .. w.message .. "\n")
end

-- Validate at a stricter tier.
local ok, err2 = doc:validate("st2110")
if not ok then print(err2.id, err2.message) end

-- Change the table and check it again.
doc.session.name = "Updated Session"
print(doc:is_sdp())    -- true
print(doc:is_st2110()) -- depends on the content

-- Serialize the table to SDP text.
local out = doc:to_sdp()
io.open("out.sdp", "w"):write(out)

-- Or to JSON.
print(doc:to_json())
```

---

## Producer workflow: building an SDP file for a sender

A device manufacturer or an SDK developer who produces SDP files can use
the library as a build-time validator. The intended loop is:

```text
1. Build a Lua table and wrap it with sdp.new, or change an existing doc.
2. Call doc:to_sdp().        It reports structural gaps: missing required fields.
3. Call doc:validate(mode).  It reports specification violations: wrong values,
                             missing per-tier attributes, malformed values.
4. Fix the field that the error names.
5. Repeat until doc:is_<tier>() returns true. Then emit the text.
```

`to_sdp()` and `validate()` answer two different questions. `to_sdp()`
answers whether the document can be rendered at all; it fails only when
a required field is missing. `validate()` answers whether the document
conforms to the chosen tier; it runs the full grammar and the per-tier
semantic checks. `to_sdp()` reports shape problems while the document is
being built, and `validate()` names the specification clause to read
next.

### Worked example: an ST 2110-20 video sender

The example builds a 1080p25 raw video sender from an empty table. Run
the checks after each step; the error message names the next thing to
add. [`examples/producer_walkthrough.lua`](examples/producer_walkthrough.lua)
is the runnable version and prints the result of every step.

```lua
local sdp = require("parse_sdp")

-- Step 1: an empty doc. to_sdp reports the first missing required field.
local text, err = sdp.new({}):to_sdp()
-- text           is nil
-- err.message    is "cannot serialize: missing required field session"
-- err.field_path is "session"

-- Step 2: a minimal session. It passes the "sdp" tier. It fails the
-- "st2110" tier because ST 2110-10:2022 section 8.1 requires the SDP
-- file to describe an RTP stream, and there is no m= line yet.
local doc = sdp.new({
  version = "0",
  origin  = { username="-", sess_id="1", sess_version="1",
              net_type="IN", addr_type="IP4", unicast_address="192.0.2.1" },
  session = {
    name = "Camera 1",
    time_descriptions = { { start=0, stop=0, repeats={} } },
  },
  media = {},
})
-- doc:validate()         returns true
-- doc:validate("st2110") returns nil, err with
--   err.id = "st2110-10.m.media-description-required"

-- Step 3: a bare m= block. RFC 8866 section 8.2.3 requires an a=rtpmap
-- line for a dynamic payload type such as 96.
doc.media[1] = {
  media = "video", port = 50000, proto = "RTP/AVP", fmts = { "96" },
  connection = { net_type="IN", addr_type="IP4", address="239.0.0.1/64" },
  attributes = {},
}
-- doc:validate() returns nil, err with
--   err.message = "dynamic RTP payload type (96-127) requires a matching a=rtpmap"

-- Step 4: add a=rtpmap. The "sdp" tier passes. The "st2110" tier now
-- requires the ST 2110-20:2022 section 7.2 fmtp parameters.
table.insert(doc.media[1].attributes,
  { name="rtpmap", payload_type=96, encoding="raw", clock_rate=90000 })
-- doc:validate("st2110") returns nil, err with
--   err.message = "fmtp for raw video must include required 'sampling' parameter"

-- Step 5: add a=fmtp with the parameters that ST 2110-20:2022 section 7.2
-- and ST 2110-21:2022 section 8.1 require.
table.insert(doc.media[1].attributes, {
  name="fmtp", payload_type=96,
  params = {
    {"sampling","YCbCr-4:2:2"}, {"width","1920"}, {"height","1080"},
    {"exactframerate","25"},    {"depth","10"},   {"colorimetry","BT709"},
    {"PM","2110GPM"},           {"SSN","ST2110-20:2022"}, {"TP","2110TPN"},
  },
})
-- doc:validate("st2110") returns nil, err with
--   err.id = "st2110.attr.mediaclk-required"

-- Step 6: add a=ts-refclk and a=mediaclk (ST 2110-10:2022 sections 8.2
-- and 8.3; the attribute forms are from RFC 7273).
table.insert(doc.media[1].attributes,
  { name="ts-refclk", source="ptp", version="IEEE1588-2008",
    grandmaster="00-1D-9A-FF-FE-2C-32-0F", domain="0" })
table.insert(doc.media[1].attributes,
  { name="mediaclk", mode="direct", offset=0 })
-- doc:is_st2110() returns true. doc:to_sdp() returns a conforming ST 2110 SDP file.
```

The loop is the same at each step: read the error, add the field, and
run the checks again. The validator names the missing or malformed field
and cites the clause in `spec_ref`.

### IPMX additions

IPMX requires attributes beyond ST 2110. For the video block above, the
`"ipmx"` tier requires the bare `IPMX` flag in the `a=fmtp` line
(TR-10-1 section 10.1) and the measurement parameters `measuredpixclk`,
`vtotal`, and `htotal` (TR-10-1 section 10.2). The same loop applies:

```lua
local ok, err = doc:validate("ipmx")
-- err.id       is "tr-10-1.a.fmtp.measuredpixclk-required"
-- err.message  is "a=fmtp on a video IPMX media block must include 'measuredpixclk'"
-- err.spec_ref is "TR-10-1 §10.2"
```

Add `{"IPMX", true}`, `{"measuredpixclk", "74250000"}`,
`{"vtotal", "1125"}`, and `{"htotal", "2640"}` to the fmtp `params` list
and validate again. The validator reports the measurement parameters
first and the `IPMX` flag after them, because the flag is checked once
per media block after the block has been parsed. The section
[IPMX validation checks](#ipmx-validation-checks) lists every IPMX
check; the producer loop turns that list into a checklist for the SDP
file being built.

### Iterating with malformed values that are known

While provisioning code is being written, a value such as a real PTP
(Precision Time Protocol) grandmaster identity may not be available yet.
The document can still be rendered and inspected without the grandmaster
check failing the parse. Demote the check with a policy:

```lua
local doc, err = sdp.parse(sdp_text, "st2110", {
  policy = {
    ["sdp.a.ts-refclk.ptp-malformed"] = "warn",  -- record the finding as a warning
  },
})
-- doc is returned; doc:warnings() contains the demoted finding.
-- Set the check back to "error" once the provisioning code is complete.
```

The same accessors are documented under
[`doc:findings()`, `doc:warnings()`, and `doc:errors()`](#docfindings-docwarnings-and-docerrors).
The pattern is useful both for debugging a document the producer built
and for prototyping against an incomplete environment.

Every known attribute has a check of the same kind for a value that does
not match the attribute's syntax, for example `sdp.a.ptime.malformed`
for `a=ptime:1.0`. When one of these checks is demoted, the attribute is
kept with `malformed = true` and its text in `value`. The section
[Malformed known attributes](#malformed-known-attributes) lists the
checks.

### Required-attribute checklists

The validator drives the loop. A static reference for the attributes a
tier requires is in these sections:

- ST 2110 per-media-block requirements: [ST 2110-10 checks](#st-2110-10-system-and-session-checks).
- ST 2110-20 video fmtp parameters: [ST 2110-20 raw video checks](#st-2110-20-raw-video-checks).
- IPMX measurement parameters: [TR-10-1 checks](#tr-10-1-system-checks).

The document shape for hand-built attributes (which keys each decomposed
attribute requires, and which attributes keep the generic `value` string)
is in [Parsed Table Structure](#parsed-table-structure) and under
[`sdp.new`](#sdpnewtable).

### Reference examples for every field

Four runnable examples show the Lua-table field names for every line
type and attribute. Each file builds on the previous one, so they are
best read in order:

| File | Content | Assertion at the end of the file |
| --- | --- | --- |
| [`examples/kitchen_sink.lua`](examples/kitchen_sink.lua) | Every RFC 8866 line type and every base-tier decomposed attribute (`rtpmap`, `fmtp`, `ssrc`, `ssrc-group`, `msid`, `extmap`, `rtcp`, `rtcp-fb`, `rtcp-mux`, `source-filter`, `mid`, `group`, `ts-refclk`, `mediaclk`), plus an unknown `x-vendor-*` attribute that passes through unchanged | parse, serialize, and re-parse produce a deep-equal table |
| [`examples/kitchen_sink_st2110.lua`](examples/kitchen_sink_st2110.lua) | One document with six media blocks: a raw video `a=group:DUP` pair, JPEG XS video, L24 audio, `smpte291` ancillary data, and ST 2110-41 fast metadata; the mandatory and optional ST 2110-20 and ST 2110-21 fmtp parameters; `TSMODE` and `TSDELAY` | `doc:is_st2110()` is true, and the document round-trips |
| [`examples/kitchen_sink_ipmx.lua`](examples/kitchen_sink_ipmx.lua) | The IPMX additions on top of the ST 2110 document: the `IPMX` fmtp flag and measurement parameters (TR-10-1), an `a=source-filter` on each block, `a=infoframe` (TR-10-10), `a=hkep` (TR-10-5), `a=privacy` (TR-10-13), and `FECPROFILE` (TR-10-6) | `doc:is_ipmx()` is true, and the document round-trips |
| [`examples/kitchen_sink_conflicts.lua`](examples/kitchen_sink_conflicts.lua) | Eight small SDP fixtures, one per forbidden combination that the three valid documents above cannot contain: a traceable and non-traceable `a=ts-refclk` mix, a malformed PTP grandmaster identity, a session-level-only `a=mediaclk`, `PM=2110BPM` with `MAXUDP`, a missing `IPMX` flag, an odd IPMX port, an IPv4 multicast `c=` without a TTL, and an IPv4 octet above 255 | each fixture is rejected with the expected `err.id` and `err.spec_ref` |

Every field in the three valid files has an inline comment with the RFC,
SMPTE, or TR-10 clause it comes from and a one-line description of the
field. The files therefore also serve as a producer-side reference for
which Lua keys each attribute requires and where the specification
defines the value.

#### Hex values in the Lua table

SDP is a text format, so every hexadecimal value that the specifications
define is a string on the wire and is also a string in the Lua table.
The library never converts a hexadecimal SDP value to or from a Lua
number, because the specification gives these values a structure
(separators, length, prefixes) that a number would lose. Four
hexadecimal shapes appear across the reference examples:

| Shape | Where it appears | Example | Shown in |
| --- | --- | --- | --- |
| Dash-separated octets (EUI-64 or EUI-48) | `ts-refclk:ptp=` grandmaster, `mediaclk:IEEE1722=` stream identity, `ts-refclk:localmac=`, IPMX `a=hkep` `port_id` | `"00-11-22-FF-FE-33-44-55"` | base, ST 2110, IPMX |
| UUID dashed form (32 hex digits) | IPMX `a=hkep` `node_id` | `"00112233-4455-6677-8899-aabbccddeeff"` | IPMX |
| Bare fixed-length hex string | IPMX `a=privacy` `iv` (16 digits), `key_generator` (32), `key_version` (8), `key_id` (16) | `"0123456789ABCDEF"` | IPMX |
| `0x`-prefixed octets in braces | `a=fmtp` `DID_SDID` per RFC 8331 section 4 | `"{0x41,0x07}"` | ST 2110 |

Only decimal fields are Lua numbers: ports, payload types, `ssrc_id`,
clock rates, channel counts, bandwidth values, and the `t=` start and
stop times.

---

## API reference

### Module functions

#### `sdp.parse(text [, mode [, opts]])`

Parses `text` and validates it at the given tier.

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `text` | string | required | The SDP text. CRLF and LF line endings are both accepted; LF produces a warning per line. |
| `mode` | string | `"sdp"` | `"sdp"`, `"st2110"`, or `"ipmx"`. Any other value returns `nil, err` with `err.message` of the form `unknown mode: <value>`. |
| `opts` | table | `nil` | The options below. |

Returns `doc` (a single value) on success. Returns `nil, err` on
failure, where `err` is a finding table (see
[Error and finding tables](#error-and-finding-tables)).

`sdp.parse` returns `nil, err` whenever at least one error-severity
finding was recorded. `err` is the first error-severity finding in the
order the grammar recorded it. When the grammar cannot match the input
and no error-severity finding was recorded (for example, the lines are
out of order, a line letter is unknown, or an `m=` line is malformed),
`err` has `code = "PARSE_ERROR"`, the line and column where matching
stopped, and the text of that line in `line_text`.

`opts` fields:

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `policy` | table | `nil` | Per-check severity overrides. See below. |
| `fail_on_first` | boolean | `false` | When `true`, the grammar stops at the first error-severity finding. When `false`, the grammar continues to the end of the input and records every finding. The option does not change the return value: `sdp.parse` returns `nil, err` in both cases when an error-severity finding exists, and the findings recorded after the first error are not returned. |

To see every finding from one parse, demote the error-severity checks to
`"warn"` with `opts.policy` and read `doc:warnings()`. The command-line
option `--all-findings` does exactly this.

`opts.policy` is a map of the form `{[check_id] = "error" | "warn" | "off"}`.
Every key is validated against the registry when `sdp.parse` is called;
an unknown id returns `nil, err` with `err.policy_key` set to the
unknown key. The registry is available through `sdp.checks()` and
`sdp.default_policy()`, described below. A policy entry applies to every
registered check id, including the registered hard-syntactic checks:
`st2110-20.a.fmtp.no-whitespace-around-equals`,
`sdp.a.ts-refclk.ptp-malformed`, and the `.malformed` check of each
known attribute. Demoting `sdp.a.ts-refclk.ptp-malformed` to `"warn"`
returns a document in which the malformed `ptp=` text is kept in the
attribute's `value` field. Demoting a `.malformed` check returns a
document in which the attribute has `malformed = true` and its text in
`value`. A policy cannot change the structural grammar rules that have no
check id; those rules fail the parse with `code = "PARSE_ERROR"`.

The returned `doc` is a plain Lua table with the
[doc methods](#doc-methods) attached through a metatable.

```lua
local doc, err = sdp.parse(text)
local doc, err = sdp.parse(text, "st2110")
local doc, err = sdp.parse(text, "ipmx")

-- Turn off the byte-order-mark warning, and demote one ST 2110 raw-video
-- value-form check from error to warn so the parse still returns a doc.
local doc, err = sdp.parse(text, "st2110", {
  policy = {
    ["sdp.file.bom-present"]                 = "off",
    ["st2110-20.a.fmtp.depth-invalid-value"] = "warn",
  },
})
```

#### `sdp.new(table)`

Wraps an existing Lua table as a doc object by attaching the metatable.
`sdp.new` does not validate the table. It is the entry point for
building SDP documents in code. A hand-built table must use the
decomposed shape documented in
[Parsed Table Structure](#parsed-table-structure): the session timing is
in `session.time_descriptions` (not `session.timing`), and every known
attribute name uses its decomposed fields (for example, an `rtpmap`
entry has `payload_type`, `encoding`, and `clock_rate` rather than one
`value` string).

Returns `doc`. `sdp.new` never fails.

```lua
local doc = sdp.new({
  version = "0",
  origin  = { username="-", sess_id="1", sess_version="1",
              net_type="IN", addr_type="IP4", unicast_address="192.0.2.1" },
  session = {
    name = "My Session",
    time_descriptions = { { start=0, stop=0, repeats={} } },
    -- emails, phones, bandwidths, and attributes may be {} or omitted.
    -- Absence and an empty array are equivalent for serialization.
  },
  media   = {},
})
```

The array-typed session fields (`emails`, `phones`, `bandwidths`,
`attributes`) and the corresponding per-media fields are all optional in
RFC 8866. The library accepts `nil` and `{}` interchangeably:
`sdp.parse(text)` returns empty tables when the corresponding lines are
absent, and `doc:to_sdp()` renders nothing for either `nil` or `{}`. A
hand-built doc that omits these fields round-trips without change.

#### `sdp.checks()` and `sdp.default_policy()`

These two functions expose the registry of checks.

- `sdp.checks()` returns an array of every registered check, sorted by
  id. Each entry has the fields `id`, `kind`, `default_severity`,
  `code`, `spec_ref`, `message_template`, and `verified`. An entry whose
  `verified` field is `false` also has a `verification_note` string. As
  of version 1.9.1, every registered check has `verified = true`.
- `sdp.default_policy()` returns a table of the form
  `{[id] = default_severity}` over every registered check. A caller can
  edit the table and pass it back as `opts.policy`.

```lua
for _, c in ipairs(sdp.checks()) do
  print(c.id, c.kind, c.default_severity, c.spec_ref)
end

local policy = sdp.default_policy()
policy["sdp.file.bom-present"] = "off"
local doc, err = sdp.parse(text, "sdp", { policy = policy })
```

#### `sdp.attr_get(block, name)` and `sdp.attrs_get(block, name)`

These functions look up decomposed attributes by name on a block. A
block is any table that has an `attributes` array: `doc.session` or any
`doc.media[i]` entry. The functions are the outer-list companions of
[`sdp.params_get`](#sdpparams_getparams-key), so a consumer never scans
the ordered `attributes` array by hand.

- `sdp.attr_get(block, name)` returns the first attribute table whose
  `name` field equals `name`, or `nil` when there is none.
- `sdp.attrs_get(block, name)` returns an array of every matching
  attribute table in document order, or an empty table when there is
  none. One block often has several `rtpmap`, `fmtp`, `ssrc`, or
  `rtcp-fb` lines, so `attrs_get` is the right call whenever more than
  one may appear.

Both functions accept `nil`: a `nil` block, or a block with no
`attributes` field, returns `nil` from `attr_get` and `{}` from
`attrs_get`. Neither function returns an attribute that a demoted
`.malformed` check kept in the document (`malformed = true`), because
that attribute has no decomposed fields. The returned tables have the decomposed shapes described in
[Parsed Table Structure](#parsed-table-structure). For example, an
`rtpmap` result has `payload_type`, `encoding`, and `clock_rate`, and an
`rtcp-fb` result has `payload_type`, `feedback_type`, and an optional
`parameters` string.

```lua
local doc = sdp.parse(text, "st2110")
local m   = doc.media[1]

local rtpmap = sdp.attr_get(m, "rtpmap")        -- first match, or nil
if rtpmap then print(rtpmap.encoding, rtpmap.clock_rate) end

for _, fb in ipairs(sdp.attrs_get(m, "rtcp-fb")) do  -- every match
  print(fb.payload_type, fb.feedback_type, fb.parameters)
end

local grp = sdp.attr_get(doc.session, "group")  -- session-level lookup
```

#### `sdp.params_get(params, key)`

Looks up a value in an ordered parameter list by key. `a=fmtp` and
`a=privacy` keep their key and value pairs in an ordered `params` list
(input order is preserved so that serialization reproduces the
parameter order). `params_get` returns the value for `key`, or `nil` when the key
is absent. A bare flag (a key with no `=value`) has the value `true`.

The argument shape differs from `attr_get`: `attr_get` takes a block,
and `params_get` takes the inner list directly, which is `fmtp.params`
rather than the `fmtp` attribute table. A parameter list has no wrapping
object, so there is no block-like table to pass. A `nil` list returns
`nil`. An `fmtp` attribute that was not decomposed (see the `raw` field
in [Parsed Table Structure](#parsed-table-structure)) has no `params`
field, so `params_get(fmtp.params, key)` returns `nil` for it.

```lua
local doc  = sdp.parse(text, "st2110")
local fmtp = sdp.attr_get(doc.media[1], "fmtp")   -- the fmtp attribute table
if fmtp then
  local width = sdp.params_get(fmtp.params, "width")      -- "1920", or nil
  local il    = sdp.params_get(fmtp.params, "interlace")  -- true when the flag is present
end
```

---

#### `sdp.decode_h264_profile_level_id(hex)`

Decodes an H.264 `profile-level-id` value (RFC 8866 `a=fmtp`, RFC 6184
section 8.1) into its three bytes and what they mean. The result has
`profile_idc`, `profile_iop`, and `level_idc` (numbers), the six
`constraint_set0_flag` to `constraint_set5_flag` booleans taken from
`profile_iop` most significant bit first, `level` (a string such as
`"3.1"`, `"4"`, or `"1b"`), and `profile` (the ITU-T H.264 Annex A
profile name, for example `"Constrained Baseline"`; nil when the
`profile_idc` is not one the table knows). Level 1b follows RFC 6184:
`level_idc` 9, or `level_idc` 11 with `constraint_set3_flag` set.

This is a convenience for reading a parsed value. It is not a check: a
value that is not six hexadecimal digits returns `nil` and a message,
and the validator's own check is `sdp.a.fmtp.h264.profile-level-id-invalid-value`.

```lua
local m = doc.media[1]
local fmtp = sdp.attr_get(m, "fmtp")
local d = sdp.decode_h264_profile_level_id(sdp.params_get(fmtp.params, "profile-level-id"))
print(d.profile, d.level)   --> Constrained Baseline  3
```

#### `sdp.decode_h265_profile(params)`

Decodes the profile, tier and level parameters of an H.265 `a=fmtp`
params list (RFC 7798 section 7.1). The result has `profile_space`,
`profile_id`, `tier_flag`, and `level_id` (numbers; when a parameter is
absent the RFC's inferred value is used: 0, 1, 0, and 93), `tier`
(`"Main"` or `"High"`), `level` (`level_id` divided by 30, as a string
such as `"3.1"` or `"4"`), `profile` (the ITU-T H.265 profile group that
`profile_id` selects, for example `"Main 10"`; nil for a `profile_id` the
table does not know), the four `interop-constraints` flags as booleans
(`progressive_source_flag`, `interlaced_source_flag`,
`non_packed_constraint_flag`, `frame_only_constraint_flag`; inferred 1,
0, 1, 1 when absent), and `profile_compatibility_flags`, a table indexed
0 to 31 read from `profile-compatibility-indicator` most significant bit
first (flag 1 and 2 set is `60000000`). The sub-profiles that the
constraint bits distinguish within a group are not named.

This is a convenience for reading a parsed value, not a check. A
malformed value returns `nil` and a message; the validator's own checks
are the `sdp.a.fmtp.h265.*-invalid-value` ids.

```lua
local fmtp = sdp.attr_get(doc.media[1], "fmtp")
local d = sdp.decode_h265_profile(fmtp.params)
print(d.profile, d.tier, d.level)   --> Main  Main  4
```

### Doc methods

#### `doc:validate([mode])`

Validates the doc at the given tier (`"sdp"`, `"st2110"`, or `"ipmx"`).
The default is `"sdp"`. The method serializes the doc with `to_sdp()`
and parses the text again with `sdp.parse(text, mode)`, so it works on
hand-built docs from `sdp.new()` as well as on parsed docs. When
`to_sdp()` fails, `validate` returns that serializer error.

Returns `true` on success. Returns `nil, err` on failure.

```lua
local ok, err = doc:validate()
local ok, err = doc:validate("st2110")
```

#### `doc:is_sdp()`, `doc:is_st2110()`, and `doc:is_ipmx()`

Each method runs `doc:validate(mode)` and returns `true` or `false`.
Call `doc:validate(mode)` directly when the error detail is needed.

```lua
if doc:is_st2110() then ... end
```

#### `doc:findings()`, `doc:warnings()`, and `doc:errors()`

These methods return the findings that were recorded while the doc was
parsed.

- `doc:findings()` returns every finding, in the order recorded.
- `doc:warnings()` returns only the findings with severity `"warn"`.
- `doc:errors()` returns only the findings with severity `"error"`.

Each finding is a table with the fields `id`, `severity`, `message`,
`spec_ref`, `code`, `line`, `col`, `line_text`, `field_path`, and
`context` (see [Error and finding tables](#error-and-finding-tables)).
A doc that `sdp.parse` returned has no error-severity findings, because
`sdp.parse` returns `nil, err` when one exists; `doc:errors()` therefore
returns an empty table for such a doc. A check that a policy demoted to
`"warn"` appears in `doc:warnings()` with `severity = "warn"`.

For a doc from `sdp.new()`, no parse happened and all three lists are
empty.

```lua
local doc, err = sdp.parse(text)
if doc then
  for _, w in ipairs(doc:warnings()) do
    print(w.id, w.line, w.message)
  end
end
```

#### `doc:to_sdp()`

Renders the doc as SDP text.

- Line endings are CRLF, per the RFC 8866 section 9 ABNF.
- Field order follows RFC 8866 section 5.
- A doc that `sdp.parse` returned serializes to text that parses again
  to an equivalent doc. The test suite checks this on every fixture.

Returns a string on success. Returns `nil, err` when a structurally
required field is missing; `err.message` names the field, for example
`cannot serialize: missing required field session`, and `err.field_path`
is the path of the field, for example `session` or
`media[0].attributes[2].payload_type` (the media index counts from 0 and
the attribute index from 1). The serializer never validates
value forms; `doc:validate()` does that. Optional fields that are `nil`
are omitted from the output.

```lua
local text, err = doc:to_sdp()
```

#### `doc:to_json()`

Returns the doc as a JSON string, encoded with dkjson. The JSON has the
same shape as the Lua table.

```lua
local json = doc:to_json()
```

---

## Command-line reference

```text
parse_sdp <subcommand> [options] [file]
```

The tool has five subcommands. `file` is the path to an SDP file (or to
a JSON file, for `to_sdp`). When `file` is `-` or is omitted, the tool
reads standard input. Run `parse_sdp <subcommand> --help` for the
options of each subcommand.

The tool does not accept a URL. To check an SDP file that a device
serves over HTTP, for example an NMOS IS-05 (Networked Media Open
Specifications, Connection Management) `transportfile` endpoint, fetch
the file with `curl` and send it to standard input:

```sh
curl -s http://192.0.2.10/x-nmos/connection/v1.1/single/senders/<id>/transportfile | parse_sdp validate -
```

`curl -s` writes the bytes as the server sends them, so the CRLF line
endings reach the parser unchanged. A URL argument would require an
HTTP library, and the only runtime dependencies are LPEG and dkjson.

| Subcommand | Purpose |
| --- | --- |
| [`validate`](#parse_sdp-validate) | Reports whether the file is valid at one tier: `OK` or a formatted error. |
| [`diagnose`](#parse_sdp-diagnose) | Reports which of the three tiers the file passes, one row per tier. |
| [`to_json`](#parse_sdp-to_json) | Parses and validates the file, then writes the document as JSON. |
| [`to_sdp`](#parse_sdp-to_sdp) | Renders a JSON document as SDP text. |
| [`checks`](#parse_sdp-checks) | Lists the registered checks with id, severity, and `spec_ref`. |

### Exit codes

| Case | Exit code |
| --- | --- |
| `validate` or `to_json` succeeds | 0 |
| `validate` or `to_json` fails to parse or validate the file (the detail is on standard error) | 1 |
| `validate` or `to_json` with `--all-findings` finishes and at least one finding has the default severity `error` | 1 |
| `validate` or `to_json` with `--all-findings` finishes and every finding has the default severity `warn`, or there are no findings | 0 |
| `validate`, `diagnose`, or `to_json` with `--all-findings` cannot parse the file structurally (`PARSE_ERROR`, a grammar rule with no check id); the formatted error is printed | 1 |
| `diagnose` finishes, whatever the verdict | 0 |
| `to_sdp` cannot decode the input as JSON | 1 |
| `to_sdp` input decodes but a required field is missing. The tool prints the serializer's error, which names the field in `field_path`. | 1 |
| `--mode` has a value other than `sdp`, `st2110`, or `ipmx` (`unknown mode: <value>`) | 1 |
| `checks --format` has a value other than `table` or `json` | 1 |

### `parse_sdp validate`

Validates the file at one tier and reports a single verdict.

```text
parse_sdp validate [--mode sdp|st2110|ipmx] [--all-findings] [file]
```

| Option | Description |
| --- | --- |
| `--mode MODE` | The validation tier. The default is `sdp`. |
| `--all-findings` | Collects every finding instead of stopping at the first error. See [All findings](#all-findings). |

```sh
$ parse_sdp validate --mode st2110 session.sdp
OK
$ echo $?
0

$ parse_sdp validate --mode st2110 examples/st2110/invalid/04_bad_tsrefclk_gmid.sdp
error: [INVALID_VALUE] ts-refclk:ptp= value must be '<version>:<EUI-64>[:<domain>]' or '<version>:traceable' (EUI-64 = 8 hex octets, RFC 7273 §4.8)
 --> line 10, col 17
  |
10 | a=ts-refclk:ptp=IEEE1588-2008:AA-BB-CC-DD-EE:0
   |                 ^
  = note: required by RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF)
$ echo $?
1
```

### `parse_sdp diagnose`

Runs the RFC 8866, ST 2110, and IPMX tiers in that order and prints one
row per tier. The exit code is always 0; the verdict is in the output.
This subcommand answers the question of which standard an unknown SDP
file conforms to and where it stops conforming.

```text
parse_sdp diagnose [--all-findings] [file]
```

| Option | Description |
| --- | --- |
| `--all-findings` | Lists every finding at each tier instead of only the first. A finding that a lower tier already reported is not repeated. The exit code is still 0. See [All findings](#all-findings). |

```sh
$ parse_sdp diagnose examples/st2110/invalid/01_missing_tsrefclk.sdp
  ✓ RFC 8866 (base SDP)
  ✗ SMPTE ST 2110
      st2110.attr.ts-refclk-required
      media block must include an 'a=ts-refclk' attribute (every ST 2110 stream description requires one)
      ST 2110-10:2022 §8.2
      at media[0]
  ✗ IPMX (VSF TR-10)
      tr-10-1.a.fmtp.measuredpixclk-required
      a=fmtp on a video IPMX media block must include 'measuredpixclk'
      TR-10-1 §10.2
      at media[0].attributes[fmtp:pt=96]
```

Under a failed row, the tool prints the finding's id, message,
`spec_ref`, and either `at <field_path>` or `at line N, col M`. When a
higher tier reports the same finding as a lower tier, the higher row
shows `(inherits SMPTE ST 2110 failure; fix it first)` (or the RFC 8866
equivalent) instead of the detail.

### `parse_sdp to_json`

Parses the file, validates it at the chosen tier, and writes the
document as JSON to standard output. The JSON has the same shape as the
parsed `doc` table: every known attribute is decomposed into typed
fields (see [Parsed Table Structure](#parsed-table-structure)).

```text
parse_sdp to_json [--mode sdp|st2110|ipmx] [--pretty] [--all-findings] [file]
```

| Option | Description |
| --- | --- |
| `--mode MODE` | The validation tier. The default is `sdp`. |
| `--pretty` | Indents the JSON output. |
| `--all-findings` | Writes the JSON to standard output and the list of every finding to standard error. See [All findings](#all-findings). |

```json
{
  "version": "0",
  "origin": { "username": "-", "sess_id": "3720000001", "sess_version": "1",
              "net_type": "IN", "addr_type": "IP4", "unicast_address": "127.0.0.1" },
  "session": { "name": "Simple Video", "time_descriptions": [ { "start": 0, "stop": 0, "repeats": [] } ],
               "emails": [], "phones": [], "bandwidths": [], "attributes": [] },
  "media": [ { "media": "video", "port": 5000, "proto": "RTP/AVP", "fmts": [ "96" ],
               "connection": { "net_type": "IN", "addr_type": "IP4", "address": "224.0.0.2/64" },
               "bandwidths": [],
               "attributes": [ { "name": "rtpmap", "payload_type": 96,
                                 "encoding": "H264", "clock_rate": 90000 } ] } ]
}
```

The example above is the output for
`examples/generic/valid/02_simple_video.sdp`, reformatted. dkjson does
not order the keys of an object, so the key order in the real output
differs from run to run.

### `parse_sdp to_sdp`

Renders a JSON document as SDP text on standard output. The output uses
CRLF line endings and RFC 8866 field order. The JSON must have the
parsed-document shape; `to_json` followed by `to_sdp` reproduces the
input SDP file, and the test suite checks this on every fixture.

```text
parse_sdp to_sdp [file.json]
```

```sh
parse_sdp to_sdp doc.json > session.sdp
cat doc.json | parse_sdp to_sdp
```

### `parse_sdp checks`

Lists the validator's registry: every check the parser can report, the
clause it cites, and its default severity. Compliance testers can use
the list as the inventory of clauses the validator covers. Tools can
read the `--format json` output, which includes every field of every
check.

```text
parse_sdp checks [--filter SUBSTR] [--format table|json] [--unverified]
```

| Option | Description |
| --- | --- |
| `--filter SUBSTR` | Keeps only the checks whose id contains the text. The match is a plain substring match, not a Lua pattern, so a `-` in an id (`ts-refclk`, `tr-10-1`) matches literally. |
| `--format MODE` | `table` (the default; column-aligned id, severity, and `spec_ref`) or `json` (an array of the full registry entries). |
| `--unverified` | Keeps only the checks with `verified = false`. As of version 1.9.1, no check has `verified = false`, so the list is empty. |

```sh
$ parse_sdp checks --filter ts-refclk
sdp.a.ts-refclk.ptp-malformed   error  RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF)
sdp.a.ts-refclk.traceable-mix   error  RFC 7273 §4.8
st2110.attr.ts-refclk-required  error  ST 2110-10:2022 §8.2

$ parse_sdp checks --format json --filter tr-10-1.a.fmtp | jq '.[] | .id'
"tr-10-1.a.fmtp.htotal-invalid-value"
"tr-10-1.a.fmtp.htotal-required"
"tr-10-1.a.fmtp.marker-required"
...
```

This subcommand prints the same data that
[`sdp.checks()`](#sdpchecks-and-sdpdefault_policy) returns in Lua.

### All findings

By default, `validate`, `diagnose`, and `to_json` report only the first
error-severity finding, which is the `err` that `sdp.parse` returns. The
parser records the other findings, but the tool does not print them. The
default gives a pass-or-fail answer.
When a file has several problems and the user wants all of them from
one run, the `--all-findings` option collects every finding (errors and
warnings) and lists them in the order they were recorded.

The tool implements the option by demoting every error-severity check to
`"warn"` through `opts.policy`, so the parse runs to the end of the
input. The tool keeps the original severity for the exit-code rule and
prints it in parentheses after each finding's id. The behavior per
subcommand:

| Subcommand | Output | Exit code |
| --- | --- | --- |
| `validate` | A numbered list on standard error; `OK` on standard output only when there are no findings | 1 when any finding's default severity is `error`; 0 otherwise |
| `to_json` | The JSON on standard output; the numbered list on standard error | 1 when any finding's default severity is `error`; 0 otherwise |
| `diagnose` | Each tier shows only the findings that the tier introduced; a tier with no new findings shows the inherits note | Always 0 |

A structural failure (`PARSE_ERROR`, a grammar rule with no check id)
cannot be demoted. In that case the tool prints the formatted error and exits 1 even with
`--all-findings`.

```sh
$ parse_sdp validate --all-findings --mode st2110 examples/st2110/invalid/03_missing_fmtp.sdp
9 findings:
[1] st2110-20.a.fmtp.sampling-required  (error)
    fmtp for raw video must include required 'sampling' parameter
    ST 2110-20:2022 §7.2
    at media[0].attributes[fmtp:pt=96]
[2] st2110-20.a.fmtp.width-required  (error)
    fmtp for raw video must include required 'width' parameter
    ST 2110-20:2022 §7.2
    at media[0].attributes[fmtp:pt=96]
...
$ echo $?
1
```

The header is `N findings:` (or `1 finding:` for one). The `(error)` or
`(warn)` label after each id is the check's default severity, which is
the severity that would have made the file fail without `--all-findings`.
A check whose default severity is `warn` is labeled `(warn)`.

### Examples

```sh
# Pass or fail at the ST 2110 tier
parse_sdp validate --mode st2110 session.sdp

# One row per tier, for a file whose intended standard is unknown
parse_sdp diagnose customer.sdp

# SDP to JSON, indented, validated at the IPMX tier
parse_sdp to_json --mode ipmx --pretty session.sdp

# Standard input
cat session.sdp | parse_sdp to_json --mode ipmx

# An SDP file that a device serves over HTTP
curl -s http://192.0.2.10/session.sdp | parse_sdp validate --mode st2110 -

# Round trip: SDP to JSON to SDP
parse_sdp to_json session.sdp | parse_sdp to_sdp > out.sdp

# Every finding in one run
parse_sdp validate --all-findings --mode st2110 customer.sdp

# The registered checks, as JSON, filtered and piped to jq
parse_sdp checks --format json --filter ts-refclk | jq '.[] | {id, spec_ref}'
```

---

## Parsed Table Structure

The doc is a fully decomposed table. A consumer never needs to parse a
string from it. Every known attribute name (`rtpmap`, `fmtp`,
`ts-refclk`, `mediaclk`, `group`, `source-filter`, `ssrc`, `extmap`, and
the others listed below) is decomposed into typed fields. Only unknown
attribute names use the generic `{name, value}` shape.

```lua
{
  version = "0",                   -- v=  (string)

  origin = {                       -- o=
    username        = "-",
    sess_id         = "1234567890",   -- string, to keep NTP-range precision
    sess_version    = "1",            -- string
    net_type        = "IN",
    addr_type       = "IP4",
    unicast_address = "192.0.2.1",
  },

  session = {
    name        = "My Session",    -- s=  (required)
    info        = nil,             -- i=  (optional)
    uri         = nil,             -- u=  (optional)
    emails      = {},              -- e=  (array of strings, zero or more)
    phones      = {},              -- p=  (array of strings, zero or more)
    connection  = nil,             -- c=  (optional)
    bandwidths  = {},              -- b=  (array, zero or more)
    time_descriptions = {          -- one entry per t= line, with its r= lines
      { start = 0, stop = 0, repeats = {} },
    },
    time_zones  = nil,             -- z=  (optional; array of pairs)
    attributes  = {},              -- a=  (array, in input order)
  },

  media = {                        -- one entry per m= line
    {
      media      = "video",        -- m=  media type (string)
      port       = 5004,           -- m=  port (number)
      port_count = nil,            -- m=  the /<count> suffix, when present (number)
      proto      = "RTP/AVP",      -- m=  transport protocol (string)
      fmts       = { "96" },       -- m=  format list (array of strings)
      info       = nil,            -- i=  (optional)
      connection = nil,            -- c=  (optional)
      bandwidths = {},             -- b=  (array, zero or more)
      attributes = {               -- a=  (array, in input order)
        -- Decomposed: a=rtpmap:96 raw/90000
        { name = "rtpmap",
          payload_type = 96, encoding = "raw", clock_rate = 90000 },
        -- Decomposed: a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;...
        { name = "fmtp", payload_type = 96,
          params = {
            { "sampling", "YCbCr-4:2:2" },
            { "width",    "1920" },
            -- an ordered list of {key, value} or {flag, true} pairs
          } },
        -- Flag attribute with no value: a=recvonly
        { name = "recvonly" },
        -- Unknown name: generic shape
        { name = "tool", value = "test-sender/1.0" },
      },
    },
  },
}
```

### Field types

The array fields `emails`, `phones`, `bandwidths`, `attributes`,
`time_descriptions`, and `media` are always present as tables, even when
empty. An optional scalar field that is absent from the source SDP is
`nil`.

| Field | Shape |
| --- | --- |
| `connection` | `{ net_type, addr_type, address }`. `address` is the whole connection address as a string, including any `/<ttl>` or `/<numaddr>` suffix. |
| `bandwidths[i]` | `{ type, value }`. `type` is the `b=` modifier string (for example `"AS"`); `value` is a number. |
| `time_descriptions[i]` | `{ start, stop, repeats }`. `start` and `stop` are numbers. |
| `time_descriptions[i].repeats[j]` | `{ interval, duration, offsets }`. The three are typed-time strings as written in the `r=` line (for example `"7d"`, `"1h"`, `"0"`); the library does not convert them to seconds. `offsets` is an array of such strings. |
| `time_zones[i]` | `{ adjustment_time, offset }`. Both are strings as written in the `z=` line (for example `"2882844526"` and `"-1h"`). |

### Decomposed attributes

The table below lists the field names of every decomposed attribute.
The `name` field is always present. A hand-built doc passed to
`sdp.new` must use these field names; the serializer reads only these
fields for known attribute names.

| Attribute | Fields |
| --- | --- |
| `rtpmap` | `payload_type` (number), `encoding` (string), `clock_rate` (number), `channels` (number, optional) |
| `fmtp` | `payload_type` (number) and either `params` or `raw`. `params` is an ordered list of `{key, value}` pairs (string value) and `{flag, true}` entries. When the value after the payload type is not a list of `key=value` and flag tokens, for example `a=fmtp:0 0-15`, the attribute has `raw` (the value as one string) and no `params` field. |
| `mid` | `tag` (string) |
| `setup` | `role` (string: `active`, `passive`, `actpass`, or `holdconn`) |
| `group` | `semantics` (string), `tags` (array of strings, possibly empty) |
| `ssrc-group` | `semantics` (string), `ssrc_ids` (array of numbers) |
| `ssrc` | `ssrc_id` (number), `attribute` (string), `value` (string, optional) |
| `msid` | `msid_id` (string), `appdata` (string, optional) |
| `extmap` | `id` (number), `uri` (string), `direction` (string, optional), `attributes` (string, optional) |
| `rtcp` | `port` (number); `net_type`, `addr_type`, and `address` (strings, present together when the line has them) |
| `rtcp-fb` | `payload_type` (a number, or the string `"*"`), `feedback_type` (string), `parameters` (string, optional) |
| `rtcp-mux` | no other fields |
| `ptime`, `maxptime`, `framerate`, `quality` | `value` (number) |
| `source-filter` | `filter_mode` (`"incl"` or `"excl"`), `net_type`, `addr_type` (`"IP4"`, `"IP6"`, or `"*"`), `dest_address` (string), `src_addresses` (array of strings) |
| `ts-refclk` | `source` (string) plus per-source fields. `ptp`: `version` (string), then either `grandmaster` (string) with optional `domain` (string), or `traceable = true`; a `ptp=` value that does not match that form has `value` (the text) and the finding `sdp.a.ts-refclk.ptp-malformed`. `ntp`: `address` (string) or `traceable = true`. `private`: optional `traceable = true`. `gps`, `gal`, `glonass`, `local`: no other fields. Any other source (for example `localmac`): optional `value` (string). |
| `mediaclk` | `mode` (string), optional `id` (string, the `id=` prefix including a `src:` marker when present), plus per-mode fields. `sender`: no other fields. `direct`: optional `offset` (number) and optional `rate = { num, den }` (numbers). `IEEE1722`: `stream_id` (string). Any other mode: optional `value` (string). |
| `infoframe` (IPMX) | `port` (number), `ssn` (string), `dit` (string) |
| `hkep` (IPMX) | `port` (number), `nettype`, `addrtype`, `addr`, `node_id`, `port_id` (strings). These field names have no underscore between `net` and `type`, unlike the `c=` fields. |
| `privacy` (IPMX) | `params` (an ordered list of `{key, value}` pairs, as for `fmtp`) and `trailing_semi` (boolean; `true` when the line ended with a semicolon). The boolean is part of the doc and of the JSON. |

The three IPMX attributes (`infoframe`, `hkep`, `privacy`) are
decomposed only when the document is parsed in `"ipmx"` mode. In
`"sdp"` and `"st2110"` mode they are returned in the generic
`{name, value}` shape.

A known attribute whose value does not match the attribute's syntax is
reported with the attribute's `.malformed` check (see
[Malformed known attributes](#malformed-known-attributes)). When that
check is demoted below error, the attribute is kept in the document as
`{name = <name>, malformed = true, value = <the text after the colon>}`.
`value` is absent when the line has no colon, as in `a=ptime`. The
document checks do not read a malformed attribute.

The flag attributes `recvonly`, `sendonly`, `sendrecv`, and `inactive`
are generic attributes with a `name` and no `value`. `rtcp-mux` is
recognized by name, so `a=rtcp-mux:<anything>` is reported as
`sdp.a.rtcp-mux.malformed`. Any
other attribute name keeps the generic `{name, value}` shape, where
`value` is absent for a flag form such as `a=foo` and is the whole text
after the colon for `a=foo:bar`.

The `attributes` array keeps the input order so that serialization
reproduces the input bytes. Look attributes up by name with
[`sdp.attr_get` and `sdp.attrs_get`](#sdpattr_getblock-name-and-sdpattrs_getblock-name)
rather than by scanning the array.

`fmtp.params` and `privacy.params` are ordered lists of `{key, value}`
pairs, in input order. Use
[`sdp.params_get(params, key)`](#sdpparams_getparams-key) to look one
up; a bare flag has the value `true`.

---

## Error and finding tables

Errors are returned as values. The library never calls `error()` for a
parse or validation failure; `error()` is reserved for programming
mistakes such as a wrong argument type.

Every error and every warning that a registered check produces is a
finding table with these fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | string | The stable check id, for example `"st2110-20.a.fmtp.depth-invalid-value"`. The id is the key into `sdp.checks()`. |
| `severity` | string | `"error"` or `"warn"`, after the policy is applied. |
| `message` | string | A description for a person. |
| `code` | string | One of `MISSING_FIELD`, `INVALID_VALUE`, `MALFORMED_LINE`, `WRONG_ORDER`, or `PARSE_ERROR`. `PARSE_ERROR` appears only on the structural failure described below. |
| `spec_ref` | string | The cited clause, for example `"ST 2110-20:2022 §7.4.2"`. |
| `field_path` | string or nil | The document path, for example `"media[0].attributes[fmtp:pt=96]"`. Absent when the finding is positioned by line instead. Media indexes in a `field_path` count from 0. |
| `line` | integer | The 1-based line number, or 0 when the finding has no line. |
| `col` | integer | The 1-based column number, or 0 when the finding has no line. |
| `line_text` | string or nil | The text of the source line, without its terminator, when the finding has a line. |
| `context` | table or string | Structured metadata, for example `{encoding = "L24"}`, or the empty string when there is none. |

The `err` that `sdp.parse` returns has the same fields. Two other error
tables also appear:

- A structural parse failure. When the grammar cannot match the input
  and no error-severity finding was recorded, `err` has
  `code = "PARSE_ERROR"`, `message = "could not parse from this line"`,
  the `line`, `col`, and `line_text` of the line where matching stopped,
  and no `id`. Lines out of order, an unknown line letter, `v=1`, an
  empty `o=` username, and a malformed `m=` or `o=` line produce this
  error. So does a value that holds a NUL byte or a CR that is not part
  of CRLF: RFC 8866 section 9 defines `byte-string` as "any byte except
  NUL, CR, or LF". The exception is an `a=fmtp` value that holds a NUL
  byte, which is `sdp.a.fmtp.malformed`. A known attribute with a malformed value does not
  produce this error. That attribute produces its `.malformed` check
  instead, with the column of the value (see
  [Malformed known attributes](#malformed-known-attributes)). The checks for a media description
  or a document run only when that part parsed to its end, so a line
  after the failure never causes a different error to be reported.
- A policy failure. When `opts.policy` names an unknown check id, `err`
  has `err.policy_key` set to that id.

`errors.format(err)` in the module `parse_sdp.errors` renders any of
these tables as the multi-line text that the command-line tool prints.

### Rendering an error

```lua
local sdp     = require("parse_sdp")
local errors  = require("parse_sdp.errors")
local doc, err = sdp.parse(text, "st2110")
if not doc then
  io.stderr:write(errors.format(err) .. "\n")
  os.exit(1)
end
```

Output for a document-level finding:

```text
error: [MISSING_FIELD] media block must include an 'a=ts-refclk' attribute (every ST 2110 stream description requires one)
 --> field: media[0]
  = note: required by ST 2110-10:2022 §8.2
```

Output for a line-positioned finding includes the source line and a
caret under the column:

```text
error: [PARSE_ERROR] could not parse from this line
 --> line 2, col 1
  |
 2 | t=0 0
   | ^
```

---

## What this library validates (and what it doesn't)

Every check is grounded in specification text. The rule is:

> A check belongs in this library only if the relevant standard
> explicitly requires something (*shall*, *MUST*), explicitly forbids
> something (*shall not*, *MUST NOT*, *is forbidden*), or defines the
> form an optional value must take when the value is present. Anything
> the standard leaves silent passes.

The library tests conformance. It does not test whether a configuration
is a sensible product configuration. Many SDP files from real ST 2110
and IPMX senders contain unusual but legal choices, and the library
accepts them.

### Check kinds and what a policy can change

Every registered check has one of three `kind` values, which
`sdp.checks()` reports:

| Kind | Definition | Default severity |
| --- | --- | --- |
| hard-syntactic | The input shape is wrong. Most of these rules are grammar rules with no check id (a line with no `=`, an unknown line letter, lines out of order, a malformed `m=` or `o=` line); a violation of one of these rules ends the parse with `PARSE_ERROR`. The registered ones record a finding, and the parse continues to the next line. The registered ones are `st2110-20.a.fmtp.no-whitespace-around-equals`, `sdp.a.ts-refclk.ptp-malformed`, and the `.malformed` check of each known attribute (see [Malformed known attributes](#malformed-known-attributes)). | `error` (`warn` for `sdp.a.msid.malformed`) |
| soft-syntactic | The specification requires a strict form, but a lax form has only one possible meaning. The parser accepts the lax form and records a finding. There are six: the four line and file checks (`sdp.line.*`, `sdp.file.*`), `sdp.a.fmtp.trailing-semicolon`, and `st2110-20.a.fmtp.semicolon-without-whitespace`. | `warn` |
| semantic | A captured value violates a value set, a presence requirement, or a cross-section rule. | `error` |

A policy (`opts.policy`, or the Policy panel in the browser playground)
sets the severity of any registered id to `"error"`, `"warn"`, or
`"off"`. A policy can promote a soft-syntactic warning to an error, so
that a file with bare LF line endings fails the verdict. A policy can demote a
semantic error to a warning, so that `sdp.parse` returns the document
with the finding in `doc:warnings()`. A policy cannot change the grammar
rules that have no id; those rules fail the parse with
`code = "PARSE_ERROR"` whatever the policy says.

### RFC 8866 checks

The checks below run at every tier. The tables have three columns: the
check id, what the check rejects, and the `spec_ref` string as the
registry stores it.

#### Document and line checks

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.v.must-be-zero` | A `v=` value other than `0`. In version 1.9.1 the grammar rejects this structurally with `PARSE_ERROR`; the id is registered but is not emitted. | RFC 8866 §5.1 |
| `sdp.o.username-required` | An `o=` line with an empty username. In version 1.9.1 the grammar rejects this structurally with `PARSE_ERROR`; the id is registered but is not emitted. | RFC 8866 §5.2 |
| `sdp.session.connection-required` | A media description with no `c=` line when the session level has no `c=` line either. A session with no media descriptions and no `c=` line is accepted. | RFC 8866 §5.7 |
| `sdp.m.rtpmap-required-for-dynamic-pt` | An RTP media description whose `m=` line lists a payload type from 96 to 127 with no `a=rtpmap` for that payload type. | RFC 8866 §8.2.3 |
| `sdp.m.odd-port-requires-rtcp` | An RTP media description whose `m=` port is odd and that has neither `a=rtcp` nor `a=rtcp-mux`. An odd RTP port does not follow the even-RTP, odd-RTCP parity rule, so the RTCP port must be stated. | RFC 8866 §5.14 |
| `sdp.a.fmtp.format-not-in-media` | An `a=fmtp` whose format is not one of the formats on the `m=` line. | RFC 8866 §6.15 |
| `sdp.file.bom-present` | A file that starts with a UTF-8 byte order mark (warning). | RFC 8866 §6 |
| `sdp.file.trailing-newline-missing` | A last line with no line terminator (warning). | RFC 8866 §5 |
| `sdp.line.lf-only-line-ending` | A line that ends with LF alone instead of CRLF (warning). The finding names the line that ended with the LF. | RFC 8866 §9 |
| `sdp.line.trailing-whitespace` | A line with spaces or tabs before the line terminator (warning). | RFC 8866 §9 |
| `sdp.a.fmtp.trailing-semicolon` | An `a=fmtp` value that ends with a semicolon after the last parameter (warning). | RFC 8866 §6.15 |

#### Connection address (`c=`) checks

A connection address is required at the session level or in every media
description (RFC 8866 section 5.7: *"A session description MUST contain
either at least one 'c=' line in each media description or a single
'c=' line at the session level."*). When a `c=` line is present at
either level, its address is checked against the RFC 8866 section 9
grammar for the declared address type. An IPv4 address from 224.0.0.0
to 239.255.255.255 is multicast; an IPv6 address that starts with `ff`
is multicast. The layered multicast form `<address>/<ttl>/<numaddr>` is
accepted, as in the RFC 8866 example `c=IN IP4 233.252.0.1/127/3`.

The two address-form checks reject a host name. RFC 8866 section 5.7
defines the `IP4` and `IP6` connection address as an IP address: *"If
the session is multicast, the connection address will be an IP multicast
group address. If the session is not multicast, then the connection
address contains the unicast IP address"*. The section 9 grammar is
looser and also allows an `FQDN`. The checks follow section 5.7, and the
finding message states the difference. A host name is still accepted in
`o=`, where section 5.2 allows it explicitly.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.c.address.invalid-ipv4` | An `IP4` address that is not four decimal octets from 0 to 255 separated by dots (for example `1.2.3` or `999.0.0.0`). A host name is rejected. | RFC 8866 §5.7 / §9 (IP4-address ABNF) |
| `sdp.c.address.invalid-ipv6` | An `IP6` address that is not a valid IPv6 address. A host name is rejected. | RFC 8866 §5.7 / §9 (IP6-address ABNF) |
| `sdp.c.ipv4-multicast.ttl-required` | An IPv4 multicast address with no `/<ttl>` suffix, or with a suffix that is not decimal digits. | RFC 8866 §9 (IP4-multicast ABNF) |
| `sdp.c.ipv4-multicast.ttl-out-of-range` | An IPv4 multicast TTL greater than 255. A TTL of 0 is accepted. | RFC 8866 §5.7 |
| `sdp.c.ipv4-multicast.numaddr-invalid` | An IPv4 multicast `<numaddr>` (the second suffix) that is not a positive integer. | RFC 8866 §9 (IP4-multicast ABNF) |
| `sdp.c.ipv4-unicast.suffix-not-allowed` | An IPv4 unicast address with a `/` suffix. | RFC 8866 §5.7 |
| `sdp.c.ipv6-multicast.suffix-form-invalid` | An IPv6 multicast address whose suffix is not a single `/<numaddr>`. IPv6 multicast has no TTL field. | RFC 8866 §9 (IP6-multicast ABNF) |
| `sdp.c.ipv6-multicast.numaddr-invalid` | An IPv6 multicast `<numaddr>` that is not a positive integer. | RFC 8866 §9 (IP6-multicast ABNF) |
| `sdp.c.ipv6-unicast.suffix-not-allowed` | An IPv6 unicast address with a `/` suffix. | RFC 8866 §5.7 |

#### Attribute checks from the RFCs that RFC 8866 builds on

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.mid.duplicate-tag` | Two media descriptions with the same `a=mid` tag. | RFC 5888 §4 |
| `sdp.a.group.requires-mid-on-all-media` | A session that has an `a=group` line and a media description with no `a=mid` line. | RFC 5888 §6 |
| `sdp.a.group.references-port-zero-mid` | An `a=group` line that names a tag whose media description has port 0. | RFC 5888 §9.2 |
| `sdp.a.source-filter.dest-not-in-connections` | An `a=source-filter` whose destination address does not equal any `c=` address in the SDP file, after expansion of layered multicast ranges. A filter with address type `*` is not checked. The source addresses are not checked. | RFC 4570 §3.1 |
| `sdp.a.ts-refclk.ptp-malformed` | An `a=ts-refclk:ptp=` value that is not `<version>:<EUI-64>[:<domain>]` or `<version>:traceable`, where the EUI-64 is eight hexadecimal octets separated by dashes. The version token and the domain are not checked. | RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF) |
| `sdp.a.ts-refclk.traceable-mix` | A traceable `a=ts-refclk` source (`gps`, `gal`, `glonass`, or a `traceable` form of `ntp`, `ptp`, or `private`) and a non-traceable source at the same level: the session level, or one media description. Mixing across levels is accepted. | RFC 7273 §4.8 |
| `sdp.a.extmap.id-out-of-range` | An `a=extmap` id outside 1 to 256. | RFC 8285 §5 / §6 |
| `sdp.a.extmap.duplicate-id` | The same `a=extmap` id twice in one media description, or twice at the session level. | RFC 8285 §6 |
| `sdp.a.extmap.duplicate-uri` | The same `a=extmap` URI with the same extension attributes twice for one stream (one media description, or the session level). The same URI with different attributes is accepted. | RFC 8285 §6 |
| `sdp.a.extmap.mixed-levels` | `a=extmap` at the session level and in a media description of the same file. | RFC 8285 §6 |

#### Codec payload-format checks

The checks below come from the IETF media-type registrations of RTP
payload formats. They apply to a media description whose `a=rtpmap`
names the encoding (compared without regard to case), and to the
`a=fmtp` lines of the payload types that rtpmap binds. A parameter the
registration does not define passes through. An `a=fmtp` whose value is
not a list of `key=value` tokens is not checked.

H.264 (RFC 6184). The decoded form of `profile-level-id` is available
through [`sdp.decode_h264_profile_level_id`](#sdpdecode_h264_profile_level_idhex).

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.rtpmap.h264.media-type-must-be-video` | An `a=rtpmap` with encoding `H264` on an `m=` line whose media type is not `video`. | RFC 6184 §8.2.1 |
| `sdp.a.rtpmap.h264.clock-rate-must-be-90000` | An `H264` rtpmap clock rate other than 90000. | RFC 6184 §8.2.1 |
| `sdp.a.fmtp.h264.profile-level-id-invalid-value` | A `profile-level-id` that is not six hexadecimal digits. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.max-recv-level-invalid-value` | A `max-recv-level` that is not four hexadecimal digits. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.max-mbps-invalid-value`, `max-smbps`, `max-fs`, `max-cpb`, `max-dpb`, `max-br`, `sar-understood` (one id per parameter) | A value that is not a decimal integer. The comparison with the H.264 level tables is not made. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.redundant-pic-cap-invalid-value`, `use-level-src-parameter-sets`, `in-band-parameter-sets`, `level-asymmetry-allowed` | A value other than `0` or `1`. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.packetization-mode-invalid-value` | A value other than `0`, `1`, or `2`. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-interleaving-depth-invalid-value`, `sprop-max-don-diff` | A value that is not an integer from 0 to 32767. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-deint-buf-req-invalid-value`, `deint-buf-cap`, `sprop-init-buf-time`, `max-rcmd-nalu-size` | A value that is not an integer from 0 to 4294967295. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sar-supported-invalid-value` | A value that is not an integer from 1 to `sar-understood` (13 when `sar-understood` is absent) or 255. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-parameter-sets-invalid-value` | A value that is not a comma-separated list of base64 strings. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-level-parameter-sets-invalid-value` | A value that is not colon-separated `PLId:PSL` pairs, where `PLId` is six hexadecimal digits and `PSL` a comma-separated list of base64 strings. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-interleaving-depth-forbidden-in-mode`, `sprop-deint-buf-req-forbidden-in-mode` | The parameter present when `packetization-mode` is absent, `0`, or `1`. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-interleaving-depth-required`, `sprop-deint-buf-req-required` | The parameter absent when `packetization-mode` is `2`. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.sprop-init-buf-time-forbidden-in-mode`, `sprop-max-don-diff-forbidden-in-mode` | The parameter present when `packetization-mode` is `0` or `1`. | RFC 6184 §8.1 |
| `sdp.a.fmtp.h264.use-level-src-parameter-sets-forbidden-with-in-band` | `use-level-src-parameter-sets` present with a value other than `0` when `in-band-parameter-sets` is `1`. | RFC 6184 §8.1 |

H.265 (RFC 7798). The decoded profile, tier and level are available
through [`sdp.decode_h265_profile`](#sdpdecode_h265_profileparams). An
`a=fmtp` line that carries `dec-parallel-cap` is not checked: that
parameter's value holds semicolons inside its braces, which the
`key=value` split of `a=fmtp` cannot carry, so checking its fragments
would report parameters that are not there.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.rtpmap.h265.media-type-must-be-video` | An `a=rtpmap` with encoding `H265` on an `m=` line whose media type is not `video`. | RFC 7798 §7.2.1 |
| `sdp.a.rtpmap.h265.clock-rate-must-be-90000` | An `H265` rtpmap clock rate other than 90000. | RFC 7798 §7.2.1 |
| `sdp.a.fmtp.h265.profile-space-invalid-value` | A value that is not an integer from 0 to 3. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.profile-id-invalid-value` | A value that is not an integer from 0 to 31. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.tier-flag-invalid-value` | A value other than `0` or `1`. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.level-id-invalid-value`, `max-recv-level-id-invalid-value` | A value that is not an integer from 0 to 255. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.interop-constraints-invalid-value` | A value that is not twelve hexadecimal digits. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.profile-compatibility-indicator-invalid-value` | A value that is not eight hexadecimal digits. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-sub-layer-id-invalid-value`, `recv-sub-layer-id-invalid-value` | A value that is not an integer from 0 to 6. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.tx-mode-invalid-value` | A value other than `SRST`, `MRST`, or `MRMT`. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-vps-invalid-value`, `sprop-sps`, `sprop-pps`, `sprop-sei` | A value that is not a comma-separated list of base64 strings. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.max-lsr-invalid-value`, `max-lps`, `max-cpb`, `max-br`, `max-tr`, `max-tc`, `max-fps` | A value that is not a decimal integer. The comparison with the H.265 level tables is not made. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.max-dpb-invalid-value` | A value that is not an integer from 1 to 16. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-max-don-diff-invalid-value`, `sprop-depack-buf-nalus-invalid-value` | A value that is not an integer from 0 to 32767. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-depack-buf-bytes-invalid-value` | A value that is not an integer from 0 to 4294967295. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.depack-buf-cap-invalid-value` | A value that is not an integer from 1 to 4294967295. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-segmentation-id-invalid-value` | A value that is not an integer from 0 to 3. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-spatial-segmentation-idc-invalid-value` | A value that is not hexadecimal digits. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.include-dph-invalid-value` | A value that is neither empty nor a comma-separated list of integers from 0 to 255. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.sprop-depack-buf-nalus-required-when-max-don-diff`, `sprop-depack-buf-bytes-required-when-max-don-diff` | The parameter absent or `0` when `sprop-max-don-diff` is present and greater than 0. | RFC 7798 §7.1 |
| `sdp.a.fmtp.h265.max-recv-level-id-not-higher-than-level-id` | A `max-recv-level-id` that is not greater than `level-id` (93 when `level-id` is absent). | RFC 7798 §7.1 |

MPEG-4 generic (RFC 3640, encoding `mpeg4-generic`). The registration
fixes no clock rate (the RFC says the rate SHOULD equal the audio
sampling rate), so none is checked. The `mode` value set is open ("Other
modes are expected to be defined in future RFCs"), so only its presence
is checked.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.rtpmap.mpeg4-generic.media-type-invalid-value` | An `mpeg4-generic` rtpmap on an `m=` line whose media type is not `video`, `audio`, or `application`. | RFC 3640 §4.1 |
| `sdp.a.fmtp.mpeg4-generic.streamType-required`, `profile-level-id-required`, `config-required`, `mode-required` | An `mpeg4-generic` fmtp without the parameter. | RFC 3640 §4.1 |
| `sdp.a.fmtp.mpeg4-generic.streamType-invalid-value`, `profile-level-id`, `objectType`, `constantSize`, `constantDuration`, `maxDisplacement`, `de-interleaveBufferSize`, `sizeLength`, `indexLength`, `indexDeltaLength`, `CTSDeltaLength`, `DTSDeltaLength`, `streamStateIndication`, `auxiliaryDataSizeLength` | A value that is not a decimal integer. | RFC 3640 §4.1 |
| `sdp.a.fmtp.mpeg4-generic.config-invalid-value` | A value that is neither a hexadecimal octet string (an even number of hexadecimal digits) nor the quoted empty string `""`. | RFC 3640 §4.1 |
| `sdp.a.fmtp.mpeg4-generic.randomAccessIndication-invalid-value` | A value other than `0` or `1`. | RFC 3640 §4.1 |
| `sdp.a.fmtp.mpeg4-generic.constantSize-sizeLength-exclusive` | `constantSize` and `sizeLength` on the same fmtp. | RFC 3640 §4.1 |
| `sdp.a.fmtp.mpeg4-generic.aac-mode-requires-size-and-index-lengths` | `mode=AAC-hbr` or `mode=AAC-lbr` without `sizeLength`, `indexLength`, and `indexDeltaLength`. | RFC 3640 §3.3.5 / §3.3.6 |
| `sdp.a.fmtp.mpeg4-generic.streamStateIndication-forbidden` | `streamStateIndication` on an `m=audio` or `m=video` block. | RFC 3640 §4.1 |

MPEG-4 audio LATM (RFC 6416, encoding `MP4A-LATM`). The registration
fixes no clock rate ("The default value is 90000. Other rates MAY be
indicated"), and defines no syntax for `bitrate`, so neither is
checked.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.rtpmap.mp4a-latm.media-type-must-be-audio` | An `MP4A-LATM` rtpmap on an `m=` line whose media type is not `audio`. | RFC 6416 §7.4 |
| `sdp.a.fmtp.mp4a-latm.profile-level-id-invalid-value`, `MPS-profile-level-id`, `object` | A value that is not a decimal integer. | RFC 6416 §7.3 |
| `sdp.a.fmtp.mp4a-latm.cpresent-invalid-value`, `SBR-enabled` | A value other than `0` or `1`. | RFC 6416 §7.3 |
| `sdp.a.fmtp.mp4a-latm.config-invalid-value`, `MPS-asc` | A value that is not a hexadecimal octet string. | RFC 6416 §7.3 |
| `sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0` | `cpresent=0` without `config`. | RFC 6416 §7.3 |

MPEG-2 transport stream (RFC 2250, encoding `MP2T`). RFC 3551 Table 5
registers the encoding under media type "AV", so the `m=` media type is
not checked, and the `video/MP2T` registration (RFC 3555 section 4.2.9)
defines no parameters, so an `a=fmtp` for it is not checked.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.rtpmap.mp2t.clock-rate-must-be-90000` | An `MP2T` rtpmap clock rate other than 90000. | RFC 2250 §2; RFC 3551 Table 5 |

Linear PCM (RFC 3555, encoding `L16`).

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.fmtp.l16.emphasis-invalid-value` | An `L16` fmtp `emphasis` value other than `50-15`, the only value the registration defines. | RFC 3555 §4.1.15 |

#### Malformed known attributes

The parser recognizes the attributes in the table below by name. When
the value of one of these attributes does not match the attribute's
syntax to the end of the line, the parser records the attribute's
`.malformed` check at the first column of the value. The check is
hard-syntactic with default severity `error`. Under a policy that
demotes the check, the parse continues and the attribute is kept as
`{name, malformed = true, value}`. A value cut short by a NUL byte or by
a CR that is not part of CRLF is a structural `PARSE_ERROR` instead,
except for a NUL byte in an `a=fmtp` value.

The `a=fmtp` check covers the payload type, the space after the payload
type, and a NUL byte in the body. RFC 8866 section 6.15 allows any byte
string as the format-specific parameters, and section 9 defines
`byte-string` as `1*(%x01-09/%x0B-0C/%x0E-FF)`, which excludes NUL. So
at the RFC 8866 tier an `a=fmtp` body is malformed only when it holds a
NUL byte, and the check is recorded at the first column of the value. At
the ST 2110 tier, the same NUL byte is reported by this check alone. At the ST 2110 tier, a `raw` video `a=fmtp` body has
its own check, `st2110-20.a.fmtp.malformed`, in the ST 2110-20 table. A
`ptp=` value of `a=ts-refclk` has its own check,
`sdp.a.ts-refclk.ptp-malformed`. The IPMX attributes `a=infoframe`,
`a=hkep`, and `a=privacy` have their checks in the IPMX tables.

A value that matches the attribute's syntax but fails a value check of a
higher tier is reported on that check's id only, not also on the
`.malformed` check. For example, at the ST 2110 tier `a=rtpmap:96
raw/48000` is reported as `st2110-20.a.rtpmap.raw-clock-rate` and not as
`sdp.a.rtpmap.malformed`, and at the IPMX tier `a=group:FID 1` is
reported as `tr-10-1.a.group.fid-forbidden` and not as
`sdp.a.group.malformed`.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `sdp.a.ptime.malformed` | An `a=ptime` value that is not a non-zero integer or a non-zero decimal. A decimal cannot end in `0` (`1.0`), and an integer cannot start with `0`. | RFC 8866 §6.4 / §9 (ptime-value = non-zero-int-or-real) |
| `sdp.a.maxptime.malformed` | An `a=maxptime` value of the same wrong forms as `a=ptime`. | RFC 8866 §6.5 / §9 (maxptime-value = non-zero-int-or-real) |
| `sdp.a.framerate.malformed` | An `a=framerate` value of the same wrong forms as `a=ptime`. | RFC 8866 §6.13 / §9 (framerate-value = non-zero-int-or-real) |
| `sdp.a.quality.malformed` | An `a=quality` value that is not `0` or an integer with no leading zero. | RFC 8866 §6.14 / §9 (quality-value = zero-based-integer) |
| `sdp.a.rtpmap.malformed` | An `a=rtpmap` value that is not `<payload type> <encoding>/<clock rate>[/<channels>]`, with a payload type from 0 to 127, a token encoding name, and a clock rate and channel count that are integers with no leading zero. `a=rtpmap:97 L24/48000/0` is an example. | RFC 8866 §6.6 (rtpmap-value ABNF) |
| `sdp.a.fmtp.malformed` | An `a=fmtp` value that does not start with a payload type from 0 to 127 followed by a space and at least one byte, or a value that holds a NUL byte. | RFC 8866 §6.15 (fmtp-value = fmt SP format-specific-params) |
| `sdp.a.mid.malformed` | An `a=mid` value that is not one token. | RFC 5888 §4 (mid-attribute ABNF) |
| `sdp.a.setup.malformed` | An `a=setup` value other than `active`, `passive`, `actpass`, or `holdconn`. | RFC 4145 §4 (setup-attr ABNF) |
| `sdp.a.group.malformed` | An `a=group` value that is not a semantics token followed by zero or more tokens, each after one space. | RFC 5888 §5 (group-attribute ABNF) |
| `sdp.a.ssrc.malformed` | An `a=ssrc` value that is not `<ssrc-id> <attribute>[:<value>]` with a decimal ssrc-id. | RFC 5576 §10 (ssrc-attr ABNF) |
| `sdp.a.ssrc-group.malformed` | An `a=ssrc-group` value that is not a semantics token followed by zero or more decimal ssrc-ids, each after one space. | RFC 5576 §10 (ssrc-group-attr ABNF) |
| `sdp.a.msid.malformed` | An `a=msid` value that is not `<msid-id>[ <msid-appdata>]`, where each field is 1 to 64 token characters. A third field, a 65-character field, or a character such as `/`, `:`, or `"` is an example. The default severity is `warn`, because RFC 8830 §3 says that a receiver "SHOULD" ignore a non-conforming `a=msid`; the attribute is kept with `malformed = true`. | RFC 8830 §2 (msid-value ABNF) |
| `sdp.a.extmap.malformed` | An `a=extmap` value that is not `<id>[/<direction>] <URI>[ <attributes>]`, with a decimal id and a direction of `sendonly`, `recvonly`, `sendrecv`, or `inactive`. | RFC 8285 §8 (extmap-value ABNF) |
| `sdp.a.rtcp-fb.malformed` | An `a=rtcp-fb` value that is not `<payload type or *> <feedback type>[ <parameters>]`. | RFC 4585 §4.2 (rtcp-fb-syntax ABNF) |
| `sdp.a.rtcp.malformed` | An `a=rtcp` value that is not `<port>[ IN <IP4 or IP6> <address>]`. | RFC 3605 §2.1 (rtcp-attribute ABNF) |
| `sdp.a.rtcp-mux.malformed` | An `a=rtcp-mux` line with a value. RFC 5761 section 8 says the attribute "does not take a value". | RFC 5761 §8 |
| `sdp.a.source-filter.malformed` | An `a=source-filter` value that is not a space, `incl` or `excl`, `IN`, `IP4`, `IP6`, or `*`, a destination address, and at least one source address, each separated by one space. | RFC 4570 Appendix A (source-filter ABNF) |
| `sdp.a.ts-refclk.malformed` | An `a=ts-refclk` value, other than a `ptp=` value, that is not one of the RFC 7273 clock sources or an extension. A defined name used in a different form, for example `gps=1`, a bare `ntp`, or `private:x`, is not accepted as an extension. | RFC 7273 §4.8 (clksrc ABNF) |
| `sdp.a.mediaclk.malformed` | An `a=mediaclk` value that is not an optional `id=<tag> ` followed by `sender`, `direct[=<offset>][ rate=<n>/<d>]`, `IEEE1722=<EUI-64>`, or an extension. A defined name used in a different form, for example `direct=x` or `sender=1`, is not accepted as an extension. | RFC 7273 §5.4 (media-clksrc ABNF) |

### What the library does not reject

- Configurations that a specification calls out of scope or permits
  without requiring. ST 2110-30 section 6.1 requires support for 48 kHz
  audio, permits 44.1 kHz and 96 kHz, and then says *"Other sampling
  frequencies and resolutions are out of scope of this standard."* Out
  of scope is not the same as forbidden, so the validator accepts any
  positive clock rate for `L16` and `L24`. The same applies to the audio
  channel count: ST 2110-30 documents conformance levels up to 64
  channels and has no global upper bound, so the validator has none.
- Combinations that the specification does not address. ST 2110-20
  lists the `sampling`, `colorimetry`, `TCS`, and `RANGE` value sets
  independently and forbids only the combinations listed under
  [ST 2110-20 raw video checks](#st-2110-20-raw-video-checks). Any other
  combination of valid individual values is accepted, for example
  `sampling=RGB` with `colorimetry=BT2020`.
- NMOS (Networked Media Open Specifications) requirements. The IPMX
  profile documents require device-level behavior: senders expose
  BCP-004-02 Sender Capabilities, receivers support defined format
  combinations, and IS-04, IS-05, and IS-11 are implemented. These
  requirements need state beyond one SDP file and are not checked.
- RTCP (RTP Control Protocol) content. IPMX Media Info Blocks, PEP
  (Privacy Encryption Protocol) Media Info Blocks, HKEP (HDCP Key
  Exchange Protocol) exchanges, and HDR (high dynamic range) metadata
  are transmitted in RTP or RTCP, not in SDP, and are not checked.
- Sender and receiver capability sets. An SDP file describes one
  stream. Whether a device supports other formats is signaled through
  NMOS Sender Capabilities, not through SDP.
- An attribute at a level other than the one its registration names,
  such as a session-level `a=rtpmap` or `a=fmtp`. RFC 8866 section 5.13
  says attributes "may be defined to be used as session-level
  attributes, media-level attributes, or both", but it does not forbid
  other use. At the ST 2110 tier a session-level `a=rtpmap` still gets
  the clock-rate checks. It gets no media-type check, because it has no
  `m=` line to compare with.
- A session with no media description, at the RFC 8866 tier. RFC 8866
  does not require one. ST 2110 and IPMX reject it
  (`st2110-10.m.media-description-required`).
- Audio shapes for which no primary text was found: `MAXUDP` on an
  `AM824` stream (ST 2110-31 defers to ST 2110-10, which permits
  `MAXUDP`), a missing channel count on `L16` or `L24` (RFC 3551
  section 6 makes the count optional), and the packet-payload-fit
  computation for `AM824` (ST 2110-31 has no UDP size requirement of its
  own).

The library also does not check the following. Each item is a
limitation of the current implementation, not a statement that the
specifications are silent.

- The `m=` port value against an upper bound. `m=video 70000` is
  accepted at every tier.
- The `a=connection` value (RFC 4145). `a=setup` is checked at every
  tier.
- The PTP version token in `a=ts-refclk:ptp=` (`IEEE1588-2008`,
  `IEEE1588-2019`, or any other token). RFC 7273 leaves it open.
- The `a=rtpmap` encoding name of an audio or video stream. Encodings
  other than `raw`, `jxsv`, `smpte291`, `AM824`, and `ST2110-41` get no
  per-encoding checks at the ST 2110 tier; `opus/48000/2` passes. `H264`,
  `H265`, `mpeg4-generic`, `MP4A-LATM`, `MP2T`, and `L16` get their RFC checks
  at every tier (see
  [Codec payload-format checks](#codec-payload-format-checks)). At the
  ST 2110 tier an ST 2110-22 stream is recognized by `jxsv` or by
  `SSN=ST2110-22:*`; an `H264` block without that marker gets no
  ST 2110-22 check there. At the IPMX tier every compressed video block
  does.
- The `a=ptime` value on `L16` and `L24` streams. AES67 section 8.1 says
  values outside its table shall be correctly interpreted, so only the
  presence is required.
- An `a=fmtp` for a payload type that the `m=` line lists but no
  `a=rtpmap` names (a static payload type) gets only the cross-encoding
  checks (`TSMODE`, `TSDELAY`, and at the IPMX tier the FEC parameters).
- Whether one SDP file describes more than one stream. ST 2110-10
  section 8.1 says a device shall construct one SDP per stream (or
  redundant pair); the library checks each stream it finds and rejects
  only a file with none.
- An H.265 `a=fmtp` line that carries `dec-parallel-cap`. Its braces
  hold semicolons, so the `key=value` split cannot carry it, and the
  line's other H.265 parameters are not checked either.
- `a=group:FID` at the ST 2110 tier. The IPMX tier rejects it
  (`tr-10-1.a.group.fid-forbidden`).
- Multicast control-block addresses such as 224.0.0.0/24. Any address
  from 224.0.0.0 to 239.255.255.255 is treated as multicast and accepted
  with a TTL.
- RTP attributes (`a=rtpmap`, `a=fmtp`, `a=mediaclk`, `a=ts-refclk`) on
  an IPMX USB transport block. TR-10-14 section 14 does not forbid them
  in explicit text, so the library accepts them.
- The `a=hkep` port and the `a=infoframe` port against an upper bound.
  Both must be positive integers; `a=hkep:70000` is accepted.
- The `k=` line. The parser accepts a `k=` line in the RFC 8866 position
  and discards it, so a file with a `k=` line does not round-trip
  byte for byte.

### Adding a check

A new check needs a specific clause in a standard or RFC with normative
language: a positive *shall* or *MUST*, a prohibitive *shall not*,
*MUST NOT*, or *is forbidden*, or a defined value form or value set for
an optional parameter. The argument that a device sending a value must
be broken is an opinion, and an opinion-based check is not added. When
the clause exists, the check quotes it in the code comment
and cites it in the `spec_ref` field of the error.

---

## ST 2110 validation checks

`sdp.parse(text, "st2110")` and `doc:validate("st2110")` run every
RFC 8866 check and then the checks in this section. The tables have
three columns: the check id, what the check rejects, and the `spec_ref`
string as the registry stores it. The section is organized by the
ST 2110 part that authors each requirement.

The ST 2110 per-stream checks apply to RTP media descriptions, which
are media descriptions whose `m=` protocol is `RTP` or starts with
`RTP/`. A media description with another protocol, such as the IPMX USB
transport block, is not subject to them.

### ST 2110-10: system and session checks

ST 2110-10:2022 section 8.1 says: *"Devices which contain one or more
Senders shall construct one SDP session description as specified in
IETF RFC 4566 for each RTP stream (or redundant pair of streams) that is
originated by that device."* A session with no `m=` line describes no
RTP stream, so the ST 2110 tier rejects it. The IPMX tier inherits the
rejection. The RFC 8866 tier accepts the session.

Section 8.2 requires an `a=ts-refclk` attribute for every stream. The
attribute may be at the session level, where it covers every media
description, or in each media description. Section 8.3 requires a
media-level `a=mediaclk` attribute; a session-level `a=mediaclk` does
not satisfy that requirement, although it is accepted when every RTP
media description also has its own.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-10.m.media-description-required` | An SDP file with no `m=` line. | ST 2110-10:2022 §8.1 |
| `st2110-10.m.proto-must-be-rtp-avp` | An RTP media description whose protocol is not `RTP/AVP`, for example `RTP/AVPF` or `RTP/SAVP`. | ST 2110-10:2022 §6.2 |
| `st2110.attr.ts-refclk-required` | An RTP media description with no `a=ts-refclk` when the session level has none either. | ST 2110-10:2022 §8.2 |
| `st2110.attr.mediaclk-required` | An RTP media description with no media-level `a=mediaclk`. | ST 2110-10:2022 §8.3 |
| `st2110-10.a.mediaclk.form-invalid-value` | An `a=mediaclk` (session or media level) that is neither `direct` nor `sender`. Section 8.3 names those two forms for the two possible clock relationships. | ST 2110-10:2022 §8.3 |
| `st2110-10.a.mediaclk.direct-offset-required` | `a=mediaclk:direct` with no `=<offset>`. | ST 2110-10:2022 §8.3 |
| `st2110-10.a.mediaclk.direct-offset-must-be-zero` | `a=mediaclk:direct=<offset>` with an offset other than 0. | ST 2110-10:2022 §7.3 |
| `st2110-10.a.ts-refclk.ptp-domain-required` | `a=ts-refclk:ptp=<version>:<grandmaster>` with no `:<domain>`. The traceable form needs no domain. | ST 2110-10:2022 §8.2 |
| `st2110-10.a.ts-refclk.ptp-domain-invalid-value` | A PTP domain that is not a decimal number from 0 to 127. | ST 2110-10:2022 §8.2; RFC 7273 §4.8 |
| `st2110-10.a.fmtp.tsmode-invalid-value` | An `a=fmtp` `TSMODE` value other than `SAMP`, `NEW`, or `PRES`. The check runs on every decomposed `a=fmtp` line, whatever the encoding. | ST 2110-10:2022 §8.7 |
| `st2110-10.a.fmtp.tsdelay-invalid-value` | An `a=fmtp` `TSDELAY` value that is not a positive decimal integer. `TSDELAY=0` is rejected. The check runs on every decomposed `a=fmtp` line. | ST 2110-10:2022 §8.7 |

#### ST 2022-7 redundancy grouping (`a=group:DUP`)

ST 2110-10:2022 section 8.5 requires duplicate streams to meet ST
2022-7. When a session-level `a=group:DUP <tag> <tag> ...` line is
present, the library resolves each tag to the media description with
the matching `a=mid` and compares the legs. The absence of
`a=group:DUP` is not an error. More than two legs are accepted. Legs
may use different destination addresses or ports.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-10.a.group-dup.mid-resolve` | A tag in an `a=group:DUP` line that matches no `a=mid` in the session. | ST 2110-10:2022 §8.5 |
| `st2110-10.a.group-dup.min-2-legs` | An `a=group:DUP` line in which fewer than two tags resolve to media descriptions. | ST 2110-10:2022 §8.5 |
| `st2110-10.a.group-dup.media-type-same` | Two legs with different `m=` media types. | ST 2110-10:2022 §8.5 |
| `st2110-10.a.group-dup.rtpmap-same` | Two legs whose first `a=rtpmap` lines differ in encoding name or clock rate. | ST 2110-10:2022 §8.5 |
| `st2110-10.a.group-dup.payload-type-same` | Two legs whose first `a=rtpmap` lines have different payload type numbers. | ST 2110-10:2022 §8.5 |
| `st2110-10.a.group-dup.fmtp-same` | Two legs whose first `a=fmtp` lines have different parameter sets. The sets are compared by key and value; the order of the parameters is ignored. | ST 2110-10:2022 §8.5 |
| `st2110-10.a.group-dup.addr-coherence` | Two legs with the same destination address (the media-level or session-level `c=` address) and the same source address (the first address of the first `a=source-filter`). The legs must differ in at least one of the two. | ST 2110-10:2022 §8.5 |

### ST 2110-20 raw video checks

The checks in this subsection apply to a media description with an
`a=rtpmap` whose encoding name is `raw`. ST 2110-20:2022 section 7.2
requires eight `a=fmtp` parameters, and ST 2110-21:2022 section 8.1
adds `TP` as a ninth. A `raw` payload type with no `a=fmtp` line is
reported with the same `-required` ids as an `a=fmtp` line that lacks
the parameters. `TCS` is defined in section 7.3 with a default and is
optional; section 7.6 says a receiver assumes `SDR` when `TCS` is
absent.

Value sets for the enumerated parameters:

| Parameter | Permitted values |
| --- | --- |
| `sampling` | `YCbCr-4:4:4`, `YCbCr-4:2:2`, `YCbCr-4:2:0`, `CLYCbCr-4:4:4`, `CLYCbCr-4:2:2`, `CLYCbCr-4:2:0`, `ICtCp-4:4:4`, `ICtCp-4:2:2`, `ICtCp-4:2:0`, `RGB`, `XYZ`, `KEY` |
| `depth` | `8`, `10`, `12`, `16`, `16f` |
| `colorimetry` | `BT601`, `BT709`, `BT2020`, `BT2100`, `ST2065-1`, `ST2065-3`, `XYZ`, `ALPHA`, `UNSPECIFIED` |
| `PM` | `2110GPM`, `2110BPM` |
| `SSN` | `ST2110-20:2017`, `ST2110-20:2022` |
| `TP` | `2110TPN`, `2110TPNL`, `2110TPW` |
| `TCS` | `SDR`, `PQ`, `HLG`, `LINEAR`, `BT2100LINPQ`, `BT2100LINHLG`, `ST2065-1`, `ST428-1`, `DENSITY`, `ST2115LOGS3`, `UNSPECIFIED` |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` |

Presence checks:

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-20.a.fmtp.sampling-required` | A `raw` video stream with no `sampling` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.width-required` | A `raw` video stream with no `width` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.height-required` | A `raw` video stream with no `height` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.exactframerate-required` | A `raw` video stream with no `exactframerate` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.depth-required` | A `raw` video stream with no `depth` parameter. | ST 2110-20:2022 §7.4.2 |
| `st2110-20.a.fmtp.colorimetry-required` | A `raw` video stream with no `colorimetry` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.PM-required` | A `raw` video stream with no `PM` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.SSN-required` | A `raw` video stream with no `SSN` parameter. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.TP-required` | A `raw` video stream with no `TP` parameter. | ST 2110-21:2022 §8.1 |

Value-form checks, which run when the parameter is present:

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-20.a.fmtp.sampling-invalid-value` | A `sampling` value outside the set above. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.width-invalid-value` | A `width` that is not an integer from 1 to 32767. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.height-invalid-value` | A `height` that is not an integer from 1 to 32767. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.exactframerate-invalid-value` | An `exactframerate` that is not a positive integer or a positive `n/d` ratio in lowest terms. `60000/2002` is rejected because section 7.2 requires *"the numerically smallest numerator value possible"*. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.depth-invalid-value` | A `depth` outside the set above, for example `14`. | ST 2110-20:2022 §7.4.2 |
| `st2110-20.a.fmtp.colorimetry-invalid-value` | A `colorimetry` value outside the set above. | ST 2110-20:2022 §7.5 |
| `st2110-20.a.fmtp.PM-invalid-value` | A `PM` value other than `2110GPM` or `2110BPM`. | ST 2110-20:2022 §6.3 |
| `st2110-20.a.fmtp.SSN-invalid-value` | An `SSN` value other than `ST2110-20:2017` or `ST2110-20:2022`. | ST 2110-20:2022 §7.2 |
| `st2110-20.a.fmtp.TP-invalid-value` | A `TP` value outside the set above. | ST 2110-21:2022 §8.1 |
| `st2110-20.a.fmtp.TCS-invalid-value` | A `TCS` value outside the set above. | ST 2110-20:2022 §7.6 |
| `st2110-20.a.fmtp.RANGE-invalid-value` | A `RANGE` value outside the set above. | ST 2110-20:2022 §7.3 |
| `st2110-20.a.fmtp.MAXUDP-invalid-value` | A `MAXUDP` that is not a positive integer, or that is greater than 8960 (the Extended UDP Size Limit). | ST 2110-20:2022 §7.3 |
| `st2110-20.a.fmtp.PAR-invalid-value` | A `PAR` that is not `W:H` with both parts positive integers in lowest terms. `12:11` is accepted; `2:2` is rejected. | ST 2110-20:2022 §7.3 |
| `st2110-21.a.fmtp.troff-invalid-value` | A `TROFF` on a `raw` video fmtp that is not a positive integer. | ST 2110-21:2022 §8.2 |
| `st2110-21.a.fmtp.cmax-invalid-value` | A `CMAX` on a `raw` video fmtp that is not an integer. | ST 2110-21:2022 §8.2 |
| `st2110-20.a.fmtp.interlace-invalid-value` | An `interlace` parameter with an `=value`. The parameter is a bare flag. | ST 2110-20:2022 §7.3 |
| `st2110-20.a.fmtp.segmented-invalid-value` | A `segmented` parameter with an `=value`. The parameter is a bare flag. | ST 2110-20:2022 §7.3 |
| `st2110-20.a.fmtp.no-whitespace-around-equals` | A space or tab before or after the `=` of any parameter on a `raw` video `a=fmtp` line. The check is hard-syntactic and is recorded once per line, at the first such space or tab. A line with this defect is reported by this check only, even when the body has other entry defects (`sampling = a b`). Demoted, a body that otherwise has the entry form keeps its `params`; any other body is kept as `{name, malformed = true, value}`. | ST 2110-20:2022 §7.1 |
| `st2110-20.a.fmtp.semicolon-without-whitespace` | A `;` between two parameters on a `raw` video `a=fmtp` line that is not followed by whitespace (`sampling=YCbCr-4:2:2;width=1920`), a warning. Section 7.1 says the entries are *"separated by the semicolon (";") character followed by whitespace"* and states no amount, so one space or tab is enough. The check is soft-syntactic, is recorded once per line at the first such `;`, and the parameters are decomposed as usual. A `;` at the end of the value is `sdp.a.fmtp.trailing-semicolon` instead. | ST 2110-20:2022 §7.1 |
| `st2110-20.a.fmtp.malformed` | A `raw` video `a=fmtp` body with a parameter entry that is empty (`;;`, or a `;` at the start), has no name (`=x`), or has whitespace within the name or within the value (`colorimetry=BT 709`). Whitespace before a `;` or before the first entry is also rejected. A body with whitespace around an `=` is `st2110-20.a.fmtp.no-whitespace-around-equals` instead. Whitespace before the line end is the `sdp.line.trailing-whitespace` warning instead. A name can contain any character other than whitespace, `;`, and `=` (`x.vendor=1` is accepted), because the clause limits a name only by "no whitespace within the name". The check is hard-syntactic and is recorded at the first column of the value. Demoted, the line is kept as `{name, malformed = true, value}`. | ST 2110-20:2022 §7.1 |

Parameters that ST 2110-20 does not define, for example a vendor
parameter, pass through without a finding.

Cross-parameter checks:

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-20.a.fmtp.segmented-requires-interlace` | `segmented` without `interlace`. | ST 2110-20:2022 §7.3 |
| `st2110-20.a.fmtp.bpm-with-maxudp-forbidden` | `MAXUDP` together with `PM=2110BPM`. Section 6.3.3 says the Extended UDP Size Limit *"shall not be used in the Block Packing Mode"*. | ST 2110-20:2022 §6.3.3 |
| `st2110-20.a.fmtp.bt2100-range-fullprotect-forbidden` | `RANGE=FULLPROTECT` together with `colorimetry=BT2100`. Only `NARROW` and `FULL` are permitted with `BT2100`. | ST 2110-20:2022 §7.3 |
| `st2110-20.a.fmtp.key-requires-alpha-colorimetry` | `sampling=KEY` without `colorimetry=ALPHA`. | ST 2110-20:2022 §7.4.1 |
| `st2110-20.a.fmtp.key-forbids-tcs` | `sampling=KEY` together with any `TCS` value. | ST 2110-20:2022 §7.4.1 |
| `st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden` | A `4:2:0` sampling value (`YCbCr-4:2:0`, `CLYCbCr-4:2:0`, or `ICtCp-4:2:0`) together with `interlace`. Section 6.2.5 says *"The 4:2:0 sampling system shall only be applied to progressive scan images transmitted in a progressive manner."* | ST 2110-20:2022 §6.2.5 |
| `st2110-20.a.fmtp.subsampling-420-depth-restricted` | A `4:2:0` sampling value with `depth=16` or `depth=16f`. Table 3 defines 4:2:0 only for depths 8, 10, and 12. | ST 2110-20:2022 §6.2.5 Table 3 |
| `st2110-20.a.fmtp.tcs-linear-requires-depth-16f` | `TCS=LINEAR` with a `depth` other than `16f`. | ST 2110-20:2022 §7.6 |
| `st2110-20.a.fmtp.tcs-bt2100linpq-requires-depth-16f` | `TCS=BT2100LINPQ` with a `depth` other than `16f`. | ST 2110-20:2022 §7.6 |
| `st2110-20.a.fmtp.tcs-bt2100linhlg-requires-depth-16f` | `TCS=BT2100LINHLG` with a `depth` other than `16f`. | ST 2110-20:2022 §7.6 |
| `st2110-20.a.fmtp.tcs-st2065-1-requires-depth-16f` | `TCS=ST2065-1` with a `depth` other than `16f`. | ST 2110-20:2022 §7.6 |
| `st2110-20.a.fmtp.ssn-required-for-2022-only-values` | `TCS=ST2115LOGS3` or `colorimetry=ALPHA` with an `SSN` other than `ST2110-20:2022`. Those two values are not defined in the 2017 revision. The reverse direction (requiring `ST2110-20:2017` when no 2022-only value is used) is not enforced, because most senders that implement the 2022 revision signal `ST2110-20:2022` unconditionally. | ST 2110-20:2022 §7.2 |

Checks on the `a=rtpmap` line:

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-20.a.rtpmap.raw-clock-rate` | An `a=rtpmap` for `raw` with a clock rate other than 90000. | ST 2110-20:2022 §7.1 |
| `st2110-20.a.rtpmap.raw-media-type` | An `a=rtpmap` for `raw` in a media description whose `m=` media type is not `video`. | ST 2110-20:2022 §7.1 |

### ST 2110-21 and ST 2110-22: JPEG XS (`jxsv`) checks

The checks in this subsection apply to a media description with an
`a=rtpmap` whose encoding name is `jxsv`. The ST 2110-22 checks that
are not specific to JPEG XS (`width`, `height`, and `TP` required and
their value forms, `b=AS`, the frame-rate indication, the 90 kHz clock
rate, and the `TP`/`SSN` edition coupling) also apply to any media
description whose fmtp carries `SSN=ST2110-22:2019` or
`SSN=ST2110-22:2022`, and at the IPMX tier to every `m=video` media
description whose encoding is not `raw` or `smpte291` (TR-10-7 and
TR-10-11 both send compressed video to ST 2110-22 section 7). ST 2110-22:2022 section 7.2
Table 1 lists `width`, `height`, and `TP` as the mandatory
format-specific parameters, and the IANA `video/jxsv` registration in
RFC 9134 section 7.1 adds `packetmode`. Section 7.3 Table 3 requires a
media-level `b=AS:<kbps>` line. `PM` is an ST 2110-20 parameter, not a
`jxsv` parameter; the corresponding `jxsv` control is `packetmode`.

The parameters `sampling`, `depth`, `TCS`, `colorimetry`, `profile`,
`level`, `sublevel`, `transmode`, `RANGE`, `MAXUDP`, `CMAX`,
`exactframerate`, and `SSN` are optional and are checked only when
present. `fbblevel` is not an SDP parameter in any specification the
library covers (it is a field of the RTCP JPEG XS Media Info Block), so
the library accepts `fbblevel=...` without checking its value.

Value sets for the enumerated `jxsv` parameters. Three of the sets
differ from the ST 2110-20 sets because RFC 9134 defines them for
`jxsv`.

| Parameter | Permitted values |
| --- | --- |
| `TP` | `2110TPN`, `2110TPNL`, `2110TPW` |
| `packetmode`, `transmode` | `0`, `1` |
| `sampling` | The ST 2110-20 set plus `UNSPECIFIED` |
| `TCS` | `SDR`, `PQ`, `HLG`, `UNSPECIFIED` |
| `colorimetry` | `BT601-5`, `BT709-2`, `SMPTE240M`, `BT601`, `BT709`, `BT2020`, `BT2100`, `ST2065-1`, `ST2065-3`, `XYZ`, `UNSPECIFIED` (no `ALPHA`) |
| `RANGE` | `NARROW`, `FULLPROTECT`, `FULL` |
| `SSN` | `ST2110-22:2019`, `ST2110-22:2022` |
| `profile` | `Unrestricted`, `Light422.10`, `Light444.12`, `LightSubline422.10`, `LightSubline444.12`, `Main422.10`, `Main444.12`, `High444.12`, `MLS.12`, `LightBayer`, `MainBayer`, `HighBayer`, `MLSBayer` |
| `level` | `Unrestricted`, `1k-1`, `2k-1`, `4k-1`, `4k-2`, `4k-3`, `8k-1`, `8k-2`, `8k-3`, `16k-1`, `16k-2`, `16k-3` |
| `sublevel` | `Unrestricted`, `Full`, `Sublev12bpp`, `Sublev9bpp`, `Sublev6bpp`, `Sublev4bpp`, `Sublev3bpp`, `Sublev2bpp` |

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-22.a.rtpmap.jxsv-clock-rate` | An `a=rtpmap` for `jxsv` with a clock rate other than 90000. | ST 2110-22:2022 §5.2 |
| `st2110-22.a.rtpmap.jxsv-media-type` | An `a=rtpmap` for `jxsv` in a media description whose `m=` media type is not `video`. | ST 2110-22:2022 §6.2 / RFC 9134 |
| `st2110-22.b.as-required` | A `jxsv` media description with no media-level `b=AS` line. | ST 2110-22:2022 §7.3 |
| `st2110-22.b.as-invalid-value` | A `b=AS` value on a `jxsv` media description that is not a positive integer. | ST 2110-22:2022 §7.3 |
| `st2110-22.framerate-indication-required` | An ST 2110-22 media description with neither `a=framerate` nor an fmtp `exactframerate`. | ST 2110-22:2022 §7.4 |
| `st2110-22.a.fmtp.tp-2110tpn-requires-ssn-2022` | `TP=2110TPN` together with `SSN=ST2110-22:2019`. The 2019 edition defines only `2110TPNL` and `2110TPW`. | ST 2110-22:2019 §7.2 Table 1 |
| `st2110-22.a.rtpmap.clock-rate-must-be-90000` | An ST 2110-22 media description (other than `jxsv`, which has its own id) whose rtpmap clock rate is not 90000. | ST 2110-22:2022 §5.2 |
| `st2110-22.a.fmtp.width-required` | A `jxsv` stream with no `width` parameter. | ST 2110-22:2022 §7.2 |
| `st2110-22.a.fmtp.height-required` | A `jxsv` stream with no `height` parameter. | ST 2110-22:2022 §7.2 |
| `st2110-22.a.fmtp.TP-required` | A `jxsv` stream with no `TP` parameter. | ST 2110-22:2022 §7.2 |
| `st2110-22.a.fmtp.packetmode-required` | A `jxsv` stream with no `packetmode` parameter. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.width-invalid-value` | A `width` that is not an integer from 1 to 32767. | ST 2110-22:2022 §7.2 |
| `st2110-22.a.fmtp.height-invalid-value` | A `height` that is not an integer from 1 to 32767. | ST 2110-22:2022 §7.2 |
| `st2110-22.a.fmtp.TP-invalid-value` | A `TP` value outside the set above. | ST 2110-22:2022 §5.3 |
| `st2110-22.a.fmtp.packetmode-invalid-value` | A `packetmode` other than `0` or `1`. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.transmode-invalid-value` | A `transmode` other than `0` or `1`. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.sampling-invalid-value` | A `sampling` value outside the set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.TCS-invalid-value` | A `TCS` value outside the four-value set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.colorimetry-invalid-value` | A `colorimetry` value outside the set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.RANGE-invalid-value` | A `RANGE` value outside the set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.profile-invalid-value` | A `profile` value outside the set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.level-invalid-value` | A `level` value outside the set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.sublevel-invalid-value` | A `sublevel` value outside the set above. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.depth-invalid-value` | A `depth` that is not a positive integer. RFC 9134 lists 8, 10, 12, and 16 as typical values without closing the set. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.exactframerate-invalid-value` | An `exactframerate` that is not a positive integer or a positive `n/d` ratio in lowest terms. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.MAXUDP-invalid-value` | A `MAXUDP` that is not a positive integer, or that is greater than 8960. | ST 2110-10 §6.4 |
| `st2110-22.a.fmtp.CMAX-invalid-value` | A `CMAX` that is not an integer. Zero and negative integers are accepted, because ST 2110-21:2022 section 8.2 defines the value as *"expressed as an integer number"* with no sign restriction. | ST 2110-21:2022 §8.2 |
| `st2110-22.a.fmtp.SSN-invalid-value` | An `SSN` value other than `ST2110-22:2019` or `ST2110-22:2022`. | ST 2110-22:2022 §7.2 |
| `st2110-22.a.fmtp.interlace-invalid-value` | An `interlace` parameter with an `=value`. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.segmented-invalid-value` | A `segmented` parameter with an `=value`. | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.segmented-requires-interlace` | `segmented` without `interlace`. RFC 9134 section 7.1 says *"Signaling of this parameter without the interlace parameter is forbidden."* | RFC 9134 §7.1 |
| `st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden` | `RANGE=FULLPROTECT` together with `colorimetry=BT2100`. | RFC 9134 §7.1 |

A trailing semicolon after the last `jxsv` parameter produces the
RFC 8866 tier warning `sdp.a.fmtp.trailing-semicolon`; the ST 2110 tier
does not add an error for it.

### ST 2110-30 and ST 2110-31: audio checks

The checks in this subsection apply to media descriptions with an
`a=rtpmap` whose encoding name is `L16`, `L24`, or `AM824`. The clock
rate of `L16` and `L24` is not restricted; see the previous section.
The channel count (the third `/`-separated field of the `a=rtpmap`
value) is optional for `L16` and `L24` and required for `AM824`.

`channel-order` is optional (ST 2110-30:2017 section 6.2.2: *"If the
channel-order parameter is not present, the audio channels shall be
treated as Undefined"*). When present, the value must have the RFC 3190
form `<convention>.<order>`. When the convention is `SMPTE2110`, the
order must be `(<group>[,<group>...])` where each group is `M`, `DM`,
`ST`, `LtRt`, `51`, `71`, `222`, `SGRP`, `U01` to `U64`, or, only on an
`AM824` stream, `AES3`. A convention other than `SMPTE2110` is accepted
without a check on the order.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-30.a.fmtp.channel-order-invalid` | A `channel-order` value that is not `<convention>.<order>`, or an `SMPTE2110` order that is not a parenthesized, comma-separated list of the group symbols above. | ST 2110-30:2025 §6.2.2 |
| `st2110-30.a.fmtp.maxudp-forbidden` | A `MAXUDP` parameter on an `L16` or `L24` stream. Section 6.2.1 requires the Standard UDP Size Limit, and `MAXUDP` signals operation beyond it. `AM824` is not checked. | ST 2110-30:2025 §6.2.1 |
| `st2110-30.audio.packet-payload-fit` | An `L16` or `L24` stream whose RTP payload per packet exceeds 1448 octets (the 1460-octet Standard UDP Size Limit minus the 12-octet RTP header). The payload is channels (1 when absent) times bytes per sample (2 for `L16`, 3 for `L24`) times samples per packet (clock rate times `a=ptime` in milliseconds, divided by 1000 and rounded to the nearest integer). The check runs only when the media description has an `a=ptime` line. `AM824` is not checked. | ST 2110-30:2025 §6.2.1 |
| `st2110-30.a.ptime-required` | An `L16` or `L24` media description with no `a=ptime`. ST 2110-30 requires AES67's SDP, and AES67 section 8.1 requires `ptime`. The value is not restricted. | ST 2110-30:2025 §6.2; AES67 §8.1 |
| `st2110-31.a.ptime-required` | An `AM824` media description with no `a=ptime`. | ST 2110-31:2022 §6.1 |
| `st2110-31.a.ptime-invalid-value` | An `AM824` `a=ptime` that is not a Table 1 value for the clock rate: 1, 0.12, or 0.08 at 48000 and 96000; 1.09, 0.14, or 0.09 at 44100. | ST 2110-31:2022 §6.1 Table 1 |
| `st2110-31.a.fmtp.channel-order-aes3-requires-am824` | The group `AES3` in a `channel-order` on a stream whose encoding is not `AM824`. | ST 2110-31:2022 §6.2 |
| `st2110-31.a.rtpmap.am824-channels-required` | An `a=rtpmap` for `AM824` with no channel count. | ST 2110-31:2022 §6.1 |
| `st2110-31.a.rtpmap.am824-channels-must-be-even` | An `a=rtpmap` for `AM824` with an odd channel count. Each AES3 signal has two subframe sequences. | ST 2110-31:2022 §6.1 |
| `st2110-31.a.rtpmap.am824-clock-rate-set` | An `a=rtpmap` for `AM824` with a clock rate other than 44100, 48000, or 96000. | ST 2110-31:2022 §6.1 |
| `st2110-31.a.rtpmap.am824-media-type` | An `a=rtpmap` for `AM824` in a media description whose `m=` media type is not `audio`. | ST 2110-31:2022 §6.1 |

### ST 2110-40: ancillary data (`smpte291`) checks

The checks in this subsection apply to a media description with an
`a=rtpmap` whose encoding name is `smpte291`. ST 2110-40:2023 section 7
adds SDP requirements to RFC 8331, and the library enforces the 2023
revision. An `a=fmtp` line is required, because `SSN` and
`exactframerate` are required; a `smpte291` payload type with no
`a=fmtp` line is reported with the `-required` ids. `TM`, `TROFF`,
`DID_SDID`, and `VPID_Code` are optional and are checked when present.
`DID_SDID` may appear several times, and every occurrence is checked.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-40.a.rtpmap.smpte291-clock-rate` | An `a=rtpmap` for `smpte291` with a clock rate other than 90000. | ST 2110-40:2023 §5.3 |
| `st2110-40.a.rtpmap.smpte291-media-type` | An `a=rtpmap` for `smpte291` in a media description whose `m=` media type is not `video`. | RFC 8331 §4 |
| `st2110-40.a.fmtp.ssn-required` | A `smpte291` stream with no `SSN` parameter. | ST 2110-40:2023 §7 |
| `st2110-40.a.fmtp.ssn-invalid-value` | An `SSN` other than `ST2110-40:2018` when `TM` is absent, or other than `ST2110-40:2023` or `ST2110-40:2021` when `TM` is present. Section 7 says a receiver treats `ST2110-40:2021` as equivalent to `ST2110-40:2023`, and the library accepts it from a sender on the same terms. | ST 2110-40:2023 §7 |
| `st2110-40.a.fmtp.exactframerate-required` | A `smpte291` stream with no `exactframerate` parameter. | ST 2110-40:2023 §7 |
| `st2110-40.a.fmtp.exactframerate-invalid-value` | An `exactframerate` that is not a positive integer or a positive `n/d` ratio in lowest terms (the ST 2110-20 form). | ST 2110-20:2022 §7.2 |
| `st2110-40.a.fmtp.tm-invalid-value` | A `TM` value other than `LLTM` or `CTM`. | ST 2110-40:2023 §7 |
| `st2110-40.a.fmtp.troff-invalid-value` | A `TROFF` that is not a positive integer. `TROFF=0` is rejected: section 8.2 says the value is "expressed as a positive integer", although section 6.2 permits a zero offset. | ST 2110-21:2022 §8.2 |
| `st2110-40.a.fmtp.did-sdid-invalid-value` | A `DID_SDID` value that is not `{0xH[H],0xH[H]}`, where each `H[H]` is one or two hexadecimal digits. | RFC 8331 §4 |
| `st2110-40.a.fmtp.vpid-code-invalid-value` | A `VPID_Code` that is not a non-negative integer. | RFC 8331 §4 |
| `st2110-40.a.fmtp.vpid-code-too-many` | More than one `VPID_Code` parameter on one `a=fmtp` line. | RFC 8331 §4 |

### ST 2110-41: fast metadata checks

The checks in this subsection apply to a media description with an
`a=rtpmap` whose encoding name is `ST2110-41`. The clock rate is defined
per data item (ST 2110-41:2024 section 5.3: *"The RTP Clock rate and
RTP Timestamp requirements of each Data Item are defined in the
document that specifies the Data Item Package Contents"*), so the
library checks only that the rate is a positive integer, which the
RFC 8866 `a=rtpmap` grammar already requires. An `a=fmtp` line is
required because `SSN` is required. `DIT` is optional.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `st2110-41.a.fmtp.SSN-required` | An `ST2110-41` stream with no `SSN` parameter. | ST 2110-41:2024 §6 |
| `st2110-41.a.fmtp.SSN-invalid-value` | An `SSN` value other than `ST2110-41:2024`. | ST 2110-41:2024 §6 |
| `st2110-41.a.fmtp.DIT-invalid-value` | A `DIT` value that is not a comma-separated list of uppercase hexadecimal tokens with no `0x` prefix and no whitespace, for example `100,2000A1,1013FC,3FFF00`. | ST 2110-41:2024 §6 |
| `st2110-41.a.fmtp.maxudp-forbidden` | A `MAXUDP` parameter on an `ST2110-41` stream. Section 5.4 limits the stream to the Standard UDP Size Limit. | ST 2110-41:2024 §5.4 |

---

## IPMX validation checks

`sdp.parse(text, "ipmx")` and `doc:validate("ipmx")` run every RFC 8866
and ST 2110 check and then the checks in this section. The ST 2110
per-stream checks apply to RTP media descriptions; a USB transport
block (`m=application <port> TCP usb`) is not an RTP stream and gets
only the TR-10-14 checks. The tables have three columns: the check id,
what the check rejects, and the `spec_ref` string as the registry
stores it.

### TR-10-1: system checks

TR-10-1 section 10.1 says: *"IPMX Senders shall include the ' IPMX'
declaration in the a=fmtp clause of the SDP file."* The library
requires at least one `a=fmtp` line per RTP media description to
include the bare `IPMX` flag. A media description with no `a=fmtp` line
at all is not reported by this check; the ST 2110 tier reports a
missing `a=fmtp` for the encodings that require one.

TR-10-1 section 10.2 says: *"the sender shall include the
measuredpixclk, vtotal and htotal parameters in the a=fmtp clause of
the SDP file."* Section 10.3 requires `measuredsamplerate` for audio.
TR-10-9 section 10 extends both requirements to senders that are not
converting from a baseband signal, so the library requires the
parameters on every `raw` and `jxsv` video `a=fmtp` and on every `L16`,
`L24`, and `AM824` audio `a=fmtp`. A media description with another
encoding is not checked for them.

TR-10-1 section 8.7 says: *"RTCP Sender Report packets shall be sent to
the UDP destination port that corresponds to +1 from the port used by
their corresponding media payload."* `a=rtcp-mux` (RFC 5761) requests
RTP and RTCP on one port, which contradicts that requirement. An
`a=rtcp:<port>` line (RFC 3605) must name the media port plus 1. The
absence of `a=rtcp` is accepted. The ST 2110 tier accepts `a=rtcp-mux`
and any `a=rtcp` port.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `tr-10-1.a.fmtp.marker-required` | An RTP media description with one or more `a=fmtp` lines, none of which has the bare `IPMX` flag. | TR-10-1 §10.1 |
| `tr-10-1.a.fmtp.measuredpixclk-required` | A `raw` or `jxsv` `a=fmtp` line with no `measuredpixclk` parameter. | TR-10-1 §10.2 |
| `tr-10-1.a.fmtp.measuredpixclk-invalid-value` | A `measuredpixclk` that is not a positive integer (hertz). | TR-10-1 §10.2 |
| `tr-10-1.a.fmtp.vtotal-required` | A `raw` or `jxsv` `a=fmtp` line with no `vtotal` parameter. | TR-10-1 §10.2 |
| `tr-10-1.a.fmtp.vtotal-invalid-value` | A `vtotal` that is not a positive integer (total lines per frame). | TR-10-1 §10.2 |
| `tr-10-1.a.fmtp.htotal-required` | A `raw` or `jxsv` `a=fmtp` line with no `htotal` parameter. | TR-10-1 §10.2 |
| `tr-10-1.a.fmtp.htotal-invalid-value` | An `htotal` that is not a positive integer (luminance sample periods per line). | TR-10-1 §10.2 |
| `tr-10-1.a.fmtp.measuredsamplerate-required` | An `L16`, `L24`, or `AM824` `a=fmtp` line with no `measuredsamplerate` parameter. | TR-10-1 §10.3 |
| `tr-10-1.a.fmtp.measuredsamplerate-invalid-value` | A `measuredsamplerate` that is not a positive integer (hertz). | TR-10-1 §10.3 |
| `tr-10-1.a.group.fid-forbidden` | A session-level `a=group:FID` line. Section 10 says FID grouping *"shall not be used under this TR"*. | TR-10-1 §10 |
| `tr-10-1.a.rtcp-mux.forbidden` | An `a=rtcp-mux` line in an RTP media description. | TR-10-1 §8.7 |
| `tr-10-1.a.rtcp.port-must-be-media-port-plus-1` | An `a=rtcp:<port>` line whose port is not the media port plus 1. | TR-10-1 §8.7 |

### TR-10-2: media port checks

TR-10-2 section 7 says: *"All IPMX Media streams shall have a UDP
destination port value that is even and that is greater than 1024."*
The same sentence appears in TR-10-3, TR-10-4, TR-10-11, and TR-10-12
section 7; the registry cites TR-10-2. The checks apply to every RTP
media description.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `ipmx.m.port-must-be-even` | An RTP media description with an odd `m=` port. | TR-10-2 §7 |
| `ipmx.m.port-must-exceed-1024` | An RTP media description with an `m=` port of 1024 or less. | TR-10-2 §7 |

### TR-10-5: HDCP key exchange (`a=hkep`) checks

`a=hkep` may appear at the session level, at the media level, or at
both (TR-10-5 section 17 registers the attribute with usage level
*"session, media"*). TR-10-5 section 10 requires at least one
session-level `a=hkep` when the stream is HDCP (High-bandwidth Digital
Content Protection) content; whether a stream is HDCP content is not
visible in the SDP, so the library checks the form of the attribute
when it is present. The form is:

```text
a=hkep:<port> IN <IP4|IP6> <unicast-address> <node-id> <port-id>
```

The port must be a positive integer in the RFC 8866 integer form; a
port of `0` or with a leading zero is reported as
`tr-10-5.a.hkep.malformed`. Several `a=hkep` lines are accepted.
`a=hkep` and `a=privacy` may both be present.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `tr-10-5.a.hkep.malformed` | An `a=hkep` value that is not six fields separated by single spaces, or whose port is not a positive integer with no leading zero. | TR-10-5 §10 |
| `tr-10-5.a.hkep.nettype-invalid-value` | A network type other than `IN`. | TR-10-5 §10 |
| `tr-10-5.a.hkep.addrtype-invalid-value` | An address type other than `IP4` or `IP6`. | TR-10-5 §10 |
| `tr-10-5.a.hkep.node-id-invalid-form` | A node id that is not 32 hexadecimal digits in the form `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`. | TR-10-5 §10 |
| `tr-10-5.a.hkep.port-id-invalid-form` | A port id that is not 10 hexadecimal digits in the form `xx-xx-xx-xx-xx`. | TR-10-5 §10 |

### TR-10-6: forward error correction parameter checks

The checks run on every decomposed `a=fmtp` line, whatever the
encoding. `FECPROFILE` is optional. The two
latency parameters signal a FEC (forward error correction) companion
stream and therefore require `FECPROFILE` on the same line.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `tr-10-6.a.fmtp.fecprofile-invalid-value` | A `FECPROFILE` value other than `profile-a`, the only IPMX FEC profile defined. | TR-10-6 §7.6 |
| `tr-10-6.a.fmtp.fec-add-latency-video-invalid-value` | A `FEC_ADD_LATENCY_VIDEO` that is not a non-negative integer (microseconds). | TR-10-6 §7.6 |
| `tr-10-6.a.fmtp.fec-add-latency-video-requires-fecprofile` | `FEC_ADD_LATENCY_VIDEO` without `FECPROFILE` on the same line. | TR-10-6 §7.6 |
| `tr-10-6.a.fmtp.fec-add-latency-audio-invalid-value` | A `FEC_ADD_LATENCY_AUDIO` that is not a non-negative integer (microseconds). | TR-10-6 §7.6 |
| `tr-10-6.a.fmtp.fec-add-latency-audio-requires-fecprofile` | `FEC_ADD_LATENCY_AUDIO` without `FECPROFILE` on the same line. | TR-10-6 §7.6 |

### TR-10-10: HDMI InfoFrame (`a=infoframe`) checks

TR-10-10 section 8 defines a session-level attribute of the form:

```text
a=infoframe:<port> SSN=ST2110-41:<year>;DIT=100100
```

The attribute is optional in the SDP, because whether the stream has an
HDMI (High-Definition Multimedia Interface) InfoFrame companion is not
visible in the SDP. When the attribute is present, the library checks
its level and its value. The port must be a positive integer. The
`SSN` year is checked only as a run of digits.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `tr-10-10.a.infoframe.malformed` | An `a=infoframe` value that is not `<port> SSN=<ssn>;DIT=<digits>`, or whose port is not a positive integer with no leading zero. | TR-10-10 §8 |
| `tr-10-10.a.infoframe.must-be-session-level` | An `a=infoframe` line inside a media description. | TR-10-10 §8 |
| `tr-10-10.a.infoframe.ssn-invalid-form` | An `SSN` that is not `ST2110-41:` followed by digits. | TR-10-10 §8 |
| `tr-10-10.a.infoframe.dit-invalid-value` | A `DIT` other than `100100`. | TR-10-10 §8 |
| `tr-10-10.a.infoframe.port-must-match-media-plus-3` | An `a=infoframe` port that is not equal to some media description's `m=` port plus 3. | TR-10-10 §8 |
| `tr-10-10.a.infoframe.duplicate-port` | Two session-level `a=infoframe` lines with the same port. | TR-10-10 §8 |

### TR-10-13: privacy encryption (`a=privacy`) checks

TR-10-13 section 13 defines the attribute as a semicolon-separated list
of `key=value` parameters, with a space permitted after each semicolon:

```text
a=privacy:protocol=<p>;mode=<m>;iv=<iv>;key_generator=<kg>;key_version=<kv>;key_id=<kid>
```

`a=privacy` may appear at the session level or at the media level. A
session-level `a=privacy` is the default for a media description that
has none. The library applies that default before comparing the legs
of an `a=group:DUP` group.

Permitted `mode` values, at every level and on every block type:
`AES-128-CTR`, `AES-256-CTR`, `AES-128-CTR_CMAC-64`,
`AES-256-CTR_CMAC-64`, `AES-128-CTR_CMAC-64-AAD`,
`AES-256-CTR_CMAC-64-AAD`, `ECDH_AES-128-CTR`, `ECDH_AES-256-CTR`,
`ECDH_AES-128-CTR_CMAC-64`, `ECDH_AES-256-CTR_CMAC-64`,
`ECDH_AES-128-CTR_CMAC-64-AAD`, `ECDH_AES-256-CTR_CMAC-64-AAD`.

The `protocol` value is not restricted on an RTP block, except that
`NULL` is forbidden. On a USB transport block the value must be
`USB_KV` (see TR-10-14 below).

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `tr-10-13.a.privacy.malformed` | An `a=privacy` value that is not a list of `key=value` parameters separated by a semicolon and an optional space. | TR-10-13 §13 |
| `tr-10-13.a.privacy.protocol-required` | An `a=privacy` with no `protocol` parameter. | TR-10-13 §13 |
| `tr-10-13.a.privacy.mode-required` | An `a=privacy` with no `mode` parameter. | TR-10-13 §13 |
| `tr-10-13.a.privacy.iv-required` | An `a=privacy` with no `iv` parameter. | TR-10-13 §13 |
| `tr-10-13.a.privacy.key_generator-required` | An `a=privacy` with no `key_generator` parameter. | TR-10-13 §13 |
| `tr-10-13.a.privacy.key_version-required` | An `a=privacy` with no `key_version` parameter. | TR-10-13 §13 |
| `tr-10-13.a.privacy.key_id-required` | An `a=privacy` with no `key_id` parameter. | TR-10-13 §13 |
| `tr-10-13.a.privacy.protocol-null-forbidden` | `protocol=NULL`. Section 13 says to omit the attribute instead. | TR-10-13 §13 |
| `tr-10-13.a.privacy.rtp-protocol-invalid-value` | An `a=privacy` on an RTP media description whose `protocol` is neither `RTP` nor `RTP_KV`. | TR-10-13 §20 |
| `tr-10-13.a.privacy.mode-invalid-value` | A `mode` outside the twelve values above. `NULL` is therefore rejected. | TR-10-13 §20.1 (per §13 'NULL mode shall not be used') |
| `tr-10-13.a.privacy.iv-invalid-form` | An `iv` that is not 16 hexadecimal digits (64 bits) with no spaces. | TR-10-13 §13 |
| `tr-10-13.a.privacy.key_generator-invalid-form` | A `key_generator` that is not 32 hexadecimal digits (128 bits). | TR-10-13 §13 |
| `tr-10-13.a.privacy.key_version-invalid-form` | A `key_version` that is not 8 hexadecimal digits (32 bits). | TR-10-13 §13 |
| `tr-10-13.a.privacy.key_id-invalid-form` | A `key_id` that is not 16 hexadecimal digits (64 bits). | TR-10-13 §13 |
| `tr-10-13.a.privacy.trailing-semicolon` | An `a=privacy` line that ends with a semicolon. | TR-10-13 §13 |
| `tr-10-13.a.privacy.dup-legs-must-match` | Two legs of an `a=group:DUP` group whose effective `a=privacy` parameters differ. The parameters are compared by key and value; order is ignored. Section 13 says: *"When using redundancy, as in ST 2022-7, the legs shall use the same privacy encryption parameters."* | TR-10-13 §13 |
| `tr-10-13.a.extmap.pep-direction-must-be-sendonly` | An `a=extmap` line, at either level, whose URI is `urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter` or `urn:ietf:params:rtp-hdrext:PEP-Short-IV-Counter` and whose direction is not `sendonly`. `a=extmap` itself is not required. | TR-10-13 §20.1 |

### TR-10-14: USB transport block checks

A USB transport block is a media description of the exact form
`m=application <port> TCP usb`. It is not an RTP stream, so the ST 2110
per-stream checks and the IPMX RTP checks (the `IPMX` flag, the port
rule, the RTCP port rule) do not apply to it. TR-10-14 section 14 says
the SDP *"shall follow RFC 4145 with the following restrictions"*;
RFC 4145 section 3 requires the `a=setup` attribute, and TR-10-14
section 14 requires its value to be `passive`. The library does not
check `a=setup` on any other block, and it does not reject RTP
attributes on a USB block. Another non-RTP `m=application` block, for
example `TCP/MSRP`, is not subject to the TR-10-14 checks.

| Id | The check rejects | `spec_ref` |
| --- | --- | --- |
| `tr-10-14.usb.setup-required` | A USB transport block with no `a=setup` line. | TR-10-14 §14 (per RFC 4145 §3) |
| `tr-10-14.usb.setup-must-be-passive` | A USB transport block whose `a=setup` value is not `passive`. | TR-10-14 §14 |
| `tr-10-14.a.privacy.usb-protocol-must-be-usb_kv` | An `a=privacy` on a USB transport block whose `protocol` is not `USB_KV`. | TR-10-14 §14 |

---

## Serialization to SDP text

`doc:to_sdp()` renders the doc as RFC 8866 SDP text. The field order
follows RFC 8866 section 5:

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
[a=]*
[m=
  [i=]
  [c=]
  [b=]*
  [a=]*
]*
```

Line endings are CRLF, per the RFC 8866 section 9 ABNF. The serializer
omits every optional field that is `nil`. The `k=` line (RFC 4566
section 5.12) is obsolete in RFC 8866 section 5 and is never emitted.
The parser accepts a `k=` line in its RFC 8866 position and discards
it, so an input with a `k=` line does not round-trip byte for byte.

A decomposed `a=fmtp` parameter list is rendered in its stored order,
with the parameters joined by a semicolon and a space (`; `). ST 2110-20
section 7.1 requires the parameters of a `raw` video `a=fmtp` line to be
*"separated by the semicolon (";") character followed by whitespace"*,
and RFC 8866 section 6.15 says only *"semicolon separated"*, so `; `
conforms at every tier. An input written as `a=1;b=2` is rendered as
`a=1; b=2`. Both forms parse to the same document, so the round-trip
holds, but such an input does not round-trip byte for byte. An `a=fmtp`
body that was not decomposed (kept in the `raw` field) is rendered as
written.

### Serializer and validator separation

`to_sdp()` checks only structural completeness: the fields that
RFC 8866 and the per-attribute grammar mark as required, so that a line
can be rendered. On success it emits the fields as they are. Value-form
correctness, membership in a value set, and cross-section invariants
are checked by `doc:validate()`, not by the serializer. A missing
required field is the only thing `to_sdp()` reports; a present field
with a wrong value is converted to a string and emitted, and the
round trip then fails at `validate()`, which is the signal to the
developer. This separation lets a developer build a doc in steps,
render it at any point to see the structural gaps, and validate it when
the doc is complete.

### Round-trip invariant

Parsing valid text, serializing the doc, and parsing the result again
yields a doc that is deep-equal to the first, and the second
serialization is byte-identical to the first. `spec/roundtrip_spec.lua`
checks this for every fixture in `examples/{generic,st2110,ipmx}/valid/`.
`spec/mutation_spec.lua` checks it for every mutated copy of every
example that still parses. Each copy is checked under the default policy
and with every error-severity check demoted to a warning, because a
demoted parse keeps shapes that a default parse rejects.

### Doc-shape contracts the serializer relies on

`session.time_descriptions` is a list of `{ start, stop, repeats }`
entries, one per `t=` line. Each `repeats` entry needs `interval`,
`duration`, and at least one entry in `offsets`. `session.time_zones`
is a list of `{ adjustment_time, offset }` pairs. A media block needs
`media`, `port`, `proto`, and at least one entry in `fmts`. Every known
compound attribute (`rtpmap`, `fmtp`, `ts-refclk`, `mediaclk`, `group`,
`source-filter`, and the others listed in
[Parsed Table Structure](#parsed-table-structure)) is rendered from its
decomposed fields; there is no fallback to a stored `attr.value` string
for a known name, and a known-name attribute that lacks a required
field makes `to_sdp()` return `nil, err`. Unknown attribute names keep
the `{name, value}` shape and render as `a=<name>` or `a=<name>:<value>`.

The three IPMX attributes (`infoframe`, `hkep`, `privacy`) have
renderers for their decomposed shapes. A document parsed in `"sdp"` or
`"st2110"` mode has those attributes in the generic shape, which holds
only `name` and, for a value attribute, `value`. That shape renders
unchanged, as `a=<name>` or `a=<name>:<value>`. A table with any other
field is treated as decomposed, and a missing required field makes
`to_sdp()` return `nil, err`.

An `a=ts-refclk:ptp=` body that fails the strict form, parsed with
`sdp.a.ts-refclk.ptp-malformed` demoted below error, is
`{source = "ptp", value = <body>}`. It renders as `ptp=<body>`.

A known attribute kept as `{name, malformed = true, value}` (a demoted
`.malformed` check) renders as `a=<name>:<value>`, or as `a=<name>`
when it has no `value`. The renderer does not read any other field of
that table.

---

## Test suite organization

The hermetic test suite (`busted spec/`) has 1438 tests at the time of
writing. The files are organized by what each test exercises: a
standard's clauses, the public library and command-line surface, or an
internal helper.

| File | Group | What it tests |
| --- | --- | --- |
| `spec/grammar_base_spec.lua` | standards | RFC 8866 base SDP: every leaf rule, every soft-syntactic and semantic finding, and the doc shape. Each test cites the clause. |
| `spec/grammar_st2110_spec.lua` | standards | SMPTE ST 2110 overrides and per-block and cross-section checks (parts -10, -20, -21, -22, -30, -31, -40, -41). |
| `spec/grammar_ipmx_spec.lua` | standards | VSF TR-10 / IPMX overrides and per-block and cross-section checks (TR-10-1 through TR-10-14). |
| `spec/grammar_codecs_spec.lua` | standards | The payload-format RFC checks that run at every tier (H.264, RFC 6184; H.265, RFC 7798; AAC, RFC 3640 and RFC 6416; MP2T, RFC 2250) and the `decode_*` helpers. |
| `spec/roundtrip_spec.lua` | standards | Every base and IPMX attribute renderer, and the parse, serialize, and re-parse round trip over `examples/{generic,st2110,ipmx}/valid/*.sdp`. |
| `spec/examples_spec.lua` | standards | Every file under `examples/<tier>/valid/` passes its tier. Every file under `examples/<tier>/invalid/` fails its tier with the check id, line, and full findings list that the spec's `EXPECTED` table records. |
| `spec/mutation_spec.lua` | library API | Properties over mutated copies of every example and fixture. An inserted unparseable line is the reported error. `sdp.parse` never raises. `fail_on_first` does not change the verdict. Every mutant that parses round-trips, under the default policy and with errors demoted. |
| `spec/library_spec.lua` | library API | The public surface: `sdp.parse(text, mode, opts)`, `sdp.new`, `sdp.checks`, `sdp.default_policy`, the accessors, and the doc methods. Policy validation, mode dispatch, and finding access. |
| `spec/cli_spec.lua` | library API | The command-line tool: `validate`, `diagnose`, `to_json`, `to_sdp`, and `checks`; `--mode`, `--pretty`, `--all-findings`, `--help`; exit codes. |
| `spec/grammar_compose_spec.lua` | internal helpers | The composition mechanism: `base.extend` parent and child rule merging, semantic-check inheritance, and distinct grammars per tier. |
| `spec/grammar_addresses_spec.lua` | internal helpers | The IPv4, IPv6, and host-name LPEG patterns in `parse_sdp.grammar.addresses`, with multicast expansion and canonicalization. |
| `spec/grammar_patterns_spec.lua` | internal helpers | The shared numeric value-form patterns in `parse_sdp.grammar.patterns`. |
| `spec/grammar_bitops_spec.lua` | internal helpers | The bitwise helper modules: native operators on Lua 5.3 and later, and the arithmetic implementation on Lua 5.1 and 5.2. |
| `spec/error_registry_spec.lua` | internal helpers | The registry schema, severity resolution, `validate_policy`, `record()`, and the deepest-failure tracker. |
| `spec/errors_spec.lua` | internal helpers | The error formatter and the `errors.new` table shape. |
| `spec/support.lua` | (not a spec) | Shared helpers: `finding_for(ctx, id)` and the `TIMING_*` fixture constants. |

The standards files cover every check that the grammar tier enforces,
and each test names the clause it tests. The library and command-line
files exercise the public surface without asserting against a clause.

### Running the tests

```sh
busted spec/                            # the full hermetic suite
busted spec/grammar_base_spec.lua       # one file
busted spec/library_spec.lua            # the library API tests only
lua spec/check_coverage.lua             # every registered check fires in some spec
```

`spec/check_coverage.lua` runs `busted spec/` with a hook on the
finding recorder and fails when a registered check is never recorded.
Checks that are registered but never emitted are listed in the script.
CI runs it on every push.

### Conformance suite (`spec_conformance/`)

An opt-in suite under `spec_conformance/` downloads pinned AMWA
(Advanced Media Workflow Association) fixtures and parses them. The
README in that directory describes how to run it.
