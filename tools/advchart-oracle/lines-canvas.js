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
//
// Round 7 R7-V (the cases named `v-...`): the recording context refuses what a
// browser's refuses, setter by setter (the HTML spec's "on setting, ...
// ignored", after WebIDL's conversion): globalAlpha outside 0..1 or not
// finite, lineWidth / miterLimit not above 0 or not finite, lineDashOffset /
// shadowOffsetX / shadowOffsetY not finite, shadowBlur below 0 or not finite,
// lineCap / lineJoin / globalCompositeOperation not one of their words,
// fillStyle / strokeStyle / shadowColor neither a gradient or pattern of this
// context nor a string a CSS colour parser takes (zrender's own
// color.parse stands in for the browser's: hex, rgb[a](), hsl[a](), the
// named colours and 'transparent'). Per tracked element and sample, beyond
// the R7-S record: `st`, the context's state once the element was brushed
// (ga globalAlpha, sc / sb / sox / soy the shadow, fs / ss fill and stroke
// style -- a gradient '[grad]' --, lw, cap, join, ml miterLimit, m the
// transform); `ops`, every fill() / stroke() of its path with the alpha then
// (a batched path is filled at a later flush: the owner is the element whose
// brush began the path); `pb`, the bounds of the path it built, on the
// canvas, and `pa` the area it encloses. A case may name probes: `hits`, [x, y, the key findHover's target
// has (null: none, 'other' an untracked element)].
//
// Round 7 R7-W (the cases named `w-...`, recorded as the v- ones and more):
// setLineDash refuses a list with a value that is not finite or below 0 (an
// odd one is doubled), and every fill() / stroke() / fillText() /
// strokeText() of a tracked element records the context then (`ops`: fs / ss
// fill and stroke style, lw, ld the dash, ldo its phase, sc / sb the shadow,
// m the transform); the state once brushed holds ld / ldo too. More elements
// are tracked: a bar `b`, a pie's sector `p`, a line's symbol `ls` and area
// `la`, a label's last text span `x<key>`, a legend's displayables `lg<i>.<n>`
// in paint order, and the text spans of the axes `ax<n>`. A case may init with
// useDirtyRect: each repaint block (`blocks`, the rect, null the whole canvas)
// numbers the ops brushed in it (`blk`), and an element brushed in two
// blocks keeps every state (`sts`). A case may set an option before a sample
// (`sets`).
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
// [R7-V] the record of the cases named v-...
let V2 = false;
// [R7-W] the record of the cases named w-...
let W = false;
let BLK = 0;
let BLOCKS = [];
let SNAPL = new Map();
let SNAPS = new Map();
let OPS = new Map();
let PATHS = new Map();
let SNAP = null;
const origIBB = Displayable.prototype.innerBeforeBrush;
Displayable.prototype.innerBeforeBrush = function () { CUR = this; return origIBB.apply(this, arguments); };
const origIAB = Displayable.prototype.innerAfterBrush;
Displayable.prototype.innerAfterBrush = function () {
  if (V2 && SNAP) SNAPS.set(this, SNAP());
  if (W && SNAP) {
    let l = SNAPL.get(this);
    if (!l) { l = []; SNAPL.set(this, l); }
    l.push(Object.assign({ blk: BLK }, SNAP()));
  }
  return origIAB.apply(this, arguments);
};
let BRUSHES = [];
// WebIDL's conversion of a double, then the setter's own refusal
const toNum = v => (typeof v === 'symbol' ? NaN : +v);
const CAPS = ['butt', 'round', 'square'];
const JOINS = ['round', 'bevel', 'miter'];
const COMPOSITES = ['source-over', 'source-in', 'source-out', 'source-atop', 'destination-over', 'destination-in',
  'destination-out', 'destination-atop', 'lighter', 'copy', 'xor', 'multiply', 'screen', 'overlay', 'darken',
  'lighten', 'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference', 'exclusion', 'hue',
  'saturation', 'color', 'luminosity'];
const isCssColour = v => !!echarts.color.parse(String(v));
function makeCtx(canvas) {
  // the canvas' own defaults: a transparent black shadow of no blur
  const st = { shadowColor: 'rgba(0, 0, 0, 0)', shadowBlur: 0, m: [1, 0, 0, 1, 0, 0],
    globalAlpha: 1, lineWidth: 1, lineCap: 'butt', lineJoin: 'miter', miterLimit: 10, lineDashOffset: 0,
    shadowOffsetX: 0, shadowOffsetY: 0, fillStyle: '#000000', strokeStyle: '#000000',
    globalCompositeOperation: 'source-over', lineDash: [] };
  const stack = [];
  const note = op => { if (CUR) BRUSHES.push({ el: CUR, op, sc: st.shadowColor, sb: st.shadowBlur, m: st.m.slice() }); };
  // [R7-V] the path being built, its owner and its points on the canvas
  let owner = null;
  let pending = false;
  const at = (x, y) => [st.m[0] * x + st.m[2] * y + st.m[4], st.m[1] * x + st.m[3] * y + st.m[5]];
  // [R7-W] the points of the path being built, kept for its owner only
  // once it is filled or stroked (a clip path built under the element
  // before is not its)
  let pend = [];
  const put = (x, y) => {
    if (!V2) return;
    if (!pending) { owner = CUR; pending = true; }
    if (!owner) return;
    if (W) { pend.push(at(x, y)); return; }
    let p = PATHS.get(owner);
    if (!p) { p = []; PATHS.set(owner, p); }
    p.push(at(x, y));
  };
  let px = 0;
  let py = 0;
  const styleName = v => (v && typeof v === 'object' ? '[grad]' : String(v));
  // [R7-W] the context a fill or a stroke is made with
  const opState = () => ({ fs: styleName(st.fillStyle), ss: styleName(st.strokeStyle), lw: hex(st.lineWidth),
    ld: st.lineDash.map(hex), ldo: hex(st.lineDashOffset), sc: String(st.shadowColor), sb: hex(st.shadowBlur),
    sox: hex(st.shadowOffsetX), soy: hex(st.shadowOffsetY), cap: st.lineCap, join: st.lineJoin,
    ml: hex(st.miterLimit), m: st.m.map(hex), blk: BLK });
  const opNote = op => {
    if (!V2) return;
    pending = false;
    if (!owner) return;
    if (W && pend.length) {
      let p = PATHS.get(owner);
      if (!p) { p = []; PATHS.set(owner, p); }
      for (const q of pend) p.push(q);
      pend = [];
    }
    let o = OPS.get(owner);
    if (!o) { o = []; OPS.set(owner, o); }
    if (W) o.push(Object.assign({ op, ga: hex(st.globalAlpha) }, opState()));
    else o.push({ op, ga: hex(st.globalAlpha) });
  };
  // a text's: its span is the owner
  const textNote = op => {
    if (!W || !CUR) return;
    let o = OPS.get(CUR);
    if (!o) { o = []; OPS.set(CUR, o); }
    o.push(Object.assign({ op, ga: hex(st.globalAlpha) }, opState()));
  };
  const ctx = {
    canvas,
    dpr: 1,
    save() { stack.push(Object.assign({}, st, { m: st.m.slice(), lineDash: st.lineDash.slice() })); },
    restore() { const s = stack.pop(); if (s) Object.assign(st, s); },
    // a browser's: a transform with a value that is not finite is refused
    setTransform(a, b, c, d, e, f) { if ([a, b, c, d, e, f].every(v => isFinite(v))) st.m = [a, b, c, d, e, f]; },
    fill() { note('fill'); opNote('fill'); },
    stroke() { note('stroke'); opNote('stroke'); },
    beginPath() { pending = false; owner = null; pend = []; },
    clip() { if (W) { pend = []; pending = false; owner = null; } },
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
      // the canvas' sweep: clockwise from a0 to a1 (anticlockwise the other way)
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
    closePath() {},
    // a browser's: a list with a value not finite or below 0 is refused, an odd one doubled
    setLineDash(a) {
      if (!W) return;
      const v = Array.from(a || [], toNum);
      if (v.some(x => !isFinite(x) || x < 0)) return;
      st.lineDash = v.length % 2 ? v.concat(v) : v;
    },
    getLineDash() { return W ? st.lineDash.slice() : []; },
    fillText() { textNote('fillText'); },
    strokeText() { textNote('strokeText'); },
    measureText(t) { return { width: String(t).length * 6 }; },
    createLinearGradient() { return { addColorStop() {} }; },
    createRadialGradient() { return { addColorStop() {} }; },
    createPattern() { return {}; },
    getImageData() { return { data: [] }; },
    isPointInPath() { return false; },
  };
  const snap = () => ({ ga: hex(st.globalAlpha), sc: String(st.shadowColor), sb: hex(st.shadowBlur),
    sox: hex(st.shadowOffsetX), soy: hex(st.shadowOffsetY), fs: styleName(st.fillStyle), ss: styleName(st.strokeStyle),
    lw: hex(st.lineWidth), cap: st.lineCap, join: st.lineJoin, ml: hex(st.miterLimit), m: st.m.map(hex),
    ...(W ? { ld: st.lineDash.map(hex), ldo: hex(st.lineDashOffset) } : {}) });
  return new Proxy(ctx, {
    get: (t, k) => {
      // the context being drawn on is the one last touched
      SNAP = snap;
      if (k === 'shadowColor') return st.shadowColor;
      if (k === 'shadowBlur') return st.shadowBlur;
      if (V2 && typeof k === 'string' && k !== 'm' && k !== 'lineDash' && Object.prototype.hasOwnProperty.call(st, k)) return st[k];
      if (k in t) return t[k];
      if (typeof k === 'string' && /^[a-z]/.test(k)) return function () {};
      return undefined;
    },
    set: (t, k, v) => {
      SNAP = snap;
      // R7-S's cases: a string is parsed (every string there is a colour),
      // anything else is refused and the value stays; the rest kept as set
      if (!V2) {
        if (k === 'shadowColor') { if (typeof v === 'string') st.shadowColor = v; }
        else if (k === 'shadowBlur') { if (typeof v === 'number' && isFinite(v) && v >= 0) st.shadowBlur = v; }
        else t[k] = v;
        return true;
      }
      // [R7-V] a browser's setter: a value it does not take is refused, the old one stays
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
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#ff8800' }, { offset: 1, color: '#0088ff' }] };
const vv = (s, more) => Object.assign({ animation: false, xAxis: { show: false, type: 'value', min: 0, max: 10 },
  yAxis: { show: false, type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const LN = (eff, data, more) => Object.assign({ type: 'lines', coordinateSystem: 'cartesian2d',
  lineStyle: { color: '#999', opacity: 1 }, effect: Object.assign({ show: true, trailLength: 0, delay: 0, period: 4,
    symbol: 'circle', symbolSize: 10 }, eff), data }, more || {});
const ROWS2 = [{ coords: [[1, 8], [9, 8]] }, { coords: [[1, 3], [9, 3]] }];
// [R7-V] a lines series with no clip (nothing restores the canvas between its elements)
const LNC = (eff, data, more) => LN(eff, data, Object.assign({ clip: false }, more || {}));
const GRAPH_LINKS = [
  { source: 'a', target: 'b', symbol: ['emptyRect', 'line'], symbolSize: [[12], [14]] },
  { source: 'b', target: 'c', symbol: ['pin', 'emptyTriangle'], symbolSize: [[16], [10]] },
  { source: 'c', target: 'd', symbol: ['emptyCircle', 'emptyDiamond'], symbolSize: [[12], [12]] },
  { source: 'd', target: 'a', symbol: ['arrow', 'emptyPin'], symbolSize: [[12], [14]] },
  { source: 'a', target: 'c', symbol: ['emptyRect', 'pin'], symbolSize: [[0, 12], [0, 12]] },
  { source: 'b', target: 'd', symbol: ['emptyArrow', 'emptyRoundRect'], symbolSize: [[12], [12]] },
];
const GR = (links, more) => ({ animation: false, series: [Object.assign({ type: 'graph', layout: 'none', left: 50, top: 50,
  width: 300, height: 200, symbolSize: 4, lineStyle: { width: 0 }, label: { show: false },
  data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 100, y: 100 }, { name: 'd', x: 0, y: 100 }],
  links }, more || {})] });

// [R7-W] the default palette, written: the port's own is its skin's
const PAL = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
function cases() {
  return withPalette([
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
    // the same over a calendar drawn first (its cells: '#000' left before the clips)
    ['grad-two-series-calendar', Object.assign(vv([LN({ color: '#00ffff', shadowBlur: 2 }, [{ coords: [[1, 8], [9, 8]] }]),
      LN({ color: GRAD, shadowBlur: 3 }, [{ coords: [[1, 3], [9, 3]] }])]),
    { calendar: { range: '2024-01', left: 20, top: 260, cellSize: [8, 4] } }), [0, 600]],
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
    // ---- [R7-V] the recording context refusing what a browser refuses ----
    // 1. a graph edge's end written as a one-number pair: a collapsed box
    //    (an empty symbol's edge, a 'line', a pin's head still drawn)
    ['v-graph-collapsed', GR(GRAPH_LINKS), [0], { v2: true, probes: 'ends' }],
    ['v-graph-collapsed-zoom', GR(GRAPH_LINKS, { zoom: 2, center: [50, 50] }), [0], { v2: true, probes: 'ends' }],
    // 2. an effect symbol's transform no number: the canvas keeps the one the
    //    element brushed before it left (an end symbol, a label, another
    //    series' symbol); hit as the unit symbol under the last inverse
    // (a triangle and slanted rows: a circle's box hides a turn)
    ['v-tf-after-end', vv(LNC({ symbol: 'triangle', symbolSize: [12] }, [{ coords: [[1, 8], [9, 5]] }, { coords: [[1, 3], [9, 1]] }], { symbol: ['none', 'arrow'], symbolSize: 10 })),
      [0, 600], { v2: true, probes: 'nan-effects' }],
    ['v-tf-after-label', vv(LNC({ symbolSize: [12] }, ROWS2, { label: { show: true, formatter: 'Ab', position: 'insideStartTop' } })),
      [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-after-label-slant', vv(LNC({ symbol: 'triangle', symbolSize: [12] },
      [{ coords: [[1, 8], [9, 5]] }, { coords: [[1, 3], [9, 1]] }],
      { label: { show: true, formatter: 'Ab', position: 'insideStartTop' } })),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-after-label-end', vv(LNC({ symbolSize: [12] }, ROWS2, { label: { show: true, formatter: 'Ab', position: 'end' } })),
      [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-after-scatter', vv([LNC({ symbolSize: [12] }, ROWS2),
      { type: 'scatter', symbolSize: [8, 6], symbolRotate: 30, data: [[3, 5], [6, 6]] }]),
    [0, 600], { v2: true, probes: 'nan-effects' }],
    // a bar series' label (z2 above its bar, below the effect symbols)
    ['v-tf-after-bar-label', vv([LNC({ symbol: 'triangle', symbolSize: [12] }, ROWS2),
      { type: 'bar', data: [[3, 4], [6, 5]], label: { show: true, rotate: 30 } }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-sh-bar-label', vv([LNC({ color: GRAD, shadowBlur: 4 }, ROWS2),
      { type: 'bar', data: [[3, 4], [6, 5]], label: { show: true, textShadowBlur: 3, textShadowColor: '#ff00ff' } }]),
    [0, 600], { v2: true }],
    // a graph series after it: its last edge's end symbol (a symbol's frame
    // under the view), or its edge's line (the view's transform)
    ['v-tf-after-scatter-z', vv([LNC({ symbol: 'triangle', symbolSize: [12] }, ROWS2,
      { lineStyle: { color: '#999', opacity: 0 } }),
      { type: 'scatter', z: 1, symbolSize: [8, 6], symbolRotate: 30, data: [[3, 5], [6, 6]] }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-after-graph-squash', vv([LNC({ symbol: 'triangle', symbolSize: [12] }, ROWS2),
      { type: 'graph', layout: 'none', left: 60, top: 40, width: 240, height: 60, symbolSize: 3,
        edgeSymbol: ['none', 'arrow'], edgeSymbolSize: 9, lineStyle: { width: 1 },
        data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }], links: [{ source: 'a', target: 'b' }] }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-after-graph-end', vv([LNC({ symbol: 'triangle', symbolSize: [12] }, ROWS2),
      { type: 'graph', coordinateSystem: 'cartesian2d', edgeSymbol: ['none', 'arrow'], edgeSymbolSize: 9,
        data: [[2, 2], [5, 6], [8, 3]], links: [{ source: 0, target: 1 }, { source: 1, target: 2 }] }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    // a filled end in a collapsed box draws nothing, but is brushed: its
    // transform is what the canvas keeps
    ['v-tf-after-graph-collapsed', vv([LNC({ symbol: 'triangle', symbolSize: [12] }, ROWS2),
      { type: 'graph', coordinateSystem: 'cartesian2d', edgeSymbol: ['arrow', 'none'], edgeSymbolSize: [[9], 9],
        data: [[2, 2], [5, 6], [8, 3]], links: [{ source: 0, target: 1 }, { source: 1, target: 2 }] }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    // a pin of no width: its path no number, still brushed
    ['v-tf-after-graph-nanpin', vv([LNC({ symbol: 'triangle', symbolSize: [12] }, ROWS2),
      { type: 'graph', coordinateSystem: 'cartesian2d', edgeSymbol: ['pin', 'none'], edgeSymbolSize: [[0, 9], 9],
        data: [[2, 2], [5, 6], [8, 3]], links: [{ source: 0, target: 1 }, { source: 1, target: 2 }] }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-after-graph-edge', vv([LNC({ symbolSize: [12] }, ROWS2),
      { type: 'graph', layout: 'none', left: 60, top: 40, width: 200, height: 120, symbolSize: 3,
        lineStyle: { width: 2, color: '#333' },
        data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 30 }], links: [{ source: 'a', target: 'b' }] }]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    // a clip entered at the effect symbol itself: the clip path's transform
    // (none), not the one before it
    ['v-tf-clip-entry', vv([LNC({ symbolSize: 10 }, [{ coords: [[1, 8], [9, 8]] }], { symbol: ['none', 'arrow'], symbolSize: 10 }),
      LN({ symbolSize: [12] }, [{ coords: [[1, 3], [9, 3]] }], { lineStyle: { color: '#999', opacity: 0 } })]),
    [0, 600], { v2: true, probes: 'nan-origin' }],
    ['v-tf-hit', vv(LNC({ symbolSize: [12] }, ROWS2)), [0, 600], { v2: true, probes: 'nan-effects' }],
    ['v-tf-rect-restart', vv(LNC({ symbol: 'rect', symbolSize: [12], period: 1 }, [{ coords: [[1, 8], [9, 8]] }])),
      [0, 300, 600, 900, 1050, 1300], { v2: true, probes: 'nan-effects' }],
    // 3. the shadowColor a gradient effect symbol takes from the canvas
    ['v-sh-line-noblur', vv(LN({ color: GRAD, shadowBlur: 4 }, ROWS2,
      { lineStyle: { color: '#999', opacity: 1, shadowColor: '#0000ff' } })), [0, 600], { v2: true }],
    ['v-sh-label', vv(LNC({ color: GRAD, shadowBlur: 4 }, ROWS2,
      { label: { show: true, formatter: 'Ab', textShadowBlur: 2, textShadowColor: '#00ff00' } })), [0, 600], { v2: true }],
    ['v-sh-label-plain', vv(LNC({ color: GRAD, shadowBlur: 4 }, ROWS2,
      { label: { show: true, formatter: 'Ab', textShadowColor: '#00ff00' } })), [0, 600], { v2: true }],
    ['v-sh-label-transparent', vv(LNC({ color: GRAD, shadowBlur: 4 }, ROWS2,
      { label: { show: true, formatter: 'Ab', textShadowBlur: 2 } })), [0, 600], { v2: true }],
    ['v-sh-scatter-noblur', vv([LNC({ color: GRAD, shadowBlur: 4 }, ROWS2),
      { type: 'scatter', itemStyle: { shadowColor: '#ff00ff' }, data: [[3, 5]] }]), [0, 600], { v2: true }],
    // a bar with a shadowColor and no blur, brushed before the effect symbols
    ['v-sh-bar-noblur', vv([LNC({ color: GRAD, shadowBlur: 4 }, ROWS2),
      { type: 'bar', data: [[3, 4], [6, 5]], itemStyle: { shadowColor: '#00ffff' } }]), [0, 600], { v2: true }],
    ['v-sh-invalid', vv(LN({ color: GRAD, shadowBlur: 4 }, [{ coords: [[1, 8], [9, 8]] }],
      { lineStyle: { color: '#999', opacity: 1, shadowColor: 'notacolor', shadowBlur: 2 } })), [0, 600], { v2: true }],
    ['v-sh-negblur', vv(LN({ color: '#ff0000', shadowBlur: 6 }, [{ coords: [[1, 8], [9, 8]] },
      { coords: [[1, 3], [9, 3]], effect: { color: '#0000ff', shadowBlur: -3 } }])), [0, 600], { v2: true }],
    // 4. an opacity outside 0..1
    ['v-op-scatter', vv([{ type: 'scatter', emphasis: { focus: 'series' }, data: [[1, 1]] },
      { type: 'scatter', symbolSize: 10, data: [{ value: [2, 2], itemStyle: { opacity: -0.5 } },
        { value: [4, 4], itemStyle: { opacity: 1.7 } }, { value: [6, 6], itemStyle: { opacity: 3 } },
        { value: [8, 8], itemStyle: { opacity: 0.4 } }] },
      { type: 'scatter', symbolSize: 10, itemStyle: { opacity: 2.5 }, data: [[3, 7]] }]), [0, 10],
    { v2: true, acts: { 1: [{ type: 'highlight', seriesIndex: 0, dataIndex: 0 }] } }],
    ['v-op-line', vv([{ type: 'scatter', emphasis: { focus: 'series' }, data: [[1, 1]] },
      { type: 'line', showSymbol: false, lineStyle: { opacity: 3 }, data: [[2, 2], [8, 6]] },
      { type: 'line', showSymbol: false, lineStyle: { opacity: -2 }, data: [[2, 5], [8, 9]] }]), [0, 10],
    { v2: true, acts: { 1: [{ type: 'highlight', seriesIndex: 0, dataIndex: 0 }] } }],
    ['v-op-lines', vv(LN({ color: GRAD, shadowBlur: 4, opacity: 2 }, [{ coords: [[1, 8], [9, 8]] }],
      { lineStyle: { color: '#999', opacity: -1, shadowColor: '#0000ff' } })), [0, 600], { v2: true }],
    ['v-op-graphic', { animation: false, graphic: [
      { type: 'rect', name: 'gr0', shape: { x: 20, y: 20, width: 40, height: 30 },
        style: { fill: '#ff0000', fillOpacity: 0.4, opacity: 2 } },
      { type: 'rect', name: 'gr1', shape: { x: 80, y: 20, width: 40, height: 30 },
        style: { fill: '#00ff00', fillOpacity: -0.5, opacity: -1 } },
      { type: 'rect', name: 'gr2', shape: { x: 140, y: 20, width: 40, height: 30 },
        style: { fill: '#0000ff', opacity: -1 } },
      { type: 'circle', name: 'gr3', shape: { cx: 250, cy: 40, r: 20 },
        style: { stroke: '#000000', lineWidth: 3, fill: 'none', strokeOpacity: 3, opacity: 0.25 } },
      { type: 'rect', name: 'gr4', shape: { x: 20, y: 80, width: 40, height: 30 },
        style: { fill: '#ff00ff', fillOpacity: 2, opacity: 0.25 } },
      { type: 'rect', name: 'gr5', shape: { x: 80, y: 80, width: 40, height: 30 },
        style: { fill: '#00ffff', fillOpacity: 0.5, opacity: 3 } },
      { type: 'rect', name: 'gr6', shape: { x: 140, y: 80, width: 40, height: 30 },
        style: { fill: '#808080', stroke: '#000000', lineWidth: 2, fillOpacity: 0.5, strokeOpacity: 0.5, opacity: 1.5 } },
      { type: 'rect', name: 'gr7', shape: { x: 200, y: 80, width: 40, height: 30 },
        style: { fill: '#804000', fillOpacity: 0.5, opacity: -1 } },
    ] }, [0], { v2: true }],
    // 5. the same refusal elsewhere: a pen's cap, join and miterLimit; a fill
    ['v-ex-pen', vv(LN({ show: false }, [
      { coords: [[1, 8], [9, 8]], lineStyle: { cap: 'round', join: 'round', miterLimit: 4, width: 3 } },
      { coords: [[1, 5], [9, 5]], lineStyle: { cap: 'Round', join: 'foo', miterLimit: -2, width: 3 } },
      { coords: [[1, 3], [9, 3]], lineStyle: { cap: 'square', join: 'bevel', miterLimit: 0, width: 3 } },
      { coords: [[1, 2], [9, 2]], lineStyle: { cap: 'round', miterLimit: 6, width: 3 } },
      { coords: [[1, 1], [9, 1]], lineStyle: { cap: '', join: '', miterLimit: '0', width: 3 } },
      { coords: [[1, 0.5], [9, 0.5]], lineStyle: { miterLimit: 'abc', width: 3 } }])),
    [0], { v2: true }],
    ['v-ex-fill', vv([{ type: 'scatter', itemStyle: { color: '#ff0000' }, data: [[2, 2]] },
      { type: 'scatter', itemStyle: { color: 'notacolor' }, data: [[5, 5]] },
      { type: 'scatter', itemStyle: { color: '#00ff00', borderColor: 'nope', borderWidth: 2 }, data: [[7, 7]] }]),
    [0], { v2: true }],
    // ---- [R7-W] ----
    // 1. a fill or stroke colour no parser reads: the canvas keeps the one it
    //    had (and a series that writes one takes no palette slot)
    ['w-fill-scatter', vv([{ type: 'scatter', itemStyle: { color: '#ff0000' }, data: [[2, 2]] },
      { type: 'scatter', itemStyle: { color: 'notacolor' }, data: [[5, 5], [5, 7]] },
      { type: 'scatter', itemStyle: { color: '#00ff00', borderColor: 'nope', borderWidth: 2 }, data: [[7, 7]] },
      { type: 'scatter', data: [[8, 3]] },
      { type: 'scatter', itemStyle: { color: '#0000ff' }, data: [[3, 8], { value: [4, 8], itemStyle: { color: 'zzz' } }] }]),
    [0], { w: true }],
    ['w-fill-line', vv([{ type: 'line', showSymbol: false, lineStyle: { color: '#ff0000', width: 3 }, data: [[1, 2], [9, 3]] },
      { type: 'line', showSymbol: false, lineStyle: { color: 'nope', width: 2 }, areaStyle: { color: 'zz' },
        data: [[1, 5], [9, 6]] },
      { type: 'line', symbolSize: 8, itemStyle: { color: 'qq' }, lineStyle: { color: '#0000ff' }, data: [[2, 8], [8, 9]] }]),
    [0], { w: true }],
    ['w-fill-bar', vv([{ type: 'bar', barWidth: 20, label: { show: true, position: 'inside' },
      data: [{ value: [3, 4], itemStyle: { color: '#00ffff' } }, { value: [6, 5], itemStyle: { color: 'nope' } },
        { value: [8, 3], itemStyle: { color: '#ff00ff', borderColor: 'bad', borderWidth: 3 } }] }]),
    [0], { w: true }],
    ['w-fill-pie', { animation: false, series: [{ type: 'pie', radius: 60, center: [200, 150], label: { show: false },
      data: [{ value: 3, name: 'a', itemStyle: { color: '#ff0000' } }, { value: 2, name: 'b', itemStyle: { color: 'nope' } },
        { value: 1, name: 'c', itemStyle: { color: '#0000ff' } }] }] },
    [0], { w: true }],
    // 2. a width of 'Infinity' and a dash phase no number: the canvas keeps
    //    the width and the phase it had
    // (a series' elements share its clip: the canvas carries a value from
    // one row to the next, a series' restore drops it)
    ['w-lw-inf', vv([LNC({ show: false }, [
      { coords: [[1, 8], [9, 8]], lineStyle: { color: '#ff0000', width: 3 } },
      { coords: [[1, 7], [9, 7]], lineStyle: { color: '#0000ff', width: 'Infinity' } }]),
    { type: 'bar', barWidth: 20, data: [{ value: [3, 4], itemStyle: { borderColor: '#000', borderWidth: 3 } },
      { value: [6, 5], itemStyle: { borderColor: '#000', borderWidth: 'Infinity' } }] },
    { type: 'scatter', symbolSize: 10, data: [{ value: [2, 2], itemStyle: { borderColor: '#000', borderWidth: 2 } },
      { value: [8, 2], itemStyle: { borderColor: '#000', borderWidth: 'Infinity' } }] }]),
    [0], { w: true }],
    ['w-dash-offset', vv(LNC({ show: false }, [
      { coords: [[1, 1], [9, 1]], lineStyle: { type: 'dashed', dashOffset: 'abc', width: 2 } },
      { coords: [[1, 3], [9, 3]], lineStyle: { type: 'dashed', dashOffset: 5, width: 2 } },
      { coords: [[1, 5], [9, 5]], lineStyle: { type: 'dashed', dashOffset: 'abc', width: 2 } },
      { coords: [[1, 7], [9, 7]], lineStyle: { type: [4, 4], dashOffset: 'Infinity', width: 2 } },
      { coords: [[1, 8], [9, 8]], lineStyle: { type: 'solid', width: 2 } },
      { coords: [[1, 9], [9, 9]], lineStyle: { type: [6, 2], dashOffset: '7', width: 2 } },
      { coords: [[1, 9.5], [9, 9.5]], lineStyle: { type: [6, 2], dashOffset: 'x', width: 2 } }])),
    [0], { w: true }],
    // 3. components: a legend's refused values; what the axes, drawn before
    //    the series, leave on the canvas
    ['w-comp-legend', Object.assign(vv([{ type: 'scatter', name: 'A', itemStyle: { color: '#ff0000', shadowBlur: 5,
      shadowColor: '#00ff00', borderColor: '#000', borderWidth: 2 }, data: [[2, 2]] },
      { type: 'scatter', name: 'B', itemStyle: { color: '#0000ff' }, data: [[5, 5]] }]),
    { legend: { left: 20, top: 10, itemStyle: { shadowBlur: -3, shadowColor: 'nope', color: 'bad', borderCap: 'Round',
      borderColor: '#ff00ff', borderWidth: 2 } } }),
    [0], { w: true }],
    ['w-comp-axes-fill', Object.assign(vv([{ type: 'scatter', clip: false,
      itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 }, data: [[5, 5]] }]), { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 } }),
    [0], { w: true }],
    ['w-comp-axes-tf', Object.assign(vv([LNC({ symbol: 'triangle', symbolSize: [12], color: GRAD, shadowBlur: 4 },
      [{ coords: [[1, 8], [9, 5]] }], { lineStyle: { color: '#999', opacity: 0 } })]),
    { xAxis: { type: 'value', min: 0, max: 10, axisLabel: { rotate: 30 } }, yAxis: { type: 'value', min: 0, max: 10 } }),
    [0, 600], { w: true, probes: 'nan-origin' }],
    // 4. useDirtyRect: each block starts from the canvas' own state
    ['w-dirty-fill', vv([{ type: 'scatter', symbolSize: 24, itemStyle: { color: '#ff0000' }, emphasis: { scale: false },
      data: [[5, 5], [1, 1]] },
      { type: 'scatter', symbolSize: 6, itemStyle: { color: 'nope' }, data: [[5.35, 5.6], [1.2, 9]] }]),
    [0, 10], { w: true, dirty: true, acts: { 1: [{ type: 'highlight', seriesIndex: 0, dataIndex: 0 }] } }],
    ['w-dirty-effect', vv(LN({ color: GRAD, shadowBlur: 5 }, [
      { coords: [[1, 8], [9, 8]], effect: { color: '#ff0000' } },
      { coords: [[1, 3], [9, 3]] }])), [0, 500, 1500], { w: true, dirty: true }],
    // 5. an option set while a trail runs whose transform is no number
    ['w-tf-update', vv(LNC({ symbol: 'rect', symbolSize: [12], period: 1 }, [{ coords: [[1, 8], [9, 8]] }])),
      [0, 300, 600, 900], { w: true, probes: 'nan-effects', more: [[234, 96], [234.4, 96.2], [222, 95], [246, 97.5],
        [230, 101.8], [238, 90.4], [234, 103], [180, 96], [300, 96]],
        sets: { 2: { series: [{ lineStyle: { color: '#333' } }] } } }],
    // 6. a symbol of size nought: its transform does not invert, hit at the
    //    canvas' top left under the inverse it was made with
    ['w-zero-scatter', vv([{ type: 'scatter', clip: false, symbol: 'rect', symbolSize: [12, 0], data: [[7, 7]] },
      { type: 'scatter', clip: false, symbolSize: 0, data: [[5, 5]] }]),
    [0], { w: true, probes: [[0.2, 0.2], [0.5, -0.5], [0.9, 0.1], [-0.6, -0.6], [1.5, 0], [0, 0.95], [0.9, 0.9],
      [0.95, -0.9], [-0.9, 0.85], [200, 150], [200.5, 150.5], [270, 111.5], [271, 111.5], [3, 3]] }],
    ['w-zero-graph', { animation: false, series: [{ type: 'graph', layout: 'none', left: 50, top: 50, width: 300, height: 200,
      symbolSize: 0, label: { show: false }, data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100, symbol: 'rect' }],
      links: [] }] },
    [0], { w: true, probes: [[0.2, 0.2], [0.5, -0.5], [0.9, 0.1], [-0.6, -0.6], [1.5, 0], [0.9, 0.9], [-0.95, 0.9],
      [50, 50], [50.5, 50.5], [350, 250], [3, 3]] }],
  ]);
}
function withPalette(list) {
  for (const c of list) if (c[3] && c[3].w && !c[1].color) c[1].color = PAL;
  return list;
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
        const lp = V2 && line && line.childOfName && line.childOfName('line');
        if (lp) map.set(lp, 'l' + si + '.' + i);
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
        const lp = V2 && line.childOfName('line');
        if (lp) map.set(lp, 'ge' + si + '.' + i);
      }
      if (V2) {
        const nd = sm.getData();
        for (let i = 0; i < nd.count(); i++) {
          const g = nd.getItemGraphicEl(i);
          const p = g && g.childAt(0);
          if (p) map.set(p, 'gn' + si + '.' + i);
        }
      }
    }
    else if (V2 && type === 'line') {
      // [R7-V] a line series' polyline
      const view = chart.getViewOfSeriesModel(sm);
      if (view && view._polyline) map.set(view._polyline, 'ln' + si + '.0');
    }
    else if (type === 'scatter') {
      const data = sm.getData();
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        const p = g && g.childAt(0);
        if (p) map.set(p, 's' + si + '.' + i);
      }
    }
    // [R7-W] a bar, a pie's sector, a line's symbols and area
    if (W && (type === 'bar' || type === 'pie')) {
      const data = sm.getData();
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        if (g) map.set(g, (type === 'bar' ? 'b' : 'p') + si + '.' + i);
      }
    }
    if (W && type === 'line') {
      const data = sm.getData();
      for (let i = 0; i < data.count(); i++) {
        const g = data.getItemGraphicEl(i);
        const p = g && g.childAt && g.childAt(0);
        if (p) map.set(p, 'ls' + si + '.' + i);
      }
      const view = chart.getViewOfSeriesModel(sm);
      if (view && view._polygon) map.set(view._polygon, 'la' + si + '.0');
    }
  });
  if (W) {
    // a label's last text span
    for (const [el, key] of Array.from(map)) {
      const tc = el.getTextContent && el.getTextContent();
      const kids = tc && tc.childrenRef ? tc.childrenRef() : [];
      let last = null;
      for (const k of kids) if (k.style && k.style.text) last = k;
      if (last) map.set(last, 'x' + key);
    }
    // the legends' displayables and the axes' text spans, in paint order
    const legends = [];
    model.eachComponent('legend', lm => {
      const v = chart.getViewOfComponentModel(lm);
      if (v) legends.push(v.group);
    });
    const counts = new Map();
    let ax = 0;
    for (const el of chart.getZr().storage.getDisplayList(true)) {
      let p = el;
      let li = -1;
      let isAxis = false;
      while (p) {
        const k = legends.indexOf(p);
        if (k >= 0) { li = k; break; }
        if (p.__ecComponentInfo && /Axis$/.test(p.__ecComponentInfo.mainType)) isAxis = true;
        p = p.parent || p.__hostTarget;
      }
      if (li >= 0) {
        const n = counts.get(li) || 0;
        counts.set(li, n + 1);
        if (!map.has(el)) map.set(el, 'lg' + li + '.' + n);
      }
      else if (isAxis && el.style && el.style.text != null && !map.has(el)) map.set(el, 'ax' + (ax++));
    }
  }
  if (V2) {
    for (const el of chart.getZr().storage.getDisplayList(true)) {
      if (el.name && /^gr[0-9]+$/.test(el.name)) map.set(el, el.name);
    }
  }
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
  if (V2) {
    // [R7-V] the context once it was brushed, its fills and strokes, its path
    r.st = SNAPS.has(el) ? SNAPS.get(el) : null;
    if (W) r.sts = SNAPL.get(el) || [];
    // the inverse its hit takes the point back through (kept while a
    // transform does not invert)
    r.inv = el.invTransform ? Array.from(el.invTransform).map(hexOrNull) : null;
    r.ops = OPS.get(el) || [];
    const p = PATHS.get(el);
    if (p && p.length) {
      const xs = p.map(q => q[0]);
      const ys = p.map(q => q[1]);
      r.pb = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)].map(hex);
      // the area it encloses (the shoelace over its points, one ring)
      let a = 0;
      for (let i = 0; i < p.length; i++) {
        const q = p[(i + 1) % p.length];
        a += p[i][0] * q[1] - q[0] * p[i][1];
      }
      r.pa = hex(Math.abs(a / 2));
    }
    else { r.pb = null; r.pa = null; }
  }
  return r;
}

// [R7-V] the points a case probes with findHover
function unhex(s) {
  bits.setUint32(0, parseInt(s.slice(0, 8), 16));
  bits.setUint32(4, parseInt(s.slice(8), 16));
  return bits.getFloat64(0);
}
function probesOf(kind, els, prevEls) {
  const out = [];
  if (Array.isArray(kind)) return kind;
  if (kind === 'ends') {
    for (const e of els) {
      if (!/^g[ft]/.test(e.key) || !e.pb) continue;
      const cx = (unhex(e.pb[0]) + unhex(e.pb[2])) / 2;
      const cy = (unhex(e.pb[1]) + unhex(e.pb[3])) / 2;
      // (off a pen's edge, never on it: 0.9 and 1.1 about a half width of 1)
      for (const dx of [-7, -3, -1.1, -0.9, -0.4, 0, 0.4, 0.9, 1.1, 3, 7]) {
        for (const dy of [-7, -3, -1.1, -0.9, -0.4, 0, 0.4, 0.9, 1.1, 3, 7]) out.push([cx + dx, cy + dy]);
      }
    }
  }
  else if (kind === 'nan-effects' || kind === 'nan-origin') {
    for (const p of [[0.1, 0.1], [0.4, 0.4], [0.45, -0.45], [0.6, 0.2], [-0.3, 0.3], [1, 1]]) out.push(p);
    // (where a label sits its box is the measurer's, not compared: the origin alone)
    if (kind === 'nan-effects') for (const e of els) {
      if (e.key[0] !== 'e' || e.sy !== null || !e.st) continue;
      const mx = unhex(e.st.m[4]);
      const my = unhex(e.st.m[5]);
      // (off its place by a little: an end symbol's tip sits there, a vertex)
      for (const d of [[0.013, 0.011], [0.3, 0], [0, 0.3], [2, 0], [0, 2], [5, 5]]) out.push([mx + d[0], my + d[1]]);
      // and where the frame before drew it (its inverse kept)
      const pe = prevEls && prevEls.find(q => q.key === e.key);
      if (pe && pe.st && pe.sy !== null) {
        const px = unhex(pe.st.m[4]);
        const py = unhex(pe.st.m[5]);
        for (const d of [[0.013, 0.011], [2, 0.5], [-3, 1], [0, 20], [1, -15]]) out.push([px + d[0], py + d[1]]);
      }
    }
  }
  return out;
}

function run(id, option, samples, opts) {
  NOW = T_BASE;
  rngState = SEED;
  CUR = null;
  opts = opts || {};
  V2 = !!opts.v2 || !!opts.w;
  W = !!opts.w;
  const dom = fakeCanvas(CW, CH);
  const chart = echarts.init(dom, null, { renderer: 'canvas', width: CW, height: CH, devicePixelRatio: 1,
    useDirtyRect: !!opts.dirty });
  // [R7-W] the repaint blocks
  if (W) {
    const P = chart.getZr().painter.constructor.prototype;
    if (!P.__r7wBlock) {
      const orig = P._paintPerCursorInRect;
      P._paintPerCursorInRect = function (layer, cursor, list, rect) {
        if (W) {
          BLK = BLOCKS.length;
          BLOCKS.push(rect ? [rect.x, rect.y, rect.width, rect.height].map(hex) : null);
        }
        return orig.apply(this, arguments);
      };
      P.__r7wBlock = true;
    }
  }
  // [R7-V] a layer cleared starts the record of its paint afresh (a frame
  // that paints nothing keeps the last paint's)
  if (V2) {
    const L = chart.getZr().painter.getLayer(0).constructor.prototype;
    if (!L.__r7vClear) {
      const orig = L.clear;
      L.clear = function () {
        if (V2) { SNAPS = new Map(); OPS = new Map(); PATHS = new Map(); SNAPL = new Map(); }
        return orig.apply(this, arguments);
      };
      L.__r7vClear = true;
    }
  }
  const frames = [];
  BLOCKS = [];
  BLK = 0;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    for (let si = 0; si < samples.length; si++) {
      const t = samples[si];
      NOW = T_BASE + t;
      BRUSHES = [];
      CUR = null;
      if (si > 0) {
        BLOCKS = [];
        BLK = 0;
      }
      if (opts.sets && opts.sets[si]) chart.setOption(JSON.parse(JSON.stringify(opts.sets[si])));
      if (opts.acts && opts.acts[si]) for (const a of opts.acts[si]) chart.dispatchAction(a);
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
      if (V2 && opts.probes) {
        const zr = chart.getZr();
        const hits = [];
        const pts = probesOf(opts.probes, els, frames.length ? frames[frames.length - 1].els : null);
        for (const [x, y] of (opts.more ? pts.concat(opts.more) : pts)) {
          const h = zr.handler.findHover(x, y);
          const tg = h && h.target;
          hits.push([hex(x), hex(y), tg ? (map.get(tg) || 'other') : null]);
        }
        if (W) frames.push({ t, els, hits, blocks: BLOCKS });
        else frames.push({ t, els, hits });
      }
      else if (W) frames.push({ t, els, blocks: BLOCKS });
      else frames.push({ t, els });
    }
  }
  finally {
    chart.dispose();
    V2 = false;
    W = false;
  }
  // [R7-W] the options set before a sample, the dirty rects
  if (opts.w) return Object.assign({ id, option }, opts.acts ? { acts: opts.acts } : {},
    opts.sets ? { sets: opts.sets } : {}, opts.dirty ? { dirty: true } : {}, { frames });
  // [R7-V] the actions dispatched before a sample
  if (opts.acts) return { id, option, acts: opts.acts, frames };
  return { id, option, frames };
}

function generate() {
  const charts = cases().map(([id, o, s, opts]) => run(id, o, s, opts));
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
    W: CW, H: CH, T0: T_BASE, charts };
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
