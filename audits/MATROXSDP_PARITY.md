# MatroxSdp parity matrix

Reference: `MatroxSdp.py` (2,674 lines), `MatroxSdpCheck.py` (594 lines),
`suites/IpmxSdpTest.py` (`test_02`, `test_03`, `test_14`),
`SdpToCapabilities.py` (`_verify_capabilities_identical`) and
`tests/sdp_decode_test.py` in `alabou/nmos-testing`, branch `testing-IPMX`,
commit `d26bc1b` (2026-10-27). Line numbers below are from that commit.

The reference is evidence of what one implementation chose to check. It is
never authority. Every verdict cites primary specification text. No code,
comment, fixture or test text was copied from the reference (Apache-2.0;
this library is MIT).

Verdicts:

- **ADOPT**: a SHALL, MUST or defined value set supports the check. The
  row names the check id that lands (or landed) and the phase.
- **COVERED**: `parse_sdp` already has the check. The row names the id.
- **REJECT**: the specification is silent or says otherwise. The row cites
  the closed `decision` bead that holds the quote.
- **OUT OF SCOPE**: the check compares the SDP against IS-04 / IS-05 state
  that is not in the SDP (CLAUDE.md "Validation Strictness Principle").
- **NONE**: a parse behavior or default that neither parser turns into a
  check, and for which the text defines no rule. Nothing to adopt or
  reject.

Status (2026-10-28): every ADOPT row landed. PR #28 (H.264), #30 (H.265),
#31 (AAC), #32 (MP2T), #33 (the limitations rows) carry the ids the rows
name. Two rows changed verdict while landing and say so inline: the
ST 2110-10 §8.1 media-count row (decision `parse_sdp-dxe`) and the RFC
6416 `bitrate` row (decision `parse_sdp-cad`). The red-team review in
epic `parse_sdp-1wh` (2026-10-28) amended six rows, each marked inline:
the PTP domain and extmap rows (§2), `emphasis` (§4.4, §5.3),
`streamStateIndication` (§4.5), and the ST 2110-22 90 kHz and `TP` rows
(§5.13).

Phases are the child beads of epic `parse_sdp-j7c`: `.3` H.264, `.4` H.265,
`.5` AAC, `.6` MP2T, `.7` limitations, `.8` close-out.

Two facts about the reference shape every verdict below:

1. Its `process_fmtp` does not consult the rtpmap encoding. Any known
   parameter name is accepted on any encoding, and 11 of its 12 enum-typed
   parameters register unknown strings as new enum values instead of
   rejecting them. Its parse-time value checks are therefore mostly
   "is an integer". The value-set and presence checks live in
   `MatroxSdpCheck.py`.
2. Its parse-time handlers return error strings; the only exceptions are
   the three profile/level decoders. "Rejects" below means "returns an
   error string" unless stated.

## 1. Line handling (`MatroxSdp.py` `process_lines` 745–782 and the per-line handlers)

| Source | Reference behavior | Verdict | Primary citation | Phase |
| --- | --- | --- | --- | --- |
| 749–753 | Strips each line; requires `=` as the second character | COVERED `sdp.line.trailing-whitespace` (warn), hard parse failure on a line without `=` | RFC 8866 §5 (`<type>=<value>`), §9 | — |
| 756–779 | No line-order check; k, z, u, e, p, r ignored; unknown types ignored | COVERED: order is enforced by the grammar (RFC 8866 §5 "fixed order"); every RFC 8866 line type is parsed; an unknown type fails | RFC 8866 §5 | — |
| 784–787 | `v=` first character must be `0` | COVERED `sdp.v.must-be-zero` | RFC 8866 §5.1 | — |
| 789–805, 2014 | `o=` exactly 6 tokens, `IN`, `IP4`/`IP6`; sess-id and sess-version must be non-zero | COVERED (six-field form, `sdp.o.username-required`); non-zero: REJECT `parse_sdp-nec` | RFC 8866 §5.2 "`<sess-id>` is a numeric string" | — |
| 807–809, 2016 | `s=` required | COVERED (grammar requires `s=`) | RFC 8866 §5.3 | — |
| 819–865 | `c=` three tokens; address split on `/`; no address, multicast or TTL checks; never required | COVERED and stricter: `sdp.c.address.invalid-ipv4/ipv6`, `sdp.c.ipv4-multicast.ttl-required` / `ttl-out-of-range` / `numaddr-invalid`, `sdp.c.ipv6-multicast.*`, `sdp.c.ipv4-unicast.suffix-not-allowed`, `sdp.session.connection-required` | RFC 8866 §5.7, §9 | — |
| 867–881 | `b=` type must be `AS`; value an integer | REJECT `parse_sdp-t7u` (CT is defined; unknown types MUST be ignored). Value form COVERED (grammar: `bwtype ":" bandwidth`, digits) | RFC 8866 §5.8 | — |
| 883–892 | `t=` two integers | COVERED (grammar) | RFC 8866 §5.9 | — |
| 969–970, 733–738 | At most two `m=` sections; without `a=group` exactly one | REJECT `parse_sdp-dxe` at every tier: RFC 8866 §5.14 sets no limit, and ST 2110-10 §8.1 binds the device that constructs SDP objects ("Devices ... shall construct one SDP session description ... for each RTP stream (or redundant pair of streams)"), not the content of one object. Each stream in a multi-stream SDP is checked; a file with no stream stays rejected (`st2110-10.m.media-description-required`) | ST 2110-10:2022 §8.1 | — |
| 977–978 | `m=` exactly four tokens, so one format only | REJECT `parse_sdp-ae4` | RFC 8866 §5.14 `fmt *(SP fmt)` | — |
| 983–984 | Media type in {audio, video, text, application, message} | REJECT `parse_sdp-xdg` (existing decision) | RFC 8866 §5.14 "may be extended" | — |
| 986–997 | Port `int` or `int/int`; no range | COVERED (grammar: `port ["/" integer]`); upper bound stays a GUIDE limitation | RFC 8866 §5.14 | — |
| 998–1012 | Any proto; format int or string | COVERED (grammar `proto` token; ST 2110 tier `st2110-10.m.proto-must-be-rtp-avp`) | RFC 8866 §5.14; ST 2110-10:2022 §6.2 | — |
| 1015–1057 | Session-level `c=`, `b=`, `i=`, hkep, privacy, extmap, mediaclk, ts-refclk copied into each media | COVERED: session-level attributes stay at the session level in the doc; checks that need them (`st2110.attr.ts-refclk-required`, source-filter dest cross-check, privacy, hkep) read both levels | RFC 8866 §5 (session-level attributes apply to all media) | — |
| 2020 | Odd RTP port without `a=rtcp` fails (RTP/AVP and TCP/RTP/AVP only) | ADOPT `sdp.m.odd-port-requires-rtcp` (base tier, RTP protos) | RFC 8866 §5.14 "If noncontiguous ports are used or if they don't follow the parity rule of even RTP ports and odd RTCP ports, the "a=rtcp:" attribute MUST be used." | `.7` |
| 2023 | Port count other than 1 with `a=rtcp` fails | REJECT `parse_sdp-8xw` | RFC 3605 §3.2 (informative) | — |
| 2028 | RTCP port defaults to port+1 | NONE: Parse convenience, no check. The IPMX tier has `tr-10-1.a.rtcp.port-must-be-media-port-plus-1` | TR-10-1 §8.7 | — |

## 2. Attribute handlers (`process_session_attribute` 899–927, `process_media_attribute` 929–966)

| Source | Reference behavior | Verdict | Primary citation | Phase |
| --- | --- | --- | --- | --- |
| 903–907 | `a=group`: value required, exactly three tokens, semantics `DUP` | Form COVERED `sdp.a.group.malformed`; DUP-only and two-tags-only: REJECT `parse_sdp-c7j` | RFC 5888 §5 `semantics = "LS" / "FID" / semantics-extension`; RFC 7104 | — |
| 715–731 | DUP mids must resolve to distinct media | COVERED `st2110-10.a.group-dup.mid-resolve`, `st2110-10.a.group-dup.min-2-legs`, `sdp.a.group.requires-mid-on-all-media`, `sdp.a.mid.duplicate-tag` | ST 2110-10:2022 §8.5; RFC 5888 §4, §6 | — |
| 923–924 | `a=charset` rejected at session level | REJECT `parse_sdp-8as` | RFC 8866 §6.10 | — |
| 925–926, 964–965 | Unknown attributes ignored; `recvonly`/`sendonly`/`sendrecv`/`inactive`, FEC and `infoframe` ignored at media level | COVERED: generic attributes pass through; `a=infoframe` and FEC fmtp parameters have IPMX checks (`tr-10-10.a.infoframe.*`, `tr-10-6.a.fmtp.*`) | TR-10-10 §8; TR-10-6 §7.6 | — |
| 1059–1079 | `a=source-filter`: media level only; at least five tokens; mode `incl`; `IN`; `IP4`/`IP6`; first source only; no address checks | Form COVERED `sdp.a.source-filter.malformed` (both levels per RFC 4570 §3); dest COVERED `sdp.a.source-filter.dest-not-in-connections`; `incl`-only: REJECT `parse_sdp-qbr` | RFC 4570 §3, §3.1, Appendix A | — |
| 1081–1125 | `a=rtcp`: one or four tokens; port int; `IN`; `IP4`/`IP6` | COVERED `sdp.a.rtcp.malformed` (RFC 3605 §2.1 ABNF); IPMX `tr-10-1.a.rtcp.port-must-be-media-port-plus-1` | RFC 3605 §2.1; TR-10-1 §8.7 | — |
| 1127–1172 | `a=rtpmap`: rejected when the `m=` format is non-numeric; two tokens; PT ≤ 127 with no lower bound; PT must equal the `m=` format; encoding `/` rate [`/` channels] | Form COVERED `sdp.a.rtpmap.malformed` (PT 0–127 both bounds); PT-must-equal-`m=`: REJECT `parse_sdp-56g`; dynamic PT needs an rtpmap COVERED `sdp.m.rtpmap-required-for-dynamic-pt` | RFC 8866 §6.6, §8.2.3 | — |
| 1151–1155 | Audio rtpmap rate stored as sample rate | NONE: Parse shape only; `parse_sdp` stores `clock_rate` and `channels` for every media type | RFC 8866 §6.6 | — |
| 1213–1264 | `a=ts-refclk`: `local`, `localmac`, `ntp`, `ptp` (`version:gmid[:domain]` or `version:traceable`, no version set, no GMID or domain form check); unknown sources stored with a warning | COVERED and stricter: `sdp.a.ts-refclk.malformed` (RFC 7273 §4.8 clksrc set + `clksrc-ext`), `sdp.a.ts-refclk.ptp-malformed` (EUI-64 GMID), `sdp.a.ts-refclk.traceable-mix`. PTP version token: no closed set (ABNF `ptp-version-ext = token`), so no check. Domain: ADOPT at the ST 2110 tier `st2110-10.a.ts-refclk.ptp-domain-required` (an `IEEE1588-2008` grandmaster must signal the domain; the SHALL is scoped to that version, so `IEEE802.1AS-2011` and other tokens need none) and at the base tier `sdp.a.ts-refclk.ptp-domain-invalid-value` (the form per version token: decimal 0–127 for `IEEE1588-2008`, 1–16 characters 0x21–0x7E for `IEEE1588-2002`, no form for other tokens; amended 2026-10-28, red-team `parse_sdp-1wh`) | RFC 7273 §4.8 ABNF with erratum 4450; ST 2110-10:2022 §8.2 "Devices which are referenced to IEEE Std 1588-2008 shall use the ts-refclk:ptp form, signaling either the grandmaster clockIdentity and domain number, or signaling that the PTP is traceable" (NOTE 1 "the PTP domain number is expressed as a decimal number" is informative); RFC 7273 §4.8 "PTP domain allowed number range: 0-127 (IEEE 1588-2008)", "PTP domain allowed characters: 0x21-0x7E (IEEE 1588-2002)" | `.7` |
| 1266–1311 | `a=mediaclk`: `sender`; `direct` with offset `int()` (negative allowed, no bound) and optional `rate=n[/d]`; unknown types stored with a warning | Form COVERED `sdp.a.mediaclk.malformed` (RFC 7273 §5.4 ABNF, `direct ["=" 1*DIGIT]`, so no sign). ST 2110 tier: ADOPT `st2110-10.a.mediaclk.form-invalid-value` (direct or sender), `st2110-10.a.mediaclk.direct-offset-required`, `st2110-10.a.mediaclk.direct-offset-must-be-zero` | RFC 7273 §5.4; ST 2110-10:2022 §8.3 "the direct reference shall be used and the offset shall be included" / "the following form shall be used: a=mediaclk:sender"; §7.3 "In this standard, the offset value shall be zero." | `.7` |
| 1313–1344 | `a=hkep`: six tokens; port int; `IN`; `IP4`/`IP6`; address, node-id, port-id unchecked; two slots, third dropped | Form COVERED and stricter: `tr-10-5.a.hkep.malformed`, `nettype-invalid-value`, `addrtype-invalid-value`, `node-id-invalid-form`, `port-id-invalid-form`. Two-slot limit: REJECT `parse_sdp-sr4` | TR-10-5 §10 | — |
| 1346–1400 | `a=privacy`: exactly six `;` parts; keys protocol (10 values), mode (16 values), iv 16 hex, key_generator 32 hex, key_version 8 hex, key_id 16 hex; other keys rejected | COVERED: `tr-10-13.a.privacy.malformed`, `*-required` (five keys), `iv-invalid-form`, `key_generator-invalid-form`, `key_version-invalid-form`, `key_id-invalid-form`, `mode-invalid-value`, `protocol-null-forbidden`, `trailing-semicolon`, `dup-legs-must-match`; USB `tr-10-14.a.privacy.usb-protocol-must-be-usb_kv`. Protocol value on RTP blocks: ADOPT `tr-10-13.a.privacy.rtp-protocol-invalid-value` (RTP or RTP_KV) | TR-10-13 §13; §20 "The protocol parameter shall be RTP or RTP_KV." | `.7` |
| 1402–1408 | `a=control` stored raw | NONE: Generic attribute; no check either side | — | — |
| 1410–1448 | `a=extmap`: at least two tokens; id ≤ 256 with no lower bound; direction `sendonly` only; URI unchecked; no duplicate check; eight slots per level | Form COVERED `sdp.a.extmap.malformed` (RFC 8285 §8 ABNF incl. the four directions). ADOPT `sdp.a.extmap.id-out-of-range` (1–256; ids 4096–4351 exempt), `sdp.a.extmap.duplicate-id` (per media section, or session; ids 4096–4351 exempt), `sdp.a.extmap.duplicate-uri` (same URI and attributes twice for one stream; no exemption), `sdp.a.extmap.mixed-levels`. sendonly-only: REJECT `parse_sdp-ocx` (PEP URNs COVERED `tr-10-13.a.extmap.pep-direction-must-be-sendonly`). Eight-slot limit: REJECT `parse_sdp-8gb` | RFC 8285 §4.3 "In the signaling section, the range 1-256 is referred to as the valid range"; §5 "A usable mapping MUST use IDs in the valid range, and each ID in this range MUST be used only once for each media section (or only once if the mappings are session level)", "An extension URI with the same attributes MUST NOT appear more than once applying to the same stream", "The definitions MUST be either all session level or all media level", and mappings that do not conform "MAY be presented, for instance, during SDP Offer/Answer"; §7 "multiple extensions with the same identifier in the extended range 4096-4351 MAY be offered", "identifiers in the range 4096-4351 MAY be offered" | `.7` |
| 1450–1454 | `a=mid` stored raw | COVERED `sdp.a.mid.malformed` (token), `sdp.a.mid.duplicate-tag` | RFC 5888 §4 | — |
| 1456–1464 | `a=setup` role in {active, passive, actpass, holdconn}; not stored | ADOPT `sdp.a.setup.malformed` (known attribute, value set); IPMX USB COVERED `tr-10-14.usb.setup-must-be-passive`, `setup-required` | RFC 4145 §4 `role = "active" / "passive" / "actpass" / "holdconn"` | `.7` |
| 1466–1488 | `a=ptime` / `a=maxptime`: float, non-zero, negative allowed, stored as truncated µs | COVERED `sdp.a.ptime.malformed`, `sdp.a.maxptime.malformed` (`non-zero-int-or-real`, no sign) | RFC 8866 §6.4, §6.5, §9 | — |
| 1490–1500 | `a=framecount` non-zero int | NONE: Not a registered attribute; generic pass-through | — | — |
| 1502–1515 | `a=framerate`: float; a value containing `.` becomes trunc(f·1001+0.5)/1001 | Form COVERED `sdp.a.framerate.malformed`; coercion: REJECT `parse_sdp-0m9` | RFC 8866 §6.13 "Decimal representations of fractional values are allowed." | — |

## 3. `process_fmtp` (1174–1211)

| Source | Reference behavior | Verdict | Primary citation | Phase |
| --- | --- | --- | --- | --- |
| 1175 | fmtp outside a media section rejected | COVERED: RFC 8866 §6.15 usage level media; the grammar accepts a session-level fmtp as an opaque attribute (`library_spec`), which is a GUIDE limitation on usage levels, not a Matrox check | RFC 8866 §6.15 | — |
| 1177–1179 | No space in the value: the whole line is silently ignored | COVERED `sdp.a.fmtp.malformed` (`fmt SP format-specific-params`) | RFC 8866 §6.15 | — |
| 1181–1196 | Format token ≤ 127 (no lower bound) and equal to the single `m=` format | PT 0–127 COVERED (grammar). Format-in-`m=`: ADOPT `sdp.a.fmtp.format-not-in-media` | RFC 8866 §6.15 "The format must be one of the formats specified for the media." | `.7` |
| 1197–1206 | Split on `;`; first `=`; whitespace stripped; names case-folded with `-`/`_` interchangeable; empty value → None (crashes most handlers); trailing `;` gives an empty name (warning only); duplicates: last wins; unknown names warn | COVERED: k=v decomposition, `sdp.a.fmtp.trailing-semicolon` (warn), ST 2110-20 §7.1 separator rules (`st2110-20.a.fmtp.semicolon-without-whitespace`, `no-whitespace-around-equals`, `malformed`). Parameter names compare case-insensitively per decision `parse_sdp-59w`; `-`/`_` are different characters and are not folded. Duplicate keys: no spec rule found; `params_get` returns the first | RFC 8866 §6.15; ST 2110-20:2022 §7.1; RFC 4855 §3 | — |

## 4. `process_parameter_*` fmtp handlers (74 methods, 1518–2011)

Column "Reference" is the value form the handler enforces; "auto-enum" means
any string is accepted.

### 4.1 ST 2110-20 raw video and shared video parameters

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| sampling (1518) | auto-enum | COVERED `st2110-20.a.fmtp.sampling-invalid-value`, `sampling-required`; jxsv `st2110-22.a.fmtp.sampling-invalid-value` | ST 2110-20:2022 §7.2, §7.4.1; RFC 9134 §7.1 | — |
| width, height (1525, 1532) | integer | COVERED `st2110-20.a.fmtp.width/height-invalid-value` (1–32767) and `-required`; `st2110-22.a.fmtp.width/height-*` | ST 2110-20:2022 §7.2; ST 2110-22:2022 §7.2 Table 1 | — |
| depth (1539) | integer | COVERED `st2110-20.a.fmtp.depth-invalid-value` (8, 10, 12, 16, 16f), `depth-required`; `st2110-22.a.fmtp.depth-invalid-value` | ST 2110-20:2022 §7.4.2; RFC 9134 §7.1 | — |
| colorimetry (1546) | auto-enum | COVERED `st2110-20.a.fmtp.colorimetry-invalid-value`, `-required`; `st2110-22.a.fmtp.colorimetry-invalid-value` | ST 2110-20:2022 §7.5; RFC 9134 §7.1 | — |
| RANGE (1553) | auto-enum | COVERED `st2110-20.a.fmtp.RANGE-invalid-value`, `bt2100-range-fullprotect-forbidden`; `st2110-22.a.fmtp.RANGE-invalid-value`, `bt2100-range-fullprotect-forbidden` | ST 2110-20:2022 §7.3; RFC 9134 §7.1 | — |
| exactframerate (1560) | `N` or `N/D` integers; D=0 or negative accepted | COVERED and stricter `st2110-20.a.fmtp.exactframerate-invalid-value` (positive, lowest terms), `-required`; `st2110-22.a.fmtp.exactframerate-invalid-value`; `st2110-40.a.fmtp.exactframerate-*` | ST 2110-20:2022 §7.2 "utilizing the numerically smallest numerator value possible" | — |
| PM (1573) | auto-enum | COVERED `st2110-20.a.fmtp.PM-invalid-value`, `PM-required`, `bpm-with-maxudp-forbidden` | ST 2110-20:2022 §6.3, §7.2 | — |
| SSN (1580) | raw | COVERED `st2110-20.a.fmtp.SSN-invalid-value`, `SSN-required`, `ssn-required-for-2022-only-values`; `st2110-22.a.fmtp.SSN-invalid-value`; `st2110-40.a.fmtp.ssn-*`; `st2110-41.a.fmtp.SSN-*` | ST 2110-20:2022 §7.2; ST 2110-22:2022 §7.2; ST 2110-40:2023 §7; ST 2110-41:2024 §6 | — |
| TP (1590) | auto-enum | COVERED `st2110-20.a.fmtp.TP-invalid-value`, `TP-required`; `st2110-22.a.fmtp.TP-invalid-value`, `TP-required` | ST 2110-21:2022 §8.1; ST 2110-22:2022 §5.3, §7.2 | — |
| interlace, segmented (1616, 1657) | flag; value forbidden | COVERED `st2110-20.a.fmtp.interlace-invalid-value`, `segmented-invalid-value`, `segmented-requires-interlace`; `st2110-22.a.fmtp.interlace/segmented-*` | ST 2110-20:2022 §7.3; RFC 9134 §7.1 | — |
| top-field-first (1610) | flag | NONE: Not a parameter ST 2110-20:2022 defines (no occurrence in the text; §7.3 lists `interlace` and `segmented`). Generic k=v pass-through; no check | ST 2110-20:2022 §7.3 | — |
| PAR (1670) | `W[:H]` integers, 0 accepted, quotes stripped | COVERED `st2110-20.a.fmtp.PAR-invalid-value` | ST 2110-20:2022 §7.3 | — |
| TCS (1684) | auto-enum | COVERED `st2110-20.a.fmtp.TCS-invalid-value` + four `tcs-*-requires-depth-16f`, `key-forbids-tcs`; `st2110-22.a.fmtp.TCS-invalid-value` | ST 2110-20:2022 §7.6, §7.4.1; RFC 9134 §7.1 | — |
| TROFF (1691) | integer | COVERED on smpte291 `st2110-40.a.fmtp.troff-invalid-value`. On raw and jxsv: GUIDE limitation. ADOPT `st2110-21.a.fmtp.troff-invalid-value` for every video block at the ST 2110 tier (the -40 id is a rule-7 misplacement to fold in) | ST 2110-21:2022 §8.2 "may be added to the a=fmtp clause of the SDP for video RTP streams conforming to this standard ... TROFF ... This value is expressed as a positive integer number of microseconds." | `.7` |
| CMAX (1698) | integer | COVERED on jxsv `st2110-22.a.fmtp.CMAX-invalid-value`; raw: ADOPT `st2110-21.a.fmtp.cmax-invalid-value` for every video block (same fold as TROFF) | ST 2110-21:2022 §8.2 "CMAX ... This value is expressed as an integer number." | `.7` |
| MAXUDP (1663) | integer | COVERED `st2110-20.a.fmtp.MAXUDP-invalid-value`, `st2110-22.a.fmtp.MAXUDP-invalid-value`, audio `st2110-30.a.fmtp.maxudp-forbidden`, `st2110-41.a.fmtp.maxudp-forbidden` | ST 2110-10:2022 §6.4; ST 2110-30:2025 §6.2.1 | — |

### 4.2 IPMX parameters

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| IPMX (1584) | flag | COVERED `tr-10-1.a.fmtp.marker-required` | TR-10-1 §10.1 | — |
| chroma-position (1597) | one or two integers | NONE: No TR-10 text on disk defines `chroma-position` as an SDP parameter (TR-10-2 does not list it). Generic k=v pass-through; no check | — | — |
| gamma (1622) | float | NONE: Same: not in TR-10-2. No check | — | — |
| htotal, vtotal, measuredpixclk (1629–1643) | integer | COVERED `tr-10-1.a.fmtp.htotal/vtotal/measuredpixclk-required`, `-invalid-value` | TR-10-1 §10.2 | — |
| measuredsamplerate (1650) | integer | COVERED `tr-10-1.a.fmtp.measuredsamplerate-required`, `-invalid-value` | TR-10-1 §10.3 | — |

### 4.3 ST 2110-22 JPEG XS (`jxsv`)

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| transmode, packetmode (1705, 1713) | int; 0 vs non-zero | COVERED `st2110-22.a.fmtp.transmode-invalid-value`, `packetmode-invalid-value`, `packetmode-required` | RFC 9134 §7.1 | — |
| profile, level, sublevel (1721–1735) | auto-enum | COVERED `st2110-22.a.fmtp.profile/level/sublevel-invalid-value` | RFC 9134 §7.1 | — |
| fbblevel (1742) | auto-enum | NONE: No SDP definition (RTCP Media Info Block field, TR-10-15 Part 1 §12); pass-through. See `spec_conformance/SDPOKER_BACKLOG.md` | TR-10-15 Part 1 §12 | — |

### 4.4 ST 2110-40 and audio

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| DID_SDID (1749) | raw, last wins | COVERED `st2110-40.a.fmtp.did-sdid-invalid-value` (TwoHex form, repeats allowed) | RFC 8331 §4 | — |
| VPID_Code (1753) | integer | COVERED `st2110-40.a.fmtp.vpid-code-invalid-value`, `vpid-code-too-many` | RFC 8331 §4 | — |
| channel-order (1760) | raw | COVERED `st2110-30.a.fmtp.channel-order-invalid`, `st2110-31.a.fmtp.channel-order-aes3-requires-am824` | ST 2110-30:2025 §6.2.2; ST 2110-31:2022 §6.2 | — |
| emphasis (1764) | raw | ADOPT `sdp.a.fmtp.l16.emphasis-invalid-value` (base tier, L16) | RFC 4856 §2.1.15 (audio/L16; RFC 4856 obsoletes RFC 3555 §4.1.15 and keeps the clause): "The only emphasis value defined here is emphasis=50-15" | `.7` |
| TSMODE, TSDELAY (1872, 1879) | auto-enum; int | COVERED `st2110-10.a.fmtp.tsmode-invalid-value`, `tsdelay-invalid-value` | ST 2110-10:2022 §8.7 | — |

### 4.5 AAC: RFC 3640 `mpeg4-generic` and RFC 6416 `MP4A-LATM` (1768–1865, 1886)

Shared fields in the reference; the two registrations are distinct here.

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| streamType (1768) | integer | ADOPT `sdp.a.fmtp.mpeg4-generic.streamType-required`, `-invalid-value` (integer). Value tied to media type: REJECT `parse_sdp-rt3` | RFC 3640 §4.1 "Required parameters: ... streamType: The integer value that indicates the type of MPEG-4 stream" | `.5` |
| profile-level-id (1886, decoded at 2492) | raw; decoded as decimal | ADOPT `sdp.a.fmtp.mpeg4-generic.profile-level-id-required`, `-invalid-value` (decimal integer); MP4A-LATM `sdp.a.fmtp.mp4a-latm.profile-level-id-invalid-value` (optional, default 30) | RFC 3640 §4.1 "A decimal representation of the MPEG-4 Profile Level indication"; RFC 6416 §7.3 (MP4A-LATM optional parameters) | `.5` |
| config (1779) | raw | ADOPT `sdp.a.fmtp.mpeg4-generic.config-required`, `-invalid-value` (hex octet string or quoted empty `""`); MP4A-LATM `sdp.a.fmtp.mp4a-latm.config-invalid-value` | RFC 3640 §4.1 "config: A hexadecimal representation of an octet string"; RFC 6416 §7.3 | `.5` |
| mode (1775) | raw | ADOPT `sdp.a.fmtp.mpeg4-generic.mode-required` (value set open: REJECT `parse_sdp-rt3`) | RFC 3640 §4.1 "Required parameters: ... mode" and "Other modes are expected to be defined in future RFCs" | `.5` |
| objectType (1791) | integer | ADOPT `sdp.a.fmtp.mpeg4-generic.objectType-invalid-value` (decimal) | RFC 3640 §4.1 "The decimal value from Table 8 in ISO/IEC 14496-1" | `.5` |
| object (1798) | integer | ADOPT `sdp.a.fmtp.mp4a-latm.object-invalid-value` (decimal) | RFC 6416 §7.3 "a decimal representation of the MPEG-4 Audio Object Type" | `.5` |
| cpresent (1783) | int → bool | ADOPT `sdp.a.fmtp.mp4a-latm.cpresent-invalid-value` (0 or 1), `sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0` | RFC 6416 §7.3 "A 0 indicates the configuration data has not been multiplexed into an RTP payload, and in that case, the "config" parameter MUST be present" | `.5` |
| bitrate (1865) | integer | REJECT `parse_sdp-cad`: §7.3 states no syntax | RFC 6416 §7.3 "the data rate for the audio bitstream" | — |
| constantDuration, maxDisplacement, de-interleaveBufferSize (1801–1815) | integer | ADOPT `-invalid-value` (decimal) for each | RFC 3640 §4.1 | `.5` |
| sizeLength, indexLength, indexDeltaLength (1822–1836) | integer | ADOPT `-invalid-value` (integer); `sdp.a.fmtp.mpeg4-generic.aac-mode-requires-size-and-index-lengths` for `mode=AAC-hbr` / `AAC-lbr`; `sdp.a.fmtp.mpeg4-generic.constantSize-sizeLength-exclusive`. Zero rejected by the reference: REJECT `parse_sdp-rt3` | RFC 3640 §3.3.5 / §3.3.6 "the following parameters MUST be present: sizeLength, indexLength, and indexDeltaLength"; §4.1 "The sizeLength and the constantSize parameters MUST NOT be simultaneously present" | `.5` |
| CTSDeltaLength, DTSDeltaLength (1843, 1850) | integer | ADOPT `-invalid-value` (integer) | RFC 3640 §4.1 | `.5` |
| randomAccessIndication (1857) | int → bool | ADOPT `-invalid-value` (0 or 1) | RFC 3640 §4.1 "A decimal value of zero or one" | `.5` |
| streamStateIndication, auxiliaryDataSizeLength, constantSize | not handled | ADOPT `-invalid-value` (integer); `streamStateIndication` with `streamType` 4 (VisualStream) or 5 (AudioStream), the ISO/IEC 14496-1 Table 9 values, not by the `m=` media type: `sdp.a.fmtp.mpeg4-generic.streamStateIndication-forbidden` (amended 2026-10-28; the RFC's §3.3.2 example has `streamStateIndication` on an `m=video` block with `streamtype=3`) | RFC 3640 §4.1 "SHALL NOT be present for MPEG-4 audio and MPEG-4 video streams" | `.5` |
| rate (rtpmap clock) | — | NONE: No closed value: RFC 3640 §3.1 "the rate SHOULD be set to the same value as the sampling rate" (SHOULD); RFC 6416 "Other rates MAY be indicated". No check | RFC 3640 §3.1; RFC 6416 §7.3 | — |

### 4.6 H.264, RFC 6184 (1886–1925)

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| rtpmap clock rate | checked in `check_sdp_rfc6184` | ADOPT `sdp.a.rtpmap.h264.clock-rate-must-be-90000` | RFC 6184 §8.2.1 "The clock rate in the "a=rtpmap" line MUST be 90000." | `.3` |
| profile-level-id (1886, decoded 2037) | raw; hex decode later | ADOPT `sdp.a.fmtp.h264.profile-level-id-invalid-value` (six hex digits); `decode_h264_profile_level_id` helper | RFC 6184 §8.1 "A base16 [7] (hexadecimal) representation of the following three bytes" | `.3` |
| sprop-parameter-sets (1890) | raw | ADOPT `-invalid-value` (comma-separated base64) | RFC 6184 §8.1 "a comma-separated (',') list of base64 [7] representations of parameter set NAL units" | `.3` |
| packetization-mode (1894) | int in {0,1,2} | ADOPT `-invalid-value` | RFC 6184 §8.1 "The value of packetization-mode MUST be an integer in the range of 0 to 2, inclusive." | `.3` |
| sprop-interleaving-depth (1904) | integer | ADOPT `-forbidden-in-mode` (absent, 0 or 1), `-required` (mode 2), `-invalid-value` (0–32767) | RFC 6184 §8.1 "This parameter MUST NOT be present when packetization-mode is not present or the value of packetization-mode is equal to 0 or 1. This parameter MUST be present when the value of packetization-mode is equal to 2." / "MUST be an integer in the range of 0 to 32767, inclusive." | `.3` |
| sprop-deint-buf-req (1911) | integer | ADOPT `-forbidden-in-mode`, `-required` (mode 2), `-invalid-value` (0–4294967295) | RFC 6184 §8.1 (same wording as above; "0 to 4294967295, inclusive") | `.3` |
| sprop-init-buf-time (1918) | integer | ADOPT `-forbidden-in-mode` (0 or 1), `-invalid-value` (0–4294967295) | RFC 6184 §8.1 "The parameter MUST NOT be present if the value of packetization-mode is equal to 0 or 1." | `.3` |
| sprop-max-don-diff (1925) | integer | ADOPT `-forbidden-in-mode` (0 or 1), `-invalid-value` (0–32767) | RFC 6184 §8.1 "The parameter MUST NOT be present if the value of packetization-mode is equal to 0 or 1. sprop-max-don-diff is an integer in the range of 0 to 32767, inclusive." | `.3` |
| max-mbps, max-smbps, max-fs, max-cpb, max-dpb, max-br, max-rcmd-nalu-size, deint-buf-cap (not handled) | — | ADOPT `-invalid-value` (integer form; `deint-buf-cap` 0–4294967295). Level-table comparison: REJECT `parse_sdp-aif` | RFC 6184 §8.1 | `.3` |
| redundant-pic-cap, level-asymmetry-allowed, use-level-src-parameter-sets, in-band-parameter-sets, sar-understood, sar-supported, max-recv-level, sprop-level-parameter-sets (not handled) | — | ADOPT `-invalid-value` (0/1 for the four flags; hex for max-recv-level; integer for sar-*); `in-band-parameter-sets=1` with `use-level-src-parameter-sets` present and not 0: `sdp.a.fmtp.h264.use-level-src-parameter-sets-forbidden-with-in-band` | RFC 6184 §8.1 "The value of redundant-pic-cap MUST be either 0 or 1"; "When in-band-parameter-sets is equal to 1, use-level-src-parameter-sets MUST NOT be present or MUST be equal to 0" | `.3` |

### 4.7 H.265, RFC 7798 (1932–2009)

| Parameter (line) | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| rtpmap clock rate | checked in `check_sdp_rfc7798` | ADOPT `sdp.a.rtpmap.h265.clock-rate-must-be-90000` | RFC 7798 §7.2.1 "The clock rate in the "a=rtpmap" line MUST be 90000." | `.4` |
| profile-space, profile-id (1932, 1939) | integer | ADOPT `-invalid-value` (0–3; 0–31) | RFC 7798 §7.1 "The value of profile-space MUST be in the range of 0 to 3, inclusive. The value of profile-id MUST be in the range of 0 to 31, inclusive." | `.4` |
| tier-flag, level-id (1946, 1954) | int; int | ADOPT `-invalid-value` (0–1; 0–255) | RFC 7798 §7.1 "The value of tier-flag MUST be in the range of 0 to 1, inclusive. The value of level-id MUST be in the range of 0 to 255, inclusive." | `.4` |
| interop-constraints (1961) | raw | ADOPT `-invalid-value` (12 hex digits); `decode_h265_profile` helper | RFC 7798 §7.1 "A base16 [RFC4648] (hexadecimal) representation of six bytes of data" | `.4` |
| profile-compatibility-indicator (1965) | raw | ADOPT `-invalid-value` (8 hex digits) | RFC 7798 §7.1 "A base16 [RFC4648] representation of four bytes of data." | `.4` |
| tx-mode (1969) | strict enum against a global table | ADOPT `-invalid-value` (SRST, MRST, MRMT) | RFC 7798 §7.1 "The value of tx-mode MUST be equal to "SRST", "MRST" or "MRMT"." | `.4` |
| sprop-vps, sprop-sps, sprop-pps (1976–1984), sprop-sei (not handled) | raw | ADOPT `-invalid-value` (comma-separated base64) | RFC 7798 §7.1 "comma-separated (',') list of base64 [RFC4648] representations" | `.4` |
| sprop-max-don-diff (1925, shared) | integer | ADOPT `-invalid-value` (0–32767) | RFC 7798 §7.1 "The value of sprop-max-don-diff MUST be an integer in the range of 0 to 32767, inclusive." | `.4` |
| sprop-depack-buf-nalus (1988) | integer | ADOPT `-invalid-value` (0–32767), `-required-when-max-don-diff` (present and > 0) | RFC 7798 §7.1 "When sprop-max-don-diff is present and greater than 0, this parameter MUST be present and the value MUST be greater than 0." | `.4` |
| sprop-depack-buf-bytes (1995) | integer | ADOPT `-invalid-value` (0–4294967295), `-required-when-max-don-diff` | RFC 7798 §7.1 (same wording) | `.4` |
| sprop-segmentation-id (2002) | integer | ADOPT `-invalid-value` (0–3) | RFC 7798 §7.1 "The value of sprop-segmentation-id MUST be an integer in the range of 0 to 3, inclusive." | `.4` |
| sprop-spatial-segmentation-idc (2009) | raw | ADOPT `-invalid-value` (hex) | RFC 7798 §7.1 "A base16 [RFC4648] representation of the syntax element min_spatial_segmentation_idc" | `.4` |
| sprop-sub-layer-id, recv-sub-layer-id, max-recv-level-id, depack-buf-cap, max-lsr, max-lps, max-cpb, max-dpb, max-br, max-tr, max-tc, max-fps, dec-parallel-cap, include-dph (not handled) | — | ADOPT `-invalid-value` (0–6; 0–6; 0–255; 1–4294967295; integer; integer; integer; 1–16; integer; integer; integer; integer; form per §7.1). Level-table comparisons: covered by `parse_sdp-aif` reasoning (ITU-T tables) | RFC 7798 §7.1 | `.4` |

### 4.8 MPEG-2 TS, RFC 2250 (no fmtp handlers)

| Item | Reference | Verdict | Citation | Phase |
| --- | --- | --- | --- | --- |
| rtpmap clock rate | `check_sdp_rfc2250` 332 | ADOPT `sdp.a.rtpmap.mp2t.clock-rate-must-be-90000` | RFC 2250 §2 "timestamp: 32 bit 90K Hz timestamp representing the target transmission time"; RFC 3551 Table 5 "33 MP2T AV 90,000" | `.6` |
| media type must be video | 326 | REJECT without bead: RFC 3551 Table 5 registers MP2T under media type "AV" (audio or video); RFC 3555 §4.2.9 registers `video/MP2T`. An `m=audio` MP2T is within RFC 3551. No check | RFC 3551 §5.7, Table 5 | — |
| fmtp parameters | none | NONE: RFC 3555 §4.2.9 "Required parameters: None. Optional parameters: None." No check | RFC 3555 §4.2.9 | — |

## 5. `MatroxSdpCheck.py` conditions (19 functions, 119 raise sites)

### 5.1 `check_sdp_rfc4175` (27–69), video/raw

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 30, 33 | media type video; encoding raw | COVERED `st2110-20.a.rtpmap.raw-media-type` (ST 2110 tier) | ST 2110-20:2022 §7.1 |
| 36 | clock rate non-zero | COVERED `st2110-20.a.rtpmap.raw-clock-rate` (90000) | ST 2110-20:2022 §7.1 |
| 46, 52, 55, 58, 65 | sampling, width (≤ 32767), height, depth, colorimetry present and in range | COVERED at the ST 2110 tier (`st2110-20.a.fmtp.*-required`, `width/height-invalid-value`). Base-tier RFC 4175 registration: follow-up feature `parse_sdp-6pj` | ST 2110-20:2022 §7.2; RFC 4175 §6 |

### 5.2 `check_sdp_rfc9134` (71–127), video/jxsv

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 74, 77, 80 | video; jxsv; 90000 | COVERED `st2110-22.a.rtpmap.jxsv-media-type`, `jxsv-clock-rate` | ST 2110-22:2022 §5.2, §6.2 |
| 84, 90 | packetmode present and valid; transmode valid | COVERED `st2110-22.a.fmtp.packetmode-required`, `packetmode-invalid-value`, `transmode-invalid-value` | RFC 9134 §7.1 |
| 93, 96 | width/height ≤ 32767 when present | COVERED `st2110-22.a.fmtp.width/height-invalid-value` (and `-required`) | ST 2110-22:2022 §7.2 |
| 99 | segmented without interlace | COVERED `st2110-22.a.fmtp.segmented-requires-interlace` | RFC 9134 §7.1 |
| 108, 117, 121 | sampling, colorimetry, TCS sets | COVERED `st2110-22.a.fmtp.sampling/colorimetry/TCS-invalid-value` | RFC 9134 §7.1 |
| 124 | FULLPROTECT with BT2100 | COVERED `st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden` | RFC 9134 §7.1 |

### 5.3 `check_sdp_rfc3551` (129–146), L8/L16/L20/L24/AM824

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 132, 136 | audio; encoding in the set | COVERED for AM824 `st2110-31.a.rtpmap.am824-media-type`; `L*` on `m=video` has no RFC 3551 prohibition (the registrations are `audio/L16`, so ADOPT is possible but no Matrox-parity gap: the reference only checks the chain it chose). No check | RFC 3551 §4.5.x |
| 139 | sample rate non-zero | COVERED (grammar `clock-rate = integer`; AM824 `am824-clock-rate-set`) | RFC 8866 §6.6; ST 2110-31:2022 §6.1 |
| 145 | emphasis must be `50-15` | ADOPT `sdp.a.fmtp.l16.emphasis-invalid-value` (see §4.4) | RFC 4856 §2.1.15 |

### 5.4 `check_sdp_rfc3640` (148–192), mpeg4-generic

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 151, 154, 157 | audio; encoding; sample rate | NONE: Encoding/clock: no closed rule (RFC 3640 §3.1 SHOULD). No check | RFC 3640 §3.1 |
| 163 | streamType must be 5 | REJECT `parse_sdp-rt3` | RFC 3640 §4.1 |
| 166, 173 | profile-level-id present; decimal; not 0, 254, 255 | ADOPT `-required`, `-invalid-value` (decimal). Exclusions: REJECT `parse_sdp-rt3` | RFC 3640 §4.1 |
| 176 | config present | ADOPT `sdp.a.fmtp.mpeg4-generic.config-required` | RFC 3640 §4.1 Required parameters |
| 182 | mode equals the literal `AAC=hbr` (typo; never a real value) | REJECT `parse_sdp-rt3`; reported as a reference defect in §9 | RFC 3640 §4.1 |
| 185, 187, 189 | sizeLength, indexLength, indexDeltaLength non-zero | Presence for AAC modes ADOPT; non-zero REJECT `parse_sdp-rt3` | RFC 3640 §3.3.5, §3.3.6, §4.1 |
| 191 | constantDuration 0 with maxDisplacement > 0 | REJECT: the clause is "when interleaving in this mode, this specific duration MUST be signaled by the MIME format parameter constantDuration", conditioned on interleaving, which the SDP does not state; `maxDisplacement` presence is not defined as the signal. Noted in `parse_sdp-rt3` | RFC 3640 §3.3.6 |

### 5.5 `check_sdp_rfc6416` (194–214), MP4A-LATM

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 197, 201, 204 | audio; encoding LATM/ADTS; sample rate | NONE: No closed rule. No check | RFC 6416 §7.3 |
| 213 | cpresent=0 without config | ADOPT `sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0` | RFC 6416 §7.3 |

### 5.6 `check_sdp_rfc8331` (216) stub, no rows

### 5.7 `check_sdp_rfc6184` (221–257), H264

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 224, 227 | video; H264 | ADOPT `sdp.a.rtpmap.h264.media-type-must-be-video` | RFC 6184 §8.2.1 "The media name in the "m=" line of SDP MUST be video." |
| 230 | clock 90000 | ADOPT (§4.6) | RFC 6184 §8.2.1 |
| 238 | profile-level-id hex | ADOPT (§4.6) | RFC 6184 §8.1 |
| 241 | packetization-mode 0–2 | ADOPT | RFC 6184 §8.1 |
| 245–251 | interleaving-depth, deint-buf-req, init-buf-time, max-don-diff non-zero in mode 0/1 | ADOPT as presence rules (the RFC forbids presence, not non-zero values; the reference accepts `=0`, see §9) | RFC 6184 §8.1 |
| 254, 256 | interleaving-depth, max-don-diff ≤ 32767 in mode 2 | ADOPT (range applies in every mode where present) | RFC 6184 §8.1 |

### 5.8 `check_sdp_rfc7798` (259–321), H265

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 262, 265 | video; H265 | ADOPT `sdp.a.rtpmap.h265.media-type-must-be-video` | RFC 7798 §7.2.1 "The media name in the "m=" line of SDP MUST be video." |
| 268 | clock 90000 | ADOPT (§4.7) | RFC 7798 §7.2.1 |
| 271, 274 | profile-space ≤ 3; profile-id ≤ 31 | ADOPT | RFC 7798 §7.1 |
| 288, 296, 320 | interop-constraints, profile-compatibility-indicator, spatial-segmentation-idc hex | ADOPT | RFC 7798 §7.1 |
| 302, 305 | max-don-diff, depack-buf-nalus ≤ 32767 | ADOPT | RFC 7798 §7.1 |
| 308, 311 | max-don-diff > 0 with depack-buf-nalus or depack-buf-bytes 0 | ADOPT `-required-when-max-don-diff` (presence and > 0) | RFC 7798 §7.1 |
| 314 | segmentation-id ≤ 3 | ADOPT | RFC 7798 §7.1 |

### 5.9 `check_sdp_rfc2250` (323–333), MP2T

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 326, 329 | video; MP2T | REJECT (§4.8, media type "AV") | RFC 3551 Table 5 |
| 332 | clock 90000 | ADOPT (§4.8) | RFC 2250 §2 |

### 5.10 `check_sdp_st2110_10` (335–352)

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 338, 348 | mediaclk and ts-refclk present | COVERED `st2110.attr.mediaclk-required`, `st2110.attr.ts-refclk-required` | ST 2110-10:2022 §8.3, §8.2 |
| 342 | non-IPMX: mediaclk must be direct with offset 0 | REJECT `parse_sdp-e74` (sender is permitted). ADOPT the two real SHALLs: `st2110-10.a.mediaclk.form-invalid-value`, `direct-offset-required`, `direct-offset-must-be-zero` (§2) | ST 2110-10:2022 §8.3, §7.3 |
| 345 | IPMX: mediaclk sender or direct=0 | NONE: Same ids via composition; TR-10-1 §10.5 repeats the two SHALLs | TR-10-1 §10.5 |
| 351 | MAXUDP default 1460 | NONE: No check (a default, see §6) | ST 2110-10:2022 §6.3 |

### 5.11 `check_sdp_st2110_20` (354–434)

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 357–363 | video; raw; 90000 | COVERED `st2110-20.a.rtpmap.raw-media-type`, `raw-clock-rate` | ST 2110-20:2022 §7.1 |
| 372 | sampling required and in set | COVERED | ST 2110-20:2022 §7.2, §7.4.1 |
| 375 | depth in {8, 10, 12, 16} | COVERED `depth-invalid-value`; the reference omits `16f` (§9) | ST 2110-20:2022 §7.4.2 |
| 378, 381 | width, height 1–32767 | COVERED | ST 2110-20:2022 §7.2 |
| 384 | exactframerate numerator/denominator non-zero | COVERED `exactframerate-invalid-value` | ST 2110-20:2022 §7.2 |
| 395 | PM in {2110GPM, 2110BPM} | COVERED `PM-invalid-value` | ST 2110-20:2022 §6.3 |
| 402 | SSN 2017 with ST2115LOGS3 or ALPHA | COVERED `ssn-required-for-2022-only-values` | ST 2110-20:2022 §7.2 |
| 405, 408 | SSN 2021 / 2022 without LOGS3 or ALPHA | REJECT `parse_sdp-m0w` (existing decision, reverse direction). `ST2110-20:2021` is not a value §7.2 defines; COVERED `SSN-invalid-value` rejects it (§9) | ST 2110-20:2022 §7.2 |
| 410 | SSN required and in set | COVERED `SSN-required`, `SSN-invalid-value` | ST 2110-20:2022 §7.2 |
| 421 | TCS set | COVERED `TCS-invalid-value` | ST 2110-20:2022 §7.6 |
| 424 | FULLPROTECT with BT2100 | COVERED `bt2100-range-fullprotect-forbidden` | ST 2110-20:2022 §7.3 |

### 5.12 `check_sdp_st2110_21` (436–444)

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 443 | TP in {2110TPN, 2110TPNL, 2110TPW}, required | COVERED `st2110-20.a.fmtp.TP-required`, `TP-invalid-value`; `st2110-22.a.fmtp.TP-*` | ST 2110-21:2022 §8.1 |

### 5.13 `check_sdp_st2110_22` (446–480)

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 449, 452, 455 | video; not raw; 90000 | COVERED for jxsv; for other compressed encodings the 90 kHz rule applies where ST 2110-22 applies (decision `parse_sdp-59w`, amended 2026-10-28): ADOPT `st2110-22.a.rtpmap.clock-rate-must-be-90000` for SSN=ST2110-22 blocks at every tier. The IPMX tier no longer treats every other `m=video` block as an ST 2110-22 stream: TR-10-7 §10 and TR-10-11 §10 bind devices "compliant with this TR", TR-10-0 is descriptive, and TR-10-1 §10 defers to "the SMPTE ST 2110 standards suite as they apply to each specific media format"; nothing in the SDP says a plain H264 / H265 / MP2T / VP9 block is one of those streams | ST 2110-22:2022 §5.2 "The RTP Timestamp Clock rate shall be 90 kHz."; TR-10-11 §9 "The Media Clock and RTP Clock rate for streams compliant with this TR shall be 90 kHz." |
| 458, 461 | width, height required, 1–32767 | COVERED for jxsv; ADOPT for the other ST 2110-22-applicable blocks via the same ids | ST 2110-22:2022 §7.2 Table 1 |
| 469 | TP set depends on SSN year: 2110TPN only with ST2110-22:2022 | ADOPT `st2110-22.a.fmtp.tp-2110tpn-requires-ssn-2022` (`spec_ref` ST 2110-22:2019 §5.3) | ST 2110-22:2019 §5.3 "The session description shall include a format-specific parameter of either TP=2110TPNL or TP=2110TPW", §7.2 Table 1 "TP: Either 2110TPNL or 2110TPW as specified in section 5.3"; ST 2110-22:2022 §7.2 Table 2 "SSN ... depending on the version of the standard implemented" |
| 472 | b=AS non-zero | COVERED `st2110-22.b.as-required`, `as-invalid-value` (positive integer) for jxsv; ADOPT for the other applicable blocks | ST 2110-22:2022 §7.3 Table 3; TR-10-7 §10 Table 1 (the section heading is lost in the markdown conversion; the clause follows §9) "The `<brvalue>` shall be the maximum target bit rate of the encoded media stream" |
| 475 | framerate or exactframerate present | ADOPT `st2110-22.framerate-indication-required` | ST 2110-22:2022 §7.4 "The SDP object shall include an indication of frame rate via one of the mechanisms listed in Table 4." |

### 5.14 `check_sdp_st2110_30` (482–516)

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 485, 489, 492 | audio; L8/L16/L20/L24; sample rate | NONE: No closed SDP rule in ST 2110-30 beyond AES67; grammar covers the rtpmap form. No check | ST 2110-30:2025 §6.2 |
| 495 | channel-order required with `SMPTE2110.` prefix | REJECT `parse_sdp-hsm`; value form COVERED `channel-order-invalid` | ST 2110-30:2025 §6.2.2 |
| 498 | ptime present | ADOPT `st2110-30.a.ptime-required` | ST 2110-30:2025 §6.2 "shall conform to AES67, including the Session Description Protocol (SDP)"; AES67-2013 §8.1 "Descriptions shall include a ptime attribute indicating the desired packet time." (the 2013 edition is the one on disk; ST 2110-31:2022 Note 2 cites the same clause number in AES67:2018) |
| 502, 505 | ptime in a value set; maxptime in the set and ≥ ptime | REJECT `parse_sdp-wgo` | AES67 §8.1 "Values outside those enumerated in table 4 shall be correctly interpreted." |
| 508 | ts-refclk present | COVERED `st2110.attr.ts-refclk-required` | ST 2110-10:2022 §8.2 |
| 512, 515 | mediaclk direct (non-IPMX) / sender or direct (IPMX) | NONE: As §5.10 | ST 2110-10:2022 §8.3 |

### 5.15 `check_sdp_st2110_31` (518–548), AM824

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 521, 524 | audio; AM824 | COVERED `st2110-31.a.rtpmap.am824-media-type` | ST 2110-31:2022 §6.1 |
| 527 | sample rate in {44100, 48000, 96000} | COVERED `am824-clock-rate-set` | ST 2110-31:2022 §6.1 |
| 530 | channel count even | COVERED `am824-channels-must-be-even`, `am824-channels-required` | ST 2110-31:2022 §6.1 |
| 533 | channel-order prefix when present | COVERED `st2110-31.a.fmtp.channel-order-aes3-requires-am824`, `st2110-30.a.fmtp.channel-order-invalid` | ST 2110-31:2022 §6.2 |
| 537 | ptime present and in the Table 1 set for the clock rate | ADOPT `st2110-31.a.ptime-required`, `st2110-31.a.ptime-invalid-value` | ST 2110-31:2022 §6.1 "Senders under this standard shall signal a ptime attribute in the SDP" and "The `<packet-time>` parameter shall take one of the values from the Table 1, based on the prevailing sampling rate" |
| 540–547 | ts-refclk, mediaclk | NONE: As §5.10 | ST 2110-10:2022 §8.2, §8.3 |

### 5.16–5.18 `check_sdp_st2110_40`, `check_sdp_ipmx`, `check_sdp_nmos` stubs, no rows

### 5.19 `check_sdp_ipmx_usb` (564–576)

| Line | Condition | Verdict | Citation |
| --- | --- | --- | --- |
| 567, 570, 573 | application; usb; TCP | COVERED: the USB block shape (`m=application <port> TCP usb`) selects the `tr-10-14.usb.*` checks; `tr-10-14.usb.setup-required`, `setup-must-be-passive` | TR-10-14 §14 |

## 6. Defaults the checker writes (claims about specification defaults)

A default written into a descriptor is not a check. Each is compared with the
text to see whether the reference's assumed default matches the specification.

| Line | Default | Text | Agrees? |
| --- | --- | --- | --- |
| 88 | transmode absent → sequential | RFC 9134 §7.1: transmode default 1 (sequential) | yes |
| 126 | RANGE absent → NARROW (FULL if colorimetry UNSPECIFIED) | RFC 9134 §7.1 RANGE default NARROW; the UNSPECIFIED special case is not in RFC 9134 | partly |
| 142, 160, 207 | channels absent → 1 | RFC 8866 §6.6 "may be omitted if the number of channels is one" | yes |
| 179 | `config=""` → empty | RFC 3640 §4.1 quoted empty string | yes |
| 210 | LATM profile-level-id absent → 30 | RFC 6416 §7.3 "default value of 30 (Natural Audio Profile/Level 1)" | yes |
| 233 | H.264 profile-level-id absent → 42000A | RFC 6184 §8.1 "If the profile-level-id parameter is not present, the Baseline profile, no additional constraints at Level 1, MUST be inferred" (0x42, 0x00, 0x0A) | yes |
| 277 | H.265 profile-id 0 → 1 | RFC 7798 §7.1: absent → 1; **0 is a legal value** (range 0–31) | no (§9) |
| 280 | H.265 level-id 0 → 93 | RFC 7798 §7.1: absent → 93; **0 is a legal value** (range 0–255) | no (§9) |
| 283 | interop-constraints absent → B00000000000 | RFC 7798 §7.1: progressive_source_flag=1, interlaced=0, non_packed=1, frame_only=1 inferred (0xB0 leading byte) | yes |
| 291 | profile-compatibility-indicator absent → 1 << profile-id | RFC 7798 §7.1 inference rule for flag j = profile-id | yes |
| 299 | tx-mode absent → SRST | RFC 7798 §7.1 "When not present, the value of tx-mode is inferred to be equal to "SRST"" | yes |
| 351, 429 | MAXUDP absent → 1460 | ST 2110-10:2022 §6.3 "The Standard UDP Size Limit shall be 1460 octets", §8.6 "If the MAXUDP parameter is not present, Receivers shall assume the Standard UDP Size Limit" | yes |
| 419 | TCS absent → SDR | ST 2110-20:2022 §7.6 (TCS optional, default SDR) | yes |
| 426 | RANGE absent → NARROW | ST 2110-20:2022 §7.3 | yes |
| 432 | PAR 0 → 1:1 | ST 2110-20:2022 §7.3 (PAR optional, default 1:1); 0 is not a permitted value, see `PAR-invalid-value` | partly |
| 478 | exactframerate absent → copied from framerate | ST 2110-22:2022 §7.4 Table 4 (either mechanism) | convenience |

## 7. Profile and level decoders (2037–2673)

All three are parse conveniences, never checks. `parse_sdp` adds the two
helpers the brief names, written from the RFC bit layouts:

| Reference | Verdict | Notes |
| --- | --- | --- |
| `get_h264_profile_level_from_sdp` (2037–2157) | ADOPT `sdp.decode_h264_profile_level_id(hex)` → `{ profile_idc, profile_iop, level_idc, constraint_set0..5, level, profile }` | Profile and level names follow ITU-T H.264 Annex A. The reference ignores constraint_set3 for level 1b/1.1 and reports `42e0xx` as plain Baseline (§9). Phase `.3` |
| `get_h265_profile_level_from_sdp` (2160–2489) | ADOPT `sdp.decode_h265_profile(params)` → `{ profile_space, profile_id, tier, level, general_profile_compatibility_flags, interop flags, profile }` | Phase `.4` |
| `get_aac_profile_level_from_sdp` (2492–2673) | REJECT without a bead: the mapping is ISO/IEC 14496-3 Table 1.14 (audioProfileLevelIndication), not an IETF or SMPTE source this library quotes. The decimal value is kept as parsed | — |

## 8. `IpmxSdpTest.py` and `SdpToCapabilities.py`

### 8.1 SDP-only checks

| Test / line | Condition | Verdict |
| --- | --- | --- |
| test_02 415, test_03 733 | IPMX marker in fmtp | COVERED `tr-10-1.a.fmtp.marker-required` |
| test_02 479 | measuredpixclk, htotal, vtotal non-zero | COVERED `tr-10-1.a.fmtp.*-required`, `-invalid-value` |
| test_02 486, test_03 822 | mediaclk sender or direct | ADOPT (§2, ST 2110-10 §8.3 / TR-10-1 §10.5) |
| test_02 524 (part) | clock 90000 | COVERED per encoding (raw, jxsv); ADOPT H264/H265 (base) and ST 2110-22 applicability |
| test_02 557–618, test_03 883–909 | per-encoding check chains | NONE: Per §5 |
| test_02 620, test_03 912 | unknown media type fails | OUT OF SCOPE: the Flow's media type is IS-04 |
| test_03 761–773 | encoding in {L8, L16, L20, L24, AM824} | OUT OF SCOPE: the test enumerates the IS-04 media types it tests, not an SDP rule |
| test_03 817 | measuredsamplerate non-zero | COVERED `tr-10-1.a.fmtp.measuredsamplerate-*` |
| test_14 2750 | `check_sdp_ipmx_usb` | COVERED (§5.19) |

### 8.2 Checks against IS-04 / IS-05 (OUT OF SCOPE, no bead)

test_02 425, 440, 446, 459–476, 492–519, 524, 534, 542, 552; test_03 757,
775, 782, 796, 810, 828–855, 860, 868, 878; test_14 2651, 2703–2730, 2735,
2744. Each compares the SDP with a Flow, Source, Node clock or IS-05 leg.
The SDP does not carry that state (CLAUDE.md "What the library validates").

#### 8.2a Other files that read the parsed SDP (reviewed 2026-10-28, no rows)

These were outside the brief's list and were read afterwards. None adds a
check on the SDP object:

- `IpmxSdpTest.py` `test_11` (2212–2423), `test_101` (1445–1794),
  `test_102` (1794–2111): decode the SDP and compare its `c=`, port and
  `source-filter` addresses with the IS-05 transport parameters
  (OUT OF SCOPE, as §8.2). `test_11` also requires the IS-05 destination
  port to be 5004 and the destination to be a `239.S.C.D` address with S
  in 1–127 and C.D equal to the source's; both run on the IS-05
  parameters, not the SDP. The address rule is TR-10-9 v2 §17.1, a default
  ("When no user defined value is provided, IPMX Senders shall use the
  following method to assign a default IPv4 multicast address", with "A
  method shall be provided for a user to change this default value"), so
  an SDP cannot show whether it applies. No TR-10 markdown on disk carries
  a 5004 clause.
- `BCP0060201Test.py` (427, 448, 943–960) and `BCP0060301Test.py` (453,
  477, 978–1000): decode `profile-level-id` / `packetization-mode` (H.264)
  and `profile-id`, `profile-space`, `profile-compatibility-indicator`,
  `sprop-max-don-diff` (H.265) and compare them with the IS-04 Flow's
  `profile`, `level` and `packet_transmission_mode` (OUT OF SCOPE).
- `IS0501Test.py` (128, 615, 663, 711): `IS05Utils.check_sdp_matches_params`,
  an IS-05 comparison (OUT OF SCOPE).
- `tests/test_sdp_to_capabilities.py`: ten inline fixtures asserting
  capability conversion (`CapFormat*`), not validation; the features they
  use (raw, L24, smpte291, MP2T DUP, IPMX marker, fractional frame rate)
  are all in `examples/`. `tests/test_flow_to_capabilities.py` does not
  read SDP.

## 8.3 `SdpToCapabilities._verify_capabilities_identical` (141–173)

Compares the capability sets built from the two DUP legs: same capability
names; per capability the same type, min, max and enumerated values. The
conversion uses only format-level fields (media type, rtpmap, fmtp-derived
video/audio parameters). COVERED by `st2110-10.a.group-dup.media-type-same`,
`rtpmap-same`, `payload-type-same`, `fmtp-same` (ST 2110-10:2022 §8.5 via
ST 2022-7 §6), which compare the raw attributes rather than a derived
capability set and therefore catch every difference the conversion would.

## 9. Where the reference and the specification text disagree

For the fork's maintainer. Each line is a place where `MatroxSdpCheck.py` or
`MatroxSdp.py` rejects what the text permits, or accepts what it forbids.

1. `b=` types other than AS rejected (867–872); RFC 8866 §5.8 defines CT and says unknown types MUST be ignored.
2. `a=charset` rejected (923–924); RFC 8866 §6.10 defines it.
3. `a=group` other than DUP rejected, and DUP limited to two tags (903–907); RFC 5888 §5 defines LS and FID and allows extensions.
4. `a=extmap` direction other than sendonly rejected on every extmap (1435–1436); RFC 8285 §5 allows four directions and TR-10-13 §20.1 binds sendonly to the PEP header extensions only.
5. `a=extmap` id 0 and negative ids accepted (1418–1432); RFC 8285 §4.3 valid range is 1–256 (ids 4096–4351 MAY be offered, §7).
6. `a=source-filter: excl` rejected (1070); RFC 4570 §3 defines both modes.
7. `a=framerate` with a decimal point rewritten to a /1001 fraction (1502–1515), so `25.0` becomes 25025/1001; RFC 8866 §6.13 allows decimals and defines no rewrite.
8. `o=` sess-id or sess-version of 0 rejected (2014); RFC 8866 §5.2 defines a numeric string.
9. More than two `m=` sections rejected at every tier (969–970); RFC 8866 sets no limit. (ST 2110-10:2022 §8.1 does limit an ST 2110 SDP to one stream or one redundant pair.)
10. `m=` with more than one format rejected (977–978); RFC 8866 §5.14 lists `fmt *(SP fmt)`.
11. `a=rtpmap` payload type must equal the `m=` format (1142–1143); RFC 8866 §6.6 states no such rule.
12. `a=mediaclk:sender` rejected on a non-IPMX ST 2110 stream (342); ST 2110-10:2022 §8.3 requires it when the media clock is asynchronous.
13. ST 2110-30 `channel-order` required (495); ST 2110-30:2025 §6.2.2 defines the absent case as Undefined.
14. ST 2110-30 `ptime` limited to a value set with ±tolerances (502), and `maxptime` compared with it (505); AES67 §8.1 says other values shall be correctly interpreted, and ST 2110-30 Tables 2/3 are conformance levels.
15. `depth=16f` rejected on raw video (375); ST 2110-20:2022 §7.4.2 defines it.
16. `SSN=ST2110-20:2021` accepted (405); ST 2110-20:2022 §7.2 defines only ST2110-20:2017 and ST2110-20:2022.
17. `SSN=ST2110-20:2022` without ST2115LOGS3 or ALPHA rejected (408); the §7.2 clause runs the other way (decision `parse_sdp-m0w`).
18. H.264 `sprop-interleaving-depth=0`, `sprop-deint-buf-req=0`, `sprop-init-buf-time=0` and `sprop-max-don-diff=0` accepted in packetization modes 0 and 1 (245–251); RFC 6184 §8.1 says each "MUST NOT be present".
19. H.264 `profile-level-id=42e0xx` decoded as Baseline (2111–2118); constraint_set1_flag set with profile_idc 66 is Constrained Baseline per RFC 6184 §8.1.
20. H.264 level_idc 11 with profile 66/77/88 always decoded as level 1b (2064–2108); RFC 6184 §8.1 says level 1b only when constraint_set3_flag is 1.
21. H.265 `profile-id=0` and `level-id=0` replaced by 1 and 93 (277, 280); RFC 7798 §7.1 ranges include 0, and the defaults apply only when the parameter is absent.
22. H.265 High tier accepted for levels 1–3.1 (2461–2487); ITU-T H.265 Table A.8 defines no High tier below level 4 (not a source this library quotes; reported as observed).
23. H.265 `profile_compatibility` argument ignored by the decoder (2160–2175).
24. RFC 3640 `mode` compared with the literal `AAC=hbr` (181); the defined token is `AAC-hbr`, so the check never fires.
25. RFC 3640 `profile-level-id` 254 and 255 rejected (173); ISO/IEC 14496-3 defines them (no profile / no capability required), and RFC 3640 excludes nothing.
26. RFC 3640 `sizeLength`, `indexLength`, `indexDeltaLength` of 0 rejected (185–189); RFC 3640 §4.1 defines zero as the absent-field value.
27. AAC `profile-level-id` 48–51 decoded as HE-AAC rather than HE-AAC v2, and 52 as Low Delay level 1 (2492–2673); ISO/IEC 14496-3 Table 1.14 (observed, not quoted).
28. `a=hkep` beyond the second entry dropped (1340–1341); TR-10-5 §10 allows multiple entries in preference order.
29. `a=privacy` duplicate keys undetected, so a line with `protocol` twice and no `key_id` passes (1346–1400); TR-10-13 §13 names six keys.
30. `a=rtpmap` for audio stores the rate as a sample rate and leaves clock_rate 0 (1151–1155), so `check_sdp_rfc4175`-style "clock rate 0" checks cannot run on audio.
31. Value-less attributes (`a=rtpmap` with no colon, and thirteen others) raise uncaught exceptions instead of returning an error (section 2 list).
32. `test_14` line 2725 builds its failure message with a doubled attribute path and line 2752 labels the USB check "RFC 3551".
33. `tests/sdp_decode_test.py` imports `InvalidData` / `InvalidObject` and calls `Decode`, `PrimaryMediaName`, `PrimaryMedia`, none of which `MatroxSdp.py` defines.

## 10. Fixtures (`tests/sdp_decode_test.py`)

None copied. Equivalents from primary or public sources, or written fresh,
land in Phase `.6` (fixtures) and the codec phases:

| Reference | Stated or inferred origin | Equivalent fixture plan |
| --- | --- | --- |
| r1, r2 | BBC IP Studio session name | Original: raw 1080i25, NMOS `extmap` URNs with non-contiguous ids, PTP ts-refclk with domain, `interlace` flag, mediaclk direct with a large offset (base tier valid; ST 2110 tier fails `direct-offset-must-be-zero`) |
| r3 | RFC 4566-style | RFC 8866 §5 example (H.263-1998, session-level `c=` with TTL, `recvonly`), taken from the RFC text |
| r4, r5, r8, r13 | generic | Covered by existing `examples/generic/valid` and `spec/fixtures` |
| r7 | RFC 7104 §4 example (MP2T DUP) | RFC 7104 §4.1 / §4.2 examples from the RFC text (Phase `.6`) |
| r9 | AWS Elemental session name | Original: raw 1080p60, `b=AS`, `TCS`, `PAR`, `localmac` ts-refclk, `mediaclk:direct=0` |
| r10, r11 | generator-style | Covered by `examples/st2110/valid/02_simple_audio.sdp`, `07_ancillary_data.sdp` |
| r12 | AJA Lily10G2-SDI session name | Original: raw DUP pair with numeric mids and differing destination addresses; a second invalid copy with `interlace=1` and a `source-filter:` with no space |

## 11. Counts

Rows by verdict: ADOPT 63, COVERED 89, REJECT 16, OUT OF SCOPE 2 (plus
the 34 IS-04 / IS-05 comparisons listed in §8.2 without rows), NONE 18.
Decision beads cited: 24. Registered checks after the effort: 319 (197
before). GUIDE limitations removed: `a=setup` values, extmap id range and
uniqueness, PTP domain, mediaclk offset, per-encoding checks for H264 /
H265 / mpeg4-generic / MP4A-LATM / MP2T / L16, ptime presence on audio
streams and the AM824 values, the fmtp format against the `m=` line,
TROFF and CMAX on raw video, frame-rate signaling on jxsv, the privacy
protocol on RTP blocks, and `b=AS` on non-jxsv ST 2110-22 blocks.
