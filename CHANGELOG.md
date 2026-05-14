# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added (M23 — validation gap closure 2026-05-13, round 2)

- **`a=group:FID` rejected at IPMX tier** (TR-10-1 §10): any session-level `a=group:FID` attribute is now rejected in IPMX mode; it is still accepted at the ST 2110 tier
- **Session-level `c=` validated** (ST 2110-10 §6.5): `valid_connection_address` is now called for `doc.session.connection` in addition to per-media connection addresses; forbidden ranges and unicast+TTL are rejected at session level
- **Missing `c=` detected** (ST 2110-10 §6.3): a media block with no per-media `c=` and no session-level `c=` is now rejected
- **All `a=ts-refclk` entries validated** (ST 2110-10 §8.2): previously only the first `a=ts-refclk` was validated via `find_attr`; all ts-refclk attributes at both session and media level are now iterated and individually validated
- **`a=extmap` ID uniqueness enforced** (RFC 5285 §3): duplicate extmap IDs within the session scope or within a single media block are now rejected; IDs may repeat across different levels

### Tests (M23)

- `spec/st2110_spec.lua`: 10 new tests — session-level c= valid multicast accepted; forbidden range and unicast+TTL at session level rejected; no c= at either level rejected; session-level c= with no media c= accepted; two valid ts-refclk accepted; second invalid ts-refclk rejected; media-level-only ts-refclk accepted; invalid media-level ts-refclk rejected even when session ts-refclk is valid
- `spec/ipmx_spec.lua`: 7 new tests — `a=group:FID` rejected with spec_ref TR-10-1 §10; `a=group:DUP` not affected; ST 2110 mode accepts FID; duplicate session-level extmap ID rejected; same ID at different levels accepted; IPMX audio ptime=0 rejected; IPMX audio ptime=-1 rejected

### Added (M22 — validation gap closure: JPEG-XS, enum gaps, SSN year, channel-order, TTL, IPMX port/audio/baseband)

- **JPEG-XS / ST 2110-22 (`jxsv`)**: new validation branch for `jxsv`-encoded video. Validates clock rate (90000), all nine standard video fmtp params plus five required codec params (`profile`, `level`, `sublevel`, `transmode`, `packetmode`), optional `RANGE`, `TP` (restricted to `2110TPNL`/`2110TPW` — `2110TPN` is rejected), `MAXUDP`, `CMAX`, `fbblevel`; SSN must use `ST2110-22:YYYY` prefix
- **TCS=UNSPECIFIED**: added missing value from ST 2110-20:2017 §7.6 — was previously rejected
- **colorimetry=XYZ**: added missing value from ST 2110-20:2017 §7.5 — was previously rejected
- **SSN 4-digit year**: ST 2110-20, ST 2110-22, and ST 2110-41 SSN values now require a 4-digit year suffix (e.g. `ST2110-20:2022`); bare prefix (`ST2110-20:`) or non-numeric suffix is rejected
- **channel-order group symbols**: group symbols in `SMPTE2110.(...)` are now validated against the ST 2110-30:2017 §6.2.2 Table 1 set (`M`, `DM`, `ST`, `LtRt`, `51`, `71`, `222`, `SGRP`, `U01`–`U64`); unknown symbols or out-of-range `Unn` values are rejected
- **Multicast TTL range**: TTL in `c=IN IP4 addr/TTL` must be an integer in 1–255; TTL=0 and TTL=256 are now rejected
- **IPMX port range**: non-USB media ports must be even and > 1024 (TR-10-1 §7); odd or ≤ 1024 ports are rejected
- **IPMX audio — AM824 rejected**: `AM824` encoding is not valid at the IPMX tier (TR-10-3 §8); only `L16` and `L24` are accepted
- **IPMX audio — ptime required**: `a=ptime` is now required on every IPMX audio media block (TR-10-3 §8)
- **IPMX baseband fmtp params**: `measuredpixclk`, `vtotal`, `htotal` (video, TR-10-2 §11) and `measuredsamplerate` (audio, TR-10-3 §10.3) must be positive integers when present
- **a=extmap ID upper bound**: extmap IDs greater than 255 are now rejected per RFC 5285

### Tests (M22)

- `spec/st2110_spec.lua`: 38 new tests — TCS=UNSPECIFIED and XYZ colorimetry accepted; unknown TCS/colorimetry rejected; SSN=ST2110-20:2022/2017 accepted; SSN without year, two-digit year, non-numeric suffix rejected; channel-order all named symbols and U01/U64 accepted; foo, U00, U65 rejected; TTL=1/64/255 accepted; TTL=0/256 rejected; valid JPEG-XS SDP accepted; wrong SSN prefix rejected; TP=2110TPN rejected; TP=2110TPW accepted; each required jxsv param missing rejected; fbblevel=3 accepted; fbblevel=0 rejected; extmap ID=255 accepted; ID=256 rejected
- `spec/ipmx_spec.lua`: 22 new tests — port=5000 accepted; port=5001 (odd) and port=1024 rejected; spec_ref=TR-10-1 §7; USB block exempt; L24/L16 with ptime accepted; audio without ptime rejected; AM824 rejected; video measuredpixclk/vtotal/htotal validated; measuredsamplerate validated; spec_refs TR-10-2 §11 / TR-10-3 §10.3

### Added (M21 — validation gap closure: DUP legs, hkep media-level, c= address, extmap URI)

- `a=group:DUP` minimum leg count (ST 2110-10 §8.5): a DUP group with fewer than 2 legs is now rejected; previously single-leg groups were silently accepted
- `a=hkep` at media block level (TR-10-5 §10): format validation now applies to `a=hkep` at media block level, not only at session level
- `c=` connection address validation for ST 2110 media blocks (ST 2110-10 §6.5 / RFC 5771): IPv4 multicast addresses require a TTL suffix; the Local Network Control Block (224.0.0.0/24) and Internetwork Control Block (224.0.1.0/24) are rejected; unicast addresses must not carry a TTL suffix
- `a=extmap` URI format validation (IPMX §6 / RFC 5285): every `a=extmap` value is now validated to conform to RFC 5285 format (`entry-count[/direction] URI`); an invalid direction keyword or a URI without a scheme is rejected; applies to session-level and non-USB media-block extmap attributes

### Tests (M21)

- `spec/st2110_spec.lua`: 8 new tests — single-leg DUP group rejected; `c=` multicast without TTL rejected; forbidden ranges 224.0.0.0/24 and 224.0.1.0/24 rejected; unicast with TTL rejected; valid multicast/unicast accepted; `exactframerate=0`, `width=0`, `height=0`, `depth=0` rejected; `MAXUDP=0` rejected; `PAR=1:0` (zero denominator) rejected; session-level-only `ts-refclk` accepted
- `spec/ipmx_spec.lua`: 12 new tests — single-leg DUP group rejected; valid `a=hkep` at media level accepted; invalid `a=hkep` at media level rejected; `a=extmap` URI format: standard urn:, direction qualifier, IPMX vendor URI accepted; missing URI scheme, invalid direction, ID-only each rejected; field_path identifies `session.attributes[extmap]`; bad extmap at media level reports `media[1]`; `FEC_ADD_LATENCY_VIDEO=0` and `FEC_ADD_LATENCY_AUDIO=0` accepted; empty `iv=` in `a=privacy` rejected

### Added (M20 — validation audit and gap closure)

- ST 2110-30 channel count (§7.1): the third component of `a=rtpmap` (e.g. `/8` in `L24/48000/8`) is now required and validated as an integer in the range 1–16; missing or out-of-range values are rejected
- ST 2110-30 `a=ptime` format validation (§7.2): when present, the value must be a positive number; zero and non-numeric values are rejected
- ST 2110: `a=rtpmap` and `a=fmtp` payload type consistency (ST 2110-10 §7): the numeric payload type at the start of each attribute's value must match; a mismatch is now rejected
- ts-refclk `ntp=` address format validation (LPEG): the address after `ntp=` is now validated against IPv4 dotted-decimal, IPv6 (full RFC 4291 / RFC 3986 §3.2.2 grammar), and hostname formats; invalid strings are rejected
- IPMX FEC: `FEC_ADD_LATENCY_VIDEO` and `FEC_ADD_LATENCY_AUDIO` now require `FECPROFILE` to also be present in the same `a=fmtp`; specifying a latency parameter without `FECPROFILE` is rejected

### Tests (M20)

- `spec/st2110_spec.lua`: 18 new tests — rtpmap/fmtp PT mismatch (match accepted, mismatch rejected); ST 2110-30 channel count (1/8/16 accepted; 0, 17, missing rejected); ST 2110-30 ptime (absent OK, 1/20 accepted; 0 and non-numeric rejected); CMAX=0 rejected; ts-refclk PTP GMID wrong octet count (6 and 9 octets rejected); ts-refclk ntp= LPEG (valid IPv4, hostname, single-label, IPv6 accepted; `not@valid!` and hyphen-prefix label rejected); RFC-compliant IPv6 grammar (loopback `::1`, all-zeros `::`, compressed, IPv4-mapped accepted; triple-colon `:::` and bare 3-group `1:2:3` rejected)
- `spec/ipmx_spec.lua`: 8 new tests — `protocol=RTP_KV` accepted; non-hex `key_generator`, `key_version`, `key_id` each rejected; `FEC_ADD_LATENCY_AUDIO=notanumber` rejected; `FEC_ADD_LATENCY_VIDEO` without FECPROFILE rejected; `FEC_ADD_LATENCY_AUDIO` without FECPROFILE rejected; `FEC_ADD_LATENCY_VIDEO` with FECPROFILE accepted

### Added

- `spec/.luarc.json`: suppress lua-language-server false-positive undefined-global warnings for busted globals (`describe`, `it`, `context`, `assert`) scoped to `spec/` only
- M18: ST 2110-20 fmtp value validation — all nine required `fmtp` parameters (`sampling`, `width`, `height`, `exactframerate`, `depth`, `TCS`, `colorimetry`, `PM`, `SSN`) are now validated for both presence and value format per ST 2110-20 §7.2
- M18: ST 2110-30 `channel-order` format validation — value must match `SMPTE2110.(<group>)` with a non-empty group token per ST 2110-30 §7
- ST 2110-20 optional `RANGE` fmtp parameter validated when present (`NARROW`, `FULLPROTECT`, `FULL`) per §7.2
- ST 2110-30 audio `rtpmap` clock rate validated against known professional sample rates: 32000, 44100, 48000, 88200, 96000, 176400, 192000 Hz
- M19: ST 2110-20 optional `fmtp` parameters now validated when present: `TP` (`2110TPN`/`2110TPNL`/`2110TPW`), `MAXUDP` (positive integer), `PAR` (`W:H` with positive integers), `TROFF` (non-negative integer), `CMAX` (positive integer)
- M19: ST 2110-20 bare-flag parameters `interlace` and `segmented` accepted without value restriction
- M19: ST 2110-30 `a=rtpmap` encoding name validated — must be `L16`, `L24`, or `AM824`
- M19: ST 2110-40 `VPID_Code` optional fmtp parameter validated as non-negative integer when present
- M19: ST 2110-41 `DIT` required fmtp parameter value validated as non-negative integer (was presence-only)

### Fixed

- ST 2110-41: clock rate (90000) is now validated (was accepted without a check)
- ST 2110-41: SSN value is now validated to start with `ST2110-41:` (was presence-only)
- ST 2110-40 (smpte291): all `DID_SDID` entries in `a=fmtp` are now validated; previously only the last occurrence was checked

### Changed

- CLI subcommands renamed: `parse` → `to_json`, `serialize` → `to_sdp` — names now
  mirror the doc methods `doc:to_json()` and `doc:to_sdp()`
- **`rtpmap_parse`** replaces the two separate `rtpmap_clock_rate` / `rtpmap_encoding`
  helpers; call sites now receive encoding name and clock rate in one call
- **`fmtp_params`** is now called once per media block (before the encoding branch)
  instead of once per branch — eliminates four copies of identical error handling
- **`each_dup_group(doc, spec_ref, callback)`** extracts the duplicated DUP group
  iteration that existed separately in `st2110.validate` and `ipmx.validate`
- **`attr_err(msg, mpath, attr, spec_ref, code)`** helper eliminates 21 repeated
  `errors.new(…, { field_path = mpath .. ".attributes[…]", … })` constructions
- Module entry points renamed: `st2110.validate`, `ipmx.validate`, `serialize.to_sdp`
  (previously `st2110.st2110`, `ipmx.ipmx`, `serialize.serialize`)
- **`check_privacy`** hoisted from a closure inside `ipmx.validate` to a module-level
  local alongside the other `valid_*` helpers
- Milestone tags (`M16:`, `M17:`) removed from inline code comments; spec references
  (`TR-10-13 §13`, `TR-10-1 §8.7`) are sufficient
- Redundant ldoc blocks stripped from five one-liner pass-through grammar functions
  (`parse_session_name`, `parse_info`, `parse_uri`, `parse_email`, `parse_phone`)
- `valid_hkep`: the captured-but-unused host address token is now named `_` with a
  comment explaining TR-10-5 §10 does not constrain its format
- 226 tests pass; file reduced from 1337 to 1256 lines

### Added (M16 — ST 2022-7 DUP grouping)

- **`a=group:DUP` validation** (ST 2110-10 §8.5): when present at session level, all
  named `mid` values are resolved against media blocks carrying `a=mid`; all legs must
  share the same media type; absence of `a=group:DUP` is not an error
- **DUP privacy consistency** (TR-10-13 §13): across DUP-grouped legs in IPMX mode,
  `a=privacy` values must be identical on every leg; a leg missing `a=privacy` while
  another carries it is rejected
- 4 new example fixtures (2 ST 2110 valid/invalid, 2 IPMX valid/invalid)
- 10 new tests across `spec/st2110_spec.lua` and `spec/ipmx_spec.lua`

### Added (M17 — RTCP port convention)

- **`a=rtcp-mux` rejection** (TR-10-1 §8.7, IPMX only): `a=rtcp-mux` on any RTP media
  block is rejected at the IPMX tier; ST 2110 mode accepts it without restriction
- **`a=rtcp:<port>` check** (TR-10-1 §8.7, IPMX only): when present, the specified port
  must equal the media block's declared port + 1; any other value is rejected
- 6 new tests in `spec/ipmx_spec.lua`; 1 new `a=rtcp-mux` fixture in `examples/ipmx/invalid/`

### Added (M15 — IPMX protocol extensions)

- **IPMX fmtp marker** (TR-10-1 §10.1): every non-USB media block's `a=fmtp` must now
  contain the bare `IPMX` flag; absence is rejected with a `TR-10-1 §10.1` error
- **`a=hkep` validation** (TR-10-5 §10): when present at session level, the HDCP Key
  Exchange attribute is validated against the required format
  `<port> IN <IP4|IP6> <addr> <node-id> <port-id>` (UUID node-id, five-octet port-id)
- **`a=privacy` validation** (TR-10-13 §13): when present at session or media level,
  all six required parameters (`protocol`, `mode`, `iv`, `key_generator`, `key_version`,
  `key_id`) are checked; `protocol` must be `RTP` or `RTP_KV`; `mode` must be one of the
  12 defined AES variants; hex parameters must be valid hex strings
- **USB transport bypass** (TR-10-14): `m=application` blocks with TCP transport are now
  identified as USB flows and exempt from ST 2110 media-block validation; any `a=privacy`
  on a USB block is validated with the stricter AAD-only mode set (four modes)
- **FEC parameter validation** (TR-10-6 §7.6): when `FECPROFILE` appears in `a=fmtp`, it
  must equal `profile-a`; `FEC_ADD_LATENCY_VIDEO` and `FEC_ADD_LATENCY_AUDIO`, if present,
  must be non-negative integers (microseconds)
- 26 new tests in `spec/ipmx_spec.lua` covering all of the above

### Fixed (M15)

- Updated existing `spec/ipmx_spec.lua` fixtures to include the `IPMX` bare flag in
  `a=fmtp` — they were missing it, silently passing a check that is now enforced

---

### Added (M14 — ST 2110-40/41)

- ST 2110-40 ancillary data validation: when `a=rtpmap` encoding name is `smpte291`, the
  library now requires clock rate 90000 and at least one `DID_SDID={0xHH,0xHH}` entry in
  `a=fmtp`; each octet is validated as exactly two hex digits (RFC 8331 / ST 2110-40 §7.2)
- ST 2110-41 fast metadata validation: when encoding name is `ST2110-41`, the library now
  requires `SSN=ST2110-41:…` and `DIT=…` in `a=fmtp` (ST 2110-41 §7.2)
- 6 new tests in `spec/st2110_spec.lua` covering the above (3 per sub-standard)
- 4 new example fixtures: `examples/st2110/valid/07_ancillary_data.sdp`,
  `examples/st2110/valid/08_fast_metadata.sdp`,
  `examples/st2110/invalid/07_missing_did_sdid.sdp`,
  `examples/st2110/invalid/08_missing_ssn.sdp`
- `GUIDE.md`: ST 2110-40 and ST 2110-41 fmtp parameter tables added

### Fixed (M14)

- `fmtp_params`: bare flag tokens (e.g. `interlace` per ST 2110-20 §7.2) are now accepted
  and stored as `params[key] = true`; only genuinely malformed tokens (containing spaces or
  other non-identifier characters) are rejected
- Corrected `DID_SDID` notation in three example fixtures from the non-standard `0xNNNN`
  form to the RFC 8331-specified `{0xHH,0xHH}` pair format

### Changed (code quality pass)

- `parse_sdp.lua`: comprehensive ldoc annotations added to all public functions and significant
  internal helpers (`errors.new`, `errors.format`, `util.find_attr`, all grammar parsers,
  `validate.sdp`, `serialize.serialize`, `st2110.st2110`, `ipmx.ipmx`, `parser.parse`,
  `M.parse`, `M.new`, all `mt:` methods)
- `serialize.serialize`: refactored from O(n²) string concatenation to O(n) table accumulation
  (`table.insert` + `table.concat`); `ser_media_block` likewise
- `mt:validate`: sequential `if` dispatch replaced with a lookup table (`validators`)
- 5 new tests: `st2110_spec` — rtpmap missing, fmtp missing, audio channel-order missing;
  `ipmx_spec` — extmap at session level only; `sdp_spec` — timing rejects trailing content
- `GUIDE.md`: 5 accuracy fixes — stale `lib/` manual-install reference removed; error code
  `UNKNOWN_FIELD` corrected to `MALFORMED_LINE`; `ts-refclk` format expanded to show all six
  accepted forms; ST 2110-20 fmtp table now shows which parameters are validated vs. specified;
  IPMX section rewritten with accurate implementation description and unimplemented-extensions
  table (HKEP, PEP, USB, FEC)
- `README.md`: stale `doc:serialize()` call corrected to `doc:to_sdp()`; project layout updated
  to reflect R9 (`lib/` removed, all spec files listed)
- `PLAN.md`: M14 (ST 2110-40/41 ancillary data and fast metadata) and M15 (IPMX protocol
  extensions: HKEP, PEP, USB, FEC) added

### Changed (R9)

- R9: `lib/` directory deleted; all modules (errors, util, grammar, validate, serialize, st2110, ipmx, parser) inlined into `parse_sdp.lua` as ordered local-table sections with banner comments; `M._grammar` and `M._errors` exposed for spec access; `spec/sdp_spec.lua` and `spec/errors_spec.lua` updated to use `require("parse_sdp")._grammar` / `._errors`

### Changed (R8)

- R8: `cli.lua` deleted; CLI merged into `parse_sdp.lua` behind a detect-if-main guard (`arg[0]:match("parse_sdp")`); argparse replaces hand-rolled flag parsing; `parse_sdp.lua` is now both the library entry point and a `chmod +x` executable; `--help` / `parse --help` / `serialize --help` all work; Docker image updated with `luarocks install argparse`

### Changed (R1–R7 refactor)

- R1: `lib/parser.lua` — trailing-content guard: any field or content after the last recognized SDP block is rejected (`WRONG_ORDER` or `MALFORMED_LINE`)
- R2: `doc:serialize()` renamed to `doc:to_sdp()` for symmetry with `doc:to_json()`; all call sites updated (examples, GUIDE.md, spec, CLAUDE.md)
- R3: `lib/util.lua` — new module; `util.find_attr` extracted from `lib/st2110.lua` and `lib/ipmx.lua`
- R4: `errors.new(msg, opts)` added to `lib/errors.lua`; all ad-hoc error literals across `parse_sdp.lua`, `lib/validate.lua`, `lib/st2110.lua`, `lib/ipmx.lua`, `cli.lua` replaced
- R5: parse loop (split_lines, parse_required, mode dispatch) extracted to `lib/parser.lua`; `parse_sdp.lua` is now a ~50-line facade
- R6: `lib/st2110.lua` — `fmtp_params` rejects tokens without `=`; `valid_tsrefclk` rejects `ntp=` with whitespace
- R7: test coverage added (gal, glonass, ntp=, ptp-no-domain, direct-negative, fmtp-malformed, unknown-mode); low-value method-existence tests removed

### Added (M11–M13)

- `examples/` — 27 annotated SDP fixtures (generic, ST 2110, IPMX; valid and invalid) plus `examples/examples.lua`, a runnable API walkthrough covering all public entry points, doc methods, error anatomy, and a full sweep of every example file
- `PLAN.md` — R1–R7 refactor milestones: trailing-content strictness bug, serialize→to_sdp rename, find_attr deduplication, unified error builder, parser extraction to lib/parser.lua, fmtp/ntp strictness, and test audit

- M13: `lib/errors.lua` — new module; `errors.format(err)` renders human-readable output: `error: [CODE] message`, location arrow, context line + caret at column, spec clause note; 11 tests in `spec/errors_spec.lua`
- M13: error codes added to all error constructors — `MISSING_FIELD`, `INVALID_VALUE`, `WRONG_ORDER`, `MALFORMED_LINE` in `parse_sdp.lua`, `lib/validate.lua`, `lib/st2110.lua`, `lib/ipmx.lua`
- M13: `cli.lua` — stderr now uses `errors.format()` instead of raw JSON; CLI tests updated accordingly
- M12: `cli.lua` — `serialize` subcommand: reads JSON from file or stdin, decodes with dkjson, calls `sdp.new()` + `doc:to_sdp()`; JSON error to stderr on invalid JSON or serialize failure; exit 0/1; 5 integration tests including round-trip
- M11: `cli.lua` — `parse` subcommand: `parse_sdp parse [--mode MODE] [--pretty] [file]`; reads file or stdin; JSON to stdout on success, JSON error to stderr on failure; exit 0/1; 8 integration tests in `spec/cli_spec.lua`
- M10: `parse_sdp.lua` — `mt:to_sdp()` alias for `serialize`; symmetric pair with `to_json`; 3 tests confirming method presence, identical output to `serialize`, and `sdp.new({})` availability
- M10: `parse_sdp.lua` — `mt:to_json()` method using dkjson; 8 tests in `spec/sdp_spec.lua` covering method presence, string return, valid JSON round-trip, field structure (version, origin, session attributes, media), and `sdp.new({})` method availability
- M8: `lib/st2110.lua` — value format checks for `ts-refclk` (ptp=, localmac=, gps/gal/glonass, ntp=; rejects unrecognized sources and malformed MACs/GMIDs) and `mediaclk` (`direct=<integer>` or `sender`; rejects anything else)
- M8: `lib/st2110.lua` — new module; `st2110.st2110(doc)` validates a parsed doc against SMPTE ST 2110: at least one `m=` block; per-media `a=ts-refclk` (or session-level), `a=mediaclk`, `a=rtpmap`, `a=fmtp`; video clock rate = 90000 and `sampling` fmtp param; audio `channel-order` fmtp param; errors carry `field_path` and `spec_ref` fields
- M8: `parse_sdp.lua` — `mt:validate("st2110")` and `mt:is_st2110()` wired to `lib/st2110`; `M.parse(text, "st2110")` runs ST 2110 validation after RFC 4566 parse
- M9: `lib/ipmx.lua` — new module; `ipmx.ipmx(doc)` runs ST 2110 validation then checks that `a=extmap` is present at session or media level; errors carry `field_path` and `spec_ref`
- M9: `parse_sdp.lua` — `mt:validate("ipmx")` and `mt:is_ipmx()` wired to `lib/ipmx`; `M.parse(text, "ipmx")` runs IPMX validation after RFC 4566 parse
- M9: 9 tests in `spec/ipmx_spec.lua` — valid IPMX (localmac ts-refclk) passes, ST 2110-only SDP rejected for missing extmap, generic SDP rejected, `is_ipmx()` bool
- M8: 15 tests in `spec/st2110_spec.lua` — valid video/audio pass, generic SDP rejected, missing ts-refclk/mediaclk/rtpmap/fmtp errors, wrong video clock rate error, missing sampling/channel-order errors, `is_st2110()` bool; added localmac ts-refclk test to confirm PTP is not required
- M7: `lib/serialize.lua` — new module; `serialize.serialize(doc)` emits RFC 4566 §5 field order with CRLF endings; handles all session-level optional fields, per-media i=/c=/b=/a=, port count, multi-fmt lists
- M7: `parse_sdp.lua` — `mt:serialize()` method; round-trip invariant: `parse(serialize(parse(text)))` deep-equals `parse(text)`
- M7: 11 tests in `spec/sdp_spec.lua` — method present, CRLF check, field order (minimal and full session), re-parse sanity, round-trip deep-equal, media blocks, port count

- M6: `lib/validate.lua` — new module; `validate.sdp(doc)` checks in-memory doc table: version, origin fields (net_type/addr_type constraints), session name and timing, media block structure
- M6: `parse_sdp.lua` — metatable methods: `mt:validate([mode])`, `mt:is_sdp()`, `mt:is_st2110()` (stub → false), `mt:is_ipmx()` (stub → false)
- M6: 10 tests in `spec/sdp_spec.lua` — methods present on parse result and `sdp.new()`, `validate()` true/nil+err, `is_sdp()` true/false after mutation, stubs return false

- M5: `lib/grammar.lua` — `parse_media` function: parses `m=` value into `{media, port, port_count, proto, fmts}`; uses LPEG `Ct` to capture variable-length fmt list; port/count split via Lua pattern after LPEG capture
- M5: `parse_sdp.lua` — after session-level `a=` fields, parse zero or more `m=` blocks; each block collects per-media `i=`, `c=`, `b=*`, `a=*` in RFC 4566 order; `doc.media` is always present (empty table when no blocks)
- M5: 13 tests in `spec/sdp_spec.lua` — `grammar.parse_media` unit tests (minimal, port/count, multi-fmt, bad values); integration tests for single block, two blocks, port count, multi-fmt, per-media i=/c=/b=/a=, empty media array, malformed m= error

- M4: `lib/grammar.lua` — optional-field parsers: `parse_info`, `parse_uri`, `parse_email`, `parse_phone` (identity); `parse_connection` returning `{net_type, addr_type, address}`; `parse_bandwidth` returning `{type, value}`; `parse_attribute` returning `{name[, value]}`
- M4: `parse_sdp.lua` — cursor-based `parse` refactor: consumes optional `i=`, `u=`, `e=*`, `p=*`, `c=`, `b=*` before `t=`, and `a=*` after `t=`; adds `session.info`, `.uri`, `.emails`, `.phones`, `.connection`, `.bandwidths`, `.attributes` fields; all array fields are always present (empty tables when absent)
- M4: 15 integration tests in `spec/sdp_spec.lua` — all optional field types, IPv4/IPv6 connection, AS/CT/X- bandwidth, flag and value attributes, multiple repeating fields, full-optional-field SDP, minimal SDP empty-array invariant

- M3: `lib/grammar.lua` — value parsers: `parse_version`, `parse_origin`, `parse_session_name`, `parse_timing`; each returns parsed result or `nil, fail_col`
- M3: `parse_sdp.lua` — real `parse(text)` implementation: splits lines, enforces `v o s t` order, builds doc table with `version`, `origin`, `session.name`, `session.timing`; error table shape `{ message, line, col, context }`
- M3: integration tests in `spec/sdp_spec.lua` — minimal valid SDP, LF-only endings, missing fields, wrong order, bad values, error table shape, extra-content passthrough
- M2: `lib/grammar.lua` — LPEG line tokenizer: `grammar.tokenize_line(s)` parses `<alpha>=<value><CRLF|LF|EOS>`, returns type char, value string, and byte offset of value start; returns `nil, fail_pos` on malformed input
- M2: grammar tests in `spec/sdp_spec.lua` — valid CRLF, LF-only, no-newline lines; rejects empty input, no-equals, multi-char type, non-alpha type, empty value; verifies failure positions
- M1: `parse_sdp.lua` stub — exports `parse` (returns `nil, {message="not implemented"}`) and `new`
- M1: `spec/sdp_spec.lua` smoke test — `require("parse_sdp")` loads without error
- M1: `.busted` config
- M1: `Dockerfile` and `docker-compose.yml` — Lua 5.5 + LuaRocks (HEAD) + lpeg + dkjson + busted
- M1: directory layout — `lib/`, `spec/`, `spec/fixtures/`
- Initial project structure: `README.md`, `GUIDE.md`, `PLAN.md`, `CLAUDE.md`, `CHANGELOG.md`
- Project name: `parse_sdp` (renamed from `sdp_parser`)
- Full API design: `sdp.parse(text[, mode])`, `sdp.new(table)`, doc object with `validate`, `serialize`, `to_json`, `is_sdp`, `is_st2110`, `is_ipmx` methods
- CLI design: `parse_sdp parse` and `parse_sdp serialize` subcommands
- 13-milestone implementation plan replacing original 6-phase structure
- dkjson selected as JSON dependency (pure Lua, LuaRocks)
- Strictness established as a primary design principle: pedantic RFC 4566 enforcement, no lenient mode

### Notes

- LuaRocks 3.12.1 (latest stable) does not support Lua 5.5; Dockerfile pins to LuaRocks HEAD commit `fc402072` pending an official release
