/*
Upstream's own answers for the fix phase, batch F3b: a CHORD series'
selection as selectchanged reports it.

A chord series is built by createGraphFromNodeEdge, which links its node
and edge data (linkSeriesData): getAllData answers both, and
getAllSelectedIndices (util/states.ts) lists the series' selected indices --
getSelectedDataIndices, the selectedMap read against the node data -- once
per data, with dataType 'node' and 'edge'. An edge selected by an action
(dataType 'edge') goes into the same map, and the map keeps the index it
was selected at (_selectedDataIndicesMap): the edge's index is listed
among the nodes', twice.

Runs the real ECharts 6.1 development build in node's server-side mode (SVG
renderer), chart._ssr = false, echarts.env.node switched off, the clock of
animation.js, Math.random the port's xorshift32.

  node tools/advchart-oracle/chord-select.js

writes tests/fixtures/advchart-chord-select.json (ORACLE_OUT overrides).
Ends with process.exit().

Top level: source, version, cases[], guards[]. A case: id, note, option,
steps[] (each {action}); after each step the events the action published --
{type, payload} with the payload as upstream hands it to a handler (JSON).
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};
const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-chord-select.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => {};
  console.error = () => {};
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const EVENTS = ['select', 'unselect', 'toggleselect', 'selectchanged'];
const CN = [{ name: 'A' }, { name: 'B' }, { name: 'C' }, { name: 'D' }];
const CL = [{ source: 'A', target: 'B', value: 3 }, { source: 'B', target: 'C', value: 2 },
  { source: 'C', target: 'A', value: 4 }, { source: 'D', target: 'A', value: 1 }];
const chord = more => ({ animation: false, series: [Object.assign({ type: 'chord', data: CN, links: CL }, more)] });

const CASES = [
  { id: 'chord-multiple', note: "selectedMode multiple: select node 1, then node 3 too, an edge (dataType 'edge', index 0), toggle node 1 off, unselect everything named -- each selectchanged lists the node indices twice, as node and as edge",
    option: chord({ selectedMode: 'multiple' }),
    steps: [{ action: { type: 'select', seriesIndex: 0, dataIndex: 1 } },
      { action: { type: 'select', seriesIndex: 0, dataIndex: 3 } },
      { action: { type: 'select', seriesIndex: 0, dataType: 'edge', dataIndex: 0 } },
      { action: { type: 'toggleSelect', seriesIndex: 0, dataIndex: 1 } },
      { action: { type: 'unselect', seriesIndex: 0, dataIndex: [1, 3] } }] },
  { id: 'chord-single', note: 'selectedMode single beside a pie: select chord node 2, then node 0 (the first leaves); the pie selects too -- one entry per data of each series',
    option: { animation: false, series: [
      { type: 'chord', data: CN, links: CL, selectedMode: 'single', center: ['30%', '50%'], radius: ['20%', '25%'] },
      { type: 'pie', selectedMode: true, center: ['75%', '50%'], radius: '20%', data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }] }] },
    steps: [{ action: { type: 'select', seriesIndex: 0, dataIndex: 2 } },
      { action: { type: 'select', seriesIndex: 1, dataIndex: 1 } },
      { action: { type: 'select', seriesIndex: 0, dataIndex: 0 } }] },
];

function runCase(c) {
  NOW = T0;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 400, height: 300 });
  chart._ssr = false;
  try {
    const got = [];
    EVENTS.forEach(t => chart.on(t, p => got.push({ type: t, payload: clone(p) })));
    quiet(() => chart.setOption(c.option));
    const out = { id: c.id, note: c.note, option: clone(c.option), steps: [] };
    c.steps.forEach(st => {
      got.length = 0;
      quiet(() => chart.dispatchAction(clone(st.action)));
      out.steps.push({ action: clone(st.action), events: got.splice(0) });
    });
    return out;
  } finally {
    chart.dispose();
  }
}

function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const sc = (id, k) => out.cases.find(q => q.id === id).steps[k].events.find(e => e.type === 'selectchanged');
  guard('a chord selection is listed as node and as edge', (() => {
    const e = sc('chord-multiple', 0);
    return e && e.payload.selected.length === 2 && e.payload.selected[0].dataType === 'node'
      && e.payload.selected[1].dataType === 'edge' && e.payload.selected[1].dataIndex.join() === '1';
  })());
  guard('an edge selected by an action adds its own index', (() => {
    const e = sc('chord-multiple', 2);
    return e && e.payload.selected[0].dataIndex.join() === '1,3,0' && e.payload.selected[1].dataIndex.join() === '1,3,0';
  })());
  guard('the nodes unselected: the edge is still listed', (() => {
    const e = sc('chord-multiple', 4);
    return e && e.payload.selected.length === 2 && e.payload.selected[0].dataIndex.join() === '0';
  })());
  guard('beside a pie: three entries', (() => {
    const e = sc('chord-single', 1);
    return e && e.payload.selected.length === 3;
  })());
  return g;
}

function generate() {
  const out = { source: DIST, version: echarts.version, cases: CASES.map(runCase) };
  out.guards = guards(out);
  return out;
}
let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
