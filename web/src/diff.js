// diff.js — line diff for the output view. Pure.
// Classic LCS over lines; SDP files are small enough that O(n·m) is fine.

// Returns [{ type: "same" | "add" | "del", text }], in output order.
export function diffLines(before, after) {
  const a = before;
  const b = after;
  const n = a.length;
  const m = b.length;
  const lcs = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  const out = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) {
      out.push({ type: "same", text: a[i] });
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.push({ type: "del", text: a[i++] });
    } else {
      out.push({ type: "add", text: b[j++] });
    }
  }
  while (i < n) out.push({ type: "del", text: a[i++] });
  while (j < m) out.push({ type: "add", text: b[j++] });
  return out;
}

export function diffSummary(entries) {
  let added = 0;
  let removed = 0;
  for (const e of entries) {
    if (e.type === "add") added++;
    else if (e.type === "del") removed++;
  }
  return { added, removed, changed: added + removed > 0 };
}
