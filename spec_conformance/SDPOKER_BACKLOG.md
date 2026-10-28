# SDPoker / AMWA Backlog — Regression Index

Every finding from [AMWA-TV/sdpoker](https://github.com/AMWA-TV/sdpoker), the
Streampunk fork, and JT-NM Tested feedback that has touched this parser. The
list exists so future revisions can confirm we have not regressed against
SDPoker-derived behavior.

## How regressions are detected

Three layers, in increasing order of bite:

1. **Clause-cited tests** — each hermetic test that came out of an SDPoker
   PR/issue sits in one of the per-tier grammar specs and carries the
   governing clause in its `describe`/`it` string or in the `-- SPEC:`
   comment above it. The table below maps each finding to its test.
   Find the tests for a clause with:
   ```sh
   grep -nE "ST 2110-20:2022 §7.1|RFC 7273 §4.8" spec/grammar_*_spec.lua
   ```
2. **Hermetic suite** — `busted spec/` runs all rows in this table; CI gates on
   it. Any change that breaks an SDPoker test fails the build.
3. **Upstream-fixture conformance suite** — `busted spec_conformance/` runs
   the parser against pinned `AMWA-TV/nmos-testing` and `AMWA-TV/bcp-006-01`
   fixtures. See [README.md](README.md).
   The allowlist ([allowlist.lua](allowlist.lua))
   is empty — every divergence has either been resolved in the parser or
   declared a negative test with `expect = "fail"` in
   [manifest.lua](manifest.lua).

## Update protocol

When an SDPoker PR/issue is referenced or revisited:

1. Add or update the row below with **source · status · spec citation · test
   location**.
2. If the resolution lands a parser change: cite the same clause in the
   CHANGELOG entry and on the test.
3. If the resolution is *not adopted* (e.g. the proposal lacks primary spec
   text): add a row marked **Not adopted**, name the spec text that's missing,
   and — if the test fixture still exists — keep the test as a "we deliberately
   accept this" regression guard.
4. If the resolution is later reversed by a decision bead (`bd list --type
   decision --all`), rewrite the row to the current behaviour and cite the
   bead id.

---

## Findings

| Source | Spec citation | Resolution | Regression test |
| --- | --- | --- | --- |
| AMWA sdpoker [Issue #2](https://github.com/AMWA-TV/sdpoker/issues/2) (closed) | RFC 8866 §6.15 + ST 2110-20:2022 §7.1 | **Accepted both forms.** Early SDPoker rejected fmtp without trailing `"; "`; neither RFC 8866 nor ST 2110-20 mandates that. A trailing `;` is the warn-severity `sdp.a.fmtp.trailing-semicolon` (Streampunk #33 below); a separator `;` with no whitespace after it on a `raw` fmtp is the warn-severity `st2110-20.a.fmtp.semicolon-without-whitespace` (decision `parse_sdp-ajh`). | [spec/grammar_base_spec.lua:2976](../spec/grammar_base_spec.lua#L2976) · [spec/grammar_st2110_spec.lua:745](../spec/grammar_st2110_spec.lua#L745) |
| AMWA sdpoker PR #12 (open since 2022, never merged) | RFC 5888 §4 / §8.1 | **Not adopted — no spec basis.** PR #12 proposed requiring `a=mid` immediately before `m=` and as the SDP's last line. Neither constraint exists in RFC 5888. Parser accepts `a=mid` anywhere in the media block; the only `a=mid` checks are the §9 token form, tag uniqueness, and "every `m=` carries `a=mid` when `a=group` is present". | [spec/grammar_base_spec.lua:1621](../spec/grammar_base_spec.lua#L1621) · [spec/grammar_base_spec.lua:3104](../spec/grammar_base_spec.lua#L3104) |
| AMWA sdpoker PR #21 + BCP-006-01 | RFC 9134 §7.1 (jxsv sampling value set); ST 2110-22:2022 §7.2 | **Accepted RGB on jxsv.** The jxsv value sets follow RFC 9134 §7.1 (the `video/jxsv` registration ST 2110-22 points at), which lists RGB / XYZ / KEY / UNSPECIFIED alongside the YCbCr forms. Check id `st2110-22.a.fmtp.sampling-invalid-value`. | [spec/grammar_st2110_spec.lua:1898](../spec/grammar_st2110_spec.lua#L1898) (per-value loop over `ENUM_VALUES.sampling`) |
| AMWA sdpoker PR #38 | ST 2110-20:2022 §7.6 | **`ST2115LOGS3` accepted as a `raw` TCS value.** :2022 added an 11th value. Check id `st2110-20.a.fmtp.TCS-invalid-value`. | [spec/grammar_st2110_spec.lua:1385](../spec/grammar_st2110_spec.lua#L1385) |
| AMWA sdpoker [Issue #11](https://github.com/AMWA-TV/sdpoker/issues/11) (JT-NM Tested) | ST 2110-20:2022 §7.2 SSN clause | **Forward direction enforced.** Reject `TCS=ST2115LOGS3` or `colorimetry=ALPHA` paired with `SSN=ST2110-20:2017` (those values are undefined in :2017). Check id `st2110-20.a.fmtp.ssn-required-for-2022-only-values`. The reverse direction ("`SSN=:2022` is forbidden unless a :2022-only value is present") is not enforced — strict reading invalidates ~115 fixtures and most real :2022 senders. Decision `parse_sdp-m0w`. | [spec/grammar_st2110_spec.lua:1391](../spec/grammar_st2110_spec.lua#L1391) · [spec/grammar_st2110_spec.lua:1402](../spec/grammar_st2110_spec.lua#L1402) |
| AMWA sdpoker [Issue #19](https://github.com/AMWA-TV/sdpoker/issues/19) / Streampunk #12 | RFC 4570 §3 (silent on multicast); TR-10-1:2024 (no `source-filter` SHALL; the attribute appears only in its example SDPs); TR-10-TP-1 §13.2 (a test-plan verification item, not a specification requirement) | **`a=source-filter` is not mandated at any tier.** RFC 4570 does not require it for multicast, and no TR-10 clause says a sender shall emit it. The only `source-filter` checks are the value form (`sdp.a.source-filter.malformed`) and the RFC 4570 §3.1 destination cross-check (`sdp.a.source-filter.dest-not-in-connections`). An earlier revision of this file said the IPMX tier required it; that was never backed by TR-10 text and the current grammar does not do it. | [spec/grammar_st2110_spec.lua:2690](../spec/grammar_st2110_spec.lua#L2690) · every `examples/st2110/valid/*.sdp` (none carries `a=source-filter`) via `spec/examples_spec.lua` |
| Streampunk sdpoker [Issue #9](https://github.com/Streampunk/sdpoker/issues/9) | RFC 7273 §4.8 (`clksrc = ntp / ptp / gps / gal / glonass / local / private / clksrc-ext`); ST 2110-10:2022 §8.2 ("Devices which are not referenced to IEEE Std 1588-2008 shall use an appropriate ts-refclk format as specified in IETF RFC 7273 or the extended form shown below") | **`a=ts-refclk:local` is accepted at every tier.** It is the RFC 7273 §4.8 `local` clock source, which §8.2 admits by reference. The base check `sdp.a.ts-refclk.malformed` rejects a defined source name used in the wrong form (`gps=1`, bare `ntp`); an unknown token (`locl`) is an RFC 7273 `clksrc-ext` extension and is accepted. An earlier revision of this file said `:local` was rejected as a typo of `:localmac=`; RFC 7273 defines it, so the rejection had no spec basis. | [spec/grammar_base_spec.lua:1956](../spec/grammar_base_spec.lua#L1956) · [spec/grammar_st2110_spec.lua:2690](../spec/grammar_st2110_spec.lua#L2690) |
| Streampunk sdpoker PR #16 follow-up | ST 2110-40:2023 §7 + ST 2110-10:2022 §8.5 / ST 2022-7 / RFC 7104 | **smpte291 DUP legs validated** as ordinary -40 streams plus the essence-agnostic `st2110-10.a.group-dup.*` leg-coherence checks. | [spec/grammar_st2110_spec.lua:3042](../spec/grammar_st2110_spec.lua#L3042) (-40 fmtp) · [spec/grammar_st2110_spec.lua:3609](../spec/grammar_st2110_spec.lua#L3609) (DUP coherence) |
| Streampunk sdpoker [Issue #25](https://github.com/Streampunk/sdpoker/issues/25) | RFC 7273 §4.8 (`ptp-server = ptp-gmid [":" ptp-domain] / "traceable"`); ST 2110-10:2022 §8.2 | **PTP domain optional at every tier.** The RFC 7273 ABNF makes `:<domain>` optional and the base grammar follows it (`sdp.a.ts-refclk.ptp-malformed` accepts `ptp=<version>:<EUI-64>` with no domain). ST 2110-10 §8.2 says PTP-referenced devices "shall use the ts-refclk:ptp form, signaling either the grandmaster clockIdentity and domain number, or signaling that the PTP is traceable"; that tightening is not yet enforced at the ST 2110 tier and GUIDE.md lists the PTP domain among the implementation limitations. Revisit under `parse_sdp-j7c.7`. An earlier revision of this file said the domain was required; the current grammar does not do that. | [spec/grammar_base_spec.lua:1929](../spec/grammar_base_spec.lua#L1929) |
| Streampunk sdpoker [Issue #33](https://github.com/Streampunk/sdpoker/issues/33) | RFC 8866 §6.15; ST 2110-20:2022 §7.1 ("There is no semicolon character after the last item.") | **Trailing `;` is the warn-severity `sdp.a.fmtp.trailing-semicolon`**, recorded at the base tier on every fmtp, raw or not. The lax form is unambiguous, so it is soft-syntactic; raise it to `error` through the policy table to reject. Decision `parse_sdp-ajh` keeps a trailing `;` on this id rather than on the -20 separator id. An earlier revision of this file said the line was rejected. | [spec/grammar_base_spec.lua:2962](../spec/grammar_base_spec.lua#L2962) · [spec/grammar_st2110_spec.lua:754](../spec/grammar_st2110_spec.lua#L754) |

## Checks removed because they lacked SDPoker / spec grounding

These were either inherited from an early reading or removed during the audit
in commit `467f859` ("Add opt-in AMWA conformance suite; remove
spec-unsupported parser checks") because primary text contradicted them.
Listing them here so a future reviewer doesn't re-introduce them by accident.

| Removed check | Reason |
| --- | --- |
| Blanket "every fmtp universally required" | ST 2110-10:2022 §8 imposes no such rule. Per-encoding branches enforce only what each spec demands (`st2110-20.a.fmtp.<key>-required`, `st2110-22.a.fmtp.<key>-required`, `st2110-40.a.fmtp.ssn-required`). |
| `channel-order` required for audio | ST 2110-30:2025 §6.2.2: when absent, channels are "Undefined" — the spec defines the absent case rather than forbidding it. Only the value form is checked (`st2110-30.a.fmtp.channel-order-invalid`). [spec/grammar_st2110_spec.lua:2340](../spec/grammar_st2110_spec.lua#L2340) |
| `PM` required for jxsv | `PM` is the ST 2110-**20** packing-mode marker. ST 2110-22 §7.2 Table 1 lists `packetmode` (per RFC 9134), not `PM`. The jxsv required set is `width`, `height`, `TP`, `packetmode`. [spec/grammar_st2110_spec.lua:1787](../spec/grammar_st2110_spec.lua#L1787) |
| `transmode` required for jxsv | Not in ST 2110-22 §7.2. The IPMX JPEG-XS Profile §6.1.4 `transmode` requirement applies to the **RTCP Media Info Block**, not SDP fmtp (CLAUDE.md "Spec Verification Protocol" rule 6 — bullet-scope binding). When present its value is checked (`st2110-22.a.fmtp.transmode-invalid-value`). |
| `DID_SDID` required for smpte291 | RFC 8331 §4 marks it optional; ST 2110-40:2023 §7 doesn't tighten it. Value form and repetition are checked. [spec/grammar_st2110_spec.lua:3252](../spec/grammar_st2110_spec.lua#L3252) |
| `fbblevel` SDP fmtp validation (audit D2) | No spec defines `fbblevel` as an SDP fmtp parameter. It exists only in the RTCP JPEG-XS Media Info Block (TR-10-15-Part1 §12). |
| `a=fmtp` payload type must match an `a=rtpmap` payload type | Dropped with the 1.0 implementation. RFC 8866 §6.15 and RFC 3551 support it and the Strictness Principle names it as in scope, so GUIDE.md lists it as an implementation limitation rather than a decision. Revisit under `parse_sdp-j7c.7`. |

## Adjacent corrections

Citation cleanups that came out of SDPoker / audit reviews:

- jxsv `RANGE` cite refined from "ST 2110-22 §7" to **RFC 9134 §7.1** (the IANA
  `video/jxsv` registration is the value-form authority). The jxsv `sampling`,
  `colorimetry`, and `TCS` sets cite the same clause.
- The jxsv `TP` set includes `2110TPN` per ST 2110-22:2022 §7.2 Table 1
  (`st2110-22.a.fmtp.TP-invalid-value`).
