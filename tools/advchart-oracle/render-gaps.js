// Round 7 R7-G: the four picture differences R7-C's hit oracle stepped round
// (tools/advchart-oracle/hit-stroke.js), each as the real ECharts 6.1 dist
// draws it.
//
//   subpixel  every displayable built with `subPixelOptimize: true` (zrender's
//             Line / Rect run subPixelOptimizeLine / subPixelOptimizeRect on
//             their shape in buildPath, with style.lineWidth, in their own
//             frame): ECLinePath of chart/helper/Line.ts (a lines series' line,
//             a graph's edge -- under the view's roam transform -- a markLine),
//             the cartesian axis pointer's line, a title's background rect.
//             Each: its type, its lineWidth, the calls buildPath makes (hex),
//             its global transform (hex, null for none) and the path's points
//             taken through it (hex); a rect its own shape as well. A graphic component's
//             `subPixelOptimize: true` is not carried onto its element (no
//             record: the guard says so).
//   pictorial a pictorial bar's itemStyle.borderWidth in the layout
//             (PictorialBarView prepareLineWidth: valueLineWidth, the border
//             over the glyph's line scale, signed by the glyph's scale along
//             the value axis; prepareLayoutInfo's unit length and
//             createOrUpdateRepeatSymbols' unit). Per item: valueLineWidth,
//             the repeat count, every glyph's global transform and the bar
//             rect (hex).
//   inset     a bar's getLineWidth: the border is taken out of the layout when
//             itemModel.get(['itemStyle', 'borderColor']) is truthy and not
//             'none' -- 'transparent', 'rgba(0,0,0,0)', a word the canvas does
//             not know, an object, a number other than 0 -- whatever the pen
//             draws. A polar bar's layout never is. Per item: the shape (hex),
//             null where the item has no element.
//   frames    a line's enter animation (shape.percent, linear over 1000 ms)
//             sampled at 300 and 700 ms on a replaced clock
//             (zr.animation.update()): each ec-line's percent, lineWidth and
//             the buildPath points through its transform -- the snap is
//             before the percent, every frame.
//   axishit   what zrender's findHover finds on each part of an axis
//             (AxisBuilder: line and ticks silent, labels and name
//             isLabelSilent -- silent, or neither triggerEvent nor
//             tooltip.show; AngleAxisView: its ticks and minor ticks not
//             silent; split lines and areas silent; a radar's indicator
//             model has no parent, so only triggerEvent wakes its names; a
//             gauge's furniture all silent). Probes: every displayable an
//             axis view (or a gauge view) draws, at a point on it (a text's
//             global rect's centre; a path's first segment's midpoint, an
//             arc's middle, a rect's centre), rounded to whole pixels --
//             dropped (`ties` counts them) where findHover a tenth of a
//             pixel round the point does not agree, an edge the rounding
//             decides (a whole pixel round a silent part, whose answer is
//             the series' hit under it); at each, findHover's target
//             written as
//               sS/D    the ECData the dispatcher walk finds: a series' datum
//               e:T     an eventData of targetType T (triggerEvent)
//               x       a target with neither
//               -       none
//             and the target's cursor.
//
// SSR svg, chart._ssr = false, animation off, a fixed clock and seed. Two
// generations must be byte-identical.
//   node tools/advchart-oracle/render-gaps.js -> tests/fixtures/advchart-render-gaps.json
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
global.Date = ClockDate;
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-render-gaps.json');
echarts.env.node = false;
const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};
class OracleError extends Error {}
function must(c, m) { if (!c) throw new OracleError(m); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const W = 400;
const H = 300;
const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666'];
const N = ['A', 'B', 'C'];

function chartOf(option) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  chart.setOption(JSON.parse(JSON.stringify(option)));
  chart.getZr().storage.getDisplayList(true);
  return chart;
}
// buildPath against a context that writes the calls down
function callsOf(el) {
  const calls = [];
  const ctx = {};
  ['moveTo', 'lineTo', 'bezierCurveTo', 'quadraticCurveTo', 'arc', 'arcTo', 'rect', 'ellipse', 'closePath']
    .forEach(k => { ctx[k] = (...a) => { calls.push([k].concat(a)); }; });
  el.buildPath(ctx, el.shape, false);
  // a merged path (graphic.mergePath) builds only into a PathProxy: its data
  // replayed (float32: a probe's point, never a compared value)
  if (!calls.length && el.getBoundingRect) {
    el.getBoundingRect();
    if (el.path) el.path.rebuildPath(ctx, 1);
  }
  return calls;
}
function globalM(el) {
  el.updateTransform && el.updateTransform();
  const m = el.getComputedTransform ? el.getComputedTransform() : el.transform;
  return m ? Array.from(m) : null;
}
const apply = (m, x, y) => (m ? [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]] : [x, y]);

// ==================== subpixel ====================
const vv = (s, more) => Object.assign({ animation: false, color: PAL, xAxis: { type: 'value', min: 0, max: 10 },
  yAxis: { type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const lines = (coords, ls, more) => vv(Object.assign({ type: 'lines', coordinateSystem: 'cartesian2d',
  lineStyle: Object.assign({ opacity: 1 }, ls || {}), data: coords.map(c => ({ coords: c })) }, more || {}));
const GN = [{ name: 'a', x: 100, y: 150 }, { name: 'b', x: 300, y: 150 }, { name: 'c', x: 300, y: 60 },
  { name: 'd', x: 160, y: 61.3 }];
const GL = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' }];
const graph = (more, ls) => ({ animation: false, color: PAL, series: [Object.assign({ type: 'graph', layout: 'none',
  symbolSize: 10, data: GN, links: GL, lineStyle: Object.assign({ opacity: 1 }, ls || {}) }, more || {})] });

function subpixelCases() {
  return [
    ['lines.h1', lines([[[1, 5.03], [9, 5.03]]], { width: 1 })],
    ['lines.v2', lines([[[4.03, 1], [4.03, 9]]], { width: 2 })],
    ['lines.h3', lines([[[1, 6.11], [9, 6.11]]], { width: 3 })],
    // nearly level: round(2 y) the same at both ends, so both ends go to the first's half pixel
    ['lines.near', lines([[[1, 5.03], [9, 5.035]]], { width: 1 })],
    ['lines.w05', lines([[[1, 5.03], [9, 5.03]]], { width: 0.5 })],
    ['lines.diag', lines([[[1, 2.03], [9, 8.11]]], { width: 1 })],
    ['lines.two', lines([[[1, 5.03], [9, 5.03]], [[2.07, 1], [2.07, 9]]], { width: 1 })],
    ['graph.view', graph()],
    ['graph.zoom', graph({ zoom: 1.6 })],
    ['graph.zoom-w3', graph({ zoom: 1.3, center: [190, 110] }, { width: 3 })],
    ['graph.cartesian', vv({ type: 'graph', coordinateSystem: 'cartesian2d', symbolSize: 10,
      data: [[1, 5.03], [9, 5.03], [9, 2]], links: [{ source: 0, target: 1 }, { source: 1, target: 2 }],
      lineStyle: { opacity: 1 } })],
    ['graph.curved', graph({}, { curveness: 0.2 })],
    // the pointer's line at the mouse (a value axis) and at a band's centre (142.33, width 3)
    ['pointer.value', vv({ type: 'line', data: [[1, 2], [3, 4]] }, { tooltip: { trigger: 'axis', showContent: false,
      axisPointer: { lineStyle: { type: 'solid' } } } }), [150, 100]],
    ['pointer.band-w3', Object.assign(vv({ type: 'bar', data: [1, 2, 3] }, { tooltip: { trigger: 'axis',
      showContent: false, axisPointer: { lineStyle: { type: 'solid', width: 3 } } } }),
    { yAxis: { type: 'category', data: N } }), [150, 133]],
    ['title.left', { animation: false, title: { text: 'Hi', left: 10.3, top: 7.2, borderWidth: 1, borderColor: '#000' } }],
    ['title.centre', { animation: false, title: { text: 'Title', subtext: 'sub', left: 'center', top: 20,
      borderWidth: 1, borderColor: '#000', backgroundColor: '#eee' } }],
    ['title.right-b2', { animation: false, title: { text: 'Hi', right: 13.7, top: 31.4, textAlign: 'right',
      textVerticalAlign: 'bottom', borderWidth: 2, borderColor: '#000', padding: [3.3, 4, 5, 6.25] } }],
    ['title.b0', { animation: false, title: { text: 'Hi', left: 10.3, top: 7.2, backgroundColor: '#eee' } }],
    ['graphic.line', { animation: false, graphic: [{ type: 'line', subPixelOptimize: true,
      shape: { x1: 10, y1: 20.2, x2: 100, y2: 20.2 }, style: { stroke: '#000', lineWidth: 1 } }] }],
  ];
}
function subpixelRun(id, option, move) {
  const chart = chartOf(option);
  try {
    if (move) {
      chart.getZr().handler.dispatch('mousemove', { zrX: move[0], zrY: move[1] });
      chart.getZr().storage.getDisplayList(true);
    }
    const els = [];
    chart.getZr().storage.getDisplayList(true).forEach(el => {
      if (!el.subPixelOptimize) return;
      const calls = callsOf(el);
      const m = globalM(el);
      const pts = [];
      calls.forEach(c => {
        if (c[0] === 'moveTo' || c[0] === 'lineTo') pts.push(apply(m, c[1], c[2]));
        else if (c[0] === 'rect') {
          pts.push(apply(m, c[1], c[2]));
          pts.push(apply(m, c[1] + c[3], c[2] + c[4]));
        }
      });
      const rec = { type: el.type, lw: hex(el.style.lineWidth), silent: !!el.silent,
        calls: calls.map(c => [c[0]].concat(c.slice(1).map(v => (typeof v === 'number' ? hex(v) : v)))),
        m: m ? m.map(hex) : null, pts: pts.map(p => [hex(p[0]), hex(p[1])]) };
      // a rect's own shape, before buildPath optimised it
      if (el.type === 'rect') rec.shape = [el.shape.x, el.shape.y, el.shape.width, el.shape.height].map(hex);
      els.push(rec);
    });
    const rec = { id, option, els };
    if (move) rec.move = move;
    return rec;
  }
  finally {
    chart.dispose();
  }
}

// ==================== frames ====================
// a line's enter (shape.percent from 0, linear over 1000 ms): every frame
// is built with the snap, before the percent
const anim = o => Object.assign({}, o, { animation: true, animationDuration: 1000, animationEasing: 'linear',
  animationDurationUpdate: 1000 });
function frameCases() {
  return [
    ['frame.graph-zoom', anim(graph({ zoom: 1.6 }))],
    ['frame.graph-cartesian', anim(vv({ type: 'graph', coordinateSystem: 'cartesian2d', symbolSize: 10,
      data: [[1, 5.03], [9, 5.03], [9, 2]], links: [{ source: 0, target: 1 }, { source: 1, target: 2 }],
      lineStyle: { opacity: 1 } }))],
    ['frame.lines', anim(lines([[[1, 5.03], [9, 5.03]], [[4.03, 1], [4.03, 9]]], { width: 1 }))],
  ];
}
const FRAME_T = [300, 700];
function frameRun(id, option) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    chart.getZr().storage.getDisplayList(true);
    const samples = FRAME_T.map(t => {
      NOW = T_BASE + t;
      chart.getZr().animation.update();
      const els = [];
      chart.getZr().storage.getDisplayList(true).forEach(el => {
        if (el.type !== 'ec-line') return;
        const calls = callsOf(el);
        const m = globalM(el);
        const pts = [];
        calls.forEach(c => { if (c[0] === 'moveTo' || c[0] === 'lineTo') pts.push(apply(m, c[1], c[2])); });
        els.push({ percent: hex(el.shape.percent), lw: hex(el.style.lineWidth),
          straight: calls.length === 2 && calls[1][0] === 'lineTo', pts: pts.map(p => [hex(p[0]), hex(p[1])]) });
      });
      return { t, els };
    });
    return { id, option, T0: T_BASE, samples };
  }
  finally {
    chart.dispose();
  }
}

// ==================== pictorial ====================
const cart = (s, more) => Object.assign({ animation: false, color: PAL, xAxis: { type: 'category', data: N },
  yAxis: { type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const hcart = (s, more) => Object.assign({ animation: false, color: PAL, yAxis: { type: 'category', data: N },
  xAxis: { type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const B = (w, more) => Object.assign({ borderColor: '#000', borderWidth: w }, more || {});
const pict = (more, is) => Object.assign({ type: 'pictorialBar', symbol: 'rect', symbolSize: [40, 30],
  data: [4, 6, 8], itemStyle: is === undefined ? B(10) : is }, more || {});
function pictorialCases() {
  return [
    ['pict.start', cart(pict())],
    ['pict.end', cart(pict({ symbolPosition: 'end' }))],
    ['pict.center', cart(pict({ symbolPosition: 'center' }))],
    ['pict.tall', cart(pict({ symbolSize: [20, 45] }))],
    ['pict.no-colour', cart(pict({}, { borderWidth: 10 }))],
    ['pict.percent', cart(pict({ symbolSize: '100%', barWidth: 40 }))],
    ['pict.negative', Object.assign(cart(pict({ data: [-4, 6, -8] })), { yAxis: { type: 'value', min: -10, max: 10 } })],
    ['pict.inverse', Object.assign(cart(pict()), { yAxis: { type: 'value', min: 0, max: 10, inverse: true } })],
    ['pict.horizontal', hcart(pict({ symbolPosition: 'end' }))],
    ['pict.horizontal-neg', Object.assign(hcart(pict({ data: [-4, 6, -8] })), { xAxis: { type: 'value', min: -10, max: 10 } })],
    ['pict.rotate', cart(pict({ symbolRotate: 30, symbolPosition: 'end' }))],
    ['pict.repeat', cart(pict({ symbolSize: [20, 10], symbolRepeat: true }, B(6)))],
    ['pict.repeat-fixed', cart(pict({ symbolSize: [20, 12], symbolRepeat: 'fixed', symbolMargin: '20%!' }, B(4)))],
    ['pict.repeat-count', cart(pict({ symbolSize: [20, 12], symbolRepeat: 3, symbolPosition: 'end' }, B(4)))],
    ['pict.repeat-clip', cart(pict({ symbolSize: [24, 8], symbolRepeat: true, symbolClip: true,
      symbolBoundingData: 10 }, B(5)))],
    ['pict.repeat-horizontal', hcart(pict({ symbolSize: [10, 20], symbolRepeat: true }, B(3)))],
    ['pict.item-border', cart(pict({ data: [4, { value: 6, itemStyle: { borderWidth: 16 } }, 8] }))],
    ['pict.pattern-size', cart(pict({ symbolPatternSize: 40 }))],
    ['pict.unit-scale', cart(pict({ symbolSize: [400, 400], symbolPatternSize: 400, symbolPosition: 'end' }, B(7)))],
    // one scale exactly 1: getLineScale answers 1 (both diagonal terms must be off 1)
    ['pict.one-unit-axis', cart(pict({ symbolSize: [400, 200], symbolPatternSize: 400, symbolPosition: 'end' }, B(7)))],
    // both scales within 5e-5 of 1: no transform at all (needLocalTransform)
    // ... and turned a quarter: the turn moves the diagonal off 1, so the line scale is the determinant's
    ['pict.one-unit-turned', cart(pict({ symbolSize: [400, 200], symbolPatternSize: 400, symbolPosition: 'end',
      symbolRotate: 90 }, B(7)))],
    ['pict.near-unit', cart(pict({ symbolSize: [400.004, 400.008], symbolPatternSize: 400, symbolPosition: 'end' }, B(7)))],
  ];
}
function pictorialRun(id, option) {
  const chart = chartOf(option);
  try {
    const data = chart.getModel().getSeriesByIndex(0).getData();
    const items = [];
    for (let i = 0; i < data.count(); i++) {
      const bar = data.getItemGraphicEl(i);
      if (!bar) { items.push(null); continue; }
      const meta = bar.__pictorialSymbolMeta;
      const glyphs = [];
      bar.__pictorialBundle.eachChild(p => { glyphs.push(globalM(p).map(hex)); });
      const r = bar.__pictorialBarRect.shape;
      items.push({ vlw: hex(meta.valueLineWidth), repeat: meta.repeatTimes == null ? null : meta.repeatTimes,
        glyphs, rect: [hex(r.x), hex(r.y), hex(r.width), hex(r.height)] });
    }
    return { id, option, items };
  }
  finally {
    chart.dispose();
  }
}

// ==================== inset ====================
const bar = (is, more) => cart(Object.assign({ type: 'bar', data: [4, 6, 8], barWidth: 60, itemStyle: is }, more || {}));
const grad = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
  colorStops: [{ offset: 0, color: 'rgba(0,0,0,0)' }, { offset: 1, color: '#000' }] };
const polar = (is, more) => Object.assign({ animation: false, color: PAL, polar: { radius: [30, 120] },
  angleAxis: { max: 10 }, radiusAxis: { type: 'category', data: N },
  series: [Object.assign({ type: 'bar', coordinateSystem: 'polar', data: [4, 6, 8], itemStyle: is }, more || {})] });
function insetCases() {
  return [
    ['bar.transparent', bar({ borderColor: 'transparent', borderWidth: 12 })],
    ['bar.rgba0', bar({ borderColor: 'rgba(0,0,0,0)', borderWidth: 12 })],
    ['bar.hsla0', bar({ borderColor: 'hsla(0,0%,0%,0)', borderWidth: 8 })],
    ['bar.word', bar({ borderColor: 'nosuchcolour', borderWidth: 12 })],
    ['bar.grad', bar({ borderColor: grad, borderWidth: 12 })],
    ['bar.number', bar({ borderColor: 1, borderWidth: 12 })],
    ['bar.zero', bar({ borderColor: 0, borderWidth: 12 })],
    ['bar.empty', bar({ borderColor: '', borderWidth: 12 })],
    ['bar.none', bar({ borderColor: 'none', borderWidth: 12 })],
    ['bar.none-upper', bar({ borderColor: 'NONE', borderWidth: 12 })],
    ['bar.black', bar({ borderColor: '#000', borderWidth: 12 })],
    ['bar.no-colour', bar({ borderWidth: 12 })],
    ['bar.item-transparent', bar({ borderColor: 'none', borderWidth: 12 },
      { data: [4, { value: 6, itemStyle: { borderColor: 'transparent' } }, 8] })],
    ['bar.item-none', bar({ borderColor: '#000', borderWidth: 12 },
      { data: [4, { value: 6, itemStyle: { borderColor: 'none' } }, 8] })],
    ['bar.item-null', bar({ borderColor: 'transparent', borderWidth: 12 },
      { data: [4, { value: 6, itemStyle: { borderColor: null } }, 8] })],
    ['bar.item-empty', bar({ borderColor: 'transparent', borderWidth: 12 },
      { data: [4, { value: 6, itemStyle: { borderColor: '' } }, 8] })],
    ['bar.item-grad', bar({ borderWidth: 12 }, { data: [4, { value: 6, itemStyle: { borderColor: grad } }, 8] })],
    ['bar.item-zero', bar({ borderColor: 'transparent', borderWidth: 12 },
      { data: [4, { value: 6, itemStyle: { borderColor: 0 } }, 8] })],
    ['bar.item-one', bar({ borderColor: 'none', borderWidth: 12 },
      { data: [4, { value: 6, itemStyle: { borderColor: 1 } }, 8] })],
    ['bar.item-width', bar({ borderColor: 'transparent' }, { data: [4, { value: 6, itemStyle: { borderWidth: 9 } }, 8] })],
    ['bar.nan-transparent', bar({ borderColor: 'transparent', borderWidth: 'abc' })],
    ['bar.horizontal', Object.assign(bar({ borderColor: 'transparent', borderWidth: 12 }),
      { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'category', data: N } })],
    ['polar.transparent', polar({ borderColor: 'transparent', borderWidth: 12 })],
    ['polar.black', polar({ borderColor: '#000', borderWidth: 12 })],
  ];
}
function insetRun(id, option) {
  const chart = chartOf(option);
  try {
    const data = chart.getModel().getSeriesByIndex(0).getData();
    const items = [];
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) { items.push(null); continue; }
      const s = el.shape;
      if (el.type === 'rect') items.push({ kind: 'rect', v: [s.x, s.y, s.width, s.height].map(hex) });
      else items.push({ kind: 'sector', v: [s.cx, s.cy, s.r0, s.r, s.startAngle, s.endAngle].map(hex) });
    }
    return { id, option, items };
  }
  finally {
    chart.dispose();
  }
}

// ==================== axishit ====================
let ecKey = null;
const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
function ecDataOf(el) {
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (v && typeof v === 'object' && !Array.isArray(v) && hasOwn(v, 'seriesIndex') && hasOwn(v, 'dataIndex')) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
function codeOf(t) {
  if (!t) return '-';
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const d = ecDataOf(e);
    if (d && d.dataIndex != null) return 's' + d.seriesIndex + '/' + d.dataIndex;
    if (d && d.eventData) return 'e:' + d.eventData.targetType;
  }
  return 'x';
}
function probeOf(el) {
  const m = globalM(el);
  if (el.type === 'text' || el.type === 'tspan') {
    const r = el.getBoundingRect().clone();
    if (m) r.applyTransform(m);
    return [r.x + r.width / 2, r.y + r.height / 2];
  }
  if (!el.buildPath) return null;
  const calls = callsOf(el);
  if (!calls.length) return null;
  const c0 = calls[0];
  let p;
  if (c0[0] === 'moveTo' && calls[1] && calls[1][0] === 'lineTo') p = [(c0[1] + calls[1][1]) / 2, (c0[2] + calls[1][2]) / 2];
  else if (c0[0] === 'arc' || (c0[0] === 'moveTo' && calls[1] && calls[1][0] === 'arc')) {
    const a = c0[0] === 'arc' ? c0 : calls[1];
    const t = (a[4] + a[5]) / 2;
    p = [a[1] + a[3] * Math.cos(t), a[2] + a[3] * Math.sin(t)];
  }
  else if (c0[0] === 'rect') p = [c0[1] + c0[3] / 2, c0[2] + c0[4] / 2];
  else {
    const r = el.getBoundingRect();
    p = [r.x + r.width / 2, r.y + r.height / 2];
  }
  return apply(m, p[0], p[1]);
}
 // 1.5 px off the middle of a path's first segment, square to it (inside
// strokeContainThreshold's 2.5, outside half a width of 1)
function offProbe(el) {
  const calls = callsOf(el);
  if (calls.length < 2 || calls[0][0] !== 'moveTo' || calls[1][0] !== 'lineTo') return null;
  const x0 = calls[0][1], y0 = calls[0][2], x1 = calls[1][1], y1 = calls[1][2];
  const len = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
  if (!(len > 0)) return null;
  const m = globalM(el);
  return apply(m, (x0 + x1) / 2 - (y1 - y0) / len * 1.5, (y0 + y1) / 2 + (x1 - x0) / len * 1.5);
}
const AXIS_TYPES = ['xAxis', 'yAxis', 'singleAxis', 'angleAxis', 'radiusAxis', 'parallelAxis', 'radar'];
function axishitCases() {
  const tr = { type: 'themeRiver', label: { show: false }, data: [[0, 3, 'a'], [1, 4, 'a'], [2, 3, 'a'],
    [0, 2, 'b'], [1, 2, 'b'], [2, 3, 'b']] };
  const pol = (aa, ra) => ({ animation: false, color: PAL, polar: { radius: [20, 100] },
    angleAxis: Object.assign({ type: 'category', data: N, minorTick: { show: true } }, aa || {}),
    radiusAxis: Object.assign({ max: 10, name: 'r' }, ra || {}),
    series: [{ type: 'bar', coordinateSystem: 'polar', data: [4, 6, 8] }] });
  const par = more => ({ animation: false, color: PAL,
    parallelAxis: [Object.assign({ dim: 0, name: 'p', min: 0, max: 10 }, more || {}),
      Object.assign({ dim: 1, name: 'q', type: 'category', data: N }, more || {})],
    series: [{ type: 'parallel', data: [[5, 'A'], [2, 'B']] }] });
  const rad = more => ({ animation: false, color: PAL, radar: Object.assign({ indicator: [{ name: 'p', max: 10 },
    { name: 'q', max: 10 }, { name: 'r', max: 10 }], radius: 80, axisLabel: { show: true },
    axisTick: { show: true } }, more || {}), series: [{ type: 'radar', areaStyle: {}, data: [{ value: [8, 6, 7] }] }] });
  const ca = (xa, ya) => cart({ type: 'bar', data: [4, 6, 8] }, {
    xAxis: Object.assign({ type: 'category', data: N, name: 'cat', axisTick: { show: true },
      minorTick: { show: false }, splitArea: { show: true } }, xa || {}),
    yAxis: Object.assign({ type: 'value', min: 0, max: 10, name: 'val', minorTick: { show: true },
      minorSplitLine: { show: true } }, ya || {}) });
  return [
    ['cart.default', ca()],
    ['cart.trigger', ca({ triggerEvent: true }, { triggerEvent: true })],
    ['cart.tooltip', ca({ tooltip: { show: true } }, { tooltip: { show: true } })],
    ['cart.silent', ca({ triggerEvent: true, silent: true }, { tooltip: { show: true }, silent: true })],
    // a scatter under the x axis' labels (z -1): a label that is not silent covers it
    ['cart.under', cart({ type: 'scatter', z: -1, symbolSize: 200, data: [[1, 0]] },
      { xAxis: { type: 'category', data: N, tooltip: { show: true } } })],
    ['single.default', solo(tr, { singleAxis: { type: 'value', min: 0, max: 2, name: 's', top: 40, bottom: 60 } })],
    ['single.trigger', solo(tr, { singleAxis: { type: 'value', min: 0, max: 2, name: 's', top: 40, bottom: 60,
      triggerEvent: true } })],
    ['single.silent', solo(tr, { singleAxis: { type: 'value', min: 0, max: 2, name: 's', top: 40, bottom: 60,
      silent: true } })],
    ['single.no-tooltip', solo(tr, { singleAxis: { type: 'value', min: 0, max: 2, name: 's', top: 40, bottom: 60,
      tooltip: { show: false } } })],
    ['polar.default', pol()],
    ['polar.trigger', pol({ triggerEvent: true }, { triggerEvent: true })],
    ['polar.silent', pol({ silent: true }, { silent: true, tooltip: { show: true } })],
    // a series at the axis' own z (0) over an angle label: a tie, the series drawn later wins
    ['polar.tie', Object.assign(pol({ triggerEvent: true }), { series: [{ type: 'bar', coordinateSystem: 'polar',
      data: [4, 6, 8] }, { type: 'scatter', coordinateSystem: 'polar', z: 0, symbolSize: 80, data: [[10, 'A']] }] })],
    // a bar at z 0, z2 0 under an angle axis' inward ticks (z 0, z2 0): the tie goes to the bar
    ['polar.tie-tick', { animation: false, color: PAL, polar: { radius: [20, 100] },
      angleAxis: { type: 'value', max: 10, axisTick: { inside: true } }, radiusAxis: { type: 'category', data: ['A'] },
      series: [{ type: 'bar', coordinateSystem: 'polar', z: 0, barCategoryGap: '0%', data: [10] }] }],
    ['parallel.default', par()],
    ['parallel.trigger', par({ triggerEvent: true })],
    ['radar.default', rad()],
    ['radar.trigger', rad({ triggerEvent: true })],
    ['gauge.default', solo({ type: 'gauge', data: [{ value: 40, name: 'g' }], detail: { show: true } })],
  ];
}
function solo(s, more) {
  return Object.assign({ animation: false, color: PAL, series: Array.isArray(s) ? s : [s] }, more || {});
}
function axishitRun(id, option) {
  const chart = chartOf(option);
  try {
    const owner = new Map();
    chart._componentsViews.forEach(v => {
      const m = v.__model;
      if (m && AXIS_TYPES.indexOf(m.mainType) >= 0) owner.set(v.group, m.mainType + m.componentIndex);
    });
    chart._chartsViews.forEach(v => {
      const m = v.__model;
      if (m && m.subType === 'gauge') owner.set(v.group, 'gauge' + m.componentIndex);
    });
    const handler = chart.getZr().handler;
    const probes = [];
    const seen = new Set();
    const perPart = new Map();
    let n0 = 0;
    chart.getZr().storage.getDisplayList(true).forEach(el => {
      let own = null;
      for (let g = el; g && !own; g = g.parent) own = owner.get(g) || null;
      if (!own) return;
      // a gauge's own items (its pointer, its progress, its anchor) are data
      const d = ecDataOf(el);
      if (own.startsWith('gauge') && d && d.dataIndex != null) return;
      const p = probeOf(el);
      if (!p || !isFinite(p[0]) || !isFinite(p[1])) return;
      const x = Math.round(p[0]);
      const y = Math.round(p[1]);
      if (x < 0 || y < 0 || x >= W || y >= H) return;
      const key = x + ',' + y;
      if (seen.has(key)) return;
      seen.add(key);
      const part = el.type + (el.anid ? ':' + String(el.anid).replace(/_.*$/, '') : '') + (el.silent ? ' silent' : '');
      // three probes of a kind of part of one owner are enough
      const n = (perPart.get(own + ' ' + part) || 0) + 1;
      perPart.set(own + ' ' + part, n);
      if (n > 3) return;
      const t = handler.findHover(x, y).target;
      const code = codeOf(t);
      // a point on an edge is a tie the rounding decides (a sector's inner
      // radius exactly): kept only where a tenth of a pixel round it agrees
      // (an angle axis' ticks answer within half their width: a merged path
      // keeps the default fill, so no strokeContainThreshold)
      // A silent part answers with what is under it, a series' hit test
      // this fixture is not about: kept only a whole pixel off any edge.
      const off = el.silent ? 1 : 0.1;
      if (![[-off, -off], [off, -off], [-off, off], [off, off]].every(o =>
        codeOf(handler.findHover(x + o[0], y + o[1]).target) === code)) { n0++; return; }
      probes.push({ own, part, x, y, code, cursor: t ? (t.cursor || '') : '' });
      // a path that answers, 1.5 px off its line too (an angle axis' ticks:
      // half their width, not strokeContainThreshold)
      if (!el.silent && el.type !== 'text' && el.type !== 'tspan') {
        const off = offProbe(el);
        if (off) {
          const ox = Math.round(off[0]);
          const oy = Math.round(off[1]);
          const tc = codeOf(handler.findHover(ox, oy).target);
          if ([[-0.1, -0.1], [0.1, -0.1], [-0.1, 0.1], [0.1, 0.1]].every(o =>
            codeOf(handler.findHover(ox + o[0], oy + o[1]).target) === tc)) {
            const t2 = handler.findHover(ox, oy).target;
            probes.push({ own, part: part + ' off', x: ox, y: oy, code: tc, cursor: t2 ? (t2.cursor || '') : '' });
          }
        }
      }
    });
    return { id, option, probes, ties: n0 };
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const subpixel = subpixelCases().map(([id, o, mv]) => subpixelRun(id, o, mv));
  const pictorial = pictorialCases().map(([id, o]) => pictorialRun(id, o));
  const inset = insetCases().map(([id, o]) => insetRun(id, o));
  const axishit = axishitCases().map(([id, o]) => axishitRun(id, o));
  const frames = frameCases().map(([id, o]) => frameRun(id, o));
  // every frame sample is part way through (a percent strictly between 0 and 1)
  frames.forEach(c => c.samples.forEach(sm => sm.els.forEach(e => {
    bits.setUint32(0, parseInt(e.percent.slice(0, 8), 16)); bits.setUint32(4, parseInt(e.percent.slice(8), 16));
    const p = bits.getFloat64(0);
    must(p > 0 && p < 1, c.id + ' t=' + sm.t + ': percent ' + p);
  })));
  const sp = id => subpixel.find(c => c.id === id);
  // guards: the graphic component does not carry subPixelOptimize; every other case has its elements
  must(sp('graphic.line').els.length === 0, 'graphic.line: ' + sp('graphic.line').els.length);
  subpixel.forEach(c => { if (c.id !== 'graphic.line' && c.id !== 'title.b0') must(c.els.length > 0, c.id + ': none'); });
  must(sp('title.b0').els.length === 1, 'title.b0');
  // a single axis' labels answer by default, a cartesian one's do not
  const ah = id => axishit.find(c => c.id === id);
  must(ah('single.default').probes.some(p => p.code === 'x'), 'single.default: no x');
  must(!ah('cart.default').probes.some(p => p.code === 'x' || p.code.startsWith('e:')), 'cart.default: a target');
  must(ah('polar.default').probes.some(p => p.code === 'x'), 'polar.default: no x');
  must(ah('cart.under').probes.some(p => p.code === 'x'), 'cart.under: no x');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-G: subpixel (elements built with subPixelOptimize: buildPath calls, global transform, points through it), '
      + 'pictorial (valueLineWidth, repeat, glyph transforms, bar rect), inset (bar shapes by getLineWidth), axishit '
      + '(findHover on every axis part: sS/D, e:targetType, x, -; and the cursor). Doubles as IEEE-754 hex.',
    W, H, subpixel, pictorial, inset, axishit, frames };
}

let j1, j2;
try {
  j1 = JSON.stringify(generate(), null, 1) + '\n';
  j2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (j1 !== j2) { console.log('FAILED: two generations differ'); process.exit(1); }
fs.writeFileSync(OUT, j1);
console.log('wrote', OUT, j1.length, 'bytes');
process.exit(0);
