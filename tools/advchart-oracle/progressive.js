// Upstream's own answers for PROGRESSIVE RENDERING and APPENDDATA (batch
// 119, roadmap C9): which series render progressively (getProgressive /
// getProgressiveThreshold per type, the bar's `large` gate and its forced
// large mode, a view without incrementalPrepareRender never does), the
// chunks each frame adds (Math.round(progressive), 'sequential' or 'mod'
// through task.ts's modNext, the first-frame restart a 'mod' pipeline takes
// after setOption), the frame budget (echarts.ts _onframe: steps while
// TEST_FRAME_REMAIN_TIME = 1 ms is left), the elements those chunks leave
// (an element per datum, or a large batch per chunk: largeDataIndices
// written at [dataIndex] into an array of the chunk's count, the scatter
// batch merged until it holds 2e4 numbers), chart.appendData (the axes keep
// the extent of the last update; sequential pipelines carry on, 'mod' ones,
// a progressive or a large switch start again), the `rendered` and
// `finished` events, and the pointer over a chart half drawn.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node: echarts.init(null, null, {renderer: 'svg', ssr:
// true}) and right after init chart._ssr = false; echarts.env.node = false and
// the chart prototype's getDom answering an empty object, so TooltipView runs
// (large-mode.js's recipe). PROGRESSIVE NEEDS A CANVAS PAINTER:
// Scheduler.restorePipelines reads `zr.painter.type === 'canvas'`, so the
// script sets the SVG painter's `type` field to 'canvas' right after init
// (painter.getType() still answers 'svg'; nothing here draws). Every option
// has animation false.
//
// TIME. The global Date is replaced before the dist loads (large-mode.js's
// FakeDate); platformApi.getTime is Date.now. A FRAME is: due timers run,
// NOW += 16, zr.animation.update() (its 'frame' event runs the chart's
// _onframe), then zr._flush(false) -- the stage update the browser's loop
// does after the frame event (null under the ssr init). THE STEP COST: while
// a frame runs, scheduler.performSeriesTasks -- called once per iteration of
// _onframe's do / while -- moves NOW on by the case's cost, so an iteration
// "takes" that long: cost 1 is one chunk a frame, 0.4 is three (1 - 0.4 * 3
// < 0), 0 never ends a frame early. After every frame and step the display
// list is taken (getDisplayList(true)) so transforms are what a painted
// frame has. A pointer step moves NOW 1000 ms on first (the large bar's 30 ms
// throttle runs at once), then the handler's mousemove / mouseout, then the
// chart's _onframe with scheduler.unfinished held false (states applied, no
// chunk drawn), then due timers.
//
//   node tools/advchart-oracle/progressive.js
//
// writes tests/fixtures/advchart-progressive.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex   a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//         lowercase (NaN 7ff8000000000000); Float32 values widened.
//   fnv   FNV-1a 32 over the concatenated hex strings of a points array, as
//         an unsigned decimal, for a batch with more than 600 numbers.
//   rows  sorted unique data indices as inclusive ranges [[a, b], ...].
//
// Top level: source, W, H, notes[], cases[], guards[], recipes{}
//   case: id, group, note, replay (false: upstream recorded, the port
//     deviates on purpose -- see the spec), option (as fed to setOption),
//     cost (the initial step cost), snaps[]
//   snap: at (-1 the setOption, else the step index), t ('init' | 'frame' |
//     'append' | 'move' | 'leave' | 'cost' | 'snap'), x, y, data (append),
//     events [{type, seriesIndex, dataIndex, dataIndexInside}] -- `rendered`
//     and `finished` carry no series -- since the snap before,
//     unfinished (scheduler.unfinished after the step), series[], hover,
//     tooltip {shown, which, inner}, geom (t 'snap' only)
//   series: seriesIndex, type, count (getData().count()), prog
//     (pipelineContext.progressiveRender), large (pipelineContext.large),
//     mod (modDataCount, null), step (pipeline.step when progressiveEnabled,
//     else null), items (the datum elements in the view), rows, els[] (the
//     large elements in group order)
//   el: kind ('bar' | 'barBg' | 'symbol' | 'candle'), z2, silent, si
//     (a symbol batch's startIndex, null), n (numbers in points), pts (hex
//     list) or fnv, idx (bar: largeDataIndices), bw (bar width hex), bd
//     (baseDimIdx), size (symbol [w, h] hex), bbox [x, y, w, h] hex, sign
//   hover: {kind: 'item', seriesIndex, dataIndex} | {kind: <large kind>,
//     seriesIndex, sign, dataIndex} | {kind: 'other'} | null
//   geom: per series [{d, x, y} (a symbol's position) | {d, rect: [x, y, w,
//     h]}] in group order, hex
//
// Self-checks: R1 every recorded chunk (the rows a frame added to a 'mod'
// batch or a 'mod' normal series) recomputed here from task.ts's modNext
// formula; R2 every recorded large bbox recomputed from its points; R3 every
// hovered large bar's dataIndex recomputed from largeDataIndices and the
// forward scan; R4 the frame count to finish predicted from the cost and the
// chunk count. Guards: below. Two generations in one process give the same
// bytes; no \u0000; the JSON parses back.
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
// every timer due by AT, in time order; zrender's own animation loop (its
// requestAnimationFrame falls back to setTimeout) is dropped: the frames are
// the script's
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-progressive.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexes = a => Array.from(a, hex);
function fnv(list) {
  let h = 0x811c9dc5;
  for (const s of list) {
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 0x01000193) >>> 0;
    }
  }
  return h >>> 0;
}
const rectRec = r => (r ? [r.x, r.y, r.width, r.height].map(hex) : null);
function ranges(list) {
  const s = Array.from(new Set(list)).sort((a, b) => a - b);
  const out = [];
  for (const v of s) {
    const last = out[out.length - 1];
    if (last && last[1] === v - 1) last[1] = v;
    else out.push([v, v]);
  }
  return out;
}

// ---------- charts ----------
let COST = 1;
let inFrame = false;
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  chart.getZr().painter.type = 'canvas';
  const sch = chart._scheduler;
  const orig = sch.performSeriesTasks;
  sch.performSeriesTasks = function (m) {
    if (inFrame) NOW += COST;
    return orig.call(this, m);
  };
  return chart;
}
(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
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

let FRAMES = 0;
function frame(chart) {
  settle(NOW);
  NOW += 16;
  inFrame = true;
  try {
    chart.getZr().animation.update();
  }
  finally {
    inFrame = false;
  }
  chart.getZr()._flush(false);
  chart.getZr().storage.getDisplayList(true);
  FRAMES++;
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
const XY = { xAxis: { type: 'value' }, yAxis: { type: 'value' } };
const catX = n => ({ xAxis: { type: 'category', data: cats(n) }, yAxis: { type: 'value' } });
const F = n => Array.from({ length: n }, () => ['frame']);

// ---------- the cases ----------
// steps: ['frame'] | ['append', seriesIndex, data] | ['move', at] | ['leave']
//        | ['cost', c] | ['snap']
// at: [x, y] | {row: [s, k]} (the datum's point -- a bar's middle)
const CASES = [];
function C(id, group, note, option, steps, opts) {
  opts = opts || {};
  CASES.push({ id, group, note, option, steps: steps || [], cost: opts.cost == null ? 1 : opts.cost,
    replay: opts.replay !== false });
}
const scatter = (n, extra, s) => Object.assign({ type: 'scatter', symbolSize: 6, data: pts(n, s || 7, [0, 100], [0, 50]) }, extra);

// --- the switch
for (const n of [49, 50, 51]) {
  C('sc-th-' + n, 'switch', 'scatter, progressive 10, progressiveThreshold 50, ' + n + ' rows',
    base(Object.assign({}, XY, { series: [scatter(n, { progressive: 10, progressiveThreshold: 50 })] })), F(6));
}
for (const n of [2999, 3000]) {
  C('sc-def-' + n, 'switch', 'scatter with the defaults (400 / 3000), ' + n + ' rows',
    base(Object.assign({}, XY, { series: [scatter(n, {}, 11)] })), F(8));
}
C('sc-prog0', 'switch', 'progressive 0 switches it off',
  base(Object.assign({}, XY, { series: [scatter(60, { progressive: 0, progressiveThreshold: 10 })] })), F(2));
C('sc-large-def', 'switch', 'a large scatter takes 5000 / 1e4: 120 rows are large but drawn at once',
  base(Object.assign({}, XY, { series: [scatter(120, { large: true, largeThreshold: 100 })] })), F(2));
for (const n of [19, 20]) {
  C('bar-th-' + n, 'switch', 'bar large: true, largeThreshold 1000, progressive 6 / 20, ' + n + ' rows: progressive forces large',
    base(Object.assign({}, catX(n), { series: [{ type: 'bar', large: true, largeThreshold: 1000, progressive: 6, progressiveThreshold: 20, data: vals(n, 5, 90, 3) }] })), F(5));
}
C('bar-notlarge', 'switch', 'a bar without large never goes progressive',
  base(Object.assign({}, catX(30), { series: [{ type: 'bar', progressive: 6, progressiveThreshold: 5, data: vals(30, 5, 90, 3) }] })), F(2));
for (const n of [19, 20]) {
  C('cd-th-' + n, 'switch', 'candlestick normal, progressive 7 / 20 (mod by default), ' + n + ' rows',
    base(Object.assign({}, catX(n), { series: [{ type: 'candlestick', large: false, progressive: 7, progressiveThreshold: 20, data: ohlc(n, 5) }] })), F(5));
}
(function () {
  const d = [];
  for (let x = 0; x < 6; x++) for (let y = 0; y < 5; y++) d.push([x, y, (x * 7 + y * 3) % 10]);
  C('hm', 'switch', 'a cartesian heatmap, progressive 8 / 30, 30 cells',
    base({ xAxis: { type: 'category', data: cats(6) }, yAxis: { type: 'category', data: cats(5) },
      visualMap: { min: 0, max: 10, calculable: false, show: false },
      series: [{ type: 'heatmap', progressive: 8, progressiveThreshold: 30, data: d }] }), F(5));
})();
C('line-prog', 'switch', 'a line with progressive written: its view has no incremental path',
  base(Object.assign({}, XY, { series: [{ type: 'line', progressive: 5, progressiveThreshold: 5, data: pts(12, 9, [0, 100], [0, 50]).sort((a, b) => a[0] - b[0]) }] })), F(2));

// --- the chunk modes
for (const mode of ['mod', 'sequential']) {
  C('bar-' + mode + '-10', 'chunk', 'a progressive bar, 10 rows by 4, ' + mode,
    base(Object.assign({}, catX(10), { series: [{ type: 'bar', large: true, progressive: 4, progressiveThreshold: 5, progressiveChunkMode: mode, data: vals(10, 5, 90, 13) }] })),
    F(5).concat([['move', { row: [0, 9] }], ['move', { row: [0, 5] }], ['move', { row: [0, 1] }], ['leave']]));
  C('cd-' + mode + '-10', 'chunk', 'normal candles, 10 rows by 4, ' + mode + ' (a mod walk misses a row and visits one twice)',
    base(Object.assign({}, catX(10), { series: [{ type: 'candlestick', progressive: 4, progressiveThreshold: 5, progressiveChunkMode: mode, data: ohlc(10, 17) }] })),
    F(5).concat([['move', { row: [0, 9] }], ['move', { row: [0, 7] }], ['leave']]));
}
C('bar-mod-23', 'chunk', 'a progressive bar with backgrounds, 23 rows by 5, mod; the pointer over every chunk',
  base(Object.assign({}, catX(23), { series: [{ type: 'bar', large: true, showBackground: true, progressive: 5, progressiveThreshold: 5, data: vals(23, 5, 90, 19) }] })),
  F(7).concat([['move', { row: [0, 0] }], ['move', { row: [0, 6] }], ['move', { row: [0, 12] }], ['move', { row: [0, 22] }], ['leave']]));
C('cd-large-mod', 'chunk', 'large candles, 10 rows by 4, mod: three paths a chunk',
  base(Object.assign({}, catX(10), { series: [{ type: 'candlestick', large: true, largeThreshold: 5, progressive: 4, progressiveThreshold: 5, data: ohlc(10, 23) }] })), F(5));
C('sc-mod', 'chunk', 'a scatter asked for mod: its layout walks start..end, only the restart remains',
  base(Object.assign({}, XY, { series: [scatter(10, { progressive: 4, progressiveThreshold: 5, progressiveChunkMode: 'mod' })] })), F(5));

// --- the frame budget
C('sc-cost-04', 'budget', 'a step costs 0.4 ms: three chunks a frame',
  base(Object.assign({}, XY, { series: [scatter(20, { progressive: 2, progressiveThreshold: 10 })] })), F(5), { cost: 0.4 });
C('sc-cost-0', 'budget', 'a step costs nothing: the first frame draws the rest',
  base(Object.assign({}, XY, { series: [scatter(20, { progressive: 2, progressiveThreshold: 10 })] })), F(3), { cost: 0 });
C('sc-cost-mixed', 'budget', 'the cost changes between frames; two series share the frame',
  base(Object.assign({}, XY, { series: [scatter(20, { progressive: 2, progressiveThreshold: 10 }), scatter(9, { progressive: 3, progressiveThreshold: 5 }, 29)] })),
  [['frame'], ['cost', 0.5], ['frame'], ['cost', 0.25], ['frame'], ['frame'], ['frame']]);

// --- appendData
C('ap-sc-seq', 'append', 'progressive scatter by 4: rows appended mid-way and after the end carry on; the extent stays',
  base(Object.assign({}, XY, { series: [scatter(10, { progressive: 4, progressiveThreshold: 8 })] })),
  [['append', 0, [[20, 10], [150, 30], [50, 80]]], ['frame'], ['frame'], ['frame'], ['frame'],
    ['append', 0, pts(5, 41, [0, 100], [0, 50])], ['frame'], ['frame'], ['frame'], ['snap']]);
C('ap-sc-cross', 'append', 'a scatter under the threshold crosses it: progressive from row 0',
  base(Object.assign({}, XY, { series: [scatter(6, { progressive: 4, progressiveThreshold: 10 })] })),
  [['frame'], ['append', 0, pts(6, 43, [0, 100], [0, 50])], ['frame'], ['frame'], ['frame'], ['frame'], ['snap']]);
C('ap-sc-normal', 'append', 'a scatter that stays under the threshold redraws whole; a point past the extent is not drawn',
  base(Object.assign({}, XY, { series: [scatter(5)] })),
  [['snap'], ['append', 0, [[10, 10], [500, 20], [30, 49]]], ['frame'], ['frame'], ['snap']]);
for (const mode of ['sequential', 'mod']) {
  C('ap-bar-' + mode, 'append', 'a progressive bar by 4, ' + mode + ', 7 rows appended after the end',
    base({ xAxis: { type: 'category', data: cats(17) }, yAxis: { type: 'value', max: 100 },
      series: [{ type: 'bar', large: true, progressive: 4, progressiveThreshold: 8, progressiveChunkMode: mode, data: vals(10, 5, 90, 31) }] }),
    F(3).concat([['append', 0, vals(7, 5, 90, 37)]], F(4), [['move', { row: [0, 12] }], ['move', { row: [0, 3] }], ['leave']]));
}
C('ap-bar-normal', 'append', 'a normal bar appended to: one render of every row',
  base({ xAxis: { type: 'category', data: cats(5) }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [10, 30, 20] }] }),
  [['append', 0, [50, 10]], ['frame'], ['frame'], ['snap']]);
C('ap-bar-large', 'append', 'a large bar that is not progressive appended to: the whole batch again',
  base({ xAxis: { type: 'category', data: cats(5) }, yAxis: { type: 'value' }, series: [{ type: 'bar', large: true, largeThreshold: 2, progressive: 0, data: [10, 30, 20] }] }),
  [['append', 0, [50, 10]], ['frame'], ['frame']]);
C('ap-large-cross', 'append', 'a scatter crossing largeThreshold through appendData goes large with every row',
  base(Object.assign({}, XY, { series: [scatter(8, { large: true, largeThreshold: 10, progressive: 0 })] })),
  [['append', 0, pts(4, 47, [0, 100], [0, 50])], ['frame'], ['frame']]);
(function () {
  const a = pts(6000, 53, [0, 1000], [0, 500]);
  const b = pts(9000, 59, [0, 1000], [0, 500]);
  C('ap-sc-merge', 'append', 'a large progressive scatter by 3000: batches merge until 2e4 numbers, appended chunks merge into the last',
    base(Object.assign({}, XY, { series: [{ type: 'scatter', large: true, largeThreshold: 10, progressive: 3000, progressiveThreshold: 3000, symbolSize: 4, data: a }] })),
    [['frame'], ['frame'], ['append', 0, b], ['frame'], ['frame'], ['frame'], ['frame'],
      ['move', { row: [0, 100] }], ['move', { row: [0, 7000] }], ['move', { row: [0, 13500] }], ['leave']]);
})();
C('ap-cd', 'append', 'normal candles, not progressive, appended to: upstream draws none of the new rows',
  base(Object.assign({}, catX(8), { series: [{ type: 'candlestick', data: ohlc(5, 61) }] })),
  [['append', 0, ohlc(3, 67)], ['frame'], ['frame']], { replay: false });
C('ap-line', 'append', 'a line appended to: upstream lays out the appended rows alone and draws only them',
  base(Object.assign({}, XY, { series: [{ type: 'line', data: [[0, 1], [10, 30], [20, 20]] }] })),
  [['append', 0, [[30, 40], [40, 10]]], ['frame'], ['frame']], { replay: false });
C('ap-two', 'append', 'two appends before a frame, on a progressive scatter by 3',
  base(Object.assign({}, XY, { series: [scatter(9, { progressive: 3, progressiveThreshold: 6 })] })),
  F(3).concat([['append', 0, pts(2, 71, [0, 100], [0, 50])], ['append', 0, pts(2, 73, [0, 100], [0, 50])]], F(3)));

// --- the pointer while the chunks come in
C('hv-sc', 'hover', 'a progressive scatter by 5; the pointer on a row before and after its chunk',
  base(Object.assign({}, XY, { series: [scatter(20, { progressive: 5, progressiveThreshold: 10, symbolSize: 10 }, 79)] })),
  [['move', { row: [0, 12] }], ['frame'], ['move', { row: [0, 12] }], ['frame'], ['move', { row: [0, 12] }],
    ['move', { row: [0, 3] }], ['frame'], ['move', { row: [0, 17] }], ['leave']]);
C('hv-bar', 'hover', 'a progressive bar by 4, mod, the pointer on rows of the second chunk while it comes in',
  base(Object.assign({}, catX(12), { series: [{ type: 'bar', large: true, progressive: 4, progressiveThreshold: 5, data: vals(12, 5, 90, 83) }] })),
  [['frame'], ['move', { row: [0, 1] }], ['frame'], ['move', { row: [0, 1] }], ['move', { row: [0, 4] }], ['leave'], ['frame']]);

// =====================================================================
// recording
// =====================================================================
function seriesModel(chart, s) { return chart.getModel().getSeriesByIndex(s); }
function largeKind(el) {
  if (el.type === 'largeBar') return el.silent ? 'barBg' : 'bar';
  if (el.type === 'largeCandlestickBox') return 'candle';
  if (typeof el.findDataIndex === 'function' && el.symbolProxy) return 'symbol';
  return null;
}
function largeEls(chart, sm) {
  const out = [];
  chart.getViewOfSeriesModel(sm).group.traverse(el => { if (!el.isGroup && largeKind(el)) out.push(el); });
  return out;
}
// the datum elements: the outermost element carrying a dataIndex, as
// {el, d, data}; a progressive candle box has no ECData at all
// (_incrementalRenderNormal never calls setItemGraphicEl), so its row is
// read back off its x through the base axis and `data` is false
function owners(chart, sm) {
  const out = [];
  const seen = new Set();
  const g = chart.getViewOfSeriesModel(sm).group;
  g.traverse(el => {
    if (el.isGroup || largeKind(el) || el.type === 'text' || el.__hostTarget) return;
    let owner = null;
    for (let e = el; e && e !== g; e = e.parent) {
      const d = ecData(e);
      if (d && d.dataIndex != null) owner = e;
    }
    if (owner) {
      if (!seen.has(owner)) { seen.add(owner); out.push({ el: owner, d: ecData(owner).dataIndex, data: true }); }
      return;
    }
    if (el.type === 'normalCandlestickBox') {
      const ax = sm.coordinateSystem.getBaseAxis();
      const p = el.shape.points;
      const x = ax.isHorizontal() ? (p[0][0] + p[2][0]) / 2 : (p[0][1] + p[2][1]) / 2;
      const d = Math.round(ax.coordToData(ax.toLocalCoord(x)));
      out.push({ el, d, data: false });
    }
  });
  return out;
}
const R = { R1: 0, R2: 0, R3: 0, R4: 0 };
function bboxOf(el) {
  const p = el.shape.points;
  const k = largeKind(el);
  if (k === 'bar' || k === 'barBg') {
    // PathProxy.getBoundingRect over ctx.rect per row, Math.min / max
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    const bd = el.baseDimIdx, vd = 1 - bd;
    for (let i = 0; i < p.length / 3; i++) {
      const sp = [], sz = [];
      sz[bd] = el.barWidth; sz[vd] = p[i * 3 + 2];
      sp[bd] = p[i * 3 + bd]; sp[vd] = p[i * 3 + vd];
      const xs = [sp[0], sp[0] + sz[0]], ys = [sp[1], sp[1] + sz[1]];
      for (const x of xs) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); }
      for (const y of ys) { y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
    }
    if (!(p.length)) return [0, 0, 0, 0];
    return [x0, y0, x1 - x0, y1 - y0];
  }
  return null;
}
function elRec(el) {
  const kind = largeKind(el);
  const p = el.shape.points;
  const r = { kind, z2: el.z2, silent: !!el.silent, si: el.startIndex == null ? null : el.startIndex, n: p.length };
  const hs = hexes(p);
  if (p.length > 600) r.fnv = fnv(hs);
  else r.pts = hs;
  r.bbox = rectRec(el.getBoundingRect());
  if (kind === 'bar' || kind === 'barBg') {
    r.idx = Array.from(el.largeDataIndices);
    r.bw = hex(el.barWidth);
    r.bd = el.baseDimIdx;
    const want = bboxOf(el);
    const got = el.getBoundingRect();
    const same = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;
    must(same(want[0], got.x) && same(want[1], got.y) && same(want[2], got.width) && same(want[3], got.height), 'R2 ' + JSON.stringify(want));
    R.R2++;
  }
  else if (kind === 'symbol') {
    r.size = el.shape.size.map(hex);
  }
  else {
    r.sign = el.__sign;
  }
  return r;
}
function seriesRecs(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    const data = sm.getData();
    const pc = sm.pipelineContext || {};
    const pl = chart._scheduler.getPipeline(sm.uid);
    const os = owners(chart, sm);
    out.push({
      seriesIndex: sm.seriesIndex, type: sm.subType, count: data.count(),
      prog: !!pc.progressiveRender, large: !!pc.large,
      mod: pc.modDataCount == null ? null : pc.modDataCount,
      step: pl && pl.progressiveEnabled ? pl.step : null,
      items: os.length,
      rows: ranges(os.map(o => o.d)),
      nodata: os.filter(o => !o.data).length,
      els: largeEls(chart, sm).map(elRec),
    });
  });
  return out;
}
function geomRec(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    out.push(owners(chart, sm).map(w => {
      const o = w.el;
      const d = w.d;
      if (o.shape && o.shape.width != null) return { d, rect: [o.shape.x, o.shape.y, o.shape.width, o.shape.height].map(hex) };
      return { d, x: hex(o.x), y: hex(o.y) };
    }));
  });
  return out;
}
function hoverTarget(chart, x, y) {
  return chart.getZr().handler.findHover(x, y).target;
}
function hoverRec(chart, x, y) {
  const t = hoverTarget(chart, x, y);
  if (!t) return null;
  const k = largeKind(t);
  if (k) {
    const d = ecData(t);
    return { kind: k, seriesIndex: d && d.seriesIndex != null ? d.seriesIndex : null, sign: k === 'candle' ? t.__sign : null,
      dataIndex: d && d.dataIndex != null ? d.dataIndex : null };
  }
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return { kind: 'item', seriesIndex: d.seriesIndex, dataIndex: d.dataIndex };
  }
  return { kind: 'other' };
}
function rowPoint(chart, s, k) {
  const sm = seriesModel(chart, s);
  const raw0 = sm.getRawData();
  const cs = sm.coordinateSystem;
  const item = raw0.getRawDataItem(k);
  const v = Array.isArray(item) ? item : (item && item.value != null ? item.value : item);
  if (sm.subType === 'bar') {
    const p = cs.dataToPoint([k, v / 2]);
    return [Math.round(p[0]), Math.round(p[1])];
  }
  if (sm.subType === 'candlestick') {
    // the raw item of a candle carries its category first: [k, o, c, l, h]
    const q = v.slice(-4);
    const p = cs.dataToPoint([k, (q[0] + q[1]) / 2]);
    return [Math.round(p[0]), Math.round(p[1])];
  }
  const p = cs.dataToPoint([v[0], v[1]]);
  return [Math.round(p[0]), Math.round(p[1])];
}
// R3: a hovered large bar's dataIndex is largeDataIndices at the first
// rect holding the pointer
function barScan(el, x, y) {
  const p = el.shape.points;
  const bd = el.baseDimIdx, vd = 1 - bd;
  for (let i = 0; i < p.length / 3; i++) {
    const sp = [], sz = [];
    sz[bd] = el.barWidth; sz[vd] = p[i * 3 + 2];
    sp[bd] = p[i * 3 + bd]; sp[vd] = p[i * 3 + vd];
    if (sz[vd] < 0) { sp[vd] += sz[vd]; sz[vd] = -sz[vd]; }
    if (x >= sp[0] && x <= sp[0] + sz[0] && y >= sp[1] && y <= sp[1] + sz[1]) return el.largeDataIndices[i];
  }
  return -1;
}

// task.ts's modNext, for R1
function modRows(start, end, modBy, modDataCount) {
  const out = [];
  const winCount = Math.ceil(modDataCount / modBy);
  for (let current = start; current < end; current++) {
    const di = (current % winCount) * modBy + Math.ceil(current / winCount);
    out.push(di < modDataCount ? di : current);
  }
  return out;
}

let LOG = null;
function recordCase(c) {
  const chart = newChart();
  COST = c.cost;
  try {
    const where = c.id;
    LOG = [];
    for (const t of ['mouseover', 'mousemove', 'mouseout']) {
      chart.on(t, e => {
        if (!LOG) return;
        const sm = seriesModel(chart, e.seriesIndex);
        const inner = sm ? sm.getData().indexOfRawIndex(e.dataIndex) : null;
        LOG.push({ type: t, seriesIndex: e.seriesIndex, dataIndex: e.dataIndex, dataIndexInside: inner });
      });
    }
    for (const t of ['rendered', 'finished']) {
      chart.on(t, () => { if (LOG) LOG.push({ type: t }); });
    }
    let lastWhich = null;
    let lastInner = null;
    const opt = JSON.parse(JSON.stringify(c.option));
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    chart.getZr().storage.getDisplayList(true);
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
      const ct = view._tooltipContent;
      if (ct && ct.el) ct.el.silent = true;
      return r;
    };
    const content = view._tooltipContent;
    const visible = () => !!(content && content.el && !content.el.ignore && !content.el.invisible);
    const snaps = [];
    const snap = (at, t, extra) => {
      const s = Object.assign({ at, t, x: null, y: null }, extra || {});
      s.events = LOG;
      LOG = [];
      s.unfinished = !!chart._scheduler.unfinished;
      s.series = seriesRecs(chart);
      const vis = visible();
      s.tooltip = { shown: vis, which: vis ? lastWhich : null, inner: vis ? lastInner : null };
      snaps.push(s);
      return s;
    };
    snap(-1, 'init');
    c.steps.forEach((st, i) => {
      if (st[0] === 'frame') {
        frame(chart);
        snap(i, 'frame');
      }
      else if (st[0] === 'cost') {
        COST = st[1];
        snap(i, 'cost', { cost: st[1] });
      }
      else if (st[0] === 'append') {
        chart.appendData({ seriesIndex: st[1], data: JSON.parse(JSON.stringify(st[2])) });
        snap(i, 'append', { seriesIndex: st[1], data: st[2] });
      }
      else if (st[0] === 'snap') {
        const s = snap(i, 'snap');
        s.geom = geomRec(chart);
      }
      else if (st[0] === 'move' || st[0] === 'leave') {
        settle(NOW + 1000);
        NOW += 1000;
        let x = null, y = null;
        if (st[0] === 'move') {
          const at = Array.isArray(st[1]) ? st[1] : rowPoint(chart, st[1].row[0], st[1].row[1]);
          x = at[0]; y = at[1];
          chart.getZr().handler.mousemove(raw(x, y));
        }
        else chart.getZr().handler.mouseout(raw(-1, -1));
        const sch = chart._scheduler;
        const held = sch.unfinished;
        sch.unfinished = false;
        try {
          chart._onframe();
        }
        finally {
          sch.unfinished = held;
        }
        settle(NOW + 500);
        chart.getZr().storage.getDisplayList(true);
        const s = snap(i, st[0], { x, y });
        s.hover = x == null ? null : hoverRec(chart, x, y);
        if (s.hover && s.hover.kind === 'bar') {
          const t = hoverTarget(chart, x, y);
          const want = barScan(t, x, y);
          must(s.hover.dataIndex === (want >= 0 ? want : null), where + ' step ' + i + ': R3');
          R.R3++;
        }
      }
      else must(false, 'step ' + st[0]);
    });
    return { id: c.id, group: c.group, note: c.note, replay: c.replay, option: opt, cost: c.cost, snaps };
  }
  finally {
    LOG = null;
    chart.dispose();
  }
}

// R1: every chunk a 'mod' bar or candlestick added is modNext's walk. A
// bar walks chunk 0 twice (its dataSample task sits in the blocked data
// stage and restarts the pipeline at the first frame); a candle does not.
function checkMod(cases) {
  for (const c of cases) {
    const s0 = c.snaps[0].series;
    s0.forEach((sr, si) => {
      if (sr.mod == null || !sr.prog) return;
      if (sr.type !== 'bar' && sr.type !== 'candlestick') return;
      // replay the walk from the setOption: chunk 0 at init, then one chunk
      // a frame at cost 1 (a restart at the first frame re-walks chunk 0)
      const step = sr.step, n = sr.mod;
      const modBy = Math.max(1, Math.ceil(n / step));
      const chunks = [];
      for (let st = 0; st < n; st += step) chunks.push(modRows(st, Math.min(st + step, n), modBy, n));
      if (sr.type === 'candlestick' && !sr.large) {
        // the items after the k-th chunk: the union of the walks
        const seen = new Set();
        let k = 0;
        const frames = c.snaps.filter(s => s.t === 'init' || s.t === 'frame');
        frames.forEach((s, fi) => {
          if (k < chunks.length) { chunks[k].forEach(r => seen.add(r)); k++; }
          const want = ranges(Array.from(seen));
          must(JSON.stringify(want) === JSON.stringify(s.series[si].rows), c.id + ': R1 candle frame ' + fi + ' ' + JSON.stringify(want) + ' vs ' + JSON.stringify(s.series[si].rows));
          R.R1++;
        });
      }
      else if (sr.type === 'bar') {
        const frames = c.snaps.filter(s => (s.t === 'init' || s.t === 'frame') && s.series[si].mod === n);
        frames.forEach((s, fi) => {
          const els = s.series[si].els.filter(e => e.kind === 'bar');
          els.forEach((e, k) => {
            const rows = chunks[k];
            const idx = new Array(rows.length).fill(0);
            rows.forEach(r => { if (r < rows.length) idx[r] = r; });
            must(JSON.stringify(idx) === JSON.stringify(e.idx), c.id + ': R1 bar idx chunk ' + k);
            R.R1++;
          });
        });
      }
    });
  }
}
// R4: frames to finish from the cost
function checkBudget(cases) {
  for (const id of ['sc-cost-04', 'sc-cost-0', 'sc-th-50']) {
    const c = cases.find(x => x.id === id);
    const chunks = Math.ceil(c.snaps[0].series[0].count / c.snaps[0].series[0].step);
    const per = c.cost === 0 ? Infinity : (() => { let k = 0, r = 1; do { r -= c.cost; k++; } while (r > 0); return k; })();
    const want = chunks <= 1 ? 0 : per === Infinity ? 1 : Math.ceil((chunks - 1) / per);
    const fin = c.snaps.findIndex(s => s.events.some(e => e.type === 'finished'));
    must(fin === want, id + ': R4 finished at snap ' + fin + ', predicted ' + want);
    R.R4++;
  }
}

// =====================================================================
// guards
// =====================================================================
function guards(cases) {
  const g = [];
  const get = id => cases.find(c => c.id === id);
  const sn = (id, k) => get(id).snaps[k == null ? 0 : k];
  const s0 = (id, k) => sn(id, k).series[0];
  const ev = (id, k) => sn(id, k).events.map(e => e.type).join(',');
  const G = (name, cond) => { must(cond, 'guard: ' + name); g.push(name); };
  G('threshold - 1 is drawn at once', !s0('sc-th-49').prog && s0('sc-th-49').items === 49 && ev('sc-th-49') === 'rendered,finished');
  G('the threshold is progressive', s0('sc-th-50').prog && s0('sc-th-50').items === 10 && ev('sc-th-50') === 'rendered');
  G('the first chunk is drawn by setOption, one more a frame', s0('sc-th-51', 1).items === 20 && s0('sc-th-51', 5).items === 51 && s0('sc-th-51', 6).items === 51);
  G('finished once, with the last chunk', ev('sc-th-51', 5) === 'rendered,finished' && ev('sc-th-51', 6) === '');
  G('rendered every frame while unfinished', [1, 2, 3, 4].every(k => ev('sc-th-51', k) === 'rendered'));
  G('the scatter default 400 / 3000', !s0('sc-def-2999').prog && s0('sc-def-3000').prog && s0('sc-def-3000').step === 400 && s0('sc-def-3000').items === 400);
  G('progressive 0 is off', !s0('sc-prog0').prog && s0('sc-prog0').step === null);
  G('a large scatter steps by 5000', s0('sc-large-def').step === 5000 && !s0('sc-large-def').prog && s0('sc-large-def').large);
  G('a progressive bar is large under its largeThreshold', !s0('bar-th-19').large && s0('bar-th-20').prog && s0('bar-th-20').large);
  G('a bar without large is not progressive', s0('bar-notlarge').step === null && !s0('bar-notlarge').prog);
  G('a candlestick is mod by default', s0('cd-th-20').prog && s0('cd-th-20').mod === 20 && s0('cd-th-19').mod === 19);
  G('a heatmap goes by 8', s0('hm').prog && s0('hm').items === 8 && s0('hm', 3).items === 30);
  G('a line never goes progressive', !s0('line-prog').prog && s0('line-prog').step === 5);
  G('mod: the first frame draws chunk 0 again', JSON.stringify(s0('bar-mod-10', 1).els.map(e => e.idx)) === JSON.stringify(s0('bar-mod-10', 0).els.map(e => e.idx))
    && s0('bar-mod-10', 1).els.length === 1);
  G('sequential: the first frame draws chunk 1', s0('bar-sequential-10', 1).els.length === 2);
  G('a later chunk\'s indices are mostly 0', s0('bar-sequential-10', 2).els[1].idx.every(v => v === 0));
  G('the mod walk misses a candle', JSON.stringify(s0('cd-mod-10', 5).rows) !== JSON.stringify([[0, 9]]) && s0('cd-mod-10', 5).items === 10);
  G('the sequential walk draws every candle', JSON.stringify(s0('cd-sequential-10', 5).rows) === JSON.stringify([[0, 9]]));
  G('the mod walk leaves row 9 out', s0('cd-mod-10', 5).rows.every(r => r[1] < 9) && get('cd-mod-10').snaps.find(s => s.t === 'move').hover === null);
  G('a progressive candle has no data: hovered, no item, no event', (() => { const s = get('cd-sequential-10').snaps.find(x => x.t === 'move');
    return s.hover && s.hover.kind === 'other' && s.events.length === 0 && !s.tooltip.shown; })());
  G('a candle drawn at once has its data', s0('cd-th-19').nodata === 0 && s0('cd-th-20').nodata === 7);
  G('backgrounds come a chunk at a time', s0('bar-mod-23', 2).els.filter(e => e.kind === 'barBg').length === 2);
  G('a hover over a later chunk names the index array\'s value', get('bar-mod-23').snaps.some(s => s.hover && s.hover.kind === 'bar' && s.hover.dataIndex === 0 && s.x > 200));
  G('three candle paths a chunk', s0('cd-large-mod', 0).els.length === 3 && s0('cd-large-mod', 2).els.length === 9);
  G('a mod scatter does not restart: no blocked task of its own', s0('sc-mod', 1).items === 8);
  G('a mod candle does not restart', s0('cd-large-mod', 1).els.length === 6);
  G('a mod bar restarts twice after appendData', s0('ap-bar-mod', 5).els.length === 1 && s0('ap-bar-mod', 6).els.length === 1 && s0('ap-bar-mod', 7).els.length === 2);
  G('three chunks a frame at 0.4', s0('sc-cost-04', 1).items === 8 && s0('sc-cost-04', 2).items === 14);
  G('one frame at cost 0', s0('sc-cost-0', 1).items === 20 && ev('sc-cost-0', 1) === 'rendered,finished');
  G('appendData draws nothing until the frame (the count is the raw one already)', s0('ap-sc-seq', 1).items === 4 && s0('ap-sc-seq', 1).count === 13);
  G('appended rows past the extent are not drawn', (() => { const s = get('ap-sc-seq').snaps; const last = s[s.length - 1].series[0]; return last.count === 18 && last.items < 18; })());
  G('the axis keeps its extent', JSON.stringify(sn('ap-sc-normal', 1).geom[0].slice(0, 5)) === JSON.stringify(sn('ap-sc-normal', 5).geom[0].slice(0, 5)));
  G('crossing the threshold starts at row 0', s0('ap-sc-cross', 3).prog && s0('ap-sc-cross', 3).items === 4);
  G('sequential carries on after appendData', s0('ap-bar-sequential', 5).els.filter(e => e.kind === 'bar').length === 4);
  G('mod starts again after appendData', s0('ap-bar-mod', 5).els.filter(e => e.kind === 'bar').length === 1);
  G('a normal bar redraws every row', s0('ap-bar-normal', 2).items === 5);
  G('a large bar redraws the whole batch', s0('ap-bar-large', 2).els[0].n === 15);
  G('crossing largeThreshold goes large with every row', s0('ap-large-cross', 2).els[0].n === 24 && s0('ap-large-cross', 2).large);
  G('the large scatter merges to 12000 points, then a new batch', (() => { const e = s0('ap-sc-merge', 7).els; return e.length === 2 && e[0].n === 24000 && e[1].si === 12000; })());
  G('normal candles appended to draw no new row (the view diffs the data with itself)', s0('ap-cd', 2).items === 5 && s0('ap-cd', 2).count === 8);
  G('the line draws only the appended rows', (() => { const s = get('ap-line').snaps; return s[s.length - 1].series[0].items === 0; })());
  G('two appends, one restart-free carry on', s0('ap-two', 6).count === 13);
  G('the pointer over a row not drawn yet finds nothing of it', get('hv-sc').snaps[1].hover === null || get('hv-sc').snaps[1].hover.kind !== 'item');
  G('the pointer over a drawn row hovers it', get('hv-sc').snaps.some(s => s.hover && s.hover.kind === 'item' && s.hover.dataIndex === 12));
  G('a tooltip during progressive', get('hv-sc').snaps.some(s => s.tooltip.shown));
  return g;
}

function generate() {
  FRAMES = 0;
  const cases = CASES.map(recordCase);
  checkMod(cases);
  checkBudget(cases);
  const gs = guards(cases);
  for (const k of Object.keys(R)) must(R[k] > 0, 'recipe ' + k + ' never ran');
  const out = {
    source: 'ECharts ' + echarts.version + ' dist (' + path.basename(DIST) + ') under node, svg painter typed canvas, ssr init then _ssr = false, env.node = false',
    W, H,
    notes: [
      'Every option has animation false.',
      'A frame: due timers, NOW += 16, zr.animation.update(), zr._flush(false); every iteration of _onframe costs the case\'s cost in ms.',
      'A pointer step: NOW += 1000, the handler, _onframe with scheduler.unfinished held false.',
    ],
    cases, guards: gs, recipes: Object.assign({}, R),
  };
  for (const k of Object.keys(R)) R[k] = 0;
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
