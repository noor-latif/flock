import QtQuick
import Quickshell
import Quickshell.Io
import "proj.mjs" as P

ShellRoot {
  Component.onCompleted: console.log("SPIKE start", P.hello("x"), JSON.stringify(P.ack({"w1:p1": 3}, {pane_id: "w1:p1", state_change_seq: 5})))

  Socket {
    id: sock
    path: Quickshell.env("SPIKE_SOCK")
    connected: true
    onConnectionStateChanged: {
      console.log("SPIKE connected=" + connected)
      if (connected) {
        write(JSON.stringify({id: "sub1", method: "events.subscribe", params: {subscriptions: [
          {type: "workspace.created"}, {type: "workspace.renamed"}, {type: "tab.created"},
          {type: "pane.created"}, {type: "pane.updated"}]}}) + "\n")
        flush()
      }
    }
    onError: function(e) { console.log("SPIKE error code=" + e) }
    parser: SplitParser {
      onRead: function(d) { console.log("SPIKE LINE " + d.substring(0, 160)) }
    }
  }
  Timer {
    interval: 1000; running: true; repeat: true
    onTriggered: if (!sock.connected) { console.log("SPIKE reconnect attempt"); sock.connected = true }
  }
}
