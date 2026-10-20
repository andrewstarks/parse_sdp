# CLAUDE.md for parse_sdp

This file gives Claude Code the context and the conventions for work in this
repository.

## Project Purpose

`parse_sdp` is a library for Lua 5.1 and later, built on LPEG (Lua Parsing
Expression Grammars), that parses, validates, and serializes SDP (Session
Description Protocol) files. The library has three validation tiers. The first
tier is RFC (Request for Comments) 8866, the generic SDP specification that
obsoletes RFC 4566. The second tier is SMPTE (Society of Motion Picture and
Television Engineers) ST 2110. The third tier is IPMX (Internet Protocol Media
Experience). Each tier extends the previous tier.

Strictness is a primary feature of the library. The strictness is grounded in
specification text, not in opinion. The library rejects any SDP that the
relevant standard explicitly forbids, and nothing else. The library has no
lenient mode. The library also has no mode that rejects input that looks broken
when the specification is silent about it. The section "Validation Strictness
Principle" below defines the exact boundary.

Keep the code small. If a module is growing, stop and refactor before adding
more code. Prefer fewer, well-named functions over many small helpers.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.1+ (tested on 5.1, 5.2, 5.3, 5.4, 5.5) |
| Parsing | LPEG |
| JSON | dkjson (pure Lua, LuaRocks) |
| Tests | busted (`busted spec/`) |
| Container | Docker (Lua 5.5) |

## Repository Layout

```
bin/
  parse_sdp          CLI shell. Requires `parse_sdp` (the library) and
                     dispatches subcommands via argparse: validate,
                     diagnose, to_json, to_sdp, checks. Only this file
                     loads argparse; library consumers never load it.
parse_sdp/
  init.lua           library entry point. `require("parse_sdp")` resolves
                     here. Wires the tier match functions, defines the
                     doc metatable methods (mt:validate / mt:to_sdp /
                     mt:to_json / mt:findings / mt:warnings / mt:errors),
                     and exports M.parse / M.new / M.checks /
                     M.default_policy / M._errors.
  errors.lua         error registry (stable check ids, severity policy,
                     record() emission helper, deepest-failure tracker),
                     plus legacy errors.new / errors.format.
  serialize.lua      doc table → SDP text (CRLF, strict RFC 8866 ordering).
  grammar/
    patterns.lua     shared LPeg numeric value-form patterns.
    addresses.lua    IPv4 / IPv6 grammars + multicast expansion +
                     canonicalization helpers.
    base.lua         RFC 8866 base SDP grammar + base_semantic_checks.
                     `base.extend(rules)` composes per-tier overrides.
    st2110.lua       SMPTE ST 2110 overrides (composed onto base).
    ipmx.lua         IPMX / VSF TR-10 overrides (composed onto st2110).
spec/
  -- Per-tier grammar specs (standards-tied; every test cites a published clause):
  grammar_base_spec.lua    RFC 8866 base SDP: document shape, value forms,
                           per-line checks, doc-level semantic checks.
  grammar_st2110_spec.lua  SMPTE ST 2110 narrowings + cross-section invariants.
  grammar_ipmx_spec.lua    VSF TR-10 / IPMX overrides + cross-section invariants.
  -- Internal helpers (white-box; exposed only for spec access):
  grammar_patterns_spec.lua   numeric value-form patterns.
  grammar_addresses_spec.lua  IPv4 / IPv6 grammars + expansion / canonicalize.
  grammar_compose_spec.lua    base.extend() composition mechanism.
  error_registry_spec.lua     registry schema + severity policy mechanics.
  errors_spec.lua             error formatter / legacy errors.new shape.
  -- Library / public API + round-trip / CLI:
  roundtrip_spec.lua  serializer-side: every base + IPMX renderer plus
                      fixture-wide parse → serialize → re-parse round-trip.
  library_spec.lua    public API: sdp.parse, sdp.new, doc:validate,
                      doc:is_*, doc:to_json / to_sdp, policy + findings,
                      mode dispatch.
  cli_spec.lua        CLI subcommand integration tests.
  examples_spec.lua   every file under examples/<tier>/<valid|invalid> passes
                      or fails its tier as the directory says; each invalid
                      file fails with the id, line, and findings in EXPECTED.
  mutation_spec.lua   properties over mutated copies of every example: an
                      unparseable line is the reported error, parse never
                      raises, fail_on_first keeps the verdict, round-trip.
  check_coverage.lua  script (`lua spec/check_coverage.lua`): fails when a
                      registered check is never recorded by any spec.
  grammar_bitops_spec.lua  bitwise helper backends (native on 5.3+, arithmetic
                      on 5.1 and 5.2).
  support.lua         shared test helpers (finding_for, timing fixtures).
  fixtures/           sample .sdp files used by tests.
spec_conformance/    opt-in suite running pinned AMWA-TV / SDPoker
                     upstream fixtures through the parser.
web/
  CONTRACT.md        JSON request/response API the browser playground uses.
  wasm/              Emscripten build: build.sh (pinned Lua 5.5 / LPeg /
                     dkjson downloads → web/dist/parse_sdp.{js,wasm}),
                     bridge.c (C shim exporting sdp_request), bridge.lua
                     (pure-Lua façade over the library; bridge_cli.lua
                     runs it natively), smoke.mjs (WASM ↔ native parity),
                     examples_manifest.lua (ships examples/ with their s=
                     titles as the UI's example picker manifest).
  src/               static UI (ES modules, no bundler) + engine.js.
  fixtures/          real bridge responses used by the UI mock.
  dist/              build output deployed to GitHub Pages (gitignored).
examples/
  examples.lua       runnable API walkthrough (lua examples/examples.lua)
  generic/           RFC 8866 SDP samples in valid/ and invalid/
  st2110/            ST 2110 SDP samples in valid/ and invalid/
  ipmx/              IPMX SDP samples in valid/ and invalid/
```

## Public API

```lua
local sdp = require("parse_sdp")

-- Entry points (module-level)
local doc, err = sdp.parse(text)            -- parse + validate RFC 8866
local doc, err = sdp.parse(text, "st2110") -- parse + validate ST 2110
local doc, err = sdp.parse(text, "ipmx")   -- parse + validate IPMX
local doc       = sdp.new(table)            -- wrap table as doc (no validation)

-- Attribute / param accessors (module-level)
local a  = sdp.attr_get(block, name)        -- first decomposed attr by name, or nil
local as = sdp.attrs_get(block, name)       -- all matches in order (empty table if none)
local v  = sdp.params_get(params, key)      -- value/true/nil from an fmtp/privacy params list
                                            -- (takes the inner list, e.g. fmtp.params, not the block)

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

Every validation check in the grammar modules (`parse_sdp/grammar/base.lua`,
`st2110.lua`, `ipmx.lua`) must be grounded in explicit
normative text from the specification. Three kinds of normative text count:

1. Positive requirements, written as "shall", "MUST", or "is required". If
   the specification says a field must be present or must take a specific
   form, the validator rejects input that omits the field or violates the
   form.
2. Prohibitions, written as "shall not", "MUST NOT", or "is forbidden". If
   the specification forbids a value, a combination, or a construction, the
   validator rejects it.
3. Optional features with defined values. If a field is optional but the
   specification defines its syntax or its legal value set (for example,
   "MAY appear; if present, value shall be one of {A, B, C}"), the validator
   rejects an ill-formed instance when the field is present. An absent field
   is accepted. A present but malformed field is rejected.

Silence in the specification is not a reason to reject. If the specification
defines no value form, no constraint, and no legal value set for a field, the
validator does not invent one. "Out of scope of specification X" does not mean
"forbidden by specification X."

When adding or auditing a check:

- Quote the "shall", "shall not", or defined-value clause verbatim in the
  code comment, as a literal quoted string, and cite the clause in the
  `spec_ref` field on the error. Then compare the interpretation against the
  quoted text. If the interpretation introduces words that the quote does not
  contain, such as "every", "forbidden", or "required", the interpretation is
  the bug. A paraphrase without the verbatim quote is the failure mode that
  lets overreach hide.
- If no such clause can be found, do not add the check.
- A configuration that is physically implausible but not forbidden is not in
  scope. The validator tests for conformance. The validator does not test
  whether a device is describing a configuration that can work in practice.

The following are in scope for validation:

- RFC 8866 grammar (RFC 8866 obsoletes RFC 4566), field order, required
  fields, and the defined value forms for every field, required or optional.
- Internal coherence required by RFC 3550 and RFC 3551. For example: a
  dynamic payload type requires `a=rtpmap`; the `a=fmtp` payload type must
  match an `a=rtpmap` payload type; an audio `a=rtpmap` requires the channels
  field.
- Every explicit "shall", "shall not", or "is forbidden" in ST 2110-10, -20,
  -21, -22, -30, -31, -40, and -41, plus the defined value sets for optional
  parameters when those parameters are present.
- Every explicit "shall", "shall not", or "is forbidden" in the applicable
  VSF (Video Services Forum) TR-10 / IPMX profile, cited to the specific
  TR-10 clause rather than to "IPMX" as a whole, plus the defined value sets
  for optional parameters when those parameters are present.
- Cross-stream consistency required by ST 2022-7 and RFC 7104 for
  `a=group:DUP`.

The following are out of scope. The validator never checks them from the SDP:

- NMOS (Networked Media Open Specifications) resources: IS-04, IS-05,
  BCP-004-01 (Receiver Capabilities), BCP-004-02 (Sender Capabilities),
  BCP-005-01 (EDID), IS-11 (Stream Compatibility), and IS-08. These
  specifications describe device-wide capabilities and require state that is
  not in the SDP.
- RTCP-layer signaling: IPMX Media Info Blocks (any type), PEP Media Info
  Blocks, HKEP HDCP exchanges, and HDR metadata. These are sent in RTP
  (Real-time Transport Protocol) or RTCP (RTP Control Protocol) packets, not
  in the SDP.
- Sender and receiver capability subsetting. A single SDP describes the
  parameters of one stream. Whether a device supports additional formats
  that it is not currently sending is a question for NMOS capabilities, not
  for the SDP.
- Combinatorial cross-tables (for example, sampling × colorimetry × range),
  unless the specification explicitly forbids the combination.
- Configurations that the specification describes as "out of scope" or
  "permitted but not required", for example ST 2110-30 audio at unusual
  sample rates or channel counts.

The GUIDE.md section
["What this library validates (and what it doesn't)"](GUIDE.md#what-this-library-validates-and-what-it-doesnt)
is the user-facing version of this principle, with worked examples.

## Spec Verification Protocol

Use this protocol when writing new checks and when auditing existing checks.
The strictness principle above says what to check. The rules below say how to
be sure of the citation and of the placement.

1. **Get the primary specification text on disk before forming a verdict.**
   Before claiming that a check is over-strict, or that "the specification
   says X", locate the SMPTE, IETF (Internet Engineering Task Force), or VSF
   document text in a canonical source that can be quoted.

   **Prefer markdown versions of the specifications whenever they exist.**
   The user maintains permanent markdown conversions of SMPTE and VSF
   documents. The markdown files are searchable with `grep`, diff cleanly,
   and quote without OCR (optical character recognition) artifacts. Check the
   markdown directories first. Fall back to PDF only when the markdown for
   the cited clause is not yet available. The locations are:

   - VSF TR-10 markdown: `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/TR-10 Markdowned Versions/`
   - SMPTE ST 2110 + IPMX (markdown if present, PDF fallback): `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/smpte_standards_internal/`
   - IETF RFCs: `WebFetch https://www.rfc-editor.org/rfc/rfcNNNN.txt`
   - Use `pdftotext` (allowlisted) only when no markdown is available.

   Do **not** substitute any of the following for primary specification text:
   - an IANA (Internet Assigned Numbers Authority) media-type registration
   - a downstream IETF RFC that the SMPTE document builds on
   - an AMWA (Advanced Media Workflow Association) NMOS profile or BCP that
     quotes the SMPTE clause
   - a reference implementation's example files

   These sources are useful for triangulation. They are never authority.
   SMPTE can tighten or loosen what its references say.

2. **Search the filesystem before declaring a specification unavailable.**
   SMPTE has made an increasing number of ST 2110 documents publicly
   available. Before assuming that a specification is paywalled or otherwise
   unavailable, run `find ~/Downloads ~/Documents -iname "*<spec-id>*"` and
   ask the user.

3. **An existing citation in the code is a claim to test, not authority to
   trust.** Read the cited clause in the primary source. If a check cites a
   section that does not say what the check enforces, that mismatch is itself
   evidence of a parser bug. Do not search elsewhere for support that would
   rescue the citation.

4. **Reference implementations are evidence, not authority.** If several
   independent reference implementations omit something that the parser
   requires, suspicion is high, but the verdict still needs primary
   specification text. When the specification is not yet on disk, label the
   finding "suspected, unconfirmed against the cited document" and resolve
   the finding before changing code.

5. **Distinguish "the specification is silent" from "the registration is
   silent."** IANA registrations and IETF RFCs that ST 2110 builds on can be
   tightened by the SMPTE document. Optionality in the lower layer does not
   establish optionality in ST 2110.

6. **Bind bullets to their parent clause, not to the section header.** When
   reading a bulleted normative list, identify the verb clause that
   immediately introduces the list. Read the full sentence aloud: "The X
   shall Y, including: [bullet]." If that substitution does not parse, the
   bullet is in a different scope. A section header such as "X & Y" never
   binds bullets. Only the parent clause binds them. A real example: IPMX
   JPEG-XS Video Profile section 6.1.4 is titled "Required Sender Signaling
   (Media Info Block & SDP)", but its bullet list of `transmode, packetmode,
   profile, level, sublevel, fbblevel` attaches to the clause in item 1,
   "shall populate the JPEG-XS Media Info Block… including:". Those bullets
   are RTCP Media Info Block fields, not SDP fmtp requirements. Reading the
   bullets as SDP requirements because SDP is in the section title is the
   failure mode that this rule prevents.

7. **The `spec_ref` citation and the error-id prefix must name the same
   tier.** If `spec_ref` cites ST 2110-22:2022, the error id is
   `st2110-22.*` and the check is at the ST 2110 tier. A parenthetical that
   points to a different authoring specification
   (`"TR-10-X §Y (per ST 2110-22 §Z)"`) means the placement is wrong. Move
   the check to the authoring tier; downstream tiers inherit the check
   through composition. The three grammar files
   (`parse_sdp/grammar/{base,st2110,ipmx}.lua`) make this concrete: a check
   is in the file for the tier at which the SHALL was authored, regardless of
   which specification family the check is grouped with for diagnostics.

8. **Do not use the labels "audit-folder follow-up", "1.0 over-strict", or
   "intentional non-parity" on the slice currently being written.** Those
   phrasings are almost always stand-ins for an unverified specification
   claim. Before any of them is committed or written into a bead,
   `grep` the relevant section text for "shall not", "MUST NOT",
   "forbidden", and "prohibit", and for the positive forms of required
   SHALLs. If the text does not say what the label implies, fix the label:
   verify the claim now, or split the work off the current slice. The label
   is never the answer to "can this stay unverified?"

When auditing a finding, the report must state which sources are primary and
which are circumstantial. A suspected but unconfirmed finding stays
allowlisted with a `spec_ref` and a note "INVESTIGATE against the cited
document". A finding confirmed against a primary source is fixed.

## Coding Conventions

- **Errors are values.** Never call `error()` for a parse or validation
  failure. All public functions return `result, err`. `error()` is reserved
  for programming mistakes, such as a wrong argument type.
- **The library has no global state.** Module state is in the returned table
  only.
- **LPEG patterns are named constants defined near the rule that uses them.**
  Per-tier patterns are in the relevant `parse_sdp/grammar/*.lua` module.
  Shared numeric forms are in `parse_sdp/grammar/patterns.lua`. Address forms
  are in `parse_sdp/grammar/addresses.lua`. Patterns are never constructed
  inline at call sites.
- **Use LPEG for pattern matching whenever possible.** Prefer LPEG patterns
  over Lua string patterns (`string.match`, `string.gmatch`) for structural
  validation. LPEG compiles once, is composable, and is the established tool
  in this codebase.
- **`M._errors` is exposed on the returned module for spec access only.** It
  is not part of the public contract. Tests reach grammar internals directly
  through `require("parse_sdp.grammar.base" | "...st2110" | "...ipmx")`.
- **The parser is strict by default.** If RFC 8866 says a field is required,
  the parser rejects input that omits the field. There are no silent
  defaults.
- **dkjson is the only external runtime dependency other than LPEG.**
- **The library is portable across Lua versions.** The library supports Lua
  5.1 through 5.5 in a single source tree. Do not introduce syntax that
  exists only in Lua 5.3 and later (`&`, `>>`, `<<`, integer division `//`,
  `string.pack`, `\u{}` escapes, `<const>`, `<close>`, `goto`, and similar)
  outside the `parse_sdp.grammar.bitops_53` module, which is loaded only on
  Lua 5.3 and later. Do not use `table.unpack` in spec code without the
  `(table.unpack or unpack)` fallback. CI (continuous integration) runs the
  full hermetic suite on each of Lua 5.1, 5.2, 5.3, 5.4, and 5.5.

## Check Taxonomy

Every registered check has one of three `kind` values. The `VALID_KINDS`
table in `parse_sdp.errors.register` enforces the set. The kind of a check
determines where the check is placed in the grammar and how the check behaves
under `opts.fail_on_first` and policy demotion:

| Kind | Definition | Site | Toggleable? |
| --- | --- | --- | --- |
| **hard-syntactic** | Input shape; parsing cannot continue past a violation | Pattern algebra and `Cmt` that returns false to fail the match | No; these checks define parseability |
| **soft-syntactic** | Spec demands a strict form but a lax form is unambiguously interpretable | Ordered choice; lax branch is a `Cmt` that records a finding and returns success | Yes; default severity `warn` |
| **semantic** | Captured value violates a value-set / presence / cross-section rule | `Cmt` that records a finding and either continues (`warn` / `off`) or fails the match (`error` under `fail_on_first=true`) | Yes; default severity per rule |

Hard-syntactic examples: a field with no `=`, an unrecognized line letter, a
malformed `m=` value form, a malformed `o=` value form, a malformed `ptp=`
body (`sdp.a.ts-refclk.ptp-malformed`), and a known attribute whose value
its rule cannot parse to the end of the line (`sdp.a.<name>.malformed`).

Soft-syntactic examples: `sdp.line.lf-only-line-ending`,
`sdp.line.trailing-whitespace`, `sdp.file.trailing-newline-missing`,
`sdp.file.bom-present`, and `sdp.a.fmtp.trailing-semicolon`.

Semantic examples: encoding-name set membership, presence of the required
attributes for a tier, cross-section invariants such as `a=group:DUP`
reference symmetry, the rule that a dynamic payload type requires
`a=rtpmap`, and the RFC 4570 section 3.1 check that an `a=source-filter`
destination is in `c=`.

## Development Workflow

1. Pick the work from `bd ready`, or file it with `bd create`, and claim it
   with `bd update <id> --claim`.
2. Branch off `main` with a name that states the intent (`feat/...`,
   `fix/...`, `docs/...`, `chore/...`).
3. Write failing tests first.
4. Run `busted spec/` and confirm that the new tests fail for the expected
   reason.
5. Implement until the tests pass.
6. Update GUIDE.md, README.md, and CHANGELOG.md as needed.
7. Commit (see "Commit Gates"), push the branch, and open a pull request (see
   "Branching & Pull Requests"). Name the bead id in the PR description.
8. When the PR merges, close the bead with `bd close <id> -r "<what
   landed>"`, and file beads for any follow-up work.

## Planning and Decisions

Planning lives in beads (`bd`), not in a plan document. There is no
PLAN.md; its open items and decisions moved to beads on 2026-10-20, after
the 1.6.0 release.

- Open work is a bead of type `feature`, `bug`, `task`, or `chore`.
  `bd ready` lists what can be started.
- A settled interpretation of a specification, especially a decision not to
  enforce something, is a bead of type `decision`, closed, with the
  rationale and the quoted clause in its description. Code comments and
  `spec_conformance/` notes cite the decision by id (for example
  `parse_sdp-m0w`). `bd list --type decision --all` lists them. Re-open a
  decision only with new primary-source evidence.
- User-facing documentation (GUIDE.md, README.md) states the rationale in
  its own words. It does not send readers to bead ids.
- Release history is in CHANGELOG.md and git, not in beads.

## Branching & Pull Requests

All non-trivial changes go through a topic branch and a pull request (PR).
The rule includes documentation and planning updates. The process is lightweight:
one developer, no required reviewers, no required approvals, and merge when
CI is green. Multiple commits per PR are fine when the commits are logically
related, for example a rule change plus the work that first applies the rule.

The exception is a trivial single-line typo, whitespace, or formatting fix,
where the cost of a branch and a PR exceeds the value. Such a fix may go
directly on `main`. Anything that touches behavior, the public API
(application programming interface), or planning documents goes through a PR.

## Commit Gates

- [ ] The work is on a topic branch, not on `main`.
- [ ] Relevant tests are added or updated in `spec/`.
- [ ] `busted spec/` passes with no failures.
- [ ] `GUIDE.md` is updated for any API or behavior change.
- [ ] `README.md` is updated if the project layout or the examples changed.
- [ ] `CHANGELOG.md` has an entry under `[Unreleased]`.
- [ ] `lua spec/check_coverage.lua` passes when a check was added or changed.
- [ ] The bead for the work is updated, and follow-up work is filed as beads.
- [ ] `CLAUDE.md` is updated if conventions or layout changed.

## Key References

- RFC 8866 (SDP, current; obsoletes RFC 4566): https://www.rfc-editor.org/rfc/rfc8866
- RFC 4566 (SDP, historical): https://www.rfc-editor.org/rfc/rfc4566
- SMPTE ST 2110-10/20/21/30/40
- IPMX specification
- LPEG docs: https://www.inf.puc-rio.br/~roberto/lpeg/
- Lua 5.5 manual: https://www.lua.org/manual/5.5/
- dkjson: https://github.com/LuaDist/dkjson

## Things to Watch Out For

- SDP field ordering is mandatory per RFC 8866 section 5. The serializer
  must enforce the ordering. The parser must reject violations.
- LPEG failure position: use `lpeg.Cp()` captures and map the byte offset to
  a line and column after the match attempt, not during the match.
- `Cb"name"` raises a Lua error when no group named `name` is in scope. It
  does not fail the match, and an ordered choice does not catch it. Every
  group that a tier reads with `Cb` must exist on every path. The base
  grammar defines a nil `params` group on the raw fmtp branch and a nil
  `media` group in the session section for this reason.
- Findings live in `ctx.findings`, a side table, so backtracking does not
  remove them. A `Cmt` that records a finding must sit after everything
  in its alternative that can still fail. Put a closing look-ahead inside
  the `Cmt` pattern, not after it. Section and document checks run only on
  a section that parsed to its end.
- A known attribute has three parts in the grammar: its rule in `a_value`,
  its name in `known_attr_lookahead` (or a tier's `tier_attr_names`), and
  a `malformed_attr(name, id)` entry in `a_malformed` (or a tier's
  `tier_malformed`) with a registered id. `a_value` accepts a known rule
  only when the rule ends at the end of the value; otherwise the line goes
  to `a_malformed`. A recording `Cmt` inside a known rule must therefore
  follow a `#V"value_boundary_chars"` look-ahead. Without the look-ahead,
  a value with more text after it (`raw/90000/0`) records the rule's
  finding and then the malformed finding.
- A demoted malformed attribute stays in `block.attributes` with
  `malformed = true` and no decomposed fields. Checks read attributes
  through `base.attr_get` / `base.attrs_get`, which skip it, or test
  `attr.malformed` before reading a decomposed field.
- ST 2110 `fmtp` values are semicolon-separated `key=value` pairs. Parse
  them as a sub-grammar, not with string splits.
- IPMX validation runs ST 2110 validation first. Never skip the lower tier.
- `doc:to_sdp()` must produce output that re-parses cleanly. The round-trip
  is a hard invariant, tested on every serializer change.
- A parse failure reports exactly where the input failed and why. A finding
  about a line other than the failing one is a bug.
- **The serializer never validates, and validation never serializes.**
  `to_sdp()` checks only structural completeness: the fields that RFC 8866
  or the per-attribute grammar mark as required, so that a renderable line
  can be produced. On success, `to_sdp()` emits the fields as given.
  Value-form correctness, enum membership, and cross-section invariants are
  checked in `doc:validate()`. A missing required field is the only thing
  that `to_sdp()` reports as an error. A field that is present but wrong is
  stringified and emitted; the round-trip then fails, and that failure is
  the developer's signal. This separation lets a developer build a doc
  piecemeal, render the doc at any point to see structural gaps, and
  validate when the doc is believed complete.
- There is no fallback to a stored `attr.value` string for known decomposed
  attribute names. The grammar tier produces the decomposed shape (for
  example, `rtpmap` has the fields `payload_type`, `encoding`, and
  `clock_rate`). The serializer renders only from those fields. A hand-built
  doc constructed with `sdp.new(t)` must use the same decomposed shape. The
  legacy `{name, value=string}` shape for known attribute names is no longer
  a supported producer surface. Generic or unknown attributes keep the legacy
  shape as the forward-compatible representation. The one exception is a
  table with `malformed = true`, which the parser produces for a demoted
  `.malformed` check; the serializer renders its `value` as written.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
