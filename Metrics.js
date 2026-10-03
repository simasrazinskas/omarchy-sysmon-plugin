// Pure dashboard calculations. Missing data remains null, never a healthy zero.
function number(value) { return typeof value === 'number' && isFinite(value) }
function percent(value) { return number(value) ? value.toFixed(1) + '%' : '—' }
function bytes(value) {
  if (!number(value)) return '—'
  var units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  var n = Math.max(0, value), i = 0
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return n.toFixed(i === 0 ? 0 : 1) + ' ' + units[i]
}
function duration(seconds) {
  if (!number(seconds)) return '—'
  var m = Math.floor(seconds / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
  return d > 0 ? d + 'd ' + h % 24 + 'h' : h > 0 ? h + 'h ' + m % 60 + 'm' : m + 'm'
}
function memory(text) {
  var fields = {}, lines = String(text || '').split('\n')
  lines.forEach(function(line) { var m = line.match(/^(\w+):\s+(\d+)\s+kB/); if (m) fields[m[1]] = Number(m[2]) * 1024 })
  if (!(fields.MemTotal > 0) || !number(fields.MemAvailable)) return null
  return { total: fields.MemTotal, available: fields.MemAvailable,
    cache: (fields.Cached || 0) + (fields.SReclaimable || 0),
    swapTotal: number(fields.SwapTotal) ? fields.SwapTotal : null,
    swapUsed: number(fields.SwapTotal) && number(fields.SwapFree) ? Math.max(0, fields.SwapTotal - fields.SwapFree) : null }
}
function cores(text) {
  var out = {}
  String(text || '').split('\n').forEach(function(line) {
    if (!/^cpu\d+\s/.test(line)) return
    var f = line.trim().split(/\s+/), values = f.slice(1, 9).map(Number)
    if (values.length < 4 || values.some(function(v) { return !isFinite(v) || v < 0 })) return
    out[f[0]] = { total: values.reduce(function(a, b) { return a + b }, 0), idle: values[3] + (values[4] || 0) }
  })
  return out
}
function coreUsage(previous, current) {
  return Object.keys(current).map(function(key) {
    var a = previous ? previous[key] : null, b = current[key], delta = a ? b.total - a.total : 0
    return { name: key.replace('cpu', ''), value: delta > 0 && b.idle >= a.idle ? Math.max(0, Math.min(100, 100 * (1 - (b.idle - a.idle) / delta))) : null }
  })
}
function pressure(text) {
  var match = String(text || '').match(/^some\s+avg10=([\d.]+)\s+avg60=([\d.]+)\s+avg300=([\d.]+)/m)
  return match ? { avg10: Number(match[1]), avg60: Number(match[2]), avg300: Number(match[3]) } : null
}
function load(text) {
  var f = String(text || '').trim().split(/\s+/)
  if (f.length < 4 || f.slice(0, 3).some(function(v) { return !isFinite(Number(v)) })) return null
  return { one: Number(f[0]), five: Number(f[1]), fifteen: Number(f[2]), tasks: f[3] }
}
function disk(text) {
  var lines = String(text || '').trim().split('\n')
  if (lines.length < 2) return null
  var m = lines[lines.length - 1].match(/^(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(.+)$/)
  return m ? { device: m[1], total: Number(m[2]) * 1024, used: Number(m[3]) * 1024, available: Number(m[4]) * 1024, percent: Number(m[5]), mount: m[6] } : null
}
function append(history, sample) {
  var cutoff = sample.time - 900000
  return history.filter(function(p) { return p.time > cutoff && p.time < sample.time }).concat([sample]).slice(-901)
}
function series(history, key, seconds, now) {
  return history.filter(function(p) { return p.time >= now - seconds * 1000 }).map(function(p) { return { time: p.time, value: number(p[key]) ? p[key] : null } })
}
function stats(points) {
  var values = points.filter(function(p) { return number(p.value) }).map(function(p) { return p.value })
  return values.length ? { average: values.reduce(function(a,b) { return a+b }, 0) / values.length, peak: Math.max.apply(null, values) } : { average: null, peak: null }
}
function processRates(previous, current) {
  if (!current || !Array.isArray(current.processes)) return []
  var old = {}, dt = previous ? current.time - previous.time : 0
  if (previous) previous.processes.forEach(function(p) { old[p.pid + ':' + p.start] = p })
  return current.processes.map(function(p) {
    var a = old[p.pid + ':' + p.start], delta = a ? p.ticks - a.ticks : -1
    return { pid: p.pid, name: p.name, user: p.user, state: p.state, rss: p.rss,
      cpu: dt > 0 && delta >= 0 && current.hz > 0 ? delta / current.hz / dt * 100 : null }
  })
}
function filterProcesses(rows, query, sort) {
  var q = String(query || '').toLowerCase().trim()
  return rows.filter(function(p) { return !q || (p.name + ' ' + p.user + ' ' + p.pid).toLowerCase().indexOf(q) !== -1 }).slice().sort(function(a,b) {
    if (sort === 'name') return a.name.localeCompare(b.name) || a.pid - b.pid
    var key = sort === 'memory' ? 'rss' : 'cpu'
    return (number(b[key]) ? b[key] : -1) - (number(a[key]) ? a[key] : -1) || a.pid - b.pid
  })
}
function health(state, pressures) {
  var issues = [], s = state || {}, p = pressures || {}
  if (number(s.cpuTemp) && s.cpuTemp >= 90) issues.push('CPU temperature is high')
  if (s.gpu && number(s.gpu.temp) && s.gpu.temp >= 85) issues.push('GPU temperature is high')
  if (s.mem && s.mem.percent >= 90) issues.push('Memory is running low')
  if (number(s.disk) && s.disk >= 90) issues.push('Storage is nearly full')
  if (p.memory && p.memory.avg10 >= 10) issues.push('Tasks are waiting for memory')
  if (p.io && p.io.avg10 >= 10) issues.push('Tasks are waiting for I/O')
  if (p.cpu && p.cpu.avg10 >= 20) issues.push('CPU demand exceeds capacity')
  if (!issues.length && number(s.cpu) && s.cpu >= 90) issues.push('CPU is working hard')
  return { title: issues.length ? 'Needs attention' : number(s.cpu) && s.mem ? 'Running smoothly' : 'Collecting readings', issues: issues }
}
if (typeof module !== 'undefined') module.exports = {number:number,percent:percent,bytes:bytes,duration:duration,memory:memory,cores:cores,coreUsage:coreUsage,pressure:pressure,load:load,disk:disk,append:append,series:series,stats:stats,processRates:processRates,filterProcesses:filterProcesses,health:health}
