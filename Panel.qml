import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Ui
import qs.Commons

// Same shape as macarchy's Panel.qml: a BarIconButton for the bar slot and
// a KeyboardPanel popup built from real qs.Ui components. The header follows
// the first-party Tailscale panel: a PanelHero with the state as its title
// and a ToggleSwitch on its trailing edge as the one control. Below it, one
// row per link, each with its own glyph and on/off state.
//
// Left click on the bar icon opens the panel; middle click flips the switch
// directly, for when you know what you want.
Panel {
  id: root
  moduleName: "oniomarchy.godark"
  ipcTarget: "oniomarchy.godark"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The icon reports real state only: urgent when dark, plain when partly
  // back on, dim when everything is normal.
  readonly property color barIconColor: service.dark ? root.urgent
    : (service.partial ? barForeground : dim)
  // Glyphs by codepoint from the installed Nerd Font (Material Design set),
  // each checked present in JetBrainsMono Nerd Font.
  readonly property string icon: String.fromCodePoint(0xf001d) // nf-md-airplane

  function glyph(type, on) {
    switch (type) {
    case "networking": return String.fromCodePoint(on ? 0xf0317 : 0xf0318) // md-lan / lan_disconnect
    case "wlan":       return String.fromCodePoint(on ? 0xf05a9 : 0xf05aa) // md-wifi / wifi_off
    case "bluetooth":  return String.fromCodePoint(on ? 0xf00af : 0xf00b2) // md-bluetooth / bluetooth_off
    case "wwan":       return String.fromCodePoint(0xf08bc)                // md-signal_cellular
    case "nfc":        return String.fromCodePoint(0xf0395)                // md-nfc
    case "gps":        return String.fromCodePoint(0xf01a4)                // md-crosshairs_gps
    default:           return String.fromCodePoint(0xf0003)                // md-access_point
    }
  }

  function typeLabel(type) {
    switch (type) {
    case "networking": return "Networking"
    case "wlan":       return "Wi-Fi"
    case "bluetooth":  return "Bluetooth"
    case "wwan":       return "Mobile data"
    case "nfc":        return "NFC"
    case "gps":        return "GPS"
    case "uwb":        return "Ultra-wideband"
    default:           return type
    }
  }

  // One list for the rows: networking first (when NetworkManager runs),
  // then every rfkill radio. Rebuilt from service state on every poll.
  readonly property var links: {
    var out = []
    if (service.networking !== "absent")
      out.push({ type: "networking", device: "wired, VPN", on: service.networking === "enabled", hard: false })
    for (var i = 0; i < service.radios.length; i++) {
      var r = service.radios[i]
      out.push({ type: r.type, device: r.device, on: r.soft !== "blocked" && r.hard !== "blocked", hard: r.hard === "blocked" })
    }
    return out
  }
  readonly property int leaks: links.filter(function(l) { return l.on }).length

  function sinceText() {
    if (service.since === "") return ""
    var t = service.since.replace(/[+-]\d\d:\d\d$/, "")
    var d = new Date(t)
    if (isNaN(d.getTime())) return t.replace("T", " ")
    var now = new Date()
    var sameDay = d.toDateString() === now.toDateString()
    return sameDay ? Qt.formatTime(d, "HH:mm") : Qt.formatDateTime(d, "ddd HH:mm")
  }

  function heroTitle() {
    if (!service.loaded) return "GoDark"
    if (service.pendingAction === "dark") return "Going dark…"
    if (service.pendingAction === "light") return "Restoring…"
    if (service.dark) return "Dark"
    if (service.partial) return "Partly back on"
    return "Connected"
  }

  function heroMeta() {
    if (!service.loaded) return service.lastError !== "" ? service.lastError : "Reading state…"
    if (service.dark) return "All off" + (sinceText() ? " since " + sinceText() : "")
    if (service.partial) return root.leaks + (root.leaks === 1 ? " link" : " links") + " back on"
    return "All links on"
  }

  Service {
    id: service
    settings: root.settings
  }

  IpcHandler {
    target: "oniomarchy.godark"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function dark() { service.goDark() }
    function light() { service.goLight() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: service.refresh()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    foreground: root.barIconColor

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (!service.busy) service.toggle()
        return
      }
      if (root.opened) root.close()
      else root.open()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") service.refresh()
        else if ((t === "d" || t === "D" || t === " ") && !service.busy) service.toggle()
      }
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      PanelHero {
        width: parent.width
        title: root.heroTitle()
        meta: root.heroMeta()
        foreground: service.dark ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        iconOpacity: service.dark || service.partial ? 1.0 : 0.5

        iconComponent: Component {
          Text {
            text: root.icon
            color: service.dark ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
        }

        // The panel's one control. Checked means dark; partial reads as
        // unchecked so flipping it cuts whatever came back.
        trailingControl: Component {
          ToggleSwitch {
            checked: service.dark
            busy: service.busy
            interactive: service.loaded && !service.busy
            foreground: root.foreground
            accent: root.urgent
            onToggled: service.toggle()
          }
        }
      }

      PanelSeparator {
        visible: service.loaded && root.links.length > 0
        foreground: root.foreground
      }

      Repeater {
        model: service.loaded ? root.links : []

        delegate: RowLayout {
          id: linkRow
          required property var modelData
          // A link still on while the machine is supposed to be dark is
          // the one thing worth shouting about.
          readonly property bool leaking: (service.dark || service.partial) && modelData.on
          width: column.width
          spacing: Style.space(12)

          Text {
            Layout.preferredWidth: Style.font.icon * 1.4
            horizontalAlignment: Text.AlignHCenter
            text: root.glyph(linkRow.modelData.type, linkRow.modelData.on)
            color: linkRow.leaking ? root.urgent : (linkRow.modelData.on ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          Column {
            Layout.fillWidth: true
            spacing: 0

            Text {
              width: parent.width
              text: root.typeLabel(linkRow.modelData.type)
              color: linkRow.modelData.on ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: linkRow.modelData.device
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            text: linkRow.modelData.hard ? "hardware off" : (linkRow.modelData.on ? "on" : "off")
            color: linkRow.leaking || linkRow.modelData.hard ? root.urgent
              : (linkRow.modelData.on ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: linkRow.modelData.on || linkRow.modelData.hard
          }
        }
      }

      // Interfaces GoDark can't cut without root. Shown, never hidden.
      Repeater {
        model: service.loaded ? service.uncovered : []

        delegate: Text {
          required property var modelData
          width: column.width
          wrapMode: Text.WordWrap
          text: modelData + " is up outside NetworkManager; GoDark can't cut it"
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        visible: service.loaded && service.lastError !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        text: service.lastError
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: service.loaded
        width: parent.width
        wrapMode: Text.WordWrap
        text: "middle-click icon · d switch · r refresh"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
