import QtQuick
import Quickshell.Io

// All state lives here, polled from `godark status --json`. Panel.qml only
// reads these properties and calls the CLI for actions -- same split as
// macarchy's and tormarchy's Service.qml / Panel.qml.
Item {
  id: root

  property var settings: ({})

  // "dark" | "partial" | "light", computed by the CLI from live rfkill and
  // NetworkManager state, never from what the last click asked for.
  property string mode: "light"
  property string networking: "absent"
  property string since: ""
  // {type, device, soft, hard} per rfkill radio.
  property var radios: []
  // Physical interfaces that are up but outside NetworkManager.
  property var uncovered: []
  property bool loaded: false
  property string lastError: ""

  readonly property bool dark: mode === "dark"
  readonly property bool partial: mode === "partial"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 3, 1, 300)

  // The CLI runs straight from this plugin checkout, as the user. It never
  // elevates.
  readonly property string cli: decodeURIComponent(Qt.resolvedUrl("godark").toString().replace(/^file:\/\//, ""))

  // "dark" | "light" while an action is in flight, so the panel can show
  // progress and disable the switch instead of going quiet until the next
  // poll -- same busy gate macarchy uses.
  property string pendingAction: ""
  readonly property bool busy: pendingAction !== ""

  function intSetting(name, fallback, min, max) {
    var value = settings ? settings[name] : undefined
    var n = Number(value)
    if (isNaN(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.running = true
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    running: false
    command: ["/bin/bash", root.cli, "status", "--json"]
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = "godark status exited " + exitCode
        return
      }
      try {
        var parsed = JSON.parse(statusStdout.text)
        root.mode = parsed.state || "light"
        root.networking = parsed.networking || "absent"
        root.since = parsed.since || ""
        root.radios = parsed.radios || []
        root.uncovered = parsed.uncovered || []
        root.loaded = true
      } catch (e) {
        root.lastError = String(e)
      }
    }
  }

  function runAction(action) {
    if (actionProc.running) return
    pendingAction = action
    lastError = ""
    actionProc.command = ["/bin/bash", root.cli, action]
    actionProc.running = true
  }

  // Partial counts as "not dark": the switch re-cuts whatever came back.
  function goDark() { runAction("dark") }
  function goLight() { runAction("light") }
  function toggle() { dark ? goLight() : goDark() }

  Process {
    id: actionProc
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      // Warnings (a hardware switch, an unplugged radio) arrive on stderr
      // even on success, and are worth showing either way.
      var err = String(actionStderr.text || "").trim()
      if (exitCode !== 0) {
        root.lastError = err || String(actionStdout.text || "").trim()
          || ("godark " + root.pendingAction + " exited " + exitCode)
      } else {
        root.lastError = err
      }
      root.pendingAction = ""
      root.refresh()
    }
  }
}
