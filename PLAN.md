# Plan

## Guiding Principles

- **Test first.** Every feature begins with failing tests.
- **Strict by spec.** Every validation check cites explicit normative spec
  text — a "shall" / "MUST", a "shall not" / "MUST NOT", or a defined value
  form / value set. Spec silence is not a reason to reject.
- **Layered.** Each tier (RFC 8866 → ST 2110 → IPMX) extends the previous;
  it never replaces it. RFC 8866 obsoletes RFC 4566.
- **Tight.** If a file is growing, stop and refactor before continuing.
  Prefer fewer, well-named things.
- **Fail loudly.** Parse failures report exactly where and why.
- **Round-trip.** `doc:to_sdp()` must produce output that re-parses to an
  equivalent table. This is a hard invariant.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.5 |
| Parsing | LPEG |
| JSON | dkjson (pure Lua, LuaRocks) |
| Tests | busted |
| Container | Docker (Lua 5.5 + LuaRocks base image) |

## Test Command

```sh
busted spec/                  # hermetic suite (1192 tests)
busted spec_conformance/      # opt-in pinned AMWA fixtures
```

## Current State

1.2.0 shipped on 2026-05-21. 1192 hermetic tests passing. Every
validation check is grounded in explicit spec text; no opinion-based
checks remain. Public API surface is `parse_sdp/init.lua` (library) +
`bin/parse_sdp` (CLI). Grammar tier under
`parse_sdp/grammar/{base,st2110,ipmx}.lua`; serializer under
`parse_sdp/serialize.lua`; registry under `parse_sdp/errors.lua`.

The 1.2 release added five diagnostic-facing CLI capabilities:
`parse_sdp validate`, `parse_sdp diagnose`, the `--all-findings` flag
on `validate` / `diagnose` / `to_json`, `parse_sdp checks` (registry
dump), plus README "Who is this for?" + error-output stanza.

## Next pass — GUIDE.md Troubleshooting recipes

A field engineer with an unfamiliar `err.id` wants "what does this
usually mean in the wild?" The error message says *what* the validator
found; a troubleshooting note can add *why this usually happens* and
*what to check next*. **Keep this tight** — don't invent edge cases.
Use real cases sourced from:

- The [SDPoker repository](https://github.com/AMWA-TV/sdpoker) — its
  test fixtures + issues + PRs are the canonical "things real senders
  get wrong" corpus.
- The [AMWA nmos-testing repo](https://github.com/AMWA-TV/nmos-testing) —
  similar corpus from JT-NM Tested.
- The 1.1.1 incident: 5-octet PTP GMID (citable `err.id`).

**What changes.** New GUIDE.md section "Troubleshooting" near the end
(after Serialization, before Test Suite Organization). Small table of
*the most commonly seen errors in real-world senders*, keyed by
`err.id`, with columns for "common cause" and "what to check on the
device side." Cap at 6–8 entries — better tight and useful than
exhaustive. Cross-link to `parse_sdp checks` and `sdp.checks()`.

**Tests.** N/A (doc-only). But every cited `err.id` should exist in
the registry — add a `spec/library_spec.lua` test asserting that every
cited `err.id` is in `sdp.checks()` so the documentation can't go
stale silently.

### Future (lower priority — track here, don't schedule yet)

- **Audit-trail export.** A compliance-tester workflow: run validation
  against a corpus of vendor SDPs and emit CSV / JSON of `(file, tier,
  pass/fail, err.id, err.spec_ref)`. The 1.2 CLI primitives are enough
  to build this externally with shell + jq; an integrated
  `parse_sdp audit <directory>` subcommand would package it. Defer
  until the 1.2 CLI work is in users' hands and the actual ergonomics
  ask is clearer.

## Next phase: per-test citation labels in `it` names

(Pre-existing item — orthogonal to the diagnostic-CLI work above.
Mechanical pass over the three standards-tied spec files.)

Every `it` block in `spec/grammar_base_spec.lua`,
`spec/grammar_st2110_spec.lua`, and `spec/grammar_ipmx_spec.lua`
currently ties to a published clause, but the citation lives in the
describe name or in the parser-side `spec_ref` — not on the test name
itself. The next phase puts it on the test name so:

1. Citations show up in busted output — when a test fails the spec
   clause it was enforcing is on the same line.
2. The cite is grep-able from the command line — a single regex
   extracts `(file, line, doc, section)` tuples across the suite.
3. Every cite is re-verified against primary spec text before landing
   (Spec Verification Protocol from CLAUDE.md applies).

### Pattern

Suffix bracket at the end of the test name:

```lua
it("<description> [<doc> §<section>]", function()
```

- Document token: `RFC NNNN`, `ST 2110-NN`, `ST 2110-NN:YYYY`
  (year-pinned when the section number depends on the revision),
  `TR-10-NN`, `TR-10-NN-PartN`.
- Section token: `§N`, `§N.M`, `§N.M.L`.
- Multiple cites comma-separated, no "and":
  `[RFC 8866 §5.7, ST 2110-10 §6.5]`.
- No URLs — document IDs are the bibliographic anchor.

### Workflow (per file, one commit per file)

1. Walk every describe top to bottom.
2. For each `it`, locate the parser-side check it exercises and read
   the `spec_ref` value the validator emits — that is the authoritative
   citation.
3. Re-read the cited clause in the on-disk spec. If the wording does
   not unambiguously support the test, **stop and flag for discussion**
   before modifying.
4. Append the bracketed citation to the `it` name.
5. Confirm `busted spec/` still passes. Test count must not change.
6. Commit.

Coverage target: 100% of `it` blocks in the three standards-tied files.

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in
routine development unless new spec evidence emerges.

- **ST 2110-20:2022 §7.2 "default to SSN=:2017 unless :2022-only values
  are used"** — the §7.2 SSN clause has a reverse direction ("Senders
  implementing this standard shall signal the value ST2110-20:2017 unless
  [exception]") that, strictly enforced, would invalidate
  `SSN=ST2110-20:2022` whenever neither `TCS=ST2115LOGS3` nor
  `colorimetry=ALPHA` is present. ~115 existing test fixtures and most
  real-world :2022-implementing senders signal :2022 unconditionally. The
  forward direction (the JT-NM Tested ask) is enforced; the reverse is
  left to a future audit if SMPTE or AMWA clarifies intent.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists
  value sets independently and contains no explicit "shall not" for any
  combination of valid individual values.
- **ST 2110-31 AES3 fmtp** — AM824 audio currently uses the ST 2110-30
  path (encoding name, channel-order, packet-fit checks). Revisit if new
  AES3-specific normative text emerges.
- **ST 2110-21 §7.1 CMAX upper bound** — the type-specific formula
  `MAX(4, INT(NPACKETS/(43200 × R_ACTIVE × T_FRAME)))` (and the Type W
  variant with `16` and `21600`) is an upper bound on `CINST` per the
  Network Compatibility Model in §6.6.1, not a lower bound on the SDP
  `CMAX` value. Enforcing the upper bound requires NPACKETS / MAXUDP /
  width × height × depth × sampling × frame-rate context; not added.
- **ST 2110-21 §6.2 vs §8.2 TROFF zero handling** — §6.2 explicitly
  permits TROFFSET to be zero (and requires it be signaled when it
  differs from TRODEFAULT); §8.2 says the SDP value is "expressed as a
  positive integer." The parser follows the §8.2 value-form SHALL and
  rejects `TROFF=0`. Revisit only if SMPTE issues an erratum.
- **ST 2110-10:2022 §8.7 vs Annex B TSDELAY zero** — §8.7 says "decimal
  positive integer"; Annex B (Informative) example shows `TSDELAY=0`. The
  §8.7 SHALL governs; parser rejects `TSDELAY=0`.
- **m= media type registry strictness (RFC 8866 §5.14 / §8.2.2)** — §5.14
  defines the five values (`audio`, `video`, `text`, `application`,
  `message`); §8.2.2 says `control` and `data` are SHOULD NOT, not MUST
  NOT, grounded in RFC 3840 SIP backward-compat. Not enforced per the
  strictness principle. Future-warning candidate.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF
  allows FQDNs in the origin address; no ST 2110 clause explicitly forbids
  them there.
