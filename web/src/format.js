// format.js — input format detection and line helpers. Pure; no DOM.

const BOM = "﻿";

// Classify pasted/dropped input. The contract routes SDP text to `report`,
// a JSON document table to `validate`, and a Lua table literal through
// `from_lua` first. Anything unrecognised is treated as SDP so the engine
// produces the diagnostic instead of the UI guessing.
export function detectFormat(text) {
  const s = String(text ?? "").replace(BOM, "").trimStart();
  if (s.startsWith("v=")) return { kind: "sdp" };
  if (s.startsWith("{") || s.startsWith("[")) {
    try {
      return { kind: "json", value: JSON.parse(s) };
    } catch {
      return { kind: "lua" };
    }
  }
  if (/^return\b/.test(s)) return { kind: "lua" };
  return { kind: "sdp" };
}

// Split on CRLF, LF or lone CR. A trailing terminator does not yield an
// extra empty line, matching how the parser numbers lines.
export function splitLines(text) {
  const lines = String(text ?? "").split(/\r\n|\n|\r/);
  if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

// Normalise every line ending to CRLF (RFC 8866 §9) and make sure the
// last line is terminated.
export function toCRLF(text) {
  const s = String(text ?? "").replace(/\r\n|\n|\r/g, "\n");
  if (s === "") return "";
  return (s.endsWith("\n") ? s : s + "\n").replace(/\n/g, "\r\n");
}

// Canonical form used to compare two SDP texts for equality regardless of
// line-ending style or a trailing newline.
export function canonicalText(text) {
  return splitLines(String(text ?? "").replace(BOM, "")).join("\n").trimEnd();
}

// "foo.sdp" → "foo"; used to name downloads after the dropped file.
export function fileStem(name, fallback = "session") {
  const base = String(name ?? "").split(/[\\/]/).pop() || "";
  const stem = base.replace(/\.[^.]+$/, "");
  return stem || fallback;
}
