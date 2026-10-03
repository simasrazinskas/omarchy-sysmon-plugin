import QtQuick
import qs.Commons
Rectangle {
  id: root
  required property var theme
  property var value: null
  property color tint: theme.accent
  implicitHeight: Style.space(4)
  radius: height / 2
  color: theme.hairline
  Rectangle {
    height: parent.height
    radius: parent.radius
    width: parent.width * Math.max(0, Math.min(100, root.value === null ? 0 : root.value)) / 100
    color: root.tint
    Behavior on width { NumberAnimation { duration: 200 } }
  }
}
