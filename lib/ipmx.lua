local util   = require("lib.util")
local errors = require("lib.errors")
local M = {}

local find_attr = util.find_attr

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
    return nil, errors.new("missing required attribute 'extmap'", {
      field_path = "session.attributes[extmap]",
      spec_ref   = "IPMX §6",
    })
  end

  return true
end

return M
