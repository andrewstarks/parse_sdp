# parse_sdp web playground: developer notes

The playground is a static, single-page front end for
[`parse_sdp`](../README.md). A user pastes or drops a Session Description
Protocol (SDP) file, reads the compliance report for the RFC 8866,
SMPTE ST 2110, and IPMX tiers, edits the parsed document table, and
downloads the serialized SDP or JSON. Everything runs in the browser, and
nothing is uploaded. The user manual is [MANUAL.md](MANUAL.md). This file
describes how the code is organized and how to build and test it.

## Layers

| Layer | Location | Role |
| --- | --- | --- |
| Lua library | `../parse_sdp/` | The parser, validator, and serializer. |
| Bridge | `wasm/bridge.lua`, `wasm/bridge.c` | Converts a JSON request into a JSON response over the library. Compiled with Emscripten. [`CONTRACT.md`](CONTRACT.md) documents the request and response shapes. |
| Engine | `src/engine.js`, plus `parse_sdp.js` and `parse_sdp.wasm` produced by `wasm/build.sh` | `createEngine()` returns `{ request(obj), version }`. |
| Mock engine | `src/engine_mock.js` | Has the same interface as the engine and answers from recorded fixtures. The app uses the mock when the WebAssembly module is absent or fails to load, or when the page URL has `?mock=1`. |
| User interface | `src/*.js`, `src/index.html`, `src/styles.css` | Plain HTML, CSS, and ES modules. No bundler, no framework, no CDN. |
| Build and deploy | `wasm/build.sh`, `../.github/workflows/pages.yml` | The script builds the WebAssembly module, copies `src/` into `dist/`, and the workflow publishes `dist/` to GitHub Pages. |

## User interface modules

The following modules contain logic only. They do not touch the DOM, and
each one has unit tests under `test/`.

- `format.js` detects the input format and provides line helpers. Text
  that starts with `v=` is SDP. Text that starts with `{` or `[` is JSON,
  with a Lua fallback when `JSON.parse` fails. Text that starts with
  `return` is Lua. The module also splits lines and normalizes line
  endings to CRLF.
- `docpath.js` converts `field_path` strings to positions in the
  document and back. The module parses both the serializer's plain paths
  (`media[0].attributes[2].encoding`) and the grammar's selector paths
  (`media[0].attributes[fmtp:pt=96]`, `session.attributes[group][1]`),
  and provides `getAt` and `setAt`.
- `findings.js` collapses the three per-tier finding lists into one
  de-duplicated table. Two findings are the same when they have the same
  `id`, `line`, `col`, and `field_path`. Each row is tagged with the
  tiers that reported it. The module also computes tier summaries and
  applies filters.
- `diff.js` is a longest-common-subsequence line diff for the output
  view.
- `coerce.js` converts between input text and document values without
  changing the type. A number field stays a number. An emptied field
  becomes absent.
- `line_map.js` computes which document field each SDP line produced,
  following the parser's fill order. A line-anchored finding can then be
  shown on the editor field as well as in the source view.
- `field_findings.js` maps report findings onto editor fields. The module
  resolves each `field_path`; a finding that names a missing field is
  attached to the nearest existing ancestor and flagged as missing. Error
  and warning counts are aggregated up every ancestor for the card
  badges.
- `checks.js` contains the policy helpers: grouping the registry by id
  prefix, sanitizing stored overrides against the live registry, looking
  up the effective severity, and counting silenced checks.
- `lua_literal.js` reads a Lua table constructor (used by the mock; the
  real engine runs `from_lua` in Lua) and provides `toLuaLiteral(doc)`,
  the writer for the "Lua table literal" output format.
- `examples.js` turns the build's `examples/index.json` manifest into
  labeled option groups for the examples dropdown. Without a build, the
  module falls back to the three bundled fixtures.
- `url_source.js` loads an SDP file from a URL. The module validates
  the address, sends an `http:` address from an `https:` page as a
  local-network request (`targetAddressSpace: "local"`, which Chrome and
  Edge 142 and later allow after a permission prompt), fetches the
  response as bytes with a 10-second timeout (60 seconds for a
  local-network request) and a 1 MB limit, decodes the bytes without changing the line endings
  or removing a byte order mark, and maps each failure to the message
  that the page shows. The module also derives the download name from
  the URL path and builds the `?url=` share link. The fetch function is
  a parameter, so the tests run under node with no network.
- `mock_serialize.js` converts a document to SDP text in the same way as
  `parse_sdp/serialize.lua`. The mock engine is the only user.

The following modules touch the DOM.

- `app.js` starts the engine, stores the only mutable state, and
  connects the other modules.
- `input.js` manages the paste area, the drop zone, the file picker, the
  "From URL" box and its "Copy link" button, and the examples dropdown.
  The module keeps `?url=` in the page address only while the input is
  the text fetched from that URL.
- `nav.js` manages the sticky bar's section navigation: a hamburger menu
  on narrow screens, the `--bar-h` custom property for scroll offsets,
  and the current-section marking through an `IntersectionObserver`.
- `report.js` renders the tier cards, the de-duplicated and grouped
  findings list with its filters, a per-row severity control for the
  check behind each finding, the "N checks silenced" notice, and the
  numbered source view.
- `editor.js` is a generic structured editor over the document table.
  Findings are shown in place: a summary block first (with counts,
  collapsible, with the collapsed state persisted), then card badges,
  field highlights, and stacked expandable disclosures with a severity
  control and a reserved action slot. After each validation the findings
  are re-applied without re-rendering the fields.
- `severity_control.js` builds the per-finding severity `<select>` that
  report rows and editor disclosures share.
- `output.js` renders the document as SDP, JSON, or a Lua table literal.
  The module owns the sticky bar's format selector, Download button, and
  Copy button, and the read-only Output section with the same selector,
  a Copy button, and the rendered text. Diff markers appear in the SDP
  view only.
- `policy.js` is the single severity-override store, persisted in
  `localStorage`. The store has two views: the popout panel attached to
  the report toolbar (filter box, grouped list with a select per check,
  override count, reset button) and the row controls that `report.js`
  renders. Every change re-runs the analysis.
- `dom.js` is the element builder. No module uses `innerHTML`.

## Running the playground locally

With the WebAssembly engine, the build needs Emscripten, Lua, and
LuaRocks. Lua and LuaRocks are used by the build's native smoke test.

```sh
bash web/wasm/build.sh          # writes web/dist/
python3 -m http.server --directory web/dist 8000
open http://localhost:8000/
```

Without a build, the page runs against the recorded fixtures:

```sh
python3 -m http.server --directory web/src 8000
open "http://localhost:8000/?mock=1"
```

The `?mock=1` parameter is optional in the second case. When no
`parse_sdp.js` file exists next to `engine.js`, the import fails and the
app falls back to the mock on its own. The status line in the header
names the active engine.

GitHub Pages lets a browser cache each file for 10 minutes. So that a
normal reload after a deploy loads the new release, `build.sh` adds
`?v=<version>` to the URLs in `web/dist/`: the script and style URLs in
`index.html`, every relative module import, and (through `CACHE_KEY` in
`engine.js`) the URL of `parse_sdp.wasm`. `web/src/` has no version
query.

To test the URL loader locally, serve an SDP file from a server that
sends CORS headers, then load its address in the "From URL" box:

```sh
npx http-server examples --cors -p 8081
# From URL: http://localhost:8081/st2110/valid/01_simple_video.sdp
```

## Manual screenshots

The images in `manual/img/` are the screenshots in [MANUAL.md](MANUAL.md).
`manual/capture.mjs` takes all of them again. The script needs Google
Chrome and the `playwright-core` package, and it reads the page from
`dist/`, so build first:

```sh
web/wasm/build.sh
cd web && npm install --no-save playwright-core && node manual/capture.mjs
```

The script serves `dist/` at the deployed address,
`https://andrewstarks.github.io/parse_sdp/`, so the page runs over HTTPS
and shows the same messages as the deployed page. Request routes answer
the two device addresses in the URL screenshots, so the script sends
nothing to the network. Every image is taken in the light color scheme,
in a window 1200 pixels wide, at 2x pixel density, and is cropped to the
part of the page that the manual text describes. The browser's own
interface, such as the local network access prompt and the native list
of a `<select>`, is not part of the page and is not captured. Take the
screenshots again after a change to the user interface, and check the
alt text in MANUAL.md against the new images.

## Tests

```sh
cd web && node --test test/        # Node 20 or later; no dependencies
```

`test/fixtures_sync.test.js` checks that the copies of `fixtures/` under
`src/mock/` and `src/examples/` are identical to the originals. The
copies ship with the site so that the mock and the bundled examples work
from `dist/`. After re-recording fixtures, copy them again:

```sh
cp web/fixtures/report_*.json web/fixtures/checks.json web/fixtures/version.json web/src/mock/
cp web/fixtures/*.sdp web/src/examples/
```

## What the mock engine covers

- `version` and `checks` return the recorded responses.
- `report` returns the recorded response for the three example inputs.
  The match ignores the line-ending style. For any other text, the mock
  synthesizes a report from the pathological fixture and re-anchors the
  findings to the input's line count and line endings. Policy `off` and
  severity overrides are applied.
- `validate` and `to_sdp` use a JavaScript re-implementation of the
  serializer's structure: field order, CRLF, and a `serialize_error` with
  the same `field_path` form when a required field is missing. The tiers
  come from the fixture whose session name matches the document.
- `from_lua` uses the Lua table-literal reader in `lua_literal.js`.

The mock does not validate anything. Findings for unknown inputs or
edited documents are illustrative only, and the header says so.
