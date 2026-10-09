import QtQuick
import qs.Commons
import "../components"
import "../Metrics.js" as Metrics

// Network traffic and storage capacity.
Scroller {
  id: root

  required property var service
  required property var theme
  required property var host

  spacing: Style.space(12)

  readonly property var net: service.net
  readonly property var totals: service.networkTotals
  readonly property var storage: service.diskDetail
  readonly property var down: Metrics.series(service.history, "down", host.historySeconds, service.lastSample)
  readonly property var up: Metrics.series(service.history, "up", host.historySeconds, service.lastSample)
  readonly property string interfaceLabel: service.activeInterface === "" ? "no default route"
    : service.activeInterface + (service.interfaceMissing ? " · not found" : "")

  Caption { width: parent.width; theme: root.theme; text: "NETWORK · " + root.interfaceLabel }

  Grid {
    width: parent.width
    columns: 2
    spacing: Style.space(8)

    Repeater {
      model: [
        { label: "↓ DOWNLOAD", value: root.net ? root.net.down : null, points: root.down, color: root.theme.accent },
        { label: "↑ UPLOAD", value: root.net ? root.net.up : null, points: root.up, color: root.theme.dim }
      ]

      Card {
        required property var modelData
        width: (parent.width - parent.spacing) / 2
        theme: root.theme

        Caption { width: parent.width; theme: root.theme; text: modelData.label; color: modelData.color }
        Label { width: parent.width; theme: root.theme; font.pixelSize: Style.font.display; font.bold: true; text: Metrics.rate(modelData.value) }
        Caption { width: parent.width; theme: root.theme; text: "Peak " + Metrics.rate(Metrics.stats(modelData.points).peak) }
      }
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Reading { width: parent.width; theme: root.theme; label: "TRAFFIC HISTORY"; value: root.host.historySeconds / 60 + " min · auto scale" }
    HistoryChart {
      id: traffic
      width: parent.width
      height: Style.space(135)
      theme: root.theme
      points: root.down
      secondary: root.up
      label: "↓ "
      secondaryLabel: "↑ "
      ceiling: 0
      unit: "bytes"
      seconds: root.host.historySeconds
      endTime: root.service.lastSample
      interactive: true
    }
    Item {
      width: parent.width
      implicitHeight: legend.implicitHeight

      Row {
        id: legend
        spacing: Style.space(12)
        Caption { theme: root.theme; text: "━ Download"; color: root.theme.accent }
        Caption { theme: root.theme; text: "━ Upload" }
      }
      Caption {
        anchors.right: parent.right
        theme: root.theme
        text: "Scale " + Metrics.rate(traffic.maximum)
      }
    }
    Reading { width: parent.width; theme: root.theme; label: "Received · interface lifetime"; value: Metrics.bytes(root.totals ? root.totals.rx : null) }
    Reading { width: parent.width; theme: root.theme; label: "Sent · interface lifetime"; value: Metrics.bytes(root.totals ? root.totals.tx : null) }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { width: parent.width; theme: root.theme; text: "STORAGE · " + root.service.activeMount }
    Label {
      width: parent.width
      theme: root.theme
      font.pixelSize: Style.font.display
      font.bold: true
      text: root.storage ? Metrics.bytes(root.storage.available) + " free" : "Unavailable"
    }
    Meter { width: parent.width; theme: root.theme; value: root.service.disk; tint: root.theme.tone(root.service.disk, "disk") }
    Reading { width: parent.width; theme: root.theme; label: "Used"; value: root.storage ? Metrics.bytes(root.storage.used) + " / " + Metrics.bytes(root.storage.total) + "  ·  " + root.storage.percent + "%" : "—" }
    Reading { width: parent.width; theme: root.theme; label: "Filesystem"; value: root.storage ? root.storage.device : "—" }
    Label {
      width: parent.width
      theme: root.theme
      color: root.theme.dim
      wrapMode: Text.WordWrap
      text: root.storage ? "Capacity updates every minute. Free space is what applications can use; filesystem reservations may account for the difference."
        : "Could not read " + root.service.activeMount + ". Check the mountpoint in settings."
    }
  }
}
