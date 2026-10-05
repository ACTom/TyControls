/*
Upstream's own answers for roadmap C2, batch 110: the public coordinate
conversions (convertToPixel / convertFromPixel / containPixel) and their
finder, the scatter jitter (beeswarm) on a category axis, and the
customValues of axisTick and axisLabel.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false`, server
side rendering.

  node tools/advchart-oracle/convert-jitter.js

writes tests/fixtures/advchart-convert-jitter.json (ORACLE_OUT overrides).

Math.random IS REPLACED by the xorshift32 the port uses (TyGraphRandom),
seeded with 2463534242 (TyGraphForceSeed(0)) and RESET BEFORE EVERY CHART:
upstream's jitter draws from Math.random -- `jitterOverlap: true` (the
default) always, `jitterOverlap: false` when the avoiding placement gives up
-- and the port draws the same numbers in the same order. Every draw is
checked to come from fixJitterIgnoreOverlaps and nowhere else.

-----------------------------------------------------------------------------
Numbers are the 16 hex digits of the IEEE double (big-endian, lowercase);
flags, strings and option values are plain JSON.

An INPUT value (a finder or a value handed to a conversion) is written as
`in`: the value with every number replaced by {"h": hex} -- strings, booleans
and null as they are -- so the test rebuilds the exact doubles; `text` is
JSON.stringify of it, and `textSafe` says whether every number in it prints
in at most 15 significant digits (the JSON text API can be replayed on it).

Top level: source, version, W, H, seed, notes[], cases[], guards[].

cases[]: id, kind ('convert' | 'jitter' | 'custom'), note, option,
  convert: probes[] {op ('to' | 'from' | 'contain'), finder {in, text},
           value {in, text, textSafe}, out, by?}
             by: the type of the coordinate system that answered ('grid',
                 'calendar', 'view'), on a to / from probe with an answer
             out: {k: 'none'} (undefined), {k: 'num', v: hex},
                  {k: 'arr', v: [hex...]}, {k: 'bool', v: true | false},
                  {k: 'throw'} (upstream raised a TypeError: it indexed a
                  null value)
           grids[] the cartesian areas [x, y, w, h] hex, per grid, as notes
  jitter:  draws (how many Math.random calls the render made),
           series[] {seriesIndex, type, items[] {i, layout [x, y] hex | null,
           drawn}}
  custom:  axes[] {dim, index, type, ticks {values[], coords[] (global),
           drawn[]}, splitLines {values[], coords[], drawn[]}, splitAreas
           {values[]}, labels[] {tick hex, text, x, y, hidden}}

Guards (any failure: nothing is written, exit 1): expectations read off the
source -- see guards(); and the whole fixture is generated twice
(byte-identical). process.exit() ends the run.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-convert-jitter.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------------------------------------------------------------------------
// the random numbers: the port's xorshift32
// ---------------------------------------------------------------------------
const SEED = 2463534242; // TyGraphForceSeed(0)
let rngState = SEED;
let draws = [];
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  draws.push((new Error().stack.split('\n')[2] || '').trim());
  return x / 4294967296;
};

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// an input value with its numbers as hex
function enc(v) {
  if (typeof v === 'number') return { h: hex(v) };
  if (Array.isArray(v)) return v.map(enc);
  if (v && typeof v === 'object') {
    const o = {};
    Object.keys(v).forEach(k => { o[k] = enc(v[k]); });
    return o;
  }
  return v;
}
function textSafe(v) {
  if (typeof v === 'number') return Number.isFinite(v) && Number(v.toPrecision(15)) === v;
  if (Array.isArray(v)) return v.every(textSafe);
  if (v && typeof v === 'object') return Object.keys(v).every(k => textSafe(v[k]));
  return true;
}
function input(v) {
  must(v !== undefined, 'an undefined input cannot be recorded');
  return { in: enc(v), text: JSON.stringify(v), textSafe: textSafe(v) };
}

function newChart(option) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  rngState = SEED;
  draws = [];
  chart.setOption(option);
  chart.renderToSVGString();
  return chart;
}

// the dev build warns about every finder it cannot serve; counted, not printed
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

// util/model.ts parseFinder with no options, transcribed for the bookkeeping
function PARSE_FINDER(ecModel, finderInput) {
  let finder = finderInput;
  if (typeof finderInput === 'string') { finder = {}; finder[finderInput + 'Index'] = 0; }
  const result = {};
  const qmap = new Map();
  if (finder && typeof finder === 'object') {
    Object.keys(finder).forEach(key => {
      const value = finder[key];
      if (key === 'dataIndex' || key === 'dataIndexInside') { result[key] = value; return; }
      const m = key.match(/^(\w+)(Index|Id|Name)$/) || [];
      if (!m[1] || !m[2]) return;
      if (!qmap.has(m[1])) qmap.set(m[1], {});
      qmap.get(m[1])[m[2].toLowerCase()] = value;
    });
  }
  qmap.forEach((q, mainType) => {
    let index = q.index;
    let id = q.id;
    let name = q.name;
    let models;
    if (index == null && id == null && name == null) models = [];
    else if (index === 'none' || index === false) models = [];
    else {
      if (index === 'all') index = id = name = null;
      models = ecModel.queryComponents({ mainType, index, id, name });
    }
    result[mainType + 'Models'] = models;
    result[mainType + 'Model'] = models[0];
  });
  return result;
}

function outOf(r) {
  if (r === undefined) return { k: 'none' };
  if (typeof r === 'boolean') return { k: 'bool', v: r };
  if (typeof r === 'number') return { k: 'num', v: hex(r) };
  if (Array.isArray(r) || ArrayBuffer.isView(r)) {
    const a = Array.from(r);
    must(a.every(x => typeof x === 'number'), 'a result array holds a non-number: ' + JSON.stringify(a));
    return { k: 'arr', v: a.map(hex) };
  }
  throw new OracleError('an unexpected result ' + JSON.stringify(r));
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const GRID = { left: 60, right: 40, top: 40, bottom: 50, outerBoundsMode: 'none' };
const GRIDF = { left: 57.5, right: 41, top: 33, bottom: 47.25, outerBoundsMode: 'none' };
const CATS5 = ['A', 'B', 'C', 'D', 'E'];
const base = extra => Object.assign({ animation: false, grid: GRID }, extra);

// probes: [op, finder, value]; a function gets the chart and returns a list
const P = (op, finder, value) => ({ op, finder, value });

// the points every grid is probed at: its corners, just outside, the centre
function gridPoints(chart, gi) {
  const g = chart.getModel().getComponent('grid', gi || 0).coordinateSystem;
  const c = g.getCartesians()[0];
  const a = c.getArea();
  const r = [a.x, a.y, a.x + a.width, a.y + a.height];
  return [
    [r[0], r[1]], [r[2], r[3]], [r[0], r[3]], [r[2], r[1]],
    [r[0] - 1e-9, r[1]], [r[2] + 0.5, r[3]], [r[0], r[1] - 0.25], [r[2], r[3] + 1],
    [(r[0] + r[2]) / 2, (r[1] + r[3]) / 2], [r[0] + 0.3, r[1] + 7.7],
  ];
}

// the finder forms, against a chart with series 0..2 (ids s0 s1 s2, names
// first second third) on grid 0 with id 'g0'
const FINDERS = [
  'series', 'grid', 'xAxis', 'yAxis', 'foo', '', 'seriesIndex',
  { seriesIndex: 0 }, { seriesIndex: 1 }, { seriesIndex: 2 }, { seriesIndex: 9 }, { seriesIndex: -1 },
  { seriesIndex: 1.5 }, { seriesIndex: '1' }, { seriesIndex: '01' }, { seriesIndex: [2, 0] }, { seriesIndex: [[1]] },
  { seriesIndex: 'all' }, { seriesIndex: 'none' }, { seriesIndex: false }, { seriesIndex: null }, { seriesIndex: true },
  { seriesId: 's1' }, { seriesId: ['s2', 's0'] }, { seriesId: 5 }, { seriesId: [5] }, { seriesId: ['5'] },
  { seriesId: 'nope' }, { seriesName: 'second' }, { seriesName: ['third'] }, { seriesName: 7 },
  { seriesIndex: null, seriesId: 's2' }, { seriesIndex: 0, seriesId: 's2' }, { seriesId: null, seriesName: 'third' },
  { gridIndex: 0 }, { gridId: 'g0' }, { gridName: 'G' }, { gridIndex: 1 }, { gridIndex: 'all' },
  { xAxisIndex: 0 }, { yAxisIndex: 0 }, { xAxisIndex: 0, yAxisIndex: 0 }, { xAxisId: 'xa' }, { yAxisName: 'Y' },
  { xAxisIndex: 3 }, { xAxisIndex: 0, gridIndex: 0 }, { xAxisIndex: 0, seriesIndex: 1 },
  { dataIndex: 2 }, { dataIndex: 2, seriesIndex: 0 }, { foo: 1 }, { Index: 0 }, { seriesindex: 0 }, 5, null,
];

const CONVERT = [];
const addConvert = (id, note, option, probes) => CONVERT.push({ id, kind: 'convert', note, option, probes });

// ---- every finder form, on two value axes ----
addConvert('cv-finders', 'two value axes, three series: every finder form for each op', base({
  grid: Object.assign({ id: 'g0', name: 'G' }, GRID),
  xAxis: { type: 'value', id: 'xa', min: 0, max: 10 }, yAxis: { type: 'value', name: 'Y', min: -20, max: 80 },
  series: [
    { type: 'scatter', id: 's0', name: 'first', data: [[1, 2], [3, 40]] },
    { type: 'line', id: 's1', name: 'second', data: [[2, 10], [8, 50]] },
    { type: 'scatter', id: '5', name: 'third', data: [[5, 5]] },
  ],
}), chart => {
  const out = [];
  FINDERS.forEach(f => {
    out.push(P('to', f, [3, 40]));
    out.push(P('to', f, 7.25));
    out.push(P('from', f, [100.5, 200.25]));
    out.push(P('from', f, 300));
    out.push(P('contain', f, [100.5, 200.25]));
    out.push(P('contain', f, [10, 10]));
  });
  return out;
});

// ---- the values a cartesian takes ----
const VALUES_XY = [
  [3, 40], [0, 40], ['3', '4'], [0, -20], [10, 80], [-3.5, 1000], [3.3333333333333335, 7.1], [1e-7, 1e21], ['3', '40'], ['', 40], [3, ''],
  [null, 40], [3, null], [3], [], 3, '34', 'ab', [true, false], [[3], 40], [[], 40], [[1, 2], 40], [{ a: 1 }, 40],
  ['0x10', 40], [' 7 ', '\t40\n'], ['Infinity', 40], ['-Infinity', 4], ['1e400', 40], ['abc', 40], [3, 40, 99],
  null, true, { 0: 3, 1: 40 },
];
const VALUES_PX = [
  [100.5, 200.25], [60, 40], [560, 350], [59.999, 350.0001], [0, 0], [-1e9, 1e9], ['100', '200'], ['', 200], [null, 200],
  [100], [], 100, '12', [true, 200], [[100], 200], [[], 200], ['Infinity', 200], ['abc', 200], [100, 200, 3], null,
  [{ a: 1 }, 2],
];
const SCALARS = [3, 3.75, -2, 0, '7', '', null, true, false, [4], [], [4, 5], 'abc', 'Infinity', [[2]], { a: 1 }, 1e300];

function valueProbes(chart, finderXY, axisFinders, extraXY, extraPx, extraScalar) {
  const out = [];
  VALUES_XY.concat(extraXY || []).forEach(v => out.push(P('to', finderXY, v)));
  VALUES_PX.concat(extraPx || []).forEach(v => out.push(P('from', finderXY, v)));
  gridPoints(chart).forEach(p => {
    out.push(P('from', finderXY, p));
    out.push(P('contain', finderXY, p));
  });
  (axisFinders || []).forEach(af => {
    SCALARS.concat(extraScalar || []).forEach(v => out.push(P('to', af, v)));
    [100.5, 60, 560, 350, '100', null, [200], 'abc', [1, 2]].forEach(v => out.push(P('from', af, v)));
  });
  // round trips: a datum to a pixel and back
  return out;
}
function roundTrips(chart, finder, data) {
  const out = [];
  data.forEach(d => {
    out.push(P('to', finder, d));
    const px = quiet(() => chart.convertToPixel(finder, d));
    if (Array.isArray(px)) out.push(P('from', finder, px));
  });
  return out;
}

addConvert('cv-value', 'value x and y: the affine fast path (ToNumber of each element) and the per-axis path', base({
  xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: -20, max: 80 },
  series: [{ type: 'scatter', data: [[1, 2], [3, 40]] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }, { yAxisIndex: 0 }])
  .concat(roundTrips(chart, 'grid', [[1, 2], [3.3, 7.7], [9.99, -19.5]])));

addConvert('cv-value-frac', 'value axes on a fractional grid, nice extents', base({
  grid: GRIDF,
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'scatter', data: [[0.3, 12], [7.7, 93], [4.1, -8]] }],
}), chart => valueProbes(chart, 'grid', [{ xAxisIndex: 0 }, { yAxisIndex: 0 }])
  .concat(roundTrips(chart, { seriesIndex: 0 }, [[0.3, 12], [7.7, 93], [4.1, -8], [1 / 3, 2 / 3]])));

addConvert('cv-category', 'category x, value y: names and ordinals, rounding, unknown names', base({
  xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value', min: 0, max: 50 },
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }, { yAxisIndex: 0 }],
  [['B', 30], ['E', 0], ['Z', 30], [1, 30], [1.4, 30], [1.5, 30], [2.5, 30], [-0.5, 30], [7, 30], ['1', 30], [[2], 30], [true, 30]],
  [[61, 300], [119.9, 300], [120, 300], [179.99, 200], [400.01, 200], [559, 200]],
  ['C', 'Z', 2.5, -0.4, 4.6, 6])
  .concat(roundTrips(chart, 'grid', [['A', 5], ['C', 36], [4, 10]])));

addConvert('cv-category-nogap', 'category x with boundaryGap false', base({
  xAxis: { type: 'category', data: CATS5, boundaryGap: false }, yAxis: { type: 'value', min: 0, max: 50 },
  series: [{ type: 'line', data: [5, 20, 36, 10, 10] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }],
  [['B', 30], ['D', 30], [1.49, 30]], [[150, 300], [209.9, 200], [210, 200]], ['C', 3.49, 3.5]));

addConvert('cv-category-y', 'category y, value x', base({
  yAxis: { type: 'category', data: CATS5 }, xAxis: { type: 'value', min: 0, max: 50 },
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}), chart => valueProbes(chart, 'series', [{ yAxisIndex: 0 }], [[30, 'B'], [30, 'Z'], [30, 3.7]], [[300, 100], [300, 349]], ['D', 0.2]));

const T0 = Date.UTC(2024, 0, 1);
const DAY = 86400000;
addConvert('cv-time', 'time x, value y: dates as text, the fast path takes the raw number, the per-axis path rounds', base({
  xAxis: { type: 'time' }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: [[T0, 3], [T0 + DAY, 8], [T0 + 5 * DAY, 4]] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }],
  [['2024-01-03T00:00:00Z', 5], ['2024-01-03T06:30:00+02:00', 5], ['2024-01-03T00:00:00.123Z', 5], [T0, 5], [T0 + 0.4, 5],
    [T0 + 0.6, 5], ['2024-01-03T00:00:00Z', null], ['2024-13-03', 5], [String(T0 + DAY), 5], [true, 5]],
  [[300, 200]], ['2024-01-02T12:00:00Z', T0 + 0.5, T0 + 2.5 * DAY, '2024-01-02', 'x'])
  .concat(roundTrips(chart, 'grid', [[T0 + DAY, 8], [T0 + 2.5 * DAY, 4.5]])));

addConvert('cv-log', 'log y, value x', base({
  xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'log', min: 1, max: 10000 },
  series: [{ type: 'line', data: [[1, 3], [5, 300], [9, 7000]] }],
}), chart => valueProbes(chart, 'series', [{ yAxisIndex: 0 }], [[5, 100], [5, 0], [5, -10], [5, 1e5]], [[300, 100]],
  [10, 1000, 0.5, 0, -1])
  .concat(roundTrips(chart, 'grid', [[5, 300], [2, 2]])));

addConvert('cv-inverse', 'inverse x (value) and inverse y (category)', base({
  xAxis: { type: 'value', inverse: true, min: 0, max: 10 }, yAxis: { type: 'category', inverse: true, data: CATS5 },
  series: [{ type: 'scatter', data: [[1, 'A'], [7, 'D']] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }, { yAxisIndex: 0 }], [[2, 'C'], [11, 'E']], [[100, 100]], ['B', 3.4])
  .concat(roundTrips(chart, 'grid', [[1, 'A'], [7, 3]])));

addConvert('cv-datazoom', 'dataZoom windows on both axes: the conversions read the zoomed extents', base({
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'] }, yAxis: { type: 'value' },
  dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 20, end: 70 }, { type: 'inside', yAxisIndex: 0, startValue: 10, endValue: 60 }],
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10, 50, 60, 15, 30, 44] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }, { yAxisIndex: 0 }], [['a', 5], ['c', 30], ['h', 70], [9, 0]], [], ['b', 'c', 'f', 8])
  .concat(roundTrips(chart, 'grid', [['c', 36], ['e', 10]])));

addConvert('cv-datazoom-value', 'a value x zoomed by percentage (filterMode none)', base({
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 12.5, end: 81.3, filterMode: 'none' }],
  series: [{ type: 'scatter', data: [[0, 3], [37, 8], [100, 4], [61.7, 9]] }],
}), chart => valueProbes(chart, 'series', [{ xAxisIndex: 0 }]).concat(roundTrips(chart, 'grid', [[37, 8], [61.7, 9]])));

// ---- several grids and axes ----
addConvert('cv-multi', 'two grids; grid 0 with two x axes and two y axes; series on each pair', {
  animation: false,
  grid: [{ left: 60, right: 340, top: 40, bottom: 50, outerBoundsMode: 'none', id: 'left' },
    { left: 340, right: 40, top: 60, bottom: 80, outerBoundsMode: 'none', id: 'right' }],
  xAxis: [{ type: 'value', min: 0, max: 10 }, { type: 'category', data: CATS5, position: 'top' },
    { type: 'value', gridIndex: 1, min: -5, max: 5, id: 'xr' }],
  yAxis: [{ type: 'value', min: 0, max: 100 }, { type: 'value', min: 0, max: 1, position: 'right' },
    { type: 'category', gridIndex: 1, data: ['p', 'q', 'r'] }],
  series: [
    { type: 'scatter', data: [[1, 10]] },
    { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [0.1, 0.5, 0.9, 0.2, 0.3] },
    { type: 'scatter', xAxisIndex: 2, yAxisIndex: 2, data: [[-1, 'q']] },
    { type: 'line', xAxisIndex: 0, yAxisIndex: 1, data: [[2, 0.2], [8, 0.8]] },
  ],
}, chart => {
  const out = [];
  const fs = [{ seriesIndex: 0 }, { seriesIndex: 1 }, { seriesIndex: 2 }, { seriesIndex: 3 }, { xAxisIndex: 1 }, { yAxisIndex: 1 },
    { xAxisIndex: 2 }, { yAxisIndex: 2 }, { xAxisIndex: 0, yAxisIndex: 1 }, { xAxisIndex: 1, yAxisIndex: 0 },
    { xAxisIndex: 0, yAxisIndex: 2 }, { xAxisIndex: 2, yAxisIndex: 2 }, { gridIndex: 1 }, { gridId: 'right' }, { gridIndex: 0 },
    { xAxisId: 'xr' }, { gridIndex: 'all' }, { seriesIndex: 'all' }, { seriesIndex: [2, 1] }, { gridIndex: [1, 0] }];
  fs.forEach(f => {
    [[1, 10], ['C', 0.5], [-1, 'q'], [3, 'r'], 2, 'C', 'q', -2.5].forEach(v => out.push(P('to', f, v)));
    [[100, 100], [450, 200], [300, 300], 150, 250].forEach(v => out.push(P('from', f, v)));
    [[100, 100], [450, 200], [300, 300], [339.9, 61], [340, 60], [560, 320]].forEach(v => out.push(P('contain', f, v)));
  });
  return out;
});

addConvert('cv-nogrid', 'no grid in the option: the preprocessor makes one, and the string finder reaches it', {
  animation: false,
  xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [{ type: 'scatter', data: [[1, 1]] }],
}, () => ['grid', { gridIndex: 0 }, 'series', 'xAxis'].reduce((o, f) => o.concat([
  P('to', f, [5, 5]), P('to', f, 5), P('from', f, [300, 200]), P('from', f, 300), P('contain', f, [300, 200]), P('contain', f, [5, 5])]), []));

addConvert('cv-legend-hidden', 'a series the legend switched off still converts on its axes', base({
  legend: { selected: { b: false } },
  xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [{ type: 'scatter', name: 'a', data: [[1, 1]] }, { type: 'scatter', name: 'b', data: [[2, 2]] }],
}), () => [{ seriesIndex: 1 }, { seriesName: 'b' }].reduce((o, f) => o.concat([
  P('to', f, [5, 5]), P('from', f, [300, 200]), P('contain', f, [300, 200])]), []));

// ---- calendar ----
const calProbes = finder => {
  const out = [];
  ['2017-02-03', ['2017-02-03', 5], Date.UTC(2017, 1, 3), Date.UTC(2017, 1, 3) + 0.5, Date.UTC(2017, 1, 3, 23, 59),
    '2017-01-01', '2017-03-31', '2016-12-31', '2017-04-01', '2017-02-30', 'nope', null, true, [], [['2017-02-03']],
    ['2017-02-03T10:00:00Z'], [Date.UTC(2017, 1, 10), 'x'], '2017-02-14T23:00:00-02:00', 1e300]
    .forEach(v => out.push(P('to', finder, v)));
  [[200, 150], [150, 100], [95, 80], [80, 61], [560, 300], [0, 0], [1000, 1000], ['abc', 100], ['Infinity', 100],
    ['-Infinity', 100], [100, 'Infinity'], [100, '-Infinity'], [300], 300, [null, 200]].forEach(v => {
    out.push(P('from', finder, v));
    out.push(P('contain', finder, v));
  });
  return out;
};
addConvert('cv-calendar', 'a horizontal calendar with a heatmap and a scatter on it', {
  animation: false,
  calendar: [{ range: ['2017-01-01', '2017-03-31'], left: 80, top: 60, right: 30, cellSize: ['auto', 20] }],
  series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2017-01-05', 3], ['2017-02-14', 9]] },
    { type: 'scatter', coordinateSystem: 'calendar', data: [['2017-03-01', 4]] }],
  visualMap: { show: false, min: 0, max: 10 },
}, chart => calProbes('calendar').concat(calProbes({ seriesIndex: 0 })).concat(calProbes({ seriesIndex: 1 }))
  .concat(calProbes({ calendarIndex: 0, seriesIndex: 1 })).concat([
    P('to', { calendarIndex: 1 }, '2017-02-03'), P('to', { calendarId: 'none' }, '2017-02-03')]));
addConvert('cv-calendar-v', 'a vertical calendar, firstDay 1', {
  animation: false,
  calendar: { orient: 'vertical', range: '2018-02', left: 100, top: 50, cellSize: 30, dayLabel: { firstDay: 1 } },
  series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2018-02-05', 3]] }],
  visualMap: { show: false, min: 0, max: 10 },
}, chart => {
  const out = [];
  ['2018-02-01', '2018-02-05', '2018-02-28', '2018-03-01', '2018-01-31'].forEach(v => out.push(P('to', 'calendar', v)));
  [[110, 60], [150, 120], [290, 220], [100, 50], [99, 49], [330, 260]].forEach(v => {
    out.push(P('from', 'calendar', v));
    out.push(P('contain', 'calendar', v));
  });
  return out;
});
addConvert('cv-calendar-grid', 'a calendar beside a grid: a finder naming both reaches the grid first', base({
  calendar: { range: '2017-01', left: 80, top: 260, cellSize: 15 },
  xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [{ type: 'scatter', data: [[1, 1]] }, { type: 'scatter', coordinateSystem: 'calendar', data: [['2017-01-03', 1]] }],
}), () => {
  const fs = [{ calendarIndex: 0, xAxisIndex: 0 }, { calendarIndex: 0, gridIndex: 0 }, { seriesIndex: 1, xAxisIndex: 0 },
    { seriesIndex: 0, calendarIndex: 0 }, { seriesIndex: 1 }, { seriesIndex: 'all' }, 'calendar'];
  return fs.reduce((o, f) => o.concat([P('to', f, ['2017-01-03', 5]), P('to', f, 5), P('from', f, [100, 280]), P('from', f, [300, 100]),
    P('contain', f, [100, 280]), P('contain', f, [300, 100])]), []);
});

// ---- radar: not implemented upstream ----
addConvert('cv-radar', 'radar: convert answers nothing, containPixel false', {
  animation: false,
  radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
  series: [{ type: 'radar', data: [{ value: [3, 5, 7] }] }],
}, () => ['radar', { seriesIndex: 0 }, { radarIndex: 0 }].reduce((o, f) => o.concat([
  P('to', f, [3, 5]), P('from', f, [300, 200]), P('contain', f, [300, 200])]), []));

// ---- graph on its view ----
const graphProbes = chart => {
  const out = [];
  [[0, 0], [100, 50], [37.5, 12.25], [-20, 80], [200, -10], 5, [5], ['10', '20'], [null, 3], ['abc', 5], [5, 'Infinity']]
    .forEach(v => out.push(P('to', 'series', v)));
  [[300, 200], [60, 40], [100.5, 333.25], [0, 0], 300, ['300', 200], ['abc', 200], [100, 'Infinity'], ['-Infinity', 3],
    [100, 'abc']].forEach(v => out.push(P('from', 'series', v)));
  [[300, 200], [10, 10], [590, 390], [150, 120], [450, 300], [80, 60], [520, 340], [299.5, 199.5]].forEach(v => out.push(P('contain', 'series', v)));
  return out;
};
const NODES = [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 40, y: 80 }];
addConvert('cv-graph', 'a graph on its own view (layout none)', {
  animation: false,
  series: [{ type: 'graph', layout: 'none', data: NODES, links: [{ source: 'a', target: 'b' }] }],
}, graphProbes);
addConvert('cv-graph-roam', 'the same zoomed and recentred', {
  animation: false,
  series: [{ type: 'graph', layout: 'none', roam: true, zoom: 1.7, center: [60, 30], data: NODES, links: [] }],
}, graphProbes);
addConvert('cv-graph-box', 'the view inside a box (left, top, width, height)', {
  animation: false,
  series: [{ type: 'graph', layout: 'none', left: 100, top: 80, width: 200, height: 150, data: NODES, links: [] }],
}, graphProbes);
addConvert('cv-graph-cartesian', 'a graph on a cartesian: the grid answers for it', base({
  xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [[10, 20], [60, 70]], links: [] }],
}), graphProbes);

// ---- series that answer containPixel with their own view ----
const containAll = finder => {
  const out = [];
  for (let x = 0; x <= 600; x += 37.5) {
    for (let y = 0; y <= 400; y += 33.25) out.push(P('contain', finder, [x, y]));
  }
  out.push(P('to', finder, [1, 2]));
  out.push(P('from', finder, [300, 200]));
  return out;
};
addConvert('cv-pie', 'a donut: containPixel is the ring of the first item, nothing converts', {
  animation: false,
  series: [{ type: 'pie', radius: ['30%', '60%'], center: ['45%', '55%'], data: [{ value: 3 }, { value: 5 }, { value: 2 }] }],
}, () => containAll('series').concat([P('contain', 'series', [270, 220]), P('contain', 'series', [270, 160.4])]));
addConvert('cv-pie-rose', 'a rose pie: the first item\'s own radius', {
  animation: false,
  series: [{ type: 'pie', roseType: 'radius', radius: [20, 150], data: [{ value: 2 }, { value: 9 }, { value: 5 }] }],
}, () => containAll({ seriesIndex: 0 }));
addConvert('cv-sunburst', 'a sunburst: the virtual root has no layout, so nothing contains', {
  animation: false,
  series: [{ type: 'sunburst', radius: [0, '80%'], data: [{ name: 'a', value: 4, children: [{ name: 'a1', value: 2 }] }, { name: 'b', value: 3 }] }],
}, () => containAll('series'));
addConvert('cv-tree', 'a tree: its own view, the nodes\' extent through the roam', {
  animation: false,
  series: [{ type: 'tree', data: [{ name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'b' }] }] }],
}, () => containAll('series'));
addConvert('cv-sankey', 'a sankey: its own view over its box', {
  animation: false,
  series: [{ type: 'sankey', left: 50, top: 40, right: 120, bottom: 60,
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b', value: 3 }, { source: 'a', target: 'c', value: 2 }] }],
}, chart => {
  // the box's own edges: in on all four, out a hair past them
  const li = chart.getModel().getSeriesByIndex(0).layoutInfo;
  const x0 = li.x, y0 = li.y, x1 = li.x + li.width, y1 = li.y + li.height;
  return containAll('series').concat([[x0, y0], [x1, y1], [x0, y1], [x1, y0], [x0 - 1e-9, y0], [x1 + 1e-9, y1],
    [x0, y0 - 1e-9], [x1, y1 + 1e-9]].map(v => P('contain', 'series', v)));
});
addConvert('cv-funnel', 'a funnel: no coordinate system, no containPoint', {
  animation: false,
  series: [{ type: 'funnel', data: [{ value: 3 }, { value: 5 }] }],
}, () => containAll('series'));
addConvert('cv-mixed', 'a pie and a cartesian: seriesIndex all contains through either', base({
  xAxis: { type: 'value', min: 0, max: 10, gridIndex: 0 }, yAxis: { type: 'value', min: 0, max: 10 },
  grid: { left: 40, right: 340, top: 40, bottom: 40, outerBoundsMode: 'none' },
  series: [{ type: 'scatter', data: [[1, 1]] }, { type: 'pie', center: [450, 200], radius: 80, data: [{ value: 1 }] }],
}), () => [{ seriesIndex: 'all' }, { seriesIndex: [1, 0] }, { seriesIndex: 1 }, 'grid'].reduce((o, f) => o.concat([
  P('contain', f, [100, 100]), P('contain', f, [450, 200]), P('contain', f, [300, 380]), P('to', f, [5, 5])]), []));

// ---------------------------------------------------------------------------
// jitter
// ---------------------------------------------------------------------------
const JITTER = [];
const addJitter = (id, note, option) => JITTER.push({ id, kind: 'jitter', note, option });
const crowd = (n, cats, spread, seed) => {
  // a fixed spread of values, no randomness of our own
  const out = [];
  for (let i = 0; i < n; i++) out.push([cats[(i * 7 + seed) % cats.length], 40 + ((i * 37 + seed * 11) % 23) * spread]);
  return out;
};
const CATS3 = ['P', 'Q', 'R'];
addJitter('j-overlap', 'jitter 30 on the category x, jitterOverlap true (the default): random within the band', base({
  xAxis: { type: 'category', data: CATS3, jitter: 30 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(30, CATS3, 1, 1) }],
}));
addJitter('j-avoid', 'jitterOverlap false: placed beside the earlier ones, margin 2', base({
  xAxis: { type: 'category', data: CATS3, jitter: 60, jitterOverlap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(30, CATS3, 0.5, 2) }],
}));
addJitter('j-avoid-margin', 'jitterOverlap false, margin 6', base({
  xAxis: { type: 'category', data: CATS3, jitter: 80, jitterOverlap: false, jitterMargin: 6 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(24, CATS3, 0.5, 3) }],
}));
addJitter('j-avoid-margin0', 'jitterOverlap false, margin 0', base({
  xAxis: { type: 'category', data: CATS3, jitter: 80, jitterOverlap: false, jitterMargin: 0 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(24, CATS3, 0.5, 3) }],
}));
addJitter('j-avoid-fallback', 'jitterOverlap false, a small jitter and a crowd: the placement gives up and draws at random', base({
  xAxis: { type: 'category', data: CATS3, jitter: 14, jitterOverlap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', symbolSize: 12, data: crowd(40, CATS3, 0.2, 4) }],
}));
addJitter('j-avoid-band', 'jitterOverlap false, a jitter wider than the band: the band stops it', base({
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], jitter: 300, jitterOverlap: false },
  yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(40, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'], 0.3, 5) }],
}));
addJitter('j-avoid-crowd', 'jitterOverlap false, thirty points on one value: the stack outgrows half the band and falls back to random', base({
  xAxis: { type: 'category', data: CATS3, jitter: 400, jitterOverlap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: Array.from({ length: 30 }, () => ['P', 50]) }],
}));
addJitter('j-y', 'jitter on a category y', base({
  yAxis: { type: 'category', data: CATS3, jitter: 40, jitterOverlap: false }, xAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(20, CATS3, 0.6, 6).map(d => [d[1], d[0]]) }],
}));
addJitter('j-y-random', 'jitter on a category y, random', base({
  yAxis: { type: 'category', data: CATS3, jitter: 40 }, xAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(20, CATS3, 0.6, 6).map(d => [d[1], d[0]]) }],
}));
addJitter('j-two-series', 'two scatter series on one axis share its placed items', base({
  xAxis: { type: 'category', data: CATS3, jitter: 50, jitterOverlap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(12, CATS3, 0.5, 7) }, { type: 'scatter', symbolSize: 16, data: crowd(12, CATS3, 0.5, 8) },
    { type: 'line', data: [10, 20, 30] }],
}));
addJitter('j-clamp', 'jitter 500 on a narrow band, random: clamped to the band less the symbol', base({
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'], jitter: 500 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', symbolSize: 20, data: crowd(20, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'], 1, 9) }],
}));
addJitter('j-gaps', "a '-', a null and a category nobody knows: the draws are made all the same", base({
  xAxis: { type: 'category', data: CATS3, jitter: 30 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: [['P', 30], ['Q', '-'], ['R', null], ['Z', 40], ['P', 50], ['Q', 60], [null, 20], ['R', 70]] }],
}));
addJitter('j-gaps-avoid', 'the same, avoiding', base({
  xAxis: { type: 'category', data: CATS3, jitter: 30, jitterOverlap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: [['P', 30], ['Q', '-'], ['P', 31], ['Z', 40], ['P', 30.5], ['Q', 60], [null, 20], ['P', 32]] }],
}));
addJitter('j-sizes', 'symbolSize per item and as [w, h]: the radius is the mean half', base({
  xAxis: { type: 'category', data: CATS3, jitter: 70, jitterOverlap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', symbolSize: [10, 24], data: [['P', 50], { value: ['P', 51], symbolSize: 30 }, ['P', 52],
    { value: ['P', 50], symbolSize: [4, 8] }, ['Q', 10], ['Q', 11]] }],
}));
addJitter('j-value-axis', 'jitter on a value axis: nothing moves (the base axis is not a category)', base({
  xAxis: { type: 'value', jitter: 30 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: [[1, 50], [1, 50], [2, 50]] }],
}));
addJitter('j-category-on-y-jitter-x', 'a category x and a category y: the base is x; jitter written on y does nothing', base({
  xAxis: { type: 'category', data: CATS3 }, yAxis: { type: 'category', data: ['u', 'v'], jitter: 40 },
  series: [{ type: 'scatter', data: [['P', 'u'], ['P', 'u'], ['Q', 'v']] }],
}));
addJitter('j-zero', 'jitter 0: nothing moves', base({
  xAxis: { type: 'category', data: CATS3, jitter: 0 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: [['P', 50], ['P', 50]] }],
}));
addJitter('j-effect', 'effectScatter is not jittered', base({
  xAxis: { type: 'category', data: CATS3, jitter: 40 }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'effectScatter', data: [['P', 50], ['P', 50]] }, { type: 'scatter', data: [['P', 50], ['P', 50]] }],
}));
addJitter('j-inverse', 'an inverse category x', base({
  xAxis: { type: 'category', data: CATS3, jitter: 40, jitterOverlap: false, inverse: true }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(15, CATS3, 0.5, 10) }],
}));
addJitter('j-nogap', 'boundaryGap false', base({
  xAxis: { type: 'category', data: CATS3, jitter: 40, boundaryGap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(15, CATS3, 0.5, 11) }],
}));
addJitter('j-clip', 'points jittered past the plot are not drawn (clip)', base({
  xAxis: { type: 'category', data: ['a', 'b'], jitter: 400, boundaryGap: false }, yAxis: { type: 'value', min: 0, max: 100 },
  series: [{ type: 'scatter', data: crowd(20, ['a', 'b'], 1, 12) }],
}));

// ---------------------------------------------------------------------------
// customValues
// ---------------------------------------------------------------------------
const CUSTOM = [];
const addCustom = (id, note, option) => CUSTOM.push({ id, kind: 'custom', note, option });
const valueY = { type: 'value', min: 0, max: 100 };
addCustom('cu-value', 'a value x: labels at [0, 25, 50.5, 100, 120 (out), 25 (again), -5 (out)], ticks at [10, 30, 77]', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [0, 25, 50.5, 100, 120, 25, -5] }, axisTick: { customValues: [10, 30, 77] } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-value-split', 'axisTick.customValues moves the split lines and areas too', base({
  xAxis: { type: 'value', min: 0, max: 100, axisTick: { customValues: [5, 40, 60.5, 99] }, splitLine: { show: true }, splitArea: { show: true } },
  yAxis: { type: 'value', min: 0, max: 100, axisTick: { customValues: [33, 66] }, splitArea: { show: true } },
  series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-unsorted', 'unsorted values, strings among them', base({
  xAxis: { type: 'value', min: 0, max: 10, axisLabel: { customValues: [7, '2', 9.5, 'x', null, 0, '7'] }, axisTick: { customValues: [8, 1, '4'] } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[1, 10]] }],
}));
addCustom('cu-category', 'a category x: names and ordinals; ticks on the band edges plus the last', base({
  xAxis: { type: 'category', data: CATS5, axisLabel: { customValues: ['B', 'D', 0, 'Z', 4.4] }, axisTick: { customValues: [1, 'C', 3] } },
  yAxis: valueY, series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-category-align', 'the same with axisTick.alignWithLabel', base({
  xAxis: { type: 'category', data: CATS5, axisLabel: { customValues: ['B', 'D'] }, axisTick: { customValues: [1, 3], alignWithLabel: true } },
  yAxis: valueY, series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-category-split', 'a category x with custom ticks and the split lines and areas shown', base({
  xAxis: { type: 'category', data: CATS5, axisTick: { customValues: [0, 2, 4] }, splitLine: { show: true }, splitArea: { show: true } },
  yAxis: valueY, series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-category-labels', 'custom labels on a crowded category axis: the ticks still walk the label interval (4, written: an auto one is measured in a font the port does not share)', base({
  xAxis: { type: 'category', data: Array.from({ length: 60 }, (_, i) => 'category ' + i), axisLabel: { customValues: [0, 10, 33, 59], interval: 4 } },
  yAxis: valueY, series: [{ type: 'bar', data: Array.from({ length: 60 }, (_, i) => i) }],
}));
addCustom('cu-category-nogap', 'a category x with boundaryGap false', base({
  xAxis: { type: 'category', data: CATS5, boundaryGap: false, axisLabel: { customValues: [1, 3] }, axisTick: { customValues: [0, 2, 4] } },
  yAxis: valueY, series: [{ type: 'line', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-y', 'a value y and a category y', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [15, 85] } },
  yAxis: { type: 'category', data: CATS5, axisLabel: { customValues: ['A', 'E'] }, axisTick: { customValues: ['C'] } },
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-time', 'a time x: ISO dates, a number, a date off the extent (useUTC, so the words are the same in any zone)', base({
  useUTC: true,
  xAxis: { type: 'time', min: T0, max: T0 + 10 * DAY,
    axisLabel: { customValues: ['2024-01-03T00:00:00Z', T0 + 5 * DAY, '2024-01-08T12:00:00Z', '2023-12-31T00:00:00Z', T0 + 6 * DAY + 0.6] },
    axisTick: { customValues: [T0 + DAY, '2024-01-09T00:00:00Z', T0 + 7 * DAY + 0.4] } },
  yAxis: valueY, series: [{ type: 'line', data: [[T0, 3], [T0 + 10 * DAY, 8]] }],
}));
addCustom('cu-log', 'a log y', base({
  xAxis: { type: 'value', min: 0, max: 10 },
  yAxis: { type: 'log', min: 1, max: 10000, axisLabel: { customValues: [1, 5, 50, 5000, 20000] }, axisTick: { customValues: [3, 300] } },
  series: [{ type: 'line', data: [[1, 3], [9, 7000]] }],
}));
addCustom('cu-formatter', "a template formatter: '{value} kg'", base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [20, 40.25], formatter: '{value} kg' } },
  yAxis: { type: 'category', data: CATS5, axisLabel: { customValues: ['B', 'C'], formatter: '<{value}>' } },
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-crowd', 'crowded custom labels without hideOverlap: all kept, the ends too', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [0, 1, 2, 3, 50, 98, 99, 100] } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-hideoverlap', 'crowded custom labels with hideOverlap: overlaps hidden, and their ticks with them', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [0, 1, 2, 3, 50, 98, 99, 100], hideOverlap: true },
    axisTick: { customValues: [0, 1, 2, 3, 50, 98, 99, 100] } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-minmax', 'showMinLabel false, showMaxLabel true with custom labels', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [0, 1, 50, 99, 100], showMinLabel: false, showMaxLabel: true } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-labels-only', 'custom labels and default ticks: a tick is hidden with a hidden label of its value', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [0, 20, 21, 40, 100], hideOverlap: true } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-inverse', 'an inverse value x and an inverse category y', base({
  xAxis: { type: 'value', min: 0, max: 100, inverse: true, axisLabel: { customValues: [10, 60] }, axisTick: { customValues: [30] } },
  yAxis: { type: 'category', data: CATS5, inverse: true, axisLabel: { customValues: [1, 3] }, axisTick: { customValues: [2] } },
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10] }],
}));
addCustom('cu-empty', 'an empty list: no labels, no ticks', base({
  xAxis: { type: 'value', min: 0, max: 100, axisLabel: { customValues: [] }, axisTick: { customValues: [] }, splitLine: { show: true } },
  yAxis: valueY, series: [{ type: 'scatter', data: [[10, 10]] }],
}));
addCustom('cu-datazoom', 'a zoomed category axis: values outside the window are dropped', base({
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'], axisLabel: { customValues: ['a', 'c', 'e', 'g', 'i'] },
    axisTick: { customValues: [1, 3, 5, 7, 9] } },
  yAxis: valueY, dataZoom: [{ type: 'inside', xAxisIndex: 0, startValue: 2, endValue: 6 }],
  series: [{ type: 'bar', data: [5, 20, 36, 10, 10, 50, 60, 15, 30, 44] }],
}));

// ---------------------------------------------------------------------------
// recording
// ---------------------------------------------------------------------------
function runConvert(c) {
  const chart = newChart(clone(c.option));
  try {
    const probes = c.probes(chart).map(p => {
      let out;
      try {
        out = outOf(quiet(() => {
          if (p.op === 'to') return chart.convertToPixel(p.finder, p.value);
          if (p.op === 'from') return chart.convertFromPixel(p.finder, p.value);
          return chart.containPixel(p.finder, p.value);
        }));
      } catch (e) {
        if (!(e instanceof TypeError)) throw e;
        // upstream indexes a null value: the call throws
        out = { k: 'throw' };
      }
      const rec = { op: p.op, finder: input(p.finder), value: input(p.value), out };
      // which coordinate system answered (doConvertPixel's loop, replayed)
      if (p.op !== 'contain' && out.k !== 'none' && out.k !== 'throw') {
        const list = chart._coordSysMgr.getCoordinateSystems();
        const pf = PARSE_FINDER(chart.getModel(), p.finder);
        const method = p.op === 'to' ? 'convertToPixel' : 'convertFromPixel';
        for (const cs of list) {
          let r = null;
          try { r = cs[method] ? quiet(() => cs[method](chart.getModel(), pf, p.value)) : null; } catch (e) { r = null; }
          if (r != null) { rec.by = cs.type; break; }
        }
        must(rec.by, c.id + ': no coordinate system answered a probe that has an answer');
      }
      return rec;
    });
    const grids = [];
    chart.getModel().eachComponent('grid', gm => {
      const cs = gm.coordinateSystem && gm.coordinateSystem.getCartesians()[0];
      if (!cs) { grids.push(null); return; }
      const a = cs.getArea();
      grids.push([a.x, a.y, a.width, a.height].map(hex));
    });
    must(draws.length === 0, c.id + ': a conversion chart drew random numbers');
    return { id: c.id, kind: c.kind, note: c.note, option: c.option, grids, probes };
  } finally {
    chart.dispose();
  }
}

function runJitter(c) {
  const chart = newChart(clone(c.option));
  try {
    const bad = draws.filter(o => !/^at fixJitterIgnoreOverlaps \(/.test(o));
    must(!bad.length, c.id + ': a random draw outside the jitter: ' + bad[0]);
    const series = [];
    chart.getModel().eachSeries(s => {
      if (s.subType !== 'scatter' && s.subType !== 'effectScatter') return;
      const d = s.getData();
      const items = [];
      for (let i = 0; i < d.count(); i++) {
        const l = d.getItemLayout(i);
        const el = d.getItemGraphicEl(i);
        items.push({ i, layout: l ? [hex(l[0]), hex(l[1])] : null, drawn: !!el });
        if (el && l) {
          must(Object.is(el.x, l[0]) && Object.is(el.y, l[1]), c.id + ': a symbol not at its layout');
        }
      }
      series.push({ seriesIndex: s.seriesIndex, type: s.subType, items });
    });
    return { id: c.id, kind: c.kind, note: c.note, option: c.option, draws: draws.length, series };
  } finally {
    chart.dispose();
  }
}

function sceneOf(chart, axis) {
  const view = chart.getViewOfComponentModel(axis.model);
  must(view && view._axisGroup, 'no axis view group');
  const bg = axis.axisBuilder.group;
  const under = (e, g) => { for (let p = e; p; p = p.parent) if (p === g) return true; return false; };
  const out = { ticks: new Map(), lines: new Map(), areas: new Map(), labels: [] };
  (function walk(e) {
    const inB = under(e, bg);
    let m;
    if (e.anid) {
      if (inB && (m = /^ticks_(.*)$/.exec(e.anid))) out.ticks.set(m[1], !e.ignore);
      else if (!inB && (m = /^line_(.*)$/.exec(e.anid))) out.lines.set(m[1], true);
      else if (!inB && (m = /^area_(.*)$/.exec(e.anid))) out.areas.set(m[1], true);
    }
    if (e.type === 'text') {
      const k = Object.keys(e).find(kk => kk.startsWith('__ec_inner') && e[kk] && e[kk].labelInfo);
      if (k && e[k].labelInfo.tick) {
        out.labels.push({ tick: hex(e[k].labelInfo.tick.value), text: String(e.style.text), x: hex(e.x), y: hex(e.y),
          hidden: !!(e.ignore || e.invisible) });
      }
    }
    if (e.childrenRef) e.childrenRef().forEach(walk);
  })(view._axisGroup);
  return out;
}

function runCustom(c) {
  const chart = newChart(clone(c.option));
  try {
    const axes = [];
    ['xAxis', 'yAxis'].forEach(mt => chart.getModel().eachComponent(mt, am => {
      const axis = am.axis;
      const sc = sceneOf(chart, axis);
      const toG = v => axis.toGlobalCoord(v);
      const ticks = axis.getTicksCoords();
      const lines = axis.getTicksCoords({ tickModel: am.getModel('splitLine'), breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' });
      const areas = axis.getTicksCoords({ tickModel: am.getModel('splitArea'), breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' });
      const showTick = am.get(['axisTick', 'show']);
      axes.push({
        dim: axis.dim, index: am.componentIndex, type: axis.type,
        ticks: { values: ticks.map(t => hex(t.tickValue)), coords: ticks.map(t => hex(toG(t.coord))),
          drawn: ticks.map(t => !!(sc.ticks.has(String(t.tickValue)) && sc.ticks.get(String(t.tickValue)))), shown: showTick !== false },
        splitLines: { values: lines.map(t => hex(t.tickValue)), coords: lines.map(t => hex(toG(t.coord))),
          drawn: lines.map(t => sc.lines.has(String(t.tickValue))) },
        splitAreas: { values: areas.map(t => hex(t.tickValue)), coords: areas.map(t => hex(toG(t.coord))) },
        labels: sc.labels,
      });
    }));
    return { id: c.id, kind: c.kind, note: c.note, option: c.option, axes };
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// guards: expectations read off the source
// ---------------------------------------------------------------------------
function guards(o) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => o.cases.find(c => c.id === id);
  const probe = (id, op, finderText, valueText) => {
    const p = cs(id).probes.find(q => q.op === op && q.finder.text === finderText && q.value.text === valueText);
    must(p, id + ': no probe ' + op + ' ' + finderText + ' ' + valueText);
    return p.out;
  };
  const arr = out => (out.k === 'arr' ? out.v.map(num) : null);
  // the finder
  guard("'series' is {seriesIndex: 0}", JSON.stringify(probe('cv-finders', 'to', '"series"', '[3,40]'))
    === JSON.stringify(probe('cv-finders', 'to', '{"seriesIndex":0}', '[3,40]')));
  guard('an unknown main type answers nothing', probe('cv-finders', 'to', '"foo"', '[3,40]').k === 'none');
  guard("'none' and false find nothing", probe('cv-finders', 'to', '{"seriesIndex":"none"}', '[3,40]').k === 'none'
    && probe('cv-finders', 'to', '{"seriesIndex":false}', '[3,40]').k === 'none');
  guard("'1' is index 1, '01' is nothing", probe('cv-finders', 'to', '{"seriesIndex":"1"}', '[3,40]').k === 'arr'
    && probe('cv-finders', 'to', '{"seriesIndex":"01"}', '[3,40]').k === 'none');
  guard('a number in an id array never matches (a native Map)', probe('cv-finders', 'to', '{"seriesId":[5]}', '[3,40]').k === 'none'
    && probe('cv-finders', 'to', '{"seriesId":5}', '[3,40]').k === 'arr' && probe('cv-finders', 'to', '{"seriesId":["5"]}', '[3,40]').k === 'arr');
  guard('an axis finder answers a number', probe('cv-finders', 'to', '{"xAxisIndex":0}', '7.25').k === 'num');
  guard('a scalar to a cartesian is [NaN, NaN]', arr(probe('cv-finders', 'to', '"grid"', '7.25')).every(Number.isNaN));
  guard('dataIndex alone finds nothing', probe('cv-finders', 'to', '{"dataIndex":2}', '[3,40]').k === 'none');
  guard('an x axis contains nothing', probe('cv-finders', 'contain', '{"xAxisIndex":0}', '[100.5,200.25]').v === false);
  // the values
  guard("'' is 0 on the affine path", JSON.stringify(arr(probe('cv-value', 'to', '"series"', '["",40]')))
    === JSON.stringify(arr(probe('cv-value', 'to', '"series"', '[0,40]'))));
  guard('null drops the affine path: x is NaN', Number.isNaN(arr(probe('cv-value', 'to', '"series"', '[null,40]'))[0]));
  guard("'34' to a cartesian reads '3' and '4'", JSON.stringify(arr(probe('cv-value', 'to', '"series"', '"34"')))
    === JSON.stringify(arr(probe('cv-value', 'to', '"series"', '["3","4"]'))));
  guard('a category name maps to its ordinal', JSON.stringify(arr(probe('cv-category', 'to', '"series"', '["B",30]')))
    === JSON.stringify(arr(probe('cv-category', 'to', '"series"', '[1,30]'))));
  guard('an unknown category is NaN', Number.isNaN(arr(probe('cv-category', 'to', '"series"', '["Z",30]'))[0]));
  guard('1.4 rounds to the category 1', JSON.stringify(arr(probe('cv-category', 'to', '"series"', '[1.4,30]')))
    === JSON.stringify(arr(probe('cv-category', 'to', '"series"', '[1,30]'))));
  guard('the time fast path does not round', arr(probe('cv-time', 'to', '"series"', '[' + (T0 + 0.4) + ',5]'))[0]
    !== arr(probe('cv-time', 'to', '"series"', '[' + T0 + ',5]'))[0]);
  guard('a calendar date off the range is [NaN, NaN]', arr(probe('cv-calendar', 'to', '"calendar"', '"2017-04-01"')).every(Number.isNaN));
  guard('a calendar pixel answers a time', probe('cv-calendar', 'from', '"calendar"', '[200,150]').k === 'num');
  guard('a calendar pixel off the range answers nothing', probe('cv-calendar', 'from', '"calendar"', '[1000,1000]').k === 'none');
  guard('a NaN calendar pixel answers NaN', Number.isNaN(num(probe('cv-calendar', 'from', '"calendar"', '["abc",100]').v)));
  guard('a calendar contains nothing', probe('cv-calendar', 'contain', '"calendar"', '[200,150]').v === false);
  guard('radar converts nothing', probe('cv-radar', 'to', '"radar"', '[3,5]').k === 'none');
  guard('a pie ring contains its inside', probe('cv-pie', 'contain', '"series"', '[270,220]').v === false
    && cs('cv-pie').probes.some(p => p.op === 'contain' && p.out.v === true));
  guard('a sunburst never contains', cs('cv-sunburst').probes.filter(p => p.op === 'contain').every(p => p.out.v === false));
  guard('a tree contains something', cs('cv-tree').probes.some(p => p.op === 'contain' && p.out.v === true));
  guard('a funnel contains nothing', cs('cv-funnel').probes.filter(p => p.op === 'contain').every(p => p.out.v === false));
  guard('a calendar and an x axis: the grid answers', probe('cv-calendar-grid', 'to', '{"calendarIndex":0,"xAxisIndex":0}', '5').k === 'num');
  guard('a calendar series and an x axis: the calendar answers', probe('cv-calendar-grid', 'to', '{"seriesIndex":1,"xAxisIndex":0}', '["2017-01-03",5]').k === 'arr');
  guard('the hidden series still converts', probe('cv-legend-hidden', 'to', '{"seriesIndex":1}', '[5,5]').k === 'arr');
  // jitter
  const jit = id => cs(id).series[0].items.map(it => it.layout ? it.layout.map(num) : null);
  const overlap = jit('j-overlap');
  guard('jitterOverlap: every point drew one number', cs('j-overlap').draws === 30);
  guard('jitterOverlap: x left its band centre', overlap.some(p => p && p[0] % 1 !== 0));
  guard('jitterOverlap false and room: no draws', cs('j-avoid').draws === 0);
  guard('the fallback draws', cs('j-avoid-fallback').draws > 0);
  guard('half the band stops a stack', cs('j-avoid-crowd').draws > 0);
  guard('jitter on a value axis draws nothing and moves nothing', cs('j-value-axis').draws === 0);
  guard('effectScatter is not jittered', cs('j-effect').draws === 2);
  guard('the gaps draw too', cs('j-gaps').draws === 8);
  guard('jitter 0 draws nothing', cs('j-zero').draws === 0);
  guard('jitter on y: y moves', jit('j-y-random').some(p => p && p[1] % 1 !== 0));
  // customValues
  const ax = (id, dim) => cs(id).axes.find(a => a.dim === dim);
  const vals = h => h.map(num);
  guard('custom labels: in the extent, deduplicated, ascending', JSON.stringify(ax('cu-value', 'x').labels.map(l => num(l.tick)))
    === JSON.stringify([0, 25, 50.5, 100]));
  guard('custom ticks', JSON.stringify(vals(ax('cu-value', 'x').ticks.values)) === JSON.stringify([10, 30, 77]));
  guard('the split lines follow axisTick.customValues', JSON.stringify(vals(ax('cu-value-split', 'x').splitLines.values))
    === JSON.stringify([5, 40, 60.5, 99]));
  guard('category ticks: the band edges and one more', vals(ax('cu-category', 'x').ticks.values).length === 4);
  guard('alignWithLabel: no extra tick', vals(ax('cu-category-align', 'x').ticks.values).length === 2);
  guard('crowded custom labels without hideOverlap all show', ax('cu-crowd', 'x').labels.every(l => !l.hidden));
  guard('with hideOverlap some hide', ax('cu-hideoverlap', 'x').labels.some(l => l.hidden));
  guard('a hidden label hides its tick', ax('cu-hideoverlap', 'x').ticks.drawn.some(d => !d));
  guard('showMinLabel false hides the first', ax('cu-minmax', 'x').labels.find(l => num(l.tick) === 0).hidden);
  guard('an empty list: nothing', ax('cu-empty', 'x').labels.length === 0 && ax('cu-empty', 'x').ticks.values.length === 0);
  return g;
}
// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------
function generate() {
  warnings = 0;
  const out = {
    source: DIST, version: echarts.version, W, H, seed: SEED,
    notes: [
      'animation: false throughout; SVG server-side rendering, 600 x 400.',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'convert: chart.convertToPixel / convertFromPixel / containPixel with the probe\'s finder and value as written.',
      'jitter: data.getItemLayout(i) after the render, and whether a symbol was drawn.',
      'custom: axis.getTicksCoords() with the axisTick, splitLine and splitArea models; the labels in the axis group.',
    ],
    cases: CONVERT.map(runConvert).concat(JITTER.map(runJitter), CUSTOM.map(runCustom)),
  };
  out.guards = guards(out);
  return out;
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
const deterministic = json1 === json2;
const nProbes = out1.cases.reduce((n, c) => n + (c.probes ? c.probes.length : 0), 0);
console.log(out1.cases.length + ' cases (' + nProbes + ' probes); ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (process.env.ORACLE_DUMP) console.log(json1);
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
