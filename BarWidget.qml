import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// wh — herdr agents on the bar.
//
// Replaces the herdr sidebar with a bar slot in the standard omarchy icon
// footprint: ONE state-colored glyph (blocked alert · working active ·
// done check; dimmed when nothing is active), never any counts — those
// live in the hover tooltip and in the panel, which lists every agent
// grouped by workspace. A click on a row focuses the window viewing that
// pane, spawning one (foot + `wh <pane_id>`) when no window has it.
// Claims stay where the user put them: the bar never changes geometry,
// it only moves focus.
Panel {
  id: root
  moduleName: "winherd"
  ipcTarget: "winherd"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // No theme tokens for state colors, so they are fixed and chosen to work
  // on both dark and light omarchy themes.
  readonly property color cWorking: "#98c379"
  readonly property color cBlocked: "#e06c75"
  readonly property color cDone: "#61afef"
  readonly property color cIdle: dim

  property var agents: []
  property var wsLabels: ({})
  property int dataRev: 0
  property string whBin: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null || value === "") ? fallback : value
  }

  readonly property int refreshIntervalSec: Math.max(1, Math.floor(Number(setting("refreshIntervalSec", 2))))

  function stateColor(status) {
    if (status === "working") return cWorking
    if (status === "blocked") return cBlocked
    if (status === "done") return cDone
    return cIdle
  }

  // The bar slot shows ONE icon in the standard icon-slot footprint, like
  // every neighbouring widget. Icon carries the worst active state by color
  // and glyph; counts never go in the bar — the hover tooltip and the panel
  // carry the breakdown.
  readonly property string barState: {
    var rev = root.dataRev
    var c = root.counts
    if (c.blocked > 0) return "blocked"
    if (c.working > 0) return "working"
    if (c.done > 0) return "done"
    return "idle"
  }

  readonly property string barTooltip: {
    var rev = root.dataRev
    var c = root.counts
    var parts = []
    if (c.working > 0) parts.push(c.working + " working")
    if (c.blocked > 0) parts.push(c.blocked + " blocked")
    if (c.done > 0) parts.push(c.done + " done")
    if (c.idle > 0) parts.push(c.idle + " idle")
    if (c.unknown > 0) parts.push(c.unknown + " unknown")
    return "winherd — " + (parts.length ? parts.join(" · ") : "none")
  }

  // Waiting-on-you: the badge's number. Blocked or done and not yet
  // seen — counts already skips acknowledged agents.
  readonly property int attentionCount: {
    var rev = root.dataRev
    var c = root.counts
    return (c.blocked || 0) + (c.done || 0)
  }

  // ------------------------------------------------------- done dismissal
  // The done alarm is a notification, so it can be dismissed: activating a
  // done agent's window (focus or fresh spawn) counts as "I looked at it".
  // Acks are derived state, not a ledger — they survive only while the
  // agent is still reported done, so a finished agent that starts and
  // finishes AGAIN re-alerts with no bookkeeping. Everything downstream
  // (bar state, +N, tooltip, hero meta) derives from counts, which simply
  // skip acked agents.
  property var acked: ({})

  function pruneDoneAcks() {
    var keep = {}
    for (var i = 0; i < root.agents.length; i++) {
      var a = root.agents[i]
      if ((a.agent_status || "") === "done" && root.acked[a.pane_id])
        keep[a.pane_id] = true
    }
    root.acked = keep
  }

  function ackPane(paneId) {
    if (!paneId || root.acked[paneId])
      return
    var next = {}
    for (var k in root.acked) next[k] = root.acked[k]
    next[paneId] = true
    root.acked = next
    root.dataRev++
  }

  readonly property var counts: {
    var rev = root.dataRev
    var c = { working: 0, blocked: 0, done: 0, idle: 0, unknown: 0 }
    for (var i = 0; i < root.agents.length; i++) {
      var s = root.agents[i].agent_status || "unknown"
      if (s === "done" && root.acked[root.agents[i].pane_id])
        continue
      if (c[s] !== undefined) c[s]++
    }
    return c
  }

  // ------------------------------------------------------------- polling

  function poll() {
    if (!agentCli.running)
      agentCli.running = true
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.poll()
  }

  Component.onCompleted: {
    whProbe.running = true
    root.poll()
  }
  onOpenedChanged: if (opened) {
    root.poll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // One CLI run per tick: agent list, then the workspace list for labels,
  // separated by an ASCII record separator that neither document contains.
  Process {
    id: agentCli
    command: ["bash", "-lc",
              "env -u HERDR_ENV -u TERM_PROGRAM herdr agent list 2>/dev/null; " +
              "printf '\\036'; env -u HERDR_ENV -u TERM_PROGRAM herdr workspace list 2>/dev/null"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        agentCli.running = false
        var parts = String(text).split("\u001e")
        try {
          var aDoc = JSON.parse(parts[0])
          if (aDoc && aDoc.result && aDoc.result.agents) {
            root.agents = aDoc.result.agents
            root.pruneDoneAcks()
          }
        } catch (e) { /* keep last good data */ }
        try {
          var wDoc = JSON.parse((parts[1] || "").trim())
          if (wDoc && wDoc.result && wDoc.result.workspaces) {
            var map = {}
            for (var i = 0; i < wDoc.result.workspaces.length; i++) {
              var w = wDoc.result.workspaces[i]
              map[w.workspace_id] = w.label || w.workspace_id
            }
            root.wsLabels = map
          }
        } catch (e) { /* keep last good labels */ }
        root.dataRev++
      }
    }
  }

  // The launcher (`wh`) resolves through the user's login PATH; the bar's
  // own env may be the compositor's minimal set, so resolve once and prefer
  // the absolute fallback if `command -v` finds nothing.
  Process {
    id: whProbe
    command: ["bash", "-lc",
              "command -v wh || echo \"$HOME/.config/omarchy/plugins/winherd/wh/wh\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text).trim().split("\n")[0]
        if (p && p.indexOf("/") === 0)
          root.whBin = p
      }
    }
  }

  // --------------------------------------------------- focus or open pane

  property string activatePaneId: ""

  function activatePane(paneId) {
    activatePaneId = paneId
    if (!clientsQuery.running)
      clientsQuery.running = true
  }

  Process {
    id: clientsQuery
    command: ["bash", "-lc", "hyprctl -j clients"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyClients(String(text))
    }
  }

  function applyClients(text) {
    var paneId = root.activatePaneId
    if (!paneId)
      return
    var address = ""
    try {
      var cs = JSON.parse(text)
      var needle = "pane " + paneId
      for (var i = 0; i < cs.length; i++) {
        if (String(cs[i].title || "").indexOf(needle) >= 0 && cs[i].address) {
          address = cs[i].address
          break
        }
      }
    } catch (e) { address = "" }
    if (address) {
      focusProc.command = ["hyprctl", "dispatch",
                           'hl.dsp.focus({ window = "address:' + address + '" })']
    } else {
      var wh = root.whBin || "wh"
      // --force: the row promises a window on this pane, and the fifo guard
      // inside wh would otherwise close the spawned window before the user
      // can read its hint.
      focusProc.command = ["hyprctl", "dispatch",
                           'hl.dsp.exec_cmd("foot -T \'wh pane ' + paneId +
                           "\' -e " + wh + " " + paneId + ' --force")']
    }
    // Focus == clear: being taken to the agent IS the acknowledgment, for
    // both the focus branch and the fresh-window spawn branch.
    root.ackPane(paneId)
    focusProc.running = true
  }

  Process {
    id: focusProc
  }

  // ------------------------------------------------------------- layout

  // The attention badge: the bar icon and the hero in one component.
  // One disc, the waiting-on-you count knocked out inside (blocked +
  // done, minus dismissed); color = worst state present among the
  // agents. A disc in the standard slot never crams two digits: from
  // ten up the badge grows sideways into a pill carrying the full
  // number (the clock-width precedent).
  component StateBadge: Rectangle {
    property string status: root.barState
    property int count: root.attentionCount
    readonly property bool hollow: status === "idle" || status === "unknown"
    width: count >= 10 ? 26 : 14
    height: 14
    radius: height / 2
    color: hollow ? "transparent" : root.stateColor(status)
    border.width: hollow ? 2 : 0
    border.color: Qt.darker(root.foreground, 1.25)
    Text {
      visible: parent.count > 0
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.count
      color: "white"
      font.family: root.fontFamily
      font.pixelSize: parent.count >= 10 ? 9 : 10
      font.bold: true
    }
  }

  // The plain state dot for panel rows: one agent per row, so a number
  // inside would always read 1 — color alone carries the status; idle
  // rows render the hollow ring.
  component StateDot: Rectangle {
    property string status: "idle"
    readonly property bool hollow: !(status === "blocked" || status === "working" || status === "done")
    width: hollow ? 10 : 13
    height: width
    radius: width / 2
    color: hollow ? "transparent" : root.stateColor(status)
    border.width: hollow ? 2 : 0
    border.color: Qt.darker(root.foreground, 1.25)
  }

  // One agent row in the first-party panel anatomy: state disc column,
  // two-line text (title over dim "cwd · pane"), trailing focus chevron,
  // and the shared hover/selected pill. The focused agent's row is the
  // selected one (bold title on the selected fill) — tailscale's current
  // account does the same. Hover-only for now: keyboard cursor wiring is
  // a later concern, so hasCursor stays false and MouseArea drives clicks.
  component AgentRow: CursorSurface {
    id: agentRowSurface
    property var agent: null
    current: agent ? agent.focused === true : false
    foreground: root.foreground

    implicitHeight: agentInner.implicitHeight + Style.spacing.rowPaddingX

    RowLayout {
      id: agentInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Item {
        Layout.preferredWidth: Style.space(22)
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: agentTitle.implicitHeight + agentSub.implicitHeight + Style.space(1)
        StateDot {
          status: agentRowSurface.agent ? agentRowSurface.agent.agent_status : "idle"
          anchors.centerIn: parent
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          id: agentTitle
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: {
            var a = agentRowSurface.agent
            if (!a) return ""
            var t = a.terminal_title_stripped
            if (!t) t = (a.foreground_cwd || a.cwd || a.pane_id).split("/").pop()
            return t
          }
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: agentRowSurface.current
          elide: Text.ElideRight
        }

        Text {
          id: agentSub
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: {
            var a = agentRowSurface.agent
            if (!a) return ""
            var cwd = (a.foreground_cwd || a.cwd || "").split("/").pop()
            return (cwd ? cwd + " · " : "") + a.pane_id
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        text: "\u203A"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (agentRowSurface.agent) root.activatePane(agentRowSurface.agent.pane_id)
    }
  }

  visible: root.agents.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.poll(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    // Custom painted badge, not a font glyph: centers by construction,
    // carries the state color and the waiting count reliably, never
    // depends on which unicode plane the user's Nerd Font assigns to a
    // PUA slot. The count (blocked + done waiting on you) lives inside
    // the disc; nothing is ever appended beside it.
    iconComponent: Component {
      Item {
        anchors.fill: parent

        StateBadge {
          anchors.centerIn: parent
        }
      }
    }

    tooltipText: root.barTooltip

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.poll()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "herdr agents"
            meta: {
              var c = root.counts
              return (root.agents.length + " agent" + (root.agents.length === 1 ? "" : "s") +
                      " · " + c.working + " working · " + c.blocked + " blocked · " +
                      c.done + " done")
            }
            iconComponent: Component {
              Item {
                implicitWidth: Style.font.display
                implicitHeight: Style.font.display
                StateBadge { status: root.barState; anchors.centerIn: parent; scale: 1.5 }
              }
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          PanelSeparator {}

          Text {
            visible: root.agents.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "No agents in this session. Open a pane with wh and run one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.workspaceSections

            delegate: Column {
              id: wsSection
              required property var modelData
              width: parent.width
              spacing: Style.space(2)

              PanelSeparator { visible: wsSection.modelData.index > 0 }

              PanelSectionHeader {
                text: wsSection.modelData.label.toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: wsSection.modelData.rows

                delegate: AgentRow {
                  width: parent.width
                  agent: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  // Workspace sections: rows grouped by workspace, sections alphabetical by
  // label, rows within a section most recently changed first. Rebuilt when
  // the data revision moves so clicks don't thrash mid-interaction.
  readonly property var workspaceSections: {
    var rev = root.dataRev
    var byWs = {}
    var order = []
    for (var i = 0; i < root.agents.length; i++) {
      var ws = root.agents[i].workspace_id
      if (!byWs[ws]) {
        byWs[ws] = []
        order.push(ws)
      }
      byWs[ws].push(root.agents[i])
    }
    for (var j = 0; j < order.length; j++)
      byWs[order[j]].sort(function(x, y) {
        return (y.state_change_seq || 0) - (x.state_change_seq || 0)
      })
    order.sort(function(x, y) {
      var lx = root.wsLabels[x] || x
      var ly = root.wsLabels[y] || y
      return lx < ly ? -1 : (lx > ly ? 1 : 0)
    })
    var sections = []
    for (var k = 0; k < order.length; k++)
      sections.push({ label: root.wsLabels[order[k]] || order[k], rows: byWs[order[k]] })
    return sections
  }
}
