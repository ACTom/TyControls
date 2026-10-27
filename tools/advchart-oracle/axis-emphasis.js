// Upstream's own answers for round-5 batch R5-D (2026-10-27): the axis
// pointer's triggerEmphasis -- axisTrigger.ts dispatchHighDownActually: after
// the tooltip's showTip / hideTip, every shown axis whose model says
// triggerEmphasis (the axis' own axisPointer block over the root axisPointer
// component, default true; tooltip.axisPointer's is not one of the fields
// makeAxisPointerModel copies) puts its seriesDataIndices in a map keyed
// seriesIndex|dataIndex; the difference against the last map is dispatched
// as {type: 'downplay', escapeConnect, notBlur, batch} then {type:
// 'highlight', escapeConnect, notBlur, batch} -- through api.dispatchAction,
// so inside the updateAxisPointer action they wait for it (IN_EC_CYCLE).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node with the harness of tooltip-actions.js (SVG renderer,
// ssr: true then chart._ssr = false, env.node off and getDom answering an
// empty object so the tooltip view and the global listeners run, the
// port's xorshift32, a fake clock and timers; every pointer step 10 ms after
// the last; a frame of every chart after every step).
//
//   node tools/advchart-oracle/axis-emphasis.js
//
// writes tests/fixtures/advchart-axis-emphasis.json (ORACLE_OUT overrides).
//
// Conventions as tooltip-actions.js: hex is a double's 16 hex digits; every
// NUL in a string is U+2400; a `from` in a payload is '<view uid>'.
//
// Top level: source, W, H, seed, clock, notes[], cases[], guards[]
//   cases[]  id, note, charts [{option}], group ('g' or null), steps[]:
//     {op: 'move' | 'click' | 'leave' | 'action' | 'idle', chart, at, payload, ms}
//     (`on: [seriesIndex, dataIndex]` resolves to an integer point over that
//     item: `at` is what was used)
//     each step records
//       events  [[chart, type, payload]]: every highlight, downplay,
//               updateaxispointer, showtip, hidetip and updated of every
//               chart, in the order the handlers heard them
//       state   per chart, per series: e [dataIndex...] the items whose
//               element (a symbol's path) is in emphasis, b [...] in blur,
//               t [...] a line's temporary symbol (LineView.highlight),
//               poly the line's polyline states joined ('' none, null no
//               polyline); per chart `tip` the tooltip box shown ('axis:' /
//               'item:' as tooltip-actions.js, null hidden or no tooltip)
//   guards[] anchors on the records; any failure writes nothing
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-emphasis.json');

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
function barLine(tooltip, extra) {
  return Object.assign({
    animation: false,
    tooltip,
    xAxis: { type: 'category', data: cats },
    yAxis: { min: 0, max: 10 },
    series: [{ type: 'bar', data: [3, 5, 2, 6] }, { type: 'line', data: [1, 4, 3, 2] }],
  }, extra || {});
}
const CASES = [
  {
    id: 'default', note: 'an axis tooltip over a bar and a line: each move downplays what the last one lit and highlights its own '
      + 'rows (downplay first), off the grid and on a leave everything goes down; the line\'s symbol and its polyline',
    charts: [barLine({ trigger: 'axis' })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'move', chart: 0, at: [260, 220] },
      { op: 'move', chart: 0, at: [370, 200] },
      { op: 'move', chart: 0, at: [5, 5] },
      { op: 'move', chart: 0, at: [480, 200] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'root-off', note: 'the root axisPointer component says triggerEmphasis: false: no highlight, no downplay, nothing lit',
    charts: [barLine({ trigger: 'axis' }, { axisPointer: { triggerEmphasis: false } })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 80] },
      { op: 'move', chart: 0, at: [370, 80] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'axis-off', note: 'the x axis\' own axisPointer.triggerEmphasis: false over the root\'s true',
    charts: [barLine({ trigger: 'axis' }, { axisPointer: { triggerEmphasis: true }, xAxis: { type: 'category', data: cats, axisPointer: { triggerEmphasis: false } } })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 80] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'tooltip-key', note: 'tooltip.axisPointer.triggerEmphasis: false is not one of the fields the tooltip hands its axes: the rows '
      + 'still light',
    charts: [barLine({ trigger: 'axis', axisPointer: { triggerEmphasis: false } })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 80] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'cross-cat', note: 'a cross over two category axes: the other arm is a category axis too, so it involves the series and its rows '
      + 'light as well; then the same with the y axis\' triggerEmphasis off',
    charts: [
      { animation: false, tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
        xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['p', 'q', 'r'] },
        series: [{ type: 'scatter', symbolSize: 12, data: [['a', 'p'], ['b', 'q'], ['c', 'q'], ['b', 'r']] }] },
      { animation: false, tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
        xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['p', 'q', 'r'], axisPointer: { triggerEmphasis: false } },
        series: [{ type: 'scatter', symbolSize: 12, data: [['a', 'p'], ['b', 'q'], ['c', 'q'], ['b', 'r']] }] },
    ], group: null,
    steps: [
      { op: 'move', chart: 0, at: [300, 205] },
      { op: 'move', chart: 0, at: [460, 205] },
      { op: 'leave', chart: 0 },
      { op: 'move', chart: 1, at: [300, 205] },
      { op: 'leave', chart: 1 },
    ],
  },
  {
    id: 'focus', note: 'emphasis.focus series on the bar: the axis\' highlight says notBlur, so nothing blurs; a hover on the bar element '
      + 'itself (the axis trigger keeps its tooltip) is the element\'s own hover',
    charts: [barLine({ trigger: 'axis' }, { series: [{ type: 'bar', data: [3, 5, 2, 6], emphasis: { focus: 'series' } }, { type: 'line', data: [1, 4, 3, 2], emphasis: { focus: 'series' } }] })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 80] },
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'move', chart: 0, at: [370, 80] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'series-item', note: 'a series whose own tooltip says trigger item takes no part in the axis: its rows never light',
    charts: [barLine({ trigger: 'axis' }, { series: [{ type: 'bar', data: [3, 5, 2, 6] }, { type: 'line', tooltip: { trigger: 'item' }, data: [1, 4, 3, 2] }] })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 80] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'actions', note: 'by hand: updateAxisPointer at a point, showTip by seriesIndex + dataIndex (the axis detour), hideTip (the '
      + 'pointer and its rows stay), updateAxisPointer currTrigger leave',
    charts: [barLine({ trigger: 'axis' })], group: null,
    steps: [
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 250, y: 80 } },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 0, dataIndex: 3 } },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', currTrigger: 'leave' } },
    ],
  },
  {
    id: 'pair', note: 'two connected charts: A\'s highlight says escapeConnect and stays in A; B lights its own rows from the '
      + 'updateAxisPointer it follows',
    charts: [barLine({ trigger: 'axis' }), barLine({ trigger: 'axis' })], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [250, 80] },
      { op: 'move', chart: 0, at: [370, 80] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'no-symbol', note: 'a line with showSymbol false: LineView.highlight builds a temporary symbol for the row and downplay takes '
      + 'it away again',
    charts: [barLine({ trigger: 'axis' }, { series: [{ type: 'line', showSymbol: false, data: [1, 4, 3, 2] }] })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'move', chart: 0, at: [370, 200] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'link', note: 'two grids linked {xAxisIndex: all}: the linked axis\' rows light too, one batch for both',
    charts: [
      { animation: false, tooltip: { trigger: 'axis' }, axisPointer: { link: { xAxisIndex: 'all' } },
        grid: [{ left: 60, right: 40, top: 30, height: 140 }, { left: 60, right: 40, top: 220, height: 140 }],
        xAxis: [{ type: 'category', data: cats }, { type: 'category', data: cats, gridIndex: 1 }],
        yAxis: [{}, { gridIndex: 1 }],
        series: [{ type: 'bar', data: [5, 3, 4, 7] }, { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [1, 6, 2, 8] }] },
    ], group: null,
    steps: [
      { op: 'move', chart: 0, at: [300, 300] },
      { op: 'move', chart: 0, at: [450, 100] },
      { op: 'leave', chart: 0 },
    ],
  },
  {
    id: 'polar', note: 'a polar bar under an axis tooltip: the angle axis\' rows light',
    charts: [
      { animation: false, tooltip: { trigger: 'axis' }, polar: {}, angleAxis: { type: 'category', data: cats }, radiusAxis: { max: 10 },
        series: [{ type: 'bar', coordinateSystem: 'polar', data: [3, 5, 2, 6] }] },
    ], group: null,
    steps: [
      { op: 'move', chart: 0, at: [380, 120] },
      { op: 'move', chart: 0, at: [220, 280] },
      { op: 'leave', chart: 0 },
    ],
  },
];

// =====================================================================
const TYPES = ['highlight', 'downplay', 'updateaxispointer', 'showtip', 'hidetip', 'updated'];
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
  const ev = (st, ch, t) => st.events.filter(e => e[0] === ch && e[1] === t);
  const types = (st, ch) => st.events.filter(e => e[0] === ch).map(e => e[1]);
  const df = cs('default');
  guard('df-first', ev(df.steps[0], 0, 'highlight').length === 1 && ev(df.steps[0], 0, 'downplay').length === 0
    && JSON.stringify(df.steps[0].state[0].series.map(s => s.e)) === '[[1],[1]]', 'the first move lights b in both series');
  const h0 = ev(df.steps[0], 0, 'highlight')[0];
  guard('df-payload', h0 && h0[2].escapeConnect === true && Array.isArray(h0[2].batch) && h0[2].batch.length === 2
    && h0[2].batch.every(b => b.notBlur === true && !('dataIndexInside' in b)), 'escapeConnect, a batch of {seriesIndex, dataIndex} with notBlur');
  guard('df-same-row-quiet', ev(df.steps[1], 0, 'highlight').length === 0 && ev(df.steps[1], 0, 'downplay').length === 0, 'the same rows again: nothing');
  const t2 = types(df.steps[2], 0);
  guard('df-down-then-high', t2.indexOf('downplay') >= 0 && t2.indexOf('downplay') < t2.indexOf('highlight')
    && t2.indexOf('updateaxispointer') > t2.indexOf('highlight') === false, 'downplay before highlight');
  guard('df-off-grid', ev(df.steps[3], 0, 'downplay').length === 1 && df.steps[3].state[0].series.every(s => s.e.length === 0), 'off the grid: all down');
  guard('df-leave', ev(df.steps[5], 0, 'downplay').length === 1, 'a leave downplays');
  const ro = cs('root-off');
  guard('root-off', ro.steps.every(s => ev(s, 0, 'highlight').length === 0 && ev(s, 0, 'downplay').length === 0
    && s.state[0].series.every(x => x.e.length === 0)), 'triggerEmphasis false: nothing');
  const ao = cs('axis-off');
  guard('axis-off', ev(ao.steps[0], 0, 'highlight').length === 0 && ao.steps[0].state[0].series.every(x => x.e.length === 0), 'the axis\' own false wins');
  const tk = cs('tooltip-key');
  guard('tooltip-key-dead', ev(tk.steps[0], 0, 'highlight').length === 1, 'tooltip.axisPointer.triggerEmphasis is not read');
  const cc = cs('cross-cat');
  guard('cross-arm-rows', cc.steps[0].state[0].series[0].e.length >= 2, 'the category cross arm lights its rows too');
  guard('cross-arm-off', cc.steps[3].state[1].series[0].e.length < cc.steps[0].state[0].series[0].e.length, 'the y arm off: fewer rows');
  const fc = cs('focus');
  guard('focus-notblur', fc.steps[0].state[0].series.every(s => s.b.length === 0), 'notBlur: nothing blurs');
  const si = cs('series-item');
  guard('series-item', si.steps[0].state[0].series[1].e.length === 0 && si.steps[0].state[0].series[0].e.length === 1, 'the item series stays down');
  const ac = cs('actions');
  guard('act-uap', ev(ac.steps[0], 0, 'highlight').length === 1, 'updateAxisPointer by hand highlights');
  guard('act-hidetip-keeps', ev(ac.steps[2], 0, 'downplay').length === 0 && ac.steps[2].state[0].series[0].e.length === 1, 'hideTip keeps the rows');
  guard('act-leave', ev(ac.steps[4], 0, 'downplay').length === 1, 'currTrigger leave downplays');
  const pr = cs('pair');
  guard('pair-own', ev(pr.steps[0], 1, 'highlight').length === 1 && ev(pr.steps[0], 0, 'highlight').length === 1
    && pr.steps[0].state[1].series[0].e.length === 1, 'each chart lights its own rows');
  const ns = cs('no-symbol');
  guard('nosym-temp', ns.steps[0].state[0].series[0].t.length === 1 && ns.steps[2].state[0].series[0].t.length === 0, 'a temporary symbol, gone again');
  const lk = cs('link');
  const lh = ev(lk.steps[0], 0, 'highlight')[0];
  guard('link-both', lh && lh[2].batch.length === 2, 'the linked axis\' row is in the batch');
  const pl = cs('polar');
  guard('polar', ev(pl.steps[0], 0, 'highlight').length === 1, 'a polar axis highlights');
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
