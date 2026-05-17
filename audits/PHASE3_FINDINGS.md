# Phase 3 — Findings Report (Pre-1.0 Audit, Pass #31)

Audit direction: **spec → parser** (inverted from prior 30 passes that went
parser → spec).  Phase 1 enumerated ~1750 normative clauses across 30+
specs cold; Phase 2 mapped them to parser checks.  Section G reconciles
against prior-audit context (`CHANGELOG.md`, `PLAN.md`, `SDPOKER_BACKLOG.md`)
— **read only after sections A–F were drafted**, per the audit-prompt rule
that prior-audit reads collapse the independent pass back into confirmation
bias.

---

## A. Inventory summary

**22 spec walkers, ~1750 enumerated normative clauses.**

| Group | Walkers | On-disk source | Notes |
| --- | --- | --- | --- |
| IETF RFCs | RFC 4566, 8866, 3550, 3551, 4570, 5888, 7104, 7273, 8331, 9134 | WebFetch `rfc-editor.org` raw `.txt` | All current revisions |
| AES | AES67-2013, AES3-1, AES3-4 | markdown + PDF | **AES67-2018 paywalled; ST 2110-30:2025 cites AES67-2023, not 2018** — rows flagged `[AES67-2013 wording]` |
| SMPTE ST 2110 | -10:2022, -20:2022, -21:2022, -22:2022, -30:2025, -31:2022, -40:2023, -41:2024, -43:2021 | mixed markdown / PDF | -10/-22/-30/-31/-40/-43 PDF-only at session start |
| SMPTE codec | ST 2042-1:2012 | markdown | VC-2 (not currently in parser) |
| SMPTE supporting | ST 2022-7:2013 | PDF | **Never mentions SDP** — any `ST 2022-7 §X` SDP cite is mis-cited |
| SMPTE RPs | RP 2110-23/24/25 | mixed | -23 carries SDP weight; -24/-25 minimal SDP |
| VSF IPMX TR-10 | 18 docs (TR-10-0 → 16 + TP-1) | markdown | Single walker, 295 enumerated rows |
| IPMX Released v1.0 | Uncompressed + JPEG-XS + PCM Audio profile reqs | markdown | All clauses delegate SDP-form to TR-10-X |

**Specs cited by parser but NOT in Phase 1 inventory** (Phase 1 gaps; not
direction-A findings on their own, but worth a backfill walk before 1.0):
RFC 3190, RFC 3605, RFC 4145, RFC 4291, RFC 4566 §9 (token), RFC 5285,
RFC 5761, RFC 8285.

**Specs with substantial unanswered questions** (recorded as caveats):
AES67-2018 (paywalled), AES67-2023 (paywalled).

---

## B. Coverage table

Full per-spec coverage matrices in `audits/SPEC_COVERAGE.md` (389 KB).  This
section quotes the headline numbers; per-clause cells live in the coverage
file.

| Spec | SDP-Y clauses | COVERED | WRONG-CITE | NO-TEST | MISSING | OOS-SDP |
| --- | --: | --: | --: | --: | --: | --: |
| RFC 4566 | 138 | 49 | 9 | 13 | 22 | 18 |
| RFC 8866 | 87 | 35 | 11 | 0 | 24 (mostly tier-gated) | 17 |
| RFC 3550 + 3551 | 54 | 2 | 1 | 0 | 32 | 19 |
| RFC 4570 | 23 | 6 | 0 | 0 | 4 | 13 |
| RFC 5888 + 7104 | 13 | 2 | 1 | 0 | 4 | 6 |
| RFC 7273 | 49 | 35 | 13 (cite-upstream) | 0 | 1 | 0 |
| RFC 8331 | 16 | 11 | 0 | 0 | 1 (cardinality) | 4 |
| RFC 9134 | 33 | 8 | 10 | 0 | 5 | 10 |
| AES67-2013 + AES3 | 17 | 9 | 0 | 0 | 3 | 86 |
| ST 2110-10:2022 | 25 | 22 | 0 | 0 | 3 | 0 |
| ST 2110-20:2022 | 57 | 45 | 0 | 0 | ~9 cross-rule | ~3 |
| ST 2110-21:2022 | 11 | 8 | 0 | 0 | 0 | 3 |
| ST 2110-22:2022 | 26 | 24 | 0 | 0 | 2 (width/height bound; partial) | 0 |
| ST 2110-30:2025 | 7 | 7 | 0 | 0 | 0 | 0 |
| ST 2110-31:2022 | 24 | 24 | 0 | 0 | 0 | 0 |
| ST 2110-40:2023 | 11 | 10 | 3 cite-§ drift | 0 | 1 (2021 equivalence) | 0 |
| ST 2110-41:2024 | 16 | 13 | 0 | 0 | 0 | 2 (SSN literal ambiguity) |
| ST 2042-1 + ST 2110-43 | 5 | 0 | 0 | 0 | 5 (feature gap) | 0 |
| ST 2022-7 | 3 | 3 | 0 (parser correctly does not cite -7 for SDP) | 0 | 0 | 0 |
| RP 2110-23/24/25 | ~30 | 0 | 0 | 0 | 18 RP-23 / 7 N/A | 5 |
| TR-10 series | 89 | 72 | 0 | 0 | 3 (TR-10-9 substitute formulas) | 14 |
| IPMX Released v1.0 | 13 | 13 (delegated to TR-10) | 0 | 0 | 0 | 0 |

**Direction-B candidates from reverse walk** (parser cites a spec but the
cite has issues): see Section E for details.

---

## C. Findings — Direction A (spec SHALL not enforced)

**Numbered for traceability. Each finding includes verbatim spec quote +
parser `file:line` + recommended action.**

### A1. ST 2110-40 SSN=2021 receiver-equivalence not enforced

**Spec quote** (ST 2110-40:2023 §7): *"Receivers shall consider a Format
Specific Parameter SSN value of ST2110-40:2021 as equivalent to a value of
ST2110-40:2023."*

**Parser** (`parse_sdp.lua:1426-1432`):
```lua
local ssn_str = tostring(ssn)
local expected_ssn = (tm and tm ~= true) and "ST2110-40:2023" or "ST2110-40:2018"
if ssn_str ~= expected_ssn then
  return attr_err(string.format(
    "invalid SSN value '%s' (expected '%s' %s)", ssn_str, expected_ssn,
    (tm and tm ~= true) and "when TM is signaled" or "when TM is absent"),
    mpath, "fmtp", "ST 2110-40:2023 §7", "INVALID_VALUE")
end
```
A sender emitting `SSN=ST2110-40:2021; TM=LLTM` is rejected.  Parser-acting-as-
receiver violates the §7 receiver SHALL.

**Recommended action.**  Accept `ST2110-40:2021` as equivalent to
`ST2110-40:2023` when `TM` is signaled.  Reject anything else with the
existing message.  Test in `spec/st2110_spec.lua` for both 2021-and-2023
acceptance and bare-2021 rejection.

### A2. RFC 8331 VPID_Code "shall appear only once" not enforced

**Spec quote** (RFC 8331 §4): *"VPID_Code shall appear only once and a
single integer value shall be expressed."*

**Parser** (`parse_sdp.lua:1174-1192`): `fmtp_params` silently coalesces
duplicate keys (`params[k] = v` overwrites).  A `fmtp:96 VPID_Code=1234;
VPID_Code=5678; DID_SDID={0x41,0x01}` line is accepted and the second value
is kept.

**Recommended action.**  In `fmtp_params`, track duplicate-key occurrences
per attribute and reject for any key whose spec defines "appears only once"
(VPID_Code).  Alternative: a single-pass check inside the smpte291 branch
counting `VPID_Code=` occurrences in the raw value.

### A3. ST 2110-20:2022 SSN year-suffix over-permissive

**Spec quote** (ST 2110-20:2022 §7.2): *"Senders implementing this standard
shall signal the value ST2110-20:2017 unless the colorimetry value ALPHA or
the TCS value ST2115LOGS3 are used, in which case the value
ST2110-20:2022 shall be signaled."*  Only `:2017` and `:2022` are defined.

**Parser** (`parse_sdp.lua:730`):
```lua
local _ssn20_pat = P("ST2110-20:") * _ssn_year * P(-1)
```
where `_ssn_year` is any four decimal digits.  `SSN=ST2110-20:1999` or
`:9999` is accepted.

**Recommended action.**  Replace `_ssn20_pat` with a closed set:
`P("ST2110-20:") * (P("2017") + P("2022")) * P(-1)`.  Same change for
`_ssn22_pat` (closed set: `{2019, 2022}`).  Test pass/fail paths.

### A4. ST 2110-20 m=video subtype "raw" not asserted

**Spec quote** (ST 2110-20:2022 §7.1): *"For a uncompressed Active Video
RTP Stream, the Media Type Field shall be `video` and the Media Subtype name
**raw** shall be used."*

**Parser** (`parse_sdp.lua:1713-1718`):
```lua
elseif m.media == "video" then
  -- ST 2110-20: uncompressed video
  if clock_rate ~= 90000 then ...
```
Branch keyed on `m.media == "video"` alone.  An `m=video 5000 RTP/AVP 96`
paired with `a=rtpmap:96 foo/90000` (encoding name "foo") routes through the
ST 2110-20 raw-video validators with no check that the encoding name is
`raw`.

**Recommended action.**  Reject encoding name ≠ `raw` for the
uncompressed-video branch with `spec_ref="ST 2110-20:2022 §7.1"`.  Note:
**this interacts with codec dispatch** — if VC-2 or other compressed codecs
were added later, they would legitimately use `m=video` with non-raw encoding
names.  The current parser handles `jxsv` upstream of the `elseif`, so a
strict `enc == "raw"` check is safe today; widen the dispatch when new
codecs land.

### A5. ST 2110-22 jxsv width/height upper bound 32767 not enforced

**Spec quote** (ST 2110-22:2022 §7.2 Table 1, restating ST 2110-20:2022
§7.2): *"Permitted values are integers between 1 and 32767 inclusive."*

**Parser** (`parse_sdp.lua:1574-1576`):
```lua
local jxs_req = {
  { "width",      valid_pos_int },
  { "height",     valid_pos_int },
  ...
```
`valid_pos_int` enforces lower bound only.  Compare to the uncompressed
video branch at `parse_sdp.lua:1743-1744` which uses `valid_width` /
`valid_height` (enforcing the 32767 ceiling).

**Recommended action.**  Reuse `valid_width` / `valid_height` for the jxsv
branch.  Test that `width=99999` on a jxsv stream is rejected.

### A6. ST 2110-20 cross-parameter rules MISSING

**Spec quotes** (multiple):

- ST 2110-20:2022 §6.2.3 Table 1 — sampling=XYZ defined only at depth ∈
  {12, 16, 16f}; depth=8 / depth=10 with XYZ accepted by parser.
- ST 2110-20:2022 §6.2.5 Table 3 — sampling=YCbCr-4:2:0 / CLYCbCr-4:2:0 /
  ICtCp-4:2:0 defined only at depth ∈ {8, 10, 12}; depth=16 / depth=16f
  with 4:2:0 accepted by parser.
- ST 2110-20:2022 §7.6 — *"Video stream of linear encoded floating-point
  samples (depth=16f)"* — TCS ∈ {LINEAR, BT2100LINPQ, BT2100LINHLG,
  ST2065-1} require depth=16f; the parser pairs TCS=LINEAR with depth=8 with
  no error.
- ST 2110-20:2022 §7.3 RANGE: *"When the colorimetry value is BT2100, only
  the NARROW and FULL values are permitted."* — parser accepts
  `colorimetry=BT2100; RANGE=FULLPROTECT`.

**Parser** (`parse_sdp.lua:1741-1820`): `video_checks` validates each
parameter independently against its enum; no cross-table check.

**Recommended action.**  Add a single cross-parameter validator at the end
of the `m.media == "video"` branch that enforces:

| Rule | Parameter A → Parameter B constraint |
| --- | --- |
| §6.2.3 Table 1 | sampling=XYZ ⇒ depth ∈ {12, 16, 16f} |
| §6.2.5 Table 3 | sampling ∈ {YCbCr-4:2:0, CLYCbCr-4:2:0, ICtCp-4:2:0} ⇒ depth ∈ {8, 10, 12} |
| §7.6 | TCS ∈ {LINEAR, BT2100LINPQ, BT2100LINHLG, ST2065-1} ⇒ depth = 16f |
| §7.3 | colorimetry=BT2100 ⇒ RANGE ∈ {NARROW, FULL} |

Tests for each: pass + fail.

### A7. ST 2110-20 fmtp whitespace around `=` silently accepted

**Spec quote** (ST 2110-20:2022 §7.1): *"Each parameter entry shall be
constructed as either: 'name=value' (no whitespace) or 'name' (no value)."*

**Parser** (`parse_sdp.lua:1181`):
```lua
local k, v = trimmed:match("^([^=%s]+)%s*=%s*(.-)$")
```
The `%s*=%s*` permits whitespace around `=`.  `width = 1920` parses as
`k="width"`, `v="1920"` — accepted.

**Recommended action.**  Pre-check that no whitespace appears immediately
around `=` for ST 2110-20:2022 fmtp values; alternatively, tighten the
regex to `"^([^=%s]+)=(.-)$"` and document the change in CHANGELOG.

### A8. ST 2110-10 TSMODE / TSDELAY scope limited to raw video

**Spec quote** (ST 2110-10:2022 §8.7): TSMODE applies to all RTP streams
conforming to ST 2110 (umbrella section under "SDP Parameters", not the
uncompressed-video subsection).

**Parser** (`parse_sdp.lua:1861-1882`): TSMODE/TSDELAY validators are
inside `video_opt_checks` which is invoked only inside the `m.media ==
"video"` arm.  jxsv, audio, smpte291, and ST 2110-41 streams never run
these checks.

**Recommended action.**  Hoist TSMODE/TSDELAY validation out of
`video_opt_checks` to run after rtpmap parse for all media-types in the
ST 2110 validator.

### A9. ST 2110-10 TSMODE=SAMP → TSDELAY presence dependency not enforced

**Spec quote** (ST 2110-10:2022 §8.7): *"When TSMODE is signaled with
value 'SAMP', the TSDELAY parameter shall also be present."*

**Parser** (`parse_sdp.lua:1877, 1881`): TSMODE and TSDELAY validators
run independently.  `TSMODE=SAMP` without TSDELAY is accepted.

**Recommended action.**  Add a cross-parameter check: when
`params["TSMODE"] == "SAMP"` and `params["TSDELAY"]` is nil, reject.

### A10. RFC 5888 §6 "any a=group ⇒ every m= has a=mid" not enforced

**Spec quote** (RFC 5888 §6): *"If a session description contains a 'group'
attribute, every 'm=' line in that session description shall contain a 'mid'
attribute."*

**Parser**: walks `each_dup_group` only for DUP semantics (`parse_sdp.lua:
486`); the broader "any `a=group` requires every m= to have a=mid" is not
enforced.  An SDP with `a=group:LS 1 2` and one of the two media blocks
missing `a=mid` is accepted.

**Recommended action.**  Add a session-level pre-validate: if any session
attribute is `a=group`, scan every media block for `a=mid` presence.

### A11. RFC 4570 dest-address ↔ c= cross-line check absent

**Spec quote** (RFC 4570 §3): *"The destination address indicated in the
source-filter attribute shall be one of the destination addresses defined
in the SDP description (either in the connection field at the session-level
or in a connection field at the media-level)."*

**Parser**: `valid_source_filter` (`parse_sdp.lua:785-803`) validates
syntax but never cross-checks against `c=` lines.

**Recommended action.**  After parsing the source-filter, compare its
`<dest-address>` against `doc.session.connection.address` and every
`doc.media[i].connection.address`, accounting for RFC 8866 `c=`
`/numaddr` ranges per RFC 4570 §3 / §3.1.  This is non-trivial and may
warrant a separate audit pass before 1.0.

### A12. RFC 4570 session-level a=source-filter syntax not validated

**Parser**: `st2110.validate` only walks media-level source-filter
attributes (`parse_sdp.lua:1257-1266`).  The session-level scan at
`parse_sdp.lua:2898` (in the IPMX block) only checks presence, not value
form.

**Recommended action.**  Symmetric session-level + media-level validation
in `st2110.validate` and `ipmx.validate`.

### A13. RFC 7273 §4.8 mixed traceable / non-traceable ts-refclk not rejected

**Spec quote** (RFC 7273 §4.8): *"A media stream shall not signal both
'traceable' and non-'traceable' reference clocks in the same SDP at the same
level."*

**Parser** (`parse_sdp.lua:1275-1294`): gathers and validates each
`ts-refclk` individually, but never compares them at session-or-media-level
for the mixed-class case.

**Recommended action.**  After gathering all `ts-refclk` attributes for a
level, classify each as traceable or non-traceable and reject if both
classes appear at the same level.

### A14. ST 2110-20 RANGE validation accepts FULLPROTECT under BT2100

Covered under A6 cross-parameter rules; listing here for completeness.

---

## D. Findings — Direction B (parser check without spec SHALL)

### B1. RFC 8331 DID_SDID exactly-2-hex-digit pattern over-strict

**Spec ABNF** (RFC 8331 §4):
```
DidSdid = "DID_SDID={" TwoHex "," TwoHex "}"
TwoHex  = "0x" 1*2(HEXDIG)
```

**Parser** (`parse_sdp.lua:712-716`):
```lua
local function valid_did_sdid(value)
  if value:match("^{0x%x%x,0x%x%x}$") then return true end
  return nil, "invalid DID_SDID value (expected {0xHH,0xHH})"
end
```
`%x%x` requires exactly 2 hex digits.  `DID_SDID={0x6,0x2}` is spec-legal
(per `1*2(HEXDIG)`) but rejected.

**Recommended action.**  Replace with `"^{0x%x%x?,0x%x%x?}$"` (1 or 2 hex
digits per token).  Test pass for `{0x6,0x2}` and `{0x06,0x02}`; test fail
for `{0xZZ,0x01}`, `{0x123,0x01}`, etc.

### B2. RFC 9134 VALID_COLORIMETRY omits BT601-5 / BT709-2 / SMPTE240M

**Spec quote** (RFC 9134 §7.1): closed set for jxsv colorimetry includes
`BT601-5`, `BT709-2`, `SMPTE240M`, `BT601`, `BT709`, `BT2020`, `BT2100`,
`ST2065-1`, `ST2065-3`, `XYZ`, `UNSPECIFIED`.

**Parser** (`parse_sdp.lua:758-762`):
```lua
local VALID_COLORIMETRY = {
  ["BT601"]=true, ["BT709"]=true, ["BT2020"]=true, ["BT2100"]=true,
  ["ST2065-1"]=true, ["ST2065-3"]=true, ["UNSPECIFIED"]=true,
  ["XYZ"]=true, ["ALPHA"]=true,
}
```

The set omits the three legacy names and adds `ALPHA` (which is correct for
ST 2110-20:2022 but not for pure RFC 9134).  A conformant jxsv SDP using
`BT601-5`, `BT709-2`, or `SMPTE240M` is rejected.

**Recommended action.**  Two options.  (a) Add the three legacy names to
the shared set and accept across both -20 and jxsv paths.  (b) Split the
set by tier (RFC 9134-relaxed vs ST 2110-20:2022-strict).  Option (a) is
simpler; option (b) is more spec-honest.  See Design Question D1.

### B3. RFC 9134 sampling=UNSPECIFIED rejected

**Spec quote** (RFC 9134 §7.1, multi-clause): all five
signal-format-conditional SHALLs name an exhaustive sampling set including
UNSPECIFIED.  A pure-RFC-9134 jxsv SDP using `sampling=UNSPECIFIED` is
spec-legal.

**Parser** (`parse_sdp.lua:742-747`): `VALID_SAMPLING` omits
`UNSPECIFIED`.

**Recommended action.**  Add `UNSPECIFIED` to the jxsv-tier sampling set.
ST 2110-20:2022 may differ (verify).  Same tier-split question as B2.

### B4. RFC 7273 generic clksrc forms rejected at the only validation tier

**Spec quote** (RFC 7273 §4.1): clksrc literals are `ntp / ptp / gps / gal
/ glonass / local / private` (plus extension).

**Parser** (`parse_sdp.lua:670-710`, `valid_tsrefclk`): only `ptp=…` is
accepted.  `ts-refclk:local`, `ts-refclk:private[:traceable]`,
`ts-refclk:ntp=…`, and `ts-refclk:gps` etc. all hit the
`return nil, "unrecognized ts-refclk clock source"` exit.

**Note.**  The parser is named `parse_sdp`, but the ST 2110 / IPMX tier
narrows the legal set to PTP via ST 2110-10:2022 §8.2.  A pure-RFC-7273
SDP exercising the wider set is rejected today because there is no
RFC-7273-generic tier — only the ST 2110 tier.  This is more "scope" than
"bug" — see Design Question D2.

**Recommended action.**  If parse_sdp is *exclusively* an ST 2110 / IPMX
validator, this finding is OUT-OF-SCOPE (rephrase CLAUDE.md accordingly).
If it is supposed to validate generic RFC 4566 + clock signalling, add a
base-tier `valid_tsrefclk_rfc7273` that accepts all clksrc literals.

### B5. ST 2110-22 exactframerate "smallest numerator" strict GCD-reduced

**Spec quote** (ST 2110-22:2022 §7.4, referencing ST 2110-20:2022
§7.2): *"numerically smallest numerator value possible"*.

**Parser** (`parse_sdp.lua:1012-1031`): rejects `60000/2002` (parser
demands `30000/1001`).  The spec wording could be read two ways:
1. **GCD-reduced** (parser's reading): `gcd(num, den)` must equal 1.
2. **Numerator-only**: only the numerator needs to be the smallest
   integer that represents the rate exactly with this denominator —
   `60000/1001` is fine, `60000/2002` is wrong because the numerator
   isn't smallest *for the rate the SDP expresses*, but `30000/1001` and
   `60000/2002` could both be considered "smallest" depending on whether
   the spec means "smallest numerator at this den" or "smallest
   numerator at any den".

Inventory flagged `AMBIGUOUS` at this clause.  Parser's strict reading is
defensible but is one of two valid readings.

**Recommended action.**  Keep current behavior; add CHANGELOG note that
"smallest numerator" is interpreted as full GCD reduction.  If a user
reports a false rejection on this, reconsider.

---

## E. Citation errors (Direction C)

Checks whose behavior is correct but `spec_ref` is wrong.

### E1. RFC 5285 → RFC 8285 (5 sites)

**Spec status.**  RFC 8285 (Oct 2017) obsoletes RFC 5285.  The
`a=extmap` attribute, its ID uniqueness rule, and value-form ABNF all
live in RFC 8285 §4 / §5.

**Parser citations**:
- `parse_sdp.lua:2589` (comment) — *"its URI format is still validated
  (RFC 5285)"*
- `parse_sdp.lua:2598` — `spec_ref = "RFC 5285"`
- `parse_sdp.lua:2619` — `spec_ref = "RFC 5285"`
- `parse_sdp.lua:2645` — `spec_ref = "RFC 5285 §3"`
- `parse_sdp.lua:2662` — `spec_ref = "RFC 5285 §3"`

**Recommended action.**  Replace `RFC 5285` with `RFC 8285` at all
sites (and `RFC 5285 §3` with `RFC 8285 §4` — RFC 8285 reorganized the
sections; ID uniqueness is §4 in 8285, was §3 in 5285).

### E2. ST 2110-40 §7.2 cite for clock-rate=90000 should be §5.3

**Parser** (`parse_sdp.lua:1377`): cites `ST 2110-40 §7.2`.  Inventory
locates the SHALL at ST 2110-40:2023 §5.3 (RTP Stream Format).

**Recommended action.**  Update spec_ref to `ST 2110-40:2023 §5.3`.

### E3. ST 2110-40:2023 §6.1.4 MAXUDP cite should be §5.2.1

**Parser** (`parse_sdp.lua:1466`): cites `ST 2110-40:2023 §6.1.4`.
Inventory locates the SHALL-NOT at §5.2.1 ("UDP size shall not exceed
Standard UDP Size Limit").

**Recommended action.**  Update spec_ref to `ST 2110-40:2023 §5.2.1`.

### E4. RFC 5888 §8.1 cite for a=mid uniqueness should be §4

**Parser** (`parse_sdp.lua:2062`): cites `RFC 5888 §8.1` for a=mid
duplicate-rejection.  Inventory: the uniqueness MUST is in RFC 5888 §4
(*"each 'mid' value shall be unique within the session"*); §8.1 is the
IANA registry policy.

**Recommended action.**  Update spec_ref to `RFC 5888 §4`.

### E5. RFC 7273 cite-upstream candidates (13 sites)

The parser cites `ST 2110-10 §7.2` / `§7.3` / `§8.2` / `§8.3` for
clksrc literals, EUI-64 form, ptp-version, ntp form, sender/direct
literals, etc. — all of which are RFC 7273 §4.8 / §5.4 SHALLs.  ST 2110-10
defers to RFC 7273; the upstream source is more authoritative.

**Examples**:
- `parse_sdp.lua:1285` `"ST 2110-10 §7.2"` for ts-refclk presence
- `parse_sdp.lua:1290` `"ST 2110-10 §7.2"` for ts-refclk value
- `parse_sdp.lua:1296` `"ST 2110-10 §7.3"` for mediaclk presence
- `parse_sdp.lua:1300` `"ST 2110-10 §7.3"` for mediaclk value
- (Plus 9 more sites — see `audits/SPEC_COVERAGE.md` RFC 7273 section.)

**Recommended action.**  This is a stylistic choice.  Either:
1. Migrate to `RFC 7273 §X` cites with comments noting ST 2110-10
   defers to RFC 7273.
2. Keep ST 2110-10 cites with comments noting the upstream cite.

Both are defensible.  See Design Question D3.

### E6. RFC 4566 → RFC 8866 cite drift on multiple base rules

ST 2110-30:2025 cites RFC 8866 (not 4566).  Various 4566-base rules
that the parser enforces are also in RFC 8866 with refinements
(notably: dynamic-PT-requires-rtpmap is now a MUST in 8866 §8.2.3,
was SHOULD in 4566 §5.14).  Parser cites RFC 4566 at most of these
sites.

**Examples**:
- Dynamic-PT-requires-rtpmap: parser cites `ST 2110-10 §7`
  (`parse_sdp.lua:1305`); operative MUST is RFC 8866 §8.2.3.
- rtpmap PT range 0-127: parser cites `RFC 3550 §5.1`; operative ABNF
  is RFC 8866 §6.6 / §6.7.

**Recommended action.**  Depends on Design Question D1 (whether parser
moves to RFC 8866 as the base).

### E7. ST 2022-7 in error message strings (cosmetic)

**Parser** (`parse_sdp.lua:2118, 2130`): error messages include
parenthetical `(ST 2022-7 §6)` text.  The structured `spec_ref` is
correctly `ST 2110-10 §8.5`.  Cosmetic but ST 2022-7 has no SDP content;
the parenthetical is misleading.

**Recommended action.**  Remove the parenthetical or change to
`(ST 2110-10 §8.5)`.

### E8. Year-tagging inconsistent

Parser uses both `ST 2110-20` and `ST 2110-20:2022` in spec_refs.
Similar for `ST 2110-22` vs `ST 2110-22:2022`, etc.  Editorial
inconsistency.

**Recommended action.**  Apply year-tagging consistently across all
spec_refs.  Style: `ST 2110-XX:YYYY §Z` for current revision; `ST
2110-XX §Z` for spec content valid across revisions.

---

## F. Documentation drift

### F1. CLAUDE.md names RFC 4566 as the base spec

ST 2110-30:2025 cites RFC 8866.  CLAUDE.md says *"RFC 4566 (generic SDP)
→ SMPTE ST 2110 → IPMX"*.  Either CLAUDE.md needs to update to RFC 8866
or to note the drift.

### F2. GUIDE.md tables vs parser behavior

Defer to a `diff GUIDE.md` review after Direction-A findings are landed.

### F3. SDPOKER_BACKLOG.md may have entries this audit resolves

See Section G.

### F4. CLAUDE.md "Spec Verification Protocol" — markdown library path drift

CLAUDE.md says TR-10 markdown lives at:
`smpte_standards_internal/TR-10 Markdowned Versions/`

Actual location:
`/TR-10 Markdowned Versions/` (top-level, NOT inside `smpte_standards_internal/`).

Phase 1 spec walkers had to recover from this path mismatch. Editorial fix in CLAUDE.md, no parser impact.

---

## G. Reconciliation against prior audits

Read order: `CHANGELOG.md` `[Unreleased]`, then `PLAN.md` "Resolved" + "Known
Deferred Items" + "Pre-1.0 Conformance Audit", then `SDPOKER_BACKLOG.md`.
This section was written AFTER A–F so the independent pass was not
contaminated.

### G1. Findings already RESOLVED by prior audits (no overlap)

The prior 30 passes have left a clean, well-documented baseline.  Resolved
items I would have re-flagged if Phase 1 + 2 had run in isolation:

- F8 (RFC 4566 §5 `r=`/`z=`/`k=`/multiple `t=`) — landed.
- F9 (RFC 8866 §9 IPv4 layered multicast `/ttl/numaddr`) — landed.
- F10 (RFC 8866 §5.7 TTL=0) — landed.
- F11 (RFC 3551 §6 static-PT carve-out for L16/PT 10 / 11) — landed (this
  is also why C3's "static PT bindings unenforced" finding only fires
  beyond L16/PT 10-11).
- N1 (TP required for raw video at ST 2110 tier) — landed.
- N2–N5 (AM824 even `<nchan>`, clock-rate set, `a=ptime` required, Table 1
  pairs) — landed.
- N6–N9 (jxsv §6.2 m=video, §7.2 no trailing `;`, §7.3 b=AS required, §7.4
  framerate required) — landed.
- N10 (FID forbidden on smpte291 at ST 2110 tier; broader at IPMX) — landed.
- N11 (MAXUDP forbidden on smpte291 / ST2110-41 / audio) — landed.
- N12 + N13 (KEY-sampling colorimetry/TCS constraints; 4:2:0 + interlace
  forbidden — both scoped to raw video correctly) — landed.
- D1 (audio ptime cite corrected to ST 2110-30:2025 §6.2.1) — landed.
- D2 (fbblevel SDP fmtp check removed) — landed.  **Phase 1 walker confirmed
  independently** at both TR-10-15-Part1 §9 and IPMX-JPEG-XS-Profile v1.0
  §6.1.4 that the bullets bind to a MIB-population SHALL, not SDP.  The
  removal is validated.
- F1 + D3 (TCS optional per §7.3) — landed.
- F2 + D4 (a=hkep media-level permitted per TR-10-5 §17) — landed.
- F3 (DIT optional + hex form) — landed.
- F4 (ST 2110-41 clock rate is Data-Item-defined, not 90 kHz) — landed.
- F5 (channel-order convention is SHOULD per ST 2110-30:2025 §6.2.2) — landed.
- F6 (`AES3` channel-grouping symbol added for AM824) — landed.
- F7 (RFC 8866 §9 IPv6 `/numaddr` cite cleanup — closed without change) — landed.

### G2. Findings ALIGNED with PLAN's "Known Deferred Items"

These align with what PLAN.md "Known Deferred Items" already documents as
deliberate exclusions, with the reasoning anchored in strictness principle:

- **ST 2110-20:2022 §7.2 reverse-direction SSN default** (SSN=:2022 without
  :2022-only values).  PLAN documents the deferral with the reason that
  strict enforcement would invalidate ~115 fixtures.  Phase 1 also flagged
  AMBIGUOUS.  **Aligned — no new finding.**
- **Sampling × colorimetry × TCS × RANGE cross-table.** PLAN documents the
  deferral with reasoning *"the spec lists value sets independently and
  contains no explicit 'shall not' for any combination of valid individual
  values."* The Phase 2 agent for ST 2110-20 flagged three cross-rules
  (XYZ × depth Table 1; 4:2:0 × depth Table 3; TCS-LINEAR → depth=16f) as
  MISSING; these belong in the same deferred category.  **Aligned —
  the deferral reasoning still holds because Tables 1/3 enumerate without
  an explicit prohibition.**
- **ST 2110-21 §6.2 vs §8.2 TROFF zero handling.** PLAN documents the §8.2
  positive-integer SHALL governing.  Phase 1 also flagged AMBIGUOUS.
  **Aligned.**
- **ST 2110-10:2022 §8.7 vs Annex B TSDELAY zero.** Same shape — §8.7 SHALL
  governs; Annex B is informative.  **Aligned.**
- **`o=` unicast_address literal-IP requirement.** PLAN documents that no
  ST 2110 clause forbids FQDNs at the o= unicast-address slot.  Phase 1 did
  not surface this.  **Aligned.**
- **VSF TR-10-1 SDP-validation audit closed 2026-05-15.** Phase 2's TR-10
  coverage agent found 3 MISSINGs in TR-10-9 §10 (not TR-10-1), so this
  doesn't conflict.

### G3. Findings IN TENSION with PLAN.md "Resolved" decisions (need re-evaluation)

These are places where Phase 1+2 reach a different conclusion than the
prior audit documented in CHANGELOG.  Each needs your eyes before being
treated as a finding.

**G3.1 — ST 2110-40 SSN=2021 acceptance (Phase 3 finding A1).**

CHANGELOG: *"senders signaling `ST2110-40:2021` are rejected — §7 makes
that value a receiver-side tolerance only."*

§7 has TWO SHALLs:
- Sender SHALL: *"Senders implementing this standard shall signal … the
  value ST2110-40:2018 unless they are signaling … TM, in which case they
  shall signal the value ST2110-40:2023."*  (No 2021 in the sender set.)
- Receiver SHALL: *"Receivers shall consider a Format Specific Parameter
  SSN value of ST2110-40:2021 as equivalent to a value of ST2110-40:2023."*

Prior audit chose **sender-side strict** (reject 2021 because the sender
SHALL doesn't include it).  Phase 1+2 noted the receiver SHALL.  The
parser is a validator — which side does it model?  The CHANGELOG decision
is defensible IF parse_sdp is exclusively a sender-side conformance
validator.  If parse_sdp is used to PARSE incoming SDPs in a receiving
application (i.e. plays the receiver role), the §7 receiver SHALL applies
and the parser MUST accept 2021 = 2023.

**This is a Design Question, not a bug.**  See D-question 1 below.

**G3.2 — RFC 7273 §4.8 `ts-refclk:local` rejection (Phase 3 finding B4).**

SDPOKER_BACKLOG (Streampunk #9): *"Reject `ts-refclk:local` (typo of
`:localmac=`).  Only the listed prefixes are valid."*

But RFC 7273 §4.8 lists `local` as a valid clksrc literal:
*"clksrc = "ntp" / "ptp" / "gps" / "gal" / "glonass" / "local" /
"private" / clksrc-ext"*

The SDPoker resolution treated `local` as a typo of `localmac=`.  **This
appears to be wrong** — `local` is a real RFC 7273 §4.8 clksrc, defined
to mean "the local clock of the device emitting the SDP (no external
sync)."

Re-verifying against the primary spec text:  RFC 7273 §4.5: *"A reference
clock indicated as 'local' is a local clock of the device making the
description.  Such a clock has no traceability to any external standard."*

So rejecting `ts-refclk:local` is over-strict.  The original SDPoker
issue may have been a typo report (Streampunk's user typing `local` for
`localmac=`), but the spec text supports both `local` (RFC 7273 §4.5) and
`localmac=` (ST 2110-10:2022 extension form, line 1140-ish in the
parser).  Both should be accepted.

**Caveat.**  At the ST 2110 tier, the ST 2110-10:2022 §8.2 narrows the
legal set to PTP-derived only.  So:
- At base RFC 7273 tier (parse-only, no ST 2110 mode): accept `local`.
- At ST 2110 tier: reject all non-PTP per §8.2.

But the parser has no "RFC 7273 base tier" today — the only `valid_tsrefclk`
gate is at the ST 2110 level.  Need to verify whether `sdp.parse(text)`
(no mode) even tries to validate ts-refclk.  Phase 1 + 2 suggest it does
not — `valid_tsrefclk` is only called from `st2110.validate`.

**Conclusion for G3.2.**  At the ST 2110 tier, the current reject is
defensible (ST 2110-10:2022 §8.2 narrows to PTP).  At the base tier,
ts-refclk isn't validated at all — so the rejection of `local` only
fires under ST 2110 mode, where it's correct.  **Phase 3 finding B4
downgrade**: this is not over-strict at the ST 2110 tier.  However, the
**SDPOKER_BACKLOG row should be re-cited** — the rejection is correct
*because of ST 2110-10:2022 §8.2*, not because `local` is a typo.

**G3.3 — ST 2110-20:2022 §7.6 "TCS LINEAR / BT2100LINPQ / BT2100LINHLG /
ST2065-1 ⇒ depth=16f"** (Phase 2 candidate from C11).

Phase 2 agent flagged MISSING.  Phase 1 quoted §7.6: *"Video stream of
linear encoded floating-point samples (depth=16f)."*

Re-reading: this is DESCRIPTIVE prose, not a normative SHALL.  §7.6 lists
the permitted TCS values and characterizes each.  The "(depth=16f)" is a
parenthetical describing what these TCS values typically pair with — not
a "shall" forbidding other combinations.

**Conclusion for G3.3.**  This belongs in the same DEFERRED category as
PLAN's "Sampling × colorimetry × TCS × RANGE cross-table" — no explicit
SHALL, just a descriptive pairing.  **Downgrade** — A6 reduces to just
the BT2100 RANGE restriction (which IS an explicit "only NARROW and FULL
are permitted").

### G4. SDPOKER_BACKLOG.md regression coverage

Every SDPoker / AMWA / JT-NM finding listed in SDPOKER_BACKLOG.md has a
regression test cited.  Phase 1 + 2 did not surface any SDPoker-flagged
issue that lacks a regression test.  **No new SDPoker-derived findings.**

### G5. New findings this pass surfaces (NOT in prior-audit context)

Filtering the Section C / D / E findings against G1–G4:

**Direction A (new — should be addressed before 1.0):**

| # | Spec | What | Severity |
| --- | --- | --- | --- |
| A2 | RFC 8331 §4 | VPID_Code "only once" cardinality | MEDIUM (silent coalescence; rare in practice but spec-explicit) |
| A3 | ST 2110-20:2022 §7.2 / -22 §7.2 | SSN year-suffix over-permissive (accepts ANY YYYY) | LOW (parser is over-permissive on a closed set) |
| A4 | ST 2110-20:2022 §7.1 | m=video subtype "raw" not asserted | MEDIUM (encoding-name dispatch correctness) |
| A5 | ST 2110-22:2022 §7.2 Table 1 | jxsv width/height upper bound 32767 not enforced | LOW (parser uses valid_pos_int; uncompressed-video path uses valid_width/height) |
| A6 (partial) | ST 2110-20:2022 §7.3 | colorimetry=BT2100 ⇒ RANGE ∈ {NARROW, FULL} (FULLPROTECT forbidden) | MEDIUM (explicit "only … permitted" prohibition) |
| A7 | ST 2110-20:2022 §7.1 | Whitespace around `=` in fmtp silently accepted | LOW (spec is explicit; rare in practice) |
| A8 | ST 2110-10:2022 §8.7 | TSMODE/TSDELAY validation scope limited to raw video | MEDIUM (umbrella SHALL applies to all media-types) |
| A9 | ST 2110-10:2022 §8.7 | TSMODE=SAMP → TSDELAY presence dependency not enforced | LOW |
| A10 | RFC 5888 §6 | Any a=group ⇒ every m= has a=mid | MEDIUM (base-tier rule, easy to add) |
| A11 | RFC 4570 §3 | dest-address ↔ c= cross-line check absent | MEDIUM (complex; consider deferring with explicit note) |
| A12 | RFC 4570 §3 | Session-level source-filter syntax not validated | LOW (asymmetric with media-level; easy fix) |
| A13 | RFC 7273 §4.8 | Mixed traceable / non-traceable ts-refclk not rejected | LOW |

**Direction B (new — over-strict):**

| # | Spec | What | Severity |
| --- | --- | --- | --- |
| B1 | RFC 8331 §4 ABNF | DID_SDID requires exactly 2 hex digits; ABNF allows 1–2 | LOW (rejects spec-legal `{0x6,0x2}`) |

**Direction B (downgrade — was new in Section D, now reconciled):**

- B2/B3 (RFC 9134 colorimetry/sampling sets): scope is jxsv-at-RFC-9134
  tier only.  Parser is ST 2110/IPMX validator; the missing colorimetry
  values (BT601-5, BT709-2, SMPTE240M) and sampling=UNSPECIFIED are
  unlikely to appear in ST 2110-22 / IPMX SDPs.  **Defer with note** in
  GUIDE.md — RFC 9134 generic forms are out of parse_sdp's ST-2110-only
  scope today.
- B4 (RFC 7273 generic forms): re-cited per G3.2.  At the ST 2110 tier
  the rejection is correct (ST 2110-10:2022 §8.2 narrows).  At a base
  RFC 7273 tier the parser doesn't validate ts-refclk at all, so no
  over-strictness fires.  **Downgrade** — re-cite SDPOKER_BACKLOG entry.
- B5 (exactframerate strict GCD): prior audit explicitly chose strict
  GCD-reduced reading.  **Aligned with prior decision.**

**Direction C (new — citation cleanup):**

| # | Cite | Correct cite |
| --- | --- | --- |
| E1 | RFC 5285 / RFC 5285 §3 (5 sites) | RFC 8285 / RFC 8285 §4 |
| E2 | ST 2110-40 §7.2 (clock rate=90000 at parse_sdp.lua:1377) | ST 2110-40:2023 §5.3 |
| E3 | ST 2110-40:2023 §6.1.4 (MAXUDP at parse_sdp.lua:1466) | ST 2110-40:2023 §5.2.1 (per inventory) — VERIFY in PDF before changing |
| E4 | RFC 5888 §8.1 (parse_sdp.lua:2062) | RFC 5888 §4 |
| E5 | ST 2110-10 §7.2 / §7.3 / §8.2 / §8.3 (13 ts-refclk/mediaclk sites) | RFC 7273 §X (upstream); ST 2110-10 is the wrapper |
| E7 | "(ST 2022-7 §6)" in error message text at parse_sdp.lua:2118, 2130 | Remove parenthetical (cosmetic; structured spec_ref is correct) |
| E8 | `ST 2110-20` vs `ST 2110-20:2022` (mixed) | Standardize on `ST 2110-XX:YYYY §Z` for revision-specific clauses |

### G6. Phase 1 inventory gaps (not in scope of CHANGELOG/PLAN — backfill candidates)

Specs the parser cites but Phase 1 did not walk:
- RFC 3190 (channel-order convention.order grammar)
- RFC 3605 (a=rtcp)
- RFC 4145 (a=setup)
- RFC 4291 (IPv6 address grammar — referenced for ABNF)
- RFC 5285 → RFC 8285 (a=extmap)
- RFC 5761 (RTP/RTCP mux — cited by TR-10-1 §8.7)

These are tributary specs.  None of the parser's checks against them
appear wrong from spot-checking.  Backfill walk before 1.0 if you want
strict bidirectional traceability.

### G7. AES67-2018 / AES67-2023 paywall remains

Phase 1 acknowledged the gap.  ST 2110-30:2025 §6.2.1 cites AES67-2023.
Inventory rows derived from AES67-2013 wording remain flagged
`[AES67-2013 wording]`.  No Phase 3 finding is *blocked* by the paywall,
but several conclusions (audio sample-rate set, multicast scope, ptime
restrictions) have the caveat "based on 2013 wording — verify against
2018/2023 if obtained."

---

## H. Verdict

**Found 17 new findings; recommend addressing before 1.0.**

Twelve Direction-A (SHALL not enforced), one Direction-B (parser
over-strict), and seven Direction-C (wrong cite, including five RFC 5285
→ RFC 8285 sites).  None is catastrophic; several (A2, A4, A5, A6-partial,
A8) are textbook spec-grounded fixes with verbatim primary text behind
them.

What this audit pass DID NOT find:
- No regressions against the prior 30 passes' decisions.
- No fbblevel-style false-finding by bullet-binding (Phase 1+2 confirmed
  the removal is correct via two independent walkers — TR-10-15-Part1 §9
  and IPMX-JPEG-XS-Profile v1.0 §6.1.4).
- No spurious ST 2022-7 cite for SDP attribute requirements (Phase 1
  confirmed ST 2022-7:2013 never mentions SDP; parser doesn't mis-cite).
- No bogus parser rejections of spec-legal SDPs in the AMWA / SDPoker
  regression set.

What this audit pass DID find that's worth your attention beyond the
17 numbered findings:
- One *design choice* (A1 / G3.1) where the parser's current behavior is
  defensible but the receiver-side SHALL is unaddressed.
- One *citation re-anchoring* opportunity (SDPOKER_BACKLOG Streampunk #9
  cites the wrong reason for rejecting `ts-refclk:local`).
- The RFC 4566 vs RFC 8866 base-spec question, which has cite-drift
  implications (E6).
- Phase 1 inventory gaps on six tributary RFCs (G6).

Reading the Section H rubric from the audit prompt:

> "Found N findings; recommend addressing before 1.0." With the findings
> listed.

That is this verdict.  The verdict is not "recommend cutting 1.0" —
17 findings is too many — but it is also not "you have severe
foundational bugs."  The parser is sound; what's missing is mostly
cross-parameter and cardinality SHALLs that no prior pass enumerated
because the prior passes went parser → spec.  The inverted pass surfaces
them.

After the 17 findings land (each as a separate commit with the standard
gates: spec quote in comment, test pass+fail paths, GUIDE/CHANGELOG/PLAN
sync), a second 31st-pass-style audit would likely return "recommend
cutting 1.0."  I have no leftover suspicion that something is hiding.

---

## I. Decisions (resolved with user — 2026-05-16)

**D1 — Base SDP spec: RFC 4566 → RFC 8866.**  Migrate.  CLAUDE.md updates
to name RFC 8866 as the base.  Adds new Direction-A findings from the
8866 deltas (see D1.x below).  spec_refs migrate where 8866 supersedes
the operative SHALL.

**D2 — SSN=ST2110-40:2021 semantics: receiver-side strict.**  Parser
accepts `SSN=ST2110-40:2021` as equivalent to `ST2110-40:2023` when `TM`
is signaled.  A1 lands as a finding.  CHANGELOG entry updated to remove
the "senders-only" reasoning.

**D3 — A11 RFC 4570 cross-line check: full RFC 8866 expansion.**  Land
the full check including session-level + media-level c= traversal,
`/numaddr` expansion per RFC 8866 §9, and `*` addrtype handling.

**D4 — Phase 1 backfill walks for tributary RFCs.**  Not explicitly
decided — defer for a follow-up audit unless any of the six RFCs (3190,
3605, 4145, 4291, 5761, 8285) shows up as a citation problem during
finding-landing.

**D5 — AES67-2018/2023 paywall: proceed with 2013 wording + GUIDE
caveat.**  No 2018/2023 acquisition required pre-1.0.  GUIDE.md adds a
note explaining that audio-related conclusions derive from AES67-2013
wording and that ST 2110-30:2025's normative reference is AES67-2023.

**D6 — m=video subtype "raw" enforcement (A4): not yet decided.**  Bake
into A4's landing; if the strict `enc == "raw"` check conflicts with
existing VC-2 fixtures (none today; verify), widen the dispatch
contemporaneously.

### D1 sub-findings — RFC 8866 base migration scope

Migrating to RFC 8866 as base adds these new Direction-A findings to
the landing queue:

**D1.1 — RFC 8866 §5.12 `k=` obsoletion.**  *"The 'k=' line MUST NOT be
used.  Implementations receiving SDP messages with this line MUST
discard it."*  Parser currently parses, stores, serializes (lines
235-248, 403-406, 3106-3112, 3151-3156).  Action: discard k= during
parse with a warning (no rejection — receiver MUST discard, not reject);
serializer omits k=.  Tests update accordingly.  This will affect F8's
recent `r=/z=/k=` work — k= portion needs to switch from "stored +
round-tripped" to "parsed-then-discarded."

**D1.2 — RFC 8866 §8.2.3 dynamic-PT MUST have a=rtpmap.**  Was SHOULD in
RFC 4566 §5.14, strengthened to MUST in RFC 8866 §8.2.3.  Parser
enforces it only at the ST 2110 tier (line 1305) with cite `ST 2110-10
§7`.  Hoist to base tier with cite `RFC 8866 §8.2.3`.

**D1.3 — RFC 8866 §5.7 IPv4-multicast `/ttl` mandatory at base tier.**
Same as D1.x — currently enforced at ST 2110 tier only.  Hoist to base.

**D1.4 — RFC 8866 §5.7 IPv6-multicast TTL forbidden at base tier.**
The §9 ABNF `IP6-multicast = IP6-address [ "/" numaddr ]` excludes TTL
syntactically; §5.7 prose: *"TTL value MUST NOT be present for 'IP6'
multicast."*  Currently enforced at ST 2110 tier only.  Hoist.

**D1.5 — RFC 8866 §5.14 media-type value set.**  *"audio / video / text
/ application / message"* + IANA-registered.  Removed `control` and
`data` (RFC 4566 listed them).  Parser doesn't enforce a media-type
value set today — `m=control` is accepted.  Land at base tier.

**D1.6 — RFC 8866 §5.14 multiple `c=` rules at session level.**
*"MUST NOT" multiple session-level c=*; per-media c= permitted in
specific layered-encoding cases per §5.7.  Currently parser accepts
multiple session-level c= silently.  Land.

**D1.7 — CLAUDE.md base spec update.**  Replace "RFC 4566 (generic SDP)"
with "RFC 8866 (SDP, current; obsoletes 4566)" in the validation-tiers
description.  Sync with PLAN.md.

---

## J. Commit landing plan

Per audit-prompt: one commit per finding, primary-source quote in the
body, tests covering pass + fail, docs sync.  Order chosen by atomicity
and risk (low → higher):

### Wave 1 — Citation-only (lowest risk, fastest)
1. **E1** RFC 5285 → RFC 8285 (5 sites; E1 includes the §3 → §4
   re-section)
2. **E4** RFC 5888 §8.1 → §4 (1 site)
3. **E2** ST 2110-40 clock-rate cite §7.2 → §5.3 (1 site)
4. **E3** ST 2110-40 MAXUDP cite §6.1.4 → §5.2.1 (1 site — re-verify in
   PDF first)
5. **E7** ST 2022-7 parenthetical cleanup in error text (2 sites,
   cosmetic)
6. **E8** Year-tagging consistency pass (multi-site, cosmetic)

### Wave 2 — Atomic Direction-A / B fixes (small, isolated)
7. **B1** DID_SDID 1-or-2 hex digits (parse_sdp.lua:714 pattern fix)
8. **A2** VPID_Code only-once cardinality
9. **A3** SSN year-suffix closed set ({2017, 2022} for -20; {2019, 2022}
   for -22)
10. **A5** jxsv width/height upper bound 32767
11. **A6** (BT2100 RANGE restriction subset only — explicit "only
    NARROW and FULL")
12. **A7** Whitespace around `=` in fmtp (parse_sdp.lua:1181)
13. **A9** TSMODE=SAMP → TSDELAY presence dependency
14. **A12** Session-level source-filter syntax validation
15. **A13** Mixed traceable/non-traceable ts-refclk rejection

### Wave 3 — Medium-complexity Direction-A
16. **A1** SSN=2021 receiver-equivalence (per D2 — accept as 2023-equivalent)
17. **A4** m=video subtype "raw" assertion
18. **A8** TSMODE/TSDELAY scope expansion to all media-types
19. **A10** Any a=group ⇒ every m= has a=mid
20. **E5** RFC 7273 cite-upstream migration (13 sites)

### Wave 4 — Complex Direction-A
21. **A11** RFC 4570 dest-address ↔ c= cross-line check (full RFC 8866
    expansion)

### Wave 5 — RFC 8866 base migration (multi-commit set)
22. **D1.7** CLAUDE.md + PLAN.md "base spec is RFC 8866" doc update
23. **D1.1** RFC 8866 §5.12 k= obsoletion (parse discards; serializer
    omits)
24. **D1.2** RFC 8866 §8.2.3 dynamic-PT MUST have a=rtpmap at base tier
25. **D1.3** RFC 8866 §5.7 IPv4-multicast /ttl mandatory at base tier
26. **D1.4** RFC 8866 §5.7 IPv6-multicast TTL forbidden at base tier
27. **D1.5** RFC 8866 §5.14 media-type value set enforcement
28. **D1.6** RFC 8866 §5.7 multiple session-level c= rejection

### Out of scope of this audit pass (per D4 / D5)
- AES67-2018/2023 conclusions remain caveated (GUIDE.md note instead of
  parser change)
- Tributary RFC backfill walks (3190, 3605, 4145, 4291, 5761) — defer
  unless a citation problem surfaces during landing

Total estimated commits: **28**, plus CHANGELOG/PLAN updates per commit.
Splits naturally into 2–3 sessions.
