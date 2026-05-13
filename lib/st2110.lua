local M = {}

local function st2110_err(msg, field_path, spec_ref)
  return {
    message    = msg,
    line       = 0,
    col        = 0,
    context    = "",
    field_path = field_path or "",
    spec_ref   = spec_ref or "",
  }
end

local function find_attr(attrs, name)
  for _, a in ipairs(attrs or {}) do
    if a.name == name then return a end
  end
end

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
  if addr then return true end
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
local function fmtp_params(value)
  local params_str = value:match("^%d+%s+(.+)$")
  if not params_str then return {} end
  local params = {}
  for kv in params_str:gmatch("[^;]+") do
    local k, v = kv:match("^%s*([^=%s]+)%s*=%s*(.-)%s*$")
    if k then params[k] = v end
  end
  return params
end

function M.st2110(doc)
  local validate = require("lib.validate")
  local ok, e = validate.sdp(doc)
  if not ok then return nil, e end

  if #doc.media < 1 then
    return nil, st2110_err(
      "ST 2110 requires at least one media block",
      "media",
      "ST 2110-10 §7"
    )
  end

  local sess_attrs = doc.session.attributes or {}

  for i, m in ipairs(doc.media) do
    local mpath  = string.format("media[%d]", i)
    local mattrs = m.attributes or {}

    local tsrefclk = find_attr(sess_attrs, "ts-refclk") or find_attr(mattrs, "ts-refclk")
    if not tsrefclk then
      return nil, st2110_err(
        "missing required attribute 'ts-refclk'",
        mpath .. ".attributes[ts-refclk]",
        "ST 2110-10 §7.2"
      )
    end
    local trok, trmsg = valid_tsrefclk(tsrefclk.value or "")
    if not trok then
      return nil, st2110_err(
        "invalid ts-refclk: " .. (trmsg or ""),
        mpath .. ".attributes[ts-refclk]",
        "ST 2110-10 §7.2"
      )
    end

    local mediaclk = find_attr(mattrs, "mediaclk")
    if not mediaclk then
      return nil, st2110_err(
        "missing required attribute 'mediaclk'",
        mpath .. ".attributes[mediaclk]",
        "ST 2110-10 §7.3"
      )
    end
    local mcok, mcmsg = valid_mediaclk(mediaclk.value or "")
    if not mcok then
      return nil, st2110_err(
        "invalid mediaclk: " .. (mcmsg or ""),
        mpath .. ".attributes[mediaclk]",
        "ST 2110-10 §7.3"
      )
    end

    local rtpmap = find_attr(mattrs, "rtpmap")
    if not rtpmap then
      return nil, st2110_err(
        "missing required attribute 'rtpmap'",
        mpath .. ".attributes[rtpmap]",
        "ST 2110-10 §7"
      )
    end

    local fmtp = find_attr(mattrs, "fmtp")
    if not fmtp then
      return nil, st2110_err(
        "missing required attribute 'fmtp'",
        mpath .. ".attributes[fmtp]",
        "ST 2110-10 §7"
      )
    end

    if m.media == "video" then
      local clock_rate = rtpmap_clock_rate(rtpmap.value or "")
      if clock_rate ~= 90000 then
        return nil, st2110_err(
          string.format(
            "rtpmap clock rate must be 90000 for video (got %s)",
            tostring(clock_rate)
          ),
          mpath .. ".attributes[rtpmap]",
          "ST 2110-20 §7.2"
        )
      end
      local params = fmtp_params(fmtp.value or "")
      if not params.sampling then
        return nil, st2110_err(
          "fmtp missing required 'sampling' parameter for video",
          mpath .. ".attributes[fmtp]",
          "ST 2110-20 §7.2"
        )
      end
    end

    if m.media == "audio" then
      local params = fmtp_params(fmtp.value or "")
      if not params["channel-order"] then
        return nil, st2110_err(
          "fmtp missing required 'channel-order' parameter for audio",
          mpath .. ".attributes[fmtp]",
          "ST 2110-30 §7.2"
        )
      end
    end
  end

  return true
end

return M
