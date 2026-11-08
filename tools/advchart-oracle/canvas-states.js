// Round 7 R7-Y: VALUES THE CANVAS REFUSES INSIDE A STATE. An emphasis, blur or
// select state's style goes through the same canvas setters as an element's
// own (zrender's bindCommonProps / bindPathAndTextCommonStyle brush whatever
// the element's style holds now): a negative shadowBlur, a cap or join that is
// no canvas word, a miterLimit not above nought, a dash phase or a width no
// finite number, a colour no parser reads -- the canvas refuses each and keeps
// what the element brushed before it left. A state's transition tweens
// shadowBlur (and the other DEFAULT_COMMON_ANIMATION_PROPS style keys) frame
// by frame: a frame whose value is refused takes the canvas' value then.
//
// From the real ECharts 6.1 dist, rendered by zrender's canvas painter on a
// recording context (lines-canvas.js' recipe, its w- record) whose setters
// refuse what a browser's refuse. The clock is replaced (T0 = 1700000000000;
// at sample t: clock T0 + t, the actions dispatched, zr.animation.update(),
// zr.refreshImmediately(true)). The states are entered by dispatchAction
// (highlight / downplay / select), not by a pointer.
//
// Per case and sample (`frames`): t, and per tracked element (a scatter's
// symbol s<series>.<row>, a bar b..., a line's polyline ln<series>.0 and
// symbols ls..., a pie's sector p...): `ops`, every fill() / stroke() made
// for its path with the context then (fs / ss fill and stroke, lw width, ld
// the dash, ldo its phase, sc / sb / sox / soy the shadow, cap, join, ml
// miterLimit, m the transform, ga the alpha).
// Run: node tools/advchart-oracle/canvas-states.js -> tests/fixtures/advchart-canvas-states.json
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
// (the dist sets env.node under node, and Series.isAnimationEnabled then
// refuses every transition: a state's too)
echarts.env.node = false;
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-canvas-states.json');
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
  const put = () => { if (!pending) { owner = CUR; pending = true; } };
  const styleName = v => (v && typeof v === 'object' ? '[grad]' : String(v));
  const opNote = op => {
    pending = false;
    if (!owner) return;
    let o = OPS.get(owner);
    if (!o) { o = []; OPS.set(owner, o); }
    o.push({ op, ga: hex(st.globalAlpha), fs: styleName(st.fillStyle), ss: styleName(st.strokeStyle),
      lw: hex(st.lineWidth), ld: st.lineDash.map(hex), ldo: hex(st.lineDashOffset), sc: String(st.shadowColor),
      sb: hex(st.shadowBlur), sox: hex(st.shadowOffsetX), soy: hex(st.shadowOffsetY), cap: st.lineCap,
      join: st.lineJoin, ml: hex(st.miterLimit), m: st.m.map(hex) });
  };
  const ctx = {
    canvas,
    dpr: 1,
    save() { stack.push(Object.assign({}, st, { m: st.m.slice(), lineDash: st.lineDash.slice() })); },
    restore() { const s = stack.pop(); if (s) Object.assign(st, s); },
    setTransform(a, b, c, d, e, f) { if ([a, b, c, d, e, f].every(v => isFinite(v))) st.m = [a, b, c, d, e, f]; },
    fill() { opNote('fill'); },
    stroke() { opNote('stroke'); },
    beginPath() { pending = false; owner = null; },
    clip() { pending = false; owner = null; },
    moveTo() { put(); },
    lineTo() { put(); },
    rect() { put(); },
    bezierCurveTo() { put(); },
    quadraticCurveTo() { put(); },
    arc() { put(); },
    ellipse() { put(); },
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
const vv = (s, more) => Object.assign({ animation: false, color: PAL, xAxis: { show: false, type: 'value', min: 0, max: 10 },
  yAxis: { show: false, type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
// the element before: a shadow, a cap / join / miterLimit, a dash and its phase, a width
const BEFORE = { color: '#ff0000', borderColor: '#0000ff', borderWidth: 3, borderType: 'dashed', borderDashOffset: 5,
  borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4, shadowBlur: 6, shadowColor: '#00ff00' };
const HI = (s, d) => ({ type: 'highlight', seriesIndex: s, dataIndex: d });
const SC = (data, more) => Object.assign({ type: 'scatter', symbol: 'rect', symbolSize: 16, emphasis: { scale: false }, data }, more || {});
function cases() {
  return [
    // ---- 1. an emphasis of refused values, after an element of its own ----
    ['st-emph-shadow', vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080' }, emphasis: { itemStyle: { shadowBlur: -3, shadowColor: '#ff00ff' } } },
      { value: [8, 5], itemStyle: { color: '#808080' }, emphasis: { itemStyle: { shadowBlur: 4, shadowColor: 'nope' } } }])),
    [0, 10], { acts: { 1: [HI(0, 1), HI(0, 2)] } }],
    ['st-emph-pen', vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { borderCap: 'Round', borderJoin: 'foo', borderMiterLimit: -2 } } },
      { value: [8, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2, borderType: [4, 4] },
        emphasis: { itemStyle: { borderDashOffset: 'abc' } } }])),
    [0, 10], { acts: { 1: [HI(0, 1), HI(0, 2)] } }],
    ['st-emph-colour', vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { color: 'nope', borderColor: 'bad' } } },
      { value: [8, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { borderWidth: 'Infinity' } } }])),
    [0, 10], { acts: { 1: [HI(0, 1), HI(0, 2)] } }],
    // and back at rest: downplay
    ['st-downplay', vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { shadowBlur: -3, shadowColor: '#ff00ff', borderCap: 'Round' } } }])),
    [0, 10, 20], { acts: { 1: [HI(0, 1)], 2: [{ type: 'downplay', seriesIndex: 0, dataIndex: 1 }] } }],
    // ---- 2. a line's emphasis lineStyle (its polyline, after another series' unclipped) ----
    ['st-emph-line', vv([{ type: 'line', showSymbol: false, clip: false, data: [[1, 2], [9, 3]],
      lineStyle: { color: '#ff0000', width: 3, type: 'dashed', dashOffset: 5, cap: 'round', join: 'bevel',
        miterLimit: 4, shadowBlur: 6, shadowColor: '#00ff00' } },
    { type: 'line', showSymbol: false, clip: false, data: [[1, 6], [5, 8], [9, 6]],
      lineStyle: { color: '#808080', width: 2, type: [4, 4] },
      emphasis: { lineStyle: { cap: 'Round', join: 'foo', miterLimit: -2, dashOffset: 'abc', shadowBlur: -3,
        shadowColor: '#ff00ff', width: 'Infinity' } } }]),
    [0, 10], { acts: { 1: [{ type: 'highlight', seriesIndex: 1 }] } }],
    // ---- 3. blur and select ----
    ['st-blur', vv([SC([{ value: [2, 5], itemStyle: BEFORE }], { clip: false, emphasis: { scale: false, focus: 'series' } }),
      SC([{ value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 } }],
        { clip: false, blur: { itemStyle: { shadowBlur: -3, shadowColor: '#ff00ff', borderCap: 'Round', borderJoin: 'foo' } } })]),
    [0, 10], { acts: { 1: [HI(0, 0)] } }],
    ['st-select', vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 } }],
    { selectedMode: 'single', select: { itemStyle: { shadowBlur: -3, shadowColor: '#ff00ff', borderCap: 'Round',
      borderMiterLimit: -1, color: 'nope', borderColor: '#123456' } } })),
    [0, 10], { acts: { 1: [{ type: 'select', seriesIndex: 0, dataIndex: 1 }] } }],
    // ---- 4. a bar's emphasis ----
    ['st-emph-bar', vv({ type: 'bar', barWidth: 20, data: [{ value: [3, 5], itemStyle: BEFORE },
      { value: [6, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { shadowBlur: -3, shadowColor: '#ff00ff', borderCap: 'Round', borderJoin: 'foo',
          borderMiterLimit: 0 } } }] }),
    [0, 10], { acts: { 1: [HI(0, 1)] } }],
    // ---- 5. a state's transition tweening into refused values ----
    ['st-tween-blur', Object.assign(vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', shadowBlur: 4, shadowColor: '#ff00ff' },
        emphasis: { itemStyle: { shadowBlur: -4 } } },
      { value: [8, 5], itemStyle: { color: '#808080', shadowColor: '#ff00ff' },
        emphasis: { itemStyle: { shadowBlur: -6, borderWidth: 0 } } }])), { animation: true, animationDuration: 100 }),
    [600, 1000, 1030, 1100, 1180, 1250, 1400, 1600], { acts: { 1: [HI(0, 1), HI(0, 2)],
      6: [{ type: 'downplay', seriesIndex: 0, dataIndex: 1 }] } }],
    // a phase of no number (discrete), of 'Infinity' (tweened: no finite number past the start),
    // a width of 'Infinity', colours no parser reads
    ['st-tween-pen', Object.assign(vv(SC([{ value: [1, 5], itemStyle: BEFORE },
      { value: [3, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2, borderType: [4, 4], borderDashOffset: 3 },
        emphasis: { itemStyle: { borderDashOffset: 'abc' } } },
      { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2, borderType: [4, 4], borderDashOffset: 3 },
        emphasis: { itemStyle: { borderDashOffset: 'Infinity' } } },
      { value: [7, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2 },
        emphasis: { itemStyle: { borderWidth: 'Infinity' } } },
      { value: [9, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2, shadowBlur: 2, shadowColor: '#ff00ff' },
        emphasis: { itemStyle: { color: 'nope', borderColor: 'bad', shadowColor: 'nope', shadowBlur: 3 } } },
      // (a rest phase refused, a state's taken: a discrete track, set at once)
      { value: [9, 8], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2, borderType: [4, 4],
        borderDashOffset: 'abc' }, emphasis: { itemStyle: { borderDashOffset: 2 } } }])),
    { animation: true, animationDuration: 100 }),
    [600, 1000, 1030, 1100, 1250, 1400], { acts: { 1: [HI(0, 1), HI(0, 2), HI(0, 3), HI(0, 4), HI(0, 5)] } }],
    // [mutation round] a value refused at rest, a state's that is taken
    // (the rest's settled mark goes): a blur, a cap, a join, a miterLimit
    ['st-rest-refused', vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 2, shadowBlur: -2,
        shadowColor: '#ff00ff', borderCap: 'Round', borderJoin: 'foo', borderMiterLimit: -3, borderType: [4, 4],
        borderDashOffset: 'abc' },
      emphasis: { itemStyle: { shadowBlur: 5, borderCap: 'square', borderJoin: 'round', borderMiterLimit: 7,
        borderDashOffset: 2 } } },
      { value: [8, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 'Infinity' },
        emphasis: { itemStyle: { borderWidth: 4 } } }])),
    [0, 10, 20], { acts: { 1: [HI(0, 1), HI(0, 2)], 2: [{ type: 'downplay', seriesIndex: 0 }] } }],
    // an emphasis width of 'Infinity' after an element of another width; a
    // phase refused over a rest of nought
    ['st-emph-inf', vv(SC([{ value: [2, 5], itemStyle: { color: '#ff0000', borderColor: '#0000ff', borderWidth: 5,
      borderType: [3, 3], borderDashOffset: 4 } },
    { value: [5, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 1 },
      emphasis: { itemStyle: { borderWidth: 'Infinity' } } },
    { value: [8, 5], itemStyle: { color: '#808080', borderColor: '#000', borderWidth: 1, borderType: [2, 2] },
      emphasis: { itemStyle: { borderDashOffset: 'Infinity' } } }])),
    [0, 10], { acts: { 1: [HI(0, 1), HI(0, 2)] } }],
    // a map region's emphasis (the geo reader's shadow keys)
    ['st-map', { animation: false, color: PAL, series: [{ type: 'map', map: 'r7ysq', label: { show: false },
      itemStyle: { areaColor: '#808080', borderColor: '#000', borderWidth: 1 },
      emphasis: { label: { show: false }, itemStyle: { areaColor: '#00ffff', shadowBlur: -3, shadowColor: 'nope' } },
      data: [{ name: 'P', itemStyle: { areaColor: '#ff0000', shadowBlur: 6, shadowColor: '#00ff00' } }, { name: 'Q' }] }] },
    [0, 10], { acts: { 1: [{ type: 'highlight', seriesIndex: 0, name: 'Q' }] } }],
    // a blur below nought at rest, tweened to one above (refused until it crosses)
    ['st-tween-rest-neg', Object.assign(vv(SC([{ value: [2, 5], itemStyle: BEFORE },
      { value: [5, 5], itemStyle: { color: '#808080', shadowBlur: -2, shadowColor: '#ff00ff' },
        emphasis: { itemStyle: { shadowBlur: 5 } } }])), { animation: true, animationDuration: 100 }),
    [600, 1000, 1030, 1060, 1100, 1250, 1400], { acts: { 1: [HI(0, 1)] } }],
    // [R7-AB] a shadow blur or offset written as a string of no finite
    // number: `dpr * ('abc' || 0)` is none, refused (the canvas' kept); a
    // numeric string its Number ('0x4' 4, '' nought); at rest a string
    // refused, a state's taken
    ['st-emph-shadow-str', vv(SC([{ value: [2, 5], itemStyle: Object.assign({}, BEFORE, { shadowOffsetX: 3, shadowOffsetY: 2 }) },
      { value: [4, 5], itemStyle: { color: '#808080', shadowBlur: 2, shadowColor: '#ff00ff' },
        emphasis: { itemStyle: { shadowBlur: 'abc', shadowOffsetX: 'x', shadowOffsetY: 'Infinity' } } },
      { value: [6, 5], itemStyle: { color: '#808080', shadowColor: '#0000ff', shadowBlur: 1 },
        emphasis: { itemStyle: { shadowBlur: '0x4', shadowOffsetX: '5', shadowOffsetY: '' } } },
      { value: [8, 5], itemStyle: { color: '#808080', shadowBlur: 'zz', shadowColor: '#0000ff', shadowOffsetX: 'q' },
        emphasis: { itemStyle: { shadowBlur: 3, shadowOffsetX: 4 } } }])),
    [0, 10, 20], { acts: { 1: [HI(0, 1), HI(0, 2), HI(0, 3)], 2: [{ type: 'downplay', seriesIndex: 0 }] } }],
    // the same in a transition: a string of no number a discrete track (set
    // at once), 'Infinity' interpolated (none past the start)
    ['st-tween-shadow-str', Object.assign(vv(SC([{ value: [2, 5], itemStyle: Object.assign({}, BEFORE, { shadowOffsetX: 3, shadowOffsetY: 2 }) },
      { value: [4, 5], itemStyle: { color: '#808080', shadowBlur: 2, shadowColor: '#ff00ff', shadowOffsetX: 1 },
        emphasis: { itemStyle: { shadowBlur: 'abc', shadowOffsetX: 'x', shadowOffsetY: 'Infinity' } } },
      { value: [6, 5], itemStyle: { color: '#808080', shadowColor: '#0000ff', shadowBlur: 1 },
        emphasis: { itemStyle: { shadowBlur: '0x4', shadowOffsetX: '5' } } }])), { animation: true, animationDuration: 100 }),
    [600, 1000, 1030, 1060, 1100, 1250], { acts: { 1: [HI(0, 1), HI(0, 2)] } }],
  ];
}

function track(chart) {
  const map = new Map();
  chart.getModel().eachSeries((sm, si) => {
    const type = sm.subType;
    const data = sm.getData();
    if (type === 'scatter') {
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        const p = g && g.childAt(0);
        if (p) map.set(p, 's' + si + '.' + i);
      }
    }
    else if (type === 'map') {
      // a region's displayables in order
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        if (!g) continue;
        let n = 0;
        const visit = e => {
          if (e.isGroup) { for (const c of e.childrenRef()) visit(c); return; }
          if (e.style && e.type !== 'text' && !map.has(e)) map.set(e, 'g' + si + '.' + i + '.' + (n++));
        };
        visit(g);
      }
    }
    else if (type === 'bar' || type === 'pie') {
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        if (g) map.set(g, (type === 'bar' ? 'b' : 'p') + si + '.' + i);
      }
    }
    else if (type === 'line') {
      const view = chart.getViewOfSeriesModel(sm);
      if (view && view._polyline) map.set(view._polyline, 'ln' + si + '.0');
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        const p = g && g.childAt && g.childAt(0);
        if (p) map.set(p, 'ls' + si + '.' + i);
      }
    }
  });
  return map;
}

// two squares, P and Q, as a GeoJSON map
const SQ = (x0, y0, x1, y1) => [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]];
const MAPS = [{ name: 'r7ysq', geo: { type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'P' }, geometry: { type: 'Polygon', coordinates: [SQ(0, 0, 8, 8)] } },
  { type: 'Feature', properties: { name: 'Q' }, geometry: { type: 'Polygon', coordinates: [SQ(8, 0, 16, 8)] } }] } }];
for (const m of MAPS) echarts.registerMap(m.name, m.geo);

function run(id, option, samples, opts) {
  NOW = T_BASE;
  rngState = SEED;
  CUR = null;
  opts = opts || {};
  const dom = fakeCanvas(CW, CH);
  const chart = echarts.init(dom, null, { renderer: 'canvas', width: CW, height: CH, devicePixelRatio: 1 });
  const L = chart.getZr().painter.getLayer(0).constructor.prototype;
  if (!L.__r7yClear) {
    const orig = L.clear;
    L.clear = function () { OPS = new Map(); return orig.apply(this, arguments); };
    L.__r7yClear = true;
  }
  const frames = [];
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    for (let si = 0; si < samples.length; si++) {
      NOW = T_BASE + samples[si];
      CUR = null;
      if (opts.acts && opts.acts[si]) for (const a of opts.acts[si]) chart.dispatchAction(a);
      chart.getZr().animation.update();
      chart.getZr().refreshImmediately(true);
      const els = [];
      for (const [el, key] of track(chart)) els.push({ key, ops: OPS.get(el) || [] });
      els.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
      frames.push({ t: samples[si], els });
    }
  }
  finally {
    chart.dispose();
  }
  return Object.assign({ id, option }, opts.acts ? { acts: opts.acts } : {}, { frames });
}

function generate() {
  const charts = cases().map(([id, o, s, opts]) => run(id, o, s, opts));
  const op = (id, fi, key) => charts.find(c => c.id === id).frames[fi].els.find(e => e.key === key).ops[0];
  // a refused blur in an emphasis: the one the element before left
  must(op('st-emph-shadow', 1, 's0.1').sb === hex(6), 'st-emph-shadow: the blur not kept');
  must(op('st-emph-pen', 1, 's0.1').cap === 'round', 'st-emph-pen: the cap not kept');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node, zrender canvas painter on a recording context',
    note: 'R7-Y: per case and sample t (ms after T0; the actions dispatched, the clock stepped, the canvas refreshed), '
      + 'each tracked element (s a scatter symbol, b a bar, ln a polyline, ls a line symbol, p a sector) with every '
      + 'fill() / stroke() of its path and the context then: a browser\'s setters refuse a negative blur, a cap / join '
      + 'no canvas word, a miterLimit or width not above nought or not finite, a phase not finite, a colour no parser reads.',
    W: CW, H: CH, T0: T_BASE, maps: MAPS.map(m => ({ name: m.name, text: JSON.stringify(m.geo) })), charts };
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
