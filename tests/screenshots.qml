import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "plugin" as Plugin
import "plugin/components" as Components
import "plugin/Model.js" as Model

// Renders the README screenshots from live readings: every dashboard view
// after the one-minute history has filled, plus each bar style.
ShellRoot {
  id: shot

  readonly property string output: Quickshell.env("SYSMON_CAPTURE_DIR")
  readonly property int warmup: parseInt(Quickshell.env("SYSMON_WARMUP") || "62")
  // [name, tab, settings open, seconds to wait before capturing]
  readonly property var plan: [
    ["overview", 0, false, 1],
    ["resources", 1, false, 2],
    ["activity", 2, false, 2],
    ["processes", 3, false, 5],
    ["settings", 0, true, 2]
  ]
  property int step: -1

  Plugin.Service { id: readings; settings: host.settings; processesActive: host.tab === host.processesTab && !host.settingsOpen }
  Components.Theme { id: palette }

  Item {
    id: host
    property int tab: 0
    property bool settingsOpen: false
    property bool opened: true
    property var tabs: ["Overview", "Resources", "Activity", "Processes"]
    readonly property int processesTab: 3
    property int historySeconds: 60
    property string chartMetric: "cpu"
    property var settings: ({ refreshIntervalSec: 1 })
    property var options: ({ tempUnit: "C", ramDisplay: "used", barMode: "full", showVram: false })
    function persistSetting(key, value) {}
    function selectTab(index) { tab = index; settingsOpen = false }
    function focusPanel() {}
  }

  // The popup as Omarchy frames it: theme background, accent border.
  Window {
    width: 540; height: 750; visible: true; color: Color.background
    Rectangle {
      id: panelShot
      anchors.fill: parent
      color: Color.background
      border.width: 2
      border.color: Color.accent
      Plugin.Dashboard {
        anchors.fill: parent
        anchors.margins: 20
        host: host; service: readings; theme: palette
      }
    }
  }

  // Each bar style on a bar-height strip, labelled.
  Window {
    width: styles.implicitWidth + 32; height: styles.implicitHeight + 32; visible: true; color: Color.background
    Rectangle {
      id: barShot
      anchors.fill: parent
      color: Color.background
      border.width: 2
      border.color: Color.accent
      Column {
        id: styles
        x: 16; y: 16
        spacing: 6
        Repeater {
          model: Model.BAR_MODES
          Row {
            required property var modelData
            spacing: 16
            Text {
              width: 170; height: 30
              verticalAlignment: Text.AlignVCenter
              text: modelData.label
              color: Color.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Rectangle {
              width: bar.implicitWidth + 24; height: 30
              radius: 4
              color: Qt.alpha(Color.foreground, 0.05)
              Components.BarReadings {
                id: bar
                anchors.centerIn: parent
                chips: Model.buildChips(readings.state, host.options)
                barMode: modelData.key
                urgent: Color.urgent
              }
            }
          }
        }
      }
    }
  }

  // grabToImage renders on the next frame, so the scene only moves on once
  // the current frame has been captured.
  function capture(item, name) {
    item.grabToImage(function(result) {
      result.saveToFile(shot.output + "/" + name + ".png")
      console.log("SHOT", name)
      shot.advance()
    })
  }

  function advance() {
    step++
    if (step >= plan.length) { quit.start(); return }
    var entry = plan[step]
    host.selectTab(entry[1])
    host.settingsOpen = entry[2]
    next.interval = entry[3] * 1000
    next.start()
  }

  Timer {
    id: next
    interval: shot.warmup * 1000
    running: true
    onTriggered: {
      if (shot.step < 0) shot.capture(barShot, "bar-styles")
      else shot.capture(panelShot, shot.plan[shot.step][0])
    }
  }

  Timer { id: quit; interval: 1000; onTriggered: { console.log("SHOTS_OK"); Qt.quit() } }
}
