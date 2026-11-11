import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Meta Muse Agent in the bar. Left click: panel. Right click: open / bring
// Muse here. Middle click: hide it. Numbers come from ~/.local/bin/muse-ctl,
// which reads what the "Muse Usage for Omarchy" Chrome add-on saved.
Panel {
  id: root
  moduleName: "muse"
  ipcTarget: "muse"
  manageIpc: false

  readonly property string iconPath: Qt.resolvedUrl("assets/muse.png")
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color museBlue: "#1F6BFF"
  readonly property color museLight: "#5AA2FF"
  readonly property color warnColor: "#FFB020"
  readonly property color badColor: "#ED4245"

  property int openCount: 0
  property real weeklyPct: -1      // percent of the weekly allowance used
  property string resetText: ""
  property string plan: ""
  property real extraTokens: -1
  property real extraPeak: 0
  property int updated: 0
  property real nowSec: Date.now() / 1000

  readonly property bool isOpen: openCount > 0
  readonly property bool hasWeekly: weeklyPct >= 0
  readonly property bool hasExtra: extraTokens >= 0
  readonly property real weeklyAllowance: plan === "Maximum" ? 3e9 : plan === "Power" ? 5e8 : 0
  readonly property color weeklyColor: weeklyPct >= 90 ? badColor : weeklyPct >= 70 ? warnColor : museBlue

  function fmtTokens(v) {
    if (v < 0) return "–"
    if (v >= 1e12) return (v / 1e12).toFixed(1) + "T"
    if (v >= 1e9) return (v / 1e9).toFixed(v >= 1e10 ? 0 : 1) + "B"
    if (v >= 1e6) return (v / 1e6).toFixed(v >= 1e7 ? 0 : 1) + "M"
    if (v >= 1e3) return (v / 1e3).toFixed(0) + "K"
    return String(Math.round(v))
  }
  function ago(sec) {
    if (sec <= 0) return "never"
    var d = Math.max(0, Math.round(root.nowSec - sec))
    if (d < 90) return "just now"
    if (d < 5400) return Math.round(d / 60) + " min ago"
    if (d < 129600) return Math.round(d / 3600) + " h ago"
    return Math.round(d / 86400) + " days ago"
  }

  Process {
    id: stateProc
    command: ["muse-ctl", "state"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(String(this.text))
          root.openCount = Math.max(0, Math.min(99, parseInt(d.open) || 0))
          root.weeklyPct = typeof d.weeklyPct === "number" ? Math.max(0, Math.min(100, d.weeklyPct)) : -1
          root.resetText = typeof d.resetText === "string" ? d.resetText.slice(0, 48) : ""
          root.plan = (d.plan === "Free" || d.plan === "Power" || d.plan === "Maximum") ? d.plan : ""
          root.extraTokens = typeof d.extraTokens === "number" && d.extraTokens >= 0 ? d.extraTokens : -1
          root.extraPeak = typeof d.extraPeak === "number" ? d.extraPeak : 0
          root.updated = parseInt(d.updated) || 0
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: root.opened ? 1500 : 6000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.nowSec = Date.now() / 1000
      if (!stateProc.running) stateProc.running = true
    }
  }
  Timer { id: refreshSoon; interval: 600; onTriggered: if (!stateProc.running) stateProc.running = true }

  function ctl(arg) { if (root.bar) root.bar.run("muse-ctl " + arg); refreshSoon.restart() }

  IpcHandler {
    id: ipc
    target: root.ipcTarget
    function toggle(): string { root.toggle(); return root.opened ? "open" : "closed" }
    function show(): string { root.ctl("open"); return "summoned" }
    Component.onCompleted: IpcRegistry.register(ipc)
    Component.onDestruction: IpcRegistry.unregister(ipc)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: ""
    onPressed: function(code) {
      if (code === Qt.RightButton) root.ctl("open")
      else if (code === Qt.MiddleButton) root.ctl("hide")
      else root.toggle()
    }
    iconComponent: Component {
      Item {
        width: 22
        height: 22
        Image {
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: 20
          height: root.hasWeekly ? 17 : 20
          source: root.iconPath
          sourceSize.width: 64
          sourceSize.height: 64
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          opacity: root.isOpen ? 1.0 : 0.7
        }
        // Mini quota meter under the icon: how much of the week is LEFT
        Rectangle {
          visible: root.hasWeekly
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: 20
          height: 3
          radius: 1.5
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
          Rectangle {
            width: parent.width * Math.max(0, 100 - root.weeklyPct) / 100
            height: parent.height
            radius: 1.5
            color: root.weeklyColor
          }
        }
      }
    }
  }

  component Meter: Column {
    id: meter
    property string title: ""
    property string valueText: ""
    property string subText: ""
    property real fraction: 0
    property color barColor: root.museBlue
    property bool known: true
    width: parent ? parent.width : 0
    spacing: Style.space(4)
    Item {
      width: parent.width
      height: titleText.implicitHeight
      Text {
        id: titleText
        anchors.left: parent.left
        textFormat: Text.PlainText
        text: meter.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: meter.known ? meter.valueText : "not read yet"
        color: meter.known ? root.foreground : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Rectangle {
      width: parent.width
      height: Style.space(10)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      Rectangle {
        visible: meter.known
        width: Math.max(height, parent.width * Math.max(0, Math.min(1, meter.fraction)))
        height: parent.height
        radius: height / 2
        color: meter.barColor
        Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
      }
    }
    Text {
      visible: meter.subText.length > 0
      width: parent.width
      textFormat: Text.PlainText
      text: meter.subText
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  component ActionRow: Rectangle {
    id: row
    property string label: ""
    property color tint: root.foreground
    property real fill: 0.12
    property bool enabledRow: true
    signal activated()
    width: parent ? parent.width : 0
    height: Style.space(30)
    radius: Style.space(6)
    opacity: enabledRow ? 1.0 : 0.45
    color: Qt.rgba(tint.r, tint.g, tint.b, rowArea.containsMouse && enabledRow ? fill + 0.1 : fill)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      width: parent.width - Style.space(20)
      textFormat: Text.PlainText
      text: row.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    MouseArea {
      id: rowArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: row.enabledRow
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activated()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(560))

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "o" || t === "O") { root.ctl("open"); root.close() }
        else if (t === "r" || t === "R") { root.ctl("usage"); root.close() }
      }
      clip: true

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        Row {
          spacing: Style.space(10)
          Image {
            width: 34; height: 34
            source: root.iconPath
            sourceSize.width: 72; sourceSize.height: 72
            fillMode: Image.PreserveAspectFit
            smooth: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            Text {
              textFormat: Text.PlainText
              text: "Muse" + (root.plan.length > 0 ? " · " + root.plan : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              text: (root.isOpen ? "Open" : "Not open") + " · numbers " + root.ago(root.updated)
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Meter {
          title: "Weekly quota"
          known: root.hasWeekly
          fraction: root.weeklyPct / 100
          barColor: root.weeklyColor
          valueText: Math.round(root.weeklyPct) + "% used"
                     + (root.weeklyAllowance > 0 ? " of " + root.fmtTokens(root.weeklyAllowance) : "")
          subText: root.hasWeekly
                   ? (root.resetText.length > 0 ? "Resets " + root.resetText : "")
                   : (root.updated > 0 ? "Open Muse settings once (button below) to fill this in" : "Needs the Muse Usage add-on in Chrome: chrome://extensions, Developer mode, Load unpacked, ~/.local/share/muse-agent/usage-extension")
        }

        Meter {
          title: "Additional tokens"
          known: root.hasExtra
          fraction: root.extraPeak > 0 ? root.extraTokens / root.extraPeak : 1
          barColor: root.museLight
          valueText: root.fmtTokens(root.extraTokens) + " left"
          subText: root.hasExtra
                   ? (root.extraPeak > root.extraTokens ? "Was " + root.fmtTokens(root.extraPeak) + " · no expiry" : "Separate from the weekly quota · no expiry")
                   : ""
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        Column {
          width: parent.width
          spacing: Style.space(8)
          ActionRow {
            label: root.isOpen ? "Bring Muse here" : "Open Muse"
            tint: root.museBlue
            fill: 0.35
            onActivated: { root.ctl("open"); root.close() }
          }
          ActionRow {
            label: "Refresh numbers (opens Muse settings)"
            onActivated: { root.ctl("usage"); root.close() }
          }
          ActionRow {
            label: "Hide Muse"
            enabledRow: root.isOpen
            onActivated: root.ctl("hide")
          }
          ActionRow {
            label: "Close Muse"
            enabledRow: root.isOpen
            onActivated: root.ctl("close")
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Right-click icon = open · middle-click = hide · o open · r refresh"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
