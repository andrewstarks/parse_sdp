# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
