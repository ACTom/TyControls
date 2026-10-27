// Upstream's own answers for fix batch R5-F (spec section 243): a legend
// item's component tooltip. LegendView._createItem: when
// legendItemModel.getModel('tooltip').get('show') (the item's tooltip over
// the legend's, whose default says show false), setTooltipConfig on the
// item's hit rect -- name the item's name, option the item's tooltip
// option, formatterParams {componentType: 'legend', legendIndex, name,
// $vars: ['name']}; TooltipView._showComponentItemTooltip shows it through
// the cascade [that option (content: the name), the legend model's tooltip,
// {formatter: content}] over the global tooltip model (a component item: the
// trigger is not asked), formatTpl over the params ({a} the name), the
// content HTML-encoded, and dispatches showTip; an item without the config
// is no tooltip target (the box another target showed hides).
//
// The harness is toolbox-extra.js' (node, SVG, a fake clock and timers,
// chart._ssr false, env.node off, the tooltip view running, the box
// answering 80 x 40).
//
//   node tools/advchart-oracle/legend-tooltip.js
//
// writes tests/fixtures/advchart-legend-tooltip.json (ORACLE_OUT overrides).
//
// Per step: op ('move' | 'leave' | 'idle'), at, events [[chart, type,
// payload]] (showtip, hidetip), state: {tip {which ('legend:<name>' for a
// legend item's), text, box [x, y]} | null}.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-legend-tooltip.json');

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
const cats = ['a', 'b', 'c', 'd'];
const BARS = { animation: false, xAxis: { type: 'category', data: cats }, yAxis: { min: 0, max: 10 },
  series: [{ type: 'bar', name: 'Alpha', data: [3, 9, 6, 8] }, { type: 'bar', name: 'Beta', data: [2, 4, 7, 5] }] };
const CASES = [
  {
    id: 'lg-tip', note: 'legend.tooltip show: an item\'s tooltip is its name; off the item it hides',
    option: Object.assign({ tooltip: {}, legend: { top: 10, tooltip: { show: true } } }, BARS),
    steps: [
      { op: 'move', at: 'item:Alpha' },
      { op: 'move', at: 'item:Beta' },
      { op: 'move', at: [5, 300] },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'lg-tip-fmt', note: 'legend.tooltip with a template ({a} the name) and a position',
    option: Object.assign({ tooltip: {}, legend: { top: 10, tooltip: { show: true, formatter: 'series {a}!', position: 'bottom' } } }, BARS),
    steps: [
      { op: 'move', at: 'item:Beta' },
      { op: 'leave' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'lg-tip-item', note: 'the legend\'s tooltip off, item Alpha\'s own on with its own template: Alpha shows, Beta does not',
    option: Object.assign({ tooltip: {}, legend: { top: 10, data: [{ name: 'Alpha', tooltip: { show: true, formatter: 'item {a}' } }, 'Beta'] } }, BARS),
    steps: [
      { op: 'move', at: 'item:Alpha' },
      { op: 'move', at: 'item:Beta' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'lg-tip-off', note: 'no legend tooltip (its default): a hover on an item shows nothing',
    option: Object.assign({ tooltip: {}, legend: { top: 10 } }, BARS),
    steps: [
      { op: 'move', at: 'item:Alpha' },
      { op: 'idle', ms: 200 },
    ],
  },
];

// =====================================================================
const TYPES = ['showtip', 'hidetip'];
const val = v => (v === undefined ? null : v);
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  el.updateTransform();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
function itemPoint(chart, name) {
  const lm = chart.getModel().getComponent('legend', 0);
  const v = chart.getViewOfComponentModel(lm);
  const data = lm.getData();
  let at = null;
  v.getContentGroup().eachChild((g, i) => {
    if (at || !data[i] || data[i].get('name') !== name) return;
    const kids = g.childrenRef();
    const hit = kids[kids.length - 1];
    const r = hit.getBoundingRect().clone();
    hit.updateTransform();
    const m = hit.getComputedTransform();
    if (m) r.applyTransform(m);
    at = [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
  });
  if (!at) throw new OracleError('no legend item ' + name);
  return at;
}
function stateOf3(chart, w) {
  let tip = null;
  if (w.view) {
    const c = w.view._tooltipContent;
    if (visible(c)) {
      tip = { which: w.which, text: c.el ? String(c.el.style.text) : null, box: w.box ? w.box.slice() : null };
      if (tip.text && /\{__EC_aUTo_\d+\|/.test(tip.text)) tip.text = 'default';
    }
  }
  return { tip };
}
function watchTooltip2(chart) {
  const w = watchTooltip(chart);
  if (!w.view) return w;
  const content = w.view._tooltipContent;
  const mv = content.moveTo;
  content.moveTo = function (x, y) {
    w.box = [x, y];
    return mv.apply(this, arguments);
  };
  const show = w.view._showTooltipContent;
  w.view._showTooltipContent = function (tooltipModel, html, params) {
    const before = w.which;
    const r = show.apply(this, arguments);
    if (!tooltipModel.get('showContent') || !tooltipModel.get('show')) w.which = before;
    else if (params && params.componentType === 'legend') w.which = 'legend:' + params.name;
    return r;
  };
  return w;
}
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const ch = newChart();
  const log = [];
  let w;
  try {
    ch.setOption(clone(def.option));
    frame(ch);
    w = watchTooltip2(ch);
    for (const t of TYPES) ch.on(t, e => log.push([0, t, jsonOf(e)]));
    const hd = ch.getZr().handler;
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      const rec = { op: st.op };
      let at = st.at;
      if (typeof at === 'string') at = itemPoint(ch, at.slice(5));
      if (at) rec.at = at;
      if (st.op === 'move' || st.op === 'leave') advanceClock(NOW + STEP_DT);
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      frame(ch);
      rec.events = log.slice();
      rec.state = stateOf3(ch, w);
      steps.push(rec);
    }
    return { id: def.id, note: def.note, option: plain(def.option, 0), steps };
  } finally {
    ch.dispose();
  }
}

function generate() {
  return CASES.map(runCase);
}

function anchors(cases) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const cs = id => cases.find(c => c.id === id);
  const t = cs('lg-tip');
  guard('tip-name', t.steps[0].state.tip && t.steps[0].state.tip.which === 'legend:Alpha' && t.steps[0].state.tip.text === 'Alpha', 'the name by default');
  guard('tip-move', t.steps[1].state.tip && t.steps[1].state.tip.which === 'legend:Beta', 'the next item');
  const f = cs('lg-tip-fmt');
  guard('tip-fmt', f.steps[0].state.tip && f.steps[0].state.tip.text === 'series Beta!', 'the template');
  const it = cs('lg-tip-item');
  guard('tip-item', it.steps[0].state.tip && it.steps[0].state.tip.text === 'item Alpha' && it.steps[1].events.some(e => e[1] === 'hidetip') && !it.steps[2].state.tip, 'the item\'s own');
  const o = cs('lg-tip-off');
  guard('tip-off', !o.steps[0].state.tip, 'none by default');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mouseout from outside the canvas; each '
    + STEP_DT + ' ms after the last; a frame of every chart after every step.',
  'TooltipRichContent.getSize answers ' + SIZE.join(' x ') + '.',
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
