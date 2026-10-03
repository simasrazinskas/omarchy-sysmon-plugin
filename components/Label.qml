import QtQuick
import qs.Commons
Text {
  required property var theme
  color: theme.foreground
  font.family: theme.fontFamily
  font.pixelSize: Style.font.bodySmall
  textFormat: Text.PlainText
  elide: Text.ElideRight
}
