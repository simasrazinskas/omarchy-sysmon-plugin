import QtQuick
import qs.Commons
import qs.Ui
import "../components"
import "../Model.js" as Model
import "../Metrics.js" as Metrics
Scroller {
  id: root
  required property var service
  required property var theme
  required property var host
  spacing: Style.space(10)
  readonly property var health: Metrics.health(service.state, service.pressures)
  readonly property int range: host.historySeconds
  readonly property var cpuSeries: Metrics.series(service.history, 'cpu', range, service.lastSample)
  readonly property var chartSeries: Metrics.series(service.history, host.chartMetric, range, service.lastSample)
  readonly property var summary: Metrics.stats(chartSeries)
  function move(dy) { scrollBy(dy * Style.space(48)) }

  Item {
    width: parent.width; implicitHeight: hero.implicitHeight
    Column {
      id: hero; width: parent.width; spacing: Style.space(5)
      Caption { theme: root.theme; text: "AT A GLANCE" }
      Label {
        theme: root.theme; width: parent.width
        text: root.health.title; font.pixelSize: Style.font.display; font.bold: true
        color: root.health.issues.length ? root.theme.urgent : root.theme.foreground
      }
      Label {
        theme: root.theme; width: parent.width; wrapMode: Text.WordWrap
        text: root.health.issues.length ? root.health.issues.join(' · ') : "No active resource warnings."
        color: root.theme.dim
      }
    }
  }
  Row {
    width: parent.width; spacing: Style.space(6)
    Repeater {
      model: [{seconds: 60, label: '1 min'}, {seconds: 300, label: '5 min'}, {seconds: 900, label: '15 min'}]
      Button {
        required property var modelData
        text: modelData.label; selected: root.range === modelData.seconds
        fontFamily: root.theme.fontFamily; fontSize: Style.font.caption
        foreground: root.theme.foreground; accent: root.theme.accent
        horizontalPadding: Style.space(10); verticalPadding: Style.space(4)
        tooltipText: 'History window · collected while the shell is running'
        onClicked: root.host.persistSetting('historyRange', modelData.seconds / 60 + 'm')
      }
    }
  }
  Grid {
    width: parent.width; columns: 2; spacing: Style.space(8)
    MetricCard {
      width: (parent.width - parent.spacing) / 2; theme: root.theme
      title: 'Processor'; value: Metrics.percent(root.service.cpu)
      detail: (Model.formatTemp(root.service.cpuTemp, root.host.options.tempUnit) || '—') + '  ·  ' + root.service.coreLoads.length + ' threads'
      points: root.cpuSeries; endTime: root.service.lastSample; seconds: root.range
      warning: root.service.cpu !== null && root.service.cpu >= 90
    }
    MetricCard {
      width: (parent.width - parent.spacing) / 2; theme: root.theme
      title: 'Memory'; value: root.service.mem ? Metrics.percent(root.service.mem.percent) : '—'
      detail: root.service.mem ? Metrics.bytes(root.service.mem.used) + ' / ' + Metrics.bytes(root.service.mem.total) : 'Waiting for memory readings'
      points: Metrics.series(root.service.history, 'ram', root.range, root.service.lastSample); endTime: root.service.lastSample; seconds: root.range
      warning: root.service.mem !== null && root.service.mem.percent >= 90
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Row {
      width: parent.width; spacing: Style.space(4)
      Repeater {
        model: [{key: 'cpu', label: 'CPU'}, {key: 'ram', label: 'Memory'}, {key: 'gpu', label: 'GPU'}]
        Button {
          required property var modelData
          text: modelData.label; selected: root.host.chartMetric === modelData.key
          foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily
          fontSize: Style.font.caption; verticalPadding: Style.space(3); horizontalPadding: Style.space(8)
          onClicked: root.host.persistSetting('chartMetric', modelData.key)
        }
      }
    }
    HistoryChart {
      width: parent.width; height: Style.space(76); theme: root.theme
      points: root.chartSeries; seconds: root.range; endTime: root.service.lastSample; interactive: true
    }
    Reading { width: parent.width; theme: root.theme; label: root.range / 60 + ' min ago'; value: 'Now · 0–100%' }
    Reading {
      width: parent.width; theme: root.theme; label: 'Average  ' + Metrics.percent(root.summary.average)
      value: 'Peak  ' + Metrics.percent(root.summary.peak)
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Reading {
      width: parent.width; theme: root.theme; label: 'Graphics' + (root.service.gpuVendor ? ' · ' + root.service.gpuVendor.toUpperCase() : '')
      value: root.service.state.gpu ? Metrics.percent(root.service.state.gpu.util) + '  /  ' + (Model.formatTemp(root.service.state.gpu.temp, root.host.options.tempUnit) || '—') : 'Unavailable'
    }
    Meter { width: parent.width; theme: root.theme; value: root.service.state.gpu ? root.service.state.gpu.util : null }
    Reading {
      width: parent.width; theme: root.theme; label: 'Network · ' + (root.service.activeInterface || 'no route')
      value: root.service.net ? '↓ ' + Model.formatBytes(root.service.net.down) + '/s  ↑ ' + Model.formatBytes(root.service.net.up) + '/s' : '—'
    }
    Reading {
      width: parent.width; theme: root.theme; label: 'Storage · ' + root.service.activeMount
      value: root.service.diskDetail ? Metrics.bytes(root.service.diskDetail.available) + ' free' : 'Unavailable'
      valueColor: root.service.disk !== null && root.service.disk >= 90 ? root.theme.urgent : root.theme.foreground
    }
    Meter { width: parent.width; theme: root.theme; value: root.service.disk; tint: root.service.disk >= 90 ? root.theme.urgent : root.theme.accent }
  }
}
