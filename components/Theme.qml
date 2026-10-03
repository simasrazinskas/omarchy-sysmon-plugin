import QtQuick
import qs.Commons

// Shared theme tokens; surfaces adapt to both light and dark themes.
QtObject {
  id: theme

  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  // Alpha-dimmed rather than darkened: darkening a dark foreground on a
  // light theme would raise contrast instead of lowering it.
  readonly property color dim: Qt.alpha(foreground, 0.6)
  readonly property color faint: Qt.alpha(foreground, 0.35)
  readonly property color hairline: Qt.alpha(foreground, 0.12)
  readonly property color surface: Qt.alpha(foreground, 0.045)
  readonly property color hover: Qt.alpha(foreground, 0.08)

}
