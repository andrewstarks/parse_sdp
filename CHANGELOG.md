# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed (test suite reorganization)

- **`spec/sdp_spec.lua` reordered by atomic → complex (no test changes).**
  Top-level describe blocks now flow: setup → atomic grammar (tokenize,
  parse_version/origin/timing/media — `parse_media` moved up next to the
  other primitive parsers) → session-level field structure (required →
  optional M4 → RFC 4566 §5 r=/z=/k=/multiple t= audit F8, with the
  optional block moved ahead of the audit F8 block so the structural
  required → optional → extended-optional reading is preserved) →
  media-level field structure (m= block plus its four nested describes
  covering dynamic-PT, IPv4/IPv6 multicast TTL, and multiple session-
  level c=) → doc-object methods → serializer (to_sdp + to_json). Added
  category section-comment headers to make the grouping visible. No
  test was added, removed, or modified; all 136 cases still pass and
  the full suite remains at 853 passing. First of three staged commits
  reorganizing `spec/` (st2110 + ipmx to follow).

### Changed (audit pass #31 — Wave 5 RFC 8866 base migration)

- **Multiple session-level c= lines rejected at parse (audit D1.6).**
  RFC 8866 §5.7: *"Multiple addresses or 'c=' lines MUST NOT be
  specified at session level."* (The same clause permits multiple
  media-level c= lines but only for hierarchical/layered multicast
  encoding.) The parser previously consumed one session-level c=
  line and then proceeded to look for `b=`/`a=`/`m=` — a second
  c= line at session level would either silently fall through or
  trip an unrelated `WRONG_ORDER` error. Added an explicit check in
  the parser's session-block walker: after consuming a session-level
  c=, peek the next line; if it's another c=, reject with
  `spec_ref="RFC 8866 §5.7"` and the explicit "multiple session-level
  c= lines are not permitted" message. 3 new tests under a
  `RFC 8866 §5.7 multiple session-level c= rejection` describe block
  (single c= pass, two-c= reject, two-c= reject even with following
  m= block). Media-level c= multiplicity (layered-encoding exception)
  is out of scope — the parser doesn't accept multiple media-level c=
  lines today for unrelated strict-ordering reasons; widening that
  is a separate enhancement noted in tests.
- **m= media-type value set (audit D1.5) — NOT enforced; future-
  warning candidate.** The audit recommended rejecting any m= media
  type outside `{audio, video, text, application, message}` (and the
  IANA-registered extensions) per RFC 8866 §5.14, with §8.2.2
  removing `control` and `data` (which RFC 4566 had listed).
  Careful re-read of the verbatim text shows the relevant
  prohibitions are weaker than the audit assumed:
  - **§5.14** *defines* the five values and notes the list "may be
    further extended by additional memos registering media types in
    the future" — no `MUST be one of` wording.
  - **§8.2.2** is a Note that says these "have been removed in this
    specification" and "applications **SHOULD NOT** use these types
    and SHOULD NOT declare support for them in SIP capabilities…
    (even though they exist in the registry created by [RFC3840])."
  The SHOULD NOT is grounded in real backward-compat (SIP user agents
  still hold these in their capability registry via RFC 3840), not a
  spec-draft artifact that would tighten in a later revision. Per
  CLAUDE.md "Validation Strictness Principle" (only positive shall /
  prohibitive shall-not / defined-value optionals warrant rejection),
  bare SHOULD-level guidance is recommendatory and excluded.
  **Action**: marked as a future-warning candidate. When/if the
  parser grows a warning channel, `m=control` and `m=data` should
  emit a warning citing RFC 8866 §8.2.2 (and any future m= subtype
  outside the §5.14 list could too). No parser change in this commit.
- **IPv6 multicast TTL forbidden at base tier (audit D1.4).** RFC 8866
  §5.7: *"TTL value MUST NOT be present for 'IP6' multicast."* §9
  ABNF: `IP6-multicast = IP6-address [ "/" numaddr ]` — the only
  permitted suffix for IPv6 multicast is `/numaddr`, never `/ttl` or
  `/ttl/numaddr`. The same `valid_connection_address` hoist landed in
  D1.3 already enforces both IPv4 (`/ttl` required) and IPv6
  (`/numaddr` only) rules at the base tier; D1.4 is the IPv6-side
  test coverage of that hoist. 5 new tests in `spec/sdp_spec.lua`:
  unicast IPv6 no-suffix pass, multicast IPv6 `/numaddr` pass,
  multicast IPv6 `/ttl/numaddr` reject (the IPv4-mirror error mode),
  multicast IPv6 `/0` numaddr=0 reject, and unicast IPv6 `/suffix`
  reject. All cite `RFC 8866 §5.7`.
- **IPv4 multicast `c=` /ttl mandatory hoisted to base tier (audit
  D1.3).** RFC 8866 §5.7 / §9 ABNF: *"IP4-multicast = m1 3('.'
  decimal-uchar) '/' ttl [ '/' numaddr ]"* — the `/ttl` suffix is
  required for IPv4 multicast c= lines. The check previously lived
  only at the ST 2110 tier (which called `valid_connection_address`
  on session/media c=); base-tier `doc:validate()` silently accepted
  `c=IN IP4 239.100.0.1` (no TTL). Added a `valid_connection_address`
  call in `validate.sdp` for both session-level (`doc.session.
  connection`) and per-media (`m.connection`) c= entries, with cite
  `RFC 8866 §5.7`. Refactored `valid_connection_address` to take an
  optional `tier` argument (`"base"` / `"st2110"`, default
  `"st2110"`) and gated the ST 2110-10 §6.5 forbidden-multicast-range
  check behind `tier == "st2110"` so the SMPTE-specific rule doesn't
  leak into the base tier with the wrong cite. The previously
  forward-declared `valid_connection_address` is now declared at the
  top of the Validate section so `validate.sdp` can reference it.
  5 new tests in `spec/sdp_spec.lua` (unicast pass, multicast +TTL
  pass at session and via `/ttl/numaddr`, multicast no-TTL reject at
  both session and media level).
- **Dynamic-PT requires a=rtpmap hoisted to base tier (audit D1.2).**
  RFC 8866 §8.2.3: *"If the payload type number is dynamically
  assigned by this session description, an additional 'a=rtpmap:'
  attribute MUST be included to specify the format name and
  parameters as defined by the media type registration for the
  payload format."* The parser previously enforced rtpmap presence
  only at the ST 2110 tier (unconditional, since ST 2110 mandates
  rtpmap for every stream). Added a per-media block check in
  `validate.sdp` that walks `m.fmts`, identifies each dynamic PT
  (96–127 per RFC 3551 §6 / RFC 8866 §6.6), and verifies a matching
  `a=rtpmap` exists in `m.attributes`. Cite: `RFC 8866 §8.2.3`.
  Scope: only fires when `m.proto` contains "RTP" (the rule is
  RTP-specific). Two pre-existing `dup_sdp` test helpers hardcoded
  `m=… RTP/AVP 96` but allowed callers to override `rtpmap2` to use
  PT 97 — an internal inconsistency that the new check correctly
  flags. Updated both helpers to extract the PT from the rtpmap
  string and emit a matching `m=` fmt. 7 new tests in
  `spec/sdp_spec.lua` covering dynamic-PT match pass, missing-rtpmap
  reject, wrong-PT-rtpmap reject, static-PT (no rtpmap) pass,
  non-RTP-proto skip, multi-PT both-mapped pass, and multi-PT one-
  unmapped reject.
- **`k=` (encryption-key) line obsoleted (audit D1.1).** RFC 8866
  §5.12: *"The 'k=' line (key-field) is obsolete and MUST NOT be
  used. It is included in this document for legacy reasons. One MUST
  NOT include a 'k=' line in an SDP, and MUST discard it if it is
  received in an SDP."* The parser previously stored session-level
  `k=` at `doc.session.key` and media-level `k=` at `doc.media[i].key`,
  and the serializer round-tripped both. Per the §5.12 receiver MUST,
  k= is now parsed-and-discarded (the line is consumed so we advance
  past it, but no value is stored). Per the §5.12 sender MUST NOT,
  the serializer no longer emits k= even when a caller hand-constructs
  a doc with `session.key` or `media[i].key` set. Removed `ser_key`
  helper and the `key` field initialization in the session table
  builder; the `parse_required` calls that previously bound
  `session_key` / `m.key` now bind throwaway locals (`discarded`).
  Updated three sdp_spec tests to assert discard semantics (no
  `doc.session.key`, no `doc.media[i].key`) and the round-trip
  fully-loaded test to assert the serialized output contains no
  `k=` substring.
- **CLAUDE.md / PLAN.md base spec rename (audit D1.7).** Updated the
  three-tier description (`RFC 4566 (generic SDP) → SMPTE ST 2110 →
  IPMX`) to `RFC 8866 (generic SDP; obsoletes RFC 4566) → SMPTE
  ST 2110 → IPMX` in CLAUDE.md, and the matching layered-tiers note
  in PLAN.md. Updated four other "RFC 4566" mentions in CLAUDE.md
  (Project Purpose, Public API examples, "Strict by default", "Key
  References", "Things to Watch Out For") to RFC 8866. RFC 4566 is
  kept in Key References as the historical predecessor. No code or
  parser-behavior changes — this commit establishes the base-spec
  context that Wave 5's six following commits (D1.1–D1.6) operate
  in. README.md / GUIDE.md mentions of RFC 4566 are user-facing API
  documentation and will land in their own commits as those tiers'
  behavior actually shifts.

### Fixed (audit pass #31 — Wave 4 parser fixes)

- **RFC 4570 §3.1 dest-address ↔ c= cross-line check (audit A11; user
  decision D3 — full RFC 8866 expansion).** RFC 4570 §3.1: *"The
  `<dest-address>` value in a 'source-filter' attribute MUST correspond
  to an existing `<connection-field>` value in the session description.
  The only exception to this is when a '*' wildcard is used to
  indicate that the source-filter applies to all `<connection-field>`
  values."* Previously the parser validated source-filter syntax via
  `valid_source_filter` but never cross-checked the dest-address
  against any `c=` line, so a SDP with `c=IN IP4 239.100.0.1/64` and
  `a=source-filter: incl IN IP4 239.200.0.1 192.168.1.1` was
  accepted. Added a post-loop check in `st2110.validate` that:
  1. Builds a set of every c= address in the SDP (session-level +
     every media-level) with RFC 8866 §5.7 `/numaddr` expansion —
     IPv4 multicast addresses contiguously above the base
     (`233.252.0.1/127/3` ⇒ `.1`, `.2`, `.3`), IPv6 multicast same
     pattern with 16-bit-group carry (`ff00::db8:0:101/3` ⇒ `:101`,
     `:102`, `:103`).
  2. For each session-level and media-level source-filter, normalises
     the dest-address to the same canonical form and rejects if not
     in the set.
  3. Skips the cross-check when source-filter `addrtype` is `*`
     (per §3.1 the dest is an FQDN or `*` literal in that case;
     literal-set membership doesn't apply).
  Cite: `RFC 4570 §3.1`. Two pre-existing test fixtures that paired
  an IP6 source-filter with an IP4 `c=` line (which is itself a §3.1
  violation) were corrected to align their addrtypes. 9 new tests
  under a dedicated `RFC 4570 §3.1 dest-address ↔ c= cross-line
  check` describe block exercising match, /numaddr expansion both
  families, mismatch reject, cross-level matching, and the `*`
  addrtype skip. **Wave 4 complete.**

  New parse_sdp.lua helpers (private): `_ipv4_to_int`, `_int_to_ipv4`,
  `_ipv6_to_groups` (handles `::` expansion), `_ipv6_canonical`
  (8-group lowercase-hex form), `_ipv6_add` (16-bit-group carry),
  `expand_connection(addr_type, addr)`,
  `canonicalize_address(addr_type, addr)`, and
  `source_filter_dest(value)`.

### Fixed (audit pass #31 — Wave 3 parser fixes)

- **RFC 7273 cite-upstream for ts-refclk / mediaclk value-form errors
  (audit E5).** ST 2110-10:2022 §7.2 and §7.3 mandate that ts-refclk
  and mediaclk respectively *be present*, but defer the *value form*
  (clksrc literals, ptp-version, EUI-64 grandmaster identifier,
  sender/direct/rate literals) to RFC 7273. The parser previously
  cited `ST 2110-10:2022 §7.2`/`§7.3` for both presence AND
  value-form errors. Migrated the two value-form `attr_err` sites to
  upstream cites:
  - `invalid ts-refclk` value → `RFC 7273 §4` (Figure 1 ABNF).
  - `invalid mediaclk` value → `RFC 7273 §5` (mediaclk forms).
  Presence cites (missing ts-refclk / missing mediaclk) keep the
  `ST 2110-10:2022 §7.2`/`§7.3` cite because the SHALL-be-present
  requirement is SMPTE-specific (RFC 7273 doesn't mandate either
  attribute be present). `ST 2110-10:2022 §8.3` cite for
  session-level mediaclk rejection and `ST 2110-10:2022 §8.2` cite
  for the PTP-domain-required tightening also stay (both are SMPTE
  narrowings of RFC 7273). Added 3 regression-protection tests in a
  new `RFC 7273 cite-upstream for value-form errors` describe block.
- **Any a=group ⇒ every m= has a=mid (audit A10).** RFC 5888 §6:
  *"All of the 'm' lines of a session description that uses 'group'
  MUST be identified with a 'mid' attribute whether they appear in the
  group line(s) or not."* The parser walked a=group:DUP-specific
  semantics only (via `each_dup_group`), so an SDP carrying
  `a=group:LS 1 2` with one of the two media blocks missing a=mid
  was accepted. Added a session-level pre-check in `st2110.validate`
  next to the existing RFC 5888 §5 a=group grammar check: if ANY
  session attribute is `group` (LS, FID, DUP, …), scan every media
  block for `a=mid` presence and reject with `spec_ref="RFC 5888 §6"`
  on the first missing one. Two pre-existing tests using
  `omit_mid2 = true` now correctly trigger the §6 path first (they
  used to surface the downstream "DUP references undefined mid"
  error) and were refactored to assert §6 explicitly, plus a separate
  scenario was used for the §8.5 spec_ref assertion. 4 new tests
  under a dedicated `RFC 5888 §6: a=group requires a=mid on every
  m= line` describe block. Two IPMX FID-rejection fixtures now
  include `a=mid` so they still reach the IPMX-tier check.
- **TSMODE / TSDELAY scope hoisted to all media types (audit A8).**
  ST 2110-10:2022 §8.7 is under "SDP Parameters" (§8) — the umbrella
  section that applies to every RTP stream conforming to ST 2110, not
  the uncompressed-video subsection. The TSMODE and TSDELAY validators
  lived inside the raw-video `video_opt_checks` table and ran only when
  `m.media == "video"` with encoding `raw`, so jxsv, audio, smpte291,
  and ST 2110-41 streams skipped both the value-form check and the
  SAMP→TSDELAY cross-rule entirely. Moved the TSMODE enum check, the
  TSDELAY positive-integer check, and the SAMP→TSDELAY cross-rule out
  of the raw-video arm and into a single block that runs after the
  encoding-specific branches conclude, still inside the per-media
  loop. Same `spec_ref="ST 2110-10:2022 §8.7"`, same error messages.
  7 new tests under a `TSMODE / TSDELAY scope is umbrella, not
  raw-video` describe block exercising audio, smpte291, and jxsv
  paths.
- **m=video raw subtype assertion (audit A4).** ST 2110-20:2022 §7.1:
  *"For an uncompressed Active Video RTP Stream, the Media Type Field
  shall be 'video' and the Media Subtype name 'raw' shall be used."*
  The raw-video branch (`m.media == "video"`) keyed only on the media
  name, so `m=video 5000 RTP/AVP 96` paired with
  `a=rtpmap:96 foo/90000` routed through the ST 2110-20 raw-video
  validators with no encoding-name check. Added a pre-branch
  `enc and enc ~= "raw"` reject with `spec_ref="ST 2110-20:2022 §7.1"`.
  Safe today because `jxsv` and `smpte291` are dispatched before this
  branch; widen the check when new `m=video` codecs land. 3 new tests
  (raw pass, foo reject, rawvideo reject) under a new
  `ST 2110-20:2022 §7.1 m=video subtype 'raw' assertion` describe
  block in `spec/st2110_spec.lua`.
- **SSN=ST2110-40:2021 receiver-equivalence (audit A1; user decision
  D2).** ST 2110-40:2023 §7: *"Receivers shall consider a Format
  Specific Parameter SSN value of ST2110-40:2021 as equivalent to a
  value of ST2110-40:2023."* The parser previously demanded an exact
  `ST2110-40:2023` when TM was signaled, rejecting spec-conformant
  senders that emit `:2021`. The parser acts as a receiver here, so
  rejecting `:2021` violates the receiver SHALL. Updated the smpte291
  SSN check: when TM is signaled, accept either `ST2110-40:2023` or
  `ST2110-40:2021`; when TM is absent, still require `ST2110-40:2018`
  (bare `:2021` is not equivalent to `:2018`). Reworded the error
  message to note the equivalence. 3 new tests in
  `spec/st2110_spec.lua` (2021+LLTM pass, 2021+CTM pass, bare-2021
  reject).

### Fixed (audit pass #31 — Wave 2 parser fixes)

- **Mixed traceable / non-traceable ts-refclk rejection (audit A13).**
  RFC 7273 §4.8: *"Traceable time sources MUST NOT be mixed with
  non-traceable time sources at any given level."* The parser
  validates every ts-refclk individually but never cross-checks the
  traceability classes at the same level. Added a per-level
  mixed-class check in `st2110.validate`: one pass over session-level
  ts-refclks, then per-media-block over media-level ts-refclks. Class
  is computed by a new `tsrefclk_traceability(value)` helper —
  `gps`/`gal`/`glonass` and any value containing `:traceable` are
  traceable; everything else (specific PTP `gmid:domain`,
  `localmac=`, plain `ntp=`) is non-traceable. Mixed within one level
  rejects with `spec_ref="RFC 7273 §4.8"`; mixing across levels is
  permitted (the spec is per-level). 5 new tests under an
  `RFC 7273 §4.8 mixed-class rejection` describe block.
- **Session-level a=source-filter syntax validation (audit A12).**
  Asymmetric coverage: the per-media loop in `st2110.validate` has
  always called `valid_source_filter` on every media-level
  `a=source-filter`, but the session-level scan only checked
  presence (in the IPMX validator). A session-level
  `a=source-filter` with malformed syntax was therefore accepted.
  Added a symmetric session-level walk in `st2110.validate` (between
  the session-c= check and the per-media loop) that runs
  `valid_source_filter` on every session-level `a=source-filter`
  value and rejects with `spec_ref="RFC 4570 §3"` on syntax failure.
  IPMX inherits via the chained `st2110.validate` call. 2 new tests
  (pass + missing-src reject) under a dedicated session-level
  describe block.
- **TSMODE=SAMP requires TSDELAY (audit A9).** ST 2110-10:2022 §8.7
  (and §7.9): *"Devices which signal TSMODE=SAMP shall also signal
  their Transmission Delay value in the SDP as indicated in
  section 8.7."* TSMODE and TSDELAY validators ran independently
  inside `video_opt_checks`, so a fmtp line carrying `TSMODE=SAMP`
  with no `TSDELAY` parameter was accepted. Added a post-loop
  cross-check in the raw-video branch: if
  `tostring(params["TSMODE"]) == "SAMP"` and `params["TSDELAY"] == nil`,
  reject with `spec_ref="ST 2110-10:2022 §8.7"`. Scope is raw-video
  only today; A8 (Wave 3) will hoist TSMODE/TSDELAY validation to all
  media types and this cross-check should hoist with it. Updated the
  legacy `accepts TSMODE=SAMP` test to pair it with TSDELAY=100, and
  added 2 new tests under a `TSMODE=SAMP → TSDELAY presence (§8.7)`
  describe block.
- **Drive-by nil-safety fix in the A2 VPID_Code cardinality check.**
  The A2 commit indexed `fmtp.value` unconditionally; AMWA upstream's
  `nmos-testing:data.sdp` fixture has a smpte291 media block without
  an `a=fmtp` line, which surfaced as `attempt to index a nil value`
  in the conformance suite. Guarded the count with `if fmtp then`,
  matching the surrounding optional-fmtp pattern (the rest of the
  smpte291 branch already null-checks `fmtp`).
- **Whitespace around '=' in raw-video fmtp tokens (audit A7).**
  ST 2110-20:2022 §7.1: *"Each parameter entry shall be constructed as
  either: 'name=value' (no whitespace) or 'name' (no value)."* The
  shared `fmtp_params` helper matched `^([^=%s]+)%s*=%s*(.-)$`, silently
  accepting `width = 1920`, `width =1920`, and `width= 1920`. The check
  is grounded in the -20 §7.1 wording only, so the strict rule was
  added inside `valid_st2110_20_fmtp_format` (which already runs only
  in the raw-video branch with the §7.1 cite) rather than tightening
  the shared parser globally. No in-repo fixture relies on the lenient
  form. 4 new tests under the §7.1 fmtp-format describe block
  (spaces-both-sides reject, space-before reject, space-after reject,
  canonical pass).
- **BT2100 colorimetry restricts RANGE to {NARROW, FULL} (audit A6
  subset).** ST 2110-20:2022 §7.3: *"When the colorimetry value is
  BT2100, only the NARROW and FULL values are permitted."* The
  raw-video branch validated RANGE against the global
  `{NARROW, FULLPROTECT, FULL}` enum independently of colorimetry, so
  `colorimetry=BT2100; RANGE=FULLPROTECT` was accepted. Added a
  post-enum cross-check in the `range_val` block: if
  `params["colorimetry"] == "BT2100"` and `range_val == "FULLPROTECT"`,
  reject with `spec_ref="ST 2110-20:2022 §7.3"`. Scope: raw video only
  — jxsv RANGE per RFC 9134 §7.1 is independent and the spec doesn't
  import this cross-rule. 3 new tests under the `RANGE` describe block
  (BT2100+NARROW pass, BT2100+FULL pass, BT2100+FULLPROTECT fail).
- **jxsv width/height 1..32767 upper bound (audit A5).** ST 2110-22:2022
  §7.2 Table 1 restates ST 2110-20:2022 §7.2: *"Permitted values are
  integers between 1 and 32767 inclusive."* The jxsv branch used
  `valid_pos_int` for `width` and `height`, enforcing only the lower
  bound; the raw-video branch already used `valid_width` /
  `valid_height` (which cap at 32767). Swapped jxsv `width`/`height` to
  `valid_width`/`valid_height` for symmetry with the raw-video tier. 3
  new tests in the JPEG-XS describe block (boundary pass, width=32768
  fail, height=99999 fail).
- **SSN year-suffix closed sets (audit A3).** ST 2110-20:2022 §7.2
  defines only `:2017` and `:2022`; ST 2110-22:2022 §7.2 Table 2 defines
  only `:2019` and `:2022`; ST 2110-41:2024 §6 defines only `:2024`.
  Previously `_ssn_year` matched any 4 decimal digits, so
  `SSN=ST2110-20:1999` or `:9999` was accepted as a value-form. Replaced
  with explicit closed sets:
  - `_ssn20_pat`: `(P("2017") + P("2022"))`
  - `_ssn22_pat`: `(P("2019") + P("2022"))`
  - `_ssn41_pat`: `P("2024")`
  All in-repo fixtures (`spec/fixtures/`, `examples/`) already use
  permitted years, so no fixture churn. 3 new pass/fail tests in
  `spec/st2110_spec.lua` under the §7.2 SSN coupling describe block.
- **VPID_Code cardinality (audit A2).** RFC 8331 §4 (smpte291 media-type
  registration) states: *"VPID_Code shall appear only once and a single
  integer value shall be expressed."* The parser's `fmtp_params` helper
  silently coalesces duplicate keys, so a fmtp line carrying
  `VPID_Code=132; VPID_Code=133` was accepted with the last value kept.
  Added a duplicate-count check in the smpte291 branch that counts raw
  `VPID_Code=` occurrences in the unparsed fmtp value and rejects if >1
  with `spec_ref="RFC 8331 §4"`. Single-occurrence and absent cases
  remain accepted. 1 new test in `spec/st2110_spec.lua`.
- **DID_SDID hex-token width (audit B1).** RFC 8331 §4 ABNF defines
  `TwoHex = "0x" 1*2(HEXDIG)` — 1 OR 2 hex digits per token. The parser
  previously demanded exactly 2 digits (`^{0x%x%x,0x%x%x}$`), rejecting
  spec-legal forms like `DID_SDID={0x6,0x2}`. Relaxed the pattern to
  `^{0x%x%x?,0x%x%x?}$` and updated the error-message hint to
  `{0xH[H],0xH[H]}`. Tokens with 3+ hex digits or empty tokens still
  reject. 4 new tests in `spec/st2110_spec.lua` (3 pass paths, 2 fail
  paths). 781 hermetic + 10 conformance tests pass.

### Fixed (audit pass #31 — citation cleanup)

- **Conformance manifest `expect_spec_ref` follow-up to E8.** The
  nmos-testing video-2022-7 negative-test fixture expected
  `"ST 2110-10 §8.5"`; E8's year-tag pass made the parser emit
  `"ST 2110-10:2022 §8.5"` instead. Updated the manifest's
  `expect_spec_ref` to match the new emitted form. Conformance suite
  10/10 passes again.
- **Year-tag consistency pass on ST 2110 cites (audit E8).** Prior
  cite-style mixed `ST 2110-XX` and `ST 2110-XX:YYYY` for the same
  spec. Standardized on `ST 2110-XX:YYYY §Z` for all revision-specific
  clauses:
  - `ST 2110-10 §X` → `ST 2110-10:2022 §X` (12 distinct cite strings)
  - `ST 2110-20 §X` → `ST 2110-20:2022 §X` (4 cites)
  - `ST 2110-22 §X` → `ST 2110-22:2022 §X` (3 cites)
  - `ST 2110-30 §6.2.2` → `ST 2110-30:2025 §6.2.2`
  - `ST 2110-30 §7.1` → `ST 2110-30:2025 §6.1` (§7 in :2025 is
    "Conformance Levels"; the encoding-name SHALL for L16/L24 sits at
    §6.1 in the current revision)
  - `ST 2110-30 §7.2` → `ST 2110-30:2025 §6.2.1` (the ptime
    value-form rule chains via §6.2.1's AES67 reference)
  Behavior unchanged; 16 test hard-assertions on spec_ref updated;
  62 lines changed across parse_sdp.lua, spec/st2110_spec.lua, and
  spec/errors_spec.lua. 777 hermetic + 10 conformance tests still
  pass.
- **ST 2022-7 parenthetical removed from DUP error-message text (audit
  E7).** Phase 1's independent spec walk confirmed that ST 2022-7:2013
  contains no SDP-level normative clauses (the §6 "RTP header and RTP
  payload shall be identical for each datagram copy" is a wire-format
  SHALL). The structured `spec_ref` already correctly points at
  ST 2110-10 §8.5 — the SDP-tier authority. Removed the misleading
  `(ST 2022-7 §6)` parenthetical from two user-facing error messages
  (`a=group:DUP` PT-mismatch and fmtp-mismatch) and added comments
  explaining the wire-format-to-SDP derivation. No behavior change.
- **MAXUDP-on-smpte291 cite §6.1.4 → §5.2.1 (audit E3).** ST 2110-40:2023
  has no §6.1.4 — §6 is "Timing Model" with §6.1 General, §6.2 Definitions
  of Time Offsets (with §6.2.1 / §6.2.2), §6.3, §6.4, §6.5. The "UDP size
  of each RTP packet shall not exceed the Standard UDP Size Limit" SHALL
  is at §5.2.1 (RTP Payload Format / General Requirements), verified
  against the on-disk 2023 PDF. Updated `parse_sdp.lua:1463-1470` plus
  the user-facing error message text and two test cite-string
  references. Behavior unchanged.
- **ST 2110-40 cite cleanup (audit E2).** Two smpte291 cite sites
  previously cited `ST 2110-40 §7.2`, a section that doesn't exist in
  ST 2110-40:2023 (§7 has no numbered subsections). Verified against
  the on-disk 2023 PDF: the rtpmap clock-rate=90000 SHALL is at §5.3
  (*"The RTP Clock rate shall be 90 kHz."*); the VPID_Code integer
  value form is defined by RFC 8331 §4 (smpte291 media-type
  registration). Updated `parse_sdp.lua:1377` to `ST 2110-40:2023 §5.3`
  and `parse_sdp.lua:1399` to `RFC 8331 §4`. One test assertion
  updated to match. Behavior unchanged.
- **a=mid uniqueness cite RFC 5888 §8.1 → §4 (audit E4).** RFC 5888 §4:
  *"The identification-tag MUST be unique within an SDP session"* — that
  is the operative MUST. §8.1 is the IANA registration section and
  contains no uniqueness MUST. Updated `parse_sdp.lua:2062` and the
  comment at `:2046` plus two test cite strings. Behavior is unchanged.
- **RFC 5285 cites migrated to RFC 8285 (audit E1).** RFC 8285 (October
  2017) obsoletes RFC 5285. The `a=extmap` attribute is now defined in
  RFC 8285; the SDP signaling and ID-uniqueness rules live in §5 (was
  §3 in RFC 5285), the ABNF in §8 (was §8), and the 1–255 entry-count
  bound derives from §4.3 (two-byte header). Updated nine cite sites
  in `parse_sdp.lua` (one comment, one error-message text, four
  `spec_ref` strings, three uniqueness sites) plus two test
  describe-string cites and one hard test assertion. Behavior is
  unchanged.

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

- **`fbblevel` SDP fmtp check removed (audit D2).** No spec defines
  `fbblevel` as an SDP fmtp parameter. It appears only in the RTCP
  JPEG-XS Media Info Block (TR-10-15-Part1 §12, encoded in the Plev
  16-bit field alongside `sublevel`). The previous "TR-10-11 §12" cite
  was wrong (TR-10-11 §12 describes the RTCP MIB, not SDP fmtp). Per
  the strictness principle, the check is removed; the parser accepts
  `fbblevel=…` in jxsv fmtp without validating its value form. Doc
  updates the optional-jxsv-params table and the descriptive paragraph
  accordingly.
- **Audio `a=ptime` required + cite corrected (audit D1).** TR-10-3 §8 is
  *"Payload Formats and Sample Rates"* and contains no ptime SHALL — the
  previous IPMX-tier `spec_ref = "TR-10-3 §8"` was wrong. The actual
  chain: ST 2110-30:2025 §6.2.1 first sentence — *"Digital audio streams
  shall conform to AES67, including the Session Description Protocol
  (SDP) as described in IETF RFC 8866"* — pulls in AES67-2018 §8.1:
  *"Descriptions shall include a ptime attribute indicating the desired
  packet time."* TR-10-3 §7 line 149 makes IPMX PCM audio chain to AES67
  the same way. Therefore `a=ptime` is required for **all** audio at the
  ST 2110 tier (extended from the AM824-only requirement that landed in
  N4). Cite now reads `ST 2110-30:2025 §6.2.1`. The redundant IPMX-tier
  check is removed (subsumed). The audio packet-fit check now uses the
  fixed Standard UDP Limit (1460 B) since MAXUDP is forbidden on audio
  (N11), and rounds samples-per-packet to nearest integer per AES67 §8.1.
- **ST 2110-20:2022 cross-parameter SHALLs on raw video (audit N12 + N13).**
  - **N12 (§7.4.1)** — *"The Key signal does not have a specific TCS or
    Colorimetry value itself; the Key stream shall signal the colorimetry
    value 'ALPHA', and shall not signal a TCS value."* `sampling=KEY`
    now requires `colorimetry=ALPHA` and rejects any `TCS=…`. Scoped to
    raw video — RFC 9134 §7.1 imports the sampling value set into jxsv
    but does not import the cross-parameter SHALL (verified explicitly).
  - **N13 (§6.2.5)** — *"The 4:2:0 sampling system shall only be applied
    to progressive scan images transmitted in a progressive manner."*
    `sampling={YCbCr,CLYCbCr,ICtCp}-4:2:0` combined with the bare
    `interlace` flag is rejected. Scoped to raw video — §6.2.5 sits in
    the RTP-payload chapter, which jxsv does not use.
- **MAXUDP forbidden on smpte291 / ST2110-41 / audio (audit N11).** Three
  SHALLs in the per-essence specs constrain UDP size to the Standard
  Limit (1460 octets, ST 2110-10:2022 §6.3). MAXUDP is the signal that
  a sender *exceeds* that limit (ST 2110-10:2022 §6.4 / §8.6), so its
  presence on these encodings is non-conformant:
  - **ST 2110-40:2023 §6.1.4** — *"The UDP size of each RTP packet shall
    not exceed the Standard UDP Size Limit."* Reject MAXUDP on smpte291.
  - **ST 2110-41:2024 §5.4** — *"The total length of the UDP packet that
    encompasses each RTP Packet shall be less than or equal to the
    Standard UDP Size Limit defined in SMPTE ST 2110-10."* Reject MAXUDP
    on ST2110-41.
  - **ST 2110-30:2025 §6.2.1** — *"The Standard UDP Datagram Size Limit
    as defined in SMPTE ST 2110-10 shall be used."* Reject MAXUDP on
    L16/L24/AM824.
- **ST 2110-40:2023 §7 FID prohibition at the ST 2110 tier (audit N10).**
  §7: *"Flow Identification ('FID') semantics shall not be used under this
  standard."* The SHALL is in -40, which governs smpte291, so the
  ST 2110-tier check fires only when at least one media block carries
  smpte291. (The IPMX-tier check at TR-10-1 §10 remains broader: it
  rejects any `a=group:FID`, regardless of essence.)
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
