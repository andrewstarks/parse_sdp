local M = {}

local function err(msg)
  return { message = msg, line = 0, col = 0, context = "" }
end

function M.sdp(doc)
  if type(doc) ~= "table" then
    return nil, err("doc must be a table")
  end
  if doc.version ~= "0" then
    return nil, err("version must be '0'")
  end

  local o = doc.origin
  if type(o) ~= "table" then
    return nil, err("origin is required")
  end
  for _, f in ipairs({ "username", "sess_id", "sess_version",
                        "net_type", "addr_type", "unicast_address" }) do
    if type(o[f]) ~= "string" then
      return nil, err("origin." .. f .. " is required")
    end
  end
  if o.net_type ~= "IN" then
    return nil, err("origin.net_type must be 'IN'")
  end
  if o.addr_type ~= "IP4" and o.addr_type ~= "IP6" then
    return nil, err("origin.addr_type must be 'IP4' or 'IP6'")
  end

  local s = doc.session
  if type(s) ~= "table" then
    return nil, err("session is required")
  end
  if type(s.name) ~= "string" or s.name == "" then
    return nil, err("session.name is required")
  end
  local t = s.timing
  if type(t) ~= "table" or type(t.start) ~= "number" or type(t.stop) ~= "number" then
    return nil, err("session.timing with numeric start and stop is required")
  end

  if type(doc.media) ~= "table" then
    return nil, err("media must be a table")
  end
  for i, m in ipairs(doc.media) do
    if type(m.media) ~= "string" or m.media == "" then
      return nil, err(string.format("media[%d].media is required", i))
    end
    if type(m.port) ~= "number" then
      return nil, err(string.format("media[%d].port must be a number", i))
    end
    if type(m.proto) ~= "string" or m.proto == "" then
      return nil, err(string.format("media[%d].proto is required", i))
    end
    if type(m.fmts) ~= "table" or #m.fmts < 1 then
      return nil, err(string.format("media[%d].fmts must be non-empty", i))
    end
  end

  return true
end

return M
