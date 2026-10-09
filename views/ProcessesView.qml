import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "../components"
import "../Metrics.js" as Metrics

// Searchable, sortable live process list. The service only scans /proc while
// this view is open.
Item {
  id: root

  required property var service
  required property var theme
  required property var host

  property string sort: "cpu"
  property bool paused: false
  property var frozen: []
  property double frozenAt: 0

  readonly property bool editorFocused: search.activeFocus
  readonly property var source: paused ? frozen : service.processes
  readonly property var rows: Metrics.filterProcesses(source, search.text, sort)

  // Shared by the header and every row so the columns line up.
  readonly property real inset: Style.space(8)
  readonly property real gap: Style.space(8)
  readonly property real cpuWidth: Style.space(64)
  readonly property real memoryWidth: Style.space(88)
  readonly property real nameWidth: list.width - inset * 2 - gap * 2 - cpuWidth - memoryWidth

  function focusSearch() { search.forceActiveFocus() }
  function move(dy) { scrollTo(list.contentY + dy * Style.space(36)) }
  // Replacing a ListView's array model resets it to the top. The model is
  // assigned here rather than bound so the reader's place survives each
  // refresh; a new search or sort order starts again from the top.
  property real pendingY: -1
  property bool scrollToTop: false
  function showRows() {
    if (pendingY < 0) pendingY = list.contentY
    list.model = rows
    scrollTo(pendingY)
    restoreTimer.restart()
  }
  function scrollTo(y) { list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height)) }
  function restoreScroll() {
    if (pendingY < 0) return
    scrollTo(scrollToTop ? 0 : pendingY)
    pendingY = -1
    scrollToTop = false
  }
  onRowsChanged: showRows()
  // A child timer rather than Qt.callLater: it dies with the view, so a
  // restore can never run against an unloaded one.
  Timer { id: restoreTimer; interval: 0; onTriggered: root.restoreScroll() }
  onSortChanged: scrollToTop = true
  Component.onCompleted: showRows()

  function togglePause() {
    if (!paused) {
      frozen = service.processes.slice()
      frozenAt = service.processUpdated
    }
    paused = !paused
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    TextField {
      id: search
      objectName: "processSearch"
      Layout.fillWidth: true
      placeholderText: "Find a process, user or PID…"
      foreground: root.theme.foreground
      accent: root.theme.accent
      placeholderTextColor: root.theme.dim
      font.family: root.theme.fontFamily
      selectByMouse: true
      onTextChanged: root.scrollToTop = true
      Keys.onEscapePressed: { focus = false; root.host.focusPanel() }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(5)

      Repeater {
        model: [{ key: "cpu", label: "CPU ↓" }, { key: "memory", label: "Memory ↓" }, { key: "name", label: "Name A–Z" }]

        ThemeButton {
          required property var modelData
          theme: root.theme
          text: modelData.label
          selected: root.sort === modelData.key
          fontSize: Style.font.caption
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(5)
          onClicked: root.sort = modelData.key
        }
      }

      Item { Layout.fillWidth: true }

      ThemeButton {
        theme: root.theme
        objectName: "pauseProcesses"
        text: root.paused ? "Resume" : "Pause"
        selected: root.paused
        fontSize: Style.font.caption
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(5)
        tooltipText: "Freeze the list for inspection (Space)"
        onClicked: root.togglePause()
      }
    }

    Reading {
      Layout.fillWidth: true
      theme: root.theme
      label: (root.rows.length === root.source.length ? "" : root.rows.length + " of ")
        + root.source.length + (root.source.length === 1 ? " process" : " processes")
      value: root.paused ? "Paused · " + Qt.formatTime(new Date(root.frozenAt), "hh:mm:ss")
        : "Live · " + Math.max(2, root.service.refreshIntervalSec) + "s"
      valueColor: root.paused ? root.theme.urgent : root.theme.dim
    }

    Row {
      Layout.fillWidth: true
      leftPadding: root.inset
      spacing: root.gap
      Caption { theme: root.theme; width: root.nameWidth; text: "PROCESS / USER" }
      Caption { theme: root.theme; width: root.cpuWidth; text: "CPU"; horizontalAlignment: Text.AlignRight }
      Caption { theme: root.theme; width: root.memoryWidth; text: "MEMORY"; horizontalAlignment: Text.AlignRight }
    }

    ListView {
      id: list
      objectName: "processList"
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

      delegate: Rectangle {
        required property var modelData
        required property int index
        width: list.width
        height: Style.space(47)
        radius: Style.space(3)
        color: hover.containsMouse ? root.theme.hover : index % 2 === 0 ? root.theme.surface : "transparent"

        // Share of the whole machine, so a busy process reads as a long bar.
        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          height: 1
          width: parent.width * Math.min(1, (modelData.cpu || 0) / (Math.max(1, root.service.coreLoads.length) * 100))
          color: Qt.alpha(root.theme.accent, 0.35)
        }

        Row {
          anchors.fill: parent
          leftPadding: root.inset
          spacing: root.gap

          Column {
            width: root.nameWidth
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Label { width: parent.width; theme: root.theme; text: modelData.name; font.bold: true }
            Caption { width: parent.width; theme: root.theme; text: modelData.user + " · " + modelData.pid + " · " + modelData.state }
          }
          Label {
            width: root.cpuWidth
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            text: Metrics.percent(modelData.cpu)
            horizontalAlignment: Text.AlignRight
            color: modelData.cpu >= 100 ? root.theme.accent : root.theme.foreground
          }
          Label {
            width: root.memoryWidth
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            text: Metrics.bytes(modelData.rss)
            horizontalAlignment: Text.AlignRight
          }
        }

        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
      }

      Label {
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        theme: root.theme
        visible: root.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.service.processError || (search.text ? "No matching processes." : "Collecting processes…")
        color: root.service.processError ? root.theme.urgent : root.theme.dim
      }
    }

    Caption {
      Layout.fillWidth: true
      theme: root.theme
      wrapMode: Text.WordWrap
      text: "100% CPU = one logical core. Memory is resident (RSS); shared pages can appear in several processes."
    }
  }
}
