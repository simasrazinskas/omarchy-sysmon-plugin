import QtQuick
import qs.Commons
import qs.Ui
import "../components"
import "../Model.js" as Model

// Preferences. Every control writes the same keys as Omarchy's plugin
// settings screen, through host.persistSetting.
Scroller {
  id: root

  required property var service
  required property var theme
  required property var host

  spacing: Style.space(12)

  readonly property bool editorFocused: iface.activeFocus || mount.activeFocus

  Caption { theme: root.theme; text: "BAR READINGS" }

  Card {
    width: parent.width
    theme: root.theme

    Repeater {
      model: Model.panelRows(root.service.state, root.host.options)

      Item {
        required property var modelData
        width: parent.width
        implicitHeight: Style.space(32)

        Label {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.4
          theme: root.theme
          text: modelData.label
        }
        Label {
          anchors.right: toggle.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.4
          horizontalAlignment: Text.AlignRight
          theme: root.theme
          text: modelData.value
          color: root.theme.dim
        }
        ToggleSwitch {
          id: toggle
          objectName: modelData.key
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: modelData.enabled
          foreground: root.theme.foreground
          onToggled: root.host.persistSetting(modelData.key, !modelData.enabled)
        }
      }
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { theme: root.theme; text: "BAR STYLE" }
    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: Model.BAR_MODES
        ThemeButton {
          required property var modelData
          objectName: "barMode-" + modelData.key
          theme: root.theme
          text: modelData.label
          selected: root.host.options.barMode === modelData.key
          onClicked: root.host.persistSetting("barMode", modelData.key)
        }
      }
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { theme: root.theme; text: "UNITS" }
    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: [{ value: "C", label: "°C" }, { value: "F", label: "°F" }]
        ThemeButton { required property var modelData; theme: root.theme; text: modelData.label; selected: root.host.options.tempUnit === modelData.value; onClicked: root.host.persistSetting("tempUnit", modelData.value) }
      }
      Repeater {
        model: [{ value: "used", label: "Memory: used" }, { value: "percent", label: "Memory: %" }]
        ThemeButton { required property var modelData; theme: root.theme; text: modelData.label; selected: root.host.options.ramDisplay === modelData.value; onClicked: root.host.persistSetting("ramDisplay", modelData.value) }
      }
    }

    Reading {
      width: parent.width
      theme: root.theme
      label: "Refresh interval"
      value: root.service.refreshIntervalSec + (root.service.refreshIntervalSec === 1 ? " second" : " seconds")
    }
    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: [1, 2, 5, 10, 30]
        ThemeButton { required property int modelData; theme: root.theme; text: modelData + "s"; selected: root.service.refreshIntervalSec === modelData; onClicked: root.host.persistSetting("refreshIntervalSec", modelData) }
      }
    }
  }

  Card {
    width: parent.width
    theme: root.theme

    Caption { theme: root.theme; text: "DATA SOURCES" }
    Label { width: parent.width; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap; text: "Network interface · blank follows the default route" }
    SettingField {
      id: iface
      width: parent.width
      theme: root.theme
      onCommitted: function(value) { root.host.persistSetting("networkInterface", value) }
      onCancelled: root.host.focusPanel()
      saved: root.service.configuredInterface
      placeholderText: "Automatic (" + (root.service.detectedInterface || "no route") + ")"
    }
    Label { width: parent.width; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap; text: "Storage mountpoint · blank monitors /" }
    SettingField {
      id: mount
      width: parent.width
      theme: root.theme
      onCommitted: function(value) { root.host.persistSetting("diskMountpoint", value) }
      onCancelled: root.host.focusPanel()
      saved: root.service.configuredMount
      placeholderText: "/"
    }
    Label {
      width: parent.width
      theme: root.theme
      color: root.theme.dim
      wrapMode: Text.WordWrap
      text: "History is kept in memory for up to 15 minutes and starts fresh when the shell reloads."
    }
  }
}
