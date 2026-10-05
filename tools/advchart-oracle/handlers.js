// Upstream's own answers for what a FUNCTION formatter draws, at every site
// that takes one. The port cannot run JavaScript, so an option names a
// registered Pascal handler as the string '@Name'; this script runs the real
// ECharts 6.1 build (D:/Projects/echarts by default, or ECHARTS_DIST) in node's
// server-side mode with each such string replaced by a JS function of the
// same name, whose return value encodes the arguments it was called with. The
// Pascal test registers handlers of the same names that build the same
// encoding from its params record and compares the multiset of drawn texts.
//
// Handlers (S(x) = String(x): arrays join with commas, null is 'null',
// undefined is 'undefined'):
//   '@L'  series and marker label formatter(p)
//         'L:' + [componentType, seriesType, seriesIndex, seriesName, name,
//         dataIndex, S(value), percent (or '-'), dataType (or '-')].join('|')
//   '@AX' axisLabel formatter(value, index, extra)
//         'A:' + S(value) + '|' + S(index) + '|' + (extra == null ? 'null' : 'L' + extra.level)
//   '@TT' time axisLabel formatter(value, index, extra): returns the TEMPLATE
//         '{yyyy}/{M}/{d} ' + (extra == null ? 'null' : 'L' + extra.level)
//   '@LG' legend formatter(name)                    'G:' + name
//   '@VF' tooltip.valueFormatter(value, dataIndex)  'V:' + S(value) + '|' + S(dataIndex)
//   '@AP' axisPointer.label.formatter(params)
//         'P:' + [axisDimension, axisIndex, S(value), seriesData.length,
//         seriesData.map(s => s.seriesIndex + ':' + s.dataIndex).join(',')].join('|')
//   '@VM' visualMap formatter(v1, v2)               'M:' + S(v1) + '|' + S(v2)
//   '@DZ' dataZoom labelFormatter(value, valueStr)  'Z:' + S(value) + '|' + S(valueStr)
//   '@GD' gauge detail.formatter(value)             'D:' + S(value)
//   '@GA' gauge axisLabel.formatter(value)          'GA:' + S(value)
//   '@RN' radar axisName.formatter(name, indicator) 'R:' + name + '|' + S(indicator && indicator.max)
//   '@CM' calendar label formatter(params)
//         'C:' + [S(nameMap), S(yyyy), S(M), S(d)].join('|')
//
// The signatures upstream actually calls them with (6.1 source):
//   label      formatter(params) -- dataFormat.ts getDataParams + status and
//              dimensionIndex. params.dataIndex is the RAW index
//              (data.getRawIndex), never the index after dataZoom/legend
//              filtering. dataType is undefined for plain series (printed '-'),
//              'node'/'edge' for graph and sankey. percent exists on pie (the
//              seat of the largest-remainder rounding, 0 when the sum is 0) and
//              funnel (+(v / sum * 100).toFixed(2)) only. Markers: componentType
//              is 'markPoint'/'markLine'/'markArea', seriesType, seriesName and
//              seriesIndex are the HOST series' (MarkerModel.getDataParams),
//              name/dataIndex/value the marker item's own; no percent, no
//              dataType. A radar label is called once per indicator with
//              params.value narrowed to that element (labelDimIndex). Tree,
//              treemap and sunburst count dataIndex over their data, where 0
//              is the virtual root, so the first node written is 1. A cartesian
//              heatmap item's name is its x category.
//   axisLabel  category: formatter(categoryName, tick.value - extent[0], null)
//              -- the index counts from the axis window's first category, so
//              interval gaps show and a dataZoom window starts at 0 again;
//              extra is always null. value/log: formatter(tick.value, i, null)
//              where i is the tick's position in getTicks() (extra is null
//              unless an axis break is on the tick). time: formatter(tick.value,
//              i, {time, level: tick.time ? tick.time.level : 0}) and whatever
//              it returns goes through the time template format (util/time.ts
//              format): {yyyy}, {M}, {d} ... are substituted, other text kept.
//   legend     formatter(name)
//   tooltip    valueFormatter(value, rawDataIndex): value is the row's inline
//              value (an array for multi-dim rows); a sub-row (candlestick
//              open/close/..., radar indicators) gets its own value and
//              undefined for the index; a candlestick's item row, whose values
//              all went to sub-rows, gets [] ('V:|1'); a scatter row is y alone.
//              Item tooltips read it from [item, series, tooltip] models; axis
//              tooltips per series from [series, tooltip].
//   axisPointer formatter({value, axisDimension, axisIndex, seriesData}) where
//              value is getAxisRawValue (category name on a category axis) and
//              seriesData is getDataParams(dataIndexInside) per series -- so
//              dataIndex there is raw again. The axis tooltip's header is the
//              same getValueLabel call, so the formatter's text also heads the
//              tooltip (tipTexts). A pointer shown by status: 'show' in the
//              option gets no seriesData.
//   visualMap  continuous: formatter(value) for each handle label (v2
//              undefined; handles only exist with calculable: true).
//              piecewise: formatter(lo, hi) for an interval piece (open ends
//              -Infinity/Infinity), formatter(value) for a value piece and
//              formatter(category) for a category; a piece with its own label
//              never calls it.
//   dataZoom   labelFormatter(value, valueStr): value is window.value[i] (the
//              ordinal index on a category axis, epoch ms on time); valueStr is
//              scale.getLabel({value: round(value)}) on category/time axes,
//              else round(value, labelPrecision, true) as a string.
//   gauge      detail.formatter(value) and axisLabel.formatter(value), value
//              the raw number (the axis one rounded to 10 digits).
//   radar      axisName.formatter(name, innerIndicatorOpt) -- a merged clone
//              of the indicator, with min defaulted to 0 when max > 0.
//   calendar   monthLabel: formatter({yyyy, yy, MM, M, nameMap}) -- no d;
//              yearLabel: formatter({start, end, nameMap}) -- no yyyy/M/d;
//              dayLabel takes no formatter at all in 6.1 (nameMap only).
//
// Recording, per case: render once (SSR, animation false), then walk the zr
// scene from its roots -- groups' children and every element's textContent --
// and take every ZRText ('text') that is not ignored (itself or any ancestor
// or host) and not invisible, whose style.text starts with one of the handler
// prefixes, or matches /\d{4}\/\d+\/\d+ / (an '@TT' template after format).
// texts is that list, sorted. A case with a tooltip trigger then shows the
// tooltip the way series-text.js does (TooltipView in renderMode 'richText',
// showDelay 0, transitionDuration 0; env.node off and getDom stubbed while the
// case runs): showTip on seriesIndex + raw dataIndex for an item trigger, or
// showTip at the category's pixel on x and the grid's middle on y for an axis
// trigger (x, y and the category are recorded). tipTexts are the tooltip
// ZRText's '{__EC_aUTo_N|...}' segments and the text between them, split on
// lines, that start with a prefix, sorted; afterTexts is the scene walked
// again after the trigger with the tooltip's own text left out (it holds the
// axisPointer labels a trigger brings up).
//
// Guards (the fixture is not written and the run exits 1 when one fails): a
// set of strings worked out from the upstream source by hand, each one of
// which a plausible mistake would change -- the filtered index for the raw
// one, the tick position for tick.value - extent[0], a non-null extra, the
// piece bounds, the host series on a marker. They guard the harness and the
// reading of the source, not the port. Outside the script: run twice, diff.
//
// Math.random is pinned BEFORE the library loads (the builds capture it), TZ
// is UTC before anything reads a date, and every time case sets useUTC.
//
//   node tools/advchart-oracle/handlers.js
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

Math.random = function () { return 0; };

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-handlers.json');

function init(lib) {
  return lib.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
}

const clone = o => JSON.parse(JSON.stringify(o));
const S = x => String(x);

// ---------- handlers ----------

const HANDLERS = {
  '@L': p => 'L:' + [p.componentType, p.seriesType, p.seriesIndex, p.seriesName, p.name, p.dataIndex, S(p.value),
    p.percent === undefined ? '-' : S(p.percent), p.dataType == null ? '-' : p.dataType].join('|'),
  '@AX': (value, index, extra) => 'A:' + S(value) + '|' + S(index) + '|' + (extra == null ? 'null' : 'L' + extra.level),
  '@TT': (value, index, extra) => '{yyyy}/{M}/{d} ' + (extra == null ? 'null' : 'L' + extra.level),
  '@LG': name => 'G:' + name,
  '@VF': (value, dataIndex) => 'V:' + S(value) + '|' + S(dataIndex),
  '@AP': params => 'P:' + [params.axisDimension, params.axisIndex, S(params.value), params.seriesData.length,
    params.seriesData.map(s => s.seriesIndex + ':' + s.dataIndex).join(',')].join('|'),
  '@VM': (v1, v2) => 'M:' + S(v1) + '|' + S(v2),
  '@DZ': (value, valueStr) => 'Z:' + S(value) + '|' + S(valueStr),
  '@GD': value => 'D:' + S(value),
  '@GA': value => 'GA:' + S(value),
  '@RN': (name, indicator) => 'R:' + name + '|' + S(indicator && indicator.max),
  '@CM': params => 'C:' + [S(params.nameMap), S(params.yyyy), S(params.M), S(params.d)].join('|'),
};

// Every string in the option that is exactly a handler name becomes the
// function; everything else is copied as is.
function bind(v) {
  if (typeof v === 'string') return Object.prototype.hasOwnProperty.call(HANDLERS, v) ? HANDLERS[v] : v;
  if (Array.isArray(v)) return v.map(bind);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = bind(v[k]);
    return o;
  }
  return v;
}

const PREFIXES = ['L:', 'A:', 'G:', 'V:', 'P:', 'M:', 'Z:', 'D:', 'GA:', 'R:', 'C:'];
const TT = /\d{4}\/\d+\/\d+ /;
const ours = t => PREFIXES.some(p => t.startsWith(p)) || TT.test(t);

// ---------- reading the scene ----------

const paintedText = t => (t == null ? '' : String(t));

// Every ZRText zrender would paint: Storage skips an ignored element with
// everything under and on it (its textContent included), the painter skips an
// invisible displayable.
function sceneTexts(chart, exclude) {
  const out = [];
  const visit = (el, hidden) => {
    if (el === exclude) return;
    const off = hidden || !!el.ignore;
    if (el.type === 'text' && !off && !el.invisible) out.push(paintedText(el.style.text));
    const tc = el.getTextContent && el.getTextContent();
    if (tc) visit(tc, off);
    if (el.isGroup) el.eachChild(c => visit(c, off));
  };
  chart.getZr().storage.getRoots().forEach(r => visit(r, false));
  return out.filter(ours).sort();
}

// Makes one library render tooltips under node for the length of fn (see
// series-text.js): env.node off, getDom answering on the prototype.
function withTooltips(lib, fn) {
  const probe = init(lib);
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const getDom = proto.getDom;
  const wasNode = lib.env.node;
  const dom = {};
  proto.getDom = function () { return dom; };
  lib.env.node = false;
  try {
    return fn();
  } finally {
    proto.getDom = getDom;
    lib.env.node = wasNode;
  }
}

function tooltipEl(chart) {
  const model = chart.getModel().getComponent('tooltip', 0);
  const view = model && chart.getViewOfComponentModel(model);
  const content = view && view._tooltipContent;
  if (!content || !content._show || !content.el || content.el.ignore || content.el.invisible) return null;
  return content.el;
}

const SEGMENT = /\{__EC_aUTo_\d+\|([^}]*)\}/g;
// The segments and the text between them, line by line.
const tipPieces = text => text.replace(SEGMENT, '\u0001$1\u0001').split(/[\n\u0001]/);

// ---------- running a case ----------

function runCase(c, lib) {
  const body = () => {
    const chart = init(lib);
    try {
      const written = clone(c.option);
      written.animation = false;
      if (c.tip) {
        written.tooltip = Object.assign({ renderMode: 'richText', showDelay: 0, transitionDuration: 0 },
          written.tooltip || {});
      }
      chart.setOption(bind(clone(written)));
      const record = { name: c.name, option: written, texts: sceneTexts(chart) };
      if (c.tip) {
        const t = c.tip;
        if (t.trigger === 'item') {
          chart.dispatchAction({ type: 'showTip', seriesIndex: t.seriesIndex, dataIndex: t.dataIndex });
          record.tooltip = { trigger: 'item', seriesIndex: t.seriesIndex, dataIndex: t.dataIndex };
        } else {
          const x = chart.convertToPixel({ xAxisIndex: 0 }, t.category);
          const rect = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
          // a whole pixel: the port's pointer is placed by mouse coordinates
          const y = Math.floor(rect.y + rect.height / 2);
          chart.dispatchAction({ type: 'showTip', x, y });
          const xAxis = chart.getModel().getComponent('xAxis', 0).axis;
          record.tooltip = { trigger: 'axis', category: t.category,
            dataIndex: xAxis.scale.getOrdinalMeta().getOrdinal(t.category), x, y };
        }
        const el = tooltipEl(chart);
        record.tipShown = !!el;
        record.tipTexts = el ? tipPieces(String(el.style.text)).filter(ours).sort() : [];
        record.afterTexts = sceneTexts(chart, el);
      }
      return record;
    } finally {
      chart.dispose();
    }
  };
  return c.tip ? withTooltips(lib, body) : body();
}

function runEither(c) {
  try {
    return runCase(c, echarts);
  } catch (e) {
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(runCase(c, PROD), { productionBuild: true });
  }
}

// ---------- cases ----------

const cases = [];
const add = (name, option, tip) => cases.push(tip ? { name, option, tip } : { name, option });
const itemTip = (seriesIndex, dataIndex) => ({ trigger: 'item', seriesIndex, dataIndex });
const axisTip = category => ({ trigger: 'axis', category });

const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
const catX = (categories, series, extra) =>
  Object.assign({ xAxis: { type: 'category', data: categories }, yAxis: { type: 'value' }, series }, extra || {});
const valueXY = (series, extra) => Object.assign({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series }, extra || {});
const LBL = { show: true, formatter: '@L' };
const TEN = [5, 12, 7.5, 20, 3, 14, 9, 11, 0.1 + 0.2, 16];
const zoomX = (startValue, endValue, extra) => [Object.assign({ type: 'inside', xAxisIndex: 0, startValue, endValue }, extra || {})];

// ----- series labels '@L'

add('label bar category', catX(cats(5), [{ type: 'bar', name: 'S', data: [1, 2.5, -3, 0, 1234.5], label: LBL }]));
add('label bar dataZoom filter: dataIndex is raw', catX(cats(10), [{ type: 'bar', name: 'S', data: TEN, label: LBL }],
  { dataZoom: zoomX(3, 6) }));
add('label bar horizontal (value x, category y)', {
  xAxis: { type: 'value' }, yAxis: { type: 'category', data: cats(4) },
  series: [{ type: 'bar', name: 'H', data: [4, 8, 15, 16], label: LBL }],
});
add('label bar on value-value with a filtering dataZoom on x', valueXY([{
  type: 'bar', name: 'VV', data: [[1, 10], [2, 20], [3, 30], [4, 40], [5, 50], [6, 60]], label: LBL,
}], { dataZoom: [{ type: 'inside', xAxisIndex: 0, startValue: 2.5, endValue: 5.5, filterMode: 'filter' }] }));
add('label bar two series, second unnamed', catX(cats(3), [
  { type: 'bar', name: 'A', data: [1, 2, 3], label: LBL },
  { type: 'bar', data: [4, 5, 6], label: LBL },
]));
add('label line dataZoom filter', catX(cats(8), [{ type: 'line', name: 'Ln', data: TEN.slice(0, 8), label: LBL }],
  { dataZoom: zoomX(2, 5) }));
add('label scatter array values', valueXY([{ type: 'scatter', name: 'Sc', data: [[1, 2], [3.5, 4, 'x'], [5, 6]], label: LBL }]));
add('label scatter dataZoom filter on x', valueXY([{
  type: 'scatter', name: 'Sc', data: [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6]], label: LBL,
}], { dataZoom: [{ type: 'inside', xAxisIndex: 0, startValue: 2, endValue: 4, filterMode: 'filter' }] }));
add('label pie percent', { series: [{ type: 'pie', name: 'P', label: LBL,
  data: [{ name: 'a', value: 1 }, { name: 'b', value: 1 }, { name: 'c', value: 2 }, { name: 'd', value: 3 }] }] });
add('label pie legend-deselected slice: raw index and percent of the rest', {
  legend: { selected: { b: false } },
  series: [{ type: 'pie', name: 'P', label: LBL,
    data: [{ name: 'a', value: 1 }, { name: 'b', value: 5 }, { name: 'c', value: 2 }] }],
});
add('label pie all zero: percent 0', { series: [{ type: 'pie', name: 'P', label: LBL,
  data: [{ name: 'a', value: 0 }, { name: 'b', value: 0 }] }] });
add('label funnel percent', { series: [{ type: 'funnel', name: 'F', label: LBL,
  data: [{ name: 'x', value: 60 }, { name: 'y', value: 40.123 }, { name: 'z', value: 1 }] }] });
add('label graph nodes and edges', { series: [{
  type: 'graph', name: 'G', layout: 'none', label: LBL, edgeLabel: { show: true, formatter: '@L' },
  data: [{ name: 'n1', x: 0, y: 0, value: 1.5 }, { name: 'n2', x: 100, y: 100 }, { name: 'n3', x: 100, y: 0, value: 7 }],
  links: [{ source: 'n1', target: 'n2', value: 9 }, { source: 'n2', target: 'n3' }],
}] });
add('label tree', { series: [{
  type: 'tree', name: 'T', label: LBL, leaves: { label: LBL },
  data: [{ name: 'root', value: 10, children: [{ name: 'a', value: 4 }, { name: 'b', children: [{ name: 'b1', value: 2 }] }] }],
}] });
add('label sunburst', { series: [{
  type: 'sunburst', name: 'SB', label: LBL,
  data: [{ name: 'A', children: [{ name: 'a1', value: 3 }, { name: 'a2', value: 5 }] }, { name: 'B', value: 4 }],
}] });
add('label treemap', { series: [{
  type: 'treemap', name: 'TM', label: LBL, breadcrumb: { show: false },
  data: [{ name: 'A', value: 10 }, { name: 'B', value: 6 }, { name: 'C', value: 4 }],
}] });
add('label sankey nodes and edges', { series: [{
  type: 'sankey', name: 'SK', label: LBL, edgeLabel: { show: true, formatter: '@L' },
  data: [{ name: 'a' }, { name: 'b' }, { name: 'c', value: 99 }],
  links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }],
}] });
// a node's own value under its flow: the layout takes the flow, the label
// the value as written
add('label sankey node value below its flow', { series: [{
  type: 'sankey', name: 'SK', label: LBL,
  data: [{ name: 'a' }, { name: 'b', value: 2 }, { name: 'c' }],
  links: [{ source: 'a', target: 'b', value: 5 }, { source: 'b', target: 'c', value: 4 }],
}] });
add('label heatmap cartesian', {
  xAxis: { type: 'category', data: ['x0', 'x1'] }, yAxis: { type: 'category', data: ['y0', 'y1'] },
  visualMap: { min: 0, max: 10, show: false },
  series: [{ type: 'heatmap', name: 'HM', label: LBL, data: [[0, 0, 5], [1, 0, 7.5], [0, 1, 2], [1, 1, 9]] }],
});
add('label candlestick', catX(['d0', 'd1'], [{
  type: 'candlestick', name: 'K', label: LBL, data: [[20, 34, 10, 38], [40, 35, 30, 50]],
}]));
add('label radar: one call per indicator', {
  radar: { indicator: [{ name: 'A', max: 10 }, { name: 'B', max: 10 }, { name: 'C', max: 10 }] },
  series: [{ type: 'radar', name: 'R', label: LBL, data: [{ name: 'r', value: [3, 5.5, 8] }] }],
});
add('label item-level @L over a series template', catX(cats(3), [{
  type: 'bar', name: 'S', label: { show: true, formatter: 'T{b}' },
  data: [1, { value: 2, label: { formatter: '@L' } }, 3],
}]));
add('label item-level template over a series @L', catX(cats(3), [{
  type: 'bar', name: 'S', label: LBL,
  data: [1, { value: 2, label: { formatter: 'I{c}' } }, 3],
}]));
add('label markers on bar: markPoint, markLine, markArea', catX(cats(4), [{
  type: 'bar', name: 'S', data: [3, 8, 5, 2],
  markPoint: { label: LBL, data: [{ name: 'mp', coord: ['c1', 8], value: 42 }, { type: 'max', name: 'top' }] },
  markLine: { label: LBL, data: [{ name: 'ml', yAxis: 4 }, { type: 'average', name: 'avg' }] },
  markArea: { label: LBL, data: [[{ name: 'ma', xAxis: 'c1' }, { xAxis: 'c2' }]] },
}]));
add('label markPoint on the second series of a line chart', catX(cats(3), [
  { type: 'line', name: 'L0', data: [1, 2, 3] },
  { type: 'line', name: 'L1', data: [4, 6, 5], markPoint: { label: LBL, data: [{ type: 'min', name: 'lo' }] } },
]));

// ----- axis labels '@AX' / '@TT'

add('axisLabel category interval 1: index gaps', catX(cats(7), [{ type: 'bar', data: [1, 2, 3, 4, 5, 6, 7] }],
  { xAxis: { type: 'category', data: cats(7), axisLabel: { interval: 1, formatter: '@AX' } } }));
add('axisLabel category dataZoom: index = tick.value - extent[0]', catX(cats(10), [{ type: 'bar', data: TEN }],
  { xAxis: { type: 'category', data: cats(10), axisLabel: { interval: 0, formatter: '@AX' } }, dataZoom: zoomX(4, 7) }));
add('axisLabel category on y', {
  xAxis: { type: 'value' }, yAxis: { type: 'category', data: cats(4), axisLabel: { interval: 0, formatter: '@AX' } },
  series: [{ type: 'bar', data: [1, 2, 3, 4] }],
});
add('axisLabel value', catX(cats(3), [{ type: 'bar', data: [10, 55, 83] }],
  { yAxis: { type: 'value', axisLabel: { formatter: '@AX' } } }));
add('axisLabel value with a dataZoom window', valueXY([{ type: 'scatter', data: [[0, 1], [10, 2], [20, 3], [30, 4]] }],
  { xAxis: { type: 'value', axisLabel: { formatter: '@AX', rotate: 90, showMinLabel: true, showMaxLabel: true, hideOverlap: false } },
    dataZoom: [{ type: 'inside', xAxisIndex: 0, startValue: 5, endValue: 25 }] }));
add('axisLabel log', catX(cats(3), [{ type: 'line', data: [1, 100, 10000] }],
  { yAxis: { type: 'log', axisLabel: { formatter: '@AX' } } }));
const DAY = 86400000;
const T0 = Date.UTC(2020, 0, 2);
// The axes with wide labels turn them upright (rotate: 90) so no two overlap,
// force the end labels (showMinLabel/showMaxLabel: true, which also skips the
// time axis' drop of a not-nice end tick) and switch hideOverlap off: which
// labels are drawn then does not hang on text metrics. (Unrotated, a forced end
// label that overlaps its neighbour hides the NEIGHBOUR -- fixMinMaxLabelShow.)
const timeLine = (fmt, days) => ({
  useUTC: true,
  xAxis: { type: 'time', axisLabel: { formatter: fmt, rotate: 90, showMinLabel: true, showMaxLabel: true, hideOverlap: false } }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: Array.from({ length: days }, (_, i) => [T0 + i * DAY, i + 1]) }],
});
add('axisLabel time @AX: days', timeLine('@AX', 5));
add('axisLabel time @TT: days', timeLine('@TT', 5));
add('axisLabel time @TT: across a month boundary', {
  useUTC: true,
  xAxis: { type: 'time', axisLabel: { formatter: '@TT', rotate: 90, showMinLabel: true, showMaxLabel: true, hideOverlap: false } }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: [[Date.UTC(2020, 0, 20), 1], [Date.UTC(2020, 1, 12), 2]] }],
});
add('axisLabel time @AX: across a year boundary', {
  useUTC: true,
  xAxis: { type: 'time', axisLabel: { formatter: '@AX', rotate: 90, showMinLabel: true, showMaxLabel: true, hideOverlap: false } }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: [[Date.UTC(2019, 9, 1), 1], [Date.UTC(2020, 3, 1), 2]] }],
});

// ----- legend '@LG'

add('legend series names', catX(cats(2), [
  { type: 'bar', name: 'Alpha', data: [1, 2] }, { type: 'line', name: 'Beta', data: [2, 1] },
], { legend: { formatter: '@LG' } }));
add('legend pie data names', { legend: { formatter: '@LG' }, series: [{ type: 'pie', name: 'P',
  data: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }, { name: 'z', value: 3 }] }] });

// ----- tooltip.valueFormatter '@VF'

add('tooltip item global @VF on bar', catX(cats(4), [{ type: 'bar', name: 'S', data: [3, 8.5, 5, 2] }],
  { tooltip: { trigger: 'item', valueFormatter: '@VF' } }), itemTip(0, 1));
add('tooltip item @VF with dataZoom filter: dataIndex is raw', catX(cats(10), [{ type: 'bar', name: 'S', data: TEN }],
  { tooltip: { trigger: 'item', valueFormatter: '@VF' }, dataZoom: zoomX(3, 6) }), itemTip(0, 5));
add('tooltip item series-level @VF', catX(cats(3), [{ type: 'bar', name: 'S', data: [3, 4, 5], tooltip: { valueFormatter: '@VF' } }],
  { tooltip: { trigger: 'item' } }), itemTip(0, 2));
add('tooltip item pie @VF', { tooltip: { trigger: 'item', valueFormatter: '@VF' }, series: [{ type: 'pie', name: 'P',
  data: [{ name: 'x', value: 1 }, { name: 'y', value: 2.5 }] }] }, itemTip(0, 1));
add('tooltip item scatter array value @VF', valueXY([{ type: 'scatter', name: 'Sc', data: [[1, 2], [3.5, 4]] }],
  { tooltip: { trigger: 'item', valueFormatter: '@VF' } }), itemTip(0, 1));
add('tooltip item candlestick sub-rows @VF', catX(['d0', 'd1'], [{ type: 'candlestick', name: 'K',
  data: [[20, 34, 10, 38], [40, 35, 30, 50]] }], { tooltip: { trigger: 'item', valueFormatter: '@VF' } }), itemTip(0, 1));
add('tooltip axis global @VF over two series', catX(cats(3), [
  { type: 'bar', name: 'A', data: [1, 2, 3] }, { type: 'line', name: 'B', data: [4.5, 5, 6] },
], { tooltip: { trigger: 'axis', valueFormatter: '@VF' } }), axisTip('c1'));
add('tooltip axis series-level @VF on one series only', catX(cats(3), [
  { type: 'bar', name: 'A', data: [1, 2, 3], tooltip: { valueFormatter: '@VF' } }, { type: 'line', name: 'B', data: [4.5, 5, 6] },
], { tooltip: { trigger: 'axis' } }), axisTip('c2'));
add('tooltip axis @VF with dataZoom filter', catX(cats(10), [
  { type: 'bar', name: 'A', data: TEN }, { type: 'line', name: 'B', data: TEN.map(v => v * 2) },
], { tooltip: { trigger: 'axis', valueFormatter: '@VF' }, dataZoom: zoomX(3, 6) }), axisTip('c5'));

// ----- axisPointer.label '@AP'

add('axisPointer label on axis tooltip, dataZoom filtered', catX(cats(10), [
  { type: 'bar', name: 'A', data: TEN }, { type: 'line', name: 'B', data: TEN.map(v => v + 1) },
], {
  xAxis: { type: 'category', data: cats(10), axisPointer: { label: { show: true, formatter: '@AP' } } },
  tooltip: { trigger: 'axis' }, dataZoom: zoomX(3, 6),
}), axisTip('c4'));
add('axisPointer cross label on both axes', catX(cats(4), [{ type: 'line', name: 'A', data: [2, 4, 6, 8] }], {
  tooltip: { trigger: 'axis', axisPointer: { type: 'cross', label: { formatter: '@AP' } } },
}), axisTip('c2'));
add('axisPointer status show with a value, no tooltip trigger', catX(cats(4), [{ type: 'bar', name: 'A', data: [2, 4, 6, 8] }], {
  xAxis: { type: 'category', data: cats(4), axisPointer: { show: true, status: 'show', value: 'c1', label: { show: true, formatter: '@AP' } } },
}));

// ----- visualMap '@VM'

const vmScatter = vm => valueXY([{ type: 'scatter', data: [[1, 1, 5], [2, 2, 50], [3, 3, 95]], encode: { x: 0, y: 1 } }],
  { visualMap: Object.assign({ dimension: 2, formatter: '@VM' }, vm) });
add('visualMap continuous calculable: handle labels', vmScatter({ type: 'continuous', min: 0, max: 100, calculable: true }));
add('visualMap continuous calculable with a range', vmScatter({ type: 'continuous', min: 0, max: 100, calculable: true, range: [20.5, 80] }));
add('visualMap continuous not calculable: no call', vmScatter({ type: 'continuous', min: 0, max: 100 }));
add('visualMap piecewise pieces', vmScatter({ type: 'piecewise', pieces: [
  { min: 0, max: 10 }, { gt: 10, lte: 40 }, { min: 60 }, { lt: 0 }, { value: 50 }, { min: 40, max: 60, label: 'mid' },
] }));
add('visualMap piecewise splitNumber', vmScatter({ type: 'piecewise', min: 0, max: 100, splitNumber: 4 }));
add('visualMap piecewise categories', valueXY([{ type: 'scatter', data: [[1, 1, 'A'], [2, 2, 'B']] }],
  { visualMap: { type: 'piecewise', dimension: 2, categories: ['A', 'B', 'C'], formatter: '@VM' } }));

// ----- dataZoom slider '@DZ'

const slider = extra => Object.assign({ type: 'slider', handleLabel: { show: true }, labelFormatter: '@DZ' }, extra);
add('dataZoom slider category', catX(cats(10), [{ type: 'bar', data: TEN }], { dataZoom: [slider({ startValue: 2, endValue: 7 })] }));
add('dataZoom slider value', valueXY([{ type: 'scatter', data: [[0, 1], [10, 2], [20, 3], [33.3, 4]] }],
  { dataZoom: [slider({ xAxisIndex: 0, start: 10, end: 75 })] }));
add('dataZoom slider value labelPrecision 1', valueXY([{ type: 'scatter', data: [[0, 1], [10, 2], [20, 3], [33.3, 4]] }],
  { dataZoom: [slider({ xAxisIndex: 0, start: 10, end: 75, labelPrecision: 1 })] }));
add('dataZoom slider time', Object.assign(timeLine(undefined, 10), {
  dataZoom: [slider({ startValue: T0 + 2 * DAY, endValue: T0 + 6 * DAY + 3600000 })] }));

// ----- gauge '@GD' / '@GA'

add('gauge detail and axis labels', { series: [{ type: 'gauge', name: 'Ga', min: 0, max: 1, splitNumber: 4,
  detail: { formatter: '@GD' }, axisLabel: { formatter: '@GA' }, data: [{ name: 't', value: 0.123456789 }] }] });
add('gauge two items, negative range', { series: [{ type: 'gauge', name: 'Ga', min: -0.3, max: 0.3, splitNumber: 3,
  detail: { formatter: '@GD' }, axisLabel: { formatter: '@GA' },
  data: [{ name: 'a', value: -0.1, detail: { offsetCenter: [0, '20%'] } }, { name: 'b', value: 0.2, detail: { offsetCenter: [0, '50%'] } }] }] });

// ----- radar '@RN'

add('radar axisName', {
  radar: { axisName: { formatter: '@RN' }, indicator: [{ name: 'A', max: 20000 }, { name: 'B' }, { name: 'C', min: -5 }] },
  series: [{ type: 'radar', data: [{ value: [100, 5, -2] }] }],
});

// ----- calendar '@CM'

add('calendar month, year (and day) labels', {
  calendar: { range: ['2020-01', '2020-03'], cellSize: 12,
    monthLabel: { formatter: '@CM' }, yearLabel: { show: true, formatter: '@CM' }, dayLabel: { formatter: '@CM' } },
  series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [['2020-01-05', 3]] }],
  visualMap: { min: 0, max: 10, show: false },
});
add('calendar across two years, vertical', {
  calendar: { range: ['2019-11-01', '2020-02-10'], orient: 'vertical', cellSize: 10,
    monthLabel: { formatter: '@CM' }, yearLabel: { formatter: '@CM' } },
  series: [{ type: 'scatter', coordinateSystem: 'calendar', data: [['2019-12-05', 3]] }],
});

// ---------- run ----------

const out = { source: 'ECharts ' + echarts.version, cases: cases.map(runEither) };

// ---------- guards ----------

// Worked out from the source by hand (see the header); each would change
// under the named mistake.
const find = name => out.cases.find(c => c.name === name);
const GUARDS = [
  // the filtered index 2 instead of the raw 5
  ['label bar dataZoom filter: dataIndex is raw', r => r.texts, [
    'L:series|bar|0|S|c3|3|20|-|-', 'L:series|bar|0|S|c4|4|3|-|-', 'L:series|bar|0|S|c5|5|14|-|-', 'L:series|bar|0|S|c6|6|9|-|-']],
  ['label pie percent', r => r.texts, [
    'L:series|pie|0|P|a|0|1|14.29|-', 'L:series|pie|0|P|b|1|1|14.28|-', 'L:series|pie|0|P|c|2|2|28.57|-',
    'L:series|pie|0|P|d|3|3|42.86|-']],
  // raw index 2 for c, and its share of 1 + 2
  ['label pie legend-deselected slice: raw index and percent of the rest', r => r.texts, [
    'L:series|pie|0|P|a|0|1|33.33|-', 'L:series|pie|0|P|c|2|2|66.67|-']],
  ['label funnel percent', r => r.texts, [
    'L:series|funnel|0|F|x|0|60|59.33|-', 'L:series|funnel|0|F|y|1|40.123|39.68|-', 'L:series|funnel|0|F|z|2|1|0.99|-']],
  // the node without a value takes its layout value (the sum of edges is 9
  // in and none out: max(9, 0))
  ['label graph nodes and edges', r => r.texts.filter(t => t.endsWith('|edge')), [
    'L:series|graph|0|G|n1 > n2|0|9|-|edge', 'L:series|graph|0|G|n2 > n3|1|undefined|-|edge']],
  // marker params carry the host series and no percent/dataType
  ['label markers on bar: markPoint, markLine, markArea', r => r.texts.filter(t => t.includes('|mp|') || t.includes('|ml|') || t.includes('|ma|')), [
    'L:markArea|bar|0|S|ma|0|undefined|-|-', 'L:markLine|bar|0|S|ml|0|4|-|-', 'L:markPoint|bar|0|S|mp|0|42|-|-']],
  ['label markPoint on the second series of a line chart', r => r.texts, ['L:markPoint|line|1|L1|lo|0|4|-|-']],
  // the tick's position in the window, not in all categories; extra null
  ['axisLabel category dataZoom: index = tick.value - extent[0]', r => r.texts, [
    'A:c4|0|null', 'A:c5|1|null', 'A:c6|2|null', 'A:c7|3|null']],
  ['axisLabel category interval 1: index gaps', r => r.texts, [
    'A:c0|0|null', 'A:c2|2|null', 'A:c4|4|null', 'A:c6|6|null']],
  ['axisLabel log', r => r.texts, ['A:10000|4|null', 'A:1000|3|null', 'A:100|2|null', 'A:10|1|null', 'A:1|0|null']],
  // day ticks inside one month are level 0
  ['axisLabel time @TT: days', r => r.texts.slice(0, 2), ['2020/1/2 L0', '2020/1/3 L0']],
  ['legend series names', r => r.texts, ['G:Alpha', 'G:Beta']],
  ['tooltip item @VF with dataZoom filter: dataIndex is raw', r => r.tipTexts, ['V:14|5']],
  ['tooltip axis series-level @VF on one series only', r => r.tipTexts, ['V:3|2']],
  ['axisPointer label on axis tooltip, dataZoom filtered', r => r.afterTexts, ['P:x|0|c4|2|0:4,1:4']],
  ['visualMap continuous calculable: handle labels', r => r.texts, ['M:0|undefined', 'M:100|undefined']],
  ['visualMap piecewise categories', r => r.texts, ['M:A|undefined', 'M:B|undefined', 'M:C|undefined']],
  ['dataZoom slider category', r => r.texts, ['Z:2|c2', 'Z:7|c7']],
  ['gauge detail and axis labels', r => r.texts, ['D:0.123456789', 'GA:0', 'GA:0.25', 'GA:0.5', 'GA:0.75', 'GA:1']],
  ['radar axisName', r => r.texts, ['R:A|20000', 'R:B|undefined', 'R:C|0']],
  ['calendar month, year (and day) labels', r => r.texts, [
    'C:2020|undefined|undefined|undefined', 'C:Feb|2020|2|undefined', 'C:Jan|2020|1|undefined', 'C:Mar|2020|3|undefined']],
];
const fails = [];
for (const [name, read, want] of GUARDS) {
  const r = find(name);
  const got = r ? JSON.stringify(read(r)) : 'no such case';
  if (got !== JSON.stringify(want)) fails.push(name + ': ' + got + ', expected ' + JSON.stringify(want));
}
if (fails.length) {
  fails.forEach(f => console.log('guard failed: ' + f));
  console.log('FAILED: ' + fails.length + ' guard(s); the fixture is not written');
  process.exit(1);
}
console.log('guards: ' + GUARDS.length + '/' + GUARDS.length);

const empty = out.cases.filter(c => !c.texts.length && !(c.tipTexts && c.tipTexts.length)
  && !(c.afterTexts && c.afterTexts.length)).map(c => c.name);
if (empty.length) console.log('cases drawing no handler text:', empty.join('; '));
const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote', OUT, out.cases.length + ' cases');
process.exit(0);
