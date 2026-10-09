import QtQuick
import qs.Commons
import "../components"
import "../Model.js" as Model
import "../Metrics.js" as Metrics

// Why the machine is busy: per-core load, memory composition, stall
// pressure and the GPU.
Scroller {
  id: root

  required property var service
  required property var theme
  required property var host

  spacing: Style.space(12)

  readonly property string tempUnit: host.options.tempUnit
  readonly property var mem: service.mem
  readonly property var gpu: service.gpu

  function swapText() {
    if (!mem || mem.swapTotal === null) return "—"
    if (mem.swapTotal === 0) return "Not configured"
    return Metrics.bytes(mem.swapUsed) + " / " + Metrics.bytes(mem.swapTotal)
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { width: parent.width; theme: root.theme; text: "PROCESSOR · " + root.service.coreLoads.length + " LOGICAL CORES" }
    Label { width: parent.width; theme: root.theme; text: root.service.cpuName || "Processor"; wrapMode: Text.WordWrap }

    Grid {
      id: cores
      width: parent.width
      columns: Math.max(2, Math.floor(width / Style.space(100)))
      spacing: Style.space(8)

      Repeater {
        model: root.service.coreLoads

        Column {
          required property var modelData
          width: (cores.width - cores.spacing * (cores.columns - 1)) / cores.columns
          spacing: Style.space(5)

          Reading { width: parent.width; theme: root.theme; label: "#" + modelData.name; value: Model.formatPercent(modelData.value) || "—" }
          Meter { width: parent.width; theme: root.theme; value: modelData.value; tint: root.theme.tone(modelData.value, "percent") }
        }
      }
    }

    Reading {
      width: parent.width
      theme: root.theme
      label: "Package temperature"
      value: root.service.cpuTemp !== null ? Model.formatTemp(root.service.cpuTemp, root.tempUnit) + root.tempUnit : "—"
      valueColor: root.theme.tone(root.service.cpuTemp, "temp", root.theme.foreground)
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { theme: root.theme; text: "MEMORY & SWAP" }
    Reading { width: parent.width; theme: root.theme; label: "In use"; value: root.mem ? Metrics.bytes(root.mem.used) + " / " + Metrics.bytes(root.mem.total) : "—" }
    Meter { width: parent.width; theme: root.theme; value: root.mem ? root.mem.percent : null; tint: root.theme.tone(root.mem ? root.mem.percent : null, "ram") }
    Reading { width: parent.width; theme: root.theme; label: "Available to applications"; value: Metrics.bytes(root.mem ? root.mem.available : null) }
    Reading { width: parent.width; theme: root.theme; label: "Cache (includes reclaimable slab)"; value: Metrics.bytes(root.mem ? root.mem.cache : null) }
    Reading { width: parent.width; theme: root.theme; label: "Swap"; value: root.swapText() }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { theme: root.theme; text: "RESOURCE PRESSURE" }
    Label { width: parent.width; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap; text: "Time with tasks waiting for resources. Lower is better." }

    Repeater {
      model: [
        { label: "CPU", threshold: 20, value: root.service.pressureCpu },
        { label: "Memory", threshold: 10, value: root.service.pressureMemory },
        { label: "I/O", threshold: 10, value: root.service.pressureIo }
      ]

      Reading {
        required property var modelData
        width: parent.width
        theme: root.theme
        label: modelData.label + " · last 10 seconds"
        value: modelData.value ? Metrics.percent(modelData.value.avg10) : "Not supported"
        valueColor: modelData.value && modelData.value.avg10 >= modelData.threshold ? root.theme.urgent : root.theme.foreground
      }
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { theme: root.theme; text: "GRAPHICS · " + (root.service.gpuVendor || "not detected").toUpperCase() }

    Label {
      width: parent.width
      theme: root.theme
      visible: root.service.gpuVendor === ""
      color: root.theme.dim
      wrapMode: Text.WordWrap
      text: "No readable GPU. NVIDIA needs nvidia-smi; AMD and Intel need a driver that publishes gpu_busy_percent."
    }

    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: root.service.gpuVendor !== ""

      Reading { width: parent.width; theme: root.theme; label: "Utilization"; value: Metrics.percent(root.gpu ? root.gpu.util : null) }
      HistoryChart {
        width: parent.width
        height: Style.space(56)
        theme: root.theme
        points: Metrics.series(root.service.history, "gpu", root.host.historySeconds, root.service.lastSample)
        endTime: root.service.lastSample
        seconds: root.host.historySeconds
        interactive: true
      }
      Reading {
        width: parent.width
        theme: root.theme
        label: "Video memory"
        value: root.gpu && root.gpu.vramTotal ? Metrics.bytes(root.gpu.vramUsed) + " / " + Metrics.bytes(root.gpu.vramTotal) : "—"
      }
      Reading {
        width: parent.width
        theme: root.theme
        label: "Temperature"
        value: root.gpu && root.gpu.temp !== null ? Model.formatTemp(root.gpu.temp, root.tempUnit) + root.tempUnit : "—"
        valueColor: root.theme.tone(root.gpu ? root.gpu.temp : null, "temp", root.theme.foreground)
      }
    }
  }
}
