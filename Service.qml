import QtQuick
import Quickshell
import Quickshell.Io
import "Muse.js" as Muse

// Single session-wide service for Cornerstone Muse.
// Reads quota from both:
//   1. ~/.local/state/muse-widget/usage.json (Chrome add-on for muse.ai web)
//   2. ~/.local/state/omarchy/agents/usage/muse.json (Omarchy's built-in
//      omarchy-agent-usage-muse collector when signed in via `muse login`)
// Reloads both files explicitly on refresh so newly-created or atomically
// replaced files are never missed by FileView's watcher.
Item {
  id: service

  property var shell: null
  readonly property string pluginId: "cornerstone.muse"
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string usagePath: stateHome + "/muse-widget/usage.json"
  readonly property string agentUsagePath: stateHome + "/omarchy/agents/usage/muse.json"
  readonly property string windowPattern: "^chrome-(muse\\.ai|agent\\.meta\\.ai)__.*$"

  property int openCount: 0
  property var webUsage: null
  property var agentUsage: null
  property real nowSec: Date.now() / 1000
  property int watchers: 0
  property bool refreshing: false

  readonly property var merged: Muse.mergeUsage(webUsage, agentUsage)
  readonly property bool isOpen: openCount > 0
  readonly property bool hasSession: merged.sessionPct >= 0
  readonly property bool hasWeekly: merged.weeklyPct >= 0
  readonly property bool hasExtra: merged.extraTokens >= 0
  readonly property real sessionPct: merged.sessionPct
  readonly property string sessionResetText: merged.sessionResetText
  readonly property real weeklyPct: merged.weeklyPct
  readonly property string resetText: merged.resetText
  readonly property string plan: merged.plan
  readonly property real extraTokens: merged.extraTokens
  readonly property real extraPeak: merged.extraPeak
  readonly property real todayTokens: merged.todayTokens
  readonly property int todayPrompts: merged.todayPrompts
  readonly property bool stale: merged.stale
  readonly property int updated: merged.updated
  readonly property string source: merged.source
  readonly property real weeklyAllowance: Muse.weeklyAllowance(plan)

  function applyWebUsage(text) {
    var u = Muse.parseUsage(text)
    if (u) webUsage = u
    nowSec = Date.now() / 1000
  }

  function applyAgentUsage(text) {
    nowSec = Date.now() / 1000
    var u = Muse.parseAgentUsage(text, nowSec)
    if (u) agentUsage = u
  }

  function reloadFiles() {
    nowSec = Date.now() / 1000
    usageFile.reload()
    agentUsageFile.reload()
  }

  function refreshWindows() {
    reloadFiles()
    if (!winProc.running) winProc.running = true
  }

  function refreshAll() {
    refreshWindows()
    if (!probeProc.running) {
      refreshing = true
      probeProc.running = true
    }
  }

  function loginCli() {
    Quickshell.execDetached(["omarchy-launch-tui", "muse", "login"])
  }

  function ctl(arg) {
    var a = String(arg || "")
    if (["open", "usage", "hide", "close"].indexOf(a) === -1) return
    Quickshell.execDetached(["muse-ctl", a])
    refreshSoon.restart()
  }

  FileView {
    id: usageFile
    path: service.usagePath
    watchChanges: true
    printErrors: false
    onLoaded: service.applyWebUsage(text())
    onFileChanged: reload()
  }

  FileView {
    id: agentUsageFile
    path: service.agentUsagePath
    watchChanges: true
    printErrors: false
    onLoaded: service.applyAgentUsage(text())
    onFileChanged: reload()
  }

  Process {
    id: winProc
    command: ["app-summon", "--count", service.windowPattern]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.openCount = Math.max(0, Math.min(99, parseInt(String(this.text || "").trim(), 10) || 0))
      }
    }
  }

  Process {
    id: probeProc
    command: ["omarchy-agent-usage-muse", "--force"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.applyAgentUsage(this.text)
    }
    onExited: {
      service.refreshing = false
      service.reloadFiles()
    }
  }

  // Fast while panel is open, gentle when closed.
  Timer {
    interval: service.watchers > 0 ? 2000 : 12000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refreshWindows()
  }

  Timer {
    id: refreshSoon
    interval: 800
    onTriggered: service.refreshWindows()
  }

  IpcHandler {
    target: "muse"

    function toggle(): string { if (service.shell) service.shell.toggle(service.pluginId); return "ok" }
    function show(): string { service.ctl("open"); return "summoned" }
    function refresh(): string { service.refreshAll(); return "ok" }
  }
}
