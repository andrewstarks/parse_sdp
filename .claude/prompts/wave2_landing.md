# Prompt — Wave 2 Landing (parse_sdp audit pass #31)

You're picking up `parse_sdp` audit pass #31 at the start of Wave 2.
Phase 1+2+3 are complete; Wave 1 (six citation-cleanup commits plus one
conformance-manifest follow-up) landed. Working tree is clean, both
test suites pass (777 hermetic + 10 conformance).

Your job: land **Wave 2 — 9 atomic Direction-A/B parser fixes**, one
commit per finding. Each changes parser behavior (not just citations),
so each needs new test coverage of pass + fail paths.

---

## Read first

1. `audits/PHASE3_FINDINGS.md` — full audit findings.
   - **Section J** is the landing plan (you're starting Wave 2).
   - **Sections C, D** have per-finding spec quotes + parser refs.
   - **Section I** records four user-made design decisions (D1–D5).
   - **Section G** reconciles against prior 30 audit passes.
2. `CLAUDE.md` — Validation Strictness Principle + Spec Verification
   Protocol. The audit constitution. Treat as binding.
3. `audits/SPEC_INVENTORY.md` (684 KB) — Phase 1 inventory if you need
   to verify a quote.

**Line numbers in `PHASE3_FINDINGS.md` may be 1–6 lines stale** because
Wave 1 commits expanded a few comment blocks. Grep for function or
attribute names; don't trust absolute line numbers.

---

## Wave 2 findings (one commit each, in this order)

Severity / risk goes low → higher. Each entry: spec quote, grep target,
proposed change, test cases.

### Commit 1 — **B1**: DID_SDID 2-hex over-strict

**Spec** (RFC 8331 §4 ABNF):
```
DidSdid = "DID_SDID={" TwoHex "," TwoHex "}"
TwoHex  = "0x" 1*2(HEXDIG)
```
`1*2(HEXDIG)` is 1 OR 2 hex digits.

**Parser**: `local function valid_did_sdid` (grep). Pattern is
`"^{0x%x%x,0x%x%x}$"` — requires exactly 2 hex digits per token.

**Change**: pattern → `"^{0x%x%x?,0x%x%x?}$"`. Reject anything beyond
2 hex digits (the `%x?` is optional second digit).

**Tests** (in `spec/st2110_spec.lua`, smpte291 / DID_SDID section):
- Pass: `DID_SDID={0x6,0x2}`, `DID_SDID={0x06,0x02}`, `DID_SDID={0x6,0x02}`.
- Fail: `DID_SDID={0xZZ,0x01}` (non-hex), `DID_SDID={0x123,0x01}` (3 digits),
  `DID_SDID={,0x01}` (empty token).

### Commit 2 — **A2**: VPID_Code "appears only once" not enforced

**Spec** (RFC 8331 §4): *"VPID_Code shall appear only once and a single
integer value shall be expressed."*

**Parser**: `local function fmtp_params` (grep). Line `params[k] = v`
silently overwrites; duplicate `VPID_Code=N1; VPID_Code=N2` keeps only
the last. The VPID_Code value-validity check at the smpte291 branch
(grep for `local vpid = params["VPID_Code"]`) doesn't see the
duplication.

**Change**: in the smpte291 branch, count raw `VPID_Code=` occurrences
in `fmtp.value` (e.g. `select(2, fmtp.value:gsub("VPID_Code=", ""))`).
If > 1, reject with cite `RFC 8331 §4`.

**Tests**:
- Pass: `fmtp:96 ...; VPID_Code=132` (single occurrence).
- Fail: `fmtp:96 ...; VPID_Code=132; VPID_Code=133` (duplicate).

### Commit 3 — **A3**: SSN year-suffix over-permissive

**Spec** (ST 2110-20:2022 §7.2): only `:2017` and `:2022` are defined.
(ST 2110-22:2022 §7.2 Table 2: only `:2019` and `:2022`.)

**Parser**: `local _ssn20_pat = P("ST2110-20:") * _ssn_year * P(-1)`
where `_ssn_year = R("09") * R("09") * R("09") * R("09")` (any 4 digits).
Same shape for `_ssn22_pat`. Accepts `ST2110-20:9999` today.

**Change**:
- `_ssn20_pat = P("ST2110-20:") * (P("2017") + P("2022")) * P(-1)`
- `_ssn22_pat = P("ST2110-22:") * (P("2019") + P("2022")) * P(-1)`

**Caveat**: ST 2110-41:2024 §6 only defines `:2024` so far; `_ssn41_pat`
should probably narrow to `P("2024")` too, but verify against any test
fixtures using other years first.

**Tests**: pass `ST2110-20:2017` and `ST2110-20:2022`; fail
`ST2110-20:1999`, `ST2110-20:2018`, `ST2110-20:9999`.

### Commit 4 — **A5**: jxsv width/height upper bound 32767

**Spec** (ST 2110-22:2022 §7.2 Table 1, restating ST 2110-20:2022 §7.2):
*"Permitted values are integers between 1 and 32767 inclusive."*

**Parser**: `local jxs_req = {` table (grep). `width` and `height` use
`valid_pos_int` — lower bound only. The uncompressed-video path (grep
for `local video_checks = {`) uses `valid_width` / `valid_height` which
enforce ≤32767.

**Change**: swap `valid_pos_int` → `valid_width` / `valid_height` in
the jxsv table.

**Tests**: in the jxsv test block, pass `width=32767`, `height=32767`;
fail `width=32768`, `width=99999`.

### Commit 5 — **A6 (subset)**: BT2100 colorimetry → RANGE restricted

**Spec** (ST 2110-20:2022 §7.3): *"When the colorimetry value is BT2100,
only the NARROW and FULL values are permitted."* This is an explicit
"only … permitted" prohibition — distinct from the table-defined
value-sets PLAN.md "Known Deferred Items" excludes.

**Parser**: in the raw-video branch (grep for `elseif m.media == "video"`),
the `range_val` check (grep `range_val = params["RANGE"]`) validates
against `VALID_RANGE = {NARROW, FULLPROTECT, FULL}` but doesn't
cross-check with `colorimetry`.

**Change**: after the existing RANGE enum check, if `params["colorimetry"]
== "BT2100"` and `range_val == "FULLPROTECT"`, reject with cite
`ST 2110-20:2022 §7.3`.

**Scope**: raw video only (jxsv RANGE per RFC 9134 §7.1 is independent
and the spec doesn't import this cross-rule — verified in Phase 1).

**Tests**: pass `colorimetry=BT2100; RANGE=NARROW` and `RANGE=FULL`;
fail `colorimetry=BT2100; RANGE=FULLPROTECT`.

### Commit 6 — **A7**: Whitespace around `=` in fmtp

**Spec** (ST 2110-20:2022 §7.1): *"Each parameter entry shall be
constructed as either: 'name=value' (no whitespace) or 'name' (no
value)."*

**Parser**: `local function fmtp_params` (grep). Pattern
`trimmed:match("^([^=%s]+)%s*=%s*(.-)$")` allows whitespace around `=`.

**Change**: tighten the regex to `"^([^=%s]+)=(.-)$"` (no whitespace
before or after `=`).

**Scope**: this is the shared `fmtp_params` — affects every fmtp parse,
not just -20. ST 2110-22 §7.2 doesn't speak to this; RFC 4566 §6 is
silent. The strict reading is from -20 §7.1. Verify no existing test
fixture relies on `name = value` form before tightening; if any do,
either:
(a) Tighten and update the fixtures.
(b) Move the strict check into a per-encoding step in the raw-video
    branch only.

**Tests**: pass `width=1920`; fail `width = 1920`, `width =1920`,
`width= 1920`. Cite `ST 2110-20:2022 §7.1`.

### Commit 7 — **A9**: TSMODE=SAMP → TSDELAY presence dependency

**Spec** (ST 2110-10:2022 §8.7): the TSMODE=SAMP case requires TSDELAY
to be signaled (look up the exact quote in the on-disk 2022 PDF —
`pdftotext -layout`).

**Parser**: `local video_opt_checks = {` (grep). TSMODE and TSDELAY are
validated independently (each entry validates its own value form);
nothing cross-checks that TSMODE=SAMP implies TSDELAY presence.

**Change**: after the `video_opt_checks` loop, in the raw-video branch,
add: if `params["TSMODE"] == "SAMP"` and `params["TSDELAY"] == nil`,
reject with cite `ST 2110-10:2022 §8.7`.

**Note**: this fix is RAW-VIDEO-ONLY today because TSMODE/TSDELAY
validation lives only in the raw-video branch (see finding A8 in
PHASE3_FINDINGS.md — TSMODE/TSDELAY scope expansion is a Wave 3 item).
After A8 lands, hoist this cross-check too.

**Tests**: pass `TSMODE=NEW` (no TSDELAY required), `TSMODE=SAMP;
TSDELAY=100`; fail `TSMODE=SAMP` alone.

### Commit 8 — **A12**: Session-level source-filter syntax validation

**Phase 1 inventory note**: media-level `a=source-filter` is validated
via `valid_source_filter` inside `st2110.validate`'s media-block loop.
Session-level `a=source-filter` is only checked for presence in the
IPMX validator and never has its value syntax validated. Asymmetric.

**Parser**: `function st2110.validate` (grep). Find the media-block
loop; add a symmetric session-level scan that runs `valid_source_filter`
on every session-level `a=source-filter` value.

**Change**: in `st2110.validate`, before or after the per-media loop,
walk `doc.session.attributes` and for each `source-filter` attribute,
call `valid_source_filter` with cite `RFC 4570 §3 / ST 2110-10:2022 §8.4`.

**Tests**: pass valid session-level `a=source-filter:incl IN IP4 …`;
fail malformed session-level `a=source-filter: incl IN IP4` (missing
src).

### Commit 9 — **A13**: Mixed traceable / non-traceable ts-refclk

**Spec** (RFC 7273 §4.8): *"A media stream shall not signal both
'traceable' and non-'traceable' reference clocks in the same SDP at
the same level."* Verify exact wording in the on-disk RFC 7273 text
(`curl https://www.rfc-editor.org/rfc/rfc7273.txt`).

**Parser**: in `st2110.validate`, the ts-refclk gathering loop (grep
for `all_tsrefclk = {}`). After all ts-refclk values are validated
individually, classify each as traceable (presence of `:traceable`
suffix or `ptp=…:traceable`) vs non-traceable. If both classes appear
at the same level, reject.

**Scope**: enforce per-level — session-level and media-level
independently. RFC 7273 §4.8 says "at the same level."

**Change**: add a post-validation pass that classifies and rejects
mixed-class. Cite `RFC 7273 §4.8`.

**Tests**: pass all-traceable, all-non-traceable; fail one of each at
the same level.

---

## Per-commit gates (commit-gate hook is real — see below)

Every commit must stage:

- `CHANGELOG.md` with a bullet under `[Unreleased]` describing the
  change. Include the verbatim primary-source spec quote.
- `PLAN.md` with a one-line Wave 2 progress note (e.g. *"B1 landed,
  A2 next"*).
- `parse_sdp.lua` (the parser change).
- `spec/*.lua` (new tests for pass + fail).
- `spec_conformance/manifest.lua` if any cite changes (audit it; see
  Wave 1 lesson below).

Then verify:

```sh
busted spec/                  # hermetic, must show 0 failures
busted spec_conformance/      # opt-in, must show 0 failures
```

Both must be clean before committing. The commit-gate hook
(`.claude/hooks/commit-gate.sh`) is enforced: it requires `CHANGELOG.md`
and `PLAN.md` staged when any `.lua` file is staged. Skip either and
the commit blocks.

Commit message format (match prior Wave 1 commits — `git log --oneline`
to see):

```
chore(<scope>): <short title> (audit <ID>)

<one-paragraph why, with the verbatim spec quote in quotation marks>

<one-paragraph what changed, naming files + functions>

<test count line: 777 hermetic + 10 conformance still pass>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## Lessons from Wave 1

1. **Conformance manifest cite audit.** When you change a `spec_ref`
   string that the parser emits, grep `spec_conformance/manifest.lua`
   for matching `expect_spec_ref` entries. Wave 1's E8 missed one
   (caught at the final test, fixed in follow-up commit `59cdd7b`).

2. **`fmtp_params` over-permissive on whitespace** (commit 6 / A7 in
   this wave). Touch is shared across every fmtp parse; verify the
   broader-than-raw-video impact before tightening.

3. **Section-number drift across revisions** (Wave 1 E8 had to remap
   ST 2110-30 §7.1 → §6.1 and §7.2 → §6.2.1 because the 2025 spec
   restructured). When citing ST 2110-30, always cite `:2025` form
   and verify the section number against the on-disk PDF.

---

## Decisions already made (PHASE3_FINDINGS.md §I)

- **D1**: Migrate base spec to RFC 8866 — Wave 5, not this wave.
- **D2**: SSN=ST2110-40:2021 receiver-equivalence — Wave 3 (A1).
- **D3**: A11 RFC 4570 cross-line check — Wave 4 (complex).
- **D5**: AES67-2018/2023 paywall — proceed with 2013 caveat in GUIDE.

None of these block Wave 2.

---

## Done condition

After all 9 Wave 2 commits land:

- Hermetic suite: ~786 passing (777 + ~9 new tests), 0 failures.
- Conformance suite: 10 / 0 (no fixture changes expected).
- `PLAN.md` says "Wave 2 complete."
- Working tree clean.
- Hand back to user for Wave 3 (or Wave 3+4+5 batched).

If any finding turns out to need re-evaluation against primary spec
text (the verbatim quote doesn't survive a careful re-read), **stop
and ask the user**. CLAUDE.md "Spec Verification Protocol" rule:
*"a finding that doesn't survive careful re-reading is, by
definition, opinion-based and excluded by the strictness principle."*
Do not land a parser change to "be safe."
