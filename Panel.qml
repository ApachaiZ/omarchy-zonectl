pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Zones.js" as Zones

// Popup for the per-screen bar control, built on the shell's Panel base and
// KeyboardPanel like the built-in panels. One card per connected screen (plus
// configured screens that are currently disconnected), with a 2×2 grid of
// Bar / Left / Center / Right toggles. Arrow keys move a cursor between the
// cells, Enter or Space toggles one, Escape closes the panel.
//
// Every click writes this widget's own shell.json entry through the host
// widget; the shell applies it live on every screen.
Panel {
  id: root
  moduleName: "zonectl"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color foreground: root.barForeground
  // Zero when the user asked the shell to reduce motion: every hover effect
  // below scales by this so the popup stays still in that mode.
  readonly property real motion: Style.reduceMotion ? 0 : 1
  readonly property var screenRows: Zones.screenRows(
    root.hostWidget ? root.hostWidget.screenMap : ({}), Quickshell.screens)
  readonly property var zoneDefs: [
    { key: "bar", label: "Bar", glyph: "▬" },
    { key: "left", label: "Left", glyph: "←" },
    { key: "center", label: "Center", glyph: "•" },
    { key: "right", label: "Right", glyph: "→" }
  ]

  // Keyboard cursor: one cell per zone, laid out as two columns per screen.
  // -1 means the cursor has not been activated yet.
  property int cursor: -1
  readonly property int cellCount: root.screenRows.length * root.zoneDefs.length

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function clampCursor() {
    if (root.cellCount === 0) { root.cursor = -1; return }
    if (root.cursor >= root.cellCount) root.cursor = root.cellCount - 1
  }

  function moveCursor(dx, dy) {
    if (root.cellCount === 0) return
    if (root.cursor < 0) { root.cursor = 0; return }
    var next = root.cursor
    if (dx !== 0) {
      const rowStart = Math.floor(next / 2) * 2
      next = rowStart + Math.max(0, Math.min(1, next % 2 + dx))
    }
    if (dy !== 0) next = Math.max(0, Math.min(root.cellCount - 1, next + dy * 2))
    root.cursor = next
  }

  function toggleAt(index) {
    var page = root.zoneDefs.length
    var screen = root.screenRows[Math.floor(index / page)]
    var zone = root.zoneDefs[index % page]
    if (!screen || !zone || !root.hostWidget) return
    root.hostWidget.setZone(screen.name, zone.key, !screen.cfg[zone.key])
  }

  function activateCursor() {
    if (root.cursor >= 0 && root.cursor < root.cellCount) root.toggleAt(root.cursor)
  }

  onScreenRowsChanged: root.clampCursor()
  onOpenedChanged: if (!root.opened) root.cursor = -1

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
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Text {
          width: parent.width
          text: "Per-Screen Zones"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        Text {
          width: parent.width
          text: "Show or hide each screen's bar and its left, center and right sections."
          textFormat: Text.PlainText
          color: Commons.Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.screenRows.length === 0
          width: parent.width
          text: "No screens detected."
          textFormat: Text.PlainText
          color: Commons.Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.screenRows

          delegate: BorderSurface {
            id: card
            required property var modelData
            required property int index

            width: content.width
            implicitHeight: cardColumn.implicitHeight + card.contentTopInset + card.contentBottomInset
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.045)
            borderSpec: Border.controlSpec(cardHover.hovered ? "hover-cursor" : "normal",
                                           root.foreground, Commons.Color.accent)
            radius: Style.cornerRadius
            padding: Style.space(10)
            z: cardHover.hovered ? 1 : 0
            // A gentle lift on hover: enough depth to feel raised, without any
            // pointer-following tilt (that reads as wobble at this size).
            scale: 1 + 0.008 * root.motion * (cardHover.hovered ? 1 : 0)
            Behavior on scale { NumberAnimation { duration: Style.duration(140) } }

            HoverHandler { id: cardHover }

            Column {
              id: cardColumn
              x: card.contentLeftInset
              y: card.contentTopInset
              width: card.width - card.contentLeftInset - card.contentRightInset
              spacing: Style.space(10)

              RowLayout {
                width: parent.width
                spacing: Style.space(7)

                Rectangle {
                  Layout.preferredWidth: Style.space(7)
                  Layout.preferredHeight: Style.space(7)
                  radius: width / 2
                  color: card.modelData.connected ? Commons.Color.accent : Commons.Color.muted
                  opacity: card.modelData.connected ? 1 : 0.55
                }

                Text {
                  Layout.fillWidth: true
                  text: Zones.sanitizeLabel(card.modelData.name)
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  text: card.modelData.connected ? "connected" : "disconnected"
                  textFormat: Text.PlainText
                  color: Commons.Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: Style.space(8)
                rowSpacing: Style.space(8)

                Repeater {
                  model: root.zoneDefs

                  delegate: Button {
                    id: zoneButton
                    required property var modelData
                    required property int index

                    readonly property int cellIndex: card.index * root.zoneDefs.length + index
                    readonly property bool value: card.modelData.cfg[modelData.key]
                    property real hoverScale: zoneHover.hovered ? 1 + 0.015 * root.motion : 1
                    Behavior on hoverScale { NumberAnimation { duration: Style.duration(120) } }

                    HoverHandler { id: zoneHover }
                    transform: Scale {
                      origin.x: zoneButton.width / 2
                      origin.y: zoneButton.height / 2
                      xScale: zoneButton.hoverScale
                      yScale: zoneButton.hoverScale
                    }

                    Layout.fillWidth: true
                    text: modelData.label
                    iconText: modelData.glyph
                    iconSize: Style.font.iconLarge
                    selected: value
                    hasCursor: root.cursor === cellIndex
                    bordered: true
                    fontSize: Style.font.body
                    horizontalPadding: Style.space(10)
                    tooltipText: (value ? "Hide " : "Show ") + modelData.label.toLowerCase()
                    onClicked: if (root.hostWidget) root.hostWidget.setZone(card.modelData.name, modelData.key, !value)
                    onHovered: function(isHovered) { if (isHovered) root.cursor = cellIndex }
                  }
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: resetButton.implicitHeight

          Button {
            id: resetButton
            anchors.right: parent.right
            text: "Show all"
            bordered: true
            fontSize: Style.font.body
            enabled: root.screenRows.length > 0
            onClicked: if (root.hostWidget) root.hostWidget.resetAll()
          }
        }

        Text {
          width: parent.width
          text: "The last visible bar always stays on. Use \"omarchy toggle bar\" to hide every bar."
          textFormat: Text.PlainText
          color: Commons.Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
