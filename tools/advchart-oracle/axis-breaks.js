/*
Upstream's own answers for AXIS BREAKS -- roadmap D1, batch 132: the
`breaks` of a value or time axis on a cartesian grid (scale/breakImpl.ts,
component/axis/axisBreakHelperImpl.ts): the breaks as parsed (sorted,
start and end swapped where written backwards, an overlapping one dropped,
an expanded one left out), the gap each takes (gapReal: a number is in data
units, a percent of the axis' linear span, a break cut by the extent
counting only the part inside), the nice step on the span with the breaks
taken out, the ticks stepping over a break, the normal ticks pruned within
three quarters of a step of a break (the extent's ends kept for the split
lines), a break's two ends added as ticks with labels (on a time axis at
the units the break spans), the two labels of a break moved apart when they
overlap (breakLabelLayout.moveOverlap), the axis line cut at the breaks
(axisLine.breakLine), the zigzag break areas -- two polylines and the
polygon between them, their points drawn from Math.random and CACHED per
break on the axis view, so a render after a resize draws only the points
it did not have -- the series mapped across the breaks, and the
expandAxisBreak / collapseAxisBreak / toggleAxisBreak actions with their
axisbreakchanged event, dispatched by a click on a break area
(breakArea.expandOnClick) or on a break label (triggerEvent).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, `animation: false`,
TZ=UTC, measuring every string with zrender's width table (the
TZrSsrMeasurer of the Pascal tests). Every chart is 600 x 400 unless a
step resizes it. Math.random is the port's xorshift32 (TyJitterSeed,
2463534242), reset before every chart; every draw is counted. The chart is
made with ssr: true and then chart._ssr = false before setOption (the
browser's model, as mouse-events.js). Pointer steps go to zrender's own
Handler: mousemove, mousedown, mouseup and click at integer points.

  node tools/advchart-oracle/axis-breaks.js

writes tests/fixtures/advchart-axis-breaks.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions or values are the 16 hex digits of the IEEE
double (big-endian, lowercase); counts, flags, strings and option values
are plain JSON. A value as upstream keys an element (anid) is its String().

Top level: source, version, W, H, seed, notes[], cases[], guards[].

A case: id, group, note, option (as run), axes ['y0', ...] (the axes
  recorded: dim and component index), series (the series indices whose
  layout is recorded), steps[] (after the first render, each
    {type 'click', at {kind 'break', axis, index, frac} | {kind 'label',
       axis, value} | {kind 'abs', x, y}} -- the point resolved to integers
       and recorded as x, y --
    | {type 'action', payload}
    | {type 'resize', W, H}),
  renders[] (one after setOption, one after each step).

A render: W, H, rect [x, y, w, h] hex (grid 0), draws (Math.random calls
  during this render), events[] (axisbreakchanged events the step fired:
  {type, breaks [{xAxisIndex | yAxisIndex, start, end, isExpanded, old
  {isExpanded}}] (as JSON, NULs as '<NUL>'), fromAction, payload (JSON)}),
  point (click steps: [x, y]), axes[] in the case's order:
    dim, index, type ('value' | 'time' | 'category' | 'log'), inverse,
    extent [2] hex (scale.getExtent()),
    interval hex (an interval scale's config.interval; a time scale's
      _approxInterval), niceExtent [2] hex | null,
    breaks[] (scale.brk.breaks; empty with no break mapper): {start, end
      (the option's, JSON), vmin, vmax hex, type ('tpAbs' | 'tpPrct'), val
      hex, gapReal hex},
    ticks[] scale.getTicks(): {v hex, b null | 'vmin' | 'vmax', lv (a time
      tick's level), lo, up (a time tick's lower / upper unit)},
    rawTicks[] hex: getTicks({breakTicks 'none', pruneByBreak 'no'}),
    lineTicks[] hex: getTicks({breakTicks 'none', pruneByBreak
      'preserve_extent_bound'}) (the split lines' and areas'),
    minor[][] hex: the minor ticks (getMinorTicks) when minorTick or
      minorSplitLine is shown, else null,
    labels[] in the order the view built them: {v hex, b, text, x, y hex
      (the Text element's own x / y after the layout), shown (!ignore)},
    splitLines[] {v (anid's value), x1, y1, x2, y2 hex},
    axisTicks[] {v, shown (!ignore: a tick whose label was hidden is ignored),
      x1, y1, x2, y2 hex} ('ticks_' elements),
    axisLine[] {anid ('line' | 'breakLine_...', NULs '<NUL>'), x1, y1, x2,
      y2 hex},
    breakAreas[] {id (the break's identifier start + '_\0_' + end, NULs
      '<NUL>'), a [[x, y]] hex (polyline A), b null | [[x, y]] hex
      (polyline B, absent when gapReal is 0), poly (the polygon is there),
      z, silent, stroke, lineWidth hex, lineDash (JSON), fill, opacity hex}
  series[] {index, type, items [[x, y, w, h] hex (a bar's layout) | [x, y] hex
    (a line's or a scatter's point as coordSys.dataToPoint answers it -- the
    layout keeps it in a Float32Array) | null]}

Self-checks (transcriptions of upstream's recipes, compared with Object.is
on every record they cover; any failure writes nothing):
  gapReal     updateAxisBreakGapReal over the recorded breaks and extent;
  prune       pruneTicksByBreak over rawTicks: every tick strictly within
              interval * 3 / 4 of a clamped break gone gives the labels'
              normal ticks ('auto'), the extent's ends kept gives lineTicks
              ('preserve_extent_bound');
  zigzag      polylines A and B from the random draws of the chart (the
              cache replayed -- kept per axis view and break, untouched by a
              render with no break pair): the walk from the grid's edge,
              alternating amplitude, the last point on the far edge, the
              ends from the elapsed mapping (transformIn and the linear
              normalisation) through subPixelOptimize with width 1; the y
              axes' views draw before the x axes'.
guards[] mutate the transcriptions one way each (a percent gap at half its
share, the prune margin halved, the zigzag drawn afresh every render, the
amplitude turned round) and name the cases that must notice.
Anchors: a case that must draw random numbers does, breakArea.show false
draws none; the expand click fires the event, a silent area does not; a
resize to a taller grid draws more and one back to it draws none.
Two in-process runs must write the same bytes; process.exit() ends it.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-breaks.json');
const W0 = 600;
const H0 = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
must(new Date(0).getTimezoneOffset() === 0, 'TZ is not UTC');

// ---------- the random numbers: the port's xorshift32 ----------
const SEED = 2463534242;
let rngState = SEED;
let DRAWS = [];
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  const r = x / 4294967296;
  DRAWS.push(r);
  return r;
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
// a payload as the user sees it: echarts' own inner store left out
const payloadRec = p => JSON.parse(nul(JSON.stringify(p, (k, v) => (k.indexOf('__ec_inner') === 0 ? undefined : v))));
const pts = a => a.map(p => [hex(p[0]), hex(p[1])]);

function walk(e, f) {
  f(e);
  if (e.childrenRef) e.childrenRef().forEach(x => walk(x, f));
}

// =====================================================================
// Recording
// =====================================================================
function axisModelOf(chart, key) {
  const dim = key[0];
  const idx = +key.slice(1);
  const m = chart.getModel().getComponent(dim + 'Axis', idx);
  must(m, 'no axis ' + key);
  return m;
}

function recordAxis(chart, key) {
  const model = axisModelOf(chart, key);
  const axis = model.axis;
  const scale = axis.scale;
  const view = chart.getViewOfComponentModel(model);
  const rec = { dim: axis.dim, index: model.componentIndex, type: axis.type, inverse: !!axis.inverse };
  rec.extent = scale.getExtent().map(hex);
  if (scale.type === 'interval') {
    const cfg = scale.getConfig();
    rec.interval = hex(cfg.interval);
    rec.niceExtent = cfg.niceExtent ? cfg.niceExtent.map(hex) : null;
  } else if (scale.type === 'time') {
    rec.interval = hex(scale._approxInterval);
    rec.niceExtent = null;
  } else {
    rec.interval = null;
    rec.niceExtent = null;
  }
  const brk = scale.brk;
  rec.breaks = (brk ? brk.breaks : []).map(b => ({
    start: J(b.breakOption.start), end: J(b.breakOption.end), vmin: hex(b.vmin), vmax: hex(b.vmax),
    type: b.gapParsed.type, val: hex(b.gapParsed.val), gapReal: hex(b.gapReal),
  }));
  const tk = t => {
    const o = { v: hex(t.value), b: t.break ? t.break.type : null };
    if (t.time) { o.lv = t.time.level; o.lo = t.time.lowerTimeUnit; o.up = t.time.upperTimeUnit; }
    return o;
  };
  const ticks = scale.type === 'ordinal' ? [] : scale.getTicks();
  rec.ticks = ticks.map(tk);
  rec.rawTicks = scale.type === 'ordinal' ? [] : scale.getTicks({ breakTicks: 'none', pruneByBreak: 'no' }).map(t => hex(t.value));
  rec.lineTicks = scale.type === 'ordinal' ? [] : scale.getTicks({ breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' }).map(t => hex(t.value));
  const wantMinor = model.get(['minorTick', 'show']) || model.get(['minorSplitLine', 'show']);
  rec.minor = wantMinor && scale.type !== 'ordinal' ? axis.getMinorTicksCoords().map(g => g.map(c => hex(c.tickValue))) : null;
  // the labels the view built, in order, zipped with the ticks they came from
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
    return { v: hex(t.value), b: t.break ? t.break.type : null, text: e.style.text, x: hex(e.x), y: hex(e.y), shown: !e.ignore };
  });
  // the break areas: the group of each break, in the order they were added
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
  rec.axisTicks = axisTicks;
  rec.axisLine = axisLine;
  rec.breakAreas = breakAreas;
  return rec;
}

function recordSeries(chart, idx) {
  const s = chart.getModel().getSeriesByIndex(idx);
  const data = s.getData();
  const items = [];
  if (s.subType === 'line' || s.subType === 'scatter') {
    // the points as dataToPoint answers them, before the Float32Array the layout keeps
    const cs = s.coordinateSystem;
    const dims = cs.dimensions.map(d => data.mapDimension(d));
    const store = data.getStore();
    for (let i = 0; i < data.count(); i++) {
      const p = cs.dataToPoint([store.get(data.getDimensionIndex(dims[0]), i), store.get(data.getDimensionIndex(dims[1]), i)], null, []);
      items.push([hex(p[0]), hex(p[1])]);
    }
    return { index: idx, type: s.subType, items };
  }
  for (let i = 0; i < data.count(); i++) {
    const l = data.getItemLayout(i);
    if (l == null) items.push(null);
    else if (Array.isArray(l)) items.push([hex(l[0]), hex(l[1])]);
    else if (l.width != null) items.push([hex(l.x), hex(l.y), hex(l.width), hex(l.height)]);
    else items.push(null);
  }
  return { index: idx, type: s.subType, items };
}

function recordRender(chart, c, W, H, draws, events, point) {
  const rect = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
  const r = { W, H, rect: [hex(rect.x), hex(rect.y), hex(rect.width), hex(rect.height)], draws, events };
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
const barY = (y, data, extra) => Object.assign({
  xAxis: { type: 'category', data: C5 }, yAxis: Object.assign({ type: 'value' }, y),
  series: [{ type: 'bar', data: data || [10, 30, 950, 40, 1000] }],
}, extra || {});

// ---- value axes
add('value', 'v-one-prct', "one break 50..900, gap '5%': the nice step on the span without it",
  barY({ breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('value', 'v-one-abs', 'one break 50..900, gap 20 in data units', barY({ breaks: [{ start: 50, end: 900, gap: 20 }] }));
add('value', 'v-default-gap', 'no gap written: nought, polyline B and the polygon left out',
  barY({ breaks: [{ start: 50, end: 900 }] }));
add('value', 'v-two', "two breaks, one '3%' and one of 10, written out of order",
  barY({ breaks: [{ start: 450, end: 900, gap: 10 }, { start: 60, end: 400, gap: '3%' }] }, [20, 420, 950, 55, 1000]));
add('value', 'v-overlap', 'overlapping breaks: the second (by start) is dropped',
  barY({ breaks: [{ start: 100, end: 500, gap: '4%' }, { start: 400, end: 800, gap: '4%' }] }, [20, 90, 950, 600, 1000]));
add('value', 'v-reversed', "start above end: swapped; a string start '50'",
  barY({ breaks: [{ start: 900, end: '50', gap: '6%' }] }));
add('value', 'v-two-prct', "two percent gaps, '4%' and '8%', share the gap sum",
  barY({ breaks: [{ start: 60, end: 400, gap: '4%' }, { start: 450, end: 900, gap: '8%' }] }, [20, 420, 950, 55, 1000]));
add('value', 'v-min-in-break', 'min: 200 inside the break 50..900: the break cut at the extent, gap by the part inside',
  barY({ min: 200, breaks: [{ start: 50, end: 900, gap: '5%' }] }, [210, 230, 950, 240, 1000]));
add('value', 'v-max-in-break', 'max: 600 inside the break 500..900 (a semi-in break at the end)',
  barY({ max: 600, breaks: [{ start: 500, end: 900, gap: '5%' }] }, [10, 30, 550, 40, 480]));
add('value', 'v-outside', 'a break wholly outside the extent: no break ticks, no area',
  barY({ breaks: [{ start: 2000, end: 3000, gap: '5%' }] }));
add('value', 'v-expanded-option', 'isExpanded: true in the option: the break is not parsed at all',
  barY({ breaks: [{ start: 50, end: 900, gap: '5%', isExpanded: true }] }));
add('value', 'v-inverse', 'an inverse y axis: the labels of the break moved the other way',
  barY({ inverse: true, breaks: [{ start: 50, end: 900, gap: '2%' }] }));
add('value', 'v-move-off', 'breakLabelLayout.moveOverlap false: the two labels stay where they are',
  barY({ breakLabelLayout: { moveOverlap: false }, breaks: [{ start: 50, end: 900, gap: '2%' }] }));
add('value', 'v-wide-gap', "a wide gap '20%': the labels do not overlap and stay",
  barY({ breaks: [{ start: 50, end: 900, gap: '20%' }] }));
add('value', 'v-interval', 'interval: 50 written: the step stays, the ticks step over the break',
  barY({ interval: 50, breaks: [{ start: 120, end: 900, gap: '5%' }] }));
add('value', 'v-split', 'splitNumber 10 and minInterval 20', barY({ splitNumber: 10, minInterval: 20, breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('value', 'v-line-ticks', 'axisLine and axisTick shown: the line cut at the break, ticks at the break ends',
  barY({ axisLine: { show: true }, axisTick: { show: true }, breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('value', 'v-breakline-off', 'axisLine.breakLine false: one whole line',
  barY({ axisLine: { show: true, breakLine: false }, breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('value', 'v-minor-area', 'minorTick, minorSplitLine and splitArea shown',
  barY({ minorTick: { show: true }, minorSplitLine: { show: true }, splitArea: { show: true }, breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('value', 'v-style', 'breakArea written: colours, a solid 2 px border, opacity 0.3, amplitude 6, spans 10..30, z 50',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }], breakArea: { itemStyle: { color: '#ffeedd', borderColor: '#aa3300', borderWidth: 2, borderType: 'solid', opacity: 0.3 },
    zigzagAmplitude: 6, zigzagMinSpan: 10, zigzagMaxSpan: 30, zigzagZ: 50 } }));
add('value', 'v-style-dashed', 'borderType [6, 2] and a min span above the max: the max is raised to it',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }], breakArea: { itemStyle: { borderType: [6, 2] }, zigzagMinSpan: 25, zigzagMaxSpan: 5 } }));
add('value', 'v-area-off', 'breakArea.show false: no zigzag, no random number',
  barY({ breaks: [{ start: 50, end: 900, gap: '5%' }], breakArea: { show: false } }));
add('value', 'v-horizontal', 'a value x axis: the zigzag runs down the grid',
  { yAxis: { type: 'category', data: C5 }, xAxis: { type: 'value', breaks: [{ start: 50, end: 900, gap: '5%' }] },
    series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] }, { axes: ['x0'] });
add('value', 'v-line', 'a line across the break, a point inside it',
  { xAxis: { type: 'category', data: C7 }, yAxis: { type: 'value', breaks: [{ start: 100, end: 800, gap: '5%' }] },
    series: [{ type: 'line', data: [20, 60, 450, 900, 950, 70, 1000] }] });
add('value', 'v-scatter-both', 'two value axes, each broken',
  { xAxis: { type: 'value', breaks: [{ start: 20, end: 80, gap: '5%' }] }, yAxis: { type: 'value', breaks: [{ start: 300, end: 700, gap: 20 }] },
    series: [{ type: 'scatter', data: [[5, 100], [10, 250], [90, 800], [95, 950], [50, 500]] }] }, { axes: ['y0', 'x0'] });
add('value', 'v-negative', 'a break below nought on a range through it',
  barY({ breaks: [{ start: -900, end: -100, gap: '5%' }] }, [-1000, -50, 30, -950, 60]));
add('value', 'v-hide-overlap', 'hideOverlap: the break labels are kept first',
  barY({ axisLabel: { hideOverlap: true }, splitNumber: 12, breaks: [{ start: 50, end: 900, gap: '1%' }] }));
// [milestone D1-D4] v-hide-overlap shows every label, so nothing weighs the
// break labels' lift; crowded ticks make hideOverlap choose
add('value', 'v-hide-overlap-crowded', 'hideOverlap over crowded labels: the two break labels win over their neighbours',
  barY({ axisLabel: { hideOverlap: true }, splitNumber: 40, breaks: [{ start: 52, end: 900, gap: '1%' }] }));
add('value', 'v-formatter', "a string formatter '{value} kg' on the break labels too",
  barY({ axisLabel: { formatter: '{value} kg' }, breaks: [{ start: 50, end: 900, gap: '5%' }] }));
add('value', 'v-category-ignored', 'breaks on a category axis: ignored (upstream supports none there)',
  barY({ breaks: [{ start: 50, end: 900, gap: '5%' }] }, null,
    { xAxis: { type: 'category', data: C5, breaks: [{ start: 1, end: 3, gap: '5%' }] } }), { axes: ['x0', 'y0'] });

// ---- time axes (useUTC: the port's local clock is not the oracle's)
const DAY = 86400000;
const T0 = Date.UTC(2024, 0, 1);
const tline = (n, step, f) => Array.from({ length: n }, (_, i) => [T0 + i * step, f(i)]);
add('time', 't-one', 'a time axis over 90 days with a 40-day break',
  { useUTC: true, xAxis: { type: 'time', breaks: [{ start: T0 + 20 * DAY, end: T0 + 60 * DAY, gap: '5%' }] }, yAxis: { type: 'value' },
    series: [{ type: 'line', data: tline(13, 7 * DAY, i => (i * 13) % 17 + 3) }] }, { axes: ['x0'] });
add('time', 't-weekends', 'two weekends broken out of a fortnight of hours',
  { useUTC: true, xAxis: { type: 'time', breaks: [
      { start: Date.UTC(2024, 0, 6), end: Date.UTC(2024, 0, 8), gap: 0 },
      { start: Date.UTC(2024, 0, 13), end: Date.UTC(2024, 0, 15), gap: 0 }] },
    yAxis: { type: 'value' }, series: [{ type: 'line', data: tline(15, DAY, i => (i * 7) % 11 + 1) }] }, { axes: ['x0'] });
add('time', 't-cross-year', 'a break from December into February: the labels at month over year',
  { useUTC: true, xAxis: { type: 'time', breaks: [{ start: Date.UTC(2023, 11, 10), end: Date.UTC(2024, 1, 5), gap: '6%' }] },
    yAxis: { type: 'value' }, series: [{ type: 'line', data: Array.from({ length: 12 }, (_, i) => [Date.UTC(2023, 9, 1) + i * 15 * DAY, (i * 5) % 9 + 2]) }] }, { axes: ['x0'] });
add('time', 't-string', "start and end as date strings with a zone (a string without one is the machine's local time), gap '4%'",
  { useUTC: true, xAxis: { type: 'time', breaks: [{ start: '2024-01-10T00:00:00Z', end: '2024-02-20T00:00:00Z', gap: '4%' }] }, yAxis: { type: 'value' },
    series: [{ type: 'line', data: tline(13, 7 * DAY, i => (i * 3) % 7 + 1) }] }, { axes: ['x0'] });

// ---- dataZoom
add('zoom', 'z-value', 'an inside dataZoom on the broken y axis (filterMode none): the window cuts the break, then leaves it',
  barY({ breaks: [{ start: 50, end: 900, gap: '5%' }] }, null, { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }] }),
  { steps: [
    { type: 'action', payload: { type: 'dataZoom', start: 3, end: 100 } },
    { type: 'action', payload: { type: 'dataZoom', start: 50, end: 100 } },
    { type: 'action', payload: { type: 'dataZoom', start: 0, end: 60 } },
    { type: 'action', payload: { type: 'dataZoom', start: 0, end: 100 } }] });
add('zoom', 'z-time', 'an inside dataZoom on a broken time axis',
  { useUTC: true, dataZoom: [{ type: 'inside', xAxisIndex: 0 }], xAxis: { type: 'time', breaks: [{ start: T0 + 20 * DAY, end: T0 + 60 * DAY, gap: '5%' }] },
    yAxis: { type: 'value' }, series: [{ type: 'line', data: tline(13, 7 * DAY, i => (i * 13) % 17 + 3) }] },
  { axes: ['x0'], steps: [
    { type: 'action', payload: { type: 'dataZoom', start: 30, end: 100 } },
    { type: 'action', payload: { type: 'dataZoom', start: 10, end: 80 } }] });

// ---- the actions and the clicks
add('action', 'a-click-expand', 'a click on the break area expands it; collapse and toggle bring it back and take it away',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }),
  { steps: [
    { type: 'click', at: { kind: 'break', axis: 'y0', index: 0, frac: 0.5 } },
    { type: 'action', payload: { type: 'collapseAxisBreak', yAxisIndex: 0, breaks: [{ start: 50, end: 900 }] } },
    { type: 'action', payload: { type: 'toggleAxisBreak', yAxisIndex: 0, breaks: [{ start: 50, end: 900 }] } },
    { type: 'action', payload: { type: 'toggleAxisBreak', yAxisIndex: 0, breaks: [{ start: 50, end: 900 }] } }] });
add('action', 'a-two-expand', 'two breaks: the second expanded by its click, the first by an action naming both',
  barY({ breaks: [{ start: 60, end: 400, gap: '6%' }, { start: 450, end: 900, gap: '6%' }] }, [20, 420, 950, 55, 1000]),
  { steps: [
    { type: 'click', at: { kind: 'break', axis: 'y0', index: 1, frac: 0.3 } },
    { type: 'action', payload: { type: 'expandAxisBreak', yAxisIndex: 0, breaks: [{ start: 60, end: 400 }, { start: 450, end: 900 }] } },
    { type: 'action', payload: { type: 'collapseAxisBreak', yAxisIndex: 0, breaks: [{ start: 450, end: 900 }] } }] });
add('action', 'a-click-off', 'expandOnClick false: the area is silent and the click does nothing',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }], breakArea: { expandOnClick: false } }),
  { steps: [{ type: 'click', at: { kind: 'break', axis: 'y0', index: 0, frac: 0.5 } }] });
add('action', 'a-label-click', 'triggerEvent: a click on a break label expands it',
  barY({ triggerEvent: true, breaks: [{ start: 50, end: 900, gap: '20%' }] }),
  { steps: [{ type: 'click', at: { kind: 'label', axis: 'y0', value: 900 } }] });
add('action', 'a-x-expand', 'a broken value x axis expanded by its click (xAxisIndex in the event)',
  { yAxis: { type: 'category', data: C5 }, xAxis: { type: 'value', breaks: [{ start: 50, end: 900, gap: '8%' }] },
    series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] },
  { axes: ['x0'], steps: [{ type: 'click', at: { kind: 'break', axis: 'x0', index: 0, frac: 0.5 } }] });
add('action', 'a-unknown', 'an action naming a break that is not there: no change, an event with no breaks',
  barY({ breaks: [{ start: 50, end: 900, gap: '8%' }] }),
  { steps: [{ type: 'action', payload: { type: 'expandAxisBreak', yAxisIndex: 0, breaks: [{ start: 51, end: 900 }] } }] });

// ---- the cache
add('cache', 'c-resize', 'a resize wider and back: the zigzag keeps its points and draws only the new ones',
  { xAxis: { type: 'value', breaks: [{ start: 50, end: 900, gap: '8%' }] }, yAxis: { type: 'category', data: C5 },
    series: [{ type: 'bar', data: [10, 30, 950, 40, 1000] }] },
  { axes: ['x0'], steps: [{ type: 'resize', W: 600, H: 700 }, { type: 'resize', W: 600, H: 300 }, { type: 'resize', W: 600, H: 700 }] });
add('cache', 'c-expand-back', 'a break expanded and collapsed again draws its zigzag anew; the other keeps its own',
  barY({ breaks: [{ start: 60, end: 400, gap: '6%' }, { start: 450, end: 900, gap: '6%' }] }, [20, 420, 950, 55, 1000]),
  { steps: [
    { type: 'action', payload: { type: 'expandAxisBreak', yAxisIndex: 0, breaks: [{ start: 60, end: 400 }] } },
    { type: 'action', payload: { type: 'collapseAxisBreak', yAxisIndex: 0, breaks: [{ start: 60, end: 400 }] } }] });

// =====================================================================
// Running a case
// =====================================================================
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

function breakPoint(chart, at) {
  const model = axisModelOf(chart, at.axis);
  const axis = model.axis;
  const brk = axis.scale.brk.breaks[at.index];
  must(brk, 'no break ' + at.index);
  const rect = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
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

function runCase(c) {
  rngState = SEED;
  DRAWS = [];
  let W = W0;
  let H = H0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  const events = [];
  chart.on('axisbreakchanged', e => {
    events.push({ type: e.type, breaks: JSON.parse(nul(JSON.stringify(e.breaks))), fromAction: e.fromAction,
      payload: payloadRec(e.fromActionPayload) });
  });
  const allDraws = [];
  try {
    chart.setOption(c.option);
    chart.renderToSVGString();
    const renders = [recordRender(chart, c, W, H, DRAWS.length, [], null)];
    allDraws.push(DRAWS.slice());
    for (const st of c.steps) {
      DRAWS = [];
      events.length = 0;
      let point = null;
      if (st.type === 'click') {
        point = st.at.kind === 'break' ? breakPoint(chart, st.at) : st.at.kind === 'label' ? labelPoint(chart, st.at) : [st.at.x, st.at.y];
        const h = chart.getZr().handler;
        h.mousemove(raw(point[0], point[1]));
        h.mousedown(raw(point[0], point[1]));
        h.mouseup(raw(point[0], point[1]));
        h.click(raw(point[0], point[1]));
      } else if (st.type === 'action') {
        chart.dispatchAction(JSON.parse(JSON.stringify(st.payload)));
      } else if (st.type === 'resize') {
        W = st.W; H = st.H;
        chart.resize({ width: W, height: H });
      } else must(false, 'an unknown step ' + st.type);
      chart.renderToSVGString();
      renders.push(recordRender(chart, c, W, H, DRAWS.length, events.slice(), point));
      allDraws.push(DRAWS.slice());
    }
    return { renders, allDraws };
  } finally {
    chart.dispose();
  }
}

// =====================================================================
// The transcriptions (guards)
// =====================================================================
const num = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };

// updateAxisBreakGapReal
function gapReals(brks, ext, mut) {
  let gapPrctSum = 0;
  const full = { tpAbs: { span: 0, val: 0 }, tpPrct: { span: 0, val: 0 } };
  const init = () => ({ has: false, span: NaN, inExtFrac: NaN, val: NaN });
  const semi = { S: { tpAbs: init(), tpPrct: init() }, E: { tpAbs: init(), tpPrct: init() } };
  for (const b of brks) {
    if (b.type === 'tpPrct') gapPrctSum += b.val;
    const cl = clampB(b, ext);
    if (!cl) continue;
    const vminC = cl.vmin !== b.vmin;
    const vmaxC = cl.vmax !== b.vmax;
    const span = cl.vmax - cl.vmin;
    if (vminC && vmaxC) { /* nothing */ } else if (vminC || vmaxC) {
      const se = vminC ? 'S' : 'E';
      semi[se][b.type] = { has: true, span, inExtFrac: span / (b.vmax - b.vmin), val: b.val };
    } else {
      full[b.type].span += span;
      full[b.type].val += b.val;
    }
  }
  const sum = gapPrctSum * (0 + (ext[1] - ext[0]) + (full.tpAbs.val - full.tpAbs.span)
    + (semi.S.tpAbs.has ? (semi.S.tpAbs.val - semi.S.tpAbs.span) * semi.S.tpAbs.inExtFrac : 0)
    + (semi.E.tpAbs.has ? (semi.E.tpAbs.val - semi.E.tpAbs.span) * semi.E.tpAbs.inExtFrac : 0)
    - full.tpPrct.span
    - (semi.S.tpPrct.has ? semi.S.tpPrct.span * semi.S.tpPrct.inExtFrac : 0)
    - (semi.E.tpPrct.has ? semi.E.tpPrct.span * semi.E.tpPrct.inExtFrac : 0))
    / (1 - full.tpPrct.val
      - (semi.S.tpPrct.has ? semi.S.tpPrct.val * semi.S.tpPrct.inExtFrac : 0)
      - (semi.E.tpPrct.has ? semi.E.tpPrct.val * semi.E.tpPrct.inExtFrac : 0));
  return brks.map(b => (b.type === 'tpPrct'
    ? (gapPrctSum !== 0 ? Math.max(sum, 0) * b.val / gapPrctSum : 0) * (mut === 'gap-half' ? 0.5 : 1)
    : b.val));
}
function clampB(b, ext) {
  const vmin = Math.max(b.vmin, ext[0]);
  const vmax = Math.min(b.vmax, ext[1]);
  return (vmin < vmax || (vmin === vmax && vmin > ext[0] && vmin < ext[1])) ? { vmin, vmax } : null;
}
function elapse(v, brks, gr) {
  let e = 0;
  let last = 0;
  let over = true;
  for (let i = 0; i < brks.length; i++) {
    const b = brks[i];
    if (v <= b.vmax) {
      if (v > b.vmin) e += b.vmin - last + (v - b.vmin) / (b.vmax - b.vmin) * gr[i];
      else e += v - last;
      last = b.vmax;
      over = false;
      break;
    }
    e += b.vmin - last + gr[i];
    last = b.vmax;
  }
  if (over) e += v - last;
  return e;
}

// subPixelOptimize with lineWidth 1 (zrender), a coordinate alone
function subPx(v) {
  const d = Math.round(v * 2);
  return (d + 1) % 2 === 0 ? d / 2 : (d + 1) / 2;
}
// rectCoordBuildBreakAxis's zigzag over every render of a case, the random draws replayed through
// the view's cache; mut 'nocache' draws afresh every render, 'amp' turns the amplitude round
function zigzagFacts(c, g, mut) {
  const caches = {};
  const out = [];
  g.renders.forEach((r, ri) => {
    const draws = g.draws[ri].slice();
    const rect = r.rect.map(num);
    r.axes.forEach(ax => {
      const key = ax.dim + ax.index;
      const list = (mut === 'nocache' ? null : caches[key]) || [];
      const used = [];
      const opt = (c.option[ax.dim + 'Axis'] || {}).breakArea || {};
      const amp = (opt.zigzagAmplitude != null ? opt.zigzagAmplitude : 4) * (mut === 'amp' ? -1 : 1);
      let minS = Math.max(2, (opt.zigzagMinSpan != null ? opt.zigzagMinSpan : 4) || 0);
      let maxS = Math.max(minS, (opt.zigzagMaxSpan != null ? opt.zigzagMaxSpan : 20) || 0);
      const horiz = ax.dim === 'x';
      const brks = ax.breaks.map(b => ({ vmin: num(b.vmin), vmax: num(b.vmax), gr: num(b.gapReal) }));
      const ext = ax.extent.map(num);
      const lin = v => {
        let e = 0; let last = 0; let over = true;
        for (const b of brks) {
          if (v <= b.vmax) { e += v > b.vmin ? b.vmin - last + (v - b.vmin) / (b.vmax - b.vmin) * b.gr : v - last; last = b.vmax; over = false; break; }
          e += b.vmin - last + b.gr; last = b.vmax;
        }
        if (over) e += v - last;
        return e;
      };
      const e0 = lin(ext[0]);
      const e1 = lin(ext[1]);
      const coord = v => {
        const n = e1 === e0 ? 0.5 : (lin(v) - e0) / (e1 - e0);
        const lo = horiz ? rect[0] : rect[1] + rect[3];
        const hi = horiz ? rect[0] + rect[2] : rect[1];
        const [a, b] = ax.inverse ? [hi, lo] : [lo, hi];
        return n <= 0 ? a : n >= 1 ? b : n * (b - a) + a;
      };
      ax.breakAreas.forEach(area => {
        const brk = ax.breaks.find(b => nul(String(b.start) + '_\u0000_' + String(b.end)) === area.id);
        const cl = clampB({ vmin: num(brk.vmin), vmax: num(brk.vmax) }, ext);
        let c0 = coord(cl.vmin);
        let c1 = coord(cl.vmax);
        if (c1 < c0) { const t = c0; c0 = c1; c1 = t; }
        c0 = subPx(c0);
        c1 = subPx(c1);
        let cached = list.find(x => x.id === area.id);
        if (!cached) cached = { id: area.id, rnd: [] };
        used.push(cached);
        const zMin = horiz ? rect[1] : rect[0];
        const zMax = zMin + (horiz ? rect[3] : rect[2]);
        const A = [];
        const B = [];
        let swap = true;
        let cur = zMin;
        for (let i = 0; ; i++) {
          const first = cur === zMin;
          const lastP = cur >= zMax;
          if (lastP) cur = zMax;
          let pa = c0;
          let pb = c1;
          if (!first && !lastP) { pa += swap ? -amp : amp; pb -= !swap ? -amp : amp; }
          A.push(horiz ? [pa, cur] : [cur, pa]);
          B.push(horiz ? [pb, cur] : [cur, pb]);
          let rv;
          if (i < cached.rnd.length) rv = cached.rnd[i];
          else {
            // a mutation may want more numbers than the chart drew: a fixed one then
            must(draws.length > 0 || mut, c.id + ' render ' + ri + ': the zigzag ran out of draws');
            rv = draws.length ? draws.shift() : 0.5;
            cached.rnd.push(rv);
          }
          cur += rv * (maxS - minS) + minS;
          swap = !swap;
          if (lastP) break;
        }
        out.push([ri, key, area.id, pts(A), area.b ? pts(B) : null]);
      });
      // no break pair (or no break area built at all): the view's cache is not touched
      if (ax.breakAreas.length) caches[key] = used;
    });
  });
  return out;
}

// the recipes over a generation; mut names one mutation
function checkAll(gen, mut) {
  const facts = {};
  for (const c of gen) {
    const f = [];
    c.renders.forEach((r, ri) => {
      r.axes.forEach(ax => {
        if (!ax.breaks.length) return;
        const brks = ax.breaks.map(b => ({ vmin: num(b.vmin), vmax: num(b.vmax), type: b.type, val: num(b.val) }));
        const ext = ax.extent.map(num);
        const gr = gapReals(brks, ext, mut);
        f.push(['gap', ri, ax.dim, gr.map(hex)]);
        // prune: no normal tick within interval * 3/4 of a clamped break
        const iv = num(ax.interval);
        const g = iv * 3 / 4 * (mut === 'prune-half' ? 0.5 : 1);
        const pruned = (keepEnds) => ax.rawTicks.map(num).filter(v => !brks.some(b => {
          const cl = clampB(b, ext);
          return cl && v > cl.vmin - g && v < cl.vmax + g && (!keepEnds || (v !== ext[0] && v !== ext[1]));
        }));
        f.push(['prune', ri, ax.dim, pruned(false).map(hex), pruned(true).map(hex)]);
        // the elapsed extent, the span the nice step used
        f.push(['span', ri, ax.dim, hex(elapse(ext[1], brks, gr) - elapse(ext[0], brks, gr))]);
      });
    });
    facts[c.id] = JSON.stringify(f) + JSON.stringify(zigzagFacts(CASES.find(x => x.id === c.id), c, mut));
  }
  return facts;
}

// =====================================================================
// Generation
// =====================================================================
function generate() {
  const out = {
    source: DIST, version: echarts.version, W: W0, H: H0, seed: SEED,
    notes: [
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart; draws counts the calls in a render.',
      'An absolute gap is in DATA units (scale.parse), not pixels; a percent gap is of the axis\' linear span.',
      'Breaks are supported on value, log and time axes of a cartesian grid or a singleAxis; a category axis ignores them.',
      'The zigzag points are cached on the axis VIEW per break (by start and end as written); a break that is expanded and collapsed again draws new ones.',
    ],
    cases: [], guards: [],
  };
  const gen = [];
  for (const c of CASES) {
    const r = runCase(c);
    gen.push({ id: c.id, renders: r.renders, draws: r.allDraws });
    out.cases.push({ id: c.id, group: c.group, note: c.note, option: J(c.option), axes: c.axes, series: c.series,
      steps: c.steps.map(s => J(s)), renders: r.renders });
  }
  // ---- self-checks
  for (const g of gen) {
    g.renders.forEach((r, ri) => r.axes.forEach(ax => {
      if (!ax.breaks.length) return;
      const brks = ax.breaks.map(b => ({ vmin: num(b.vmin), vmax: num(b.vmax), type: b.type, val: num(b.val) }));
      const gr = gapReals(brks, ax.extent.map(num), null);
      ax.breaks.forEach((b, k) => must(Object.is(num(b.gapReal), gr[k]), g.id + ' render ' + ri + ': gapReal ' + k));
      // pruneTicksByBreak over the unpruned ticks: 'auto' gives the labels' normal ticks, the
      // extent's ends kept gives the lines'
      const ext = ax.extent.map(num);
      const g2 = num(ax.interval) * 3 / 4;
      const prune = keepEnds => ax.rawTicks.filter(h => {
        const v = num(h);
        return !brks.some(b => {
          const cl = clampB(b, ext);
          return cl && v > cl.vmin - g2 && v < cl.vmax + g2 && (!keepEnds || (v !== ext[0] && v !== ext[1]));
        });
      });
      must(JSON.stringify(prune(false)) === JSON.stringify(ax.ticks.filter(t => !t.b).map(t => t.v)), g.id + ' render ' + ri + ': the auto prune');
      must(JSON.stringify(prune(true)) === JSON.stringify(ax.lineTicks), g.id + ' render ' + ri + ': the line prune');
    }));
  }
  for (const g of gen) {
    const zz = zigzagFacts(CASES.find(x => x.id === g.id), g, null);
    let k = 0;
    g.renders.forEach((r, ri) => r.axes.forEach(ax => ax.breakAreas.forEach(area => {
      const z = zz[k++];
      must(JSON.stringify(z[3]) === JSON.stringify(area.a) && JSON.stringify(z[4]) === JSON.stringify(area.b),
        g.id + ' render ' + ri + ': the zigzag of ' + area.id);
    })));
    must(k === zz.length, g.id + ': zigzag count');
  }
  const draws0 = gen.find(g => g.id === 'v-one-prct').renders[0].draws;
  must(draws0 > 0, 'v-one-prct drew no random numbers');
  must(gen.find(g => g.id === 'v-area-off').renders[0].draws === 0, 'v-area-off drew random numbers');
  const exp = gen.find(g => g.id === 'a-click-expand').renders[1];
  must(exp.events.length === 1 && exp.events[0].breaks.length === 1 && exp.events[0].breaks[0].isExpanded === true,
    'the expand click fired no event');
  must(gen.find(g => g.id === 'a-click-off').renders[1].events.length === 0, 'a silent area expanded');
  const rs = gen.find(g => g.id === 'c-resize').renders;
  must(rs[1].draws > 0 && rs[2].draws === 0, 'the resize cache: ' + rs.map(r => r.draws).join(','));
  // ---- guards: each mutation must change the named cases' facts
  const base = checkAll(gen, null);
  const guard = (id, mutation, named) => {
    const m = checkAll(gen, id);
    const changed = Object.keys(base).filter(k => base[k] !== m[k]);
    out.guards.push({ id, mutation, named, changed, ok: named.every(n => changed.includes(n)) });
  };
  guard('gap-half', 'a percent gap at half its share', ['v-one-prct', 'v-two-prct', 'v-min-in-break']);
  guard('prune-half', 'the prune margin at half of three quarters of a step', ['v-one-prct']);
  guard('nocache', 'the zigzag drawn afresh every render', ['c-resize', 'z-value', 'c-expand-back']);
  guard('amp', 'the zigzag amplitude turned round', ['v-one-prct', 'v-horizontal', 't-one']);
  return { out };
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

let g1;
let json1;
let json2;
try {
  g1 = generate();
  json1 = serialise(g1.out);
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(JSON.parse(JSON.stringify(g1.out))), 'the written JSON does not parse back to the record');
  const g2 = generate();
  json2 = serialise(g2.out);
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const out = g1.out;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nRenders = out.cases.reduce((n, c) => n + c.renders.length, 0);
console.log(out.cases.length + ' cases, ' + nRenders + ' renders; ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
