import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

// Native dashboard host. Bar values keep their stable, compact layout.
Panel {
  id: root
  moduleName: "io.github.simasrazinskas.sysmon"
  ipcTarget: "io.github.simasrazinskas.sysmon"

  property int tab: 0
  property bool settingsOpen: false
  readonly property var tabs: ['Overview', 'Resources', 'Activity', 'Processes']
  readonly property var dataService: service
  readonly property var panelTheme: theme
  readonly property int historySeconds: ({'1m': 60, '5m': 300, '15m': 900})[String(setting('historyRange', '1m'))] || 60
  readonly property string chartMetric: ['cpu', 'ram', 'gpu'].indexOf(String(setting('chartMetric', 'cpu'))) >= 0 ? String(setting('chartMetric', 'cpu')) : 'cpu'
  readonly property bool editorFocused: dashboard.view && dashboard.view.editorFocused === true
  function selectTab(index) { settingsOpen = false; tab = index; focusPanel() }
  function focusPanel() { keyCatcher.forceActiveFocus() }
  function stepTab(direction) { selectTab((tab + direction + tabs.length) % tabs.length) }

  Theme {
    id: theme
    foreground: root.foreground
    accent: Color.accent
    urgent: root.bar ? root.bar.urgent : Color.urgent
    fontFamily: root.fontFamily
  }

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
    tempUnit: String(setting("tempUnit", "C")).toUpperCase() === "F" ? "F" : "C",
    barMode: Model.barMode(String(setting("barMode", "full"))).key
  })

  readonly property var chips: Model.buildChips(service.state, options)
  readonly property var mode: Model.barMode(options.barMode)
  // Minimal collapses the bar to one icon; vertical bars never show icons.
  readonly property bool showIcons: mode.layout === "full" && !vertical
  readonly property bool minimal: mode.layout === "minimal" || chips.length === 0

  // Right-click steps through Model.BAR_MODES.
  function cycleBarMode() { persistSetting("barMode", Model.nextBarMode(options.barMode)) }

  function chipColor(chip) {
    var tint = Model.chipTint(chip, options.barMode)
    if (!tint) return root.foreground
    var hue = tint.hue === "urgent" ? theme.urgent : tint.hue
    return Qt.tint(root.foreground, Qt.alpha(hue, tint.strength))
  }

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
    processesActive: root.opened && !root.settingsOpen && root.tab === 3
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
    fixedHeight: root.vertical ? verticalLabel.implicitHeight + scaledVerticalPadding * 2 : -1
    tooltipText: Model.tooltipText(service.state, root.options)
      + (Model.tooltipText(service.state, root.options) ? "\n\n" : "")
      + "Style: " + root.mode.label + "  ·  right-click to change"
    useActiveColor: false
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.cycleBarMode()
      else root.toggle()
    }

    // Measures the bar font so a value can reserve a whole number of character
    // widths. Pinning in pixels is what lets the icon sit a few pixels from its
    // value instead of a full monospace cell away.
    FontMetrics {
      id: metrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    // Vertical bars have no room for icons and stack bare values instead.
    Column {
      id: verticalLabel
      anchors.centerIn: parent
      visible: root.vertical

      Text {
        visible: root.minimal
        anchors.horizontalCenter: parent.horizontalCenter
        text: Model.ICONS.cpu
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.minimal ? [] : root.chips

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: modelData.value
          color: root.chipColor(modelData)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          renderType: Text.NativeRendering
        }
      }
    }

    Row {
      id: barLabel
      anchors.centerIn: parent
      visible: !root.vertical
      spacing: Style.space(7)

      // Keeps a hit target in Minimal, while readings initialize, or when
      // every chip is off.
      Text {
        visible: root.minimal
        text: Model.ICONS.cpu
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
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
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            // Reserve the pinned width in pixels and left-align inside it, so
            // the value always starts hard against its icon and the slack ends
            // up between chips instead of inside one.
            width: Math.ceil(metrics.advanceWidth("0") * modelData.width)
            horizontalAlignment: Text.AlignLeft
            text: modelData.value
            color: root.chipColor(modelData)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(Style.space(710), Style.space(750))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editorFocused
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx) root.stepTab(dx)
        else if (dashboard.view && typeof dashboard.view.move === 'function') dashboard.view.move(dy)
      }
      onActivateRequested: if (dashboard.view && typeof dashboard.view.togglePause === 'function') dashboard.view.togglePause()
      onTextKey: function(text) {
        if (text >= '1' && text <= '4') root.selectTab(Number(text) - 1)
        else if (text === ',') root.settingsOpen = !root.settingsOpen
        else if (text === '/') {
          root.selectTab(3)
          Qt.callLater(function() { if (dashboard.view) dashboard.view.focusSearch() })
        }
      }

      Dashboard {
        id: dashboard
        anchors.fill: parent
        host: root
        service: root.dataService
        theme: root.panelTheme
      }
    }
  }
}
