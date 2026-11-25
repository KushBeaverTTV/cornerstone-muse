// Plain formatting, parsing and source-merging logic for Cornerstone Muse.
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

function formatReset(iso, nowSec) {
  var s = String(iso || "").trim()
  if (!s) return ""
  var ms = Date.parse(s)
  if (!isFinite(ms)) return s.slice(0, 48)
  var diff = Math.round(ms / 1000 - (Number(nowSec) || Date.now() / 1000))
  if (diff <= 60) return "soon"
  var mins = Math.round(diff / 60)
  if (mins < 60) return "in " + mins + "m"
  var hours = Math.floor(mins / 60)
  var remMins = mins % 60
  if (hours < 24) return "in " + hours + "h" + (remMins > 0 ? " " + remMins + "m" : "")
  var days = Math.floor(hours / 24)
  var remHours = hours % 24
  return "in " + days + "d" + (remHours > 0 ? " " + remHours + "h" : "")
}

function weeklyAllowance(plan) {
  var p = String(plan || "").toLowerCase()
  if (p.indexOf("maximum") !== -1 || p === "max") return 3e9
  if (p.indexOf("power") !== -1) return 5e8
  return 0
}

function cleanPlan(raw) {
  var s = String(raw || "").trim().slice(0, 32)
  return s
}

// Parse ~/.local/state/muse-widget/usage.json written by the Chrome add-on.
function parseUsage(text) {
  var d
  try { d = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!d || typeof d !== "object" || Array.isArray(d)) return null
  return {
    sessionPct: typeof d.sessionPct === "number" && isFinite(d.sessionPct)
      ? Math.max(0, Math.min(100, d.sessionPct)) : -1,
    sessionResetText: typeof d.sessionResetText === "string" ? d.sessionResetText.slice(0, 48) : "",
    weeklyPct: typeof d.weeklyPct === "number" && isFinite(d.weeklyPct)
      ? Math.max(0, Math.min(100, d.weeklyPct)) : -1,
    resetText: typeof d.resetText === "string" ? d.resetText.slice(0, 48) : "",
    plan: cleanPlan(d.plan),
    extraTokens: typeof d.extraTokens === "number" && isFinite(d.extraTokens) && d.extraTokens >= 0
      ? d.extraTokens : -1,
    extraPeak: typeof d.extraPeak === "number" && isFinite(d.extraPeak) && d.extraPeak >= 0
      ? d.extraPeak : 0,
    updated: parseInt(d.updated, 10) || 0,
    source: "web"
  }
}

// Parse ~/.local/state/omarchy/agents/usage/muse.json written by omarchy-agent-usage-muse.
function parseAgentUsage(text, nowSec) {
  var d
  try { d = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!d || typeof d !== "object" || Array.isArray(d)) return null
  var limits = Array.isArray(d.limits) ? d.limits : []
  var sessionPct = -1
  var sessionResetText = ""
  var weeklyPct = -1
  var resetText = ""
  for (var i = 0; i < limits.length; i++) {
    var lim = limits[i]
    if (!lim || typeof lim.percent !== "number" || !isFinite(lim.percent)) continue
    var pct = Math.max(0, Math.min(100, Math.round(lim.percent * 1000) / 10))
    var label = String(lim.label || lim.title || "").toLowerCase()
    var reset = formatReset(lim.resetsAt, nowSec)
    if (label.indexOf("week") !== -1 || label.indexOf("7-day") !== -1 || label.indexOf("7d") !== -1) {
      weeklyPct = pct
      resetText = reset
    } else if (label.indexOf("session") !== -1 || label.indexOf("5-hour") !== -1 || label.indexOf("5h") !== -1) {
      sessionPct = pct
      sessionResetText = reset
    } else if (weeklyPct < 0) {
      weeklyPct = pct
      resetText = reset
    }
  }
  var fetchedMs = Number(d.limitsFetchedAt) || 0
  var updated = fetchedMs > 0 ? Math.round(fetchedMs / 1000) : 0
  var todayTokens = Number(d.todayTotalTokens) || 0
  var todayPrompts = Number(d.todayPrompts) || 0
  if (weeklyPct < 0 && sessionPct < 0 && !d.tierLabel && todayTokens <= 0 && todayPrompts <= 0) return null
  return {
    sessionPct: sessionPct,
    sessionResetText: sessionResetText,
    weeklyPct: weeklyPct,
    resetText: resetText,
    plan: cleanPlan(d.tierLabel),
    extraTokens: -1,
    extraPeak: 0,
    todayTokens: todayTokens,
    todayPrompts: todayPrompts,
    stale: d.limitsStale === true,
    updated: updated,
    source: "cli"
  }
}

// Merge web add-on data and Omarchy CLI collector data, preferring the fresher
// quota reading when both are present while keeping extraTokens from web and
// session/local stats from CLI.
function mergeUsage(web, agent) {
  var w = web || null
  var a = agent || null
  if (!w && !a) {
    return {
      sessionPct: -1, sessionResetText: "", weeklyPct: -1, resetText: "",
      plan: "", extraTokens: -1, extraPeak: 0, todayTokens: 0, todayPrompts: 0,
      stale: false, updated: 0, source: ""
    }
  }
  var pickAgentWeekly = !!a && a.weeklyPct >= 0 && (!w || w.weeklyPct < 0 || a.updated >= w.updated)
  var weeklyPct = pickAgentWeekly ? a.weeklyPct : (w && w.weeklyPct >= 0 ? w.weeklyPct : -1)
  var resetText = pickAgentWeekly ? a.resetText : (w && w.weeklyPct >= 0 ? w.resetText : "")
  var sessionPct = a && a.sessionPct >= 0 ? a.sessionPct : (w && w.sessionPct >= 0 ? w.sessionPct : -1)
  var sessionResetText = a && a.sessionPct >= 0 ? a.sessionResetText : (w && w.sessionPct >= 0 ? w.sessionResetText : "")
  var plan = (pickAgentWeekly ? (a && a.plan) : (w && w.plan)) || (a && a.plan) || (w && w.plan) || ""
  var updated = Math.max(w ? w.updated : 0, a ? a.updated : 0)
  return {
    sessionPct: sessionPct,
    sessionResetText: sessionResetText,
    weeklyPct: weeklyPct,
    resetText: resetText,
    plan: plan,
    extraTokens: w ? w.extraTokens : -1,
    extraPeak: w ? w.extraPeak : 0,
    todayTokens: a ? a.todayTokens : 0,
    todayPrompts: a ? a.todayPrompts : 0,
    stale: !!(pickAgentWeekly && a && a.stale),
    updated: updated,
    source: pickAgentWeekly ? "cli" : (w && (w.weeklyPct >= 0 || w.extraTokens >= 0) ? "web" : (a ? "cli" : ""))
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    fmtTokens: fmtTokens,
    ago: ago,
    formatReset: formatReset,
    weeklyAllowance: weeklyAllowance,
    parseUsage: parseUsage,
    parseAgentUsage: parseAgentUsage,
    mergeUsage: mergeUsage
  }
}
