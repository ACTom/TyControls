// Upstream's own answers for THE HOVER LAYER [R2-I9]: which elements a
// state switch puts on zrender's hover layer instead of repainting their own
// layer, what the hover layer draws, and what the element's own layer keeps.
//
// zrender 6.1 (Element.useState / useStates, shouldUseHoverLayer,
// Displayable._applyStateObj, Painter._paintHoverList): when the LAST state
// object of a switch carries `hoverLayer` (and the element is no Text and
// has no textContent), the element enters the hover layer BEFORE the states
// apply and is ONLY_STYLE_CHANGE there: its own style, z2, transform and
// shape stay as they were -- the switch writes the merged target style to
// __hoverStyle instead -- and its layer is not repainted (dirty elements in
// the hover layer are skipped). The hover layer (zlevel 1e5, over every
// other layer) brushes the display list's __inHover elements in list order
// with __hoverStyle. A switch whose last state has no flag leaves the hover
// layer AFTER applying -- still only to __hoverStyle -- so the own layer
// keeps what it had when the element entered.
//
// ECharts 6.1 sets the flag on `emphasis` states: HOVER_LAYER_FOR_INCREMENTAL
// on every element an incremental render made (SymbolDraw, LineDraw,
// HeatmapView, CustomView -- not ParallelView, not the large draws), and
// HOVER_LAYER_FROM_THRESHOLD on every rendered element of every series
// (but a treemap: preventUsingHoverLayer) after each renderSeries while
// the storage holds more non-group elements than the root
// `hoverLayerThreshold` (3000) -- on a canvas painter, not under node.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node with progressive.js's recipe: svg ssr init, then
// _ssr = false, the painter typed 'canvas', echarts.env.node = false, a
// fake clock; a frame is due timers, NOW += 16, zr.animation.update(),
// zr._flush(false). A pointer step: NOW += 1000, the handler's mousemove /
// mouseout, _onframe with scheduler.unfinished held false, due timers. An
// action step: dispatchAction, _onframe the same way.
//
//   node tools/advchart-oracle/hover-layer.js
//
// writes tests/fixtures/advchart-hover-layer.json (ORACLE_OUT overrides).
//
// Top level: source, W, H, notes[], cases[], guards[], recipes{}
//   case: id, note, option, steps[] (as fed), snaps[]
//   snap: at (-1 after setOption), t ('init' | 'frame' | 'move' | 'leave' |
//     'act'), x, y (a move's point) | payload (an act's),
//     thl (chart._usingTHL), count (the non-group elements in the storage),
//     hover (the display list's __inHover elements in list order:
//       {s, d, p} -- series, data index, the path's place in its datum
//       group (0 for the datum element itself)),
//     els (every series path with a state list or in the hover layer, in
//       series then data order: {s, d, p, cs (currentStates), ih (__inHover),
//       st (its own style: fill, stroke, lineWidth (hex), opacity (hex)),
//       hs (__hoverStyle the same way, null outside the hover layer),
//       z2, sx, sy (scaleX, scaleY hex), dz2 and ds (z2 less, scaleX over,
//       the values the element had at the setOption -- the port's rest)})
//   A colour is the string the style holds ('none' / null as written).
//
// Self-checks: H1 an element is in `hover` exactly when it is __inHover;
// H2 every element in the hover layer has an emphasis state with a
// hoverLayer flag and no textContent; H3 an element in the hover layer has
// the z2 and scale it had before the step. Guards below. Two
// generations in one process give the same bytes; no \u0000.
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock (installed before the build loads) ----------
let NOW = 1700000000000;
class FakeDate extends Date {
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-hover-layer.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const numOrNull = v => (v == null ? null : hex(v));
const colour = v => (v == null ? null : typeof v === 'string' ? v : 'object');

// ---------- charts ----------
let inFrame = false;
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  chart.getZr().painter.type = 'canvas';
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
}
function stateFrame(chart) {
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
}

// ---------- the data ----------
let lcg = 1;
function seed(s) { lcg = s >>> 0; }
function rnd(lo, hi) {
  lcg = (Math.imul(lcg, 1103515245) + 12345) >>> 0;
  return lo + ((lcg >>> 8) % (hi - lo + 1));
}
function pts(n, s) {
  seed(s);
  return Array.from({ length: n }, () => [rnd(0, 1000), rnd(0, 500)]);
}
function vals(n, lo, hi, s) {
  seed(s);
  return Array.from({ length: n }, () => rnd(lo, hi));
}
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);

const GRID = { left: 60, right: 40, top: 40, bottom: 40 };
const COLORS = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
function base(extra) {
  return Object.assign({ animation: false, color: COLORS, grid: GRID }, extra);
}
const XY = { xAxis: { type: 'value', min: 0, max: 1000 }, yAxis: { type: 'value', min: 0, max: 500 } };

// a few points placed apart so a pointer finds exactly them: the first
// rows of a scatter are these, the rest fill the plot away from them
const PROBES = [[100, 100], [300, 250], [700, 400], [900, 50]];
function scatterData(n, s) {
  const out = PROBES.map(p => p.slice());
  seed(s);
  while (out.length < n) {
    const p = [rnd(0, 1000), rnd(0, 500)];
    if (PROBES.some(q => Math.abs(q[0] - p[0]) < 40 && Math.abs(q[1] - p[1]) < 40)) continue;
    out.push(p);
  }
  return out;
}
const scatter = (n, extra) => Object.assign({ type: 'scatter', symbolSize: 8, data: scatterData(n, 5) }, extra || {});
// the pixel of a probe point: grid 60..560 x 40..360, value axes 0..1000 x 0..500
const probeAt = k => [Math.round(60 + PROBES[k][0] / 1000 * 500), Math.round(360 - PROBES[k][1] / 500 * 320)];

const CASES = [];
function C(id, note, option, steps) {
  CASES.push({ id, note, option, steps });
}
const hl = (s, d) => ['act', { type: 'highlight', seriesIndex: s, dataIndex: d }];
const dp = (s, d) => ['act', { type: 'downplay', seriesIndex: s, dataIndex: d }];
const sel = (s, d) => ['act', { type: 'select', seriesIndex: s, dataIndex: d }];
const unsel = (s, d) => ['act', { type: 'unselect', seriesIndex: s, dataIndex: d }];
const mv = k => ['move', probeAt(k)];
const F = n => Array.from({ length: n }, () => ['frame']);

// --- the threshold
C('sc-over', 'a scatter of 3500 symbols drawn at once (progressive 0): past the threshold, a hovered symbol is drawn again over all in its emphasis style, its own copy unchanged (no scale, no z2)',
  base(Object.assign({}, XY, { series: [scatter(3500, { progressive: 0 })] })),
  [mv(0), mv(1), ['leave'], mv(2), ['leave']]);
C('sc-over-update', '[r2v] past the threshold, a symbol highlighted, then a dataZoom (a full update) while it is held: after the update it is on the hover layer still, its own copy at rest',
  base(Object.assign({ dataZoom: [{ type: 'inside', xAxisIndex: 0 }] }, XY, { series: [scatter(3500, { progressive: 0 })] })),
  [hl(0, 1), ['act', { type: 'dataZoom', start: 0, end: 95 }], ['act', { type: 'dataZoom', start: 0, end: 100 }], dp(0, 1)]);
C('sc-scaled-enter', '[r2v] a scatter of 3500 zoomed to half (under the threshold): a symbol highlighted takes its emphasis scale in its own layer; the zoom back to the whole (past the threshold) keeps it so; a select while held puts it on the hover layer with its own layer as it was -- scaled',
  base(Object.assign({ dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 0, end: 50 }] }, XY, { series: [scatter(3500, { progressive: 0, selectedMode: 'multiple' })] })),
  [hl(0, 1), ['act', { type: 'dataZoom', start: 0, end: 100 }], sel(0, 1), dp(0, 1), unsel(0, 1)]);
C('sc-under', 'the same scatter with 1500 symbols: under the threshold, the symbol itself takes the state (scale, z2, lifted fill)',
  base(Object.assign({}, XY, { series: [scatter(1500, { progressive: 0 })] })),
  [mv(0), ['leave']]);
C('sc-root-threshold', 'hoverLayerThreshold 1000 at the root: 1500 symbols are past it',
  base(Object.assign({ hoverLayerThreshold: 1000 }, XY, { series: [scatter(1500, { progressive: 0 })] })),
  [mv(1), ['leave']]);
C('sc-emph-style', 'past the threshold, a declared emphasis style and scale: the style is the hover copy\'s, the scale nobody\'s',
  base(Object.assign({}, XY, { series: [scatter(3500, { progressive: 0, emphasis: { scale: 2, itemStyle: { color: '#ff0000', borderColor: '#000000', borderWidth: 3, opacity: 0.5 } } })] })),
  [mv(0), ['leave']]);
C('sc-label', 'past the threshold, an emphasis label: the symbol has a textContent and never uses the hover layer',
  base(Object.assign({}, XY, { series: [scatter(3500, { progressive: 0, emphasis: { label: { show: true, formatter: 'x' } } })] })),
  [mv(0), ['leave']]);
C('sc-two-series', 'two scatters of 2000: the count is the chart\'s, both series use the hover layer; highlight both',
  base(Object.assign({}, XY, { series: [scatter(2000, { progressive: 0 }), Object.assign(scatter(2000, { progressive: 0 }), { data: scatterData(2000, 9).map(p => [p[0], 500 - p[1]]) })] })),
  [hl(0, 1), hl(1, 3), dp(0, 1), dp(1, 3)]);
C('sc-blur', 'past the threshold, focus series: the blur is no hover state -- the other series repaint in their layer, the hovered symbol is on the hover layer',
  base(Object.assign({}, XY, { series: [scatter(2000, { progressive: 0, emphasis: { focus: 'series' } }), scatter(2000, { progressive: 0, emphasis: { focus: 'series' }, data: scatterData(2000, 13).map(p => [p[0], 500 - p[1]]) })] })),
  [mv(0), ['leave']]);

// --- the incremental flag
C('sc-incremental', 'a progressive scatter of 2000 by 500 (threshold 1000): every symbol an incremental render made carries the flag, under the count threshold',
  base(Object.assign({}, XY, { series: [scatter(2000, { progressive: 500, progressiveThreshold: 1000 })] })),
  F(4).concat([mv(0), mv(3), ['leave']]));
(function () {
  const d = [];
  for (let x = 0; x < 40; x++) for (let y = 0; y < 30; y++) d.push([x, y, (x * 7 + y * 3) % 10]);
  const hm = (extra) => base({ xAxis: { type: 'category', data: cats(40) }, yAxis: { type: 'category', data: cats(30) },
    visualMap: { min: 0, max: 10, show: false, inRange: { color: ['#313695', '#a50026'] } },
    series: [Object.assign({ type: 'heatmap', data: d }, extra)] });
  C('hm-incremental', 'a progressive heatmap of 1200 cells by 300: incremental rects use the hover layer',
    hm({ progressive: 300, progressiveThreshold: 1000 }), F(4).concat([hl(0, 37), hl(0, 38), dp(0, 37), dp(0, 38)]));
  C('hm-whole', 'the same heatmap drawn at once: under the threshold, no hover layer',
    hm({ progressive: 0 }), [hl(0, 37), dp(0, 37)]);
})();

// --- bars, select and the stuck own layer
C('bar-over', 'a bar of 3200 categories (not large): past the threshold; select while held, then downplay -- the own layer keeps the style it had when the bar entered the hover layer',
  base({ xAxis: { type: 'category', data: cats(3200) }, yAxis: { type: 'value' },
    series: [{ type: 'bar', selectedMode: 'multiple', select: { itemStyle: { color: '#00aa00' } }, data: vals(3200, 5, 90, 3) }] }),
  [sel(0, 10), hl(0, 10), dp(0, 10), hl(0, 20), sel(0, 20), dp(0, 20), unsel(0, 10), hl(0, 10), dp(0, 10)]);
C('bar-over-unsel', '[r2v] the same bars, the select style with a border: a bar selected, then hovered (its own layer keeps the select style), then unselected while held -- the hover style is the normal style under emphasis, no border, whatever the own layer still shows',
  base({ xAxis: { type: 'category', data: cats(3200) }, yAxis: { type: 'value' },
    series: [{ type: 'bar', selectedMode: 'multiple', select: { itemStyle: { color: '#00aa00', borderColor: '#000000', borderWidth: 3 } },
      data: vals(3200, 5, 90, 3) }] }),
  [sel(0, 30), hl(0, 30), unsel(0, 30), dp(0, 30), hl(0, 30), dp(0, 30)]);

// --- parallel
(function () {
  seed(21);
  const rows = Array.from({ length: 3200 }, () => [rnd(0, 100), rnd(0, 100), rnd(0, 100)]);
  const par = extra => base({ parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
    series: [Object.assign({ type: 'parallel', lineStyle: { width: 1, opacity: 0.5 }, data: rows }, extra)] });
  C('par-over', 'a parallel series of 3200 lines drawn at once: no incremental flag (ParallelView sets none), the threshold puts a highlighted line on the hover layer',
    par({ progressive: 0 }), [hl(0, 5), hl(0, 6), dp(0, 5), dp(0, 6)]);
  C('par-prog', 'the same lines by 400: the threshold once the chunks are in',
    par({ progressive: 400 }), F(9).concat([hl(0, 5), dp(0, 5)]));
  C('par-prog-first', '[r2v] the same lines by 400, highlighted before the second chunk: the storage holds the first chunk alone, under the threshold -- the line takes the state in its own layer',
    par({ progressive: 400 }), [hl(0, 5), dp(0, 5)]);
  C('par-emph', 'a declared emphasis lineStyle on the hover layer',
    par({ progressive: 0, emphasis: { lineStyle: { width: 4, color: '#ff00ff', opacity: 1 } } }), [hl(0, 7), dp(0, 7)]);
})();

// --- the root threshold on small charts
C('pie-thl', 'hoverLayerThreshold 1, a pie whose labels show only on emphasis (the default): a textContent all the same, no hover layer',
  base({ hoverLayerThreshold: 1, series: [{ type: 'pie', radius: '50%', label: { show: false }, labelLine: { show: false }, data: [3, 5, 7, 2] }] }),
  [hl(0, 2), dp(0, 2)]);
C('pie-thl-nolabel', 'hoverLayerThreshold 1, a pie with no label in any state: PiePiece gives every sector a textContent, so never the hover layer',
  base({ hoverLayerThreshold: 1, series: [{ type: 'pie', radius: '50%', label: { show: false }, labelLine: { show: false },
    emphasis: { label: { show: false } }, data: [3, 5, 7, 2] }] }),
  [hl(0, 2), dp(0, 2)]);
C('pie-thl-label', 'hoverLayerThreshold 1, a pie with its labels: every sector has a textContent, no hover layer',
  base({ hoverLayerThreshold: 1, series: [{ type: 'pie', radius: '50%', data: [3, 5, 7, 2] }] }),
  [hl(0, 2), dp(0, 2)]);
C('line-thl', 'hoverLayerThreshold 1, a line: its symbol and its polyline on the hover layer (the line\'s emphasis width is the hover copy\'s)',
  base({ hoverLayerThreshold: 1, xAxis: { type: 'category', data: cats(5) }, yAxis: { type: 'value' },
    series: [{ type: 'line', data: [5, 20, 36, 10, 10], emphasis: { lineStyle: { width: 6 } } }] }),
  [hl(0, 2), dp(0, 2)]);
(function () {
  const g = thl => base({ hoverLayerThreshold: thl, xAxis: { type: 'value', min: 0, max: 1000, show: false }, yAxis: { type: 'value', min: 0, max: 500, show: false },
    series: [{ type: 'scatter', symbolSize: 8, data: [[100, 100], [300, 250], [700, 400], [900, 50], [500, 300]] }] });
  C('sc-at-threshold', '[r2v] five symbols and nothing else in the storage (the axes hidden), hoverLayerThreshold 5: the count must pass the threshold (elCount > value) -- five is not past five',
    g(5), [hl(0, 2), dp(0, 2)]);
  C('sc-past-threshold', '[r2v] the same symbols, hoverLayerThreshold 4: five is past it',
    g(4), [hl(0, 2), dp(0, 2)]);
})();
C('treemap-thl', 'hoverLayerThreshold 1, a treemap: preventUsingHoverLayer',
  base({ hoverLayerThreshold: 1, series: [{ type: 'treemap', label: { show: false }, upperLabel: { show: false }, breadcrumb: { show: false },
    data: [{ name: 'a', value: 4 }, { name: 'b', value: 6 }, { name: 'c', value: 2 }] }] }),
  [hl(0, 1), dp(0, 1)]);

// =====================================================================
// recording
// =====================================================================
const R = { H1: 0, H2: 0, H3: 0 };
function styleRec(s) {
  if (!s) return null;
  return { fill: colour(s.fill), stroke: colour(s.stroke), lineWidth: numOrNull(s.lineWidth), opacity: numOrNull(s.opacity) };
}
// every path of a series view with a data index: {el, s, d, p}
function seriesPaths(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    const g = chart.getViewOfSeriesModel(sm).group;
    const perDatum = new Map();
    g.traverse(el => {
      if (el.isGroup || el.type === 'text' || el.type === 'tspan') return;
      if (!el.states || !el.states.emphasis) return;
      let d = null;
      for (let e = el; e && e !== g; e = e.parent) {
        const ed = ecData(e);
        if (ed && ed.dataIndex != null) { d = ed.dataIndex; break; }
      }
      if (d == null) d = -1;
      const p = perDatum.get(d) || 0;
      perDatum.set(d, p + 1);
      out.push({ el, s: sm.seriesIndex, d, p });
    });
  });
  return out;
}
function countEls(chart) {
  let n = 0;
  chart.getZr().storage.traverse(el => { if (!el.isGroup) n++; });
  return n;
}
function recordCase(c) {
  const chart = newChart();
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    chart.getZr().storage.getDisplayList(true);
    const rest = new Map();
    const init = new Map();
    const snaps = [];
    const snap = (at, t, extra) => {
      const s = Object.assign({ at, t }, extra || {});
      s.thl = !!chart._usingTHL;
      s.count = countEls(chart);
      const paths = seriesPaths(chart);
      const key = new Map(paths.map(q => [q.el, q]));
      s.hover = [];
      for (const el of chart.getZr().storage.getDisplayList(true)) {
        if (!el.__inHover) continue;
        const q = key.get(el);
        must(q, c.id + ': an element on the hover layer that is no series path');
        s.hover.push({ s: q.s, d: q.d, p: q.p });
      }
      s.els = [];
      for (const q of paths) {
        const el = q.el;
        const k = q.s + ':' + q.d + ':' + q.p;
        // the values before this step (the setOption's at first)
        const was = rest.get(k) || { z2: el.z2, sx: el.scaleX, sy: el.scaleY };
        rest.set(k, { z2: el.z2, sx: el.scaleX, sy: el.scaleY });
        if (!init.has(k)) init.set(k, { z2: el.z2, sx: el.scaleX });
        const i0 = init.get(k);
        const inHover = !!el.__inHover;
        // H1
        must(inHover === s.hover.some(h => h.s === q.s && h.d === q.d && h.p === q.p), c.id + ': H1');
        R.H1++;
        if (inHover) {
          // H2
          must(el.states.emphasis.hoverLayer && !el.getTextContent() && el.type !== 'text', c.id + ': H2');
          R.H2++;
          // H3
          must(el.z2 === was.z2 && el.scaleX === was.sx && el.scaleY === was.sy, c.id + ': H3 ' + k);
          R.H3++;
        }
        if (!el.currentStates.length && !inHover) continue;
        s.els.push({ s: q.s, d: q.d, p: q.p, cs: el.currentStates.slice(), ih: inHover,
          st: styleRec(el.style), hs: inHover ? styleRec(el.__hoverStyle) : null,
          z2: el.z2, sx: hex(el.scaleX), sy: hex(el.scaleY),
          dz2: el.z2 - i0.z2, ds: hex(el.scaleX / i0.sx) });
      }
      snaps.push(s);
      return s;
    };
    snap(-1, 'init');
    c.steps.forEach((st, i) => {
      if (st[0] === 'frame') {
        frame(chart);
        snap(i, 'frame');
      }
      else if (st[0] === 'move' || st[0] === 'leave') {
        settle(NOW + 1000);
        NOW += 1000;
        if (st[0] === 'move') chart.getZr().handler.mousemove(raw(st[1][0], st[1][1]));
        else chart.getZr().handler.mouseout(raw(-1, -1));
        stateFrame(chart);
        snap(i, st[0], st[0] === 'move' ? { x: st[1][0], y: st[1][1] } : {});
      }
      else if (st[0] === 'act') {
        settle(NOW + 1000);
        NOW += 1000;
        chart.dispatchAction(JSON.parse(JSON.stringify(st[1])));
        stateFrame(chart);
        snap(i, 'act', { payload: st[1] });
      }
      else must(false, 'step ' + st[0]);
    });
    return { id: c.id, note: c.note, option: c.option, steps: c.steps, snaps };
  }
  finally {
    chart.dispose();
  }
}

// =====================================================================
// guards
// =====================================================================
function guards(cases) {
  const g = [];
  const get = id => cases.find(c => c.id === id);
  const sn = (id, k) => get(id).snaps[k];
  const G = (name, cond) => { must(cond, 'guard: ' + name); g.push(name); };
  const one = (id, k) => sn(id, k).els.find(e => e.ih);
  G('past the threshold the hovered symbol is on the hover layer', sn('sc-over', 1).thl && sn('sc-over', 1).hover.length === 1);
  G('its own copy keeps its style', (() => { const e = one('sc-over', 1); return e.st.fill === '#5470c6' && e.hs.fill !== '#5470c6'; })());
  G('and its scale', (() => { const e = one('sc-over', 1); return e.sx === hex(1) || e.sx === sn('sc-over', 1).els[0].sx; })());
  G('the next one replaces it', sn('sc-over', 2).hover.length === 1 && sn('sc-over', 2).hover[0].d === 1);
  G('leaving empties the hover layer', sn('sc-over', 3).hover.length === 0 && sn('sc-over', 3).els.length === 0);
  G('under the threshold no hover layer', !sn('sc-under', 1).thl && sn('sc-under', 1).hover.length === 0 && sn('sc-under', 1).els.length === 1);
  G('under the threshold the symbol itself is lifted', (() => { const e = sn('sc-under', 1).els[0]; return e.st.fill !== '#5470c6'; })());
  G('the root threshold is read', sn('sc-root-threshold', 1).thl && sn('sc-root-threshold', 1).hover.length === 1);
  G('a declared style is the hover style', (() => { const e = one('sc-emph-style', 1); return e.hs.fill === '#ff0000' && e.st.fill === '#5470c6'; })());
  G('a label keeps the symbol off the hover layer', sn('sc-label', 1).thl && sn('sc-label', 1).hover.length === 0 && sn('sc-label', 1).els.length === 1);
  G('two series, two on the hover layer', sn('sc-two-series', 2).hover.length === 2);
  G('a blur is drawn in the own layer', sn('sc-blur', 1).hover.length === 1 && sn('sc-blur', 1).els.filter(e => e.cs[0] === 'blur' && !e.ih).length === 2000);
  G('incremental symbols use it under the count', !sn('sc-incremental', 5).thl && sn('sc-incremental', 5).hover.length === 1);
  G('incremental rects use it', sn('hm-incremental', 5).hover.length === 1 && sn('hm-incremental', 6).hover.length === 2);
  G('a heatmap drawn at once does not', sn('hm-whole', 1).hover.length === 0 && sn('hm-whole', 1).els.length === 1);
  G('a selected bar entering the hover layer keeps its select style below', (() => { const e = one('bar-over', 2); return e.st.fill === '#00aa00'; })());
  G('selected while held: the own layer stays unselected', (() => { const e = sn('bar-over', 6).els.find(x => x.d === 20); return e && !e.ih && e.cs.join() === 'select' && e.st.fill !== '#00aa00'; })());
  G('unselected while held: the hover style has no border, the own layer keeps it', (() => {
    const e = one('bar-over-unsel', 3);
    return e && e.cs.join() === 'emphasis' && e.st.lineWidth === hex(3) && e.hs.lineWidth !== hex(3);
  })());
  G('the parallel threshold', sn('par-over', 1).thl && sn('par-over', 2).hover.length === 2);
  G('before the second chunk they do not', !sn('par-prog-first', 1).thl && sn('par-prog-first', 1).hover.length === 0
    && sn('par-prog-first', 1).els.length === 1);
  G('the parallel lines by chunks reach it', sn('par-prog', 10).thl && sn('par-prog', 10).hover.length === 1);
  G('an emphasis-only label keeps a sector off', sn('pie-thl', 1).hover.length === 0);
  G('a pie sector never: PiePiece sets a textContent whatever the label says', sn('pie-thl-nolabel', 1).hover.length === 0 && sn('pie-thl-nolabel', 1).els[0].z2 === 12);
  G('pie labels keep it off', sn('pie-thl-label', 1).hover.length === 0);
  G('a line\'s symbol and polyline', sn('line-thl', 1).hover.length === 2);
  G('at the threshold no hover layer, past it the hover layer', sn('sc-at-threshold', 1).count === 5 && !sn('sc-at-threshold', 1).thl
    && sn('sc-at-threshold', 1).hover.length === 0 && sn('sc-past-threshold', 1).thl && sn('sc-past-threshold', 1).hover.length === 1);
  G('a treemap never', sn('treemap-thl', 1).hover.length === 0 && sn('treemap-thl', 1).thl);
  return g;
}

function generate() {
  const cases = CASES.map(recordCase);
  const gs = guards(cases);
  for (const k of Object.keys(R)) must(R[k] > 0, 'recipe ' + k + ' never ran');
  const out = {
    source: 'ECharts ' + echarts.version + ' dist (' + path.basename(DIST) + ') under node, svg painter typed canvas, ssr init then _ssr = false, env.node = false',
    W, H,
    notes: [
      'Every option has animation false.',
      'A frame: due timers, NOW += 16, zr.animation.update(), zr._flush(false).',
      'A pointer or action step: NOW += 1000, the handler or dispatchAction, _onframe with scheduler.unfinished held false.',
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
