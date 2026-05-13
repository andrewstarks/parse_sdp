local util   = require("lib.util")
local errors = require("lib.errors")
local M = {}

local find_attr = util.find_attr

-- Parse clock rate from rtpmap value "PT encoding-name/clock-rate[/params]"
local function rtpmap_clock_rate(value)
  local rest = value:match("^%d+%s+(.+)$")
  if not rest then return nil end
  local rate = rest:match("^[^/]+/(%d+)")
  return rate and tonumber(rate)
end

-- Validate ts-refclk attribute value per ST 2110-10 §7.2
-- Returns true or nil, message fragment
local function valid_tsrefclk(value)
  if value == "gps" or value == "gal" or value == "glonass" then
    return true
  end
  local addr = value:match("^ntp=(.+)$")
  if addr then
    if addr:match("%s") then return nil, "invalid ts-refclk ntp address" end
    return true
  end
  local mac = value:match("^localmac=(.+)$")
  if mac then
    local count = 0
    for octet in mac:gmatch("[^%-]+") do
      if not octet:match("^%x%x$") then return nil, "invalid ts-refclk localmac value" end
      count = count + 1
    end
    if count ~= 6 then return nil, "invalid ts-refclk localmac value" end
    return true
  end
  local ptp_rest = value:match("^ptp=(.+)$")
  if ptp_rest then
    -- version:gmid[:domain] — GMID must be 8 HH-separated hex octets
    local _, gmid = ptp_rest:match("^([^:]+):([^:]+)")
    if not gmid then return nil, "invalid ts-refclk ptp value" end
    local count = 0
    for octet in gmid:gmatch("[^%-]+") do
      if not octet:match("^%x%x$") then return nil, "invalid ts-refclk ptp value" end
      count = count + 1
    end
    if count ~= 8 then return nil, "invalid ts-refclk ptp value" end
    return true
  end
  return nil, "unrecognized ts-refclk clock source"
end

-- Validate mediaclk attribute value per ST 2110-10 §7.3
local function valid_mediaclk(value)
  if value == "sender" then return true end
  local offset = value:match("^direct=(.+)$")
  if offset then
    if offset:match("^%-?%d+$") then return true end
    return nil, "invalid mediaclk direct= value"
  end
  return nil, "unrecognized mediaclk value"
end

-- Parse semicolon-separated key=value pairs from fmtp value "PT param1=v1; param2=v2; ..."
-- Returns params table, or nil + error message on malformed input.
local function fmtp_params(value)
  local params_str = value:match("^%d+%s+(.+)$")
  if not params_str then return {} end
  local params = {}
  for kv in params_str:gmatch("[^;]+") do
    local trimmed = kv:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      local k, v = trimmed:match("^([^=%s]+)%s*=%s*(.-)$")
      if not k then
        return nil, "malformed fmtp parameter: " .. trimmed
      end
      params[k] = v
    end
  end
  return params
end

function M.st2110(doc)
  local validate = require("lib.validate")
  local ok, e = validate.sdp(doc)
  if not ok then return nil, e end

  if #doc.media < 1 then
    return nil, errors.new("ST 2110 requires at least one media block",
      { field_path = "media", spec_ref = "ST 2110-10 §7" })
  end

  local sess_attrs = doc.session.attributes or {}

  for i, m in ipairs(doc.media) do
    local mpath  = string.format("media[%d]", i)
    local mattrs = m.attributes or {}

    local tsrefclk = find_attr(sess_attrs, "ts-refclk") or find_attr(mattrs, "ts-refclk")
    if not tsrefclk then
      return nil, errors.new("missing required attribute 'ts-refclk'", {
        field_path = mpath .. ".attributes[ts-refclk]",
        spec_ref   = "ST 2110-10 §7.2",
      })
    end
    local trok, trmsg = valid_tsrefclk(tsrefclk.value or "")
    if not trok then
      return nil, errors.new("invalid ts-refclk: " .. (trmsg or ""), {
        field_path = mpath .. ".attributes[ts-refclk]",
        spec_ref   = "ST 2110-10 §7.2",
        code       = "INVALID_VALUE",
      })
    end

    local mediaclk = find_attr(mattrs, "mediaclk")
    if not mediaclk then
      return nil, errors.new("missing required attribute 'mediaclk'", {
        field_path = mpath .. ".attributes[mediaclk]",
        spec_ref   = "ST 2110-10 §7.3",
      })
    end
    local mcok, mcmsg = valid_mediaclk(mediaclk.value or "")
    if not mcok then
      return nil, errors.new("invalid mediaclk: " .. (mcmsg or ""), {
        field_path = mpath .. ".attributes[mediaclk]",
        spec_ref   = "ST 2110-10 §7.3",
        code       = "INVALID_VALUE",
      })
    end

    local rtpmap = find_attr(mattrs, "rtpmap")
    if not rtpmap then
      return nil, errors.new("missing required attribute 'rtpmap'", {
        field_path = mpath .. ".attributes[rtpmap]",
        spec_ref   = "ST 2110-10 §7",
      })
    end

    local fmtp = find_attr(mattrs, "fmtp")
    if not fmtp then
      return nil, errors.new("missing required attribute 'fmtp'", {
        field_path = mpath .. ".attributes[fmtp]",
        spec_ref   = "ST 2110-10 §7",
      })
    end

    if m.media == "video" then
      local clock_rate = rtpmap_clock_rate(rtpmap.value or "")
      if clock_rate ~= 90000 then
        return nil, errors.new(
          string.format("rtpmap clock rate must be 90000 for video (got %s)", tostring(clock_rate)),
          {
            field_path = mpath .. ".attributes[rtpmap]",
            spec_ref   = "ST 2110-20 §7.2",
            code       = "INVALID_VALUE",
          }
        )
      end
      local params, fmtp_err = fmtp_params(fmtp.value or "")
      if not params then
        return nil, errors.new("invalid fmtp: " .. fmtp_err, {
          field_path = mpath .. ".attributes[fmtp]",
          spec_ref   = "ST 2110-20 §7.2",
          code       = "INVALID_VALUE",
        })
      end
      if not params.sampling then
        return nil, errors.new("fmtp missing required 'sampling' parameter for video", {
          field_path = mpath .. ".attributes[fmtp]",
          spec_ref   = "ST 2110-20 §7.2",
        })
      end
    end

    if m.media == "audio" then
      local params, fmtp_err = fmtp_params(fmtp.value or "")
      if not params then
        return nil, errors.new("invalid fmtp: " .. fmtp_err, {
          field_path = mpath .. ".attributes[fmtp]",
          spec_ref   = "ST 2110-30 §7.2",
          code       = "INVALID_VALUE",
        })
      end
      if not params["channel-order"] then
        return nil, errors.new("fmtp missing required 'channel-order' parameter for audio", {
          field_path = mpath .. ".attributes[fmtp]",
          spec_ref   = "ST 2110-30 §7.2",
        })
      end
    end
  end

  return true
end

return M
