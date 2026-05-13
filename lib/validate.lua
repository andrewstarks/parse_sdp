local errors = require("lib.errors")
local M = {}

function M.sdp(doc)
  if type(doc) ~= "table" then
    return nil, errors.new("doc must be a table", { code = "INVALID_VALUE" })
  end
  if doc.version ~= "0" then
    return nil, errors.new("version must be '0'", { code = "INVALID_VALUE" })
  end

  local o = doc.origin
  if type(o) ~= "table" then
    return nil, errors.new("origin is required", { code = "MISSING_FIELD" })
  end
  for _, f in ipairs({ "username", "sess_id", "sess_version",
                        "net_type", "addr_type", "unicast_address" }) do
    if type(o[f]) ~= "string" then
      return nil, errors.new("origin." .. f .. " is required", { code = "MISSING_FIELD" })
    end
  end
  if o.net_type ~= "IN" then
    return nil, errors.new("origin.net_type must be 'IN'", { code = "INVALID_VALUE" })
  end
  if o.addr_type ~= "IP4" and o.addr_type ~= "IP6" then
    return nil, errors.new("origin.addr_type must be 'IP4' or 'IP6'", { code = "INVALID_VALUE" })
  end

  local s = doc.session
  if type(s) ~= "table" then
    return nil, errors.new("session is required", { code = "MISSING_FIELD" })
  end
  if type(s.name) ~= "string" or s.name == "" then
    return nil, errors.new("session.name is required", { code = "MISSING_FIELD" })
  end
  local t = s.timing
  if type(t) ~= "table" or type(t.start) ~= "number" or type(t.stop) ~= "number" then
    return nil, errors.new("session.timing with numeric start and stop is required",
      { code = "MISSING_FIELD" })
  end

  if type(doc.media) ~= "table" then
    return nil, errors.new("media must be a table", { code = "INVALID_VALUE" })
  end
  for i, m in ipairs(doc.media) do
    if type(m.media) ~= "string" or m.media == "" then
      return nil, errors.new(string.format("media[%d].media is required", i),
        { code = "MISSING_FIELD" })
    end
    if type(m.port) ~= "number" then
      return nil, errors.new(string.format("media[%d].port must be a number", i),
        { code = "INVALID_VALUE" })
    end
    if type(m.proto) ~= "string" or m.proto == "" then
      return nil, errors.new(string.format("media[%d].proto is required", i),
        { code = "MISSING_FIELD" })
    end
    if type(m.fmts) ~= "table" or #m.fmts < 1 then
      return nil, errors.new(string.format("media[%d].fmts must be non-empty", i),
        { code = "MISSING_FIELD" })
    end
  end

  return true
end

return M
