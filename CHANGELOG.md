# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **RFC 4566 §5 / §9 ABNF trailing newline.** Reject input not terminated by
  `\n` (LF or CRLF both accepted). Blank lines between records were already
  rejected.
- **ST 2110-20:2022 §7.6 `ST2115LOGS3`** added to `VALID_TCS` (the 2022
  revision's 11th value).
- **ST 2110-20:2022 §7.1 fmtp separator strictness** at the raw-video branch:
  `;` must be followed by whitespace, and there is no semicolon after the
  last parameter. ST 2110-22 §7.2 keeps the whitespace optional, so this
  strict rule applies only to ST 2110-20 (raw video).
- **RFC 8331 §4 `smpte291` requires `m=video`.** Reject mismatched
  media-type / encoding combinations.
- **RFC 4570 §3 `*` addrtype** in `a=source-filter:` (FQDN dest/src per the
  RFC 4570 ABNF).
- **RFC 7273 §5.4 mediaclk `rate=` option.** Accept
  `direct=0 rate=<int>/<int>` (pull-down form, e.g. 1000/1001 for NTSC
  audio). Format validated.
- **ST 2110-10:2022 §8.2 PTP domain required** when using
  `ts-refclk:ptp=IEEE1588-2008:<gmid>` with a non-`traceable` gmid (per the
  §8.2 SHALL "shall signal either clockIdentity AND domain number, or
  traceable").
- **ST 2110-40:2023 §7 SHALL clauses on smpte291 fmtp.** Require `SSN`
  (`ST2110-40:2018` when `TM` is absent; `ST2110-40:2023` when present;
  senders signaling `ST2110-40:2021` are rejected — §7 makes that value a
  receiver-side tolerance only) and `exactframerate`. Validate `TM`
  (`LLTM`/`CTM`) and `TROFF` (positive integer per ST 2110-21 §8) when
  present.
- **Opt-in conformance test suite** at `spec_conformance/`, driven against
  pinned upstream fixtures from `AMWA-TV/nmos-testing` and
  `AMWA-TV/bcp-006-01`. Fixtures are fetched on demand into a gitignored
  `.cache/`. Manifest entries can declare `expect = "fail"` with an
  `expect_spec_ref` for fixtures that are known non-conformant. Runs
  separately via `busted spec_conformance/`; the default `busted spec/` stays
  hermetic.

### Fixed

- **ST 2110-21:2022 §8.2 CMAX value form relaxed to "an integer number."**
  The §8.2 SDP value-form clause is "expressed as an integer number" — no sign
  or zero restriction. (Same wording in :2017.) Previously the parser used
  `valid_pos_int`, rejecting `CMAX=0` and negative integers under a misquoted
  cite of "§8 — positive integer." The §7.1 type-specific formula
  (`MAX(4, INT(...))` for Type N/NL, `MAX(16, INT(...))` for Type W) is an
  *upper* bound on `CINST` per the Network Compatibility Model in §6.6.1, not
  a lower bound on the SDP-signaled value, so no minimum check is added.
  CMAX-related errors now cite `ST 2110-21:2022 §8.2`. TROFF and TSDELAY
  retain their existing positive-integer enforcement (per ST 2110-21:2022
  §8.2 and ST 2110-10:2022 §8.7 respectively); cites refined accordingly.
- **jxsv mandatory fmtp params reduced to spec.** Required set is now
  `{width, height, TP, packetmode}` per ST 2110-22:2022 §7.2 Table 1 and
  RFC 9134 §7.1. `sampling`, `depth`, `exactframerate`, `TCS`, `colorimetry`
  are validated only when present (RFC 9134 §7.1 marks them optional).
- **jxsv `profile` / `level` / `sublevel` / `transmode` / `SSN` optional.**
  ST 2110-22 §7.2 Tables 1 and 2 don't list these as mandatory; IPMX
  references them for the RTCP JPEG-XS Media Info Block (out of validator
  scope), not SDP fmtp. Format is validated when present.
- **jxsv `PM` requirement removed.** `PM` is the ST 2110-20 packing-mode
  marker; `packetmode` (per RFC 9134) is the jxsv analogue.
- **`VALID_TP_22` includes `2110TPN`** (added in ST 2110-22:2022 §7.2
  Table 1).
- **Blanket fmtp-required check removed.** ST 2110-10:2022 §8 imposes no
  universal fmtp requirement; per-encoding branches enforce what they need.
- **ST 2110-30 `channel-order` optional** per §6.2.2 (absent ⇒ Undefined
  channels). Citation corrected from §7.2 to §6.2.2.
- **ST 2110-40 `DID_SDID` optional.** RFC 8331's media-type registration
  marks it optional; ST 2110-40:2023 §7 doesn't mention it. Format is
  validated on every occurrence when present.
- **Corrected RFC 4566 §6 citation** for the rtpmap/fmtp PT-match check
  (was incorrectly cited as ST 2110-10 §7).

### Docs

- Clarify the validation strictness principle in CLAUDE.md, GUIDE.md, and
  PLAN.md across all three polarities of normative text — positive,
  prohibitive, and defined-value-set-for-an-optional-field. Behavior is
  unchanged.
- GUIDE.md tables updated to match the new jxsv mandatory-param set,
  `ST2115LOGS3` in `TCS`, `a=mediaclk` `rate=` form, mandatory PTP domain,
  and `*` source-filter addrtype.
- PLAN.md tightened: the SDPoker cross-reference backlog (now resolved end
  to end) is no longer mirrored in the plan; remaining work is summarized
  by milestone.

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
