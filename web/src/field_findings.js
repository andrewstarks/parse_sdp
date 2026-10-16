// field_findings.js — map report findings onto editor fields. Pure.
//
// attachFindings(doc, rows) resolves each finding's field_path against the
// document (docpath.resolvePath). A path that resolves fully attaches to
// that field; one that does not (the finding names a missing field, e.g.
// media[0].attributes[fmtp] with no fmtp) attaches to the deepest existing
// ancestor with `missing: true`. Counts are aggregated up every ancestor
// so a collapsed card can show what is inside it.

import { resolvePath, pathToString } from "./docpath.js";

const SEV_RANK = { error: 2, warn: 1 };

export function worstSeverity(a, b) {
  return (SEV_RANK[b] ?? 0) > (SEV_RANK[a] ?? 0) ? b : a;
}

// First sentence / clause of a message, for the one-line summary.
export function shortMessage(message, max = 90) {
  const m = String(message ?? "").replace(/\s+/g, " ").trim();
  if (m.length <= max) return m;
  const cut = m.slice(0, max);
  const stop = Math.max(cut.lastIndexOf("; "), cut.lastIndexOf(" ("), cut.lastIndexOf(", "), cut.lastIndexOf(" "));
  return `${cut.slice(0, stop > 40 ? stop : max).trimEnd()}…`;
}

// rows: de-duplicated finding rows (findings.dedupeFindings).
// options.lineMap: lineToPath(text) for the analysed text, which lets a
//   line-anchored finding (no field_path) attach to the field that line
//   produced, flagged `byLine`; without a map such rows are ignored.
// options.skipIds: check ids never shown on fields (formatting checks that
//   fire per line, e.g. bare-LF warnings, belong to the source view).
// A row with neither field_path nor line (a document-level finding the
// engine could not locate) attaches to the document root, flagged
// `unlocated`.
// Returns {
//   attachments: Map<pathStr, [{ key, finding, tiers, path, pathStr, missing, fieldPath }]>,
//   counts:      Map<pathStr, { errors, warnings, worst }>   // every ancestor, "" = document
// }
export function attachFindings(doc, rows, { lineMap, skipIds } = {}) {
  const attachments = new Map();
  const counts = new Map();
  if (!doc || typeof doc !== "object") return { attachments, counts };
  for (const row of rows ?? []) {
    const f = row.finding;
    if (!f) continue;
    if (skipIds?.has(f.id)) continue;
    let target = f.field_path || null;
    let byLine = false;
    const unlocated = !target && !(f.line > 0);
    if (!target && !unlocated) {
      target = lineMap?.[f.line - 1] ?? null;
      if (!target) continue;
      byLine = true;
    }
    const { path, exact } = unlocated ? { path: [], exact: false } : resolvePath(doc, target);
    const pathStr = pathToString(path);
    const a = { key: row.key, finding: f, tiers: row.tiers ?? [], path, pathStr, missing: !exact, unlocated, byLine, fieldPath: f.field_path || null };
    if (!attachments.has(pathStr)) attachments.set(pathStr, []);
    attachments.get(pathStr).push(a);
    for (let i = 0; i <= path.length; i++) {
      const anc = pathToString(path.slice(0, i));
      const c = counts.get(anc) ?? { errors: 0, warnings: 0, worst: null };
      if (f.severity === "error") c.errors++;
      else c.warnings++;
      c.worst = worstSeverity(c.worst, f.severity);
      counts.set(anc, c);
    }
  }
  for (const list of attachments.values()) {
    list.sort((x, y) => (SEV_RANK[y.finding.severity] ?? 0) - (SEV_RANK[x.finding.severity] ?? 0) || (x.missing === y.missing ? 0 : x.missing ? -1 : 1));
  }
  return { attachments, counts };
}

export function countsLabel(c) {
  if (!c) return "";
  const parts = [];
  if (c.errors) parts.push(`${c.errors} error${c.errors === 1 ? "" : "s"}`);
  if (c.warnings) parts.push(`${c.warnings} warning${c.warnings === 1 ? "" : "s"}`);
  return parts.join(" · ");
}

// Document order for paths: top-level fields in SDP order, then segment by
// segment (indices numerically). Used to list findings "as the document reads".
const ROOT_RANK = { version: 0, origin: 1, session: 2, media: 3 };
export function comparePaths(a, b) {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const x = a[i], y = b[i];
    if (x === y) continue;
    if (i === 0) {
      const rx = ROOT_RANK[x] ?? 9, ry = ROOT_RANK[y] ?? 9;
      if (rx !== ry) return rx - ry;
    }
    if (typeof x === "number" && typeof y === "number") return x - y;
    return String(x) < String(y) ? -1 : 1;
  }
  return a.length - b.length;
}

// Flat list for the editor's summary block: errors first, then document
// position (unlocated findings sit at the root, so they lead their group).
export function summaryEntries(attachments) {
  const all = [];
  for (const list of attachments.values()) all.push(...list);
  return all.sort((x, y) => (SEV_RANK[y.finding.severity] ?? 0) - (SEV_RANK[x.finding.severity] ?? 0) || comparePaths(x.path, y.path) || (x.finding.line || 0) - (y.finding.line || 0));
}
