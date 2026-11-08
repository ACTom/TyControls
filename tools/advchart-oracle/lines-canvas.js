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
//
// Round 7 R7-Z (the cases named `z-...`, recorded as the w- ones): every
// displayable of a component (not a series') is tracked as
// `c.<mainType><index>.<z2>.<t|p>.<n>` -- t a text span, p a path, n its
// count among those of its component, z2 and kind in paint order -- in place
// of the w- cases' `lg` / `ax` keys; a text span's text is `tx`.
// Round 7 R7-Y (the cases named `y-...`, recorded as the w- ones and more):
// every paint of a sample is kept (`paints`: per paint the blocks it
// repainted, null the whole canvas), and per tracked element every fill /
// stroke / text made in the sample (`yops`: p the paint, b its block, and
// the context then), never reset by a layer's clear; `pr` the element's
// paint rect now. A gradient the context makes keeps its arguments, a
// pattern its repetition and the matrix setTransform gave it (a DOMMatrix
// stands in for the browser's: translate . rotate . scale, as
// createCanvasPattern builds it), and an op records them (`fo` / `so`: k
// 'linear' / 'radial' / 'pattern', a the arguments, in the frame of the
// element that made it, or rep and m); an image is ready at once (2 x 2).
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
// [R7-AA] a case with `timers` runs what setTimeout queued once the
// option is set (a browser's next task: ParallelView's removeClipPath)
let TIMERS = null;
global.setTimeout = function (fn) { if (TIMERS && typeof fn === 'function') TIMERS.push(fn); return 0; };
global.clearTimeout = function () {};
global.requestAnimationFrame = function () { return 0; };
// [R7-Y] the browser's DOMMatrix, as far as createCanvasPattern uses it
// (node has none, and zrender skips the pattern's transform without it)
global.DOMMatrix = class {
  constructor() { this.a = 1; this.b = 0; this.c = 0; this.d = 1; this.e = 0; this.f = 0; }
  translateSelf(tx, ty) {
    this.e += this.a * tx + this.c * ty;
    this.f += this.b * tx + this.d * ty;
    return this;
  }
  rotateSelf(rx, ry, rz) {
    const rad = rz * Math.PI / 180;
    const cs = Math.cos(rad);
    const sn = Math.sin(rad);
    const a = this.a * cs + this.c * sn;
    const b = this.b * cs + this.d * sn;
    const c = -this.a * sn + this.c * cs;
    const d = -this.b * sn + this.d * cs;
    this.a = a; this.b = b; this.c = c; this.d = d;
    return this;
  }
  scaleSelf(sx, sy) {
    this.a *= sx; this.b *= sx; this.c *= sy; this.d *= sy;
    return this;
  }
};
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
// [R7-Z] the record of the cases named z-...
let Z = false;
// [R7-AA] the cases named aa-...: every op numbered in paint order (`q`)
let AA = false;
let SEQ = 0;
// [R7-Y] the record of the cases named y-...
let Y = false;
// [R7-AB] a case that must not touch a path before it is brushed (see elRec)
let PRISTINE = false;
let YPAINTS = [];
let YBLK = 0;
let YOPS = new Map();
const yNote = (el, rec) => {
  if (!Y || !el) return;
  let o = YOPS.get(el);
  if (!o) { o = []; YOPS.set(el, o); }
  o.push(Object.assign({ p: YPAINTS.length - 1, b: YBLK }, rec));
};
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
// [R7-Y] the font shorthand a browser's parser takes, as far as makeFont
// writes one: words of style / variant / weight / stretch, a size with its
// unit (or a size keyword), then a family that does not start with a digit
const FONT_WORDS = ['normal', 'italic', 'oblique', 'small-caps', 'bold', 'bolder', 'lighter', 'ultra-condensed',
  'extra-condensed', 'condensed', 'semi-condensed', 'semi-expanded', 'expanded', 'extra-expanded', 'ultra-expanded'];
const FONT_SIZE = /^\+?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?(px|em|rem|pt|pc|in|cm|mm|q|ex|ch|vw|vh|vmin|vmax|%)(\/\S+)?$/i;
const FONT_SIZE_WORDS = ['xx-small', 'x-small', 'small', 'medium', 'large', 'x-large', 'xx-large', 'xxx-large', 'larger', 'smaller'];
function cssFontOk(v) {
  const t = String(v).trim().split(/\s+/);
  let i = 0;
  for (; i < t.length; i++) {
    const w = t[i].toLowerCase();
    if (FONT_SIZE.test(w) || FONT_SIZE_WORDS.indexOf(w) >= 0) break;
    if (FONT_WORDS.indexOf(w) >= 0) continue;
    if (/^\+?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/.test(w) && +w >= 1 && +w <= 1000) continue;
    return false;
  }
  if (i >= t.length - 1) return false;
  const fam = t.slice(i + 1).join(' ');
  return fam.length > 0 && !/^[0-9]/.test(fam);
}
function makeCtx(canvas) {
  // the canvas' own defaults: a transparent black shadow of no blur
  const st = { shadowColor: 'rgba(0, 0, 0, 0)', shadowBlur: 0, m: [1, 0, 0, 1, 0, 0],
    globalAlpha: 1, lineWidth: 1, lineCap: 'butt', lineJoin: 'miter', miterLimit: 10, lineDashOffset: 0,
    shadowOffsetX: 0, shadowOffsetY: 0, fillStyle: '#000000', strokeStyle: '#000000',
    globalCompositeOperation: 'source-over', lineDash: [] };
  // [R7-Y] the canvas' own font
  if (Y) st.font = '10px sans-serif';
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
  // [R7-Y] a gradient's or a pattern's own record
  const objRec = v => (!v || typeof v !== 'object' || !v.__k ? null
    : v.__k === 'pattern' ? { k: 'pattern', rep: v.rep, m: v.m ? v.m.map(hex) : null }
      : { k: v.__k, a: v.args.map(hex) });
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
    if (W) o.push(Object.assign({ op, ga: hex(st.globalAlpha) }, opState(), AA ? { q: SEQ++ } : {}));
    else o.push({ op, ga: hex(st.globalAlpha) });
    yNote(owner, Object.assign({ op, ga: hex(st.globalAlpha) }, opState(),
      { fo: objRec(st.fillStyle), so: objRec(st.strokeStyle), gco: st.globalCompositeOperation }));
  };
  // a text's: its span is the owner
  const textNote = op => {
    if (!W || !CUR) return;
    let o = OPS.get(CUR);
    if (!o) { o = []; OPS.set(CUR, o); }
    o.push(Object.assign({ op, ga: hex(st.globalAlpha) }, opState(), AA ? { q: SEQ++ } : {}));
    yNote(CUR, Object.assign({ op, ga: hex(st.globalAlpha) }, opState(),
      { fo: objRec(st.fillStyle), so: objRec(st.strokeStyle), gco: st.globalCompositeOperation, font: st.font }));
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
    createLinearGradient(...a) { return Y ? { __k: 'linear', args: a, addColorStop() {} } : { addColorStop() {} }; },
    createRadialGradient(...a) { return Y ? { __k: 'radial', args: a, addColorStop() {} } : { addColorStop() {} }; },
    createPattern(img, rep) {
      return Y ? { __k: 'pattern', rep, m: null, setTransform(mm) { this.m = [mm.a, mm.b, mm.c, mm.d, mm.e, mm.f]; } } : {};
    },
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
        // [R7-Y] the font, refused where the parser does not take it
        case 'font': if (Y) { if (cssFontOk(v)) st.font = String(v); } else t[k] = v; break;
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
echarts.setPlatformAPI({ createCanvas() { return fakeCanvas(300, 150); },
  // [R7-Y] an image ready at once
  loadImage(src) { return { width: 2, height: 2, src }; } });
// [R7-Y] a 2 x 2 image for a pattern (red and blue checker)
const IMG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR42mP4z8AAQkAMJEAsAEPOB/npBtUZAAAAAElFTkSuQmCC';

// [R7-AD] a square map for the geo cases (the fixture holds its text: the
// port registers the same)
const MAPS = [{ name: 'ad-sq', text: JSON.stringify({ type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [[[10, 0], [20, 0], [20, 10], [10, 10], [10, 0]]] } }] }) }];
for (const m of MAPS) echarts.registerMap(m.name, m.text);
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
// [R7-W] an axis' colours written (the port's own are its skin's)
const AXC = a => Object.assign({ axisLabel: { color: '#112233' }, axisLine: { lineStyle: { color: '#445566' } },
  axisTick: { lineStyle: { color: '#778899' } }, splitLine: { lineStyle: { color: '#aabbcc' } } }, a);
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
    ['w-fill-line', vv([{ type: 'line', showSymbol: false, lineStyle: { color: '#ff0000', width: 3 },
      areaStyle: { color: '#ff0000' }, data: [[1, 2], [9, 3]] },
      { type: 'line', showSymbol: false, lineStyle: { color: 'nope', width: 2 }, areaStyle: { color: 'zz' },
        data: [[1, 5], [9, 6]] },
      { type: 'line', symbolSize: 8, itemStyle: { color: 'qq' }, lineStyle: { color: '#0000ff' }, data: [[2, 8], [8, 9]] }]),
    [0], { w: true }],
    ['w-fill-bar', vv([{ type: 'bar', barWidth: 20, label: { show: true, position: 'inside' },
      data: [{ value: [3, 4], itemStyle: { color: '#00ffff' } }, { value: [6, 5], itemStyle: { color: 'nope' } },
        { value: [8, 3], itemStyle: { color: '#ff00ff', borderColor: 'bad', borderWidth: 3 } }] }]),
    [0], { w: true }],
    // a lines row's own unreadable colour, after a row of another
    ['w-fill-lines-rows', vv(LNC({ show: false }, [
      { coords: [[1, 8], [9, 8]], lineStyle: { color: '#0000ff', width: 2 } },
      { coords: [[1, 6], [9, 6]], lineStyle: { color: 'nope', width: 2 } }])), [0], { w: true }],
    // a label of 'inherit' after one of a colour; a rich inside label of an
    // unreadable host
    ['w-fill-label', vv([{ type: 'bar', barWidth: 20, label: { show: true, position: 'top', color: 'inherit' },
      data: [{ value: [3, 4], itemStyle: { color: '#00ffff' } }, { value: [6, 5], itemStyle: { color: 'nope' } }] },
    { type: 'bar', barWidth: 20, label: { show: true, position: 'inside', formatter: '{a|Ab}', rich: { a: {} } },
      data: [{ value: [8, 6], itemStyle: { color: '#ff00ff' } }, { value: [9, 6], itemStyle: { color: 'bad' } }] }]),
    [0], { w: true }],
    // (a bar in normal mode has no clip path: one series' bar after another's)
    ['w-fill-bar-series', Object.assign(vv([{ type: 'bar', data: [[3, 5]], itemStyle: { color: '#ff0000' } },
      { type: 'bar', data: [[3, 5]], itemStyle: { color: 'bananas' } }, { type: 'bar', data: [[3, 5]] }]),
    { xAxis: AXC({ type: 'category', data: ['A', 'B', 'C', 'D'] }), yAxis: AXC({ type: 'value' }) }),
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
      { coords: [[1, 4], [9, 4]], lineStyle: { type: 'solid', dashOffset: 9, width: 2 } },
      { coords: [[1, 5], [9, 5]], lineStyle: { type: 'dashed', dashOffset: 'abc', width: 2 } },
      { coords: [[1, 7], [9, 7]], lineStyle: { type: [4, 4], dashOffset: 'Infinity', width: 2 } },
      { coords: [[1, 8], [9, 8]], lineStyle: { type: 'solid', width: 2 } },
      { coords: [[1, 9], [9, 9]], lineStyle: { type: [6, 2], dashOffset: '7', width: 2 } },
      { coords: [[1, 9.5], [9, 9.5]], lineStyle: { type: [6, 2], dashOffset: 'x', width: 2 } }])),
    [0], { w: true }],
    // (the other builders of a pen of 'Infinity': each element after one of 3)
    ['w-lw-inf-pie', { animation: false, color: PAL, series: [{ type: 'pie', radius: 60, center: [200, 150], label: { show: false },
      data: [{ value: 3, itemStyle: { borderColor: '#000', borderWidth: 3 } },
        { value: 2, itemStyle: { borderColor: '#000', borderWidth: 'Infinity' } }] }] }, [0], { w: true }],
    ['w-lw-inf-sunburst', { animation: false, color: PAL, series: [{ type: 'sunburst', radius: [0, 90], label: { show: false },
      data: [{ name: 'a', value: 3, itemStyle: { borderColor: '#000', borderWidth: 3 } },
        { name: 'b', value: 2, itemStyle: { borderColor: '#000', borderWidth: 'Infinity' } }] }] }, [0], { w: true }],
    ['w-lw-inf-radar', { animation: false, color: PAL, radar: { indicator: [{ max: 10 }, { max: 10 }, { max: 10 }] },
      series: [{ type: 'radar', symbol: 'none', lineStyle: { width: 'Infinity' }, data: [{ value: [5, 6, 7] }, { value: [3, 8, 4] }] },
      { type: 'radar', symbol: 'none', lineStyle: { width: 3 }, data: [{ value: [2, 2, 2] }] }] }, [0], { w: true }],
    ['w-lw-inf-tree', { animation: false, color: PAL, series: [{ type: 'tree', label: { show: false }, symbolSize: 10,
      itemStyle: { color: '#b0c4de', borderColor: '#000', borderWidth: 'Infinity' }, lineStyle: { width: 3 },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }] }, [0], { w: true }],
    ['w-lw-inf-graph', { animation: false, color: PAL, series: [{ type: 'graph', layout: 'none', symbolSize: 20, label: { show: false },
      data: [{ name: 'a', x: 0, y: 0, itemStyle: { borderColor: '#000', borderWidth: 3 } },
        { name: 'b', x: 100, y: 0, itemStyle: { borderColor: '#000', borderWidth: 'Infinity' } }], links: [] }] },
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
      itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 }, data: [[5, 5]] }]),
    { xAxis: AXC({ type: 'value', min: 0, max: 10 }), yAxis: AXC({ type: 'value', min: 0, max: 10 }) }),
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
    // [R7-Y] 1. useDirtyRect in motion: only the block round what moved is
    //    repainted, from the canvas' own state; the rest of the canvas keeps
    //    the last frame's pixels. (Steps small enough that a symbol's last
    //    rect and its new one merge: zrender 6.1 brushes the first block of
    //    a paint only -- each _paintPerCursorInRect leaves the cursor's
    //    drawIdx at the end -- and clears the others; y-dirty-two-blocks
    //    records that.)
    // a gradient effect after a scatter's red shadow far away: in its block
    // nothing before it, the canvas' transparent default
    ['y-dirty-shadow', vv([{ type: 'scatter', symbolSize: 10, itemStyle: { color: '#00aa00', shadowColor: '#ff0000',
      shadowBlur: 6 }, data: [[8, 9]] },
    LN({ color: GRAD, shadowBlur: 5, period: 1 }, [{ coords: [[3, 5], [9, 5]] }],
      { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // a scatter of an unreadable colour under a moving effect: the part of
    // it in the effect's block is repainted from the canvas' own black, the
    // rest keeps the whole paint's (the scatter's green before it)
    ['y-dirty-scatter', vv([{ type: 'scatter', symbolSize: 40, itemStyle: { color: '#00aa00' }, data: [[8, 9]] },
      { type: 'scatter', symbolSize: 40, itemStyle: { color: 'nope' }, data: [[3, 5]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5], [9, 5]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // two rows near enough that their blocks merge: the second's gradient
    // after the first's red, as the whole paint has it
    ['y-dirty-effect-near', vv(LN({ color: GRAD, shadowBlur: 5, period: 1 }, [
      { coords: [[3, 6], [9, 6]], effect: { color: '#ff0000' } },
      { coords: [[3, 5.4], [9, 5.4]] }])), [0, 16, 32, 48], { y: true, dirty: true }],
    // (rows apart: two blocks a paint, the second cleared and not brushed)
    ['y-dirty-two-blocks', vv(LN({ color: GRAD, shadowBlur: 5, period: 1 }, [
      { coords: [[3, 8], [9, 8]], effect: { color: '#ff0000' } },
      { coords: [[3, 3], [9, 3]] }])), [0, 16, 32], { y: true, dirty: true }],
    // [R7-Y] 2. a pattern or a gradient the canvas keeps for an element whose
    //    fill or stroke it refuses: the CanvasPattern under that element's
    //    transform, the CanvasGradient's points (made in the frame of the
    //    element before) under it too
    ['y-pat-bar', vv([{ type: 'bar', barWidth: 30, data: [{ value: [3, 5], itemStyle: { color: { image: IMG, repeat: 'repeat',
      x: 3, y: 1, rotation: 0.5, scaleX: 4, scaleY: 3 } } },
    { value: [7, 6], itemStyle: { color: 'nope' } }] }]), [0], { y: true }],
    ['y-pat-scatter', vv([{ type: 'scatter', symbol: 'rect', symbolSize: 20, itemStyle: { color: { image: IMG, repeat: 'repeat',
      scaleX: 0.25, scaleY: 0.5 } }, data: [[3, 5]] },
    { type: 'scatter', symbolSize: 30, itemStyle: { color: 'nope' }, data: [[7, 6]] }]), [0], { y: true }],
    ['y-grad-scatter', vv([{ type: 'scatter', symbol: 'rect', symbolSize: 20, itemStyle: { color: GRAD }, data: [[3, 5]] },
      { type: 'scatter', symbolSize: 30, itemStyle: { color: 'nope' }, data: [[7, 6]] }]), [0], { y: true }],
    ['y-grad-radial', vv([{ type: 'scatter', symbol: 'rect', symbolSize: 20, itemStyle: { color: { type: 'radial', x: 0.3,
      y: 0.4, r: 0.6, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }, data: [[3, 5]] },
    { type: 'scatter', symbolSize: [30, 30], itemStyle: { color: 'nope' }, data: [[7, 6]] }]), [0], { y: true }],
    // (a bar in normal mode has no clip path: the next series' symbol takes
    // its gradient, made in no transform, under its own)
    ['y-grad-bar', vv([{ type: 'bar', barWidth: 30, itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
      colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }, data: [[3, 5]] },
    { type: 'bar', barWidth: 30, itemStyle: { color: 'nope' }, data: [[5, 4]] },
    { type: 'scatter', clip: false, symbolSize: 16, itemStyle: { color: 'nope' }, data: [[7, 8]] }]), [0], { y: true }],
    ['y-grad-stroke', vv([{ type: 'scatter', symbol: 'rect', symbolSize: 20, itemStyle: { color: '#ffffff', borderWidth: 2,
      borderColor: GRAD }, data: [[3, 5]] },
    { type: 'scatter', symbolSize: 30, itemStyle: { color: '#ffffff', borderWidth: 2, borderColor: 'nope' }, data: [[7, 6]] }]),
    [0], { y: true }],
    // [R7-Y] 3. a shadow offset or blur that is a string of no finite
    //    number (dpr times it is none: refused, the canvas' kept), a numeric
    //    string taken; a blend no word of the canvas' (kept)
    ['y-sh-offset', vv({ type: 'scatter', symbolSize: 12, data: [
      { value: [2, 2], itemStyle: { shadowColor: '#ff0000', shadowBlur: 2, shadowOffsetX: 4, shadowOffsetY: 3 } },
      { value: [4, 4], itemStyle: { shadowColor: '#ff0000', shadowBlur: 2, shadowOffsetX: 'abc', shadowOffsetY: 'Infinity' } },
      { value: [5, 5], itemStyle: { shadowColor: '#0000ff', shadowBlur: 3, shadowOffsetX: '6', shadowOffsetY: '0x3' } },
      { value: [6, 6], itemStyle: { shadowColor: '#00ff00', shadowBlur: 'abc', shadowOffsetX: 'x', shadowOffsetY: -2 } },
      { value: [8, 8], itemStyle: { shadowColor: '#00ff00', shadowBlur: 'Infinity', shadowOffsetX: 1, shadowOffsetY: '' } }] }),
    [0], { y: true }],
    ['y-blend', vv([{ type: 'scatter', clip: false, blendMode: 'multiply', itemStyle: { color: '#ff0000' }, data: [[2, 2]] },
      { type: 'scatter', clip: false, blendMode: 'darken', label: { show: true, formatter: 'A' }, itemStyle: { color: '#ff8800' },
        data: [[3, 3]] },
      // (above the label before it: a label sets source-over)
      { type: 'scatter', clip: false, z: 3, blendMode: 'Foo', itemStyle: { color: '#00ff00' }, data: [[4, 4]] },
      { type: 'scatter', clip: false, blendMode: 'lighter', itemStyle: { color: '#0000ff' }, data: [[6, 6]] },
      { type: 'scatter', clip: false, blendMode: 'Screen', itemStyle: { color: '#00ffff' }, data: [[8, 8]] },
      { type: 'scatter', clip: false, blendMode: 'screen', itemStyle: { color: '#ff00ff' }, data: [[9, 3]] }]), [0], { y: true }],
    ['y-blend-graphic', { animation: false, graphic: [
      { type: 'rect', name: 'gr0', shape: { x: 20, y: 20, width: 40, height: 30 }, style: { fill: '#ff0000', blend: 'multiply' } },
      { type: 'rect', name: 'gr1', shape: { x: 80, y: 20, width: 40, height: 30 }, style: { fill: '#00ff00', blend: 'nope' } },
      { type: 'rect', name: 'gr2', shape: { x: 140, y: 20, width: 40, height: 30 }, style: { fill: '#0000ff' } },
      { type: 'rect', name: 'gr3', shape: { x: 200, y: 20, width: 40, height: 30 }, style: { fill: '#00ffff', blend: 'screen' } },
      { type: 'rect', name: 'gr4', shape: { x: 260, y: 20, width: 40, height: 30 }, style: { fill: '#ff00ff', blend: 'Darken' } }] },
    [0], { y: true }],
    // [R7-Y] 4. a stroke colour of no width is still the canvas' strokeStyle
    //    (bindPathAndTextCommonStyle assigns every string stroke)
    ['y-stroke-zero', vv([{ type: 'bar', barWidth: 20, data: [
      { value: [2, 5], itemStyle: { borderColor: '#0000ff', borderWidth: 2 } },
      { value: [4, 5], itemStyle: { borderColor: '#00ff00', borderWidth: 0 } },
      { value: [6, 5], itemStyle: { borderColor: 'nope', borderWidth: 2 } },
      { value: [8, 5], itemStyle: { borderColor: 'bad', borderWidth: 3 } }] }]), [0], { y: true }],
    // [R7-Y] 5. an end symbol in the line's enter animation hands the canvas
    //    its transform then (placed at the percent, scaled by it): what an
    //    effect symbol of no transform is drawn under after it
    ['y-tf-enter-end', Object.assign(vv(LNC({ symbol: 'triangle', symbolSize: [12] },
      [{ coords: [[1, 8], [9, 5]] }, { coords: [[1, 3], [9, 1]] }], { symbol: ['none', 'arrow'], symbolSize: 10 })),
    { animation: true, animationDuration: 1000, animationEasing: 'linear' }), [0, 300, 600, 1200],
    { y: true, anim: true }],
    // [R7-Y] 6. a lines end symbol hit exactly on a vertex or an edge: its
    //    own Path.contain, in the symbol's frame
    ['y-hit-ends', vv(LNC({ show: false }, [{ coords: [[1, 8], [9, 5]] }, { coords: [[1, 2], [7, 4]] },
      { coords: [[2, 6], [2, 1]] }], { symbol: ['diamond', 'arrow'], symbolSize: [14, 10],
      lineStyle: { color: '#999', opacity: 1, width: 1 } })),
    [0], { y: true, probes: 'end-verts' }],
    // [R7-Y] 7. a label's font the canvas refuses: the one the text before
    //    it left (the canvas' own '10px sans-serif' before any)
    ['y-font', vv([{ type: 'bar', barWidth: 16, label: { show: true, position: 'top', formatter: 'Ab' }, data: [
      { value: [1, 3], label: { fontWeight: 'heavy' } },
      { value: [2, 3], label: { fontSize: 16, fontWeight: 'bold', fontFamily: 'serif' } },
      { value: [3, 3], label: { fontWeight: 'heavy' } },
      { value: [4, 3], label: { fontStyle: 'slanted', fontSize: 9 } },
      { value: [5, 3], label: { fontSize: '12abcpx' } },
      { value: [6, 3], label: { fontSize: 11, fontWeight: 600 } },
      { value: [7, 3], label: { fontSize: '13px', fontWeight: 'Bolder' } },
      { value: [8, 3], label: { fontWeight: '450', fontSize: 10 } },
      { value: [9, 3], label: { fontStyle: 'Italic', fontSize: 14 } }] }]), [0], { y: true }],
    // ---- [R7-AB] (recorded as the y- ones) ----
    // 1. a lines end symbol in the enter animation, hit on its own vertices
    //    and the middles of its edges (y-tf-enter-end's chart). Scaled to
    //    nought at first, it is not brushed: its first brush builds its path
    //    and stores it in a Float32Array (toStatic), which Path.contain then
    //    reads -- y-tf-enter-end's record read its paint rect first, and the
    //    path made then stays in doubles: pristine
    ['ab-tf-enter-end-hits', Object.assign(vv(LNC({ symbol: 'triangle', symbolSize: [12] },
      [{ coords: [[1, 8], [9, 5]] }, { coords: [[1, 3], [9, 1]] }], { symbol: ['none', 'arrow'], symbolSize: 10 })),
    { animation: true, animationDuration: 1000, animationEasing: 'linear' }), [0, 300, 600, 1200],
    { y: true, anim: true, probes: 'end-verts', pristine: true }],
    // 2. a block starts from the ground: a half-transparent scatter of an
    //    unreadable colour under a moving effect is, in the effect's block,
    //    the canvas' own black at half over the ground -- never over the
    //    whole paint's green (an opaque one, y-dirty-scatter's, hides what
    //    lies under it)
    ['ab-dirty-alpha', vv([{ type: 'scatter', symbolSize: 40, itemStyle: { color: '#00aa00' }, data: [[8, 9]] },
      { type: 'scatter', symbolSize: 40, itemStyle: { color: 'nope', opacity: 0.5 }, data: [[3, 5]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5], [9, 5]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // [R7-AB] 3. a text span's shadow offset of no finite number (`'abc' ||
    //    0` is 'abc', dpr times it none): refused, the canvas' kept -- only
    //    where the span casts one (textShadowBlur above nought); a rich
    //    token's blur of no number over the label's (hasShadow by either,
    //    the token's 'zz' then refused)
    ['ab-sh-text', vv([{ type: 'scatter', clip: false, symbolSize: 12,
      itemStyle: { shadowColor: '#ff0000', shadowBlur: 2, shadowOffsetX: 4, shadowOffsetY: 3 }, data: [
        { value: [2, 2] },
        { value: [4, 4], label: { show: true, formatter: 'Ab', textShadowColor: '#00ff00', textShadowBlur: 3,
          textShadowOffsetX: 'abc', textShadowOffsetY: 'Infinity' } },
        { value: [6, 6], label: { show: true, formatter: 'Cd', textShadowColor: '#0000ff', textShadowBlur: '2',
          textShadowOffsetX: '5', textShadowOffsetY: '' } },
        { value: [8, 8], label: { show: true, formatter: '{a|Ef}', rich: { a: { textShadowBlur: 'zz', textShadowOffsetX: 'q' } },
          textShadowColor: '#ff00ff', textShadowBlur: 4, textShadowOffsetX: 2 } },
        { value: [9, 3], label: { show: true, formatter: 'Gh', textShadowOffsetX: 'abc' } }] }]), [0], { y: true }],
    // (R7-AB after R7-AA: each span sets the shadowColor -- `token ||
    //    style || 'transparent'` where it casts one --, a refused one keeping
    //    the span's before it: the second span of the first label the first
    //    span's green, not the symbols' red; a span whose blur and colour are
    //    both refused keeps both)
    ['ab-sh-text-colour', vv([{ type: 'scatter', clip: false, symbolSize: 12,
      itemStyle: { shadowColor: '#ff0000', shadowBlur: 2 }, data: [
        { value: [2, 2] },
        { value: [4, 4], label: { show: true, formatter: '{a|Ab}{b|Cd}', textShadowBlur: 2,
          rich: { a: { textShadowColor: '#00ff00' }, b: { textShadowColor: 'nope' } } } },
        { value: [7, 7], label: { show: true, formatter: '{a|Ef}', textShadowBlur: 3,
          rich: { a: { textShadowBlur: 'abc', textShadowColor: 'nope' } } } }] }]), [0], { y: true }],
    // [R7-AB] 4. a gradient under a transform that is no similarity: a
    //    symbol's frame scaled unevenly -- its own radial gradient is an
    //    ellipse (the circle in its frame), and the CanvasGradient the canvas
    //    keeps for the next symbol (made in the first's frame) lands under
    //    that one's: an ellipse again, a linear one's stripes slanted
    ['ab-grad-ellipse', vv([{ type: 'scatter', symbol: 'rect', symbolSize: [40, 16], itemStyle: { color: { type: 'radial', x: 0.3,
      y: 0.4, r: 0.6, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }, data: [[3, 5]] },
    { type: 'scatter', symbol: 'rect', symbolSize: [16, 44], itemStyle: { color: 'nope' }, data: [[6, 6]] }]), [0], { y: true }],
    ['ab-grad-linear-skew', vv([{ type: 'scatter', symbol: 'rect', symbolSize: [40, 16], symbolRotate: 30,
      itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 1, y2: 1,
        colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }, data: [[3, 5]] },
    { type: 'scatter', symbol: 'rect', symbolSize: [16, 44], symbolRotate: -20, itemStyle: { color: 'nope' }, data: [[6, 6]] }]),
    [0], { y: true }],
    // (a gradient made in a uniform frame -- a circle there -- held for a
    //    symbol scaled unevenly: back in the first frame, an ellipse under
    //    the second; its radius the first frame's)
    ['ab-grad-held-ellipse', vv([{ type: 'scatter', symbol: 'rect', symbolSize: 20, itemStyle: { color: { type: 'radial', x: 0.3,
      y: 0.4, r: 0.6, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }, data: [[3, 5]] },
    { type: 'scatter', symbol: 'rect', symbolSize: [40, 14], itemStyle: { color: 'nope' }, data: [[6, 6]] }]), [0], { y: true }],
    // (the same turned a quarter: its frame's diagonal nought, a shear to
    //    the first's all the same)
    ['ab-grad-held-turned', vv([{ type: 'scatter', symbol: 'rect', symbolSize: 20, itemStyle: { color: { type: 'radial', x: 0.3,
      y: 0.4, r: 0.6, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }, data: [[3, 5]] },
    { type: 'scatter', symbol: 'rect', symbolSize: [40, 14], symbolRotate: 90, itemStyle: { color: 'nope' }, data: [[6, 6]] }]),
    [0], { y: true }],
    // [R7-AB] 5. a trail under useDirtyRect: its layer (the series' zlevel,
    //    motionBlur) is faded whole every paint (the last frame drawn back
    //    at lastFrameAlpha), then only the blocks round what moved are
    //    brushed -- a line away from every block fades frame by frame
    ['ab-dirty-trail', vv(LN({ color: '#ff00ff', symbolSize: 8, period: 1, trailLength: 0.2 },
      [{ coords: [[1, 8], [9, 8]] }, { coords: [[1, 3], [9, 3]] }], { lineStyle: { color: '#0000ff', width: 3, opacity: 1 } })),
    [0, 20, 40, 60, 80], { y: true, dirty: true }],
    // (the same on a zlevel of its own above the axes': that layer's)
    ['ab-dirty-trail-z', Object.assign(vv(LN({ color: '#ff00ff', symbolSize: 8, period: 1, trailLength: 0.2 },
      [{ coords: [[1, 8], [9, 8]] }, { coords: [[1, 3], [9, 3]] }], { zlevel: 1, lineStyle: { color: '#0000ff', width: 3, opacity: 1 } })),
    { xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false } } }),
    [0, 20, 40, 60, 80], { y: true, dirty: true }],
    // [R7-AB] 6. a dirty block starts from the canvas' own state and brushes
    //    the components meeting it too: a scatter of an unreadable colour
    //    under a moving effect takes, in its block, the fill of the axis
    //    label in that block (the y axis' inside one), or none (the canvas'
    //    black) -- the whole paint's is the x axis' labels', drawn last
    ['ab-dirty-axes', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 36, itemStyle: { color: 'nope', opacity: 1 }, data: [[0.2, 5], [5, 7]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[0.2, 5], [9.4, 5]] }, { coords: [[5, 7], [9.4, 7]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { xAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#aa00aa' } }),
      yAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#00aa00', inside: true } }) }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // (a split line two px above the block: its paint rect is its
    //    Line's bounds grown by max(width, strokeContainThreshold 5), so it
    //    meets the block and hands it its stroke -- the ring of a symbol of
    //    an unreadable border in the block is the split line's green)
    ['ab-dirty-axes-stroke', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 40, itemStyle: { color: '#ffffff', opacity: 1, borderColor: 'nope',
        borderWidth: 4 }, data: [[2.35, 5.6]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5.6], [9, 5.6]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { yAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false }, splitLine: { lineStyle: { color: '#00ff00' } } } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // (R7-AB after R7-AA: a split area a Rect a band, a split line a Line
    //    a mark -- only the band and the line meeting the block are brushed
    //    in it: the scatter of an unreadable colour takes the blue of the band
    //    it is in, the ring of an unreadable border the red of the line above
    //    it; the whole paint the last band's green, the last line's blue)
    ['ab-dirty-bands', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 36, itemStyle: { color: 'nope', opacity: 1 }, data: [[0.2, 5]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[0.2, 5], [9.4, 5]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { yAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false }, splitLine: { show: false },
      splitArea: { show: true, areaStyle: { color: ['#ff0000', '#00ff00', '#0000ff'] } } } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    ['ab-dirty-stroke-inks', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 40, itemStyle: { color: '#ffffff', opacity: 1, borderColor: 'nope',
        borderWidth: 4 }, data: [[2.35, 5.6]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5.6], [9, 5.6]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { yAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
      splitLine: { lineStyle: { color: ['#ff0000', '#00ff00', '#0000ff'] } } } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // (a split line's shadow grows its paint rect: the line 13 px above the
    //    block's centre meets it by its blur, not by its pen)
    ['ab-dirty-stroke-shadow', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 40, itemStyle: { color: '#ffffff', opacity: 1, borderColor: 'nope',
        borderWidth: 4 }, data: [[2.35, 5.3]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5.3], [9, 5.3]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { yAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
      splitLine: { lineStyle: { color: '#00ff00', shadowBlur: 12, shadowColor: 'rgba(0,0,0,0.2)' } } } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // (a state's change repainted in blocks, the static layer's: the same)
    ['ab-dirty-hover-axes', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 36, itemStyle: { color: 'nope', opacity: 1 }, data: [[0.2, 5], [5, 7]] },
      { type: 'scatter', clip: false, symbolSize: 8, itemStyle: { color: '#ff00ff', opacity: 1 }, emphasis: { scale: 2 },
        data: [[0.2, 5.2], [5, 7.2]] }]),
    { xAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#aa00aa' } }),
      yAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#00aa00', inside: true } }) }),
    [0, 10], { y: true, dirty: true, acts: { 1: [{ type: 'highlight', seriesIndex: 1 }] } }],
    // [R7-AB] 7. fonts the canvas refuses elsewhere: a rich text's token
    //    (its own font refused: the one the span before left); the axes'
    //    labels drawn before the series (their font left on the canvas for
    //    the first series label whose own is refused); an axis label's own
    //    refused font (the graphic text's under it)
    ['ab-font-rich', vv([{ type: 'scatter', clip: false, symbolSize: 6, label: { show: true, position: 'top' }, data: [
      { value: [2, 3], label: { formatter: '{a|Ab}{b|Cd}', rich: { a: { fontSize: 15, fontFamily: 'serif' },
        b: { fontWeight: 'heavy' } } } },
      { value: [5, 3], label: { formatter: '{a|Ef}', rich: { a: { fontStyle: 'slanted', fontSize: 11 } } } },
      { value: [8, 3], label: { formatter: '{a|Gh}{b|Ij}', rich: { a: { fontSize: '13px', fontWeight: 'bold' },
        b: { fontSize: '12abcpx' } } } },
      // (a token naming its size alone takes the label's refused weight:
      // richInheritPlainLabel)
      { value: [9.5, 6], label: { fontWeight: 'heavy', formatter: '{a|Kl}', rich: { a: { fontSize: 17 } } } }] }]),
    [0], { y: true }],
    ['ab-font-ground', Object.assign(vv([{ type: 'scatter', clip: false, symbolSize: 6,
      label: { show: true, position: 'top', formatter: 'Ab' }, data: [
        { value: [2, 3], label: { fontWeight: 'heavy' } }, { value: [5, 3], label: { fontSize: 11 } }] }]),
    { xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false },
      axisLabel: { color: '#112233', fontSize: 14, fontFamily: 'monospace' } } }), [0], { y: true }],
    ['ab-font-axis', Object.assign(vv([{ type: 'scatter', clip: false, symbolSize: 6,
      label: { show: true, position: 'top', formatter: 'Ab' }, data: [
        { value: [2, 3], label: { fontStyle: 'slanted' } }, { value: [5, 3], label: { fontSize: 11 } }] }]),
    { graphic: [{ type: 'text', z: -1, x: 20, y: 20, style: { text: 'G', fill: '#000', fontSize: 16, fontWeight: 'bold',
      fontFamily: 'serif' } }],
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false },
        axisLabel: { color: '#112233', fontWeight: 'heavy' } } }), [0], { y: true }],
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
    // ---- [R7-Z] a component's own refused values; what the components
    //      drawn before the series hand the canvas ----
    // 1. cartesian axes: by z2 (split lines, then line and name, ticks,
    //    labels, arrows), the y axes' before the x axes'
    ['z-ax-refused', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, axisLine: { lineStyle: { color: 'nope', width: 'Infinity' } },
        axisTick: { lineStyle: { color: '#ff0000', width: 3 } }, axisLabel: { color: 'bad' },
        splitLine: { lineStyle: { color: '#00ff00', width: 2 } } },
      yAxis: { type: 'value', min: 0, max: 10, axisLine: { show: true, lineStyle: { color: '#0000ff', width: 4 } },
        axisLabel: { color: '#123456' }, splitLine: { lineStyle: { color: 'nope' } } },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: 'nope' } }] }, [0], { w: true, z: true }],
    ['z-ax-phase-cap', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false },
        axisLine: { lineStyle: { color: '#ff0000', type: 'dashed', dashOffset: 'abc', cap: 'Round' } } },
      yAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisLabel: { show: false },
        axisLine: { show: true, lineStyle: { color: '#0000ff', width: 2, type: [3, 2], dashOffset: 2, cap: 'square' } } },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#00ff00', borderColor: '#000', borderWidth: 1,
        borderType: 'dashed', borderDashOffset: 'zz' } }] }, [0], { w: true, z: true }],
    // the graphic component's elements of z under 0 first; a name before its line
    ['z-ax-name-gfx', { animation: false, graphic: [{ type: 'rect', z: -1, shape: { x: 10, y: 10, width: 20, height: 20 },
      style: { fill: '#ff0000', stroke: '#00ff00', lineWidth: 3 } }],
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisTick: { show: false },
        axisLine: { lineStyle: { color: 'nope', width: 'Infinity' } }, axisLabel: { color: 'nope' },
        name: 'Xx', nameTextStyle: { color: 'nope' } },
      yAxis: { show: false, type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#0000ff' } }] }, [0], { w: true, z: true }],
    // a name before the labels: the fill it keeps is the graphic's, not theirs
    ['z-ax-name-order', { animation: false, graphic: [{ type: 'rect', z: -1, shape: { x: 10, y: 10, width: 20, height: 20 },
      style: { fill: '#ff0000' } }],
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisTick: { show: false },
        axisLine: { lineStyle: { color: '#0000ff' } }, axisLabel: { color: '#00ff00' }, name: 'Xx', nameTextStyle: { color: 'nope' } },
      yAxis: { show: false, type: 'value', min: 0, max: 10 },
      series: [] }, [0], { w: true, z: true }],
    // a dash word under an infinite width: [Infinity, Infinity], refused -- solid
    ['z-ax-tick-inf-dash', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisLabel: { show: false },
        axisLine: { lineStyle: { color: '#ff0000', width: 3 } },
        axisTick: { show: true, lineStyle: { color: 'nope', width: 'Infinity', type: 'dashed' } } },
      yAxis: { show: false, type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#0000ff', borderColor: 'nope', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    // 2. a label's own colours the canvas refuses; a text span's miterLimit
    //    (TSpan's 2) kept by a symbol that writes one below nought
    ['z-label', Object.assign(vv([
      { type: 'scatter', data: [[3, 3]], itemStyle: { color: '#ff0000', borderColor: '#00ff00', borderWidth: 2 },
        label: { show: true, formatter: 'Ab', color: 'nope', textBorderColor: 'bad', textBorderWidth: 2 } },
      { type: 'scatter', z: 3, data: [[6, 6]], itemStyle: { color: 'nope', borderColor: '#0000ff', borderWidth: 2,
        borderMiterLimit: -1 } }])), [0], { w: true, z: true }],
    // a rich text's own fill the canvas refuses
    ['z-label-rich', Object.assign(vv([
      { type: 'scatter', data: [[3, 3]], itemStyle: { color: '#ff0000' },
        label: { show: true, formatter: '{a|Ab}', rich: { a: { color: 'nope' } } } }])), [0], { w: true, z: true }],
    // 3. after the series: a legend's text, a title's box and text
    ['z-legend-text', Object.assign(vv([{ type: 'scatter', name: 'A', data: [[5, 5]],
      itemStyle: { color: '#ff0000' } }]), { legend: { left: 20, top: 10, textStyle: { color: 'nope' } } }),
    [0], { w: true, z: true }],
    ['z-title', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 3 } }]), { title: { text: 'Ab', subtext: 'Cd', left: 20, top: 10,
      textStyle: { color: 'nope' }, subtextStyle: { color: 'bad' }, backgroundColor: 'nope', borderColor: 'nope',
      borderWidth: 'Infinity' } }), [0], { w: true, z: true }],
    // 4. polar and single axes: their views' order (single, radius, angle)
    //    and parts (an angle axis' labels and merged ticks at z2 0, merged
    //    split paths filled '#000')
    ['z-polar', { animation: false, polar: { radius: 100 },
      angleAxis: { type: 'value', min: 0, max: 10, axisLine: { lineStyle: { color: '#ff00ff', width: 3 } },
        axisLabel: { color: 'nope' }, splitLine: { lineStyle: { color: 'nope', width: 'Infinity' } },
        axisTick: { lineStyle: { color: 'nope' } } },
      radiusAxis: { type: 'value', min: 0, max: 10, axisLine: { lineStyle: { color: 'nope', type: 'dashed', dashOffset: 'abc' } },
        axisLabel: { color: '#0000ff' }, splitLine: { lineStyle: { color: '#00aa00', type: [2, 2], dashOffset: 1 } } },
      series: [{ type: 'scatter', coordinateSystem: 'polar', data: [[5, 5]], itemStyle: { color: 'nope' } }] },
    [0], { w: true, z: true }],
    ['z-single', { animation: false, singleAxis: { type: 'value', min: 0, max: 10,
      axisLine: { lineStyle: { color: '#ff00ff', width: 3 } }, axisTick: { lineStyle: { color: 'nope', width: 'Infinity' } },
      axisLabel: { color: 'nope' }, splitLine: { lineStyle: { color: '#00ffff' } } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [5], itemStyle: { color: 'nope' } }] },
    [0], { w: true, z: true }],
    // 5. components in the list after the series: their own refused colours
    ['z-toolbox', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 2 } }]), { toolbox: { right: 20, top: 10, feature: { restore: {} },
      borderColor: '#123456', borderWidth: 1, iconStyle: { borderColor: 'nope' } } }), [0], { w: true, z: true }],
    ['z-visualmap', Object.assign(vv([{ type: 'scatter', data: [[5, 5, 3]], itemStyle: { borderColor: '#00ff00',
      borderWidth: 2 } }]), { visualMap: { type: 'piecewise', left: 20, top: 10, min: 0, max: 6, splitNumber: 2,
      dimension: 2, textStyle: { color: 'nope' }, inRange: { color: ['#ff0000', '#0000ff'] } } }), [0], { w: true, z: true }],
    // ---- [R7-AA] (recorded as the z- ones) ----
    // 1. an axis' pens: their shadow, join and miterLimit, drawn and handed on
    ['aa-ax-pens', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
        axisLine: { lineStyle: { color: '#ff0000', width: 3, shadowBlur: 4, shadowColor: '#00ff00', shadowOffsetX: 2,
          join: 'round', miterLimit: 4 } },
        axisTick: { show: true, lineStyle: { color: '#0000ff', width: 2, shadowBlur: 3, shadowColor: 'rgba(0,0,0,0.5)',
          join: 'bevel', miterLimit: 'abc' } },
        minorTick: { show: true, lineStyle: { shadowBlur: 2, shadowColor: '#ff00ff' } },
        splitLine: { lineStyle: { color: '#888888', shadowBlur: -1, join: 'Round' } },
        minorSplitLine: { show: true, lineStyle: { color: '#999999', shadowBlur: 5, shadowColor: 'nope', miterLimit: 3 } } },
      yAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisLabel: { show: false },
        axisLine: { show: true, lineStyle: { color: '#123456', shadowBlur: 6, shadowColor: '#654321', shadowOffsetY: 3 } } },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000', borderColor: '#0000ff', borderWidth: 2,
        shadowBlur: 3, shadowColor: 'nope', borderJoin: 'Bevel', borderMiterLimit: -2 } }] }, [0], { w: true, z: true }],
    ['aa-polar-pens', { animation: false, polar: { radius: 100 },
      angleAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
        axisLine: { lineStyle: { color: '#ff00ff', width: 3, shadowBlur: 2, shadowColor: '#00ff00', join: 'round' } },
        axisTick: { lineStyle: { shadowBlur: 3, shadowColor: '#0000ff', miterLimit: 5 } },
        splitLine: { lineStyle: { color: '#00aa00', shadowBlur: 4, shadowColor: 'nope' } } },
      radiusAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
        axisLine: { lineStyle: { color: '#0000ff', shadowBlur: 5, shadowColor: '#ff0000', join: 'bevel' } },
        splitLine: { lineStyle: { color: '#aa0000', shadowBlur: 2, shadowColor: '#00ffff', miterLimit: 7 } } },
      series: [{ type: 'scatter', coordinateSystem: 'polar', data: [[5, 5]], itemStyle: { color: '#ff0000',
        shadowBlur: 2, shadowColor: 'nope', borderMiterLimit: -1, borderColor: '#000', borderWidth: 1 } }] },
    [0], { w: true, z: true }],
    ['aa-single-pens', { animation: false, singleAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
      axisLine: { lineStyle: { color: '#ff00ff', width: 3, shadowBlur: 3, shadowColor: '#00ff00', join: 'bevel' } },
      axisTick: { lineStyle: { color: '#0000ff', shadowBlur: 2, shadowColor: '#ff0000', miterLimit: 6 } },
      splitLine: { lineStyle: { color: '#00ffff', shadowBlur: 4, shadowColor: '#000080', join: 'round' } } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [5], itemStyle: { color: '#00ff00',
        shadowBlur: 2, shadowColor: 'nope' } }] },
    [0], { w: true, z: true }],
    ['aa-parallel-pens', { animation: false, parallel: { left: 40, right: 40, top: 40, bottom: 40 },
      parallelAxis: [{ dim: 0, min: 0, max: 10, axisLabel: { color: '#112233' },
        axisLine: { lineStyle: { color: '#ff0000', width: 2, shadowBlur: 3, shadowColor: '#00ff00', join: 'round', miterLimit: 3 } },
        axisTick: { lineStyle: { color: '#0000ff', shadowBlur: 2, shadowColor: '#ff00ff' } } },
      { dim: 1, min: 0, max: 10, axisLabel: { color: '#112233' }, axisLine: { lineStyle: { color: '#00aaaa', shadowBlur: 'x' } } }],
      series: [{ type: 'parallel', lineStyle: { color: '#ff8800', width: 2 }, data: [[3, 7]] }] }, [0], { w: true, z: true, timers: true }],
    ['aa-radar-pens', { animation: false, radar: { radius: 90, indicator: [{ max: 10 }, { max: 10 }, { max: 10 }],
      axisName: { show: false },
      axisLine: { lineStyle: { color: '#ff0000', width: 2, shadowBlur: 3, shadowColor: '#00ff00', join: 'bevel' } },
      splitLine: { lineStyle: { color: '#0000ff', shadowBlur: 2, shadowColor: '#ff00ff', join: 'round', miterLimit: 3 } },
      splitArea: { show: false } },
      series: [{ type: 'radar', symbol: 'none', lineStyle: { color: '#ff8800', shadowBlur: 2, shadowColor: 'nope' },
        data: [{ value: [3, 5, 7] }] }] }, [0], { w: true, z: true }],
    ['aa-timeline-pens', { animation: false, timeline: { axisType: 'category', left: 20, right: 20, bottom: 10, data: ['a', 'b'], autoPlay: false,
      label: { show: false }, controlStyle: { show: false }, itemStyle: { color: '#c0c9e6' },
      checkpointStyle: { color: '#6578ba', borderColor: '#6578ba' },
      lineStyle: { color: '#ff0000', width: 3, shadowBlur: 3, shadowColor: '#00ff00', join: 'round', miterLimit: 4 },
      progress: { lineStyle: { color: '#0000ff', shadowBlur: 2, shadowColor: '#ff00ff' } } },
      options: [{ series: [] }, { series: [] }] }, [0], { w: true, z: true }],
    ['aa-calendar-pens', { animation: false, calendar: { range: '2020-01', left: 40, top: 40, right: 40, height: 150,
      dayLabel: { show: false }, monthLabel: { show: false }, yearLabel: { show: false },
      splitLine: { lineStyle: { color: '#ff0000', width: 2, shadowBlur: 3, shadowColor: '#00ff00', join: 'bevel', miterLimit: 3 } },
      itemStyle: { color: '#ffffff', borderWidth: 0 } }, series: [] }, [0], { w: true, z: true }],
    // 2. refused values of the parallel axes (z 10, after the series), a
    //    timeline, a dataZoom slider
    ['aa-parallel-refused', { animation: false, parallel: { left: 40, right: 40, top: 40, bottom: 40 },
      parallelAxis: [{ dim: 0, min: 0, max: 10, name: 'P', nameTextStyle: { color: 'nope' },
        axisLine: { lineStyle: { color: 'nope', width: 'Infinity' } }, axisTick: { lineStyle: { color: 'bad' } },
        axisLabel: { color: 'nope' } },
      { dim: 1, min: 0, max: 10, axisLine: { lineStyle: { color: '#00aa00', width: 2, dashOffset: 'abc', type: 'dashed' } },
        axisLabel: { color: '#0000ff' } }],
      series: [{ type: 'parallel', lineStyle: { color: '#ff0000', width: 3 }, data: [[3, 7]] }] }, [0], { w: true, z: true, timers: true }],
    ['aa-timeline-refused', { animation: false, timeline: { axisType: 'category', left: 20, right: 20, bottom: 10, data: ['a', 'b', 'c'],
      autoPlay: false, lineStyle: { color: 'nope' }, itemStyle: { color: 'nope', borderColor: 'bad', borderWidth: 1 },
      checkpointStyle: { color: 'nope', borderColor: '#ff0000', borderWidth: 2 }, label: { color: 'nope' },
      controlStyle: { color: 'nope', borderColor: 'bad', borderWidth: 1 }, progress: { lineStyle: { color: 'bad' } } },
      options: [{ series: [] }, { series: [] }, { series: [] }] }, [0], { w: true, z: true }],
    ['aa-datazoom-refused', { animation: false, xAxis: { type: 'value', min: 0, max: 10, show: false },
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      dataZoom: [{ type: 'slider', left: 40, right: 40, bottom: 10, fillerColor: 'nope', borderColor: 'nope',
        handleStyle: { color: 'nope', borderColor: 'bad' }, moveHandleStyle: { color: 'nope' }, textStyle: { color: 'nope' },
        dataBackground: { lineStyle: { color: 'nope' }, areaStyle: { color: 'bad' } },
        selectedDataBackground: { lineStyle: { color: '#8292cc', opacity: 1 }, areaStyle: { color: '#c0c9e6', opacity: 1 } } }],
      series: [{ type: 'line', symbol: 'none', lineStyle: { color: '#ff0000' }, data: [[1, 2], [5, 8], [9, 3]] }] },
    [0], { w: true, z: true }],
    // the graphic component's own (the converter a timeline's elements share)
    ['aa-graphic-refused', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 3, borderType: [4, 2], borderDashOffset: 1, borderJoin: 'round', borderMiterLimit: 4 } }]),
    { graphic: [{ type: 'rect', z: 5, shape: { x: 20, y: 20, width: 30, height: 20 },
      style: { fill: 'nope', stroke: 'bad', lineWidth: 'Infinity', lineDash: [3, 3], lineDashOffset: 'x', lineJoin: 'Round',
        miterLimit: 'abc', lineCap: 'Square' } },
    { type: 'rect', z: 6, shape: { x: 60, y: 20, width: 30, height: 20 }, style: { fill: '#0000ff', stroke: '#ff00ff', lineWidth: 0 } },
    { type: 'circle', z: 7, shape: { cx: 120, cy: 30, r: 10 }, style: { fill: 'nope', stroke: 'bad', lineWidth: '2' } }] }),
    [0], { w: true, z: true }],
    // a richText tooltip's own refused colours: the box's fill and border,
    // the text's fill (TooltipRichContent: borderWidth 1, the border the
    // near point's colour)
    ['aa-tip-rich', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 3 } }]), { tooltip: { renderMode: 'richText', showDelay: 0,
      transitionDuration: 0, backgroundColor: 'nope', borderColor: 'bad', textStyle: { color: 'nope' },
      shadowBlur: 6, shadowColor: 'rgba(0,0,255,0.5)', shadowOffsetX: 2,
      formatter: 'Ab' } }),
    [0], { w: true, z: true, tip: true, acts: { 0: [{ type: 'showTip', seriesIndex: 0, dataIndex: 0 }] } }],
    // a time axis' labels: z2 10 plus their tick's level
    ['aa-time-labels', { animation: false, xAxis: AXC({ type: 'time', min: Date.UTC(2020, 11, 30), max: Date.UTC(2021, 0, 3),
      splitLine: { show: false }, axisTick: { show: false } }),
      yAxis: { show: false, type: 'value', min: 0, max: 10 }, useUTC: true,
      series: [{ type: 'scatter', data: [[Date.UTC(2021, 0, 1), 5]], itemStyle: { color: 'nope' } }] },
    [0], { w: true, z: true }],
    // an axis pointer's own refused values (its group the root's, after the list)
    ['aa-pointer-refused', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 3 } }]), { xAxis: { type: 'value', min: 0, max: 10, axisLine: { show: false },
      axisLabel: { show: false }, splitLine: { show: false }, axisTick: { show: false },
      axisPointer: { show: true, value: 4, status: 'show', label: { show: false },
        lineStyle: { color: 'nope', width: 'Infinity', type: 'dashed', dashOffset: 'x', cap: 'Round' } } } }),
    [0], { w: true, z: true }],
    // a refused join and miterLimit after a line's own; the minor ticks take
    // the tick model's own shadow
    ['aa-ax-join', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false }, splitLine: { show: false },
        axisLine: { lineStyle: { color: '#ff0000', width: 3, join: 'round', miterLimit: 4 } },
        axisTick: { show: true, shadowBlur: 4, shadowColor: '#00ffff',
          lineStyle: { color: '#0000ff', join: 'Round', miterLimit: 'abc' } },
        minorTick: { show: true } },
      yAxis: { show: false, type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#00ff00' } }] }, [0], { w: true, z: true }],
    // a dataZoom's unselected shadow its clip culls hands the canvas nothing
    ['aa-datazoom-culled', { animation: false, xAxis: { type: 'value', min: 0, max: 10, show: false },
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      dataZoom: [{ type: 'slider', left: 40, right: 40, bottom: 10, showDetail: false,
        fillerColor: 'rgba(0,0,255,0.2)', borderColor: '#e0e4f2', backgroundColor: 'transparent',
        handleStyle: { color: '#ffffff', borderColor: '#c0c9e6' }, moveHandleStyle: { color: '#8292cc', opacity: 1 },
        dataBackground: { lineStyle: { color: '#123456', opacity: 1 }, areaStyle: { color: '#654321', opacity: 1 } },
        selectedDataBackground: { lineStyle: { color: 'nope' }, areaStyle: { color: 'bad' } } }],
      series: [{ type: 'line', symbol: 'none', lineStyle: { color: '#ff0000' }, data: [[1, 2], [5, 8], [9, 3]] }] },
    [0], { w: true, z: true }],
    // 3. the polar's and the single axis' split areas, in paint order
    ['aa-polar-area', { animation: false, graphic: [{ type: 'rect', z: -1, shape: { x: 10, y: 10, width: 20, height: 20 },
      style: { fill: '#ff0000' } }], polar: { radius: 100 },
      angleAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { show: false }, splitArea: { show: true,
        areaStyle: { color: ['#0000ff', 'nope'] } } }),
      radiusAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { show: false }, splitArea: { show: true,
        areaStyle: { color: ['nope', '#00ff00'] } } }),
      series: [{ type: 'scatter', coordinateSystem: 'polar', data: [[5, 5]], itemStyle: { color: 'nope' } }] },
    [0], { w: true, z: true }],
    ['aa-single-area', { animation: false, graphic: [{ type: 'rect', z: -1, shape: { x: 10, y: 10, width: 20, height: 20 },
      style: { fill: '#ff0000' } }], singleAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { show: false },
      splitArea: { show: true, areaStyle: { color: ['nope', '#00ff00'] } } }),
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [5], itemStyle: { color: 'nope' } }] },
    [0], { w: true, z: true }],
    // radar's component (z 0) among the cartesian axes' parts by z2
    ['aa-radar-order', { animation: false, grid: { left: 40, right: 40, top: 40, bottom: 40 },
      xAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#00ff00' }, splitLine: { lineStyle: { color: '#0000ff' } } }),
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      radar: { radius: 60, indicator: [{ max: 10 }, { max: 10 }, { max: 10 }], axisName: { color: 'nope' },
        axisLine: { lineStyle: { color: 'nope' } }, splitLine: { lineStyle: { color: 'bad' } },
        splitArea: { areaStyle: { color: ['nope', '#ffff00'] } } },
      series: [{ type: 'radar', symbol: 'none', lineStyle: { color: '#ff8800' }, data: [{ value: [3, 5, 7] }] }] },
    [0], { w: true, z: true }],
    // 4. a zero width with a stroke colour; a transparent background
    ['aa-zero-width', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false },
        axisLine: { lineStyle: { color: '#ff0000', width: 0 } } },
      yAxis: { show: false, type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#0000ff', borderColor: 'nope', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    ['aa-toolbox-zero', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 2 } }]), { toolbox: { right: 20, top: 10, feature: { restore: {} },
      borderColor: '#123456', iconStyle: { borderColor: 'nope', color: 'nope' } } }), [0], { w: true, z: true }],
    ['aa-legend-zero', Object.assign(vv([{ type: 'scatter', name: 'A', data: [[5, 5]],
      itemStyle: { color: '#ff0000', borderColor: 'nope', borderWidth: 2 } }]),
    { legend: { left: 20, top: 10, borderColor: '#123456', textStyle: { color: '#112233' } } }), [0], { w: true, z: true }],
    ['aa-title-zero', Object.assign(vv([{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff0000',
      borderColor: '#00ff00', borderWidth: 3 } }]), { title: { text: 'Ab', left: 20, top: 10, borderColor: '#123456',
      textStyle: { textBorderColor: 'nope', textBorderWidth: 2, color: '#000000' } } }), [0], { w: true, z: true }],
    // 5. a gradient axis pen: the canvas keeps the gradient
    ['aa-ax-grad', { animation: false,
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false },
        axisLine: { lineStyle: { color: GRAD, width: 2 } } },
      yAxis: { show: false, type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: 'nope', borderColor: 'bad', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    // 6. a label's refused colours in a state, its textShadowColor
    ['aa-label-emph', Object.assign(vv([
      { type: 'scatter', data: [[3, 3], [6, 6]], itemStyle: { color: '#ff0000' },
        label: { show: true, formatter: 'Ab', color: '#00ff00', textShadowColor: 'nope', textShadowBlur: 2 },
        emphasis: { label: { color: 'bad', textBorderColor: 'nope', textBorderWidth: 2 } } }])),
    [0, 1], { w: true, z: true, acts: { 1: [{ type: 'highlight', seriesIndex: 0, dataIndex: 1 }] } }],
    // ---- [R7-AD] (recorded as the aa- ones) ----
    // 1. what sorts among the axes' parts by z, z2 and the views' order (the
    //    zr root's: single, radius, angle, polar, geo, radar, y, x, grid --
    //    an axis a view of its own): a geo's regions (z 0) before the x
    //    axis' parts of their z2; a series of z under nought before every
    //    axis part, one of z 0 between the split lines (z2 0) and the line
    //    (z2 1); a matrix (z -50) before them all; a second x axis' parts
    //    after the first's of their z2, not interleaved with them
    ['ad-geo-order', { animation: false, grid: { left: 40, right: 40, top: 40, bottom: 40 },
      xAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#00ff00' }, splitLine: { lineStyle: { color: '#0000ff' } } }),
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      geo: { map: 'ad-sq', left: 100, top: 80, width: 200, height: 140, silent: true,
        itemStyle: { areaColor: 'nope', borderColor: 'bad', borderWidth: 2 } },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    ['ad-series-z', { animation: false, grid: { left: 40, right: 40, top: 40, bottom: 40 },
      xAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#00ff00' }, splitLine: { lineStyle: { color: '#0000ff' } } }),
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      series: [{ type: 'scatter', z: -1, data: [[3, 3]], itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 } },
        { type: 'scatter', z: 0, data: [[5, 5]], itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 } },
        { type: 'scatter', data: [[7, 7]], itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    // (the matrix's own colours written: its defaults are the theme's tokens,
    // the port's its skin's; the x axis' split lines refuse theirs and take
    // the matrix's last stroke)
    ['ad-matrix-under', { animation: false, grid: { left: 40, right: 40, top: 40, bottom: 40 },
      xAxis: AXC({ type: 'value', min: 0, max: 10, axisLabel: { color: '#00ff00' }, splitLine: { lineStyle: { color: 'nope' } } }),
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      matrix: { left: 80, right: 80, top: 80, bottom: 80,
        x: { data: ['a', 'b'], label: { color: '#112233' }, itemStyle: { color: '#eeeeee', borderColor: '#223344' },
          dividerLineStyle: { color: '#334455' } },
        y: { data: ['c'], label: { color: '#112233' }, itemStyle: { color: '#eeeeee', borderColor: '#223344' },
          dividerLineStyle: { color: '#334455' } },
        body: { itemStyle: { borderColor: '#445566' } }, corner: { itemStyle: { borderColor: '#556677' } },
        backgroundStyle: { borderColor: '#667788' } },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: 'nope', borderColor: 'nope', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    ['ad-two-x', { animation: false, grid: { left: 40, right: 40, top: 40, bottom: 40 },
      xAxis: [AXC({ type: 'value', min: 0, max: 10, axisLabel: { show: false },
        splitLine: { lineStyle: { color: ['#ff0000', '#00ff00', '#0000ff'] } } }),
      AXC({ type: 'value', position: 'top', min: 0, max: 10, axisLabel: { show: false }, axisTick: { show: false },
        axisLine: { lineStyle: { color: 'nope' } }, splitLine: { show: true, lineStyle: { color: 'nope' } } })],
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      series: [{ type: 'scatter', data: [[5, 5]], itemStyle: { color: '#ff00ff', borderColor: 'nope', borderWidth: 2 } }] },
    [0], { w: true, z: true }],
    // 2. [R7-AD] fonts the canvas refuses in the rest of the texts (recorded
    //    as the y- ones, the components' displayables keyed as the z- ones):
    //    the font the text before left -- a title's text and subtext after
    //    the series' labels; a legend's words, a visualMap's; a polar's and a
    //    single axis' labels after the graphic's text under them; an axis'
    //    rich label's span
    ['ady-font-title', Object.assign(vv([{ type: 'scatter', clip: false, symbolSize: 6,
      label: { show: true, position: 'top', formatter: 'Ab', fontSize: 15, fontFamily: 'serif', fontWeight: 'bold' },
      data: [[5, 5]] }]), { title: { text: 'Tt', subtext: 'Ss', left: 20, top: 10,
      textStyle: { fontWeight: 'heavy', color: '#000' }, subtextStyle: { fontSize: '9abcpx', color: '#000' } } }),
    [0], { y: true, z: true }],
    ['ady-font-legend', Object.assign(vv([{ type: 'scatter', clip: false, name: 'Aa', symbolSize: 6,
      label: { show: true, position: 'top', formatter: 'Ab', fontSize: 13, fontFamily: 'monospace' }, data: [[5, 5]] },
    { type: 'scatter', clip: false, name: 'Bb', data: [[6, 6]] }]),
    { legend: { left: 20, top: 10, textStyle: { fontStyle: 'slanted', color: '#000' },
      data: ['Aa', { name: 'Bb', textStyle: { fontStyle: 'italic', fontSize: 11 } }] } }),
    [0], { y: true, z: true }],
    ['ady-font-vm', Object.assign(vv([{ type: 'scatter', clip: false, symbolSize: 6,
      label: { show: true, position: 'top', formatter: 'Ab', fontSize: 14, fontFamily: 'serif' }, data: [[5, 5, 3]] }]),
    { visualMap: { type: 'piecewise', left: 20, top: 10, min: 0, max: 6, splitNumber: 2, dimension: 2,
      textStyle: { fontSize: '12abcpx', color: '#000' }, inRange: { color: ['#ff0000', '#0000ff'] } } }),
    [0], { y: true, z: true }],
    ['ady-font-polar', { animation: false, graphic: [{ type: 'text', z: -1, x: 20, y: 20,
      style: { text: 'G', fill: '#000', fontSize: 16, fontWeight: 'bold', fontFamily: 'serif' } }],
      polar: { radius: 90 },
      angleAxis: { type: 'value', min: 0, max: 10, axisLabel: { color: '#112233', fontWeight: 'heavy' } },
      radiusAxis: { type: 'value', min: 0, max: 10, axisLabel: { color: '#112233', fontStyle: 'slanted' } },
      series: [] }, [0], { y: true, z: true }],
    ['ady-font-single', { animation: false, graphic: [{ type: 'text', z: -1, x: 20, y: 20,
      style: { text: 'G', fill: '#000', fontSize: 16, fontWeight: 'bold', fontFamily: 'serif' } }],
      singleAxis: { type: 'value', min: 0, max: 10, axisLabel: { color: '#112233', fontStyle: 'slanted' } },
      series: [] }, [0], { y: true, z: true }],
    ['ady-font-axis-rich', { animation: false, graphic: [{ type: 'text', z: -1, x: 20, y: 20,
      style: { text: 'G', fill: '#000', fontSize: 16, fontWeight: 'bold', fontFamily: 'serif' } }],
      xAxis: { type: 'value', min: 0, max: 10, splitLine: { show: false },
        axisLabel: { color: '#112233', formatter: '{a|{value}}', rich: { a: { fontWeight: 'heavy' } } } },
      yAxis: { type: 'value', min: 0, max: 10, show: false }, series: [] }, [0], { y: true, z: true }],
    // 3. [R7-AD] a dirty block counts a polar's, a single axis' part only where
    //    it was drawn (its getPaintRect: a merged path's union), and a line
    //    of no width that hands on its colour only where it lies: a symbol's
    //    ring of an unreadable border in a block away from them is the
    //    canvas' black, in one over them their colour
    ['ady-dirty-stroke-zero', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 40, itemStyle: { color: '#ffffff', opacity: 1, borderColor: 'nope',
        borderWidth: 4 }, data: [[2.35, 5], [2.35, 6]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5], [9, 5]] }, { coords: [[3, 6], [9, 6]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { yAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false },
      splitLine: { lineStyle: { color: '#ff0000', width: 0 } } } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    ['ady-dirty-stroke-polar', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 40, itemStyle: { color: '#ffffff', opacity: 1, borderColor: 'nope',
        borderWidth: 4 }, data: [[2.35, 5], [2.35, 8]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5], [9, 5]] }, { coords: [[3, 8], [9, 8]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { polar: { center: [130, 60], radius: 40 },
      angleAxis: { type: 'value', min: 0, max: 10, axisLine: { show: false }, axisTick: { show: false },
        axisLabel: { show: false }, splitLine: { lineStyle: { color: '#00ff00' } } },
      radiusAxis: { type: 'value', min: 0, max: 10, show: false } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    ['ady-dirty-stroke-single', Object.assign(vv([
      { type: 'scatter', clip: false, symbolSize: 40, itemStyle: { color: '#ffffff', opacity: 1, borderColor: 'nope',
        borderWidth: 4 }, data: [[2.35, 5], [2.35, 8]] },
      LN({ color: '#ff00ff', symbolSize: 8, period: 1 }, [{ coords: [[3, 5], [9, 5]] }, { coords: [[3, 8], [9, 8]] }],
        { lineStyle: { color: '#999', opacity: 0 }, z: 3 })]),
    { singleAxis: { type: 'value', min: 0, max: 10, left: 100, right: 100, top: 40, height: 40,
      axisLabel: { show: false }, axisTick: { show: false }, axisLine: { show: false },
      splitLine: { lineStyle: { color: '#00ff00' } } } }),
    [0, 20, 40, 60], { y: true, dirty: true }],
    // 5. [R7-AD] §282 (b): the root textStyle's shadow keys written as
    //    strings no number reads; a label's shadow and font in a state
    //    (emphasis) the canvas refuses
    ['ady-sh-root', vv([{ type: 'scatter', clip: false, symbolSize: 12,
      itemStyle: { shadowColor: '#ff0000', shadowBlur: 2, shadowOffsetX: 4, shadowOffsetY: 3 }, data: [
        { value: [2, 2] },
        { value: [4, 4], label: { show: true, formatter: 'Ab', textShadowColor: '#0000ff', textShadowBlur: 2 } },
        { value: [6, 6], label: { show: true, formatter: 'Cd' } },
        { value: [8, 8], label: { show: true, formatter: '{a|Ef}', rich: { a: {} }, textShadowBlur: 3 } }] }],
    { textStyle: { textShadowColor: '#00ff00', textShadowBlur: 'abc', textShadowOffsetX: 'x', textShadowOffsetY: '2' } }),
    [0], { y: true }],
    ['ady-sh-emph', vv([{ type: 'scatter', clip: false, symbolSize: 12,
      itemStyle: { shadowColor: '#ff0000', shadowBlur: 2, shadowOffsetX: 4, shadowOffsetY: 3 },
      label: { show: true, formatter: 'Ab', textShadowColor: '#0000ff', textShadowBlur: 2, textShadowOffsetX: 1 },
      emphasis: { scale: false, label: { textShadowBlur: 'abc', textShadowOffsetX: 'q', textShadowOffsetY: 'Infinity' } },
      data: [[2, 2], [5, 5], [8, 8]] }]),
    [0, 1], { y: true, acts: { 1: [{ type: 'highlight', seriesIndex: 0, dataIndex: 1 }] } }],
    ['ady-font-emph', vv([{ type: 'scatter', clip: false, symbolSize: 6,
      label: { show: true, position: 'top', formatter: 'Ab', fontSize: 15, fontFamily: 'serif' },
      emphasis: { scale: false, label: { fontWeight: 'heavy' } },
      data: [{ value: [2, 3], label: { fontSize: 11 } }, [5, 3], { value: [8, 3], label: { fontSize: 13 } }] }]),
    [0, 1], { y: true, acts: { 1: [{ type: 'highlight', seriesIndex: 0, dataIndex: 1 }] } }],
    // 4. [R7-AD] a graphic element's own gradient under a transform that is
    //    no similarity (scaled unevenly, turned): its CanvasGradient made
    //    against its getBoundingRect in its own frame -- an ellipse, slanted
    //    stripes (the custom series' elements are the same converter's)
    ['ady-grad-graphic', { animation: false, graphic: [
      { type: 'rect', name: 'gr0', x: 40, y: 40, scaleX: 3, shape: { x: 0, y: 0, width: 30, height: 60 },
        style: { fill: { type: 'radial', x: 0.3, y: 0.4, r: 0.6,
          colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } } },
      { type: 'rect', name: 'gr1', x: 260, y: 60, rotation: 0.5, scaleY: 0.4,
        shape: { x: -60, y: -60, width: 120, height: 120 },
        style: { fill: { type: 'linear', x: 0, y: 0, x2: 1, y2: 1,
          colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } } },
      { type: 'circle', name: 'gr2', x: 120, y: 220, scaleX: 2.5, shape: { cx: 0, cy: 0, r: 30 },
        style: { fill: { type: 'radial', x: 0.5, y: 0.5, r: 0.5,
          colorStops: [{ offset: 0, color: '#00ff00' }, { offset: 1, color: '#0000ff' }] } } }] },
    [0], { y: true }],
  ]);
}
function withPalette(list) {
  for (const c of list) if (c[3] && (c[3].w || c[3].y) && !c[1].color) c[1].color = PAL;
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
    // [R7-W] any other series' item graphics (its displayables in order)
    if (W && ['lines', 'graph', 'scatter', 'line', 'bar', 'pie'].indexOf(type) < 0) {
      const data = sm.getData();
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
    // [R7-Z] every component's displayables, in paint order
    if (Z) {
      const zc = new Map();
      // [R7-AA] a richText tooltip's element, on the root (no view's group)
      let tipEl = null;
      // [R7-AA] an axis pointer's group, on the root too
      const PTRS = new Map();
      for (const mt of ['xAxis', 'yAxis']) model.eachComponent(mt, (m, i) => {
        const v = chart.getViewOfComponentModel(m);
        if (v && v._axisPointer && v._axisPointer._group) PTRS.set(v._axisPointer._group, { mainType: mt + 'Pointer', index: i });
      });
      for (const v of chart._componentsViews || []) {
        if (v && v.type === 'tooltip' && v._tooltipContent && v._tooltipContent.el) tipEl = v._tooltipContent.el;
      }
      for (const el of chart.getZr().storage.getDisplayList(true)) {
        let p = el;
        let info = null;
        while (p) {
          if (p.__ecComponentInfo) { info = p.__ecComponentInfo; break; }
          if (AA && tipEl && p === tipEl) { info = { mainType: 'tooltip', index: 0 }; break; }
          if (AA && PTRS.has(p)) { info = PTRS.get(p); break; }
          p = p.parent || p.__hostTarget;
        }
        if (!info || info.mainType === 'series' || map.has(el) || !el.style) continue;
        const g = 'c.' + info.mainType + info.index + '.' + el.z2 + '.' + (el.style.text != null ? 't' : 'p');
        const n = zc.get(g) || 0;
        zc.set(g, n + 1);
        map.set(el, g + '.' + n);
      }
      return map;
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
  // [R7-Z] a component's text span: its text
  if (Z && key.slice(0, 2) === 'c.' && el.style && el.style.text != null) r.tx = String(el.style.text);
  // [R7-Y] every op of the sample, and the paint rect now
  if (Y) {
    r.yops = YOPS.get(el) || [];
    // [R7-AB] (a path's getBoundingRect before its first brush makes its
    // proxy: the brush then rebuilds the path from the doubles and never
    // stores it in a Float32Array -- the record would change what findHover
    // finds; a pristine case reads no paint rect off such an element)
    const pr = el.getPaintRect && !(PRISTINE && el instanceof Path && !el.path) ? el.getPaintRect() : null;
    r.pr = pr ? [pr.x, pr.y, pr.width, pr.height].map(hexOrNull) : null;
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
  V2 = !!opts.v2 || !!opts.w || !!opts.y;
  W = !!opts.w || !!opts.y;
  Z = !!opts.z;
  AA = id.slice(0, 3) === 'aa-' || id.slice(0, 3) === 'ad-' || id.slice(0, 4) === 'ady-';
  SEQ = 0;
  Y = !!opts.y;
  PRISTINE = !!opts.pristine;
  YPAINTS = [];
  YBLK = 0;
  YOPS = new Map();
  const dom = fakeCanvas(CW, CH);
  // [R7-Y] a case whose enter animation runs: echarts.env.node off (node
  // skips every transition)
  const nodeWas = echarts.env.node;
  if (opts.anim) echarts.env.node = false;
  // [R7-AA] a tooltip view renders nothing under env.node
  if (opts.tip) echarts.env.node = false;
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
        if (Y && YPAINTS.length) {
          const l = YPAINTS[YPAINTS.length - 1];
          YBLK = l.length;
          l.push(rect ? [rect.x, rect.y, rect.width, rect.height].map(hex) : null);
        }
        return orig.apply(this, arguments);
      };
      P.__r7wBlock = true;
    }
  }
  // [R7-Y] each paint of the layers
  if (Y) {
    const P = chart.getZr().painter.constructor.prototype;
    if (!P.__r7yPaint) {
      const orig = P._doPaintList;
      P._doPaintList = function () {
        if (Y) { YPAINTS.push([]); YBLK = 0; }
        return orig.apply(this, arguments);
      };
      P.__r7yPaint = true;
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
    TIMERS = opts.timers ? [] : null;
    chart.setOption(JSON.parse(JSON.stringify(option)));
    if (TIMERS) { const q = TIMERS; TIMERS = null; for (const fn of q) fn(); }
    for (let si = 0; si < samples.length; si++) {
      const t = samples[si];
      NOW = T_BASE + t;
      BRUSHES = [];
      CUR = null;
      if (si > 0) {
        BLOCKS = [];
        BLK = 0;
        YPAINTS = [];
        YBLK = 0;
        YOPS = new Map();
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
        let pts = probesOf(opts.probes, els, frames.length ? frames[frames.length - 1].els : null);
        // [R7-Y] an end symbol's own vertices and the middles of its edges,
        // exactly (where the path was built on the canvas)
        if (opts.probes === 'end-verts') {
          pts = [];
          for (const [el, key] of map) {
            if (!/^[ft][0-9]/.test(key)) continue;
            const p = PATHS.get(el) || [];
            for (let q = 0; q < p.length; q++) {
              const r = p[(q + 1) % p.length];
              pts.push([p[q][0], p[q][1]], [(p[q][0] + r[0]) / 2, (p[q][1] + r[1]) / 2]);
            }
          }
        }
        for (const [x, y] of (opts.more ? pts.concat(opts.more) : pts)) {
          const h = zr.handler.findHover(x, y);
          const tg = h && h.target;
          hits.push([hex(x), hex(y), tg ? (map.get(tg) || 'other') : null]);
        }
        if (Y) frames.push({ t, els, hits, blocks: BLOCKS, paints: YPAINTS });
        else if (W) frames.push({ t, els, hits, blocks: BLOCKS });
        else frames.push({ t, els, hits });
      }
      else if (Y) frames.push({ t, els, blocks: BLOCKS, paints: YPAINTS });
      else if (W) frames.push({ t, els, blocks: BLOCKS });
      else frames.push({ t, els });
    }
  }
  finally {
    chart.dispose();
    V2 = false;
    W = false;
    Z = false;
    AA = false;
    Y = false;
    PRISTINE = false;
    echarts.env.node = nodeWas;
  }
  // [R7-W] the options set before a sample, the dirty rects
  if (opts.w || opts.y) return Object.assign({ id, option }, opts.acts ? { acts: opts.acts } : {},
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
    W: CW, H: CH, T0: T_BASE, maps: MAPS, charts };
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
