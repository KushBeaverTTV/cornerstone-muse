import QtQuick
import qs.Commons
import qs.Ui
import "Muse.js" as Muse

// Meta Muse Agent in the bar. Built once per monitor; FileView watchers,
// CLI collector probe, window checks, actions and IPC live in Service.qml.
// Left click: panel. Right click: open / bring Muse here. Middle click: hide.
Panel {
  id: root
  moduleName: "cornerstone.muse"
  ipcTarget: "muse"
  manageIpc: false

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("cornerstone.muse") : null
  readonly property string iconPath: Qt.resolvedUrl("assets/muse.png")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property color hairline: Qt.darker(foreground, 2.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color museBlue: "#1F6BFF"
  readonly property color museLight: "#5AA2FF"
  readonly property color warnColor: "#FFB020"
  readonly property color badColor: Color.urgent

  readonly property bool isOpen: service ? service.isOpen : false
  readonly property bool hasSession: service ? service.hasSession : false
  readonly property bool hasWeekly: service ? service.hasWeekly : false
  readonly property bool hasExtra: service ? service.hasExtra : false
  readonly property bool hasAnyData: hasSession || hasWeekly || hasExtra || todayTokens > 0 || todayPrompts > 0
  readonly property real sessionPct: service ? service.sessionPct : -1
  readonly property string sessionResetText: service ? service.sessionResetText : ""
  readonly property real weeklyPct: service ? service.weeklyPct : -1
  readonly property string resetText: service ? service.resetText : ""
  readonly property string plan: service ? service.plan : ""
  readonly property real extraTokens: service ? service.extraTokens : -1
  readonly property real extraPeak: service ? service.extraPeak : 0
  readonly property real todayTokens: service ? service.todayTokens : 0
  readonly property int todayPrompts: service ? service.todayPrompts : 0
  readonly property bool refreshing: service ? service.refreshing : false
  readonly property int updated: service ? service.updated : 0
  readonly property real nowSec: service ? service.nowSec : Date.now() / 1000
  readonly property real weeklyAllowance: service ? service.weeklyAllowance : 0
  readonly property color sessionColor: sessionPct >= 90 ? badColor : sessionPct >= 70 ? warnColor : museLight
  readonly property color weeklyColor: weeklyPct >= 90 ? badColor : weeklyPct >= 70 ? warnColor : museBlue

  readonly property string barTooltip: {
    var parts = ["Muse"]
    if (hasSession) parts.push("5h " + Math.round(sessionPct) + "%")
    if (hasWeekly) parts.push("Week " + Math.round(weeklyPct) + "%")
    if (!hasSession && !hasWeekly) parts.push(isOpen ? "Open" : "Not open")
    if (hasExtra) parts.push(Muse.fmtTokens(extraTokens) + " extra")
    return parts.join(" · ")
  }

  readonly property var stops: {
    var list = ["open", "refresh", "usage"]
    if (!hasAnyData) list.push("login")
    if (isOpen) { list.push("hide"); list.push("close") }
    return list
  }

  property int cursor: -1
  property bool watching: false

  onOpenedChanged: {
    cursor = -1
    if (service) {
      if (opened && !watching) { watching = true; service.watchers++; service.refreshWindows() }
      else if (!opened && watching) { watching = false; service.watchers = Math.max(0, service.watchers - 1) }
    }
  }
  Component.onDestruction: {
    if (watching && service) service.watchers = Math.max(0, service.watchers - 1)
  }

  function stopIndex(id) { return stops.indexOf(id) }

  function activateStop(id) {
    if (!service) return
    if (id === "open") { service.ctl("open"); root.close() }
    else if (id === "refresh") service.refreshAll()
    else if (id === "usage") { service.ctl("usage"); root.close() }
    else if (id === "login") { service.loginCli(); root.close() }
    else if (id === "hide" && isOpen) service.ctl("hide")
    else if (id === "close" && isOpen) service.ctl("close")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function(code) {
      if (code === Qt.RightButton && root.service) root.service.ctl("open")
      else if (code === Qt.MiddleButton && root.service) root.service.ctl("hide")
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
          height: (root.hasWeekly || root.hasSession) ? 17 : 20
          source: root.iconPath
          sourceSize.width: 64
          sourceSize.height: 64
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          opacity: root.isOpen || root.hasAnyData ? 1.0 : 0.7
        }
        // Mini quota meter under the icon: how much of the quota is LEFT
        Rectangle {
          visible: root.hasWeekly || root.hasSession
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: 20
          height: 3
          radius: 1.5
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
          Rectangle {
            readonly property real pct: root.hasWeekly ? root.weeklyPct : root.sessionPct
            width: parent.width * Math.max(0, 100 - pct) / 100
            height: parent.height
            radius: 1.5
            color: root.hasWeekly ? root.weeklyColor : root.sessionColor
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
    property bool focused: false
    signal hovered()
    signal activated()
    width: parent ? parent.width : 0
    height: Style.space(30)
    radius: Style.space(6)
    opacity: enabledRow ? 1.0 : 0.45
    color: Qt.rgba(tint.r, tint.g, tint.b, (rowArea.containsMouse || focused) && enabledRow ? fill + 0.1 : fill)
    border.width: focused && enabledRow ? 1 : 0
    border.color: Color.accent
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
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
      onEntered: row.hovered()
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
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || root.stops.length === 0) return
        var n = root.stops.length
        root.cursor = root.cursor < 0 ? (dy > 0 ? 0 : n - 1) : (root.cursor + dy + n) % n
      }
      onActivateRequested: {
        if (root.cursor >= 0 && root.cursor < root.stops.length)
          root.activateStop(root.stops[root.cursor])
      }
      onTextKey: function(t) {
        if (!root.service) return
        if (t === "o" || t === "O") { root.service.ctl("open"); root.close() }
        else if (t === "r" || t === "R") root.service.refreshAll()
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
            mipmap: true
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
              text: (root.isOpen ? "Open" : "Not open")
                    + " · " + (root.refreshing ? "refreshing…" : ("updated " + Muse.ago(root.updated, root.nowSec)))
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Meter {
          visible: root.hasSession
          title: "Session quota (5h)"
          known: root.hasSession
          fraction: root.sessionPct / 100
          barColor: root.sessionColor
          valueText: Math.round(root.sessionPct) + "% used"
          subText: root.sessionResetText.length > 0 ? "Resets " + root.sessionResetText : ""
        }

        Meter {
          title: "Weekly quota"
          known: root.hasWeekly
          fraction: root.weeklyPct / 100
          barColor: root.weeklyColor
          valueText: Math.round(root.weeklyPct) + "% used"
                     + (root.weeklyAllowance > 0 ? " of " + Muse.fmtTokens(root.weeklyAllowance) : "")
          subText: root.hasWeekly
                   ? (root.resetText.length > 0 ? "Resets " + root.resetText : "")
                   : "Sign in with Muse CLI below for automatic quota sync, or load the Chrome add-on from ~/.local/share/muse-agent/usage-extension."
        }

        Meter {
          visible: root.hasExtra
          title: "Additional tokens"
          known: root.hasExtra
          fraction: root.extraPeak > 0 ? root.extraTokens / root.extraPeak : 1
          barColor: root.museLight
          valueText: Muse.fmtTokens(root.extraTokens) + " left"
          subText: root.extraPeak > root.extraTokens
                   ? "Was " + Muse.fmtTokens(root.extraPeak) + " · no expiry"
                   : "Separate from the weekly quota · no expiry"
        }

        Text {
          visible: root.todayTokens > 0 || root.todayPrompts > 0
          width: parent.width
          textFormat: Text.PlainText
          text: "Today (CLI): " + root.todayPrompts + " prompt" + (root.todayPrompts === 1 ? "" : "s")
                + (root.todayTokens > 0 ? " · " + Muse.fmtTokens(root.todayTokens) + " tokens" : "")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        Column {
          width: parent.width
          spacing: Style.space(8)
          ActionRow {
            label: root.isOpen ? "Bring Muse here" : "Open Muse"
            tint: root.museBlue
            fill: 0.35
            focused: root.cursor === root.stopIndex("open")
            onHovered: root.cursor = root.stopIndex("open")
            onActivated: root.activateStop("open")
          }
          ActionRow {
            label: root.refreshing ? "Refreshing quota…" : "Refresh quota now"
            enabledRow: !root.refreshing
            focused: root.cursor === root.stopIndex("refresh")
            onHovered: if (!root.refreshing) root.cursor = root.stopIndex("refresh")
            onActivated: root.activateStop("refresh")
          }
          ActionRow {
            label: "Open Muse settings (web)"
            focused: root.cursor === root.stopIndex("usage")
            onHovered: root.cursor = root.stopIndex("usage")
            onActivated: root.activateStop("usage")
          }
          ActionRow {
            visible: !root.hasAnyData
            label: "Sign in to Muse CLI (auto-sync quota)"
            tint: Color.accent
            fill: 0.18
            focused: root.cursor === root.stopIndex("login")
            onHovered: root.cursor = root.stopIndex("login")
            onActivated: root.activateStop("login")
          }
          ActionRow {
            visible: root.isOpen
            label: "Hide Muse"
            focused: root.cursor === root.stopIndex("hide")
            onHovered: root.cursor = root.stopIndex("hide")
            onActivated: root.activateStop("hide")
          }
          ActionRow {
            visible: root.isOpen
            label: "Close Muse"
            focused: root.cursor === root.stopIndex("close")
            onHovered: root.cursor = root.stopIndex("close")
            onActivated: root.activateStop("close")
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Right-click = open · middle-click = hide · j/k + Enter navigate · o open · r refresh"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
