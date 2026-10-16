// web/wasm/smoke.mjs — WASM engine vs native bridge parity check.
// Run from anywhere: node web/wasm/smoke.mjs (after build.sh).
import { readFileSync, readdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import assert from "node:assert/strict";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DIST = join(ROOT, "web", "dist");

const native = (req) => {
  const r = spawnSync("lua", ["web/wasm/bridge_cli.lua"], {
    cwd: ROOT, input: JSON.stringify(req), encoding: "utf8",
  });
  assert.equal(r.status, 0, `native bridge failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
};

const sdpFiles = (dir) =>
  readdirSync(dir).filter((f) => f.endsWith(".sdp")).map((f) => join(dir, f));
const fixtures = [
  ...sdpFiles(join(ROOT, "web", "fixtures")),
  ...["generic", "st2110", "ipmx"].flatMap((t) => sdpFiles(join(ROOT, "examples", t, "valid"))),
];

const { createEngine } = await import(pathToFileURL(join(DIST, "engine.js")));
const engine = await createEngine();

// Report parity on every fixture (assert.deepEqual ignores key order).
for (const file of fixtures) {
  const text = readFileSync(file, "utf8");
  const req = { op: "report", text };
  assert.deepEqual(await engine.request(req), native(req), `report mismatch: ${file}`);
}

// Contract shapes for the remaining ops.
const typical = readFileSync(join(ROOT, "web", "fixtures", "ipmx_typical.sdp"), "utf8");
const report = await engine.request({ op: "report", text: typical });
assert.equal(report.ok, true);
assert.equal(report.tiers.ipmx.passes, true);

const validated = await engine.request({ op: "validate", doc: report.doc });
assert.equal(validated.ok, true);
assert.equal(typeof validated.text, "string");
// validate re-serializes with CRLF, so its tiers match a report of its own text.
const reparsed = await engine.request({ op: "report", text: validated.text });
assert.deepEqual(validated.tiers, reparsed.tiers, "validate tiers differ from report");
assert.deepEqual(validated.doc, report.doc, "validate doc differs from report");

const rendered = await engine.request({ op: "to_sdp", doc: report.doc });
assert.equal(rendered.ok, true);
assert.equal(rendered.text, validated.text);
const missing = await engine.request({ op: "validate", doc: { version: "0" } });
assert.equal(missing.ok, true);
assert.equal(typeof missing.serialize_error.message, "string");
assert.equal(typeof missing.serialize_error.code, "string");
const bad = await engine.request({ op: "to_sdp", doc: { version: "0" } });
assert.equal(bad.ok, false);
assert.equal(typeof bad.error.message, "string");

const fromLua = await engine.request({ op: "from_lua", source: '{ version = "0", session = { name = "x" } }' });
assert.equal(fromLua.ok, true);
assert.equal(fromLua.doc.session.name, "x");
const badLua = await engine.request({ op: "from_lua", source: "return {" });
assert.equal(badLua.ok, false);
assert.equal(typeof badLua.error.message, "string");

const checks = await engine.request({ op: "checks" });
assert.equal(checks.ok, true);
assert.ok(checks.checks.length > 0);
for (const key of ["id", "kind", "default_severity", "code", "spec_ref", "message_template", "verified"]) {
  assert.ok(key in checks.checks[0], `checks entry lacks ${key}`);
}
assert.deepEqual(checks, native({ op: "checks" }), "checks registry mismatch");

const rockspec = readdirSync(ROOT).find((f) => /^parse_sdp-.*\.rockspec$/.test(f));
const version = rockspec.replace(/^parse_sdp-/, "").replace(/-\d+\.rockspec$/, "");
assert.deepEqual(engine.version, { ok: true, lua: "Lua 5.5", lpeg: "LPeg 1.1.0", parse_sdp: version });

const unknown = await engine.request({ op: "nope" });
assert.equal(unknown.ok, false);
assert.equal(unknown.error.code, "INVALID_VALUE");
assert.match(unknown.error.message, /unknown op/);

// Malformed JSON bypasses engine.request, which always sends valid JSON.
const { default: createModule } = await import(pathToFileURL(join(DIST, "parse_sdp.js")));
const raw = (await createModule()).cwrap("sdp_request", "string", ["string"]);
const malformed = JSON.parse(raw("{not json"));
assert.equal(malformed.ok, false);
assert.equal(malformed.error.code, "INVALID_VALUE");
const notObject = await engine.request("just a string");
assert.equal(notObject.ok, false);
assert.equal(notObject.error.code, "INVALID_VALUE");

console.log(`smoke: ${fixtures.length} fixtures match native bridge; all op shapes OK`);
