import { test } from "node:test";
import assert from "node:assert/strict";
import { detectFormat, splitLines, toCRLF, canonicalText, fileStem } from "../src/format.js";

test("detectFormat: SDP text starts with v=", () => {
  assert.equal(detectFormat("v=0\r\no=- 1 1 IN IP4 1.2.3.4\r\n").kind, "sdp");
  assert.equal(detectFormat("\uFEFF  \n v=0\n").kind, "sdp");
});

test("detectFormat: JSON object or array parses", () => {
  const r = detectFormat('{"version":"0"}');
  assert.equal(r.kind, "json");
  assert.deepEqual(r.value, { version: "0" });
  assert.equal(detectFormat("[1,2]").kind, "json");
});

test("detectFormat: brace that is not JSON falls back to Lua", () => {
  assert.equal(detectFormat('{ version = "0" }').kind, "lua");
  assert.equal(detectFormat('return { version = "0" }').kind, "lua");
  assert.equal(detectFormat("returned = 1").kind, "sdp", "`return` must be a whole word");
});

test("detectFormat: unknown input is handed to the SDP parser", () => {
  assert.equal(detectFormat("hello").kind, "sdp");
  assert.equal(detectFormat("").kind, "sdp");
  assert.equal(detectFormat(undefined).kind, "sdp");
});

test("splitLines handles CRLF, LF, CR and a trailing terminator", () => {
  assert.deepEqual(splitLines("a\r\nb\nc\rd\r\n"), ["a", "b", "c", "d"]);
  assert.deepEqual(splitLines("a\n\n"), ["a", ""]);
  assert.deepEqual(splitLines(""), [""]);
});

test("toCRLF normalises endings and terminates the last line", () => {
  assert.equal(toCRLF("v=0\ns=x"), "v=0\r\ns=x\r\n");
  assert.equal(toCRLF("v=0\r\ns=x\r\n"), "v=0\r\ns=x\r\n");
  assert.equal(toCRLF("v=0\rs=x\r"), "v=0\r\ns=x\r\n");
  assert.equal(toCRLF(""), "");
});

test("canonicalText ignores line-ending style, BOM and trailing newline", () => {
  assert.equal(canonicalText("\uFEFFv=0\r\ns=x\r\n"), canonicalText("v=0\ns=x"));
});

test("fileStem strips directories and extension", () => {
  assert.equal(fileStem("dir/cam1.sdp"), "cam1");
  assert.equal(fileStem("C:\\x\\cam1.SDP"), "cam1");
  assert.equal(fileStem(""), "session");
});
