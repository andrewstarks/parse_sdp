local M = {}

local function ipmx_err(msg, field_path, spec_ref, code)
  return {
    message    = msg,
    line       = 0,
    col        = 0,
    context    = "",
    field_path = field_path or "",
    spec_ref   = spec_ref or "",
    code       = code or "MISSING_FIELD",
  }
end

local function find_attr(attrs, name)
  for _, a in ipairs(attrs or {}) do
    if a.name == name then return a end
  end
end

function M.ipmx(doc)
  local st2110 = require("lib.st2110")
  local ok, e = st2110.st2110(doc)
  if not ok then return nil, e end

  -- a=extmap must appear at session level or in at least one media block
  local has_extmap = find_attr(doc.session.attributes, "extmap") ~= nil
  if not has_extmap then
    for _, m in ipairs(doc.media) do
      if find_attr(m.attributes or {}, "extmap") then
        has_extmap = true
        break
      end
    end
  end

  if not has_extmap then
    return nil, ipmx_err(
      "missing required attribute 'extmap'",
      "session.attributes[extmap]",
      "IPMX §6"
    )
  end

  return true
end

return M
