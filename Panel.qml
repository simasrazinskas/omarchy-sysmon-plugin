import QtQuick
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

  readonly property var rows: Model.panelRows(service.state, options)
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // A plain Column rather than a ColumnLayout: implicitHeight is then the
      // simple sum of the children, which is what the popup sizes itself from.
      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Text {
            anchors.baseline: vendorLabel.baseline
            text: "System Monitor"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
          }

          // The vendor sits on the title's line rather than under it: one row
          // saved is one row the switches below do not lose.
          Text {
            id: vendorLabel
            text: service.gpuVendor !== "" ? "· " + service.gpuVendor.toUpperCase() : "· no GPU"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }

        PanelSeparator { width: parent.width }

        // Reading and switch on one line each. Every metric is listed whether
        // or not it is in the bar, so the panel is the full readout as well as
        // the control surface.
        Repeater {
          model: root.rows

          Item {
            width: content.width
            implicitHeight: Math.max(toggleSwitch.implicitHeight, rowLabel.implicitHeight)

            Text {
              id: rowLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            Text {
              id: rowValue
              anchors.right: toggleSwitch.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.value
              // A metric with no reading — no GPU, no sensor — dims rather
              // than disappearing, so its switch still has a label.
              color: modelData.available ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
            }

            ToggleSwitch {
              id: toggleSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: modelData.enabled
              foreground: root.foreground
              onToggled: root.persistSetting(modelData.key, !modelData.enabled)
            }
          }
        }
      }
    }
  }
}
