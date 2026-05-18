package = "parse_sdp"
version = "1.0.0-1"

source = {
  url  = "git+https://github.com/andrewstarks/parse_sdp.git",
  tag  = "v1.0.0",
}

description = {
  summary  = "Strict SDP parser, validator, and serializer for RFC 8866 / SMPTE ST 2110 / IPMX",
  detailed = [[
parse_sdp is a Lua library that parses, validates, and serializes Session
Description Protocol (SDP) documents at three conformance tiers:

  1. RFC 8866 — generic SDP well-formedness (RFC 8866 obsoletes RFC 4566)
  2. SMPTE ST 2110 — broadcast-grade media transport
  3. IPMX (VSF TR-10 suite) — interoperability profile for ST 2110

Every check is grounded in an explicit "shall" / "shall not" clause from the
referenced specification.  Validation errors carry a machine-readable error code
and a human-readable spec citation so callers can report exactly what failed and
why.

The library also ships a CLI (parse_sdp to_json / parse_sdp to_sdp) that reads
and writes SDP files from the command line.
  ]],
  homepage = "https://github.com/andrewstarks/parse_sdp",
  license  = "MIT",
}

-- argparse is only used by the CLI binary; require("parse_sdp") never loads it.
dependencies = {
  "lua >= 5.5",
  "lpeg",
  "dkjson",
  "argparse",
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
