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

return M
