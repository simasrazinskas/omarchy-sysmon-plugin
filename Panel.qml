import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// System Monitor bar widget: machine vitals in the bar, detail panel on click.
// The panel is both the readout and the control surface — every chip can be
// switched on or off there, writing the same settings keys the plugin settings
// screen uses, so the two can never drift apart.
Panel {
  id: root
  moduleName: "io.github.simasrazinskas.sysmon"
  ipcTarget: "io.github.simasrazinskas.sysmon"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Alpha-dimmed rather than darkened: darkening a dark foreground on a light
  // theme would raise contrast instead of lowering it.
  readonly property color dim: Qt.alpha(foreground, 0.6)

  readonly property var options: ({
    showCpu: setting("showCpu", true) === true,
    showRam: setting("showRam", true) === true,
    showCpuTemp: setting("showCpuTemp", true) === true,
    showGpu: setting("showGpu", true) === true,
    showGpuTemp: setting("showGpuTemp", true) === true,
    showVram: setting("showVram", false) === true,
    showNet: setting("showNet", true) === true,
    showDisk: setting("showDisk", true) === true,
    ramDisplay: String(setting("ramDisplay", "used")),
    tempUnit: String(setting("tempUnit", "C")).toUpperCase() === "F" ? "F" : "C"
  })

  readonly property string label: root.vertical
    ? Model.barTextVertical(service.state, options)
    : Model.barText(service.state, options)

  readonly property var rows: Model.detailRows(service.state, options)
  readonly property bool vertical: bar ? bar.vertical : false

  // Mirrors the clock's format cycling and the t212 widget: apply locally for
  // an instant change, then write the same value back through shell.json so it
  // survives a shell restart. The write is debounced so flicking several
  // toggles lands as one shell.json update of the final state — intermediate
  // writes would otherwise race the bar's settings re-injection.
  property var _pendingEntry: null

  function persistSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value
    root.settings = entry
    _pendingEntry = entry
    persistTimer.restart()
  }

  Timer {
    id: persistTimer
    interval: 400
    repeat: false
    onTriggered: {
      if (!root._pendingEntry) return
      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
        root.bar.shell.updateEntryInline(root.moduleName, root._pendingEntry)
      root._pendingEntry = null
    }
  }

  Service {
    id: service
    settings: root.settings
  }

  // Nothing to show until the first samples land — CPU needs two ticks for a
  // delta — and nothing to show if every chip is off. But the button has to
  // stay clickable in that second case, or switching everything off would
  // remove the only way back to the panel that turns them on again.
  readonly property bool everythingOff: {
    for (var i = 0; i < Model.TOGGLES.length; i++) {
      if (options[Model.TOGGLES[i].key]) return false
    }
    return true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : barLabel.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? barLabel.implicitHeight + scaledVerticalPadding * 2 : -1
    tooltipText: Model.tooltipText(service.state, root.options)
    useActiveColor: false
    onPressed: function(buttonCode) { root.toggle() }

    Text {
      id: barLabel
      anchors.centerIn: parent
      // A widget with every chip switched off still needs a hit target, so it
      // falls back to its own icon rather than collapsing to nothing.
      text: root.label !== "" ? root.label : (root.everythingOff ? Model.ICONS.cpu : "")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
      renderType: Text.NativeRendering
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight + Style.space(12), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Column {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            text: "System Monitor"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            renderType: Text.NativeRendering
          }

          Text {
            visible: text !== ""
            text: service.gpuVendor !== "" ? service.gpuVendor.toUpperCase() + " GPU" : "No supported GPU detected"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }
        }

        PanelSeparator { Layout.fillWidth: true }

        PanelSectionHeader {
          text: "READINGS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // Every reading the widget has, whether or not its chip is in the bar —
        // switching a chip off hides it from the bar, not from here.
        Column {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Repeater {
            model: root.rows

            Item {
              width: parent ? parent.width : 0
              implicitHeight: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

              Text {
                id: rowLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              Text {
                id: rowValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.value
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                renderType: Text.NativeRendering
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.rows.length === 0
          text: "Taking first readings…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }

        PanelSeparator { Layout.fillWidth: true }

        PanelSectionHeader {
          text: "SHOW IN BAR"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          Layout.fillWidth: true
          spacing: Style.space(4)

          Repeater {
            model: Model.TOGGLES

            Toggle {
              width: parent ? parent.width : 0
              label: modelData.label
              checked: root.options[modelData.key] === true
              foreground: root.foreground
              fontFamily: root.fontFamily
              titleSize: Style.font.body
              onClicked: root.persistSetting(modelData.key, !checked)
            }
          }
        }
      }
    }
  }
}
