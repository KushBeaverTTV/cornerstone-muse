import QtQuick
import Quickshell
import Quickshell.Io
import "Muse.js" as Muse

// Single session-wide service for Cornerstone Muse: watches usage.json with
// FileView (instant updates with zero polling), checks open window count only
// gently (or on demand when the panel opens / after actions), and owns the
// single `muse` IPC target across all monitors.
Item {
  id: service

  property var shell: null
  readonly property string pluginId: "cornerstone.muse"
  readonly property string usagePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/muse-widget/usage.json"
  readonly property string windowPattern: "^chrome-(muse\\.ai|agent\\.meta\\.ai)__.*$"

  property int openCount: 0
  property real weeklyPct: -1
  property string resetText: ""
  property string plan: ""
  property real extraTokens: -1
  property real extraPeak: 0
  property int updated: 0
  property real nowSec: Date.now() / 1000
  property int watchers: 0

  readonly property bool isOpen: openCount > 0
  readonly property bool hasWeekly: weeklyPct >= 0
  readonly property bool hasExtra: extraTokens >= 0
  readonly property real weeklyAllowance: Muse.weeklyAllowance(plan)

  function applyUsage(text) {
    var u = Muse.parseUsage(text)
    if (!u) return
    weeklyPct = u.weeklyPct
    resetText = u.resetText
    plan = u.plan
    extraTokens = u.extraTokens
    extraPeak = u.extraPeak
    updated = u.updated
    nowSec = Date.now() / 1000
  }

  function refreshWindows() {
    nowSec = Date.now() / 1000
    if (!winProc.running) winProc.running = true
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
    onLoaded: service.applyUsage(text())
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

  // Fast while panel is open, gentle when closed (usage.json itself is FileView-watched).
  Timer {
    interval: service.watchers > 0 ? 2000 : 12000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refreshWindows()
  }

  Timer {
    id: refreshSoon
    interval: 600
    onTriggered: service.refreshWindows()
  }

  IpcHandler {
    target: "muse"

    function toggle(): string { if (service.shell) service.shell.toggle(service.pluginId); return "ok" }
    function show(): string { service.ctl("open"); return "summoned" }
    function refresh(): string { usageFile.reload(); service.refreshWindows(); return "ok" }
  }
}
