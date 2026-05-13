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

   ```
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
