// Upstream's own answers for the LINES series (batch 121, roadmap C12): the
// layout (linesLayout: dataToPoint per coordinate, the control point from
// `lineStyle.curveness` -- not the graph's formula), the per-item style and
// the end symbols (linesVisual, Line._createLine / beforeUpdate: the symbols
// at pointAt(0) and pointAt(percent), turned along tangentAt, the label
// placed by position and distance), the polyline, the data formats (coords,
// a bare coords array, the flat typed format, the ec2 pairs), the clip, the
// effect symbol moving along the line (EffectLine / EffectPolyline: period,
// delay, constantSpeed, loop, roundTrip, the symbol types and the trail
// scaleY of 'line' / 'rect' / 'roundRect'), the zlevel and the motion-blur
// config a trail asks of the canvas painter, the enter animation (the line's
// shape.percent, the symbols and the label following it), large lines
// (LargeLineDraw: the Float32 segs, its bounding rect, findDataIndex and the
// dataIndex its mousemove handler writes), hover / emphasis / blur, the
// tooltip and the legend.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node: echarts.init(null, null, {renderer: 'svg', ssr:
// true}) and right after init chart._ssr = false; echarts.env.node = false
// and the chart prototype's getDom answering an empty object so TooltipView
// runs (tooltip-finish.js' recipe). The painter answers getType() 'canvas'
// (its `type` field stays 'svg', so progressive rendering stays off -- the
// Scheduler reads the field) and getLayer() a stub, so LinesView takes its
// canvas branch; zr.configLayer is recorded rather than applied. The
// motion blur itself is canvas pixels and is not recorded.
//
// TIME. The global Date is replaced before the dist loads. Every case starts
// at T0 = 1700000000000 (the clock is reset per case: no throttle here, and
// the effect's fractional delays round at the epoch's ulp, which the port
// replays with the same T0); setOption's own flush steps every clip once at
// T0 (sample 0), each later sample is NOW = T0 + t, zr.animation.update(),
// storage.getDisplayList(true) (Line.beforeUpdate runs there).
// setTimeout / clearTimeout are a queue (the tooltip's hideDelay); zrender's
// animation loop frame is dropped, never run.
//
//   node tools/advchart-oracle/lines.js
//
// writes tests/fixtures/advchart-lines.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex    a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//          lowercase (NaN 7ff8000000000000). Float32 values widened.
//   colour [r, g, b, a] from echarts.color.parse, null when unset.
//
// Top level: source, W, H, T0, notes[], cases[], guards[], recipes{}
//   case: id, group, note, option, record, frames[] | null, steps[]
//   record: series[] (after setOption, display list updated)
//   series: seriesIndex, count, large (pipeline), mode ('normal' | 'large' |
//     'none'), zlevel, polyline, effect (show), clip [x, y, w, h] hex | null,
//     trail {motionBlur, lastFrameAlpha hex} | null, items[] (normal), els[]
//     (large)
//   item: dataIndex, drawn; when drawn: kind ('line' | 'polyline'), shape
//     {x1, y1, x2, y2, cpx1, cpy1, percent} hex | points (hex, flat), style
//     {stroke, lineWidth hex, opacity hex, lineDash [hex] | null}, z2,
//     symbols [{name, symbolType, x, y, rotation, scale, box [x, y, w, h],
//     fill, stroke, opacity}], label {text, x, y, rotation, align,
//     verticalAlign, opacity, fill} | null, effect {symbolType, z2, x, y,
//     rotation, scaleX, scaleY, ignore, fill, stroke, shadowColor, opacity,
//     life, delay, loop, t} | null
//   el (large): segs (hex), polyline, curveness hex, bbox [x, y, w, h] hex,
//     style {stroke, lineWidth, opacity}, startIndex (null when unset), z2
//   frame: t (ms after T0), items [{seriesIndex, dataIndex, line {percent} ,
//     symbols [{name, x, y, rotation, scale}], label {x, y, rotation, align,
//     verticalAlign} | null, effect {present, x, y, rotation, scaleX, scaleY,
//     ignore, t} | null}]
//   step: i, t ('move' | 'leave' | 'action'), x, y, payload, hover {role,
//     seriesIndex, dataIndex (null: none, 'NaN': not a number)} | null,
//     events [{type, seriesIndex, dataIndex | 'NaN', name}], tooltip {shown,
//     rows [{marker, name, value}] | null, text}, states [{seriesIndex,
//     dataIndex, line {states, stroke, opacity hex, lineWidth hex, z2},
//     symbols [{states, fill, opacity hex}], label {states, opacity hex} |
//     null}], legend [{name, icon, fill, stroke, opacity hex}] (legend cases)
//
// Self-checks (recipes; each must run): R1 every laid-out point is
// recomputed from the option through the coordinate system's dataToPoint
// (and the control point by linesLayout's formula); R2 every effect symbol
// position at every frame is recomputed here from its __t (the quadratic and
// its derivative, or the polyline's offsets) -- for the trail symbols the
// scaleY too; R3 every large path's bounding rect is recomputed from its
// segs (minX, minY, then maxX and maxY as the width and height, upstream's
// own BoundingRect(minX, minY, maxX, maxY)); R4 every hovered large element's
// findDataIndex is recomputed here (containStroke, the polyline's first point
// kept as x0). Guards: distinguishing facts, each must hold. Two
// generations in one process give the same bytes; no \u0000; the JSON parses
// back.
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock (installed before the build loads) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-lines.json');

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
const hexOr = (v, d) => hex(v == null ? d : +v);
function colourOf(c) {
  if (c == null || c === 'none') return null;
  if (typeof c !== 'string') return null;
  const p = echarts.color.parse(c);
  return p ? [p[0], p[1], p[2], p[3]] : null;
}
const rectRec = r => (r ? [r.x, r.y, r.width, r.height].map(hex) : null);
const same = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || a === b;

// ---------- charts ----------
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
// the canvas branch of LinesView: getType 'canvas', a stub layer, the
// configLayer calls recorded per zlevel (the last one wins)
function canvasLike(chart) {
  const zr = chart.getZr();
  const cfg = {};
  zr.painter.getType = () => 'canvas';
  zr.painter.getLayer = () => ({ clear() {} });
  zr.configLayer = function (zlevel, config) {
    cfg[zlevel] = Object.assign(cfg[zlevel] || {}, config);
  };
  return cfg;
}

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

// =====================================================================
// the cases
// =====================================================================
const GRID = { left: 60, right: 40, top: 40, bottom: 40 };
const COLORS = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
function base(extra) {
  return Object.assign({ animation: false, color: COLORS, grid: GRID, tooltip: {},
    xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 } }, extra);
}
const CART = { type: 'lines', coordinateSystem: 'cartesian2d' };
const L = o => Object.assign({}, CART, o);
// a series with animation off: the effect still moves (it animates its
// symbol directly, not through the series' animation)
const LE = o => Object.assign({ animation: false }, CART, o);

const SAMPLES_EFFECT = [0, 16, 100, 250, 500, 1000, 1333, 1700, 2000, 2667, 3500, 3999, 4000, 4016, 4500, 5500, 7000, 8100];
const SAMPLES_DENSE = (() => { const a = []; for (let t = 0; t <= 3000; t += 100) a.push(t); a.push(3016, 4000, 4100, 6000, 6050); return a; })();
const SAMPLES_ENTER = [0, 16, 100, 250, 500, 750, 999, 1000, 1001, 1500];

// steps: ['move', at] | ['leave'] | ['action', payload]
// at: [x, y] | {line: [s, k, t]} (a point on item k's line at t) |
//   {sym: [s, k, 'from'|'to']} | {seg: [s, k, j, t]} (a large path's item k,
//   segment j, at t) | {off: [x, y]}
const CASES = [];
function C(id, group, note, option, opts) {
  CASES.push(Object.assign({ id, group, note, option, steps: [], samples: null, legend: false }, opts || {}));
}

// ---- A. drawing ----
C('d-straight', 'draw', 'three straight lines, the defaults: opacity 0.5, no symbols, the palette colour',
  base({ series: [L({ data: [{ coords: [[10, 10], [80, 60]] }, { coords: [[20, 80], [90, 30]] }, { coords: [[50, 5], [50, 95]] }] })] }));
C('d-curve', 'draw', 'series curveness 0.3; items -0.25, an explicit 0 (straight), the string "0.5", and a horizontal one',
  base({ series: [L({ lineStyle: { curveness: 0.3 }, data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]], lineStyle: { curveness: -0.25 } },
    { coords: [[15, 50], [70, 55]], lineStyle: { curveness: 0 } },
    { coords: [[30, 20], [95, 85]], lineStyle: { curveness: '0.5' } },
    { coords: [[5, 40], [60, 40]] },
  ] })] }));
C('d-poly', 'draw', 'polyline: true -- three, five and two points; symbols and labels are not drawn on a polyline',
  base({ series: [L({ polyline: true, symbol: ['circle', 'arrow'], label: { show: true }, data: [
    { coords: [[10, 20], [30, 40], [50, 20]] },
    { coords: [[5, 90], [25, 70], [45, 85], [65, 60], [95, 75]] },
    { coords: [[60, 10], [90, 30]], lineStyle: { color: '#ff0000', width: 3 } },
  ] })] }));
C('d-symbols', 'draw', 'symbols: the series pair, an item string, an item pair with a 0 size (the series size stays), emptyCircle, on a curve',
  base({ series: [L({ symbol: ['circle', 'arrow'], symbolSize: [8, 14], data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]], symbol: 'triangle' },
    { coords: [[15, 50], [45, 50]], symbol: ['none', 'diamond'], symbolSize: [0, 20] },
    { coords: [[60, 90], [60, 40]], symbol: 'emptyCircle', symbolSize: 12 },
    { coords: [[30, 20], [95, 85]], lineStyle: { curveness: 0.4 } },
    { coords: [[90, 10], [55, 25]], symbol: ['rect', 'roundRect'], symbolSize: [6, 10] },
  ] })] }));
C('d-labels', 'draw', 'labels: end with no distance, start, middle 6, insideStartTop [4, 8], insideEndBottom, insideMiddle, a reversed line, curves, the default texts',
  base({ series: [L({ label: { show: true }, data: [
    { coords: [[10, 10], [40, 30]] },
    { coords: [[20, 80], [50, 60]], label: { position: 'start' }, name: 'n1' },
    { coords: [[55, 85], [95, 70]], label: { position: 'middle', distance: 6 }, value: 12.5 },
    { coords: [[50, 10], [90, 40]], label: { position: 'insideStartTop', distance: [4, 8] }, value: [3, 4] },
    { coords: [[90, 50], [60, 55]], label: { position: 'insideEndBottom' }, fromName: 'A', toName: 'B' },
    { coords: [[10, 45], [40, 60]], label: { position: 'insideMiddle' }, lineStyle: { curveness: 0.3 }, value: 0.1 + 0.2 },
    [[30, 92], [5, 70]],
    { coords: [[70, 20], [95, 5]], lineStyle: { curveness: -0.5 }, label: { position: 'insideEnd', distance: 3 } },
  ] })] }));
C('d-formatter', 'draw', 'a label formatter template over the item: {a} {b} {c}',
  base({ series: [L({ name: 'routes', label: { show: true, position: 'middle', formatter: '{a}|{b}|{c}' }, data: [
    { coords: [[10, 10], [60, 40]], name: 'x', value: 7 },
    { coords: [[20, 80], [80, 70]], fromName: 'P', toName: 'Q' },
  ] })] }));
C('d-style', 'draw', 'the palette over three series; series lineStyle width 2 dotted opacity 1; items with their own colour, width, opacity, dashed',
  base({ series: [
    L({ lineStyle: { width: 2, type: 'dotted', opacity: 1 }, data: [
      { coords: [[10, 10], [80, 20]] },
      { coords: [[10, 30], [80, 40]], lineStyle: { color: '#123456', width: 3, opacity: 0.8, type: 'dashed' } },
    ] }),
    L({ data: [{ coords: [[10, 50], [80, 60]] }] }),
    L({ lineStyle: { color: '#aa3300' }, data: [{ coords: [[10, 70], [80, 80]], lineStyle: { width: 0.5 } }] }),
  ] }));
C('d-formats', 'draw', 'the data formats: bare coords arrays, the flat typed format [count, x, y, ...] (dimensions given: the dev build asserts them), the ec2 pairs',
  base({ series: [
    L({ label: { show: true }, data: [[[10, 10], [40, 30]], [[15, 60], [45, 80], [70, 70]]] }),
    L({ polyline: true, dimensions: ['value'], label: { show: true }, data: [2, 50, 10, 90, 30, 3, 55, 60, 75, 85, 95, 65] }),
    L({ label: { show: true }, data: [[{ coord: [20, 40], name: 'from' }, { coord: [60, 45], name: 'to' }], [{ coord: [30, 90] }, { coord: [70, 95] }]] }),
    L({ dimensions: ['value'], label: { show: true }, data: [2, 5, 30, 35, 35, 2, 40, 5, 60, 25] }),
  ] }));
C('d-category', 'draw', 'category axes: coords by name, an unknown name (not drawn), by index',
  { animation: false, color: COLORS, grid: GRID, tooltip: {},
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [L({ data: [{ coords: [['a', 10], ['c', 50]] }, { coords: [['b', 80], ['zz', 20]] }, { coords: [[1, 30], [4, 70]] }] })] });
C('d-nan', 'draw', 'a null coordinate: the item is not drawn; a NaN in the second point too',
  base({ series: [L({ data: [{ coords: [[10, 10], [80, 60]] }, { coords: [[null, 20], [50, 50]] }, { coords: [[20, 20], [60, null]] }, { coords: [[30, 70], [90, 90]] }] })] }));
C('d-clip', 'draw', 'lines past the axis range: the clip rect (default true) and clip: false',
  base({ series: [
    L({ data: [{ coords: [[-20, 50], [130, 60]] }, { coords: [[50, -10], [60, 120]] }] }),
    L({ clip: false, data: [{ coords: [[-10, 20], [120, 30]] }] }),
  ] }));
C('d-polar', 'draw', 'on a polar: radius then angle',
  { animation: false, color: COLORS, tooltip: {},
    polar: { center: ['50%', '50%'], radius: '70%' },
    radiusAxis: { type: 'value', min: 0, max: 100 }, angleAxis: { type: 'value', min: 0, max: 360 },
    series: [{ type: 'lines', coordinateSystem: 'polar', symbol: ['none', 'arrow'], data: [{ coords: [[20, 0], [80, 90]] }, { coords: [[50, 180], [90, 300]], lineStyle: { curveness: 0.2 } }] }] });
C('d-calendar', 'draw', 'on a calendar: the date of each coordinate; a date out of the range is not drawn (dataToPoint clamps by default)',
  { animation: false, color: COLORS, tooltip: {},
    calendar: { range: ['2024-01-01', '2024-03-31'], top: 60, left: 50, right: 30, cellSize: ['auto', 20] },
    series: [{ type: 'lines', coordinateSystem: 'calendar', data: [{ coords: [['2024-01-03', 0], ['2024-02-10', 0]] }, { coords: [['2024-03-01', 5], ['2024-01-20', 1]], lineStyle: { curveness: 0.3 } },
      { coords: [['2024-05-01', 0], ['2024-01-10', 0]] }] }] });
C('d-geo-missing', 'draw', 'no coordinateSystem: the default is geo, there is none, nothing is drawn',
  base({ series: [{ type: 'lines', data: [{ coords: [[10, 10], [80, 60]] }] }] }));

// ---- B. the effect ----
C('e-default', 'effect', 'effect show: the defaults (period 4, delay idx/count*period/3, a circle of 3); straight and curved',
  base({ series: [LE({ effect: { show: true }, data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 } },
    { coords: [[50, 5], [50, 95]] },
    { coords: [[90, 90], [10, 70]], lineStyle: { curveness: -0.2 } },
  ] })] }), { samples: SAMPLES_EFFECT });
C('e-speed', 'effect', 'constantSpeed 80 px/s, an arrow [8, 6] in its own colour, a delay of 300',
  base({ series: [LE({ effect: { show: true, constantSpeed: 80, symbol: 'arrow', symbolSize: [8, 6], color: '#ff0000', delay: 300 }, data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 } },
    { coords: [[5, 50], [30, 50]] },
  ] })] }), { samples: SAMPLES_EFFECT });
C('e-noloop', 'effect', 'loop false, period 1: the symbol is removed when its clip is done',
  base({ series: [LE({ effect: { show: true, loop: false, period: 1, symbolSize: 6 }, data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]] },
  ] })] }), { samples: [0, 16, 250, 500, 999, 1000, 1001, 1100, 1300, 1334, 1400, 2000] });
C('e-trail', 'effect', 'trailLength 0.4 with a rect [3, 8]: the zlevel, the motion blur, the trail scaleY',
  base({ series: [LE({ effect: { show: true, trailLength: 0.4, symbol: 'rect', symbolSize: [3, 8], period: 2 }, data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 } },
  ] })] }), { samples: SAMPLES_DENSE });
C('e-trail-line', 'effect', "symbol 'line' and 'roundRect' trails beside a bar series; the components and the later series get the next zlevel",
  base({ legend: {}, series: [
    { type: 'bar', data: [[20, 30], [60, 50]] },
    LE({ effect: { show: true, trailLength: 0.1, symbol: 'line', symbolSize: 2, period: 1.5 }, data: [{ coords: [[10, 90], [90, 70]] }] }),
    LE({ effect: { show: true, trailLength: 0.1, symbol: 'roundRect', symbolSize: [4, 4], period: 1.5 }, data: [{ coords: [[10, 20], [90, 40]], lineStyle: { curveness: 0.2 } }] }),
    { type: 'scatter', data: [[50, 50]] },
  ] }), { samples: SAMPLES_DENSE });
C('e-trail0', 'effect', 'trailLength 0: no motion blur, no zlevel of its own',
  base({ series: [LE({ effect: { show: true, trailLength: 0 }, data: [{ coords: [[10, 10], [80, 60]] }] })] }),
  { samples: [0, 500, 1000] });
C('e-poly', 'effect', 'a polyline effect (EffectPolyline): the offsets, the frame search forward and back across the loop',
  base({ series: [LE({ polyline: true, effect: { show: true, period: 2, symbol: 'triangle', symbolSize: 5 }, data: [
    { coords: [[10, 20], [30, 40], [50, 20], [70, 60]] },
    { coords: [[5, 90], [25, 70], [45, 85], [65, 60], [95, 75]] },
  ] })] }), { samples: SAMPLES_DENSE });
C('e-poly-speed', 'effect', 'a polyline effect at constantSpeed 120',
  base({ series: [LE({ polyline: true, effect: { show: true, constantSpeed: 120, symbol: 'rect', symbolSize: 4, trailLength: 0.3 }, data: [
    { coords: [[10, 20], [30, 40], [50, 20], [70, 60]] },
  ] })] }), { samples: SAMPLES_DENSE });
C('e-roundtrip', 'effect', 'roundTrip: __t runs to 2 over twice the period and the symbol comes back',
  base({ series: [LE({ effect: { show: true, roundTrip: true, period: 1 }, data: [
    { coords: [[10, 10], [80, 60]] },
    { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 } },
  ] })] }), { samples: SAMPLES_DENSE });
C('e-item', 'effect', "an item's own effect: period 1.5 and a diamond; an item's effect.show false is ignored (the series decides)",
  base({ series: [LE({ effect: { show: true }, data: [
    { coords: [[10, 10], [80, 60]], effect: { period: 1.5, symbol: 'diamond', symbolSize: 7 } },
    { coords: [[20, 80], [90, 30]], effect: { show: false } },
  ] })] }), { samples: SAMPLES_EFFECT });

// ---- C. the enter animation ----
C('a-enter', 'enter', 'the enter animation: shape.percent 0 -> 1 (1000 ms cubicOut); the symbols scale and ride the end; the labels follow',
  { color: COLORS, grid: GRID, tooltip: {}, xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [L({ symbol: ['circle', 'arrow'], symbolSize: [6, 12], label: { show: true }, data: [
      { coords: [[10, 10], [80, 60]], value: 3 },
      { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 }, label: { position: 'middle' }, name: 'c' },
      { coords: [[90, 50], [40, 55]], label: { position: 'insideStartTop', distance: 4 } },
    ] })] }, { samples: SAMPLES_ENTER });
C('a-poly', 'enter', 'a polyline does not animate in',
  { color: COLORS, grid: GRID, tooltip: {}, xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [L({ polyline: true, data: [{ coords: [[10, 20], [30, 40], [50, 20]] }] })] }, { samples: [0, 100, 1000] });
C('a-effect', 'enter', 'the enter and the effect together; animationDuration 600',
  { color: COLORS, grid: GRID, tooltip: {}, xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [L({ animationDuration: 600, symbol: ['none', 'arrow'], effect: { show: true, period: 2 }, data: [
      { coords: [[10, 10], [80, 60]] },
      { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 } },
    ] })] }, { samples: SAMPLES_ENTER });

// ---- D. large ----
function ladder(n, x0, x1, y0, dy) {
  const out = [];
  for (let i = 0; i < n; i++) out.push({ coords: [[x0, y0 + i * dy], [x1, y0 + i * dy + 3]] });
  return out;
}
C('l-straight', 'large', 'large, largeThreshold 3, six straight lines: hovering row 0 finds no data, a later row a NaN dataIndex',
  base({ series: [L({ large: true, largeThreshold: 3, data: ladder(6, 10, 90, 10, 15) })] }),
  { steps: [['move', { seg: [0, 0, 0, 0.5] }], ['move', { seg: [0, 3, 0, 0.3] }], ['move', { seg: [0, 5, 0, 0.7] }], ['move', { off: [300, 380] }], ['leave']] });
C('l-curve', 'large', 'large curved lines: the quadratic containStroke',
  base({ series: [L({ large: true, largeThreshold: 3, lineStyle: { curveness: 0.25, width: 2 }, data: ladder(5, 10, 90, 10, 18) })] }),
  { steps: [['move', { seg: [0, 1, 0, 0.5] }], ['move', { seg: [0, 4, 0, 0.2] }], ['leave']] });
C('l-poly', 'large', 'large polylines: the count in the segs, the bbox reading counts as coordinates, the second segment tested from the first point',
  base({ series: [L({ large: true, largeThreshold: 2, polyline: true, data: [
    { coords: [[10, 10], [30, 30], [50, 10]] },
    { coords: [[10, 60], [40, 80], [70, 60], [90, 90]] },
    { coords: [[60, 20], [90, 40]] },
    { coords: [[55, 50], [95, 55]] },
  ] })] }),
  { steps: [['move', { seg: [0, 1, 0, 0.5] }], ['move', { seg: [0, 1, 1, 0.5] }], ['move', { seg: [0, 1, 2, 0.5] }], ['move', { seg: [0, 2, 0, 0.5] }], ['leave']] });
C('l-poly-odd', 'large', 'large polylines whose segs hold an odd count of numbers: the bounding rect reads past the end and is not a number, nothing is hovered',
  base({ series: [L({ large: true, largeThreshold: 2, polyline: true, data: [
    { coords: [[10, 10], [30, 30], [50, 10]] },
    { coords: [[10, 60], [40, 80], [70, 60], [90, 90]] },
    { coords: [[60, 20], [90, 40]] },
  ] })] }),
  { steps: [['move', { seg: [0, 2, 0, 0.5] }]] });
C('l-under', 'large', 'large true, five lines under the threshold 6: drawn normally',
  base({ series: [L({ large: true, largeThreshold: 6, data: ladder(5, 10, 90, 10, 15) })] }));
C('l-default', 'large', 'large true, ten lines under the default threshold 2000',
  base({ series: [L({ large: true, data: ladder(10, 10, 90, 10, 8) })] }));
C('l-style', 'large', 'a large batch in its own colour, width 3, opacity 0.8; clip off',
  base({ series: [L({ large: true, largeThreshold: 1, clip: false, lineStyle: { color: '#336699', width: 3, opacity: 0.8 }, data: ladder(4, -10, 110, 20, 20) })] }));

// ---- E. hover ----
C('h-basic', 'hover', 'two series with names, a legend and the item tooltip: a line, a curve, a symbol, off and leave',
  base({ legend: {}, series: [
    L({ name: 'A', symbol: ['none', 'arrow'], symbolSize: 12, data: [
      { coords: [[10, 10], [80, 60]], name: 'first', value: 4 },
      { coords: [[20, 80], [90, 30]], lineStyle: { curveness: 0.3 }, fromName: 'X', toName: 'Y', value: 9 },
    ] }),
    L({ name: 'B', data: [[[10, 90], [90, 90]], { coords: [[30, 40], [60, 40]], fromName: 'only' }] }),
  ] }), { legend: true, steps: [['move', { line: [0, 0, 0.5] }], ['move', { line: [0, 1, 0.4] }], ['move', { sym: [0, 0, 'to'] }],
    ['move', { line: [1, 0, 0.5] }], ['move', { line: [1, 1, 0.5] }], ['move', { off: [300, 380] }], ['leave']] });
C('h-focus', 'hover', "emphasis focus 'series' with its own lineStyle; blur lineStyle; highlight and downplay actions",
  base({ series: [
    L({ name: 'A', emphasis: { focus: 'series', lineStyle: { width: 4, color: '#ff0000' } }, blur: { lineStyle: { opacity: 0.1 } },
      symbol: ['circle', 'none'], label: { show: true, position: 'middle' }, data: [
        { coords: [[10, 10], [80, 60]], value: 1 },
        { coords: [[20, 80], [90, 30]], value: 2 },
      ] }),
    L({ name: 'B', symbol: ['none', 'arrow'], data: [{ coords: [[10, 90], [90, 85]] }, { coords: [[30, 30], [60, 40]] }] }),
  ] }), { steps: [['move', { line: [0, 0, 0.25] }], ['move', { line: [1, 0, 0.5] }], ['leave'],
    ['action', { type: 'highlight', seriesIndex: 0, dataIndex: 1 }], ['action', { type: 'downplay', seriesIndex: 0, dataIndex: 1 }],
    ['action', { type: 'highlight', seriesIndex: 1 }], ['action', { type: 'downplay', seriesIndex: 1 }]] });
C('h-legend', 'hover', 'legend icons; a legend hover highlights the series; a toggle hides it',
  base({ legend: {}, series: [
    L({ name: 'A', data: [{ coords: [[10, 10], [80, 60]] }] }),
    L({ name: 'B', lineStyle: { color: '#aa0000', opacity: 0.3 }, polyline: true, data: [{ coords: [[10, 50], [50, 80], [90, 50]] }] }),
  ] }), { legend: true, steps: [['action', { type: 'highlight', seriesName: 'A' }], ['action', { type: 'downplay', seriesName: 'A' }],
    ['action', { type: 'legendToggleSelect', name: 'B' }], ['move', { off: [300, 380] }]] });
C('h-names', 'hover', "an unnamed series: an item's name, from > to, only a fromName, nothing (the series' own name is the fallback upstream reads first)",
  base({ series: [L({ data: [
    { coords: [[10, 10], [80, 20]], name: 'own', value: 1 },
    { coords: [[10, 40], [80, 50]], fromName: 'X', toName: 'Y', value: 2 },
    { coords: [[10, 70], [80, 80]], toName: 'Z' },
    { coords: [[10, 95], [80, 95]], value: [5, 6] },
  ] })] }),
  { steps: [['move', { line: [0, 0, 0.5] }], ['move', { line: [0, 1, 0.5] }], ['move', { line: [0, 2, 0.5] }], ['move', { line: [0, 3, 0.5] }], ['leave']] });
C('h-poly', 'hover', 'hovering a polyline and its tooltip',
  base({ series: [L({ name: 'P', polyline: true, data: [{ coords: [[10, 20], [40, 60], [80, 30]], name: 'route', value: 3 }] })] }),
  { steps: [['move', { line: [0, 0, 0.5] }], ['leave']] });

// =====================================================================
// the elements
// =====================================================================
function seriesModel(chart, s) { return chart.getModel().getSeriesByIndex(s); }
function viewOf(chart, sm) { return chart.getViewOfSeriesModel(sm); }
// an item's parts: the Line or Polyline group, its effect symbol
function partsOf(el) {
  if (!el) return null;
  const first = el.childAt(0);
  if (first && first.isGroup) return { inner: first, effect: el.childAt(1) || null };
  return { inner: el, effect: null };
}
function lineOf(inner) {
  return inner.childOfName('line') || inner.childAt(0);
}
function isEffectSymbol(el) {
  const p = el.parent;
  return !!(p && p.childAt(0) && p.childAt(0).isGroup && p.childAt(1) === el);
}
function largeEls(chart, sm) {
  const out = [];
  const v = viewOf(chart, sm);
  if (!v) return out;
  v.group.traverse(el => { if (!el.isGroup && typeof el.findDataIndex === 'function' && el.shape && el.shape.segs) out.push(el); });
  return out;
}
function styleRec(s) {
  return {
    stroke: colourOf(s.stroke),
    lineWidth: hexOr(s.lineWidth, 1),
    opacity: hexOr(s.opacity, 1),
    lineDash: s.lineDash ? (Array.isArray(s.lineDash) ? s.lineDash.map(hex) : String(s.lineDash)) : null,
  };
}
function symbolRec(sym) {
  return {
    name: sym.name, symbolType: sym.shape.symbolType,
    x: hex(sym.x), y: hex(sym.y), rotation: hex(sym.rotation), scale: hex(sym.scaleX),
    box: [sym.shape.x, sym.shape.y, sym.shape.width, sym.shape.height].map(hex),
    fill: colourOf(sym.style.fill), stroke: colourOf(sym.style.stroke), opacity: hexOr(sym.style.opacity, 1),
  };
}
// the point the text hangs from: the label's own transform applied to its
// origin (no transform: its x / y)
function anchorOf(tc) {
  const m = tc.transform;
  return m ? [hex(m[4]), hex(m[5])] : [hex(tc.x), hex(tc.y)];
}
function labelRec(inner) {
  const tc = inner.getTextContent && inner.getTextContent();
  if (!tc) return null;
  return { text: String(tc.style.text == null ? '' : tc.style.text), x: hex(tc.x), y: hex(tc.y), rotation: hex(tc.rotation || 0),
    origin: [hex(tc.originX || 0), hex(tc.originY || 0)], anchor: anchorOf(tc),
    align: tc.style.align || null, verticalAlign: tc.style.verticalAlign || null, ignore: !!tc.ignore,
    opacity: hexOr(tc.style.opacity, 1), fill: colourOf(tc.style.fill) };
}
function clipOf(sym) {
  const a = sym.animators && sym.animators[0];
  const c = a && a.getClip ? a.getClip() : null;
  return c;
}
function effectRec(sym) {
  if (!sym) return null;
  const c = clipOf(sym);
  return {
    symbolType: sym.shape.symbolType, z2: sym.z2,
    x: hex(sym.x), y: hex(sym.y), rotation: hex(sym.rotation || 0), scaleX: hex(sym.scaleX), scaleY: hex(sym.scaleY),
    ignore: !!sym.ignore, fill: colourOf(sym.style.fill), stroke: colourOf(sym.style.stroke),
    shadowColor: colourOf(sym.style.shadowColor), opacity: hexOr(sym.style.opacity, 1),
    life: c ? hex(c._life) : null, delay: c ? hex(c._delay) : null, loop: c ? !!c.loop : null,
    t: sym.__t == null ? null : hex(sym.__t),
  };
}
function itemRec(sm, idx) {
  const data = sm.getData();
  const el = data.getItemGraphicEl(idx);
  if (!el) return { dataIndex: idx, drawn: false };
  const { inner, effect } = partsOf(el);
  const line = lineOf(inner);
  const r = { dataIndex: idx, drawn: true };
  if (line.type === 'polyline') {
    r.kind = 'polyline';
    const pts = [];
    for (const p of line.shape.points) { pts.push(p[0], p[1]); }
    r.points = pts.map(hex);
  }
  else {
    r.kind = 'line';
    const s = line.shape;
    r.shape = { x1: hex(s.x1), y1: hex(s.y1), x2: hex(s.x2), y2: hex(s.y2), cpx1: hex(+s.cpx1), cpy1: hex(+s.cpy1), percent: hex(s.percent) };
  }
  r.style = styleRec(line.style);
  r.z2 = line.z2;
  r.symbols = [];
  for (const nm of ['fromSymbol', 'toSymbol']) {
    const sym = inner.childOfName(nm);
    if (sym) r.symbols.push(symbolRec(sym));
  }
  r.label = labelRec(inner);
  r.effect = effectRec(effect);
  return r;
}
function largeRec(el) {
  return {
    segs: hexes(el.shape.segs), polyline: !!el.shape.polyline, curveness: hexOr(el.shape.curveness, 0),
    bbox: rectRec(el.getBoundingRect()), style: styleRec(el.style), z2: el.z2,
    startIndex: el.__startIndex == null ? null : el.__startIndex,
  };
}
function seriesRecords(chart, cfg) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'lines') return;
    const data = sm.getData();
    const view = viewOf(chart, sm);
    const cp = view.group.getClipPath();
    const els = largeEls(chart, sm);
    const zl = sm.get('zlevel') || 0;
    let clip = null;
    if (cp) {
      if (cp.type === 'rect') clip = { kind: 'rect', rect: [cp.shape.x, cp.shape.y, cp.shape.width, cp.shape.height].map(hex) };
      else clip = { kind: cp.type, shape: Object.keys(cp.shape).sort().map(k => [k, typeof cp.shape[k] === 'number' ? hex(cp.shape[k]) : cp.shape[k]]) };
    }
    const tr = cfg[zl];
    const rec = {
      seriesIndex: sm.seriesIndex, count: data.count(), large: !!sm.pipelineContext.large,
      mode: els.length ? 'large' : (sm.coordinateSystem ? 'normal' : 'none'),
      zlevel: zl, polyline: !!sm.get('polyline'), effect: !!sm.get(['effect', 'show']),
      clip,
      trail: tr && tr.motionBlur ? { motionBlur: true, lastFrameAlpha: hex(tr.lastFrameAlpha) } : null,
      items: [], els: els.map(largeRec),
    };
    if (!els.length && sm.coordinateSystem) for (let i = 0; i < data.count(); i++) rec.items.push(itemRec(sm, i));
    out.push(rec);
  });
  return out;
}
function zlevels(chart) {
  const out = [];
  chart.getModel().eachComponent((t, m) => {
    if (t === 'series' || t === 'legend') out.push({ type: t, index: m.componentIndex, zlevel: m.get('zlevel') || 0 });
  });
  return out;
}

// =====================================================================
// the self-checks' arithmetic
// =====================================================================
const RECIPES = { R1: 0, R2: 0, R3: 0, R4: 0 };
const quadAt = (p0, p1, p2, t) => { const onet = 1 - t; return onet * (onet * p0 + 2 * t * p1) + t * t * p2; };
const quadDerivAt = (p0, p1, p2, t) => 2 * ((1 - t) * (p1 - p0) + t * (p2 - p1));
const dist = (a, b) => Math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));

// R1: the item's points from its coords and its curveness
function checkLayout(chart, where) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'lines' || !sm.coordinateSystem || sm.pipelineContext.large) return;
    const data = sm.getData();
    const cs = sm.coordinateSystem;
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      const coords = [];
      sm.getLineCoords(i, coords);
      const line = lineOf(partsOf(el).inner);
      if (line.type === 'polyline') {
        line.shape.points.forEach((p, k) => {
          const q = cs.dataToPoint(coords[k]);
          must(same(q[0], p[0]) && same(q[1], p[1]), where + ': R1 polyline point');
          RECIPES.R1++;
        });
        continue;
      }
      const p0 = cs.dataToPoint(coords[0]);
      const p1 = cs.dataToPoint(coords[1]);
      const c = data.getItemModel(i).get(['lineStyle', 'curveness']);
      const s = line.shape;
      must(same(p0[0], s.x1) && same(p0[1], s.y1) && same(p1[0], s.x2) && same(p1[1], s.y2), where + ': R1 ends');
      if (+c) {
        const cx = (p0[0] + p1[0]) / 2 - (p0[1] - p1[1]) * c;
        const cy = (p0[1] + p1[1]) / 2 - (p1[0] - p0[0]) * c;
        must(same(cx, s.cpx1) && same(cy, s.cpy1), where + ': R1 control point');
      }
      else must(Number.isNaN(+s.cpx1), where + ': R1 straight');
      RECIPES.R1++;
    }
  });
}

// R2: the effect symbol where its __t puts it (EffectLine / EffectPolyline),
// with a shadow of the run state per symbol
const SHADOW = new Map();
function checkEffect(chart, where) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'lines' || !sm.get(['effect', 'show']) || sm.pipelineContext.large) return;
    const data = sm.getData();
    const poly = !!sm.get('polyline');
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      const sym = el.childAt(1);
      if (!sym || sym.ignore) continue;
      let sh = SHADOW.get(sym);
      if (!sh) { sh = { lastFrame: 0, lastFramePercent: 0, lastT: undefined, x: 0, y: 0 }; SHADOW.set(sym, sh); }
      const pts = data.getItemLayout(i);
      const T = sym.__t;
      const t = T <= 1 ? T : 2 - T;
      let x, y, rot;
      if (!poly) {
        const p1 = pts[0], p2 = pts[1];
        const cp = pts[2] || [(p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2];
        x = quadAt(p1[0], cp[0], p2[0], t);
        y = quadAt(p1[1], cp[1], p2[1], t);
        const tx = T <= 1 ? quadDerivAt(p1[0], cp[0], p2[0], t) : quadDerivAt(p2[0], cp[0], p1[0], 1 - t);
        const ty = T <= 1 ? quadDerivAt(p1[1], cp[1], p2[1], t) : quadDerivAt(p2[1], cp[1], p1[1], 1 - t);
        rot = -Math.atan2(ty, tx) - Math.PI / 2;
        const st = el._symbolType;
        if (st === 'line' || st === 'rect' || st === 'roundRect') {
          let sy;
          const last = [sh.x, sh.y];
          if (sh.lastT !== undefined && sh.lastT < T) {
            sy = dist(last, [x, y]) * 1.05;
            if (t === 1) { x = last[0] + (x - last[0]) / 2; y = last[1] + (y - last[1]) / 2; }
          }
          else if (sh.lastT === 1) sy = 2 * dist(p1, [x, y]);
          else sy = el._symbolScale[1];
          must(same(sy, sym.scaleY), where + ': R2 trail scaleY ' + i);
        }
      }
      else {
        const off = [0];
        let len = 0;
        for (let k = 1; k < pts.length; k++) { len += dist(pts[k - 1], pts[k]); off.push(len); }
        for (let k = 0; k < off.length; k++) off[k] /= len;
        const n = pts.length;
        let frame;
        if (t < sh.lastFramePercent) {
          const start = Math.min(sh.lastFrame + 1, n - 1);
          for (frame = start; frame >= 0; frame--) if (off[frame] <= t) break;
          frame = Math.min(frame, n - 2);
        }
        else {
          for (frame = sh.lastFrame; frame < n; frame++) if (off[frame] > t) break;
          frame = Math.min(frame - 1, n - 2);
        }
        const p = (t - off[frame]) / (off[frame + 1] - off[frame]);
        const a = pts[frame], b = pts[frame + 1];
        x = a[0] * (1 - p) + p * b[0];
        y = a[1] * (1 - p) + p * b[1];
        const tx = T <= 1 ? b[0] - a[0] : a[0] - b[0];
        const ty = T <= 1 ? b[1] - a[1] : a[1] - b[1];
        rot = -Math.atan2(ty, tx) - Math.PI / 2;
        sh.lastFrame = frame;
        sh.lastFramePercent = t;
      }
      must(same(x, sym.x) && same(y, sym.y) && same(rot, sym.rotation), where + ': R2 effect ' + i + ' at __t ' + T);
      sh.lastT = T;
      sh.x = sym.x;
      sh.y = sym.y;
      RECIPES.R2++;
    }
  });
}

// R3 / R4: the large path's box and findDataIndex
function containLine(x0, y0, x1, y1, l, x, y) {
  if (l === 0) return false;
  if ((y > y0 + l && y > y1 + l) || (y < y0 - l && y < y1 - l) || (x > x0 + l && x > x1 + l) || (x < x0 - l && x < x1 - l)) return false;
  if (x0 === x1) return Math.abs(x - x0) <= l / 2;
  const a = (y0 - y1) / (x0 - x1);
  const b = (x0 * y1 - x1 * y0) / (x0 - x1);
  const tmp = a * x - y + b;
  return tmp * tmp / (a * a + 1) <= l / 2 * l / 2;
}
function projectQuad(x0, y0, x1, y1, x2, y2, x, y) {
  let t;
  let interval = 0.005;
  let d = Infinity;
  for (let _t = 0; _t < 1; _t += 0.05) {
    const qx = quadAt(x0, x1, x2, _t), qy = quadAt(y0, y1, y2, _t);
    const d1 = (x - qx) * (x - qx) + (y - qy) * (y - qy);
    if (d1 < d) { t = _t; d = d1; }
  }
  d = Infinity;
  for (let i = 0; i < 32; i++) {
    if (interval < 1e-4) break;
    const prev = t - interval, next = t + interval;
    let qx = quadAt(x0, x1, x2, prev), qy = quadAt(y0, y1, y2, prev);
    const d1 = (qx - x) * (qx - x) + (qy - y) * (qy - y);
    if (prev >= 0 && d1 < d) { t = prev; d = d1; }
    else {
      qx = quadAt(x0, x1, x2, next); qy = quadAt(y0, y1, y2, next);
      const d2 = (qx - x) * (qx - x) + (qy - y) * (qy - y);
      if (next <= 1 && d2 < d) { t = next; d = d2; }
      else interval *= 0.5;
    }
  }
  return Math.sqrt(d);
}
function containQuad(x0, y0, x1, y1, x2, y2, l, x, y) {
  if (l === 0) return false;
  if ((y > y0 + l && y > y1 + l && y > y2 + l) || (y < y0 - l && y < y1 - l && y < y2 - l)
    || (x > x0 + l && x > x1 + l && x > x2 + l) || (x < x0 - l && x < x1 - l && x < x2 - l)) return false;
  return projectQuad(x0, y0, x1, y1, x2, y2, x, y) <= l / 2;
}
function findIndex(el, x, y) {
  const segs = el.shape.segs;
  const c = el.shape.curveness;
  const lw = el.style.lineWidth;
  let di = 0;
  if (el.shape.polyline) {
    for (let i = 0; i < segs.length;) {
      const count = segs[i++];
      if (count > 0) {
        const x0 = segs[i++], y0 = segs[i++];
        for (let k = 1; k < count; k++) {
          const x1 = segs[i++], y1 = segs[i++];
          if (containLine(x0, y0, x1, y1, lw, x, y)) return di;
        }
      }
      di++;
    }
    return -1;
  }
  for (let i = 0; i < segs.length;) {
    const x0 = segs[i++], y0 = segs[i++], x1 = segs[i++], y1 = segs[i++];
    if (c > 0) {
      const x2 = (x0 + x1) / 2 - (y0 - y1) * c, y2 = (y0 + y1) / 2 - (x1 - x0) * c;
      if (containQuad(x0, y0, x2, y2, x1, y1, lw, x, y)) return di;
    }
    else if (containLine(x0, y0, x1, y1, lw, x, y)) return di;
    di++;
  }
  return -1;
}
function bboxOf(segs) {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  for (let i = 0; i < segs.length;) {
    const x = segs[i++], y = segs[i++];
    minX = Math.min(x, minX); maxX = Math.max(x, maxX);
    minY = Math.min(y, minY); maxY = Math.max(y, maxY);
  }
  return [minX, minY, maxX, maxY];
}
function checkLarge(chart, where) {
  chart.getModel().eachSeries(sm => {
    for (const el of largeEls(chart, sm)) {
      const b = bboxOf(el.shape.segs);
      const r = el.getBoundingRect();
      must(same(b[0], r.x) && same(b[1], r.y) && same(b[2], r.width) && same(b[3], r.height), where + ': R3');
      RECIPES.R3++;
    }
  });
}

// =====================================================================
// pointer positions
// =====================================================================
function hoverTarget(chart, x, y) {
  return chart.getZr().handler.findHover(x, y).target;
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
function pointOnLine(line, t) {
  if (line.type === 'polyline') {
    const p = line.shape.points;
    const seg = Math.min(Math.floor(t * (p.length - 1)), p.length - 2);
    const u = t * (p.length - 1) - seg;
    return [p[seg][0] + (p[seg + 1][0] - p[seg][0]) * u, p[seg][1] + (p[seg + 1][1] - p[seg][1]) * u];
  }
  return line.pointAt(t);
}
// the distance from (x, y) to the line, sampled finely
function distToLine(line, x, y) {
  let best = Infinity;
  for (let k = 0; k <= 400; k++) {
    const p = pointOnLine(line, k / 400);
    best = Math.min(best, Math.hypot(p[0] - x, p[1] - y));
  }
  return best;
}
function resolveAt(chart, at, where) {
  if (Array.isArray(at)) return at;
  if (at.off) return at.off;
  if (at.line) {
    const [s, k, t] = at.line;
    const el = seriesModel(chart, s).getData().getItemGraphicEl(k);
    const line = lineOf(partsOf(el).inner);
    const p = pointOnLine(line, t);
    return search(p[0], p[1], (x, y) => hoverTarget(chart, x, y) === line && distToLine(line, x, y) <= 0.75, where);
  }
  if (at.sym) {
    const [s, k, end] = at.sym;
    const el = seriesModel(chart, s).getData().getItemGraphicEl(k);
    const sym = partsOf(el).inner.childOfName(end === 'from' ? 'fromSymbol' : 'toSymbol');
    // a little way back along the line from the end, still inside the arrow
    const line = lineOf(partsOf(el).inner);
    const p = pointOnLine(line, end === 'from' ? 0.02 : 0.98);
    return search(p[0], p[1], (x, y) => hoverTarget(chart, x, y) === sym, where);
  }
  if (at.seg) {
    const [s, k, j, t] = at.seg;
    const el = largeEls(chart, seriesModel(chart, s))[0];
    must(el, where + ': no large element');
    const segs = el.shape.segs;
    let x0, y0, x1, y1, cx = null, cy = null;
    if (el.shape.polyline) {
      let i = 0;
      for (let n = 0; n < k; n++) i += 1 + segs[i] * 2;
      i += 1 + j * 2;
      x0 = segs[i]; y0 = segs[i + 1]; x1 = segs[i + 2]; y1 = segs[i + 3];
    }
    else {
      x0 = segs[k * 4]; y0 = segs[k * 4 + 1]; x1 = segs[k * 4 + 2]; y1 = segs[k * 4 + 3];
      const c = el.shape.curveness;
      if (c > 0) { cx = (x0 + x1) / 2 - (y0 - y1) * c; cy = (y0 + y1) / 2 - (x1 - x0) * c; }
    }
    const p = cx === null ? [x0 + (x1 - x0) * t, y0 + (y1 - y0) * t] : [quadAt(x0, cx, x1, t), quadAt(y0, cy, y1, t)];
    return [Math.round(p[0]), Math.round(p[1])];
  }
  throw new OracleError(where + ': an unknown position');
}

// =====================================================================
// steps
// =====================================================================
function roleOf(chart, t) {
  if (!t) return null;
  if (typeof t.findDataIndex === 'function' && t.shape && t.shape.segs) return 'large';
  if (isEffectSymbol(t)) return 'effect';
  if (t.name === 'line' || t.type === 'polyline') return 'line';
  if (t.name === 'fromSymbol' || t.name === 'toSymbol') return t.name;
  return 'other';
}
function hoverRec(chart, x, y) {
  const t = hoverTarget(chart, x, y);
  if (!t) return null;
  const role = roleOf(chart, t);
  let d = null;
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const q = ecData(e);
    if (q && q.seriesIndex != null) { d = q; break; }
  }
  const di = d ? d.dataIndex : null;
  return { role, seriesIndex: d ? d.seriesIndex : null, dataIndex: di == null ? null : (Number.isNaN(di) ? 'NaN' : di) };
}
function stateRec(el) {
  return { states: (el.currentStates || []).slice() };
}
function statesRec(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'lines' || sm.pipelineContext.large) return;
    const data = sm.getData();
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      const inner = partsOf(el).inner;
      const line = lineOf(inner);
      const r = { seriesIndex: sm.seriesIndex, dataIndex: i,
        line: Object.assign(stateRec(line), { stroke: colourOf(line.style.stroke), opacity: hexOr(line.style.opacity, 1),
          lineWidth: hexOr(line.style.lineWidth, 1), z2: line.z2 }),
        symbols: [], label: null };
      for (const nm of ['fromSymbol', 'toSymbol']) {
        const sym = inner.childOfName(nm);
        if (sym) r.symbols.push(Object.assign(stateRec(sym), { name: nm, fill: colourOf(sym.style.fill), opacity: hexOr(sym.style.opacity, 1) }));
      }
      const tc = inner.getTextContent && inner.getTextContent();
      if (tc) r.label = Object.assign(stateRec(tc), { opacity: hexOr(tc.style.opacity, 1) });
      out.push(r);
    }
  });
  return out;
}
const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function tooltipRows(content) {
  const text = String(content.el.style.text);
  const rich = content.el.style.rich || {};
  return text.split('\n').map(line => {
    const row = { marker: null, name: null, value: null };
    SEGMENT.lastIndex = 0;
    let m;
    while ((m = SEGMENT.exec(line))) {
      const st = rich[m[1]] || {};
      if (st.width != null) row.marker = st.width === 10 ? 'item' : 'subItem';
      else if (st.fontWeight != null && +st.fontWeight >= 700 || st.fontWeight === 'bold') row.value = m[2];
      else if (row.name === null && row.marker === null && st.align !== 'right') row.name = m[2];
      else row.value = m[2];
    }
    return row;
  });
}
function legendRec(chart) {
  const m = chart.getModel().getComponent('legend', 0);
  if (!m) return null;
  const v = chart.getViewOfComponentModel(m);
  const out = [];
  v.group.traverse(el => {
    if (el.type === 'text' && el.parent) {
      const icon = el.parent.childAt(0);
      if (icon && icon.shape && icon.shape.symbolType) {
        out.push({ name: String(el.style.text), selected: m.isSelected(String(el.style.text)),
          icon: icon.shape.symbolType, fill: colourOf(icon.style.fill),
          stroke: colourOf(icon.style.stroke), opacity: hexOr(icon.style.opacity, 1), lineWidth: hexOr(icon.style.lineWidth, 1) });
      }
    }
  });
  return out;
}

// =====================================================================
// one case
// =====================================================================
let LOG = null;
function recordCase(c) {
  NOW = T0;
  TIMERS = [];
  SHADOW.clear();
  const chart = newChart();
  const cfg = canvasLike(chart);
  try {
    const where = c.id;
    for (const t of ['mouseover', 'mousemove', 'mouseout']) {
      chart.on(t, e => {
        if (!LOG) return;
        const di = e.dataIndex;
        LOG.push({ type: t, seriesIndex: e.seriesIndex, dataIndex: di == null ? null : (Number.isNaN(di) ? 'NaN' : di),
          name: e.name == null ? null : String(e.name) });
      });
    }
    const opt = JSON.parse(JSON.stringify(c.option));
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    const zr = chart.getZr();
    zr.storage.getDisplayList(true);
    checkLayout(chart, where);
    checkLarge(chart, where);
    const record = { series: seriesRecords(chart, cfg), zlevels: zlevels(chart) };
    const legend0 = c.legend ? legendRec(chart) : null;
    let frames = null;
    if (c.samples) {
      frames = [];
      for (const t of c.samples) {
        if (t > 0) {
          NOW = T0 + t;
          zr.animation.update();
        }
        zr.storage.getDisplayList(true);
        checkEffect(chart, where + ' at ' + t);
        frames.push({ t, items: frameItems(chart) });
      }
    }
    const steps = [];
    if (c.steps.length) {
      const tv = chart.getViewOfComponentModel(chart.getModel().getComponent('tooltip', 0));
      must(tv, where + ': no tooltip view');
      const content = () => tv._tooltipContent;
      const visible = () => { const ct = content(); return !!(ct && ct.el && !ct.el.ignore && !ct.el.invisible); };
      const show = tv._showTooltipContent;
      tv._showTooltipContent = function () {
        const r = show.apply(this, arguments);
        const ct = tv._tooltipContent;
        if (ct && ct.el) ct.el.silent = true;
        return r;
      };
      chart._onframe();
      c.steps.forEach((s, i) => {
        settle(NOW + 500);
        const st = { i, t: s[0], x: null, y: null };
        LOG = [];
        if (s[0] === 'move') {
          const at = resolveAt(chart, s[1], where + ' step ' + i);
          st.x = at[0];
          st.y = at[1];
          zr.handler.mousemove(raw(at[0], at[1]));
        }
        else if (s[0] === 'leave') {
          zr.handler.mouseout(raw(-1, -1));
        }
        else if (s[0] === 'action') {
          st.payload = s[1];
          chart.dispatchAction(JSON.parse(JSON.stringify(s[1])));
        }
        chart._onframe();
        zr.storage.getDisplayList(true);
        settle(NOW + 500);
        chart._onframe();
        zr.storage.getDisplayList(true);
        st.events = LOG;
        LOG = null;
        st.hover = st.x == null ? null : hoverRec(chart, st.x, st.y);
        if (st.hover && st.hover.role === 'large') checkFind(chart, st, where + ' step ' + i);
        const vis = visible();
        st.tooltip = { shown: vis, rows: vis ? tooltipRows(content()) : null,
          text: vis ? String(content().el.style.text).replace(SEGMENT, '$2') : null };
        st.states = statesRec(chart);
        if (c.legend) st.legend = legendRec(chart);
        if (s[0] === 'action' && s[1].type === 'legendToggleSelect') st.series = seriesRecords(chart, cfg);
        steps.push(st);
      });
    }
    return { id: c.id, group: c.group, note: c.note, option: opt, record,
      legend: legend0, frames, steps };
  }
  finally {
    chart.dispose();
  }
}
function checkFind(chart, st, where) {
  const t = hoverTarget(chart, st.x, st.y);
  const di = findIndex(t, st.x, st.y);
  must(di === t.hoverDataIdx, where + ': R4 findDataIndex');
  const want = di > 0 ? 'NaN' : null;
  must(st.hover.dataIndex === want, where + ': R4 the handler\'s dataIndex ' + JSON.stringify(st.hover.dataIndex));
  RECIPES.R4++;
}
function frameItems(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'lines' || !sm.coordinateSystem || sm.pipelineContext.large) return;
    const data = sm.getData();
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      const { inner } = partsOf(el);
      const line = lineOf(inner);
      const r = { seriesIndex: sm.seriesIndex, dataIndex: i };
      if (line.type !== 'polyline') r.line = { percent: hex(line.shape.percent) };
      r.symbols = [];
      for (const nm of ['fromSymbol', 'toSymbol']) {
        const sym = inner.childOfName(nm);
        if (sym) r.symbols.push({ name: nm, x: hex(sym.x), y: hex(sym.y), rotation: hex(sym.rotation), scale: hex(sym.scaleX) });
      }
      const tc = inner.getTextContent && inner.getTextContent();
      r.label = tc ? { x: hex(tc.x), y: hex(tc.y), rotation: hex(tc.rotation || 0), anchor: anchorOf(tc), align: tc.style.align || null,
        verticalAlign: tc.style.verticalAlign || null, opacity: hexOr(tc.style.opacity, 1) } : null;
      if (sm.get(['effect', 'show'])) {
        const sym = el.childAt(0) && el.childAt(0).isGroup ? el.childAt(1) : null;
        r.effect = sym ? { present: true, x: hex(sym.x), y: hex(sym.y), rotation: hex(sym.rotation || 0),
          scaleX: hex(sym.scaleX), scaleY: hex(sym.scaleY), ignore: !!sym.ignore, t: sym.__t == null ? null : hex(sym.__t) }
          : { present: false };
      }
      else r.effect = null;
      out.push(r);
    }
  });
  return out;
}

// =====================================================================
// guards
// =====================================================================
function guards(cases) {
  const g = [];
  const get = id => { const c = cases.find(k => k.id === id); must(c, 'no case ' + id); return c; };
  const s0 = (id, s) => get(id).record.series[s || 0];
  const it = (id, s, k) => s0(id, s).items[k];
  const num = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  const G = (name, cond) => { must(cond, 'guard: ' + name); g.push(name); };
  G('a straight line has no control point', Number.isNaN(num(it('d-straight', 0, 0).shape.cpx1)));
  G('the default opacity is 0.5', num(it('d-straight', 0, 0).style.opacity) === 0.5);
  G('an explicit curveness 0 is straight', Number.isNaN(num(it('d-curve', 0, 2).shape.cpx1)));
  G("the string '0.5' curves", !Number.isNaN(num(it('d-curve', 0, 3).shape.cpx1)));
  G('the lines formula: the control point of a horizontal line is above it for a positive curveness',
    num(it('d-curve', 0, 4).shape.cpy1) < num(it('d-curve', 0, 4).shape.y1));
  G('a polyline has no symbols and no label', it('d-poly', 0, 0).symbols.length === 0 && it('d-poly', 0, 0).label === null);
  G('a symbol size of 0 keeps the series size', it('d-symbols', 0, 2).symbols.length === 1 && num(it('d-symbols', 0, 2).symbols[0].box[2]) === 20);
  G('an item string symbol is both ends', it('d-symbols', 0, 1).symbols.every(s => s.symbolType === 'triangle'));
  G('emptyCircle is stroked and filled', it('d-symbols', 0, 3).symbols[0].stroke !== null);
  G('a label without distance sits on the end point', it('d-labels', 0, 0).label.x === it('d-labels', 0, 0).shape.x2);
  G('an array item reads its coords as its value', it('d-formats', 0, 0).label.text === '10,10,40,30');
  G('the flat format: the value is 0', it('d-formats', 3, 0).label.text === '0' && it('d-formats', 1, 1).points.length === 6);
  G('the ec2 pairs: the first point names the item', it('d-formats', 2, 0).label.text === 'from');
  G('an unknown category is not drawn', !it('d-category', 0, 1).drawn && it('d-category', 0, 0).drawn);
  G('a null coordinate is not drawn', !it('d-nan', 0, 1).drawn && !it('d-nan', 0, 2).drawn && it('d-nan', 0, 3).drawn);
  G('clip: a rect on the grid', s0('d-clip', 0).clip && s0('d-clip', 0).clip.kind === 'rect' && s0('d-clip', 1).clip === null);
  G('polar: drawn, clipped to a sector', s0('d-polar').mode === 'normal' && s0('d-polar').clip && s0('d-polar').clip.kind === 'sector');
  G('calendar: drawn, not clipped', s0('d-calendar').mode === 'normal' && s0('d-calendar').clip === null);
  G('calendar: a date out of the range is not drawn', !it('d-calendar', 0, 2).drawn);
  G('no geo: nothing', s0('d-geo-missing').mode === 'none');
  G('the default effect: a circle of 3 at z2 100, period 4 s', it('e-default', 0, 0).effect.symbolType === 'circle'
    && it('e-default', 0, 0).effect.z2 === 100 && num(it('e-default', 0, 0).effect.life) === 4000 && num(it('e-default', 0, 0).effect.scaleX) === 3);
  G('the default delay is idx / count * period / 3', num(it('e-default', 0, 1).effect.delay) === 1 / 4 * 4000 / 3);
  G('a delayed effect is already at its start at T0', it('e-default', 0, 3).effect.ignore === false);
  G('constantSpeed sets the period from the length', num(it('e-speed', 0, 2).effect.life) === 125 / 80 * 1000);
  G('a numeric delay is taken as it is', num(it('e-speed', 0, 0).effect.delay) === 300);
  G('loop false: the symbol is removed', (() => { const f = get('e-noloop').frames; return f[f.length - 1].items[0].effect.present === false && f[0].items[0].effect.present; })());
  G('a trail asks the canvas for motion blur at 0.94', s0('e-trail').trail && num(s0('e-trail').trail.lastFrameAlpha) === Math.max(Math.min(0.4 / 10 + 0.9, 1), 0));
  G('a trail gets its own zlevel, the same key shares it and the later ones take the next', s0('e-trail').zlevel === 1
    && s0('e-trail-line', 0).zlevel === 1 && s0('e-trail-line', 1).zlevel === 1
    && get('e-trail-line').record.zlevels.find(z => z.type === 'legend').zlevel === 2
    && get('e-trail-line').record.zlevels.find(z => z.type === 'series' && z.index === 3).zlevel === 2);
  G('trailLength 0: no blur, zlevel 0', s0('e-trail0').trail === null && s0('e-trail0').zlevel === 0);
  G('the rect trail stretches', get('e-trail').frames.some(f => f.items.some(i => i.effect.present && num(i.effect.scaleY) !== 8)));
  G('roundTrip: __t passes 1', get('e-roundtrip').frames.some(f => f.items.some(i => i.effect.present && i.effect.t && num(i.effect.t) > 1)));
  G("an item's effect.show false still moves", it('e-item', 0, 1).effect !== null);
  G("an item's own period", num(it('e-item', 0, 0).effect.life) === 1500 && it('e-item', 0, 0).effect.symbolType === 'diamond');
  G('the enter animation starts at percent 0', num(get('a-enter').frames[0].items[0].line.percent) === 0);
  G('the enter animation ends at percent 1', num(get('a-enter').frames[get('a-enter').frames.length - 1].items[0].line.percent) === 1);
  G('a polyline does not animate in', it('a-poly', 0, 0).kind === 'polyline');
  G('large: one path per series', s0('l-straight').mode === 'large' && s0('l-straight').els.length === 1);
  G('large: no startIndex outside progressive', s0('l-straight').els[0].startIndex === null);
  G('large: row 0 hovered without data', (() => { const h = get('l-straight').steps[0].hover; return h && h.role === 'large' && h.dataIndex === null; })());
  G('large: a later row has a NaN dataIndex', get('l-straight').steps[1].hover.dataIndex === 'NaN');
  G('large: a NaN row fires events with a NaN dataIndex', get('l-straight').steps[1].events.some(e => e.dataIndex === 'NaN'));
  G('large under its threshold is normal', s0('l-under').mode === 'normal' && s0('l-default').mode === 'normal');
  G('a hover lifts the stroke and the z2', (() => { const s = get('h-basic').steps[0].states.find(r => r.seriesIndex === 0 && r.dataIndex === 0); return s.line.states.indexOf('emphasis') >= 0 && s.line.z2 === 10; })());
  G("a named series lends its name to an unnamed item's tooltip", get('h-basic').steps[1].tooltip.rows[0].name === 'A');
  G('an unnamed series: the tooltip names a link from > to', get('h-names').steps[1].tooltip.rows[0].name === 'X > Y'
    && get('h-names').steps[2].tooltip.rows[0].name === 'Z');
  G('an array item has no value in its tooltip', get('h-basic').steps[3].tooltip.shown);
  G("focus 'series' blurs the other series", get('h-focus').steps[0].states.filter(r => r.seriesIndex === 1).every(r => r.line.states.indexOf('blur') >= 0));
  G('the legend icon is a roundRect in the stroke colour', get('h-legend').legend[0].icon === 'roundRect');
  return g;
}

function generate() {
  const cases = CASES.map(recordCase);
  if (process.env.C12_DUMP) fs.writeFileSync(process.env.C12_DUMP, JSON.stringify(cases, null, 1));
  const gs = guards(cases);
  for (const k of Object.keys(RECIPES)) must(RECIPES[k] > 0, 'recipe ' + k + ' never ran');
  const out = {
    source: 'ECharts ' + echarts.version + ' dist (' + path.basename(DIST) + ') under node, svg painter answering getType canvas, ssr init then _ssr = false, env.node = false',
    W, H, T0, seed: SEED,
    notes: [
      'The clock is reset to T0 per case; setOption steps every clip once at T0 (sample 0); a later sample is T0 + t, one zr.animation.update(), getDisplayList(true).',
      'hover is handler.findHover after the event; dataIndex NaN is the string NaN.',
      'trail is the zr.configLayer the canvas branch of LinesView asks for its zlevel; the motion blur itself is not recorded.',
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
