// examples.js — the example manifest (web/dist/examples/index.json, written
// by wasm/build.sh) → labelled option groups for the examples dropdown. Pure.

const TIER_LABEL = { generic: "RFC 8866", st2110: "ST 2110", ipmx: "IPMX" };
const TIER_RANK = { generic: 0, st2110: 1, ipmx: 2 };
const STATUS_RANK = { valid: 0, invalid: 1 };

// The three fixtures bundled under src/examples, used when no manifest is
// served (plain web/src, the mock engine). The mock answers these exactly.
export const BUNDLED_EXAMPLES = [
  { tier: "ipmx", status: "valid", name: "ipmx_typical", path: "examples/ipmx_typical.sdp" },
  { tier: "st2110", status: "invalid", name: "st2110_invalid", path: "examples/st2110_invalid.sdp" },
  { tier: "generic", status: "valid", name: "generic_pathological", path: "examples/generic_pathological.sdp" },
];

// "05_typical_multistream" → "05 · Typical multistream"; "dup_group_video" → "Dup group video".
export function formatExampleName(name) {
  const m = /^(\d+)_(.*)$/.exec(name);
  const words = (m ? m[2] : name).replace(/_/g, " ").trim();
  const text = words.charAt(0).toUpperCase() + words.slice(1);
  return m ? `${m[1]} · ${text}` : text;
}

export function groupLabel(tier, status) {
  return `${TIER_LABEL[tier] ?? tier} — ${status}`;
}

// The s= session-name line of an SDP text, or "" when there is none. Used
// to title the bundled fallback examples the way the build manifest does.
export function sessionNameOf(text) {
  const m = /(?:^|\r?\n|\r)s=([^\r\n]*)/.exec(String(text ?? ""));
  return m ? m[1].trim() : "";
}

// Option text: the manifest's `title` (the file's own s= line) when it has
// one; otherwise the readable form of the file name.
export function exampleLabel(entry) {
  const title = typeof entry.title === "string" ? entry.title.trim() : "";
  return title || formatExampleName(entry.name ?? entry.path);
}

// manifest: [{ tier, status, name, path, title? }] in repo order →
// [{ label, items: [{ label, path, name }] }] grouped by tier then status,
// groups in tier order (RFC 8866 → ST 2110 → IPMX, valid before invalid),
// items keeping manifest order.
export function groupExamples(manifest) {
  const groups = new Map();
  for (const e of manifest ?? []) {
    if (!e || typeof e.path !== "string") continue;
    const key = `${e.tier}|${e.status}`;
    if (!groups.has(key)) groups.set(key, { tier: e.tier, status: e.status, label: groupLabel(e.tier, e.status), items: [] });
    groups.get(key).items.push({ label: exampleLabel(e), path: e.path, name: e.name });
  }
  const rank = (g) => [(TIER_RANK[g.tier] ?? 9), (STATUS_RANK[g.status] ?? 9)];
  return [...groups.values()]
    .sort((a, b) => { const ra = rank(a); const rb = rank(b); return ra[0] - rb[0] || ra[1] - rb[1] || (a.label < b.label ? -1 : 1); })
    .map(({ label, items }) => ({ label, items }));
}
