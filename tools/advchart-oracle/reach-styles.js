// Round 7 R7-X: WHAT REACHES THE AXIS POINTER'S LINE, THE COMPONENT BOXES, A
// CANDLESTICK AND A BAR'S CORNERS -- the styles R7-U (root-styles.js) left.
//
//  - The axis pointer: viewHelper.buildElStyle draws the pointer with
//    axisPointerModel.getModel(type + 'Style').getLineStyle() (a line:
//    colour, width, dash, its phase, cap, join, miterLimit, opacity, shadow)
//    or getAreaStyle() (a shadow band: its fill, opacity, shadow). The model
//    is axis.model.getModel('axisPointer', parent): the axis' own block key
//    by key, over -- for a tooltip axis -- the volatile model makeAxisPointerModel
//    builds from tooltip.axisPointer (its `lineStyle` cloned whole from the first
//    tooltip level that has one, or on the other arm of a cross its `crossStyle`),
//    over the global axisPointer component (its defaults merged in), over the
//    option root (GlobalModel). So the root's lineStyle reaches every key the
//    component's defaults leave (all but colour, width, type), and a root
//    crossStyle reaches nothing.
//  - The component boxes: listComponent.makeBackground (legend, toolbox) and
//    the title's Rect take getItemStyle(['color', 'opacity']) of the component
//    model -- its top-level keys, climbing to the root's top-level keys where
//    the component's defaults hold none: the shadow's four, borderType,
//    borderDashOffset, borderCap, borderJoin, borderMiterLimit, and the title's
//    borderRadius (legend and toolbox default it to 0). A visualMap's box is
//    fill, stroke and width alone. A continuous visualMap's itemWidth and
//    itemHeight default to null (resetItemSize climbs), every visualMap's
//    `text`; a legend's `icon` and `formatter`.
//  - A candlestick: candlestickVisual calls getItemStyle() on each item's
//    model: the TOP-LEVEL keys of the item, then the series, then the root
//    (borderWidth, opacity, the shadow's four, borderType ...), the fill and
//    stroke then overwritten by the item's itemStyle colours.
//  - A bar's corners: BarView reads itemModel.get(['itemStyle',
//    'borderRadius']) per item (a polar bar getSectorCornerRadius of the
//    item's itemStyle model), as the pie and the others do.
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false,
// animation off), recorded as root-styles.js records them -- `pens` the
// sorted set of stroke|width|dash|offset|cap/join/miter of every stroked
// path of the part, `looks` opacity|shadowBlur|shadowOffsetX|shadowOffsetY|
// shadowColor, `fills`, `shapes` (rects and sectors with their corners).
// The part: '' every path under the series' views; 'pointer' every path of
// the axes' pointer groups, each entry prefixed with its axis
// (`xAxis0|...`); 'title' / 'legend' / 'toolbox' / 'visualMap' the
// component's background rect. A case with `nocolour` writes its pens
// without the stroke colour (the defaults', the theme's). `texts` (where
// asked) the sorted texts of the part's component views, `icons` a
// legend's icon symbol types, `vm` a visualMap model's itemSize and text.
//
// Run: node tools/advchart-oracle/reach-styles.js -> tests/fixtures/advchart-reach-styles.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-reach-styles.json');
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
// root-styles.js' root blocks
const RI = { color: '#ff0000', borderColor: '#00aa00', borderWidth: 3, opacity: 0.5, shadowBlur: 4, shadowColor: '#0000ff',
  shadowOffsetX: 2, borderType: 'dashed', borderDashOffset: 1, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4,
  borderRadius: 6 };
const RL = { color: '#aa00aa', width: 5, opacity: 0.6, type: 'dotted', dashOffset: 2, cap: 'square', join: 'round', miterLimit: 3,
  shadowBlur: 3, shadowColor: '#00ffff', shadowOffsetY: 2, curveness: 0.3 };
const RA = { color: '#ffaa00', opacity: 0.4, shadowBlur: 2, shadowColor: '#333333' };
// a pointer's own pen: every key a distinct value
const PL = { color: '#123456', width: 2, type: 'dashed', dashOffset: 3, cap: 'round', join: 'bevel', miterLimit: 2,
  opacity: 0.7, shadowBlur: 5, shadowColor: '#ff00ff', shadowOffsetX: 1, shadowOffsetY: -2 };
const PS = { color: 'rgba(10, 20, 30, 0.5)', opacity: 0.8, shadowBlur: 6, shadowColor: '#00ff00', shadowOffsetX: 3, shadowOffsetY: 1 };
// the root's top-level keys a component's box and a candlestick reach
const RT = { shadowBlur: 7, shadowColor: '#0000ff', shadowOffsetX: 2, shadowOffsetY: 3, borderRadius: 5, borderType: 'dashed',
  borderDashOffset: 1, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4 };

const bare = o => Object.assign({ animation: false, color: PAL }, o);
const MOVE = { type: 'updateAxisPointer', currTrigger: 'mousemove', x: 200, y: 150 };
// an axis pointer shown by updateAxisPointer on a scatter of no symbols
const TIP = ap => ({ trigger: 'axis', showContent: false, renderMode: 'richText',
  axisPointer: Object.assign({ label: { show: false } }, ap || {}) });
const cartP = (o, ap, xa) => bare(Object.assign({
  tooltip: TIP(ap),
  xAxis: Object.assign({ type: 'category', data: N, axisLabel: { show: false }, axisTick: { show: false } }, xa || {}),
  yAxis: { axisLabel: { show: false } },
  series: [{ type: 'scatter', symbolSize: 0, data: [3, 5, 2] }] }, o));
const polarP = (o, ap) => bare(Object.assign({
  tooltip: TIP(ap), polar: {},
  angleAxis: { type: 'category', data: N, axisLabel: { show: false } }, radiusAxis: { axisLabel: { show: false } },
  series: [{ type: 'scatter', coordinateSystem: 'polar', symbolSize: 0, data: [3, 5, 2] }] }, o));
const singleP = (o, ap) => bare(Object.assign({
  tooltip: TIP(ap), singleAxis: { type: 'category', data: N, axisLabel: { show: false } },
  series: [{ type: 'scatter', coordinateSystem: 'singleAxis', symbolSize: 0, data: [3, 5, 2] }] }, o));
const PT = { looks: true, fills: true, action: MOVE };
// off the polar's centre
const MOVE_P = { type: 'updateAxisPointer', currTrigger: 'mousemove', x: 250, y: 110 };
const PTP = { looks: true, fills: true, action: MOVE_P };
const PTPN = { looks: true, fills: true, nocolour: true, action: MOVE_P };
const PTN = { looks: true, fills: true, nocolour: true, action: MOVE };
const BOX = { looks: true, fills: true, shapes: true };
const CS = { color: '#eb5454', color0: '#47b262', borderColor: '#eb5454', borderColor0: '#47b262' };
const candle = (s, o) => bare(Object.assign({ xAxis: { type: 'category', data: N }, yAxis: {},
  series: [Object.assign({ type: 'candlestick', itemStyle: CS, data: [[2, 4, 1, 5], [3, 2, 1, 4]] }, s)] }, o));
const ALL = { looks: true, fills: true, shapes: true };
// a candlestick's body is no rect: its pens, looks and fills
const LF = { looks: true, fills: true };
// a map of two squares, registered for the geo and map cases
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
const MAPS = [{ name: 'r7xsq', text: JSON.stringify({ type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] } }] }) }];
// [R7-AC] an SVG map of two named open paths (their ends show the cap and the join): node has no
// DOMParser -- jsdom's, as geo-svg.js installs it. One map a case: GeoSVGResource hands its first
// graphic to the next chart of the map, the styles a chart set on it kept
const JSDOM_PATH = process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom';
global.DOMParser = new (require(JSDOM_PATH).JSDOM)('').window.DOMParser;
const SVG_ENDS = '<svg width="200" height="100" viewBox="0 0 200 100">'
  + '<path name="P" d="M10 10 L90 10 L90 90" fill="none" stroke="#000000" stroke-width="1"/>'
  + '<path name="Q" d="M110 90 L110 10 L190 10" fill="none" stroke="#000000" stroke-width="1"/></svg>';
MAPS.push({ name: 'r7acsvg1', svg: true, text: SVG_ENDS }, { name: 'r7acsvg2', svg: true, text: SVG_ENDS });
for (const m of MAPS) echarts.registerMap(m.name, m.svg ? { svg: m.text } : m.text);
// the pens without their (default) colours, no fills: a region's defaults are the theme's
const NCL = { looks: true, nocolour: true };
// root-styles.js' own keys of a series
const OI = { color: '#112233', opacity: 0.9, borderWidth: 1, borderRadius: 2, shadowBlur: 1 };
const RS = { itemStyle: RI, lineStyle: RL, areaStyle: RA };
// an item tooltip shown by showTip, its content in rich text
const TIPC = { tooltip: { renderMode: 'richText' }, xAxis: { type: 'category', data: N }, yAxis: {},
  series: [{ type: 'scatter', data: [1, 2, 3] }] };
const vm = (v, o) => bare(Object.assign({ visualMap: Object.assign({ min: 0, max: 10, calculable: false }, v),
  series: [{ type: 'scatter', data: [[1, 2, 3]] }], xAxis: {}, yAxis: {} }, o));

// [id, option, part, more]
function cases() {
  return [
    // ---- the axis pointer's line ----
    // the root's lineStyle: all but colour, width and type (the component's defaults)
    ['ptr.root', cartP(Object.assign({ lineStyle: RL }, {})), 'pointer', PTN],
    // the pointer's own pen, on the axis
    ['ptr.axis', cartP({}, {}, { axisPointer: { lineStyle: PL } }), 'pointer', PT],
    // ... on the tooltip
    ['ptr.tooltip', cartP({}, { lineStyle: PL }), 'pointer', PT],
    // ... on the global axisPointer component
    ['ptr.component', cartP({ axisPointer: { lineStyle: PL } }), 'pointer', PT],
    // key by key: the axis' width over the tooltip's colour and opacity over the component's shadow over the root's cap
    ['ptr.perkey', cartP({ axisPointer: { lineStyle: { shadowBlur: 4, shadowColor: '#ff0000' } }, lineStyle: { cap: 'round', join: 'bevel' } },
      { lineStyle: { color: '#00ff00', opacity: 0.5, width: 4 } }, { axisPointer: { lineStyle: { width: 3 } } }), 'pointer', PT],
    // the coordinate system's tooltip lineStyle is taken whole: the global tooltip's width does not reach
    ['ptr.coordtip', cartP({ grid: { tooltip: { axisPointer: { lineStyle: { color: '#0000ff', opacity: 0.3 } } } } },
      { lineStyle: { width: 4, shadowBlur: 2, shadowColor: '#ff0000' } }), 'pointer', PT],
    // an axis' own pointer, no tooltip: the axis', the component's, the root's
    ['ptr.own', bare({ lineStyle: RL, xAxis: { type: 'category', data: N, axisLabel: { show: false },
      axisPointer: { show: true, label: { show: false }, lineStyle: { color: '#123456', join: 'bevel' } } },
      yAxis: { axisLabel: { show: false } }, series: [{ type: 'scatter', symbolSize: 0, data: [3, 5, 2] }] }), 'pointer', PT],
    // a cross: the base arm the lineStyle chain, the other arm the tooltip's crossStyle (whole) over the
    // component's and the root's lineStyle; the root's crossStyle reaches neither
    ['ptr.cross-root', cartP({ lineStyle: RL }, { type: 'cross', label: { show: false } }), 'pointer', PTN],
    ['ptr.cross-own', cartP({}, { type: 'cross', label: { show: false }, lineStyle: { color: '#445566' }, crossStyle: PL }), 'pointer', PT],
    ['ptr.cross-rootcross', cartP({ crossStyle: PL }, { type: 'cross', label: { show: false } }), 'pointer', PTN],
    // the shadow band: getAreaStyle of shadowStyle -- its fill, opacity, shadow
    ['ptr.shadow', cartP({}, { type: 'shadow', shadowStyle: PS }), 'pointer', PT],
    // a band of a fractional width, where it lands
    ['ptr.shadow-frac', cartP({}, { type: 'shadow', shadowStyle: PS }, { data: ['A', 'B', 'C', 'D', 'E', 'F', 'G'] }), 'pointer',
      Object.assign({ shapes: true }, PT)],
    ['ptr.shadow-root', cartP({ shadowStyle: { opacity: 0.3, shadowBlur: 5, shadowColor: '#0000ff' }, areaStyle: RA, lineStyle: RL,
      axisPointer: { shadowStyle: { color: 'rgba(0, 0, 0, 0.25)' } } },
      { type: 'shadow' }), 'pointer', PTN],
    // polar: a line on the angle axis, a circle on the radius axis, a sector for a shadow
    ['ptr.polar', polarP({ lineStyle: RL }), 'pointer', PTPN],
    ['ptr.polar-own', polarP({}, { lineStyle: PL }), 'pointer', PTP],
    ['ptr.polar-radius', polarP({}, { axis: 'radius', lineStyle: PL }), 'pointer', PTP],
    ['ptr.polar-shadow', polarP({}, { type: 'shadow', shadowStyle: PS }), 'pointer', PTP],
    // a single axis
    ['ptr.single', singleP({ lineStyle: RL }), 'pointer', PTN],
    ['ptr.single-own', singleP({}, { lineStyle: PL }), 'pointer', PT],
    ['ptr.single-shadow', singleP({}, { type: 'shadow', shadowStyle: PS }), 'pointer', PT],
    // ---- the component boxes: their own keys, and the root's top-level ones ----
    ['title.own', bare({ title: Object.assign({ text: 'T', backgroundColor: '#eeeeee', borderWidth: 2, borderColor: '#333333' }, RT) }), 'title', BOX],
    ['title.root', bare(Object.assign({ title: { text: 'T', backgroundColor: '#eeeeee', borderWidth: 2, borderColor: '#333333' } }, RT)), 'title', BOX],
    ['title.bare', bare(Object.assign({ title: { text: 'T' } }, RT)), 'title', BOX],
    ['legend.own', bare({ legend: Object.assign({ backgroundColor: '#eeeeee', borderWidth: 2, borderColor: '#333333' }, RT),
      series: [{ type: 'pie', name: 'p', label: { show: false }, data: [{ name: 'a', value: 1 }] }] }), 'legend', BOX],
    ['legend.root', bare(Object.assign({ legend: { backgroundColor: '#eeeeee', borderWidth: 2, borderColor: '#333333' },
      series: [{ type: 'pie', label: { show: false }, data: [{ name: 'a', value: 1 }] }] }, RT)), 'legend', BOX],
    ['toolbox.own', bare({ toolbox: Object.assign({ feature: { restore: {} }, backgroundColor: '#eeeeee', borderWidth: 2,
      borderColor: '#333333' }, RT) }), 'toolbox', BOX],
    ['toolbox.root', bare(Object.assign({ toolbox: { feature: { restore: {} }, backgroundColor: '#eeeeee', borderWidth: 2,
      borderColor: '#333333' } }, RT)), 'toolbox', BOX],
    ['visualMap.root', vm({ backgroundColor: '#eeeeee', borderWidth: 2, borderColor: '#333333' }, RT), 'visualMap', BOX],
    // a continuous visualMap's itemWidth / itemHeight and every visualMap's text climb to the root
    ['visualMap.size', vm({}, { itemWidth: 30, itemHeight: 80, text: ['hi', 'lo'] }), 'visualMap', { vm: true, texts: true }],
    ['visualMap.size-own', vm({ itemWidth: 10, itemHeight: 50, text: ['H', 'L'] }, { itemWidth: 30, itemHeight: 80, text: ['hi', 'lo'] }),
      'visualMap', { vm: true, texts: true }],
    ['visualMap.piece', vm({ type: 'piecewise', splitNumber: 2 }, { itemWidth: 30, itemHeight: 80, text: ['hi', 'lo'] }),
      'visualMap', { vm: true, texts: true }],
    // a legend's icon and formatter
    ['legend.icon', bare({ icon: 'diamond', formatter: '{name}!', legend: {},
      series: [{ type: 'pie', label: { show: false }, data: [{ name: 'a', value: 1 }, { name: 'b', value: 2 }] }] }), 'legend',
    { icons: true, texts: true }],
    ['legend.icon-own', bare({ icon: 'diamond', formatter: '{name}!', legend: { icon: 'rect', formatter: '<{name}>' },
      series: [{ type: 'pie', label: { show: false }, data: [{ name: 'a', value: 1 }, { name: 'b', value: 2 }] }] }), 'legend',
    { icons: true, texts: true }],
    // ---- a candlestick's top-level keys: the item's, the series', the root's ----
    ['candle.top-root', candle({}, { borderWidth: 3, opacity: 0.5, shadowBlur: 4, shadowColor: '#0000ff', shadowOffsetX: 2,
      borderType: 'dashed', borderDashOffset: 1, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4 }), '', LF],
    ['candle.top-series', candle({ borderWidth: 2, opacity: 0.7, shadowBlur: 1, shadowColor: '#ff0000' }, { borderWidth: 3 }), '', LF],
    ['candle.top-item', candle({ data: [{ value: [2, 4, 1, 5], borderWidth: 4, opacity: 0.3 }, [3, 2, 1, 4]] }, { opacity: 0.5 }), '', LF],
    // the root's colour and borderColor are overwritten by the item's itemStyle colours
    ['candle.top-colour', candle({}, { borderColor: '#00ff00' }), '', LF],
    // ---- a bar's item corners ----
    ['bar.item-radius', bare({ xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'bar', itemStyle: { borderRadius: 2 }, data: [3, { value: 5, itemStyle: { borderRadius: [6, 4, 0, 0] } }, 2] }] }), '', ALL],
    ['bar.item-radius-root', bare({ itemStyle: { borderRadius: 3 }, xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'bar', data: [3, { value: 5, itemStyle: { borderRadius: 8 } }, 2] }] }), '', ALL],
    ['bar.item-radius-stack', bare({ xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'bar', stack: 's', data: [3, { value: 5, itemStyle: { borderRadius: 4 } }, 2] },
        { type: 'bar', stack: 's', itemStyle: { borderRadius: 1 }, data: [1, 1, { value: 1, itemStyle: { borderRadius: 3 } }] }] }), '', ALL],
    ['bar.item-radius-horizontal', bare({ yAxis: { type: 'category', data: N }, xAxis: {},
      series: [{ type: 'bar', data: [3, { value: 5, itemStyle: { borderRadius: [6, 4, 2, 0] } }, 2] }] }), '', ALL],
    ['bar.polar-item-radius', bare({ polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', itemStyle: { borderRadius: 2 },
        data: [3, { value: 5, itemStyle: { borderRadius: [4, 8] } }, 2] }] }), '', ALL],
    ['pie.item-radius', bare({ series: [{ type: 'pie', label: { show: false }, itemStyle: { borderRadius: 2 },
      data: [3, { value: 5, itemStyle: { borderRadius: 9 } }, 2] }] }), '', ALL],
    // ---- the states under the root's blocks: emphasis / select / blur style what they write, the root's base stays ----
    ['state.line-hover', bare(Object.assign({ lineStyle: RL, xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'line', symbol: 'none', emphasis: { lineStyle: { width: 7 } }, data: [3, 5, 2] }] })),
    '', { looks: true, fills: true, action: { type: 'highlight', seriesIndex: 0 } }],
    ['state.bar-select', bare({ itemStyle: RI, xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'bar', selectedMode: 'single', select: { itemStyle: { borderWidth: 2, borderColor: '#000000' } }, data: [3, 5, 2] }] }),
    '', { looks: true, fills: true, shapes: true, action: { type: 'select', seriesIndex: 0, dataIndex: 1 } }],
    // ---- the tooltip's model: its keys TooltipModel has no default for (formatter, borderColor,
    // order, position, valueFormatter, align, verticalAlign; padding's is null) climb to the root's ----
    ['tip.root', bare(Object.assign({}, TIPC, { formatter: 'R:{b}', borderColor: '#00ff00', padding: 20, order: 'valueDesc',
      backgroundColor: '#123456', borderRadius: 9, borderWidth: 4 })), 'tooltip', { tip: true }],
    ['tip.own', bare(Object.assign({}, TIPC, { tooltip: { renderMode: 'richText', formatter: 'T:{b}', padding: [1, 2],
      borderColor: '#0000ff' }, formatter: 'R:{b}', borderColor: '#00ff00', padding: 20 })), 'tooltip', { tip: true }],
    ['tip.series', bare(Object.assign({}, TIPC, { formatter: 'R:{b}', padding: 20,
      series: [{ type: 'scatter', tooltip: { formatter: 'S:{b}' }, data: [1, 2, 3] }] })), 'tooltip', { tip: true }],
    // ---- geo and map under the root's blocks: a region's getItemStyle climbs the geo's (the series') itemStyle to the root's ----
    ['geo.root', bare(Object.assign({ geo: { map: 'r7xsq' } }, RS)), 'geo', NCL],
    ['geo.own', bare(Object.assign({ geo: { map: 'r7xsq', itemStyle: OI } }, RS)), 'geo', { looks: true, fills: true, nocolour: true }],
    ['map.root', bare(Object.assign({ series: [{ type: 'map', map: 'r7xsq', data: [{ name: 'A', value: 1 }] }] }, RS)), '', NCL],
    // ---- more per-item keys: a funnel's opacity, a treemap's and a sunburst's corners ----
    ['funnel.item-opacity', bare({ series: [{ type: 'funnel', label: { show: false }, itemStyle: { opacity: 0.8 },
      data: [3, { value: 5, itemStyle: { opacity: 0.3 } }, 2] }] }), '', ALL],
    ['treemap.item-radius', bare({ series: [{ type: 'treemap', breadcrumb: { show: false }, itemStyle: { borderRadius: 2 },
      data: [{ name: 'a', value: 3, itemStyle: { borderRadius: 6 } }, { name: 'b', value: 2 }] }] }), '', ALL],
    ['sunburst.item-radius', bare({ series: [{ type: 'sunburst', itemStyle: { borderRadius: 2 },
      data: [{ name: 'a', value: 3, itemStyle: { borderRadius: 5 } }, { name: 'c', value: 2 }] }] }), '', ALL],
    // ---- a label's inherited colour: the visual's, not the root's itemStyle colour ----
    ['label.inherit-bar', bare({ itemStyle: RI, xAxis: { type: 'category', data: N }, yAxis: {},
      series: [{ type: 'bar', label: { show: true, position: 'top', color: 'inherit' }, data: [3, 5, 2] }] }), '', { labels: true }],
    // ---- for the mutation round ----
    // a continuous visualMap's controller sizes map onto itemSize[0]: the bar's polygon under inRange.symbolSize
    ['visualMap.size-symbol', vm({ inRange: { symbolSize: [5, 40] } }, { itemWidth: 30 }), 'visualMap', { polys: true }],
    // a dash word from the series' itemStyle, measured against the root's top-level width
    ['candle.top-dash', candle({ itemStyle: Object.assign({ borderType: 'dashed' }, CS) }, { borderWidth: 3 }), '', LF],
    // an axis tooltip: its model over the global one, the root under it
    ['tip.axis', bare(Object.assign({}, TIPC, { tooltip: { renderMode: 'richText', trigger: 'axis' }, formatter: 'R:{b}',
      borderColor: '#00ff00' })), 'tooltip', { tip: true }],
    // a title's corners as an array
    ['title.radius-array', bare({ title: { text: 'T', backgroundColor: '#eeeeee', borderRadius: [1, 2, 3, 4] } }), 'title', BOX],
    // the axis' colour over the tooltip's, the tooltip's over the component's (key by key, the first level wins)
    ['ptr.colour-order', cartP({ axisPointer: { lineStyle: { color: '#0000ff', type: 'dotted' } } },
      { lineStyle: { color: '#00ff00', type: 'solid' } }, { axisPointer: { lineStyle: { color: '#123456' } } }), 'pointer', PT],
    // a proxy tooltip (showTip at a point with its own option): [tooltipOpt, {formatter: content}] over the global, the root under it
    ['tip.proxy', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20 })), 'tooltip',
      { tip: { type: 'showTip', x: 100, y: 100, tooltip: { content: 'hello' } } }],
    ['state.pie-blur', bare({ itemStyle: RI, series: [{ type: 'pie', label: { show: false }, emphasis: { focus: 'self' },
      data: [3, 5, 2] }] }), '', { looks: true, fills: true, shapes: true, action: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } }],
    // ---- [R7-AC] the other tooltips' cascades, the root under the global tooltip: a marker's (the
    // series item tooltip of its data), a matrix cell's, a geo region's, a legend item's, a toolbox
    // icon's, a timeline tick's -- each opened by showTip at a point over its element (findHover's
    // target there: `find` names what it must be; the point found is the action recorded) ----
    ['tip.marker-root', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      series: [{ type: 'scatter', symbolSize: 4, data: [1, 2, 3],
        markPoint: { symbol: 'circle', symbolSize: 24, label: { show: false }, data: [{ name: 'M', coord: [1, 2.5] }] } }] })),
    'tooltip', { tip: { find: 'markPoint' } }],
    ['tip.matrix-root', bare({ tooltip: { renderMode: 'richText' }, borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      matrix: { x: { data: ['P', 'Q'] }, y: { data: ['U', 'V'] }, tooltip: { show: true } } }),
    'tooltip', { tip: { find: 'matrix' } }],
    ['tip.geo-root', bare({ tooltip: { renderMode: 'richText' }, borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      geo: { map: 'r7xsq', tooltip: { show: true } } }), 'tooltip', { tip: { find: 'geo' } }],
    ['tip.legend-root', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      legend: { tooltip: { show: true } }, series: [{ type: 'scatter', name: 'S', data: [1, 2, 3] }] })),
    'tooltip', { tip: { find: 'legend' } }],
    ['tip.toolbox-root', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      toolbox: { feature: { restore: {} }, tooltip: { show: true } } })), 'tooltip', { tip: { find: 'toolbox' } }],
    ['tip.timeline-root', { baseOption: bare({ tooltip: { renderMode: 'richText' }, borderColor: '#00ff00', padding: 20,
      formatter: 'R:{b}', timeline: { axisType: 'category', data: ['a', 'b'], autoPlay: false, left: 20, right: 20, bottom: 10 } }),
      options: [{ series: [] }, { series: [] }] }, 'tooltip', { tip: { find: 'timeline' } }],
    // [R7-AE] showTip naming a component and an item's name (findComponentReference: the first
    // element of the component's view whose tooltipConfig has the name -- the tip shown at the
    // centre of its rect, `at` the point); a series by its index and a name; a timeline has no
    // tooltipConfig (`none`: nothing shown)
    ['tip.legend-ref', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      legend: { tooltip: { show: true } }, series: [{ type: 'scatter', name: 'S', data: [1, 2, 3] }] })),
    'tooltip', { tip: { type: 'showTip', legendIndex: 0, name: 'S' }, at: true }],
    ['tip.legend-ref-off', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      legend: {}, series: [{ type: 'scatter', name: 'S', data: [1, 2, 3] }] })),
    'tooltip', { tip: { type: 'showTip', legendIndex: 0, name: 'S' }, none: true }],
    // (an item's tooltip showing: a showTip that finds no element leaves it as it was)
    ['tip.legend-ref-pre', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      legend: {}, series: [{ type: 'scatter', name: 'S', data: [1, 2, 3] }] })),
    'tooltip', { pre: { type: 'showTip', seriesIndex: 0, dataIndex: 1 }, tip: { type: 'showTip', legendIndex: 0, name: 'S' },
      at: true }],
    ['tip.legend-name', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      legend: { name: 'LG', tooltip: { show: true } }, series: [{ type: 'scatter', name: 'S', data: [1, 2, 3] },
        { type: 'scatter', name: 'T', data: [2, 3, 1] }] })),
    'tooltip', { tip: { type: 'showTip', legendName: 'LG', name: 'T' }, at: true }],
    ['tip.toolbox-ref', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      toolbox: { feature: { restore: {}, saveAsImage: {} }, tooltip: { show: true } } })),
    'tooltip', { tip: { type: 'showTip', toolboxIndex: 0, name: 'saveAsImage' }, at: true }],
    ['tip.axis-ref', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      xAxis: { type: 'category', data: N, tooltip: { show: true } } })),
    'tooltip', { tip: { type: 'showTip', xAxisIndex: 0, name: 'B' }, at: true }],
    ['tip.graphic-ref', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      graphic: [{ type: 'rect', name: 'G', shape: { x: 50, y: 40, width: 40, height: 30 }, style: { fill: '#ff0000' },
        tooltip: { show: true, formatter: 'G!' } }] })),
    'tooltip', { tip: { type: 'showTip', graphicIndex: 0, name: 'G' }, at: true }],
    // [R7-AF] the element found off what is shown: a scroll legend's item on a page not shown (its
    // hit rect in the content group all the same), an axis label turned (its rect's centre through
    // the turn) or hidden by hideOverlap (ignored, found all the same), a graphic group and its child
    // of one name, two elements of one name (the first in the view group's traversal)
    ['tip.legend-scroll-ref', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      legend: { type: 'scroll', left: 20, width: 160, tooltip: { show: true } },
      series: ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel'].map(n => ({ type: 'scatter', name: n,
        data: [1, 2, 3] })) })),
    'tooltip', { tip: { type: 'showTip', legendIndex: 0, name: 'Golf' }, at: true }],
    ['tip.axis-ref-turned', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      xAxis: { type: 'category', data: ['Alpha', 'Bravo', 'Charlie'], axisLabel: { rotate: 40 }, tooltip: { show: true } } })),
    'tooltip', { tip: { type: 'showTip', xAxisIndex: 0, name: 'Bravo' }, at: true }],
    ['tip.axis-ref-hidden', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      xAxis: { type: 'category', data: ['Alphabet', 'Bravissimo', 'Charleston', 'Deltawing', 'Echoplex', 'Foxtrotting'],
        axisLabel: { interval: 0, hideOverlap: true, fontSize: 30 }, tooltip: { show: true } } })),
    'tooltip', { tip: { type: 'showTip', xAxisIndex: 0, name: 'Bravissimo' }, at: true }],
    ['tip.graphic-ref-group', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      graphic: [{ type: 'group', name: 'G', x: 30, y: 20, tooltip: { show: true, formatter: 'grp' },
        children: [{ type: 'rect', name: 'G', shape: { x: 50, y: 40, width: 40, height: 30 }, style: { fill: '#ff0000' },
          tooltip: { show: true, formatter: 'kid' } }] }] })),
    'tooltip', { tip: { type: 'showTip', graphicIndex: 0, name: 'G' }, at: true }],
    ['tip.graphic-ref-twice', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      graphic: [{ type: 'rect', name: 'H', shape: { x: 150, y: 40, width: 40, height: 30 }, style: { fill: '#ff0000' },
        tooltip: { show: true, formatter: 'one' } },
      { type: 'rect', name: 'H', shape: { x: 50, y: 140, width: 60, height: 20 }, style: { fill: '#0000ff' },
        tooltip: { show: true, formatter: 'two' } }] })),
    'tooltip', { tip: { type: 'showTip', graphicIndex: 0, name: 'H' }, at: true }],
    ['tip.series-name', bare(Object.assign({}, TIPC, { borderColor: '#00ff00', padding: 20, formatter: 'R:{b}' })),
    'tooltip', { tip: { type: 'showTip', seriesIndex: 0, name: 'C' }, at: true }],
    ['tip.geo-ref', bare({ tooltip: { renderMode: 'richText' }, borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      geo: { map: 'r7xsq', tooltip: { show: true } } }), 'tooltip', { tip: { type: 'showTip', geoIndex: 0, name: 'B' }, at: true }],
    ['tip.matrix-ref', bare({ tooltip: { renderMode: 'richText' }, borderColor: '#00ff00', padding: 20, formatter: 'R:{b}',
      matrix: { x: { data: ['P', 'Q'] }, y: { data: ['U', 'V'] }, tooltip: { show: true } } }),
    'tooltip', { tip: { type: 'showTip', matrixIndex: 0, name: 'Q' }, at: true }],
    ['tip.timeline-ref', { baseOption: bare({ tooltip: { renderMode: 'richText' }, borderColor: '#00ff00', padding: 20,
      formatter: 'R:{b}', timeline: { axisType: 'category', data: ['a', 'b'], autoPlay: false, left: 20, right: 20, bottom: 10 } }),
      options: [{ series: [] }, { series: [] }] }, 'tooltip', { tip: { type: 'showTip', timelineIndex: 0, name: 'b' }, none: true }],
    // [R7-AC] an SVG map's named shapes: the geo's own ends, the root's under them (MapDraw._buildSVG
    // sets the option's itemStyle over the shape's own; R7-X's ends had no SVG case)
    ['geo.svg-ends', bare({ geo: { map: 'r7acsvg1', itemStyle: { borderColor: '#123456', borderWidth: 3, borderCap: 'round',
      borderJoin: 'bevel', borderMiterLimit: 3 } } }), 'geo', { looks: true }],
    ['geo.svg-root', bare(Object.assign({ geo: { map: 'r7acsvg2', itemStyle: { borderColor: '#123456', borderWidth: 2 } } }, RS)),
      'geo', { looks: true }],
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
function rectCorners(r) {
  if (typeof r === 'number') return [r, r, r, r];
  if (!Array.isArray(r)) return [0, 0, 0, 0];
  if (r.length === 1) return [r[0], r[0], r[0], r[0]];
  if (r.length === 2) return [r[0], r[1], r[0], r[1]];
  if (r.length === 3) return [r[0], r[1], r[2], r[1]];
  return [r[0], r[1], r[2], r[3]];
}
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
  // (an axis pointer's band is graphic['Rect'], its type the class name)
  if (e.type === 'rect' || e.type === 'Rect') {
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
// a polygon's points, canvas frame, two places (root-styles.js')
function polyOf(e) {
  if (e.type !== 'polygon' || !e.shape.points) return '';
  const m = e.transform || [1, 0, 0, 1, 0, 0];
  return e.shape.points.map(p => r2(m[0] * p[0] + m[2] * p[1] + m[4]) + ',' + r2(m[1] * p[0] + m[3] * p[1] + m[5])).join(';');
}
function looksOf(e) {
  const s = e.style;
  const o = s.opacity == null ? 1 : s.opacity;
  const b = s.shadowBlur || 0, x = s.shadowOffsetX || 0, y = s.shadowOffsetY || 0;
  const cast = b > 0 || x !== 0 || y !== 0;
  return [String(o), String(b), String(x), String(y), cast ? colourOf(s.shadowColor) : ''].join('|');
}
function penOf(e, nocolour) {
  const s = e.style;
  if (!(s.lineWidth > 0) || s.stroke == null || s.stroke === 'none') return '';
  const dash = normalizeLineDash(s.lineDash, s.lineWidth);
  const bad = dash && dash.some(v => !(isFinite(Number(v)) && Number(v) >= 0));
  const off = s.lineDashOffset == null ? 0 : s.lineDashOffset;
  const ends = [s.lineCap || 'butt', s.lineJoin || 'miter', String(s.miterLimit || 10)].join('/');
  const rest = [String(Number(s.lineWidth)), bad ? 'ignored' : dash ? dash.map(Number).join(',') : 'solid',
    String(Number(off)), ends].join('|');
  return nocolour ? rest : colourOf(s.stroke) + '|' + rest;
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
const PROTO = (function () {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  const p = Object.getPrototypeOf(probe);
  probe.dispose();
  return p;
})();
const DOM = {};
const GET_DOM = PROTO.getDom;
const AXES = ['xAxis', 'yAxis', 'angleAxis', 'radiusAxis', 'singleAxis'];

function run(id, option, part, more) {
  NOW = T_BASE;
  rngState = SEED;
  more = more || {};
  // a tooltip view needs a dom (TooltipView.render returns without one): only for the cases that ask
  if (more.tip) PROTO.getDom = () => DOM;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    if (more.tip) {
      const view = chart.getViewOfComponentModel(chart.getModel().getComponent('tooltip', 0));
      view._tooltipContent.getSize = () => [80, 40];
      let model = null;
      const show = view._showTooltipContent;
      view._showTooltipContent = function (tooltipModel) { model = tooltipModel; return show.apply(this, arguments); };
      // [R7-AC] a point over the element `find` names: of the points of a 2 px raster where findHover's
      // target is it (a component's tooltipConfig of that main type, a marker's data, a timeline's tick),
      // the one nearest the middle of those of the first such element (off its edges)
      if (more.tip.find) {
        const zr = chart.getZr();
        // (the transforms brought up to date, as a paint would)
        zr.storage.getDisplayList(true);
        // (getECData's store: makeInner's '__ec_inner_<n>' key, geo-svg.js' innerOf)
        const getECDataOf = el => {
          for (const k of Object.keys(el)) {
            const v = el[k];
            if (k.startsWith('__ec_inner_') && v && typeof v === 'object'
              && ('dataIndex' in v || 'tooltipConfig' in v || 'dataType' in v || 'dataModel' in v)) return v;
          }
          return null;
        };
        const kind = more.tip.find;
        const ok = t => {
          for (let e = t; e; e = e.parent || e.__hostTarget) {
            const d = getECDataOf(e);
            if (!d) continue;
            if (kind === 'markPoint') return !!d.dataModel && d.dataModel.mainType === 'markPoint';
            if (kind === 'timeline') return !!d.dataModel && d.dataModel.mainType === 'timeline';
            if (d.tooltipConfig) return d.componentMainType === kind;
          }
          return false;
        };
        let found = null;
        let first = null;
        const pts = [];
        for (let y = 1; y < H; y += 2) {
          for (let x = 1; x < W; x += 2) {
            const h = zr.handler.findHover(x, y);
            if (!(h && h.target && ok(h.target))) continue;
            if (!first) first = h.target;
            if (h.target === first) pts.push([x, y]);
          }
        }
        if (pts.length) {
          const mx = pts.reduce((s, p) => s + p[0], 0) / pts.length;
          const my = pts.reduce((s, p) => s + p[1], 0) / pts.length;
          let best = Infinity;
          for (const p of pts) {
            const d = (p[0] - mx) * (p[0] - mx) + (p[1] - my) * (p[1] - my);
            if (d < best) { best = d; found = { type: 'showTip', x: p[0], y: p[1] }; }
          }
        }
        must(found, id + ': no ' + kind + ' element to show the tip over');
        more = Object.assign({}, more, { tip: found });
      }
      // ([R7-AE] the transforms brought up to date first, as a paint would:
      // the rect of the element named is taken through its transform)
      if (more.at || more.none || more.pre) chart.getZr().storage.getDisplayList(true);
      if (more.pre) chart.dispatchAction(JSON.parse(JSON.stringify(more.pre)));
      chart.dispatchAction(more.tip === true ? { type: 'showTip', seriesIndex: 0, dataIndex: 1 } : JSON.parse(JSON.stringify(more.tip)));
      // [R7-AE] a showTip that opens nothing
      if (more.none) {
        must(!model, id + ': a tooltip shown');
        return { id, option, part, seen: 1, n: 0, pens: [], tip: { action: more.tip, none: true } };
      }
      must(model, id + ': no tooltip shown');
      const el = view._tooltipContent.el;
      const get = k => { const v = model.get(k); return v == null ? null : JSON.parse(JSON.stringify(v)); };
      const rec = { id, option, part, seen: 1, n: 0, pens: [], tip: { formatter: get('formatter'), borderColor: get('borderColor'),
        padding: get('padding'), order: get('order'), backgroundColor: get('backgroundColor'), borderRadius: get('borderRadius'),
        text: el.style.text, stroke: colourOf(el.style.borderColor) } };
      if (more.tip !== true) rec.tip.action = more.tip;
      if (more.pre) rec.tip.pre = more.pre;
      // [R7-AE] the point the tip was shown at
      if (more.at) rec.tip.at = [view._lastX, view._lastY];
      return rec;
    }
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
    const texts = [];
    const labels = new Set();
    const polys = [];
    const icons = [];
    let seen = 0;
    let n = 0;
    const visit = (e, pre) => {
      if (!(e instanceof Path) || e.ignore || e.invisible) return;
      seen++;
      pre = pre ? pre + '|' : '';
      if (more.looks) looks.add(pre + looksOf(e));
      if (more.shapes) { const t = shapeOf(e); if (t) shapes.push(pre + t); }
      if (more.fills && e.style.fill != null && e.style.fill !== 'none') fills.add(pre + colourOf(e.style.fill));
      if (more.labels) {
        const tc = e.getTextContent && e.getTextContent();
        if (tc && !tc.ignore && !tc.invisible && tc.style.text) labels.add(String(tc.style.text) + '|' + colourOf(tc.style.fill));
      }
      const p = penOf(e, more.nocolour);
      if (!p) return;
      n++;
      pens.add(pre + p);
    };
    const walk = (el, f) => {
      if (el.ignore) return;
      f(el);
      if (el.childrenRef) el.childrenRef().forEach(c => walk(c, f));
    };
    const views = (chart._componentsViews || []).filter(v => v && v.__model);
    if (part === 'pointer') {
      views.forEach(v => {
        if (!AXES.includes(v.__model.mainType)) return;
        const g = v._axisPointer && v._axisPointer._group;
        if (!g || g.ignore) return;
        const owner = v.__model.mainType + v.__model.componentIndex;
        walk(g, e => visit(e, owner));
      });
    }
    else if (part === 'geo') {
      views.forEach(v => { if (v.__model.mainType === 'geo') walk(v.group, e => visit(e, '')); });
    }
    else if (part) {
      views.forEach(v => {
        if (v.__model.mainType !== part) return;
        walk(v.group, e => {
          if (more.texts && e.type === 'text' && e.style && e.style.text != null && String(e.style.text) !== '') texts.push(String(e.style.text));
          if (more.icons && e instanceof Path && e.shape && e.shape.symbolType != null) icons.push(e.shape.symbolType);
          // the box: makeBackground's / the visualMap's z2 -1 rect, the title's rect
          if (e.type === 'rect' && (e.z2 === -1 || part === 'title')) visit(e, '');
          if (more.polys) { const q = polyOf(e); if (q) polys.push(q); }
        });
      });
    }
    else (chart._chartsViews || []).forEach(v => walk(v.group, e => visit(e, '')));
    const rec = { id, option, part, seen, n, pens: Array.from(pens).sort() };
    if (more.action) rec.action = more.action;
    if (more.nocolour) rec.nocolour = true;
    if (more.looks) rec.looks = Array.from(looks).sort();
    if (more.fills) rec.fills = Array.from(fills).sort();
    if (more.shapes) rec.shapes = shapes.sort();
    if (more.texts) rec.texts = texts.sort();
    if (more.icons) rec.icons = icons.sort();
    if (more.polys) rec.polys = polys.sort();
    if (more.labels) rec.labels = Array.from(labels).sort();
    if (more.vm) {
      const m = chart.getModel().getComponent('visualMap', 0);
      rec.vm = { itemSize: m.itemSize.map(Number), text: m.get('text') == null ? null : m.get('text').map(String) };
    }
    return rec;
  }
  finally {
    chart.dispose();
    if (more.tip) PROTO.getDom = GET_DOM;
  }
}

function generate() {
  const charts = cases().map(([id, o, part, more]) => run(id, o, part, more));
  const by = id => charts.find(c => c.id === id);
  const has = (id, k, v) => by(id)[k].includes(v);
  // guards: what upstream does
  // the root's lineStyle under the pointer: its opacity, shadow, phase and ends; the component's colour, width and type
  must(has('ptr.root', 'pens', 'xAxis0|1|4,2|2|square/round/3'), 'ptr.root pens: ' + by('ptr.root').pens);
  must(has('ptr.root', 'looks', 'xAxis0|0.6|3|0|2|#00ffffff'), 'ptr.root looks: ' + by('ptr.root').looks);
  // the root's crossStyle reaches no arm
  must(by('ptr.cross-rootcross').looks.every(l => l.endsWith('|1|0|0|0|')), 'ptr.cross-rootcross: ' + by('ptr.cross-rootcross').looks);
  // the title's box: the root's shadow and corners
  must(by('title.root').shapes.some(s => s.endsWith('|r:5,5,5,5')), 'title.root shapes: ' + by('title.root').shapes);
  // a legend's box keeps its default corners (0)
  must(by('legend.root').shapes.every(s => !s.includes('|r:')), 'legend.root shapes: ' + by('legend.root').shapes);
  must(by('visualMap.size').vm.itemSize.join() === '30,80', 'visualMap.size: ' + JSON.stringify(by('visualMap.size').vm));
  must(by('visualMap.piece').vm.itemSize.join() === '20,14', 'visualMap.piece: ' + JSON.stringify(by('visualMap.piece').vm));
  must(has('candle.top-root', 'looks', '0.5|4|2|0|#0000ffff'), 'candle.top-root looks: ' + by('candle.top-root').looks);
  // the root's formatter, borderColor and padding reach an item tooltip; its backgroundColor does not
  must(by('tip.root').tip.text === 'R:B' && by('tip.root').tip.stroke === '#00ff00ff' && by('tip.root').tip.padding === 20
    && by('tip.root').tip.backgroundColor === '#fff', 'tip.root: ' + JSON.stringify(by('tip.root').tip));
  // a geo region: the root's opacity and shadow under the geo's defaults (colour, border)
  must(by('geo.root').looks.some(l => l.startsWith('0.5|4|2|0|')), 'geo.root looks: ' + by('geo.root').looks);
  must(charts.every(c => c.seen > 0), 'a case has no path: ' + charts.filter(c => c.seen === 0).map(c => c.id));
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-X: what reaches the axis pointer\'s line and band, the component boxes, a candlestick (its top-level keys) '
      + 'and a bar\'s corners. Each case settled (its action dispatched and settled); `pens` the sorted set of stroke|width|dash|'
      + 'offset|cap/join/miter of every stroked path of the part (\'\' the series\' views; pointer the axes\' pointer groups, '
      + 'each entry prefixed with its axis; title / legend / toolbox / visualMap the component\'s background rect), as '
      + 'root-styles.js; nocolour: the pens without the stroke colour; `looks` opacity|shadowBlur|shadowOffsetX|shadowOffsetY|'
      + 'shadowColor; `fills`; `shapes` rects and sectors with their corners; `texts` the component\'s texts; `icons` a legend\'s '
      + 'icon symbol types; `vm` the visualMap model\'s itemSize and text; `tip` (part tooltip) the item tooltip model\'s '
      + 'formatter, borderColor, padding, order, backgroundColor and borderRadius as showTip builds it, and its rich-text box\'s '
      + 'text and border colour; `labels` the text|fill of each series element\'s label; part geo every path of the geo '
      + 'component\'s view; `polys` a component\'s polygons (root-styles.js\'). `maps` the maps registered.',
    W, H, maps: MAPS, charts };
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
