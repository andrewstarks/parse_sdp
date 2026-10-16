# parse_sdp web playground

A static, single-page front end for [`parse_sdp`](../README.md): paste or
drop an SDP file, see the RFC 8866 → SMPTE ST 2110 → IPMX compliance
report, edit the parsed document table, and download the re-serialized
SDP or JSON. Everything runs in the browser; nothing is uploaded.

## How the pieces fit

| Layer | Where | Role |
| --- | --- | --- |
| Lua library | `../parse_sdp/` | The parser / validator / serializer. |
| Bridge | `wasm/bridge.lua`, `wasm/bridge.c` | JSON request → JSON response over the library, compiled with Emscripten. [`CONTRACT.md`](CONTRACT.md) is the API. |
| Engine | `src/engine.js` (+ `parse_sdp.js` / `parse_sdp.wasm` produced by `wasm/build.sh`) | `createEngine()` → `{ request(obj), version }`. |
| Mock engine | `src/engine_mock.js` | Same interface, answers from recorded fixtures. Used when the WASM module is absent or fails to load, or when the page URL has `?mock=1`. |
| UI | `src/*.js`, `src/index.html`, `src/styles.css` | Plain HTML + CSS + ES modules. No bundler, no framework, no CDN. |
| Build / deploy | `wasm/build.sh`, `../.github/workflows/pages.yml` | Builds the WASM, copies `src/` into `dist/`, publishes to GitHub Pages. |

### UI modules

Pure logic (no DOM, unit-tested under `test/`):

- `format.js` — input format detection (`v=` → SDP, `{`/`[` → JSON with a Lua fallback when `JSON.parse` fails, `return` → Lua), line splitting, CRLF normalisation.
- `docpath.js` — `field_path` strings ↔ positions in the doc: parses both the serializer's plain paths (`media[0].attributes[2].encoding`) and the grammar's selector paths (`media[0].attributes[fmtp:pt=96]`, `session.attributes[group][1]`), plus `getAt` / `setAt`.
- `findings.js` — collapses the three per-tier finding lists into one de-duplicated table (same `id` + `line` + `col` + `field_path`) tagged with the tiers that raised each finding; tier summaries; filtering.
- `diff.js` — LCS line diff for the output view.
- `coerce.js` — type-preserving coercion between input text and doc values (a number field stays a number; an emptied field becomes absent).
- `checks.js` — policy helpers: grouping the registry by id prefix, sanitising stored overrides against the live registry.
- `lua_literal.js` — Lua table-constructor reader (used by the mock; the real engine runs `from_lua` in Lua) and `toLuaLiteral(doc)`, the writer behind the "Lua table literal" output format.
- `examples.js` — turns the build's `examples/index.json` manifest into labelled option groups for the examples dropdown (falls back to the three bundled fixtures without a build).
- `mock_serialize.js` — document → SDP text, mirroring `parse_sdp/serialize.lua`; mock only.

Thin DOM modules:

- `app.js` — boots the engine, owns the state, wires everything.
- `input.js` — paste area, drop zone, file picker, examples dropdown.
- `nav.js` — sticky-bar section navigation: hamburger on narrow screens, `--bar-h` for scroll offsets, current-section marking via IntersectionObserver.
- `report.js` — tier cards, findings list with filters, numbered source view.
- `editor.js` — generic structured editor over the document table.
- `output.js` — the document as SDP / JSON / Lua table literal: the sticky bar's format selector + Download + Copy, and the read-only Output section (same selector, Copy, rendered text; diff markers in the SDP view only).
- `policy.js` — per-check severity overrides, persisted in `localStorage`.
- `dom.js` — element builder (no `innerHTML` anywhere).

## Running locally

With the WebAssembly engine (needs Emscripten, Lua and LuaRocks for the
build's native smoke test):

```sh
bash web/wasm/build.sh          # writes web/dist/
python3 -m http.server --directory web/dist 8000
open http://localhost:8000/
```

Without a build, against the recorded fixtures:

```sh
python3 -m http.server --directory web/src 8000
open "http://localhost:8000/?mock=1"
```

(`?mock=1` is optional there: with no `parse_sdp.js` next to `engine.js`
the import fails and the app falls back to the mock on its own. The
status line in the header says which engine is active.)

## Tests

```sh
cd web && node --test test/        # Node 20+; no dependencies
```

`test/fixtures_sync.test.js` checks that the copies of `fixtures/` under
`src/mock/` and `src/examples/` (shipped with the site so the mock and the
example buttons work from `dist/`) are identical to the originals. After
re-recording fixtures, copy them again:

```sh
cp web/fixtures/report_*.json web/fixtures/checks.json web/fixtures/version.json web/src/mock/
cp web/fixtures/*.sdp web/src/examples/
```

## What the mock covers

- `version`, `checks`: the recorded responses.
- `report`: the recorded response for the three example inputs (matched
  ignoring line-ending style); for any other text a report synthesised
  from the pathological fixture, re-anchored to the input's line count
  and line endings. Policy `off` / severity overrides are applied.
- `validate` / `to_sdp`: a JS re-implementation of the serializer's
  structure (field order, CRLF, missing-required-field → `serialize_error`
  with the same `field_path` form), with tiers borrowed from the fixture
  whose session name matches.
- `from_lua`: a Lua table-literal reader.

The mock does not validate anything; findings for unknown inputs or edited
documents are illustrative only, and the header says so.
