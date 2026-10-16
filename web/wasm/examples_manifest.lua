-- Emit examples/index.json for the UI's example picker. Arguments: the
-- repo-relative .sdp paths in display order. Each entry carries the file's
-- own s= session name (RFC 8866 §5.3) as "title" so the display name lives
-- in the SDP itself; "" when the file has none.
local function json_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end

local out = {}
for _, path in ipairs(arg) do
  local tier, status, name = path:match("^examples/([^/]+)/([^/]+)/(.-)%.sdp$")
  local title = ""
  for line in io.lines(path) do
    local s = line:match("^s=(.-)\r?$")
    if s then title = s; break end
  end
  out[#out + 1] = string.format(
    '  {"tier":%s,"status":%s,"name":%s,"title":%s,"path":%s}',
    json_string(tier), json_string(status), json_string(name),
    json_string(title), json_string(path))
end
io.write("[\n", table.concat(out, ",\n"), "\n]\n")
