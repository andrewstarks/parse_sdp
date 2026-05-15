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

708 tests passing (hermetic) · 10/10 upstream conformance · allowlist empty.
Every validation check is grounded in explicit spec text. No known check is
opinion-only.

The AMWA / Streampunk SDPoker cross-reference backlog has been walked end to
end. All actionable PR-tagged and Issue-tagged findings have been evaluated
against primary spec text and either landed parser changes, added regression
tests, or were documented as non-applicable. See CHANGELOG.md for the
specific spec citations.

## Next

Remaining open work falls into two buckets:

**Own milestones (broad scope):**

- VSF TR-10-1 compatibility audit (AMWA Issue #36).
- Full ST 2110-21 traffic-shaping bounds audit (AMWA Issue #20: `TROFF`,
  `TSDELAY`, `CMAX` against the :2022 revision).
- JT-NM Tested updates for the ST 2110 revision (AMWA Issue #11).
- Full RFC 9134 jxsv parameter audit beyond what PR #21 covered
  (AMWA Issue #39 — `RANGE`, `interlace`, `segmented` per-jxsv form audit).

**Smaller open items:**

- Streampunk Issue #9 — `ts-refclk:localmac` edge cases.
- Streampunk Issue #12 / AMWA Issue #19 — further source-filter spec
  re-reads (currently we accept what RFC 4570 §3 allows; IPMX
  TR-10-TP-1 §13.2 mandates presence at the IPMX tier only).

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in routine
development unless new spec evidence emerges.

- **`exactframerate` lowest-terms enforcement** — ST 2110-20 §7.2 says "the
  numerically smallest numerator value possible" but does not phrase it as "shall
  not." Not enforced; noted in GUIDE.md.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists value
  sets independently and contains no explicit "shall not" for any combination of
  valid individual values.
- **ST 2110-31 AES3 fmtp** — AM824 audio currently uses the ST 2110-30 path
  (encoding name, channel-order, packet-fit checks). Revisit if new
  AES3-specific normative text emerges.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF allows
  FQDNs in the origin address; no ST 2110 clause explicitly forbids them there.
- **NMOS, RTCP Info Blocks, and capability subsetting** — out of SDP scope by
  definition. See GUIDE.md "What this library validates (and what it doesn't)."
