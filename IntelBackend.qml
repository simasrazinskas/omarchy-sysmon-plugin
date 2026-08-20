import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Intel GPU readings from sysfs.
//
// UNTESTED, and expected to stay unavailable on most Intel hardware: i915 has
// never exposed a utilisation percentage in sysfs — that number lives behind
// the i915 PMU (perf events), which needs elevated privileges or a helper this
// plugin deliberately does not ship. Newer `xe`-driver cards do publish
// gpu_busy_percent, so this backend reads it where it exists and reports
// nothing where it does not, rather than pretending to a reading it cannot
// take. Temperature alone is not enough to activate the backend, because a
// GPU chip with no utilisation is not what the widget promises.
Item {
  id: root

  readonly property string vendor: "intel"
  property bool available: false
  property bool probed: false
  property var reading: null

  readonly property var probeCommand: ["bash", "-c",
    "rd() { [ -r \"$1\" ] && cat \"$1\" 2>/dev/null || echo; }\n"
    + "for dev in /sys/class/drm/card*/device; do\n"
    + "  [ \"$(cat \"$dev/vendor\" 2>/dev/null)\" = \"0x8086\" ] || continue\n"
    + "  [ -r \"$dev/gpu_busy_percent\" ] || continue\n"
    + "  rd \"$dev/gpu_busy_percent\"\n"
    + "  rd \"$dev/mem_info_vram_used\"\n"
    + "  rd \"$dev/mem_info_vram_total\"\n"
    + "  for hw in \"$dev\"/hwmon/hwmon*; do\n"
    + "    if [ -r \"$hw/temp1_input\" ]; then cat \"$hw/temp1_input\"; exit 0; fi\n"
    + "  done\n"
    + "  echo\n"
    + "  exit 0\n"
    + "done\n"
    + "exit 127\n"]

  function refresh() {
    if (queryProcess.running) return
    queryProcess.running = true
  }

  Process {
    id: queryProcess
    command: root.probeCommand
    stdout: StdioCollector {
      id: queryStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.probed = true
      if (exitCode !== 0) {
        root.available = false
        root.reading = null
        return
      }
      var lines = String(queryStdout.text || "").split("\n")
      var parsed = Model.parseSysfsGpu(lines[0], lines[1], lines[2], lines[3])
      root.available = parsed !== null
      root.reading = parsed
    }
  }

  Component.onCompleted: refresh()
}
