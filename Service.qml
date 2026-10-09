import QtQuick
import Quickshell.Io
import "Model.js" as Model
import "Metrics.js" as Metrics

// Data layer: samples the machine and exposes the readings the bar and the
// dashboard render.
//
// Everything the kernel publishes as a file is read in-process with FileView —
// /proc and /sys are cheap, and forking a helper twice a second to read data
// that is already a file would cost more than the readings are worth. Only the
// GPU and disk use slower subprocesses; process scans run only in their view.
Item {
  id: root

  property var settings: ({})
  property bool processesActive: false

  // ------------------------------------------------------------- settings

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 2, 1, 30)
  readonly property string configuredInterface: String(setting("networkInterface", "")).trim()
  readonly property string configuredMount: String(setting("diskMountpoint", "")).trim()

  // Auto-detected values, used whenever the matching setting is blank. The
  // route is re-read periodically so a laptop moving between wifi and ethernet
  // follows along without anyone editing settings.
  property string detectedInterface: ""
  readonly property string activeInterface: configuredInterface !== "" ? configuredInterface : detectedInterface
  readonly property string activeMount: configuredMount !== "" ? configuredMount : "/"

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  // ------------------------------------------------------------- readings

  property var cpu: null
  property var coreLoads: []
  property var cpuTemp: null
  property string cpuTempPath: ""
  // Total/used/percent plus available, cache and swap; see Metrics.memory.
  property var mem: null
  property var net: null
  property var networkTotals: null
  // A named interface that /proc/net/dev does not list — usually a typo in
  // settings, or a USB adapter that is unplugged.
  property bool interfaceMissing: false
  property var disk: null
  property var diskDetail: null
  property var loadAverage: null
  property var uptime: null
  property var pressureCpu: null
  property var pressureMemory: null
  property var pressureIo: null
  property string cpuName: ""
  property string hostname: ""

  readonly property var gpu: gpuController.reading
  // Which vendor backend won, so the panel can say what it is reading from —
  // empty when no GPU could be read at all.
  readonly property string gpuVendor: gpuController.available ? gpuController.vendor : ""

  // The bar's view of the readings; Model.buildChips and the tooltip read it.
  readonly property var state: ({
    cpu: cpu,
    mem: mem,
    cpuTemp: cpuTemp,
    gpu: gpu,
    net: net,
    disk: disk,
    netInterface: activeInterface,
    diskMount: activeMount
  })

  // Timestamped samples for the charts; see Metrics.append for the bounds.
  property var history: []
  property double lastSample: 0

  property var processes: []
  property string processError: ""
  property double processUpdated: 0

  // Previous cumulative counters. Network keeps the time it was read at so a
  // rate is computed against the interval that actually elapsed rather than
  // the interval that was scheduled.
  property var _prevCpuTimes: null
  property var _prevNet: null
  property double _prevNetMs: 0
  property var _prevProcesses: null

  // --------------------------------------------------------------- update

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

  // Called once per CPU sample, which is what paces the history.
  function record() {
    var now = Date.now()
    lastSample = now
    history = Metrics.append(history, {
      time: now, cpu: cpu, ram: mem ? mem.percent : null, gpu: gpu ? gpu.util : null,
      down: net ? net.down : null, up: net ? net.up : null
    })
  }

  function refreshDisk() {
    if (diskProcess.running || activeMount === "") return
    diskProcess.command = ["bash", "-c", "export LC_ALL=C; exec timeout 5 df -Pk -- \"$1\"", "sysmon", activeMount]
    diskProcess.requestedMount = activeMount
    diskProcess.running = true
  }

  function refreshRoute() {
    // Nothing to detect while the user has named an interface explicitly.
    if (routeProcess.running || configuredInterface !== "") return
    routeProcess.running = true
  }

  function refreshProcesses() {
    if (processesActive && !processReader.running) processReader.running = true
  }

  function resetProcesses(error) {
    processes = []
    _prevProcesses = null
    processError = error || ""
  }

  // Process rows are only worth their memory while someone is looking at them.
  onProcessesActiveChanged: {
    resetProcesses()
    if (processesActive) refreshProcesses()
  }

  // A changed interface invalidates the counters the old one accumulated;
  // keeping them would report the difference between two unrelated
  // interfaces as one huge burst of traffic.
  onActiveInterfaceChanged: {
    _prevNet = null
    _prevNetMs = 0
    net = null
    networkTotals = null
    interfaceMissing = false
    // Never label traffic from the old interface as belonging to the new one.
    history = history.map(function(sample) {
      var copy = Object.assign({}, sample)
      copy.down = null
      copy.up = null
      return copy
    })
  }

  onActiveMountChanged: {
    disk = null
    diskDetail = null
    refreshDisk()
  }

  // ---------------------------------------------------------- procfs reads

  FileView {
    id: cpuStatFile
    path: "/proc/stat"
    printErrors: false
    onLoaded: {
      var times = Metrics.cpuTimes(text())
      var previous = root._prevCpuTimes
      root.cpu = Metrics.busy(previous ? previous.cpu : null, times.cpu || null)
      root.coreLoads = Metrics.coreUsage(previous, times)
      root._prevCpuTimes = times.cpu ? times : null
      root.record()
    }
    onLoadFailed: {
      root.cpu = null
      root.coreLoads = []
      root._prevCpuTimes = null
      root.record()
    }
  }

  FileView {
    id: memInfoFile
    path: "/proc/meminfo"
    printErrors: false
    onLoaded: root.mem = Metrics.memory(text())
    onLoadFailed: root.mem = null
  }

  FileView {
    id: netDevFile
    path: "/proc/net/dev"
    printErrors: false
    onLoaded: {
      var counters = Model.parseNetDev(text(), root.activeInterface)
      var now = Date.now()
      root.networkTotals = counters
      root.interfaceMissing = counters === null
      root.net = counters ? Model.netRates(root._prevNet, counters, now - root._prevNetMs) : null
      root._prevNet = counters
      root._prevNetMs = now
    }
    onLoadFailed: {
      root.net = null
      root.networkTotals = null
      root._prevNet = null
    }
  }

  FileView {
    id: cpuTempFile
    path: root.cpuTempPath
    printErrors: false
    onLoaded: root.cpuTemp = Model.parseTemp(text())
    onLoadFailed: root.cpuTemp = null
  }

  FileView {
    id: loadFile
    path: "/proc/loadavg"
    printErrors: false
    onLoaded: root.loadAverage = Metrics.load(text())
    onLoadFailed: root.loadAverage = null
  }

  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    printErrors: false
    onLoaded: root.uptime = Metrics.uptime(text())
    onLoadFailed: root.uptime = null
  }

  FileView {
    id: pressureCpuFile
    path: "/proc/pressure/cpu"
    printErrors: false
    onLoaded: root.pressureCpu = Metrics.pressure(text())
    onLoadFailed: root.pressureCpu = null
  }

  FileView {
    id: pressureMemoryFile
    path: "/proc/pressure/memory"
    printErrors: false
    onLoaded: root.pressureMemory = Metrics.pressure(text())
    onLoadFailed: root.pressureMemory = null
  }

  FileView {
    id: pressureIoFile
    path: "/proc/pressure/io"
    printErrors: false
    onLoaded: root.pressureIo = Metrics.pressure(text())
    onLoadFailed: root.pressureIo = null
  }

  // Read once: neither changes while the shell runs.
  FileView {
    path: "/proc/cpuinfo"
    printErrors: false
    onLoaded: {
      var m = text().match(/(?:model name|Hardware)\s*:\s*(.+)/)
      root.cpuName = m ? m[1].trim() : ""
    }
  }

  FileView {
    path: "/proc/sys/kernel/hostname"
    printErrors: false
    onLoaded: root.hostname = text().trim()
  }

  // ------------------------------------------------------------ discovery

  // hwmon numbering is assigned in probe order and is not stable across boots,
  // so the CPU sensor has to be found by name rather than hardcoded. Prefer a
  // package-wide label (Intel's "Package id 0", AMD's Tctl/Tdie) over a single
  // core, which would report whichever core happens to be busy. Drivers are
  // tried in priority order rather than hwmon order: acpitz is often a static
  // ACPI zone (a constant ~28°C) and must only be used when nothing else exists.
  Process {
    id: cpuTempProbe
    command: ["bash", "-c",
      "for driver in coretemp k10temp zenpower cpu_thermal acpitz; do\n"
      + "  for hw in /sys/class/hwmon/hwmon*; do\n"
      + "    [ \"$(cat \"$hw/name\" 2>/dev/null)\" = \"$driver\" ] || continue\n"
      + "    for label in \"$hw\"/temp*_label; do\n"
      + "      [ -r \"$label\" ] || continue\n"
      + "      case \"$(cat \"$label\" 2>/dev/null)\" in\n"
      + "        Package\\ id*|Tctl|Tdie|CPU*) echo \"${label%_label}_input\"; exit 0 ;;\n"
      + "      esac\n"
      + "    done\n"
      + "    [ -r \"$hw/temp1_input\" ] && { echo \"$hw/temp1_input\"; exit 0; }\n"
      + "  done\n"
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

  Process {
    id: diskProcess
    property string requestedMount: ""
    stdout: StdioCollector {
      id: diskStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      // The mountpoint changed while df ran; measure the new one instead.
      if (requestedMount !== root.activeMount) { Qt.callLater(root.refreshDisk); return }
      root.diskDetail = exitCode === 0 ? Metrics.disk(String(diskStdout.text || "")) : null
      root.disk = root.diskDetail ? root.diskDetail.percent : null
    }
  }

  Process {
    id: processReader
    command: ["timeout", "5", "python3",
      decodeURIComponent(Qt.resolvedUrl("scripts/processes.py").toString().replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      id: processOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (!root.processesActive) return
      if (exitCode !== 0) {
        root.resetProcesses("Process readings unavailable. Check that Python 3 is installed.")
        return
      }
      try {
        var snapshot = JSON.parse(processOutput.text)
        root.processes = Metrics.processRates(root._prevProcesses, snapshot)
        root._prevProcesses = snapshot
        root.processUpdated = Date.now()
        root.processError = ""
      } catch (e) {
        root.resetProcesses("Could not read processes.")
      }
    }
  }

  GpuController {
    id: gpuController
    intervalMs: Math.max(5000, root.refreshIntervalSec * 1000)
  }

  // --------------------------------------------------------------- timers

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

  // Route changes and a sensor that appears late (a module loaded after the
  // shell started) are both rare; checking twice a minute is plenty.
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshRoute()
      if (root.cpuTemp === null && !cpuTempProbe.running) cpuTempProbe.running = true
    }
  }

  Timer {
    interval: Math.max(2000, root.refreshIntervalSec * 1000)
    running: root.processesActive
    repeat: true
    onTriggered: root.refreshProcesses()
  }
}
