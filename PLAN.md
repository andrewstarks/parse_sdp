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

## Current State

728 tests passing (hermetic) · 10/10 upstream conformance · allowlist empty.
Every validation check is grounded in explicit spec text. No known check is
opinion-only.

The AMWA / Streampunk SDPoker cross-reference backlog has been walked end to
end. All actionable PR-tagged and Issue-tagged findings have been evaluated
against primary spec text and either landed parser changes, added regression
tests, or were documented as non-applicable. See CHANGELOG.md for the
specific spec citations.

## Next

The AMWA / Streampunk SDPoker backlog is fully walked. No tracked items
remain open. Future work is driven by new spec releases, new conformance-
fixture findings, or user reports.

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in routine
development unless new spec evidence emerges.

- **ST 2110-20:2022 §7.2 "default to SSN=:2017 unless :2022-only values are
  used"** — the §7.2 SSN clause has a reverse direction ("Senders implementing
  this standard shall signal the value ST2110-20:2017 unless [exception]")
  that, strictly enforced, would invalidate `SSN=ST2110-20:2022` whenever
  neither `TCS=ST2115LOGS3` nor `colorimetry=ALPHA` is present. ~115 existing
  test fixtures and most real-world :2022-implementing senders signal :2022
  unconditionally. The forward direction (the JT-NM Tested ask) is enforced;
  the reverse is left to a future audit if SMPTE or AMWA clarifies intent.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists value
  sets independently and contains no explicit "shall not" for any combination of
  valid individual values.
- **ST 2110-31 AES3 fmtp** — AM824 audio currently uses the ST 2110-30 path
  (encoding name, channel-order, packet-fit checks). Revisit if new
  AES3-specific normative text emerges.
- **ST 2110-21 §7.1 CMAX upper bound** — the type-specific formula
  `MAX(4, INT(NPACKETS/(43200 × R_ACTIVE × T_FRAME)))` (and the Type W
  variant with `16` and `21600`) is an upper bound on `CINST` per the
  Network Compatibility Model in §6.6.1, not a lower bound on the SDP
  CMAX value. Enforcing the upper bound requires NPACKETS / MAXUDP /
  width × height × depth × sampling × frame-rate context; not added.
- **ST 2110-21 §6.2 vs §8.2 TROFF zero handling** — §6.2 explicitly
  permits TROFFSET to be zero (and requires it be signaled when it
  differs from TRODEFAULT), while §8.2 says the SDP value is "expressed
  as a positive integer." The parser follows the §8.2 value-form SHALL
  and rejects `TROFF=0`. Revisit only if SMPTE issues an erratum.
- **ST 2110-10:2022 §8.7 vs Annex B TSDELAY zero** — §8.7 says
  "decimal positive integer"; Annex B (Informative) example shows
  `TSDELAY=0`. The §8.7 SHALL governs; parser rejects `TSDELAY=0`.
- **VSF TR-10-1 (IPMX System Timing) SDP-validation audit** — every
  SDP-touching SHALL in TR-10-1 §10 (and the SDP-adjacent §8.1 traffic
  shape) is already enforced by the parser: §10 FID prohibition
  ([parse_sdp.lua:2031](parse_sdp.lua#L2031)), §10.1 `IPMX` fmtp marker,
  §10.2 `measuredpixclk`/`vtotal`/`htotal` (extended to all IPMX video
  by TR-10-9 §10), §10.3 `measuredsamplerate` (extended by TR-10-9
  §10), §10.4 media-level `ts-refclk` (via ST 2110-10 §8.2) and
  `ts-refclk:localmac` format, §10.5 `mediaclk` presence + `direct=0`
  enforcement (via ST 2110-10 §8.3 — same SHALL). §8.1 specifies
  CMAX = Type W formula with an informative Note permitting Type N for
  interop; Type NL is silent. The parser accepts the ST 2110-22:2022
  §7.2 union {2110TPN, 2110TPNL, 2110TPW}; the strictness principle
  ("silence is not a reason to reject") rules out narrowing further on
  Note language alone. Audited 2026-05-15 — no actionable findings.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF allows
  FQDNs in the origin address; no ST 2110 clause explicitly forbids them there.

