# Plan

## Guiding Principles

- **Test first.** Every feature begins with failing tests.
- **Strict by spec.** Every validation check must cite explicit normative spec
  text — a positive "shall" / "MUST", a prohibitive "shall not" / "MUST NOT" /
  "is forbidden", or a defined value form / value set for an optional field.
  Spec silence is not a reason to reject.
- **Layered.** Each tier (RFC 8866 → ST 2110 → IPMX) extends the previous; it
  never replaces it. RFC 8866 obsoletes RFC 4566.
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

777 tests passing (hermetic) · allowlist empty. Every validation check is
grounded in explicit spec text. No known check is opinion-only.

The AMWA / Streampunk SDPoker cross-reference backlog and the pre-1.0
conformance audit (first pass) have both been walked end to end. See
CHANGELOG.md for the specific spec citations and
[SDPOKER_BACKLOG.md](SDPOKER_BACKLOG.md) for the per-finding regression index.

**Audit Pass #31 (2026-05-16) — IN PROGRESS.** An inverted-direction audit
(spec → parser, the first such pass) enumerated ~1750 normative SDP-touching
clauses across 30+ specs cold, then mapped each to a parser line. Found 17
new findings (12 Direction-A, 1 Direction-B, 7 Direction-C / cosmetic) plus
6 RFC 8866 base-migration sub-findings. See
[audits/PHASE3_FINDINGS.md](audits/PHASE3_FINDINGS.md) for the full report
and a 28-commit landing plan in five waves. Wave 1 (citation cleanup) is
landing now.

**Wave 1 complete (citation cleanup).** All six commits landed plus a
follow-up manifest-cite fix:
- E1 RFC 5285 → RFC 8285 (`a=extmap`, 9 sites)
- E4 RFC 5888 §8.1 → §4 (a=mid uniqueness)
- E2 ST 2110-40 §7.2 → §5.3 / RFC 8331 §4 (clock-rate + VPID_Code)
- E3 ST 2110-40 MAXUDP §6.1.4 → §5.2.1
- E7 ST 2022-7 parenthetical removed from DUP error text
- E8 Year-tag consistency pass on ST 2110 cites

**Wave 2 in progress** (atomic Direction-A/B fixes — B1, A2, A3, A5,
A6 subset, A7, A9, A12, A13).

- B1 landed: DID_SDID 1-or-2 hex digits (RFC 8331 §4 ABNF).
- A2 landed: VPID_Code "appears only once" (RFC 8331 §4).
- A3 landed: SSN year-suffix closed sets ({2017,2022} / {2019,2022} /
  {2024}).
- A5 landed: jxsv width/height upper bound 32767 (ST 2110-22:2022 §7.2
  Table 1).
- A6 subset landed: BT2100 → RANGE ∈ {NARROW, FULL} only (ST 2110-20:2022
  §7.3).
- A7 landed: whitespace around '=' rejected in raw-video fmtp
  (ST 2110-20:2022 §7.1).
- A9 landed: TSMODE=SAMP requires TSDELAY (ST 2110-10:2022 §8.7);
  also fixed a nil-safety bug in the A2 VPID_Code check.
- A12 landed: symmetric session-level source-filter syntax validation
  (RFC 4570 §3).
- A13 landed: per-level mixed traceable / non-traceable ts-refclk
  rejection (RFC 7273 §4.8). **Wave 2 complete.**

**Wave 3 in progress** (medium-complexity Direction-A — A1, A4, A8,
A10, E5).

- A1 landed: SSN=ST2110-40:2021 receiver-equivalence (ST 2110-40:2023
  §7 / user decision D2).
- A4 landed: m=video raw subtype assertion (ST 2110-20:2022 §7.1).
- A8 landed: TSMODE/TSDELAY scope hoisted to all media types
  (ST 2110-10:2022 §8.7 umbrella).
- A10 landed: any a=group ⇒ every m= has a=mid (RFC 5888 §6).
- E5 landed: RFC 7273 cite-upstream for ts-refclk / mediaclk
  value-form errors. **Wave 3 complete.**

**Wave 4 in progress** (complex Direction-A — A11).

- A11 landed: RFC 4570 §3.1 dest-address ↔ c= cross-line check with
  full RFC 8866 §5.7 /numaddr expansion for IPv4 and IPv6 multicast
  (per user decision D3). **Wave 4 complete.**

**Wave 5 in progress** (RFC 8866 base migration — D1.7, D1.1, D1.2,
D1.3, D1.4, D1.5, D1.6).

- D1.7 landed: base-spec rename in CLAUDE.md + PLAN.md (no code).
- D1.1 landed: k= obsoleted per RFC 8866 §5.12 (parse-and-discard;
  serializer never emits).
- D1.2 landed: dynamic-PT requires a=rtpmap, hoisted to base tier
  (RFC 8866 §8.2.3).
- D1.3 landed: IPv4 multicast /ttl mandatory at base tier (RFC 8866
  §5.7). D1.4 next.

## Next

Wave 1: cite migrations (E1–E8). Wave 2–5: Direction-A/B fixes and the
RFC 8866 base migration. Per-finding commits with the standard gates.

## Pre-1.0 Conformance Audit — CLOSED (2026-05-15)

All F (false-positive) and N (false-negative) findings have landed; both
D (citation cleanup) findings are resolved. See CHANGELOG.md `[Unreleased]`
for the per-finding commits. The codebase has no known opinion-based
checks and no known spec-grounded SHALL that the validator misses.

**Resolved (2026-05-15):**

- F1 + D3 — TCS optional per §7.3 + GUIDE doc sync.
- F2 + D4 — `a=hkep` permitted at media level per TR-10-5 §17 + GUIDE doc sync.
- F3 — ST 2110-41 DIT is optional + comma-separated uppercase hex per §6.
- F4 — ST 2110-41 clock rate is Data-Item-defined per §5.3 (not fixed at 90 kHz).
- F5 — `channel-order` convention is SHOULD per ST 2110-30:2025 §6.2.2; non-`SMPTE2110` accepted structurally.
- F6 — `AES3` channel-grouping symbol added for AM824 per ST 2110-31:2022 §6.2 Table 2.
- F7 — Reframed (cite cleanup, no parser change). RFC 8866 §9 ABNF has
  `IP6-multicast = IP6-address [ "/" numaddr ]` — the IPv6 `/N` suffix is a
  layered-address count, not a TTL; the audit's recommendation to reject
  it conflated §5.7's TTL prohibition with §9's `numaddr` permit. Parser
  behavior unchanged; messages/comments now use the correct ABNF term.
- F9 — IPv4 layered multicast `<addr>/<ttl>/<numaddr>` accepted per RFC 8866 §9 IP4-multicast ABNF.
- F10 — IPv4 multicast TTL=0 accepted per RFC 8866 §5.7 (range 0-255) / §9 ABNF.
- F8 — RFC 4566 §5 `r=`, `z=`, session/media `k=`, and multiple `t=` blocks
  parsed, validated, and round-tripped through `to_sdp()`.
- F11 — ST 2110-10 §6.2 fixed-PT carve-out implemented: PT 10 (L16/44100/2)
  and PT 11 (L16/44100/1) accepted per RFC 3551 §6 statics; all other
  PTs outside 96-127 still rejected.
- N1 — TP is required for raw video at the ST 2110 tier per ST 2110-20:2022
  §6.1.1 → ST 2110-21:2022 §8.1 chain. Cross-field "TROFF/CMAX require TP"
  check dropped (subsumed by the always-required TP).
- N2 + N3 + N4 + N5 — ST 2110-31:2022 §5.5 / §6.1 AM824 SHALLs:
  even `<nchan>`, clock-rate ∈ {44100, 48000, 96000}, `a=ptime` required,
  ptime value in Table 1 for the prevailing rate. L16/L24 unaffected.
- N6 + N7 + N8 + N9 — ST 2110-22:2022 jxsv SHALLs: §6.2 requires
  `m=video`; §7.2 forbids trailing `;` on fmtp; §7.3 requires `b=AS:<kbps>`
  at the ST 2110 tier; §7.4 requires frame-rate signaling via either
  `a=framerate` or fmtp `exactframerate`.
- N10 — ST 2110-40:2023 §7 FID prohibition. At ST 2110 tier, scoped to
  SDPs with at least one smpte291 block (the §7 SHALL is in -40);
  IPMX-tier broader prohibition (TR-10-1 §10) unchanged.
- N11 — MAXUDP forbidden on smpte291 / ST2110-41 / audio per
  ST 2110-40:2023 §6.1.4, ST 2110-41:2024 §5.4, ST 2110-30:2025 §6.2.1
  (each constrains UDP size to the Standard limit; ST 2110-10 §6.4 / §8.6
  define MAXUDP as the signal that the sender exceeds the Standard limit).
- N12 + N13 — ST 2110-20:2022 cross-parameter SHALLs on raw video:
  §7.4.1 KEY-sampling requires colorimetry=ALPHA and no TCS; §6.2.5
  forbids 4:2:0 sampling combined with interlace. Both scoped to raw
  video only — RFC 9134 §7.1 does not import either SHALL into jxsv
  (verified directly against the RFC text).
- D1 — IPMX audio ptime cite corrected to ST 2110-30:2025 §6.2.1 (chains
  to AES67 §8.1). Side-effect: `a=ptime` is now required for ALL audio
  at the ST 2110 tier (extended from AM824-only). Redundant IPMX-tier
  check removed.
- D2 — `fbblevel` is not an SDP fmtp parameter in any spec; check removed
  per strictness principle. (It lives only in the RTCP JPEG-XS Media
  Info Block per TR-10-15-Part1 §12.)

These findings came out of a multi-spec audit that read every SDP-relevant
SHALL / SHALL-NOT / defined-value clause across RFC 4566, RFC 8866,
ST 2110-10/-20/-21/-22/-30/-31/-40/-41, ST 2022-7, RFC 7104, RFC 9134, and
VSF TR-10-1, -2, -3, -5 v2, -7, -10, -11, -13 v2, -14, -15, -TP-1, then
cross-referenced against the parser and tests.

**Working principle for the next thread.** Each item below names a clause and
quotes the diagnostic fragment. The audit was systematic, but the conformance
principle (CLAUDE.md) requires every check to be grounded in actual spec
text — not a paraphrase of it. Before changing parser behavior:

1. Open the cited spec (PDFs in `~/Library/CloudStorage/Dropbox/Personal/
   Claude/Macnica/Standards Related/smpte_standards_internal/`; TR-10 markdown
   in `…/TR-10 Markdowned Versions/`) and re-read the named clause in full
   context. The fragment quoted below may be qualified by surrounding text.
2. If the wording does not unambiguously support the finding, **stop and
   flag for discussion** — do not land a parser change pending confirmation.
   A finding that doesn't survive careful re-reading is, by definition,
   opinion-based and excluded by the strictness principle.
3. If the finding holds, land the parser change + new tests covering both
   passing and failing paths + GUIDE.md / README.md / CHANGELOG.md sync in
   one commit. The CHANGELOG entry should cite the same clause.

Items are grouped by severity. F = false positives (parser rejects compliant
SDPs; blockers for 1.0). N = false negatives (parser accepts non-conformant
SDPs; should-fix). D = documentation/citation cleanups.

---

All open audit items have been resolved. See the "Resolved since audit
opened" list at the top of this section for the canonical summary. The
audit is closed.

---

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

