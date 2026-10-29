-- parse_sdp.grammar.ipmx — VSF IPMX (TR-10 series) tier grammar.
--
-- Composed via `st2110.extend(st2110, overrides)`. IPMX is a TR-10-1 §7
-- profile on top of ST 2110, so this module chains the ST 2110 tier and
-- adds TR-10-only narrowings (new attributes a=hkep / a=privacy /
-- a=infoframe, fmtp IPMX marker, FEC parameters, b=AS bandwidth form,
-- USB transport block constraints, etc.). Per CLAUDE.md and the audits/
-- folder, every check cites explicit primary TR-10 / IPMX-profile text.

local lpeg     = require("lpeg")
local base     = require("parse_sdp.grammar.base")
local st2110   = require("parse_sdp.grammar.st2110")
local errors   = require("parse_sdp.errors")
local patterns = require("parse_sdp.grammar.patterns")

local P, R, C       = lpeg.P, lpeg.R, lpeg.C
local Cb, Cc, Cg    = lpeg.Cb, lpeg.Cc, lpeg.Cg
local Cmt, Carg, V  = lpeg.Cmt, lpeg.Carg, lpeg.V

local SP = P(" ")

local is_rtp_block = base.is_rtp_block
local is_usb_block = base.is_usb_block

-- ── §10 FID prohibition ────────────────────────────────────────────────────
-- TR-10-1 §10: "Section 4.1 of IETF RFC 8331 permits the use of Flow
-- Identification (FID) semantics to group streams within the SDP; such use
-- is inconsistent with the 'one SDP object per RTP Stream' provision of
-- SMPTE ST 2110-10 and shall not be used under this TR."
local function check_a_group_fid(_, pos, semantics, ctx)
  if semantics == "FID" then
    local cont = errors.record(ctx, "tr-10-1.a.group.fid-forbidden",
      { pos = pos, field_path = "session.attributes[group]" })
    if not cont then return false end
  end
  return pos
end

local a_group_with_fid_check =
  base.rules.a_group * #V"value_boundary_chars"
  * Cmt(Cb"semantics" * Carg(1), check_a_group_fid)

-- ── §10.1 IPMX fmtp marker ─────────────────────────────────────────────────
-- TR-10-1 §10.1 (verbatim): "IPMX Senders shall include the ' IPMX'
-- declaration in the a=fmtp clause of the SDP file." Singular "the a=fmtp
-- clause" → at-least-one per RTP block satisfies the SHALL. Blocks with
-- no a=fmtp at all are out of §10.1's scope (caught instead by the ST 2110
-- tier's rtpmap-requires-fmtp checks for raw/jxsv encodings).
local function check_ipmx_fmtp_marker(block, ctx)
  if not is_rtp_block(block) then return true end
  local fmtps, marked = base.attrs_get(block, "fmtp"), false
  for _, attr in ipairs(fmtps) do
    if base.params_get(attr.params, "IPMX") then
      marked = true
    end
  end
  if #fmtps > 0 and not marked then
    local cont = errors.record(ctx, "tr-10-1.a.fmtp.marker-required",
      { pos        = fmtps[1]._pos,
        field_path = string.format(
          "media[%d].attributes[fmtp]", ctx.media_index or 0) })
    if not cont then return false end
  end
  return true
end

-- ── §10.2 video IPMX fmtp required parameters ─────────────────────────────
-- TR-10-1 §10.2: "the sender shall include the measuredpixclk, vtotal and
-- htotal parameters in the a=fmtp clause of the SDP file." TR-10-9 §10
-- extends the same requirement to non-baseband senders, so presence +
-- positive-integer value form (RFC 8866 §9 ABNF integer) is required on
-- every video IPMX block's a=fmtp.

local IPMX_VIDEO_REQUIRED_PARAMS = {
  "measuredpixclk", "vtotal", "htotal",
}

-- Per-key: absent → `<key>-required`, present-but-malformed (not RFC 8866
-- integer) → `<key>-invalid-value`. One walk emits both.
local function check_ipmx_video_fmtp(params, ctx, pos, field_path)
  for _, key in ipairs(IPMX_VIDEO_REQUIRED_PARAMS) do
    local v = base.params_get(params, key)
    if v == nil then
      local cont = errors.record(ctx,
        "tr-10-1.a.fmtp." .. key .. "-required",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    elseif patterns.pos_int:match(tostring(v)) == nil then
      local cont = errors.record(ctx,
        "tr-10-1.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  return true
end

-- ── §10.3 audio IPMX fmtp required parameter ────────────────────────────────
-- TR-10-1 §10.3: "An audio IPMX Sender that is converting from a Baseband
-- signal shall include the measuredsamplerate parameters in the a=fmtp
-- clause... measuredsamplerate reports the audio sample rate in Hertz."
-- TR-10-9 §10 extends to non-baseband audio (substitute = rtpmap rate),
-- so presence is required regardless of sender type. Value form is
-- positive integer (Hertz).

local function check_ipmx_audio_fmtp(params, ctx, pos, field_path)
  local v = base.params_get(params, "measuredsamplerate")
  if v == nil then
    local cont = errors.record(ctx,
      "tr-10-1.a.fmtp.measuredsamplerate-required",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  elseif patterns.pos_int:match(tostring(v)) == nil then
    local cont = errors.record(ctx,
      "tr-10-1.a.fmtp.measuredsamplerate-invalid-value",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  end
  return true
end

-- ── §7.6 FECPROFILE / FEC_ADD_LATENCY_* (encoding-agnostic) ────────────────
-- TR-10-6 §7.6: when FECPROFILE is present, value must be "profile-a"
-- (the only IPMX FEC profile currently defined). FEC_ADD_LATENCY_VIDEO
-- and FEC_ADD_LATENCY_AUDIO are optional, non-negative integer values
-- (microseconds); presence of either implies a FEC companion stream is
-- signaled, which in turn requires FECPROFILE on the same fmtp.
--
-- Encoding-agnostic: the same SHALL applies to any RTP fmtp that may
-- declare a FEC companion, so this check runs as part of the universal
-- per-fmtp pass below, independent of the rtpmap encoding.
local FEC_LATENCY_KEYS = {
  { key = "FEC_ADD_LATENCY_VIDEO", suffix = "video" },
  { key = "FEC_ADD_LATENCY_AUDIO", suffix = "audio" },
}

local function check_ipmx_fec_params(params, ctx, pos, field_path)
  local fecprofile = base.params_get(params, "FECPROFILE")
  if fecprofile ~= nil and fecprofile ~= "profile-a" then
    local cont = errors.record(ctx,
      "tr-10-6.a.fmtp.fecprofile-invalid-value",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  end
  for _, e in ipairs(FEC_LATENCY_KEYS) do
    local v = base.params_get(params, e.key)
    if v ~= nil then
      if fecprofile == nil then
        local cont = errors.record(ctx,
          "tr-10-6.a.fmtp.fec-add-latency-" .. e.suffix .. "-requires-fecprofile",
          { pos = pos, field_path = field_path })
        if not cont then return false end
      end
      if patterns.zero_based_int:match(tostring(v)) == nil then
        local cont = errors.record(ctx,
          "tr-10-6.a.fmtp.fec-add-latency-" .. e.suffix .. "-invalid-value",
          { pos = pos, field_path = field_path })
        if not cont then return false end
      end
    end
  end
  return true
end

-- Per-encoding IPMX fmtp checks.
--   - raw (TR-10-2 §7) and jxsv (TR-10-11 §7) inherit TR-10-1 §10.2 via
--     their respective "compliance with TR-10-1" clauses.
--   - L16 / L24 (TR-10-3 §7) and AM824 (TR-10-12 §7) inherit TR-10-1
--     §10.3 the same way.
local IPMX_FMTP_CHECKS_BY_ENCODING = {
  raw   = { check_ipmx_video_fmtp },
  jxsv  = { check_ipmx_video_fmtp },
  L16   = { check_ipmx_audio_fmtp },
  L24   = { check_ipmx_audio_fmtp },
  AM824 = { check_ipmx_audio_fmtp },
}

-- Universal IPMX fmtp checks — apply to every RTP fmtp regardless of
-- rtpmap encoding. Currently just the TR-10-6 §7.6 FEC parameter
-- validations.
local IPMX_FMTP_UNIVERSAL_CHECKS = {
  check_ipmx_fec_params,
}

local function ipmx_fmtp_dispatch(_, pos, pt, params, ctx)
  if params == nil then return pos end       -- raw-fallback path; skip
  local field_path = string.format(
    "media[%d].attributes[fmtp:pt=%d]", ctx.media_index or 0, pt)
  -- Universal checks first (FEC params apply to any encoding).
  for _, check in ipairs(IPMX_FMTP_UNIVERSAL_CHECKS) do
    if not check(params, ctx, pos, field_path) then return false end
  end
  -- Per-encoding checks next, when the rtpmap encoding is recognized.
  local enc = ctx and ctx.rtpmap_encodings
                    and ctx.rtpmap_encodings[pt]
  local checks = enc and IPMX_FMTP_CHECKS_BY_ENCODING[enc]
  if checks then
    for _, check in ipairs(checks) do
      if not check(params, ctx, pos, field_path) then return false end
    end
  end
  return pos
end

-- Chain IPMX dispatch after st2110's: parse the fmtp, run st2110's per-
-- encoding checks (returns pos on success, false on hard failure), then
-- run IPMX's per-encoding checks. Cb"payload_type" and Cb"params" are
-- the same back-references st2110's trailing Cmt reads — both are still
-- in scope inside the surrounding a_value Ct.
local a_fmtp_with_ipmx_dispatch =
    st2110.rules.a_fmtp
  * Cmt(Cb"payload_type" * Cb"params" * Carg(1), ipmx_fmtp_dispatch)

-- ── §7 RTP port must be even AND > 1024 (per-block check) ──────────────────
-- TR-10-2 §7 (verbatim, replicated in TR-10-3/-4/-11/-12 §7): "All IPMX
-- Media streams shall have a UDP destination port value that is even
-- and that is greater than 1024."
--
-- Applies only to RTP-bearing blocks. block.port is captured as a
-- number by base's m_value rule; no parsing in this check — just integer
-- comparisons on captured data.
local function check_ipmx_port_constraints(block, ctx)
  if not is_rtp_block(block) then return true end
  local port = block.port
  if type(port) ~= "number" then return true end
  local field_path = string.format("media[%d].port", ctx.media_index or 0)
  if port <= 1024 then
    local cont = errors.record(ctx, "ipmx.m.port-must-exceed-1024",
      { field_path = field_path })
    if not cont then return false end
  end
  if port % 2 ~= 0 then
    local cont = errors.record(ctx, "ipmx.m.port-must-be-even",
      { field_path = field_path })
    if not cont then return false end
  end
  return true
end

-- ── TR-10-1 §8.7 RTCP port convention (per-block check) ────────────────────
-- TR-10-1 §8.7 (verbatim): "RTCP Sender Report packets shall be sent to
-- the UDP destination port that corresponds to +1 from the port used by
-- their corresponding media payload."
--   a=rtcp-mux (RFC 5761 §5.1.1) requests RTP and RTCP on one port, which
--   cannot satisfy the +1 SHALL.
--   a=rtcp:<port> (RFC 3605 §2.1) declares the RTCP port explicitly; any
--   value other than media port + 1 contradicts the SHALL. Absence is
--   accepted (the +1 convention is then implicit).
local function check_rtcp_port_convention(block, ctx)
  if not is_rtp_block(block) then return true end
  local field = string.format("media[%d].attributes", ctx.media_index or 0)
  for _ in ipairs(base.attrs_get(block, "rtcp-mux")) do
    local cont = errors.record(ctx, "tr-10-1.a.rtcp-mux.forbidden",
      { field_path = field .. "[rtcp-mux]" })
    if not cont then return false end
  end
  for _, attr in ipairs(base.attrs_get(block, "rtcp")) do
    if type(block.port) == "number" and attr.port ~= block.port + 1 then
      local cont = errors.record(ctx,
        "tr-10-1.a.rtcp.port-must-be-media-port-plus-1",
        { field_path = field .. "[rtcp]",
          context    = { port = attr.port, expected = block.port + 1 } })
      if not cont then return false end
    end
  end
  return true
end

-- ── §8 a=infoframe attribute (HDMI InfoFrame signaling) ────────────────────
-- TR-10-10 §8: "IPMX Senders compliant to this TR shall include the
-- following session attribute in the SDP object of the associated IPMX
-- media stream. The format of this attribute is as follows:
--   a=infoframe:<port> SSN=ST2110-41:2024;DIT=100100"
--
-- Presence is conditional on the SDP describing an HDMI/TR-10-10 stream
-- (out-of-SDP state); the validator therefore checks form + scope WHEN
-- the attribute IS present. Five SHALLs apply:
--   (a) session-level only — media-level a=infoframe rejected
--       (in-grammar Cmt reads ctx.media_index)
--   (b) SSN value form — `ST2110-41:<year>` (literal prefix +
--       trailing digits)
--   (c) DIT value form — literally "100100"
--   (d) port == associated media port + 3 (cross-section
--       — semantic_check)
--   (e) port uniqueness across infoframe lines (cross-section
--       — semantic_check)

-- LPeg sub-patterns for the value parts. Anchored standalone matches
-- via patterns.* for full-string validation in the Cmt below.
local SSN_FORM = P("ST2110-41:") * R("09")^1 * P(-1)
local DIT_VALUE = P("100100") * P(-1)

local function check_a_infoframe(_, pos, ssn, dit, ctx)
  -- (a) session-level: ctx.media_index = -1 until the first
  --     media_section's leading Cmt pre-increments it to 0. Inside any
  --     media block, media_index >= 0.
  if ctx.media_index and ctx.media_index >= 0 then
    local cont = errors.record(ctx,
      "tr-10-10.a.infoframe.must-be-session-level",
      { pos = pos,
        field_path = string.format(
          "media[%d].attributes[infoframe]", ctx.media_index) })
    if not cont then return false end
  end
  -- (b) SSN form
  if SSN_FORM:match(ssn) == nil then
    local cont = errors.record(ctx,
      "tr-10-10.a.infoframe.ssn-invalid-form",
      { pos = pos, field_path = "session.attributes[infoframe]" })
    if not cont then return false end
  end
  -- (c) DIT literal value
  if DIT_VALUE:match(dit) == nil then
    local cont = errors.record(ctx,
      "tr-10-10.a.infoframe.dit-invalid-value",
      { pos = pos, field_path = "session.attributes[infoframe]" })
    if not cont then return false end
  end
  -- The captured port surfaces to the doc table for the cross-section
  -- semantic checks below; no validation on the numeric value here
  -- (SHALL is relational to media-block port + 3, validated post-doc).
  return pos
end

-- The a=infoframe parse: port is a positive integer (base's
-- rfc8866_pos_int_num captures POS-DIGIT *DIGIT and converts to a
-- number). SSN value is everything up to ";" (line terminator excluded
-- to keep the rule's failure modes clean). DIT value is the digit run
-- to end-of-line.
--
-- infoframe_value is the value's shape alone; the malformed branch
-- declines a value of that shape, so a field check that fails the match
-- under fail_on_first is not reported again as malformed.
local infoframe_value =
    Cg(V"rfc8866_pos_int_num", "port") * SP
  * P("SSN=")
  * Cg(C((P(1) - P(";") - V"line_end_chars")^1), "ssn")
  * P(";")
  * P("DIT=")
  * Cg(C(R("09")^1), "dit")
  * #V"value_boundary_chars"

local a_infoframe =
    P("infoframe:")
  * Cg(Cc("infoframe"), "name")
  * infoframe_value
  * Cmt(Cb"ssn" * Cb"dit" * Carg(1), check_a_infoframe)

-- Cross-section semantic_check (d) + (e): one walk over the session-
-- level a=infoframe lines, building two sets — observed ports and the
-- set of valid (media + 3) ports from doc.media.
local function check_infoframe_cross_section(doc, ctx)
  local valid_ports = {}
  for _, m in ipairs(doc.media or {}) do
    if type(m.port) == "number" then
      valid_ports[m.port + 3] = true
    end
  end
  local seen = {}
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "infoframe" then
      local port = attr.port
      if type(port) == "number" then
        if seen[port] then
          local cont = errors.record(ctx,
            "tr-10-10.a.infoframe.duplicate-port",
            { field_path = "session.attributes[infoframe]" })
          if not cont then return false end
        end
        seen[port] = true
        if not valid_ports[port] then
          local cont = errors.record(ctx,
            "tr-10-10.a.infoframe.port-must-match-media-plus-3",
            { field_path = "session.attributes[infoframe]" })
          if not cont then return false end
        end
      end
    end
  end
  return true
end

-- ── §10 a=hkep attribute (HDCP Key Exchange Protocol signaling) ────────────
-- TR-10-5 §10 (rows 122–135 of audits/SPEC_INVENTORY.md):
--   "The SDP transport file shall contain at least one 'hkep' session
--    attribute when the associated ST 2110/IPMX media stream is HDCP
--    Content. The format is as follows:
--      a=hkep:<port> <nettype> <addrtype> <unicast-address>
--                    <node-id> <port-id>"
-- Per-component SHALLs:
--   <nettype>   = "IN"
--   <addrtype>  ∈ {"IP4", "IP6"}
--   <node-id>   = 32 hex digits formatted as xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
--   <port-id>   = 10 hex digits formatted as xx-xx-xx-xx-xx
--   <unicast-address> — host is present; specific syntax not constrained
-- Presence is conditional on out-of-SDP HDCP state, so the validator
-- checks form WHEN the attribute IS present. TR-10-5 §17 permits the
-- attribute at session level, media level, or both.

local HEX = R("09", "af", "AF")
local hex4 = HEX * HEX * HEX * HEX
local hex2 = HEX * HEX

-- Anchored value-form patterns. Each consumes its full input on a match
-- or returns nil; used with `:match(captured_string)` inside the
-- value-form Cmt below.
local HKEP_NODE_ID_FORM =
    hex4 * hex4 * P("-")        -- 8 hex digits
  * hex4 * P("-")               -- 4
  * hex4 * P("-")               -- 4
  * hex4 * P("-")               -- 4
  * hex4 * hex4 * hex4          -- 12
  * P(-1)
local HKEP_PORT_ID_FORM =
    hex2 * P("-") * hex2 * P("-") * hex2 * P("-")
  * hex2 * P("-") * hex2
  * P(-1)

local function check_a_hkep(_, pos, nettype, addrtype, node_id, port_id, ctx)
  local function loc()
    -- a=hkep may be session-level or media-level; pick the field_path
    -- accordingly from ctx.media_index (set to -1 at session-level
    -- attribute parse time).
    if ctx.media_index and ctx.media_index >= 0 then
      return { pos = pos, field_path = string.format(
        "media[%d].attributes[hkep]", ctx.media_index) }
    else
      return { pos = pos, field_path = "session.attributes[hkep]" }
    end
  end
  if nettype ~= "IN" then
    local cont = errors.record(ctx,
      "tr-10-5.a.hkep.nettype-invalid-value", loc())
    if not cont then return false end
  end
  if addrtype ~= "IP4" and addrtype ~= "IP6" then
    local cont = errors.record(ctx,
      "tr-10-5.a.hkep.addrtype-invalid-value", loc())
    if not cont then return false end
  end
  if HKEP_NODE_ID_FORM:match(node_id) == nil then
    local cont = errors.record(ctx,
      "tr-10-5.a.hkep.node-id-invalid-form", loc())
    if not cont then return false end
  end
  if HKEP_PORT_ID_FORM:match(port_id) == nil then
    local cont = errors.record(ctx,
      "tr-10-5.a.hkep.port-id-invalid-form", loc())
    if not cont then return false end
  end
  return pos
end

-- Loose structural parse: 6 SP-separated tokens after "hkep:<port> ".
-- Specific value forms are validated in the trailing Cmt above so that
-- a single failing field produces a specific error ID rather than a
-- generic parse failure.
local hkep_token = C((P(1) - SP - V"line_end_chars")^1)

local hkep_value =
    Cg(V"rfc8866_pos_int_num", "port") * SP
  * Cg(hkep_token, "nettype")  * SP
  * Cg(hkep_token, "addrtype") * SP
  * Cg(hkep_token, "addr")     * SP
  * Cg(hkep_token, "node_id")  * SP
  * Cg(hkep_token, "port_id")
  * #V"value_boundary_chars"

local a_hkep =
    P("hkep:")
  * Cg(Cc("hkep"), "name")
  * hkep_value
  * Cmt(Cb"nettype" * Cb"addrtype" * Cb"node_id" * Cb"port_id" * Carg(1),
        check_a_hkep)

-- ── §13 a=privacy attribute (Privacy Encryption Protocol signaling) ───────
-- TR-10-13 §13 (audits rows 246–257):
--   Required parameters: protocol, mode, iv, key_generator, key_version,
--                        key_id.
--   "The privacy attribute of an SDP transport file shall be formatted as
--   a follow with a semicolon and an optional space separating the
--   parameters and a CRLF to terminate the attribute line. There shall be
--   no semicolon after the last parameter." (§13 line 338)
--   Format line (§13 lines 340-342): "a=privacy:protocol=<protocol>;
--   mode=<mode>; iv=<iv>; key_generator=<key_generator>;
--   key_version=<key_version>; key_id=<key_id> CRLF". No space follows
--   "privacy:" or surrounds "="; the only optional space follows ";".
--   Octet-string values are hex (no spaces) with bit-lengths defined per
--   parameter (§13 lines 366, 372, 376, 386).
--   protocol = "NULL" is forbidden in SDP (§13 line 352); the
--   omit-the-attribute alternative is the correct way to indicate
--   "no privacy". mode = "NULL" is similarly forbidden (§13 line 362)
--   and is subsumed by the §20.1 enum (the 12 enumerated mode values).
--
-- The grammar parses a permissive structural shape (kv-list separated
-- by `;[SP]?`) and a trailing Cmt enforces required-keys + value forms.
-- Anchored value-form sub-patterns below drive the per-key checks.

-- Mode enum from TR-10-13 §20.1 (line 679): 12 AES-128/256-CTR variants
-- plus their ECDH_ peer-to-peer counterparts. NULL is intentionally
-- absent so the enum check subsumes the §13 NULL-mode prohibition.
local PRIVACY_MODE_VALUES = {
  ["AES-128-CTR"]                  = true,
  ["AES-256-CTR"]                  = true,
  ["AES-128-CTR_CMAC-64"]          = true,
  ["AES-256-CTR_CMAC-64"]          = true,
  ["AES-128-CTR_CMAC-64-AAD"]      = true,
  ["AES-256-CTR_CMAC-64-AAD"]      = true,
  ["ECDH_AES-128-CTR"]             = true,
  ["ECDH_AES-256-CTR"]             = true,
  ["ECDH_AES-128-CTR_CMAC-64"]     = true,
  ["ECDH_AES-256-CTR_CMAC-64"]     = true,
  ["ECDH_AES-128-CTR_CMAC-64-AAD"] = true,
  ["ECDH_AES-256-CTR_CMAC-64-AAD"] = true,
}

local PRIVACY_REQUIRED_KEYS = {
  "protocol", "mode", "iv", "key_generator", "key_version", "key_id",
}

-- Anchored hex-form patterns for each Octet-String parameter.
-- HEX was already defined for a=hkep above; reuse for consistency.
local function hex_exact(n)
  local p = HEX
  for _ = 2, n do p = p * HEX end
  return p * P(-1)
end
local PRIVACY_HEX_FORMS = {
  iv            = hex_exact(16),  -- 64-bit
  key_generator = hex_exact(32),  -- 128-bit
  key_version   = hex_exact(8),   -- 32-bit
  key_id        = hex_exact(16),  -- 64-bit
}

local function check_a_privacy(_, pos, params, trailing_semi, ctx)
  local function loc()
    if ctx.media_index and ctx.media_index >= 0 then
      return { pos = pos, field_path = string.format(
        "media[%d].attributes[privacy]", ctx.media_index) }
    else
      return { pos = pos, field_path = "session.attributes[privacy]" }
    end
  end
  -- Trailing-semicolon check first; if true, the parse already captured
  -- a malformed line.
  if trailing_semi then
    local cont = errors.record(ctx,
      "tr-10-13.a.privacy.trailing-semicolon", loc())
    if not cont then return false end
  end
  -- Build a key→value lookup from the params list.
  local kv = {}
  for _, p in ipairs(params) do
    kv[p[1]] = p[2]
  end
  -- Required keys.
  for _, key in ipairs(PRIVACY_REQUIRED_KEYS) do
    if kv[key] == nil then
      local cont = errors.record(ctx,
        "tr-10-13.a.privacy." .. key .. "-required", loc())
      if not cont then return false end
    end
  end
  -- protocol NULL prohibition.
  if kv.protocol == "NULL" then
    local cont = errors.record(ctx,
      "tr-10-13.a.privacy.protocol-null-forbidden", loc())
    if not cont then return false end
  end
  -- mode enum (subsumes the NULL prohibition).
  if kv.mode ~= nil and not PRIVACY_MODE_VALUES[kv.mode] then
    local cont = errors.record(ctx,
      "tr-10-13.a.privacy.mode-invalid-value", loc())
    if not cont then return false end
  end
  -- Hex-form keys.
  for key, form in pairs(PRIVACY_HEX_FORMS) do
    local v = kv[key]
    if v ~= nil and form:match(v) == nil then
      local cont = errors.record(ctx,
        "tr-10-13.a.privacy." .. key .. "-invalid-form", loc())
      if not cont then return false end
    end
  end
  return pos
end

-- LPeg sub-patterns for the kv-list. Each entry captures
-- {key, value} (Ct-collected). A trailing `;` at end-of-attribute is
-- captured as a boolean for the trailing-semicolon SHALL check.
local privacy_key   = C((P(1) - P("=") - P(";") - SP - V"line_end_chars")^1)
local privacy_value = C((P(1) - P(";") - V"line_end_chars")^0)
local privacy_entry =
    lpeg.Ct(privacy_key * P("=") * -SP * privacy_value)
local privacy_sep = P(";") * SP^-1

local privacy_body =
    Cg(lpeg.Ct(privacy_entry * (privacy_sep * privacy_entry)^0),
       "params")
  * Cg(P(";") * Cc(true) + Cc(false), "trailing_semi")
  * #V"value_boundary_chars"

local a_privacy =
    P("privacy:")
  * Cg(Cc("privacy"), "name")
  * privacy_body
  * Cmt(Cb"params" * Cb"trailing_semi" * Carg(1), check_a_privacy)

-- ── §13 redundancy — DUP legs share privacy parameters (semantic_check) ──
-- TR-10-13 §13 (verbatim): "When using redundancy, as in ST 2022-7, the
-- legs shall use the same privacy encryption parameters." A leg's
-- effective parameters are its media-level a=privacy, else the session-
-- level one (§17 permits either level). Legs resolve through a=group:DUP
-- tags as the ST 2110-10 §8.5 coherence check does; an unresolved tag is
-- that check's finding, not this one's. Parameter order is irrelevant.
local function privacy_params_equal(a, b)
  if a == nil or b == nil then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    if base.params_get(b, a[i][1]) ~= a[i][2] then return false end
  end
  return true
end

local function check_group_dup_privacy(doc, ctx)
  local session_privacy = base.attr_get(doc.session, "privacy")
  local by_mid = {}
  for _, m in ipairs(doc.media) do
    local mid = base.attr_get(m, "mid")
    if mid then by_mid[mid.tag] = m end
  end
  for gi, g in ipairs(doc.session.attributes) do
    if g.name == "group" and g.semantics == "DUP" then
      local seen_lead, lead_params = false, nil
      for _, tag in ipairs(g.tags) do
        local m = by_mid[tag]
        if m then
          local p      = base.attr_get(m, "privacy") or session_privacy
          local params = p and p.params
          if not seen_lead then
            seen_lead, lead_params = true, params
          elseif not privacy_params_equal(params, lead_params) then
            local cont = errors.record(ctx,
              "tr-10-13.a.privacy.dup-legs-must-match",
              { field_path = string.format("session.attributes[group][%d]", gi - 1),
                context    = { tag = tag } })
            if not cont then return false end
          end
        end
      end
    end
  end
  return true
end

-- ── §20.1 a=extmap PEP IV-Counter direction (semantic_check) ──────────────
-- TR-10-13 §20.1 (line 751): "The a=extmap attribute shall be used to
-- declare the RTP Extension Headers in the SDP transport file using
-- 'sendonly' as the direction parameter."
--
-- Applies to a=extmap lines whose URI is one of the PEP IV-Counter
-- URNs (§20.1 line 747). The SHALL is conditional on the URI; any
-- non-PEP extmap is out of scope of this check.
--
-- This lives in semantic_checks rather than in-grammar because base's
-- a_extmap rule wraps `direction` in an optional Cg — when no `/dir`
-- is supplied, the Cg never runs and a Cb"direction" reference inside
-- a trailing Cmt raises an LPeg "back reference not found" error. A
-- post-parse doc walk reads `attr.direction` cleanly (nil when absent)
-- and emits findings for both PEP-on-session and PEP-on-media-level
-- extmap attributes.
local PEP_EXTMAP_URIS = {
  ["urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter"]  = true,
  ["urn:ietf:params:rtp-hdrext:PEP-Short-IV-Counter"] = true,
}

local function check_pep_extmap_in_attrs(attrs, field_path, ctx)
  for _, attr in ipairs(attrs or {}) do
    if attr.name == "extmap"
       and attr.uri and PEP_EXTMAP_URIS[attr.uri]
       and attr.direction ~= "sendonly" then
      local cont = errors.record(ctx,
        "tr-10-13.a.extmap.pep-direction-must-be-sendonly",
        { field_path = field_path })
      if not cont then return false end
    end
  end
  return true
end

-- ── §14 USB transport block constraints (per-block check) ────────────────
-- TR-10-14 §14 line 724: "The SDP shall follow RFC 4145 with the
-- following restrictions" — RFC 4145 §3 makes a=setup mandatory on
-- TCP-based media.
-- TR-10-14 §14 line 740: "The 'role' of the 'setup' attribute shall be
-- 'passive'." — narrows the setup value to "passive" on USB blocks.
-- TR-10-14 §14 line 736: when a=privacy is present on a USB block,
-- "<protocol>: USB_KV" — the privacy protocol parameter MUST be
-- USB_KV.
--
-- The "USB block forbids RTP-specific attributes (rtpmap / fmtp /
-- mediaclk / ts-refclk)" check that the 1.0 IPMX validator enforces is
-- INTENTIONALLY OMITTED here: TR-10-14 §14 says only "follow RFC 4145
-- with the following restrictions" — it does not explicitly forbid
-- those attributes on USB blocks. Per CLAUDE.md's strictness principle
-- (no opinion-based checks), the forbidden-attributes restriction is
-- documented as a 1.0-over-strict flag for audit follow-up rather than
-- ported here.
local function check_usb_block(block, ctx)
  if not is_usb_block(block) then return true end
  local field_path = string.format("media[%d]", ctx.media_index or 0)
  local setup = base.attr_get(block, "setup")
  if setup == nil then
    -- A malformed a=setup counts as present; sdp.a.setup.malformed names
    -- it (decision parse_sdp-n7i).
    for _, attr in ipairs(block.attributes) do
      if attr.name == "setup" then return true end
    end
    local cont = errors.record(ctx, "tr-10-14.usb.setup-required",
      { field_path = field_path .. ".attributes[setup]" })
    if not cont then return false end
  elseif setup.role ~= "passive" then
    local cont = errors.record(ctx, "tr-10-14.usb.setup-must-be-passive",
      { pos = setup._pos, field_path = field_path .. ".attributes[setup]" })
    if not cont then return false end
  end
  return true
end

-- ST 2110-22 at this tier applies to the blocks the ST 2110 tier already
-- recognizes (jxsv, or SSN=ST2110-22:*). TR-10-7 §10 and TR-10-11 §10
-- bind devices "compliant with this TR"; TR-10-0 is descriptive; TR-10-1
-- §10 defers to "the SMPTE ST 2110 standards suite as they apply to each
-- specific media format" and names neither TR. No clause makes every
-- other m=video block an ST 2110-22 stream (decision parse_sdp-59w,
-- amended 2026-10-28).

-- TR-10-13 §23: "a session-level privacy attribute represents the default
-- value for each media-level privacy attribute unless an explicit
-- media-level privacy attribute is provided for the corresponding "m="
-- section." The protocol value set follows the transport. §20 (verbatim,
-- RTP): "The protocol parameter shall be RTP or RTP_KV." TR-10-14 §14
-- (USB): USB_KV (the registry entry quotes it).
local PRIVACY_PROTOCOLS_BY_TRANSPORT = {
  rtp = { id      = "tr-10-13.a.privacy.rtp-protocol-invalid-value",
          allowed = { RTP = true, RTP_KV = true } },
  usb = { id      = "tr-10-14.a.privacy.usb-protocol-must-be-usb_kv",
          allowed = { USB_KV = true } },
}

local function check_privacy_protocol(doc, ctx)
  local session_privacy = base.attrs_get(doc.session, "privacy")
  for i, m in ipairs(doc.media) do
    local rule = (is_rtp_block(m) and PRIVACY_PROTOCOLS_BY_TRANSPORT.rtp)
              or (is_usb_block(m) and PRIVACY_PROTOCOLS_BY_TRANSPORT.usb)
    if rule then
      local attrs      = base.attrs_get(m, "privacy")
      local field_path = string.format("media[%d].attributes[privacy]", i - 1)
      if #attrs == 0 then
        attrs, field_path = session_privacy, "session.attributes[privacy]"
      end
      for _, attr in ipairs(attrs) do
        local protocol = base.params_get(attr.params, "protocol")
        if protocol ~= nil and not rule.allowed[protocol] then
          local cont = errors.record(ctx, rule.id,
            { pos = attr._pos, field_path = field_path })
          if not cont then return false end
        end
      end
    end
  end
  return true
end

local function check_pep_extmap_direction(doc, ctx)
  if not check_pep_extmap_in_attrs(
       doc.session.attributes, "session.attributes[extmap]", ctx) then
    return false
  end
  for i, m in ipairs(doc.media or {}) do
    if not check_pep_extmap_in_attrs(
         m.attributes,
         string.format("media[%d].attributes[extmap]", i - 1), ctx) then
      return false
    end
  end
  return true
end

return st2110.extend(st2110, {
  rules = {
    a_group           = a_group_with_fid_check,
    a_fmtp            = a_fmtp_with_ipmx_dispatch,
    a_tier_extensions = a_infoframe + a_hkep + a_privacy,
    tier_attr_names   = P("infoframe") + P("hkep") + P("privacy"),
    tier_malformed    =
        st2110.rules.tier_malformed
      + base.malformed_attr("infoframe", "tr-10-10.a.infoframe.malformed",
                            infoframe_value)
      + base.malformed_attr("hkep",      "tr-10-5.a.hkep.malformed",
                            hkep_value)
      + base.malformed_attr("privacy",   "tr-10-13.a.privacy.malformed",
                            privacy_body),
  },
  media_section_checks = {
    check_ipmx_fmtp_marker,
    check_ipmx_port_constraints,
    check_rtcp_port_convention,
    check_usb_block,
  },
  semantic_checks = {
    check_infoframe_cross_section,
    check_group_dup_privacy,
    check_privacy_protocol,
    check_pep_extmap_direction,
  },
})
