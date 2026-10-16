import { test } from "node:test";
import assert from "node:assert/strict";
import { lineToPath } from "../src/line_map.js";
import { fixtureText, fixtureJson } from "./helpers.js";
import { getAt, parsePath } from "../src/docpath.js";

test("lineToPath follows the parser's fill order across session and media blocks", () => {
  const text = ["v=0", "o=- 1 1 IN IP4 1.2.3.4", "s=x", "i=info", "u=http://u", "e=a@b", "e=c@d", "p=+1", "c=IN IP4 1.2.3.4", "b=CT:1", "t=0 0", "r=1 2 3", "r=4 5 6", "t=1 2", "z=1 -1h", "a=recvonly", "a=tool:x",
    "m=video 5000 RTP/AVP 96", "i=vid", "c=IN IP4 2.3.4.5", "b=AS:1", "b=TIAS:2", "a=rtpmap:96 raw/90000", "a=fmtp:96 x=1", "", "k=obsolete",
    "m=audio 5002 RTP/AVP 97", "a=rtpmap:97 L24/48000/2"].join("\r\n") + "\r\n";
  assert.deepEqual(lineToPath(text), [
    "version", "origin", "session.name", "session.info", "session.uri", "session.emails[0]", "session.emails[1]", "session.phones[0]",
    "session.connection", "session.bandwidths[0]", "session.time_descriptions[0]", "session.time_descriptions[0].repeats[0]",
    "session.time_descriptions[0].repeats[1]", "session.time_descriptions[1]", "session.time_zones", "session.attributes[0]", "session.attributes[1]",
    "media[0]", "media[0].info", "media[0].connection", "media[0].bandwidths[0]", "media[0].bandwidths[1]", "media[0].attributes[0]", "media[0].attributes[1]",
    null, null,
    "media[1]", "media[1].attributes[0]",
  ]);
});

test("lineToPath on a real fixture: every mapped line names an existing field with the matching text", async () => {
  const text = await fixtureText("generic_pathological.sdp");
  const { doc } = await fixtureJson("report_generic_pathological.json");
  const lines = text.split("\n").filter((l) => l !== "");
  const map = lineToPath(text);
  assert.equal(map.length, lines.length);
  map.forEach((p, i) => {
    assert.ok(p, `line ${i + 1} unmapped`);
    const v = getAt(doc, parsePath(p));
    assert.notEqual(v, undefined, `line ${i + 1}: ${p} missing in doc`);
    if (lines[i].startsWith("a=rtpmap:")) assert.equal(v.name, "rtpmap", `line ${i + 1}`);
    if (lines[i].startsWith("m=")) assert.equal(`m=${v.media} ${v.port} ${v.proto} ${v.fmts.join(" ")}`, lines[i]);
    if (lines[i].startsWith("b=")) assert.equal(`b=${v.type}:${v.value}`, lines[i]);
  });
});
