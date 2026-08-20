import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// System Monitor bar widget: machine vitals in the bar, full values on hover,
// btop on click. There is deliberately no popup panel — btop is already a
// better detail view than anything this widget could draw, and it is one
// keystroke away.
BarWidget {
  id: root
  moduleName: "io.github.simasrazinskas.sysmon"

  // Which chips are on, and how they are rendered. Read straight off the
  // widget's shell.json entry, so the plugin settings screen is the whole
  // configuration surface.
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
    tempUnit: String(setting("tempUnit", "C")).toUpperCase() === "F" ? "F" : "C"
  })

  readonly property string label: root.vertical
    ? Model.barTextVertical(service.state, options)
    : Model.barText(service.state, options)

  readonly property string details: Model.tooltipText(service.state, options)

  Service {
    id: service
    settings: root.settings
  }

  // Nothing to show until the first samples land (CPU needs two ticks for a
  // delta), and nothing to show if every chip is switched off. Collapsing to
  // zero width beats reserving a gap for a widget with no content.
  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.details
    // No threshold colouring by design: the bar stays in the theme foreground
    // whatever the machine is doing, so this widget never fights the theme.
    useActiveColor: false
    onPressed: function(mouseButton) {
      if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    }
  }
}
