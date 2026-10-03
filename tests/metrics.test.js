const { test } = require('node:test')
const assert = require('node:assert/strict')
const M = require('../Metrics.js')

test('memory distinguishes cache, available memory and disabled swap', () => {
  const m = M.memory('MemTotal: 1000 kB\nMemAvailable: 300 kB\nCached: 100 kB\nSReclaimable: 20 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB')
  assert.equal(m.available, 300 * 1024)
  assert.equal(m.cache, 120 * 1024)
  assert.equal(m.swapUsed, 0)
  assert.equal(M.memory('MemTotal: 1000 kB'), null)
  assert.equal(M.memory('MemTotal: 1000 kB\nMemAvailable: 500 kB').swapUsed, null)
})
test('per-core deltas exclude guest counters and handle hotplug', () => {
  const a = M.cores('cpu 0 0 0 0\ncpu0 100 0 0 100 0 0 0 0 900 0')
  const b = M.cores('cpu0 150 0 0 150 0 0 0 0 999 0\ncpu2 1 0 0 1')
  assert.equal(M.coreUsage(a, b)[0].value, 50)
  assert.equal(M.coreUsage(a, b)[1].value, null)
  assert.equal(M.coreUsage(b, a)[0].value, null)
  assert.deepEqual(M.cores('cpu1 broken data'), {})
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
test('health warns on genuine pressure and does not claim healthy before sampling', () => {
  assert.equal(M.health({},{}).title,'Collecting readings')
  assert.equal(M.health({cpu:10,mem:{percent:40}},{}).title,'Running smoothly')
  assert.equal(M.health({cpu:10,mem:{percent:95}},{}).issues.length,1)
  assert.equal(M.health({cpu:10,mem:{percent:40}},{memory:{avg10:12}}).title,'Needs attention')
})
test('formatters distinguish missing data and zero', () => {
  assert.equal(M.percent(null),'—'); assert.equal(M.percent(0),'0.0%')
  assert.equal(M.bytes(null),'—'); assert.equal(M.bytes(1024),'1.0 KiB')
  assert.equal(M.duration(90061),'1d 1h')
})
