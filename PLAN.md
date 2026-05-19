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
busted spec/                  # hermetic suite (~850 tests)
busted spec_conformance/      # opt-in upstream-fixture suite
docker compose run test       # Docker (hermetic)
```

The opt-in `spec_conformance/` suite downloads pinned SDP fixtures from
`AMWA-TV/nmos-testing` and `AMWA-TV/bcp-006-01` into a gitignored cache
and runs them through the parser. See
[spec_conformance/README.md](spec_conformance/README.md).

## Current State

1569 hermetic tests passing. Every validation check is grounded in explicit
spec text; no opinion-based checks remain.

The grammar-first refactor on branch `refactor/grammar-first` is **in
progress**. Phases 4 + 5 complete; **Phase 6 (all of 6.A–6.L except
the deferred 6.I) is now closed.** The grammar tier matches or
exceeds the 1.0 parser on every check grounded in primary spec text.
Three 1.0-over-strict flags from 6.D (audio MAXUDP-forbidden on
AM824, channels-required on L16/L24, packet-payload-fit on AM824)
are intentionally not ported and remain flagged in `audits/` for
separate follow-up. Phase 6.F refactored 11 per-line ST 2110 checks
out of `semantic_checks` into in-grammar Cmt callbacks. 6.G wired
byte-position diagnostics through every in-grammar Cmt. 6.H applied
the in-grammar treatment to base SDP's `check_connection_addresses`.
6.J hoisted shared numeric-value-form LPeg patterns into a new
`parse_sdp.grammar.patterns` module that base and st2110 both draw
from. 6.K added a `media_section_checks` slot parallel to
`semantic_checks`, migrated 5 per-block checks into it, and
recovered the `media[N]` field_path prefix on every in-grammar
finding via the new `ctx.media_index` plumbing. 6.L finished the
LPeg sweep by rewriting `validate_channel_order` (the last inline-
regex validator) as a small LPeg grammar.

Phases 7–10 remain (IPMX tier via `extend(st2110_rules, ...)`,
serializer rewrite, public API stabilization, migration cutover).
The grammar tier covers:

- ST 2110-20 raw video: §7.1 no-whitespace-around-=, §7.2/§7.4.2
  required-param presence + -21 §8.1 TP, 7 enum value-sets, 6
  non-enum value forms, 2 flag-only, 7 cross-parameter SHALLs +
  5 1.0-gap-close SHALLs from §6.2.5 Table 3 + §7.6.
- ST 2110-22 jxsv: 4 required-param presence, 16 value-form /
  flag-only narrowings (RFC 9134-aligned enums for colorimetry /
  TCS / sampling, correcting 1.0 mismatches), 2 cross-param SHALLs.
- ST 2110-30 / -31 audio: channel-order RFC 3190 syntax + SMPTE2110
  group set + AES3-requires-AM824.
- ST 2110-31 AM824: rtpmap channel parity (§6.1).
- ST 2110-41 Fast Metadata: required SSN with value form, optional
  DIT with hex-token value form, MAXUDP forbidden.
- ST 2110-10 §8.2 + §8.3: per-media-block `a=ts-refclk` and
  media-level `a=mediaclk` presence (Phase 6.D.A; 1.0 cited the
  wrong sections, grammar tier corrects to §8.2 / §8.3).

Phases 6.D.B+ and 6.E–10 remain (audio MAXUDP-forbidden, audio rtpmap
channels-presence, packet-payload-fit; cross-stream invariants like
group:DUP; serializer rewrite; public API stabilization; migration
cutover). Tracking and design live in [REFACTOR-PLAN.md](REFACTOR-PLAN.md).
The 1.0 parser at `parse_sdp.lua` remains the shipping artifact on
`main`; the new grammar under `parse_sdp/grammar/` is internal-only
until Phase 9 cutover.

**Former flake (resolved in 6.C.A):** the `sdp.a.fmtp.trailing-semicolon`
tests in `spec/grammar_base_spec.lua` previously flaked at ~45% with
*"no previous value for accumulator capture"*. The 6.C.A rewrite
replaced `fmtp_params_branch`'s `Ct(P("")) * (entry % set_pair) * …`
chain with `Ct(entry * (sep * entry)^0) / fmtp_entries_to_params`,
sidestepping LPeg's accumulator-capture runtime path. 30 fresh full-suite
runs and 30 fresh `--filter "trailing semicolon"` runs went 30/30 green
afterward. The root cause was not definitively isolated; see
[audits/FMTP_ACCUMULATOR_FLAKE.md](audits/FMTP_ACCUMULATOR_FLAKE.md) for
the investigation record.

The test suite is split along a single axis — *what kind of code each
test exercises*. Refactor-era files (`grammar_base_spec`,
`grammar_addresses_spec`, `error_registry_spec`) are not yet enumerated
in the table below.

| File | Tests | What it covers |
| --- | ---: | --- |
| `spec/sdp_spec.lua` | 99 | RFC 4566 / RFC 8866 (base SDP) — 100% standards-tied |
| `spec/st2110_spec.lua` | 405 | SMPTE ST 2110 — 100% standards-tied |
| `spec/ipmx_spec.lua` | 190 | VSF TR-10 / IPMX — 100% standards-tied |
| `spec/library_spec.lua` | 42 | Public API (parse / validate / doc methods / to_json) |
| `spec/cli_spec.lua` | 15 | CLI subcommands |
| `spec/grammar_spec.lua` | 35 | LPEG primitive parsers (internal, white-box) |
| `spec/errors_spec.lua` | 16 | Error formatter (internal, white-box) |

Non-standards `it` blocks carry an inline `-- NOT-SPEC: library` or
`-- NOT-SPEC: implementation` marker.

## Next phase: per-test citation labels in `it` names

Every `it` block in the three standards-tied files (`sdp_spec`,
`st2110_spec`, `ipmx_spec`) currently ties to a published clause, but the
citation lives in the describe name or in the parser-side `spec_ref` — not
on the test name itself. The next phase puts it on the test name so:

1. **Citations show up in busted output.** When a test fails, the spec
   clause it was enforcing is on the same line as the test name. No need
   to grep back into the surrounding describe.
2. **The cite is grep-able from the command line.** A single regex
   extracts `(file, line, doc, section)` tuples across the suite — useful
   for auditing, for cross-referencing against fixture sets, and for
   downstream tooling that wants to know which clauses a passing build
   actually exercised.
3. **Every cite is re-verified against primary spec text** before
   landing — the Spec Verification Protocol from CLAUDE.md applies.

### Pattern

Suffix bracket at the end of the test name:

```lua
it("<description> [<doc> §<section>]", function()
```

- **Document token:** `RFC NNNN`, `ST 2110-NN`, `ST 2110-NN:YYYY`
  (year-pinned when the section number depends on the revision),
  `TR-10-NN`, `TR-10-NN-PartN`.
- **Section token:** `§N`, `§N.M`, `§N.M.L`. No other punctuation;
  uses the same separator the spec uses internally.
- **Multiple cites:** comma-separated, no "and":
  `[RFC 8866 §5.7, ST 2110-10 §6.5]`.
- **No URLs.** Document IDs are the bibliographic anchor; readers look
  the document up themselves.

Examples:

```lua
it("rejects b=AS:0 (must be positive) [TR-10-7 §11]", function()
it("rejects IPv6 unicast with /suffix [RFC 8866 §5.7]", function()
it("accepts width=32767 (boundary) [ST 2110-22:2022 §7.2]", function()
```

Grep:

```sh
grep -nE '\[(RFC |ST 2110-|TR-10-)[^]]+\]' spec/sdp_spec.lua spec/st2110_spec.lua spec/ipmx_spec.lua
```

### Workflow (per file, one commit per file)

1. Walk every describe top to bottom.
2. For each `it`, locate the parser-side check it exercises and read the
   `spec_ref` value the validator emits — that is the authoritative
   citation.
3. Re-read the cited clause in the on-disk spec. If the wording does not
   unambiguously support the test, **stop and flag for discussion**
   before modifying. (Same protocol as audit pass #31.)
4. Append the bracketed citation to the `it` name.
5. Confirm `busted spec/` still passes. Test count must not change.
6. Commit.

Coverage target: 100% of `it` blocks in `sdp_spec.lua` / `st2110_spec.lua`
/ `ipmx_spec.lua` carry an inline citation.

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
