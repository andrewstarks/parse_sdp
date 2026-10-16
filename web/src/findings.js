// findings.js — collapse per-tier finding lists into one de-duplicated
// table and summarise tiers. Pure.

export const TIER_ORDER = ["sdp", "st2110", "ipmx"];

export const TIER_LABELS = {
  sdp: "RFC 8866",
  st2110: "ST 2110",
  ipmx: "IPMX",
};

// Identity of a finding across tiers: same check at the same place.
// PARSE_ERROR findings carry no id, so the code stands in for it.
export function findingKey(f) {
  return [f.id || f.code || "", f.line || 0, f.col || 0, f.field_path || ""].join("|");
}

export function tierSummary(tier) {
  const findings = tier?.findings ?? [];
  let errors = 0;
  let warnings = 0;
  for (const f of findings) {
    if (f.severity === "error") errors++;
    else if (f.severity === "warn") warnings++;
  }
  return { passes: Boolean(tier?.passes), errors, warnings, total: findings.length };
}

// Rows are ordered as the source reads: line-anchored findings by line and
// column, document-level findings (line 0) after them by field_path.
function compareRows(a, b) {
  const fa = a.finding;
  const fb = b.finding;
  const la = fa.line || Infinity;
  const lb = fb.line || Infinity;
  if (la !== lb) return la - lb;
  if ((fa.col || 0) !== (fb.col || 0)) return (fa.col || 0) - (fb.col || 0);
  const pa = fa.field_path || "";
  const pb = fb.field_path || "";
  if (pa !== pb) return pa < pb ? -1 : 1;
  if (fa.severity !== fb.severity) return fa.severity === "error" ? -1 : 1;
  return (fa.id || "") < (fb.id || "") ? -1 : 1;
}

// tiers: { sdp: {findings}, st2110: {...}, ipmx: {...} } →
// [{ key, finding, tiers: ["sdp", "st2110"] }, ...]
export function dedupeFindings(tiers) {
  const rows = new Map();
  for (const name of TIER_ORDER) {
    for (const f of tiers?.[name]?.findings ?? []) {
      const key = findingKey(f);
      const row = rows.get(key);
      if (row) row.tiers.push(name);
      else rows.set(key, { key, finding: f, tiers: [name] });
    }
  }
  return [...rows.values()].sort(compareRows);
}

// tier: "all" | tier name; severities: Set of "error"/"warn".
export function filterRows(rows, { tier = "all", severities } = {}) {
  return rows.filter((row) => {
    if (tier !== "all" && !row.tiers.includes(tier)) return false;
    if (severities && !severities.has(row.finding.severity)) return false;
    return true;
  });
}

export function locationLabel(f) {
  if (f.line) return f.col ? `${f.line}:${f.col}` : `${f.line}`;
  return f.field_path || "";
}

// Collapse repeated line-anchored findings. Rows with the same id, the same
// severity and the same tier set, each anchored to a line and carrying no
// field_path, become one group row when there are at least two of them:
//   { group: true, key, finding (the earliest member's), members, lines,
//     tiers, count }
// Every other row is returned unchanged. Output order follows compareRows
// with a group positioned at its first line, so a group of bare-LF
// warnings starting on line 2 sits where line 2's finding would.
export function groupRows(rows) {
  const groups = new Map();
  const order = [];
  for (const row of rows) {
    const f = row.finding;
    const groupable = f.line > 0 && !f.field_path && f.id;
    const key = groupable ? `${f.id}|${f.severity}|${row.tiers.join(",")}` : null;
    if (key && groups.has(key)) {
      groups.get(key).members.push(row);
      continue;
    }
    const entry = { key, members: [row] };
    if (key) groups.set(key, entry);
    order.push(entry);
  }
  return order
    .map(({ key, members }) => {
      if (members.length === 1) return members[0];
      const sorted = [...members].sort(compareRows);
      return {
        group: true,
        key: `group|${key}`,
        finding: sorted[0].finding,
        members: sorted,
        lines: sorted.map((m) => m.finding.line),
        tiers: sorted[0].tiers,
        count: sorted.length,
      };
    })
    .sort(compareRows);
}
