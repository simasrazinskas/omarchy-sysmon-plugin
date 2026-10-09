// Kernel parsing and dashboard calculations. Pure functions, no QML types, so
// the file runs under `node --test` too. Missing data stays null — never a
// healthy-looking zero.

function number(value) {
  return typeof value === 'number' && isFinite(value)
}

// ---------------------------------------------------------------- formatting

function percent(value) {
  return number(value) ? value.toFixed(1) + '%' : '—'
}

function bytes(value) {
  if (!number(value)) return '—'
  var units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  var n = Math.max(0, value), i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return n.toFixed(i === 0 ? 0 : 1) + ' ' + units[i]
}

function rate(value) {
  return number(value) ? bytes(value) + '/s' : '—'
}

function duration(seconds) {
  if (!number(seconds)) return '—'
  var m = Math.floor(seconds / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
  if (d > 0) return d + 'd ' + h % 24 + 'h'
  if (h > 0) return h + 'h ' + m % 60 + 'm'
  return m + 'm'
}

// ---------------------------------------------------------------- /proc/stat

// Every `cpu` line: the aggregate under `cpu`, each logical core under
// `cpu0`, `cpu1`, … The first eight counters are user nice system idle iowait
// irq softirq steal. guest and guest_nice are left out because the kernel
// already counts them inside user and nice; adding them again would inflate
// the total and understate load. iowait is idle time spent waiting on disk.
function cpuTimes(text) {
  var out = {}
  String(text || '').split('\n').forEach(function(line) {
    if (!/^cpu\d*\s/.test(line)) return
    var fields = line.trim().split(/\s+/)
    var values = fields.slice(1, 9).map(Number)
    if (values.length < 4 || values.some(function(v) { return !isFinite(v) || v < 0 })) return
    out[fields[0]] = {
      total: values.reduce(function(a, b) { return a + b }, 0),
      idle: values[3] + (values[4] || 0)
    }
  })
  return out
}

// Busy share between two readings of one counter set. The first sample has
// nothing to diff against and returns null: a real 0% and "not measured yet"
// must not look the same. Counters that did not advance (or went backwards
// after CPU hotplug) are also unknown rather than zero.
function busy(previous, current) {
  if (!previous || !current) return null
  var total = current.total - previous.total
  var idle = current.idle - previous.idle
  if (total <= 0 || idle < 0) return null
  return Math.max(0, Math.min(100, 100 * (1 - idle / total)))
}

function coreUsage(previous, current) {
  return Object.keys(current || {}).filter(function(key) { return key !== 'cpu' }).map(function(key) {
    return { name: key.slice(3), value: busy(previous ? previous[key] : null, current[key]) }
  })
}

// ------------------------------------------------------------- /proc/meminfo

// Used memory is total − MemAvailable: the kernel's own estimate of what a new
// allocation could claim. total − MemFree would count reclaimable page cache
// as used and report a permanently near-full machine.
function memory(text) {
  var fields = {}
  String(text || '').split('\n').forEach(function(line) {
    var m = line.match(/^(\w+):\s+(\d+)\s+kB/)
    if (m) fields[m[1]] = Number(m[2]) * 1024
  })
  if (!(fields.MemTotal > 0) || !number(fields.MemAvailable)) return null
  var used = Math.max(0, fields.MemTotal - fields.MemAvailable)
  var hasSwap = number(fields.SwapTotal) && number(fields.SwapFree)
  return {
    total: fields.MemTotal,
    available: fields.MemAvailable,
    used: used,
    percent: used / fields.MemTotal * 100,
    cache: (fields.Cached || 0) + (fields.SReclaimable || 0),
    swapTotal: hasSwap ? fields.SwapTotal : null,
    swapUsed: hasSwap ? Math.max(0, fields.SwapTotal - fields.SwapFree) : null
  }
}

// ------------------------------------------------------- other procfs / df

function pressure(text) {
  var m = String(text || '').match(/^some\s+avg10=([\d.]+)\s+avg60=([\d.]+)\s+avg300=([\d.]+)/m)
  return m ? { avg10: Number(m[1]), avg60: Number(m[2]), avg300: Number(m[3]) } : null
}

function load(text) {
  var f = String(text || '').trim().split(/\s+/)
  if (f.length < 4 || f.slice(0, 3).some(function(v) { return !isFinite(Number(v)) })) return null
  return { one: Number(f[0]), five: Number(f[1]), fifteen: Number(f[2]), tasks: f[3] }
}

function uptime(text) {
  var n = parseFloat(String(text || ''))
  return isFinite(n) && n >= 0 ? n : null
}

// `df -Pk` prints one record per line (-P stops long device names wrapping):
// Filesystem 1024-blocks Used Available Capacity Mounted-on. The device and
// mountpoint may both contain spaces, so the numeric columns anchor the match.
function disk(text) {
  var lines = String(text || '').trim().split('\n')
  if (lines.length < 2) return null
  var m = lines[lines.length - 1].match(/^(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(.+)$/)
  if (!m || !(Number(m[2]) > 0)) return null
  return {
    device: m[1], total: Number(m[2]) * 1024, used: Number(m[3]) * 1024,
    available: Number(m[4]) * 1024, percent: Number(m[5]), mount: m[6]
  }
}

// ------------------------------------------------------------------- history

var HISTORY_MS = 900000
var HISTORY_LIMIT = 901

// Appends a timestamped sample, dropping anything older than 15 minutes and
// anything not strictly before it (a wall-clock jump backwards would
// otherwise leave the line doubling back on itself).
function append(history, sample) {
  var cutoff = sample.time - HISTORY_MS
  return history.filter(function(p) { return p.time > cutoff && p.time < sample.time })
    .concat([sample]).slice(-HISTORY_LIMIT)
}

function series(history, key, seconds, now) {
  return history.filter(function(p) { return p.time >= now - seconds * 1000 }).map(function(p) {
    return { time: p.time, value: number(p[key]) ? p[key] : null }
  })
}

// Mean of the available samples, not a time-weighted average.
function stats(points) {
  var values = points.filter(function(p) { return number(p.value) }).map(function(p) { return p.value })
  if (!values.length) return { average: null, peak: null }
  return {
    average: values.reduce(function(a, b) { return a + b }, 0) / values.length,
    peak: Math.max.apply(null, values)
  }
}

// ----------------------------------------------------------------- processes

// CPU is the change in utime + stime over elapsed monotonic time, so 100%
// means one fully busy logical core. PID plus start time identifies a
// process, so a reused PID cannot inherit someone else's counters.
function processRates(previous, current) {
  if (!current || !Array.isArray(current.processes)) return []
  var old = {}, dt = previous ? current.time - previous.time : 0
  if (previous && Array.isArray(previous.processes))
    previous.processes.forEach(function(p) { old[p.pid + ':' + p.start] = p })
  return current.processes.map(function(p) {
    var a = old[p.pid + ':' + p.start], delta = a ? p.ticks - a.ticks : -1
    return {
      pid: p.pid, name: p.name, user: p.user, state: p.state, rss: p.rss,
      cpu: dt > 0 && delta >= 0 && current.hz > 0 ? delta / current.hz / dt * 100 : null
    }
  })
}

function filterProcesses(rows, query, sort) {
  var q = String(query || '').toLowerCase().trim()
  var key = sort === 'memory' ? 'rss' : 'cpu'
  return rows.filter(function(p) {
    return !q || (p.name + ' ' + p.user + ' ' + p.pid).toLowerCase().indexOf(q) !== -1
  }).sort(function(a, b) {
    if (sort === 'name') return a.name.localeCompare(b.name) || a.pid - b.pid
    return (number(b[key]) ? b[key] : -1) - (number(a[key]) ? a[key] : -1) || a.pid - b.pid
  })
}

if (typeof module !== 'undefined') module.exports = {
  number: number, percent: percent, bytes: bytes, rate: rate, duration: duration,
  cpuTimes: cpuTimes, busy: busy, coreUsage: coreUsage, memory: memory,
  pressure: pressure, load: load, uptime: uptime, disk: disk,
  append: append, series: series, stats: stats,
  processRates: processRates, filterProcesses: filterProcesses
}
