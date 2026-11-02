// Round 6 R6-D: the pens of a series' paths -- the stroke, its width, its
// dash and the dash's phase -- per series type: getItemStyle's borderColor /
// borderWidth / borderType / borderDashOffset and getLineStyle's color /
// width / type / dashOffset, an item's own over its series', and the views'
// own rules over them:
//   a radar's symbols take the item's visual style (useStyle(itemStyle)) and
//     then setColor -- an empty symbol strokes in the colour at 2, a 'line'
//     symbol strokes in the colour at the border's width;
//   a gauge's pointer takes the visual style and pointer.itemStyle over it,
//     its progress arc the visual style and progress.itemStyle over it;
//   a chord's ribbon takes its link's getLineStyle (stroke the colour word
//     as written: 'source' is a word the canvas does not take);
// and the states' styles over them: a radar symbol's state is
// clone(getItemStyle of [state, 'itemStyle']), a gauge pointer's and a
// chord ribbon's setStatesStylesFromModel.
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false):
// each case set at T0 and settled, an optional action dispatched at T1 and
// settled; then every path under the series' views (a part filter where a
// case names one) that strokes -- lineWidth above nought and a stroke that is
// not null nor 'none' -- as `stroke|width|dash|offset`: the stroke
// `#rrggbbaa` (zrender's color.parse), 'grad' a gradient, 'x:<word>' a word
// zrender's parse does not take; the dash normalizeLineDash'd against the
// width ('solid' none; 'ignored' one setLineDash does not take -- an entry
// that is no finite number of nought or more), the offset the style's (0
// where none), the ends the
// canvas' defaults (butt, miter, 10) where the style has none. `pens` is the
// sorted set of these, `n` how many stroked paths.
//
// Round 6 R6-E adds, on its own cases only (the R6-D records keep their
// fields): `shapes` -- each path of the part as `type|cx|cy|r0|r|a|sweep`
// (a sector's or a sausage's ring, the sweep's clockwise start and its
// size; a circle's centre and radius; a rect's x|y|w|h) -- `fills` the
// sorted set of the fills of the part, `hits` what zr's findHover finds at the
// given points (the part, '' another path, '-' nothing), and `at`: sampled
// at T0 + at with the animation running instead of settled. And on every
// case a path whose stroke scales with it (no strokeNoScale, a transform
// that scales: a pictorial bar's glyph, which useStyle(symbolMeta.style)
// leaves without the strokeNoScale createPath gave it) records the width,
// the dash and the offset as drawn -- times the transform's line scale
// sqrt|det| -- and the ends as the canvas takes them: `style.x || default`.
//
// Round 6 R6-F adds, on its own cases only: `looks` -- each path of the part
// as `opacity|shadowBlur|shadowOffsetX|shadowOffsetY|shadowColor` (the
// colour only where a shadow is cast), the sorted set; `cHits` what zr's
// findHover finds at each rect of the part's centre and a pixel either side
// of it; the gauge parts `line` (its split lines and ticks: a case shows one
// of them), `anchor`, `box` (a title's or a reading's background rect, a
// child of its Text) and `words` (a title's or a reading's TSpans: looks
// only); and a pen's width there as Number has it ('Infinity' one the
// canvas refuses).
// Run: node tools/advchart-oracle/series-borders.js -> tests/fixtures/advchart-series-borders.json
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
global.Date = ClockDate;
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-series-borders.json');
echarts.env.node = false;
const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};
class OracleError extends Error {}
function must(c, m) { if (!c) throw new OracleError(m); }
const W = 400;
const H = 300;
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;

const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666'];
const IS = { borderColor: '#000', borderWidth: 3, borderType: 'dashed', borderDashOffset: 2 };
const LS = { color: '#333', width: 4, type: 'dotted', dashOffset: 1 };
const N = ['A', 'B', 'C'];
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#f00' }, { offset: 1, color: '#00f' }] };
const cart = s => ({ animation: false, color: PAL, xAxis: { type: 'category', data: N }, yAxis: {}, series: [s] });
const solo = s => ({ animation: false, color: PAL, series: [s] });
const IND = [{ name: 'p', max: 10 }, { name: 'q', max: 10 }, { name: 'r', max: 10 }];
const radar = s => ({ animation: false, color: PAL, radar: { indicator: IND },
  series: [Object.assign({ type: 'radar', data: [{ value: [3, 5, 2] }] }, s)] });
const gauge = s => solo(Object.assign({ type: 'gauge', data: [{ value: 40 }] }, s));
const chord = s => solo(Object.assign({ type: 'chord', data: [{ name: 'a' }, { name: 'b' }],
  links: [{ source: 'a', target: 'b', value: 3 }] }, s));
const HL = { type: 'highlight', seriesIndex: 0, dataIndex: 0 };
// R6-E: the same pens with every number written as a numeric string
const ISS = { borderColor: '#000', borderWidth: '3', borderType: 'dashed', borderDashOffset: '2', borderMiterLimit: '4' };
const LSS = { color: '#333', width: '4', type: 'dotted', dashOffset: '1', miterLimit: '4' };
const RC = { show: true, roundCap: true, width: 14, itemStyle: { borderColor: '#000', borderWidth: 3 } };
// R6-F: a gauge with one part shown
const GH = { axisLine: { show: false }, splitLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false },
  pointer: { show: false }, anchor: { show: false }, title: { show: false }, detail: { show: false } };
const gOnly = (o) => gauge(Object.assign({}, GH, o));
const LK = { looks: true };
const SHD = { shadowBlur: 3, shadowColor: '#000', shadowOffsetX: 1 };

// [id, option, part ('' every path, 'symbol' a radar's symbols, 'pointer',
//  'progress', 'ribbon' a chord's links), action]
function cases() {
  return [
    // ---- a radar's symbols ----
    ['radar.rest', radar({}), 'symbol'],
    ['radar.border', radar({ itemStyle: IS }), 'symbol'],
    ['radar.width-only', radar({ itemStyle: { borderColor: '#f00' } }), 'symbol'],
    ['radar.no-colour', radar({ itemStyle: { borderWidth: 4 } }), 'symbol'],
    ['radar.auto', radar({ itemStyle: { borderColor: 'auto', borderWidth: 2 } }), 'symbol'],
    ['radar.item-auto', radar({ itemStyle: { borderWidth: 2 }, data: [{ value: [3, 5, 2], itemStyle: { borderColor: 'auto' } }] }),
      'symbol'],
    ['radar.none', radar({ itemStyle: { borderColor: 'none', borderWidth: 2 } }), 'symbol'],
    ['radar.empty', radar({ symbol: 'emptyCircle', itemStyle: IS }), 'symbol'],
    ['radar.line', radar({ symbol: 'line', itemStyle: IS }), 'symbol'],
    ['radar.item', radar({ itemStyle: IS, data: [{ value: [3, 5, 2] },
      { value: [4, 2, 6], itemStyle: { borderWidth: 5, borderColor: '#0f0', borderType: [2, 1], borderDashOffset: 1 } }] }), 'symbol'],
    ['radar.line-rest', radar({ symbol: 'line' }), 'symbol'],
    ['radar.dash-only', radar({ itemStyle: { borderColor: '#000', borderType: 'dotted' } }), 'symbol'],
    ['radar.grad', radar({ itemStyle: { borderColor: GRAD, borderWidth: 2 } }), 'symbol'],
    ['radar.empty-grad', radar({ symbol: 'emptyCircle', itemStyle: { borderColor: GRAD, borderWidth: 3 } }), 'symbol'],
    ['radar.size', radar({ symbolSize: 20, itemStyle: { borderColor: '#000', borderWidth: 2 } }), 'symbol'],
    ['radar.array-row', radar({ itemStyle: IS, data: [[3, 5, 2]] }), 'symbol'],
    ['radar.emphasis', radar({ itemStyle: IS, emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f', borderType: 'solid' } } }),
      'symbol', HL],
    ['radar.emphasis-rest', radar({ emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f' } } }), 'symbol', HL],
    ['radar.select', radar({ selectedMode: 'single', itemStyle: IS, select: { itemStyle: { borderColor: '#f0f', borderWidth: 4 } } }),
      'symbol', { type: 'select', seriesIndex: 0, dataIndex: 0 }],
    ['radar.blur', radar({ itemStyle: IS, emphasis: { focus: 'self' }, blur: { itemStyle: { borderColor: '#0ff', borderWidth: 1 } },
      data: [{ value: [3, 5, 2] }, { value: [4, 2, 6] }] }), 'symbol', HL],
    // ---- a gauge's pointer and progress arc ----
    ['gauge.rest', gauge({}), 'pointer'],
    ['gauge.border', gauge({ itemStyle: IS }), 'pointer'],
    ['gauge.pointer', gauge({ itemStyle: IS, pointer: { itemStyle: { borderColor: '#f00', borderWidth: 1, borderType: 'solid' } } }),
      'pointer'],
    ['gauge.pointer-only', gauge({ pointer: { itemStyle: { borderColor: '#f00', borderWidth: 2 } } }), 'pointer'],
    ['gauge.auto', gauge({ itemStyle: { borderColor: 'auto', borderWidth: 2 } }), 'pointer'],
    ['gauge.item-auto', gauge({ itemStyle: { borderWidth: 2 }, data: [{ value: 40, itemStyle: { borderColor: 'auto' } }] }), 'pointer'],
    ['gauge.item', gauge({ itemStyle: IS, data: [{ value: 40, itemStyle: { borderColor: '#0f0' } },
      { value: 70, pointer: { itemStyle: { borderWidth: 5 } } }] }), 'pointer'],
    ['gauge.icon', gauge({ itemStyle: IS, pointer: { icon: 'rect' } }), 'pointer'],
    ['gauge.icon-empty', gauge({ itemStyle: IS, pointer: { icon: 'emptyCircle' } }), 'pointer'],
    ['gauge.icon-line', gauge({ itemStyle: { borderWidth: 3 }, pointer: { icon: 'line' } }), 'pointer'],
    ['gauge.width-word', gauge({ itemStyle: IS, pointer: { itemStyle: { borderWidth: 'x' } } }), 'pointer'],
    ['gauge.progress', gauge({ itemStyle: IS, progress: { show: true, itemStyle: { borderWidth: 4 } } }), 'progress'],
    ['gauge.progress-ends', gauge({ itemStyle: Object.assign({ borderJoin: 'round', borderCap: 'square' }, IS),
      progress: { show: true, itemStyle: { borderMiterLimit: 4, borderColor: '#f00' } } }), 'progress'],
    ['gauge.emphasis', gauge({ itemStyle: IS, emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f' } } }), 'pointer', HL],
    // ---- a chord's ribbons ----
    ['chord.rest', chord({}), 'ribbon'],
    ['chord.width', chord({ lineStyle: { width: 2 } }), 'ribbon'],
    ['chord.colour', chord({ lineStyle: { width: 2, color: '#000', type: 'dashed', dashOffset: 1 } }), 'ribbon'],
    ['chord.target', chord({ lineStyle: { width: 2, color: 'target' } }), 'ribbon'],
    ['chord.link', chord({ lineStyle: { width: 2, color: '#000' },
      links: [{ source: 'a', target: 'b', value: 3, lineStyle: { type: [3, 2], width: 4, dashOffset: 2 } }] }), 'ribbon'],
    ['chord.emphasis', chord({ lineStyle: { width: 2, color: '#000' },
      emphasis: { lineStyle: { width: 5, color: '#f00', type: 'dotted' } } }), 'ribbon',
      { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 0 }],
    // ---- every other series, every stroked path ----
    ['bar', cart({ type: 'bar', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['bar.zero-width-dash', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 0, borderType: [5, 3] },
      emphasis: { itemStyle: { borderWidth: 3 } }, data: [3] }), '', HL],
    ['line', cart({ type: 'line', symbol: 'circle', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.rest', cart({ type: 'line', symbol: 'circle', data: [3, 5, 2] }), ''],
    ['line.ls', cart({ type: 'line', symbol: 'circle', lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.is', cart({ type: 'line', symbol: 'circle', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['line.empty', cart({ type: 'line', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.line-symbol', cart({ type: 'line', symbol: 'line', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.line-rest', cart({ type: 'line', symbol: 'line', data: [3, 5, 2] }), ''],
    ['line.grad-symbol', cart({ type: 'line', symbol: 'circle', itemStyle: { borderColor: GRAD, borderWidth: 2 }, data: [3, 5, 2] }), ''],
    ['scatter', cart({ type: 'scatter', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['scatter.empty', cart({ type: 'scatter', symbol: 'emptyCircle', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['scatter.line-symbol', cart({ type: 'scatter', symbol: 'line', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['scatter.line-rest', cart({ type: 'scatter', symbol: 'line', data: [3, 5, 2] }), ''],
    ['scatter.line-item', cart({ type: 'scatter', symbol: 'line', data: [3, { value: 5, itemStyle: { borderWidth: 4 } }] }), ''],
    ['escatter', cart({ type: 'effectScatter', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['pie', solo({ type: 'pie', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['funnel', solo({ type: 'funnel', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['candle', cart({ type: 'candlestick', itemStyle: Object.assign({ borderColor0: '#444' }, IS), data: [[2, 4, 1, 5], [3, 2, 1, 4]] }), ''],
    ['boxplot', cart({ type: 'boxplot', itemStyle: IS, data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }), ''],
    ['heatmap', { animation: false, color: PAL, xAxis: { type: 'category', data: N }, yAxis: { type: 'category', data: N },
      visualMap: { show: false, min: 0, max: 5 }, series: [{ type: 'heatmap', itemStyle: IS, data: [[0, 0, 1], [1, 1, 3]] }] }, ''],
    ['sunburst', solo({ type: 'sunburst', itemStyle: IS, data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }] }), ''],
    ['sunburst.join', solo({ type: 'sunburst', itemStyle: Object.assign({ borderJoin: 'round' }, IS),
      data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }] }), ''],
    ['pie.join', solo({ type: 'pie', itemStyle: Object.assign({ borderJoin: 'miter' }, IS), data: [3, 5, 2] }), ''],
    ['pie.zero-width-dash', solo({ type: 'pie', itemStyle: { borderColor: '#000', borderWidth: 0, borderType: [5, 3] },
      emphasis: { itemStyle: { borderWidth: 3 } }, data: [3] }), '', HL],
    ['treemap', solo({ type: 'treemap', breadcrumb: { show: false }, itemStyle: IS,
      data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }] }), ''],
    ['graph', solo({ type: 'graph', layout: 'none', itemStyle: IS, lineStyle: LS,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 10, y: 10 }], links: [{ source: 'a', target: 'b' }] }), ''],
    ['tree', solo({ type: 'tree', itemStyle: Object.assign({ color: '#abc' }, IS), lineStyle: LS, data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.number-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: 4 },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.bad-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: [{}, 2] },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.negative-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: [-2, 3] },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.string-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: ['4', '2'] },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['sankey', solo({ type: 'sankey', itemStyle: IS, lineStyle: Object.assign({ opacity: 0.5 }, LS),
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] }), ''],
    ['sankey.band', solo({ type: 'sankey', lineStyle: { borderColor: '#000', borderWidth: 2, borderType: 'dashed', borderDashOffset: 1 },
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] }), ''],
    ['parallel', { animation: false, color: PAL, parallelAxis: [{ dim: 0 }, { dim: 1 }],
      series: [{ type: 'parallel', lineStyle: LS, data: [[1, 2], [3, 4]] }] }, ''],
    ['parallel.is-only', { animation: false, color: PAL, parallelAxis: [{ dim: 0 }, { dim: 1 }],
      series: [{ type: 'parallel', itemStyle: IS, data: [[1, 2], [3, 4]] }] }, ''],
    ['lines', { animation: false, color: PAL, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: LS, data: [{ coords: [[0, 0], [5, 5]] }] }] }, ''],
    ['lines.is-only', { animation: false, color: PAL, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', itemStyle: IS, data: [{ coords: [[0, 0], [5, 5]] }] }] }, ''],
    ['pict', cart({ type: 'pictorialBar', itemStyle: IS, symbol: 'rect', data: [3, 5, 2] }), ''],
    ['river', { animation: false, color: PAL, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', itemStyle: IS,
      data: [['2015/11/08', 3, 'a'], ['2015/11/09', 4, 'a']] }] }, ''],
    ['chord.nodes', chord({ itemStyle: IS }), ''],
    ['polarbar', { animation: false, color: PAL, polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', itemStyle: IS, data: [3, 5, 2] }] }, ''],
    // ==== R6-E ====
    // ---- a round-capped progress arc and track: one Sausage, one outline ----
    ['gauge.round', gauge({ progress: RC }), 'progress', null, { shapes: true, hits: true }],
    ['gauge.round-dash', gauge({ progress: Object.assign({}, RC, { itemStyle: ISS }) }), 'progress', null, { shapes: true }],
    ['gauge.round-two', gauge({ progress: Object.assign({}, RC, { overlap: false }), data: [{ value: 40 }, { value: 70 }] }),
      'progress', null, { shapes: true, hits: true }],
    ['gauge.round-ccw', gauge({ clockwise: false, progress: Object.assign({}, RC, { itemStyle: IS }) }), 'progress', null,
      { shapes: true, hits: true }],
    ['gauge.round-emphasis', gauge({ progress: RC, emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f' } } }),
      'progress', HL, { shapes: true }],
    ['gauge.round-grow', Object.assign(gauge({ progress: RC }), { animation: true }), 'progress', null,
      { shapes: true, at: 300 }],
    ['gauge.round-track', gauge({ axisLine: { roundCap: true } }), 'track', null, { shapes: true }],
    ['gauge.round-stops', gauge({ axisLine: { roundCap: true, lineStyle: { width: 12, shadowBlur: 4, shadowColor: '#000',
      color: [[0.3, '#f00'], [0.7, '#0f0'], [1, '#00f']] } } }), 'track', null, { shapes: true }],
    ['gauge.track', gauge({ axisLine: { lineStyle: { color: [[0.4, '#f00'], [1, '#00f']] } } }), 'track', null, { shapes: true }],
    ['polarbar.round', { animation: false, color: PAL, polar: {}, radiusAxis: { type: 'category', data: N }, angleAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', roundCap: true, itemStyle: IS, data: [3, 5, 2] }] }, '', null,
      { shapes: true }],
    // ---- numbers written as numeric strings ----
    ['radar.str', radar({ itemStyle: ISS }), 'symbol'],
    ['gauge.str', gauge({ itemStyle: ISS }), 'pointer'],
    ['gauge.pointer-str', gauge({ pointer: { itemStyle: ISS } }), 'pointer'],
    ['gauge.progress-str', gauge({ progress: { show: true, itemStyle: ISS } }), 'progress'],
    ['chord.str', chord({ lineStyle: Object.assign({}, LSS, { color: '#000' }) }), 'ribbon'],
    ['bar.str', cart({ type: 'bar', itemStyle: ISS, data: [3, 5, 2] }), '', null, { shapes: true }],
    ['line.str', cart({ type: 'line', symbol: 'circle', itemStyle: ISS, lineStyle: LSS, data: [3, 5, 2] }), ''],
    ['scatter.str', cart({ type: 'scatter', itemStyle: ISS, data: [3, 5, 2] }), ''],
    ['scatter.empty-str', cart({ type: 'scatter', symbol: 'emptyCircle', itemStyle: ISS, data: [3, 5, 2] }), ''],
    ['escatter.str', cart({ type: 'effectScatter', itemStyle: ISS, data: [3, 5, 2] }), ''],
    ['pie.str', solo({ type: 'pie', itemStyle: ISS, data: [3, 5, 2] }), ''],
    ['funnel.str', solo({ type: 'funnel', itemStyle: ISS, data: [3, 5, 2] }), ''],
    ['candle.str', cart({ type: 'candlestick', itemStyle: Object.assign({ borderColor0: '#444' }, ISS), data: [[2, 4, 1, 5], [3, 2, 1, 4]] }), ''],
    ['boxplot.str', cart({ type: 'boxplot', itemStyle: ISS, data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }), ''],
    ['heatmap.str', { animation: false, color: PAL, xAxis: { type: 'category', data: N }, yAxis: { type: 'category', data: N },
      visualMap: { show: false, min: 0, max: 5 }, series: [{ type: 'heatmap', itemStyle: ISS, data: [[0, 0, 1], [1, 1, 3]] }] }, ''],
    ['sunburst.str', solo({ type: 'sunburst', itemStyle: ISS, data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }] }), ''],
    ['treemap.str', solo({ type: 'treemap', breadcrumb: { show: false }, itemStyle: ISS,
      data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }] }), '', null, { shapes: true }],
    ['graph.str', solo({ type: 'graph', layout: 'none', itemStyle: ISS, lineStyle: LSS,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 10, y: 10 }], links: [{ source: 'a', target: 'b' }] }), ''],
    ['tree.str', solo({ type: 'tree', itemStyle: Object.assign({ color: '#abc' }, ISS), lineStyle: LSS,
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['sankey.str', solo({ type: 'sankey', itemStyle: ISS, lineStyle: Object.assign({ opacity: 0.5 }, LSS),
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] }), ''],
    ['sankey.band-str', solo({ type: 'sankey', lineStyle: { borderColor: '#000', borderWidth: '2', borderType: 'dashed',
      borderDashOffset: '1', borderMiterLimit: '4' },
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] }), ''],
    ['parallel.str', { animation: false, color: PAL, parallelAxis: [{ dim: 0 }, { dim: 1 }],
      series: [{ type: 'parallel', lineStyle: LSS, data: [[1, 2], [3, 4]] }] }, ''],
    ['lines.str', { animation: false, color: PAL, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: LSS, data: [{ coords: [[0, 0], [5, 5]] }] }] }, ''],
    ['pict.str', cart({ type: 'pictorialBar', itemStyle: ISS, symbol: 'rect', data: [3, 5, 2] }), ''],
    ['river.str', { animation: false, color: PAL, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', itemStyle: ISS,
      data: [['2015/11/08', 3, 'a'], ['2015/11/09', 4, 'a']] }] }, ''],
    ['chord.nodes-str', chord({ itemStyle: ISS }), ''],
    ['polarbar.str', { animation: false, color: PAL, polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', itemStyle: ISS, data: [3, 5, 2] }] }, ''],
    // ---- a width that is a string but no positive number ----
    ...['0', 'abc', ''].map(w => [
      ['bar.w' + JSON.stringify(w), cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: w }, data: [3, 5] }), '', null,
        { shapes: true }],
      ['gauge.w' + JSON.stringify(w), gauge({ itemStyle: { borderColor: '#000', borderWidth: w } }), 'pointer'],
      ['line.w' + JSON.stringify(w), cart({ type: 'line', symbol: 'circle', itemStyle: { borderColor: '#000', borderWidth: w },
        lineStyle: { width: w }, data: [3, 5, 2] }), ''],
      ['scatter.w' + JSON.stringify(w), cart({ type: 'scatter', itemStyle: { borderColor: '#000', borderWidth: w }, data: [3, 5] }), ''],
      ['pie.w' + JSON.stringify(w), solo({ type: 'pie', itemStyle: { borderColor: '#000', borderWidth: w }, data: [3, 5] }), ''],
    ]).reduce((a, b) => a.concat(b), []),
    ['bar.item-abc', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 3 },
      data: [3, { value: 5, itemStyle: { borderWidth: 'abc' } }] }), '', null, { shapes: true }],
    ['line.item-str', cart({ type: 'line', symbol: 'circle', itemStyle: { borderColor: '#000', borderWidth: 3 },
      data: [3, { value: 5, itemStyle: { borderWidth: '1' } }, { value: 2, itemStyle: { borderWidth: '' } }] }), ''],
    ['bar.miter-empty', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 2, borderMiterLimit: '',
      borderDashOffset: '', borderType: [4, 2] }, data: [3] }), ''],
    ['gauge.pointer-miter', gauge({ pointer: { itemStyle: { borderColor: '#000', borderWidth: '2', borderMiterLimit: '6',
      borderDashOffset: '3', borderType: [4, 2] } } }), 'pointer'],
    // ---- a pictorial bar's glyphs: no setColor; a pen in the glyph's frame ----
    ['pict.empty', cart({ type: 'pictorialBar', symbol: 'emptyCircle', data: [3, 5] }), '', null, { fills: true }],
    ['pict.empty-border', cart({ type: 'pictorialBar', symbol: 'emptyCircle', itemStyle: { borderColor: '#000', borderWidth: 2 },
      data: [3, 5] }), '', null, { fills: true }],
    ['pict.empty-size', cart({ type: 'pictorialBar', symbol: 'emptyRect', symbolSize: [20, 20],
      itemStyle: { borderColor: '#000', borderWidth: 40, borderType: [20, 10], borderDashOffset: 10 }, data: [3, 5] }), '', null,
      { fills: true }],
    ['pict.line', cart({ type: 'pictorialBar', symbol: 'line', itemStyle: { borderColor: '#000', borderWidth: 30 }, data: [3, 5] }),
      '', null, { fills: true }],
    ['pict.line-rest', cart({ type: 'pictorialBar', symbol: 'line', data: [3, 5] }), '', null, { fills: true }],
    ['pict.repeat', cart({ type: 'pictorialBar', symbol: 'emptyRect', symbolRepeat: true, symbolSize: [16, 8],
      itemStyle: { borderColor: '#000', borderWidth: 25 }, data: [3, 5] }), '', null, { fills: true }],
    ['pict.empty-emphasis', cart({ type: 'pictorialBar', symbol: 'emptyCircle', symbolSize: [20, 20],
      emphasis: { itemStyle: { borderColor: '#00f', borderWidth: 60 } }, data: [3, 5] }), '', HL, { fills: true }],
    ['pict.empty-item', cart({ type: 'pictorialBar', symbol: 'emptyTriangle', symbolSize: [20, 20],
      data: [3, { value: 5, itemStyle: { color: '#0f0', borderColor: '#f00', borderWidth: 20 } }] }), '', null, { fills: true }],
    // ---- the mutation round's follow-ups ----
    ['gauge.flat', gauge({ progress: { show: true, width: 14, itemStyle: { borderColor: '#000', borderWidth: 3 } } }), 'progress', null,
      { shapes: true }],
    ['bar.abc-no-colour', cart({ type: 'bar', itemStyle: { borderWidth: 'abc' }, data: [3, 5] }), '', null, { shapes: true }],
    ['bar.emphasis-str', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 1 },
      emphasis: { itemStyle: { borderWidth: '6', borderDashOffset: '3', borderType: 'dashed' } }, data: [3] }), '', HL],
    ['bar.item-offset-str', cart({ type: 'bar', itemStyle: IS, data: [3, { value: 5, itemStyle: { borderDashOffset: '5' } }] }), ''],
    ['line.clip', cart({ type: 'line', symbol: 'none', areaStyle: {}, data: [3, 5, 2] }), '', null, { clip: true }],
    ['line.w0-clip', cart({ type: 'line', symbol: 'none', areaStyle: {}, lineStyle: { width: 0 }, data: [3, 5, 2] }), '', null,
      { clip: true }],
    ['line.w4-clip', cart({ type: 'line', symbol: 'none', lineStyle: { width: 4 }, data: [3, 5, 2] }), '', null, { clip: true }],
    // ==== R6-F ====
    // ---- a gauge's parts: the lineStyle / itemStyle keys getLineStyle and getItemStyle hand over ----
    ['gauge.track-opacity', gOnly({ axisLine: { lineStyle: { opacity: 0.5, color: [[0.4, '#f00'], [1, '#00f']] } } }), 'track',
      null, LK],
    ['gauge.track-round-opacity', gOnly({ axisLine: { roundCap: true, lineStyle: Object.assign({ opacity: 0.3, color: [[1, '#0f0']] },
      SHD) } }), 'track', null, LK],
    ['gauge.track-pen-keys', gOnly({ axisLine: { lineStyle: { color: [[1, '#f00']], type: 'dashed', dashOffset: 2, cap: 'round',
      join: 'round', miterLimit: 4, opacity: 0.7 } } }), 'track', null, LK],
    ['gauge.track-default-opacity', gOnly({ axisLine: { lineStyle: { opacity: 0.4 } } }), 'track', null, LK],
    ['gauge.split-looks', gOnly({ splitLine: { show: true, lineStyle: Object.assign({ color: '#f00', width: 3, opacity: 0.4,
      type: 'dashed', dashOffset: 2, cap: 'round', join: 'bevel', miterLimit: 5 }, SHD) } }), 'line', null, LK],
    ['gauge.split-auto-dash', gOnly({ axisLine: { show: false, lineStyle: { color: [[0.5, '#f00'], [1, '#00f']] } },
      splitLine: { show: true, lineStyle: { color: 'auto', width: 2, type: [4, 2], opacity: 0.8 } } }), 'line', null, LK],
    ['gauge.tick-looks', gOnly({ axisTick: { show: true, lineStyle: { color: '#00f', width: 2, type: 'dotted', dashOffset: 1,
      cap: 'square', opacity: 0.6, shadowBlur: 2, shadowColor: '#f00' } } }), 'line', null, LK],
    ['gauge.tick-str', gOnly({ axisTick: { show: true, splitNumber: 2, lineStyle: { color: '#00f', width: '2', type: 'dashed',
      dashOffset: '1', miterLimit: '3' } } }), 'line', null, LK],
    ['gauge.pointer-looks', gOnly({ pointer: { show: true, itemStyle: { opacity: 0.8, shadowBlur: 2, shadowColor: '#000' } },
      itemStyle: { color: '#0f0', opacity: 0.5 } }), 'pointer', null, LK],
    ['gauge.pointer-item-opacity', gOnly({ pointer: { show: true }, itemStyle: { color: '#0f0' },
      data: [{ value: 40, itemStyle: { opacity: 0.3 } }, { value: 70, pointer: { itemStyle: { opacity: 0.6 } } }] }), 'pointer',
      null, LK],
    ['gauge.pointer-icon-opacity', gOnly({ pointer: { show: true, icon: 'emptyCircle', itemStyle: { opacity: 0.4 } },
      itemStyle: { color: '#0f0', borderWidth: 2 } }), 'pointer', null, LK],
    ['gauge.progress-looks', gOnly({ progress: { show: true, itemStyle: { opacity: 0.7 } }, itemStyle: { color: '#f00', opacity: 0.4 } }),
      'progress', null, LK],
    ['gauge.progress-item-opacity', gOnly({ progress: { show: true, overlap: false }, itemStyle: { color: '#f00' },
      data: [{ value: 40, itemStyle: { opacity: 0.3 } }, { value: 70, progress: { itemStyle: { opacity: 0.6 } } }] }), 'progress',
      null, LK],
    ['gauge.anchor-looks', gOnly({ anchor: { show: true, size: 20, itemStyle: Object.assign({ color: '#f00', borderColor: '#000',
      borderWidth: 2, borderType: 'dashed', borderDashOffset: 1, borderCap: 'round', borderJoin: 'round', borderMiterLimit: 3,
      opacity: 0.5 }, SHD) } }), 'anchor', null, LK],
    ['gauge.anchor-rect', gOnly({ anchor: { show: true, icon: 'rect', size: 16, itemStyle: { color: '#ff0', borderColor: '#000',
      borderWidth: 3, borderType: [3, 1] } } }), 'anchor', null, LK],
    ['gauge.detail-box', gOnly({ detail: Object.assign({ show: true, backgroundColor: '#ff0', borderColor: '#000', borderWidth: 2,
      borderType: 'dashed', borderDashOffset: 3, borderRadius: 4, opacity: 0.5 }, SHD) }), 'box', null, LK],
    ['gauge.detail-border-only', gOnly({ detail: { show: true, borderColor: '#000', borderWidth: 2, borderType: 'dotted' } }), 'box',
      null, LK],
    ['gauge.title-box', gOnly({ title: Object.assign({ show: true, backgroundColor: '#ff0', borderColor: '#000', borderWidth: 1,
      borderType: [2, 2], opacity: 0.6 }, SHD), data: [{ value: 40, name: 'Speed' }] }), 'box', null, LK],
    ['gauge.title-words', gOnly({ title: { show: true, opacity: 0.4 }, data: [{ value: 40, name: 'Speed' }] }), 'words', null, LK],
    ['gauge.detail-words', gOnly({ detail: { show: true, opacity: 0.3 } }), 'words', null, LK],
    // ---- a bar's border width that is no finite number: getLineWidth's Math.min ----
    ['bar.w-infinity', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 'Infinity' }, data: [3, 5] }), '', null,
      { shapes: true, cHits: true }],
    ['bar.w-1e999', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: '1e999' }, data: [3, 5] }), '', null,
      { shapes: true }],
    ['bar.w-infinity-h', { animation: false, color: PAL, yAxis: { type: 'category', data: N }, xAxis: {},
      series: [{ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 'Infinity' }, data: [3, 5] }] }, '', null,
      { shapes: true, cHits: true }],
    ['bar.w-infinity-item', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 2 },
      data: [3, { value: 5, itemStyle: { borderWidth: 'Infinity' } }] }), '', null, { shapes: true, cHits: true }],
    ['bar.w-infinity-no-colour', cart({ type: 'bar', itemStyle: { borderWidth: 'Infinity' }, data: [3, 5] }), '', null,
      { shapes: true }],
    ['bar.w-huge', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 1000 }, data: [3, 5] }), '', null,
      { shapes: true }],
    ['bar.w-neg-infinity', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: '-Infinity' }, data: [3, 5] }), '',
      null, { shapes: true }],
    ['bar.w-neg', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: -2 }, data: [3, 5] }), '', null,
      { shapes: true }],
    ['polarbar.w-infinity', { animation: false, color: PAL, polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', itemStyle: { borderColor: '#000', borderWidth: 'Infinity' }, data: [3, 5, 2] }] },
      '', null, { shapes: true }],
  ];
}

function hex2(v) { return ('0' + Math.round(v).toString(16)).slice(-2); }
function colourOf(c) {
  if (c != null && typeof c === 'object') return 'grad';
  const p = echarts.color.parse(c);
  if (!p) return 'x:' + c;
  return '#' + hex2(p[0]) + hex2(p[1]) + hex2(p[2]) + hex2(p[3] * 255);
}
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  lineWidth = lineWidth || 1;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType]
        : Array.isArray(lineType) ? lineType : null;
}
// the part each path is: a radar item's symbols (its group's third child),
// a gauge's pointers (the items' graphic elements) and progress arcs
// (the view's _progressEls), a chord's ribbons (not its sectors)
function partsOf(chart, view) {
  const m = new Map();
  const model = chart.getModel().getSeriesByIndex(0);
  const data = model && model.getData();
  if (view.type === 'radar' && data) data.eachItemGraphicEl(g => g.childAt(2).eachChild(e => m.set(e, 'symbol')));
  if (view.type === 'gauge' && data) {
    data.each(i => { const e = data.getItemGraphicEl(i); if (e) m.set(e, 'pointer'); });
    (view._progressEls || []).forEach(e => e && m.set(e, 'progress'));
    // the axis line's bands: the view's own sectors / sausages
    view.group.traverse(e => { if ((e.type === 'sector' || e.type === 'sausage') && !m.has(e)) m.set(e, 'track'); });
    // R6-F: its split lines and ticks, its anchor (the one other path of its own)
    view.group.traverse(e => { if (e.type === 'line' && !m.has(e)) m.set(e, 'line'); });
    view.group.traverse(e => { if (e instanceof Path && !m.has(e)) m.set(e, 'anchor'); });
  }
  if (view.type === 'chord') view.group.traverse(e => { if (e instanceof Path && e.type !== 'sector') m.set(e, 'ribbon'); });
  return m;
}

const r2 = v => String(Math.round(v * 100) / 100);
const r4 = v => String(Math.round(v * 10000) / 10000);
function mod2pi(a) { a = a % (2 * Math.PI); if (a < 0) a += 2 * Math.PI; return a; }
function shapeOf(e) {
  // as the path takes them (PathProxy's data is numbers: a treemap's content
  // rect is at x: borderWidth as written, a string where one is)
  const s = {};
  Object.keys(e.shape).forEach(k => { s[k] = typeof e.shape[k] === 'string' ? Number(e.shape[k]) : e.shape[k]; });
  if (e.type === 'sector' || e.type === 'sausage') {
    const cw = s.clockwise !== false;
    const from = cw ? s.startAngle : s.endAngle;
    return [e.type, r2(s.cx), r2(s.cy), r2(Math.max(s.r0 || 0, 0)), r2(s.r), r4(mod2pi(from)),
      r4(Math.abs(s.endAngle - s.startAngle))].join('|');
  }
  if (e.type === 'circle') return ['circle', r2(s.cx), r2(s.cy), r2(s.r)].join('|');
  if (e.type === 'rect') {
    // in the canvas' frame (a treemap's rects sit in their nodes' groups),
    // the corner that is the least
    const m = e.transform || [1, 0, 0, 1, 0, 0];
    const x0 = m[0] * s.x + m[2] * s.y + m[4], y0 = m[1] * s.x + m[3] * s.y + m[5];
    const x1 = m[0] * (s.x + s.width) + m[2] * (s.y + s.height) + m[4];
    const y1 = m[1] * (s.x + s.width) + m[3] * (s.y + s.height) + m[5];
    return ['rect', r2(Math.min(x0, x1)), r2(Math.min(y0, y1)), r2(Math.abs(x1 - x0)), r2(Math.abs(y1 - y0))].join('|');
  }
  return e.type;
}
// zrender's line scale, the drawn one: sqrt|det| of the transform where the
// path is no strokeNoScale and the transform scales; else 1
function penScale(e) {
  const m = e.transform;
  if (e.style.strokeNoScale || !m) return 1;
  const d = Math.sqrt(Math.abs(m[0] * m[3] - m[2] * m[1]));
  return Math.abs(d - 1) > 1e-10 ? d : 1;
}
// points about a round-capped arc: inside each cap, beyond the sweep, and
// the middle of the ring
function capPoints(e) {
  const s = e.shape;
  const r0 = Math.max(s.r0 || 0, 0);
  const dr = (s.r - r0) / 2;
  const rc = r0 + dr;
  const sgn = s.clockwise !== false ? 1 : -1;
  const at = (a, rad) => [Math.round(s.cx + Math.cos(a) * rad), Math.round(s.cy + Math.sin(a) * rad)];
  const beyond = 0.6 * dr / rc;
  return [at(s.endAngle + sgn * beyond, rc), at(s.startAngle - sgn * beyond, rc),
    at((s.startAngle + s.endAngle) / 2, rc), at(s.endAngle + sgn * 1.5 * dr / rc, rc)];
}

// R6-F: a gauge's titles' and readings' children -- the background rect
// (box) and the lines of words (words) zrender's Text made
function textParts(view, part) {
  const out = [];
  if (view.type !== 'gauge') return out;
  (view._titleEls || []).concat(view._detailEls || []).forEach(t => {
    if (!t || !t.parent || t.ignore || t.invisible) return;
    (t.childrenRef ? t.childrenRef() : []).forEach(c => {
      if (part === 'box' && c instanceof Path) out.push(c);
      if (part === 'words' && c.type === 'tspan') out.push(c);
    });
  });
  return out;
}
function looksOf(e) {
  const s = e.style;
  const o = s.opacity == null ? 1 : s.opacity;
  const b = s.shadowBlur || 0, x = s.shadowOffsetX || 0, y = s.shadowOffsetY || 0;
  const cast = b > 0 || x !== 0 || y !== 0;
  return [String(o), String(b), String(x), String(y), cast ? colourOf(s.shadowColor) : ''].join('|');
}

function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
  let live = 0;
  for (let c = zr.animation._head; c; c = c.next) if (!c.loop) live++;
  must(live === 0, 'did not settle');
}

function run(id, option, part, action, more) {
  NOW = T_BASE;
  rngState = SEED;
  more = more || {};
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    if (more.at != null) {
      NOW = T_BASE + more.at;
      chart.getZr().animation.update();
      chart.getZr().storage.getDisplayList(true);
    }
    else settle(chart, T_BASE);
    if (action) {
      NOW = T_BASE + 10000;
      chart.dispatchAction(JSON.parse(JSON.stringify(action)));
      settle(chart, T_BASE + 10000);
    }
    const set = new Set();
    const shapes = [];
    const fills = new Set();
    const partEls = [];
    let n = 0;
    let seen = 0;
    let parts = new Map();
    const looks = new Set();
    (chart._chartsViews || []).forEach(v => { const pv = partsOf(chart, v); pv.forEach((p, e) => parts.set(e, p));
      const visit = e => {
      if (part === 'words') {
        seen++;
        looks.add(looksOf(e));
        return;
      }
      if (!(e instanceof Path) || e.ignore || e.invisible) return;
      if (part && part !== 'box' && pv.get(e) !== part) return;
      seen++;
      partEls.push(e);
      if (more.looks) looks.add(looksOf(e));
      if (more.shapes) shapes.push(shapeOf(e));
      if (more.fills && e.style.fill != null && e.style.fill !== 'none') fills.add(colourOf(e.style.fill));
      const s = e.style;
      if (!(s.lineWidth > 0) || s.stroke == null || s.stroke === 'none') return;
      n++;
      const ls = penScale(e);
      const dash = normalizeLineDash(s.lineDash, s.lineWidth);
      // setLineDash ignores a dash with an entry that is no finite number of nought or more
      const bad = dash && dash.some(v => !(isFinite(Number(v)) && Number(v) >= 0));
      const off = s.lineDashOffset == null ? 0 : s.lineDashOffset;
      if (ls === 1) {
        set.add([colourOf(s.stroke), R6F_IDS.has(id) ? String(Number(s.lineWidth)) : String(s.lineWidth), bad ? 'ignored' : dash ? dash.map(Number).join(',') : 'solid',
          String(Number(off)),
          [s.lineCap || 'butt', s.lineJoin || 'miter', String(s.miterLimit || 10)].join('/')].join('|'));
      }
      else {
        set.add([colourOf(s.stroke), r4(s.lineWidth * ls), bad ? 'ignored' : dash ? dash.map(v => r4(v * ls)).join(',') : 'solid',
          r4(off * ls), [s.lineCap || 'butt', s.lineJoin || 'miter', String(s.miterLimit || 10)].join('/')].join('|'));
      }
      };
      if (part === 'box' || part === 'words') textParts(v, part).forEach(visit);
      else v.group.traverse(visit);
    });
    const rec = { id, option, part, action: action || null, seen, n, pens: Array.from(set).sort() };
    if (more.at != null) rec.at = more.at;
    if (more.looks) rec.looks = Array.from(looks).sort();
    if (more.shapes) rec.shapes = shapes.sort();
    if (more.fills) rec.fills = Array.from(fills).sort();
    // the clip path of a line's group (createGridClipPath), x|y|w|h
    if (more.clip) {
      rec.clip = [];
      (chart._chartsViews || []).forEach(v => v.group.traverse(e => {
        const c = e.getClipPath && e.getClipPath();
        if (c && c.shape) rec.clip.push(['rect', r2(+c.shape.x), r2(+c.shape.y), r2(+c.shape.width), r2(+c.shape.height)].join('|'));
      }));
    }
    // R6-F: at each rect's centre and a pixel either side of it, in the canvas' frame
    if (more.cHits) {
      const handler = chart.getZr().handler;
      rec.cHits = [];
      partEls.forEach(e => { if (e.type === 'rect') {
        const b = shapeOf(e).split('|').map(Number);
        const cx = Math.round(b[1] + b[3] / 2), cy = Math.round(b[2] + b[4] / 2);
        [[cx, cy], [cx - 1, cy], [cx + 1, cy]].forEach(q => {
          const h = handler.findHover(q[0], q[1]).target;
          rec.cHits.push([q[0], q[1], h ? (h === e ? 'bar' : 'other') : '-']);
        });
      } });
    }
    if (more.hits) {
      const handler = chart.getZr().handler;
      rec.hits = [];
      partEls.forEach(e => { if (e.type === 'sausage') capPoints(e).forEach(p => {
        const h = handler.findHover(p[0], p[1]).target;
        let what = '-';
        if (h) what = parts.get(h) || '';
        rec.hits.push([p[0], p[1], what]);
      }); });
    }
    return rec;
  }
  finally {
    chart.dispose();
  }
}

// the R6-F cases: their pens' widths as Number has them
let R6F_IDS = new Set();
function generate() {
  const all = cases();
  R6F_IDS = new Set(all.slice(all.findIndex(c => c[0] === 'gauge.track-opacity')).map(c => c[0]));
  const charts = all.map(([id, o, part, act, more]) => run(id, o, part, act, more));
  const by = id => charts.find(c => c.id === id);
  const pens = id => by(id).pens.join(' ');
  // guards: what upstream does that the port did not
  must(by('radar.rest').seen === 3 && by('radar.rest').n === 0, 'radar.rest: ' + by('radar.rest').seen + ' ' + pens('radar.rest'));
  must(pens('radar.border') === '#000000ff|3|12,6|2|butt/miter/10', 'radar.border: ' + pens('radar.border'));
  must(pens('radar.width-only') === '#ff0000ff|1|solid|0|butt/miter/10', 'radar.width-only: ' + pens('radar.width-only'));
  must(pens('radar.auto') === '#5470c6ff|2|solid|0|butt/miter/10', 'radar.auto: ' + pens('radar.auto'));
  // setColor: an empty symbol's stroke is the colour at 2 -- the border's dash stays
  must(pens('radar.empty') === '#5470c6ff|2|8,4|2|butt/miter/10', 'radar.empty: ' + pens('radar.empty'));
  must(pens('radar.line') === '#5470c6ff|3|12,6|2|butt/miter/10', 'radar.line: ' + pens('radar.line'));
  must(pens('radar.emphasis') === '#0000ffff|6|solid|2|butt/miter/10', 'radar.emphasis: ' + pens('radar.emphasis'));
  must(pens('gauge.border') === '#000000ff|3|12,6|2|butt/miter/10', 'gauge.border: ' + pens('gauge.border'));
  must(pens('gauge.pointer') === '#ff0000ff|1|solid|2|butt/miter/10', 'gauge.pointer: ' + pens('gauge.pointer'));
  must(pens('gauge.progress') === '#000000ff|4|16,8|2|butt/miter/10', 'gauge.progress: ' + pens('gauge.progress'));
  must(pens('chord.colour') === '#000000ff|2|8,4|1|butt/miter/10', 'chord.colour: ' + pens('chord.colour'));
  must(pens('chord.width') === 'x:source|2|solid|0|butt/miter/10', 'chord.width: ' + pens('chord.width'));
  must(pens('chord.emphasis') === '#ff0000ff|5|5|0|butt/miter/10', 'chord.emphasis: ' + pens('chord.emphasis'));
  must(by('radar.select').seen > 0 && by('radar.blur').seen > 0, 'states seen');
  // R6-E: a round-capped arc is one Sausage, stroked whole; a hover on its round end finds it
  must(by('gauge.round').shapes.join(' ') === 'sausage|200|150|98.5|112.5|2.3562|1.885', 'gauge.round: ' + by('gauge.round').shapes);
  must(pens('gauge.round') === '#000000ff|3|solid|0|butt/miter/10' && by('gauge.round').hits[0][2] === 'progress'
    && by('gauge.round').hits[3][2] === '-', 'gauge.round hits: ' + JSON.stringify(by('gauge.round').hits));
  must(by('gauge.round-track').shapes[0].indexOf('sausage|') === 0, 'gauge.round-track');
  // a numeric string is its number; a word, '' and '0' stroke nothing; a word makes a bar's layout NaN
  must(pens('bar.str') === '#000000ff|3|12,6|2|butt/miter/4', 'bar.str: ' + pens('bar.str'));
  must(by('bar.w"abc"').seen === 0 && by('bar.w""').n === 0 && by('line.w""').n === 0 && by('line.w"0"').n === 0, 'width words');
  must(pens('bar.miter-empty') === '#000000ff|2|4,2|0|butt/miter/10', 'bar.miter-empty: ' + pens('bar.miter-empty'));
  // a pictorial glyph: no setColor (an empty one filled in the colour), its pen in the glyph's frame
  must(by('pict.empty').n === 0 && by('pict.empty').fills.includes('#5470c6ff'), 'pict.empty: ' + by('pict.empty').fills);
  must(pens('pict.empty-size') === '#000000ff|2|1,0.5|0.5|butt/miter/10', 'pict.empty-size: ' + pens('pict.empty-size'));
  // a line written at nought: its clip is not grown (lineStyle.width || 0); the default 2 grows it by 1 a side
  must(by('line.w0-clip').clip[0] !== by('line.clip').clip[0], 'line clips: ' + by('line.w0-clip').clip + ' ' + by('line.clip').clip);
  // R6-F: a gauge's own parts take their style blocks' opacity, dash and ends; a reading's plate with a
  // fill (its default rgba(0,0,0,0) is one) strokes first at twice the width
  must(by('gauge.track-opacity').looks.join(' ') === '0.5|0|0|0|', 'gauge.track-opacity: ' + by('gauge.track-opacity').looks);
  must(pens('gauge.split-looks') === '#ff0000ff|3|12,6|2|round/bevel/5', 'gauge.split-looks: ' + pens('gauge.split-looks'));
  must(pens('gauge.detail-border-only') === '#000000ff|4|4|0|butt/miter/10', 'gauge.detail-border-only: '
    + pens('gauge.detail-border-only'));
  // an infinite border takes all of a bar's width (Math.min), its bounding rect NaN: never hit; a negative one grows it
  must(by('bar.w-infinity').shapes.every(s => s.split('|')[3] === '0') && by('bar.w-infinity').cHits.every(h => h[2] === '-'),
    'bar.w-infinity: ' + by('bar.w-infinity').shapes + ' ' + JSON.stringify(by('bar.w-infinity').cHits));
  must(by('bar.w-neg').shapes.join(' ') === 'rect|174.5|65|71|155 rect|74.5|126|71|94', 'bar.w-neg: ' + by('bar.w-neg').shapes);
  // R6-E: a bar whose border width is a word: getLineWidth's Math.min is NaN, the layout NaN -- no bar
  // R6-F: and one whose border width is -Infinity: its layout's x is -Infinity
  const NO_PATH = ['bar.w"abc"', 'bar.w-neg-infinity'];
  must(charts.every(c => c.seen > 0 || NO_PATH.includes(c.id)), 'a case has no path: '
    + charts.filter(c => c.seen === 0 && !NO_PATH.includes(c.id)).map(c => c.id));
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R6-D: each case settled (an action, where one, at T1 and settled), `pens` = the sorted set of stroke|width|dash|offset|ends '
      + 'of every stroked path under the series views (lineWidth > 0, a stroke not null nor none) -- of the part `part` names where '
      + 'one is (symbol: a radar item\'s symbols; pointer / progress: a gauge\'s; ribbon: a chord\'s links) -- the stroke #rrggbbaa '
      + '(color.parse), grad a gradient, x:<word> a word that does not parse; the dash normalizeLineDash\'d against the width (solid '
      + 'none, ignored one setLineDash does not take); the offset 0 where none; the ends cap/join/miterLimit, butt/miter/10 where none. `seen` the paths of that part, `n` the stroked ones. '
      + 'R6-E: a pen whose path scales with it (no strokeNoScale, a scaling transform: a pictorial glyph) as drawn, its width, dash and '
      + 'offset times sqrt|det| to four places; the offset as the canvas takes it (Number); part track: the bands of a gauge axis line; '
      + '`shapes` each path of the part as type|cx|cy|r0|r|clockwise start|sweep (sector, sausage), circle|cx|cy|r, rect|x|y|w|h '
      + '(canvas frame); `fills` the fills of the part; `hits` [x, y, the part findHover finds there, empty another path, - none]; `at`: '
      + 'sampled at T0 + at, animating; `clip` the clip rects of the view (a line group, createGridClipPath).', W, H, charts };
}

let j1, j2;
try {
  j1 = JSON.stringify(generate(), null, 1) + '\n';
  j2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (j1 !== j2) { console.log('FAILED: two generations differ'); process.exit(1); }
fs.writeFileSync(OUT, j1);
console.log('wrote', OUT, j1.length, 'bytes');
process.exit(0);
