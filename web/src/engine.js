// web/src/engine.js — JS side of the parse_sdp WebAssembly engine.
// See web/CONTRACT.md. The only thing the UI talks to.

import createParseSdpModule from "./parse_sdp.js";

// options.locateFile(path, prefix) lets a host page relocate parse_sdp.wasm.
export async function createEngine(options = {}) {
  const moduleOptions = {};
  if (options.locateFile) moduleOptions.locateFile = options.locateFile;
  const mod = await createParseSdpModule(moduleOptions);
  const sdpRequest = mod.cwrap("sdp_request", "string", ["string"]);

  const request = async (obj) => JSON.parse(sdpRequest(JSON.stringify(obj)));
  const version = await request({ op: "version" });
  return { request, version };
}
