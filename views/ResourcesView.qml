import QtQuick
import qs.Commons
import "../components"
import "../Model.js" as Model
import "../Metrics.js" as Metrics
Scroller {
  id: root
  required property var service
  required property var theme
  required property var host
  spacing: Style.space(12)
  function move(dy) { scrollBy(dy * Style.space(48)) }
  Card {
    width: parent.width; theme: root.theme
    Caption { width: parent.width; theme: root.theme; text: 'PROCESSOR · ' + root.service.coreLoads.length + ' LOGICAL CORES' }
    Label { width: parent.width; theme: root.theme; text: root.service.cpuName || 'Processor'; wrapMode: Text.WordWrap }
    Grid {
      width: parent.width; columns: Math.max(2, Math.floor(width / Style.space(100))); spacing: Style.space(8)
      Repeater {
        model: root.service.coreLoads
        Column {
          required property var modelData
          width: (parent.width - parent.spacing * (parent.columns - 1)) / parent.columns
          spacing: Style.space(5)
          Reading { width: parent.width; theme: root.theme; label: '#' + modelData.name; value: Model.formatPercent(modelData.value) || '—' }
          Meter { width: parent.width; theme: root.theme; value: modelData.value; tint: modelData.value >= 90 ? root.theme.urgent : root.theme.accent }
        }
      }
    }
    Reading { width: parent.width; theme: root.theme; label: 'Package temperature'; value: (Model.formatTemp(root.service.cpuTemp, root.host.options.tempUnit) || '—') + (root.service.cpuTemp !== null ? root.host.options.tempUnit : '') }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'MEMORY & SWAP' }
    Reading { width: parent.width; theme: root.theme; label: 'In use'; value: root.service.mem ? Metrics.bytes(root.service.mem.used) + ' / ' + Metrics.bytes(root.service.mem.total) : '—' }
    Meter { width: parent.width; theme: root.theme; value: root.service.mem ? root.service.mem.percent : null }
    Reading { width: parent.width; theme: root.theme; label: 'Available to applications'; value: Metrics.bytes(root.service.memoryDetail ? root.service.memoryDetail.available : null) }
    Reading { width: parent.width; theme: root.theme; label: 'Cache (includes reclaimable slab)'; value: Metrics.bytes(root.service.memoryDetail ? root.service.memoryDetail.cache : null) }
    Reading { width: parent.width; theme: root.theme; label: 'Swap'; value: !root.service.memoryDetail ? '—' : root.service.memoryDetail.swapTotal === 0 ? 'Not configured' : Metrics.bytes(root.service.memoryDetail.swapUsed) + ' / ' + Metrics.bytes(root.service.memoryDetail.swapTotal) }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'RESOURCE PRESSURE' }
    Label { width: parent.width; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap; text: 'Time with tasks waiting for resources. Lower is better.' }
    Repeater {
      model: [{label: 'CPU', threshold: 20, value: root.service.pressureCpu}, {label: 'Memory', threshold: 10, value: root.service.pressureMemory}, {label: 'I/O', threshold: 10, value: root.service.pressureIo}]
      Reading {
        required property var modelData
        width: parent.width; theme: root.theme; label: modelData.label + ' · last 10 seconds'
        value: modelData.value ? Metrics.percent(modelData.value.avg10) : 'Not supported'
        valueColor: modelData.value && modelData.value.avg10 >= modelData.threshold ? root.theme.urgent : root.theme.foreground
      }
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'GRAPHICS · ' + (root.service.gpuVendor || 'UNAVAILABLE').toUpperCase() }
    Reading { width: parent.width; theme: root.theme; label: 'Utilization'; value: Metrics.percent(root.service.state.gpu ? root.service.state.gpu.util : null) }
    HistoryChart { width: parent.width; height: Style.space(56); theme: root.theme; points: Metrics.series(root.service.history, 'gpu', root.host.historySeconds, root.service.lastSample); endTime: root.service.lastSample; seconds: root.host.historySeconds; interactive: true }
    Reading { width: parent.width; theme: root.theme; label: 'Video memory'; value: root.service.state.gpu ? Metrics.bytes(root.service.state.gpu.vramUsed) + ' / ' + Metrics.bytes(root.service.state.gpu.vramTotal) : 'Unavailable' }
    Reading { width: parent.width; theme: root.theme; label: 'Temperature'; value: (Model.formatTemp(root.service.state.gpu ? root.service.state.gpu.temp : null, root.host.options.tempUnit) || '—') }
  }
}
