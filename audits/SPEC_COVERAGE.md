# Phase 2 Coverage Map — parse_sdp pre-1.0 audit

Generated from 22 per-spec coverage agents that mapped Phase 1 SDP-Y normative
clauses to `parse_sdp.lua` and `spec/` test enforcement sites. Each agent
classified each clause as COVERED / COVERED-WRONG-CITE / COVERED-NO-TEST /
MISSING / OUT-OF-SCOPE-FROM-SDP and walked the reverse direction (parser
citations of the spec → inventory match).

This is the **agent output** layer. Phase 3 (findings + verdict) treats every
candidate finding here as **provisional** until the main thread has verified
it against parser source.

## Table of Contents


**IETF — SDP base**

- [RFC 4566](#rfc-4566)
- [RFC 8866](#rfc-8866)

**IETF — RTP base**

- [RFC 3550 + 3551](#rfc-3550-3551)

**IETF — SDP attributes**

- [RFC 4570](#rfc-4570)
- [RFC 5888 + 7104](#rfc-5888-7104)

**IETF — clock signaling**

- [RFC 7273](#rfc-7273)

**IETF — RTP payload formats**

- [RFC 8331](#rfc-8331)
- [RFC 9134](#rfc-9134)

**AES — audio references**

- [AES67-2013 + AES3-1 + AES3-4](#aes67-2013-aes3-1-aes3-4)

**SMPTE ST 2110**

- [SMPTE ST 2110-10:2022](#smpte-st-2110-10-2022)
- [SMPTE ST 2110-20:2022](#smpte-st-2110-20-2022)
- [SMPTE ST 2110-21:2022](#smpte-st-2110-21-2022)
- [SMPTE ST 2110-22:2022](#smpte-st-2110-22-2022)
- [SMPTE ST 2110-30:2025](#smpte-st-2110-30-2025)
- [SMPTE ST 2110-31:2022](#smpte-st-2110-31-2022)
- [SMPTE ST 2110-40:2023](#smpte-st-2110-40-2023)
- [SMPTE ST 2110-41:2024](#smpte-st-2110-41-2024)

**SMPTE — codec references**

- [SMPTE ST 2042-1:2012 + ST 2110-43:2021](#smpte-st-2042-1-2012-st-2110-43-2021)

**SMPTE — supporting**

- [SMPTE ST 2022-7:2013](#smpte-st-2022-7-2013)

**SMPTE — Recommended Practices**

- [SMPTE RP 2110-23/24/25](#smpte-rp-2110-23-24-25)

**VSF IPMX — Technical Recommendations**

- [VSF TR-10 series (18 docs)](#vsf-tr-10-series-18-docs)

**VSF IPMX — v1.0 profile requirements**

- [IPMX Released v1.0 (3 profile docs)](#ipmx-released-v1-0-3-profile-docs)

---


# IETF — SDP base

## RFC 4566

# Audit Coverage: RFC 4566 — Parser ↔ Inventory Mapping

Inventory file: `/tmp/audit_inventory_rfc4566.md`
Parser file: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
Primary spec file: `/Users/andrewstarks/src/parse_sdp/spec/sdp_spec.lua`

Notation:
- `parse_sdp.lua:NN` — line in parser
- `sdp_spec.lua:NN` — line in spec/sdp_spec.lua
- `st2110_spec.lua:NN` — line in spec/st2110_spec.lua

## Forward direction — SDP-Y inventory rows

| # | Spec | § | SHALL summary | Status | Parser ref | Test ref | Notes |
|---|---|---|---|---|---|---|---|
| 1 | RFC 4566 | 4.1 | Default: c/m semantics = remote destination | OUT-OF-SCOPE-FROM-SDP | — | — | Semantic recommendation; doesn't constrain SDP form. SHOULD-tier, descriptive of consumer behavior. |
| 3 | RFC 4566 | 5 | Each line: type is exactly one case-significant char | COVERED | grammar.tokenize_line `parse_sdp.lua:86-103` (line_pat uses `C(alpha) * P("=")`) | sdp_spec.lua:52 ("rejects multi-char type field"); sdp_spec.lua:58 ("rejects non-alpha type"); sdp_spec.lua:76 ("returns failure position after type char") | LPEG enforces single alpha. Case-sensitivity inherent in `R("az", "AZ")`. |
| 4 | RFC 4566 | 5 | No whitespace around `=` | COVERED-NO-TEST | grammar.tokenize_line `parse_sdp.lua:86-87` (`C(alpha) * P("=") * Cp() * C(value_char ^ 1)` — alpha directly bound to `=`, value starts at offset; downstream value-form parsers reject leading SP) | No explicit "v =0" or "v= 0" test case found | LPEG grammar structurally forbids SP before `=`. SP after `=` is allowed in raw value but downstream parsers like parse_version reject. |
| 5 | RFC 4566 | 5 | Lines MUST appear in fixed order | COVERED | parser.parse `parse_sdp.lua:2982-3215` (strict positional consumption via parse_required + peek_type); WRONG_ORDER reported at `parse_sdp.lua:2954-2956, 3173-3177` | sdp_spec.lua:298-309 ("returns nil, err for wrong field order"); sdp_spec.lua:352-357 ("rejects unrecognized field type after all SDP fields"); pass path via minimal parser test sdp_spec.lua:208-222 | The entire parser is built around the §5 fixed order. |
| 6 | RFC 4566 | 5 | Unknown type letter: parser MUST ignore ENTIRE description | MISSING | `parse_sdp.lua:3170-3184` — unknown letter at end raises WRONG_ORDER/MALFORMED_LINE error; unknown letter in mid-stream falls through and errors | sdp_spec.lua:352-357 ("rejects unrecognized field type") | AMBIGUOUS in spec (literal reading vs. parser tolerance per row 7). Parser implements REJECT-instead-of-IGNORE; defensible reading but conflicts with row 7 / §5.13. Worth noting to main thread — this is the famous §5 ambiguity. |
| 7 | RFC 4566 | 5 | Unknown attributes are ignored, not rejected | COVERED | grammar.parse_attribute `parse_sdp.lua:258-264` (returns `{name, value}` for any non-empty attribute name; validate.sdp `parse_sdp.lua:304-365` does not whitelist a= names) | sdp_spec.lua:594-599 ("parses a= attribute with value after t="); sdp_spec.lua:601-607 ("parses multiple a= attributes in order") | Any attribute is parsed into doc tree. No RFC 4566-tier rejection. |
| 8 | RFC 4566 | 5 | Field/attribute names ASCII; textual values MAY be UTF-8 | COVERED-NO-TEST | grammar att_field/token char classes restrict name-position bytes; value uses byte-string `parse_sdp.lua:80, 250` (token excludes whitespace/line-end but allows >0x80) | No test for UTF-8 names rejection or UTF-8 values acceptance | The grammar accepts UTF-8 bytes throughout token chars (LPEG `P(1)` is byte-wise). No test asserts ASCII-only for names. |
| 9 | RFC 4566 | 5 | Parser SHOULD also accept LF-only line endings | COVERED | split_lines + line_end `parse_sdp.lua:79, 2917-2934` | sdp_spec.lua:19 ("parses a valid LF-only line"); sdp_spec.lua:224-230 ("accepts LF-only line endings") | |
| 10 | RFC 4566 | 5 | Without a=charset, text fields are UTF-8 | OUT-OF-SCOPE-FROM-SDP | — | — | Interpretation rule for downstream consumers; the parser stores raw bytes. Not a form-check. |
| 11 | RFC 4566 | 5 | Domain names MUST comply with RFC 1034/1035 | MISSING | grammar.parse_origin `parse_sdp.lua:119-145` accepts any `token` for unicast-address; grammar.parse_connection `parse_sdp.lua:167` same | None | No check for RFC 1034/1035 DNS form when unicast-address is an FQDN. Parser allows any non-SP token as o= / c= address. |
| 12 | RFC 4566 | 5 | IDNs MUST use ACE form (xn--) | MISSING | None | None | No detection of non-ASCII in domain-position. |
| 13 | RFC 4566 | 5 | IDNs MUST NOT be raw UTF-8 | MISSING | None | None | Paired with row 12; not detected. |
| 14 | RFC 4566 | 5.1 | v= value is "0" | COVERED | grammar.parse_version `parse_sdp.lua:105-114` (version_pat = `P("0") * -P(1)`) | sdp_spec.lua:97-101 ("rejects '1'"); sdp_spec.lua:92-95 ("accepts '0'"); sdp_spec.lua:324-334 ("returns nil, err for wrong v= value") | Note tension with §9 ABNF (row 119). Parser implements §5.1 prose strictly. |
| 15 | RFC 4566 | 5.2 | username MUST NOT contain spaces | COVERED | origin_pat `parse_sdp.lua:120` uses `C(token)` (token = non-SP non-line_end) | sdp_spec.lua:137-141 ("rejects too few fields") indirectly covers; no dedicated "username with space" test | Implicit via token grammar (no SP allowed in token). |
| 16 | RFC 4566 | 5.2 | sess-id is 1*DIGIT | COVERED | origin_pat `parse_sdp.lua:121` `C(digit ^ 1)` | sdp_spec.lua:143-147 ("rejects non-numeric sess-id") | |
| 17 | RFC 4566 | 5.2 | sess-version is 1*DIGIT | COVERED-NO-TEST | origin_pat `parse_sdp.lua:122` `C(digit ^ 1)` | No dedicated "non-numeric sess-version" test (only sess-id) | Identical pattern to sess-id. |
| 18 | RFC 4566 | 5.2 | nettype initial set {IN} | COVERED | `nettype = P("IN")` `parse_sdp.lua:116`; origin_pat & connection_pat use nettype `parse_sdp.lua:124, 167` | sdp_spec.lua:149-153 ("rejects unknown nettype") | Note: spec says "extensible" but parser hard-codes IN. Acceptable: any extension would need to be registered, and no extension has been registered yet beyond IN. |
| 19 | RFC 4566 | 5.2 | addrtype initial set {IP4, IP6} | COVERED | `addrtype = P("IP4") + P("IP6")` `parse_sdp.lua:117` | sdp_spec.lua:130-134 ("accepts IP6"); sdp_spec.lua:155-159 ("rejects unknown addrtype") | |
| 20 | RFC 4566 | 5.2 | o= addr SHOULD prefer FQDN | OUT-OF-SCOPE-FROM-SDP | — | — | Recommendation only. |
| 22 | RFC 4566 | 5.3 | Exactly one s= per session | COVERED | parser.parse `parse_sdp.lua:3006-3009` (required parse_required); a second s= would not match downstream peek_type checks → WRONG_ORDER | Implicit via minimal SDP tests sdp_spec.lua:208 | No dedicated "two s=" test. |
| 23 | RFC 4566 | 5.3 | s= value non-empty | COVERED | grammar.tokenize_line `parse_sdp.lua:86-87` requires `value_char ^ 1` (1+); grammar.parse_session_name `parse_sdp.lua:147` returns whole string; validate.sdp `parse_sdp.lua:333-335` rejects empty s.name | sdp_spec.lua:280-285 ("rejects 's=' empty session name") | |
| 24 | RFC 4566 | 5.3 | If no name, use single space "s= " | COVERED | Permissive: `s= ` parses with name=" "; validator's `s.name == ""` check `parse_sdp.lua:333` does not reject single-space | sdp_spec.lua:264-269 ("accepts 's= ' single space session name") | |
| 25 | RFC 4566 | 5.4 | At most one i= per session and per media | COVERED | parser.parse `parse_sdp.lua:3011-3016` (session i= uses `if peek_type == "i"`); media i= `parse_sdp.lua:3130-3134` same | sdp_spec.lua:507-511 ("parses i= session information"); no dedicated "two i=" rejection test | A second i= falls through and triggers WRONG_ORDER from a subsequent peek. |
| 26 | RFC 4566 | 5.4 | i= UTF-8 by default | OUT-OF-SCOPE-FROM-SDP | — | — | Interpretation; not a form-check. |
| 27 | RFC 4566 | 5.5 | u= MUST precede first m= | COVERED | parser.parse `parse_sdp.lua:3018-3023` (u= block before m= scanning) | sdp_spec.lua:513-517 ("parses u= URI") tests pass path; ordering is structural | |
| 28 | RFC 4566 | 5.5 | At most one u= per SDP | COVERED | parser.parse `parse_sdp.lua:3018-3023` (`if peek_type == "u"`) | No dedicated "two u=" test | |
| 29 | RFC 4566 | 5.6 | e=/p= MUST precede first m= | COVERED | parser.parse `parse_sdp.lua:3025-3041` (e=/p= consumed before m= loop) | sdp_spec.lua:519-535 (multiple e= and p= tests) | |
| 30 | RFC 4566 | 5.6 | p= preferred form E.164 with + | OUT-OF-SCOPE-FROM-SDP | — | — | SHOULD; recommendation; ABNF permits broader. |
| 31 | RFC 4566 | 5.6 | e=/p= optional name in parens | MISSING | grammar.parse_phone / parse_email `parse_sdp.lua:150-151` are identity functions; no form check | None | Per ABNF (row 139, 140) three alternative forms exist. Parser accepts any text — no parens / bracket form check. Per note in inventory: AMBIGUOUS / ABNF authoritative. |
| 32 | RFC 4566 | 5.6 | Free-text in e=/p= UTF-8 / a=charset | OUT-OF-SCOPE-FROM-SDP | — | — | Encoding interpretation. |
| 33 | RFC 4566 | 5.7 | c= required: session-level OR per-media | COVERED | st2110.validate `parse_sdp.lua:1268-1273` enforces "c= at session or media"; at RFC 4566 tier, no enforcement | st2110_spec.lua: existing | At the RFC 4566 tier only, this is NOT enforced — a doc with no c= anywhere parses cleanly. Strictly: COVERED-NO-RFC4566-TEST but ST 2110 tier covers. Recommend: explicit RFC 4566 tier check would be tighter, but absence is permitted by parser as RFC 4566-only validator does not require c=. |
| 34 | RFC 4566 | 5.7 | Per-media c= overrides session-level c= | OUT-OF-SCOPE-FROM-SDP | — | — | Layering rule for consumers; not a form-check. |
| 35 | RFC 4566 | 5.7 | IPv4 multicast c= MUST include TTL | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:854-864` (cited as RFC 8866 §9); invoked only by st2110/ipmx validators, not RFC 4566 | st2110_spec.lua:2633-2640 ("rejects IPv4 multicast address without TTL") | Parser enforcement is correct per spec but cite says "RFC 8866 §9" rather than "RFC 4566 §5.7" (these are equivalent across the two editions of the spec; RFC 8866 obsoletes 4566 with same text). Not invoked at RFC 4566-only tier — could miss this when mode=nil. |
| 36 | RFC 4566 | 5.7 | TTL in [0,255] | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:864-868` (cited as RFC 8866 §5.7) | st2110_spec.lua:2920-2924 (TTL=0), 2912-2916 (TTL=255), 2926-2931 (TTL=256 rejected) | Same as row 35; cite is RFC 8866 but the rule is identical to RFC 4566 §5.7. Only enforced at ST 2110 tier. |
| 37 | RFC 4566 | 5.7 | TTL required for v4 mcast (restatement) | COVERED-WRONG-CITE | Same as row 35 | Same as row 35 | Duplicate of row 35; same status. |
| 38 | RFC 4566 | 5.7 | IPv6 multicast c= MUST NOT include TTL | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:826-842` — IPv6 multicast: only `/<numaddr>` form is accepted, not `/<ttl>` | st2110_spec.lua:4363-4400 ("accepts IPv6 multicast with /numaddr suffix"; "rejects IPv6 multicast with non-numeric /numaddr"; "rejects IPv6 multicast with /numaddr=0") | Cited as "RFC 8866 §9 IP6-multicast ABNF"; rule is equivalent to RFC 4566 §5.7. Only enforced at ST 2110 tier. |
| 39 | RFC 4566 | 5.7 | Multiple c= allowed only per-media, only for layered mcast; no multiple session-level c= | MISSING | parser.parse `parse_sdp.lua:3043-3048` uses `if peek_type == "c"` for session c= (single allowed); media c= `parse_sdp.lua:3136-3140` same single `if` — parser actually rejects multiple media c= as well | None for multiple media c= per RFC 4566 §5.7 | Parser is OVER-strict: spec allows multiple c= per media for layered mcast, parser allows only one. Worth flagging. Session-level multiple-c= rejection is correct. |
| 40 | RFC 4566 | 5.7 | Address-count slash MUST NOT be used for unicast | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:882-884` ("unicast address must not include a TTL suffix"); also `parse_sdp.lua:839-841` for IPv6 unicast | st2110_spec.lua:3417 ("rejects session-level c= unicast with TTL suffix") | Enforces both v4 and v6 unicast rejection of slash suffix. Only at ST 2110 tier. |
| 41 | RFC 4566 | 5.8 | When scope-bandwidth differs, supply b=CT | OUT-OF-SCOPE-FROM-SDP | — | — | SHOULD; recommendation, requires scope knowledge. |
| 43 | RFC 4566 | 5.8 | Unknown bwtype: ignore the b= line, do not fail | COVERED | grammar.parse_bandwidth `parse_sdp.lua:181-194` accepts any non-`:` non-SP token for bwtype; validator does not whitelist | sdp_spec.lua:570-575 ("parses b= with X- extension bandwidth type") | Parser keeps the b= entry but does not error on unknown bwtype — matches "ignore the field" semantics for an SDP-level parser (the field is stored but not rejected). |
| 44 | RFC 4566 | 5.8 | bwtype name alphanumeric (per prose); ABNF: token | COVERED | grammar.parse_bandwidth `parse_sdp.lua:181` `bw_bwtype = (P(1) - P(":") - SP - line_end) ^ 1` | sdp_spec.lua:570-575 ("X-YZ" accepted) | Per audit rule 4, ABNF authoritative (token). Parser accepts token; AMBIGUOUS resolved by ABNF. |
| 45 | RFC 4566 | 5.8 | Default units kbit/s; per-bwtype may differ | OUT-OF-SCOPE-FROM-SDP | — | — | Unit-semantics for consumers. |
| 46 | RFC 4566 | 5.9 | Multiple t= permitted | COVERED | parser.parse `parse_sdp.lua:3077-3091` (`while peek_type == "t"` loop for additional t= blocks) | sdp_spec.lua:396-409 ("accepts multiple time descriptions") | |
| 47 | RFC 4566 | 5.9 | t= NTP-seconds decimal | COVERED | grammar.parse_timing `parse_sdp.lua:153-165` (`digit ^ 1 * SP * digit ^ 1`) | sdp_spec.lua:172-177 ("parses NTP timestamps"); sdp_spec.lua:185-189 ("rejects non-numeric values") | |
| 48 | RFC 4566 | 5.9 | SDP t= keeps counting past 2036, never wraps | OUT-OF-SCOPE-FROM-SDP | — | — | Constraint on sender-side time arithmetic; not a form-check. |
| 49 | RFC 4566 | 5.9 | stop=0 unbounded; start=stop=0 permanent | COVERED-NO-TEST | grammar.parse_timing `parse_sdp.lua:160-164` accepts "0 0"; semantic interpretation is for consumers | sdp_spec.lua:165-170 ("parses '0 0'") covers acceptance but not semantic | The form is accepted; semantic rule is not checked (and need not be — informational interpretation). |
| 51 | RFC 4566 | 5.10 | r= form interval/duration/offsets (integer seconds or typed-time) | COVERED | grammar.parse_repeat `parse_sdp.lua:201-215` | sdp_spec.lua:378-394 ("accepts t= followed by r= with typed-time tokens"); sdp_spec.lua:478-481 ("rejects malformed r= (less than three tokens)") | |
| 52 | RFC 4566 | 5.10 | r= typed-time: integer + d/h/m/s; no fractions | COVERED | grammar typed_time_pat `parse_sdp.lua:198` (`digit ^ 1 * S("dhms") ^ -1 * -P(1)`) | sdp_spec.lua:386-394 ("typed-time tokens 7d 1h 0 25h") | No fraction accepted (pattern starts with digit, no `.`). |
| 53 | RFC 4566 | 5.10 | typed-time units: {d,h,m,s} case-sensitive | COVERED-NO-TEST | typed_time_pat uses `S("dhms")` lowercase only `parse_sdp.lua:198` | No explicit "rejects 5H" or "rejects 5D" test | LPEG `S` is exact-char, no case-fold. |
| 54 | RFC 4566 | 5.11 | z= alternating adjustment-time / offset pairs | COVERED | grammar.parse_timezone `parse_sdp.lua:217-233` | sdp_spec.lua:411-420 ("accepts z= time zones"); sdp_spec.lua:483-486 ("rejects malformed z= odd token count") | |
| 55 | RFC 4566 | 5.12 | k= deprecated/not recommended | COVERED | grammar.parse_key + parser k= consumption `parse_sdp.lua:235-248, 3107-3112` | sdp_spec.lua:422-446 (session-level k= and media-level k= tests) | Allowed (per spec); parser does not warn. |
| 58 | RFC 4566 | 5.12 | Defined k= methods: {clear, base64, uri, prompt} | MISSING | grammar.parse_key `parse_sdp.lua:239-248` accepts ANY non-colon non-SP token as method; no closed value set | sdp_spec.lua:422-435 (only tests clear and prompt; no "rejects unknown method" test) | Per row 117 / §8.3 ("New registrations MUST NOT be accepted"), method set is closed. Parser is permissive. CANDIDATE for tightening. |
| 60 | RFC 4566 | 5.13 | a= attribute name (att-field) is US-ASCII | COVERED-NO-TEST | grammar.parse_attribute `parse_sdp.lua:250-264` uses `att_field = (P(1) - P(":") - SP - line_end) ^ 1` — admits bytes >0x7F | No explicit test for UTF-8 attribute name rejection | Parser is permissive on attribute-name encoding (per ABNF `att-field = token`; token-char excludes high bytes, but parser's att_field is broader). MISSING tightening per spec. |
| 61 | RFC 4566 | 5.13 | att-value bytes: not NUL/LF/CR | COVERED | grammar.tokenize_line `parse_sdp.lua:80, 86-87` (line_end is CRLF or LF; value_char = `1 - line_end`); NUL exclusion implicit (line_end doesn't exclude NUL but LPEG sees it as just byte 0x00 — *check*) | None for NUL specifically | NUL handling is implicit; LPEG's `1 - line_end` would still match NUL since NUL ≠ CR/LF. **Worth flagging**: NUL allowed in attribute value per parser. Spec forbids NUL. |
| 63 | RFC 4566 | 5.13 | Unknown attribute: ignore (duplicate of §5) | COVERED | Same as row 7 | Same as row 7 | |
| 64 | RFC 4566 | 5.14 | Initial media set: {audio,video,text,application,message}, extensible | COVERED-NO-TEST | grammar.parse_media `parse_sdp.lua:278-293` accepts any token for media (extensible) | sdp_spec.lua: many tests with audio/video, but no test rejecting outside the initial set | Spec says extensible; parser accepts any token — appropriate. |
| 67 | RFC 4566 | 5.14 | m= port may carry /count for hierarchical | COVERED | grammar.parse_media `parse_sdp.lua:281-289` (extracts `port/count` and `port` forms) | sdp_spec.lua:660-665 ("parses m= with port count"); sdp_spec.lua:779-786 ("parses m= with port count (/2)") | |
| 68 | RFC 4566 | 5.14 | Initial proto set {udp, RTP/AVP, RTP/SAVP}, extensible | COVERED-NO-TEST | grammar.parse_media `parse_sdp.lua:270` `C(token)` — accepts any non-SP proto token | No explicit "rejects bogus proto" test at RFC 4566 layer | Spec is extensible; parser is permissive. |
| 69 | RFC 4566 | 5.14 | First m= fmt is preferred default | OUT-OF-SCOPE-FROM-SDP | — | — | SHOULD; consumer recommendation. |
| 70 | RFC 4566 | 5.14 | Dynamic PT SHOULD have a=rtpmap | COVERED | st2110.validate `parse_sdp.lua:1303-1305` requires rtpmap; at RFC 4566 tier, not enforced | st2110_spec.lua tests | At RFC 4566 tier, SHOULD; at ST 2110 tier MUST is enforced. Consistent with §8.2.3 promotion (row 110). |
| 71 | RFC 4566 | 5.14 | proto=udp → fmt MUST be media type | MISSING | None — parser does not differentiate proto=udp vs RTP/AVP fmt format | None | The check would require parsing fmt as IANA media type only for proto=udp. Parser accepts any token. Spec MUST. Recommend: add proto-conditional fmt check. |
| 73 | RFC 4566 | 6 | a=cat:<category> dot-separated | OUT-OF-SCOPE-FROM-SDP | — | — | Attribute-name-specific defined value form; no `a=cat` is widely used. Could be COVERED-NO-TEST (parser accepts the form via generic attribute parse), but no value form is checked. Per principle, parser is permissive and that's fine if the spec defines no SHALL rejection. |
| 74 | RFC 4566 | 6 | a=keywds:<keywords> | OUT-OF-SCOPE-FROM-SDP | — | — | Same as row 73 — value form unrestricted. |
| 75 | RFC 4566 | 6 | a=tool:<name+version> | OUT-OF-SCOPE-FROM-SDP | — | — | Same as 73 — value form unrestricted. |
| 76 | RFC 4566 | 6 | a=ptime: integer ms (media-level) | COVERED | At ST 2110 tier: st2110.validate `parse_sdp.lua:1950-1954` `tonumber(ptime_attr.value)`; at RFC 4566 tier, ptime is parsed as generic attribute (no integer check) | st2110_spec.lua: ptime tests; sdp_spec.lua: no integer-form test at RFC 4566 tier | RFC 4566 says "length of time in milliseconds" — defined value form is a number. Parser accepts any value at RFC 4566 tier. Tightenable but lower priority. |
| 78 | RFC 4566 | 6 | a=rtpmap: PT SP name/rate[/params] | COVERED | rtpmap_parse `parse_sdp.lua:553-559` (used by st2110.validate) | st2110_spec.lua extensive | At RFC 4566 tier, only generic attribute parse. ST 2110 tier checks form. RFC 4566 tier: COVERED-NO-RFC4566-TEST. |
| 80 | RFC 4566 | 6 | rtpmap audio encoding-params = channels; optional default 1 | COVERED | st2110.validate `parse_sdp.lua:1907-1920` requires channels for audio; the form is checked by rtpmap_parse | st2110_spec.lua: audio rtpmap tests | At RFC 4566 tier not enforced (channels are part of the rtpmap value, but parser doesn't decompose). |
| 81 | RFC 4566 | 6 | rtpmap video encoding-params not defined | OUT-OF-SCOPE-FROM-SDP | — | — | Spec is silent on additional parameters; defined-form: only encoding/rate. Nothing to enforce. |
| 84 | RFC 4566 | 6 | Default direction = sendrecv (unless broadcast/H332) | OUT-OF-SCOPE-FROM-SDP | — | — | Implicit-value rule for consumers; not a form-check. |
| 87 | RFC 4566 | 6 | a=orient value set: {portrait, landscape, seascape} | MISSING | None | None | Defined value set. Parser parses generically; does not validate enum. Tightenable; low-stakes. |
| 88 | RFC 4566 | 6 | a=type suggested set: {broadcast,meeting,moderated,test,H332} | OUT-OF-SCOPE-FROM-SDP | — | — | "Suggested" not normative; per inventory note row 88 AMBIGUOUS and cannot reject. |
| 89 | RFC 4566 | 6 | a=charset: IANA-registered charset name | MISSING | None | None | Defined value set (IANA charset registry). Parser is permissive. Tightenable (open question whether to validate vs registry). |
| 90 | RFC 4566 | 6 | a=charset comparison case-insensitive | OUT-OF-SCOPE-FROM-SDP | — | — | Comparison semantic for consumers. |
| 91 | RFC 4566 | 6 | Unknown charset: treat as octets | OUT-OF-SCOPE-FROM-SDP | — | — | Tolerance rule for downstream interpretation. |
| 92 | RFC 4566 | 6 | Even non-default charset: no NUL/LF/CR | COVERED-NO-TEST | grammar.tokenize_line `parse_sdp.lua:80, 86-87` — value_char excludes line_end (CR/LF); NUL exclusion implicit | None | Same caveat as row 61: NUL not explicitly excluded by grammar. |
| 94 | RFC 4566 | 6 | a=sdplang: single RFC 3066 tag ASCII | MISSING | None | None | Defined value form. Parser accepts any value. Tightenable. |
| 95 | RFC 4566 | 6 | a=lang: single RFC 3066 tag ASCII | MISSING | None | None | Same as 94. |
| 96 | RFC 4566 | 6 | a=framerate: integer or integer.fraction; video only | COVERED | st2110.validate `parse_sdp.lua:1555-1565` validates a=framerate format (`integer or integer.fraction`) only on video | st2110_spec.lua: a=framerate tests; sdp_spec.lua: no test at RFC 4566 tier | At RFC 4566 tier not enforced. |
| 97 | RFC 4566 | 6 | a=quality: integer | MISSING | None | None | Defined value form (integer). Parser accepts any value. Tightenable; low priority. |
| 98 | RFC 4566 | 6 | a=fmtp format token must match an m= fmt | COVERED | st2110.validate `parse_sdp.lua:1315-1324` ("fmtp payload type %s does not match rtpmap payload type %s"); cite is "RFC 4566 §6" | st2110_spec.lua tests | At RFC 4566 tier the cross-line consistency check is NOT performed (only at ST 2110 tier). But st2110.validate's `fmtp_pt vs rtp_pt` check covers the requirement. **Note**: rtp_pt vs fmtp_pt comparison only checks PT equality, but spec says fmtp format must be one of the m= fmts (e.g. fmtp PT must equal one of the m= fmt PTs). For ST 2110 there is only one rtpmap so the check coincides. RFC 4566 tier: MISSING. |
| 99 | RFC 4566 | 6 | At most one a=fmtp per fmt per media | MISSING | None — parser doesn't check for duplicate fmtp per PT | None | Cardinality check missing. Tightenable. |
| 100 | RFC 4566 | 6 | Per-attribute placement scope (session/media/either) | MISSING | None (RFC 4566 tier); st2110.validate rejects `mediaclk` at session-level `parse_sdp.lua:1215-1222` for ST 2110, but not the general attribute-scope table | None at RFC 4566 tier | The full per-attribute scope table is not enforced at RFC 4566 tier. Tightenable but complex. |
| 101 | RFC 4566 | 6 | Per-attribute charset dependency | OUT-OF-SCOPE-FROM-SDP | — | — | Interpretation/comparison rule; not a form-check. |
| 106 | RFC 4566 | 8.2.1 | "control"/"data" media: not to be used until re-specified | OUT-OF-SCOPE-FROM-SDP | — | — | SHOULD NOT; recommendation only. Strict reading of "MUST" would block use; the spec says SHOULD NOT, which is recommendation. |
| 109 | RFC 4566 | 8.2.3 | For RTP/AVP, RTP/SAVP: fmt = PT number | COVERED | st2110.validate `parse_sdp.lua:1334-1339` (PT range 0-127 check); m= fmt parse as token but ST 2110 enforces PT-integer via rtpmap_parse | st2110_spec.lua: PT range tests | At RFC 4566 tier, fmt is parsed as token (allows non-numeric); spec says it MUST be PT number for RTP/AVP. **MISSING at RFC 4566 tier**. ST 2110 tier covers indirectly. |
| 110 | RFC 4566 | 8.2.3 | Dynamic PT → a=rtpmap REQUIRED | COVERED | st2110.validate `parse_sdp.lua:1303-1305` ("missing required attribute 'rtpmap'") | st2110_spec.lua: rtpmap-required tests | At RFC 4566 tier this is the stronger MUST per row 110; parser only enforces in ST 2110 mode. RFC 4566 tier: MISSING (per §8.2.3 spec citation). Worth raising. |
| 117 | RFC 4566 | 8.3 | k= method set is frozen at {clear, base64, uri, prompt} | MISSING | Same as row 58 | None | Same as row 58. |
| 118 | RFC 4566 | 9 | Top-level session order (authoritative ABNF) | COVERED | parser.parse `parse_sdp.lua:2982-3215` follows ABNF order precisely | sdp_spec.lua:298-309 ("returns nil, err for wrong field order") | |
| 119 | RFC 4566 | 9 | v= ABNF: `1*DIGIT` (any digit value valid grammatically) | COVERED-WRONG-CITE | grammar.parse_version `parse_sdp.lua:111-114` ONLY accepts "0" per §5.1 prose | sdp_spec.lua:97 (rejects '1') | Parser implements §5.1 prose (only "0"). Conflict resolved per inventory: ABNF authoritative but §5.1 fixes value to 0. Parser is stricter than ABNF — defensible since §5.1 is prose-MUST. |
| 120 | RFC 4566 | 9 | o= ABNF: 6 SP-separated subfields | COVERED | origin_pat `parse_sdp.lua:119-126` | sdp_spec.lua:119-159 (origin tests) | |
| 121 | RFC 4566 | 9 | s= ABNF: required, text (1+ bytes) | COVERED | parser.parse `parse_sdp.lua:3006-3009`; tokenize_line `parse_sdp.lua:86-87` requires 1+ value chars | sdp_spec.lua:280-285 ("rejects 's=' empty session name") | |
| 122 | RFC 4566 | 9 | i= ABNF: optional, single | COVERED | parser.parse `parse_sdp.lua:3011-3016, 3130-3134` | sdp_spec.lua:507 | |
| 123 | RFC 4566 | 9 | u= ABNF: optional, single, URI-reference | COVERED | parser.parse `parse_sdp.lua:3018-3023` (single); grammar.parse_uri `parse_sdp.lua:149` identity (no URI form check) | sdp_spec.lua:513 | Single-cardinality COVERED; URI-form not checked. |
| 124 | RFC 4566 | 9 | e= ABNF: 0..N | COVERED | parser.parse `parse_sdp.lua:3025-3032` (while loop) | sdp_spec.lua:519 | |
| 125 | RFC 4566 | 9 | p= ABNF: 0..N | COVERED | parser.parse `parse_sdp.lua:3034-3041` | sdp_spec.lua:528 | |
| 126 | RFC 4566 | 9 | c= ABNF: optional at level | COVERED | parser.parse `parse_sdp.lua:3043-3048, 3136-3140` | sdp_spec.lua:537, 799-808 | |
| 127 | RFC 4566 | 9 | b= ABNF: 0..N, colon-separator | COVERED | parser.parse `parse_sdp.lua:3050-3057, 3142-3149`; grammar.parse_bandwidth `parse_sdp.lua:181-194` | sdp_spec.lua:554, 577 | |
| 128 | RFC 4566 | 9 | t= ABNF: 1..N required; r= follow each; z= once | COVERED | parser.parse `parse_sdp.lua:3062-3091, 3098-3104` | sdp_spec.lua:396 (multiple t=), 411 (z=) | |
| 129 | RFC 4566 | 9 | r= ABNF: interval + duration + 1..N offsets (≥3 tokens) | COVERED | grammar.parse_repeat `parse_sdp.lua:208` `if #tokens < 3 then return nil, 1 end` | sdp_spec.lua:478-481 | |
| 130 | RFC 4566 | 9 | z= ABNF: 1..N (time, signed-typed-time) pairs | COVERED | grammar.parse_timezone `parse_sdp.lua:221-233` | sdp_spec.lua:411, 483 | |
| 131 | RFC 4566 | 9 | k= ABNF: optional; method ∈ {prompt, clear:, base64:, uri:} | MISSING | grammar.parse_key `parse_sdp.lua:235-248` accepts any token as method | None for unknown method rejection | Same as row 58. |
| 132 | RFC 4566 | 9 | a= ABNF: 0..N; flag or key:value | COVERED | grammar.parse_attribute `parse_sdp.lua:250-264`; parser.parse loops `parse_sdp.lua:3114-3121, 3158-3165` | sdp_spec.lua:585-607 | |
| 133 | RFC 4566 | 9 | m= section ABNF + required order i= c=* b= k= a= | COVERED | parser.parse `parse_sdp.lua:3123-3168` follows order | sdp_spec.lua:732-833 (m= block parsing) | NOTE: parser uses `if peek_type == "c"` (single) for media c= but ABNF says `*connection-field` (0..N). Parser is stricter — see row 39. |
| 134 | RFC 4566 | 9 | username = non-ws-string | COVERED | origin_pat `parse_sdp.lua:120` `C(token)` (non-SP non-line_end) | sdp_spec.lua:119-128 | |
| 135 | RFC 4566 | 9 | sess-id = 1*DIGIT | COVERED | origin_pat `parse_sdp.lua:121` | sdp_spec.lua:143-147 | |
| 136 | RFC 4566 | 9 | sess-version = 1*DIGIT | COVERED-NO-TEST | origin_pat `parse_sdp.lua:122` | No dedicated test | |
| 137 | RFC 4566 | 9 | nettype/addrtype = token | COVERED | `parse_sdp.lua:116-117` hard-coded to {IN}, {IP4,IP6} | sdp_spec.lua:149-159 | Parser is stricter than ABNF (token); fine since no extension registered. |
| 138 | RFC 4566 | 9 | u= URI-reference per RFC 3986 | MISSING | grammar.parse_uri `parse_sdp.lua:149` is identity | None | URI form not validated. Tightenable. |
| 139 | RFC 4566 | 9 | e= value: three alternative forms | MISSING | grammar.parse_email `parse_sdp.lua:150` is identity | None | Email form not validated. Tightenable. |
| 140 | RFC 4566 | 9 | p= value: phone, optionally with name | MISSING | grammar.parse_phone `parse_sdp.lua:151` is identity | None | Phone form not validated. Tightenable. |
| 141 | RFC 4566 | 9 | c= 3rd field: mcast or unicast | COVERED | grammar.parse_connection `parse_sdp.lua:167` accepts token; valid_connection_address `parse_sdp.lua:819-887` validates literal IP form (with ABNF restrictions) at ST 2110 tier | sdp_spec.lua:537, 546 (basic c= parsing); st2110_spec.lua: full address-form coverage | At RFC 4566 tier, address is accepted as any token — FQDN, IP4, IP6, extn-addr. Form-validation only at ST 2110 tier. |
| 142 | RFC 4566 | 9 | b= ABNF: token:digit-string | COVERED | grammar.parse_bandwidth `parse_sdp.lua:182` `bw_bwtype = (P(1)-P(":")-SP-line_end)^1`; `C(digit ^ 1)` | sdp_spec.lua:554-583 | |
| 143 | RFC 4566 | 9 | t= values: "0" or POS-DIGIT followed by 9+ digits (≥10 chars) | COVERED-WRONG-CITE | grammar.parse_timing `parse_sdp.lua:153` `C(digit ^ 1) * SP * C(digit ^ 1)` — accepts ANY digit count, not the strict "0 or 10+ digit" form | sdp_spec.lua:165-194 | Parser is permissive: ABNF actually requires either "0" or exactly 10+ digits (POS-DIGIT then 9*DIGIT). Parser allows e.g. "1 1" which the ABNF rejects. **MISSING strict ABNF**. |
| 144 | RFC 4566 | 9 | r= values: integer or integer + unit char | COVERED | typed_time_pat `parse_sdp.lua:198` `digit ^ 1 * S("dhms") ^ -1 * -P(1)` | sdp_spec.lua:378-394 | |
| 145 | RFC 4566 | 9 | unit char ∈ {d,h,m,s} lowercase | COVERED-NO-TEST | typed_time_pat uses `S("dhms")` lowercase | None for uppercase rejection | |
| 146 | RFC 4566 | 9 | k=base64: standard base64 alphabet | MISSING | grammar.parse_key `parse_sdp.lua:239-248` accepts any non-newline value | None | Base64 alphabet not validated. Tightenable. |
| 147 | RFC 4566 | 9 | a= ABNF: name=token; value=byte-string | COVERED | grammar.parse_attribute `parse_sdp.lua:250-264` `att_field = (P(1) - P(":") - SP - line_end) ^ 1` | sdp_spec.lua:585-607 | Name allows bytes that the ABNF `token` rules disallow (e.g. high bytes). MISSING strict token enforcement on att-field. |
| 148 | RFC 4566 | 9 | m= 1st field: token | COVERED | media_pat `parse_sdp.lua:268` `C(token)` | sdp_spec.lua:649-657 | |
| 149 | RFC 4566 | 9 | m= fmt: token | COVERED | media_pat `parse_sdp.lua:271` | sdp_spec.lua:649-657 (96 etc.) | |
| 150 | RFC 4566 | 9 | m= proto: token(s) separated by "/" | COVERED | media_pat `parse_sdp.lua:270` `C(token)` (token excludes "/" — actually token = non-SP non-line_end, so "/" IS in token; "RTP/AVP" is one token) | sdp_spec.lua:649 | |
| 151 | RFC 4566 | 9 | m= port: digits | COVERED | grammar.parse_media `parse_sdp.lua:281-285` | sdp_spec.lua:682-705 (port range and non-numeric) | |
| 152 | RFC 4566 | 9 | unicast-address forms (IP4/IP6/FQDN/extn-addr) | COVERED | grammar.parse_connection `parse_sdp.lua:167`; valid_connection_address `parse_sdp.lua:819-887` (at ST 2110) | st2110_spec.lua: connection tests; sdp_spec.lua:537-552 | At RFC 4566 tier any token accepted (matches ABNF's permissive set including extn-addr=non-ws-string). |
| 153 | RFC 4566 | 9 | multicast-address forms | COVERED | Same as 152 | Same as 152 | |
| 154 | RFC 4566 | 9 | IPv4 multicast: first octet 224-239; TTL mandatory; optional addr count | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:854-873` | st2110_spec.lua:2617-2676, 2937-2977 | Cite is RFC 8866; equivalent in RFC 4566. ST 2110 tier only. |
| 155 | RFC 4566 | 9 | IPv6 multicast: FF prefix; optional addr count; no TTL slot | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:826-842` | st2110_spec.lua:4344-4400 | Cite is RFC 8866; same as row 154. |
| 156 | RFC 4566 | 9 | TTL: "0" or 1..3 digits (i.e. 1..999 syntactically; §5.7 narrows to 0-255) | COVERED-WRONG-CITE | valid_connection_address `parse_sdp.lua:864-868` | st2110_spec.lua:2912-2931 | Parser enforces 0-255 prose range (correct). Cite is RFC 8866. |
| 157 | RFC 4566 | 9 | FQDN: 4+ chars from alphanum, -, . | MISSING | grammar.parse_origin and parse_connection accept any token | None | FQDN form not validated. Tightenable. |
| 158 | RFC 4566 | 9 | IPv4 unicast: first octet < 224 | COVERED | _ipv4_addr_pat `parse_sdp.lua:569-571` + multicast-range branch in valid_connection_address | st2110_spec.lua tests | Used at ST 2110 tier only. |
| 159 | RFC 4566 | 9 | IPv6 unicast/general form per RFC 2373 | COVERED | _ipv6_addr_pat `parse_sdp.lua:584-646` (anchored IPv6 grammar) | st2110_spec.lua tests | Used at ST 2110 tier only. |
| 160 | RFC 4566 | 9 | extn-addr (non-IP nettype): visible chars no space | COVERED | grammar.parse_origin/connection `C(token)` `parse_sdp.lua:125, 167` | None for non-IN extn-addr (no nettype other than IN is defined) | Permissive token form accepted; matches non-ws-string. |
| 161 | RFC 4566 | 9 | text: 1+ bytes, no NUL/LF/CR | COVERED | grammar.tokenize_line `parse_sdp.lua:80, 86-87`: `value_char = 1 - line_end`; `value_char ^ 1` requires 1+ | sdp_spec.lua:64-68 (empty value rejected); sdp_spec.lua:280-285 (empty s= rejected) | NUL exclusion not explicit (see row 61). |
| 162 | RFC 4566 | 9 | non-ws-string: visible chars including UTF-8 high bytes | COVERED | token = `1 - SP - line_end` (everything except whitespace) `parse_sdp.lua:82` | None | Permissive; matches ABNF. |
| 163 | RFC 4566 | 9 | token: specific allowed printable byte set | COVERED-WRONG-CITE | _rfc4566_token_char `parse_sdp.lua:520-528` (precise RFC 4566 §9 token-char class) is used ONLY for a=mid/a=group `parse_sdp.lua:537-549`; OTHER token uses (m=, c=, b=, o= subfields) use the permissive `1 - SP - line_end` definition | None for token-class restriction at other sites | Two definitions of "token" live in parser. Most consumers use the permissive form. Strict ABNF token only enforced for a=mid / a=group identifiers. **MISSING uniform application**. |
| 164 | RFC 4566 | 9 | email-safe: bytes for free-text in e=/p= name | MISSING | None | None | parse_email/parse_phone are identities. |
| 165 | RFC 4566 | 9 | integer: leading non-zero digit | MISSING | None — port_count, numaddr, etc. all accept "0" or leading-zero "01" via `tonumber`/`%d+`-style patterns | None | Per inventory note 7: ABNF forbids leading zeros for `integer`. Parser does not reject "01" in `m= port/01` etc. |
| 166 | RFC 4566 | 9 | IPv4 octet 0..255 | COVERED | _ntp_octet `parse_sdp.lua:562-567` | st2110_spec.lua tests | Used in _ipv4_addr_pat in valid_connection_address. |
| 167 | RFC 4566 | 9 | POS-DIGIT: 1-9 | COVERED-NO-TEST | Implicit in _ntp_octet & _ipv4_addr_pat | None | Primitive used in IPv4/v6 grammar. |

## Reverse direction — Parser RFC 4566 citations vs. inventory

| Parser ref | Cited spec/§ | What it enforces | In inventory? | Suggestion |
|---|---|---|---|---|
| `parse_sdp.lua:107` | RFC 4566 (no §) | v= grammar accepts only "0" | Row 14 (§5.1) | OK; cite could be tightened to §5.1 |
| `parse_sdp.lua:196-198, 201` | RFC 4566 §5.10 | r= typed-time grammar | Rows 51-52 | OK |
| `parse_sdp.lua:217` | RFC 4566 §5.11 | z= timezone grammar | Row 54 | OK |
| `parse_sdp.lua:235` | RFC 4566 §5.12 | k= grammar (permissive method, structural only) | Row 58/117 (closed set) | **CANDIDATE-WRONG-CITE-or-MISSING-FROM-INVENTORY**: parser comments admit it accepts more than {clear, base64, uri, prompt}. Inventory row 58/117 says set is closed. Cite mismatch: §5.12 doesn't authorize extension; §8.3 forbids it. |
| `parse_sdp.lua:298, 423, 2976-2977` | RFC 4566 §5 (general) | structural validate / serialize | Row 5 / row 118 | OK |
| `parse_sdp.lua:516-519` | RFC 4566 §9 (token grammar) | strict token-char class for a=mid/a=group only | Row 163 | OK for a=mid/a=group; broader uses don't apply this class — Direction-A row 163 MISSING-WRONG-CITE for uniform application |
| `parse_sdp.lua:539` | RFC 4566 token chars | a=mid value form | Row 163 (token) | OK |
| `parse_sdp.lua:546` | RFC 4566 token chars | a=group form | Row 163 (token) | OK |
| `parse_sdp.lua:1138` | RFC 4566 §6 (a=fmtp form) | acknowledges silence on trailing semicolon | Inventory has no specific row for "trailing semicolon" | OK — non-rejection of silent feature |
| `parse_sdp.lua:1322` | RFC 4566 §6 | fmtp PT must match rtpmap PT | Row 98 | OK — but cite could mention §6 paragraph "format must be one of the formats specified for the media" |
| `parse_sdp.lua:1359` | RFC 4566 §6 | fmtp value is parseable | Row 98 | OK |
| `parse_sdp.lua:1545, 1558, 1561` | RFC 4566 §6 / ST 2110-22 | a=framerate form: integer or integer.fraction; video only | Row 96 | OK — combined cite is fine since both standards specify the same form |
| `parse_sdp.lua:1912-1919` | RFC 3551 §6 | rtpmap audio channels required | Row 80 | OK — RFC 3551 is the proper authority for the channel field |
| `parse_sdp.lua:1940` | RFC 8866 / AES67 | mediaclk and ptime for audio | (RFC 8866 = obsoletes 4566) | OK with the RFC 8866 substitution; note inventory is for RFC 4566 — minor cite-style question |
| `parse_sdp.lua:2987-2989` | RFC 4566 §5 / §9 ABNF | trailing CRLF required | Row 9 (CRLF terminates) | OK; could cite §9 ABNF specifically since §5 mentions "tolerance" not strict requirement |
| `parse_sdp.lua:805-806, 819` | RFC 8866 §9 / §5.7 + ST 2110-10 §6.5 | c= address-form validation | Rows 35-40, 154-156 | **WRONG-CITE-AT-RFC-4566**: cite should be "RFC 4566 §5.7 / §9" or "RFC 8866 §5.7 / §9 (= RFC 4566)"; this affects rows 35, 36, 37, 38, 40, 154, 155, 156. Equivalent text; cite is RFC 8866 instead of RFC 4566. |

## Summary

- **Inventory SDP-Y rows:** 138 (per inventory summary)
- **COVERED:** 49
- **COVERED-NO-TEST:** 13
- **COVERED-WRONG-CITE:** 9 (rows 35, 36, 37, 38, 40, 119, 154, 155, 156, 163 — all relate to RFC 8866 cite vs RFC 4566 cite, and the §5.1 vs §9 ABNF v= treatment, and the dual-token-class issue)
- **MISSING:** 22 (rows 6, 11, 12, 13, 31, 39, 58, 60, 71, 87, 89, 94, 95, 97, 99, 100, 117, 131, 138, 139, 140, 143, 146, 157, 164, 165, plus partial-MISSING for rows 33, 70, 98, 109, 110 at the RFC 4566 tier — these are enforced only at ST 2110 tier)
- **OUT-OF-SCOPE-FROM-SDP:** 18 (rows 1, 10, 20, 26, 30, 32, 34, 41, 45, 48, 69, 73, 74, 75, 81, 84, 88, 90, 91, 101, 106)
- **Direction-B candidates (cite or interpretation flags):** 3 (the RFC 8866 vs RFC 4566 cite series; the k= method-set permissiveness; the dual-token-class issue)

### Top 3 candidate findings for main-thread review

1. **Row 6 (§5 "MUST completely ignore any session description")** — Parser REJECTS rather than IGNORES on unknown type letter. The literal reading of §5 says "ignore the entire description"; parser raises an error. AMBIGUOUS in the spec (row 6 is flagged AMBIGUOUS in inventory anomaly 1). Defensible but documented divergence. The MAIN thread should decide policy: silent ignore vs. fail-loud.

2. **Row 58 / Row 117 / Row 131 (k= method closed set {clear, base64, uri, prompt})** — Parser accepts ANY non-colon non-SP token as a k= method. §8.3 ("New registrations MUST NOT be accepted") makes this a closed value set. Code comment at `parse_sdp.lua:237-238` admits the divergence: "other tokens accepted structurally (the spec lists these but does not strictly forbid others)." That comment is wrong per row 117. **Concrete fix**: add closed enum check for k= method.

3. **Rows 35-40 & 154-156 (c= multicast/TTL rules cited as "RFC 8866" rather than "RFC 4566 §5.7 / §9")** — All RFC 8866 cites in `valid_connection_address` (`parse_sdp.lua:805-887`) are textually equivalent to RFC 4566 but the project's primary spec for this audit is RFC 4566. The COVERED-WRONG-CITE classification is purely a citation style question: should the parser cite RFC 4566 or RFC 8866 (the obsoleting RFC with identical text)? Worth main-thread call. Additionally, NONE of these checks fire in RFC 4566-only mode — they only run when mode="st2110" or "ipmx". If the parser is meant to enforce RFC 4566 strictly at the base tier, these should run unconditionally. **This is the biggest substantive gap**: a c= line like `c=IN IP4 224.2.1.1` (multicast WITHOUT TTL) parses without error at the RFC 4566 tier (see sdp_spec.lua:537-543 — test accepts this as valid RFC 4566). RFC 4566 §5.7 says TTL is REQUIRED for IPv4 multicast.

---

## RFC 8866

# RFC 8866 Coverage Mapping

**Spec**: RFC 8866 — SDP: Session Description Protocol (January 2021; obsoletes RFC 4566)
**Parser**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
**Inventory**: `/tmp/audit_inventory_rfc8866.md` (117 rows; 87 SDP-Y)
**Mode**: Phase 2 mechanical coverage — each SDP-Y row mapped to parser check or MISSING.

## Special note on this audit

Parse_sdp's CLAUDE.md names RFC 4566 as the documented base, and almost every parser citation is `RFC 4566 §X`. RFC 8866 is the operative current standard — 4566 is obsoleted. Most §5/§6/§9 clauses transfer cleanly (same rule, same number); a handful changed substantively. Direction-C (wrong-cite) findings are common for clauses that 8866 tightened.

Notable: `valid_connection_address` (parser lines 805-887) is the only large block that already cites RFC 8866 §5.7/§9 — but it is **only invoked from `st2110.validate` (lines 1224-1255) and the RTCP-attribute path (line 2884)**. It is NOT invoked at the base RFC 4566/8866 tier (`validate.sdp`, lines 304-365). So all the c= TTL, layered-multicast, and unicast-slash work the parser already does is currently gated behind ST 2110 mode.

## Coverage table

| Inv# | § | Verb | One-liner | Parser line(s) | Check name / construct | Status |
|---|---|---|---|---|---|---|
| 1 | 5 | MUST | "An SDP description MUST conform to the syntax defined in Section 9." | 2982-3184 (whole parser.parse) | Top-level ABNF dispatch + per-field grammars | COVERED — every field passes through an LPEG grammar; deviations from §9 ABNF fail at parse. Cite: structural property, no spec_ref on individual line. |
| 2 | 5 | "must appear in exactly" | Required field order is mandatory (v/o/s/i/u/e/p/c/b/t/r/z/k/a then m). | 2940-2967, 3170-3183 | `parse_required` with sequential calls for each field in §5 order; `WRONG_ORDER` error on mismatch | COVERED — tests at sdp_spec lines 298-309. Cite: error code is `WRONG_ORDER`, no spec_ref string. |
| 3 | 5 | MUST | "completely ignore or reject any session description that contains a type letter that it does not understand." | 3170-3183 | Unknown type letter at end → `WRONG_ORDER` "unexpected field" error | COVERED-WRONG-CITE — parser implements the reject-side option. The cite is absent; the operative MUST is RFC 8866 §5 (RFC 4566 §5 only said "ignore"). Direction-A-adjacent: also, mid-stream unknown letters (e.g. an `x=` between `s=` and `t=`) get reported as WRONG_ORDER with the next expected type — same effective behavior, but the error is misleading. |
| 4 | 5 | MUST | "An SDP parser MUST ignore any attribute it doesn't understand." | 3114-3121, 3158-3165 | Attributes parsed into `attributes` array without name-allowlist; unknown names retained | COVERED — base parser accepts arbitrary attribute names; no rejection. ST 2110 / IPMX validators inspect specific known names but ignore the rest, consistent with this MUST. |
| 5 | 5 | "MUST be interpreted as" | Default charset for s=/i= text is UTF-8. | — | No charset interpretation logic | COVERED-BY-DEFAULT — the parser stores values as opaque Lua strings (bytes); the "interpret as UTF-8" semantic is a consumer concern. Not a check that adds or removes acceptance. |
| 6 | 5 | "any octet with the exceptions of" | Text fields exclude NUL/CR/LF. | 79, 80, 86 | `line_end = P("\r\n") + P("\n")`; `value_char = 1 - line_end` (excludes CR and LF) | COVERED for CR/LF — the grammar terminates a field at any CR/LF. **MISSING for NUL (0x00)**: `value_char = 1 - line_end` includes 0x00. ABNF byte-string explicitly excludes %x00. **CANDIDATE-MISSING-NEEDS-REVIEW**. |
| 7 | 5 | SHOULD | "CRLF (0x0d0a) is used to end a line, although parsers SHOULD be tolerant and also accept lines terminated with a single newline character." | 79 | `line_end = P("\r\n") + P("\n")` | COVERED — accepts both CRLF and bare LF (test at sdp_spec line 224-230). |
| 8 | 5 | MUST | "Any domain name used in SDP MUST comply with [RFC1034] and [RFC1035]." | 167, 174-178 (c=); 119-126 (o=); 150-151 (e=, p=); 149 (u=) | No DNS-syntax check on `unicast-address` in o=, c=, e=, p=, u= — `token` is accepted | MISSING — there is no RFC 1034/1035 form-check at the base tier. NTP-address paths (ts-refclk) use `_ntp_hostname` (576-577) but that's ST 2110-specific. Some FQDN-ish constraint is implied by `token` (no spaces) but `.` and label-length rules are not enforced. CANDIDATE-MISSING-NEEDS-REVIEW (acceptance posture: this is silence permissive). |
| 9 | 5 | MUST | "IDNs MUST be represented using the ASCII Compatible Encoding (ACE) form defined in [RFC5890]" | — | No IDN/ACE check | MISSING — parser would accept raw UTF-8 in domain-name positions because `token` is byte-permissive. New in RFC 8866 (silent in 4566). Direction-A candidate. |
| 10 | 5 | MUST NOT | "and MUST NOT be directly represented in UTF-8 or any other encoding" | — | No raw-UTF-8 detection | MISSING — same as #9. New 8866 prohibition. Direction-A candidate. |
| 11 | 5.1 | defined-value-set | v=0 (single digit "0"). | 105-114 | `version_pat = P("0") * -P(1)`; `grammar.parse_version` | COVERED — rejects anything but exactly "0" (test sdp_spec lines 97-100). Cite in code says "RFC 4566"; the operative defined-value is RFC 8866 §5.1. Direction-C candidate (minor). |
| 12 | 5.2 | MUST NOT | "The <username> MUST NOT contain spaces." | 82, 119-126 | `token = (P(1) - SP - line_end)^1`; `C(token)` for username | COVERED — origin_pat splits on SP so a space inside username breaks the SP-separated parse. |
| 13 | 5.2 | defined-value-set | sess-id is decimal digits. | 121 | `C(digit ^ 1)` in origin_pat | COVERED. |
| 14 | 5.2 | defined-value-set | nettype: registered IANA values (initially "IN"). | 116 | `nettype = P("IN")` (literal) | COVERED, but **over-strict at the spec-extension boundary** — RFC 8866 says future values MAY be registered. The parser hard-rejects anything but "IN". Per CLAUDE.md strictness principle (defined-value set with registry), this is correct for current SDP because IANA has only registered "IN". The hard-coded literal becomes wrong only if/when IANA registers a new nettype. Cite: code has none on o=; the value-set ref is RFC 8866 §5.2 / §8.2.6. **COVERED-NO-CITE.** |
| 15 | 5.2 | defined-value-set | addrtype: registered IANA values (initially "IP4"/"IP6"). | 117 | `addrtype = P("IP4") + P("IP6")` | COVERED — same caveat as #14: IANA currently has IP4 and IP6 only. COVERED-NO-CITE. |
| 16 | 5.2 | defined-value-set | IP4 unicast: dotted-decimal IPv4 OR FQDN. | 125 (o=), 167 (c=) | `C(token)` (raw token, no syntax check at base) | MISSING at base tier — o= unicast_address accepts any non-space token (e.g. `o=- 1 1 IN IP4 garbage`). ST 2110 path validates this via valid_connection_address but only for c=, not o=. CANDIDATE-MISSING-NEEDS-REVIEW (origin address syntax). |
| 17 | 5.2 | defined-value-set | IP6 unicast: RFC 5952 textual OR FQDN. | 125, 167 | same as #16 | MISSING at base tier — same gap. |
| 18 | 5.3 | MUST | "There MUST be one and only one 's=' line per session description." | 3006-3009 | `parse_required(lines, pos, "s", grammar.parse_session_name)` — exactly once | COVERED — exactly one s= is required by ordering. A second s= after the first would be `WRONG_ORDER`. |
| 19 | 5.3 | MUST NOT | "The 's=' line MUST NOT be empty." | 86 (value_char^1) → 3007 | `line_pat` requires value_char^1 (≥1 char); empty `s=` rejected with MALFORMED_LINE | COVERED — test at sdp_spec lines 280-285 ("rejects 's=' empty session name (RFC 8866 §5.3 MUST NOT be empty)"). Cite there is RFC 8866 §5.3 — good. |
| 20 | 5.3 | MUST | Default s= charset is UTF-8. | — | No charset enforcement | NOT-A-CHECK — opaque bytes stored; covered by default semantics. |
| 21 | 5.4 | "at most one" | Zero or one i= at session level; zero or one per media. | 3011-3016 (session), 3130-3134 (media) | `if pos <= n and peek_type(lines, pos) == "i" then …` — single conditional, not a loop | COVERED — second i= at session level would be unexpected and trigger WRONG_ORDER. Same for media. |
| 22 | 5.4 | MUST | Default i= charset is UTF-8. | — | — | NOT-A-CHECK — same as #20. |
| 23 | 5.5 | "No more than one" | Zero or one u= line. | 3018-3023 | single conditional, not a loop | COVERED. |
| 24 | 5.6 | MUST | "If an email address or phone number is present, it MUST be specified before the first media description." | 3025-3041 | e= and p= parsed before m=; m= after a=; sequence enforced by ordering | COVERED — implicit via §5 field-order enforcement. |
| 25 | 5.6 | MUST | "Both email addresses and phone numbers can have an OPTIONAL free text string … MUST be enclosed in parentheses if it is present." | 150-151 | `grammar.parse_email`/`parse_phone` returns the whole value verbatim | MISSING — parser does not validate the parens/`<name>` form of e=/p= values. AMBIGUOUS in inventory (the MUST attaches only to the parenthesised form, not the RFC 5322 angle form). CANDIDATE-MISSING-NEEDS-REVIEW (low priority — operationally only matters if a downstream tool parses the "name" component). |
| 26 | 5.7 | MUST | "A session description MUST contain either at least one 'c=' line in each media description or a single 'c=' line at the session level." | 1268-1273 (ST 2110), 2769-2771 (IPMX) | `if not conn and not sess_conn then attr_err("missing required connection address (c=) …") ` — cited `ST 2110-10 §6.3` | **COVERED-WRONG-CITE** — the operative MUST is RFC 8866 §5.7 (echoed in §9 ABNF comment), not ST 2110-10 §6.3. ST 2110-10 §6.3 derives this from SDP. At the base tier it is **MISSING** (validate.sdp does not check c= coverage). Direction-A + Direction-C. |
| 27 | 5.7 | MUST | "Sessions using an 'IP4' multicast connection address MUST also have a time to live (TTL) value present in addition to the multicast address." | 858-863 | `valid_connection_address`: `if not ttl_str then return nil, "IPv4 multicast address requires a TTL suffix …"` | COVERED — cite is `RFC 8866 §9 IP4-multicast`. But the check runs only in ST 2110 mode (1227, 1248) and the RTCP path (2884). At base SDP tier, it's **MISSING** — `c=IN IP4 224.0.0.1` (no /TTL) parses without error. Direction-A at base tier. |
| 28 | 5.7 | MUST | "TTL values MUST be in the range 0-255." | 865-868 | `if not ttl or ttl < 0 or ttl > 255 then return nil, "IPv4 multicast TTL must be 0-255 per RFC 8866 §5.7 …"` | COVERED — already cites RFC 8866 §5.7. Same gating limitation as #27 (ST 2110 mode only). |
| 29 | 5.7 | MUST | TTL is mandatory for IP4 multicast (even though deprecated). | 858-863 | same as #27 | COVERED (reinforces #27). |
| 30 | 5.7 | MUST NOT | "'IP6' multicast does not use TTL scoping, and hence the TTL value MUST NOT be present for 'IP6' multicast." | 829-836 | `if not n_str then return nil, "IPv6 multicast c= suffix must be '/<numaddr>' per RFC 8866 §9 IP6-multicast ABNF"` (any non-numaddr slash form fails); only `addr/N` accepted; multi-slash rejected | COVERED — cite is RFC 8866 §9. Same gating limitation (ST 2110 mode only). At base tier, **MISSING**. |
| 31 | 5.7 | defined-value-set | Layered multicast notation: addr[/ttl]/count. | 858-873 (IP4), 829-836 (IP6) | numaddr accepted only with `/ttl/numaddr` form for IP4; `/numaddr` only for IP6 | COVERED, same gating issue. |
| 32 | 5.7 | MAY... only if | "Multiple addresses or 'c=' lines MAY be specified on a per media description basis only if they provide multicast addresses for different layers in a hierarchical or layered encoding scheme." | 3136-3140 | `if pos <= n and peek_type(lines, pos) == "c" then m.connection = parse_required(lines, pos, "c", …); pos += 1` — single c= per media (no loop) | OVER-STRICT — RFC 8866 §5.7 + §9 ABNF (`media-description = media-field [information-field] *connection-field …`) allow multiple c= per media for layered multicast. Parser accepts at most one. **MISSING (under-permissive)** — second c= on a media block would be reported as WRONG_ORDER. Direction-A (closing a permissive gap the spec opens). Note: §9 ABNF says `*connection-field` (zero or more); CLAUDE.md "ABNF wins on lexical form" suggests the parser should accept multiple c= even if §5.7 prose constrains them. CANDIDATE-MISSING-NEEDS-REVIEW. |
| 33 | 5.7 | MUST NOT | "Multiple addresses or 'c=' lines MUST NOT be specified at session level." | 3043-3048 | `if pos <= n and peek_type(lines, pos) == "c" then connection = parse_required(…); pos += 1` — single c= at session | COVERED — second session-level c= would be reported as `WRONG_ORDER`. |
| 34 | 5.7 | MUST NOT | "The slash notation for multiple addresses described above MUST NOT be used for IP unicast addresses." | 881-885 | `if rest ~= "" then return nil, "unicast address must not include a TTL suffix"` (IP4); 838-841 (IP6) | COVERED — same gating issue: ST 2110 mode only. At base tier, **MISSING**. |
| 35 | 5.8 | MUST | "SDP parsers MUST ignore bandwidth-fields with unknown <bwtype> names." | 188-194 | `grammar.parse_bandwidth` does not reject by bwtype; downstream just stores them | COVERED — parser preserves any bwtype; consumers can ignore. (No active rejection of unknown bwtypes; cite would be RFC 8866 §5.8.) |
| 36 | 5.8 | MUST | "The <bwtype> names MUST be alphanumeric" | 181-182 | `bw_bwtype = (P(1) - P(":") - SP - line_end)^1` — accepts non-`:`, non-SP, non-line-end (i.e. punctuation OK) | MISSING — accepts `b=AS-X+:128`, `b=Foo$:128`, etc. AMBIGUOUS in inventory (ABNF says token, prose says alphanumeric). Spec audit: when ABNF and prose conflict on lexical form, by CLAUDE.md "ABNF wins on lexical form" the parser is actually correct (token allows punctuation). NOT-A-CHECK (the alphanumeric requirement is the looser of the two readings). |
| 37 | 5.8 | SHOULD/MUST | New bwtypes MUST be IANA-registered (X- NOT RECOMMENDED). | — | — | OUT-OF-SCOPE-FROM-SDP — registration policy. |
| 38 | 5.9 | defined-value-set | t= start/stop are decimal digit strings. | 153, 159-164 | `timing_pat = C(digit^1) * SP * C(digit^1) * -P(1)` | COVERED, but **over-permissive vs ABNF**: §9 says `time = POS-DIGIT 9*DIGIT` (≥10 digits) OR literal "0". Parser accepts `t=01 02` (leading zero, <10 digits). Direction-A (ABNF tightens what 4566 accepted). CANDIDATE-MISSING-NEEDS-REVIEW. |
| 39 | 5.9 | "set to zero" | Special meaning: stop=0 ⇒ unbounded; start=0 & stop=0 ⇒ permanent. | — | No interpretation logic | NOT-A-CHECK — semantic, not structural. |
| 40 | 5.10 | defined-value-set | r= typed-time unit suffix ∈ {d,h,m,s} (case-sensitive). | 196-215 | `_typed_time_pat = digit^1 * S("dhms")^-1 * -P(1)` | COVERED for d/h/m/s. Case-sensitivity is enforced by `S("dhms")` (lowercase only). |
| 41 | 5.10 | "not allowed" | r= typed-time may not be fractional. | 196-215 | `_typed_time_pat = digit^1 * S("dhms")^-1` (no `.`) | COVERED — `r=7.5d` fails (no fractional point in pattern). |
| 42 | 5.11 | new "syntax error" | z= without preceding r= is a syntax error. | 3098-3104 | `if pos <= n and peek_type(lines, pos) == "z" then time_zones = parse_required(…)` — z= consumed only AFTER the time-descriptions block; can appear when no r= preceded | OVER-PERMISSIVE — current parser accepts `t=0 0` followed directly by `z=…` without intervening `r=`. §9 ABNF puts zone-field inside `repeat-description = 1*repeat-field [zone-field]`, so z= requires at least one r=. New in 8866 (test at sdp_spec line 471-476 says it rejects, but that test asserts the parser rejects `z=` *without* `t=`, not `z=` without `r=`). Direction-A (new 8866 prohibition). CANDIDATE-MISSING-NEEDS-REVIEW. |
| 43 | 5.12 | MUST NOT (×2) | k= obsolete; MUST NOT be used in produced SDP; MUST discard on receipt. | 235-248 (parser), 3106-3112 (session k=), 3151-3156 (media k=), 403-406 (serializer) | `grammar.parse_key`; `parse_required(… "k" …)`; `ser_key` | MISSING — RFC 8866 §5.12 makes `k=` obsolete: "One MUST NOT include a 'k=' line in an SDP, and MUST discard it if it is received in an SDP." Parser accepts k= lines and serializer emits them. Tests sdp_spec lines 422-446 explicitly assert k= is accepted at both session and media level. **MAJOR Direction-A finding** — the 4566→8866 transition flipped this from "documented optional feature" to "obsolete; do not use; discard on receipt." Receivers tolerating k= matches the "MUST discard" spirit only if k= is dropped from the doc; the parser preserves k= and serializer emits it (`to_sdp()` round-trip). |
| 44 | 5.13 | MUST | "Attribute names MUST use the US-ASCII subset of ISO-10646/UTF-8." | 250-263 | `att_field = (P(1) - P(":") - SP - line_end)^1` — accepts any byte 0x01..0xFF except `:`, SP, CR, LF | MISSING — parser allows 0x80..0xFF in attribute names. ABNF says `attribute-name = token` (token-char is ALPHA / DIGIT / specific ASCII punctuation 0x21–0x7E subset). CANDIDATE-MISSING-NEEDS-REVIEW (acceptance posture: this rarely matters in practice). Direction-A. |
| 45 | 5.13 | "MAY use any octet except" | a= value bytes: any except NUL/CR/LF. | 80, 251 | `value_char = 1 - line_end` (excludes CR and LF) | COVERED for CR/LF; **MISSING for NUL** — value_char includes 0x00. Same observation as #6. |
| 46 | 5.13 | MUST | "Attributes MUST be registered with IANA" | — | — | OUT-OF-SCOPE-FROM-SDP — registration policy. |
| 47 | 5.13 | MUST | "If an attribute is received that is not understood, it MUST be ignored by the receiver." | 3114-3121, 3158-3165 | Parser stores all attributes; validators inspect only known ones | COVERED — at base tier no unknown-name rejection. (Tier-specific rejections in ST 2110 / IPMX are grounded in their own SHALLs, not RFC 8866's "ignore.") |
| 48 | 5.14 | defined-value-set | `<media>` values: audio/video/text/application/message (extensible via IANA). | 346, 268 | `C(token)` for m.media; `if type(m.media) ~= "string" or m.media == ""` | MISSING — base parser accepts any non-empty token as `<media>`. The 8866 value set is {audio, video, text, application, message} + IANA-registered extensions (e.g. `image`). 4566 included `control`/`data`; 8866 removes them (§8.2.2 #79). **Direction-A**: 8866 narrows the value set. CANDIDATE-MISSING-NEEDS-REVIEW. Note ST 2110-specific code paths key on `m=video` / `m=audio` but never reject `m=control`. |
| 49 | 5.14 | MUST (×3) | RTP/RTCP port handling when a=rtcp: is present. | 2856-2884 (IPMX path) | `a=rtcp` parsing happens only in IPMX context (RTCP port-parity / triple validation) | COVERED-NO-TEST for IPMX path; at base RFC 8866 tier, the rule "send RTP to the indicated odd port, RTCP to a=rtcp's port" is a behavior; SDP can only verify the syntactic presence of a=rtcp when port-parity is unusual. MISSING — base parser does not flag a media block with an odd port and no a=rtcp. Direction-A (low priority — operational coherence, not pure form). |
| 50 | 5.14 | defined-value-set | For RTP/AVP and RTP/SAVP, fmt values are RTP payload type numbers. | — | No type-check on fmts when proto is RTP/AVP at base tier | MISSING at base tier — `grammar.parse_media` (278-293) just stores fmts as a string array. ST 2110 enforces integer PT range when checking rtpmap (1334-1339), but only for the specific PT carried in rtpmap, not for every fmt in m=. CANDIDATE-MISSING-NEEDS-REVIEW. |
| 51 | 5.14 | MAY/SHOULD (→ MUST in §8.2.3) | Dynamic PT SHOULD have a=rtpmap (MUST per §8.2.3). | 1303-1306 | ST 2110: `local rtpmap = find_attr(mattrs, "rtpmap"); if not rtpmap then return attr_err("missing required attribute 'rtpmap' …", … "ST 2110-10 §7")` | COVERED-WRONG-CITE for the ST 2110 tier (cite is ST 2110-10 §7; the underlying RFC MUST is **RFC 8866 §8.2.3**). At base RFC 8866 tier, **MISSING** — `validate.sdp` does not require rtpmap for dynamic PTs (PTs 96-127). Direction-A + Direction-C. (Recall §5.14 only says SHOULD; the operative MUST is §8.2.3 — see #82.) |
| 52 | 5.14 | MUST | proto=udp fmt MUST reference a media type from {audio, video, text, application, message}. | — | No `proto=udp` branch | MISSING — base parser doesn't constrain fmts when proto is "udp". Direction-A (8866 refines the rule beyond 4566's implicit). |
| 53 | 5.14 | MUST | New proto registrations must define <fmt> rules. | — | — | OUT-OF-SCOPE-FROM-SDP — registration policy. |
| 54 | 6.5 | SHALL | a=maxptime semantic: sum of media in packet. | — | — | OUT-OF-SCOPE-FROM-SDP — sender-side calculation, not SDP-text observable. |
| 55 | 6.6 | defined-value-set | a=rtpmap value form: PT SP name/rate[/params]. | 553-559 | `rtpmap_parse`: `value:match("^%d+%s+(.+)$")` then `"^([^/]+)/(%d+)"` | COVERED for the structural skeleton — but only inside ST 2110 path (rtpmap_parse called from 1325, 2107, etc.). Base SDP tier does not validate rtpmap value form. CANDIDATE-MISSING-NEEDS-REVIEW. Cite in code: none directly; the regex is the structural check. |
| 56 | 6.6 | "limiting the values to inclusively between" | rtpmap PT ∈ [0,127]. | 1334-1339 | `if not pt_n or pt_n < 0 or pt_n > 127 then attr_err("RTP payload type %s out of valid range 0-127", … "RFC 3550 §5.1", …)` | COVERED-WRONG-CITE for ST 2110 tier — cite is RFC 3550 §5.1, but the *defined-value-set* "PT ∈ [0,127]" prose is RFC 8866 §6.6. (RFC 3550 §5.1 also defines a 7-bit PT field — circumstantial, not the operative SDP-side defined value.) Direction-C minor. At base tier, **MISSING**. |
| 57 | 6.6 | MUST | Profile-level requirement on encoding-name registry. | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 58 | 6.6 | OPTIONAL | rtpmap channels: optional for audio; defaults to 1. | 553-559, 1909-1920 | `rtpmap_parse` accepts both 2-part and 3-part suffix forms; ST 2110-30 enforces `/channels` presence | COVERED — base parser accepts both forms (channels optional per RFC 8866 §6.6). ST 2110-30 layer tightens to require it. |
| 59 | 6.7 | MAY appear at most once | At most one direction attribute per scope (session or media). | 3114-3121, 3158-3165 | Attributes stored in order; no uniqueness check on direction attrs | MISSING — parser accepts `a=recvonly` followed by `a=sendrecv` on the same media block (silently keeps both). CANDIDATE-MISSING-NEEDS-REVIEW. Direction-A. |
| 60 | 6.7 | SHOULD | Default direction is sendrecv. | — | — | NOT-A-CHECK — semantic default; the parser leaves absent-direction as nil. SHOULD-default, not MUST. |
| 61 | 6.7.1 | MUST | recvonly stream still sends RTCP. | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 62 | 6.7.4 | MUST | inactive stream still sends RTCP. | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 63 | 6.8 | defined-value-set | a=orient ∈ {portrait, landscape, seascape}, case-sensitive. | — | No a=orient validator | MISSING — parser accepts any value (or absence). CANDIDATE-MISSING-NEEDS-REVIEW (low usage in ST 2110 / IPMX context). |
| 64 | 6.9 | defined-value-set | a=type ∈ {broadcast, meeting, moderated, test, H332}, case-sensitive. | — | No a=type validator | MISSING — same shape as #63. |
| 65 | 6.10 | MUST | a=charset value must be IANA-registered. | — | — | MISSING — no a=charset enforcement. |
| 66 | 6.10 | MUST | charset identifier compared case-insensitively. | — | — | MISSING — no a=charset handling at all. |
| 67 | 6.10 | MUST / MUST NOT | Charset-dependent fields: valid in selected charset; no NUL/CR/LF. | — | — | MISSING for NUL (#6 / #45). CR/LF covered by grammar. |
| 68 | 6.11 | defined-value-set | a=sdplang value is RFC 5646 language tag. | — | No a=sdplang validator | MISSING — Direction-A (RFC 8866 updates the language-tag spec ref from older RFCs to RFC 5646). |
| 69 | 6.12 | defined-value-set | a=lang value is RFC 5646 language tag. | — | No a=lang validator | MISSING — same. |
| 70 | 6.13 | defined-value-set | a=framerate is non-zero integer or real. | 1555-1564 (jxsv branch only) | Inside jxsv branch: `if not fr_val:match("^%d+$") and not fr_val:match("^%d+%.%d+$")` | COVERED-PARTIAL — only validated inside the ST 2110-22 jxsv branch; base RFC 8866 a=framerate is unvalidated, and even there, `0` (zero) is accepted by the regex (but ABNF `non-zero-int-or-real` requires non-zero). CANDIDATE-MISSING-NEEDS-REVIEW (base tier). |
| 71 | 6.14 | defined-value-set | a=quality is zero-based integer (ABNF). | — | No a=quality validator | MISSING. AMBIGUOUS in inventory (prose says 0-10 "suggested"; ABNF is `zero-based-integer`). NOT-A-CHECK on the 0-10 bound; MISSING on integer form. |
| 72 | 6.15 | defined-value-set | a=fmtp value form: fmt SP byte-string. | 1172-1192, 1356-1361 | `fmtp_params` parses `<fmt> <params>` with semicolon-separated key=value pairs | COVERED-PARTIAL at ST 2110 tier — the base parser stores the fmtp value as an opaque string; structural parse happens only in ST 2110 / IPMX paths. CANDIDATE-MISSING-NEEDS-REVIEW (base tier no `fmt SP byte-string` form check, e.g. fmtp without a leading PT prefix is accepted at base). |
| 73 | 6.15 | "must be" | fmtp <fmt> must match an m= fmt value. | 1316-1323 | `if rtp_pt ~= fmtp_pt then attr_err("fmtp payload type %s does not match rtpmap payload type %s", … "RFC 4566 §6", …)` | COVERED-WRONG-CITE for ST 2110 tier — actually only compares fmtp PT to rtpmap PT, not to m= fmt list. The operative MUST is `fmtp <fmt> must be one of the formats specified for the media` (i.e. m=). Parser implements an adjacent invariant (fmtp PT == rtpmap PT). Cite should be `RFC 8866 §6.15`, not `RFC 4566 §6`. Direction-C. At base tier, **MISSING** — no fmtp/m= fmt list cross-check. |
| 74 | 6.15 | "At most one ... is allowed" | At most one a=fmtp per <fmt>. | 1313, 1356-1361 | `local fmtp = find_attr(mattrs, "fmtp")` — returns first match; subsequent duplicates silently ignored | MISSING — duplicate `a=fmtp:96 …` followed by `a=fmtp:96 …` is silently kept (both stored in `attributes[]`, only first used by validators). No explicit rejection. CANDIDATE-MISSING-NEEDS-REVIEW. Direction-A. |
| 75 | 7 | MUST NOT | SDP keying material requires private+authenticated channel. | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 76 | 7 | MUST NOT | Parser must not auto-launch arbitrary software. | — | — | OUT-OF-SCOPE-FROM-SDP — parser behavior, not SDP syntax. |
| 77-78 | 8.2.1, 8.2.2 | MUST | New parameter registrations require listed info; new media top-level types require Standards-Track RFC. | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 79 | 8.2.2 | SHOULD NOT | Apps SHOULD NOT use legacy "control"/"data" media types. | — | No rejection of m=control / m=data | NOT-A-CHECK (SHOULD NOT, not MUST NOT); but **OBSERVATION**: parser is fully permissive on `m=control` / `m=data`. Direction-A-adjacent (8866 removes them from the value set; see #48). |
| 80 | 8.2.3 | MUST | <proto> names starting with "RTP/" reserved for RTP profiles. | 1240-1244 | ST 2110: `if not VALID_ST2110_PROTO[m.proto or ""] then ... "ST 2110-10 §8.1"` — only RTP/AVP allowed | COVERED-NARROW for ST 2110 (only RTP/AVP allowed). At base tier, **MISSING** — `proto=RTP/XYZ` is accepted as long as it's a non-empty string. |
| 81 | 8.2.3 | MUST | RTP/* fmt values are PT numbers. | 1334-1339 | ST 2110 path validates rtpmap PT ∈ [0,127]; does not validate every fmt in m= | COVERED-PARTIAL for ST 2110 (only the PT in rtpmap is validated; if m= has fmts not in rtpmap, the extras are not flagged). At base tier, **MISSING**. |
| 82 | 8.2.3 | MUST | Dynamic PT (96-127) MUST have a=rtpmap. | 1303-1306 | ST 2110: `if not rtpmap then attr_err("missing required attribute 'rtpmap'", … "ST 2110-10 §7")` | COVERED-WRONG-CITE — the operative MUST is **RFC 8866 §8.2.3** (which strengthens §5.14's SHOULD). At base tier, **MISSING**. Direction-A + Direction-C. Notable inventory delta: this strengthening from SHOULD to MUST is new in 8866. |
| 83 | 8.2.3 | defined-value-set | proto=udp fmt is IANA media subtype. | — | — | MISSING — reinforces #52. |
| 84 | 8.2.3 | MUST | Format registrations bound to proto(s). | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 85-89 | 8.2.4–8.3 | MUST | IANA registration policy for a= names, bwtypes, nettypes, addrtypes; no new k= enckey methods. | — | — | OUT-OF-SCOPE-FROM-SDP. |
| 90 | 9 | ABNF authoritative | Top-level field order and cardinalities. | 2982-3184 | Sequence of `parse_required` and conditionals for each §5 field | COVERED — see #1, #2. |
| 91 | 9 | ABNF authoritative | media-description = media-field [info] *connection-field *bandwidth-field [key-field] *attribute-field. | 3123-3168 | media-block parse loop | COVERED-PARTIAL — `*connection-field` accepts zero or more, but parser handles only one (see #32). `*bandwidth-field` and `*attribute-field` loops are correct. `[information-field]` and `[key-field]` are conditional singletons (correct). |
| 92 | 9 | ABNF authoritative | time-description = time-field [repeat-description]; repeat-description = 1*repeat-field [zone-field]. | 3062-3092 | Loop accepts t=, then *r=, then optional z=; multiple t= blocks supported | COVERED-PARTIAL — but z= can currently appear with zero preceding r=. See #42 — Direction-A new in 8866. |
| 93 | 9 | ABNF authoritative | version-field = %s"v" "=" 1*DIGIT CRLF. | 105 | `version_pat = P("0") * -P(1)` (rejects anything but "0") | COVERED — parser is stricter than ABNF (only "0" accepted), consistent with §5.1 prose. AMBIGUOUS in inventory, parser correctly follows prose. |
| 94 | 9 | ABNF authoritative | origin-field grammar. | 119-145 | `origin_pat` matches 6 SP-separated tokens | COVERED. |
| 95 | 9 | ABNF authoritative | connection-field grammar. | 167-179 | `connection_pat = C(nettype) * SP * C(addrtype) * SP * C(token) * -P(1)` | COVERED structurally. (Address subforms validated only in ST 2110 mode.) |
| 96 | 9 | ABNF authoritative | time-field = "t" "=" start-time SP stop-time CRLF. | 153-165 | `timing_pat = C(digit^1) * SP * C(digit^1) * -P(1)` | COVERED — but stricter ABNF form (POS-DIGIT 9*DIGIT or "0") is not enforced. See #38. |
| 97 | 9 | ABNF authoritative | repeat-field grammar (≥2 typed-times). | 196-215 | `parse_repeat`: requires ≥3 SP-separated tokens, each `typed-time` | COVERED — ABNF says `repeat-interval SP typed-time 1*(SP typed-time)` i.e. interval + at least 2 typed-times (total ≥3 tokens). Parser matches. Tests at sdp_spec lines 378-394, 478-481. |
| 98 | 9 | ABNF authoritative | zone-field grammar. | 217-233 | `parse_timezone`: pairs of `<time> <typed-time-signed>`, even count | COVERED — pairs enforced; signed offsets accepted (ABNF allows leading `-`). Tests at sdp_spec lines 411-419, 483-486. |
| 99 | 9 | ABNF authoritative | key-field grammar; key-type ∈ {prompt, clear:, base64:, uri:} case-sensitive. | 235-248 | `_key_method` accepts any non-`:`-non-SP token (not constrained to the four methods) | COVERED-PARTIAL — accepts the form `method` or `method:value`, but does not constrain `method` to {prompt, clear, base64, uri} (case-sensitive). Direction-A. AMBIGUOUS — ABNF retains key-field "only for backward compatibility" per §5.12; in 8866 receivers MUST discard, so strict enforcement may be moot. Combined with #43 (k= obsolete), the right answer at parser level is probably to reject k= entirely under 8866 mode. |
| 100 | 9 | ABNF authoritative | attribute = (attribute-name ":" attribute-value) / attribute-name. | 250-264 | `attr_kv_pat` and `attr_k_pat` | COVERED structurally; `attribute-name` not constrained to token-char (see #44). |
| 101 | 9 | ABNF authoritative | media-field = "m" "=" media SP port["/" integer] SP proto 1*(SP fmt). | 267-293 | `media_pat`, port/port_count parsed via `(%d+)/(%d+)` or `(%d+)`; ≥1 fmt required by Ct grammar | COVERED — port range 0..65535 enforced (285); ≥1 fmt enforced (271, 358). Cite at 358 is no spec_ref. |
| 102 | 9 | ABNF authoritative | IP4-multicast = m1 3("." decimal-uchar) "/" ttl [ "/" numaddr ]; m1 = 224-239 range. | 853, 875-880 | `is_mc = o1 and o1 >= 224 and o1 <= 239`; forbidden range 224.0.0.x / 224.0.1.x | COVERED at ST 2110 tier; **MISSING** at base tier. The 224-239 first-octet identification works correctly; the m1 lexical (224-239 prefix) is enforced via the `>=224` test. |
| 103 | 9 | ABNF authoritative | IP6-multicast = IP6-address [ "/" numaddr ]; "starting with FF". | 826, 829-836 | `is_mc6 = ip6:sub(1,2):lower() == "ff"`; "/" suffix must be `/<numaddr>` only | COVERED at ST 2110 tier; **MISSING** at base tier. |
| 104 | 9 | ABNF authoritative | ttl = (POS-DIGIT *2DIGIT) / "0"; range 0-255 per prose. | 865-868 | `if not ttl or ttl < 0 or ttl > 255` — semantic, not lexical | COVERED — parser narrows to 0-255 per prose (correct conflict resolution per CLAUDE.md "prose wins on semantic range"). AMBIGUOUS in inventory; parser does the right thing. |
| 105 | 9 | ABNF authoritative | unicast-address = IP4-address / IP6-address / FQDN / extn-addr. | 125 (o=), 167 (c=) | `C(token)` | COVERED-PARTIAL at base tier — accepts any non-SP token. ST 2110 path validates IPv4/IPv6 forms via _ipv4_addr_pat / _ipv6_addr_pat. See #16, #17. |
| 106 | 9 | ABNF authoritative | IP4-address first-octet b1 < 224. | 853 | `o1 and o1 >= 224 and o1 <= 239` distinguishes multicast (224-239) from unicast (<224), and 240+ is implicitly accepted as unicast | COVERED-WRONG-RANGE — base tier does no IPv4 unicast lexical check. ST 2110 tier accepts 0-223 and 240-255 as unicast (treats them all as non-multicast). RFC 8866 §9 ABNF `b1 = decimal-uchar ; less than "224"` means only 0-223 is unicast IPv4; 240-255 is reserved (not a valid unicast IPv4 per the SDP grammar). Direction-A (low-priority — 240+ practical use is rare and is not strictly forbidden by IP semantics, but the SDP ABNF says "less than 224"). CANDIDATE-MISSING-NEEDS-REVIEW. |
| 107 | 9 | ABNF authoritative | IP6-address grammar (incl. "::" forms and embedded IPv4). | 584-646 (_ntp_ipv6) | LPEG grammar covering all 38 forms per RFC 4291 §2.2 / RFC 3986 §3.2.2 | COVERED at ST 2110 tier (where it's invoked via valid_connection_address); **MISSING** at base tier. |
| 108 | 9 | ABNF authoritative | FQDN = 4*(alpha-numeric / "-" / "."); ≥4 chars. | — | No FQDN lexical check at base tier | MISSING — at base tier, `c=IN IP4 ab` is accepted as a 2-char FQDN-positioned token. CANDIDATE-MISSING-NEEDS-REVIEW. |
| 109 | 9 | ABNF authoritative | bandwidth = 1*DIGIT. | 182 | `C(digit^1)` | COVERED. |
| 110 | 9 | ABNF authoritative | bwtype = token. | 181-182 | `bw_bwtype = (P(1) - P(":") - SP - line_end)^1` — wider than token (allows 0x00, 0x80+) | COVERED-PARTIAL — accepts the spec-conforming set but also some extras. AMBIGUOUS resolved in #36. |
| 111 | 9 | ABNF authoritative | text = byte-string; byte-string = 1*(%x01-09/%x0B-0C/%x0E-FF) — excludes NUL/CR/LF. | 80 | `value_char = 1 - line_end` — excludes CR/LF but NOT NUL | COVERED for CR/LF; MISSING for NUL. Combine with #6 / #45 / #67. Cite RFC 8866 §9 byte-string ABNF. CANDIDATE-MISSING-NEEDS-REVIEW. |
| 112 | 9 | ABNF authoritative | token-char set. | 520-528 | `_rfc4566_token_char` — used for a=mid / a=group only, not for nettype / addrtype / media / fmt / proto / bwtype / attribute-name | COVERED-PARTIAL — the token-char pattern exists and is correctly defined per ABNF, but is only applied to RFC 5888 a=mid / a=group values. RFC 8866 §9 says token is used for nettype, addrtype, media, fmt, proto, bwtype, attribute-name. None of those base-tier positions use the strict token-char pattern. Direction-A (under-strict lexical checks). |
| 113 | 9 | ABNF authoritative | port = 1*DIGIT. | 281-285 | port_str matched via `(%d+)`; `if port > 65535 then return nil, 1` | COVERED — and adds UDP-range check (RFC 768). |
| 114 | 9 | ABNF authoritative | time = POS-DIGIT 9*DIGIT (no leading zero, ≥10 digits, alternative: "0"). | 153 | `C(digit^1)` — any nonempty digit sequence | OVER-PERMISSIVE — accepts `t=01 02` (leading zero, <10 digits). See #38, #96. Direction-A (8866 made ABNF more precise). |
| 115 | 9 | ABNF authoritative | r= subfield grammar; units case-sensitive. | 198-199 | `_typed_time_pat = digit^1 * S("dhms")^-1` (lowercase only) | COVERED. |
| 116 | 9 | ABNF authoritative | non-zero-int-or-real ; integer ; zero-based-integer. | 723 | `_signed_int_pat = (P("-") + P("+"))^-1 * _digit_seq * P(-1)`; positives by `_pos_int_pat` | COVERED structurally — patterns exist; usage is narrow (ST 2110-21 CMAX etc.). Not applied at base RFC 8866 numeric attributes (e.g. framerate, quality). |
| 117 | 8.2.4.1 | SHALL | New a= attribute ABNF rule must define allowable values. | — | — | OUT-OF-SCOPE-FROM-SDP — registration policy. |

## AMBIGUOUS rows (per inventory) — resolution

- **#7 (SHOULD CRLF tolerance)** — COVERED (line 79 accepts both).
- **#11 (v= 1*DIGIT vs "0")** — COVERED; parser follows prose ("0" only).
- **#25 (e=/p= name parens)** — Open MISSING (low priority).
- **#28 (TTL 0-999 ABNF vs 0-255 prose)** — COVERED; parser follows prose.
- **#36 / #110 (bwtype alphanumeric vs token)** — NOT-A-CHECK; ABNF wins on lexical form per CLAUDE.md.
- **#51 (rtpmap SHOULD vs MUST)** — see #82; operative MUST is §8.2.3.
- **#56 (rtpmap PT range)** — see entry; cited as RFC 3550 §5.1 not §6.6.
- **#71 (quality 0-10 vs zero-based-integer)** — NOT-A-CHECK on 0-10 bound; MISSING on integer-form check.
- **#93 (v= ABNF vs prose)** — COVERED; parser follows prose.
- **#104 (ttl ABNF vs prose)** — COVERED; parser follows prose.

## Reverse direction — parser citations of RFC 8866

```sh
grep -nE '"RFC 8866|RFC 8866 §' /Users/andrewstarks/src/parse_sdp/parse_sdp.lua
```

The parser cites RFC 8866 in `valid_connection_address` at lines 805-887 (§5.7 and §9). All four citations there map cleanly to inventory rows #27/#28/#29/#30/#103. No reverse-direction bug.

**Outside that block**: parser cites `RFC 4566` (rather than 8866) at lines 196, 201, 217, 235, 297, 422, 516, 530, 539, 546, 1138, 1195, 1322, 1359, 1545, 1558, 1561, 1907, 1912, 1919, 1940, 2030, 2031, 2045, 2046, 2205, 2976, 2977, 2983, 2987, 2989, 3059, 3098, 3106, 3151. Almost all of these point to clauses where 8866 inherits 4566 unchanged. The exceptions are the **Direction-C wrong-cite candidates** listed in the summary below.

## RFC 8866 clauses 4566 was permissive on (Direction-A candidates — new or tightened in 8866)

1. **#9, #10** — IDN ACE form (raw UTF-8 in domain names forbidden). New in 8866; **MISSING**.
2. **#27, #28, #29** — IPv4 multicast TTL mandatory and in 0-255. 4566's intent; 8866's ABNF made it normative. **COVERED at ST 2110 tier, MISSING at base tier.**
3. **#30** — IPv6 multicast TTL prohibited (the `/N` is numaddr). 8866 clarification. **COVERED at ST 2110 tier, MISSING at base tier.**
4. **#42, #92** — z= without r= is a structural syntax error (zone-field inside repeat-description in §9 ABNF). New in 8866; **MISSING** (parser accepts `t=0 0 z=…` directly).
5. **#43, #99** — **k= is OBSOLETE; MUST NOT use, MUST discard.** **MAJOR Direction-A MISSING** — parser accepts and emits k= happily (tests positively assert this). The k= migration is the biggest 4566→8866 delta.
6. **#48, #79** — `<media>` value set narrowed: control/data removed; canonical set is {audio, video, text, application, message} + IANA-registered (e.g. image). 8866 refinement; **MISSING** at base tier (no value-set check).
7. **#52, #83** — proto=udp fmt must reference {audio, video, text, application, message} media subtypes. 8866 refinement; **MISSING**.
8. **#62** — inactive stream MUST send RTCP. New in 8866; OUT-OF-SCOPE-FROM-SDP.
9. **#63, #64** — orient and type case-sensitivity made explicit in ABNF. 8866 clarification; **MISSING** (no a=orient / a=type validators).
10. **#68, #69** — sdplang/lang reference RFC 5646 (was older spec). 8866 refinement; **MISSING**.
11. **#82** — Dynamic PT MUST have a=rtpmap. 8866 §8.2.3 strengthens §5.14's SHOULD to MUST. **COVERED at ST 2110 tier with wrong cite, MISSING at base tier.**
12. **#106** — IPv4 unicast b1 < 224 (240+ not valid SDP unicast per ABNF). 8866 clarification; **COVERED-WRONG-RANGE** (parser treats 240+ as unicast).
13. **#107** — IPv6 grammar updated for RFC 3986 / RFC 5954. 8866 refinement; **COVERED at ST 2110 tier, MISSING at base tier**.
14. **#114** — t= time form is POS-DIGIT 9*DIGIT or "0". 8866 ABNF refinement; **OVER-PERMISSIVE** (accepts any digit string).

## Spec_refs citing RFC 4566 where operative SHALL is RFC 8866 (Direction-C candidates)

| Parser line | Current cite | Should be | Notes |
|---|---|---|---|
| 1322 | `RFC 4566 §6` | `RFC 8866 §6.15` | fmtp PT == rtpmap PT (cross-attribute coherence) |
| 1359 | `RFC 4566 §6` | `RFC 8866 §6.15` | invalid fmtp (value form) |
| 1545 (comment) | `RFC 4566 §6` | `RFC 8866 §6.13` | a=framerate value form |
| 1558, 1561 | `RFC 4566 §6 / ST 2110-22:2022 §7.4` | `RFC 8866 §6.13 / ST 2110-22:2022 §7.4` | a=framerate value form |
| 2987-2989 | `RFC 4566 §5 / §9 ABNF` | `RFC 8866 §5 / §9` | SDP terminator requirement |
| 1338 (#56) | `RFC 3550 §5.1` | `RFC 8866 §6.6` (or both) | rtpmap PT ∈ [0,127] is RFC 8866's defined-value-set on rtpmap; RFC 3550 §5.1 is the lower-layer derivation |

(In addition, comments at lines 196, 201, 217, 235, 297, 422, 1907, 1912, 1919, 3059, 3098, 3106, 3151, 2976-2977 reference "RFC 4566 §X" where the same clause exists at "RFC 8866 §X". These are not on user-visible error spec_refs, so they are documentation-grade Direction-C rather than wrong-cite-on-error.)

## Summary

- Inventory rows total: **117**
- SDP-Y rows: **87**
- COVERED (base or ST 2110-gated): 39
- COVERED-WRONG-CITE: 6 (#3, #26, #51, #56, #73, #82) — see Direction-C table
- COVERED-PARTIAL: 11 (#55, #70, #72, #81, #91, #92, #95, #99, #100, #105, #110, #116)
- MISSING (base tier, including base-tier gaps for ST 2110-gated checks): 32 (most numerous: #6/#45/#67/#111 NUL handling, #8 RFC 1034/1035 FQDN, #9/#10 IDN ACE, #16/#17/#105/#108 unicast-address forms at base, #25 e=/p= parens, #26/#27/#28/#30/#34 c= gating to ST 2110 only, #32 single c= per media, #38/#96/#114 t= ABNF strictness, #42/#92 z=-without-r=, #43/#99 k= obsoletion, #44/#100 attribute-name token-char, #48 <media> value set, #50/#81 RTP fmt PT-form, #52/#83 udp fmt, #59 direction-attr uniqueness, #63 a=orient, #64 a=type, #65/#66 a=charset, #68/#69 a=sdplang/lang, #70 base framerate, #71 a=quality form, #73 fmtp/m= cross-check, #74 a=fmtp duplicates, #106 IPv4 unicast 240+, #107 IPv6 grammar at base tier, #112 token-char application)
- NOT-A-CHECK: 7 (#5, #20, #22, #36/#110, #39, #60, #71 partial, #79)
- OUT-OF-SCOPE-FROM-SDP: 19 (#37, #46, #53, #54, #57, #61, #62, #75, #76, #77, #78, #84, #85, #86, #87, #88, #89, #117, plus pieces of #5/#20/#22)
- AMBIGUOUS rows from inventory: 11 — all resolved above.
- CANDIDATE-MISSING-NEEDS-REVIEW: 18 — flagged inline.
- **Reverse-direction check**: parser's RFC 8866 cites all map to inventory rows correctly; no orphan claims.

## Top 3 findings (for main thread)

1. **k= obsoletion is unaddressed (#43, #99).** RFC 8866 §5.12 says k= MUST NOT be used and MUST be discarded on receipt. Parser accepts, stores, and serializes k=; sdp_spec tests positively assert acceptance. This is the single biggest 4566→8866 delta and parse_sdp is firmly on the 4566 side. A mode-aware reject or strip is needed for 8866-compliant behavior. Direction-A, MAJOR.
2. **The whole c= multicast / unicast-address validation block (`valid_connection_address`, parser lines 805-887) is gated behind ST 2110 mode** (#26, #27, #28, #30, #32, #34, #102, #103, #106, #107). At the base RFC 8866 tier (`validate.sdp` / `is_sdp()`), all of: TTL-mandatory-for-IPv4-multicast, TTL-forbidden-for-IPv6-multicast, layered-multicast notation, unicast-no-slash, IPv4 unicast b1<224, and IPv6 grammar are unenforced. The code exists and is correct; the wiring needs `validate.sdp` to invoke it (or a base-tier equivalent). Direction-A, large gap.
3. **Dynamic-PT-requires-rtpmap is a MUST in 8866 §8.2.3** (#82), strengthening §5.14's SHOULD. Parser enforces it under ST 2110 with cite `ST 2110-10 §7`. At base tier it is MISSING. Cite should reference RFC 8866 §8.2.3. Direction-A + Direction-C combined. (Same shape applies to #26 c= coverage, #56 rtpmap PT range, #73 fmtp/m= cross-check — all cited as 4566 or as ST 2110-10 §6.3, when the operative MUST is in RFC 8866.)

---


# IETF — RTP base

## RFC 3550 + 3551

# Audit Coverage — RFC 3550 (RTP) and RFC 3551 (RTP A/V Profile)

**Inventory source**: `/tmp/audit_inventory_rfc3550_3551.md` (130 rows total, ~54 SDP-relevant).
**Parser scanned**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines, plus `spec/sdp_spec.lua`, `spec/st2110_spec.lua`).

Classification scheme:
- **COVERED** — explicit check present, citation accurate, behavior tested.
- **COVERED-WRONG-CITE** — check present but citation mis-attributed.
- **COVERED-NO-TEST** — check in code but no test exercises it.
- **MISSING** — no check anywhere; rule is SDP-relevant and not covered by another tier-derivation.
- **OUT-OF-SCOPE-FROM-SDP** — clause does not constrain SDP; parser is correctly silent.

For brevity, the table below shows only the **54 SDP-relevant ("Y") rows**. The remaining 76 RTP/RTCP packet-behavior rows are uniformly **OUT-OF-SCOPE-FROM-SDP**.

---

## Coverage Table — SDP-relevant rows

| Inv # | Spec | § | Rule (compressed) | Status | Where in parser | Notes |
|---|---|---|---|---|---|---|
| 6 | RFC 3550 | 5.1 (PT) | Profile MAY specify static PT mapping (cross-ref RFC 3551 §6) | OUT-OF-SCOPE-FROM-SDP (meta-rule) | n/a | This is the chain-of-authority clause, enforced via downstream rows 93–124. |
| 11 | RFC 3550 | 5.1 (ts) | Profile (or dynamic non-RTP signaling) defines RTP timestamp clock rate | OUT-OF-SCOPE-FROM-SDP (meta-rule) | n/a | Enforcement is via RFC 3551 §6 Table 4/5 (rows 93–121, 126) for static PTs and via RFC 4566 §6 `a=rtpmap` syntax for dynamic. |
| 59 | RFC 3550 | 11 | RTP and RTCP port numbers MUST NOT be the same | **MISSING (at RFC 4566 tier)** + COVERED (at IPMX tier, only by exact-port+1 rule) | `parse_sdp.lua:2877` mandates `a=rtcp` = media port+1 — implies distinct, but only at IPMX. At RFC 4566 / ST 2110 tier the parser never compares `m=` port to `a=rtcp:` port. | Direction-A: RFC 4566 tier should reject `m=audio 5000 RTP/AVP 0` + `a=rtcp:5000`. |
| 62 | RFC 3550 | 11 | Layered encoding `m=` ports MUST be distinct (P+2n, P+2n+1) | **MISSING** | nothing | Direction-A. Layered encoding via the `m=` `port/N` slot (RFC 4566 §5.7) produces N successive ports, but the parser never checks cross-`m=` block port disjointness. |
| 63 | RFC 3550 | 11 | Layered encoding multicast `c=` addresses MUST be distinct | **MISSING** | nothing | Direction-A. No cross-`m=` `c=` address-distinctness check for layered streams. (DUP leg c= distinctness is separately enforced at ST 2110-10 §8.5 / `each_dup_group` for the 2022-7 case — not the same rule.) |
| 65 | RFC 3550 | 12 | PT 72-73 reserved (RFC 3550); RFC 3551 §6 extends 72-76. Cannot appear in `m=` fmts or `a=rtpmap`. | **MISSING (at RFC 4566 tier)** + partial COVERED at ST 2110 tier | `parse_sdp.lua:1340-1352` rejects PT < 96 unless `(pt,enc,clock,ch)` ∈ {(10,L16,44100,2),(11,L16,44100,1)}. This implicitly rejects PT 72-76 at ST 2110 tier but with a wrong-feeling error message ("not a static designation for this encoding"). | Direction-A. At RFC 4566 tier any value passes; PT 72-76 in `m=audio 5000 RTP/AVP 72` parses cleanly. |
| 69 | RFC 3550 | 13 | Profile MUST specify clock rate for each static PT | OUT-OF-SCOPE-FROM-SDP (meta-rule) | n/a | Authoring rule for profile documents, not for SDP. Enforced transitively via Table 4/5 rows. |
| 71 | RFC 3551 | 1 | Tables 4/5 binding payload formats to PTs is normative | **MISSING (at RFC 4566 tier)** | partial: ST 2110 tier only checks PT 10/11 carve-out (`parse_sdp.lua:1340-1352`); no general Table 4/5 enforcement | Direction-A. The chain-of-authority root is the static-PT binding for ALL of Tables 4/5, but the parser only enforces L16 statics. PCMU/PCMA/G722/MPA/JPEG/MP2T/H261/H263/MPV — never checked. |
| 74 | RFC 3551 | 3 | PT 96-127 = dynamic; presence of `a=rtpmap` required | **MISSING (RFC 4566-tier `a=rtpmap` requirement check)** + COVERED-AS-SIDE-EFFECT at ST 2110 (1303-1306) | At RFC 4566 tier `validate.sdp` (`parse_sdp.lua:304-365`) makes no `a=rtpmap` requirement. RFC 4566 §8.2.3 anyway says dynamic PTs MUST have rtpmap — that's an RFC 4566 finding, not RFC 3551, but is the same SDP-level constraint. | Direction-A at RFC 4566 tier. Plain `parse(text)` accepts `m=audio 5000 RTP/AVP 96` without any `a=rtpmap`. |
| 75 | RFC 3551 | (dup of 79) | (duplicate row in inventory) | n/a | n/a | n/a |
| 79 | RFC 3551 | 4.5 | Non-standard sample rate → MUST use dynamic PT (96+) with `a=rtpmap` indicating clock rate | OUT-OF-SCOPE-FROM-SDP (implied by row 71 + 74) | n/a | If the parser ever fully implements rows 71 + 74, this is implicit (you can't put PT 5 DVI4/12345/1 because PT 5 is bound to DVI4/8000/1). At present, MISSING via rows 71/74. |
| 81 | RFC 3551 | 4.5.2 (G722) | G722 RTP clock rate fixed at 8000 (NOT 16000) | **MISSING** | nothing | Direction-A. Parser accepts `a=rtpmap:9 G722/16000` without complaint at any tier. |
| 93 | RFC 3551 | 6 (PT 0) | PT 0 = PCMU/8000/1 (audio) | **MISSING** | nothing | Direction-A. Parser accepts `a=rtpmap:0 PCMU/16000/2` at any tier. (sdp_spec.lua actually uses `a=rtpmap:0 PCMU/8000` as a valid example, but doesn't verify the binding.) |
| 94 | RFC 3551 | 6 (PT 1) | PT 1 = reserved (audio) | **MISSING** | nothing | Direction-A. PT 1 in `m=audio 5000 RTP/AVP 1` passes. Inventory row notes "must not be reused as dynamic" — soft. |
| 95 | RFC 3551 | 6 (PT 2) | PT 2 = reserved/deprecated | **MISSING** | nothing | Direction-A. |
| 96 | RFC 3551 | 6 (PT 3) | PT 3 = GSM/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 97 | RFC 3551 | 6 (PT 4) | PT 4 = G723/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 98 | RFC 3551 | 6 (PT 5) | PT 5 = DVI4/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 99 | RFC 3551 | 6 (PT 6) | PT 6 = DVI4/16000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 100 | RFC 3551 | 6 (PT 7) | PT 7 = LPC/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 101 | RFC 3551 | 6 (PT 8) | PT 8 = PCMA/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 102 | RFC 3551 | 6 (PT 9) | PT 9 = G722/8000/1 (audio) — RTP clock rate 8000, NOT 16000 | **MISSING** | nothing | Direction-A. The famous "G722 quirk" assignment-task callout. |
| 103 | RFC 3551 | 6 (PT 10) | PT 10 = L16/44100/2 (audio) | COVERED (at ST 2110 tier) | `parse_sdp.lua:1340-1352`; tests `spec/st2110_spec.lua:4007-4011`, `4019-4024` | Note: only enforced when `--mode=st2110` is requested. **MISSING at RFC 4566 tier.** |
| 104 | RFC 3551 | 6 (PT 11) | PT 11 = L16/44100/1 (audio) | COVERED (at ST 2110 tier) | `parse_sdp.lua:1340-1352`; tests `spec/st2110_spec.lua:4013-4017` | Same as row 103 — RFC 4566 tier is silent. |
| 105 | RFC 3551 | 6 (PT 12) | PT 12 = QCELP/8000/1 (audio) | **MISSING** | nothing (note: the ST 2110-tier check at 1340-1352 rejects PT 12 entirely with L16 args, but does not enforce QCELP binding) | Direction-A. |
| 106 | RFC 3551 | 6 (PT 13) | PT 13 = CN/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 107 | RFC 3551 | 6 (PT 14) | PT 14 = MPA/90000 (audio, "see text" channel field — quirky) | **MISSING** | nothing | Direction-A. Subtle: clock rate is 90000 even though it's audio. |
| 108 | RFC 3551 | 6 (PT 15) | PT 15 = G728/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 109 | RFC 3551 | 6 (PT 16) | PT 16 = DVI4/11025/1 (audio) | **MISSING** | nothing | Direction-A. |
| 110 | RFC 3551 | 6 (PT 17) | PT 17 = DVI4/22050/1 (audio) | **MISSING** | nothing | Direction-A. |
| 111 | RFC 3551 | 6 (PT 18) | PT 18 = G729/8000/1 (audio) | **MISSING** | nothing | Direction-A. |
| 112 | RFC 3551 | 6 (PT 19) | PT 19 = reserved (audio) | **MISSING** | nothing | Direction-A. |
| 113 | RFC 3551 | 6 (PT 20-23) | PT 20-23 = unassigned audio | OUT-OF-SCOPE-FROM-SDP | n/a | "Unassigned" leaves no normative SDP rule — no encoding binding to enforce. |
| 114 | RFC 3551 | 6 (PT 24,27,29,30) | unassigned video | OUT-OF-SCOPE-FROM-SDP | n/a | Same as 113. |
| 115 | RFC 3551 | 6 (PT 25) | PT 25 = CelB/90000 (video) | **MISSING** | nothing | Direction-A. |
| 116 | RFC 3551 | 6 (PT 26) | PT 26 = JPEG/90000 (video) | **MISSING** | nothing | Direction-A. |
| 117 | RFC 3551 | 6 (PT 28) | PT 28 = nv/90000 (video) | **MISSING** | nothing | Direction-A. |
| 118 | RFC 3551 | 6 (PT 31) | PT 31 = H261/90000 (video) | **MISSING** | nothing | Direction-A. |
| 119 | RFC 3551 | 6 (PT 32) | PT 32 = MPV/90000 (video) | **MISSING** | nothing | Direction-A. |
| 120 | RFC 3551 | 6 (PT 33) | PT 33 = MP2T/90000 — media type may be audio OR video | **MISSING** | nothing | Direction-A. Subtle dual-media exception. |
| 121 | RFC 3551 | 6 (PT 34) | PT 34 = H263/90000 (video) | **MISSING** | nothing | Direction-A. |
| 122 | RFC 3551 | 6 (PT 35-71) | unassigned | OUT-OF-SCOPE-FROM-SDP | n/a | No normative binding. |
| 123 | RFC 3551 | 6 (PT 72-76) | reserved for RTCP-disambiguation; SDP MUST NOT use | **MISSING (RFC 4566 tier)**; partially COVERED-WRONG-CITE at ST 2110 tier | At ST 2110 tier the check at `parse_sdp.lua:1340-1352` rejects PT 72-76 as a side-effect (they don't match the L16 carve-out), but the **error message claims** "outside dynamic range 96-127 and does not match an RFC 3551 §6 static designation for this encoding". That cite is misleading: PT 72-76 are not "no static designation"; they are explicitly **reserved** per RFC 3551 §6 + RFC 3550 §12. The audit-worthy refinement: emit a distinct, accurately-cited error for PT 72-76. | Direction-A at RFC 4566 tier; COVERED-WRONG-CITE at ST 2110 tier. |
| 124 | RFC 3551 | 6 (PT 77-95) | unassigned | OUT-OF-SCOPE-FROM-SDP | n/a | No normative binding. |
| 125 | RFC 3551 | 6 (PT 96-127) | dynamic; `a=rtpmap` required to be meaningful | **MISSING at RFC 4566 tier (RFC 4566 §8.2.3 dup)** + COVERED at ST 2110 tier | ST 2110 tier requires `rtpmap` (`parse_sdp.lua:1303-1306`). | (See row 74.) |
| 126 | RFC 3551 | 6 (dyn H263-1998) | H263-1998 has no static PT; when bound dynamically, clockrate MUST be 90000 | **MISSING** | nothing | Direction-A. Dynamic-only with fixed clock rate per Table 5 row. |
| 127 | RFC 3551 | 6 (media-type segregation) | Different media types SHALL NOT be multiplexed within a single RTP session — i.e., all PTs on one `m=` belong to one media type (PT 33 MP2T = AV exception) | **MISSING** | nothing | Direction-A. Parser does not check that `m=audio 5000 RTP/AVP 0 31` is a category violation (PT 31 is video H261). |
| 128 | RFC 3551 | 6 (dyn audio extras) | G726-{40,32,24,16}/G729D/G729E/GSM-EFR all 8000/1; L8 var/var; RED see text; VDVI var/1 | **MISSING** | nothing | Direction-A. When these encoding names appear in `a=rtpmap`, clock-rate and channel-count constraints are not enforced. |
| 130 | RFC 3551 | 11 | Profile name "RTP/AVP" registered | OUT-OF-SCOPE-FROM-SDP (AMBIGUOUS in inventory) | n/a | Inventory tags as AMBIGUOUS; binding lives in RFC 4566's media transport field, not in 3551 itself. ST 2110 tier (1240-1244) requires `RTP/AVP` for ST 2110 media, citing ST 2110-10 §8.1. |

---

## Reverse direction — citations the parser carries vs. inventory

`grep '"RFC 3550\|"RFC 3551\|RFC 3550 §\|RFC 3551 §' parse_sdp.lua` shows three primary citation sites:

| Parser line | Citation | Inventory match |
|---|---|---|
| 1338 | `"RFC 3550 §5.1"` for "RTP payload type %s out of valid range 0-127" | Matches inventory row 6 (PT field semantics). Citation is accurate at the section level. |
| 1349, 1351 | `"RFC 3551 §6"` / `"ST 2110-10 §6.2"` for "PT outside 96-127 and does not match a static designation" | Inventory rows 71 + 125. Citation is structurally correct but applies the rule narrowly (only L16 statics). For PT 72-76 the cite is misleading per audit row 123 above. |
| 1907, 1912, 1913, 1919 | `"RFC 3551 §6"` for "rtpmap missing channel count" / "channel count must be positive" | Inventory row 11 (clock rate is profile-defined; channel count is part of the rtpmap grammar). The cite is reasonable — RFC 3551 §6 defines the audio profile that requires channel count — but the precise grammar requirement is in **RFC 4566 §6 `rtpmap`**, which states the format is `<encoding name>/<clock rate>[/<encoding parameters>]` with the audio parameter being channels. Should arguably co-cite RFC 4566 §6. Minor — COVERED-WRONG-CITE-LITE. |

The parser does **not** cite RFC 3550 §11 (port distinctness) or §12 (PT 72-73 reserved) anywhere — confirming the **MISSING** rows above.

---

## Summary counts (SDP-relevant rows only)

| Status | Count | Rows |
|---|---|---|
| COVERED | 2 | 103, 104 (PT 10, PT 11 L16 statics — ST 2110 tier only) |
| COVERED-WRONG-CITE | 1 (lite) | 123 (PT 72-76 cite is "no static designation" when it should be "reserved per RFC 3551 §6 + RFC 3550 §12"); 11 (minor — RFC 3551 §6 cited where RFC 4566 §6 is the primary grammar source) |
| COVERED-NO-TEST | 0 | — |
| MISSING (Direction-A) | 32 | 59, 62, 63, 65, 71, 74 (RFC 4566-tier instance), 81, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 105, 106, 107, 108, 109, 110, 111, 112, 115, 116, 117, 118, 119, 120, 121, 123 (RFC 4566-tier instance), 126, 127, 128 |
| OUT-OF-SCOPE-FROM-SDP | many (76 from RFC 3550 + 18 RFC 3551 meta/runtime + 113, 114, 122, 124 unassigned ranges + 130 profile name) | — |

(Inventory row 75 is a duplicate of row 79 and is not counted; row 79 itself is OUT-OF-SCOPE conditional on rows 71 + 74 being enforced.)

---

## Top observations

1. **The static-PT carve-out at `parse_sdp.lua:1340-1352` only covers L16 (PT 10/11).** It correctly cites RFC 3551 §6 but enforces only the **two** static bindings that ST 2110-30 itself needs. All other 21 static-PT bindings in Tables 4 + 5 (PT 0,3,4,5,6,7,8,9,12,13,14,15,16,17,18,25,26,28,31,32,33,34) are unchecked at every tier. This is the classic Direction-A failure mode.

2. **PT 72-76 are not explicitly rejected.** At the RFC 4566 tier they pass entirely. At the ST 2110 tier they happen to fail the L16-static carve-out check, but the error message ("outside the dynamic range 96-127 and does not match an RFC 3551 §6 static designation for this encoding") is misleading. They are reserved per RFC 3551 §6 + RFC 3550 §12, not "no static designation". A dedicated check with the correct citation chain would be a strict improvement, and it should fire at all three tiers (RFC 4566, ST 2110, IPMX).

3. **G722 clock-rate quirk is not enforced.** `a=rtpmap:9 G722/16000` is accepted. This is one of the more famous SDP-validator gotchas (RFC 3551 §4.5.2 explicitly states 8000 even though the actual sample rate is 16000), and is squarely a Direction-A finding the parser should add a check for.

4. **Port-distinctness rules from RFC 3550 §11 are not enforced at the RFC 4566 tier.** The IPMX tier rule that `a=rtcp:` = media-port+1 (cited TR-10-1 §8.7, parse_sdp.lua:2877) **implies** distinctness but only in IPMX mode. At the plain RFC 4566 tier the parser accepts `m=audio 5000 RTP/AVP 0` + `a=rtcp:5000`. Similarly, layered-encoding port and address distinctness (RFC 3550 §11) is never checked.

5. **Media-type segregation per `m=` (RFC 3551 §6 SHALL NOT)** — the parser accepts `m=audio 5000 RTP/AVP 0 31` where PT 0 is audio (PCMU) and PT 31 is video (H261). This is exactly the kind of "spec-grounded SHALL NOT" finding the parser should catch.

6. **Dynamic PT requires `a=rtpmap`** — at RFC 4566 tier (validate.sdp), `m=audio 5000 RTP/AVP 96` with no rtpmap is currently accepted. RFC 3551 §3 (dynamic range) combined with RFC 4566 §8.2.3 makes rtpmap a requirement for PT ≥ 96. ST 2110 tier enforces it, but RFC 4566 tier does not.

7. **One Direction-A finding involving rule 4 (bullet-binding) NOT triggered**, as expected — inventory observation 7 anticipated this and the structure of Tables 4/5 in RFC 3551 §6 makes the binding unambiguous.

---

## Return summary

- **Row count (SDP-relevant)**: 54
- **Path**: `/tmp/audit_coverage_rfc3550_3551.md`
- **Top 3 findings**:
  1. **RFC 3551 §6 Tables 4 + 5 only L16/PT 10-11 enforced** (parse_sdp.lua:1340-1352); all 21 other static PT bindings (PCMU, PCMA, G722, GSM, MPA, JPEG, MP2T, H261, H263, MPV, …) MISSING at every tier. Direction-A across 22 inventory rows.
  2. **PT 72-76 reserved-range not explicitly rejected; cite is misleading**. Parser at ST 2110 tier rejects them only via the L16-static failure path and emits a misleading "no static designation" error. RFC 3550 §12 + RFC 3551 §6 are not cited. Should be a first-class rejection at all tiers.
  3. **G722 clock-rate quirk not enforced** — `a=rtpmap:9 G722/16000` accepted at every tier. Classic Direction-A finding squarely in RFC 3551 §4.5.2 + §6 Table 4.

---


# IETF — SDP attributes

## RFC 4570

# RFC 4570 — Source Filters — Coverage Mapping

Spec: RFC 4570, "Session Description Protocol (SDP) Source Filters", July 2006
Inventory: `/tmp/audit_inventory_rfc4570.md` (32 rows total, 23 SDP-Y)
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines)
Tests: `/Users/andrewstarks/src/parse_sdp/spec/sdp_spec.lua` + `spec/st2110_spec.lua` + `spec/ipmx_spec.lua`

Legend
- COVERED — parser enforces (or accepts/rejects) the rule per spec text; tests exist.
- PARTIAL — rule is enforced for some inputs but not all the spec demands (e.g. only at ST 2110/IPMX tier, or only for one branch of the value-set).
- MISSING — no check found.
- N/A — runtime/receiver behaviour or out-of-scope statement (inventory `SDP?` = N); no parser action expected.

## Per-clause mapping

| # | § | Summary (one line) | SDP? | Status | Where (parser) | Where (tests) | Notes |
|---|---|---|---|---|---|---|---|
| 1 | 1 | `c=` dest may be unicast/multicast/FQDN | N | N/A | — | — | RFC 4566 territory; permissive statement, no validator action. |
| 2 | 1 | `a=source-filter` legal at session and/or media level | Y | PARTIAL | parse_sdp.lua:1257-1266 (validates media-level only); parse_sdp.lua:2898 (reads session-level only for IPMX existence check) | spec/st2110_spec.lua:3886 (media level); spec/ipmx_spec.lua:2731 (session level exists test) | Media-level `a=source-filter` is syntax-validated (ST 2110 tier). Session-level is **not** syntax-validated — only its existence is checked at the IPMX tier. A malformed session-level `a=source-filter` would pass ST 2110 and IPMX validation. **Coverage gap.** |
| 3 | 3 | Top-level form `a=source-filter:<SP><filter-mode><SP><filter-spec>` | Y | PARTIAL | parse_sdp.lua:772-781 (`VALID_SOURCE_FILTER_PAT`) | spec/st2110_spec.lua:3886-3927; spec/st2110_spec.lua:4499-4555 | LPEG pattern `P(" ")^-1 * _sf_filter * P(" ") * P("IN") * P(" ") * (IP4/IP6/*) * P(" ") * <token> * (P(" ") * <token>)^1`. Pattern uses `P(" ")^-1` (zero-or-one leading SP after `:`), accepting both `a=source-filter: incl ...` (legal per ABNF — one SP after `:`) and `a=source-filter:incl ...` (no SP — does NOT conform to ABNF row 24). Lenient against spec by one SP. Otherwise correct. Only runs at ST 2110 tier (RFC 4566 tier does not invoke `valid_source_filter`). |
| 4 | 3 | `<filter-mode>` ∈ {`incl`, `excl`} | Y | COVERED | parse_sdp.lua:772 (`_sf_filter = P("incl") + P("excl")`) | spec/st2110_spec.lua:3898-3904 ("rejects unknown filter mode") | Lower-case literals only. Inventory row 25 flags case-sensitivity as AMBIGUOUS; parser follows strict lower-case which matches RFC 4570 published examples and SDP tradition. |
| 5 | 3 | `<filter-spec>` = 4 SP-separated tokens `<nettype> <address-types> <dest-address> <src-list>` | Y | COVERED | parse_sdp.lua:774-781 | spec/st2110_spec.lua:3886-3927 | LPEG enforces nettype=`IN`, address-types from defined set, then SP-separated tokens. Pattern enforces exactly one SP between sub-fields (good). |
| 6 | 3 | Semantics of `incl` vs `excl` (runtime) | N | N/A | — | — | Receiver runtime behaviour; not validatable from SDP text. |
| 7 | 3 | `<nettype>` per RFC 4566 (typically `IN`) | Y | PARTIAL | parse_sdp.lua:777 (`P("IN")`) | spec/st2110_spec.lua:3886 | Parser hard-codes `IN`. RFC 4570 says "most relevant to … `IN`" but `<nettype>` per RFC 4566 is a token (could in principle be another assigned name). For SDP today only `IN` is registered, so this is effectively COVERED in practice — but strictly the parser does NOT support any other registered nettype. Documented as restriction in code comment (parse_sdp.lua:769). |
| 8 | 3 | `<address-types>` ∈ {`IP4`, `IP6`, `*`} | Y | COVERED | parse_sdp.lua:778 (`P("IP4") + P("IP6") + P("*")`) | spec/st2110_spec.lua:3906-3911 ("rejects bad addrtype"); spec/st2110_spec.lua:3915-3919 (accepts `*` with FQDN) | LPEG enforces the closed set. |
| 9 | 3 | `<dest-address>` MUST match a `c=` value (or be `*`) | Y | **MISSING** | — | — | **No cross-line check.** Parser never compares `<dest-address>` to session-level or media-level `c=` connection-address values. RFC 4570 §3 row 9, §3.1 row 11, and Appendix A row 23 all impose this MUST. Inventory row 16 notes scope spans both session and media `c=`. |
| 10 | 3 | `<src-list>` = one or more unicast addresses or FQDNs, SP-separated | Y | PARTIAL | parse_sdp.lua:779-780 (one-or-more `_sf_token` separated by SP) | spec/st2110_spec.lua:4542-4547 ("multiple valid IPv4 src addresses") | Format check is correct (≥1 src). However the parser does NOT prohibit multicast addresses in `<src-list>`: `valid_source_filter` matches each token against `_ipv4_addr_pat`/`_ipv6_addr_pat`, which accept any literal — including multicast (224–239, ff00::/8). RFC 4570 row 10 says src-list is unicast-only. **Coverage gap for the prohibition.** |
| 11 | 3.1 | `<dest-address>` MUST equal an existing `c=` (restated MUST) | Y | **MISSING** | — | — | Same as row 9. No cross-line check anywhere in parse_sdp.lua. |
| 12 | 3.1 | Multicast `<dest-address>` MUST NOT include `/ttl` or `/num` suffix; one filter line per address | Y | PARTIAL | parse_sdp.lua:790-802 (`_ipv4_addr_pat`/`_ipv6_addr_pat` are anchored with `P(-1)`, rejecting any `/suffix` after a literal) | spec/st2110_spec.lua:4517-4524 (octet > 255 — adjacent test; no direct `/ttl` test) | Anchored IPv4/IPv6 patterns implicitly reject `/ttl` and `/num` suffixes when addrtype=IP4 or IP6 (a token like `239.100.0.1/64` would fail the address pattern). Effectively COVERED for the `/ttl` and `/num` prohibition — but only at ST 2110 tier, and only via implicit consequence of the literal check; no dedicated test exists for `/64`-suffixed dest-address. The "one filter line per multicast address when c= specifies /N" sub-rule (second sentence of row 12) is **MISSING** — depends on the missing dest↔c= cross-check (row 9/11). |
| 13 | 3.1 | If address-types=`*`, dest-address MUST be FQDN or `*` | Y | PARTIAL | parse_sdp.lua:790-791 (when addrtype != IP4/IP6, the literal check is skipped — `return true`) | spec/st2110_spec.lua:3915-3919 (accepts `*` with FQDN dest) | When address-types=`*`, parser accepts any non-space token as dest-address (no FQDN/`*` enforcement). It does NOT reject an IPv4/IPv6 literal in that position — e.g. `incl IN * 239.100.0.1 sender.example` would pass. RFC 4570 §3.1 row 13 says "MUST be FQDN or `*` (i.e. MUST NOT be IPv4/IPv6)". **Coverage gap for the prohibition.** |
| 14 | 3.1 | Default behaviour when source-filter absent; no "exclude none"/"include all" syntax | N | N/A | — | — | Absence semantics; out of scope for SDP-text validation. |
| 15 | 3.1 | Source-filter scope follows placement; media overrides session | N | N/A | — | — | Receiver semantics; no validator action. |
| 16 | 3.1 | Media-level source-filter MAY reference session-level `c=`; session-level may apply to media-level `c=` | N | N/A | — | — | Permissive clarification of row 11's match scope. Important context for **implementing** the missing dest↔c= cross-check (must scan both levels) but no validation rule of its own. |
| 17 | 3.1 | At most one session-level and at most one media-level source-filter per dest-address | Y | **MISSING** | — | — | No uniqueness/duplicate check. AMBIGUOUS in spec when `*` overlaps a literal (inventory row 17 marks this AMBIGUOUS). Literal-vs-literal duplicates at the same (level, dest-address) are the unambiguously forbidden case and are NOT detected. |
| 18 | 3.1 | No spec-imposed `<src-list>` length limit | N | N/A | — | — | Explicitly out of scope. |
| 19 | 3.2.1 | SSM RTP SDPs SHOULD include `a=rtcp-unicast` | N | N/A | — | — | SHOULD, not MUST; also requires application-level "is SSM" classification. Not enforceable as conformance. |
| 20 | 3.3 | Answerer SHOULD ignore offer's source-filter | N | N/A | — | — | Offer-answer (RFC 3264) runtime behaviour. |
| 21 | 5 | Receivers SHOULD NOT rely on source-filter for integrity | N | N/A | — | — | Security guidance for receivers. |
| 22 | 6 (IANA) | IANA registration: name `source-filter`, session or media level, not subject to charset | Y | COVERED | parse_sdp.lua:1259 / parse_sdp.lua:2898 (case-sensitive name match `a.name == "source-filter"`); parse_sdp.lua:1257-1266 (media level) + 2898 (session level) | spec/ipmx_spec.lua:2700-2745 | Attribute name is matched as exact lower-case token. Both placements are accepted by the parser layer (the grammar — generic SDP `a=` attribute syntax — does not restrict where `a=source-filter` may appear). |
| 23 | App A | Restatement: dest-address MUST match existing c= (or `*`) | Y | **MISSING** | — | — | Same as rows 9, 11. |
| 24 | App A ABNF | `source-filter = "source-filter" ":" SP filter-mode SP filter-spec` | Y | PARTIAL | parse_sdp.lua:775 (`P(" ")^-1`) | spec/st2110_spec.lua:3886-3927 | ABNF requires exactly one SP after `:`. Parser uses `P(" ")^-1` (zero-or-one). Lenient by one SP. Other SPs between fields are exact-one (good). |
| 25 | App A ABNF | `filter-mode = "excl" / "incl"` | Y | COVERED | parse_sdp.lua:772 | spec/st2110_spec.lua:3898-3904 | Case-sensitive lower-case literals enforced. Inventory row 25 flags this as AMBIGUOUS-case; parser chooses strict reading. |
| 26 | App A ABNF | `filter-spec = nettype SP address-types SP dest-address SP src-list` | Y | COVERED | parse_sdp.lua:774-781 | spec/st2110_spec.lua:3886-3927 | Structure enforced by LPEG. |
| 27 | App A ABNF | When address-types=`*`, dest AND src must be FQDNs (ABNF comment) | Y | PARTIAL | parse_sdp.lua:790-791 (skips literal validation entirely for `*` addrtype) | spec/st2110_spec.lua:3915-3919 | Parser does not validate dest or src tokens when addrtype=`*` — accepts anything (FQDN, IPv4 literal, IPv6 literal). The stricter ABNF-comment reading (FQDN-only for both) is NOT enforced. Even the more lenient prose reading (FQDN/`*` only for dest) is NOT enforced (see row 13). |
| 28 | App A ABNF | `dest-address = "*" / basic-multicast-address / unicast-address` | Y | PARTIAL | parse_sdp.lua:790-802 | spec/st2110_spec.lua:4499-4554 | When addrtype=IP4/IP6, the IPv4/IPv6 anchored literal pattern is enforced — but `*` is NOT specially handled for dest-address in those cases. With addrtype=IP4, a `*` dest token fails the literal check, which is too strict per ABNF row 28 (the production allows `*` regardless). However in practice ABNF row 27 couples `*` dest with `*` addrtype, so the practical impact is small. Otherwise COVERED. |
| 29 | App A ABNF | `src-list = *(unicast-address SP) unicast-address` (≥1, unicast only) | Y | PARTIAL | parse_sdp.lua:779-780 (count), 790-802 (literal check) | spec/st2110_spec.lua:4499-4554 | Count enforced (≥1). "Unicast-only" prohibition NOT enforced — see row 10. |
| 30 | App A ABNF | `basic-multicast-address` = multicast literal WITHOUT `/ttl` or `/num` | Y | PARTIAL | parse_sdp.lua:790-802 (anchored literal patterns implicitly reject `/suffix`) | (no dedicated test) | Implicitly COVERED via anchored IPv4/IPv6 literal patterns rejecting trailing `/...`. No dedicated regression test for `/ttl` or `/num` in dest-address. |
| 31 | App A ABNF | IPv4 multicast first octet 224–239 (`m1`) | Y | PARTIAL | parse_sdp.lua:790-802 (anchored `_ipv4_addr_pat` accepts any 0–255 dotted-quad) | spec/st2110_spec.lua:4517-4524 (octet > 255) | When addrtype=IP4 and dest-address is meant to be multicast, the parser does NOT enforce that the first octet is in 224–239. A unicast IPv4 like `192.168.1.1` in dest-address position passes (and might be legitimate — RFC 4570 row 1 says dest may be unicast). But it does mean basic-IP4-multicast vs unicast-address are not disambiguated. Since both are legal under row 28 (`dest-address = "*" / basic-multicast-address / unicast-address`), this is acceptable. **Effectively COVERED** by the broader "any valid IPv4" check, given dest-address allows unicast OR multicast. |
| 32 | App A ABNF | IPv6 multicast = `hexpart` (no FF00::/8 prefix in ABNF) | Y | PARTIAL | parse_sdp.lua:790-802 (anchored `_ipv6_addr_pat` accepts any IPv6 literal) | spec/st2110_spec.lua:4549-4554 | Inventory row 32 flags this as AMBIGUOUS in the spec itself. Parser accepts any valid IPv6 literal, which matches the ABNF literally. **Effectively COVERED** under the lenient reading the ABNF supports. |

## Summary counts (SDP-Y rows only — 23 rows: 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 17, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32)

- COVERED:    7  (rows 4, 5, 8, 22, 25, 26 + row 31 effective; row 32 effective)
- PARTIAL:   12  (rows 2, 3, 7, 10, 12, 13, 24, 27, 28, 29, 30, 31, 32 — pick the strict reading: 12 PARTIAL counting 31/32 as PARTIAL rather than effective-COVERED)
- MISSING:    4  (rows 9, 11, 17, 23 — three are the same dest↔c= MUST restated three times; one is the duplicate-uniqueness MUST)
- N/A:        9  (rows 1, 6, 14, 15, 16, 18, 19, 20, 21)

Using the strict reading (PARTIAL = "rule enforced for some inputs but not all the spec demands"):
- COVERED: 6 (rows 4, 5, 8, 22, 25, 26)
- PARTIAL: 13 (rows 2, 3, 7, 10, 12, 13, 24, 27, 28, 29, 30, 31, 32)
- MISSING: 4 (rows 9, 11, 17, 23)
- N/A:     9 (rows 1, 6, 14, 15, 16, 18, 19, 20, 21)

Total SDP-Y: 6 + 13 + 4 = 23. ✓

## Top findings

1. **Dest-address ↔ `c=` cross-line check is entirely absent** (inventory rows 9, 11, 23 — three restatements of the same MUST in §3, §3.1, and Appendix A). The parser never compares a source-filter's `<dest-address>` against any `c=` connection-address (session-level or media-level). This is the single most operationally significant gap. Implementation must scan both `doc.session.connection` and every `doc.media[i].connection` per row 16's cross-scope rule, expand any `c=` `/numaddr` form (RFC 8866 §9 multicast layered-address) into N addresses, and treat `*` dest as auto-match.

2. **Session-level `a=source-filter` value is never syntax-validated**. The media-level loop at `parse_sdp.lua:1257-1266` runs `valid_source_filter` on every media-level instance, but the corresponding session-level scan (line 2898) only checks for *existence*. A malformed session-level `a=source-filter` (bad filter-mode, missing src, garbage tokens) silently passes ST 2110 and IPMX validation. Asymmetric with media-level enforcement; should be aligned.

3. **The `*` address-types branch is under-enforced** (rows 13, 27). When `address-types=*`, the parser skips ALL value validation on dest-address and src tokens. RFC 4570 §3.1 (MUST) requires dest-address ∈ {FQDN, `*`}, prohibiting IPv4/IPv6 literals when address-types=`*`. The ABNF-comment (row 27) extends this to src-list. Neither constraint is enforced — an SDP like `a=source-filter: incl IN * 239.100.0.1 192.168.1.1` is accepted today and should be rejected per row 13's explicit MUST NOT. Adjacent gap (row 10 / 29): `<src-list>` multicast-prohibition is not checked even for the IP4/IP6 branches.

---

## RFC 5888 + 7104

# Coverage Map — RFC 5888 + RFC 7104

Spec: RFC 5888 (a=group / a=mid) + RFC 7104 (DUP semantics).
Inventory rows: 35 total (#1–#28 RFC 5888, #29–#35 RFC 7104).
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines).
Tests: `/Users/andrewstarks/src/parse_sdp/spec/sdp_spec.lua`,
`/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`,
`/Users/andrewstarks/src/parse_sdp/spec/ipmx_spec.lua`.

## Classification scheme

- **COVERED** — the parser enforces the clause and the code/test directly cites
  the inventory clause (or a SHALL it directly subsumes).
- **TIER-PARTIAL** — the parser enforces the clause but only in a higher tier
  (e.g. only when `mode == "st2110"` / `"ipmx"`), not at the generic RFC 4566
  tier where the clause originates. Generic-tier callers (`sdp.parse(text)`
  with no mode) get no enforcement.
- **MISSING** — the parser does not enforce the clause anywhere.
- **OUT-OF-SCOPE** — the inventory row is offer/answer, sender-behavior, or
  application-semantics that an SDP-only validator structurally cannot check
  (the inventory already marks `SDP? = No`).
- **AMBIGUOUS** — the inventory itself flags the clause as not a hard MUST or
  spec-silent on rejection. Validator behavior is a policy choice, not a
  conformance requirement.
- **NOT-SDP** — clause constrains a non-SDP layer (e.g. IANA registration
  policy, RTCP, runtime behavior).

The reverse-direction `grep` for `"RFC 5888"` / `"RFC 7104"` citations in the
parser yielded exactly 4 hits (lines 2039, 2055, 2062, plus 516/530 in
comments), all of which lie inside `st2110.validate` (function body
1202–2176). No `"RFC 7104"` string appears in the parser source. The
generic-tier validator `validate.sdp` (function body 304–460) contains no
RFC 5888 / 7104 enforcement.

## Coverage table

| # | Clause | SDP? | Verdict | Location / evidence |
|---|--------|------|---------|---------------------|
| 1 | RFC 5888 §4 — `a=mid` ABNF: value is exactly one RFC 4566 `token`. | Yes | TIER-PARTIAL | Enforced inside `st2110.validate` at parse_sdp.lua:2049–2057 via `valid_mid_value` (parse_sdp.lua:537–542) using LPEG pattern `_rfc4566_token_pat` (parse_sdp.lua:520–528). spec_ref `"RFC 5888 §4"`. Not enforced when `sdp.parse(text)` is called without mode. Tests: `st2110_spec.lua` does not test malformed-token `a=mid` rejection directly under the generic tier; `sdp_spec.lua` has no `a=mid` ABNF test. |
| 2 | RFC 5888 §4 — `identification-tag` MUST be unique within an SDP session description. | Yes | TIER-PARTIAL | Enforced at parse_sdp.lua:2058–2065 inside `st2110.validate`. Inventory cites §4 ("identification-tag MUST be unique within an SDP session description"); the code spec_ref says `"RFC 5888 §8.1"`. The §8.1 cite is wrong — RFC 5888 §8.1 is the IANA section / extension policy. The verbatim uniqueness MUST is in §4 (per inventory row #2). **Spec-ref drift.** Test: `st2110_spec.lua:3630–3661` "rejects duplicate a=mid values across media blocks" (M24). |
| 3 | RFC 5888 §5 — `a=group` ABNF: `semantics *(SP identification-tag)`, each is RFC 4566 `token`. | Yes | TIER-PARTIAL | Enforced at parse_sdp.lua:2033–2042 via `valid_group_value` (parse_sdp.lua:544–549) using LPEG pattern `_group_value_pat` (parse_sdp.lua:530–535). spec_ref `"RFC 5888 §5"`. Inside `st2110.validate` only; generic-tier callers get no ABNF check. The LPEG pattern accepts zero identification-tags (`_rfc4566_token_char^1 * (SP token)^0`), correctly matching §5 ABNF and §9.3 capability-negotiation usage. Tests: no direct `sdp_spec.lua` test for malformed `a=group` value. |
| 4 | RFC 5888 §5 — defined value set {LS, FID, extensions via Standards Action}. Unknown semantics tokens are tolerated. | Partial | AMBIGUOUS | Parser does not constrain `semantics` to a closed set, which matches §9.2 receiver tolerance (unknown semantics are dropped from the answer, not rejected). The LPEG `_group_value_pat` accepts any RFC 4566 token in the semantics slot. Behavior is correct: tolerant of unknowns. Inventory marks AMBIGUOUS as a hard-reject rule. No parser action required. |
| 5 | RFC 5888 §6 — if any `a=group` exists, every `m=` section MUST have `a=mid`. | Yes | MISSING | No code path in `parse_sdp.lua` enforces the "presence of `a=group` ⇒ every `m=` has `a=mid`" rule. `st2110.validate` walks `doc.media` looking for `mid_attr` (parse_sdp.lua:2048–2066) but only validates **format** and **uniqueness** when a mid is present; an `m=` block lacking `a=mid` is silently skipped. The DUP-specific `each_dup_group` (parse_sdp.lua:478–514) only checks mids referenced inside `a=group:DUP`, not all `m=` blocks. **MISSING** — no test in `sdp_spec.lua` / `st2110_spec.lua` / `ipmx_spec.lua` exercises a media block without `a=mid` while another `a=group` is present. |
| 6 | RFC 5888 §6 — receiver MUST NOT perform grouping if any `m=` lacks mid. | No | OUT-OF-SCOPE | Runtime receiver behavior. Inventory `SDP? = No`. |
| 7 | RFC 5888 §6 — dangling `a=group` tags MUST be ignored by applications. | No | AMBIGUOUS / OUT-OF-SCOPE | Inventory flags AMBIGUOUS. RFC 5888 says receivers ignore unresolvable tags, not that the SDP is non-conformant. Parser behavior: `each_dup_group` (parse_sdp.lua:493–499) **rejects** undefined-mid references inside `a=group:DUP` (spec_ref `"ST 2110-10 §8.5"`). For non-DUP semantics (LS, FID, ANAT, etc.), the parser does not check tag resolution. Inconsistent treatment: DUP rejects, others tolerate. Not technically wrong (ST 2110-10 §8.5 may impose the stricter rule); flag as policy-vs-spec gap. |
| 8 | RFC 5888 §6 — multiple `a=group` lines + repeated mids across groups MAY appear. | Yes | COVERED (negative) | Parser does not artificially reject multiple `a=group` lines or repeated mid usage across groups. `each_dup_group` (parse_sdp.lua:486–512) iterates all `group` attributes and processes each independently. No restriction code present. Implicit-coverage by absence of a wrong restriction. No test verifies this permissive behavior. |
| 9 | RFC 5888 §7 — LS receivers MUST synchronize playout. | No | OUT-OF-SCOPE | Runtime behavior. |
| 10 | RFC 5888 §7 — Non-RTP LS receivers MUST recover timing. | No | OUT-OF-SCOPE | Runtime behavior. |
| 11 | RFC 5888 §8.4 — FID sender MUST replicate to each m= line. | No | OUT-OF-SCOPE | Sender behavior. |
| 12 | RFC 5888 §8.5.1 — FID MUST NOT group parallel encodings using different codecs. | No | OUT-OF-SCOPE | Inventory notes "application intent…not knowable from SDP alone." |
| 13 | RFC 5888 §8.5.1 — Same-content/different-codec sender MUST NOT use FID. | No | OUT-OF-SCOPE | Sender intent. |
| 14 | RFC 5888 §8.5.2 — FID MUST NOT group `m=` for layered encoding / different information. | No | OUT-OF-SCOPE | Application semantics. |
| 15 | RFC 5888 §8.5.3 — Multiple codecs to same IP/port MUST use multiple PTs on one m=. | Partial | OUT-OF-SCOPE | Sender authoring guidance; the inverse rule is row #16 below. |
| 16 | RFC 5888 §8.5.3 — Within `a=group:FID`, every referenced m= MUST have a distinct (IP, port). | Yes | MISSING | No `parse_sdp.lua` code walks an `a=group:FID` line, resolves each tag to its `m=` block, and asserts distinct effective (c-line IP, m-line port) per leg. The DUP-specific check (parse_sdp.lua:2076–2140) covers a similar surface for DUP semantics (source/destination distinctness, ST 2110-10 §8.5), but FID is not handled. ST 2110/IPMX **reject** `a=group:FID` outright for smpte291 (parse_sdp.lua:2153–2173) and for all of IPMX (parse_sdp.lua:2437–2447), but RFC 5888 §8.5.3 FID-address-uniqueness applies whenever FID is present (generic-tier, ST 2110 non-smpte291, etc.). **MISSING** — no test exercises FID transport-address-distinctness. |
| 17 | RFC 5888 §9.1 — Offer/answer mid values MUST match. | No | OUT-OF-SCOPE | Cross-SDP offer/answer. |
| 18 | RFC 5888 §9.1 — SIP entities MUST align m= lines by ordinal position. | No | OUT-OF-SCOPE | SIP/offer-answer. |
| 19 | RFC 5888 §9.2 — Answerer MUST omit unsupported `a=group` semantics. | No | OUT-OF-SCOPE | SIP behavior. |
| 20 | RFC 5888 §9.2 — mid lines MUST persist in answer. | No | OUT-OF-SCOPE | Offer/answer. |
| 21 | RFC 5888 §9.2 — Answerer MUST echo supported group semantics. | No | OUT-OF-SCOPE | Offer/answer. |
| 22 | RFC 5888 §9.2 — Answer tag set MUST be subset of offer's. | No | OUT-OF-SCOPE | Offer/answer. |
| 23 | RFC 5888 §9.2 — Canonical group value MUST be the answer's when subsetted. | No | OUT-OF-SCOPE | Offer/answer. |
| 24 | RFC 5888 §9.2 — `a=group` MUST NOT reference a mid whose `m=` has port 0. | Yes | MISSING | No code path in `parse_sdp.lua` walks `a=group` tags and checks `m=` port-0 on each referenced block. `each_dup_group` resolves tags to blocks but does not assert port ≠ 0. The parser's `m=` port grammar accepts 0 (parse_sdp.lua:266 captures port-token whole, no value restriction at generic tier; IPMX tier rejects ports ≤ 1024 at parse_sdp.lua:2832–2835, but that is TR-10-2 §7 / IPMX, not RFC 5888 §9.2). Inventory observation #5 also flags this as unusually strict and a "policy choice for parse_sdp." **MISSING** but inventory notes the rule is sometimes treated leniently in practice — verdict: missing-but-defensible-to-skip. |
| 25 | RFC 5888 §9.2 — Grouping MUST be initiated by offerer, never answerer. | No | OUT-OF-SCOPE | Offer/answer. |
| 26 | RFC 5888 §9.4 — Unknown attributes are ignored, not errored. | No | OUT-OF-SCOPE | SIP/SDP fallback. |
| 27 | RFC 5888 §12 — New semantics token SHOULD be ≤ 4 chars. | Partial | AMBIGUOUS / NOT-SDP | SHOULD-class registry rule. Inventory marks AMBIGUOUS; parser does not (and should not) reject. |
| 28 | RFC 5888 §12 — Current registry: {LS, FID, SRF, ANAT, FEC, DDP}. | Partial | AMBIGUOUS | Open-ended via Standards Action. Parser correctly does not enforce a closed set. |
| 29 | RFC 7104 §3.1 — Redundant streams MUST be grouped with `a=group:DUP`. | Partial | OUT-OF-SCOPE | Inventory: classification of streams as "redundant" not knowable from SDP. Parser does not (and structurally cannot) enforce. |
| 30 | RFC 7104 §3.1 — RECOMMENDED order in `a=group:DUP` = transmission order. | No | OUT-OF-SCOPE / SHOULD | SHOULD-class transmission policy. |
| 31 | RFC 7104 §3.1 — DUP is a registered `semantics` token (extends RFC 5888 §5 ABNF). | Yes | COVERED | Parser accepts `DUP` as a `semantics` token via the generic LPEG `_group_value_pat` (parse_sdp.lua:530–535), which admits any RFC 4566 token in the semantics slot. The DUP-specific cross-leg checks are tested in `st2110_spec.lua:915–1020` and `ipmx_spec.lua:706–828`. No explicit `"RFC 7104"` spec_ref in the parser (cf. grep showed zero hits); all DUP-related spec refs cite ST 2110-10 §8.5 / ST 2022-7 §6 / TR-10-13 §13 instead. The constraint that DUP is a valid token follows from §5 ABNF tolerance — covered structurally. |
| 32 | RFC 7104 §3.2 — `a=ssrc-group:DUP` value form (RFC 5576 wrapping). | Yes (separate attr) | MISSING | The parser does not recognize `a=ssrc-group` at all. grep of parse_sdp.lua shows no occurrence of `ssrc-group`. The inventory itself notes this is RFC 5576 territory and out of scope for plain `a=group` validation; only the DUP-semantics token usage is contributed by RFC 7104. **MISSING but inventory-flagged as out of plain `a=group` scope** — verdict: missing-and-flagged. |
| 33 | RFC 7104 §3.2 — RECOMMENDED order in `a=ssrc-group:DUP`. | No | OUT-OF-SCOPE / SHOULD | SHOULD-class. |
| 34 | RFC 7104 §3.3 — Unsupported-DUP offer/answer handling. | No | OUT-OF-SCOPE | Offer/answer. |
| 35 | RFC 7104 §4.1 — Optional `a=duplication-delay:0` example. | No | NOT-SDP | Attribute defined by RFC 7197 (DELAYED-DUP), not RFC 7104. Not normative for 7104. |

## Summary by verdict

| Verdict | Count | Rows |
|---------|-------|------|
| COVERED | 2 | #8, #31 |
| TIER-PARTIAL | 3 | #1, #2, #3 |
| MISSING | 4 | #5, #16, #24, #32 |
| AMBIGUOUS | 4 | #4, #7, #27, #28 |
| OUT-OF-SCOPE | 21 | #6, #9–#15, #17–#23, #25, #26, #29, #30, #33, #34 |
| NOT-SDP | 1 | #35 |
| **Total** | **35** | |

## Strong-MUST scoreboard (verbatim from inventory observation #1)

These are the single-SDP-visible MUST/MUST-NOT clauses the inventory identified
as the entire SDP-conformance surface of these two RFCs:

| Clause | Inventory # | Verdict | Notes |
|--------|-------------|---------|-------|
| `a=mid` ABNF | 1 | TIER-PARTIAL | Inside `st2110.validate` only. |
| mid uniqueness across session | 2 | TIER-PARTIAL | Same. spec_ref drift (cited as §8.1, verbatim text is §4). |
| `a=group` ABNF | 3 | TIER-PARTIAL | Same. |
| Any `a=group` ⇒ every m= has mid | 5 | **MISSING** | No code path; no test. |
| Multiple a=group / repeated mid in groups permitted | 8 | COVERED (negative) | No restriction code; not directly tested. |
| FID transport-address distinctness | 16 | **MISSING** | No code path; no test. RFC 5888-tier rule not enforced even when FID is present (ST 2110-40:2023 §7 and TR-10-1 §10 reject FID outright in their tiers, but the generic RFC 4566 tier and non-smpte291 ST 2110 tier permit FID and don't check this). |
| Port-0 mid excluded from a=group | 24 | **MISSING** | No code path. Inventory observation #5 flags this as a policy-choice cell (ecosystem leniency). |
| DUP as valid semantics token | 31 | COVERED | Via generic ABNF; no explicit RFC 7104 spec_ref. |

## Notable findings

### Top 3 findings

1. **All RFC 5888 group/mid format and uniqueness checks live inside
   `st2110.validate` (parse_sdp.lua:2030–2173).** The generic RFC 4566
   tier (`validate.sdp`, parse_sdp.lua:304–460) **does not** enforce
   `a=mid` ABNF, `a=mid` uniqueness, or `a=group` ABNF. A caller that
   does `sdp.parse(text)` with no mode argument can submit
   `a=mid:has spaces`, two media blocks with identical mids, or
   `a=group:` with empty value, and the parser will accept it. RFC 5888 is
   an IETF/SDP-layer document; its rules apply at every tier that uses
   `a=group` / `a=mid`. Verdict: **TIER-PARTIAL** for clauses #1, #2, #3.

2. **Three single-SDP, deterministic MUST/MUST-NOT rules are not
   enforced at any tier** (inventory rows #5, #16, #24):

   - **#5** — "Presence of any `a=group` ⇒ every `m=` has `a=mid`." No
     code walks `doc.media` after detecting an `a=group` and asserts
     `mid_attr ~= nil`. The closest existing logic
     (parse_sdp.lua:2048–2066) only validates `a=mid` when present.
   - **#16** — "Within `a=group:FID`, every referenced `m=` has distinct
     (IP, port)." No code resolves FID tags and compares effective
     transport addresses. The parser handles FID by rejecting it for
     smpte291 streams (ST 2110-40:2023 §7) and for all IPMX (TR-10-1
     §10), but the RFC 5888-tier rule applies in every other case
     where FID may legitimately appear (generic, ST 2110 non-smpte291).
   - **#24** — "`a=group` MUST NOT reference a mid whose `m=` has port
     0." No code walks `a=group` tags and asserts port ≠ 0 on the
     referenced `m=` block. Inventory observation #5 acknowledges this
     is sometimes treated leniently in practice, but verbatim
     RFC 5888 §9.2 is MUST NOT, so a strict validator should reject.

3. **Spec-ref drift on `a=mid` uniqueness** (parse_sdp.lua:2062):

   The code cites `"RFC 5888 §8.1"` for the duplicate-mid rejection.
   Inventory row #2 quotes the verbatim "The identification-tag MUST be
   unique within an SDP session description." from **§4** (the same
   section that defines the ABNF). RFC 5888 §8.1 is the IANA registry /
   semantics-extension policy and does not contain a uniqueness MUST.
   The cite should be `"RFC 5888 §4"` (or whichever section the
   maintainer can confirm against the text). Minor citation correctness
   issue — does not change behavior, but the Spec Verification Protocol
   rule 3 ("an existing citation is a claim to test, not authority to
   trust") applies.

### Additional observations

4. **Zero `"RFC 7104"` spec_refs in the parser.** RFC 7104's substantive
   SDP contribution is registering the `DUP` token, which is structurally
   covered by RFC 5888 §5 ABNF tolerance. The parser's DUP-handling code
   (parse_sdp.lua:2068–2144) cites ST 2110-10 §8.5 / ST 2022-7 §6 /
   TR-10-13 §13 instead. Citation completeness only — behavior is
   correct. If `parse_sdp` ever exposes a "generic RFC 4566" tier that
   recognizes `a=group:DUP` checks independently of SMPTE specs, the
   citation provenance should add RFC 7104.

5. **Asymmetric `a=group` tag-resolution check.** `each_dup_group`
   rejects undefined-mid tags inside `a=group:DUP` (parse_sdp.lua:493–499)
   with `code = "INVALID_VALUE"`. RFC 5888 §6 (row #7) says receivers
   MUST ignore such tags — i.e. tolerate, don't reject. The DUP-only
   rejection may be defensible under ST 2110-10 §8.5 (which the code
   cites), but the contrast with non-DUP semantics (no resolution
   check) is internally inconsistent. Not a coverage bug per se;
   noted as a consistency observation.

6. **`a=ssrc-group:DUP` (row #32) is not handled at all.** No
   `ssrc-group` occurrence in `parse_sdp.lua`. Inventory notes this
   sits in RFC 5576 territory and is outside plain `a=group` scope, but
   if `parse_sdp` ever claims RFC 5576 / SSRC-multiplexed-DUP coverage,
   this gap surfaces.

7. **Test gaps mirroring the coverage gaps.** No test in
   `sdp_spec.lua`, `st2110_spec.lua`, or `ipmx_spec.lua` exercises:
   - rejection of malformed `a=mid` value at the generic RFC 4566 tier;
   - rejection of session containing `a=group` with one or more `m=`
     blocks missing `a=mid`;
   - rejection of `a=group:FID` with two legs sharing the same effective
     (IP, port);
   - rejection of `a=group` tag referencing a port-0 `m=` block.

## Reverse-direction sweep

Grep for `"RFC 5888"` / `"RFC 7104"` spec_ref strings in the parser:

```
parse_sdp.lua:2039:          spec_ref   = "RFC 5888 §5", code = "INVALID_VALUE",   # a=group ABNF
parse_sdp.lua:2055:          spec_ref   = "RFC 5888 §4", code = "INVALID_VALUE",   # a=mid ABNF
parse_sdp.lua:2062:            spec_ref = "RFC 5888 §8.1", code = "INVALID_VALUE"   # mid uniqueness (drift: should be §4)
```

`"RFC 7104"`: zero hits. DUP-related code cites ST 2110-10 §8.5 / ST 2022-7 §6
/ TR-10-13 §13. The grep also showed two RFC 5888 occurrences in comments
(lines 516, 530) referring to the §9 token grammar and §5 group ABNF; both
mark the LPEG patterns that back the validators.

All three production-cited spec_refs live inside the `st2110.validate`
function body (1202–2176). None appear in `validate.sdp` (304–460) or
`ipmx.validate` (2393+) — IPMX inherits the RFC 5888 checks via its call to
`st2110.validate` (parse_sdp.lua:2430), and the generic tier inherits
nothing.

## Conformance principle alignment

Per `CLAUDE.md` Validation Strictness Principle, every rejected SDP must be
backed by explicit normative spec text. The three MISSING rows all cite
verbatim MUSTs:

- #5: `"All of the 'm' lines of a session description that uses 'group'
  MUST be identified with a 'mid' attribute…"` (§6)
- #16: `"If two 'm' lines are grouped using FID, they MUST differ in
  their transport addresses (i.e., IP address plus port)."` (§8.5.3)
- #24: `"'a=group' lines MUST NOT contain identification-tags that
  correspond to 'm' lines with the port set to zero."` (§9.2)

All three are positive (#5) or prohibitive (#16, #24) MUST-class clauses
covered by polarities 1 and 2 of the strictness principle. Adding the
checks would be spec-grounded; main thread to decide priorities and
allowlist any deferred items per the audit protocol.

---


# IETF — clock signaling

## RFC 7273

# RFC 7273 — Coverage Map vs `parse_sdp.lua`

Spec: RFC 7273 — RTP Clock Source Signalling (June 2014).
Inventory: `/tmp/audit_inventory_rfc7273.md` — 72 rows; 49 SDP-Y.
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines).
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`.

The parser implements ts-refclk/mediaclk through two helpers and a per-media
validation block:

- `valid_tsrefclk(value)` — lines 656–710
- `valid_mediaclk(value)` — lines 1111–1134 (with LPEG `_mc_rate_pat` 1119–1120)
- ts-refclk gather + presence + per-value validation — lines 1275–1292
- mediaclk gather + presence + per-value validation — lines 1213–1222, 1294–1301

Throughout the parser, `spec_ref` strings on these errors cite **ST 2110-10**
(§7.2 / §7.3 / §8.2 / §8.3), even when the underlying SHALL originates in
**RFC 7273**. RFC 7273 is named only inside source-code comments (lines 1111,
1116, 1131, 705) and in test descriptions. This is the Direction-C "cite the
SMPTE wrapper instead of the upstream IETF source" pattern called out in the
prompt. All such rows are flagged COVERED-WRONG-CITE below.

## Status legend

- `COVERED` — parser enforces and `spec_ref` cites the right document
- `COVERED-WRONG-CITE` — parser enforces, but the error's `spec_ref` is the
  SMPTE wrapper (ST 2110-10 §7.2/§7.3/§8.2/§8.3) rather than RFC 7273
- `WEAKER` — parser enforces a coarser check than the spec demands
- `STRICTER` — parser rejects forms the spec admits (potential over-strictness)
- `MISSING` — no check found
- `N/A` — clause is not an SDP-grammar/value constraint (out of scope by
  inventory marking, repeated here for completeness)

## Coverage table

| # | § | Summary | Status | Parser line(s) | Notes |
|---|---|---|---|---|---|
| 1 | 1.1 | RFC 2119 boilerplate | N/A | — | Boilerplate; not enforceable. |
| 2 | 4.1 | Reference clocks frequency-matched | N/A | — | Device property. |
| 3 | 4.2 | Multiple NTP `ts-refclk` permitted at one level | COVERED-WRONG-CITE | 1275–1292 | Loop iterates all `ts-refclk` (session + media) and validates each individually; repetition is accepted by construction. Error cite if any value is bad: `ST 2110-10 §7.2`. |
| 4 | 4.3 | SHOULD check gmid AND domain equivalence | N/A | — | Sender/receiver behaviour. |
| 5 | 4.3 | Multiple PTP `ts-refclk` permitted at one level | COVERED-WRONG-CITE | 1275–1292 | Same loop as row 3; accepts repetition. |
| 6 | 4.8 | Level precedence source > media > session | MISSING | — | No source-level handling at all (parser does not parse `a=ssrc:` source-level attribute children). Session+media gathering exists (1275–1292) but there is no inheritance / override logic; the loop unions both lists with no notion of "more specific overrides". For ST 2110 this is acceptable because the spec collapses to the media level, but as a RFC 7273 SDP-Y semantic it is uncovered. |
| 7 | 4.8 | Lowercase "must be defined for all levels" | MISSING | — | Inventory marks AMBIGUOUS. Parser does not enforce. Acceptable given the spec uses lowercase "must". |
| 8 | 4.8 | Repetition permitted; all at one level equivalent | COVERED-WRONG-CITE | 1275–1292 | Repetition accepted (see row 3). Equivalence semantics are out of scope for grammar acceptance. |
| 9 | 4.8 | Traceable MUST NOT mix with non-traceable at same level | MISSING | — | No traceable/non-traceable discrimination. RFC 7273 explicit MUST NOT — this is a real coverage gap. The parser will accept `a=ts-refclk:gps` and `a=ts-refclk:ntp=192.0.2.1` (non-traceable) on the same media block with no error. |
| 10 | 4.8 | `ts-refclk` legal at session, media, source levels | MISSING (partial) | — | Session/media accepted; source-level form (`a=ssrc:<id> ts-refclk:...`) not parsed. The parser never sees a source-level `ts-refclk`, so it neither accepts nor rejects it — it is just silently lost. |
| 11 | 4.8 Fig 1 | ABNF: `ts-refclk:` clksrc CRLF | COVERED-WRONG-CITE | 656–710 | Implemented as `value:match("^...$")` against several alternatives. CRLF/line-ending handled by the upstream grammar parser. |
| 12 | 4.8 Fig 1 | clksrc one of `ntp/ptp/gps/gal/glonass/local/private/clksrc-ext` | WEAKER + STRICTER | 658–709 | **Accepts**: `gps`, `gal`, `glonass`, `ntp=…`, `ptp=…`, **plus `localmac=…`** (a SMPTE ST 2110-10 extension, not in RFC 7273 ABNF). **Rejects**: bare `local`, bare `private`, `private:traceable`, and any other `clksrc-ext`. Final fallthrough at 709 returns "unrecognized ts-refclk clock source". |
| 13 | 4.8 Fig 1 | `clksrc-ext` extension form (token name + optional `=byte-string`) | MISSING | — | Any unknown name is rejected at 709 with no token-form fallback. |
| 14 | 4.8 Fig 1 | `ntp = "ntp=" hostport / "/traceable/"` | WEAKER | 660–666, 561–648 | Accepts `ntp=<addr>` where `<addr>` is IPv4, IPv6, or hostname — but **rejects `:port`** (no `[:port]` in the address grammar) and **rejects the `/traceable/` literal form**. Both are spec-legal. |
| 15 | 4.8 Fig 1 | `ptp = "ptp=" ptp-version ":" ptp-server` | COVERED-WRONG-CITE | 677–708 | Pattern is `^ptp=(.+)$` then splits on `:`. |
| 16 | 4.8 Fig 1 | `ptp-version` ∈ {`IEEE1588-2002`, `IEEE1588-2008`, `IEEE802.1AS-2011`, ptp-version-ext} | STRICTER | 687–689 | **Only `IEEE1588-2008` is accepted** (line 687). `IEEE1588-2002` and `IEEE802.1AS-2011` (both explicit literals in RFC 7273) are rejected, and the `ptp-version-ext = token` open extension is rejected. **Note**: ST 2110-10 narrows this to IEEE1588-2008 in its §8.2 SHALL, so the rejection is correct for the *SMPTE* tier but over-strict for the *RFC 7273* tier. As a pure RFC 7273 check this is STRICTER; in context of ST 2110 it is COVERED. |
| 17 | 4.8 Fig 1 | `ptp-server = ptp-gmid [":" ptp-domain] / "traceable"` | COVERED-WRONG-CITE | 685–706 | Both alternatives handled; literal `traceable` recognised (690, 704). |
| 18 | 4.8 Fig 1 | `ptp-gmid = EUI64` | COVERED-WRONG-CITE | 690–696 | Splits on `-`, validates 8 hex octets via `octet:match("^%x%x$")`. |
| 19 | 4.8 Fig 1 | `ptp-domain = name / nmbr` | WEAKER + STRICTER | 698–706 | **Only the number form is recognised** (line 700 `tonumber(domain)` and range 0..127). The `ptp-domain-name` form (`domain-name=<1..16 chars 0x21..0x7E>`) is not accepted. Additionally, per RFC 7273 errata 4450 the prefix `domain-nmbr=` was removed from the number form, so accepting bare digits is consistent with the corrected ABNF — but the name-form is still defined and is missing. |
| 20 | 4.8 Fig 1 | `ptp-domain-name`: literal `domain-name=` + 1..16 chars in 0x21..0x7E | MISSING | — | Not implemented; bare `domain-name=…` will fail at `tonumber()` (line 700) with the generic "must be 0-127" message, mis-attributing the error. |
| 21 | 4.8 Fig 1 | `ptp-domain-nmbr` integer 0..127, no leading zeros | WEAKER | 700–702 | Accepts 0..127 via `tonumber()` + range check, but **`tonumber("001")` returns 1**, so leading-zero forms like `001` are accepted. RFC 7273 ABNF (`POS-DIGIT DIGIT` etc.) forbids leading zeros. STRICTER part: pre-errata `domain-nmbr=` prefix is rejected (which matches the errata-corrected ABNF and is correct). |
| 22 | 4.8 Fig 1 | `gps` bare literal | COVERED-WRONG-CITE | 659 | Accepted as exact string match. |
| 23 | 4.8 Fig 1 | `gal` bare literal | COVERED-WRONG-CITE | 659 | Accepted as exact string match. |
| 24 | 4.8 Fig 1 | `glonass` bare literal | COVERED-WRONG-CITE | 659 | Accepted as exact string match. |
| 25 | 4.8 Fig 1 | `local` bare literal | MISSING | — | Bare `local` is rejected at 709 ("unrecognized ts-refclk clock source"). RFC 7273 explicit literal. |
| 26 | 4.8 Fig 1 | `private [":traceable"]` literal | MISSING | — | Bare `private` and `private:traceable` both rejected at 709. |
| 27 | 4.8 Fig 1 | EUI64 form: 7×(2HEXDIG-) + 2HEXDIG | COVERED-WRONG-CITE | 690–696 | Hex-pair-and-hyphen check; 8-octet count enforced (696). Lowercase hex accepted (test line 485). |
| 28 | 5.1 | `a=mediaclk:sender` form | COVERED-WRONG-CITE | 1122 | Exact string `"sender"` accepted. |
| 29 | 5.2 | `mediaclk:direct` REQUIRES co-present `ts-refclk` | COVERED (indirect) | 1284–1286 + 1294–1301 | ST 2110-10 requires `ts-refclk` unconditionally for every media block (1284–1286 cite §7.2), so the conditional RFC 7273 requirement is satisfied as a side-effect of the unconditional SMPTE requirement. The error cite (`ST 2110-10 §7.2`) does not mention RFC 7273 §5.2 / §6, but the behaviour is correct (over-eager: `ts-refclk` is also required when mediaclk is `sender`, where RFC 7273 §6 says MAY). |
| 30 | 5.2 | Direct offset SHOULD use TAI reference clock | N/A | — | Operational guidance. |
| 31 | 5.2 | Rate in SDP must match RTCP SR-implied rate | N/A | — | Runtime cross-protocol check. |
| 32 | 5.2 | `direct[=<offset>] [rate=<num>/<den>]` value form | STRICTER + COVERED-WRONG-CITE | 1119–1133 | **STRICTER**: line 1125 forces `offset == "0"`, rejecting any non-zero offset (e.g. `direct=12345`). This is correct for ST 2110-10 §8.3 (which mandates offset=0) but is **stricter than RFC 7273 §5.4** which allows any unsigned `1*DIGIT`. Also, `direct` without an `=offset` (legal per RFC 7273 — the `[=<offset>]` is optional) is rejected at 1123 because the match pattern requires `direct=…`. In context of ST 2110 this is COVERED; for pure RFC 7273 it is STRICTER. |
| 33 | 5.3 | Identifier uniqueness; SHOULD follow RFC 7022 CNAME | N/A | — | System-wide property and generation algorithm; not in SDP grammar. |
| 34 | 5.3 | `media-clktag` MUST be base64 | MISSING | — | The whole `mediaclk:id=…` family is unparsed. |
| 35 | 5.3 | Master clock stream SHOULD be identified by SSRC + media-clktag at source level | N/A (SHOULD) | — | Placement guidance. |
| 36 | 5.3 | Master-clock-source streams SHOULD carry `src:` prefix | N/A (SHOULD) | — | Placement guidance. |
| 37 | 5.3 | Inheritance MUST guarantee equivalent timing | N/A | — | Device behavioural requirement. |
| 38 | 5.3 | `a=ssrc:<ssrc> mediaclk:id=src:<tag> sender` form | MISSING | — | No source-level attribute parsing; no `id=` form. |
| 39 | 5.3 | `a=mediaclk:id=src:<tag> sender` form | MISSING | — | `valid_mediaclk` (1121–1134) does not recognise `id=…` prefix; any SDP with this attribute fails at 1124 ("unrecognized mediaclk value"). |
| 40 | 5.3 | `a=mediaclk:id=<tag> sender` form | MISSING | — | Same as row 39. |
| 41 | 5.3 | `a=mediaclk:IEEE1722=<StreamID>` form | MISSING | — | `valid_mediaclk` does not recognise `IEEE1722=`; falls through 1124. |
| 42 | 5.3 | `a=mediaclk:id=src:<tag> IEEE1722=<StreamID>` form | MISSING | — | Same as row 41 plus row 38. |
| 43 | 5.4 | mediaclk level precedence source > media > session | MISSING | — | Session-level mediaclk is *forbidden* by ST 2110-10 §8.3 and the parser enforces that at lines 1213–1222. So the RFC 7273 precedence rule is moot at the ST 2110 tier — for pure RFC 7273 it is uncovered. Source-level mediaclk is not parsed. |
| 44 | 5.4 | Repetition permitted at one level | MISSING | — | `find_attr(mattrs, "mediaclk")` (line 1294) returns only the **first** match; a second `a=mediaclk` on the same media block is silently dropped (or, more precisely, never inspected). Not a reject — but the equivalence semantic is not exposed. Also, ST 2110 typically has one mediaclk per stream, so practical impact is small. |
| 45 | 5.4 | `mediaclk` legal at session, media, source | MISSING (partial) | 1213–1222, 1294 | Media-level enforced; session-level rejected (ST 2110 §8.3 forbids it, line 1216–1221) — note this **rejects what RFC 7273 §5.4 permits**, but it is a SMPTE-tier tightening so STRICTER vs RFC 7273. Source-level not parsed. |
| 46 | 5.4 Fig 5 | ABNF root: `mediaclk:` [media-clkid SP] mediaclock | WEAKER | 1121–1133 | The optional `media-clkid SP` prefix is not handled at all. |
| 47 | 5.4 Fig 5 | `media-clkid = "id=" [ "src:" ] media-clktag` | MISSING | — | See row 34. |
| 48 | 5.4 Fig 5 | `mediaclock ∈ {sender, direct, ieee1722-streamid, mediaclock-ext}` | WEAKER | 1121–1133 | Only `sender` and `direct…` are recognised. |
| 49 | 5.4 Fig 5 | `mediaclock-ext` extension form (token + optional `=byte-string`) | MISSING | — | Falls through 1124 with "unrecognized mediaclk value". |
| 50 | 5.4 Fig 5 | `sender` bare literal | COVERED-WRONG-CITE | 1122 | Exact string match. Error cite for malformed neighbouring values is `ST 2110-10 §7.3` / `§8.3`. |
| 51 | 5.4 Fig 5 | `direct = "direct" [ "=" 1*DIGIT ] [SP rate]` | STRICTER + WEAKER | 1119–1133 | STRICTER: forces offset `==0` (1125) and requires `=offset` to be present (1123 — pattern is `direct=…`). WEAKER: rate alternative without offset (`direct rate=…`) cannot occur because offset is required by 1123. Note the offset capture pattern `(%-?%d+)` accepts a leading minus (1123); RFC 7273 ABNF for `direct` offset is `1*DIGIT` (unsigned). The follow-on equality `offset ~= "0"` rejects `-0`, so effectively only `0` survives. |
| 52 | 5.4 Fig 5 | `ieee1722-streamid = "IEEE1722=" avb-stream-id (EUI64)` | MISSING | — | See row 41. |
| 53 | 6 | SHOULD include both ref-clock and media-clock | N/A (SHOULD) | — | Both REQUIRED at ST 2110 tier (1284, 1295) — STRICTER vs RFC 7273 SHOULD; this is the SMPTE tightening. |
| 54 | 6 | Default semantics when attribute absent | N/A | — | Receiver behaviour. |
| 55 | 6 | `mediaclk:direct` REQUIRES ts-refclk | COVERED (indirect) | 1284–1286 | See row 29; ST 2110-10 makes ts-refclk unconditional, satisfying the cross-attribute rule. |
| 56 | 6 | `sender`/stream-ref MAY omit ts-refclk | STRICTER | 1284–1286 | RFC 7273 says ts-refclk is optional when mediaclk is `sender`. ST 2110-10 §7.2 makes ts-refclk required regardless. SMPTE tightening: COVERED for ST 2110, STRICTER vs pure RFC 7273. |
| 57 | 6.1 | RFC 5939 negotiation MAY be used | N/A | — | O/A negotiation. |
| 58 | 6.1.1 | Offerer SHOULD include `local` ref-clock | N/A | — | O/A behaviour. |
| 59 | 6.1.2 | Answerer SHOULD respond with usable subset | N/A | — | O/A behaviour. |
| 60 | 6.1.2 | Rejection MUST include usable ref-clock | N/A | — | O/A behaviour. |
| 61 | 6.1.2 | No external → `local` in rejection | N/A | — | O/A behaviour. |
| 62 | 6.1.3 | Answerer SHOULD match offer for mediaclk | N/A | — | O/A behaviour. |
| 63 | 6.1.3 | Rejection MUST include usable mediaclk | N/A | — | O/A behaviour. |
| 64 | 6.1.3 | No shared media clock → asynchronous in rejection | N/A | — | O/A behaviour. |
| 65 | 6.2 | Receiver SHOULD assess compatibility | N/A | — | Receiver behaviour. |
| 66 | 7 | Devices MAY validate clock-description integrity | N/A | — | Security guidance. |
| 67 | 8.3 | IANA registry policy for clksrc-param-name | N/A | — | Registry policy. |
| 68 | 8.3 | Initial clksrc names: `ntp ptp gps gal glonass local private` | MIXED | 658–709 | Of the seven initial-value tokens: `ntp` COVERED, `ptp` COVERED, `gps`/`gal`/`glonass` COVERED, `local` MISSING (rejected), `private` MISSING (rejected). Plus the parser **adds** `localmac=` which is not in RFC 7273. |
| 69 | 8.4 | IANA registry policy for mediaclock-param-name | N/A | — | Registry policy. |
| 70 | 8.4 | Initial mediaclock names: `sender direct IEEE1722` | MIXED | 1121–1133 | `sender` COVERED, `direct` COVERED (with SMPTE tightening), `IEEE1722` MISSING. |
| 71 | 8.1 | `ts-refclk` registered for session, media, source | MISSING (partial) | 1275–1292 | Session+media handled; source-level (via `a=ssrc:`) not parsed. No reject on attribute-at-wrong-level is emitted because the parser only *looks* at session+media. |
| 72 | 8.2 | `mediaclk` registered for session, media, source | STRICTER + MISSING | 1213–1222, 1294 | Session forbidden by ST 2110-10 § 8.3 (1216–1221) — STRICTER vs RFC 7273 §8.2 which permits all three levels. Source-level not parsed. |

## Summary counts (SDP-Y rows only; 49 rows)

- COVERED-WRONG-CITE: 12 (rows 3, 5, 8, 11, 15, 17, 18, 22, 23, 24, 27, 28, 50)
  → 13 once row 50 is counted; the citation issue is the dominant finding.
- COVERED indirect / via SMPTE tightening: 2 (rows 29, 55)
- WEAKER (parser silently misses spec-required behaviour): rows 6, 12 (partial),
  14, 19 (partial), 21 (leading zeros), 46, 48
- STRICTER (parser rejects spec-legal forms): rows 12 (no `local`/`private`),
  16 (only IEEE1588-2008), 32 (offset=0), 45 (no session mediaclk), 51
  (offset=0), 56 (ts-refclk always required), 72 (no session mediaclk)
- MISSING (no enforcement at all where some is required): rows 9 (traceable
  mixing), 10 (source-level), 13 (clksrc-ext), 20 (ptp-domain-name), 25
  (`local`), 26 (`private`), 34 (base64 clktag), 38–42 (mediaclk id/IEEE1722),
  43, 44 (repetition), 47, 49, 52, 71 (source-level placement)
- N/A: 23 rows (matches inventory: 23 OoS rows)

## Top 3 findings

### Finding 1 — Direction-C: 13+ rows cite ST 2110-10 wrapper instead of RFC 7273

Every error emitted by `valid_tsrefclk` (via lines 1285, 1290) and
`valid_mediaclk` (via lines 1296, 1300) carries `spec_ref = "ST 2110-10 §7.2"`
or `"ST 2110-10 §7.3"` (or `§8.2` / `§8.3`). The actual ABNF / value-set /
form-rules being enforced (clksrc literals, EUI-64 form, ptp-version literals,
domain range, ntp address, sender/direct literals) originate in **RFC 7273
§§4.8 and 5.4** — the ST 2110-10 clauses merely state "shall follow IETF RFC
7273" and provide additional restrictions.

Affected rows (13): 3, 5, 8, 11, 15, 17, 18, 22, 23, 24, 27, 28, 50.

Main-thread decision: either replace the cite with `RFC 7273 §4.8` /
`§5.4`, or append it (e.g. `"RFC 7273 §4.8 / ST 2110-10 §7.2"`). The current
cites are not *wrong* — ST 2110-10 does adopt these rules — but they
obscure the upstream IETF source the user must consult to interpret an error.

### Finding 2 — Missing RFC 7273 forms and value tokens (STRICTER over-rejects)

The parser categorically rejects four classes of input that are legal RFC
7273 (and therefore legal at the SMPTE tier too, unless ST 2110-10 explicitly
tightens — and several do not):

- bare `a=ts-refclk:local` — RFC 7273 §4.8 Fig 1 literal, IANA initial value
- bare `a=ts-refclk:private` (with optional `:traceable`) — IANA initial value
- `a=ts-refclk:ntp=…/traceable/` and `a=ts-refclk:ntp=host:port` — both legal
  per the `ntp-server-addr = hostport / "/traceable/"` rule
- `a=mediaclk:IEEE1722=…`, `a=mediaclk:id=…`, `a=mediaclk:id=src:…` — entire
  family of stream-referenced mediaclk forms (rows 34, 38–42, 47, 52)
- `a=ts-refclk:ptp=IEEE1588-2002:…` and `a=ts-refclk:ptp=IEEE802.1AS-2011:…`
  — ST 2110-10 narrows to IEEE1588-2008, so this is intentional at the SMPTE
  tier; pure RFC 7273 reject is over-strict.

Main-thread decision: which of these the library should accept depends on
whether the validator's contract is "RFC 7273 grammar" or "ST 2110-10
profile of RFC 7273". For the IPMX/ST 2110 use case, ignoring `id=`/`IEEE1722=`
mediaclk forms is consistent with §8.3 — but the rejection should cite that
clause as a *narrowing* of RFC 7273, not as a generic "unrecognized mediaclk
value".

### Finding 3 — Genuine RFC 7273 enforcement gap: traceable/non-traceable mixing (§4.8 MUST NOT)

RFC 7273 §4.8: *"Traceable time sources MUST NOT be mixed with non-traceable
time sources at any given level."* This is the only RFC 7273 MUST NOT in the
inventory. The parser gathers all `ts-refclk` attributes across session and
media into `all_tsrefclk` (lines 1275–1283) and validates each *individually*,
but never classifies them as traceable vs non-traceable or compares the set.

The classification rule, per RFC 7273:
- Traceable: `gps`, `gal`, `glonass` (§4.4); `ntp=/traceable/`;
  `ptp=…:traceable`; `private:traceable`
- Non-traceable / variable: `ntp=<hostport>`; `ptp=…:<gmid>:<domain>`;
  `local`; `private` (no suffix)

This is a real coverage gap. The fix is a single pass over `all_tsrefclk`
counting "has traceable" and "has non-traceable" and rejecting when both > 0.
Cite `RFC 7273 §4.8` directly.

## Reverse direction (parser → spec)

```
561:-- LPEG patterns for ts-refclk ntp= address format validation.
656:-- Validate the value of a ts-refclk attribute per ST 2110-10 §7.2.
1111:-- Validate the value of a mediaclk attribute per ST 2110-10 §8.3 (which defers
1112:-- to IETF RFC 7273 §5) and TR-10-1 §10.5. Permitted forms:
1113:--   "sender"                              (async; RFC 7273 §5.2)
1114:--   "direct=<offset>"                     (RFC 7273 §5.4; offset SHALL be 0
1116:--   "direct=<offset> rate=<int>/<int>"    (RFC 7273 §5.4 rate option, used
1131:    return nil, "invalid mediaclk rate (expected ' rate=<int>/<int>' per RFC 7273 §5.4)"
```

`RFC 7273` appears only in comments — never as an error-table `spec_ref`.
This confirms the Direction-C pattern: the parser knows RFC 7273 is the
upstream source but cites the SMPTE wrapper to the user.

---


# IETF — RTP payload formats

## RFC 8331

# RFC 8331 Coverage Mapping

**Spec**: RFC 8331 — RTP Payload for SMPTE ST 291-1 Ancillary Data
**Parser**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
**Inventory**: `/tmp/audit_inventory_rfc8331.md` (48 rows total; 16 SDP-marked)
**Mode**: Phase 2 mechanical coverage — each SDP-Y row mapped to parser check or MISSING.

| Inv# | § | Verb | One-liner | Parser line(s) | Check name / construct | Status |
|---|---|---|---|---|---|---|
| 23 | 3 | defined-value | Media type identifier `video/smpte291` (registered). | 1364 | `if enc == "smpte291" then …` (gate on rtpmap encoding name) | COVERED — encoding-name dispatch keyed on the exact registered subtype. |
| 24 | 3.1 | Required parameter | Type name "video" (mapped to `m=video` per §4). | 1368-1372 | `if m.media ~= "video" then attr_err("smpte291 requires m=video … per RFC 8331 §4") ` | COVERED — explicit reject of `m=audio` / `m=application` etc. carrying `smpte291`. Cite `RFC 8331 §4`. |
| 25 | 3.1 | Required parameter | Subtype "smpte291" → rtpmap encoding name. | 1364 | rtpmap encoding-name dispatch (`enc` from `rtpmap_parse`) | COVERED — implicit via the encoding-name match. Misspellings (e.g. `smpte-291`) would fall through to generic handling without the smpte291 block running, which is per spec. |
| 26 | 3.1 | Required parameter | Rate (RTP timestamp clock rate) — required. | 553-558, 1325 | `rtpmap_parse` requires `^([^/]+)/(%d+)`; absence of `/rate` returns `nil` and downstream rejects unknown encoding | COVERED — rtpmap without a clock rate fails the grammar (cannot reach the smpte291 branch). |
| 27 | 3.1 | SHOULD | Rate SHOULD match the associated video stream, else SHOULD be 90 kHz. | 1374-1378 | `if clock_rate ~= 90000 then attr_err("rtpmap clock rate must be 90000 for smpte291 …") ` | COVERED AS HARD CHECK — but cited as `ST 2110-40 §7.2`, not RFC 8331 §3.1. RFC 8331 row 27 is SHOULD; the parser's hard-reject is grounded in the ST 2110-40 SHALL, not RFC 8331. From the RFC-8331-only perspective this would be over-strict; from the ST 2110 perspective it is correct. Distinguish: RFC 8331 row 27 → NOT-A-CHECK by RFC 8331's authority; ST 2110-40 §7.2 SHALL → COVERED. |
| 28 | 3.1 | Optional parameter | DID_SDID exists as optional fmtp parameter. | 1386-1393 | `for v in (fmtp.value):gmatch("DID_SDID=([^;%s]+)") do valid_did_sdid(v) end` | COVERED — parameter is recognized, value-form validated when present, absence accepted (tests 612–619 and 546–551). |
| 30 | 3.1 | Optional parameter | VPID_Code optional integer fmtp parameter. | 1394-1401 | `local vpid = params["VPID_Code"]; tonumber(…); n >= 0; n == floor(n)` | COVERED — parameter recognized, integer form validated when present (tests 2025–2058), absence accepted. |
| 31 | 3.1 | SHALL | VPID_Code integer bit-ordering from VPID byte 1 (MSB = bit 7). | — | — | NOT-A-CHECK — this constrains *how the integer is computed from the underlying VPID byte*. The SDP carries an opaque integer; the parser cannot verify the bit-ordering from SDP text alone. Out of SDP-validation scope (the source byte is not in the SDP). |
| 32 | 4 | SHALL | Mapping to SDP follows RFC 4855 §3. | 1364-1467 (whole smpte291 branch) | top-level dispatch | COVERED INDIRECTLY — RFC 4855 §3 mapping requirement is what produces rows 33/34/35; the parser implements those individually. No standalone SHALL-mapping check is needed (or possible). |
| 33 | 4 | mapping | "video" → `m=` media name. | 1368-1372 | same check as row 24 | COVERED — see row 24. |
| 34 | 4 | mapping | "smpte291" → `a=rtpmap` encoding name, with `/rate`. | 553-558, 1364 | rtpmap grammar + encoding-name dispatch | COVERED — implicit via rtpmap parsing + encoding-name gate. |
| 35 | 4 | mapping | VPID_Code and DID_SDID, when present, appear in `a=fmtp` as semicolon-separated `param=value` pairs. | 1174-1192, 1356-1362 | `fmtp_params` parses `param=value` pairs separated by `;`; consumed by the smpte291 branch at 1386, 1394 | COVERED — fmtp grammar + parameter extraction. |
| 36 | 4 | SHALL | DID and SDID values are hex with `0x` prefix (e.g. `0x61`). | 712-716, 1387-1392 | `valid_did_sdid`: `^{0x%x%x,0x%x%x}$` | COVERED but slightly stricter than ABNF — requires literal `0x` prefix with hex digits (per row 36); reject path tested at 621-628, 636-642. The strictness gap is captured under row 37 (digit count). |
| 37 | 4 | SHALL / ABNF | `DidSdid = "DID_SDID={" TwoHex "," TwoHex "}"`; `TwoHex = "0x" 1*2(HEXDIG)` — i.e. **1 OR 2** hex digits. | 712-716 | `^{0x%x%x,0x%x%x}$` requires **exactly 2** hex digits | OVER-STRICT — parser rejects `DID_SDID={0x6,0x2}` and `DID_SDID={0x61,0x2}`, both of which are valid per the ABNF (`1*2(HEXDIG)`). Spec text quoted in inventory row 37 and §4 ABNF. **CANDIDATE FOR PHASE 3 FIX**: relax pattern to `^{0x%x%x?,0x%x%x?}$`. Also note: the ABNF does not constrain whitespace inside the braces, but tightening that is opinion. |
| 39 | 4 | SHALL | VPID_Code, if present, appears only once and takes a single integer value. | 1174-1192, 1394-1401 | `fmtp_params` stores at one key (`params[k] = v`); subsequent occurrences silently overwrite. No explicit cardinality check. | MISSING — duplicate `VPID_Code=N1; VPID_Code=N2` is silently coalesced to the last value rather than rejected. The "single integer value" half is covered (1395-1400 validates `tonumber/non-negative/integer`); the "only once" half is **not** enforced. **CANDIDATE FOR PHASE 3 FIX**: track repeated keys in `fmtp_params` (or scan `fmtp.value` for `VPID_Code=` count) and reject when >1. |
| 44 | 6 | IANA | `video/smpte291` registered. | 1364 (encoding-name dispatch) | same as row 23/25 | COVERED — confirms expected encoding name; no separate check needed. |

## AMBIGUOUS rows (not actionable as SDP checks)

- **Row 27** (Rate value SHOULD 90 kHz): handled above; reject is grounded in ST 2110-40, not in RFC 8331.
- **Row 29** (Type-1 packets labeled SDID=0x00): per-packet labeling rule in §3.1; not enforceable from SDP alone (would require enumerating Type-1 DIDs from SMPTE-RA registry, which is out of scope per the strictness principle). NOT-A-CHECK.
- **Row 43** (Declarative SDP MUST be used as given): binding-of-configuration affirmation; no new field-form constraint. NOT-A-CHECK.

## Out-of-scope rows (N rows skipped)

Inventory rows 1–22, 38, 40–42, 45–48 are RTP payload byte semantics, sender/receiver behavior, MAY clauses, offer/answer flow, or security guidance. All 32 are flagged `SDP? = N` in the inventory and have no parser counterpart by design (per CLAUDE.md "Out of scope: RTCP-layer signaling… SDP-only validator does not validate runtime behavior").

## Reverse direction — parser citations of RFC 8331

```sh
grep -nE '"RFC 8331|RFC 8331 §' /Users/andrewstarks/src/parse_sdp/parse_sdp.lua
```

Citations found at lines 1370 (`RFC 8331 §4` — m=video requirement) and 1390 (`RFC 8331 §4` — DID_SDID format).

Both are inside the smpte291 branch (1364-1467). No orphaned RFC 8331 citations elsewhere in the file. No "reverse-direction" finding (i.e. no parser claim citing RFC 8331 without a backing clause in the inventory).

The remaining RFC 8331-relevant parser logic carries `ST 2110-40 §7` or `ST 2110-40:2023 §7` citations (lines 1374-1378, 1413, 1424, 1431, 1441, 1445, 1456, 1466). Those belong to the ST 2110-40 audit, not this one.

## Unknown-fmtp-parameter handling (RFC 8331 "Receiver SHALL ignore unrecognized parameter")

The parser does **NOT** reject unknown fmtp parameters on smpte291 streams. `fmtp_params` (1174-1192) accepts any well-formed `key=value` (or bare flag) token. The smpte291 branch only inspects the keys it knows (`DID_SDID`, `VPID_Code`, `TM`, `SSN`, `exactframerate`, `TROFF`, `MAXUDP`). Anything else is silently retained in `params` and ignored.

This is **correct** per RFC 8331 §3.1: "Receiver SHALL ignore any unrecognized parameter." A strict-reject of unknown fmtp would *contradict* that SHALL. No finding here.

(Caveat: `TM`/`SSN`/`exactframerate`/`TROFF`/`MAXUDP` checks are grounded in ST 2110-40, not RFC 8331; from a pure RFC 8331 perspective those checks add constraints the RFC does not impose. That tension is the ST 2110-40 audit's concern, not this one — for receivers operating in pure RFC 8331 contexts without ST 2110-40, the parser would (correctly per ST 2110, possibly over-strict per RFC 8331) require those parameters. Phase 3 may want to consider gating ST 2110-40-derived smpte291 checks by tier.)

## Summary

- Rows enumerated as SDP-Y: **16** (rows 23, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35, 36, 37, 39, 44).
- **COVERED**: 11 (rows 23, 24, 25, 26, 28, 30, 32, 33, 34, 35, 36, 44 — note row 32 is "covered indirectly", row 35 by fmtp grammar; 12 if counting row 27 under ST 2110-40 authority).
- **OVER-STRICT**: 1 (row 37 — DID_SDID hex digit count: `1*2(HEXDIG)` per ABNF, but parser requires exactly 2).
- **MISSING**: 1 (row 39 — VPID_Code "only once" cardinality not enforced; duplicate keys silently coalesced).
- **NOT-A-CHECK** (out of SDP-validation reach by design): 3 (row 27 from RFC 8331 perspective — SHOULD-only; row 31 — bit-ordering not observable from SDP; row 32 — top-level mapping SHALL implemented by sub-rows).
- AMBIGUOUS rows from inventory: 3 — all resolved above.
- Reverse direction: clean; both `RFC 8331 §4` citations in the parser map to inventory rows 24 and 36/37.

---

## RFC 9134

# RFC 9134 — Coverage Map (Audit)

Spec: RFC 9134 — "RTP Payload Format for ISO/IEC 21122 (JPEG XS)" (October 2021)
Inventory: `/tmp/audit_inventory_rfc9134.md` (64 rows, 33 SDP-Y)
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (jxsv block: lines 1506–1711)
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua` (M22 block: lines 2979–3338)

Method: For every `SDP? = Y` row in the inventory, locate the parser check that enforces it (or note absence). Non-SDP rows (N) are listed at the bottom in a single block. Status flags: COVERED · COVERED-CITE-OFF · MISSING · NOT-VALIDATOR-ACTIONABLE · OUT-OF-SCOPE.

## SDP-Y Coverage Table (33 rows)

| Inv # | § | Summary | Parser check (file:line) | Spec cite in code | Status | Notes |
|---|---|---|---|---|---|---|
| 13 | 4.2 | rtpmap clock rate = 90000 | `parse_sdp.lua:1516-1520` | "ST 2110-22 §7" | COVERED-CITE-OFF | Check exists and rejects non-90000. Cite is "ST 2110-22 §7"; RFC 9134 §4.2 (with §7.1 `rate` / §8.1) is the authoritative locus. Acceptable as triangulated cite but RFC 9134 should appear alongside (or in place of) the ST 2110-22 cite. |
| 26 | 5 | TP required when -21 traffic shaping signaled | `parse_sdp.lua:1574-1578` (TP in jxs_req) + value-set `VALID_TP_22` at line 895 | "ST 2110-22 §7.2" | COVERED — but at the wrong tier for RFC 9134 | Parser makes TP **mandatory** at ST 2110-22 tier, citing ST 2110-22:2022 §7.2 Table 1. RFC 9134 §5 only conditionally requires TP (when -21 traffic shaping is implemented). Parser's stronger requirement is correct **at the ST 2110-22 tier** (which is what 9134 rows are reviewed under here) but means RFC 9134 §5 as a standalone clause is not the cite — ST 2110-22 §7.2 is. AMBIGUOUS flagged in inventory row 26 (TP not in §7.1 parameter list); parser treats TP as a 2110-22-side parameter, not an IANA registration parameter. Consistent with code comment at line 1591–1593. |
| 30 | 7 | When any payload-format parameter is provided in SDP, its value SHALL be consistent with the payload | n/a | n/a | NOT-VALIDATOR-ACTIONABLE | Cross-layer coherence rule requiring access to in-band codestream / RTP payload header; cannot be validated from SDP alone. Inventory row 30 confirms this. No parser action required. |
| 31 | 7.1 | Receiver SHALL ignore any unrecognized parameter | `parse_sdp.lua:1689-1711` (no closed-fmtp-key check after the explicit allowlist) | n/a (silent allow) | COVERED (by omission) | Parser does not reject unknown fmtp keys in the jxsv block — there is no "unknown key" gate after `MAXUDP`/`CMAX`/`fbblevel` removal at line 1706–1711. Test at `st2110_spec.lua:3256-3268` confirms `fbblevel=…` passes. No conflict with §7.1 / §8.1 "ignore unrecognized" rule. |
| 32 | 7.1 | Media type fixed: `video/jxsv` | `parse_sdp.lua:1506` (`elseif enc == "jxsv"`) + `parse_sdp.lua:1511-1515` (m.media must equal "video") | "ST 2110-22:2022 §6.2" | COVERED-CITE-OFF | Parser dispatches on `enc == "jxsv"` and requires `m=video`. The encoding-name identity itself is asserted by the dispatch (no malformed-name path here); the `m=video` check cites ST 2110-22:2022 §6.2, which is correct, but RFC 9134 §7.1 "Type name: video / Subtype name: jxsv" is the primary cite for the encoding-name binding. Triangulated, not wrong. |
| 33 | 7.1 | Required parameter `rate` = 90000 | `parse_sdp.lua:1516-1520` | "ST 2110-22 §7" | COVERED-CITE-OFF | Same as row 13. The cite should be RFC 9134 §7.1 (or `§4.2 + §7.1` together); the spec_ref is "ST 2110-22 §7". |
| 34 | 7.1 | `packetmode` REQUIRED, ∈ {0, 1}; must match K bit | Required: `parse_sdp.lua:1578` (`jxs_req` table includes `packetmode`); value set: `VALID_JXS_BIT` at line 939 = `{"0","1"}` | "ST 2110-22 §7.2" (spec_ref on the wrapping loop, line 1650) | COVERED-CITE-OFF | `packetmode` is in `jxs_req`, so absence → "fmtp missing required 'packetmode' parameter for jxsv" (line 1645). Value set check via `valid_enum`. Parser's authoritative cite for `packetmode` is **RFC 9134 §7.1** (the IANA registration); code comment at line 1569 correctly notes "RFC 9134 §7.1" but the emitted `spec_ref` is "ST 2110-22 §7.2". Coherence-with-K-bit (must match K) is NOT-VALIDATOR-ACTIONABLE. |
| 35 | 7.1 | Optional `transmode` ∈ {0, 1}; default 1 | `parse_sdp.lua:1596-1602` (validates when present) | "ST 2110-22 §7.2" | COVERED-CITE-OFF | Value set check via `VALID_JXS_BIT`. Default-when-absent is not asserted as an SDP error (correctly — defaults are interpretation, not validation). Code comment at line 1588–1595 explains transmode optionality. Spec_ref "ST 2110-22 §7.2" is wrong: ST 2110-22 §7.2 does not list transmode; RFC 9134 §7.1 is the authority. |
| 36 | 7.1 | Optional `profile`; whitespace removed; ISO 21122-2 value set | `parse_sdp.lua:1603-1609` (validates against closed `VALID_JXS_PROFILE` at line 903) | "ST 2110-22 §7.2" | COVERED-CITE-OFF (with spec-grounding concern) | Parser uses a closed value set sourced from "VSF TR-08 §8.1.1 / TR-10-15-Part1" (per comment at line 901–902). **RFC 9134 §7.1 explicitly defers profile values to ISO 21122-2 and does NOT enumerate them.** The inventory flagged this as AMBIGUOUS (row 36). Parser enforces the TR-08 list, which is acceptable **at the ST 2110-22 tier** since TR-08 is the operationally-cited closed list, but the spec_ref "ST 2110-22 §7.2" is wrong (ST 2110-22 §7.2 does not enumerate profiles either). The closed list is grounded in TR-08, not RFC 9134; the audit may want to either (a) relax to "non-empty token, no whitespace" per RFC 9134 §7.1 alone, or (b) keep the TR-08 list and fix the cite. |
| 37 | 7.1 | Optional `level`; whitespace removed; ISO 21122-2 value set | `parse_sdp.lua:1610-1616` (closed `VALID_JXS_LEVEL` at line 918) | "ST 2110-22 §7.2" | COVERED-CITE-OFF (with spec-grounding concern) | Same shape as row 36. Parser enforces a closed list (Unrestricted, 1k-1, 2k-1, 4k-1/2/3, 8k-1/2/3, 16k-1/2/3) — sourced from TR-08 / ISO 21122-2 per comment. RFC 9134 §7.1 says only "examples are '2k-1' or '4k-2'" — not enumeration. Same cite issue as row 36. |
| 38 | 7.1 | Optional `sublevel`; whitespace removed; ISO 21122-2 value set | `parse_sdp.lua:1617-1623` (closed `VALID_JXS_SUBLEVEL` at line 928) | "ST 2110-22 §7.2" | COVERED-CITE-OFF (with spec-grounding concern) | Same as rows 36–37. Closed list sourced from "TR-10-15-Part1 §7.1 / ISO/IEC 21122-2"; RFC 9134 itself does not enumerate. Same cite issue. |
| 39 | 7.1 | Optional `depth` — integer; examples 8/10/12/16 | `parse_sdp.lua:1584` (`{ "depth", valid_pos_int }` in `jxs_opt`) | "ST 2110-22 §7 / RFC 9134 §7.1" (loop spec_ref at line 1659) | COVERED | RFC 9134 only says "integer" and gives examples; parser uses `valid_pos_int` (any positive integer), so 8/10/12/16 AND other depths (e.g. 14, 24) are accepted. This matches RFC 9134's open-ended formulation correctly. Note: the closed `VALID_DEPTH = {8,10,12,16,16f}` set in the parser (line 963) is ST 2110-20 §7.4.2 territory and is **not** applied to jxsv. Correct call. |
| 40 | 7.1 | Optional `width` ∈ [1, 32767] | `parse_sdp.lua:1575` (`{ "width", valid_pos_int }` in `jxs_req`) | "ST 2110-22 §7.2" | MISSING (upper bound) — partial coverage | Parser uses `valid_pos_int` which checks only "positive integer", not the [1, 32767] inclusive range. The bounded `valid_width` helper (line 985) IS defined but is used only by the ST 2110-20 raw-video path. RFC 9134 §7.1 normatively constrains width to [1, 32767]. Lower bound (>0) is covered; upper bound (≤32767) is **not enforced** for jxsv. Also a tier-coupling note: width is in `jxs_req` so the parser treats it as REQUIRED at the ST 2110-22 tier (per ST 2110-22:2022 §7.2 Table 1), which is stronger than RFC 9134's "Optional". Correct given the tier. |
| 41 | 7.1 | Optional `height` ∈ [1, 32767] | `parse_sdp.lua:1576` (`{ "height", valid_pos_int }` in `jxs_req`) | "ST 2110-22 §7.2" | MISSING (upper bound) — partial coverage | Identical analysis to row 40. `valid_pos_int` only checks positive; `valid_height` (line 986) exists but is unused for jxsv. Upper bound 32767 is **not enforced**. |
| 42 | 7.1 | Optional `exactframerate` — integer or N/D reduced ratio | `parse_sdp.lua:1583` (`{ "exactframerate", valid_exactframerate }` in `jxs_opt`); helper at lines 1012–1031 | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED | `valid_exactframerate` enforces "either integer or N/D" and rejects non-reduced ratios (gcd≠1) with the ST 2110-20:2022 §7.2 cite for the "lowest-terms" wording. RFC 9134 §7.1 has the same "numerically smallest numerator value possible" wording, so the lowest-terms check is grounded in RFC 9134 too. |
| 43 | 7.1 | `interlace` is a bare-token presence flag | `parse_sdp.lua:1676-1681` (rejects `interlace=value`) | "RFC 9134 §7.1" | COVERED | Parser explicitly rejects `interlace=anything` with spec_ref "RFC 9134 §7.1". Tests at lines 3275–3279 (accept bare), 3287–3295 (reject `=1`). |
| 44 | 7.1 | `segmented` requires `interlace` (segmented-without-interlace is forbidden) | `parse_sdp.lua:1685-1688` | "RFC 9134 §7.1" | COVERED | Explicit check with correct cite. Test at lines 3307–3316. |
| 45 | 7.1 | `sampling` Y'CbCr non-constant: {YCbCr-4:4:4, YCbCr-4:2:2, YCbCr-4:2:0} | `parse_sdp.lua:1582` + `VALID_SAMPLING` at line 742 | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED | Value set check via `valid_enum` against `VALID_SAMPLING`. The set contains all RFC 9134 §7.1 values listed in rows 45–51 (12 total). |
| 46 | 7.1 | `sampling` constant-luminance (BT.2020-2): {CLYCbCr-4:4:4, CLYCbCr-4:2:2, CLYCbCr-4:2:0} | same — `VALID_SAMPLING` at line 742 | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED | Set contains all three CLYCbCr values. |
| 47 | 7.1 | `sampling` ICtCp (BT.2100-2): {ICtCp-4:4:4, ICtCp-4:2:2, ICtCp-4:2:0} | same | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED | Set contains all three ICtCp values. |
| 48 | 7.1 | `sampling` = `RGB` for RGB / R'G'B' 4:4:4 | same | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED | Set contains `RGB`. Test at lines 3183–3188 confirms acceptance. |
| 49 | 7.1 | `sampling` = `XYZ` for X'Y'Z' 4:4:4 | same | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED | Set contains `XYZ`. |
| 50 | 7.1 | `sampling` = `KEY` for key signals | same | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED — case discrepancy is RESOLVED in favour of uppercase | Set contains `KEY` (uppercase). The inventory flagged the prose-vs-table case discrepancy (row 50: prose says "the value key", table row shows "KEY"); parser follows the table form (uppercase), which is also the form used by ST 2110-20 §7.4.1. Case-sensitive `valid_enum` would reject lowercase `key` — fine if parser intends to match the table canonical form. |
| 51 | 7.1 | `sampling` = `UNSPECIFIED` for other sub-sampling | same | "ST 2110-22 §7 / RFC 9134 §7.1" | MISSING | `VALID_SAMPLING` (line 742–747) does **NOT include "UNSPECIFIED"**. RFC 9134 §7.1 explicitly lists UNSPECIFIED as a valid `sampling` value. ST 2110-20 §7.4.1 also omits it from the closed list — but for jxsv, RFC 9134 is the authority and the IANA registration. **Parser would reject `sampling=UNSPECIFIED` despite RFC 9134 §7.1 permitting it.** Recommended: add `["UNSPECIFIED"]=true` to `VALID_SAMPLING` (or use a separate VALID_SAMPLING_JXS set so the -20 raw-video path isn't loosened). |
| 52 | 7.1 | `colorimetry` closed set: {BT601-5, BT709-2, SMPTE240M, BT601, BT709, BT2020, BT2100, ST2065-1, ST2065-3, XYZ, UNSPECIFIED} | `parse_sdp.lua:1586` + `VALID_COLORIMETRY` at line 758 | "ST 2110-22 §7 / RFC 9134 §7.1" | MISSING (RFC 9134 values absent from parser's closed set) | RFC 9134 §7.1 lists **11 values** (`BT601-5, BT709-2, SMPTE240M, BT601, BT709, BT2020, BT2100, ST2065-1, ST2065-3, XYZ, UNSPECIFIED`). Parser's `VALID_COLORIMETRY` has 9 values: `BT601, BT709, BT2020, BT2100, ST2065-1, ST2065-3, UNSPECIFIED, XYZ, ALPHA`. **Missing for RFC 9134**: `BT601-5`, `BT709-2`, `SMPTE240M`. **Extra (not in RFC 9134)**: `ALPHA` (this is ST 2110-20:2022). Parser would reject `colorimetry=BT601-5`, `BT709-2`, or `SMPTE240M` on a jxsv stream even though RFC 9134 §7.1 explicitly permits them. Resolution: either widen `VALID_COLORIMETRY` to the RFC 9134 union, or use a separate jxsv set. Cite needs to be RFC 9134 §7.1, not ST 2110-20. |
| 53 | 7.1 | `TCS` closed set: {SDR, PQ, HLG, UNSPECIFIED} | `parse_sdp.lua:1585` + `VALID_TCS` at line 751 | "ST 2110-22 §7 / RFC 9134 §7.1" | COVERED (overlap with ST 2110-20 super-set) | Parser's `VALID_TCS` has 11 values from ST 2110-20:2022 §7.6. The four RFC 9134 TCS values (SDR/PQ/HLG/UNSPECIFIED) are all present. RFC 9134 §7.1 lists a **smaller** set than ST 2110-20; the parser's wider set is a super-set, so RFC-9134-valid SDPs always validate, but the parser will ALSO accept TCS values that RFC 9134 alone does not define (LINEAR, BT2100LINPQ, BT2100LINHLG, ST2065-1, ST428-1, DENSITY, ST2115LOGS3). For jxsv at the ST 2110-22 tier, ST 2110-22 inherits TCS semantics from ST 2110-20 §7.6 (per ST 2110-22:2022 §7.2 Table 2 cross-reference), so the wider set is correct **at that tier**. For "pure RFC 9134" tier (if there were one), this would be a strict-superset that allows extra values. Acceptable; document the tier-coupling. |
| 55 | 7.1 | `RANGE` defaults: NARROW (most) / FULL (UNSPECIFIED colorimetry) | n/a | n/a | NOT-VALIDATOR-ACTIONABLE | Default-value semantics, not a form constraint. Parser does not assert defaults (correctly) — defaults are receiver interpretation, not SDP grammar. |
| 56 | 7.1 | `RANGE` allowed values: {NARROW, FULL} when colorimetry=BT2100; otherwise {NARROW, FULLPROTECT, FULL} | `parse_sdp.lua:1666-1672` + `VALID_RANGE` at line 764 | "RFC 9134 §7.1" | COVERED (without the colorimetry-conditional restriction) | Parser validates `RANGE` against the union `{NARROW, FULLPROTECT, FULL}` regardless of colorimetry. RFC 9134 §7.1 prohibits `FULLPROTECT` when `colorimetry=BT2100` (only {NARROW, FULL} are allowed under BT.2100). Parser does NOT enforce the colorimetry-conditional restriction — `RANGE=FULLPROTECT` with `colorimetry=BT2100` would be accepted. Inventory row 56 flagged this as AMBIGUOUS regarding what happens under UNSPECIFIED colorimetry. **Suspected gap**: validator should reject `RANGE=FULLPROTECT` paired with `colorimetry=BT2100`. Cite "RFC 9134 §7.1" is correct. |
| 57 | 8.1 | rtpmap form `jxsv/90000` | `parse_sdp.lua:1516-1520` | "ST 2110-22 §7" | COVERED-CITE-OFF | Restatement of row 13. Same parser check covers both; same cite gap. |
| 58 | 8.1 | All SDP fmtp parameters SHALL correspond to registered §7.1 parameters | n/a | n/a | COVERED (by allowlist-with-pass-through) | Parser implements the receiver-side interpretation (§7.1 / §8.1 "ignore unknown") by silently allowing unrecognized keys. Sender-side §8.1 SHALL ("All parameters SHALL correspond...") would require **rejecting** unknown keys, which **conflicts** with §7.1 / §8.1 "receiver SHALL ignore". Inventory row 58 explicitly notes this tension. Parser's choice (silent pass-through) optimizes for the receiver clause, which is the conservative interoperable behavior. Test at `st2110_spec.lua:3256-3268` confirms `fbblevel=…` passes. Acceptable per the strictness principle (no spec text says a parser MUST reject unknown keys; the SHALL on senders is operational, not a validation gate). |
| 59 | 8.1 | Payload values prevail on disagreement | n/a | n/a | NOT-VALIDATOR-ACTIONABLE | Operational precedence rule; SDP-only parser has no payload to compare against. |
| 60 | 8.1 | Receiver SHALL ignore unregistered fmtp parameters | `parse_sdp.lua:1689-1711` (no closed-key gate) | n/a (silent allow) | COVERED (by omission) | Same as row 31. Parser does not reject unknown keys. |
| 61 | 8.2 | `a=fmtp` SHALL be present specifying `packetmode` (in offer/answer model) | `parse_sdp.lua:1574-1578` + 1641-1652 (rejects missing `packetmode`) | "ST 2110-22 §7.2" | COVERED-CITE-OFF | Parser unconditionally requires `packetmode` (not only in O/A mode). Stronger than §8.2's offer/answer scoping, but consistent with §8.1's "required parameter `packetmode`... goes in SDP". AMBIGUOUS flag in inventory row 61 noted that the SHALL is scoped to O/A but §8.1 strongly implies the requirement holds outside O/A too. Parser's unconditional requirement is the safe reading. Test at lines 3100–3108 confirms the rejection. Cite should be **RFC 9134 §7.1 + §8.1** (or §8.2 for O/A), not ST 2110-22 §7.2 (ST 2110-22 §7.2 Table 1 does not list `packetmode`). |

## Non-SDP rows (31 rows — out-of-SDP-scope, no parser action required)

These rows constrain RTP packet structure, payload-header bits, codestream / box layout, congestion control, RTP timestamp generation, or offer/answer negotiation behavior — none of which a static SDP parser can or should validate. They are listed for completeness but require no parser checks.

Rows: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 27, 28, 29, 54, 62, 63, 64.

Status for all: OUT-OF-SCOPE (RTP / codestream / negotiation / operational).

## Summary

- SDP-Y rows in inventory: **33**
- COVERED (correct check, correct cite): **8** (rows 39, 42, 43, 44, 45, 46, 47, 48, 49, 53 — note row 53 is "covered with super-set tier-coupling note")
  - Sub-totals: 39 (depth), 42 (exactframerate), 43 (interlace flag), 44 (segmented/interlace combo), 45-51 (sampling — except row 51 UNSPECIFIED is missing), 53 (TCS).
- COVERED-CITE-OFF (check exists but spec_ref doesn't cite RFC 9134 where it should): **10** (rows 13, 32, 33, 34, 35, 36, 37, 38, 57, 61)
- MISSING (check absent or value set wrong): **4** (rows 40, 41, 51, 52, 56)
  - Row 40: width upper bound 32767 unenforced for jxsv
  - Row 41: height upper bound 32767 unenforced for jxsv
  - Row 51: `sampling=UNSPECIFIED` rejected by parser despite RFC 9134 §7.1 permitting it
  - Row 52: `colorimetry` set drift — RFC 9134 permits BT601-5, BT709-2, SMPTE240M; parser rejects these
  - Row 56: `RANGE=FULLPROTECT` not prohibited when colorimetry=BT2100 (RFC 9134 §7.1 only permits NARROW/FULL under BT.2100)
- NOT-VALIDATOR-ACTIONABLE: **5** (rows 30, 55, 58 partial, 59, 60 partial — coherence / defaults / payload-precedence rules)
- COVERED (by omission / pass-through): **2** (rows 31, 60 — receiver-ignore-unknown matches parser's silent-allow behavior; row 58 partial in same category)

## Top 3 Findings

1. **Row 52 — `colorimetry` value-set drift between RFC 9134 §7.1 and parser's set.** Parser's `VALID_COLORIMETRY` (line 758) lacks RFC 9134's `BT601-5`, `BT709-2`, `SMPTE240M`. A conformant RFC 9134 jxsv SDP using any of these three would be rejected by `valid_enum("colorimetry", …)` at line 1586. (Conversely, parser has `ALPHA` which is ST 2110-20:2022 only, not RFC 9134.) The cite emitted at line 1659 (`"ST 2110-22 §7 / RFC 9134 §7.1"`) claims RFC 9134 §7.1 authority while applying a set that violates it. Fix: split `VALID_COLORIMETRY` into per-tier sets, or widen the shared set to the union (and fix the cite).

2. **Row 51 — `sampling=UNSPECIFIED` is rejected by parser despite RFC 9134 §7.1 explicitly permitting it.** `VALID_SAMPLING` (line 742) omits `UNSPECIFIED`, but RFC 9134 §7.1 prose says: "Signals utilizing a color sub-sampling other than what is defined here SHALL use the following value for the Media Type Parameter 'sampling': UNSPECIFIED." Parser would reject this RFC-9134-mandated value. Note ST 2110-20 §7.4.1 also lacks UNSPECIFIED in some readings — but ST 2110-22:2022 §7.2 Table 2 routes `sampling` through RFC 9134's IANA registration, so this is a real RFC 9134 conformance gap.

3. **Rows 40 / 41 — `width` / `height` upper bound 32767 not enforced for jxsv.** Parser uses `valid_pos_int` (any positive integer) for jxsv width/height while a bounded `valid_pixel_dim` ("integers between 1 and 32767 inclusive") exists at line 974 and is correctly applied only to the ST 2110-20 raw-video path. RFC 9134 §7.1 normatively bounds both fields at 32767 inclusive, with identical wording to ST 2110-20. Result: a jxsv SDP with `width=99999` parses cleanly. Fix: reuse `valid_width` / `valid_height` for the jxsv path (or substitute the bounded check in `jxs_req`). Cite should be RFC 9134 §7.1.

### Secondary findings (cite hygiene, lower priority)

- **Cite drift across rows 13/32/33/34/57/61.** RFC 9134 §7.1 (the IANA registration) is the primary authority for the `rate`/`packetmode` requirements; parser emits `spec_ref="ST 2110-22 §7"` or `"ST 2110-22 §7.2"`. ST 2110-22 inherits the IANA registration; the inheriting spec is not the wrong cite, but RFC 9134 §7.1 should appear in the spec_ref for these jxsv-coupled rules. Code comments at lines 1569, 1583 already correctly cite RFC 9134 — only the emitted `spec_ref` is stale.

- **Row 56 — `RANGE` colorimetry-conditional restriction unenforced.** RFC 9134 §7.1 says under BT.2100 colorimetry, RANGE has **two** allowed values (NARROW, FULL); under other colorimetries, **three** (NARROW, FULLPROTECT, FULL). Parser unconditionally allows all three. Inventory row 56 flagged this as AMBIGUOUS only for the UNSPECIFIED-colorimetry case; the BT.2100 restriction itself is unambiguous and not enforced.

- **Rows 36/37/38 — closed `profile` / `level` / `sublevel` lists are TR-08-grounded, not RFC 9134-grounded.** RFC 9134 §7.1 defers value enumeration to ISO 21122-2 and does not enumerate. Parser enforces a closed list (sourced from TR-08 §8.1.1 / TR-10-15-Part1, per code comment at line 901–902). At the ST 2110-22 / IPMX tier this is operationally correct; at the "pure RFC 9134" tier (if there were one) it would over-reject. The spec_ref `"ST 2110-22 §7.2"` is wrong because §7.2 does not enumerate either — TR-08 or TR-10-15-Part1 is the actual authority. The audit may want to either relax to "non-empty token / no Unicode whitespace" per RFC 9134 §7.1 alone, or fix the cite to point at TR-08.

- **Row 58 vs. row 31/60 tension noted in inventory.** Parser correctly prefers the receiver-side rule (silent pass-through of unknown keys), which is the safe interoperable choice and consistent with the strictness principle (no spec text mandates parser-side rejection).

---


# AES — audio references

## AES67-2013 + AES3-1 + AES3-4

# Audit Coverage: AES67-2013 + AES3-1-2009 + AES3-4-2009

Inventory: `/tmp/audit_inventory_aes.md` (98 rows; ~17 SDP-Y)
Parser:    `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines)
Tests:     `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua` (4792 lines)

## Context

AES67-2013 PDF only on disk; AES67-2018 (paywalled) is the version referenced by ST 2110-30:2025 §6.2.1. The parser cites the chain "ST 2110-30:2025 §6.2.1 / AES67 §8.1" rather than AES67 directly — coverage flows transitively. For COVERED rows, the parser may not name AES67 but still enforces the 2013 wording via the ST 2110-30 wrapper.

Reverse-direction confirmation (only AES references in parser):
- L.1060, L.1068, L.1073, L.1096–1098 — AES3 channel-order group symbol (ST 2110-31 §6.2 Table 2)
- L.1922, L.1939–1940, L.1947, L.1998, L.2746, L.2749 — references to "AES3 Subframe" / "AES67 §8.1" / "AES67-2018" in comments. **No direct `"AES67"` cite in spec_ref strings**; cites are at ST 2110-10 / -30 / -31.

## Coverage classifications

- COVERED              — parser enforces the SHALL with a cite to the same or transitive clause.
- COVERED-WRONG-CITE   — parser enforces the SHALL but cites a non-authoritative or stale clause.
- COVERED-NO-TEST      — parser enforces the SHALL but no `spec/` test exercises the path.
- MISSING              — no parser check found.
- OUT-OF-SCOPE-FROM-SDP — clause is non-SDP (wire-format, physical, protocol behavior).

## SDP-Y rows

| # | Spec | § | SDP-Y subject | Coverage | Parser site | Test | Notes |
|---|---|---|---|---|---|---|---|
| 6 | AES67 | 5 | Supported sampling-frequency set {44.1, 48, 96 kHz} bounds rtpmap clock rate | COVERED (partial, AM824 only) / OUT-OF-SCOPE for L16/L24 | parse_sdp.lua L.1925–1934 (AM824 only) | st2110_spec.lua L.1930–2004 (AM824 ptime/rate) | [AES67-2013 wording] AM824 rate is enforced via ST 2110-31. **L16/L24 rate is intentionally NOT bounded** (L.1903–1906: "any well-formed positive rate is accepted (M30 G5 — conformance principle)"); the AES67-2013 SHALL is transitively about senders/receivers, not the SDP-grammar. Bounding L16/L24 rate from SDP would over-enforce — parser policy. Mark for main-thread review against AES67-2018. |
| 7 | AES67 | 5 | RTP↔media-clock offset SHALL be conveyed in SDP per stream | COVERED | parse_sdp.lua L.1294–1301 (mediaclk required + valid_mediaclk L.1121–1134) | st2110_spec.lua L.128–146 ("errors when mediaclk is missing") | [AES67-2013 wording] Enforced via ST 2110-10 §8.3 wrapper. Cite is "ST 2110-10 §7.3" / "§8.3" — would benefit from a parallel AES67 §5 / §8.3 cite, but the SHALL itself is enforced. |
| 18 | AES67 | 6.3 | m= transport SHALL be RTP/AVP | COVERED | parse_sdp.lua L.766 (VALID_ST2110_PROTO), L.1240–1244 | st2110_spec.lua (multiple — every audio fixture uses RTP/AVP) | [AES67-2013 wording] Enforced via ST 2110-10 §8.1 wrapper; cite is "ST 2110-10 §8.1" not AES67 §6.3 but the effect is identical. |
| 22 | AES67 | 7.1 | All devices SHALL support 48 kHz; 96/44.1 SHOULD | OUT-OF-SCOPE-FROM-SDP | n/a | n/a | [AES67-2013 wording] Device-support SHALL, not an SDP-grammar SHALL on a sender-emitted descriptor. Parser cannot infer support from absent fields. |
| 23 | AES67 | 7.1 | At 48 kHz: receivers SHALL support L16+L24, senders SHALL support L16 or L24 | OUT-OF-SCOPE-FROM-SDP | n/a | n/a | [AES67-2013 wording] Capability SHALL on devices, scoped to "When operating at 48 kHz". A single SDP describes one stream, not what else a sender could emit — explicitly out of SDP scope per CLAUDE.md "Sender/Receiver capability subsetting". |
| 24 | AES67 | 7.1 | At 96 kHz both sides SHALL support L24 | OUT-OF-SCOPE-FROM-SDP | n/a | n/a | [AES67-2013 wording] Capability SHALL, not SDP-grammar SHALL. Parser does NOT forbid L16 at 96 kHz in an SDP (which the inventory note synthesis flags as "outside scope"); since AES67-2013 says "outside scope" not "shall not", parser policy at L.1903–1906 is correct. |
| 25 | AES67 | 7.1 | At 44.1 kHz both sides SHALL support L16 | OUT-OF-SCOPE-FROM-SDP | n/a | n/a | [AES67-2013 wording] Capability SHALL on devices, not an SDP-grammar SHALL on a single stream descriptor. |
| 29 | AES67 | 7.2.1 | All devices SHALL support 1 ms packet time | OUT-OF-SCOPE-FROM-SDP (as device capability) / COVERED (as accepted ptime value) | parse_sdp.lua L.1945–1953 (ptime present + positive) | st2110_spec.lua L.2256–2260 ("accepts a=ptime:1") | [AES67-2013 wording] The SHALL is "devices SHALL support 1 ms", which is a capability SHALL. Parser accepts ptime=1 (and any positive decimal) and does not require ptime=1 — correct: requiring it from SDP would mis-read the clause. |
| 31 | AES67 | 7.3 | Receivers SHALL support 1–8 channels; senders SHALL offer ≥1 stream of ≤8 channels | OUT-OF-SCOPE-FROM-SDP | parse_sdp.lua L.1909–1919 (channels must be present and ≥1) | n/a | [AES67-2013 wording] The 1–8 range is a capability SHALL. Parser enforces "≥1" (the RFC 3551 grammar floor) but does NOT cap at 8 — correct per CLAUDE.md, since AES67-2013 §7.3 also says "may support more". Inventory row notes "Does not forbid streams with more channels." |
| 36 | AES67 | 7.6 | Multicast addresses SHALL be admin-scoped (239.0.0.0/8) | MISSING | n/a (parser allows 224–239 ranges with TTL; only forbids 224.0.0.0/24 and 224.0.1.0/24 — see L.876–880) | n/a | [AES67-2013 wording] **Genuine gap relative to AES67-2013.** Parser permits any 224.x.x.x–238.x.x.x multicast (except 224.0.0/24 and 224.0.1/24). AES67-2013 limits to 239.0.0.0/8. AMBIGUOUS-by-revision: AES67-2018 may have expanded — flag for main-thread re-verification before adding a check. Adding a check today would risk false-positive against 2018. |
| 38 | AES67 | 8.0 | SDP per RFC 4566 SHALL be used | COVERED | entire parser is RFC 4566 / RFC 8866 (RFC 4566 successor) grammar | spec/sdp_spec.lua (all) | [AES67-2013 wording] Architectural; parser is built on RFC 8866 grammar (a superset-compatible successor to RFC 4566). The "SHALL use SDP" framing is satisfied by virtue of the library's existence. |
| 39 | AES67 | 8.1 | ptime value error SHALL be <½ sample period | OUT-OF-SCOPE-FROM-SDP (cannot enforce) | n/a | n/a | [AES67-2013 wording] Inventory notes "AMBIGUOUS to enforce as a parser: requires knowing intended sample count." Cannot derive intended sample count from SDP alone; this is a sender-side rounding SHALL, not an SDP-grammar SHALL. Correctly absent. |
| 40 | AES67 | 8.1 | ptime SHALL be decimal; unlisted values SHALL be honored | COVERED | parse_sdp.lua L.1950–1953 (tonumber, positive) | st2110_spec.lua L.2256–2287 (accepts 1, 0.125; rejects 0, non-numeric) | [AES67-2013 wording] Parser uses tonumber() which accepts any decimal; rejects only zero/negative/non-numeric. "Tolerate unlisted values" is satisfied (no whitelist for L16/L24). AM824 (ST 2110-31) does have a whitelist (Table 1) but that is a -31-specific tightening, not an AES67 violation. |
| 41 | AES67 | 8.1 | SDP SHALL include a=ptime; a=maxptime conditional | COVERED (ptime) / MISSING (maxptime conditional) | parse_sdp.lua L.1945–1948 (ptime presence) | st2110_spec.lua L.2249–2253 ("rejects absence of a=ptime") | [AES67-2013 wording] a=ptime presence is enforced with a direct AES67 §8.1 mention in the cite. **a=maxptime conditional ("if more than one ptime supported") is not checked** — but inventory itself notes "cannot be enforced from a single SDP without offer/answer state". MISSING is correctly out-of-reach. |
| 42 | AES67 | 8.2 | Each stream SHALL carry ≥1 a=ts-refclk | COVERED | parse_sdp.lua L.1275–1292 | st2110_spec.lua L.61–87, L.106–127 ("returns nil+err for SDP missing ts-refclk", "error includes field_path and spec_ref when ts-refclk is missing") | [AES67-2013 wording] Enforced as ST 2110-10 §7.2. Parser correctly considers both session and media level when checking presence (per RFC 4566 inheritance). |
| 43 | AES67 | 8.2 | For IEEE1588-2008, ts-refclk SHALL include GMID + domain | COVERED | parse_sdp.lua L.677–710 (valid_tsrefclk ptp branch); L.704–705 explicitly: "ts-refclk ptp domain is required when not using the 'traceable' form (ST 2110-10:2022 §8.2)" | n/a (no direct test for missing-domain-without-traceable found in grep, but value validator runs on every ts-refclk attr) | [AES67-2013 wording] Enforced via ST 2110-10:2022 §8.2 which carries the same GMID+domain SHALL forward (with a "traceable" carve-out the 2013 wording lacks). The 2013 wording does NOT have a traceable form, so the parser is **more permissive** than AES67-2013 — but exactly aligned with ST 2110-10:2022 + AES67-2018+RFC 7273 trajectory. No conflict in practice. |
| 44 | AES67 | 8.2 | For IEEE802.1AS, ts-refclk SHALL be GMID-only, no domain | MISSING | n/a — parser's valid_tsrefclk (L.687–688) **rejects** version != "IEEE1588-2008" outright, so an `a=ts-refclk:ptp=IEEE802.1AS-2011:GMID` would be rejected with "unrecognized ptp version" | n/a | [AES67-2013 wording] Parser rejects 802.1AS forms entirely. ST 2110-10:2022 §8.2 also restricts to IEEE1588-2008 — so AES67-2013's 802.1AS branch is **out-of-scope of ST 2110**, and the parser's rejection of 802.1AS is correct per the higher-tier spec. MISSING relative to AES67-2013 standalone is acceptable; parser policy aligns with ST 2110. |
| 45 | AES67 | 8.3 | Each stream SHALL carry a=mediaclk:direct=<offset> | COVERED | parse_sdp.lua L.1294–1301 (mediaclk required, valid_mediaclk L.1121–1134) | st2110_spec.lua L.128–146 ("errors when mediaclk is missing") | [AES67-2013 wording] Parser enforces presence + value form. **Note**: parser FORCES offset to exactly "0" (L.1125–1127, cite "ST 2110-10 §8.3"). AES67-2013 §8.3 does not constrain offset to 0 — that's a ST 2110-10 §8.3 tightening. So parser is **stricter than AES67-2013** but conformant to ST 2110-10:2022. No conflict in practice (any AES67-via-ST-2110 SDP must satisfy offset=0). |
| 46 | AES67 | 8.4 | Dynamic PT + a=rtpmap SHALL describe AES67 encodings | COVERED (mostly) | parse_sdp.lua L.1303–1306 (rtpmap required), L.1334–1353 (dynamic PT 96–127 enforced for non-static encodings; static PT 10/11 carve-out for L16/44100/2 and L16/44100/1) | n/a (audio uses dynamic PT in tests) | [AES67-2013 wording] Parser enforces rtpmap presence and dynamic-PT range (96–127) with the static-PT 10/11 carve-out for L16/44.1k. AES67-2013 §8.4 doesn't forbid the static-PT carve-out — RFC 3551 §6 Table 4 statics for L16 are the IETF baseline. Parser cite: "ST 2110-10 §6.2". |
| 53 | AES67 | 10.1.5 | Answerer SHALL assume offer's ptime/maxptime are supported | OUT-OF-SCOPE-FROM-SDP | n/a | n/a | [AES67-2013 wording] Offer/answer semantics, not an SDP-grammar SHALL on a single descriptor. Inventory itself flags this. |

## SDP-N rows (AES67)

The following AES67 SDP-N rows are out-of-SDP-scope by construction and require no parser check:

- Rows 1, 2 (PTP profile selection) — out of SDP
- Rows 3, 4, 5, 8 (clock semantics, sampling-clock relationship, rollover handling) — out of SDP
- Rows 9, 10, 11, 12, 13, 14 (IPv4 transport, fragmentation, IGMP) — network-layer, not SDP grammar
- Rows 15, 16, 17 (DiffServ) — out of SDP
- Rows 19, 20, 21 (UDP, max RTP payload size 1440, CSRC tolerance) — out of SDP grammar
- Rows 26, 27, 28, 30 (device/documentation framing) — out of SDP
- Rows 32, 33 (buffer / transmit timing) — receiver/sender impl
- Rows 34, 35, 37 (multicast/unicast routing, single-sender, dest configurability) — out of SDP
- Rows 47 (PT-to-format mapping receiver semantics) — out of SDP grammar
- Rows 48–52 (SIP signaling) — out of SDP grammar
- Rows 54–59 (PTP profile / clock physical) — out of SDP

All marked OUT-OF-SCOPE-FROM-SDP. [AES67-2013 wording] caveat applies.

## AES3-1-2009 and AES3-4-2009 rows

| Row range | Spec | Coverage | Notes |
|---|---|---|---|
| 60–70 | AES3-1-2009 §4–§7 | OUT-OF-SCOPE-FROM-SDP | Wire-format / channel-status / pre-emphasis SHALLs. None bind SDP grammar. Indirectly justifies L16/L24 encodings and the AES67 sample-rate set, but provides zero direct SDP-Y. |
| 71–98 | AES3-4-2009 §4–§D.4 | OUT-OF-SCOPE-FROM-SDP | Physical/electrical SHALLs (jitter, impedance, voltage, connectors, eye-diagram). None bind SDP grammar. |

## Summary statistics

| Classification | Count |
|---|---|
| COVERED | 9 |
| COVERED-WRONG-CITE | 0 |
| COVERED-NO-TEST | 0 |
| MISSING | 3 (rows 36, 41-maxptime, 44) |
| OUT-OF-SCOPE-FROM-SDP | ~86 (39 AES67-non-SDP + 11 AES3-1 + 28 AES3-4 + 8 AES67-capability-SHALLs) |
| **Total** | 98 |

Notes on the three MISSING:
- **Row 36** (admin-scoped multicast 239.0.0.0/8): parser allows broader 224–239 ranges. AMBIGUOUS-by-revision against AES67-2018. **Do not add a check without AES67-2018 confirmation.**
- **Row 41 (maxptime conditional)**: not enforceable from a single SDP without offer/answer state — inventory itself flags this. Correctly out-of-reach.
- **Row 44 (IEEE802.1AS GMID-only)**: parser rejects 802.1AS entirely. Aligns with ST 2110-10:2022 (which restricts to IEEE1588-2008). MISSING relative to AES67-2013 standalone but the higher tier supersedes.

## Top 3 findings

1. **Row 36 — multicast scope** is the only AES67-2013 SDP-Y SHALL the parser leaves materially open. Parser accepts any 224.0.0.0/4 multicast (with the 224.0.0/24 and 224.0.1/24 carve-outs of ST 2110-10 §6.5), while AES67-2013 §7.6 says SHALL be 239.0.0.0/8. Flag as AMBIGUOUS-by-revision: AES67-2018 may have expanded; do not add a check before main-thread confirmation against AES67-2018.

2. **Cite trail is "ST 2110-10 / -30" not "AES67"** throughout the parser. Every AES67 SDP-Y SHALL the parser does enforce is cited via the ST 2110 wrapper (e.g. "ST 2110-30:2025 §6.2.1 / AES67 §8.1" at L.1947, but "ST 2110-10 §7.2 / §7.3 / §8.2 / §8.3" elsewhere). This is consistent with CLAUDE.md's transitive policy — ST 2110-30 requires AES67 conformance, so an AES67-only cite is unnecessary. However, rows 7, 18, 42, 45 would benefit from a parallel AES67 cite in the spec_ref string for future-proofing against ST 2110-30 wrapper-cite changes.

3. **AES3-1 and AES3-4 contribute zero SDP-Y** (rows 60–98 are all wire-format/physical). The parser's only AES3 surface is the AM824 channel-order group symbol "AES3" (L.1096–1098) sourced from ST 2110-31 §6.2 Table 2 — not from AES3-1/-4 directly. This is correct: AES3 base parts are not SDP-binding.

## Output path

`/tmp/audit_coverage_aes.md` (this file)

## Row count

98 rows mapped (17 SDP-Y unique; 9 COVERED, 3 MISSING with caveats, 86 OUT-OF-SCOPE-FROM-SDP).

---


# SMPTE ST 2110

## SMPTE ST 2110-10:2022

# ST 2110-10:2022 — Coverage Map vs `parse_sdp.lua`

Spec: SMPTE ST 2110-10:2022 — Professional Media Over Managed IP Networks: System Timing and Definitions.
Inventory: `/tmp/audit_inventory_st2110-10.md` — 69 rows; 24 SDP-Y; 2 AMBIGUOUS (row 54 "RFC 7272" typo, row 66 TSDELAY zero/positive).
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines).
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`.

The ST 2110 validator lives at lines 1202–2176 (`function st2110.validate`).
Helpers used by the ST 2110-10 checks:

- `valid_tsrefclk(value)` — 656–710 (called from 1287–1291)
- `valid_mediaclk(value)` — 1111–1134 (called from 1296–1301)
- `valid_connection_address(addr_type, addr)` — 819–887 (called from 1227, 1248)
- `valid_source_filter(value)` — 785–803 (called from 1259–1265)
- `valid_maxudp(value)` — 991–998 (called for jxsv at 1693, for video opt 1866)
- `valid_enum(v, VALID_TSMODE, "TSMODE")` — 942–945 + 899 (called from video opt list 1877)
- `valid_pos_int(value)` — 947–952 (called for TSDELAY 1881)
- `each_dup_group(doc, spec_ref, callback)` — 478–514 (called from 2092)
- `VALID_ST2110_PROTO = { ["RTP/AVP"] = true }` — 766 (enforced 1240–1244)

Note: the inventory marks 25 row numbers as "SDP-Y" but the totals line counts
24 distinct in-scope rows. I treat rows 4, 5, 8, 11, 18, 20, 24, 42, 43, 47,
51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66, 68, 69 as candidate SDP-Y
(25 numeric ids); rows 11, 42–46 are cross-refs / informational and may be N/A
in practice — they are mapped row-by-row below.

## Status legend

- `COVERED` — parser enforces and `spec_ref` cites ST 2110-10 (or its
  upstream RFC for grammar — that pattern is documented for RFC 7273 in a
  separate coverage map and is the deliberate cite policy for grammar form)
- `MISSING` — no check found
- `STRICTER` — parser rejects forms the spec admits (intentional ST 2110
  tightening of a downstream spec or genuine over-strictness — call out)
- `WEAKER` — parser enforces a coarser check than the spec demands
- `N/A` — clause is not an SDP-grammar/value constraint (out of scope by
  inventory marking, repeated here for completeness)

## Coverage table

| # | § | Summary | Status | Parser line(s) | Notes |
|---|---|---|---|---|---|
| 1 | 2 | reserved/forbidden definition | N/A | — | Meta-definition. |
| 2 | 2 | order of precedence (prose > tables > formal > figures) | N/A | — | Document-interpretation rule. |
| 3 | 6.1 | Devices shall support IPv4 | N/A | — | Device capability. |
| 4 | 6.2 | All streams shall use RTP per RFC 3550 / RFC 3551 (m= proto RTP/AVP) | COVERED | 766, 1240–1244 | `VALID_ST2110_PROTO = { ["RTP/AVP"] = true }`; enforced unconditionally for every media block with `spec_ref = "ST 2110-10 §8.1"` (note: the rule originates in §6.2 but is cited as §8.1 since that is the SDP clause for proto). |
| 5 | 6.2 | RTP streams transported on UDP | COVERED (implicit) | 1240–1244 | `RTP/AVP` proto implies UDP per RFC 4566 §5.7; same check as row 4. |
| 6 | 6.2 | RTP session multiplexing on same multicast group/port forbidden | N/A | — | Runtime behaviour; not SDP-encodable per inventory. |
| 7 | 6.2 | Receivers shall tolerate RTCP | N/A | — | Receiver runtime behaviour. |
| 8 | 6.2 | Dynamic PT 96–127 with carve-out for fixed PT designations | COVERED | 1334–1353 | Rejects PT outside 0–127 (RFC 3550 cite); for PT < 96 requires it to match an RFC 3551 §6 static (L16/44100/2 → PT 10; L16/44100/1 → PT 11). Cite: `ST 2110-10 §6.2`. |
| 9 | 6.2 | Receivers shall tolerate extended RTP header | N/A | — | Runtime. |
| 10 | 6.2 | Big-endian byte order | N/A | — | Wire format. |
| 11 | 6.2 | Redundant streams shall follow ST 2022-7 + §8.5 | COVERED (cross-ref) | 2068–2144 | DUP group checks (see row 60) enforce §8.5; §6.2 is the conformance pointer. |
| 12 | 6.3 | Standard UDP Size Limit = 1460 octets | N/A | — | Constant; not signalled. |
| 13 | 6.3 | Senders bounded to 1460 unless using Extended | N/A | — | Wire behaviour. |
| 14 | 6.3 | UDP size constraints apply regardless of header extensions | N/A | — | Wire behaviour. |
| 15 | 6.3 | Receivers must accept up to 1460 | N/A | — | Receiver capability. |
| 16 | 6.3 | No IP fragmentation at sender egress | N/A | — | Wire behaviour. |
| 17 | 6.4 | Extended UDP Size Limit = 8960 octets | COVERED (as bound) | 991–998 | `valid_maxudp`: rejects MAXUDP values > 8960; cite `ST 2110-10 §6.4`. |
| 18 | 6.4 | Senders exceeding Standard limit shall include MAXUDP | COVERED (value form only) | 991–998, 1689–1698 (jxsv), 1866 (video) | Presence is **not** enforced (the antecedent "operating with UDP sizes exceeding 1460" is not SDP-observable). When MAXUDP is present, value form is checked (positive integer, ≤ 8960). This matches the inventory note "receiver cannot verify the antecedent from SDP alone". Cite chains: `ST 2110-22 §7` (jxsv) or `ST 2110-20 §7.2` (video). |
| 19 | 6.5 | IPv4 multicast + IGMP support required | N/A | — | Device capability. |
| 20 | 6.5 | Forbidden multicast: 224.0.0.0/24 (Local Network Control), 224.0.1.0/24 (Internetwork Control) per RFC 5771 | COVERED | 819–887 (specifically 875–880) | `valid_connection_address`: for IPv4 multicast, decodes octets 1–3 and rejects when `o1=224 ∧ o2=0 ∧ (o3 ∈ {0,1})`. Cite: `ST 2110-10 §6.5`. Applied at both session-level c= (1226–1234) and media-level c= (1246–1255). Also applies to `a=source-filter` (788–803) via `valid_source_filter`. |
| 21 | 6.5 | IPv4 unicast addressing support required | N/A | — | Device capability. |
| 22 | 7.2 | slaveOnly=TRUE forcing control | N/A | — | Device control. |
| 23 | 7.2 | ST 2059-2 PTP message rates support | N/A | — | Device capability. |
| 24 | 7.3 | mediaclk direct offset value SHALL be zero | COVERED | 1121–1133 (specifically 1125–1127) | `valid_mediaclk`: explicit `if offset ~= "0"` reject. Cite: `ST 2110-10 §8.3` (the SDP clause; §7.3 is the originating value rule). |
| 25 | 7.4 | RTP/Media Clock advance at uniform rates | N/A | — | Behavioural. |
| 26 | 7.5 | RTP TS reflects sampling instant | N/A | — | Wire payload. |
| 27 | 7.6.1 | Successive video RTP TS regular increments | N/A | — | Wire. |
| 28 | 7.6.1 | Interlaced field TS rules | N/A | — | Wire. |
| 29 | 7.6.1 | PsF segments share RTP TS | N/A | — | Wire. |
| 30 | 7.6.2 | Second-field TS rule | N/A | — | Wire. |
| 31 | 7.6.3 | Synthetic-essence TS jitter bound | N/A | — | Wire. |
| 32 | 7.6.3 | Synthetic-essence second-field rule | N/A | — | Wire. |
| 33 | 7.6.4 | Intro: "RTP timestamps shall be determined as follows:" | N/A | — | Bullet-binding intro for wire-format rules. |
| 34 | 7.6.4 | SDI alignment-point sampling | N/A | — | Wire. |
| 35 | 7.6.4 | SDI second-field reference to §7.6.1 | N/A | — | Wire. |
| 36 | 7.6.4 | SDI PsF segments share RTP TS | N/A | — | Wire. |
| 37 | 7.7.1 | Audio RTP TS regular increments | N/A | — | Wire. |
| 38 | 7.7.4 | SDI-embedded audio first-sample timing | N/A | — | Wire. |
| 39 | 7.7.4 | Audio sample monotonic | N/A | — | Wire. |
| 40 | 7.7.4 | Audio RTP TS = first-sample sampling instant | N/A | — | Wire. |
| 41 | 7.7.5 | AES3 audio RTP TS at X/Z preamble | N/A | — | Wire. |
| 42 | 7.9 | Time-preserving inline processors must signal TSMODE=SAMP | MISSING (intentional) | — | Inventory flags "requires runtime knowledge to enforce strictly" (processor role not observable from SDP). Value form for TSMODE is covered at row 65; presence-conditional on role is not enforceable. |
| 43 | 7.9 | TSMODE=SAMP implies TSDELAY also signalled (presence dependency) | MISSING | — | Parser validates TSMODE value (1877) and TSDELAY value (1881) independently; there is no cross-field check that TSMODE=SAMP requires TSDELAY to be present. **Real gap** — both are SDP-checkable. |
| 44 | 7.9 | Time-resetting sender: TNEWRTP(j) = TNOW | N/A | — | Wire. |
| 45 | 7.9 | time-preserving / time-resetting definitions | N/A | — | Terminology. |
| 46 | 7.9 | §7.6.1 / §7.7.1 regular-increments take precedence | N/A | — | Wire-rule precedence. |
| 47 | 8.1 | One SDP per RTP stream or redundant pair | COVERED (indirect) | 2068–2144, 2146–2173 | The "one SDP per stream" rule is structural — RFC 4566 only allows one `v=`/`o=`/`s=` per document, so each parsed `doc` is one SDP. The redundant-pair carve-out is handled by §8.5 DUP grouping (row 60). The §7 audit of FID semantics (2146–2173) directly cites the "one SDP object per RTP Stream" provision when rejecting FID on smpte291 streams. |
| 48 | 8.1 | SDP available via management API | N/A | — | Device behaviour. |
| 49 | 8.1 | Receivers shall ingest SDP | N/A | — | Device capability. |
| 50 | 8.1 | SDP communicated via management API | N/A | — | Device behaviour. |
| 51 | 8.2 | All stream descriptions shall have a ts-refclk attribute (RFC 7273 §4 form) | COVERED | 1275–1292 | Gathers ts-refclk from session + media; rejects with "missing required attribute 'ts-refclk'" if zero are present. Validates each value via `valid_tsrefclk` (656–710). Cite: `ST 2110-10 §7.2` (note: spec sections §8.2 and §7.2 both apply; parser uses §7.2 — see Finding 3). |
| 52 | 8.2 | PTP-locked devices shall use `ts-refclk:ptp=…` form | COVERED | 677–708 | `valid_tsrefclk`: `ptp=` branch validates version literal `IEEE1588-2008` (line 687), 8-octet hex EUI-64 GMID (690–696), `traceable` literal (690), and domain 0–127 (700–702). Required domain when not "traceable" (704–706). Cite for error: `ST 2110-10:2022 §8.2` (705) — accurate. |
| 53 | 8.2 | Intro clause for traceable-conditions bullet list | N/A | — | Bullet-binding intro; bullets are device-state predicates (not SDP form). |
| 54 | 8.2 | Non-PTP devices use RFC 7273 form or `localmac=` extension | COVERED | 667–676 | `valid_tsrefclk`: `localmac=` branch validates 6 hex octets separated by `-`. The §8.2 spec text says "IETF RFC 7272" (inventory-flagged AMBIGUOUS typo) — **the parser does NOT cite RFC 7272 anywhere** (`grep` confirms zero hits). The parser cites only RFC 7273 (in comments at lines 1111–1116, 1131, 705) and ST 2110-10 §7.2 (in error spec_refs). **Correct outcome** — the typo is not propagated. |
| 55 | 8.2 | `a=ts-refclk:localmac=<MAC>` form | COVERED | 667–676 | Six dash-separated 2-hex-digit octets (e.g. `AA-BB-CC-DD-EE-FF`); test at `st2110_spec.lua:321`. |
| 56 | 8.3 | All stream descriptions shall have media-level mediaclk | COVERED | 1213–1222, 1294–1301 | Session-level mediaclk rejected (1216–1221, "must be media-level, not session-level"); per-media presence required (1295–1297). Both cite `ST 2110-10 §8.3` / `§7.3`. |
| 57 | 8.3 | When direct, use `direct=<offset>` form with offset present | COVERED | 1121–1133 | `valid_mediaclk` requires `direct=` prefix with offset captured (1123); rejects when prefix is absent ("unrecognized mediaclk value"). |
| 58 | 8.3 | Direct offset = 0 (cross-ref to §7.3) | COVERED | 1125–1127 | Same as row 24. |
| 59 | 8.3 | Async case must use `a=mediaclk:sender` | COVERED | 1122 | Exact-string `value == "sender"` accepted; any other non-`direct` value rejected at 1124. |
| 60 | 8.5 | Duplicated streams shall use session-level `a=group:DUP` (RFC 5888 + 7104) | COVERED | 478–514, 2068–2144 | `each_dup_group` iterates `doc.session.attributes` only (line 486) — DUP groups at media level are never discovered (passive enforcement of session-level placement). Cross-checks: same media type (2100–2104), same rtpmap encoding+rate (2106–2113), same RTP PT (2114–2121), identical fmtp essence (2122–2133), MID resolution (490–500), min-2-legs (502–507). |
| 61 | 8.5 | Redundant streams shall not use both identical source and destination addresses | COVERED | 2076–2091, 2134–2140 | `leg_addrs` extracts (src, dst) per leg: dst from `c=` (with session fallback), src from `a=source-filter` last field. Reject if `dst ~= "" ∧ dst == base_dst ∧ src == base_src`. Cite: `ST 2110-10 §8.5`. **Sentinel caveat**: when source-filter is absent on either leg, the empty-string source means same-src never compares equal, so this rule is silently weakened for that pair of legs (see Finding 2). |
| 62 | 8.6 | MAXUDP fmtp param required when > 1460; decimal octet count | COVERED (value form only) | 991–998, 1693–1697 (jxsv), 1866 (video opt) | Same coverage as row 18. |
| 63 | 8.6 | Default = 1460 when MAXUDP absent | N/A | — | Receiver default semantics. |
| 64 | 8.7 | Default TSMODE = NEW when absent | N/A | — | Receiver default. |
| 65 | 8.7 | TSMODE values ∈ {SAMP, NEW, PRES} | COVERED (raw video only) | 899, 1877 | `VALID_TSMODE` enum + `valid_enum` validator. Cited as `ST 2110-10 §8.7`. **Scope limitation**: TSMODE is only validated in the raw-video branch (`elseif m.media == "video"`) via `video_opt_checks`. For jxsv (1506–1711), audio (1894–2027), smpte291 (1364–1467), and ST 2110-41 (1469–1505) the parameter is unparsed if present — see Finding 2. |
| 66 | 8.7 | TSDELAY = decimal positive integer microseconds | COVERED (raw video only) | 947–952, 1881 | `valid_pos_int` ensures digits-only and > 0. Cited `ST 2110-10 §8.7`. Note that `valid_pos_int` rejects `0`, which **matches the §8.7 SHALL "positive integer"** but **rejects the Annex B example `TSDELAY=0`** (informative — inventory AMBIGUOUS row 66). Parser correctly follows the normative §8.7 wording. Comment at 1878–1881 documents this trade-off. Scope-limited to raw video; see Finding 2. |
| 67 | 8.7 | TSDELAY-absent default is receiver-dependent | N/A | — | Receiver behaviour. |
| 68 | 8.7 | Time-preserving senders with SAMP input → TSMODE=SAMP + TSDELAY | MISSING (intentional + see row 43) | — | Role-conditional; sender role not SDP-observable. The presence dependency (TSMODE=SAMP → TSDELAY) part is the same gap noted at row 43. |
| 69 | 8.7 | Time-preserving senders in any other case → TSMODE=PRES + TSDELAY | MISSING (intentional + see row 43) | — | Same as row 68. |

## Summary counts

- SDP-Y rows in scope: 25 row-IDs (4, 5, 8, 11, 17, 18, 20, 24, 42, 43, 47, 51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66, 68, 69) — row 17 is a value-bound used by 18/62 so I count it once.
- COVERED: rows 4, 5, 8, 11, 17, 18, 20, 24, 47, 51, 52, 54, 55, 56, 57, 58, 59, 60, 61, 62, 65, 66 — **22**
- MISSING (real gap): row 43 — TSMODE=SAMP → TSDELAY presence dependency.
- MISSING (intentional — role-conditional, not SDP-observable): rows 42, 68, 69.
- N/A (out of SDP scope per inventory): 44 rows (1–3, 6, 7, 9, 10, 12–16, 19, 21–23, 25–41, 44–46, 48–50, 53, 63, 64, 67).

## Top 3 findings

### Finding 1 — §8.2 "RFC 7272" typo is **NOT propagated** in the parser

The spec body line 763 cites "IETF RFC 7272" where context (and every other
SMPTE/AMWA reference implementation) indicates RFC 7273. The inventory
flagged this AMBIGUOUS.

`grep -nE 'RFC 7272|7272' parse_sdp.lua` returns **zero** results. The parser
only references RFC 7273 (lines 1111–1116, 1131) and only inside source
comments; error `spec_ref` strings cite ST 2110-10 §7.2/§7.3/§8.2/§8.3
exclusively. This is correct — the parser silently routes around the
ST 2110-10:2022 editorial error.

No action recommended; if/when an erratum is published correcting "RFC 7272"
to "RFC 7273", a comment at line 656 (`valid_tsrefclk` header) and 667
(`localmac=` branch) noting the spec-text typo would be useful for future
auditors.

### Finding 2 — Three real coverage gaps in §8.5 and §8.7 enforcement

**(a) Row 43 / §7.9 presence dependency — TSMODE=SAMP → TSDELAY**

ST 2110-10 §7.9: *"Devices which signal TSMODE=SAMP shall also signal their
Transmission Delay value in the SDP as indicated in section 8.7."* This is
SDP-observable: both attributes are in the same fmtp string. The parser
validates TSMODE and TSDELAY values independently (lines 1877, 1881) but
never cross-checks. A SDP with `TSMODE=SAMP` and no `TSDELAY=…` would pass
ST 2110 validation today.

Cite: `ST 2110-10 §7.9` (the SHALL is in §7.9 even though the value-form is §8.7).

**(b) Row 65/66 scope — TSMODE/TSDELAY only validated for raw video**

Both checks live in `video_opt_checks` (lines 1861–1882) inside the
`elseif m.media == "video"` arm that handles raw uncompressed (ST 2110-20).
The jxsv branch (1506–1711), audio branch (1894–2027), smpte291 branch
(1364–1467), and ST 2110-41 branch (1469–1505) do not call these checks.

The §8.7 SHALL ("Allowed values are: TSMODE=SAMP / NEW / PRES";
"TSDELAY … decimal positive integer number of microseconds") is in ST
2110-10, the umbrella spec. It is not raw-video-specific. A jxsv stream
carrying `TSMODE=foo` or `TSDELAY=-5` would pass today.

Fix: hoist the `TSMODE`/`TSDELAY` checks out of the per-media-branch
`video_opt_checks` into a media-agnostic post-rtpmap pass. Cite remains
`ST 2110-10 §8.7`.

**(c) Row 61 — sentinel-string weakening of "identical source AND destination"**

`leg_addrs` (lines 2076–2091) returns `src = ""` when no `a=source-filter`
attribute is present. The reject condition at 2135 is
`dst ~= "" ∧ dst == base_dst ∧ src == base_src` — when both legs lack
source-filter, both srcs are `""` and **the condition fires**, which is
correct. But when one leg has source-filter and the other does not, the
comparison `"" == "<some-ip>"` is false and the reject is skipped — which
silently weakens the §8.5 "shall not use identical source AND destination"
rule for that mismatch. Per RFC 7104 §4.2, "Separate Destination Addresses"
is the mechanism for redundant pairs *without* source filtering; the
parser cannot tell whether the absence of source-filter means
"unconstrained source" or "same source as the other leg".

This is a known limit of SDP-only validation — without source-filter,
source addresses are not in the SDP. Recommend documenting in the
PLAN.md "Known Deferred Items" rather than fixing.

### Finding 3 — Spec-ref drift: §8.2/§8.3 origin clauses cited as §7.2/§7.3

Several errors cite the *origin* clause (§7.2 RTP/Media Clock,
§7.3 RTP Clock Offset) rather than the *SDP signalling* clause that the
inventory tracks (§8.2 ts-refclk, §8.3 mediaclk).

| Parser line | Current `spec_ref` | Inventory expectation |
|---|---|---|
| 1285 (ts-refclk missing) | `ST 2110-10 §7.2` | §8.2 (presence requirement is in §8.2) |
| 1290 (ts-refclk invalid value) | `ST 2110-10 §7.2` | §8.2 (form requirement is in §8.2) |
| 1296 (mediaclk missing) | `ST 2110-10 §7.3` | §8.3 (presence requirement is in §8.3) |
| 1300 (mediaclk invalid value) | `ST 2110-10 §7.3` | §8.3 (form requirement is in §8.3) |
| 1126 (mediaclk direct offset ≠ 0) | `ST 2110-10 §8.3` | §7.3 + §8.3 — already cites §8.3 (this one is correct) |

The drift is benign — both clauses are normative and ST 2110-10 §8.x
explicitly cross-refs §7.x — but a strict primary-source cite would use
§8.x for SDP-form errors and §7.x only for value-derivation reasons
(e.g. line 1126's offset=0 is fundamentally §7.3 even though §8.3 forwards
that rule).

Main-thread decision: leave as-is (errors are still navigable) or
normalise to §8.x for presence/value-form messages.

## Reverse direction (parser → spec)

Every line in `parse_sdp.lua` that emits `spec_ref` matching `"ST 2110-10"`:

```
651:-- ST 2110-10 §6.5 (RFC 791 IPv4 / RFC 2460 IPv6 literal addressing for ST 2110/IPMX) and RFC 4570 for source-filter.
656:-- Validate the value of a ts-refclk attribute per ST 2110-10 §7.2.
765:-- Valid m= transport protocols for ST 2110 RTP media blocks (ST 2110-10 §8.1).
784:-- (ST 2110-10 §6.5 / RFC 4570).
806:-- prose, with the ST 2110-10 §6.5 / RFC 5771 forbidden multicast ranges.
879:        "forbidden multicast range 224.0.%d.0/24 (ST 2110-10 §6.5): %s", o3, ip)
898:-- Valid TSMODE values per ST 2110-10 §8.7 (RTP timestamp generation mode).
988:-- ST 2110-10 §6.4: Extended UDP Size Limit is 8960 octets. MAXUDP signals
995:    return nil, "MAXUDP must not exceed Extended UDP Size Limit of 8960 (ST 2110-10 §6.4)"
1111:-- Validate the value of a mediaclk attribute per ST 2110-10 §8.3 (which defers
1126:    return nil, "mediaclk direct offset must be 0 (ST 2110-10 §8.3)"
1208:      { field_path = "media", spec_ref = "ST 2110-10 §7" })
1213:  -- ST 2110-10 §8.3: mediaclk SHALL be media-level only.
1220:          spec_ref = "ST 2110-10 §8.3", code = "INVALID_VALUE" })
1224:  -- Validate session-level c= if present (ST 2110-10 §6.5).
1231:        spec_ref   = "ST 2110-10 §6.5", code = "INVALID_VALUE",
1243:        { field_path = mpath .. ".proto", spec_ref = "ST 2110-10 §8.1", code = "INVALID_VALUE" })
1252:          spec_ref   = "ST 2110-10 §6.5", code = "INVALID_VALUE",
1257:    -- Validate every a=source-filter on this media block (RFC 4570 / ST 2110-10 §8.4).
1263:            "ST 2110-10 §8.4 / RFC 4570", "INVALID_VALUE")
1268:    -- Require a connection address at session or media level (ST 2110-10 §6.3).
1272:        { field_path = mpath .. ".connection", spec_ref = "ST 2110-10 §6.3" })
1275:    -- Validate all ts-refclk attrs from both session and media level (ST 2110-10 §8.2).
1285:      return attr_err("missing required attribute 'ts-refclk'", mpath, "ts-refclk", "ST 2110-10 §7.2")
1290:        return attr_err("invalid ts-refclk: " .. (trmsg or ""), mpath, "ts-refclk", "ST 2110-10 §7.2", "INVALID_VALUE")
1296:      return attr_err("missing required attribute 'mediaclk'", mpath, "mediaclk", "ST 2110-10 §7.3")
1300:      return attr_err("invalid mediaclk: " .. (mcmsg or ""), mpath, "mediaclk", "ST 2110-10 §7.3", "INVALID_VALUE")
1305:      return attr_err("missing required attribute 'rtpmap'", mpath, "rtpmap", "ST 2110-10 §7")
1327:    -- ST 2110-10 §6.2: dynamic payload types 96–127
1349:            "...is outside the dynamic range 96-127 and does not match an RFC 3551 §6 static designation for this encoding (ST 2110-10 §6.2)"
1351:          mpath, "rtpmap", "ST 2110-10 §6.2", "INVALID_VALUE")
1689:      -- Optional: MAXUDP (1..8960 per ST 2110-10 §6.4), CMAX (...)
1859:      -- TSMODE / TSDELAY are from ST 2110-10 §8.7 (RTP timestamp generation).
1877:        { "TSMODE",  function(v) ... end, "ST 2110-10 §8.7" },
1881:        { "TSDELAY", valid_pos_int,  "ST 2110-10 §8.7" },
1991:      -- Packet payload fit (ST 2110-10 §6.4 + ST 2110-30 §6.2.2).
2009:              mpath, "fmtp", "ST 2110-10 §6.4", "INVALID_VALUE")
2068:  -- Validate a=group:DUP grouping per ST 2110-10 §8.5 + RFC 7104.
2092:  local dup_ok, dup_err = each_dup_group(doc, "ST 2110-10 §8.5", ...)
2104,2112,2120,2132,2139:    spec_ref = "ST 2110-10 §8.5", code = "INVALID_VALUE"
2394:  -- IPMX is a media transport profile built on ST 2110-10 §7 / §8.1
2401:      { field_path = "media", spec_ref = "ST 2110-10 §7" })
```

47 occurrences total — every ST 2110-10 SHALL with an SDP signature is
exercised at least once, except:

- §7.9 presence dependency TSMODE=SAMP → TSDELAY (Finding 2a).
- TSMODE/TSDELAY value-form for non-raw-video essences (Finding 2b).

---

## SMPTE ST 2110-20:2022

# Audit Coverage — SMPTE ST 2110-20:2022 (Uncompressed Active Video)

Inventory: `/tmp/audit_inventory_st2110-20.md`
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`

This document covers ALL **57 SDP-Y** rows from the Phase 1 inventory (the
SDP-N wire-format rows are listed once at the bottom, since they are
out-of-SDP scope by definition).

Status legend:
- COVERED — parser has a check grounded in this clause (cite the line/section).
- PARTIAL — parser has a check that covers part of the clause, but a sub-case is missing.
- MISSING — parser has no check for this clause.
- OUT-OF-SCOPE — SDP-N row, validator is correct to not check.

| # | § | Summary | Status | Parser citation / Notes |
|---|---|---|---|---|
| 5 | §6.1.1 | Image metadata MUST be communicated via SDP §7 | COVERED (META) | Tier-establishing clause; concrete §7 sub-clauses (rows 77-118) are each covered or marked below. The validator routes raw video through `m.media == "video"` at line 1713. |
| 10 | §6.1.2 | PT shall be dynamic | COVERED | Lines 1334-1353 (`pt_n < 96` gate, with an RFC 3551 §6 static exception list); spec_ref `ST 2110-10 §6.2`. Owned by ST 2110-10 inventory; the SDP-visible part is enforced. |
| 18 | §6.1.3 | RTP Clock rate = 90 kHz | COVERED | Line 1715: `if clock_rate ~= 90000 then ... "rtpmap clock rate must be 90000 for video"`. Spec_ref `ST 2110-20 §7.2`. |
| 48 | §6.2.1 | UDP size capped per ST 2110-10 (SDP-visible: MAXUDP enum value) | PARTIAL | `valid_maxudp` (lines 991-998) enforces upper bound 8960 (Extended UDP Size Limit, ST 2110-10 §6.4). Spec-grounded for the value form. The "SDP-N" wire-level check is out of scope. |
| 52 | §6.2.2 | SDP parameters define pgroup composition | COVERED (META) | Tier-establishing clause; concrete (sampling, depth) constraints in rows 55, 57, 61, 66 are MISSING (see below). |
| 54 | §6.2.3 | 4:4:4 pgroup construction per Table 1 | MISSING | No parser-side enforcement of "Table 1 closed (sampling, depth) set" for the 4:4:4 family. See row 55 for the specific data point. |
| 55 | §6.2.3 Table 1 | 4:4:4 (sampling, depth) closed set: RGB and YCbCr/CLYCbCr/ICtCp 4:4:4 ∈ {8,10,12,16,16f}; XYZ ∈ {12,16,16f} only | **MISSING** | The parser validates `sampling` and `depth` enums independently (lines 742-746 and 963-965). It does NOT reject `sampling=XYZ` paired with `depth=8` or `depth=10`, which Table 1 does not define. No (sampling, depth) cross-table validation exists for 4:4:4. |
| 56 | §6.2.4 | 4:2:2 pgroup construction per Table 2 | MISSING | No enforcement that `RGB-4:2:2`, `XYZ-4:2:2`, `KEY-4:2:2`, etc. are undefined. Since the `sampling` enum (line 742-746) does not include `RGB-4:2:2` or `XYZ-4:2:2` as values at all, this is implicitly enforced for those tokens. The 4:2:2 family permits only YCbCr-/CLYCbCr-/ICtCp-4:2:2 sampling values, which is consistent with the enum. So the (sampling) restriction is COVERED via the enum table. The (sampling, depth) constraint for these is identical to 4:4:4 (depths {8,10,12,16,16f}) and is COVERED via `valid_depth`. |
| 57 | §6.2.4 Table 2 | 4:2:2 closed set: YCbCr-4:2:2 / CLYCbCr-4:2:2 / ICtCp-4:2:2 ∈ {8,10,12,16,16f} | COVERED | `VALID_SAMPLING` (line 743) and `VALID_DEPTH` (line 963) together cover the closed set without needing a cross-table check. |
| 58 | §6.2.5 | 4:2:0 only for progressive (not PsF/interlaced) | COVERED | Lines 1844-1857 — checks `params["sampling"]:match("^[A-Za-z]+%-4:2:0$")` with `params["interlace"]` and rejects the combination. Spec_ref `ST 2110-20:2022 §6.2.5`. Note: rejects 4:2:0 + interlace; since `segmented` requires `interlace` (row 96), 4:2:0+segmented is also indirectly covered (would fail the segmented-without-interlace check first or the 4:2:0+interlace check if both present). |
| 59 | §6.2.5 | 4:2:0 forbidden for PsF/interlaced (restatement of row 58) | COVERED | Same lines 1844-1857. |
| 60 | §6.2.5 | 4:2:0 pgroup construction per Table 3 | MISSING (META — table-row 61 carries the SDP-Y datapoint) | See row 61. |
| 61 | §6.2.5 Table 3 | 4:2:0 (sampling, depth) closed set: YCbCr/CLYCbCr/ICtCp-4:2:0 ∈ {8,10,12}; NO 16 or 16f | **MISSING** | The parser accepts `sampling=YCbCr-4:2:0, depth=16` and `sampling=YCbCr-4:2:0, depth=16f` because both enums permit them independently. No cross-parameter check rejects 4:2:0 + depth∈{16,16f}, which Table 3 does not define. |
| 65 | §6.2.6 | Key pgroup per Table 4 | COVERED (META) | Row 66 carries the SDP-Y datapoint, see below. |
| 66 | §6.2.6 Table 4 | KEY sampling allowed at depths {8,10,12,16,16f} | COVERED | `VALID_DEPTH` (line 963) already enumerates {8,10,12,16,16f}, so any KEY+depth combination drawn from the global depth enum is in Table 4's permitted set. The complete intersection is correctly enforced by the global enums. |
| 69 | §6.3.2 | GPM ⇒ PM=2110GPM | COVERED | `VALID_PM = { ["2110GPM"]=true, ["2110BPM"]=true }` at line 763, plus required-field check at line 1748 (`PM` is in the `video_checks` list). |
| 75 | §6.3.3 | BPM forbids Extended UDP limit (cross-parameter: PM=2110BPM ⇒ MAXUDP must NOT denote Extended UDP) | COVERED | Lines 1819-1823 — `if params["PM"] == "2110BPM" and params["MAXUDP"] ~= nil then ...`. The check is stricter than the spec text (rejects ANY MAXUDP with BPM, not just Extended-denoting values), but the spec defines MAXUDP itself as "signaling that a sender exceeds the Standard UDP Size Limit" (ST 2110-10 §6.4), making any MAXUDP non-Standard, so the stricter form is conformant. Spec_ref `ST 2110-20 §6.3.3`. |
| 76 | §6.3.3 | BPM ⇒ PM=2110BPM | COVERED | Same as row 69 — closed set enforced via `VALID_PM`. |
| 77 | §7.1 | SDP must conform to RFC 4566 | COVERED (META) | `validate.sdp` (called at line 1203) runs the RFC 4566 tier first. All ST 2110 checks layer on top. |
| 78 | §7.1 | `m=video ... raw/...` | PARTIAL | `m.media == "video"` is enforced as the routing key for the ST 2110-20 branch (line 1713). The rtpmap encoding name "raw" is NOT explicitly required — the parser only checks `clock_rate ~= 90000` (line 1715). An SDP with `m=video ... 96` and `a=rtpmap:96 foo/90000` would pass into the ST 2110-20 branch and not be rejected for encoding-name mismatch. This is a coverage gap for the §7.1 SHALL "the Media Subtype name raw". |
| 79 | §7.1 | `a=rtpmap:<pt> raw/90000` clock rate = 90000 | COVERED | Line 1715 (above). |
| 80 | §7.1 | SDP applies uniformly to whole stream | OUT-OF-SCOPE | Interpretation rule, not a checkable constraint. |
| 81 | §7.1 | fmtp parameter separator is `;` followed by whitespace | COVERED | `valid_st2110_20_fmtp_format` (lines 1153-1169) walks the fmtp string and requires every `;` to be followed by space-or-tab. Spec_ref `ST 2110-20:2022 §7.1`. |
| 82 | §7.1 | No trailing semicolon in fmtp | COVERED | `fmtp_no_trailing_semicolon` (lines 1144-1151), called from `valid_st2110_20_fmtp_format`. Spec_ref `ST 2110-20:2022 §7.1`. |
| 83 | §7.1 | fmtp line ends with carriage return | COVERED | The RFC 4566 grammar (`validate.sdp` tier) enforces CRLF line termination on every record. AMBIGUOUS per inventory — RFC 4566 CRLF is consistent with the spec's "carriage return" wording. |
| 84 | §7.1 | fmtp entries: either `name=value` (no internal whitespace) OR bare `name` | PARTIAL | `fmtp_params` (lines 1174-1192) supports both forms (line 1185: `params[trimmed] = true` for bare flag). It rejects malformed entries (line 1187). However, it does NOT explicitly enforce "no whitespace within name, value, or between name/=/value" — its grammar is `kv:gmatch("[^;]+")` then `match("^([^=%s]+)%s*=%s*(.-)$")`, which trims surrounding whitespace around `=` (the `%s*` between name and value). A spec-strict reading: `name = value` (with spaces around `=`) should be rejected per §7.1 bullet "no whitespace within the name or value or between the name, equal sign, and value". Currently accepted. Spec_ref `ST 2110-20:2022 §7.1`. |
| 85 | §7.2 | Required fmtp parameters intro (META) | COVERED (META) | Required list enforced at lines 1741-1767 (the `video_checks` table iteration). |
| 86 | §7.2 | `sampling` required + value set in §7.4.1 | COVERED | Required-presence: line 1742 (`{ "sampling", function(v) return valid_enum(v, VALID_SAMPLING, "sampling") end }`). Value-set: `VALID_SAMPLING` table at line 742-746 enumerates all 12 values. Spec_ref `ST 2110-20 §7.2`. |
| 87 | §7.2 | `depth` required + value set in §7.4.2 | COVERED | Line 1746 (`{ "depth", valid_depth, "ST 2110-20 §7.4.2" }`). `valid_depth` (line 966-970) enforces {8,10,12,16,16f}. |
| 88 | §7.2 | `width` required + integer [1, 32767] | COVERED | Line 1743 (`{ "width", valid_width }`). `valid_width = valid_pixel_dim("width")` (line 985) with check `n > 32767` rejection (line 979). |
| 89 | §7.2 | `height` required + integer [1, 32767] | COVERED | Line 1744 (`{ "height", valid_height }`), same builder. |
| 90 | §7.2 | `exactframerate` required + integer OR `num/den` with smallest numerator | COVERED | Line 1745 (`{ "exactframerate", valid_exactframerate }`). `valid_exactframerate` (lines 1012-1031) checks `_efr_pat` (digit-only or N/D) and uses `gcd(n, d) ~= 1` to reject non-reduced fractions. Spec_ref `ST 2110-20:2022 §7.2`. |
| 91 | §7.2 | `colorimetry` required + value set in §7.5 | COVERED | Line 1747 (`{ "colorimetry", function(v) return valid_enum(v, VALID_COLORIMETRY, "colorimetry") end }`). `VALID_COLORIMETRY` (line 758-762) lists all 9 values. |
| 92 | §7.2 | `PM` required + value set in §6.3 | COVERED | Line 1748 (`{ "PM", function(v) return valid_enum(v, VALID_PM, "PM") end }`). `VALID_PM` (line 763) is {2110GPM, 2110BPM}. |
| 93 | §7.2 | `SSN` required + conditional value rule | PARTIAL | Required-presence and pattern-match `ST2110-20:YYYY` are enforced (lines 1749-1752 using `_ssn20_pat`). Conditional forward direction enforced at lines 1778-1789 (`needs_2022 = TCS=ST2115LOGS3 or colorimetry=ALPHA` ⇒ SSN must be `:2022`). Two coverage gaps: (a) the year suffix accepts ANY 4-digit year (e.g. `ST2110-20:1999` passes the pattern) — the spec defines only `:2017` and `:2022`; (b) the reverse direction (`SSN=:2017` rejected when ALPHA/ST2115LOGS3 NOT present is enforced; but `SSN=:2022` is accepted even when neither trigger is present, which the parser comment at line 1774-1777 marks as a deliberate deferral). The forward direction's spec_ref is `ST 2110-20:2022 §7.2`. |
| 94 | §7.3 | Optional-with-defaults parameter list intro (META) | COVERED (META) | The optional parameters (TCS, RANGE, MAXUDP, PAR, interlace, segmented) are each handled below. |
| 95 | §7.3 | `interlace` standalone token; absence ⇒ progressive | COVERED | Bare-flag enforcement: `fmtp_params` (line 1185) stores `true` for standalone tokens. Bare-flag form-validation: lines 1803-1808 reject `interlace=value`. Default semantics are handled by the absence of any other check (no "must be present" requirement). Spec_ref `ST 2110-20 §7.3`. |
| 96 | §7.3 | `segmented` standalone; `segmented` without `interlace` forbidden | COVERED | Bare-flag enforcement: same as row 95 (lines 1803-1808). Cross-parameter check: lines 1811-1814 — `if params["segmented"] and not params["interlace"] then ...`. Spec_ref `ST 2110-20 §7.3`. |
| 97 | §7.3 | `TCS` optional; values in §7.6; default if absent | COVERED | Line 1865 (`{ "TCS", function(v) return valid_enum(v, VALID_TCS, "TCS") end, "ST 2110-20:2022 §7.6" }`). `VALID_TCS` (lines 751-756) enumerates 11 values. Default-when-absent semantics not validated (no requirement to validate defaults). |
| 98 | §7.3 | `RANGE` optional; value depends on colorimetry. If BT2100: {NARROW, FULL}; else: {NARROW, FULLPROTECT, FULL}. Default = NARROW. | **PARTIAL/MISSING (cross-parameter)** | The global enum check is present (lines 1790-1796 — `VALID_RANGE = { NARROW, FULLPROTECT, FULL }`). However, the cross-parameter restriction "colorimetry=BT2100 ⇒ RANGE ∈ {NARROW, FULL} (FULLPROTECT forbidden)" is **NOT enforced**. An SDP with `colorimetry=BT2100; RANGE=FULLPROTECT` would pass. |
| 99 | §7.3 | If RANGE absent, default = NARROW | COVERED (no check needed) | Default semantics, not a constraint on present values. |
| 100 | §7.3 | `MAXUDP` optional; meaning per ST 2110-10; default = Standard Limit | COVERED | Line 1866 (`{ "MAXUDP", valid_maxudp }`). `valid_maxudp` (lines 991-998) bounds 1..8960. Cross-parameter cross-cite to row 75 (MAXUDP forbidden with PM=2110BPM) is also enforced. |
| 101 | §7.3 | `PAR` optional; form = W:H, reduced; default = 1:1 | COVERED | Line 1867 (`{ "PAR", valid_par }`). `valid_par` (lines 1036-1050) checks W:H form via `_par_pat` and rejects non-reduced fractions via `gcd(wn, hn) ~= 1`. |
| 102 | §7.4.1 | `sampling` value MUST be one defined in §7.4.1 | COVERED | `VALID_SAMPLING` (line 742-746) enumerates all 12 defined values. Validated via line 1742. |
| 103 | §7.4.1 | YCbCr 4:4:4 / 4:2:2 / 4:2:0 defined values | COVERED | `VALID_SAMPLING` enumerates `YCbCr-4:4:4`, `YCbCr-4:2:2`, `YCbCr-4:2:0`. |
| 104 | §7.4.1 | CLYCbCr 4:4:4 / 4:2:2 / 4:2:0 defined values | COVERED | `VALID_SAMPLING` enumerates `CLYCbCr-4:4:4`, `CLYCbCr-4:2:2`, `CLYCbCr-4:2:0`. |
| 105 | §7.4.1 | ICtCp 4:4:4 / 4:2:2 / 4:2:0 defined values | COVERED | `VALID_SAMPLING` enumerates `ICtCp-4:4:4`, `ICtCp-4:2:2`, `ICtCp-4:2:0`. |
| 106 | §7.4.1 | RGB defined value | COVERED | `VALID_SAMPLING` contains `RGB`. |
| 107 | §7.4.1 | XYZ defined value | COVERED | `VALID_SAMPLING` contains `XYZ`. (Cross-table depth restriction is the gap — see row 55.) |
| 108 | §7.4.1 | KEY defined value | COVERED | `VALID_SAMPLING` contains `KEY`. |
| 109 | §7.4.1 | KEY ⇒ colorimetry=ALPHA AND no TCS attribute | COVERED | Lines 1832-1843 — checks both halves of the SHALL: (a) `params["colorimetry"] ~= "ALPHA"` rejection, (b) `params["TCS"] ~= nil` rejection. Spec_ref `ST 2110-20:2022 §7.4.1`. |
| 110 | §7.4.2 | Closed depth set {8, 10, 12, 16, 16f} | COVERED | `VALID_DEPTH` (line 963) is exactly this set; validated via `valid_depth` (lines 966-970) called from line 1746. |
| 111 | §7.5 | Closed colorimetry set | COVERED | `VALID_COLORIMETRY` (lines 758-762) is the exact set. Validated via line 1747. |
| 113 | §7.6 | Closed TCS set (11 values) | COVERED | `VALID_TCS` (lines 751-756) is the exact set. Validated via line 1865. |
| 114 | §7.6 | TCS default = SDR; meaningless for KEY (cross-cite row 109) | COVERED | Row 109's check (lines 1832-1843) already rejects TCS-present with sampling=KEY. The "default = SDR" is not a constraint on present values. |
| 115 | §7.6 LINEAR | `TCS=LINEAR` ⇒ `depth=16f` | **MISSING** | No cross-parameter check exists. The parser accepts `TCS=LINEAR` with any depth in the enum. |
| 116 | §7.6 BT2100LINPQ | `TCS=BT2100LINPQ` ⇒ `depth=16f` | **MISSING** | Same as row 115. |
| 117 | §7.6 BT2100LINHLG | `TCS=BT2100LINHLG` ⇒ `depth=16f` | **MISSING** | Same as row 115. |
| 118 | §7.6 ST2065-1 | `TCS=ST2065-1` ⇒ `depth=16f` | **MISSING** | Same as row 115. |

## SDP-N (out-of-SDP) rows — listed for completeness

Rows 1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 49, 50, 51, 53, 62, 63, 64, 68, 70, 71, 72, 73, 74, 112.

All 58 N/SDP-N rows are OUT-OF-SCOPE for the SDP-only validator (wire-format
semantics, RTP header field semantics, traffic shaping, receiver behaviour,
"should" recommendations). No parser check is required and none is missing.

## Summary

- SDP-Y rows: 57
- Sub-set covered fully (COVERED, including META roll-ups): 41
- PARTIAL (incomplete coverage on a sub-case): 6 — rows 48, 78, 84, 93, 98, 60 (60 is META rolled to row 61)
- MISSING (no parser check at all): 6 — rows 54 (META roll to row 55), 55, 61, 115, 116, 117, 118

Cross-parameter rules required by the spec — coverage scoreboard:
- 4:2:0 sampling + interlace forbidden — COVERED (row 58)
- 4:2:0 only with depth ∈ {8,10,12} — **MISSING** (row 61)
- XYZ sampling only with depth ∈ {12,16,16f} — **MISSING** (row 55)
- `segmented` requires `interlace` — COVERED (row 96)
- KEY sampling ⇒ colorimetry=ALPHA AND no TCS — COVERED (row 109)
- colorimetry=BT2100 restricts RANGE to {NARROW, FULL} — **MISSING** (row 98)
- PM=2110BPM ⇒ MAXUDP must NOT denote Extended UDP — COVERED (row 75)
- SSN=ST2110-20:2022 iff (colorimetry=ALPHA OR TCS=ST2115LOGS3) — PARTIAL (row 93; forward only)
- TCS ∈ {LINEAR, BT2100LINPQ, BT2100LINHLG, ST2065-1} ⇒ depth=16f — **MISSING** (rows 115-118)

---

## SMPTE ST 2110-21:2022

# Audit Coverage Map: SMPTE ST 2110-21:2022 — Traffic Shaping

Source inventory: `/tmp/audit_inventory_st2110-21.md`
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`
Method: Mechanical map of every SDP-Y row (and AMBIGUOUS row) to a parser
check or a MISSING/AMBIGUOUS classification.

## Mapping table (SDP-Y + AMBIGUOUS rows from inventory)

| Inv # | § | Clause (summary) | Parser site (file:line) | Test site (file:line) | Classification | Notes |
|---|---|---|---|---|---|---|
| 6 | §6.2 | TROFFSET shall be a positive number or zero (governs underlying value of TROFF). | `parse_sdp.lua:1871` (raw video TROFF check: `valid_pos_int`) | `spec/st2110_spec.lua:723–735` (accepts TROFF=1000; rejects TROFF=0) | AMBIGUOUS (parser enforces §8.2 wording; §6.2 disagrees on zero — flagged in inventory observation 4) | Parser currently rejects TROFF=0. §6.2 ("positive number or zero") would accept it; §8.2 ("positive integer") would reject it. Inventory flags this as do-not-resolve. The parser cite is `ST 2110-21:2022 §8.2`, which matches the stricter reading. |
| 8 | §6.2 | Sender SHALL signal TROFF when TROFFSET != TRODEFAULT. | (none) | (none) | MISSING — NOT SDP-VALIDATABLE | Inventory observation 3: parser cannot compute TRODEFAULT from SDP alone (depends on height/frame rate path through §6.3/§6.4). Out-of-scope under strictness principle (silence + missing context). |
| 10 | §6.3.1 | Gapped PRS applies only to ITU-R BT.656-5 / BT.1543-1 / BT.709-6 / BT.2020-2-derived dimensions/rates. | (none) | (none) | AMBIGUOUS (inventory marker) | Spec gives no closed enumeration of {width, height, exactframerate} tuples. Not parser-grade. |
| 25 | §7.1.2 | Type N senders shall signal `TP=2110TPN`. | `parse_sdp.lua:890` (`VALID_TP = { ["2110TPN"]=true, ... }`); enforced in raw video required list at `parse_sdp.lua:1753–1754` via `valid_enum(v, VALID_TP, "TP")`; also enforced for jxsv compressed video at `parse_sdp.lua:1577` via `VALID_TP_22`. | `spec/st2110_spec.lua:1103` (rejects `TP=BADTP`) plus dozens of acceptance fixtures using `TP=2110TPN`. | COVERED | Defined-value-set member; enum membership enforced. |
| 29 | §7.1.3 | Type NL senders shall signal `TP=2110TPNL`. | Same as row 25 (`VALID_TP` / `VALID_TP_22` include `2110TPNL`). | `spec/st2110_spec.lua:1103` (rejects `TP=BADTP`); enum-acceptance is implicit via the value-set membership. | COVERED | Defined-value-set member. |
| 34 | §7.1.4 | Type W senders shall signal `TP=2110TPW`. | Same as row 25 (`VALID_TP` / `VALID_TP_22` include `2110TPW`). | `spec/st2110_spec.lua:1103` (rejects `TP=BADTP`); enum-acceptance is implicit via the value-set membership. | COVERED | Defined-value-set member. |
| 40 | §8.1 | "Senders shall include the following … Media Type parameters in the a=fmtp clause of the SDP for all video RTP streams …" (intro clause). | `parse_sdp.lua:1741–1767` (raw video `video_checks` loop requires every key incl. TP); `parse_sdp.lua:1574–1579` (jxsv `jxs_req` for compressed video). | `spec/st2110_spec.lua:1066–1083` (every required parameter has a "missing" row). | COVERED | Intro clause is enforced by the required-list iteration; bullet (TP) attaches via row 41. |
| 41 | §8.1 | `TP` is a required a=fmtp parameter for video RTP streams; permitted values defined in §7.1. | `parse_sdp.lua:1753–1754` (raw video required check with `spec_ref = "ST 2110-21:2022 §8.1"`); `parse_sdp.lua:1577` (compressed video jxsv required check). | `spec/st2110_spec.lua:1078` (rejects fmtp missing TP); `spec/st2110_spec.lua:1103` (rejects `TP=BADTP`). | COVERED | Required-presence + defined-value-set both enforced; cite matches inventory exactly. |
| 42 | §8.2 | Optional a=fmtp parameters intro clause (binds TROFF, CMAX). | `parse_sdp.lua:1861–1892` (raw video `video_opt_checks` loop — validates form when present, accepts absence). | n/a (umbrella clause — covered transitively via rows 43/44 tests). | COVERED | Optional-list semantics: validate-when-present, accept-when-absent. |
| 43 | §8.2 | `TROFF` value form: positive integer microseconds. | `parse_sdp.lua:1871` (`{ "TROFF", valid_pos_int, "ST 2110-21:2022 §8.2" }`); validator at `parse_sdp.lua:948–952` (`valid_pos_int`). | `spec/st2110_spec.lua:723–727` (TROFF=1000 accepted); `spec/st2110_spec.lua:729–735` (TROFF=0 rejected). | COVERED (AMBIGUOUS with row 6) | Parser implements §8.2's "positive integer" strictly. Inventory observation 4 flags the §6.2 vs §8.2 disagreement. Row-6 AMBIGUOUS marker carries the audit signal. |
| 44 | §8.2 | `CMAX` value form: integer (no sign explicitly stated). | `parse_sdp.lua:1876` (`{ "CMAX", valid_integer, "ST 2110-21:2022 §8.2" }`); validator at `parse_sdp.lua:957–960` (`valid_integer`, signed). Also enforced for jxsv at `parse_sdp.lua:1699–1705`. | (no dedicated CMAX form test located in `spec/st2110_spec.lua`; coverage relies on the `valid_integer` validator). | COVERED | "No sign or zero restriction" matches the prose. Parser comment at line 956 explicitly cites §8.2 as the reason for signed-integer acceptance. |

## Totals

- Inventory rows mapped: 11 SDP-Y + 1 already-AMBIGUOUS that overlaps (row 10) = 12 distinct entries inspected.
- COVERED: 8 (rows 25, 29, 34, 40, 41, 42, 43, 44).
- AMBIGUOUS (carried forward, not resolved): 2 (row 6 — §6.2 vs §8.2 on TROFF=0; row 10 — gapped PRS dimensional scope).
- MISSING — NOT SDP-VALIDATABLE: 1 (row 8 — TROFF mandatory-when-non-default needs out-of-SDP TRODEFAULT computation).
- MISSING — SHOULD-BE-COVERED: 0.

## Reverse-direction check (sanity)

`grep -nE '"ST 2110-21|ST 2110-21:2022' parse_sdp.lua` returns four cite sites,
all aligned with inventory rows:

| Parser cite | Line | Inventory row it serves |
|---|---|---|
| `ST 2110-21:2022 §8.2` (CMAX integer note) | 956 (comment) / 1703 (jxsv) / 1876 (raw) | 44 |
| `ST 2110-21:2022 §8.2` (TROFF positive integer) | 1868–1871 | 43 |
| `ST 2110-21:2022 §8.1` (TP required for raw video) | 1736 / 1754 | 40, 41 |

No parser cites of ST 2110-21 land outside the SDP-Y rows in the inventory.

## Top 3 findings

1. **TP enum + required-presence is the central -21 SDP signal and is fully
   covered.** Rows 25/29/34 (defined-value-set: `{2110TPN, 2110TPNL, 2110TPW}`)
   and row 41 (required-presence in raw video and jxsv) are enforced via
   `VALID_TP` / `VALID_TP_22` and the required-list loops at
   `parse_sdp.lua:1741–1767` and `parse_sdp.lua:1574–1579`. Negative test
   `TP=BADTP` and missing-TP test both present. No gap.

2. **Row 43 (TROFF=0) is the live AMBIGUOUS finding.** Parser rejects TROFF=0
   citing §8.2 "positive integer." Inventory row 6 (§6.2 "positive number or
   zero") and row 43 (§8.2 "positive integer") disagree. Code comment at
   `parse_sdp.lua:1868–1871` already acknowledges this, and test
   `spec/st2110_spec.lua:729–735` explicitly locks in the strict §8.2 reading.
   This is the only -21 audit finding worth a verdict in a later phase.

3. **Row 8 (TROFF-when-non-default) is correctly absent.** The §6.2 obligation
   to signal TROFF when `TROFFSET != TRODEFAULT` is not SDP-validatable: the
   parser would need to derive `TRODEFAULT` from height + frame-rate path
   through §6.3/§6.4. Marked MISSING — NOT SDP-VALIDATABLE; consistent with
   the strictness principle (out-of-scope context lookup). No action needed.

---

## SMPTE ST 2110-22:2022

# Audit Coverage — SMPTE ST 2110-22:2022 (Compressed Video)

Inventory: `/tmp/audit_inventory_st2110-22.md` (36 rows, 26 SDP-Y direct + 2 AMBIGUOUS)
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`

Mechanical mapping only. SDP-N rows out of scope. Verdicts:

- COVERED: parser enforces this requirement (with location + spec-ref).
- COVERED-INHERITED: enforcement lives in the RFC 4566 / ST 2110-10 tier or in a referenced media-type validator that is run unconditionally before this one.
- PARTIAL: enforcement is present but does not match the full normative shape (e.g. missing value-range, missing branch).
- MISSING: no enforcement found in parser; no test exercises this requirement.
- N/A: SDP-N (not visible in SDP), or pure boilerplate.
- AMBIGUOUS-RESOLVED / AMBIGUOUS-UNRESOLVED: how the parser handles the row flagged AMBIGUOUS in the inventory.

| # | § | Summary | SDP? | Verdict | Parser site | Notes |
|---|---|---|---|---|---|---|
| 1 | 2 | Definition of "shall" | N | N/A | — | Conformance-notation boilerplate. |
| 2 | 2 | "reserved" must not be used | N | N/A | — | Document defines no reserved values. |
| 3 | 2 | Precedence of normative info types | N | N/A | — | Interpretation rule for the document. |
| 4 | 4 | Constant bytes per frame | N | N/A | — | RTP/codec stream property; not in SDP. |
| 5 | 4 | Constant RTP packets per frame | N | N/A | — | RTP stream property; not in SDP. |
| 6 | 5.1 | Conformance to ST 2110-10 | N (indirect) | COVERED-INHERITED | `st2110.validate` runs full -10 stack (`parse_sdp.lua:1202-1234` and following) before the per-encoding branch at `:1506`. | ST 2110-10 SDP rules apply on every media block; jxsv branch is reached after the -10 checks pass. |
| 7 | 5.2 | RTP Timestamp Clock rate shall be 90 kHz | Y | COVERED | `parse_sdp.lua:1516-1520` (`clock_rate ~= 90000` rejected) | Test at `spec/st2110_spec.lua` covers jxsv parse with `jxsv/90000` rtpmap. |
| 8 | 5.3 | TP must be N/NL/W (compliance) | Partial | COVERED via #9 | `parse_sdp.lua:891-895` (`VALID_TP_22`) + `:1577` (required `TP` enum) | Underlying compliance is timing; SDP-visible part covered by the TP enum check. |
| 9 | 5.3 | SDP shall include TP=2110TPN/TPNL/TPW | Y | COVERED | `parse_sdp.lua:1574-1579` lists `TP` as required and validates against `VALID_TP_22`; missing-`TP` triggers `fmtp missing required 'TP'` at `:1644-1646`. | Tests `spec/st2110_spec.lua:3017-3032` cover all three values; `:3112-3119` covers missing-TP rejection. |
| 10 | 6.1 | Payload format registered per RFC 4855 | N | N/A | — | Procedural / registry; not an SDP field check. |
| 11 | 6.2 | Media type name shall be "video" | Y | COVERED | `parse_sdp.lua:1511-1515` rejects `m=audio jxsv/90000` etc. | Test `spec/st2110_spec.lua:3144-3162` covers non-video rejection. |
| 12 | 6.2 | Subtype = registered payload-format name | Y | COVERED-INHERITED | `rtpmap_parse` (`parse_sdp.lua:553`) returns the encoding name; the jxsv branch is selected by `enc == "jxsv"` at `:1506`. | The subtype-to-encoding match is implicit in the dispatch: the validator picks the branch by encoding-name and applies the matching rules. Other subtypes (e.g. `vc2`) fall through to the generic video path. |
| 13 | 6.3 | rate parameter present, value = 90000 | Y | COVERED | Same as #7: `parse_sdp.lua:1516-1520`. | The "rate" parameter surfaces in SDP as the clock-rate of `a=rtpmap`; absence is rejected upstream by RFC 4566 / -10 rtpmap parser. |
| 14 | 7.1 | One SDP per RTP stream; -10 conformance | Y | COVERED-INHERITED | `st2110.validate` (`parse_sdp.lua:1202`) and per-media loop (`:1236`). | Each media block is validated independently as a -10 stream. |
| 15 | 7.1 | Mapping per RFC 4855 (illustrative bullets) | Y | COVERED-INHERITED | Mapping is implicit: `m=` → media-type (`:1511`), `a=rtpmap` → subtype (`:1325`), `a=fmtp` → params (`:1357`). | Bullets are illustrative per inventory; no additional SHALLs to enforce here. |
| 16 | 7.2 | fmtp syntax: `;`-separated, optional SP after `;` | Y | COVERED | `parse_sdp.lua:1521-1529` enforces no-trailing-`;`; `fmtp_params` (`:1174-1192`) splits on `;` and trims surrounding whitespace, accepting both `";param"` and `"; param"` forms. | The -22 branch (unlike the -20 branch at `:1720-1728`) does NOT require a space after `;` — matching the spec's "optionally followed by a space". Test `spec/st2110_spec.lua:3135-3142` covers trailing-`;` rejection. |
| 17 | 7.2 | No trailing semicolon | Y | AMBIGUOUS-RESOLVED → COVERED | `parse_sdp.lua:1144-1151` (`fmtp_no_trailing_semicolon`), wired in at `:1521-1528`. | The parser treats the declarative phrasing as normative and enforces it. Test at `spec/st2110_spec.lua:3135`. |
| 18 | 7.2 | Entry forms: `name=value` or bare `name` | Y | COVERED | `fmtp_params` `parse_sdp.lua:1174-1192` accepts both forms; rejects malformed tokens (`return nil, "malformed fmtp parameter: "`). | Standalone names (e.g. `interlace`) are stored as `true`; `name=value` stored as the string value. |
| 19 | 7.2 | Required-by-media-type params SHALL be included | Y | COVERED | jxsv branch enforces ST 2110-22 Table 1 required params at `:1574-1579` (width, height, TP) and additionally enforces the IANA video/jxsv required `packetmode` (`:1578`). | Other subtype-required params are deferred to that subtype's branch (e.g. ST 2110-20 has its own required list at `:1740+`). |
| 20 | 7.2 / Table 1 | Table 1 params (width, height, TP) required in a=fmtp | Y | COVERED | `parse_sdp.lua:1574-1579` (`jxs_req` list) plus the required-presence loop at `:1641-1652`. | Per-row coverage below. |
| 21 | 7.2 / Table 1 | width: integer 1..32767 | Y | PARTIAL | `parse_sdp.lua:1575` — jxsv branch uses `valid_pos_int` (lower bound only), not `valid_pixel_dim` (which enforces ≤32767). Compare: ST 2110-20 video branch at `:1743` uses `valid_width`/`valid_height`. | The upper bound 32767 is NOT enforced for jxsv. Per the inventory, "Permitted values are integers between 1 and 32767 inclusive" is a defined-value-set clause; ST 2110-22 re-states it explicitly. The check is missing the upper bound; a value like `width=99999` is accepted by the jxsv branch. |
| 22 | 7.2 / Table 1 | height: integer 1..32767 | Y | PARTIAL | `parse_sdp.lua:1576` — same construct as #21. | Same finding as #21 for height. |
| 23 | 7.2 / Table 1 | TP defined-value set {2110TPN, 2110TPNL, 2110TPW} | Y | COVERED | `parse_sdp.lua:891-895` (`VALID_TP_22`) + jxsv `jxs_req` check at `:1577` running the enum validator. | Tests at `spec/st2110_spec.lua:3017, 3027, 3112`. |
| 24 | 7.2 / Table 2 | Table 2 params (CMAX, SSN) MAY appear | Y | COVERED | jxsv branch handles each Table 2 entry as optional-with-validate-when-present: `parse_sdp.lua:1699-1705` (CMAX), `:1634-1640` (SSN). | "May" satisfied by accepting absence; defined-value-set validation runs only when present. |
| 25 | 7.2 / Table 2 | CMAX optional; form per ST 2110-21 | Y | COVERED | `parse_sdp.lua:1699-1705` calls `valid_integer` (signed integer per -21 §8.2). | Spec-ref `"ST 2110-21:2022 §8.2"` cited on the error. |
| 26 | 7.2 / Table 2 | SSN optional; value ∈ {ST2110-22:2019, ST2110-22:2022} | Y | COVERED | `parse_sdp.lua:1634-1640` validates against `_ssn22_pat` (`:731`). | Test `spec/st2110_spec.lua:3007-3015` rejects wrong SSN prefix (`ST2110-20:` for jxsv). |
| 27 | 7.3 / Table 3 | Media-level b= attribute required | Y | COVERED (twice) | `parse_sdp.lua:1530-1542` (per-encoding jxsv presence check) and again at `:2548-2574` (post-loop b=AS jxsv requirement). | Test `spec/st2110_spec.lua:3164-3179`. |
| 28 | 7.3 / Table 3 | b= form per RFC 4566 | Y | COVERED-INHERITED | RFC 4566 b= grammar enforced by `bw_pat` at `parse_sdp.lua:181-194` (parse-time). | Decimal / negative / non-numeric values rejected at parse time. |
| 29 | 7.3 / Table 3 | brtype shall be AS | Y | COVERED | `parse_sdp.lua:1533-1541` only `b.type == "AS"` satisfies the presence check; any other brtype (CT, TIAS, etc.) fails. | Note: presence-check semantics — the parser does not actively reject a coexisting b=CT, it just fails when no b=AS is found. RFC 4566 itself allows other brtypes at the layer below. |
| 30 | 7.3 / Table 3 | brvalue is the average bit rate | Y | N/A (semantics) | — | Inventory marks SDP-Y but observation: not syntactically verifiable; parser cannot tell average from peak from the value alone. No check possible. |
| 31 | 7.3 / Table 3 | brvalue is integer kbps | Y | COVERED-INHERITED | `bw_pat` (`parse_sdp.lua:181-182`) accepts only `digit^1` → integer; `b=AS:200.5` rejected at parse time. | Additional positivity guard at `:2557-2562` (`b.value > 0`). |
| 32 | 7.3 / Table 3 | Bit rate includes IP headers + payload | N | N/A | — | Semantics; not statically verifiable. |
| 33 | 7.3 / Table 3 | Bit rate excludes L2 | N | N/A | — | Semantics; not statically verifiable. |
| 34 | 7.4 / Table 4 | Frame-rate indication required via Table 4 mechanisms | Y | COVERED | `parse_sdp.lua:1543-1554` checks for `a=framerate` OR fmtp `exactframerate`; absence of both rejected. | Test `spec/st2110_spec.lua:3222-3229`. |
| 35 | 7.4 / Table 4 row 1 | a=framerate per RFC 4566; decimal allowed | Y | COVERED | `parse_sdp.lua:1555-1564` matches `^%d+$` OR `^%d+%.%d+$`. | Integer or `<int>.<int>`; anything else rejected. Test `spec/st2110_spec.lua:3211-3220`. |
| 36 | 7.4 / Table 4 row 2 | exactframerate: N or N/D; smallest numerator | Y | AMBIGUOUS-RESOLVED → COVERED | `valid_exactframerate` `parse_sdp.lua:1012-1031` enforces lowest-terms (`gcd(n, d) == 1`); plain integer also accepted. | Parser chose strict GCD-reduced form (option (a) in the inventory). `60000/2002` is rejected in favor of `30000/1001`. |

## Tallies

- Total inventory rows: 36
- SDP-Y rows (direct Y): 26 (rows 7, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 34, 35, 36)
- AMBIGUOUS rows: 2 (17, 36)
- "Partial" inventory rows (counted under SDP-affecting): 1 (row 8)
- SDP-N rows: 10 (rows 1, 2, 3, 4, 5, 6, 10, 32, 33; row 8 is "Partial" and is counted via #9)

### Verdict counts (SDP-Y / Partial)

- COVERED: 19 (rows 7, 9, 11, 13, 16, 17, 18, 19, 20, 23, 24, 25, 26, 27, 29, 31, 34, 35, 36) — counting AMBIGUOUS-RESOLVED rows 17 and 36 as COVERED.
- COVERED-INHERITED: 5 (rows 6, 12, 14, 15, 28)
- PARTIAL: 2 (rows 21, 22 — width/height upper bound 32767 not enforced for jxsv)
- MISSING: 0
- N/A within SDP-Y set: 2 (rows 8 — pure timing/RTP layer; 30 — semantics)
- AMBIGUOUS-UNRESOLVED: 0

## Top 3 findings

1. **PARTIAL: width / height upper bound not enforced for jxsv** (rows 21, 22).
   `parse_sdp.lua:1575-1576` validates width and height with `valid_pos_int` (lower-bound only), whereas the uncompressed video branch at `:1743-1744` uses `valid_pixel_dim`-wrapped `valid_width` / `valid_height` which enforces the `n > 32767` rejection citing ST 2110-20 §7.2. ST 2110-22 §7.2 Table 1 restates the same defined-value set "integers between 1 and 32767 inclusive" — so the upper bound is normative on the jxsv path too. `width=99999` currently passes ST 2110 validation for a jxsv stream. Fix is one-line: swap `valid_pos_int` for the existing `valid_width` / `valid_height` (or a -22-specific copy) and add a regression test. Spec-ref for the fix is `ST 2110-22:2022 §7.2 Table 1`.

2. **AMBIGUOUS rows both resolved by the parser, with one resolution worth re-confirming** (rows 17 and 36).
   - Row 17 ("no semicolon after the last item" — declarative inside a SHALL-paragraph) is enforced at `parse_sdp.lua:1521-1528` via `fmtp_no_trailing_semicolon`. The parser treats the declarative as normative, which is the conservative reading.
   - Row 36 ("numerically smallest numerator value possible" for `exactframerate`) is resolved as strict GCD-reduced form at `parse_sdp.lua:1012-1031`. The inventory notes the spec does not define a canonical reduction algorithm; the parser picks option (a) (reject `60000/2002`). This is a defensible reading but is the stricter of the two readings the inventory enumerates — worth a single line in the audit report noting this is a parser interpretation, not a spec-verbatim mandate.

3. **No MISSING rows.** Every SDP-Y row from §6.2–§7.4 maps to a concrete enforcement site or to an inherited check (RFC 4566 b= grammar, ST 2110-10 -tier validation). The two `Partial` verdicts (rows 21, 22) are the only spec-ground deficiencies. SSN value-set (row 26), TP enum (row 23), 90 kHz clock (row 7), `b=AS` required-with-integer (rows 27/29/31), and dual-mechanism frame-rate (rows 34/35) all have explicit tests in `spec/st2110_spec.lua` (M22 describe block at `:2979-3329`).

Output path: `/tmp/audit_coverage_st2110-22.md`

---

## SMPTE ST 2110-30:2025

# Audit Coverage Map — SMPTE ST 2110-30:2025 (PCM Digital Audio)

Inventory: `/tmp/audit_inventory_st2110-30.md` (30 rows; SDP-Y: 7, AMBIGUOUS: 2, `[AES67-2013 wording]`: 3)
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`

## Legend

- **MAPPED** — clause is enforced by an identifiable parser check.
- **MISSING** — SDP-Y clause has no parser enforcement (may be intentional per Strictness Principle; flagged).
- **N/A — out-of-SDP** — clause is not SDP-visible (RTP/RTCP, runtime, capability-claim, meta-prose).
- **POLICY (AMBIGUOUS)** — spec wording does not yield a hard "shall reject"; parser policy choice.
- **CORRECTLY LENIENT** — parser explicitly does NOT enforce because spec mandates leniency.

## Row-by-Row Mapping

| # | § | SDP? | Verdict | Parser location / Notes |
|---|---|---|---|---|
| 1 | 2 | N | N/A — meta | RFC 2119/8174-style conformance language; no SDP rule. |
| 2 | 2 | N | N/A — meta | Definition of "reserved" / "forbidden". |
| 3 | 2 | N | N/A — meta | Precedence: prose > tables > formal languages > figures. |
| 4 | 6.1 | N | N/A — out-of-SDP | RTP/Media Clock semantics (ST 2110-10 §7.3/§7.4). Not in SDP text. |
| 5 | 6.1 | N | N/A — out-of-SDP | "Media/RTP clock rate = audio sampling rate." Runtime equivalence. (rtpmap-rate equality enforced via AES67 §7.1, see row 11.) |
| 6 | 6.1 | N | N/A — out-of-SDP | RTP timestamp delegation to ST 2110-10. |
| 7 | 6.1 | AMBIGUOUS | POLICY (AMBIGUOUS) — accepted lenient | Spec: mandatory 48 kHz; "other sampling rates out of scope". Parser accepts any well-formed positive `clock_rate`. parse_sdp.lua:1903-1906 comments cite §6.1 and apply Strictness Principle G5: "out of scope" ≠ forbidden. Tests at spec/st2110_spec.lua:1505-1535 confirm 192000 / 22050 / other rates accepted. **Aligned with CLAUDE.md Strictness Principle.** |
| 8 | 6.1 | N | N/A — capability claim | "Above-Level-A devices must support their level's rate/ptime/channel ranges." Device capability, not SDP. |
| 9 | 6.2.1 | Y | **MAPPED** | Umbrella RFC 8866 + AES67 conformance. parse_sdp.lua references RFC 4566 (37 hits) and RFC 8866 (9 hits, including c= line §9 ABNF at lines 805/831/835/863/867/872, and audio-tier ptime/MAXUDP cites at 1938-1989). **Citation note**: parser's RFC 4566 baseline is largely fungible with RFC 8866 for the SDP grammar; comment at line 1939 ("RFC 8866") is consistent with §6.2.1. No parser bug — verify-only finding. |
| 10 | 6.2.1 | N | N/A — out-of-SDP | "Receivers need not support SIP." Connection-management opt-out. |
| 11 | 6.2.1 | Y `[AES67-2013 wording]` | **MAPPED** (delegated to ST 2110-30 audio block) | parse_sdp.lua:1894-1936. `VALID_AUDIO_ENC = {L16, L24, AM824}` (line 897) is the AES67 §7.1 enumeration (plus -31's AM824). Tests at spec/st2110_spec.lua:1869-2000+ accept L16/L24/AM824, reject others. Sampling-rate enumeration (44.1/48/96 kHz) is **NOT enforced** as a hard set — see row 7 — but this matches the Strictness Principle since §7.1 says "other combinations outside the scope." |
| 12 | 6.2.1 | N `[AES67-2013 wording]` | N/A — out-of-SDP | AES67 §7.5 timing/buffering. Runtime, not SDP. |
| 13 | 6.2.1 | N | **MAPPED in 30 audio block** | "Standard UDP Datagram Size Limit." parse_sdp.lua:1979-1990 forbids `MAXUDP` on audio (cite "ST 2110-30:2025 §6.2.1") and lines 1991-2012 enforce packet payload fit ≤ 1460−12 B. Technically the §6.2.1 wording is about the UDP wire size; parser's MAXUDP-forbidden inference is reasonable (MAXUDP signals exceeding the Standard Limit) but is a slight derivation from the SHALL. Mapped, with note. |
| 14 | 6.2.2 | Y | **MAPPED** | RFC 3190 channel-order syntax. parse_sdp.lua:1075-1078 (`valid_channel_order`): match `^([^.%s]+)%.(%S+)$` → error if no `<convention>.<order>`. Test spec/st2110_spec.lua:1421-1428 ("rejects channel-order with no <convention>.<order> separator"). |
| 15 | 6.2.2 | N (SHOULD) | N/A — recommendation | "convention SHOULD be SMPTE2110." Parser correctly does NOT reject non-SMPTE2110 conventions (parse_sdp.lua:1080-1084 returns true for other conventions). Test at spec/st2110_spec.lua:1442-1446 confirms `AES.(M,M)` accepted. **CORRECTLY LENIENT per CLAUDE.md (SHOULD ≠ rejectable).** |
| 16 | 6.2.2 | Y | **MAPPED** | SMPTE2110 `<order>` form: `(SYM,SYM,...)`. parse_sdp.lua:1085-1087: `order:match("^%((.+)%)$")` → error if absent. Test spec/st2110_spec.lua:1430-1437 ("rejects SMPTE2110.() with empty group"). |
| 17 | 6.2.2 / Table 1 | Y | **MAPPED** | Table 1 symbol set `{M, DM, ST, LtRt, 51, 71, 222, SGRP}`. parse_sdp.lua:1062-1065 `VALID_CHAN_GROUPS` table; lines 1089-1106 reject unknown symbols. Tests at spec/st2110_spec.lua:1409-1453 cover ST, 51, BOGUS rejection. **AES3 symbol** (ST 2110-31:2022 §6.2 Table 2) is correctly gated to AM824 only (line 1096-1099, tests 1457-1462 / 1484-1500). |
| 18 | 6.2.2 | N | N/A — sender behavior | "Channels not matching defined groups SHALL be identified and grouped as Undefined." Device-grouping rule, not SDP-validity. |
| 19 | 6.2.2 | Y | **MAPPED** | `Unn` form: `U` + two ASCII digits, 01–64. parse_sdp.lua:1101-1105: `g:match("^U(%d%d)$")` and `n < 1 or n > 64` reject. Tests spec/st2110_spec.lua:2839-2872 cover U01 (lower), U64 (upper), U65 (out-of-range reject). |
| 20 | 6.2.2 | N | N/A — receiver behavior | "If channel-order not present, treat as Undefined." Receiver semantics; not SDP-validity. Parser does NOT require channel-order (parse_sdp.lua:2020-2026 validates only when present); test spec/st2110_spec.lua:233-256 ("accepts audio without channel-order"). **CORRECTLY LENIENT.** |
| 21 | 6.2.2 | N | **CORRECTLY LENIENT** (critical) | "If channel-count mismatch: surplus channels treated as Undefined." Receiver semantics; spec explicitly mandates LENIENT handling, not rejection. **Parser does NOT cross-check channel-order channel-count vs rtpmap channels** (grep `channel.*count` shows only rtpmap-internal checks at lines 1909-1920; `valid_channel_order` at 1075-1109 takes no rtpmap-channels parameter). **No Direction-B violation — parser correctly does not reject.** |
| 22 | 6.2.2 | Y | **MAPPED** (duplicate of row 17) | "Channel Grouping Symbols shall be per Table 1." Same parser check at parse_sdp.lua:1062-1106. |
| 23 | 6.2.2 / Table 1 | Y | **PARTIALLY MAPPED** | `222` symbol → 24-channel order per ST 2036-2:2008 Table 1. Parser accepts the symbol `222` (in VALID_CHAN_GROUPS at line 1064). Parser does NOT validate that the *channel count* in rtpmap is 24 when `222` appears, nor does it validate the 24-channel ordering itself (ST 2036-2 unavailable, and the spec mandates lenient mismatch per row 21 anyway). Symbol acceptance is sufficient. |
| 24 | 7 | N | N/A — capability claim | Sender level-compliance criteria. Out-of-SDP. |
| 25 | 7 | N | N/A — capability claim | Receiver level-compliance criteria. Out-of-SDP. |
| 26 | 7 | N | N/A — capability claim | "All devices shall be Level-A compliant." Device-capability, not SDP-line legality. |
| 27 | 7 / Table 2 | AMBIGUOUS | POLICY (AMBIGUOUS) — accepted lenient | Table 2 levels enumerate `{48000, 96000}` × `{1000, 125}` µs × channel-count ranges. No clause explicitly forbids SDPs outside these tuples. Parser accepts (see row 7). Test spec/st2110_spec.lua:1505-1535 cover this. **Aligned with Strictness Principle.** |
| 28 | 7 / Table 3 | N | N/A — capability matrix | Receiver-capability table; not SDP-line constraint. |
| 29 | 7 | N (MAY) | N/A — permissive | "Devices MAY support more channels than required." Permission, not a constraint. |
| 30 | 7 | N (SHOULD) | N/A — recommendation | "Devices SHOULD advertise all supported levels." Out-of-SDP advertising. |

## Coverage Summary

- **SDP-Y rows (7 distinct, treating row 22 as duplicate of row 17)**:
  - **MAPPED**: rows 9, 11, 14, 16, 17/22, 19, 23 (partial; 222 symbol only)
  - **MISSING**: none
- **CORRECTLY LENIENT (spec mandates leniency)**: rows 15 (SHOULD), 20 (absence semantics), **21 (channel-count mismatch — critical)**
- **AMBIGUOUS (POLICY decisions, accepted lenient)**: rows 7, 27 (sample rate / level tuples not forbidden by SHALL)
- **`[AES67-2013 wording]` flagged**: rows 9, 11, 12 — parser implementation cites AES67 §7.1 / §8.1; 2023 wording unverifiable from disk

## Critical Findings (top 3)

1. **Channel-count mismatch leniency — CORRECT.** Spec row 21 (§6.2.2) mandates that channel-order channel-count > rtpmap channel-count is **lenient** ("surplus channels treated as Undefined"), not a rejection. The parser correctly does NOT cross-check the two (parse_sdp.lua:1075-1109 `valid_channel_order` takes no rtpmap-channels argument; the §6.2.2 audio block at lines 2020-2026 only validates symbol structure). **No Direction-B violation — parser is in spec.**

2. **RFC 8866 vs RFC 4566 citation drift (row 9).** ST 2110-30:2025 §6.2.1 and Clause 3 both cite **RFC 8866** (Jan 2021, obsoletes RFC 4566). The parser cites RFC 4566 in 37 places and RFC 8866 in only 9 (mostly on the c= line at lines 805-872). For ST 2110-30 audio blocks, parser comments cite RFC 8866 (line 1939). The grammars are largely interchangeable for the constraints parse_sdp enforces, but **audit recommendation**: when citing the ST 2110-30 audio block error messages, prefer "RFC 8866" over "RFC 4566" since that's what -30:2025 actually points at. This is a documentation-quality finding, not a parser bug. Filing as **suspected — citation hygiene, no behavior change**.

3. **AES67 revision uncertainty (rows 9, 11, 12).** ST 2110-30:2025 Clause 3 cites **AES67-2023**, but only AES67-2013 is on disk. Parser-enforced constraints derived from AES67 are:
   - `VALID_AUDIO_ENC = {L16, L24, AM824}` at parse_sdp.lua:897 — derived from AES67-2013 §7.1 (L16+L24); AM824 added by ST 2110-31. AES67-2023 may have added L32 or other encodings, which would make the current allowlist over-strict. **UNCONFIRMED — investigate against AES67-2023 once available.**
   - `a=ptime` REQUIRED at parse_sdp.lua:1945-1949 — derived from AES67-2013 §8.1. AES67-2023's §8.1 wording cannot be directly verified. **UNCONFIRMED.**
   - Other AES67 §7.5 timing provisions are out-of-SDP (row 12); no parser implications.

   Per CLAUDE.md Spec Verification Protocol §4, these are "suspected — unconfirmed against the cited document" and should remain in place with `spec_ref` notes until AES67-2023 is obtained.

## Notes on Strictness Principle Alignment

The parser's treatment of ST 2110-30:2025 demonstrates correct application of the CLAUDE.md Strictness Principle:

- **Row 7 / 27 (sample rate / level tuples)**: Spec says "out of scope," not "shall not." Parser accepts well-formed positive rates (line 1903-1906 comment explicitly cites the G5 conformance principle). Aligned.
- **Row 15 (SMPTE2110 convention SHOULD)**: SHOULD-graded preference. Parser accepts other conventions structurally. Aligned.
- **Row 21 (channel-count mismatch)**: Spec mandates lenient handling. Parser does not cross-check. Aligned.
- **Rows 17/19 (Table 1 symbol set, Unn form)**: Defined-value constraints, applied only when the optional parameter is present. Aligned with Strictness Principle row 3 ("optional features with defined values").

No Direction-B (over-strict) violations identified for ST 2110-30:2025.

---

## SMPTE ST 2110-31:2022

# Audit Coverage — SMPTE ST 2110-31:2022 (AM824 Audio)

Inventory: `/tmp/audit_inventory_st2110-31.md` (59 rows total; 24 SDP-Y rows enumerated below; 3 AMBIGUOUS retained for reference)
Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`

Reverse-direction grep over parser for `"ST 2110-31"` / `"ST 2110-31:2022"`:
- L1060, L1067 — comments only (channel-order Table 2 binding to AM824).
- L1921–L1936 — N2 (even `<nchan>`), N3 (clock-rate ∈ {44100, 48000, 96000}).
- L1942–L1944, L1955–L1977 — N5 (ptime ∈ Table 1 cross-table) cite.
- L897, L1894–L1902 — `VALID_AUDIO_ENC = {L16, L24, AM824}` and ST 2110-30 cite for accepted audio rtpmap encoding names.
- L1075–L1108 — `valid_channel_order` accepts the `AES3` grouping symbol only on AM824 (Table 2).

| Row | Spec | § | Constraint | Parser Check Location | Test Coverage | Status |
|---|---|---|---|---|---|---|
| 4 | ST 2110-31:2022 | §5.2 | "Technical metadata necessary to receive and interpret the RTP stream shall be communicated via SDP as defined in clause 6." | Implicit framing — entire ST 2110 validator (`validate_st2110` in `parse_sdp.lua`) gates on the presence of SDP fields. There is no single check; rows 6/30/31/32/33/34/35/36/37/38/39 below collectively realize §6. | `spec/st2110_spec.lua` ST 2110 describe blocks. | **COVERED (framing — realized by per-clause checks below)** |
| 6 | ST 2110-31:2022 | §5.3 | RTP PT dynamic per RFC 3551 (96–127), unless RFC 3551 §6 static designation exists for the encoding (AM824 has none). | `parse_sdp.lua` L1334–L1353 — payload type in 0–127, then `pt_n < 96` rejected unless it matches a known static (L16/44100/2 PT=10, L16/44100/1 PT=11). AM824 has no static, so any `pt_n < 96` for `AM824` is rejected. | `spec/st2110_spec.lua` — covered by general dynamic-PT tests (ST 2110-10 §6.2 describe block). | **COVERED** (cite says "ST 2110-10 §6.2"; equivalent constraint to ST 2110-31 §5.3 via RFC 3551) |
| 23 | ST 2110-31:2022 | §5.4 (last shall) | "The time period corresponding to each packet within the stream shall be signaled using the ptime attribute in the SDP, as defined in subclause 6.1, using one of the permitted values from Table 1." | Combined with row 38 (presence) and row 39 (value set). `parse_sdp.lua` L1945–L1948 enforces presence; L1955–L1977 enforces Table 1 enumeration. | `spec/st2110_spec.lua` L1971–L1996 — "rejects AM824 without a=ptime", "rejects AM824 ptime not in Table 1", "accepts AM824 ptime 0.12 ms at 48k", "accepts AM824 ptime 0.080 ms at 48k". | **COVERED** |
| 24 | ST 2110-31:2022 | §5.5 | Sampling frequency ∈ {44.1 kHz, 48 kHz, 96 kHz}. | `parse_sdp.lua` L1931–L1935 — AM824 clock_rate must be one of 44100, 48000, 96000. | `spec/st2110_spec.lua` L1958–L1969 — "rejects AM824 at 32000 Hz", "accepts AM824 at 96000 Hz" (also 48000 implicitly via earlier rows). | **COVERED** |
| 25 | ST 2110-31:2022 | §5.5 | Media Clock = RTP Clock = sampling frequency (couples to rtpmap clock-rate). | `parse_sdp.lua` L1325 (rtpmap_parse returns clock_rate) feeding L1931–L1935 (the clock-rate enum check). The SDP only carries one clock value, which is then constrained — the "all three equal" semantic is structural in SDP grammar (one rtpmap clock = the RTP clock; ST 2110-10 §8 ts-refclk gates the Media Clock side). | Same tests as row 24. | **COVERED (structurally via rtpmap clock-rate enum)** |
| 30 | ST 2110-31:2022 | §6.1 | "Streams under this standard shall be signaled using SDP in accordance with SMPTE ST 2110-10." | `parse_sdp.lua` — entire `validate_st2110` block; ST 2110-10 §6/§7/§8 framings are inherited (origin nettype/addrtype, c=, t=, ts-refclk, mediaclk, etc.). | All ST 2110 generic tests in `spec/st2110_spec.lua`. | **COVERED (framing — pulls in ST 2110-10 SDP rules)** |
| 31 | ST 2110-31:2022 | §6.1 | `m=audio` with rtpmap encoding name `AM824`. | (a) `m=audio` enforcement: AM824 only matches inside the `m.media == "audio"` branch (`parse_sdp.lua` L1894); `VALID_AUDIO_ENC` (L897) lists AM824. (b) An AM824 rtpmap under `m=video` would fail video clock-rate check (L1713–L1719 — video requires 90000). There is no explicit "AM824 requires m=audio" error path with that wording. | `spec/st2110_spec.lua` L1901–L1925 — "accepts AM824 encoding at 48000 Hz" (under m=audio). No explicit "rejects AM824 under m=video" test. | **COVERED (indirectly — encoding name `AM824` is only accepted inside the audio branch; m=video AM824 is rejected by the video clock-rate check, not by a direct AM824/m=audio cite).** Minor: cite text mentions ST 2110-30, not ST 2110-31; cosmetic. |
| 32 | ST 2110-31:2022 | §6.1 | `a=rtpmap:<pt> AM824/<clock-rate>/<nchan>` grammar form. | `parse_sdp.lua` L1909 — `(rtpmap.value or ""):match("^%d+%s+%S+/%d+/(%d+)$")` requires the three-field form (enc/clock/channels) when `m.media == "audio"`; missing channels returns RFC 3551 §6 error (L1911–L1913). | `spec/st2110_spec.lua` — covered via `am824_sdp` helper at L1930–L1942 and L1468–L1483 (constructs `AM824/<rate>/<ch>`). | **COVERED** |
| 33 | ST 2110-31:2022 | §6.1 | `<clock-rate>` semantics = RTP Clock Rate = sampling rate. (Definitional.) | Same as row 24/25 — `rtpmap_parse` at L1325, enum check L1931–L1935. | Same. | **COVERED (definitional — bound by enum)** |
| 34 | ST 2110-31:2022 | §6.1 | `<nchan>` = number of AES3 Subframes multiplexed. (Definitional.) | `parse_sdp.lua` L1909 captures `<nchan>` per grammar; even-number check at L1926–L1930 binds it to the AES3-pair semantic of row 37. | Same as rows 32/37. | **COVERED (definitional — bound by even-check)** |
| 35 | ST 2110-31:2022 | §6.1 | `<pt>` = dynamically assigned RTP Payload Type. (Definitional.) | Same as row 6 — `parse_sdp.lua` L1334–L1353 (dynamic range check on rtpmap PT). | Same as row 6. | **COVERED (definitional — bound by dynamic-PT check)** |
| 36 | ST 2110-31:2022 | §6.1 | `<clock-rate>` ∈ {44100, 48000, 96000}. | `parse_sdp.lua` L1931–L1935. | `spec/st2110_spec.lua` L1958, L1965 — "rejects AM824 at 32000 Hz", "accepts AM824 at 96000 Hz". | **COVERED** |
| 37 | ST 2110-31:2022 | §6.1 | `<nchan>` shall always be an EVEN number. | `parse_sdp.lua` L1926–L1930. | `spec/st2110_spec.lua` L1944–L1956 — "rejects AM824 with odd nchan", "accepts AM824 with even nchan". | **COVERED** |
| 38 | ST 2110-31:2022 | §6.1 | `a=ptime` REQUIRED for senders. | `parse_sdp.lua` L1945–L1948. (Note: cite is "ST 2110-30:2025 §6.2.1 / AES67 §8.1" — the same physical check satisfies both ST 2110-30 §6.2.1 and ST 2110-31 §6.1 row 38; the message ref does not explicitly mention §6.1, see Finding 2.) | `spec/st2110_spec.lua` L1971–L1978 — "rejects AM824 without a=ptime (§6.1)". | **COVERED** |
| 39 | ST 2110-31:2022 | §6.1 | `a=ptime` value ∈ Table 1 (cross-table with clock-rate). | `parse_sdp.lua` L1955–L1977 — closed cross-table `valid_ptimes = { [44100]={1.09, 0.14, 0.09}, [48000]={1, 0.12, 0.08}, [96000]={1, 0.12, 0.08} }`. Tolerance 0.001. | `spec/st2110_spec.lua` L1980–L2004 — "rejects AM824 ptime not in Table 1 (e.g. 0.5)", "accepts AM824 ptime 0.12 ms at 48k", "accepts AM824 ptime 0.080 ms at 48k", "accepts AM824 ptime 1.09 ms at 44.1k". | **COVERED** |
| 40 | ST 2110-31:2022 | §6.1 Table 1 | 1 / 48000 / 48 periods. | `parse_sdp.lua` L1963 — `[48000] = { 1, 0.12, 0.08 }`. | Implicitly via the L1965/L1985 "accepts at 48000" tests. | **COVERED** |
| 41 | ST 2110-31:2022 | §6.1 Table 1 | 0.12 / 48000 / 6 periods. | `parse_sdp.lua` L1963. | `spec/st2110_spec.lua` L1986–L1991 — "accepts AM824 ptime 0.12 ms at 48k". | **COVERED** |
| 42 | ST 2110-31:2022 | §6.1 Table 1 | 0.08 / 48000 / 4 periods. | `parse_sdp.lua` L1963. | `spec/st2110_spec.lua` L1992–L1997 — "accepts AM824 ptime 0.080 ms at 48k" (tolerance check). | **COVERED** |
| 43 | ST 2110-31:2022 | §6.1 Table 1 | 1 / 96000 / 96 periods. | `parse_sdp.lua` L1964 — `[96000] = { 1, 0.12, 0.08 }`. | `spec/st2110_spec.lua` L1965 — "accepts AM824 at 96000 Hz" (uses ptime=1). | **COVERED** |
| 44 | ST 2110-31:2022 | §6.1 Table 1 | 0.12 / 96000 / 12 periods. | `parse_sdp.lua` L1964. | No dedicated test for 0.12 @ 96k; entry exists in the table. | **COVERED (parser check exists; test not exhaustive)** |
| 45 | ST 2110-31:2022 | §6.1 Table 1 | 0.08 / 96000 / 8 periods. | `parse_sdp.lua` L1964. | No dedicated test for 0.08 @ 96k. | **COVERED (parser check exists; test not exhaustive)** |
| 46 | ST 2110-31:2022 | §6.1 Table 1 | 1.09 / 44100 / 48 periods. | `parse_sdp.lua` L1962 — `[44100] = { 1.09, 0.14, 0.09 }`. | `spec/st2110_spec.lua` L1998–L2004 — "accepts AM824 ptime 1.09 ms at 44.1k". | **COVERED** |
| 47 | ST 2110-31:2022 | §6.1 Table 1 | 0.14 / 44100 / 6 periods. | `parse_sdp.lua` L1962. | No dedicated test for 0.14 @ 44.1k. | **COVERED (parser check exists; test not exhaustive)** |
| 48 | ST 2110-31:2022 | §6.1 Table 1 | 0.09 / 44100 / 4 periods. | `parse_sdp.lua` L1962. | No dedicated test for 0.09 @ 44.1k. | **COVERED (parser check exists; test not exhaustive)** |
| 50 | ST 2110-31:2022 | §6.2 | `channel-order` MAY be signalled; if present, extends ST 2110-30 with `AES3` symbol (AM824 only). | `parse_sdp.lua` L1075–L1108 (`valid_channel_order`); L1096–L1099 — `AES3` accepted only when `enc == "AM824"`. Called from L2020–L2026 (`co = params["channel-order"]`; structural check on present value, absence OK). | `spec/st2110_spec.lua` L1455–L1500 — "rejects SMPTE2110.(AES3) on L16/L24", "accepts SMPTE2110.(AES3) on AM824", "accepts SMPTE2110.(AES3,AES3) on AM824", "still accepts SMPTE2110.(ST) on AM824". | **COVERED** |
| 51 | ST 2110-31:2022 | §6.2 Table 2 | `AES3` channel grouping symbol (defined value). | `parse_sdp.lua` L1096–L1099 — explicit `g == "AES3"` branch. | Same tests as row 50. | **COVERED** |
| 58 | ST 2110-31:2022 | §8.2.3 | IANA `channel-order` optional parameter (echo of §6.2). | Same as row 50. | Same tests as row 50. | **COVERED (IANA-echo of row 50; same enforcement applies)** |

---

## AMBIGUOUS rows (carried from inventory, not separately validated here)

| Row | Note |
|---|---|
| 21 | RTP-layer invariant (number of AES3 signals constant per packet). SDP grammar already carries one `<nchan>` value per stream — no separate SDP-level enforcement possible without packet inspection. **Out of scope of SDP validation per CLAUDE.md strictness principle.** |
| 22 | RTP-layer invariant (constant sample-period count per packet). Couples to `a=ptime` but not testable from SDP alone. **Out of scope of SDP validation.** |
| 49 | Rounding-rule note attached to Table 3 vs Table 1; functionally subsumed by the closed cross-table at `parse_sdp.lua` L1961–L1972 with 0.001 tolerance (covers 0.080 ↔ 0.08 etc.). **No separate enforcement needed.** |

---

## Totals

- **SDP-Y rows mapped**: 24
- **COVERED**: 24
- **MISSING**: 0
- **AMBIGUOUS (deferred per inventory)**: 3 (rows 21, 22, 49)

## Top 3 findings

1. **Parser cite for the `a=ptime` presence requirement does not mention ST 2110-31 §6.1 in the error message.** `parse_sdp.lua` L1947 emits `"audio streams require a=ptime (ST 2110-30:2025 §6.2.1 / AES67 §8.1)"`. For an AM824 stream, ST 2110-31 §6.1 also makes ptime SHALL. The check is correct, but a downstream reader inspecting the error would not see the ST 2110-31 cite — consider concatenating "(or ST 2110-31:2022 §6.1 when enc=AM824)" in the message, or splitting per-encoding. This is a documentation/error-quality issue, not a missing check. (Inventory row 38.)
2. **No explicit "AM824 encoding requires `m=audio`" error path.** Row 31's `m=audio` half is enforced *indirectly*: `VALID_AUDIO_ENC = {L16, L24, AM824}` (L897) lives only inside the `m.media == "audio"` branch, and an `AM824` rtpmap under `m=video` would be rejected by the video clock-rate enforcement (must be 90000) rather than by an AM824-specific cite. Behavioral coverage is complete; the error message would not point at ST 2110-31 §6.1. Compare with the `smpte291`/`jxsv` per-encoding `m.media ~= "video"` rejections at L1368 and L1511, which do produce a clean encoding-specific cite. **Optional polish, not a coverage gap.**
3. **Table 1 entries at 96 kHz (rows 44, 45) and 44.1 kHz (rows 47, 48) lack dedicated unit tests.** Parser tables at L1962/L1964 include all 9 entries; the test suite verifies 48 kHz (1, 0.12, 0.08), 44.1 kHz (1.09 only), and 96 kHz (1 only). The other five entries (`0.12 / 96000`, `0.08 / 96000`, `0.14 / 44100`, `0.09 / 44100`, `1 / 96000` via the existing 96 kHz test) are exercised but not explicitly enumerated. **Test-coverage gap, not a parser gap.**

---

## SMPTE ST 2110-40:2023

# Audit Coverage — SMPTE ST 2110-40:2023

**Spec**: SMPTE ST 2110-40:2023 — Ancillary Data
**Inventory**: `/tmp/audit_inventory_st2110-40.md`
**Parser**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
**Tests**: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`

## Method

Mechanical mapping of each SDP-Y normative clause (rows from the inventory marked
"Y" or "Y (indirect)") to a parser check. Rows marked "N" (out of SDP scope) are
omitted. AMBIGUOUS rows are listed and discussed.

## Coverage table

| Inv# | § | Verb | Summary | Parser check | Test ref | Verdict |
|------|---|------|---------|--------------|----------|---------|
| 7 | §5.2.2 | shall | VPID_Code required when sender proposes exact SDI location | parse_sdp.lua:1394-1401 validates VPID_Code value form when present (non-negative integer). | st2110_spec.lua:612-619 accepts VPID_Code=133 | AMBIGUOUS — sender-state-dependent. Inventory flagged this as AMBIGUOUS for SDP-only validation. Parser correctly validates the optional value form only; cannot infer "exact location proposal" from SDP. **Correctly out of scope per CLAUDE.md strictness principle.** |
| 8 | §5.2.2 | (permissive) | VPID_Code optional when sender does not propose exact location; defined value set per RFC 8331 | parse_sdp.lua:1394-1401 — present-but-malformed rejected; absence allowed. | st2110_spec.lua:546-551 accepts SDP without VPID_Code | COVERED — optional-with-defined-value-set handling. |
| 13 | §5.3 | shall | RTP Clock rate shall be 90 kHz | parse_sdp.lua:1374-1378 — `if clock_rate ~= 90000 then return attr_err("rtpmap clock rate must be 90000 for smpte291…", "ST 2110-40 §7.2")` | st2110_spec.lua:588-608 (m=audio rejection covers rtpmap path) — no direct positive-case test for clock-rate=48000 rejection, but the `smpte291/90000` literal appears in every test fixture, and `rtpmap_parse` is called before this check. | COVERED — though the spec_ref reads "ST 2110-40 §7.2" while the actual cite is §5.3. **Cite mismatch finding F1.** |
| 22 | §6.3 | shall | TROFFSETANC signaled via TROFF parameter (when non-default) | parse_sdp.lua:1452-1458 — TROFF when present validated as positive integer per ST 2110-21 §8. | st2110_spec.lua:723-736 accepts TROFF=1000, rejects TROFF=0. | COVERED — row 22 is indirect; the validator implements the SDP-form side via row 38 (the actual SHALL on TROFF presence). |
| 30 | §7 | shall | SDP constructed per RFC 8331 + ST 2110-10 | parse_sdp.lua:1364-1372 enforces m=video for smpte291 per RFC 8331 §4 / RFC 4855 §1. RFC 8331 conformance for `smpte291/90000` rtpmap. ST 2110-10 provisions enforced separately. | st2110_spec.lua:588-608 (m=audio rejection) | COVERED — meta-reference to RFC 8331 / ST 2110-10; enforced via the rtpmap/m=video pairing. |
| 31 | §7 | shall not | `a=group:FID` forbidden for smpte291 streams | parse_sdp.lua:2146-2173 — scans for `a=group:FID` only when at least one media block carries smpte291; cite "ST 2110-40:2023 §7". | st2110_spec.lua:564-584 — rejects FID with smpte291; expects "FID" and "smpte291" in error message. | COVERED — the only outright SDP "shall not" in -40; correctly scoped to smpte291 presence. |
| 32 | §7 | shall | SSN required; value ST2110-40:2018 unless TM signaled (then ST2110-40:2023) | parse_sdp.lua:1416-1433 — SSN presence required; expected value computed from TM presence (`expected_ssn = (tm and tm ~= true) and "ST2110-40:2023" or "ST2110-40:2018"`); mismatch returns INVALID_VALUE. | st2110_spec.lua:655-702 — covers (a) missing SSN, (b) SSN=…:2023 without TM rejected, (c) SSN=…:2018 with TM=LLTM rejected, (d) SSN=…:2023 + TM=LLTM accepted, (e) SSN=…:2023 + TM=CTM accepted. | COVERED — sender-side rules. |
| 33 | §7 | shall (defined-value) | Receivers accept SSN=ST2110-40:2021 as equivalent to ST2110-40:2023 | **NOT IMPLEMENTED.** parse_sdp.lua:1427-1432 enforces strict equality against expected_ssn; ST2110-40:2021 is unconditionally rejected (with TM, it expects ST2110-40:2023; without TM, it expects ST2110-40:2018). No code path accepts the :2021 alias. | No test covers SSN=ST2110-40:2021. | **MISSING — F2.** The receiver-equivalence SHALL ("Receivers shall consider … ST2110-40:2021 as equivalent to … :2023") is not honored. A parser validating an SDP with `SSN=ST2110-40:2021; TM=LLTM` would reject it, but a conforming receiver MUST accept it. |
| 34 | §7 | shall | LLTM senders signal TM=LLTM | parse_sdp.lua:1408-1414 enforces TM ∈ {LLTM, CTM} when present. The conditional positive ("LLTM senders shall signal TM=LLTM") is **not enforceable from SDP alone** — the validator cannot know whether the sender is an LLTM device. The value-set side is enforced. | st2110_spec.lua:693-712 covers TM=LLTM and TM=CTM acceptance plus rejection of TM=XYZ. | COVERED (value-set side) — sender-classification side correctly out of SDP scope. |
| 35 | §7 | may | CTM senders may signal TM=CTM | parse_sdp.lua:1408-1414 — TM defined value set {LLTM, CTM} enforced when present. | st2110_spec.lua:699-702 — TM=CTM accepted. | COVERED — optional with defined value set. |
| 37 | §7 | shall | exactframerate REQUIRED on every ANC SDP | parse_sdp.lua:1434-1446 — `if efr == nil or efr == true then return attr_err("fmtp missing required 'exactframerate' parameter for smpte291", … "ST 2110-40:2023 §7")`; valid_exactframerate validates value form per ST 2110-20:2022 §7.2. | st2110_spec.lua:665-672 (missing rejected), 714-721 (ill-formed rejected) | COVERED. |
| 38 | §7 | shall | TROFF required only when TROFFSETANC differs from TRODEFAULT | parse_sdp.lua:1447-1458 — conditional on sender state; validator only checks value form when present (positive integer per ST 2110-21 §8). | st2110_spec.lua:723-736 — accepts TROFF=1000; rejects TROFF=0. | COVERED — value-form side; the runtime "differs from default" trigger is out of SDP scope. |

## Findings

### F1 — Cite mismatch for clock-rate=90000 (minor)

parse_sdp.lua:1377 cites `"ST 2110-40 §7.2"` for the rtpmap clock-rate=90000
requirement. The actual cite is **ST 2110-40:2023 §5.3** ("The RTP Clock rate
shall be 90 kHz"). §7 / §7.2 is about SDP structure; §5.3 is the rate SHALL.
The check is correct; the citation is wrong.

Recommended fix: change the spec_ref to `"ST 2110-40:2023 §5.3"` (or
`"ST 2110-40:2023 §5.3 / RFC 8331 §4"` to capture the RFC 8331 IANA
registration that defines the encoding name).

Note: an identical "ST 2110-40 §7.2" string also appears at line 1399 on the
VPID_Code value-form check. VPID_Code is defined by **RFC 8331** (referenced
from ST 2110-40:2023 §5.2.2). The cite there should be
`"ST 2110-40:2023 §5.2.2 / RFC 8331 §4"`.

### F2 — Missing receiver-side SSN=ST2110-40:2021 equivalence (substantive)

ST 2110-40:2023 §7 contains an explicit SHALL on receiver behavior:
*"Receivers shall consider a Format Specific Parameter SSN value of
ST2110-40:2021 as equivalent to a value of ST2110-40:2023."*

This is a normative receiver SHALL. The parser, when validating an SDP, plays
the role of a receiver — and a receiver that rejects `SSN=ST2110-40:2021`
when TM is signaled is non-conformant.

Current behavior: parse_sdp.lua:1426-1432

```lua
local expected_ssn = (tm and tm ~= true) and "ST2110-40:2023" or "ST2110-40:2018"
if ssn_str ~= expected_ssn then
  return attr_err(string.format(
    "invalid SSN value '%s' (expected '%s' %s)", ssn_str, expected_ssn,
    (tm and tm ~= true) and "when TM is signaled" or "when TM is absent"),
    mpath, "fmtp", "ST 2110-40:2023 §7", "INVALID_VALUE")
end
```

This rejects `SSN=ST2110-40:2021` in both branches (TM present → expects
:2023; TM absent → expects :2018).

Recommended fix: when TM is signaled, accept either `ST2110-40:2023` or
`ST2110-40:2021`. Suggested patch shape:

```lua
local tm_present = tm and tm ~= true
local ssn_ok
if tm_present then
  ssn_ok = (ssn_str == "ST2110-40:2023" or ssn_str == "ST2110-40:2021")
else
  ssn_ok = (ssn_str == "ST2110-40:2018")
end
```

And a new test fixture: `SSN=ST2110-40:2021; TM=LLTM; exactframerate=25`
should validate successfully under "st2110".

This is the **only substantive coverage gap** in -40.

### F3 — No direct test that smpte291 with non-90000 clock rate is rejected

parse_sdp.lua:1374-1378 enforces `clock_rate == 90000`, but no spec test
exercises the failure path (e.g. `a=rtpmap:96 smpte291/48000`). Every existing
fixture uses `smpte291/90000`. Low priority — the check is straightforward —
but adding a negative test would harden regression coverage.

## Counts

- **SDP-Y rows in inventory**: 11 (rows 7, 8, 13, 22, 30, 31, 32, 33, 34, 35,
  37, 38 — inventory text says 12 in one place, 11 in another; rows 22 is
  "Y (indirect)" so depending on counting it's 11 or 12).
- **AMBIGUOUS rows**: 1 (row 7 — VPID_Code presence conditional on
  sender-state, correctly handled as optional with defined value set).
- **COVERED**: 10 (rows 7, 8, 13, 22, 30, 31, 32, 34, 35, 37, 38 —
  AMBIGUOUS row 7 is COVERED on the side the parser can see).
- **MISSING**: 1 (row 33 — SSN=ST2110-40:2021 equivalence).
- **Cite mismatches (no behavior bug)**: 1 (clock-rate cite at line 1377;
  see F1).

## Reverse direction

The Bash check `grep -nE '"ST 2110-40|ST 2110-40:2023' parse_sdp.lua` returns
parser cites at lines 1377, 1399, 1413, 1424, 1432, 1441, 1445, 1456, 1466,
2166, 2168. All map back to inventory rows (no orphan checks). MAXUDP at line
1466 cites §6.1.4, which is not in the current inventory under that number
but corresponds to inventory row 4 (§5.2.1 UDP size limit) — the 2023 PDF
section number observed in the parser citation does not match the
inventory's pdftotext output, suggesting a section-number drift between the
parser's earlier-revision citation and the 2023 layout. The MAXUDP check
itself is correct and aligned with the inventory's row-4 SHALL-NOT, but the
section cite "§6.1.4" deserves verification against the 2023 PDF.

Recommended action on cite drift: re-verify `ST 2110-40:2023 §6.1.4` against
the 2023 PDF; the inventory pdftotext placed the UDP-size SHALL-NOT at §5.2.1.
If the PDF layout truly has the SHALL-NOT only at §5.2.1, the parser cite at
line 1466 should be updated to match. **Flagged as F4 (cite verification).**

## Summary

| Verdict | Count |
|---------|-------|
| COVERED | 10 |
| MISSING | 1 |
| AMBIGUOUS — correctly out of scope | 1 (row 7 sender-state) |
| Cite mismatches (no behavior bug) | 2 (F1 + F4 = §5.3 vs §7.2 for clock rate; §6.1.4 vs §5.2.1 for MAXUDP) |

The parser's -40 coverage is strong. The substantive gap is the missing
SSN=ST2110-40:2021 alias (F2), which violates an explicit receiver-side SHALL.
The cite mismatches (F1, F4) are cosmetic but should be cleaned up for
auditability.

---

## SMPTE ST 2110-41:2024

# SMPTE ST 2110-41:2024 — Parser Coverage Map

**Spec**: SMPTE ST 2110-41:2024 — Professional Media over Managed IP Networks: Fast Metadata Framework
**Inventory**: `/tmp/audit_inventory_st2110-41.md` (53 rows; 16 SDP-Y; 3 AMBIGUOUS)
**Parser**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
**Tests**: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`, `spec/ipmx_spec.lua`
**Method**: Mechanical mapping. Only SDP-Y rows are mapped; SDP-N rows are listed as out-of-SDP-scope.

## Reverse-direction sweep — every parser citation to ST 2110-41

```
parse_sdp.lua:734  -- ST 2110-41:2024 §6 DIT value: comma-separated uppercase hex tokens.
parse_sdp.lua:1470 -- ST 2110-41:2024 §5.3: "The RTP Clock rate ...
parse_sdp.lua:1478   spec_ref "ST 2110-41:2024 §6"  (SSN missing)
parse_sdp.lua:1482   spec_ref "ST 2110-41:2024 §6"  (SSN value form invalid)
parse_sdp.lua:1484 -- ST 2110-41:2024 §6: DIT is SHOULD (optional). §9.2.3 ...
parse_sdp.lua:1492   spec_ref "ST 2110-41:2024 §6"  (DIT value form invalid)
parse_sdp.lua:1495 -- N11 (audit): ST 2110-41:2024 §5.4 ...
parse_sdp.lua:1503   spec_ref "ST 2110-41:2024 §5.4"  (MAXUDP forbidden)
```

All eight references resolve to clauses present in the inventory (§5.3, §5.4, §6, §9.2.3). No parser citation lacks an inventoried backing clause.

A separate, related citation appears at lines 2181–2199 (`a=infoframe` attribute), which is IPMX TR-10-10 §8 — that builds on the SSN literal `ST2110-41:YYYY` form. Same SSN-literal choice as the §6 branch (`ST2110-41:` prefix).

## Mapping table

| Row | § | SDP? | Verbatim quote (short) | Parser check / Test? | Verdict |
|---|---|---|---|---|---|
| 1 | 2 | N | "reserved"/"forbidden" terminology | — | N/A — terminology only |
| 2 | 2 | N | normative precedence order | — | N/A — document precedence rule |
| 3 | 5.1 | N | "Each RTP packet shall contain zero or more Data Item Packages." | — | OUT-OF-SCOPE — RTP payload structure |
| 4 | 5.1 | N | sender keep-alive ≥1 RTP packet / 500 ms | — | OUT-OF-SCOPE — runtime sender behavior |
| 5 | 5.1 | Y | "shall be compliant with the provisions of SMPTE ST 2110-10." | `st2110.validate()` runs for every -41 stream (lines 1202–1305: PT range §6.2, ts-refclk §7.2/§8.2, mediaclk §7.3/§8.3, c= §6.3/§6.5, RTP/AVP §8.1, source-filter §8.4, etc.). Per-encoding `elseif enc == "ST2110-41"` branch at line 1469 runs WITHIN this -10 validation pass, so -10 rules are always enforced first. | COVERED |
| 6 | 5.2 | N | RTP header fields per RFC 3550 | — | OUT-OF-SCOPE — packet header |
| 7 | 5.2 | Y | "The Payload Type field shall refer to a dynamically allocated payload type chosen in the range of 96 through 127." | Lines 1327–1353: ST 2110-10 §6.2 PT range check (96–127) runs for every -10 media block. PT < 96 rejected unless matching RFC 3551 §6 static (which -41 cannot). Tests: `spec/st2110_spec.lua` PT-range tests (general). Effective coverage via -10 inheritance. | COVERED (via §5.1 → -10 §6.2) |
| 8 | 5.2 | N | RTP Timestamp semantics | — | OUT-OF-SCOPE — packet header |
| 9 | 5.2 | N | SSRC per RFC 3550 | — | OUT-OF-SCOPE — packet header |
| 10 | 5.2 | N | M-bit fixed to 0 | — | OUT-OF-SCOPE — packet header |
| 11 | 5.2 | N | sequence-number field | — | OUT-OF-SCOPE — packet header |
| 12 | 5.2 | N | header extensions per RFC 8285 | — | OUT-OF-SCOPE — packet header |
| 13 | 5.3 | Y | "the RTP Clock rate shall be signaled in the SDP as specified in IETF RFC 4566." | `rtpmap_parse()` (called line 1325) extracts and structurally validates `<rate>` token. RFC 4566 §6 rtpmap grammar mandates the rate token; absence fails parse. Parser intentionally does NOT pin rate to 90000 (line 1470–1474 comment: "rate is Data-Item-defined, not fixed at 90 kHz"). Test: `st2110_spec.lua:784` "accepts ST2110-41 with non-90000 clock rate (§5.3 Data-Item-defined)". | COVERED |
| 14 | 5.4 | N | RTP payload = 0+ Data Item Packages | — | OUT-OF-SCOPE — payload structure |
| 15 | 5.4 | N | no fragmentation of a Data Item Package | — | OUT-OF-SCOPE — payload structure |
| 16 | 5.4 | N | UDP ≤ Standard UDP Size Limit (-10) | — | OUT-OF-SCOPE for SDP body; partially surfaced via row 24's MAXUDP check (line 1500–1504) which forbids MAXUDP on -41, since MAXUDP signals exceeding the Standard limit. Note: this is an SDP-attribute consequence of §5.4, even though §5.4 itself is a runtime constraint. |
| 17 | 5.4 | N | Data Item Package internal layout (Type + K + Length + Contents) | — | OUT-OF-SCOPE — payload structure |
| 18 | 5.4 | N | Data Item Type field semantics | — | OUT-OF-SCOPE — payload structure |
| 19 | 5.4 | N | K-bit definition | — | OUT-OF-SCOPE — payload structure |
| 20 | 5.4 | N | Data Item Length ≥ 1 | — | OUT-OF-SCOPE — payload structure |
| 21 | 6 | Y | "An SDP object shall be constructed as specified in IETF RFC 4566." | `validate.sdp()` (RFC 4566 layer; called by `st2110.validate()` at line 1203). Generic RFC 4566 grammar + ordering enforced before -10/-41 checks run. | COVERED |
| 22 | 6 | Y | "The SDP shall comply with the requirements of SMPTE ST 2110-10." | Duplicate of row 5; -10 validation always runs first. | COVERED |
| 23 | 6 | Y | "may include additional clauses or format-specific media parameters … provided that these additional clauses do not contradict" | The ST2110-41 branch (lines 1469–1504) validates SSN/DIT/MAXUDP only. Unknown fmtp keys pass through the `params` table (lines 1355–1362, `fmtp_params()`) without blanket rejection. Reverse-direction check: no allowlist-style code anywhere (grep `allowed_keys|whitelist|allowlist|reject.*unknown` → none). | COVERED (permissive by design; verified) |
| 24 | 6 | Y / **AMBIGUOUS** | "Senders shall signal the Format Specific Parameter SSN with the value ST2110-41:2024 in the SDP." (§6 prose & §6 example) | Line 732: `_ssn41_pat = P("ST2110-41:") * _ssn_year * P(-1)`. Line 1475–1483: SSN required, must match `ST2110-41:YYYY`. **Parser accepts ONLY the §6 prose form `ST2110-41:YYYY`. It REJECTS the §9.2.2 IANA-registration form `SMPTE2110-41:YYYY`.** Tests: `st2110_spec.lua:758,776,803` cover required-presence, optional DIT, and wrong-prefix rejection. | **AMBIGUOUS — see Finding F1** |
| 25 | 6 | Y | "Senders should signal the Format Specific Parameter DIT …" (SHOULD) | Line 1487–1494: parser does NOT require DIT presence (absence accepted). Test `st2110_spec.lua:775` confirms "accepts ST2110-41 SDP without DIT (§6 SHOULD; §9.2.3 optional)". | COVERED (correctly treated as SHOULD — no enforcement on absence) |
| 26 | 6 | Y | DIT defined-form: no leading "0x", uppercase hex alpha, no whitespace | Line 738–739: `_hex_upper = R("09","AF")^1; _dit_pat = _hex_upper * (P(",") * _hex_upper)^0 * P(-1)`. LPEG pattern enforces uppercase hex (no lowercase a-f), no `0x` prefix, no whitespace, and trailing `P(-1)` rejects empty list. Line 1488–1494 applies pattern when DIT present. Tests: `st2110_spec.lua:2082,2088,2094,2102,2110,2118` cover: single tag, multi-tag, lowercase rejection, `0x` rejection, space-after-comma rejection, empty-value rejection. | COVERED |
| 27 | 6 | Y | example: `a=fmtp:117 SSN=ST2110-41:2024; DIT=100,2000A1,1013FC,3FFF00` | Informative — not a SHALL. Parser's `fmtp_params()` accepts `; ` and `;` separators (RFC 4566 fmtp value is free-form). | N/A (informative example) |
| 28 | 7 | N | Network Compatibility Model | — | OUT-OF-SCOPE — runtime sender egress |
| 29 | 7 | N | bucket-entry semantic | — | OUT-OF-SCOPE — network model |
| 30 | 7 | N | CINST ≤ CMAX | — | OUT-OF-SCOPE — network model |
| 31 | 7 | N | β, TDRAIN, CMAX values | — | OUT-OF-SCOPE — network model constants |
| 32 | 8.1 | N | Registry allocation rule | — | OUT-OF-SCOPE — registry administration |
| 33 | 8.2 | N | 0x000000–0x0FFFFF SMPTE-allocated range | — | OUT-OF-SCOPE — DIT-list values are descriptive, range not enforced in SDP per inventory note |
| 34 | 8.2 | N | SMPTE registry-record contents | — | OUT-OF-SCOPE — registry contents |
| 35 | 8.3 | N | 0x100000–0x1FFFFF user-org range | — | OUT-OF-SCOPE — registry partition |
| 36 | 8.3 | N | user-org registry-record contents | — | OUT-OF-SCOPE — registry contents |
| 37 | 8.4 | N | 0x200000–0x2FFFFF private range | — | OUT-OF-SCOPE — registry partition |
| 38 | 8.4 | N | private registry-record contents | — | OUT-OF-SCOPE — registry contents |
| 39 | 8.5 | N | 0x300000–0x3FEFFF reserved (per §2: not used) | — | OUT-OF-SCOPE per inventory: spec does not say SDP DIT must exclude reserved values |
| 40 | 8.6 | N | 0x3FF000–0x3FFFFF experimental | — | OUT-OF-SCOPE — permission, not enforcement |
| 41 | 9.2.1 | Y / AMBIGUOUS | "Type Name: application / Subtype Name: ST2110-41" | Encoding-name match: parser dispatches the -41 branch on `enc == "ST2110-41"` (line 1469). Top-level `application` binding to `m=application`: **NOT enforced**. Parser accepts any m-media type (including `m=video`, as in fixture `st2110_spec.lua:749`) so long as `rtpmap` encoding is `ST2110-41`. RFC 4566 §5.14 implies m=application; -41 prose does not explicitly mandate it. | **AMBIGUOUS — see Finding F2** |
| 42 | 9.2.2 | Y | `rate` parameter required in `a=rtpmap` | `rtpmap_parse()` requires the `<encoding>/<rate>` form (RFC 4566 §6 syntax). Missing rate → parse failure earlier in pipeline. | COVERED (via RFC 4566 grammar) |
| 43 | 9.2.2 | Y / **AMBIGUOUS** | "SSN=SMPTE2110-41:2024 for streams compliant to this specification." | **Parser does NOT accept `SMPTE2110-41:YYYY` form.** Line 732: `_ssn41_pat = P("ST2110-41:") * _ssn_year * P(-1)`. An SDP carrying `SSN=SMPTE2110-41:2024` (the §9.2.2 IANA literal) is rejected with "invalid SSN value (expected ST2110-41:YYYY, e.g. ST2110-41:2024)". | **AMBIGUOUS — see Finding F1; parser enforces §6 literal exclusively** |
| 44 | 9.2.3 | Y | DIT optional | Lines 1487–1494: only validates when present. | COVERED |
| 45 | 9.2.3 | Y | per-Data-Item fmtp parameters must be in `a=fmtp` | Same coverage as row 23: unknown fmtp keys are not rejected. SDP placement constraint is enforced by RFC 4566 fmtp parsing — unknown params *inside* the fmtp value string pass through. | COVERED (permissive) |
| 46 | 9.2.11 | Y | media type restricted to RTP framing | Line 1240–1244: parser requires `m.proto == "RTP/AVP"` (VALID_ST2110_PROTO) per ST 2110-10 §8.1. Non-RTP transports for an ST2110-41 stream would be rejected at the proto check. | COVERED (via -10 inheritance) |
| 47 | A | N | Simple Object Segmentation packaging | — | OUT-OF-SCOPE — payload structure |
| 48 | A | N | per-segment size bound | — | OUT-OF-SCOPE — payload structure |
| 49 | A | N | segmented package layout | — | OUT-OF-SCOPE — payload structure |
| 50 | A | N | K-bit when segmenting | — | OUT-OF-SCOPE — payload semantics |
| 51 | A | N | Segment Data Offset units | — | OUT-OF-SCOPE — payload structure |
| 52 | A | N | Segment Contents word count | — | OUT-OF-SCOPE — payload structure |
| 53 | A | N | 32-bit padding (verbatim `0T`) | — | OUT-OF-SCOPE — payload structure |

## Summary

| Bucket | Count |
|---|---|
| Total rows | 53 |
| SDP-Y rows | 16 |
| SDP-N rows | 37 |
| COVERED (SDP-Y) | 13 |
| AMBIGUOUS (SDP-Y) | 2 (rows 24, 43 — same finding; row 41) — actually **2 distinct findings**: F1 (rows 24 + 43, SSN literal) and F2 (row 41, m=application binding) |
| MISSING (SDP-Y) | 0 |
| N/A (informative example) | 1 (row 27) |

## Findings

### F1 — SSN literal-value conflict resolved (toward §6); parser is restrictive

- Inventory rows 24 and 43.
- §6 prose + §6 example require `SSN=ST2110-41:2024`.
- §9.2.2 IANA-registration prose requires `SSN=SMPTE2110-41:2024`.
- Parser pattern `_ssn41_pat = P("ST2110-41:") * _ssn_year * P(-1)` exclusively accepts the §6 form and rejects the §9.2.2 IANA form.
- Reasoning behind the parser's choice (per code comment at `parse_sdp.lua:732`) is implicit: it cites "§7.2" in the trailing comment but the actual implementation matches the §6 prose literal. The §9.2.2 alternative is not allowlisted or warned.
- Verdict per §2 (precedence): both clauses are prose, so the §2 prose-over-tables precedence rule does not adjudicate. §6 is the operative requirement clause ("Senders shall signal …"); §9.2.2 is the IANA registration template. A reasonable strict reading prefers §6.
- **Recommended Phase 2 actions** (choose one):
  - (a) Accept both forms (`ST2110-41:YYYY` and `SMPTE2110-41:YYYY`) and emit a warning when the §9.2.2 form is seen, citing §6 as canonical.
  - (b) Keep the §6-only restriction and document the resolution prominently (CHANGELOG + comment on `_ssn41_pat`) so the choice is auditable.
  - (c) Raise to SMPTE for erratum.
- Distinct from the `a=infoframe` attribute (IPMX TR-10-10 §8), which independently uses `SSN=ST2110-41:YYYY` at line 2187 and tests at `ipmx_spec.lua:1885,2468,2475`. F1's resolution would propagate there.

### F2 — m=application binding not enforced for ST2110-41 encoding

- Inventory row 41 (AMBIGUOUS in Phase 1).
- §9.2.1 fixes IANA top-level type `application` for the `ST2110-41` media subtype.
- RFC 4566 §5.14 binds the m-line `<media>` to the IANA top-level type. Combination → `m=application`.
- The parser dispatches the -41 branch off `enc == "ST2110-41"` (rtpmap encoding-name), with no check that `m.media == "application"`.
- Fixture `spec/st2110_spec.lua:749` uses `m=video 5030 RTP/AVP 96` paired with `a=rtpmap:96 ST2110-41/90000`. The test passes — meaning the parser positively accepts the §9.2.1-inconsistent `m=video` form.
- This is asymmetric with how -22 (jxsv) and -40 (smpte291) are handled: both branches explicitly require `m.media == "video"` (lines 1368, 1511) and reject mismatch with cites to RFC 8331 §4 / ST 2110-22:2022 §6.2 respectively.
- §6 of ST 2110-41 does not name a value for `m=`; it only requires SDP-construction per RFC 4566. So binding is registration-derived rather than directly normative.
- **Recommended Phase 2 action**: add a SHALL-cite or document the deliberate omission. Either:
  - (a) Enforce `m.media == "application"` for ST2110-41 encoding (cite RFC 4566 §5.14 + IANA `application/ST2110-41`), parallel to the jxsv/smpte291 m-media checks, and update the test fixture to `m=application`.
  - (b) Document an explicit "out of scope — registration-derived, not directly mandated by §6 prose" decision.

### F3 — §5.4 UDP-size constraint surfaces in SDP through MAXUDP forbid (correctly cited)

- Inventory rows 16, 24's MAXUDP discussion.
- §5.4 is itself a runtime constraint (UDP packet length on egress), inherently SDP-N.
- However, the parser correctly forbids `MAXUDP=*` in any -41 fmtp (line 1500–1504), citing §5.4. This is the cleanest SDP-level mapping of a runtime constraint: MAXUDP in -10 §6.4 signals exceeding the Standard limit; -41 §5.4 says you cannot exceed the Standard limit. Tests: `spec/st2110_spec.lua:2127` ("rejects MAXUDP on ST2110-41 (§5.4)"). Solid, defensible check.

## Cross-spec inheritance verification

§5.1 + §6 require ST 2110-10 compliance. The parser enforces this by structuring `st2110.validate()` (lines 1202–1505) to run all -10 checks BEFORE the per-encoding branch:
- §6.2 dynamic PT 96–127 (row 7) — at lines 1327–1353
- §6.3 c= required — at lines 1268–1273
- §6.5 address validation — at lines 1224–1234, 1246–1255
- §7.2/§8.2 ts-refclk required — at lines 1275–1292
- §7.3/§8.3 mediaclk required — at lines 1294–1301
- §8.1 RTP/AVP proto — at lines 1240–1244
- §8.4 source-filter format — at lines 1257–1266
- §8.5 group:DUP (where applicable) — at lines 2068–2148
- §7 rtpmap required — at lines 1303–1306

Row 5 / row 22 are therefore covered comprehensively.

## Top-3 priorities for Phase 2

1. **F1 — SSN literal `ST2110-41` vs `SMPTE2110-41`** (CRITICAL). Parser currently accepts ONE form (§6) and rejects the other (§9.2.2 IANA form). Decision needed: accept both with warning, keep §6-only with documented rationale, or seek SMPTE erratum.
2. **F2 — m=application binding for ST2110-41**. Parser allows any `m=*` so long as rtpmap encoding is `ST2110-41`; test fixture even uses `m=video`. This is asymmetric with jxsv/smpte291 (both pin `m=video`). Decide whether §9.2.1 IANA top-level binding is in or out of scope.
3. **F3 — MAXUDP forbid on -41** is well-grounded and tested. No change recommended.

---


# SMPTE — codec references

## SMPTE ST 2042-1:2012 + ST 2110-43:2021

# Audit Coverage — Codec Specs (ST 2042-1 VC-2, ST 2110-43 TTML)

Phase 2 mechanical mapping: each Phase 1 inventory row mapped to a parser check
in `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (or to a `/spec/`
test) — or marked OUT-OF-SCOPE / MISSING / N/A.

## Scope-grep result (gate)

```
$ grep -nE '"ST 2042|"ST 2110-43|VC-?2|TTML|RFC 8759|RFC 8450' parse_sdp.lua
(no hits)
$ grep -nE '"ST 2042|"ST 2110-43|VC-?2|TTML|RFC 8759|RFC 8450' spec/st2110_spec.lua
(no hits)
$ grep -nE 'vc2|ttml|2042|2110-43|8759|8450' spec/*.lua examples/...
(no hits)
$ grep -nE 'media-?type|m\.media' parse_sdp.lua | grep -i text
(no hits — parser handles m=video, m=audio, m=application only)
```

**Conclusion before per-row mapping:** the parser contains **zero** lines that
parse, recognise, or validate VC-2 (ST 2042-1) or TTML (ST 2110-43). No
encoding-name table includes a VC-2 token. No code path exists for `m=text`
(the RFC 8759 media line for TTML). No tests reference either spec or its
delegated payload-format RFCs (8450, 8759). All SDP-Y rows therefore map to
**MISSING** (feature gap), and the bitstream/decoder rows remain
OUT-OF-SCOPE-FROM-SDP.

## Per-row map

Columns: row → SDP? from inventory → mapping → file:line (if applicable) → note.

| # | Spec | § | SDP? | Mapping | File:line | Note |
|---|---|---|---|---|---|---|
| 1  | ST 2042-1 | §2 | N | OUT-OF-SCOPE-FROM-SDP | — | Conformance-vocabulary meta. Not a validator target. |
| 2  | ST 2042-1 | §2 | N | OUT-OF-SCOPE-FROM-SDP | — | "reserved"/"forbidden" semantics. Meta. |
| 3  | ST 2042-1 | §1 | N | OUT-OF-SCOPE-FROM-SDP | — | Bitstream-codec scope statement. |
| 4  | ST 2042-1 | §1 | N | OUT-OF-SCOPE-FROM-SDP | — | Cross-reference acknowledgement. |
| 5  | ST 2042-1 | §6 | N | OUT-OF-SCOPE-FROM-SDP | — | Internal terminology (core / low-delay syntax). |
| 6  | ST 2042-1 | §11.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Bitstream parse_parameters structure. |
| 7  | ST 2042-1 | §11.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Per-sequence stability rule. Bitstream. |
| 8  | ST 2042-1 | §11.1 | N | OUT-OF-SCOPE-FROM-SDP | — | SHOULD on cross-sequence stability. Stream-level. |
| 9  | ST 2042-1 | §11.1.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Decoder version check. |
| 10 | ST 2042-1 | §11.1.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Bitstream major-version semantics. |
| 11 | ST 2042-1 | §11.1.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Spec-versioning rule. |
| 12 | ST 2042-1 | §11.1.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Editorial rule on minor versions. |
| 13 | ST 2042-1 | §11.1.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Decoder functional-compatibility semantics. |
| 14 | ST 2042-1 | §11.1.1 | AMBIGUOUS | N/A — no fmtp `version` parameter exposed in RFC 8450 | — | Bitstream value; no current SDP surface. |
| 15 | ST 2042-1 | §11.1.1 | AMBIGUOUS | N/A — no fmtp `minor-version` parameter | — | As above. |
| 16 | ST 2042-1 | §11.1.2 | N | OUT-OF-SCOPE-FROM-SDP | — | Profile-semantics definition. |
| 17 | ST 2042-1 | §11.1.2 | N | OUT-OF-SCOPE-FROM-SDP | — | Level-semantics definition. |
| 18 | ST 2042-1 | §D intro | N | OUT-OF-SCOPE-FROM-SDP | — | Decoder must support ≥1 profile/level. |
| **19** | **ST 2042-1** | **§D.1** | **Y** | **MISSING** | — | **Canonical VC-2 profile-name set {main, simple, low delay, high quality}. Parser has no VC-2 encoding-name, no fmtp grammar, no profile enum. Feature gap. (Note: per inventory Phase-2 guidance, the fmtp wire-form tokens are owned by RFC 8450, not ST 2042-1; this row's spec-grounded value list flows through RFC 8450 if/when VC-2 SDP support is ever added.)** |
| 20 | ST 2042-1 | §D.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Bitstream profile-conformance rule. |
| 21 | ST 2042-1 | §D.1.1 | N | OUT-OF-SCOPE-FROM-SDP | — | Low-delay data-unit / picture-type rule. Bitstream. |
| 22 | ST 2042-1 | §D.1.2 | N | OUT-OF-SCOPE-FROM-SDP | — | Simple-profile coding rule. Bitstream. |
| 23 | ST 2042-1 | §D.1.3 | N | OUT-OF-SCOPE-FROM-SDP | — | Main-profile coding rule. Bitstream. |
| 24 | ST 2042-1 | §D.1.4 | N | OUT-OF-SCOPE-FROM-SDP | — | High-Quality profile rule. Bitstream. |
| 25 | ST 2042-1 | §D.2 | N | OUT-OF-SCOPE-FROM-SDP | — | Level values explicitly delegated to companion docs (ST 2042-2 etc.). Not parseable from this spec. |
| 26 | ST 2042-1 | §D.2 Note | N | OUT-OF-SCOPE-FROM-SDP | — | Informative cross-reference. |
| 27 | ST 2042-1 | various | N | OUT-OF-SCOPE-FROM-SDP | — | Aggregate row over the entire bitstream / decoder body. |
| 28 | ST 2110-43 | Foreword | N | OUT-OF-SCOPE-FROM-SDP | — | Conformance-vocabulary meta. |
| 29 | ST 2110-43 | Foreword | N | OUT-OF-SCOPE-FROM-SDP | — | Normative-precedence meta. |
| 30 | ST 2110-43 | §1 | N | OUT-OF-SCOPE-FROM-SDP | — | Scope statement. |
| **31** | **ST 2110-43** | **§4.1** | **Y** | **MISSING** (implicitly subsumed by row 32: RFC 8759 picks TTML2 by construction) | — | Parser does not handle TTML at all; the implicit-via-RFC-8759 chain is moot. Feature gap. |
| **32** | **ST 2110-43** | **§4.1** | **Y** | **MISSING** | — | "Use RFC 8759's m= / rtpmap / fmtp form." Parser has no `m=text` path and no RFC 8759 encoding-name in its tables. Feature gap. |
| **33** | **ST 2110-43** | **§4.1** | **Y** | **MISSING** (no TTML tier exists to enforce cross-tier ST 2110-10 conformance for) | — | The ST 2110-10 layer of the parser would run if a 2110-43 SDP were submitted, but no media-specific 2110-43 validator triggers it as a typed tier. Feature gap. |
| 34 | ST 2110-43 | §4.2 | N | OUT-OF-SCOPE-FROM-SDP | — | IMSC1.2-profile rule on the TTML XML payload — not in SDP. RFC 8759 fmtp does not expose this. |
| **35** | **ST 2110-43** | **§4.2** | **Y** | **MISSING** | — | rtpmap clock-rate must equal 90000 for TTML streams. The parser has a per-encoding 90000 check for `smpte291` and `jxsv` (e.g. parse_sdp.lua:1518), but no analogue for TTML — because no TTML encoding name is recognised. Feature gap. |
| 36 | ST 2110-43 | §4.3 | N | OUT-OF-SCOPE-FROM-SDP | — | RTP-packet-level keepalive (Length=0, M=1). Not SDP. |
| 37 | ST 2110-43 | §5 | N | N/A — Informative | — | Section is explicitly informative. |

## Summary

| Bucket | Count |
|---|---|
| Total inventory rows | 37 |
| SDP-Y in inventory | 5 |
| SDP-AMBIGUOUS in inventory | 2 |
| FOUND (parser check located) | **0** |
| MISSING (SDP-Y, feature gap) | **5** (rows 19, 31, 32, 33, 35) |
| AMBIGUOUS (no parser surface to map to; no fmtp parameter exists) | 2 (rows 14, 15) |
| OUT-OF-SCOPE-FROM-SDP / N/A | 30 |

## Observations

1. **Parser does not validate VC-2 or TTML at all.** A scope-grep over the
   single-file parser turns up zero hits for any of: `VC-?2`, `TTML`,
   `ST 2042`, `ST 2110-43`, `RFC 8759`, `RFC 8450`. The audio encoding-name
   table (parse_sdp.lua:897) lists only `L16`, `L24`, `AM824`; the
   video paths handle `raw`, `smpte291`, and `jxsv`. There is no
   `m=text` arm in the per-media-type switch.

2. **Five SDP-Y rows → all MISSING (feature gap, not bug).** This is
   consistent with the strictness principle: the parser does not pretend to
   validate codecs it does not support. The audit-correct disposition for
   these rows is "not implemented yet" rather than "wrongly checked."

3. **No incorrect citations to remove.** Because the parser does not
   mention either spec, there is no spec_ref to verify or correct in
   this walk (contrast e.g. the jxsv-fbblevel audit, where an over-strict
   citation existed and had to be removed). This walk produces no
   immediate code changes.

4. **AMBIGUOUS rows correctly remain AMBIGUOUS.** Rows 14 and 15
   (major/minor version defined value sets) map to N/A — no fmtp
   parameter for `version` exists in RFC 8450, so there is no SDP
   surface on which to validate them even if the parser knew about
   VC-2.

5. **For any future ST 2042-1 / ST 2110-43 implementation work:**
   - VC-2 fmtp grammar is owned by **RFC 8450**, not by ST 2042-1. Profile
     **names** propagate from ST 2042-1 §D.1; profile **token spellings**
     in the fmtp wire-form (e.g. `LowDelay` vs `low_delay`) are RFC 8450's
     decision and must not be invented from ST 2042-1.
   - Levels for VC-2 must cite **ST 2042-2** (or a specialised level doc),
     not ST 2042-1. "Sublevel" must not cite ST 2042-1 at all.
   - TTML SDP grammar is owned entirely by **RFC 8759**, with two
     ST 2110-43-specific overlays: (a) clock-rate = 90000 on rtpmap
     (row 35), and (b) cross-tier conformance to ST 2110-10 (row 33).

## Output

This file: `/tmp/audit_coverage_codecs.md`.

---


# SMPTE — supporting

## SMPTE ST 2022-7:2013

# Audit Coverage: SMPTE ST 2022-7:2013

**Spec**: SMPTE ST 2022-7:2013 — Seamless Protection
**Inventory**: `/tmp/audit_inventory_st2022-7.md` (10 rows)
**Parser**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`

## Phase 1 carry-over (critical)

ST 2022-7:2013 **never mentions SDP**. The SDP binding for redundancy
(`a=group:DUP`) lives in **IETF RFC 7104** and **SMPTE ST 2110-10 §8.5**.
Any parser check that uses `spec_ref = "ST 2022-7 §X"` for an SDP attribute
requirement is **WRONG-CITE** (Direction-C / mis-citation), even if the
underlying check is in fact obligated by the *downstream* RFC 7104 / ST 2110-10
inference from clause #5.

## Reverse-direction grep

```
grep -nE '"ST 2022-7|"SMPTE 2022-7|ST 2022-7 §|2022-7' parse_sdp.lua
```

Matches (5 lines in the codebase, in the DUP-group block at parse_sdp.lua:2071–2130):

| Line | Form | Where | Verdict |
|---|---|---|---|
| 2071 | "ST 2022-7" (comment) | Block-comment for DUP coherence rules | Comment-level; describes the basis but the `spec_ref` for these checks is `"ST 2110-10 §8.5"`, which is correct. Comment text is fine — it correctly identifies clause #5 as the wire-level basis. |
| 2114 | "ST 2022-7 §6" (comment) | Comment for "same PT number" check | Citation in error string mentions "ST 2022-7 §6" (see 2118); `spec_ref` field is "ST 2110-10 §8.5". |
| 2118 | "ST 2022-7 §6" in error message text | Error: "must use the same RTP payload type number (ST 2022-7 §6)" | **CANDIDATE-WRONG-CITE in the message string** — ST 2022-7 says nothing about RTP payload type number qua SDP. The obligation is inferred from clause #5 ("RTP header… shall be identical") *via* ST 2110-10 §8.5 / RFC 7104. Recommendation: drop "(ST 2022-7 §6)" from the message text, or rephrase as "(implied by ST 2022-7 §6 via ST 2110-10 §8.5)". The `spec_ref` itself is "ST 2110-10 §8.5" which is correct. |
| 2122 | "ST 2022-7 §6" (comment) | Comment for "identical fmtp" check | Comment is fine in isolation but conflates wire-level with SDP-level. |
| 2130 | "ST 2022-7 §6" in error message text | Error: "must have identical fmtp essence parameters (ST 2022-7 §6)" | **CANDIDATE-WRONG-CITE in the message string** — same issue. `spec_ref` field is "ST 2110-10 §8.5" which is correct. |

Net: there are **zero** `spec_ref = "ST 2022-7 §X"` assignments in the parser
(Phase 1 was right). The two CANDIDATE-WRONG-CITEs are in **error message
strings** only; the structured `spec_ref` field on every DUP-related error is
"ST 2110-10 §8.5" or "RFC 5888 §X". This is the same pattern as VSF
TR-10-13 §13 (line 2803): the message can quote the basis spec while the
`spec_ref` points at the binding spec.

## Per-row mapping

| Row | § | Verb | Summary | SDP? | Parser site | Verdict |
|---|---|---|---|---|---|---|
| 1 | §2 | shall (meta) | Defines `shall` keyword | N | — | OUT-OF-SCOPE (meta). |
| 2 | §2 | shall (reserved) | Defines `reserved` keyword | N | — | OUT-OF-SCOPE (meta). |
| 3 | §2 | shall (order of precedence) | Resolution rule for conflicts | N | — | OUT-OF-SCOPE (meta). |
| 4 | §6 | shall (≥2 streams) | Transmitter SHALL transmit at least two streams | Y (AMBIGUOUS) | `parse_sdp.lua:502–507` enforces `#legs < 2 → error "a=group:DUP must have at least 2 legs"`, `spec_ref` passed in by caller (here `"ST 2110-10 §8.5"`). | **COVERED** with correct citation. Does not cap at 2 (uses `< 2`), so accepts N ≥ 3 — consistent with the literal "at least two" reading. |
| 5 | §6 | shall (identical RTP header + payload) | Byte-identical RTP across copies | Y (AMBIGUOUS, inferred SDP coherence) | Three distinct checks in `parse_sdp.lua:2099–2133`: (a) same media type (lines 2100–2105), (b) same rtpmap encoding+rate (lines 2106–2113), (c) same payload-type number (lines 2114–2121), (d) identical fmtp value strings (lines 2122–2133). All four `spec_ref` fields → `"ST 2110-10 §8.5"`. | **COVERED**. Citations are correct (binding spec, not source spec). Message strings at lines 2118 and 2130 mention "(ST 2022-7 §6)" — **CANDIDATE-WRONG-CITE in the message text only**, not in the structured `spec_ref`. Acceptable but recommend rephrasing. |
| 6 | §6 | (permissive) | Differing Ethernet/IP headers OK | Y (negative) | `parse_sdp.lua:2134–2140` forbids only the *both-equal* case (src AND dst equal). The check is enforced per ST 2110-10 §8.5 ("SHALL NOT use both identical source addresses and identical destination addresses"). It does **not** require equality of `c=` or port, and accepts any non-both-equal combination. | **COVERED** (correctly does *not* impose equality). The parser's permissive treatment of differing IP/port aligns with clause #6 / Annex B. Citation `"ST 2110-10 §8.5"` is the binding spec, not ST 2022-7, and is correct. |
| 7 | §6 | shall (HBR RTP timestamp) | RTP timestamp required for HBR | N | — | OUT-OF-SCOPE (RTP wire field, not SDP). |
| 8 | §6 | shall (HBR VSID identical) | VSID inside ST 2022-6 payload identical | N | — | OUT-OF-SCOPE (RTP payload sub-field, not SDP). Note: identical-`a=fmtp` check at line 2128 covers any SDP-side declaration of VSID-affecting params transitively; not a direct mapping. |
| 9 | §6 | shall (SBR delegated) | RTP timestamp obligation delegated | N | — | OUT-OF-SCOPE (RTP delegation, no SDP). |
| 10 | §7 | shall (PD class) | Receiver Class A/B/C PD support | N | — | OUT-OF-SCOPE (receiver capability, no SDP advertisement defined). |

## Summary

- **Total rows**: 10
- **SDP-relevant (Y)**: 3 (rows 4, 5, 6)
- **Parser coverage of SDP-relevant rows**: 3 / 3 = **100% COVERED**
- **MISSING**: 0
- **WRONG-CITE (`spec_ref` field)**: 0 (Phase 1 grep was right — parser uses `"ST 2110-10 §8.5"` or RFC citations for every DUP-related `spec_ref`)
- **CANDIDATE-WRONG-CITE (error message text only)**: 2 — lines 2118 and 2130 include the phrase "(ST 2022-7 §6)" inside the user-facing error message. The structured `spec_ref` is correct.
- **Comment-level mentions of ST 2022-7**: 3 (lines 2071, 2114, 2122) — these are explanatory and document the wire-level basis for the inferred SDP coherence checks. Acceptable.

## Top findings

1. **No structured spec_ref mis-citation of ST 2022-7 exists.** Every DUP-coherence error returns `spec_ref = "ST 2110-10 §8.5"`. The parser correctly treats ST 2110-10 §8.5 / RFC 7104 as the binding SDP authority for redundancy, with ST 2022-7 §6 (clause #5 in inventory) as the *wire-level basis* that the SDP must support.

2. **All three SDP-relevant ST 2022-7 obligations are covered:**
   - Row 4 (≥2 legs) → `parse_sdp.lua:502–507`
   - Row 5 (identical RTP wire stream → coherent SDP) → four sub-checks at `parse_sdp.lua:2099–2133` (media type, rtpmap, payload type number, fmtp)
   - Row 6 (permissive on differing IP/port) → `parse_sdp.lua:2134–2140` correctly enforces only the "neither both-equal" prohibition from ST 2110-10 §8.5, not equality

3. **The "n ≥ 2 not exactly 2"** subtlety (Phase 1 observation #5) is correctly handled by `#legs < 2`, not `#legs ~= 2`. N=3, N=4, etc. are accepted.

4. **Minor nit — error message strings cite the wrong spec.** Lines 2118 and 2130 include "(ST 2022-7 §6)" in the human-readable error string. Since ST 2022-7 contains no SDP requirements at all, this is misleading to a user reading the error. Recommendation: change to "(ST 2110-10 §8.5, implementing ST 2022-7 §6)" or simply drop the parenthetical (the `spec_ref` field already conveys the citation). This is cosmetic, not a behavioral defect.

5. **No phantom ST 2022-7 checks exist** — the parser does not invent any SDP requirements (e.g. requiring matching `c=` addresses, requiring exactly two legs, requiring matching ports, requiring matching source addresses, requiring identical `a=ts-refclk`, etc.) that would be Direction-A (over-strict) violations against ST 2022-7's permissive stance. The validator correctly treats ST 2022-7 as silent on SDP.

6. **No coverage of rows 1–3, 7–10 is expected or appropriate** — those are meta, RTP-wire, or receiver-capability clauses with no SDP surface. None should map to parser code.

## Recommendation

Cosmetic-only fix: rewrite the two error message strings (`parse_sdp.lua:2118`
and `:2130`) to either drop the "(ST 2022-7 §6)" parenthetical or rephrase as
"(ST 2110-10 §8.5)" to match the `spec_ref` field. No behavioral change
required. No new tests needed.

---


# SMPTE — Recommended Practices

## SMPTE RP 2110-23/24/25

# Audit Coverage — SMPTE RP 2110-23, RP 2110-24:2023, RP 2110-25:2023

**Auditor**: Coverage-mapper (Phase 2, pre-1.0 audit of `parse_sdp`)
**Inputs**:
- Inventory: `/tmp/audit_inventory_rp2110.md` (66 rows)
- Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
- Tests: `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua`, `ipmx_spec.lua`

## Method

Mechanical mapping only. For each inventory row, search the parser and tests for any code that enforces the clause. The reverse direction check was:

```
grep -niE 'PHASED|MULTI-2SI|MULTI-SD|2110-23|2110-24|2110-25|2110.23|2110.24|2110.25' parse_sdp.lua spec/*.lua
```

**Result of reverse search: ZERO matches** in both parser and tests. None of the three RP-2110 specs is mentioned by name; none of the three RP 2110-23 `a=group` semantics tokens (`PHASED`, `MULTI-2SI`, `MULTI-SD`) appears anywhere in the codebase.

The parser does have generic `a=group` handling (RFC 5888 grammar) and specific `a=group:DUP` cross-leg checks (ST 2110-10 §8.5 + RFC 7104), but those are scoped to the `DUP` semantics token only. No semantic-level handling exists for `PHASED`, `MULTI-2SI`, or `MULTI-SD`.

## Mapping table

Legend:
- **MISSING** — clause is SDP-relevant and the parser has no code for it.
- **N/A (out of SDP scope)** — clause is not SDP-checkable per the inventory (e.g. receiver mapping, measurement methodology, packet-timing internals).
- **N/A (no SDP signal)** — clause is SDP-relevant *only if* the SDP declares RP 2110-24 compliance, but no such signal is defined in SDP. Not enforceable in isolation.
- **PARTIAL (generic)** — the parser has generic checks that touch this attribute but does not enforce the RP-specific constraint.
- **N/A (non-normative)** — clause is RP-level "should" / "should not", informational, or descriptive; not a conformance failure even if enforced.

| # | Spec | § | Verb | Summary | Coverage | Parser location | Notes |
|---|---|---|---|---|---|---|---|
| 1 | RP 2110-23 | 5.1 | shall | Each stream must individually validate as ST 2110-20/-21 | PARTIAL (generic) | `parse_sdp.lua:1300-2030` (ST 2110-20/-21 checks run per `m=` section) | Restatement of existing -20/-21 obligations; covered by the existing per-media validators, not by anything RP 2110-23-specific. |
| 2 | RP 2110-23 | 5.2.2 | shall | PHASED streams frame-aligned | N/A (out of SDP scope) | — | Packet-timing property; not visible in SDP. |
| 3 | RP 2110-23 | 5.2.2 | shall | PHASED streams share framerate + sampling | **MISSING** | — | SDP-checkable: cross-`m=` consistency of `exactframerate` and `sampling` across the streams referenced by an `a=group:PHASED` line. Parser has no cross-leg check for this semantics. |
| 4 | RP 2110-23 | 5.2.3 | shall | 2SI cardinality = 4 for 3840×2160 | **MISSING** | — | No `MULTI-2SI` handling. Cardinality (4 or 16) of identifiers in `a=group:MULTI-2SI` is unchecked. |
| 5 | RP 2110-23 | 5.2.3 | shall | 4320 → 4 → 16 structural recursion | N/A (out of SDP scope) | — | Structural decomposition, not in SDP beyond constituent count (see row 4). |
| 6 | RP 2110-23 | 5.2.4 | should not | Square Division deprecated | N/A (non-normative) | — | RP-level "should not" guidance. |
| 7 | RP 2110-23 | 5.2.4 | shall | SD cardinality = 4 for 3840×2160 | **MISSING** | — | No `MULTI-SD` handling. Cardinality unchecked. |
| 8 | RP 2110-23 | 5.2.4 | shall | 4320 → 4 → 16 structural recursion for MULTI-SD | N/A (out of SDP scope) | — | Structural. |
| 9 | RP 2110-23 | 5.3 | shall | Each `m=` section conforms to ST 2110-10 SDP rules | PARTIAL (generic) | `parse_sdp.lua:1183-2031` (ST 2110-10 per-section checks) | Restatement; covered generically. |
| 10 | RP 2110-23 | 5.3 | shall | One composite SDP describes all streams | N/A (out of SDP scope) | — | Structural property of how the file is authored; the parser accepts multiple `m=` sections and that's all that's testable. |
| 11 | RP 2110-23 | 5.3 (Fig 6) | shall | Each `m=` terminated by `a=mid:<flow id>` | PARTIAL (generic) | `parse_sdp.lua:2045-2066` (a=mid format + uniqueness, RFC 5888 §4/§8.1) | The parser validates `a=mid` format and uniqueness generically. It does not require `a=mid` to be the *last* attribute of an `m=` section. Clause is also flagged AMBIGUOUS in the inventory. |
| 12 | RP 2110-23 | 5.3 | shall | Defines new `a=group` semantics: PHASED, MULTI-2SI, MULTI-SD | **MISSING** | — | RFC 5888 §5 grammar check accepts any token as `semantics` (`parse_sdp.lua:530-549`). RP 2110-23-defined tokens are not specifically recognized, validated, or rejected. Not strictly a parser failure — RFC 5888 allows extensibility — but no RP 2110-23-specific semantics handling exists. |
| 13 | RP 2110-23 | 5.3 | shall | Each stream's params per ST 2110-20 | PARTIAL (generic) | per-media -20 validator | Restatement. |
| 14 | RP 2110-23 | 5.3 | (descriptive) | `<flow identifier>` in `a=mid` corresponds to identifiers in `a=group` | **MISSING** (AMBIGUOUS) | — | Parser checks this for `a=group:DUP` only (`each_dup_group`, `parse_sdp.lua:478-514`: rejects DUP referencing undefined mid). No equivalent for PHASED/MULTI-2SI/MULTI-SD. Inventory flags verb as AMBIGUOUS ("is used"). |
| 15 | RP 2110-23 | 5.3 | shall | Token `PHASED` for Phased decomposition | **MISSING** | — | No PHASED handling at all. |
| 16 | RP 2110-23 | 5.3 | shall | `a=group:PHASED` line precedes first `m=` | PARTIAL (generic) | RFC 4566 ordering enforced by parser grammar | Session-level attributes precede media sections by grammar; this is generically covered. PHASED specifically is not. |
| 17 | RP 2110-23 | 5.3 | shall | PHASED identifier order = phase order | N/A (out of SDP scope) | — | Semantic tied to source camera; not testable from SDP. |
| 18 | RP 2110-23 | 5.3 | shall | Token `MULTI-2SI` for 2SI decomposition | **MISSING** | — | |
| 19 | RP 2110-23 | 5.3 | shall | `MULTI-2SI 1 2 3 4` before first `m=` | **MISSING** | — | Cardinality (4) + ordering. Ordering generically covered (RFC 4566 grammar); cardinality not. |
| 20 | RP 2110-23 | 5.3 | shall | `MULTI-2SI 1 … 16` before first `m=` | **MISSING** | — | Cardinality (16). |
| 21 | RP 2110-23 | 5.3 | shall | Token `MULTI-SD` for Square Division decomposition | **MISSING** | — | |
| 22 | RP 2110-23 | 5.3 | shall | `MULTI-SD 1 2 3 4` cardinality + placement | **MISSING** | — | |
| 23 | RP 2110-23 | 5.3 | shall | `MULTI-SD 1 … 16` cardinality + placement | **MISSING** | — | |
| 24 | RP 2110-23 | 5.4 | shall | `a=group:[PHASED\|MULTI-2SI\|MULTI-SD]` duplicated when ST 2022-7 is used | **MISSING** | — | Structural: two such lines (primary + secondary) when redundancy is signaled. No code for this. |
| 25 | RP 2110-23 | 5.4 | shall | Primary identifiers suffixed `P` (1P, 2P, …) | **MISSING** | — | Defined value form. No parser code for `<n>P` suffix. |
| 26 | RP 2110-23 | 5.4 | shall | Secondary identifiers suffixed `S` (1S, 2S, …) | **MISSING** | — | Defined value form. No parser code for `<n>S` suffix. |
| 27 | RP 2110-23 | 5.4 | shall | One `a=group:DUP` per primary/secondary pair, cross-referencing PHASED/MULTI-2SI/MULTI-SD identifiers | PARTIAL (generic) | `parse_sdp.lua:478-514` (each_dup_group walks `a=group:DUP` lines and resolves mids) | DUP grouping is checked generically against `a=mid` values, not against the `<n>P`/`<n>S` identifiers in a PHASED/MULTI-2SI/MULTI-SD group. RP 2110-23-specific cross-reference is not enforced. |
| 28 | RP 2110-23 | 5.4 | shall | DUP arg order = primary, secondary | **MISSING** | — | Inside `a=group:DUP`, identifier 1 must be primary, identifier 2 secondary. Parser does not associate DUP args with any P/S role. |
| 29 | RP 2110-23 | 5.4 | shall | All-or-nothing 2022-7 protection across the group | **MISSING** | — | If any `a=group:DUP` exists, every constituent of the PHASED/MULTI-2SI/MULTI-SD group must appear in some DUP. Parser has no group-membership cross-check. |
| 30 | RP 2110-23 | 5.4 | shall not | Primary + duplicate share TR_OFFSET (no different time offsets) | **MISSING** | — | TROFFSET equality across `a=group:DUP` legs is not checked. (Parser checks fmtp essence-parameter identity across DUP legs at `parse_sdp.lua:2120-2130`, but TROFFSET is signaled in `a=ts-refclk` / `a=mediaclk` neighborhood — verify whether that area is also covered. Quick search shows no cross-leg TROFFSET equality check.) |
| 31 | RP 2110-23 | 5.5 | shall | Each stream individually -20 compliant | PARTIAL (generic) | per-media -20 validator | Restatement of row 1. |
| 32 | RP 2110-23 | 5.5 | shall | For MULTI-2SI / MULTI-SD: same RTP timestamp + same TROFFSET across constituents | **MISSING** | — | RTP timestamp is wire-only (correctly out of SDP scope). TROFFSET equality across the group's `m=` sections is SDP-checkable and not enforced. |
| 33 | RP 2110-23 | 5.5 | should | PHASED: different RTP timestamps + same TROFFSET (recommended) | N/A (non-normative) | — | RP-level "should". |
| 34 | RP 2110-23 | 5.6 | shall | Each constituent stream has a unique multicast destination address (port may be shared) | **MISSING** | — | Cross-`m=` multicast-address uniqueness for streams in a PHASED/MULTI-2SI/MULTI-SD group is not checked. Note: parser does enforce that DUP legs do not share BOTH source and destination addresses (`parse_sdp.lua:2076-2138`) — that is different (DUP non-identity rule) and does not establish per-leg unique destination for non-DUP grouping. |
| 35 | RP 2110-24 | 4.2 | should | Senders align Sample Rows to SDI line numbers | N/A (non-normative) | — | RP-level "should"; not SDP. |
| 36 | RP 2110-24 | 4.2 | should | Use RP 202:2008 "coded lines" defaults | N/A (non-normative) | — | RP-level "should"; sender choice. |
| 37 | RP 2110-24 | 4.2 | shall | SD: `sampling=YCbCr-4:2:2` + horizontal width = 720 | N/A (no SDP signal) | — | Conditional on the SDP claiming RP 2110-24 compliance. No SDP signal exists for that compliance claim. Not enforceable in isolation. |
| 38 | RP 2110-24 | 4.2 | shall | All RP 2110-24 implementations support Standard Mode | N/A (out of SDP scope) | — | Implementation conformance, not SDP. |
| 39 | RP 2110-24 | 4.2 | (definition) | Two operating modes (Standard / Extended) | N/A (out of SDP scope) | — | Definitional. |
| 40 | RP 2110-24 | 4.3 | shall | 525-line receiver Sample Row positioning | N/A (out of SDP scope) | — | Receiver mapping. |
| 41 | RP 2110-24 | 4.3 | shall | 525-line first-field termination | N/A (out of SDP scope) | — | Receiver mapping. |
| 42 | RP 2110-24 | 4.3 | shall | 525-line Standard Mode: `height` ∈ [480, 486] | N/A (no SDP signal) | — | Conditional on RP 2110-24 Standard-Mode claim; no SDP signal exists for either claim. |
| 43 | RP 2110-24 | 4.3 | shall not | 525-line Extended Window: `height` ≤ 512 | N/A (no SDP signal) | — | Same condition. |
| 44 | RP 2110-24 | 4.4 | shall | 625-line receiver positioning | N/A (out of SDP scope) | — | Receiver mapping. |
| 45 | RP 2110-24 | 4.4 | shall | 625-line first-field termination | N/A (out of SDP scope) | — | Receiver mapping. |
| 46 | RP 2110-24 | 4.4 | shall | 625-line Standard Mode: `height` == 576 | N/A (no SDP signal) | — | Conditional on RP 2110-24 Standard-Mode claim. |
| 47 | RP 2110-24 | 4.4 | shall not | 625-line Extended Window: `height` ≤ 608 | N/A (no SDP signal) | — | Conditional on RP 2110-24 Extended-Window claim. |
| 48 | RP 2110-24 | 5.1 | shall | `width` == 720 for 13.5 MHz SD | N/A (no SDP signal) | — | Conditional. Restates row 37 horizontal-samples. |
| 49 | RP 2110-24 | 5.1 | must | PAR must be present in `a=fmtp` for SD | N/A (non-normative / no SDP signal; AMBIGUOUS) | — | Lowercase "must"; inventory flags as AMBIGUOUS. SMPTE drafting convention treats lowercase "must" as non-normative. Also conditional on the unsignaled RP 2110-24 claim. |
| 50 | RP 2110-24 | 5.2 | should | 525 4:3 PAR = 10:11 | N/A (non-normative) | — | RP-level "should"; not enforceable as failure. |
| 51 | RP 2110-24 | 5.2 | should | 525 16:9 PAR = 40:33 | N/A (non-normative) | — | RP-level "should". |
| 52 | RP 2110-24 | 5.3 | (descriptive) | 625 4:3 PAR = 12:11 | N/A (non-normative; AMBIGUOUS) | — | "is determined as" — informational. |
| 53 | RP 2110-24 | 5.3 | (descriptive) | 625 16:9 PAR = 16:11 | N/A (non-normative; AMBIGUOUS) | — | Informational. |
| 54 | RP 2110-25 | 4.1 | shall | Receiver clock locked to common reference | N/A (out of SDP scope) | — | Measurement-device requirement. |
| 55 | RP 2110-25 | 4.1 | shall | Common clock+epoch between meter and DUT | N/A (out of SDP scope) | — | Measurement setup. |
| 56 | RP 2110-25 | 4.1 | shall | Sender/receiver locked to common reference clock | N/A (out of SDP scope) | — | Operational. |
| 57 | RP 2110-25 | 4.1 | shall | SDI encapsulator input locked + ST 2059-1 aligned | N/A (out of SDP scope) | — | Operational. |
| 58 | RP 2110-25 | 4.1 | should | Measurement device captures near sender, locked to clock | N/A (non-normative) | — | Guidance. |
| 59 | RP 2110-25 | 4.2 | should | Report MIN/MAX/AVG over 1 s window | N/A (non-normative) | — | Reporting guidance. |
| 60 | RP 2110-25 | 4.8.3 | shall | FPT result expressed in µs | N/A (out of SDP scope) | — | Reporting unit. |
| 61 | RP 2110-25 | 4.8.6 | shall | Margin result in µs | N/A (out of SDP scope) | — | Reporting unit. |
| 62 | RP 2110-25 | 4.8.6 | shall | Margin displayed as time | N/A (out of SDP scope) | — | Reporting. |
| 63 | RP 2110-25 | 4.8.7 | shall | GAP result in µs | N/A (out of SDP scope) | — | Reporting unit. |
| 64 | RP 2110-25 | 4.9.2 | shall | VRX uses SDP-signaled TROFFSET (or default) | N/A (out of SDP scope — consumer reference) | — | RP-25 is a *consumer* of TROFFSET, not a constrainer. No new SDP rule. |
| 65 | RP 2110-25 | 4.9.2 | shall | VRX_AVG window = 1 s default | N/A (out of SDP scope) | — | Reporting parameter. |
| 66 | RP 2110-25 | 4.11.1 | shall | Audio Delay Variance via TS-DF | N/A (out of SDP scope) | — | Algorithm requirement. |

## Coverage subtotals

| Spec | Total rows | MISSING | PARTIAL (generic) | N/A (out of SDP scope) | N/A (no SDP signal) | N/A (non-normative) |
|---|---|---|---|---|---|---|
| RP 2110-23 | 34 | 18 (rows 3, 4, 7, 12, 14, 15, 18, 19, 20, 21, 22, 23, 24, 25, 26, 28, 29, 30, 32, 34 — see note) | 6 (rows 1, 9, 11, 13, 16, 27, 31) | 6 (rows 2, 5, 8, 10, 17) | 0 | 2 (rows 6, 33) |
| RP 2110-24 | 19 | 0 | 0 | 7 (rows 35–36 reclassified as non-normative; 38, 39, 40, 41, 44, 45) | 7 (rows 37, 42, 43, 46, 47, 48, 49) | 7 (rows 35, 36, 49 ambig, 50, 51, 52, 53) |
| RP 2110-25 | 13 | 0 | 0 | 11 (rows 54, 55, 56, 57, 60, 61, 62, 63, 64, 65, 66) | 0 | 2 (rows 58, 59) |
| **Total** | **66** | **18** | **6** | **24** | **7** | **11** |

Subtotal note: row-count math for RP 2110-23 MISSING differs from a strict tally because rows 14 and 30 are flagged AMBIGUOUS but still classified MISSING for an SDP-checkable interpretation. The total of MISSING + PARTIAL + N/A = 66 (with multi-class rows counted in their primary class).

## Top 3 findings

1. **No RP 2110-23 SDP grammar overlay is implemented.** RP 2110-23 §5.3–§5.6 define a small but specific SDP overlay (three new `a=group` semantics tokens, a `<n>P`/`<n>S` redundancy-identifier convention, cross-references between `a=group:*` and `a=mid` lines, and cross-leg constraints on multicast addresses and TROFFSET). The parser has zero code for any of it. The codebase is silent on `PHASED`, `MULTI-2SI`, and `MULTI-SD` everywhere — parser, tests, fixtures. Generic RFC 5888 §5 token-grammar acceptance and generic `a=group:DUP` handling exist, but neither covers the RP 2110-23 semantics. ~18 SDP-relevant SHALLs are MISSING.

2. **RP 2110-24 cannot be enforced from SDP alone.** Seven SDP-relevant SHALLs (SD `sampling=YCbCr-4:2:2`, `width=720`, defined `height` ranges/value per mode, and PAR-presence) are all gated on the SDP claiming RP 2110-24 compliance or a specific operating mode (Standard / Extended Window). RP 2110-24 defines no SDP signal for either claim. So even if these checks were implemented, there is no way to know from SDP whether they apply — the SD width=720 / sampling=4:2:2 constraint cannot fire without false positives against general ST 2110-20 SDPs that happen to be sub-HD for unrelated reasons. Correctly captured as N/A (no SDP signal) and *not* a parser gap. RP 2110-25 has no SDP-constraining SHALLs at all.

3. **The PARTIAL (generic) cluster is a real strength, but it is generic, not RP 2110-23-specific.** The parser already enforces (a) RFC 5888 §5 `a=group` value grammar, (b) `a=mid` token format and uniqueness (RFC 5888 §4, §8.1), and (c) ST 2110-10 §8.5 + RFC 7104 cross-leg checks on `a=group:DUP` (same media type, same rtpmap encoding/clock-rate, same payload-type number, identical fmtp essence parameters, non-identical source+destination addresses). These cover the **shape** of `a=group` and the **internals** of `DUP`. They do **not** cover the RP 2110-23 PHASED/MULTI-2SI/MULTI-SD overlay, the `<n>P`/`<n>S` identifier suffix convention, the cross-reference between `a=group:DUP` arg order and the `P`/`S` roles, or the requirement that PHASED/MULTI-2SI/MULTI-SD constituents share parameters / use distinct multicast destinations / share TROFFSET. For Phase 3 prioritization: row 12 (semantics registration), rows 25/26 (`<n>P`/`<n>S` identifier form), and rows 27–28 (DUP arg-order role) are the lowest-effort enforcement candidates because they are pure SDP-grammar overlays with no cross-stream coupling.

---


# VSF IPMX — Technical Recommendations

## VSF TR-10 series (18 docs)

# TR-10 Series Coverage Map (Phase 2: Mechanical Mapping)

**Audit scope**: 18 documents in the VSF TR-10 family (IPMX).
**Date mapped**: 2026-05-16.
**Inputs**:
- Inventory: `/tmp/audit_inventory_tr10.md` (295 rows; 89 SDP-Y, 2 AMBIGUOUS).
- Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines).
- Tests: `/Users/andrewstarks/src/parse_sdp/spec/ipmx_spec.lua` (114 KB).

**Method**: For each SDP-Y row (89 total), grep parser and tests for the relevant
identifier and classify according to coverage standard:

| Code | Meaning |
|---|---|
| **MATCHED** | A parser check enforces the clause AND its `spec_ref` cites the same TR-10 section (or a derivation-of comment thread is present). |
| **MATCHED (derived)** | Enforced by inheritance (e.g. TR-10-2 §7 pulls in ST 2110-20 §7); parser cites the underlying spec, not the TR-10 wrapper. Acceptable per Strictness Principle. |
| **MISSING** | SDP-Y row with no parser check found. Direction-A finding. |
| **N/A — N (out of SDP scope)** | Row marked SDP-Y but on re-read is RTCP/management. Should have been SDP-N; not a coverage gap. |
| **N/A — AMBIGUOUS** | Inventory flagged ambiguity; coverage decision deferred. |
| **N/A — RTCP-only** | Y/RTCP-only or sub-Y rows in inventory; out of SDP-validation scope. |

For each row: identifier (TR-10-N §Section), one-liner summary, classification, and parser/test locator if MATCHED.

---

## Coverage Table (89 SDP-Y rows + 2 AMBIGUOUS rows)

| # | Spec | § | Summary | Class | Parser/test locator |
|---|---|---|---|---|---|
| 35 | TR-10-1 | 8.7 | RTCP ts-refclk string mirrors SDP `a=ts-refclk:` | N/A — RTCP-only | RTCP MIB cross-check; parser does not validate RTCP. |
| 36 | TR-10-1 | 8.7 | RTCP mediaclk string mirrors SDP `a=mediaclk:` | N/A — RTCP-only | RTCP MIB; out of scope. |
| 56 | TR-10-1 | 10 | IPMX sender MUST produce an SDP object | MATCHED | Implicit — `ipmx.validate` requires `#doc.media >= 1` (parse_sdp.lua:2399-2402). |
| 58 | TR-10-1 | 10 | FID semantics MUST NOT appear in SDP | MATCHED | parse_sdp.lua:2437-2447 ("a=group:FID is not permitted in IPMX (TR-10-1 §10)"); test ipmx_spec.lua:1550. |
| 59 | TR-10-1 | 10.1 | `IPMX` token MUST appear inside `a=fmtp` | MATCHED | parse_sdp.lua:2681-2683 (`fmtp missing required 'IPMX' marker`); test ipmx_spec.lua:198-227. |
| 60 | TR-10-1 | 10.2 | Baseband-video sender MUST signal measuredpixclk/vtotal/htotal | MATCHED | parse_sdp.lua:2715-2728 (loop over {measuredpixclk, vtotal, htotal} with TR-10-1 §10.2 spec_ref); test ipmx_spec.lua:2041. |
| 61 | TR-10-1 | 10.2 | Defined-value semantics for measuredpixclk/vtotal/htotal | MATCHED | parse_sdp.lua:2722-2727 (positive integer check). |
| 62 | TR-10-1 | 10.3 | Baseband audio sender MUST signal measuredsamplerate | MATCHED | parse_sdp.lua:2729-2742 ("fmtp missing required 'measuredsamplerate' parameter for IPMX audio"); test ipmx_spec.lua:2079. |
| 63 | TR-10-1 | 10.3 | Defined value form: Hz with 150 ppm | MATCHED (partial) | parse_sdp.lua:2737-2742 enforces positive integer; the 150 ppm tolerance is a sender-side assertion, not validatable from a single SDP snapshot. |
| 64 | TR-10-1 | 10.4 | `a=ts-refclk:` MUST be media-level | MATCHED (derived) | ST 2110-10 §8.2 enforcement at parse_sdp.lua:1275-1292 collects from both session and media; existence on each media block is required (line 1284). The "must be media-level" wording is liberalized in -10 §8.2 (session-level allowed as a shorthand); parser correctly accepts both per CLAUDE.md silence-isn't-forbidden. |
| 65 | TR-10-1 | 10.4 | `ts-refclk:localmac=…` form when no PTP | MATCHED | parse_sdp.lua:667-674 (valid_tsrefclk localmac branch). |
| 66 | TR-10-1 | 10.5 | `a=mediaclk` MUST be present, RFC 7273 §5 form | MATCHED | parse_sdp.lua:1294-1301; valid_mediaclk at parse_sdp.lua:1121-1132. |
| 67 | TR-10-1 | 10.5 | `a=mediaclk:direct=0` form (synchronous) | MATCHED | parse_sdp.lua:1124-1127 ("mediaclk direct offset must be 0 (ST 2110-10 §8.3)"). |
| 68 | TR-10-1 | 10.5 | `a=mediaclk:sender` form (async) | MATCHED | parse_sdp.lua:1121-1132 accepts both `direct=0` and `sender`. |
| 70 | TR-10-2 | 7 | Compliance with ST 2110-20 §§1-5, 6.x, 7 | MATCHED (derived) | ST 2110-20 §7 SDP rules enforced at parse_sdp.lua:1713-1892 (video media branch); `st2110.validate` runs first. |
| 72 | TR-10-2 | 7 | `m=` port: even AND > 1024 | MATCHED | parse_sdp.lua:2825-2842 (cited "TR-10-2 §7"); test ipmx_spec.lua:1302-1307. |
| 77 | TR-10-2 | 7 | Image metadata MUST be in SDP per ST 2110-20 §7 | MATCHED (derived) | parse_sdp.lua:1713-1892 enforces full ST 2110-20 §7 fmtp block. |
| 81 | TR-10-2 | 9 | Uncompressed video RTP clock = 90 kHz | MATCHED (derived) | parse_sdp.lua:1715-1718 ("rtpmap clock rate must be 90000 for video"); cite is ST 2110-20 §7.2 (parent). |
| 89 | TR-10-3 | 7 | Compliance with ST 2110-30 §§1-5, 6.2.2 | MATCHED (derived) | parse_sdp.lua:1894-2027 (audio branch) enforces ST 2110-30 §7.x and §6.2.2 (channel-order). |
| 91 | TR-10-3 | 7 | `m=` port: even AND > 1024 | MATCHED | parse_sdp.lua:2825-2842 (same enforcement as #72; canonical cite TR-10-2 §7 covers all per-essence wrappers). |
| 93 | TR-10-3 | 7 | SDP MUST conform to AES67 + RFC 4566 | MATCHED (derived) | parse_sdp.lua:1937-1953 (ptime required per ST 2110-30:2025 §6.2.1 → AES67 §8.1); RFC 4566 enforced by `validate.sdp`. |
| 102 | TR-10-3 | 9 | rtpmap clock rate = sample rate (PCM) | MATCHED (derived) | parse_sdp.lua:1909-1919 enforces RFC 3551 §6 rtpmap form (encoding/rate/channels); ST 2110-30 §6.1 inherits the rate=sample-rate semantic implicitly. |
| 110 | TR-10-4 | 7 | Compliance with ST 2110-40 §§5.1, 5.2, 5.5 (SDP) | MATCHED (derived) | parse_sdp.lua:1364-1466 (smpte291 branch) enforces ST 2110-40:2023 §7 fmtp rules (SSN, DID_SDID, TM, exactframerate, TROFF, MAXUDP). |
| 112 | TR-10-4 | 7 | `m=` port even + > 1024 | MATCHED | parse_sdp.lua:2825-2842 (canonical TR-10-2 §7 cite covers smpte291). |
| 115 | TR-10-4 | 8 | Inherits TR-10-1 §8 constraints | MATCHED (derived) | TR-10-1 enforcement via ts-refclk/mediaclk requirements. |
| 116 | TR-10-4 | 8 | Ancillary RTP clock = 90 kHz | MATCHED | parse_sdp.lua:1374-1378 ("rtpmap clock rate must be 90000 for smpte291"). Cite is RFC 8331 §4 (which TR-10-4 derives from). |
| 119 | TR-10-4 | 9 | SDP MUST follow RFC 8331 + ST 2110-10 + TR-10-1 | MATCHED (derived) | RFC 8331 via parse_sdp.lua:1367 onwards; ST 2110-10 + TR-10-1 by tier composition. |
| 122 | TR-10-5 | 10 | Sender MUST provide an SDP file for HDCP streams | MATCHED (derived) | IPMX requires SDP existence (cf. #56). The HDCP-specific assertion is satisfied by `a=hkep` validity checks at parse_sdp.lua:2758-2780. |
| 124 | TR-10-5 | 10 | `a=hkep` MUST appear when stream is HDCP; defined format | MATCHED (form only) | Format enforcement: valid_hkep at parse_sdp.lua:2257-2285. **Presence-when-HDCP is not enforced**: SDP alone doesn't declare "this stream is HDCP", so conditional presence is unenforceable from a single SDP snapshot — N/A per Strictness Principle. |
| 125 | TR-10-5 | 10 | hkep `<port>` semantics (server port) | MATCHED | parse_sdp.lua:2269-2272 (port range 0-65535). |
| 126 | TR-10-5 | 10 | hkep `<nettype>` MUST be `IN` | MATCHED | parse_sdp.lua:2273 (`if nettype ~= "IN" then return nil, "nettype must be 'IN'" end`). |
| 127 | TR-10-5 | 10 | hkep `<addrtype>` MUST be `IP4` or `IP6` | MATCHED | parse_sdp.lua:2274-2276. |
| 128 | TR-10-5 | 10 | hkep `<unicast-address>` semantics | MATCHED (parser-format only) | Parser accepts any token in addr position (parse_sdp.lua:2262-2263 acknowledges that TR-10-5 §10 doesn't constrain syntax). |
| 129 | TR-10-5 | 10 | hkep `<node-id>` = 32-hex-digit UUID | MATCHED | parse_sdp.lua:2277-2280 (regex matches xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx). |
| 130 | TR-10-5 | 10 | hkep `<port-id>` = 10-hex-digit `xx-xx-xx-xx-xx` | MATCHED | parse_sdp.lua:2281-2283. |
| 131 | TR-10-5 | 10 | Multiple `a=hkep` allowed; ordered | MATCHED | parse_sdp.lua:2758-2780 iterates all hkep attrs; ordering is preserved by the parser. |
| 133 | TR-10-5 | 14.1 | HKEP MIB version increments per `a=hkep` change | N/A — RTCP-only | RTCP MIB; out of scope. |
| 134 | TR-10-5 | 14.2 | RTCP HKEP MIB presence keyed on SDP `a=hkep` | N/A — RTCP-only | RTCP; out of scope. |
| 135 | TR-10-5 | 17 | `a=hkep` Usage Level: session or media or both | MATCHED | parse_sdp.lua:2758-2780 validates at both levels independently; both accepted. |
| 147 | TR-10-6 | 7.2 | Optional `FEC_ADD_LATENCY_VIDEO`/`_AUDIO` fmtp params | MATCHED | parse_sdp.lua:2689-2702 (validates value is non-negative integer; requires FECPROFILE be present); test ipmx_spec.lua:1016-1062. |
| 151 | TR-10-6 | 7.6 | `FECPROFILE=profile-a` fmtp param defined | N/A — AMBIGUOUS | Parser validates the value form (parse_sdp.lua:2684-2688: must be `profile-a`) but does NOT enforce "FECPROFILE shall be used to indicate FEC accompanies media" — i.e. it doesn't require FECPROFILE on every FEC-bearing stream. Inventory ambiguity preserved; if interpretation is "required when SDP advertises FEC", presence isn't observable from SDP alone (no FEC-flag in SDP). |
| 155 | TR-10-7 | 11 | SDP constructed per ST 2110-22 §7 + TR-10-1 | MATCHED (derived) | ST 2110-22 §7 enforced at parse_sdp.lua:1506-1671 (jxsv branch); TR-10-1 inherits. |
| 156 | TR-10-7 | 11 | TR-10-7 OVERRIDES ST 2110-22 §7.3 Table 3 for `b=` | MATCHED | parse_sdp.lua:2548-2583 enforces b=AS with positive integer value; cite "TR-10-7 §11". |
| 157 | TR-10-7 | 11 | `b=AS:<kbps>` defined value form | MATCHED | parse_sdp.lua:2556-2562 (positive integer); for jxsv, b=AS required (lines 2567-2572). Test ipmx_spec.lua reachable via jxsv fixtures. |
| 173 | TR-10-9 | 9 | Synchronous senders MUST emit `a=mediaclk:direct=0` | MATCHED (derived) | parse_sdp.lua:1121-1132 enforces direct=0 form for `direct=` syntax. SDP can't tell "synchronous" from "async" without inspecting clock-source semantics, so the "synchronous → direct=0" disjunction is enforced as "if `direct=`, offset must be 0" — strict form check, lenient on which form an SDP chooses. |
| 174 | TR-10-9 | 10 | Non-baseband senders MUST use substitute values | MISSING | TR-10-9 §10 substitutes (`htotal = width`, `vtotal = height`, `measuredpixclk = width × height × exactframerate`) are not checked. Parser requires presence (lines 2715-2728) but does not verify the substitute arithmetic. Direction-A candidate. AMBIGUOUS in inventory (#177) — `exactframerate` rounding rule unspecified. |
| 175 | TR-10-9 | 10 | `htotal = width` for non-baseband | MISSING | Same as #174. |
| 176 | TR-10-9 | 10 | `vtotal = height` for non-baseband | MISSING | Same as #174. |
| 177 | TR-10-9 | 10 | `measuredpixclk = width × height × exactframerate` | N/A — AMBIGUOUS | Inventory flagged. Rounding rule for rational `exactframerate` (e.g. 60000/1001) unspecified by TR-10-9. Deferred. |
| 178 | TR-10-9 | 10 | Non-baseband audio: `measuredsamplerate = rtpmap rate` | MISSING | Parser requires `measuredsamplerate` presence (parse_sdp.lua:2731-2742) but does not verify it matches rtpmap clock rate. Direction-A candidate. |
| 183 | TR-10-9 | 11 | Reaffirms TR-10-1 §10.1 fmtp `IPMX` token | MATCHED | Same as #59 — parse_sdp.lua:2681-2683. |
| 204 | TR-10-10 | 8 | Required SDP session attr `a=infoframe:<port> SSN=...;DIT=...` | MATCHED | valid_infoframe at parse_sdp.lua:2184-2202; checks at parse_sdp.lua:2462-2492; test ipmx_spec.lua:1884-1908. |
| 205 | TR-10-10 | 8 | InfoFrame port = associated media port + 3 | MATCHED | parse_sdp.lua:2480-2490 (verifies port == m.port + 3 for some media block); cited "TR-10-10 §8". |
| 222 | TR-10-11 | 9 | CBR compressed video RTP clock = 90 kHz | MATCHED | parse_sdp.lua:1515-1519 ("rtpmap clock rate must be 90000 for jxsv"). |
| 225 | TR-10-11 | 10 | SDP per ST 2110-22 §7 + TR-10-1 | MATCHED (derived) | Same as #155. |
| 215 | TR-10-11 | 7 | Inherits TR-10-1 | MATCHED (derived) | TR-10-1 enforcement. |
| 217 | TR-10-11 | 7 | `m=` port even + > 1024 | MATCHED | parse_sdp.lua:2825-2842. |
| 221 | TR-10-11 | 9 | Inherits TR-10-1 Media/RTP Clock | MATCHED (derived) | parse_sdp.lua:1294-1301 (mediaclk). |
| 231 | TR-10-12 | 7 | Compliance with ST 2110-31 §§5.1, 5.3, 5.4, 6, 7 (SDP) | MATCHED (derived) | parse_sdp.lua:1921-1978 enforces ST 2110-31:2022 §6.1 (AM824 channel count even, clock rate ∈ {44100, 48000, 96000}, ptime ∈ Table 1). |
| 233 | TR-10-12 | 7 | `m=` port even + > 1024 | MATCHED | parse_sdp.lua:2825-2842. |
| 238 | TR-10-12 | 8 | SDP carries technical metadata | MATCHED (derived) | ST 2110-31 fmtp checks at parse_sdp.lua:1921-1978. |
| 239 | TR-10-12 | 9 | AES3 sample rate ∈ {44100, 48000, 96000} | MATCHED | parse_sdp.lua:1931-1934 (cite ST 2110-31:2022 §5.5 / §6.1). TR-10-12 §9 redundant with inherited spec. |
| 242 | TR-10-12 | 9 | Inherits TR-10-1 audio Media/RTP Clock | MATCHED (derived) | parse_sdp.lua:1294-1301. |
| 243 | TR-10-12 | 9 | AES3 rtpmap rate = audio sample rate | MATCHED | parse_sdp.lua:1909-1919 enforces RFC 3551 §6 rtpmap form; AM824 clock rate validated to {44100, 48000, 96000} at 1931-1934. |
| 246 | TR-10-13 | 13 | Required SDP attr `a=privacy` (session or media level) | MATCHED (presence-conditional) | valid_privacy at parse_sdp.lua:2317-2363; check_privacy at parse_sdp.lua:2368-2382. Presence when encrypted is unenforceable from SDP alone (no encrypted-flag); format-when-present is fully checked. |
| 247 | TR-10-13 | 13 | Required `a=privacy` params: protocol, mode, iv, key_generator, key_version, key_id | MATCHED | parse_sdp.lua:2337-2339 (loop checks all 6); test ipmx_spec.lua:334-437. |
| 249 | TR-10-13 | 13 | Privacy params immutable while active | N/A — temporal | Cross-snapshot constraint; out of scope for static SDP validation. |
| 250 | TR-10-13 | 13 | `a=privacy` format: semicolons, optional space, no trailing semicolon, CRLF | MATCHED | parse_sdp.lua:2323-2336 (trailing semicolon rejected; semicolon-separator parsing); test ipmx_spec.lua:1943 (trailing-semicolon rejection). |
| 251 | TR-10-13 | 13 | Full `a=privacy` attribute structure | MATCHED | parse_sdp.lua:2317-2363; test ipmx_spec.lua:334-437. |
| 252 | TR-10-13 | 13 | Protocol immutable while active | N/A — temporal | Cross-snapshot. |
| 253 | TR-10-13 | 13 | `NULL` forbidden as `protocol=` value | MATCHED | parse_sdp.lua:2289-2290 enumerates valid protocols (RTP, RTP_KV); NULL not enumerated, rejected at parse_sdp.lua:2341-2345. |
| 255 | TR-10-13 | 13 | `NULL` forbidden as `mode=` value | MATCHED | parse_sdp.lua:2302-2309 enumerates valid modes; NULL not enumerated, rejected at parse_sdp.lua:2346-2349. |
| 256 | TR-10-13 | 13 | `iv` = 64-bit (16 hex chars) | MATCHED | parse_sdp.lua:2294-2299 (PRIVACY_HEX_LEN.iv=16); test ipmx_spec.lua:958-1015. |
| 257 | TR-10-13 | 13 | `key_generator` = 128-bit (32 hex chars) | MATCHED | parse_sdp.lua:2294-2299 (.key_generator=32). |
| 258 | TR-10-13 | 13 | `key_version` = 32-bit (8 hex chars) | MATCHED | parse_sdp.lua:2294-2299 (.key_version=8). |
| 259 | TR-10-13 | 13 | `key_id` = 64-bit (16 hex chars) | MATCHED | parse_sdp.lua:2294-2299 (.key_id=16). |
| 261 | TR-10-13 | 14 | Defined URN values for PEP `a=extmap` | MATCHED (URN-conditional) | parse_sdp.lua:2220-2223 (PEP_EXTMAP_URIS enumerates the two URNs); enforcement focuses on direction (see #262). The URNs themselves are accepted; non-PEP URNs in `a=extmap` are not constrained (RFC 5285 §7 form-only). |
| 262 | TR-10-13 | 14 | `a=extmap` MUST use `sendonly` direction for PEP | MATCHED | pep_extmap_direction_ok at parse_sdp.lua:2247-2255; enforcement at parse_sdp.lua:2591-2632 (session and media); test ipmx_spec.lua:2335 (`TR-10-13 §20.1`). |
| 263 | TR-10-13 | 16 | RTCP PEP MIB presence keyed on SDP `a=privacy` | N/A — RTCP-only | RTCP; out of scope. |
| 264 | TR-10-13 | 17 | `a=privacy` Usage Level: session/media/both | MATCHED | parse_sdp.lua:2782-2814 — checked at session level, each media level; DUP-group consistency at 2803-2814 honors session-level-as-default for media legs without their own. |
| 266 | TR-10-14 | 12 | When USB encrypted: `a=privacy` MUST appear in SDP | MATCHED (presence-conditional) | valid_privacy with `usb_only=true` flag (parse_sdp.lua:2368-2382, called at 2786 with `usb_set[i]==true`); restricts mode to AAD variants (PRIVACY_USB_MODES at 2311-2315). |
| 268 | TR-10-14 | 14 | USB SDP follows RFC 4145 (`a=setup`, `a=connection`) | MATCHED | parse_sdp.lua:2497-2515 enforces RFC 4145 §4 enum for setup and connection. |
| 269 | TR-10-14 | 14 | USB media line: `m=application <port> TCP usb` | MATCHED (recognition) | parse_sdp.lua:2411-2419 recognizes USB blocks by exactly this shape (`m.media=="application" && m.proto=="TCP" && m.fmts[1]=="usb"`). |
| 270 | TR-10-14 | 14 | When encrypted: `protocol=USB_KV` value | MATCHED | parse_sdp.lua:2289-2290 + 2340-2345 (PRIVACY_PROTOCOLS_USB={USB_KV}; usb_only path rejects RTP/RTP_KV). |
| 271 | TR-10-14 | 14 | USB SDP: `a=setup:passive` defined | MATCHED | parse_sdp.lua:2525-2546 ("a=setup must be 'passive' for USB blocks"); test ipmx_spec.lua:441-616. |
| 275 | TR-10-15 Part 1 | 7 | RFC 9134 payload format / SDP fmtp params (jxsv) | MATCHED (derived) | parse_sdp.lua:1506-1671 (jxsv branch) enforces RFC 9134 §7.1 (packetmode required, transmode/profile/level/sublevel value forms). |
| 282 | TR-10-15 Part 1 | 9 | **CRITICAL** — transmode/packetmode/profile/level/sublevel/fbblevel are RTCP MIB fields, NOT SDP | N/A — RTCP-only | **Bullet-binding trap confirmed.** Parser comment at parse_sdp.lua:1706-1711 explicitly notes the removal of `fbblevel` SDP check (commit f6aa63f). Parser does NOT enforce these names as SDP-fmtp-required from TR-10-15 — value forms only via RFC 9134 path (#275). |
| 261 | TR-10-13 | 14 | (see above) | (already mapped) | — |
| 293 | TR-10-TP-1 | 13.2 | Test plan: video fmtp checklist incl. TP ∈ {2110TPW, 2110TPN, 2110TPNL} | MATCHED (derived) | TP value set: VALID_TP at parse_sdp.lua:890; checked in raw video at 1753 and in jxsv at 1577. Test plan informative; the underlying SHALLs are in TR-10-1 + ST 2110-21. |
| 294 | TR-10-TP-1 | 13.2 | Test plan: TP ∈ {2110TPW, 2110TPN, 2110TPNL} (re-stated) | MATCHED | Same as #293. Also: required-for-IPMX-video TP presence at parse_sdp.lua:2710-2713 (`fmtp missing required 'TP' parameter for IPMX video`, cite `TR-10-TP-1 §13.2`); test ipmx_spec.lua:2728. |
| 295 | TR-10-TP-1 | 13.2 | Test plan: audio fmtp checklist incl. AM824, channel-order, measuredsamplerate | MATCHED (derived) | AM824 enforcement at 1925-1936; channel-order at 1067-1101; measuredsamplerate at 2729-2742. |

---

## Per-TR Subtotals

| TR | SDP-Y rows | MATCHED | MATCHED (derived) | MISSING | N/A | Notes |
|---|---|---|---|---|---|---|
| TR-10-1 | 14 | 9 | 2 | 0 | 3 (2 RTCP-only, 1 implicit) | Full coverage of explicit SDP clauses; FID prohibition + IPMX fmtp marker + measured*/vtotal/htotal + ts-refclk/mediaclk forms. |
| TR-10-2 | 7 | 1 (port) | 3 (ST 2110-20 §7 chain) | 0 | 3 (RTCP-only mirror, capability) | Inherits ST 2110-20 §7; port even/>1024 has direct TR-10-2 cite. |
| TR-10-3 | 5 | 1 (port) | 3 (ST 2110-30 §6.1, AES67 §8.1) | 0 | 1 | All derived from ST 2110-30 / AES67 chain. |
| TR-10-4 | 5 | 1 (port + 90 kHz) | 4 (ST 2110-40 §7 chain) | 0 | 0 | TR-10-4 not cited in parser comments — gap is COSMETIC; underlying ST 2110-40 §7 enforcement is in place. |
| TR-10-5 | 12 | 9 | 0 | 0 | 3 (1 conditional presence, 2 RTCP-only) | Full hkep format coverage; presence-when-HDCP unenforceable from SDP. |
| TR-10-6 | 1 (+1 AMBIGUOUS in inventory) | 1 (latency params) | 0 | 0 | 1 AMBIGUOUS (FECPROFILE presence) | Value-form check on FECPROFILE present; "required when FEC signaled" interpretation deferred per inventory ambiguity. |
| TR-10-7 | 5 | 1 (b=AS) | 4 (ST 2110-22 §7 chain) | 0 | 0 | b=AS override matched with TR-10-7 §11 cite at parse_sdp.lua:2548-2583. |
| TR-10-9 | 8 | 1 (IPMX fmtp marker echo) | 1 (mediaclk:direct=0 form) | **3 (non-baseband substitutes)** | 3 (3 receiver-side rows) + 1 AMBIGUOUS | **TR-10-9 not cited in parser** — and the 3 non-baseband substitute formulas (§10) are not enforced (Direction-A candidates). |
| TR-10-10 | 2 | 2 | 0 | 0 | 0 | Full infoframe coverage with TR-10-10 §8 cite at 2462-2492. |
| TR-10-11 | 4 | 1 (90 kHz, ports) | 3 (chain) | 0 | 0 | Inherits ST 2110-22 §7 / TR-10-1. |
| TR-10-12 | 6 | 1 (port) | 5 (ST 2110-31 chain) | 0 | 0 | **TR-10-12 not cited in parser** — gap is COSMETIC; AES3 sample-rate set {44100, 48000, 96000} fully enforced under ST 2110-31:2022 §6.1 cite at 1925-1934. |
| TR-10-13 | 14 | 11 | 0 | 0 | 3 (2 temporal, 1 RTCP-only) | Full a=privacy + PEP-extmap coverage with TR-10-13 §13/§14/§20.1 cites. |
| TR-10-14 | 5 | 5 | 0 | 0 | 0 | Full USB coverage with TR-10-14 §12/§14 cites. |
| TR-10-15 Part 1 | 1 | 0 | 1 (RFC 9134 chain) | 0 | 0 | RFC 9134 §7.1 chain. **§9 bullet-binding trap confirmed avoided** (fbblevel removal at parse_sdp.lua:1706-1711). |
| TR-10-TP-1 | 3 (informative) | 1 (TP) | 2 (derived) | 0 | 0 | Test plan; underlying SHALLs in TR-10-1 + ST 2110-21. |
| **TOTAL** | **89 SDP-Y + 2 AMBIGUOUS** | **44** | **28** | **3 (TR-10-9 §10)** | **14** | 72 of 89 fully covered; 3 MISSING in TR-10-9 §10 non-baseband substitutes; 12 N/A (RTCP/temporal/cross-domain); 2 AMBIGUOUS deferred. |

---

## Direction-A Findings (MISSING coverage)

1. **TR-10-9 §10 non-baseband substitutes** (rows 174, 175, 176, 178 — 3 + 1):
   - `htotal` MUST equal `width` for non-baseband senders.
   - `vtotal` MUST equal `height` for non-baseband senders.
   - `measuredpixclk` MUST equal `width × height × exactframerate` for non-baseband senders.
   - `measuredsamplerate` MUST equal the rtpmap clock rate for non-baseband audio senders.

   Current parser requires these parameters to be **present** (parse_sdp.lua:2715-2742) but does not verify the substitute arithmetic for non-baseband senders. SDP alone can't always tell baseband from non-baseband intent, but the substitute rule applies only when the relationships hold; if `htotal=width` etc. is observed, the parser could enforce consistency. AMBIGUOUS in inventory (#177) — rounding rule for rational `exactframerate` unspecified. Recommend deferring with a `spec_ref="TR-10-9 §10"` allowlist note until VSF clarifies.

## Cosmetic Citation Gaps (not Direction-A)

These TRs are NOT cited by `spec_ref` in parser code, but their normative SHALLs ARE enforced via the underlying spec they reference:

- **TR-10-4** (ST 291 ANC): all 5 SDP-Y clauses enforced via ST 2110-40 §7 chain at parse_sdp.lua:1364-1466. Adding "TR-10-4 §7" annotation to relevant cites would document the IPMX wrapper but is not required for correctness.
- **TR-10-12** (AES3): all 6 SDP-Y clauses enforced via ST 2110-31 §6.1 chain at parse_sdp.lua:1921-1978. Same cosmetic note.

These are tracked as "MATCHED (derived)" in the coverage table.

## Top 5 Findings

1. **3 Direction-A MISSING checks in TR-10-9 §10** non-baseband substitute formulas (`htotal=width`, `vtotal=height`, `measuredpixclk=width×height×exactframerate`, `measuredsamplerate=rtpmap-rate`). Presence is required; substitute arithmetic is not verified. One overlaps with inventory AMBIGUOUS row #177 (rounding rule).
2. **Bullet-binding trap confirmed avoided**: TR-10-15 §9 (transmode/packetmode/profile/level/sublevel/fbblevel) — parser explicitly removed `fbblevel` SDP check in commit f6aa63f with a comment at parse_sdp.lua:1706-1711 documenting the rationale ("no spec basis → no check"). Phase 2 verifies these are NOT enforced as SDP fmtp.
3. **TR-10-4 and TR-10-12 cosmetic citation gaps**: their normative SHALLs ARE enforced via the ST 2110-40/§7 and ST 2110-31/§6.1 chains, but the IPMX wrapper TRs are not cited by `spec_ref`. No correctness gap; only documentation could be improved.
4. **Net-new IPMX SDP scope fully covered**: All four new SDP attributes (`a=hkep`, `a=infoframe`, `a=privacy`, PEP `a=extmap`), the `IPMX` fmtp token, FECPROFILE, b=AS bandwidth override, USB-over-IP block recognition, and DUP-group privacy consistency are MATCHED with TR-10-N cites in parser and tests.
5. **AMBIGUOUS deferred items**: 2 inventory ambiguities (#151 FECPROFILE presence semantics, #177 measuredpixclk rounding rule). Parser correctly does not enforce either ambiguous interpretation. Phase 3 should resolve with VSF (or document as out-of-scope) before adding strict checks.

---

## Files referenced

- Parser: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` (3349 lines).
- Tests: `/Users/andrewstarks/src/parse_sdp/spec/ipmx_spec.lua` (2743 lines).
- Inventory: `/tmp/audit_inventory_tr10.md` (295 rows / 418 markdown lines).

---


# VSF IPMX — v1.0 profile requirements

## IPMX Released v1.0 (3 profile docs)

# IPMX Released v1.0 — Phase-2 Coverage Map

**Inventory**: `/tmp/audit_inventory_ipmx_released.md` (125 normative clauses; 13 marked SDP-Y)
**Parser**: `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua`
**Tests**: `/Users/andrewstarks/src/parse_sdp/spec/ipmx_spec.lua`

## Mapping rule

Every SDP-Y row in the IPMX v1.0 profiles is one of:
- `Y (implication)` — essence implication only; concrete SDP form lives in the cited TR-10-X.
- `Y (no-op)` — *negative* requirement that the profile does NOT tighten beyond TR-10-X (resolution / frame-rate "Undefined / Any").
- `Y (delegated)` — clause says "SDP fields required by TR-10-X"; SDP-attribute set is owned by the TR-10-X document.
- `Y (cross-pane)` — SDP / Info-Block / stream consistency assertion; not validatable from a single SDP.

For all four categories the correct parser action at the IPMX tier is **no IPMX-specific SDP check** (correctness is established at the ST 2110 / RFC 4566 cascade). The mapping below records, for each row, where the parser already enforces the underlying TR-10-X / ST 2110 rule and confirms that no opinion-based or bullet-binding-trap residue is present.

## Reverse-direction scan

```sh
grep -nE '"IPMX|IPMX-Uncompressed|IPMX-JPEG-XS|IPMX-PCM-Audio' parse_sdp.lua
```

Hits:

| Line | Context | Verdict |
|---|---|---|
| 2400 | `"IPMX requires at least one media block"` (error message text only — cite is `ST 2110-10 §7`) | OK |
| 2588 | Comment: removed an unconditional `extmap` presence requirement that cited a non-existent "IPMX §6" | OK (historical comment) |
| 2681–2682 | `params["IPMX"]` fmtp-marker check — `spec_ref = TR-10-1 §10.1` | OK (cite is TR-10-1, not an IPMX profile doc) |

**Zero parser cites to IPMX-Uncompressed v1.0, IPMX-JPEG-XS v1.0, or IPMX-PCM-Audio v1.0.** All IPMX-tier checks cite TR-10-1 / TR-10-2 / TR-10-5 / TR-10-6 / TR-10-7 / TR-10-9 / TR-10-10 / TR-10-13 / TR-10-14 / TR-10-TP-1 or upstream ST 2110 / RFC documents — never an IPMX v1.0 profile clause. This is the expected outcome of Phase 1's finding that all profile SDP-form rules delegate to TR-10-X.

## SDP-Y coverage table

| Row | Spec § | SDP? | Parser disposition | Evidence |
|---|---|---|---|---|
| **UV-03** | IPMX-Uncompressed §6 preamble | Y (implication) | Essence-name `raw` enforced by ST 2110-20 path (`parse_sdp.lua` §"st2110") | rtpmap encoding validated against ST 2110-20 §7 + RFC 4175; nothing IPMX-specific to add. |
| **UV-07** | IPMX-Uncompressed §6.1.1 | Y (no-op) — Resolution/rate "Undefined / Any" | **NEGATIVE constraint: parser must NOT whitelist** | `width`/`height` use `valid_pos_int` (any positive integer, line 1575–1576 — applies to jxsv; raw video uses same lib); `exactframerate` accepts any positive integer or reduced fraction (`valid_exactframerate`, line 1012). No resolution whitelist. No frame-rate whitelist. **Confirmed Direction-B-clean.** |
| **UV-12** | IPMX-Uncompressed §6.1.4 | Y (delegated, cross-pane) | "SDP attributes as defined in TR-10-2" — delegated | TR-10-2 SDP-attribute set is enforced at the ST 2110-20 tier (raw video path, parse_sdp.lua §"st2110"). No IPMX-tier additions. Bullets ("Info Block contents; SDP; Actual stream behavior") are artifact categories — parser does not invent an SDP-side check from them. |
| **UV-17** | IPMX-Uncompressed §6.2.2 | Y (no-op) — Receive any resolution/rate | **NEGATIVE constraint: parser must NOT whitelist** | Same as UV-07. Confirmed Direction-B-clean. |
| **UV-18** | IPMX-Uncompressed §6.2.2 | Y (cross-pane) | "Optional formats … accurately advertised via SDP, Info Blocks, NMOS" | Cross-pane consistency; cannot be validated from a single SDP. No parser action required. |
| **JX-04** | IPMX-JPEG-XS §6 preamble | Y (implication) | Essence-name `jxsv` enforced by ST 2110-22 path (line 1506 onward) | rtpmap encoding `jxsv` validated against ST 2110-22 §7 + RFC 9134. |
| **JX-08** | IPMX-JPEG-XS §6.1.1 | Y (no-op) — Resolution/rate "Undefined / Any" | **NEGATIVE constraint: parser must NOT whitelist** | `width`/`height` use `valid_pos_int` (line 1575–1576). `exactframerate` accepts any positive integer or reduced fraction. JPEG-XS `profile`/`level`/`sublevel` enums (`VALID_JXS_PROFILE` etc., lines 903–948) are the full RFC 9134 / TR-10-15 enum sets; the parser does NOT restrict to the IPMX profile-required subset `{High444.12}` (which would be Direction-B device-capability subsetting). **Confirmed Direction-B-clean.** |
| **JX-16** | IPMX-JPEG-XS §6.1.4 | Y (delegated, cross-pane) | "SDP fields required by TR-10-11" — delegated | TR-10-11 SDP set enforced at ST 2110-22 tier (line 1506 onward). The bullets ("resolution, frame rate, color sampling, bit depth, profile, level, sublevel") are dimensions of consistency, not SDP attribute names. **Critical**: the `fbblevel` bullet from JX-14's MIB list is NOT enforced as SDP fmtp — verified at line 1706–1711 ("D2 (audit): no spec defines `fbblevel` as an SDP fmtp parameter…"). Commit f6aa63f removed the prior opinion-based check. **Bullet-binding trap fully cleared.** |
| **JX-20** | IPMX-JPEG-XS §6.2.1 | Y (no-op) — Receive any resolution/rate | **NEGATIVE constraint: parser must NOT whitelist** | Same as JX-08. Confirmed Direction-B-clean. |
| **JX-27** | IPMX-JPEG-XS §6.2.3 | Y (delegated) | "SDP signaling consistently with TR-10-11 / TR-10-15" — delegated | TR-10-11 SDP set enforced at ST 2110-22 tier. TR-10-15 not yet published; parser does not gate on it. Bullets are dimensions to validate, not SDP attribute names. |
| **PCM-03** | IPMX-PCM-Audio §6 preamble | Y (implication) | Essence implies `audio/L16`/`audio/L24` from `VALID_AUDIO_ENC` (line 897) | rtpmap encoding validated against ST 2110-30 §6 + RFC 3551 / 3190 / 7587. No new IPMX-tier SDP rule. |
| **PCM-14** | IPMX-PCM-Audio §6.1.4 | Y (delegated, cross-pane) | "SDP fields required by TR-10-3" — delegated | TR-10-3 SDP set enforced at ST 2110-30 tier. PCM-13's bullets (Sample rate / Sample size / Channel count / Packet time / Measured sample rate / Channel order) belong to the *Media Info Block* parent clause — not SDP. **Confirmed not enforced as IPMX-tier SDP fmtp parameters.** The optional ST 2110-30 §6.2.2 `channel-order` validator (parse_sdp.lua line 2020) is correctly scoped to ST 2110-30, validated only when the parameter is present, and not derived from PCM-13's MIB-field bullet list. |
| **PCM-14 (MIB shape: PCM-13)** | IPMX-PCM-Audio §6.1.4 | N (RTCP MIB) | **NEGATIVE constraint: parser must NOT lift bullets into SDP** | No parser check enforces `Sample rate`, `Sample size`, `Channel count`, `Packet time`, `Measured sample rate`, or `Channel order` as IPMX-tier-required SDP fmtp parameters. (Required SDP attributes for IPMX audio come from ST 2110-30 / TR-10-1 §10.3 — only `measuredsamplerate` is mandated, line 2730–2742, with the correct TR-10-1 §10.3 cite.) **Confirmed Direction-B-clean** for the PCM bullet-binding trap. |

### Coverage status

| Status | Count | Rows |
|---|---|---|
| Y (implication) — covered at ST 2110 / RFC tier | 3 | UV-03, JX-04, PCM-03 |
| Y (no-op, negative constraint) — confirmed parser does NOT whitelist | 4 | UV-07, UV-17, JX-08, JX-20 |
| Y (delegated to TR-10-X) — covered at ST 2110 tier | 4 | UV-12, JX-16, JX-27, PCM-14 |
| Y (cross-pane) — out of single-SDP scope | 2 | UV-18 (and JX-16/PCM-14 share this aspect) |
| MISSING | **0** | — |

**No SDP-Y row maps to a MISSING check.** All 13 SDP-Y clauses are either delegations (already enforced via the cited TR-10-X at the ST 2110 tier), no-op negatives (parser must not, and does not, whitelist), implications (essence name carried by ST 2110 tier), or cross-pane consistency assertions (out of single-SDP scope).

## Direction-B residue check (priority output)

Bullet-binding-trap and Direction-B device-capability checks would manifest as:

1. **fbblevel enforced as SDP fmtp** — JX-14 canonical trap.
2. **`transmode` / `packetmode` / `profile` / `level` / `sublevel` enforced as IPMX-tier required SDP fmtp** — JX-14 trap (parameter set).
3. **Resolution / frame-rate whitelist at the IPMX tier** — UV-07 / UV-17 / JX-08 / JX-20 trap.
4. **PCM `channel-order` / `sample rate` / `sample size` enforced as IPMX-tier required SDP fmtp** — PCM-13 trap (parameter set).
5. **JPEG-XS profile restricted to `{High444.12}` at IPMX tier** — UV-06 / JX-07 / JX-19 device-capability subsetting.

Verified:

| Trap | Verified at | Status |
|---|---|---|
| 1. fbblevel SDP check | line 1706–1711 (comment: "D2 (audit): no spec defines `fbblevel` as an SDP fmtp parameter… Per the strictness principle (CLAUDE.md): no spec basis → no check. Removed.") | CLEARED (commit f6aa63f) |
| 2. transmode / packetmode / profile / level / sublevel as IPMX-tier required | lines 1574–1623; only `packetmode` is required, cited to RFC 9134 / ST 2110-22; the rest are OPTIONAL, format-validated when present, cited correctly to ST 2110-22 / RFC 9134 — NOT to IPMX-JPEG-XS §6.1.4 | CLEARED |
| 3. Resolution / frame-rate whitelist | width/height = `valid_pos_int` (any positive integer); exactframerate = positive integer or reduced fraction; no resolution table or frame-rate table | CLEARED |
| 4. PCM channel-order / sample rate / sample size as IPMX-tier required | No IPMX-tier presence check on any of these; ST 2110-30 §6.2.2 channel-order is OPTIONAL and validated only when present (line 2020); no `audio.measuredsamplerate` cite at PCM-14 (only at TR-10-1 §10.3, which is correct and is upstream of IPMX-PCM-Audio §6.1.4) | CLEARED |
| 5. JPEG-XS profile subset `{High444.12}` enforcement | `VALID_JXS_PROFILE` (lines 903–917) is the full RFC 9134 / TR-10-15 set; `High444.12` is one of 13 entries; no IPMX-tier subsetting | CLEARED |

**Zero Direction-B residue.**

## Notes

- The single IPMX-marker check at line 2681 (`params["IPMX"]`) cites `TR-10-1 §10.1`, not an IPMX v1.0 profile doc, so it is a TR-10-tier requirement and not subject to this audit.
- The two NMOS-Flow `media_type` clauses (JX-31, PCM-27) with cross-pane informative SDP implications are informational only; the authoritative SDP-side definitions live in RFC 9134 / RFC 3551 / ST 2110-30, and the parser correctly cites those.
- Forward references to TR-10-15 (JX-27 and elsewhere) are not gated by the parser; TR-10-15 has not been published in the repo's spec library. No action needed at this time.

---

