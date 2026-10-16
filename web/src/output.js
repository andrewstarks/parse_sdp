// output.js — the current document in one of three formats (SDP, JSON, Lua
// table literal). Owns both the sticky-bar actions (format, Download, Copy)
// and the read-only Output section (format, Copy, rendered text); the two
// format selects share one piece of state. Diff markers apply to the SDP
// view only, comparing against the document as first parsed.

import { h, replace, setText } from "./dom.js";
import { diffLines, diffSummary } from "./diff.js";
import { splitLines, toCRLF } from "./format.js";
import { toLuaLiteral } from "./lua_literal.js";

const FORMATS = {
  sdp: { ext: "sdp", mime: "application/sdp", label: "SDP" },
  json: { ext: "json", mime: "application/json", label: "JSON" },
  lua: { ext: "lua", mime: "text/x-lua", label: "Lua table literal" },
};

function download(name, text, type) {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = h("a", { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function initOutput({ section, bar }) {
  const status = section.querySelector("#output-status");
  const lines = section.querySelector("#output-lines");
  const statuses = [bar.querySelector("#bar-status"), section.querySelector("#copy-status")];
  const selects = [bar.querySelector("#out-format-top"), section.querySelector("#out-format")];
  const downloadBtn = bar.querySelector("#out-download");
  const copyBtns = [bar.querySelector("#out-copy-top"), section.querySelector("#out-copy")];

  let format = "sdp";
  let current = { text: "", baseline: "", edited: false, doc: null, stem: "session" };

  // Text for the selected format, or null when it cannot be produced.
  function textFor(fmt) {
    if (fmt === "sdp") return current.text ? toCRLF(current.text) : null;
    if (!current.doc) return null;
    if (fmt === "json") return JSON.stringify(current.doc, null, 2) + "\n";
    return toLuaLiteral(current.doc);
  }

  function flash(message) {
    for (const el of statuses) setText(el, message);
    setTimeout(() => { for (const el of statuses) setText(el, ""); }, 2500);
  }

  async function copy() {
    const text = textFor(format);
    if (text === null) return;
    try {
      await navigator.clipboard.writeText(text);
      flash(`${FORMATS[format].label} copied.`);
    } catch {
      flash("Clipboard unavailable; use Download.");
    }
  }

  function setFormat(fmt) {
    format = fmt in FORMATS ? fmt : "sdp";
    for (const sel of selects) sel.value = format;
    renderLines();
  }

  for (const sel of selects) sel.addEventListener("change", () => setFormat(sel.value));
  for (const btn of copyBtns) btn.addEventListener("click", copy);
  downloadBtn.addEventListener("click", () => {
    const text = textFor(format);
    if (text !== null) download(`${current.stem}.${FORMATS[format].ext}`, text, FORMATS[format].mime);
  });

  function updateControls() {
    const available = textFor(format) !== null;
    const any = Boolean(current.doc || current.text);
    for (const sel of selects) sel.disabled = !any;
    downloadBtn.disabled = !available;
    for (const btn of copyBtns) btn.disabled = !available;
    const title = available ? `${FORMATS[format].label} (${current.stem}.${FORMATS[format].ext})` : "No document to output yet";
    downloadBtn.title = `Download ${title}`;
    for (const btn of copyBtns) btn.title = `Copy ${title}`;
  }

  function row(n, mark, type, line) {
    return h("li", { class: type },
      h("span", { class: "ln" }, n === "" ? "" : String(n)),
      h("span", { class: "mark", "aria-label": type === "add" ? "added" : type === "del" ? "removed" : null }, mark),
      h("span", { class: "txt" }, line === "" ? " " : line));
  }

  function renderLines() {
    updateControls();
    const text = textFor(format);
    if (text === null) {
      const why = !current.doc && !current.text ? "Output appears here once an input has been analyzed."
        : format === "sdp" ? "The document could not be serialized; fix the field named in the editor."
          : "No document to render.";
      replace(lines, h("li", { class: "empty" }, why));
      setText(status, "");
      return;
    }
    const after = splitLines(text);
    if (format !== "sdp") {
      setText(status, format === "json" ? "Document table as JSON; accepted back as input." : "Lua table literal; accepted back as input and by the library's from_lua.");
      replace(lines, after.map((line, i) => row(i + 1, "", "same", line)));
      return;
    }
    if (!current.edited) {
      setText(status, "Serialized from the parsed document (CRLF, RFC 8866 field order).");
      replace(lines, after.map((line, i) => row(i + 1, "", "same", line)));
      return;
    }
    const entries = diffLines(splitLines(current.baseline), after);
    const s = diffSummary(entries);
    setText(status, s.changed
      ? `Edited: ${s.added} line${s.added === 1 ? "" : "s"} added, ${s.removed} removed, compared with the document as first parsed.`
      : "Edited; serialized text is identical to the document as first parsed.");
    let n = 0;
    replace(lines, entries.map((e) => row(e.type === "del" ? "" : ++n, e.type === "add" ? "+" : e.type === "del" ? "−" : "", e.type, e.text)));
  }

  // text: current serialized SDP ("" when unavailable); baseline: the
  // pre-edit serialization; doc: the working document table.
  function render({ text, baseline, edited, doc, stem }) {
    current = { text: text ?? "", baseline: baseline ?? "", edited: Boolean(edited), doc: doc ?? null, stem: stem || "session" };
    renderLines();
  }

  setFormat("sdp");
  render({ text: "", doc: null });
  return { render, setFormat, getFormat: () => format };
}
