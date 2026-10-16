import { test } from "node:test";
import assert from "node:assert/strict";
import { mockSerialize } from "../src/mock_serialize.js";
import { fixtureJson, fixtureText } from "./helpers.js";

// The real serializer's output for each fixture doc is the fixture text with
// CRLF endings and fmtp params joined by ";" (verified against
// web/wasm/bridge_cli.lua when the fixtures were recorded).
async function expectedText(name) {
  const lines = (await fixtureText(`${name}.sdp`)).split("\n");
  if (lines[lines.length - 1] === "") lines.pop();
  return lines.map((l) => (l.startsWith("a=fmtp:") ? l.replace(/;\s+/g, ";") : l) + "\r\n").join("");
}

for (const name of ["ipmx_typical", "st2110_invalid", "generic_pathological"]) {
  test(`mockSerialize matches the real serializer for ${name}`, async () => {
    const { doc } = await fixtureJson(`report_${name}.json`);
    assert.equal(mockSerialize(doc).text, await expectedText(name));
  });
}

test("mockSerialize reports the first missing required field with the serializer's field_path", async () => {
  const { doc } = await fixtureJson("report_ipmx_typical.json");
  delete doc.media[1].port;
  assert.equal(mockSerialize(doc).error.field_path, "media[1].port");
  const d2 = (await fixtureJson("report_ipmx_typical.json")).doc;
  delete d2.media[0].attributes[1].encoding;
  const e = mockSerialize(d2).error;
  assert.equal(e.field_path, "media[0].attributes[2].encoding".replace("[2]", "[1]"));
  assert.equal(e.code, "MISSING_FIELD");
});
