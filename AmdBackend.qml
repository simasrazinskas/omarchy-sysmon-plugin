import QtQuick
import Quickshell.Io
import "Model.js" as Model

// AMD GPU readings from amdgpu's sysfs interface.
//
// UNTESTED: the author has no AMD hardware. The paths below are amdgpu's
// documented sysfs surface, but nobody has run this against a real card.
// Bug reports and fixes welcome — see README.
Item {
  id: root

  readonly property string vendor: "amd"
  property bool available: false
  property bool probed: false
  property var reading: null

  // Emits four lines — busy percent, VRAM used, VRAM total, temperature in
  // millidegrees — so a driver that publishes only some of them still lines
  // up, with the missing ones arriving blank. gpu_busy_percent is the gate:
  // without it there is no utilisation to show and the backend stays quiet.
  readonly property var probeCommand: ["bash", "-c",
    "rd() { [ -r \"$1\" ] && cat \"$1\" 2>/dev/null || echo; }\n"
    + "for dev in /sys/class/drm/card*/device; do\n"
    + "  [ -r \"$dev/gpu_busy_percent\" ] || continue\n"
    + "  [ \"$(cat \"$dev/vendor\" 2>/dev/null)\" = \"0x1002\" ] || continue\n"
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
