// Round 7 R7-S: WHAT THE CANVAS ITSELF IS LEFT WITH when a lines series'
// effect symbol and the end symbols are brushed -- two things the elements'
// own styles do not say.
//
// 1. THE SHADOW OF A GRADIENT-COLOURED EFFECT SYMBOL. EffectLine sets
//    `symbol.setStyle('shadowColor', color)` where color is effect.color (or
//    the line's stroke): a gradient object there. zrender's bindCommonProps
//    assigns `ctx.shadowColor = style.shadowColor || '#000'` whenever it
//    differs from the previous element's; a canvas refuses a value that is not
//    a colour string and keeps the one it had -- the shadowColor the element
//    brushed before it left (an element with none leaves zrender's '#000'; a
//    solid effect symbol its own colour; an element with a shadowColor written
//    that colour).
// 2. A SIZE WRITTEN AS A ONE-NUMBER PAIR. An end symbol's `[12]`
//    (symbolSize: [[12], ...], edgeSymbolSize the same): Line.createSymbol's
//    normalizeSymbolSize makes it [12, 0], a box of no height. An effect's
//    `symbolSize: [12]`: scaleY undefined, the transform not a number, and the
//    painter culls the symbol (culling: true) -- never brushed. A scatter's
//    `symbolSize: [12]`: Symbol.ts' [12, 0], scaleY 0.
//
// From the real ECharts 6.1 dist, RENDERED BY ZRENDER'S CANVAS PAINTER on a
// recording context (pen-map.js' recipe: echarts.init on a stand-in canvas,
// renderer 'canvas', devicePixelRatio 1) whose shadowColor setter takes only
// a string, as a browser's does (a gradient object is refused: the old value
// stays), the canvas' own default 'rgba(0, 0, 0, 0)' at the start. The clock
// is replaced: every case starts at T0 = 1700000000000; at each sample t the
// clock is T0 + t, zr.animation.update() (its stage flush paints: the
// clips stepped once, as zrender's own frame), zr.refreshImmediately(true).
//
// Per case and sample (`frames`): t, and per tracked element (an effect
// symbol `e<series>.<row>`, an end symbol `f...` / `t...`, a scatter's symbol
// `s<series>.<row>`, a graph edge's ends `gf...` / `gt...`):
//   ignore     el.ignore
//   sx, sy     scaleX, scaleY (hex; null where not a number)
//   box        [x, y, w, h] of the symbol's shape (hex)
//   brushes    (an effect symbol) every fill() / stroke() made while it was
//              being brushed: {op, sc (ctx.shadowColor then), sb
//              (ctx.shadowBlur, hex), m (the context's transform [a, b, c, d,
//              e, f], hex: setTransform refuses a value that is not finite)}
// Run: node tools/advchart-oracle/lines-canvas.js -> tests/fixtures/advchart-lines-canvas.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-lines-canvas.json');
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
const hexOrNull = v => (typeof v === 'number' && !Number.isNaN(v) ? hex(v) : null);

// ---------- the recording canvas ----------
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;
const Displayable = Object.getPrototypeOf(Path.prototype).constructor;
let CUR = null;
const origIBB = Displayable.prototype.innerBeforeBrush;
Displayable.prototype.innerBeforeBrush = function () { CUR = this; return origIBB.apply(this, arguments); };
let BRUSHES = [];
function makeCtx(canvas) {
  // the canvas' own defaults: a transparent black shadow of no blur
  const st = { shadowColor: 'rgba(0, 0, 0, 0)', shadowBlur: 0, m: [1, 0, 0, 1, 0, 0] };
  const stack = [];
  const note = op => { if (CUR) BRUSHES.push({ el: CUR, op, sc: st.shadowColor, sb: st.shadowBlur, m: st.m.slice() }); };
  const ctx = {
    canvas,
    dpr: 1,
    save() { stack.push(Object.assign({}, st, { m: st.m.slice() })); },
    restore() { const s = stack.pop(); if (s) Object.assign(st, s); },
    // a browser's: a transform with a value that is not finite is refused
    setTransform(a, b, c, d, e, f) { if ([a, b, c, d, e, f].every(v => isFinite(v))) st.m = [a, b, c, d, e, f]; },
    fill() { note('fill'); },
    stroke() { note('stroke'); },
    setLineDash() {},
    getLineDash() { return []; },
    measureText(t) { return { width: String(t).length * 6 }; },
    createLinearGradient() { return { addColorStop() {} }; },
    createRadialGradient() { return { addColorStop() {} }; },
    createPattern() { return {}; },
    getImageData() { return { data: [] }; },
    isPointInPath() { return false; },
  };
  return new Proxy(ctx, {
    get: (t, k) => {
      if (k === 'shadowColor') return st.shadowColor;
      if (k === 'shadowBlur') return st.shadowBlur;
      if (k in t) return t[k];
      if (typeof k === 'string' && /^[a-z]/.test(k)) return function () {};
      return undefined;
    },
    set: (t, k, v) => {
      // a browser's setter: a string is parsed (every string here is a
      // colour), anything else is refused and the value stays
      if (k === 'shadowColor') { if (typeof v === 'string') st.shadowColor = v; }
      else if (k === 'shadowBlur') { if (typeof v === 'number' && isFinite(v) && v >= 0) st.shadowBlur = v; }
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
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#ff8800' }, { offset: 1, color: '#0088ff' }] };
const vv = (s, more) => Object.assign({ animation: false, xAxis: { show: false, type: 'value', min: 0, max: 10 },
  yAxis: { show: false, type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const LN = (eff, data, more) => Object.assign({ type: 'lines', coordinateSystem: 'cartesian2d',
  lineStyle: { color: '#999', opacity: 1 }, effect: Object.assign({ show: true, trailLength: 0, delay: 0, period: 4,
    symbol: 'circle', symbolSize: 10 }, eff), data }, more || {});
const ROWS2 = [{ coords: [[1, 8], [9, 8]] }, { coords: [[1, 3], [9, 3]] }];

function cases() {
  return [
    // ---- 1. a gradient effect symbol's shadow ----
    ['grad-alone', vv(LN({ color: GRAD, shadowBlur: 6 }, ROWS2)), [0, 400, 1200]],
    ['grad-solid-first', vv(LN({ color: GRAD, shadowBlur: 5 }, [
      { coords: [[1, 8], [9, 8]], effect: { color: '#ff0000', delay: 1000 } },
      { coords: [[1, 3], [9, 3]] }])), [0, 500, 1500, 2500]],
    ['grad-line-shadow', vv(LN({ color: GRAD, shadowBlur: 4 }, ROWS2,
      { lineStyle: { color: '#999', opacity: 1, shadowColor: '#0000ff', shadowBlur: 2 } })), [0, 600]],
    // a solid one with no shadow of its own still hands the canvas its colour
    ['grad-after-unshadowed', vv(LN({ color: GRAD }, [
      { coords: [[1, 8], [9, 8]], effect: { color: '#ff0000' } },
      { coords: [[1, 3], [9, 3]], effect: { shadowBlur: 5 } }])), [0, 600]],
    // two series' clips over shown axes: the restore returns to what the axes left, '#000'
    ['grad-two-series-axes', Object.assign(vv([LN({ color: '#00ffff', shadowBlur: 2 }, [{ coords: [[1, 8], [9, 8]] }]),
      LN({ color: GRAD, shadowBlur: 3 }, [{ coords: [[1, 3], [9, 3]] }])]),
    { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 } }), [0, 600]],
    ['grad-written', vv(LN({ color: GRAD, shadowBlur: 4, shadowColor: '#00ff00' }, ROWS2)), [0, 600]],
    ['grad-line-colour', vv(LN({ shadowBlur: 3 }, ROWS2, { lineStyle: { color: GRAD, opacity: 1 } })), [0, 600]],
    ['grad-two-series', vv([LN({ color: '#00ffff', shadowBlur: 2 }, [{ coords: [[1, 8], [9, 8]] }]),
      LN({ color: GRAD, shadowBlur: 3 }, [{ coords: [[1, 3], [9, 3]] }])]), [0, 600]],
    ['grad-polyline', vv(LN({ color: GRAD, shadowBlur: 4 }, [{ coords: [[1, 8], [5, 2], [9, 8]] }],
      { polyline: true })), [0, 600]],
    // ---- 2. a size written as a one-number pair ----
    ['one-size-ends', vv(LN({ show: false }, [
      { coords: [[1, 8], [9, 8]] },
      { coords: [[1, 3], [9, 3]], symbolSize: [[14], 6] }],
      { symbol: ['circle', 'rect'], symbolSize: [[12], 10] })), [0]],
    ['one-size-effect', vv(LN({ symbol: 'circle', symbolSize: [12] }, ROWS2)), [0, 600]],
    // a trail's symbol: scaleY the step's from the second frame on
    ['one-size-effect-rect', vv(LN({ symbol: 'rect', symbolSize: [12] }, ROWS2)), [0, 600]],
    ['one-size-effect-item', vv(LN({ symbol: 'circle', symbolSize: 8 }, [
      { coords: [[1, 8], [9, 8]] }, { coords: [[1, 3], [9, 3]], effect: { symbolSize: [14] } }])), [0, 600]],
    ['one-size-graph', { animation: false, series: [{ type: 'graph', layout: 'none', left: 50, top: 50, width: 300,
      height: 200, edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: [[12], 10], label: { show: false },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 50, y: 100 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c', symbolSize: [[16], [8]] }] }] }, [0]],
    ['one-size-scatter', vv({ type: 'scatter', symbolSize: [12], data: [[2, 2], [5, 5],
      { value: [8, 8], symbolSize: [6, 9] }] }), [0]],
  ];
}

function track(chart) {
  const map = new Map();
  const model = chart.getModel();
  model.eachSeries((sm, si) => {
    const type = sm.subType;
    if (type === 'lines') {
      const data = sm.getData();
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        if (!g) continue;
        // an EffectLine holds its Line group first, then the effect symbol
        const eff = g.childAt(0) && g.childAt(0).isGroup ? g.childAt(1) : null;
        const line = eff ? g.childAt(0) : g;
        if (eff) map.set(eff, 'e' + si + '.' + i);
        const f = line && line.childOfName && line.childOfName('fromSymbol');
        const t = line && line.childOfName && line.childOfName('toSymbol');
        if (f) map.set(f, 'f' + si + '.' + i);
        if (t) map.set(t, 't' + si + '.' + i);
      }
    }
    else if (type === 'graph') {
      const ed = sm.getEdgeData();
      for (let i = 0; i < ed.count(); i++) {
        const line = ed.getItemGraphicEl(i);
        if (!line) continue;
        const f = line.childOfName('fromSymbol');
        const t = line.childOfName('toSymbol');
        if (f) map.set(f, 'gf' + si + '.' + i);
        if (t) map.set(t, 'gt' + si + '.' + i);
      }
    }
    else if (type === 'scatter') {
      const data = sm.getData();
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        const p = g && g.childAt(0);
        if (p) map.set(p, 's' + si + '.' + i);
      }
    }
  });
  return map;
}

function elRec(el, key, brushes) {
  const s = el.shape || {};
  const r = {
    key, ignore: !!el.ignore, sx: hexOrNull(el.scaleX), sy: hexOrNull(el.scaleY),
    box: [s.x, s.y, s.width, s.height].map(hexOrNull),
  };
  // an effect symbol's own brushes (a symbol that can batch -- no shadow --
  // is filled at a later flush, under another element: only the effect
  // symbols are recorded, and the shadow cases give theirs a blur)
  if (key[0] === 'e') r.brushes = brushes.filter(b => b.el === el).map(b => ({ op: b.op, sc: String(b.sc), sb: hex(b.sb), m: b.m.map(hex) }));
  return r;
}

function run(id, option, samples) {
  NOW = T_BASE;
  rngState = SEED;
  CUR = null;
  const dom = fakeCanvas(W, H);
  const chart = echarts.init(dom, null, { renderer: 'canvas', width: W, height: H, devicePixelRatio: 1 });
  const frames = [];
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    for (const t of samples) {
      NOW = T_BASE + t;
      BRUSHES = [];
      CUR = null;
      // zrender's own frame: the clips stepped once, then the stage's flush
      // paints what they moved (a refresh from outside would step them a
      // second time at the same instant: a trail's scaleY falls back to the
      // symbol's size); then whatever is still to paint, without a step
      chart.getZr().animation.update();
      chart.getZr().refreshImmediately(true);
      const map = track(chart);
      const els = [];
      for (const [el, key] of map) els.push(elRec(el, key, BRUSHES));
      els.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
      frames.push({ t, els });
    }
  }
  finally {
    chart.dispose();
  }
  return { id, option, frames };
}

function generate() {
  const charts = cases().map(([id, o, s]) => run(id, o, s));
  const by = id => charts.find(c => c.id === id);
  const el = (id, fi, key) => by(id).frames[fi].els.find(e => e.key === key);
  // a gradient effect symbol shadowed in what the canvas had: zrender's #000
  must(el('grad-alone', 1, 'e0.0').brushes.every(b => b.sc === '#000'), 'grad-alone: not #000');
  // after a red one, red
  must(el('grad-solid-first', 2, 'e0.1').brushes.every(b => b.sc === '#ff0000'), 'grad-solid-first: not red');
  // a one-number effect size is never brushed
  // a one-number effect size: brushed, its transform not a number -- the
  // canvas refuses it and keeps the one it had
  must(el('one-size-effect', 1, 'e0.0').sy === null, 'one-size-effect: a scaleY');
  // a one-number end size: a box of no height
  must(el('one-size-ends', 0, 'f0.0').box[3] === hex(0), 'one-size-ends: height');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node, zrender canvas painter on a recording context',
    note: 'R7-S: per case and sample t (ms after T0, the clock stepped and the canvas refreshed), the tracked elements -- '
      + 'e<series>.<row> a lines effect symbol, f / t its end symbols, gf / gt a graph edge\'s, s a scatter\'s symbol -- with '
      + 'ignore, scaleX / scaleY (hex, null not a number), the shape box [x, y, w, h] and every fill() / stroke() made while '
      + 'it was brushed: the context\'s shadowColor (a string setter, the canvas default rgba(0, 0, 0, 0)) and shadowBlur.',
    W, H, T0: T_BASE, charts };
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
