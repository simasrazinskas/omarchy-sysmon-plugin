import QtQuick
import qs.Commons
import qs.Ui

// Omarchy's Button, coloured from the dashboard theme.
Button {
  required property var theme
  foreground: theme.foreground
  accent: theme.accent
  fontFamily: theme.fontFamily
}
