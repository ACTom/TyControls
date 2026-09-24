// Upstream's own answers for the text a series puts on screen for its values:
// data labels, the default tooltip rows, tooltip formatter templates, and a
// gauge's titles, details and axis labels.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode and reads what zrender is handed to
// draw, never what an API claims the text would be:
//
//   labels    for every raw data item of every series: the item's graphic
//             element (data.getItemGraphicEl on the item's index after
//             filtering), then every label (getTextContent) on it or on any
//             element below it. drawn is false when the item has no element --
//             a null bar, a legend-filtered or negative pie slice. A NaN pie
//             slice keeps its sector (with NaN angles, so nothing is painted)
//             and an ignored label: drawn true, no texts. texts holds
//             the labels zrender paints, in tree order: a label that is
//             ignored, sits under an ignored element, or is invisible is left
//             out. A null style.text is written as '', which is what zrender
//             paints for it. series.getFormattedLabel is not used: it answers
//             only when a string formatter applies (the view picks the default
//             text itself), and it answers for items that are never drawn.
//   tooltips  the real TooltipView with renderMode 'richText', showDelay 0 and
//             transitionDuration 0, so the show is synchronous. TooltipView
//             bails on env.node or on a missing DOM, so for these cases env.node
//             is switched off and the chart prototype's getDom answers a bare
//             object (see withTooltips). An item tooltip is a showTip action on
//             a series and raw data index, an axis tooltip a showTip at the
//             category's pixel on x and the middle of the grid on y, and a graph
//             edge tooltip a mousemove through zrender at the edge's midpoint
//             after an SVG render has laid the transforms down; the mouseover
//             that hover fires is checked to name the edge asked for. What is
//             read back is the one ZRText TooltipRichContent adds: text is its
//             style.text as zrender lays it out. Each '\n' line is split into
//             '{__EC_aUTo_N|...}' segments and each segment classified by
//             style.rich[N] (format.ts getTooltipMarker, tooltipMarkup.ts
//             getTooltipTextStyle): a width of 10 is an item marker, 4 a
//             subItem marker, fontWeight '900' a value, '400' a name or header.
//             A line of a formatter template has no segments at all, so all
//             three are null there. visible is the text with the segment
//             wrappers taken off; for a formatter template it is also
//             entity-decoded, because formatTpl encodes its substitutions even
//             in richText mode while a browser (renderMode 'auto' is html)
//             decodes them -- the default markup is not encoded in richText.
//   gauge     GaugeView's _titleEls[i] and _detailEls[i] for every data item,
//             and the axis labels: the silent Texts _renderTicks adds straight
//             to the view's group, one per split, in tick order.
//
// A case marked deferred depends on something the port does not keep or draw
// yet (sub-row tooltips, encode, the unnamed series' auto name, the parse of a
// raw string into the number drawn, ...). Its upstream answer is recorded all
// the same, so a later batch only has to take the flag off; why says what it
// waits for.
//
// Spot checks (the fixture is not written and the run exits 1 when one
// fails): a handful of recorded answers are compared with what separate
// probes of the same build printed -- the raw-value cases' scalar fallback,
// null against a missing value, arrays joined, datasets, the tooltip cell's
// reparse. They guard the harness, not the port. Outside the script: run
// twice and diff.
//
// Math.random is replaced by a constant BEFORE the library loads (the builds
// capture it at load time). TooltipMarkupStyleCreator starts naming its rich
// styles at round(random * 9), so without this the raw tooltip text would name
// them differently on every run; with it every tooltip names them from
// __EC_aUTo_0 up and the fixture is reproducible.
//
// The option each case ran is written out as given. Numbers in it are plain
// JSON, except that one JSON.stringify would write as an integer literal past
// 2^63 goes out in exponent form (1.2345678901234568e+20, not
// 123456789012345680000), because the Pascal JSON reader misparses those.
//
//   node tools/advchart-oracle/series-text.js
'use strict';
const fs = require('fs');
const path = require('path');

Math.random = function () { return 0; };

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// The development build asserts its own invariants and throws where the
// production build carries on; a case that trips one is run through the
// production build instead, which is what a page actually ships, and says so.
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-series-text.json');

function init(lib) {
  return lib.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
}

const clone = o => JSON.parse(JSON.stringify(o));

// Makes one library render tooltips under node for the length of fn: env.node
// off, getDom answering on the prototype. The ExtensionAPI binds getDom when
// the chart is built, hence the prototype, before init. Put back whatever
// happens.
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

// zrender paints text + '' and nothing for null (formatText); a radar label
// even stores a Number.
const paintedText = t => (t == null ? '' : String(t));

// Whether zrender paints a label: Storage skips an ignored element with
// everything under and on it, and the painter skips an invisible displayable.
function labelShown(textEl, host) {
  if (textEl.ignore || textEl.invisible) return false;
  for (let n = host; n; n = n.parent) {
    if (n.ignore) return false;
  }
  return true;
}

function itemLabels(el) {
  const out = [];
  (function walk(node) {
    const tc = node.getTextContent && node.getTextContent();
    if (tc && labelShown(tc, node)) out.push(paintedText(tc.style.text));
    if (node.isGroup) node.eachChild(walk);
  })(el);
  return out;
}

function withDeferred(record, c) {
  if (c.deferred) {
    record.deferred = true;
    record.why = c.deferred;
  }
  return record;
}

// ---------- labels ----------

function runLabels(c, lib) {
  const chart = init(lib);
  try {
    const option = clone(c.option);
    option.animation = false;
    const written = clone(option);
    chart.setOption(option);
    const series = [];
    chart.getModel().eachSeries(s => {
      const data = s.getData();
      const count = s.getRawData().count();
      const items = [];
      // dataIndex is the raw index -- the position in the option's data --
      // so an item a legend or a negative value filtered out still has a row.
      for (let r = 0; r < count; r++) {
        const i = data.indexOfRawIndex(r);
        const el = i >= 0 ? data.getItemGraphicEl(i) : null;
        items.push({ dataIndex: r, drawn: !!el, texts: el ? itemLabels(el) : [] });
      }
      series.push({ seriesIndex: s.seriesIndex, type: s.subType, items });
    });
    const record = withDeferred({ name: c.name, option: written }, c);
    record.series = series;
    return record;
  } finally {
    chart.dispose();
  }
}

const labels = [];
const label = (name, option, extra) => labels.push(Object.assign({ name, option }, extra || {}));
const deferredFor = why => ({ deferred: why });

// The values the number text is held to. {value: 7} is an item object, null
// and '-' are missing values: no bar, no symbol, '-' in a tooltip row.
const V = [0.1 + 0.2, 1e-7, 5e-7, 0.0000015, 1e17, 1e21, 123456789012345.6, 1.2345678901234568e20,
  1.23456789, 1 / 3, -1234.5, 0, { value: 7 }, null, '-'];
const VC = V.map((_, i) => 'c' + i);

const catX = (cats, series) => ({ xAxis: { type: 'category', data: cats }, yAxis: { type: 'value' }, series });
const catY = (cats, series) => ({ xAxis: { type: 'value' }, yAxis: { type: 'category', data: cats }, series });
const valueXY = series => ({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series });
const named = (names, values) => values.map((v, i) => ({ name: names[i], value: v }));
const nNames = values => named(values.map((_, i) => 'n' + i), values);

// bar
label('bar: default labels on V', catX(VC, [{ type: 'bar', name: 'S', data: V, label: { show: true } }]));
label('bar horizontal: default labels on V', catY(VC, [{ type: 'bar', name: 'S', data: V, label: { show: true } }]));
label('bar stacked: each series labels its own value', catX(['A', 'B', 'C'], [
  { type: 'bar', name: 'S1', stack: 't', data: [0.1 + 0.2, 1e-7, 1.23456789], label: { show: true } },
  { type: 'bar', name: 'S2', stack: 't', data: [1 / 3, -1234.5, 12.5], label: { show: true } },
]));
// A bar of no length keeps its label: stacked on 1e17, a third is no length
// at all -- upstream draws it flat, number and all.
label('bar stacked: a bar too short to see keeps its label', catX(['A', 'B', 'C'], [
  { type: 'bar', name: 'S1', stack: 't', data: [0.1 + 0.2, 1e-7, 1.23456789], label: { show: true } },
  { type: 'bar', name: 'S2', stack: 't', data: [1 / 3, -1234.5, 1e17], label: { show: true } },
]));
for (const f of ['{a}|{b}|{c}', '{c}/{c}', '{a0}|{b0}|{c0}', '{d}|{e}|{c1}']) {
  label('bar template ' + f + ' on V', catX(VC, [{ type: 'bar', name: 'S', data: V, label: { show: true, formatter: f } }]));
}
label("bar formatter '': an empty label", catX(['A', 'B'], [
  { type: 'bar', name: 'S', data: [1, 2.5], label: { show: true, formatter: '' } },
]));
label('bar numeric series name 2015: {a}', catX(['A'], [
  { type: 'bar', name: 2015, data: [5], label: { show: true, formatter: '{a}|{c}' } },
]));
// The one case with '$' in a name: the name is the replacement string of a
// String.replace, so '$&' puts back the matched '{b0}', '$$' is one '$' and
// "$'" is what follows the match.
label("bar template [{b}] on names with '$' patterns", catX(['$&x', '$$y', "$'z"], [
  { type: 'bar', name: 'S', data: [1, 2, 3], label: { show: true, formatter: '[{b}]' } },
]));

// line
label('line: default labels on V', catX(VC, [{ type: 'line', name: 'L', data: V, label: { show: true } }]));
label('line showSymbol false: no labels', catX(['A', 'B'], [
  { type: 'line', name: 'L', showSymbol: false, data: [1, 2], label: { show: true } },
]));

// scatter
label('scatter: the label is y', valueXY([
  { type: 'scatter', name: 'Sc', data: [[1234.5, 20.5], [3, 4, 5]], label: { show: true } },
]));

// pie
label('pie: default names', { series: [{ type: 'pie', name: 'P', data: [
  { name: 'x', value: 1 }, { value: 2 }, { name: 'z', value: '-' }, { name: 'n', value: null }, { name: 5, value: 3 },
] }] });
for (const values of [[1, 1, 1], [1, 2, 4]]) {
  for (const p of [2, 0, 5, 8, -1]) {
    label('pie percentPrecision ' + p + ' on ' + JSON.stringify(values), { series: [{
      type: 'pie', name: 'P', percentPrecision: p, data: nNames(values), label: { formatter: '{a}|{b}|{c}|{d}' },
    }] });
  }
}
for (const values of [[1, 1], [0, 0], [1, '-', 3, null], [5, -3, 2]]) {
  label('pie {d} on ' + JSON.stringify(values), { series: [{
    type: 'pie', name: 'P', data: nNames(values), label: { formatter: '{a}|{b}|{c}|{d}' },
  }] });
}
label('pie legend.selected: the middle slice off', {
  legend: { selected: { n1: false } },
  series: [{ type: 'pie', name: 'P', data: nNames([1, 2, 3]), label: { formatter: '{b}:{c}:{d}' } }],
});
label("pie formatter '': an empty label, leader line kept", { series: [{
  type: 'pie', name: 'P', data: nNames([1, 2]), label: { formatter: '' },
}] });

// funnel
label('funnel: default names', { series: [{ type: 'funnel', name: 'F', data: named(['x', 'y', 'z'], [60, 40.123, 1]) }] });
label('funnel {d} on [60,40.123,1]', { series: [{
  type: 'funnel', name: 'F', data: named(['x', 'y', 'z'], [60, 40.123, 1]), label: { formatter: '{a}|{b}|{c}|{d}' },
}] });
for (const values of [[1, 1, 1], [1, 2, 4], [5, -3, 2]]) {
  label('funnel {d} on ' + JSON.stringify(values), { series: [{
    type: 'funnel', name: 'F', data: nNames(values), label: { formatter: '{a}|{b}|{c}|{d}' },
  }] });
}
label("funnel {d} of a '-' item is NaN", { series: [{
  type: 'funnel', name: 'F', data: named(['a', 'd'], [1, '-']), label: { formatter: '{a}|{b}|{d}' },
}] });
label('funnel legend.selected: the middle item off', {
  legend: { selected: { n1: false } },
  series: [{ type: 'funnel', name: 'F', data: nNames([1, 2, 3]), label: { formatter: '{b}:{d}' } }],
});
label("funnel formatter '': an empty label", { series: [{
  type: 'funnel', name: 'F', data: nNames([1, 2]), label: { formatter: '' },
}] });

// graph
label('graph: default label {b}', { series: [{
  type: 'graph', name: 'G', layout: 'none', label: { show: true },
  data: [{ name: 'n1', x: 0, y: 0, value: 1.5 }, { name: 'n2', x: 10, y: 10 }, { name: 'n3', x: 5, y: 5, value: 0.1 + 0.2 }],
  links: [{ source: 'n1', target: 'n2' }],
}] });
label('graph cartesian2d: label formatter null is the value', catX(['a', 'b'], [{
  type: 'graph', name: 'G', coordinateSystem: 'cartesian2d', data: [['a', 1.5], ['b', 0.1 + 0.2]],
  label: { show: true, formatter: null },
}]));

// candlestick
label('candlestick: label.show draws no data text', catX(['d0', 'd1'], [{
  type: 'candlestick', name: 'K', data: [[20, 34, 10, 38], [1.5, 2.25, 0.5, 3]], label: { show: true },
}]));
// ... and not with a formatter either: a candlestick has no single value
// column, so without one the default text is empty on both sides
label('candlestick: a label formatter draws nothing either', catX(['d0', 'd1'], [{
  type: 'candlestick', name: 'K', data: [[20, 34, 10, 38], [1.5, 2.25, 0.5, 3]],
  label: { show: true, formatter: '{b}|{c}' },
}]));

// numbers as names: a category collected from the data, and a data item's
// own name, are `'' + x` -- 0.30000000000000004 and 1e+21, not 0.3 and 1E21
label('bar: numeric categories are named as JavaScript names them', {
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', name: 'S', data: [[0.1 + 0.2, 1], [1e21, 2], [1.23456789, 3]],
    label: { show: true, formatter: '{b}' } }],
});
label('pie: numeric names', { series: [{ type: 'pie', name: 'P', data: [
  { name: 1.23456789, value: 1 }, { name: 1e21, value: 2 }, { name: 0.1 + 0.2, value: 3 }] }] });

// The raw value as written -- and a scalar item, which answers every {@dim},
// [n] or name, with its one value (retrieveRawValue)
label('bar template {@[0]}|{@value}|{@nope} on V', catX(VC, [
  { type: 'bar', name: 'S', data: V, label: { show: true, formatter: '{@[0]}|{@value}|{@nope}' } },
]));
label('bar: raw strings and booleans', catX(['A', 'B', 'C', 'D', 'E'], [
  { type: 'bar', name: 'S', data: ['12.50', ' 5 ', '1e3', true, 'abc'], label: { show: true } },
]));
label('graph cartesian2d: label formatter null on a raw string', catX(['a', 'b'], [{
  type: 'graph', name: 'G', coordinateSystem: 'cartesian2d', data: [['a', '1.50'], ['b', 2]],
  label: { show: true, formatter: null },
}]));
label("funnel {c} of '-', null and a missing value", { series: [{
  type: 'funnel', name: 'F', label: { formatter: '{b}:{c}:{d}' },
  data: [{ name: 'a', value: 1 }, { name: 'd', value: '-' }, { name: 'e', value: null }, { name: 'f' }],
}] });
label('graph {c} of a node without a value', { series: [{
  type: 'graph', name: 'G', layout: 'none', label: { show: true, formatter: '[{c}]' },
  data: [{ name: 'n1', x: 0, y: 0, value: 1.5 }, { name: 'n2', x: 10, y: 10 }],
  links: [],
}] });
// {c} of an array value
label('scatter {c} of [x, y]', valueXY([
  { type: 'scatter', name: 'Sc', data: [[1234.5, 20.5], [3, 4, 5]], label: { show: true, formatter: '{c}' } },
]));
label('graph cartesian2d {c} of [x, y]', catX(['a', 'b'], [{
  type: 'graph', name: 'G', coordinateSystem: 'cartesian2d', data: [['a', 1.5], ['b', 0.1 + 0.2]],
  label: { show: true, formatter: '{c}' },
}]));
label('dataset row {c}', {
  dataset: { source: [['p', 'a', 'b'], ['x', 1234.5, 2], ['y', 0.1 + 0.2, 3]] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', label: { show: true, formatter: '{c}' } }],
});

// The raw zoo: every shape a JSON item comes in. The default text is the raw
// cell as written; {c} is String(raw) -- 'null' for {value: null},
// 'undefined' for a null item or one without a value; a scalar answers every
// {@...} with itself, a null or missing value with ''.
const ZOO = ['12.50', ' 5 ', '1e3', true, false, { value: '12.50' }, { value: true }, { value: null }, {}, null,
  '-', 'abc', 0, 1e21];
const zoo = formatter => catX(ZOO.map((_, i) => 'z' + i), [
  { type: 'bar', name: 'S', data: ZOO, label: formatter === undefined ? { show: true } : { show: true, formatter } },
]);
label('bar raw zoo: default labels', zoo());
label('bar raw zoo: {c}', zoo('{c}'));
label('bar raw zoo: [{@[0]}|{@y}|{@x}|{@nope}|{@[1]}]', zoo('[{@[0]}|{@y}|{@x}|{@nope}|{@[1]}]'));
// null and a missing value apart: {c} is 'null' against 'undefined', {@}
// prints '' for both, and a null item has no name either
label('funnel {b}:{c}:{@value} of a null item, {}, a null value and a raw string', { series: [{
  type: 'funnel', name: 'F', label: { formatter: '{b}:{c}:{@value}' },
  data: [{ name: 'a', value: 1 }, null, {}, { name: 'z', value: null }, { name: 's', value: '12.50' }],
}] });
const pieRaw = () => ({ series: [{
  type: 'pie', name: 'P', data: [{ name: 'a', value: '12.50' }, { name: 'b', value: true }], label: { formatter: '{c}' },
}] });
label("pie {c} of '12.50' and true", pieRaw());
// Original arrays: a declared name is the position it was encoded from;
// positions past the coord dims are value, value0, value1, ...; a series'
// dimensions replace the coord names; a null element joins as ''.
label('scatter encode {x: 1, y: 0}: {@x}|{@y}|{@[0]}|{@1}|{c}', valueXY([{
  type: 'scatter', name: 'Sc', encode: { x: 1, y: 0 }, data: [['1.50', 7, 'z'], [2, '3.25']],
  label: { show: true, formatter: '{@x}|{@y}|{@[0]}|{@1}|{c}' },
}]));
label('bar [cat, 1, 2, 3, 4]: {@value}|{@value0}|{@value1}|{@[3]}', catX(['A', 'B'], [{
  type: 'bar', name: 'S', data: [['A', 1, 2, 3, 4], ['B', 5, '6.50', 7]],
  label: { show: true, formatter: '{@value}|{@value0}|{@value1}|{@[3]}' },
}]));
label("scatter dimensions ['u', 'v', 'w']: {@u}|{@v}|{@w}|{@x}", valueXY([{
  type: 'scatter', name: 'Sc', dimensions: ['u', 'v', 'w'], data: [[1, '2.0', 'q'], [3, 4, 'r']],
  label: { show: true, formatter: '{@u}|{@v}|{@w}|{@x}' },
}]));
label('scatter {c} of [3, 4, null]', valueXY([
  { type: 'scatter', name: 'Sc', data: [[3, 4, null], [1, 2]], label: { show: true, formatter: '{c}' } },
]));
const lineWrapped = label => catX(['a', 'b'], [
  { type: 'line', name: 'L', data: [{ value: ['a', '1.50'] }, ['b', '2e0']], label },
]);
label("line {value: ['a', '1.50']}: {c}|{@y}", lineWrapped({ show: true, formatter: '{c}|{@y}' }));
label("line {value: ['a', '1.50']}: default labels", lineWrapped({ show: true }));
// {@...} corners: [n] is Number(n) ([] is 0, [ 1 ] is 1), a bad or out of
// range index is '', {@} is no placeholder at all; and the {@...} pass runs
// over the whole text, so a series or category name carrying one expands too.
// ({@[x]} has the development build warn 'Invalide label formatter'.)
const CORNERS = '{@[]}|{@[ 1 ]}|{@[x]}|{@[-1]}|{@[99]}|{@}';
label('scatter {@} corners on arrays', valueXY([{
  type: 'scatter', name: 'Sc', data: [[1.5, '2.50', 'q'], [3, 4]], label: { show: true, formatter: CORNERS },
}]));
label('bar {@} corners on scalars', catX(['A', 'B'], [{
  type: 'bar', name: 'S', data: ['12.50', 3], label: { show: true, formatter: CORNERS },
}]));
label('bar {a} of a series named N{@[0]}', catX(['A', 'B'], [{
  type: 'bar', name: 'N{@[0]}', data: ['12.50', 3], label: { show: true, formatter: '{a}' },
}]));
label('bar {b} of a category named c{@y}', catX(['c{@y}', 'd{@[0]}'], [{
  type: 'bar', name: 'S', data: ['12.50', 3], label: { show: true, formatter: '{b}' },
}]));
// Datasets: the dims are named by the header (none: x, y, value, ...); an
// ordinal or time cell prints as written, not as its index or epoch ms.
label('dataset with a header: {@p}|{@a}|{@x}|{@y}|{c}', {
  dataset: { source: [['p', 'a', 'b'], ['x', '12.50', 2], ['y', 3]] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [
    { type: 'bar', label: { show: true, formatter: '{@p}|{@a}|{@x}|{@y}|{c}' } },
    { type: 'bar', label: { show: true, formatter: '{@p}|{@b}|{c}' } },
  ],
});
label('dataset without a header: {@x}|{@y}|{@[1]}', {
  dataset: { source: [['x', 1, 2], ['y', '3.50', 4]] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', label: { show: true, formatter: '{@x}|{@y}|{@[1]}' } }],
});
const rowLayout = label => ({
  dataset: { source: [['p', 'x', 'y', 'z'], ['a', 1, '2.50', 3], ['b', 4, 5]] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', seriesLayoutBy: 'row', label }, { type: 'bar', seriesLayoutBy: 'row', label }],
});
label('dataset row layout, a short row: {c}', rowLayout({ show: true, formatter: '{c}' }));
const objectRows = label => ({
  dataset: { dimensions: ['p', 'a'], source: [{ p: 'x', a: '12.50', extra: 9 }, { p: 'y', a: true }] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', label }],
});
label('dataset objectRows: {c}|{@a}|{@[1]}|{@extra}', objectRows({ show: true, formatter: '{c}|{@a}|{@[1]}|{@extra}' }));
const keyedColumns = label => ({
  dataset: { dimensions: ['p', 'a'], source: { p: ['x', 'y'], a: ['12.50', 3] } },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', label }],
});
label('dataset keyedColumns: {c}', keyedColumns({ show: true, formatter: '{c}' }));
// The second series reads the table's THIRD column, which is its store's
// second: its default label and tooltip cell are that column's raw cell.
const secondColumn = label => ({
  dataset: { source: [['p', 'a', 'b'], ['x', '12.50', ' 7 '], ['y', 3, 'abc']] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', label }, { type: 'bar', label }],
});
label('dataset second series: default labels', secondColumn({ show: true }));
label('dataset ordinal and time dims: {@p}|{@t}', {
  dataset: {
    dimensions: ['p', { name: 't', type: 'time' }, 'a'], sourceHeader: false,
    source: [['x', '2020-01-02', '12.50'], ['y', 1577923200000, 3]],
  },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', encode: { x: 'p', y: 'a' }, label: { show: true, formatter: '{@p}|{@t}' } }],
});
// deferred: a raw string's number is Number(s) -- '   ' is 0 and drawn, '0x10'
// is 16
label("bar: '   ' and '0x10' are drawn", catX(['A', 'B', 'C'], [
  { type: 'bar', name: 'S', data: ['   ', '0x10', 5], label: { show: true } },
]), deferredFor('parse parity (D9)'));

// deferred: encode and the defaulted label dimension
const ENCODE = 'encode and the defaulted label dimension';
label('scatter encode.label [0, 1]', valueXY([
  { type: 'scatter', name: 'Sc', encode: { label: [0, 1] }, data: [[10, 20.5], [3, 4]], label: { show: true } },
]), deferredFor(ENCODE));
label('scatter category-category: no default label', {
  xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['u', 'v'] },
  series: [{ type: 'scatter', name: 'CC', data: [['a', 'u'], [1, 1]], label: { show: true } }],
}, deferredFor(ENCODE));
label('scatter time-category: no default label', {
  xAxis: { type: 'time' }, yAxis: { type: 'category', data: ['a', 'b'] },
  series: [{ type: 'scatter', name: 'TC', data: [['2020-01-01', 'a'], ['2020-01-02', 'b']], label: { show: true } }],
}, deferredFor(ENCODE));
// deferred: the unnamed series' auto name 'series\0' + index
const AUTONAME = "the unnamed series' auto name";
label('bar unnamed series: {a}', catX(['A'], [{ type: 'bar', data: [5], label: { show: true, formatter: '[{a}]' } }]),
  deferredFor(AUTONAME));

// ---------- tooltips ----------

// The tooltip's own ZRText, when it is shown.
function tooltipText(chart) {
  const model = chart.getModel().getComponent('tooltip', 0);
  const view = model && chart.getViewOfComponentModel(model);
  const content = view && view._tooltipContent;
  if (!content || !content._show || !content.el || content.el.ignore || content.el.invisible) return null;
  return content.el;
}

const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;

function markerKind(st) {
  if (st.width === 10) return 'item';
  if (st.width === 4) return 'subItem';
  throw new Error('a marker of width ' + JSON.stringify(st.width));
}

// One default-markup line: [marker] [name] [value], each at most once and in
// that order. The only text outside a segment is the two spaces a marker
// carries after itself ('{id|}  ', format.ts); anything else means the markup
// has a shape this reader does not know, and the case fails loudly.
function parseLine(line, rich, where) {
  const row = { marker: null, name: null, value: null };
  let last = 0;
  let stage = 0;
  let afterMarker = false;
  const gap = s => {
    if (s && !(afterMarker && !s.trim())) throw new Error(where + ': text outside a segment ' + JSON.stringify(s));
  };
  SEGMENT.lastIndex = 0;
  let m;
  while ((m = SEGMENT.exec(line))) {
    gap(line.slice(last, m.index));
    last = SEGMENT.lastIndex;
    const st = rich[m[1]];
    if (!st) throw new Error(where + ': no rich style ' + m[1]);
    let kind;
    if (st.width != null) kind = 0;
    else if (String(st.fontWeight) === '400') kind = 1;
    else if (String(st.fontWeight) === '900') kind = 2;
    else throw new Error(where + ': a segment styled ' + JSON.stringify(st));
    if (kind < stage) {
      throw new Error(where + ': segments out of order in ' + JSON.stringify(line));
    }
    stage = kind + 1;
    afterMarker = kind === 0;
    if (kind === 0) {
      if (m[2]) throw new Error(where + ': a marker with text ' + JSON.stringify(m[2]));
      row.marker = markerKind(st);
    } else if (kind === 1) {
      row.name = m[2];
    } else {
      row.value = m[2];
    }
  }
  gap(line.slice(last));
  return row;
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', '#39': "'" };
// One pass, so '&amp;lt;' comes out as '&lt;' and not '<'.
const decodeEntities = s => s.replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ENTITIES[e]);

function runTooltip(c, lib) {
  return withTooltips(lib, () => {
    const chart = init(lib);
    try {
      const option = clone(c.option);
      option.animation = false;
      option.tooltip = Object.assign({
        trigger: c.trigger, renderMode: 'richText', showDelay: 0, transitionDuration: 0,
      }, clone(c.tooltip || {}));
      const written = clone(option);
      chart.setOption(option);
      if (c.edge) {
        chart.renderToSVGString();
        const s = chart.getModel().getSeriesByIndex(c.edge.seriesIndex);
        const el = s.getEdgeData().getItemGraphicEl(c.edge.edgeIndex);
        const line = el.childOfName('line');
        const mid = line.pointAt(0.5);
        const at = line.transformCoordToGlobal(mid[0], mid[1]);
        let hovered = null;
        chart.on('mouseover', e => { hovered = e; });
        chart.getZr().handler.dispatch('mousemove', {
          zrX: at[0], zrY: at[1], offsetX: at[0], offsetY: at[1], target: null,
          preventDefault() {}, stopPropagation() {},
        });
        if (!hovered || hovered.dataType !== 'edge' || hovered.seriesIndex !== c.edge.seriesIndex
          || hovered.dataIndex !== c.edge.edgeIndex) {
          return { skipped: c.name + ': the midpoint hovers ' + JSON.stringify(hovered && {
            dataType: hovered.dataType, seriesIndex: hovered.seriesIndex, dataIndex: hovered.dataIndex }) };
        }
      } else if (c.trigger === 'item') {
        chart.dispatchAction({ type: 'showTip', seriesIndex: c.seriesIndex, dataIndex: c.dataIndex });
      } else {
        const x = chart.convertToPixel({ xAxisIndex: 0 }, c.category);
        const rect = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
        chart.dispatchAction({ type: 'showTip', x, y: rect.y + rect.height / 2 });
      }
      const el = tooltipText(chart);
      if (!el) return { skipped: c.name + ': no tooltip is shown' };
      const text = String(el.style.text);
      const template = typeof option.tooltip.formatter === 'string';
      const lines = text.split('\n').map(line => (template
        ? { marker: null, name: null, value: null }
        : parseLine(line, el.style.rich || {}, c.name)));
      const plain = text.replace(SEGMENT, '$2');
      const record = withDeferred({ name: c.name, option: written }, c);
      record.trigger = c.trigger;
      if (c.edge) {
        record.edge = { seriesIndex: c.edge.seriesIndex, edgeIndex: c.edge.edgeIndex };
      } else if (c.trigger === 'item') {
        record.seriesIndex = c.seriesIndex;
        record.dataIndex = c.dataIndex;
      } else {
        record.category = c.category;
      }
      record.lines = lines;
      record.text = text;
      record.visible = template ? decodeEntities(plain) : plain;
      return record;
    } finally {
      chart.dispose();
    }
  });
}

const tooltips = [];
const itemTip = (name, option, seriesIndex, dataIndex, tooltip, extra) =>
  tooltips.push(Object.assign({ name, option, trigger: 'item', seriesIndex, dataIndex, tooltip }, extra || {}));
const axisTip = (name, option, category, tooltip, extra) =>
  tooltips.push(Object.assign({ name, option, trigger: 'axis', category, tooltip }, extra || {}));
const edgeTip = (name, option, edgeIndex, tooltip, extra) =>
  tooltips.push(Object.assign({ name, option, trigger: 'item', edge: { seriesIndex: 0, edgeIndex }, tooltip }, extra || {}));

// bar on V. An item tooltip on a missing value never shows: showTip finds no
// point for it (the run reports those as skipped). The axis tooltip keeps the
// row and prints '-'.
const barV = () => catX(VC, [{ type: 'bar', name: 'S', data: V }]);
V.forEach((v, i) => itemTip('bar item ' + VC[i] + ' ' + JSON.stringify(v), barV(), 0, i));
V.forEach((v, i) => axisTip('bar axis ' + VC[i] + ' ' + JSON.stringify(v), barV(), VC[i]));
itemTip('bar item, unnamed series: no header', catX(['A'], [{ type: 'bar', data: [5] }]), 0, 0);
itemTip('bar item, series name 2015', catX(['A'], [{ type: 'bar', name: 2015, data: [5] }]), 0, 0);
itemTip("bar item, series name ' ': header '-'", catX(['A'], [{ type: 'bar', name: ' ', data: [5] }]), 0, 0);
axisTip('line axis, two series, one null', catX(['A', 'B'], [
  { type: 'line', name: 'L1', data: [1, 2.5] },
  { type: 'line', name: 'L2', data: [3, null] },
]), 'B');
// scatter: the row is y alone
const sc = () => valueXY([{ type: 'scatter', name: 'Sc', data: [[1234.5, 20.5], [3, 4, 5]] }]);
itemTip('scatter item [1234.5,20.5]', sc(), 0, 0);
itemTip('scatter item [3,4,5]', sc(), 0, 1);
// pie and funnel: name and value, no percent
const pie = () => ({ series: [{ type: 'pie', name: 'P', data: named(['x', 'y', ''], [1234.5, 1 / 3, 3]) }] });
[0, 1, 2].forEach(i => itemTip('pie item ' + i, pie(), 0, i));
itemTip('pie template {a}|{b}|{c}|{d}', pie(), 0, 0, { formatter: '{a}|{b}|{c}|{d}' });
// the share of the slice hovered, not of the one at its raw position
itemTip('pie template with the middle slice off', {
  legend: { selected: { n1: false } },
  series: [{ type: 'pie', name: 'P', data: nNames([1, 2, 3]) }],
}, 0, 2, { formatter: '{b}|{d}' });
const funnel = () => ({ series: [{ type: 'funnel', name: 'F', data: named(['x', 'y', 'd'], [60, 40.123, '-']) }] });
[0, 1, 2].forEach(i => itemTip('funnel item ' + i, funnel(), 0, i));
itemTip('funnel template {a}|{b}|{c}|{d}', funnel(), 0, 1, { formatter: '{a}|{b}|{c}|{d}' });
// graph: nodes, and edges hovered for real
const graph = () => ({ series: [{
  type: 'graph', name: 'G', layout: 'none',
  data: [{ name: 'n1', x: 0, y: 0, value: 1234.5 }, { name: 'n2', x: 100, y: 100 }, { name: 'n3', x: 100, y: 0 }],
  links: [{ source: 'n1', target: 'n2', value: 9876.5 }, { source: 'n2', target: 'n3' }],
}] });
itemTip('graph node with a value', graph(), 0, 0);
itemTip("graph node without a value: '-'", graph(), 0, 1);
edgeTip('graph edge with a value', graph(), 0);
edgeTip('graph edge without a value: no value cell', graph(), 1);
edgeTip('graph edge template {a}|{b}|{c}', graph(), 0, { formatter: '{a}|{b}|{c}' });
edgeTip('graph edge template {b}', graph(), 1, { formatter: '{b}' });
// templates
itemTip('bar item template', catX(['A'], [{ type: 'bar', name: 'S', data: [1234.5] }]), 0, 0,
  { formatter: '{a}|{b}|{c}|{c1}|{d}|{e}|{a0}|{@[0]}' });
itemTip('bar item template {c} of 0.1+0.2', catX(['A'], [{ type: 'bar', name: 'S', data: [0.1 + 0.2] }]), 0, 0,
  { formatter: '{c}' });
const three = unnamed => catX(['A', 'B'], [
  { type: 'bar', name: 'S1', data: [1, 2] },
  { type: 'line', name: 'S2', data: [3, null] },
  unnamed ? { type: 'line', data: [5, 6] } : { type: 'line', name: 'S3', data: [5, 6] },
]);
const threeTpl = '{a}|{b}|{c}|{a0}|{c0}|{a1}|{c1}|{a2}|{c2}|{c3}|{d}|{@[0]}|{c}';
axisTip('axis template over three series', three(false), 'B', { formatter: threeTpl });
// The one case with '&', '<' and quotes in names: formatTpl encodes them.
itemTip("item template on names with '&', '<' and quotes", catX(['x&y'], [
  { type: 'bar', name: 'a&b<c>"\'', data: [1] },
]), 0, 0, { formatter: '{a}|{b}' });

// The raw value as written: the cell is the raw reparsed (numericToNumber)
// and given commas, or the text itself when that is not a number. Items 0-2
// and axis A-C pin the reparse ('12.50' -> 12.5, '1e3' -> 1,000). Item 4
// ('abc') is never shown: no bar.
const barRaw = () => catX(['A', 'B', 'C', 'D', 'E'], [{ type: 'bar', name: 'S', data: ['12.50', ' 5 ', '1e3', true, 'abc'] }]);
const AGREE = 'the raw value as written (the reparse already agrees)';
[0, 1, 2, 3, 4].forEach(i => itemTip('bar item raw ' + i, barRaw(), 0, i, null, i === 4 ? deferredFor(AGREE) : undefined));
['A', 'B', 'C', 'D', 'E'].forEach(k => axisTip('bar axis raw ' + k, barRaw(), k, null));
// {c} of an array value
itemTip('scatter template {c} of [x, y]', sc(), 0, 0, { formatter: '{c}' });
const candle = () => catX(['d0', 'd1'], [{ type: 'candlestick', name: 'K', data: [[20, 34, 10, 38], [4000.5, 1234.25, 1000, 5000]] }]);
itemTip('candlestick template {c}', candle(), 0, 0, { formatter: '{c}' });
const dataset = () => ({
  dataset: { source: [['p', 'a', 'b'], ['x', 1234.5, 2], ['y', 0.1 + 0.2, 3]] },
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'bar' }, { type: 'bar' }],
});
itemTip('dataset row template {c}', dataset(), 0, 0, { formatter: '{c}' });
itemTip('dataset second series: default cell of item 0', secondColumn(), 1, 0);
itemTip('dataset second series: default cell of item 1', secondColumn(), 1, 1);
// One category, one bar series per raw: the axis tooltip keeps a row for
// every series, '-' where the cell is no number and no text; a template's {cN}
// is String(raw), '' for null.
const TIPRAW = ['12.50', ' 5 ', '1e3', true, false, '-', 'abc', '', 'Infinity', '0x10', null, { value: null }];
const tipRaw = () => catX(['A'], TIPRAW.map((v, i) => ({ type: 'bar', name: 'S' + i, data: [v] })));
axisTip('axis over one bar per raw: default cells', tipRaw(), 'A');
axisTip('axis over one bar per raw: template {c0}..{c11}', tipRaw(), 'A',
  { formatter: TIPRAW.map((_, i) => '{c' + i + '}').join('|') });
// an item template's {c}: an object row is [object Object], a column or row
// layout the whole array, and what it prints is entity-encoded
itemTip('objectRows item template {c}', objectRows(), 0, 0, { formatter: '{c}' });
itemTip('keyedColumns item template {c}', keyedColumns(), 0, 0, { formatter: '{c}' });
itemTip('row layout item template {c}', rowLayout(), 1, 1, { formatter: '{c}' });
itemTip("item template {c} of [cat, 5, 'a&<b']", catX(['A'], [
  { type: 'bar', name: 'S', data: [['A', 5, 'a&<b']] },
]), 0, 0, { formatter: '{c}' });
// the default cells of a raw string and of a pie's raw values
itemTip("pie item '12.50'", pieRaw(), 0, 0);
itemTip('pie item true', pieRaw(), 0, 1);
// deferred: '   ' is Number('   ') = 0, a bar with a tooltip
itemTip("bar item '   '", catX(['A', 'B', 'C'], [{ type: 'bar', name: 'S', data: ['   ', '0x10', 5] }]), 0, 0, null,
  deferredFor('parse parity (D9)'));
// deferred: sub-row tooltips
const SUBROWS = 'sub-row tooltips';
itemTip('candlestick item: open/close/lowest/highest rows', candle(), 0, 1, null, deferredFor(SUBROWS));
axisTip('candlestick axis: open/close/lowest/highest rows', candle(), 'd1', null, deferredFor(SUBROWS));
const radar = () => ({
  radar: { indicator: [{ name: 'A', max: 20000 }, { name: 'B', max: 10 }, { name: 'C', max: 10 }] },
  series: [{ type: 'radar', name: 'R', data: [{ name: 'r', value: [12345.5, 0.1 + 0.2, '-'] }, { value: [1, 2, 3] }] }],
});
itemTip('radar item: one row per indicator', radar(), 0, 0, null, deferredFor(SUBROWS));
itemTip('radar item unnamed: the series name heads it', radar(), 0, 1, null, deferredFor(SUBROWS));
// deferred: encode.tooltip and displayName
itemTip('scatter encode.tooltip [1, 0]', valueXY([
  { type: 'scatter', name: 'E', encode: { tooltip: [1, 0] }, data: [[10, 20]] },
]), 0, 0, null, deferredFor('encode.tooltip and displayName'));
itemTip('scatter displayName rows', valueXY([{
  type: 'scatter', name: 'E', encode: { tooltip: [0, 1] },
  dimensions: [{ name: 'x', displayName: 'XX' }, { name: 'y', displayName: 'YY' }], data: [[10, 20]],
}]), 0, 0, null, deferredFor('encode.tooltip and displayName'));
// deferred: the defaulted value of a category-category series
itemTip('scatter category-category item', {
  xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['u', 'v'] },
  series: [{ type: 'scatter', name: 'CC', data: [['a', 'u'], [1, 1]] }],
}, 0, 0, null, deferredFor('the defaulted value of a category-category series'));
// deferred: the unnamed series' auto name
axisTip('axis template over three series, the third unnamed', three(true), 'B', { formatter: threeTpl }, deferredFor(AUTONAME));

// ---------- gauge ----------

function gaugeText(el, what) {
  if (!el || !el.parent || !labelShown(el, el.parent)) throw new Error('the ' + what + ' is not shown');
  return paintedText(el.style.text);
}

function runGauge(c, lib) {
  const chart = init(lib);
  try {
    const option = clone(c.option);
    option.animation = false;
    const written = clone(option);
    chart.setOption(option);
    const s = chart.getModel().getSeriesByIndex(0);
    const view = chart.getViewOfSeriesModel(s);
    const titles = [];
    const details = [];
    s.getData().each(i => {
      titles.push(gaugeText(view._titleEls[i], c.name + ' title ' + i));
      details.push(gaugeText(view._detailEls[i], c.name + ' detail ' + i));
    });
    const axisLabels = [];
    view.group.eachChild(ch => {
      if (ch.type !== 'text') return;
      if (!ch.silent) throw new Error(c.name + ': a Text on the gauge group that is not silent');
      if (labelShown(ch, view.group)) axisLabels.push(paintedText(ch.style.text));
    });
    return Object.assign(withDeferred({ name: c.name, option: written }, c), { titles, details, axisLabels });
  } finally {
    chart.dispose();
  }
}

const gauges = [];
const gauge = (name, series, extra) =>
  gauges.push(Object.assign({ name, option: { series: [Object.assign({ type: 'gauge', name: 'Ga' }, series)] } }, extra || {}));

gauge('detail 0.123456789', { data: [{ name: 't', value: 0.123456789 }] });
gauge('detail 1e21', { data: [{ name: 't', value: 1e21 }] });
gauge("detail '-' is NaN", { data: [{ name: 't', value: '-' }] });
gauge('detail 1234.5 has no commas', { data: [{ name: 't', value: 1234.5 }] });
gauge('detail template, first {value} only', { detail: { formatter: '{value} km/h {value}' }, data: [{ name: 'speed', value: 12.5 }] });
gauge("detail template on '-'", { detail: { formatter: '{value} km/h {value}' }, data: [{ name: 'speed', value: '-' }] });
gauge('detail formatter on the item over the series', {
  detail: { formatter: 'S {value}' }, data: [{ name: 'a', value: 5, detail: { formatter: 'item {value}' } }],
});
gauge('titles: named and unnamed items', { data: [{ name: 'speed', value: 50 }, { value: 20 }] });
for (const [min, max, splitNumber] of [[0, 1, 3], [-0.3, 0.3, 6], [0, 0.3, 3], [0, 1e22, 2], [0, 100, 10]]) {
  gauge('axis ' + min + '..' + max + ' in ' + splitNumber, { min, max, splitNumber, data: [{ name: 't', value: min }] });
}
gauge('axis template {value}%', { axisLabel: { formatter: '{value}%' }, data: [{ name: 't', value: 5 }] });
// A documented deviation: upstream divides by zero and prints 'NaN'; the port
// draws the min on purpose.
gauge('axis splitNumber 0', { splitNumber: 0, data: [{ name: 't', value: 5 }] },
  deferredFor('a documented deviation: the port draws the min'));

// ---------- run and write ----------

function runEither(run, c) {
  try {
    return run(c, echarts);
  } catch (e) {
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

const skipped = [];
function runAll(run, list) {
  const out = [];
  for (const c of list) {
    const r = runEither(run, c);
    if (r.skipped) skipped.push(r.skipped);
    else out.push(r);
  }
  return out;
}

const out = {
  source: 'ECharts ' + echarts.version,
  labels: runAll(runLabels, labels),
  tooltips: runAll(runTooltip, tooltips),
  gauge: runAll(runGauge, gauges),
};

// ---------- spot checks ----------

// What separate probes of the same build printed (wf49 probes a1, a2, P1-P7):
// a label case as its items' texts ('/' between labels, '#' for an item not
// drawn), per series; a tooltip as its visible text or its value cells.
const itemTexts = r => r.series.map(s => s.items.map(i => (i.drawn ? i.texts.join('/') : '#')));
const cells = r => r.lines.slice(1).map(l => l.value);
const SPOT = [
  ['labels', 'bar raw zoo: default labels', itemTexts, [['12.50', ' 5 ', '1e3', 'true', 'false', '12.50', 'true',
    '#', '#', '#', '#', '#', '0', '1e+21']]],
  ['labels', 'bar raw zoo: [{@[0]}|{@y}|{@x}|{@nope}|{@[1]}]', r => itemTexts(r)[0][1], '[ 5 | 5 | 5 | 5 | 5 ]'],
  ['labels', 'funnel {b}:{c}:{@value} of a null item, {}, a null value and a raw string', itemTexts,
    [['a:1:1', ':undefined:', ':undefined:', 'z:null:', 's:12.50:12.50']]],
  ['labels', "pie {c} of '12.50' and true", itemTexts, [['12.50', 'true']]],
  ['labels', 'scatter encode {x: 1, y: 0}: {@x}|{@y}|{@[0]}|{@1}|{c}', r => itemTexts(r)[0][0], '7|1.50|1.50|7|1.50,7,z'],
  ['labels', 'bar [cat, 1, 2, 3, 4]: {@value}|{@value0}|{@value1}|{@[3]}', r => itemTexts(r)[0][0], '2|3|4|3'],
  ['labels', "scatter dimensions ['u', 'v', 'w']: {@u}|{@v}|{@w}|{@x}", r => itemTexts(r)[0][0], '1|2.0|q|'],
  ['labels', "line {value: ['a', '1.50']}: {c}|{@y}", itemTexts, [['a,1.50|1.50', 'b,2e0|2e0']]],
  ['labels', "line {value: ['a', '1.50']}: default labels", itemTexts, [['1.50', '2e0']]],
  ['labels', 'dataset with a header: {@p}|{@a}|{@x}|{@y}|{c}', r => itemTexts(r)[0][0], 'x|12.50|||x,12.50,2'],
  ['labels', 'dataset objectRows: {c}|{@a}|{@[1]}|{@extra}', itemTexts,
    [['[object Object]|12.50|12.50|', '[object Object]|true|true|']]],
  ['labels', 'dataset keyedColumns: {c}', itemTexts, [['x,12.50', 'y,3']]],
  ['tooltips', "pie item '12.50'", cells, ['12.5']],
  ['tooltips', 'pie item true', cells, ['true']],
  ['tooltips', 'axis over one bar per raw: default cells', cells,
    ['12.5', '5', '1,000', 'true', 'false', '-', 'abc', '-', 'Infinity', '0x10', '-', '-']],
  ['tooltips', 'axis over one bar per raw: template {c0}..{c11}', r => r.visible,
    '12.50| 5 |1e3|true|false|-|abc||Infinity|0x10||'],
  ['tooltips', 'objectRows item template {c}', r => r.visible, '[object Object]'],
  ['tooltips', 'keyedColumns item template {c}', r => r.visible, 'x,12.50'],
];
const spotFails = [];
for (const [section, name, read, want] of SPOT) {
  const r = out[section].find(c => c.name === name);
  const got = r ? JSON.stringify(read(r)) : 'no such case';
  if (got !== JSON.stringify(want)) spotFails.push(name + ': ' + got + ', the probes printed ' + JSON.stringify(want));
}
if (spotFails.length) {
  spotFails.forEach(f => console.log('spot check failed: ' + f));
  console.log('FAILED: ' + spotFails.length + ' spot check(s); the fixture is not written');
  process.exit(1);
}
console.log('spot checks: ' + SPOT.length + '/' + SPOT.length);

// A number JSON.stringify would write as an integer literal past 2^63 goes
// out in exponent form instead: marked in the replacer, unquoted afterwards.
const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

for (const s of ['labels', 'tooltips', 'gauge']) {
  const prod = out[s].filter(c => c.productionBuild).map(c => c.name);
  if (prod.length) console.log(s + ' through the production build:', prod.join(', '));
}
for (const s of skipped) console.log('skipped', s);
fs.writeFileSync(OUT, json + '\n');
console.log('wrote', OUT, ['labels', 'tooltips', 'gauge'].map(k => {
  const d = out[k].filter(c => c.deferred).length;
  return k + ' ' + (out[k].length - d) + ' + ' + d + ' deferred';
}).join(', '));
process.exit(0);
