import QtQuick
import qs.Commons
import qs.Ui

// Text setting that saves on Enter or focus loss, only when the value
// actually changed. Esc restores the saved value.
TextField {
  id: root

  required property var theme
  property string saved: ""

  signal committed(string value)
  signal cancelled()

  text: saved
  foreground: theme.foreground
  accent: theme.accent
  placeholderTextColor: theme.dim
  font.family: theme.fontFamily
  selectByMouse: true
  onEditingFinished: if (text.trim() !== saved) committed(text.trim())
  Keys.onEscapePressed: {
    text = saved
    focus = false
    cancelled()
  }
}
