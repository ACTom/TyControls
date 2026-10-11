// Upstream's own answers for LARGE MODE (batch 117, roadmap C8): when a bar,
// scatter or candlestick series switches to its batched path (`large` and
// `largeThreshold` against the data count after the dataZoom filter), what
// the batch holds (bar: largePoints [x, y, size] with largeDataIndices and
// the bar width, and the background's points; scatter: the points, the
// series-level symbol size and type, the soft clip, the fillRect boost under
// 4 px; candlestick: [sign, x, ylow, yhigh] per row, one stroked path per
// sign), the clip, the bounding rects, which element and which dataIndex the
// pointer finds (largePathFindDataIndex's forward scan, LargeSymbolPath's
// top-down findDataIndex at max(size, 4), the candle paths without data),
// the chart mouse events and the tooltip, and that emphasis / blur do not
// reach a large element. A line never goes large.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node: echarts.init(null, null, {renderer: 'svg', ssr: true})
// and right after init chart._ssr = false; echarts.env.node = false and the
// chart prototype's getDom answering an empty object, so TooltipView runs
// (tooltip-finish.js's recipe). The SVG painter makes progressive rendering
// impossible (Scheduler: progressive only on 'canvas'), so every large
// series here is drawn in one pass -- progressive is C9. Math.random is the
// port's xorshift32 (seed 2463534242, reset per chart) for the jitter case.
//
// TIME. The global Date is replaced before the dist loads; the clock only
// ever moves forward (1000 ms per step, never reset between cases or the two
// generations), so the bar's 30 ms throttle (largePathUpdateDataIndex, one
// throttled function shared by every large bar in the process) always runs
// its call at once. setTimeout / clearTimeout are a queue; a guard checks it
// stays empty.
//
// The pointer goes through zrender's own Handler (mousemove / mouseout with
// {zrX, zrY}); after every step the chart's _onframe runs (states applied).
//
//   node tools/advchart-oracle/large-mode.js
//
// writes tests/fixtures/advchart-large-mode.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex   a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//         lowercase (NaN 7ff8000000000000). Float32 values are recorded
//         widened to double.
//   colour [r, g, b, a] from echarts.color.parse, null when unset.
//
// Top level: source, version, W, H, seed, notes[], cases[], guards[], recipes{}
//   case: id, group, note, option (as fed to setOption, minus the tooltip
//     formatter the oracle adds), records[] (one after init and one after
//     every 'zoom' step), steps[]
//   record: at (the step index it follows, -1 for init), series[]
//   series: seriesIndex, type, count (data.count() after the filter),
//     pipelineLarge, mode ('large' | 'normal': whether the view drew a large
//     element), items (item graphic elements), clip ([x, y, w, h] hex of the
//     view group's clip path, null), largePoints (candlestick: the shared
//     [sign, x, ylow, yhigh] array, hex), els[]
//   el: kind ('bar' | 'barBg' | 'symbol' | 'candle'), z2, silent, bbox [x, y,
//     w, h] hex (el.getBoundingRect()), style {fill, stroke, lineWidth hex,
//     opacity hex}; bar / barBg: points (hex), indices (ints), barWidth hex,
//     baseDim; symbol: points (hex), size [w, h] hex, symbolType, boost,
//     softClip [x, y, w, h] hex | null; candle: sign
//   step: i, t ('move' | 'leave' | 'action' | 'zoom'), x, y, payload,
//     hover {kind, seriesIndex, sign, dataIndex} | {kind: 'item', seriesIndex,
//       dataIndex} | {kind: 'other'} | null (handler.findHover after the event;
//       dataIndex is the ECData's -- inner -- after the element handlers ran),
//     events [{type, seriesIndex, dataIndex (raw), dataIndexInside}],
//     tooltip {shown, which ('item:<s>:<raw>' | 'axis:<axisValueLabel>'),
//       inner (an item's dataIndexInside)} ,
//     states [{seriesIndex, kind, sign, currentStates[], opacity hex}] (every
//       large element), normal [{seriesIndex, dataIndex, states[]}] (the
//       items the case names in watch)
//
// Self-checks (recipes; each must run): R1 every hovered large element's
// dataIndex is recomputed here from the recorded points (bar: the forward
// scan; scatter: the top-down scan at max(size, 4) inside the bounding rect;
// candle: none); R2 every recorded bbox is recomputed from the recorded
// points; R3 a large bar's path containment (zrender's winding over the
// rects) agrees with the scan at every step; R4 every recorded bar / scatter
// point is recomputed from the store through the cartesian (dataToPoint,
// Math.fround). Guards: distinguishing counts, each >= 1. Two generations in
// one process give the same bytes; no \u0000; the JSON parses back.
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock (installed before the build loads) ----------
const RealDate = Date;
let NOW = 1700000000000;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
let TIMERS = [];
let timerSeq = 0;
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  TIMERS.push({ id, due: NOW + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  TIMERS = TIMERS.filter(t => t.id !== id);
};
// run every timer due by AT, in time order (ties in creation order), the
// clock at each one's due time; zrender's animation loop frame (its
// requestAnimationFrame falls back to setTimeout) is dropped, never run
function settle(at) {
  for (;;) {
    TIMERS = TIMERS.filter(t => String(t.fn).indexOf('requestAnimationFrame') < 0);
    TIMERS.sort((a, b) => a.due - b.due || a.id - b.id);
    if (!TIMERS.length || TIMERS[0].due > at) break;
    const t = TIMERS.shift();
    if (t.due > NOW) NOW = t.due;
    t.fn();
  }
  if (at > NOW) NOW = at;
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-large-mode.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the seeded Math.random (the port's xorshift32) ----------
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

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexes = a => Array.from(a, hex);
function colourOf(c) {
  if (c == null || c === 'none') return null;
  must(typeof c === 'string', 'a colour that is not a string');
  const p = echarts.color.parse(c);
  return p ? [p[0], p[1], p[2], p[3]] : null;
}
const rectRec = r => (r ? [r.x, r.y, r.width, r.height].map(hex) : null);

// ---------- charts with a live TooltipView ----------
function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
(function enableTooltips() {
  const probe = newChart();
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object' && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}

// ---------- the data ----------
let lcg = 1;
function seed(s) { lcg = s >>> 0; }
function rnd(lo, hi) {
  lcg = (Math.imul(lcg, 1103515245) + 12345) >>> 0;
  return lo + ((lcg >>> 8) % (hi - lo + 1));
}
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
function vals(n, lo, hi, s) {
  seed(s);
  return Array.from({ length: n }, () => rnd(lo, hi));
}
function pts(n, s, xr, yr) {
  seed(s);
  return Array.from({ length: n }, () => [rnd(xr[0], xr[1]), rnd(yr[0], yr[1])]);
}
function ohlc(n, s) {
  seed(s);
  let last = 100;
  const out = [];
  for (let i = 0; i < n; i++) {
    const o = last + rnd(-6, 6);
    const c = o + rnd(-10, 10);
    const lo = Math.min(o, c) - rnd(0, 8);
    const hi = Math.max(o, c) + rnd(0, 8);
    out.push([o, c, lo, hi]);
    last = c;
  }
  return out;
}

const GRID = { left: 60, right: 40, top: 40, bottom: 40 };
const COLORS = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
function base(extra) {
  return Object.assign({ animation: false, color: COLORS, grid: GRID, tooltip: {} }, extra);
}
const catX = n => ({ xAxis: { type: 'category', data: cats(n) }, yAxis: { type: 'value' } });

// ---------- the cases ----------
// steps: ['move', at] | ['leave'] | ['action', payload] | ['zoom', start, end]
// at: [x, y] | {on: [s, k]} | {gap: [s, k]} | {wick: [s, k]} | {item: [s, k]} | {edge: [s, k, dx, dy]}
const CASES = [];
function C(id, group, note, option, steps, watch) {
  CASES.push({ id, group, note, option, steps: steps || [], watch: watch || [] });
}

// A. the switch
C('bar-399', 'switch', 'bar large: true, 399 rows: one under the default threshold 400 -- normal',
  base(Object.assign(catX(399), { series: [{ type: 'bar', large: true, data: vals(399, 1, 100, 11) }] })));
C('bar-400', 'switch', 'bar large: true, 400 rows: the default threshold -- large',
  base(Object.assign(catX(400), { series: [{ type: 'bar', large: true, data: vals(400, 1, 100, 12) }] })),
  [['move', { on: [0, 200] }], ['move', { on: [0, 7] }], ['leave']]);
C('bar-401', 'switch', 'bar large: true, 401 rows -- large',
  base(Object.assign(catX(401), { series: [{ type: 'bar', large: true, data: vals(401, 1, 100, 13) }] })));
C('bar-few', 'switch', 'bar large: true, 5 rows -- normal',
  base(Object.assign(catX(5), { series: [{ type: 'bar', large: true, data: [3, 8, 5, 9, 2] }] })),
  [['move', { item: [0, 1] }]]);
C('bar-th0', 'switch', 'bar large: true, largeThreshold 0, 3 rows -- large',
  base(Object.assign(catX(3), { series: [{ type: 'bar', large: true, largeThreshold: 0, data: [3, 8, 5] }] })),
  [['move', { on: [0, 0] }], ['move', { on: [0, 1] }], ['move', { gap: [0, 1] }], ['move', { on: [0, 2] }], ['leave']]);
C('bar-off', 'switch', 'bar large: false, 450 rows -- normal',
  base(Object.assign(catX(450), { series: [{ type: 'bar', data: vals(450, 1, 100, 14) }] })));
C('sc-49', 'switch', 'scatter large: true, largeThreshold 50, 49 points -- normal',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', large: true, largeThreshold: 50, data: pts(49, 21, [0, 100], [0, 100]) }] }));
C('sc-50', 'switch', 'scatter, 50 points -- large',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', large: true, largeThreshold: 50, data: pts(50, 22, [0, 100], [0, 100]) }] }),
  [['move', { on: [0, 10] }], ['move', { on: [0, 30] }], ['leave']]);
C('sc-51', 'switch', 'scatter, 51 points -- large',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', large: true, largeThreshold: 50, data: pts(51, 23, [0, 100], [0, 100]) }] }));
C('sc-1999', 'switch', 'scatter large: true, 1999 points: under the default threshold 2000 -- normal',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', large: true, data: pts(1999, 24, [0, 1000], [0, 1000]) }] }));
C('sc-2000', 'switch', 'scatter large: true, 2000 points -- large',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'scatter', large: true, data: pts(2000, 25, [0, 1000], [0, 1000]) }] }),
  [['move', { on: [0, 1000] }]]);
C('cd-599', 'switch', 'candlestick, 599 rows: under its default threshold 600 (large is on by default) -- normal',
  base(Object.assign(catX(599), { yAxis: { type: 'value', scale: true }, series: [{ type: 'candlestick', data: ohlc(599, 31) }] })));
C('cd-600', 'switch', 'candlestick, 600 rows -- large',
  base(Object.assign(catX(600), { yAxis: { type: 'value', scale: true }, series: [{ type: 'candlestick', data: ohlc(600, 32) }] })),
  [['move', { wick: [0, 300] }]]);
C('cd-601', 'switch', 'candlestick, 601 rows -- large',
  base(Object.assign(catX(601), { yAxis: { type: 'value', scale: true }, series: [{ type: 'candlestick', data: ohlc(601, 33) }] })));
C('cd-off', 'switch', 'candlestick large: false, 650 rows -- normal',
  base(Object.assign(catX(650), { yAxis: { type: 'value', scale: true }, series: [{ type: 'candlestick', large: false, data: ohlc(650, 34) }] })));
C('line-large', 'switch', 'a line with large: true and largeThreshold 5: the pipeline says large, the line view draws as ever',
  base(Object.assign(catX(10), { series: [{ type: 'line', large: true, largeThreshold: 5, data: vals(10, 1, 50, 15) }] })));

// B. bars
C('bar-v-two', 'bar', 'two large bar series side by side, negative values, the first with a background',
  base(Object.assign(catX(30), {
    series: [
      { type: 'bar', large: true, largeThreshold: 10, showBackground: true, data: vals(30, -40, 90, 41) },
      { type: 'bar', large: true, largeThreshold: 10, data: vals(30, 5, 60, 42) },
    ],
  })),
  [['move', { on: [0, 4] }], ['move', { on: [1, 4] }], ['move', { on: [0, 5] }], ['move', { gap: [1, 5] }], ['move', { edge: [0, 9, 0, -1] }], ['move', { on: [1, 20] }], ['leave']]);
C('bar-h', 'bar', 'horizontal large bars (category y), negative values, a background',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'category', data: cats(24) },
    series: [{ type: 'bar', large: true, largeThreshold: 10, showBackground: true, data: vals(24, -50, 80, 43) }] }),
  [['move', { on: [0, 3] }], ['move', { on: [0, 11] }], ['move', { gap: [0, 11] }], ['leave']]);
C('bar-stack', 'bar', 'two stacked large bar series, mixed signs',
  base(Object.assign(catX(20), {
    series: [
      { type: 'bar', stack: 'a', large: true, largeThreshold: 10, data: vals(20, -30, 50, 44) },
      { type: 'bar', stack: 'a', large: true, largeThreshold: 10, data: vals(20, -20, 40, 45) },
    ],
  })),
  [['move', { on: [1, 3] }], ['move', { on: [0, 4] }], ['move', { on: [1, 4] }], ['move', { on: [1, 12] }], ['leave']]);
C('bar-minheight', 'bar', 'barMinHeight 6 with zeros and small values',
  base(Object.assign(catX(12), { yAxis: { type: 'value', max: 100 },
    series: [{ type: 'bar', large: true, largeThreshold: 5, barMinHeight: 6, data: [0, 1, 50, 0, 2, -1, 70, 0, 3, 90, 0, 4] }] })),
  [['move', { on: [0, 0] }], ['move', { on: [0, 5] }]]);
C('bar-clip', 'bar', 'clip (default true): values past the y max reach above the plot; the group clip cuts the hover there too',
  base(Object.assign(catX(12), { yAxis: { type: 'value', max: 50 },
    series: [{ type: 'bar', large: true, largeThreshold: 5, data: [20, 80, 30, 120, 10, 60, 45, 90, 5, 75, 40, 100] }] })),
  [['move', { on: [0, 1] }], ['move', { colY: [0, 1, 20] }], ['move', { colY: [0, 3, 30] }], ['leave']]);
C('bar-noclip', 'bar', 'clip: false: the same bars, hovered above the plot',
  base(Object.assign(catX(12), { yAxis: { type: 'value', max: 50 },
    series: [{ type: 'bar', large: true, largeThreshold: 5, clip: false, data: [20, 80, 30, 120, 10, 60, 45, 90, 5, 75, 40, 100] }] })),
  [['move', { colY: [0, 1, 20] }], ['move', { colY: [0, 3, 30] }], ['leave']]);
C('bar-null', 'bar', 'a null among large bars: the path bounding rect is not a number and nothing is hovered',
  base(Object.assign(catX(20), { series: [{ type: 'bar', large: true, largeThreshold: 5, data: vals(20, 5, 90, 46).map((v, i) => (i === 7 ? null : v)) }] })),
  [['move', { mid: [0, 3] }], ['move', { mid: [0, 12] }]]);
C('bar-width', 'bar', 'barWidth 4 px and a second series at 90%',
  base(Object.assign(catX(16), {
    series: [
      { type: 'bar', large: true, largeThreshold: 5, barWidth: 4, data: vals(16, 10, 90, 47) },
      { type: 'bar', large: true, largeThreshold: 5, barWidth: '90%', data: vals(16, 10, 90, 48) },
    ],
  })),
  [['move', { on: [0, 2] }], ['move', { on: [1, 2] }]]);
C('bar-dz', 'bar', 'a slider dataZoom filtering: 30 of 40 large, zoomed to 14 normal, back to 40 large',
  base(Object.assign(catX(40), { dataZoom: [{ type: 'slider', start: 25, end: 100 }],
    series: [{ type: 'bar', large: true, largeThreshold: 30, data: vals(40, 5, 95, 49) }] })),
  [['move', { on: [0, 4] }], ['zoom', 25, 60], ['move', { item: [0, 4] }], ['zoom', 0, 100], ['move', { on: [0, 4] }], ['leave']]);

// C. scatter
C('sc-basic', 'scatter', 'large scatter on value axes, overlapping points: the scan goes top down',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, data: pts(60, 51, [0, 50], [0, 50]).concat([[20, 20], [20.5, 20.5], [21, 21]]) }] }),
  [['move', { on: [0, 5] }], ['move', { on: [0, 6] }], ['move', { on: [0, 61] }], ['move', { pt: [0, 60, 0, 0] }], ['move', { pt: [0, 62, 3, 3] }], ['move', [70, 380]], ['leave']]);
C('sc-types', 'scatter', 'three large scatters: triangle [14, 8], emptyCircle (filled in large), roundRect 12',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [
      { type: 'scatter', large: true, largeThreshold: 10, symbol: 'triangle', symbolSize: [14, 8], data: pts(15, 52, [0, 100], [0, 100]) },
      { type: 'scatter', large: true, largeThreshold: 10, symbol: 'emptyCircle', symbolSize: 9, data: pts(15, 53, [0, 100], [0, 100]) },
      { type: 'scatter', large: true, largeThreshold: 10, symbol: 'roundRect', symbolSize: 12, data: pts(15, 54, [0, 100], [0, 100]) },
    ] }),
  [['move', { on: [0, 2] }], ['move', { on: [1, 2] }], ['move', { on: [2, 2] }], ['move', { edge: [0, 4, 6, 3] }], ['leave']]);
C('sc-boost', 'scatter', 'symbolSize 3: drawn by fillRect; the hit box is 4 wide but the bounding rect only 3',
  base({ xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, symbolSize: 3, data: pts(20, 55, [10, 90], [10, 90]).concat([[95, 50], [5, 50]]) }] }),
  [['move', { on: [0, 3] }], ['move', { pt: [0, 20, 2, 0] }], ['move', { pt: [0, 20, 1, 0] }], ['move', { pt: [0, 21, -2, 0] }], ['leave']]);
C('sc-clip', 'scatter', 'points past the x max: not drawn (the soft clip) but still hovered',
  base({ xAxis: { type: 'value', max: 80 }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, data: pts(20, 56, [0, 75], [0, 100]).concat([[84, 50], [86, 20]]) }] }),
  [['move', { pt: [0, 20, 0, 0] }], ['move', { on: [0, 4] }], ['leave']]);
C('sc-noclip', 'scatter', 'clip false: the same points, no soft clip',
  base({ xAxis: { type: 'value', max: 80 }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, clip: false, data: pts(20, 56, [0, 75], [0, 100]).concat([[84, 50], [86, 20]]) }] }));
C('sc-null', 'scatter', 'a null point: the bounding rect is not a number and nothing is hovered',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, data: pts(20, 57, [0, 100], [0, 100]).concat([[null, 30]]) }] }),
  [['move', { mid: [0, 2] }], ['move', { mid: [0, 9] }]]);
C('sc-style', 'scatter', 'itemStyle border and opacity; a data item with its own colour (large ignores it)',
  base({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, symbolSize: 14,
      itemStyle: { borderColor: '#333333', borderWidth: 2, opacity: 0.5 },
      data: pts(20, 58, [0, 100], [0, 100]).map((p, i) => (i === 3 ? { value: p, itemStyle: { color: '#ff0000' } } : p)) }] }),
  [['move', { on: [0, 3] }]]);
C('sc-dz', 'scatter', 'an inside dataZoom on x filtering a large scatter below its threshold and back',
  base({ xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value' }, dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 0, end: 100 }],
    series: [{ type: 'scatter', large: true, largeThreshold: 30, data: pts(50, 59, [0, 100], [0, 100]) }] }),
  [['move', { on: [0, 8] }], ['zoom', 20, 60], ['move', { item: [0, 3] }], ['zoom', 10, 100], ['move', { on: [0, 8] }], ['leave']]);
C('sc-jitter', 'scatter', 'a large scatter on a category x with jitter 30: the jittered points are Float32',
  base({ xAxis: { type: 'category', data: cats(4), jitter: 30 }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', large: true, largeThreshold: 10, symbolSize: 8, data: (() => { seed(60); return Array.from({ length: 40 }, () => [rnd(0, 3), rnd(0, 100)]); })() }] }),
  [['move', { on: [0, 5] }]]);
C('sc-emph', 'scatter', 'emphasis: a large scatter next to a line with focus series; hovering the line blurs nothing large; highlight actions do nothing',
  base({ legend: {}, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [
      { type: 'scatter', name: 'big', large: true, largeThreshold: 10, data: pts(30, 61, [0, 100], [0, 100]) },
      { type: 'line', name: 'line', emphasis: { focus: 'series' }, data: [[5, 90], [50, 95], [95, 92]] },
    ] }),
  [['move', { on: [0, 4] }], ['move', { item: [1, 1] }], ['leave'], ['action', { type: 'highlight', seriesIndex: 0 }], ['action', { type: 'highlight', seriesIndex: 0, dataIndex: 3 }], ['action', { type: 'downplay', seriesIndex: 0 }]],
  [[1, 1]]);

// D. candlestick
C('cd-basic', 'candle', 'large candlesticks (threshold 30), own colours: hovering a wick finds an element with no data',
  base(Object.assign(catX(40), { yAxis: { type: 'value', scale: true },
    series: [{ type: 'candlestick', largeThreshold: 30, itemStyle: { color: '#ff3300', color0: '#00aa44', borderColor: '#cc0000', borderColor0: '#008833', borderWidth: 2 }, data: ohlc(40, 71) }] })),
  [['move', { wick: [0, 5] }], ['move', { wick: [0, 6] }], ['move', { edge: [0, 8, 2, 0] }], ['move', { edge: [0, 8, 3, 0] }], ['leave']]);
C('cd-doji', 'candle', 'borderColorDoji: rows with open = close draw on the third path',
  base(Object.assign(catX(36), { yAxis: { type: 'value', scale: true },
    series: [{ type: 'candlestick', largeThreshold: 30, itemStyle: { borderColorDoji: '#888888' },
      data: ohlc(36, 72).map((r, i) => (i % 5 === 2 ? [r[0], r[0], r[2], r[3]] : r)) }] })),
  [['move', { wick: [0, 2] }]]);
C('cd-axis', 'candle', 'an axis tooltip over large candlesticks',
  base(Object.assign(catX(40), { tooltip: { trigger: 'axis' }, yAxis: { type: 'value', scale: true },
    series: [{ type: 'candlestick', largeThreshold: 30, data: ohlc(40, 73) }] })),
  [['move', { wick: [0, 11] }], ['move', { mid0: [0, 20] }], ['leave']]);
C('cd-clip', 'candle', 'a y max under the highs: the group clip cuts the wick and its hover',
  base(Object.assign(catX(40), { yAxis: { type: 'value', min: 60, max: 110 },
    series: [{ type: 'candlestick', largeThreshold: 30, data: ohlc(40, 74) }] })),
  [['move', { wickTop: [0, 0, -6] }], ['move', { wick: [0, 1] }]]);
C('cd-vertical', 'candle', 'a category y: upstream stores y twice and draws zero-length wicks',
  base({ xAxis: { type: 'value', scale: true }, yAxis: { type: 'category', data: cats(40) },
    series: [{ type: 'candlestick', largeThreshold: 30, data: ohlc(40, 75) }] }));

// E. emphasis over bars
C('bar-emph', 'bar', 'a large bar beside a small one with focus series: hover, highlight, legend hover',
  base(Object.assign(catX(20), { legend: {},
    series: [
      { type: 'bar', name: 'big', large: true, largeThreshold: 10, emphasis: { focus: 'series' }, data: vals(20, 10, 90, 81) },
      { type: 'bar', name: 'small', emphasis: { focus: 'series' }, data: vals(20, 5, 40, 82) },
    ] })),
  [['move', { on: [0, 2] }], ['move', { item: [1, 2] }], ['leave'], ['action', { type: 'highlight', seriesName: 'big' }], ['action', { type: 'downplay', seriesName: 'big' }], ['action', { type: 'highlight', seriesIndex: 0, dataIndex: 4 }]],
  [[1, 2], [1, 3]]);

// =====================================================================
// the elements
// =====================================================================
function largeKind(el) {
  if (el.type === 'largeBar') return el.silent ? 'barBg' : 'bar';
  if (el.type === 'largeCandlestickBox') return 'candle';
  if (typeof el.findDataIndex === 'function' && el.symbolProxy) return 'symbol';
  return null;
}
function largeEls(chart, seriesModel) {
  const out = [];
  const view = chart.getViewOfSeriesModel(seriesModel);
  view.group.traverse(el => { if (!el.isGroup && largeKind(el)) out.push(el); });
  return out;
}
function styleRec(el) {
  const s = el.style;
  return {
    fill: colourOf(s.fill),
    stroke: colourOf(s.stroke),
    lineWidth: hex(s.lineWidth == null ? 1 : s.lineWidth),
    opacity: hex(s.opacity == null ? 1 : s.opacity),
  };
}
function elRec(el) {
  const kind = largeKind(el);
  const r = { kind, z2: el.z2, silent: !!el.silent, bbox: rectRec(el.getBoundingRect()), style: styleRec(el) };
  if (kind === 'bar' || kind === 'barBg') {
    r.points = hexes(el.shape.points);
    r.indices = Array.from(el.largeDataIndices);
    r.barWidth = hex(el.barWidth);
    r.baseDim = el.baseDimIdx;
  }
  else if (kind === 'symbol') {
    r.points = hexes(el.shape.points);
    r.size = el.shape.size.map(hex);
    r.symbolType = el.symbolProxy.shape.symbolType;
    r.boost = el.shape.size[0] < 4;
    r.softClip = el.softClipShape ? rectRec(el.softClipShape) : null;
  }
  else {
    r.sign = el.__sign;
  }
  return r;
}
function seriesRecords(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    const data = sm.getData();
    let items = 0;
    data.eachItemGraphicEl(el => { if (el) items++; });
    const els = largeEls(chart, sm);
    const view = chart.getViewOfSeriesModel(sm);
    const cp = view.group.getClipPath();
    const rec = {
      seriesIndex: sm.seriesIndex, type: sm.subType, count: data.count(),
      pipelineLarge: !!sm.pipelineContext.large,
      mode: els.length ? 'large' : 'normal', items,
      clip: cp ? [cp.shape.x, cp.shape.y, cp.shape.width, cp.shape.height].map(hex) : null,
      largePoints: null,
      els: els.map(elRec),
    };
    if (sm.subType === 'candlestick' && els.length) {
      rec.largePoints = hexes(els[0].shape.points);
      for (const e of rec.els) delete e.points;
    }
    out.push(rec);
  });
  return out;
}

// =====================================================================
// the self-checks' arithmetic (R1-R3)
// =====================================================================
const RECIPES = { R1: 0, R2: 0, R3: 0, R4: 0 };
function barScan(el, x, y) {
  const p = el.shape.points;
  const bd = el.baseDimIdx;
  const vd = 1 - bd;
  for (let i = 0, n = p.length / 3; i < n; i++) {
    const sp = [];
    const sz = [];
    sz[bd] = el.barWidth;
    sz[vd] = p[i * 3 + 2];
    sp[bd] = p[i * 3 + bd];
    sp[vd] = p[i * 3 + vd];
    if (sz[vd] < 0) { sp[vd] += sz[vd]; sz[vd] = -sz[vd]; }
    if (x >= sp[0] && x <= sp[0] + sz[0] && y >= sp[1] && y <= sp[1] + sz[1]) return el.largeDataIndices[i];
  }
  return -1;
}
function symbolScan(el, x, y) {
  const p = el.shape.points;
  const w = Math.max(el.shape.size[0], 4);
  const h = Math.max(el.shape.size[1], 4);
  for (let idx = p.length / 2 - 1; idx >= 0; idx--) {
    const x0 = p[idx * 2] - w / 2;
    const y0 = p[idx * 2 + 1] - h / 2;
    if (x >= x0 && y >= y0 && x <= x0 + w && y <= y0 + h) return idx;
  }
  return -1;
}
function rectHas(r, x, y) {
  return x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3];
}
// the bbox from the recorded points, as the port computes it
function bboxOf(el) {
  const k = largeKind(el);
  let x0 = Number.MAX_VALUE, y0 = Number.MAX_VALUE, x1 = -Number.MAX_VALUE, y1 = -Number.MAX_VALUE;
  const mn = (a, b) => Math.min(a, b);
  const mx = (a, b) => Math.max(a, b);
  const p = el.shape.points;
  if (k === 'bar' || k === 'barBg') {
    const bd = el.baseDimIdx;
    for (let i = 0; i < p.length; i += 3) {
      const rx = p[i], ry = p[i + 1];
      const w = bd === 0 ? el.barWidth : p[i + 2];
      const h = bd === 0 ? p[i + 2] : el.barWidth;
      x0 = mn(x0, mn(rx, rx + w)); y0 = mn(y0, mn(ry, ry + h));
      x1 = mx(x1, mx(rx, rx + w)); y1 = mx(y1, mx(ry, ry + h));
    }
    if (!p.length) { x0 = y0 = x1 = y1 = 0; }
    return [x0, y0, x1 - x0, y1 - y0];
  }
  if (k === 'symbol') {
    let a = Infinity, b = Infinity, c = -Infinity, d = -Infinity;
    for (let i = 0; i < p.length; i += 2) {
      a = Math.min(p[i], a); c = Math.max(p[i], c);
      b = Math.min(p[i + 1], b); d = Math.max(p[i + 1], d);
    }
    const w = el.shape.size[0], h = el.shape.size[1];
    return [a - w / 2, b - h / 2, c - a + w, d - b + h];
  }
  // candle: the moves and lines of its own sign, grown by max(lineWidth, 5)
  let any = false;
  for (let i = 0; i < p.length; i += 4) {
    if (p[i] !== el.__sign) continue;
    const x = p[i + 1];
    // M then L: the M resets the subpath box, the L unions the segment
    x0 = mn(x0, mn(x, x)); x1 = mx(x1, mx(x, x));
    y0 = mn(y0, mn(p[i + 2], p[i + 3])); y1 = mx(y1, mx(p[i + 2], p[i + 3]));
    any = true;
  }
  if (!any) { x0 = y0 = x1 = y1 = 0; }
  const r = [x0, y0, x1 - x0, y1 - y0];
  if (any) {
    const w = Math.max(el.style.lineWidth == null ? 1 : el.style.lineWidth, 5);
    r[2] += w; r[3] += w; r[0] -= w / 2; r[1] -= w / 2;
  }
  return r;
}

// =====================================================================
// pointer positions
// =====================================================================
function seriesModel(chart, s) { return chart.getModel().getSeriesByIndex(s); }
function elOf(chart, s, kind, sign) {
  return largeEls(chart, seriesModel(chart, s)).find(e => largeKind(e) === kind && (sign == null || e.__sign === sign));
}
function hoverTarget(chart, x, y) {
  return chart.getZr().handler.findHover(x, y).target;
}
function barRect(el, k) {
  const p = el.shape.points;
  const bd = el.baseDimIdx;
  const vd = 1 - bd;
  const i = el.largeDataIndices.indexOf ? Array.from(el.largeDataIndices).indexOf(k) : k;
  const sp = [], sz = [];
  sz[bd] = el.barWidth; sz[vd] = p[i * 3 + 2];
  sp[bd] = p[i * 3 + bd]; sp[vd] = p[i * 3 + vd];
  if (sz[vd] < 0) { sp[vd] += sz[vd]; sz[vd] = -sz[vd]; }
  return { x: sp[0], y: sp[1], w: sz[0], h: sz[1] };
}
function search(cx, cy, ok, where) {
  for (let rad = 0; rad <= 8; rad++) {
    for (let dx = -rad; dx <= rad; dx++) {
      for (let dy = -rad; dy <= rad; dy++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
        const x = Math.round(cx) + dx;
        const y = Math.round(cy) + dy;
        if (x < 1 || y < 1 || x > W - 2 || y > H - 2) continue;
        if (ok(x, y)) return [x, y];
      }
    }
  }
  throw new OracleError(where + ': no point');
}
function resolveAt(chart, at, where) {
  if (Array.isArray(at)) return at;
  if (at.on) {
    const [s, k] = at.on;
    const sm = seriesModel(chart, s);
    const els = largeEls(chart, sm);
    const bar = els.find(e => largeKind(e) === 'bar');
    if (bar) {
      const r = barRect(bar, k);
      return search(r.x + r.w / 2, r.y + r.h / 2, (x, y) => hoverTarget(chart, x, y) === bar && barScan(bar, x, y) === k, where);
    }
    const sym = els.find(e => largeKind(e) === 'symbol');
    must(sym, where + ': no large element');
    const p = sym.shape.points;
    return search(p[k * 2], p[k * 2 + 1], (x, y) => hoverTarget(chart, x, y) === sym && sym.hoverDataIdx === k, where);
  }
  if (at.gap) {
    // halfway between two neighbouring bars, across the base axis, at the
    // first bar's middle along the value axis
    const [s, k] = at.gap;
    const bar = elOf(chart, s, 'bar');
    const a = barRect(bar, k);
    const b = barRect(bar, k + 1);
    if (bar.baseDimIdx === 0) return [Math.round((a.x + a.w + b.x) / 2), Math.round(a.y + a.h / 2)];
    return [Math.round(a.x + a.w / 2), Math.round((a.y + a.h + b.y) / 2)];
  }
  if (at.mid) {
    // the middle of a bar or a point, whatever is hovered there
    const [s, k] = at.mid;
    const bar = elOf(chart, s, 'bar');
    if (bar) { const r = barRect(bar, k); return [Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2)]; }
    const sym = elOf(chart, s, 'symbol');
    return [Math.round(sym.shape.points[k * 2]), Math.round(sym.shape.points[k * 2 + 1])];
  }
  if (at.mid0) {
    // a candle's x at the plot's middle height
    const [s, k] = at.mid0;
    const el = largeEls(chart, seriesModel(chart, s))[0];
    return [Math.round(el.shape.points[k * 4 + 1]), 200];
  }
  if (at.pt) {
    // a point's or a bar's anchor plus an offset: [s, k, dx, dy]
    const [s, k, dx, dy] = at.pt;
    const bar = elOf(chart, s, 'bar');
    if (bar) {
      const r = barRect(bar, k);
      // the bar's value end, above the plot when it overflows
      return [Math.round(r.x + r.w / 2) + dx, Math.round(r.y) + dy];
    }
    const sym = elOf(chart, s, 'symbol');
    return [Math.round(sym.shape.points[k * 2]) + dx, Math.round(sym.shape.points[k * 2 + 1]) + dy];
  }
  if (at.edge) {
    // a bar's right edge or a point's centre, plus an offset, unrounded
    // anchor rounded once
    const [s, k, dx, dy] = at.edge;
    const bar = elOf(chart, s, 'bar');
    if (bar) { const r = barRect(bar, k); return [Math.round(r.x + r.w) + dx, Math.round(r.y + r.h / 2) + dy]; }
    const sym = elOf(chart, s, 'symbol');
    if (sym) return [Math.round(sym.shape.points[k * 2]) + dx, Math.round(sym.shape.points[k * 2 + 1]) + dy];
    const el = largeEls(chart, seriesModel(chart, s))[0];
    const p = el.shape.points;
    return [Math.round(p[k * 4 + 1]) + dx, Math.round((p[k * 4 + 2] + p[k * 4 + 3]) / 2) + dy];
  }
  if (at.colY) {
    // a bar's middle across the base axis at a given height
    const [s, k, y] = at.colY;
    const r = barRect(elOf(chart, s, 'bar'), k);
    return [Math.round(r.x + r.w / 2), y];
  }
  if (at.wick) {
    const [s, k] = at.wick;
    const el = largeEls(chart, seriesModel(chart, s))[0];
    const p = el.shape.points;
    return [Math.round(p[k * 4 + 1]), Math.round((p[k * 4 + 2] + p[k * 4 + 3]) / 2)];
  }
  if (at.wickTop) {
    const [s, k, dy] = at.wickTop;
    const el = largeEls(chart, seriesModel(chart, s))[0];
    const p = el.shape.points;
    return [Math.round(p[k * 4 + 1]), Math.round(Math.min(p[k * 4 + 2], p[k * 4 + 3])) + dy];
  }
  if (at.item) {
    const [s, k] = at.item;
    const el = seriesModel(chart, s).getData().getItemGraphicEl(k);
    must(el, where + ': no item element');
    const g = el.getBoundingRect().clone();
    chart.getZr().storage.getDisplayList(true);
    if (el.transform) g.applyTransform(el.transform);
    return search(g.x + g.width / 2, g.y + g.height / 2, (x, y) => {
      const t = hoverTarget(chart, x, y);
      for (let e = t; e; e = e.__hostTarget || e.parent) {
        const d = ecData(e);
        if (d && d.dataIndex != null) return d.seriesIndex === s && d.dataIndex === k;
      }
      return false;
    }, where);
  }
  throw new OracleError(where + ': an unknown position');
}

// =====================================================================
// one case
// =====================================================================
function hoverRec(chart, x, y) {
  const t = hoverTarget(chart, x, y);
  if (!t) return null;
  const k = largeKind(t);
  if (k) {
    const d = ecData(t);
    return { kind: k, seriesIndex: d && d.seriesIndex != null ? d.seriesIndex : seriesOfLarge(chart, t), sign: k === 'candle' ? t.__sign : null,
      dataIndex: d && d.dataIndex != null ? d.dataIndex : null };
  }
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return { kind: 'item', seriesIndex: d.seriesIndex, dataIndex: d.dataIndex };
  }
  return { kind: 'other' };
}
function seriesOfLarge(chart, el) {
  let r = null;
  chart.getModel().eachSeries(sm => { if (largeEls(chart, sm).indexOf(el) >= 0) r = sm.seriesIndex; });
  return r;
}
function statesRec(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    for (const el of largeEls(chart, sm)) {
      out.push({ seriesIndex: sm.seriesIndex, kind: largeKind(el), sign: largeKind(el) === 'candle' ? el.__sign : null,
        currentStates: (el.currentStates || []).slice(), opacity: hex(el.style.opacity == null ? 1 : el.style.opacity) });
    }
  });
  return out;
}
function normalRec(chart, watch) {
  return watch.map(([s, k]) => {
    let el = seriesModel(chart, s).getData().getItemGraphicEl(k);
    // a symbol is a group: its path carries the states
    if (el && el.isGroup) {
      let leaf = null;
      el.traverse(c => { if (!leaf && !c.isGroup) leaf = c; });
      el = leaf;
    }
    return { seriesIndex: s, dataIndex: k, states: el ? (el.currentStates || []).slice() : null };
  });
}

let LOG = null;
function recordCase(c) {
  const chart = newChart();
  try {
    const where = c.id;
    const events = [];
    for (const t of ['mouseover', 'mousemove', 'mouseout']) {
      chart.on(t, e => {
        if (!LOG) return;
        const sm = seriesModel(chart, e.seriesIndex);
        const inner = sm ? sm.getData().indexOfRawIndex(e.dataIndex) : null;
        LOG.push({ type: t, seriesIndex: e.seriesIndex, dataIndex: e.dataIndex, dataIndexInside: inner });
      });
    }
    let lastWhich = null;
    let lastInner = null;
    const opt = JSON.parse(JSON.stringify(c.option));
    const fed = JSON.parse(JSON.stringify(c.option));
    fed.tooltip = Object.assign({}, fed.tooltip);
    chart.setOption(fed);
    const view = (() => {
      const m = chart.getModel().getComponent('tooltip', 0);
      return m ? chart.getViewOfComponentModel(m) : null;
    })();
    must(view, where + ': no tooltip view');
    const show = view._showTooltipContent;
    view._showTooltipContent = function (tooltipModel, html, params) {
      if (Array.isArray(params)) {
        lastWhich = 'axis:' + (params.length ? params[0].axisValueLabel : '');
        lastInner = null;
      }
      else {
        lastWhich = 'item:' + params.seriesIndex + ':' + params.dataIndex;
        const sm = seriesModel(chart, params.seriesIndex);
        lastInner = sm ? sm.getData().indexOfRawIndex(params.dataIndex) : null;
      }
      const r = show.apply(this, arguments);
      // THE BOX IS NOT A TARGET: under node the richText box is a zrender
      // element on the chart's own canvas, and it would take the next hover
      // from what lies under it -- a browser's HTML box never does
      const ct = view._tooltipContent;
      if (ct && ct.el) ct.el.silent = true;
      return r;
    };
    const content = view._tooltipContent;
    const visible = () => !!(content && content.el && !content.el.ignore && !content.el.invisible);
    chart._onframe();
    chart.renderToSVGString();
    const records = [{ at: -1, series: seriesRecords(chart) }];
    checkRecord(chart, records[0], where);
    const steps = [];
    c.steps.forEach((s, i) => {
      settle(NOW + 500);
      NOW += 500;
      const st = { i, t: s[0], x: null, y: null };
      LOG = [];
      if (s[0] === 'move') {
        const at = resolveAt(chart, s[1], where + ' step ' + i);
        st.x = at[0];
        st.y = at[1];
        chart.getZr().handler.mousemove(raw(at[0], at[1]));
      }
      else if (s[0] === 'leave') {
        chart.getZr().handler.mouseout(raw(-1, -1));
      }
      else if (s[0] === 'action') {
        st.payload = s[1];
        chart.dispatchAction(JSON.parse(JSON.stringify(s[1])));
      }
      else if (s[0] === 'zoom') {
        st.payload = { type: 'dataZoom', start: s[1], end: s[2] };
        chart.dispatchAction({ type: 'dataZoom', start: s[1], end: s[2] });
      }
      chart._onframe();
      chart.renderToSVGString();
      // the timers the step armed (the tooltip's hideDelay) run out within
      // half a second; then the frame
      settle(NOW + 500);
      chart._onframe();
      chart.renderToSVGString();
      st.events = LOG;
      LOG = null;
      st.hover = st.x == null ? null : hoverRec(chart, st.x, st.y);
      const vis = visible();
      st.tooltip = { shown: vis, which: vis ? lastWhich : null, inner: vis ? lastInner : null };
      st.states = statesRec(chart);
      st.normal = normalRec(chart, c.watch);
      if (st.x != null) checkHover(chart, st, where + ' step ' + i);
      steps.push(st);
      if (s[0] === 'zoom') {
        const r = { at: i, series: seriesRecords(chart) };
        checkRecord(chart, r, where + ' step ' + i);
        records.push(r);
      }
    });
    return { id: c.id, group: c.group, note: c.note, option: opt, records, steps };
  }
  finally {
    chart.dispose();
  }
}

// R1 and R3 over a step's hover; R2 and R4 over a record
function checkHover(chart, st, where) {
  const t = hoverTarget(chart, st.x, st.y);
  const k = t && largeKind(t);
  chart.getModel().eachSeries(sm => {
    for (const el of largeEls(chart, sm)) {
      if (largeKind(el) !== 'bar') continue;
      const rect = el.getBoundingRect();
      const winding = rect.contain(st.x, st.y) && el.contain(st.x, st.y);
      const scan = barScan(el, st.x, st.y);
      const bb = bboxOf(el);
      must(winding === (rectHas(bb, st.x, st.y) && scan >= 0), where + ': the winding and the scan disagree');
      RECIPES.R3++;
    }
  });
  if (!k) return;
  if (k === 'bar') {
    const want = barScan(t, st.x, st.y);
    must(st.hover.dataIndex === (want >= 0 ? want : null), where + ': R1 bar');
    RECIPES.R1++;
  }
  else if (k === 'symbol') {
    const bb = bboxOf(t);
    const want = rectHas(bb, st.x, st.y) ? symbolScan(t, st.x, st.y) : -1;
    must(want >= 0 && st.hover.dataIndex === want, where + ': R1 symbol');
    RECIPES.R1++;
  }
  else if (k === 'candle') {
    must(st.hover.dataIndex === null, where + ': a candle with data');
  }
}
function checkRecord(chart, rec, where) {
  chart.getModel().eachSeries(sm => {
    for (const el of largeEls(chart, sm)) {
      const want = bboxOf(el);
      const got = el.getBoundingRect();
      const same = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;
      must(same(want[0], got.x) && same(want[1], got.y) && same(want[2], got.width) && same(want[3], got.height),
        where + ': R2 ' + largeKind(el) + ' ' + JSON.stringify(want) + ' vs ' + JSON.stringify([got.x, got.y, got.width, got.height]));
      RECIPES.R2++;
      const kind = largeKind(el);
      if (kind === 'symbol') {
        // R4: the store through the cartesian, Float32; the jittered case only
        // through the fixed dimension
        const data = sm.getData();
        const cs = sm.coordinateSystem;
        const p = el.shape.points;
        const jit = !!(cs.getBaseAxis && cs.getBaseAxis().type === 'category' && sm.coordinateSystem.getBaseAxis().model.get('jitter'));
        for (let i = 0; i < data.count(); i++) {
          const q = cs.dataToPoint([data.get(data.mapDimension('x'), i), data.get(data.mapDimension('y'), i)]);
          const fx = Math.fround(q[0]);
          const fy = Math.fround(q[1]);
          must(same(p[i * 2 + 1], fy) && (jit || same(p[i * 2], fx)), where + ': R4 point ' + i);
          RECIPES.R4++;
        }
      }
    }
  });
}

// =====================================================================
// guards
// =====================================================================
function guards(cases) {
  const g = [];
  const get = id => cases.find(c => c.id === id);
  const s0 = (id, at) => get(id).records[at || 0].series[0];
  const G = (name, cond) => { must(cond, 'guard: ' + name); g.push(name); };
  G('threshold - 1 is normal', s0('bar-399').mode === 'normal' && s0('sc-49').mode === 'normal' && s0('cd-599').mode === 'normal' && s0('sc-1999').mode === 'normal');
  G('the threshold is large', s0('bar-400').mode === 'large' && s0('sc-50').mode === 'large' && s0('cd-600').mode === 'large' && s0('sc-2000').mode === 'large');
  G('threshold + 1 is large', s0('bar-401').mode === 'large' && s0('sc-51').mode === 'large' && s0('cd-601').mode === 'large');
  G('large with few rows is normal', s0('bar-few').mode === 'normal' && s0('bar-few').items === 5);
  G('largeThreshold 0 is large', s0('bar-th0').mode === 'large');
  G('large false is normal', s0('bar-off').mode === 'normal' && s0('cd-off').mode === 'normal');
  G('a line never draws large though the pipeline says so', s0('line-large').pipelineLarge && s0('line-large').mode === 'normal');
  G('a background is a second, silent bar path', s0('bar-v-two').els.some(e => e.kind === 'barBg' && e.silent));
  G('the null poisons the bar bbox', s0('bar-null').els[0].bbox.some(h => h === '7ff8000000000000'));
  G('the null bar is never hovered', get('bar-null').steps.every(s => !s.hover));
  G('the null point is never hovered', get('sc-null').steps.every(s => !s.hover));
  G('a boost symbol', s0('sc-boost').els[0].boost === true);
  G('a hit box past the bbox does not hover', get('sc-boost').steps[1].hover === null && get('sc-boost').steps[3].hover === null);
  G('a point inside the bbox at the 4 px box hovers', get('sc-boost').steps[2].hover && get('sc-boost').steps[2].hover.kind === 'symbol');
  G('clip cuts the bar hover above the plot', get('bar-clip').steps[1].hover === null);
  G('no clip hovers above the plot', get('bar-noclip').steps[0].hover && get('bar-noclip').steps[0].hover.kind === 'bar');
  G('a soft-clipped point is still hovered', get('sc-clip').steps[0].hover && get('sc-clip').steps[0].hover.kind === 'symbol');
  G('the soft clip is null without clip', s0('sc-noclip').els[0].softClip === null);
  G('a candle hover has no data and no item tooltip', get('cd-basic').steps[0].hover && get('cd-basic').steps[0].hover.kind === 'candle' && !get('cd-basic').steps[0].tooltip.shown);
  G('an axis tooltip over large candles', get('cd-axis').steps.some(s => s.tooltip.shown && /^axis:/.test(s.tooltip.which)));
  G('an item tooltip over a large bar', get('bar-v-two').steps[0].tooltip.shown && get('bar-v-two').steps[0].tooltip.which === 'item:0:4');
  G('an item tooltip over a large symbol', get('sc-basic').steps[0].tooltip.shown);
  G('one mouseover across two bars of one path', get('bar-th0').steps[1].events.every(e => e.type !== 'mouseover'));
  G('no mouse event in a bar gap but a target', get('bar-th0').steps[2].events.length === 0 || get('bar-th0').steps[2].hover === null);
  G('overlapping points: the later one wins', get('sc-basic').steps[3].hover && get('sc-basic').steps[3].hover.dataIndex >= 60);
  G('no states on a large element', cases.every(c => c.steps.every(s => s.states.every(e => e.currentStates.length === 0))));
  G('a hovered line symbol is in emphasis, the large batch beside it in no state', get('sc-emph').steps[1].normal[0].states.indexOf('emphasis') >= 0
    && get('sc-emph').steps[1].states.every(e => e.currentStates.length === 0));
  G('a highlight on a large series with focus series blurs the other series', get('bar-emph').steps[3].normal.every(n => n.states.indexOf('blur') >= 0));
  G('the doji path holds points', s0('cd-doji').largePoints.some((h, i) => i % 4 === 0 && h === hex(0)));
  G('a vertical candle has zero-length wicks', (() => { const p = s0('cd-vertical').largePoints; return p.length > 0 && p[2] === p[3]; })());
  G('dataZoom switches to normal', get('bar-dz').records[1].series[0].mode === 'normal' && get('bar-dz').records[2].series[0].mode === 'large');
  G('the large bar index is inner', get('bar-dz').steps[0].hover && get('bar-dz').steps[0].tooltip.inner === get('bar-dz').steps[0].hover.dataIndex
    && get('bar-dz').steps[0].tooltip.which !== 'item:0:' + get('bar-dz').steps[0].hover.dataIndex);
  G('the scatter dataZoom goes normal', get('sc-dz').records[1].series[0].mode === 'normal');
  G('emptyCircle is a filled circle path in large', get('sc-types').records[0].series[1].els[0].symbolType === 'circle'
    && get('sc-types').records[0].series[1].els[0].style.fill !== null);
  G('a large stack: the top series stands on the bottom one', s0('bar-stack').mode === 'large');
  G('the item colour is ignored in large', (() => { const e = s0('sc-style').els[0]; return e.style.fill && e.style.fill[0] !== 255; })());
  return g;
}

function generate() {
  const cases = CASES.map(recordCase);
  const gs = guards(cases);
  for (const k of Object.keys(RECIPES)) must(RECIPES[k] > 0, 'recipe ' + k + ' never ran');
  const out = {
    source: 'ECharts ' + echarts.version + ' dist (' + path.basename(DIST) + ') under node, svg, ssr init then _ssr = false, env.node = false',
    W, H, seed: SEED,
    notes: [
      'Every option has animation false; the oracle adds nothing to it but a hook on the tooltip view.',
      'hover is handler.findHover after the event; a large element\'s dataIndex is its ECData\'s (inner).',
      'The clock moves 1000 ms per step and never back, so the bar throttle always runs at once.',
    ],
    cases, guards: gs, recipes: Object.assign({}, RECIPES),
  };
  for (const k of Object.keys(RECIPES)) RECIPES[k] = 0;
  return JSON.stringify(out);
}

try {
  const a = generate();
  const b = generate();
  must(a === b, 'two generations differ');
  must(!a.includes('\\u0000'), 'a NUL in the output');
  JSON.parse(a);
  fs.writeFileSync(OUT, a);
  console.log('wrote ' + OUT + ' (' + CASES.length + ' cases, ' + a.length + ' bytes)');
  process.exit(0);
}
catch (e) {
  console.error(e && e.stack || e);
  process.exit(1);
}
