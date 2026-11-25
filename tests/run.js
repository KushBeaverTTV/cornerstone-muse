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

assert.equal(Muse.formatReset(new Date((NOW + 9000) * 1000).toISOString(), NOW), "in 2h 30m")
assert.equal(Muse.formatReset(new Date((NOW + 180000) * 1000).toISOString(), NOW), "in 2d 2h")

assert.equal(Muse.weeklyAllowance("Maximum"), 3e9)
assert.equal(Muse.weeklyAllowance("Power"), 5e8)
assert.equal(Muse.weeklyAllowance("Free"), 0)

assert.equal(Muse.parseUsage("{"), null)
assert.equal(Muse.parseUsage("[]"), null)
const web = Muse.parseUsage(JSON.stringify({
  weeklyPct: 142,
  plan: "Power",
  resetText: "Monday at 00:00",
  extraTokens: 1250000,
  extraPeak: 5000000,
  updated: NOW - 100
}))
assert.equal(web.weeklyPct, 100)
assert.equal(web.plan, "Power")
assert.equal(web.extraTokens, 1250000)

const agent = Muse.parseAgentUsage(JSON.stringify({
  id: "muse",
  tierLabel: "Power",
  limits: [
    { label: "Session (5-hour)", percent: 0.25, resetsAt: new Date((NOW + 3600) * 1000).toISOString() },
    { label: "Weekly (7-day)", percent: 0.42, resetsAt: new Date((NOW + 86400) * 1000).toISOString() }
  ],
  limitsFetchedAt: NOW * 1000,
  todayPrompts: 5,
  todayTotalTokens: 250000
}), NOW)
assert.equal(agent.sessionPct, 25)
assert.equal(agent.weeklyPct, 42)
assert.equal(agent.sessionResetText, "in 1h")
assert.equal(agent.resetText, "in 1d")

const merged = Muse.mergeUsage(web, agent)
assert.equal(merged.weeklyPct, 42)          // fresher CLI weekly wins
assert.equal(merged.sessionPct, 25)         // CLI 5h session kept
assert.equal(merged.extraTokens, 1250000)   // web extraTokens preserved
assert.equal(merged.todayPrompts, 5)

console.log("PASS cornerstone.muse unit tests")
