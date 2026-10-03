import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "../components"
import "../Metrics.js" as Metrics
Item {
  id: root
  required property var service
  required property var theme
  required property var host
  property string sort: 'cpu'
  property bool paused: false
  property var frozen: []
  property double frozenAt: 0
  readonly property bool editorFocused: search.activeFocus
  readonly property var rows: Metrics.filterProcesses(paused ? frozen : service.processes, search.text, sort)
  function focusSearch() { search.forceActiveFocus() }
  function move(dy) { list.contentY = Math.max(0, Math.min(Math.max(0, list.contentHeight - list.height), list.contentY + dy * Style.space(36))) }
  function togglePause() { if (!paused) { frozen = service.processes.slice(); frozenAt = service.processUpdated }; paused = !paused }
  ColumnLayout {
    anchors.fill: parent; spacing: Style.space(10)
    TextField {
      id: search; objectName: "processSearch"; Layout.fillWidth: true
      placeholderText: 'Find a process, user or PID…'
      foreground: root.theme.foreground; accent: root.theme.accent
      placeholderTextColor: root.theme.dim
      font.family: root.theme.fontFamily
      selectByMouse: true
      Keys.onEscapePressed: { focus = false; root.host.focusPanel() }
    }
    RowLayout {
      Layout.fillWidth: true; spacing: Style.space(5)
      Repeater {
        model: [{key: 'cpu', label: 'CPU ↓'}, {key: 'memory', label: 'Memory ↓'}, {key: 'name', label: 'Name A–Z'}]
        Button {
          required property var modelData
          text: modelData.label; selected: root.sort === modelData.key
          foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily
          fontSize: Style.font.caption; horizontalPadding: Style.space(8); verticalPadding: Style.space(5)
          onClicked: root.sort = modelData.key
        }
      }
      Item { Layout.fillWidth: true }
      Button {
        objectName: 'pauseProcesses'
        text: root.paused ? 'Resume' : 'Pause'; selected: root.paused
        foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily
        fontSize: Style.font.caption; horizontalPadding: Style.space(8); verticalPadding: Style.space(5)
        tooltipText: 'Freeze the list for inspection (Space)'
        onClicked: root.togglePause()
      }
    }
    Reading {
      Layout.fillWidth: true; theme: root.theme
      label: root.rows.length + (root.rows.length === 1 ? ' process' : ' processes')
      value: root.paused ? 'Paused · ' + Qt.formatTime(new Date(root.frozenAt), 'hh:mm:ss') : 'Live · ' + Math.max(2, root.service.refreshIntervalSec) + 's'
      valueColor: root.paused ? root.theme.urgent : root.theme.dim
    }
    Row {
      Layout.fillWidth: true; spacing: Style.space(8)
      Caption { theme: root.theme; width: parent.width - Style.space(170); text: 'PROCESS / USER' }
      Caption { theme: root.theme; width: Style.space(64); text: 'CPU'; horizontalAlignment: Text.AlignRight }
      Caption { theme: root.theme; width: Style.space(90); text: 'MEMORY'; horizontalAlignment: Text.AlignRight }
    }
    ListView {
      id: list
      Layout.fillWidth: true; Layout.fillHeight: true
      clip: true; model: root.rows
      boundsBehavior: Flickable.StopAtBounds
      Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: list.width; height: Style.space(47)
        color: hover.containsMouse ? root.theme.hover : index % 2 === 0 ? root.theme.surface : 'transparent'
        radius: Style.space(3)
        Rectangle {
          anchors.left: parent.left; anchors.bottom: parent.bottom; height: 1
          width: parent.width * Math.min(1, (modelData.cpu || 0) / (Math.max(1, root.service.coreLoads.length) * 100))
          color: Qt.alpha(root.theme.accent, 0.35)
        }
        Row {
          anchors.fill: parent; anchors.leftMargin: Style.space(6); spacing: Style.space(8)
          Column {
            width: parent.width - Style.space(170); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(3)
            Label { width: parent.width; theme: root.theme; text: modelData.name; font.bold: true }
            Caption { width: parent.width; theme: root.theme; text: modelData.user + ' · ' + modelData.pid + ' · ' + modelData.state }
          }
          Label { width: Style.space(64); anchors.verticalCenter: parent.verticalCenter; theme: root.theme; text: Metrics.percent(modelData.cpu); horizontalAlignment: Text.AlignRight; color: modelData.cpu >= 100 ? root.theme.accent : root.theme.foreground }
          Label { width: Style.space(84); anchors.verticalCenter: parent.verticalCenter; theme: root.theme; text: Metrics.bytes(modelData.rss); horizontalAlignment: Text.AlignRight }
        }
        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
      }
      Label {
        anchors.centerIn: parent; width: parent.width - Style.space(24); theme: root.theme
        visible: root.rows.length === 0; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: root.service.processError || (search.text ? 'No matching processes.' : 'Collecting processes…')
        color: root.service.processError ? root.theme.urgent : root.theme.dim
      }
    }
    Label {
      Layout.fillWidth: true; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap
      font.pixelSize: Style.font.caption
      text: '100% CPU = one logical core. Memory is resident (RSS); shared pages can appear in several processes.'
    }
  }
}
