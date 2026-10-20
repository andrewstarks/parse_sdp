// capture.mjs — retakes the screenshots in web/manual/img/ for MANUAL.md.
//
// Usage, from web/ after wasm/build.sh has produced dist/:
//   npm install --no-save playwright-core
//   node manual/capture.mjs
//
// The page is served from dist/ at the deployed address
// (https://andrewstarks.github.io/parse_sdp/), so it runs over HTTPS as
// users see it. Device URLs are answered by request routes; nothing goes
// to the network. Google Chrome must be installed. Every image is taken
// in the light color scheme at a 1200 px wide window, at 2x pixel density,
// and framed with a thin gray border and a faint shadow on a transparent
// margin, so a white screenshot stands out on a white page.

import { chromium } from "playwright-core";
import { readFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(HERE, "..", "dist");
const OUT = path.join(HERE, "img");
const SITE = "https://andrewstarks.github.io/parse_sdp/";
const WIDTH = 1200;
const TYPES = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css",
  ".wasm": "application/wasm", ".json": "application/json", ".sdp": "application/sdp" };

const DEVICE_URL = "http://192.0.2.10/x-nmos/connection/v1.1/single/senders/3f1d6c2e/transportfile";
const SHARED_URL = "https://device.example/x-nmos/connection/v1.1/single/senders/3f1d6c2e/transportfile";
const EX = {
  sampling: "examples/st2110/invalid/05_missing_sampling.sdp",
  missingFmtp: "examples/st2110/invalid/03_missing_fmtp.sdp",
  badPtime: "examples/st2110/invalid/09_bad_ptime.sdp",
  hdVideo: "examples/st2110/valid/03_typical_hd_video.sdp",
  multistream: "examples/st2110/valid/05_typical_multistream.sdp",
};

async function serve(context) {
  await context.route("https://github.com/**", (r) => r.abort());
  await context.route(`${SITE}**`, async (route) => {
    let rel = new URL(route.request().url()).pathname.slice("/parse_sdp/".length) || "index.html";
    try {
      const body = await readFile(path.join(DIST, rel));
      await route.fulfill({ status: 200, body, contentType: TYPES[path.extname(rel)] ?? "text/plain" });
    } catch {
      await route.fulfill({ status: 404, body: "not found" });
    }
  });
  // A device that sends CORS headers, and one the browser cannot reach.
  const sdp = await readFile(path.join(DIST, EX.hdVideo));
  await context.route(SHARED_URL, (r) => r.fulfill({ status: 200, body: sdp,
    contentType: "application/sdp", headers: { "Access-Control-Allow-Origin": "*" } }));
  await context.route(DEVICE_URL, (r) => r.abort("failed"));
}

async function open(browser, { query = "", width = WIDTH, height = 900 } = {}) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 2, colorScheme: "light" });
  await serve(context);
  const page = await context.newPage();
  await page.goto(SITE + query);
  await page.waitForFunction(() => !/Loading/.test(document.querySelector("#engine-status").textContent));
  return page;
}

async function settle(page) {
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(300);
}

async function example(page, file) {
  await page.selectOption("#example-select", file);
  await page.waitForFunction(() => document.querySelector("#tier-cards").textContent.includes("Pass")
    || document.querySelector("#tier-cards").textContent.includes("Fail"));
  await settle(page);
}

// Open an editor card and every finding disclosure in it.
async function openFindings(page, dataPath) {
  const card = page.locator(`#editor-root details[data-path="${dataPath}"]`);
  await card.evaluate((el) => { for (let d = el; d; d = d.parentElement?.closest("details")) d.open = true; });
  const btn = card.locator(":scope > summary .expand-findings");
  if ((await btn.getAttribute("aria-expanded")) !== "true") await btn.click();
  await settle(page);
}

// Draw the screenshot in a border and shadow and write it to img/<name>.png.
async function frame(name, png) {
  const width = png.readUInt32BE(16) / 2;
  const page = await framer.newPage();
  await page.setContent(`<body style="margin:0"><div style="display:inline-block;padding:6px 8px 10px">
    <img style="display:block;width:${width}px;border:1px solid #a3a3a3;border-radius:3px;
      box-shadow:0 1px 2px rgba(0,0,0,.08),0 2px 6px rgba(0,0,0,.06)"
      src="data:image/png;base64,${png.toString("base64")}"></div></body>`);
  await page.locator("div").screenshot({ path: path.join(OUT, `${name}.png`), omitBackground: true });
  await page.close();
  console.log(`${name}.png`);
}

// Screenshot the box that contains every element matched by `selectors`.
async function shot(page, name, selectors, pad = 12, maxHeight = Infinity) {
  const boxes = [];
  for (const s of [].concat(selectors)) {
    const loc = typeof s === "string" ? page.locator(s).first() : s;
    boxes.push(await loc.evaluate((el) => {
      const r = el.getBoundingClientRect();
      return { x: r.x + scrollX, y: r.y + scrollY, width: r.width, height: r.height };
    }));
  }
  await page.mouse.move(0, 0);
  await page.evaluate(() => window.scrollTo(0, 0));
  const width = page.viewportSize().width;
  const x0 = Math.max(0, Math.min(...boxes.map((b) => b.x)) - pad);
  const y0 = Math.max(0, Math.min(...boxes.map((b) => b.y)) - pad);
  const x1 = Math.min(width, Math.max(...boxes.map((b) => b.x + b.width)) + pad);
  const y1 = Math.max(...boxes.map((b) => b.y + b.height)) + pad;
  await frame(name, await page.screenshot({ fullPage: true,
    clip: { x: x0, y: y0, width: x1 - x0, height: Math.min(y1 - y0, maxHeight) } }));
}

await mkdir(OUT, { recursive: true });
const browser = await chromium.launch({ channel: "chrome" });
const framer = await browser.newContext({ deviceScaleFactor: 2 });

// Header: engine label and the output bar.
{
  const page = await open(browser);
  await example(page, EX.sampling);
  await page.evaluate(() => window.scrollTo(0, 0));
  await shot(page, "header", ".site-header", 0);
  await page.context().close();
}
{
  const page = await open(browser, { query: "?mock=1" });
  await shot(page, "engine-mock", "#engine-status", 8);
  await page.context().close();
}

// Input panel with an example loaded; an input that cannot be read.
{
  const page = await open(browser);
  await example(page, EX.sampling);
  await shot(page, "input", "#input");
  await page.fill("#input-text", "{ origin = { username = }");
  await page.click("#analyze");
  await page.waitForSelector("#input-error:not([hidden])");
  await shot(page, "input-error", ["#input-text", "#input-error"]);
  await page.context().close();
}

// From URL: a loaded file with Copy link, and a request that failed.
{
  const page = await open(browser);
  await page.fill("#url-input", SHARED_URL);
  await page.click("#url-form button[type=submit]");
  await page.waitForSelector("#copy-link:not([hidden])");
  await settle(page);
  await shot(page, "url-loaded", ["#url-form", "#input > div.toolbar"]);
  await page.fill("#url-input", DEVICE_URL);
  await page.click("#url-form button[type=submit]");
  await page.waitForSelector("#url-error:not([hidden])");
  await shot(page, "url-error", ["#url-form", "#url-error"]);
  await page.context().close();
}

// Report: tier cards and filters; a clicked finding and its source line.
{
  const page = await open(browser);
  await example(page, EX.sampling);
  await shot(page, "tier-cards", ["#report .panel-head", "#report .filters"]);
  await page.locator("#findings .finding").first().click();
  await settle(page);
  await shot(page, "findings", "#report .report-grid");
  await page.context().close();
}

// Pasted LF text: a collapsed multi-line row, opened, and the LF note.
{
  const page = await open(browser);
  const text = (await readFile(path.join(DIST, EX.multistream), "utf8")).replace(/\r\n/g, "\n");
  await page.fill("#input-text", text);
  await page.click("#analyze");
  await page.waitForSelector("#crlf-note:not([hidden])");
  await settle(page);
  await page.locator("#input-text").evaluate((el) => { el.scrollTop = 0; });
  await shot(page, "crlf-note", ["#drop-zone", "#crlf-note"]);
  await page.locator("#findings .finding-group > button").first().click();
  await page.locator("#findings .group-lines .line-chip").nth(2).click();
  await settle(page);
  await shot(page, "finding-group", ["#findings .finding-group", "#report .source-view"]);
  await page.context().close();
}

// Policy panel: one override, one check off, and a fixed check in view.
{
  const page = await open(browser);
  await example(page, EX.sampling);
  await page.click("#policy-toggle");
  await page.fill("#policy-filter", "st2110-20.a.fmtp");
  await page.locator('#policy-groups select[aria-label="Severity for st2110-20.a.fmtp.sampling-required"]').selectOption("warn");
  await settle(page);
  await page.locator('#policy-groups select[aria-label="Severity for st2110-20.a.fmtp.width-required"]').selectOption("off");
  await settle(page);
  await page.fill("#policy-filter", "fmtp.s");
  await shot(page, "policy", ["#report .filters", "#policy-panel"], 12, 1000);
  await page.fill("#policy-filter", "fmtp.malformed");
  await shot(page, "policy-fixed", "#policy-panel", 12, 700);
  await page.fill("#policy-filter", "");
  await page.click("#policy-reset");
  await page.context().close();
}

// Document editor: summary, card badges, open disclosures, line badge.
{
  const page = await open(browser);
  await example(page, EX.sampling);
  await shot(page, "editor-summary", "#editor-summary");
  await openFindings(page, "media[0].attributes[1]");
  const fmtp = page.locator('#editor-root details[data-path="media[0].attributes[1]"]');
  await shot(page, "editor-findings", [fmtp.locator(":scope > summary"), fmtp.locator(".fdisc").nth(1)]);
  await page.context().close();
}
{
  const page = await open(browser);
  await example(page, EX.missingFmtp);
  await openFindings(page, "media[0]");
  const host = page.locator('#editor-root [data-path="media[0].attributes"] > .field-findings');
  await shot(page, "editor-missing", [host.locator(".fdisc").nth(0), host.locator(".fdisc").nth(1)]);
  await page.context().close();
}
{
  const page = await open(browser);
  await example(page, EX.badPtime);
  await openFindings(page, "media[0].attributes[3]");
  await shot(page, "editor-line-badge", 'details[data-path="media[0].attributes[3]"]');
  await page.context().close();
}

// fmtp parameters with a flag, then an edit and its output diff.
{
  const page = await open(browser);
  await example(page, EX.hdVideo);
  const fmtp = page.locator('#editor-root details[data-path="media[0].attributes[1]"]');
  await fmtp.evaluate((el) => { el.open = true; });
  const params = fmtp.locator(".params");
  await shot(page, "editor-fmtp", params, 8);
  const width = params.locator(".param-row").nth(1).locator("input").nth(1);
  await width.fill("1280");
  await width.press("Tab");
  await settle(page);
  await shot(page, "output-diff", "#output");
  await page.locator('.row[data-path="media[0].port"] button[aria-label="Remove port"]').click();
  await page.waitForSelector("#serialize-error:not([hidden])");
  await settle(page);
  const media = page.locator('#editor-root details[data-path="media[0]"]');
  await shot(page, "serialize-error", [media.locator(":scope > summary"), media.locator(".fdisc").first(),
    page.locator('#editor-root .row[data-path="media[0].proto"]')]);
  await shot(page, "report-stale", ["#report .panel-head", "#tier-cards"]);
  await page.context().close();
}

// Narrow window: the sections menu.
{
  const page = await open(browser, { width: 420, height: 700 });
  await page.click("#nav-toggle");
  await settle(page);
  await frame("narrow-menu", await page.screenshot({ clip: { x: 0, y: 0, width: 420, height: 360 } }));
  await page.context().close();
}

await browser.close();
