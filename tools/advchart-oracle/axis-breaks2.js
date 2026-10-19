/*
Upstream's own answers for the AXIS BREAKS batch 132 left out (fix phase
F4a), next to axis-breaks.js, whose fixture this one leaves alone:

  log     `breaks` on a log axis. LogScale keeps two stubs: powStub with the
          breaks as written and intervalStub with them taken into the
          logarithm (parseAxisBreakOptionInwardTransform: the ends through
          the log, an absolute gap as what it spans from the start there,
          `noNegative`); the nice step, the ticks stepping over a break, the
          pruning and the break ends are intervalStub's, in log space; a
          normal tick goes back through logScalePowTick over the stubs'
          extents, a break end through the scale's own lookup -- [log
          extent at the last effective setExtent, then each break's ends at
          2 + idx and 2 + idx + 1, so a second break's start overwrites the
          first one's end: the first one's end comes back as a power].
  single  `breaks` on a singleAxis (createScaleByModel's
          coordSysSupportAxisBreaks): the same scale, the zigzag over the
          single's rect, added to the view's group (not its _axisGroup:
          no groupTransition), the click expanding by singleAxisIndex.
  rotate  the two labels of a break turned by axisLabel.rotate: labelIntersect
          goes past the rects to the oriented boxes (OrientedBoundingRect.
          intersect with the direction -(axis rotation), one way,
          touchThreshold 0), and the MTV moves them apart -- k 0.5 unless a
          side of the label is parallel to the axis.
  params  the `break` a function axisLabel.formatter is handed in its third
          argument ({type 'start' | 'end', start, end} -- the parsed break,
          clamped by the extent) and the `break` ({start, end}) of an axis
          label's click event params (triggerEvent).
  anim    the break areas in the axis' _axisGroup: groupTransition moves
          break_a_* / break_b_* / break_c_* from the old shape to the new by
          anid (updateProps on the axis model) -- a dataZoom over a broken
          y axis, frames sampled; points arrays of different lengths are cut
          or padded (zrender's fillArray).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, TZ=UTC, the global
Date replaced before the dist loads (the clock of full-update-anim.js),
chart._ssr = false and echarts.env.node = false. Math.random is the port's
xorshift32 from TyJitterSeed (2463534242), reset before every chart.
Every chart is 600 x 400. Pointer steps go to zrender's own Handler:
mousemove, mousedown, mouseup and click at integer points.

  node tools/advchart-oracle/axis-breaks2.js

writes tests/fixtures/advchart-axis-breaks2.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions or values are the 16 hex digits of the IEEE double
(big-endian, lowercase). A case: id, group, note, option (as run; a formatter
'@brk' is the recording function below), axes ['y0' | 'x0' | 's0'], series,
steps (as axis-breaks.js: click / action), renders[] -- or, for group anim,
frames[] {t, leaves [{anid, points [[x, y] hex]}]} after the action at t 0.

A render: rect [x, y, w, h] hex (grid 0, or the single's), draws, events
(axisbreakchanged), clicks (the click events' params: componentType,
targetType, value, tickIndex, break), calls (the formatter's calls: value
hex, index, extra), point, axes[]:
  dim, index, type, inverse, extent [2] hex, interval hex, niceExtent,
  breaks[] (the scale's breaks as written: start, end, vmin, vmax hex, type,
    val hex, gapReal hex -- a log axis': powStub's ends, intervalStub's
    gapReal),
  lbreaks[] (a log axis: intervalStub's -- vmin, vmax, val hex),
  lextent [2] hex (a log axis: intervalStub's extent),
  ticks[] {v, b}, rawTicks[], lineTicks[], minor (as axis-breaks.js),
  labels[] {v, b, text, x, y, shown, rot hex},
  splitLines, axisTicks, axisLine, breakAreas (as axis-breaks.js),
  singleSplit[] [x1, y1, x2, y2] hex (a single axis: the lines its split
    lines merged into one path per colour -- SingleAxisView.splitLine's
    mergePath, no anid -- in the order merged).
An anim case with action2 dispatches it right after the sample at at2 (a
second transition starting while the first moves).
series[] {index, type, items [[x, y] hex]}.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-breaks2.json');
echarts.env.node = false;
const W0 = 600;
const H0 = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the random numbers: the port's xorshift32 ----------
const SEED = 2463534242;
let rngState = SEED;
let DRAWS = 0;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  DRAWS++;
  return x / 4294967296;
};

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const nul = s => (s == null ? null : String(s).split('\u0000').join('<NUL>'));
const J = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const payloadRec = p => JSON.parse(nul(JSON.stringify(p, (k, v) => (k.indexOf('__ec_inner') === 0 ? undefined : v))));
const pts = a => a.map(p => [hex(p[0]), hex(p[1])]);
function walk(e, f) {
  f(e);
  if (e.childrenRef) e.childrenRef().forEach(x => walk(x, f));
}

// ---------- the lines mergePath merges ----------
// SingleAxisView.splitLine merges its lines into one path per colour, which
// keeps them only as a Float32 path proxy: the lines are caught as mergePath
// reads them (getUpdatedPathProxy(true) on a Line no group holds).
let MERGED = [];
{
  const L = echarts.graphic.Line.prototype;
  const orig = L.getUpdatedPathProxy;
  must(typeof orig === 'function', 'no getUpdatedPathProxy');
  L.getUpdatedPathProxy = function (inBatch) {
    if (inBatch && !this.parent) MERGED.push(this);
    return orig.apply(this, arguments);
  };
}

// ---------- the formatter ----------
let CALLS = [];
function brkFormatter(value, index, extra) {
  CALLS.push({ value: hex(value), index, extra: extra == null ? null : J(extra) });
  const b = extra && extra.break;
  return String(value) + (b ? ' [' + b.type + ' ' + b.start + '~' + b.end + ']' : '');
}
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = (k === 'formatter' && v[k] === '@brk') ? brkFormatter : materialize(v[k]);
    return o;
  }
  return v;
}

// =====================================================================
// Recording
// =====================================================================
const MAIN = { x: 'xAxis', y: 'yAxis', s: 'singleAxis' };
function axisModelOf(chart, key) {
  const m = chart.getModel().getComponent(MAIN[key[0]], +key.slice(1));
  must(m, 'no axis ' + key);
  return m;
}
function rectOf(chart, key) {
  if (key[0] === 's') return axisModelOf(chart, key).coordinateSystem.getRect();
  return chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
}

function recordAxis(chart, key) {
  const model = axisModelOf(chart, key);
  const axis = model.axis;
  const scale = axis.scale;
  const view = chart.getViewOfComponentModel(model);
  const rec = { dim: axis.dim, index: model.componentIndex, type: axis.type, inverse: !!axis.inverse };
  rec.extent = scale.getExtent().map(hex);
  const isLog = scale.type === 'log';
  const stub = isLog ? scale.intervalStub : scale;
  if (stub.type === 'interval') {
    const cfg = stub.getConfig();
    rec.interval = hex(cfg.interval);
    rec.niceExtent = cfg.niceExtent ? cfg.niceExtent.map(hex) : null;
  } else if (scale.type === 'time') {
    rec.interval = hex(scale._approxInterval);
    rec.niceExtent = null;
  } else {
    rec.interval = null;
    rec.niceExtent = null;
  }
  const brk = isLog ? scale.powStub.brk : scale.brk;
  const lbrk = isLog ? scale.intervalStub.brk : null;
  rec.breaks = (brk ? brk.breaks : []).map((b, k) => ({
    start: J(b.breakOption.start), end: J(b.breakOption.end), vmin: hex(b.vmin), vmax: hex(b.vmax),
    type: b.gapParsed.type, val: hex(b.gapParsed.val), gapReal: hex(lbrk ? lbrk.breaks[k].gapReal : b.gapReal),
  }));
  if (isLog) {
    rec.lbreaks = (lbrk ? lbrk.breaks : []).map(b => ({ vmin: hex(b.vmin), vmax: hex(b.vmax), val: hex(b.gapParsed.val) }));
    rec.lextent = scale.intervalStub.getExtent().map(hex);
  }
  const tk = t => ({ v: hex(t.value), b: t.break ? t.break.type : null });
  rec.ticks = scale.type === 'ordinal' ? [] : scale.getTicks().map(tk);
  rec.rawTicks = scale.type === 'ordinal' ? [] : scale.getTicks({ breakTicks: 'none', pruneByBreak: 'no' }).map(t => hex(t.value));
  rec.lineTicks = scale.type === 'ordinal' ? [] : scale.getTicks({ breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' }).map(t => hex(t.value));
  const wantMinor = model.get(['minorTick', 'show']) || model.get(['minorSplitLine', 'show']);
  rec.minor = wantMinor && scale.type !== 'ordinal' ? axis.getMinorTicksCoords().map(g => g.map(c => hex(c.tickValue))) : null;
  const labelEls = [];
  const splitLines = [];
  const axisTicks = [];
  const axisLine = [];
  const breakAreas = [];
  walk(view.group, e => {
    const anid = e.anid || '';
    if (e.type === 'text' && anid.indexOf('label_') === 0) labelEls.push(e);
    else if (e.type === 'line' && anid.indexOf('line_') === 0) {
      splitLines.push({ v: anid.slice(5), x1: hex(e.shape.x1), y1: hex(e.shape.y1), x2: hex(e.shape.x2), y2: hex(e.shape.y2) });
    } else if (e.type === 'line' && anid.indexOf('ticks_') === 0) {
      axisTicks.push({ v: anid.slice(6), shown: !e.ignore, x1: hex(e.shape.x1), y1: hex(e.shape.y1), x2: hex(e.shape.x2), y2: hex(e.shape.y2) });
    } else if (e.type === 'line' && (anid === 'line' || anid.indexOf('breakLine_') === 0)) {
      axisLine.push({ anid: nul(anid), x1: hex(e.shape.x1), y1: hex(e.shape.y1), x2: hex(e.shape.x2), y2: hex(e.shape.y2) });
    }
  });
  const labelTicks = axis.getViewLabels();
  must(labelEls.length === labelTicks.length || !model.get(['axisLabel', 'show']),
    key + ': ' + labelEls.length + ' label elements, ' + labelTicks.length + ' labels');
  rec.labels = labelEls.map((e, i) => {
    const t = labelTicks[i].tick;
    must(e.anid === 'label_' + t.value, key + ': label ' + i + ' is ' + e.anid);
    return { v: hex(t.value), b: t.break ? t.break.type : null, text: e.style.text, x: hex(e.x), y: hex(e.y),
      shown: !e.ignore, rot: hex(e.rotation) };
  });
  walk(view.group, e => {
    if (e.type !== 'group') return;
    const kids = e.childrenRef();
    const a = kids.find(k => k.type === 'polyline' && (k.anid || '').indexOf('break_a_') === 0);
    if (!a) return;
    const b = kids.find(k => k.type === 'polyline' && (k.anid || '').indexOf('break_b_') === 0);
    const c = kids.find(k => k.type === 'polygon' && (k.anid || '').indexOf('break_c_') === 0);
    breakAreas.push({
      id: nul(a.anid.slice(8)), a: pts(a.shape.points), b: b ? pts(b.shape.points) : null, poly: !!c,
      z: a.z, silent: !!e.silent, stroke: a.style.stroke == null ? null : String(a.style.stroke),
      lineWidth: hex(a.style.lineWidth), lineDash: J(a.style.lineDash),
      fill: c ? String(c.style.fill) : null, opacity: c ? hex(c.style.opacity) : null,
    });
  });
  rec.splitLines = splitLines;
  if (key[0] === 's') rec.singleSplit = MERGED.map(l => [hex(l.shape.x1), hex(l.shape.y1), hex(l.shape.x2), hex(l.shape.y2)]);
  rec.axisTicks = axisTicks;
  rec.axisLine = axisLine;
  rec.breakAreas = breakAreas;
  return rec;
}

function recordSeries(chart, idx) {
  const s = chart.getModel().getSeriesByIndex(idx);
  const data = s.getData();
  const items = [];
  const cs = s.coordinateSystem;
  if (s.subType === 'bar') {
    for (let i = 0; i < data.count(); i++) {
      const l = data.getItemLayout(i);
      items.push(l && l.width != null ? [hex(l.x), hex(l.y), hex(l.width), hex(l.height)] : null);
    }
    return { index: idx, type: s.subType, items };
  }
  const dims = cs.dimensions.map(d => data.mapDimension(d));
  const store = data.getStore();
  for (let i = 0; i < data.count(); i++) {
    const v = dims.map(d => store.get(data.getDimensionIndex(d), i));
    const p = cs.dataToPoint(v.length === 1 ? v[0] : v, null, []);
    items.push([hex(p[0]), hex(p[1])]);
  }
  return { index: idx, type: s.subType, items };
}

function recordRender(chart, c, draws, events, clicks, calls, point) {
  const rect = rectOf(chart, c.axes[0]);
  const r = { rect: [hex(rect.x), hex(rect.y), hex(rect.width), hex(rect.height)], draws, events, clicks, calls };
  if (point) r.point = point;
  r.axes = c.axes.map(k => recordAxis(chart, k));
  r.series = c.series.map(i => recordSeries(chart, i));
  return r;
}

// =====================================================================
// The cases
// =====================================================================
const C5 = ['a', 'b', 'c', 'd', 'e'];
const C7 = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const CASES = [];
function add(group, id, note, option, more) {
  CASES.push(Object.assign({ group, id, note, option: Object.assign({ animation: false }, option), axes: ['y0'], series: [0], steps: [] }, more || {}));
}
const logY = (y, data, extra) => Object.assign({
  xAxis: { type: 'category', data: C5 }, yAxis: Object.assign({ type: 'log' }, y),
  series: [{ type: 'bar', data: data || [1, 30, 950, 4000, 10000] }],
}, extra || {});
const barY = (y, data, extra) => Object.assign({
  xAxis: { type: 'category', data: C5 }, yAxis: Object.assign({ type: 'value' }, y),
  series: [{ type: 'bar', data: data || [10, 30, 950, 40, 1000] }],
}, extra || {});

// ---- log axes
add('log', 'l-one-prct', "a log y axis, a break 50..900 '5%': in log space, the decades stepping over it",
  logY({ breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('log', 'l-abs', 'an absolute gap of 100: log(150) - log(50) in log space', logY({ breaks: [{ start: 50, end: 900, gap: 100 }] }));
add('log', 'l-two', "two breaks, '3%' and 10: the lookup's second start overwrites the first end, which comes back as a power",
  logY({ breaks: [{ start: 200, end: 3000, gap: 10 }, { start: 20, end: 60, gap: '3%' }] }));
add('log', 'l-min-in', 'min 100 inside the break 50..900: the break cut at the extent, its end tick the extent\'s',
  logY({ min: 100, breaks: [{ start: 50, end: 900, gap: '5%' }] }, [120, 300, 950, 4000, 10000]));
add('log', 'l-line-ticks', 'a line, the axis line and ticks shown, minor ticks and split lines',
  { xAxis: { type: 'category', data: C7 }, yAxis: { type: 'log', axisLine: { show: true }, axisTick: { show: true },
    minorTick: { show: true }, minorSplitLine: { show: true }, breaks: [{ start: 40, end: 2000, gap: '6%' }] },
  series: [{ type: 'line', data: [2, 30, 120, 2500, 9000, 35, 20000] }] });
add('log', 'l-base2', 'logBase 2 and a break 8..512', logY({ logBase: 2, breaks: [{ start: 8, end: 512, gap: '5%' }] }, [1, 4, 600, 1000, 2000]));
add('log', 'l-x', 'a log x axis under a scatter', { xAxis: { type: 'log', breaks: [{ start: 30, end: 300, gap: '5%' }] }, yAxis: { type: 'value' },
  series: [{ type: 'scatter', data: [[2, 1], [20, 2], [400, 3], [5000, 4], [10, 5]] }] }, { axes: ['x0'] });
add('log', 'l-click', 'a click on the log axis\' break area expands it',
  logY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }),
  { steps: [{ type: 'click', at: { kind: 'break', axis: 'y0', index: 0, frac: 0.5 } }] });
// [R2-H] the lookup after a dataZoom changes the extent (setExtent2 writes its first two entries again), and the
// break ends that equal the nice extent's ends (the lookup brings them back, as it does any break end)
add('log', 'l-zoom', 'a log y axis with a break under an inside dataZoom: two zooms change the extent, the lookup\'s '
  + 'first two entries follow it, the break ends come back through it',
  logY({ breaks: [{ start: 50, end: 900, gap: '5%' }] }, null,
    { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { steps: [{ type: 'action', payload: { type: 'dataZoom', start: 0, end: 60 } },
    { type: 'action', payload: { type: 'dataZoom', start: 30, end: 90 } },
    { type: 'action', payload: { type: 'dataZoom', start: 0, end: 100 } }] });
add('log', 'l-zoom-x', 'a log x axis with two breaks under an inside dataZoom (start / end values): the second start '
  + 'overwrites the first end in the lookup, the zoom rewrites only the extent\'s two',
  { xAxis: { type: 'log', breaks: [{ start: 20, end: 60, gap: '3%' }, { start: 200, end: 3000, gap: 10 }] },
    yAxis: { type: 'value' }, dataZoom: [{ type: 'inside', xAxisIndex: 0, filterMode: 'none' }],
    series: [{ type: 'scatter', data: [[2, 1], [30, 2], [400, 3], [5000, 4], [9000, 5]] }] },
  { axes: ['x0'], steps: [{ type: 'action', payload: { type: 'dataZoom', startValue: 5, endValue: 4000 } },
    { type: 'action', payload: { type: 'dataZoom', startValue: 25, endValue: 9000 } }] });
add('log', 'l-nice-end', 'a break whose end is the nice extent\'s max (3000..10000, the data to 9000): the end tick '
  + 'and the extent\'s end are the one value through the lookup',
  logY({ breaks: [{ start: 3000, end: 10000, gap: '5%' }] }, [1, 30, 950, 2000, 9000]));
add('log', 'l-nice-start', 'a break whose start is the nice extent\'s min (1..20, the data from 2): the start '
  + 'and the extent\'s start are the one value',
  logY({ breaks: [{ start: 1, end: 20, gap: '5%' }] }, [2, 30, 950, 2000, 9000]));
add('log', 'l-nice-both', 'min and max written onto two breaks\' outer ends (10..30 and 300..1000, min 10, max 1000)',
  logY({ min: 10, max: 1000, breaks: [{ start: 10, end: 30, gap: '5%' }, { start: 300, end: 1000, gap: '5%' }] },
    [20, 40, 95, 200, 900]));
add('log', 'l-nice-zoom', 'the nice-end break under a dataZoom that brings the extent back onto it',
  logY({ breaks: [{ start: 3000, end: 10000, gap: '5%' }] }, [1, 30, 950, 2000, 9000],
    { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { steps: [{ type: 'action', payload: { type: 'dataZoom', start: 50, end: 100 } },
    { type: 'action', payload: { type: 'dataZoom', start: 0, end: 100 } }] });

// ---- single axes
const RIVER = [];
add('single', 's-value', 'a value singleAxis under a scatter, a break 20..80',
  { singleAxis: { type: 'value', breaks: [{ start: 20, end: 80, gap: '5%' }] },
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 10, 90, 95, 100, 15] }] }, { axes: ['s0'] });
add('single', 's-vertical', 'a vertical singleAxis on the left, two breaks',
  { singleAxis: { type: 'value', orient: 'vertical', left: 80, right: 80, breaks: [{ start: 20, end: 40, gap: '5%' }, { start: 60, end: 85, gap: 3 }] },
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 10, 50, 90, 100, 55] }] }, { axes: ['s0'] });
add('single', 's-time', 'a time singleAxis under a themeRiver, a break of a fortnight',
  { useUTC: true, singleAxis: { type: 'time', breaks: [{ start: Date.UTC(2024, 0, 5), end: Date.UTC(2024, 0, 19), gap: '5%' }] },
    series: [{ type: 'themeRiver', data: [
      [Date.UTC(2024, 0, 1), 3, 'p'], [Date.UTC(2024, 0, 3), 4, 'p'], [Date.UTC(2024, 0, 20), 2, 'p'], [Date.UTC(2024, 0, 25), 5, 'p'],
      [Date.UTC(2024, 0, 1), 2, 'q'], [Date.UTC(2024, 0, 3), 1, 'q'], [Date.UTC(2024, 0, 20), 5, 'q'], [Date.UTC(2024, 0, 25), 3, 'q']] }] },
  { axes: ['s0'], series: [] });
add('single', 's-click', 'a click on the single\'s break area expands it (singleAxisIndex)',
  { singleAxis: { type: 'value', breaks: [{ start: 20, end: 80, gap: '10%' }] },
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 10, 90, 95, 100] }] },
  { axes: ['s0'], steps: [{ type: 'click', at: { kind: 'break', axis: 's0', index: 0, frac: 0.5 } }] });
add('single', 's-action', 'expandAxisBreak and toggleAxisBreak by singleAxisIndex',
  { singleAxis: { type: 'value', breaks: [{ start: 20, end: 80, gap: '10%' }] },
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 10, 90, 95, 100] }] },
  { axes: ['s0'], steps: [
    { type: 'action', payload: { type: 'expandAxisBreak', singleAxisIndex: 0, breaks: [{ start: 20, end: 80 }] } },
    { type: 'action', payload: { type: 'toggleAxisBreak', singleAxisIndex: 0, breaks: [{ start: 20, end: 80 }] } }] });

// ---- the labels of a break turned
add('rotate', 'r-x45', 'an x value axis, labels turned 45: the break\'s two labels moved apart along the oriented boxes',
  { yAxis: { type: 'category', data: C5 }, xAxis: { type: 'value', axisLabel: { rotate: 45 }, breaks: [{ start: 50, end: 900, gap: '1%' }] },
    series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] }, { axes: ['x0'] });
add('rotate', 'r-y30', 'a y value axis, labels turned 30', barY({ axisLabel: { rotate: 30 }, breaks: [{ start: 50, end: 900, gap: '1%' }] }));
add('rotate', 'r-x90', 'labels turned 90 on an x axis', { yAxis: { type: 'category', data: C5 },
  xAxis: { type: 'value', axisLabel: { rotate: 90 }, breaks: [{ start: 50, end: 900, gap: '1%' }] },
  series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] }, { axes: ['x0'] });
add('rotate', 'r-x-inverse', 'an inverse x axis, labels turned -40', { yAxis: { type: 'category', data: C5 },
  xAxis: { type: 'value', inverse: true, axisLabel: { rotate: -40 }, breaks: [{ start: 50, end: 900, gap: '1%' }] },
  series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] }, { axes: ['x0'] });
// two labels of very different widths: the oriented boxes' centres no longer
// follow their anchors, so which one of the two MTVs along a box axis is the
// shorter turns on the widths (calcDirMTV's two candidates)
add('rotate', 'r-x-inverse-wide-end', 'an inverse x axis turned -40, the break end\'s label far wider than its start\'s',
  { yAxis: { type: 'category', data: C5 },
    xAxis: { type: 'value', inverse: true, axisLabel: { rotate: -40 }, breaks: [{ start: 5, end: 900000, gap: '1%' }] },
    series: [{ type: 'bar', data: [1, 3, 950000, 4, 1000000] }] }, { axes: ['x0'] });
add('rotate', 'r-x45-wide-start', 'an x axis turned 45, the break start\'s label far wider than its end\'s',
  { yAxis: { type: 'category', data: C5 },
    xAxis: { type: 'value', min: -1000000, axisLabel: { rotate: 45 }, breaks: [{ start: -900000, end: -5, gap: '1%' }] },
    series: [{ type: 'bar', data: [-1, -3, -950000, -4, -1000000] }] }, { axes: ['x0'] });
add('rotate', 'r-y30-wide-end', 'a y axis turned 30, the break end\'s label far wider than its start\'s',
  barY({ axisLabel: { rotate: 30 }, breaks: [{ start: 5, end: 900000, gap: '1%' }] }, [1, 3, 950000, 4, 1000000]));
add('rotate', 'r-x-60-wide-start', 'an x axis turned -60, the break start\'s label far wider than its end\'s',
  { yAxis: { type: 'category', data: C5 },
    xAxis: { type: 'value', min: -1000000, axisLabel: { rotate: -60 }, breaks: [{ start: -900000, end: -5, gap: '1%' }] },
    series: [{ type: 'bar', data: [-1, -3, -950000, -4, -1000000] }] }, { axes: ['x0'] });
add('rotate', 'r-x30-wide','turned 30 with a wide gap: the boxes meet the rect test but not the oriented one',
  { yAxis: { type: 'category', data: C5 }, xAxis: { type: 'value', axisLabel: { rotate: 30, fontSize: 16 }, breaks: [{ start: 50, end: 900, gap: '4%' }] },
    series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] }, { axes: ['x0'] });

// ---- the break in the formatter's params and in the click event's
add('params', 'p-formatter', 'a function formatter: the third argument carries the break of a break end',
  barY({ axisLabel: { formatter: '@brk' }, breaks: [{ start: 50, end: 900, gap: '20%' }] }));
add('params', 'p-formatter-cut', 'the break cut by min: the formatter is handed the clamped one',
  barY({ min: 200, axisLabel: { formatter: '@brk' }, breaks: [{ start: 50, end: 900, gap: '20%' }] }, [210, 230, 950, 240, 1000]));
add('params', 'p-formatter-log', 'a log axis\' formatter: the break as the lookup brings it back',
  logY({ axisLabel: { formatter: '@brk' }, breaks: [{ start: 50, end: 900, gap: '20%' }] }));
add('params', 'p-event', 'triggerEvent: a click on a break label: params.break {start, end}; on a plain label none',
  barY({ triggerEvent: true, breaks: [{ start: 50, end: 900, gap: '20%' }] }),
  { steps: [{ type: 'click', at: { kind: 'label', axis: 'y0', value: 50 } },
    { type: 'click', at: { kind: 'label', axis: 'y0', value: 1000 } }] });

// ---- the break areas in a transition
const ANIM = [];
function addAnim(id, note, option, action, axis, more) {
  ANIM.push(Object.assign({ group: 'anim', id, note, option, action, axis: axis || 'y0' }, more || {}));
}
addAnim('t-zoom', 'a dataZoom over a broken y axis: the break area moves from its old points to its new by anid',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { type: 'dataZoom', start: 0, end: 70 });
addAnim('t-zoom-x', 'a dataZoom over a broken x axis: the area slides along it',
  { yAxis: { type: 'category', data: C5 }, xAxis: { type: 'value', breaks: [{ start: 50, end: 900, gap: '8%' }] },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, filterMode: 'none' }], series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] },
  { type: 'dataZoom', start: 10, end: 100 }, 'x0');
addAnim('t-legend', 'a legend toggle: the area is drawn again where it was, no move',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { legend: {}, series: [{ type: 'bar', name: 'A', data: [10, 30, 950, 40, 1000] },
    { type: 'bar', name: 'B', data: [5, 40, 920, 30, 990] }] }),
  { type: 'legendToggleSelect', name: 'B' });
addAnim('t-zoom-twice', 'a second dataZoom while the first transition moves: the new one starts from the leaves as they are now',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { type: 'dataZoom', start: 0, end: 70 }, 'y0',
  { action2: { type: 'dataZoom', start: 0, end: 40 }, at2: 250, samples: [0, 16, 100, 250, 266, 400, 500, 600, 749, 750, 751, 1000] });
// [R2-H] the other combinations of a second trigger while the first transition moves
const S2 = [0, 16, 100, 250, 266, 400, 500, 600, 749, 750, 751, 1000];
addAnim('t-zoom-x-twice', 'a second dataZoom on the broken x axis while the first moves: from the leaves as they are',
  { yAxis: { type: 'category', data: C5 }, xAxis: { type: 'value', breaks: [{ start: 50, end: 900, gap: '8%' }] },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, filterMode: 'none' }], series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] },
  { type: 'dataZoom', start: 10, end: 100 }, 'x0', { action2: { type: 'dataZoom', start: 30, end: 90 }, at2: 250, samples: S2 });
addAnim('t-zoom-back', 'a dataZoom back to the whole while the first one moves (100 ms in): back from where the leaves are',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { type: 'dataZoom', start: 0, end: 70 }, 'y0',
  { action2: { type: 'dataZoom', start: 0, end: 100 }, at2: 100, samples: [0, 16, 100, 116, 250, 400, 599, 600, 601, 1000] });
addAnim('t-zoom-legend', 'a legend toggle while a dataZoom moves: the render again keeps the leaves going from where they are',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { legend: {},
    dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }],
    series: [{ type: 'bar', name: 'A', data: [10, 30, 950, 40, 1000] }, { type: 'bar', name: 'B', data: [5, 40, 920, 30, 990] }] }),
  { type: 'dataZoom', start: 0, end: 70 }, 'y0', { action2: { type: 'legendToggleSelect', name: 'B' }, at2: 250, samples: S2 });
addAnim('t-zoom-expand', 'expandAxisBreak while a dataZoom moves: the area goes, the axis transition goes on',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { type: 'dataZoom', start: 0, end: 70 }, 'y0',
  { action2: { type: 'expandAxisBreak', yAxisIndex: 0, breaks: [{ start: 50, end: 900 }] }, at2: 250, samples: S2 });
addAnim('t-zoom-thrice', 'a third dataZoom while the second moves (each 150 ms after the last)',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }, null, { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { type: 'dataZoom', start: 0, end: 70 }, 'y0',
  { action2: { type: 'dataZoom', start: 0, end: 40 }, at2: 150, action3: { type: 'dataZoom', start: 10, end: 80 }, at3: 300,
    samples: [0, 16, 150, 166, 300, 316, 500, 799, 800, 801, 1000] });

// =====================================================================
// Running a case
// =====================================================================
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

function breakPoint(chart, at) {
  const model = axisModelOf(chart, at.axis);
  const axis = model.axis;
  const sc = axis.scale;
  const brk = (sc.type === 'log' ? sc.powStub.brk : sc.brk).breaks[at.index];
  must(brk, 'no break ' + at.index);
  const rect = rectOf(chart, at.axis);
  const c0 = axis.toGlobalCoord(axis.dataToCoord(brk.vmin, true));
  const c1 = axis.toGlobalCoord(axis.dataToCoord(brk.vmax, true));
  const mid = (c0 + c1) / 2;
  if (axis.isHorizontal()) return [Math.round(mid), Math.round(rect.y + rect.height * at.frac)];
  return [Math.round(rect.x + rect.width * at.frac), Math.round(mid)];
}
function labelPoint(chart, at) {
  const model = axisModelOf(chart, at.axis);
  const view = chart.getViewOfComponentModel(model);
  let el = null;
  walk(view.group, e => { if (e.type === 'text' && e.anid === 'label_' + at.value) el = e; });
  must(el, 'no label ' + at.value);
  const r = el.getBoundingRect().clone();
  r.applyTransform(el.getComputedTransform());
  return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
}

function newChart() {
  rngState = SEED;
  DRAWS = 0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W0, height: H0 });
  chart._ssr = false;
  return chart;
}

function runCase(c) {
  const chart = newChart();
  const events = [];
  const clicks = [];
  chart.on('axisbreakchanged', e => {
    events.push({ type: e.type, breaks: JSON.parse(nul(JSON.stringify(e.breaks))), fromAction: e.fromAction,
      payload: payloadRec(e.fromActionPayload) });
  });
  chart.on('click', p => {
    clicks.push({ componentType: p.componentType, targetType: p.targetType == null ? null : p.targetType,
      value: p.value == null ? null : J(p.value), tickIndex: p.tickIndex == null ? null : p.tickIndex,
      break: p.break == null ? null : J(p.break) });
  });
  try {
    CALLS = [];
    MERGED = [];
    chart.setOption(materialize(c.option));
    chart.renderToSVGString();
    const renders = [recordRender(chart, c, DRAWS, [], [], CALLS.slice(), null)];
    for (const st of c.steps) {
      DRAWS = 0;
      CALLS = [];
      events.length = 0;
      clicks.length = 0;
      MERGED = [];
      let point = null;
      if (st.type === 'click') {
        point = st.at.kind === 'break' ? breakPoint(chart, st.at) : labelPoint(chart, st.at);
        const h = chart.getZr().handler;
        h.mousemove(raw(point[0], point[1]));
        h.mousedown(raw(point[0], point[1]));
        h.mouseup(raw(point[0], point[1]));
        h.click(raw(point[0], point[1]));
      } else if (st.type === 'action') {
        chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
      } else must(false, 'an unknown step ' + st.type);
      chart.renderToSVGString();
      renders.push(recordRender(chart, c, DRAWS, events.slice(), clicks.slice(), CALLS.slice(), point));
    }
    return renders;
  } finally {
    chart.dispose();
  }
}

// the break leaves of an axis view's _axisGroup, by anid
function breakLeaves(chart, key) {
  const v = chart.getViewOfComponentModel(axisModelOf(chart, key));
  const out = [];
  if (!v._axisGroup) return out;
  v._axisGroup.traverse(el => {
    if (!el.isGroup && el.anid && el.anid.indexOf('break_') === 0) {
      out.push({ anid: nul(el.anid), points: pts(el.shape.points) });
    }
  });
  return out;
}
const SAMPLES = [0, 1, 16, 100, 250, 400, 499, 500, 501, 800];
function runAnim(c) {
  const chart = newChart();
  try {
    const opt = materialize(c.option);
    opt.animation = true;
    chart.setOption(opt);
    const zr = chart.getZr();
    const start = NOW;
    for (let t = 16; t <= 5000; t += 250) {
      NOW = start + t;
      zr.animation.update();
    }
    zr.storage.getDisplayList(true);
    const before = { draws: DRAWS, leaves: breakLeaves(chart, c.axis) };
    DRAWS = 0;
    const T1 = start + 10000;
    NOW = T1;
    chart.dispatchAction(JSON.parse(JSON.stringify(c.action)));
    const frames = [];
    for (const t of c.samples || SAMPLES) {
      NOW = T1 + t;
      zr.animation.update();
      zr.storage.getDisplayList(true);
      frames.push({ t, leaves: breakLeaves(chart, c.axis) });
      if (c.action2 && t === c.at2) chart.dispatchAction(JSON.parse(JSON.stringify(c.action2)));
      if (c.action3 && t === c.at3) chart.dispatchAction(JSON.parse(JSON.stringify(c.action3)));
    }
    return { before, draws: DRAWS, frames };
  } finally {
    chart.dispose();
  }
}

// =====================================================================
// Generation
// =====================================================================
function generate() {
  const out = {
    source: DIST, version: echarts.version, W: W0, H: H0, seed: SEED,
    notes: [
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'A log axis\' breaks: the ends as written (powStub), the gaps of intervalStub (log space).',
      'anim: the break leaves of the axis\' _axisGroup by anid after the settled first render (before) and at each sample after the action at T1.',
    ],
    cases: [], anim: [],
  };
  for (const c of CASES) {
    const renders = runCase(c);
    out.cases.push({ id: c.id, group: c.group, note: c.note, option: J(c.option), axes: c.axes, series: c.series,
      steps: c.steps.map(s => J(s)), renders });
  }
  for (const c of ANIM) {
    const r = runAnim(c);
    out.anim.push({ id: c.id, group: c.group, note: c.note, option: J(c.option), action: J(c.action), axis: c.axis,
      action2: c.action2 ? J(c.action2) : undefined, at2: c.action2 ? c.at2 : undefined,
      action3: c.action3 ? J(c.action3) : undefined, at3: c.action3 ? c.at3 : undefined,
      before: r.before, draws: r.draws, frames: r.frames });
  }
  return out;
}

function checks(out) {
  const anchors = [];
  const anchor = (name, cond) => { anchors.push(name); must(cond, 'anchor failed: ' + name); };
  const cs = id => out.cases.find(c => c.id === id);
  const ax0 = (id, ri) => cs(id).renders[ri || 0].axes[0];
  anchor('l-one-prct: a break end of each kind among the ticks', ax0('l-one-prct').ticks.some(t => t.b === 'vmin') && ax0('l-one-prct').ticks.some(t => t.b === 'vmax'));
  anchor('l-one-prct: a break area', ax0('l-one-prct').breakAreas.length === 1);
  const two = ax0('l-two');
  anchor('l-two: the first break\'s end comes back as a power, not 60', two.ticks.some(t => t.b === 'vmax' && t.v !== hex(60) && Math.abs(
    (function () { bits.setUint32(0, parseInt(t.v.slice(0, 8), 16)); bits.setUint32(4, parseInt(t.v.slice(8), 16)); return bits.getFloat64(0); })() - 60) < 1e-9));
  anchor('l-click: the click expanded it', cs('l-click').renders[1].events.length === 1);
  anchor('s-value: a break area on the single', ax0('s-value').breakAreas.length === 1);
  anchor('s-click: the click expanded it by singleAxisIndex', cs('s-click').renders[1].events.length === 1
    && cs('s-click').renders[1].events[0].breaks[0].singleAxisIndex === 0);
  const moved = id => { const l = ax0(id).labels.filter(x => x.b); return l.length === 2; };
  anchor('r-x45: two break labels', moved('r-x45'));
  anchor('p-formatter: a call with a break', cs('p-formatter').renders[0].calls.some(c => c.extra && c.extra.break));
  anchor('p-event: the break label click carries the break', cs('p-event').renders[1].clicks.length === 1
    && cs('p-event').renders[1].clicks[0].break && cs('p-event').renders[2].clicks[0].break === null);
  const zf = out.anim.find(a => a.id === 't-zoom').frames;
  anchor('t-zoom: the area moves in between', JSON.stringify(zf[3].leaves) !== JSON.stringify(zf[0].leaves)
    && JSON.stringify(zf[3].leaves) !== JSON.stringify(zf[zf.length - 1].leaves));
  const tw = out.anim.find(a => a.id === 't-zoom-twice').frames;
  const at = t => JSON.stringify(tw.find(f => f.t === t).leaves);
  const once = t => JSON.stringify(zf.find(f => f.t === t).leaves);
  anchor('t-zoom-twice: the second transition starts where the first one is (266 is its first frame) and leaves its path',
    at(266) === at(250) && at(250) !== once(500) && at(400) !== once(400));
  anchor('s-value: the single\'s split lines are caught',ax0('s-value').singleSplit.length > 2);
  return anchors;
}

// the compact writer of box-merge.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + Array.from(v, x => oneLine(x === undefined ? null : x)).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const f = oneLine(v);
  if (f.length + ind.length <= LINE || v === null || typeof v !== 'object') return f;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = Array.from(v, x => fmt(x === undefined ? null : x, inner));
    if (items.every(t => !t.includes('\n'))) {
      const lines = [];
      let cur = '';
      for (const t of items) {
        if (cur && inner.length + cur.length + 1 + t.length + 1 > LINE) { lines.push(cur); cur = ''; }
        cur += (cur ? ',' : '') + t;
      }
      lines.push(cur);
      return '[\n' + lines.map(l => inner + l).join(',\n') + '\n' + ind + ']';
    }
    return '[\n' + items.map(x => inner + x).join(',\n') + '\n' + ind + ']';
  }
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner))
    .join(',\n') + '\n' + ind + '}';
}
const serialise = out => fmt(out, '') + '\n';

let json1;
let json2;
let anchors;
try {
  const g1 = generate();
  anchors = checks(g1);
  g1.anchors = anchors;
  json1 = serialise(g1);
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  JSON.parse(json1);
  const g2 = generate();
  g2.anchors = anchors;
  json2 = serialise(g2);
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const deterministic = json1 === json2;
console.log(CASES.length + ' cases, ' + ANIM.length + ' transitions; ' + anchors.length + ' anchors; two generations '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (!deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
