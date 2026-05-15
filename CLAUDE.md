# CLAUDE.md — parse_sdp

Context and conventions for Claude Code working in this repo.

## Project Purpose

`parse_sdp` is a Lua 5.5 + LPEG library that parses, validates, and serializes SDP
(Session Description Protocol) files. Three validation tiers:
RFC 4566 (generic SDP) → SMPTE ST 2110 → IPMX.

**Strictness is a primary feature**, but it is *spec-grounded*, not opinion.
The library rejects any SDP that the relevant standard explicitly forbids and
nothing else. There is no lenient mode, and no "obviously broken but the spec
is silent" mode either. See **Validation Strictness Principle** below for the
exact boundary.

**Keep it tight.** If a module is growing, stop and refactor before adding more.
Prefer fewer, well-named things over many small helpers.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.5 |
| Parsing | LPEG |
| JSON | dkjson (pure Lua, LuaRocks) |
| Tests | busted — `busted spec/` |
| Container | Docker |

## Repository Layout

```
parse_sdp.lua        single-file library AND CLI executable (dual-purpose)
                     `require("parse_sdp")` loads the library; running it
                     directly (`lua parse_sdp.lua` or `./parse_sdp.lua`)
                     activates the argparse CLI (parse / serialize subcommands)
                     Internal sections (in order): errors · util · grammar ·
                     validate · serialize · st2110 · ipmx · parser · public API · CLI
spec/
  sdp_spec.lua       RFC 4566 parser tests
  st2110_spec.lua    ST 2110 validation tests
  ipmx_spec.lua      IPMX validation tests
  errors_spec.lua    error formatting tests
  cli_spec.lua       CLI integration tests
  fixtures/          sample .sdp files used by tests
examples/
  examples.lua       runnable API walkthrough (lua examples/examples.lua)
  generic/           RFC 4566 SDP samples — valid/ and invalid/
  st2110/            ST 2110 SDP samples — valid/ and invalid/
  ipmx/              IPMX SDP samples — valid/ and invalid/
```

## Public API

```lua
local sdp = require("parse_sdp")

-- Entry points (module-level)
local doc, err = sdp.parse(text)            -- parse + validate RFC 4566
local doc, err = sdp.parse(text, "st2110") -- parse + validate ST 2110
local doc, err = sdp.parse(text, "ipmx")   -- parse + validate IPMX
local doc       = sdp.new(table)            -- wrap table as doc (no validation)

-- doc methods (via metatable)
doc:validate()            -- validate as RFC 4566; true or nil, err
doc:validate("st2110")    -- validate as ST 2110; true or nil, err
doc:validate("ipmx")      -- validate as IPMX; true or nil, err
doc:is_sdp()              -- bool
doc:is_st2110()           -- bool
doc:is_ipmx()             -- bool
doc:to_sdp()           -- → SDP text string (CRLF, strict RFC 4566 ordering)
doc:to_json()             -- → JSON string (via dkjson)

-- doc is also a plain table
doc.version
doc.origin.unicast_address
doc.session.name
doc.media[1].port
```

## Validation Strictness Principle

Every validation check in `parse_sdp.lua` must be grounded in **explicit
normative spec text**. Three polarities of normative text count:

1. **Positive requirements** (*"shall"*, *"MUST"*, *"is required"*) — if the
   spec says a field must be present or take a specific form, the validator
   rejects input that omits it or violates the form.
2. **Prohibitions** (*"shall not"*, *"MUST NOT"*, *"is forbidden"*) — if the
   spec forbids a value, combination, or construction, the validator rejects it.
3. **Optional features with defined values** — if a field is optional but the
   spec defines its syntax or legal value set (e.g. *"MAY appear; if present,
   value shall be one of {A, B, C}"*), the validator rejects ill-formed
   instances when the field is present. Absence is accepted; a present but
   malformed instance is rejected.

Silence is not a reason to reject. If the spec defines no value form, no
constraint, and no legal value set for something, the validator does not invent
one. *"Out of scope of spec X"* is not the same as *"forbidden by spec X."*

When adding or auditing a check:

- Quote the SHALL / SHALL-NOT / defined-value clause in the code comment and as
  the `spec_ref` field on the error.
- If you can't find one, don't add the check.
- *"Physically silly but not forbidden"* — a configuration that probably can't
  work in practice — is **not** in scope. The validator tests for conformance,
  not for whether a device is saying things that can't be true.

**In scope for validation:**

- RFC 4566 grammar, field order, required fields, and defined value forms for
  every field (required or optional).
- RFC 3550 / 3551 internal coherence (dynamic PT requires `a=rtpmap`; `a=fmtp`
  PT must match `a=rtpmap` PT; audio rtpmap requires the channels field; etc.).
- Every explicit "shall" / "shall not" / "is forbidden" in ST 2110-10 / -20 /
  -21 / -22 / -30 / -31 / -40 / -41, plus defined value sets for optional
  parameters when those parameters are present.
- Every explicit "shall" / "shall not" / "is forbidden" in the applicable VSF
  TR-10 / IPMX profile (with the per-clause TR-10 cite, not a blanket "IPMX"),
  plus defined value sets for optional parameters when present.
- Cross-stream consistency required by ST 2022-7 / RFC 7104 for `a=group:DUP`.

**Out of scope (never validate from SDP):**

- NMOS resources: IS-04, IS-05, BCP-004-01 (Receiver Capabilities), BCP-004-02
  (Sender Capabilities), BCP-005-01 (EDID), IS-11 (Stream Compatibility),
  IS-08. These describe device-wide capabilities and require state beyond the
  SDP.
- RTCP-layer signaling: IPMX Media Info Blocks (any type), PEP Media Info
  Blocks, HKEP HDCP exchanges, HDR metadata. These live in RTP / RTCP, not in
  SDP.
- Sender/Receiver capability subsetting. A single SDP describes one stream's
  parameters; whether a device supports additional formats it isn't currently
  sending is an NMOS-Capabilities question.
- Combinatorial cross-tables (e.g. sampling × colorimetry × range) unless the
  spec explicitly forbids the combination.
- Configurations the spec describes as "out of scope" or "permitted but not
  required" — e.g. ST 2110-30 audio at unusual sample rates or channel counts.

See [GUIDE.md "What this library validates (and what it doesn't)"](GUIDE.md#what-this-library-validates-and-what-it-doesnt)
for the user-facing version with worked examples.

## Coding Conventions

- **Errors are values.** Never call `error()` for parse or validation failures.
  All public functions return `result, err`. `error()` is reserved for programming
  mistakes (wrong argument type).
- **No global state.** Module state lives in the returned table only.
- **LPEG patterns are named constants** defined near the section that uses them
  (grammar patterns in `── Grammar ──`, validation patterns near the validator that
  owns them), never constructed inline at call sites.
- **Use LPEG for pattern matching whenever possible.** Prefer LPEG patterns over
  Lua string patterns (`string.match`/`gmatch`) for structural validation — LPEG
  compiles once, is composable, and is the established tool in this codebase.
- **`M._grammar` and `M._errors`** are exposed on the returned module for spec
  access only; they are not part of the public contract.
- **Strict by default.** If RFC 4566 says a field is required, the parser rejects
  input that omits it — no silent defaults, no forgiveness.
- **dkjson** is the only external runtime dependency beyond LPEG.
- Lua 5.5: use `local` and `global` declarations explicitly; no implicit globals.

## Development Workflow

1. Write failing tests first.
2. `busted spec/` — confirm they fail for the right reason.
3. Implement until tests pass.
4. Update GUIDE.md, README.md, CHANGELOG.md, PLAN.md as needed.
5. Commit (see gates).

## Commit Gates

- [ ] Relevant tests added or updated in `spec/`
- [ ] `busted spec/` passes with no failures
- [ ] `GUIDE.md` updated for any API or behavior change
- [ ] `README.md` updated if project layout or examples changed
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`
- [ ] `PLAN.md` milestone tasks checked off / updated
- [ ] `CLAUDE.md` updated if conventions or layout changed

## Key References

- RFC 4566 (SDP): https://www.rfc-editor.org/rfc/rfc4566
- SMPTE ST 2110-10/20/21/30/40
- IPMX specification
- LPEG docs: https://www.inf.puc-rio.br/~roberto/lpeg/
- Lua 5.5 manual: https://www.lua.org/manual/5.5/
- dkjson: https://github.com/LuaDist/dkjson

## Things to Watch Out For

- SDP field ordering is mandatory per RFC 4566 §5. The serializer must enforce it;
  the parser must reject violations.
- LPEG failure position: use `lpeg.Cp()` captures and map byte offset → line/col
  after the match attempt, not during.
- ST 2110 `fmtp` values are semicolon-separated `key=value` pairs — parse as a
  sub-grammar, not with string splits.
- IPMX validation runs ST 2110 validation first; never skip the lower tier.
- `doc:to_sdp()` must produce output that re-parses cleanly. Round-trip is a
  hard invariant tested on every serializer change.
