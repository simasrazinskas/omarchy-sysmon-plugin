import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "components"

// Bar widget entry point: the bar readings, the dashboard popup, keyboard
// routing, and writing settings back to shell.json.
Panel {
  id: root
  moduleName: "io.github.simasrazinskas.sysmon"
  ipcTarget: "io.github.simasrazinskas.sysmon"

  readonly property var tabs: ["Overview", "Resources", "Activity", "Processes"]
  readonly property int processesTab: 3
  property int tab: 0
  property bool settingsOpen: false

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int historySeconds: ({ "1m": 60, "5m": 300, "15m": 900 })[String(setting("historyRange", "1m"))] || 60
  readonly property string chartMetric: {
    var value = String(setting("chartMetric", "cpu"))
    return ["cpu", "ram", "gpu"].indexOf(value) >= 0 ? value : "cpu"
  }

  readonly property var options: ({
    showCpu: setting("showCpu", true) === true,
    showRam: setting("showRam", true) === true,
    showCpuTemp: setting("showCpuTemp", true) === true,
    showGpu: setting("showGpu", true) === true,
    showGpuTemp: setting("showGpuTemp", true) === true,
    showVram: setting("showVram", false) === true,
    showNet: setting("showNet", true) === true,
    showDisk: setting("showDisk", true) === true,
    ramDisplay: String(setting("ramDisplay", "used")) === "percent" ? "percent" : "used",
    tempUnit: String(setting("tempUnit", "C")).toUpperCase() === "F" ? "F" : "C",
    barMode: Model.barMode(String(setting("barMode", "full"))).key
  })

  readonly property bool editorFocused: dashboard.view !== null && dashboard.view.editorFocused === true

  function selectTab(index) {
    settingsOpen = false
    tab = index
    focusPanel()
  }
  function stepTab(direction) { selectTab((tab + direction + tabs.length) % tabs.length) }
  function focusPanel() { keyCatcher.forceActiveFocus() }
  // Views opt in to keyboard actions by defining these functions.
  function viewCall(name, argument) {
    var view = dashboard.view
    if (view && typeof view[name] === "function") view[name](argument)
  }

  // Apply locally for an instant change, then write the same value back
  // through shell.json so it survives a shell restart. The write is debounced
  // so flicking several toggles lands as one shell.json update of the final
  // state — intermediate writes would otherwise race the bar's settings
  // re-injection.
  property var _pendingEntry: null

  function persistSetting(name, value) {
    if (root.settings && root.settings[name] === value) return
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
    onTriggered: {
      if (!root._pendingEntry) return
      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
        root.bar.shell.updateEntryInline(root.moduleName, root._pendingEntry)
      root._pendingEntry = null
    }
  }

  Theme {
    id: palette
    foreground: root.foreground
    accent: Color.accent
    urgent: root.bar ? root.bar.urgent : Color.urgent
    fontFamily: root.fontFamily
  }

  Service {
    id: monitor
    settings: root.settings
    processesActive: root.opened && !root.settingsOpen && root.tab === root.processesTab
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : readings.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? readings.implicitHeight + scaledVerticalPadding * 2 : -1
    tooltipText: Model.tooltipText(monitor.state, root.options)
    useActiveColor: false
    onPressed: function(buttonCode) { root.toggle() }

    BarReadings {
      id: readings
      anchors.centerIn: parent
      chips: Model.buildChips(monitor.state, root.options)
      barMode: root.options.barMode
      vertical: root.vertical
      foreground: root.foreground
      urgent: palette.urgent
      fontFamily: root.fontFamily
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
        else root.viewCall("move", dy)
      }
      onActivateRequested: root.viewCall("togglePause")
      onTextKey: function(text) {
        if (text >= "1" && text <= String(root.tabs.length)) root.selectTab(Number(text) - 1)
        else if (text === ",") root.settingsOpen = !root.settingsOpen
        else if (text === "/") {
          root.selectTab(root.processesTab)
          Qt.callLater(function() { root.viewCall("focusSearch") })
        }
      }

      Dashboard {
        id: dashboard
        anchors.fill: parent
        host: root
        service: monitor
        theme: palette
      }
    }
  }
}
