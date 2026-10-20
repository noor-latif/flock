import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// hd — herdr agents on the bar.
//
// Replaces the herdr sidebar with a bar slot in the standard omarchy icon
// footprint: ONE state-colored glyph (blocked alert · working active ·
// done check; dimmed when nothing is active), never any counts — those
// live in the hover tooltip and in the panel, which lists every agent
// grouped by workspace. A click on a row focuses the window viewing that
// pane, spawning one (foot + `hd <pane_id>`) when no window has it.
// Claims stay where the user put them: the bar never changes geometry,
// it only moves focus.
Panel {
  id: root
  moduleName: "hd-herdr"
  ipcTarget: "hd-herdr"
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
  property string hdBin: ""

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
    return "herdr agents — " + (parts.length ? parts.join(" · ") : "none")
  }

  readonly property var counts: {
    var rev = root.dataRev
    var c = { working: 0, blocked: 0, done: 0, idle: 0, unknown: 0 }
    for (var i = 0; i < root.agents.length; i++) {
      var s = root.agents[i].agent_status || "unknown"
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
    hdProbe.running = true
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
          if (aDoc && aDoc.result && aDoc.result.agents)
            root.agents = aDoc.result.agents
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

  // The launcher (`hd`) resolves through the user's login PATH; the bar's
  // own env may be the compositor's minimal set, so resolve once and prefer
  // the absolute fallback if `command -v` finds nothing.
  Process {
    id: hdProbe
    command: ["bash", "-lc",
              "command -v hd || echo \"$HOME/.config/omarchy/plugins/hd-herdr/hd/hd\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text).trim().split("\n")[0]
        if (p && p.indexOf("/") === 0)
          root.hdBin = p
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
      var hd = root.hdBin || "hd"
      // --force: the row promises a window on this pane, and the fifo guard
      // inside hd would otherwise close the spawned window before the user
      // can read its hint.
      focusProc.command = ["hyprctl", "dispatch",
                           'hl.dsp.exec_cmd("foot -T \'hd pane ' + paneId +
                           "\' -e " + hd + " " + paneId + ' --force")']
    }
    focusProc.running = true
  }

  Process {
    id: focusProc
  }

  // ------------------------------------------------------------- layout

  // The state disc shared by the bar icon, the hero and every panel row —
  // one shape language everywhere. Idle renders as a faint hollow ring.
  component StateDisc: Rectangle {
    property string status: "idle"
    width: status === "idle" ? 9 : 11
    height: width
    radius: width / 2
    color: status === "idle" ? "transparent" : root.stateColor(status)
    border.width: status === "idle" ? 1.5 : 0
    border.color: root.stateColor(status)
    opacity: status === "idle" ? 0.55 : 1
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
        StateDisc {
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

    // Custom painted icon (shared StateDisc), not a font glyph: centers by
    // construction, carries state color reliably, never depends on which
    // unicode plane the user's Nerd Font assigns to a PUA slot. working =
    // dot, blocked = red badge with !, done = blue badge with check,
    // idle/unknown = faint hollow ring.
    iconComponent: Component {
      Item {
        anchors.fill: parent

        StateDisc {
          status: root.barState
          anchors.centerIn: parent
        }

        Text {
          visible: root.barState === "blocked" || root.barState === "done"
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.barState === "blocked" ? "!" : "\u2713"
          color: "#1c1c22"
          font.family: root.fontFamily
          font.pixelSize: 9
          font.bold: true
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
                StateDisc { status: root.barState; anchors.centerIn: parent; scale: 1.5 }
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
            text: "No agents in this session. Open a pane with hd and run one."
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
