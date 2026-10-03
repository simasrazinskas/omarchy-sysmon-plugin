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
  readonly property var down: Metrics.series(service.history, 'down', host.historySeconds, service.lastSample)
  readonly property var up: Metrics.series(service.history, 'up', host.historySeconds, service.lastSample)
  function move(dy) { scrollBy(dy * Style.space(48)) }
  Caption { theme: root.theme; text: 'NETWORK · ' + (root.service.activeInterface || 'NO DEFAULT ROUTE') }
  Grid {
    width: parent.width; columns: 2; spacing: Style.space(8)
    Card {
      width: (parent.width - parent.spacing) / 2; theme: root.theme
      Caption { theme: root.theme; text: '↓ DOWNLOAD'; color: root.theme.accent }
      Label { width: parent.width; theme: root.theme; font.pixelSize: Style.font.display; font.bold: true; text: root.service.net ? Model.formatBytes(root.service.net.down) + '/s' : '—' }
      Caption { width: parent.width; theme: root.theme; text: 'Peak ' + Metrics.bytes(Metrics.stats(root.down).peak) + '/s' }
    }
    Card {
      width: (parent.width - parent.spacing) / 2; theme: root.theme
      Caption { theme: root.theme; text: '↑ UPLOAD' }
      Label { width: parent.width; theme: root.theme; font.pixelSize: Style.font.display; font.bold: true; text: root.service.net ? Model.formatBytes(root.service.net.up) + '/s' : '—' }
      Caption { width: parent.width; theme: root.theme; text: 'Peak ' + Metrics.bytes(Metrics.stats(root.up).peak) + '/s' }
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Reading { width: parent.width; theme: root.theme; label: 'TRAFFIC HISTORY'; value: root.host.historySeconds / 60 + ' min · auto scale' }
    HistoryChart {
      id: traffic; width: parent.width; height: Style.space(135); theme: root.theme
      points: root.down; secondary: root.up; ceiling: 0; unit: 'bytes'
      seconds: root.host.historySeconds; endTime: root.service.lastSample; interactive: true
    }
    Reading { width: parent.width; theme: root.theme; label: '↓ Accent  ·  ↑ Muted'; value: Metrics.bytes(traffic.maximum) + '/s max' }
    Reading { width: parent.width; theme: root.theme; label: 'Received · interface lifetime'; value: Metrics.bytes(root.service.networkTotals ? root.service.networkTotals.rx : null) }
    Reading { width: parent.width; theme: root.theme; label: 'Sent · interface lifetime'; value: Metrics.bytes(root.service.networkTotals ? root.service.networkTotals.tx : null) }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'STORAGE · ' + root.service.activeMount }
    Label { width: parent.width; theme: root.theme; font.pixelSize: Style.font.display; font.bold: true; text: root.service.diskDetail ? Metrics.bytes(root.service.diskDetail.available) + ' free' : 'Unavailable' }
    Meter { width: parent.width; theme: root.theme; value: root.service.disk; tint: root.service.disk >= 90 ? root.theme.urgent : root.theme.accent }
    Reading { width: parent.width; theme: root.theme; label: 'Used'; value: root.service.diskDetail ? Metrics.bytes(root.service.diskDetail.used) + ' / ' + Metrics.bytes(root.service.diskDetail.total) : '—' }
    Reading { width: parent.width; theme: root.theme; label: 'Filesystem'; value: root.service.diskDetail ? root.service.diskDetail.device : '—' }
    Label { width: parent.width; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap; text: 'Capacity updates every minute. Free space is what applications can use; filesystem reservations may account for the difference.' }
  }
}
