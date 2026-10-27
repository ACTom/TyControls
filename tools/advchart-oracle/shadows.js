/*
Upstream's own answers for fix batch R5-A (spec section 238): WHICH ELEMENTS
CAST A SHADOW, AND WHICH. zrender draws a canvas shadow under every
Displayable whose style has a shadowBlur or a shadowOffsetX / Y (canvas/
graphic.ts bindCommonProps: ctx.shadowBlur = dpr * (style.shadowBlur || 0),
the offsets alike, ctx.shadowColor = style.shadowColor || '#000'); ECharts
puts the four keys there through getItemStyle / getLineStyle / getAreaStyle
(model/mixin/*Style.ts: the four are in every key map) -- the visual style
(visual/style.ts: the series' itemStyle, an item's own over it key by key),
a line's lineStyle and areaStyle, an edge's lineStyle, a label line's
labelLine.lineStyle, a gauge's parts (GaugeView), a state's
(setStatesStylesFromModel), the series' defaults (BoxplotSeries'
emphasis.itemStyle) -- and a text's TSpan its textShadow* (Text.ts: only
for a textShadowBlur above nought).

Each case is a chart, rendered once with animation off; then, where the
case says, a highlight action and the same elements read again. Every
element the case's picker finds is recorded: its role, series, index (and
a sub index where one item has several), and the four style values as the
canvas reads them -- the blur and the offsets (numbers as the hex of the
IEEE double), the colour as written (the prototype's '#000' where none).

  node tools/advchart-oracle/shadows.js

writes tests/fixtures/advchart-shadows.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-shadows.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function refresh(chart) { chart.getZr().storage.getDisplayList(true); }

// the canvas' reading of a style: (x || 0) for the three numbers, the colour
// as written or the prototype's
function shadowRec(role, s, i, st, extra) {
  const v = k => (typeof st[k] === 'number' && !Number.isNaN(st[k]) ? st[k] : 0);
  return Object.assign({ role, s, i,
    blur: hex(v('shadowBlur')), ox: hex(v('shadowOffsetX')), oy: hex(v('shadowOffsetY')),
    color: st.shadowColor == null ? null : String(st.shadowColor) }, extra || {});
}
function eachSeriesOf(chart, type, fn) {
  chart.getModel().eachSeries(sm => { if (sm.subType === type) fn(sm, sm.getData(), chart.getViewOfSeriesModel(sm)); });
}
const kids = g => (g && g.childrenRef ? g.childrenRef() : []);
function eachItem(chart, type, fn) {
  eachSeriesOf(chart, type, (sm, d, v) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) fn(sm, d, v, i, el); }));
}

const PICK = {
  bar: (chart, r) => eachItem(chart, 'bar', (sm, d, v, i, el) => r.push(shadowRec('bar', sm.seriesIndex, i, el.style))),
  line: (chart, r) => eachSeriesOf(chart, 'line', (sm, d, v) => {
    if (v._polyline) r.push(shadowRec('lineRun', sm.seriesIndex, -1, v._polyline.style));
    if (v._polygon) r.push(shadowRec('lineArea', sm.seriesIndex, -1, v._polygon.style));
    d.each(i => { const el = d.getItemGraphicEl(i); if (el && el.childAt(0)) r.push(shadowRec('lineSymbol', sm.seriesIndex, i, el.childAt(0).style)); });
  }),
  scatter: (chart, r) => eachItem(chart, 'scatter', (sm, d, v, i, el) => r.push(shadowRec('symbol', sm.seriesIndex, i, el.childAt(0).style))),
  effectScatter: (chart, r) => eachItem(chart, 'effectScatter', (sm, d, v, i, el) => {
    r.push(shadowRec('effectSymbol', sm.seriesIndex, i, el.childAt(0).childAt(0).style));
    // the ripples: none
    kids(el.childAt(1)).forEach((rp, k) => r.push(shadowRec('ripple', sm.seriesIndex, i, rp.style, { sub: k })));
  }),
  pie: (chart, r) => eachItem(chart, 'pie', (sm, d, v, i, el) => {
    r.push(shadowRec('sector', sm.seriesIndex, i, el.style));
    const g = el.getTextGuideLine && el.getTextGuideLine();
    if (g) r.push(shadowRec('guide', sm.seriesIndex, i, g.style));
  }),
  funnel: (chart, r) => eachItem(chart, 'funnel', (sm, d, v, i, el) => r.push(shadowRec('funnel', sm.seriesIndex, i, el.style))),
  gauge: (chart, r) => eachSeriesOf(chart, 'gauge', (sm, d, v) => {
    const pointers = new Set();
    const prog = new Set(v._progressEls || []);
    d.each(i => {
      const el = d.getItemGraphicEl(i);
      if (el) { pointers.add(el); r.push(shadowRec('gaugePointer', sm.seriesIndex, i, el.style)); }
      if (v._progressEls && v._progressEls[i]) r.push(shadowRec('gaugeProgress', sm.seriesIndex, i, v._progressEls[i].style));
    });
    let band = 0, split = 0, tick = 0, anchor = 0;
    v.group.traverse(el => {
      if (el.isGroup || el.type === 'text' || el.type === 'tspan' || pointers.has(el) || prog.has(el)) return;
      if (el.type === 'sector') r.push(shadowRec('gaugeBand', sm.seriesIndex, band++, el.style));
      else if (el.type === 'line') {
        // the case gives the split lines width 3, the ticks 1
        if (el.style.lineWidth === 3) r.push(shadowRec('gaugeSplit', sm.seriesIndex, split++, el.style));
        else r.push(shadowRec('gaugeTick', sm.seriesIndex, tick++, el.style));
      }
      else if (el.style && el.style.fill) r.push(shadowRec('gaugeAnchor', sm.seriesIndex, anchor++, el.style));
    });
  }),
  radar: (chart, r) => eachItem(chart, 'radar', (sm, d, v, i, g) => {
    r.push(shadowRec('radarLine', sm.seriesIndex, i, g.childAt(0).style));
    r.push(shadowRec('radarArea', sm.seriesIndex, i, g.childAt(1).style));
    kids(g.childAt(2)).forEach((s, k) => r.push(shadowRec('radarSymbol', sm.seriesIndex, i, s.style, { sub: k })));
  }),
  candlestick: (chart, r) => eachItem(chart, 'candlestick', (sm, d, v, i, el) => r.push(shadowRec('candle', sm.seriesIndex, i, el.style))),
  boxplot: (chart, r) => eachItem(chart, 'boxplot', (sm, d, v, i, el) => r.push(shadowRec('boxplot', sm.seriesIndex, i, el.style))),
  heatmap: (chart, r) => eachItem(chart, 'heatmap', (sm, d, v, i, el) => r.push(shadowRec('heat', sm.seriesIndex, i, el.style))),
  graph: (chart, r) => eachSeriesOf(chart, 'graph', (sm, d) => {
    d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(shadowRec('node', sm.seriesIndex, i, el.childAt(0).style)); });
    const ed = sm.getEdgeData();
    ed.each(i => { const el = ed.getItemGraphicEl(i); if (el) r.push(shadowRec('edge', sm.seriesIndex, i, el.childOfName('line').style)); });
  }),
  tree: (chart, r) => eachItem(chart, 'tree', (sm, d, v, i, el) => {
    r.push(shadowRec('treeNode', sm.seriesIndex, i, el.childAt(0).style));
    if (el.__edge) r.push(shadowRec('treeEdge', sm.seriesIndex, i, el.__edge.style));
  }),
  treemap: (chart, r) => eachSeriesOf(chart, 'treemap', (sm, d, v) => {
    const st = v._storage;
    d.each(i => {
      const raw = d.getRawIndex(i);
      if (st.background[raw]) r.push(shadowRec('tmBack', sm.seriesIndex, i, st.background[raw].style));
      if (st.content[raw]) r.push(shadowRec('tmContent', sm.seriesIndex, i, st.content[raw].style));
    });
  }),
  sunburst: (chart, r) => eachItem(chart, 'sunburst', (sm, d, v, i, el) => r.push(shadowRec('sun', sm.seriesIndex, i, el.style))),
  sankey: (chart, r) => eachSeriesOf(chart, 'sankey', (sm, d) => {
    d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(shadowRec('sankeyNode', sm.seriesIndex, i, el.style)); });
    const ed = sm.getEdgeData();
    ed.each(i => { const el = ed.getItemGraphicEl(i); if (el) r.push(shadowRec('sankeyEdge', sm.seriesIndex, i, el.style)); });
  }),
  chord: (chart, r) => eachSeriesOf(chart, 'chord', (sm, d) => {
    d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(shadowRec('chordNode', sm.seriesIndex, i, el.style)); });
    const ed = sm.getEdgeData();
    ed.each(i => { const el = ed.getItemGraphicEl(i); if (el) r.push(shadowRec('chordEdge', sm.seriesIndex, i, el.style)); });
  }),
  themeRiver: (chart, r) => eachSeriesOf(chart, 'themeRiver', (sm, d, v) => {
    let n = 0;
    v.group.traverse(el => { if (el.type === 'ec-polygon' || el.type === 'polygon') r.push(shadowRec('river', sm.seriesIndex, n++, el.style)); });
  }),
  parallel: (chart, r) => eachItem(chart, 'parallel', (sm, d, v, i, el) => r.push(shadowRec('parallel', sm.seriesIndex, i, el.style))),
  lines: (chart, r) => eachItem(chart, 'lines', (sm, d, v, i, el) => r.push(shadowRec('lines', sm.seriesIndex, i, el.childOfName('line').style))),
  pictorialBar: (chart, r) => eachItem(chart, 'pictorialBar', (sm, d, v, i, bar) => {
    const glyphs = [];
    kids(bar.__pictorialBundle).forEach(g => { if (!g.isGroup) glyphs.push(g); });
    if (!glyphs.length && bar.__pictorialMainPath) glyphs.push(bar.__pictorialMainPath);
    glyphs.forEach((g, k) => r.push(shadowRec('glyph', sm.seriesIndex, i, g.style, { sub: k })));
  }),
  // a label's box rects (the block's first, then each token's): their canvas shadow
  labelBox: (chart, r) => eachItem(chart, 'bar', (sm, d, v, i, el) => {
    const t = el.getTextContent && el.getTextContent();
    if (!t) return;
    let n = 0;
    kids(t).forEach(k => { if (k.type === 'rect') r.push(shadowRec('box', sm.seriesIndex, i, k.style, { sub: n++ })); });
  }),
  polarBar: (chart, r) => eachItem(chart, 'bar', (sm, d, v, i, el) => r.push(shadowRec('polarBar', sm.seriesIndex, i, el.style))),
  // a rich label's TSpans: their canvas shadow (Text.ts: a token's textShadowBlur, else the block's)
  richSpans: (chart, r) => eachItem(chart, 'bar', (sm, d, v, i, el) => {
    const t = el.getTextContent && el.getTextContent();
    if (!t) return;
    kids(t).filter(k => k.type === 'tspan').forEach((k, n) => r.push(shadowRec('span', sm.seriesIndex, i, k.style, { sub: n, text: String(k.style.text) })));
  }),
};

const CAT = { type: 'category', data: ['a', 'b', 'c'] };
const VAL = { type: 'value' };
const SH = { shadowBlur: 10, shadowColor: 'rgba(0, 0, 0, 0.5)', shadowOffsetX: 2, shadowOffsetY: 3 };
const CASES = [
  { id: 'bar', pick: ['bar'], note: "bars: the series' itemStyle shadow; item 1 its own shadowOffsetY 5 and shadowColor #ff0000 over it key by key; item 2 shadowBlur null (falls through); the second series only a blur (the colour '#000'), a blur of 0 with offsets on item 0 of a third, a negative blur on its item 1",
    option: { xAxis: CAT, yAxis: VAL, series: [
      { type: 'bar', itemStyle: SH, data: [5, { value: 7, itemStyle: { shadowOffsetY: 5, shadowColor: '#ff0000' } }, { value: 3, itemStyle: { shadowBlur: null } }] },
      { type: 'bar', itemStyle: { shadowBlur: 6 }, data: [4, 6, 2] },
      { type: 'bar', data: [{ value: 2, itemStyle: { shadowBlur: 0, shadowOffsetX: 4, shadowColor: '#00f' } }, { value: 3, itemStyle: { shadowBlur: -5, shadowOffsetY: 2 } }, 1] }] } },
  { id: 'barEmphasis', pick: ['bar'], highlight: { seriesIndex: 0, dataIndex: 1 }, note: "bar-brush's emphasis.itemStyle shadow: none at rest, the highlighted bar its blur 10 in rgba(0,0,0,0.3)",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', emphasis: { itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.3)' } }, data: [5, 7, 3] }] } },
  { id: 'line', pick: ['line'], note: "a line: lineStyle shadow (the polyline), areaStyle shadow (the area), itemStyle shadow (the symbols, item 2 its own colour)",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'line', showSymbol: true, symbolSize: 8,
      lineStyle: { shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.3)', shadowOffsetY: 8 },
      areaStyle: { shadowBlur: 5, shadowColor: '#888' },
      itemStyle: { shadowBlur: 3, shadowOffsetX: 1 },
      data: [5, 7, { value: 3, itemStyle: { shadowColor: '#ff0000' } }] }] } },
  { id: 'scatter', pick: ['scatter', 'effectScatter'], note: "scatter symbols: the series' shadow (bubble-gradient's), item 1 its own; an effectScatter's symbol its itemStyle's, its ripples none",
    option: { xAxis: VAL, yAxis: VAL, series: [
      { type: 'scatter', symbolSize: 20, itemStyle: { shadowBlur: 10, shadowColor: 'rgba(120, 36, 50, 0.5)', shadowOffsetY: 5 }, data: [[1, 2], { value: [3, 4], itemStyle: { shadowOffsetY: -2 } }] },
      { type: 'effectScatter', symbolSize: 12, itemStyle: { shadowBlur: 10, shadowColor: '#333' }, data: [[2, 3]] }] } },
  { id: 'pie', pick: ['pie'], note: "a pie: item 0 its own itemStyle shadow (pie-custom's 200), labelLine.lineStyle shadow on every line",
    option: { series: [{ type: 'pie', radius: '50%', labelLine: { lineStyle: { shadowBlur: 4, shadowColor: '#0f0' } },
      data: [{ value: 3, name: 'a', itemStyle: { shadowBlur: 200, shadowColor: 'rgba(0, 0, 0, 0.5)' } }, { value: 2, name: 'b' }, { value: 1, name: 'c' }] }] } },
  { id: 'pieEmphasis', pick: ['pie'], highlight: { seriesIndex: 0, dataIndex: 0 }, note: "pie-simple's emphasis shadow: the highlighted slice blur 10, offsetX 0, rgba(0,0,0,0.5)",
    option: { series: [{ type: 'pie', radius: '50%', emphasis: { itemStyle: { shadowBlur: 10, shadowOffsetX: 0, shadowColor: 'rgba(0, 0, 0, 0.5)' } },
      data: [{ value: 3, name: 'a' }, { value: 2, name: 'b' }] }] } },
  { id: 'funnel', pick: ['funnel'], note: 'funnel trapezoids: itemStyle shadow',
    option: { series: [{ type: 'funnel', itemStyle: SH, data: [{ value: 60, name: 'a' }, { value: 40, name: 'b' }] }] } },
  { id: 'gauge', pick: ['gauge'], note: "a gauge (gauge-clock's and gauge-speed's): axisLine.lineStyle, splitLine.lineStyle (width 3), axisTick.lineStyle (width 1), anchor.itemStyle; the series' itemStyle under the progress arc and the pointer, pointer.itemStyle over it; item 1 its own pointer.itemStyle blur",
    option: { series: [{ type: 'gauge', progress: { show: true, width: 8 },
      itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0,138,255,0.45)', shadowOffsetX: 2, shadowOffsetY: 2 },
      axisLine: { lineStyle: { width: 10, shadowBlur: 15, shadowColor: 'rgba(0, 0, 0, 0.5)' } },
      splitLine: { lineStyle: { width: 3, shadowBlur: 3, shadowColor: 'rgba(0, 0, 0, 0.3)', shadowOffsetX: 1, shadowOffsetY: 2 } },
      axisTick: { lineStyle: { width: 1, shadowBlur: 10, shadowColor: 'rgba(255, 255, 255)', shadowOffsetY: -10 } },
      pointer: { itemStyle: { shadowBlur: 8, shadowOffsetX: 2, shadowOffsetY: 4, shadowColor: 'rgba(0, 0, 0, 0.3)' } },
      anchor: { show: true, size: 12, itemStyle: { shadowBlur: 8, shadowColor: 'rgba(0, 0, 0, 0.3)', shadowOffsetX: 2, shadowOffsetY: 4 } },
      data: [{ value: 40 }, { value: 70, pointer: { itemStyle: { shadowBlur: 20 } } }] }] } },
  { id: 'radar', pick: ['radar'], note: "a radar item's polyline (lineStyle), polygon (areaStyle) and symbols (itemStyle); item 1 its own lineStyle colour",
    option: { radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
      series: [{ type: 'radar', lineStyle: { shadowBlur: 4, shadowColor: '#111' }, areaStyle: { shadowBlur: 10, shadowColor: 'rgba(0, 0, 0, 0.2)' }, itemStyle: { shadowBlur: 2 },
        data: [{ value: [5, 6, 7] }, { value: [3, 4, 5], lineStyle: { shadowColor: '#f00' } }] }] } },
  { id: 'candleBox', pick: ['candlestick', 'boxplot'], note: 'candlesticks (itemStyle shadow) and boxplots (itemStyle shadow)',
    option: { xAxis: CAT, yAxis: VAL, series: [
      { type: 'candlestick', itemStyle: SH, data: [[2, 4, 1, 5], [4, 3, 2, 6], [3, 5, 2, 6]] },
      { type: 'boxplot', itemStyle: { shadowBlur: 6, shadowColor: '#222' }, data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }] } },
  { id: 'boxEmphasis', pick: ['boxplot'], highlight: { seriesIndex: 0, dataIndex: 1 }, note: "BoxplotSeries' emphasis.itemStyle default: the highlighted box a blur of 5 at (1, 1) in tokens.color.shadow",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'boxplot', data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }] } },
  { id: 'heatEmphasis', pick: ['heatmap'], highlight: { seriesIndex: 0, dataIndex: 1 }, note: "heatmap-cartesian's emphasis shadow on the highlighted cell; the series' own itemStyle shadow at rest",
    option: { xAxis: CAT, yAxis: CAT, visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', itemStyle: { shadowBlur: 2, shadowColor: '#999' }, emphasis: { itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0, 0, 0, 0.5)' } }, data: [[0, 0, 5], [1, 1, 7], [2, 2, 3]] }] } },
  { id: 'graph', pick: ['graph'], note: "graph nodes (itemStyle, a category's over the series', a node's own over both) and edges (lineStyle, a link's own)",
    option: { series: [{ type: 'graph', layout: 'none', symbolSize: 20,
      itemStyle: { shadowBlur: 9, shadowColor: '#555', shadowOffsetX: 1.5, shadowOffsetY: 3 },
      lineStyle: { shadowBlur: 3, shadowColor: '#0f0' },
      categories: [{ name: 'k', itemStyle: { shadowColor: '#00f' } }],
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0, category: 0 }, { name: 'c', x: 50, y: 80, itemStyle: { shadowBlur: 1 } }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c', lineStyle: { shadowOffsetY: 4 } }] }] } },
  { id: 'tree', pick: ['tree'], note: "tree nodes (itemStyle) and edges (the node's lineStyle); node b its own",
    option: { series: [{ type: 'tree', initialTreeDepth: -1, itemStyle: { shadowBlur: 5, shadowColor: '#333' }, lineStyle: { shadowBlur: 2, shadowColor: '#999' },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b', itemStyle: { shadowOffsetY: 3 }, lineStyle: { shadowOffsetX: 2 } }] }] }] } },
  { id: 'treemap', pick: ['treemap'], note: "treemap rects: the series' itemStyle shadow (getItemStyleNormal), a level's and a node's own",
    option: { series: [{ type: 'treemap', breadcrumb: { show: false }, itemStyle: { shadowBlur: 4, shadowColor: '#444' },
      levels: [{}, { itemStyle: { shadowOffsetY: 2 } }],
      data: [{ name: 'a', value: 6, children: [{ name: 'a1', value: 4, itemStyle: { shadowColor: '#f00' } }, { name: 'a2', value: 2 }] }, { name: 'b', value: 3 }] }] } },
  { id: 'sunburst', pick: ['sunburst'], note: 'sunburst pieces: itemStyle shadow, a node its own',
    option: { series: [{ type: 'sunburst', itemStyle: { shadowBlur: 3, shadowColor: '#123456' },
      data: [{ name: 'a', value: 4, children: [{ name: 'a1', value: 2, itemStyle: { shadowBlur: 8 } }] }, { name: 'b', value: 3 }] }] } },
  { id: 'sankey', pick: ['sankey'], note: "sankey nodes (itemStyle) and links (lineStyle through getItemStyle), a link's own",
    option: { series: [{ type: 'sankey', itemStyle: { shadowBlur: 3, shadowColor: '#333' }, lineStyle: { shadowBlur: 5, shadowColor: '#999' },
      data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b', value: 3 }, { source: 'a', target: 'c', value: 2, lineStyle: { shadowOffsetY: 2 } }] }] } },
  { id: 'chord', pick: ['chord'], note: "chord nodes (the visual style, an item's own over it) and links (lineStyle's getLineStyle), a link's own",
    option: { series: [{ type: 'chord', itemStyle: { shadowBlur: 4, shadowColor: '#444' }, lineStyle: { shadowBlur: 6, shadowColor: '#888' },
      data: [{ name: 'a', itemStyle: { shadowOffsetX: 3 } }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 3 }, { source: 'b', target: 'c', value: 2, lineStyle: { shadowOffsetY: 5 } }] }] } },
  { id: 'river', pick: ['themeRiver'], highlight: { seriesIndex: 0, dataIndex: 1 }, note: "themeRiver-basic's emphasis shadow (blur 20, rgba(0,0,0,0.8)) on the highlighted layer; none at rest",
    option: { singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', emphasis: { itemStyle: { shadowBlur: 20, shadowColor: 'rgba(0, 0, 0, 0.8)' } },
      data: [['2015/11/08', 10, 'A'], ['2015/11/09', 15, 'A'], ['2015/11/08', 5, 'B'], ['2015/11/09', 8, 'B']] }] } },
  { id: 'parallelLines', pick: ['parallel', 'lines'], note: "parallel lines and a lines series: lineStyle shadow, an item's own",
    option: { parallelAxis: [{ dim: 0 }, { dim: 1 }], xAxis: VAL, yAxis: VAL, grid: { left: '60%' },
      series: [{ type: 'parallel', lineStyle: { shadowBlur: 3, shadowColor: '#333' }, data: [[1, 2], { value: [2, 1], lineStyle: { shadowOffsetX: 3 } }] },
        { type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { shadowBlur: 4, shadowColor: '#0a0' }, data: [{ coords: [[0, 0], [10, 10]] }, { coords: [[0, 10], [10, 0]], lineStyle: { shadowBlur: 7 } }] }] } },
  { id: 'pictorialPolar', pick: ['pictorialBar', 'polarBar'], note: "a pictorial bar's glyphs (itemStyle shadow) on a grid; a polar bar's sectors",
    option: { grid: { right: '55%' }, xAxis: CAT, yAxis: VAL, polar: { center: ['75%', '50%'], radius: '30%' }, angleAxis: { type: 'category', data: ['a', 'b'] }, radiusAxis: {},
      series: [{ type: 'pictorialBar', symbol: 'circle', symbolSize: [20, 20], itemStyle: { shadowBlur: 5, shadowColor: '#300' }, data: [5, 7, 3] },
        { type: 'bar', coordinateSystem: 'polar', itemStyle: { shadowBlur: 6, shadowColor: '#030', shadowOffsetX: 1 }, data: [2, 3] }] } },
  { id: 'labelBox', pick: ['labelBox'], note: "a bar label's box: backgroundColor with shadowBlur 4, shadowColor #333, offsetY 2; a rich token's own box with its own shadow (offsetX 3, #f00); the second series' box a blur with no colour: the text style's prototype '#000' (shadowColor || 'transparent' never reaches 'transparent')",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', data: [5, 7],
      label: { show: true, position: 'top', backgroundColor: '#eee', padding: 4, shadowBlur: 4, shadowColor: '#333', shadowOffsetY: 2,
        formatter: '{a|Ab} cd', rich: { a: { backgroundColor: '#ff0', shadowOffsetX: 3, shadowColor: '#f00' } } } },
      { type: 'bar', data: [3, 4], label: { show: true, backgroundColor: '#eee', shadowBlur: 5 } }] } },
  { id: 'richText', pick: ['richSpans'], note: "bar-rich-text's rich token a: textShadowBlur 2, #000, (0, 1); token b none; a plain label's textShadowBlur 0 with an offset (no shadow)",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', data: [5, 7],
      label: { show: true, position: 'top', formatter: '{a|Ab}{b|Cd}', rich: { a: { color: '#fff', textShadowBlur: 2, textShadowColor: '#000', textShadowOffsetX: 0, textShadowOffsetY: 1 }, b: {} } } },
      { type: 'bar', data: [3, 4], label: { show: true, textShadowBlur: 0, textShadowOffsetX: 3, textShadowColor: '#f00' } }] } },
];

// ---------- whole charts: the distinct shadows the components cast ----------
// every displayable of the chart but the texts, as the canvas would draw it:
// a shadow is a blur or an offset in a colour of some alpha; the distinct
// ones, sorted -- a component's elements are not one to one with the port's
const WHOLE = [
  { id: 'markers', note: "a bar's markPoint (itemStyle shadow), markLine (lineStyle shadow) and markArea (itemStyle shadow)",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', data: [5, 7, 3],
      markPoint: { itemStyle: { shadowBlur: 4, shadowColor: '#112233' }, data: [{ type: 'max' }] },
      markLine: { symbol: 'none', lineStyle: { shadowBlur: 6, shadowColor: '#223344', shadowOffsetY: 2 }, data: [{ type: 'average' }] },
      markArea: { itemStyle: { shadowBlur: 8, shadowColor: '#334455' }, data: [[{ xAxis: 'a' }, { xAxis: 'b' }]] } }] } },
  { id: 'matrix', note: "a matrix: backgroundStyle's shadow on the background (not the border), the body's cells' itemStyle, the x dimension's dividerLineStyle",
    option: { matrix: { x: { data: ['a', 'b'], dividerLineStyle: { shadowBlur: 3, shadowColor: '#0000ff' } }, y: { data: ['c', 'd'] },
      backgroundStyle: { color: '#eee', shadowBlur: 10, shadowColor: '#ff0000' }, body: { itemStyle: { shadowBlur: 2, shadowColor: '#00ff00' } } } } },
  { id: 'dataZoom', note: "a slider: handleStyle, moveHandleStyle, dataBackground's areaStyle and lineStyle shadows",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'line', data: [5, 7, 3] }],
      dataZoom: [{ type: 'slider', handleStyle: { shadowBlur: 3, shadowColor: '#ff0000' }, moveHandleStyle: { shadowBlur: 4, shadowColor: '#00ff00' },
        dataBackground: { areaStyle: { shadowBlur: 5, shadowColor: '#0000ff' }, lineStyle: { shadowBlur: 6, shadowColor: '#ff00ff' } } }] } },
  { id: 'toolbox', note: "toolbox icons: iconStyle's shadow",
    option: { toolbox: { feature: { restore: {}, saveAsImage: {} }, iconStyle: { shadowBlur: 3, shadowColor: '#ff0000', shadowOffsetX: 1 } },
      xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', data: [1, 2, 3] }] } },
  { id: 'graphic', note: "line-graphic's: a graphic rect's style shadow, a circle's own",
    option: { graphic: [{ type: 'rect', left: 10, top: 10, shape: { width: 50, height: 30 }, style: { fill: '#fff', shadowBlur: 8, shadowColor: 'rgba(0,0,0,0.2)', shadowOffsetX: 3, shadowOffsetY: 3 } },
      { type: 'circle', left: 100, top: 10, shape: { r: 20 }, style: { fill: '#f00', shadowBlur: 5, shadowColor: '#000' } }] } },
  { id: 'legend', note: "a legend box: backgroundColor with the legend's own shadow keys",
    option: { legend: { backgroundColor: '#fff', shadowBlur: 6, shadowColor: '#123456', shadowOffsetY: 2 }, xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', name: 's', data: [1, 2, 3] }] } },
  { id: 'radarGrid', note: "radar-custom's: the radar component's splitArea.areaStyle shadow, splitLine.lineStyle and axisLine.lineStyle",
    option: { radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }],
      splitArea: { areaStyle: { color: ['#eee', '#ddd'], shadowBlur: 10, shadowColor: 'rgba(0, 0, 0, 0.2)' } },
      splitLine: { lineStyle: { shadowBlur: 2, shadowColor: '#ff0000' } }, axisLine: { lineStyle: { shadowBlur: 3, shadowColor: '#00ff00' } } },
      series: [{ type: 'radar', data: [{ value: [5, 6, 7] }] }] } },
  { id: 'calendar', note: "a calendar: the day cells' itemStyle shadow, the split lines' lineStyle shadow",
    option: { calendar: { range: '2017-02', itemStyle: { shadowBlur: 2, shadowColor: '#ff0000' }, splitLine: { lineStyle: { shadowBlur: 3, shadowColor: '#0000ff' } } } } },
  { id: 'map', maps: true, note: "a map series' regions: itemStyle shadow, region B its own colour; then B highlighted: its emphasis shadow (blur 9)",
    option: { series: [{ type: 'map', map: 'r5ashadow', itemStyle: { shadowBlur: 4, shadowColor: '#ff0000' },
      emphasis: { itemStyle: { shadowBlur: 9 } },
      data: [{ name: 'A', value: 1 }, { name: 'B', value: 2, itemStyle: { shadowColor: '#00ff00' } }] }] },
    highlight: { seriesIndex: 0, name: 'B' } },
  { id: 'geo', maps: true, note: "a geo component's regions: its itemStyle shadow",
    option: { geo: { map: 'r5ashadow', itemStyle: { shadowBlur: 6, shadowColor: '#0000ff', shadowOffsetY: 2 } } } },
  { id: 'visualMap', note: "a continuous visualMap's handles: handleStyle's shadow",
    option: { visualMap: { type: 'continuous', calculable: true, min: 0, max: 10, handleStyle: { shadowBlur: 4, shadowColor: '#ff0000' } },
      xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', data: [1, 2, 3] }] } },
];
function wholeShadows(chart) {
  const seen = new Set();
  const out = [];
  chart.getZr().storage.getDisplayList(true).forEach(el => {
    if (el.type === 'text' || el.type === 'tspan' || el.invisible || el.ignore) return;
    const st = el.style || {};
    const v = k => (typeof st[k] === 'number' && !Number.isNaN(st[k]) ? st[k] : 0);
    const b = v('shadowBlur'), ox = v('shadowOffsetX'), oy = v('shadowOffsetY');
    if (!(b > 0 || ox || oy)) return;
    const col = st.shadowColor == null ? '#000' : String(st.shadowColor);
    const rec = { blur: hex(b), ox: hex(ox), oy: hex(oy), color: col };
    const key = JSON.stringify(rec);
    if (seen.has(key)) return;
    seen.add(key);
    out.push(rec);
  });
  out.sort((a, b) => (JSON.stringify(a) < JSON.stringify(b) ? -1 : 1));
  return out;
}
const SQ = [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]];
const SQ2 = [[[10, 0], [20, 0], [20, 10], [10, 10], [10, 0]]];
const MAPJSON = { type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: SQ } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: SQ2 } }] };
function runWhole(c) {
  if (c.maps) echarts.registerMap('r5ashadow', MAPJSON);
  const chart = mk(600, 400);
  try {
    chart.setOption(Object.assign({ animation: false }, c.option));
    chart.renderToSVGString();
    refresh(chart);
    const out = { id: c.id, note: c.note, option: c.option, shadows: wholeShadows(chart) };
    if (c.highlight) {
      chart.dispatchAction(Object.assign({ type: 'highlight' }, c.highlight));
      chart.getZr().animation.update();
      chart.renderToSVGString();
      refresh(chart);
      out.highlight = c.highlight;
      out.highlighted = wholeShadows(chart);
    }
    return out;
  } finally {
    chart.dispose();
  }
}

// ---------- layers: zlevel and blendMode ----------
// each picked element's zlevel, style.blend and place in the display list;
// a label's (its textContent's) zlevel
const LAYERS = [
  { id: 'zlevel', note: "series 0 at zlevel 1 (z 2) over series 1 at zlevel 0 z 10 (overlapping bars), its labels with it; series 1's markPoint at its own zlevel 2",
    option: { xAxis: CAT, yAxis: VAL, series: [
      { type: 'bar', zlevel: 1, barGap: '-100%', label: { show: true }, data: [5, 7, 3] },
      { type: 'bar', z: 10, label: { show: true }, data: [4, 8, 2], markPoint: { zlevel: 2, data: [{ type: 'max' }] } }] } },
  { id: 'blend', note: "lines-ny's blendMode 'lighter' on a bar series: every bar, not its labels; the other series none",
    option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', blendMode: 'lighter', label: { show: true }, data: [5, 7, 3] },
      { type: 'bar', data: [4, 8, 2] }] } },
  { id: 'rootLevel', note: "the root's zlevel 3 reaches a series that writes none (the series model's parent is the option)",
    option: { zlevel: 3, xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', data: [5, 7, 3] }] } },
];
function runLayers(c) {
  const chart = mk(600, 400);
  try {
    chart.setOption(Object.assign({ animation: false }, c.option));
    chart.renderToSVGString();
    refresh(chart);
    const list = chart.getZr().storage.getDisplayList(true);
    const at = el => list.indexOf(el);
    const items = [];
    eachItem(chart, 'bar', (sm, d, v, i, el) => {
      items.push({ role: 'bar', s: sm.seriesIndex, i, zlevel: el.zlevel, blend: el.style.blend == null ? null : String(el.style.blend), order: at(el) });
      const t = el.getTextContent && el.getTextContent();
      if (t) items.push({ role: 'label', s: sm.seriesIndex, i, zlevel: t.zlevel, blend: t.style.blend == null ? null : String(t.style.blend), order: at(t) });
    });
    const marks = [];
    (chart._componentsViews || []).forEach(v => {
      if (!v || v.type !== 'markPoint') return;
      v.group.traverse(el => { if (!el.isGroup && el.type !== 'text') marks.push({ role: 'markPoint', zlevel: el.zlevel, order: at(el) }); });
    });
    return { id: c.id, note: c.note, option: c.option, items, marks };
  } finally {
    chart.dispose();
  }
}

// ---------- a state's shadow tweening (state-anim.js' clock) ----------
// set at T0 and settled (a frame every 250 ms to 5 s); at T1 = T0 + 10000 the
// events of each sample t (ms after T1), then NOW = T1 + t and one frame; the
// bar's style shadow keys at every sample
const ANIM_SAMPLES = [0, 1, 50, 150, 299, 300, 301, 500, 501, 650, 799, 800, 801];
const ANIM = [
  { id: 'emphasisTween', note: "a bar's emphasis.itemStyle shadow (blur 10, offsetY 4, rgba(0,0,0,0.5)) by a highlight at 0 and a downplay at 500: stateAnimation's 300 ms cubicOut from the rest's prototype 0, 0, '#000' and back",
    option: { color: ['#5470c6'], xAxis: CAT, yAxis: { type: 'value', max: 10 },
      series: [{ type: 'bar', emphasis: { itemStyle: { shadowBlur: 10, shadowOffsetY: 4, shadowColor: 'rgba(0,0,0,0.5)' } }, data: [5, 7, 3] }] },
    events: [{ at: 0, payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } }, { at: 500, payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'restTween', note: "a bar's own shadow (blur 4, #ff0000) under an emphasis shadow (blur 12): from 4 to 12 in the bar's colour, the emphasis naming none",
    option: { color: ['#5470c6'], xAxis: CAT, yAxis: { type: 'value', max: 10 },
      series: [{ type: 'bar', itemStyle: { shadowBlur: 4, shadowColor: '#ff0000' }, emphasis: { itemStyle: { shadowBlur: 12 } }, data: [5, 7, 3] }] },
    events: [{ at: 0, payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } }, { at: 500, payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'colourTween', note: "a bar's own shadow (blur 4, #ff0000) under an emphasis one of its own colour (blur 12, #0000ff): the colour tweens red to blue and back",
    option: { color: ['#5470c6'], xAxis: CAT, yAxis: { type: 'value', max: 10 },
      series: [{ type: 'bar', itemStyle: { shadowBlur: 4, shadowColor: '#ff0000' }, emphasis: { itemStyle: { shadowBlur: 12, shadowColor: '#0000ff' } }, data: [5, 7, 3] }] },
    events: [{ at: 0, payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } }, { at: 500, payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] },
];
function runAnimCase(c) {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
  chart._ssr = false;
  try {
    chart.setOption(c.option);
    const zr = chart.getZr();
    for (let t = 16; t <= 5000; t += 250) {
      NOW = T0 + t;
      zr.animation.update();
    }
    const t1 = T0 + 10000;
    const samples = ANIM_SAMPLES.map(t => {
      NOW = t1 + t;
      c.events.filter(e => e.at === t).forEach(e => chart.dispatchAction(e.payload));
      NOW = t1 + t;
      zr.animation.update();
      zr.storage.getDisplayList(true);
      const el = chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(1);
      const st = el.style;
      const v = k => (typeof st[k] === 'number' ? hex(st[k]) : null);
      return { t, blur: v('shadowBlur'), ox: v('shadowOffsetX'), oy: v('shadowOffsetY'),
        color: st.shadowColor == null ? null : String(st.shadowColor), states: el.currentStates.join(',') };
    });
    return { id: c.id, note: c.note, option: c.option, events: c.events, samples };
  } finally {
    chart.dispose();
  }
}

function runCase(c) {
  const chart = mk(600, 400);
  try {
    chart.setOption(Object.assign({ animation: false }, c.option));
    chart.renderToSVGString();
    refresh(chart);
    const items = [];
    c.pick.forEach(p => PICK[p](chart, items));
    const out = { id: c.id, note: c.note, option: c.option, items };
    if (c.highlight) {
      chart.dispatchAction(Object.assign({ type: 'highlight' }, c.highlight));
      // the 'frame' event runs echarts' _onframe: applyChangedStates turns the
      // flags into state lists
      chart.getZr().animation.update();
      chart.renderToSVGString();
      refresh(chart);
      const hi = [];
      c.pick.forEach(p => PICK[p](chart, hi));
      out.highlight = c.highlight;
      out.highlighted = hi;
    }
    return out;
  } finally {
    chart.dispose();
  }
}

function generate() {
  return {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
    cases: CASES.map(runCase),
    whole: WHOLE.map(runWhole),
    layers: LAYERS.map(runLayers),
    anim: ANIM.map(runAnimCase),
    maps: [{ name: 'r5ashadow', text: JSON.stringify(MAPJSON) }],
  };
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const cs = id => out1.cases.find(c => c.id === id);
const find = (arr, role, s, i, sub) => arr.find(r => r.role === role && r.s === s && r.i === i && (sub == null || r.sub === sub));
const sh = r => (r ? [num(r.blur), num(r.ox), num(r.oy), r.color] : null);
const wh = id => out1.whole.find(c => c.id === id).shadows;
const ly = id => out1.layers.find(c => c.id === id);
const an = id => out1.anim.find(c => c.id === id).samples;
const at = (id, t) => an(id).find(q => q.t === t);
const guards = [
  { name: 'emphasisTween: 0 at rest, between at 150, 10 from 300, back to 0 from 800', ok: num(at('emphasisTween', 0).blur) === 0
    && num(at('emphasisTween', 150).blur) > 0 && num(at('emphasisTween', 150).blur) < 10 && num(at('emphasisTween', 301).blur) === 10
    && num(at('emphasisTween', 801).blur) === 0 },
  { name: 'colourTween: red at rest, between at 150, blue from 301, red again from 801', ok: at('colourTween', 0).color === '#ff0000'
    && /^rgba\(/.test(at('colourTween', 150).color) && at('colourTween', 150).color !== 'rgba(0,0,255,1)'
    && /^(#0000ff|rgba\(0,0,255,1\))$/.test(at('colourTween', 301).color) && /^(#ff0000|rgba\(255,0,0,1\))$/.test(at('colourTween', 801).color) },
  { name: 'restTween: from 4 to 12 in #ff0000', ok: num(at('restTween', 0).blur) === 4 && num(at('restTween', 301).blur) === 12
    && at('restTween', 301).color === '#ff0000' },
  { name: 'map: the regions, B its own colour, then B blur 9', ok: wh('map').length === 2 && out1.whole.find(c => c.id === 'map').highlighted.some(r => num(r.blur) === 9 && r.color === '#00ff00')
    && wh('geo').length === 1 },
  { name: 'markers: the three blocks', ok: ['#112233', '#223344', '#334455'].every(c => wh('markers').some(r => r.color === c)) },
  { name: 'matrix: background, cells and the divider; the border none', ok: ['#ff0000', '#00ff00', '#0000ff'].every(c => wh('matrix').some(r => r.color === c)) && wh('matrix').length === 3 },
  { name: 'dataZoom: four shadows', ok: ['#ff0000', '#00ff00', '#0000ff', '#ff00ff'].every(c => wh('dataZoom').some(r => r.color === c)) },
  { name: 'toolbox, graphic, legend, visualMap', ok: wh('toolbox').some(r => r.color === '#ff0000') && wh('graphic').length === 2
    && wh('legend').some(r => r.color === '#123456') && wh('visualMap').some(r => r.color === '#ff0000') },
  { name: 'zlevel: series 0 and its labels at 1, after series 1 (z 10); the markPoint at 2', ok: ly('zlevel').items.filter(r => r.s === 0).every(r => r.zlevel === 1)
    && ly('zlevel').items.filter(r => r.s === 1).every(r => r.zlevel === 0)
    && Math.min(...ly('zlevel').items.filter(r => r.s === 0 && r.role === 'bar').map(r => r.order)) > Math.max(...ly('zlevel').items.filter(r => r.s === 1 && r.role === 'bar').map(r => r.order))
    && ly('zlevel').marks.length > 0 && ly('zlevel').marks.every(r => r.zlevel === 2) },
  { name: "blend: series 0's bars 'lighter', its labels not, series 1 none", ok: ly('blend').items.filter(r => r.s === 0 && r.role === 'bar').every(r => r.blend === 'lighter')
    && ly('blend').items.filter(r => r.role === 'label').every(r => r.blend !== 'lighter') && ly('blend').items.filter(r => r.s === 1).every(r => r.blend === null) },
  { name: 'rootLevel: the root zlevel 3 on the bars', ok: ly('rootLevel').items.filter(r => r.role === 'bar').every(r => r.zlevel === 3) },
  { name: "bar: the series' shadow, item 1 its own oy 5 and #ff0000 over it", ok: JSON.stringify(sh(find(cs('bar').items, 'bar', 0, 0))) === '[10,2,3,"rgba(0, 0, 0, 0.5)"]'
    && JSON.stringify(sh(find(cs('bar').items, 'bar', 0, 1))) === '[10,2,5,"#ff0000"]' && num(find(cs('bar').items, 'bar', 0, 2).blur) === 10 },
  { name: "bar: a blur alone leaves the colour the prototype's", ok: find(cs('bar').items, 'bar', 1, 0).color === '#000' && num(find(cs('bar').items, 'bar', 1, 0).blur) === 6 },
  { name: 'barEmphasis: nothing at rest, the blur once highlighted', ok: num(find(cs('barEmphasis').items, 'bar', 0, 1).blur) === 0
    && num(find(cs('barEmphasis').highlighted, 'bar', 0, 1).blur) === 10 && num(find(cs('barEmphasis').highlighted, 'bar', 0, 0).blur) === 0 },
  { name: 'line: the polyline its lineStyle, the area its areaStyle, a symbol its itemStyle', ok: num(find(cs('line').items, 'lineRun', 0, -1).oy) === 8
    && num(find(cs('line').items, 'lineArea', 0, -1).blur) === 5 && num(find(cs('line').items, 'lineSymbol', 0, 0).blur) === 3
    && find(cs('line').items, 'lineSymbol', 0, 2).color === '#ff0000' },
  { name: 'scatter: the effect symbol has it, its ripples not', ok: num(find(cs('scatter').items, 'effectSymbol', 1, 0).blur) === 10
    && cs('scatter').items.filter(r => r.role === 'ripple').every(r => num(r.blur) === 0) && cs('scatter').items.some(r => r.role === 'ripple') },
  { name: 'pie: item 0 its 200, the others none; every label line its labelLine.lineStyle', ok: num(find(cs('pie').items, 'sector', 0, 0).blur) === 200
    && num(find(cs('pie').items, 'sector', 0, 1).blur) === 0 && cs('pie').items.filter(r => r.role === 'guide').length === 3
    && cs('pie').items.filter(r => r.role === 'guide').every(r => num(r.blur) === 4) },
  { name: 'pieEmphasis: the highlighted slice blur 10', ok: num(find(cs('pieEmphasis').highlighted, 'sector', 0, 0).blur) === 10 && num(find(cs('pieEmphasis').items, 'sector', 0, 0).blur) === 0 },
  { name: 'gauge: every part as its block says', ok: ['gaugeBand', 'gaugeSplit', 'gaugeTick', 'gaugeAnchor', 'gaugePointer', 'gaugeProgress'].every(k => cs('gauge').items.some(r => r.role === k))
    && cs('gauge').items.filter(r => r.role === 'gaugeBand').every(r => num(r.blur) === 15)
    && cs('gauge').items.filter(r => r.role === 'gaugeSplit').every(r => num(r.blur) === 3)
    && cs('gauge').items.filter(r => r.role === 'gaugeTick').every(r => num(r.oy) === -10)
    && num(find(cs('gauge').items, 'gaugePointer', 0, 0).blur) === 8 && num(find(cs('gauge').items, 'gaugePointer', 0, 1).blur) === 20
    && find(cs('gauge').items, 'gaugeProgress', 0, 0).color === 'rgba(0,138,255,0.45)' },
  { name: 'radar: line, area, symbols', ok: num(find(cs('radar').items, 'radarLine', 0, 0).blur) === 4 && num(find(cs('radar').items, 'radarArea', 0, 0).blur) === 10
    && num(find(cs('radar').items, 'radarSymbol', 0, 0, 0).blur) === 2 && find(cs('radar').items, 'radarLine', 0, 1).color === '#f00' },
  { name: 'boxEmphasis: the default emphasis shadow', ok: JSON.stringify(sh(find(cs('boxEmphasis').highlighted, 'boxplot', 0, 1))) === '[5,1,1,"rgba(0,0,0,0.2)"]'
    && num(find(cs('boxEmphasis').items, 'boxplot', 0, 1).blur) === 0 },
  { name: 'heatEmphasis: rest 2, highlighted 10', ok: num(find(cs('heatEmphasis').items, 'heat', 0, 1).blur) === 2 && num(find(cs('heatEmphasis').highlighted, 'heat', 0, 1).blur) === 10 },
  { name: "graph: the category's colour, the node's own blur, the link's own offset", ok: find(cs('graph').items, 'node', 0, 1).color === '#00f'
    && num(find(cs('graph').items, 'node', 0, 2).blur) === 1 && num(find(cs('graph').items, 'edge', 0, 1).oy) === 4 && num(find(cs('graph').items, 'edge', 0, 0).blur) === 3 },
  { name: 'tree, treemap, sunburst, sankey carry theirs', ok: cs('tree').items.some(r => r.role === 'treeEdge' && num(r.ox) === 2)
    && cs('treemap').items.some(r => r.color === '#f00') && cs('sunburst').items.some(r => num(r.blur) === 8)
    && cs('sankey').items.some(r => r.role === 'sankeyEdge' && num(r.oy) === 2) && cs('sankey').items.some(r => r.role === 'sankeyNode' && num(r.blur) === 3) },
  { name: "chord: the nodes' blur 4, a's offset 3; the links' blur 6, link 1 its offset 5", ok: cs('chord').items.filter(r => r.role === 'chordNode').length === 3
    && cs('chord').items.filter(r => r.role === 'chordNode').every(r => num(r.blur) === 4) && num(find(cs('chord').items, 'chordNode', 0, 0).ox) === 3
    && cs('chord').items.filter(r => r.role === 'chordEdge').length === 2 && cs('chord').items.filter(r => r.role === 'chordEdge').every(r => num(r.blur) === 6)
    && num(find(cs('chord').items, 'chordEdge', 0, 1).oy) === 5 && num(find(cs('chord').items, 'chordEdge', 0, 0).oy) === 0 },
  { name: 'river: the highlighted layer blur 20', ok: cs('river').highlighted.some(r => num(r.blur) === 20) && cs('river').items.every(r => num(r.blur) === 0) },
  { name: 'parallel and lines', ok: cs('parallelLines').items.some(r => r.role === 'parallel' && num(r.ox) === 3) && cs('parallelLines').items.some(r => r.role === 'lines' && num(r.blur) === 7) },
  { name: 'pictorial glyphs and polar bars', ok: cs('pictorialPolar').items.some(r => r.role === 'glyph' && num(r.blur) === 5) && cs('pictorialPolar').items.some(r => r.role === 'polarBar' && num(r.blur) === 6) },
  { name: "richText: token a's TSpan its shadow, b's none, a blur of 0 none", ok: cs('richText').items.some(r => r.role === 'span' && r.text === 'Ab' && num(r.blur) === 2 && num(r.oy) === 1 && r.color === '#000')
    && cs('richText').items.some(r => r.role === 'span' && r.text === 'Cd' && num(r.blur) === 0)
    && cs('richText').items.filter(r => r.role === 'span' && r.s === 1).every(r => num(r.blur) === 0 && num(r.ox) === 0) },
];
out1.guards = guards.map(g => ({ name: g.name, ok: !!g.ok }));
out1.cases.forEach(c => console.log(c.id + ': ' + c.items.length + ' elements' + (c.highlighted ? ', highlighted ' + c.highlighted.length : '')));
out1.anim.forEach(c => console.log('anim ' + c.id + ': ' + JSON.stringify(c.samples.map(q => [q.t, q.blur && num(q.blur), q.oy && num(q.oy), q.color, q.states]))));
out1.whole.forEach(c => console.log('whole ' + c.id + ': ' + JSON.stringify(c.shadows.map(r => [num(r.blur), num(r.ox), num(r.oy), r.color]))));
out1.layers.forEach(c => console.log('layers ' + c.id + ': ' + JSON.stringify(c.items.map(r => [r.role, r.s, r.i, r.zlevel, r.blend, r.order])) + ' marks ' + JSON.stringify(c.marks)));
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
const final = JSON.stringify(out1, null, 1) + '\n';
if (bad.length || json1 !== json2 || final.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, final);
console.log('wrote', OUT);
process.exit(0);
