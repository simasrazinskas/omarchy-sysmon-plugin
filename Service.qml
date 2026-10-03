import QtQuick
import Quickshell.Io
import "Model.js" as Model
import "Metrics.js" as Metrics

// Data layer: samples the machine and exposes one `state` object for the
// widget to render.
//
// Everything the kernel publishes as a file is read in-process with FileView —
// /proc and /sys are cheap, and forking a helper twice a second to read data
// that is already a file would cost more than the readings are worth. Only the
// GPU and disk use slower subprocesses; process scans run only in their view.
Item {
  id: root

  property var settings: ({})
  property bool processesActive: false
  property var history: []
  property var coreLoads: []
  property var _prevCores: null
  property var memoryDetail: null
  property var diskDetail: null
  property var loadAverage: null
  property var uptime: null
  property string cpuName: ""
  property string hostname: ""
  property var pressureCpu: null
  property var pressureMemory: null
  property var pressureIo: null
  readonly property var pressures: ({cpu: pressureCpu, memory: pressureMemory, io: pressureIo})
  property var networkTotals: null
  property double lastSample: 0
  property var processes: []
  property var _previousProcesses: null
  property string processError: ""
  property double processUpdated: 0

  onProcessesActiveChanged: {
    if (processesActive) { _previousProcesses = null; processes = []; refreshProcesses() }
  }

  function refreshProcesses() {
    if (processesActive && !processReader.running) processReader.running = true
  }

  function record() {
    var now = Date.now()
    lastSample = now
    history = Metrics.append(history, {time: now, cpu: cpu, ram: mem ? mem.percent : null,
      gpu: gpuController.reading ? gpuController.reading.util : null,
      down: net ? net.down : null, up: net ? net.up : null})
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 2, 1, 30)
  readonly property string configuredInterface: String(setting("networkInterface", "")).trim()
  readonly property string configuredMount: String(setting("diskMountpoint", "")).trim()

  // Auto-detected values, used whenever the matching setting is blank. The
  // route is re-read periodically so a laptop moving between wifi and ethernet
  // follows along without anyone editing settings.
  property string detectedInterface: ""
  property string detectedMount: "/"
  property string cpuTempPath: ""

  readonly property string activeInterface: configuredInterface !== "" ? configuredInterface : detectedInterface
  readonly property string activeMount: configuredMount !== "" ? configuredMount : detectedMount

  property var cpu: null
  property var mem: null
  property var cpuTemp: null
  property var net: null
  property var disk: null

  // Previous cumulative counters, kept with the timestamp they were taken at
  // so a rate is computed against the interval that actually elapsed rather
  // than the interval that was scheduled.
  property var _prevCpu: null
  property var _prevNet: null
  property double _prevNetMs: 0

  // Which vendor backend won, so the panel can say what it is reading from —
  // empty when no GPU could be read at all.
  readonly property string gpuVendor: gpuController.available ? gpuController.vendor : ""

  readonly property var state: ({
    cpu: cpu,
    mem: mem,
    cpuTemp: cpuTemp,
    gpu: gpuController.reading,
    net: net,
    disk: disk,
    netInterface: activeInterface,
    diskMount: activeMount
  })

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  // A changed interface invalidates the counters the old one accumulated;
  // keeping them would produce one huge bogus rate on the first tick after the
  // switch, as the difference between two unrelated interfaces is reported as
  // traffic.
  onActiveInterfaceChanged: {
    _prevNet = null
    _prevNetMs = 0
    net = null
    networkTotals = null
    // Never label traffic from the old interface as belonging to the new one.
    history = history.map(function(sample) {
      var copy = Object.assign({}, sample)
      copy.down = null; copy.up = null
      return copy
    })
  }

  onActiveMountChanged: {
    disk = null
    diskDetail = null
    refreshDisk()
  }

  function tick() {
    cpuStatFile.reload()
    memInfoFile.reload()
    loadFile.reload()
    uptimeFile.reload()
    pressureCpuFile.reload()
    pressureMemoryFile.reload()
    pressureIoFile.reload()
    if (activeInterface !== "") netDevFile.reload()
    if (cpuTempPath !== "") cpuTempFile.reload()
  }

  function refreshDisk() {
    if (diskProcess.running || activeMount === "") return
    diskProcess.command = ["bash", "-c", "export LC_ALL=C; exec timeout 5 df -Pk -- \"$1\"", "sysmon", activeMount]
    diskProcess.requestedMount = activeMount
    diskProcess.running = true
  }

  // ------------------------------------------------------------- procfs reads

  FileView {
    id: cpuStatFile
    path: "/proc/stat"
    printErrors: false
    onLoaded: {
      var totals = Model.parseCpuTotals(text())
      var nextCores = Metrics.cores(text())
      root.coreLoads = Metrics.coreUsage(root._prevCores, nextCores)
      root._prevCores = nextCores
      if (!totals) { root.cpu = null; root._prevCpu = null; root.record(); return }
      var percent = Model.cpuPercent(root._prevCpu, totals)
      root._prevCpu = totals
      // The first sample has nothing to diff against, so cpu stays null and
      // the chip does not render until the second tick — a real 0% and "not
      // measured yet" must not look the same.
      root.cpu = percent
      root.record()
    }
    onLoadFailed: { root.cpu = null; root._prevCpu = null; root.coreLoads = []; root._prevCores = null; root.record() }
  }

  FileView {
    id: memInfoFile
    path: "/proc/meminfo"
    printErrors: false
    onLoaded: { root.mem = Model.parseMeminfo(text()); root.memoryDetail = Metrics.memory(text()) }
    onLoadFailed: { root.mem = null; root.memoryDetail = null }
  }

  FileView {
    id: netDevFile
    path: "/proc/net/dev"
    printErrors: false
    onLoaded: {
      var counters = Model.parseNetDev(text(), root.activeInterface)
      root.networkTotals = counters
      var now = Date.now()
      if (!counters) {
        root.net = null
        root._prevNet = null
        return
      }
      var rates = Model.netRates(root._prevNet, counters, now - root._prevNetMs)
      root._prevNet = counters
      root._prevNetMs = now
      root.net = rates
    }
    onLoadFailed: { root.net = null; root.networkTotals = null; root._prevNet = null }
  }

  FileView {
    id: cpuTempFile
    path: root.cpuTempPath
    printErrors: false
    onLoaded: root.cpuTemp = Model.parseTemp(text())
    onLoadFailed: root.cpuTemp = null
  }

  // ---------------------------------------------------------------- discovery

  // hwmon numbering is assigned in probe order and is not stable across boots,
  // so the CPU sensor has to be found by name rather than hardcoded. Prefer a
  // package-wide label (Intel's "Package id 0", AMD's Tctl/Tdie) over a single
  // core, which would report whichever core happens to be busy.
  Process {
    id: cpuTempProbe
    command: ["bash", "-c",
      "for hw in /sys/class/hwmon/hwmon*; do\n"
      + "  name=$(cat \"$hw/name\" 2>/dev/null)\n"
      + "  case \"$name\" in\n"
      + "    coretemp|k10temp|zenpower|cpu_thermal|acpitz) ;;\n"
      + "    *) continue ;;\n"
      + "  esac\n"
      + "  for label in \"$hw\"/temp*_label; do\n"
      + "    [ -r \"$label\" ] || continue\n"
      + "    case \"$(cat \"$label\" 2>/dev/null)\" in\n"
      + "      Package\\ id*|Tctl|Tdie|CPU*) echo \"${label%_label}_input\"; exit 0 ;;\n"
      + "    esac\n"
      + "  done\n"
      + "  [ -r \"$hw/temp1_input\" ] && { echo \"$hw/temp1_input\"; exit 0; }\n"
      + "done\n"
      + "exit 127\n"]
    stdout: StdioCollector {
      id: cpuTempProbeOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.cpuTempPath = exitCode === 0 ? String(cpuTempProbeOut.text || "").trim() : ""
      if (root.cpuTempPath === "") root.cpuTemp = null
    }
  }

  Process {
    id: routeProcess
    command: ["bash", "-c", "exec timeout 5 ip route show default"]
    stdout: StdioCollector {
      id: routeStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.detectedInterface = exitCode === 0
        ? Model.parseDefaultRouteIface(String(routeStdout.text || "")) : ""
    }
  }

  function refreshRoute() {
    // Nothing to detect while the user has named an interface explicitly.
    if (routeProcess.running || root.configuredInterface !== "") return
    routeProcess.running = true
  }

  Process {
    id: diskProcess
    property string requestedMount: ""
    stdout: StdioCollector {
      id: diskStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (requestedMount !== root.activeMount) { Qt.callLater(root.refreshDisk); return }
      root.diskDetail = exitCode === 0 ? Metrics.disk(String(diskStdout.text || "")) : null
      root.disk = root.diskDetail ? root.diskDetail.percent : null
    }
  }

  GpuController {
    id: gpuController
    intervalMs: Math.max(5000, root.refreshIntervalSec * 1000)
  }

  // ------------------------------------------------------------------- timers

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  // Disk usage moves in minutes, not seconds, and every reading is a fork —
  // polling it on the main tick would be the most expensive metric here by far
  // and the least informative.
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshDisk()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.refreshRoute(); if (root.cpuTemp === null && !cpuTempProbe.running) cpuTempProbe.running = true }
  }


  FileView {
    id: loadFile; path: "/proc/loadavg"; printErrors: false
    onLoaded: root.loadAverage = Metrics.load(text())
    onLoadFailed: root.loadAverage = null
  }
  FileView {
    id: uptimeFile; path: "/proc/uptime"; printErrors: false
    onLoaded: { var n = parseFloat(text()); root.uptime = isFinite(n) ? n : null }
    onLoadFailed: root.uptime = null
  }
  FileView {
    path: "/proc/cpuinfo"; printErrors: false
    onLoaded: { var m = text().match(/(?:model name|Hardware)\s*:\s*(.+)/); root.cpuName = m ? m[1].trim() : "Processor" }
  }
  FileView {
    path: "/proc/sys/kernel/hostname"; printErrors: false
    onLoaded: root.hostname = text().trim()
  }
  FileView {
    id: pressureCpuFile; path: "/proc/pressure/cpu"; printErrors: false
    onLoaded: root.pressureCpu = Metrics.pressure(text())
    onLoadFailed: root.pressureCpu = null
  }
  FileView {
    id: pressureMemoryFile; path: "/proc/pressure/memory"; printErrors: false
    onLoaded: root.pressureMemory = Metrics.pressure(text())
    onLoadFailed: root.pressureMemory = null
  }
  FileView {
    id: pressureIoFile; path: "/proc/pressure/io"; printErrors: false
    onLoaded: root.pressureIo = Metrics.pressure(text())
    onLoadFailed: root.pressureIo = null
  }
  Process {
    id: processReader
    command: ["timeout", "5", "python3", decodeURIComponent(Qt.resolvedUrl("scripts/processes.py").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector { id: processOutput; waitForEnd: true }
    onExited: function(code) {
      if (!root.processesActive) return
      if (code !== 0) { root.processError = "Process readings unavailable. Check that Python 3 is installed."; root.processes = []; root._previousProcesses = null; return }
      try {
        var snapshot = JSON.parse(processOutput.text)
        root.processes = Metrics.processRates(root._previousProcesses, snapshot)
        root._previousProcesses = snapshot
        root.processUpdated = Date.now()
        root.processError = ""
      } catch (e) { root.processError = "Could not read processes."; root.processes = []; root._previousProcesses = null }
    }
  }
  Timer {
    interval: Math.max(2000, root.refreshIntervalSec * 1000)
    running: root.processesActive; repeat: true
    onTriggered: root.refreshProcesses()
  }

  Component.onCompleted: cpuTempProbe.running = true
}
