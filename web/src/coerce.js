// coerce.js — type-preserving conversion between input text and doc
// values. Pure. A number field stays a number, a string stays a string,
// and an emptied field becomes absent (undefined) rather than "" or null.

export function kindOf(value) {
  if (value === null || value === undefined) return "null";
  if (Array.isArray(value)) return "array";
  if (typeof value === "object") return "object";
  if (typeof value === "boolean") return "boolean";
  if (typeof value === "number") return "number";
  return "string";
}

const NUMERIC = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;

// Text typed into a field whose original value had `kind`.
//   number  → Number when the text is numeric, otherwise the raw string
//             (the engine then reports the bad value; the UI never
//             silently drops what the user typed)
//   string  → the string as typed
//   ""      → undefined (field removed)
export function coerceScalar(text, kind) {
  const s = String(text ?? "");
  if (s === "") return undefined;
  if (kind === "number") {
    const t = s.trim();
    return NUMERIC.test(t) ? Number(t) : s;
  }
  if (kind === "boolean") return s === "true";
  return s;
}

// Default value when the user adds a field of a chosen kind.
export function emptyOfKind(kind) {
  switch (kind) {
    case "number": return 0;
    case "boolean": return true;
    case "array": return [];
    case "object": return {};
    default: return "";
  }
}

// Tokens for scalar lists (fmts, emails, src_addresses, …). Items keep the
// kind of their siblings; a list of numbers accepts numbers.
export function coerceToken(text, siblingKind = "string") {
  const s = String(text ?? "").trim();
  if (s === "") return undefined;
  return siblingKind === "number" && NUMERIC.test(s) ? Number(s) : s;
}

export function scalarToText(value) {
  if (value === undefined || value === null) return "";
  return String(value);
}
