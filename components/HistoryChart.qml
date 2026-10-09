import QtQuick
import qs.Commons
import "../Metrics.js" as Metrics

// Timestamped line chart. `points` is drawn filled in `tint`; the optional
// `secondary` series (same timestamps, e.g. upload next to download) is a
// thin dimmed line. Missing samples and gaps over 45 s break the line rather
// than drawing a slope across time nobody measured.
Item {
  id: root

  required property var theme
  property var points: []
  property var secondary: []
  property double endTime: 0
  property int seconds: 60
  // Fixed top of the scale; 0 auto-scales to the data (used for traffic).
  property real ceiling: 100
  property string unit: "%"
  property string emptyText: "No readings yet"
  // Prefixes for the hover readout when two series share the chart.
  property string label: ""
  property string secondaryLabel: ""
  property color tint: theme.accent
  property bool interactive: false
  property int hoverIndex: -1

  readonly property real maximum: {
    if (ceiling > 0) return ceiling
    var max = 1024
    points.concat(secondary).forEach(function(p) { if (Metrics.number(p.value)) max = Math.max(max, p.value * 1.12) })
    return max
  }
  readonly property bool hasData: points.some(function(p) { return Metrics.number(p.value) })
  readonly property var hovered: hoverIndex >= 0 && hoverIndex < points.length ? points[hoverIndex] : null

  function pointX(time) {
    var span = seconds * 1000
    return Math.max(0, Math.min(width, width * (time - (endTime - span)) / span))
  }
  function pointY(value) { return height - 3 - Math.max(0, Math.min(1, value / maximum)) * (height - 6) }
  function format(value) { return unit === "%" ? Metrics.percent(value) : Metrics.rate(value) }

  onPointsChanged: plot.requestPaint()
  onSecondaryChanged: plot.requestPaint()
  onMaximumChanged: plot.requestPaint()
  onTintChanged: plot.requestPaint()
  onEndTimeChanged: plot.requestPaint()
  onSecondsChanged: plot.requestPaint()
  onWidthChanged: plot.requestPaint()
  onHeightChanged: plot.requestPaint()
  Connections { target: root.theme; function onForegroundChanged() { plot.requestPaint() } }

  Canvas {
    id: plot
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.strokeStyle = root.theme.hairline
      ctx.lineWidth = 1
      for (var i = 1; i <= 3; i++) {
        var y = Math.round(height * i / 4) + 0.5
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
      }

      function draw(points, color, fill) {
        var segment = []
        function flush() {
          if (!segment.length) return
          ctx.beginPath()
          ctx.moveTo(root.pointX(segment[0].time), root.pointY(segment[0].value))
          for (var j = 1; j < segment.length; j++) ctx.lineTo(root.pointX(segment[j].time), root.pointY(segment[j].value))
          ctx.strokeStyle = color; ctx.lineWidth = fill ? 1.8 : 1.4; ctx.lineJoin = "round"; ctx.stroke()
          if (fill && segment.length > 1) {
            ctx.lineTo(root.pointX(segment[segment.length - 1].time), height)
            ctx.lineTo(root.pointX(segment[0].time), height); ctx.closePath()
            var gradient = ctx.createLinearGradient(0, 0, 0, height)
            gradient.addColorStop(0, Qt.alpha(color, 0.24)); gradient.addColorStop(1, Qt.alpha(color, 0.015))
            ctx.fillStyle = gradient; ctx.fill()
          }
          var last = segment[segment.length - 1]
          ctx.beginPath(); ctx.arc(root.pointX(last.time), root.pointY(last.value), 2.5, 0, Math.PI * 2)
          ctx.fillStyle = color; ctx.fill()
          segment = []
        }
        points.forEach(function(p, i) {
          if (!Metrics.number(p.value) || (i > 0 && p.time - points[i - 1].time > 45000)) flush()
          if (Metrics.number(p.value)) segment.push(p)
        })
        flush()
      }
      draw(root.points, root.tint, true)
      draw(root.secondary, root.theme.dim, false)
    }
  }

  Caption {
    anchors.centerIn: parent
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    theme: root.theme
    text: root.emptyText
    visible: !root.hasData
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onPositionChanged: {
      var closest = -1, distance = Infinity
      root.points.forEach(function(p, i) {
        var d = Math.abs(root.pointX(p.time) - hover.mouseX)
        if (d < distance) { distance = d; closest = i }
      })
      root.hoverIndex = closest
    }
    onExited: root.hoverIndex = -1
  }

  Rectangle {
    visible: root.hovered !== null
    x: visible ? root.pointX(root.hovered.time) : 0
    width: 1; height: parent.height; color: root.theme.dim
  }

  Rectangle {
    visible: root.hovered !== null
    anchors.top: parent.top
    anchors.right: parent.right
    width: tip.implicitWidth + Style.space(12); height: tip.implicitHeight + Style.space(6)
    radius: Style.space(3); color: Color.background
    border.width: 1; border.color: root.theme.hairline
    Label {
      id: tip
      anchors.centerIn: parent
      theme: root.theme
      text: {
        var p = root.hovered
        if (!p) return ""
        var parts = [Qt.formatTime(new Date(p.time), "hh:mm:ss"), root.label + root.format(p.value)]
        var other = root.secondary[root.hoverIndex]
        if (other && other.time === p.time) parts.push(root.secondaryLabel + root.format(other.value))
        return parts.join("  ")
      }
    }
  }
}
