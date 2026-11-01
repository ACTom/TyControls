// Upstream's own answers for round-5 batch R5-D (2026-10-27): the legacy
// sunburst actions (chart/sunburst/sunburstAction.ts):
//   sunburstHighlight (update 'none'): the payload cloned; for every sunburst
//     series the payload queries (all when it names none), retrieveTargetInfo
//     finds targetNode (a string: the root's getNodeById) or targetNodeId
//     and writes that node's dataIndex into the clone; the clone is then
//     dispatched as a `highlight` -- through api.dispatchAction, so it waits
//     for the action (its event comes first)
//   sunburstUnhighlight (update 'updateView'): the clone dispatched as a
//     `downplay`
//
// The harness is axis-emphasis.js' (node, SVG, a fake clock, chart._ssr
// false). Per step: events [[chart, type, payload]] (sunbursthighlight,
// sunburstunhighlight, highlight, downplay, updated) and per series which
// items are in emphasis (e) or blur (b), by raw index.
//
//   node tools/advchart-oracle/sunburst-legacy.js
//
// writes tests/fixtures/advchart-sunburst-legacy.json (ORACLE_OUT overrides).
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the fake clock and timers (installed before the build loads) ----------
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
function advanceClock(to) {
  for (;;) {
    let best = null;
    for (const t of TIMERS) if (t.due <= to && (!best || t.due < best.due || (t.due === best.due && t.id < best.id))) best = t;
    if (!best) break;
    TIMERS = TIMERS.filter(t => t !== best);
    if (best.due > NOW) NOW = best.due;
    best.fn();
  }
  NOW = to;
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-sunburst-legacy.json');

const W = 600;
const H = 400;
const SIZE = [80, 40];
const STEP_DT = 10;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the seeded Math.random (the port's xorshift32) ----------
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

// ---------- records ----------
const clone = v => JSON.parse(JSON.stringify(v));
const NULMARK = '\u2400';
function plain(v, depth) {
  if (typeof v === 'string') return v.split('\u0000').join(NULMARK);
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return 'NaN';
    if (!Number.isFinite(v)) return v > 0 ? 'Infinity' : '-Infinity';
    return v;
  }
  if (v === null || typeof v !== 'object') return typeof v === 'function' ? undefined : v;
  must(depth < 40, 'too deep');
  if (Array.isArray(v)) return v.map(x => { const s = plain(x, depth + 1); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    if (v[k] === undefined) continue;
    if (/^__ec_inner_\d+$/.test(k)) continue;
    const s = k === 'from' && typeof v[k] === 'string' ? '<view uid>' : plain(v[k], depth + 1);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
const jsonOf = ev => (ev === undefined ? null : plain(JSON.parse(JSON.stringify(ev)), 0));

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

// ---------- the tooltip view, watched ----------
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function watchTooltip(chart) {
  const view = tooltipView(chart);
  const w = { which: null, view };
  if (!view) return w;
  const content = view._tooltipContent;
  must(content, 'no tooltip content');
  content.getSize = () => SIZE.slice();
  const show = view._showTooltipContent;
  view._showTooltipContent = function (tooltipModel, html, params) {
    if (Array.isArray(params)) {
      w.which = 'axis:' + params.map(p => p.seriesIndex + '/' + p.dataIndex + '@' + p.axisDim + p.axisIndex).join(',');
    } else if (params && params.componentType === 'series') {
      w.which = 'item:' + params.seriesIndex + ':' + params.dataIndex;
    } else w.which = 'other';
    return show.apply(this, arguments);
  };
  return w;
}
const visible = c => !!(c && c.el && !c.el.ignore && !c.el.invisible);

function statesOf(el) {
  if (!el) return null;
  const p = typeof el.getSymbolPath === 'function' ? el.getSymbolPath() : el;
  return (p && p.currentStates) || [];
}
function stateOf(chart, w) {
  const series = [];
  chart.getModel().eachSeries(function (sm) {
    const data = sm.getData();
    const view = chart.getViewOfSeriesModel(sm);
    const rec = { e: [], b: [], t: [] };
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const st = statesOf(el);
      if (!st) continue;
      const raw = data.getRawIndex(i);
      if (st.indexOf('emphasis') >= 0) rec.e.push(raw);
      if (st.indexOf('blur') >= 0) rec.b.push(raw);
      if (el.__temp) rec.t.push(raw);
    }
    rec.poly = view && view._polyline ? (view._polyline.currentStates || []).join(',') : null;
    series.push(rec);
  });
  let tip = null;
  if (w.view) tip = visible(w.view._tooltipContent) ? w.which : null;
  return { series, tip };
}

// ---------- an integer point over an item (tooltip-actions.js) ----------
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
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
function pointOn(chart, seriesIndex, dataIndex, where) {
  const els = chart.getZr().storage.getDisplayList(true);
  const h = chart.getZr().handler;
  for (const el of els) {
    const d = dispatcherOf(el);
    if (!d || d.seriesIndex !== seriesIndex || d.dataIndex !== dataIndex || d.dataType) continue;
    const r = globalRect(el);
    const cx = Math.round(r.x + r.width / 2);
    const cy = Math.round(r.y + r.height / 2);
    const R = Math.ceil(Math.max(r.width, r.height) / 2) + 1;
    for (let rad = 0; rad <= R; rad++) {
      for (let dx = -rad; dx <= rad; dx++) {
        for (let dy = -rad; dy <= rad; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
          const hv = h.findHover(cx + dx, cy + dy);
          const hd = hv && hv.target ? dispatcherOf(hv.target) : null;
          if (hd && hd.seriesIndex === seriesIndex && hd.dataIndex === dataIndex && !hd.dataType) return [cx + dx, cy + dy];
        }
      }
    }
  }
  throw new OracleError(where + ': no point over ' + seriesIndex + '/' + dataIndex);
}

// =====================================================================
// the cases
// =====================================================================
const tree = [
  { name: 'a', value: 4 },
  { name: 'b', children: [{ name: 'b1', value: 2 }, { name: 'b2', value: 3 }] },
  { name: 'c', id: 'cid', value: 5 },
];
const CASES = [
  {
    id: 'one', note: 'one sunburst (emphasis.focus ancestor): sunburstHighlight by targetNode (an id -- the name), by targetNodeId, by '
      + 'an unknown node (no dataIndex: the whole series), sunburstUnhighlight (updateView, then a downplay)',
    charts: [{ animation: false, series: [{ type: 'sunburst', radius: [0, '90%'], emphasis: { focus: 'ancestor' }, data: tree }] }], group: null,
    steps: [
      { op: 'action', chart: 0, payload: { type: 'sunburstHighlight', targetNode: 'b1' } },
      { op: 'action', chart: 0, payload: { type: 'sunburstUnhighlight' } },
      { op: 'action', chart: 0, payload: { type: 'sunburstHighlight', seriesIndex: 0, targetNodeId: 'cid' } },
      { op: 'action', chart: 0, payload: { type: 'sunburstUnhighlight', seriesIndex: 0 } },
      { op: 'action', chart: 0, payload: { type: 'sunburstHighlight', seriesIndex: 0, targetNode: 'nope' } },
      { op: 'action', chart: 0, payload: { type: 'sunburstUnhighlight' } },
    ],
  },
  {
    id: 'two', note: 'two sunbursts: a node only the second has gives its dataIndex to a highlight that names no series -- both '
      + 'series light that index',
    charts: [{ animation: false, series: [
      { type: 'sunburst', center: ['25%', '50%'], radius: [0, '40%'], data: tree },
      { type: 'sunburst', center: ['75%', '50%'], radius: [0, '40%'], data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }, { name: 'x', value: 3 }] }] }], group: null,
    steps: [
      { op: 'action', chart: 0, payload: { type: 'sunburstHighlight', targetNode: 'x' } },
      { op: 'action', chart: 0, payload: { type: 'sunburstUnhighlight' } },
      { op: 'action', chart: 0, payload: { type: 'sunburstHighlight', seriesIndex: 1, targetNode: 'q' } },
    ],
  },
];

// =====================================================================
const TYPES = ['sunbursthighlight', 'sunburstunhighlight', 'highlight', 'downplay', 'updated'];
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const charts = def.charts.map(() => newChart());
  const watch = [];
  const log = [];
  try {
    charts.forEach((c, i) => {
      c.setOption(clone(def.charts[i]));
      frame(c);
      watch.push(watchTooltip(c));
      for (const t of TYPES) c.on(t, e => log.push([i, t, jsonOf(e)]));
      if (def.group) c.group = def.group;
    });
    if (def.group) echarts.connect(def.group);
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      const rec = { op: st.op };
      if (st.chart !== undefined) rec.chart = st.chart;
      const ch = st.chart !== undefined ? charts[st.chart] : null;
      let at = st.at;
      if (st.on) at = pointOn(ch, st.on[0], st.on[1], def.id);
      if (at) rec.at = at;
      if (st.op === 'move' || st.op === 'click' || st.op === 'leave') advanceClock(NOW + STEP_DT);
      const hd = ch ? ch.getZr().handler : null;
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'click') {
        hd.mousedown(rawEvent('mousedown', at[0], at[1]));
        hd.mouseup(rawEvent('mouseup', at[0], at[1]));
        hd.click(rawEvent('click', at[0], at[1]));
      } else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'action') {
        rec.payload = st.payload;
        ch.dispatchAction(clone(st.payload));
      } else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      charts.forEach(frame);
      rec.events = log.slice();
      rec.state = charts.map((c, i) => stateOf(c, watch[i]));
      steps.push(rec);
    }
    return { id: def.id, note: def.note, charts: def.charts.map(o => ({ option: plain(o, 0) })), group: def.group, steps };
  } finally {
    if (def.group) echarts.disconnect(def.group);
    charts.forEach(c => c.dispose());
  }
}

function generate() {
  return CASES.map(runCase);
}

function anchors(cases) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const cs = id => cases.find(c => c.id === id);
  const types = st => st.events.map(e => e[1]).join(',');
  const one = cs('one');
  guard('one-order', types(one.steps[0]) === 'sunbursthighlight,highlight,updated', 'its event, then the highlight it dispatched');
  guard('one-node', one.steps[0].state[0].series[0].e.length === 1, 'one node lit');
  guard('one-blur', one.steps[0].state[0].series[0].b.length > 0, 'focus ancestor blurs the rest');
  guard('one-down', types(one.steps[1]) === 'sunburstunhighlight,downplay,updated' && one.steps[1].state[0].series[0].e.length === 0, 'unhighlight downplays');
  guard('one-whole', one.steps[4].state[0].series[0].e.length > 2, 'no node: the whole series');
  const two = cs('two');
  guard('two-both', two.steps[0].state[0].series[0].e.length === 1 && two.steps[0].state[0].series[1].e.length === 1, 'both series light the index');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mouseout from outside the canvas; each '
    + STEP_DT + ' ms after the last; a frame of every chart after every step.',
  'State e / b: emphasis / blur in currentStates of data.getItemGraphicEl(i) (a symbol: its path), by raw index.',
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
    W, H, seed: SEED, clock: { start: CLOCK0, stepDt: STEP_DT },
    notes: NOTES, cases: g1, guards,
  };
  json1 = JSON.stringify(plain(out, 0), null, 1) + '\n';
  const nul = json1.indexOf('\\u0000');
  must(nul < 0, 'the fixture holds a \\u0000: ' + json1.slice(Math.max(0, nul - 300), nul + 40));
  JSON.parse(json1);
  if (!process.env.ORACLE_ONCE) {
    const g2 = generate();
    json2 = JSON.stringify(plain(Object.assign({}, out, { cases: g2, guards: anchors(g2) }), 0), null, 1) + '\n';
  } else json2 = json1;
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, json1);
const bad = guards.filter(gd => !gd.ok);
guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': ' + gd.what));
const deterministic = json1 === json2;
console.log(g1.length + ' cases, ' + g1.reduce((n, c) => n + c.steps.length, 0) + ' steps; '
  + (guards.length - bad.length) + '/' + guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; '
  + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
