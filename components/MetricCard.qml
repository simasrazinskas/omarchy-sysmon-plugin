import QtQuick
import qs.Commons

// Headline reading with a small trend line underneath.
Card {
  id: root

  property string title: ""
  property string value: "—"
  property string detail: ""
  property var points: []
  property double endTime: 0
  property int seconds: 60
  // Accent normally; the alert colour once the reading is high.
  property color tint: theme.accent

  readonly property bool alarming: !Qt.colorEqual(tint, theme.accent)

  Caption { width: parent.width; theme: root.theme; text: root.title.toUpperCase() }
  Label {
    width: parent.width
    theme: root.theme
    text: root.value
    font.pixelSize: Style.font.display
    font.bold: true
    color: root.alarming ? root.tint : root.theme.foreground
  }
  HistoryChart {
    width: parent.width
    height: Style.space(32)
    theme: root.theme
    points: root.points
    endTime: root.endTime
    seconds: root.seconds
    tint: root.tint
  }
  Caption { width: parent.width; theme: root.theme; text: root.detail }
}
