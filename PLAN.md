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
