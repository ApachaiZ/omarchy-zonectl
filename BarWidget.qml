import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Zones.js" as Zones

// Per-screen bar control: shows or hides this screen's bar panel and each of
// its three sections, without replacing the native bar.
//
// Every bar surface builds one instance of this widget. An instance learns
// which panel it lives in through the attached `QsWindow.window` and only
// ever touches that panel:
//   - the whole bar is parked off-screen with the same margin +
//     ExclusionMode.Ignore mechanism the native bar-hidden toggle uses, but
//     only while this screen's zone config says `bar: false`; the native
//     `omarchy toggle bar` keeps owning global hiding;
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

  readonly property var screenMap: Zones.screenMap(root.settings)
  readonly property var hostWindow: QsWindow.window
  readonly property var hostScreen: hostWindow ? hostWindow.screen : null
  readonly property string hostScreenName: hostScreen ? String(hostScreen.name || "") : ""
  readonly property var zoneConfig: Zones.zoneConfig(root.screenMap, root.hostScreenName)

  function setZone(screenName, key, value) {
    var shown = value === true
    // Keep the escape hatch: the last visible bar cannot be hidden from here.
    // The native `omarchy toggle bar` still hides every bar at once.
    if (key === "bar" && !shown
        && !Zones.otherBarVisible(root.screenMap, screenName, Quickshell.screens)) return false
    var next = Zones.setZone(root.screenMap, screenName, key, shown)
    if (next === null) return false
    root.writeScreens(next)
    return true
  }

  function resetAll() {
    // updateEntryInline is idempotent, but skip the write when there is
    // nothing to reset.
    if (Object.keys(root.screenMap).length === 0) return
    root.writeScreens({})
  }

  function writeScreens(screens) {
    var entry = Zones.copyMap(root.settings)
    entry.id = root.moduleName
    entry.screens = screens
    // Applied locally first so the popup moves on the click itself; the shell
    // config update that follows lands the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Self-parking --------------------------------------------------------

  // Only this plugin's own per-screen setting parks the bar. The native
  // `bar-off` flag is left to the native bar so a missed file-watch event can
  // never leave the plugin overriding the user's global bar toggle.
  readonly property bool parked: !root.zoneConfig.bar
  readonly property real parkedOffset: root.parked
    ? -Math.max(root.bar && root.bar.barSize > 0 ? root.bar.barSize : 26, 26)
    : 0

  // These Bindings displace the native panel's own margin/exclusion bindings
  // and restore them on teardown, so removing the plugin always brings the
  // bar back.
  property bool teardown: false
  readonly property bool parkingActive: root.parked && !!root.hostWindow && !root.teardown

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
    value: ExclusionMode.Ignore
    when: root.parkingActive && "exclusionMode" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.top"
    value: root.bar && root.bar.position === "top" ? root.parkedOffset : 0
    when: root.parkingActive && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.bottom"
    value: root.bar && root.bar.position === "bottom" ? root.parkedOffset : 0
    when: root.parkingActive && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.left"
    value: root.bar && root.bar.position === "left" ? root.parkedOffset : 0
    when: root.parkingActive && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  Binding {
    target: root.hostWindow
    property: "margins.right"
    value: root.bar && root.bar.position === "right" ? root.parkedOffset : 0
    when: root.parkingActive && "margins" in root.hostWindow
    restoreMode: Binding.RestoreBindingOrValue
  }

  // ---- Section visibility --------------------------------------------------

  // Omarchy 4.5 builds one ModuleList per section: `left`, `right`, and the
  // center split into `centerBegin`, `center` and `centerEnd`. A ModuleList
  // carries a `keys` array, while its ModuleSlot delegates and drag spacers
  // only carry `region`. Matching on the list marker keeps this plugin off
  // the bar's private object names.
  function isSectionContainer(item) {
    return item.keys !== undefined
  }

  function zoneForRegion(region) {
    var name = String(region || "")
    if (name === "left" || name === "right") return name
    if (name === "center" || name === "centerBegin" || name === "centerEnd") return "center"
    return ""
  }

  // Every section's containers (the ModuleLists) and its slots (their direct
  // children). The walk stops at each container: its slots are right there,
  // and descending into every widget's subtree made the old fixed node budget
  // run out before the left section was reached on a full bar.
  function scanSections() {
    var out = {
      left: { containers: [], slots: [] },
      center: { containers: [], slots: [] },
      right: { containers: [], slots: [] }
    }
    var win = root.hostWindow
    if (!win || !win.contentItem) return out
    var stack = [win.contentItem]
    var guard = 0
    while (stack.length > 0 && guard < 20000) {
      guard++
      var item = stack.pop()
      if (!item) continue
      if (root.isSectionContainer(item)) {
        var zone = root.zoneForRegion(item.region)
        if (!zone) continue
        out[zone].containers.push(item)
        var slots = item.children
        if (slots) for (var s = 0; s < slots.length; s++) {
          var slot = slots[s]
          if (slot && slot.region !== undefined && root.zoneForRegion(slot.region) === zone)
            out[zone].slots.push(slot)
        }
        continue
      }
      var kids = item.children
      if (kids) for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return out
  }

  // Hide by opacity, not by `visible`. A ModuleList binds its own `visible` to
  // whether it holds any rows, and its Repeater only makes slots while the
  // list is visible. Hiding the container with `visible=false` would empty
  // the Repeater and destroy every widget inside, including this controller
  // when it lives in the hidden section. Opacity keeps the list mounted
  // (settings still reach it) while drawing nothing and taking no input.
  //
  // Slots are plain Items: `visible` does not unload their widget, so it also
  // keeps the bar's panel navigation and drag targets from offering entries
  // the user cannot see, and lets the layout reclaim their room.
  function setSectionShown(section, shown) {
    for (var c = 0; c < section.containers.length; c++) {
      var container = section.containers[c]
      if (!container) continue
      container.opacity = shown ? 1 : 0
      container.enabled = shown
    }
    for (var i = 0; i < section.slots.length; i++) {
      var slot = section.slots[i]
      if (!slot) continue
      if (slot.visible !== shown) slot.visible = shown
      slot.enabled = shown
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

  Component.onCompleted: Qt.callLater(root.applyZones)

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
