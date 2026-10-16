// input.js — paste area, drop zone, file picker and example buttons.
// Hands raw text (plus a file name for downloads) to the app; it never
// interprets the content itself.

import { h, replace, setText } from "./dom.js";

// onSubmit(text, fileName); fetchText(path) → Promise<string> for examples.
export function initInput(root, { onSubmit, fetchText }) {
  const textarea = root.querySelector("#input-text");
  const dropZone = root.querySelector("#drop-zone");
  const fileInput = root.querySelector("#file-input");
  const meta = root.querySelector("#input-meta");
  const exampleSelect = root.querySelector("#example-select");
  const error = root.querySelector("#input-error");
  let fileName = "session";
  // A textarea normalises CR LF to LF, which would turn every CRLF file
  // into a wall of bare-LF warnings. Keep the text as loaded (or pasted)
  // and submit that while the textarea still shows it unchanged.
  let raw = null;
  const lfOnly = (t) => t.replace(/\r\n?/g, "\n");

  function currentText() {
    return raw !== null && textarea.value === lfOnly(raw) ? raw : textarea.value;
  }

  function submit() {
    onSubmit(currentText(), fileName);
  }

  function loadText(text, name) {
    fileName = name;
    raw = text;
    textarea.value = text;
    setText(meta, name === "session" ? "" : name);
    submit();
  }

  async function loadFile(file) {
    if (!file) return;
    loadText(await file.text(), file.name);
  }

  root.querySelector("#analyze").addEventListener("click", submit);
  textarea.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
      e.preventDefault();
      submit();
    }
  });
  textarea.addEventListener("input", () => {
    if (raw !== null && textarea.value !== lfOnly(raw)) raw = null;
  });
  textarea.addEventListener("paste", (e) => {
    const clip = e.clipboardData?.getData("text/plain") ?? "";
    // Let the paste land, then analyze what arrived (with its CRs when the
    // paste replaced the whole content).
    setTimeout(() => {
      raw = clip && textarea.value === lfOnly(clip) ? clip : null;
      fileName = "session";
      setText(meta, "");
      submit();
    }, 0);
  });
  fileInput.addEventListener("change", () => {
    loadFile(fileInput.files[0]);
    fileInput.value = "";
  });

  let dragDepth = 0;
  dropZone.addEventListener("dragenter", (e) => {
    e.preventDefault();
    dragDepth++;
    dropZone.classList.add("is-dragging");
  });
  dropZone.addEventListener("dragover", (e) => e.preventDefault());
  dropZone.addEventListener("dragleave", () => {
    if (--dragDepth <= 0) {
      dragDepth = 0;
      dropZone.classList.remove("is-dragging");
    }
  });
  dropZone.addEventListener("drop", (e) => {
    e.preventDefault();
    dragDepth = 0;
    dropZone.classList.remove("is-dragging");
    const file = e.dataTransfer?.files?.[0];
    if (file) loadFile(file);
    else {
      const text = e.dataTransfer?.getData("text/plain");
      if (text) loadText(text, "session");
    }
  });

  exampleSelect.addEventListener("change", async () => {
    const path = exampleSelect.value;
    if (!path) return;
    showError(null);
    try {
      loadText(await fetchText(path), path.split("/").pop());
    } catch (e) {
      showError(`Could not load example: ${e.message}`);
    }
  });

  // groups: [{ label, items: [{ label, path }] }] from examples.js.
  function setExamples(groups) {
    replace(exampleSelect, h("option", { value: "" }, "Load an example…"),
      groups.map((g) => h("optgroup", { label: g.label }, g.items.map((it) => h("option", { value: it.path }, it.label)))));
  }

  function showError(message) {
    setText(error, message ?? "");
    error.hidden = !message;
  }

  return { showError, setExamples, getText: () => textarea.value, getFileName: () => fileName };
}
