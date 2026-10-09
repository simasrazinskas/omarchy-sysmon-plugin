import QtQuick
import qs.Commons
import qs.Ui
import "../components"
import "../Model.js" as Model
import "../Metrics.js" as Metrics

// Current values and recent trends at a glance.
Scroller {
  id: root

  required property var service
  required property var theme
  required property var host

  spacing: Style.space(10)

  readonly property int range: host.historySeconds
  readonly property string tempUnit: host.options.tempUnit
  readonly property var gpu: service.gpu
  readonly property var chartSeries: Metrics.series(service.history, host.chartMetric, range, service.lastSample)
  readonly property var summary: Metrics.stats(chartSeries)

  function series(key) { return Metrics.series(service.history, key, range, service.lastSample) }

  Row {
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: [{ seconds: 60, label: "1 min" }, { seconds: 300, label: "5 min" }, { seconds: 900, label: "15 min" }]

      ThemeButton {
        required property var modelData
        theme: root.theme
        text: modelData.label
        selected: root.range === modelData.seconds
        fontSize: Style.font.caption
        horizontalPadding: Style.space(10)
        verticalPadding: Style.space(4)
        tooltipText: "History window · collected while the shell is running"
        onClicked: root.host.persistSetting("historyRange", modelData.seconds / 60 + "m")
      }
    }
  }

  Grid {
    width: parent.width
    columns: 2
    spacing: Style.space(8)

    MetricCard {
      width: (parent.width - parent.spacing) / 2
      theme: root.theme
      title: "Processor"
      value: Metrics.percent(root.service.cpu)
      detail: (Model.formatTemp(root.service.cpuTemp, root.tempUnit) || "—") + "  ·  " + root.service.coreLoads.length + " threads"
      points: root.series("cpu")
      endTime: root.service.lastSample
      seconds: root.range
      tint: root.theme.tone(root.service.cpu, "percent")
    }

    MetricCard {
      width: (parent.width - parent.spacing) / 2
      theme: root.theme
      title: "Memory"
      value: root.service.mem ? Metrics.percent(root.service.mem.percent) : "—"
      detail: root.service.mem ? Metrics.bytes(root.service.mem.used) + " / " + Metrics.bytes(root.service.mem.total) : "Waiting for memory readings"
      points: root.series("ram")
      endTime: root.service.lastSample
      seconds: root.range
      tint: root.theme.tone(root.service.mem ? root.service.mem.percent : null, "ram")
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Row {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [{ key: "cpu", label: "CPU" }, { key: "ram", label: "Memory" }, { key: "gpu", label: "GPU" }]

        ThemeButton {
          required property var modelData
          theme: root.theme
          text: modelData.label
          selected: root.host.chartMetric === modelData.key
          fontSize: Style.font.caption
          verticalPadding: Style.space(3)
          horizontalPadding: Style.space(8)
          onClicked: root.host.persistSetting("chartMetric", modelData.key)
        }
      }
    }

    HistoryChart {
      width: parent.width
      height: Style.space(76)
      theme: root.theme
      points: root.chartSeries
      seconds: root.range
      endTime: root.service.lastSample
      interactive: true
      emptyText: root.host.chartMetric === "gpu" && root.service.gpuVendor === "" ? "No supported GPU detected" : "No readings yet"
    }

    Reading { width: parent.width; theme: root.theme; label: root.range / 60 + " min ago"; value: "Now · 0–100%" }
    Reading {
      width: parent.width
      theme: root.theme
      label: "Average  " + Metrics.percent(root.summary.average)
      value: "Peak  " + Metrics.percent(root.summary.peak)
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Reading {
      width: parent.width
      theme: root.theme
      label: "Graphics" + (root.service.gpuVendor ? " · " + root.service.gpuVendor.toUpperCase() : "")
      value: root.gpu ? Metrics.percent(root.gpu.util) + "  ·  " + (Model.formatTemp(root.gpu.temp, root.tempUnit) || "—") : "Not detected"
    }
    Meter {
      width: parent.width
      theme: root.theme
      visible: root.gpu !== null
      value: root.gpu ? root.gpu.util : null
      tint: root.theme.tone(root.gpu ? root.gpu.util : null, "percent")
    }
    Reading {
      width: parent.width
      theme: root.theme
      label: "Network · " + (root.service.activeInterface || "no route")
      value: root.service.net ? "↓ " + Metrics.rate(root.service.net.down) + "  ↑ " + Metrics.rate(root.service.net.up)
        : root.service.interfaceMissing ? "Interface not found" : "—"
    }
    Reading {
      width: parent.width
      theme: root.theme
      label: "Storage · " + root.service.activeMount
      value: root.service.diskDetail ? Metrics.bytes(root.service.diskDetail.available) + " free" : "Unavailable"
      valueColor: root.theme.tone(root.service.disk, "disk", root.theme.foreground)
    }
    Meter {
      width: parent.width
      theme: root.theme
      value: root.service.disk
      tint: root.theme.tone(root.service.disk, "disk")
    }
  }
}
