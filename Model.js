// Pure parsing and formatting for the System Monitor bar widget. No QML or
// Quickshell types in here so the whole file runs under `node --test` too.

// Glyphs are checked against JetBrainsMono Nerd Font, which Omarchy ships as
// ttf-jetbrains-mono-nerd-basic. Font Awesome's fa-memory (U+F538) is NOT in
// that font and renders as tofu — md-memory (U+EFC5) is, hence the mix.
var ICONS = {
  cpu: "",
  ram: "",
  temp: "",
  gpu: "",
  vram: "",
  netUp: "",
  netDown: "",
  disk: ""
}

// Chips always render in this order. Per-widget settings live in the bar's
// shell.json layout entry, and the manifest schema has no array type, so
// there is nowhere to persist a user ordering — only which chips are on.
var CHIP_ORDER = ["cpu", "ram", "cpuTemp", "gpu", "gpuTemp", "vram", "net", "disk"]

// Width each value is pinned to, in characters, so a reading that grows a
// digit (9% -> 10%, 99° -> 100°) cannot shove the rest of the bar sideways.
// The widget reserves this many character widths in pixels; barText() pads
// with spaces to the same width for its plain-text form.
var WIDTHS = { percent: 4, temp: 4, size: 4, rate: 4 }

function padLeft(value, width) {
  var text = String(value)
  while (text.length < width) text = " " + text
  return text
}

// Values are padded on the right, not the left. Right-aligning them would put
// the slack between the icon and its own number — "5%" would sit three cells
// from its icon while "100%" sat one — which reads as a wobbling gap. Padding
// trailing instead keeps every value hard against its icon and moves the slack
// out to the chip's edge, where it separates chips rather than splitting one.
function padRight(value, width) {
  var text = String(value)
  while (text.length < width) text += " "
  return text
}

// ---------------------------------------------------------------- /proc/stat

// The first `cpu` line is the aggregate across every core. guest and
// guest_nice are deliberately excluded: the kernel already counts them inside
// user and nice, so adding them again would inflate the total and understate
// load.
function parseCpuTotals(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("cpu ") !== 0) continue
    var fields = lines[i].trim().split(/\s+/)
    var total = 0
    for (var f = 1; f <= 8 && f < fields.length; f++) {
      var value = parseInt(fields[f], 10)
      if (!isFinite(value)) return null
      total += value
    }
    var idle = parseInt(fields[4], 10)
    var iowait = fields.length > 5 ? parseInt(fields[5], 10) : 0
    if (!isFinite(idle)) return null
    if (!isFinite(iowait)) iowait = 0
    return { total: total, idle: idle + iowait }
  }
  return null
}

// Busy share between two readings. The first tick after startup has no
// previous sample and deliberately returns null rather than 0 — a real 0%
// and "not known yet" must not render the same.
function cpuPercent(previous, current) {
  if (!previous || !current) return null
  var totalDelta = current.total - previous.total
  var idleDelta = current.idle - previous.idle
  if (totalDelta <= 0) return null
  var busy = (1 - idleDelta / totalDelta) * 100
  return Math.max(0, Math.min(100, busy))
}

// ------------------------------------------------------------- /proc/meminfo

// MemAvailable is the kernel's own estimate of what a new allocation could
// claim, which is the number people mean by "free". total - free would count
// reclaimable page cache as used and report a permanently near-full machine.
function parseMeminfo(text) {
  var lines = String(text || "").split("\n")
  var total = null
  var available = null
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^(MemTotal|MemAvailable):\s+(\d+)\s+kB/)
    if (!match) continue
    if (match[1] === "MemTotal") total = parseInt(match[2], 10) * 1024
    else available = parseInt(match[2], 10) * 1024
  }
  if (total === null || available === null || total <= 0) return null
  var used = Math.max(0, total - available)
  return { total: total, used: used, percent: (used / total) * 100 }
}

// ------------------------------------------------------------ /proc/net/dev

// Columns after the interface name are receive (bytes packets errs drop fifo
// frame compressed multicast) then transmit in the same shape, so received
// bytes are field 0 and transmitted bytes field 8.
function parseNetDev(text, iface) {
  var wanted = String(iface || "")
  if (wanted === "") return null
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var colon = lines[i].indexOf(":")
    if (colon === -1) continue
    if (lines[i].slice(0, colon).trim() !== wanted) continue
    var fields = lines[i].slice(colon + 1).trim().split(/\s+/)
    var rx = parseInt(fields[0], 10)
    var tx = parseInt(fields[8], 10)
    if (!isFinite(rx) || !isFinite(tx)) return null
    return { rx: rx, tx: tx }
  }
  return null
}

// Counters are cumulative and reset when the interface is reconfigured or the
// kernel counter wraps. A negative delta means a reset, not negative traffic,
// so it reports zero for that tick instead of a nonsense spike.
function netRates(previous, current, elapsedMs) {
  if (!previous || !current || !(elapsedMs > 0)) return null
  var seconds = elapsedMs / 1000
  var down = (current.rx - previous.rx) / seconds
  var up = (current.tx - previous.tx) / seconds
  return { down: down < 0 ? 0 : down, up: up < 0 ? 0 : up }
}

// -------------------------------------------------------------------- hwmon

// hwmon exposes millidegrees Celsius as a bare integer.
function parseTemp(text) {
  var value = parseInt(String(text || "").trim(), 10)
  if (!isFinite(value)) return null
  return value / 1000
}

// ------------------------------------------------------------------- GPU

// `nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,
// memory.total --format=csv,noheader,nounits` prints one comma-separated row
// per GPU. Only the first is read: the bar has room for one number, and
// picking an arbitrary card on a multi-GPU box would be worse than being
// explicit that it is the first.
function parseNvidia(text) {
  var line = String(text || "").split("\n")[0]
  if (!line) return null
  var fields = line.split(",")
  if (fields.length < 4) return null
  var util = parseFloat(fields[0])
  var temp = parseFloat(fields[1])
  var usedMib = parseFloat(fields[2])
  var totalMib = parseFloat(fields[3])
  if (!isFinite(util) || !isFinite(totalMib) || totalMib <= 0) return null
  return {
    util: util,
    temp: isFinite(temp) ? temp : null,
    vramUsed: isFinite(usedMib) ? usedMib * 1024 * 1024 : null,
    vramTotal: totalMib * 1024 * 1024
  }
}

// AMD (amdgpu) and Intel (i915/xe) both expose plain integers in sysfs rather
// than a query tool, so the backend reads the files and hands the raw strings
// here. Any field the driver does not publish arrives empty and stays null,
// which hides that chip rather than rendering a zero.
function parseSysfsGpu(busyText, vramUsedText, vramTotalText, tempText) {
  var util = parseFloat(String(busyText || "").trim())
  var used = parseFloat(String(vramUsedText || "").trim())
  var total = parseFloat(String(vramTotalText || "").trim())
  var temp = parseTemp(tempText)
  if (!isFinite(util)) return null
  return {
    util: Math.max(0, Math.min(100, util)),
    temp: temp,
    vramUsed: isFinite(used) ? used : null,
    vramTotal: isFinite(total) && total > 0 ? total : null
  }
}

// -------------------------------------------------------------------- disk

// `df -P` output: Filesystem 1024-blocks Used Available Capacity Mounted-on.
// -P forces one record per line, so a long device name cannot wrap and shift
// the columns.
function parseDiskPercent(text) {
  var lines = String(text || "").trim().split("\n")
  if (lines.length < 2) return null
  var fields = lines[lines.length - 1].trim().split(/\s+/)
  for (var i = 0; i < fields.length; i++) {
    var match = fields[i].match(/^(\d+)%$/)
    if (match) return parseInt(match[1], 10)
  }
  return null
}

// Pick the lowest metric among default routes, retaining order on ties.
function parseDefaultRouteIface(text) {
  var lines = String(text || "").split("\n")
  var selected = "", lowest = Infinity
  for (var i = 0; i < lines.length; i++) {
    if (!/^default\s/.test(lines[i].trim()) || /\blinkdown\b/.test(lines[i])) continue
    var match = lines[i].match(/\bdev\s+(\S+)/)
    var metric = lines[i].match(/\bmetric\s+(\d+)/)
    var priority = metric ? Number(metric[1]) : 0
    if (match && priority < lowest) { selected = match[1]; lowest = priority }
  }
  return selected
}

// --------------------------------------------------------------- formatting

// At most 4 characters, so the chip width can be pinned: one decimal below
// 10, none above. Bytes here are true binary units, matching what /proc and
// nvidia-smi report.
function formatBytes(bytes) {
  if (bytes === null || bytes === undefined || !isFinite(bytes)) return ""
  var units = ["B", "K", "M", "G", "T", "P"]
  var value = Math.abs(bytes)
  var unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }
  // Rounding can push a value up into the next unit — 1023.999K rounds to
  // "1024K", which is five characters and one unit too low — so the carry has
  // to happen after rounding, not before it.
  var rounded = value >= 10 || unit === 0 ? Math.round(value) : Math.round(value * 10) / 10
  if (rounded >= 1024 && unit < units.length - 1) {
    rounded = 1
    unit++
  }
  return String(rounded) + units[unit]
}

function formatPercent(value) {
  if (value === null || value === undefined || !isFinite(value)) return ""
  return String(Math.round(value)) + "%"
}

function formatTemp(celsius, unit) {
  if (celsius === null || celsius === undefined || !isFinite(celsius)) return ""
  var value = String(unit || "C").toUpperCase() === "F" ? celsius * 9 / 5 + 32 : celsius
  return String(Math.round(value)) + "°"
}

// Builds the visible chips in CHIP_ORDER. A metric whose source is missing
// contributes nothing at all: an absent GPU, an unreadable sensor and a
// not-yet-taken first sample all simply do not render, rather than showing a
// zero or an "N/A" that reads like a real measurement.
function buildChips(state, options) {
  var data = state || {}
  var opts = options || {}
  var tempUnit = opts.tempUnit || "C"
  var chips = []

  function enabled(key, fallback) {
    return opts[key] === undefined ? fallback !== false : opts[key] === true
  }

  for (var i = 0; i < CHIP_ORDER.length; i++) {
    var key = CHIP_ORDER[i]
    var text = ""
    var icon = ""
    var width = WIDTHS.percent

    if (key === "cpu" && enabled("showCpu") && data.cpu !== null && data.cpu !== undefined) {
      icon = ICONS.cpu
      text = formatPercent(data.cpu)
    } else if (key === "ram" && enabled("showRam") && data.mem) {
      icon = ICONS.ram
      if (String(opts.ramDisplay || "used") === "percent") {
        text = formatPercent(data.mem.percent)
      } else {
        text = formatBytes(data.mem.used)
        width = WIDTHS.size
      }
    } else if (key === "cpuTemp" && enabled("showCpuTemp") && data.cpuTemp !== null && data.cpuTemp !== undefined) {
      icon = ICONS.temp
      text = formatTemp(data.cpuTemp, tempUnit)
      width = WIDTHS.temp
    } else if (key === "gpu" && enabled("showGpu") && data.gpu && data.gpu.util !== null) {
      icon = ICONS.gpu
      text = formatPercent(data.gpu.util)
    } else if (key === "gpuTemp" && enabled("showGpuTemp") && data.gpu && data.gpu.temp !== null && data.gpu.temp !== undefined) {
      icon = ICONS.temp
      text = formatTemp(data.gpu.temp, tempUnit)
      width = WIDTHS.temp
    } else if (key === "vram" && enabled("showVram", false) && data.gpu && data.gpu.vramUsed !== null && data.gpu.vramUsed !== undefined) {
      icon = ICONS.vram
      text = formatBytes(data.gpu.vramUsed)
      width = WIDTHS.size
    } else if (key === "net" && enabled("showNet") && data.net) {
      // Down and up are separate chips so a vertical bar can stack them; laid
      // out horizontally they sit next to each other and read as one pair.
      chips.push({ key: "netDown", icon: ICONS.netDown, value: formatBytes(data.net.down), width: WIDTHS.rate })
      chips.push({ key: "netUp", icon: ICONS.netUp, value: formatBytes(data.net.up), width: WIDTHS.rate })
      continue
    } else if (key === "disk" && enabled("showDisk") && data.disk !== null && data.disk !== undefined) {
      icon = ICONS.disk
      text = formatPercent(data.disk)
    }

    if (text !== "") chips.push({ key: key, icon: icon, value: text, width: width })
  }
  return chips
}

// Plain-text rendering of the bar, used by the tests and by anything that
// wants one string. The widget itself lays the same chips out as separate
// items so the icon-to-value gap can be set in pixels rather than in whole
// monospace cells, which is wider than it should be.
function barText(state, options) {
  var chips = buildChips(state, options)
  var parts = []
  for (var i = 0; i < chips.length; i++) parts.push(chips[i].icon + " " + padRight(chips[i].value, chips[i].width))
  return parts.join(" ")
}

// A vertical bar is 28px wide — an icon plus a four-character value does not
// fit on one line. Stack the values instead and drop the icons: the reading is
// the part worth keeping, and the tooltip still names every one of them.
function barTextVertical(state, options) {
  var chips = buildChips(state, options)
  var parts = []
  for (var i = 0; i < chips.length; i++) parts.push(chips[i].value)
  return parts.join("\n")
}

// Full-precision readings, independent of which chips are switched on: the bar
// is the summary, this is everything the widget knows. Both the panel and the
// hover tooltip render from this one list so they can never disagree.
function detailRows(state, options) {
  var data = state || {}
  var opts = options || {}
  var unit = opts.tempUnit || "C"
  var rows = []

  if (data.cpu !== null && data.cpu !== undefined) {
    var cpu = (Math.round(data.cpu * 10) / 10) + "%"
    if (data.cpuTemp !== null && data.cpuTemp !== undefined) cpu += "  ·  " + formatTemp(data.cpuTemp, unit)
    rows.push({ key: "cpu", label: "CPU", value: cpu })
  }
  if (data.mem) {
    rows.push({
      key: "ram",
      label: "RAM",
      value: formatBytes(data.mem.used) + " / " + formatBytes(data.mem.total) + "  ·  " + formatPercent(data.mem.percent)
    })
  }
  if (data.gpu) {
    var gpu = formatPercent(data.gpu.util)
    if (data.gpu.temp !== null && data.gpu.temp !== undefined) gpu += "  ·  " + formatTemp(data.gpu.temp, unit)
    rows.push({ key: "gpu", label: "GPU", value: gpu })
    if (data.gpu.vramTotal) {
      rows.push({
        key: "vram",
        label: "VRAM",
        value: formatBytes(data.gpu.vramUsed) + " / " + formatBytes(data.gpu.vramTotal)
      })
    }
  }
  if (data.net) {
    rows.push({
      key: "net",
      label: "NET",
      value: "↓ " + formatBytes(data.net.down) + "/s  ↑ " + formatBytes(data.net.up) + "/s"
        + (data.netInterface ? "  ·  " + data.netInterface : "")
    })
  }
  if (data.disk !== null && data.disk !== undefined) {
    rows.push({
      key: "disk",
      label: "DISK",
      value: formatPercent(data.disk) + (data.diskMount ? "  ·  " + data.diskMount : "")
    })
  }
  return rows
}

// The hover tooltip is the same readings as the panel, flattened. Labels are
// padded to a constant width so the values line up in a monospace tooltip.
function tooltipText(state, options) {
  var rows = detailRows(state, options)
  var lines = []
  for (var i = 0; i < rows.length; i++) {
    var label = rows[i].label
    while (label.length < 4) label += " "
    lines.push(label + " " + rows[i].value)
  }
  return lines.join("\n")
}

// One row per switchable chip: its label, its current reading, and whether it
// is in the bar. Collapsing the readings and the switches into a single list
// keeps the panel short enough to fit — a separate readings section plus
// full-size toggle cards overflowed the popup and clipped the last rows.
function panelRows(state, options) {
  var data = state || {}
  var opts = options || {}
  var unit = opts.tempUnit || "C"

  var values = {
    showCpu: data.cpu !== null && data.cpu !== undefined ? (Math.round(data.cpu * 10) / 10) + "%" : "",
    showRam: data.mem ? formatBytes(data.mem.used) + " / " + formatBytes(data.mem.total) : "",
    showCpuTemp: formatTemp(data.cpuTemp, unit),
    showGpu: data.gpu && data.gpu.util !== null && data.gpu.util !== undefined ? formatPercent(data.gpu.util) : "",
    showGpuTemp: data.gpu ? formatTemp(data.gpu.temp, unit) : "",
    showVram: data.gpu && data.gpu.vramTotal ? formatBytes(data.gpu.vramUsed) + " / " + formatBytes(data.gpu.vramTotal) : "",
    showNet: data.net ? "↓ " + formatBytes(data.net.down) + "  ↑ " + formatBytes(data.net.up) : "",
    showDisk: data.disk !== null && data.disk !== undefined ? formatPercent(data.disk) : ""
  }

  var rows = []
  for (var i = 0; i < TOGGLES.length; i++) {
    var toggle = TOGGLES[i]
    var value = values[toggle.key] || ""
    rows.push({
      key: toggle.key,
      label: toggle.label,
      // An em dash rather than a blank keeps the column aligned and says
      // "nothing to read here" without implying a measurement of zero.
      value: value !== "" ? value : "—",
      available: value !== "",
      enabled: opts[toggle.key] === undefined ? toggle.defaultValue : opts[toggle.key] === true
    })
  }
  return rows
}

// The chips the panel offers as switches, in the order they render in the bar.
// `key` is the settings key the toggle writes, so the panel and the plugin
// settings screen drive exactly the same values.
var TOGGLES = [
  { key: "showCpu", label: "CPU usage", defaultValue: true },
  { key: "showRam", label: "Memory", defaultValue: true },
  { key: "showCpuTemp", label: "CPU temperature", defaultValue: true },
  { key: "showGpu", label: "GPU usage", defaultValue: true },
  { key: "showGpuTemp", label: "GPU temperature", defaultValue: true },
  { key: "showVram", label: "VRAM used", defaultValue: false },
  { key: "showNet", label: "Network throughput", defaultValue: true },
  { key: "showDisk", label: "Disk usage", defaultValue: true }
]

if (typeof module !== "undefined") {
  module.exports = {
    ICONS: ICONS,
    CHIP_ORDER: CHIP_ORDER,
    WIDTHS: WIDTHS,
    padLeft: padLeft,
    padRight: padRight,
    parseCpuTotals: parseCpuTotals,
    cpuPercent: cpuPercent,
    parseMeminfo: parseMeminfo,
    parseNetDev: parseNetDev,
    netRates: netRates,
    parseTemp: parseTemp,
    parseNvidia: parseNvidia,
    parseSysfsGpu: parseSysfsGpu,
    parseDiskPercent: parseDiskPercent,
    parseDefaultRouteIface: parseDefaultRouteIface,
    formatBytes: formatBytes,
    formatPercent: formatPercent,
    formatTemp: formatTemp,
    buildChips: buildChips,
    barText: barText,
    barTextVertical: barTextVertical,
    detailRows: detailRows,
    panelRows: panelRows,
    tooltipText: tooltipText,
    TOGGLES: TOGGLES
  }
}
