# parse_sdp web bridge contract

The site runs `parse_sdp` entirely in the browser: Lua 5.5 + LPeg +
`parse_sdp` + dkjson compiled to WebAssembly with Emscripten. No backend.

## Layers

| Layer | File | Role |
| --- | --- | --- |
| Lua bridge | `web/wasm/bridge.lua` | JSON request → JSON response over the library. Pure Lua; testable natively with `lua web/wasm/bridge_cli.lua < req.json`. |
| C shim | `web/wasm/bridge.c` | Creates one `lua_State`, preloads LPeg, loads `bridge.lua` from the embedded FS, exports `sdp_request(const char* json) → const char*`. |
| JS engine | `web/src/engine.js` | `createEngine()` → `{ request(obj) → Promise<obj> }`. Instantiates the Emscripten module, marshals strings. |
| UI | `web/src/*.{html,js,css}` | Static, no bundler. Only talks to `engine.request`. |
| Build | `web/wasm/build.sh` | Downloads pinned Lua/LPeg/dkjson, runs `emcc`, writes `web/dist/`. |
| Deploy | `.github/workflows/pages.yml` | Builds and publishes `web/dist/` to GitHub Pages. |

## Requests

Every request is a JSON object with an `op` field. Every response has
`ok: true` or `ok: false` plus `error` (an error table: `message`, `code`,
and optionally `line`, `col`, `line_text`, `field_path`, `id`, `spec_ref`).

### `report` — parse SDP text and validate at every tier

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

`policy` is optional. Tiers are always all three; findings are complete
(the parse never stops at the first error). `passes` is true when the
grammar matched and no finding has severity `error`. When the grammar
could not match at all, the tier's findings include one entry with
`code: "PARSE_ERROR"`, no `id`, and `line` / `col` / `line_text` pointing
at the line the parser could not get past. `doc` is absent only when no
tier matched.

A finding:

```json
{ "id": "sdp.line.lf-only-line-ending", "severity": "warn",
  "message": "...", "spec_ref": "RFC 8866 §5", "code": "MALFORMED_LINE",
  "line": 3, "col": 1, "line_text": "s=x", "field_path": "media[0].attributes[fmtp:pt=96]",
  "context": {} }
```

`line` / `col` are 0 when the finding came from a document-level check
(it then carries `field_path` instead). `context` is `""` or a table.

### `validate` — validate an edited document table

```json
{ "op": "validate", "doc": { ... }, "policy": { ... } }
```

Serializes `doc` with `to_sdp`, then runs `report` on the text.

```json
{ "ok": true, "text": "v=0\r\n...", "doc": {...}, "tiers": { ... } }
{ "ok": true, "serialize_error": { "message": "...", "field_path": "media[1].port", "code": "MISSING_FIELD" } }
```

`serialize_error` means the table is structurally incomplete (a required
field is missing) and no text could be produced; the UI should point at
`field_path`.

### `to_sdp` — render a document table

```json
{ "op": "to_sdp", "doc": { ... } }
→ { "ok": true, "text": "v=0\r\n..." }   |   { "ok": false, "error": {...} }
```

### `from_lua` — accept a Lua table literal as input

```json
{ "op": "from_lua", "source": "return { version = \"0\", ... }" }
→ { "ok": true, "doc": { ... } }
```

The chunk is loaded with an empty environment (no globals). A bare
`{ ... }` constructor is accepted as well as `return { ... }`.

### `checks` — the validator registry

```json
{ "op": "checks" }
→ { "ok": true, "checks": [ { "id", "kind", "default_severity", "code", "spec_ref", "message_template", "verified" }, ... ] }
```

### `version`

```json
{ "op": "version" }
→ { "ok": true, "lua": "Lua 5.5", "lpeg": "LPeg 1.1.0", "parse_sdp": "1.5.1" }
```

## Document table shape

Exactly the library's `doc` table (see GUIDE.md "Parsed Table Structure"):
`version`, `origin`, `session` (name, info, uri, emails, phones,
connection, bandwidths, time_descriptions, time_zones, attributes),
`media[]` (media, port, port_count, proto, fmts[], info, connection,
bandwidths, attributes). Attributes are decomposed by name (`rtpmap` has
`payload_type`, `encoding`, `clock_rate`, `channels`; `fmtp` has
`payload_type` and `params` as an ordered list of `[key, value|true]`
pairs or `raw`); unknown attributes are `{ name, value? }`. The editor
must keep these shapes: `validate` and `to_sdp` only accept them.

dkjson encodes empty Lua tables as `[]`; the UI should treat `[]` and a
missing field the same way for list-valued fields.
