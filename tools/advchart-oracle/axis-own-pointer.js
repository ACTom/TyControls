// Upstream's own answers for round-2 batch R2-I7 (spec section 229f): AN
// AXIS' OWN POINTER and WHEN A TOOLTIP'S FUNCTIONS ARE CALLED.
//
// 1. modelHelper.collectAxesInfo takes every axis of a coordinate system
//    whose own axisPointer model (the axis' block over the root component)
//    says `show` truthy and not 'auto' -- saveTooltipAxisInfo(false, null,
//    axis), with triggerTooltip read off that model (default true), snap off
//    it (default false), the label shown by default -- before the tooltip's
//    axes, which replace an axis already taken. axisTrigger then draws its
//    pointer and label, puts its rows into the axis tooltip when it triggers
//    the tooltip (involveSeries: triggerTooltip || snap || a category axis),
//    and links it like any other axis. The tooltip's own trigger plays no
//    part: TooltipView shows whatever dataByCoordSys reaches it.
// 2. TooltipView calls a function formatter once per show
//    (_showTooltipContent) -- an axis tooltip's only when its content changed
//    (_updateContentNotChangedOnAxis) --, a function position once per show
//    (_updatePosition), and a valueFormatter while the default markup is
//    built, once per value per show, a formatter or not.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node exactly as tooltip-keep.js does (SVG renderer, ssr:
// true then chart._ssr = false, env.node off and getDom answering an empty
// object so TooltipView runs, Math.random the port's xorshift32, Date and
// setTimeout on a fake clock, TooltipRichContent.getSize answering 80 x 40).
// The option's '@fmt' / '@pos' / '@vf' / '@ptrfmt' strings are functions
// that count their calls:
//   @fmt     (params) => each params (an item's one, an axis tooltip's every)
//            as '<seriesIndex>:<dataIndex>@<axisDim><axisIndex>' (an item's
//            'undefinedundefined'), joined by a space
//   @pos     () => [10, 10]
//   @vf      (value) => 'v' + value
//   @ptrfmt  (params) => 'P' + params.value
//
//   node tools/advchart-oracle/axis-own-pointer.js
//
// writes tests/fixtures/advchart-axis-own-pointer.json (ORACLE_OUT
// overrides).
//
// Records: as tooltip-keep.js (steps {op, at, events, state}; state per
// chart {axes, tip}). Each axis of state.axes also has, when its pointer is
// shown, `draw`: {pixel (hex: the pointer line's coordinate along the axis,
// toGlobalCoord(dataToCoord(value, true)); null for a shadow or none),
// label (the label's text, null when it has none)}. tip.text is the box's
// text (a marker's style name written __EC_aUTo_#). Each step has `calls` {fmt, pos, vf, ptrfmt}: how many times each
// function ran during the step (the frame after it included).
// A move step may give `data: [gridIndex, x, y]` for its point: the data
// point through convertToPixel, rounded.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-own-pointer.json');

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

// ---------- the counting functions ----------
let CALLS = null;
const FNS = {
  fmt: params => (Array.isArray(params) ? params : [params]).map(p => p.seriesIndex + ':' + p.dataIndex + '@' + p.axisDim
    + p.axisIndex).join(' '),
  pos: () => [10, 10],
  vf: value => 'v' + value,
  ptrfmt: params => 'P' + params.value,
};
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      const s = v[k];
      if (typeof s === 'string' && s[0] === '@' && FNS[s.slice(1)]) {
        const name = s.slice(1);
        o[k] = function (...args) {
          if (CALLS) CALLS[name] = (CALLS[name] || 0) + 1;
          return FNS[name](...args);
        };
      } else o[k] = materialize(s);
    }
    return o;
  }
  return v;
}

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

// the pointer an axis draws: its group under the axis view
function drawOf(chart, ai) {
  const axis = ai.axis;
  const view = chart.getViewOfComponentModel(axis.model);
  const ap = view && view._axisPointer;
  const g = ap && ap._group;
  if (!g || g.ignore) return { pixel: null, label: null, group: false };
  const out = { pixel: null, label: null, group: true };
  g.childrenRef().forEach(e => {
    const t = String(e.type).toLowerCase();
    if (t === 'line') {
      // makeLineShape swaps the two for a y axis: the coordinate along the
      // axis is x1 on an x axis, y1 on a y axis
      out.pixel = hex(axis.dim === 'x' ? e.shape.x1 : e.shape.y1);
      out.pixelText = text(axis.dim === 'x' ? e.shape.x1 : e.shape.y1);
    } else if (t === 'text') {
      if (!e.ignore && !e.invisible) out.label = String(e.style.text);
    }
  });
  return out;
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
      const rec = {
        key: ai.axis.dim + ai.axis.model.componentIndex, dim: ai.axis.dim, index: ai.axis.model.componentIndex,
        status: o.status || 'hide',
        value: shown && typeof o.value === 'number' ? hex(o.value) : null, valueText: shown && o.value != null ? text(o.value) : null,
        sdi: shown ? (o.seriesDataIndices || []).map(b => [b.seriesIndex, b.dataIndex, b.dataIndexInside]) : [],
        triggerTooltip: !!ai.triggerTooltip, snap: !!ai.snap, involveSeries: !!ai.involveSeries,
      };
      if (shown) {
        const d = drawOf(chart, ai);
        must(d.group, 'a shown pointer with no group: ' + rec.key);
        rec.draw = { pixel: d.pixel, pixelText: d.pixelText || null, label: d.label };
      }
      axes.push(rec);
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
      // the markers' style names numbered from Math.random: written '#'
      text: vis && c.el ? String(c.el.style.text).replace(/__EC_aUTo_[0-9]+/g, '__EC_aUTo_#') : null,
    };
  }
  return { axes, tip };
}

// =====================================================================
// the cases
// =====================================================================
const SC = [[2, 3], [5, 6], [8, 4]];
function scatter(extra, tooltip) {
  const o = {
    animation: false,
    xAxis: { type: 'value', min: 0, max: 10 },
    yAxis: { type: 'value', min: 0, max: 10 },
    series: [{ type: 'scatter', name: 's', data: SC }],
  };
  if (tooltip !== undefined) o.tooltip = tooltip;
  return Object.assign(o, extra || {});
}
const cats = ['a', 'b', 'c', 'd'];
function barLine(tooltip, extra) {
  const o = {
    animation: false,
    xAxis: { type: 'category', data: cats },
    yAxis: { min: 0, max: 10 },
    series: [{ type: 'bar', name: 'b', data: [3, 5, 2, 6] }, { type: 'line', name: 'l', data: [1, 4, 3, 2] }],
  };
  if (tooltip !== undefined) o.tooltip = tooltip;
  return Object.assign(o, extra || {});
}
const TF = { formatter: '@fmt' };
const mv = (data, dx, dy) => ({ op: 'move', chart: 0, data, d: [dx || 0, dy || 0] });
const CASES = [
  // ---------------- 1. an axis' own pointer ----------------
  {
    id: 'own-root-none', note: 'tooltip trigger none, the root axisPointer show true with snap and a label (scatter-nutrients-matrix): '
      + 'both axes collected, both snap, both labels shown, and the axis tooltip shows their rows',
    charts: [scatter({ axisPointer: { show: true, snap: true, label: { show: true } } }, Object.assign({ trigger: 'none' }, TF))],
    steps: [mv([0, 5.2, 5.9]), mv([0, 7.6, 4.3]), mv([0, 7.6, 4.3], 1, 0), mv([0, 1, 9]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-x-item', note: 'an item tooltip and the x axis\' own show: the pointer on x alone, its rows in an axis tooltip over '
      + 'empty space; over a point the item tooltip wins',
    charts: [scatter({ xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true } } }, Object.assign({}, TF))],
    steps: [mv([0, 4.8, 8]), mv([0, 5, 6]), mv([0, 2.2, 8]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-trigger-false', note: 'x: show with triggerTooltip false (no rows: a value axis that neither snaps nor triggers); '
      + 'y: show -- its rows alone in the box',
    charts: [scatter({
      xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true, triggerTooltip: false } },
      yAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true } },
    }, Object.assign({ trigger: 'none' }, TF))],
    steps: [mv([0, 5.3, 6.2]), mv([0, 2.4, 2.7]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-category', note: 'a category axis\' own show under a none tooltip: no snap, the rows of the category (involveSeries)',
    charts: [barLine(Object.assign({ trigger: 'none' }, TF), { xAxis: { type: 'category', data: cats, axisPointer: { show: true } } })],
    steps: [mv([0, 1.2, 5]), mv([0, 2.9, 1]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-plus-tooltip-axis', note: 'an axis tooltip (its x) and the y axis\' own show: y collected first, then x; both in the box',
    charts: [barLine(Object.assign({ trigger: 'axis' }, TF), { yAxis: { min: 0, max: 10, axisPointer: { show: true } } })],
    steps: [mv([0, 1, 4.6]), mv([0, 2.2, 1.3]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-link', note: 'two grids, the root show and link xAxisIndex all, a none tooltip: the hovered grid\'s axes and the other '
      + 'grid\'s linked x',
    charts: [{
      animation: false,
      tooltip: Object.assign({ trigger: 'none' }, TF),
      axisPointer: { show: true, link: [{ xAxisIndex: 'all' }] },
      grid: [{ left: 40, width: 220, top: 40, bottom: 40 }, { left: 340, width: 220, top: 40, bottom: 40 }],
      xAxis: [{ gridIndex: 0, min: 0, max: 10 }, { gridIndex: 1, min: 0, max: 10 }],
      yAxis: [{ gridIndex: 0, min: 0, max: 10 }, { gridIndex: 1, min: 0, max: 10 }],
      series: [{ type: 'scatter', xAxisIndex: 0, yAxisIndex: 0, data: SC }, { type: 'scatter', xAxisIndex: 1, yAxisIndex: 1, data: [[3, 7], [6, 2]] }],
    }],
    steps: [mv([0, 5.4, 5.8]), mv([1, 3.1, 6.6]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-no-tooltip', note: 'no tooltip component: the root show draws both pointers, nothing else',
    charts: [scatter({ axisPointer: { show: true } })],
    steps: [mv([0, 5.2, 5.9]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-auto', note: 'show \'auto\' on the axis, an item tooltip: not collected',
    charts: [scatter({ xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: 'auto' } } }, Object.assign({}, TF))],
    steps: [mv([0, 4.8, 8]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-label', note: 'the y axis\' own show with a label template, a function label on x, a dashed red line, no tooltip trigger',
    charts: [scatter({
      xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true, label: { formatter: '@ptrfmt' } } },
      yAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true, lineStyle: { color: '#f00' }, label: { formatter: '{value} kg', precision: 1 } } },
    }, Object.assign({ trigger: 'none' }, TF))],
    steps: [mv([0, 5.2, 5.9]), mv([0, 5.2, 5.9], 0, 1), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-shadow', note: 'a category axis\' own shadow pointer, its label off, an item tooltip',
    charts: [barLine(Object.assign({}, TF), { xAxis: { type: 'category', data: cats, axisPointer: { show: true, type: 'shadow', label: { show: false } } } })],
    steps: [mv([0, 1, 9]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-snap-no-trigger', note: '[r2v] x: show with triggerTooltip false and snap true -- involveSeries by the snap alone: '
      + 'the pointer snaps to a point\'s x, its rows stay out of the box; y: show, its rows in the box',
    charts: [scatter({
      xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true, triggerTooltip: false, snap: true } },
      yAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true } },
    }, Object.assign({ trigger: 'none' }, TF))],
    steps: [mv([0, 5.3, 6.2]), mv([0, 2.4, 2.7]), { op: 'leave', chart: 0 }],
  },
  {
    id: 'own-show-truthy', note: '[r2v] show written as a truthy number (1) on x and a truthy string on y, an item tooltip: '
      + 'both collected as show true',
    charts: [scatter({
      xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: 1 } },
      yAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: 'yes' } },
    }, Object.assign({}, TF))],
    steps: [mv([0, 4.8, 8]), { op: 'leave', chart: 0 }],
  },
  // ---------------- 2. when the tooltip's functions run ----------------
  {
    id: 'calls-item', note: 'an item tooltip with a function formatter, position and valueFormatter: each show calls each once',
    charts: [barLine({ formatter: '@fmt', position: '@pos', valueFormatter: '@vf' })],
    steps: [{ op: 'move', chart: 0, on: [0, 1] }, { op: 'move', chart: 0, on: [0, 1], d: [0, 2] }, { op: 'move', chart: 0, on: [0, 3] },
      { op: 'leave', chart: 0 }],
  },
  {
    id: 'calls-item-vf', note: 'an item tooltip with a valueFormatter and a position, no formatter',
    charts: [barLine({ position: '@pos', valueFormatter: '@vf' })],
    steps: [{ op: 'move', chart: 0, on: [0, 1] }, { op: 'move', chart: 0, on: [0, 1], d: [0, 2] }, { op: 'leave', chart: 0 }],
  },
  {
    id: 'calls-axis', note: 'an axis tooltip: the formatter only when the content changes, the position and the valueFormatter '
      + 'every show',
    charts: [barLine({ trigger: 'axis', formatter: '@fmt', position: '@pos', valueFormatter: '@vf' })],
    steps: [mv([0, 1, 5]), mv([0, 1, 5], 3, 0), mv([0, 2, 5]), mv([0, 1, 5]), { op: 'leave', chart: 0 }, mv([0, 1, 5])],
  },
  {
    id: 'calls-axis-keep', note: 'an axis tooltip kept across a setOption: the keep timer shows it again, new values are new content',
    charts: [barLine({ trigger: 'axis', formatter: '@fmt', position: '@pos' })],
    steps: [mv([0, 1, 5]), { op: 'setOption', chart: 0, option: { series: [{ data: [4, 6, 3, 7] }, { data: [2, 5, 4, 3] }] } },
      { op: 'idle', chart: 0, ms: 0 }, { op: 'setOption', chart: 0, option: { title: { text: 't' } } }, { op: 'idle', chart: 0, ms: 0 }],
  },
  {
    id: 'calls-delay', note: 'showDelay: the formatter and the position wait for the delay, a second move before it replaces the show',
    charts: [barLine({ formatter: '@fmt', position: '@pos', showDelay: 50 })],
    steps: [{ op: 'move', chart: 0, on: [0, 1] }, { op: 'move', chart: 0, on: [0, 3] }, { op: 'idle', chart: 0, ms: 60 },
      { op: 'leave', chart: 0 }],
  },
  {
    id: 'calls-delay-vf', note: 'showDelay and a valueFormatter: the markup is built when the show is tried -- each move calls it, the delay does not',
    charts: [barLine({ valueFormatter: '@vf', position: '@pos', showDelay: 50 })],
    steps: [{ op: 'move', chart: 0, on: [0, 1] }, { op: 'move', chart: 0, on: [0, 3] }, { op: 'idle', chart: 0, ms: 60 },
      { op: 'leave', chart: 0 }],
  },
  // ---------------- 3. a pointer label's function (R2-I8) ----------------
  {
    id: 'calls-ptrfmt', note: 'no tooltip, the x axis own pointer with a function label: BaseAxisPointer.render runs it when the '
      + 'value or the status changed, once more after the first show (the graphicKey change clears _lastValue), and on a '
      + 'full update (forceRender)',
    charts: [scatter({ xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true, label: { formatter: '@ptrfmt' } } } })],
    steps: [mv([0, 5.2, 5.9]), mv([0, 5.2, 5.9], 0, 1), mv([0, 5.2, 5.9], 0, 2), mv([0, 5.2, 5.9], 0, 3), mv([0, 7, 5.9]),
      mv([0, 7, 5.9], 0, 1), { op: 'leave', chart: 0 }, mv([0, 7, 5.9]), { op: 'setOption', chart: 0, option: { title: { text: 't' } } },
      mv([0, 7, 5.9], 0, 1), { op: 'leave', chart: 0 }],
  },
  {
    id: 'calls-ptrfmt-tip', note: 'the same under a tooltip with trigger none: the axis tooltip header asks the label once per show besides',
    charts: [scatter({ xAxis: { type: 'value', min: 0, max: 10, axisPointer: { show: true, label: { formatter: '@ptrfmt' } } } },
      { trigger: 'none' })],
    steps: [mv([0, 5.2, 5.9]), mv([0, 5.2, 5.9], 0, 1), mv([0, 5.2, 5.9], 0, 2), mv([0, 7, 5.9]), { op: 'leave', chart: 0 },
      mv([0, 7, 5.9])],
  },
];

// an integer point over a series item (tooltip-keep.js)
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

const TYPES = ['updateaxispointer', 'showtip', 'hidetip', 'updated'];
function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  CALLS = null;
  const charts = def.charts.map(() => newChart());
  const watch = [];
  const log = [];
  try {
    charts.forEach((c, i) => {
      c.setOption(materialize(clone(def.charts[i])));
      frame(c);
      watch.push(watchTooltip(c));
      for (const t of TYPES) c.on(t, e => log.push([i, t, jsonOf(e)]));
    });
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      CALLS = {};
      const rec = { op: st.op };
      if (st.chart !== undefined) rec.chart = st.chart;
      const ch = st.chart !== undefined ? charts[st.chart] : null;
      let at = st.at;
      if (st.data) {
        const p = ch.convertToPixel({ gridIndex: st.data[0] }, [st.data[1], st.data[2]]);
        at = [Math.round(p[0]), Math.round(p[1])];
      } else if (st.on) at = pointOn(ch, st.on[0], st.on[1], def.id);
      if (at && st.d) at = [at[0] + st.d[0], at[1] + st.d[1]];
      if (at) rec.at = at;
      if (st.op === 'move' || st.op === 'leave') advanceClock(NOW + STEP_DT);
      const hd = ch ? ch.getZr().handler : null;
      if (st.op === 'move') hd.mousemove(rawEvent('mousemove', at[0], at[1]));
      else if (st.op === 'leave') hd.mouseout(rawEvent('mouseout', W + 50, H / 2));
      else if (st.op === 'setOption') {
        rec.option = plain(st.option, 0);
        rec.notMerge = false;
        ch.setOption(materialize(clone(st.option)));
      } else if (st.op === 'idle') {
        rec.ms = st.ms;
        advanceClock(NOW + st.ms);
      } else throw new OracleError('op ' + st.op);
      charts.forEach(frame);
      rec.events = log.slice();
      rec.state = charts.map((c, i) => stateOf(c, watch[i]));
      rec.calls = { fmt: CALLS.fmt || 0, pos: CALLS.pos || 0, vf: CALLS.vf || 0, ptrfmt: CALLS.ptrfmt || 0 };
      steps.push(rec);
      CALLS = null;
    }
    return { id: def.id, note: def.note, charts: def.charts.map(o => ({ option: plain(o, 0) })), steps };
  } finally {
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
  const tip = st => st.state[0].tip;
  const ax = (st, key) => st.state[0].axes.find(a => a.key === key);
  const rn = cs('own-root-none');
  guard('rn-both', ax(rn.steps[0], 'x0').status === 'show' && ax(rn.steps[0], 'y0').status === 'show'
    && ax(rn.steps[0], 'x0').draw.label !== null, 'trigger none and the root show: both axes shown, labels on');
  guard('rn-tip', tip(rn.steps[0]).visible && tip(rn.steps[0]).which.indexOf('axis:') === 0, 'the axis tooltip shows');
  guard('rn-fmt-each', rn.steps[2].calls.fmt === 1,
    'a move to the same content: the tooltip\'s own record forgot the last dataByCoordSys, the formatter runs');
  const xi = cs('own-x-item');
  guard('xi-axis', tip(xi.steps[0]).visible && tip(xi.steps[0]).which.indexOf('axis:') === 0 && !ax(xi.steps[0], 'y0'),
    'x alone, an axis tooltip over empty space');
  guard('xi-item', tip(xi.steps[1]).which === 'item:0:1', 'over a point: the item');
  const tf = cs('own-trigger-false');
  guard('tf-y', tip(tf.steps[0]).visible && tip(tf.steps[0]).which.indexOf('@x') < 0 && ax(tf.steps[0], 'x0').sdi.length === 0,
    'x does not trigger: y\'s rows alone');
  const au = cs('own-auto');
  guard('au-none', !ax(au.steps[0], 'x0'), 'show auto: not collected');
  const sn = cs('own-snap-no-trigger');
  guard('sn-snap', ax(sn.steps[0], 'x0').involveSeries && ax(sn.steps[0], 'x0').valueText === '5'
    && tip(sn.steps[0]).visible && tip(sn.steps[0]).which.indexOf('@x') < 0,
    'snap without trigger: x snaps to the point (5), its rows stay out of the box');
  const st = cs('own-show-truthy');
  guard('st-both', ax(st.steps[0], 'x0').status === 'show' && ax(st.steps[0], 'y0').status === 'show',
    'a truthy show that is no boolean: both collected');
  const nt = cs('own-no-tooltip');
  guard('nt-drawn', ax(nt.steps[0], 'x0').status === 'show' && nt.steps[0].state[0].tip === null, 'no tooltip component, pointers drawn');
  const ci = cs('calls-item');
  guard('ci-each', ci.steps[0].calls.fmt === 1 && ci.steps[1].calls.fmt === 1 && ci.steps[0].calls.pos === 1, 'an item show: one call each');
  const ca = cs('calls-axis');
  guard('ca-vf', ca.steps[0].calls.vf === 2 && ca.steps[1].calls.fmt === 1, 'an axis show: the valueFormatter per row, the formatter each move');
  const ck = cs('calls-axis-keep');
  guard('ck-same', ck.steps[2].calls.fmt === 1 && ck.steps[4].calls.fmt === 0 && ck.steps[4].calls.pos === 1,
    'kept: new values call the formatter, the same ones only the position');
  const ol = cs('own-link');
  guard('ol-linked', ax(ol.steps[0], 'x1').status === 'show', 'the other grid\'s x is linked');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

const NOTES = [
  'Pointer steps: zrender Handler mousemove / mouseout from outside the canvas; each ' + STEP_DT
    + ' ms after the last; a frame of every chart after every step. A move\'s point: `data` through convertToPixel, '
    + 'rounded, or a point over a series item (`on`), then moved by `d`.',
  'TooltipRichContent.getSize answers ' + SIZE.join(' x ') + '; box is the moveTo argument.',
  'calls: per step, how many times each counting function ran (the frame after the step included).',
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
  must(nul < 0, 'the fixture holds a \\u0000');
  JSON.parse(json1);
  const g2 = generate();
  json2 = JSON.stringify(plain(Object.assign({}, out, { cases: g2, guards: anchors(g2) }), 0), null, 1) + '\n';
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
if (process.env.ORACLE_DUMP2) fs.writeFileSync(process.env.ORACLE_DUMP2, json2);
const bad = guards.filter(gd => !gd.ok);
guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': ' + gd.what));
const deterministic = json1 === json2;
console.log(g1.length + ' cases, ' + g1.reduce((n, c) => n + c.steps.length, 0) + ' steps; '
  + (guards.length - bad.length) + '/' + guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; '
  + json1.length + ' bytes; ' + logged.length + ' console messages'
  + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
