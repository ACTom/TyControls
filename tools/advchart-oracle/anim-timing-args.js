/*
Upstream's own answers for round-2 batch R2-J3: WHAT AN ANIMATION TIMING
FUNCTION IS HANDED. animationDelay, animationDuration and their Update twins
may be functions; basicTransition.ts getAnimationConfig calls a delay as
delay(dataIndex, extraDelayParams) and a duration as duration(dataIndex) --
dataIndex the one the element's animateOrSetProps call names (undefined or
null for an element of no item: a clip path, an axis, a legend), and
extraDelayParams what the animatable model's getAnimationDelayParams answers
for the element (only a pictorial bar's item model has one: {index, count},
a repeated glyph's place in its column and the column's repeat count,
undefined fields on any other element of the bar), else null. LineView calls
the series' delay and duration with null once and the delay with the
symbol's index per symbol.

Each case writes the four keys at the ROOT of its option (so every series,
every component and every marker inherits them) as functions that write
down their arguments, sets the option (animation on) and draws it, then sets
the case's update (new data, as a page's setInterval would) and draws it.
Per phase and per key, the distinct calls as
  'i:<dataIndex> p:<extraDelayParams>'
-- dataIndex 'n:<integer>' or 'u' (null / undefined), the second argument
'u' (null / undefined / not passed) or 'j:<json>' with the keys sorted and
the numbers hex ('j:{}' for an object with no index and no count).

The port writes the four keys as '@ad' (animationDelay), '@aD'
(animationDuration), '@adu' (animationDelayUpdate), '@aDu'
(animationDurationUpdate); the functions answer a delay of 0 for an index
and a duration of 300 (so every element animates), whatever they are handed.

Runs the real ECharts 6.1 build (ECHARTS_DIST) in node's server-side mode as
gallery-callbacks.js does (SVG renderer, chart._ssr false before the first
setOption, env.node off, the clock of animation.js, Math.random the port's
xorshift32, zrender's width table measuring every string). Every chart
600 x 400.

  node tools/advchart-oracle/anim-timing-args.js

writes tests/fixtures/advchart-anim-timing-args.json (ORACLE_OUT overrides).
Top level: source, version, seed, W, H, measure {firstCode, ratio[]},
notes[], cases[] {id, note, option, update, enter {key: [call...]},
updated {key: [call...]}}, guards[]. Ends with process.exit().
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-timing-args.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => {};
  console.error = () => {};
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

const FIRST_CODE = 32;
const LAST_CODE = 126;
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk() {
  rngState = SEED;
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function paint(chart) {
  chart._onframe();
  chart.getZr().storage.getDisplayList(true);
  quiet(() => chart.renderToSVGString());
}

// [R2-I7] null 'z', undefined 'u': a handler tells them apart (null * 10
// is 0, undefined * 10 NaN)
function reprIndex(v) {
  if (v === null) return 'z';
  if (v === undefined) return 'u';
  return Number.isInteger(v) ? 'n:' + v : 'n:' + hex(v);
}
function deep(v) {
  if (typeof v === 'number') return hex(v);
  if (Array.isArray(v)) return v.map(deep);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) {
      if (v[k] === undefined) continue;
      o[k] = deep(v[k]);
    }
    return o;
  }
  return v;
}
function reprParams(v) {
  if (v === undefined || v === null) return 'u';
  return 'j:' + JSON.stringify(deep(v));
}

const KEYS = {
  ad: 'animationDelay', aD: 'animationDuration',
  adu: 'animationDelayUpdate', aDu: 'animationDurationUpdate',
};

// '@ad' and the rest turned into recording functions
function materialize(v, logOf) {
  if (Array.isArray(v)) return v.map(x => materialize(x, logOf));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      const s = v[k];
      if (typeof s === 'string' && s[0] === '@' && KEYS[s.slice(1)]) {
        const key = KEYS[s.slice(1)];
        const isDelay = /Delay/.test(key);
        o[k] = function (...args) {
          const log = logOf();
          (log[key] = log[key] || new Set()).add('i:' + reprIndex(args[0]) + ' p:' + reprParams(args[1]));
          // [R2-I7] and in order, where the case asks for it
          if (log.__seq) log.__seq.push(key + ' i:' + reprIndex(args[0]) + ' p:' + reprParams(args[1]));
          return isDelay ? 0 : 300;
        };
      }
      else o[k] = materialize(s, logOf);
    }
    return o;
  }
  return v;
}
function sortedLog(log) {
  const out = {};
  Object.keys(log).sort().forEach(k => { if (k !== '__seq') out[k] = Array.from(log[k]).sort(); });
  return out;
}

const T = { animationDelay: '@ad', animationDuration: '@aD', animationDelayUpdate: '@adu', animationDurationUpdate: '@aDu' };
const cat = ['A', 'B', 'C', 'D', 'E'];

const CASES = [
  { id: 'line', seq: true, note: 'a line with symbols on a category axis: the line clip and the series delay called with null, each symbol with its index; an update moves the points',
    option: { xAxis: { type: 'category', data: cat }, yAxis: {}, series: [{ type: 'line', data: [3, 5, 2, 6, 4] }] },
    update: { series: [{ data: [4, 2, 6, 3, 5] }] } },
  { id: 'bar', note: 'a bar series and a legend: each bar at its index; the update changes the values',
    option: { legend: {}, xAxis: { type: 'category', data: cat }, yAxis: {}, series: [{ type: 'bar', name: 'b', data: [3, 5, 2, 6, 4] }] },
    update: { series: [{ data: [4, 2, 6, 3, 5] }] } },
  { id: 'scatter', note: 'scatter symbols on value axes',
    option: { xAxis: {}, yAxis: {}, series: [{ type: 'scatter', data: [[1, 3], [2, 5], [3, 2], [4, 6]] }] },
    update: { series: [{ data: [[1, 4], [2, 2], [3, 6], [4, 3]] }] } },
  { id: 'pie', note: 'a pie with its labels',
    option: { series: [{ type: 'pie', data: [{ value: 3, name: 'a' }, { value: 5, name: 'b' }, { value: 2, name: 'c' }] }] },
    update: { series: [{ data: [{ value: 4, name: 'a' }, { value: 2, name: 'b' }, { value: 6, name: 'c' }] }] } },
  { id: 'funnel', note: 'a funnel',
    option: { series: [{ type: 'funnel', data: [{ value: 30, name: 'a' }, { value: 50, name: 'b' }, { value: 20, name: 'c' }] }] },
    update: { series: [{ data: [{ value: 40, name: 'a' }, { value: 20, name: 'b' }, { value: 60, name: 'c' }] }] } },
  { id: 'gauge', note: 'a gauge: its pointer and progress',
    option: { series: [{ type: 'gauge', progress: { show: true }, data: [{ value: 40 }] }] },
    update: { series: [{ data: [{ value: 70 }] }] } },
  { id: 'radar', note: 'a radar',
    option: { radar: { indicator: [{ max: 10 }, { max: 10 }, { max: 10 }] }, series: [{ type: 'radar', data: [{ value: [3, 5, 7] }] }] },
    update: { series: [{ data: [{ value: [6, 2, 4] }] }] } },
  { id: 'pictorial', note: 'pictorial bars: a repeated column (each glyph its index and the repeat count), a single glyph and a clipped repeat (the clip path: an object with neither)',
    option: { xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { max: 100 },
      series: [{ type: 'pictorialBar', symbol: 'rect', symbolSize: [20, 8], symbolMargin: 2,
        data: [{ value: 40, symbolRepeat: true }, { value: 60 }, { value: 30, symbolRepeat: true, symbolClip: true }] }] },
    update: { series: [{ data: [{ value: 60, symbolRepeat: true }, { value: 30 }, { value: 50, symbolRepeat: true, symbolClip: true }] }] } },
  { id: 'pictorial-shrink', note: '[r2v] a repeated column whose count falls: the glyphs past the new count shrink to nothing, '
      + 'each handed {index, count} with the NEW count',
    option: { xAxis: { type: 'category', data: ['a'] }, yAxis: { max: 100 },
      series: [{ type: 'pictorialBar', symbol: 'rect', symbolSize: [20, 8], symbolMargin: 2,
        data: [{ value: 70, symbolRepeat: true }] }] },
    update: { series: [{ data: [{ value: 40, symbolRepeat: true }] }] } },
  { id: 'graph', note: 'a graph of three nodes and two edges, no layout',
    option: { series: [{ type: 'graph', layout: 'none', label: { show: true },
      data: [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 50, y: 100 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] }] },
    update: { series: [{ data: [{ name: 'a', x: 20, y: 10 }, { name: 'b', x: 90, y: 60 }, { name: 'c', x: 40, y: 90 }] }] } },
  { id: 'candle-box', note: 'a candlestick and a boxplot',
    option: { xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {},
      series: [{ type: 'candlestick', data: [[2, 4, 1, 5], [4, 3, 2, 6]] }, { type: 'boxplot', data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }] },
    update: { series: [{ data: [[3, 4, 1, 5], [4, 2, 1, 6]] }, { data: [[1, 2, 3, 4, 6], [2, 3, 4, 5, 7]] }] } },
  { id: 'heatmap', note: 'a cartesian heatmap',
    option: { xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['x', 'y'] }, visualMap: { min: 0, max: 10, show: false },
      series: [{ type: 'heatmap', data: [[0, 0, 1], [0, 1, 5], [1, 0, 7], [1, 1, 3]] }] },
    update: { series: [{ data: [[0, 0, 4], [0, 1, 2], [1, 0, 9], [1, 1, 6]] }] } },
  { id: 'tree', note: 'a tree',
    option: { series: [{ type: 'tree', data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b', children: [{ name: 'c' }] }] }] }] },
    update: { series: [{ data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }] } },
  { id: 'treemap', note: 'a treemap',
    option: { series: [{ type: 'treemap', data: [{ name: 'a', value: 6 }, { name: 'b', value: 4, children: [{ name: 'c', value: 3 }, { name: 'd', value: 1 }] }] }] },
    update: { series: [{ data: [{ name: 'a', value: 3 }, { name: 'b', value: 7, children: [{ name: 'c', value: 5 }, { name: 'd', value: 2 }] }] }] } },
  { id: 'treemap-upper', note: '[r2v] a treemap showing its parents\' upper labels (not the root\'s: levels[0] hides it): after a '
      + 'merge LabelManager updateProps every label not ignored -- a parent\'s only label is its upper one, the only call at its row',
    option: { series: [{ type: 'treemap', upperLabel: { show: true, height: 20 }, levels: [{ upperLabel: { show: false } }], breadcrumb: { show: false },
      data: [{ name: 'a', value: 6 }, { name: 'b', children: [{ name: 'c', value: 3 }, { name: 'd', value: 1 }] }] }] },
    update: { series: [{ data: [{ name: 'a', value: 3 }, { name: 'b', children: [{ name: 'c', value: 5 }, { name: 'd', value: 2 }] }] }] } },
  { id: 'sunburst', note: 'a sunburst',
    option: { series: [{ type: 'sunburst', data: [{ name: 'a', value: 6 }, { name: 'b', value: 4, children: [{ name: 'c', value: 3 }] }] }] },
    update: { series: [{ data: [{ name: 'a', value: 3 }, { name: 'b', value: 7, children: [{ name: 'c', value: 5 }] }] }] } },
  { id: 'markers', note: 'a line with a markPoint, a markLine and a markArea',
    option: { xAxis: { type: 'category', data: cat }, yAxis: {}, series: [{ type: 'line', data: [3, 5, 2, 6, 4],
      markPoint: { data: [{ type: 'max' }] }, markLine: { data: [{ type: 'average' }] }, markArea: { data: [[{ xAxis: 'A' }, { xAxis: 'B' }]] } }] },
    update: { series: [{ data: [4, 2, 6, 3, 5] }] } },
];

function runCase(c) {
  const enter = {};
  const update = {};
  // [R2-I7] every call in order, for the cases that ask (a series' delay
  // with null before its symbols')
  if (c.seq) {
    Object.defineProperty(enter, '__seq', { value: [], enumerable: false });
    Object.defineProperty(update, '__seq', { value: [], enumerable: false });
  }
  let cur = enter;
  const chart = mk();
  try {
    quiet(() => chart.setOption(materialize(Object.assign({}, T, c.option), () => cur)));
    paint(chart);
    cur = update;
    NOW += 50;
    quiet(() => chart.setOption(materialize(c.update, () => cur)));
    paint(chart);
  } finally {
    chart.dispose();
  }
  const rec = { id: c.id, note: c.note, option: Object.assign({}, T, c.option), update: c.update,
    enter: sortedLog(enter), updated: sortedLog(update) };
  if (c.seq) {
    rec.enterSeq = enter.__seq.slice();
    rec.updatedSeq = update.__seq.slice();
  }
  return rec;
}

function guards(out) {
  const g = [];
  const add = (name, ok) => g.push({ name, ok: !!ok });
  const c = id => out.cases.find(x => x.id === id);
  add('pictorial: a glyph hands {index, count}', c('pictorial').enter.animationDelay.some(s => /"index"/.test(s) && /"count"/.test(s)));
  add('pictorial: the clip path hands an empty object', c('pictorial').enter.animationDelay.some(s => /p:j:\{\}/.test(s)));
  add('pictorial-shrink: the shrinking glyphs hand the new count', (() => {
    const counts = new Set();
    c('pictorial-shrink').updated.animationDelayUpdate.forEach(s => { const m = /"count":"([0-9a-f]+)"/.exec(s); if (m) counts.add(m[1]); });
    return counts.size === 1;
  })());
  add('line: the series delay is called with null', c('line').enter.animationDelay.some(s => /^i:z p:u$/.test(s)));
  add('line: the calls in order -- the duration and the delay with null, then each symbol\'s delay',
    c('line').enterSeq[0] === 'animationDuration i:z p:u' && c('line').enterSeq[1] === 'animationDelay i:z p:u'
    && c('line').enterSeq[2] === 'animationDelay i:n:0 p:u');
  add('bar: each bar at its index', c('bar').enter.animationDelay.filter(s => /^i:n:\d p:u$/.test(s)).length >= 5);
  // a heatmap's cells have no enter animation upstream: only its update
  add('every case but the heatmap animates', out.cases.every(x => x.id === 'heatmap' || Object.keys(x.enter).length > 0));
  add('every case updates', out.cases.every(x => Object.keys(x.updated).length > 0));
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, ' + W + ' x ' + H + '; the option set at T0 and drawn, the update 50 ms later and drawn.',
      'enter / updated: per key, the distinct calls of the root\'s timing function in the first setOption and in the update.',
    ],
    cases: CASES.map(runCase),
  };
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
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (json1 === json2 ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || json1 !== json2) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
