# System Monitor — Omarchy bar plugin

Machine vitals in the [Omarchy](https://omarchy.org) status bar: CPU, memory,
temperature, GPU, network throughput and disk usage. Hover for full values,
click for `btop`.

```
 12%   18G   42°   64%  71°   1.2M   340K   23%
```

Every chip can be switched off in the plugin settings, so the widget can be as
small as a single CPU reading or as full as the line above.

## Install

```bash
omarchy plugin add https://github.com/simasrazinskas/omarchy-sysmon-plugin.git --enable
```

Then place it with `omarchy bar move io.github.simasrazinskas.sysmon`, or drag
it along the bar.

## Settings

Everything lives in the standard plugin settings screen — there is no config
file to hand-edit.

| Setting | Default | What it does |
|---|---|---|
| Show CPU usage | on | Busy share across all cores |
| Show memory | on | Used memory, or percent |
| Show CPU temperature | on | Package sensor, not a single core |
| Show GPU usage | on | Hidden automatically with no supported GPU |
| Show GPU temperature | on | |
| Show VRAM used | off | |
| Show network throughput | on | Down and up rate |
| Show disk usage | on | Percent used |
| Memory shown as | `used` | `used` (18G) or `percent` (28%) |
| Temperature unit | `C` | `C` or `F` |
| Refresh interval | 2s | 1–30 seconds |
| Network interface | blank | Blank follows the default route |
| Disk mountpoint | blank | Blank means `/` |

### Auto-detection

Leave **Network interface** and **Disk mountpoint** blank and the widget works
this out itself:

- **Network** follows the interface carrying the default route, re-checked
  every 30 seconds, so moving between wifi and ethernet follows along. Naming
  an interface explicitly turns the re-check off.
- **Disk** uses `/`. This matters more than it sounds: picking "the largest
  filesystem" or "the first mount" would happily report a mounted USB stick
  that happens to be 100% full.
- **CPU temperature** finds the sensor by name (`coretemp`, `k10temp`,
  `zenpower`, …) rather than by hwmon number, which is assigned in probe order
  and changes between boots. It prefers a package-wide label — Intel's
  `Package id 0`, AMD's `Tctl`/`Tdie` — over any single core, which would
  otherwise report whichever core happens to be busy.

## What it does not do

Worth being upfront about, so nobody files a bug for a deliberate choice:

- **No colour thresholds.** Chips stay in the theme foreground whatever the
  machine is doing. The widget never fights your theme; the flip side is that
  98°C looks the same as 42°C.
- **No detail panel.** Left-click opens `btop`, which is a better system
  monitor than anything this widget could draw. The hover tooltip carries the
  full values, including chips you have switched off.
- **No presets, and a fixed chip order.** Per-widget settings live in the bar's
  `shell.json` layout entry, and the plugin manifest schema supports only
  scalar values — no arrays, no nested objects. There is nowhere to store named
  presets or a custom ordering. Chips always render in the order shown above.
- **No per-core, per-process, swap, fan or battery readings.** Out of scope for
  now; `btop` is one click away.

## Hardware support

CPU, memory, temperature, network and disk come from `/proc` and `/sys` and
work on any Linux machine.

GPU support is split into per-vendor backends, picked automatically in NVIDIA →
AMD → Intel order. **When no backend can take a reading, the GPU chips simply
do not render** — no `N/A`, no zeros. Everything else keeps working.

| Backend | Source | Status |
|---|---|---|
| `NvidiaBackend.qml` | `nvidia-smi` | Tested on real hardware (RTX 5070 Ti) |
| `AmdBackend.qml` | `amdgpu` sysfs — `gpu_busy_percent`, `mem_info_vram_*` | **Untested.** No AMD hardware available. Written to amdgpu's documented sysfs surface |
| `IntelBackend.qml` | `gpu_busy_percent` where the driver publishes it | **Untested, and usually unavailable.** `i915` has never exposed utilisation in sysfs — it lives behind the i915 PMU, which needs privileges this plugin will not ask for. Newer `xe` cards do publish it |

If you have AMD or Intel hardware, a bug report saying what did or didn't
appear is genuinely useful, and PRs are welcome.

## How it samples

Anything the kernel publishes as a file is read in-process with `FileView`.
Forking a helper twice a second to read data that is already a file would cost
more than the readings are worth — so only the GPU and disk use a subprocess,
and both run on slower timers of their own.

| Metric | Source | Interval |
|---|---|---|
| CPU, memory, temperature, network | `/proc/stat`, `/proc/meminfo`, `/sys/class/hwmon`, `/proc/net/dev` | refresh interval (2s) |
| GPU | `nvidia-smi` or sysfs | max(5s, refresh interval) |
| Disk | `df -P` | 60s |

A few details that are deliberate rather than accidental:

- **CPU needs two samples**, so no CPU chip renders on the very first tick. A
  real 0% and "not measured yet" must not look identical.
- **Memory uses `MemAvailable`**, not `MemFree`. `MemFree` counts reclaimable
  page cache as used and reports a permanently near-full machine.
- **Network counters are cumulative and reset** when an interface is
  reconfigured. A negative delta is treated as a reset and reported as zero,
  rather than as a large bogus spike.
- **Values are padded to a constant width.** A reading that grows a digit
  (9% → 10%) would otherwise shove every widget beside it sideways.

The bar is built per monitor, so on a multi-monitor setup the service runs once
per bar surface. On one monitor that costs four small file reads every two
seconds.

## Vertical bars

A vertical bar is 28px wide, which does not fit an icon plus a four-character
reading. In `left`/`right` bar positions the icons are dropped and the values
stack instead. The tooltip still names every one of them.

## Fonts

Icons come from the Nerd Font glyph set that Omarchy ships
(`ttf-jetbrains-mono-nerd-basic`). Note that Font Awesome's `fa-memory`
(`U+F538`) is *not* in JetBrainsMono Nerd Font and renders as tofu, which is
why memory uses `md-memory` (`U+EFC5`) instead. If you swap the bar font, check
these codepoints exist in it: `U+F4BC` `U+EFC5` `U+F2C9` `U+F2DB` `U+F1C0`
`U+F176` `U+F175` `U+F0A0`.

## Development

```bash
./tests/run
```

`Model.js` holds all parsing and formatting and deliberately contains no QML or
Quickshell types, so the whole file runs under `node --test`. The parsers are
tested against real captured `/proc`, `nvidia-smi`, `df` and `ip route` output.
`tests/run` also validates the manifest when `omarchy-plugin-validate` is
present.

Saving any file under `~/.config/omarchy/plugins/` hot-reloads the plugin, so
there is no restart in the edit loop.

## License

MIT
