// Round 7 R7-P: THE PEN UNDER AN UNEQUAL TRANSFORM. The canvas strokes a path
// in the space its transform maps, so where the transform scales x and y
// unequally (or skews) the pen is stretched with the shape: an elliptical pen,
// its dash measured along the path in that space. zrender's brushPath sets
// ctx.lineWidth = lineWidth / getLineScale() for a strokeNoScale path
// (getLineScale: the square root of |det| of the element's global transform,
// one where either diagonal entry is one) and divides the dash and its phase
// by the same (canvas/dashStyle.ts getLineDash) -- but the transform it sets
// (setContextTransform) is the whole of it, so the pen the canvas draws is
// that transform's linear part times a round pen of that width.
//
// From the real ECharts 6.1 dist, RENDERED BY ZRENDER'S CANVAS PAINTER on a
// recording context (echarts.init on a stand-in canvas, renderer 'canvas',
// devicePixelRatio 1, animation off, then zr.refreshImmediately()): at every
// ctx.stroke() the context's transform, lineWidth, dash and phase as zrender
// set them, and the element being brushed (Displayable.innerBeforeBrush) --
// its stroke colour, the centre of its global box, whether it is
// strokeNoScale and its line scale. Every case writes each element its own
// stroke colour, so a reader finds an element by its colour (and the nearest
// centre among those that share one).
//
// Per stroke:
//   col   ctx.strokeStyle (a string)
//   cx,cy the centre of the element's own box (getBoundingRect) through its
//         global transform, hex
//   m     the context's transform when it stroked [a, b, c, d] (the linear
//         part; dpr 1), hex
//   lw    ctx.lineWidth, hex
//   dash  ctx's dash ([] solid), hex
//   off   ctx.lineDashOffset, hex
//   sns   style.strokeNoScale
//   ls    el.getLineScale(), hex
// The pen the canvas draws is m times a round pen of width lw, its dash (and
// phase) lengths along the path taken back through m.
// Run: node tools/advchart-oracle/pen-map.js -> tests/fixtures/advchart-pen-map.json
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
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};
global.requestAnimationFrame = function () { return 0; };
// a DOMParser for parseXML (an SVG map): jsdom's, as geo-svg.js
const JSDOM_PATH = process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom';
const { JSDOM } = require(JSDOM_PATH);
global.DOMParser = new JSDOM('').window.DOMParser;
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// an SVG map: a path under its own transform scale(2, 1), a dashed rect, a
// named rect the option styles (MapDraw: strokeNoScale)
const MAPS = [{ map: 'r7p-pen', svg: '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">'
  + '<path d="M10 10 L60 10 L60 40 Z" fill="#eee" stroke="#ab0001" stroke-width="2" transform="scale(2,1)"/>'
  + '<rect x="130" y="10" width="40" height="30" fill="#eee" stroke="#ab0002" stroke-width="3" stroke-dasharray="4 2"/>'
  + '<rect name="b" x="40" y="60" width="50" height="30" fill="#eee" stroke="#000" stroke-width="1"/>'
  + '</svg>' }];
MAPS.forEach(m => echarts.registerMap(m.map, { svg: m.svg }));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-pen-map.json');
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

// ---------- the recording canvas ----------
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;
const Displayable = Object.getPrototypeOf(Path.prototype).constructor;
let CUR = null;
const origIBB = Displayable.prototype.innerBeforeBrush;
Displayable.prototype.innerBeforeBrush = function () { CUR = this; return origIBB.apply(this, arguments); };
let STROKES = [];
function makeCtx(canvas) {
  const st = { m: [1, 0, 0, 1, 0, 0], lw: 1, dash: [], off: 0, stroke: '#000' };
  const stack = [];
  const mul = (a, b, c, d, e, f) => {
    const m = st.m;
    st.m = [m[0] * a + m[2] * b, m[1] * a + m[3] * b, m[0] * c + m[2] * d, m[1] * c + m[3] * d,
      m[0] * e + m[2] * f + m[4], m[1] * e + m[3] * f + m[5]];
  };
  const ctx = {
    canvas,
    dpr: 1,
    save() { stack.push({ m: st.m.slice(), lw: st.lw, dash: st.dash.slice(), off: st.off, stroke: st.stroke }); },
    restore() { const s = stack.pop(); if (s) Object.assign(st, s); },
    setTransform(a, b, c, d, e, f) { st.m = [a, b, c, d, e, f]; },
    resetTransform() { st.m = [1, 0, 0, 1, 0, 0]; },
    transform: mul,
    scale(x, y) { mul(x, 0, 0, y, 0, 0); },
    translate(x, y) { mul(1, 0, 0, 1, x, y); },
    rotate(r) { const c = Math.cos(r), s = Math.sin(r); mul(c, s, -s, c, 0, 0); },
    setLineDash(d) { st.dash = d.slice(); },
    getLineDash() { return st.dash.slice(); },
    stroke() { if (CUR) STROKES.push({ el: CUR, m: st.m.slice(), lw: st.lw, dash: st.dash.slice(), off: st.off, col: st.stroke }); },
    measureText(t) { return { width: String(t).length * 6 }; },
    createLinearGradient() { return { addColorStop() {} }; },
    createRadialGradient() { return { addColorStop() {} }; },
    createPattern() { return {}; },
    getImageData() { return { data: [] }; },
    isPointInPath() { return false; },
  };
  return new Proxy(ctx, {
    get: (t, k) => {
      if (k === 'lineWidth') return st.lw;
      if (k === 'lineDashOffset') return st.off;
      if (k === 'strokeStyle') return st.stroke;
      if (k in t) return t[k];
      if (typeof k === 'string' && /^[a-z]/.test(k)) return function () {};
      return undefined;
    },
    set: (t, k, v) => {
      if (k === 'lineWidth') st.lw = v;
      else if (k === 'lineDashOffset') st.off = v;
      else if (k === 'strokeStyle') st.stroke = v;
      else t[k] = v;
      return true;
    },
  });
}
function fakeCanvas(w, h) {
  const c = { nodeName: 'CANVAS', width: w, height: h, style: {}, setAttribute() {}, getAttribute() { return null; },
    addEventListener() {}, removeEventListener() {} };
  const ctx = makeCtx(c);
  c.getContext = () => ctx;
  return c;
}
echarts.setPlatformAPI({ createCanvas() { return fakeCanvas(300, 150); } });

const W = 400;
const H = 300;
const vv = (s, more) => Object.assign({ animation: false, xAxis: { show: false, type: 'value', min: 0, max: 10 },
  yAxis: { show: false, type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const solo = (s, more) => Object.assign({ animation: false, series: Array.isArray(s) ? s : [s] }, more || {});
const SB = (c, w, more) => Object.assign({ borderColor: c, borderWidth: w }, more || {});
const it = (x, y, sym, size, is, more) => Object.assign({ value: [x, y], symbol: sym, symbolSize: size, itemStyle: is }, more || {});

function cases() {
  return [
    // ---- Symbol.ts: the unit box scaled by half the size, strokeNoScale ----
    ['scatter-oblong', vv({ type: 'scatter', data: [
      it(1, 8, 'circle', [10, 30], SB('#a00001', 2)),
      it(3, 8, 'rect', [40, 10], SB('#a00002', 4)),
      it(5, 8, 'triangle', [20, 40], SB('#a00003', 3, { borderType: 'dashed' }), { symbolRotate: 30 }),
      it(7, 8, 'roundRect', [30, 12], SB('#a00004', 2, { borderType: 'dotted' })),
      it(9, 8, 'diamond', [12, 36], SB('#a00005', 2), { symbolRotate: -45 }),
      it(1, 5, 'pin', [20, 30], SB('#a00006', 2)),
      it(3, 5, 'arrow', [16, 30], SB('#a00007', 2), { symbolRotate: 90 }),
      it(5, 5, 'emptyCircle', [8, 24], { color: '#a00008' }),
      it(7, 5, 'rect', [2, 20], SB('#a00009', 2)),
      it(9, 5, 'circle', [20, 20], SB('#a0000c', 2), { symbolRotate: 30 }),
      it(1, 2, 'emptyRect', [24, 8], { color: '#a0000d', borderType: [3, 2], borderDashOffset: 3 }),
      it(3, 2, 'rect', [30, 10], SB('#a0000e', 3, { borderType: [6, 2], borderDashOffset: 4 }), { symbolRotate: 60 }),
      it(5, 2, 'emptyDiamond', [20, 2], { color: '#a0000f' }),
      it(7, 2, 'path://M0 0L10 0L5 10Z', [30, 10], SB('#a0000a', 2)),
      it(9, 2, 'line', [24, 8], { color: '#a0000b', borderWidth: 3 }, { symbolRotate: 20 }),
    ] })],
    ['line-symbols', vv({ type: 'line', symbol: 'emptyCircle', symbolSize: [12, 6], color: '#a10001',
      lineStyle: { color: '#a10002' }, data: [[1, 2], [4, 6], [8, 3]] })],
    ['effect-scatter', vv({ type: 'effectScatter', symbolSize: [10, 24], itemStyle: SB('#a20001', 2),
      rippleEffect: { brushType: 'stroke', color: '#a20002' }, data: [[5, 5]] })],
    ['markpoint', vv({ type: 'line', symbol: 'none', lineStyle: { color: '#a30009' }, data: [[1, 2], [9, 3]],
      markPoint: { data: [
        { coord: [3, 5], symbol: 'pin', symbolSize: [20, 40], itemStyle: SB('#a30001', 2) },
        { coord: [7, 5], symbol: 'emptyCircle', symbolSize: [10, 30], itemStyle: { color: '#a30002' } },
        { coord: [5, 8], symbol: 'rect', symbolSize: [30, 10], symbolRotate: 40, itemStyle: SB('#a30003', 3, { borderType: 'dashed' }) },
      ] } })],
    ['radar', { animation: false, radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }],
      axisLine: { show: false }, splitLine: { show: false }, splitArea: { show: false }, axisName: { show: false } },
      series: [{ type: 'radar', symbol: 'emptyRect', symbolSize: [16, 6], lineStyle: { color: '#a40002' },
        itemStyle: { color: '#a40001' }, data: [{ value: [5, 8, 3] }] }] }],
    ['tree', solo({ type: 'tree', symbol: 'emptyCircle', symbolSize: [10, 24], label: { show: false },
      itemStyle: { color: '#a50001' }, lineStyle: { color: '#a50002' },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] })],
    // ---- a graph view whose scaleY is not its scaleX ----
    ['graph-squash', solo({ type: 'graph', layout: 'none', left: 0, top: 50, width: 400, height: 200,
      edgeSymbol: ['emptyCircle', 'arrow'], edgeSymbolSize: [8, 12], label: { show: false },
      lineStyle: { width: 2, type: 'dashed', opacity: 1 },
      data: [
        { name: 'a', x: 0, y: 0, symbolSize: 12, itemStyle: SB('#a60001', 2) },
        { name: 'b', x: 100, y: 0, symbol: 'rect', symbolSize: [10, 20], symbolRotate: 30, itemStyle: SB('#a60002', 2) },
        { name: 'c', x: 50, y: 100, symbol: 'emptyCircle', symbolSize: 14, itemStyle: { color: '#a60003' } },
        { name: 'd', x: 100, y: 100, symbol: 'rect', symbolSize: [16, 8], itemStyle: SB('#a60004', 3, { borderType: 'dotted' }) },
      ],
      links: [
        { source: 'a', target: 'b', lineStyle: { color: '#a60011' } },
        { source: 'a', target: 'c', lineStyle: { color: '#a60012', curveness: 0.3 } },
        { source: 'c', target: 'd', lineStyle: { color: '#a60013', type: [5, 3], dashOffset: 2 } },
        { source: 'b', target: 'd', lineStyle: { color: '#a60014', type: 'solid', width: 3 } },
      ] })],
    // scaleX one: getLineScale is one, the pen stretched by scaleY whole
    ['graph-quirk', solo({ type: 'graph', layout: 'none', left: 100, top: 0, width: 100, height: 300,
      edgeSymbol: ['none', 'emptyCircle'], edgeSymbolSize: 10, label: { show: false },
      lineStyle: { width: 2 },
      data: [
        { name: 'a', x: 0, y: 0, symbolSize: 10, itemStyle: SB('#a70001', 2) },
        { name: 'b', x: 100, y: 0, symbolSize: 10, itemStyle: SB('#a70002', 2) },
        { name: 'c', x: 0, y: 100, symbolSize: 10, itemStyle: SB('#a70003', 2) },
      ],
      links: [
        { source: 'a', target: 'b', lineStyle: { color: '#a70011' } },
        { source: 'a', target: 'c', lineStyle: { color: '#a70012' } },
        { source: 'b', target: 'c', lineStyle: { color: '#a70013' } },
      ] })],
    // ---- a pictorial bar's glyphs: the pattern size scaled to the glyph ----
    ['pictorial', { animation: false, xAxis: { show: false, type: 'category', data: ['A', 'B', 'C', 'D'] },
      yAxis: { show: false, type: 'value', min: -10, max: 10 },
      series: [{ type: 'pictorialBar', barCategoryGap: '20%', data: [
        { value: 6, symbol: 'rect', symbolSize: [30, 12], symbolRepeat: true, itemStyle: SB('#a80001', 2) },
        { value: -5, symbol: 'triangle', symbolSize: [20, 40], itemStyle: SB('#a80002', 3, { borderType: 'dashed' }) },
        { value: 7, symbol: 'circle', symbolSize: [16, 40], symbolRotate: 30, itemStyle: SB('#a80003', 2) },
        // square and mirrored (a negative value): a turn-and-scale's mirror, a round pen
        { value: -4, symbol: 'circle', symbolSize: [20, 20], itemStyle: SB('#a80004', 2) },
      ] }] }],
    // ---- the graphic component: an element's own scaleX / scaleY ----
    ['graphic', { animation: false, graphic: [
      { type: 'rect', x: 60, y: 60, scaleX: 3, scaleY: 1, shape: { x: 0, y: 0, width: 20, height: 30 },
        style: { fill: null, stroke: '#a90001', lineWidth: 2, lineDash: [4, 2], lineDashOffset: 1 } },
      { type: 'circle', x: 200, y: 80, scaleX: 1.5, scaleY: 3, rotation: 0.5, shape: { cx: 0, cy: 0, r: 10 },
        style: { fill: '#eee', stroke: '#a90002', lineWidth: 2 } },
      { type: 'polyline', x: 40, y: 200, scaleX: 4, scaleY: 1, shape: { points: [[0, 0], [10, 30], [20, 0], [30, 30]] },
        style: { fill: null, stroke: '#a90003', lineWidth: 3, strokeNoScale: true } },
      { type: 'polygon', x: 260, y: 200, scaleX: 2, scaleY: 3, rotation: -0.3,
        shape: { points: [[0, 0], [20, 0], [10, 20]] },
        style: { fill: null, stroke: '#a90004', lineWidth: 3, strokeNoScale: true, lineDash: [6, 3] } },
      { type: 'group', x: 300, y: 40, scaleX: 2, scaleY: 0.5, children: [
        { type: 'rect', shape: { x: 0, y: 0, width: 30, height: 40 }, style: { fill: null, stroke: '#a90005', lineWidth: 2 } },
      ] },
      // mirrored and scaled alike: a round pen
      { type: 'rect', x: 200, y: 150, scaleX: -2, scaleY: 2, shape: { x: 0, y: 0, width: 20, height: 10 },
        style: { fill: null, stroke: '#a90006', lineWidth: 2 } },
    ] }],
    // ---- an SVG map under a geo whose aspectScale is not one ----
    ['geo-svg', { animation: false, geo: { map: 'r7p-pen', aspectScale: 0.5, roam: false, left: 20, top: 20, width: 360, height: 260,
      label: { show: false }, regions: [{ name: 'b', itemStyle: { borderColor: '#ab0003', borderWidth: 2, borderType: 'dashed' } }] } }],
    // ---- timeline symbols: the unit box scaled, strokeNoScale ----
    ['timeline', { animation: false, baseOption: { timeline: { data: ['a', 'b', 'c'], axisType: 'category',
      symbol: 'rect', symbolSize: [16, 6], itemStyle: { color: '#fff', borderColor: '#aa0001', borderWidth: 2 },
      lineStyle: { color: '#aa0002' }, label: { show: false }, controlStyle: { show: false },
      checkpointStyle: { symbol: 'circle', symbolSize: [10, 24], color: '#fff', borderColor: '#aa0003', borderWidth: 2,
        animation: false } } }, options: [{}, {}, {}] }],
  ];
}

function boxCentre(el) {
  const r = el.getBoundingRect();
  el.updateTransform();
  const m = el.transform;
  const pts = [[r.x, r.y], [r.x + r.width, r.y], [r.x, r.y + r.height], [r.x + r.width, r.y + r.height]];
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const p of pts) {
    const x = m ? m[0] * p[0] + m[2] * p[1] + m[4] : p[0];
    const y = m ? m[1] * p[0] + m[3] * p[1] + m[5] : p[1];
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return [(x0 + x1) / 2, (y0 + y1) / 2];
}

function run(id, option) {
  STROKES = [];
  CUR = null;
  const dom = fakeCanvas(W, H);
  const chart = echarts.init(dom, null, { renderer: 'canvas', width: W, height: H, devicePixelRatio: 1 });
  chart.setOption(option);
  chart.getZr().refreshImmediately();
  const out = [];
  for (const s of STROKES) {
    const el = s.el;
    if (!(el instanceof Path)) continue;
    const c = boxCentre(el);
    out.push({
      col: String(s.col),
      cx: hex(c[0]), cy: hex(c[1]),
      m: s.m.slice(0, 4).map(hex),
      lw: hex(s.lw),
      dash: s.dash.map(hex),
      off: hex(+s.off || 0),
      sns: !!el.style.strokeNoScale,
      ls: hex(el.getLineScale()),
    });
  }
  chart.dispose();
  must(out.length > 0, id + ': nothing stroked');
  return { id, option, strokes: out };
}

function aniso(s) {
  const m = s.m.map(h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); });
  const n = Math.max(...m.map(Math.abs));
  return !(Math.abs(m[0] - m[3]) <= 1e-9 * n && Math.abs(m[1] + m[2]) <= 1e-9 * n)
    && !(Math.abs(m[0] + m[3]) <= 1e-9 * n && Math.abs(m[1] - m[2]) <= 1e-9 * n);
}

function generate() {
  const charts = cases().map(([id, o]) => run(id, o));
  // every case has a stretched pen somewhere
  charts.forEach(c => must(c.strokes.some(aniso), c.id + ': no stretched pen'));
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node, zrender canvas painter on a recording context',
    note: 'R7-P: per case, every ctx.stroke() of a path: the stroke colour, the centre of the element\'s own box through its '
      + 'global transform, the context\'s transform (linear part), lineWidth, dash and phase as zrender set them, '
      + 'strokeNoScale and getLineScale. The canvas pen is m times a round pen of width lw. `maps` the SVG maps the cases name.',
    W, H, maps: MAPS, charts };
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
