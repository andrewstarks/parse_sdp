# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **RFC 4566 §5 `r=`, `z=`, `k=`, and multiple `t=` support (audit F8).**
  The parser now accepts the full RFC 4566 §5 session structure:
  one-or-more time descriptions (each `t=` followed by zero or more
  `r=` lines), an optional `z=` line, an optional session-level `k=`,
  and an optional media-level `k=` per media block. New grammar entry
  points: `grammar.parse_repeat`, `grammar.parse_timezone`,
  `grammar.parse_key`. New doc-table fields: `session.time_descriptions`
  (list of `{start, stop, repeats}`), `session.time_zones`,
  `session.key`, `m.key`. `session.timing` is preserved as the first
  time description's `{start, stop}` for back-compat. `to_sdp()`
  round-trips all new fields.
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
- **RFC 9134 §7.1 `interlace`/`segmented` enforcement on jxsv.** The jxsv
  branch now enforces the bare-flag form of these parameters and rejects
  `segmented` without `interlace`. RFC 9134 §7.1: *"Signaling of this
  parameter without the interlace parameter is forbidden."* Previously
  these were unconstrained in the jxsv path (they were enforced only in
  the raw-video / ST 2110-20 branch).
- **ST 2110-20:2022 §7.2 SSN ↔ TCS/colorimetry coupling (JT-NM Tested,
  AMWA Issue #11).** A :2022-only value SHALL be paired with `SSN=ST2110-20:2022`:
  reject `TCS=ST2115LOGS3` or `colorimetry=ALPHA` when `SSN=ST2110-20:2017`
  is signaled. (§7.2 SSN clause: "Senders implementing this standard
  shall signal the value ST2110-20:2017 unless the colorimetry value
  ALPHA or the TCS value ST2115LOGS3 are used, in which case the value
  ST2110-20:2022 shall be signaled.") The reverse direction
  ("`SSN=:2022` without :2022-only values is forbidden") is documented
  as a deferred item — strict reading would invalidate ~115 existing
  fixtures and most real-world :2022-implementing senders.
- **ST 2110-20:2022 §7.2 `exactframerate` lowest-terms enforcement.**
  Non-integer rates must be in lowest terms (gcd of numerator and
  denominator must be 1): `30000/1001` accepted; `60000/2002` and `50/2`
  rejected. §7.2: "non-integer rates shall be signaled as a ratio of two
  integer decimal numbers… utilizing the numerically smallest numerator
  value possible." Previously deferred; reading the clause as a SHALL
  extension was the correct interpretation.

### Fixed

- **ST 2110-22:2022 jxsv SHALLs enforced (audit N6 + N7 + N8 + N9).**
  - **N6 (§7.4 Table 4)** — Frame-rate signaling SHALL be present, via
    either `a=framerate:<rate>` (RFC 4566 §6) or fmtp `exactframerate=<rate>`.
  - **N7 (§7.3 Table 3)** — `b=<brtype>:<brvalue>` SHALL appear at media
    level on every jxsv block, with `brtype=AS`. The check moves to the
    ST 2110 tier; the equivalent IPMX-tier check (TR-10-7 §11) becomes
    redundant but is kept as a defensive guard for the value form.
  - **N8 (§7.2)** — *"There is no semicolon character after the last
    item."* Trailing-`;` rejected on jxsv fmtp (factored shared helper
    `fmtp_no_trailing_semicolon`). Unlike -20 §7.1, the post-`;`
    whitespace is OPTIONAL in -22 §7.2, so only the trailing-only check
    transfers.
  - **N9 (§6.2)** — *"The media type name shall be 'video'."* Reject any
    jxsv stream signaled with a non-`video` `m=` line.
- **ST 2110-31:2022 AM824 SHALLs enforced (audit N2 + N3 + N4 + N5).**
  - **N2 (§6.1)** — `<nchan>` SHALL be even ("each AES3 signal contains two
    sequences of AES3 Subframes"). Odd channel counts on AM824 rejected.
  - **N3 (§5.5 + §6.1)** — `<clock-rate>` SHALL be one of `44100`,
    `48000`, `96000`. Other rates on AM824 rejected. (L16/L24 unchanged —
    ST 2110-30 §6.1 leaves other rates "out of scope," not forbidden.)
  - **N4 (§6.1)** — `a=ptime` SHALL be present on AM824. Absence rejected.
  - **N5 (§6.1)** — `<packet-time>` SHALL be one of the Table 1 entries
    for the prevailing clock rate. Float comparison uses ±0.001 ms
    tolerance so equivalent decimal strings (e.g. `0.080` vs `0.08`)
    match. L16/L24 unchanged.
- **ST 2110-21:2022 §8.1 TP required at ST 2110 tier for raw video (audit
  N1).** ST 2110-20:2022 §6.1.1: *"Traffic shaping and transmission timing
  of the RTP stream shall be in accordance with the Network Compatibility
  Model compliance definitions specified in SMPTE ST 2110-21 for Narrow
  Senders (Type N), Narrow Linear Senders (Type NL), or Wide Senders
  (Type W)."* ST 2110-21:2022 §8.1: *"Senders shall include the following
  additional payload-format-specific Media Type parameters in the a=fmtp
  clause of the SDP for all video RTP streams conforming to this
  standard."* — TP. The chain makes TP a Required Parameter on every raw
  video SDP. Moved TP from `video_opt_checks` to `video_checks`. The
  obsolete cross-field "TROFF/CMAX require TP" check is dropped (TP is
  now always present, so it's subsumed). Existing fixtures and tests
  carrying TP continue to pass; tests that omitted TP were updated.
- **ST 2110-10 §6.2 fixed-PT carve-out for L16/44100 (audit F11).** §6.2:
  *"All RTP streams shall use dynamic payload types chosen in the range
  of 96 through 127 … unless a fixed payload type designation exists for
  that RTP Stream within the IETF standard which specifies it."* RFC 3551
  §6 Table 4 statics that match ST 2110-30 essences: PT 10 = L16/44100/2
  and PT 11 = L16/44100/1. Previously rejected; now accepted. PT outside
  96-127 with any other encoding/rate/channel triple still rejected.
  PT > 127 rejected with an RFC 3550 §5.1 cite (7-bit field).
- **RFC 8866 §9 IPv4 layered multicast `<addr>/<ttl>/<numaddr>` accepted
  (audit F9).** §9 ABNF: `IP4-multicast = m1 3("." decimal-uchar) "/" ttl
  [ "/" numaddr ]`. Spec example `c=IN IP4 233.252.0.1/127/3` was
  previously rejected. Now accepted; numaddr must be a positive integer
  (`numaddr = integer = POS-DIGIT *DIGIT`).
- **RFC 8866 §5.7 / §9 IPv4 multicast TTL=0 accepted (audit F10).**
  §5.7 prose: *"TTL values MUST be in the range 0-255."* §9 ABNF
  explicitly admits `"0"` (`ttl = (POS-DIGIT *2DIGIT) / "0"`). Previously
  the parser required `ttl >= 1`.
- **RFC 8866 §9 IPv6 multicast `/numaddr` cite cleanup (audit F7,
  reframed).** The audit suggested rejecting any `/N` suffix on IPv6
  multicast based on §5.7's "TTL MUST NOT be present for 'IP6' multicast"
  prose. Verification against §9 ABNF
  (`IP6-multicast = IP6-address [ "/" numaddr ]`) shows the suffix is a
  layered-address count (`numaddr`), **not** a TTL — both prohibitions
  hold (no IPv6 TTL slot exists, per the ABNF). Parser behavior unchanged
  (still accepts `ff02::1/64`); error messages and comments updated to
  call the suffix `numaddr` instead of `scope`. F7 closed without a
  parser change.
- **ST 2110-30:2025 §6.2.2 `channel-order` convention is SHOULD, not SHALL
  (audit F5).** §6.2.2: *"The `<convention>` of the channel-order should be
  SMPTE2110."* The parser previously hard-required the `SMPTE2110.` prefix
  and rejected any other convention. Now any RFC 3190 §6 `<convention>.<order>`
  form is accepted structurally; the Table 1 symbol enum is enforced only
  when the convention is `SMPTE2110`.
- **ST 2110-31:2022 §6.2 Table 2 `AES3` channel-grouping symbol (audit F6).**
  AM824 streams may signal `channel-order=SMPTE2110.(AES3,…)`. Previously
  rejected because `AES3` was missing from the symbol enum. Now accepted on
  AM824 only — L16/L24 streams still reject `AES3` (per §6.2's "for AES3
  Subframes containing PCM audio" carve-out, the symbol is defined only for
  AM824).
- **ST 2110-41:2024 §6 DIT is optional, comma-separated uppercase hex
  (audit F3).** Previously the parser required `DIT` and validated it as
  a single non-negative decimal integer, which rejected the literal §6
  example `DIT=100,2000A1,1013FC,3FFF00`. §6 makes DIT a SHOULD; §9.2.3
  lists it under Optional Parameters. When present: comma-separated
  uppercase hex tokens; no leading `0x`; no whitespace
  (all SHALLs from §6). Reject lowercase hex, `0x` prefix, whitespace.
- **ST 2110-41:2024 §5.3 clock rate is Data-Item-defined, not fixed
  at 90 kHz (audit F4).** Previously the parser rejected any `ST2110-41`
  rtpmap whose clock rate was not 90000. §5.3: *"The RTP Clock rate
  and RTP Timestamp requirements of each Data Item are defined in the
  document that specifies the Data Item Package Contents."* §9.2.2
  references rate "as specified in Clause 5.3." Removed the 90 kHz
  equality check; rate is still validated as a positive integer by
  `rtpmap` parsing.
- **TR-10-5 §17 `a=hkep` permitted at media level (audit F2 + D4).**
  Previously the parser rejected any media-level `a=hkep`, citing the
  §10 "shall contain at least one 'hkep' session attribute" wording as
  session-only. §17 (IANA Registration) is explicit: *"its Usage Level
  is 'session, media' … an SDP transport file may convey HKEP
  information at the session level, at the media level, or at both
  levels."* §10 requires at least one session-level hkep when the stream
  carries HDCP Content; it does not forbid additional media-level
  attributes. Now validates every `a=hkep` (session or media) with the
  same `valid_hkep` function.
- **ST 2110-20:2022 §7.3 TCS is optional, not required (audit F1 + D3).**
  Raw-video `TCS` is listed in §7.3 "Media Type Parameters with default values",
  not in §7.2 ("Required Media Type Parameters"). §7.6: *"If the TCS value is
  not specified, receivers shall assume the value SDR, unless the sampling
  keyword indicates the signal is a KEY signal, in which case the TCS value
  is not meaningful."* Moved TCS from the raw-video required-fmtp list to the
  optional-when-present list (value enum unchanged — full §7.6 set). Updates
  GUIDE.md to "eight required parameters" and reclassifies the TCS row.
- **jxsv `RANGE` cite refined to RFC 9134 §7.1.** ST 2110-22 does not
  define `RANGE`; the value-form authority for the IANA `video/jxsv`
  registration is RFC 9134 §7.1. The enum `{NARROW, FULLPROTECT, FULL}`
  is unchanged; only the `spec_ref` cite moved.
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
