import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons
import "plugin" as Plugin
import "plugin/components" as Components
ShellRoot {
  id: test
  property int stage: 0
  property string output: Quickshell.env('SYSMON_CAPTURE_DIR')
  Plugin.Service { id: readings; settings: host.settings; processesActive: host.tab === 3 && !host.settingsOpen }
  Components.Theme { id: palette }
  Item {
    id: host
    property int tab: 0
    property bool settingsOpen: false
    property bool opened: true
    property var tabs: ['Overview', 'Resources', 'Activity', 'Processes']
    property int historySeconds: 60
    property string chartMetric: 'cpu'
    property var settings: ({refreshIntervalSec: 1})
    property var options: Object.assign({tempUnit:'C', ramDisplay:'used'}, settings)
    function persistSetting(key, value) { var next = Object.assign({}, settings); next[key] = value; settings = next; if (key === 'historyRange') historySeconds = parseInt(value) * 60; else if (key === 'chartMetric') chartMetric = value }
    function selectTab(index) { tab = index; settingsOpen = false }
    function focusPanel() {}
  }
  function find(item, name) {
    if (item.objectName === name) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) { var found = find(children[i], name); if (found) return found }
    return null
  }
  function check(condition, message) {
    if (!condition) { console.error('SMOKE_FAILED: ' + message); Qt.quit() }
  }
  Window {
    id: window
    width: 540; height: 750; visible: true; color: Color.background
    Item {
      id: capture
      anchors.fill: parent
      Rectangle { anchors.fill: parent; color: Color.background }
      Plugin.Dashboard {
        id: dashboard
        anchors.fill: parent; anchors.margins: 20
        host: host; service: readings; theme: palette
      }
    }
  }
  Timer {
    interval: 3000; running: true; repeat: true
    onTriggered: {
      if (test.stage === 0 && (readings.cpu === null || !readings.mem || readings.coreLoads.length === 0)) {
        console.error('SMOKE_FAILED: live service did not sample'); Qt.quit(); return
      }
      if (test.stage === 3 && readings.processes.length === 0) {
        console.error('SMOKE_FAILED: processes did not sample'); Qt.quit(); return
      }
      if (test.stage === 3) {
        var view = dashboard.view
        var search = test.find(view, 'processSearch')
        test.check(search !== null, 'search field exists')
        search.text = 'sysmon-no-matching-process-987654'
        test.check(view.rows.length === 0, 'search filters live rows')
        search.text = ''
        test.check(view.rows.length > 0, 'clearing search restores rows')
        var pause = test.find(view, 'pauseProcesses')
        pause.clicked()
        test.check(view.paused && view.frozen.length > 0, 'pause freezes rows')
        pause.clicked()
        test.check(!view.paused, 'resume returns to live data')
      }
      if (test.stage === 4) {
        var toggle = test.find(dashboard.view, 'showCpu')
        test.check(toggle !== null && toggle.checked, 'CPU toggle starts enabled')
        toggle.toggled()
        test.check(host.settings.showCpu === false, 'toggle persists through host')
        Qt.callLater(function() {
          var refreshed = test.find(dashboard.view, 'showCpu')
          test.check(refreshed !== null && !refreshed.checked, 'toggle reflects persisted value')
          refreshed.toggled()
          test.check(host.settings.showCpu === true, 'toggle restores through binding')
        })
        test.check(!readings.processesActive, 'process scans stop outside process view')
      }
      if (test.output) capture.grabToImage(function(result) { result.saveToFile(test.output + '/view-' + test.stage + '.png') })
      console.log('SMOKE_VIEW', test.stage, 'cpu', readings.cpu, 'memory', readings.mem !== null, 'cores', readings.coreLoads.length, 'processes', readings.processes.length)
      advance.restart()
    }
  }
  Timer {
    id: advance; interval: 300
    onTriggered: {
      test.stage++
      if (test.stage < 4) host.selectTab(test.stage)
      else if (test.stage === 4) host.settingsOpen = true
      else if (test.stage === 5) { host.settingsOpen = false; host.tab = 0; window.width = 360; window.height = 480 }
      else if (test.stage === 6) { window.width = 540; window.height = 750; Color.foreground = '#20242b'; Color.background = '#f3f4f7'; Color.accent = '#235ac6'; Color.urgent = '#b42318' }
      else if (test.stage === 7) { host.tab = 3; window.width = 360; window.height = 480 }
      else { console.log('SMOKE_OK'); Qt.quit() }
    }
  }
}
