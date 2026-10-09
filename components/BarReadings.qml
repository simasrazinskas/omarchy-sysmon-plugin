import QtQuick
import qs.Commons
import "../Model.js" as Model

// The readings drawn in the bar: one icon + value per chip on a horizontal
// bar, stacked bare values on a vertical one. Values reserve a fixed number
// of character widths so a reading that grows a digit (9% -> 10%) cannot
// shove neighbouring widgets sideways.
Item {
  id: root

  property var chips: []
  property string barMode: "full"
  property bool vertical: false
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property var mode: Model.barMode(barMode)
  // Vertical bars never show icons: 28px has no room for icon and value.
  readonly property bool showIcons: mode.layout === "full" && !vertical
  // Minimal collapses to one icon; so does a bar with nothing to show yet,
  // which keeps a click target while readings initialise or when every chip
  // is switched off.
  readonly property bool minimal: mode.layout === "minimal" || chips.length === 0

  implicitWidth: vertical ? stack.implicitWidth : row.implicitWidth
  implicitHeight: vertical ? stack.implicitHeight : row.implicitHeight

  function chipColor(chip) {
    var tint = Model.chipTint(chip, root.barMode)
    if (!tint) return root.foreground
    var hue = tint.hue === "urgent" ? root.urgent : tint.hue
    return Qt.tint(root.foreground, Qt.alpha(hue, tint.strength))
  }

  readonly property font barFont: Qt.font({ family: fontFamily, pixelSize: Style.font.body })

  // Measures the bar font so a value can reserve a whole number of character
  // widths. Pinning in pixels is what lets the icon sit a few pixels from its
  // value instead of a full monospace cell away.
  FontMetrics {
    id: metrics
    font: root.barFont
  }

  Column {
    id: stack
    anchors.centerIn: parent
    visible: root.vertical

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.minimal
      text: Model.ICONS.cpu
      color: root.foreground
      font: root.barFont
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.minimal ? [] : root.chips

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        text: modelData.value
        color: root.chipColor(modelData)
        font: root.barFont
        renderType: Text.NativeRendering
      }
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    visible: !root.vertical
    spacing: Style.space(7)

    Text {
      visible: root.minimal
      text: Model.ICONS.cpu
      color: root.foreground
      font: root.barFont
      renderType: Text.NativeRendering
    }

    Repeater {
      model: root.minimal ? [] : root.chips

      Row {
        // Keep icons close to their pinned-width readings.
        spacing: Style.space(2)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: root.showIcons
          text: modelData.icon
          color: root.chipColor(modelData)
          font: root.barFont
          renderType: Text.NativeRendering
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          // Reserve the pinned width and left-align inside it, so the value
          // always starts hard against its icon and the slack ends up between
          // chips instead of inside one.
          width: Math.ceil(metrics.advanceWidth("0") * modelData.width)
          text: modelData.value
          color: root.chipColor(modelData)
          font: root.barFont
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
