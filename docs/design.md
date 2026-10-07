# Design notes

The dashboard borrows durable ideas from established monitors, sized for an
Omarchy popup rather than reproducing a full task manager.

| Reference | Proven strength | Applied here |
| --- | --- | --- |
| [btop](https://github.com/aristocratos/btop) (C++ releases since 2021) | Resource graphs, network auto-scaling, sortable/filterable processes, pause | Timestamped 1/5/15-minute history, traffic chart, process search/sort/pause |
| [htop](https://htop.dev/) | Interactive process inspection and per-core visibility | Per-core meters, PID/user/state context, one-core CPU convention |
| [Glances](https://nicolargo.github.io/glances/) | A compact system overview with resource alerts | Pressure readings, bar alert colours with local advisory thresholds |
| [Trading212 plugin](https://github.com/simasrazinskas/omarchy-trading212-plugin) | Clear hierarchy, restrained themed surfaces, focused tabs | Shared design language, fixed navigation, scrollable views, separate preferences |

The overview gives current values and recent trends. Resources explains CPU,
memory and GPU load; Activity provides network and storage context; Processes answers “what is using
it?” Settings do not compete with the readings for space.

## Measurement choices

- CPU history remains on a fixed 0–100% scale; an idle 2% must not look like a
  saturated machine. Network rates auto-scale because useful rates vary widely.
- Every history sample has a timestamp. Changing refresh rate does not change
  what “five minutes” means. Missing readings break graph lines, and gaps over
  45 seconds break them too. History starts empty, with no invented samples.
- Chart average is a mean of available samples, not a time-weighted average.
- [Linux PSI](https://docs.kernel.org/accounting/psi.html) measures time when
  tasks stall for resources. The UI uses `some avg10`, not CPU utilization or
  the system-level CPU `full` field.
- Process CPU comes from changes in `utime + stime`, divided by elapsed
  monotonic time and the machine's clock tick rate. PID plus start time guards
  against PID reuse. The first observation deliberately has no CPU percentage.
- [procfs](https://docs.kernel.org/filesystems/proc.html) provides memory and
  process counters. RSS is not unique memory: shared pages can be counted in
  multiple processes. This is stated directly below the process list.
- Monitoring is read-only. Killing processes, privileged probes, remote agents,
  disk-wide scans and desktop notifications are outside this release.

## Visual and runtime checks

`tests/qml-smoke` renders the real dashboard offscreen using the installed
Omarchy components and live readings. It covers every view, a compact window,
a light palette, search, pause/resume, settings binding and process sampling
lifecycle. It fails on runtime QML errors. The layer-shell bar host is checked
separately on Wayland because offscreen Qt cannot create layer-shell surfaces.
