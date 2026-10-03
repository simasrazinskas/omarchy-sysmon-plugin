import QtQuick
import qs.Commons
Item {
  id: root
  required property var theme
  property string label: ""
  property string value: "—"
  property color valueColor: theme.foreground
  implicitHeight: Math.max(name.implicitHeight, reading.implicitHeight) + Style.space(5)
  Label {
    id: name; theme: root.theme
    anchors.left: parent.left; anchors.right: reading.left; anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.label; color: root.theme.dim
  }
  Label {
    id: reading; theme: root.theme
    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width * 0.65)
    text: root.value; color: root.valueColor; horizontalAlignment: Text.AlignRight
  }
}
