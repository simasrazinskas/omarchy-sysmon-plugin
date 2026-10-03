import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "components"
import "views"
import "Metrics.js" as Metrics
Item {
  id: dashboard
  required property var host
  required property var service
  required property var theme
  readonly property alias view: viewLoader.item
  Component { id: overviewView; OverviewView { service: dashboard.service; theme: dashboard.theme; host: dashboard.host } }
  Component { id: resourcesView; ResourcesView { service: dashboard.service; theme: dashboard.theme; host: dashboard.host } }
  Component { id: activityView; ActivityView { service: dashboard.service; theme: dashboard.theme; host: dashboard.host } }
  Component { id: processesView; ProcessesView { service: dashboard.service; theme: dashboard.theme; host: dashboard.host } }
  Component { id: settingsView; SettingsView { service: dashboard.service; theme: dashboard.theme; host: dashboard.host } }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)
    Item {
      Layout.fillWidth: true
      implicitHeight: heading.implicitHeight
      Column {
        id: heading
        anchors.left: parent.left; anchors.right: settingsButton.left
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(4)
        Label { theme: dashboard.theme; width: parent.width; text: 'System Monitor'; font.pixelSize: Style.font.title; font.bold: true }
        Caption {
          theme: dashboard.theme; width: parent.width
          text: (dashboard.service.hostname || 'THIS MACHINE').toUpperCase() + '  ·  LIVE / ' + dashboard.service.refreshIntervalSec + 's'
        }
      }
      PanelActionButton {
        id: settingsButton
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        iconText: host.settingsOpen ? '×' : ''
        tooltipText: host.settingsOpen ? 'Back to dashboard (,)' : 'Customize readings (,)'
        foreground: dashboard.theme.foreground; fontFamily: dashboard.theme.fontFamily
        onClicked: { host.settingsOpen = !host.settingsOpen; host.focusPanel() }
      }
    }
    Row {
      Layout.fillWidth: true
      spacing: Style.space(4)
      Repeater {
        model: host.tabs
        Button {
          required property string modelData
          required property int index
          width: (parent.width - Style.space(12)) / 4
          text: modelData
          selected: !host.settingsOpen && host.tab === index
          bordered: true
          fontSize: Style.font.caption
          foreground: dashboard.theme.foreground; accent: dashboard.theme.accent; fontFamily: dashboard.theme.fontFamily
          horizontalPadding: Style.space(4); verticalPadding: Style.space(6)
          tooltipText: modelData + ' (' + (index + 1) + ')'
          onClicked: host.selectTab(index)
        }
      }
    }
    Loader {
      id: viewLoader
      Layout.fillWidth: true; Layout.fillHeight: true
      active: host.opened
      sourceComponent: host.settingsOpen ? settingsView : host.tab === 1 ? resourcesView : host.tab === 2 ? activityView : host.tab === 3 ? processesView : overviewView
    }
    Caption {
      Layout.fillWidth: true; theme: dashboard.theme
      text: host.settingsOpen ? 'PREFERENCES  ·  Saved automatically'
        : host.tab === 0 ? 'UP ' + Metrics.duration(dashboard.service.uptime) + (dashboard.service.loadAverage ? '  ·  LOAD ' + dashboard.service.loadAverage.one.toFixed(2) + ' / ' + dashboard.service.loadAverage.five.toFixed(2) + ' / ' + dashboard.service.loadAverage.fifteen.toFixed(2) : '')
        : '1–4 views    ← → navigate    / processes    , settings'
      font.pixelSize: Style.font.caption
    }
  }
}
