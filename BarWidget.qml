import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// hd — herdr agents on the bar.
//
// Replaces the herdr sidebar with a bar slot: at most three dots for the
// agents that changed state most recently (colored by state), a compact
// count badge, and a panel listing every agent grouped by workspace. A
// click on a row focuses the window viewing that pane, spawning one (foot
// + `hd <pane_id>`) when no window has it. Claims stay where the user put
// them: the bar never changes geometry, it only moves focus.
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

  readonly property int maxDots: Math.max(0, Math.min(5, Math.floor(Number(setting("maxDots", 3)))))
  readonly property int refreshIntervalSec: Math.max(1, Math.floor(Number(setting("refreshIntervalSec", 2))))

  function stateColor(status) {
    if (status === "working") return cWorking
    if (status === "blocked") return cBlocked
    if (status === "done") return cDone
    return cIdle
  }

  function stateGlyph(status) {
    if (status === "done") return "✓"
    if (status === "blocked") return "!"
    if (status === "working") return "●"
    if (status === "idle") return "○"
    return "?"
  }

  // Active agents, most recently changed first — the dots truncate this.
  readonly property var activeAgents: {
    var rev = root.dataRev
    var out = []
    for (var i = 0; i < root.agents.length; i++) {
      var s = root.agents[i].agent_status
      if (s === "working" || s === "blocked" || s === "done")
        out.push(root.agents[i])
    }
    out.sort(function(a, b) { return (b.state_change_seq || 0) - (a.state_change_seq || 0) })
    return out
  }

  readonly property var dots: root.activeAgents.slice(0, root.maxDots)

  readonly property var counts: {
    var rev = root.dataRev
    var c = { working: 0, blocked: 0, done: 0, idle: 0, unknown: 0 }
    for (var i = 0; i < root.agents.length; i++) {
      var s = root.agents[i].agent_status || "unknown"
      if (c[s] !== undefined) c[s]++
    }
    return c
  }

  readonly property string badgeText: {
    var c = root.counts
    var parts = []
    if (c.working > 0) parts.push("●" + c.working)
    if (c.blocked > 0) parts.push("!" + c.blocked)
    if (c.done > 0) parts.push("✓" + c.done)
    var rest = c.idle + c.unknown
    if (rest > 0) parts.push("○" + rest)
    return parts.join(" ")
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

  visible: root.agents.length > 0
  // The slot must measure the real content: WidgetButton derives its width
  // from the text label alone, and this button's label is empty (the dots +
  // badge are nested content), so the default collapses to padding-width and
  // the row paints over the neighbouring widgets — unclickable and tangled.
  implicitWidth: barRow.implicitWidth + Style.space(18)
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.poll()
      else root.toggle()
    }

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Repeater {
        model: root.dots

        delegate: Rectangle {
          required property var modelData
          width: 7
          height: 7
          radius: 3.5
          color: root.stateColor(modelData.agent_status)
        }
      }

      Text {
        textFormat: Text.PlainText
        text: root.badgeText
        color: root.foreground
        visible: root.badgeText !== ""
        font.family: root.fontFamily
        font.pixelSize: button.fontSize * 0.82
      }
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
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

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

              PanelSectionHeader {
                text: wsSection.modelData.label + "  ·  " + wsSection.modelData.rows.length
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: wsSection.modelData.rows

                delegate: Item {
                  id: agentRow
                  required property var modelData
                  width: parent.width
                  height: agentTitle.implicitHeight + Style.space(10)

                  MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activatePane(agentRow.modelData.pane_id)
                  }

                  Rectangle {
                    width: 2
                    height: parent.height
                    color: rowArea.containsMouse
                            ? Style.selectedFillFor(root.foreground, Color.accent)
                            : "transparent"
                  }

                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.right: parent.right
                    spacing: Style.space(8)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: root.stateGlyph(agentRow.modelData.agent_status)
                      color: root.stateColor(agentRow.modelData.agent_status)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      id: agentTitle
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: {
                        var a = agentRow.modelData
                        var t = a.terminal_title_stripped
                        if (!t) t = (a.foreground_cwd || a.cwd || a.pane_id).split("/").pop()
                        return t
                      }
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: Math.max(80, parent.width - Style.space(90))
                      opacity: rowArea.containsMouse ? 1 : 0.92
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: agentRow.modelData.focused ? "◇" : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      textFormat: Text.PlainText
                      text: agentRow.modelData.pane_id
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: 10
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.agents.length > 0
            width: parent.width
            textFormat: Text.PlainText
            text: "click a row to focus its window"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 10
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
