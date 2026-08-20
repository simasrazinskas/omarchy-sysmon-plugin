import QtQuick

// Picks whichever GPU backend can actually take a reading on this machine and
// forwards it. Every backend probes itself once at startup and reports
// `available`; the first one that says yes wins, in NVIDIA → AMD → Intel
// order. On a machine with no supported GPU nothing is active, `reading` stays
// null, and the widget simply renders no GPU chips.
//
// The property is `reading` rather than the more natural `data` because Item
// already defines `data` as its default child list — shadowing it makes the
// whole component fail to load.
Item {
  id: root

  // GPU readings cost a subprocess, so they run on their own slower timer than
  // the procfs metrics — utilisation that lags by a few seconds is a fair
  // trade for not forking nvidia-smi twice a second forever.
  property int intervalMs: 5000

  readonly property var backends: [nvidia, amd, intel]
  property var activeBackend: null

  readonly property bool available: activeBackend !== null && activeBackend.available
  readonly property var reading: available ? activeBackend.reading : null
  readonly property string vendor: activeBackend ? activeBackend.vendor : ""
  // True only once every backend has answered, so the widget can tell "no GPU
  // here" apart from "still probing" and avoid flashing a chip on and off.
  readonly property bool probed: nvidia.probed && amd.probed && intel.probed

  function selectBackend() {
    for (var i = 0; i < backends.length; i++) {
      if (backends[i].available) {
        activeBackend = backends[i]
        return
      }
    }
    activeBackend = null
  }

  function refresh() {
    // A backend that has gone away (driver unloaded, eGPU unplugged) drops its
    // availability on the next failed read, so re-selecting each tick lets a
    // lower-priority backend take over instead of the widget going dark.
    if (activeBackend && !activeBackend.available) selectBackend()
    if (activeBackend) activeBackend.refresh()
  }

  NvidiaBackend {
    id: nvidia
    onAvailableChanged: root.selectBackend()
  }

  AmdBackend {
    id: amd
    onAvailableChanged: root.selectBackend()
  }

  IntelBackend {
    id: intel
    onAvailableChanged: root.selectBackend()
  }

  Timer {
    interval: root.intervalMs
    running: root.activeBackend !== null
    repeat: true
    onTriggered: root.refresh()
  }
}
