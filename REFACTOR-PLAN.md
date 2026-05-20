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
- **6.C.C (complete)** — ST 2110-20:2022 §7.2 + §7.4.2 raw video
  required Media Type parameters (sampling, width, height,
  exactframerate, depth, colorimetry, PM, SSN) plus ST 2110-21:2022
  §8.1 (TP). 9 new error ids `st2110-20.a.fmtp.<key>-required` in
  `errors.lua`. Implemented as a post-parse semantic check on the ST
  2110 tier: walks `doc.media`, builds a per-block raw-PT set from
  `a=rtpmap` attributes, locates the matching `a=fmtp`, and records a
  finding for each absent required key in spec order. Registered via
  the new `overrides.semantic_checks` slot in
  `parse_sdp.grammar.st2110`. 11 new tests; suite 1166 green. Inherits
  the same rtpmap-before-fmtp ordering caveat as 6.C.B.
- **6.C.D.1 (complete)** — seven raw video fmtp enum value-set
  narrowings (sampling §7.2 — 12 values; depth §7.4.2 — 5;
  colorimetry §7.5 — 9; PM §6.3 — 2; TP ST 2110-21:2022 §8.1 — 3;
  TCS §7.6 — 11 incl. `ST2115LOGS3`; RANGE §7.3 — 3). 7 new error
  ids `st2110-20.a.fmtp.<key>-invalid-value`. Implemented as a
  second tier-level semantic check `check_raw_video_fmtp_values`
  alongside the §7.2 presence check, with a shared
  `each_raw_video_fmtp` helper. Value sets lifted verbatim from
  the 1.0 parser's VALID_* constants. 60 new tests; suite 1226 green.
- **6.C.D.2 (complete)** — non-enum value forms for raw video fmtp
  (width / height integer 1..32767; exactframerate integer or N/D
  in lowest terms; MAXUDP integer ≤8960; PAR W:H in lowest terms;
  SSN `ST2110-20:2017` or `ST2110-20:2022`) and flag-only
  `interlace` / `segmented`. 8 new error ids
  `st2110-20.a.fmtp.<key>-invalid-value`. Same
  `check_raw_video_fmtp_values` semantic check extended with
  per-key validator functions ported from the 1.0 parser's
  predicates. 33 new tests; suite 1259 green.
- **6.C.E (complete)** — seven raw video fmtp cross-parameter
  SHALLs ported from the 1.0 parser at `parse_sdp.lua:2063-2158`:
  §7.2 SSN-conditional (forward direction); §7.3 BT2100 RANGE
  narrowing (FULLPROTECT forbidden); §7.3 segmented-requires-
  interlace; §6.3.3 BPM forbids MAXUDP; §7.4.1 KEY-requires-ALPHA;
  §7.4.1 KEY-forbids-TCS; §6.2.5 4:2:0-progressive-only.
  7 new error ids `st2110-20.a.fmtp.<constraint>`. Implemented as
  a third tier-level semantic check
  `check_raw_video_fmtp_cross_param` alongside the
  presence-check (6.C.C) and value-form check (6.C.D), all sharing
  `each_raw_video_fmtp(doc)`. 29 new tests; suite 1282 green.
  Cross-param coverage now at parity with 1.0.
- **6.C.F (complete)** — five cross-parameter SHALLs normatively
  in ST 2110-20:2022 that the 1.0 parser did NOT enforce, now in
  the grammar tier (`audits/SPEC_INVENTORY.md` rows 61, 115, 116,
  117, 118):
  - §6.2.5 Table 3 — 4:2:0 sampling permits only depth ∈ {8, 10,
    12}; depth ∈ {16, 16f} rejected.
  - §7.6 LINEAR row — TCS=LINEAR requires depth=16f.
  - §7.6 BT2100LINPQ row — TCS=BT2100LINPQ requires depth=16f.
  - §7.6 BT2100LINHLG row — TCS=BT2100LINHLG requires depth=16f.
  - §7.6 ST2065-1 row — TCS=ST2065-1 requires depth=16f.

  5 new error ids in `errors.lua`. Two helper functions
  (`check_420_depth_restricted`, `check_tcs_floating_point_depth`)
  appended to the existing `check_raw_video_fmtp_cross_param`
  semantic check. The SHALL grounding is CLAUDE.md strictness
  polarity #3 (defined value forms — Table 3 and §7.6 row
  parentheticals `(depth=16f)`), not explicit SHALL prose. 39 new
  tests; suite 1321 green. The grammar tier is now strictly more
  conformant than 1.0 for ST 2110-20 raw video fmtp.
- **6.C.G.1 (complete)** — ST 2110-22 jxsv fmtp required-param
  presence (4 params from §7.2 + RFC 9134) and per-key value
  narrowings (16 value-form/flag-only error ids). Notable RFC
  9134 vs 1.0 enum corrections for colorimetry (3 legacy values
  added, ALPHA removed), TCS (narrowed to 4 values), and
  sampling (UNSPECIFIED added). Generalized
  `each_raw_video_fmtp` to `each_fmtp_for_encoding(doc, enc)`.
  133 new tests; suite 1437 green.
- **6.C.G.2 (complete)** — ST 2110-22 jxsv cross-parameter
  SHALLs from RFC 9134 §7.1: segmented-requires-interlace and
  BT2100/RANGE narrowing. 2 new error ids, 1 new semantic check.
  8 new tests; suite 1445 green. Closes the jxsv fmtp port.
- **6.C.H (complete)** — ST 2110-30 / -31 audio channel-order
  RFC 3190 syntax check on L16 / L24 / AM824. 2 new error ids
  (`-30` channel-order-invalid for syntax/group-symbol failures;
  `-31` channel-order-aes3-requires-am824 for the
  cross-encoding SHALL). New `each_audio_fmtp(doc)` helper.
  22 new tests; suite 1467 green.
- **6.C.I (complete)** — ST 2110-31:2022 §6.1 AM824 rtpmap
  channel-count parity (1.0-parity port that 6.B missed).
  1 new error id, 1 new semantic check. 14 new tests; suite
  1481 green.
- **6.C.J (complete)** — ST 2110-41:2024 Fast Metadata fmtp
  (SSN required + value form, DIT optional with hex-token
  value form, MAXUDP forbidden per §5.4). 4 new error ids,
  1 new semantic check. 12 new tests; suite 1493 green.

**Phase 6.C is now closed.** The grammar tier matches or
exceeds 1.0 parity for every ST 2110 encoding's `a=fmtp`
constraints (-20, -22, -30, -31, -41). Several spec-conformant
1.0-gap closes landed: §6.2.5 Table 3 4:2:0/depth, §7.6
TCS/depth=16f coupling, RFC 9134 enum corrections for jxsv,
AM824 channel parity.

- **6.D.A (complete)** — ST 2110-10:2022 §8.2 + §8.3 per-media-
  block presence checks for `a=ts-refclk` and media-level
  `a=mediaclk`, lifted from the 1.0 parser with citation corrections
  (1.0 cited §7.2 / §7.3; primary text places the SHALLs at §8.2 /
  §8.3). Two new error ids `st2110.attr.ts-refclk-required` and
  `st2110.attr.mediaclk-required`. Two tier-level semantic checks
  walking `doc.media` with a small `media_block_has_attr` /
  `session_has_attr` helper pair. RFC 7273 §4.8 session-level
  ts-refclk covers all media blocks; §8.3's "media-level" qualifier
  means session-level mediaclk does NOT satisfy a per-stream SHALL.
  The `build()` / `build_with_fmtp()` helpers in
  `spec/grammar_st2110_spec.lua` and the `MINIMAL_WITH_RTPMAP`
  fixture in `spec/grammar_compose_spec.lua` now include both
  timing attributes by default so the existing ~140 grammar-tier
  tests survive. 8 new tests; suite 1501 green.
- **6.D.B (complete)** — ST 2110-30:2025 §6.2.1 audio MAXUDP-
  forbidden (L16 / L24 only). 1 new error id
  `st2110-30.a.fmtp.maxudp-forbidden`. Walks `each_audio_fmtp` and
  emits when encoding ∈ {L16, L24} and `params.MAXUDP` is set.
  **Intentional non-parity with 1.0**: the 1.0 parser also forbids
  MAXUDP on AM824 with the cite "ST 2110-31 §5.x inherits" — that
  cite is conjecture; -31 §5.2 actually defers to -10 which
  *permits* MAXUDP (§6.5). No -31 SHALL forbids it. Grammar tier
  ports only the well-grounded -30 limb. 5 new tests; suite 1506
  green. Flagged for audit-folder follow-up: candidate to remove
  1.0's AM824 MAXUDP-forbidden check.
- **6.D.C (complete)** — ST 2110-31:2022 §6.1 AM824 rtpmap
  channels-required (AM824 only). 1 new error id
  `st2110-31.a.rtpmap.am824-channels-required`. **Intentional
  non-parity with 1.0**: 1.0 also enforces channels-required for
  L16 / L24 per an unverified "ST 2110-30 tightens RFC 3551"
  annotation; primary text of -30 / AES67 / RFC 3551 §6 does NOT
  carry that SHALL — RFC 3551 §6 explicitly makes channels
  OPTIONAL (default 1). 5 new tests; suite 1511 green. Flagged for
  audit-folder follow-up: candidate to remove 1.0's L16/L24
  channels-required check.
- **6.D.D (complete)** — ST 2110-30:2025 §6.2.1 audio packet-
  payload-fit (L16/L24 only). 1 new error id
  `st2110-30.audio.packet-payload-fit`. Computes
  `needed = channels × bytes_per_sample × samples_per_packet`
  (where `samples_per_packet = round(clock_rate × ptime / 1000)`
  per AES67 §8.1) and rejects when needed > 1448 octets
  (1460 UDP - 12 RTP header). RFC 3551 §6's `channels=1` default
  applied when channels is absent on rtpmap. AM824 deferred (same
  reason as 6.D.B). 9 new tests; suite 1520 green.

**Phase 6.D is now closed.** Grammar tier matches 1.0 parity on
every well-grounded per-encoding required-attribute and cross-
attribute SHALL. Three out-of-parity flags carry forward for
separate audit follow-up: 1.0 enforces MAXUDP-forbidden on AM824,
channels-required on L16/L24, and packet-payload-fit on AM824 —
none of these are grounded in -30 / -31 primary text.

- **6.E.A (complete)** — RFC 5888 group attribute cross-stream
  invariants (base SDP tier). 2 new error ids
  `sdp.a.group.requires-mid-on-all-media` (§6 parity port) and
  `sdp.a.group.references-port-zero-mid` (§9.2, 1.0-gap close).
  New base-tier semantic check `check_group_attribute_invariants`
  does one doc walk for both passes. 7 new tests; suite 1527 green.
- **6.E.B (complete)** — ST 2110-10:2022 §8.5 + ST 2022-7:2019 §6
  group:DUP leg coherence (ST 2110 tier). Full 7-check port from
  1.0 via the cite chain (§8.5 invokes ST 2022-7 §6, which
  requires at-least-two streams with bit-identical RTP headers +
  payloads — necessary condition: SDP attrs defining packet shape
  must match across legs). 7 new error ids
  `st2110-10.a.group-dup.{mid-resolve, min-2-legs,
  media-type-same, rtpmap-same, payload-type-same, fmtp-same,
  addr-coherence}`. Improvement over 1.0: fmtp comparison is
  order-insensitive (decomposed `params` table compare instead of
  raw value-string compare). 11 new tests; suite 1538 green.

**Phase 6.E is now closed.** Phase 6 as a whole (6.A–6.E) ships
the full ST 2110 + base-SDP cross-stream and per-encoding
coverage set. Grammar tier matches or exceeds the 1.0 parser on
every check grounded in primary spec text; three 1.0-over-strict
flags from 6.D (audio MAXUDP / channels-required / packet-fit
limbs for AM824 or L16/L24) remain flagged in `audits/` for
separate follow-up.

- **6.F (complete)** — in-grammar refactor. 11 of 13 ST 2110-tier
  checks moved out of `semantic_checks` (the doc-walk
  Lua-massage-between-stages slot) and into LPeg `Cmt` callbacks
  on the actual grammar rules. Per-fmtp-line dispatch via a new
  `FMTP_CHECKS_BY_ENCODING` table + a trailing Cmt on `a_fmtp`
  (Category A: 9 checks). Per-rtpmap-line checks for AM824
  channels-required + channels-even merged into the
  `st2110_rtpmap_am824` branch (Category B: 2 checks). One small
  bridge check `check_rtpmap_requires_fmtp` stays in
  `semantic_checks` (covers the "rtpmap present, no fmtp at all"
  case the in-grammar dispatch can't see) until `media_section`
  Cmt infrastructure exists. Net code reduction: ~50 lines.
  Tradeoff: per-fmtp findings lose the `media[N].attributes[...]`
  field_path prefix (grammar doesn't track media-index). Suite
  unchanged at 1538 green. Updates [[lpeg-discipline]] memory
  with the per-category placement rule.
- **6.G (complete)** — diagnostic-position plumbing + cleanup.
  Wires byte position from in-grammar Cmts to (line, col) in
  the formatted error output: `errors.pos_to_line_col` + ctx.text
  threaded through `make_match` + every Cmt that emits a finding
  now passes `loc.pos = pos`. Per-fmtp / per-rtpmap findings
  recover real line numbers (col, too), restoring most of the
  diagnostic context the 6.F refactor traded away when it dropped
  the `media[N]` field_path prefix. Also: dead `path` parameter
  on the 10 raw/jxsv cross-param helpers (always `""` since 6.F)
  replaced with `pos`, fixing the smell and threading position in
  one pass. 8 new tests (3 unit + 3 unit + 2 integration); suite
  1546 green.
- **6.H (complete)** — applied 6.F's principle to base.lua.
  `check_connection_addresses` moved in-grammar as a Cmt on
  `c_value` (uses Cb"addr_type" + Cb"address" inside the
  surrounding Ct; pos threads through 6.G's plumbing). Audited
  the remaining 4 base semantic_checks:
  `check_dynamic_pt_rtpmap` and `check_tsrefclk_traceability` are
  per-media-block and could move to a `media_section` Cmt if/when
  that infrastructure lands; `check_mid_uniqueness` and `check_group_attribute_invariants`
  span media blocks and stay doc-level. base_semantic_checks
  dropped from 5 to 4 entries. One test relaxed (line-number
  assertion instead of field_path). Suite unchanged at 1546.
- **6.I (deferred)** — topical reorganization of
  `spec/grammar_st2110_spec.lua` per the test-ordering principle
  ([[test-ordering]] memory: base SDP first, then ST 2110
  extensions in spec order -10 / -20 / -22 / -30 / -31 / -40 /
  -41, then TR-10-N hierarchy). 5 phase-tagged blocks (6.D.A,
  6.D.B, 6.D.C, 6.D.D, 6.E.B) were appended at the file end
  during May 2026 development and should slot into their
  respective encoding sections. Test-only commit, no logic
  change. Deferred to a later session; pending work tracked in
  this bullet so a future agent picks it up.
- **6.J (complete)** — shared numeric-value-form patterns +
  validator sweep. New `parse_sdp/grammar/patterns.lua` module
  exposes `pos_int_raw` / `zero_based_int_raw` / `int_raw`
  (composable) and `pos_int` / `int` / `fraction` / `ratio`
  (anchored for whole-string validation). `base.lua`'s
  `rfc8866_pos_int` and `rfc8866_zero_based_int` V-rules alias
  the shared primitives; `st2110.lua`'s 6 value validators
  (`validate_pixel_dim`, `validate_exactframerate`,
  `validate_maxudp`, `validate_par`, `validate_positive_integer`,
  `validate_integer`) rewritten to use them. Dropped the
  `make_pixel_dim_validator` factory (no-arg, returned identical
  closure on every call). Net wins: 4 fewer closure allocations
  at load, 7 inline `:match` strings collapsed, stricter
  leading-zero rejection (POS-DIGIT *DIGIT instead of `%d+`). 21
  new tests in `spec/grammar_patterns_spec.lua`; suite 1567 green.
  Phase 7 (IPMX) inherits the shared patterns by `require`.
- **6.K (complete)** — `media_section` Cmt infrastructure +
  per-block check migrations + diagnostic field_path recovery.
  Closes both "future infrastructure gaps" flagged after 6.H.
  base.lua's `media_section` rule now wrapped in two Cmts
  (leading: increment `ctx.media_index` 0-indexed; trailing:
  dispatch `ctx.media_section_checks`). New
  `media_section_checks` slot parallel to `semantic_checks`;
  `extend()` merges per-tier overrides. 5 checks migrated out
  of `semantic_checks` (check_dynamic_pt_rtpmap,
  check_media_tsrefclk_traceability, check_rtpmap_requires_fmtp,
  check_mediaclk_presence, check_audio_packet_payload_fit) —
  `semantic_checks` is now strictly cross-section invariants.
  All in-grammar Cmts that emit findings now thread
  `field_path = "media[N].attributes[<attr>:pt=<PT>]"` through
  `errors.record` via the `fmtp_dispatch` pre-format. 9 per-fmtp
  check functions + 8 cross-param helpers + 2 AM824 rtpmap Cmts
  updated. `errors.format` now emits both field_path AND
  line/col when both present (was `elseif`). Pre-existing
  `loc.context` overload bug fixed (string-only highlight path).
  Suite 1569 green (up from 1567). Phase 7 IPMX inherits the
  full slot machinery.
- **6.L (complete)** — `validate_channel_order` LPeg sweep
  (last inline-regex validator in st2110.lua). Replaced 5
  `string.match` / `gmatch` calls with a small LPeg grammar
  encoding ST 2110-30 §6.2.2 + ST 2110-31 §6.2 Table 2 + RFC
  3190 channel-order syntax. The AES3-on-AM824 cross-encoding
  check stays in Lua (it depends on a runtime argument). Udd
  range 01..64 enforced by three sub-range alternatives in pure
  pattern algebra. `AUDIO_CHANNEL_GROUPS` constant deleted.
  Suite unchanged at 1569 green. Closes the "code review"
  thread that started with the `make_pixel_dim_validator`
  factory and produced 6.J + 6.L.

**Phase 7 — IPMX grammar via `extend(st2110_rules, ...)`.**
Same pattern, IPMX-specific from TR-10 markdowns. Re-verify each citation
against the TR-10 part it claims (per CLAUDE.md Spec Verification Protocol).

- **7.A (complete)** — composition shell. New
  `parse_sdp/grammar/ipmx.lua` chains st2110 via
  `st2110.extend(st2110, {})`. Internal entry point only;
  `sdp.parse(text, "ipmx")` remains on the 1.0 path until Phase 9.
  6 new composition-parity tests in
  `spec/grammar_compose_spec.lua` (shape, accept/reject parity with
  st2110, semantic_checks + media_section_checks inheritance ordering,
  distinct table identity). Suite 1575 green.
- **7.B (complete)** — TR-10-1 §10 baseline ("this SDP is IPMX"):
  §10 forbids `a=group:FID`, §10.1 requires the `IPMX` token in
  `a=fmtp` on every RTP media block. 2 new error ids
  `tr-10-1.a.group.fid-forbidden` and
  `tr-10-1.a.fmtp.marker-required`. FID prohibition lands as an
  in-grammar override of base's `a_group` rule (trailing Cmt reads
  `Cb"semantics"` and emits the finding when the value is "FID"); the
  fmtp marker check lands in `media_section_checks` (per-RTP-block).
  Phase 7.B also introduced `base.is_rtp_block(block)` — an LPeg-
  driven `proto = "RTP" / "RTP/..."` predicate that replaces the
  pre-existing `block.proto:find("RTP", 1, true)` string-library calls
  in base.lua's `check_dynamic_pt_rtpmap` and the new IPMX checks
  (keeps the codebase inside the parser per [[lpeg-discipline]]). New
  `spec/grammar_ipmx_spec.lua` with topical TR-10-1 §10 / §10.1
  describe blocks. Suite 1586 green after the initial slice;
  re-verified to literal spec text on review: §10.1 reads
  "IPMX Senders shall include the ' IPMX' declaration in the a=fmtp
  clause of the SDP file" — singular "the a=fmtp clause", no "every".
  The check now fires per RTP block only when at-least-one a=fmtp is
  present AND none of them carries the IPMX flag; field_path is
  block-level (no `:pt=N` suffix). Earlier "audit-folder follow-up"
  language removed.
- **7.C (complete)** — TR-10-1 §10.2 (extended by TR-10-9 §10) video
  IPMX fmtp required parameters. Every RTP video block's `a=fmtp`
  must carry `measuredpixclk`, `vtotal`, and `htotal` as positive
  integers (RFC 8866 §9 ABNF `POS-DIGIT *DIGIT` via
  `patterns.pos_int:match`). 6 new error ids
  (`tr-10-1.a.fmtp.<key>-required` and `<key>-invalid-value` for each
  of the three keys). Wired via a new `ipmx_fmtp_dispatch` that
  chains after st2110's per-encoding dispatch on the `a_fmtp` rule;
  IPMX_FMTP_CHECKS_BY_ENCODING keys raw + jxsv to the IPMX video
  check function (TR-10-2 §7 / TR-10-11 §7 inheritance). 18 new
  tests; suite 1604 green. Single-walk merged-function refactor of
  `check_ipmx_video_fmtp` (combines presence and value-form checks
  into one walk per key, per the user's DRY pushback).
- **7.D (complete)** — TR-10-1 §10.3 (extended by TR-10-9 §10) audio
  IPMX fmtp required parameter `measuredsamplerate`. 2 new error ids
  `tr-10-1.a.fmtp.measuredsamplerate-required` / `-invalid-value`.
  IPMX_FMTP_CHECKS_BY_ENCODING also keys L16 / L24 / AM824 to
  `check_ipmx_audio_fmtp`. 10 new tests; suite 1614 green.
- **7.E (complete)** — TR-10-2/-3/-4/-11/-12 §7 IPMX RTP UDP port
  constraints: port MUST be even AND > 1024. 2 new error ids
  `ipmx.m.port-must-be-even` and `ipmx.m.port-must-exceed-1024`. New
  per-block `check_ipmx_port_constraints` in `media_section_checks`,
  gated by `is_rtp_block`. 8 new tests; suite 1622 green.
- **7.F (complete)** — ST 2110-22:2022 §7.3 jxsv `b=AS:<kbps>`
  requirement: every jxsv media block MUST carry `b=AS` with brvalue
  a positive integer (RFC 8866 §9 ABNF `integer`). 2 new error ids
  `st2110-22.b.as-required` / `as-invalid-value`. New per-block
  `check_jxsv_bandwidth` in `media_section_checks`, encoding-gated
  on rtpmap `jxsv`. The check lives at the ST 2110 tier where
  §7.3 authors the SHALL ("The media-level section of the SDP
  object shall include the attribute listed in Table 3"); TR-10-7
  §11 substitutes only the Table 3 row's cell semantics (changes
  brvalue from "average" to "maximum target bit rate") — the
  wrapping presence SHALL is unchanged and inherited via composition
  by the IPMX tier. Re-placement on review: the initial slice put
  the check at the IPMX tier matching 1.0's placement, but the 1.0
  placement conflated 1.0's monolithic file structure with spec
  authorship; per CLAUDE.md the check belongs where the spec
  authors it. Phase 6 jxsv test fixtures retro-fitted with b=AS
  (build helpers in `spec/grammar_st2110_spec.lua` add
  `b=AS:1500000` whenever the rtpmap encoding is jxsv, via an LPeg
  substring match). New `b=AS` describe block topically placed
  next to the jxsv rtpmap-narrowing block. 6 new ST 2110 tests
  (8 IPMX tests were removed when the IPMX-tier mirror was
  deleted); suite 1710 green.
- **7.G (complete)** — TR-10-10 §8 `a=infoframe` HDMI InfoFrame
  signaling attribute. Adds `a_tier_extensions` and `tier_attr_names`
  hooks to base.lua's `a_value` alternation and `known_attr_lookahead`
  (default `P(false)` — never matches; tiers override to add new
  attributes without redeclaring the alternations). IPMX overrides
  add the new `a_infoframe` rule that parses
  `<port> SSN=<ssn>;DIT=<dit>` and validates: session-level only,
  SSN matches `ST2110-41:<year>`, DIT equals literally "100100".
  Cross-section semantic_check verifies port equals some media
  port + 3 and ports are unique. 5 new error ids; 10 new tests;
  suite 1639 green.
- **7.H (complete)** — TR-10-5 §10 `a=hkep` HDCP Key Exchange Protocol
  attribute. New `a_hkep` rule parses
  `<port> <nettype> <addrtype> <addr> <node-id> <port-id>` with
  in-grammar Cmt validating: nettype = "IN", addrtype ∈ {IP4, IP6},
  node-id is `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (32 hex digits in
  5 groups, anchored LPeg pattern), port-id is `xx-xx-xx-xx-xx`
  (10 hex digits in 5 pairs). Accepts session- and media-level per
  TR-10-5 §17; addr syntax not validated per TR-10-5 §10. 4 new
  error ids; 11 new tests; suite 1650 green.
- **7.I (complete)** — TR-10-6 §7.6 FEC parameter signaling in
  `a=fmtp`: `FECPROFILE` value MUST be `profile-a` when present, and
  `FEC_ADD_LATENCY_VIDEO` / `FEC_ADD_LATENCY_AUDIO` (when present)
  MUST (a) have a non-negative integer value and (b) require
  `FECPROFILE` to also be present. New `IPMX_FMTP_UNIVERSAL_CHECKS`
  slot in the IPMX fmtp dispatch — encoding-agnostic checks that run
  on every RTP fmtp regardless of rtpmap encoding. New
  `zero_based_int` export in `patterns.lua` for the non-negative
  integer validation. 5 new error ids; 12 new tests; suite 1662 green.
- **7.J (complete)** — TR-10-13 §13 `a=privacy` attribute. New
  `a_privacy` rule parses the `<key>=<value>; <key>=<value>; ...`
  kv-list and a trailing Cmt validates: 6 required params present
  (protocol, mode, iv, key_generator, key_version, key_id), no
  trailing semicolon, `protocol != "NULL"` (§13 line 352),
  `mode` in the 12-value TR-10-13 §20.1 enum (subsumes the
  NULL-mode prohibition since NULL is outside the enum), and per-key
  hex form/length checks (iv = 16, key_generator = 32,
  key_version = 8, key_id = 16 hex digits — all anchored LPeg
  patterns built from a `HEX^n * P(-1)` helper). 13 new error ids;
  32 new tests; suite 1694 green.
- **7.K (complete)** — TR-10-13 §20.1 `a=extmap` direction for PEP
  IV-Counter URNs. New semantic_check verifies that when an
  `a=extmap` URI is one of the PEP IV-Counter URNs (full / short),
  its direction MUST equal `sendonly`. Implemented as a post-parse
  doc walk rather than in-grammar — base's `a_extmap` rule wraps
  `direction` in an optional Cg, so a Cb back-reference inside a
  trailing Cmt would raise "back reference not found" when the
  optional didn't fire. The doc walk reads `attr.direction` cleanly
  (nil when absent). 1 new error id; 8 new tests; suite 1702 green.
- **7.L (complete)** — TR-10-14 §14 USB transport block
  (`m=application TCP usb`) constraints. New `is_usb_block(block)`
  helper in base.lua (LPeg/structural — matches the literal proto
  triple). New media_section_check `check_usb_block` validates:
  a=setup is present (RFC 4145 §3 via TR-10-14 §14 line 724) and
  equals "passive" (line 740), and when a=privacy is present its
  `protocol` parameter equals `USB_KV` (line 736). 3 new error ids.
  Also gates the ST 2110 `ts-refclk-required` and `mediaclk-required`
  checks on `is_rtp_block` so non-RTP USB blocks don't spuriously
  trip RTP-specific timing-attribute SHALLs. Intentional
  non-parity flag: 1.0 forbids rtpmap / fmtp / mediaclk /
  ts-refclk on USB blocks; TR-10-14 §14 only says "follow RFC 4145"
  without explicitly forbidding those attributes, so the
  forbidden-attribute check is documented as a 1.0-over-strict
  audit-folder follow-up rather than ported. 9 new tests; suite
  1711 green.

**Phase 7 closed (A–L).** Grammar tier covers every SDP-touching
SHALL the 1.0 IPMX validator enforces that is grounded in primary
TR-10 / ST 2110-22 spec text. After review, three earlier
"non-parity flags" were re-verified against the primary spec text:

- **7.B**: TR-10-1 §10.1 reads "shall include the ' IPMX' declaration
  in the a=fmtp clause of the SDP file" — no "every", singular "the".
  The check is at-least-one-per-RTP-block, not every-fmtp. Earlier
  "strict reading deferred" language was a misread of the SHALL.
- **7.F**: ST 2110-22:2022 §7.3 is the authoring SHALL ("The
  media-level section of the SDP object shall include the attribute
  listed in Table 3"). TR-10-7 §11 substitutes only the Table 3
  row's cell semantics; the §7.3 presence SHALL is unchanged. The
  check is now at the ST 2110 tier where it belongs; IPMX inherits
  via composition.
- **7.L**: TR-10-14 §14 says "follow RFC 4145 with the following
  restrictions" and enumerates the restrictions ("media space port
  set to 'application/usb'", "'role' of 'setup' shall be 'passive'",
  privacy "protocol : USB_KV"). It does NOT say `rtpmap`, `fmtp`,
  `mediaclk`, or `ts-refclk` are forbidden on USB blocks — the 1.0
  validator's "RFC 4145 doesn't use RTP-specific attributes"
  reasoning is interpretation, not spec text. Per CLAUDE.md's
  strictness principle, the grammar tier does not enforce that
  prohibition.

Also two DRY cleanups landed during Phase 7: the
`check_*_fmtp_required` + `_values` function pairs in ST 2110
(raw_video and jxsv) and IPMX (video and audio) were merged into
single-walk functions per the user's "neat and tidy" pushback.
Final test count: 1711 green.

**Phase 8 — Serializer rewrite.**
Render from structured doc, never from stored strings. Round-trip invariant
test runs on every fixture in `examples/{generic,st2110,ipmx}/valid/`.

Sub-slice ordering (decided 2026-05-20 in planning conversation):

- **8.A (complete)** — bootstrap shell. New
  `parse_sdp/serialize.lua` exporting `M.to_sdp(doc)`; new
  `spec/roundtrip_spec.lua` whose helper parses via
  `parse_sdp.grammar.base.match`, serializes via the new module,
  re-parses, and deep-equals. 8.A scope: v / o / s / t only —
  optional session fields, multi t-blocks, r= / z=, attributes,
  and media blocks defer to 8.B. Structural-completeness contract
  also established here: missing required fields → `nil, err`
  (the "Serializer never validates. Validate never serializes."
  invariant added to [CLAUDE.md](CLAUDE.md#things-to-watch-out-for)).
  Public API stays on 1.0 serializer; the new module is internal
  until Phase 9. 11 new tests; suite 1721 green (was 1710).
- **8.B (complete)** — base SDP optional session fields (i, u, e*,
  p*, c, b*), r= repeats inside time_descriptions, z= time zones,
  session-level generic + flag a= attributes, and media blocks
  (m + port_count + proto + fmts; i, c, b*, generic+flag a* per
  block). `parse_sdp/serialize.lua` grows the section renderers
  (`render_connection`, `render_bandwidths`, `render_repeats`,
  `render_time_zones`, `render_attribute`, `render_media_block`)
  and a `ATTR_RENDERERS` dispatch table populated empty (filled
  by 8.D / 8.E). Compound attribute names (rtpmap, fmtp, mid,
  ts-refclk, …) still fall through to the generic carrier in 8.B;
  fixtures use static PTs only (≤95) so the grammar's
  dynamic-PT-requires-rtpmap check doesn't trip. 21 new tests in
  `spec/roundtrip_spec.lua` covering full session round-trip,
  multi e=/p=/b=, multiple t= blocks with r= repeats (numeric and
  typed-time `7d 1h 0 25h`), z= one-pair and multi-pair, flag and
  generic name:value attributes, attribute order preservation,
  media blocks with all optional fields, `m=video N/2 RTP/AVP 33`
  port_count, multi-fmts, multi-block ordering, plus
  structural-completeness errors for missing m.media / empty
  m.fmts / missing r.offsets / missing b.type / missing c.address.
  Suite 1742 green (was 1721).
- **8.C (complete)** — fmtp params order preservation. Grammar-tier
  change: `a_fmtp`'s decomposable branch (both base.lua's
  `fmtp_params_branch` and st2110.lua's `fmtp_st2110_raw_params`
  override) now captures `params` as an ordered Ct of
  `{key, value | true}` sub-tables — the same shape `a=privacy`
  has used since 7.J. Input key order is preserved for the
  serializer's text-identical round-trip. The
  `fmtp_entries_to_params` postprocessor (and the `M.` export of
  it) is gone; in its place a single helper
  `M.params_get(params, key)` is the lookup primitive for any
  consumer that needs a by-key read off either an fmtp or a
  privacy params list. `params_get` is threaded through
  `base.extend` so child tiers inherit it cleanly. 44 consumer
  sites updated across `parse_sdp/grammar/st2110.lua` (27),
  `parse_sdp/grammar/ipmx.lua` (6), and
  `spec/grammar_base_spec.lua` (11) via a mechanical agent pass
  (verified by the user against the full suite). Privacy code
  (`a_privacy` / `check_a_privacy` / `check_usb_block`) was
  already on the ordered-list shape and stayed untouched.
  `params_equal` (group:DUP fmtp comparison) rewritten to compare
  by-key with `#a ~= #b` short-circuit, preserving its order-
  insensitive semantics. Suite 1742 green (unchanged — pure shape
  refactor, no behavior change).
- **8.D (complete)** — base compound-attribute renderers. Per-name
  dispatch table `ATTR_RENDERERS` in `parse_sdp/serialize.lua`;
  every `a_<name>` rule in `parse_sdp/grammar/base.lua` now has an
  inverse. Bootstrap (rtpmap + `require_fields` helper + dispatch
  scaffold) landed first, then three sub-slices closed the
  remaining 17 renderers:
  - **8.D.1 (complete)** — value-only attrs: mid, ptime, maxptime,
    framerate, quality, msid (msid_id + optional appdata), ssrc
    (ssrc_id + attribute + optional value), rtcp-mux (flag).
    19 new tests; suite 1767 green (was 1748).
  - **8.D.2 (complete)** — RTP-stack attrs: fmtp, rtcp, rtcp-fb,
    extmap, ssrc-group. fmtp is the critical one — walks
    `attr.params` (the ordered Ct from 8.C) positionally so
    decomposed-kv round-trip is text-identical, falls through to
    `attr.raw` for opaque byte-strings. rtcp enforces the
    all-or-nothing optional `net_type+addr_type+address` triple via
    `require_fields`. rtcp-fb handles polymorphic payload_type
    (number or `"*"`) via `tostring`. 21 new tests; suite 1788 green.
  - **8.D.3 (complete)** — clock + grouping: ts-refclk (branches
    on `attr.source` to per-branch builders via TSR_BUILDERS table —
    ntp / ptp / private / bare / ext), mediaclk (branches on
    `attr.mode` via MC_BUILDERS — sender / direct / IEEE1722 / ext —
    with optional `id=` prefix), group (semantics + zero-or-more
    tags), source-filter (all five Cg fields required, ≥1
    src_address). The `BUILDERS[key] or build_ext` idiom keeps
    branch dispatch DRY without a mega-function. 29 new tests;
    suite 1817 green.

  Producer-side contract held throughout: required fields error
  early via `require_fields`; optional fields silently omitted
  when absent; no fallback to legacy `attr.value` string shape on
  known-decomposed names. Grammar-tier worktree isolation was
  attempted for 8.D.1/.2/.3 parallelism but the harness pointed
  the worktrees at a stale 1.0.0 snapshot; 8.D.1 worked around it
  by editing the main repo directly, and 8.D.2/.3 were run
  sequentially without isolation. Pattern noted for future agent
  dispatch (see [[project-phase8-tooling]] if memory captures the
  lesson).
- **8.E (complete)** — IPMX-tier attribute renderers. Three new
  `ATTR_RENDERERS` entries in `parse_sdp/serialize.lua` cover every
  attribute the IPMX tier adds via `a_tier_extensions`:
  - `infoframe` — `<port> SSN=<ssn>;DIT=<dit>` per TR-10-10 §8.
    Required: port, ssn, dit.
  - `hkep` — `<port> <nettype> <addrtype> <addr> <node_id> <port_id>`
    per TR-10-5 §10. Required: all six fields. Doc-shape keys mirror
    the grammar's Cg names (`nettype`/`addrtype`/`addr`), distinct
    from the c= line's underscored field names.
  - `privacy` — `key=value;...[;]` per TR-10-13 §13. Walks
    `attr.params` (the ordered Ct shape from 8.C) positionally and
    emits with `;` separators (no space — re-parses cleanly under
    the grammar's `;` + SP^-1 separator). Honors the captured
    `trailing_semi` boolean so a malformed §13 trailing-`;` line
    round-trips faithfully (same finding fires on the re-parse).

  Round-trip tests drive through `ipmx.match` with `fail_on_first =
  false` so the renderer exercise stays focused on doc-shape
  preservation; cross-section IPMX checks (e.g. infoframe
  port-must-match-media-plus-3) record findings into ctx without
  aborting the match, so doc1 == doc2 even when the fixture isn't
  fully IPMX-conformant. Full-fixture validation lands in 8.F.
  16 new tests; suite 1833 green (was 1817).
- **8.F (complete)** — fixture-wide round-trip. New describe block
  in `spec/roundtrip_spec.lua` discovers every
  `examples/{generic,st2110,ipmx}/valid/*.sdp` via `io.popen("ls ...")`
  and runs each through `parse → serialize → re-parse → deep-equal`
  under its tier matcher (`base.match` / `st2110.match` / `ipmx.match`)
  with default opts (`fail_on_first = true`). 19 fixture tests
  added (5 generic + 9 ST 2110 + 5 IPMX); suite 1852 green (was
  1833). Triage surfaced two real bugs and three fixture bugs:
  - **Grammar bug** (fixed): `a_source_filter` required no SP
    between `:` and the filter-mode token, but RFC 4570 Appendix A
    ABNF explicitly defines
    `"source-filter" ":" SP filter-mode SP filter-spec`. The
    `SP` after `:` is required by the spec; the IPMX fixtures
    already write the spec-conformant form. Fixed
    `parse_sdp/grammar/base.lua` (`P("source-filter:") * SP ...`)
    and `parse_sdp/serialize.lua` (emit the SP between
    `source-filter:` and the filter-mode token). Re-grounded the
    rule comments against Appendix A. 12
    existing test inputs across
    `spec/grammar_base_spec.lua` (4),
    `spec/grammar_st2110_spec.lua` (4), and
    `spec/roundtrip_spec.lua` (4 source-filter cases × 2
    input/output strings) were updated mechanically to the SP
    form. The 1.0 parser at `parse_sdp.lua:802` accepted both
    forms via `P(" ")^-1` with a comment ("Some senders include
    a leading space after the `:` — accept it"); that was an
    opinion-based loosening of the ABNF and is removed in the
    grammar-tier port per CLAUDE.md's strictness principle.
  - **Fixture bugs** (fixed): three fixtures used
    `m=application` for `smpte291` ANC streams, violating
    RFC 8331 §4: *"The type name ("video") goes in SDP "m=" as
    the media name."* The new grammar tier enforces this via
    `st2110-40.a.rtpmap.smpte291-media-type` (and the 1.0
    parser rejects the same construction at
    `parse_sdp.lua:1617-1624`). Fixed
    `examples/st2110/valid/05_typical_multistream.sdp` (1 block),
    `examples/st2110/valid/06_pathological.sdp` (2 blocks), and
    `examples/ipmx/valid/03_pathological.sdp` (1 block) to use
    `m=video` per the IANA registration; the test ANC port and
    rtpmap PT are unchanged. No fixture renaming.

Producer-side contract (8.D / 8.E renderer rules):

- **Required field absent → `nil, err`.** Per-attribute "required"
  means what the RFC's ABNF marks as mandatory (e.g. `rtpmap`'s
  `payload_type` + `encoding` + `clock_rate` are required;
  `channels` is optional). Error message names the exact field
  and field_path so the developer knows what to populate.
- **Optional field absent → omit from the rendered output.**
- **Present field of wrong type/value → stringified and emitted.**
  The result may not re-parse; that's the developer's signal.
  `validate()` would have caught the value-form issue.
- **No fallback to legacy `{name, value=string}` shape for known
  attribute names.** Renderer reads from decomposed fields only.
  Generic / unknown attributes keep the `{name, value}` shape
  as the forward-compat carrier.

The 1.0 `s.timing` fallback at parse_sdp.lua:457-464 (single t=
block via `s.timing.start/stop`) is dropped in the new
serializer. The grammar tier never produces that shape; `sdp.new`
consumers must use `time_descriptions[]`. Migration cutover is a
Phase 10 concern.

**Phase 9 — Pre-cutover refactor + public-API surface.**

Four sub-slices, ordered so each one lands on a green tree.

- **9.A (complete)** — DRY sweep across the grammar tier and spec
  helpers. Four refactors landed:
  - `parse_sdp/grammar/ipmx.lua` `check_usb_block` now calls
    `base.params_get(privacy.params, "protocol")` instead of an inline
    linear scan (missed reuse of an existing primitive).
  - `parse_sdp/grammar/st2110.lua` `media_block_has_attr` +
    `session_has_attr` collapsed into one `has_attr(attrs, name)` taking
    the attrs list directly (both callers were one-liners differing only
    in the parent table they indexed).
  - `parse_sdp/grammar/st2110.lua` introduces a small
    `make_param_check(predicate, error_id)` factory. The four cross-param
    check pairs that share a predicate but carry distinct -20 / -22 error
    IDs (`check_(jxsv_)?bt2100_range`,
    `check_(jxsv_)?segmented_requires_interlace`) collapse to two named
    predicates plus four factory invocations. Spec authorship stays
    explicit via the registered error IDs.
  - New `spec/support.lua` carries the three shared spec-helper bits:
    `finding_for(ctx, id)` (was duplicated in `grammar_base_spec.lua`,
    `grammar_st2110_spec.lua`, `grammar_ipmx_spec.lua`),
    `TIMING_TS_REFCLK`, `TIMING_MEDIACLK` (duplicated in the latter two).
    Each consumer aliases the support exports at the top of the file.

  **Intentionally skipped** — call out, per CLAUDE.md "Don't add
  abstractions beyond what the task requires":
  - Unifying `check_raw_video_fmtp` + `check_jxsv_fmtp` into one driver.
    The 4-pass loop bodies are structurally parallel, but the per-tier
    keys / values / validators differ enough (RFC 9134 enum corrections,
    -20 vs -22 spec authorship in error IDs) that consolidation would
    obscure spec authorship and the grep-ability of per-essence checks.
  - Extracting a shared `dispatch_fmtp_checks` loop helper between
    `st2110.fmtp_dispatch` and `ipmx.ipmx_fmtp_dispatch`. The inner loops
    are 2-line bodies; the meaningful difference is the outer
    "which list when" control flow (st2110 has one list; ipmx has
    universal + per-encoding). Net savings ~1 line for added indirection.
  - Serializer `ts-refclk` / `mediaclk` dispatch consolidation. The
    existing `BUILDERS[key] or build_ext` idiom is already tight; further
    abstraction would obscure the per-branch builders, which are the
    load-bearing parts.
  - `errors.lua` registry-row consolidation. Already as DRY as Lua's
    syntax permits given each row's unique strings (`id`,
    `message_template`, `spec_ref`).

  Suite unchanged at 1852 green. Net delta: -31 lines across the
  grammar modules and three spec files; +32 lines for the new
  `spec/support.lua` module.

- **9.B (complete)** — comment-tightening sweep across the new
  grammar tier, serializer, and errors module. Convention applied:
  each comment briefly says (a) what it is, (b) what problem it
  solves, (c) very briefly how. Removed: paragraphs paraphrasing
  what the code says; "Phase N: did X" inline annotations that lost
  value once the phase shipped; section banners that repeated their
  own next-line description; module-header Phase X.Y enumerated
  histories (now in REFACTOR-PLAN). Preserved verbatim per the
  named load-bearing-context list: the fmtp accumulator dissolution
  from 6.C.A (base.lua `fmtp_params_branch` and `fmtp_trailing_sep_record`),
  the LPeg V-rule sharing pitfall in `base.extend` (base.lua
  `make_document_body`), and the rtpmap-before-fmtp ordering caveat
  in 6.C.B (st2110.lua a_fmtp dispatch). Every per-spec citation
  (SHALL/MUST quote, `spec_ref` text, RFC/ST/TR section numbers)
  stays. Suite unchanged at 1852 green. Net delta: -188 lines across
  base.lua, st2110.lua, ipmx.lua, serialize.lua, errors.lua.

- **9.C — Policy + findings feature go live.** The infrastructure
  is already in place from Phase 0:
  [errors.record](parse_sdp/errors.lua#L179-L203) consults
  `ctx.policy[id]`, every check has a registered `default_severity`,
  and `sdp.checks()` / `sdp.default_policy()` already expose the
  toggleable IDs. 9.C flips the switch:

  - On `sdp.parse(text, tier, opts)` entry, validate every key in
    `opts.policy` against the registry; an unknown ID is a caller
    bug (typo / stale config) and returns `nil, err` pointing at
    the offending key.
  - Apply the override: `policy[id]` (when set) wins over
    `default_severity`. `"off"` short-circuits the `record()` call.
    `"warn"` records the finding and returns success.
  - Default `fail_on_first` flips to `false` for the public-API
    path. Error-severity findings still surface as a parse failure
    (`sdp.parse` returns `nil, err`), but the doc carries every
    finding the grammar saw via `ctx.findings`. The internal
    `tier.match(text, { fail_on_first = true })` 1.0-compatible
    semantics stay for spec helpers.
  - The doc surfaces findings via `doc:findings()` (all),
    `doc:warnings()` (severity = `"warn"`), and `doc:errors()`
    (severity = `"error"`). Each finding is the registry shape
    plus a `field_path` / `line` / `col`.

  The user-facing usage pattern is: grep `sdp.checks()` for the
  offending ID, drop `{ ["<id>"] = "warn" }` (or `"off"`) into
  `opts.policy`, re-parse. No reach-into-internals.

- **9.D — Cutover wiring.** Flip `mt:to_sdp()` from the 1.0
  serializer to `parse_sdp/serialize.lua`. `sdp.parse(text, tier,
  opts)` lands its final public-API shape (the `opts` argument
  already accepted; 9.D promotes it from undocumented to
  contracted). `doc:warnings()` / `doc:errors()` / `doc:findings()`
  added on the metatable. The 1.0 grammar / validator code in
  `parse_sdp.lua` stays in place but is no longer reachable from
  the public API.

**Phase 10 — Migration cutover + final audit.**

- **10.A — Delete the 1.0 implementation.** Remove the
  grammar / validator / serializer blocks from `parse_sdp.lua`;
  the file shrinks to errors-shim re-export, public-API surface,
  CLI dispatch. `busted spec/` and `busted spec_conformance/`
  green.

- **10.B — Coverage + size comparison.** Brief audit pass, three
  questions:
  1. **Coverage parity.** Walk `audits/SPEC_INVENTORY.md` +
     `audits/SPEC_COVERAGE.md` against the grammar-tier registry.
     Confirm every grounded check is enforced by the new tier.
     The three 1.0-over-strict items (audio MAXUDP-forbidden on
     AM824, channels-required on L16/L24, packet-payload-fit on
     AM824) stay flagged as intentional drops without primary-
     source SHALL.
  2. **What's new since 1.0.** Enumerate checks added in the
     refactor (e.g. ST 2110-20 §6.2.5 Table 3 4:2:0/depth, §7.6
     TCS/depth=16f coupling, RFC 9134 enum corrections for jxsv,
     RFC 4570 SP-after-`:` strictness from Phase 8.F, TR-10-X
     SHALLs ported during Phase 7).
  3. **Code size delta.** `wc -l` of the new module set vs.
     `parse_sdp.lua` at the 1.0 tag, both raw and stripped of
     comments + blank lines. Report both numbers.

- **10.C — Append findings to CHANGELOG.md.** A brief
  "Comparison with 1.0" section under `[Unreleased]`: one
  paragraph for coverage, one for new checks, one for size delta.
  Tight — the audit memos in `audits/` carry the full detail.
  README.md + GUIDE.md regenerated sections cite the audit for
  users tracking the migration.

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
