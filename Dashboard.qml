import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "components"
import "views"
import "Metrics.js" as Metrics

// The popup's frame: heading, tab row, the active view and a footer line.
// Views are loaded only while the panel is open, so closing it frees their
// charts and process rows.
Item {
  id: dashboard

  required property var host
  required property var service
  required property var theme
  readonly property alias view: viewLoader.item

  readonly property string footer: {
    if (host.settingsOpen) return "Changes save automatically    , back to dashboard"
    if (host.tab === 0) {
      var load = service.loadAverage
      return "Up " + Metrics.duration(service.uptime)
        + (load ? "  ·  Load " + [load.one, load.five, load.fifteen].map(function(n) { return n.toFixed(2) }).join(" / ") : "")
    }
    if (host.tab === host.processesTab) return "/ search    space pause    ← → views    , settings"
    return "1–" + host.tabs.length + " views    ← → navigate    / processes    , settings"
  }

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
        anchors.left: parent.left
        anchors.right: settingsButton.left
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(4)

        Label {
          width: parent.width
          theme: dashboard.theme
          text: "System Monitor"
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Caption {
          width: parent.width
          theme: dashboard.theme
          text: (dashboard.service.hostname || "This machine").toUpperCase() + "  ·  LIVE / " + dashboard.service.refreshIntervalSec + "s"
        }
      }

      PanelActionButton {
        id: settingsButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: dashboard.host.settingsOpen ? "×" : ""
        tooltipText: dashboard.host.settingsOpen ? "Back to dashboard (,)" : "Customize readings (,)"
        foreground: dashboard.theme.foreground
        fontFamily: dashboard.theme.fontFamily
        onClicked: {
          dashboard.host.settingsOpen = !dashboard.host.settingsOpen
          dashboard.host.focusPanel()
        }
      }
    }

    Row {
      id: tabRow
      Layout.fillWidth: true
      spacing: Style.space(4)

      Repeater {
        model: dashboard.host.tabs

        ThemeButton {
          required property string modelData
          required property int index
          theme: dashboard.theme
          width: (tabRow.width - tabRow.spacing * (dashboard.host.tabs.length - 1)) / dashboard.host.tabs.length
          text: modelData
          selected: !dashboard.host.settingsOpen && dashboard.host.tab === index
          bordered: true
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          verticalPadding: Style.space(6)
          tooltipText: modelData + " (" + (index + 1) + ")"
          onClicked: dashboard.host.selectTab(index)
        }
      }
    }

    Loader {
      id: viewLoader
      Layout.fillWidth: true
      Layout.fillHeight: true
      active: dashboard.host.opened
      sourceComponent: dashboard.host.settingsOpen ? settingsView
        : [overviewView, resourcesView, activityView, processesView][dashboard.host.tab] || overviewView
    }

    Caption {
      Layout.fillWidth: true
      theme: dashboard.theme
      text: dashboard.footer
    }
  }
}
