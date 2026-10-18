// Upstream's own answers for fix batch F4b: the tooltip shown by a click
// (triggerOn 'click' and 'mousemove|click', item and axis triggers, with
// alwaysShowContent) and TooltipView._keepShow -- the box a re-render leaves
// up: every render of the view (setOption, an action whose update renders
// the components: dataZoom, legend) arms a timeout that shows the tip again
// at the last point (_lastX / _lastY, the axis tooltip's
// _lastDataByCoordSys), unless triggerOn is 'none' or 'click' or a hideTip
// cleared the point; alwaysShowContent keeps the box up through all of it.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node exactly as tooltip-actions.js does (SVG renderer,
// ssr: true then chart._ssr = false, env.node off and getDom answering an
// empty object so TooltipView runs, Math.random the port's xorshift32, Date
// and setTimeout on a fake clock, TooltipRichContent.getSize answering
// 80 x 40).
//
//   node tools/advchart-oracle/tooltip-keep.js
//
// writes tests/fixtures/advchart-tooltip-keep.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions and records: as tooltip-actions.js. One more step:
//     {op: 'setOption', chart, option, notMerge}   chart.setOption(option,
//                                                  notMerge) -- no clock
//   An 'idle' step of 0 ms runs the timeouts due now (the keep timer is a
//   setTimeout without a delay).
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tooltip-keep.json');

const W = 600;
const H = 400;
const SIZE = [80, 40];
// every pointer step is this much later than the last one
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
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
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
function rawEvent(type, x, y, delta) {
  const e = {
    type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {},
  };
  if (type === 'mousewheel') e.zrDelta = delta;
  return e;
}

// ---------- the tooltip view, watched ----------
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function watchTooltip(chart) {
  const view = tooltipView(chart);
  const w = { which: null, anchor: null, box: null, view };
  if (!view) return w;
  const content = view._tooltipContent;
  must(content, 'no tooltip content');
  content.getSize = () => SIZE.slice();
  const mv = content.moveTo;
  content.moveTo = function (x, y) {
    w.box = [x, y];
    return mv.apply(this, arguments);
  };
  const show = view._showTooltipContent;
  view._showTooltipContent = function (tooltipModel, html, params, ticket, x, y) {
    if (Array.isArray(params)) {
      w.which = 'axis:' + params.map(p => p.seriesIndex + '/' + p.dataIndex + '@' + p.axisDim + p.axisIndex).join(',');
    } else if (params && params.componentType === 'series') {
      w.which = 'item:' + params.seriesIndex + ':' + params.dataIndex + (params.dataType ? ':' + params.dataType : '');
    } else if (params) {
      w.which = 'cmpt:' + params.componentType + ':' + params[params.componentType + 'Index'] + ':' + params.name;
    } else w.which = 'none';
    w.anchor = [x, y];
    return show.apply(this, arguments);
  };
  const up = view._updatePosition;
  view._updatePosition = function (tooltipModel, positionExpr, x, y) {
    w.anchor = [x, y];
    return up.apply(this, arguments);
  };
  return w;
}
const visible = c => !!(c && c.el && !c.el.ignore && !c.el.invisible);

function axisKeyOf(ai) {
  return ai.axis.dim + ai.axis.model.componentIndex;
}
function stateOf(chart, w) {
  const ap = chart.getModel().getComponent('axisPointer');
  const info = ap && ap.coordSysAxesInfo;
  const axes = [];
  if (info) {
    for (const key of Object.keys(info.axesInfo)) {
      const ai = info.axesInfo[key];
      const o = ai.axisPointerModel.option;
      const shown = o.status === 'show';
      axes.push({
        key: axisKeyOf(ai), dim: ai.axis.dim, index: ai.axis.model.componentIndex, status: o.status || 'hide',
        value: shown && typeof o.value === 'number' ? hex(o.value) : null, valueText: shown && o.value != null ? text(o.value) : null,
        sdi: shown ? (o.seriesDataIndices || []).map(b => [b.seriesIndex, b.dataIndex, b.dataIndexInside]) : [],
      });
    }
  }
  let tip = null;
  if (w.view) {
    const c = w.view._tooltipContent;
    const vis = visible(c);
    tip = {
      visible: vis,
      show: !!c._show,
      which: vis ? w.which : null,
      anchor: vis && w.anchor ? w.anchor.map(hex) : null,
      anchorText: vis && w.anchor ? w.anchor.map(text) : null,
      box: vis && w.box ? w.box.map(hex) : null,
      boxText: vis && w.box ? w.box.map(text) : null,
    };
  }
  return { axes, tip };
}

// ---------- an integer point over an item (tooltip-finish.js) ----------
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
const newData = { series: [{ data: [4, 6, 3, 7] }, { data: [2, 5, 4, 3] }] };
const CASES = [
  {
    id: 'click-item', note: 'triggerOn click, item: a move shows nothing, a click on a bar shows it, a move leaves it, a click on '
      + 'nothing hides it, a click on a line symbol, a leave',
    charts: [barLine({ trigger: 'item', triggerOn: 'click' })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'click', chart: 0, on: [0, 1] },
      { op: 'move', chart: 0, on: [0, 2] },
      { op: 'click', chart: 0, at: [5, 5] },
      { op: 'idle', ms: 150 },
      { op: 'click', chart: 0, on: [1, 2] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'click-move-item', note: 'triggerOn mousemove|click, item: a move shows, a click on another bar shows that one, a move off '
      + 'hides, a click shows again',
    charts: [barLine({ trigger: 'item', triggerOn: 'mousemove|click' })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'click', chart: 0, on: [0, 3] },
      { op: 'move', chart: 0, at: [5, 5] },
      { op: 'idle', ms: 150 },
      { op: 'click', chart: 0, on: [0, 0] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'click-always', note: 'triggerOn click with alwaysShowContent: a click on nothing and a leave leave the box up',
    charts: [barLine({ trigger: 'item', triggerOn: 'click', alwaysShowContent: true })],
    steps: [
      { op: 'click', chart: 0, on: [0, 1] },
      { op: 'click', chart: 0, at: [5, 5] },
      { op: 'idle', ms: 150 },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
      { op: 'click', chart: 0, on: [0, 2] },
    ],
  },
  {
    id: 'click-axis', note: 'triggerOn click, axis: a click shows the axis tooltip, a move is silent, a click off the grid hides',
    charts: [barLine({ trigger: 'axis', triggerOn: 'click' })],
    steps: [
      { op: 'click', chart: 0, at: [250, 200] },
      { op: 'move', chart: 0, at: [370, 200] },
      { op: 'click', chart: 0, at: [5, 5] },
      { op: 'idle', ms: 150 },
      { op: 'click', chart: 0, at: [480, 300] },
    ],
  },
  {
    id: 'keep-axis', note: 'an axis tooltip and a setOption: the box stays and the keep timer shows the last dataByCoordSys again at '
      + 'the last point (no action); a notMerge setOption the same',
    charts: [barLine({ trigger: 'axis' })],
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
      { op: 'move', chart: 0, at: [370, 200] },
      { op: 'setOption', chart: 0, option: barLine({ trigger: 'axis' }, { series: [{ type: 'bar', data: [1, 2, 3, 4] }] }), notMerge: true },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'keep-item', note: 'an item tooltip and a setOption: the keep timer dispatches updateAxisPointer at the last point and tries '
      + 'the element there again',
    charts: [barLine({ trigger: 'item' })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 150 },
      { op: 'move', chart: 0, on: [1, 3] },
      { op: 'setOption', chart: 0, option: { series: [{}, { data: [2, 5, 4, 9] }] } },
      { op: 'idle', ms: 0 },
    ],
  },
  {
    id: 'keep-datazoom', note: 'an axis tooltip and a dataZoom action (its update renders the view): kept at the last point',
    charts: [barLine({ trigger: 'axis' }, { dataZoom: [{ type: 'inside' }] })],
    steps: [
      { op: 'move', chart: 0, at: [370, 200] },
      { op: 'action', chart: 0, payload: { type: 'dataZoom', start: 25, end: 100 } },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'keep-legend', note: 'an item tooltip over a bar, the legend hides the bars: the keep timer finds nothing at the point and hides',
    charts: [barLine({ trigger: 'item' }, { legend: {}, series: [{ type: 'bar', name: 'B', data: [3, 5, 2, 6] }, { type: 'line', name: 'L', data: [1, 4, 3, 2] }] })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', name: 'B' } },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'keep-highlight', note: 'a highlight is no render of the view: nothing is kept, nothing changes',
    charts: [barLine({ trigger: 'item' })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'highlight', seriesIndex: 0, dataIndex: 3 } },
      { op: 'idle', ms: 0 },
    ],
  },
  {
    id: 'keep-always', note: 'alwaysShowContent, the pointer gone (a hideTip cleared the last point): a setOption leaves the box up '
      + 'and keeps nothing',
    charts: [barLine({ trigger: 'axis', alwaysShowContent: true })],
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 300 },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'keep-click', note: 'triggerOn click: nothing is kept, the box shown stays up',
    charts: [barLine({ trigger: 'item', triggerOn: 'click' })],
    steps: [
      { op: 'click', chart: 0, on: [0, 1] },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'keep-none', note: 'triggerOn none, a showTip by hand: nothing is kept, the box stays up',
    charts: [barLine({ trigger: 'item', triggerOn: 'none' })],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 0, dataIndex: 2 } },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
    ],
  },
  {
    id: 'keep-hidden', note: 'the pointer left and the box went: a setOption keeps nothing',
    charts: [barLine({ trigger: 'item' })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
    ],
  },
  {
    id: 'keep-delay', note: 'showDelay 50: the kept show waits it out again',
    charts: [barLine({ trigger: 'item', showDelay: 50 })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'idle', ms: 60 },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 30 },
      { op: 'idle', ms: 30 },
    ],
  },
  {
    id: 'keep-showtip-point', note: 'a showTip by seriesIndex + dataIndex places at findPointFromSeries: that point is kept',
    charts: [barLine({ trigger: 'item' })],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 1, dataIndex: 2 } },
      { op: 'setOption', chart: 0, option: newData },
      { op: 'idle', ms: 0 },
    ],
  },
  {
    id: 'keep-axis-to-item', note: 'an axis tooltip, then a setOption that makes it an item tooltip: _keepShow drops the last '
      + 'dataByCoordSys (axis only), so the keep timer tries the element at the last point -- the bar, as an item',
    charts: [barLine({ trigger: 'axis' })],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'setOption', chart: 0, option: { tooltip: { trigger: 'item' } } },
      { op: 'idle', ms: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
];
// =====================================================================
const TYPES = ['updateaxispointer', 'showtip', 'hidetip', 'updated'];
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
      if (st.inBox) {
        const w = watch[st.chart];
        must(w.box && visible(w.view._tooltipContent), def.id + ': no box to move into');
        at = [Math.ceil(w.box[0]) + st.inBox[0], Math.ceil(w.box[1]) + st.inBox[1]];
        const hv = ch.getZr().handler.findHover(at[0], at[1]);
        // the richText content's hit list holds its glyph runs only: over
        // its blank part the pointer finds what lies beneath (the port's box
        // is no hover target at all)
        let t = hv.target;
        while (t && t !== w.view._tooltipContent.el) t = t.parent;
        must(!t, def.id + ': the point is over the box\'s text');
      }
      if (at) rec.at = at;
      if (st.op === 'move' || st.op === 'click' || st.op === 'wheel' || st.op === 'leave') advanceClock(NOW + STEP_DT);
      const hd = ch ? ch.getZr().handler : null;
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'click') {
        hd.mousedown(rawEvent('mousedown', at[0], at[1]));
        hd.mouseup(rawEvent('mouseup', at[0], at[1]));
        hd.click(rawEvent('click', at[0], at[1]));
      } else if (st.op === 'wheel') {
        rec.delta = st.delta;
        hd.mousewheel(rawEvent('mousewheel', at[0], at[1], st.delta));
      } else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'action') {
        rec.payload = st.payload;
        ch.dispatchAction(clone(st.payload));
      } else if (st.op === 'setOption') {
        rec.option = plain(st.option, 0);
        rec.notMerge = !!st.notMerge;
        ch.setOption(clone(st.option), !!st.notMerge);
        // a notMerge replaces the models: a new view, watched afresh
        if (tooltipView(ch) !== watch[st.chart].view) {
          rec.newView = true;
          watch[st.chart] = watchTooltip(ch);
        }
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
  const ev = (st, t) => st.events.filter(e => e[0] === 0 && e[1] === t);
  const tip = st => st.state[0].tip;
  const ci = cs('click-item');
  guard('ci-move-silent', ci.steps[0].events.length === 0 && !tip(ci.steps[0]).visible, 'a move shows nothing under triggerOn click');
  guard('ci-click-shows', tip(ci.steps[1]).visible && tip(ci.steps[1]).which === 'item:0:1', 'a click on a bar shows it');
  guard('ci-move-keeps', tip(ci.steps[2]).visible && tip(ci.steps[2]).which === 'item:0:1', 'a move leaves the box');
  guard('ci-click-off-hides', ev(ci.steps[3], 'hidetip').length >= 1 && !tip(ci.steps[4]).visible, 'a click on nothing hides it');
  const cm = cs('click-move-item');
  guard('cm-click-other', tip(cm.steps[1]).which === 'item:0:3', 'mousemove|click: the click shows the bar clicked');
  const ca = cs('click-always');
  guard('ca-stays', tip(ca.steps[2]).visible && tip(ca.steps[4]).visible, 'alwaysShowContent: up after a click on nothing and a leave');
  const cx = cs('click-axis');
  guard('cx-click', tip(cx.steps[0]).visible && tip(cx.steps[0]).which.indexOf('axis:') === 0 && cx.steps[1].events.length === 0, 'an axis click shows, a move is silent');
  const ka = cs('keep-axis');
  guard('ka-stays', tip(ka.steps[1]).visible && ka.steps[2].events.length === 0 && tip(ka.steps[2]).visible
    && tip(ka.steps[2]).anchor[0] === tip(ka.steps[0]).anchor[0], 'setOption: the axis box stays and is shown again at the last point, no action');
  const ki = cs('keep-item');
  guard('ki-reshown', ev(ki.steps[2], 'updateaxispointer').length === 1 && ev(ki.steps[2], 'showtip').length === 1
    && tip(ki.steps[3]).visible && tip(ki.steps[3]).which === 'item:0:1', 'the keep timer: updateAxisPointer and the item shown again');
  const kd = cs('keep-datazoom');
  guard('kd-kept', tip(kd.steps[1]).visible && tip(kd.steps[3]).visible, 'dataZoom: kept');
  const kl = cs('keep-legend');
  guard('kl-hides', tip(kl.steps[1]).visible && ev(kl.steps[2], 'hidetip').length >= 1 && !tip(kl.steps[3]).visible, 'the bars hidden: the kept point finds nothing and hides');
  const kh = cs('keep-highlight');
  guard('kh-nothing', kh.steps[2].events.length === 0 && tip(kh.steps[2]).visible, 'a highlight keeps nothing');
  const kal = cs('keep-always');
  guard('kal-up', tip(kal.steps[3]).visible && kal.steps[4].events.length === 0 && tip(kal.steps[5]).visible, 'alwaysShowContent: up, nothing kept');
  const kc = cs('keep-click');
  guard('kc-up', kc.steps[2].events.length === 0 && tip(kc.steps[2]).visible && tip(kc.steps[3]).visible, 'triggerOn click: nothing kept, the box up');
  const kn = cs('keep-none');
  guard('kn-up', kn.steps[2].events.length === 0 && tip(kn.steps[2]).visible, 'triggerOn none: nothing kept, the box up');
  const kh2 = cs('keep-hidden');
  guard('khd-nothing', kh2.steps[4].events.length === 0 && !tip(kh2.steps[4]).visible, 'the point cleared: nothing kept');
  const kdl = cs('keep-delay');
  guard('kdl-waits', ev(kdl.steps[3], 'showtip').length === 1, 'the kept show dispatches at once');
  const kp = cs('keep-showtip-point');
  guard('kp-kept', ev(kp.steps[2], 'showtip').length === 1 && tip(kp.steps[2]).anchor[0] === tip(kp.steps[0]).anchor[0]
    && tip(kp.steps[2]).which === 'item:0:2', 'the showTip point is kept: what is under it now (the bar) is shown');
  const kti = cs('keep-axis-to-item');
  guard('kti-item', tip(kti.steps[0]).which.indexOf('axis:') === 0 && ev(kti.steps[2], 'updateaxispointer').length === 1
    && ev(kti.steps[2], 'showtip').length === 1 && ev(kti.steps[2], 'showtip')[0][2].dataIndex === 1
    && tip(kti.steps[3]).which === 'item:0:1', 'trigger now item: the last dataByCoordSys is dropped, the bar at the point is shown as an item');
  guard('ka-notmerge-drops', ka.steps[4].newView && !tip(ka.steps[4]).visible && ka.steps[5].events.length === 0,
    'a notMerge setOption: a new view, the box gone, nothing kept');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'setOption steps and action steps move no clock; an idle step of 0 ms fires the timeouts due now.',
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mousewheel / mouseout from outside the canvas; each '
    + STEP_DT + ' ms after the last; a frame of every chart after every step.',
  'TooltipRichContent.getSize answers ' + SIZE.join(' x ') + '; box is the moveTo argument.',
  'The axis pointer\'s own highlight / downplay batches (notBlur, escapeConnect) are not listened to.',
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
    W, H, seed: SEED, clock: { start: CLOCK0, stepDt: STEP_DT }, size: SIZE,
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
