package = "parse_sdp"
version = "0.1.0-1"

source = {
  url  = "git+https://github.com/andrewstarks/parse_sdp.git",
  tag  = "v0.1.0",
}

description = {
  summary  = "Strict SDP parser, validator, and serializer for RFC 4566 / SMPTE ST 2110 / IPMX",
  detailed = [[
parse_sdp is a Lua library that parses, validates, and serializes Session
Description Protocol (SDP) documents at three conformance tiers:

  1. RFC 4566 — generic SDP well-formedness
  2. SMPTE ST 2110 — broadcast-grade media transport
  3. IPMX (VSF TR-10 suite) — interoperability profile for ST 2110

Every check is grounded in an explicit "shall" / "shall not" clause from the
referenced specification.  Validation errors carry a machine-readable error code
and a human-readable spec citation so callers can report exactly what failed and
why.

The library also ships a CLI (parse_sdp parse / parse_sdp serialize) that reads
and writes SDP files from the command line.
  ]],
  homepage = "https://github.com/andrewstarks/parse_sdp",
  license  = "MIT",
}

-- argparse is only loaded when parse_sdp.lua is run as a CLI binary; it is not
-- required for library use via require("parse_sdp").  Install it separately if
-- you want the CLI: luarocks install argparse
dependencies = {
  "lua >= 5.5",
  "lpeg",
  "dkjson",
}

build = {
  type    = "builtin",
  modules = {
    parse_sdp = "parse_sdp.lua",
  },
  install = {
    bin = {
      parse_sdp = "parse_sdp.lua",
    },
  },
}
