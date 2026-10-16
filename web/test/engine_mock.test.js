import { test } from "node:test";
import assert from "node:assert/strict";
import { createEngine } from "../src/engine_mock.js";
import { fsLoader, fixtureJson, fixtureText } from "./helpers.js";

const engine = await createEngine({ load: fsLoader });

test("version and checks come from the recorded fixtures", async () => {
  assert.deepEqual(engine.version, await fixtureJson("version.json"));
  const checks = await engine.request({ op: "checks" });
  assert.equal(checks.checks.length, (await fixtureJson("checks.json")).checks.length);
});

test("report on a known input returns the recorded response regardless of line endings", async () => {
  const text = await fixtureText("ipmx_typical.sdp");
  const rep = await engine.request({ op: "report", text: text.replace(/\n/g, "\r\n") });
  const recorded = await fixtureJson("report_ipmx_typical.json");
  assert.deepEqual(rep.tiers, recorded.tiers);
  assert.deepEqual(rep.doc, recorded.doc);
  assert.equal(rep.mock, "fixture");
});

test("report on an unknown input is synthesized from the pathological fixture", async () => {
  const rep = await engine.request({ op: "report", text: "v=0\r\no=- 1 1 IN IP4 1.2.3.4\r\ns=x\r\n" });
  assert.equal(rep.ok, true);
  assert.equal(rep.mock, "synthesized");
  assert.ok(rep.doc);
  for (const f of rep.tiers.ipmx.findings) {
    assert.ok(f.line <= 3, "line-anchored findings never point past the input");
    assert.notEqual(f.id, "sdp.line.lf-only-line-ending", "CRLF input gets no bare-LF warnings");
  }
  const lf = await engine.request({ op: "report", text: "v=0\ns=x\nt=0 0\n" });
  assert.equal(lf.tiers.sdp.findings.filter((f) => f.id === "sdp.line.lf-only-line-ending").length, 2);
});

test("policy overrides change severity and `off` removes findings", async () => {
  const text = await fixtureText("st2110_invalid.sdp");
  const rep = await engine.request({ op: "report", text, policy: { "sdp.line.lf-only-line-ending": "off", "st2110.attr.ts-refclk-required": "warn" } });
  assert.equal(rep.tiers.sdp.findings.length, 0);
  assert.equal(rep.tiers.st2110.passes, true);
  assert.equal(rep.tiers.st2110.findings[0].severity, "warn");
});

test("validate returns text + tiers for a complete doc and serialize_error for an incomplete one", async () => {
  const { doc } = await fixtureJson("report_ipmx_typical.json");
  const ok = await engine.request({ op: "validate", doc });
  assert.equal(ok.ok, true);
  assert.ok(ok.text.startsWith("v=0\r\n"));
  assert.ok(ok.tiers.ipmx);
  doc.media[0].port = 20001;
  const edited = await engine.request({ op: "validate", doc });
  assert.ok(edited.text.includes("m=video 20001 RTP/AVP 96"));
  assert.equal(edited.doc.media[0].port, 20001);
  delete doc.origin.sess_id;
  const bad = await engine.request({ op: "validate", doc });
  assert.equal(bad.ok, true);
  assert.equal(bad.serialize_error.field_path, "origin.sess_id");
  assert.equal(bad.text, undefined);
});

test("to_sdp and from_lua", async () => {
  const { doc } = await fixtureJson("report_st2110_invalid.json");
  const r = await engine.request({ op: "to_sdp", doc });
  assert.ok(r.text.includes("a=rtpmap:96 raw/90000\r\n"));
  const lua = await engine.request({ op: "from_lua", source: 'return { version = "0", media = {} }' });
  assert.deepEqual(lua, { ok: true, doc: { version: "0", media: [] } });
  const bad = await engine.request({ op: "from_lua", source: "{ nope" });
  assert.equal(bad.ok, false);
  assert.equal(bad.error.code, "MALFORMED_LINE");
});

test("unknown op", async () => {
  const r = await engine.request({ op: "nope" });
  assert.equal(r.ok, false);
});
