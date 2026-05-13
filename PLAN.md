# Implementation Plan

## Guiding Principles

- **Test first.** Every milestone begins with failing tests. No implementation starts without a spec.
- **Strict by spec.** RFC 4566 compliance is pedantic and non-negotiable. Reject anything the spec rejects. Do not invent lenient behaviour.
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

### M3 — Required session fields

**Done when:** `sdp.parse` returns a doc table for minimal valid SDP; returns `nil, err` for anything invalid.

Covers: `v=`, `o=`, `s=`, `t=` in required order.

- [ ] `lib/grammar.lua`: patterns for each field value format
- [ ] `parse_sdp.lua`: `parse(text)` wires tokenizer → field parsers → table
- [ ] Error table shape: `{ message, line, col, context }`
- [ ] Tests:
  - Minimal valid SDP (`v o s t`) → doc table
  - Missing `v=` → error at line 1
  - Wrong order (e.g. `s=` before `o=`) → error with correct position
  - Bad `o=` format (wrong field count) → error

---

### M4 — Optional session fields

**Done when:** All optional session-level fields parse correctly.

Covers: `i=`, `u=`, `e=`, `p=`, `c=`, `b=`, `a=` (zero or more of each where allowed).

- [ ] Tests:
  - SDP with every optional field present → correct table
  - Multiple `e=`, `p=`, `b=`, `a=` → arrays in correct order
  - `c=` with IPv4 and IPv6 addresses
  - `b=` with `AS:`, `CT:`, `X-` prefixes

---

### M5 — Media blocks

**Done when:** `sdp.parse` handles one or more `m=` blocks with their per-media fields.

- [ ] `m=` line: type, port, `/count`, proto, format list
- [ ] Per-media: `i=`, `c=`, `b=`, `a=` (same rules as session level)
- [ ] Multiple media blocks in sequence
- [ ] Tests:
  - One video `m=` block with attributes
  - Two media blocks (video + audio)
  - `m=` with port count (`/2`)
  - Missing required `m=` field → error

---

### M6 — doc object

**Done when:** `sdp.parse` returns a table with working methods; `sdp.new` wraps any table.

- [ ] Metatable on the table returned by `parse`
- [ ] `sdp.new(table)` attaches same metatable, no validation
- [ ] `doc:is_sdp()` → runs RFC 4566 validate, returns bool
- [ ] `doc:validate()` and `doc:validate("sdp")` → `true` or `nil, err`
- [ ] Tests:
  - Parsed doc has methods
  - `sdp.new({})` has methods
  - `doc:is_sdp()` true for valid, false for mutated-invalid
  - `doc:validate()` error table has expected fields

---

### M7 — Serializer

**Done when:** `doc:serialize()` produces strict RFC 4566 SDP text; round-trip holds.

- [ ] `lib/serialize.lua`: field output in RFC 4566 §5 order
- [ ] CRLF line endings
- [ ] `doc:serialize()` method
- [ ] Tests:
  - Serialized output re-parses without error
  - Field order matches spec (`v o s i u e p c b t a m ...`)
  - Round-trip: `parse(serialize(parse(text)))` equals `parse(text)` (deep equal)

---

### M8 — ST 2110 validation

**Done when:** `sdp.parse(text, "st2110")` and `doc:validate("st2110")` work correctly.

- [ ] `lib/st2110.lua`: validates required attributes on parsed doc
- [ ] `doc:is_st2110()` → bool
- [ ] Required checks:
  - At least one `m=` block
  - `a=ts-refclk` present and format-valid
  - `a=mediaclk` present
  - `a=rtpmap` with correct clock rate for media type
  - `a=fmtp` present; key=value pairs validated per sub-standard
- [ ] Tests:
  - Valid ST 2110-20 (video) SDP → success
  - Valid ST 2110-30 (audio) SDP → success
  - Missing `a=ts-refclk` → error with `field_path` and `spec_ref`
  - Invalid `fmtp` (missing `sampling`) → error
  - Generic valid SDP fails ST 2110 validate

---

### M9 — IPMX validation

**Done when:** `sdp.parse(text, "ipmx")` and `doc:validate("ipmx")` work correctly.

- [ ] `lib/ipmx.lua`: validates IPMX-specific attributes (runs ST 2110 first)
- [ ] `doc:is_ipmx()` → bool
- [ ] Tests:
  - Valid IPMX SDP → success
  - ST 2110 SDP (non-IPMX) fails IPMX validate
  - Missing IPMX `a=extmap` → error

---

### M10 — JSON output

**Done when:** `doc:to_json()` returns a valid JSON string.

- [ ] Wire dkjson in `parse_sdp.lua`
- [ ] `doc:to_json()` method
- [ ] Tests:
  - `to_json()` output is valid JSON (parse it back)
  - All doc fields present in JSON output

---

### M11 — CLI: `parse` subcommand

**Done when:** `parse_sdp parse [--mode MODE] [--pretty] [file]` works end-to-end.

- [ ] `cli.lua`: argument parsing, stdin fallback, exit codes
- [ ] JSON to stdout on success; JSON error to stderr on failure
- [ ] Exit `0` success, `1` parse error
- [ ] Integration tests (via `io.popen`)

---

### M12 — CLI: `serialize` subcommand

**Done when:** `parse_sdp serialize [file.json]` produces valid SDP on stdout.

- [ ] Read JSON, call `sdp.new()`, call `doc:serialize()`
- [ ] Integration tests

---

### M13 — Error UX

**Done when:** Every error message is actionable without reading the spec.

- [ ] Caret display: offending line + `^` at column
- [ ] ST 2110 / IPMX errors include spec clause (`ST 2110-20 §7.2`)
- [ ] Consistent error codes (`MISSING_FIELD`, `INVALID_VALUE`, `WRONG_ORDER`, etc.)
- [ ] Review all existing error messages for clarity

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
