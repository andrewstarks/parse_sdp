# CLAUDE.md — parse_sdp

Context and conventions for Claude Code working in this repo.

## Project Purpose

`parse_sdp` is a Lua 5.5 + LPEG library that parses, validates, and serializes SDP
(Session Description Protocol) files. Three validation tiers:
RFC 4566 (generic SDP) → SMPTE ST 2110 → IPMX.

**Strictness is a primary feature.** The library rejects any SDP that does not
conform exactly to RFC 4566 (and the relevant sub-standard when a mode is given).
There is no lenient mode. Many SDP files in the wild are subtly invalid; this
library must not produce or accept them.

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
parse_sdp.lua        library entry point (thin facade, attaches metatable)
lib/
  grammar.lua        LPEG grammar for RFC 4566 line and field parsing
  st2110.lua         ST 2110 validation (operates on parsed doc table)
  ipmx.lua           IPMX validation (operates on parsed doc table)
  serialize.lua      doc → valid SDP text
  errors.lua         error table construction and formatting
cli.lua              CLI entry point (subcommands: parse, serialize)
spec/
  sdp_spec.lua       RFC 4566 parser tests
  st2110_spec.lua    ST 2110 validation tests
  ipmx_spec.lua      IPMX validation tests
  fixtures/          sample .sdp files used by tests
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
doc:serialize()           -- → SDP text string (CRLF, strict RFC 4566 ordering)
doc:to_json()             -- → JSON string (via dkjson)

-- doc is also a plain table
doc.version
doc.origin.unicast_address
doc.session.name
doc.media[1].port
```

## Coding Conventions

- **Errors are values.** Never call `error()` for parse or validation failures.
  All public functions return `result, err`. `error()` is reserved for programming
  mistakes (wrong argument type).
- **No global state.** Module state lives in the returned table only.
- **LPEG patterns are named constants** defined at the top of `lib/grammar.lua`,
  never constructed inline at call sites.
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
- `doc:serialize()` must produce output that re-parses cleanly. Round-trip is a
  hard invariant tested on every serializer change.
