/*
Upstream's own answers for fix batch R7-T (spec section 274): THE STYLE OF A
LEGEND ICON'S PATHS, as LegendView.getLegendStyle resolves it and the icon
builders set it.

  - getLegendStyle: the legend item's itemStyle (getItemStyle) and lineStyle
    (getLineStyle) models -- the item's over the legend's, over the
    LegendModel defaults: itemStyle {color, opacity, borderColor, borderCap,
    borderJoin, borderDashOffset, borderMiterLimit: 'inherit', borderWidth:
    'auto'}, lineStyle {width: 'auto', color, opacity, type, cap, join,
    dashOffset, miterLimit: 'inherit', inactiveColor, inactiveWidth 2}.
    Every key that reads 'inherit' takes the visual's (lineStyle: the
    series' `legendLineStyle` visual -- a line's lineStyle, its colour the
    data's fill when none is written; itemStyle: the `style` visual), fill
    from the visual's drawType key, stroke from its brush key ('fill' for an
    empty icon), opacity from the line visual for a stroke-drawn series;
    width 'auto' 2 where the visual has a width above nought, else 0;
    colour 'auto' the visual's fill. Unselected: itemStyle fill
    inactiveColor, stroke inactiveBorderColor, its width 2 / 0 under
    inactiveBorderWidth 'auto'; lineStyle stroke lineStyle.inactiveColor,
    width lineStyle.inactiveWidth -- the rest (dash, cap, opacity, shadow)
    kept.
  - LineSeries.getLegendIcon: a 'line' symbol across the box at its middle,
    setStyle(lineStyle); the marker (0.8 of itemHeight) setStyle(itemStyle),
    an empty one stroked in its fill, filled white, width 2.
  - getDefaultLegendIcon: the icon in the whole box, setStyle(itemStyle),
    the same empty rule.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off). For legend 0 each item group's icon paths are read in
order: the shape's global bounding rect and the style as the canvas would
take it (fill, stroke as a string or the gradient's JSON, lineWidth,
opacity, the dash normalised as canvas/dashStyle does, dashOffset, cap,
join, miterLimit, the shadow).

[R7-U, appended: the cases above are unchanged] the root's itemStyle and
lineStyle: the legend's own models and a line's legendLineStyle climb to
them (root.blocks, root.own).

  node tools/advchart-oracle/legend-styles.js

writes tests/fixtures/advchart-legend-styles.json (ORACLE_OUT overrides);
generated twice in the process, byte-identical; ends with process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option,
        items[] {name, hit [4 hex], paths [{rect [4 hex], fill, stroke,
                 strokeGrad, lineWidth (hex), opacity (hex|null), dash
                 [hex]|null, dashOffset (hex|null), cap, join, miter
                 (hex|null), shadowBlur (hex|null), shadowColor,
                 shadowOffsetX, shadowOffsetY (hex|null)}]}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-legend-styles.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function fh(h) { for (let i = 0; i < 8; i++) bits.setUint8(i, parseInt(h.substr(i * 2, 2), 16)); return bits.getFloat64(0); }
const clone = o => JSON.parse(JSON.stringify(o));
const hexOrNull = v => (v == null ? null : hex(+v));

const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const cats = ['a', 'b', 'c', 'd'];
function chart(series, legend) {
  return { animation: false, color: PALETTE, legend: Object.assign({ top: 10 }, legend || {}),
    xAxis: { type: 'category', data: cats }, yAxis: {}, series };
}
function pie(data, extra, legend) {
  return { animation: false, color: PALETTE, legend: Object.assign({ top: 10 }, legend || {}),
    series: [Object.assign({ type: 'pie', radius: '40%', center: ['50%', '60%'], data }, extra || {})] };
}
const L = (name, extra) => Object.assign({ type: 'line', name, data: [3, 5, 2, 4] }, extra || {});
const B = (name, extra) => Object.assign({ type: 'bar', name, data: [3, 5, 2, 4] }, extra || {});
const S = (name, extra) => Object.assign({ type: 'scatter', name, data: [3, 5, 2, 4] }, extra || {});
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0,
  colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };

const CASES = [
  // ---- a line series' own icon: the rule's lineStyle ----
  { id: 'rule.color', note: "a line's lineStyle.color: the rule in it, the marker in the data's colour",
    option: chart([L('A', { lineStyle: { color: '#ff0000' } }), L('B')]) },
  { id: 'rule.color.item', note: "itemStyle.color only: the line visual's stroke is the data's fill",
    option: chart([L('A', { itemStyle: { color: '#00aa00' } }), L('B', { itemStyle: { color: '#00aa00' }, lineStyle: { color: '#aa00aa' } })]) },
  { id: 'rule.width', note: "lineStyle.width 6 and 0: 'auto' is 2 where the series' width is above 0, else 0",
    option: chart([L('A', { lineStyle: { width: 6 } }), L('B', { lineStyle: { width: 0 } })]) },
  { id: 'rule.width.inherit', note: "legend lineStyle.width 'inherit': the series' own width",
    option: chart([L('A', { lineStyle: { width: 6 } }), L('B')], { lineStyle: { width: 'inherit' } }) },
  { id: 'rule.width.legend', note: 'legend lineStyle.width 5; an item\'s own 1',
    option: chart([L('A'), L('B')], { lineStyle: { width: 5 }, data: [{ name: 'A', lineStyle: { width: null } }, { name: 'B', lineStyle: { width: 1 } }] }) },
  { id: 'rule.item.inherit', note: "an item's lineStyle color / width 'inherit' over the legend's: the series' again",
    option: chart([L('A'), L('B', { lineStyle: { width: 6, color: '#ff0000' } })],
      { lineStyle: { color: '#00ff00', width: 4 }, data: ['A', { name: 'B', lineStyle: { color: 'inherit', width: 'inherit' } }] }) },
  { id: 'rule.none', note: "an item's lineStyle.color 'none': no rule (its path still in the group's rect)",
    option: chart([L('A'), L('B')], { data: ['A', { name: 'B', lineStyle: { color: 'none' } }] }) },
  { id: 'rule.color.empty', note: "a series' lineStyle.color '' (falsy): the line visual's stroke is the data's fill",
    option: chart([L('A', { lineStyle: { color: '' } }), L('B')]) },
  { id: 'rule.two.legends', note: "two legends, the second unselecting A: the series is filtered, so legend 0's selected A has an empty line visual -- no rule colour, no rule",
    option: { animation: false, color: PALETTE, legend: [{ top: 10, selected: { A: true } }, { bottom: 10, selected: { A: false } }],
      xAxis: { type: 'category', data: cats }, yAxis: {}, series: [L('A', { lineStyle: { type: 'dashed' } }), L('B')] } },
  { id: 'rule.two.legends.width', note: "the same, legend 0 writing lineStyle.width 4: the rule has a width and still no colour -- not drawn",
    option: { animation: false, color: PALETTE, legend: [{ top: 10, selected: { A: true }, lineStyle: { width: 4 } }, { bottom: 10, selected: { A: false } }],
      xAxis: { type: 'category', data: cats }, yAxis: {}, series: [L('A'), L('B')] } },
  { id: 'rule.dash', note: "lineStyle.type dashed, dotted, [6, 3] with dashOffset 2: inherited, dashed in the rule's width",
    option: chart([L('A', { lineStyle: { type: 'dashed' } }), L('B', { lineStyle: { type: 'dotted' } }),
      L('C', { lineStyle: { type: [6, 3], dashOffset: 2 } })]) },
  { id: 'rule.dash.wide', note: "dashed under legend width 'inherit' (a 6 px line): the dash in 6s",
    option: chart([L('A', { lineStyle: { type: 'dashed', width: 6 } }), L('B', { lineStyle: { type: 4 } })], { lineStyle: { width: 'inherit' } }) },
  { id: 'rule.cap', note: 'lineStyle cap round / square, join bevel, miterLimit 4: inherited',
    option: chart([L('A', { lineStyle: { cap: 'round', join: 'bevel', miterLimit: 4 } }), L('B', { lineStyle: { cap: 'square', join: 'round' } })]) },
  { id: 'rule.opacity', note: "lineStyle.opacity 0.4: the rule's; itemStyle.opacity 0.7: the marker's",
    option: chart([L('A', { lineStyle: { opacity: 0.4 }, itemStyle: { opacity: 0.7 } }), L('B', { itemStyle: { opacity: 0.3 } })]) },
  { id: 'rule.shadow.series', note: "a series' lineStyle shadow: not inherited (the legend's lineStyle names no shadow key)",
    option: chart([L('A', { lineStyle: { shadowBlur: 8, shadowColor: '#ff0000', shadowOffsetX: 3 } }), L('B')]) },
  { id: 'rule.shadow.legend', note: "legend lineStyle shadow: the rule's",
    option: chart([L('A'), L('B')], { lineStyle: { shadowBlur: 6, shadowColor: '#0000ff', shadowOffsetX: 2, shadowOffsetY: 3 } }) },
  { id: 'rule.shadow.inherit', note: "legend lineStyle shadow keys 'inherit': the series'",
    option: chart([L('A', { lineStyle: { shadowBlur: 8, shadowColor: '#ff0000', shadowOffsetY: 4 } }), L('B')],
      { lineStyle: { shadowBlur: 'inherit', shadowColor: 'inherit', shadowOffsetY: 'inherit' } }) },
  { id: 'rule.legend.color', note: "legend lineStyle.color; an item's own over it",
    option: chart([L('A', { lineStyle: { color: '#ff0000' } }), L('B')],
      { lineStyle: { color: '#00ff00' }, data: ['A', { name: 'B', lineStyle: { color: '#ff00ff' } }] }) },
  { id: 'rule.legend.auto', note: "legend lineStyle.color 'auto': the style visual's fill, not the line's colour",
    option: chart([L('A', { lineStyle: { color: '#ff0000' } }), L('B', { itemStyle: { color: '#008800' }, lineStyle: { color: '#ff0000' } })],
      { lineStyle: { color: 'auto' } }) },
  { id: 'rule.legend.keys', note: 'legend lineStyle type / cap / opacity written: over the series\'',
    option: chart([L('A', { lineStyle: { type: 'dotted', opacity: 0.2 } }), L('B')],
      { lineStyle: { type: 'dashed', cap: 'round', opacity: 0.6, dashOffset: 3 } }) },
  { id: 'rule.inactive', note: "unselected from the start: the rule in lineStyle.inactiveColor at inactiveWidth 2; a filtered series has no legendLineStyle visual, so every 'inherit' key reads nothing (no dash, no opacity)",
    option: chart([L('A', { lineStyle: { type: 'dashed', width: 6, opacity: 0.5, color: '#ff0000' } }), L('B')],
      { selected: { A: false } }) },
  { id: 'rule.inactive.toggled', note: "unselected by legendToggleSelect after a first render: the series' data keeps the visual it had",
    option: chart([L('A', { lineStyle: { type: 'dashed', width: 6, opacity: 0.5, color: '#ff0000', cap: 'round' } }), L('B')]),
    actions: [{ type: 'legendToggleSelect', name: 'A' }] },
  { id: 'rule.inactive.back', note: 'unselected from the start, then selected again: the visual as selected',
    option: chart([L('A', { lineStyle: { type: 'dashed', opacity: 0.5, color: '#ff0000' } }), L('B')], { selected: { A: false } }),
    actions: [{ type: 'legendToggleSelect', name: 'A' }] },
  { id: 'rule.inactive.custom', note: 'lineStyle inactiveColor / inactiveWidth, inactiveColor / inactiveBorderColor written',
    option: chart([L('A', { symbol: 'circle', itemStyle: { borderWidth: 2, borderColor: '#000000' } }), L('B')],
      { selected: { A: false, B: false }, inactiveColor: '#abcdef', inactiveBorderColor: '#fedcba',
        lineStyle: { inactiveColor: '#123456', inactiveWidth: 4 },
        data: ['A', { name: 'B', lineStyle: { inactiveWidth: 1, inactiveColor: '#654321' } }] }) },
  { id: 'rule.gradient', note: 'a gradient lineStyle.color: the rule stroked with it',
    option: chart([L('A', { lineStyle: { color: GRAD } }), L('B')]) },
  { id: 'marker.gradient', note: "a gradient itemStyle.color: the rule (the data's fill) and an empty marker's ring stroked with it",
    option: chart([L('A', { itemStyle: { color: GRAD } }), S('B', { symbol: 'emptyCircle', itemStyle: { color: GRAD } })]) },
  { id: 'rule.icon.word', note: "legend icon 'rect': the default icon, no rule; data icon 'inherit': the line's own",
    option: chart([L('A', { lineStyle: { color: '#ff0000' } }), L('B', { lineStyle: { color: '#ff0000' } })],
      { icon: 'rect', data: ['A', { name: 'B', icon: 'inherit' }] }) },
  { id: 'rule.icon.line', note: "icon 'line' on a line series: the default icon's line symbol, styled by itemStyle",
    option: chart([L('A', { lineStyle: { color: '#ff0000' } }), L('B', { itemStyle: { borderWidth: 3, borderColor: '#333333' } })],
      { icon: 'line' }) },
  // ---- the marker: itemStyle ----
  { id: 'marker.border', note: "a filled marker with the series' border: 'auto' width 2, borderColor inherited; an empty one ringed in its fill",
    option: chart([L('A', { symbol: 'circle', itemStyle: { borderWidth: 3, borderColor: '#000000' } }),
      L('B', { itemStyle: { borderWidth: 3, borderColor: '#000000' } }), L('C', { symbol: 'rect' })]) },
  { id: 'marker.legend', note: 'legend itemStyle color / borderColor / borderWidth / opacity written',
    option: chart([L('A', { symbol: 'circle' }), B('B'), L('C')],
      { itemStyle: { color: '#ff8800', borderColor: '#333333', borderWidth: 1, opacity: 0.5 } }) },
  { id: 'marker.keys', note: "itemStyle cap / join / dashOffset / miterLimit inherited; borderType not (no 'inherit' default)",
    option: chart([L('A', { symbol: 'rect', itemStyle: { borderWidth: 2, borderColor: '#000000', borderType: 'dashed',
      borderCap: 'round', borderJoin: 'bevel', borderDashOffset: 3, borderMiterLimit: 5 } }),
      B('B', { itemStyle: { borderWidth: 2, borderColor: '#000000', borderType: 'dashed', borderCap: 'square', borderJoin: 'round' } })]) },
  { id: 'marker.item.inherit', note: "an item's itemStyle color / opacity 'inherit' over the legend's: the series' again",
    option: chart([B('A'), B('B', { itemStyle: { opacity: 0.6 } }), L('C', { symbol: 'circle' })],
      { itemStyle: { color: '#ff8800', opacity: 0.5 }, data: ['A', { name: 'B', itemStyle: { color: 'inherit', opacity: 'inherit' } },
        { name: 'C', itemStyle: { color: 'inherit', opacity: 'inherit' } }] }) },
  { id: 'marker.shadow', note: "itemStyle shadow not inherited; legend itemStyle shadow applied",
    option: chart([B('A', { itemStyle: { shadowBlur: 5, shadowColor: '#ff0000' } }), L('B', { symbol: 'circle' })],
      { itemStyle: { shadowBlur: 4, shadowColor: '#00ff00', shadowOffsetX: 1 } }) },
  { id: 'marker.inherit.keys', note: "legend itemStyle borderType / shadowBlur 'inherit': the series'",
    option: chart([B('A', { itemStyle: { borderWidth: 2, borderColor: '#000000', borderType: 'dotted', shadowBlur: 5, shadowColor: '#ff0000' } }), B('B')],
      { itemStyle: { borderType: 'inherit', shadowBlur: 'inherit', shadowColor: 'inherit' } }) },
  // ---- the default icon: itemStyle only ----
  { id: 'bar.lineStyle', note: "legend lineStyle on bars: no effect -- the default icon reads itemStyle",
    option: chart([B('A'), B('B', { itemStyle: { borderWidth: 1, borderColor: '#000000' } })],
      { lineStyle: { color: '#ff0000', width: 4, type: 'dashed' } }) },
  { id: 'bar.icon.line', note: "icon 'line' on bars: stroked by itemStyle's stroke (the series' border) at 'auto' width",
    option: chart([B('A'), B('B', { itemStyle: { borderWidth: 1, borderColor: '#000000', borderCap: 'round' } })], { icon: 'line' }) },
  { id: 'bar.inactive', note: "an unselected bar with a border: inactiveColor fill, inactiveBorderColor at 2",
    option: chart([B('A', { itemStyle: { borderWidth: 1, borderColor: '#000000' } }), B('B')], { selected: { A: false, B: false } }) },
  { id: 'scatter.empty', note: "scatter emptyCircle / emptyRect icons: stroked in the fill at 2, filled white",
    option: chart([S('A', { symbol: 'emptyCircle' }), S('B', { symbol: 'emptyRect', itemStyle: { borderWidth: 4, borderColor: '#000000' } })], { icon: 'inherit' }) },
  { id: 'scatter.symbol', note: "scatter emptyCircle / emptyRect as the legendIcon visual: stroked in the fill at 2, filled white; the default opacity 0.8 inherited",
    option: chart([S('A', { symbol: 'emptyCircle' }), S('B', { symbol: 'emptyRect', itemStyle: { borderWidth: 4, borderColor: '#000000' } }),
      S('C', { symbol: 'diamond', itemStyle: { opacity: 0.4 } })]) },
  { id: 'series.color', note: "a line's series colour: the rule and the marker in it",
    option: chart([L('A', { color: '#ff00ff' }), L('B', { color: '#ff00ff', lineStyle: { color: '#00ffff' } })]) },
  { id: 'pie.border', note: 'a pie with a border: the slices\' icons',
    option: pie([{ name: 'P', value: 3 }, { name: 'Q', value: 5, itemStyle: { borderColor: '#000000', borderWidth: 3, opacity: 0.6 } }],
      { itemStyle: { borderWidth: 1, borderColor: '#ffffff' } }) },
  // ---- the same keys on the other series' default icons ----
  { id: 'lines.keys', note: "a lines series (drawn with its stroke): its style visual is its lineStyle -- cap, join, miterLimit inherited, opacity not (the line visual's, which a lines series has none of), its type not (borderType has no 'inherit' default)",
    option: { animation: false, color: PALETTE, legend: { top: 10 }, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', name: 'A', coordinateSystem: 'cartesian2d', data: [{ coords: [[0, 1], [2, 3]] }],
        lineStyle: { color: '#ff0000', width: 3, cap: 'round', join: 'bevel', miterLimit: 3, opacity: 0.5, type: 'dashed', shadowBlur: 4 } },
      { type: 'lines', name: 'B', coordinateSystem: 'cartesian2d', data: [{ coords: [[0, 2], [2, 1]] }], lineStyle: { width: 0 } }] } },
  { id: 'boxplot.keys', note: 'a boxplot (drawn with its stroke): borderCap / borderJoin inherited, opacity not',
    option: chart([{ type: 'boxplot', name: 'A', data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6], [1, 2, 3, 4, 5], [2, 3, 4, 5, 6]],
      itemStyle: { borderCap: 'round', borderJoin: 'bevel', opacity: 0.5 } }]) },
  { id: 'funnel.keys', note: "a funnel's default border (1 in the ground colour) and its borderJoin",
    option: { animation: false, color: PALETTE, legend: { top: 10 },
      series: [{ type: 'funnel', top: 60, data: [{ name: 'P', value: 3 }, { name: 'Q', value: 5, itemStyle: { borderJoin: 'bevel', opacity: 0.5 } }],
        itemStyle: { borderCap: 'square' } }] } },
  { id: 'marker.width.inherit', note: "legend itemStyle borderWidth 'inherit': the series' border width",
    option: chart([B('A', { itemStyle: { borderWidth: 5, borderColor: '#000000' } }), L('B', { symbol: 'rect', itemStyle: { borderWidth: 3, borderColor: '#ff0000' } })],
      { itemStyle: { borderWidth: 'inherit' } }) },
  { id: 'marker.auto', note: "legend itemStyle color / borderColor 'auto': the style visual's fill",
    option: chart([B('A', { itemStyle: { color: '#ff0000', borderWidth: 1, borderColor: '#000000' } }), L('B', { symbol: 'rect', itemStyle: { color: '#00ff00', borderWidth: 1, borderColor: '#000000' } })],
      { itemStyle: { color: 'auto', borderColor: 'auto' } }) },
  { id: 'marker.inactive.width', note: "inactiveBorderWidth 1 (not 'auto'): an unselected icon keeps the width its style resolved",
    option: chart([B('A', { itemStyle: { borderWidth: 1, borderColor: '#000000' } }), B('B'), L('C', { symbol: 'rect' })],
      { selected: { A: false, B: false, C: false }, inactiveBorderWidth: 1, itemStyle: { borderWidth: 3 } }) },
  { id: 'marker.inactive.legend.border', note: "unselected under inactiveBorderWidth 'auto': 2 where the series has a width and the resolved style a stroke -- the legend's borderColor counts",
    option: chart([B('A', { itemStyle: { borderWidth: 2 } }), B('B')], { selected: { A: false, B: false }, itemStyle: { borderColor: '#333333' } }) },
  { id: 'marker.opacity.odd', note: "legend itemStyle opacity '-Infinity' (a string): not a number the canvas takes -- drawn opaque",
    option: chart([B('A'), L('B', { symbol: 'circle' })], { itemStyle: { opacity: '-Infinity' } }) },
  { id: 'graph.category', note: "a graph's categories: the category's style visual under the legend style",
    option: { animation: false, color: PALETTE, legend: { top: 10, data: ['c1', 'c2'] },
      series: [{ type: 'graph', top: 60, categories: [{ name: 'c1', itemStyle: { opacity: 0.5, borderColor: '#000000', borderWidth: 2, borderCap: 'round' } }, { name: 'c2' }],
        data: [{ name: 'n1', category: 0, x: 0, y: 0 }, { name: 'n2', category: 1, x: 10, y: 10 }], layout: 'none' }] } },
  { id: 'line.empty.legend.width', note: "legend lineStyle.width 5 does not thicken an empty marker's ring",
    option: chart([L('A'), L('B', { symbol: 'emptyRect' })], { lineStyle: { width: 5 } }) },
  // ---- [R7-U] the root's style blocks: the legend's own models (their parent the GlobalModel) and a line's
  // legendLineStyle (getModel('lineStyle').getLineStyle) climb to them; the style visual does not ----
  { id: 'root.blocks', note: "the root's itemStyle and lineStyle: a line's rule takes its lineStyle (legendLineStyle), every icon "
      + "the legend's own itemStyle keys it has no default for (borderType, the shadow), no icon its colour or opacity",
    option: Object.assign(chart([L('A', { symbol: 'circle' }), L('B'), B('C'), S('D')]),
      { itemStyle: { color: '#ff0000', borderColor: '#00aa00', borderWidth: 3, opacity: 0.5, borderType: 'dashed',
        shadowBlur: 4, shadowColor: '#0000ff', shadowOffsetX: 2 },
        lineStyle: { color: '#aa00aa', width: 5, opacity: 0.6, type: 'dotted', cap: 'square', shadowBlur: 3,
          shadowColor: '#00ffff', shadowOffsetY: 2 } }) },
  { id: 'root.own', note: "the root's blocks under a series' and a legend's own keys: theirs win, key by key",
    option: Object.assign(chart([L('A', { symbol: 'circle', itemStyle: { borderColor: '#333333', borderWidth: 1 },
      lineStyle: { color: '#123456', shadowBlur: 1 } }), B('C', { itemStyle: { opacity: 0.9 } })],
      { itemStyle: { shadowBlur: 2, shadowColor: '#999999' }, lineStyle: { shadowOffsetX: 3 } }),
      { itemStyle: { borderType: 'dotted', shadowBlur: 4, shadowColor: '#0000ff' },
        lineStyle: { color: '#aa00aa', opacity: 0.6, shadowBlur: 3, shadowColor: '#00ffff' } }) },
];

function globalRect(el) {
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return r;
}
const rect4 = r => [r.x, r.y, r.width, r.height].map(hex);

function normDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : Array.isArray(lineType) ? lineType : null;
}

function colourOf(v) {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  return '#object';
}

function readPath(p) {
  const s = p.style;
  const out = { rect: rect4(globalRect(p)) };
  out.fill = colourOf(s.fill);
  out.stroke = colourOf(s.stroke);
  out.strokeGrad = (s.stroke && typeof s.stroke === 'object') ? clone({ type: s.stroke.type, x: s.stroke.x, y: s.stroke.y,
    x2: s.stroke.x2, y2: s.stroke.y2, colorStops: s.stroke.colorStops }) : null;
  out.lineWidth = hex(s.lineWidth == null ? 1 : +s.lineWidth);
  out.opacity = hexOrNull(s.opacity);
  const dash = normDash(s.lineDash, s.lineWidth);
  out.dash = dash ? dash.map(v => hex(+v)) : null;
  out.dashOffset = hexOrNull(s.lineDashOffset);
  out.cap = s.lineCap == null ? null : String(s.lineCap);
  out.join = s.lineJoin == null ? null : String(s.lineJoin);
  out.miter = hexOrNull(s.miterLimit);
  out.shadowBlur = hexOrNull(s.shadowBlur);
  out.shadowColor = s.shadowColor == null ? null : String(s.shadowColor);
  out.shadowOffsetX = hexOrNull(s.shadowOffsetX);
  out.shadowOffsetY = hexOrNull(s.shadowOffsetY);
  out.symbolType = p.shape && p.shape.symbolType != null ? String(p.shape.symbolType) : null;
  return out;
}

function readItems(chart) {
  const lm = chart.getModel().getComponent('legend', 0);
  const view = chart.getViewOfComponentModel(lm);
  const group = view.getContentGroup();
  const data = lm.getData();
  const out = [];
  group.eachChild((g, i) => {
    const kids = g.childrenRef();
    const paths = [];
    kids.forEach((k, j) => {
      if (k.type === 'text') return;
      if (j === kids.length - 1) return; // the hit rect
      if (k.isGroup) k.traverse(c => { if (!c.isGroup) paths.push(readPath(c)); });
      else paths.push(readPath(k));
    });
    const hit = kids[kids.length - 1];
    out.push({ name: data[i] ? data[i].get('name') : null, hit: rect4(globalRect(hit)), paths });
  });
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    chart.renderToSVGString();
    (c.actions || []).forEach(a => { chart.dispatchAction(clone(a)); chart.renderToSVGString(); });
    const rec = { id: c.id, note: c.note, option: clone(c.option) };
    if (c.actions) rec.actions = clone(c.actions);
    rec.items = readItems(chart);
    return rec;
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const P = (id, k, j) => by(id).items[k].paths[j];
  const guards = [
    { name: 'rule.color: the rule red, the marker in the palette', ok: () => P('rule.color', 0, 0).stroke === '#ff0000' && P('rule.color', 0, 1).stroke === PALETTE[0] },
    { name: 'rule.width: 2 and 0', ok: () => fh(P('rule.width', 0, 0).lineWidth) === 2 && fh(P('rule.width', 1, 0).lineWidth) === 0 },
    { name: 'rule.width.inherit: 6', ok: () => fh(P('rule.width.inherit', 0, 0).lineWidth) === 6 },
    { name: 'rule.dash: dashed [8, 4]', ok: () => P('rule.dash', 0, 0).dash && fh(P('rule.dash', 0, 0).dash[0]) === 8 },
    { name: 'rule.cap: round', ok: () => P('rule.cap', 0, 0).cap === 'round' },
    { name: 'rule.opacity: 0.4 on the rule', ok: () => fh(P('rule.opacity', 0, 0).opacity) === 0.4 },
    { name: 'rule.shadow.series: no shadow', ok: () => fh(P('rule.shadow.series', 0, 0).shadowBlur) === 0 },
    { name: 'rule.shadow.legend: blur 6', ok: () => fh(P('rule.shadow.legend', 0, 0).shadowBlur) === 6 },
    { name: 'rule.inactive: width 2, no dash', ok: () => fh(P('rule.inactive', 0, 0).lineWidth) === 2 && P('rule.inactive', 0, 0).dash === null },
    { name: 'rule.gradient: an object', ok: () => P('rule.gradient', 0, 0).stroke === '#object' },
    { name: 'rule.icon.word: one path for A, two for B', ok: () => by('rule.icon.word').items[0].paths.length === 1 && by('rule.icon.word').items[1].paths.length === 2 },
  ];
  for (const g of guards) {
    let ok = false;
    try { ok = !!g.ok(); } catch (e) { ok = false; }
    if (process.env.ORACLE_NOGUARD) continue;
    must(ok, 'guard failed: ' + g.name);
  }
  return { source: 'ECharts 6.1 dist: component/legend/LegendView.ts getLegendStyle / getDefaultLegendIcon, chart/line/LineSeries.ts getLegendIcon',
    W, H, cases, guards: guards.map(g => g.name) };
}

let code = 0;
try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  console.log('wrote ' + OUT);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  code = 1;
}
process.exit(code);
