# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Documentation

- **GUIDE.md gains a "Producer Workflow" section** covering the
  build-then-validate loop for device manufacturers and SDK developers
  emitting SDP — empty table → `to_sdp()` for structural gaps →
  `doc:validate(tier)` for spec gaps, iterating until `is_<tier>()`
  returns `true`. Walks an ST 2110-20 1080p25 sender end-to-end with
  the real error message produced at each step; notes the IPMX delta;
  documents the policy-demotion pattern for prototyping against
  not-yet-provisioned values. Cross-references the per-tier reference
  tables already in the guide rather than duplicating them.
- `examples/producer_walkthrough.lua` — runnable companion that mirrors
  the GUIDE section step for step and prints the emitted SDP.
- **Four kitchen-sink reference examples** for producers who need to
  see every field/attribute shape the library knows about:
  - [`examples/kitchen_sink.lua`](examples/kitchen_sink.lua) — every
    RFC 8866 line type + every base-tier decomposed attribute (rtpmap,
    fmtp, ssrc, ssrc-group, msid, extmap, rtcp, rtcp-fb, rtcp-mux,
    source-filter, mid, group, ts-refclk, mediaclk) + a forward-compat
    `x-vendor-*` attribute. Self-validating: `parse → serialize →
    re-parse → deep-equal`.
  - [`examples/kitchen_sink_st2110.lua`](examples/kitchen_sink_st2110.lua)
    — every ST 2110 attribute and parameter on one doc with six media
    blocks (raw video DUP pair, JPEG-XS, L24 audio, smpte291 ANC, ST
    2110-41 fast metadata). Asserts `is_st2110()` and round-trip.
  - [`examples/kitchen_sink_ipmx.lua`](examples/kitchen_sink_ipmx.lua)
    — IPMX deltas on top of ST 2110: TR-10-1 IPMX flag + measurement
    params, TR-10-TP-1 per-block a=source-filter, TR-10-10 a=infoframe,
    TR-10-5 a=hkep, TR-10-13 a=privacy, TR-10-6 FECPROFILE. Asserts
    `is_ipmx()` and round-trip.
  - [`examples/kitchen_sink_conflicts.lua`](examples/kitchen_sink_conflicts.lua)
    — eight tiny per-conflict SDP fixtures for combinations the valid
    sinks above can't show together (RFC 7273 traceable / non-traceable
    mix, ST 2110-10 §8.3 session-level mediaclk, ST 2110-20 §7 BPM+MAXUDP,
    TR-10-1 §10.1 missing IPMX flag, TR-10-2 §7 odd UDP port,
    RFC 8866 §5.7 IPv4 multicast without TTL, RFC 8866 §9 malformed
    IPv4, RFC 7273 §4.8 5-octet PTP GMID — the conflict the 1.1.1
    fix restored). Each fixture asserts a structured rejection with
    the expected `err.id` and `err.spec_ref`.
- **GUIDE.md "Kitchen-sink references"** subsection under Producer
  Workflow pointing at all four files, including a table of the four
  hex-formatting conventions SDP uses across them (dash-separated
  octets, UUID-dashed, bare fixed-length, `0x`-prefixed RFC 8331
  octet pairs).
- **README first-impression polish.** New "Who is this for?" stanza
  (field troubleshooting / compliance verification / SDK integration),
  plus a realistic-error block showing the CLI's carrot-highlight
  output with `id` / `spec_ref` so a reader sees the diagnostic story
  before the install instructions. Feature list reordered so
  spec-citation + structured-error points come first.

### Repository reorg

- `REFACTOR-PLAN.md` (1500-line historical planning artifact that
  drove the 1.1.0 refactor) moved to `audits/REFACTOR-PLAN.md`
  alongside the other refactor-era audit memos. 50+ CHANGELOG
  audit-trail references updated to the new path.
- `SDPOKER_BACKLOG.md` moved to `spec_conformance/SDPOKER_BACKLOG.md`
  — it's conceptually a companion to the conformance suite, not a
  top-level project doc. Internal links updated to relative.
- Check-taxonomy table (hard-syntactic / soft-syntactic / semantic +
  where each lives in the grammar) preserved from REFACTOR-PLAN §3.3
  into CLAUDE.md, which is now the agent-facing reference for kind
  discipline.

### Plan

`PLAN.md` rewritten. Removed the stale "Current State" block from
before 1.1.0 shipped (talked about phases that are all closed and
the 1.0 parser that's been deleted). Replaced with a concise
current-state summary + a verbose "Next pass" section detailing
seven diagnostic-CLI / docs items: `parse_sdp validate`,
`parse_sdp diagnose`, `--all-findings` flag, `parse_sdp checks`,
`parse_sdp conformance`, README polish, GUIDE.md troubleshooting
recipes. Each item carries enough per-item context (why, what it
does, where it lives, tests, doc placement) for a fresh-thread Claude
to execute. Known Deferred Items section preserved.

## [1.1.1] — 2026-05-21

Patch release. Restores a strict-validation guarantee that regressed in
1.1.0 and brings the runnable example walkthrough into alignment with the
1.1 decomposed doc shape.

### Fixed

- **`a=ts-refclk:ptp=` now rejects malformed bodies (RFC 7273 §4.8
  regression introduced in 1.1.0 Phase 4.C).** When `ts-refclk` was
  decomposed into typed fields during the grammar-first refactor, the
  alternation in `a_ts_refclk` ended with a permissive `clksrc-ext`
  fallback (`tsr_ext`) that silently swallowed any reserved-literal
  prefix whose body failed the strict form — e.g.
  `ts-refclk:ptp=IEEE1588-2008:AA-BB-CC-DD-EE:0` (5-octet GMID, not the
  RFC 7273 EUI-64 `7(2HEXDIG "-") 2HEXDIG` form) was accepted as an
  opaque `source="ptp", value="…"` extension instead of being rejected.
  1.0 caught the same case via a hand-rolled octet-count walk.

  Restored two ways:

  - `tsr_ptp` is now `strict-body / malformed-body`. The malformed branch
    captures the raw remainder as `.value` and records a new
    `sdp.a.ts-refclk.ptp-malformed` finding (severity `error`,
    `spec_ref = "RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF)"`,
    pos-anchored to the start of the bad body). The structured finding
    surfaces through the normal public-API `nil, err` contract, and
    policy can demote it to `"warn"` to inspect the captured body via
    `doc:findings()`.
  - `tsr_ext` now starts with a negative-lookahead guard
    (`-tsr_reserved`) that refuses the RFC 7273 Figure 1 reserved
    literals (`ntp=`, `ptp=`, `private`, `gps`, `gal`, `glonass`,
    `local`) — the same `known_attr_lookahead` discipline already used
    at the `a=` level for malformed-known-attribute rejection. Effect:
    `gps=foo`, `private:bogus`, `ntp=`, etc. now fail the grammar
    instead of being captured as opaque extension tokens. Tokens that
    merely share a prefix with a reserved literal (`localmac=…`,
    `gpsfoo=bar`) are still accepted, since they are legitimate
    `clksrc-ext` tokens.

  10 new tests under `spec/grammar_base_spec.lua` cover both behaviors:
  the malformed-ptp recovery path under `fail_on_first=false`, finding
  shape, all four reserved-prefix guard paths, and continued acceptance
  of the strict forms and prefix-overlapping ext tokens.

### Changed

- **`examples/examples.lua` rewritten to match the 1.1 doc shape.**
  The walkthrough was still printing 1.0-style attribute values
  (`a.value` on `rtpmap` / `fmtp`, which are decomposed in 1.1) and
  building a hand-built doc with `session.timing` instead of
  `session.time_descriptions`. Specifically:

  - Section 1 now formats each known attribute from its decomposed
    fields (`rtpmap` → `pt=N enc/rate[/channels]`, `fmtp` → `pt=N
    k=v; k=v…`), falling back to `.value` only for opaque attributes
    and to empty string for flag attributes (`recvonly` etc.).
  - Section 4's `sdp.new(raw)` example uses the documented
    decomposed shape — `session.time_descriptions = {{ start, stop }}`
    — so `is_sdp()` returns `true` and `to_sdp()` succeeds.
  - Section 5 picks invalid files that actually produce structured
    errors (`05_multiple_errors.sdp`, `03_missing_fmtp.sdp`,
    `01_missing_ipmx_marker.sdp`) so the printed `err.id` / `err.line`
    / `err.col` / `err.spec_ref` / `err.field_path` fields are real,
    not blank fallbacks.
  - Section 5.5's "Multiple errors with `fail_on_first=false`"
    subsection was rewritten. The previous version claimed
    `fail_on_first=false` returns a `doc` with collected errors
    accessible via `doc:errors()`, but `parse_sdp/init.lua` always
    surfaces errors via `nil, err` regardless of `fail_on_first`,
    so the demonstrated behavior never happened. The new section
    shows the actual collection pattern — demote known errors to
    `"warn"` via the policy table to keep them on the returned doc's
    `doc:findings()` / `doc:warnings()` — and follows with a short
    honest comparison of `fail_on_first=true` vs the default
    (both still return `nil, err`; the difference is which error
    surfaces).

## [1.1.0] — 2026-05-20

Ground-up rewrite of the parser per [audits/REFACTOR-PLAN.md](audits/REFACTOR-PLAN.md).
Phase 9.D cut sdp.parse / mt:to_sdp over to the grammar tier; Phase
10.A.0 ported the six grounded SHALLs the 10.B audit surfaced as
silently-dropped during the refactor; Phase 10.A deleted the 1.0
implementation. The on-disk artifact is no longer the 1.0 monolith
on `main`.

Post-Phase 10 follow-ups in this release: 1.0-style carrot highlight
restored in error output; the CLI was split out of the library
(library is now `parse_sdp/init.lua`, CLI lives at `bin/parse_sdp`,
rockspec finally lists every submodule); Lua dependency relaxed to
`>= 5.3, < 5.6` (verified against 5.3); GUIDE.md clarified that
optional array session fields accept nil and `{}` interchangeably.

### Changed (post-Phase 10)

- **CLI split into a dedicated shell script.** The dual-purpose top-level
  `parse_sdp.lua` (library + detect-if-main CLI) is gone. Library code
  moved to `parse_sdp/init.lua` so `require("parse_sdp")` resolves to it
  naturally — no `?.lua`-shadows-`?/init.lua` ambiguity, and library
  consumers no longer drag `argparse` into their runtime. The CLI lives
  as `bin/parse_sdp` (a small shim that `require`s the library and
  dispatches `to_json` / `to_sdp` subcommands). Local invocation is
  `lua bin/parse_sdp ...`; after `luarocks install` it's just
  `parse_sdp ...` per the rockspec's `install.bin` mapping.
  
  Rockspec updates:
  
  - `build.modules` now lists every submodule (`parse_sdp` →
    `parse_sdp/init.lua`, plus `parse_sdp.errors`,
    `parse_sdp.serialize`, `parse_sdp.grammar.{patterns,addresses,base,
    st2110,ipmx}`). Earlier the rockspec only registered the top-level
    file — a pre-existing bug that would have left submodules
    uninstalled under LuaRocks.
  - `install.bin.parse_sdp` now points at `bin/parse_sdp`.
  - Lua dependency relaxed from `>= 5.5` to `>= 5.3, < 5.6` (verified
    against 5.3).
  
  `spec/cli_spec.lua` updated to invoke `lua bin/parse_sdp`; CLAUDE.md +
  README.md Repository Layout regenerated for the new tree.

### Added (post-Phase 10)

- **Carrot highlight in error format.** Restored the 1.0-style
  source-line + caret block under errors emitted from in-grammar Cmts.
  Earlier the highlight only rendered when callers stashed the source
  line in `err.context` (a string) — the grammar tier overloaded
  `context` for metadata tables, so the block never lit up. New
  `errors.pos_to_line_text(text, pos)` extracts the source line;
  `errors.record()` populates a dedicated `line_text` field on every
  finding with a `pos` + `ctx.text`; `errors.format()` prefers
  `line_text` for the highlight block and falls back to a string
  `context` for legacy callers. Doc-level semantic checks (which have
  no byte position) still render just the field-path. 5 new tests
  in `spec/errors_spec.lua`.

  Example after restoration:

  ```text
  error: [INVALID_VALUE] IPv4 multicast c= address requires a '/<ttl>' suffix
   --> line 6, col 19
    |
   6 | c=IN IP4 239.0.0.1
     |                   ^
    = note: required by RFC 8866 §9 (IP4-multicast ABNF)
  ```

### Comparison with 1.0

**Coverage.** The grammar tier ships **169 registered checks** versus
roughly 80 inline `errors.new` sites in v1.0.0. Every grounded SHALL
that v1.0.0 enforced is enforced in the grammar tier, after the six
Phase 10.A.0 ports closed the gaps the 10.B parity audit surfaced
(see [audits/PHASE3_FINDINGS.md](audits/PHASE3_FINDINGS.md) and
[audits/SPEC_COVERAGE.md](audits/SPEC_COVERAGE.md)). Five intentional
drops carry over without primary-source SHALLs: ST 2110-31 AM824
MAXUDP-forbidden, ST 2110-30 L16/L24 channels-required, ST 2110-30
AM824 packet-payload-fit limb, ST 2110-10 §7 empty-media-block
rejection at st2110/ipmx tier, and ST 2110-10 §8.7's §7.9-conditional
TSMODE=SAMP→TSDELAY coupling.

**New checks since 1.0.** Roughly 90 IDs in the registry are new
since v1.0.0. The notable groupings: the complete VSF TR-10 series
ported during Phase 7 (~50 IDs across TR-10-1 / -2 / -5 / -6 / -10
/ -13 / -14, including IPMX HKEP / FEC / InfoFrame / PEP / USB);
RFC 9134 §7.1 jxsv per-parameter enums distinct from ST 2110-20's
set (~15 IDs); RFC 8866 base-tier IPv4 / IPv6 multicast ABNF
strictness promoted from the st2110-only check (9 IDs); RFC 5888
group cross-stream invariants + ST 2110-10 §8.5 DUP coherence
(9 IDs); ST 2110-20 §6.2.5 Table 3 + §7.6 cross-parameter SHALLs
(5 IDs); ST 2110-10 §8.7 TSMODE / TSDELAY value forms ported during
Phase 10.A.0.3 (2 IDs); RFC 8331 §4 + ST 2110-40:2023 §7 smpte291
fmtp bundle ported during Phase 10.A.0.4 (9 IDs); RFC 4570 §3.1
source-filter cross-check ported during 10.A.0.5.

**Code size delta.** Comparing v1.0.0's monolithic `parse_sdp.lua`
against the post-10.A module set (`parse_sdp.lua` + `parse_sdp/`):

|                 | Raw lines | Stripped (no comments / blank) |
| --------------- | --------: | -----------------------------: |
| v1.0.0 monolith |      3801 |                           2771 |
| HEAD post-10.A  |      6899 |                           4403 |
| Delta           |      +81% |                           +59% |

The growth is primarily check coverage (169 typed IDs vs. ~80
inline) and the per-attribute renderer + check-registry surfaces
that give every check a stable id, verified spec_ref, and severity
policy.

### Removed

- **Phase 10.A:** deleted the 1.0 implementation from `parse_sdp.lua`.
  After Phase 9.D's cutover the 1.0 grammar / validator / serializer
  blocks were on disk but unreachable from the public API; Phase
  10.A.0's six ports closed the parity gaps; now the file shrinks to
  what the post-cutover plan called for — module requires + the
  public-API surface + the CLI dispatch.

  `parse_sdp.lua` went from 3875 lines (mid-cutover) to **257 lines**
  (-93%). The on-disk tree:

  ```text
  parse_sdp.lua                257  public entry point + CLI
  parse_sdp/errors.lua        1947  registry + policy + tracker
  parse_sdp/serialize.lua      762  doc → SDP rendering
  parse_sdp/grammar/
    patterns.lua                48  shared numeric forms
    addresses.lua              268  IPv4 / IPv6 + expansion + canon
    base.lua                  1310  RFC 8866 grammar + checks
    st2110.lua                1499  ST 2110 overrides
    ipmx.lua                   677  TR-10 / IPMX overrides
                              ----
                              6768  total
  ```

  Also deleted: `spec_legacy_1.0/` (the four 1.0-tied spec files
  moved out of `spec/` during Phase 9.D — their replacements
  `spec/grammar_{base,st2110,ipmx}_spec.lua` carry the going-forward
  per-tier coverage). `M._grammar` removed (grammar internals now
  reach the spec via direct `require("parse_sdp.grammar.base"|...)`
  rather than the legacy module-level breadcrumb).

  CLAUDE.md Repository Layout section regenerated to match the new
  tree; the lpeg-patterns convention re-aimed at the per-tier
  modules; the `spec_ref` ↔ tier-prefix invariant's monolith
  footnote replaced with concrete tier-file guidance.

  Suite 1146 green in `spec/`; conformance 10/10 green.

  Audit ref: audits/REFACTOR-PLAN.md §5 Phase 10.A.

### Added

- **Phase 10.A.0.5:** ported the RFC 4570 §3.1 source-filter
  dest-address cross-check the grammar tier had silently dropped. The
  1.0 parser walked every session- and media-level a=source-filter and
  verified each `<dest-address>` matched some c= `<connection-field>`
  value in the SDP, with RFC 8866 §5.7 multicast expansion
  (`<base>/<ttl>/<numaddr>` → contiguously allocated addresses above
  the base). Grammar tier parsed source-filter syntactically but
  performed no cross-check.

  1 new error id `sdp.a.source-filter.dest-not-in-connections` (RFC
  4570 §3.1, error severity); new base-tier doc semantic check
  `check_source_filter_dests`. Wildcard addr_type `*` exempt per the
  §3.1 carve-out ("source-filter applies to all `<connection-field>`
  values"). New helpers in `parse_sdp/grammar/addresses.lua`:
  `expand_connection` (with RFC 8866 §5.7 multicast expansion for both
  IPv4 `<base>/<ttl>/<numaddr>` and IPv6 `<base>/<numaddr>`) and
  `canonicalize` (case-insensitive IPv6, integer-normalized IPv4)
  for cross-set membership.

  11 new tests in `spec/grammar_base_spec.lua` (session-level match,
  per-media match, `*`-wildcard exempt, IPv4 /numaddr expansion,
  IPv6 match, IPv6 /numaddr expansion, IPv6 case-insensitive match,
  dest-mismatch reject, addr_type-mismatch reject, /numaddr boundary
  reject, policy off). Four pre-existing source-filter round-trip
  tests in `roundtrip_spec` updated to use a c= that matches each
  test's source-filter dest (the original c= was set up before the
  cross-check existed).

  Suite 1146 green (was 1135).

  Audit ref: audits/REFACTOR-PLAN.md §5 Phase 10.A.0.

- **Phase 10.A.0.4:** ported the RFC 8331 §4 + ST 2110-40:2023 §7
  smpte291 fmtp SHALLs the grammar tier had silently dropped. The
  failing `nmos-testing:data.sdp` conformance fixture (no `a=fmtp` on
  its smpte291 block — expected to be rejected per §7) now rejects
  correctly; `busted spec_conformance/` returns to green.
  
  9 new error ids, all under the `st2110-40.a.fmtp.*` composition
  layer:
  
  - `vpid-code-too-many` — RFC 8331 §4: *"If the optional parameter
    VPID_Code is present, it SHALL be present only once."*
  - `vpid-code-invalid-value` — RFC 8331 §4: single non-negative integer.
  - `did-sdid-invalid-value` — RFC 8331 §4 syntax `{0xH[H],0xH[H]}`
    (TwoHex per §4 ABNF). Multiple occurrences permitted.
  - `tm-invalid-value` — ST 2110-40:2023 §7: TM ∈ {LLTM, CTM} (defined
    value set).
  - `ssn-required` / `ssn-invalid-value` — ST 2110-40:2023 §7: SSN
    required; TM-conditional value with the §7 receiver-equivalence
    clause (ST2110-40:2021 accepted as equivalent to :2023 when TM is
    signaled).
  - `exactframerate-required` — ST 2110-40:2023 §7: required.
  - `exactframerate-invalid-value` — value form delegated to ST
    2110-20:2022 §7.2 (positive integer or positive n/d in lowest terms).
  - `troff-invalid-value` — value form delegated to ST 2110-21:2022 §8.2
    (positive integer; TROFF=0 rejected per PLAN.md Known Deferred Items).
  
  New `check_smpte291_fmtp` + `smpte291 =` entries in both
  `FMTP_CHECKS_BY_ENCODING` (per-line dispatch) and
  `FMTP_REQUIRED_BY_ENCODING` (rtpmap-requires-fmtp fallback for the
  no-fmtp case). LPeg-grammared `DID_SDID_PAT` for the TwoHex shape; new
  Lua-helpered `validate_ssn40` / `validate_troff` / `validate_vpid_code`
  matching the surrounding pattern. 30 new tests in
  `spec/grammar_st2110_spec.lua` (required-presence × 4; TM × 3;
  SSN × 7; exactframerate × 3; TROFF × 3; VPID_Code × 4; DID_SDID × 5;
  policy × 1).
  
  Test-fixture updates: four pre-existing tests (smpte291 rtpmap
  narrowings; whitespace-around-= scope; -20 raw-required-params scope;
  -20 sampling-enum scope) carried a no-fmtp or minimal-fmtp smpte291
  block to demonstrate that -20 narrowings don't apply. Each now
  includes the §7 minimum (`SSN=ST2110-40:2018; exactframerate=30000/1001`)
  so the test isolates the absence of the -20 narrowing from the new
  -40 SHALLs. Suite 1135 green (was 1105); `busted spec_conformance/`
  10/10 green (was 9 + 1 error).

  Audit ref: audits/REFACTOR-PLAN.md §5 Phase 10.A.0.

- **Phase 10.A.0.3:** ported the ST 2110-10:2022 §8.7 TSMODE / TSDELAY
  value-form SHALLs the grammar tier had silently dropped. §8.7:
  "Allowed values are: TSMODE=SAMP / TSMODE=NEW / TSMODE=PRES" — a
  defined three-value enum — and TSDELAY "is represented as a decimal
  positive integer number of microseconds." Both apply to every ST 2110
  RTP stream regardless of essence type, so the in-grammar fmtp
  dispatch grew a new `FMTP_COMMON_CHECKS` slot that runs cross-encoding
  before per-encoding dispatch. 2 new error ids
  `st2110-10.a.fmtp.tsmode-invalid-value` /
  `st2110-10.a.fmtp.tsdelay-invalid-value`; 14 new tests in
  `spec/grammar_st2110_spec.lua` (3 enum-accept, 2 enum-reject incl.
  case-sensitivity, 1 absent-OK, 5 TSDELAY accept/reject, 1
  cross-encoding scope, 1 policy off, 1 non-port docs check).

  **Intentional non-port:** the 1.0 parser's unconditional "TSMODE=SAMP
  requires TSDELAY" check does not port — §8.7 restricts that pairing
  to §7.9 time-preserving senders, a sender classification SDP alone
  cannot identify. CLAUDE.md strictness principle disallows the
  unconditional reading. Suite 1105 green (was 1091).

  Audit ref: audits/REFACTOR-PLAN.md §5 Phase 10.A.0.

- **Phase 10.A.0.2:** ported the ST 2110-10:2022 §6.2 RTP-Profile SHALL
  that the grammar tier had silently dropped. The 1.0 parser enforced
  m= proto = "RTP/AVP" at the ST 2110 tier with cite "ST 2110-10:2022
  §8.1" — primary text actually carries the SHALL at §6.2: "All of the
  streams specified in this standard ... shall conform to the RTP
  Profile specified in IETF RFC 3551." RFC 3551 names the profile
  "RTP/AVP" in SDP. Port to the correct cite. New ST 2110-tier
  media_section check `check_rtp_profile` fires on RTP-shaped blocks
  (`is_rtp_block` predicate); rejects every proto other than RTP/AVP
  (so RTP/SAVP, RTP/AVPF, etc. are rejected). Non-RTP transports
  (TR-10-14 USB blocks at `TCP usb`) stay out of scope. 1 new error id
  `st2110-10.m.proto-must-be-rtp-avp` (ST 2110-10:2022 §6.2, error
  severity); 6 new tests in `spec/grammar_st2110_spec.lua`. Suite
  1091 green (was 1085).

  Audit ref: audits/REFACTOR-PLAN.md §5 Phase 10.A.0.

- **Phase 10.A.0.1:** ported the base-tier RFC 8866 §5.7 c=-required SHALL
  that the grammar tier had silently dropped during the refactor (surfaced
  by the Phase 10.B parity audit). New base semantic check
  `check_connection_required` walks the doc once: session-level c= covers
  every media block; otherwise every media block must carry its own c=.
  Zero-media SDP satisfies the SHALL vacuously. 1 new error id
  `sdp.session.connection-required` (RFC 8866 §5.7, error severity);
  6 new tests in `spec/grammar_base_spec.lua` cover session-level
  coverage, per-media coverage, the zero-media vacuous case, both
  failure paths, and policy=`off` bypass. Spec fixtures that build
  media blocks without c= updated: `minimal()` helper auto-inserts a
  session-level c= when `media_blocks` is non-empty; `roundtrip_spec`'s
  hand-built SDPs and `grammar_compose_spec`'s `MINIMAL_WITH_RTPMAP`
  carry an explicit session-level c=. Suite 1085 green (was 1079).

  Audit ref: audits/REFACTOR-PLAN.md §5 Phase 10.A.0.

- `parse_sdp/errors.lua` — new error-handling module: registry of
  checkable spec clauses with stable IDs, severity-policy infrastructure
  (default everything-is-error / fail-on-first; toggle hooks ready for
  later), record() emission helper, deepest-failure tracker for pure-LPeg
  position carry. 1.0 `errors.new` / `errors.format` re-exported with an
  additive `id` field.
- `spec/error_registry_spec.lua` — 31 tests covering registry schema,
  severity resolution, policy validation, record() semantics, the
  deepest-failure tracker, and legacy-compatibility surface.
- `sdp.checks()` and `sdp.default_policy()` on the public module.
  Together they let callers inspect every check the parser may emit and
  dump a starting policy table. Architecture-ready for the deferred
  severity-toggling feature (no toggleable behavior yet). 4 new tests
  in `spec/library_spec.lua`.
- `parse_sdp/grammar/base.lua` — Phase 1 base SDP grammar skeleton.
  Top-down `lpeg.P(rules)` for the RFC 8866 §5 document shape with
  session-section / media-section sub-grammars and per-line wrappers.
  Every leaf is a placeholder (`(1 - line_end)^1`) — value-set tightening
  and rich-doc decomposition land in Phase 2. The exported `rules` table
  is the composition unit Phases 6/7 will extend for st2110 / ipmx.
- `spec/grammar_base_spec.lua` — 20 tests covering structural
  acceptance/rejection: minimal SDP, optional fields, multiple time
  descriptions and r= lines, missing required fields, wrong order,
  bare LF rejection (Phase 5 will soften), empty values rejected.
- **Phase 2.A:** capturing scaffold + version (v) + session-name (s).
  The base grammar's document rule now produces a `Ct` table with
  `doc.version` and `doc.session.name` captured; `v=` is tightened
  from any-text to literal `"0"` per RFC 8866 §5.1. k= continues to
  parse-and-discard per §5.12. Remaining session and media fields
  are still matched-and-discarded placeholders, to be Cg-wrapped in
  2.B–2.E. 7 new tests in `spec/grammar_base_spec.lua`.
- **Phase 2.B:** origin (o) + connection (c) leaves with structured
  captures. `doc.origin` is a six-field table (username, sess_id,
  sess_version, net_type, addr_type, unicast_address); sess_id and
  sess_version stay as strings to preserve NTP-range precision.
  `doc.session.connection` (optional) is a three-field table
  (net_type, addr_type, address); the address string includes any
  `/TTL` or `/<numaddrs>` suffix verbatim (decomposition + value-form
  validation lives in Phase 3 with the findings context). nettype
  tightened to literal "IN", addrtype to "IP4"|"IP6". 12 new tests.
- **Phase 2.C:** text fields (i, u, e, p) + bandwidth (b) leaves.
  `doc.session.info` / `doc.session.uri` are strings (optional).
  `doc.session.emails` / `doc.session.phones` are arrays of strings
  (empty array when absent). `doc.session.bandwidths` is an array
  of `{type, value=number}`. media_section becomes `Ct(...)` and the
  document scaffold now wraps it as `Cg(Ct(media_section^0), "media")`,
  so `doc.media` is always an array (was previously absent). Each
  media block captures `info` / `connection` / `bandwidths` from
  media-level i=, c=, b= lines. m= itself is captured in 2.E.
  16 new tests.
- **Phase 2.D:** timing (t), repeat (r), zone (z) leaves with a typed-time
  sub-grammar. `doc.session.time_descriptions` is now an array of
  `{start=number, stop=number, repeats=[...]}` per RFC 8866 §5.9.
  Each `repeats[i] = {interval, duration, offsets=[...]}` per §5.10,
  with typed-time suffixes (d/h/m/s) preserved verbatim
  (e.g., `"7d"` stays `"7d"`, not normalized to seconds).
  `doc.session.time_zones` (optional) is an array of
  `{adjustment_time, offset}` per §5.11, with signed typed-time
  supported on offsets. 14 new tests. The 1.0 parser's `parse_repeat`
  and `parse_timezone` `gmatch` loops are now obsolete in the new
  grammar path (Phase 8 cutover will retire the 1.0 module).
- **Phase 2.E (Phase 2 close):** media (m) + attributes (a) leaves.
  m= captures land *flat* at each media-block top level —
  `{media, port=number, port_count=number?, proto, fmts=[]}` per
  RFC 8866 §5.14. a= produces `{name, value=string?}` per §5.13
  (flag attributes have no `value` key). The base grammar leaves
  attribute *values* as strings; per-attribute decomposition for
  rtpmap / fmtp / ts-refclk / source-filter / group / mid / ssrc
  / etc. lands in Phase 4. 11 new tests including a full round-trip
  doc-shape integration test against a realistic SDP.

Phase 2 close: the new base grammar produces a fully captured RFC 8866
doc table for every primitive line type. 60 new tests in
`spec/grammar_base_spec.lua`. The grammar still isn't wired into
`sdp.parse()` — that's Phase 9 — so the 1.0 parser remains the
shipping artifact for `require("parse_sdp")` callers.

- **Phase 3.A:** findings-context plumbing. Document rule wrapped in a
  `Cmt(Ct(body) * Carg(1), validate_doc)`; a new `base.match(text, opts)`
  wrapper creates a ctx with `{findings, policy, fail_on_first}` and
  threads it through. The Cmt callback is a no-op scaffold — actual
  cross-section checks land in Phase 3.B and 3.C — but the wiring,
  default-policy honoring, and ctx return semantics are in place. 7
  new tests covering wrapper behavior; the 80 existing capture tests
  now go through `base.match()` instead of `g:match()`.
- **Phase 3.B:** first real semantic check — dynamic RTP PT requires
  matching `a=rtpmap` (RFC 8866 §8.2.3). New registry entry
  `sdp.m.rtpmap-required-for-dynamic-pt` (semantic / error /
  MISSING_FIELD). The check walks `doc.media`, and for every media
  block whose proto contains "RTP", confirms every dynamic-range
  payload type (96–127) in `m.fmts` has a matching `a=rtpmap`
  attribute. The rtpmap-PT extraction uses a small LPeg sub-grammar
  rather than a Lua string match, keeping the discipline. Policy
  overrides (`"off"` / `"warn"`) work. `fail_on_first = false`
  collects every violation. 11 new tests including multi-PT
  collection, policy variants, non-RTP proto skip, and correct
  field_path attribution across media blocks.
- **Phase 3.C (Phase 3 close):** connection-address value-form
  validation per RFC 8866 §5.7 / §9. New module
  [parse_sdp/grammar/addresses.lua](parse_sdp/grammar/addresses.lua)
  with RFC 791 IPv4 and RFC 4291 / RFC 3986 §3.2.2 IPv6 grammars
  (the 38-alternative IPv6 form lifted from the 1.0 parser), plus
  multicast-classification helpers. The base grammar's validate_doc
  now calls check_connection_addresses, which exercises every c= in
  the doc against nine new registry entries:
  `sdp.c.address.invalid-{ipv4,ipv6}`,
  `sdp.c.ipv4-multicast.{ttl-required,ttl-out-of-range,numaddr-invalid}`,
  `sdp.c.ipv4-unicast.suffix-not-allowed`,
  `sdp.c.ipv6-multicast.{suffix-form-invalid,numaddr-invalid}`,
  `sdp.c.ipv6-unicast.suffix-not-allowed`.
  Both session-level and media-level c= lines are validated with
  correct field_path attribution. 29 new tests in
  `spec/grammar_addresses_spec.lua` (address patterns + multicast
  helpers) and 19 in `spec/grammar_base_spec.lua` (semantic checks
  + policy variants).

Phase 3 close: the base SDP grammar enforces every cross-section
invariant the 1.0 parser checked plus connection-address value-form
validation, all through the registry + Carg-threaded findings ctx.
118 new tests across Phase 3. Suite: 1030 green (was 904 at start
of Phase 2; was 964 at start of Phase 3).

- **Phase 4.A:** typed decomposition for the simple-shape compound
  attributes: rtpmap, mid, ptime, maxptime, framerate, quality.
  Each lands as a typed table with named fields instead of the 1.0
  `{name, value=string}` carrier:
  - `a=rtpmap` → `{name, payload_type, encoding, clock_rate, channels?}`
    (RFC 8866 §6.6; PT range 0..127 enforced via Cmt, encoding-name
    against the §9 token char-set, clock-rate / channels against
    `POS-DIGIT *DIGIT`).
  - `a=mid` → `{name, tag}` (RFC 5888 §4 identification-tag = RFC 8866
    §9 token).
  - `a=ptime` / `a=maxptime` / `a=framerate` → `{name, value=number}`
    with the value form constrained to `non-zero-int-or-real` per
    RFC 8866 §6.4 / §6.5 / §6.13. The ABNF's strict
    `*DIGIT POS-DIGIT` tail (rejecting trailing-zero reals like "1.0")
    is enforced via the `(DIGIT * #DIGIT)^0 * POS-DIGIT` LPeg idiom
    — LPeg's `^0` is non-backtracking, so the naive `DIGIT^0 *
    POS-DIGIT` would starve the final digit.
  - `a=quality` → `{name, value=number}` (RFC 8866 §6.14
    `zero-based-integer`; §6.14's suggested 0..10 range is *meaning*,
    not normative, so unenforced).
  Dispatch lives in `a_value` as an ordered-choice over the known-name
  branches, with a generic `{name, value=string?}` fallback for
  unknown attributes (forward-compat). A malformed known attribute
  (e.g. `a=rtpmap:96 H264/bad`) fails the whole grammar match instead
  of degrading to the generic carrier — `a_generic` refuses to start
  on a known-name lookahead.
- New registry entry `sdp.a.mid.duplicate-tag` (RFC 5888 §4
  "identification-tag MUST be unique within an SDP session
  description") wired into `validate_doc` as a doc-level Cmt that
  walks every media block's attributes. The 1.0 parser's
  RFC 5888 §4 uniqueness rule for `a=mid` now lives natively in the
  grammar path.
- The `check_dynamic_pt_rtpmap` semantic check now reads
  `attr.payload_type` directly instead of re-parsing the (now
  decomposed) rtpmap value string.
- 17 new tests in `spec/grammar_base_spec.lua` covering each
  decomposed shape, the strict-ABNF rejections (PT=128, ptime:0,
  mid with space), and the mid-uniqueness Cmt. Suite: 1047 green
  (was 1030 at Phase 3 close).
- **Phase 4.B:** typed decomposition for `a=fmtp` (RFC 8866 §6.15).
  Per the §6.15 ABNF `fmtp-value = fmt SP format-specific-params`
  where `format-specific-params = byte-string`, the inner structure
  is intentionally opaque — codec-specific. The convention is
  `key=value` semicolon-separated, but non-k=v forms (DTMF event
  ranges `0-15,256-511`, red/ulpfec PT lists) are real and
  conformant. Decomposition is therefore **opportunistic**:
  - The kv-list branch commits via `#line_end` and only fires when
    the rest is fully decomposable into k=v / bare-flag tokens
    separated by `;` (with optional surrounding whitespace per the
    base tier; ST 2110-20 §7.1 will narrow this in Phase 6).
  - When it commits: shape is `{name="fmtp", payload_type,
    params={...}}`. params is a hash with string values for k=v
    pairs and `params[name] = true` for bare-flag tokens
    (e.g. ST 2110-20 `interlace`, `segmented`).
  - When it doesn't commit (DTMF, red/ulpfec): shape is
    `{name="fmtp", payload_type, raw="..."}` — the whole
    byte-string preserved opaquely.
  - `params` and `raw` are mutually exclusive; consumers dispatch
    on which field is present.
  Implementation uses the LPeg-1.1 `%` accumulator idiom
  (idioms.md §18) — `Ct(P"") * (pair % set_pair + flag %
  set_flag)^+ * (sep ...)` folds entries into a seed table
  directly inside the grammar. The whole accumulator is wrapped
  in an anonymous `Cg` so intermediate values don't leak into the
  surrounding `a_value` `Ct`. Key/flag character set is tightened
  to identifier-like (`ALPHA / DIGIT / _ / -`) to match the 1.0
  parser's `^[%w_%-]+$` flag form and prevent comma-containing or
  range-shaped opaque values from being mis-decomposed as flags.
- 9 new tests in `spec/grammar_base_spec.lua`: single k=v,
  multiple ;-separated pairs, bare flag tokens, the DTMF raw
  fallback, whitespace tolerance after `;` and around `=`,
  trailing-semicolon tolerance (Phase 5 will record the
  pre-registered `sdp.a.fmtp.trailing-semicolon` finding), and
  rejections (`a=fmtp:` with no PT, `a=fmtp:96` with no params).
  Suite: 1056 green.
- **Phase 4.C:** typed decomposition for `a=ts-refclk` and
  `a=mediaclk` per RFC 7273 §4.8 / §5.4.
  - **ts-refclk variants** all share `{name="ts-refclk", source=...}`:
    `source="ntp"` adds `address` (hostport) OR `traceable=true`
    (for `ntp=/traceable/`); `source="ptp"` adds `version`,
    plus either `grandmaster` (EUI-64) and optional `domain`,
    OR `traceable=true` (for `ptp=<version>:traceable`);
    bare names `gps`/`gal`/`glonass`/`local` use only `source`;
    `private [":traceable"]` adds optional `traceable=true`.
    Anything else falls through to the RFC 7273 §4.8 `clksrc-ext`
    form: `{source="<token>", value="<byte-string>"?}` — which
    is where `localmac=<mac>` lands at the base tier (ST 2110-10
    §8.2 elevates it to a recognized clock source; Phase 6 will
    promote it).
  - **mediaclk variants** all share `{name="mediaclk", mode=...}`:
    `mode="sender"` is parameterless; `mode="direct"` adds
    optional `offset` (number) and optional `rate={num, den}`
    per `direct [ "=" 1*DIGIT ] [SP rate]`; `mode="IEEE1722"`
    adds `stream_id` (EUI-64). The optional `id=<base64tag>`
    prefix (RFC 7273 §5.4 `media-clkid`) is captured as a
    separate `id` field with any `src:` marker preserved inline.
    `mediaclock-ext` falls through as `{mode="<token>",
    value="<byte-string>"?}`.
  - PTP domain accepts both the RFC 7273 ABNF `domain-nmbr=N`
    form **and** the bare-`:N` form ST 2110-10:2017 §8.2 examples
    use (every real-world ST 2110 SDP uses the bare form). Phase 5
    may add a soft-syntactic finding for the non-ABNF form;
    Phase 6 narrows.
  - Each branch ends with a `#line_end` look-ahead so the
    ordered choice only commits on a branch that consumes
    exactly to EOL — preventing e.g. `tsr_bare`'s `P"local"`
    from claiming the `local` prefix of `localmac=...`.
- New leaves added (composable for Phase 6 ST 2110 narrowing):
  `eui64_str` (8 hex octets `-`-separated), `hex_octet`,
  `mediaclk_offset_num`, `rate_pair`.
- 16 new tests in `spec/grammar_base_spec.lua`. RFC 7273 saved
  permanently as markdown per the spec-storage rule. Suite: 1072
  green.
- **Phase 4.D:** typed decomposition for five identity / grouping
  attributes:
  - `a=source-filter` (RFC 4570 §3):
    `{name, filter_mode, net_type, addr_type, dest_address,
       src_addresses=[...]}`. filter_mode ∈ {"incl", "excl"},
    addr_type ∈ {"IP4", "IP6", "*"}; literal-IP form
    validation is **out of scope at the base tier** — that
    narrows in Phase 6 (ST 2110-10 §6.5 / §8.4). At least one
    src address is required (per `1*(src-address SP)` ABNF);
    `a=source-filter:incl IN IP4 239.1.1.1` (no src) is rejected.
  - `a=group` (RFC 5888 §5):
    `{name, semantics, tags=[...]}`. semantics is an RFC 8866 §9
    token (LS / FID / SRF / ANAT / DUP / FEC / BUNDLE / etc.);
    tags is a possibly-empty array of identification-tag tokens
    per the spec's `*(SP identification-tag)`. The Phase 4.A
    mid-uniqueness Cmt and a future group-mid-symmetry Cmt land
    on top of this shape.
  - `a=ssrc` (RFC 5576 §10 Figure 4):
    `{name, ssrc_id, attribute, value?}`. ssrc_id is a 32-bit
    unsigned integer (captured as a Lua number; Lua 5.5's
    integer subtype represents 0..2^32-1 exactly). The inner
    attribute follows SDP §5.13 `name [":" value]` shape — each
    `a=ssrc` line carries exactly one attribute (multiple lines
    for the same SSRC are not merged at this layer).
  - `a=ssrc-group` (RFC 5576 §10 Figure 5):
    `{name, semantics, ssrc_ids=[...]}`. semantics is a token
    (FEC / FID per RFC 5576, with RFC 8866 §9 token extension);
    ssrc_ids is a possibly-empty array of decimal integers per
    the spec's `*(SP ssrc-id)`.
  - `a=msid` (RFC 8830 §2):
    `{name, msid_id, appdata?}`. Both tokens are captured via
    the non-ws-token rule; `appdata` is nil when only the
    msid-id is present.
- New leaves: `non_ws_token` (any non-whitespace run up to
  line_end; reused by source-filter and msid), `ssrc_id_num`
  (32-bit decimal integer → number).
- `known_attr_lookahead` extended with source-filter, group,
  ssrc-group, ssrc, msid; ordered longer-first so `ssrc-group`
  binds before `ssrc`.
- 12 new tests in `spec/grammar_base_spec.lua` covering the
  decomposed shapes and the ABNF-strict rejections (e.g.
  source-filter with no source addresses). Suite: 1084 green.
- **Phase 4.E (Phase 4 close):** typed decomposition for the four
  RTCP-adjacent attributes.
  - `a=extmap` (RFC 8285 §8):
    `{name, id, direction?, uri, attributes?}`. id is the 1*5
    DIGIT local identifier (captured as a number); direction ∈
    {sendonly, recvonly, sendrecv, inactive} when the `/dir`
    suffix is present; attributes is the optional
    extensionattributes byte-string (free-form, opaque at base
    tier — extension-specific narrowing belongs to per-extension
    code if needed).
  - `a=rtcp-fb` (RFC 4585 §4.2):
    `{name, payload_type, feedback_type, parameters?}`.
    payload_type is type-polymorphic — the literal string `"*"`
    for the wildcard form, or a number for numeric fmt
    (consumers dispatch on type). The full ack/nack-specific
    param subgrammar is **not** enforced at base tier; the
    remainder of the line (after the feedback-type token) is
    captured verbatim as `parameters` for downstream
    interpretation.
  - `a=rtcp` (RFC 3605 §2.1):
    `{name, port, net_type?, addr_type?, address?}`. port is a
    decimal POS-DIGIT *DIGIT (RFC 8866 §9 integer). The optional
    triple mirrors the `c=` line.
  - `a=rtcp-mux` (RFC 5761 §5.1.3): pure flag attribute,
    `{name="rtcp-mux"}`. The grammar uses `#line_end` after the
    bare name so `a=rtcp-mux:foo` fails the match (was silently
    accepted as a generic carrier through Phase 4.D).
- `known_attr_lookahead` extended with extmap, rtcp-fb, rtcp-mux,
  rtcp — ordered so `rtcp-mux` and `rtcp-fb` bind before bare
  `rtcp`. New leaves: `extmap_direction`, `rtcp_fb_pt`.
- 10 new tests in `spec/grammar_base_spec.lua`. Suite: 1094 green.

Phase 4 close: every compound attribute named in
audits/REFACTOR-PLAN.md §5 is decomposed. The base SDP grammar produces
a rich, fully-typed doc table — no consumer needs to re-parse a
captured string. 64 new tests across Phase 4 (1030 → 1094).

- **Carry-over from Phase 3** (audit-driven): `RFC 7273 §4.8`
  cross-attribute check — *"Traceable time sources MUST NOT be
  mixed with non-traceable time sources at any given level."*
  Lives at the base tier in `validate_doc` alongside the
  existing dynamic-PT / mid-uniqueness / c=-value-form checks,
  because RFC 7273 is a generic IETF SDP attribute spec (not
  ST 2110-specific) and Phase 4.C's structured ts-refclk shape
  makes the traceability classification a direct field lookup
  (no string-substring heuristic). New registry entry
  `sdp.a.ts-refclk.traceable-mix`. Each level (session, every
  media block) is checked independently; mix across levels is
  permitted per the spec. Traceability classification: §4.6
  (gps/gal/glonass) and §4.7 (`:traceable` suffix on ntp/ptp/
  private) — all other forms (specific NTP/PTP, `local`, bare
  `private`, clksrc-ext including `localmac=`) are
  non-traceable. 7 new tests. Suite: 1101 green.

Audit ref: `audits/SPEC_INVENTORY.md` row 9 — RFC 7273 §4.8.

- **Phase 5:** soft-syntactic findings. The grammar now accepts five
  common deviations from RFC 8866 §9 strict form, recording each via
  the registry while continuing the parse. Default severity is `warn`
  per the registry — caller policy can promote any to `error` (fails
  the match) or suppress to `off`.
  - `sdp.line.lf-only-line-ending` (existing) — bare LF instead of
    CRLF. The `line_end` rule is now `P("\r\n") + Cmt(P("\n"), …) +
    Cmt(#P(-1), …)`.
  - `sdp.file.trailing-newline-missing` (existing) — last line ends
    without a terminator. Implemented via the same `#P(-1)`
    end-of-input lookahead in `line_end`; the lookahead is
    non-consuming so the document's `* -1` still matches EOF after
    the finding lands.
  - **New** `sdp.line.trailing-whitespace` — trailing SP/HTAB before
    a line terminator. The `line_end` rule's first branch absorbs the
    trailing whitespace via a Cmt before delegating to `line_end_core`.
    Value captures stop at the trailing-ws boundary via a new
    `value_boundary_chars` rule so the trailing whitespace lands in
    `line_end`'s scope, not the value string.
  - `sdp.a.fmtp.trailing-semicolon` (existing) — fmtp value ending
    with a stray `;`. The Cmt sits inside `Cg("params")` and CONSUMES
    the `;` + optional whitespace; this works around an LPeg quirk
    where a *zero-width* `Cmt(Carg(1), …)` inside the same `Cg` as
    a `%` accumulator chain trips the "no previous value for
    accumulator capture" runtime error.
  - **New** `sdp.file.bom-present` — leading UTF-8 BOM. A
    `Cmt(P("\xef\xbb\xbf") * Carg(1), …) ^ -1` at the start of the
    document rule.
- The `line_end` rule now has a clean structural twin `line_end_chars`
  (just `P("\r\n") + P("\n") + P(-1)`, no captures) used in
  `1 - V"line_end_chars"` byte-boundary lookaheads. The split is
  required: Cmt callbacks **fire during lookahead evaluation** in LPeg,
  so using the side-effectful `line_end` rule in `1 -` predicates
  would spuriously double-record findings on every `\n` byte tested
  against the boundary. All 25+ in-grammar lookaheads were migrated.
- 14 new tests covering each finding's emission, the no-finding
  baseline, the policy precedence (warn / error / off promotion),
  trailing-whitespace stripping from captured values, internal-vs-
  trailing whitespace discrimination, and the BOM-absent path.
  Suite: 1115 green.

Audit ref: audits/REFACTOR-PLAN.md §3.3 (Soft-syntactic candidates) +
LPeg-skill `references/idioms.md` §18 (accumulator caveat).

- **Phase 6.A:** compile-time grammar composition mechanism. Refactor of
  `parse_sdp/grammar/base.lua` to expose the primitives a child tier
  needs, plus an empty `parse_sdp/grammar/st2110.lua` shell that is
  internally callable but not yet wired into `sdp.parse()`.
  - `base.extend(parent, overrides)` — composes a child grammar from a
    parent. `overrides.rules` table-merges into the parent rules (child
    wins on collision); `overrides.semantic_checks` appends to the
    parent's ordered check list. The child rebuilds the `document`
    rule's Cmt so its validator closes over the merged check list.
    Returns a table with `rules` / `grammar` / `semantic_checks` /
    `match` / `extend` / `make_validate_doc` / `document_body`, so the
    result chains (`child.extend(child, {...})` for Phase 7 IPMX).
  - `base.semantic_checks` (new export) — the previously-implicit
    in-order check list `validate_doc` ran. Promoted to an explicit
    array so `extend` can splice tier checks onto the end.
  - `base.make_validate_doc(checks)` (new export) — factory that
    produces a `document_body * Carg(1)` Cmt callback bound to a
    specific check list. Both base and every child grammar use it.
  - `base.make_document_body()` (new export) — factory returning the
    `Ct(Cg(v) * Cg(o) * Cg(session) * Cg(media))` body of the document
    rule, FRESH per call. Cannot be a V-rule (`V"document_body"` breaks
    the `%` accumulator inside fmtp's params kv-list — V-rule
    indirection interferes with LPeg's compile-time resolution of
    `Ct(P("")) * X % fold`). Originally exposed as a single shared
    pattern object, but reusing the same pattern across two grammar
    compilations (base.grammar and a child grammar built via extend)
    intermittently corrupted base.grammar's match behaviour for the
    fmtp accumulator chain. The factory ensures each grammar owns its
    own document_body tree.
  - `parse_sdp/grammar/st2110.lua` — three-line module:
    `base.extend(base, {})`. Behaviorally identical to base today; the
    extension surface is in place for 6.B (leaf narrowings), 6.C (fmtp
    narrowings), 6.D (required-attribute presence), 6.E (cross-stream
    invariants). Internal entry point only — public `sdp.parse(text,
    "st2110")` continues to run the 1.0 validator chain until Phase 9.
- `spec/grammar_compose_spec.lua` — 12 new tests covering:
  child-table shape, identity behavior of empty-extend, rule-override
  precedence, semantic-check list extension and call order, fail-the-
  match semantics when a child check returns false, base-isolation
  across extend calls, chaining (grandchild composition), and the
  `parse_sdp.grammar.st2110` shell. Suite: 1127 green.

Audit ref: audits/REFACTOR-PLAN.md §3.1 (Three composed grammars / option C).

- **Phase 6.B:** ST 2110 rtpmap narrowings per media type, expressed as
  layered grammar overrides (not a post-parse doc walk). The empty
  6.A shell now overrides base's `a_rtpmap` rule with a branched form:
  one branch per recognised essence encoding, plus a default branch
  gated by negative lookahead so a malformed known-encoding rtpmap
  (e.g. `raw/48000`) cannot fall through to it. Each known-encoding
  branch ends in a Cmt that reads `Cb"clock_rate"` and `Cb"media"`
  (the surrounding media-section's m= type) and records findings via
  `errors.record`. Per the LPeg-discipline rule in CLAUDE.md and the
  user's pushback on the first 6.B attempt (which used a `doc.media`
  walker), the value-set constraints now live in the grammar itself.
  - **encoding=raw** → `m=video`, clock_rate=90000 (ST 2110-20:2022 §7.1).
    IDs `st2110-20.a.rtpmap.raw-media-type` /
    `st2110-20.a.rtpmap.raw-clock-rate`.
  - **encoding=jxsv** → `m=video`, clock_rate=90000 (ST 2110-22:2022 §6.2
    + RFC 9134 for the m=video implication; §5.2 for 90 kHz). IDs
    `st2110-22.a.rtpmap.jxsv-media-type` /
    `st2110-22.a.rtpmap.jxsv-clock-rate`.
  - **encoding=smpte291** → `m=video`, clock_rate=90000 (RFC 8331 §4
    media-type registration; ST 2110-40:2023 §5.3). IDs
    `st2110-40.a.rtpmap.smpte291-media-type` /
    `st2110-40.a.rtpmap.smpte291-clock-rate`.
  - **encoding=AM824** → `m=audio`, clock_rate ∈ {44100, 48000, 96000}
    (ST 2110-31:2022 §6.1). IDs
    `st2110-31.a.rtpmap.am824-media-type` /
    `st2110-31.a.rtpmap.am824-clock-rate-set`.

  Each ID is registered in `parse_sdp/errors.lua` with verified=true
  and the per-clause spec_ref. The semantic check uses `errors.record`
  so the fail-on-first / policy plumbing applies. Encodings not
  recognized by ST 2110 (e.g. `H264`, `L16`) pass through unchecked
  per CLAUDE.md's strictness principle (silence ≠ rejection).

  L16/L24 media-type and clock-rate constraints — implied by ST 2110-30
  §6.2.1 via reference to AES67-2013 §7.1 — are deferred. AES67-2023 is
  paywalled and unverifiable from disk (audit row 11), so the union
  check would need `verified=false`. Tracked for 6.B follow-up.

- `spec/grammar_st2110_spec.lua` — 17 new tests. Per encoding: accept
  the well-formed case, reject the wrong media-type, reject the wrong
  clock-rate (or set element). For raw, an extra test confirms the
  base tier still accepts the same input the ST 2110 tier rejects.
  Two final tests verify non-ST-2110 encodings (H264, L16) pass
  through. Suite: 1144 green (modulo a separate flake; see note).

**Note (pre-existing flakiness):** the suite intermittently reports 2
errors in `spec/grammar_base_spec.lua` for the
`sdp.a.fmtp.trailing-semicolon` cases — *"no previous value for
accumulator capture"* from inside the `Cg(Ct(P("")) * fmtp_entry * …,
"params")` chain at ~45% rate. Not introduced by 6.A or 6.B —
reproduces on the unchanged Phase 5 commit. Full investigation,
attempted workarounds, and what was ruled out in
[audits/FMTP_ACCUMULATOR_FLAKE.md](audits/FMTP_ACCUMULATOR_FLAKE.md).
Status: not yet a sendable upstream report; no standalone-Lua repro
exists, so the case for it being an LPeg bug specifically is not
established.

- The Phase 6.A `inherits base.semantic_checks unchanged at the shell
  stage` assertion in `grammar_compose_spec.lua` was rewritten to
  `inherits every base check in order, then appends ST 2110 checks` —
  asserts the inheritance shape without coupling to the per-phase
  count of appended checks.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.B; audits/SPEC_INVENTORY.md
rows ST 2110-20 §7.1 #78–79, ST 2110-22 §5.2 #7 / §6.2 #12, ST 2110-31
§6.1 #31/#36, ST 2110-40 §5.3 #13.

- **Phase 6.C.A:** `fmtp_params_branch` rewritten off the `%` accumulator
  to dissolve the long-standing trailing-semicolon flake.

  Old shape:

  ```lua
  Cg(
      Ct(P(""))
        * V"fmtp_entry"
        * (V"fmtp_sep" * V"fmtp_entry") ^ 0
        * V"fmtp_trailing_sep_record" ^ -1,
      "params")
  ```

  The `%` operator inside `fmtp_entry` folded each entry into the seed
  table. Under specific busted-harness conditions LPeg's `accumulatorcap`
  raised "no previous value for accumulator capture" at ~45% rate —
  present back through the Phase 5 commit and investigation-resistant
  to standalone-Lua repro (full record in
  [audits/FMTP_ACCUMULATOR_FLAKE.md](audits/FMTP_ACCUMULATOR_FLAKE.md)).

  New shape:

  ```lua
  Cg(
      Ct(V"fmtp_entry" * (V"fmtp_sep" * V"fmtp_entry") ^ 0)
        / fmtp_entries_to_params,
      "params")
    * V"fmtp_trailing_sep_record" ^ -1
  ```

  Each entry now captures a `{key, value}` or `{flag, true}` sub-table,
  and a function capture flattens the list into the
  `{key = value, flag = true, …}` shape the doc contract exposes. The
  optional trailing-`;` Cmt moves OUTSIDE the params Cg, so a `^-1`
  Cmt+Carg tail can no longer interact with the params capture's
  internal state.

  30 fresh `busted spec/` runs and 30 fresh
  `--filter "trailing semicolon"` runs went 30/30 green; previous rate
  ~45%. Doc-shape contract preserved (params is still a flat key/value
  table); existing tests unchanged. `set_pair` / `set_flag` Lua locals
  removed; replaced by a single `fmtp_entries_to_params` transform.

- **Phase 6.C.B:** ST 2110-20 raw fmtp parameter-form narrowing per
  ST 2110-20:2022 §7.1 — *"Each media type parameter entry shall be
  constructed as either a `<name>=<value>` pair, with no whitespace
  within the name or value or between the name, equal sign, and value;
  a `<name>` standalone declaration, with no whitespace within the
  name."* Scope:
  only fmtp lines whose PT was previously bound to a raw rtpmap. Other
  ST 2110 essence specs (-22, -30, -31, -40) do not carry this
  prohibition and keep base's loose form.

  New error id `st2110-20.a.fmtp.no-whitespace-around-equals` in
  `parse_sdp/errors.lua` (hard-syntactic / error / INVALID_VALUE / spec
  ref `ST 2110-20:2022 §7.1`).

  Implementation. The narrowing is encoding-gated, but the rtpmap's
  encoding capture is no longer in scope by the time the next a= line
  parses — each a_line closes its own a_value Ct, so `Cb"encoding"` from
  a later fmtp line cannot reach the earlier rtpmap's group capture. The
  cross-line carrier is ctx:

  - ST 2110's `a_rtpmap` override gains a trailing
    `Cmt(Cb"payload_type" * Cb"encoding" * Carg(1), ...)` that writes
    `ctx.rtpmap_encodings[pt] = encoding` after the rtpmap branch
    matches. (The Cb pair is in scope here because we're still inside
    a_rtpmap and the encoding Cg lives in the branch that just
    completed.)
  - ST 2110's `a_fmtp` override has a two-branch alternation gated on
    the recorded encoding via `Cmt(Cb"payload_type" * Carg(1), ...)`.
    The raw branch (`fmtp_st2110_raw_params`) uses a strict kv-pair
    that captures the ws around `=` and records the finding via
    `errors.record` when either side is non-empty; the non-raw branch
    falls through to base's loose `fmtp_params_branch` / `fmtp_raw_branch`.
    A raw fmtp with whitespace fails the strict branch (and the
    non-raw branch's gate), so a_fmtp fails — the finding is in
    ctx.findings under fail_on_first=true.

  `parse_sdp.grammar.base` exposes `fmtp_entries_to_params` so the
  ST 2110 strict-form override reuses the same list-to-table transform
  6.C.A introduced.

  Limitation. If a media block places `a=fmtp` for a given PT before
  the corresponding `a=rtpmap`, the encoding lookup misses (no rtpmap
  has been recorded yet) and the fmtp falls through to the non-raw
  branch. RFC 8866 does not mandate rtpmap-before-fmtp ordering, but
  every real ST 2110 sender and every fixture in the suite follows it.
  Tracked as a deferred edge case; revisit only if a real SDP surfaces
  the opposite ordering.

- `spec/grammar_st2110_spec.lua` — 8 new tests (25 total in the file).
  Per ST 2110-20:2022 §7.1: accept fmtp with no ws around `=`; reject
  ws on both sides, before only, after only; reject the offending
  entry's row when an earlier entry was clean; do NOT reject ws around
  `=` for jxsv or smpte291 (no narrowing applies); confirm base tier
  still accepts what ST 2110 rejects. Suite: 1152 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
ST 2110-20:2022 §7.1.

- **Phase 6.C.C:** ST 2110-20:2022 §7.2 (raw video required Media Type
  parameters) + ST 2110-21:2022 §8.1 (required TP for every raw video
  stream — ST 2110-20:2022 §6.1.1 requires every raw stream to conform
  to ST 2110-21). The check walks `doc.media`, finds payload types
  whose `a=rtpmap` encoding is `raw`, locates the matching `a=fmtp`,
  and verifies every required parameter is present. If no fmtp exists
  for a raw PT, the first §7.2 key (sampling) is reported missing —
  §7.2's SHALL on the parameter is necessarily a SHALL on the fmtp
  itself.

  9 new error ids in `parse_sdp/errors.lua`, one per required key:
  `st2110-20.a.fmtp.<key>-required` for sampling, width, height,
  exactframerate, depth, colorimetry, PM, SSN, TP. Each cites its own
  spec ref (sampling/width/height/exactframerate/colorimetry/PM/SSN →
  §7.2; depth → §7.4.2; TP → ST 2110-21:2022 §8.1).

  The check is registered as the first entry of the new ST 2110 tier
  `semantic_checks` list — appended to base's check list by
  `base.extend`. It's a post-parse doc walk, not a grammar narrowing:
  required-parameter PRESENCE is a cross-key invariant, not a per-pair
  syntactic check. (Per-key value-set narrowings — sampling enum, width
  range, etc. — are still pending and live in 6.C.D.)

  Limitation. The check fires only for PTs that are explicitly bound
  to `encoding=raw` via a matching `a=rtpmap`. A static PT with no
  rtpmap, or a raw PT whose rtpmap appears AFTER the fmtp in the media
  block, is not subject to the check (the same ordering caveat
  introduced in 6.C.B). RFC 8866 doesn't mandate rtpmap-before-fmtp,
  but every real ST 2110 sender follows it.

- `spec/grammar_st2110_spec.lua` — 11 new tests (39 in the file).
  Accept canonical complete raw fmtp; per-required-key reject when
  omitted (9 tests, one per key, each with its own spec citation);
  do NOT require -20 params for smpte291 (different essence); do NOT
  require -20 params for unbound static PT (no rtpmap); base tier
  still accepts a raw rtpmap with no fmtp at all; ST 2110 tier
  rejects raw video with no fmtp (sampling-required is the first
  finding). Two pre-existing Phase 6.B / 6.C.B accept-tests updated
  to append the new `RAW_FMTP_COMPLETE_PT96` helper so they don't
  trip the new §7.2 check. Suite: 1166 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
ST 2110-20:2022 §7.2 / §7.4.2; ST 2110-21:2022 §8.1.

- **Phase 6.C.D.1:** ST 2110-20:2022 enum value-set narrowings for seven
  raw video fmtp parameters: `sampling` (§7.2 — 12 values), `depth`
  (§7.4.2 — 5 values), `colorimetry` (§7.5 — 9 values), `PM` (§6.3 —
  2 values), `TP` (ST 2110-21:2022 §8.1 — 3 values), `TCS` (§7.6 —
  11 values, including 2022 addition `ST2115LOGS3`), `RANGE` (§7.3 —
  3 values). 7 new error ids `st2110-20.a.fmtp.<key>-invalid-value`,
  each carrying its own spec ref.

  Implemented as a second tier-level semantic check
  `check_raw_video_fmtp_values` alongside the §7.2 presence check.
  Both walk `doc.media` for raw rtpmap PTs; a shared
  `each_raw_video_fmtp(doc)` helper extracts the (media_index, pt,
  params) tuple list so the two checks don't repeat the doc walk.
  Each value check fires only when the parameter is PRESENT —
  absence is the *-required check's concern.

  Value sets lifted verbatim from the 1.0 parser's `VALID_SAMPLING` /
  `VALID_DEPTH` / `VALID_COLORIMETRY` / `VALID_PM` / `VALID_TP` /
  `VALID_TCS` / `VALID_RANGE` constants. Grammar-tier accepts the
  exact same set as the 1.0 parser.

  60 new tests in `spec/grammar_st2110_spec.lua` (one accept per
  permitted value per key — 50 — plus per-key reject of `BOGUS` — 7 —
  plus base-tier accepts-BOGUS confirmation per key — 7 — plus a
  non-raw scope sanity check). Suite: 1226 green.

  Per-key value-form narrowings for non-enum parameters (`width`,
  `height`, `exactframerate`, `MAXUDP`, `PAR`, `SSN`) require Lua
  predicates (integer range, gcd, pattern match); they land in
  6.C.D.2.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
ST 2110-20:2022 §7.2 / §7.3 / §7.4.2 / §7.5 / §7.6 / §6.3;
ST 2110-21:2022 §8.1.

- **Phase 6.C.D.2:** ST 2110-20:2022 non-enum value forms (§7.2 +
  §7.3) and §7.3 flag-only parameters for raw video fmtp.

  Six non-enum value-form narrowings (each PRESENT → must satisfy
  the spec rule; absence is the *-required check's concern):
  - `width` / `height` — positive integer 1..32767 (§7.2)
  - `exactframerate` — positive integer OR positive `n/d` ratio in
    lowest terms via gcd(n, d) == 1 (§7.2 "numerically smallest
    numerator value possible")
  - `MAXUDP` — positive integer ≤ 8960 (§7.3 + ST 2110-10 §6.4
    Extended UDP Size Limit)
  - `PAR` — `W:H` with W,H positive integers in lowest terms (§7.3)
  - `SSN` — `ST2110-20:2017` or `ST2110-20:2022` (§7.2: only those
    two revisions defined)

  Two flag-only narrowings (params[key] must be `true`, never a
  string captured from `key=value`):
  - `interlace` — bare-attribute flag (§7.3)
  - `segmented` — bare-attribute flag (§7.3); cross-param SHALL
    requiring `interlace` also present is deferred to 6.C.E.

  Same `check_raw_video_fmtp_values` semantic check extended with
  per-key validator functions (`make_pixel_dim_validator`,
  `validate_exactframerate`, `validate_maxudp`, `validate_par`,
  `validate_ssn`) plus a flag-only loop. Validators ported from the
  1.0 parser's predicates (`valid_pixel_dim`, `valid_exactframerate`,
  `valid_maxudp`, `valid_par`, the `_ssn20_pat`).

  8 new error ids `st2110-20.a.fmtp.<key>-invalid-value` for width,
  height, exactframerate, MAXUDP, PAR, SSN, interlace, segmented.
  33 new tests; suite: 1259 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
ST 2110-20:2022 §7.2 / §7.3; ST 2110-10 §6.4.

- **Phase 6.C.E:** ST 2110-20:2022 cross-parameter SHALLs for raw video
  fmtp. Seven constraints, each evaluating a relationship across two
  or more fmtp parameter values, ported from the 1.0 parser at
  `parse_sdp.lua:2063-2158` per [[feedback_refactor_parity]] (new
  grammar tier must be ≥ 1.0 strict).

  1. **§7.2 SSN-conditional** — colorimetry=ALPHA or TCS=ST2115LOGS3
     must be paired with SSN=ST2110-20:2022 (a :2022-only value
     requires the :2022 SSN). Forward direction only; reverse
     remains deferred per PLAN.md known items.
  2. **§7.3 BT2100 RANGE narrowing** — colorimetry=BT2100 with
     RANGE=FULLPROTECT forbidden ("only NARROW and FULL are
     permitted").
  3. **§7.3 segmented requires interlace** — bare `segmented`
     without `interlace` forbidden (PsF requires interlace too).
  4. **§6.3.3 BPM forbids MAXUDP** — PM=2110BPM with MAXUDP present
     forbidden ("The Extended UDP size limit … shall not be used in
     the Block Packing Mode").
  5. **§7.4.1 KEY requires ALPHA** — sampling=KEY with colorimetry≠
     ALPHA forbidden ("the Key stream shall signal the colorimetry
     value 'ALPHA'").
  6. **§7.4.1 KEY forbids TCS** — sampling=KEY with any TCS value
     forbidden ("shall not signal a TCS value").
  7. **§6.2.5 4:2:0 progressive only** — any `*-4:2:0` sampling with
     interlace forbidden ("The 4:2:0 sampling system shall only be
     applied to progressive scan images transmitted in a progressive
     manner").

  7 new error ids in `errors.lua`:
  `st2110-20.a.fmtp.ssn-required-for-2022-only-values`,
  `bt2100-range-fullprotect-forbidden`,
  `segmented-requires-interlace`,
  `bpm-with-maxudp-forbidden`,
  `key-requires-alpha-colorimetry`,
  `key-forbids-tcs`,
  `subsampling-420-with-interlace-forbidden`.

  Implemented as a third tier-level semantic check
  `check_raw_video_fmtp_cross_param` alongside the §7.2 presence
  check (6.C.C) and value-form check (6.C.D). All three reuse the
  shared `each_raw_video_fmtp(doc)` helper. The check is broken into
  six per-constraint helper functions (§7.4.1's two SHALLs share a
  function) ordered to match the 1.0 parser's check sequence for
  deterministic fail_on_first behaviour.

  29 new tests covering accept and reject cases for every
  constraint, plus a base-tier sanity test verifying that all seven
  violations together still pass the base tier. The 6.C.D.1
  per-key enum-acceptance helper was updated: when testing
  `sampling=KEY`, the helper now pairs it with `colorimetry=ALPHA`
  so the §7.4.1 cross-param check doesn't mask the enum value-set
  acceptance. Suite: 1282 green.

  **1.0-gap close deferred to a follow-up slice (6.C.F).** Five
  additional cross-parameter SHALLs are inventoried in
  `audits/SPEC_INVENTORY.md` (rows 61, 115, 116, 117, 118) but
  NOT enforced by the 1.0 parser:
  - §6.2.5 Table 3: 4:2:0 sampling defined-value set permits only
    depth ∈ {8, 10, 12}; values outside the table are not defined.
  - §7.6: TCS=LINEAR / BT2100LINPQ / BT2100LINHLG / ST2065-1 each
    defined with `(depth=16f)` parenthetical in the row prose.

  These are 1.0-gap closes (the constraints are in the spec; 1.0
  is incomplete, not lax), grounded by CLAUDE.md strictness
  polarity #3 (defined value forms) rather than explicit SHALL
  prose. Verification status as of this commit (2026-05-19): all
  five audit rows confirmed against `st2110-20-2022.md`, and the
  1.0 parser confirmed not to enforce any of them. Tracked in
  audits/REFACTOR-PLAN.md for a separate 6.C.F slice.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
ST 2110-20:2022 §6.2.5 / §6.3.3 / §7.2 / §7.3 / §7.4.1.

- **Phase 6.C.F:** five ST 2110-20:2022 cross-parameter SHALLs the
  1.0 parser does NOT enforce, ported to the grammar tier so the
  refactor closes the 1.0 gap. Each is grounded by CLAUDE.md
  strictness polarity #3 (defined value forms) — Table 3 / §7.6
  row prose — rather than explicit SHALL prose.

  1. **§6.2.5 Table 3** — 4:2:0 sampling pgroup table defines depth
     ∈ {8, 10, 12} only. `*-4:2:0` with depth ∈ {16, 16f} → reject.
     New error id `st2110-20.a.fmtp.subsampling-420-depth-restricted`.
  2. **§7.6 LINEAR row** — `TCS=LINEAR (depth=16f)`. Other depths →
     reject. ID `st2110-20.a.fmtp.tcs-linear-requires-depth-16f`.
  3. **§7.6 BT2100LINPQ row** — `TCS=BT2100LINPQ (depth=16f)`. ID
     `…tcs-bt2100linpq-requires-depth-16f`.
  4. **§7.6 BT2100LINHLG row** — `TCS=BT2100LINHLG (depth=16f)`. ID
     `…tcs-bt2100linhlg-requires-depth-16f`.
  5. **§7.6 ST2065-1 row** — `TCS=ST2065-1 (depth=16f)`. ID
     `…tcs-st2065-1-requires-depth-16f`.

  Two new helper functions appended to the existing tier-level
  semantic check `check_raw_video_fmtp_cross_param`:
  `check_420_depth_restricted` (§6.2.5 Table 3) and
  `check_tcs_floating_point_depth` (§7.6, dispatched per-TCS via a
  string→error_id lookup table). Helpers run after the 6.C.E
  baseline so fail_on_first behaviour preserves the existing order.

  39 new tests: every (4:2:0-sampling, allowed-depth) accept pair
  (9), every (4:2:0-sampling, forbidden-depth) reject pair (6),
  per-floating-point-TCS accept-with-16f (4), per-floating-point-TCS
  reject-with-other-depth (16), TCS-absent / non-floating-point-TCS
  / non-4:2:0 / base-tier sanity (4). The 6.C.D.1 enum-acceptance
  helper updated to pair floating-point TCS values with depth=16f
  so per-key acceptance isn't masked by the new §7.6 cross-param
  check. Suite: 1321 green.

  This completes the ST 2110-20 cross-parameter SHALL coverage:
  6.C.E ported the 7 SHALLs already enforced by 1.0; 6.C.F adds the
  5 SHALLs 1.0 missed. The grammar tier is now strictly more
  conformant than 1.0 for ST 2110-20 raw video fmtp.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
rows 61, 115, 116, 117, 118; ST 2110-20:2022 §6.2.5 Table 3 + §7.6.

- **Phase 6.C.G.1:** ST 2110-22 jxsv fmtp required-parameter presence
  (ST 2110-22:2022 §7.2 Table 1 + RFC 9134 §7.1) plus per-key
  value-set / value-form narrowings for the full RFC 9134 §7.1
  optional parameter set.

  Refactor: the `each_raw_video_fmtp(doc)` helper from 6.C.C was
  generalized to `each_fmtp_for_encoding(doc, encoding)` so the same
  walker drives raw, jxsv, smpte291, and AM824 scope checks. A thin
  `each_raw_video_fmtp` wrapper preserves the original call sites.

  4 required-param error ids: `st2110-22.a.fmtp.{width,height,TP,
  packetmode}-required`. 16 value-form / flag-only error ids:
  `st2110-22.a.fmtp.<key>-invalid-value` for sampling, exactframerate,
  depth, TCS, colorimetry, RANGE, transmode, profile, level, sublevel,
  SSN, MAXUDP, CMAX, width, height, TP, packetmode, interlace,
  segmented.

  Two new semantic checks (`check_jxsv_fmtp_required`,
  `check_jxsv_fmtp_values`) mirror the -20 raw structure. Both scoped
  to PTs whose `a=rtpmap` encoding is `jxsv` via the ctx-carried
  rtpmap→encoding map (Phase 6.C.B mechanism).

  **Spec-conformant divergence from 1.0 parser.** The 1.0 parser
  reuses ST 2110-20's value sets for jxsv `colorimetry`, `TCS`, and
  `sampling`. RFC 9134 §7.1 — verified directly against
  `https://www.rfc-editor.org/rfc/rfc9134.txt` — defines its own enums
  that overlap but are not identical. The grammar tier follows RFC
  9134 (primary spec text). Per [[feedback_refactor_parity]] this is
  a 1.0-gap close that goes both ways:

  - `colorimetry`: RFC 9134 lists `{BT601-5, BT709-2, SMPTE240M,
    BT601, BT709, BT2020, BT2100, ST2065-1, ST2065-3, XYZ,
    UNSPECIFIED}`. 1.0 reuses -20's set (includes `ALPHA`, omits the
    three legacy values). Net: grammar accepts BT601-5/BT709-2/
    SMPTE240M (1.0 rejected); rejects ALPHA (1.0 accepted).
  - `TCS`: RFC 9134 lists `{SDR, PQ, HLG, UNSPECIFIED}` only. 1.0
    reuses -20's 11-value set. Net: grammar rejects LINEAR, BT2100-
    LINPQ, BT2100LINHLG, ST2065-1, ST428-1, DENSITY, ST2115LOGS3
    (all of which 1.0 accepted for jxsv).
  - `sampling`: RFC 9134 adds `UNSPECIFIED` to the -20 set. Net:
    grammar accepts UNSPECIFIED for jxsv (1.0 rejected).

  Five tests in `RFC 9134 §7.1 vs 1.0 enum divergence` lock the new
  behavior in: ALPHA rejected, BT601-5 accepted, LINEAR rejected,
  ST2115LOGS3 rejected, UNSPECIFIED sampling accepted.

  133 new tests total (310 in the file). Suite: 1437 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; audits/SPEC_INVENTORY.md
RFC 9134 rows 31–58 + ST 2110-22:2022 rows 7, 9, 11–13, 20–26.

- **Phase 6.C.G.2:** ST 2110-22 jxsv fmtp cross-parameter SHALLs.
  Two constraints from RFC 9134 §7.1, parallel in shape to the
  6.C.E pair on -20 but with their own normative source (separate
  error ids so audit grep can target either independently):

  1. **`segmented` requires `interlace`** — RFC 9134 §7.1
     segmented row: *"Signaling of this parameter without the
     interlace parameter is forbidden."*
  2. **BT2100 colorimetry RANGE narrowing** — RFC 9134 §7.1
     RANGE row: *"When paired with [BT.2100-2] colorimetry, the
     allowed values are NARROW and FULL."* Implies
     `RANGE=FULLPROTECT` rejected with `colorimetry=BT2100`.

  2 new error ids: `st2110-22.a.fmtp.segmented-requires-interlace`
  and `st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden`. New
  tier-level semantic check `check_jxsv_fmtp_cross_param` runs
  both per-jxsv-PT. 8 new tests; suite 1445 green.

  This closes the jxsv fmtp port (6.C.G).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; RFC 9134 §7.1.

- **Phase 6.C.H:** ST 2110-30 / -31 audio `channel-order` fmtp
  syntax. Optional `a=fmtp` parameter on L16 / L24 / AM824 audio:
  *"If channel order is signaled in the SDP, the syntax of IETF
  RFC 3190 for the parameter channel-order shall be used."*
  (§6.2.2). RFC 3190 form `<convention>.<order>`. When the
  convention is `SMPTE2110`, the order SHALL be
  `(<group>[,<group>...])` with each group from §6.2.2 Table 1
  ({M, DM, ST, LtRt, 51, 71, 222, SGRP}) or a Unn track symbol
  (U01–U64). The `AES3` group is permitted only on AM824 per
  ST 2110-31:2022 §6.2 Table 2. Other conventions accepted
  structurally — §6.2.2 is silent on their internals.

  2 new error ids:
  - `st2110-30.a.fmtp.channel-order-invalid` (RFC 3190 syntax,
    SMPTE2110 form, unknown group symbol, out-of-range Unn).
  - `st2110-31.a.fmtp.channel-order-aes3-requires-am824` (AES3
    group on non-AM824 encoding).

  Implemented as a new tier-level semantic check
  `check_audio_fmtp_channel_order` with a per-encoding helper
  walker `each_audio_fmtp(doc)` that multiplexes L16/L24/AM824
  rtpmap PTs in one pass. 22 new tests covering every group
  symbol (8), Unn range bounds, AES3 across encodings (3
  accept/reject), syntax malformations (5), non-SMPTE2110
  passthrough, channel-order absence (optional), and base-tier
  sanity. Suite: 1467 green.

  Scope note: ST 2110-30's other fmtp-adjacent checks (MAXUDP-
  forbidden on audio, packet-payload-fit calculation) are
  cross-attribute / cross-layer (RTP-payload-aware) rather than
  per-key fmtp narrowings. They live more naturally in Phase 6.D
  (per-encoding required-attribute / cross-attribute checks) and
  are deferred there.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; ST 2110-30:2025 §6.2.2;
ST 2110-31:2022 §6.2 Table 2; RFC 3190 §6.

- **Phase 6.C.I:** ST 2110-31:2022 §6.1 AM824 rtpmap channel-count
  parity. *"the number of AES3 Subframe sequences `<nchan>` expressed
  in the SDP object shall always be an even number."* AM824
  transports AES3 signals; each AES3 signal contains two sequences
  of AES3 Subframes, so `<nchan>` is always even.

  This is a 1.0-parity port: `parse_sdp.lua:2222-2227` enforces the
  same SHALL, but the grammar tier hadn't picked it up — the Phase
  6.B rtpmap narrowings covered clock-rate-set and media-type but
  not channel parity. Closing the regression.

  1 new error id: `st2110-31.a.rtpmap.am824-channels-must-be-even`
  (registered under the rtpmap namespace because `<nchan>` appears
  on the `a=rtpmap` line, not `a=fmtp`).

  New tier-level semantic check `check_am824_rtpmap_channels_even`
  that walks `doc.media` for rtpmap PTs with encoding=AM824 and
  asserts `channels % 2 == 0` when channels is present. The
  channels-presence SHALL (required for all audio rtpmap per
  RFC 3551 §6) is a separate concern that belongs to Phase 6.D.

  14 new tests: 6 accept (even channels {2, 4, 8, 16, 32, 64}),
  5 reject (odd channels {1, 3, 5, 7, 15}), L24 and L16 non-AM824
  with odd channels accepted (narrowing is AM824-only), base-tier
  accepts AM824 with odd channels (no -31 narrowing in base).
  Suite: 1481 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; ST 2110-31:2022 §6.1.

- **Phase 6.C.J:** ST 2110-41:2024 (Fast Metadata) fmtp narrowings.
  Distinct shape from the -20 family: SSN is the only required
  parameter, DIT is optional with a tight value form, MAXUDP is
  forbidden.

  4 new error ids:
  - `st2110-41.a.fmtp.SSN-required` — §6 names SSN as required.
  - `st2110-41.a.fmtp.SSN-invalid-value` — §6 defines only
    `ST2110-41:2024` (no other revisions exist).
  - `st2110-41.a.fmtp.DIT-invalid-value` — §6 value form: comma-
    separated uppercase hex tokens; no `0x` prefix; no whitespace.
  - `st2110-41.a.fmtp.maxudp-forbidden` — §5.4 limits UDP packet
    length to the Standard UDP Size Limit; MAXUDP signals operation
    beyond that limit (ST 2110-10:2022 §6.4), so its presence
    violates §5.4.

  Implemented as a new tier-level semantic check
  `check_st2110_41_fmtp` scoped to PTs whose rtpmap encoding is
  `ST2110-41`. SSN validator is a literal string match. DIT
  validator is an LPeg pattern mirroring the 1.0 parser's
  `_dit_pat`: `R("09","AF")^1 * (P(",") * ...)^0 * P(-1)`. Lua
  string-patterns don't support quantified groups, so the
  comma-separated form isn't expressible as `string.match`.

  12 new tests; suite 1493 green.

  **Phase 6.C is now closed.** Coverage summary across all ten
  sub-phases:
  - 6.C.A: fmtp_params_branch %-accumulator rewrite (flake fix)
  - 6.C.B: §7.1 no-whitespace-around-= (ctx-based encoding lookup)
  - 6.C.C: §7.2 + §7.4.2 + -21 §8.1 required-param presence
  - 6.C.D.1 + .2: 7 enum value-sets + 6 non-enum forms + 2 flag-only
  - 6.C.E: 7 cross-parameter SHALLs (1.0 parity)
  - 6.C.F: 5 cross-parameter SHALLs (1.0-gap close)
  - 6.C.G.1 + .2: jxsv presence + 16 value-form/flag-only + 2 cross-
    param (with RFC 9134 enum corrections vs 1.0)
  - 6.C.H: -30/-31 audio channel-order syntax
  - 6.C.I: -31 AM824 channel-parity (1.0-parity port)
  - 6.C.J: -41 SSN/DIT/MAXUDP

  Grammar tier ST 2110 fmtp coverage is now at or above 1.0 parser
  parity across every encoding (-20 / -22 / -30 / -31 / -41), with
  several spec-conformant 1.0-gap closes (depth/sampling/TCS
  combinations from §6.2.5 Table 3 and §7.6; RFC 9134 enum
  corrections for jxsv).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.C; ST 2110-41:2024 §5.4 + §6.

- **Phase 6.D.A:** ST 2110-10:2022 §8.2 + §8.3 per-media-block
  required-attribute presence. First slice of Phase 6.D; lifts
  ts-refclk / mediaclk presence checks from the 1.0 parser into the
  grammar tier with corrected citations (1.0 cited §7.2 / §7.3; primary
  text places the SHALLs at §8.2 / §8.3).

  2 new error ids:
  - `st2110.attr.ts-refclk-required` — §8.2: "All stream descriptions
    shall have a ts-refclk attribute as specified in IETF RFC 7273
    section 4." Per-stream presence; RFC 7273 §4.8 permits the
    attribute at session level, so a session-level ts-refclk covers
    all media blocks (the check exits early when one is present).
  - `st2110.attr.mediaclk-required` — §8.3: "All stream descriptions
    shall have a media-level mediaclk attribute as per IETF RFC 7273
    section 5." The "media-level" qualifier means a session-level
    mediaclk does NOT satisfy the per-stream SHALL — a media block
    lacking its own `a=mediaclk` is rejected even if the session
    carries one.

  Two new tier-level semantic checks `check_ts_refclk_presence` and
  `check_mediaclk_presence` walk `doc.media` and emit findings with
  `field_path = "media[<i>]"`. Helpers `media_block_has_attr` and
  `session_has_attr` are reused across both checks. The base grammar
  already parses both attributes via the RFC 7273 ABNF (`a_ts_refclk`
  and `a_mediaclk` rules) — this slice only adds the per-media-block
  presence assertions on top of existing value-form validation.

  The `build()` / `build_with_fmtp()` helpers in
  `spec/grammar_st2110_spec.lua` (and the `MINIMAL_WITH_RTPMAP`
  fixture in `spec/grammar_compose_spec.lua`) now include
  `a=ts-refclk:localmac=…` and `a=mediaclk:sender` lines by default
  so the existing ~140 grammar-tier ST 2110 tests survive the new
  per-block requirement.

  8 new tests in `spec/grammar_st2110_spec.lua`: positive (single
  media block carrying both), negative (each attribute omitted in
  turn), session-level cover for ts-refclk only (§4.8 path),
  session-level non-cover for mediaclk (§8.3 "media-level"), and
  multi-media-block per-index field-path reporting. Suite: 1501 green.

Audit ref: [audits/REFACTOR-PLAN.md](audits/REFACTOR-PLAN.md) §5 Phase 6.D; ST 2110-10:2022 §8.2 + §8.3;
on-disk primary text at [`smpte_standards_internal/st2110-10-2022.pdf`](../../Standards Related/smpte_standards_internal/st2110-10-2022.pdf).

- **Phase 6.D.B:** ST 2110-30:2025 §6.2.1 audio MAXUDP-forbidden
  (L16 / L24 only).

  1 new error id `st2110-30.a.fmtp.maxudp-forbidden`. §6.2.1 says
  "The Standard UDP Datagram Size Limit as defined in SMPTE ST
  2110-10 shall be used." Combined with ST 2110-10:2022 §6.4 / §8.6
  (MAXUDP signals operation beyond the Standard Limit), MAXUDP
  cannot appear in a conformant L16 / L24 fmtp.

  New tier-level semantic check `check_audio_maxudp_forbidden` walks
  `each_audio_fmtp(doc)` (helper from 6.C.H) and emits the finding
  when encoding ∈ {L16, L24} and `params.MAXUDP` is present.

  **INTENTIONAL non-parity with 1.0.** The 1.0 parser at
  [`parse_sdp.lua:2293`](parse_sdp.lua#L2293) also forbids MAXUDP
  for AM824 with the cite "ST 2110-31 §5.x inherits the same UDP-
  size constraint." Primary text disagrees: ST 2110-31 §5.2 defers
  to ST 2110-10, which explicitly *permits* MAXUDP for streams
  exceeding the Standard Limit (§6.5). No -31 clause forbids MAXUDP.
  Per the validation-strictness principle (silence is not a reason
  to reject), the grammar tier ports only the well-grounded -30
  limb of the check. The 1.0 AM824 check is now flagged as a
  candidate for removal in a separate audit pass.

  5 new tests in `spec/grammar_st2110_spec.lua`: positive (L24
  without MAXUDP), reject L24 + MAXUDP, reject L16 + MAXUDP,
  intentional accept on AM824 + MAXUDP, no-spill onto raw video
  with MAXUDP. Suite: 1506 green.

Audit ref: ST 2110-30:2025 §6.2.1 + ST 2110-10:2022 §6.4 + §8.6;
on-disk primary text at `smpte_standards_internal/st2110-30-2025.pdf`
and `st2110-10-2022.pdf`. Out-of-parity-flag: 1.0 parser's
ST 2110-31 MAXUDP-forbidden limb.

- **Phase 6.D.C:** ST 2110-31:2022 §6.1 AM824 rtpmap
  channels-required (AM824 only).

  1 new error id `st2110-31.a.rtpmap.am824-channels-required`. §6.1:
  "The number of AES3 Subframe sequences multiplexed within the
  payload shall be signaled in the SDP object on the a=rtpmap line,
  using the syntactic field which typically communicates the number
  of channels in an audio signal, as shown below: `a=rtpmap:<pt>
  AM824/<clock-rate>/<nchan>`". The `<nchan>` field is therefore
  mandatory for AM824 rtpmaps.

  New tier-level semantic check `check_am824_rtpmap_channels_required`
  walks `doc.media`, finds rtpmap PTs with encoding=AM824, and emits
  the finding when `attr.channels == nil`. Paired with the existing
  `check_am824_rtpmap_channels_even` (Phase 6.C.I) which only fires
  when channels is present; the two together fully cover §6.1's
  channels constraint.

  **INTENTIONAL non-parity with 1.0.** The 1.0 parser also enforces
  channels-required for L16 / L24 audio rtpmaps, citing an unverified
  "ST 2110-30 tightens RFC 3551" annotation in
  `audits/SPEC_INVENTORY.md` row 58. Primary text of ST 2110-30:2025
  / AES67-2013 §8.4 / RFC 3551 §6 does NOT carry that SHALL — RFC
  3551 §6 explicitly makes the channels field OPTIONAL (defaults to
  1). The grammar tier ports only the well-grounded AM824 limb. The
  1.0 L16/L24 channels-required check is flagged for audit-folder
  follow-up.

  5 new tests in `spec/grammar_st2110_spec.lua`: positive (AM824 with
  channels), reject AM824 missing channels, multi-media-block per-pt
  field-path, intentional accept on L24 missing channels, intentional
  accept on L16 missing channels. Suite: 1511 green.

Audit ref: ST 2110-31:2022 §6.1 (line 502 in pdftotext extract); RFC
3551 §6; AES67-2013 §8.4. On-disk primary text at
`smpte_standards_internal/st2110-31-2022.pdf`, `aes67-2013-f.pdf`. Out-
of-parity-flag: 1.0 parser's L16 / L24 channels-required limb.

- **Phase 6.D.D:** ST 2110-30:2025 §6.2.1 audio packet-payload-fit
  (L16 / L24 only).

  1 new error id `st2110-30.audio.packet-payload-fit`. §6.2.1's
  "Standard UDP Datagram Size Limit ... shall be used" combined with
  ST 2110-10:2022 §6.4 (Standard Limit = 1460 octets UDP payload)
  and the 12-octet RTP fixed header (RFC 3550 §5.1) yields an RTP
  payload limit of 1448 octets per audio packet.

  Per AES67-2013 §8.1, `samples_per_packet = round(clock_rate × ptime
  / 1000)`. The check computes
  `needed = channels × bytes_per_sample × samples_per_packet`
  (where `bytes_per_sample` = 2 for L16, 3 for L24) and emits the
  finding when `needed > 1448`. RFC 3551 §6's `channels = 1` default
  is applied when the rtpmap channels field is absent.

  New tier-level semantic check `check_audio_packet_payload_fit`
  walks `doc.media`, finds `a=ptime`, and iterates rtpmap attributes
  whose encoding is in `{L16, L24}`. Skips quietly when ptime is
  absent (separate ptime-required SHALL from AES67 §8.1 left for a
  later slice). AM824 intentionally excluded, matching 6.D.B scope.

  9 new tests in `spec/grammar_st2110_spec.lua`: positive (L24/48k/2
  ptime=1, L16/48k/2 ptime=1, L24/48k/2 ptime=5 at boundary 1440 B,
  L24/48k default-channels=1), reject (L24/48k/2 ptime=6 → 1728 B,
  L24/48k/64 ptime=1 → 9216 B, L16/48k/8 ptime=2 → 1536 B),
  intentional skips (no-ptime, AM824 over-sized). Suite: 1520 green.

**Phase 6.D is now closed.** Coverage summary across the four slices:

- 6.D.A: ST 2110-10 §8.2 + §8.3 ts-refclk + mediaclk presence
- 6.D.B: ST 2110-30 §6.2.1 L16/L24 MAXUDP-forbidden
- 6.D.C: ST 2110-31 §6.1 AM824 rtpmap channels-required
- 6.D.D: ST 2110-30 §6.2.1 L16/L24 packet-payload-fit

- **Phase 6.E.A:** RFC 5888 group attribute cross-stream invariants
  (base SDP tier).

  2 new error ids:
  - `sdp.a.group.requires-mid-on-all-media` — RFC 5888 §6: "All of the
    'm' lines of a session description that uses 'group' MUST be
    identified with a 'mid' attribute whether they appear in the
    group line(s) or not." Conditional MUST triggered by presence of
    any session-level `a=group`. Semantics-independent (LS, FID, DUP,
    …). 1.0-parity port.
  - `sdp.a.group.references-port-zero-mid` — RFC 5888 §9.2: "`a=group`
    lines MUST NOT contain identification-tags that correspond to 'm'
    lines with the port set to zero." Closes a 1.0 gap: 1.0 did not
    enforce this; the new check makes the grammar tier strictly more
    conformant.

  New base-tier semantic check `check_group_attribute_invariants` in
  [parse_sdp/grammar/base.lua](parse_sdp/grammar/base.lua) (added to
  `base_semantic_checks` between `check_mid_uniqueness` and
  `check_tsrefclk_traceability`). Single function does one doc walk
  for both passes: collects all session-level `a=group` attributes,
  then runs the §6 pass (every media block must have `a=mid`) and the
  §9.2 pass (build `mid → port` map; reject group tags pointing at
  port-0 mids).

  7 new tests in `spec/grammar_base_spec.lua` covering §6 positive
  (every block has mid), no-group skip, reject (missing mid),
  third-block-not-referenced reject, and §9.2 positive (non-zero
  ports), reject (port-0 referenced), and skip (port-0 not in any
  group). Suite: 1527 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.E; RFC 5888 §6 + §9.2
verified against primary text via WebFetch.

- **Phase 6.E.B:** ST 2110-10 §8.5 group:DUP leg coherence
  (ST 2110 tier).

  7 new error ids covering the full cross-stream coherence semantics
  for `a=group:DUP`. All cite `ST 2110-10:2022 §8.5` as the SDP-side
  spec_ref; the underlying SHALL chain (§8.5 invokes ST 2022-7 §6
  which requires "at least two streams" with bit-identical RTP
  headers + payloads) lives in error-registry comments and message
  text:

  - `st2110-10.a.group-dup.mid-resolve` — every DUP tag must
    resolve to a defined `a=mid`; unresolved tags reduce the
    effective leg count, breaking ST 2022-7 §6's at-least-two-
    streams SHALL.
  - `st2110-10.a.group-dup.min-2-legs` — direct ST 2022-7 §6:
    "The transmitter shall transmit at least two streams".
  - `st2110-10.a.group-dup.media-type-same` — chained: ST 2022-7
    §6's bit-identical RTP payload cannot be satisfied across
    different m= media types.
  - `st2110-10.a.group-dup.rtpmap-same` — chained: same encoding
    + clock rate required across legs.
  - `st2110-10.a.group-dup.payload-type-same` — chained: PT field
    is part of the RTP header that must be bit-identical.
  - `st2110-10.a.group-dup.fmtp-same` — chained: identical RTP
    payload bytes imply identical signaled essence params.
  - `st2110-10.a.group-dup.addr-coherence` — direct ST 2110-10
    §8.5: "Redundant streams shall not use both identical source
    addresses and identical destination addresses at the same
    time".

  ST 2022-7:2019 §6 chain verified on disk at
  `/tmp/st2022-7.txt:234-236`:
  > "The transmitter shall transmit at least two streams, each
  > containing copies of each RTP datagram. The RTP header and
  > the RTP payload shall be identical for each datagram copy."

  New tier-level semantic check `check_group_dup_coherence` in
  `parse_sdp/grammar/st2110.lua` builds a mid → media-block index
  once, then for each `a=group:DUP` session attribute resolves
  tags, validates min-2 legs, and compares legs[2..N] against
  legs[1] across all five essence attributes plus address
  coherence. Helpers `params_equal` (order-insensitive table
  compare), `first_attr`, and `leg_src_dst` (reads
  `attr.src_addresses[1]` from the decomposed source-filter).

  **Improvement over 1.0:** fmtp comparison is now order-
  insensitive (table compare on decomposed `params`) instead of
  raw value-string compare. A DUP pair with reordered-but-
  equivalent fmtp keys would have been rejected by 1.0 but is
  accepted by the grammar tier as semantically identical.

  11 new tests in `spec/grammar_st2110_spec.lua`: positive
  (identical legs), mid-resolution (one tag undefined), min-2-
  legs (single-tag group), media-type-mismatch, rtpmap-encoding-
  mismatch, payload-type-mismatch, fmtp-mismatch, reordered-
  fmtp-equivalence (the 1.0-improvement case), address-coherence
  reject (both src+dst identical), accept (RFC 7104 §4.1 same-
  dst-different-src), accept (RFC 7104 §4.2 different-dst).
  Suite: 1538 green.

**Phase 6.E is now closed.** Coverage summary across the two
slices:

- 6.E.A: RFC 5888 §6 + §9.2 group/mid invariants (base tier)
- 6.E.B: ST 2110-10 §8.5 + ST 2022-7 §6 group:DUP leg coherence
  (ST 2110 tier, 7 checks)

**Phase 6 is now closed.** Phases 6.A–6.E ship the full ST 2110
+ base-SDP cross-stream and per-encoding coverage set. The
grammar tier matches or exceeds the 1.0 parser on every check
that is grounded in primary spec text; three 1.0-over-strict
flags (audio MAXUDP / channels-required / packet-payload-fit
limbs for AM824 or L16/L24) are intentionally not ported and
remain flagged in `audits/` for follow-up.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.E; ST 2110-10:2022 §8.5,
ST 2022-7:2019 §6 verified against on-disk primary text.

- **Phase 6.F:** in-grammar refactor of per-line checks that shipped
  through 6.B–6.E as post-parse doc walks via `semantic_checks`.

  User pushback: `semantic_checks` is itself a Lua-massage pipeline
  between parse and validation — exactly the "drop out of LPeg
  between stages" pattern flagged in
  [[lpeg-discipline]]. REFACTOR-PLAN §3.1 sanctions doc-level Cmt for
  *cross-section invariants*, but 11 of the 13 ST 2110-tier checks
  were per-attribute or per-media-block constraints that don't need
  the cross-section escape hatch. They land in-grammar in this slice.

  **Category A — 9 per-fmtp-line checks moved to a Cmt on `a_fmtp`.**
  A new `FMTP_CHECKS_BY_ENCODING` dispatch table maps each rtpmap
  encoding to the ordered check list that fires when the matching
  fmtp line completes its match. A single trailing Cmt on `a_fmtp`
  reads `Cb"payload_type" * (Cb"params" + Cc(nil)) * Carg(1)`, looks
  the encoding up via the existing `ctx.rtpmap_encodings[pt]` map
  (populated by `a_rtpmap`'s own trailing Cmt), and dispatches:
  - raw → required + values + cross-param
  - jxsv → required + values + cross-param
  - L16 / L24 → channel-order syntax + MAXUDP-forbidden
  - AM824 → channel-order syntax
  - ST2110-41 → SSN/DIT/MAXUDP-forbidden

  Each check function's signature dropped from `(doc, ctx)` (with
  outer `for _, e in ipairs(each_X(doc)) do ... end` walks) to
  `(params, ctx, encoding)` — a single fmtp instance.

  **Category B — 2 per-rtpmap-line AM824 checks moved into the
  `st2110_rtpmap_am824` rule.** The branch now uses ordered choice on
  the optional `/<channels>` suffix: present → Cmt validates evenness;
  absent → Cmt records the §6.1 channels-required SHALL. Both Cmts
  return `pos` to continue matching so the trailing rate+media-type
  Cmt still fires.

  **One small Category C-movable bridge check stayed in
  `semantic_checks`.** `check_rtpmap_requires_fmtp` covers the case
  the in-grammar dispatch can't see: a raw/jxsv/-41 rtpmap with NO
  matching `a=fmtp` at all (no fmtp line ⇒ no Cmt fires). The check
  walks `doc.media`, finds rtpmap PTs whose encoding requires fmtp,
  and runs the same required-keys check against an empty `params`
  table — yielding the identical `<key>-required` finding set the
  doc-walk previously produced. It belongs in a `media_section` Cmt
  but lives in `semantic_checks` until that infrastructure exists.

  **Obsolete helpers removed**: `each_fmtp_for_encoding`,
  `each_raw_video_fmtp`, `each_audio_fmtp`, `AUDIO_ENCODINGS`,
  `PCM_ENCODINGS`. Net file size: `parse_sdp/grammar/st2110.lua` from
  1334 lines down to ~1280 (smaller AND denser).

  **`semantic_checks` is now scoped to genuine cross-section
  invariants only**:
  - `check_rtpmap_requires_fmtp` (Category C-movable; awaits
    media_section Cmt infrastructure)
  - `check_ts_refclk_presence` (session-level cover semantics)
  - `check_mediaclk_presence` (per-media-block; could move to
    media_section Cmt later)
  - `check_audio_packet_payload_fit` (per-media-block cross-attr;
    same)
  - `check_group_dup_coherence` (cross-media-block, doc-level)

  **Behavioral change**: per-fmtp-line findings no longer carry a
  `media[N].attributes[fmtp:pt=PT]` field_path prefix (the grammar
  doesn't track media-index by default). One test that asserted on
  the deep field_path was relaxed to assert finding presence only.

  Suite unchanged at 1538 green; no error registry entries added or
  removed; no behavioral regression detected.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.F; [[lpeg-discipline]]
memory note updated with the per-category placement rule and the
explicit naming of `semantic_checks` as a Lua-massage pipeline
worth scrutinizing.

- **Phase 6.G:** in-grammar Cmts now carry byte position → line/col
  for human-readable error diagnostics, plus assorted cleanups.

  User pushback after 6.F: per-fmtp / per-rtpmap findings dropped
  the `media[N].attributes[…]` field_path prefix that doc-walks
  used to carry, and the line/col fallback in `errors.format` never
  fired because in-grammar Cmts emitted findings with `loc = {}`
  (no position info). Net result: a 4-media-block SDP with a bad
  raw fmtp produced "fmtp 'sampling' invalid value" with no
  indication of which block.

  This slice wires position through. New `errors.pos_to_line_col(
  text, pos)` translates an LPeg byte position to (1-indexed line,
  col) via O(n) LF scan. `errors.record` now accepts `loc.pos` and,
  when `ctx.text` is present, translates to populate the finding's
  `line` / `col` fields. `make_match` in
  `parse_sdp/grammar/base.lua` stores the input text in `ctx.text`
  automatically.

  Updated every in-grammar Cmt call site to pass `loc.pos = pos`:
  `record_soft` and `fmtp_trailing_sep_record` in base.lua;
  `record_rate_and_media`, the AM824 rtpmap channels-required +
  channels-even Cmts, `fmtp_st2110_raw_kv_pair`
  (whitespace-around-=), and the 6.F `fmtp_dispatch` in st2110.lua.
  The 9 per-fmtp check functions (raw / jxsv / audio / -41) take
  `(params, ctx, pos)` or `(params, ctx, pos, encoding)` and pass
  pos through to `errors.record`. The 10 raw / jxsv cross-param
  helpers had their dead `path` parameter (always passed as `""`
  since 6.F) replaced with `pos` — fixes the dead-param smell AND
  threads position in one pass.

  Diagnostic improvement, before / after:

  ```text
  error: [MISSING_FIELD] fmtp 'sampling' invalid value
    = note: required by ST 2110-20:2022 §7.2

  error: [MISSING_FIELD] fmtp 'sampling' invalid value
   --> line 8, col 127
    = note: required by ST 2110-20:2022 §7.2
  ```

  Doc-walks (semantic_checks) continue to record without `pos` —
  they don't have one, since they iterate the captured doc after
  parsing. Their findings keep `line=0 col=0` (no regression vs.
  pre-6.F).

  Cleanup: dropped a stale 4-line orphan comment in
  `parse_sdp/grammar/st2110.lua` that referenced the deleted
  `check_am824_rtpmap_channels_*` helpers (relics of the 6.F
  refactor). Consolidated a doubled MAXUDP-forbidden comment block.

  8 new tests: 3 unit tests for `pos_to_line_col` + 3 unit tests
  for `errors.record` loc.pos translation in
  `spec/error_registry_spec.lua`; 2 integration tests in
  `spec/grammar_st2110_spec.lua` verifying that the raw-fmtp
  missing-sampling and AM824 missing-channels findings now carry
  real line numbers. Suite: 1546 green.

  Implementation note: under `fail_on_first=true`, an in-grammar
  Cmt that returns `false` (because record returned cont=false)
  fails its grammar match, which triggers LPeg backtracking — the
  same Cmt may fire again under a different alternation branch,
  appending a duplicate finding. Only the first finding is
  user-visible (the doc returns nil and only the deepest-failure
  is reported), so the duplicate is invisible in practice. The new
  integration tests use `fail_on_first=false` to dodge this and
  inspect findings directly.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.G.

- **Phase 6.H:** in-grammar refactor for base SDP's connection-address
  validation; follow-up audit of base.lua's remaining
  `semantic_checks`.

  Same principle as 6.F applied to base.lua: a per-line check
  shouldn't sit in `semantic_checks`. `check_connection_addresses`
  was a doc walk that iterated `doc.session.connection` plus every
  `doc.media[i].connection` and validated each address (IPv4/IPv6
  syntax, multicast TTL/numaddr suffix forms, unicast-with-suffix
  rejection). Lifted in-grammar as a `Cmt` appended to `c_value`,
  inside the existing Ct so `Cb"addr_type"` + `Cb"address"` resolve
  cleanly. Same validation logic in `validate_c_address`, now taking
  `(addr_type, address, ctx, pos)` instead of `(..., path)`. The
  per-c= line position threads through 6.G's `loc.pos` plumbing, so
  findings carry real line numbers.

  Audit of base.lua's remaining 4 semantic_checks (so the layering
  is documented even where no move happened):

  - `check_dynamic_pt_rtpmap` — per-media-block; could move to a
    `media_section` Cmt if that infrastructure gets added.
    Currently a legitimate semantic_check.
  - `check_tsrefclk_traceability` — per-level (session + each
    media). Same story.
  - `check_mid_uniqueness` — cross-media-block; genuinely
    doc-level.
  - `check_group_attribute_invariants` — cross-section (session
    `a=group` references mids in media blocks); genuinely
    doc-level.

  Net: base.lua's `semantic_checks` list dropped from 5 to 4. The
  remaining 4 carry an explanatory comment classifying each as
  "could move with media_section Cmt infra" vs "genuinely
  cross-section". When the media_section Cmt slot lands, 2 more
  base checks + the 6.F bridge check `check_rtpmap_requires_fmtp`
  in st2110 will all migrate there.

  One test in `spec/grammar_base_spec.lua` relaxed: the test for
  "media-level IPv4 multicast missing TTL is rejected with
  media[N].connection path" had its field_path assertion replaced
  with a line-number assertion (line 6, the c= line). Same shape
  as the 6.F test relaxation for the AM824 channels-required
  multi-block test.

  Suite: 1546 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.H.

- **Phase 6.J:** shared numeric-value-form patterns + validator sweep.

  Triggered by a code review on `make_pixel_dim_validator()` —
  a no-arg factory returning an identical closure on every call,
  called 4 times (`width` + `height` for raw + jxsv). Vestigial
  premature flexibility from someone who expected to parameterize
  bounds later and never did. Also surfaced a wider pattern: 7
  inline `:match("^%d+$")` and `:match("^(%d+)/(%d+)$")` checks
  scattered across the value validators in `st2110.lua`, each
  doing essentially the same "is this a clean POS-DIGIT *DIGIT?"
  job.

  **New shared module `parse_sdp/grammar/patterns.lua`** exposes
  reusable LPeg primitives for RFC 8866 §9 numeric ABNF:
  - `pos_int_raw` — POS-DIGIT *DIGIT, unanchored (composable)
  - `zero_based_int_raw` — "0" / POS-DIGIT *DIGIT
  - `int_raw` — optional "-" prefix + zero-based-integer
  - `pos_int` / `int` — anchored standalone forms (`* P(-1)`)
    for whole-string value validation
  - `fraction` — anchored `<pos-int>/<pos-int>`, captures (n, d)
  - `ratio` — anchored `<pos-int>:<pos-int>`, captures (w, h)

  **Why LPeg patterns over `math.tointeger(v)`?** Lua's converter
  is too permissive for spec-conformant POS-DIGIT *DIGIT: it
  accepts hex literals (`0x780`), scientific notation (`1e3`),
  leading/trailing whitespace, and signs (`+100`). The LPeg
  patterns enforce the exact ABNF shape (no leading zero, no
  prefix, decimal only). See the new
  `spec/grammar_patterns_spec.lua` for the full accept/reject
  matrix per pattern.

  **base.lua aliasing.** The `rfc8866_pos_int` and
  `rfc8866_zero_based_int` V-rules in `parse_sdp/grammar/base.lua`
  now alias `patterns.pos_int_raw` and `patterns.zero_based_int_raw`
  — one source of truth for the integer ABNF across the codebase.
  The deeper `rfc8866_nonzero_real` and friends continue to
  reference these V-rules via `V"…"` for grammar composition.

  **st2110.lua sweep.** All 6 affected validators rewritten to use
  the shared patterns; the `make_pixel_dim_validator` factory
  removed (replaced by a plain `validate_pixel_dim`). Wins:

  - 4 fewer closure allocations at module load.
  - 7 inline pattern strings collapsed to named constants with
    one source of truth.
  - Stricter than the old `^%d+$`: rejects leading zeros (e.g.
    "0010" was previously accepted as a width).
  - Stricter than the old `^(%d+)/(%d+)$` for exactframerate:
    "0/0" and similar zero-denominator forms now rejected at the
    pattern layer (the `n == 0 or d == 0` check was redundant
    once `pos_int_raw` excluded zero-starting strings).

  Validators sharing the same patterns: `validate_pixel_dim`
  (width / height ≤ 32767), `validate_maxudp` (1..8960),
  `validate_positive_integer` (jxsv), `validate_integer` (jxsv
  CMAX — any signed integer), `validate_exactframerate` (fraction
  or integer fallback), `validate_par` (W:H ratio).

  21 new tests in `spec/grammar_patterns_spec.lua`: per-pattern
  accept / reject matrix covering the LPeg behavior, the `vs.
  tonumber` trap cases (hex / scientific / signs / whitespace),
  the leading-zero rejection, and the captures returned by
  `fraction` and `ratio`. Suite: 1567 green (up from 1546).

  Forward-compat: Phase 7 IPMX validators get these patterns for
  free via `require("parse_sdp.grammar.patterns")`. The shared
  module also gives any future TR-10 / IPMX rule-table the same
  hoisted `rfc8866_pos_int_raw` etc. that base.lua now references.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.J; RFC 8866 §9 ABNF
verified for the integer / zero-based-integer grammar.

- **Phase 6.K:** `media_section` Cmt infrastructure + per-block
  check migrations + diagnostic field_path recovery.

  Two long-standing infrastructure gaps closed in one slice.

  **Gap 1 — no `media_section` Cmt slot.** Several checks
  (check_dynamic_pt_rtpmap, the per-media half of
  check_tsrefclk_traceability, check_rtpmap_requires_fmtp,
  check_mediaclk_presence, check_audio_packet_payload_fit) were
  per-media-block but sat in `semantic_checks` (a doc-walk slot)
  because there was no per-block Cmt slot to migrate them to.
  Phase 6.K adds the slot:
  - `parse_sdp/grammar/base.lua` `media_section` rule wrapped in
    two Cmts: a leading one increments `ctx.media_index`
    (0-indexed, matching 6.D/6.E); a trailing one dispatches every
    function in `ctx.media_section_checks` against the captured
    block.
  - `M.media_section_checks` is a new export slot parallel to
    `M.semantic_checks`. `extend()` merges
    `overrides.media_section_checks` into the child tier the same
    way as `semantic_checks`.
  - `make_match` threads each grammar's check list via
    `ctx.media_section_checks` so the rule can be shared without
    per-tier rebuild.

  **Gap 2 — in-grammar findings lost `media[N]` field_path.**
  Since Phase 6.F, per-fmtp / per-rtpmap findings emitted with no
  field_path, falling back to line/col only. Now that
  `ctx.media_index` is reliably set by the media_section Cmt,
  every in-grammar Cmt threads a constructed
  `media[N].attributes[<attr>:pt=<PT>]` field_path through to
  `errors.record`. Touched: `fmtp_dispatch` (constructs the path
  once, passes as 4th positional arg to each check); 9 per-fmtp
  check functions (raw / jxsv / audio / -41) updated to receive
  and propagate `field_path`; 8 cross-param helpers
  (raw + jxsv) updated similarly; the AM824 rtpmap
  channels-required and channels-even Cmts read `ctx.media_index`
  directly.

  **5 checks migrated** from `semantic_checks` to
  `media_section_checks`:
  - `check_dynamic_pt_rtpmap` (base)
  - `check_media_tsrefclk_traceability` (base, split out of
    `check_tsrefclk_traceability`; the session-level pass
    becomes `check_session_tsrefclk_traceability` and stays a
    `semantic_check`)
  - `check_rtpmap_requires_fmtp` (st2110 — the 6.F bridge check
    that was always meant to live in a `media_section` Cmt)
  - `check_mediaclk_presence` (st2110)
  - `check_audio_packet_payload_fit` (st2110)

  `semantic_checks` is now strictly cross-section invariants:
  - base: `check_mid_uniqueness`,
    `check_group_attribute_invariants`,
    `check_session_tsrefclk_traceability`
  - st2110: `check_ts_refclk_presence` (session-level cover
    semantics), `check_group_dup_coherence` (cross-media-block)

  **`errors.format` now emits BOTH field_path AND line/col when
  both are present** (was `elseif` before, only one shown).
  field_path = doc-shape coordinates; line/col = text coordinates.
  Different questions, both useful. Also fixed a pre-existing bug
  surfaced by the dual-display: `loc.context` is overloaded —
  legacy 1.0 callers set it to the source-line string for the
  `N | <line>` highlight block, but newer in-grammar Cmts set it
  to a metadata table like `{encoding = "L24"}` for downstream
  JSON consumers. The format now renders the highlight only when
  context is a string (legacy use); a table context flows into the
  JSON output but doesn't get stringified into the formatted
  error.

  **Behavioral change**: doc-walk emissions for `media[N]` are now
  0-indexed (matching the convention in 6.D / 6.E / new in-grammar
  paths) instead of 1-indexed. Two existing tests in
  `spec/grammar_base_spec.lua` updated to match — the field_path
  assertions for `check_dynamic_pt_rtpmap` and
  `check_media_tsrefclk_traceability` changed by `-1`.

  Diagnostic output, before / after for a per-fmtp finding:

  ```text
  -- Before 6.K (in-grammar finding):
  error: [MISSING_FIELD] fmtp 'sampling' invalid value
   --> line 8, col 127
    = note: required by ST 2110-20:2022 §7.2

  -- After 6.K (multi-block SDP, second media block is audio):
  error: [INVALID_VALUE] MAXUDP must not be signaled on L16 / L24 …
   --> field: media[1].attributes[fmtp:pt=96]
         at line 14, col 51
    = note: required by ST 2110-30:2025 §6.2.1
  ```

  2 new tests in `spec/errors_spec.lua` covering the dual-display
  emission and the metadata-table-context skip. Suite: 1569 green
  (up from 1567).

  Phase 7 (IPMX) inherits the `media_section_checks` slot — any
  per-block IPMX check (TR-10 profile presence, NMOS-adjacent
  layered constraints) drops into `overrides.media_section_checks`
  and gets the same in-grammar dispatch + field_path + pos
  plumbing for free.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.K.

- **Phase 6.L:** `validate_channel_order` LPeg sweep — last of the
  inline-regex validators in `parse_sdp/grammar/st2110.lua`.

  Same anti-pattern as the Phase 6.J validator sweep, applied to the
  one validator that 6.J missed: 5 inline `string.match` / `gmatch`
  calls implementing ST 2110-30 §6.2.2 + ST 2110-31 §6.2 Table 2 +
  RFC 3190 channel-order syntax. Replaced with a small LPeg grammar
  that captures the group symbols and dispatches the
  AES3-on-AM824 cross-encoding check in Lua (the only piece that
  can't live in the grammar — it depends on a runtime argument).

  The new grammar is exactly the spec's syntax:

  ```text
  channel_order = convention "." order
  -- For SMPTE2110:
  order   = "(" group *("," group) ")"
  group   = "M" | "DM" | "ST" | "LtRt" | "51" | "71" | "222"
          | "SGRP"     ; ST 2110-30 §6.2.2 Table 1
          | "AES3"     ; ST 2110-31 §6.2 Table 2 (AM824 only)
          | "U" Udd    ; Undefined group (Udd = 01..64)
  Udd     = "0"[1-9] | [1-5][0-9] | "6"[0-4]
  ```

  Wins:

  - 5 inline `string.match` / `gmatch` calls collapsed.
  - The Udd range check (01..64) is now enforced by pure pattern
    algebra (the three sub-ranges as an ordered choice) instead of
    a separate `tonumber` + `>= 1 and <= 64` check.
  - Stricter than the old `gmatch` + `^%s*(.-)%s*$` trim loop:
    no whitespace allowed inside the `(...)` parens, matching the
    literal form in the §6.2.2 examples (`SMPTE2110.(51,ST)`).
    No existing tests used internal whitespace, so the strictness
    bump is a free spec-correctness gain.
  - `AUDIO_CHANNEL_GROUPS` constant table deleted — the symbol set
    is enumerated inline in the LPeg pattern (single source of
    truth, ordered-choice friendly: longer prefixes first so
    `"DM"` doesn't get pre-empted by `"M"`).

  Net file size change: minor; the LPeg pattern is denser than the
  match-loop it replaces but adds explanatory grammar comments.

  Suite unchanged at 1569 green — accept / reject set preserved.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.L; [[lpeg-discipline]].

The grammar tier now matches 1.0 parity on every well-grounded
per-encoding required-attribute and cross-attribute SHALL. Three
out-of-parity flags carry forward for separate audit follow-up:

1. 1.0 enforces MAXUDP-forbidden on AM824 (no -31 SHALL grounds it)
2. 1.0 enforces channels-required on L16/L24 (no -30 SHALL grounds it)
3. 1.0 enforces packet-payload-fit on AM824 (no -31 SHALL grounds it)

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 6.D; ST 2110-30:2025 §6.2.1 +
ST 2110-10:2022 §6.4 + RFC 3550 §5.1 + AES67-2013 §8.1.

- **Phase 7.A:** IPMX grammar composition shell. New
  `parse_sdp/grammar/ipmx.lua` chains st2110 via
  `st2110.extend(st2110, {})` — same compile-time composition
  mechanism Phase 6.A established for ST 2110-over-base, now
  applied for IPMX-over-ST-2110. Internal entry point only;
  `sdp.parse(text, "ipmx")` remains on the 1.0 path until Phase 9.
  6 new composition-parity tests in
  `spec/grammar_compose_spec.lua` (shape, accept/reject parity with
  st2110, `semantic_checks` + `media_section_checks` inheritance
  ordering, distinct table identity). Suite: 1575 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.A.

- **Phase 7.B:** TR-10-1 §10 baseline ("this SDP is IPMX") — `a=group:FID`
  prohibition + per-RTP-block `a=fmtp` IPMX marker requirement.

  §10 forbids `a=group:FID`; §10.1 requires the `IPMX` token in
  `a=fmtp` on every RTP media block. 2 new error ids
  `tr-10-1.a.group.fid-forbidden` and
  `tr-10-1.a.fmtp.marker-required`. The FID prohibition lands as
  an in-grammar override of base's `a_group` rule (trailing Cmt
  reads `Cb"semantics"` and emits the finding when the value is
  "FID"); the fmtp marker check lands in `media_section_checks`
  (per-RTP-block).

  Phase 7.B also introduced `base.is_rtp_block(block)` — an
  LPeg-driven `proto = "RTP" / "RTP/..."` predicate that replaces
  the pre-existing `block.proto:find("RTP", 1, true)`
  string-library calls in base.lua's `check_dynamic_pt_rtpmap`
  and the new IPMX checks (keeps the codebase inside the parser
  per [[lpeg-discipline]]).

  New `spec/grammar_ipmx_spec.lua` with topical TR-10-1 §10 /
  §10.1 describe blocks. Suite: 1586 green after the initial
  slice.

  **Re-verified to literal spec text on review** (one of three
  earlier non-parity flags reconciled at Phase 7 close): §10.1
  reads "IPMX Senders shall include the ' IPMX' declaration in
  the a=fmtp clause of the SDP file" — singular "the a=fmtp
  clause", no "every". The check now fires per RTP block only
  when at-least-one a=fmtp is present AND none of them carries
  the IPMX flag; `field_path` is block-level (no `:pt=N` suffix).
  Earlier "audit-folder follow-up" language was a misread of the
  SHALL and has been removed.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.B; TR-10-1 §10 + §10.1.

- **Phase 7.C:** TR-10-1 §10.2 (extended by TR-10-9 §10) IPMX video fmtp
  required parameters — `measuredpixclk`, `vtotal`, `htotal`.

  Every RTP video block's `a=fmtp` must carry these three keys
  as positive integers (RFC 8866 §9 ABNF `POS-DIGIT *DIGIT` via
  `patterns.pos_int:match`). 6 new error ids
  (`tr-10-1.a.fmtp.<key>-required` and `<key>-invalid-value` for
  each of the three keys). Wired via a new
  `ipmx_fmtp_dispatch` that chains after st2110's per-encoding
  dispatch on the `a_fmtp` rule; `IPMX_FMTP_CHECKS_BY_ENCODING`
  keys raw + jxsv to the IPMX video check function (TR-10-2 §7
  / TR-10-11 §7 inheritance).

  Single-walk merged-function refactor of
  `check_ipmx_video_fmtp` (combines presence and value-form
  checks into one walk per key, per the user's DRY pushback).
  18 new tests; suite: 1604 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.C; TR-10-1 §10.2 +
TR-10-9 §10; TR-10-2 §7 + TR-10-11 §7.

- **Phase 7.D:** TR-10-1 §10.3 (extended by TR-10-9 §10) IPMX audio fmtp
  required parameter — `measuredsamplerate`.

  Every RTP audio block's `a=fmtp` must carry
  `measuredsamplerate` as a positive integer. 2 new error ids
  `tr-10-1.a.fmtp.measuredsamplerate-required` /
  `-invalid-value`. `IPMX_FMTP_CHECKS_BY_ENCODING` also keys L16
  / L24 / AM824 to `check_ipmx_audio_fmtp`. 10 new tests; suite:
  1614 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.D; TR-10-1 §10.3 +
TR-10-9 §10.

- **Phase 7.E:** TR-10-2/-3/-4/-11/-12 §7 IPMX RTP UDP port constraints —
  port MUST be even AND > 1024.

  2 new error ids `ipmx.m.port-must-be-even` and
  `ipmx.m.port-must-exceed-1024`. New per-block
  `check_ipmx_port_constraints` in `media_section_checks`, gated
  by `is_rtp_block` (USB / non-RTP transport blocks don't trip
  the RTP port constraints). 8 new tests; suite: 1622 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.E; TR-10-2 §7 + TR-10-3
§7 + TR-10-4 §7 + TR-10-11 §7 + TR-10-12 §7.

- **Phase 7.F:** ST 2110-22:2022 §7.3 jxsv `b=AS:<kbps>` requirement —
  per-jxsv-block bandwidth attribute presence + value form.

  Every jxsv media block MUST carry `b=AS` with brvalue a
  positive integer (RFC 8866 §9 ABNF `integer`). 2 new error ids
  `st2110-22.b.as-required` / `as-invalid-value`. New per-block
  `check_jxsv_bandwidth` in `media_section_checks`,
  encoding-gated on rtpmap `jxsv`.

  **Placement-correction on review** (one of three earlier
  non-parity flags reconciled at Phase 7 close): the check lives
  at the **ST 2110 tier**, not the IPMX tier. §7.3 authors the
  SHALL — "The media-level section of the SDP object shall
  include the attribute listed in Table 3" — and TR-10-7 §11
  substitutes only the Table 3 row's cell semantics (changes
  brvalue from "average" to "maximum target bit rate"). The
  wrapping presence SHALL is unchanged and inherited via
  composition by the IPMX tier. The initial slice put the check
  at the IPMX tier matching 1.0's placement; but the 1.0
  placement conflated 1.0's monolithic file structure with spec
  authorship. Per CLAUDE.md's `spec_ref` ↔ tier-prefix
  invariant, the check belongs where the spec authors it.

  Phase 6 jxsv test fixtures retro-fitted with `b=AS` (build
  helpers in `spec/grammar_st2110_spec.lua` add
  `b=AS:1500000` whenever the rtpmap encoding is jxsv, via an
  LPeg substring match). New `b=AS` describe block topically
  placed next to the jxsv rtpmap-narrowing block. 6 new ST 2110
  tests (8 IPMX tests were removed when the IPMX-tier mirror was
  deleted); suite: 1710 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.F; ST 2110-22:2022 §7.3;
TR-10-7 §11.

- **Phase 7.G:** TR-10-10 §8 `a=infoframe` HDMI InfoFrame signaling
  attribute.

  Adds `a_tier_extensions` and `tier_attr_names` hooks to
  base.lua's `a_value` alternation and `known_attr_lookahead`
  (default `P(false)` — never matches; tiers override to add new
  attributes without redeclaring the alternations). IPMX
  overrides add the new `a_infoframe` rule that parses
  `<port> SSN=<ssn>;DIT=<dit>` and validates: session-level
  only, SSN matches `ST2110-41:<year>`, DIT equals literally
  "100100". Cross-section `semantic_check` verifies port equals
  some media port + 3 and ports are unique. 5 new error ids;
  10 new tests; suite: 1639 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.G; TR-10-10 §8.

- **Phase 7.H:** TR-10-5 §10 `a=hkep` HDCP Key Exchange Protocol attribute.

  New `a_hkep` rule parses
  `<port> <nettype> <addrtype> <addr> <node-id> <port-id>` with
  in-grammar Cmt validating: nettype = "IN", addrtype ∈ {IP4,
  IP6}, node-id is `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (32
  hex digits in 5 groups, anchored LPeg pattern), port-id is
  `xx-xx-xx-xx-xx` (10 hex digits in 5 pairs). Accepts session-
  and media-level per TR-10-5 §17; addr syntax not validated per
  TR-10-5 §10. 4 new error ids; 11 new tests; suite: 1650 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.H; TR-10-5 §10 + §17.

- **Phase 7.I:** TR-10-6 §7.6 FEC parameter signaling in `a=fmtp` —
  `FECPROFILE` value-set narrowing + `FEC_ADD_LATENCY_*` cross-parameter
  dependency.

  `FECPROFILE` value MUST be `profile-a` when present;
  `FEC_ADD_LATENCY_VIDEO` / `FEC_ADD_LATENCY_AUDIO` (when
  present) MUST (a) have a non-negative integer value and (b)
  require `FECPROFILE` to also be present. New
  `IPMX_FMTP_UNIVERSAL_CHECKS` slot in the IPMX fmtp dispatch —
  encoding-agnostic checks that run on every RTP fmtp
  regardless of rtpmap encoding. New `zero_based_int` export in
  `patterns.lua` for the non-negative integer validation. 5 new
  error ids; 12 new tests; suite: 1662 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.I; TR-10-6 §7.6.

- **Phase 7.J:** TR-10-13 §13 `a=privacy` attribute — required parameters,
  value forms, and enum narrowing.

  New `a_privacy` rule parses the
  `<key>=<value>; <key>=<value>; ...` kv-list and a trailing
  Cmt validates: 6 required params present (protocol, mode, iv,
  key_generator, key_version, key_id), no trailing semicolon,
  `protocol != "NULL"` (§13 line 352), `mode` in the 12-value
  TR-10-13 §20.1 enum (subsumes the NULL-mode prohibition since
  NULL is outside the enum), and per-key hex form/length checks
  (iv = 16, key_generator = 32, key_version = 8, key_id = 16 hex
  digits — all anchored LPeg patterns built from a
  `HEX^n * P(-1)` helper). 13 new error ids; 32 new tests;
  suite: 1694 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.J; TR-10-13 §13 + §20.1.

- **Phase 7.K:** TR-10-13 §20.1 `a=extmap` direction for PEP IV-Counter
  URNs — direction MUST equal `sendonly`.

  New `semantic_check` verifies that when an `a=extmap` URI is
  one of the PEP IV-Counter URNs (full / short), its direction
  MUST equal `sendonly`. Implemented as a post-parse doc walk
  rather than in-grammar: base's `a_extmap` rule wraps
  `direction` in an optional Cg, so a Cb back-reference inside
  a trailing Cmt would raise "back reference not found" when
  the optional didn't fire. The doc walk reads `attr.direction`
  cleanly (nil when absent). 1 new error id; 8 new tests;
  suite: 1702 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.K; TR-10-13 §20.1.

- **Phase 7.L:** TR-10-14 §14 USB transport block (`m=application TCP
  usb`) constraints.

  New `is_usb_block(block)` helper in base.lua
  (LPeg/structural — matches the literal proto triple). New
  `media_section_check` `check_usb_block` validates: `a=setup`
  is present (RFC 4145 §3 via TR-10-14 §14 line 724) and equals
  "passive" (line 740), and when `a=privacy` is present its
  `protocol` parameter equals `USB_KV` (line 736). 3 new error
  ids. Also gates the ST 2110 `ts-refclk-required` and
  `mediaclk-required` checks on `is_rtp_block` so non-RTP USB
  blocks don't spuriously trip RTP-specific timing-attribute
  SHALLs.

  **Intentional non-parity flag re-verified on review** (one of
  three earlier non-parity flags reconciled at Phase 7 close):
  TR-10-14 §14 says "follow RFC 4145 with the following
  restrictions" and enumerates the restrictions ("media space
  port set to 'application/usb'", "'role' of 'setup' shall be
  'passive'", privacy "protocol : USB_KV"). It does NOT say
  `rtpmap`, `fmtp`, `mediaclk`, or `ts-refclk` are forbidden on
  USB blocks — the 1.0 validator's "RFC 4145 doesn't use
  RTP-specific attributes" reasoning is interpretation, not
  spec text. Per CLAUDE.md's strictness principle, the grammar
  tier does not enforce that prohibition; 1.0's
  forbidden-attribute check is documented as a 1.0-over-strict
  audit-folder follow-up rather than ported.

  9 new tests; suite: 1711 green.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 7.L; TR-10-14 §14;
RFC 4145 §3.

**Phase 7 closed (A–L).** Grammar tier covers every SDP-touching
SHALL the 1.0 IPMX validator enforces that is grounded in primary
TR-10 / ST 2110-22 spec text. Three earlier "non-parity flags"
(7.B, 7.F, 7.L above) were re-verified against the primary spec
text on review and either reconciled (7.B over-strict reading
corrected; 7.F placement moved to authoring tier) or documented
as 1.0-over-strict (7.L). Two DRY cleanups also landed during
Phase 7: the `check_*_fmtp_required` + `_values` function pairs
in ST 2110 (raw_video and jxsv) and IPMX (video and audio) were
merged into single-walk functions per the user's "neat and tidy"
pushback. Final test count: 1711 green.

- **Phase 8.A:** serializer rewrite — bootstrap shell.
  `parse_sdp/serialize.lua` is the new structure-walking serializer; it
  reads the grammar tier's decomposed doc shape and emits RFC 8866 text,
  rather than echoing stored attribute-value strings the way the 1.0
  serializer does. 8.A scope is the minimum compelling slice: v / o / s /
  t (bare t= blocks; r= repeats and z= time zones defer to 8.B). Optional
  session-level fields, media blocks, and per-attribute renderers come in
  later 8.B–8.E slices.

  The producer-side contract — *Serializer never validates. Validate never
  serializes.* — is established here and documented in
  [CLAUDE.md](CLAUDE.md#things-to-watch-out-for): `to_sdp` errors only on
  missing-required fields (the ones the spec's ABNF marks as mandatory),
  emits faithfully otherwise. Value-form correctness and cross-section
  invariants live in `doc:validate`. A developer can build a doc piecemeal,
  render at any point to see structural gaps, and validate when they think
  they're done.

  New `spec/roundtrip_spec.lua` does parse → serialize → parse → deep-equal
  via `parse_sdp.grammar.base.match`. 11 new tests. Public API stays on
  the 1.0 serializer until Phase 9 cutover; `parse_sdp.serialize` is
  internal-only for the rest of Phase 8. Suite: 1721 green (up from 1710).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 8.A.

- **Phase 8.B:** serializer base SDP optional fields, repeats, time zones,
  generic / flag attributes, and media blocks.

  Adds renderers for every RFC 8866 §5 field not in 8.A's bootstrap scope:
  session-level `i`, `u`, `e*`, `p*`, `c`, `b*`; `r=` repeat-time inside
  each time-description; `z=` time-zone-adjustments; session- and
  media-level `a=` attributes via a new `ATTR_RENDERERS` dispatch table
  (populated empty — 8.D / 8.E fill in the decomposed-attribute renderers);
  media blocks with `m`, optional `port_count`, multiple fmts, and the
  optional per-block `i` / `c` / `b*` / `a*` sub-fields. RFC 8866 §5
  ordering is enforced by the order of the calls in `M.to_sdp(doc)`.

  Compound attribute names (rtpmap, fmtp, mid, ts-refclk, mediaclk,
  source-filter, group, ssrc, ssrc-group, msid, extmap, rtcp-fb, rtcp,
  rtcp-mux, ptime, maxptime, framerate, quality) still fall through to
  the generic `{name, value?}` carrier in 8.B; some round-trip "by
  accident" because their decomposed shape (a number-typed `value`)
  happens to match the carrier, others (mid, rtpmap, fmtp, …) cannot
  yet round-trip and are deliberately not in 8.B's fixture set. 8.D
  registers per-name renderers in `ATTR_RENDERERS` to close that gap.

  21 new tests in `spec/roundtrip_spec.lua` covering: full session
  round-trip with all optional session fields; multiple `e=` / `p=` /
  `b=` lines preserving order; multiple `t=` blocks; `r=` repeats in
  both numeric (`604800 3600 0 90000`) and typed-time (`7d 1h 0 25h`)
  forms; multi-`r=` per `t=` block; `z=` with one and multiple pairs;
  session-level flag attributes (`recvonly` / `sendonly` / `inactive` /
  `sendrecv`) and generic `name:value` attributes (`tool` / `type` /
  `charset` / `sdplang` / `lang`); attribute order preservation; media
  blocks with all optional fields; `m=` with `port_count` (`49170/2`);
  multi-fmts on `m=` (`0 8 9` static PTs); multiple media blocks
  preserving order. Plus structural-completeness errors for missing
  `m.media`, empty `m.fmts`, missing `r.offsets`, missing `b.type`,
  missing `c.address`. Fixtures use static PTs (≤95) only so the
  grammar's `check_dynamic_pt_rtpmap` doesn't trip — dynamic-PT
  fixtures land in 8.D once `a=rtpmap` decomposes via
  `ATTR_RENDERERS`.

  Suite: 1742 green (up from 1721).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 8.B.

- **Phase 8.C:** fmtp params shape change — hash → ordered list, with a
  single `base.params_get(params, key)` lookup helper.

  Grammar-tier change: `a_fmtp`'s decomposable branch (both base.lua's
  `fmtp_params_branch` and st2110.lua's `fmtp_st2110_raw_params` override)
  now captures `params` as an ordered Ct of `{key, value | true}` sub-
  tables — the same shape `a=privacy` has used since 7.J. Input key
  order is preserved, which is the prerequisite for the serializer's
  text-identical round-trip on fmtp lines (Phase 8.D / 8.F).

  The earlier `fmtp_entries_to_params` postprocessor that flattened the
  capture into a key→value hash is gone, as is its `M.` export. In its
  place: `base.params_get(params, key)` returns the value for `key`
  (string for k=v entries, `true` for bare flags, nil for absent).
  Threaded through `base.extend` so child tiers inherit it as
  `<tier>.params_get`. Single source of truth for every consumer that
  needs a by-key read off either an fmtp or a privacy params list.

  44 consumer sites updated to the helper across the codebase:
  `parse_sdp/grammar/st2110.lua` (27 sites across 14 functions —
  `check_raw_video_fmtp`, `check_ssn_conditional`, `check_bt2100_range`,
  `check_segmented_requires_interlace`, `check_bpm_forbids_maxudp`,
  `check_key_sampling`, `check_420_progressive_only`,
  `check_420_depth_restricted`, `check_tcs_floating_point_depth`,
  `check_jxsv_segmented_requires_interlace`, `check_jxsv_bt2100_range`,
  `check_st2110_41_fmtp`, `check_audio_maxudp_forbidden`,
  `check_audio_fmtp_channel_order`, `check_jxsv_fmtp`);
  `parse_sdp/grammar/ipmx.lua` (6 sites in `check_ipmx_fmtp_marker`,
  `check_ipmx_video_fmtp`, `check_ipmx_audio_fmtp`,
  `check_ipmx_fec_params`); `spec/grammar_base_spec.lua` (11
  assertion sites in the fmtp-decomposition tests). Privacy code
  (`a_privacy` / `check_a_privacy` / `check_usb_block`) was already on
  the ordered-list shape and stayed untouched. Lookup tables that
  happen to live alongside params consumers
  (`RAW_VIDEO_ENUM_VALUES[key][val]`, `FMTP_REQUIRED_BY_ENCODING[enc]`,
  `RAW_VIDEO_VALUE_VALIDATORS[key]`, etc.) keep their hash shape — they
  are not params captures.

  `params_equal` (group:DUP fmtp comparison) rewritten to compare
  by-key via `params_get` with an `#a ~= #b` short-circuit, preserving
  its existing order-insensitive semantics — ST 2110-22 §8.5 / ST
  2022-7 §6 require packet-shape equivalence across DUP legs, not
  identical SDP textual layout.

  Pure shape refactor; no behavior change. Suite: 1742 green
  (unchanged).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 8.C.

- **Phase 8.D:** base compound-attribute renderers — every base-tier
  `a_<name>` rule in `parse_sdp/grammar/base.lua` now has an inverse in
  the new `ATTR_RENDERERS` dispatch table in `parse_sdp/serialize.lua`.
  18 total entries.

  Bootstrap (rtpmap + `require_fields` helper + dispatch scaffold) landed
  first as commit `40bc802`, then three sub-slices closed the remaining
  17 renderers:

  - **8.D.1** — value-only attrs: mid, ptime, maxptime, framerate,
    quality, msid (msid_id with optional appdata), ssrc (ssrc_id and
    attribute, with optional value), rtcp-mux (flag, no required fields). 19 new tests
    in `spec/roundtrip_spec.lua`; suite 1767 green (was 1748).
  - **8.D.2** — RTP-stack attrs: fmtp, rtcp, rtcp-fb, extmap, ssrc-group.
    The fmtp renderer is the critical one — walks `attr.params` (the
    ordered Ct from 8.C) positionally so decomposed-kv round-trip is
    text-identical (`profile-level-id=42801f;max-mbps=108000;max-fs=3600`
    renders byte-for-byte), falls through to `attr.raw` for opaque
    byte-strings (DTMF telephone-event form). rtcp enforces the
    all-or-nothing optional `net_type+addr_type+address` triple via
    `require_fields`. rtcp-fb handles polymorphic `payload_type` (number
    or literal `"*"`) via `tostring`. 21 new tests; suite 1788 green.
  - **8.D.3** — clock + grouping: ts-refclk, mediaclk, group,
    source-filter. ts-refclk and mediaclk both have branch-specific
    field sets; the renderers dispatch on `attr.source` / `attr.mode` via
    small `TSR_BUILDERS` / `MC_BUILDERS` tables to per-branch builders,
    with `BUILDERS[key] or build_ext` as the ext-form fallback idiom.
    Each branch builder owns its own required-field set. group emits
    semantics + zero-or-more tags per RFC 5888 §5. source-filter requires
    all five Cg fields (filter_mode, net_type, addr_type, dest_address,
    src_addresses with ≥1 element). 29 new tests; suite 1817 green.

  The renderer contract (established by rtpmap + the bootstrap) holds
  throughout: required fields error early via `require_fields` (one
  helper call replaces the per-required-field early-return ladder),
  optional fields silently omitted when absent, no fallback to legacy
  `attr.value` string shape on known-decomposed names — the decomposed
  shape is the only producer surface for known attributes (generic /
  unknown names keep the `{name, value?}` carrier).

  Suite total: 1817 green (up from 1748 at Phase 8.C close). 69 new
  round-trip tests across the four 8.D commits.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 8.D (incl. 8.D.1 / 8.D.2 / 8.D.3).

- **Phase 8.E:** IPMX-tier attribute renderers. Three new `ATTR_RENDERERS`
  entries in `parse_sdp/serialize.lua` cover every attribute the IPMX tier
  adds to base via `a_tier_extensions`:

  - `infoframe` — `<port> SSN=<ssn>;DIT=<dit>` per TR-10-10 §8. Required:
    port, ssn, dit.
  - `hkep` — `<port> <nettype> <addrtype> <addr> <node_id> <port_id>` per
    TR-10-5 §10. Required: all six fields. Doc-shape keys mirror the
    grammar's `Cg` names (`nettype`/`addrtype`/`addr`), distinct from the
    underscored `net_type`/`addr_type` on the c= line.
  - `privacy` — `key=value;...[;]` per TR-10-13 §13. Walks `attr.params`
    (the ordered Ct shape established for fmtp in 8.C) positionally and
    emits with `;` separators (no space). The captured `trailing_semi`
    boolean is honored so a doc that parsed a §13-malformed trailing-`;`
    line round-trips faithfully (same finding fires on the re-parse).

  Round-trip tests drive through `ipmx.match` with `fail_on_first = false`
  so the renderer-correctness exercise stays focused on doc-shape
  preservation; cross-section semantic checks (e.g. the infoframe
  port-must-match-media-plus-3 SHALL) record findings without aborting
  the match. Phase 8.F runs the full fixture suite with validation on.
  16 new tests in `spec/roundtrip_spec.lua`; suite 1833 green (was 1817).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 8.E.

- **Phase 8.F:** fixture-wide round-trip. New describe block in
  `spec/roundtrip_spec.lua` discovers every
  `examples/{generic,st2110,ipmx}/valid/*.sdp` via
  `io.popen("ls ...")` and drives each through
  `parse → serialize → re-parse → deep-equal` under its tier matcher
  (`base.match` / `st2110.match` / `ipmx.match`) with the default
  `fail_on_first = true` opts. 19 fixture tests added (5 generic +
  9 ST 2110 + 5 IPMX); suite 1852 green (was 1833). Closes Phase 8
  in full.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 8.F.

### Changed

- **Phase 9.D:** Cutover wiring — `sdp.parse(text, mode, opts)` now
  routes through the grammar tier (`base.match` / `st2110.match` /
  `ipmx.match`) instead of the 1.0 `parser.parse`; `mt:to_sdp()` routes
  through the new `parse_sdp.serialize` module; `mt:validate(mode)` /
  `mt:is_sdp/st2110/ipmx()` re-implemented as serialize-then-reparse
  against the grammar tier. The 1.0 grammar / validator / serializer
  code in `parse_sdp.lua` stays in place but is no longer reachable
  from the public API; Phase 10.A deletes it.

  Default `fail_on_first` flips to `false` for the public-API path —
  the grammar collects every finding and `sdp.parse` partitions: any
  error-severity finding surfaces as `nil, err`; warnings reach the
  caller via `doc:warnings()`. The internal tier `match(text, opts)`
  default of `fail_on_first = true` stays for spec helpers.

  Two doc-shape / strictness changes surface (documented as
  intentional per CLAUDE.md strictness):
  - The grammar tier no longer rejects SDPs with zero media blocks at
    the ST 2110 / IPMX tiers. RFC 8866 / ST 2110-10 / TR-10 do not
    explicitly forbid `#media == 0`; the 1.0 parser's cite for the
    rejection ("ST 2110-10:2022 §7") doesn't carry the SHALL on
    primary read. Joins the existing three 1.0-over-strict flags
    from Phase 6.D for audit follow-up.
  - The grammar tier enforces RFC 8866 §9 `IP4-multicast` ABNF at the
    base tier (requires `/<ttl>` suffix on multicast c= lines). The
    1.0 base parser was permissive; only its st2110 / ipmx tier
    callers invoked the check. Grammar tier is correctly stricter
    per the ABNF.

  Test triage: the four 1.0-tied spec files
  (`spec/sdp_spec.lua`, `spec/st2110_spec.lua`, `spec/ipmx_spec.lua`,
  `spec/grammar_spec.lua`) moved to `spec_legacy_1.0/`. They assert
  against the 1.0 doc shape (`session.timing.start/stop` vs the
  grammar tier's `session.time_descriptions[]`) and the 1.0-over-strict
  checks the grammar intentionally drops. Phase 10.A deletes them
  along with the 1.0 implementation. `spec/library_spec.lua` had the
  "no media → reject at st2110/ipmx" assertions removed (behavior
  change) and one JSON fixture's c= updated with the `/<ttl>` suffix.
  `spec/cli_spec.lua` had one test's fixture swapped for one that
  fails the grammar tier under a spec-grounded SHALL.

  `spec/` ends Phase 9 at 1079 green (was 1862; 783 moved to
  spec_legacy_1.0/). Grammar-tier suite is the going-forward authority.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 9.D.

- **Phase 9.C:** Public-API surface for the policy / findings feature.
  Two surface additions to `parse_sdp.lua`:
  - `sdp.parse(text, mode, opts)` now accepts an `opts` table. On
    entry every key in `opts.policy` is validated against the
    registry via `errors.validate_policy`. An unknown id (typo or
    stale config) returns `nil, err` with `err.policy_key` naming the
    offending key. Invalid severity values fail the same way. Nil opts
    behaves as before (backward-compat).
  - `doc:findings()` / `doc:warnings()` / `doc:errors()` accessors
    added on the metatable. Findings live in a weak-keyed side table
    (out of `doc:to_json()` output). For `sdp.new()` docs and
    1.0-path parses the accessors return an empty list.

  The actual cut-over of `sdp.parse` from the 1.0 parser to the
  grammar-tier `match()` happens in 9.D — at that point findings
  start populating and policy overrides apply during parsing. 9.C
  prepares the surface so 9.D is just a routing flip.

  10 new tests in `spec/library_spec.lua`. Suite 1862 green (was 1852).

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 9.C.

- **Phase 9.B:** Comment-tightening sweep across the new grammar tier,
  serializer, and errors module. Removed paraphrase comments,
  "Phase N: did X" inline annotations whose history is now in
  REFACTOR-PLAN, and module-header Phase X.Y enumerated lists.
  Preserved the three named load-bearing blocks (fmtp accumulator
  dissolution; the LPeg V-rule sharing pitfall in `base.extend`; the
  rtpmap-before-fmtp ordering caveat in 6.C.B) verbatim, plus every
  per-spec citation. Suite unchanged at 1852 green. Net delta: -188
  lines across `base.lua`, `st2110.lua`, `ipmx.lua`, `serialize.lua`,
  `errors.lua`.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 9.B.

- **Phase 9.A:** DRY sweep across the grammar tier and spec helpers. No
  behavior change; suite unchanged at 1852 green.
  - `parse_sdp/grammar/ipmx.lua` `check_usb_block` now uses
    `base.params_get(privacy.params, "protocol")` instead of an inline
    linear scan (missed reuse of the existing primitive).
  - `parse_sdp/grammar/st2110.lua` merged `media_block_has_attr` +
    `session_has_attr` into one `has_attr(attrs, name)` taking the attrs
    list directly.
  - `parse_sdp/grammar/st2110.lua` extracted a
    `make_param_check(predicate, error_id)` factory. The four raw + jxsv
    cross-param check functions (`check_(jxsv_)?bt2100_range`,
    `check_(jxsv_)?segmented_requires_interlace`) collapse to two named
    predicates plus four factory invocations; the registered error IDs
    keep -20 vs -22 spec authorship visible.
  - New `spec/support.lua` carries shared spec helpers: `finding_for(ctx, id)`
    (was duplicated in 3 spec files) and the `TIMING_TS_REFCLK` /
    `TIMING_MEDIACLK` fixture constants (in 2). `grammar_base_spec.lua`,
    `grammar_st2110_spec.lua`, and `grammar_ipmx_spec.lua` now alias the
    support exports.

  Net delta: -31 lines across the grammar modules and three spec files;
  +32 lines for the new `spec/support.lua` module.

Audit ref: audits/REFACTOR-PLAN.md §5 Phase 9.A.

- The inline `errors` table in `parse_sdp.lua` now delegates to
  `parse_sdp.errors`. Error struct shape, `errors.new()` signature, and
  `errors.format()` output are byte-identical to 1.0. Internal-only;
  no caller-visible change.
- **All `spec_ref` citations migrated from RFC 4566 to RFC 8866**
  (RFC 8866 obsoletes RFC 4566). Section numbers verified against the
  on-disk RFC 8866 text and updated where 8866 introduces finer
  subsections — fmtp cites now point to §6.15, framerate cites to §6.13,
  rtpmap to §6.6. Test assertions and citation-label test names updated
  to match.
- **All RFC 4566 prose / docstring / comment / CLI-help references
  migrated to RFC 8866** (file headers, public-API docstrings,
  examples runner, test descriptions, spec_conformance comments).
  Two SMPTE spec quotes (ST 2110-10 §6.2 in parse_sdp.lua, ST
  2110-41:2024 §5.3 in spec/st2110_spec.lua) keep "IETF RFC 4566"
  verbatim because that's what the SMPTE text says; the rockspec's
  "RFC 8866 obsoletes RFC 4566" historical note also stays.

### Fixed

- **`a=source-filter` grammar required no SP between `:` and the
  filter-mode token** (Phase 8.F triage). RFC 4570 Appendix A
  defines the ABNF as
  `"source-filter" ":" SP filter-mode SP filter-spec` — the SP after
  the colon is part of the grammar, not optional. Updated
  `parse_sdp/grammar/base.lua` `a_source_filter` to insert `* SP`
  immediately after `P("source-filter:")`. Updated
  `parse_sdp/serialize.lua` to emit the SP between `source-filter:`
  and the filter-mode token
  so the renderer matches the ABNF. 12 existing test inputs across
  `spec/grammar_base_spec.lua` (4), `spec/grammar_st2110_spec.lua`
  (4), and `spec/roundtrip_spec.lua` (8 — 4 input strings + 4
  expected-output strings) updated to the SP form. The 1.0 parser
  at `parse_sdp.lua:802` accepts both forms via `P(" ")^-1` with
  a comment ("Some senders include a leading space after the `:`
  — accept it"); the grammar-tier port removes that opinion-based
  loosening per CLAUDE.md's strictness principle. Surfaced by every
  IPMX fixture in Phase 8.F (all of which write the
  spec-conformant SP form).

- **Three fixture files used `m=application` for `smpte291` ANC
  streams** (Phase 8.F triage). RFC 8331 §4 reads, verbatim:
  *"The type name ("video") goes in SDP "m=" as the media name."*
  The new grammar tier's `st2110-40.a.rtpmap.smpte291-media-type`
  check (and the 1.0 parser at `parse_sdp.lua:1617-1624`) reject
  the construction. Fixed by changing the `m=` media name from
  `application` to `video` (port + PT + rest of the block
  unchanged):
  - `examples/st2110/valid/05_typical_multistream.sdp` — 1 block
    (port 10020).
  - `examples/st2110/valid/06_pathological.sdp` — 2 blocks
    (ports 22000, 22002).
  - `examples/ipmx/valid/03_pathological.sdp` — 1 block
    (port 32000).

- **Audio `a=ptime` `spec_ref` audit completeness.** The shipping parser's
  `a=ptime`-missing and `a=ptime`-invalid checks previously reported
  `spec_ref = "ST 2110-30:2025 §6.2.1"` only, while the message text
  named both ST 2110-30:2025 §6.2.1 and AES67 §8.1. Audit row 38
  (ptime presence SHALL) and row 39 (Table 1 value SHALL) in
  `audits/SPEC_COVERAGE.md` cite all the normatively-applicable
  clauses; the parser's `spec_ref` now matches.
  - PCM audio (L16 / L24): `spec_ref = "ST 2110-30:2025 §6.2.1 / AES67 §8.1"`
    — ST 2110-30 chains to AES67 for the SDP SHALL; AES67 §8.1 is
    where the actual ptime SHALL lives.
  - AM824 audio: `spec_ref = "ST 2110-30:2025 §6.2.1 / AES67 §8.1 / ST 2110-31:2022 §6.1"`
    — ST 2110-31:2022 §6.1 *also* SHALL-requires ptime
    (*"Senders under this standard shall signal a ptime attribute in
    the SDP"*) and additionally constrains the value to Table 1.
    Both clauses apply jointly; the cite now enumerates all three.
  Two existing spec_ref assertions updated to the new combined cite:
  `spec/st2110_spec.lua` ptime=0 test, `spec/ipmx_spec.lua` D1 cite
  test. New assertion added to the AM824-without-ptime test to lock
  in the tri-clause cite. Suite: 1259 green.

- CLAUDE.md's VSF TR-10 markdown path. It pointed to
  `smpte_standards_internal/TR-10 Markdowned Versions/`; the directory
  is at `Standards Related/TR-10 Markdowned Versions/`.

---

## [1.0.0] — 2026-05-18

First stable release. Every validation check is grounded in explicit
normative spec text; no opinion-based checks remain. Test suite split
into seven files by what each test exercises (standards / public API /
internal helpers).

### Changed

- **Base SDP spec migrated from RFC 4566 to RFC 8866.** RFC 8866
  obsoletes RFC 4566. New base-tier checks: dynamic-PT requires
  `a=rtpmap` (§8.2.3); IPv4 multicast requires `/ttl` (§5.7 / §9 ABNF);
  IPv6 multicast forbids TTL but permits `/numaddr` (§5.7 / §9); multiple
  session-level `c=` lines rejected at parse (§5.7); `k=` parsed and
  silently discarded, serializer never emits (§5.12).
- **Test suite reorganized into seven files** along a single axis —
  *what kind of code each test exercises*:
  - `spec/sdp_spec.lua` (99) — RFC 4566 / RFC 8866, 100% standards-tied
  - `spec/st2110_spec.lua` (405) — SMPTE ST 2110, 100% standards-tied
  - `spec/ipmx_spec.lua` (190) — VSF TR-10 / IPMX, 100% standards-tied
  - `spec/library_spec.lua` (42) — public API (mode dispatch, doc
    methods, `to_json`, predicate behavior, error shape)
  - `spec/cli_spec.lua` (15) — CLI subcommands
  - `spec/grammar_spec.lua` (35) — LPEG primitive parsers (white-box)
  - `spec/errors_spec.lua` (16) — error formatter (white-box)
  Non-standards `it` blocks carry an inline
  `-- NOT-SPEC: library` or `-- NOT-SPEC: implementation` marker.
- **Describe blocks within each tier file reordered atomic → complex**
  with explicit section-header comments. 4 verified duplicate
  `it` blocks removed during a dedup pass (suite 853 → 849).
- **GUIDE.md** gains a "Test Suite Organization" section documenting
  the split and the marker convention.

### Fixed

Audit Pass #31 (a spec → parser inverted-direction audit covering
~1750 normative SDP-touching clauses across 30+ specs) landed the
following parser fixes:

- **RFC 8331 / ST 2110-40 ancillary data:**
  - `DID_SDID` accepts 1 *or* 2 hex digits per `1*2(HEXDIG)` ABNF.
  - `VPID_Code` rejected when present more than once.
- **ST 2110-20 raw video:**
  - `SSN` year suffix restricted to `:2017` / `:2022`.
  - `BT2100` colorimetry restricts `RANGE` to `NARROW` / `FULL` only —
    `FULLPROTECT` rejected.
  - Whitespace around `=` rejected in raw-video fmtp.
  - `m=video` subtype must be `raw` at the ST 2110 tier.
- **ST 2110-22 JPEG-XS:** `width` / `height` upper bound 32767.
- **ST 2110-10:**
  - `TSMODE=SAMP` requires `TSDELAY` to be signaled.
  - `TSMODE` / `TSDELAY` scope hoisted to all media types.
- **RFC 5888 grouping:** any `a=group` requires every `m=` block to
  carry `a=mid`.
- **RFC 4570 source-filter:**
  - Session-level `a=source-filter` value-syntax now validated
    symmetrically with media-level.
  - `<dest-address>` in source-filter cross-checked against an
    existing `<connection-field>`, with full RFC 8866 `/numaddr`
    expansion for IPv4 and IPv6 multicast.
- **RFC 7273:** mixed traceable / non-traceable `ts-refclk` rejected
  at the same level (§4.8); value-form errors cite RFC 7273 upstream
  rather than ST 2110.
- **Citation cleanups:** RFC 5285 → RFC 8285 for `a=extmap`;
  RFC 5888 §8.1 → §4 for `a=mid` uniqueness; ST 2110-40 §7.2 → §5.3
  for clock-rate and `VPID_Code`; ST 2110-40 MAXUDP §6.1.4 → §5.2.1;
  ST 2022-7 parenthetical removed from DUP error text; year-tag
  consistency pass on ST 2110 cites.
- **AES67 audio:** `a=ptime` required for all audio at the ST 2110
  tier (was AM824-only); cite corrected to ST 2110-30:2025 §6.2.1.

### Notes

- Previous releases were 0.1.0 / 0.1.1; this release supersedes them.
- The full per-finding history (citation quotes, parser line refs,
  workflow notes) for Audit Pass #31 lived in
  `audits/PHASE3_FINDINGS.md` during development; the audit is closed.

---

## [0.1.1] — 2026-05-14

- Fix Docker CLI example in README (`parse` → `to_json`).
- Correct README stderr description (human-readable, not JSON).
- Update rockspec to `0.1.1-1` with corrected CLI subcommand names in description.

---

## [0.1.0] — 2026-05-14

Initial release.

### Features

- **Three validation tiers:** RFC 4566 (generic SDP), SMPTE ST 2110, and IPMX
  (VSF TR-10 profile). Each tier is a strict superset of the previous.
- **Spec-grounded strictness.** Every check cites an explicit "shall not" or
  well-formedness clause. Spec silence is not a reason to reject.
- **ST 2110 fmtp coverage:** video (ST 2110-20/21), JPEG-XS compressed video
  (ST 2110-22), audio (ST 2110-30), ancillary data (ST 2110-40), and fast
  metadata (ST 2110-41).
- **IPMX extensions:** HDCP Key Exchange (`a=hkep`), Privacy Encryption Protocol
  (`a=privacy`), USB transport (TR-10-14), FEC parameters (TR-10-6), HDMI
  InfoFrame (`a=infoframe`), and ST 2022-7 DUP redundancy cross-leg consistency.
- **Precise errors.** Every error carries a human-readable message, 1-based line
  and column, the offending line text, a machine-readable code, a `field_path`,
  and a `spec_ref` citing the specific clause.
- **Serialization.** `doc:to_sdp()` produces RFC 4566-compliant text with strict
  field ordering and CRLF endings. Functional round-trip is a hard invariant.
- **CLI.** `parse_sdp to_json` and `parse_sdp to_sdp` subcommands; reads from
  file or stdin.
- **666 tests** across RFC 4566, ST 2110, IPMX, error formatting, and CLI.
- **LuaRocks packaging** (`parse_sdp-0.1.0-1.rockspec`) and MIT license.
