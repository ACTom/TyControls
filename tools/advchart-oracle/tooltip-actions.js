// Upstream's own answers for roadmap batch D8b [Batch 153]: the tooltip and
// the axis pointer driven by ACTIONS -- updateAxisPointer (axisTrigger: the
// point, currTrigger, the payload's axesInfo, findPointFromSeries), showTip
// (manuallyShowTip: dataByCoordSys, seriesIndex + dataIndex / name, the
// axis-trigger detour through updateAxisPointer, x / y, a component by
// index + name), hideTip (manuallyHideTip) and their events -- the pointer's
// two global listeners (axisPointer, itemTooltip) folding a zrender
// mousemove / click / mousewheel / globalout into those actions, and
// echarts.connect carrying them to the other charts of a group.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node: SVG renderer, ssr: true and then chart._ssr = false
// (the browser's model), several chart instances in one process, Math.random
// the port's xorshift32 reseeded per chart, Date and setTimeout replaced by a
// fake clock (as connect-link-batch.js). TooltipView and the global listener
// refuse to run under node: env.node is off for the whole script and getDom
// answers an empty object on the prototype (tooltip-finish.js); the view
// then builds its richText content on the zrender canvas.
// TooltipRichContent.getSize answers 80 x 40 instead of measuring (the port's
// test answers the same through TooltipContentSize), so where the box goes is
// comparable.
//
//   node tools/advchart-oracle/tooltip-actions.js
//
// writes tests/fixtures/advchart-tooltip-actions.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian
//           (NaN 7ff8000000000000); a readable twin beside it (...Text).
//   NUL     every NUL in a string (upstream's auto ids) is written U+2400.
//   from    a `from` string in an event payload (a view uid) is written
//           '<view uid>'.
//
// Top level
//   source, W, H, seed, clock, size [80, 40], notes[], cases[], guards[]
//   cases[]   id, note, charts [{option}], group ('g': every chart joined and
//             connected; null: none), steps[]:
//     {op: 'move', chart, at: [x, y]}      handler.mousemove
//     {op: 'click', chart, at: [x, y]}     handler.mousedown, mouseup, click
//     {op: 'wheel', chart, at: [x, y], delta}  handler.mousewheel
//     {op: 'leave', chart}                 handler.mouseout from outside
//     {op: 'action', chart, payload}       chart.dispatchAction(payload)
//     {op: 'idle', ms}                     the clock only
//     (`on: [seriesIndex, dataIndex]` in a definition is resolved to an
//     integer point over that item; `inBox: [dx, dy]` to the shown box's
//     top-left plus that offset: `at` is what was used)
//     each step records events [[chart, type, payload]] -- every
//     updateaxispointer, showtip, hidetip and updated of every chart, in the
//     order they reached the handlers (the axis pointer's own highlight /
//     downplay batches, `notBlur`, are not listened to) -- and state, per
//     chart: {axes [{key, dim, index, status, value hex + valueText, sdi
//     [[seriesIndex, dataIndex, dataIndexInside]]}] (the axisPointer
//     model's axisInfos, as connect-link-batch.js), tip {visible (the
//     content element is shown), show (TooltipRichContent._show), which
//     ('axis:' + s/d@dimIndex,... | 'item:s:d' | 'cmpt:type:index:name' of
//     the last content shown), anchor [x, y] hex (the point it was placed
//     from), box [x, y] hex (what moveTo was given: the box's top-left)} or
//     null with no tooltip component}
//   guards[]  anchors on the records; any failure writes nothing
//
// Self-checks: every anchor holds; no \u0000; the written JSON parses back;
// two generations give the same bytes.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tooltip-actions.json');

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
const CASES = [
  {
    id: 'axis-pair', note: 'two charts of one shape, an axis tooltip, connected: A\'s pointer and B following through updateAxisPointer '
      + '(B\'s point from findPointFromSeries), then the three actions dispatched by hand on A -- showTip by seriesIndex + dataIndex '
      + '(the axis detour), hideTip, showTip at x / y, updateAxisPointer at x / y, by seriesIndex + dataIndex with axesInfo, a payload '
      + 'position, an escapeConnect showTip that stays in A',
    charts: [barLine({ trigger: 'axis' }), barLine({ trigger: 'axis' })], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'move', chart: 0, at: [370, 150] },
      { op: 'move', chart: 0, at: [5, 5] },
      { op: 'move', chart: 0, at: [130, 300] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
      { op: 'move', chart: 1, at: [480, 100] },
      { op: 'leave', chart: 1 },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 0, dataIndex: 2 } },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 480, y: 250 } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 120, y: 200 } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', seriesIndex: 1, dataIndex: 3, axesInfo: [{ axisDim: 'x', axisIndex: 0, value: 1 }] } },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 0, dataIndex: 1, position: [10, 20] } },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 1, dataIndex: 3, escapeConnect: true } },
      { op: 'action', chart: 1, payload: { type: 'updateAxisPointer', currTrigger: 'leave' } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', axesInfo: [{ axisDim: 'x', axisIndex: 0, value: 2 }] } },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'item-pair', note: 'two charts of one shape, an item tooltip, connected: A over a bar and over a line symbol (B shows the item at '
      + 'findPointFromSeries, the box below the element), off them; showTip by seriesIndex + dataIndex, by name, with a position word; hideTip',
    charts: [barLine({ trigger: 'item' }), barLine({ trigger: 'item' })], group: 'g',
    steps: [
      { op: 'move', chart: 0, on: [0, 1] },
      { op: 'move', chart: 0, on: [1, 2] },
      { op: 'move', chart: 0, at: [5, 5] },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 1, dataIndex: 0 } },
      { op: 'action', chart: 1, payload: { type: 'showTip', seriesIndex: 0, name: 'c' } },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 0, dataIndex: 3, position: 'top' } },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 300, y: 250 } },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'three-shapes', note: 'three connected charts of different shapes: A five categories; B four categories and two series (its own '
      + 'series 0 places the point: past its last row there is no point, so nothing); C two grids -- a pointer in its second names '
      + 'series 1, which A does not have',
    charts: [
      { animation: false, tooltip: { trigger: 'axis' }, xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] }, yAxis: {},
        series: [{ type: 'bar', data: [2, 4, 6, 8, 3] }] },
      { animation: false, tooltip: { trigger: 'axis' }, xAxis: { type: 'category', data: cats }, yAxis: { max: 10 },
        series: [{ type: 'line', data: [9, 1, 5, 2] }, { type: 'bar', data: [2, 3, 4, 5] }] },
      { animation: false, tooltip: { trigger: 'axis' },
        grid: [{ left: 50, right: 50, top: 30, height: 130 }, { left: 50, right: 50, top: 230, height: 130 }],
        xAxis: [{ type: 'category', data: cats }, { type: 'category', data: cats, gridIndex: 1 }],
        yAxis: [{}, { gridIndex: 1 }],
        series: [{ type: 'bar', data: [5, 3, 4, 7] }, { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [1, 6, 2, 8] }] },
    ], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [200, 250] },
      { op: 'move', chart: 0, at: [500, 250] },
      { op: 'move', chart: 2, at: [300, 300] },
      { op: 'move', chart: 2, at: [200, 100] },
      { op: 'leave', chart: 2 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'link-pair', note: 'A two grids linked {xAxisIndex: all}, B one grid, connected: A\'s event lists both axes, B takes x0',
    charts: [
      { animation: false, tooltip: { trigger: 'axis' }, axisPointer: { link: { xAxisIndex: 'all' } },
        grid: [{ left: 60, right: 40, top: 30, height: 140 }, { left: 60, right: 40, top: 220, height: 140 }],
        xAxis: [{ type: 'category', data: cats }, { type: 'category', data: cats, gridIndex: 1 }],
        yAxis: [{}, { gridIndex: 1 }],
        series: [{ type: 'bar', data: [5, 3, 4, 7] }, { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [1, 6, 2, 8] }] },
      barLine({ trigger: 'axis' }),
    ], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [300, 300] },
      { op: 'move', chart: 0, at: [450, 100] },
      { op: 'move', chart: 1, at: [130, 200] },
      { op: 'leave', chart: 1 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'always', note: 'alwaysShowContent: a leave, a hideTip and a move off the grid leave the box up; the pointer goes',
    charts: [barLine({ trigger: 'axis', alwaysShowContent: true })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 300 },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 300 },
      { op: 'move', chart: 0, at: [5, 5] },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'click', note: 'triggerOn click|mousewheel, connected: a move is silent (neither listener hears it), a click on a bar and a '
      + 'wheel drive both, a leave hides',
    charts: [barLine({ trigger: 'axis', triggerOn: 'click|mousewheel' }), barLine({ trigger: 'axis', triggerOn: 'click|mousewheel' })], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'click', chart: 0, on: [0, 3] },
      { op: 'move', chart: 0, at: [130, 330] },
      { op: 'wheel', chart: 0, at: [370, 300], delta: 1 },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'none', note: 'triggerOn none: the pointer drives nothing; showTip and hideTip still work',
    charts: [barLine({ trigger: 'axis', triggerOn: 'none' })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 1, dataIndex: 2 } },
      { op: 'move', chart: 0, at: [480, 200] },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'hideTip' } },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'enterable', note: 'enterable, item: the pointer goes into the box\'s blank corner -- the richText content is hit on its glyph '
      + 'runs only, so the pointer is over the ground beneath and the hide is armed as without enterable',
    charts: [barLine({ trigger: 'item', enterable: true }, { yAxis: { min: 0, max: 40 }, series: [{ type: 'bar', data: [3, 5, 2, 6] }] })], group: null,
    steps: [
      { op: 'move', chart: 0, on: [0, 0] },
      { op: 'move', chart: 0, inBox: [3, 3] },
      { op: 'idle', ms: 300 },
      { op: 'move', chart: 0, at: [500, 80] },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'enterable-off', note: 'the same moves without enterable',
    charts: [barLine({ trigger: 'item' }, { yAxis: { min: 0, max: 40 }, series: [{ type: 'bar', data: [3, 5, 2, 6] }] })], group: null,
    steps: [
      { op: 'move', chart: 0, on: [0, 0] },
      { op: 'move', chart: 0, inBox: [3, 3] },
      { op: 'idle', ms: 300 },
      { op: 'move', chart: 0, at: [500, 80] },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'delay', note: 'showDelay 50 and hideDelay 300 in both charts of a group: the shows wait in A and in B',
    charts: [barLine({ trigger: 'axis', showDelay: 50, hideDelay: 300 }), barLine({ trigger: 'axis', showDelay: 50, hideDelay: 300 })], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'idle', ms: 30 },
      { op: 'move', chart: 0, at: [370, 200] },
      { op: 'idle', ms: 60 },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 120 },
      { op: 'idle', ms: 300 },
    ],
  },
  {
    id: 'cross-pair', note: 'value axes with a cross pointer, connected: the event\'s axesInfo carries both arms; B takes both values',
    charts: [
      { animation: false, tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } }, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { min: 0, max: 100 },
        series: [{ type: 'scatter', data: [[1, 20], [4, 70], [8, 40]] }] },
      { animation: false, tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } }, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { min: 0, max: 100 },
        series: [{ type: 'scatter', data: [[2, 30], [5, 60], [9, 10]] }] },
    ], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [200, 150] },
      { op: 'action', chart: 1, payload: { type: 'showTip', x: 400, y: 250 } },
      { op: 'leave', chart: 0 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'hand', note: 'by hand on one chart: showTip with a written dataByCoordSys, a leave through updateAxisPointer, showTip at a point '
      + 'off the grid, updateAxisPointer with axesInfo alone (no point: everything hides), showTip by seriesIndex alone',
    charts: [barLine({ trigger: 'axis' })], group: null,
    steps: [
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 100, y: 120, dataByCoordSys: [{ coordSysIndex: 0, dataByAxis: [{ axisDim: 'x', axisIndex: 0, value: 2, valueLabelOpt: {}, seriesDataIndices: [{ seriesIndex: 1, dataIndexInside: 2, dataIndex: 2 }] }] }] } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', currTrigger: 'leave', x: 250, y: 200 } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 250, y: 200 } },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 590, y: 390 } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', x: 370, y: 200 } },
      { op: 'action', chart: 0, payload: { type: 'updateAxisPointer', axesInfo: [{ axisDim: 'x', axisIndex: 0, value: 1 }] } },
      { op: 'idle', ms: 150 },
      { op: 'action', chart: 0, payload: { type: 'showTip', seriesIndex: 0 } },
    ],
  },
  {
    id: 'restrict', note: 'B has two x axes in one grid (the top one with its own series) and a third series whose own tooltip says '
      + 'item: it never joins an axis tooltip; A\'s axesInfo names x0 only, so B\'s x1 stays down though the point is in its grid',
    charts: [
      barLine({ trigger: 'axis' }),
      { animation: false, tooltip: { trigger: 'axis' },
        xAxis: [{ type: 'category', data: cats }, { type: 'category', position: 'top', data: ['p', 'q', 'r', 's'] }], yAxis: { max: 10 },
        series: [{ type: 'bar', data: [2, 4, 6, 8] }, { type: 'line', xAxisIndex: 1, data: [5, 3, 7, 1] },
          { type: 'line', tooltip: { trigger: 'item' }, data: [1, 2, 3, 4] }] },
    ], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'move', chart: 1, at: [370, 200] },
      { op: 'leave', chart: 1 },
      { op: 'idle', ms: 150 },
    ],
  },
  {
    id: 'no-tooltip', note: 'A without a tooltip component (the axis pointer\'s triggerOn is then mousemove|click|mousewheel), B with one: '
      + 'A\'s moves and its wheel publish updateAxisPointer and hideTip, B follows',
    charts: [barLine(undefined), barLine({ trigger: 'axis' })], group: 'g',
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'wheel', chart: 0, at: [370, 200], delta: -1 },
      { op: 'leave', chart: 0 },
      { op: 'move', chart: 1, at: [250, 200] },
      { op: 'leave', chart: 1 },
      { op: 'idle', ms: 150 },
    ],
  },
  // [D9-D14 mutation round]
  {
    id: 'short-rows', note: 'a base axis with no row under the pointer: the series stops at b, so over c and d buildPayloadsBySeries '
      + 'finds nothing, showTooltip adds no axis and the pointer\'s action is a hideTip; showTip at x / y there the same',
    charts: [barLine({ trigger: 'axis' }, { series: [{ type: 'bar', data: [3, 5] }] })], group: null,
    steps: [
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'move', chart: 0, at: [480, 200] },
      { op: 'idle', ms: 150 },
      { op: 'move', chart: 0, at: [250, 200] },
      { op: 'action', chart: 0, payload: { type: 'showTip', x: 370, y: 200 } },
      { op: 'idle', ms: 150 },
      { op: 'leave', chart: 0 },
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
  const shown = (st, ch) => st.state[ch].axes.filter(a => a.status === 'show');
  const ap = cs('axis-pair');
  guard('ap-move-a', ev(ap.steps[0], 0, 'updateaxispointer').length === 1 && ev(ap.steps[0], 0, 'showtip').length === 1, 'a move: one updateAxisPointer, one showTip in A');
  guard('ap-b-follows', shown(ap.steps[0], 1).length === 1 && shown(ap.steps[0], 1)[0].valueText === shown(ap.steps[0], 0)[0].valueText
    && ap.steps[0].state[1].tip.visible, 'B\'s pointer and box follow A');
  guard('ap-b-own-point', ap.steps[0].state[1].tip.anchor[0] !== ap.steps[0].state[0].tip.anchor[0], 'B\'s box is at its own series\' point');
  guard('ap-showtip-escape', ev(ap.steps[0], 1, 'showtip').every(e => e[2].escapeConnect === true), 'A\'s showTip is not broadcast: B\'s is its own');
  guard('ap-two-hidetip-b', ev(ap.steps[2], 1, 'hidetip').length >= 2, 'B hides with its own second hideTip');
  guard('ap-axis-detour', ev(ap.steps[9], 0, 'updateaxispointer').length === 1 && ap.steps[9].state[0].tip.which.indexOf('axis:') === 0,
    'showTip by seriesIndex + dataIndex under an axis trigger goes through updateAxisPointer');
  guard('ap-escape-stays', ap.steps[16].events.filter(e => e[0] === 1 && e[1] === 'showtip' && e[2].seriesIndex === 1 && e[2].escapeConnect !== true).length === 0
    && ev(ap.steps[16], 0, 'showtip').length >= 1, 'an escapeConnect showTip stays in A');
  guard('ap-axesinfo-alone-hides', shown(ap.steps[18], 0).length === 0, 'updateAxisPointer with axesInfo and no point hides');
  const ip = cs('item-pair');
  guard('ip-item', ip.steps[0].state[0].tip.which === 'item:0:1' && ip.steps[0].state[1].tip.which === 'item:0:1', 'both show bar b');
  guard('ip-b-bottom', ip.steps[0].state[1].tip.box[1] !== ip.steps[0].state[0].tip.box[1], 'B\'s box below the element, A\'s by the pointer');
  guard('ip-name', ip.steps[5].state[1].tip.which === 'item:0:2', 'showTip by name');
  const ts = cs('three-shapes');
  guard('ts-follow', shown(ts.steps[0], 1).length === 1 && shown(ts.steps[0], 2).length === 1, 'B and C follow A at b');
  guard('ts-no-row', shown(ts.steps[1], 1).length === 0 && shown(ts.steps[1], 2).length === 0, 'A at e: B and C have no row 4 to place the point');
  guard('ts-other-grid', shown(ts.steps[2], 2).length === 1 && shown(ts.steps[2], 2)[0].key === 'x1' && shown(ts.steps[2], 0).length === 0,
    'C in its second grid: A has no series 1');
  const lp = cs('link-pair');
  const lpe = ev(lp.steps[0], 0, 'updateaxispointer')[0];
  guard('lp-both-axes', lpe && lpe[2].axesInfo.length === 2, 'A\'s event lists both linked axes');
  const al = cs('always');
  guard('always-stays', al.steps[2].state[0].tip.visible && al.steps[4].state[0].tip.visible && al.steps[6].state[0].tip.visible, 'the box stays up');
  guard('always-pointer-goes', shown(al.steps[1], 0).length === 0, 'the pointer goes on a leave');
  const ck = cs('click');
  guard('click-move-silent', ck.steps[0].events.length === 0, 'a move publishes nothing under triggerOn click');
  guard('click-click', ev(ck.steps[1], 0, 'updateaxispointer').length === 1 && ck.steps[1].state[1].tip.visible, 'a click drives A and B');
  guard('click-wheel', ev(ck.steps[3], 0, 'updateaxispointer').length === 1, 'a wheel drives the pointer');
  const nn = cs('none');
  guard('none-silent', nn.steps[0].events.length === 0 && nn.steps[3].events.length === 0, 'neither listener reacts');
  guard('none-showtip', nn.steps[1].state[0].tip.visible && nn.steps[4].state[0].tip.visible, 'showTip works, a leave does not hide');
  const en = cs('enterable');
  const eo = cs('enterable-off');
  guard('enter-same', JSON.stringify(en.steps.map(s => s.events)) === JSON.stringify(eo.steps.map(s => s.events))
    && en.steps[1].state[0].tip.visible && !en.steps[2].state[0].tip.visible, 'the blank part of the box: enterable changes nothing');
  const dl = cs('delay');
  guard('delay-waits', !dl.steps[0].state[0].tip.visible && !dl.steps[0].state[1].tip.visible && dl.steps[3].state[0].tip.visible, 'the shows wait out showDelay');
  const cp = cs('cross-pair');
  const cpe = ev(cp.steps[0], 0, 'updateaxispointer')[0];
  guard('cross-both-arms', cpe && cpe[2].axesInfo.length === 2 && shown(cp.steps[0], 1).length === 2, 'both arms travel');
  const hn = cs('hand');
  guard('hand-dbc', hn.steps[0].state[0].tip.which === 'axis:1/2@x0', 'a written dataByCoordSys is shown');
  guard('hand-leave', shown(hn.steps[1], 0).length === 0, 'currTrigger leave hides the pointer');
  const rs = cs('restrict');
  guard('restrict-x0-only', shown(rs.steps[0], 1).length === 1 && shown(rs.steps[0], 1)[0].key === 'x0', 'B takes x0 alone');
  guard('restrict-item-series', shown(rs.steps[1], 1).every(a => a.sdi.every(r => r[0] !== 2)) && shown(rs.steps[1], 1).length === 2,
    'B\'s own pointer: both axes, never the item-triggered series');
  const nt = cs('no-tooltip');
  guard('nt-publishes', ev(nt.steps[0], 0, 'updateaxispointer').length === 1 && ev(nt.steps[1], 0, 'updateaxispointer').length === 1, 'no tooltip, still the pointer\'s action (move and wheel)');
  const sr = cs('short-rows');
  guard('sr-row-shows', sr.steps[0].state[0].tip.visible && ev(sr.steps[0], 0, 'showtip').length === 1, 'over b the series has a row: the box shows');
  guard('sr-no-row-hides', ev(sr.steps[1], 0, 'showtip').length === 0 && ev(sr.steps[1], 0, 'hidetip').length === 1
    && !sr.steps[2].state[0].tip.visible, 'over d it has none: a hideTip, no showTip, the box goes');
  guard('sr-showtip-no-row', ev(sr.steps[4], 0, 'showtip').length === 1 && ev(sr.steps[4], 0, 'hidetip').length >= 1
    && !sr.steps[4].state[0].tip.show && !sr.steps[5].state[0].tip.visible, 'showTip at c: its detour finds no axis to show and hides, the box goes');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
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
