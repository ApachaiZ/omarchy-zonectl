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
//   - the left/center/right sections are hidden without unloading them, so
//     this widget keeps receiving settings even inside a hidden section.
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

  function isPlainObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value)
  }

  function copyMap(source) {
    var out = {}
    if (!root.isPlainObject(source)) return out
    for (var key in source)
      if (Object.prototype.hasOwnProperty.call(source, key)) out[key] = source[key]
    return out
  }

  function screenConfig(name) {
    var cfg = root.screenMap[String(name || "")]
    return root.isPlainObject(cfg) ? cfg : ({})
  }

  readonly property var hostWindow: QsWindow.window
  readonly property var hostScreen: hostWindow ? hostWindow.screen : null
  readonly property string hostScreenName: hostScreen ? String(hostScreen.name || "") : ""

  readonly property var zoneConfig: {
    var cfg = root.screenConfig(root.hostScreenName)
    function shown(key) { return cfg[key] !== false }
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
      var cfg = root.screenConfig(String(screen.name || ""))
      if (cfg.bar !== false) return true
    }
    return false
  }

  readonly property var zoneKeys: ["bar", "left", "center", "right"]

  function setZone(screenName, key, value) {
    var name = String(screenName || "").trim()
    var zone = String(key || "")
    if (!name || name.length > 128 || root.zoneKeys.indexOf(zone) === -1) return false
    var shown = value === true
    if (zone === "bar" && !shown && !root.otherBarVisible(name)) return false
    var next = root.copyMap(root.screenMap)
    var row = root.copyMap(root.screenConfig(name))
    row[zone] = shown
    next[name] = row
    root.writeScreens(next)
    return true
  }

  function resetAll() {
    root.writeScreens({})
  }

  function writeScreens(screens) {
    var entry = root.copyMap(root.settings)
    entry.id = root.moduleName
    entry.screens = screens
    // Applied locally first so the popup moves on the click itself; the shell
    // config update that follows lands the same value.
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
    root.setSectionShown(sections.left, true)
    root.setSectionShown(sections.center, true)
    root.setSectionShown(sections.right, true)
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
  // off the bar's private object names. Center matching is restricted to the
  // outer CenterModules: the inner center ModuleLists also carry `entries`,
  // and touching their `visible` would mount every center widget twice.
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

  // Hide by opacity, not by `visible`. A ModuleList's `active` binding is
  // `visible && entries.length > 0`, so hiding a section with `visible=false`
  // deactivates its Loader and destroys the widgets inside it. When this
  // widget itself lives in the hidden section, that would destroy the very
  // controller that turns the section back on, and the screen would need a
  // shell restart before a config change from another screen could apply.
  // Opacity keeps the section mounted (settings still reach it) while drawing
  // nothing and taking no input.
  function setSectionShown(items, shown) {
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (!item) continue
      // Section containers (ModuleList and CenterModules) declare `entries`;
      // ModuleSlot delegates do not. Containers have to stay mounted so their
      // Loader keeps the widgets alive, so opacity draws nothing instead.
      if (item.entries !== undefined) {
        // A previous version hid sections with `visible = false`, which also
        // breaks the section's own binding. Take the section back to mounted
        // so an in-place plugin reload recovers without a shell restart.
        if (!item.visible) item.visible = true
        item.opacity = shown ? 1 : 0
        item.enabled = shown
        continue
      }
      // A ModuleSlot is a plain Item: `visible` does not unload its widget,
      // so use it to keep the bar's panel navigation and drag targets from
      // offering entries the user cannot see.
      if (item.visible !== shown) item.visible = shown
      item.enabled = shown
    }
  }

  function applyZones() {
    var sections = root.scanSections()
    var zones = root.zoneConfig
    root.setSectionShown(sections.left, zones.left)
    root.setSectionShown(sections.center, zones.center)
    root.setSectionShown(sections.right, zones.right)
  }

  onHostWindowChanged: Qt.callLater(root.applyZones)
  onZoneConfigChanged: Qt.callLater(root.applyZones)
  onParkedChanged: Qt.callLater(root.applyZones)

  Component.onCompleted: {
    root.syncBarHidden()
    Qt.callLater(root.applyZones)
  }

  // The bar can rebuild its section items (orientation/position changes), so
  // re-scan on a slow timer as a fallback. Re-applying the current state is
  // cheap and also recovers from a rebuild without a config change.
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
      var text = String(value || "").toLowerCase()
      root.setZone(screen, key, text === "true" || text === "on" || text === "1")
    }
  }
}
