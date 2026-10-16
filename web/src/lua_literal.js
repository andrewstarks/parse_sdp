// lua_literal.js — read a Lua table constructor into JS values. Pure.
//
// Used only by the mock engine, which cannot run Lua: the real engine
// hands `from_lua` to the Lua VM. Covers what a hand-written document
// table needs: nested constructors, `name =` / `["str"] =` / `[n] =`
// keys, positional entries, strings with escapes and long brackets,
// numbers (decimal, hex, exponent), true/false/nil, comments. Sequences
// become arrays (an empty table becomes [], matching dkjson).

class Reader {
  constructor(src) {
    this.s = src;
    this.i = 0;
  }
  error(msg) {
    throw new SyntaxError(`${msg} at offset ${this.i}`);
  }
  skip() {
    for (;;) {
      const m = /^(?:\s+|--\[(=*)\[[\s\S]*?\]\1\]|--[^\n]*)/.exec(this.s.slice(this.i));
      if (!m || m[0] === "") return;
      this.i += m[0].length;
    }
  }
  peek() {
    this.skip();
    return this.s[this.i];
  }
  eat(ch) {
    if (this.peek() === ch) {
      this.i++;
      return true;
    }
    return false;
  }
  expect(ch) {
    if (!this.eat(ch)) this.error(`expected '${ch}'`);
  }
  word() {
    const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(this.s.slice(this.i));
    return m ? m[0] : null;
  }
  value() {
    const c = this.peek();
    if (c === "{") return this.table();
    if (c === '"' || c === "'") return this.quoted(c);
    if (c === "[" && /^\[=*\[/.test(this.s.slice(this.i))) return this.longString();
    const num = /^[+-]?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)/.exec(this.s.slice(this.i));
    if (num) {
      this.i += num[0].length;
      return Number(num[0]);
    }
    const w = this.word();
    if (w === "true" || w === "false" || w === "nil") {
      this.i += w.length;
      return w === "true" ? true : w === "false" ? false : null;
    }
    this.error("unexpected token");
  }
  quoted(q) {
    this.i++;
    let out = "";
    while (this.i < this.s.length) {
      const c = this.s[this.i++];
      if (c === q) return out;
      if (c === "\n") this.error("unterminated string");
      if (c !== "\\") {
        out += c;
        continue;
      }
      const e = this.s[this.i++];
      const simple = { n: "\n", t: "\t", r: "\r", a: "\x07", b: "\b", f: "\f", v: "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n" };
      if (e in simple) out += simple[e];
      else if (e === "x") {
        out += String.fromCharCode(parseInt(this.s.substr(this.i, 2), 16));
        this.i += 2;
      } else if (e === "u" && this.s[this.i] === "{") {
        const end = this.s.indexOf("}", this.i);
        out += String.fromCodePoint(parseInt(this.s.slice(this.i + 1, end), 16));
        this.i = end + 1;
      } else if (/\d/.test(e)) {
        const m = /^\d{1,3}/.exec(this.s.slice(this.i - 1));
        out += String.fromCharCode(Number(m[0]));
        this.i += m[0].length - 1;
      } else if (e === "z") {
        while (/\s/.test(this.s[this.i] ?? "")) this.i++;
      } else this.error(`bad escape \\${e}`);
    }
    this.error("unterminated string");
  }
  longString() {
    const open = /^\[(=*)\[/.exec(this.s.slice(this.i));
    const close = `]${open[1]}]`;
    const start = this.i + open[0].length;
    const end = this.s.indexOf(close, start);
    if (end === -1) this.error("unterminated long string");
    this.i = end + close.length;
    let body = this.s.slice(start, end);
    if (body.startsWith("\r\n")) body = body.slice(2);
    else if (body.startsWith("\n")) body = body.slice(1);
    return body;
  }
  table() {
    this.expect("{");
    const positional = [];
    const named = new Map();
    while (!this.eat("}")) {
      let key;
      if (this.peek() === "[" && !/^\[=*\[/.test(this.s.slice(this.i))) {
        this.i++;
        key = this.value();
        this.expect("]");
        this.expect("=");
      } else {
        const w = this.word();
        const save = this.i;
        if (w && !["true", "false", "nil"].includes(w)) {
          this.i += w.length;
          if (this.eat("=")) key = w;
          else this.i = save;
        }
      }
      const v = this.value();
      if (key === undefined) positional.push(v);
      else if (v !== null) named.set(key, v);
      if (!this.eat(",") && !this.eat(";")) {
        this.expect("}");
        break;
      }
    }
    const seq = positional.filter((v) => v !== null);
    if (named.size === 0) return seq;
    // Mixed table: positional fields are assigned after keyed ones, as Lua does.
    const obj = {};
    for (const [k, v] of named) obj[k] = v;
    seq.forEach((v, i) => { obj[i + 1] = v; });
    return obj;
  }
}

// Accepts `return { ... }` or a bare `{ ... }` and returns the JS value.
export function parseLuaLiteral(source) {
  const r = new Reader(String(source ?? ""));
  r.skip();
  if (r.word() === "return") r.i += 6;
  const v = r.value();
  r.skip();
  if (r.i !== r.s.length) r.error("trailing input");
  return v;
}

// ── Writer ───────────────────────────────────────────────────────────────
// toLuaLiteral(doc) → "return { ... }\n", readable and accepted by both
// parseLuaLiteral above and the engine's `from_lua` (which loads the chunk
// with an empty environment, so only literals are emitted).

const LUA_KEYWORDS = new Set(["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
  "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"]);
const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/;

function luaString(s) {
  let out = '"';
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (c < 0x20 || c === 0x7f) out += `\\${String(c).padStart(3, "0")}`;
    else out += ch;
  }
  return out + '"';
}

function luaScalar(v) {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "boolean") return String(v);
  if (typeof v === "number") {
    if (Number.isNaN(v)) return "(0/0)";
    if (!Number.isFinite(v)) return v > 0 ? "(1/0)" : "(-1/0)";
    return String(v);
  }
  return luaString(String(v));
}

function luaKey(k) {
  return IDENT.test(k) && !LUA_KEYWORDS.has(k) ? k : `[${luaString(k)}]`;
}

function luaValue(v, depth, indent) {
  if (v === null || typeof v !== "object") return luaScalar(v);
  const pad = indent.repeat(depth + 1);
  const end = indent.repeat(depth);
  if (Array.isArray(v)) {
    if (v.length === 0) return "{}";
    if (v.every((x) => x === null || typeof x !== "object")) return `{ ${v.map(luaScalar).join(", ")} }`;
    return `{\n${v.map((x) => `${pad}${luaValue(x, depth + 1, indent)},`).join("\n")}\n${end}}`;
  }
  const entries = Object.entries(v).filter(([, x]) => x !== undefined);
  if (entries.length === 0) return "{}";
  return `{\n${entries.map(([k, x]) => `${pad}${luaKey(k)} = ${luaValue(x, depth + 1, indent)},`).join("\n")}\n${end}}`;
}

export function toLuaLiteral(doc, indent = "  ") {
  return `return ${luaValue(doc, 0, indent)}\n`;
}
