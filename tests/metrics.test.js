const { test } = require('node:test')
const assert = require('node:assert/strict')
const M = require('../Metrics.js')

// Real samples taken from a running machine, so the parsers are tested against
// the exact shapes the kernel emits.
const PROC_STAT = [
  'cpu  5130975 721 1219628 352675467 245032 288590 68337 0 0 0',
  'cpu0 259387 39 61553 17627395 12938 20826 12345 0 0 0',
  'intr 1234567890',
  ''
].join('\n')

const PROC_MEMINFO = [
  'MemTotal:       65593584 kB',
  'MemFree:        41234567 kB',
  'MemAvailable:   47000000 kB',
  'Buffers:         1234567 kB',
  ''
].join('\n')

test('cpuTimes sums the first eight counters and folds iowait into idle', () => {
  const times = M.cpuTimes(PROC_STAT)
  // guest is excluded because the kernel already counts it inside user.
  assert.equal(times.cpu.total, 5130975 + 721 + 1219628 + 352675467 + 245032 + 288590 + 68337 + 0)
  assert.equal(times.cpu.idle, 352675467 + 245032)
  assert.deepEqual(Object.keys(times), ['cpu', 'cpu0'])
  assert.deepEqual(M.cpuTimes('intr 123\nctxt 456'), {})
  assert.deepEqual(M.cpuTimes('cpu1 broken data'), {})
})
test('busy needs two samples, so the first tick reports null not zero', () => {
  assert.equal(M.busy(null, M.cpuTimes(PROC_STAT).cpu), null)
  assert.equal(M.busy({ total: 1000, idle: 900 }, { total: 1100, idle: 950 }), 50)
  assert.equal(M.busy({ total: 1000, idle: 500 }, { total: 1100, idle: 500 }), 100)
  // A counter that did not advance, or went backwards, is unknown.
  assert.equal(M.busy({ total: 1000, idle: 900 }, { total: 1000, idle: 900 }), null)
  assert.equal(M.busy({ total: 1000, idle: 900 }, { total: 1100, idle: 800 }), null)
})
test('per-core usage skips the aggregate and handles hotplug', () => {
  const a = M.cpuTimes('cpu 0 0 0 0\ncpu0 100 0 0 100 0 0 0 0 900 0')
  const b = M.cpuTimes('cpu 1 0 0 1\ncpu0 150 0 0 150 0 0 0 0 999 0\ncpu2 1 0 0 1')
  assert.deepEqual(M.coreUsage(a, b), [{ name: '0', value: 50 }, { name: '2', value: null }])
  assert.equal(M.coreUsage(b, a)[0].value, null)
  assert.deepEqual(M.coreUsage(null, {}), [])
})
test('memory uses MemAvailable rather than MemFree', () => {
  const mem = M.memory(PROC_MEMINFO)
  assert.equal(mem.total, 65593584 * 1024)
  assert.equal(mem.used, (65593584 - 47000000) * 1024)
  // MemFree would have reported a far higher usage than the machine really has.
  assert.ok(mem.percent > 28 && mem.percent < 29)
})
test('memory distinguishes cache, available memory and disabled swap', () => {
  const m = M.memory('MemTotal: 1000 kB\nMemAvailable: 300 kB\nCached: 100 kB\nSReclaimable: 20 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB')
  assert.equal(m.available, 300 * 1024)
  assert.equal(m.cache, 120 * 1024)
  assert.equal(m.swapTotal, 0)
  assert.equal(m.swapUsed, 0)
  assert.equal(M.memory('MemTotal: 1000 kB'), null)
  assert.equal(M.memory(''), null)
  assert.equal(M.memory('MemTotal: 1000 kB\nMemAvailable: 500 kB').swapUsed, null)
})
test('pressure parses some rather than full stall time', () => {
  assert.deepEqual(M.pressure('some avg10=12.34 avg60=5.00 avg300=1.00 total=333\nfull avg10=1.00 avg60=0.00 avg300=0.00 total=1'), {avg10:12.34,avg60:5,avg300:1})
  assert.equal(M.pressure(''), null)
  assert.equal(M.load(''), null)
  assert.equal(M.load('0.10 0.20 0.30 1/500 123').five, 0.2)
})
test('disk parsing keeps spaces in mountpoint and distinguishes reserved space', () => {
  const d = M.disk('Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/nvme0n1p2 1000 600 350 64% /mnt/my drive')
  assert.equal(d.mount, '/mnt/my drive'); assert.equal(d.available, 350 * 1024); assert.equal(d.percent, 64)
  assert.equal(M.disk('df: no such file'), null)
  // Pseudo filesystems report zero blocks; a percentage of nothing is unavailable.
  assert.equal(M.disk('Filesystem 1024-blocks Used Available Capacity Mounted on\nproc 0 0 0 0% /proc'), null)
})
test('uptime reads the first field and rejects garbage', () => {
  assert.equal(M.uptime('12345.67 99999.00\n'), 12345.67)
  assert.equal(M.uptime(''), null)
  assert.equal(M.uptime('nope'), null)
})
test('history is time-bounded, immutable, and retains missing samples', () => {
  const original = [{time:1,cpu:20},{time:500000,cpu:null}]
  const history = M.append(original,{time:1000000,cpu:50})
  assert.equal(original.length, 2)
  assert.equal(history.length, 2)
  assert.deepEqual(M.series(history,'cpu',900,1000000),[{time:500000,value:null},{time:1000000,value:50}])
  assert.deepEqual(M.stats(M.series(history,'cpu',900,1000000)), {average:50,peak:50})
  assert.deepEqual(M.stats([{time:1,value:null}]), {average:null,peak:null})
  assert.equal(M.append(history,{time:400000,cpu:1}).length,1)
})
function snap(time, ticks, start = '123', pid = 1) { return {time,hz:100,processes:[{pid,start,ticks,name:'firefox',rss:1024,user:'me',state:'R'}]} }
test('process CPU uses elapsed monotonic time and one-core convention', () => {
  assert.equal(M.processRates(snap(1,0),snap(3,300))[0].cpu,150)
  assert.equal(M.processRates(null,snap(3,300))[0].cpu,null)
  assert.equal(M.processRates(snap(1,100),snap(3,50))[0].cpu,null)
  assert.equal(M.processRates(snap(1,100),snap(1,300))[0].cpu,null)
})
test('PID reuse cannot become a bogus CPU spike', () => {
  assert.equal(M.processRates(snap(1,100,'old'),snap(3,1000,'new'))[0].cpu,null)
})
test('process search includes user and PID with stable sorting', () => {
  const rows = [{pid:2,name:'Browser',user:'alice',cpu:50,rss:200},{pid:1,name:'Editor',user:'bob',cpu:null,rss:500}]
  assert.equal(M.filterProcesses(rows,'BOB','cpu')[0].pid,1)
  assert.equal(M.filterProcesses(rows,'2','memory')[0].name,'Browser')
  assert.equal(M.filterProcesses(rows,'','memory')[0].pid,1)
  assert.equal(M.filterProcesses(rows,'','cpu')[0].pid,2)
  assert.equal(rows[0].pid,2)
})
test('formatters distinguish missing data and zero', () => {
  assert.equal(M.percent(null),'—'); assert.equal(M.percent(0),'0.0%')
  assert.equal(M.bytes(null),'—'); assert.equal(M.bytes(1024),'1.0 KiB')
  assert.equal(M.duration(90061),'1d 1h')
  assert.equal(M.duration(3720),'1h 2m')
  assert.equal(M.rate(null),'—'); assert.equal(M.rate(2048),'2.0 KiB/s')
})
