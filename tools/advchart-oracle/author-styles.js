/*
Upstream's own answers for THE AUTHOR'S STYLES ON THE FURNITURE -- round 5,
batch R5-B: what an axis' line, ticks, minor ticks, split lines, minor split
lines, split areas, arrows and name are stroked and filled with when the
option writes `axisLine.lineStyle`, `axisTick.lineStyle`, `minorTick`,
`splitLine.lineStyle`, `minorSplitLine.lineStyle` or `splitArea.areaStyle`
(width, type, dashOffset, cap, opacity as well as the colour), on every kind
of axis there is: cartesian, single, polar (angle and radius), parallel and
radar.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, `animation: false`,
measuring every string with zrender's SSR width table. Every case is
600 x 400 unless it says otherwise.

  node tools/advchart-oracle/author-styles.js

writes tests/fixtures/advchart-author-styles.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Top level: source, version, notes[], cases[], guards[].

A case: id, group ('axis'), note, W, H, option (as run, animation false),
  fails[] (empty), axes[].

An axis record: kind ('cartesian' | 'single' | 'angle' | 'radius' |
  'parallel' | 'radar'), mainType, index (componentIndex), parts{}: one entry
  per part the view drew -- line, tick, minorTick, split, minorSplit, area,
  arrow, name -- each
    { styles[]: one per distinct style the part's elements carry (a split
      line or area has one per colour of its list), each the element style's
      stroke, fill, lineWidth, lineDash (as written: a word, a list or null),
      lineDashOffset, lineCap, opacity (the arrow's and the name's: fill and
      opacity only),
      src: per key, 'author' when the option wrote the value somewhere along
      upstream's chain for that key, else 'theme' (the port's skin stands in
      for the theme there and the replay compares those with the skin) }

Guards: every part's style is the transcription of its view's recipe
(AxisBuilder's axisLine / ticks / minor ticks and name fill, the cartesian /
single / angle / radius / radar split builders), and each one is matched by
at least one element of the view with exactly that style; every path element
of the view is one of the recipes'. Named facts below. Two in-process runs
must write the same bytes.
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-author-styles.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const clone = o => JSON.parse(JSON.stringify(o));

function walk(e, f) {
  f(e);
  if (e.childrenRef) e.childrenRef().forEach(x => walk(x, f));
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const C5 = ['a', 'b', 'c', 'd', 'e'];
const catBar = (x, y, extra) => Object.assign({
  xAxis: Object.assign({ type: 'category', data: C5 }, x || {}),
  yAxis: Object.assign({ type: 'value' }, y || {}),
  series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }, extra || {});
const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400, option }, more || {}));

// ---- cartesian
add('axis', 'cart-line-colour', "axisLine.lineStyle.color on a category x axis with ticks and a name: the ticks, the arrows and the name follow it",
  catBar({ name: 'Cat', boundaryGap: false, axisLine: { symbol: ['none', 'arrow'], lineStyle: { color: '#c23531' } } }));
add('axis', 'cart-line-full', 'axisLine.lineStyle width 3, dashed, opacity 0.5, cap butt, dashOffset 2 on a value y axis shown',
  catBar(null, { name: 'Val', axisLine: { show: true, symbol: 'arrow', lineStyle: { color: '#2f4554', width: 3, type: 'dashed', opacity: 0.5, cap: 'butt', dashOffset: 2 } },
    axisTick: { show: true } }));
add('axis', 'cart-tick-own', "axisTick.lineStyle's own colour, width, [3, 2] and opacity over the line's colour",
  catBar({ boundaryGap: false, axisLine: { lineStyle: { color: '#c23531' } },
    axisTick: { lineStyle: { color: '#0000ff', width: 2, type: [3, 2], opacity: 0.6 } } }));
add('axis', 'cart-minor-own', "minorTick.lineStyle written; the y axis' line shown in its own colour",
  catBar(null, { axisLine: { show: true, lineStyle: { color: '#61a0a8' } }, axisTick: { show: true, lineStyle: { width: 2 } },
    minorTick: { show: true, lineStyle: { color: '#00aa00', width: 2, type: 'dotted' } } }));
add('axis', 'cart-minor-follows-line', "minorTick with no lineStyle: the line's colour, not axisTick.lineStyle's (getLineStyle on the axisTick model reads its own keys)",
  catBar(null, { axisLine: { show: true, lineStyle: { color: '#d48265' } }, axisTick: { show: true, lineStyle: { color: '#0000ff', width: 3 } },
    minorTick: { show: true } }));
add('axis', 'cart-minor-tick-keys', 'axisTick.color / width written on the axisTick itself: the minor ticks read them',
  catBar(null, { axisLine: { show: true }, axisTick: { show: true, color: '#ff00ff', width: 2 }, minorTick: { show: true } }));
add('axis', 'cart-split-full', 'splitLine width 2, dashed, opacity 0.5 and a list of two colours',
  catBar(null, { splitLine: { lineStyle: { color: ['#aaaaaa', '#cccccc'], width: 2, type: 'dashed', opacity: 0.5 } } }));
add('axis', 'cart-split-type-only', "splitLine type 'dotted' and width 2 alone: the skin's colour",
  catBar(null, { splitLine: { lineStyle: { type: 'dotted', width: 2 } } }));
add('axis', 'cart-split-numbers', 'splitLine type [5, 10], dashOffset 3, cap round',
  catBar(null, { splitLine: { lineStyle: { type: [5, 10], dashOffset: 3, cap: 'round' } } }));
add('axis', 'cart-split-width-0', 'splitLine width 0: the lines are built and stroke nothing (hasStroke)',
  catBar(null, { splitLine: { lineStyle: { width: 0 } } }));
add('axis', 'cart-minor-split', 'minorSplitLine shown with its own colour, width, dotted and opacity',
  catBar(null, { minorTick: { show: true }, minorSplitLine: { show: true, lineStyle: { color: '#eeeeee', width: 2, type: 'dotted', opacity: 0.8 } } }));
add('axis', 'cart-area-opacity', 'splitArea areaStyle colours and opacity 0.5',
  catBar(null, { splitArea: { show: true, areaStyle: { color: ['rgba(250,250,250,0.3)', 'rgba(200,200,200,0.3)'], opacity: 0.5 } } }));
add('axis', 'cart-area-opacity-only', "splitArea areaStyle opacity alone: the theme's colours at that opacity",
  catBar({ splitArea: { show: true, areaStyle: { opacity: 0.5 } } }));
add('axis', 'cart-name-own', "nameTextStyle.color over the line's colour",
  catBar({ name: 'Cat', axisLine: { lineStyle: { color: '#c23531' } }, nameTextStyle: { color: '#00ff00' } }));
add('axis', 'cart-name-root-text', "a root textStyle colour and the line's colour: which one the name takes",
  catBar({ name: 'Cat', axisLine: { lineStyle: { color: '#c23531' } } }, null, { textStyle: { color: '#123456' } }));
add('axis', 'cart-dark', 'the candlestick-sh-2015 look: both axes in #8392A5, no split lines, y line shown',
  catBar({ axisLine: { lineStyle: { color: '#8392A5' } } },
    { scale: true, axisLine: { show: true, lineStyle: { color: '#8392A5' } }, splitLine: { show: false } }));
add('axis', 'cart-line-gradient-free', "axisLine.lineStyle.color 'rgba(0,0,0,0.3)' with width 2: an alpha colour on the line, its arrows and ticks",
  catBar({ boundaryGap: false, axisLine: { symbol: 'arrow', lineStyle: { color: 'rgba(0,0,0,0.3)', width: 2 } } }));

// ---- single
add('axis', 'single-full', 'a single axis: line, tick, split line, split area and name in the author styles',
  { singleAxis: { type: 'value', name: 'S', top: 50, height: 100, axisLine: { lineStyle: { color: '#c23531', width: 2, type: 'dashed' } },
    axisTick: { lineStyle: { width: 2, opacity: 0.5 } }, splitLine: { lineStyle: { width: 2, type: 'dotted', opacity: 0.6 } },
    splitArea: { show: true, areaStyle: { opacity: 0.4 } } },
  series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 3, 7] }] });

// ---- polar
add('axis', 'polar-full', 'angle and radius axes: line, tick, minor tick, split line, minor split line and area in the author styles',
  { polar: {}, angleAxis: { type: 'value', axisLine: { lineStyle: { color: '#c23531', width: 2, type: 'dashed', opacity: 0.7 } },
    axisTick: { lineStyle: { width: 2 } }, minorTick: { show: true }, splitLine: { lineStyle: { type: 'dotted', width: 2 } },
    minorSplitLine: { show: true, lineStyle: { color: '#dddddd', type: 'dashed' } }, splitArea: { show: true, areaStyle: { opacity: 0.5 } } },
  radiusAxis: { type: 'value', name: 'R', axisLine: { symbol: 'arrow', lineStyle: { color: '#2f4554', width: 3 } }, axisTick: { lineStyle: { color: '#0000ff' } },
    minorTick: { show: true, lineStyle: { width: 2 } }, splitLine: { lineStyle: { color: ['#aaaaaa', '#bbbbbb'], opacity: 0.5 } },
    splitArea: { show: true, areaStyle: { color: ['#eeeeee', '#f6f6f6'], opacity: 0.6 } } },
  series: [{ type: 'line', coordinateSystem: 'polar', data: [[1, 30], [3, 120], [5, 250]] }] });

// ---- parallel
add('axis', 'parallel-full', "parallelAxisDefault's axisLine colour and width, an axis' own tick style and name colour",
  { parallel: { parallelAxisDefault: { axisLine: { lineStyle: { color: '#c23531', width: 2 } }, axisTick: { lineStyle: { width: 2 } } } },
    parallelAxis: [{ dim: 0, name: 'A' }, { dim: 1, name: 'B', axisLine: { lineStyle: { type: 'dashed', opacity: 0.5 } }, axisTick: { lineStyle: { color: '#0000ff' } },
      nameTextStyle: { color: '#00aa00' } }],
    series: [{ type: 'parallel', data: [[1, 2], [3, 4]] }] });

// ---- radar
add('axis', 'radar-full', 'a radar: line, ticks, split line and split area in the author styles',
  { radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }],
    axisLine: { lineStyle: { color: '#c23531', width: 2, type: 'dashed', opacity: 0.7 } },
    axisTick: { show: true, lineStyle: { width: 2 } },
    splitLine: { lineStyle: { color: ['#aaaaaa', '#bbbbbb'], width: 2, type: 'dotted', opacity: 0.5 } },
    splitArea: { areaStyle: { opacity: 0.5 } } },
  series: [{ type: 'radar', data: [{ value: [3, 5, 7] }] }] });

// ---- a bar's background strip (BarView: backgroundModel.getItemStyle())
const barBg = (bs, more, extra) => Object.assign({
  xAxis: { type: 'category', data: C5 }, yAxis: { type: 'value', max: 10 },
  series: [Object.assign({ type: 'bar', data: [5, 3, 8, 2, 6], showBackground: true }, bs === undefined ? {} : { backgroundStyle: bs }, more || {})] },
  extra || {});
add('barbg', 'bg-default', "showBackground with no backgroundStyle: the theme's strip", barBg());
add('barbg', 'bg-colour', "backgroundStyle.color", barBg({ color: 'rgba(220, 30, 30, 0.3)' }));
add('barbg', 'bg-border', 'a border colour, width, dashed type and phase; an opacity', barBg({ color: '#eeeeee', borderColor: '#333333', borderWidth: 2,
  borderType: 'dashed', borderDashOffset: 1, opacity: 0.6 }));
add('barbg', 'bg-border-no-width', 'a border colour with no width: no pen (the default borderWidth 0)', barBg({ borderColor: '#333333' }));
add('barbg', 'bg-radius', 'borderRadius [6, 6, 0, 0] with a colour', barBg({ color: '#dddddd', borderRadius: [6, 6, 0, 0] }));
add('barbg', 'bg-gradient', 'a linear gradient colour', barBg({ color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
  colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } }));
add('barbg', 'bg-none', "color 'none': no fill", barBg({ color: 'none', borderColor: '#333333', borderWidth: 1 }));
add('barbg', 'bg-polar', 'a bar on a polar, its background sector in the author style', {
  polar: {}, angleAxis: { type: 'category', data: C5 }, radiusAxis: { type: 'value', max: 10 },
  series: [{ type: 'bar', coordinateSystem: 'polar', data: [5, 3, 8, 2, 6], showBackground: true,
    backgroundStyle: { color: '#eeddcc', borderColor: '#333333', borderWidth: 1, opacity: 0.8 } }] });

// ---- colorBy 'data' (dataColorPaletteTask): each row its palette colour on
// the colour the type draws with, a row with its own colour keeping it. (A
// heatmap is not here: the development build throws 'Heatmap must use with
// visualMap', and with one the visual colours every cell.)
const PAL = ['#aa0000', '#00aa00', '#0000aa', '#aaaa00', '#00aaaa', '#aa00aa', '#555555'];
add('colorby', 'cb-lines', "lines, colorBy 'data': each line's stroke; one its own lineStyle colour", {
  color: PAL, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [{ type: 'lines', coordinateSystem: 'cartesian2d', colorBy: 'data', data: [
    { coords: [[1, 1], [9, 1]] }, { coords: [[1, 3], [9, 3]], lineStyle: { color: '#123456' } },
    { coords: [[1, 5], [9, 5]] }, { coords: [[1, 7], [9, 7]] }] }] });
add('colorby', 'cb-parallel', "a parallel series, colorBy 'data': each line's stroke; one its own", {
  color: PAL, parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
  series: [{ type: 'parallel', colorBy: 'data', data: [[1, 2, 3], { value: [2, 3, 1], lineStyle: { color: '#123456' } },
    [3, 1, 2], [2, 2, 2]] }] });

// ---- a palette entry that is a gradient: the object itself is the fill
// (the series' and, under colorBy 'data', the datum's), not its first stop
const GRAD = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };
add('palgrad', 'pg-series', "a root palette [gradient, '#00aa00']: a bar series takes the gradient, a pie by data every other slice", {
  color: [GRAD, '#00aa00'], xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' },
  series: [{ type: 'bar', name: 'B', data: [1, 2] }, { type: 'pie', colorBy: 'data', center: ['80%', '30%'], radius: 30,
    data: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }, { name: 'z', value: 3 }] }] });
add('palgrad', 'pg-line', 'a line series on a gradient palette: its stroke and its area', {
  color: [GRAD], xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: [1, 3, 2], areaStyle: {}, showSymbol: false }] });

// ---- a legend item's own style (legend.data[i]: a model whose parent is
// the legend model), and the selector's whole emphasis label
const LG_SERIES = [{ type: 'bar', name: 'A', data: [1, 2] }, { type: 'bar', name: 'B', data: [2, 1] },
  { type: 'bar', name: 'C', data: [1, 1] }, { type: 'line', name: 'L', data: [2, 2] }];
add('legend', 'lg-items', "legend.data[i]'s textStyle, itemStyle, lineStyle and inactive colours over the legend's", {
  xAxis: { type: 'category', data: ['p', 'q'] }, yAxis: { type: 'value' }, series: LG_SERIES,
  legend: { top: 10, selected: { C: false }, itemStyle: { borderColor: '#333333', borderWidth: 1 },
    data: [{ name: 'A', textStyle: { color: '#ff0000', fontSize: 16, fontWeight: 'bold' }, itemStyle: { color: '#00ff00', opacity: 0.5 } },
      { name: 'B', itemStyle: { borderColor: '#0000ff', borderWidth: 3 } },
      { name: 'C', inactiveColor: '#aaaaaa', inactiveBorderColor: '#888888', textStyle: { color: '#ff0000' } },
      { name: 'L', lineStyle: { color: '#ff00ff', width: 4 } }] } });
add('legend', 'lg-item-inactive-line', "an unselected line item's own lineStyle.inactiveColor / inactiveWidth", {
  xAxis: { type: 'category', data: ['p', 'q'] }, yAxis: { type: 'value' }, series: LG_SERIES,
  legend: { top: 10, selected: { L: false }, data: ['A', { name: 'L', lineStyle: { inactiveColor: '#00ffff', inactiveWidth: 5 } }] } });
add('legend', 'lg-selector-emph', "emphasis.selectorLabel's font and box as well as its colour", {
  xAxis: { type: 'category', data: ['p', 'q'] }, yAxis: { type: 'value' }, series: LG_SERIES.slice(0, 2),
  legend: { top: 10, selector: ['all'], emphasis: { selectorLabel: { color: '#ff0000', fontWeight: 'bold', fontSize: 14,
    backgroundColor: '#eeeeee', borderColor: '#0000ff' } } } });

// ---- emphasis.label.rich: the hovered label's rich styles, each merged key
// by key over the normal one when the state is entered (zrender's Text
// merges `rich` per name; a probe with env.node off and a highlight showed
// the merged style: the normal keys kept, the emphasis keys over them)
add('emphrich', 'er-bar', "a bar label's emphasis.label.rich: one token restyled on hover, the other kept", {
  xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [5, 6], label: { show: true, formatter: '{a|X}{b|Y}',
    rich: { a: { color: '#ff0000', fontSize: 20 }, b: { color: '#00ff00' } } },
  emphasis: { label: { rich: { b: { color: '#0000ff', fontWeight: 'bold' } } } } }] });

// ---- a treemap's corners (TreemapView: itemStyle.borderRadius on both rects)
const TM = [{ name: 'a', value: 10, children: [{ name: 'a1', value: 6 }, { name: 'a2', value: 4 }] },
  { name: 'b', value: 6, children: [{ name: 'b1', value: 6, itemStyle: { borderRadius: 1 } }] }, { name: 'c', value: 4 }];
add('treemap', 'tm-radius', 'itemStyle.borderRadius 5 on the series, one item its own 1',
  { series: [{ type: 'treemap', roam: false, nodeClick: false, breadcrumb: { show: false }, itemStyle: { borderRadius: 5, gapWidth: 2, borderWidth: 1 }, data: TM }] });
add('treemap', 'tm-radius-levels', "levels' borderRadius [4, 0], an array on the second level",
  { series: [{ type: 'treemap', roam: false, nodeClick: false, breadcrumb: { show: false },
    levels: [{ itemStyle: { borderRadius: 8, borderWidth: 4, gapWidth: 4 } }, { itemStyle: { borderRadius: [4, 0], gapWidth: 1 } }], data: TM }] });

// ---------------------------------------------------------------------------
// the recipes
// ---------------------------------------------------------------------------
const KEYS = ['stroke', 'fill', 'lineWidth', 'lineDash', 'lineDashOffset', 'lineCap', 'opacity'];
// zrender's path defaults, which an element style reads through
const PATH_DEFAULT = { stroke: null, fill: '#000', lineWidth: 1, lineDash: null, lineDashOffset: 0, lineCap: 'butt', opacity: 1 };
function effective(style) {
  const r = {};
  KEYS.forEach(k => { const v = style[k]; r[k] = v === undefined ? PATH_DEFAULT[k] : v; });
  return r;
}
const LINE_KEYS = ['stroke', 'lineWidth', 'lineDash', 'lineDashOffset', 'lineCap', 'opacity'];
const AREA_KEYS = ['fill', 'opacity'];
// a stroked part is matched on its pen, a filled one on its fill
function keyOf(s, area) {
  return JSON.stringify((area ? AREA_KEYS : LINE_KEYS).map(k => s[k]));
}
const defaults = (t, s) => { const o = Object.assign({}, t); Object.keys(s).forEach(k => { if (o[k] == null) o[k] = s[k]; }); return o; };
const lineStyleOf = m => m.getLineStyle();
const areaStyleOf = m => m.getAreaStyle();

// what the option wrote: a getter over the written option, per axis
function writtenGetter(c, kind, mainType, index) {
  const o = c.option;
  const pick = (v, i) => (Array.isArray(v) ? v[i] : (i === 0 ? v : undefined));
  let nodes = [];
  if (kind === 'radar') nodes = [pick(o.radar, index)];
  else if (kind === 'parallel') {
    const pa = (Array.isArray(o.parallelAxis) ? o.parallelAxis : [o.parallelAxis]).filter(Boolean)[index];
    const par = pick(o.parallel, (pa && pa.parallelIndex) || 0);
    nodes = [pa, par && par.parallelAxisDefault];
  } else nodes = [pick(o[mainType], index)];
  return p => {
    for (const n of nodes) {
      let v = n;
      for (const k of p) { v = v == null ? undefined : v[k]; }
      if (v != null) return v;
    }
    return undefined;
  };
}
const srcOf = (w, paths) => (paths.some(p => w(p) != null) ? 'author' : 'theme');

// the recipe per part: { styles: [...], src: {key: [paths]} }
function recipes(kind, m, w) {
  const out = {};
  const lineColour = m.get(['axisLine', 'lineStyle', 'color']);
  const L = ['axisLine', 'lineStyle'];
  const T = ['axisTick', 'lineStyle'];
  const MT = ['minorTick', 'lineStyle'];
  const S = ['splitLine', 'lineStyle'];
  const MS = ['minorSplitLine', 'lineStyle'];
  const A = ['splitArea', 'areaStyle'];
  const lineKeys = { stroke: 'color', lineWidth: 'width', lineDash: 'type', lineDashOffset: 'dashOffset', lineCap: 'cap', opacity: 'opacity' };
  const srcFor = (chains) => {
    const s = {};
    Object.keys(chains).forEach(k => { s[k] = srcOf(w, chains[k]); });
    return s;
  };
  const plain = (base) => {
    const ch = {};
    Object.keys(lineKeys).forEach(k => { ch[k] = [base.concat([lineKeys[k]])]; });
    return ch;
  };
  // the line
  let line = lineStyleOf(m.getModel(L));
  if (kind !== 'angle') line = Object.assign({ lineCap: 'round' }, line);
  if (kind === 'angle') line.fill = null;
  out.line = { styles: [line], src: srcFor(plain(L)) };
  out.arrow = { styles: [{ fill: line.stroke }], src: { fill: srcOf(w, [L.concat(['color'])]) } };
  // the ticks: their own over the line's colour
  out.tick = { styles: [defaults(lineStyleOf(m.getModel(T)), { stroke: lineColour })],
    src: Object.assign(srcFor(plain(T)), { stroke: srcOf(w, [T.concat(['color']), L.concat(['color'])]) }) };
  // the minor ticks: their own over the axisTick model's own keys over the line's colour
  const mtc = plain(MT);
  Object.keys(lineKeys).forEach(k => mtc[k].push(['axisTick', lineKeys[k]]));
  mtc.stroke.push(L.concat(['color']));
  out.minorTick = { styles: [defaults(lineStyleOf(m.getModel(MT)), defaults(lineStyleOf(m.getModel('axisTick')), { stroke: lineColour }))],
    src: srcFor(mtc) };
  // the split lines: one style per colour
  const sc = m.get(S.concat(['color']));
  const scs = Array.isArray(sc) ? sc : [sc];
  let sbase = lineStyleOf(m.getModel(S));
  if (kind === 'single') sbase = m.getModel(S).getLineStyle(['color']);
  out.split = { styles: scs.map(c => {
    if (kind === 'radar') return defaults({ fill: 'none', stroke: c }, sbase);
    if (kind === 'radius') return defaults({ stroke: c, fill: null }, sbase);
    return defaults({ stroke: c }, sbase);
  }), src: srcFor(plain(S)) };
  // the minor split lines
  let ms = lineStyleOf(m.getModel(MS));
  if (kind === 'radius') ms = defaults({ fill: null }, ms);
  out.minorSplit = { styles: [ms], src: srcFor(plain(MS)) };
  // the split areas: one per colour
  const ac = m.get(A.concat(['color']));
  const acs = Array.isArray(ac) ? ac : [ac];
  const abase = areaStyleOf(m.getModel(A));
  out.area = { styles: acs.map(c => (kind === 'radar' ? defaults({ stroke: 'none', fill: c }, abase) : defaults({ fill: c }, abase))),
    src: { fill: srcOf(w, [A.concat(['color'])]), opacity: srcOf(w, [A.concat(['opacity'])]) } };
  // the name: nameTextStyle's colour, else the line's (a radar's names are
  // its axisName, which has a colour of its own by default)
  out.name = { styles: [{ fill: m.getModel('nameTextStyle').getTextColor() || lineColour }],
    src: { fill: kind === 'radar' ? srcOf(w, [['axisName', 'color']])
      : srcOf(w, [['nameTextStyle', 'color'], L.concat(['color'])]) } };
  return out;
}

// the axes of a chart: [kind, model, view group, the AxisBuilder groups]
function axesOf(chart) {
  const ecModel = chart.getModel();
  const out = [];
  const push = (kind, m, view) => out.push({ kind, m, view });
  ['xAxis', 'yAxis'].forEach(t => ecModel.eachComponent(t, m => push('cartesian', m, chart.getViewOfComponentModel(m))));
  ecModel.eachComponent('singleAxis', m => push('single', m, chart.getViewOfComponentModel(m)));
  ecModel.eachComponent('angleAxis', m => push('angle', m, chart.getViewOfComponentModel(m)));
  ecModel.eachComponent('radiusAxis', m => push('radius', m, chart.getViewOfComponentModel(m)));
  ecModel.eachComponent('parallelAxis', m => push('parallel', m, chart.getViewOfComponentModel(m)));
  ecModel.eachComponent('radar', m => {
    const view = chart.getViewOfComponentModel(m);
    // the indicator models are the axes' models; the radar's own carries the split styles
    push('radar', m, view);
  });
  return out;
}

function partOfEl(e) {
  if (e.type === 'text' || e.type === 'tspan') return null;
  if (!e.style) return null;
  return effective(e.style);
}

function readAxis(c, ax, fails) {
  const { kind, m, view } = ax;
  const w = writtenGetter(c, kind, m.mainType, m.componentIndex);
  const rec = { kind, mainType: m.mainType, index: m.componentIndex, parts: {} };
  // the radar's axes are its indicator models; the split styles are the radar's
  const am = kind === 'radar' ? m.getIndicatorModels()[0] : m;
  const R = recipes(kind, am, w);
  if (kind === 'radar') {
    const RS = recipes('radar', m, w);
    R.split = RS.split;
    R.area = RS.area;
    R.minorSplit = null;
  }
  // the elements of the view, by the style they carry
  const els = [];
  let nameEl = null;
  walk(view.group, e => {
    if (e.anid === 'name' && e.style) nameEl = e;
    if (e.isGroup || e.type === 'text' || e.type === 'tspan' || e.type === 'image') return;
    if (e.style && e.type) els.push(e);
  });
  const explained = new Set();
  Object.keys(R).forEach(part => {
    const r = R[part];
    if (!r) return;
    if (part === 'name') {
      if (!nameEl) return;
      const f = nameEl.style.fill;
      if (f !== r.styles[0].fill) fails.push(rec.mainType + rec.index + ' name fill ' + f + ', the recipe gives ' + r.styles[0].fill);
      rec.parts.name = { styles: [{ fill: f }], src: r.src };
      return;
    }
    if (part === 'arrow') {
      const arrows = els.filter(e => e.shape && e.shape.symbolType != null);
      if (!arrows.length) return;
      arrows.forEach(e => explained.add(e));
      arrows.forEach(e => {
        const want = r.styles[0].fill;
        const got = e.style.fill === undefined ? null : e.style.fill;
        if (got !== want) fails.push(rec.mainType + rec.index + ' arrow fill ' + got + ', the recipe gives ' + want);
      });
      rec.parts.arrow = { styles: [{ fill: r.styles[0].fill, opacity: effective(arrows[0].style).opacity }], src: r.src };
      return;
    }
    const styles = [];
    r.styles.forEach(s => {
      const eff = effective(s);
      const area = part === 'area';
      const k = keyOf(eff, area);
      const hit = els.filter(e => !(e.shape && e.shape.symbolType != null) && keyOf(effective(e.style), area) === k
        && (area ? e.style.fill != null && e.style.fill !== 'none' : e.style.stroke != null && e.style.stroke !== 'none'));
      if (hit.length) {
        hit.forEach(e => explained.add(e));
        const keep = {};
        (area ? AREA_KEYS : LINE_KEYS).forEach(q => { keep[q] = eff[q]; });
        styles.push(keep);
      }
    });
    if (styles.length) rec.parts[part] = { styles, src: r.src };
  });
  els.forEach(e => {
    if (explained.has(e)) return;
    // a radar's polygon of the series is not in this view; a break area is not ours
    fails.push(rec.mainType + rec.index + ': an element the recipes do not explain, ' + e.type + ' ' + JSON.stringify(effective(e.style)));
  });
  return rec;
}

// a style value as JSON can hold it: a gradient object as its plain keys
function plainColour(v) {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  return { type: v.type, x: v.x, y: v.y, x2: v.x2, y2: v.y2, r: v.r, global: !!v.global,
    colorStops: (v.colorStops || []).map(q => ({ offset: q.offset, color: q.color })) };
}
function plainStyle(st) {
  const e = effective(st);
  return { fill: plainColour(st.fill === undefined ? null : st.fill), stroke: plainColour(e.stroke), lineWidth: e.lineWidth,
    lineDash: e.lineDash, lineDashOffset: e.lineDashOffset, opacity: e.opacity };
}

// a bar series' background elements, in their order (BarView._backgroundEls)
function readBarBg(chart, fails) {
  const out = [];
  chart.getModel().eachSeriesByType('bar', s => {
    const view = chart.getViewOfSeriesModel(s);
    const els = (view && view._backgroundEls) || [];
    out.push({ seriesIndex: s.seriesIndex, items: els.map((el, i) => {
      must(el, 'a hole in the backgrounds');
      const r = el.type === 'sector' ? el.shape.cornerRadius : el.shape.r;
      return { i, type: el.type, r: r == null ? null : r, style: plainStyle(el.style) };
    }) });
  });
  return out;
}

// a treemap's rects with their corners: global x, y and the size, r
function readTreemap(chart, fails) {
  const out = [];
  chart.getModel().eachSeriesByType('treemap', s => {
    const view = chart.getViewOfSeriesModel(s);
    const rects = [];
    walk(view.group, e => {
      if (e.type !== 'rect' || e.invisible || !e.shape) return;
      const m = e.getComputedTransform();
      const tx = m ? m[4] : 0;
      const ty = m ? m[5] : 0;
      rects.push({ x: e.shape.x + tx, y: e.shape.y + ty, width: e.shape.width, height: e.shape.height,
        r: e.shape.r == null ? null : e.shape.r });
    });
    out.push({ seriesIndex: s.seriesIndex, rects });
  });
  return out;
}

// each row's visual colour on the type's draw type (the model's visual, which
// the view paints the row with)
function readColorBy(chart, fails) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const data = s.getData();
    const key = data.getVisual('drawType') || 'fill';
    const colors = [];
    for (let i = 0; i < data.count(); i++) {
      const st = data.getItemVisual(i, 'style');
      colors.push({ raw: data.getRawIndex(i), color: st && st[key] != null ? String(st[key]) : null });
    }
    out.push({ seriesIndex: s.seriesIndex, type: s.subType, drawType: key, colors });
  });
  return out;
}

// the fill of each datum's element; a line's polyline stroke and area fill
function readPalGrad(chart, fails) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const data = s.getData();
    const rec = { seriesIndex: s.seriesIndex, type: s.subType, fills: [] };
    if (s.subType === 'line') {
      chart.getViewOfSeriesModel(s).group.traverse(e => {
        if (e.type === 'ec-polyline') rec.stroke = plainColour(e.style.stroke);
        if (e.type === 'ec-polygon') rec.area = plainColour(e.style.fill);
      });
    } else {
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        rec.fills.push({ raw: data.getRawIndex(i), fill: el ? plainColour(el.style.fill) : null });
      }
    }
    out.push(rec);
  });
  return out;
}

// each legend item's words and icon paths, by name; each selector button's
// emphasis state style
function readLegend(chart, fails) {
  const lm = chart.getModel().getComponent('legend', 0);
  const view = chart.getViewOfComponentModel(lm);
  const items = [];
  const names = lm.getData().map(m => m.get('name'));
  const kids = view.getContentGroup().children();
  must(kids.length === names.length, 'one item group per name');
  kids.forEach((g, i) => {
    const rec = { name: names[i], text: null, icons: [] };
    g.traverse(e => {
      if (e.type === 'text') {
        rec.text = { fill: e.style.fill, fontSize: e.style.fontSize == null ? null : e.style.fontSize,
          fontWeight: e.style.fontWeight == null ? null : String(e.style.fontWeight) };
      } else if (e.style && e.type !== 'tspan' && e.type !== 'group' && e.style.fill !== 'transparent') {
        const ef = effective(e.style);
        rec.icons.push({ type: e.type, fill: e.style.fill == null ? null : e.style.fill, stroke: ef.stroke,
          lineWidth: ef.lineWidth, opacity: ef.opacity });
      }
    });
    items.push(rec);
  });
  const selectors = [];
  const sg = view.getSelectorGroup ? view.getSelectorGroup() : view._selectorGroup;
  if (sg) sg.children().forEach(t => {
    const st = t.states && t.states.emphasis && t.states.emphasis.style;
    if (!st) return;
    selectors.push({ fill: st.fill == null ? null : st.fill, fontWeight: st.fontWeight == null ? null : String(st.fontWeight),
      fontSize: st.fontSize == null ? null : st.fontSize, backgroundColor: st.backgroundColor == null ? null : st.backgroundColor,
      borderColor: st.borderColor == null ? null : st.borderColor });
  });
  return [{ items, selectors }];
}

// each label's normal rich styles and the emphasis state's, merged as the
// state merges them
function readEmphRich(chart, fails) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const data = s.getData();
    const labels = [];
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const t = el && el.getTextContent();
      if (!t) continue;
      const pick = st => ({ fill: st.fill == null ? null : st.fill, fontSize: st.fontSize == null ? null : st.fontSize,
        fontWeight: st.fontWeight == null ? null : String(st.fontWeight) });
      const normal = {};
      const rich = t.style.rich || {};
      Object.keys(rich).forEach(n => { normal[n] = pick(rich[n]); });
      const es = t.states && t.states.emphasis && t.states.emphasis.style;
      const emph = {};
      Object.keys(rich).forEach(n => {
        const over = es && es.rich && es.rich[n] ? es.rich[n] : {};
        emph[n] = pick(Object.assign({}, rich[n], over));
      });
      labels.push({ i, text: t.style.text, normal, emphasis: emph });
    }
    out.push({ seriesIndex: s.seriesIndex, labels });
  });
  return out;
}

function runCase(c) {
  const fails = [];
  const option = clone(c.option);
  option.animation = false;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  let axes = [];
  let series = null;
  try {
    chart.setOption(option);
    chart.renderToSVGString();
    if (c.group === 'axis') axes = axesOf(chart).map(ax => readAxis(c, ax, fails));
    else if (c.group === 'barbg') series = readBarBg(chart, fails);
    else if (c.group === 'treemap') series = readTreemap(chart, fails);
    else if (c.group === 'colorby') series = readColorBy(chart, fails);
    else if (c.group === 'palgrad') series = readPalGrad(chart, fails);
    else if (c.group === 'legend') series = readLegend(chart, fails);
    else if (c.group === 'emphrich') series = readEmphRich(chart, fails);
  } finally {
    chart.dispose();
  }
  const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option, fails, axes };
  if (series) rec.series = series;
  return rec;
}

function guards(out) {
  const g = [];
  const guard = (name, ok) => {
    let v = false;
    try { v = !!(typeof ok === 'function' ? ok() : ok); } catch (e) { v = false; }
    g.push({ name, ok: v });
  };
  guard('no case fails its recipes', out.cases.every(c => c.fails.length === 0));
  const cs = id => out.cases.find(c => c.id === id);
  const axis = (id, mt, i) => cs(id).axes.find(a => a.mainType === mt && a.index === (i || 0));
  const lc = (() => { try { return axis('cart-line-colour', 'xAxis'); } catch (e) { return {}; } })();
  guard("the ticks follow the line's colour", () => lc.parts.tick.styles[0].stroke === '#c23531' && lc.parts.tick.src.stroke === 'author');
  guard("the arrows follow the line's colour", () => lc.parts.arrow.styles[0].fill === '#c23531');
  guard("the name follows the line's colour", () => lc.parts.name.styles[0].fill === '#c23531');
  guard('the axis line has a round cap unless written', () => lc.parts.line.styles[0].lineCap === 'round'
    && axis('cart-line-full', 'yAxis').parts.line.styles[0].lineCap === 'butt');
  const mf = (() => { try { return axis('cart-minor-follows-line', 'yAxis'); } catch (e) { return {}; } })();
  guard("a minor tick takes the line's colour, not axisTick.lineStyle's", () => mf.parts.minorTick.styles[0].stroke === '#d48265'
    && mf.parts.minorTick.styles[0].lineWidth === 1);
  const mk = (() => { try { return axis('cart-minor-tick-keys', 'yAxis'); } catch (e) { return {}; } })();
  guard("a minor tick reads axisTick's own color / width", () => mk.parts.minorTick.styles[0].stroke === '#ff00ff'
    && mk.parts.minorTick.styles[0].lineWidth === 2);
  guard('a split line list draws one style per colour', () => axis('cart-split-full', 'yAxis').parts.split.styles.length === 2);
  guard("nameTextStyle's colour wins", () => axis('cart-name-own', 'xAxis').parts.name.styles[0].fill === '#00ff00');
  guard("the angle axis' line has no round cap", () => axis('polar-full', 'angleAxis').parts.line.styles[0].lineCap === 'butt');
  const bg = id => cs(id).series[0].items;
  guard('a background strip per bar', () => bg('bg-default').length === 5);
  guard('backgroundStyle.color is the fill', () => bg('bg-colour')[0].style.fill === 'rgba(220, 30, 30, 0.3)');
  guard('a border with a width is a pen', () => bg('bg-border')[0].style.stroke === '#333333' && bg('bg-border')[0].style.lineWidth === 2
    && bg('bg-border')[0].style.opacity === 0.6 && bg('bg-border')[0].style.lineDash === 'dashed');
  guard('a border with no width is width 0', () => bg('bg-border-no-width')[0].style.lineWidth === 0);
  guard("a polar bar's background is a sector", () => bg('bg-polar')[0].type === 'sector');
  guard('a gradient fill stays a gradient', () => typeof bg('bg-gradient')[0].style.fill === 'object');
  const cb = id => cs(id).series[0].colors.map(q => q.color);
  guard("lines colorBy 'data'", () => cb('cb-lines').join() === '#aa0000,#123456,#00aa00,#0000aa');
  guard("parallel colorBy 'data'", () => cb('cb-parallel').join() === '#aa0000,#123456,#00aa00,#0000aa');
  const pg = cs('pg-series').series;
  guard("a bar series takes the gradient entry whole", () => typeof pg[0].fills[0].fill === 'object');
  guard("a pie by data: the gradient, the colour, the gradient", () => typeof pg[1].fills[0].fill === 'object'
    && pg[1].fills[1].fill === '#00aa00' && typeof pg[1].fills[2].fill === 'object');
  guard("a line's stroke and area are the gradient", () => typeof cs('pg-line').series[0].stroke === 'object'
    && typeof cs('pg-line').series[0].area === 'object');
  const li = (id, n) => cs(id).series[0].items.find(q => q.name === n);
  guard("an item's own text colour, size and weight", () => li('lg-items', 'A').text.fill === '#ff0000'
    && li('lg-items', 'A').text.fontSize === 16 && li('lg-items', 'A').text.fontWeight === 'bold');
  guard("an item's own icon colour and opacity", () => li('lg-items', 'A').icons[0].fill === '#00ff00'
    && li('lg-items', 'A').icons[0].opacity === 0.5);
  guard("an item's own border over the legend's", () => li('lg-items', 'B').icons[0].stroke === '#0000ff'
    && li('lg-items', 'B').icons[0].lineWidth === 3);
  guard("an unselected item's own inactive colours", () => li('lg-items', 'C').text.fill === '#aaaaaa'
    && li('lg-items', 'C').icons[0].fill === '#aaaaaa' && li('lg-items', 'C').icons[0].stroke === '#888888');
  guard("a line item's own rule", () => li('lg-items', 'L').icons.some(q => q.stroke === '#ff00ff' && q.lineWidth === 4));
  guard("an unselected line item's own inactive rule", () => li('lg-item-inactive-line', 'L').icons.some(q => q.stroke === '#00ffff' && q.lineWidth === 5));
  guard("the hovered selector: font and box", () => cs('lg-selector-emph').series[0].selectors[0].fontWeight === 'bold'
    && cs('lg-selector-emph').series[0].selectors[0].backgroundColor === '#eeeeee');
  const er = cs('er-bar').series[0].labels[0];
  guard('the hovered token takes the emphasis keys over its own', () => er.emphasis.b.fill === '#0000ff'
    && er.emphasis.b.fontWeight === 'bold' && er.normal.b.fill === '#00ff00');
  guard('a token the emphasis does not name keeps its style', () => er.emphasis.a.fill === '#ff0000' && er.emphasis.a.fontSize === 20);
  const tm = id => cs(id).series[0].rects;
  guard("a treemap's rects take the radius", () => tm('tm-radius').filter(r => r.r === 5).length > 4 && tm('tm-radius').some(r => r.r === 1));
  guard("a level's radius", () => tm('tm-radius-levels').some(r => r.r === 8) && tm('tm-radius-levels').some(r => Array.isArray(r.r)));
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version,
    notes: [
      'parts: the styles of the elements of the axis view, matched against the transcribed recipes.',
      "src 'author': the option wrote the value along upstream's chain; 'theme': the theme's default (the skin in the port).",
      "lineDash as the style holds it: a word ('dashed', 'dotted', 'solid'), a list, or null; the canvas normalises a word against the width.",
    ],
    cases: CASES.map(runCase),
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
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
out1.cases.forEach(q => q.fails.forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (process.env.ORACLE_DUMP) console.log(JSON.stringify(out1.cases.map(c => ({ id: c.id, axes: c.axes })), null, 1));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
