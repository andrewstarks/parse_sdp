# SDPoker / AMWA Backlog — Regression Index

Every finding from [AMWA-TV/sdpoker](https://github.com/AMWA-TV/sdpoker), the
Streampunk fork, and JT-NM Tested feedback that has touched this parser. The
list exists so future revisions can confirm we have not regressed against
SDPoker-derived behavior.

## How regressions are detected

Three layers, in increasing order of bite:

1. **Inline test citations** — each hermetic test that came out of an SDPoker
   PR/issue carries the originating identifier in its `describe`/`it` string
   or the comment immediately above it. Greppable via:
   ```sh
   grep -nE "AMWA #|Streampunk #|JT-NM|sdpoker" spec/st2110_spec.lua parse_sdp.lua
   ```
2. **Hermetic suite** — `busted spec/` runs all rows in this table; CI gates on
   it. Any change that breaks an SDPoker test fails the build.
3. **Upstream-fixture conformance suite** — `busted spec_conformance/` runs
   the parser against pinned `AMWA-TV/nmos-testing` and `AMWA-TV/bcp-006-01`
   fixtures. See [spec_conformance/README.md](spec_conformance/README.md).
   The allowlist ([spec_conformance/allowlist.lua](spec_conformance/allowlist.lua))
   is empty — every divergence has either been resolved in the parser or
   declared a negative test with `expect = "fail"` in
   [spec_conformance/manifest.lua](spec_conformance/manifest.lua).

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

---

## Findings

| Source | Spec citation | Resolution | Regression test |
| --- | --- | --- | --- |
| AMWA sdpoker [Issue #2](https://github.com/AMWA-TV/sdpoker/issues/2) (closed) | RFC 4566 §6 + ST 2110-20:2022 §7.1 | **Accepted both forms.** Early SDPoker rejected fmtp without trailing `"; "`; neither RFC 4566 nor ST 2110-20 mandates that. Trailing-`;` is separately *forbidden* by §7.1 (Streampunk #33). | [spec/st2110_spec.lua:1323](spec/st2110_spec.lua#L1323) |
| AMWA sdpoker PR #12 (open since 2022, never merged) | RFC 5888 §4 / §8.1 | **Not adopted — no spec basis.** PR #12 proposed requiring `a=mid` immediately before `m=` and as the SDP's last line. Neither constraint exists in RFC 5888. Parser accepts `a=mid` anywhere in the media block. | [spec/st2110_spec.lua:3675](spec/st2110_spec.lua#L3675) |
| AMWA sdpoker PR #21 + BCP-006-01 | ST 2110-22:2022 §7.2 → ST 2110-20 §7.4.1 (sampling enum) | **Accepted RGB on jxsv.** §7.4.1 sampling values include RGB / XYZ / KEY; §7.2 imports them for jxsv. | [spec/st2110_spec.lua:3181](spec/st2110_spec.lua#L3181) |
| AMWA sdpoker PR #38 | ST 2110-20:2022 §7.6 | **Added `ST2115LOGS3` to `VALID_TCS`.** :2022 added an 11th value. | [spec/st2110_spec.lua:1177](spec/st2110_spec.lua#L1177) |
| AMWA sdpoker [Issue #11](https://github.com/AMWA-TV/sdpoker/issues/11) (JT-NM Tested) | ST 2110-20:2022 §7.2 SSN clause | **Forward direction enforced.** Reject `TCS=ST2115LOGS3` or `colorimetry=ALPHA` paired with `SSN=ST2110-20:2017` (those values are undefined in :2017). The reverse direction ("`SSN=:2022` is forbidden unless a :2022-only value is present") is documented as a deferred item — strict reading invalidates ~115 fixtures and most real :2022 senders. See [PLAN.md "Known Deferred Items"](PLAN.md#known-deferred-items). | [spec/st2110_spec.lua:1189](spec/st2110_spec.lua#L1189) |
| AMWA sdpoker [Issue #19](https://github.com/AMWA-TV/sdpoker/issues/19) / Streampunk #12 | RFC 4570 §3 (silent on multicast); TR-10-TP-1 §13.2 (IPMX) | **Source-filter not mandated at ST 2110 tier**, only at IPMX. RFC 4570 doesn't require `a=source-filter` for multicast. | [spec/st2110_spec.lua:1300](spec/st2110_spec.lua#L1300) |
| Streampunk sdpoker [Issue #9](https://github.com/Streampunk/sdpoker/issues/9) | ST 2110-10:2022 §8.2 | **Reject `ts-refclk:local`** (typo of `:localmac=`). Only the listed prefixes are valid. | [spec/st2110_spec.lua:1272](spec/st2110_spec.lua#L1272) |
| Streampunk sdpoker PR #16 follow-up | ST 2110-40:2023 §7 + ST 2022-7 / RFC 7104 | **Validate smpte291 DUP legs** as ordinary -40 streams plus -7 consistency. | [spec/st2110_spec.lua:4168](spec/st2110_spec.lua#L4168) |
| Streampunk sdpoker [Issue #25](https://github.com/Streampunk/sdpoker/issues/25) | ST 2110-10:2022 §8.2 | **PTP domain required** when not using `traceable`. | [spec/st2110_spec.lua:456](spec/st2110_spec.lua#L456) · [parse_sdp.lua:452](parse_sdp.lua#L452) |
| Streampunk sdpoker [Issue #33](https://github.com/Streampunk/sdpoker/issues/33) | ST 2110-20:2022 §7.1 | **Reject trailing `;`** on raw-video fmtp ("There is no semicolon character after the last item"). Strict per the 2022 wording. | [spec/st2110_spec.lua:1331](spec/st2110_spec.lua#L1331) |

## Checks removed because they lacked SDPoker / spec grounding

These were either inherited from an early reading or removed during the audit
in commit `467f859` ("Add opt-in AMWA conformance suite; remove
spec-unsupported parser checks") because primary text contradicted them.
Listing them here so a future reviewer doesn't re-introduce them by accident.

| Removed check | Reason |
| --- | --- |
| Blanket "every fmtp universally required" | ST 2110-10:2022 §8 imposes no such rule. Per-encoding branches enforce only what each spec demands. |
| `channel-order` required for audio | ST 2110-30 §6.2.2: when absent, channels are "Undefined" — the spec defines the absent case rather than forbidding it. Citation also corrected from §7.2 to §6.2.2. |
| `PM` required for jxsv | `PM` is the ST 2110-**20** packing-mode marker. ST 2110-22 §7.2 Table 1 lists `packetmode` (per RFC 9134), not `PM`. |
| `transmode` required for jxsv | Not in ST 2110-22 §7.2. The IPMX JPEG-XS Profile §6.1.4 `transmode` requirement applies to the **RTCP Media Info Block**, not SDP fmtp (CLAUDE.md "Spec Verification Protocol" rule 6 — bullet-scope binding). |
| `DID_SDID` required for smpte291 | RFC 8331 §4 marks it optional; ST 2110-40:2023 §7 doesn't tighten it. |
| `fbblevel` SDP fmtp validation (audit D2) | No spec defines `fbblevel` as an SDP fmtp parameter. It exists only in the RTCP JPEG-XS Media Info Block (TR-10-15-Part1 §12). |

## Adjacent corrections

Citation cleanups that came out of SDPoker / audit reviews:

- jxsv `RANGE` cite refined from "ST 2110-22 §7" to **RFC 9134 §7.1** (the IANA
  `video/jxsv` registration is the value-form authority).
- PT-mismatch cite corrected from "ST 2110-10 §7" to **RFC 4566 §6**.
- `VALID_TP_22` extended to include `2110TPN` per ST 2110-22:2022 §7.2 Table 1.
