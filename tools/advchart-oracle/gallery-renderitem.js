/*
Upstream's own answers for round-2 batch R2-J: the gallery examples whose
custom series draw with a renderItem FUNCTION. The harvest names each one
(`renderItem: '@<id>'`, a second function '@<id>#2', ...: the
tools/advchart-gallery/harvest.js namer) and the demo registers a Pascal
transcription of it under that name (examples/advchart/urenderitems.pas).
This script says what the transcription must draw.

HOW THE FUNCTIONS ARE GOT. Not copied by hand: harvest.js is required as a
module and runs each example exactly as the harvest ran it (the same sandbox,
seeded Math.random, the virtual clock), so the functions are the page's own,
closing over the page's own data. The option is the gallery file as shipped
(examples/advchart/gallery/<file>) with every '@name' turned back into the
function the namer gave that name -- so the chart here gets what the demo's
chart gets, the dropped callbacks (label formatters, tooltip positions) as
absent here as there. Guard: the live option stringified by the namer is the
gallery file, byte for byte.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node off (custom-series.js' recipe), the clock of animation.js
(the global Date replaced BEFORE the dist loads), Math.random the port's
xorshift32 for the chart's own draws and zrender's width table measuring
every string. An SVG map is registered from examples/advchart/maps, parsed
by jsdom's DOMParser (geo-svg.js' recipe). Every chart: 960 x 600, the
option's root `animation: false` (keyframe animations do not run).

  node tools/advchart-oracle/gallery-renderitem.js

writes tests/fixtures/advchart-gallery-renderitem.json (ORACLE_OUT
overrides). Needs the TypeScript compiler for the harvest's sandbox (TY_TSC,
default D:/Projects/xterm.js/node_modules/typescript) and the examples clone
(D:/Projects/echarts-examples). Ends with process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000).

Top level: source, version, seed, W, H, measure {firstCode, ratio[] (hex)},
notes[], cases[], guards[].

A case: id (the gallery id), files[] (the gallery files set in order: the
first by setOption, each later one merged), maps[] ({name, file} SVG maps
registered), handlers[] (the names the files use), state: {els[], order[],
clips[]} after the last file -- custom-series.js' records (elRec: key
's<series>:<raw dataIndex>' for an item's root, '/k' per child, type, name,
ignore, invisible, silent, z, z2, zlevel, t, transform, shape, path, style,
pieces, label, ec, info), plus for an image: style {image, x, y, width,
height, opacity}.

Guards (any failure: nothing is written, exit 1): the gallery file is the
live option as the namer writes it; every case draws something; named
discriminating facts; the whole fixture generated twice, byte-identical; no
\u0000; it parses back.
*/
'use strict';
process.env.TZ = 'UTC';
process.env.TY_TSC = process.env.TY_TSC || 'D:/Projects/xterm.js/node_modules/typescript';
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

// ---------- a DOMParser for parseXML (geo-svg.js) ----------
const JSDOM_PATH = process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom';
const { JSDOM } = require(JSDOM_PATH);
global.DOMParser = new JSDOM('').window.DOMParser;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
const MAPS = path.join(ROOT, 'examples', 'advchart', 'maps');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-gallery-renderitem.json');
const HARVEST = require(path.join(ROOT, 'tools', 'advchart-gallery', 'harvest.js'));
HARVEST.setSeeded(true);

const W = 960;
const H = 600;

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
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

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

function mk() {
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
function customInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'customGraphicType' in el[k]) return el[k];
  }
  return null;
}

// ---------------------------------------------------------------------------
// reading the elements (custom-series.js' records)
// ---------------------------------------------------------------------------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY'];
const pathData = el => {
  if (!el.path) el.getBoundingRect();
  must(el.path, 'no path proxy');
  return Array.from(el.path.data).slice(0, el.path.len());
};
const opac = st => (st.opacity == null ? 1 : st.opacity);
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
  else if (el.type === 'image') {
    const s = el.style;
    r.style = { image: typeof s.image === 'string' ? s.image : null, x: hexN(s.x), y: hexN(s.y),
      width: hexN(s.width), height: hexN(s.height), opacity: hex(opac(s)) };
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

// ---------------------------------------------------------------------------
// the cases: every gallery example whose files name a renderItem
// ---------------------------------------------------------------------------
const INDEX = JSON.parse(fs.readFileSync(path.join(GALLERY, 'index.json'), 'utf8'));
const MAPS_INDEX = JSON.parse(fs.readFileSync(path.join(MAPS, 'maps.json'), 'utf8'));

// the files an example sets, in order: its own, or its sequence's up to and
// including the last step that names a renderItem
function filesOf(entry) {
  if (!entry.sequence) return [{ file: entry.id + '.json', opts: null }];
  const steps = entry.sequence.steps.map(s => ({ file: s.file, opts: s.opts || null }));
  let last = 0;
  steps.forEach((s, i) => {
    if (fs.readFileSync(path.join(GALLERY, s.file), 'utf8').indexOf('"renderItem": "@') >= 0) last = i;
  });
  return steps.slice(0, last + 1);
}

// the live options of a run: the first shown, then each interval tick's
function liveOptions(entry) {
  const src = fs.readFileSync(path.join(HARVEST.TS_DIR, entry.id + '.ts'), 'utf8');
  const collected = {};
  const run = HARVEST.runExample(src, entry.id + '.ts', collected);
  const out = run.shown.map(s => s.option);
  const ticks = (collected.intervals || []);
  for (let t = 0; t < 4 && ticks.length; t++) {
    const before = (collected.calls || []).length;
    ticks.forEach(iv => iv.fn());
    (collected.calls || []).slice(before).forEach(c => out.push(c.option));
  }
  return { out, collected };
}

function materialize(v, byName) {
  if (Array.isArray(v)) return v.map(x => materialize(x, byName));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (typeof v[k] === 'string' && v[k][0] === '@' && byName.has(v[k].slice(1))) o[k] = byName.get(v[k].slice(1));
      else o[k] = materialize(v[k], byName);
    }
    return o;
  }
  return v;
}

// the SVG maps an option names that maps.json ships as .svg
function svgMapsOf(text) {
  const out = [];
  for (const name of Object.keys(MAPS_INDEX.maps)) {
    const f = MAPS_INDEX.maps[name].file;
    if (!/\.svg$/i.test(f)) continue;
    if (text.indexOf('"map": "' + name + '"') >= 0) out.push({ name, file: f });
  }
  return out;
}

function runCase(entry) {
  const files = filesOf(entry);
  const live = liveOptions(entry);
  const namer = live.collected.namer;
  const byName = new Map();
  namer.names.forEach((name, fn) => byName.set(name, fn));
  const texts = files.map(f => fs.readFileSync(path.join(GALLERY, f.file), 'utf8'));
  // the gallery file is the live option, as the namer writes it
  texts.forEach((t, i) => {
    const liveOpt = live.out[i];
    must(liveOpt, entry.id + ': no live option for ' + files[i].file);
    must(JSON.stringify(liveOpt, namer.replacer, 1) === t,
      entry.id + ': ' + files[i].file + ' is not the live option as the harvest writes it');
  });
  const maps = [];
  texts.forEach(t => svgMapsOf(t).forEach(m => {
    if (!maps.some(x => x.name === m.name)) maps.push(m);
  }));
  maps.forEach(m => echarts.registerMap(m.name, { svg: fs.readFileSync(path.join(MAPS, m.file), 'utf8') }));
  const chart = mk();
  try {
    texts.forEach((t, i) => {
      const opt = materialize(JSON.parse(t), byName);
      if (i === 0) quiet(() => chart.setOption(Object.assign({ animation: false }, opt)));
      else quiet(() => chart.setOption(opt, files[i].opts || undefined));
      paint(chart);
    });
    const tree = keyedTree(chart);
    return {
      id: entry.id,
      files: files.map(f => (f.opts ? { file: f.file, opts: f.opts } : { file: f.file })),
      maps,
      handlers: Array.from(byName.keys()).filter(n => texts.some(t => t.indexOf('"@' + n + '"') >= 0)),
      state: {
        els: tree.map(q => elRec(q.el, q.key)),
        order: readOrder(chart),
        clips: readClips(chart)
      }
    };
  } finally {
    chart.dispose();
  }
}

function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(c => c.id === id);
  const els = id => cs(id).state.els;
  out.cases.forEach(c => guard(c.id + ' draws something', c.state.els.length > 0));
  guard('bar trend: one polyline per category in the window',
    els('custom-bar-trend').every(e => e.type === 'polyline'));
  guard('calendar icon: icons are paths fitted into 16 x 16 boxes',
    els('custom-calendar-icon').some(e => e.type === 'path'));
  guard('cartesian polygon: one polygon (params.context.rendered)',
    els('custom-cartesian-polygon').filter(e => e.type === 'polygon').length === 1);
  guard('error bar: three lines per item', els('custom-error-bar').filter(e => e.type === 'line').length % 3 === 0);
  guard('polar heatmap: sectors', els('custom-polar-heatmap').every(e => e.type === 'sector'));
  guard('profit: a rect per item with an ec4 label',
    els('custom-profit').filter(e => e.type === 'rect' && e.label).length === 6);
  guard('wind barb: arrows as paths and weather as images with texts',
    els('wind-barb').some(e => e.type === 'path') && els('wind-barb').some(e => e.type === 'image'));
  guard('the geo effect: a pin path in every group', els('geo-svg-custom-effect').some(e => e.type === 'path'));
  guard('parliament: circles after the step', els('pie-parliament-transition').some(e => e.type === 'circle'));
  guard('mini bars on three series', new Set(els('matrix-mini-bar-data-collection').map(e => e.key.split(':')[0])).size === 3);
  return g;
}

function generate() {
  NOW = T0;
  const ids = INDEX.entries.filter(e => e.ok && e.handlers && e.handlers.some(h => h.indexOf('.') < 0))
    .map(e => e.id);
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, ' + W + ' x ' + H + ', the option\'s root animation false.',
      'the option is the gallery file with each \'@name\' the function the harvest namer named so (the page\'s own).',
      'a later file of a sequence is merged with the options the page passed (setOption(option, opts)).',
      'a paint (renderToSVGString) after every setOption builds every path and text block.',
    ],
    cases: INDEX.entries.filter(e => ids.indexOf(e.id) >= 0).map(runCase),
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
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
console.log(out1.cases.length + ' cases (' + out1.cases.map(c => c.id + ' ' + c.state.els.length).join(', ') + '); '
  + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
