#!/usr/bin/env lua
local parser    = require("lib.parser")
local validate  = require("lib.validate")
local serialize = require("lib.serialize")
local st2110    = require("lib.st2110")
local ipmx      = require("lib.ipmx")
local errors    = require("lib.errors")
local dkjson    = require("dkjson")

local M  = {}
local mt = {}
mt.__index = mt

function mt:validate(mode)
  mode = mode or "sdp"
  if mode == "sdp"    then return validate.sdp(self) end
  if mode == "st2110" then return st2110.st2110(self) end
  if mode == "ipmx"   then return ipmx.ipmx(self) end
  return nil, errors.new("unknown mode: " .. tostring(mode))
end

function mt:is_sdp()
  return validate.sdp(self) == true
end

function mt:to_json()
  return dkjson.encode(self)
end

function mt:to_sdp()
  return serialize.serialize(self)
end

function mt:is_st2110()
  return st2110.st2110(self) == true
end

function mt:is_ipmx()
  return ipmx.ipmx(self) == true
end

function M.parse(text, mode)
  local doc, e = parser.parse(text, mode)
  if not doc then return nil, e end
  return setmetatable(doc, mt)
end

function M.new(t)
  return setmetatable(t, mt)
end

-- ── CLI (detect-if-main) ─────────────────────────────────────────────────────
if arg and arg[0] and arg[0]:match("parse_sdp") then
  local argparse = require("argparse")

  local function die(err_table)
    io.stderr:write(errors.format(err_table) .. "\n")
    os.exit(1)
  end

  local function read_input(file)
    if file then
      local f, ioerr = io.open(file, "r")
      if not f then die(errors.new("cannot open file: " .. (ioerr or file))); return end
      local text = f:read("*a")
      f:close()
      return text
    end
    return io.read("*a")
  end

  local ap = argparse("parse_sdp", "Parse, validate, and serialize SDP (RFC 4566 / ST 2110 / IPMX).")
  ap:epilog(table.concat({
    "Examples:",
    "  parse_sdp parse session.sdp",
    "  parse_sdp parse --mode st2110 --pretty session.sdp",
    "  parse_sdp parse < session.sdp | parse_sdp serialize",
    "  parse_sdp serialize session.json",
  }, "\n"))
  ap:command_target("command")

  local cmd_parse = ap:command("parse", "Parse and validate an SDP file; output JSON.")
  cmd_parse:argument("file", "Path to .sdp file. Reads stdin if omitted."):args("?")
  cmd_parse:option("--mode", "Validation tier: 'st2110' or 'ipmx'. Defaults to RFC 4566 only.")
  cmd_parse:flag("--pretty", "Pretty-print JSON output with indentation.")

  local cmd_ser = ap:command("serialize", "Convert a JSON SDP document back to SDP text.")
  cmd_ser:argument("file", "Path to .json file. Reads stdin if omitted."):args("?")

  local parsed = ap:parse()

  if parsed.command == "parse" then
    local text = read_input(parsed.file)
    local doc, perr = M.parse(text, parsed.mode)
    if not doc then die(perr) end
    local encode_opts = parsed.pretty and { indent = true } or nil
    io.write(dkjson.encode(doc, encode_opts) .. "\n")
    os.exit(0)

  elseif parsed.command == "serialize" then
    local json_text = read_input(parsed.file)
    local tbl, _, jsonerr = dkjson.decode(json_text)
    if not tbl then
      die(errors.new("invalid JSON: " .. (jsonerr or "parse error")))
    end
    local doc = M.new(tbl)
    local ok, result = pcall(function() return doc:to_sdp() end)
    if not ok then
      die(errors.new("serialize error: " .. tostring(result)))
    end
    io.write(result)
    os.exit(0)
  end
end

return M
