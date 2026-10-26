import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Per-screen bar control: shows or hides this screen's bar panel and each of
// its three sections, without replacing the native bar.
//
// Every bar surface builds one instance of this widget. An instance learns
// which panel it lives in through the attached `QsWindow.window` and only
// ever touches that panel:
//   - the whole bar is parked off-screen with the same margin +
//     ExclusionMode.Ignore mechanism the native bar-hidden toggle uses;
//   - the left/center/right sections are hidden by toggling `visible` on the
//     section items the native bar built inside this panel.
// Widgets, layout, theming and popouts stay Omarchy-owned: disabling this
// plugin restores everything.
//
// Configuration lives in this widget's own shell.json entry:
//   { "id": "zonectl", "screens": {
//       "HDMI-A-1": { "bar": true, "left": true, "center": false, "right": false } } }
// A screen or key that is absent means "shown". The popup writes the entry
// through the widget-shell `updateEntryInline` path.
BarWidget {
  id: root
  moduleName: "zonectl"

  // ---- Configuration -------------------------------------------------------

  readonly property var screenMap: {
    var m = root.settings ? root.settings.screens : null
    return (m && typeof m === "object" && !Array.isArray(m)) ? m : ({})
  }

  readonly property var hostWindow: QsWindow.window
  readonly property var hostScreen: hostWindow ? hostWindow.screen : null
  readonly property string hostScreenName: hostScreen ? String(hostScreen.name || "") : ""

  readonly property var zoneConfig: {
    var cfg = root.screenMap[root.hostScreenName]
    function shown(key) { return !cfg || cfg[key] !== false }
    return {
      bar: shown("bar"),
      left: shown("left"),
      center: shown("center"),
      right: shown("right")
    }
  }

  // Keep the escape hatch: the last visible bar cannot be hidden from here.
  // The native `omarchy toggle bar` still hides every bar at once.
  function otherBarVisible(exceptName) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (!screen || String(screen.name || "") === String(exceptName || "")) continue
      var cfg = root.screenMap[String(screen.name || "")]
      if (!cfg || cfg.bar !== false) return true
    }
    return false
  }

  function setZone(screenName, key, value) {
    var name = String(screenName || "")
    if (!name) return
    if (key === "bar" && value === false && !root.otherBarVisible(name)) return
    var next = {}
    for (var k in root.screenMap) next[k] = root.screenMap[k]
    var row = {}
    var current = next[name] || {}
    for (var c in current) row[c] = current[c]
    row[String(key)] = !!value
    next[name] = row
    root.writeScreens(next)
  }

  function resetAll() {
    root.writeScreens({})
  }

  function writeScreens(screens) {
    var entry = { id: root.moduleName }
    var current = root.settings || {}
    for (var k in current) if (k !== "id") entry[k] = current[k]
    entry.screens = screens
    // Applied locally first so the popup moves on the click itself; the shell
    // reload that follows lands the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Global bar-hidden flag (native `omarchy toggle bar`) ----------------

  property bool barHidden: false

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: root.syncBarHidden()
  }

  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c",
      "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function(line) {
        var on = String(line).trim() === "yes"
        if (on !== root.barHidden) root.barHidden = on
      }
    }
  }

  function syncBarHidden() {
    barHiddenProbe.running = true
    reProbeTimer.restart()
  }

  Timer {
    id: reProbeTimer
    // The directory watch can go quiet after rapid flag changes; a periodic
    // re-probe is this plugin's belt-and-braces version of the native IPC
    // nudge (barhide documents the same failure mode).
    interval: 15000
    onTriggered: barHiddenProbe.running = true
  }

  // ---- Self-parking --------------------------------------------------------

  readonly property bool parked: root.barHidden || !root.zoneConfig.bar
  readonly property real parkedOffset: root.parked
    ? -Math.max(root.bar && root.bar.barSize > 0 ? root.bar.barSize : 26, 26)
    : 0

  // These Bindings displace the native panel's own margin/exclusion bindings
  // and restore them on teardown, so removing the plugin always brings the
  // bar back.
  property bool teardown: false

  Component.onDestruction: {
    root.teardown = true
    var sections = root.scanSections()
    for (var i = 0; i < sections.left.length; i++) sections.left[i].visible = true
    for (var c = 0; c < sections.center.length; c++) sections.center[c].visible = true
    for (var r = 0; r < sections.right.length; r++) sections.right[r].visible = true
  }

  Binding {
    target: root.hostWindow
    property: "exclusionMode"
    value: root.parked ? ExclusionMode.Ignore : ExclusionMode.Auto
    when: root.hostWindow !== null && "exclusionMode" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.top"
    value: root.bar && root.bar.position === "top" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.bottom"
    value: root.bar && root.bar.position === "bottom" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.left"
    value: root.bar && root.bar.position === "left" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.right"
    value: root.bar && root.bar.position === "right" ? root.parkedOffset : 0
    when: root.hostWindow !== null && "margins" in root.hostWindow && !root.teardown
    restoreMode: Binding.RestoreBindingOrValue
  }

  // ---- Section visibility --------------------------------------------------

  // The native bar builds one of each section inside this panel. The section
  // items are internal to Bar.qml, but they carry stable shape markers:
  // LeftModules/RightModules declare `region`, CenterModules declares
  // `anchorEntry` alongside `entries`. Matching on those keeps this plugin
  // off the bar's private object names.
  function scanSections() {
    var out = { left: [], center: [], right: [] }
    var win = root.hostWindow
    if (!win || !win.contentItem) return out
    var stack = [win.contentItem]
    var guard = 0
    while (stack.length > 0 && guard < 500) {
      guard++
      var item = stack.pop()
      if (!item) continue
      if (item.region === "left") out.left.push(item)
      else if (item.region === "right") out.right.push(item)
      else if (item.entries !== undefined && item.anchorEntry !== undefined) out.center.push(item)
      var kids = item.children
      if (kids) for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return out
  }

  property var sectionItems: ({ left: [], center: [], right: [] })

  function applyZones() {
    var sections = root.scanSections()
    root.sectionItems = sections
    var zones = root.zoneConfig
    // Every match is hidden, not just the outermost container: the scan also
    // finds the per-widget slots inside an expanded section, and leaving one
    // of those visible would keep drawing it.
    for (var i = 0; i < sections.left.length; i++) sections.left[i].visible = zones.left
    for (var c = 0; c < sections.center.length; c++) sections.center[c].visible = zones.center
    for (var r = 0; r < sections.right.length; r++) sections.right[r].visible = zones.right
  }

  onHostWindowChanged: Qt.callLater(root.applyZones)
  onZoneConfigChanged: Qt.callLater(root.applyZones)
  onParkedChanged: Qt.callLater(root.applyZones)

  Component.onCompleted: {
    root.syncBarHidden()
    Qt.callLater(root.applyZones)
  }

  // The bar can rebuild its section items (orientation/position changes), so
  // re-scan on a slow timer as a fallback. Assigning an unchanged boolean is
  // a no-op in QML.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.applyZones()
  }

  // ---- Popup lifecycle (shell.summon/hide/toggle contract) -----------------

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggle() {
    togglePanel()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\udb80\udf79"
    slotSize: Style.bar.iconSlot
    tooltipText: "Bar and zones for this screen"
    onPressed: root.toggle()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "zonectl"

    function reset(): void { root.resetAll() }

    function set(screen: string, key: string, value: string): void {
      root.setZone(screen, key, String(value) === "true"
        || String(value) === "on" || String(value) === "1")
    }
  }
}
