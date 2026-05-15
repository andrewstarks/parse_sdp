# Plan

## Guiding Principles

- **Test first.** Every feature begins with failing tests.
- **Strict by spec.** Every validation check must cite explicit normative spec
  text — a positive "shall" / "MUST", a prohibitive "shall not" / "MUST NOT" /
  "is forbidden", or a defined value form / value set for an optional field.
  Spec silence is not a reason to reject.
- **Layered.** Each tier (RFC 4566 → ST 2110 → IPMX) extends the previous; it
  never replaces it.
- **Tight.** If a file is growing, stop and refactor before continuing. Prefer
  fewer, well-named things.
- **Fail loudly.** Parse failures report exactly where and why.
- **Round-trip.** `doc:to_sdp()` must produce output that re-parses to an
  equivalent table. This is a hard invariant.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.5 |
| Parsing | LPEG |
| JSON | dkjson (pure Lua, LuaRocks) |
| Tests | busted |
| Container | Docker (Lua 5.5 + LuaRocks base image) |

## Test Command

```sh
busted spec/                  # local — hermetic suite
busted spec_conformance/      # opt-in upstream-fixture conformance suite
docker compose run test       # Docker (runs the hermetic suite)
```

The `spec_conformance/` suite downloads pinned SDP fixtures from
`AMWA-TV/nmos-testing` and `AMWA-TV/bcp-006-01` into a gitignored cache, then
runs them through the parser. See [spec_conformance/README.md](spec_conformance/README.md).

---

## Current State (v0.1.0 — 2026-05-14)

666 tests passing. Every validation check is grounded in explicit spec text.
No known check is opinion-only. The codebase is internally consistent with the
conformance principle documented in CLAUDE.md and GUIDE.md.

---

## Resolved Findings from Upstream Conformance Suite

The conformance suite (`busted spec_conformance/`) currently passes
**10 / 10** against pinned AMWA fixtures. The allowlist is empty.

### Parser fixes landed

- ✅ **Removed blanket fmtp-required check.** ST 2110-10:2022 §8 imposes no
  universal fmtp requirement; the previous "ST 2110-10 §7" citation pointed
  to the System Timing Model, which is unrelated. Per-encoding branches now
  enforce what each encoding actually requires.
- ✅ **Made channel-order optional.** ST 2110-30:2017 §6.2.2 explicitly
  defines the behavior when channel-order is absent ("audio channels shall
  be treated as Undefined").
- ✅ **Removed PM requirement for jxsv.** ST 2110-22:2019 / :2022 §7.2
  Table 1 lists only width/height/TP as mandatory. PM is the ST 2110-20
  packing-mode marker; jxsv uses `packetmode` per IANA `video/jxsv`.
- ✅ **Made SSN optional for jxsv.** ST 2110-22:2022 §7.2 Table 2 marks SSN
  optional; ST 2110-22:2019 did not define it.
- ✅ **Expanded `VALID_TP_22`.** ST 2110-22:2022 §7.2 Table 1 added
  `2110TPN` to the TP enum.
- ✅ **Made transmode optional at ST 2110 tier.** Not in ST 2110-22 §7.2
  Table 1 (mandatory) or Table 2 (optional); IANA `video/jxsv` marks it
  optional. **Correction:** my earlier claim that the IPMX tier requires
  transmode in SDP was wrong. IPMX JPEG-XS Video Profile §6.1.4 lists
  transmode/packetmode/profile/level/sublevel/fbblevel as fields to populate
  in the **RTCP JPEG-XS Media Info Block (type 0x0003)** — not SDP fmtp.
  §6.1.4 item 3 defers SDP requirements to TR-10-11, and TR-10-11 §10 just
  says "construct SDP per ST 2110-22 §7." No tier requires transmode in
  SDP fmtp.
- ✅ **Made DID_SDID optional for smpte291.** ST 2110-40:2023 §7 does not
  mention DID_SDID; RFC 8331 marks it explicitly optional.
- ✅ **Made jxsv `profile` / `level` / `sublevel` optional at every tier.**
  ST 2110-22:2022 §7.2 Table 1 lists only width/height/TP as mandatory;
  IANA `video/jxsv` requires only `packetmode` beyond rate. The IPMX
  JPEG-XS Video Profile §6.1.4 references those fields for the RTCP
  JPEG-XS Media Info Block (out of validator scope), not SDP fmtp.
  TR-10-11 §10 defers SDP construction to ST 2110-22 §7. Validate value
  format when present.
- ✅ **Enforced ST 2110-40:2023 §7 SHALL clauses on smpte291 fmtp.** SSN
  (value gated by `TM` presence) and `exactframerate` are now required;
  `TM` (`LLTM`/`CTM`) and `TROFF` (positive integer per ST 2110-21) are
  validated when present. The pre-2023 `nmos-testing:data.sdp` fixture
  carries no fmtp; it now runs in the conformance suite as a negative
  test with `expect_spec_ref = "ST 2110-40:2023 §7"`.

### Confirmed correct (no change)

- ✅ **2022-7 redundancy distinct-addressing rule.** ST 2110-10:2022 §8.5
  explicitly forbids redundant streams from using both identical source AND
  identical destination addresses at the same time. The nmos-testing
  `video-2022-7.sdp` template is non-conformant per this clause; we run it
  as a negative test (`expect = "fail"`) that asserts the parser rejects it
  with the correct spec_ref.

### Open follow-ups (not on the critical path)

None at this time. Next strictness-principle work should come from the
SDPoker cross-reference backlog below, or from new fixtures added to the
conformance suite.

## SDPoker Cross-Reference Backlog

Full inventory of substantive PRs and issues from both SDPoker forks. Each
entry needs a per-clause spec read against parse_sdp.lua before action.
Skip-tagged entries are dependabot / operational and not interesting for
parse_sdp.

Sources:
- [AMWA-TV/sdpoker](https://github.com/AMWA-TV/sdpoker) — canonical fork
- [Streampunk/sdpoker](https://github.com/Streampunk/sdpoker) — original
  fork; Streampunk #30 directs new work to AMWA-TV, but historical PRs/issues
  still contain useful findings

### Spec-grounded findings to evaluate

**Grammar / RFC 4566:**

- AMWA PR #18 (MERGED) — RFC 4566 §5: SDP file must end with a newline; no
  blank lines permitted between records. Verify parse_sdp enforces both.
- AMWA PR #15 (MERGED) — `a=fmtp:<pt>` with no params (just PT) should
  parse; current SDPoker regex required at least one param. Verify
  parse_sdp accepts the param-less form.
- AMWA Issue #56 (CLOSED) — `s= ` (single-space session name) is valid per
  RFC 8866; SDPoker had rejected. Verify parse_sdp accepts.
- AMWA Issue #2 (CLOSED) — Relax fmtp line-ending check. Verify.
- Streampunk Issue #33 (OPEN) — fmtp pattern doesn't match ST 2110-20:2022
  §7.1 wording: *"separated by the semicolon (";") character followed by
  whitespace"*. The whitespace-after-semicolon is in the 2022 revision.
  Check parse_sdp grammar against the 2022 wording (including the
  trailing-CR clause).
- Streampunk Issue #11 (CLOSED) — `s= ` whitespace. Resolved upstream.

**ST 2110-10:**

- AMWA Issue #1 (OPEN) — `a=mediaclk:direct` syntax: RFC 7273 defines
  `direct = "direct" [ "=" 1*DIGIT ] [SP rate]` and `rate = "rate=" integer
  "/" integer`. SDPoker only validates the direct=N part and accepts any
  rate string. Worth checking parse_sdp's rate validation.
- AMWA Issue #36 (OPEN) — VSF TR-10-1 compatibility. Broad.
- Streampunk Issue #25 (OPEN) — ST 2110 PTP domain should not be optional.
  Worth a spec re-read of ST 2110-10:2022 §8.2 against parse_sdp's
  ts-refclk:ptp parsing.
- Streampunk PR #24 (OPEN) — Three PTP findings, all from RFC 7273:
  (a) `ptpPattern` should accept uppercase hex only (RFC 5234 HEXDIG); we
  probably allow lowercase. (b) The pre-errata `domain-name=` prefix form
  should be removed per RFC 7273 errata 4450. (c) `ptp-domain-name` only
  applies to IEEE 1588-2002 (v1), not 2008 (v2). Verify each against
  parse_sdp's ts-refclk validator.
- Streampunk Issue #9 (OPEN) — `ts-refclk:local` — likely about `localmac`.
  Verify parse_sdp handles the localmac form correctly.

**ST 2110-20 (raw video):**

- Streampunk PR #22 (OPEN) — Typo bug: SDPoker check used
  `stream.interlaced` when the actual fmtp parameter is `interlace`. Verify
  parse_sdp uses the right name (we cited ST 2110-20 §7.3 — should be
  consistent).
- AMWA PR #38 (MERGED) — **ST 2110-2022 updates**: Verified items —
  ✅ `TSMODE`/`TSDELAY` (we have), ✅ `mediaclk direct\|sender` (we have),
  ✅ `colorimetry=ALPHA` (we have). **❌ Missing:** `TCS=ST2115LOGS3` — new
  value in ST 2110-20:2022 not in our `VALID_TCS`. Verify against the
  ST 2110-20:2022 PDF and add.

**ST 2110-22 (JPEG XS):**

- AMWA PR #21 (MERGED) — BCP-006-01 RGB support: extends jxsv sampling
  values to cover RGB. Verify parse_sdp's `VALID_SAMPLING` covers RGB
  sampling forms used in jxsv.
- AMWA Issue #39 (OPEN) — Check RFC 9134 format-specific parameters in
  full. Cross-reference against parse_sdp's jxsv branch (already trimmed
  to PM-out, transmode-optional).

**ST 2110-30 (audio):**

- Streampunk PR #13 (MERGED, AMWA Issue #14 CLOSED) — fmtp optional for
  ST 2110-40 (smpte291). ✅ Confirmed/applied in our recent fix.
- Streampunk Issue #17 (OPEN) — "SDPoker doesn't accept SMPTE-2110-31 sub
  media type (AM248)". The actual encoding name is `AM824`; either the
  issue title is a typo, or this is about an obscure variant. Worth a
  quick check.

**ST 2110-40 (ancillary data):**

- Streampunk PR #19 (OPEN) — Per RFC 8331 §4, subtype `smpte291` must be
  paired with type `video` in the `m=` line. Verify parse_sdp rejects
  `m=audio … smpte291/90000`.
- Streampunk PR #16 (OPEN) — Fix fmtp testing for ST 2110-40 in ST 2022-7
  (DUP) groups. Verify parse_sdp handles ancillary DUP-leg pairs.

**Source-filters / multicast (RFC 4570):**

- AMWA Issue #19 (OPEN) — Mandatory source-filter when multicast is used:
  the issue argues SDPoker over-enforces; RFC 4570 §3 doesn't require it.
  Check parse_sdp's stance (we currently make source-filter optional at
  ST 2110 and mandatory at IPMX — verify against TR-10-TP-1 §13.2 cite).
- Streampunk Issue #12 (OPEN) — Tests for source-filter. Cross-check.
- Streampunk PR #23 (OPEN) — Additional source-filter testing. Cross-check.
- Streampunk PR #15 (MERGED) — Basic source-filter formatting. Verify.

**Traffic shaping (ST 2110-21):**

- AMWA Issue #20 (OPEN) — Check for traffic shaping. ST 2110-21 mostly
  RTCP-side, but `TROFF`, `TSDELAY`, `CMAX` are SDP-fmtp. Verify our
  bounds against the 2022 revision.

**Bigger / cross-cutting:**

- AMWA Issue #11 (OPEN) — JT-NM Tested updates for ST 2110 revision.
  Useful as a checklist of what the JT-NM TCG considered breaking.
- AMWA PR #12 (OPEN) — Stricter `a=mid` position verification: requires
  `a=mid` to be the immediately-preceding line before `m=`, and the last
  line of the SDP to be `a=mid:`. PR has been open since 2022 without
  merge — probably over-strict relative to RFC 5888 §8.1, which only
  requires `mid` to appear in the media block, not in a specific position.
  Worth verifying against RFC 5888 / 5234 ABNF before adopting.
- AMWA PR #21 → AMWA Issue #11 → multiple TR-10 docs are interlinked;
  resolving #11 may surface other findings.

### Already resolved by parse_sdp's recent fixes

- AMWA Issue #14 (CLOSED) / Streampunk PR #13 (MERGED): fmtp optional for
  smpte291. ✅ Matched by our DID_SDID fix.
- AMWA Issue #17 (CLOSED) → AMWA PR #18 (MERGED): SDP CRLF endings.
  parse_sdp already enforces CRLF in serializer and accepts both CRLF/LF
  in parser. Verify per-edge case.
- AMWA Issue #24 (CLOSED) → AMWA PR #38 (MERGED): ST 2110:2022 updates.
  Mostly matched by parse_sdp; only `TCS=ST2115LOGS3` missing.

### Likely skip (operational, dependabot, packaging)

- AMWA PRs #43–#55, #28–#35, #22–#23 (all `dependabot/npm_and_yarn/*`):
  Node.js dependency bumps. No relevance to a Lua codebase.
- AMWA PR #42 (MERGED) / Issue #41 (CLOSED): `--skipRFC4566` /
  `--skipRFC4570` / `--skipST2110` CLI flags. Operational, not spec.
- AMWA PR #10 (MERGED), Issue #9 (CLOSED): release packaging. Operational.
- AMWA Issue #13, #25, #26, #27, #37 (OPEN): refactor / CI / dependency
  hygiene. Operational.
- AMWA Issue #4 (OPEN): "support for testing other common SDP files."
  Scope-broadening, not a spec finding.
- Streampunk PR #5, #10 (MERGED): typo fixes.
- Streampunk PR #7 (MERGED), Issue #6 (CLOSED): "ignore ancillary"
  (Streampunk era — predates Streampunk #13 which made fmtp optional for
  -40 properly). Superseded.
- Streampunk PR #8 (OPEN): "add the SDP of a real ST 2110 sender" —
  example file, not a spec finding.
- Streampunk Issue #30 (OPEN): admin redirect to AMWA fork.
- Streampunk Issue #4 (OPEN): `.sdp` filename extension check. Operational.
- Streampunk Issues #1, #2, #3, #6, #11 (all CLOSED): historical bugs
  resolved upstream.

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in routine
development unless new spec evidence emerges.

- **`exactframerate` lowest-terms enforcement** — ST 2110-20 §7.2 says "the
  numerically smallest numerator value possible" but does not phrase it as "shall
  not." Not enforced; noted in GUIDE.md.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists value
  sets independently and contains no explicit "shall not" for any combination of
  valid individual values.
- **ST 2110-31 AES3 fmtp** — the ST 2110-31 PDF was unavailable at time of
  implementation. AM824 audio currently uses the ST 2110-30 path (encoding name,
  channel-order, packet-fit checks). Revisit when the PDF is accessible.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF allows
  FQDNs in the origin address; no ST 2110 clause explicitly forbids them there.
- **NMOS, RTCP Info Blocks, and capability subsetting** — out of SDP scope by
  definition. See GUIDE.md "What this library validates (and what it doesn't)."
