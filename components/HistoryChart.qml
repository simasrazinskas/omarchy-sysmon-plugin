import QtQuick
import qs.Commons
import "../Metrics.js" as Metrics
Item {
  id: root
  required property var theme
  property var points: []
  property var secondary: []
  property double endTime: 0
  property int seconds: 60
  property real ceiling: 100
  property string unit: "%"
  property color tint: theme.accent
  property bool interactive: false
  property int hoverIndex: -1
  readonly property real maximum: {
    if (ceiling > 0) return ceiling
    var max = 1024
    points.concat(secondary).forEach(function(p) { if (Metrics.number(p.value)) max = Math.max(max, p.value * 1.12) })
    return max
  }
  function pointX(time) { return Math.max(0, Math.min(width, width * (time - (endTime - seconds * 1000)) / (seconds * 1000))) }
  function pointY(value) { return height - 3 - Math.max(0, Math.min(1, value / maximum)) * (height - 6) }
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
      var ctx = getContext('2d')
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
          ctx.strokeStyle = color; ctx.lineWidth = 1.8; ctx.lineJoin = 'round'; ctx.stroke()
          if (fill && segment.length > 1) {
            ctx.lineTo(root.pointX(segment[segment.length - 1].time), height)
            ctx.lineTo(root.pointX(segment[0].time), height); ctx.closePath()
            var gradient = ctx.createLinearGradient(0, 0, 0, height)
            gradient.addColorStop(0, Qt.alpha(color, 0.24)); gradient.addColorStop(1, Qt.alpha(color, 0.015))
            ctx.fillStyle = gradient; ctx.fill()
          }
          var last = segment[segment.length - 1]
          ctx.beginPath(); ctx.arc(root.pointX(last.time), root.pointY(last.value), 2.5, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill()
          segment = []
        }
        points.forEach(function(p, i) {
          if (!Metrics.number(p.value) || (i > 0 && p.time - points[i-1].time > 45000)) flush()
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
    text: 'No readings yet'
    visible: !root.points.some(function(p) { return Metrics.number(p.value) })
  }
  MouseArea {
    id: hover
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onPositionChanged: {
      var closest = -1, distance = Infinity
      root.points.forEach(function(p, i) { var d = Math.abs(root.pointX(p.time) - hover.mouseX); if (d < distance) { distance = d; closest = i } })
      root.hoverIndex = closest
    }
    onExited: root.hoverIndex = -1
  }
  Rectangle {
    visible: root.hoverIndex >= 0 && root.hoverIndex < root.points.length
    x: visible ? root.pointX(root.points[root.hoverIndex].time) : 0
    width: 1; height: parent.height; color: root.theme.dim
  }
  Rectangle {
    visible: root.hoverIndex >= 0 && root.hoverIndex < root.points.length
    anchors.top: parent.top
    anchors.right: parent.right
    width: tip.implicitWidth + Style.space(12); height: tip.implicitHeight + Style.space(6)
    radius: Style.space(3); color: Color.background
    Label {
      id: tip; anchors.centerIn: parent; theme: root.theme
      text: {
        if (root.hoverIndex < 0 || root.hoverIndex >= root.points.length) return ''
        var p = root.points[root.hoverIndex]
        return Qt.formatTime(new Date(p.time), 'hh:mm:ss') + '  ' + (root.unit === '%' ? Metrics.percent(p.value) : Metrics.bytes(p.value) + '/s')
      }
    }
  }
}
