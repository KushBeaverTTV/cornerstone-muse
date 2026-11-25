// Plain formatting and parsing logic for Cornerstone Muse (Meta Muse Agent).
// No Qt dependencies so `node tests/run.js` tests it directly.

function fmtTokens(v) {
  var n = Number(v)
  if (!isFinite(n) || n < 0) return "–"
  if (n >= 1e12) return (n / 1e12).toFixed(1) + "T"
  if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
  if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(0) + "K"
  return String(Math.round(n))
}

function ago(sec, nowSec) {
  var s = Number(sec) || 0
  if (s <= 0) return "never"
  var d = Math.max(0, Math.round((Number(nowSec) || 0) - s))
  if (d < 90) return "just now"
  if (d < 5400) return Math.round(d / 60) + " min ago"
  if (d < 129600) return Math.round(d / 3600) + " h ago"
  return Math.round(d / 86400) + " days ago"
}

function weeklyAllowance(plan) {
  return plan === "Maximum" ? 3e9 : plan === "Power" ? 5e8 : 0
}

function parseUsage(text) {
  var d
  try { d = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!d || typeof d !== "object" || Array.isArray(d)) return null
  var plan = (d.plan === "Free" || d.plan === "Power" || d.plan === "Maximum") ? d.plan : ""
  return {
    weeklyPct: typeof d.weeklyPct === "number" && isFinite(d.weeklyPct)
      ? Math.max(0, Math.min(100, d.weeklyPct)) : -1,
    resetText: typeof d.resetText === "string" ? d.resetText.slice(0, 48) : "",
    plan: plan,
    extraTokens: typeof d.extraTokens === "number" && isFinite(d.extraTokens) && d.extraTokens >= 0
      ? d.extraTokens : -1,
    extraPeak: typeof d.extraPeak === "number" && isFinite(d.extraPeak) && d.extraPeak >= 0
      ? d.extraPeak : 0,
    updated: parseInt(d.updated, 10) || 0
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    fmtTokens: fmtTokens,
    ago: ago,
    weeklyAllowance: weeklyAllowance,
    parseUsage: parseUsage
  }
}
