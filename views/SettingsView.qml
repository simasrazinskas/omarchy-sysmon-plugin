import QtQuick
import qs.Commons
import qs.Ui
import "../components"
import "../Model.js" as Model
Scroller {
  id: root
  required property var service
  required property var theme
  required property var host
  spacing: Style.space(12)
  readonly property bool editorFocused: iface.activeFocus || mount.activeFocus
  function move(dy) { scrollBy(dy * Style.space(48)) }
  Caption { theme: root.theme; text: 'MAKE ROOM FOR WHAT MATTERS' }
  Label { width: parent.width; theme: root.theme; color: root.theme.dim; wrapMode: Text.WordWrap; text: 'Choose your bar readings. Every metric stays available in the dashboard.' }
  Card {
    width: parent.width; theme: root.theme
    Repeater {
      model: Model.panelRows(root.service.state, root.host.options)
      Item {
        required property var modelData
        width: parent.width; implicitHeight: Style.space(32)
        Label { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; theme: root.theme; text: modelData.label }
        Label { anchors.right: toggle.left; anchors.rightMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; horizontalAlignment: Text.AlignRight; theme: root.theme; text: modelData.value; color: root.theme.dim }
        ToggleSwitch { id: toggle; objectName: modelData.key; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; checked: modelData.enabled; foreground: root.theme.foreground; onToggled: root.host.persistSetting(modelData.key, !modelData.enabled) }
      }
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'BAR STYLE' }
    Flow {
      width: parent.width; spacing: Style.space(6)
      Repeater {
        model: Model.BAR_MODES
        Button { required property var modelData; objectName: 'barMode-' + modelData.key; text: modelData.label; selected: Model.barMode(root.host.options.barMode).key === modelData.key; foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily; onClicked: root.host.persistSetting('barMode', modelData.key) }
      }
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'READINGS' }
    Row {
      width: parent.width; spacing: Style.space(6)
      Repeater {
        model: ['C', 'F']
        Button { required property string modelData; text: '°' + modelData; selected: root.host.options.tempUnit === modelData; foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily; onClicked: root.host.persistSetting('tempUnit', modelData) }
      }
      Repeater {
        model: [{key:'used', label:'RAM: used'}, {key:'percent', label:'RAM: %'}]
        Button { required property var modelData; text: modelData.label; selected: root.host.options.ramDisplay === modelData.key; foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily; onClicked: root.host.persistSetting('ramDisplay', modelData.key) }
      }
    }
    Reading { width: parent.width; theme: root.theme; label: 'Refresh interval'; value: root.service.refreshIntervalSec + ' seconds' }
    Row {
      spacing: Style.space(6)
      Repeater {
        model: [1, 2, 5, 10, 30]
        Button { required property int modelData; text: modelData + 's'; selected: root.service.refreshIntervalSec === modelData; foreground: root.theme.foreground; accent: root.theme.accent; fontFamily: root.theme.fontFamily; onClicked: root.host.persistSetting('refreshIntervalSec', modelData) }
      }
    }
  }
  Card {
    width: parent.width; theme: root.theme
    Caption { theme: root.theme; text: 'DATA SOURCES' }
    Label { width: parent.width; theme: root.theme; text: 'Network interface · blank follows the default route'; wrapMode: Text.WordWrap; color: root.theme.dim }
    TextField {
      id: iface; width: parent.width; text: root.service.configuredInterface; placeholderText: 'Automatic (' + (root.service.detectedInterface || 'no route') + ')'
      foreground: root.theme.foreground; accent: root.theme.accent; placeholderTextColor: root.theme.dim
      onEditingFinished: root.host.persistSetting('networkInterface', text.trim())
      Keys.onEscapePressed: { focus = false; root.host.focusPanel() }
    }
    Label { width: parent.width; theme: root.theme; text: 'Storage mountpoint · blank monitors /'; color: root.theme.dim }
    TextField {
      id: mount; width: parent.width; text: root.service.configuredMount; placeholderText: '/'
      foreground: root.theme.foreground; accent: root.theme.accent; placeholderTextColor: root.theme.dim
      onEditingFinished: root.host.persistSetting('diskMountpoint', text.trim())
      Keys.onEscapePressed: { focus = false; root.host.focusPanel() }
    }
    Label { width: parent.width; theme: root.theme; wrapMode: Text.WordWrap; color: root.theme.dim; text: 'Changes save automatically. History lives in memory for up to 15 minutes and starts fresh when the shell reloads.' }
  }
  Caption { width: parent.width; theme: root.theme; text: '1–4 TABS   / SEARCH   SPACE PAUSE   , SETTINGS   ESC CLOSE'; wrapMode: Text.WordWrap }
}
