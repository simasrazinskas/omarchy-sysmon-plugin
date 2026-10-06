const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

// Real samples taken from a running machine, so the parsers are tested against
// the exact shapes the kernel and nvidia-smi actually emit.
const PROC_STAT = [
  "cpu  5130975 721 1219628 352675467 245032 288590 68337 0 0 0",
  "cpu0 259387 39 61553 17627395 12938 20826 12345 0 0 0",
  "intr 1234567890",
  ""
].join("\n")

const PROC_MEMINFO = [
  "MemTotal:       65593584 kB",
  "MemFree:        41234567 kB",
  "MemAvailable:   47000000 kB",
  "Buffers:         1234567 kB",
  ""
].join("\n")

const PROC_NET_DEV = [
  "Inter-|   Receive                                                |  Transmit",
  " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed",
  "    lo: 1000 10 0 0 0 0 0 0 1000 10 0 0 0 0 0 0",
  "enp129s0: 31866150334 26028235    0   30    0     0          0     36467 3371386801 6306183    0    0    0     0       0          0",
  ""
].join("\n")

const DF_OUTPUT = [
  "Filesystem     1024-blocks      Used Available Capacity Mounted on",
  "/dev/mapper/root 975019084 221093736 704369788      24% /",
  ""
].join("\n")

// ---------------------------------------------------------------- /proc/stat

test("parseCpuTotals sums the aggregate line and folds iowait into idle", () => {
  const totals = Model.parseCpuTotals(PROC_STAT)
  // user+nice+system+idle+iowait+irq+softirq+steal, guest excluded because the
  // kernel already counts it inside user.
  assert.equal(totals.total, 5130975 + 721 + 1219628 + 352675467 + 245032 + 288590 + 68337 + 0)
  assert.equal(totals.idle, 352675467 + 245032)
})

test("parseCpuTotals returns null when there is no cpu line", () => {
  assert.equal(Model.parseCpuTotals("intr 123\nctxt 456"), null)
  assert.equal(Model.parseCpuTotals(""), null)
})

test("cpuPercent needs two samples, so the first tick reports null not zero", () => {
  const totals = Model.parseCpuTotals(PROC_STAT)
  assert.equal(Model.cpuPercent(null, totals), null)
})

test("cpuPercent computes the busy share between two samples", () => {
  const previous = { total: 1000, idle: 900 }
  const current = { total: 1100, idle: 950 }
  // 100 jiffies elapsed, 50 of them idle.
  assert.equal(Model.cpuPercent(previous, current), 50)
})

test("cpuPercent clamps and rejects a non-advancing counter", () => {
  assert.equal(Model.cpuPercent({ total: 1000, idle: 900 }, { total: 1000, idle: 900 }), null)
  assert.equal(Model.cpuPercent({ total: 1000, idle: 500 }, { total: 1100, idle: 500 }), 100)
})

// ------------------------------------------------------------- /proc/meminfo

test("parseMeminfo uses MemAvailable rather than MemFree", () => {
  const mem = Model.parseMeminfo(PROC_MEMINFO)
  assert.equal(mem.total, 65593584 * 1024)
  assert.equal(mem.used, (65593584 - 47000000) * 1024)
  // MemFree would have reported a far higher usage than the machine really has.
  assert.ok(mem.percent > 28 && mem.percent < 29)
})

test("parseMeminfo returns null when a required field is absent", () => {
  assert.equal(Model.parseMeminfo("MemTotal:  100 kB"), null)
  assert.equal(Model.parseMeminfo(""), null)
})

// ------------------------------------------------------------ /proc/net/dev

test("parseNetDev picks the named interface and reads rx/tx bytes", () => {
  const counters = Model.parseNetDev(PROC_NET_DEV, "enp129s0")
  assert.equal(counters.rx, 31866150334)
  assert.equal(counters.tx, 3371386801)
})

test("parseNetDev does not confuse one interface for another", () => {
  assert.equal(Model.parseNetDev(PROC_NET_DEV, "lo").rx, 1000)
  assert.equal(Model.parseNetDev(PROC_NET_DEV, "enp129"), null)
  assert.equal(Model.parseNetDev(PROC_NET_DEV, ""), null)
})

test("netRates divides by the interval that actually elapsed", () => {
  const rates = Model.netRates({ rx: 1000, tx: 500 }, { rx: 3000, tx: 1500 }, 2000)
  assert.equal(rates.down, 1000)
  assert.equal(rates.up, 500)
})

test("netRates reports zero across a counter reset instead of a negative spike", () => {
  const rates = Model.netRates({ rx: 5000, tx: 5000 }, { rx: 10, tx: 10 }, 1000)
  assert.equal(rates.down, 0)
  assert.equal(rates.up, 0)
})

test("netRates refuses a zero or missing interval", () => {
  assert.equal(Model.netRates({ rx: 1, tx: 1 }, { rx: 2, tx: 2 }, 0), null)
  assert.equal(Model.netRates(null, { rx: 2, tx: 2 }, 1000), null)
})

// -------------------------------------------------------------------- hwmon

test("parseTemp converts millidegrees to degrees", () => {
  assert.equal(Model.parseTemp("41000\n"), 41)
  assert.equal(Model.parseTemp("105000"), 105)
})

test("parseTemp returns null for an unreadable sensor", () => {
  assert.equal(Model.parseTemp(""), null)
  assert.equal(Model.parseTemp("n/a"), null)
})

// ---------------------------------------------------------------------- GPU

test("parseNvidia reads the csv row nvidia-smi emits", () => {
  const gpu = Model.parseNvidia("11, 38, 1287, 16303\n")
  assert.equal(gpu.util, 11)
  assert.equal(gpu.temp, 38)
  assert.equal(gpu.vramUsed, 1287 * 1024 * 1024)
  assert.equal(gpu.vramTotal, 16303 * 1024 * 1024)
})

test("parseNvidia takes the first GPU on a multi-card machine", () => {
  assert.equal(Model.parseNvidia("11, 38, 1287, 16303\n55, 70, 900, 8000\n").util, 11)
})

test("parseNvidia returns null for driver-not-loaded output", () => {
  assert.equal(Model.parseNvidia(""), null)
  assert.equal(Model.parseNvidia("[N/A], [N/A], [N/A], [N/A]"), null)
})

test("parseSysfsGpu keeps utilisation when the driver publishes no VRAM", () => {
  const gpu = Model.parseSysfsGpu("42\n", "", "", "55000\n")
  assert.equal(gpu.util, 42)
  assert.equal(gpu.temp, 55)
  assert.equal(gpu.vramUsed, null)
  assert.equal(gpu.vramTotal, null)
})

test("parseSysfsGpu requires utilisation, since that is the chip's whole point", () => {
  assert.equal(Model.parseSysfsGpu("", "1", "2", "55000"), null)
})

// -------------------------------------------------------------- disk + route

test("parseDiskPercent reads the capacity column out of df -P", () => {
  assert.equal(Model.parseDiskPercent(DF_OUTPUT), 24)
})

test("parseDiskPercent returns null when df failed or printed only a header", () => {
  assert.equal(Model.parseDiskPercent("Filesystem 1024-blocks Used Available Capacity Mounted on"), null)
  assert.equal(Model.parseDiskPercent(""), null)
})

test("parseDefaultRouteIface names the device carrying the default route", () => {
  assert.equal(
    Model.parseDefaultRouteIface("default via 192.168.1.1 dev enp129s0 proto dhcp src 192.168.1.70 metric 100"),
    "enp129s0")
})

test("parseDefaultRouteIface prefers the lowest metric, regardless of output order", () => {
  const text = "default via 10.0.0.1 dev wlan0 metric 600\ndefault via 192.168.1.1 dev eth0 metric 100"
  assert.equal(Model.parseDefaultRouteIface(text), "eth0")
})

test("parseDefaultRouteIface returns empty with no default route", () => {
  assert.equal(Model.parseDefaultRouteIface(""), "")
})

// --------------------------------------------------------------- formatting

test("formatBytes stays within four characters across every magnitude", () => {
  assert.equal(Model.formatBytes(512), "512B")
  assert.equal(Model.formatBytes(1024 * 512), "512K")
  assert.equal(Model.formatBytes(1024 * 1024 * 1024 * 18.2), "18G")
  assert.equal(Model.formatBytes(1024 * 1024 * 1024 * 9.24), "9.2G")
  for (const bytes of [0, 999, 12345, 1234567, 12345678901, 1234567890123]) {
    assert.ok(Model.formatBytes(bytes).length <= 4, `${bytes} -> ${Model.formatBytes(bytes)}`)
  }
})

test("formatBytes carries into the next unit rather than printing 1024K", () => {
  assert.equal(Model.formatBytes(1024 * 1024 - 1), "1M")
})

test("formatBytes returns empty for a missing reading", () => {
  assert.equal(Model.formatBytes(null), "")
  assert.equal(Model.formatBytes(undefined), "")
})

test("formatTemp converts to Fahrenheit on request", () => {
  assert.equal(Model.formatTemp(42, "C"), "42°")
  assert.equal(Model.formatTemp(100, "F"), "212°")
  assert.equal(Model.formatTemp(null, "C"), "")
})

test("padLeft pins width so a growing value cannot shift the bar", () => {
  assert.equal(Model.padLeft("5%", 4), "  5%")
  assert.equal(Model.padLeft("100%", 4), "100%")
  // Already wider than the pin: never truncate a real reading to fit.
  assert.equal(Model.padLeft("1000%", 4), "1000%")
})

// --------------------------------------------------------------------- chips

function fullState() {
  return {
    cpu: 12.4,
    mem: { total: 64 * 1024 * 1024 * 1024, used: 18 * 1024 * 1024 * 1024, percent: 28.1 },
    cpuTemp: 42,
    gpu: { util: 64, temp: 71, vramUsed: 9 * 1024 * 1024 * 1024, vramTotal: 16 * 1024 * 1024 * 1024 },
    net: { down: 1200000, up: 340000 },
    disk: 23,
    netInterface: "enp129s0",
    diskMount: "/"
  }
}

test("chips carry the raw value plus the width to pin it to", () => {
  const chips = Model.buildChips(fullState(), {})
  const byKey = Object.fromEntries(chips.map(c => [c.key, c]))
  // Raw, so the widget can reserve the width in pixels and left-align inside
  // it — padding here would put the slack between icon and value.
  assert.equal(byKey.cpu.value, "12%")
  assert.equal(byKey.cpuTemp.value, "42°")
  assert.equal(byKey.disk.value, "23%")
  assert.equal(byKey.ram.value, "18G")
  for (const chip of chips) {
    assert.ok(chip.width >= chip.value.length, `${chip.key} width too small for its value`)
  }
})

test("barText pads trailing, keeping every value hard against its icon", () => {
  const state = fullState()
  state.cpu = 5
  const text = Model.barText(state, { showCpu: true, showRam: false, showCpuTemp: false,
    showGpu: false, showGpuTemp: false, showNet: false, showDisk: false })
  // Icon, one space, then the digits — never icon, space, then blank cells.
  assert.equal(text, Model.ICONS.cpu + " 5%  ")
  assert.ok(!text.startsWith(Model.ICONS.cpu + "   "))
})

test("padRight pins width without displacing the value", () => {
  assert.equal(Model.padRight("5%", 4), "5%  ")
  assert.equal(Model.padRight("100%", 4), "100%")
  assert.equal(Model.padRight("1000%", 4), "1000%")
})

test("a metric with no reading contributes no chip at all", () => {
  const state = fullState()
  state.gpu = null
  state.cpuTemp = null
  const keys = Model.buildChips(state, {}).map(c => c.key)
  assert.ok(!keys.includes("gpu"))
  assert.ok(!keys.includes("gpuTemp"))
  assert.ok(!keys.includes("cpuTemp"))
  assert.ok(keys.includes("cpu"))
})

test("switched-off chips disappear even when the reading is present", () => {
  const keys = Model.buildChips(fullState(), { showCpu: false, showNet: false }).map(c => c.key)
  assert.ok(!keys.includes("cpu"))
  assert.ok(!keys.includes("netDown"))
  assert.ok(keys.includes("ram"))
})

test("VRAM is off unless asked for, since it duplicates the GPU chip's story", () => {
  assert.ok(!Model.buildChips(fullState(), {}).map(c => c.key).includes("vram"))
  assert.ok(Model.buildChips(fullState(), { showVram: true }).map(c => c.key).includes("vram"))
})

test("ramDisplay switches memory between absolute and percent", () => {
  const used = Model.buildChips(fullState(), { ramDisplay: "used" }).find(c => c.key === "ram")
  const percent = Model.buildChips(fullState(), { ramDisplay: "percent" }).find(c => c.key === "ram")
  assert.equal(used.value.trim(), "18G")
  assert.equal(percent.value.trim(), "28%")
})

test("chips keep CHIP_ORDER regardless of which ones are on", () => {
  const keys = Model.buildChips(fullState(), { showVram: true }).map(c => c.key)
  assert.deepEqual(keys, ["cpu", "cpuTemp", "ram", "gpu", "gpuTemp", "vram", "netDown", "netUp", "disk"])
})

test("network splits into two chips so a vertical bar can stack them", () => {
  const keys = Model.buildChips(fullState(), {}).map(c => c.key)
  assert.ok(keys.includes("netDown") && keys.includes("netUp"))
})

test("barText renders nothing when every reading is missing", () => {
  assert.equal(Model.barText({}, {}), "")
  assert.equal(Model.barText(null, null), "")
})

test("vertical bars drop the icons and stack the values", () => {
  const vertical = Model.barTextVertical(fullState(), { showNet: false, showDisk: false })
  assert.deepEqual(vertical.split("\n"), ["12%", "42°", "18G", "64%", "71°"])
  // 28px of bar leaves no room for an icon next to a four-character reading.
  for (const line of vertical.split("\n")) assert.ok(line.length <= 4)
})

// ------------------------------------------------------------------- tooltip

test("tooltip carries full values including chips switched off in the bar", () => {
  const text = Model.tooltipText(fullState(), { showCpu: false })
  assert.match(text, /CPU {2}12\.4%/)
  assert.match(text, /42°/)
  assert.match(text, /RAM {2}18G \/ 64G/)
  assert.match(text, /VRAM 9G \/ 16G/)
  assert.match(text, /enp129s0/)
  assert.match(text, /DISK 23%/)
})

test("tooltip omits sections with no data rather than showing zeros", () => {
  const text = Model.tooltipText({ cpu: 5 }, {})
  assert.match(text, /CPU {2}5%/)
  assert.ok(!text.includes("RAM"))
  assert.ok(!text.includes("GPU"))
  assert.ok(!text.includes("DISK"))
})

// ------------------------------------------------------------- panel + rows

test("detailRows reports every reading regardless of which chips are on", () => {
  // The bar is the summary; the panel shows everything the widget knows, so
  // switching a chip off must not empty the panel row too.
  const rows = Model.detailRows(fullState(), { showCpu: false, showGpu: false, showDisk: false })
  const keys = rows.map(r => r.key)
  assert.deepEqual(keys, ["cpu", "ram", "gpu", "vram", "net", "disk"])
})

test("detailRows omits a reading that genuinely has no data", () => {
  const state = fullState()
  state.gpu = null
  state.net = null
  const keys = Model.detailRows(state, {}).map(r => r.key)
  assert.deepEqual(keys, ["cpu", "ram", "disk"])
})

test("detailRows carries full precision the bar chips round away", () => {
  const cpu = Model.detailRows(fullState(), {}).find(r => r.key === "cpu")
  // The chip renders "12%"; the panel keeps the tenth.
  assert.match(cpu.value, /12\.4%/)
})

test("detailRows names the interface and mountpoint being measured", () => {
  const rows = Model.detailRows(fullState(), {})
  assert.match(rows.find(r => r.key === "net").value, /enp129s0/)
  assert.match(rows.find(r => r.key === "disk").value, /\//)
})

test("detailRows is empty before the first samples land", () => {
  assert.deepEqual(Model.detailRows({}, {}), [])
  assert.deepEqual(Model.detailRows(null, null), [])
})

test("every panel toggle drives a chip the bar actually renders", () => {
  // A toggle whose key buildChips ignores would be a dead switch in the panel.
  const chipKeys = new Set(Model.buildChips(fullState(), {
    showCpu: true, showRam: true, showCpuTemp: true, showGpu: true,
    showGpuTemp: true, showVram: true, showNet: true, showDisk: true
  }).map(c => c.key))
  for (const toggle of Model.TOGGLES) {
    const optionsOff = {}
    for (const t of Model.TOGGLES) optionsOff[t.key] = true
    optionsOff[toggle.key] = false
    const withAll = Model.buildChips(fullState(), Object.fromEntries(Model.TOGGLES.map(t => [t.key, true])))
    const withOne = Model.buildChips(fullState(), optionsOff)
    assert.ok(withOne.length < withAll.length, `${toggle.key} changed nothing`)
  }
  assert.ok(chipKeys.size > 0)
})

test("panelRows lists one row per switch, always, in bar order", () => {
  // Fixed row count is what keeps the popup a predictable height — the panel
  // clipped its last rows when the content could grow.
  const rows = Model.panelRows(fullState(), {})
  assert.equal(rows.length, Model.TOGGLES.length)
  assert.deepEqual(rows.map(r => r.key), Model.TOGGLES.map(t => t.key))
})

test("panelRows keeps its row count when a metric has no reading at all", () => {
  const state = fullState()
  state.gpu = null
  state.cpuTemp = null
  const rows = Model.panelRows(state, {})
  assert.equal(rows.length, Model.TOGGLES.length)
  const gpu = rows.find(r => r.key === "showGpu")
  assert.equal(gpu.value, "—")
  assert.equal(gpu.available, false)
  assert.equal(rows.find(r => r.key === "showCpu").available, true)
})

test("panelRows reports each switch's current state, falling back to defaults", () => {
  const rows = Model.panelRows(fullState(), { showCpu: false })
  assert.equal(rows.find(r => r.key === "showCpu").enabled, false)
  // Not specified in options, so the manifest default applies.
  assert.equal(rows.find(r => r.key === "showRam").enabled, true)
  assert.equal(rows.find(r => r.key === "showVram").enabled, false)
})

test("panelRows shows readings for metrics switched off in the bar", () => {
  const row = Model.panelRows(fullState(), { showDisk: false }).find(r => r.key === "showDisk")
  assert.equal(row.enabled, false)
  assert.equal(row.value, "23%")
})

test("panel toggle defaults match the manifest defaults", () => {
  const manifest = require("../manifest.json")
  for (const toggle of Model.TOGGLES) {
    assert.equal(toggle.defaultValue, manifest.barWidget.defaults[toggle.key],
      `${toggle.key} default disagrees with the manifest`)
  }
})


test("default-route selection skips linkdown and keeps the first equal metric", () => {
  assert.equal(Model.parseDefaultRouteIface("default dev eth0 metric 10 linkdown\ndefault dev wlan0 metric 20\ndefault dev usb0 metric 20"), "wlan0")
  assert.equal(Model.parseDefaultRouteIface("default via fe80::1 dev wlan0 proto ra metric 600"), "wlan0")
  assert.equal(Model.parseDefaultRouteIface("10.0.0.0/8 dev eth0"), "")
})
