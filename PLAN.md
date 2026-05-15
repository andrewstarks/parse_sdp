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
busted spec/          # local
docker compose run test   # Docker
```

---

## Current State (v0.1.0 — 2026-05-14)

666 tests passing. Every validation check is grounded in explicit spec text.
No known check is opinion-only. The codebase is internally consistent with the
conformance principle documented in CLAUDE.md and GUIDE.md.

---

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
