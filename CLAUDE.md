# CLAUDE.md — parse_sdp

Context and conventions for Claude Code working in this repo.

## Project Purpose

`parse_sdp` is a Lua 5.5 + LPEG library that parses, validates, and serializes SDP
(Session Description Protocol) files. Three validation tiers:
RFC 8866 (generic SDP; obsoletes RFC 4566) → SMPTE ST 2110 → IPMX.

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
  sdp_spec.lua       RFC 8866 (base SDP) observable behavior tests
  st2110_spec.lua    ST 2110 validation tests
  ipmx_spec.lua      IPMX validation tests
  grammar_spec.lua   LPEG primitive parser tests (white-box;
                     characterization tests for parse_sdp._grammar;
                     tagged NOT-SPEC: implementation — see file header)
  errors_spec.lua    error formatter tests (pure library)
  cli_spec.lua       CLI integration tests (pure library)
  fixtures/          sample .sdp files used by tests
examples/
  examples.lua       runnable API walkthrough (lua examples/examples.lua)
  generic/           RFC 8866 SDP samples — valid/ and invalid/
  st2110/            ST 2110 SDP samples — valid/ and invalid/
  ipmx/              IPMX SDP samples — valid/ and invalid/
```

## Public API

```lua
local sdp = require("parse_sdp")

-- Entry points (module-level)
local doc, err = sdp.parse(text)            -- parse + validate RFC 8866
local doc, err = sdp.parse(text, "st2110") -- parse + validate ST 2110
local doc, err = sdp.parse(text, "ipmx")   -- parse + validate IPMX
local doc       = sdp.new(table)            -- wrap table as doc (no validation)

-- doc methods (via metatable)
doc:validate()            -- validate as RFC 8866; true or nil, err
doc:validate("st2110")    -- validate as ST 2110; true or nil, err
doc:validate("ipmx")      -- validate as IPMX; true or nil, err
doc:is_sdp()              -- bool
doc:is_st2110()           -- bool
doc:is_ipmx()             -- bool
doc:to_sdp()           -- → SDP text string (CRLF, strict RFC 8866 ordering)
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

- RFC 8866 grammar (obsoletes RFC 4566), field order, required fields, and
  defined value forms for every field (required or optional).
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

## Spec Verification Protocol

This protocol applies to *auditing* existing checks (e.g. when a conformance
finding suggests a check may be wrong), not to writing new ones. New checks
follow the strictness principle above. Audits follow these rules:

1. **Get the primary spec on disk before forming a verdict.** Before claiming
   any check is over-strict, or that "the spec says X," locate the actual
   SMPTE / IETF / VSF document text in a canonical source you can quote.

   **Prefer markdown versions of the specs whenever they exist.** The user
   maintains permanent markdown conversions of SMPTE / VSF documents — they
   are searchable with `grep`, diff cleanly, and quote without OCR
   artifacts. Check the markdown directories first; fall back to PDF only
   when the markdown for the cited clause is not yet available. Locations:

   - VSF TR-10 markdown: `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/smpte_standards_internal/TR-10 Markdowned Versions/`
   - SMPTE ST 2110 + IPMX (markdown if present, PDF fallback): `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/smpte_standards_internal/`
   - IETF RFCs: `WebFetch https://www.rfc-editor.org/rfc/rfcNNNN.txt`
   - Use `pdftotext` (allowlisted) only when no markdown is available.

   Do **not** substitute one of the following for primary spec text:
   - an IANA media-type registration
   - a downstream IETF RFC the SMPTE document builds on
   - an AMWA NMOS profile / BCP that quotes the SMPTE clause
   - a reference implementation's example files

   These are useful triangulation, never authority. SMPTE can tighten or
   loosen what its references say.

2. **Search the filesystem before declaring a spec unavailable.** SMPTE has
   made an increasing number of ST 2110 documents publicly available. Before
   assuming a spec is paywalled or out of reach, run
   `find ~/Downloads ~/Documents -iname "*<spec-id>*"` and ask the user.

3. **An existing citation in the code is a claim to test, not authority to
   trust.** Read the cited clause yourself, in primary source. If a check
   cites a section that does not say what the check enforces, that is itself
   evidence of a parser bug — do not go hunting for support elsewhere to
   rescue the citation.

4. **Reference implementations are evidence, not authority.** If multiple
   independent reference implementations omit something the parser requires,
   the suspicion is high — but the verdict still needs primary spec text.
   When the spec is not yet on disk, label the finding "suspected — unconfirmed
   against the cited document" and resolve it before changing code.

5. **Distinguish "the spec is silent" from "the registration is silent."**
   IANA registrations and IETF RFCs that ST 2110 builds on can be tightened
   by the SMPTE document. The lower layer's optionality does not establish
   ST 2110's optionality.

6. **Bind bullets to their parent clause, not the section header.** When
   reading a bulleted normative list, identify the verb-clause that
   *immediately* introduces it. Read the full sentence aloud: *"The X
   shall Y, including: [bullet]."* If that substitution doesn't parse, the
   bullet belongs to a different scope. Section headers like "X & Y" never
   bind bullets — only the parent clause does. Real example: IPMX
   JPEG-XS Video Profile §6.1.4 is titled "Required Sender Signaling (Media
   Info Block & SDP)", but its bullet list of `transmode, packetmode,
   profile, level, sublevel, fbblevel` attaches to item 1's clause "shall
   populate the JPEG-XS Media Info Block… including:" — those are RTCP
   Media Info Block fields, not SDP fmtp requirements. Reading the bullets
   as SDP requirements (because SDP is in the section title) is the
   failure mode this rule prevents.

When auditing a finding, the report should make clear which sources are
primary and which are circumstantial. Suspected-but-unconfirmed findings stay
allowlisted with a `spec_ref` and an "INVESTIGATE against the cited document" note;
confirmed-against-primary-source findings get fixed.

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
- **Strict by default.** If RFC 8866 says a field is required, the parser rejects
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

- RFC 8866 (SDP — current; obsoletes RFC 4566): https://www.rfc-editor.org/rfc/rfc8866
- RFC 4566 (SDP — historical): https://www.rfc-editor.org/rfc/rfc4566
- SMPTE ST 2110-10/20/21/30/40
- IPMX specification
- LPEG docs: https://www.inf.puc-rio.br/~roberto/lpeg/
- Lua 5.5 manual: https://www.lua.org/manual/5.5/
- dkjson: https://github.com/LuaDist/dkjson

## Things to Watch Out For

- SDP field ordering is mandatory per RFC 8866 §5. The serializer must enforce it;
  the parser must reject violations.
- LPEG failure position: use `lpeg.Cp()` captures and map byte offset → line/col
  after the match attempt, not during.
- ST 2110 `fmtp` values are semicolon-separated `key=value` pairs — parse as a
  sub-grammar, not with string splits.
- IPMX validation runs ST 2110 validation first; never skip the lower tier.
- `doc:to_sdp()` must produce output that re-parses cleanly. Round-trip is a
  hard invariant tested on every serializer change.
