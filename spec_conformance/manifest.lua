-- Pinned upstream sources and the per-fixture test plan.
-- Bump `sha` deliberately when refreshing; see spec_conformance/README.md.

return {
  sources = {
    nmos_testing = {
      repo = "AMWA-TV/nmos-testing",
      sha  = "c0f4f30ee764a12d9f76c39057149122b1e7029c",
      license = "Apache-2.0",
    },
    bcp_006_01 = {
      repo = "AMWA-TV/bcp-006-01",
      sha  = "865faf3ff987f75d1466aa4c3576ce78b331d1f1",
      license = "Apache-2.0",
    },
  },

  -- Each entry is one test case. `path` is fetched from the pinned source;
  -- if `vars` is set, the file is rendered through the Jinja2-subset
  -- renderer before parsing. `mode` selects the validation tier.
  --
  -- The nmos-testing corpus is templated; bcp-006-01's example is literal.
  fixtures = {
    -- ── nmos-testing: ST 2110-30 audio ──
    {
      id = "nmos-testing:audio.sdp/L24-48k-2ch",
      source = "nmos_testing",
      path = "test_data/sdp/audio.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        media_subtype = "L24", sample_rate = "48000", channels = "2",
        packet_time = "1", max_packet_time = "1",
      },
    },
    {
      id = "nmos-testing:audio.sdp/L16-48k-2ch",
      source = "nmos_testing",
      path = "test_data/sdp/audio.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        media_subtype = "L16", sample_rate = "48000", channels = "2",
        packet_time = "0.125", max_packet_time = "0.125",
      },
    },

    -- ── nmos-testing: ST 2110-40 ancillary data ──
    -- The upstream fixture predates ST 2110-40:2023 and carries no fmtp at
    -- all on its smpte291 block. ST 2110-40:2023 §7 imposes new SHALLs
    -- (SSN, exactframerate; conditional TM/TROFF) that the fixture cannot
    -- satisfy. We run it as a negative test asserting rejection citing §7.
    {
      id = "nmos-testing:data.sdp",
      source = "nmos_testing",
      path = "test_data/sdp/data.sdp",
      mode = "st2110",
      vars = { src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004" },
      expect = "fail",
      expect_spec_ref = "ST 2110-40:2023 §7",
    },

    -- ── nmos-testing: ST 2022-6 mux (parses as RFC 4566 only) ──
    {
      id = "nmos-testing:mux.sdp",
      source = "nmos_testing",
      path = "test_data/sdp/mux.sdp",
      mode = nil,
      vars = { src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004" },
    },

    -- ── nmos-testing: ST 2110-20 raw video ──
    {
      id = "nmos-testing:video.sdp/1080p59.94",
      source = "nmos_testing",
      path = "test_data/sdp/video.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        sampling = "YCbCr-4:2:2", width = "1920", height = "1080", depth = "10",
        interlace = false,
        colorimetry = "BT709", TP = "2110TPN", TCS = "SDR",
        exactframerate = "60000/1001",
      },
    },
    {
      id = "nmos-testing:video.sdp/1080i29.97",
      source = "nmos_testing",
      path = "test_data/sdp/video.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        sampling = "YCbCr-4:2:2", width = "1920", height = "1080", depth = "10",
        interlace = true,
        colorimetry = "BT709", TP = "2110TPN", TCS = "SDR",
        exactframerate = "30000/1001",
      },
    },

    -- ── nmos-testing: ST 2110-20 + ST 2022-7 redundancy ──
    -- The upstream template uses one {{ dst_port }} / {{ dst_ip }} placeholder
    -- shared by both legs. ST 2110-10:2022 §8.5 forbids redundant streams from
    -- using both identical source addresses and identical destination
    -- addresses at the same time. The template is non-conformant; this is a
    -- negative test — we expect rejection citing §8.5.
    {
      id = "nmos-testing:video-2022-7.sdp/1080p59.94",
      source = "nmos_testing",
      path = "test_data/sdp/video-2022-7.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        sampling = "YCbCr-4:2:2", width = "1920", height = "1080", depth = "10",
        interlace = false,
        colorimetry = "BT709", TP = "2110TPN", TCS = "SDR",
        exactframerate = "60000/1001",
      },
      expect = "fail",
      expect_spec_ref = "ST 2110-10 §8.5",
    },

    -- ── nmos-testing: ST 2110-22 JPEG XS ──
    {
      id = "nmos-testing:video-jxsv.sdp/720p59.94",
      source = "nmos_testing",
      path = "test_data/sdp/video-jxsv.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        bit_rate = "116000",
        profile = "High444.12", level = "1k-1", sublevel = "Sublev3bpp",
        depth = "10", width = "1280", height = "720",
        exactframerate = "60000/1001", interlace = false,
        sampling = "YCbCr-4:2:2", colorimetry = "BT709",
        RANGE = false, TCS = "SDR", TP = "2110TPN",
      },
    },
    {
      id = "nmos-testing:video-jxsv.sdp/720p59.94+RANGE",
      source = "nmos_testing",
      path = "test_data/sdp/video-jxsv.sdp",
      mode = "st2110",
      vars = {
        src_ip = "192.0.2.1", dst_ip = "239.0.0.1", dst_port = "5004",
        bit_rate = "116000",
        profile = "High444.12", level = "1k-1", sublevel = "Sublev3bpp",
        depth = "10", width = "1280", height = "720",
        exactframerate = "60000/1001", interlace = false,
        sampling = "YCbCr-4:2:2", colorimetry = "BT709",
        RANGE = "FULL", TCS = "SDR", TP = "2110TPN",
      },
    },

    -- ── bcp-006-01: NMOS With JPEG XS reference SDP (literal, no rendering) ──
    {
      id = "bcp-006-01:jpeg-xs.sdp",
      source = "bcp_006_01",
      path = "examples/jpeg-xs.sdp",
      mode = "st2110",
    },
  },
}
