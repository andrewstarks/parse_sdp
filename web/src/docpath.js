// docpath.js — field_path strings ↔ positions in the document table. Pure.
//
// Two path dialects reach the UI:
//   * serializer paths:   media[0].attributes[2].encoding   (plain indices)
//   * grammar paths:      media[0].attributes[fmtp:pt=96]   (selectors)
//                         session.attributes[group][0]      (k-th by name)
// Both are parsed into segments; selectors are resolved against the doc
// into plain keys/indices so the editor can address a single element.

// "media[0].attributes[fmtp:pt=96]" → [ "media", 0, "attributes", { selector: "fmtp:pt=96" } ]
export function parsePath(str) {
  const segs = [];
  const re = /([^.[\]]+)|\[([^\]]*)\]/g;
  let m;
  for (const s of String(str ?? "").split(".")) {
    re.lastIndex = 0;
    while ((m = re.exec(s)) !== null) {
      if (m[1] !== undefined) segs.push(m[1]);
      else if (/^\d+$/.test(m[2])) segs.push(Number(m[2]));
      else segs.push({ selector: m[2] });
    }
  }
  return segs;
}

// Plain path (keys and indices only) → canonical string.
export function pathToString(path) {
  let out = "";
  for (const seg of path) {
    if (typeof seg === "number") out += `[${seg}]`;
    else out += out === "" ? seg : `.${seg}`;
  }
  return out;
}

function matchesSelector(item, selector) {
  if (item === null || typeof item !== "object") return false;
  const colon = selector.indexOf(":");
  const name = colon === -1 ? selector : selector.slice(0, colon);
  if (item.name !== name) return false;
  if (colon === -1) return true;
  for (const cond of selector.slice(colon + 1).split(",")) {
    const eq = cond.indexOf("=");
    if (eq === -1) continue;
    const key = cond.slice(0, eq).trim();
    const want = cond.slice(eq + 1).trim();
    const field = key === "pt" ? "payload_type" : key;
    if (String(item[field]) !== want) return false;
  }
  return true;
}

// Resolve a field_path against `doc`. Returns { path, exact } where `path`
// is a plain path to the deepest element that exists and `exact` says
// whether every segment resolved. Selectors pick the first matching
// element of an array; a numeric segment right after a selector picks the
// k-th match instead (0-based, as the grammar emits it).
export function resolvePath(doc, str) {
  const segs = parsePath(str);
  const path = [];
  let cur = doc;
  for (let i = 0; i < segs.length; i++) {
    const seg = segs[i];
    if (cur === null || typeof cur !== "object") return { path, exact: false };
    if (typeof seg === "object") {
      if (!Array.isArray(cur)) return { path, exact: false };
      const matches = [];
      cur.forEach((item, idx) => { if (matchesSelector(item, seg.selector)) matches.push(idx); });
      let pick = 0;
      if (typeof segs[i + 1] === "number") { pick = segs[i + 1]; i++; }
      if (matches[pick] === undefined) return { path, exact: false };
      path.push(matches[pick]);
      cur = cur[matches[pick]];
    } else {
      if (!(seg in Object(cur))) return { path, exact: false };
      path.push(seg);
      cur = cur[seg];
    }
  }
  return { path, exact: true };
}

export function getAt(doc, path) {
  let cur = doc;
  for (const seg of path) {
    if (cur === null || typeof cur !== "object") return undefined;
    cur = cur[seg];
  }
  return cur;
}

// Set a value in place. `undefined` deletes the key (object) or splices the
// element out (array) so the doc never carries null/undefined — the
// bridge treats an absent field as absent, and JSON has no `undefined`.
export function setAt(doc, path, value) {
  if (path.length === 0) return doc;
  const parent = getAt(doc, path.slice(0, -1));
  if (parent === null || typeof parent !== "object") return doc;
  const key = path[path.length - 1];
  if (value === undefined) {
    if (Array.isArray(parent) && typeof key === "number") parent.splice(key, 1);
    else delete parent[key];
  } else {
    parent[key] = value;
  }
  return doc;
}

export function parentPath(path) {
  return path.slice(0, -1);
}

export function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}
