-- Minimal Jinja2 subset for the upstream AMWA nmos-testing templates.
-- Supports exactly the forms found in test_data/sdp/*.sdp:
--   {{ name }}                                — variable substitution
--   {{ "literal" if name }}                   — emit literal if var truthy, else ""
--   {{ "...{}...".format(name) if name }}     — Python format with single arg

local lpeg = require("lpeg")
local P, R, S, C, Cs = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Cs

local space = S(" \t")^0
local ident = C((R("az", "AZ", "09") + P("_"))^1)
local strlit = P('"') * C((1 - P('"'))^0) * P('"')

local function truthy(v)
  if v == nil or v == false or v == "" then return false end
  return true
end

return function(template, vars)
  local function lookup(name)
    local v = vars[name]
    if v == nil then
      error("template variable not provided: " .. name)
    end
    return tostring(v)
  end

  local cond_format = P("{{") * space * strlit * space * P(".format(") * space * ident * space * P(")")
                      * space * P("if") * space * ident * space * P("}}") /
    function(fmt, fmt_arg, cond_var)
      if not truthy(vars[cond_var]) then return "" end
      return (fmt:gsub("{}", lookup(fmt_arg)))
    end

  local cond_literal = P("{{") * space * strlit * space * P("if") * space * ident * space * P("}}") /
    function(lit, cond_var)
      if truthy(vars[cond_var]) then return lit end
      return ""
    end

  local plain = P("{{") * space * ident * space * P("}}") / lookup

  local expr = cond_format + cond_literal + plain
  local doc = Cs((expr + 1)^0)
  return doc:match(template)
end
