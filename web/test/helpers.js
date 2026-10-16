// Shared test helpers: read fixtures from disk for the mock engine.
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

export const SRC = fileURLToPath(new URL("../src/", import.meta.url));
export const FIXTURES = fileURLToPath(new URL("../fixtures/", import.meta.url));

// Loader with the same signature the mock uses in the browser.
export async function fsLoader(relPath) {
  const text = await readFile(new URL(relPath, `file://${SRC}`), "utf8");
  return relPath.endsWith(".json") ? JSON.parse(text) : text;
}

export async function fixtureText(name) {
  return readFile(`${FIXTURES}${name}`, "utf8");
}

export async function fixtureJson(name) {
  return JSON.parse(await fixtureText(name));
}
