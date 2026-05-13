# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- M2: `lib/grammar.lua` — LPEG line tokenizer: `grammar.tokenize_line(s)` parses `<alpha>=<value><CRLF|LF|EOS>`, returns type char, value string, and byte offset of value start; returns `nil, fail_pos` on malformed input
- M2: grammar tests in `spec/sdp_spec.lua` — valid CRLF, LF-only, no-newline lines; rejects empty input, no-equals, multi-char type, non-alpha type, empty value; verifies failure positions
- M1: `parse_sdp.lua` stub — exports `parse` (returns `nil, {message="not implemented"}`) and `new`
- M1: `spec/sdp_spec.lua` smoke test — `require("parse_sdp")` loads without error
- M1: `.busted` config
- M1: `Dockerfile` and `docker-compose.yml` — Lua 5.5 + LuaRocks (HEAD) + lpeg + dkjson + busted
- M1: directory layout — `lib/`, `spec/`, `spec/fixtures/`
- Initial project structure: `README.md`, `GUIDE.md`, `PLAN.md`, `CLAUDE.md`, `CHANGELOG.md`
- Project name: `parse_sdp` (renamed from `sdp_parser`)
- Full API design: `sdp.parse(text[, mode])`, `sdp.new(table)`, doc object with `validate`, `serialize`, `to_json`, `is_sdp`, `is_st2110`, `is_ipmx` methods
- CLI design: `parse_sdp parse` and `parse_sdp serialize` subcommands
- 13-milestone implementation plan replacing original 6-phase structure
- dkjson selected as JSON dependency (pure Lua, LuaRocks)
- Strictness established as a primary design principle: pedantic RFC 4566 enforcement, no lenient mode

### Notes

- LuaRocks 3.12.1 (latest stable) does not support Lua 5.5; Dockerfile pins to LuaRocks HEAD commit `fc402072` pending an official release
