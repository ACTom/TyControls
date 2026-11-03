// Round 7 R7-U: THE STYLES WRITTEN AT THE OPTION ROOT. Every series and
// component model is made with the GlobalModel as its parent model
// (GlobalModel._mergeOption: new ComponentModelClass(option, this, this)),
// and Model.getModel(path) builds its child with
// parentModel.getModel(resolveParentPath(path)) under it -- so a read of
// `itemStyle`, `lineStyle` or `areaStyle` through getModel / get(path) /
// getShallow climbs to the root's block for every key the series' option
// (its type's defaultOption merged under it) leaves null or out. What climbs
// and what does not is the reader's:
//   - the series' visual style (visual/style.ts seriesStyleTask) reads its
//     block with makeStyleMapper(..., ignoreParent = true): the root's colour,
//     opacity, border, shadow never reach the visual -- nor the legend, the
//     tooltip marker or the labels that inherit from it;
//   - the views read with the parent: LineView's polyline (getLineStyle of
//     the series' lineStyle: colour, opacity, shadow, cap, join...), its area
//     (getAreaStyle where the series has an areaStyle), a bar's borderRadius
//     and getLineWidth (borderColor / borderWidth inset the rect), a heatmap's,
//     a pie's and a sunburst's corners, a funnel's opacity, a radar's polyline,
//     a graph's and a sankey's edges, a tree's nodes and edges, a treemap's
//     and a sunburst's and a sankey's node style (getItemStyle on the item
//     model), the markers' items (their models' parent is the master marker
//     component, its parent the GlobalModel);
//   - a key the type's defaultOption holds is the series' own and wins.
//
// The same climb takes the root's scalars a series reads with get() where
// its type's defaults hold none (a pie's roseType, a funnel's min / max, a
// tree's, a graph's, a sankey's center, a pictorial bar's symbolSize); and
// the large draws read the series' getModel (LargeLineDraw, LargeSymbolDraw,
// a large candlestick), a large bar its visual style; and a legend, a
// timeline and a calendar have the root's blocks under their own.
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false,
// animation off): each case settled (an action, where one, dispatched and
// settled); then every path under the series'
// views (part '') or under the marker components' views (part 'marker') or
// of the whole display list (part 'all': a timeline, a calendar -- the pens
// then without their colours, which are the defaults', the theme's),
// recorded as series-borders.js records them -- `pens` the sorted set of
// stroke|width|dash|offset|cap/join/miter of every stroked path, `seen` the
// paths, `n` the stroked ones; with `looks` the set of
// opacity|shadowBlur|shadowOffsetX|shadowOffsetY|shadowColor; with `fills`
// the set of the fills; with `shapes` each rect and sector as series-borders
// writes them, a rect's corners (RectShape.r expanded as zrender's roundRect
// does: a number all four, [a] all four, [a, b] a b a b, [a, b, c] a b c b)
// and a sector's (normalizeCornerRadius: a number all four, [a] a a 0 0,
// [a, b] a a b b, [a, b, c] a b c c) appended as `|r:` four numbers where
// one is above nought; with `curves` each Line / BezierCurve shape as
// x1|y1|x2|y2|cpx1|cpy1 (two places, the control point '-' where none);
// with `polys` each polygon's points; with `boxes` each symbol path's box
// (no pen). `defaults` the leaves each type's defaultOption holds under the
// three blocks and the scalars (a component's: the blocks).
//
// Run: node tools/advchart-oracle/root-styles.js -> tests/fixtures/advchart-root-styles.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-root-styles.json');
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
const N = ['A', 'B', 'C'];
// the root's blocks: every key a distinct value, so a miss names itself
const RI = { color: '#ff0000', borderColor: '#00aa00', borderWidth: 3, opacity: 0.5, shadowBlur: 4, shadowColor: '#0000ff',
  shadowOffsetX: 2, borderType: 'dashed', borderDashOffset: 1, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4,
  borderRadius: 6 };
const RL = { color: '#aa00aa', width: 5, opacity: 0.6, type: 'dotted', dashOffset: 2, cap: 'square', join: 'round', miterLimit: 3,
  shadowBlur: 3, shadowColor: '#00ffff', shadowOffsetY: 2, curveness: 0.3 };
const RA = { color: '#ffaa00', opacity: 0.4, shadowBlur: 2, shadowColor: '#333333' };
const RS = { itemStyle: RI, lineStyle: RL, areaStyle: RA };
// what a series writes of its own in the `.own` cases: a few keys of each
const OI = { color: '#112233', opacity: 0.9, borderWidth: 1, borderRadius: 2, shadowBlur: 1 };
const OL = { color: '#334455', opacity: 0.8, type: 'solid', curveness: 0.1 };
const OA = { opacity: 0.7 };
const OS = { itemStyle: OI, lineStyle: OL };

const root = (o, extra) => Object.assign({ animation: false, color: PAL }, RS, extra || {}, o);
const cart = (s, extra) => root({ xAxis: { type: 'category', data: N }, yAxis: {}, series: [s] }, extra);
const solo = (s, extra) => root({ series: [s] }, extra);
const IND = [{ name: 'p', max: 10 }, { name: 'q', max: 10 }, { name: 'r', max: 10 }];
const radar = (s, extra) => root({ radar: { indicator: IND }, series: [Object.assign({ type: 'radar', data: [{ value: [3, 5, 2] }] }, s)] }, extra);
// the defaults that are theme tokens written out: the port's skin stands in for the theme
const tree = { type: 'tree', itemStyle: { color: '#b0c4de' }, lineStyle: { color: '#cfd2d7' }, data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] };
const graph = { type: 'graph', layout: 'none', lineStyle: { color: '#86878c' }, data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 10, y: 10 }, { name: 'c', x: 20, y: 0 }],
  links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] };
const sankey = { type: 'sankey', lineStyle: { color: '#86878c' }, data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
  links: [{ source: 'a', target: 'b', value: 3 }, { source: 'a', target: 'c', value: 1 }] };
const sun = { type: 'sunburst', data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }, { name: 'c', value: 2 }] };
const tmap = { type: 'treemap', breadcrumb: { show: false }, data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }] };
const chordS = { type: 'chord', data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] };
const linesS = { type: 'lines', coordinateSystem: 'cartesian2d', data: [{ coords: [[0, 0], [5, 5]] }, { coords: [[1, 4], [4, 1]] }] };
const heat = (s, extra) => root({ xAxis: { type: 'category', data: N }, yAxis: { type: 'category', data: N },
  visualMap: { show: false, min: 0, max: 5, inRange: { color: ['#ffffff', '#000080'] } }, series: [Object.assign({ type: 'heatmap', data: [[0, 0, 1], [1, 1, 3]] }, s)] }, extra);
const own = s => Object.assign({}, OS, s);
// no style blocks at the root: the scalar cases
const bare = o => Object.assign({ animation: false, color: PAL }, o);
const ALL = { looks: true, fills: true, shapes: true };
const LF = { looks: true, fills: true };
const SH = { shapes: true, polys: true, boxes: true };
const CV = { curves: true, shapes: true };
const BX = { boxes: true };
const NC = { looks: true, nocolour: true };
// an axis pointer shown by updateAxisPointer on a scatter: the tooltip's axis pointer (its line) and nothing of the content
const PTR = { tooltip: { trigger: 'axis', showContent: false, renderMode: 'richText', axisPointer: { label: { show: false } } },
  xAxis: { type: 'category', data: N, axisLabel: { show: false }, axisTick: { show: false } }, yAxis: { show: false },
  series: [{ type: 'scatter', symbolSize: 0, data: [3, 5, 2] }] };
const PT = { looks: true, nocolour: true, action: { type: 'updateAxisPointer', currTrigger: 'mousemove', x: 200, y: 150 } };
const CS = { color: '#eb5454', color0: '#47b262', borderColor: '#eb5454', borderColor0: '#47b262' };
// a gauge with its pointer and its progress arc and nothing else
const GH = { axisLine: { show: false }, splitLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false },
  anchor: { show: false }, title: { show: false }, detail: { show: false }, progress: { show: true } };

// [id, option, part ('' the series' views, 'marker' the marker components'), more]
function cases() {
  return [
    // ---- a line: its polyline and its area read the root (LineView), its symbols the visual ----
    ['line.root', cart({ type: 'line', symbol: 'circle', data: [3, 5, 2] }), '', ALL],
    ['line.own', cart(own({ type: 'line', symbol: 'circle', data: [3, 5, 2] })), '', ALL],
    ['line.area', cart({ type: 'line', symbol: 'none', areaStyle: {}, data: [3, 5, 2] }), '', ALL],
    ['line.area-own', cart({ type: 'line', symbol: 'none', areaStyle: OA, data: [3, 5, 2] }), '', ALL],
    ['line.area-null', cart({ type: 'line', symbol: 'none', areaStyle: null, data: [3, 5, 2] }), '', ALL],
    ['line.ls-null', cart({ type: 'line', symbol: 'none', lineStyle: null, data: [3, 5, 2] }), '', ALL],
    ['line.item', cart({ type: 'line', symbol: 'circle', data: [3, { value: 5, itemStyle: { borderWidth: 2 } }, 2] }), '', ALL],
    // ---- a bar: its corners and getLineWidth read the root; its fill and pen the visual ----
    ['bar.root', cart({ type: 'bar', data: [3, 5, 2] }), '', ALL],
    ['bar.own', cart(own({ type: 'bar', data: [3, 5, 2] })), '', ALL],
    // getLineWidth: the item's own width with the root's colour
    ['bar.item', cart({ type: 'bar', data: [3, { value: 5, itemStyle: { borderWidth: 1 } }, 2] }), '', ALL],
    ['bar.polar', root({ polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [3, 5, 2] }] }), '', ALL],
    ['bar.horizontal', root({ yAxis: { type: 'category', data: N }, xAxis: {}, series: [{ type: 'bar', data: [3, 5, 2] }] }), '', ALL],
    // ---- the rest of the cartesian ones ----
    ['scatter.root', cart({ type: 'scatter', data: [3, 5, 2] }), '', ALL],
    ['pictorial.root', cart({ type: 'pictorialBar', symbol: 'rect', data: [3, 5, 2] }), '', ALL],
    ['boxplot.root', cart({ type: 'boxplot', data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }), '', ALL],
    ['candle.root', cart({ type: 'candlestick', itemStyle: CS, data: [[2, 4, 1, 5], [3, 2, 1, 4]] }), '', LF],
    ['heatmap.root', heat({}), '', ALL],
    ['heatmap.own', heat({ itemStyle: { borderRadius: 2 } }), '', ALL],
    ['lines.root', root({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [linesS] }), '', Object.assign({ curves: true }, ALL)],
    ['lines.own', root({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [own(linesS)] }), '', Object.assign({ curves: true }, ALL)],
    // ---- the rest ----
    ['pie.root', solo({ type: 'pie', label: { show: false }, data: [3, 5, 2] }), '', ALL],
    ['pie.own', solo(own({ type: 'pie', label: { show: false }, data: [3, 5, 2] })), '', ALL],
    ['funnel.root', solo({ type: 'funnel', label: { show: false }, data: [3, 5, 2] }), '', ALL],
    ['funnel.own', solo(own({ type: 'funnel', label: { show: false }, data: [3, 5, 2] })), '', ALL],
    ['gauge.root', solo(Object.assign({ type: 'gauge', data: [{ value: 40 }] }, GH)), '', ALL],
    ['radar.root', radar({}), '', ALL],
    ['radar.own', radar(OS), '', ALL],
    ['radar.area', radar({ areaStyle: {} }), '', ALL],
    ['graph.root', solo(graph), '', Object.assign({ curves: true }, ALL)],
    ['graph.own', solo(own(graph)), '', Object.assign({ curves: true }, ALL)],
    // a node in a category: categoryVisual's getItemStyle of the category climbs through the series' to the root's
    ['graph.category', solo(Object.assign({}, graph, { categories: [{ name: 'k' }],
      data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 10 }, { name: 'c', x: 20, y: 0, category: 0 }] })), '', ALL],
    ['tree.root', solo(tree), '', Object.assign({ curves: true }, ALL)],
    ['tree.own', solo(own(tree)), '', Object.assign({ curves: true }, ALL)],
    ['treemap.root', solo(tmap), '', ALL],
    ['treemap.own', solo(own(tmap)), '', ALL],
    ['sunburst.root', solo(sun), '', ALL],
    ['sunburst.own', solo(own(sun)), '', ALL],
    ['sankey.root', solo(sankey), '', ALL],
    ['sankey.own', solo(own(sankey)), '', ALL],
    ['parallel.root', root({ parallelAxis: [{ dim: 0 }, { dim: 1 }], series: [{ type: 'parallel', data: [[1, 2], [3, 4]] }] }), '', ALL],
    ['river.root', root({ singleAxis: { type: 'value' }, series: [{ type: 'themeRiver', label: { show: false },
      data: [[0, 10, 'A'], [1, 15, 'A'], [0, 5, 'B'], [1, 8, 'B']] }] }), '', ALL],
    ['chord.root', solo(Object.assign({ label: { show: false } }, chordS)), '', ALL],
    ['chord.own', solo(own(Object.assign({ label: { show: false } }, chordS))), '', ALL],
    // ---- large: LargeSymbolDraw's and LargeLineDraw's getModel(...).getItemStyle / getLineStyle climb
    // (the colour the visual's), a large bar draws its visual style ----
    ['scatter.large', cart({ type: 'scatter', large: true, largeThreshold: 1, data: [3, 5, 2] }), '', LF],
    ['bar.large', cart({ type: 'bar', large: true, largeThreshold: 1, data: [3, 5, 2] }), '', LF],
    ['lines.large', root({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [Object.assign({ large: true, largeThreshold: 1 }, linesS)] }), '', LF],
    ['candle.large', cart({ type: 'candlestick', large: true, largeThreshold: 1, itemStyle: CS, data: [[2, 4, 1, 5], [3, 2, 1, 4]] }), '', LF],
    // ---- the markers: entry -> series' marker -> the master marker component -> the root ----
    ['marker.root', cart({ type: 'scatter', data: [3, 5, 2], markPoint: { label: { show: false }, data: [{ type: 'max' }] },
      markLine: { label: { show: false }, symbol: 'none', data: [{ type: 'average' }] },
      markArea: { label: { show: false }, data: [[{ xAxis: 'A' }, { xAxis: 'B' }]] } }), 'marker', ALL],
    // ---- the root's scalars a series reads with get() and its type holds no default for:
    // a pie's roseType, a funnel's min / max, a tree's / graph's / sankey's center, a pictorial bar's symbolSize ----
    ['pie.rose', bare({ roseType: 'radius', series: [{ type: 'pie', label: { show: false }, data: [3, 5, 2] }] }), '', SH],
    ['pie.rose-own', bare({ roseType: 'radius', series: [{ type: 'pie', roseType: false, label: { show: false }, data: [3, 5, 2] }] }), '', SH],
    ['funnel.minmax', bare({ min: 1, max: 10, series: [{ type: 'funnel', label: { show: false }, data: [3, 5, 2] }] }), '', SH],
    ['funnel.minmax-own', bare({ min: 1, max: 10, series: [{ type: 'funnel', max: 5, label: { show: false }, data: [3, 5, 2] }] }), '', SH],
    ['tree.center', bare({ center: [100, 100], series: [tree] }), '', CV],
    ['graph.center', bare({ center: [5, 5], series: [graph] }), '', CV],
    ['graph.center-own', bare({ center: [5, 5], series: [Object.assign({ center: [15, 5] }, graph)] }), '', CV],
    ['sankey.center', bare({ center: [100, 100], series: [sankey] }), '', { shapes: true }],
    ['pictorial.size', bare({ symbolSize: 20, xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'pictorialBar', symbol: 'circle', data: [3, 5, 2] }] }), '', BX],
    ['scatter.size', bare({ symbolSize: 20, xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'scatter', data: [3, 5, 2] }] }), '', BX],
    // ---- the components whose own blocks climb to the root's: a timeline's, a calendar's, the axis
    // pointers' (their models' parent the global axisPointer component's, its the GlobalModel). Every path
    // of the chart (part all), the pens without their colours: the colours are the defaults' (the theme's) ----
    ['timeline.root', root({ timeline: { data: ['2001', '2002', '2003'], label: { show: false } } }), 'all', NC],
    ['timeline.bare', bare({ timeline: { data: ['2001', '2002', '2003'], label: { show: false } } }), 'all', NC],
    ['calendar.root', root({ calendar: { range: '2017-01', dayLabel: { show: false }, monthLabel: { show: false },
      yearLabel: { show: false }, splitLine: { show: false } } }), 'all', NC],
    ['calendar.bare', bare({ calendar: { range: '2017-01', dayLabel: { show: false }, monthLabel: { show: false },
      yearLabel: { show: false }, splitLine: { show: false } } }), 'all', NC],
    // the master marker component (the root's markPoint / markLine / markArea) stands before the root's blocks
    ['marker.master', Object.assign(cart({ type: 'scatter', data: [3, 5, 2], markPoint: { label: { show: false }, data: [{ type: 'max' }] },
      markLine: { label: { show: false }, symbol: 'none', data: [{ type: 'average' }] },
      markArea: { label: { show: false }, data: [[{ xAxis: 'A' }, { xAxis: 'B' }]] } }),
      { markPoint: { itemStyle: { color: '#123456', shadowBlur: 1 } }, markLine: { lineStyle: { color: '#654321', cap: 'butt' } },
        markArea: { itemStyle: { opacity: 0.25 } } }), 'marker', ALL],
    ['marker.own', cart({ type: 'scatter', data: [3, 5, 2],
      markPoint: { label: { show: false }, itemStyle: OI, data: [{ type: 'max' }] },
      markLine: { label: { show: false }, symbol: 'none', lineStyle: OL, data: [{ type: 'average' }] },
      markArea: { label: { show: false }, itemStyle: OI, data: [[{ xAxis: 'A' }, { xAxis: 'B' }]] } }), 'marker', ALL],
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
const r2 = v => String(Math.round(v * 100) / 100);
const r4 = v => String(Math.round(v * 10000) / 10000);
function mod2pi(a) { a = a % (2 * Math.PI); if (a < 0) a += 2 * Math.PI; return a; }
// zrender's roundRect corners (helper/roundRect.ts) before the clamp
function rectCorners(r) {
  if (typeof r === 'number') return [r, r, r, r];
  if (!Array.isArray(r)) return [0, 0, 0, 0];
  if (r.length === 1) return [r[0], r[0], r[0], r[0]];
  if (r.length === 2) return [r[0], r[1], r[0], r[1]];
  if (r.length === 3) return [r[0], r[1], r[2], r[1]];
  return [r[0], r[1], r[2], r[3]];
}
// zrender's sector normalizeCornerRadius
function sectorCorners(cr) {
  if (!Array.isArray(cr)) { const v = +cr || 0; return [v, v, v, v]; }
  if (cr.length === 1) return [cr[0], cr[0], 0, 0];
  if (cr.length === 2) return [cr[0], cr[0], cr[1], cr[1]];
  if (cr.length === 3) return cr.concat(cr[2]);
  return cr.slice(0, 4);
}
function shapeOf(e) {
  const s = {};
  Object.keys(e.shape).forEach(k => { s[k] = typeof e.shape[k] === 'string' ? Number(e.shape[k]) : e.shape[k]; });
  if (e.type === 'sector' || e.type === 'sausage') {
    const cw = s.clockwise !== false;
    const from = cw ? s.startAngle : s.endAngle;
    let out = [e.type, r2(s.cx), r2(s.cy), r2(Math.max(s.r0 || 0, 0)), r2(s.r), r4(mod2pi(from)),
      r4(Math.abs(s.endAngle - s.startAngle))].join('|');
    const c = sectorCorners(e.shape.cornerRadius);
    if (c.some(v => v > 0)) out += '|r:' + c.map(r2).join(',');
    return out;
  }
  if (e.type === 'rect') {
    const m = e.transform || [1, 0, 0, 1, 0, 0];
    const x0 = m[0] * s.x + m[2] * s.y + m[4], y0 = m[1] * s.x + m[3] * s.y + m[5];
    const x1 = m[0] * (s.x + s.width) + m[2] * (s.y + s.height) + m[4];
    const y1 = m[1] * (s.x + s.width) + m[3] * (s.y + s.height) + m[5];
    let out = ['rect', r2(Math.min(x0, x1)), r2(Math.min(y0, y1)), r2(Math.abs(x1 - x0)), r2(Math.abs(y1 - y0))].join('|');
    const c = rectCorners(e.shape.r);
    if (c.some(v => v > 0)) out += '|r:' + c.map(r2).join(',');
    return out;
  }
  return '';
}
// a polygon's points, canvas frame, two places
function polyOf(e) {
  if (e.type !== 'polygon' || !e.shape.points) return '';
  const m = e.transform || [1, 0, 0, 1, 0, 0];
  return e.shape.points.map(p => r2(m[0] * p[0] + m[2] * p[1] + m[4]) + ',' + r2(m[1] * p[0] + m[3] * p[1] + m[5])).join(';');
}
// a symbol path's box (no pen), canvas frame, two places
function boxOf(e) {
  if (e.type !== 'path' || !e.shape || e.shape.symbolType == null) return '';
  const s = e.shape;
  const m = e.transform || [1, 0, 0, 1, 0, 0];
  const xs = [s.x, s.x + s.width].map(x => [m[0] * x + m[2] * s.y + m[4], m[0] * x + m[2] * (s.y + s.height) + m[4]]).flat();
  const ys = [s.y, s.y + s.height].map(y => [m[1] * s.x + m[3] * y + m[5], m[1] * (s.x + s.width) + m[3] * y + m[5]]).flat();
  return [r2(Math.min(...xs)), r2(Math.min(...ys)), r2(Math.max(...xs) - Math.min(...xs)), r2(Math.max(...ys) - Math.min(...ys))].join('|');
}
function curveOf(e) {
  const s = e.shape;
  if (!('x1' in s) || !('x2' in s)) return '';
  const m = e.transform || [1, 0, 0, 1, 0, 0];
  const at = (x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const p1 = at(s.x1, s.y1), p2 = at(s.x2, s.y2);
  // a straight line's control point is none (Line's cpx1 null, a BezierCurve's NaN)
  const cp = s.cpx1 == null || isNaN(s.cpx1) ? null : at(s.cpx1, s.cpy1);
  return [r2(p1[0]), r2(p1[1]), r2(p2[0]), r2(p2[1]), cp ? r2(cp[0]) : '-', cp ? r2(cp[1]) : '-'].join('|');
}
function penScale(e) {
  const m = e.transform;
  if (e.style.strokeNoScale || !m) return 1;
  const d = Math.sqrt(Math.abs(m[0] * m[3] - m[2] * m[1]));
  return Math.abs(d - 1) > 1e-10 ? d : 1;
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
const MARKERS = ['markPoint', 'markLine', 'markArea'];

function run(id, option, part, more) {
  NOW = T_BASE;
  rngState = SEED;
  more = more || {};
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    settle(chart, T_BASE);
    if (more.action) {
      NOW = T_BASE + 10000;
      chart.dispatchAction(JSON.parse(JSON.stringify(more.action)));
      settle(chart, T_BASE + 10000);
    }
    const pens = new Set();
    const looks = new Set();
    const fills = new Set();
    const shapes = [];
    const curves = [];
    const polys = [];
    const boxes = [];
    let seen = 0;
    let n = 0;
    const visit = e => {
      if (!(e instanceof Path) || e.ignore || e.invisible) return;
      seen++;
      if (more.looks) looks.add(looksOf(e));
      if (more.shapes) { const t = shapeOf(e); if (t) shapes.push(t); }
      if (more.curves) { const t = curveOf(e); if (t) curves.push(t); }
      if (more.polys) { const t = polyOf(e); if (t) polys.push(t); }
      if (more.boxes) { const t = boxOf(e); if (t) boxes.push(t); }
      if (more.fills && e.style.fill != null && e.style.fill !== 'none') fills.add(colourOf(e.style.fill));
      const s = e.style;
      if (!(s.lineWidth > 0) || s.stroke == null || s.stroke === 'none') return;
      n++;
      const ls = penScale(e);
      const dash = normalizeLineDash(s.lineDash, s.lineWidth);
      const bad = dash && dash.some(v => !(isFinite(Number(v)) && Number(v) >= 0));
      const off = s.lineDashOffset == null ? 0 : s.lineDashOffset;
      const ends = [s.lineCap || 'butt', s.lineJoin || 'miter', String(s.miterLimit || 10)].join('/');
      if (more.nocolour) {
        pens.add([String(Number(s.lineWidth)), bad ? 'ignored' : dash ? dash.map(Number).join(',') : 'solid',
          String(Number(off)), ends].join('|'));
      }
      else if (ls === 1) {
        pens.add([colourOf(s.stroke), String(Number(s.lineWidth)), bad ? 'ignored' : dash ? dash.map(Number).join(',') : 'solid',
          String(Number(off)), ends].join('|'));
      }
      else {
        pens.add([colourOf(s.stroke), r4(s.lineWidth * ls), bad ? 'ignored' : dash ? dash.map(v => r4(v * ls)).join(',') : 'solid',
          r4(off * ls), ends].join('|'));
      }
    };
    if (part === 'marker') {
      (chart._componentsViews || []).forEach(v => { if (v && MARKERS.includes(v.type)) v.group.traverse(visit); });
    }
    else if (part === 'all') chart.getZr().storage.getDisplayList(true).forEach(visit);
    else (chart._chartsViews || []).forEach(v => v.group.traverse(visit));
    const rec = { id, option, part, seen, n, pens: Array.from(pens).sort() };
    if (more.action) rec.action = more.action;
    if (more.looks) rec.looks = Array.from(looks).sort();
    if (more.fills) rec.fills = Array.from(fills).sort();
    if (more.shapes) rec.shapes = shapes.sort();
    if (more.curves) rec.curves = curves.sort();
    if (more.polys) rec.polys = polys.sort();
    if (more.boxes) rec.boxes = boxes.sort();
    return rec;
  }
  finally {
    chart.dispose();
  }
}

// the leaves each type's defaultOption holds under the three blocks: where
// the root's do not reach (the port's table must be this)
function defaultPaths() {
  const walk = (o, pre, out) => {
    for (const k of Object.keys(o)) {
      const v = o[k];
      const p = pre + '.' + k;
      if (v != null && typeof v === 'object' && !Array.isArray(v)) walk(v, p, out);
      else if (v != null) out.push(p);
    }
    return out;
  };
  const out = [];
  const seen = new Set();
  const add = (mains, prefix) => mains.forEach(main => {
    for (const C of echarts.ComponentModel.getClassesByMainType(main)) {
      // a component's subtypes (legend.plain / scroll, timeline.slider) are the main type's
      const t = prefix ? C.type.replace(prefix, '') : main;
      if (t.startsWith('__') || seen.has(t)) continue;
      seen.add(t);
      const d = C.defaultOption || {};
      // [the scalars a series' get() climbs for: its own and its type's only]
      for (const k of prefix ? ['itemStyle', 'lineStyle', 'areaStyle', 'symbolSize', 'roseType', 'center', 'min', 'max']
        : ['itemStyle', 'lineStyle', 'areaStyle']) {
        if (d[k] == null) continue;
        const ps = typeof d[k] === 'object' && !Array.isArray(d[k]) ? walk(d[k], k, []) : [k];
        for (const p of ps) out.push(t + ':' + p);
      }
    }
  });
  add(['series'], 'series.');
  add(['markPoint', 'markLine', 'markArea', 'legend', 'timeline', 'calendar', 'axisPointer', 'geo'], '');
  return out;
}

function generate() {
  const charts = cases().map(([id, o, part, more]) => run(id, o, part, more));
  const by = id => charts.find(c => c.id === id);
  const has = (id, k, v) => by(id)[k].includes(v);
  // guards: what the root does upstream
  // the line's polyline: the root's colour, opacity, cap, join, shadow; its width and type are LineSeries' own
  must(has('line.root', 'pens', '#aa00aaff|2|solid|2|square/round/3'), 'line.root pens: ' + by('line.root').pens);
  must(has('line.root', 'looks', '0.6|3|0|2|#00ffffff'), 'line.root looks: ' + by('line.root').looks);
  // its symbols: the visual -- none of the root's item keys
  must(has('line.root', 'fills', '#5470c6ff') && !has('line.root', 'fills', '#ff0000ff'), 'line.root fills: ' + by('line.root').fills);
  // the series' own keys win, key by key
  must(has('line.own', 'pens', '#334455ff|2|solid|2|square/round/3'), 'line.own pens: ' + by('line.own').pens);
  // the area: the root's colour and opacity where the series has an areaStyle
  must(has('line.area', 'fills', '#ffaa00ff') && has('line.area', 'looks', '0.4|2|0|0|#333333ff'), 'line.area: ' + JSON.stringify(by('line.area')));
  must(!has('line.area-null', 'fills', '#ffaa00ff'), 'line.area-null');
  // a bar: the visual's fill, no pen; the root's corners and its border inset the rect by its width
  must(!has('bar.root', 'fills', '#ff0000ff') && by('bar.root').n === 0, 'bar.root: ' + JSON.stringify(by('bar.root').fills));
  must(by('bar.root').shapes.every(s => s.endsWith('|r:6,6,6,6')), 'bar.root shapes: ' + by('bar.root').shapes);
  // a funnel: the root's opacity
  must(has('funnel.root', 'looks', '0.5|0|0|0|'), 'funnel.root looks: ' + by('funnel.root').looks);
  // a sunburst: its node style is getItemStyle on the node -- the root's colour
  must(has('sunburst.root', 'fills', '#ff0000ff'), 'sunburst.root fills: ' + by('sunburst.root').fills);
  // the markers: the root's colour on every marker
  must(has('marker.root', 'fills', '#ff0000ff'), 'marker.root fills: ' + by('marker.root').fills);
  must(charts.every(c => c.seen > 0), 'a case has no path: ' + charts.filter(c => c.seen === 0).map(c => c.id));
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-U: the root\'s itemStyle / lineStyle / areaStyle under the series and the markers. Each case settled; `pens` the sorted set '
      + 'of stroke|width|dash|offset|cap/join/miter of every stroked path under the series\' views (part \'\') or the marker components\' '
      + 'views (part marker), as series-borders.js; `seen` the paths, `n` the stroked ones; `looks` opacity|shadowBlur|shadowOffsetX|'
      + 'shadowOffsetY|shadowColor; `fills` the fills; `shapes` each rect and sector (canvas frame), its corners appended as |r:a,b,c,d '
      + 'where one is above nought (a rect\'s RectShape.r expanded as roundRect does, a sector\'s normalizeCornerRadius); `curves` each '
      + 'Line / BezierCurve as x1|y1|x2|y2|cpx1|cpy1. `defaults` the leaves each type\'s defaultOption holds under the three blocks.',
    W, H, defaults: defaultPaths(), charts };
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
