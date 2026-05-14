# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
