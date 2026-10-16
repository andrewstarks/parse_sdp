import { test } from "node:test";
import assert from "node:assert/strict";
import { parseLuaLiteral } from "../src/lua_literal.js";

test("parses a document-shaped table with return", () => {
  const v = parseLuaLiteral(`
    -- a comment
    return {
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1", net_type = "IN", addr_type = "IP4", unicast_address = "192.0.2.1" },
      session = { name = "x", emails = {}, time_descriptions = { { start = 0, stop = 0, repeats = {} } },
                  attributes = { { name = "recvonly" }, { name = "tool", value = 'a "quoted" tool' } } },
      media = { { media = "video", port = 5004, proto = "RTP/AVP", fmts = { "96" },
                  attributes = { { name = "fmtp", payload_type = 96, params = { { "width", "1920" }, { "IPMX", true } } } } } },
    }`);
  assert.equal(v.version, "0");
  assert.deepEqual(v.session.emails, []);
  assert.equal(v.session.attributes[1].value, 'a "quoted" tool');
  assert.deepEqual(v.media[0].attributes[0].params, [["width", "1920"], ["IPMX", true]]);
  assert.equal(v.media[0].port, 5004);
});

test("accepts a bare constructor, bracket keys, semicolons, long strings, escapes, nil", () => {
  const v = parseLuaLiteral(`{ ["a-b"] = 1; [2] = "two", x = [[long
text]], y = "tab\\there\\65", z = nil, 0x10, --[[ block
comment ]] true }`);
  assert.deepEqual(v, { 1: 16, 2: true, "a-b": 1, x: "long\ntext", y: "tab\thereA" });
});

test("rejects malformed input with a SyntaxError", () => {
  assert.throws(() => parseLuaLiteral("{ a = }"), SyntaxError);
  assert.throws(() => parseLuaLiteral('{ a = "unterminated }'), SyntaxError);
  assert.throws(() => parseLuaLiteral("{ } extra"), SyntaxError);
});

import { toLuaLiteral } from "../src/lua_literal.js";
import { fixtureJson } from "./helpers.js";

test("toLuaLiteral writes a readable return chunk", () => {
  const out = toLuaLiteral({ version: "0", media: [], session: { name: "x", emails: [], attributes: [{ name: "recvonly" }] } });
  assert.equal(out, `return {
  version = "0",
  media = {},
  session = {
    name = "x",
    emails = {},
    attributes = {
      {
        name = "recvonly",
      },
    },
  },
}
`);
});

test("toLuaLiteral brackets non-identifier and keyword keys, escapes strings, keeps numbers and booleans", () => {
  const out = toLuaLiteral({ "a-b": 1, end: true, q: 'say "hi"\n', n: -1.5e21, params: [["IPMX", true], ["w", "1"]] });
  assert.match(out, /\["a-b"\] = 1,/);
  assert.match(out, /\["end"\] = true,/);
  assert.match(out, /q = "say \\"hi\\"\\n",/);
  assert.match(out, /n = -1.5e\+21,/);
  assert.match(out, /\{ "IPMX", true \},\n\s+\{ "w", "1" \},/);
});

for (const name of ["ipmx_typical", "st2110_invalid", "generic_pathological"]) {
  test(`toLuaLiteral round-trips the ${name} document through parseLuaLiteral`, async () => {
    const { doc } = await fixtureJson(`report_${name}.json`);
    assert.deepEqual(parseLuaLiteral(toLuaLiteral(doc)), doc);
  });
}

test("toLuaLiteral round-trips control characters and unicode", () => {
  const v = { s: "tab\there\x01 — ünïcode \\ back", list: [1, "two", false] };
  assert.deepEqual(parseLuaLiteral(toLuaLiteral(v)), v);
});
