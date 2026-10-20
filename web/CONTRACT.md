# parse_sdp web bridge contract

The playground runs `parse_sdp`, the Session Description Protocol (SDP)
parser, entirely in the browser. Lua, LPeg, `parse_sdp`, and dkjson are
compiled to WebAssembly with Emscripten. There is no backend.
`web/wasm/build.sh` pins the versions: Lua 5.5.1, LPeg 1.1.0, and dkjson
2.10. SDP text uses CRLF (carriage return and line feed) line endings.

## Layers

| Layer | File | Role |
| --- | --- | --- |
| Lua bridge | `web/wasm/bridge.lua` | Converts a JSON request into a JSON response over the library. The bridge is pure Lua and runs natively with `lua web/wasm/bridge_cli.lua < req.json` from the repository root. |
| C shim | `web/wasm/bridge.c` | Creates one `lua_State`, preloads LPeg, loads `bridge.lua` from the embedded file system, and exports `sdp_request(const char* json)`, which returns `const char*`. The returned buffer is owned by the shim and stays valid until the next call. Every failure path returns a JSON error object instead of aborting. |
| JS engine | `web/src/engine.js` | `createEngine(options)` returns `{ request(obj), version }`. `request` returns a Promise of the response object. The function instantiates the Emscripten module and converts between strings and objects. `options.locateFile(path, prefix)` lets a host page relocate `parse_sdp.wasm`. `version` is the response of one `version` request made when the engine is created. |
| User interface | `web/src/*.{html,js,css}` | Static files with no bundler. The interface calls `engine.request` and nothing else. |
| Build | `web/wasm/build.sh` | Downloads the pinned Lua, LPeg, and dkjson sources, verifies their SHA-256 checksums, runs `emcc`, writes `web/dist/`, and runs `web/wasm/smoke.mjs`. |
| Smoke test | `web/wasm/smoke.mjs` | Sends every `report` request for the files in `web/fixtures/*.sdp` and `examples/*/valid/*.sdp` to both the WebAssembly engine and the native bridge, and requires identical responses. The test also checks the response shape of every other operation. |
| Deploy | `.github/workflows/pages.yml` | Builds `web/dist/` and publishes it to GitHub Pages on every push to `main` that touches `parse_sdp/**`, `web/**`, the rockspec, or the workflow file. The native side of the smoke test runs on Lua 5.4 in that workflow. |

## Requests

Every request is a JSON object with an `op` field. Every response has
`ok: true`, or `ok: false` with an `error` field. The `error` field is an
error table with `message` and `code`, and optionally `line`, `col`,
`line_text`, `field_path`, `id`, and `spec_ref`.

Three request-level failures return `ok: false` with `code:
"INVALID_VALUE"`: a request that is not a JSON object, an `op` value that
names no operation, and a Lua runtime error inside an operation (the
bridge runs every operation under `pcall`).

### `report`: parse SDP text and validate at every tier

```json
{ "op": "report", "text": "v=0\r\n...", "policy": { "<check id>": "error|warn|off" } }
```

```json
{ "ok": true,
  "doc": { ...parsed document table, from the highest tier that parsed... },
  "tiers": {
    "sdp":    { "passes": true,  "findings": [ ...finding... ] },
    "st2110": { "passes": false, "findings": [ ... ] },
    "ipmx":   { "passes": false, "findings": [ ... ] }
  } }
```

`policy` is optional. The bridge validates `policy` against the check
registry before parsing. One unknown check id rejects the whole request
with `ok: false`.

All three tiers always run. The findings are complete, because the parse
never stops at the first error. `passes` is true when the grammar
matched and no finding has severity `error`. When the grammar could not
match at all, the tier's findings include one entry with
`code: "PARSE_ERROR"`, no `id`, and `line`, `col`, and `line_text` that
name the line the parser could not get past. `doc` is absent only when
no tier matched.

A finding has this shape:

```json
{ "id": "sdp.line.lf-only-line-ending", "severity": "warn",
  "message": "...", "spec_ref": "RFC 8866 §5", "code": "MALFORMED_LINE",
  "line": 3, "col": 1, "line_text": "s=x", "field_path": "media[0].attributes[fmtp:pt=96]",
  "context": {} }
```

`line` and `col` are 0 when the finding came from a document-level check.
Such a finding has `field_path` instead. `context` is `""` or a table.

### `validate`: validate an edited document table

```json
{ "op": "validate", "doc": { ... }, "policy": { ... } }
```

The bridge serializes `doc` with `to_sdp`, then runs `report` on the
resulting text.

```json
{ "ok": true, "text": "v=0\r\n...", "doc": {...}, "tiers": { ... } }
{ "ok": true, "serialize_error": { "message": "...", "field_path": "media[1].port", "code": "MISSING_FIELD" } }
```

`serialize_error` means that the table is structurally incomplete (a
required field is missing) and no text could be produced. The user
interface points at `field_path`.

### `to_sdp`: render a document table

```json
{ "op": "to_sdp", "doc": { ... } }
→ { "ok": true, "text": "v=0\r\n..." }   |   { "ok": false, "error": {...} }
```

### `from_lua`: accept a Lua table literal as input

```json
{ "op": "from_lua", "source": "return { version = \"0\", ... }" }
→ { "ok": true, "doc": { ... } }
```

The bridge loads the chunk as text only, with an empty environment (no
globals). A bare `{ ... }` constructor is accepted as well as
`return { ... }`. A chunk that fails to compile or to run returns
`ok: false` with `code: "MALFORMED_LINE"`. A chunk that returns a value
other than a table returns `ok: false` with `code: "INVALID_VALUE"`.

### `checks`: the validator registry

```json
{ "op": "checks" }
→ { "ok": true, "checks": [ { "id", "kind", "default_severity", "code", "spec_ref", "message_template", "verified" }, ... ] }
```

The array is sorted by `id`. A check with `verified: false` also has a
`verification_note` field.

### `version`

```json
{ "op": "version" }
→ { "ok": true, "lua": "Lua 5.5", "lpeg": "LPeg 1.1.0", "parse_sdp": "1.8.1" }
```

`parse_sdp` is read from the module `parse_sdp_version`. `build.sh`
generates that module from the rockspec file name and embeds it in the
WebAssembly file system. When the module is absent, as in a native run
of `bridge_cli.lua`, the value is `"dev"`.

## Document table shape

The `doc` table is exactly the library's `doc` table (see GUIDE.md
"Parsed Table Structure"). The top-level fields are `version`, `origin`,
`session` (with `name`, `info`, `uri`, `emails`, `phones`, `connection`,
`bandwidths`, `time_descriptions`, `time_zones`, `attributes`), and
`media[]` (with `media`, `port`, `port_count`, `proto`, `fmts[]`, `info`,
`connection`, `bandwidths`, `attributes`). Attributes are decomposed by
name. `rtpmap` has `payload_type`, `encoding`, `clock_rate`, and
`channels`. `fmtp` has `payload_type` and either `params`, an ordered
list of `[key, value|true]` pairs, or `raw`. An unknown attribute is
`{ name, value? }`. The editor must keep these shapes, because `validate`
and `to_sdp` accept only these shapes.

dkjson encodes an empty Lua table as `[]`. The user interface treats `[]`
and a missing field the same way for list-valued fields.
