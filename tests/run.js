const assert = require("node:assert/strict")
const Muse = require("../Muse.js")

assert.equal(Muse.fmtTokens(-1), "–")
assert.equal(Muse.fmtTokens(500), "500")
assert.equal(Muse.fmtTokens(1500), "2K")
assert.equal(Muse.fmtTokens(2.5e6), "2.5M")
assert.equal(Muse.fmtTokens(3e9), "3.0B")
assert.equal(Muse.fmtTokens(1.2e12), "1.2T")

const NOW = 1700000000
assert.equal(Muse.ago(0, NOW), "never")
assert.equal(Muse.ago(NOW - 30, NOW), "just now")
assert.equal(Muse.ago(NOW - 300, NOW), "5 min ago")
assert.equal(Muse.ago(NOW - 7200, NOW), "2 h ago")
assert.equal(Muse.ago(NOW - 172800, NOW), "2 days ago")

assert.equal(Muse.weeklyAllowance("Maximum"), 3e9)
assert.equal(Muse.weeklyAllowance("Power"), 5e8)
assert.equal(Muse.weeklyAllowance("Free"), 0)

assert.equal(Muse.parseUsage("{"), null)
assert.equal(Muse.parseUsage("[]"), null)
const parsed = Muse.parseUsage(JSON.stringify({
  weeklyPct: 142,
  plan: "Power",
  resetText: "Monday at 00:00",
  extraTokens: 1250000,
  extraPeak: 5000000,
  updated: 1700000000
}))
assert.equal(parsed.weeklyPct, 100)
assert.equal(parsed.plan, "Power")
assert.equal(parsed.extraTokens, 1250000)
assert.equal(parsed.updated, 1700000000)

console.log("PASS cornerstone.muse unit tests")
