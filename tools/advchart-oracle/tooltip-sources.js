// Upstream's own answers for round-5 batch R5-D (2026-10-27): where a
// tooltip's option comes from besides the global component --
//   * a coordinate system's own `tooltip`: TooltipView's item cascade is
//     [data item, series, seriesModel.coordinateSystem.model] over the
//     global model (grid, polar, singleAxis, parallel and geo have a model
//     there; calendar, radar and matrix keep theirs private, so theirs is
//     never read), and axisPointer/modelHelper.collectAxesInfo reads
//     coordSysModel.getModel('tooltip', globalTooltipModel) for show, trigger,
//     axisPointer.type / axis and the fields makeAxisPointerModel copies
//   * showTip's payload.tooltip at x / y (manuallyShowTip): a proxy rect at
//     the point whose tooltipConfig is {name: null, option: payload.tooltip},
//     shown as a component item ([tooltipOpt, {formatter: content}] over the
//     global; a string is content and formatter)
//   * tooltipOption: updateAxisPointer hands it to the showTip it
//     dispatches, and _showAxisTooltip builds its model as [tooltipOption]
//     over the global one
//
// The harness is axis-emphasis.js' (tooltip-actions.js'): node, SVG, the
// tooltip view and listeners enabled, a fake clock, the box answering 80 x 40.
//
//   node tools/advchart-oracle/tooltip-sources.js
//
// writes tests/fixtures/advchart-tooltip-sources.json (ORACLE_OUT overrides).
//
// Per step: events [[chart, type, payload]] (updateaxispointer, showtip,
// hidetip); state per chart: axes [{key, dim, index, status, type, label,
// valueText}] (the axisPointer model's axisInfos: shown, the pointer's type,
// its label shown) and tip {visible, which ('axis:' / 'item:' / 'cmpt:' /
// 'proxy'), text (the content element's text; 'default' for the default
// markup, whose style names are random), anchor, box (hex and text)}.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tooltip-sources.json');

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
    // a show that returns at once (showContent or show false) changes nothing
    if (!tooltipModel.get('showContent') || !tooltipModel.get('show')) return show.apply(this, arguments);
    if (Array.isArray(params)) {
      w.which = 'axis:' + params.map(p => p.seriesIndex + '/' + p.dataIndex + '@' + p.axisDim + p.axisIndex).join(',');
    } else if (params && params.componentType === 'series') {
      w.which = 'item:' + params.seriesIndex + ':' + params.dataIndex + (params.dataType ? ':' + params.dataType : '');
    } else if (params && params.componentType) {
      w.which = 'cmpt:' + params.componentType + ':' + params[params.componentType + 'Index'] + ':' + params.name;
    } else w.which = 'proxy';
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

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
function axisKeyOf(ai) {
  return ai.axis.dim + ai.axis.model.componentIndex;
}
// the axisPointer model's axes: shown or not, the pointer's type
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
        type: ai.axisPointerModel.get('type'), label: !!ai.axisPointerModel.get(['label', 'show']),
        valueText: shown && o.value != null ? text(o.value) : null,
      });
    }
  }
  let tip = null;
  if (w.view) {
    const c = w.view._tooltipContent;
    const vis = visible(c);
    tip = {
      visible: vis,
      which: vis ? w.which : null,
      // the default markup (its style names are random per tooltip) is 'default'
      text: vis && c.el ? (c.el.style.text == null ? null
        : /\{__EC_aUTo_\d+\|/.test(String(c.el.style.text)) ? 'default' : String(c.el.style.text)) : null,
      anchor: vis && w.anchor ? w.anchor.map(hex) : null,
      anchorText: vis && w.anchor ? w.anchor.map(text) : null,
      box: vis && w.box ? w.box.map(hex) : null,
      boxText: vis && w.box ? w.box.map(text) : null,
    };
  }
  return { axes, tip };
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
const GRIDS = [{ left: 40, width: 220, top: 40, bottom: 40 }, { left: 340, width: 220, top: 40, bottom: 40 }];
function twoGrids(tooltip, grids, extra) {
  return Object.assign({
    animation: false,
    tooltip,
    grid: grids,
    xAxis: [{ type: 'category', data: cats }, { type: 'category', data: cats, gridIndex: 1 }],
    yAxis: [{ min: 0, max: 10 }, { min: 0, max: 10, gridIndex: 1 }],
    series: [{ type: 'bar', data: [3, 5, 2, 6] }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [4, 2, 7, 1] }],
  }, extra || {});
}
const CASES = [
  {
    id: 'grid-item', note: 'an item tooltip: grid 0 writes a formatter of its own, which the cascade [item, series, coordinate '
      + 'system] reaches before the global one; grid 1 does not; a series formatter over the grid\'s',
    charts: [twoGrids({ trigger: 'item', formatter: 'G {b}' }, [Object.assign({ tooltip: { formatter: 'grid0 {b} {c}' } }, GRIDS[0]), GRIDS[1]])],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'move', chart: 0, on: [1, 2] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'grid-series', note: 'the series\' own formatter wins over its grid\'s',
    charts: [twoGrids({ trigger: 'item' }, [Object.assign({ tooltip: { formatter: 'grid0 {b}' } }, GRIDS[0]), GRIDS[1]],
      { series: [{ type: 'bar', data: [3, 5, 2, 6], tooltip: { formatter: 'S {b}' } }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [4, 2, 7, 1] }] })],
    steps: [
      { op: 'move', chart: 0, on: [0, 3] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'grid-trigger', note: 'a global item trigger, grid 0 says trigger axis: grid 0 collects its tooltip axes (the pointer and an axis '
      + 'tooltip there), and an item over grid 0\'s bar shows nothing of its own (its cascade says axis); grid 1 stays item',
    charts: [twoGrids({ trigger: 'item', formatter: 'G {b}' }, [Object.assign({ tooltip: { trigger: 'axis', formatter: 'A {b0}' } }, GRIDS[0]), GRIDS[1]])],
    steps: [
      { op: 'move', chart: 0, at: [100, 60] },
      { op: 'move', chart: 0, on: [0, 2] },
      { op: 'move', chart: 0, on: [1, 2] },
      { op: 'move', chart: 0, at: [400, 60] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'grid-cross', note: 'a global axis trigger, grid 1 asks for a cross through its tooltip.axisPointer: both of its axes show, with '
      + 'labels; grid 0 keeps a line on its base axis',
    charts: [twoGrids({ trigger: 'axis' }, [GRIDS[0], Object.assign({ tooltip: { axisPointer: { type: 'cross' } } }, GRIDS[1])])],
    steps: [
      { op: 'move', chart: 0, at: [100, 150] },
      { op: 'move', chart: 0, at: [450, 150] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'grid-shadow', note: 'the grid\'s tooltip.axisPointer.type shadow is one of the fields its axes take',
    charts: [twoGrids({ trigger: 'axis' }, [Object.assign({ tooltip: { axisPointer: { type: 'shadow' } } }, GRIDS[0]), GRIDS[1]])],
    steps: [
      { op: 'move', chart: 0, at: [100, 150] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'grid-hidden', note: 'grid 1 says tooltip.show false: no tooltip axes there (no pointer, no box); its item cascade says show '
      + 'false as well',
    charts: [twoGrids({ trigger: 'axis' }, [GRIDS[0], Object.assign({ tooltip: { show: false } }, GRIDS[1])])],
    steps: [
      { op: 'move', chart: 0, at: [100, 60] },
      { op: 'move', chart: 0, at: [450, 60] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'polar', note: 'a global item trigger and polar.tooltip.trigger axis: the polar\'s angle axis takes the pointer',
    charts: [{ animation: false, tooltip: { trigger: 'item' }, polar: { tooltip: { trigger: 'axis', formatter: 'P {b0}' } },
      angleAxis: { type: 'category', data: cats }, radiusAxis: { max: 10 },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [3, 5, 2, 6] }] }],
    steps: [
      { op: 'move', chart: 0, at: [380, 120] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'single', note: 'a scatter on a single axis: singleAxis.tooltip formatter for its items',
    charts: [{ animation: false, tooltip: { trigger: 'item', formatter: 'G {c}' }, singleAxis: { type: 'value', min: 0, max: 10, tooltip: { formatter: 'S1 {c}' } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', symbolSize: 14, data: [2, 5, 8] }] }],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'calendar', note: 'a calendar has no model on its coordinate system (Calendar._model): calendar.tooltip is not in the cascade',
    charts: [{ animation: false, tooltip: { trigger: 'item', formatter: 'G {c}' }, calendar: { range: '2024-01', cellSize: 30, tooltip: { formatter: 'CAL {c}' } },
      series: [{ type: 'scatter', coordinateSystem: 'calendar', symbolSize: 14, data: [['2024-01-10', 3], ['2024-01-17', 5]] }] }],
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'proxy', note: 'showTip with payload.tooltip at x / y: a proxy element carrying it as a component tooltip -- a string (content '
      + 'and formatter), an object with a formatter, an object with content only (its content is the formatter level), an object '
      + 'with neither (the global formatter), a position from the option; without x / y it falls to the next branch',
    charts: [twoGrids({ trigger: 'item', formatter: 'G {b}' }, GRIDS)],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 300, y: 200, tooltip: 'just text' } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 120, y: 100, tooltip: { formatter: 'F here' } } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 450, y: 300, tooltip: { content: 'C here' } } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 200, y: 250, tooltip: { padding: 3 } } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 200, y: 250, tooltip: { formatter: 'P', position: [10, 20] } } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 200, y: 250, tooltip: { formatter: 'B', position: 'bottom' } } },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'showTip', tooltip: 'no point' } },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'tooltip-option', note: 'updateAxisPointer with a tooltipOption: it rides into the showTip and is the top level of the axis '
      + 'tooltip\'s model (its formatter over the global one; showContent false shows nothing); a showTip with dataByCoordSys and one',
    charts: [twoGrids({ trigger: 'axis', formatter: 'G {b0}' }, GRIDS)],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 100, y: 150, tooltipOption: { formatter: 'O {b0} {c0}' } } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 160, y: 150 } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 450, y: 150, tooltipOption: { showContent: false } } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 100, y: 120, tooltipOption: { formatter: 'D {b0}' },
        dataByCoordSys: [{ coordSysIndex: 0, dataByAxis: [{ axisDim: 'x', axisIndex: 0, value: 2, valueLabelOpt: {}, seriesDataIndices: [{ seriesIndex: 0, dataIndexInside: 2, dataIndex: 2 }] }] }] } },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 150 },
    ],
  },
];

// =====================================================================
const TYPES = ['updateaxispointer', 'showtip', 'hidetip'];
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
  const tip = (c, k) => cs(c).steps[k].state[0].tip;
  const shown = (c, k) => cs(c).steps[k].state[0].axes.filter(a => a.status === 'show');
  guard('grid-item-own', tip('grid-item', 0).text === 'grid0 b 5', 'grid 0 formatter');
  guard('grid-item-global', tip('grid-item', 1).text === 'G c', 'grid 1: the global formatter');
  guard('grid-series', tip('grid-series', 0).text === 'S d', 'the series formatter over its grid one');
  guard('grid-trigger-axis', shown('grid-trigger', 0).length === 1 && tip('grid-trigger', 0).visible && tip('grid-trigger', 0).which.indexOf('axis:') === 0,
    'grid 0 takes an axis tooltip');
  guard('grid-trigger-item', tip('grid-trigger', 2).which === 'item:1:2' && tip('grid-trigger', 2).text === 'G c', 'grid 1 an item tooltip');
  guard('grid-cross', shown('grid-cross', 1).length === 2 && shown('grid-cross', 1).every(a => a.label) && shown('grid-cross', 0).length === 1,
    'a cross in grid 1 only');
  guard('grid-shadow', shown('grid-shadow', 0).length === 1 && shown('grid-shadow', 0)[0].type === 'shadow', 'the grid shadow');
  guard('grid-hidden', shown('grid-hidden', 1).length === 0 && cs('grid-hidden').steps[1].events.some(e => e[1] === 'hidetip') && !tip('grid-hidden', 3).visible, 'nothing in grid 1');
  guard('polar-axis', shown('polar', 0).length === 1 && tip('polar', 0).which === 'axis:0/0@angle0' && tip('polar', 0).text === 'default', 'the polar axis tooltip (its formatter is not the axis tooltip one)');
  guard('single', tip('single', 0).text === 'S1 5', 'singleAxis.tooltip');
  guard('calendar-not', tip('calendar', 0).text === 'G 2024-01-17,5', 'calendar.tooltip is not read');
  guard('proxy-string', tip('proxy', 0).text === 'just text' && tip('proxy', 0).which === 'proxy', 'a string');
  guard('proxy-formatter', tip('proxy', 1).text === 'F here', 'a formatter');
  guard('proxy-content', tip('proxy', 2).text === 'C here', 'content');
  guard('proxy-neither', tip('proxy', 3).text === 'G {b}', 'the global formatter, no name');
  guard('proxy-position', tip('proxy', 4).boxText[0] === '10' && tip('proxy', 4).boxText[1] === '20', 'its own position');
  guard('proxy-no-point', !tip('proxy', 8).visible, 'no x / y: nothing');
  guard('topt-formatter', tip('tooltip-option', 0).text === 'O b 5', 'tooltipOption formatter');
  guard('topt-gone', tip('tooltip-option', 1).text === 'G c', 'the next one without');
  guard('topt-nocontent', tip('tooltip-option', 2).visible && tip('tooltip-option', 2).text === 'G c' && tip('tooltip-option', 2).which === 'axis:0/2@x0', 'showContent false: the content is not touched, the last one stays');
  guard('topt-dbc', tip('tooltip-option', 3).text === 'D c', 'a showTip with dataByCoordSys');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mouseout from outside the canvas; each '
    + STEP_DT + ' ms after the last; a frame of every chart after every step.',
  'TooltipRichContent.getSize answers ' + SIZE.join(' x ') + '; box is the moveTo argument.',
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
