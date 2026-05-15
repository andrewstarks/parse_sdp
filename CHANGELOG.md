# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- **Removed spec-unsupported "a=fmtp universally required" check.** The check
  at the ST 2110 media-block level cited "ST 2110-10 §7" but §7 of the 2022
  revision is the System Timing Model, not SDP. §8 (Session Description
  Protocol) imposes no universal fmtp requirement either — fmtp presence is
  driven by the per-encoding specs (-20 / -22 / -41 require fmtp params;
  -30 / -31 / -40 do not). Per-encoding branches still enforce what they need.
- **Made `channel-order` optional in ST 2110-30 audio fmtp.** ST 2110-30:2017
  §6.2.2 explicitly defines the absent case ("If the channel-order parameter
  is not present, the audio channels shall be treated as Undefined"), so the
  parameter is optional. Format validation when present is preserved. The
  citation has been corrected from `ST 2110-30 §7.2` to `ST 2110-30 §6.2.2`.
- **Removed spec-unsupported `PM` requirement for jxsv.** ST 2110-22:2019
  §7.2 Table 1 and ST 2110-22:2022 §7.2 Table 1 both list only `width`,
  `height`, and `TP` as mandatory format-specific parameters. PM (`2110GPM` /
  `2110BPM`) is the uncompressed-video packing-mode marker defined by
  ST 2110-20; for jxsv the analogous control is `packetmode` (per IANA
  `video/jxsv` registration / RFC 9134).
- **Made `SSN` optional for jxsv.** ST 2110-22:2022 §7.2 Table 2 marks SSN
  as optional (a new addition in the 2022 revision); ST 2110-22:2019 did not
  define SSN at all. Validate format when present.
- **Expanded `VALID_TP_22` to include `2110TPN`.** ST 2110-22:2022 §7.2
  Table 1 expanded the TP enum from {`2110TPNL`, `2110TPW`} (2019) to add
  `2110TPN`. The AMWA BCP-006-01 reference SDP uses `TP=2110TPN`.
- **Made `transmode` optional for jxsv.** ST 2110-22:2022 §7.2 does not
  list transmode in either the mandatory or optional fmtp tables. IANA
  `video/jxsv` marks it optional. The IPMX JPEG-XS Video Profile §6.1.4
  references for transmode/profile/level/sublevel/fbblevel apply to the
  **RTCP Media Info Block** (type 0x0003), not SDP fmtp — and Media Info
  Blocks are out of scope for this validator per CLAUDE.md.
- **Made `DID_SDID` optional for smpte291.** ST 2110-40:2023 §7 (Session
  Description Protocol) defers to RFC 8331 and does not mention DID_SDID at
  all. RFC 8331's media-type registration marks DID_SDID optional and
  explicitly defines absence as "receivers must determine DID/SDID by
  inspecting packets." Validate format on every occurrence when present.
- **Corrected `RFC 4566 §6` citation for fmtp PT-mismatch.** The rtpmap/fmtp
  payload-type match check previously cited `ST 2110-10 §7`. The actual
  authority is RFC 4566 §6.

### Known follow-ups (parser still slightly over-strict at ST 2110 tier)

- jxsv `profile`, `level`, `sublevel` are currently required at the ST 2110
  tier. Per ST 2110-22:2022 §7.2 (only width/height/TP mandatory) and IANA
  `video/jxsv` (only `packetmode` required besides rate), these are optional
  at the SDP level. The IPMX JPEG-XS Video Profile §6.1.4 references them
  for the RTCP Media Info Block (out of validator scope), not SDP fmtp. No
  normative source requires them in SDP. Make optional at every tier.
  Deferred to keep the current change focused.

### Added

- **Opt-in conformance test suite** at `spec_conformance/`, driven against
  upstream SDP fixtures from `AMWA-TV/nmos-testing` and `AMWA-TV/bcp-006-01`,
  pinned to specific commit SHAs. Fixtures are fetched on demand into a
  gitignored `.cache/` directory; nothing upstream is checked in. The six
  templated nmos-testing fixtures are rendered through a minimal Jinja2
  subset (`spec_conformance/render.lua`) before parsing. Includes a separate
  GitHub Actions job. Run with `busted spec_conformance/`. The default
  `busted spec/` run is unchanged and stays hermetic.
- **Expected-failure semantics in the conformance suite.** Manifest entries
  may set `expect = "fail"` with `expect_spec_ref` to declare that an upstream
  fixture is known non-conformant and our parser must reject it for the
  specified clause. Used for the `nmos-testing` 2022-7 fixture, which renders
  both redundant legs with identical addressing — explicitly forbidden by
  ST 2110-10:2022 §8.5.
- **Allowlist** in `spec_conformance/allowlist.lua` for divergences that are
  open questions (parser may be over-strict, but unconfirmed against the
  primary SMPTE PDF). Two clusters remain: `PM` for jxsv (3 entries) and
  `DID_SDID` for smpte291 (1 entry). Both are suspected parser over-strictness
  based on IANA registrations + AMWA reference SDPs.

### Docs

- Clarify the validation strictness principle in CLAUDE.md, GUIDE.md, and
  PLAN.md. The principle now explicitly covers all three polarities of
  normative spec text — positive "shall" / "MUST" requirements, prohibitive
  "shall not" / "MUST NOT" / "is forbidden" clauses, and defined value forms /
  value sets for optional fields when present. Prior wording mentioned only
  prohibitions and well-formedness; behavior is unchanged.

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
