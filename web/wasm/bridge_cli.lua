-- Native harness for bridge.lua: reads one JSON request on stdin, writes
-- the JSON response on stdout. Run from the repo root:
--   lua web/wasm/bridge_cli.lua < request.json
package.path = "./?.lua;./?/init.lua;./web/wasm/?.lua;" .. package.path
io.write(require("bridge").handle(io.read("*a")), "\n")
