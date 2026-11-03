// Round 7 R7-Y: A PEN WRITTEN WHERE ONLY THE SERIES' WAS READ, AND A BORDER
// NEVER DRAWN -- what zrender's canvas painter brushes for
//
// 1. A RADAR DATA ITEM'S OWN lineStyle.width 'Infinity' (RadarView:
//    polyline.useStyle(itemModel.getModel('lineStyle').getLineStyle()) -- the
//    item's width over the series'): bindPathAndTextCommonStyle assigns
//    ctx.lineWidth = Infinity, which the canvas refuses, so the ring strokes
//    at the width the element before it left; its stroked bounding rect is
//    not a number and it is never hit. The same for a radar symbol's
//    itemStyle.borderWidth, and the other series whose item writes a pen of
//    'Infinity' (graph links, parallel lines, funnel, boxplot, candlestick).
// 2. A THEMERIVER'S itemStyle BORDER (ThemeRiverView: polygon.useStyle(the
//    last row's visual style), seriesStyleTask's getItemStyle: borderColor
//    the stroke, borderWidth the lineWidth -- 1, zrender's default, when only
//    the colour is written --, borderType / borderDashOffset / borderCap /
//    borderJoin / borderMiterLimit, the shadow, the opacity).
//
// From the real ECharts 6.1 dist, rendered by zrender's canvas painter on a
// recording context that refuses what a browser's refuses, setter by setter
// (lines-canvas.js' R7-V / R7-W context: globalAlpha outside 0..1,
// lineWidth / miterLimit not above 0 or not finite, lineDashOffset /
// shadowOffsetX / Y not finite, shadowBlur below 0, a word lineCap /
// lineJoin does not know, a fill / stroke / shadow colour zrender's
// color.parse does not read, setLineDash with a value not finite or below 0).
// Per case: per tracked element its fills and strokes (`ops`: op, ga, fs, ss,
// lw, ld, ldo, sc, sb, sox, soy, cap, join, ml, m), the bounds of the path it
// built on the canvas (`pb`); per probe [x, y] the key of findHover's target.
// Keys: r<s>.<i> a radar ring, ra<s>.<i> its area, rs<s>.<i>.<j> its j-th
// symbol; tr<s>.<k> a themeRiver layer; d<s>.<i>.<n> another series' item's
// n-th displayable; ge<s>.<i> a graph link's line.
// Run: node tools/advchart-oracle/canvas-borders.js -> tests/fixtures/advchart-canvas-borders.json
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
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-canvas-borders.json');
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
let OPS = new Map();
let PATHS = new Map();
const origIBB = Displayable.prototype.innerBeforeBrush;
Displayable.prototype.innerBeforeBrush = function () { CUR = this; return origIBB.apply(this, arguments); };
const toNum = v => (typeof v === 'symbol' ? NaN : +v);
const CAPS = ['butt', 'round', 'square'];
const JOINS = ['round', 'bevel', 'miter'];
const COMPOSITES = ['source-over', 'source-in', 'source-out', 'source-atop', 'destination-over', 'destination-in',
  'destination-out', 'destination-atop', 'lighter', 'copy', 'xor', 'multiply', 'screen', 'overlay', 'darken',
  'lighten', 'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference', 'exclusion', 'hue',
  'saturation', 'color', 'luminosity'];
const isCssColour = v => !!echarts.color.parse(String(v));
function makeCtx(canvas) {
  const st = { shadowColor: 'rgba(0, 0, 0, 0)', shadowBlur: 0, m: [1, 0, 0, 1, 0, 0],
    globalAlpha: 1, lineWidth: 1, lineCap: 'butt', lineJoin: 'miter', miterLimit: 10, lineDashOffset: 0,
    shadowOffsetX: 0, shadowOffsetY: 0, fillStyle: '#000000', strokeStyle: '#000000',
    globalCompositeOperation: 'source-over', lineDash: [] };
  const stack = [];
  let owner = null;
  let pending = false;
  let pend = [];
  const at = (x, y) => [st.m[0] * x + st.m[2] * y + st.m[4], st.m[1] * x + st.m[3] * y + st.m[5]];
  const put = (x, y) => {
    if (!pending) { owner = CUR; pending = true; }
    if (!owner) return;
    pend.push(at(x, y));
  };
  let px = 0;
  let py = 0;
  const styleName = v => (v && typeof v === 'object' ? '[grad]' : String(v));
  const opState = () => ({ fs: styleName(st.fillStyle), ss: styleName(st.strokeStyle), lw: hex(st.lineWidth),
    ld: st.lineDash.map(hex), ldo: hex(st.lineDashOffset), sc: String(st.shadowColor), sb: hex(st.shadowBlur),
    sox: hex(st.shadowOffsetX), soy: hex(st.shadowOffsetY), cap: st.lineCap, join: st.lineJoin,
    ml: hex(st.miterLimit), m: st.m.map(hex) });
  const opNote = op => {
    pending = false;
    if (!owner) return;
    if (pend.length) {
      let p = PATHS.get(owner);
      if (!p) { p = []; PATHS.set(owner, p); }
      for (const q of pend) p.push(q);
      pend = [];
    }
    let o = OPS.get(owner);
    if (!o) { o = []; OPS.set(owner, o); }
    o.push(Object.assign({ op, ga: hex(st.globalAlpha) }, opState()));
  };
  const ctx = {
    canvas,
    dpr: 1,
    save() { stack.push(Object.assign({}, st, { m: st.m.slice(), lineDash: st.lineDash.slice() })); },
    restore() { const s = stack.pop(); if (s) Object.assign(st, s); },
    setTransform(a, b, c, d, e, f) { if ([a, b, c, d, e, f].every(v => isFinite(v))) st.m = [a, b, c, d, e, f]; },
    fill() { opNote('fill'); },
    stroke() { opNote('stroke'); },
    beginPath() { pending = false; owner = null; pend = []; },
    clip() { pend = []; pending = false; owner = null; },
    moveTo(x, y) { put(x, y); px = x; py = y; },
    lineTo(x, y) { put(x, y); px = x; py = y; },
    rect(x, y, w, h) { put(x, y); put(x + w, y); put(x + w, y + h); put(x, y + h); px = x; py = y; },
    bezierCurveTo(x1, y1, x2, y2, x, y) {
      for (let i = 1; i <= 64; i++) {
        const t = i / 64;
        const u = 1 - t;
        put(u * u * u * px + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x,
          u * u * u * py + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y);
      }
      px = x; py = y;
    },
    quadraticCurveTo(x1, y1, x, y) {
      for (let i = 1; i <= 64; i++) {
        const t = i / 64;
        const u = 1 - t;
        put(u * u * px + 2 * u * t * x1 + t * t * x, u * u * py + 2 * u * t * y1 + t * t * y);
      }
      px = x; py = y;
    },
    arc(cx, cy, r, a0, a1, acw) {
      let sw = a1 - a0;
      const full = Math.PI * 2;
      if (!acw && sw >= full) sw = full;
      else if (acw && -sw >= full) sw = -full;
      else if (!acw) { sw = sw % full; if (sw < 0) sw += full; }
      else { sw = sw % full; if (sw > 0) sw -= full; }
      for (let i = 0; i <= 256; i++) {
        const a = a0 + sw * i / 256;
        put(cx + r * Math.cos(a), cy + r * Math.sin(a));
      }
      px = cx + r * Math.cos(a0 + sw); py = cy + r * Math.sin(a0 + sw);
    },
    ellipse() {},
    closePath() {},
    setLineDash(a) {
      const v = Array.from(a || [], toNum);
      if (v.some(x => !isFinite(x) || x < 0)) return;
      st.lineDash = v.length % 2 ? v.concat(v) : v;
    },
    getLineDash() { return st.lineDash.slice(); },
    fillText() {},
    strokeText() {},
    measureText(t) { return { width: String(t).length * 6 }; },
    createLinearGradient() { return { addColorStop() {} }; },
    createRadialGradient() { return { addColorStop() {} }; },
    createPattern() { return {}; },
    getImageData() { return { data: [] }; },
    isPointInPath() { return false; },
  };
  return new Proxy(ctx, {
    get: (t, k) => {
      if (typeof k === 'string' && k !== 'm' && k !== 'lineDash' && Object.prototype.hasOwnProperty.call(st, k)) return st[k];
      if (k in t) return t[k];
      if (typeof k === 'string' && /^[a-z]/.test(k)) return function () {};
      return undefined;
    },
    set: (t, k, v) => {
      let n;
      switch (k) {
        case 'shadowColor': if (isCssColour(v)) st.shadowColor = v; break;
        case 'shadowBlur': n = toNum(v); if (isFinite(n) && n >= 0) st.shadowBlur = n; break;
        case 'globalAlpha': n = toNum(v); if (isFinite(n) && n >= 0 && n <= 1) st.globalAlpha = n; break;
        case 'lineWidth': case 'miterLimit': n = toNum(v); if (isFinite(n) && n > 0) st[k] = n; break;
        case 'lineDashOffset': case 'shadowOffsetX': case 'shadowOffsetY':
          n = toNum(v); if (isFinite(n)) st[k] = n; break;
        case 'lineCap': if (CAPS.indexOf(String(v)) >= 0) st.lineCap = String(v); break;
        case 'lineJoin': if (JOINS.indexOf(String(v)) >= 0) st.lineJoin = String(v); break;
        case 'globalCompositeOperation': if (COMPOSITES.indexOf(String(v)) >= 0) st[k] = String(v); break;
        case 'fillStyle': case 'strokeStyle':
          if ((v && typeof v === 'object') || isCssColour(v)) st[k] = v; break;
        default: t[k] = v;
      }
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

const CW = 400;
const CH = 300;
const PAL = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#ff8800' }, { offset: 1, color: '#0088ff' }] };
const RADAR = { indicator: [{ max: 10 }, { max: 10 }, { max: 10 }], radius: 100, center: [200, 150] };
// a radar series' items (symbol none unless written)
const RD = (more, data) => Object.assign({ type: 'radar', symbol: 'none', data }, more);
const RIVER_DATA = [['2024/01/01', 3, 'A'], ['2024/01/02', 5, 'A'], ['2024/01/03', 2, 'A'],
  ['2024/01/01', 4, 'B'], ['2024/01/02', 2, 'B'], ['2024/01/03', 6, 'B']];
const TR = (itemStyle, more) => Object.assign({ animation: false, color: PAL,
  singleAxis: { type: 'time', top: 40, bottom: 40, left: 40, right: 40 },
  series: [{ type: 'themeRiver', label: { show: false }, itemStyle, data: RIVER_DATA }] }, more || {});
// probes along a ring's first edge (spoke 0 to spoke 1) and off it
function cases() {
  return [
    // ---- 1. a radar item's own width of 'Infinity' ----
    ['r-item-inf', { animation: false, color: PAL, radar: RADAR, series: [RD({ lineStyle: { width: 3 } }, [
      { value: [8, 8, 8], lineStyle: { width: 5 } },
      { value: [6, 6, 6], lineStyle: { width: 'Infinity' } },
      { value: [4, 4, 4] }])] },
    { probes: 'rings' }],
    // the series' 'Infinity' under an item's number, and under an item's
    // lineStyle that writes no width
    ['r-series-inf', { animation: false, color: PAL, radar: RADAR, series: [
      RD({ lineStyle: { width: 4 } }, [{ value: [9, 9, 9] }]),
      RD({ lineStyle: { width: 'Infinity' } }, [
        { value: [8, 8, 8], lineStyle: { width: 2 } },
        { value: [6, 6, 6], lineStyle: { type: 'dashed' } },
        { value: [4, 4, 4], lineStyle: { width: '-Infinity' } },
        { value: [3, 3, 3] }])] },
    { probes: 'rings' }],
    // with a colour of its own and an area, after another series' ring
    ['r-item-inf-area', { animation: false, color: PAL, radar: RADAR, series: [
      RD({ lineStyle: { width: 6 } }, [{ value: [9, 9, 9] }]),
      RD({ areaStyle: { opacity: 0.3 } }, [{ value: [5, 7, 5], lineStyle: { width: 'Infinity', color: '#ff0000' } }])] },
    { probes: 'rings' }],
    // a series' width written as a numeric string
    ['r-series-str', { animation: false, color: PAL, radar: RADAR, series: [RD({ lineStyle: { width: '4' } }, [
      { value: [8, 8, 8] }, { value: [5, 5, 5], lineStyle: { width: '1.5' } }])] },
    { probes: 'rings' }],
    // a symbol's border of 'Infinity', the series' and an item's
    ['r-sym-inf', { animation: false, color: PAL, radar: RADAR, series: [
      RD({ symbol: 'circle', symbolSize: 10, lineStyle: { width: 3 }, itemStyle: { borderColor: '#000', borderWidth: 2 } }, [
        { value: [8, 8, 8] },
        { value: [5, 5, 5], itemStyle: { borderWidth: 'Infinity' } }]),
      RD({ symbol: 'rect', symbolSize: 8, lineStyle: { width: 1 }, itemStyle: { borderColor: '#00f', borderWidth: 'Infinity' } },
        [{ value: [3, 3, 3] }, { value: [7, 2, 6], itemStyle: { borderWidth: 3 } }])] },
    { probes: 'symbols' }],
    // ---- 2. a themeRiver's border ----
    ['tr-border', TR({ borderColor: '#000' }), { probes: 'river' }],
    ['tr-border-pen', TR({ borderColor: '#ff0000', borderWidth: 3, borderType: 'dashed', borderDashOffset: 2,
      borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4 }), { probes: 'river' }],
    ['tr-border-grad', TR({ borderColor: GRAD, borderWidth: 2 }), {}],
    ['tr-border-auto', TR({ borderColor: 'auto', borderWidth: 2 }), {}],
    ['tr-border-none', TR({ borderColor: 'none', borderWidth: 4 }), { probes: 'river' }],
    ['tr-border-clear', TR({ borderColor: 'transparent', borderWidth: 6 }), { probes: 'river' }],
    ['tr-border-zero', TR({ borderColor: '#000', borderWidth: 0 }), {}],
    ['tr-border-str', TR({ borderColor: '#000', borderWidth: '2' }), {}],
    ['tr-border-dash-arr', TR({ borderColor: '#000', borderWidth: 2, borderType: [5, 3] }), {}],
    ['tr-shadow', TR({ borderColor: '#000', borderWidth: 1, shadowBlur: 6, shadowColor: '#0000ff', shadowOffsetX: 2,
      shadowOffsetY: 3, opacity: 0.6 }), {}],
    // two rivers: the second's border of 'Infinity' strokes at the first's 4
    ['tr-border-inf', { animation: false, color: PAL,
      singleAxis: [{ type: 'time', top: 20, height: 100, left: 40, right: 40 },
        { type: 'time', top: 160, height: 100, left: 40, right: 40 }],
      series: [{ type: 'themeRiver', singleAxisIndex: 0, label: { show: false }, itemStyle: { borderColor: '#000', borderWidth: 4 },
        data: RIVER_DATA },
      { type: 'themeRiver', singleAxisIndex: 1, label: { show: false }, itemStyle: { borderColor: '#000', borderWidth: 'Infinity' },
        data: RIVER_DATA }] }, { probes: 'river' }],
    // ---- 3. the same pattern elsewhere: an item's pen of 'Infinity' ----
    ['x-graph-link', { animation: false, color: PAL, series: [{ type: 'graph', layout: 'none', symbolSize: 10,
      label: { show: false }, lineStyle: { width: 3, color: '#333' },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 100, y: 100 }],
      links: [{ source: 'a', target: 'b', lineStyle: { width: 5 } }, { source: 'b', target: 'c', lineStyle: { width: 'Infinity' } }] }] },
    { probes: 'links' }],
    ['x-graph-link-series', { animation: false, color: PAL, series: [{ type: 'graph', layout: 'none', symbolSize: 10,
      label: { show: false }, lineStyle: { width: 'Infinity', color: '#333' },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 100, y: 100 }],
      links: [{ source: 'a', target: 'b', lineStyle: { width: 5 } }, { source: 'b', target: 'c' }] }] },
    { probes: 'links' }],
    ['x-parallel', { animation: false, color: PAL, parallelAxis: [{ dim: 0, max: 10 }, { dim: 1, max: 10 }, { dim: 2, max: 10 }],
      series: [{ type: 'parallel', lineStyle: { width: 2 }, data: [{ value: [2, 5, 8], lineStyle: { width: 6 } },
        { value: [7, 3, 4], lineStyle: { width: 'Infinity' } }, [5, 5, 5]] }] }, {}],
    ['x-parallel-series', { animation: false, color: PAL, parallelAxis: [{ dim: 0, max: 10 }, { dim: 1, max: 10 }, { dim: 2, max: 10 }],
      series: [{ type: 'parallel', lineStyle: { width: 4 }, data: [[1, 1, 1]] },
        { type: 'parallel', lineStyle: { width: 'Infinity' }, data: [{ value: [2, 5, 8], lineStyle: { width: 3 } },
          [7, 3, 4]] }] }, {}],
    ['x-funnel', { animation: false, color: PAL, series: [{ type: 'funnel', label: { show: false },
      itemStyle: { borderColor: '#000', borderWidth: 2 },
      data: [{ value: 3, name: 'a', itemStyle: { borderWidth: 5 } }, { value: 2, name: 'b', itemStyle: { borderWidth: 'Infinity' } }] }] }, {}],
    ['x-boxplot', { animation: false, color: PAL, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'boxplot', itemStyle: { borderWidth: 2 }, data: [{ value: [1, 2, 4, 6, 8], itemStyle: { borderWidth: 5 } },
        { value: [2, 3, 5, 7, 9], itemStyle: { borderWidth: 'Infinity' } }] }] }, {}],
    ['x-boxplot-str', { animation: false, color: PAL, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'boxplot', itemStyle: { borderWidth: 'Infinity' }, data: [{ value: [1, 2, 4, 6, 8], itemStyle: { borderWidth: '3' } },
        { value: [2, 3, 5, 7, 9] }] }] }, {}],
    ['x-candle-series', { animation: false, color: PAL, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'candlestick', itemStyle: { borderWidth: 'Infinity', color: '#ff0000', color0: '#00aa00', borderColor: '#880000',
        borderColor0: '#004400' }, data: [{ value: [2, 6, 1, 8], itemStyle: { borderWidth: 3 } }, [6, 3, 2, 9],
        { value: [4, 7, 3, 8], itemStyle: { color: '#0000ff' } }] }] }, {}],
    ['x-candle', { animation: false, color: PAL, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'candlestick', itemStyle: { borderWidth: 2, color: '#ff0000', color0: '#00aa00', borderColor: '#880000', borderColor0: '#004400' }, data: [{ value: [2, 6, 1, 8], itemStyle: { borderWidth: 5 } },
        { value: [6, 3, 2, 9], itemStyle: { borderWidth: 'Infinity' } }] }] }, {}],
    ['x-heatmap', { animation: false, color: PAL, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['p'] },
      visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', itemStyle: { borderColor: '#000', borderWidth: 2 },
        data: [{ value: [0, 0, 3], itemStyle: { borderWidth: 5 } }, { value: [1, 0, 7], itemStyle: { borderWidth: 'Infinity' } }] }] }, {}],
  ];
}

function track(chart) {
  const map = new Map();
  const model = chart.getModel();
  model.eachSeries((sm, si) => {
    const type = sm.subType;
    const data = sm.getData();
    if (type === 'radar') {
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        if (!g) continue;
        map.set(g.childAt(0), 'r' + si + '.' + i);
        map.set(g.childAt(1), 'ra' + si + '.' + i);
        const sg = g.childAt(2);
        for (let j = 0; sg && j < sg.childCount(); j++) map.set(sg.childAt(j), 'rs' + si + '.' + i + '.' + j);
      }
      return;
    }
    if (type === 'themeRiver') {
      const view = chart.getViewOfSeriesModel(sm);
      const layers = view && view._layers;
      if (layers) for (let k = 0; k < layers.length; k++) if (layers[k]) map.set(layers[k].childAt(0), 'tr' + si + '.' + k);
      return;
    }
    if (type === 'graph') {
      const ed = sm.getEdgeData();
      for (let i = 0; i < ed.count(); i++) {
        const line = ed.getItemGraphicEl(i);
        const lp = line && line.childOfName('line');
        if (lp) map.set(lp, 'ge' + si + '.' + i);
      }
      return;
    }
    for (let i = 0; i < data.count(); i++) {
      const g = data.getItemGraphicEl(i);
      if (!g) continue;
      let n = 0;
      const visit = e => {
        if (e.isGroup) { for (const c of e.childrenRef()) visit(c); return; }
        if (e.style && !map.has(e)) map.set(e, 'd' + si + '.' + i + '.' + (n++));
      };
      visit(g);
    }
  });
  return map;
}

function elRec(el, key) {
  const r = { key, ignore: !!el.ignore, ops: OPS.get(el) || [] };
  const p = PATHS.get(el);
  if (p && p.length) {
    const xs = p.map(q => q[0]);
    const ys = p.map(q => q[1]);
    r.pb = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)].map(hex);
  }
  else r.pb = null;
  return r;
}

// the points a case probes: on and off each tracked path's edges
function probesOf(kind, chart, map) {
  const out = [];
  const add = (x, y) => out.push([Math.round(x * 64) / 64, Math.round(y * 64) / 64]);
  for (const [el, key] of map) {
    if (kind === 'rings' && /^r[0-9]/.test(key)) {
      const pts = el.shape.points;
      for (let k = 0; k < pts.length; k++) {
        const a = pts[k];
        const b = pts[(k + 1) % pts.length];
        // (not a closing edge of no length: its probes would sit on a vertex)
        if (Math.hypot(b[0] - a[0], b[1] - a[1]) < 1e-9) continue;
        for (const t of [0.3, 0.5]) {
          const x = a[0] + (b[0] - a[0]) * t;
          const y = a[1] + (b[1] - a[1]) * t;
          const len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
          const nx = -(b[1] - a[1]) / len;
          const ny = (b[0] - a[0]) / len;
          for (const d of [0, 0.7, 1.6, 2.6, -2.6]) add(x + nx * d, y + ny * d);
        }
      }
    }
    else if (kind === 'symbols' && /^rs/.test(key)) {
      for (const d of [[0, 0], [5.6, 0], [0, 4.6], [6.5, 0], [-4.2, 4.2]]) add(el.x + d[0], el.y + d[1]);
    }
    else if (kind === 'links' && /^ge/.test(key)) {
      const s = el.shape;
      for (const t of [0.3, 0.6]) {
        const x = s.x1 + (s.x2 - s.x1) * t;
        const y = s.y1 + (s.y2 - s.y1) * t;
        const len = Math.hypot(s.x2 - s.x1, s.y2 - s.y1) || 1;
        const nx = -(s.y2 - s.y1) / len;
        const ny = (s.x2 - s.x1) / len;
        for (const d of [0, 1.2, 2.2, 3.1]) add(x + nx * d, y + ny * d);
      }
    }
    else if (kind === 'river' && /^tr/.test(key)) {
      const pts = el.shape.points;
      const stk = el.shape.stackedOnPoints;
      // above the top edge and below the bottom edge, at each point
      // (not the first and last points: the layer's ends are its edges)
      for (let k = 2; k < pts.length - 2; k += 2) {
        for (const d of [0.4, 1.2, 2.4, 3.6]) {
          const p0 = el.transformCoordToGlobal(pts[k], pts[k + 1] - d);
          const p1 = el.transformCoordToGlobal(stk[k], stk[k + 1] + d);
          add(p0[0], p0[1]);
          add(p1[0], p1[1]);
        }
      }
    }
  }
  return out;
}

function run(id, option, opts) {
  NOW = T_BASE;
  rngState = SEED;
  CUR = null;
  OPS = new Map();
  PATHS = new Map();
  const dom = fakeCanvas(CW, CH);
  const chart = echarts.init(dom, null, { renderer: 'canvas', width: CW, height: CH, devicePixelRatio: 1 });
  const L = chart.getZr().painter.getLayer(0).constructor.prototype;
  if (!L.__r7yClear) {
    const orig = L.clear;
    L.clear = function () { OPS = new Map(); PATHS = new Map(); return orig.apply(this, arguments); };
    L.__r7yClear = true;
  }
  let rec;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    chart.getZr().animation.update();
    chart.getZr().refreshImmediately(true);
    const map = track(chart);
    const els = [];
    for (const [el, key] of map) els.push(elRec(el, key));
    els.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    rec = { id, option, els };
    if (opts.probes) {
      const zr = chart.getZr();
      rec.hits = probesOf(opts.probes, chart, map).map(([x, y]) => {
        const h = zr.handler.findHover(x, y);
        const tg = h && h.target;
        return [hex(x), hex(y), tg ? (map.get(tg) || 'other') : null];
      });
    }
  }
  finally {
    chart.dispose();
  }
  return rec;
}

function generate() {
  const charts = cases().map(([id, o, opts]) => run(id, o, opts));
  const by = id => charts.find(c => c.id === id);
  const el = (id, key) => by(id).els.find(e => e.key === key);
  const strokeW = (id, key) => {
    const s = el(id, key).ops.find(o => o.op === 'stroke');
    return s ? s.lw : null;
  };
  // an item's 'Infinity' strokes at the width the ring before it left: 5
  must(strokeW('r-item-inf', 'r0.1') === hex(5), 'r-item-inf: not 5');
  // a river's border colour alone strokes at zrender's default 1
  must(strokeW('tr-border', 'tr0.0') === hex(1), 'tr-border: not 1');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node, zrender canvas painter on a recording context',
    note: 'R7-Y: per case the tracked elements (r a radar ring, ra its area, rs its symbols, tr a themeRiver layer, '
      + 'ge a graph link, d another series\' displayables) with every fill() / stroke() and the context then, the '
      + 'path\'s bounds on the canvas, and findHover\'s target at probes.',
    W: CW, H: CH, charts };
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
