local M = {}

local function err(msg, code)
  return { message = msg, line = 0, col = 0, context = "", code = code }
end

function M.sdp(doc)
  if type(doc) ~= "table" then
    return nil, err("doc must be a table", "INVALID_VALUE")
  end
  if doc.version ~= "0" then
    return nil, err("version must be '0'", "INVALID_VALUE")
  end

  local o = doc.origin
  if type(o) ~= "table" then
    return nil, err("origin is required", "MISSING_FIELD")
  end
  for _, f in ipairs({ "username", "sess_id", "sess_version",
                        "net_type", "addr_type", "unicast_address" }) do
    if type(o[f]) ~= "string" then
      return nil, err("origin." .. f .. " is required", "MISSING_FIELD")
    end
  end
  if o.net_type ~= "IN" then
    return nil, err("origin.net_type must be 'IN'", "INVALID_VALUE")
  end
  if o.addr_type ~= "IP4" and o.addr_type ~= "IP6" then
    return nil, err("origin.addr_type must be 'IP4' or 'IP6'", "INVALID_VALUE")
  end

  local s = doc.session
  if type(s) ~= "table" then
    return nil, err("session is required", "MISSING_FIELD")
  end
  if type(s.name) ~= "string" or s.name == "" then
    return nil, err("session.name is required", "MISSING_FIELD")
  end
  local t = s.timing
  if type(t) ~= "table" or type(t.start) ~= "number" or type(t.stop) ~= "number" then
    return nil, err("session.timing with numeric start and stop is required", "MISSING_FIELD")
  end

  if type(doc.media) ~= "table" then
    return nil, err("media must be a table", "INVALID_VALUE")
  end
  for i, m in ipairs(doc.media) do
    if type(m.media) ~= "string" or m.media == "" then
      return nil, err(string.format("media[%d].media is required", i), "MISSING_FIELD")
    end
    if type(m.port) ~= "number" then
      return nil, err(string.format("media[%d].port must be a number", i), "INVALID_VALUE")
    end
    if type(m.proto) ~= "string" or m.proto == "" then
      return nil, err(string.format("media[%d].proto is required", i), "MISSING_FIELD")
    end
    if type(m.fmts) ~= "table" or #m.fmts < 1 then
      return nil, err(string.format("media[%d].fmts must be non-empty", i), "MISSING_FIELD")
    end
  end

  return true
end

return M
