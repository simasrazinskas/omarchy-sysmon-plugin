import QtQuick
import qs.Commons
import "../Metrics.js" as Metrics
Card {
  id: root
  property string title: ""
  property string value: "—"
  property string detail: ""
  property var points: []
  property double endTime: 0
  property int seconds: 60
  property bool warning: false
  Caption { theme: root.theme; text: root.title.toUpperCase(); width: parent.width }
  Label {
    theme: root.theme; text: root.value; width: parent.width
    font.pixelSize: Style.font.display; font.bold: true
    color: root.warning ? root.theme.urgent : root.theme.foreground
  }
  HistoryChart {
    width: parent.width; height: Style.space(32)
    theme: root.theme; points: root.points; endTime: root.endTime; seconds: root.seconds
    tint: root.warning ? root.theme.urgent : root.theme.accent
  }
  Label { theme: root.theme; text: root.detail; width: parent.width; color: root.theme.dim; font.pixelSize: Style.font.caption }
}
