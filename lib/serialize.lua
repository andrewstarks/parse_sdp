local M = {}

local function ln(t, v)
  return t .. "=" .. v .. "\r\n"
end

local function serialize_connection(c)
  return ln("c", c.net_type .. " " .. c.addr_type .. " " .. c.address)
end

local function serialize_bandwidth(b)
  return ln("b", b.type .. ":" .. tostring(b.value))
end

local function serialize_attribute(a)
  if a.value then
    return ln("a", a.name .. ":" .. a.value)
  end
  return ln("a", a.name)
end

local function serialize_media_block(m)
  local port_field = tostring(m.port)
  if m.port_count then
    port_field = port_field .. "/" .. tostring(m.port_count)
  end
  local out = ln("m", m.media .. " " .. port_field .. " " .. m.proto
                      .. " " .. table.concat(m.fmts, " "))
  if m.info       then out = out .. ln("i", m.info) end
  if m.connection then out = out .. serialize_connection(m.connection) end
  for _, b in ipairs(m.bandwidths or {}) do out = out .. serialize_bandwidth(b) end
  for _, a in ipairs(m.attributes or {}) do out = out .. serialize_attribute(a) end
  return out
end

function M.serialize(doc)
  local s   = doc.session
  local o   = doc.origin
  local out = ""

  out = out .. ln("v", doc.version)
  out = out .. ln("o", o.username .. " " .. o.sess_id .. " " .. o.sess_version
                       .. " " .. o.net_type .. " " .. o.addr_type
                       .. " " .. o.unicast_address)
  out = out .. ln("s", s.name)

  if s.info then out = out .. ln("i", s.info) end
  if s.uri  then out = out .. ln("u", s.uri) end
  for _, e in ipairs(s.emails     or {}) do out = out .. ln("e", e) end
  for _, p in ipairs(s.phones     or {}) do out = out .. ln("p", p) end
  if s.connection then out = out .. serialize_connection(s.connection) end
  for _, b in ipairs(s.bandwidths or {}) do out = out .. serialize_bandwidth(b) end

  out = out .. ln("t", tostring(s.timing.start) .. " " .. tostring(s.timing.stop))

  for _, a in ipairs(s.attributes or {}) do out = out .. serialize_attribute(a) end
  for _, m in ipairs(doc.media    or {}) do out = out .. serialize_media_block(m) end

  return out
end

return M
