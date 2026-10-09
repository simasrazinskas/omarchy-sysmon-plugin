import QtQuick
import QtQuick.Controls
import qs.Commons

// Vertical scroll container for a tab's content. `content` children go in a
// Column the full width of the view, so cards line up with the tab row; the
// scrollbar is transient and overlays the edge only while scrolling.
Flickable {
  id: root

  default property alias content: column.data
  property alias spacing: column.spacing

  contentWidth: width
  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  interactive: contentHeight > height
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  // j/k and the arrow keys step by a few lines of content.
  function move(dy) {
    contentY = Math.max(0, Math.min(Math.max(0, contentHeight - height), contentY + dy * Style.space(48)))
  }

  Column {
    id: column
    width: root.width
  }
}
