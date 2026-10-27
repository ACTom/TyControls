// Upstream's own answers for round-5 batch R5-D (2026-10-27): what the
// loading effect does to the pointer (src/loading/default.ts). Its mask is a
// Rect over the whole canvas, z 10000 at the effect's zlevel (0 unless the
// config says otherwise), NOT silent: zrender's Handler finds it as the
// hover target over everything else of that layer -- so no element under it
// is hovered, clicked, dragged or given an item tooltip, and its cursor is
// the Element default 'pointer'. The zr-level listeners still hear every
// event: the axis pointer's global listener (updateAxisPointer and an axis
// tooltip), the RoamControllers (an inside dataZoom's wheel), the brush.
//
// The harness is axis-emphasis.js' (node, SVG, a fake clock and timers, the
// tooltip view and listeners enabled, the box answering 80 x 40).
//
//   node tools/advchart-oracle/loading-pointer.js
//
// writes tests/fixtures/advchart-loading-pointer.json (ORACLE_OUT overrides).
//
// Per case: types (the event types listened to). Per step: op ('move' |
// 'click' | 'wheel' | 'drag' (200 ms between its moves) | 'leave' | 'idle' |
// 'show' | 'hide'), events [[chart, type, payload]] (mouseover, mouseout,
// click, mousedown -- {componentType, seriesIndex, dataIndex, name} --,
// legendselectchanged, datazoom, updateaxispointer, showtip, hidetip),
// state: {tip ('axis:' / 'item:' as tooltip-actions.js, null hidden), cursor
// (the last proxy.setCursor of the step, null none), pointers (the shown
// axes' keys), window ([start, end] of dataZoom 0, null none)}.
//
// THE THUMBNAIL'S BOX (cases 'thumb*', appended): ThumbnailView's _bgRect
// and _windowRect are not silent and carry no ecData -- the dispatcher in
// echarts.ts finds no params on them, so they fire no mouse event of their
// own, and as the hover target over a graph node under them (z 10 over the
// series' 2) they keep the node from being hovered, clicked or tipped; the
// cursor is their 'grab'. A thumbnail over a graph on a calendar or a matrix
// (GraphView._getThumbnailInfo: no thumbnail info but on a view) shows its
// box and an empty window, no copy. Their state also records thumb: {box,
// window ([x, y, w, h] of the two rects' shapes), copy (the copy's leaf
// count)}.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-loading-pointer.json');

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
const cats = ['a', 'b', 'c', 'd'];
const BARS = { animation: false, legend: {}, xAxis: { type: 'category', data: cats }, yAxis: { min: 0, max: 10 },
  series: [{ type: 'bar', name: 'B', data: [3, 9, 6, 8] }] };
const CASES = [
  {
    id: 'item', note: 'an item tooltip and a legend: under the mask the bar is not hovered, clicked or tipped, the legend item not '
      + 'clicked; the cursor is the pointer of the mask; after hideLoading all of it again',
    charts: [Object.assign({ tooltip: { trigger: 'item' } }, BARS)],
    steps: [
      { op: 'show' },
      { op: 'move', at: [240, 150] },
      { op: 'click', at: [240, 150] },
      { op: 'move', at: [5, 5] },
      { op: 'click', at: [300, 13] },
      { op: 'hide' },
      { op: 'move', at: [240, 151] },
      { op: 'click', at: [240, 151] },
      { op: 'leave' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'axis', note: 'an axis tooltip: the global listener of the axis pointer still hears the moves under the mask -- the pointer '
      + 'and the axis tooltip show',
    charts: [Object.assign({ tooltip: { trigger: 'axis' } }, BARS)],
    steps: [
      { op: 'show' },
      { op: 'move', at: [240, 150] },
      { op: 'leave' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'zoom', note: 'an inside dataZoom pans and zooms under the mask (its RoamController is zr-level); the handle of a slider is '
      + 'under the mask and does not drag',
    charts: [Object.assign({ dataZoom: [{ type: 'inside', start: 20, end: 80 }, { type: 'slider', start: 20, end: 80 }] }, BARS)],
    // the pointer's actions are not listened to here: whether the inside
    // dataZoom's RoamController hears a wheel before or after the global
    // listener depends on which of them zrender registered last (a render
    // that re-enables the controller re-registers it)
    types: ['mouseover', 'mouseout', 'click', 'mousedown', 'datazoom'],
    steps: [
      { op: 'show' },
      { op: 'wheel', at: [300, 200], delta: 1 },
      { op: 'drag', points: [[200, 200], [260, 200], [320, 200]] },
      { op: 'idle', ms: 500 },
      { op: 'hide' },
      { op: 'wheel', at: [300, 200], delta: -1 },
      { op: 'drag', points: [[200, 200], [260, 200], [320, 200]] },
      { op: 'idle', ms: 500 },
    ],
  },
  {
    id: 'zlevel', note: 'the effect at zlevel 1 is still over the zlevel-0 chart: its mask is the target',
    charts: [Object.assign({ tooltip: { trigger: 'item' } }, BARS)],
    steps: [
      { op: 'show', cfg: { zlevel: 1 } },
      { op: 'move', at: [240, 150] },
      { op: 'hide' },
      { op: 'move', at: [240, 152] },
    ],
  },
  {
    id: 'thumb', note: 'a thumbnail over a graph on a view: the node under its box (460, 360) is not hovered, clicked or tipped, the '
      + 'box fires nothing and its cursor is grab; the node outside it (300, 200) as ever',
    thumb: true,
    charts: [{ animation: false, tooltip: { trigger: 'item' }, thumbnail: {},
      series: [{ type: 'graph', layout: 'none', roam: true, symbolSize: 20,
        data: [{ name: 'p', x: 0, y: 0 }, { name: 'q', x: 50, y: 50 }, { name: 'r', x: 90, y: 90 }, { name: 's', x: 100, y: 100 }],
        links: [{ source: 'p', target: 'q' }] }] }],
    steps: [
      { op: 'move', at: [300, 200] },
      { op: 'move', at: [460, 360] },
      { op: 'click', at: [460, 360] },
      { op: 'move', at: [300, 201] },
      { op: 'click', at: [300, 201] },
      { op: 'leave' },
      { op: 'idle', ms: 200 },
    ],
  },
  {
    id: 'thumb-calendar', note: 'a thumbnail over a graph on a calendar: its box, an empty window, no copy; the box fires nothing',
    thumb: true,
    charts: [{ animation: false, thumbnail: {}, calendar: { range: '2024-01', cellSize: 40, left: 20, top: 20 },
      series: [{ type: 'graph', coordinateSystem: 'calendar', symbolSize: 10,
        data: [['2024-01-02', 1], ['2024-01-10', 2], ['2024-01-30', 3]] }] }],
    steps: [
      { op: 'move', at: [500, 350] },
      { op: 'click', at: [500, 350] },
    ],
  },
  {
    id: 'thumb-matrix', note: 'a thumbnail over a graph on a matrix: the same',
    thumb: true,
    charts: [{ animation: false, thumbnail: { coordinateSystem: 'matrix', coord: [1, 1] },
      matrix: { x: { data: ['a', 'b'] }, y: { data: ['u', 'v'] } },
      series: [{ type: 'graph', coordinateSystem: 'matrix', symbolSize: 10,
        data: [['a', 'u'], ['b', 'v']] }] }],
    steps: [
      { op: 'move', at: [450, 300] },
    ],
  },
];

// =====================================================================
const TYPES = ['mouseover', 'mouseout', 'click', 'mousedown', 'legendselectchanged', 'datazoom', 'updateaxispointer', 'showtip', 'hidetip'];
const MOUSE = ['mouseover', 'mouseout', 'click', 'mousedown'];
function stateOf2(chart, w, cur) {
  const ap = chart.getModel().getComponent('axisPointer');
  const info = ap && ap.coordSysAxesInfo;
  const pointers = [];
  if (info) for (const key of Object.keys(info.axesInfo)) {
    const ai = info.axesInfo[key];
    if (ai.axisPointerModel.option.status === 'show') pointers.push(ai.axis.dim + ai.axis.model.componentIndex);
  }
  const dz = chart.getModel().getComponent('dataZoom', 0);
  let tip = null;
  if (w.view) tip = visible(w.view._tooltipContent) ? w.which : null;
  const rec = { tip, cursor: cur.v, pointers, window: dz ? [dz.option.start, dz.option.end] : null };
  if (thumbOn) rec.thumb = thumbOf(chart);
  return rec;
}
let thumbOn = false;
function thumbOf(chart) {
  const m = chart.getModel().getComponent('thumbnail', 0);
  const v = m ? chart.getViewOfComponentModel(m) : null;
  if (!v || !v._bgRect || !v.group.children().length) return null;
  const xywh = sh => [sh.x, sh.y, sh.width, sh.height];
  let copy = 0;
  const walk = g => g.eachChild(c => { if (c.isGroup) walk(c); else copy++; });
  if (v._targetGroup) walk(v._targetGroup);
  return { box: xywh(v._bgRect.shape), window: xywh(v._windowRect.shape), copy };
}
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  thumbOn = !!def.thumb;
  const ch = newChart();
  const log = [];
  const cur = { v: null };
  let w;
  try {
    ch.setOption(clone(def.charts[0]));
    frame(ch);
    w = watchTooltip(ch);
    for (const t of (def.types || TYPES)) ch.on(t, e => log.push([0, t, MOUSE.indexOf(t) >= 0
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
      if (st.op !== 'idle' && st.op !== 'show' && st.op !== 'hide') advanceClock(NOW + STEP_DT);
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'click') {
        hd.mousemove(rawEvent('mousemove', at[0], at[1]));
        hd.mousedown(rawEvent('mousedown', at[0], at[1]));
        hd.mouseup(rawEvent('mouseup', at[0], at[1]));
        hd.click(rawEvent('click', at[0], at[1]));
      } else if (st.op === 'wheel') {
        rec.delta = st.delta;
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
      } else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'show') {
        if (st.cfg) rec.cfg = st.cfg;
        ch.showLoading(st.cfg ? clone(st.cfg) : undefined);
      } else if (st.op === 'hide') ch.hideLoading();
      else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      frame(ch);
      rec.events = log.slice();
      rec.state = [stateOf2(ch, w, cur)];
      steps.push(rec);
    }
    return { id: def.id, note: def.note, types: def.types || TYPES, charts: def.charts.map(o => ({ option: plain(o, 0) })), steps };
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
  const it = cs('item');
  guard('item-masked', ev(it.steps[1], 'mouseover').length === 0 && it.steps[1].state[0].tip === null, 'no hover, no tip under the mask');
  guard('item-cursor', it.steps[1].state[0].cursor === 'pointer', 'the cursor of the mask');
  guard('item-noclick', ev(it.steps[2], 'click').length === 0, 'no click');
  guard('item-nolegend', ev(it.steps[4], 'legendselectchanged').length === 0, 'no legend click');
  guard('item-after', ev(it.steps[6], 'mouseover').length === 1 && it.steps[6].state[0].tip !== null && ev(it.steps[7], 'click').length === 1, 'back after hideLoading');
  const ax = cs('axis');
  guard('axis-pointer', ev(ax.steps[1], 'updateaxispointer').length === 1 && ax.steps[1].state[0].pointers.length === 1
    && ax.steps[1].state[0].tip !== null, 'the axis pointer and its tooltip under the mask');
  const zm = cs('zoom');
  guard('zoom-wheel', ev(zm.steps[1], 'datazoom').length === 1, 'the inside dataZoom zooms under the mask');
  const zl = cs('zlevel');
  guard('zlevel-over', ev(zl.steps[1], 'mouseover').length === 0, 'zlevel 1 masks');
  guard('zlevel-after', ev(zl.steps[3], 'mouseover').length === 0 && zl.steps[3].state[0].tip !== null, 'hidden: the mask is gone, the last hover is looked for again where it was (no mouseover), the tip shows');
  const th = cs('thumb');
  guard('thumb-node', ev(th.steps[0], 'mouseover').length === 1 && ev(th.steps[0], 'mouseover')[0][2].dataIndex === 1
    && th.steps[0].state[0].tip !== null, 'the node outside the box is hovered and tipped');
  guard('thumb-box', ev(th.steps[1], 'mouseover').length === 0 && ev(th.steps[1], 'mouseout').length === 1
    && th.steps[1].state[0].cursor === 'grab', 'over the box: the node left, nothing hovered, grab');
  guard('thumb-noclick', ev(th.steps[2], 'click').length === 0 && ev(th.steps[2], 'mousedown').length === 0, 'the box clicks nothing');
  guard('thumb-copy', th.steps[0].state[0].thumb && th.steps[0].state[0].thumb.copy > 0, 'a copy on a view');
  guard('thumb-click', ev(th.steps[4], 'click').length === 1, 'the node outside clicks');
  for (const id of ['thumb-calendar', 'thumb-matrix']) {
    const c = cs(id);
    const t = c.steps[0].state[0].thumb;
    guard(id + '-box', t && t.copy === 0 && t.window[2] === 0 && t.window[3] === 0 && t.box[2] > 0, 'the box, no copy, an empty window');
  }
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mouseout from outside the canvas; each '
    + STEP_DT + ' ms after the last; a frame of every chart after every step.',
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
