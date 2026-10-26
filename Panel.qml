pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Popup for the per-screen bar control, built on the shell's Panel base and
// KeyboardPanel like the built-in clock: one row per connected screen (plus
// configured screens that are currently disconnected), each with Bar, Left,
// Center and Right toggles. Escape closes it through
// PanelKeyCatcher.
//
// Every click writes this widget's own shell.json entry through the host
// widget; the bar reloads and every screen re-applies from the shared config.
Panel {
  id: root
  moduleName: "zonectl"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function configFor(name, map) {
    var cfg = map[name] || {}
    return {
      bar: cfg.bar !== false,
      left: cfg.left !== false,
      center: cfg.center !== false,
      right: cfg.right !== false
    }
  }

  readonly property var screenRows: {
    var out = []
    var map = root.hostWidget ? root.hostWidget.screenMap : ({})
    var seen = {}
    var live = Quickshell.screens || []
    for (var i = 0; i < live.length; i++) {
      var screen = live[i]
      if (!screen || !screen.name) continue
      var name = String(screen.name)
      if (seen[name]) continue
      seen[name] = true
      out.push({ name: name, connected: true, cfg: root.configFor(name, map) })
    }
    for (var key in map) {
      if (seen[key]) continue
      out.push({ name: key, connected: false, cfg: root.configFor(key, map) })
    }
    return out
  }

  function flip(name, key, current) {
    if (!root.hostWidget) return
    root.hostWidget.setZone(name, key, !current)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Bar and zones per screen"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "Each screen keeps its own settings. The last visible bar cannot be hidden from here; use \"Show all\" to bring everything back."
          color: Commons.Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: root.screenRows

          delegate: Column {
            id: row
            required property var modelData
            width: content.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: row.modelData.name + (row.modelData.connected ? "" : "  (disconnected)")
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Row {
              spacing: Style.space(6)

              Repeater {
                model: [
                  { key: "bar", label: "Bar" },
                  { key: "left", label: "Left" },
                  { key: "center", label: "Center" },
                  { key: "right", label: "Right" }
                ]

                delegate: Button {
                  required property var modelData
                  readonly property bool value: row.modelData.cfg[modelData.key]
                  text: modelData.label
                  active: value
                  bordered: true
                  fontSize: Style.font.caption
                  horizontalPadding: Style.space(10)
                  tooltipText: value ? "Hide" : "Show"
                  onClicked: root.flip(row.modelData.name, modelData.key, value)
                }
              }
            }
          }
        }

        Button {
          text: "Show all"
          bordered: true
          fontSize: Style.font.caption
          onClicked: if (root.hostWidget) root.hostWidget.resetAll()
        }
      }
    }
  }
}
