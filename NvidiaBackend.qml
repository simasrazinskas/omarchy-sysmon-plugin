import QtQuick
import Quickshell.Io
import "Model.js" as Model

// NVIDIA GPU readings via nvidia-smi. This is the only backend the author can
// test on real hardware; see README for what that means for AMD and Intel.
Item {
  id: root

  readonly property string vendor: "nvidia"
  property bool available: false
  property bool probed: false
  property var reading: null

  // `command -v` keeps a machine with no NVIDIA driver from turning a missing
  // binary into a spawn error every tick — it exits 127 cleanly instead. The
  // timeout matters more than it looks: nvidia-smi blocks for tens of seconds
  // when the driver is mid-reset, and a Process that never exits can never be
  // re-run, which would freeze the reading until the shell restarts.
  readonly property var probeCommand: ["bash", "-c",
    "command -v nvidia-smi >/dev/null 2>&1 || exit 127\n"
    + "exec timeout 5 nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits\n"]

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
      var parsed = Model.parseNvidia(String(queryStdout.text || ""))
      root.available = parsed !== null
      root.reading = parsed
    }
  }

  Component.onCompleted: refresh()
}
