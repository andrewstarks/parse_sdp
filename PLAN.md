# Plan

## Guiding Principles

- **Test first.** Every feature begins with failing tests.
- **Strict by spec.** Every validation check cites explicit normative spec
  text — a "shall" / "MUST", a "shall not" / "MUST NOT", or a defined value
  form / value set. Spec silence is not a reason to reject.
- **Layered.** Each tier (RFC 8866 → ST 2110 → IPMX) extends the previous;
  it never replaces it. RFC 8866 obsoletes RFC 4566.
- **Tight.** If a file is growing, stop and refactor before continuing.
  Prefer fewer, well-named things.
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
busted spec/                  # hermetic suite (1192 tests)
busted spec_conformance/      # opt-in pinned AMWA fixtures
```

## Current State

1.2.1 shipped on 2026-05-22. 1197 hermetic tests passing. Every
validation check is grounded in explicit spec text; no opinion-based
checks remain. Public API surface is `parse_sdp/init.lua` (library) +
`bin/parse_sdp` (CLI). Grammar tier under
`parse_sdp/grammar/{base,st2110,ipmx}.lua`; serializer under
`parse_sdp/serialize.lua`; registry under `parse_sdp/errors.lua`.

The 1.2 release added five diagnostic-facing CLI capabilities:
`parse_sdp validate`, `parse_sdp diagnose`, the `--all-findings` flag
on `validate` / `diagnose` / `to_json`, `parse_sdp checks` (registry
dump), plus README "Who is this for?" + error-output stanza.

The 1.2.1 point release fixed two error-output accuracy bugs:

- Grammar-failure errors now carry line / col / source-line — the
  deepest-failure tracker (already defined in `errors.lua`, never
  wired) feeds `init.lua`'s fallback path. Replaces the bare
  `"SDP parse failed"` for `v=1`, mis-ordered fields, unknown
  addrtype, missing tail-field cases.
- `c=` invalid-address findings point at the address, not past EOL —
  a `Cg(Cp(), "_addr_pos")` capture (stripped after the Cmt) ferries
  the address-start position to `validate_c_address`.

## Next pass — GUIDE.md Troubleshooting recipes

A field engineer with an unfamiliar `err.id` wants "what does this
usually mean in the wild?" The error message says *what* the validator
found; a troubleshooting note can add *why this usually happens* and
*what to check next*. **Keep this tight** — don't invent edge cases.
Use real cases sourced from:

- The [SDPoker repository](https://github.com/AMWA-TV/sdpoker) — its
  test fixtures + issues + PRs are the canonical "things real senders
  get wrong" corpus.
- The [AMWA nmos-testing repo](https://github.com/AMWA-TV/nmos-testing) —
  similar corpus from JT-NM Tested.
- The 1.1.1 incident: 5-octet PTP GMID (citable `err.id`).

**What changes.** New GUIDE.md section "Troubleshooting" near the end
(after Serialization, before Test Suite Organization). Small table of
*the most commonly seen errors in real-world senders*, keyed by
`err.id`, with columns for "common cause" and "what to check on the
device side." Cap at 6–8 entries — better tight and useful than
exhaustive. Cross-link to `parse_sdp checks` and `sdp.checks()`.

**Tests.** N/A (doc-only). But every cited `err.id` should exist in
the registry — add a `spec/library_spec.lua` test asserting that every
cited `err.id` is in `sdp.checks()` so the documentation can't go
stale silently.

### Future (lower priority — track here, don't schedule yet)

- **Audit-trail export.** A compliance-tester workflow: run validation
  against a corpus of vendor SDPs and emit CSV / JSON of `(file, tier,
  pass/fail, err.id, err.spec_ref)`. The 1.2 CLI primitives are enough
  to build this externally with shell + jq; an integrated
  `parse_sdp audit <directory>` subcommand would package it. Defer
  until the 1.2 CLI work is in users' hands and the actual ergonomics
  ask is clearer.

## Next phase: per-test citation labels in `it` names

(Pre-existing item — orthogonal to the diagnostic-CLI work above.
Mechanical pass over the three standards-tied spec files.)

Every `it` block in `spec/grammar_base_spec.lua`,
`spec/grammar_st2110_spec.lua`, and `spec/grammar_ipmx_spec.lua`
currently ties to a published clause, but the citation lives in the
describe name or in the parser-side `spec_ref` — not on the test name
itself. The next phase puts it on the test name so:

1. Citations show up in busted output — when a test fails the spec
   clause it was enforcing is on the same line.
2. The cite is grep-able from the command line — a single regex
   extracts `(file, line, doc, section)` tuples across the suite.
3. Every cite is re-verified against primary spec text before landing
   (Spec Verification Protocol from CLAUDE.md applies).

### Pattern

Suffix bracket at the end of the test name:

```lua
it("<description> [<doc> §<section>]", function()
```

- Document token: `RFC NNNN`, `ST 2110-NN`, `ST 2110-NN:YYYY`
  (year-pinned when the section number depends on the revision),
  `TR-10-NN`, `TR-10-NN-PartN`.
- Section token: `§N`, `§N.M`, `§N.M.L`.
- Multiple cites comma-separated, no "and":
  `[RFC 8866 §5.7, ST 2110-10 §6.5]`.
- No URLs — document IDs are the bibliographic anchor.

### Workflow (per file, one commit per file)

1. Walk every describe top to bottom.
2. For each `it`, locate the parser-side check it exercises and read
   the `spec_ref` value the validator emits — that is the authoritative
   citation.
3. Re-read the cited clause in the on-disk spec. If the wording does
   not unambiguously support the test, **stop and flag for discussion**
   before modifying.
4. Append the bracketed citation to the `it` name.
5. Confirm `busted spec/` still passes. Test count must not change.
6. Commit.

Coverage target: 100% of `it` blocks in the three standards-tied files.

## Next phase — Lua 5.1 / 5.2 compatibility (opt-in shim)

Today the rockspec declares `lua >= 5.3, < 5.6`. The only thing
binding that floor is `parse_sdp/grammar/addresses.lua` lines 124–198
(`int_to_ipv4`, `ipv4_to_int`, `ipv6_add`), which use `&` / `>>` /
`<<`. Those operators are a parse error on Lua 5.1/5.2 — the file
cannot even be loaded. Everything else in the library is portable
(no `goto`, no `<const>`/`<close>`, no `//` integer division, no
`string.pack`/`unpack`, no `\u{}`/`\z` escapes, no `bit32.*`, no
`_ENV`).

The fix is to isolate the bitwise code into a tiny dispatcher module
so the 5.3+ syntax never reaches a 5.1/5.2 parser, and provide a
pure-Lua arithmetic backend for the 5.1/5.2 path so there is no
extra rock to install.

### Goal & non-goals

- **Goal.** Ship `parse_sdp` on Lua 5.1, 5.2, 5.3, 5.4, 5.5 with no
  behavioral difference visible to library callers and no compromise
  to the 5.3+ code path (no global compat shim, no compat53 import,
  no arithmetic rewrites of the `addresses.lua` bitwise ops
  themselves — only an isolated `bitops_compat` module).
- **Non-goals.** LuaJIT-specific work beyond what falls out for free.
  Backporting Lua 5.4 stdlib features (none are used). Compat shims
  for unrelated 5.3+ syntax (none exists outside addresses.lua).

### Verification finding (2026-05-26)

The original plan called for a `_VERSION`-conditional `dependencies`
table that would pull in the `bit32` rock only on Lua 5.1. **That
mechanism is not available in modern LuaRocks.** Confirmed against
LuaRocks 3.8.0 under hererocks-built Lua 5.1 and Lua 5.4 envs:

- Rockspecs are loaded via `persist.load_into_table` in
  `luarocks/core/persist.lua`, which sets a sandbox env equal to the
  rockspec output table itself. The env has no globals — `_VERSION`,
  `table`, `pcall`, `ipairs` are all absent.
- The rockspec schema (`luarocks/type/rockspec.lua`) supports
  `platforms.*` overrides for OS (`unix`, `linux`, `macosx`,
  `windows`, `mingw32`, `cygwin`) but not for Lua version.

The smoke tests live in `/tmp/parse_sdp_envs/` for the duration of
this slice. Net effect: no rockspec-side conditional. We commit to
**Option A — pure-Lua arithmetic in `bitops_compat.lua`** so there is
nothing to install on 5.1/5.2 in the first place.

### Approach — three-file shim

```text
parse_sdp/grammar/
  bitops.lua            -- dispatcher (~6 lines, parses on any Lua ≥ 5.1)
  bitops_53.lua         -- native `&` / `>>` / `<<`  (5.3+ only — never required on 5.1/5.2)
  bitops_compat.lua     -- pure-Lua arithmetic       (5.1/5.2 only; no extra rock)
  addresses.lua         -- calls bitops.band / bitops.rshift / bitops.lshift; no `&` or `>>` in source
```

`bitops.lua` dispatches by `_VERSION`:

```lua
if _VERSION == "Lua 5.1" or _VERSION == "Lua 5.2" then
  return require("parse_sdp.grammar.bitops_compat")
end
return require("parse_sdp.grammar.bitops_53")
```

Each backend exports the same three functions: `band(a, b)`,
`rshift(a, n)`, `lshift(a, n)`. That's the entire surface
`addresses.lua` needs — no `bor`, `bxor`, `bnot`. `bitops_53.lua`
is shipped to all installs but only `require`'d on 5.3+, so its
`&` / `>>` syntax is invisible to a 5.1/5.2 parser.

`bitops_compat.lua` implements the three operations in pure Lua
arithmetic. The operands at our call sites are bounded (32-bit IPv4
ints and 16-bit IPv6 groups), well within Lua 5.1's double-precision
mantissa, so a straight arithmetic decomposition is correct and
cheap:

```lua
local function band(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    local ax, bx = a % 2, b % 2
    if ax == 1 and bx == 1 then r = r + p end
    a, b, p = (a - ax) / 2, (b - bx) / 2, p * 2
  end
  return r
end
local function rshift(a, n) return math.floor(a / 2 ^ n) end
local function lshift(a, n) return a * 2 ^ n end
```

### Rockspec changes

Relax: `"lua >= 5.1, < 5.6"`. Add the three new modules to
`build.modules`:

```lua
["parse_sdp.grammar.bitops"]        = "parse_sdp/grammar/bitops.lua",
["parse_sdp.grammar.bitops_53"]     = "parse_sdp/grammar/bitops_53.lua",
["parse_sdp.grammar.bitops_compat"] = "parse_sdp/grammar/bitops_compat.lua",
```

No conditional dependency. No new dep at all — `bit32` is not
listed. Lua 5.1/5.2 use the pure-Lua backend; Lua 5.3+ use native
operators.

### addresses.lua edits

- Replace `(n >> 24) & 0xff` etc. in `int_to_ipv4` with `bitops.band` /
  `bitops.rshift` calls. Same for `ipv6_add` (the inner `g[i] & 0xffff`
  and `carry = v >> 16`).
- `ipv4_to_int` already uses arithmetic only — no change.
- Module-top `local bitops = require("parse_sdp.grammar.bitops")`.

### Tests

- **New file** `spec/grammar_bitops_spec.lua` — exercises the three
  exported functions against the cases addresses.lua actually hits:
  `band(0x12345678, 0xff) == 0x78`, `rshift(0x12345678, 24) == 0x12`,
  `lshift(0xab, 8) == 0xab00`, plus an `ipv6_add` carry case
  (e.g. `ipv6_add({0,0,0,0,0,0,0,0xffff}, 1)` returns
  `{0,0,0,0,0,0,1,0}`). Slots topically — bitops is grammar-internal,
  near `grammar_addresses_spec.lua`. (See [[test-ordering]].)
- **In-place** `spec/grammar_base_spec.lua:1349`:
  `table.unpack(media_block)` → `(table.unpack or unpack)(media_block)`.
  This is the only 5.2+-only call in the spec tree.
- Hermetic count: today 1197. After this work: 1197 + whatever
  bitops cases land (single-digit). No grammar tests change.

### CI

Today `.github/workflows/test.yml` is a single `docker compose run --rm
test` job pinned to Lua 5.5 (via `Dockerfile`'s `LUA_VERSION=5.5.0`
build-arg). The Lua 5.5 path is the one to keep mirroring local dev.
For the matrix, add a separate job using `leafo/gh-actions-lua@v10`
(or `luarocks/gh-actions-lua@v10`) — faster than Docker per-version
and avoids cross-building Lua 5.1/5.2 in the existing Dockerfile.

```yaml
matrix-test:
  strategy:
    matrix:
      lua: ["5.1", "5.2", "5.3", "5.4", "5.5"]
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: leafo/gh-actions-lua@v10
      with: { luaVersion: ${{ matrix.lua }} }
    - uses: leafo/gh-actions-luarocks@v4
    - run: luarocks install --deps-only ./parse_sdp-*.rockspec
    - run: luarocks install busted
    - run: busted spec/
```

Keep the existing `test` (Lua 5.5 via Docker) and `conformance` jobs
unchanged — they exercise the same parser code, no value in running
the AMWA conformance fixtures across the matrix.

### Migration & version

- Ships as **1.3.0** (minor: new supported platforms, no API change).
- CHANGELOG.md entry under `[Unreleased]` calling out the supported
  Lua range.
- GUIDE.md "Installation" gains a "Supported Lua versions" line:
  "Lua 5.1 through 5.5. No additional rocks needed on any version —
  Lua 5.3+ uses native bitwise operators; Lua 5.1 and 5.2 use a
  pure-Lua arithmetic implementation."
- README.md tech-stack table row: `Language | Lua 5.1+ (tested on
  5.1–5.5)`.
- CLAUDE.md tech-stack table gets the same edit.

### Risks & open questions

- **LuaJIT (`_VERSION == "Lua 5.1"`).** LuaJIT advertises
  `_VERSION == "Lua 5.1"` so it gets the compat backend. Pure-Lua
  arithmetic works fine under LuaJIT — flag for an end-to-end run
  during the matrix-CI slice.
- **Round-trip invariant.** No change — bitops live below the
  parser/serializer interface, and `addresses.lua` IPv6 canonicalization
  is byte-exact regardless of which backend computed the math. The
  bitops spec includes the carry case `ipv6_add({0,...,0xffff}, 1)`
  that addresses.lua actually depends on.

### Task checklist (execute in order; one PR per major slice)

1. [x] **Verification slice** (no code, no docs change):
   smoke-tested `_VERSION`-conditional dependency eval on a throwaway
   rockspec under `luarocks-5.1` and `luarocks-5.4`. Finding: the
   sandbox has no globals (no `_VERSION`, no `table`), so the
   conditional-dep mechanism is not viable. See "Verification finding"
   above. Resolution: Option A (pure-Lua arithmetic backend).
2. [ ] **Shim slice**: add `bitops.lua` / `bitops_53.lua` /
   `bitops_compat.lua` + `spec/grammar_bitops_spec.lua`. Switch
   `addresses.lua` to call the shim. Keep rockspec at `lua >= 5.3`
   for this PR — pure refactor, suite count grows by the bitops cases.
3. [ ] **Compat slice**: relax rockspec to `lua >= 5.1`, register the
   three new modules in `build.modules`, fix `table.unpack` in the
   one spec file, add the matrix CI job. Bump version to 1.3.0.
   Update CHANGELOG / GUIDE / README / CLAUDE per Migration & version
   above.
4. [ ] **Release slice**: tag `v1.3.0`, upload rockspec, publish.

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in
routine development unless new spec evidence emerges.

- **ST 2110-20:2022 §7.2 "default to SSN=:2017 unless :2022-only values
  are used"** — the §7.2 SSN clause has a reverse direction ("Senders
  implementing this standard shall signal the value ST2110-20:2017 unless
  [exception]") that, strictly enforced, would invalidate
  `SSN=ST2110-20:2022` whenever neither `TCS=ST2115LOGS3` nor
  `colorimetry=ALPHA` is present. ~115 existing test fixtures and most
  real-world :2022-implementing senders signal :2022 unconditionally. The
  forward direction (the JT-NM Tested ask) is enforced; the reverse is
  left to a future audit if SMPTE or AMWA clarifies intent.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists
  value sets independently and contains no explicit "shall not" for any
  combination of valid individual values.
- **ST 2110-31 AES3 fmtp** — AM824 audio currently uses the ST 2110-30
  path (encoding name, channel-order, packet-fit checks). Revisit if new
  AES3-specific normative text emerges.
- **ST 2110-21 §7.1 CMAX upper bound** — the type-specific formula
  `MAX(4, INT(NPACKETS/(43200 × R_ACTIVE × T_FRAME)))` (and the Type W
  variant with `16` and `21600`) is an upper bound on `CINST` per the
  Network Compatibility Model in §6.6.1, not a lower bound on the SDP
  `CMAX` value. Enforcing the upper bound requires NPACKETS / MAXUDP /
  width × height × depth × sampling × frame-rate context; not added.
- **ST 2110-21 §6.2 vs §8.2 TROFF zero handling** — §6.2 explicitly
  permits TROFFSET to be zero (and requires it be signaled when it
  differs from TRODEFAULT); §8.2 says the SDP value is "expressed as a
  positive integer." The parser follows the §8.2 value-form SHALL and
  rejects `TROFF=0`. Revisit only if SMPTE issues an erratum.
- **ST 2110-10:2022 §8.7 vs Annex B TSDELAY zero** — §8.7 says "decimal
  positive integer"; Annex B (Informative) example shows `TSDELAY=0`. The
  §8.7 SHALL governs; parser rejects `TSDELAY=0`.
- **m= media type registry strictness (RFC 8866 §5.14 / §8.2.2)** — §5.14
  defines the five values (`audio`, `video`, `text`, `application`,
  `message`); §8.2.2 says `control` and `data` are SHOULD NOT, not MUST
  NOT, grounded in RFC 3840 SIP backward-compat. Not enforced per the
  strictness principle. Future-warning candidate.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF
  allows FQDNs in the origin address; no ST 2110 clause explicitly forbids
  them there.
