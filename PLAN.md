# Implementation Plan

## Guiding Principles

- **Test first.** Every milestone begins with failing tests. No implementation starts without a spec.
- **Strict by spec.** RFC 4566 compliance is pedantic and non-negotiable. Reject anything the spec rejects. Do not invent lenient behavior.
- **Layered.** Each validation tier (RFC 4566 → ST 2110 → IPMX) extends the previous; it never replaces it.
- **Tight.** If a file is growing, stop and refactor before continuing. Prefer fewer, well-named things.
- **Fail loudly.** Parse failures report exactly where and why.
- **Round-trip.** `doc:serialize()` must produce output that re-parses to an equivalent table. This is a hard invariant.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.5 |
| Parsing | LPEG |
| JSON | dkjson (pure Lua, single file, LuaRocks) |
| Tests | busted |
| Container | Docker (Lua 5.5 + LuaRocks base image) |

## Test Command

```sh
busted spec/
```

Inside Docker:

```sh
docker compose run test
```

---

## Milestones

Each milestone: write tests → confirm they fail → implement → confirm they pass → update docs → commit.

---

### M1 — Scaffolding ✓

**Done when:** `busted spec/` runs and one smoke test passes.

- [x] Directory layout: `lib/`, `spec/`, `spec/fixtures/`
- [x] `.busted` config
- [x] `Dockerfile` and `docker-compose.yml`
- [x] `parse_sdp.lua` stub: exports `parse` (returns `nil, {message="not implemented"}`) and `new`
- [x] `spec/sdp_spec.lua`: one test — `require("parse_sdp")` loads without error

---

### M2 — Line tokenizer ✓

**Done when:** LPEG can tokenize any SDP line and record its position.

- [x] `lib/grammar.lua`: pattern matching `<alpha>=<value><CRLF|LF>`
- [x] Captures: type character, value string, byte offset of value start
- [x] Rejects lines that don't match (returns nil + position of failure)
- [x] Tests: valid lines, LF-only lines, malformed lines, empty input

---

### M3 — Required session fields ✓

**Done when:** `sdp.parse` returns a doc table for minimal valid SDP; returns `nil, err` for anything invalid.

Covers: `v=`, `o=`, `s=`, `t=` in required order.

- [x] `lib/grammar.lua`: patterns for each field value format
- [x] `parse_sdp.lua`: `parse(text)` wires tokenizer → field parsers → table
- [x] Error table shape: `{ message, line, col, context }`
- [x] Tests:
  - Minimal valid SDP (`v o s t`) → doc table
  - Missing `v=` → error at line 1
  - Wrong order (e.g. `s=` before `o=`) → error with correct position
  - Bad `o=` format (wrong field count) → error

---

### M4 — Optional session fields ✓

**Done when:** All optional session-level fields parse correctly.

Covers: `i=`, `u=`, `e=`, `p=`, `c=`, `b=`, `a=` (zero or more of each where allowed).

- [x] Tests:
  - SDP with every optional field present → correct table
  - Multiple `e=`, `p=`, `b=`, `a=` → arrays in correct order
  - `c=` with IPv4 and IPv6 addresses
  - `b=` with `AS:`, `CT:`, `X-` prefixes
- [ ] Tests (rejection — grammar already enforces these, tests would immediately pass):
  - `c=OUT IP4 127.0.0.1` → rejected (bad nettype)
  - `c=IN IP9 127.0.0.1` → rejected (bad addrtype)

---

### M5 — Media blocks ✓

**Done when:** `sdp.parse` handles one or more `m=` blocks with their per-media fields.

- [x] `m=` line: type, port, `/count`, proto, format list
- [x] Per-media: `i=`, `c=`, `b=`, `a=` (same rules as session level)
- [x] Multiple media blocks in sequence
- [x] Tests:
  - One video `m=` block with attributes
  - Two media blocks (video + audio)
  - `m=` with port count (`/2`)
  - Missing required `m=` field → error
- [ ] Tests (rejection — same grammar as session-level `c=`, would immediately pass):
  - Per-media `c=` with bad nettype → rejected
  - Per-media `c=` with bad addrtype → rejected

---

### M6 — doc object ✓

**Done when:** `sdp.parse` returns a table with working methods; `sdp.new` wraps any table.

- [x] Metatable on the table returned by `parse`
- [x] `sdp.new(table)` attaches same metatable, no validation
- [x] `doc:is_sdp()` → runs RFC 4566 validate, returns bool
- [x] `doc:validate()` and `doc:validate("sdp")` → `true` or `nil, err`
- [x] Tests:
  - Parsed doc has methods
  - `sdp.new({})` has methods
  - `doc:is_sdp()` true for valid, false for mutated-invalid
  - `doc:validate()` error table has expected fields

---

### M7 — Serializer ✓

**Done when:** `doc:serialize()` produces strict RFC 4566 SDP text; round-trip holds.

- [x] `lib/serialize.lua`: field output in RFC 4566 §5 order
- [x] CRLF line endings
- [x] `doc:serialize()` method
- [x] Tests:
  - Serialized output re-parses without error
  - Field order matches spec (`v o s i u e p c b t a m ...`)
  - Round-trip: `parse(serialize(parse(text)))` equals `parse(text)` (deep equal)

---

### M8 — ST 2110 validation ✓

**Done when:** `sdp.parse(text, "st2110")` and `doc:validate("st2110")` work correctly, including value format checks.

- [x] `lib/st2110.lua`: validates required attributes on parsed doc
- [x] `doc:is_st2110()` → bool
- [x] Presence checks:
  - At least one `m=` block
  - `a=ts-refclk` present (session or per-media)
  - `a=mediaclk` present (per-media)
  - `a=rtpmap` present (per-media); clock rate = 90000 for video
  - `a=fmtp` present (per-media); `sampling` required for video, `channel-order` required for audio
- [x] Value format checks (presence is necessary but not sufficient):
  - `a=ts-refclk` value must be a recognized clock source; PTP is not required — all of these are valid:
    - `ptp=<version>:<gmid>[:<domain>]` where GMID is 8 hex octets (`HH-HH-HH-HH-HH-HH-HH-HH`)
    - `localmac=<mac>` where MAC is 6 hex octets (`HH-HH-HH-HH-HH-HH`)
    - `gps`, `gal`, `glonass` (bare tokens)
    - `ntp=<address>` (non-empty address)
    - Any unrecognized format → error
  - `a=mediaclk` value must be `direct=<integer>` or `sender`; any other value → error
- [x] Tests (presence and media-type logic):
  - Valid ST 2110-20 (video) SDP → success
  - Valid ST 2110-30 (audio) SDP → success
  - Missing `a=ts-refclk` → error with `field_path` and `spec_ref`
  - Invalid `fmtp` (missing `sampling`) → error
  - Generic valid SDP fails ST 2110 validate
  - `localmac=` ts-refclk accepted (PTP not required)
- [x] Tests (value format):
  - `a=ts-refclk:garbage` → error
  - `a=ts-refclk:ptp=IEEE1588-2008` (no GMID) → error
  - `a=ts-refclk:localmac=GG-BB-CC-DD-EE-FF` (non-hex octet) → error
  - `a=ts-refclk:localmac=AA-BB-CC` (wrong octet count) → error
  - `a=mediaclk:garbage` → error
  - `a=mediaclk:direct=notanumber` → error

---

### M9 — IPMX validation ✓

**Done when:** `sdp.parse(text, "ipmx")` and `doc:validate("ipmx")` work correctly.

- [x] `lib/ipmx.lua`: validates IPMX-specific attributes (runs ST 2110 first)
- [x] `doc:is_ipmx()` → bool
- [x] Note: PTP is **optional** in IPMX. `a=ts-refclk` presence is inherited from ST 2110 validation, but the clock source value (`ptp=`, `localmac=`, etc.) is never required to be PTP at either tier.
- [x] Required checks (IPMX-specific, beyond ST 2110):
  - `a=extmap` present with at least one extension URI
- [x] Tests:
  - Valid IPMX SDP → success
  - ST 2110 SDP (non-IPMX) fails IPMX validate
  - Missing IPMX `a=extmap` → error

---

### M10 — JSON output ✓

**Done when:** `doc:to_json()` returns a valid JSON string.

- [x] Wire dkjson in `parse_sdp.lua`
- [x] `doc:to_json()` method
- [x] `doc:to_sdp()` alias for `serialize` (symmetric pair with `to_json`)
- [x] Tests:
  - `to_json()` output is valid JSON (parse it back)
  - All doc fields present in JSON output
  - `to_sdp()` returns same output as `serialize`

---

### M11 — CLI: `parse` subcommand ✓

**Done when:** `parse_sdp parse [--mode MODE] [--pretty] [file]` works end-to-end.

- [x] `cli.lua`: argument parsing, stdin fallback, exit codes
- [x] JSON to stdout on success; JSON error to stderr on failure
- [x] Exit `0` success, `1` parse error
- [x] Integration tests (via `io.popen`)

---

### M12 — CLI: `serialize` subcommand ✓

**Done when:** `parse_sdp serialize [file.json]` produces valid SDP on stdout.

- [x] Read JSON, call `sdp.new()`, call `doc:to_sdp()`
- [x] Integration tests

---

### M13 — Error UX ✓

**Done when:** Every error message is actionable without reading the spec.

- [x] Caret display: offending line + `^` at column
- [x] ST 2110 / IPMX errors include spec clause (`ST 2110-20 §7.2`)
- [x] Consistent error codes (`MISSING_FIELD`, `INVALID_VALUE`, `WRONG_ORDER`, `MALFORMED_LINE`)
- [x] Review all existing error messages for clarity

---

### M14 — ST 2110-40/41: ancillary data and fast metadata ✓

**Done when:** ST 2110-40 ancillary data flows and ST 2110-41 fast metadata flows validate
correctly at the ST 2110 tier (and therefore at the IPMX tier).

ST 2110-40 maps SMPTE ST 291-1 ancillary packets (captions, timecodes, VBI) to RTP using
encoding name `smpte291` at 90 kHz (RFC 8331). ST 2110-41 carries fast metadata (subtitles,
ad-insertion cues) using encoding name `ST2110-41/<rate>`.

**New checks in `st2110.st2110`:**

When the rtpmap encoding name is `smpte291` (ST 2110-40):

- Clock rate must be 90000.
- `fmtp` must include at least one `DID_SDID={0xHH,0xHH}` entry; each octet must be exactly
  two hex digits.
- `VPID_Code=<decimal>` is optional and accepted.

When the rtpmap encoding name is `ST2110-41` (ST 2110-41):

- `fmtp` must contain `SSN=ST2110-41:...`.
- `fmtp` must contain at least one `DIT=<hex-list>` entry.

- [x] `rtpmap_encoding` helper extracts encoding name from rtpmap value
- [x] `valid_did_sdid` helper validates `{0xHH,0xHH}` format
- [x] `st2110.st2110` dispatches on encoding name before media type:
  - `smpte291` → ST 2110-40 checks (clock rate 90000, DID_SDID presence + format)
  - `ST2110-41` → ST 2110-41 checks (SSN presence, DIT presence)
  - `m.media == "video"` → existing ST 2110-20 checks
  - `m.media == "audio"` → existing ST 2110-30 checks
- [x] Tests (6 new in `spec/st2110_spec.lua`):
  - Valid ST 2110-40 SDP (`smpte291/90000`, `DID_SDID={0x61,0x02}`) → success
  - ST 2110-40 fmtp missing `DID_SDID` → `nil, err` matching `"DID_SDID"`
  - ST 2110-40 `DID_SDID` with non-hex octet → `nil, err`
  - Valid ST 2110-41 SDP (`ST2110-41/90000`, `SSN=ST2110-41:2024; DIT=100`) → success
  - ST 2110-41 fmtp missing `SSN` → `nil, err` matching `"SSN"`
  - ST 2110-41 fmtp missing `DIT` → `nil, err` matching `"DIT"`
- [x] 4 new example fixtures (2 valid, 2 invalid)
- [x] `GUIDE.md` updated with ST 2110-40 and ST 2110-41 fmtp tables

**Spec references:**

- RFC 8331: RTP Payload for SMPTE ST 291-1 Ancillary Data
- SMPTE ST 2110-40:2023
- SMPTE ST 2110-41:2024

---

### M15 — IPMX protocol extensions: HKEP, PEP, USB, FEC ✓

**Done when:** When HKEP, PEP, USB, and FEC extensions are present in an IPMX SDP, their
representation is validated; malformed or inconsistent usage is rejected. Absence of any
of these extensions is not an error.

| Extension | Spec | SDP presence indicator |
| --- | --- | --- |
| HDCP Key Exchange (HKEP) | VSF TR-10-5 | `a=hkep` attribute |
| Privacy Encryption Protocol (PEP) | VSF TR-10-13 | `a=privacy` attribute |
| USB transport | VSF TR-10-14 | `m=application … TCP …` |
| FEC (TR-10-6) | VSF TR-10-6 | `FECPROFILE` in `a=fmtp` |

**Completed checks in `ipmx.ipmx`:**

- [x] IPMX fmtp marker: every non-USB block's `a=fmtp` must contain bare `IPMX` flag (TR-10-1 §10.1)
- [x] `a=hkep`: if present, validates `<port> IN <addrtype> <addr> <node-id> <port-id>` format (TR-10-5 §10)
- [x] `a=privacy`: if present, validates all 6 required parameters; 12 valid modes for RTP, 4 AAD-only modes for USB blocks (TR-10-13 §13, TR-10-14 §12)
- [x] USB blocks (`m=application` + TCP): bypass ST 2110 media-block validation (TR-10-14)
- [x] `FECPROFILE` in fmtp: must be `profile-a`; `FEC_ADD_LATENCY_VIDEO`/`_AUDIO` must be non-negative integers (TR-10-6 §7.6)
- [x] HKEP and PEP are NOT mutually exclusive — both may appear in the same session
- [x] 26 new tests added to `spec/ipmx_spec.lua`

**Notes from spec review:**

- The SDP attribute is `a=privacy` (not `a=pep`); the protocol name is PEP (Privacy Encryption Protocol)
- TR-10-6 FEC uses port offsets (main+2 column, main+4 row) — no separate repair `m=` blocks
- USB session-level `a=extmap` satisfies the IPMX extmap requirement; no per-block extmap needed

**Spec references:**

- VSF TR-10-5 (2026-02-17 v2): IPMX HDCP Key Exchange Protocol
- VSF TR-10-13 (2026-02-17 v2): IPMX Privacy Encryption Protocol
- VSF TR-10-14 (2026-04-07): IPMX USB transport — AMWA BCP-007-02
- VSF TR-10-6 (2023-08-07): IPMX Forward Error Correction
- VSF TR-10-1 (2024-02-23): IPMX core system requirements

---

### M16 — ST 2022-7 redundancy grouping ✓

**Done when:** When `a=group:DUP` is present in an IPMX or ST 2110 SDP, the grouping
semantics are validated; each referenced `mid` resolves to an existing media block;
both redundant legs are individually valid; IPMX PEP consistency is enforced.

**Background:** SMPTE ST 2022-7 provides seamless protection switching between two
identical RTP streams transmitted over separate network paths. In SDP it is signaled
with `a=group:DUP <primary-mid> <secondary-mid>` at session level (RFC 7104).
Each leg is a full media block with `a=mid:<id>`.

**New checks in `st2110.st2110` and `ipmx.ipmx`:**

- `a=group:DUP <mid1> <mid2>` at session level:
  - Both mids must correspond to a media block carrying `a=mid` matching that value.
  - The two blocks must have the same media type (`video`, `audio`, `application`, etc.).
  - For ST 2110 mode: each leg individually passes all ST 2110 per-block checks.
- IPMX-specific:
  - If `a=privacy` is present on either leg, both legs must carry **identical**
    `a=privacy` parameter values (TR-10-13 §13, lines 329/335). Different values on
    the two legs is a SHALL violation.
  - Both legs count toward the `a=extmap` check (presence on either leg satisfies
    the IPMX requirement).
  - DUP-grouped blocks are identified before the ST 2110 loop so the loop can
    validate them as a pair rather than independently on the extmap/privacy checks.
- Absence of `a=group:DUP` is not an error at any tier.

**SDP attribute format (RFC 7104):**

```text
a=group:DUP <mid1> <mid2>
a=mid:<id>           (per media block)
```

**Open questions — resolved:**

1. ST 2110-10 §8.5 explicitly mandates `a=group:DUP` + RFC 7104 semantics; format from RFC 7104.
2. Different ports are explicitly allowed — ST 2022-7 defines copies as potentially having "a different IP destination or port"; ST 2110-10 §8.5 only requires separate source or destination address, not equal ports.
3. More than two legs allowed by RFC 7104 and not restricted by ST 2022-7 ("at least two streams") or ST 2110-10; no enforcement added.

**Implemented:**

- [x] `a=group:DUP` at session level: all named mids resolve to media blocks with `a=mid`
- [x] All DUP legs must share the same media type
- [x] IPMX: `a=privacy` values must be identical (or identically absent) across all DUP legs
- [x] `a=extmap` on either DUP leg satisfies IPMX requirement (existing loop already handles this)
- [x] 5 new tests in `spec/st2110_spec.lua`, 6 new tests in `spec/ipmx_spec.lua`
- [x] 4 example fixtures (2 ST 2110, 2 IPMX)

**Spec references:**

- SMPTE ST 2022-7:2019 — Seamless Protection Switching of RTP Datagrams
- RFC 7104 — Duplication Grouping Semantics in SDP
- RFC 5888 — The SDP Grouping Framework (`a=group`, `a=mid`)
- VSF TR-10-13 (2026-02-17 v2) §13 lines 329/335 — PEP leg consistency

---

### M17 — RTCP port convention ✓

**Done when:** When `a=rtcp` or `a=rtcp-mux` appears in an IPMX SDP, it is
validated against the port convention mandated by TR-10-1 §8.7.

**Background:** IPMX mandates RTCP Sender Reports on the destination port equal to the
media port + 1 (TR-10-1 §8.7: "shall be sent to the UDP destination port that
corresponds to +1 from the port used by their corresponding media payload"). This
makes `a=rtcp-mux` (which puts RTCP on the same port as RTP) a violation, and
any `a=rtcp:<port>` that specifies a different offset also a violation.
In practice most ST 2110/IPMX SDPs omit `a=rtcp` entirely (using the implicit
RFC 3550 default), so these are error-on-presence checks.

**Open questions — resolved:**

1. ST 2110-10 §6.2 is silent on `a=rtcp-mux` — RTCP is optional ("may be used"). No prohibition at ST 2110 tier. Checks belong in `ipmx.ipmx` only.
2. `a=rtcp-rsize` not mentioned in any ST 2110/IPMX spec — treated as opaque, no check.
3. `a=rtcp-fb` not mentioned either — treated as opaque, no check.

**Implemented:**

- [x] `a=rtcp-mux` on any RTP media block → rejected in `ipmx.ipmx` (TR-10-1 §8.7)
- [x] `a=rtcp:<port>` on a media block → port must equal media port + 1
- [x] `IN <addrtype> <addr>` suffix accepted but not validated
- [x] ST 2110 mode: no restriction (tested)
- [x] 6 new tests in `spec/ipmx_spec.lua`; 1 example fixture `examples/ipmx/invalid/rtcp_mux.sdp`

**SDP attribute formats (RFC 3605):**

```text
a=rtcp:<port>
a=rtcp:<port> IN IP4 <unicast-address>
a=rtcp:<port> IN IP6 <unicast-address>
a=rtcp-mux
```

**Spec references:**

- VSF TR-10-1 (2024-02-23) §8.7 — RTCP Sender Report General Provision (lines 278–284)
- SMPTE ST 2110-10 §6.2 — RTP (confirms RTCP is optional; no rtcp-mux restriction)
- RFC 3605 — Real-Time Transport Control Protocol (RTCP) attribute in SDP
- RFC 5761 — Multiplexing RTP Data and Control Packets (`a=rtcp-mux`)

---

### M18 — ST 2110-20/30 fmtp value validation ✓

**Done when:** All ST 2110-20 §7.2 required `fmtp` parameters are validated for both
presence and value format. ST 2110-30 `channel-order` is validated for value format.
`GUIDE.md` updated to mark each field as validated.

**Background:** M8 added presence checks for `sampling` (video) and `channel-order`
(audio). ST 2110-20 §7.2 requires eight additional parameters (`width`, `height`,
`exactframerate`, `depth`, `TCS`, `colorimetry`, `PM`, `SSN`), none of which are
currently checked. The `sampling` and `channel-order` values are also accepted without
format validation, meaning syntactically garbage values pass today.

**ST 2110-20 validation tasks:**

- [x] `sampling` — reject if not one of the enumerated values from ST 2110-20 §7.2:
  `YCbCr-4:4:4`, `YCbCr-4:2:2`, `YCbCr-4:2:0`, `CLYCbCr-4:4:4`, `CLYCbCr-4:2:2`,
  `CLYCbCr-4:2:0`, `ICtCp-4:4:4`, `ICtCp-4:2:2`, `ICtCp-4:2:0`, `RGB`, `XYZ`, `KEY`
- [x] `width` — required; must be a positive integer
- [x] `height` — required; must be a positive integer
- [x] `exactframerate` — required; must be a positive integer or `<int>/<int>` fraction
- [x] `depth` — required; must be a positive integer
- [x] `TCS` — required; must be one of the enumerated values from ST 2110-20 §7.2:
  `SDR`, `PQ`, `HLG`, `LINEAR`, `BT2100LINPQ`, `BT2100LINHLG`, `ST2065-1`, `ST428-1`, `DENSITY`
- [x] `colorimetry` — required; must be one of the enumerated values from ST 2110-20 §7.2:
  `BT601`, `BT709`, `BT2020`, `BT2100`, `ST2065-1`, `ST2065-3`, `UNSPECIFIED`, `ALPHA`
- [x] `PM` — required; must be `2110GPM` or `2110BPM`
- [x] `SSN` — required; must match `ST2110-20:<year>` (starts with `ST2110-20:`)

**ST 2110-30 validation tasks:**

- [x] `channel-order` — must match the SMPTE 2110-30 §7 format:
  `SMPTE2110.(<group>)` where `<group>` is a non-empty token

**Tests to add (spec/st2110_spec.lua):**

- Valid ST 2110-20 SDP with all required fmtp fields → success (update existing fixture)
- Each of the 9 required fields missing individually → error naming the missing field
- `sampling` with an invalid value (e.g., `garbage`) → error
- `width` with a non-integer value → error
- `height` with a non-integer value → error
- `exactframerate` with an invalid format → error
- `depth` with a non-integer value → error
- `TCS` with an invalid value → error
- `colorimetry` with an invalid value → error
- `PM` with an invalid value → error
- `SSN` with wrong prefix → error
- Valid ST 2110-30 SDP with valid `channel-order` → success
- `channel-order` with an invalid format → error

**Spec references:**

- SMPTE ST 2110-20:2022 §7.2 — Required fmtp parameters for video
- SMPTE ST 2110-30:2020 §7 — Required fmtp parameters for audio

---

### M19 — Optional fmtp param validation and audio encoding name ✓

**Done when:** All ST 2110-20 optional `fmtp` parameters with defined value formats are
validated when present. ST 2110-30 rtpmap encoding name is validated. ST 2110-40
`VPID_Code` and ST 2110-41 `DIT` value formats are validated.

- [x] ST 2110-20 optional `fmtp` params: `TP` (`2110TPN`/`2110TPNL`/`2110TPW`), `MAXUDP`
  (positive integer), `PAR` (`W:H` with positive integers), `TROFF` (non-negative integer),
  `CMAX` (positive integer) — validated when present; absent is fine
- [x] ST 2110-20 bare-flag params `interlace` and `segmented` — accepted without value check
- [x] ST 2110-30 `a=rtpmap` encoding name validated: must be `L16`, `L24`, or `AM824`
- [x] ST 2110-40 `VPID_Code` — optional; validated as non-negative integer when present
- [x] ST 2110-41 `DIT` — required; value validated as non-negative integer (was presence-only)
- [x] `GUIDE.md` updated; inaccurate "audio clock rate is not validated" corrected

**Tests added (spec/st2110_spec.lua):**

- TP: accepts all three valid values; rejects unknown value; absent OK
- MAXUDP: accepts valid integer; rejects non-integer; absent OK
- PAR: accepts `1:1` and `16:15`; rejects wrong format and zero dimension; absent OK
- TROFF: accepts `0` and positive value; rejects non-integer; absent OK
- CMAX: accepts valid integer; rejects non-integer; absent OK
- `interlace`, `segmented`: accepted as bare flags; both together accepted
- ST 2110-30 encoding: accepts L16, L24, AM824; rejects OPUS and AAC
- ST 2110-40 VPID_Code: accepts integer and zero; rejects non-integer and negative
- ST 2110-41 DIT: accepts 0 and 100; rejects non-integer, decimal, and empty value

---

### M21 — Validation gap closure (audit 2026-05-13 follow-up)

**Done when:** All gaps identified in the M20 post-commit audit are addressed.

**New validation:**

- [x] `a=group:DUP` must have at least 2 legs; single-leg DUP groups are now rejected (ST 2110-10 §8.5)
- [x] `a=hkep` format validated at media block level, not only session level (TR-10-5 §10)
- [x] `c=` connection address validated for ST 2110 media blocks: IPv4 multicast requires TTL; forbidden ranges 224.0.0.0/24 and 224.0.1.0/24 rejected; unicast must not carry TTL (ST 2110-10 §6.5 / RFC 5771)
- [x] `a=extmap` URI format validated per RFC 5285: `entry-count[/direction] URI`; invalid direction or missing URI scheme rejected (IPMX §6)

**Test gap coverage:**

- [x] `exactframerate=0`, `width=0`, `height=0`, `depth=0` rejected (positive int required)
- [x] `MAXUDP=0` rejected
- [x] `PAR=1:0` (zero denominator) rejected; renamed existing `PAR=0:1` test for clarity
- [x] `FEC_ADD_LATENCY_VIDEO=0` and `FEC_ADD_LATENCY_AUDIO=0` accepted (non-negative integer)
- [x] Empty `iv=` value in `a=privacy` rejected
- [x] Session-level-only `ts-refclk` (no per-media attribute) accepted
- [x] `---@diagnostic disable` added to all spec files (suppresses busted false positives)

---

### M20 — Validation gaps closed (audit 2026-05-13)

**Done when:** All gaps identified in the M19 post-commit audit are addressed: new validation
added for ST 2110-30 channel count, `a=ptime` format, rtpmap/fmtp PT consistency, and
`FEC_ADD_LATENCY_*`/`FECPROFILE` dependency; missing tests added for previously validated
but untested code paths.

**New validation in `st2110.validate`:**

- [x] `a=rtpmap` PT must match `a=fmtp` PT (applies to all media types; ST 2110-10 §7)
- [x] ST 2110-30 audio: channel count field required in rtpmap (`encoding/rate/channels`);
  must be an integer 1–16 per ST 2110-30 §7.1
- [x] ST 2110-30 audio: `a=ptime` — if present, value must be a positive number per
  RFC 4566 / ST 2110-30 §7.2 (absence is fine; recommendation of 1 ms is not enforced)

**New validation in `ipmx.validate`:**

- [x] `FEC_ADD_LATENCY_VIDEO` and `FEC_ADD_LATENCY_AUDIO` require `FECPROFILE` to also be
  present (TR-10-6 §7.6); latency params are meaningless without a FEC profile

**Additional validation in `valid_tsrefclk`:**

- [x] `ntp=` address: LPEG pattern validates that the address is a well-formed IPv4 address
  (`N.N.N.N`, each octet 0–255), an IPv6 address (full RFC 4291 / RFC 3986 §3.2.2 grammar,
  adapted from lpeg_patterns MIT © daurnimator), or an RFC 1123 hostname (dot-separated
  labels of alphanumeric/hyphen characters); plainly malformed values are rejected

**New tests in `spec/st2110_spec.lua`:**

- rtpmap PT ≠ fmtp PT → error
- ST 2110-30 channel count: valid (1, 8, 16); missing → error; out-of-range (0, 17) → error
- `a=ptime`: valid integer → accepted; invalid (non-numeric, zero) → error; absent → accepted
- `CMAX=0` → error (positive int required)
- PTP GMID with wrong octet count (e.g. 6 instead of 8) → error
- `ntp=` with valid IPv4 → accepted
- `ntp=` with valid hostname → accepted
- `ntp=` with valid IPv6 address → accepted
- `ntp=` with empty value → error
- `ntp=` with malformed token (no dots, not hex+colon) → error

**New tests in `spec/ipmx_spec.lua`:**

- `a=privacy` with `protocol=RTP_KV` → accepted
- `a=privacy` non-hex `key_generator` → error
- `a=privacy` non-hex `key_version` → error
- `a=privacy` non-hex `key_id` → error
- `FEC_ADD_LATENCY_AUDIO=notanumber` → error
- `FEC_ADD_LATENCY_VIDEO` without `FECPROFILE` → error
- `FEC_ADD_LATENCY_AUDIO` without `FECPROFILE` → error

---

### M23 — Validation completeness audit (gap closure 2026-05-13, round 2)

**Done when:** All gaps identified in the sixth round of spec/code audit are addressed.
Sources: direct spec reads of TR-10-1 §10, ST 2110-10 §6.3/§7.2/§8.2, RFC 5285 §3/§4.2.

---

#### Gap 1 — `a=group:FID` not rejected at IPMX tier (TR-10-1 §10)

**Source:** TR-10-1 §10: "Flow Identification (FID) semantics as defined in RFC 5888 shall not
be used under this TR." Any IPMX SDP carrying `a=group:FID` at session level must be rejected.
The ST 2110 tier has no such rule. This is IPMX-only.

- [x] Scan `doc.session.attributes` in `ipmx.validate` for any `a=group:` with value beginning `FID`
- [x] Test: IPMX SDP with `a=group:FID mid1 mid2` → rejected with spec_ref `TR-10-1 §10`
- [x] Test: IPMX SDP with `a=group:DUP mid1 mid2` → still accepted
- [x] Test: ST 2110 SDP with `a=group:FID` → accepted (rule is IPMX-only)

---

#### Gap 2 — Session-level `c=` not validated (ST 2110-10 §6.5)

**Source:** `valid_connection_address` is called for per-media `c=` but never for `doc.session.connection`.
A session-level `c=IN IP4 224.0.0.1` (forbidden range) passes ST 2110 validation today.

- [x] In `st2110.validate`, after `local sess_attrs = ...`, add `valid_connection_address` check for `doc.session.connection` when present
- [x] Test: session-level `c=IN IP4 224.0.0.1` (forbidden 224.0.0.0/24) → rejected
- [x] Test: session-level `c=IN IP4 239.100.0.1/64` (valid multicast) → accepted
- [x] Test: session-level `c=IN IP4 192.168.1.1` with TTL suffix → rejected (unicast must not carry TTL)

---

#### Gap 3 — Only first `a=ts-refclk` validated; subsequent entries skipped (ST 2110-10 §8.2)

**Source:** `find_attr` returns the first matching attribute. If multiple `a=ts-refclk` attrs are
present (session or media level), only the first is validated. ST 2110-10 §8.2 allows multiple
ts-refclk sources; each must be individually valid.

- [x] Replace `find_attr` ts-refclk lookup + single `valid_tsrefclk` call with a loop over all
  ts-refclk attrs from both session and media level
- [x] Test: two valid ts-refclk attrs → accepted
- [x] Test: first ts-refclk valid, second invalid → rejected
- [x] Test: first ts-refclk absent but second present and valid → accepted (order shouldn't matter)

---

#### Gap 4 — `a=extmap` ID uniqueness not enforced (RFC 5285 §3)

**Source:** RFC 5285 §3: "The ID in an extmap attribute MUST be unique within the SDP per level."
Two `a=extmap:1 ...` lines at session level (or within the same media block) must be rejected.
The existing `valid_extmap` only checks format and range; no cross-attribute uniqueness check.

- [x] In `ipmx.validate`, after the per-attribute format checks, scan for duplicate IDs at session scope and per media-block scope separately
- [x] Test: two `a=extmap:1 ...` at session level → rejected with spec_ref `RFC 5285 §3`
- [x] Test: two `a=extmap:1 ...` in the same media block → rejected
- [x] Test: `a=extmap:1 ...` at session level and `a=extmap:1 ...` in media block → accepted (different levels)

---

#### Gap 5 — Missing media-level `c=` not detected when no session-level `c=` (ST 2110-10 §6.3)

**Source:** ST 2110-10 §6.3: a connection address must be present — either at session level or
at media level. If neither is present, the validator silently passes today.

- [x] In the per-media loop in `st2110.validate`, after the per-media `c=` check, reject if `m.connection == nil` AND `doc.session.connection == nil`
- [x] Test: no session `c=` and no media `c=` → rejected
- [x] Test: session-level `c=` present, no media `c=` → accepted
- [x] Test: media-level `c=` present, no session `c=` → accepted (existing behavior)

---

#### Gap 6 — IPMX audio `a=ptime:0` and `a=ptime:-1` not tested

**Source:** IPMX requires `a=ptime` to be present (TR-10-3 §8) and the ST 2110 tier requires
a positive value. Both cases already return errors via the ST 2110 tier when ptime=0 or ptime=-1
is present, but no IPMX-level tests cover these values.

- [x] Test: IPMX audio with `a=ptime:0` → rejected (ST 2110 tier rejects non-positive)
- [x] Test: IPMX audio with `a=ptime:-1` → rejected

---

**Spec references for M23:**

- VSF TR-10-1 (2024-02-23) §10 — FID semantics forbidden
- SMPTE ST 2110-10 §6.3 — connection address required at session or media level
- SMPTE ST 2110-10 §6.5 — multicast TTL, forbidden ranges
- SMPTE ST 2110-10 §8.2 — multiple ts-refclk sources allowed; each individually valid
- RFC 5285 §3 — extmap ID must be unique per level

---

### M31 — Opinion audit + citation cleanup ✓ (audit 2026-05-14, round 10)

**Done when:** A systematic audit of every validation check in `parse_sdp.lua` against the M30 conformance principle is complete, and the surfaced findings are addressed. The audit classified each of ~140 checks as GROUNDED, WELL-FORMEDNESS, GROUNDED-MISCITED, OPINION, or UNCLEAR. Opinion-tagged checks were deleted with their negative tests; miscited grounded checks were re-cited; one structural gap exposed by the deletions was closed.

The audit also confirmed two cases where pre-flagged "OPINION" candidates from the M30 punch list turned out to be GROUNDED on closer reading of the spec text:

- **IANA multicast 224.0.0.0/24 and 224.0.1.0/24 rejection** (parse_sdp.lua:753-756) — kept. ST 2110-10:2022 §6.5 explicit "shall not": *"Senders shall not transmit media signals on IPv4 multicast addresses within the 'Local Network Control Block' nor the 'Internetwork Control Block' specified in IETF RFC 5771."*

#### Opinion deletion

- [x] **Unconditional `a=extmap` presence requirement** ([parse_sdp.lua:1940-1955](parse_sdp.lua#L1940-L1955) — pre-M31 lines). Previously cited "IPMX §6" which doesn't exist in any IPMX profile or TR-10 doc. `a=extmap` is mentioned normatively only in TR-10-13 §1.1.1, and only when declaring RTP Extension Headers for PEP (privacy). No other spec mandates extmap presence. Deleted; replaced with a comment explaining why. The URI format and PEP-direction checks ([parse_sdp.lua:1957-2037](parse_sdp.lua#L1957-L2037)) are kept — those are RFC 5285 well-formedness and TR-10-13 §20.1 grounded.

#### Structural gap closed (consequence of the opinion deletion)

- [x] **IPMX requires at least one media block** ([parse_sdp.lua:1768-1772](parse_sdp.lua#L1768-L1772)). Cite: ST 2110-10 §7. The IPMX validator already filters RTP-relevant media and routes the SDP through `validate.sdp` (RFC 4566) when there are no RTP media (used for USB-only SDPs under TR-10-14). With the old extmap check gone, an SDP with zero media blocks total now took that fallback path and passed silently. IPMX is built on ST 2110-10 §7/§8.1's SDP-for-media-streams premise, so an empty SDP isn't describing any IPMX stream; the ST 2110 validator already rejects this and IPMX now mirrors the check at the top of `ipmx.validate`.

#### Citation cleanup (grounded-miscited)

- [x] **IPMX port even and > 1024** ([parse_sdp.lua:2178-2191](parse_sdp.lua#L2178-L2191)). Cite was "TR-10-1 §7" but that clause is **not in TR-10-1**. It appears verbatim across every per-essence TR-10: TR-10-2 §7 (uncompressed video), TR-10-3 §7 (PCM audio), TR-10-4 §7 (ANC), TR-10-11 §7 (JPEG-XS CBR), TR-10-12 §7 (AES3). Re-cited to "TR-10-2 §7" as the canonical reference; comment notes the wording is identical across the per-essence TR-10 suite. Matching test (`spec_ref is TR-10-1 §7`) was renamed and updated.
- [x] **`a=rtcp-mux` rejection cite** ([parse_sdp.lua:2200-2203](parse_sdp.lua#L2200-L2203)). Cite was "TR-10-1 §8.7" alone. The rejection is GROUNDED but via derivation: TR-10-1 §8.7 mandates RTCP on port+1 ("RTCP Sender Report packets shall be sent to the UDP destination port that corresponds to +1 from the port used by their corresponding media payload"); RFC 5761 defines `a=rtcp-mux` as RTP/RTCP sharing the same port. The two are mutually exclusive. Re-cited to "TR-10-1 §8.7 + RFC 5761" to make the derivation explicit. Matching test updated.
- [x] **`a=extmap` format/ID validation cite** ([parse_sdp.lua:1947-1996](parse_sdp.lua#L1947-L1996)). Cite was "IPMX §6 / RFC 5285" — dropped the phantom "IPMX §6", kept just "RFC 5285".

#### Audit findings deliberately not changed

- **`c=` multicast 224.0.0.0/24 / 224.0.1.0/24 rejection** ([parse_sdp.lua:753-756](parse_sdp.lua#L753-L756)). Confirmed GROUNDED in ST 2110-10:2022 §6.5 explicit "shall not". The M30 punch list pre-flagged this as a potential opinion; the audit corrected.
- **Audio packet RTP payload fit math** ([parse_sdp.lua:1374-1389](parse_sdp.lua#L1374-L1389)). The audit suggested re-citing to add RFC 3550 §2 (12-byte RTP header) alongside ST 2110-10 §6.4 (MAXUDP). Skipped — the current cite is sufficient for the user-visible error context; expanding it offered marginal benefit at the cost of test churn.
- **Audio `a=ptime` value validation** ([parse_sdp.lua:1369-1377](parse_sdp.lua#L1369-L1377)). Cite "ST 2110-30 §7.2" is fine — that section is where ptime applies. The check (positive number when present) is well-formedness; the cite points to where the attribute is described.

#### Test changes

- [x] `spec/ipmx_spec.lua`: three "missing extmap" tests renamed to test the actual failure mode (missing IPMX fmtp marker, per TR-10-1 §10.1, since the M30 fixture lacks both).
- [x] `spec/ipmx_spec.lua`: deleted the `doc:validate('ipmx') — extmap location` describe block (it was a regression guard for the now-removed requirement).
- [x] `spec/ipmx_spec.lua`: added new describe block `a=extmap is optional at IPMX baseline (M31)` with two acceptance tests guarding against accidental re-introduction of the unconditional requirement.
- [x] `spec/ipmx_spec.lua`: two "generic SDP" tests now expect the new "media block required" error.
- [x] `spec/ipmx_spec.lua`: `spec_ref is TR-10-1 §7` test updated to expect "TR-10-2 §7"; comment explains the cite correction.
- [x] `spec/ipmx_spec.lua`: `spec_ref for rtcp-mux rejection is TR-10-1 §8.7` updated to "TR-10-1 §8.7 + RFC 5761".
- [x] `examples/ipmx/invalid/01_missing_extmap.sdp` renamed to `01_missing_ipmx_marker.sdp` (the SDP content already lacked the IPMX fmtp marker; the filename now matches the actual reason it fails).
- [x] `examples/examples.lua` references updated to the new filename and label.

**Tests:** 665 → 666.

**Spec references for M31:**

- SMPTE ST 2110-10:2022 §6.5 — IPv4 multicast Local/Internetwork Control Block prohibition (confirmed grounded)
- SMPTE ST 2110-10:2022 §7 / §8.1 — SDP-based media-stream signaling (basis for "at least one media block")
- VSF TR-10-1 §8.7 — RTCP on media-port+1
- VSF TR-10-2 §7, TR-10-3 §7, TR-10-4 §7, TR-10-11 §7, TR-10-12 §7 — per-essence port-even/>1024 clause (identical wording)
- VSF TR-10-13 §1.1.1 — `a=extmap` mandated only for PEP RTP Extension Header declaration
- IETF RFC 5285 — `a=extmap` grammar
- IETF RFC 5761 — `a=rtcp-mux` definition (derivation source for IPMX prohibition)

---

### M30 — Conformance principle + strictness fixes ✓ (audit 2026-05-14, round 9)

**Done when:** A user-directed conformance principle is in place — every validator check must cite explicit prohibitive spec text ("shall not", "is forbidden", or RFC well-formedness); silence in the spec is not a reason to reject. Six real gaps from a round-9 audit are fixed under that principle; two existing checks that violated it are loosened.

The audit also flagged opinion-based checks (e.g., 224.0.0.0/24 multicast reservation, ST 2110-30 audio rate/channel caps) for an M31 audit pass that will systematically tag every check by category {explicit prohibition / RFC well-formedness / opinion} and remove the opinion-tagged ones.

#### Strictness fixes (non-conformant SDPs that used to pass)

- [x] **G1: `depth` enumeration** (ST 2110-20:2017 §7.4.2). `depth` was previously validated as a positive integer, so `depth=7`, `depth=14`, `depth=24` passed. New `VALID_DEPTH` set + `valid_depth` validator enforces the §7.4.2 enumeration `{8, 10, 12, 16, 16f}`. ([parse_sdp.lua:839-848](parse_sdp.lua#L839-L848))
- [x] **G1b: `width`/`height` upper bound 32767** (ST 2110-20:2017 §7.2 — "Permitted values are integers between 1 and 32767 inclusive"). New `valid_pixel_dim` builder enforces the upper bound on both dimensions. ([parse_sdp.lua:850-862](parse_sdp.lua#L850-L862))
- [x] **G4: `interlace` / `segmented` are flag-only** (ST 2110-20:2017 §7.3 + §7.1). §7.3 defines both parameters by parameter-name presence/absence; §7.1 lets fmtp entries take `name=value` or bare-name form. After fmtp parsing, `interlace=anything` and `segmented=anything` are rejected because the §7.3 spec defines no value form. ([parse_sdp.lua:1316-1323](parse_sdp.lua#L1316-L1323))
- [x] **G8: `TROFF` positive (not non-negative)** (ST 2110-21:2017 §8 — "decimal positive integer"). Optional video fmtp validator now uses `valid_pos_int` for `TROFF`; the previously-accepted `TROFF=0` case is inverted. `valid_nonneg_int` is removed (no longer used). ([parse_sdp.lua:1342](parse_sdp.lua#L1342))
- [x] **G9: `MAXUDP` forbidden with `PM=2110BPM`** (ST 2110-20:2017 §6.3.3 — "The Extended UDP size limit defined in SMPTE ST 2110-10 shall not be used in the Block Packing Mode"). MAXUDP signals Extended-limit operation, so its presence with `PM=2110BPM` violates the §6.3.3 prohibition. New cross-field check after the required-params loop. ([parse_sdp.lua:1325-1331](parse_sdp.lua#L1325-L1331))

#### Strictness loosenings (existing checks not grounded in normative spec text)

- [x] **G5a: ST 2110-30 audio sample rate scope removed**. §6.1 mandates 48 kHz and permits 44.1/96 kHz, then says *"Other sampling frequencies and resolutions are out of scope of this standard."* "Out of scope" is not "shall not". The strict-ST-2110 rejection of 32/88.2/176.4/192/22050/1 kHz was opinion, not conformance. Deleted `ST2110_AUDIO_RATES`, `IPMX_AUDIO_RATES`, the `valid_audio_rates` branch in `st2110.validate`, and the `opts = { ipmx_layer = true }` argument that selected between them. The IPMX-side regression guards for extended rates still pass — both modes now accept any well-formed positive rate.
- [x] **G5b: ST 2110-30 audio 1..16 channel cap removed**. ST 2110-30:2017 §6.2.2 / Table 2 documents Conformance Levels with channel counts up to 64; the spec has no global upper bound. Replaced `1..16` cap with RFC 3551 / RFC 4566 well-formedness (`channels >= 1`; rtpmap must include channel count). Test fixture expanded to {1, 2, 8, 16, 32, 64, 128}.

#### Audit findings deferred to M31

The audit also surfaced cited-but-not-grounded checks that should be re-cited or removed under the principle. Held for M31 to avoid mixing strict-add and strict-remove behavior in one diff:

- IANA multicast reservation 224.0.0.0/24 and 224.0.1.0/24 rejection ([parse_sdp.lua:753-756](parse_sdp.lua#L753-L756)) — configuration-time concern (RFC 5771), not SDP conformance.
- IPMX `m=` port-even-and-greater-than-1024 ([parse_sdp.lua:2169-2178](parse_sdp.lua#L2169-L2178)) — currently cited as TR-10-x; confirmed clause is **TR-10-12 §7** (and likely repeated across per-essence TR-10s). M31 fixes the citation.
- IPMX `a=rtcp-mux` rejection ([parse_sdp.lua:2181-2185](parse_sdp.lua#L2181-L2185)) — same: cite TR-10-12 / TR-10-x §7 or remove.
- Audio packet-fit math ([parse_sdp.lua:1374-1389](parse_sdp.lua#L1374-L1389)) — keep as RFC 3550 + MAXUDP well-formedness, re-cite.

#### Audit findings deliberately not addressed (this round)

- **G2: ST 2110-40 `ancCount`** — RFC 8331 §2 defines `ANC_Count` as a runtime field in the RTP payload header, not an SDP fmtp parameter. Not actionable from SDP validation.
- **G3: ST 2110-31 (AES3 / AM824) fmtp validation** — local PDF set does not include ST 2110-31 (only TR-10-12, which defers to ST 2110-31 §5.1, 5.3, 5.4, 6, 7). Deferred until the spec source is available; the current AM824 path goes through the same encoding / channel-order / packet-fit checks as ST 2110-30.
- **G7: ST 2110-20 sampling × colorimetry × range cross-table** — combinatorial; one wrong cell would create false positives against conformant streams. User-deferred indefinitely.
- **exactframerate reduction to lowest terms** (§7.2 — "utilizing the numerically smallest numerator value possible"). User decision: do not enforce; documented in GUIDE.md instead.

#### Tests added / inverted (29 net new)

- M30 G1 (depth enum): 5 acceptance + 9 rejection tests (`spec/st2110_spec.lua` new section, plus existing `rejects depth=0` test updated to match the new error message).
- M30 G1b (width/height ≤ 32767): 4 tests (boundary acceptance, two off-by-one rejections, one far-above rejection).
- M30 G4 (interlace/segmented flag-only): 5 tests (3 rejections + 2 regression guards for bare-flag form).
- M30 G5a (audio rate loosening): 8 tests (the previously-rejecting "out of scope" / nonsense-rate cases are now acceptance tests; the IPMX-side `extended_rates` regression guard in `spec/ipmx_spec.lua` continues to pass unchanged).
- M30 G5b (channel count cap removed): channel test set widened from {1, 8, 16} to {1, 2, 8, 16, 32, 64, 128}; "rejects channel count 17" removed; "rejects channel count 0" re-cited as RFC 3551 well-formedness; "rejects rtpmap with no channel count" re-cited as RFC 3551 well-formedness.
- M30 G8 (TROFF positive): "accepts TROFF=0" inverted to "rejects TROFF=0"; existing TROFF/CMAX cross-field test fixture updated to use `TROFF=4500`.
- M30 G9 (MAXUDP + PM=2110BPM): 4 tests (2 rejections, 1 missing-MAXUDP acceptance, 1 GPM regression guard).

**Tests:** 636 → 665.

**Spec references for M30:**

- SMPTE ST 2110-20:2017 §7.4.2 — depth enumeration {8, 10, 12, 16, 16f}
- SMPTE ST 2110-20:2017 §7.2 — width/height range 1..32767 inclusive
- SMPTE ST 2110-20:2017 §7.1 / §7.3 — interlace/segmented parameter-name-only form
- SMPTE ST 2110-20:2017 §6.3.3 — Extended UDP size shall not be used in Block Packing Mode
- SMPTE ST 2110-21:2017 §8 — TROFF decimal positive integer
- SMPTE ST 2110-30:2017 §6.1 — audio sample rate scope language ("out of scope" ≠ "forbidden")
- SMPTE ST 2110-30:2017 §6.2.2 / Table 2 — audio Conformance Levels (no global channel cap)
- IETF RFC 3551 §6 — rtpmap channels parameter well-formedness

---

### M29 — Validation gap closure ✓ (audit 2026-05-14, round 8: IP address syntax + IPMX source-filter)

**Done when:** Gaps surfaced by a six-spec parallel audit (ST 2110-10:2022 PDF, TR-10-1, the per-media-type TR-10-2/3/4/7/9/10/11/12, the extension TR-10-5/6/13/14/15/16, the three 2026-01 IPMX Released Profile docs, and TR-10-TP-1 the IPMX test plan) are addressed. The audit cross-referenced the validator's ~140 checks and ~600 tests against ~250 normative SDP requirements. Five gaps surfaced; four were verified false-negatives by running invalid SDPs through the validator (e.g. `c=IN IP4 999.0.0.0` and `c=IN IP6 not-an-ipv6` both used to pass), one was a SHOULD→MUST-wording strictness gap.

#### False-negative fixes (non-conformant SDPs that used to pass)

- [x] **G1: c= IPv4/IPv6 literal address syntax** (ST 2110-10 §6.5 — IPv4 unicast per RFC 791, IPv6 per RFC 2460). `valid_connection_address` previously extracted only the first octet to check the multicast range and accepted anything else. Now the address (before any `/<ttl>` or `/<scope>` suffix) must match the LPEG IPv4/IPv6 patterns (aliased as `_ipv4_addr_pat` / `_ipv6_addr_pat` from the existing `valid_tsrefclk` patterns). Catches `c=IN IP4 1.2.3` (3 octets), `c=IN IP4 999.0.0.0` (octet > 255), `c=IN IP4 192.168.1.1.5` (5 octets), `c=IN IP6 not-an-ipv6`, `c=IN IP6 ff02::garbage`. ([parse_sdp.lua:683-737](parse_sdp.lua#L683-L737))
- [x] **G2: a=source-filter dest/src literal address syntax** (RFC 4570 / ST 2110-10 §6.5). The format LPEG pattern matched but the dest and src tokens were unchecked. After format match, the validator now parses out addrtype, dest, and each src and validates each as a literal address of that family. ([parse_sdp.lua:679-697](parse_sdp.lua#L679-L697))
- [x] **G4: a=source-filter required on every IPMX RTP block** (TR-10-TP-1 §13.2). User-confirmed: enforce at IPMX tier only — ST 2110-10 §8.4 only says SHOULD, so ST 2110 mode is unchanged. Session-level `a=source-filter` (RFC 4570: applies to all media) satisfies the requirement. TR-10-14 USB blocks remain exempt. Check fires at the end of `ipmx.validate` so existing more-specific errors continue to fire first.
- [x] **G5: TSDELAY must be a positive integer** (ST 2110-10 §8.7: "decimal positive integer number of microseconds"). The optional video fmtp validator entry used `valid_nonneg_int`, which accepted `TSDELAY=0`. Switched to `valid_pos_int`; the previously-passing "accepts TSDELAY=0" test was inverted to a rejection.

#### Gap surfaced but deliberately not fixed

- **G3: o= line `unicast_address` syntax**. RFC 4566 §5.7 ABNF allows `IP4-address / IP6-address / FQDN / extn-addr`. FQDN single-label tokens like "localhost" match valid RFC 1123 hostname grammar, so any strict check would reject very little while risking real-world senders that legitimately put hostnames in `o=`. Skipped pending a clear ST 2110/IPMX requirement that `o=` must be a literal IP.

#### Fixture / docs updates

- [x] `IPMX_VIDEO_SDP`, `base_ipmx_sdp`, and ~30 inline IPMX test fixtures across `spec/ipmx_spec.lua` and `spec/st2110_spec.lua` updated to include `a=source-filter` on every RTP block (RFC 4566 §5 order preserved: b= before a=). For helpers that conditionally append `b=AS:...`, the source-filter line was moved after the conditional so order stays valid for both call shapes.
- [x] All five valid example fixtures in `examples/ipmx/valid/` updated with `a=source-filter`. The four invalid fixtures in `examples/ipmx/invalid/` still reject for their intended reasons (extmap missing, ts-refclk missing, DUP privacy mismatch, rtcp-mux) — each of those errors fires before the new source-filter check.

#### Tests added (20 net new)

- M29 G1 (c= IPv4/IPv6 syntax): 8 new tests in `spec/st2110_spec.lua` (3-octet, octet>255, 5-octet, IPv4 syntax bad-inner-octet, IPv6 garbage, IPv6 garbage-multicast, IPv4 boundary 255.255.255.254, IPv6 compressed).
- M29 G2 (source-filter address syntax): 7 new tests in `spec/st2110_spec.lua` (non-IPv4 src, non-IPv4 dest, IPv4 octet>255, non-IPv6 src, valid IPv4, multi-src IPv4, valid IPv6).
- M29 G4 (IPMX source-filter required): 3 new tests in `spec/ipmx_spec.lua` + 1 regression-guard in `spec/st2110_spec.lua` confirming ST 2110 tier does not require it.
- M29 G5 (TSDELAY positive): 1 net new test (`rejects TSDELAY=0`), 1 test inverted (`accepts TSDELAY=0 and positive integer` → `accepts positive TSDELAY`).

**Tests:** 616 → 636.

**Spec references for M29:**

- SMPTE ST 2110-10:2022 §6.5 — IPv4/IPv6 literal addressing requirements for the `c=` connection field
- SMPTE ST 2110-10:2022 §8.7 — `TSDELAY` decimal positive integer
- IETF RFC 4570 — `a=source-filter` syntax
- IETF RFC 791 / RFC 2460 — IPv4 / IPv6 address literal grammar
- VSF TR-10-TP-1 §13.2 — IPMX sender SDP verification (`a=source-filter` verified on every essence type)

---

### M28 — IETF RFC strictness audit ✓ (audit 2026-05-14, round 7)

**Done when:** Gaps surfaced by an IETF-RFC-focused audit (different angle from the SMPTE/VSF-focused M27 round) are addressed. Two parallel research agents read RFC 4145, 4570, 5285, 5761, 5888, 7104, 3605 (Agent 1) and RFC 7273, 8331, 9134, 5771 (Agent 2) and compared the prose ABNFs to the validator. Several agent claims were rejected after direct ABNF verification (see "Rejected claims" below); three real low-severity strictness gaps were fixed.

**ABNF re-verified directly against the RFC source text before coding** (the audit prose was approximate in places):

- RFC 5285 §7: `extensionattributes = byte-string`; RFC 4566 §9 `byte-string = 1*(%x01-09 / %x0B-0C / %x0E-FF)` (excludes NUL, LF, CR — not "VCHAR-only" as the audit said).
- RFC 5888 §4/§5: `semantics` and `identification-tag` are both RFC 4566 tokens (`token-char = %x21 / %x23-27 / %x2A-2B / %x2D-2E / %x30-39 / %x41-5A / %x5E-7E`).
- RFC 3605 §2.1: `rtcp-attribute = "rtcp:" port [SP nettype SP addrtype SP connection-address]`.

#### LOW-severity strictness fixes

- [x] **RFC 5285 §7 — extmap ext-attr byte-string strictness**. The trailing `(P(" ") * P(1)^0)^-1` accepted any byte (including NUL/CR/LF). Now `(P(" ") * (P(1) - S("\0\r\n"))^1)^-1`. Practical impact: NUL bytes in ext-attrs are now rejected. ([parse_sdp.lua:1466-1471](parse_sdp.lua#L1466-L1471))
- [x] **RFC 5888 §4/§5 — a=group and a=mid token grammar**. Added `_rfc4566_token_char` LPEG pattern (precise RFC 4566 token character set) and helpers `valid_mid_value` / `valid_group_value`. Both are invoked from `st2110.validate` (which IPMX inherits). The previous code extracted the first non-whitespace run as semantics, silently allowing invalid characters and letting malformed groups bypass DUP validation. ([parse_sdp.lua:434-476](parse_sdp.lua#L434-L476), invocation [parse_sdp.lua:1378-1408](parse_sdp.lua#L1378-L1408))
- [x] **RFC 3605 §2.1 — a=rtcp full grammar**. The previous code extracted only `^(%d+)`, silently ignoring any trailing garbage. Now the value must match either `<port>` alone or `<port> SP IN SP (IP4|IP6) SP <address>`; the optional address triple is delegated to `valid_connection_address` (which IPMX already uses for `c=` lines). ([parse_sdp.lua:2154-2189](parse_sdp.lua#L2154-L2189))

#### Rejected claims (after direct ABNF verification)

- **"RFC 7273 rejects bare `ntp`, `local`, `private` in `sdp` mode"** — wrong. `valid_tsrefclk` is only invoked from `st2110.validate`; `sdp` mode does no ts-refclk validation at all. ST 2110-10 mandates PTPv2, so rejecting bare `ntp`/`local`/`private` in ST 2110 mode is correct.
- **"RFC 5771 reserves 232.x/233.x/239.x — reject those multicast ranges"** — wrong. 239.0.0.0/8 (administratively-scoped) is the canonical ST 2110 / IPMX multicast range; rejecting it would break the library against every real-world SDP.
- **"RFC 8331 should reject unknown smpte291 fmtp params"** — the agent's own caveat: RFC 8331 doesn't forbid extensions.
- **"RFC 4566 §6.1 ptime non-negative integer in `sdp` mode"** — ST 2110 mode already validates this; RFC 4566 itself permits `ptime` to be opaque.

#### Borderline cases left as-is

- **RFC 4145 setup-required for non-USB TCP blocks** — RFC 4145's REQUIRED status applies to offer/answer exchanges per RFC 3264; declarative SDP (which is what IPMX/ST 2110 use) does not mandate `a=setup`. Current behavior of bypassing non-USB application blocks remains.
- **RFC 5888: unknown group semantics (BUNDLE/ALT/LS)** — TR-10-1 §10 forbids only FID; other semantics aren't prohibited by IPMX (also confirmed in M27).

#### Tests added (4 new, all guarded)

- a=extmap: rejects NUL byte in ext-attr; accepts printable `opt=val` ext-attr.
- a=mid: rejects parenthesis, rejects forward slash, accepts hyphen+period token (`primary-feed.0`).
- a=group: rejects parenthesis in semantics, rejects comma in identification-tag, rejects whitespace-only value, accepts `DUP leg1 leg2`.
- a=rtcp: accepts `<port> IN IP4 <addr>`, rejects `<port>/<addr>` slash form, rejects `IN IPX <addr>` (bad addrtype), rejects `IN IP4` with no address.

**Tests:** 603 → 616 (13 net new tests).

**Spec references for M28:**

- IETF RFC 4566 §9 — byte-string and token grammar
- IETF RFC 5285 §7 — a=extmap ABNF
- IETF RFC 5888 §4/§5 — a=mid identification-tag and a=group semantics
- IETF RFC 3605 §2.1 — a=rtcp ABNF

---

### M27 — Validation gap closure ✓ (audit 2026-05-14, round 6)

**Done when:** Six gaps surfaced by the round-6 cross-spec audit (ST 2110-10/-20/-21/-22/-30 PDFs + IPMX Released Profile docs + TR-10 series) are addressed. Two parallel research agents audited the ~80KB validator and ~210KB of tests against the spec corpus; six findings were flagged by the user as "fix"; four findings ("TP IPMX restriction," "HKEP fmtp conditional," "Group BUNDLE/ALT/LS rejection," "Infoframe backing m=ST2110-41") were verified against source spec text and skipped because the specs do not require them.

#### HIGH-severity (SHALL violations passing today)

- [x] **H1: ST 2110-20 §7.3 — `segmented` requires `interlace`** ("Signaling of [segmented] without the interlace parameter is forbidden"). The video fmtp validator at [parse_sdp.lua:1213-1217](parse_sdp.lua#L1213-L1217) now rejects this combination. The previously-passing "accepts segmented bare flag" test was removed (the spec forbids it).
- [x] **H2: ST 2110-20 §7.3 — PAR must be in lowest terms** ("The smallest integer values possible for width and height shall be used"). `valid_par` ([parse_sdp.lua:807-822](parse_sdp.lua#L807-L822)) now rejects e.g. `PAR=2:2`, `PAR=4:6`, `PAR=100:100`. A small `gcd` helper was added.
- [x] **H3: ST 2110-30 §6.1 — sample rate scope tightened in ST 2110 mode only** ("Other sampling rates are out of scope"). Strict ST 2110 mode permits only {44.1, 48, 96} kHz; IPMX mode keeps the AES67-extended set {32, 44.1, 48, 88.2, 96, 176.4, 192} kHz. Implemented by threading `opts.ipmx_layer` through `st2110.validate(doc, opts)`; the IPMX validator passes `{ ipmx_layer = true }` when calling down.
- [x] **H4: ST 2110-10 §6.4 — audio packet payload fit** (Standard UDP Size Limit 1460 unless MAXUDP signals Extended Limit ≤ 8960). When `a=ptime` is present, the validator computes `channels × samples-per-packet × bytes-per-sample` (L16=2, L24=3, AM824=4) and rejects when it exceeds `MAXUDP − 12` (RTP header overhead). Catches e.g. `L24/48000/16ch @ ptime=1ms` (2304 B > 1448 B) which can't physically be transmitted.
- [x] **H5: ST 2022-7 §6 — DUP cross-leg PT and fmtp identity** ("Senders shall transmit on both flows the same RTP payload data and shall use the same payload type number"). The existing DUP validator already enforced media-type and rtpmap-encoding/rate equality; now also enforces identical RTP payload type numbers and identical fmtp value strings across legs.
- [x] **H6: TR-10-14 §14 — USB block RTP-attribute rejection** ("The SDP shall follow RFC 4145 with the following restrictions"; RFC 4145 is TCP-only, no RTP attrs defined). IPMX USB blocks (`m=application TCP usb`) now reject `a=rtpmap`, `a=fmtp`, `a=mediaclk`, and `a=ts-refclk` — these have no meaning on TCP transport.

#### Regression guards

- [x] **R1: IPMX PCM mono accepted** (`channel-order=SMPTE2110.(M)`). The "M" group is in ST 2110-30:2017 §6.2.2 Table 1 and IPMX inherits it; user explicitly confirmed mono is permitted. Test guards against accidental tightening.
- [x] **R2: IPMX permissive audio rates retained**. Adds tests asserting 32 / 88.2 / 176.4 / 192 kHz are accepted in IPMX mode after the ST 2110 tightening.

#### Verified against spec and intentionally not fixed

- **TP value enumeration for IPMX video** — VSF TR-10-1 §8.1 says IPMX senders MAY use any of ST 2110-21's {2110TPN, 2110TPNL, 2110TPW} without restriction; existing presence-only check at [parse_sdp.lua:1872-1876](parse_sdp.lua#L1872-L1876) is correct.
- **HKEP conditional presence** — VSF TR-10-5 §10 conditions a=hkep on the stream being HDCP Content (not derivable from SDP alone); no fmtp-side trigger exists. Cannot be enforced strictly from SDP.
- **Group BUNDLE/ALT/LS rejection** — TR-10-1 §10 explicitly forbids only `a=group:FID`; other group semantics are not prohibited (over-strict to reject).
- **Infoframe backing `m=ST2110-41` block** — TR-10-10 §8 says only that the infoframe port equals the associated media stream's port + 3; it does not require the associated media block to be a fast-metadata stream.

#### Tests added

- PAR: rejects `PAR=2:2`, `PAR=4:6`, `PAR=100:100`; accepts `PAR=12:11`, `PAR=64:45`.
- Cross-field: rejects `segmented` without `interlace` (previously passed; the now-incorrect "accepts segmented bare flag" test was removed).
- DUP: rejects different PT across legs; rejects same rtpmap but different fmtp essence params; accepts identical-attribute baseline.
- ST 2110-30 audio rates: accepts {44.1, 48, 96} kHz; rejects {32, 88.2, 176.4, 192} kHz with `spec_ref = "ST 2110-30 §6.1"`.
- IPMX audio rates: accepts {32, 88.2, 176.4, 192} kHz (regression guard).
- IPMX PCM: accepts `channel-order=SMPTE2110.(M)` (mono regression guard).
- Audio payload fit: accepts L24/48000/8ch @ ptime=1; rejects L24/48000/16ch @ ptime=1 with spec_ref `ST 2110-10 §6.4`; accepts the same with MAXUDP=8960; accepts at ptime=0.125; rejects L16/96000/8ch @ ptime=1.
- USB block: rejects each of `a=rtpmap`, `a=fmtp`, `a=mediaclk`, `a=ts-refclk` with spec_ref `TR-10-14 §14`.

**Spec references for M27:**

- SMPTE ST 2110-20:2017 §7.3 — interlace/segmented requirements; PAR lowest-terms requirement
- SMPTE ST 2110-10 §6.4 — Standard / Extended UDP Size Limits
- SMPTE ST 2110-30:2017 §6.1 — audio sample-rate scope
- ST 2022-7 §6 (referenced by ST 2110-10 §8.5 / RFC 7104) — DUP identical payload + PT
- VSF TR-10-14 (2026-04-07) §14 — USB-SDP definition
- VSF TR-10-1 §8.1, TR-10-5 §10, TR-10-10 §8 — verified-and-skipped findings

---

### M26 — Validation gap closure ✓ (audit 2026-05-14, round 5)

**Done when:** Four gaps surfaced by the round-5 cross-spec audit are addressed.

#### HIGH-severity (SHALL violations passing today)

- [x] **H1: a=privacy session→media inheritance for DUP consistency**
  (TR-10-13 §13 line 859 — *"a session-level privacy attribute represents the
  default value for each media-level privacy attribute unless an explicit
  media-level privacy attribute is provided"*). The DUP-leg privacy equality
  check compared only media-level attributes; a leg without media-level
  `a=privacy` against a leg with one would falsely report a mismatch even
  when the inherited session-level value matched. `ipmx.validate` now resolves
  effective privacy (media-or-session) before the leg-equality test.
- [x] **H2: `ts-refclk:ptp=` version must be `IEEE1588-2008`**. The round-5
  audit recommended enforcing this in IPMX mode; the test-first pass revealed
  that `valid_tsrefclk` ([parse_sdp.lua:555](parse_sdp.lua#L555)) already
  enforced it at the **ST 2110** tier per ST 2110-10:2022 §6.1 / §8.2 (PTPv2
  is mandated; the RFC 7273 grammar is parametric but the ST 2110-10 profile
  pins it). IPMX inherits this restriction. No code change needed; tests
  pinning the behavior were added at both tiers and the asymmetry is
  documented in GUIDE.md.

#### LOW coverage tightening

- [x] **L1: UDP port upper bound** — `m=` port and `a=rtcp:<port>` must be
  ≤ 65535 (RFC 768). `grammar.parse_media` now rejects ports > 65535;
  IPMX `a=rtcp` validation rejects > 65535 before the port+1 check. `a=hkep`
  already enforced it.
- [x] **L2: IPv6 multicast c= scope suffix** — `valid_connection_address`
  short-circuited for IP6. Now: IPv6 multicast (`ff` prefix) may carry
  `/<positive-integer>` suffix; IPv6 unicast must not include a suffix.

#### Tests to add

- DUP legs both without media-level a=privacy but session has one → success.
- DUP legs where session has a=privacy + leg2 has same value explicitly + leg1 inherits → success (currently fails).
- DUP legs where session has a=privacy + leg2 has DIFFERENT value + leg1 inherits → reject.
- IPMX SDP with `ptp=IEEE1588-2008:...` → success.
- IPMX SDP with `ptp=IEEE1588-2019:...` → reject (HIGH).
- IPMX SDP with `ptp=IEEE1588:...` → reject.
- ST 2110 mode with `ptp=IEEE1588-2019:...` → still success (intentional asymmetry).
- IPMX SDP with `localmac=` (no ptp) → success (rule does not apply).
- `m=video 65536 RTP/AVP 96` → parse error.
- `a=rtcp:65536` → reject in IPMX mode.
- `c=IN IP6 ff02::1` (multicast missing scope) — accept-or-reject per chosen rule.
- `c=IN IP6 2001:db8::1/64` (unicast with suffix) → reject.
- `c=IN IP6 ff02::1/64` (multicast with valid scope) → success.

**Spec references for M26:**

- VSF TR-10-1 (2024-02-23) §10.4 line 196 — IEEE 1588-2008 mandated for IPMX PTP
- VSF TR-10-13 (2026-02-17 v2) §13 line 859 — session-level a=privacy is the
  default for each media-level a=privacy
- RFC 768 — UDP port range
- RFC 4566 §5.7 — connection address grammar
- RFC 7273 / ST 2110-10:2022 §8.2 — ts-refclk grammar permits multiple PTP versions

---

### M25 — Validation completeness audit ✓ (2026-05-14, round 4)

**Done when:** All gaps from the parallel cross-spec audit (ST 2110-10:2022 PDF,
TR-10-0 … TR-10-16, TR-10-TP-1, three IPMX Released Profile docs) are addressed.

#### Critical fixes (correctness bugs from round 3)

- [x] **C1: IPMX AM824 rejection removed** (TR-10-12).
  TR-10-12 is the IPMX equivalent of SMPTE ST 2110-31 (AES3 transparent transport),
  which mandates AM824. The IPMX validator previously rejected AM824 citing TR-10-3 §8;
  that rejection was wrong and is removed. Flipped existing M22 AM824 rejection tests.
- [x] **C2: a=privacy trailing semicolon rejected** (TR-10-13 §13 line 338 — *"There
  shall be no semicolon after the last parameter."*). The parser previously consumed
  `[^;]+` segments silently, masking a trailing `;`. Now explicit-rejected.

#### HIGH-severity (SHALL violations passing today)

- [x] **H1: RTP dynamic payload type range 96–127 enforced** (ST 2110-10 §6.2).
  `st2110.validate` rejects any rtpmap payload type outside the dynamic range.
- [x] **H3: a=infoframe port = associated media port + 3** (TR-10-10 §8 line 135).
  Cross-check against every media block's port; reject orphan ports.
- [x] **H4: DUP legs may not share identical (src, dst) addresses** (ST 2110-10 §8.5).
  `each_dup_group` callback compares c= and a=source-filter src across legs.
- [x] **H5: IPMX baseband fmtp params required** (TR-10-1 §10.2 / §10.3 + TR-10-9 §10).
  `measuredpixclk`, `vtotal`, `htotal` required on every IPMX video fmtp;
  `measuredsamplerate` required on every IPMX audio fmtp.
- [x] **H6: b=AS required on jxsv blocks** (TR-10-7 §11 / ST 2110-22 §7.3).
  Compressed-video media blocks must declare bandwidth.
- [x] **H7: RFC 4145 a=setup / a=connection enum check** (RFC 4145 §4).
  General enum validation: `setup` ∈ {active, passive, actpass, holdconn};
  `connection` ∈ {new, existing}. Runs before the TR-10-14 USB-specific passive check.

H2 (ts-refclk restricted to ptp/localmac) was investigated and **skipped** —
TR-10-1 §10.4 reads "as specified in ST 2110-10 section 8.2," which permits
gps/gal/glonass/ntp forms. The audit agent over-interpreted; not a gap.

#### MEDIUM-severity

- [x] **M1: JPEG XS profile/level/sublevel enum validation** (TR-10-15-Part1 §8/§9 +
  TR-08 §8.1.1 / ISO/IEC 21122-2). Replace `valid_nonempty` with explicit enums
  (`VALID_JXS_PROFILE`, `VALID_JXS_LEVEL`, `VALID_JXS_SUBLEVEL`).
- [x] **M2: JPEG XS transmode/packetmode ∈ {0, 1}** (RFC 9134 / TR-10-15 §9 —
  both are 1-bit values). Replace `valid_nonneg_int` with `valid_enum`.
- [x] **M3: MAXUDP upper bound 8960** (ST 2110-10 §6.4 — Extended UDP Size Limit).
  New `valid_maxudp` wraps `valid_pos_int` with the 8960 ceiling.
- [x] **M4: Session-level a=mediaclk rejected** (ST 2110-10 §8.3 — "media-level mediaclk").
- [x] **M5: Session-level b=AS validated at IPMX tier** (TR-10-7 §11). Positive
  integer required on both session and media scope.
- [x] **M6: DUP legs must share rtpmap encoding and clock rate** (ST 2022-7 / ST 2110-10 §8.5).
- [x] **M7: PEP IV-Counter extmap direction = sendonly** (TR-10-13 §20.1).
- [x] **M8: a=infoframe per-port uniqueness across multiple lines** (TR-10-10 §8 implied).
- [x] **M9: a=infoframe must be session-level only** (TR-10-10 §8 — "session attribute").
- [x] **M10: TP required on IPMX video fmtp** (TR-10-TP-1 §13.2).
- [x] **M11: a=hkep must be session-level only** (TR-10-5 §10 — "session attribute"). The
  previous M15 implementation tolerated media-level placement; tightened to reject.

#### LOW coverage tightening

- [x] a=hkep with IPv6 unicast address (positive test).
- [x] PEP `ECDH_AES-128-CTR_CMAC-64` (non-AAD) rejected on USB.
- [x] a=privacy key-order invariance (positive test).
- [x] USB block without a=privacy (encryption-off path) accepted.
- [x] Valid IPMX JPEG-XS SDP — IPMX-tier acceptance.
- [x] a=infoframe SSN year coverage (2099 accepted, malformed 24 rejected).
- [x] b=AS:1 lower-bound accepted; b=AS:0 rejected at IPMX tier.
- [x] New fixture: `examples/ipmx/valid/04_jpegxs.sdp`.

#### Fixture / docs updates

- [x] `IPMX_VIDEO_SDP`, `base_ipmx_sdp` defaults, and all 29 inline IPMX video
  fmtp strings updated with `measuredpixclk=148500000; vtotal=1125; htotal=2200`.
- [x] All 5 inline IPMX audio fmtp strings updated with `measuredsamplerate=48000`.
- [x] Example fixtures in `examples/ipmx/valid/` (01–04, dup_group_video) and
  `examples/ipmx/invalid/` (dup_privacy_mismatch, rtcp_mux) updated for new required fields.

**Tests:**

- 60 new tests across `spec/st2110_spec.lua` and `spec/ipmx_spec.lua`.
- 2 obsolete tests removed (M22 AM824 rejection + spec_ref for AM824 rejection).
- 2 obsoleted media-level a=hkep tests removed (replaced by M11 placement tests).
- Final count: 559 passing / 0 failing.

**Spec references for M25:**

- SMPTE ST 2110-10:2022 §6.2 — dynamic payload type range
- SMPTE ST 2110-10:2022 §6.4 — Extended UDP Size Limit (8960)
- SMPTE ST 2110-10:2022 §8.3 — mediaclk media-level only
- SMPTE ST 2110-10:2022 §8.5 — DUP redundant streams
- SMPTE ST 2110-22:2019 §7.3 — compressed video b=AS required
- IETF RFC 4145 §4 — setup/connection enums
- IETF RFC 9134 / VSF TR-10-15-Part1 §8–§9 — JPEG XS params
- VSF TR-10-1 §10.2, §10.3 — IPMX baseband fmtp
- VSF TR-10-5 §10 — a=hkep session attribute
- VSF TR-10-7 §11 — b=AS positive integer
- VSF TR-10-9 §10 — non-baseband IPMX fmtp
- VSF TR-10-10 §8 — a=infoframe port association
- VSF TR-10-12 §1 — IPMX AES3 transparent transport (AM824)
- VSF TR-10-13 §13 — a=privacy trailing-semicolon rule
- VSF TR-10-13 §20.1 — PEP IV-Counter extmap direction
- VSF TR-10-14 §12 — USB privacy AAD modes
- VSF TR-10-TP-1 §13.2 — IPMX required fmtp parameters

---

### M24 — Validation completeness audit ✓ (2026-05-13, round 3)

**Done when:** All gaps identified in the comprehensive spec audit are addressed.
Sources: full reads of ST 2110-10:2022 (PDF), TR-10-0 through TR-10-16, TR-10-TP-1,
and the three IPMX profile docs (Uncompressed Video, PCM Audio, JPEG-XS Video).

---

#### HIGH-severity (SHALL violations passing today)

- [x] **H1: `a=mediaclk:direct` offset must be 0** (ST 2110-10 §7.3 / TR-10-1 §10.5).
  `valid_mediaclk` now accepts only `direct=0` or `sender`; any non-zero offset is rejected.
- [x] **H2: USB `a=privacy` protocol must be `USB_KV`** (TR-10-14 §14).
  Split `PRIVACY_PROTOCOLS` into RTP/USB allow-lists; `valid_privacy` selects by transport.
- [x] **H3: USB blocks require `a=setup:passive`** (TR-10-14 §14).
  Every TR-10-14 USB block (`m=application TCP usb`) must declare `a=setup:passive`.
- [x] **H4: Privacy hex parameter lengths enforced** (TR-10-13 §13).
  Added `PRIVACY_HEX_LEN`; `iv`=16h, `key_generator`=32h, `key_version`=8h, `key_id`=16h.

#### MEDIUM-severity

- [x] **M1: `b=AS` positive integer** (TR-10-7 §11). Preparatory check for VBR compressed video.
- [x] **M2: `a=infoframe` format** (TR-10-10 §8). Validated as `<port> SSN=ST2110-41:YYYY;DIT=100100`.
- [x] **M3: PTP domain range 0–127** (IEEE 1588-2008 §7.1). `valid_tsrefclk` ptp branch now extracts and validates the optional domain.
- [x] **M4: `TROFF`/`CMAX` require `TP`** (ST 2110-21 §8). Cross-field check in video fmtp validation.
- [x] **M5: `a=mid` uniqueness per session** (RFC 5888 §8.1). Checked after the per-media loop in `st2110.validate`.

#### LOW-severity additions

- [x] **L1: `TSMODE` / `TSDELAY` format** (ST 2110-10 §8.7). `TSMODE` enum `{SAMP, NEW, PRES}`; `TSDELAY` non-negative integer.
- [x] **L2: `a=source-filter` format** (RFC 4570 / ST 2110-10 §8.4). LPEG grammar for `<incl|excl> IN <IP4|IP6> <dest> <src>+`.

#### Refactor

- [x] USB block detection split: `non_rtp_set` (broad bypass of ST 2110 RTP checks) vs `usb_set` (strictly `m=application TCP usb`, subject to TR-10-14 rules). Previously a single loose `usb_set` matched any application+TCP-in-proto.

**Tests:**

- ~47 new tests added across `spec/st2110_spec.lua` and `spec/ipmx_spec.lua`
- Existing privacy fixtures updated to use spec-correct hex digit counts; existing USB privacy tests updated to use `protocol=USB_KV` and include `a=setup:passive`

**Spec references for M24:**

- SMPTE ST 2110-10:2022 §7.3 — mediaclk direct offset SHALL be zero
- SMPTE ST 2110-10:2022 §8.7 — TSMODE, TSDELAY
- SMPTE ST 2110-10:2022 §8.4 — source-filter (RFC 4570)
- SMPTE ST 2110-21 §8 — TROFF, CMAX require TP
- IEEE 1588-2008 §7.1 — PTP domain range
- RFC 5888 §8.1 — a=mid uniqueness
- VSF TR-10-7 §11 — b=AS bandwidth
- VSF TR-10-10 §8 — a=infoframe
- VSF TR-10-13 §13 — privacy hex bit-lengths
- VSF TR-10-14 §14 — USB `a=setup:passive`, USB_KV protocol

---

## Commit Gates

Before any commit:

- [ ] Relevant tests added or updated
- [ ] `busted spec/` passes with no failures
- [ ] `GUIDE.md` reflects any API or behavior changes
- [ ] `README.md` updated if project layout or examples changed
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`
- [ ] `PLAN.md` milestone tasks checked off / updated
- [ ] `CLAUDE.md` updated if conventions changed

---

## Open Questions

- LuaRocks rockspec: publish to public registry or local-install only?
- Should ST 2110 validation have a non-fatal warning mode for informational checks?

---

## Refactor Milestones

These milestones address correctness bugs and structural issues found in an architectural review
(2026-05-13). They do not add public-facing features. Execute them in order — later milestones
assume earlier ones are complete.

Each milestone still follows the standard gate: write failing tests first, implement until they
pass, then update docs and commit.

---

### R1 — Fix: trailing content silently accepted (correctness bug)

**The bug.** `parse_sdp.lua` never verifies that all lines were consumed after the parse loop.
Any content after the last recognized field is silently dropped and the parser returns a valid
doc. This violates the strictness principle.

**Where it is.** `parse_sdp.lua`, after the `while pos <= n and peek_type(lines, pos) == "m"`
loop closes (≈ line 241 as of this writing). The loop exits when it no longer sees an `m=` type,
and `pos` is left pointing at the first unconsumed line. There is no guard.

**Step 1 — write failing tests in `spec/sdp_spec.lua`** (these currently PASS the parse but
should return `nil, err`):

```lua
describe("sdp.parse — trailing content rejected (R1)", function()
  local sdp = require("parse_sdp")

  it("rejects an unrecognized field after session attributes (no media)", function()
    local text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\nx=garbage\r\n"
    local doc, err = sdp.parse(text)
    assert.is_nil(doc)
    assert.is_table(err)
    assert.is_string(err.message)
    assert.equal(5, err.line)
  end)

  it("rejects an unrecognized field after the last media block", function()
    local text = table.concat({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=Test", "t=0 0",
      "m=video 49170 RTP/AVP 96", "a=recvonly",
      "x=garbage",
    }, "\r\n") .. "\r\n"
    local doc, err = sdp.parse(text)
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(7, err.line)
  end)

  it("rejects a second t= appearing where content is not expected", function()
    local text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\nt=100 200\r\n"
    local doc, err = sdp.parse(text)
    assert.is_nil(doc)
    assert.is_table(err)
  end)
end)
```

**Step 2 — implement the fix** in `parse_sdp.lua` after the media-block while-loop ends:

```lua
  -- guard: reject any unconsumed lines
  if pos <= n then
    local line = lines[pos]
    local t = peek_type(lines, pos)
    if t then
      return nil, make_err(
        string.format("unexpected field '%s=' after all SDP fields", t),
        pos, 1, line, "WRONG_ORDER"
      )
    else
      return nil, make_err(
        "unexpected content at end of SDP",
        pos, 1, line, "MALFORMED_LINE"
      )
    end
  end
```

**Step 3 — confirm all existing tests still pass.** The M3 test "ignores content after the four
required fields" in `sdp_spec.lua` (≈ line 291) does `sdp.parse(minimal .. "a=recvonly\r\n")` and
expects success. That line IS a recognized `a=` attribute and will be consumed, so it is not
trailing content — the test should keep passing. Verify before committing.

---

### R2 — Rename `doc:serialize()` → `doc:to_sdp()`; delete the old method

**The decision.** `doc:to_sdp()` and `doc:to_json()` form a self-describing, extensible pair —
the caller knows exactly what format they get. `doc:serialize()` is a generic verb that requires
knowing SDP is the canonical format. `to_sdp` becomes the only public method; `serialize` is
removed from the public API. `lib/serialize.lua` (internal module) and the CLI subcommand named
`serialize` are unaffected — this is a doc-method rename only.

**Scope of the rename — what changes vs. what stays:**

| Thing | Change? | Reason |
| --- | --- | --- |
| `mt:to_sdp()` in `parse_sdp.lua` | Becomes the real method, not an alias | It's already there |
| `mt:serialize()` in `parse_sdp.lua` | Delete | Replaced by `to_sdp` |
| `doc:serialize()` call sites in `spec/` | Rename to `doc:to_sdp()` | Follow the API change |
| `lib/serialize.lua` module + `M.serialize()` | No change | Internal implementation detail |
| `serialize.serialize(self)` inside `mt:to_sdp` | No change | Still the correct internal call |
| `cli.lua` `serialize` subcommand | No change | CLI verb, independent of method name |
| `examples/examples.lua` line ≈91 `mdoc:serialize()` | Rename to `mdoc:to_sdp()` | Follows API change |
| `GUIDE.md` API table | Update | Reflects the new public API |

**A global find/replace of `doc:serialize()` → `doc:to_sdp()` across `.lua` files works for
call sites in spec files. Before running it, verify the replacement will not touch the internal
call inside `mt:to_sdp()` itself — `serialize.serialize(self)` does not match the pattern, so
it is safe.**

**Files to change:**

1. **`parse_sdp.lua` lines 24–34** — make `to_sdp` the real method and delete `serialize`:

   ```lua
   -- KEEP (to_sdp is now the real method, not an alias):
   function mt:to_sdp()
     return serialize.serialize(self)
   end

   -- DELETE these three lines:
   function mt:serialize()
     return serialize.serialize(self)
   end
   ```

2. **`spec/sdp_spec.lua`** — the `describe("doc:serialize() (M7)")` block (≈ lines 687–814):
   rename every `doc:serialize()` and `sdp.parse(...):serialize()` call to use `to_sdp`. Also
   delete the `describe("to_sdp")` block (≈ lines 896–922) — its three tests become redundant
   (the rename makes `to_sdp` the canonical method, so testing serialize behavior through
   `to_sdp` is already done in the M7 block).

3. **`GUIDE.md`** — in the API reference, swap `doc:serialize()` → `doc:to_sdp()` and remove
   the `doc:to_sdp()` alias entry.

4. **`CHANGELOG.md`** — add under `[Unreleased]`:

   ```text
   - Changed: `doc:serialize()` renamed to `doc:to_sdp()`; old name removed
   ```

**Done when:** `busted spec/` passes and `grep -rn '\.serialize()' .lua` finds nothing in
`spec/` or `parse_sdp.lua` (only in `lib/serialize.lua` and the `mt:to_sdp` body).

---

### R3 — Deduplicate `find_attr` into `lib/util.lua`

**The issue.** `find_attr(attrs, name)` is copy-pasted verbatim at `lib/st2110.lua:15` and
`lib/ipmx.lua:15`. Any change to one must be manually mirrored to the other.

**Step 1 — create `lib/util.lua`:**

```lua
local M = {}

function M.find_attr(attrs, name)
  for _, a in ipairs(attrs or {}) do
    if a.name == name then return a end
  end
end

return M
```

**Step 2 — update `lib/st2110.lua`:**

- Add at top: `local util = require("lib.util")`
- Delete the local `find_attr` function (lines 15–19)
- Replace all six call sites `find_attr(...)` with `util.find_attr(...)`

**Step 3 — update `lib/ipmx.lua`:**

- Add at top: `local util = require("lib.util")`
- Delete the local `find_attr` function (lines 15–19)
- Replace the two call sites with `util.find_attr(...)`

**No new tests required.** Existing `st2110_spec.lua` and `ipmx_spec.lua` tests cover the
behavior; confirm they still pass after the change.

---

### R4 — Unify error construction in `lib/errors.lua`

**The issue.** Error tables are built in four separate places with different signatures:

| File | Local name | Signature |
| --- | --- | --- |
| `parse_sdp.lua:69` | `make_err` | `(msg, line, col, context, code)` |
| `lib/validate.lua:3` | `err` | `(msg, code)` — line/col always 0 |
| `lib/st2110.lua:3` | `st2110_err` | `(msg, field_path, spec_ref, code)` |
| `lib/ipmx.lua:3` | `ipmx_err` | `(msg, field_path, spec_ref, code)` |
| `cli.lua:18,26,42,67,77,94,104` | inline tables | ad-hoc `{message,line,col,context}` |

`lib/errors.lua` exists for this purpose but only implements `format()`.

**Step 1 — add `errors.new()` to `lib/errors.lua`** before the existing `format` function:

```lua
-- Construct a normalised error table.
-- msg: required string.
-- opts (optional table): line, col, context, code, field_path, spec_ref.
-- Absent opts default to 0/""/nil as appropriate.
function M.new(msg, opts)
  local o = opts or {}
  return {
    message    = msg,
    line       = o.line    or 0,
    col        = o.col     or 0,
    context    = o.context or "",
    code       = o.code    or "MISSING_FIELD",
    field_path = o.field_path,   -- nil when absent; format() checks nil
    spec_ref   = o.spec_ref,     -- nil when absent
  }
end
```

**Step 2 — add tests for `errors.new()` in `spec/errors_spec.lua`:**

```lua
describe("errors.new", function()
  it("sets message and defaults", function()
    local e = errors.new("something bad")
    assert.equal("something bad", e.message)
    assert.equal(0, e.line)
    assert.equal(0, e.col)
    assert.equal("", e.context)
    assert.equal("MISSING_FIELD", e.code)
    assert.is_nil(e.field_path)
    assert.is_nil(e.spec_ref)
  end)

  it("accepts all optional fields", function()
    local e = errors.new("x", {line=3, col=5, context="v=1", code="INVALID_VALUE",
                                field_path="origin", spec_ref="RFC §1"})
    assert.equal(3,             e.line)
    assert.equal(5,             e.col)
    assert.equal("v=1",         e.context)
    assert.equal("INVALID_VALUE", e.code)
    assert.equal("origin",      e.field_path)
    assert.equal("RFC §1",      e.spec_ref)
  end)

  it("result is renderable by format()", function()
    local e = errors.new("bad", {line=1, col=2, context="s="})
    local out = errors.format(e)
    assert.is_string(out)
    assert.truthy(out:find("bad", 1, true))
  end)
end)
```

**Step 3 — migrate each call site:**

- **`parse_sdp.lua`**: add `local errors = require("lib.errors")` at top; replace every
  `make_err(msg, line, col, context, code)` with
  `errors.new(msg, {line=line, col=col, context=context, code=code})`; delete the
  `make_err` local function (lines 69–71).

- **`lib/validate.lua`**: add `local errors = require("lib.errors")` at top; replace every
  `err(msg, code)` with `errors.new(msg, {code=code})`; delete the `err` local function
  (lines 3–5).

- **`lib/st2110.lua`**: add `local errors = require("lib.errors")` at top; replace every
  `st2110_err(msg, field_path, spec_ref, code)` with
  `errors.new(msg, {field_path=field_path, spec_ref=spec_ref, code=code})`; delete the
  `st2110_err` local function (lines 3–13).

- **`lib/ipmx.lua`**: same pattern; replace `ipmx_err(...)` with `errors.new(...)`;
  delete `ipmx_err` local function (lines 3–13).

- **`cli.lua`**: replace seven inline tables `{message=..., line=0, col=0, context=""}` with
  `errors.new(...)` calls. The `die()` function on lines 5–8 already accepts an error table,
  so only the construction sites change.

**Note on `field_path`/`spec_ref` normalization.** The old `st2110_err`/`ipmx_err` defaulted
these to `""` (empty string). `errors.format()` already handles nil with
`if err.field_path and err.field_path ~= ""`. After migration, absent fields will be nil, not
`""`. This is cleaner and already handled by `format()`. **Do not pass `field_path=""` to the
new builder** — just omit it from opts.

The existing test in `ipmx_spec.lua` line 89 asserts `assert.is_string(err.field_path)`. After
this change, field_path will still be a non-nil string when it's present — that test continues
to pass. Verify.

---

### R5 — Move parse loop to `lib/parser.lua`

**The issue.** `parse_sdp.lua` is documented as a "thin facade" but contains the full parsing
implementation: `split_lines` (lines 46–67), `make_err` (removed in R4), `parse_required`
(lines 76–102), `peek_type` (lines 104–107), and the 130-line `M.parse()` body.

**After R4**, `parse_sdp.lua` no longer has `make_err` — but `parse_required` and `split_lines`
still belong in a library module.

**Step 1 — create `lib/parser.lua`**, moving from `parse_sdp.lua`:

```lua
local grammar  = require("lib.grammar")
local errors   = require("lib.errors")
local st2110   = require("lib.st2110")
local ipmx     = require("lib.ipmx")

local M = {}

-- (move split_lines here — keep local)
-- (move parse_required here — keep local, uses errors.new)
-- (move peek_type here — keep local)
-- (move the M.parse body here exactly, returning a plain table — no setmetatable)
--   the final setmetatable({...}, mt) call becomes return { version=..., ... }
--   and the metatable attachment stays in parse_sdp.lua

return M
```

The key change in the moved `M.parse`: replace the final `setmetatable({...}, mt)` with
a plain table return. Mode-based validation (st2110/ipmx) stays inside `parser.parse()` because
it must run before the doc is returned to the caller — only metatable attachment moves out.

**Step 2 — shrink `parse_sdp.lua` to a true facade:**

```lua
local parser    = require("lib.parser")
local validate  = require("lib.validate")
local serialize = require("lib.serialize")
local st2110    = require("lib.st2110")
local ipmx      = require("lib.ipmx")
local dkjson    = require("dkjson")

local M  = {}
local mt = {}
mt.__index = mt

-- (all mt methods unchanged)

function M.parse(text, mode)
  local doc, e = parser.parse(text, mode)
  if not doc then return nil, e end
  return setmetatable(doc, mt)
end

function M.new(t)
  return setmetatable(t, mt)
end

return M
```

**Step 3 — no new tests.** All existing tests exercise behavior through `parse_sdp.lua`; they
continue to pass unchanged. Run `busted spec/` to confirm.

**Watch out:** `lib/parser.lua` must not `require("parse_sdp")` — that would be a circular
dependency. Mode-based validation (st2110, ipmx) is wired inside parser.parse, not in the facade.

---

### R6 — `fmtp_params` strictness + `ntp=` format validation

**Issue A — `fmtp_params` silently drops malformed pairs.**
`lib/st2110.lua:79-81`: the gmatch loop silently skips any semicolon-separated token that has
no `=` sign. A malformed fmtp like `96 sampling=YCbCr; =broken; depth=10` will parse the valid
pairs and ignore `=broken`. If the required parameter (`sampling`) is present elsewhere in the
value, the check passes despite the malformed pair. This contradicts strictness.

**Issue B — `ntp=` value not validated.**
`lib/st2110.lua:35-37`: `ntp=<addr>` accepts any non-empty string as the address, including
strings with whitespace, which cannot be valid network addresses.

**Step 1 — write failing tests in `spec/st2110_spec.lua`:**

```lua
-- in the "ts-refclk value format" describe block:

it("rejects ntp= with whitespace in address", function()
  -- "ntp=has space" cannot be a valid address
  local doc = sdp.parse(with_tsrefclk("ntp=has space"))
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(ok)
  assert.is_table(err)
  assert.matches("ts%-refclk", err.message)
end)

-- in a new "fmtp_params validation" describe block:

it("rejects video fmtp with a malformed (no equals) parameter pair", function()
  local text = table.concat({
    "v=0", "o=- 1234567890 1 IN IP4 192.168.1.1", "s=ST2110 Video", "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=video 5000 RTP/AVP 96",
    "c=IN IP4 239.100.0.1/64",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2; MALFORMED; depth=10",  -- no '=' in second pair
    "a=mediaclk:direct=0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
  }, "\r\n")
  local doc = sdp.parse(text)
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(ok)
  assert.is_table(err)
  assert.matches("fmtp", err.message)
end)
```

**Step 2 — fix `fmtp_params` in `lib/st2110.lua`:**

Change the return signature to `params, err_msg` and detect malformed pairs:

```lua
local function fmtp_params(value)
  local params_str = value:match("^%d+%s+(.+)$")
  if not params_str then return {} end
  local params = {}
  for kv in params_str:gmatch("[^;]+") do
    local trimmed = kv:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      local k, v = trimmed:match("^([^=%s]+)%s*=%s*(.-)$")
      if not k then
        return nil, "malformed fmtp parameter: " .. trimmed
      end
      params[k] = v
    end
  end
  return params
end
```

Update both callers (video block ≈ line 172, audio block ≈ line 183) to propagate the error:

```lua
local params, fmtp_err = fmtp_params(fmtp.value or "")
if not params then
  return nil, errors.new("invalid fmtp: " .. fmtp_err, {
    field_path = mpath .. ".attributes[fmtp]",
    spec_ref   = "ST 2110-20 §7.2",
    code       = "INVALID_VALUE",
  })
end
```

**Step 3 — fix `ntp=` validation in `valid_tsrefclk`** (`lib/st2110.lua:35-37`):

```lua
local addr = value:match("^ntp=(.+)$")
if addr then
  if addr:match("%s") then
    return nil, "invalid ts-refclk ntp address"
  end
  return true
end
```

---

### R7 — Test audit: additions and deletions

This milestone cleans up test debt introduced with earlier milestones and adds coverage for
untested code paths. Run `busted spec/` in clean state before starting to establish baseline.

**Tests to add — `spec/sdp_spec.lua`:**

```lua
-- in "sdp — doc object" describe block:
it("doc:validate() with unknown mode returns nil, err", function()
  local doc = sdp.parse(minimal)
  local ok, err = doc:validate("bogus_mode")
  assert.is_nil(ok)
  assert.is_table(err)
  assert.truthy(err.message:find("unknown mode", 1, true))
end)
```

This tests the error path at `parse_sdp.lua:17` which is currently unreachable from any test.

**Tests to add — `spec/st2110_spec.lua`** (all in the "ts-refclk value format" describe block):

```lua
it("accepts bare 'gal'", function()
  -- gal (Galileo) is a valid clock source; accepted by code but never tested
  local doc = sdp.parse(with_tsrefclk("gal"))
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(err)
  assert.equal(true, ok)
end)

it("accepts bare 'glonass'", function()
  local doc = sdp.parse(with_tsrefclk("glonass"))
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(err)
  assert.equal(true, ok)
end)

it("accepts ntp= with a valid address", function()
  local doc = sdp.parse(with_tsrefclk("ntp=127.0.0.1"))
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(err)
  assert.equal(true, ok)
end)

it("accepts ptp= with version and GMID but no domain", function()
  -- domain is optional; ptp=version:gmid (no third segment) must be valid
  local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55"))
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(err)
  assert.equal(true, ok)
end)
```

In the "mediaclk value format" describe block:

```lua
it("accepts 'direct=' with a negative integer offset", function()
  -- negative offsets are syntactically valid per spec; the regex allows them
  local doc = sdp.parse(with_mediaclk("direct=-100"))
  assert.is_table(doc)
  local ok, err = doc:validate("st2110")
  assert.is_nil(err)
  assert.equal(true, ok)
end)
```

**Tests to add — new `describe("validate.sdp direct")` in `spec/sdp_spec.lua`:**

`lib/validate.lua` is only exercised indirectly through `sdp.parse`. Add a small direct-unit
block so regressions in the validator are locatable without running the full parser:

```lua
describe("validate.sdp direct unit tests", function()
  local validate = require("lib.validate")
  local sdp      = require("parse_sdp")
  local minimal_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"

  it("returns true for a fully valid doc", function()
    local doc = sdp.parse(minimal_text)
    local ok, err = validate.sdp(doc)
    assert.equal(true, ok)
    assert.is_nil(err)
  end)

  it("returns nil, err for non-table argument", function()
    local ok, err = validate.sdp("not a table")
    assert.is_nil(ok)
    assert.is_table(err)
  end)

  it("returns nil, err when version is not '0'", function()
    local doc = sdp.parse(minimal_text)
    doc.version = "1"
    local ok, err = validate.sdp(doc)
    assert.is_nil(ok)
    assert.equal("INVALID_VALUE", err.code)
  end)

  it("returns nil, err when origin is missing", function()
    local doc = sdp.parse(minimal_text)
    doc.origin = nil
    local ok, err = validate.sdp(doc)
    assert.is_nil(ok)
    assert.equal("MISSING_FIELD", err.code)
  end)

  it("returns nil, err when session.name is empty string", function()
    local doc = sdp.parse(minimal_text)
    doc.session.name = ""
    local ok, err = validate.sdp(doc)
    assert.is_nil(ok)
    assert.equal("MISSING_FIELD", err.code)
  end)
end)
```

**Tests to delete** (after R2 removes `to_sdp`):

- Entire `describe("to_sdp")` block in `spec/sdp_spec.lua` (≈ lines 896–922) — three tests,
  all testing a removed method.

**Tests to delete** (low-value existence checks in `spec/sdp_spec.lua`):

- `describe("to_json")`: delete "to_json method exists on parsed doc" and
  "sdp.new({}) has to_json method" — these assert that a method is a function, which will always
  be true as long as the module loads. They add no behavioral coverage and can mask real failures.
  The remaining to_json tests ("returns a string", "output is valid JSON", etc.) are worth keeping.

**Done when:** `busted spec/` passes with zero failures and all items above are addressed.

---

### R8 — CLI: merge into `parse_sdp.lua`, add argparse, shebang ✓

**Goal.** Users interact with one file, not two. `parse_sdp.lua` is both the library and the
executable. `cli.lua` is deleted.

**Design decisions:**

- `argparse` (LuaRocks) replaces the hand-rolled `parse_flags`. It handles `--help` / `-h`,
  argument errors, subcommand dispatch, and usage text. It is only `require`d inside the
  detect-if-main block so it is never a library dependency.
- **Help is first-class.** Every subcommand, option, and flag gets a description string.
  The top-level parser gets an epilog with short examples so `parse_sdp --help` is
  immediately useful to a new user without reading any docs.
- Detect-if-main check: `if arg and arg[0] and arg[0]:match("parse_sdp") then`. When
  `require("parse_sdp")` is called by busted or application code, `arg[0]` is the outer
  script and the block is skipped. When `lua parse_sdp.lua` is run directly, `arg[0]` matches
  and the CLI runs, always ending in `os.exit()`.
- `#!/usr/bin/env lua` as the first line; `chmod +x parse_sdp.lua` so it can be invoked
  directly (or symlinked as `parse_sdp`).

**Step 1 — install argparse:**

```sh
luarocks install argparse
```

Add `argparse` to the rockspec `dependencies` when the rockspec is written.

**Step 2 — update `parse_sdp.lua`:**

Add shebang as the very first line:

```lua
#!/usr/bin/env lua
```

Add the CLI block immediately before `return M`:

```lua
-- ── CLI (detect-if-main) ──────────────────────────────────────────────────────
if arg and arg[0] and arg[0]:match("parse_sdp") then
  local argparse = require("argparse")

  local function die(err_table)
    io.stderr:write(errors.format(err_table) .. "\n")
    os.exit(1)
  end

  local function read_input(file)
    if file then
      local f, ioerr = io.open(file, "r")
      if not f then die(errors.new("cannot open file: " .. (ioerr or file))); return end
      local text = f:read("*a")
      f:close()
      return text
    end
    return io.read("*a")
  end

  local ap = argparse("parse_sdp", "Parse, validate, and serialize SDP (RFC 4566 / ST 2110 / IPMX).")
  ap:epilog(table.concat({
    "Examples:",
    "  parse_sdp parse session.sdp",
    "  parse_sdp parse --mode st2110 --pretty session.sdp",
    "  parse_sdp parse < session.sdp | parse_sdp serialize",
    "  parse_sdp serialize session.json",
  }, "\n"))
  ap:command_target("command")

  local cmd_parse = ap:command("parse", "Parse and validate an SDP file; output JSON.")
  cmd_parse:argument("file", "Path to .sdp file. Reads stdin if omitted."):args("?")
  cmd_parse:option("--mode", "Validation tier: 'st2110' or 'ipmx'. Defaults to RFC 4566 only.")
  cmd_parse:flag("--pretty", "Pretty-print JSON output with indentation.")

  local cmd_ser = ap:command("serialize", "Convert a JSON SDP document back to SDP text.")
  cmd_ser:argument("file", "Path to .json file. Reads stdin if omitted."):args("?")

  local parsed = ap:parse()

  if parsed.command == "parse" then
    local text = read_input(parsed.file)
    local doc, perr = M.parse(text, parsed.mode)
    if not doc then die(perr) end
    local encode_opts = parsed.pretty and { indent = true } or nil
    io.write(dkjson.encode(doc, encode_opts) .. "\n")
    os.exit(0)

  elseif parsed.command == "serialize" then
    local json_text = read_input(parsed.file)
    local tbl, _, jsonerr = dkjson.decode(json_text)
    if not tbl then
      die(errors.new("invalid JSON: " .. (jsonerr or "parse error")))
    end
    local doc = M.new(tbl)
    local ok, result = pcall(function() return doc:to_sdp() end)
    if not ok then
      die(errors.new("serialize error: " .. tostring(result)))
    end
    io.write(result)
    os.exit(0)
  end
end
```

Note: `errors`, `dkjson`, and `M` are already in scope from the library section above the block.

**Step 3 — update `spec/cli_spec.lua`:**

Replace every `lua cli.lua` with `lua parse_sdp.lua` (two locations: the `run()` helper and the
`fixture_json()` helper inside the serialize describe block).

Add help tests:

```lua
it("--help exits 0 and prints usage", function()
  local stdout, _, code = run("--help")
  assert.equal(0, code)
  assert.truthy(stdout:find("parse_sdp", 1, true))
end)

it("parse --help exits 0 and mentions --mode", function()
  local stdout, _, code = run("parse --help")
  assert.equal(0, code)
  assert.truthy(stdout:find("--mode", 1, true))
end)
```

**Step 4 — delete `cli.lua`.**

**Step 5 — update `CLAUDE.md`:**

- Remove `cli.lua` from the repository layout table.
- Add a note that `parse_sdp.lua` is dual-purpose: library entry point and CLI executable.

**Step 6 — `chmod +x parse_sdp.lua` in the repo** (or document it; the shebang is inert without it).

**Done when:** `busted spec/` passes (including the new `--help` tests); `parse_sdp --help` and
`parse_sdp parse --help` print actionable usage with examples; `cli.lua` is gone.

---

### R9 — Collapse `lib/` into `parse_sdp.lua` ✓

**Goal.** The library is a single file plus external dependencies (lpeg, dkjson, argparse). No
`lib/` directory. The file is large but navigable via section banner comments.

**Approach.**

All seven `lib/` modules inlined into `parse_sdp.lua` as local tables in dependency order:
`errors → util → grammar → validate → serialize → st2110 → ipmx → parser`

Each section opens with a `-- ── Section Name ──` banner. Private locals (LPEG patterns, helper
functions) remain at file scope in the section where they originate. `find_attr` is hoisted to one
declaration after `util` and shared by `st2110` and `ipmx`. All intra-lib `require("lib.xxx")`
calls are removed; the locals are already in scope.

`M._grammar` and `M._errors` added to the returned module for spec access (not public contract).
`spec/sdp_spec.lua` and `spec/errors_spec.lua` updated to use these instead of direct lib requires.
`lib/` directory deleted.

**Done when:** `busted spec/` passes with 169 successes; `lib/` is gone.

---

### R10 — DRY / clarity pass ✓

**Goal.** Address code-quality issues identified during review: duplicated logic, redundant naming, comment rot, and a correctness documentation gap.

- [x] `rtpmap_parse` replaces separate `rtpmap_clock_rate` / `rtpmap_encoding` helpers
- [x] `fmtp_params` lifted above the encoding branch in `st2110.validate` (was called once per branch)
- [x] `each_dup_group(doc, spec_ref, cb)` extracts duplicated DUP iteration from `st2110.validate` and `ipmx.validate`
- [x] `attr_err(msg, mpath, attr, spec_ref, code)` eliminates 21 repeated error-table constructions
- [x] Module entry points renamed: `st2110.validate`, `ipmx.validate`, `serialize.to_sdp`
- [x] `check_privacy` hoisted from closure to module-level local
- [x] Milestone tags (`M16:`, `M17:`) removed from inline comments
- [x] Redundant ldoc stripped from five one-liner pass-through grammar functions
- [x] `valid_hkep` addr token documented with comment explaining why format is not checked

**Done when:** `busted spec/` passes with 226 successes; 1337 → 1256 lines.

---

### M22 — Validation completeness audit (gap closure 2026-05-13)

**Done when:** All gaps identified in the fifth round of spec/code audit are addressed. Every
required and optional SDP field mentioned in ST 2110-20, ST 2110-22, ST 2110-30, ST 2110-40,
ST 2110-41, TR-10-1, TR-10-2, TR-10-3, and TR-10-11 is either validated or explicitly noted
as out-of-scope for a per-SDP validator (device-capability requirements).

---

#### Gap 1 — `VALID_TCS` missing `UNSPECIFIED` (ST 2110-20:2017 §7.6)

**Source:** SMPTE ST 2110-20:2017 §7.6 lists exactly 10 TCS values; `UNSPECIFIED` is on the list.
The code has 9 — `UNSPECIFIED` is absent. Any SDP with `TCS=UNSPECIFIED` is wrongly rejected.

- [x] Add `["UNSPECIFIED"]=true` to `VALID_TCS` in `parse_sdp.lua`
- [x] Test: `TCS=UNSPECIFIED` accepted
- [x] Test: existing `TCS=SDR` and `TCS=PQ` still accepted

---

#### Gap 2 — `VALID_COLORIMETRY` missing `XYZ`, has spurious `ALPHA` (ST 2110-20:2017 §7.5)

**Source:** SMPTE ST 2110-20:2017 §7.5 lists exactly 8 colorimetry values:
`BT601 BT709 BT2020 BT2100 ST2065-1 ST2065-3 UNSPECIFIED XYZ`.
The code has `ALPHA` in place of `XYZ`. Consequence: `colorimetry=XYZ` is wrongly rejected;
`colorimetry=ALPHA` is wrongly accepted. `ALPHA` is not in the 2017 standard — it may appear
in the 2022 revision, so it is retained alongside the addition of `XYZ`.

- [x] Add `["XYZ"]=true` to `VALID_COLORIMETRY`; retain `ALPHA` pending 2022-edition confirmation
- [x] Test: `colorimetry=XYZ` accepted
- [x] Test: `colorimetry=BT709` still accepted

---

#### Gap 3 — SSN validated by prefix only; year not checked (ST 2110-20:2017 §7.2)

**Source:** ST 2110-20:2017 §7.2: *"Senders implementing this standard shall signal the value
ST2110-20:2017."* The 2022 edition signals `ST2110-20:2022`. Similarly for ST 2110-22
(`ST2110-22:2019`) and ST 2110-41. The current code uses prefix-only LPEG patterns
(`P("ST2110-20:")`) which accept garbage like `ST2110-20:badvalue`.

**Fix:** Replace prefix-only patterns with patterns that require a 4-digit numeric year:
`P("ST2110-20:") * (R("09")^4) * P(-1)` — accepts `ST2110-20:2017`, `ST2110-20:2022`, and
any future 4-digit year. Rejects `ST2110-20:`, `ST2110-20:foo`, `ST2110-20:20x2`, etc.

New LPEG constants defined once and shared across all SSN validation sites:
```lua
local _ssn_year  = R("09") * R("09") * R("09") * R("09")
local _ssn20_pat = P("ST2110-20:") * _ssn_year * P(-1)
local _ssn22_pat = P("ST2110-22:") * _ssn_year * P(-1)   -- JPEG-XS / ST 2110-22
local _ssn41_pat = P("ST2110-41:") * _ssn_year * P(-1)
```

- [x] Define `_ssn_year`, `_ssn20_pat`, `_ssn22_pat`, `_ssn41_pat` in `parse_sdp.lua`
- [x] Replace existing ST 2110-20 SSN check with `_ssn20_pat`
- [x] Replace existing ST 2110-41 SSN Lua `string.match` with `_ssn41_pat`
- [x] Test: `SSN=ST2110-20:2017` accepted; `SSN=ST2110-20:2022` accepted
- [x] Test: `SSN=ST2110-20:badvalue` rejected; `SSN=ST2110-20:` rejected (no year)
- [x] Test: `SSN=ST2110-41:2024` still accepted; `SSN=ST2110-41:` rejected

---

#### Gap 4 — `channel-order` group symbols not validated (ST 2110-30:2017 §6.2.2 Table 1)

**Source:** ST 2110-30:2017 §6.2.2 Table 1 defines exactly 9 named group symbols
(`M`, `DM`, `ST`, `LtRt`, `51`, `71`, `222`, `SGRP`, `U01`–`U64`) and states the syntax is
`SMPTE2110.(<group>[,<group>...])`. The current `_chan_ord_pat` accepts any non-empty string
inside the parentheses: `SMPTE2110.(garbage)` passes; multiple comma-separated groups are
technically accepted (the pattern is permissive) but individual symbols are not validated.

**Fix:** Replace `_chan_ord_pat` (the simple LPEG structural check) with a proper
`valid_channel_order` that:
1. Checks the `SMPTE2110.(...)` wrapper
2. Splits on commas
3. Validates each token against `VALID_CHAN_GROUPS` or the `Unn` range (U01–U64)

```lua
local VALID_CHAN_GROUPS = {
  ["M"]=true,["DM"]=true,["ST"]=true,["LtRt"]=true,
  ["51"]=true,["71"]=true,["222"]=true,["SGRP"]=true,
}
```

- [x] Define `VALID_CHAN_GROUPS` and rewrite `valid_channel_order` in `parse_sdp.lua`
- [x] Remove `_chan_ord_pat` (now unused)
- [x] Test: `SMPTE2110.(ST)` accepted; `SMPTE2110.(M,DM)` accepted; `SMPTE2110.(51,ST)` accepted
- [x] Test: `SMPTE2110.(U08)` accepted; `SMPTE2110.(U64)` accepted; `SMPTE2110.(U00)` rejected
- [x] Test: `SMPTE2110.(U65)` rejected; `SMPTE2110.(U99)` rejected
- [x] Test: `SMPTE2110.(foo)` rejected; `SMPTE2110.()` rejected

---

#### Gap 5 — Multicast TTL not range-validated (ST 2110-10:2022 §6.5)

**Source:** The connection address `c=IN IP4 239.x.x.x/TTL` requires a valid TTL 1–255.
The current check only confirms a digit string is present after `/`; `/0` and `/999` both pass.

- [x] Update `valid_connection_address` to parse TTL as an integer and reject values outside 1–255
- [x] Test: `239.100.0.1/64` accepted; `239.100.0.1/255` accepted
- [x] Test: `239.100.0.1/0` rejected (TTL=0 invalid); `239.100.0.1/256` rejected

---

#### Gap 6 — JPEG-XS (`jxsv`) entirely unimplemented (TR-10-11 / ST 2110-22 / IPMX JPEG-XS Profile)

**Source:** The IPMX JPEG-XS Video Profile (v1.0-2025-12) and VSF TR-10-11 define JPEG-XS as a
major IPMX media type. SMPTE ST 2110-22:2019 defines compressed video SDP format.
The rtpmap encoding name is `jxsv` (clock rate 90000). No code currently handles this.

**ST 2110-level checks** (new `elseif enc == "jxsv"` branch in `st2110.validate`):

| fmtp param | Required? | Validation rule | Spec |
|---|---|---|---|
| `sampling` | Required | VALID_SAMPLING enum | ST 2110-20 §7.4.1 |
| `width` | Required | Positive integer | ST 2110-22 §7 |
| `height` | Required | Positive integer | ST 2110-22 §7 |
| `exactframerate` | Required | Positive int or N/D fraction | ST 2110-22 §7 |
| `depth` | Required | Positive integer | ST 2110-22 §7 |
| `TCS` | Required | VALID_TCS enum | ST 2110-20 §7.6 |
| `colorimetry` | Required | VALID_COLORIMETRY enum | ST 2110-20 §7.5 |
| `PM` | Required | `2110GPM` or `2110BPM` | ST 2110-20 §6.3 |
| `SSN` | Required | `_ssn22_pat` (ST2110-22:YYYY) | ST 2110-22 §7 |
| `profile` | Required | Non-empty string | TR-10-11 / IPMX JPEG-XS Profile §6.1.4 |
| `level` | Required | Non-empty string | TR-10-11 / IPMX JPEG-XS Profile §6.1.4 |
| `sublevel` | Required | Non-empty string | TR-10-11 / IPMX JPEG-XS Profile §6.1.4 |
| `transmode` | Required | Non-negative integer | TR-10-11 / IPMX JPEG-XS Profile §6.1.4 |
| `packetmode` | Required | Non-negative integer | TR-10-11 / IPMX JPEG-XS Profile §6.1.4 |
| `TP` | Optional | `2110TPNL` or `2110TPW` (ST 2110-22 traffic profiles only) | ST 2110-22 §7 |
| `RANGE` | Optional | VALID_RANGE enum | ST 2110-20 §7.3 |
| `MAXUDP` | Optional | Positive integer | ST 2110-22 §7 |
| `CMAX` | Optional | Positive integer | ST 2110-21 |
| `fbblevel` | Optional | Positive integer | TR-10-11 §12 |

Note: `TP` for JPEG-XS/ST 2110-22 is restricted to `2110TPNL` or `2110TPW` — NOT `2110TPN`
(which is only for uncompressed video per ST 2110-10/ST 2110-20). This is a stricter enum.
A separate `VALID_TP_22` table is defined.

**IPMX-level checks** (in `ipmx.validate`):
- The existing IPMX fmtp `IPMX` marker check already applies to JPEG-XS blocks automatically.
- No additional IPMX-specific checks needed beyond the ST 2110 tier for JPEG-XS.

- [x] Define `VALID_TP_22 = { ["2110TPNL"]=true, ["2110TPW"]=true }` in `parse_sdp.lua`
- [x] Add `elseif enc == "jxsv"` branch in `st2110.validate` with all checks above
- [x] Write minimal valid JPEG-XS ST 2110 fixture SDP
- [x] Write minimal valid JPEG-XS IPMX fixture SDP
- [x] Tests in `spec/st2110_spec.lua`:
  - Valid JPEG-XS SDP → success
  - Missing `profile` → error naming `profile`
  - Missing `level` → error naming `level`
  - Missing `sublevel` → error naming `sublevel`
  - Missing `transmode` → error naming `transmode`
  - Missing `packetmode` → error naming `packetmode`
  - Missing any standard video param (`sampling`, `width`, `height`, etc.) → error
  - `SSN=ST2110-20:2017` on a jxsv block → rejected (wrong SSN prefix)
  - `SSN=ST2110-22:2019` → accepted
  - `TP=2110TPN` on jxsv block → rejected (not valid for compressed video)
  - `TP=2110TPNL` on jxsv block → accepted
  - `fbblevel=4` → accepted; `fbblevel=0` → rejected (must be positive)
- [x] Tests in `spec/ipmx_spec.lua`:
  - Valid IPMX JPEG-XS SDP (with IPMX marker in fmtp) → success
  - IPMX JPEG-XS SDP without IPMX marker → rejected

---

#### Gap 7 — IPMX media port not validated (TR-10-1 §7)

**Source:** TR-10-1 §7: *"All IPMX Media streams shall have a UDP destination port value that
is even and that is greater than 1024."* Nothing validates port range at any tier.

- [x] Add port range check in `ipmx.validate` RTCP loop (each non-USB media block)
- [x] Test: port 5000 (even, >1024) → accepted
- [x] Test: port 1025 (odd, >1024) → rejected (odd)
- [x] Test: port 1024 (even, not >1024) → rejected (not >1024)
- [x] Test: port 1022 → rejected (even but ≤1024)

---

#### Gap 8 — IPMX audio: `a=ptime` required; `AM824` rejected (TR-10-3)

**Sources:**
- TR-10-3 / IPMX PCM Audio Profile §6.1.4: *"The sender shall populate ... Packet time"* —
  ptime is required for IPMX audio, not optional.
- TR-10-3 defines only L16 and L24 as valid IPMX encodings. AM824 (ST 2110-31) is valid at
  the generic ST 2110 tier but not at the IPMX tier.

Both checks added in the IPMX fmtp marker loop in `ipmx.validate`.

- [x] IPMX audio: require `a=ptime`; if absent → error with spec_ref "TR-10-3 §8 / IPMX PCM Audio Profile §6.1.4"
- [x] IPMX audio: reject `AM824` rtpmap encoding; error with spec_ref "TR-10-3 §8"
- [x] Test: valid IPMX audio with L24 and ptime → success
- [x] Test: IPMX audio missing ptime → rejected
- [x] Test: IPMX audio with AM824 → rejected
- [x] Test: generic ST 2110 audio with AM824 → still accepted (not an IPMX restriction)

---

#### Gap 9 — IPMX baseband param format not validated (TR-10-2 §11, TR-10-3 §10.3)

**Source:** TR-10-2 defines optional fmtp params `measuredpixclk`, `vtotal`, `htotal` for IPMX
uncompressed video; TR-10-3 defines optional `measuredsamplerate` for IPMX audio. All four
must be positive integers if present. Currently they are silently ignored.

These are validated in the IPMX fmtp marker loop, after the IPMX marker check.

- [x] IPMX video: if `measuredpixclk` present, validate as positive integer (TR-10-2 §11)
- [x] IPMX video: if `vtotal` present, validate as positive integer (TR-10-2 §11)
- [x] IPMX video: if `htotal` present, validate as positive integer (TR-10-2 §11)
- [x] IPMX audio: if `measuredsamplerate` present, validate as positive integer (TR-10-3 §10.3)
- [x] Test: `measuredpixclk=148550104` accepted; `measuredpixclk=notanumber` rejected
- [x] Test: `vtotal=1125` accepted; `vtotal=0` rejected (must be positive)
- [x] Test: `htotal=2200` accepted; `htotal=-1` rejected (must be positive)
- [x] Test: `measuredsamplerate=47952` accepted; `measuredsamplerate=garbage` rejected

---

#### Gap 10 — `a=extmap` ID upper bound not enforced (RFC 5285)

**Source:** RFC 5285 §4.2: extension IDs are 1–14 for one-byte header form, 1–255 for two-byte.
The current `valid_extmap` checks `id >= 1` but not `id <= 255`. `a=extmap:9999 urn:foo` passes.

- [x] Add `id > 255` check in `valid_extmap`; error: "a=extmap entry count must be 1-255 (RFC 5285)"
- [x] Test: `a=extmap:255 urn:x-test` accepted (max valid)
- [x] Test: `a=extmap:256 urn:x-test` rejected

---

**Spec references for M22:**
- SMPTE ST 2110-20:2017 §7.5 (colorimetry), §7.6 (TCS), §7.2 (SSN)
- SMPTE ST 2110-22:2019 §7 (compressed video SDP, TP values)
- SMPTE ST 2110-30:2017 §6.2.2 Table 1 (channel-order groups)
- SMPTE ST 2110-10:2022 §6.5 (multicast TTL)
- VSF TR-10-1 (2024-02-23) §7 (port range), §8.7 (RTCP)
- VSF TR-10-2 (2024-02-23) §11 (baseband video params)
- VSF TR-10-3 (2024-02-23) §8, §10.3 (ptime required, measuredsamplerate, L16/L24 only)
- VSF TR-10-11 (2024-02-23) §10, §12 (JPEG-XS SDP, codec params)
- IPMX JPEG-XS Video Profile v1.0-2025-12 §6.1.4 (required sender signaling)
- IPMX PCM Digital Audio Profile v1.0-2025-12 §6.1.4 (packet time required)
- RFC 5285 §4.2 (extmap ID range)
