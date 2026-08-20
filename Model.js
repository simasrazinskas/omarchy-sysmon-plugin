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

// Every value is padded to a constant width so a reading that grows a digit
// (9% -> 10%, 99C -> 100C) cannot shove the rest of the bar sideways. The
// bar font is monospace, so padding with spaces is enough to pin the width.
var WIDTHS = { percent: 4, temp: 4, size: 4, rate: 4 }

function padLeft(value, width) {
  var text = String(value)
  while (text.length < width) text = " " + text
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

// `ip route show default` names the interface carrying the default route,
// which is the one whose throughput people mean. Picking the first line makes
// the lowest-metric route win when several exist.
function parseDefaultRouteIface(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/\bdev\s+(\S+)/)
    if (match) return match[1]
  }
  return ""
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
      chips.push({ key: "netDown", icon: ICONS.netDown, value: padLeft(formatBytes(data.net.down), WIDTHS.rate) })
      chips.push({ key: "netUp", icon: ICONS.netUp, value: padLeft(formatBytes(data.net.up), WIDTHS.rate) })
      continue
    } else if (key === "disk" && enabled("showDisk") && data.disk !== null && data.disk !== undefined) {
      icon = ICONS.disk
      text = formatPercent(data.disk)
    }

    if (text !== "") chips.push({ key: key, icon: icon, value: padLeft(text, width) })
  }
  return chips
}

// Horizontal bars get icon + value per chip, two spaces between chips.
function barText(state, options) {
  var chips = buildChips(state, options)
  var parts = []
  for (var i = 0; i < chips.length; i++) parts.push(chips[i].icon + " " + chips[i].value)
  return parts.join("  ")
}

// A vertical bar is 28px wide — an icon plus a four-character value does not
// fit on one line. Stack the values instead and drop the icons: the reading is
// the part worth keeping, and the tooltip still names every one of them.
function barTextVertical(state, options) {
  var chips = buildChips(state, options)
  var parts = []
  for (var i = 0; i < chips.length; i++) parts.push(chips[i].value.trim())
  return parts.join("\n")
}

// The tooltip is this widget's only detail surface — there is no popup panel —
// so it carries the full-precision values and the totals the bar has no room
// for, including chips the user has switched off.
function tooltipText(state, options) {
  var data = state || {}
  var opts = options || {}
  var unit = opts.tempUnit || "C"
  var lines = []

  if (data.cpu !== null && data.cpu !== undefined) {
    var cpuLine = "CPU  " + (Math.round(data.cpu * 10) / 10) + "%"
    if (data.cpuTemp !== null && data.cpuTemp !== undefined) cpuLine += "  ·  " + formatTemp(data.cpuTemp, unit)
    lines.push(cpuLine)
  }
  if (data.mem) {
    lines.push("RAM  " + formatBytes(data.mem.used) + " / " + formatBytes(data.mem.total)
      + "  ·  " + formatPercent(data.mem.percent))
  }
  if (data.gpu) {
    var gpuLine = "GPU  " + formatPercent(data.gpu.util)
    if (data.gpu.temp !== null && data.gpu.temp !== undefined) gpuLine += "  ·  " + formatTemp(data.gpu.temp, unit)
    lines.push(gpuLine)
    if (data.gpu.vramTotal) {
      lines.push("VRAM " + formatBytes(data.gpu.vramUsed) + " / " + formatBytes(data.gpu.vramTotal))
    }
  }
  if (data.net) {
    lines.push("NET  ↓ " + formatBytes(data.net.down) + "/s  ↑ " + formatBytes(data.net.up) + "/s"
      + (data.netInterface ? "  ·  " + data.netInterface : ""))
  }
  if (data.disk !== null && data.disk !== undefined) {
    lines.push("DISK " + formatPercent(data.disk) + (data.diskMount ? "  ·  " + data.diskMount : ""))
  }
  return lines.join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    ICONS: ICONS,
    CHIP_ORDER: CHIP_ORDER,
    WIDTHS: WIDTHS,
    padLeft: padLeft,
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
    tooltipText: tooltipText
  }
}
