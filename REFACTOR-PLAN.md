# Refactor Plan — Grammar-First parse_sdp

Status: **draft, awaiting review**. Branch: `refactor/grammar-first`.

This document plans a ground-up rewrite of `parse_sdp.lua` against two
principles that the 1.0 implementation didn't fully honor:

1. **The grammar IS the spec.** Stay inside LPeg patterns from input bytes to
   structured doc. No Lua-massage pipelines between stages.
2. **Plan in layers, top-down.** Sketch the document shape, list constraints
   with their scope, then write leaves into the slots the outline already cut.

Both principles come from the LPeg skill (§2, §3) and the project's
conformance discipline ([CLAUDE.md](CLAUDE.md)). The existing PLAN.md and its
"Known Deferred Items" remain authoritative for spec questions that already
have a decided answer.

---

## 1. Goals and non-goals

**Goals.**

- A single LPeg grammar pass produces a **rich, fully-decomposed doc table**.
  No consumer should ever have to re-parse a string from the doc.
- Three composed grammars — `sdp_grammar`, `st2110_grammar`, `ipmx_grammar` —
  related by rule-table extension (see §3.1).
- Every check carries a **stable error ID** plus a verified `spec_ref`. The
  set of IDs is the audit table.
- Architecture **supports per-error severity toggling** (`error` / `warn` /
  `off`) without committing to implement it now.
- Existing error functionality preserved: same human-formatted output, same
  `field_path` / `line` / `col` / `context` / `code` / `spec_ref` fields.
  The new `id` field is additive.
- Round-trip invariant tightens: `text → doc → text` is **functionally
  equivalent** — output is a fully spec-compliant SDP with no accepted
  weirdness (correct line terminators, no stray semicolons or trailing
  whitespace). `doc → text → doc` produces an equivalent doc. Serialization
  is rendered from structure, not echoed strings.

**Non-goals.**

- Changing what is validated. Every existing check survives, possibly under a
  new ID. The "Known Deferred Items" in PLAN.md stay deferred.
- Implementing severity toggling. The architecture must support it; the
  policy interface ships as a no-op default ("everything = error, fail on
  first").
- Replacing the public top-level API surface. `sdp.parse`, `sdp.new`,
  `doc:validate`, `doc:is_*`, `doc:to_sdp`, `doc:to_json` keep their names
  and headline semantics; `parse` and `validate` accept an optional `opts`
  table for future policy.
- **File shape is not constrained.** The 1.0 shipping artifact was a
  single file; the refactor doesn't have to be. Use whichever organization
  is cleanest during implementation; we can recombine for shipping later.

## 2. The three problems the current code has

Diagnosed during the planning conversation; documented here so the refactor
addresses them deliberately.

1. **The "grammar" isn't really a grammar.** The Lua loop at
   [parse_sdp.lua:3420-3635](parse_sdp.lua#L3420-L3635) line-splits with
   `string.find` ([parse_sdp.lua:3355-3372](parse_sdp.lua#L3355-L3372)),
   then per-line calls small LPeg patterns. Document-shape rules (field
   ordering, "exactly one s=", "at most one session-level c=") live in
   `if peek_type(...) == "c"` Lua, not pattern algebra.

2. **Compound values stay as raw strings.**
   `grammar.parse_attribute` at [parse_sdp.lua:258-264](parse_sdp.lua#L258-L264)
   returns `{ name = "rtpmap", value = "96 H264/90000" }` — the value is
   never decomposed. Sub-grammars exist (`rtpmap_parse` at
   [parse_sdp.lua:604-610](parse_sdp.lua#L604-L610)) but their output is
   used inside validators and thrown away. A consumer asking for
   `rtpmap.encoding` must re-parse the string. Round-trip works today only
   because `to_sdp()` echoes the strings back verbatim.

3. **Lua loops where LPeg would compose.** `parse_repeat` and
   `parse_timezone` ([parse_sdp.lua:205-233](parse_sdp.lua#L205-L233))
   `gmatch` their tokens. The DUP-group iterator at
   [parse_sdp.lua:540-543](parse_sdp.lua#L540-L543) `gmatch`es mids. Every
   one of these is reachable as an LPeg sub-grammar.

The refactor fixes all three by construction.

---

## 3. Architecture

### 3.1 Three composed grammars (option C)

LPeg grammars are tables of rules. Composition is a table merge that happens
once at module-load time:

```lua
local function extend(parent, overrides)
  local out = {}
  for k, v in pairs(parent) do out[k] = v end
  for k, v in pairs(overrides) do out[k] = v end
  return out
end

local sdp_rules = {
  "document",
  document         = V"session_section" * V"media_section"^0 * -1,
  -- ... base SDP rules
  rtpmap_encoding  = C((1 - SP - P"/")^1),     -- any nonempty token
  audio_channels   = V"required_channels_field",
}

local st2110_rules = extend(sdp_rules, {
  -- Narrow value sets via Cmt
  rtpmap_encoding  = Cmt(C((1 - SP - P"/")^1),
                          require_member("st2110-30.a.rtpmap.encoding-set",
                                         ST2110_AUDIO_ENCODINGS)),
  -- New top-level invariant (existence of required attribute, etc.)
  document         = sdp_rules.document
                   * Cmt(Carg(1), check_st2110_required_attrs),
})

local ipmx_rules = extend(st2110_rules, { ... })

local sdp_grammar    = lpeg.P(sdp_rules)
local st2110_grammar = lpeg.P(st2110_rules)
local ipmx_grammar   = lpeg.P(ipmx_rules)
```

Each grammar is a self-contained `P{...}` that matches text and produces the
rich doc table. The composition mechanism is one helper (`extend`); the rules
that distinguish a tier are visibly grouped in one place.

**A tier can extend its parent in three ways.** All map to standard LPeg
operations; nothing requires a new mechanism.

| Way | Mechanism | Example |
|---|---|---|
| **Narrow a value's allowed set** | Override the leaf rule with a stricter `Cmt(C(...), check)` | ST 2110-30 narrows `rtpmap_encoding` to `{L16, L24, AM824}`. |
| **Add a required-presence or cross-section invariant** | Append `* Cmt(Carg(1), fn)` to the top-level `document` rule; the callback walks the captured doc | ST 2110 requires `a=ts-refclk` on every media block. |
| **Introduce a value form the base doesn't know** | Add new rules; reference them from an override | TR-10 may add new `a=` attributes not in base SDP. |

### 3.2 Rich doc-table contract

The parsed doc carries fully decomposed values. Compound attributes are no
longer strings.

```lua
-- Today
attr = { name = "rtpmap", value = "96 H264/90000" }
attr = { name = "fmtp",   value = "97 sampling=YCbCr-4:2:2; width=1920; ..." }
attr = { name = "ts-refclk", value = "ptp=IEEE1588-2008:00-1D-9A-..." }

-- After refactor
attr = { name = "rtpmap",
         payload_type = 96, encoding = "H264", clock_rate = 90000,
         channels = nil }
attr = { name = "fmtp",
         payload_type = 97,
         params = { sampling = "YCbCr-4:2:2", width = 1920, ... } }
attr = { name = "ts-refclk",
         source = "ptp",
         ptp = { version = "IEEE1588-2008",
                 grandmaster = "00-1D-9A-...",
                 domain = 127 } }
```

The full list of compound attributes that get decomposed:

- `o=` — already decomposed.
- `c=` — already decomposed.
- `m=` — already decomposed; clean up port-with-count split (currently
  uses a Lua string match at [parse_sdp.lua:281-283](parse_sdp.lua#L281-L283)).
- `b=` — already decomposed.
- `t=`, `r=`, `z=` — already decomposed; `r=` and `z=` move from `gmatch` to
  LPeg sub-grammars.
- `a=` — generic `{ name = ..., value = ... }` carries through for unknown
  attributes (forward-compat). Known attributes get typed decomposition:
  - `rtpmap`, `fmtp`, `ts-refclk`, `mediaclk`
  - `source-filter`, `group`, `mid`
  - `ssrc`, `ssrc-group`, `msid`
  - `extmap`, `rtcp-fb`, `rtcp`, `rtcp-mux`
  - `ptime`, `maxptime`, `framerate`, `quality`
  - `sendonly` / `recvonly` / `sendrecv` / `inactive` (flag attrs, name-only)

The exact target shape for each lands in the implementation; the audit table
includes a "doc shape" column per attribute.

**JSON output** is the doc table serialized via dkjson — automatically rich
once the table is rich. Existing JSON consumers get more useful output; we
should bump a documentation note.

**Serializer** renders from structure: `to_sdp(doc)` walks the doc and emits
`a=rtpmap:96 H264/90000` from the structured fields, never from a stored
string. This makes the round-trip invariant real: a doc constructed via
`sdp.new(table)` and then serialized must produce parseable text.

**Per-node serialization** is a natural extension: each doc node carries
an explicit `:to_sdp()` method that emits its own text fragment. So
`doc:to_sdp()` renders the whole document, `doc.media[1]:to_sdp()` renders
one media section, `attr:to_sdp()` renders one attribute line. We use
explicit methods rather than `__tostring` because `__tostring` is Lua's
debug-print convention — overriding it for serialization would mean
`print(doc.media[1])` shows rendered SDP instead of the table's internal
shape, which is a development footgun. Keeping `:to_sdp()` explicit
separates rendering from debugging.

### 3.3 Three-way check taxonomy

| Kind | Definition | Site | Toggleable? |
|---|---|---|---|
| **Hard-syntactic** | Input shape; parsing cannot continue past a violation | Pattern algebra and `Cmt` that returns false to fail the match | No — these define parseability |
| **Soft-syntactic** | Spec demands a strict form, but a lax form is unambiguously interpretable | Ordered choice; lax branch is a `Cmt` that records a finding and returns success | Yes; default severity `warn` |
| **Semantic** | Captured value violates a value-set / presence / cross-section rule | `Cmt` that records a finding (and either continues — `warn`/`off` — or fails the match — `error`) | Yes; default severity per rule |

Hard-syntactic examples: field with no `=`, unrecognized letter, malformed
`m=` line, malformed `o=` line.

Soft-syntactic candidates (initial list — extend during implementation):

- `sdp.line.lf-only-line-ending` — bare LF instead of CRLF
- `sdp.line.trailing-whitespace`
- `sdp.file.trailing-newline-missing`
- `sdp.file.bom-present`
- `sdp.a.fmtp.trailing-semicolon`
- `sdp.a.fmtp.whitespace-around-equals`
- `sdp.line.leading-whitespace`

Semantic examples (mostly inherited from current ST 2110 / IPMX validators):
encoding-name set membership, presence of required attributes, cross-section
invariants like `a=group:DUP` reference symmetry, dynamic-PT-requires-rtpmap.

### 3.4 Error registry

A single Lua table keys every check by its ID. The table is statically
inspectable — the audit table is grep-able directly from source.

```lua
local CHECKS = {
  ["sdp.v.must-be-zero"] = {
    kind             = "hard-syntactic",
    default_severity = "error",
    code             = "INVALID_VALUE",      -- legacy enum (kept for back-compat)
    message_template = "v= must be '0'",
    spec_ref         = "RFC 8866 §5.1",
    verified         = true,                 -- spec text read against rfc8866 on disk
  },
  ["st2110-30.a.rtpmap.encoding-set"] = {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template = "audio rtpmap encoding must be one of {L16, L24, AM824}",
    spec_ref         = "ST 2110-30:2017 §6.2.1",
    verified         = true,
  },
  ["sdp.line.lf-only-line-ending"] = {
    kind             = "soft-syntactic",
    default_severity = "warn",
    code             = "MALFORMED_LINE",
    message_template = "line ended with bare LF; RFC 8866 §9 ABNF requires CRLF",
    spec_ref         = "RFC 8866 §9",
    verified         = true,
  },
  ["aes67.audio.sample-rate"] = {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template = "AES67 audio sample rate must be from <TBD>",
    spec_ref         = "AES67-2023 §<TBD>",
    verified         = false,
    verification_note = "AES67-2023 paywalled; not on disk. Check derived "
                     .. "from secondary source: <X>. Confirm against primary "
                     .. "spec before treating as authoritative.",
  },
  -- ...
}
```

**ID scheme** (recap from the planning conversation): `<tier>.<area>.<slug>`.

- `tier` ∈ `sdp` / `st2110` / `ipmx` — the **validation tier** the user
  opts into, not the spec layer that authored the check. ST 2110-22, -30,
  -31, -40 are all optional parts of the 2110 family applied per media
  block, so they share the `st2110` umbrella. The spec authoring detail
  (which 2110 part, which TR-10 part, which RFC) lives in `spec_ref`.
- `area` = the SDP field or attribute it applies to (`v`, `o`, `c`, `m`,
  `a.rtpmap`, `a.fmtp`, `a.ts-refclk`, `line`, `file`).
- `slug` = human-readable shorthand for what it checks.

Spec section numbers live in the registry's `spec_ref`, **not** in the ID —
specs revise (RFC 4566 → 8866, ST 2110-30:2017 → -30:2025) and IDs need to
outlive that.

**Unverified-citation lane** (the AES67-2023 case generalizes): `verified =
false` plus a `verification_note` explaining what we don't have access to and
where the secondary evidence came from. The PLAN's audit table should
ideally have zero `verified = false` rows; ones that remain are tracked as
known gaps. This is consistent with the
[spec_conformance/](spec_conformance/) suite's `allowlist.lua` discipline.

### 3.5 Severity policy

A policy is a table from ID → severity (`error` / `warn` / `off`).
`sdp.parse` accepts it via the `opts` table:

```lua
local doc, err, warnings = sdp.parse(text, "st2110", {
  policy = {
    ["sdp.line.lf-only-line-ending"] = "warn",   -- default already warn
    ["sdp.a.fmtp.trailing-semicolon"] = "off",   -- disable entirely
    ["st2110-30.a.rtpmap.encoding-set"] = "warn", -- downgrade error
  },
})
```

**Today (1.0 behavior)**: the default policy is "every default-error stays
error; first error halts; warnings are dropped." The opts table is accepted
and parsed, but the `policy` field is currently a no-op for non-default
values. We architect for it; we don't implement it.

**The mechanism** (when implemented): the grammar threads a `findings`
accumulator via `lpeg.Carg(1)`. Every check site calls a helper:

```lua
local function record(ctx, check_id, location)
  local def = CHECKS[check_id]
  local sev = (ctx.policy and ctx.policy[check_id]) or def.default_severity
  if sev == "off" then return true end
  ctx.findings[#ctx.findings + 1] = {
    id          = check_id,
    severity    = sev,
    message     = def.message_template,  -- can take params later
    spec_ref    = def.spec_ref,
    code        = def.code,
    line        = location.line,
    col         = location.col,
    field_path  = location.field_path,
    context     = location.context,
  }
  if sev == "error" and ctx.fail_on_first then
    return false   -- fails the match; deepest-failure tracker carries this finding out
  end
  return true
end
```

After match completion, `parse()` partitions findings: any `error`-severity
finding produces a parse failure (returning `nil, err`); `warn`-severity
findings return as the `warnings` list. With `fail_on_first = true` (the
1.0-compatible default) we never collect more than one error.

**Policy keys are derived from the registry, not invented.** Two helpers
make this concrete:

- `sdp.checks()` — returns an array of every registered check
  (`{id, kind, default_severity, code, spec_ref, message_template, verified}`).
  Inspectable for audit; dumpable for tooling.
- `sdp.default_policy()` — returns a `{id = default_severity}` table over
  every registered check. Users dump it, edit it, save it as their config,
  pass it back via `opts.policy`.

At parse time, every key in `opts.policy` is validated against the
registry: an unknown ID is a caller bug (typo or stale config) and `parse`
returns an error pointing at the offending key. The registry is the only
source of truth for what's toggleable.

### 3.6 Error functionality preserved

Today's [errors.format](parse_sdp.lua#L38-L57) output stays exactly the same.
The new `id` field is additive — it appears in the structured error table
but the human-formatted output is byte-identical to today's. Existing
consumers that read `err.code` continue to work; `err.id` is new.

```
error: [INVALID_VALUE] audio rtpmap encoding must be one of {L16, L24, AM824}
 --> field: media[0].attributes[rtpmap]
  = note: required by ST 2110-30:2017 §6.2.1
```

Position tracking inside LPeg uses the deepest-failure tracker pattern
(LPeg skill `references/errors.md` + `lib/errors.lua`). Each `Cmt` writes
its position to the `ctx.deepest` slot before failing; the post-match
handler reads that slot. This is the standard pure-LPeg approach since
labeled failures (`lpeg.T`) live in the separate `lpeglabel` library we
don't depend on.

---

## 4. Current spec coverage (audit baseline)

The 1.0 parser cites these specs across ~33 distinct `spec_ref` strings.
The refactor's audit table will reproduce all of them under the new ID
scheme; any check that can't find an explicit spec citation is removed (per
the conformance principle).

| Spec | Sections cited today |
|---|---|
| RFC 4566 (historical) | §5 (still referenced; some are really RFC 8866 §5.X — audit) |
| RFC 4570 | §3, §3.1 |
| RFC 5888 | §4, §5, §6 |
| RFC 7273 | §4.8 |
| RFC 8285 | §5 |
| RFC 8866 | §5.7, §8.2.3 (under-cited; many checks are RFC 8866 §5.X but cite §4566) |
| ST 2110-10:2022 | §6.3, §6.5, §7, §8.1, §8.3, §8.5 |
| ST 2110-40:2023 | §7 |
| TR-10-1 | §10 |
| TR-10-5 | §10 |
| TR-10-7 | §11 |
| TR-10-10 | §8 |
| TR-10-13 | §13, §20.1 |

The audit table will be a separate artifact (`spec_conformance/checks.md`
or a Lua-table dump from the runtime registry — to decide during Phase 0).
It is a deliverable of Phase 0, not of this plan.

**Available primary sources for re-verification.**

- IETF RFCs via WebFetch — always primary.
- TR-10 markdown at `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/TR-10 Markdowned Versions/`
  (CLAUDE.md cites the wrong path; fix as a sub-task) covering parts 0–16 plus TP-1.
- SMPTE PDFs in the same Dropbox tree: ST 2022-7/-8, ST 2110-22, ST 2110-23/-24/-25, AES3 parts, AES67-2013.
- **AES67-2023 is NOT on disk**: the only AES67 file we have is the 2013
  edition. Checks citing AES67-2023 must be `verified = false` until the
  spec is obtained.

**Spec-storage workflow rule.** When a primary spec is fetched (RFC via
WebFetch or any other source), save it permanently as markdown in the
`Standards Related/` tree so future sessions don't re-fetch and citations
stay verifiable offline. RFCs save as raw text plus a markdown copy; PDFs
go through the existing conversion pipeline. Paywalled specs we can't
obtain stay tracked in the unverified-citation lane.

---

## 5. Implementation phases

Each phase has a tight deliverable, gets reviewed independently, and ends
with green tests. Order is chosen so the architecture validates
incrementally rather than landing as one big mass.

**Phase 0 — Error registry skeleton + RFC 4566→8866 citation migration.**
Build `errors.lua` machinery: `CHECKS` table schema, `record()` helper,
deepest-failure tracker, policy lookup (no-op default), policy-key
validation against the registry. Migrate existing errors module
(formatter, struct shape). Expose `sdp.checks()` and `sdp.default_policy()`.

Sub-task: walk every existing `spec_ref = "RFC 4566 §X"` and rewrite to
`RFC 8866 §X`, verifying section-number stability against the 8866 text on
disk; where sections renumbered, update. RFC 4566 is historical; 8866 is
current authority.

Sub-task: fix CLAUDE.md's TR-10 markdown path (currently points to
`smpte_standards_internal/TR-10 Markdowned Versions/`; the directory is at
`Standards Related/TR-10 Markdowned Versions/`).

Tests: registry well-formedness, record/policy semantics,
deepest-failure-tracker correctness, policy-key validation.

**Phase 1 — Base SDP grammar, top-down skeleton.**
Write `P{...}` for `document`, `session_section`, `media_section` with
placeholders for leaves. Verify acceptance/rejection of structural
edge cases (missing v=, wrong order, no media blocks). Tests pass on
trivially-minimal SDPs only.

**Phase 2 — Base SDP leaves.**
Fill in leaf patterns for v, o, s, i, u, e, p, c, b, t, r, z, m, a. Use
existing per-field parsers as starting points but with rich decomposition
(replacing `gmatch` loops with LPeg sub-grammars). Round-trip tests for
RFC-8866 fixtures pass.

**Phase 3 — Base SDP semantic checks.**
Top-level `Cmt` for cross-section invariants the current validator covers:
dynamic PT requires `a=rtpmap` (RFC 8866 §8.2.3), session-level `c=`
multiplicity (§5.7), c= multicast value-form (§5.7 / §9). All under new
IDs. Tests: existing RFC 8866 spec tests pass with new IDs.

**Phase 4 — Compound attribute decomposition.**
LPeg sub-grammars for rtpmap, fmtp, ts-refclk, mediaclk, source-filter,
group, mid, ssrc / ssrc-group / msid, extmap, rtcp-fb / rtcp / rtcp-mux,
ptime / maxptime / framerate / quality. Each lands in the doc as a typed
table. Round-trip via serializer is a per-attribute test.

**Phase 5 — Soft-syntactic findings.**
Add the lax-form-accepting alternatives (CRLF tolerance, trailing semicolons,
trailing whitespace, BOM, missing trailing newline). Each records a finding
via the registry helper. Default policy emits them as warnings.

**Phase 6 — ST 2110 grammar via `extend(sdp_rules, ...)`.**
Override leaves where ST 2110 narrows value sets (rtpmap audio encoding,
fmtp parameter constraints per media type, mediaclk/ts-refclk specifics, c=
multicast rules). Append top-level `Cmt` for ST 2110 cross-section invariants
(required attributes per media type, group:DUP symmetry). Every existing
ST 2110 check migrates under its new ID.

- **6.A (complete)** — composition mechanism in
  `parse_sdp/grammar/base.lua`: `M.extend(parent, overrides)`,
  `M.semantic_checks` (explicit list), `M.make_validate_doc(checks)`
  factory, `M.document_body` (Lua pattern, not V-rule — V-indirection
  breaks the `%` accumulator inside fmtp's params kv-list). Empty
  `parse_sdp/grammar/st2110.lua` = `base.extend(base, {})`. Internal
  entry point only; `sdp.parse(text, "st2110")` remains on the 1.0
  path until Phase 9. 12 new composition tests; suite 1127 green.
- **6.B (complete)** — per-encoding rtpmap narrowings expressed as
  in-grammar overrides. `parse_sdp/grammar/st2110.lua` overrides
  `a_rtpmap` with a branched form: one branch per recognised essence
  (raw / jxsv / smpte291 / AM824) plus a default for unknown encodings.
  Each known-encoding branch ends in a Cmt that reads `Cb"clock_rate"`
  and `Cb"media"` (surrounding media-section's m= type) and emits
  findings via `errors.record`. Default branch gated by negative
  lookahead so malformed known-encoding rtpmaps cannot backtrack to it.
  8 new check IDs in `errors.lua`, 17 new tests in
  `spec/grammar_st2110_spec.lua`. Suite 1144 green (modulo pre-existing
  fmtp flake). L16/L24 union check via AES67 deferred — AES67-2023 is
  paywalled, would need `verified=false`.
- **6.C.A (complete)** — `fmtp_params_branch` rewritten off the `%`
  accumulator to dissolve the trailing-semicolon flake. Entries now
  capture `{key, value}` / `{flag, true}` sub-tables collected by
  `Ct(...) / fmtp_entries_to_params` rather than folded via `%`. 30/30
  fresh runs green after change (previously ~45% flake rate). Investigation
  preserved at [audits/FMTP_ACCUMULATOR_FLAKE.md](audits/FMTP_ACCUMULATOR_FLAKE.md).
- **6.C.B (complete)** — ST 2110-20:2022 §7.1 raw fmtp parameter-form
  narrowing. New error id `st2110-20.a.fmtp.no-whitespace-around-equals`
  in `errors.lua`. ST 2110 overrides `a_rtpmap` to record
  `ctx.rtpmap_encodings[pt] = encoding`, then overrides `a_fmtp` with
  two encoding-gated branches: a strict params parser for raw PTs that
  rejects whitespace around `=`, and base's loose form for everything
  else. The ctx-based lookup is necessary because each a= line closes
  its own a_value Ct — `Cb"encoding"` from a later fmtp line cannot
  reach the earlier rtpmap's group capture. 8 new tests in
  `spec/grammar_st2110_spec.lua`; suite 1152 green. Deferred edge case:
  if `a=fmtp` precedes `a=rtpmap` for the same PT within a media block,
  the encoding lookup misses; revisit only if a real SDP surfaces this
  ordering (no real ST 2110 sender does).
- **6.C (remaining)** — other -20 fmtp value-set narrowings, -22 jxsv
  fmtp parameter sets, -30 audio fmtp where defined, -41 SSN/DIT.
- **6.D (pending)** — required-attribute presence per media type
  (ts-refclk, mediaclk, ptime).
- **6.E (pending)** — cross-stream invariants (RFC 7104 group:DUP,
  SMPTE ST 2022-7 redundancy coherence).

**Phase 7 — IPMX grammar via `extend(st2110_rules, ...)`.**
Same pattern, IPMX-specific from TR-10 markdowns. Re-verify each citation
against the TR-10 part it claims (per CLAUDE.md Spec Verification Protocol).

**Phase 8 — Serializer rewrite.**
Render from structured doc, never from stored strings. Round-trip invariant
test runs on every fixture in `examples/{generic,st2110,ipmx}/valid/`.

**Phase 9 — Public API stabilization.**
`sdp.parse(text, tier, opts)`, `doc:warnings()`, `doc:findings()`,
`sdp.policy(table)` helper. Policy field accepted but treated as no-op for
non-default values (defer behavior change).

**Phase 10 — Migration cutover.**
Delete the 1.0 implementation modules. `busted spec/` green.
`busted spec_conformance/` green. CHANGELOG.md entry, GUIDE.md regenerated
sections, README.md notes the doc-shape change.

Estimated weight: phases 0–3 are small and gated by getting the architecture
right; phases 4–7 are the bulk of the work; phases 8–10 are mechanical given
the foundation.

---

## 6. File layout

Choose whichever organization is cleanest during implementation. The 1.0
single-file `parse_sdp.lua` was 3801 lines and pushing it; splitting into
a small module directory is a reasonable starting point. We can recombine
for shipping later if a single-file artifact becomes useful again.

Section ordering (single-file or split):

```
─ Errors (registry, formatter, deepest-failure tracker, policy helpers)
─ Common patterns (digit, alpha, SP, line_end, hostnames, IPv4/IPv6)
─ Check registry (CHECKS table — one row per ID)
─ Base SDP rules (rule table, not P{...} yet)
─ ST 2110 rules (extend)
─ IPMX rules (extend)
─ Grammar compilation (three P{...} instances)
─ Serializer (structure → text)
─ JSON adapter (doc table → JSON via dkjson)
─ Public API (parse, new, doc methods)
─ CLI (detect-if-main)
```

Candidate split:

- `parse_sdp.lua` — entry point, public API, CLI dispatch
- `parse_sdp/errors.lua` — registry, formatter, policy plumbing
- `parse_sdp/grammar.lua` — common patterns + compilation glue
- `parse_sdp/grammar/base.lua`, `parse_sdp/grammar/st2110.lua`,
  `parse_sdp/grammar/ipmx.lua` — rule tables per tier
- `parse_sdp/serialize.lua` — render from structure

---

## 7. Test strategy

`spec/` test layout adapts but stays organized by what each file exercises:

| File | After-refactor role |
|---|---|
| `spec/sdp_spec.lua` | Base SDP grammar — every leaf, every check, doc shape |
| `spec/st2110_spec.lua` | ST 2110 overrides + cross-section invariants |
| `spec/ipmx_spec.lua` | IPMX overrides + cross-section invariants |
| `spec/library_spec.lua` | Public API + doc-table shape + JSON output |
| `spec/cli_spec.lua` | Unchanged |
| `spec/grammar_spec.lua` | LPeg primitive parsers — adapt to new pattern set |
| `spec/errors_spec.lua` | Errors + registry well-formedness + policy mechanics |
| **new** `spec/findings_spec.lua` | Soft-syntactic findings emission & policy |
| **new** `spec/roundtrip_spec.lua` | Doc-shape round-trip per attribute |

Tests that depend on the old `attr.value = string` shape need updating to
the new decomposed shape. Track which tests change as part of phases 4 / 8.

`spec_conformance/` runs unchanged. The `allowlist.lua` will likely change
shape (new IDs, fewer entries) as we re-audit each citation against primary
sources during Phases 6 and 7.

---

## 8. Risks and open questions

**Doc-shape change breaks many existing tests by design.** The 1.0 tests
assert against the old string-value attribute shape; the refactor produces
fully decomposed values. Tests under [spec/](spec/) will be rewritten or
replaced during Phases 4 and 8 — this is expected scope, not a regression.

**Doc-shape change is a breaking API change for JSON consumers.** A field
that was `attr.value = "96 H264/90000"` becomes
`attr.payload_type = 96, attr.encoding = "H264", attr.clock_rate = 90000`.
2.0-class change; CHANGELOG.md and README.md will call it out, with a
GUIDE.md migration note.

**The `fail_on_first` default preserves 1.0 behavior**, but it leaves the
architecture's collect-all-findings capability dormant. We can flip it on
later via the `opts.policy` plumbing without breaking changes.

**Severity-toggling-for-real is deferred.** When it ships, three things
need to be checked: (a) every registered ID is final (we don't want to
rename public toggle names later), (b) policy precedence between
caller-policy and registry defaults is unambiguous, (c) the legacy `code`
enum stays stable so existing consumers don't break.

**Comparing against the 1.0 implementation** doesn't need special tooling.
`refactor/grammar-first` is a branch off `main`, so `git diff main..HEAD`
and `git log main..HEAD` give the full picture at any time. Keep `main`
clean for the duration of the refactor.

**`lpeglabel` evaluated, not adopted.** The labeled-failures library would
let us drop the manual deepest-failure tracker, but (a) it's another
LuaRocks dep beyond LPeg + dkjson, (b) the severity-policy mechanism needs
`Cmt + Carg` regardless (`severity = "warn"` is exactly record-and-continue),
so the tracker rides on infrastructure we're building anyway, (c) the LPeg
skill ships a reference implementation we can borrow. Worth revisiting only
if the tracker becomes painful in practice.

---

## 9. Pointers

- [CLAUDE.md](CLAUDE.md) — coding conventions and the Validation Strictness
  Principle this plan implements.
- [PLAN.md](PLAN.md) — existing milestone work (citation labels in test
  names) and the Known Deferred Items list. The refactor pauses the
  citation-labeling milestone; the deferred items remain authoritative.
- [GUIDE.md](GUIDE.md) — user-facing docs that need updating once the doc
  shape changes (Phases 4, 8, 10).
- LPeg skill — §2 (the discipline + its border) and §3 (planning the
  grammar) are the design reference for this refactor.
- `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/`
  — primary spec sources (RFCs via WebFetch; TR-10 markdowns; SMPTE PDFs).
