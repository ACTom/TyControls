/*
Upstream's own answers for roadmap C13, batch 122: the GRAPHIC component --
its preprocessor (a bare element, an array of elements, `[{elements}]`, only
the first component kept), the model (GraphicModel.ts: the flattened element
list, mappingToExists by id, name and index, $action merge / replace /
remove, mergeLayoutParam with ignoreSize, hv, a group's default size), the
view (GraphicView.ts: createEl, applyUpdateTransition, updateCommonAttrs --
z, zlevel, z2, cursor -- silent / ignore / invisible / draggable, the
textContent and textConfig, the ec4 style compat, setEventData with name and
info, _relocate: a group's size against its parent, positionElement with
`bounding: 'all' | 'raw'` bottom-up), zrender's elements (the shapes' paths
-- rect and its radii, circle, ellipse, ring, sector with corners, arc,
polygon and polyline with smooth, line and bezierCurve with percent -- the
image, the text block, the group's bounding rect, the transform with origin,
skew and anchor), the display order against a series and the axes, element
handlers (on* bubbling up the groups, a true return cancelling the chart's
event) and the chart's events (componentType 'graphic', name, info), and the
transitions (customGraphicTransition.ts: enterFrom, transition, leaveTo, the
enter / update / leave configs and their element overrides).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32 and zrender's width table measuring every
string (the TZrSsrMeasurer of the Pascal tests). Every pointer step goes
through zrender's own Handler with a synthetic event {zrX, zrY, which 1}; a
paint follows every step, so every path and every text block is built.

  node tools/advchart-oracle/graphic.js

writes tests/fixtures/advchart-graphic.json (ORACLE_OUT overrides). Ends with
process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON. An element id an author did not write is upstream's
'\0name\0n' with every \0 written '~'. An element handler in an option is
{$fn: 'log:NAME'} (records the call) or {$fn: 'stop:NAME'} (records it and
returns true); the port reads them as '@log:NAME' / '@stop:NAME'.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, image
(the data URL every image case draws), clock {T0} (the animation cases' first
setOption instant), notes[], cases[], guards[].

A case: id, group, note, W, H, option (as run), steps[] (each: {merge
option} | {notMerge option} | {resize [w, h]} | {click id} | {move id} |
{leave} | {down id} | {up id} | {wait ms}), throws (the setOption threw: its
message), states[] (index-parallel to [after the first setOption, after step
1, ...]), anim (animation cases: samplesMs).

A state: {els[] (the view's elements depth first, the root group's children
in order: see elRec), order[] (the display list as owner tags, runs merged:
'g:<id>' a graphic element, 'g:<id>#label' its textContent, 's<n>' series n,
'a' an axis' or a grid's, 'o' anything else), model[] (getOption's flat
element list: {id, type, parentId}), log[] (element handler calls: {fn,
type, self, target}), events[] (chart events: {type, componentType,
componentIndex, name, info}), point (a pointer step's [x, y]), samples[]
(animation: per sample {t, clips, els: {id: snap}})}.

elRec: id, gtype (the option's type), type (zrender's), parent (id, null the
root), name, t {x, y, rotation, scaleX, scaleY, originX, originY, skewX,
skewY, anchorX, anchorY}, transform (6 hex or null), silent, ignore,
invisible, draggable, cursor, z, zlevel, z2 (null on a group), size (a
group's inner width / height), rect (getBoundingRect: x, y, width, height),
shape {key: hex | [hex] | [[hex]] | bool | null}, path[] (PathProxy data),
style (paths: fill, stroke, lineWidth, opacity, lineDash; image: image, x,
y, width, height, opacity; text: text, font, fill, stroke, lineWidth, align,
verticalAlign, x, y, opacity), pieces[] (a text's children: {k 't', text, x,
y, font, align, base, fill, stroke, lineWidth, opacity} | {k 'r', x, y,
width, height, r, fill, stroke, lineWidth}), label (textContent: transform,
inner {x, y, rotation, originX, originY}, def {fill, stroke, autoStroke,
align, verticalAlign}, style, pieces, rect, z, z2, zlevel, ignore),
eventData (has ECData's eventData), info (its info as JSON text, or null).

Guards (any failure: nothing is written, exit 1): T1 every element's global
transform recomputed from its props (getLocalTransform, the parent's
transform) equals upstream's; D1 the display list is sorted by (zlevel, z,
z2) with ties in tree order; named discriminating facts; and the whole
fixture generated twice, byte-identical.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

// ---------- the random numbers: the port's xorshift32 ----------
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-graphic.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexN = v => (v == null ? null : hex(+v));
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const enc = id => (id == null ? null : String(id).split('\u0000').join('~'));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const isGrad = v => v != null && typeof v === 'object' && Array.isArray(v.colorStops);
function colourRec(v) {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  if (isGrad(v)) {
    return { type: v.type, x: hexN(v.x), y: hexN(v.y), x2: hexN(v.x2), y2: hexN(v.y2), r: hexN(v.r), global: !!v.global,
      stops: v.colorStops.map(s => ({ offset: s.offset, color: s.color })) };
  }
  return JSON.stringify(v);
}

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m && decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  }
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

// ---------- a data-URL image (2 x 2: red, blue / green, white) ----------
const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(pixels) {
  const h = pixels.length;
  const w = pixels[0].length;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const raw = [];
  for (const row of pixels) {
    raw.push(0);
    for (const p of row) raw.push(p[0], p[1], p[2], p[3]);
  }
  const idat = zlib.deflateSync(Buffer.from(raw), { level: 9 });
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  return 'data:image/png;base64,' + Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]).toString('base64');
}
const IMG = png([[[255, 0, 0, 255], [0, 0, 255, 255]], [[0, 160, 0, 255], [255, 255, 255, 255]]]);

// ---------- the chart ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  rngState = SEED;
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function paint(chart) {
  chart._onframe();
  refresh(chart);
  quiet(() => chart.renderToSVGString());
  refresh(chart);
}
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, extra) {
  refresh(chart);
  zr(chart).handler[name](zev(extra));
  refresh(chart);
}
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && ('dataIndex' in el[k] || 'eventData' in el[k])) return el[k];
  }
  return null;
}
// GraphicView's inner store: {id, type, isNew, option, width, height}
function gInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'isNew' in el[k]) return el[k];
  }
  return null;
}
function graphicView(chart) {
  return (chart._componentsViews || []).find(v => v && v.type === 'graphic') || null;
}

// ---------------------------------------------------------------------------
// reading the elements
// ---------------------------------------------------------------------------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY', 'skewX', 'skewY', 'anchorX', 'anchorY'];
const pathData = el => {
  if (!el.path) el.getBoundingRect();
  must(el.path, 'no path proxy');
  return Array.from(el.path.data).slice(0, el.path.len());
};
const opac = st => (st.opacity == null ? 1 : st.opacity);
const rectRec = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
function valRec(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(valRec);
  return JSON.stringify(v);
}
function shapeRec(shape) {
  const o = {};
  for (const k of Object.keys(shape)) o[k] = valRec(shape[k]);
  return o;
}
function piecesOf(textEl) {
  return textEl.childrenRef().map(c => {
    const s = c.style;
    if (c.type === 'tspan') {
      return { k: 't', text: s.text == null ? null : String(s.text), x: hexN(s.x), y: hexN(s.y), font: s.font,
        align: s.textAlign == null ? null : s.textAlign, base: s.textBaseline == null ? null : s.textBaseline,
        fill: colourRec(s.fill), stroke: colourRec(s.stroke), lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)) };
    }
    if (c.type === 'rect') {
      return { k: 'r', x: hex(c.shape.x), y: hex(c.shape.y), width: hex(c.shape.width), height: hex(c.shape.height),
        r: valRec(c.shape.r), fill: colourRec(s.fill), stroke: colourRec(s.stroke), lineWidth: hexN(s.lineWidth) };
    }
    return { k: c.type };
  });
}
function textStyleRec(s) {
  return { text: s.text == null ? null : String(s.text), font: s.font == null ? null : s.font, fill: colourRec(s.fill),
    stroke: colourRec(s.stroke), lineWidth: hexN(s.lineWidth), align: s.align == null ? null : s.align,
    verticalAlign: s.verticalAlign == null ? null : s.verticalAlign, x: hexN(s.x), y: hexN(s.y), opacity: hex(opac(s)) };
}
function labelRec(host, chartIdOf) {
  const tc = host.getTextContent();
  if (!tc) return null;
  tc.getComputedTransform();
  const it = tc.innerTransformable;
  const ds = tc._defaultStyle || {};
  return { transform: tc.transform ? Array.from(tc.transform).map(hex) : null,
    inner: { x: hex(it.x), y: hex(it.y), rotation: hex(it.rotation), originX: hex(it.originX), originY: hex(it.originY) },
    def: { fill: colourRec(ds.fill), stroke: colourRec(ds.stroke), autoStroke: !!ds.autoStroke, align: ds.align == null ? null : ds.align,
      verticalAlign: ds.verticalAlign == null ? null : ds.verticalAlign },
    style: textStyleRec(tc.style), pieces: piecesOf(tc), rect: rectRec(tc.getBoundingRect()),
    z: hex(tc.z), z2: hex(tc.z2), zlevel: hex(tc.zlevel), ignore: !!tc.ignore, silent: !!tc.silent };
}
function idOfEl(el) {
  const inn = el && gInner(el);
  return inn ? enc(inn.id) : null;
}
function elRec(el, parentId) {
  const inn = gInner(el);
  must(inn, 'a graphic element with no inner store');
  const r = { id: enc(inn.id), gtype: inn.type, type: el.type, parent: parentId, name: el.name == null ? null : String(el.name) };
  r.t = {};
  for (const k of TKEYS) r.t[k] = hex(el[k]);
  r.transform = el.transform ? Array.from(el.transform).map(hex) : null;
  r.silent = !!el.silent;
  r.ignore = !!el.ignore;
  r.invisible = !!el.invisible;
  r.draggable = el.draggable == null ? null : el.draggable;
  r.cursor = el.isGroup ? null : (el.cursor == null ? null : el.cursor);
  r.z = el.isGroup ? null : hex(el.z);
  r.zlevel = el.isGroup ? null : hex(el.zlevel);
  r.z2 = el.isGroup ? null : hex(el.z2);
  r.size = el.isGroup ? { width: hexN(inn.width), height: hexN(inn.height) } : null;
  r.rect = rectRec(el.getBoundingRect());
  if (el.type === 'image') {
    const s = el.style;
    r.style = { image: typeof s.image === 'string' ? s.image : null, x: hexN(s.x), y: hexN(s.y), width: hexN(s.width),
      height: hexN(s.height), opacity: hex(opac(s)) };
  }
  else if (el.type === 'text') {
    r.style = textStyleRec(el.style);
    r.pieces = piecesOf(el);
  }
  else if (!el.isGroup) {
    const s = el.style;
    r.shape = shapeRec(el.shape);
    r.path = pathData(el).map(hex);
    r.style = { fill: colourRec(s.fill), stroke: colourRec(s.stroke), lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)),
      lineDash: s.lineDash == null ? null : valRec(s.lineDash) };
  }
  r.label = el.isGroup ? null : labelRec(el);
  const ecd = ecDataOf(el);
  r.eventData = !!(ecd && ecd.eventData);
  r.info = ecd && ecd.eventData && ecd.eventData.info !== undefined ? JSON.stringify(ecd.eventData.info) : null;
  return r;
}
function readEls(chart) {
  const view = graphicView(chart);
  if (!view) return [];
  const out = [];
  const walk = (g, parentId) => {
    g.childrenRef().forEach(el => {
      const rec = elRec(el, parentId);
      out.push(rec);
      if (el.isGroup) walk(el, rec.id);
    });
  };
  walk(view.group, null);
  return out;
}
function readModel(chart) {
  const opt = chart.getOption();
  const g = opt.graphic && opt.graphic[0];
  if (!g || !g.elements) return [];
  return g.elements.map(e => ({ id: enc(e.id), type: e.type == null ? null : e.type, parentId: enc(e.parentId) }));
}
// the display list as owner tags
function readOrder(chart) {
  const tags = new Map();
  const view = graphicView(chart);
  const tagTree = (el, tag) => {
    tags.set(el, tag);
    if (el.childrenRef) el.childrenRef().forEach(c => tagTree(c, tag));
    const tc = el.getTextContent && el.getTextContent();
    if (tc) tagTree(tc, tag);
  };
  if (view) {
    const walk = g => g.childrenRef().forEach(el => {
      const id = idOfEl(el);
      if (el.isGroup) walk(el);
      else {
        tags.set(el, 'g:' + id);
        if (el.childrenRef) el.childrenRef().forEach(c => tagTree(c, 'g:' + id));
        const tc = el.getTextContent && el.getTextContent();
        if (tc) tagTree(tc, 'g:' + id + '#label');
      }
    });
    walk(view.group);
  }
  chart.getModel().eachSeries(s => {
    const v = chart.getViewOfSeriesModel(s);
    if (v) tagTree(v.group, 's' + s.seriesIndex);
  });
  (chart._componentsViews || []).forEach(v => {
    if (!v || !v.__model || v.type === 'graphic') return;
    const mt = v.__model.mainType;
    tagTree(v.group, /Axis$|^grid$/.test(mt) ? 'a' : 'o');
  });
  const list = zr(chart).storage.getDisplayList(true);
  const out = [];
  list.forEach(d => {
    let t = tags.get(d);
    if (t === undefined) {
      let p = d;
      while (p && t === undefined) {
        p = p.__hostTarget || p.parent;
        if (p) t = tags.get(p);
      }
    }
    if (t === undefined) t = 'o';
    if (out[out.length - 1] !== t) out.push(t);
  });
  return out;
}

// ---------- transforms, recomputed (guard T1) ----------
function mul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3], m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
function localOf(t) {
  const m = [];
  const ox = t.originX || 0;
  const oy = t.originY || 0;
  const sx = t.scaleX;
  const sy = t.scaleY;
  const ax = t.anchorX;
  const ay = t.anchorY;
  const rotation = t.rotation || 0;
  const skewX = t.skewX ? Math.tan(t.skewX) : 0;
  const skewY = t.skewY ? Math.tan(-t.skewY) : 0;
  if (ox || oy || ax || ay) {
    const dx = ox + ax;
    const dy = oy + ay;
    m[4] = -dx * sx - skewX * dy * sy;
    m[5] = -dy * sy - skewY * dx * sx;
  }
  else m[4] = m[5] = 0;
  m[0] = sx; m[3] = sy; m[1] = skewY * sx; m[2] = skewX * sy;
  if (rotation) {
    const aa = m[0], ac = m[2], atx = m[4], ab = m[1], ad = m[3], aty = m[5];
    const st = Math.sin(rotation);
    const ct = Math.cos(rotation);
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * atx + st * aty;
    m[5] = ct * aty - st * atx;
  }
  m[4] += ox + t.x;
  m[5] += oy + t.y;
  return m;
}
const around = v => v > 5e-5 || v < -5e-5;
function needLocal(t) {
  return around(t.rotation) || around(t.x) || around(t.y) || around(t.scaleX - 1) || around(t.scaleY - 1) || around(t.skewX) || around(t.skewY);
}
function checkTransforms(chart, fails, where) {
  const view = graphicView(chart);
  if (!view) return;
  const walk = (g, parentM) => g.childrenRef().forEach(el => {
    const t = {};
    TKEYS.forEach(k => { t[k] = el[k]; });
    let m = null;
    if (needLocal(t) || parentM) {
      m = needLocal(t) ? localOf(t) : [1, 0, 0, 1, 0, 0];
      if (parentM) m = needLocal(t) ? mul(parentM, m) : parentM.slice();
    }
    const got = el.transform ? Array.from(el.transform) : null;
    const same = (m === null && (got === null || got.join() === '1,0,0,1,0,0'))
      || (m !== null && got !== null && m.every((v, i) => Object.is(v, got[i]) || (v === 0 && got[i] === 0)));
    if (!same) fails.push(where + ' ' + idOfEl(el) + ': the transform ' + JSON.stringify(got) + ', the recipe ' + JSON.stringify(m));
    if (el.isGroup) walk(el, got && got.join() !== '1,0,0,1,0,0' ? got : (m || null));
  });
  walk(view.group, null);
}
// D1: sorted by (zlevel, z, z2)
function checkSorted(chart, fails, where) {
  const list = zr(chart).storage.getDisplayList(true);
  for (let i = 1; i < list.length; i++) {
    const a = list[i - 1];
    const b = list[i];
    const k = (a.zlevel - b.zlevel) || (a.z - b.z) || (a.z2 - b.z2);
    if (k > 0) fails.push(where + ': the display list is not sorted at ' + i);
  }
}

// ---------- point finders ----------
function hoverTarget(chart, x, y) {
  refresh(chart);
  return zr(chart).handler.findHover(x, y).target;
}
function ownerId(el) {
  while (el) {
    const id = idOfEl(el);
    if (id != null) return id;
    el = el.__hostTarget || el.parent;
  }
  return null;
}
function spiral(x0, y0, ok, where) {
  for (let r = 0; r <= 24; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        if (ok(x0 + dx, y0 + dy)) return [x0 + dx, y0 + dy];
      }
    }
  }
  throw new OracleError(where + ': no point found near ' + x0 + ',' + y0);
}
// a point the pointer finds the element at (its global bounding rect's
// centre, then a spiral); [x, y] is taken as it is
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  const view = graphicView(chart);
  let target = null;
  view._elMap.each((el, id) => { if (enc(id) === t) target = el; });
  must(target, where + ': no element ' + t);
  const r = target.getBoundingRect().clone();
  target.getComputedTransform();
  if (target.transform) r.applyTransform(target.transform);
  return spiral(Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2),
    (x, y) => ownerId(hoverTarget(chart, x, y)) === t, where);
}

// ---------- handlers ----------
let LOG = [];
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    if (typeof v.$fn === 'string') {
      const [kind, name] = v.$fn.split(':');
      must(kind === 'log' || kind === 'stop', 'an unknown $fn ' + v.$fn);
      return function (e) {
        LOG.push({ fn: name, type: e.type, self: idOfEl(this), target: ownerId(e.target) });
        return kind === 'stop';
      };
    }
    const o = {};
    for (const k of Object.keys(v)) o[k] = materialize(v[k]);
    return o;
  }
  return v;
}
function eventRec(p) {
  return { type: p.type, componentType: p.componentType == null ? null : p.componentType,
    componentIndex: p.componentIndex == null ? null : p.componentIndex, name: p.name == null ? null : String(p.name),
    info: p.info === undefined ? null : JSON.stringify(p.info) };
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400,
  option: Object.assign({ animation: false }, option) }, more || {}));
const BAR = { xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [3, 5, 2], barWidth: 60 }] };

// ---- the shapes
add('shape', 'rects', "rects: plain, r 8, r [4, 12], r [2, 4, 6, 8], a stroke, no fill written (the prototype's '#000'), fill 'none' and a stroke, an opacity, a dash",
  { graphic: [
    { type: 'rect', id: 'plain', shape: { x: 20, y: 20, width: 80, height: 40 }, style: { fill: '#5070dd' } },
    { type: 'rect', id: 'r8', shape: { x: 120, y: 20, width: 80, height: 40, r: 8 }, style: { fill: '#b6d634' } },
    { type: 'rect', id: 'r2', shape: { x: 220, y: 20, width: 80, height: 40, r: [4, 12] }, style: { fill: '#ff994d' } },
    { type: 'rect', id: 'r4', shape: { x: 320, y: 20, width: 80, height: 40, r: [2, 4, 6, 8] }, style: { fill: '#0ca8df' } },
    { type: 'rect', id: 'stroke', shape: { x: 20, y: 90, width: 80, height: 40 }, style: { fill: '#ffd10a', stroke: '#333', lineWidth: 3 } },
    { type: 'rect', id: 'nofill', shape: { x: 120, y: 90, width: 80, height: 40 } },
    { type: 'rect', id: 'none', shape: { x: 220, y: 90, width: 80, height: 40 }, style: { fill: 'none', stroke: '#fb628b', lineWidth: 2 } },
    { type: 'rect', id: 'half', shape: { x: 320, y: 90, width: 80, height: 40 }, style: { fill: '#785db0', opacity: 0.5 } },
    { type: 'rect', id: 'dash', shape: { x: 420, y: 90, width: 80, height: 40 }, style: { fill: 'none', stroke: '#3fbe95', lineWidth: 2, lineDash: [5, 3] } }] });
add('shape', 'rounds', 'circle, ellipse, ring; sectors with r0, corners and both directions; arcs (stroke #000 by default) with and without a fill',
  { graphic: [
    { type: 'circle', id: 'circle', shape: { cx: 60, cy: 60, r: 40 }, style: { fill: '#5070dd' } },
    { type: 'ellipse', id: 'ellipse', shape: { cx: 170, cy: 60, rx: 50, ry: 30 }, style: { fill: '#b6d634', stroke: '#000', lineWidth: 1 } },
    { type: 'ring', id: 'ring', shape: { cx: 290, cy: 60, r: 40, r0: 25 }, style: { fill: '#ff994d' } },
    { type: 'sector', id: 'sector', shape: { cx: 60, cy: 180, r0: 15, r: 50, startAngle: 0, endAngle: 2 } , style: { fill: '#0ca8df' } },
    { type: 'sector', id: 'sectorC', shape: { cx: 180, cy: 180, r0: 10, r: 55, startAngle: 0.5, endAngle: 2.5, cornerRadius: 5 }, style: { fill: '#ffd10a' } },
    { type: 'sector', id: 'sectorCCW', shape: { cx: 300, cy: 180, r: 50, startAngle: 1, endAngle: -1, clockwise: false, cornerRadius: [2, 6] }, style: { fill: '#fb628b' } },
    { type: 'sector', id: 'sectorDef', shape: { cx: 420, cy: 180, r: 30 }, style: { fill: '#785db0' } },
    { type: 'arc', id: 'arc', shape: { cx: 60, cy: 300, r: 40, startAngle: 0, endAngle: Math.PI } },
    { type: 'arc', id: 'arcFill', shape: { cx: 180, cy: 300, r: 40, startAngle: 1, endAngle: 5, clockwise: false }, style: { fill: '#3fbe95', lineWidth: 3 } }] });
add('shape', 'polys', 'polygon, polyline (no fill, stroke #000 by default), a smooth polygon, a smooth polyline with a constraint, a polyline of one point',
  { graphic: [
    { type: 'polygon', id: 'polygon', shape: { points: [[20, 20], [120, 30], [90, 110], [30, 90]] }, style: { fill: '#5070dd' } },
    { type: 'polyline', id: 'polyline', shape: { points: [[150, 20], [200, 100], [250, 30], [300, 100]] } },
    { type: 'polygon', id: 'smoothGon', shape: { points: [[340, 20], [440, 30], [410, 110], [350, 90]], smooth: 0.4 }, style: { fill: '#b6d634' } },
    { type: 'polyline', id: 'smoothLine', shape: { points: [[20, 160], [80, 240], [140, 170], [200, 250], [260, 180]], smooth: 0.6,
      smoothConstraint: [[0, 150], [300, 260]] }, style: { stroke: '#ff994d', lineWidth: 2 } },
    { type: 'polyline', id: 'onePoint', shape: { points: [[300, 300]] } }] });
add('shape', 'lines', 'lines and bezier curves: a line, a line at percent 0.4, a quadratic, a cubic, a cubic at percent 0.6, a quadratic at percent 0.3, percent 0',
  { graphic: [
    { type: 'line', id: 'line', shape: { x1: 20, y1: 20, x2: 200, y2: 80 }, style: { stroke: '#5070dd', lineWidth: 2 } },
    { type: 'line', id: 'linePct', shape: { x1: 20, y1: 100, x2: 200, y2: 160, percent: 0.4 } },
    { type: 'bezierCurve', id: 'quad', shape: { x1: 240, y1: 20, cpx1: 300, cpy1: 120, x2: 380, y2: 20 } },
    { type: 'bezierCurve', id: 'cubic', shape: { x1: 240, y1: 160, cpx1: 280, cpy1: 60, cpx2: 340, cpy2: 260, x2: 400, y2: 160 },
      style: { stroke: '#ff994d', lineWidth: 3 } },
    { type: 'bezierCurve', id: 'cubicPct', shape: { x1: 20, y1: 200, cpx1: 60, cpy1: 100, cpx2: 120, cpy2: 300, x2: 180, y2: 200, percent: 0.6 } },
    { type: 'bezierCurve', id: 'quadPct', shape: { x1: 240, y1: 260, cpx1: 300, cpy1: 360, x2: 380, y2: 260, percent: 0.3 } },
    { type: 'line', id: 'line0', shape: { x1: 400, y1: 300, x2: 500, y2: 350, percent: 0 } }] });
add('shape', 'images', 'images from a data URL: a sized one, one placed by its style x / y, one half transparent, one without a size (upstream measures 0 until it loads)',
  { graphic: [
    { type: 'image', id: 'img', style: { image: IMG, width: 80, height: 60 }, x: 20, y: 20 },
    { type: 'image', id: 'imgXY', style: { image: IMG, x: 150, y: 30, width: 40, height: 40 } },
    { type: 'image', id: 'imgOp', style: { image: IMG, x: 250, y: 30, width: 60, height: 30, opacity: 0.4 } },
    { type: 'image', id: 'imgNoSize', style: { image: IMG, x: 350, y: 30 } }] });

// ---- text
add('text', 'texts', "texts: the font shorthand, the separate font keys, right / bottom aligned, two lines, a box with padding and a radius, a width that truncates, style x / y, a legacy textAlign",
  { graphic: [
    { type: 'text', id: 'short', x: 20, y: 20, style: { text: 'Hello world', font: 'bold 20px serif', fill: '#5070dd' } },
    { type: 'text', id: 'parts', x: 20, y: 60, style: { text: 'Parts', fontSize: 18, fontFamily: 'monospace', fontWeight: 'bold', fill: '#333' } },
    { type: 'text', id: 'aligned', x: 400, y: 120, style: { text: 'Right bottom', align: 'right', verticalAlign: 'bottom', fontSize: 14 } },
    { type: 'text', id: 'lines', x: 20, y: 120, style: { text: 'one\ntwo lines', fontSize: 12, lineHeight: 20, fill: '#ff994d' } },
    { type: 'text', id: 'box', x: 220, y: 180, style: { text: 'Boxed', fontSize: 16, backgroundColor: '#eee', padding: [4, 8], borderRadius: 4,
      borderColor: '#999', borderWidth: 1, fill: '#000' } },
    { type: 'text', id: 'trunc', x: 20, y: 220, style: { text: 'a long text that will be truncated', width: 90, overflow: 'truncate', fontSize: 12 } },
    { type: 'text', id: 'styleXY', style: { text: 'at style x/y', x: 300, y: 260, fill: '#0ca8df', stroke: '#fff', lineWidth: 2 } },
    { type: 'text', id: 'legacy', x: 500, y: 300, style: { text: 'legacy', textAlign: 'center', textVerticalAlign: 'middle', fontSize: 13 } }] });
add('text', 'rich', 'rich text: two named styles, a token with a background and padding, an unknown name, a block width and line height',
  { graphic: [
    { type: 'text', id: 'rich', x: 40, y: 40, style: { text: '{a|Big} plain {b|boxed}\n{a|second} {zz|unknown}', fontSize: 12, fill: '#333',
      rich: { a: { fontSize: 22, fill: '#5070dd', fontWeight: 'bold' }, b: { backgroundColor: '#ffd10a', padding: [2, 4], borderRadius: 3, fill: '#000' } } } },
    { type: 'text', id: 'richBox', x: 300, y: 200, style: { text: '{t|Title}\nbody text', width: 160, lineHeight: 24, backgroundColor: '#f4f4f4',
      padding: 6, align: 'center', verticalAlign: 'middle', rich: { t: { fontSize: 18, fill: '#fb628b', align: 'center' } } } }] });
add('text', 'text-hv', 'texts placed by left / top / right / bottom: a top or bottom drops the alignment (hv[1]), a left only keeps it',
  { graphic: [
    { type: 'text', id: 'lt', left: 20, top: 20, style: { text: 'left top', fontSize: 16, align: 'right', verticalAlign: 'bottom' } },
    { type: 'text', id: 'l', left: 20, y: 120, style: { text: 'left only', fontSize: 16, align: 'center', verticalAlign: 'middle' } },
    { type: 'text', id: 'rb', right: 10, bottom: 10, style: { text: 'right bottom', fontSize: 16 } },
    { type: 'text', id: 'cm', left: 'center', top: 'middle', style: { text: 'centre', fontSize: 30, fill: '#5070dd' } }] });
add('text', 'text-content', "textContent on a host: inside by default colour rules, 'top' with a distance, 'insideTopLeft', 'left' with an offset, a rotated label about its centre, explicit inside colours, an outside colour, an array position, a turned host, a local label, a label with its own fill",
  { graphic: [
    { type: 'rect', id: 'in', shape: { x: 20, y: 20, width: 100, height: 50 }, style: { fill: '#5070dd' },
      textContent: { style: { text: 'inside', fontSize: 14 } }, textConfig: { position: 'inside' } },
    { type: 'rect', id: 'top', shape: { x: 160, y: 40, width: 100, height: 40 }, style: { fill: '#ffd10a' },
      textContent: { style: { text: 'top', fontSize: 12 } }, textConfig: { position: 'top', distance: 10 } },
    { type: 'rect', id: 'itl', shape: { x: 300, y: 20, width: 120, height: 60 }, style: { fill: '#eeeeee' },
      textContent: { style: { text: 'insideTopLeft' } }, textConfig: { position: 'insideTopLeft' } },
    { type: 'rect', id: 'left', shape: { x: 120, y: 120, width: 60, height: 40 }, style: { fill: '#3fbe95' },
      textContent: { style: { text: 'left' } }, textConfig: { position: 'left', offset: [3, -4] } },
    { type: 'rect', id: 'rot', shape: { x: 220, y: 120, width: 80, height: 50 }, style: { fill: '#fb628b' },
      textContent: { style: { text: 'turned' } }, textConfig: { position: 'inside', rotation: 0.5, origin: 'center' } },
    { type: 'rect', id: 'cols', shape: { x: 340, y: 120, width: 100, height: 40 }, style: { fill: '#785db0' },
      textContent: { style: { text: 'colours' } }, textConfig: { position: 'inside', insideFill: '#ffd10a', insideStroke: '#000' } },
    { type: 'circle', id: 'out', shape: { cx: 60, cy: 260, r: 30 }, style: { fill: '#ff994d' },
      textContent: { style: { text: 'outside' } }, textConfig: { position: 'right', outsideFill: '#0ca8df' } },
    { type: 'rect', id: 'arr', shape: { x: 160, y: 230, width: 100, height: 50 }, style: { fill: '#b6d634' },
      textContent: { style: { text: 'array' } }, textConfig: { position: ['50%', 0] } },
    { type: 'rect', id: 'turnedHost', x: 340, y: 230, rotation: 0.3, shape: { x: 0, y: 0, width: 100, height: 40 }, style: { fill: '#0ca8df' },
      textContent: { style: { text: 'host turned' } }, textConfig: { position: 'bottom' } },
    { type: 'rect', id: 'local', x: 480, y: 230, rotation: -0.4, shape: { x: 0, y: 0, width: 80, height: 40 }, style: { fill: '#5070dd' },
      textContent: { style: { text: 'local' } }, textConfig: { position: 'inside', local: true } },
    { type: 'rect', id: 'ownFill', shape: { x: 20, y: 330, width: 100, height: 40 }, style: { fill: '#333' },
      textContent: { style: { text: 'own', fill: '#ff0000', fontSize: 16 } }, textConfig: { position: 'inside' } }] });
add('text', 'legacy-text', "an ec4 style on a rect -- style.text, textPosition 'right', textFill, textDistance -- becomes a silent textContent and a textConfig",
  { graphic: [
    { type: 'rect', id: 'ec4', shape: { x: 40, y: 40, width: 80, height: 40 }, style: { fill: '#5070dd', text: 'ec4 label', textPosition: 'right',
      textFill: '#ff994d', textDistance: 8, fontSize: 15 } },
    { type: 'rect', id: 'ec4in', shape: { x: 40, y: 140, width: 120, height: 40 }, style: { fill: '#b6d634', text: 'in' } }] });

// ---- placing
add('place', 'positions', "left / top in px and %, 'center' and 'middle', right / bottom in px and %, both left and right (left wins), 'auto' (no placement)",
  { graphic: [
    { type: 'rect', id: 'px', left: 30, top: 40, shape: { width: 60, height: 30 }, style: { fill: '#5070dd' } },
    { type: 'rect', id: 'pct', left: '25%', top: '30%', shape: { width: 60, height: 30 }, style: { fill: '#b6d634' } },
    { type: 'rect', id: 'centre', left: 'center', top: 'middle', shape: { width: 80, height: 40 }, style: { fill: '#ff994d' } },
    { type: 'rect', id: 'rb', right: 20, bottom: 30, shape: { width: 60, height: 30 }, style: { fill: '#0ca8df' } },
    { type: 'rect', id: 'rbPct', right: '10%', bottom: '20%', shape: { width: 60, height: 30 }, style: { fill: '#ffd10a' } },
    { type: 'rect', id: 'both', left: 100, right: 100, top: 300, shape: { width: 60, height: 30 }, style: { fill: '#fb628b' } },
    { type: 'rect', id: 'auto', left: 'auto', top: 'auto', x: 5, y: 5, shape: { width: 20, height: 20 }, style: { fill: '#785db0' } },
    { type: 'rect', id: 'shapeXY', left: 400, top: 200, shape: { x: 50, y: 50, width: 40, height: 40 }, style: { fill: '#3fbe95' } },
    { type: 'circle', id: 'circ', right: 0, top: 0, shape: { cx: 0, cy: 0, r: 25 }, style: { fill: '#333', stroke: '#000', lineWidth: 4 } }] });
add('place', 'groups', "groups: children placed in the group, the group placed by its children's union (bounding 'all'), the same with bounding 'raw' (its own 0 x 0 box), a turned group, a nested group, a sized group whose children sit against it",
  { graphic: [
    { type: 'group', id: 'all', left: 20, top: 20, children: [
      { type: 'rect', id: 'all.r', shape: { x: 10, y: 10, width: 60, height: 30 }, style: { fill: '#5070dd' } },
      { type: 'circle', id: 'all.c', shape: { cx: 100, cy: 50, r: 20 }, style: { fill: '#b6d634' } }] },
    { type: 'group', id: 'raw', left: 200, top: 20, bounding: 'raw', children: [
      { type: 'rect', id: 'raw.r', shape: { x: 10, y: 10, width: 60, height: 30 }, style: { fill: '#ff994d' } },
      { type: 'circle', id: 'raw.c', shape: { cx: 100, cy: 50, r: 20 }, style: { fill: '#0ca8df' } }] },
    { type: 'group', id: 'turn', right: 20, top: 20, rotation: 0.4, children: [
      { type: 'rect', id: 'turn.r', shape: { x: 0, y: 0, width: 80, height: 40 }, style: { fill: '#ffd10a' } }] },
    { type: 'group', id: 'turnRaw', right: 20, top: 150, rotation: 0.4, bounding: 'raw', children: [
      { type: 'rect', id: 'turnRaw.r', shape: { x: 0, y: 0, width: 80, height: 40 }, style: { fill: '#fb628b' } }] },
    { type: 'group', id: 'outer', left: 20, bottom: 20, children: [
      { type: 'group', id: 'inner', x: 30, y: 10, rotation: -0.3, children: [
        { type: 'rect', id: 'inner.r', shape: { x: 0, y: 0, width: 50, height: 25 }, style: { fill: '#785db0' } }] },
      { type: 'text', id: 'outer.t', x: 0, y: 0, style: { text: 'nested', fontSize: 14 } }] },
    { type: 'group', id: 'box', left: 250, top: 180, width: 200, height: 100, children: [
      { type: 'rect', id: 'box.bg', shape: { x: 0, y: 0, width: 200, height: 100 }, style: { fill: '#eeeeee' } },
      { type: 'rect', id: 'box.rb', right: 0, bottom: 0, shape: { width: 40, height: 20 }, style: { fill: '#3fbe95' } },
      { type: 'circle', id: 'box.c', left: 'center', top: '50%', shape: { r: 10 }, style: { fill: '#333' } },
      { type: 'text', id: 'box.t', right: '10%', top: 4, style: { text: 'in box', fontSize: 12 } }] },
    { type: 'group', id: 'empty', left: 10, top: 300, children: [] }] });
add('place', 'transforms', 'transforms: a turned rect, a scaled rect about an origin, a circle stretched, a turned text, a skew, a turned group with a turned child, an anchor, a placed turned rect (bounding all)',
  { graphic: [
    { type: 'rect', id: 'rot', x: 80, y: 60, rotation: Math.PI / 6, shape: { x: -30, y: -15, width: 60, height: 30 }, style: { fill: '#5070dd' } },
    { type: 'rect', id: 'scale', x: 200, y: 40, scaleX: 1.5, scaleY: 0.5, originX: 30, originY: 20, shape: { width: 60, height: 40 }, style: { fill: '#b6d634' } },
    { type: 'circle', id: 'stretch', x: 340, y: 60, scaleX: 2, shape: { r: 20 }, style: { fill: '#ff994d' } },
    { type: 'text', id: 'tt', x: 460, y: 60, rotation: -0.6, style: { text: 'turned text', fontSize: 16, fill: '#333' } },
    { type: 'rect', id: 'skew', x: 40, y: 160, skewX: 0.3, shape: { width: 60, height: 40 }, style: { fill: '#0ca8df' } },
    { type: 'group', id: 'gt', x: 200, y: 200, rotation: 0.5, scaleX: 1.2, scaleY: 1.2, children: [
      { type: 'rect', id: 'gt.r', x: 20, y: 0, rotation: 0.3, originX: 10, originY: 10, shape: { width: 50, height: 20 }, style: { fill: '#fb628b' } }] },
    { type: 'rect', id: 'anchor', x: 360, y: 200, anchorX: 20, anchorY: 10, rotation: 0.2, shape: { width: 40, height: 20 }, style: { fill: '#785db0' } },
    { type: 'rect', id: 'placedRot', right: 30, bottom: 30, rotation: 0.7, shape: { width: 80, height: 30 }, style: { fill: '#3fbe95' } },
    { type: 'rect', id: 'placedRaw', left: 30, bottom: 30, rotation: 0.7, bounding: 'raw', shape: { width: 80, height: 30 }, style: { fill: '#ffd10a' } }] });

// ---- order and flags
add('order', 'z-order', 'against a bar series (z 2) and the axes (z 0): the default z 0, z 1, z 2 (a tie: the component drawn first), z 2 z2 5, z 3, z -1, a zlevel 1, a text z 10, a label (its own z, not its host\'s)',
  Object.assign({}, BAR, { graphic: [
    { type: 'rect', id: 'z0', left: 60, top: 80, shape: { width: 500, height: 40 }, style: { fill: '#eeeeee' } },
    { type: 'rect', id: 'z1', z: 1, left: 80, top: 140, shape: { width: 300, height: 30 }, style: { fill: '#dddddd' } },
    { type: 'rect', id: 'z2', z: 2, left: 100, top: 200, shape: { width: 300, height: 30 }, style: { fill: '#cccccc' } },
    { type: 'rect', id: 'z2b', z: 2, z2: 5, left: 120, top: 240, shape: { width: 300, height: 30 }, style: { fill: '#bbbbbb' } },
    { type: 'rect', id: 'z3', z: 3, left: 140, top: 280, shape: { width: 300, height: 30 }, style: { fill: '#aaaaaa' },
      textContent: { style: { text: 'label of z3' } }, textConfig: { position: 'inside' } },
    { type: 'rect', id: 'zneg', z: -1, left: 20, top: 20, shape: { width: 560, height: 360 }, style: { fill: '#f8f8f8' } },
    { type: 'rect', id: 'zl1', zlevel: 1, left: 160, top: 320, shape: { width: 300, height: 20 }, style: { fill: '#999999' } },
    { type: 'text', id: 'ztext', z: 10, left: 'center', top: 10, style: { text: 'on top', fontSize: 20 } }] }));
add('order', 'flags', "silent, invisible, ignore (a group's children go with it), a cursor, draggable, names and info, a silent group's child",
  { graphic: [
    { type: 'rect', id: 'silent', silent: true, shape: { x: 20, y: 20, width: 60, height: 40 }, style: { fill: '#5070dd' } },
    { type: 'rect', id: 'invisible', invisible: true, shape: { x: 100, y: 20, width: 60, height: 40 }, style: { fill: '#b6d634' } },
    { type: 'rect', id: 'ignore', ignore: true, shape: { x: 180, y: 20, width: 60, height: 40 }, style: { fill: '#ff994d' } },
    { type: 'rect', id: 'cursor', cursor: 'move', draggable: true, name: 'mover', info: { a: 1, b: 'two' },
      shape: { x: 260, y: 20, width: 60, height: 40 }, style: { fill: '#0ca8df' } },
    { type: 'group', id: 'gIgnore', ignore: true, children: [
      { type: 'circle', id: 'gIgnore.c', shape: { cx: 60, cy: 150, r: 20 }, style: { fill: '#ffd10a' } }] },
    { type: 'group', id: 'gSilent', silent: true, children: [
      { type: 'circle', id: 'gSilent.c', shape: { cx: 160, cy: 150, r: 20 }, style: { fill: '#fb628b' } }] },
    { type: 'rect', id: 'named', name: 'theName', shape: { x: 340, y: 20, width: 60, height: 40 }, style: { fill: '#785db0' } }] });
add('order', 'compound', "a compoundPath (reserved, no class): the render throws",
  { graphic: [{ type: 'rect', id: 'before', shape: { x: 10, y: 10, width: 20, height: 20 } },
    { type: 'compoundPath', id: 'cp', shape: { paths: [] } }] });
add('order', 'forms', "the preprocessor: a bare element; then an array of two `{elements}` merges only the first",
  { graphic: { type: 'rect', id: 'bare', left: 10, top: 10, shape: { width: 30, height: 30 }, style: { fill: '#5070dd' } } }, { steps: [
    { merge: { graphic: [{ elements: [{ type: 'circle', id: 'first', left: 100, top: 10, shape: { r: 15 }, style: { fill: '#b6d634' } }] },
      { elements: [{ type: 'circle', id: 'second', left: 200, top: 10, shape: { r: 15 } }] }] } }] });

// ---- merging
add('merge', 'actions', "$action across merges: a style merged into an id (its shape kept), a replace changing the type, a remove, a new element; then a group removed with its children; a nameless option by name; then a notMerge",
  { graphic: [
    { type: 'rect', id: 'a', left: 20, top: 20, shape: { width: 60, height: 30 }, style: { fill: '#5070dd', stroke: '#000' } },
    { type: 'circle', id: 'b', left: 120, top: 20, shape: { r: 20 }, style: { fill: '#b6d634' } },
    { type: 'group', id: 'g', left: 220, top: 20, children: [
      { type: 'rect', id: 'c', shape: { width: 40, height: 40 }, style: { fill: '#ff994d' } },
      { type: 'rect', id: 'd', shape: { x: 50, width: 40, height: 40 }, style: { fill: '#0ca8df' } }] },
    { type: 'text', name: 'eName', left: 20, top: 120, style: { text: 'named text', fontSize: 14 } },
    { type: 'text', left: 20, top: 160, style: { text: 'anonymous', fontSize: 14 } }] }, { steps: [
    { merge: { graphic: [
      { id: 'a', style: { fill: '#fb628b' } },
      { id: 'b', $action: 'replace', type: 'rect', shape: { width: 30, height: 30 }, style: { fill: '#785db0' } },
      { id: 'c', $action: 'remove' },
      { id: 'h', type: 'ring', left: 400, top: 20, shape: { r: 30, r0: 15 }, style: { fill: '#3fbe95' } }] } },
    { merge: { graphic: [{ id: 'g', $action: 'remove' }, { name: 'eName', style: { text: 'renamed by name', fill: '#ff0000' } }] } },
    { merge: { graphic: { elements: [{ type: 'rect', left: 300, top: 300, shape: { width: 10, height: 10 } }] } } },
    { notMerge: { animation: false, graphic: [{ type: 'circle', id: 'fresh', left: 'center', top: 'middle', shape: { r: 40 }, style: { fill: '#333' } }] } }] });
add('merge', 'relayout', "merging placements: a right replaces the left (mergeLayoutParam, ignoreSize), a top in %, a turn kept on the merged element, a resize moving everything placed",
  { graphic: [
    { type: 'rect', id: 'm', left: 10, top: 10, shape: { width: 50, height: 30 }, style: { fill: '#5070dd' } },
    { type: 'text', id: 'mt', right: 10, top: 10, style: { text: 'text right', fontSize: 14 } },
    { type: 'group', id: 'mg', left: 'center', bottom: 10, children: [{ type: 'rect', id: 'mg.r', shape: { width: 100, height: 20 }, style: { fill: '#ff994d' } }] }] }, { steps: [
    { merge: { graphic: [{ id: 'm', right: 20 }] } },
    { merge: { graphic: [{ id: 'm', top: '50%', rotation: 0.2 }, { id: 'mt', left: 30 }] } },
    { resize: [500, 300] }] });
// [milestone C6-C13] the side a new placement replaces is nulled, not only
// outranked: with both written the left (top) wins and the stale right
// (bottom) is invisible -- until the new side is unset again
add('merge', 'relayout-unset', "a left over a right nulls the right: unset the left again and the element has no horizontal placement at all (not the old right); the same for top over bottom",
  { graphic: [
    { type: 'rect', id: 'u', right: 40, bottom: 30, shape: { width: 60, height: 40 }, style: { fill: '#5070dd' } },
    { type: 'text', id: 'ut', right: 10, top: 10, style: { text: 'unset', fontSize: 14 } }] }, { steps: [
    { merge: { graphic: [{ id: 'u', left: 50, top: 20 }, { id: 'ut', left: 30 }] } },
    { merge: { graphic: [{ id: 'u', left: null, top: null }, { id: 'ut', left: null }] } }] });

// ---- events
add('event', 'events', "element handlers and chart events: a click on a rect with onclick, a click on a child of a group with onclick (bubbling), a handler that returns true (no chart event), a silent rect over another (the one under it), an invisible rect (still hit), an ignored one (not), hovers with onmouseover / onmouseout",
  { graphic: [
    { type: 'rect', id: 'A', name: 'nameA', info: { k: 'A' }, onclick: { $fn: 'log:A' }, onmouseover: { $fn: 'log:Aover' }, onmouseout: { $fn: 'log:Aout' },
      shape: { x: 20, y: 20, width: 100, height: 60 }, style: { fill: '#5070dd' } },
    { type: 'group', id: 'G', onclick: { $fn: 'log:G' }, children: [
      { type: 'rect', id: 'B', name: 'nameB', shape: { x: 160, y: 20, width: 100, height: 60 }, style: { fill: '#b6d634' } }] },
    { type: 'rect', id: 'C', onclick: { $fn: 'stop:C' }, shape: { x: 300, y: 20, width: 100, height: 60 }, style: { fill: '#ff994d' } },
    { type: 'rect', id: 'S', silent: true, onclick: { $fn: 'log:S' }, shape: { x: 30, y: 30, width: 40, height: 30 }, style: { fill: '#0ca8df' } },
    { type: 'rect', id: 'I', invisible: true, onclick: { $fn: 'log:I' }, shape: { x: 20, y: 120, width: 100, height: 60 }, style: { fill: '#ffd10a' } },
    { type: 'rect', id: 'N', ignore: true, onclick: { $fn: 'log:N' }, shape: { x: 160, y: 120, width: 100, height: 60 }, style: { fill: '#fb628b' } },
    { type: 'text', id: 'T', x: 300, y: 140, onclick: { $fn: 'log:T' }, style: { text: 'click me', fontSize: 20 } }] }, { steps: [
    { click: 'A' }, { click: 'B' }, { click: 'C' }, { click: [45, 45] }, { click: 'I' }, { click: [210, 150] }, { click: 'T' },
    { move: 'A' }, { move: 'B' }, { leave: true }] });

// ---------------------------------------------------------------------------
// the animations
// ---------------------------------------------------------------------------
const SAMPLES = [0, 1, 50, 100, 250, 400, 500, 600, 800, 900, 1000, 1001, 1500];
add('anim', 'enter', "enter: the root's enterFrom (x) and the style's (opacity), an enterAnimation override (800 ms linear, delay 100), a default enter (1000 ms cubicOut), a group's child entering with it",
  { animation: true, graphic: [
    { type: 'rect', id: 'e1', x: 200, y: 40, shape: { width: 80, height: 40 }, enterFrom: { x: 0 }, style: { fill: '#5070dd', enterFrom: { opacity: 0 } },
      enterAnimation: { duration: 800, easing: 'linear', delay: 100 } },
    { type: 'circle', id: 'e2', x: 100, y: 150, shape: { r: 30, enterFrom: { r: 0 } }, style: { fill: '#b6d634' } },
    { type: 'group', id: 'eg', x: 300, y: 200, enterFrom: { scaleX: 0, scaleY: 0 }, children: [
      { type: 'rect', id: 'eg.r', shape: { width: 60, height: 30 }, style: { fill: '#ff994d' } }] },
    { type: 'rect', id: 'plain', x: 20, y: 250, shape: { width: 40, height: 20 } }] }, { W: 400, H: 300, samples: SAMPLES });
add('anim', 'update', "update: a shape moved with transition 'shape', a colour with style.transition 'fill', x with transition ['x'] (500 ms cubicInOut by default), a change with no transition (set at once), an updateAnimation override",
  { animation: true, graphic: [
    { type: 'rect', id: 'u1', shape: { x: 20, y: 20, width: 60, height: 30 }, style: { fill: '#5070dd' } },
    { type: 'rect', id: 'u2', shape: { x: 20, y: 80, width: 60, height: 30 }, style: { fill: '#5070dd' } },
    { type: 'circle', id: 'u3', x: 50, y: 170, shape: { r: 20 }, style: { fill: '#b6d634' } },
    { type: 'rect', id: 'u4', shape: { x: 20, y: 220, width: 60, height: 30 }, style: { fill: '#ff994d' } },
    { type: 'rect', id: 'u5', x: 200, y: 20, shape: { width: 60, height: 30 }, style: { fill: '#0ca8df' } }] }, { W: 400, H: 300, samples: SAMPLES, steps: [
    { wait: 2000 },
    { merge: { graphic: [
      { id: 'u1', shape: { x: 200 }, transition: 'shape' },
      { id: 'u2', style: { fill: '#ff0000', transition: 'fill' } },
      { id: 'u3', x: 250, transition: ['x'] },
      { id: 'u4', shape: { x: 250 } },
      { id: 'u5', y: 200, transition: 'all', updateAnimation: { duration: 300, easing: 'linear' } }] } }] });
add('anim', 'relocate', "a placed element moving to a new place with transition ['x', 'y']: _relocate's updateProps",
  { animation: true, graphic: [
    { type: 'rect', id: 'p', left: 20, top: 20, shape: { width: 60, height: 30 }, style: { fill: '#5070dd' } }] }, { W: 400, H: 300, samples: SAMPLES, steps: [
    { wait: 2000 },
    { merge: { graphic: [{ id: 'p', left: 200, top: 150, transition: ['x', 'y'] }] } }] });
add('anim', 'leave', "leave: a remove with leaveTo (the update timing and updateAnimation, not leaveAnimation), a remove with none (gone at once), a group removed with its child's leaveTo",
  { animation: true, graphic: [
    { type: 'rect', id: 'l1', x: 20, y: 20, shape: { width: 60, height: 30 }, style: { fill: '#5070dd', leaveTo: { opacity: 0 } }, leaveTo: { x: 300 },
      updateAnimation: { duration: 400 }, leaveAnimation: { duration: 2000 } },
    { type: 'rect', id: 'l2', x: 20, y: 100, shape: { width: 60, height: 30 }, style: { fill: '#b6d634' } },
    { type: 'group', id: 'lg', x: 200, y: 200, children: [
      { type: 'circle', id: 'lg.c', shape: { r: 20, leaveTo: { r: 0 } }, style: { fill: '#ff994d' } }] }] }, { W: 400, H: 300, samples: SAMPLES, steps: [
    { wait: 2000 },
    { merge: { graphic: [{ id: 'l1', $action: 'remove' }, { id: 'l2', $action: 'remove' }, { id: 'lg', $action: 'remove' }] } }] });

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
const SNAP_STYLE = ['opacity', 'fill', 'stroke', 'lineWidth'];
function snap(el) {
  const o = {};
  for (const k of TKEYS) o[k] = hex(el[k]);
  if (el.style) for (const k of SNAP_STYLE) if (el.style[k] != null) o['style.' + k] = valRec(el.style[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (el.shape[k] != null) o['shape.' + k] = valRec(el.shape[k]);
  return o;
}
function clipCount(z) {
  let n = 0;
  for (let cl = z.animation._head; cl; cl = cl.next) n++;
  return n;
}
function samplesOf(chart, start, times) {
  const z = zr(chart);
  return times.map(t => {
    NOW = start + t;
    z.animation.update();
    refresh(chart);
    const view = graphicView(chart);
    const els = {};
    const walk = g => g.childrenRef().forEach(el => {
      els[idOfEl(el)] = snap(el);
      if (el.isGroup) walk(el);
    });
    if (view) walk(view.group);
    return { t, clips: clipCount(z), els };
  });
}
function runCase(c) {
  const fails = [];
  const chart = mk(c.W, c.H);
  const events = [];
  ['click', 'mouseover', 'mouseout'].forEach(type => chart.on(type, p => { if (p.componentType === 'graphic') events.push(eventRec(p)); }));
  LOG = [];
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option), steps: clone(c.steps || []),
      throws: null, states: [] };
    if (c.samples) rec.samplesMs = c.samples;
    let start = NOW;
    try {
      quiet(() => chart.setOption(materialize(c.option)));
    } catch (e) {
      rec.throws = e.message;
    }
    if (!c.samples) paint(chart);
    const state = () => {
      const st = { els: readEls(chart), order: readOrder(chart), model: readModel(chart), log: LOG.splice(0), events: events.splice(0) };
      checkTransforms(chart, fails, c.id);
      checkSorted(chart, fails, c.id);
      return st;
    };
    if (c.samples) {
      const st = { model: readModel(chart), samples: samplesOf(chart, start, c.samples) };
      st.els = readEls(chart);
      rec.states.push(st);
    }
    else rec.states.push(state());
    let clock = start + (c.samples ? c.samples[c.samples.length - 1] : 0);
    (c.steps || []).forEach((step, i) => {
      const where = c.id + ' step ' + i;
      let point = null;
      if (step.wait !== undefined) {
        clock += step.wait;
        NOW = clock;
        zr(chart).animation.update();
        return;
      }
      if (step.merge) quiet(() => chart.setOption(materialize(step.merge)));
      else if (step.notMerge) quiet(() => chart.setOption(materialize(step.notMerge), true));
      else if (step.resize) quiet(() => chart.resize({ width: step.resize[0], height: step.resize[1] }));
      else if (step.click !== undefined) {
        point = resolvePoint(chart, step.click, where);
        fire(chart, 'mousemove', { zrX: point[0], zrY: point[1] });
        fire(chart, 'mousedown', { zrX: point[0], zrY: point[1] });
        fire(chart, 'mouseup', { zrX: point[0], zrY: point[1] });
        fire(chart, 'click', { zrX: point[0], zrY: point[1] });
      }
      else if (step.move !== undefined) {
        point = resolvePoint(chart, step.move, where);
        fire(chart, 'mousemove', { zrX: point[0], zrY: point[1] });
      }
      else if (step.leave) fire(chart, 'mousemove', { zrX: -10, zrY: -10 });
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      if (c.samples) {
        start = clock;
        const st = { model: readModel(chart), samples: samplesOf(chart, start, c.samples) };
        st.els = readEls(chart);
        rec.states.push(st);
        clock = start + c.samples[c.samples.length - 1];
      }
      else {
        paint(chart);
        const st = state();
        st.point = point;
        rec.states.push(st);
      }
    });
    rec.fails = fails;
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  const el = (id, eid, si) => cs(id).states[si || 0].els.find(e => e.id === eid);
  const num = h => {
    bits.setUint32(0, parseInt(h.slice(0, 8), 16));
    bits.setUint32(4, parseInt(h.slice(8), 16));
    return bits.getFloat64(0);
  };
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  guard("an unwritten fill is the prototype's '#000'", el('rects', 'nofill').style.fill === '#000');
  guard("an arc strokes '#000' and fills nothing", el('rounds', 'arc').style.stroke === '#000' && el('rounds', 'arc').style.fill === null);
  guard('a rect with r draws arcs', el('rects', 'r8').path.length > el('rects', 'plain').path.length);
  guard('a polyline of one point builds nothing', el('polys', 'onePoint').path.length === 0);
  guard('a line at percent 0 builds nothing', el('lines', 'line0').path.length === 0);
  guard('an image without a size measures 0', num(el('images', 'imgNoSize').rect.width) === 0);
  guard('a rich text draws a token box', el('rich', 'rich').pieces.some(p => p.k === 'r'));
  guard('a top drops the alignment', el('text-hv', 'lt').style.align === null && el('text-hv', 'l').style.align === 'center');
  guard('a label inside a blue rect is light and stroked in the fill', el('text-content', 'in').label.def.fill !== '#000'
    && el('text-content', 'in').label.def.stroke === '#5070dd');
  guard('a label above its host is dark', el('text-content', 'top').label.def.fill === '#333');
  guard('the ec4 style became a silent label', el('legacy-text', 'ec4').label && el('legacy-text', 'ec4').label.silent);
  guard("left 30 is x 30", num(el('positions', 'px').t.x) === 30);
  guard("'auto' leaves x alone", num(el('positions', 'auto').t.x) === 5);
  guard("bounding 'raw' places a group's origin", num(el('groups', 'raw').t.x) === 200 && num(el('groups', 'all').t.x) === 20 - 10);
  guard('a sized group places its children against itself', num(el('groups', 'box.rb').t.x) === 160);
  guard('a group sizes 0 x 0 by default', num(el('groups', 'all').size.width) === 0);
  const zo = cs('z-order').states[0].order;
  const at = t => zo.indexOf(t);
  guard('z 0 goes under the axes', at('g:z0') < at('a'));
  guard('a z 2 tie goes under the series', at('g:z2') < at('s0') && at('g:z2b') > at('s0'));
  guard('z 3 goes over the series, its label under them (z 0)', at('g:z3') > at('s0') && at('g:z3#label') < at('s0'));
  guard('zlevel 1 is last', zo[zo.length - 1] === 'g:zl1');
  guard('an ignored element is not in the view list as drawn', el('flags', 'ignore').ignore === true);
  guard('info rides the event data', el('flags', 'cursor').info === '{"a":1,"b":"two"}');
  guard('a silent element has no event data', !el('flags', 'silent').eventData);
  guard('a compoundPath throws', /compoundPath/.test(cs('compound').throws || ''));
  guard('only the first {elements} survives', cs('forms').states[1].els.some(e => e.id === 'first') && !cs('forms').states[1].els.some(e => e.id === 'second'));
  const act = cs('actions').states;
  guard('a merge keeps the shape', num(act[1].els.find(e => e.id === 'a').shape.width) === 60 && act[1].els.find(e => e.id === 'a').style.fill === '#fb628b');
  guard('a replace changes the type', act[1].els.find(e => e.id === 'b').type === 'rect');
  guard('a remove removes', !act[1].els.some(e => e.id === 'c') && act[1].els.some(e => e.id === 'h'));
  guard('a removed group takes its children', !act[2].els.some(e => e.id === 'g' || e.id === 'd'));
  guard('a name maps an option', act[2].els.some(e => e.name === 'eName' && e.pieces && e.pieces.some(p => p.text === 'renamed by name')));
  guard('a notMerge starts over', act[4].els.length === 1 && act[4].els[0].id === 'fresh');
  const rl = cs('relayout').states;
  guard('a right replaces the left', num(rl[1].els.find(e => e.id === 'm').t.x) === 600 - 20 - 50);
  guard('a resize relocates', num(rl[3].els.find(e => e.id === 'm').t.x) === num(rl[2].els.find(e => e.id === 'm').t.x) - 100);
  const ev = cs('events').states;
  guard('a click logs its handler and the chart event', ev[1].log.some(l => l.fn === 'A') && ev[1].events.some(e => e.type === 'click' && e.name === 'nameA' && e.info === '{"k":"A"}'));
  guard("a child's click bubbles to its group", ev[2].log.some(l => l.fn === 'G' && l.self === 'G' && l.target === 'B'));
  guard('a true return stops the chart event', ev[3].log.some(l => l.fn === 'C') && !ev[3].events.some(e => e.type === 'click'));
  guard('a silent element passes the click on', ev[4].log.some(l => l.fn === 'A') && !ev[4].log.some(l => l.fn === 'S'));
  guard('an invisible element is still hit', ev[5].log.some(l => l.fn === 'I'));
  guard('an ignored element is not', !ev[6].log.some(l => l.fn === 'N'));
  guard('mouseover and mouseout handlers run', ev[8].log.some(l => l.fn === 'Aover') && ev[9].log.some(l => l.fn === 'Aout'));
  const en = cs('enter').states[0].samples;
  guard('enterFrom x runs from 0', num(en[0].els.e1.x) === 0 && num(en[en.length - 1].els.e1.x) === 200);
  guard('the enter delay holds the first 100 ms', num(en[2].els.e1.x) === 0);
  guard('a shape enterFrom grows r', num(en[3].els.e2['shape.r']) > 0 && num(en[3].els.e2['shape.r']) < 30);
  const up = cs('update').states[1].samples;
  guard('an update with no transition jumps', num(up[0].els.u4['shape.x']) === 250);
  guard('a shape transition moves', num(up[3].els.u1['shape.x']) > 20 && num(up[3].els.u1['shape.x']) < 200);
  guard('a colour transition runs in rgba', /^rgba\(/.test(up[3].els.u2['style.fill']));
  guard('an updateAnimation shortens the update', num(up[6].els.u5.y) === 200 && num(up[2].els.u5.y) > 20);
  const lv = cs('leave').states[1].samples;
  guard('a leaving element stays until it is done', lv[3].els.l1 && !lv[lv.length - 1].els.l1);
  guard('a remove without leaveTo is gone at once', !lv[0].els.l2);
  guard('leave runs on the update timing (400 ms, not 2000)', lv[6] && !lv[6].els.l1);
  guard('the animations settle', ['enter', 'update', 'relocate', 'leave'].every(id => cs(id).states.every(s => s.samples[s.samples.length - 1].clips === 0)));
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    image: IMG,
    clock: { T0 },
    notes: [
      'every chart: chart._ssr false, env.node off, 600 x 400 (the animations 400 x 300).',
      'static cases: animation false; a paint (renderToSVGString) after setOption and after every step builds every path and text block.',
      'pointer steps go through zrender\'s Handler; a click is mousemove, mousedown, mouseup, click at one point.',
      'animation cases: each state samples the clock at samplesMs after its setOption; a {wait} step only lets the clock run.',
      'ids an author did not write are upstream\'s with \\0 written ~.',
    ],
    cases: CASES.map(runCase),
  };
  out.guards = guards(out);
  return out;
}
let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (process.env.ORACLE_FORCE) fs.writeFileSync(OUT, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
out1.cases.forEach(q => q.fails.slice(0, 8).forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
