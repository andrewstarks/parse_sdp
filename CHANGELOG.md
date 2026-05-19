# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] — `refactor/grammar-first` branch

Ground-up rewrite of the parser per [REFACTOR-PLAN.md](REFACTOR-PLAN.md).
**Internal-only so far; no public-API change has landed yet.** The 1.0
parser remains the shipping artifact on `main`.

### Added

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
REFACTOR-PLAN.md §5 is decomposed. The base SDP grammar produces
a rich, fully-typed doc table — no consumer needs to re-parse a
captured string. 64 new tests across Phase 4 (1030 → 1094).

### Changed

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
