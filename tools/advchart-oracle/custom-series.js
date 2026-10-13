/*
Upstream's own answers for roadmap C14, batch 123: the CUSTOM series, first
part -- renderItem called once per data item shown (makeRenderItem: params
with context, seriesId / Name / Index, dataIndex and dataIndexInside,
dataInsideLength, actionType, coordSys, encode, itemPayload; the api:
value, ordinalRawValue, coord, size, style, styleEmphasis, visual,
barLayout, currentSeriesIndices, font, getWidth / getHeight /
getDevicePixelRatio), what it returns turned into elements
(createOrUpdateItem, doCreateOrUpdateEl, the merge principle, the attached
text and the ec4 style, mergeChildren by index and by name, updateZ, the
state options), the diff by data id across updates (a legend toggle, a
dataZoom with filterMode 'weakFilter', a merge of new data), the series
clip, the display order, the hit test, the item tooltip (encode.tooltip),
the legend and the emphasis.

Every renderItem is JavaScript here and a named handler in the port: an
option says renderItem: '@name' and this script hands the series RENDER[name]
wrapped in a recorder that writes down the params, every api call with its
answer, and the element tree returned. The Pascal tests register a
transcription of each under the same name.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off and the chart prototype's getDom answering an
empty object so TooltipView runs (tooltip-finish.js' recipe), with the clock
of animation.js (the global Date replaced BEFORE the dist loads; setTimeout a
queue the steps settle), Math.random the port's xorshift32 and zrender's
width table measuring every string. Every pointer step goes through
zrender's own Handler; a paint follows every step.

  node tools/advchart-oracle/custom-series.js

writes tests/fixtures/advchart-custom-series.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON. Colours of the states are [r, g, b, a] from
echarts.color.parse.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)},
notes[], cases[], guards[].

A case: id, group, note, W, H, option (as run; renderItem '@name'), steps[]
(each: {move key | [x, y]} | {leave} | {action payload} | {merge option}),
states[] (index-parallel to [after setOption, after step 1, ...]).

A state: calls[] (every renderItem call since the last state, in order: {s
seriesIndex, name (the handler), params, api[] ({fn, args, ret}), ret (the
element tree returned)}), els[] (every element of every custom series' view
group, depth first: elRec), order[] (the custom displayables in display
order: key, key + '#label' for a textContent), clips[] ({s, rect [x, y, w,
h] hex | null}), point ([x, y] of a pointer step), hover ({key, seriesIndex,
dataIndex} | null), tooltip ({shown, rows [{marker, name, value}] | null}),
st[] (every custom path's state: {key, states[], fill, stroke, lineWidth
hex, opacity hex, z2}), legend ([{name, selected, icon, fill}] | null).

A value in a recorded params / api answer / element tree: a number as hex, a
string, a boolean, null (also undefined), an array or an object of those.

elRec: key ('s<series>:<raw dataIndex>' for an item's root, '/k' per child),
type (zrender's), name, ignore, invisible, silent, z, z2, zlevel (hex; null
on a group), t {x, y, rotation, scaleX, scaleY, originX, originY} (hex),
transform (6 hex | null), shape, path (PathProxy data, hex), style (paths:
fill, stroke, lineWidth, opacity, lineDash; text: text, font, fill, stroke,
lineWidth, align, verticalAlign, x, y, opacity), pieces (a text's: {k 't',
text, x, y, font, align, base, fill, stroke, lineWidth, opacity} | {k 'r'
...}), label (textContent: transform, inner, def, style, pieces, z, z2,
silent, ignore), ec {seriesIndex, dataIndex}, info (JSON text | null).

Guards (any failure: nothing is written, exit 1): every case's recipe
checks (R1: an element's global transform from its props; R2: the display
list sorted by (zlevel, z, z2)); named discriminating facts; the whole
fixture generated twice, byte-identical; no \u0000; it parses back.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

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
  NOW = Math.max(NOW, at);
}

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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-custom-series.json');

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
function colourOf(c) {
  if (c == null || c === 'none') return null;
  if (typeof c !== 'string') return null;
  const p = echarts.color.parse(c);
  return p ? [p[0], p[1], p[2], p[3]] : null;
}
// a recorded value: numbers hexed, undefined as null
function rv(v) {
  if (v === undefined || v === null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'string' || typeof v === 'boolean') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(rv);
  if (typeof v === 'function') return '<fn>';
  if (typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (v[k] === undefined) continue;
      o[k] = rv(v[k]);
    }
    return o;
  }
  throw new OracleError('an unrecordable value ' + typeof v);
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
  TIMERS = [];
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
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });
let ecKey = null;
function ecDataOf(el) {
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
// customInnerStore: {info, customGraphicType, ...}
function customInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'customGraphicType' in el[k]) return el[k];
  }
  return null;
}

// ---------------------------------------------------------------------------
// the renderItems (each mirrored in tests/test.advchart.customseries.pas)
// ---------------------------------------------------------------------------
const RENDER = {
  // a gantt bar: the category's row, from start to end, 0.6 of the band
  gantt(params, api) {
    const cat = api.value(0);
    const start = api.coord([api.value(1), cat]);
    const end = api.coord([api.value(2), cat]);
    const h = api.size([0, 1])[1] * 0.6;
    return { type: 'rect', shape: { x: start[0], y: start[1] - h / 2, width: end[0] - start[0], height: h },
      style: api.style() };
  },
  // an error bar: a group of three lines in the series colour
  errorbar(params, api) {
    const x = api.value(0);
    const hi = api.coord([x, api.value(2)]);
    const lo = api.coord([x, api.value(1)]);
    const half = api.size([1, 0])[0] * 0.1;
    const col = api.visual('color');
    return { type: 'group', children: [
      { type: 'line', shape: { x1: hi[0] - half, y1: hi[1], x2: hi[0] + half, y2: hi[1] }, style: { stroke: col, lineWidth: 2, fill: 'none' } },
      { type: 'line', shape: { x1: hi[0], y1: hi[1], x2: lo[0], y2: lo[1] }, style: { stroke: col, lineWidth: 2, fill: 'none' } },
      { type: 'line', shape: { x1: lo[0] - half, y1: lo[1], x2: lo[0] + half, y2: lo[1] }, style: { stroke: col, lineWidth: 2, fill: 'none' } }] };
  },
  // a hexagon of the item's size about its point, on two value axes
  hexagon(params, api) {
    const c = api.coord([api.value(0), api.value(1)]);
    const r = api.size([api.value(2), api.value(2)], [api.value(0), api.value(1)]);
    const pts = [];
    for (let k = 0; k < 6; k++) {
      const a = Math.PI / 3 * k;
      pts.push([c[0] + r[0] / 2 * Math.cos(a), c[1] + r[1] / 2 * Math.sin(a)]);
    }
    api.barLayout({ count: 1 });
    const info = { w: api.getWidth(), h: api.getHeight(), dpr: api.getDevicePixelRatio() };
    return { type: 'polygon', shape: { points: pts }, info,
      style: { fill: api.visual('color'), opacity: 0.7, stroke: api.visual('borderColor') || '#333', lineWidth: 1 } };
  },
  // a dot with its value above it, a free text under it, and an ec4 label
  texts(params, api) {
    params.context.n = (params.context.n || 0) + 1;
    const p = api.coord([api.value(0), api.value(1)]);
    return { type: 'group', children: [
      { type: 'circle', shape: { cx: p[0], cy: p[1], r: 6 }, style: { fill: api.visual('color') },
        textContent: { style: { text: String(api.value(1)), fill: '#333' } }, textConfig: { position: 'top', distance: 4 } },
      { type: 'text', x: p[0], y: p[1] + 12, style: { text: api.ordinalRawValue(2) + '@' + api.ordinalRawValue(0) + '#' + params.context.n,
        font: api.font({ fontSize: 14, fontWeight: 'bold' }), fill: '#444', align: 'center', verticalAlign: 'top' } },
      { type: 'rect', shape: { x: p[0] - 20, y: p[1] - 50, width: 40, height: 20 },
        style: api.style({ text: 'L' + params.dataIndex, textPosition: 'insideTop' }) }] };
  },
  // a group at the item's point: a box and a ring; the third column picks
  // the variant (1: the ring leaves, 2: by name, reversed and turned); the
  // box strokes only in variant 0, so an update shows the style replaced
  groups(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    const mode = api.value(2);
    const kids = [
      { type: 'rect', name: 'box', shape: { x: -12, y: -8, width: 24, height: 16 },
        style: mode === 0 ? { fill: api.visual('color'), stroke: '#333' } : { fill: api.visual('color') } },
      { type: 'ring', name: 'ring', shape: { cx: 0, cy: 0, r: 10, r0: 5 }, style: { fill: '#91cc75' } }];
    if (mode === 1) kids.pop();
    if (mode === 2) kids.reverse();
    const g = { type: 'group', x: p[0], y: p[1], rotation: mode === 2 ? Math.PI / 6 : 0, info: { row: params.dataIndex, mode },
      children: kids };
    if (mode === 2) g.$mergeChildren = 'byName';
    return g;
  },
  // two bar series sharing a band through api.barLayout
  bar0(params, api) {
    return barOf(params, api, 0);
  },
  bar1(params, api) {
    return barOf(params, api, 1);
  },
  // a square of three data units about the item's point
  square(params, api) {
    const c = api.coord([api.value(0), api.value(1)]);
    const s = api.size([3, 3]);
    return { type: 'rect', shape: { x: c[0] - s[0] / 2, y: c[1] - s[1] / 2, width: s[0], height: s[1] }, style: { fill: api.visual('color') } };
  },
  // a dot per category value, the indices of the series drawn in its info
  dot(params, api) {
    const c = api.coord([api.value(0), api.value(1)]);
    return { type: 'circle', shape: { cx: c[0], cy: c[1], r: 8 }, info: { cur: api.currentSeriesIndices() },
      style: { fill: api.visual('color') } };
  },
  // gantt again, its rows on a zoomed axis
  span(params, api) {
    const cat = api.value(0);
    const start = api.coord([api.value(1), cat]);
    const end = api.coord([api.value(2), cat]);
    const h = api.size([0, 1])[1] * 0.5;
    return { type: 'rect', shape: { x: start[0], y: start[1] - h / 2, width: end[0] - start[0], height: h },
      style: { fill: api.visual('color') }, info: { inside: params.dataIndexInside, of: params.dataInsideLength, act: params.actionType } };
  },
  // a rect with a declared emphasis, a circle lifted by default, a text
  hover(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    const base = api.coord([api.value(0), 0]);
    api.styleEmphasis();
    return { type: 'group', children: [
      { type: 'rect', shape: { x: p[0] - 15, y: p[1], width: 30, height: base[1] - p[1] }, style: { fill: api.visual('color') },
        emphasis: { style: { fill: '#ee6666', stroke: '#000', lineWidth: 2 } } },
      { type: 'circle', shape: { cx: p[0], cy: p[1] - 12, r: 8 }, z2: 3, style: { fill: '#73c0de', stroke: '#5470c6', lineWidth: 1 } }] };
  },
};
function barOf(params, api, k) {
  const layout = api.barLayout({ count: 2, barGap: '20%', barCategoryGap: 10 });
  api.barLayout({ count: 3, barWidth: 12, barMaxWidth: 10 });
  const base = api.coord([api.value(0), 0]);
  const top = api.coord([api.value(0), api.value(1)]);
  const item = layout[k];
  return { type: 'rect', shape: { x: base[0] + item.offset, y: top[1], width: item.width, height: base[1] - top[1] },
    style: { fill: api.visual('color') } };
}

// the recorder each '@name' becomes
let CALLS = [];
function recorder(name) {
  const fn = RENDER[name];
  must(fn, 'no renderItem ' + name);
  return function (params, api) {
    const call = { s: params.seriesIndex, name, params: null, api: [], ret: null };
    call.params = {
      dataIndex: params.dataIndex, dataIndexInside: params.dataIndexInside, dataInsideLength: params.dataInsideLength,
      actionType: params.actionType == null ? null : params.actionType, seriesId: enc(params.seriesId),
      seriesName: params.seriesName == null ? null : enc(params.seriesName), seriesIndex: params.seriesIndex,
      coordSys: rv(params.coordSys), encode: clone(params.encode), itemPayload: clone(params.itemPayload),
      context: rv(params.context) };
    const wrapped = {};
    for (const k of Object.keys(api)) {
      if (typeof api[k] !== 'function') continue;
      wrapped[k] = function () {
        const args = Array.from(arguments);
        const recArgs = rv(args);
        const ret = api[k].apply(api, args);
        call.api.push({ fn: k, args: recArgs, ret: rv(ret) });
        return ret;
      };
    }
    const ret = quiet(() => fn(params, wrapped));
    call.ret = rv(ret);
    CALLS.push(call);
    return ret;
  };
}
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (k === 'renderItem' && typeof v[k] === 'string' && v[k][0] === '@') o[k] = recorder(v[k].slice(1));
      else o[k] = materialize(v[k]);
    }
    return o;
  }
  return v;
}

// ---------------------------------------------------------------------------
// reading the elements
// ---------------------------------------------------------------------------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY'];
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
        fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
        lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)) };
    }
    if (c.type === 'rect') {
      return { k: 'r', x: hex(c.shape.x), y: hex(c.shape.y), width: hex(c.shape.width), height: hex(c.shape.height),
        r: valRec(c.shape.r), fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
        lineWidth: hexN(s.lineWidth) };
    }
    return { k: c.type };
  });
}
function textStyleRec(s) {
  return { text: s.text == null ? null : String(s.text), font: s.font == null ? null : s.font,
    fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: hexN(s.lineWidth), align: s.align == null ? null : s.align,
    verticalAlign: s.verticalAlign == null ? null : s.verticalAlign, x: hexN(s.x), y: hexN(s.y), opacity: hex(opac(s)) };
}
function labelRec(host) {
  const tc = host.getTextContent();
  if (!tc) return null;
  tc.getComputedTransform();
  const it = tc.innerTransformable;
  const ds = tc._defaultStyle || {};
  return { transform: tc.transform ? Array.from(tc.transform).map(hex) : null,
    inner: { x: hex(it.x), y: hex(it.y), rotation: hex(it.rotation), originX: hex(it.originX), originY: hex(it.originY) },
    def: { fill: ds.fill == null ? null : String(ds.fill), stroke: ds.stroke == null ? null : String(ds.stroke),
      autoStroke: !!ds.autoStroke, align: ds.align == null ? null : ds.align,
      verticalAlign: ds.verticalAlign == null ? null : ds.verticalAlign },
    style: textStyleRec(tc.style), pieces: piecesOf(tc),
    z: hex(tc.z), z2: hex(tc.z2), zlevel: hex(tc.zlevel), ignore: !!tc.ignore, silent: !!tc.silent };
}
function elRec(el, key) {
  const r = { key, type: el.type, name: el.name == null || el.name === '' ? null : String(el.name) };
  r.ignore = !!el.ignore;
  r.invisible = !!el.invisible;
  r.silent = !!el.silent;
  r.z = el.isGroup ? null : hex(el.z);
  r.zlevel = el.isGroup ? null : hex(el.zlevel);
  r.z2 = el.isGroup ? null : hex(el.z2);
  r.t = {};
  for (const k of TKEYS) r.t[k] = hex(el[k]);
  r.transform = el.transform ? Array.from(el.transform).map(hex) : null;
  if (el.type === 'text') {
    r.style = textStyleRec(el.style);
    r.pieces = piecesOf(el);
  }
  else if (!el.isGroup) {
    const s = el.style;
    r.shape = shapeRec(el.shape);
    r.path = pathData(el).map(hex);
    r.style = { fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
      lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)), lineDash: s.lineDash == null ? null : valRec(s.lineDash) };
  }
  r.label = el.isGroup ? null : labelRec(el);
  const ecd = ecDataOf(el);
  r.ec = ecd ? { seriesIndex: ecd.seriesIndex == null ? null : ecd.seriesIndex, dataIndex: ecd.dataIndex == null ? null : ecd.dataIndex } : null;
  const inn = customInner(el);
  r.info = inn && inn.info !== undefined ? JSON.stringify(inn.info) : null;
  return r;
}
function customSeries(chart) {
  const out = [];
  chart.getModel().eachRawSeries(s => {
    if (s.subType === 'custom') out.push(s);
  });
  return out;
}
// every element of every custom view group, depth first, keyed
function keyedTree(chart) {
  const list = [];
  customSeries(chart).forEach(s => {
    const view = chart.getViewOfSeriesModel(s);
    if (!view) return;
    const data = s.getData();
    const walk = (el, key) => {
      list.push({ el, key });
      if (el.isGroup) el.childrenRef().forEach((c, k) => walk(c, key + '/' + k));
    };
    view.group.childrenRef().forEach(el => {
      const ecd = ecDataOf(el);
      must(ecd && ecd.dataIndex != null, 'a custom root without a data index');
      walk(el, 's' + s.seriesIndex + ':' + data.getRawIndex(ecd.dataIndex));
    });
  });
  return list;
}
function readEls(chart) {
  return keyedTree(chart).map(q => elRec(q.el, q.key));
}
function keyOf(chart, target) {
  const tree = keyedTree(chart);
  for (let e = target; e; e = e.__hostTarget || e.parent) {
    const q = tree.find(t => t.el === e);
    if (q) return q.key + (e !== target && target === e.getTextContent() ? '#label' : '');
  }
  return null;
}
function readOrder(chart) {
  const tree = keyedTree(chart);
  const tags = new Map();
  tree.forEach(q => {
    tags.set(q.el, q.key);
    const tc = q.el.getTextContent && q.el.getTextContent();
    if (tc) {
      tags.set(tc, q.key + '#label');
      tc.childrenRef().forEach(c => tags.set(c, q.key + '#label'));
    }
    if (q.el.type === 'text') q.el.childrenRef().forEach(c => tags.set(c, q.key));
  });
  const out = [];
  zr(chart).storage.getDisplayList(true).forEach(d => {
    const t = tags.get(d);
    if (t !== undefined && out[out.length - 1] !== t) out.push(t);
  });
  return out;
}
function readClips(chart) {
  return customSeries(chart).map(s => {
    const view = chart.getViewOfSeriesModel(s);
    const cp = view && view.group.getClipPath();
    return { s: s.seriesIndex, rect: cp ? [cp.shape.x, cp.shape.y, cp.shape.width, cp.shape.height].map(hex) : null };
  });
}
function readSt(chart) {
  return keyedTree(chart).filter(q => !q.el.isGroup && q.el.type !== 'text').map(q => {
    const s = q.el.style;
    return { key: q.key, states: (q.el.currentStates || []).slice(), fill: colourOf(s.fill), stroke: colourOf(s.stroke),
      lineWidth: hexN(s.lineWidth), opacity: hex(opac(s)), z2: q.el.z2 };
  });
}

// ---------- transforms, recomputed (R1) ----------
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
  const rotation = t.rotation || 0;
  if (ox || oy) {
    m[4] = -ox * sx;
    m[5] = -oy * sy;
  }
  else m[4] = m[5] = 0;
  m[0] = sx; m[3] = sy; m[1] = 0; m[2] = 0;
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
  return around(t.rotation) || around(t.x) || around(t.y) || around(t.scaleX - 1) || around(t.scaleY - 1);
}
function checkTransforms(chart, fails, where) {
  customSeries(chart).forEach(s => {
    const view = chart.getViewOfSeriesModel(s);
    if (!view) return;
    const walk = (g, parentM) => g.childrenRef().forEach(el => {
      const t = {};
      TKEYS.forEach(k => { t[k] = el[k]; });
      must(!el.skewX && !el.skewY && !el.anchorX && !el.anchorY, where + ': a skew or an anchor');
      let m = null;
      if (needLocal(t) || parentM) {
        m = needLocal(t) ? localOf(t) : [1, 0, 0, 1, 0, 0];
        if (parentM) m = needLocal(t) ? mul(parentM, m) : parentM.slice();
      }
      const got = el.transform ? Array.from(el.transform) : null;
      const same = (m === null && (got === null || got.join() === '1,0,0,1,0,0'))
        || (m !== null && got !== null && m.every((v, i) => Object.is(v, got[i]) || (v === 0 && got[i] === 0)));
      if (!same) fails.push(where + ': R1 the transform ' + JSON.stringify(got) + ', the recipe ' + JSON.stringify(m));
      if (el.isGroup) walk(el, got && got.join() !== '1,0,0,1,0,0' ? got : (m || null));
    });
    walk(view.group, null);
  });
}
function checkSorted(chart, fails, where) {
  const list = zr(chart).storage.getDisplayList(true);
  for (let i = 1; i < list.length; i++) {
    const a = list[i - 1];
    const b = list[i];
    const k = (a.zlevel - b.zlevel) || (a.z - b.z) || (a.z2 - b.z2);
    if (k > 0) fails.push(where + ': R2 the display list is not sorted at ' + i);
  }
}

// ---------- the pointer ----------
function hoverTarget(chart, x, y) {
  refresh(chart);
  return zr(chart).handler.findHover(x, y).target;
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
// a point the pointer finds the element of a key at
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  const q = keyedTree(chart).find(e => e.key === t);
  must(q, where + ': no element ' + t);
  const r = q.el.getBoundingRect().clone();
  q.el.getComputedTransform();
  if (q.el.transform) r.applyTransform(q.el.transform);
  return spiral(Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2),
    (x, y) => keyOf(chart, hoverTarget(chart, x, y)) === t, where);
}
function hoverRec(chart, x, y) {
  const t = hoverTarget(chart, x, y);
  if (!t) return null;
  let d = null;
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const q = ecDataOf(e);
    if (q && q.seriesIndex != null) { d = q; break; }
  }
  return { key: keyOf(chart, t), seriesIndex: d ? d.seriesIndex : null, dataIndex: d && d.dataIndex != null ? d.dataIndex : null };
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
      // a marker is the box with a width; a value is the bold run; any other
      // run is a name
      if (st.width != null) row.marker = st.width === 10 ? 'item' : 'subItem';
      else if (st.fontWeight != null && +st.fontWeight >= 700 || st.fontWeight === 'bold') row.value = m[2];
      else row.name = m[2];
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
          icon: icon.shape.symbolType, fill: colourOf(icon.style.fill) });
      }
    }
  });
  return out;
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
const GRID = { left: 60, right: 40, top: 40, bottom: 40 };
const COLORS = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400,
  option: Object.assign({ animation: false, color: COLORS, grid: GRID }, option), steps: [] }, more || {}));

add('shape', 'gantt', "gantt bars: api.value / coord / size (a category band) / style (the series' and an item's own colour, the series opacity, the ec4 label of an empty text), encode.tooltip and the item tooltip",
  { tooltip: {}, yAxis: { type: 'category', data: ['A', 'B', 'C'] }, xAxis: { type: 'value', min: 0, max: 20 },
    series: [{ type: 'custom', name: 'jobs', renderItem: '@gantt', itemStyle: { opacity: 0.8 },
      encode: { x: [1, 2], y: 0, tooltip: [1, 2] }, dimensions: ['row', 'start', 'end', 'job'],
      data: [[0, 1, 5, 'a1'], [1, 3, 9, 'b1'], { value: [2, 6, 15, 'c1'], itemStyle: { color: '#ee6666' } }, [0, 10, 18, 'a2']] }] },
  { steps: [{ move: 's0:1' }, { move: 's0:2' }, { leave: true }] });
add('shape', 'errorbar', 'error bars: a group of three lines per item, api.visual(color), a category x axis (api.size along it)',
  { xAxis: { type: 'category', data: ['m', 't', 'w', 'r'] }, yAxis: { type: 'value' },
    series: [{ type: 'custom', renderItem: '@errorbar', encode: { x: 0, y: [1, 2] },
      data: [[0, 3, 7], [1, 5, 11], [2, 4, 8], [3, 6, 12]] }] },
  { steps: [{ move: 's0:2/1' }] });
add('shape', 'polygon', 'hexagons on two value axes: api.size with a data item, visual borderColor (none written: undefined), barLayout on a value axis (undefined), getWidth / getHeight / getDevicePixelRatio, info',
  { xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [{ type: 'custom', renderItem: '@hexagon', data: [[20, 30, 10], [50, 60, 20], [80, 40, 6]] }] },
  { steps: [{ move: 's0:1' }] });
add('shape', 'texts', "texts: a circle's textContent on top, a free text (ordinalRawValue of a guessed ordinal and of a category, api.font, params.context counting the calls), an ec4 label through api.style with its own text",
  { xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 30 },
    series: [{ type: 'custom', renderItem: '@texts', itemPayload: { k: 1 },
      data: [[0, 10, 'alpha'], [1, 20, 'beta'], [2, 15, 'gamma']] }] });
add('merge', 'groups', 'groups at their points (x / y / rotation of a group), info; a merge of new data: by index the ring leaves, by name the children keep their places and turn',
  { xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [{ type: 'custom', renderItem: '@groups', data: [[10, 10, 0], [30, 40, 0], [60, 20, 0]] }] },
  { steps: [{ merge: { series: [{ data: [[10, 10, 0], [35, 45, 1], [60, 20, 2]] }] } },
    { merge: { series: [{ data: [[15, 15, 0], [35, 45, 1], [60, 20, 2], [80, 80, 0]] }] } }] });
add('shape', 'barlayout', "two custom series sharing the band through api.barLayout (count 2, barGap '20%', barCategoryGap 10; count 3 with barWidth and barMaxWidth recorded)",
  { xAxis: { type: 'category', data: ['p', 'q', 'r'] }, yAxis: { type: 'value', min: 0, max: 12 },
    series: [{ type: 'custom', renderItem: '@bar0', encode: { x: 0, y: 1 }, data: [[0, 5], [1, 8], [2, 3]] },
      { type: 'custom', renderItem: '@bar1', encode: { x: 0, y: 1 }, data: [[0, 7], [1, 2], [2, 10]] }] });
add('shape', 'clip', 'clip: true (widened by lineStyle.width 4) against the default clip: false; squares across the grid edges',
  { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', renderItem: '@square', clip: true, lineStyle: { width: 4 }, data: [[0, 5], [5, 5], [9, 9]] },
      { type: 'custom', renderItem: '@square', data: [[10, 0], [2, 9]] }] });
add('legend', 'legend', "a legend over two custom series: the icons; a toggle hides one (currentSeriesIndices drops it) and brings it back (the same elements, updated)",
  { legend: {}, xAxis: { type: 'category', data: ['u', 'v'] }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', name: 'P', renderItem: '@dot', data: [[0, 3], [1, 6]] },
      { type: 'custom', name: 'Q', renderItem: '@dot', data: [[0, 5], [1, 8]] }] },
  { steps: [{ action: { type: 'legendToggleSelect', name: 'P' } }, { action: { type: 'legendToggleSelect', name: 'P' } }] });
add('zoom', 'datazoom', "dataZoom inside with filterMode 'weakFilter' on the x axis both ends of a span feed: a span straddling or touching the window stays; dataIndex against dataIndexInside; a dataZoom action's actionType",
  { yAxis: { type: 'category', data: ['A', 'B', 'C'] }, xAxis: { type: 'value', min: 0, max: 100 },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, filterMode: 'weakFilter', start: 30, end: 60 }],
    series: [{ type: 'custom', renderItem: '@span', encode: { x: [1, 2], y: 0 },
      data: [[0, 5, 20], [1, 10, 40], [2, 25, 80], [0, 50, 55], [1, 65, 90], [2, 0, 100]] }] },
  { steps: [{ action: { type: 'dataZoom', start: 0, end: 40 } }, { action: { type: 'dataZoom', start: 70, end: 100 } }] });
add('hover', 'emphasis', 'emphasis: a declared emphasis style on the rect, the default lift on the circle (z2 3, its lift 1), the whole item enters the state together; leave',
  { xAxis: { type: 'category', data: ['e', 'f'] }, yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'custom', renderItem: '@hover', data: [[0, 6], [1, 4]] }] },
  { steps: [{ move: 's0:0/0' }, { move: 's0:1/1' }, { leave: true }] });

// ---------------------------------------------------------------------------
// one case
// ---------------------------------------------------------------------------
function runCase(c) {
  const fails = [];
  const chart = mk(c.W, c.H);
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option), steps: clone(c.steps),
      states: [] };
    const tv = () => {
      const m = chart.getModel().getComponent('tooltip', 0);
      return m ? chart.getViewOfComponentModel(m) : null;
    };
    CALLS = [];
    quiet(() => chart.setOption(materialize(c.option)));
    paint(chart);
    const state = (step) => {
      const st = { calls: CALLS.splice(0) };
      const pointer = step && (step.move !== undefined || step.leave);
      if (!pointer) {
        st.els = readEls(chart);
        st.order = readOrder(chart);
        st.clips = readClips(chart);
      }
      st.st = readSt(chart);
      st.legend = legendRec(chart);
      checkTransforms(chart, fails, c.id);
      checkSorted(chart, fails, c.id);
      return st;
    };
    rec.states.push(state(null));
    c.steps.forEach((step, i) => {
      const where = c.id + ' step ' + i;
      settle(NOW + 500);
      let point = null;
      if (step.move !== undefined) {
        point = resolvePoint(chart, step.move, where);
        zr(chart).handler.mousemove(raw(point[0], point[1]));
      }
      else if (step.leave) zr(chart).handler.mouseout(raw(-1, -1));
      else if (step.action) quiet(() => chart.dispatchAction(clone(step.action)));
      else if (step.merge) quiet(() => chart.setOption(materialize(step.merge)));
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      paint(chart);
      settle(NOW + 500);
      paint(chart);
      const st = state(step);
      st.point = point;
      st.hover = point ? hoverRec(chart, point[0], point[1]) : null;
      const t = tv();
      if (t) {
        const ct = t._tooltipContent;
        const vis = !!(ct && ct.el && !ct.el.ignore && !ct.el.invisible);
        st.tooltip = { shown: vis, rows: vis ? tooltipRows(ct) : null };
      }
      else st.tooltip = null;
      rec.states.push(st);
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
  const el = (id, key, si) => cs(id).states[si || 0].els.find(e => e.key === key);
  const num = h => {
    bits.setUint32(0, parseInt(h.slice(0, 8), 16));
    bits.setUint32(4, parseInt(h.slice(8), 16));
    return bits.getFloat64(0);
  };
  const call = (id, si, k) => cs(id).states[si].calls[k];
  const apiOf = (c, fn) => c.api.filter(a => a.fn === fn);
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  out.cases.forEach(q => q.states.forEach((s, i) => {
    const step = i > 0 ? q.steps[i - 1] : null;
    if (step && (step.move !== undefined || step.leave)) guard(q.id + ' state ' + i + ': a pointer step renders nothing', s.calls.length === 0);
  }));
  const g0 = call('gantt', 0, 0);
  guard('one call per item shown', cs('gantt').states[0].calls.length === 4);
  guard('the params name the series and its coordinate system', g0.params.seriesName === 'jobs' && g0.params.coordSys.type === 'cartesian2d'
    && g0.params.encode.x.join() === '1,2' && g0.params.encode.y.join() === '0' && g0.params.actionType === null);
  guard("api.style carries the item's own colour", apiOf(call('gantt', 0, 2), 'style')[0].ret.fill === '#ee6666'
    && apiOf(call('gantt', 0, 0), 'style')[0].ret.fill === '#5470c6');
  guard('api.style is legacy and carries the series opacity', apiOf(call('gantt', 0, 0), 'style')[0].ret.legacy === true
    && num(apiOf(call('gantt', 0, 0), 'style')[0].ret.opacity) === 0.8);
  guard('a category band is the size along it', num(apiOf(g0, 'size')[0].ret[1]) > 50);
  guard('the ec4 style made a silent label', el('gantt', 's0:0').label && el('gantt', 's0:0').label.silent);
  const gt = cs('gantt').states[1];
  guard('the tooltip names the hovered row with both encoded values', gt.tooltip.shown && gt.hover.dataIndex === 1
    && gt.tooltip.rows.some(r => r.value != null));
  guard('an error bar is a group of three lines', el('errorbar', 's0:0').type === 'group' && el('errorbar', 's0:0/2').type === 'line');
  guard('the hovered line names its item', cs('errorbar').states[1].hover.dataIndex === 2);
  const h0 = call('polygon', 0, 0);
  guard('barLayout on a value axis is undefined', apiOf(h0, 'barLayout')[0].ret === null);
  guard('an unwritten borderColor visual is undefined', apiOf(h0, 'visual')[1].ret === null);
  guard('getWidth is the chart width', num(apiOf(h0, 'getWidth')[0].ret) === 600);
  guard('info rides the element', el('polygon', 's0:0').info === JSON.stringify({ w: 600, h: 400, dpr: 1 }));
  const t2 = call('texts', 0, 2);
  guard('the context is shared by the calls of one render', t2.params.context.n === hex(2));
  guard('ordinalRawValue reads a category and a guessed ordinal', apiOf(t2, 'ordinalRawValue')[0].ret === 'gamma'
    && apiOf(t2, 'ordinalRawValue')[1].ret === 'c');
  guard('api.font assembles the global text style', /^normal bold 14px /.test(apiOf(t2, 'font')[0].ret));
  guard('a textContent above its circle', el('texts', 's0:0/0').label && el('texts', 's0:0/0').label.style.text === '10');
  guard('the ec4 rect label says L1', el('texts', 's0:1/2').label.style.text === 'L1');
  const gr = cs('groups').states;
  guard('a group sits at its point', num(gr[0].els.find(e => e.key === 's0:1').t.x) > 100);
  guard('by index the ring leaves', !gr[1].els.some(e => e.key === 's0:1/1') && gr[0].els.some(e => e.key === 's0:1/1'));
  guard('by name the box stays first', gr[1].els.find(e => e.key === 's0:2/0').type === 'rect' && num(gr[1].els.find(e => e.key === 's0:2').t.rotation) > 0);
  guard('a new item is added last', gr[2].els[gr[2].els.length - 1].key.startsWith('s0:3'));
  guard('an update replaces the style: the stroke it does not write is gone', gr[0].els.find(e => e.key === 's0:1/0').style.stroke === '#333'
    && gr[1].els.find(e => e.key === 's0:1/0').style.stroke === null);
  const b0 = call('barlayout', 0, 0);
  guard('barLayout answers two columns', apiOf(b0, 'barLayout')[0].ret.length === 2 && apiOf(b0, 'barLayout')[1].ret.length === 3);
  const cl = cs('clip').states[0].clips;
  guard('clip: true clips, the default does not', cl[0].rect && !cl[1].rect);
  guard('the clip is widened by lineStyle.width', num(cl[0].rect[0]) === 58);
  const lg = cs('legend').states;
  guard('a hidden series is not drawn', !lg[1].els.some(e => e.key.startsWith('s0:')) && lg[1].calls.every(c => c.s === 1));
  guard('currentSeriesIndices leaves the hidden one out', apiOf(lg[1].calls[0], 'currentSeriesIndices')[0].ret.length === 1);
  guard('shown again it is drawn', lg[2].els.some(e => e.key === 's0:1'));
  guard('the legend lists both', lg[0].legend.length === 2 && lg[1].legend.some(l => !l.selected));
  const dz = cs('datazoom').states;
  guard('weakFilter keeps a straddling span', dz[0].calls.some(c => c.params.dataIndex === 5));
  guard('weakFilter drops a span outside', !dz[0].calls.some(c => c.params.dataIndex === 0));
  guard('dataIndexInside counts what is shown', dz[0].calls.some(c => c.params.dataIndex !== c.params.dataIndexInside));
  guard("a dataZoom action's actionType", dz[1].calls.length > 0 && dz[1].calls.every(c => c.params.actionType === 'dataZoom'));
  const em = cs('emphasis').states;
  const stOf = (s, key) => s.st.find(e => e.key === key);
  guard('the declared emphasis fill', stOf(em[1], 's0:0/0').states.join() === 'emphasis' && stOf(em[1], 's0:0/0').fill.join() === '238,102,102,1');
  guard('the whole item enters together', stOf(em[1], 's0:0/1').states.join() === 'emphasis');
  guard('the circle lifts by 1', stOf(em[2], 's0:1/1').z2 === 4);
  guard('leaving clears the states', em[3].st.every(e => e.states.length === 0));
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, 600 x 400, animation false, the grid 60 / 40 / 40 / 40.',
      'a paint (renderToSVGString) after setOption and after every step builds every path and text block.',
      'pointer steps go through zrender\'s Handler; the timers settle 500 ms before and after every step.',
      'renderItem: \'@name\' is the recorder of RENDER[name]: the params, every api call and its answer, the tree returned.',
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
