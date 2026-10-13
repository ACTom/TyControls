// Upstream's own answers for roadmap batch D8 [Batch 141]: axisPointer.link
// (+ its mapper), echarts.connect / disconnect / chart.group (the action and
// event broadcast between charts of a group), batch actions (dispatchAction
// with `batch`: the items, the one update, the one event), the silent
// dispatch, and getConnectedDataURL (the layout of several charts' images).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node: SVG renderer, ssr: true and then chart._ssr = false
// (the browser's model, as mouse-events.js), several chart instances in one
// process, Math.random the port's xorshift32 reseeded per chart, Date and
// setTimeout replaced by a fake clock (as datazoom-interact.js: the clock only
// moves between steps, due timers fire in due order). Pointer steps go to
// zrender's own Handler ({zrX, zrY, zrDelta, which 1}) and are followed by one
// frame (chart._onframe() + renderToSVGString()) of every chart.
//
//   node tools/advchart-oracle/connect-link-batch.js
//
// writes tests/fixtures/advchart-connect-link-batch.json (ORACLE_OUT
// overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex     a double as the 16 hex digits of its IEEE-754 bits, big-endian
//           (NaN 7ff8000000000000); a readable twin beside it (...Text).
//   NUL     upstream's auto ids hold NULs ('\0series\00\00'); in this file
//           every NUL in a string is written U+2400 (the port's test maps
//           its own payloads the same way before comparing). The fixture holds
//           no \u0000.
//   from    a `from` string in an event payload (a view uid) is written
//           '<view uid>'.
//
// Top level
//   source, W, H, seed, clock, api, notes[]
//   revertMap   {eventType: actionType}: echarts' connectionEventRevertMap,
//               read through chart.makeActionFromEvent for every event type
//               the connect listener is registered for (an instance's
//               _messageCenter handlers registered after the published-event
//               forwarders), in registration order
//   link[]      one per case: id, note, option (as fed, mappers as '@Name'),
//               steps[]: {at: [x, y] | 'leave', axes[], tip, highlights[],
//               mapper[]}
//     axes[]    every axisInfo of the axisPointer model's coordSysAxesInfo in
//               collection order: {key ('x0', 'y1', 'angle0', ...), dim, index,
//               status ('show' | 'hide'), value (hex | null) + valueText,
//               sdi [[seriesIndex, dataIndex, dataIndexInside]] (the option's
//               seriesDataIndices after the step; [] when hidden)}
//     tip       the last showtip / hidetip event of the step: null (none),
//               'hide', or [{cs ('grid0'), axes: [{dim, index, value hex +
//               valueText, sdi}]}] (showTip's dataByCoordSys)
//     highlights  every highlight / downplay event of the step:
//               {type, items [[seriesIndex, dataIndex]]}
//     mapper    every mapper call of the step: {fn, value hex + valueText,
//               src {axisDim, axisIndex, axisName, axisId}, tar {...}}
//   connect[]   one per case: id, note, charts [{option, w, h}], steps[]:
//     {op: 'group', chart, value}            chart.group = value (null: delete)
//     {op: 'connect', group}                 echarts.connect(group) -> ret
//     {op: 'connectList', charts: [i...]}    echarts.connect([charts]) -> ret
//     {op: 'disconnect', group}
//     {op: 'action', chart, payload, silent} chart.dispatchAction(payload,
//                                            silent ? true : undefined)
//     {op: 'wheel', chart, x, y, delta}      handler.mousewheel on that chart
//     {op: 'idle', ms}                       the clock only
//     each step records: ret (connect's return, a group id; 'g_<n>' ids are
//     written 'g_<auto>'), events [[chart, type, payload]] in the order they
//     reached the handlers (every chart listens to every event type the
//     connect listener is registered for plus selectchanged,
//     axisbreakchanged and updated), state [per chart: {legend [selected map
//     JSON], dz [[start hex, end hex] getPercentRange per dataZoom], sel
//     [{s: seriesIndex, idx: selected raw indices} per series the legend
//     shows], tl (timeline currentIndex | null), brush [areas per brush]}]
//   batch[]     the same shape as connect[] (one chart, or two connected)
//   exportCases[]  getConnectedDataURL: id, rects [{left, top, w, h}] (each
//               chart's getBoundingClientRect, stubbed), group (connected or
//               not), opts, chart (the one asked), and what upstream did:
//               self (getDataURL instead: the group is not connected), renders
//               [{chart, opts}] (renderToCanvas calls, each returning a stub
//               canvas of the chart's rect x pixelRatio, floored), canvas
//               {width, height} (the raw values the target canvas was given,
//               hex + Text), ops [{op: 'fill', color, rect [x, y, w, h]} |
//               {op: 'image', chart, x, y, w, h} (hex + Text)], mime
//   guards[]    anchors on the records; any failure writes nothing
//
// Self-checks: every anchor holds; the connected layout's transcription
// (below) reproduces every export case; no \u0000; the written JSON parses
// back; two generations give the same bytes.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-connect-link-batch.json');

const W = 600;
const H = 400;

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
    // a makeInner store a view left on a shared payload object
    if (/^__ec_inner_\d+$/.test(k)) continue;
    const s = k === 'from' && typeof v[k] === 'string' ? '<view uid>' : plain(v[k], depth + 1);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
// what JSON.stringify would carry of an event: undefined keys dropped
const jsonOf = ev => (ev === undefined ? null : plain(JSON.parse(JSON.stringify(ev)), 0));

function newChart(w, h) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w || W, height: h || H });
  chart._ssr = false;
  return chart;
}
// TooltipView and the axis pointer's global listener refuse to run under node:
// env.node off for the whole script, getDom an empty object on the prototype
// (tooltip-finish.js)
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

// ---------- the mappers (the port registers the same names) ----------
let MAPPER_LOG = null;
const MAPPERS = {
  Double: v => v * 2,
  Half: v => v / 2,
  Shift: v => v + 1,
  Hundred: v => v * 100,
};
function mapperParam(p) {
  return { axisDim: p.axisDim, axisIndex: p.axisIndex, axisName: plain(p.axisName, 0), axisId: plain(p.axisId, 0) };
}
function withMappers(option) {
  const o = clone(option);
  const ap = o.axisPointer;
  if (ap && ap.link) {
    const links = Array.isArray(ap.link) ? ap.link : [ap.link];
    for (const l of links) {
      if (typeof l.mapper === 'string' && l.mapper[0] === '@') {
        const name = l.mapper.slice(1);
        const fn = MAPPERS[name];
        must(fn, 'no mapper ' + name);
        l.mapper = function (v, src, tar) {
          const r = fn(v, src, tar);
          if (MAPPER_LOG) MAPPER_LOG.push({ fn: name, value: hex(v), valueText: text(v), src: mapperParam(src), tar: mapperParam(tar) });
          return r;
        };
      }
    }
  }
  return o;
}

function rawEvent(type, x, y, delta) {
  const e = {
    type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {},
  };
  if (type === 'mousewheel') e.zrDelta = delta;
  return e;
}

// =====================================================================
// axisPointer.link
// =====================================================================
const cats = ['a', 'b', 'c', 'd', 'e'];
const LINK_CASES = [
  {
    id: 'link-all', note: 'grid-multiple: two grids stacked, category x, link as an OBJECT {xAxisIndex: all} (the preprocessor wraps it)',
    option: {
      animation: false, tooltip: { trigger: 'axis' }, axisPointer: { link: { xAxisIndex: 'all' } },
      grid: [{ left: 60, right: 40, top: 30, height: 140 }, { left: 60, right: 40, top: 220, height: 140 }],
      xAxis: [{ type: 'category', data: cats }, { type: 'category', data: cats, gridIndex: 1 }],
      yAxis: [{}, { gridIndex: 1 }],
      series: [{ type: 'bar', data: [5, 3, 4, 7, 2] }, { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [1, 6, 2, 8, 3] }],
    },
    steps: [[120, 100], [300, 100], [450, 300], [559, 250], [300, 200], 'leave', [61, 360]],
  },
  {
    id: 'link-id-mapper', note: 'three grids side by side, value x axes with ids a / b / c; [{xAxisId: [a, b], mapper: @Double}]: a pointer in a puts b at twice the value and back; c is on its own',
    option: {
      animation: false, tooltip: { trigger: 'axis' },
      axisPointer: { link: [{ xAxisId: ['a', 'b'], mapper: '@Double' }] },
      grid: [{ left: 40, width: 140, top: 40, bottom: 40 }, { left: 230, width: 140, top: 40, bottom: 40 }, { left: 420, width: 140, top: 40, bottom: 40 }],
      xAxis: [{ id: 'a', type: 'value', min: 0, max: 10 }, { id: 'b', type: 'value', gridIndex: 1, min: 0, max: 20 }, { id: 'c', type: 'value', gridIndex: 2, min: 0, max: 10 }],
      yAxis: [{}, { gridIndex: 1 }, { gridIndex: 2 }],
      series: [
        { type: 'line', data: [[1, 3], [3, 5], [6, 2], [9, 4]] },
        { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [[2, 1], [7, 6], [12, 3], [18, 5]] },
        { type: 'scatter', xAxisIndex: 2, yAxisIndex: 2, data: [[2, 2], [5, 5], [8, 1]] },
      ],
    },
    steps: [[60, 200], [110, 200], [300, 200], [355, 200], [500, 200]],
  },
  {
    id: 'link-name-first', note: 'by axis NAME and the first group that matches: [{xAxisName: left}, {xAxisName: [right, left], mapper: @Shift}] -- left is taken by group 0, so group 1 holds right alone and nothing links; [{xAxisIndex: [0, 2]} ...] in the next case',
    option: {
      animation: false, tooltip: { trigger: 'axis' },
      axisPointer: { link: [{ xAxisName: 'left' }, { xAxisName: ['right', 'left'], mapper: '@Shift' }] },
      grid: [{ left: 40, width: 220, top: 40, bottom: 60 }, { left: 330, width: 220, top: 40, bottom: 60 }],
      xAxis: [{ name: 'left', type: 'category', data: cats }, { name: 'right', type: 'category', data: cats, gridIndex: 1 }],
      yAxis: [{}, { gridIndex: 1 }],
      series: [{ type: 'bar', data: [1, 2, 3, 4, 5] }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [5, 4, 3, 2, 1] }],
    },
    steps: [[100, 200], [400, 200]],
  },
  {
    id: 'link-name-shift', note: 'by name with a category mapper: [{xAxisName: [left, right], mapper: @Shift}] -- the target is one category on; past the last one there is no pointer',
    option: {
      animation: false, tooltip: { trigger: 'axis' },
      axisPointer: { link: [{ xAxisName: ['left', 'right'], mapper: '@Shift' }] },
      grid: [{ left: 40, width: 220, top: 40, bottom: 60 }, { left: 330, width: 220, top: 40, bottom: 60 }],
      xAxis: [{ name: 'left', type: 'category', data: cats }, { name: 'right', type: 'category', data: cats, gridIndex: 1 }],
      yAxis: [{}, { gridIndex: 1 }],
      series: [{ type: 'bar', data: [1, 2, 3, 4, 5] }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [5, 4, 3, 2, 1] }],
    },
    steps: [[60, 200], [150, 200], [250, 200], [345, 200], [540, 200]],
  },
  {
    id: 'link-cross', note: 'tooltip cross: x linked by index, y linked with @Half (the cross arm: no tooltip, no snap, the pointer at the mapped value)',
    option: {
      animation: false, tooltip: { trigger: 'axis', axisPointer: { type: 'cross' } },
      axisPointer: { link: [{ xAxisIndex: [0, 1] }, { yAxisIndex: 'all', mapper: '@Half' }] },
      grid: [{ left: 50, width: 220, top: 40, bottom: 60 }, { left: 340, width: 220, top: 40, bottom: 60 }],
      xAxis: [{ type: 'value', min: 0, max: 10 }, { type: 'value', gridIndex: 1, min: 0, max: 10 }],
      yAxis: [{ min: 0, max: 100 }, { gridIndex: 1, min: 0, max: 100 }],
      series: [{ type: 'line', data: [[1, 10], [4, 60], [8, 30]] }, { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [[2, 80], [5, 20], [9, 70]] }],
    },
    steps: [[160, 150], [400, 250], [300, 200]],
  },
  {
    id: 'link-snap-out', note: 'a snapping value source passes its SNAPPED value on, the target does not snap; @Hundred maps out of the target extent: no pointer there',
    option: {
      animation: false, tooltip: { trigger: 'axis' },
      axisPointer: { link: [{ xAxisIndex: [0, 1] }, { xAxisIndex: [2, 3], mapper: '@Hundred' }] },
      grid: [{ left: 40, width: 110, top: 40, bottom: 60 }, { left: 180, width: 110, top: 40, bottom: 60 }, { left: 320, width: 110, top: 40, bottom: 60 }, { left: 460, width: 110, top: 40, bottom: 60 }],
      xAxis: [{ type: 'value', min: 0, max: 10 }, { type: 'value', gridIndex: 1, min: 0, max: 10 }, { type: 'value', gridIndex: 2, min: 0, max: 10 }, { type: 'value', gridIndex: 3, min: 0, max: 10 }],
      yAxis: [{}, { gridIndex: 1 }, { gridIndex: 2 }, { gridIndex: 3 }],
      series: [
        { type: 'line', data: [[1, 1], [4.5, 3], [8, 2]] },
        { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [[2, 3], [5, 1], [6, 4]] },
        { type: 'line', xAxisIndex: 2, yAxisIndex: 2, data: [[0, 1], [0.05, 2], [10, 1]] },
        { type: 'line', xAxisIndex: 3, yAxisIndex: 3, data: [[1, 2], [5, 2], [9, 2]] },
      ],
    },
    steps: [[95, 200], [70, 200], [330, 200], [500, 200]],
  },
  // ---- milestone D5-D8 ----
  {
    id: 'link-shared-grid', note: 'two x axes in one grid (bottom a..e; top p, q, r with max 4: positions 3 and 4 hold no category), linked '
      + 'with @Half: at b both show and nothing is linked; at e and d the top one shows nothing and takes half the bottom one\'s value, '
      + 'parsed (2, and 1.5 -> 2)',
    option: {
      animation: false, tooltip: { trigger: 'axis' }, axisPointer: { link: [{ xAxisIndex: [0, 1], mapper: '@Half' }] },
      grid: { left: 50, right: 50, top: 60, bottom: 60 },
      xAxis: [{ type: 'category', data: cats }, { type: 'category', position: 'top', data: ['p', 'q', 'r'], max: 4 }],
      yAxis: {},
      series: [{ type: 'bar', data: [5, 3, 4, 7, 2] }, { type: 'line', xAxisIndex: 1, data: [2, 6, 4] }],
    },
    steps: [[200, 200], [500, 200], [400, 200]],
  },
  {
    id: 'link-last-source', note: 'two shown axes of one group in grid 0 (the bottom x at b, 1; the top x of three categories at p, 0) and a '
      + 'target in grid 1: the target takes the LAST source\'s value',
    option: {
      animation: false, tooltip: { trigger: 'axis' }, axisPointer: { link: { xAxisIndex: 'all' } },
      grid: [{ left: 50, width: 500, top: 40, height: 130 }, { left: 50, width: 500, top: 230, height: 130 }],
      xAxis: [{ type: 'category', data: cats }, { type: 'category', position: 'top', data: ['p', 'q', 'r'] },
        { type: 'category', data: cats, gridIndex: 1 }],
      yAxis: [{}, { gridIndex: 1 }],
      series: [{ type: 'bar', data: [5, 3, 4, 7, 2] }, { type: 'line', xAxisIndex: 1, data: [2, 6, 4] },
        { type: 'line', xAxisIndex: 2, yAxisIndex: 1, data: [1, 2, 3, 4, 5] }],
    },
    steps: [[200, 100], [450, 100]],
  },
  {
    id: 'link-regroup', note: 'a polar over the grid holds the point too: the grid\'s top x shows nothing and is linked from its bottom x '
      + '(d, 3 -> @Half 1.5 -> r) -- its pointer joins the grid\'s axes in the tooltip, before the polar\'s',
    option: {
      animation: false, tooltip: { trigger: 'axis' }, axisPointer: { link: [{ xAxisIndex: [0, 1], mapper: '@Half' }] },
      grid: { left: 50, right: 50, top: 60, bottom: 60 },
      polar: { center: [400, 200], radius: 80 },
      angleAxis: { type: 'category', data: ['u', 'v', 'w', 'x'] }, radiusAxis: {},
      xAxis: [{ type: 'category', data: cats }, { type: 'category', position: 'top', data: ['p', 'q', 'r'], max: 4 }],
      yAxis: {},
      series: [{ type: 'bar', data: [5, 3, 4, 7, 2] }, { type: 'line', xAxisIndex: 1, data: [2, 6, 4] },
        { type: 'bar', coordinateSystem: 'polar', data: [1, 2, 3, 4] }],
    },
    steps: [[420, 180], [380, 230]],
  },
  {
    id: 'snap-outside', note: 'no link: a value axis cut at 10 snaps only to a point that is on it -- nearest 9 is 12, past the axis, so the '
      + 'pointer stays at 9 (the tooltip still names 12); nearest 3 is 2',
    option: {
      animation: false, tooltip: { trigger: 'axis' }, grid: { left: 50, right: 50, top: 40, bottom: 40 },
      xAxis: { type: 'value', min: 0, max: 10 }, yAxis: {},
      series: [{ type: 'line', data: [[2, 1], [12, 3]] }],
    },
    steps: [[500, 200], [200, 200]],
  },
];

function axisKeyOf(ai) {
  return ai.axis.dim + ai.axis.model.componentIndex;
}
function runLinkCase(def) {
  const chart = newChart();
  const events = [];
  try {
    chart.setOption(withMappers(def.option));
    frame(chart);
    for (const t of ['showtip', 'hidetip', 'highlight', 'downplay']) chart.on(t, e => events.push({ t, e }));
    const steps = [];
    for (const at of def.steps) {
      events.length = 0;
      MAPPER_LOG = [];
      const hd = chart.getZr().handler;
      if (at === 'leave') hd.dispatch('globalout', rawEvent('globalout', 0, 0));
      else hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      frame(chart);
      const ap = chart.getModel().getComponent('axisPointer');
      const info = ap.coordSysAxesInfo;
      const axes = [];
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
      let tip = null;
      const highlights = [];
      for (const { t, e } of events) {
        if (t === 'showtip') {
          tip = e.dataByCoordSys.map(c => ({
            cs: c.coordSysMainType + c.coordSysIndex,
            axes: c.dataByAxis.map(a => ({ dim: a.axisDim, index: a.axisIndex, value: hex(a.value), valueText: text(a.value), sdi: a.seriesDataIndices.map(b => [b.seriesIndex, b.dataIndex, b.dataIndexInside]) })),
          }));
        } else if (t === 'hidetip') tip = 'hide';
        else highlights.push({ type: t, items: (e.batch || []).map(b => [b.seriesIndex, b.dataIndex]) });
      }
      steps.push({ at, axes, tip, highlights, mapper: MAPPER_LOG });
      MAPPER_LOG = null;
    }
    return { id: def.id, note: def.note, option: def.option, steps };
  } finally {
    chart.dispose();
  }
}

// =====================================================================
// connect, batch
// =====================================================================
function barLine(extra) {
  return Object.assign({
    animation: false,
    legend: { data: ['s1', 's2'] },
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'] },
    yAxis: {},
    dataZoom: [{ type: 'slider' }, { type: 'inside' }],
    series: [
      { name: 's1', type: 'bar', selectedMode: 'multiple', data: [3, 5, 2, 6, 4, 7] },
      { name: 's2', type: 'line', selectedMode: 'single', data: [6, 2, 5, 3, 7, 1] },
    ],
  }, extra || {});
}
function withBrush() {
  return barLine({ brush: { xAxisIndex: 0 } });
}
function timelineOpt() {
  return {
    animation: false,
    baseOption: {
      timeline: { axisType: 'category', autoPlay: false, data: ['2001', '2002', '2003'] },
      xAxis: { type: 'category', data: ['a', 'b', 'c'] },
      yAxis: {},
      series: [{ name: 'v', type: 'bar' }],
    },
    options: [{ series: [{ data: [1, 2, 3] }] }, { series: [{ data: [3, 1, 2] }] }, { series: [{ data: [2, 3, 1] }] }],
  };
}
const AUTO_DZ0 = '\u0000series\u00000\u00000';

const CONNECT_CASES = [
  {
    id: 'conn-two', note: 'two charts of one shape in group g: what A does B follows; B\'s own events do not come back; escapeConnect, a silent dispatch and disconnect stop it; connect([A, B]) keeps g',
    charts: [{ option: withBrush() }, { option: withBrush() }],
    steps: [
      { op: 'group', chart: 0, value: 'g' }, { op: 'group', chart: 1, value: 'g' }, { op: 'connect', group: 'g' },
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', name: 's2' } },
      { op: 'action', chart: 0, payload: { type: 'dataZoom', dataZoomIndex: 0, start: 20, end: 60 } },
      { op: 'action', chart: 1, payload: { type: 'dataZoom', batch: [{ dataZoomId: AUTO_DZ0, start: 10, end: 90 }] } },
      { op: 'action', chart: 0, payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
      { op: 'action', chart: 0, payload: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } },
      { op: 'action', chart: 0, payload: { type: 'select', seriesIndex: 0, dataIndex: [1, 3] } },
      { op: 'action', chart: 1, payload: { type: 'toggleSelect', seriesIndex: 0, dataIndex: 3 } },
      { op: 'action', chart: 0, payload: { type: 'brush', areas: [{ brushType: 'lineX', coordRange: [1, 3], xAxisIndex: 0 }] } },
      { op: 'action', chart: 0, payload: { type: 'highlight', seriesIndex: 1, dataIndex: 0, escapeConnect: true } },
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', name: 's2' }, silent: true },
      { op: 'disconnect', group: 'g' },
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', name: 's1' } },
      { op: 'connectList', charts: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'legendAllSelect' } },
    ],
  },
  {
    id: 'conn-three', note: 'three charts: B\'s action reaches A and C (each once); C moved to group h stops hearing g; a chart with no group hears nothing',
    charts: [{ option: barLine() }, { option: barLine() }, { option: barLine() }, { option: barLine() }],
    steps: [
      { op: 'connectList', charts: [0, 1, 2] },
      { op: 'action', chart: 1, payload: { type: 'legendUnSelect', name: 's1' } },
      { op: 'action', chart: 2, payload: { type: 'dataZoom', dataZoomIndex: 1, start: 30, end: 70 } },
      { op: 'group', chart: 2, value: 'h' }, { op: 'connect', group: 'h' },
      { op: 'action', chart: 0, payload: { type: 'legendSelect', name: 's1' } },
      { op: 'action', chart: 2, payload: { type: 'legendInverseSelect' } },
      { op: 'action', chart: 3, payload: { type: 'legendInverseSelect' } },
    ],
  },
  {
    id: 'conn-wheel', note: 'a wheel on A\'s inside dataZoom: the batched dataZoom action (its animation in every item) and B following',
    charts: [{ option: barLine() }, { option: barLine() }],
    steps: [
      { op: 'connectList', charts: [0, 1] },
      { op: 'wheel', chart: 0, x: 300, y: 200, delta: 1 },
      { op: 'idle', ms: 1000 },
    ],
  },
  {
    id: 'conn-timeline', note: 'timelineChange and timelinePlayChange between two timeline charts, with the brushSelect their updates dispatch (milestone D5-D8: it was left out, dropBrushSelect, while the port ran the update of a merged frame at the next frame)',
    charts: [{ option: timelineOpt() }, { option: timelineOpt() }],
    steps: [
      { op: 'connectList', charts: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'timelineChange', currentIndex: 2 } },
      { op: 'action', chart: 1, payload: { type: 'timelinePlayChange', playState: false } },
    ],
  },
  {
    id: 'conn-unlike', note: 'B has no legend and one dataZoom: A\'s legend action reaches a chart with no legend (an empty map), A\'s dataZoom on index 1 finds no dataZoom in B',
    charts: [{ option: barLine() }, { option: barLine({ legend: undefined, dataZoom: [{ type: 'slider' }] }) }],
    steps: [
      { op: 'connectList', charts: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', name: 's1' } },
      { op: 'action', chart: 0, payload: { type: 'dataZoom', dataZoomIndex: 1, start: 40, end: 50 } },
    ],
  },
];

const BATCH_CASES = [
  {
    id: 'brush-own-keys', note: 'a brush whose option writes its style (the colours echoed as written) and action areas with keys of their '
      + 'own: generateBrushOption overwrites the six in place, the rest follow in order, then range and a targeted panelId (milestone D5-D8)',
    charts: [{ option: barLine({ brush: { xAxisIndex: 0, brushStyle: { color: 'rgba(10,20,30,0.25)', borderColor: '#336699', borderWidth: 2, opacity: 0.8 } } }) }],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'brush', areas: [{ brushType: 'lineX', foo: 'bar', coordRange: [1, 3], xAxisIndex: 0, brushMode: 'multiple' }] } },
      { op: 'action', chart: 0, payload: { type: 'brush', areas: [{ brushType: 'rect', range: [[100, 200], [80, 160]], z: 7 }] } },
    ],
  },
  {
    id: 'resize-brush', note: 'a resize is an update with a payload ({type: \'resize\'}): the brush visual dispatches brushSelect -- '
      + 'brushselected, which B is sent -- then `updated` (milestone D5-D8)',
    charts: [{ option: withBrush() }, { option: withBrush() }],
    steps: [
      { op: 'connectList', charts: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'brush', areas: [{ brushType: 'lineX', coordRange: [1, 3], xAxisIndex: 0 }] } },
      { op: 'resize', chart: 0, w: 500, h: 360 },
      { op: 'resize', chart: 1, w: 560, h: 380 },
    ],
  },
  {
    id: 'batch-legend', note: 'the legend actions with a batch: each item over the payload, ONE update, one event whose batch holds each item\'s own result',
    charts: [{ option: barLine() }],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', batch: [{ name: 's1' }, { name: 's2' }, { name: 's1' }] } },
      { op: 'action', chart: 0, payload: { type: 'legendUnSelect', legendIndex: 0, batch: [{ name: 's1' }, { name: 's2', legendIndex: null }] } },
      { op: 'action', chart: 0, payload: { type: 'legendAllSelect', batch: [{}, { legendIndex: 0 }] } },
      { op: 'action', chart: 0, payload: { type: 'legendInverseSelect', escapeConnect: false, batch: [{}] } },
    ],
  },
  {
    id: 'batch-select', note: 'select / toggleSelect / unselect with a batch: the event batch repeats the FIRST item (refineEvent keeps eventObj), selectchanged once with the outer payload',
    charts: [{ option: barLine() }],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'select', seriesIndex: 0, batch: [{ dataIndex: 1 }, { dataIndex: 4 }, { seriesIndex: 1, dataIndex: 2 }] } },
      { op: 'action', chart: 0, payload: { type: 'toggleSelect', batch: [{ seriesIndex: 0, dataIndex: [1, 2] }, { seriesIndex: 1, dataIndex: 5 }] } },
      { op: 'action', chart: 0, payload: { type: 'unselect', seriesIndex: 0, dataIndex: 4, batch: [{ dataIndex: null }, { seriesName: 's2', dataIndex: 5 }] } },
      // milestone D5-D8: an item's own type is the one its update reads
      { op: 'action', chart: 0, payload: { type: 'select', batch: [{ seriesIndex: 0, dataIndex: 0 }, { type: 'unselect', seriesIndex: 0, dataIndex: 0 }, { type: 'toggleSelect', seriesIndex: 0, dataIndex: 2 }] } },
    ],
  },
  {
    id: 'batch-highdown', note: 'highlight / downplay batches: escapeConnect rides on the event',
    charts: [{ option: barLine() }],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'highlight', escapeConnect: true, batch: [{ seriesIndex: 0, dataIndex: 1 }, { seriesIndex: 1, dataIndex: 3 }] } },
      { op: 'action', chart: 0, payload: { type: 'downplay', seriesIndex: 0, batch: [{ dataIndex: 1 }] } },
    ],
  },
  {
    id: 'batch-datazoom', note: 'dataZoom batches: by index, by id, the outer animation in every item; a silent one publishes nothing',
    charts: [{ option: barLine() }],
    steps: [
      { op: 'action', chart: 0, payload: { type: 'dataZoom', animation: { duration: 0 }, batch: [{ dataZoomIndex: 0, start: 10, end: 50 }] } },
      { op: 'action', chart: 0, payload: { type: 'dataZoom', batch: [{ dataZoomId: AUTO_DZ0, start: 25, end: 75 }, { dataZoomIndex: 1, start: 30, end: 40 }] } },
      { op: 'action', chart: 0, payload: { type: 'dataZoom', batch: [{ dataZoomIndex: 0, start: 0, end: 100 }] }, silent: true },
      // milestone D5-D8: by value, both ends, then one end (the other kept)
      { op: 'action', chart: 0, payload: { type: 'dataZoom', batch: [{ dataZoomIndex: 0, startValue: 1, endValue: 4 }] } },
      { op: 'action', chart: 0, payload: { type: 'dataZoom', batch: [{ dataZoomIndex: 0, startValue: 2 }] } },
    ],
  },
  {
    id: 'batch-connect', note: 'a batch in a connected group: B is sent the batched event as an action (each item keeps the event\'s type and result keys)',
    charts: [{ option: barLine() }, { option: barLine() }],
    steps: [
      { op: 'connectList', charts: [0, 1] },
      { op: 'action', chart: 0, payload: { type: 'legendToggleSelect', batch: [{ name: 's2' }, { name: 's1' }, { name: 's1' }] } },
      { op: 'action', chart: 1, payload: { type: 'select', batch: [{ seriesIndex: 0, dataIndex: 2 }, { seriesIndex: 0, dataIndex: 5 }] } },
      { op: 'action', chart: 0, payload: { type: 'highlight', batch: [{ seriesIndex: 0, dataIndex: 0 }] } },
      // milestone D5-D8: a toggleSelect batch of three, its event's items (the first one's copy, typed 'toggleselect') as A is
      // sent them -- an item whose type is no select type changes nothing
      { op: 'action', chart: 1, payload: { type: 'toggleSelect', batch: [{ seriesIndex: 0, dataIndex: 1 }, { seriesIndex: 0, dataIndex: 3 }, { seriesIndex: 0, dataIndex: 4 }] } },
    ],
  },
];

let REVERT = null;
function revertMapOf(chart) {
  const hs = chart._messageCenter._$handlers;
  const out = {};
  for (const t of Object.keys(hs)) {
    const a = chart.makeActionFromEvent({ type: t }).type;
    if (a !== undefined) out[t] = a;
  }
  return out;
}

function stateOf(chart) {
  const m = chart.getModel();
  const legend = [];
  m.eachComponent('legend', l => legend.push(JSON.stringify(l.option.selected || {})));
  const dz = [];
  m.eachComponent('dataZoom', d => { const r = d.getPercentRange(); dz.push([hex(r[0]), hex(r[1])]); });
  const sel = [];
  m.eachSeries(s => sel.push({ s: s.seriesIndex, idx: s.getSelectedDataIndices() }));
  const tlm = m.getComponent('timeline');
  const tl = tlm ? tlm.getCurrentIndex() : null;
  const brush = [];
  m.eachComponent('brush', b => brush.push((b.areas || []).length));
  return { legend, dz, sel, tl, brush };
}

const EXTRA_EVENTS = ['selectchanged', 'axisbreakchanged', 'updated'];
function runConnectCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const charts = def.charts.map(c => newChart(c.w, c.h));
  const log = [];
  try {
    charts.forEach((c, i) => {
      c.setOption(clone(def.charts[i].option));
      frame(c);
      if (!REVERT) REVERT = revertMapOf(c);
      const types = Object.keys(REVERT).concat(EXTRA_EVENTS);
      // dropBrushSelect: no brushselected, and nothing a brushSelect
      // dispatch publishes (its `updated`)
      let inBrushSelect = 0;
      if (def.dropBrushSelect) {
        const own = c.dispatchAction;
        c.dispatchAction = function (payload, opt) {
          const is = payload && payload.type === 'brushSelect';
          if (is) inBrushSelect++;
          try {
            return own.call(this, payload, opt);
          } finally {
            if (is) inBrushSelect--;
          }
        };
      }
      for (const t of types) {
        c.on(t, e => {
          if (def.dropBrushSelect && (t === 'brushselected' || inBrushSelect > 0)) return;
          log.push([i, t, jsonOf(e)]);
        });
      }
    });
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      let ret;
      let pointerSkipped = false;
      if (st.op === 'group') {
        if (st.value === null) delete charts[st.chart].group;
        else charts[st.chart].group = st.value;
      } else if (st.op === 'connect') ret = echarts.connect(st.group);
      else if (st.op === 'connectList') ret = echarts.connect(st.charts.map(i => charts[i]));
      else if (st.op === 'disconnect') echarts.disconnect(st.group);
      else if (st.op === 'action') charts[st.chart].dispatchAction(clone(st.payload), st.silent ? true : undefined);
      else if (st.op === 'wheel') {
        advanceClock(NOW + 200);
        charts[st.chart].getZr().handler.mousewheel(rawEvent('mousewheel', st.x, st.y, st.delta));
        // THE POINTER'S OWN ACTIONS are left out: the axis pointer's global
        // listener dispatches updateAxisPointer (and hideTip) on every pointer
        // event, and those are broadcast too; the port drives its pointer
        // without actions (see the notes). Their `updated` go with them.
        const kept = [];
        let skip = 0;
        for (const e of log) {
          if (e[1] === 'updateaxispointer' || e[1] === 'hidetip' || e[1] === 'showtip') { skip++; continue; }
          kept.push(e);
        }
        log.length = 0;
        for (const e of kept) log.push(e);
        must(skip > 0, def.id + ': the wheel dispatched no pointer action');
        pointerSkipped = true;
      } else if (st.op === 'idle') advanceClock(NOW + st.ms);
      else if (st.op === 'resize') charts[st.chart].resize({ width: st.w, height: st.h });
      else throw new OracleError('op ' + st.op);
      charts.forEach(frame);
      if (typeof ret === 'string' && /^g_\d+$/.test(ret)) ret = 'g_<auto>';
      let events = log.slice();
      // the pointer actions' own `updated` (one per chart per pointer action,
      // after the dataZoom's) are dropped with them: everything after the last
      // non-`updated` event of the dataZoom's broadcast
      if (pointerSkipped) {
        const cut = events.length;
        let firstUpd = -1;
        for (let k = 0; k < cut; k++) if (events[k][1] === 'updated' && events[k][0] === st.chart) { firstUpd = k; break; }
        if (firstUpd >= 0) events = events.slice(0, firstUpd + 1);
      }
      steps.push(Object.assign({}, plain(st, 0), { ret: ret === undefined ? null : ret, events, state: charts.map(stateOf) }));
    }
    return { id: def.id, note: def.note, dropBrushSelect: !!def.dropBrushSelect, charts: def.charts.map(c => ({ option: plain(c.option, 0), w: c.w || W, h: c.h || H })), steps };
  } finally {
    charts.forEach(c => { echarts.disconnect(c.group); c.dispose(); });
  }
}

// =====================================================================
// getConnectedDataURL
// =====================================================================
const EXPORT_CASES = [
  { id: 'exp-row', note: 'three charts in a row with gaps, no options: the dpr is the asking chart\'s (1 here)', rects: [{ left: 10, top: 20, w: 200, h: 150 }, { left: 230, top: 20, w: 160, h: 150 }, { left: 400, top: 60, w: 100, h: 80 }], connect: true, chart: 0, opts: {} },
  { id: 'exp-ratio2-bg', note: 'pixelRatio 2 and a connected background', rects: [{ left: 10, top: 20, w: 200, h: 150 }, { left: 230, top: 40, w: 160, h: 100 }], connect: true, chart: 1, opts: { pixelRatio: 2, connectedBackgroundColor: '#336699' } },
  { id: 'exp-ratio15', note: 'pixelRatio 1.5 with odd offsets: fractional positions, the canvas size as the raw product', rects: [{ left: 3, top: 7, w: 101, h: 67 }, { left: 117, top: 2, w: 55, h: 91 }], connect: true, chart: 0, opts: { pixelRatio: 1.5, connectedBackgroundColor: 'rgba(255,0,0,0.5)' } },
  { id: 'exp-overlap-neg', note: 'overlapping charts at negative offsets; jpeg; backgroundColor goes to each chart\'s own render', rects: [{ left: -40, top: -10, w: 120, h: 90 }, { left: 30, top: 20, w: 120, h: 90 }], connect: true, chart: 0, opts: { type: 'jpeg', backgroundColor: '#ffffff' } },
  { id: 'exp-none-bg', note: 'connectedBackgroundColor \'none\' is still a rect fill (zrender: no fill)', rects: [{ left: 0, top: 0, w: 100, h: 100 }, { left: 150, top: 0, w: 100, h: 100 }], connect: true, chart: 0, opts: { connectedBackgroundColor: 'none' } },
  { id: 'exp-ratio11', note: 'pixelRatio 1.1: the left edge times the ratio is inexact, each offset the product less it (milestone D5-D8)', rects: [{ left: 3, top: 7, w: 101, h: 67 }, { left: 117, top: 29, w: 55, h: 91 }, { left: 241, top: 13, w: 40, h: 40 }], connect: true, chart: 0, opts: { pixelRatio: 1.1 } },
  { id: 'exp-not-connected', note: 'the group is set but never connected: getDataURL of the asking chart alone', rects: [{ left: 0, top: 0, w: 100, h: 100 }, { left: 150, top: 0, w: 100, h: 100 }], connect: false, chart: 1, opts: { pixelRatio: 2 } },
];

let OPS = null;
let canvasSeq = 0;
function fakeCtx() {
  const store = {};
  return new Proxy(store, {
    get(t, p) {
      if (p in t) return t[p];
      if (typeof p === 'symbol') return undefined;
      return (...a) => {
        if (OPS) OPS.push([p, a]);
        return p === 'measureText' ? { width: 0 } : undefined;
      };
    },
    set(t, p, v) { t[p] = v; if (OPS) OPS.push(['set ' + String(p), [v]]); return true; },
  });
}
function fakeTargetCanvas() {
  const c = { __target: ++canvasSeq, nodeName: 'CANVAS', _w: 0, _h: 0, sizes: [] };
  Object.defineProperty(c, 'width', { get() { return this._w; }, set(v) { this.sizes.push(['w', v]); this._w = v; } });
  Object.defineProperty(c, 'height', { get() { return this._h; }, set(v) { this.sizes.push(['h', v]); this._h = v; } });
  const ctx = fakeCtx();
  c.getContext = () => ctx;
  c.toDataURL = m => { if (OPS) OPS.push(['toDataURL', [m]]); return 'data:' + m; };
  LAST_TARGET = c;
  return c;
}
let LAST_TARGET = null;

function runExportCase(def) {
  const charts = def.rects.map(r => newChart(r.w, r.h));
  try {
    const renders = [];
    let self = false;
    charts.forEach((c, i) => {
      c.setOption({ animation: false, series: [] });
      c.group = 'ex';
      const r = def.rects[i];
      c.getDom = () => ({ getBoundingClientRect: () => ({ left: r.left, top: r.top, right: r.left + r.w, bottom: r.top + r.h }) });
      c.renderToCanvas = opts => {
        renders.push({ chart: i, opts: plain(opts, 0) });
        const dpr = (opts && opts.pixelRatio) || c.getDevicePixelRatio();
        return { __chart: i, width: Math.floor(r.w * dpr), height: Math.floor(r.h * dpr) };
      };
      c.getDataURL = () => { self = true; return 'self'; };
    });
    if (def.connect) echarts.connect('ex');
    OPS = [];
    LAST_TARGET = null;
    const url = charts[def.chart].getConnectedDataURL(clone(def.opts));
    const raw = OPS;
    OPS = null;
    const ops = [];
    let fill = null;
    let rect = null;
    let mime = null;
    for (const [p, a] of raw) {
      if (p === 'set fillStyle') fill = a[0];
      else if (p === 'rect') rect = a;
      else if (p === 'fill') ops.push({ op: 'fill', color: fill, rect: rect.map(hex), rectText: rect.map(text) });
      else if (p === 'drawImage') {
        const img = a[0];
        ops.push({ op: 'image', chart: img.__chart, x: hex(a[1]), y: hex(a[2]), w: hex(a[3]), h: hex(a[4]), xText: text(a[1]), yText: text(a[2]), wText: text(a[3]), hText: text(a[4]) });
      } else if (p === 'toDataURL') mime = a[0];
    }
    let canvas = null;
    if (LAST_TARGET) {
      const ws = LAST_TARGET.sizes.filter(s => s[0] === 'w').map(s => s[1]);
      const hs = LAST_TARGET.sizes.filter(s => s[0] === 'h').map(s => s[1]);
      const w = ws[ws.length - 1];
      const h = hs[hs.length - 1];
      canvas = { width: hex(w), height: hex(h), widthText: text(w), heightText: text(h) };
    }
    return { id: def.id, note: def.note, rects: def.rects, connect: def.connect, chart: def.chart, opts: def.opts, self, url: self ? 'self' : url, renders, canvas, ops, mime };
  } finally {
    echarts.disconnect('ex');
    charts.forEach(c => c.dispose());
  }
}

// the transcription of getConnectedDataURL's canvas branch (echarts.ts
// 1027-1112), checked against every connected record
function connectedLayout(rects, dpr) {
  let left = Infinity;
  let top = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  for (const r of rects) {
    left = Math.min(r.left, left);
    top = Math.min(r.top, top);
    right = Math.max(r.left + r.w, right);
    bottom = Math.max(r.top + r.h, bottom);
  }
  left *= dpr;
  top *= dpr;
  right *= dpr;
  bottom *= dpr;
  return { width: right - left, height: bottom - top, pos: rects.map(r => [r.left * dpr - left, r.top * dpr - top]) };
}

// =====================================================================
function generate() {
  REVERT = null;
  echarts.setPlatformAPI({ createCanvas: fakeTargetCanvas });
  const link = LINK_CASES.map(runLinkCase);
  const connect = CONNECT_CASES.map(runConnectCase);
  const batch = BATCH_CASES.map(runConnectCase);
  // the target canvas of getConnectedDataURL is not a DOM node: zrender must
  // not mount listeners on it
  echarts.env.node = true;
  const exportCases = EXPORT_CASES.map(runExportCase);
  echarts.env.node = false;
  return { revertMap: REVERT, link, connect, batch, exportCases };
}

function anchors(g) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const lk = id => g.link.find(c => c.id === id);
  const cn = id => g.connect.find(c => c.id === id) || g.batch.find(c => c.id === id);
  const ax = (step, key) => step.axes.find(a => a.key === key);
  // link
  const la = lk('link-all');
  guard('link-follows', ax(la.steps[0], 'x1').status === 'show' && ax(la.steps[0], 'x1').valueText === ax(la.steps[0], 'x0').valueText, 'the bottom grid follows the top one');
  guard('link-tip-two-grids', Array.isArray(la.steps[0].tip) && la.steps[0].tip.length === 2, 'the tooltip lists both grids');
  guard('link-highlight-both', la.steps[0].highlights.some(h => h.type === 'highlight' && h.items.length === 2), 'one highlight batch for both grids');
  guard('link-leave-hides', la.steps[5].axes.every(a => a.status === 'hide'), 'leaving hides every pointer');
  const li = lk('link-id-mapper');
  guard('link-mapper-doubles', ax(li.steps[0], 'x1').status === 'show' && li.steps[0].mapper.length === 1 && li.steps[0].mapper[0].fn === 'Double', 'b follows a through the mapper');
  guard('link-unlinked-c', li.steps[4].axes.filter(a => a.status === 'show').length === 1, 'c links nothing');
  const ln = lk('link-name-first');
  guard('link-first-group', ln.steps[0].axes.filter(a => a.status === 'show').length === 1, 'left belongs to group 0 alone: nothing follows');
  const ls = lk('link-name-shift');
  guard('link-shift-past-end', ls.steps[4].axes.filter(a => a.status === 'show').length === 1, 'one category on from the last: no target');
  const lc = lk('link-cross');
  guard('link-cross-y', ax(lc.steps[0], 'y1') && ax(lc.steps[0], 'y1').status === 'show', 'the y cross arm follows');
  const lo = lk('link-snap-out');
  guard('link-out-of-extent', ax(lo.steps[3], 'x2').status === 'hide' && lo.steps[3].mapper.length === 1, '@Hundred maps out of the extent');
  guard('link-in-extent', ax(lo.steps[2], 'x3').valueText === '5', '@Hundred maps the snapped 0.05 to 5');
  guard('link-snapped-source', ax(lo.steps[0], 'x1').valueText === '4.5', 'the target takes the source\'s snapped 4.5');
  // connect
  const c2 = cn('conn-two');
  const ev = (st, ch, t) => st.events.filter(e => e[0] === ch && e[1] === t);
  const step = (c, op, i) => c.steps.filter(s => s.op === op)[i];
  const lt = step(c2, 'action', 0);
  guard('conn-legend-reaches-b', ev(lt, 1, 'legendselectchanged').length === 1 && lt.state[1].legend[0] === lt.state[0].legend[0], 'B toggles s2 as A did');
  guard('conn-handlers-first', lt.events.findIndex(e => e[0] === 0 && e[1] === 'legendselectchanged') < lt.events.findIndex(e => e[0] === 1), 'A\'s own handler before B hears anything');
  guard('conn-no-loop', lt.events.filter(e => e[1] === 'legendselectchanged').length === 2, 'B\'s event is not sent back to A');
  const esc = step(c2, 'action', 8);
  guard('conn-escape', ev(esc, 1, 'highlight').length === 0 && ev(esc, 0, 'highlight').length === 1, 'escapeConnect stays in A');
  const sil = step(c2, 'action', 9);
  guard('conn-silent', sil.events.length === 0, 'a silent dispatch publishes nothing, so nothing is broadcast');
  const disc = step(c2, 'action', 10);
  guard('conn-disconnect', disc.events.every(e => e[0] === 0), 'disconnected: A alone');
  guard('conn-list-keeps', step(c2, 'connectList', 0).ret === 'g', 'connect([A, B]) keeps their group');
  const br = step(c2, 'action', 7);
  guard('conn-brush-echo', ev(br, 1, 'brushselected').length === 2, 'B hears its own brushselected and A\'s echo');
  const c3 = cn('conn-three');
  guard('conn-three-once', ev(step(c3, 'action', 0), 0, 'legendunselected').length === 1 && ev(step(c3, 'action', 0), 2, 'legendunselected').length === 1, 'A and C once each');
  guard('conn-moved', step(c3, 'action', 2).events.every(e => e[0] !== 2), 'C in h hears nothing of g');
  guard('conn-nogroup', step(c3, 'action', 4).events.every(e => e[0] === 3), 'no group, no broadcast');
  const cw = cn('conn-wheel');
  guard('conn-wheel', cw.steps[1].events.some(e => e[0] === 1 && e[1] === 'datazoom'), 'the wheel reaches B');
  // batch
  const bs = cn('batch-select');
  const sb = bs.steps[0].events.find(e => e[1] === 'select');
  guard('batch-select-first-item', sb && sb[2].batch.length === 3 && JSON.stringify(sb[2].batch[0]) === JSON.stringify(sb[2].batch[2]), 'the select batch repeats the first item');
  const bl = cn('batch-legend');
  const lb = bl.steps[0].events.find(e => e[1] === 'legendselectchanged');
  guard('batch-legend-results', lb && lb[2].batch.length === 3 && lb[2].batch[0].selected.s1 === false && lb[2].batch[2].selected.s1 === true, 'each item its own result');
  guard('batch-one-updated', bl.steps[0].events.filter(e => e[1] === 'updated').length === 1, 'one update');
  const bd = cn('batch-datazoom');
  guard('batch-dz-silent', bd.steps[2].events.length === 0 && bd.steps[2].state[0].dz[0][1] === hex(100), 'silent: applied, nothing published');
  // export: the transcription
  for (const c of g.exportCases) {
    if (!c.connect) {
      guard('exp-self-' + c.id, c.self && c.renders.length === 0, 'not connected: getDataURL');
      continue;
    }
    const dpr = c.opts.pixelRatio || 1;
    const lay = connectedLayout(c.rects, dpr);
    let ok = c.canvas.width === hex(lay.width) && c.canvas.height === hex(lay.height);
    const imgs = c.ops.filter(o => o.op === 'image');
    ok = ok && imgs.length === c.rects.length;
    imgs.forEach((im, k) => { ok = ok && im.chart === k && im.x === hex(lay.pos[k][0]) && im.y === hex(lay.pos[k][1]); });
    const fills = c.ops.filter(o => o.op === 'fill');
    ok = ok && fills.length === (c.opts.connectedBackgroundColor && c.opts.connectedBackgroundColor !== 'none' ? 1 : 0);
    guard('exp-layout-' + c.id, ok, 'the transcription reproduces the layout');
  }
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / globalout; a frame after every step.',
  'Every chart listens to every connect-able event type plus selectchanged, axisbreakchanged and updated (rendered / finished are frames, not actions).',
  'Upstream registers the forwarder of a published event before the connect listener (_initEvents runs in the constructor, enableConnect after init): a chart\'s own handlers hear an event before the charts of its group are sent the action.',
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
    W, H, seed: SEED, clock: { start: CLOCK0, wheelDt: 200 },
    api: {
      chart: "echarts.init(null, null, {renderer: 'svg', ssr: true, width, height}); chart._ssr = false",
      connect: 'echarts.connect(group | charts[]), echarts.disconnect(group), chart.group',
      export: 'chart.getConnectedDataURL(opts) with getDom().getBoundingClientRect and renderToCanvas stubbed per chart and setPlatformAPI({createCanvas}) a recording canvas',
    },
    notes: NOTES,
    revertMap: g1.revertMap, link: g1.link, connect: g1.connect, batch: g1.batch, exportCases: g1.exportCases, guards,
  };
  json1 = JSON.stringify(plain(out, 0), null, 1) + '\n';
  const nul = json1.indexOf('\\u0000');
  must(nul < 0, 'the fixture holds a \\u0000: ' + json1.slice(Math.max(0, nul - 300), nul + 40));
  JSON.parse(json1);
  if (!process.env.ORACLE_ONCE) {
    const g2 = generate();
    json2 = JSON.stringify(plain(Object.assign({}, out, { revertMap: g2.revertMap, link: g2.link, connect: g2.connect, batch: g2.batch, exportCases: g2.exportCases, guards: anchors(g2) }), 0), null, 1) + '\n';
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
console.log(g1.link.length + ' link cases, ' + g1.connect.length + ' connect cases, ' + g1.batch.length + ' batch cases, ' + g1.exportCases.length + ' export cases; '
  + (guards.length - bad.length) + '/' + guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; '
  + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
