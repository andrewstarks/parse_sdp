import { test } from "node:test";
import assert from "node:assert/strict";
import { groupExamples, formatExampleName, exampleLabel, sessionNameOf, BUNDLED_EXAMPLES } from "../src/examples.js";

test("formatExampleName makes numeric prefixes and underscores readable", () => {
  assert.equal(formatExampleName("05_typical_multistream"), "05 · Typical multistream");
  assert.equal(formatExampleName("01_simple_audio"), "01 · Simple audio");
  assert.equal(formatExampleName("dup_group_video"), "Dup group video");
  assert.equal(formatExampleName("ipmx_typical"), "Ipmx typical");
});

test("groupExamples groups by tier and status in tier order, keeping manifest order within a group", () => {
  const manifest = [
    { tier: "ipmx", status: "invalid", name: "01_bad", path: "examples/ipmx/invalid/01_bad.sdp" },
    { tier: "generic", status: "valid", name: "02_simple_video", path: "examples/generic/valid/02_simple_video.sdp", title: "Simple Video Call" },
    { tier: "st2110", status: "valid", name: "05_typical_multistream", path: "examples/st2110/valid/05_typical_multistream.sdp" },
    { tier: "generic", status: "valid", name: "01_simple_audio", path: "examples/generic/valid/01_simple_audio.sdp" },
    { tier: "st2110", status: "invalid", name: "03_x", path: "examples/st2110/invalid/03_x.sdp" },
    { tier: "generic", status: "invalid", name: "09_y", path: "examples/generic/invalid/09_y.sdp", title: "" },
  ];
  const groups = groupExamples(manifest);
  assert.deepEqual(groups.map((g) => g.label), ["RFC 8866 — valid", "RFC 8866 — invalid", "ST 2110 — valid", "ST 2110 — invalid", "IPMX — invalid"]);
  assert.deepEqual(groups[0].items.map((i) => i.label), ["Simple Video Call", "01 · Simple audio"], "title wins; readable name is the fallback");
  assert.deepEqual(groups[1].items.map((i) => i.label), ["09 · Y"], "an empty title falls back to the name");
  assert.equal(groups[2].items[0].path, "examples/st2110/valid/05_typical_multistream.sdp");
});

test("groupExamples skips malformed entries and handles the bundled fallback", () => {
  assert.deepEqual(groupExamples([{ tier: "x" }, null]), []);
  const groups = groupExamples(BUNDLED_EXAMPLES);
  assert.equal(groups.length, 3);
  assert.equal(groups.flatMap((g) => g.items).length, 3);
});

test("exampleLabel and sessionNameOf", () => {
  assert.equal(exampleLabel({ name: "05_typical_multistream", title: "ST 2110 Multi-stream" }), "ST 2110 Multi-stream");
  assert.equal(exampleLabel({ name: "05_typical_multistream", title: "   " }), "05 · Typical multistream");
  assert.equal(exampleLabel({ name: "05_typical_multistream" }), "05 · Typical multistream");
  assert.equal(sessionNameOf("v=0\r\no=- 1 1 IN IP4 1.2.3.4\r\ns=IPMX Studio Feed\r\nt=0 0\r\n"), "IPMX Studio Feed");
  assert.equal(sessionNameOf("v=0\ns= \n"), "");
  assert.equal(sessionNameOf("v=0\nt=0 0\n"), "");
  assert.equal(sessionNameOf("s=not at line start? yes it is\n"), "not at line start? yes it is");
});
