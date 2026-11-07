.pragma library

// Shared per-screen zone model for the zonectl bar widget and its popup.
//
// Configuration is a JSON map keyed by compositor output name:
//   { "HDMI-A-2": { "bar": true, "left": false, "center": true, "right": false } }
// A screen or key that is absent means "shown". The popup and the bar widget
// both read and write this shape, so the parsing and validation live here
// instead of being duplicated in each entry point.

var ZONE_KEYS = ["bar", "left", "center", "right"]

// Bound the stored map. The UI only writes live outputs, but the IPC surface
// accepts arbitrary names, and this keeps a local caller from growing
// shell.json without limit.
var MAX_SCREENS = 64

var ZONE_LABELS = {
  bar: "Bar",
  left: "Left",
  center: "Center",
  right: "Right"
}

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function copyMap(source) {
  var out = {}
  if (!isPlainObject(source)) return out
  for (var key in source)
    if (Object.prototype.hasOwnProperty.call(source, key)) out[key] = source[key]
  return out
}

function ownValue(map, key) {
  return map && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined
}

// The `screens` map from a shell.json entry, or an empty map.
function screenMap(settings) {
  var map = settings ? ownValue(settings, "screens") : undefined
  return isPlainObject(map) ? map : ({})
}

function screenConfig(map, name) {
  var cfg = ownValue(map, String(name || ""))
  return isPlainObject(cfg) ? cfg : ({})
}

// A screen's four zones with absent keys resolved to "shown".
function zoneConfig(map, name) {
  var cfg = screenConfig(map, name)
  function shown(key) { return cfg[key] !== false }
  return { bar: shown("bar"), left: shown("left"), center: shown("center"), right: shown("right") }
}

function screenName(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

// Screen names come from the compositor or from IPC, so bound them and keep
// the keys that would reach an object prototype out of the stored map.
function validScreenName(value) {
  var name = screenName(value)
  return name !== "" && name.length <= 128
    && name !== "__proto__" && name !== "constructor" && name !== "prototype"
}

// A new map with one zone set, or null when the request is invalid.
function setZone(map, name, key, value) {
  var screen = screenName(name)
  var zone = String(key || "")
  if (!validScreenName(screen) || ZONE_KEYS.indexOf(zone) === -1) return null
  var next = copyMap(map)
  if (!Object.prototype.hasOwnProperty.call(next, screen) && Object.keys(next).length >= MAX_SCREENS)
    return null
  var row = copyMap(screenConfig(next, screen))
  row[zone] = value === true
  next[screen] = row
  return next
}

// True when another connected screen still has its bar shown, so the last
// visible bar can never be hidden from the plugin.
function otherBarVisible(map, exceptName, screens) {
  var list = screens || []
  for (var i = 0; i < list.length; i++) {
    var screen = list[i]
    if (!screen || String(screen.name || "") === screenName(exceptName)) continue
    if (screenConfig(map, String(screen.name || "")).bar !== false) return true
  }
  return false
}

// One row per connected screen, followed by configured screens that are
// currently disconnected.
function screenRows(map, screens) {
  var rows = []
  var seen = {}
  var list = screens || []
  for (var i = 0; i < list.length; i++) {
    var screen = list[i]
    if (!screen || !screen.name) continue
    var name = String(screen.name)
    if (seen[name]) continue
    seen[name] = true
    rows.push({ name: name, connected: true, cfg: zoneConfig(map, name) })
  }
  for (var key in map) {
    if (!Object.prototype.hasOwnProperty.call(map, key) || seen[key]) continue
    rows.push({ name: key, connected: false, cfg: zoneConfig(map, key) })
  }
  return rows
}

// Screen names are imported from the compositor or from user config. Keep
// them single-line and bounded before they reach a text sink.
function sanitizeLabel(value) {
  var text = String(value === undefined || value === null ? "" : value)
    .replace(/[\u0000-\u001f\u007f-\u009f‪-‮⁦-⁩]/g, "")
  return text.length > 128 ? text.slice(0, 128) + "…" : text
}
