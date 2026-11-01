// Upstream's own answers for round-5 batch R5-D (2026-10-27): an inside
// dataZoom on a single axis and on a polar (component/dataZoom/roams.ts,
// InsideZoomView.ts). installDataZoomRoamProcessor makes one coordSysRecord
// -- a RoamController -- per coordinate system an inside dataZoom's axes
// live in: a grid, a polar, a singleAxis (the axis model is its own
// coordinate system model); its isInSelf is that system's containPoint
// (Polar: the radius and the angle axis contain pointToCoord of the point;
// Single: the axis contains the point along its orient and the rect the
// other way). getRangeHandlers take the first axis of the dataZoom in that
// system and getDirectionInfo[mainType]: singleAxis -- as a grid's x / y by
// the orient, the single's rect; polar -- pointToCoord of the old and the
// new point, the radius (px) or the angle (degrees) difference over the
// axis' extent [e1 - e0 from e0], the signal -1 / 1 for radius / angle (1 /
// -1 inverse). The batch dispatched through the record's throttle.
//
// The harness is loading-pointer.js' (node, SVG, a fake clock and timers).
//
//   node tools/advchart-oracle/inside-roam-coordsys.js
//
// writes tests/fixtures/advchart-inside-roam-coordsys.json (ORACLE_OUT
// overrides).
//
// Per step: op ('move' | 'wheel' | 'drag' (200 ms between its moves) |
// 'idle'), events [[0, 'datazoom', payload]], state: {cursor (the last
// proxy.setCursor of the step, null none), ranges ([start, end] of every
// inside dataZoom's view range, InsideZoomView.range, in component order)}.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-inside-roam-coordsys.json');

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
const pts = n => Array.from({ length: n }, (_, i) => 5 + i * 90 / (n - 1));
const SINGLE_H = { animation: false,
  singleAxis: { type: 'value', min: 0, max: 100, left: 50, right: 50, top: 150, height: 100 },
  series: [{ type: 'scatter', coordinateSystem: 'singleAxis', symbolSize: 4, data: pts(11) }] };
const SINGLE_V = { animation: false,
  singleAxis: { type: 'value', min: 0, max: 100, orient: 'vertical', position: 'left', inverse: true, left: 250, width: 100, top: 50, bottom: 50 },
  series: [{ type: 'scatter', coordinateSystem: 'singleAxis', symbolSize: 4, data: pts(11) }] };
const POLAR = (angle) => ({ animation: false,
  polar: { center: [300, 200], radius: [40, 160] },
  radiusAxis: { type: 'value', min: 0, max: 100 },
  angleAxis: Object.assign({ type: 'value', min: 0, max: 360 }, angle || {}),
  series: [{ type: 'scatter', coordinateSystem: 'polar', symbolSize: 4, data: [[20, 30], [50, 120], [80, 250]] }] });
const ins = o => Object.assign({ type: 'inside' }, o);
const CASES = [
  {
    id: 'single-h', note: 'a horizontal single axis: a wheel up in it, a drag 100 px left, a wheel above it (nothing), a wheel down',
    charts: [Object.assign({ dataZoom: [ins({ singleAxisIndex: 0, start: 20, end: 80 })] }, SINGLE_H)],
    steps: [
      { op: 'move', at: [280, 200] },
      { op: 'wheel', at: [280, 200], delta: 1 },
      { op: 'idle', ms: 300 },
      { op: 'drag', points: [[280, 200], [230, 200], [180, 200]] },
      { op: 'idle', ms: 300 },
      { op: 'wheel', at: [300, 100], delta: 1 },
      { op: 'idle', ms: 300 },
      { op: 'wheel', at: [120, 210], delta: -1 },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'single-v', note: 'a vertical inverse single axis (position left: a vertical one at the default bottom takes its extent from the rect width): a drag 60 px down, a wheel up near its top',
    charts: [Object.assign({ dataZoom: [ins({ singleAxisIndex: 0, start: 10, end: 60 })] }, SINGLE_V)],
    steps: [
      { op: 'drag', points: [[300, 190], [300, 220], [300, 250]] },
      { op: 'idle', ms: 300 },
      { op: 'wheel', at: [300, 80], delta: 1 },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'polar-radius', note: 'an inside on the radius axis: a wheel up at radius 100, a radial drag 50 px in, a wheel inside the '
      + 'hole (radius 20) and outside the ring (nothing)',
    charts: [Object.assign({ dataZoom: [ins({ radiusAxisIndex: 0, start: 20, end: 80 })] }, POLAR())],
    steps: [
      { op: 'move', at: [400, 200] },
      { op: 'wheel', at: [400, 200], delta: 1 },
      { op: 'idle', ms: 300 },
      { op: 'drag', points: [[400, 200], [375, 200], [350, 200]] },
      { op: 'idle', ms: 300 },
      { op: 'wheel', at: [320, 200], delta: 1 },
      { op: 'wheel', at: [500, 200], delta: 1 },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'polar-angle', note: 'an inside on the angle axis (clockwise): a drag a quarter turn anticlockwise, a wheel at the top',
    charts: [Object.assign({ dataZoom: [ins({ angleAxisIndex: 0, start: 10, end: 70 })] }, POLAR())],
    steps: [
      { op: 'drag', points: [[400, 200], [371, 129], [300, 100]] },
      { op: 'idle', ms: 300 },
      { op: 'wheel', at: [300, 100], delta: 1 },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'polar-both', note: 'insides on both axes of an anticlockwise polar starting at 30 degrees: one batch of two per roam',
    charts: [Object.assign({ dataZoom: [ins({ radiusAxisIndex: 0, start: 10, end: 90 }), ins({ angleAxisIndex: 0, start: 20, end: 80 })] },
      POLAR({ clockwise: false, startAngle: 30 }))],
    steps: [
      { op: 'wheel', at: [380, 140], delta: -1 },
      { op: 'idle', ms: 300 },
      { op: 'drag', points: [[380, 140], [340, 90], [280, 80]] },
      { op: 'idle', ms: 300 },
    ],
  },
];

// =====================================================================
const TYPES = ['datazoom'];
function stateOf2(chart, w, cur) {
  const ranges = [];
  chart.getModel().eachComponent({ mainType: 'dataZoom', subType: 'inside' }, m => {
    const v = chart.getViewOfComponentModel(m);
    ranges.push(v && v.range ? v.range.slice() : null);
  });
  return { cursor: cur.v, ranges };
}
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const ch = newChart();
  const log = [];
  const cur = { v: null };
  try {
    ch.setOption(clone(def.charts[0]));
    frame(ch);
    for (const t of TYPES) ch.on(t, e => log.push([0, t, jsonOf(e)]));
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
      else if (st.op === 'wheel') {
        rec.delta = st.delta;
        hd.mousemove(rawEvent('mousemove', at[0], at[1]));
        const e = rawEvent('mousewheel', at[0], at[1]);
        e.zrDelta = st.delta;
        hd.mousewheel(e);
      } else if (st.op === 'drag') {
        rec.points = st.points;
        const p = st.points;
        hd.mousemove(rawEvent('mousemove', p[0][0], p[0][1]));
        hd.mousedown(rawEvent('mousedown', p[0][0], p[0][1]));
        for (let k = 1; k < p.length; k++) {
          advanceClock(NOW + 200);
          hd.mousemove(rawEvent('mousemove', p[k][0], p[k][1]));
        }
        advanceClock(NOW + 200);
        hd.mouseup(rawEvent('mouseup', p[p.length - 1][0], p[p.length - 1][1]));
      } else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      frame(ch);
      rec.events = log.slice();
      rec.state = [stateOf2(ch, null, cur)];
      steps.push(rec);
    }
    return { id: def.id, note: def.note, charts: def.charts.map(o => ({ option: plain(o, 0) })), steps };
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
  const sh = cs('single-h');
  guard('single-wheel', ev(sh.steps[1], 'datazoom').length === 1, 'a wheel on the single axis zooms');
  guard('single-cursor', sh.steps[0].state[0].cursor === 'grab', 'grab over the single axis');
  guard('single-drag', sh.steps[3].events.length + sh.steps[4].events.length >= 1, 'a drag pans');
  guard('single-out', ev(sh.steps[5], 'datazoom').length === 0 && ev(sh.steps[6], 'datazoom').length === 0, 'nothing above it');
  const pr = cs('polar-radius');
  guard('polar-wheel', ev(pr.steps[1], 'datazoom').length === 1, 'a wheel in the ring zooms');
  guard('polar-out', ev(pr.steps[5], 'datazoom').length === 0 && ev(pr.steps[6], 'datazoom').length === 0
    && ev(pr.steps[7], 'datazoom').length === 0, 'nothing in the hole or outside');
  const pa = cs('polar-angle');
  guard('angle-drag', pa.steps[0].events.length + pa.steps[1].events.length >= 1, 'an angular drag pans');
  const pb = cs('polar-both');
  const sv = cs('single-v');
  guard('single-v-drag', sv.steps[0].events.length >= 1, 'a vertical drag pans');
  guard('both-batch', ev(pb.steps[0], 'datazoom').length === 1 && ev(pb.steps[0], 'datazoom')[0][2].batch.length === 2, 'one batch of two');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown / mouseup / mousewheel (a mousemove to the point first); each '
    + STEP_DT + ' ms after the last; a frame after every step.',
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
