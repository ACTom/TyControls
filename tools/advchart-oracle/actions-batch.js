// Upstream's own answers for fix batch F4b: every action the port dispatches
// as a batch (doDispatchAction's `if (payload.batch)`: each item over the
// payload, the action per item, the update once -- or per item for the
// highlight / select families and the component-direct updates
// ('tooltip:manuallyShowTip', ':updateAxisPointer') -- and one event
// {type, escapeConnect, batch: [each item's event]}); the pending-action
// model (an action dispatched while another runs -- IN_EC_CYCLE -- waits in
// _pendingActions and is flushed after that action's event, before
// `updated`; a dispatch from an event handler runs at once and flushes the
// queue the outer one left; a silent dispatch publishes nothing, flushed
// actions included); and zrender's `rendered` / `finished` on every flush
// that had something to draw.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node as tooltip-actions.js does (SVG renderer, ssr: true
// then chart._ssr = false, env.node off and getDom answering an empty object
// so TooltipView runs, Math.random the port's xorshift32, Date and
// setTimeout on a fake clock, TooltipRichContent.getSize answering 80 x 40).
//
//   node tools/advchart-oracle/actions-batch.js
//
// writes tests/fixtures/advchart-actions-batch.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions: as tooltip-actions.js (hex doubles, NUL written U+2400, a
// `from` string written '<view uid>').
//
// Top level
//   source, W, H, seed, clock, maps [{name, text}] (registered before any
//   chart; the port registers the same text), listen [event types every
//   chart listens to, in this order], notes[], cases[], guards[]
//   cases[]   id, note, option, twin (a batch case: true), steps[]:
//     {op: 'action', payload, silent}   chart.dispatchAction(payload, silent)
//     {op: 'move', at: [x, y]} | {op: 'click', at} | {op: 'leave'}
//                                       zrender's Handler, as tooltip-actions.js
//     {op: 'idle', ms}                  the clock only
//     handlers [{on, times, dispatch}]  registered after the listeners: the
//               first `times` events `on` dispatch `dispatch` on the chart
//     each step records events [[0, type, payload]] in the order the
//     handlers heard them (`rendered` as {elapsedTime}); with `flush` set on
//     the case, a frame after the step is zrender's own: animation.update()
//     (its frame event runs _onframe) and then _flush(false) -- what the
//     browser loop does -- and its rendered / finished are recorded with
//     the step; otherwise the frame is tooltip-actions.js' (no flush).
//   twin      a batch case also dispatches every item one by one -- each
//             item over the outer payload, its batch dropped -- on a second
//             chart of the same option; `sameAsItems` (per step) says
//             whether the two charts then agree: getOption(), every
//             series' selected indices, the tooltip content's visibility
//             and the axisPointer model's shown axes and values.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-actions-batch.json');

const W = 600;
const H = 400;
const SIZE = [80, 40];
const STEP_DT = 10;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

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

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
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

// ---------- the maps ----------
const MAPS = [{
  name: 'mab_sq',
  json: { type: 'FeatureCollection', features: [
    { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] } },
    { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [[[10, 0], [20, 0], [20, 10], [10, 10], [10, 0]]] } },
    { type: 'Feature', properties: { name: 'C' }, geometry: { type: 'Polygon', coordinates: [[[0, 10], [10, 10], [10, 20], [0, 20], [0, 10]]] } },
  ] },
}];
MAPS.forEach(m => { m.text = JSON.stringify(m.json); echarts.registerMap(m.name, m.text); });

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
function frame(chart, flush) {
  if (flush) {
    chart.getZr().animation.update();
    chart.getZr()._flush(false);
  } else {
    chart._onframe();
    chart.renderToSVGString();
  }
}
function rawEvent(type, x, y) {
  return {
    type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {},
  };
}
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function sizeTooltip(chart) {
  const v = tooltipView(chart);
  if (v && v._tooltipContent) v._tooltipContent.getSize = () => SIZE.slice();
}
const visible = c => !!(c && c.el && !c.el.ignore && !c.el.invisible);

// the state two charts are compared by
function signature(chart) {
  const m = chart.getModel();
  const sel = [];
  m.eachSeries(s => sel.push(s.getSelectedDataIndices()));
  const v = tooltipView(chart);
  const ap = m.getComponent('axisPointer');
  const axes = [];
  if (ap && ap.coordSysAxesInfo) {
    for (const key of Object.keys(ap.coordSysAxesInfo.axesInfo)) {
      const o = ap.coordSysAxesInfo.axesInfo[key].axisPointerModel.option;
      axes.push([key, o.status || 'hide', o.status === 'show' ? o.value : null]);
    }
  }
  return JSON.stringify(plain({ option: chart.getOption(), sel, tip: v ? visible(v._tooltipContent) : null, axes }, 0));
}

// ---------- the event types listened to: every action's event the port
// publishes, the refined ones, `updated`, zrender's two ----------
const LISTEN = [
  'highlight', 'downplay', 'select', 'unselect', 'toggleselect', 'selectchanged',
  'globalcursortaken', 'restore', 'pietoggleselect', 'pieselect', 'pieunselect', 'pieselectchanged', 'pieselected', 'pieunselected',
  'geoselectchanged', 'geoselected', 'geounselected', 'georoam',
  'treemapzoomtonode', 'treemaprender', 'treemapmove', 'treemaproottonode', 'graphroam', 'axisareaselected', 'parallelaxisexpand',
  'dragnode', 'sankeyroam', 'sunburstroottonode', 'updateaxispointer', 'datazoom', 'showtip', 'hidetip',
  'brush', 'brushselected', 'brushend', 'timelinechanged', 'timelineplaychanged',
  'legendselectchanged', 'legendselectall', 'legendinverseselect', 'legendselected', 'legendunselected', 'legendscroll',
  'datarangeselected', 'axisbreakchanged', 'updated', 'rendered', 'finished',
];

// =====================================================================
// the cases
// =====================================================================
const cats = ['a', 'b', 'c', 'd'];
const barLine = (tooltip, extra) => Object.assign({
  animation: false, tooltip,
  xAxis: { type: 'category', data: cats }, yAxis: { min: 0, max: 10 },
  series: [{ type: 'bar', data: [3, 5, 2, 6] }, { type: 'line', data: [1, 4, 3, 2] }],
}, extra || {});
const manySeries = n => Array.from({ length: n }, (_, i) => ({ type: 'line', name: 'series ' + i, data: [i, i + 1, i + 2] }));
const tree = [
  { name: 'r', children: [
    { name: 'a', children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 2 }] },
    { name: 'b', children: [{ name: 'b1', value: 3 }, { name: 'b2', value: 5 }] },
    { name: 'c', value: 6 }] },
];
const SN = [{ name: 'n0' }, { name: 'n1' }, { name: 'n2' }, { name: 'n3' }];
const SL = [{ source: 'n0', target: 'n1', value: 5 }, { source: 'n0', target: 'n2', value: 3 }, { source: 'n1', target: 'n3', value: 4 }, { source: 'n2', target: 'n3', value: 2 }];

function batchCase(id, note, option, payload, extra) {
  return Object.assign({ id, note, option, twin: true, steps: [{ op: 'action', payload }] }, extra || {});
}

const CASES = [
  // ---------------- batches ----------------
  batchCase('b-legendscroll', 'legendScroll: one event, each item a copy; escapeConnect in the head',
    { animation: false, legend: { type: 'scroll', width: 200 }, xAxis: { type: 'category', data: ['x', 'y', 'z'] }, yAxis: {}, series: manySeries(12) },
    { type: 'legendScroll', escapeConnect: true, batch: [{ scrollDataIndex: 3 }, { scrollDataIndex: 6 }] }),
  batchCase('b-legendscroll-object', 'a batch that is no list maps to no items: an event with an empty batch',
    { animation: false, legend: { type: 'scroll', width: 200 }, xAxis: { type: 'category', data: ['x', 'y', 'z'] }, yAxis: {}, series: manySeries(12) },
    { type: 'legendScroll', scrollDataIndex: 4, batch: { scrollDataIndex: 2 } }),
  batchCase('b-legendscroll-silent', 'a silent batch publishes nothing',
    { animation: false, legend: { type: 'scroll', width: 200 }, xAxis: { type: 'category', data: ['x', 'y', 'z'] }, yAxis: {}, series: manySeries(12) },
    { type: 'legendScroll', batch: [{ scrollDataIndex: 5 }] }, { steps: [{ op: 'action', silent: true, payload: { type: 'legendScroll', batch: [{ scrollDataIndex: 5 }] } }] }),
  batchCase('b-selectdatarange', 'selectDataRange on a continuous visualMap: the action returns nothing, each item a copy',
    { animation: false, visualMap: { min: 0, max: 10, calculable: true }, xAxis: { type: 'category', data: cats }, yAxis: {},
      series: [{ type: 'bar', data: [3, 5, 2, 6] }] },
    { type: 'selectDataRange', visualMapIndex: 0, batch: [{ selected: [1, 8] }, { selected: [2, 5] }] }),
  batchCase('b-pietoggleselect', 'the legacy pieToggleSelect: its event, then the toggleSelect each item dispatched waits and runs after',
    { animation: false, series: [{ type: 'pie', selectedMode: 'multiple', data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }, { name: 'r', value: 3 }] }] },
    { type: 'pieToggleSelect', seriesIndex: 0, batch: [{ dataIndex: 1 }, { dataIndex: 2 }] }),
  batchCase('b-geotoggleselect', 'geoToggleSelect: each item\'s event is the action\'s result',
    { animation: false, geo: { map: 'mab_sq', selectedMode: 'multiple' } },
    { type: 'geoToggleSelect', geoIndex: 0, batch: [{ name: 'A' }, { name: 'C' }] }),
  batchCase('b-georoam', 'geoRoam: the update is none, the event per item',
    { animation: false, geo: { map: 'mab_sq', roam: true } },
    { type: 'geoRoam', geoIndex: 0, batch: [{ dx: 10, dy: 5 }, { zoom: 2, originX: 300, originY: 200 }] }),
  batchCase('b-sunburst', 'sunburstRootToNode: updateView once, each item a copy',
    { animation: false, series: [{ type: 'sunburst', data: tree }] },
    { type: 'sunburstRootToNode', batch: [{ targetNode: 'a' }, { targetNode: 'b' }] }),
  batchCase('b-treemap', 'treemapRootToNode: each item a copy',
    { animation: false, series: [{ type: 'treemap', data: tree }] },
    { type: 'treemapRootToNode', seriesIndex: 0, batch: [{ targetNodeId: 'a' }, { targetNodeId: 'b' }] }),
  batchCase('b-graphroam', 'graphRoam on a graph with no layout',
    { animation: false, series: [{ type: 'graph', layout: 'none', roam: true, data: [{ name: 'u', x: 0, y: 0 }, { name: 'v', x: 10, y: 10 }], links: [{ source: 'u', target: 'v' }] }] },
    { type: 'graphRoam', seriesIndex: 0, batch: [{ dx: 12, dy: -7 }, { zoom: 2, originX: 150, originY: 100 }] }),
  batchCase('b-dragnode', 'dragNode on a sankey: update once, each item a copy',
    { animation: false, series: [{ type: 'sankey', data: SN, links: SL }] },
    { type: 'dragNode', seriesIndex: 0, batch: [{ dataIndex: 1, localX: 0.25, localY: 0.125 }, { dataIndex: 2, localX: 0.5, localY: 0.75 }] }),
  batchCase('b-takecursor', 'takeGlobalCursor: each item a copy; the update reads the outer payload (an item brushOption alone would leave it none)',
    { animation: false, brush: {}, xAxis: { type: 'category', data: cats }, yAxis: {}, series: [{ type: 'bar', data: [3, 5, 2, 6] }] },
    { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: 'lineX' }, batch: [{ brushOption: { brushType: 'rect' } }, {}] }),
  batchCase('b-brush', 'brush: updateVisual once, each item a copy; the brushSelect its update dispatched comes after',
    { animation: false, brush: { xAxisIndex: 0, brushStyle: { borderWidth: 1, color: 'rgba(120,140,180,0.3)', borderColor: 'rgba(120,140,180,0.8)' } }, xAxis: { type: 'category', data: cats }, yAxis: { min: 0, max: 10 }, series: [{ type: 'bar', data: [3, 5, 2, 6] }] },
    { type: 'brush', batch: [{ areas: [{ brushType: 'lineX', coordRange: [0, 1], xAxisIndex: 0 }] }, { areas: [{ brushType: 'lineX', coordRange: [1, 3], xAxisIndex: 0 }] }] }),
  batchCase('b-brushend', 'brushEnd: no update, each item a copy',
    { animation: false, brush: {}, xAxis: { type: 'category', data: cats }, yAxis: {}, series: [{ type: 'bar', data: [3, 5, 2, 6] }] },
    { type: 'brushEnd', batch: [{ areas: [] }, { areas: [] }] }),
  batchCase('b-timeline', 'timelineChange: the action\'s results, the update once',
    { baseOption: { animation: false, timeline: { data: ['t0', 't1', 't2'] }, xAxis: { type: 'category', data: cats }, yAxis: {} },
      options: [{ series: [{ type: 'bar', data: [1, 2, 3, 4] }] }, { series: [{ type: 'bar', data: [4, 3, 2, 1] }] }, { series: [{ type: 'bar', data: [2, 2, 2, 2] }] }] },
    { type: 'timelineChange', batch: [{ currentIndex: 2 }, { currentIndex: 1 }] }),
  batchCase('b-timelineplay', 'timelinePlayChange: each item a copy',
    { baseOption: { animation: false, timeline: { data: ['t0', 't1', 't2'] }, xAxis: { type: 'category', data: cats }, yAxis: {} },
      options: [{ series: [{ type: 'bar', data: [1, 2, 3, 4] }] }, { series: [{ type: 'bar', data: [4, 3, 2, 1] }] }, { series: [{ type: 'bar', data: [2, 2, 2, 2] }] }] },
    { type: 'timelinePlayChange', batch: [{ playState: true }, { playState: false }] }),
  batchCase('b-axisareaselect', 'axisAreaSelect on two parallel axes: each item a copy',
    { animation: false, parallelAxis: [{ dim: 0, name: 'p' }, { dim: 1, name: 'q' }], series: [{ type: 'parallel', data: [[1, 5], [2, 4], [3, 3], [4, 2]] }] },
    { type: 'axisAreaSelect', batch: [{ parallelAxisIndex: 0, intervals: [[1, 2]] }, { parallelAxisIndex: 1, intervals: [[3, 5]] }] }),
  batchCase('b-axisexpand', 'parallelAxisExpand: each item a copy',
    { animation: false, parallel: { axisExpandable: true, axisExpandWidth: 60, axisExpandCount: 2 },
      parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }, { dim: 3 }, { dim: 4 }], series: [{ type: 'parallel', data: [[1, 2, 3, 4, 5], [5, 4, 3, 2, 1]] }] },
    { type: 'parallelAxisExpand', batch: [{ axisExpandWindow: [0, 120] }, { axisExpandWindow: [60, 180] }] }),
  batchCase('b-axisbreak', 'expandAxisBreak (a refined event): the non-refined event goes to connect only; one axisbreakchanged with every item\'s breaks',
    { animation: false, xAxis: { type: 'category', data: cats }, yAxis: { breaks: [{ start: 60, end: 400, gap: '6%' }, { start: 450, end: 900, gap: '6%' }] },
      series: [{ type: 'bar', data: [20, 420, 950, 55] }] },
    { type: 'expandAxisBreak', yAxisIndex: 0, batch: [{ breaks: [{ start: 60, end: 400 }] }, { breaks: [{ start: 450, end: 900 }] }] }),
  batchCase('b-showtip', 'showTip (tooltip:manuallyShowTip per item): one showtip event; the updateAxisPointer each item dispatched waits',
    barLine({ trigger: 'axis' }),
    { type: 'showTip', batch: [{ seriesIndex: 0, dataIndex: 1 }, { seriesIndex: 0, dataIndex: 2 }] }),
  batchCase('b-showtip-item', 'showTip under an item trigger: each item shows its element',
    barLine({ trigger: 'item' }),
    { type: 'showTip', batch: [{ seriesIndex: 0, dataIndex: 1 }, { seriesIndex: 1, dataIndex: 3 }] }),
  batchCase('b-hidetip', 'hideTip: one hidetip event; the hideTip each _hide dispatched waits',
    barLine({ trigger: 'axis' }),
    { type: 'hideTip', batch: [{}, {}] }, { pre: [{ op: 'move', at: [250, 200] }] }),
  batchCase('b-updateaxispointer', 'updateAxisPointer (an update of its own per item): its event the outputPayloads; the showTips wait',
    barLine({ trigger: 'axis' }),
    { type: 'updateAxisPointer', batch: [{ x: 250, y: 200 }, { x: 370, y: 200 }] }),
  // ---------------- the pending actions ----------------
  { id: 'p-legacy', note: 'pieToggleSelect alone: its event, its update, then the toggleSelect it dispatched (pending) with selectchanged',
    option: { animation: false, series: [{ type: 'pie', selectedMode: 'single', data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }] }] },
    steps: [{ op: 'action', payload: { type: 'pieToggleSelect', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'p-nested', note: 'a handler of the first hidetip dispatches a legendToggleSelect: it runs at once and its own flush takes the '
      + 'hideTip the outer one left waiting, before its updated',
    option: barLine({ trigger: 'axis' }, { legend: {}, series: [{ type: 'bar', name: 'B', data: [3, 5, 2, 6] }, { type: 'line', name: 'L', data: [1, 4, 3, 2] }] }),
    handlers: [{ on: 'hidetip', times: 1, dispatch: { type: 'legendToggleSelect', name: 'L' } }],
    steps: [{ op: 'move', at: [250, 200] }, { op: 'action', payload: { type: 'hideTip' } }, { op: 'idle', ms: 150 }] },
  { id: 'p-silent', note: 'a silent hideTip: nothing published, the pending hideTip either',
    option: barLine({ trigger: 'axis' }),
    steps: [{ op: 'move', at: [250, 200] }, { op: 'action', silent: true, payload: { type: 'hideTip' } }, { op: 'idle', ms: 150 }] },
  { id: 'p-handler-later', note: 'a handler of legendselectchanged dispatches a highlight: it runs at once, between the outer event and its updated',
    option: barLine(undefined, { legend: {}, series: [{ type: 'bar', name: 'B', data: [3, 5, 2, 6] }, { type: 'line', name: 'L', data: [1, 4, 3, 2] }] }),
    handlers: [{ on: 'legendselectchanged', times: 1, dispatch: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } }],
    steps: [{ op: 'action', payload: { type: 'legendToggleSelect', name: 'L' } }] },
  // ---------------- rendered / finished ----------------
  { id: 'r-hover', note: 'zrender flushes when something was marked: a hover that changes a state, a tooltip box that moves; '
      + 'nothing changed, nothing flushed', flush: true,
    option: barLine({ trigger: 'item' }),
    steps: [
      { op: 'idle', ms: 10 },
      { op: 'move', on: [0, 1] },
      { op: 'move', on: [0, 1], nudge: [1, 1] },
      { op: 'move', at: [5, 5] },
      { op: 'idle', ms: 150 },
      { op: 'move', at: [6, 6] },
      { op: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
      { op: 'action', payload: { type: 'legendToggleSelect', name: 'nothing' } },
      { op: 'action', payload: { type: 'hideTip' } },
      { op: 'leave' },
    ] },
  { id: 'r-plain', note: 'no tooltip: a move inside the same bar marks nothing', flush: true,
    option: barLine(undefined),
    steps: [
      { op: 'move', on: [0, 1] },
      { op: 'move', on: [0, 1], nudge: [1, 1] },
      { op: 'move', at: [5, 5] },
      { op: 'move', at: [6, 6] },
      { op: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } },
    ] },
];

// ---------- an integer point over an item ----------
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
function pointOn(chart, seriesIndex, dataIndex, where) {
  const els = chart.getZr().storage.getDisplayList(true);
  const h = chart.getZr().handler;
  for (const el of els) {
    const d = dispatcherOf(el);
    if (!d || d.seriesIndex !== seriesIndex || d.dataIndex !== dataIndex || d.dataType) continue;
    const r = el.getBoundingRect().clone();
    if (el.transform) r.applyTransform(el.transform);
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

// each item over the payload, its batch dropped (doDispatchAction's map)
function itemsOf(payload) {
  const outer = Object.assign({}, payload);
  delete outer.batch;
  const list = Array.isArray(payload.batch) ? payload.batch : [];
  return list.map(it => Object.assign({}, outer, it));
}

function runStep(chart, st, log, flush, rec) {
  let at = st.at;
  if (st.on) {
    at = pointOn(chart, st.on[0], st.on[1], 'step');
    if (st.nudge) at = [at[0] + st.nudge[0], at[1] + st.nudge[1]];
  }
  if (at) rec.at = at;
  if (st.op === 'move' || st.op === 'click' || st.op === 'leave') advanceClock(NOW + STEP_DT);
  const hd = chart.getZr().handler;
  if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
  else if (st.op === 'click') {
    hd.mousedown(rawEvent('mousedown', at[0], at[1]));
    hd.mouseup(rawEvent('mouseup', at[0], at[1]));
    hd.click(rawEvent('click', at[0], at[1]));
  } else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
  else if (st.op === 'action') {
    rec.payload = plain(st.payload, 0);
    if (st.silent) rec.silent = true;
    chart.dispatchAction(clone(st.payload), st.silent ? true : undefined);
  } else if (st.op === 'idle') {
    rec.ms = st.ms;
    advanceClock(NOW + st.ms);
  } else throw new OracleError('op ' + st.op);
  frame(chart, flush);
}

function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const chart = newChart();
  const twin = def.twin ? newChart() : null;
  const log = [];
  try {
    chart.setOption(clone(def.option));
    frame(chart, def.flush);
    sizeTooltip(chart);
    if (twin) {
      twin.setOption(clone(def.option));
      frame(twin, false);
      sizeTooltip(twin);
    }
    for (const t of LISTEN) {
      chart.on(t, e => {
        // the axis pointer's triggerEmphasis batches (notBlur): the port
        // does not dispatch them (spec section 192), so they are not heard
        if ((t === 'highlight' || t === 'downplay') && e.batch && e.batch.some(b => b && b.notBlur)) return;
        log.push([0, t, jsonOf(e)]);
      });
    }
    for (const h of def.handlers || []) {
      let left = h.times;
      chart.on(h.on, () => {
        if (left <= 0) return;
        left--;
        chart.dispatchAction(clone(h.dispatch));
      });
    }
    for (const st of def.pre || []) {
      runStep(chart, st, [], def.flush, {});
      if (twin) runStep(twin, st, [], false, {});
    }
    log.length = 0;
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      const rec = { op: st.op };
      runStep(chart, st, log, def.flush, rec);
      rec.events = log.slice();
      if (twin && st.op === 'action') {
        for (const it of itemsOf(st.payload)) {
          twin.dispatchAction(clone(it), st.silent ? true : undefined);
          frame(twin, false);
        }
        rec.items = itemsOf(st.payload).map(it => plain(it, 0));
        rec.sameAsItems = signature(chart) === signature(twin);
      }
      steps.push(rec);
    }
    return { id: def.id, note: def.note, option: plain(def.option, 0), twin: !!def.twin, flush: !!def.flush,
      handlers: (def.handlers || []).map(h => plain(h, 0)), pre: (def.pre || []).map(p => plain(p, 0)), steps };
  } finally {
    chart.dispose();
    if (twin) twin.dispose();
  }
}

function generate() {
  return CASES.map(def => {
    try {
      return runCase(def);
    } catch (e) {
      if (e instanceof OracleError) throw e;
      throw new OracleError(def.id + ': ' + (e.stack || e).toString().split(String.fromCharCode(10)).slice(0, 3).join(' / '));
    }
  });
}

function anchors(cases) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const cs = id => cases.find(c => c.id === id);
  const evs = (c, i, t) => c.steps[i].events.filter(e => e[1] === t);
  const types = (c, i) => c.steps[i].events.map(e => e[1]).join(',');
  const ls = cs('b-legendscroll');
  guard('ls-one-event', evs(ls, 0, 'legendscroll').length === 1 && evs(ls, 0, 'legendscroll')[0][2].batch.length === 2
    && evs(ls, 0, 'legendscroll')[0][2].escapeConnect === true && evs(ls, 0, 'updated').length === 1, 'legendScroll: one event of two items, escapeConnect, one updated');
  guard('ls-same', ls.steps[0].sameAsItems, 'the batch ends where the items one by one do');
  const lo = cs('b-legendscroll-object');
  guard('lo-empty', evs(lo, 0, 'legendscroll').length === 1 && evs(lo, 0, 'legendscroll')[0][2].batch.length === 0, 'a batch that is no list: no items');
  const lsi = cs('b-legendscroll-silent');
  guard('silent-nothing', lsi.steps[0].events.length === 0, 'a silent batch publishes nothing');
  const pt = cs('b-pietoggleselect');
  guard('pt-order', types(pt, 0) === 'pietoggleselect,toggleselect,selectchanged,toggleselect,selectchanged,brushselected,updated',
    'pieToggleSelect batch: its event, then the two pending toggleSelects, then updated');
  const ab = cs('b-axisbreak');
  guard('ab-refined-once', evs(ab, 0, 'axisbreakchanged').length === 1 && evs(ab, 0, 'axisbreakchanged')[0][2].breaks.length === 2,
    'one axisbreakchanged with both items\' breaks');
  const tl = cs('b-timeline');
  guard('tl-results', evs(tl, 0, 'timelinechanged').length === 1 && evs(tl, 0, 'timelinechanged')[0][2].batch[0].currentIndex === 2, 'timelineChange: each entry the action\'s result');
  const st = cs('b-showtip');
  guard('st-one', evs(st, 0, 'showtip').filter(e => e[2].batch).length === 1, 'one batched showtip');
  guard('st-pending-after', st.steps[0].events.findIndex(e => e[1] === 'updateaxispointer') > st.steps[0].events.findIndex(e => e[1] === 'showtip' && e[2].batch),
    'the updateAxisPointers the items dispatched come after the batch event');
  const ua = cs('b-updateaxispointer');
  guard('ua-results', evs(ua, 0, 'updateaxispointer').length === 1 && evs(ua, 0, 'updateaxispointer')[0][2].batch[1].axesInfo[0].value === 2,
    'updateAxisPointer: entries are the outputPayloads');
  const pl = cs('p-legacy');
  guard('pl-order', types(pl, 0) === 'pietoggleselect,toggleselect,selectchanged,brushselected,updated', 'the legacy action\'s own event first, the select after');
  const pn = cs('p-nested');
  guard('pn-order', types(pn, 1) === 'hidetip,legendselectchanged,hidetip,brushselected,updated,updated', 'the nested dispatch flushes the outer\'s pending hideTip before its updated');
  const ps = cs('p-silent');
  guard('ps-nothing', ps.steps[1].events.length === 0, 'silent: nothing');
  const ph = cs('p-handler-later');
  guard('ph-order', types(ph, 0) === 'legendselectchanged,highlight,brushselected,updated,updated', 'a handler\'s dispatch runs at once');
  const rh = cs('r-hover');
  guard('rh-idle-none', evs(rh, 0, 'rendered').length === 0, 'nothing marked: no rendered');
  guard('rh-hover', evs(rh, 1, 'rendered').length === 1 && evs(rh, 1, 'finished').length === 1, 'a hover: rendered and finished');
  guard('rh-box-moves', evs(rh, 2, 'rendered').length === 1, 'the box moved with the pointer: rendered');
  const rp = cs('r-plain');
  guard('rp-same-bar', evs(rp, 1, 'rendered').length === 0, 'no tooltip, the same bar: nothing flushed');
  guard('rp-elapsed', evs(rp, 0, 'rendered').every(e => e[2].elapsedTime === 0), 'elapsedTime on the frozen clock');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'The axis pointer\'s own highlight / downplay batches (notBlur) are not recorded.',
  'Pointer steps: zrender Handler mousemove / mousedown + mouseup + click / mouseout from outside; each ' + STEP_DT + ' ms after the last.',
  'A frame after every step; a `flush` case\'s frames are zrender\'s own loop (animation.update, then _flush(false)) and record rendered / finished.',
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
    W, H, seed: SEED, clock: { start: CLOCK0, stepDt: STEP_DT }, size: SIZE,
    maps: MAPS.map(m => ({ name: m.name, text: m.text })), listen: LISTEN,
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
