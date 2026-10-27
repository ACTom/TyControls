// Upstream's own answers for round-5 batch R5-D (2026-10-27): the axis
// pointer's handle (axisPointer.handle; BaseAxisPointer._renderHandle,
// CartesianAxisPointer / SingleAxisPointer getHandleTransform and
// updateHandleTransform, modelHelper.fixValue). With handle.show the axis is
// collected whatever its show 'auto' says, its status is 'show' from the
// start (fixValue: the value the option wrote, else the extent's end,
// clamped into the extent) and stays 'show' whatever the pointer does
// (updateModelActually leaves a handle's status alone); the handle -- the
// icon fitted into [-1, 1] and scaled by size / 2, the colour, the axis
// pointer's z -- stands at getTransformedPosition(value) with
// labelMargin = handle.margin and turns with the axis (+ pi where the label
// direction is negative); it is draggable: mousedown dispatches at once,
// each drift moves it along the axis (clamped to the extent) and dispatches
// updateAxisPointer {x, y: the middle of the other extent, axesInfo: [the
// axis]} through a fixRate throttle of handle.throttle ms, and the drag's end
// moves it onto the value (with the pointer's moveAnimation) and dispatches
// hideTip.
//
// The harness is loading-pointer.js' (node, SVG, a fake clock and timers).
//
//   node tools/advchart-oracle/pointer-handle.js
//
// writes tests/fixtures/advchart-pointer-handle.json (ORACLE_OUT overrides).
//
// Per step: op ('move' | 'drag' (200 ms between its moves; 'handle': true
// starts at the handle's centre and `by` are the moves) | 'leave' | 'idle'),
// events [[0, type, payload]] (updateaxispointer, showtip, hidetip), state:
// {cursor (the last proxy.setCursor of the step, null none), handles:
// [{axis, status, value, handle: {x, y, rotation, scaleX, scaleY, fill,
// invisible} | null}]} for every axis model with a handle.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-pointer-handle.json');

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
      w.which = 'item:' + params.seriesIndex + ':' + params.dataIndex + (params.dataType ? ':' + params.dataType : '');
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
const CATS = ['a', 'b', 'c', 'd', 'e'];
const LINE = { type: 'line', data: [3, 7, 2, 5, 6] };
const CASES = [
  {
    id: 'x-category', note: 'a category x axis with a handle: at the extent end from the start; dragged 60 px left (3 drifts); '
      + 'settled on the value; a move in the grid; a leave (still shown)',
    charts: [{ animation: false, xAxis: { type: 'category', data: CATS, axisPointer: { handle: { show: true } } },
      yAxis: { type: 'value' }, series: [LINE] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'drag', handle: { mainType: 'xAxis', index: 0 }, by: [[-20, 0], [-20, 0], [-20, 0]] },
      { op: 'idle', ms: 500 },
      { op: 'move', at: [200, 150] },
      { op: 'idle', ms: 500 },
      { op: 'leave' },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'y-value', note: "a value y axis: handle size [30, 20], margin 30, a colour, throttle 0, the value 4 written; dragged "
      + '50 px up and back 10',
    charts: [{ animation: false, xAxis: { type: 'category', data: CATS },
      yAxis: { type: 'value', min: 0, max: 10, axisPointer: { value: 4, handle: { show: true, size: [30, 20], margin: 30, color: '#ff0000', throttle: 0 } } },
      series: [LINE] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'drag', handle: { mainType: 'yAxis', index: 0 }, by: [[0, -25], [0, -25], [5, 10]] },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'global', note: 'the handle from the axisPointer component (show on its own axes too: x and y both collected); a tooltip '
      + 'on the axis: the drag shows it',
    charts: [{ animation: false, tooltip: { trigger: 'axis' }, axisPointer: { handle: { show: true, margin: 40 } },
      xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', min: 0, max: 10 }, series: [LINE] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'drag', handle: { mainType: 'xAxis', index: 0 }, by: [[-40, 0], [-40, 0]] },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'x-fast', note: 'moves 15 ms apart: the handle follows each, the dispatch runs at once, then at most once per 40 ms '
      + '(fixRate: deferred to the last run + 40 with the latest place)',
    charts: [{ animation: false, xAxis: { type: 'category', data: CATS, axisPointer: { handle: { show: true } } },
      yAxis: { type: 'value' }, series: [LINE] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'drag', handle: { mainType: 'xAxis', index: 0 }, dt: 15, by: [[-30, 0], [-30, 0], [-30, 0], [-30, 0], [-30, 0]] },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'x-over-series', note: 'a big symbol reaching under the axis to the handle: over the handle it is not hovered',
    charts: [{ animation: false, xAxis: { type: 'category', data: CATS, axisPointer: { handle: { show: true } } },
      yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', symbolSize: 120, data: [[4, 0]] }] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'move', at: [495, 300] },
      { op: 'move', at: [495, 370] },
      { op: 'move', at: [495, 301] },
    ],
  },
  {
    id: 'single', note: 'a single axis with a handle: dragged 100 px right',
    charts: [{ animation: false, singleAxis: { type: 'value', min: 0, max: 100, top: 100, height: 100, axisPointer: { handle: { show: true } } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [10, 50, 90] }] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'drag', handle: { mainType: 'singleAxis', index: 0 }, by: [[50, 0], [50, 0]] },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'single-top', note: 'a single axis at the top: the handle above it, turned half round (label direction -1); dragged 60 px left',
    charts: [{ animation: false, singleAxis: { type: 'value', min: 0, max: 100, top: 150, height: 100, position: 'top',
      axisPointer: { handle: { show: true, margin: 30 } } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [10, 50, 90] }] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'drag', handle: { mainType: 'singleAxis', index: 0 }, by: [[-30, 0], [-30, 0]] },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'x-over-series-tip', note: 'the same with an item tooltip: over the handle the symbol under it is no tooltip target',
    charts: [{ animation: false, tooltip: { trigger: 'item' }, xAxis: { type: 'category', data: CATS, axisPointer: { handle: { show: true } } },
      yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', symbolSize: 120, data: [[4, 0]] }] }],
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'move', at: [495, 300] },
      { op: 'move', at: [495, 370] },
      { op: 'idle', ms: 500 },
    ],
  },
];

// =====================================================================
const TYPES = ['updateaxispointer', 'showtip', 'hidetip', 'mouseover', 'mouseout'];
const MOUSE = ['mouseover', 'mouseout'];
function axisView(chart, mainType, index) {
  const m = chart.getModel().getComponent(mainType, index);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function handleOf(chart, mainType, index) {
  const v = axisView(chart, mainType, index);
  return v && v._axisPointer ? v._axisPointer._handle : null;
}
function stateOf2(chart, w, cur) {
  const handles = [];
  for (const mt of ['xAxis', 'yAxis', 'singleAxis']) {
    chart.getModel().eachComponent(mt, m => {
      const ap = m.axisPointerModel || null;
      const v = chart.getViewOfComponentModel(m);
      const ptr = v && v._axisPointer;
      const pm = ptr && ptr._axisPointerModel;
      if (!pm || !pm.get(['handle', 'show'])) return;
      const h = ptr._handle;
      handles.push({ axis: mt + m.componentIndex, status: pm.get('status'), value: pm.get('value'),
        handle: h ? { x: h.x, y: h.y, rotation: h.rotation, scaleX: h.scaleX, scaleY: h.scaleY, fill: h.style.fill,
          invisible: !!h.invisible } : null });
    });
  }
  let tip = null;
  if (w && w.view) tip = visible(w.view._tooltipContent) ? w.which : null;
  return { cursor: cur.v, tip, handles };
}
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const ch = newChart();
  const log = [];
  const cur = { v: null };
  let w;
  try {
    ch.setOption(clone(def.charts[0]));
    frame(ch);
    w = watchTooltip(ch);
    for (const t of TYPES) ch.on(t, e => log.push([0, t, MOUSE.indexOf(t) >= 0
      ? { componentType: e.componentType, seriesIndex: e.seriesIndex == null ? null : e.seriesIndex,
        dataIndex: e.dataIndex == null ? null : e.dataIndex, name: e.name == null ? null : e.name } : jsonOf(e)]));
    const hd = ch.getZr().handler;
    const pr = hd.proxy;
    const set = pr.setCursor;
    pr.setCursor = function (v) { cur.v = v || 'default'; return set && set.apply(this, arguments); };
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      cur.v = null;
      const rec = { op: st.op };
      const at = st.at;
      if (at) rec.at = at;
      if (st.op !== 'idle') advanceClock(NOW + STEP_DT);
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'drag') {
        const h = handleOf(ch, st.handle.mainType, st.handle.index);
        must(h, def.id + ': no handle');
        const p = [[Math.round(h.x), Math.round(h.y)]];
        for (const d of st.by) p.push([p[p.length - 1][0] + d[0], p[p.length - 1][1] + d[1]]);
        rec.points = p;
        hd.mousemove(rawEvent('mousemove', p[0][0], p[0][1]));
        hd.mousedown(rawEvent('mousedown', p[0][0], p[0][1]));
        // a browser paints between moves 200 ms apart: the handle's
        // transform follows its drift before the next hover test
        const dt = st.dt || 200;
        if (st.dt) rec.dt = st.dt;
        for (let k = 1; k < p.length; k++) {
          advanceClock(NOW + dt);
          ch.getZr().storage.getDisplayList(true);
          hd.mousemove(rawEvent('mousemove', p[k][0], p[k][1]));
        }
        advanceClock(NOW + dt);
        ch.getZr().storage.getDisplayList(true);
        hd.mouseup(rawEvent('mouseup', p[p.length - 1][0], p[p.length - 1][1]));
      } else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      frame(ch);
      rec.events = log.slice();
      rec.state = [stateOf2(ch, w, cur)];
      steps.push(rec);
    }
    return { id: def.id, note: def.note, types: TYPES, charts: def.charts.map(o => ({ option: plain(o, 0) })), steps };
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
  const ev = (st, t) => st.events.filter(e => e[1] === t);
  const x = cs('x-category');
  const h0 = x.steps[0].state[0].handles[0];
  guard('x-init', h0 && h0.status === 'show' && h0.value === 4 && h0.handle && !h0.handle.invisible, 'shown at the end from the start');
  guard('x-drag', ev(x.steps[1], 'updateaxispointer').length >= 1, 'the drag dispatches');
  guard('x-leave', x.steps[5].state[0].handles[0].status === 'show', 'a leave keeps it');
  const y = cs('y-value');
  guard('y-init', y.steps[0].state[0].handles[0].value === 4, 'the written value');
  const g = cs('global');
  guard('global-both', g.steps[0].state[0].handles.length === 2, 'both axes from the component');
  guard('global-tip', ev(g.steps[1], 'showtip').length >= 1, 'the tooltip shows on the drag');
  const xf = cs('x-fast');
  guard('fast-throttled', ev(xf.steps[1], 'updateaxispointer').length > 0, 'the fast drag dispatches');
  const xo = cs('x-over-series');
  guard('over-series', ev(xo.steps[0], 'mouseover').length === 0 && ev(xo.steps[1], 'mouseover').length === 1
    && ev(xo.steps[2], 'mouseout').length === 1 && ev(xo.steps[3], 'mouseover').length === 1, 'the handle hides the symbol under it');
  const s = cs('single');
  guard('single-drag', ev(s.steps[1], 'updateaxispointer').length >= 1, 'a single axis drags');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown / mouseup / mouseout; each ' + STEP_DT
    + ' ms after the last; a frame after every step.',
  'The cursor: the last proxy.setCursor of the step (null: none).',
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
