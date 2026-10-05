/*
Upstream's own answers for the TOOLTIP'S FINISHING TOUCHES -- roadmap B5,
batch 100: where the box goes (tooltip.position in its four forms, align /
verticalAlign, confine), when it shows and hides (showDelay, hideDelay,
alwaysShowContent), that there is no tooltip without a tooltip component,
and what the box says over a marker, a heatmap cell, a sunburst sector, a
treemap rectangle and a sankey node or edge.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false`. Charts
are created with ssr: true and then chart._ssr = false (the browser's model).
TooltipView refuses to run under node, so for the whole script env.node is
switched off and getDom answers an empty object on the chart prototype (the
recipe of series-text.js / handlers.js): the view then builds its richText
content on the zrender canvas. Pointer events go straight to zrender's
Handler ({zrX, zrY} integers); a leave is Handler.mouseout from outside the
canvas (zrender's mouseout then globalout).

THE CLOCK IS FAKE. setTimeout / clearTimeout are replaced for the whole run
by a queue on a virtual millisecond clock; `wait` steps advance it, running
every callback due in time order (ties in creation order). Nothing else in
the run schedules a timer (no animation loop runs under ssr: true).

  node tools/advchart-oracle/tooltip-finish.js

writes tests/fixtures/advchart-tooltip-finish.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions are the 16 hex digits of the IEEE double
(big-endian); counts, flags and option values are plain JSON.

Top level: source, version, W, H, notes[], component[], position[],
timers[], content[], guards[].

component[]: id, note, option, at [x, y] (a bar's centre, rounded), shown
  (was a tooltip box visible after the move).

position[]: id, note, option (tooltip.renderMode is whatever the case wrote;
  absent means 'auto'), trigger 'item' | 'axis', at [x, y] (the pointer),
  size [w, h] (TooltipRichContent.getSize answers these instead of measuring),
  hit {seriesIndex, dataIndex} | null, rect [x, y, w, h] hex | null (the
  element's bounding rect in global space, as _updatePosition builds it),
  border (the content's borderWidth option, as calcTooltipPosition reads it),
  calls[] (a position FUNCTION's arguments: point, rect, viewSize,
  contentSize, params {seriesIndex, dataIndex} or a list of them), result
  [x, y] hex (what TooltipRichContent.moveTo was given: the box's top-left).
  A '@Name' in the option is a JS function in the run (see HANDLERS).

timers[]: id, note, option, steps[]: each {t (the clock after the step),
  type 'move' | 'leave' | 'wait', at [x, y] (move / leave)}; after each step
  {visible (the content element is shown), show (TooltipRichContent._show),
  which ('item:<seriesIndex>:<dataIndex>', 'axis:<category>' or null: the
  content's datum), anchor [x, y] (the pointer point the shown box was
  placed from)}.

content[]: id, note, option, at [x, y], hit {componentType, seriesType,
  seriesIndex, dataIndex, dataType}, template (a string formatter is in
  force), lines[] ({marker: 'item' | 'subItem' | null, name, value}: the
  richText lines, a header being a line with a name only, a blank line all
  null), text (the visible text, segments stripped), border (the box's
  border colour as a string).

Guards (any failure: nothing is written, exit 1): expectations read off the
source -- see guards(); and the whole fixture is generated twice
(byte-identical).
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tooltip-finish.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
Math.random = function () { return 0; };

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// ---------------------------------------------------------------------------
// the fake clock
// ---------------------------------------------------------------------------
let now = 0;
let timerSeq = 0;
const queue = [];
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  queue.push({ id, at: now + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  const i = queue.findIndex(t => t.id === id);
  if (i >= 0) queue.splice(i, 1);
};
function advance(t) {
  must(t >= now, 'the clock runs backwards');
  for (;;) {
    queue.sort((a, b) => a.at - b.at || a.id - b.id);
    if (!queue.length || queue[0].at > t) break;
    const k = queue.shift();
    now = k.at;
    k.fn();
  }
  now = t;
}
function resetClock() {
  queue.length = 0;
  now = 0;
}

// ---------------------------------------------------------------------------
// charts with a live TooltipView
// ---------------------------------------------------------------------------
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
(function enableTooltips() {
  const probe = newChart();
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

// ECData lives in a makeInner store ('__ec_inner_<n>') on every element
let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object'
        && ('dataIndex' in v || 'componentMainType' in v) && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
// the first ECData with a dataIndex up the host / parent chain (findEventDispatcher)
function dispatcherOf(el) {
  for (let e = el; e; e = e.__hostTarget || e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return d;
  }
  return null;
}
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function contentOf(chart) {
  const v = tooltipView(chart);
  return v ? v._tooltipContent : null;
}
const visible = c => !!(c && c.el && !c.el.ignore && !c.el.invisible);
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
// an integer point whose hover dispatcher matches `match`, searched outward
// from the matching element's centre
function pointOn(chart, match, where) {
  const els = chart.getZr().storage.getDisplayList(true);
  const h = chart.getZr().handler;
  for (const el of els) {
    const d = dispatcherOf(el);
    if (!d || !match(d)) continue;
    const r = globalRect(el);
    const cx = Math.round(r.x + r.width / 2);
    const cy = Math.round(r.y + r.height / 2);
    const R = Math.ceil(Math.max(r.width, r.height) / 2) + 1;
    for (let rad = 0; rad <= R; rad++) {
      for (let dx = -rad; dx <= rad; dx++) {
        for (let dy = -rad; dy <= rad; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
          const x = cx + dx;
          const y = cy + dy;
          if (x < 1 || y < 1 || x > W - 2 || y > H - 2) continue;
          // the neighbourhood too, so a pixel of disagreement on an edge does not matter
          let ok = true;
          for (const [ox, oy] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const t = h.findHover(x + ox, y + oy).target;
            const td = dispatcherOf(t);
            if (!td || !match(td)) { ok = false; break; }
          }
          if (ok) return [x, y];
        }
      }
    }
  }
  throw new OracleError(where + ': no point on the target');
}
// a marker's ECData carries its marker model as dataModel; a series item's none
const markerType = d => (d.dataModel && d.dataModel.mainType !== 'series' ? d.dataModel.mainType : null);
const sameItem = (si, di, dt) => d => d.seriesIndex === si && d.dataIndex === di
  && (d.dataType && d.dataType !== 'main' ? d.dataType : null) === (dt || null) && !markerType(d);
const sameMarker = (type, si, di) => d => markerType(d) === type && d.seriesIndex === si && d.dataIndex === di;

// ---------------------------------------------------------------------------
// named handlers (the '@Name' of the Pascal side)
// ---------------------------------------------------------------------------
let calls = [];
function paramsKey(p) {
  if (Array.isArray(p)) return p.map(paramsKey);
  return { seriesIndex: p.seriesIndex, dataIndex: p.dataIndex };
}
function recordCall(point, params, dom, rect, size) {
  calls.push({
    point: point.map(hex),
    params: paramsKey(params),
    rect: rect ? [rect.x, rect.y, rect.width, rect.height].map(hex) : null,
    viewSize: size.viewSize.map(hex),
    contentSize: size.contentSize.map(hex)
  });
}
const HANDLERS = {
  // an array of numbers worked out of every argument
  '@PosArgs': (point, params, dom, rect, size) => {
    recordCall(point, params, dom, rect, size);
    return [point[0] - size.contentSize[0] / 2, rect ? rect.y - size.contentSize[1] : point[1] - 10];
  },
  '@PosPct': (point, params, dom, rect, size) => {
    recordCall(point, params, dom, rect, size);
    return ['10%', '50%'];
  },
  '@PosTop': (point, params, dom, rect, size) => {
    recordCall(point, params, dom, rect, size);
    return 'top';
  },
  '@PosBox': (point, params, dom, rect, size) => {
    recordCall(point, params, dom, rect, size);
    return { right: 10, bottom: '10%' };
  },
  '@PosNull': (point, params, dom, rect, size) => {
    recordCall(point, params, dom, rect, size);
    return null;
  },
  '@PosFar': (point, params, dom, rect, size) => {
    recordCall(point, params, dom, rect, size);
    return [size.viewSize[0] - 5, -30];
  },
};
function bind(o) {
  if (Array.isArray(o)) return o.map(bind);
  if (o && typeof o === 'object') {
    const r = {};
    for (const k of Object.keys(o)) r[k] = bind(o[k]);
    return r;
  }
  if (typeof o === 'string' && Object.prototype.hasOwnProperty.call(HANDLERS, o)) return HANDLERS[o];
  return o;
}

// ---------------------------------------------------------------------------
// fixtures
// ---------------------------------------------------------------------------
const CATS = ['A', 'B', 'C', 'D'];
function bars(tooltip, extra) {
  const o = Object.assign({ animation: false,
    xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', min: 0, max: 100 },
    series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80] }] }, extra || {});
  if (tooltip !== undefined) o.tooltip = tooltip;
  return o;
}
// a bar's centre, rounded (the port's pointer is an integer)
function barPoint(chart, k) {
  const v = chart.getModel().getSeriesByIndex(0).getData().get('y', k);
  const p = chart.convertToPixel({ seriesIndex: 0 }, [k, v / 2]);
  return [Math.round(p[0]), Math.round(p[1])];
}

// ---- 1. no tooltip without a tooltip component ----
const COMPONENT = [
  { id: 'cmp-none', note: 'no tooltip key at all', tooltip: undefined },
  { id: 'cmp-empty', note: 'tooltip: {}', tooltip: {} },
  { id: 'cmp-array-empty', note: 'tooltip: [] -- no component', tooltip: [] },
  { id: 'cmp-array-one', note: 'tooltip: [{}]', tooltip: [{}] },
  { id: 'cmp-show-false', note: 'tooltip: {show: false}', tooltip: { show: false } },
  { id: 'cmp-string', note: "tooltip: 'abc' at the root -- no component", tooltip: 'abc' },
  { id: 'cmp-null', note: 'tooltip: null', tooltip: null },
  { id: 'cmp-series-only', note: 'a series tooltip and no root one', tooltip: undefined,
    extra: { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], tooltip: { show: true, formatter: 'x' } }] } },
];

// ---- 2. where the box goes ----
const RT = { renderMode: 'richText' };
const POSITION = [
  // the default: refixTooltipPosition, gap 20, the +2 on the horizontal test
  { id: 'pos-default', note: 'no position: 20 down and right of the pointer', tooltip: RT, at: { bar: 1 }, size: [120, 50] },
  { id: 'pos-flip-x', note: 'no position, too wide for the right: flipped left', tooltip: RT, at: { bar: 3 }, size: [200, 50] },
  { id: 'pos-flip-y', note: 'no position, too tall below: flipped up', tooltip: RT, at: { bar: 0, dy: 18 }, size: [100, 120] },
  { id: 'pos-plus2', note: 'x + w + 20 fits exactly, + 2 does not: flipped', tooltip: RT, at: { pt: [479, 200] }, size: [100, 40] },
  { id: 'pos-plus2-fits', note: 'x + w + 22 = 600: fits', tooltip: RT, at: { pt: [478, 200] }, size: [100, 40] },
  { id: 'pos-oversized', note: 'a box wider than the view: flipped, then confined to x 0', tooltip: RT, at: { bar: 1 }, size: [700, 50] },
  // confine
  { id: 'conf-rt-null', note: "renderMode 'richText', confine unset: confined", tooltip: { renderMode: 'richText', position: [550, 380] }, at: { bar: 1 }, size: [100, 50] },
  { id: 'conf-auto-null', note: "renderMode unset ('auto'), confine unset: NOT confined", tooltip: { position: [550, 380] }, at: { bar: 1 }, size: [100, 50] },
  { id: 'conf-false', note: 'confine false', tooltip: { renderMode: 'richText', confine: false, position: [550, 380] }, at: { bar: 1 }, size: [100, 50] },
  { id: 'conf-true', note: 'confine true, renderMode auto', tooltip: { confine: true, position: [-40, -30] }, at: { bar: 1 }, size: [100, 50] },
  { id: 'conf-default-edge', note: 'confined after the flip: a box taller than the room above', tooltip: RT, at: { bar: 0 }, size: [100, 380] },
  // an array
  { id: 'arr-px', note: 'position [10, 20]', tooltip: { renderMode: 'richText', position: [10, 20] }, at: { bar: 1 }, size: [120, 50] },
  { id: 'arr-pct', note: "position ['50%', '10%']", tooltip: { renderMode: 'richText', position: ['50%', '10%'] }, at: { bar: 2 }, size: [120, 50] },
  { id: 'arr-words', note: "position ['center', 'middle'] (parsePercent's words)", tooltip: { renderMode: 'richText', position: ['center', 'middle'] }, at: { bar: 0 }, size: [120, 50] },
  { id: 'arr-text', note: "position ['30px', ' 25% '] (parseFloat, a trimmed %)", tooltip: { renderMode: 'richText', position: ['30px', ' 25% '] }, at: { bar: 0 }, size: [120, 50] },
  { id: 'arr-axis', note: 'position [100, 60] under an axis trigger', tooltip: { renderMode: 'richText', trigger: 'axis', position: [100, 60] }, at: { pt: [250, 200] }, size: [120, 50], trigger: 'axis' },
  // a string around the element
  { id: 'str-inside', note: "position 'inside'", tooltip: { renderMode: 'richText', position: 'inside' }, at: { bar: 2 }, size: [80, 40] },
  { id: 'str-top', note: "position 'top'", tooltip: { renderMode: 'richText', position: 'top' }, at: { bar: 2 }, size: [80, 40] },
  { id: 'str-bottom', note: "position 'bottom'", tooltip: { renderMode: 'richText', position: 'bottom' }, at: { bar: 1 }, size: [80, 40] },
  { id: 'str-left', note: "position 'left'", tooltip: { renderMode: 'richText', position: 'left' }, at: { bar: 2 }, size: [80, 40] },
  { id: 'str-right', note: "position 'right' with borderWidth 3 (offset ceil(3 sqrt 2) + 8)", tooltip: { renderMode: 'richText', position: 'right', borderWidth: 3 }, at: { bar: 1 }, size: [80, 40] },
  { id: 'str-unknown', note: "position 'middle': no case matches, (0, 0)", tooltip: { renderMode: 'richText', position: 'middle' }, at: { bar: 1 }, size: [80, 40] },
  { id: 'str-axis', note: "position 'top' under an axis trigger: no element, the default", tooltip: { renderMode: 'richText', trigger: 'axis', position: 'top' }, at: { pt: [250, 200] }, size: [80, 40], trigger: 'axis' },
  { id: 'str-series', note: "the series' position 'bottom' over the global 'top'", tooltip: { renderMode: 'richText', position: 'top' }, at: { bar: 2 }, size: [80, 40],
    extra: { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], tooltip: { position: 'bottom' } }] } },
  // [added for a surviving mutant] a null at the series level falls through to the global (Model.get)
  { id: 'str-null-falls-through', note: "the series' position null: the global 'top' (a null falls through)", tooltip: { renderMode: 'richText', position: 'top' }, at: { bar: 2 }, size: [80, 40],
    extra: { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], tooltip: { position: null } }] } },
  { id: 'str-item', note: "a data item's position 'left' over the series' and the global", tooltip: { renderMode: 'richText', position: 'top' }, at: { bar: 2 }, size: [80, 40],
    extra: { series: [{ type: 'bar', name: 'Sales', data: [20, 40, { value: 60, tooltip: { position: 'left' } }, 80], tooltip: { position: 'bottom' } }] } },
  // an object: getLayoutRect, align ignored
  { id: 'obj-lt', note: 'position {left: 10, top: 10}', tooltip: { renderMode: 'richText', position: { left: 10, top: 10 } }, at: { bar: 1 }, size: [120, 50] },
  { id: 'obj-rb', note: "position {right: 10, bottom: '10%'}", tooltip: { renderMode: 'richText', position: { right: 10, bottom: '10%' } }, at: { bar: 1 }, size: [120, 50] },
  { id: 'obj-centre', note: "position {left: 'center', top: 'middle'}", tooltip: { renderMode: 'richText', position: { left: 'center', top: 'middle' } }, at: { bar: 1 }, size: [120, 50] },
  { id: 'obj-right-word', note: "position {left: 'right', top: 'bottom'}", tooltip: { renderMode: 'richText', position: { left: 'right', top: 'bottom' } }, at: { bar: 1 }, size: [120, 50] },
  { id: 'obj-empty', note: 'position {} (left and top from nothing: 0)', tooltip: { renderMode: 'richText', position: {} }, at: { bar: 1 }, size: [120, 50] },
  { id: 'obj-align', note: "position {left: 100, top: 50} with align 'right': align ignored", tooltip: { renderMode: 'richText', position: { left: 100, top: 50 }, align: 'right', verticalAlign: 'bottom' }, at: { bar: 1 }, size: [120, 50] },
  // align / verticalAlign on the default and on an array
  { id: 'align-default', note: "no position, align 'center', verticalAlign 'middle': no gap, centred", tooltip: { renderMode: 'richText', align: 'center', verticalAlign: 'middle' }, at: { bar: 1 }, size: [120, 50] },
  { id: 'align-right-only', note: "no position, align 'right' only: the vertical gap stays", tooltip: { renderMode: 'richText', align: 'right' }, at: { bar: 2 }, size: [120, 50] },
  { id: 'align-array', note: "position [300, 200], align 'right', verticalAlign 'bottom'", tooltip: { renderMode: 'richText', position: [300, 200], align: 'right', verticalAlign: 'bottom' }, at: { bar: 1 }, size: [120, 50] },
  { id: 'align-string', note: "position 'top', align 'center' (applied after the string's place)", tooltip: { renderMode: 'richText', position: 'top', align: 'center' }, at: { bar: 1 }, size: [80, 40] },
  // a function, by name
  { id: 'fn-args', note: 'a handler answering an array from its arguments', tooltip: { renderMode: 'richText', position: '@PosArgs' }, at: { bar: 1 }, size: [120, 50] },
  { id: 'fn-pct', note: "a handler answering ['10%', '50%']", tooltip: { renderMode: 'richText', position: '@PosPct' }, at: { bar: 2 }, size: [120, 50] },
  { id: 'fn-top', note: "a handler answering 'top'", tooltip: { renderMode: 'richText', position: '@PosTop' }, at: { bar: 2 }, size: [80, 40] },
  { id: 'fn-box', note: "a handler answering {right: 10, bottom: '10%'}", tooltip: { renderMode: 'richText', position: '@PosBox' }, at: { bar: 1 }, size: [120, 50] },
  { id: 'fn-null', note: 'a handler answering null: the default', tooltip: { renderMode: 'richText', position: '@PosNull' }, at: { bar: 1 }, size: [120, 50] },
  { id: 'fn-far', note: 'a handler answering a point off the view: confined', tooltip: { renderMode: 'richText', position: '@PosFar' }, at: { bar: 0 }, size: [120, 50] },
  { id: 'fn-axis', note: 'a handler under an axis trigger: params a list, rect undefined', tooltip: { renderMode: 'richText', trigger: 'axis', position: '@PosArgs' }, at: { pt: [380, 150] }, size: [120, 50], trigger: 'axis',
    extra: { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80] }, { type: 'line', name: 'Cost', data: [10, 30, 50, 70] }] } },
  { id: 'fn-axis-top', note: "a handler answering 'top' under an axis trigger: no element, the default", tooltip: { renderMode: 'richText', trigger: 'axis', position: '@PosTop' }, at: { pt: [380, 150] }, size: [120, 50], trigger: 'axis' },
];

// ---- 3. the timers ----
const TIMERS = [
  { id: 'tm-default', note: 'showDelay 0, hideDelay 100 (the defaults): onto bar 1, off onto nothing, wait',
    tooltip: { renderMode: 'richText' },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 10], ['wait', null, 60], ['wait', null, 109], ['wait', null, 110]] },
  { id: 'tm-hide0', note: 'hideDelay 0: hidden at once',
    tooltip: { renderMode: 'richText', hideDelay: 0 },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 10], ['wait', null, 11]] },
  { id: 'tm-hide-not-rearmed', note: 'off the bar twice: the second hide arms nothing (_show is already false), so the first timer stands',
    tooltip: { renderMode: 'richText' },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 10], ['move', { pt: [310, 30] }, 60], ['wait', null, 109], ['wait', null, 110]] },
  // [added for surviving mutants] a show still waiting when the pointer leaves the canvas; timers due
  // before a move fire before the move is handled
  { id: 'tm-leave-before-show', note: 'showDelay 50, the pointer leaves the canvas at 20: the show still comes at 50 and stays',
    tooltip: { renderMode: 'richText', showDelay: 50 },
    steps: [['move', { bar: 1 }, 0], ['leave', { pt: [300, -1] }, 20], ['wait', null, 49], ['wait', null, 50], ['wait', null, 400]] },
  { id: 'tm-late-move', note: 'the hide armed at 10 is due at 110: a move at 200 over nothing finds the box already gone',
    tooltip: { renderMode: 'richText' },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 10], ['move', { pt: [310, 30] }, 200]] },
  { id: 'tm-late-move-delay', note: 'showDelay 50: a second move at 100 finds the first show done (anchor of the first), and waits again',
    tooltip: { renderMode: 'richText', showDelay: 50 },
    steps: [['move', { bar: 1 }, 0], ['move', { bar: 1, dy: 4 }, 100], ['wait', null, 150]] },
  { id: 'tm-hide-back', note: 'hide pending, back onto another bar before it fires: the show clears it',
    tooltip: { renderMode: 'richText', hideDelay: 100 },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 10], ['move', { bar: 2 }, 50], ['wait', null, 200]] },
  { id: 'tm-show-delay', note: 'showDelay 50: every move restarts the wait; the box shows where the LAST move was',
    tooltip: { renderMode: 'richText', showDelay: 50 },
    steps: [['move', { bar: 1 }, 0], ['move', { bar: 1, dy: 4 }, 30], ['wait', null, 79], ['wait', null, 80], ['move', { bar: 2 }, 100], ['wait', null, 149], ['wait', null, 150]] },
  { id: 'tm-show-then-leave', note: 'showDelay 50, off the bar before it fires: hideLater does nothing (not shown yet) and the box shows at 50 and stays',
    tooltip: { renderMode: 'richText', showDelay: 50 },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 20], ['wait', null, 50], ['wait', null, 400], ['move', { pt: [310, 30] }, 410], ['wait', null, 509], ['wait', null, 510]] },
  { id: 'tm-always', note: 'alwaysShowContent: never hidden, not by nothing and not by leaving the chart',
    tooltip: { renderMode: 'richText', alwaysShowContent: true },
    steps: [['move', { bar: 1 }, 0], ['move', { pt: [300, 30] }, 10], ['wait', null, 500], ['leave', { pt: [300, -1] }, 510], ['wait', null, 900], ['move', { bar: 2 }, 910]] },
  { id: 'tm-leave', note: 'leaving the chart: hidden after hideDelay',
    tooltip: { renderMode: 'richText', hideDelay: 40 },
    steps: [['move', { bar: 1 }, 0], ['leave', { pt: [-1, 200] }, 5], ['wait', null, 44], ['wait', null, 45]] },
  { id: 'tm-axis', note: 'an axis trigger: across categories, out of the grid, hideDelay 100',
    tooltip: { renderMode: 'richText', trigger: 'axis' },
    steps: [['move', { pt: [130, 200] }, 0], ['move', { pt: [400, 200] }, 20], ['move', { pt: [400, 5] }, 30], ['wait', null, 129], ['wait', null, 130]] },
  { id: 'tm-axis-show-delay', note: 'an axis trigger with showDelay 60',
    tooltip: { renderMode: 'richText', trigger: 'axis', showDelay: 60 },
    steps: [['move', { pt: [130, 200] }, 0], ['wait', null, 59], ['wait', null, 60], ['move', { pt: [400, 200] }, 70], ['wait', null, 130]] },
  { id: 'tm-series-delay', note: "a series' showDelay 80 over the global 0 (the item's cascade); hideDelay is the global's",
    tooltip: { renderMode: 'richText', hideDelay: 30 },
    extra: { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], tooltip: { showDelay: 80, hideDelay: 500 } }] },
    steps: [['move', { bar: 1 }, 0], ['wait', null, 79], ['wait', null, 80], ['move', { pt: [300, 30] }, 90], ['wait', null, 119], ['wait', null, 120]] },
];

// ---- 4. what the box says ----
const NESTED = [
  { name: 'Root A', children: [{ name: 'A1', value: 4 }, { name: 'A2', value: 6 }] },
  { name: 'Root B', value: 5, children: [{ name: 'B1', value: 3 }] },
];
const CONTENT = [
  // markers (the global trigger is 'item')
  { id: 'mk-point-max', note: "markPoint {type: 'max', name: 'Max'} on a named bar series",
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { data: [{ type: 'max', name: 'Max' }], itemStyle: { color: '#ff0000' } } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  { id: 'mk-point-coord', note: 'markPoint by coord with a value and no name; an unnamed host series (the auto name heads the box)',
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', data: [20, 40, 60, 80], markPoint: { data: [{ coord: ['B', 70], value: 1234.5 }], itemStyle: { color: '#00aa00' } } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  { id: 'mk-point-novalue', note: 'markPoint by x / y pixels: no value, a name',
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { data: [{ x: 300, y: 100, name: 'Pinned' }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  { id: 'mk-line-average', note: "markLine {type: 'average', name: 'Avg'}",
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markLine: { data: [{ type: 'average', name: 'Avg' }], lineStyle: { color: '#0000ff', width: 4 } } }] }),
    target: { marker: 'markLine', series: 0, index: 0 } },
  { id: 'mk-line-y', note: 'markLine {yAxis: 90}: a value, no name',
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markLine: { data: [{ yAxis: 90 }], lineStyle: { width: 4 } } }] }),
    target: { marker: 'markLine', series: 0, index: 0 } },
  { id: 'mk-area', note: "markArea [{name: 'Zone', yAxis: 85}, {yAxis: 95}]: no value",
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markArea: { data: [[{ name: 'Zone', yAxis: 85 }, { yAxis: 95 }]], itemStyle: { color: '#ffcc00' } } }] }),
    target: { marker: 'markArea', series: 0, index: 0 } },
  { id: 'mk-template', note: "a global template formatter over a markPoint: '{a}|{b}|{c}'",
    option: bars({ renderMode: 'richText', formatter: '{a}|{b}|{c}' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { data: [{ type: 'max', name: 'Max' }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  { id: 'mk-axis-trigger', note: "a global trigger 'axis' over a markPoint outside the grid: no box -- the marker model's default trigger 'item' is not in its option, so the cascade reads the global 'axis'",
    option: bars({ renderMode: 'richText', trigger: 'axis' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { data: [{ x: 300, y: 40, name: 'Pinned', value: 7 }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 }, none: true },
  { id: 'mk-axis-trigger-own', note: "the same with markPoint.tooltip.trigger 'item' written: the marker's box",
    option: bars({ renderMode: 'richText', trigger: 'axis' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { tooltip: { trigger: 'item' }, data: [{ x: 300, y: 40, name: 'Pinned', value: 7 }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  { id: 'mk-own-tooltip', note: "markPoint.tooltip.formatter '{b}!' and a data item's own 'item {c}'",
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { tooltip: { formatter: '{b}!' }, data: [{ x: 200, y: 60, name: 'One', value: 1 }, { x: 400, y: 60, name: 'Two', value: 2, tooltip: { formatter: 'item {c}' } }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 1 } },
  { id: 'mk-own-tooltip-0', note: "the same: item 0 takes markPoint.tooltip's '{b}!'",
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], markPoint: { tooltip: { formatter: '{b}!' }, data: [{ x: 200, y: 60, name: 'One', value: 1 }, { x: 400, y: 60, name: 'Two', value: 2, tooltip: { formatter: 'item {c}' } }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  { id: 'mk-host-tooltip', note: "the host series' tooltip formatter does NOT reach its marker",
    option: bars({ renderMode: 'richText' }, { series: [{ type: 'bar', name: 'Sales', data: [20, 40, 60, 80], tooltip: { formatter: 'host {c}' }, markPoint: { data: [{ x: 300, y: 60, name: 'P', value: 3 }] } }] }),
    target: { marker: 'markPoint', series: 0, index: 0 } },
  // heatmap
  { id: 'hm-named', note: 'a heatmap cell on two category axes, a named series',
    option: { animation: false, tooltip: { renderMode: 'richText' }, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { show: false, min: 0, max: 10, inRange: { color: ['#ffffff', '#ff0000'] } },
      series: [{ type: 'heatmap', name: 'Heat', data: [[0, 0, 5], [1, 0, 1234.5], [2, 1, 9]] }] },
    target: { series: 0, index: 1 } },
  { id: 'hm-unnamed', note: 'a heatmap cell, unnamed series, a cell with a name',
    option: { animation: false, tooltip: { renderMode: 'richText' }, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', data: [[0, 0, 5], { value: [2, 1, 9], name: 'hot' }] }] },
    target: { series: 0, index: 1 } },
  { id: 'hm-value-axes', note: 'a heatmap on value axes is not drawn by upstream (cartesian needs categories); on category x and value y? -- category x / category y with a dash value',
    option: { animation: false, tooltip: { renderMode: 'richText' }, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'H', data: [[0, 0, 3], [1, 1, '-']] }] },
    target: { series: 0, index: 0 } },
  // sunburst
  { id: 'sb-leaf', note: 'a sunburst leaf, a named series',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'sunburst', name: 'Sun', radius: [0, '90%'], data: NESTED }] },
    target: { series: 0, index: 2, name: 'A1' } },
  { id: 'sb-parent', note: 'a sunburst parent without its own value, an unnamed series',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'sunburst', radius: [0, '90%'], data: NESTED }] },
    target: { series: 0, index: 1, name: 'Root A' } },
  // treemap
  { id: 'tm-leaf', note: 'a treemap leaf',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'treemap', name: 'Tree', data: [{ name: 'Big', value: 60 }, { name: 'Small', value: 1234.5 }, { value: 20 }] }] },
    target: { series: 0, index: 2, name: 'Small' } },
  { id: 'tm-noname', note: 'a treemap leaf without a name: the name reads -',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'treemap', name: 'Tree', data: [{ name: 'Big', value: 60 }, { name: 'Small', value: 10 }, { value: 30 }] }] },
    target: { series: 0, index: 3, name: null } },
  { id: 'tm-array', note: 'a treemap leaf whose value is an array [v, extra]',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'treemap', name: 'Tree', data: [{ name: 'Big', value: [60, 7] }, { name: 'Small', value: [20, 3] }] }] },
    target: { series: 0, index: 1, name: 'Big' } },
  // sankey
  { id: 'sk-node', note: 'a sankey node: its layout value (the flow)',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'sankey', name: 'Flow', data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 1234.5 }, { source: 'b', target: 'c', value: 2 }] }] },
    target: { series: 0, index: 0, dataType: 'node' } },
  { id: 'sk-node-own', note: 'a sankey node whose own value is larger than its flow',
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'sankey', name: 'Flow', data: [{ name: 'a', value: 50 }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }, { source: 'b', target: 'c', value: 2 }] }] },
    target: { series: 0, index: 0, dataType: 'node' } },
  { id: 'sk-edge', note: "a sankey edge: 'a -- c'",
    option: { animation: false, tooltip: { renderMode: 'richText' }, series: [{ type: 'sankey', name: 'Flow', data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 30 }, { source: 'b', target: 'c', value: 2 }] }] },
    target: { series: 0, index: 1, dataType: 'edge' } },
];

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function setUp(option) {
  resetClock();
  const chart = newChart();
  chart.setOption(bind(clone(option)));
  frame(chart);
  return chart;
}
function resolveAt(chart, at, where) {
  if (at.pt) return at.pt.slice();
  if (at.bar !== undefined) {
    const p = barPoint(chart, at.bar);
    return [p[0] + (at.dx || 0), p[1] + (at.dy || 0)];
  }
  throw new OracleError(where + ': an unknown point');
}

function runComponent(c) {
  const option = bars(c.tooltip, c.extra);
  const chart = setUp(option);
  try {
    const at = barPoint(chart, 1);
    chart.getZr().handler.mousemove(raw(at[0], at[1]));
    frame(chart);
    return { id: c.id, note: c.note, option, at, shown: visible(contentOf(chart)) };
  } finally {
    chart.dispose();
  }
}

function runPosition(c) {
  const option = bars(c.tooltip, c.extra);
  const chart = setUp(option);
  try {
    const content = contentOf(chart);
    must(content, c.id + ': no tooltip content');
    content.getSize = () => c.size.slice();
    let moved = null;
    const mv = content.moveTo;
    content.moveTo = function (x, y) {
      moved = [x, y];
      return mv.call(this, x, y);
    };
    const view = tooltipView(chart);
    let seenRect = null;
    let seenBorder;
    const up = view._updatePosition;
    view._updatePosition = function (tooltipModel, positionExpr, x, y, cnt, params, el) {
      seenRect = el ? globalRect(el) : null;
      seenBorder = tooltipModel.get('borderWidth');
      return up.apply(this, arguments);
    };
    calls = [];
    const at = resolveAt(chart, c.at, c.id);
    const target = chart.getZr().handler.findHover(at[0], at[1]).target;
    const d = dispatcherOf(target);
    chart.getZr().handler.mousemove(raw(at[0], at[1]));
    frame(chart);
    must(moved, c.id + ': the box was never placed');
    must(visible(content), c.id + ': the box is not shown');
    return { id: c.id, note: c.note, option, trigger: c.trigger || 'item', at, size: c.size,
      hit: c.trigger === 'axis' ? null : (d ? { seriesIndex: d.seriesIndex, dataIndex: d.dataIndex } : null),
      rect: seenRect ? [seenRect.x, seenRect.y, seenRect.width, seenRect.height].map(hex) : null,
      border: seenBorder,
      calls: calls.slice(),
      result: moved.map(hex) };
  } finally {
    chart.dispose();
  }
}

function whichOf(chart, content) {
  if (!visible(content)) return null;
  return lastWhich;
}
let lastWhich = null;
let lastAnchor = null;
function runTimers(c) {
  const option = bars(c.tooltip, c.extra);
  const chart = setUp(option);
  try {
    const content = contentOf(chart);
    must(content, c.id + ': no tooltip content');
    const view = tooltipView(chart);
    lastWhich = null;
    lastAnchor = null;
    const show = view._showTooltipContent;
    view._showTooltipContent = function (tooltipModel, html, params, ticket, x, y) {
      if (Array.isArray(params)) {
        lastWhich = 'axis:' + (params.length ? params[0].axisValue : '');
      } else {
        lastWhich = 'item:' + params.seriesIndex + ':' + params.dataIndex;
      }
      lastAnchor = [x, y];
      return show.apply(this, arguments);
    };
    const up = view._updatePosition;
    view._updatePosition = function (tooltipModel, positionExpr, x, y) {
      lastAnchor = [x, y];
      return up.apply(this, arguments);
    };
    const steps = [];
    for (const [type, at0, t] of c.steps) {
      const st = { t, type };
      if (type !== 'wait') {
        advance(t);
        const at = resolveAt(chart, at0, c.id);
        st.at = at;
        if (type === 'move') chart.getZr().handler.mousemove(raw(at[0], at[1]));
        else chart.getZr().handler.mouseout(raw(at[0], at[1]));
        frame(chart);
      } else {
        advance(t);
        frame(chart);
      }
      st.visible = visible(content);
      st.show = !!content._show;
      st.which = st.visible ? lastWhich : null;
      st.anchor = st.visible && lastAnchor ? lastAnchor.slice() : null;
      steps.push(st);
    }
    return { id: c.id, note: c.note, option, steps };
  } finally {
    chart.dispose();
  }
}

const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function parseLine(line, rich, where) {
  const row = { marker: null, name: null, value: null };
  let last = 0;
  let stage = 0;
  let afterMarker = false;
  const gap = s => { must(!s || (afterMarker && !s.trim()), where + ': text outside a segment ' + JSON.stringify(s)); };
  SEGMENT.lastIndex = 0;
  let m;
  while ((m = SEGMENT.exec(line))) {
    gap(line.slice(last, m.index));
    last = SEGMENT.lastIndex;
    const st = rich[m[1]];
    must(st, where + ': no rich style ' + m[1]);
    let kind;
    if (st.width != null) kind = 0;
    else if (String(st.fontWeight) === '400') kind = 1;
    else if (String(st.fontWeight) === '900') kind = 2;
    else throw new OracleError(where + ': a segment styled ' + JSON.stringify(st));
    must(kind >= stage, where + ': segments out of order');
    stage = kind + 1;
    afterMarker = kind === 0;
    if (kind === 0) row.marker = st.width === 10 ? 'item' : 'subItem';
    else if (kind === 1) row.name = m[2];
    else row.value = m[2];
  }
  gap(line.slice(last));
  return row;
}

function runContent(c) {
  const chart = setUp(c.option);
  try {
    const t = c.target;
    let match;
    if (t.marker) match = sameMarker(t.marker, t.series, t.index);
    else match = sameItem(t.series, t.index, t.dataType);
    const at = pointOn(chart, match, c.id);
    const d = dispatcherOf(chart.getZr().handler.findHover(at[0], at[1]).target);
    const content = contentOf(chart);
    const view = tooltipView(chart);
    let params = null;
    const show = view._showTooltipContent;
    view._showTooltipContent = function (tooltipModel, html, p) {
      params = p;
      return show.apply(this, arguments);
    };
    chart.getZr().handler.mousemove(raw(at[0], at[1]));
    frame(chart);
    if (c.none) {
      must(!visible(content) && params === null, c.id + ': a box');
      return { id: c.id, note: c.note, option: c.option, at, none: true,
        hit: { componentType: null, seriesType: null, seriesIndex: d.seriesIndex, dataIndex: d.dataIndex, dataType: null, mainType: markerType(d) },
        template: false, lines: [], text: '', border: '' };
    }
    must(visible(content), c.id + ': no box');
    must(params && !Array.isArray(params), c.id + ': not an item tooltip');
    if (t.name !== undefined) must(params.name === (t.name === null ? '' : t.name), c.id + ': hovered ' + params.name);
    const text = String(content.el.style.text);
    // a template's text holds no rich segment; the default markup always does
    SEGMENT.lastIndex = 0;
    const template = !SEGMENT.test(text);
    SEGMENT.lastIndex = 0;
    const lines = template ? [] : text.split('\n').map(line => parseLine(line, content.el.style.rich || {}, c.id));
    return { id: c.id, note: c.note, option: c.option, at,
      hit: { componentType: params.componentType, seriesType: params.seriesType, seriesIndex: params.seriesIndex,
        dataIndex: params.dataIndex, dataType: params.dataType === undefined ? null : params.dataType,
        mainType: markerType(d) },
      template, lines, text: text.replace(SEGMENT, '$2'),
      border: String(content.el.style.borderColor) };
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// guards: expectations read off the source
// ---------------------------------------------------------------------------
function guards(g0) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const n = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  const cmp = id => g0.component.find(c => c.id === id);
  const pos = id => g0.position.find(c => c.id === id);
  const tm = id => g0.timers.find(c => c.id === id);
  const ct = id => g0.content.find(c => c.id === id);
  const res = id => pos(id).result.map(n);
  // a tooltip component: only an object, or an array holding one
  guard('no tooltip key: no box', !cmp('cmp-none').shown);
  guard('tooltip: {} shows', cmp('cmp-empty').shown && cmp('cmp-array-one').shown);
  guard("tooltip: [], 'abc', null: no component", !cmp('cmp-array-empty').shown && !cmp('cmp-string').shown && !cmp('cmp-null').shown);
  guard('a series tooltip alone: no component, no box', !cmp('cmp-series-only').shown);
  // refixTooltipPosition: +20 both ways; the +2 on the horizontal test only
  const pd = pos('pos-default');
  guard('the default hangs 20 right and 20 down', res('pos-default')[0] === pd.at[0] + 20 && res('pos-default')[1] === pd.at[1] + 20);
  guard('the +2 flips a box that fits exactly', res('pos-plus2')[0] === 479 - 100 - 20 && res('pos-plus2-fits')[0] === 478 + 20);
  // confine: null resolves on the RAW renderMode
  guard("confine null under 'richText' confines", res('conf-rt-null')[0] === 500 && res('conf-rt-null')[1] === 350);
  guard("confine null under 'auto' does not", res('conf-auto-null')[0] === 550 && res('conf-auto-null')[1] === 380);
  guard('confine true clamps to 0', res('conf-true')[0] === 0 && res('conf-true')[1] === 0);
  // calcTooltipPosition
  guard("an unknown position word with an element is (0, 0)", res('str-unknown')[0] === 0 && res('str-unknown')[1] === 0);
  const sr = pos('str-right');
  guard("'right' offsets by ceil(sqrt2 * borderWidth) + 8", res('str-right')[0] === n(sr.rect[0]) + n(sr.rect[2]) + 13);
  guard("a word under an axis trigger is the default placement", res('str-axis')[0] === pos('str-axis').at[0] + 20);
  // a function's arguments
  guard('an axis handler gets a list of params and no rect', Array.isArray(pos('fn-axis').calls[0].params) && pos('fn-axis').calls[0].rect === null);
  // timers
  const d = tm('tm-default').steps;
  guard('hideDelay 100: shown at 109, hidden at 110', d[3].visible && !d[4].visible);
  const sd = tm('tm-show-delay').steps;
  guard('showDelay restarts on every move', !sd[2].visible && sd[3].visible);
  const sl = tm('tm-show-then-leave').steps;
  guard('a show due after leaving still shows and stays', sl[2].visible && sl[3].visible && !sl[6].visible);
  const nr = tm('tm-hide-not-rearmed').steps;
  guard('a second hide does not re-arm the timer', nr[3].visible && !nr[4].visible);
  const al = tm('tm-always').steps;
  guard('alwaysShowContent survives leaving the chart', al[4].visible);
  // content
  guard('a marker heads its box with the host series name', ct('mk-point-max').lines[0].name === 'Sales');
  guard("the host series' formatter does not reach its marker", !ct('mk-host-tooltip').template && ct('mk-host-tooltip').lines[1].name === 'P');
  guard('a treemap row has no marker and no header', ct('tm-leaf').lines.length === 1 && ct('tm-leaf').lines[0].marker === null);
  guard("a sankey edge reads 'source -- target'", ct('sk-edge').lines[0].name === 'a -- c');
  return g;
}

// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------
function generate() {
  ecKey = null;
  const out = {
    source: DIST, version: echarts.version, W, H,
    notes: [
      'TooltipView under node: env.node off, getDom stubbed; richText content on the zrender canvas.',
      'position: TooltipRichContent.getSize is replaced by the case size; result = the moveTo argument (the box top-left, before the border and shadow offset moveTo adds to the text element).',
      "shouldTooltipConfine: confine != null ? !!confine : the RAW renderMode option === 'richText' (default 'auto': false).",
      'timers: a virtual clock; setTimeout / clearTimeout replaced for the run.',
      'content: the richText lines parsed by segment style (width -> marker, weight 400 -> name, 900 -> value).',
    ],
    component: COMPONENT.map(runComponent),
    position: POSITION.map(runPosition),
    timers: TIMERS.map(runTimers),
    content: CONTENT.map(runContent),
  };
  out.guards = guards(out);
  return out;
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
const deterministic = json1 === json2;
console.log(out1.component.length + ' component, ' + out1.position.length + ' position, ' + out1.timers.length + ' timer, '
  + out1.content.length + ' content cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (process.env.ORACLE_DUMP) console.log(json1);
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
