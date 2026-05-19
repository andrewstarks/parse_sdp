---@diagnostic disable
local A = require("parse_sdp.grammar.addresses")

describe("addresses.ipv4 — RFC 791 dotted-quad, anchored", function()

  -- NOT-SPEC: library
  it("matches 0.0.0.0", function()
    assert.is_truthy(A.ipv4:match("0.0.0.0"))
  end)

  -- NOT-SPEC: library
  it("matches 255.255.255.255", function()
    assert.is_truthy(A.ipv4:match("255.255.255.255"))
  end)

  -- NOT-SPEC: library
  it("matches 192.168.1.1", function()
    assert.is_truthy(A.ipv4:match("192.168.1.1"))
  end)

  -- NOT-SPEC: library
  it("matches 239.255.255.255 (multicast top)", function()
    assert.is_truthy(A.ipv4:match("239.255.255.255"))
  end)

  -- NOT-SPEC: library
  it("rejects 256.0.0.0 (octet out of range)", function()
    assert.is_nil(A.ipv4:match("256.0.0.0"))
  end)

  -- NOT-SPEC: library
  it("rejects 1.2.3 (only three octets)", function()
    assert.is_nil(A.ipv4:match("1.2.3"))
  end)

  -- NOT-SPEC: library
  it("rejects 1.2.3.4.5 (trailing extra octet)", function()
    assert.is_nil(A.ipv4:match("1.2.3.4.5"))
  end)

  -- NOT-SPEC: library
  it("rejects 1.2.3.4/24 (suffix not allowed in the anchored pattern)", function()
    assert.is_nil(A.ipv4:match("1.2.3.4/24"))
  end)

  -- NOT-SPEC: library
  it("rejects empty string", function()
    assert.is_nil(A.ipv4:match(""))
  end)

end)

describe("addresses.ipv6 — RFC 4291 §2.2, anchored", function()

  -- NOT-SPEC: library
  it("matches ::", function()
    assert.is_truthy(A.ipv6:match("::"))
  end)

  -- NOT-SPEC: library
  it("matches ::1", function()
    assert.is_truthy(A.ipv6:match("::1"))
  end)

  -- NOT-SPEC: library
  it("matches a fully-expanded address", function()
    assert.is_truthy(A.ipv6:match("2001:db8:1234:5678:9abc:def0:1234:5678"))
  end)

  -- NOT-SPEC: library
  it("matches a compressed address with ::", function()
    assert.is_truthy(A.ipv6:match("2001:db8::1"))
  end)

  -- NOT-SPEC: library
  it("matches the link-local prefix fe80::1", function()
    assert.is_truthy(A.ipv6:match("fe80::1"))
  end)

  -- NOT-SPEC: library
  it("matches multicast ff02::1", function()
    assert.is_truthy(A.ipv6:match("ff02::1"))
  end)

  -- NOT-SPEC: library
  it("matches IPv4-mapped form ::ffff:192.168.1.1", function()
    assert.is_truthy(A.ipv6:match("::ffff:192.168.1.1"))
  end)

  -- NOT-SPEC: library
  it("rejects gggg::1 (non-hex character)", function()
    assert.is_nil(A.ipv6:match("gggg::1"))
  end)

  -- NOT-SPEC: library
  it("rejects 1:2:3:4:5:6:7:8:9 (too many groups)", function()
    assert.is_nil(A.ipv6:match("1:2:3:4:5:6:7:8:9"))
  end)

  -- NOT-SPEC: library
  it("rejects a plain IPv4 address (not IPv6)", function()
    assert.is_nil(A.ipv6:match("192.168.1.1"))
  end)

  -- NOT-SPEC: library
  it("rejects 2001:db8::1/64 (suffix not allowed in anchored pattern)", function()
    assert.is_nil(A.ipv6:match("2001:db8::1/64"))
  end)

end)

describe("addresses.is_ipv4_multicast", function()

  -- NOT-SPEC: library
  it("returns true for 224.0.0.1 (lowest mcast)", function()
    assert.is_true(A.is_ipv4_multicast("224.0.0.1"))
  end)

  -- NOT-SPEC: library
  it("returns true for 239.255.255.255 (highest mcast)", function()
    assert.is_true(A.is_ipv4_multicast("239.255.255.255"))
  end)

  -- NOT-SPEC: library
  it("returns false for 223.255.255.255 (just below mcast range)", function()
    assert.is_false(A.is_ipv4_multicast("223.255.255.255"))
  end)

  -- NOT-SPEC: library
  it("returns false for 240.0.0.1 (just above mcast range)", function()
    assert.is_false(A.is_ipv4_multicast("240.0.0.1"))
  end)

  -- NOT-SPEC: library
  it("returns false for typical unicast 192.168.1.1", function()
    assert.is_false(A.is_ipv4_multicast("192.168.1.1"))
  end)

end)

describe("addresses.is_ipv6_multicast", function()

  -- NOT-SPEC: library
  it("returns true for ff02::1", function()
    assert.is_true(A.is_ipv6_multicast("ff02::1"))
  end)

  -- NOT-SPEC: library
  it("returns true for FF02::1 (case-insensitive)", function()
    assert.is_true(A.is_ipv6_multicast("FF02::1"))
  end)

  -- NOT-SPEC: library
  it("returns false for 2001:db8::1", function()
    assert.is_false(A.is_ipv6_multicast("2001:db8::1"))
  end)

  -- NOT-SPEC: library
  it("returns false for fe80::1 (link-local but not multicast)", function()
    assert.is_false(A.is_ipv6_multicast("fe80::1"))
  end)

end)
