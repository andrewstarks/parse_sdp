# Plan

This file is the working plan for `parse_sdp`, a Lua library that parses,
validates, and serializes SDP (Session Description Protocol) files.

## Guiding Principles

- Every feature begins with failing tests.
- Every validation check cites explicit normative specification text: a
  "shall" or "MUST", a "shall not" or "MUST NOT", or a defined value form or
  value set. Silence in the specification is not a reason to reject.
- Each validation tier extends the previous tier and never replaces it. The
  tiers are RFC (Request for Comments) 8866, then SMPTE (Society of Motion
  Picture and Television Engineers) ST 2110, then IPMX (Internet Protocol
  Media Experience). RFC 8866 obsoletes RFC 4566.
- If a file is growing, stop and refactor before continuing. Prefer fewer,
  well-named functions.
- A parse failure reports exactly where the input failed and why.
- `doc:to_sdp()` must produce output that re-parses to an equivalent table.
  This round-trip is a hard invariant.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.1+ (tested on 5.1, 5.2, 5.3, 5.4, 5.5) |
| Parsing | LPEG (Lua Parsing Expression Grammars) |
| JSON | dkjson (pure Lua, LuaRocks) |
| Tests | busted |
| Container | Docker (Lua 5.5 + LuaRocks base image) |

## Test Command

```sh
busted spec/                  # hermetic suite (1277 tests on current main)
busted spec_conformance/      # opt-in suite of pinned AMWA fixtures
```

## Current State

Version 1.5.1 was tagged on 2026-10-15 with 1225 hermetic tests. The current
`main` has 1277 hermetic tests, and all of them pass. Every validation check
is grounded in explicit specification text; no opinion-based checks remain.
The public API (application programming interface) surface is
`parse_sdp/init.lua` (the library) and `bin/parse_sdp` (the CLI,
command-line interface). The grammar tier is in
`parse_sdp/grammar/{base,st2110,ipmx}.lua`. The serializer is in
`parse_sdp/serialize.lua`. The error registry is in `parse_sdp/errors.lua`.

`main` also has unreleased changes since 1.5.1. CHANGELOG.md lists them under
`[Unreleased]`: the browser playground, two restored IPMX checks, rejection
of a session-only SDP at the ST 2110 and IPMX tiers, a `field_path` on
required-parameter findings for streams with no `a=fmtp`, and CRLF line
endings on the example files.

The 1.2 release added CLI capabilities for diagnostics: `parse_sdp validate`,
`parse_sdp diagnose`, the `--all-findings` flag on `validate`, `diagnose`,
and `to_json`, and `parse_sdp checks` (a registry dump). The 1.2 release also
added the README section "Who is this for?" and the README section on error
output.

The 1.2.1 point release fixed two error-output accuracy bugs:

- Grammar-failure errors now include the line, the column, and the source
  line. The deepest-failure tracker, which was already defined in
  `errors.lua` but never connected, now feeds the fallback path in
  `init.lua`. The connected tracker replaces the bare `"SDP parse failed"`
  message for the
  `v=1`, mis-ordered field, unknown addrtype, and missing tail-field cases.
- `c=` invalid-address findings point at the address, not past the end of
  the line. A `Cg(Cp(), "_addr_pos")` capture, stripped after the `Cmt`,
  passes the address-start position to `validate_c_address`.

The 1.3.0 release (2026-05-26) added support for Lua 5.1 and later and the
CI (continuous integration) matrix for Lua 5.1 through 5.4.

## 1.4.0: attribute accessors

Consumer feedback from the lnmos projection layer: the only awkward part of
reading a parsed doc was scanning the ordered `media[i].attributes` array by
name. The library had `params_get` for the inner `a=fmtp` params but nothing
for the outer attribute list, so every consumer wrote its own `find_attr`
scan.

- [x] `sdp.attr_get(block, name)` returns the first decomposed attribute with
  that name on a block (`doc.session` or `doc.media[i]`), or nil.
- [x] `sdp.attrs_get(block, name)` returns all matches in document order, or
  an empty table when there are none. A separate function is justified
  because same-name attributes are common (`rtpmap`, `fmtp`, `ssrc`,
  `rtcp-fb`).
- [x] Both functions are defined once in `grammar/base.lua` beside
  `params_get`, inherited through `extend()`, and re-exported on the public
  module in `init.lua`. They are nil-safe and read-only. They have no
  round-trip or serialization impact, because they are free functions and
  add no metatable surface on blocks.
- [x] Release: tagged `v1.4.0`, uploaded the rockspec, and published to
  LuaRocks (2026-05-31).

## 1.5.0: params_get top-level re-export

A follow-up note from the same consumer (the lnmos `nmos/sdp.lua` layer):
1.4.0 promoted the outer attribute accessors to the public module but left
`params_get` (the inner `a=fmtp` and `a=privacy` lookup) reachable only
through `parse_sdp.grammar.base`. Consumers had to reach into a grammar
internal for the inner lookup. Re-exporting `params_get` gives one public
surface for name lookups.

- [x] `sdp.params_get(params, key)` is re-exported on the public module. The
  `grammar.base` path still works for existing callers.
- [x] The argument-shape difference from `attr_get` (`params_get` takes the
  inner list, for example `fmtp.params`, not the block) is documented at
  the re-export, in the GUIDE API reference, and in a dedicated test.
- [x] Release: tagged `v1.5.0`, uploaded the rockspec, and published to
  LuaRocks (2026-05-31).

## 1.5.1: linear finding positioning

The project was resumed after a break with the impression that LPeg made the
parser slow. Profiling showed otherwise. Module load takes about 6 ms. The
grammar is linear, at about 29 µs per media block, which is about 5 times
the cost of a trivial line splitter. The only super-linear cost was in Lua:
`errors.record` scanned the subject from byte 1 for every finding's line,
column, and source line. At the time, every fixture and example in the
repository was LF-terminated, so every line emitted
`sdp.line.lf-only-line-ending`, and a parse cost O(lines × bytes).

- [x] `errors.line_index(text)` builds the LF-offset index once per parse.
  `record()` caches the index on `ctx` and resolves positions by binary
  search. `pos_to_line_col` and `pos_to_line_text` take the index as an
  optional third argument, so the one-off failure path is unchanged.
- [x] Measured: a 2 KB LF-terminated example went from 2.3 ms to 0.23 ms,
  and a 316 KB synthetic file went from 3.95 s to 32 ms. Clean documents
  are unchanged. There is no API or output change.
- [x] Decision recorded: stay on LPeg. A rewrite in plain Lua would not have
  touched the bottleneck.
- [x] Release: tagged `v1.5.1`, uploaded the rockspec, and published to
  LuaRocks (2026-10-15).

## Web playground: parse_sdp in the browser

The library is small, is pure C plus Lua, and parses a document in well under
a millisecond, so a hosted front end needs no server. The build compiles Lua
5.5, LPeg, dkjson, and `parse_sdp` to WebAssembly and runs the result in the
page. GitHub Pages serves the static files. SDP text never leaves the
browser.

- [x] `web/wasm/bridge.lua` is a JSON (JavaScript Object Notation) façade
  over the library. The `report` request runs every tier with
  `fail_on_first=false`. The `validate` request serializes an edited doc and
  reports on it. The other requests are `to_sdp`, `from_lua`, `checks`, and
  `version`. The bridge is testable natively through `bridge_cli.lua`. The
  contract is in `web/CONTRACT.md`.
- [x] `web/wasm/build.sh` and `bridge.c` form the Emscripten build of pinned
  Lua 5.5.1, LPeg 1.1.0, and dkjson 2.10, with embedded Lua sources and
  ES-module output. `smoke.mjs` asserts that the WebAssembly and native
  responses are identical.
- [x] `web/src/` is the static UI (user interface): input as SDP, JSON, or
  Lua; a tier report with source highlighting; a generic editor over the doc
  table that validates on blur; a policy panel; and downloads. A mock engine
  runs over `web/fixtures/`.
- [x] `.github/workflows/pages.yml` builds the site and deploys it to Pages.
  Pages is enabled on the repository with the Actions build type.
- [x] Documentation: README, GUIDE, CLAUDE.md, and CHANGELOG.

## Next pass: GUIDE.md troubleshooting recipes

A field engineer who sees an unfamiliar `err.id` wants to know what the
error usually means on deployed equipment. The error message says what the
validator found. A troubleshooting note can add why the error usually happens
and what to check next. Keep the section small; do not invent edge cases. Use
real cases from these sources:

- The [SDPoker repository](https://github.com/AMWA-TV/sdpoker). Its test
  fixtures, issues, and pull requests are the canonical corpus of mistakes
  that real senders make.
- The [AMWA nmos-testing repository](https://github.com/AMWA-TV/nmos-testing),
  a similar corpus from JT-NM Tested. AMWA is the Advanced Media Workflow
  Association.
- The 1.1.1 incident: a 5-octet PTP (Precision Time Protocol) grandmaster
  identifier (a citable `err.id`).

The change is a new GUIDE.md section "Troubleshooting" near the end of the
file, after "Serialization" and before "Test Suite Organization". The section
is a small table of the errors most commonly seen in real-world senders,
keyed by `err.id`, with one column for the common cause and one column for
what to check on the device side. Cap the table at 6 to 8 entries; a small
useful table is preferred over an exhaustive one. Cross-link the table to
`parse_sdp checks` and `sdp.checks()`.

No code tests are needed for a documentation-only change. However, every
cited `err.id` must exist in the registry. Add a test in
`spec/library_spec.lua` that asserts every cited `err.id` is in
`sdp.checks()`, so that the documentation cannot go stale silently.

### Future items (lower priority; tracked here, not scheduled)

- An audit-trail export is a compliance-tester workflow: run validation
  against a corpus of vendor SDPs and emit CSV or JSON rows of
  `(file, tier, pass/fail, err.id, err.spec_ref)`. The 1.2 CLI primitives
  are enough to build this externally with a shell and jq. An integrated
  `parse_sdp audit <directory>` subcommand would package it. Defer this
  until users have the 1.2 CLI and the requested ergonomics are clearer.

## Next phase: per-test citation labels in `it` names

(This item predates the diagnostic-CLI work above and is independent of it.
The item is a mechanical pass over the three standards-tied spec files.)

Every `it` block in `spec/grammar_base_spec.lua`,
`spec/grammar_st2110_spec.lua`, and `spec/grammar_ipmx_spec.lua` currently
ties to a published clause, but the citation is in the describe name or in
the parser-side `spec_ref`, not on the test name itself. The next phase puts
the citation on the test name so that:

1. Citations appear in busted output. When a test fails, the specification
   clause that the test was enforcing is on the same line.
2. The citation can be searched from the command line. A single regular
   expression extracts `(file, line, doc, section)` tuples across the suite.
3. Every citation is re-verified against primary specification text before
   it is merged (the Spec Verification Protocol in CLAUDE.md applies).

### Pattern

Suffix bracket at the end of the test name:

```lua
it("<description> [<doc> §<section>]", function()
```

- The document token is one of `RFC NNNN`, `ST 2110-NN`, `ST 2110-NN:YYYY`
  (year-pinned when the section number depends on the revision),
  `TR-10-NN`, or `TR-10-NN-PartN`.
- The section token is `§N`, `§N.M`, or `§N.M.L`.
- Multiple citations are comma-separated, with no "and":
  `[RFC 8866 §5.7, ST 2110-10 §6.5]`.
- No URLs. Document identifiers are the bibliographic reference.

### Workflow (per file, one commit per file)

1. Walk every describe block from top to bottom.
2. For each `it`, locate the parser-side check that it exercises and read
   the `spec_ref` value that the validator emits. That value is the
   authoritative citation.
3. Re-read the cited clause in the on-disk specification. If the wording
   does not unambiguously support the test, **stop and flag the test for
   discussion** before modifying it.
4. Append the bracketed citation to the `it` name.
5. Confirm that `busted spec/` still passes. The test count must not change.
6. Commit.

Coverage target: 100% of `it` blocks in the three standards-tied files.

## Next phase: Lua 5.1 / 5.2 compatibility (opt-in shim)

Today the rockspec declares `lua >= 5.3, < 5.6`. The only thing
binding that floor is `parse_sdp/grammar/addresses.lua` lines 124–198
(`int_to_ipv4`, `ipv4_to_int`, `ipv6_add`), which use `&` / `>>` /
`<<`. Those operators are a parse error on Lua 5.1/5.2, so the file
cannot be loaded. Everything else in the library is portable
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
  themselves, only an isolated `bitops_compat` module).
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
  rockspec output table itself. The env has no globals: `_VERSION`,
  `table`, `pcall`, and `ipairs` are all absent.
- The rockspec schema (`luarocks/type/rockspec.lua`) supports
  `platforms.*` overrides for OS (`unix`, `linux`, `macosx`,
  `windows`, `mingw32`, `cygwin`) but not for Lua version.

The smoke tests are in `/tmp/parse_sdp_envs/` for the duration of
this slice. Net effect: no rockspec-side conditional. We commit to
**Option A (pure-Lua arithmetic in `bitops_compat.lua`)** so there is
nothing to install on 5.1/5.2 in the first place.

### Approach: three-file shim

```text
parse_sdp/grammar/
  bitops.lua            -- dispatcher (~6 lines, parses on any Lua ≥ 5.1)
  bitops_53.lua         -- native `&` / `>>` / `<<`  (5.3+ only; never required on 5.1/5.2)
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
`rshift(a, n)`, `lshift(a, n)`. That is the entire surface
`addresses.lua` needs; there is no `bor`, `bxor`, or `bnot`. `bitops_53.lua`
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

No conditional dependency. No new dependency at all; `bit32` is not
listed. Lua 5.1/5.2 use the pure-Lua backend; Lua 5.3+ use native
operators.

### addresses.lua edits

- Replace `(n >> 24) & 0xff` etc. in `int_to_ipv4` with `bitops.band` /
  `bitops.rshift` calls. Same for `ipv6_add` (the inner `g[i] & 0xffff`
  and `carry = v >> 16`).
- `ipv4_to_int` already uses arithmetic only, so no change.
- Module-top `local bitops = require("parse_sdp.grammar.bitops")`.

### Tests

- **New file** `spec/grammar_bitops_spec.lua` exercises the three
  exported functions against the cases addresses.lua hits:
  `band(0x12345678, 0xff) == 0x78`, `rshift(0x12345678, 24) == 0x12`,
  `lshift(0xab, 8) == 0xab00`, plus an `ipv6_add` carry case
  (e.g. `ipv6_add({0,0,0,0,0,0,0,0xffff}, 1)` returns
  `{0,0,0,0,0,0,1,0}`). The file slots topically, near
  `grammar_addresses_spec.lua`, because bitops is grammar-internal.
  (See [[test-ordering]].)
- **In-place** `spec/grammar_base_spec.lua:1349`:
  `table.unpack(media_block)` → `(table.unpack or unpack)(media_block)`.
  This is the only 5.2+-only call in the spec tree.
- Hermetic count: today 1197. After this work: 1197 + whatever
  bitops cases are added (single-digit). No grammar tests change.

### CI

Today `.github/workflows/test.yml` is a single `docker compose run --rm
test` job pinned to Lua 5.5 (via `Dockerfile`'s `LUA_VERSION=5.5.0`
build-arg). The Lua 5.5 path is the one to keep mirroring local dev.
For the matrix, add a separate job using `leafo/gh-actions-lua@v10`
(or `luarocks/gh-actions-lua@v10`). A gh-actions-lua job is faster than
Docker per version and avoids cross-building Lua 5.1/5.2 in the existing Dockerfile.

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
unchanged; they exercise the same parser code, so there is no value in
running the AMWA conformance fixtures across the matrix.

### Migration & version

- Ships as **1.3.0** (minor: new supported platforms, no API change).
- CHANGELOG.md entry under `[Unreleased]` calling out the supported
  Lua range.
- GUIDE.md "Installation" gains a "Supported Lua versions" line:
  "Lua 5.1 through 5.5. No additional rocks needed on any version.
  Lua 5.3+ uses native bitwise operators; Lua 5.1 and 5.2 use a
  pure-Lua arithmetic implementation."
- README.md tech-stack table row: `Language | Lua 5.1+ (tested on
  5.1–5.5)`.
- CLAUDE.md tech-stack table gets the same edit.

### Risks & open questions

- **LuaJIT (`_VERSION == "Lua 5.1"`).** LuaJIT advertises
  `_VERSION == "Lua 5.1"` so it gets the compat backend. Pure-Lua
  arithmetic works under LuaJIT. Flag for an end-to-end run
  during the matrix-CI slice.
- **Round-trip invariant.** No change: bitops are below the
  parser/serializer interface, and `addresses.lua` IPv6 canonicalization
  is byte-exact regardless of which backend computed the math. The
  bitops spec includes the carry case `ipv6_add({0,...,0xffff}, 1)`
  that addresses.lua depends on.

### Task checklist (execute in order; one PR per major slice)

1. [x] **Verification slice** (no code, no docs change):
   smoke-tested `_VERSION`-conditional dependency eval on a throwaway
   rockspec under `luarocks-5.1` and `luarocks-5.4`. Finding: the
   sandbox has no globals (no `_VERSION`, no `table`), so the
   conditional-dep mechanism is not viable. See "Verification finding"
   above. Resolution: Option A (pure-Lua arithmetic backend).
2. [x] **Shim slice**: added `bitops.lua` / `bitops_53.lua` /
   `bitops_compat.lua` + `spec/grammar_bitops_spec.lua`. Switched
   `addresses.lua` to call the shim. Rockspec still at `lua >= 5.3`.
   Suite grew 1197 → 1208 (+11 bitops cases). Verified passing under
   Docker Lua 5.5 and under hererocks-built Lua 5.1.
3. [x] **Compat slice**: rockspec floor relaxed to `lua >= 5.1`,
   three new modules registered in `build.modules`, `table.unpack`
   fixed via `(table.unpack or unpack)`, `spec/cli_spec.lua`'s
   `run()` helper rewritten to capture exit codes via a subshell
   (the 5.2+ `io.popen():close()` three-value return doesn't exist
   on 5.1). Matrix CI job added using `leafo/gh-actions-lua@v10`
   across 5.1 / 5.2 / 5.3 / 5.4. Version bumped to 1.3.0. CHANGELOG
   / GUIDE / README / CLAUDE.md updated. All 1208 tests pass locally
   under 5.1, 5.2, 5.3, 5.4, and 5.5.
4. [x] **Release slice**: tagged `v1.3.0`, uploaded the rockspec, and
   published (2026-05-26; see the 1.3.0 entry in CHANGELOG.md).

## Known Deferred Items

These items were evaluated and set aside. Do not re-raise them in routine
development unless new specification evidence appears.

- **The reverse direction of the ST 2110-20:2022 section 7.2 SSN clause is
  not enforced.** The clause says "default to SSN=:2017 unless :2022-only
  values are used". Its reverse direction ("Senders implementing this
  standard shall signal the value ST2110-20:2017 unless [exception]"),
  strictly enforced, would invalidate `SSN=ST2110-20:2022` whenever neither
  `TCS=ST2115LOGS3` nor `colorimetry=ALPHA` is present. About 115 existing
  test fixtures, and most real-world senders that implement the :2022
  revision, signal :2022 unconditionally. The forward direction, which is
  what JT-NM Tested requested, is enforced. The reverse direction is left to
  a future audit if SMPTE or AMWA clarifies the intent.
- **The sampling × colorimetry × TCS × RANGE cross-table is not enforced.**
  The specification lists the value sets independently and contains no
  explicit "shall not" for any combination of valid individual values.
- **ST 2110-31 AES3 `fmtp` has no separate path.** AM824 audio currently
  uses the ST 2110-30 path (encoding name, channel order, and packet-fit
  checks). Revisit this if new AES3-specific normative text appears.
- **The ST 2110-21 section 7.1 CMAX upper bound is not enforced.** The
  type-specific formula `MAX(4, INT(NPACKETS/(43200 × R_ACTIVE × T_FRAME)))`,
  and the Type W variant with `16` and `21600`, is an upper bound on `CINST`
  under the Network Compatibility Model in section 6.6.1. It is not a lower
  bound on the SDP `CMAX` value. Enforcing the upper bound requires NPACKETS,
  MAXUDP, width, height, depth, sampling, and frame-rate context, so the
  check was not added.
- **`TROFF=0` is rejected.** ST 2110-21 section 6.2 explicitly permits
  TROFFSET to be zero, and requires TROFFSET to be signaled when it differs
  from TRODEFAULT. Section 8.2 says the SDP value is "expressed as a positive
  integer." The parser follows the section 8.2 value-form SHALL and rejects
  `TROFF=0`. Revisit this only if SMPTE issues an erratum.
- **`TSDELAY=0` is rejected.** ST 2110-10:2022 section 8.7 says "decimal
  positive integer". Annex B (informative) shows an example with
  `TSDELAY=0`. The section 8.7 SHALL governs, so the parser rejects
  `TSDELAY=0`.
- **The `m=` media type set is not enforced strictly.** RFC 8866 section
  5.14 defines five values (`audio`, `video`, `text`, `application`,
  `message`). Section 8.2.2 says `control` and `data` are SHOULD NOT, not
  MUST NOT, for backward compatibility with RFC 3840 SIP. The restriction is
  not enforced, per the strictness principle. The restriction is a candidate
  for a future warning.
- **The `o=` unicast address may be a domain name.** The RFC 4566 section
  5.7 ABNF allows a fully qualified domain name in the origin address. No ST
  2110 clause explicitly forbids one there.
