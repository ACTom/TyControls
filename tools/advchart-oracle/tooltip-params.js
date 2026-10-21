// Upstream's own answers for fix batch R2-E: what a tooltip formatter is
// given over a sunburst, a treemap and a sankey -- the series' own
// getDataParams: SunburstSeries and TreemapSeries add treePathInfo
// (wrapTreePathInfo: every node from the root down, {name, dataIndex, value:
// getRawValue}; the treemap's also as treeAncestors), SankeySeries gives a
// node without a value its layout value; the rest is SeriesModel's
// (componentType, componentSubType, componentIndex, seriesType,
// seriesIndex, seriesId, seriesName, name, dataIndex, dataType, value).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node as tooltip-keep.js does (SVG renderer, ssr: true then
// chart._ssr = false, env.node off and getDom answering an empty object so
// TooltipView runs, Math.random the port's xorshift32, Date and setTimeout
// on a fake clock). The tooltip's formatter is a function that keeps what it
// is given; the pointer goes onto an item through zrender's Handler.
//
//   node tools/advchart-oracle/tooltip-params.js
//
// writes tests/fixtures/advchart-tooltip-params.json (ORACLE_OUT overrides).
//
// Fixture: source, W, H, seed, notes[], cases[] {id, note, option (the
// formatter written '@tipParams'), steps[] {at [x, y], aim, params (the
// last call's: the keys above, value as String() prints it and as JSON,
// treePathInfo as given, or null for a series that has none)}}, guards[].
// Self-checks: every guard holds; the JSON parses back; two generations give
// the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const CLOCK0 = 1700000000000;
let NOW = CLOCK0;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tooltip-params.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

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

function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function rawEvent(type, x, y) {
  return {
    type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {},
  };
}

// ---------- an integer point over an item (tooltip-keep.js) ----------
function ecData(el) {
  const k = Object.keys(el).find(n => /^__ec_inner_\d+$/.test(n) && el[n] && 'dataIndex' in el[n]);
  return k ? el[k] : null;
}
function dispatcherOf(el) {
  for (let e = el; e; e = e.__hostTarget || e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return d;
  }
  return null;
}
// a tree's elements are typed 'main' (its one data): '' here
const typeOf = d => (!d.dataType || d.dataType === 'main' ? '' : d.dataType);
function pointOn(chart, seriesIndex, dataIndex, dataType, where) {
  const els = chart.getZr().storage.getDisplayList(true);
  const h = chart.getZr().handler;
  for (const el of els) {
    const d = dispatcherOf(el);
    if (!d || d.seriesIndex !== seriesIndex || d.dataIndex !== dataIndex || typeOf(d) !== dataType) continue;
    const r = el.getBoundingRect().clone();
    const m = el.getComputedTransform();
    if (m) r.applyTransform(m);
    const cx = Math.round(r.x + r.width / 2);
    const cy = Math.round(r.y + r.height / 2);
    const R = Math.ceil(Math.max(r.width, r.height) / 2) + 1;
    for (let rad = 0; rad <= R; rad++) {
      for (let dx = -rad; dx <= rad; dx++) {
        for (let dy = -rad; dy <= rad; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
          const hv = h.findHover(cx + dx, cy + dy);
          const hd = hv && hv.target ? dispatcherOf(hv.target) : null;
          if (hd && hd.seriesIndex === seriesIndex && hd.dataIndex === dataIndex && typeOf(hd) === dataType) return [cx + dx, cy + dy];
        }
      }
    }
  }
  throw new OracleError(where + ': no point over ' + seriesIndex + '/' + dataIndex + ' ' + dataType);
}

// ---------- the cases ----------
const tree = [
  { name: 'r', children: [
    { name: 'a', children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2 }] },
    { name: 'b', value: 7, children: [{ name: 'b1', value: 3 }] },
    { name: 'c', value: 6 }] },
];
const SN = [{ name: 'n0' }, { name: 'n1', value: 2 }, { name: 'n2' }, { name: 'n3' }];
const SL = [{ source: 'n0', target: 'n1', value: 5 }, { source: 'n0', target: 'n2', value: 3 },
  { source: 'n1', target: 'n3', value: 4 }, { source: 'n2', target: 'n3', value: 2 }];
const TIP = { trigger: 'item', formatter: '@tipParams' };
const CASES = [
  { id: 'sunburst', note: 'sunburst: treePathInfo from the root down, each value getRawValue (a parent its summed value)',
    option: { animation: false, tooltip: TIP, series: [{ type: 'sunburst', name: 'sb', id: 'sbId', radius: [0, '90%'], data: tree }] },
    aims: [[0, 4, ''], [0, 1, ''], [0, 2, ''], [0, 6, '']] },
  { id: 'treemap', note: 'treemap: treePathInfo (and treeAncestors) the same way; the leaves are what the pointer finds',
    option: { animation: false, tooltip: TIP, series: [{ type: 'treemap', top: 10, bottom: 60, left: 10, right: 10, data: tree }] },
    aims: [[0, 3, ''], [0, 4, ''], [0, 6, ''], [0, 7, '']] },
  { id: 'sankey', note: 'sankey: a node without a value takes its layout value, one with a value keeps it; an edge its own',
    option: { animation: false, tooltip: TIP, series: [{ type: 'sankey', name: 'sk', left: 40, right: 140, top: 40, bottom: 40, data: SN, links: SL }] },
    aims: [[0, 0, 'node'], [0, 1, 'node'], [0, 3, 'node'], [0, 0, 'edge'], [0, 2, 'edge']] },
];

const KEYS = ['componentType', 'componentSubType', 'componentIndex', 'seriesType', 'seriesIndex', 'seriesId', 'seriesName', 'name',
  'dataIndex', 'dataType'];
function record(p) {
  const out = {};
  // NUL (an auto id's, an auto name's) written U+2400, as the other oracles do
  for (const k of KEYS) out[k] = p[k] === undefined ? null : (typeof p[k] === 'string' ? p[k].split('\u0000').join('\u2400') : p[k]);
  out.valueText = String(p.value);
  out.value = p.value === undefined ? null : JSON.parse(JSON.stringify(p.value));
  out.treePathInfo = p.treePathInfo === undefined ? null : JSON.parse(JSON.stringify(p.treePathInfo));
  out.sameAncestors = p.treeAncestors === undefined ? null : JSON.stringify(p.treeAncestors) === JSON.stringify(p.treePathInfo);
  return out;
}

function withFns(v, fn) {
  if (v === '@tipParams') return fn;
  if (Array.isArray(v)) return v.map(x => withFns(x, fn));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = withFns(v[k], fn);
    return o;
  }
  return v;
}

function runCase(def) {
  NOW = CLOCK0;
  const chart = newChart();
  let last = null;
  const fn = p => { last = record(p); return 'tip'; };
  try {
    chart.setOption(withFns(JSON.parse(JSON.stringify(def.option)), fn));
    frame(chart);
    const steps = [];
    for (const [s, d, t] of def.aims) {
      // off everything first: the next item is a new show
      chart.getZr().handler.mouseout(rawEvent('mouseout', W + 50, H / 2));
      NOW += 1000;
      frame(chart);
      last = null;
      const at = pointOn(chart, s, d, t, def.id);
      NOW += 10;
      chart.getZr().handler.mousemove(rawEvent('mousemove', at[0], at[1]));
      frame(chart);
      must(last, def.id + ': the formatter was not called at ' + s + '/' + d + ' ' + t);
      steps.push({ at, aim: s + '/' + d + (t ? ' ' + t : ''), params: last });
    }
    return { id: def.id, note: def.note, option: def.option, steps };
  } finally {
    chart.dispose();
  }
}

function generate() {
  return CASES.map(runCase);
}

function anchors(cases) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const cs = id => cases.find(c => c.id === id);
  const sb = cs('sunburst');
  const p0 = sb.steps[0].params;
  guard('sb-path', p0.treePathInfo && p0.treePathInfo.length === 4 && p0.treePathInfo[0].name === 'sb' && p0.treePathInfo[3].name === p0.name,
    'sunburst: treePathInfo from the virtual root (named as the series) to the node');
  const tm = cs('treemap');
  guard('tm-ancestors', tm.steps.every(s => s.params.sameAncestors === true), 'treemap: treeAncestors is treePathInfo');
  const sk = cs('sankey');
  guard('sk-layout', sk.steps[0].params.value === 8 && sk.steps[1].params.value === 2, 'sankey: a node without a value its layout value, one with a value its own');
  guard('sk-edge', sk.steps[3].params.dataType === 'edge' && sk.steps[3].params.value === 5 && sk.steps[3].params.treePathInfo === null,
    'sankey: an edge its own value, no tree path');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Each aim: a mouseout from outside the canvas, a second later a mousemove onto the item; the formatter\'s last call is recorded.',
  'valueText is String(params.value); value is params.value as JSON; treePathInfo as given (null where the series gives none); '
    + 'sameAncestors whether treeAncestors (the treemap\'s) equals it.',
];

let g1;
let json1;
let json2;
let guards;
try {
  g1 = generate();
  guards = anchors(g1);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version,
    W, H, seed: SEED, notes: NOTES, cases: g1, guards,
  };
  json1 = JSON.stringify(out, null, 1) + '\n';
  JSON.parse(json1);
  const g2 = generate();
  json2 = JSON.stringify(Object.assign({}, out, { cases: g2, guards: anchors(g2) }), null, 1) + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const bad = guards.filter(gd => !gd.ok);
guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': ' + gd.what));
const deterministic = json1 === json2;
console.log(g1.length + ' cases, ' + g1.reduce((n, c) => n + c.steps.length, 0) + ' aims; ' + (guards.length - bad.length) + '/' + guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages'
  + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (process.env.ORACLE_DEBUG) for (const c of g1) for (const s of c.steps) console.log(c.id, s.aim, JSON.stringify(s.params));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
