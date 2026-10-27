// Upstream's own answers for fix batch R5-I (spec section 243b): a timeline
// tick as a data item. SliderTimelineView._renderAxisTick: where the tick's
// item model says tooltip (the item's over the timeline's, whose default is
// {trigger: 'item'}), getECData(tick).dataIndex is the tick's value and its
// dataModel the timeline model -- TooltipView._showSeriesItemTooltip shows
// it through [the item model, the timeline model] over the global tooltip
// (trigger item asked), its content timelineModel.formatTooltip: a nameValue
// with no name, the axis label; a formatter over getDataParams; showTip
// dispatched. The chart's mouse events on it carry the timeline's
// getDataParams (componentType 'timeline'). Where the item says no tooltip
// the tick is no data item: no box, no data events.
//
// The harness is legend-tooltip.js' (toolbox-extra.js': node, SVG, a fake
// clock and timers, chart._ssr false, env.node off, the tooltip view
// running, the box answering 80 x 40).
//
//   node tools/advchart-oracle/timeline-tick.js
//
// writes tests/fixtures/advchart-timeline-tick.json (ORACLE_OUT overrides).
//
// Per step: op ('move' | 'leave' | 'click' | 'idle'), at, events [[chart,
// type, payload]] (showtip, hidetip; mouseover, mouseout, click with the
// params' componentType, componentSubType, componentIndex, name, dataIndex,
// value, seriesIndex), state: {tip {which ('timeline:<dataIndex>'), text,
// box [x, y]} | null}.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-timeline-tick.json');

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
const TL = (tl, extra) => Object.assign({ animation: false, tooltip: {},
  timeline: Object.assign({ axisType: 'category', data: ['2001', '2002', '2003'], bottom: 10, left: 40, right: 40 }, tl || {}),
  xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {}, series: [{ type: 'bar', data: [3, 5] }] }, extra || {});
const CASES = [
  {
    id: 'tl-tip', note: "the timeline's default tooltip ({trigger: 'item'}): a tick shows its label, the mouse events carry the timeline's params",
    option: TL(),
    steps: [
      { op: 'move', at: 'tick:1' },
      { op: 'move', at: 'tick:2' },
      { op: 'move', at: [300, 100] },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'tl-tip-fmt', note: 'a template over the params: {b} the name, {c} the value',
    option: TL({ tooltip: { formatter: 'year {b} / {c}' } }),
    steps: [
      { op: 'move', at: 'tick:1' },
      { op: 'leave' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'tl-tip-off', note: 'timeline.tooltip false: the ticks are no data items -- no box, no data events',
    option: TL({ tooltip: false }),
    steps: [
      { op: 'move', at: 'tick:1' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'tl-tip-item', note: "the timeline's tooltip off, the second item's own on with a template",
    option: TL({ tooltip: false, data: ['2001', '2002', { value: '2003', tooltip: { formatter: 'item {b}' } }] }),
    steps: [
      { op: 'move', at: 'tick:1' },
      { op: 'move', at: 'tick:2' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'tl-click', note: "a click on a tick: the chart's click with the timeline's params (the change follows)",
    option: TL(),
    steps: [
      { op: 'move', at: 'tick:2' },
      { op: 'click', at: 'tick:2' },
    ],
  },
];

// =====================================================================
const TYPES = ['showtip', 'hidetip'];
const MOUSE = ['mouseover', 'mouseout', 'click'];
const pick = e => ({ componentType: e.componentType, componentSubType: e.componentSubType, componentIndex: e.componentIndex,
  name: e.name, dataIndex: e.dataIndex, value: e.value, seriesIndex: e.seriesIndex });
function tickPoint(chart, i) {
  const m = chart.getModel().getComponent('timeline', 0);
  const v = chart.getViewOfComponentModel(m);
  const el = v._tickSymbols[i];
  must(el, 'no tick ' + i);
  el.updateTransform();
  const r = el.getBoundingRect().clone();
  const tm = el.getComputedTransform();
  if (tm) r.applyTransform(tm);
  return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
}
function stateOf3(chart, w) {
  let tip = null;
  if (w.view) {
    const c = w.view._tooltipContent;
    if (visible(c)) {
      tip = { which: w.which, text: c.el ? String(c.el.style.text) : null, box: w.box ? w.box.slice() : null };
      if (tip.text && /\{__EC_aUTo_\d+\|/.test(tip.text)) {
        tip.text = 'default';
        // the default content's one value: the tick's axis label
        const m = chart.getModel().getComponent('timeline', 0);
        const v = m && chart.getViewOfComponentModel(m);
        if (v && /^timeline:/.test(w.which)) tip.plain = v._axis.scale.getLabel({ value: +w.which.slice(9) });
      }
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
    else if (params && params.componentType === 'timeline') w.which = 'timeline:' + params.dataIndex;
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
    for (const t of MOUSE) ch.on(t, e => log.push([0, t, jsonOf(pick(e))]));
    const hd = ch.getZr().handler;
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      const rec = { op: st.op };
      let at = st.at;
      if (typeof at === 'string') at = tickPoint(ch, +at.slice(5));
      if (at) rec.at = at;
      if (st.op === 'move' || st.op === 'leave' || st.op === 'click') advanceClock(NOW + STEP_DT);
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'click') {
        hd.mousedown(rawEvent('mousedown', at[0], at[1]));
        hd.mouseup(rawEvent('mouseup', at[0], at[1]));
        hd.click(rawEvent('click', at[0], at[1]));
      }
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
  const t = cs('tl-tip');
  guard('tip-label', t.steps[0].state.tip && t.steps[0].state.tip.which === 'timeline:1', 'a tick shows its tooltip');
  guard('tip-event', t.steps[0].events.some(e => e[1] === 'mouseover' && e[2].componentType === 'timeline' && e[2].dataIndex === 1), 'its mouseover carries the timeline params');
  const o = cs('tl-tip-off');
  guard('tip-off', !o.steps[0].state.tip && !o.steps[0].events.some(e => e[1] === 'mouseover'), 'no tooltip, no data event');
  const c = cs('tl-click');
  guard('click', c.steps[1].events.some(e => e[1] === 'click' && e[2].componentType === 'timeline'), 'a click');
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
