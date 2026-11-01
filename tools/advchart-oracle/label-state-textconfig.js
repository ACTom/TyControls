/*
Upstream's own answers for fix batch R6-A (spec section 248): a series
label's STATE textConfig -- emphasis.label / select.label / blur.label
`position`, `distance`, `offset` and `rotate`, the series' and a data
item's.

  - setLabelStyle (label/labelStyle.ts) gives the host element, for every
    special state, `states[state].textConfig = createTextConfig(stateModel,
    opt, true)`: only the keys the state's label model (the item's
    [state].label over the series') writes -- position when truthy
    ('outside' is the host's defaultOutsidePosition), distance, offset,
    rotate (in radians) -- plus outsideFill.
  - zrender's Element._applyStateObj sets the host's textConfig to the
    normal one extended by the merged states' (select first, then emphasis
    or blur: echarts.ts applyElementStates) AT ONCE (no transition), and
    updateInnerText lays the label out by it on the host's rect: the anchor,
    the alignment the position implies, the turn, the offset inside the
    turn, and the inside / outside ink (`position` containing 'inside').
  - The normal textConfig is the one LabelManager left: its position and
    rotation as the series wrote them and its offset [dx || 0, dy || 0]
    (updateLayoutConfig) -- the normal label.offset is dropped.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off unless the case says; chart._ssr = false before setOption and
chart._onframe() after every step, the browser's model, so the states
apply). Every label of series 0 is read off the live elements after the
render and after every step.

  node tools/advchart-oracle/label-state-textconfig.js

writes tests/fixtures/advchart-label-state-textconfig.json (ORACLE_OUT
overrides); generated twice in the process, byte-identical; ends with
process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option, steps[] (dispatchAction payloads), states[]:
        the labels at rest, then after each step:
          {d, ignore, text, x, y (hex: the computed transform's
           translation), m ([4 hex]: its linear part), align, verticalAlign
           (the style's, else the host's default), rect ([4 hex]: the global
           bounding rect), fill (the ink painted, the first span's), inside
           (updateInnerText's isInside on the host's textConfig), fontSize}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-state-textconfig.json');
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
const clone = o => JSON.parse(JSON.stringify(o));

const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const HL = d => ({ type: 'highlight', seriesIndex: 0, dataIndex: d });
const DP = d => ({ type: 'downplay', seriesIndex: 0, dataIndex: d });
const SEL = d => ({ type: 'select', seriesIndex: 0, dataIndex: d });
// zrender's Draggable on a label: drift(dx, dy), then its 'drag' handler
const DRAG = (d, dx, dy) => ({ drag: d, dx, dy });
const EHL = d => ({ type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: d });
const EDP = d => ({ type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: d });

function bar(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: {},
    series: [Object.assign({ type: 'bar', data: [12, 30, 18, 25], label: { show: true, position: 'top' } }, series)] }, root || {});
}
function scatter(series, root) {
  return Object.assign({ animation: false, color: PALETTE, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [Object.assign({ type: 'scatter', symbolSize: 20, data: [[1, 1], [2, 3], [3, 2]] }, series)] }, root || {});
}
function line(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: {},
    series: [Object.assign({ type: 'line', data: [12, 30, 18, 25], label: { show: true } }, series)] }, root || {});
}

const CASES = [
  // ---- the R5-L leftover: scatter-alias, modern spelling ----
  { id: 'scatter.alias', note: "backward-compat scatter-alias: no series label; emphasis.label shows it on the right at 15px",
    option: scatter({ itemStyle: { opacity: 0.5, color: '#3366cc' },
      emphasis: { scale: false, itemStyle: { opacity: 1, borderColor: '#000', borderWidth: 2 },
        label: { show: true, position: 'right', color: '#ff0000', fontSize: 15 } } }), steps: [HL(1)] },
  { id: 'scatter.top.bottom', note: 'labels on top; emphasis.label position bottom, distance 12',
    option: scatter({ label: { show: true, position: 'top' },
      emphasis: { scale: false, label: { position: 'bottom', distance: 12 } } }), steps: [HL(2)] },
  { id: 'scatter.scaled', note: 'emphasis scale (the default 1.1? no: symbolSize 20 scales); label right in emphasis, inside at rest',
    option: scatter({ label: { show: true, formatter: 'p{@[1]}' },
      emphasis: { label: { position: 'right' } } }), steps: [HL(0)] },
  // ---- a bar's ----
  { id: 'bar.insideTop', note: 'labels on top; emphasis.label position insideTop: inside ink on the hovered bar',
    option: bar({ emphasis: { label: { position: 'insideTop' } } }), steps: [HL(1)] },
  { id: 'bar.offset.rotate', note: 'emphasis.label offset [10, -5] and rotate 30 over the top position; label.offset [4, 4] at rest',
    option: bar({ label: { show: true, position: 'top', offset: [4, 4] }, emphasis: { label: { offset: [10, -5], rotate: 30 } } }), steps: [HL(2)] },
  { id: 'bar.distance', note: 'emphasis.label distance 20 alone (position top kept)',
    option: bar({ emphasis: { label: { distance: 20 } } }), steps: [HL(0)] },
  { id: 'bar.item', note: "an item's own emphasis.label position right over the series' emphasis position bottom",
    option: bar({ emphasis: { label: { position: 'bottom' } },
      data: [12, { value: 30, emphasis: { label: { position: 'right' } } }, 18, 25] }), steps: [HL(1), DP(1), HL(0)] },
  { id: 'bar.outside.neg', note: "emphasis.label position 'outside' on a negative bar: below it; labels inside at rest",
    option: bar({ data: [12, -30, 18, -25], label: { show: true, position: 'inside' }, emphasis: { label: { position: 'outside' } } }), steps: [HL(1)] },
  { id: 'bar.array', note: 'emphasis.label position [10, "50%"]',
    option: bar({ emphasis: { label: { position: [10, '50%'] } } }), steps: [HL(3)] },
  { id: 'bar.rich', note: 'a rich label; emphasis.label position insideBottom',
    option: bar({ label: { show: true, position: 'top', formatter: '{a|{c}}', rich: { a: { color: '#333333', padding: [2, 4] } } },
      emphasis: { label: { position: 'insideBottom' } } }), steps: [HL(2)] },
  // ---- the other states ----
  { id: 'bar.select', note: 'select.label position bottom (selectedMode single)',
    option: bar({ selectedMode: 'single', select: { label: { position: 'insideBottom' } } }), steps: [SEL(1)] },
  { id: 'bar.select.emph', note: 'select.label position bottom, emphasis.label distance 15: selected then hovered, the two merged',
    option: bar({ selectedMode: 'single', select: { label: { position: 'bottom' } }, emphasis: { label: { distance: 15 } } }),
    steps: [SEL(1), HL(1), DP(1)] },
  { id: 'bar.blur', note: "emphasis focus self: the others blur, blur.label position insideTop",
    option: bar({ emphasis: { focus: 'self' }, blur: { label: { position: 'insideTop' } } }), steps: [HL(0)] },
  { id: 'bar.select.emph.same', note: 'select.label position bottom, emphasis.label position insideTop: selected then hovered, the hover\'s wins',
    option: bar({ selectedMode: 'single', select: { label: { position: 'bottom' } }, emphasis: { label: { position: 'insideTop' } } }),
    steps: [SEL(2), HL(2)] },
  { id: 'bar.item.chain', note: "the series' emphasis.label position bottom, an item's own distance 20: the item's chain has both",
    option: bar({ emphasis: { label: { position: 'bottom' } },
      data: [12, 30, { value: 18, emphasis: { label: { distance: 20 } } }, 25] }), steps: [HL(2)] },
  { id: 'bar.align', note: "label.align right; emphasis.label position insideTop: the style's alignment over the position's",
    option: bar({ label: { show: true, position: 'top', align: 'right' }, emphasis: { label: { position: 'insideTop' } } }), steps: [HL(1)] },
  { id: 'scatter.pin', note: "a pin symbol, label top; emphasis.label position inside: the pin's head (40 % of its height)",
    option: scatter({ symbol: 'pin', symbolSize: 30, label: { show: true, position: 'top' },
      emphasis: { scale: false, label: { position: 'inside' } } }), steps: [HL(1)] },
  { id: 'scatter.hollow.stroke', note: 'an unfilled symbol bordered 1, label right; emphasis border 8: the rect grows by the width, at least 5 with no fill',
    option: scatter({ itemStyle: { color: 'none', borderColor: '#000000', borderWidth: 1 }, label: { show: true, position: 'right' },
      emphasis: { scale: false, itemStyle: { borderWidth: 8 } } }), steps: [HL(1)] },
  // ---- R6-A2: labels a Line group or a curve carries ----
  { id: 'graph.edge', edges: true, note: 'graph edge labels (middle); emphasis.edgeLabel position top, distance 8: on the Line group\'s box',
    option: { animation: false, series: [{ type: 'graph', layout: 'none', edgeLabel: { show: true },
      emphasis: { edgeLabel: { position: 'top', distance: 8 } },
      data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 400, y: 300 }, { name: 'c', x: 100, y: 300 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] }] },
    steps: [EHL(0), EDP(0), EHL(1)] },
  { id: 'graph.edge.symbols', edges: true, note: 'edge symbols circle / arrow, emphasis lineStyle width 6; emphasis.edgeLabel position insideTopLeft',
    option: { animation: false, series: [{ type: 'graph', layout: 'none', edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: 12,
      edgeLabel: { show: true }, emphasis: { lineStyle: { width: 6 }, edgeLabel: { position: 'insideTopLeft' } },
      data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 400, y: 300 }], links: [{ source: 'a', target: 'b' }] }] },
    steps: [EHL(0)] },
  { id: 'graph.edge.word', edges: true, note: "emphasis.edgeLabel position 'end' (a Line word calculateTextPosition does not know): the box's corner",
    option: { animation: false, series: [{ type: 'graph', layout: 'none', edgeLabel: { show: true },
      emphasis: { edgeLabel: { position: 'end' } },
      data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 400, y: 300 }], links: [{ source: 'a', target: 'b' }] }] },
    steps: [EHL(0)] },
  { id: 'graph.edge.item', edges: true, note: "a link's own emphasis.label offset over the series' emphasis.edgeLabel position bottom",
    option: { animation: false, series: [{ type: 'graph', layout: 'none', edgeLabel: { show: true },
      emphasis: { edgeLabel: { position: 'bottom' } },
      data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 400, y: 300 }, { name: 'c', x: 100, y: 300 }],
      links: [{ source: 'a', target: 'b', emphasis: { label: { offset: [10, 4] } } }, { source: 'b', target: 'c' }] }] },
    steps: [EHL(0)] },
  { id: 'lines', note: 'lines labels (end); emphasis.label position top',
    option: { animation: false, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', label: { show: true, formatter: 'L' }, emphasis: { label: { position: 'top' } },
        data: [{ coords: [[1, 1], [5, 5]] }, { coords: [[6, 2], [9, 8]] }] }] }, steps: [HL(0)] },
  { id: 'sankey.edge', edges: true, note: 'sankey edge labels; emphasis.edgeLabel position top: on the curve\'s rect',
    option: { animation: false, series: [{ type: 'sankey', edgeLabel: { show: true }, emphasis: { edgeLabel: { position: 'top' } },
      data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }] }] }, steps: [EHL(1)] },
  { id: 'bar.word', note: "emphasis.label position 'foo' (no zrender name)",
    option: bar({ emphasis: { label: { position: 'foo' } } }), steps: [HL(1)] },
  { id: 'bar.layout.x', note: 'labelLayout x 100: the label at x 100; emphasis.label position bottom',
    option: bar({ labelLayout: { x: 100 }, emphasis: { label: { position: 'bottom' } } }), steps: [HL(1)] },
  { id: 'bar.layout.align', note: 'labelLayout align left, fontSize 16; emphasis.label position insideBottom',
    option: bar({ labelLayout: { align: 'left', fontSize: 16 }, emphasis: { label: { position: 'insideBottom' } } }), steps: [HL(2)] },
  { id: 'bar.layout.size', note: 'labelLayout width 40 height 20; emphasis.label position right',
    option: bar({ labelLayout: { width: 40, height: 20 }, emphasis: { label: { position: 'right' } } }), steps: [HL(0)] },
  { id: 'bar.layout.shift', note: 'labels on narrow bars overlapping, labelLayout moveOverlap shiftX; emphasis.label position bottom',
    option: bar({ data: [12, 13, 12.5, 13.2], label: { show: true, position: 'top', formatter: 'value {c}' },
      labelLayout: { moveOverlap: 'shiftX' }, emphasis: { label: { position: 'bottom' } } }), steps: [HL(1)] },
  { id: 'bar.layout.drag', note: 'labelLayout x 100, draggable; label 1 dragged by (20, 30), then hovered: emphasis.label position bottom puts it on its bar',
    option: bar({ labelLayout: { x: 100, draggable: true }, emphasis: { label: { position: 'bottom' } } }),
    steps: [DRAG(1, 20, 30), HL(1), DP(1)] },
  { id: 'bar.layout.drag.off', note: 'the same with emphasis.label offset [6, 6] alone: hovered where it was dragged, offset',
    option: bar({ labelLayout: { x: 100, draggable: true }, emphasis: { label: { offset: [6, 6] } } }),
    steps: [DRAG(1, 20, 30), HL(1), DP(1)] },
  { id: 'bar.layout.cut', note: "labelLayout width 30 on 'value {c}' labels, overflow truncate; emphasis.label position right: the cut words",
    option: bar({ label: { show: true, position: 'top', formatter: 'value {c}', overflow: 'truncate' },
      labelLayout: { width: 30 }, emphasis: { label: { position: 'right' } } }), steps: [HL(2)] },
  { id: 'graph.edge.arrow', edges: true, note: 'arrows at both ends; emphasis.edgeLabel position insideBottomRight: the end arrow\'s turned rect',
    option: { animation: false, series: [{ type: 'graph', layout: 'none', edgeSymbol: ['arrow', 'arrow'], edgeSymbolSize: 14,
      edgeLabel: { show: true }, emphasis: { edgeLabel: { position: 'insideBottomRight' } },
      data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 400, y: 260 }], links: [{ source: 'a', target: 'b' }] }] },
    steps: [EHL(0)] },
  // ---- a normal position zrender does not know: the rect's top-left (calculateTextPosition has no default) ----
  { id: 'normal.word.bar', note: "label.position 'foo' on bars: each bar's rect top-left, aligned left / top",
    option: bar({ label: { show: true, position: 'foo' } }), steps: [] },
  { id: 'normal.word.scatter', note: "label.position 'nowhere' on symbols, emphasis.label distance 9 (a key over it)",
    option: scatter({ label: { show: true, position: 'nowhere' }, emphasis: { scale: false, label: { distance: 9 } } }), steps: [HL(1)] },
  { id: 'normal.word.empty', note: "label.position '' is none: `'' || 'inside'`, the middle",
    option: scatter({ label: { show: true, position: '' } }), steps: [] },
  { id: 'normal.word.heatmap', note: "label.position 'centre' (a misspelling) on heatmap cells",
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', data: [[0, 0, 1], [0, 1, 5], [1, 0, 7], [1, 1, 9]], label: { show: true, position: 'centre' } }] }, steps: [] },
  { id: 'normal.word.treemap', note: "label.position 'foo' on treemap nodes",
    option: { animation: false, series: [{ type: 'treemap', label: { position: 'foo' }, data: [{ name: 'a', value: 6 }, { name: 'b', value: 4 }] }] }, steps: [] },
  { id: 'tree.radial', note: 'radial tree; emphasis.label position top',
    option: { animation: false, series: [{ type: 'tree', layout: 'radial', symbolSize: 14, expandAndCollapse: false,
      data: [{ name: 'root', children: [{ name: 'A', children: [{ name: 'A1' }, { name: 'A2' }] }, { name: 'B' }, { name: 'C' }] }],
      emphasis: { label: { position: 'top', distance: 6 } } }] }, steps: [HL(2), DP(2), HL(3)] },
  { id: 'graph.circular', note: 'circular graph, rotateLabel; emphasis.label position inside',
    option: { animation: false, series: [{ type: 'graph', layout: 'circular', circular: { rotateLabel: true }, symbolSize: 20,
      label: { show: true, position: 'right' }, emphasis: { scale: false, label: { position: 'top' } },
      data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }, { name: 'e' }], links: [] }] }, steps: [HL(1), DP(1), HL(3)] },
  // ---- the other series that lay their labels out on a host ----
  { id: 'pie.outer', note: 'pie outer labels; emphasis.label position inside',
    option: { animation: false, color: PALETTE, series: [{ type: 'pie', radius: '50%', data: [
      { value: 1548, name: 'CityE' }, { value: 735, name: 'CityC' }, { value: 510, name: 'CityD' }, { value: 434, name: 'CityB' }, { value: 335, name: 'CityA' }],
      emphasis: { label: { position: 'inside' } } }] }, steps: [HL(1)] },
  { id: 'pie.inner', note: 'pie inside labels; emphasis.label position top, rotate 20, offset [5, 5]',
    option: { animation: false, color: PALETTE, series: [{ type: 'pie', radius: '50%', label: { position: 'inside' }, data: [
      { value: 1548, name: 'CityE' }, { value: 735, name: 'CityC' }, { value: 510, name: 'CityD' }, { value: 434, name: 'CityB' }, { value: 335, name: 'CityA' }],
      emphasis: { label: { position: 'top', rotate: 20, offset: [5, 5] } } }] }, steps: [HL(0)] },
  { id: 'funnel.none', note: 'funnel: the label is a ZRText of its own (setLabelStyle on it): no state textConfig, emphasis.label position left changes nothing',
    option: { animation: false, color: PALETTE, series: [{ type: 'funnel', data: [
      { value: 60, name: 'Visit' }, { value: 40, name: 'Inquiry' }, { value: 20, name: 'Order' }],
      emphasis: { label: { position: 'left' } } }] }, steps: [HL(1)] },
  { id: 'heatmap', note: 'heatmap; emphasis.label position top',
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', data: [[0, 0, 1], [0, 1, 5], [1, 0, 7], [1, 1, 9]], label: { show: true },
        emphasis: { label: { position: 'top' } } }] }, steps: [HL(2)] },
  { id: 'radar', note: 'radar point labels; emphasis.label position right',
    option: { animation: false, radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
      series: [{ type: 'radar', label: { show: true }, emphasis: { label: { position: 'right' } }, data: [{ value: [5, 7, 3] }] }] }, steps: [HL(0)] },
  { id: 'graph', note: 'graph none layout; labels right; emphasis.label position top',
    option: { animation: false, series: [{ type: 'graph', layout: 'none', symbolSize: 20, label: { show: true, position: 'right' },
      emphasis: { scale: false, label: { position: 'top' } },
      data: [{ name: 'n0', x: 100, y: 100 }, { name: 'n1', x: 300, y: 100 }, { name: 'n2', x: 200, y: 300 }], links: [{ source: 'n0', target: 'n1' }] }] }, steps: [HL(1)] },
  { id: 'tree', note: 'tree; emphasis.label position top',
    option: { animation: false, series: [{ type: 'tree', data: [{ name: 'root', children: [{ name: 'a' }, { name: 'b' }] }],
      emphasis: { label: { position: 'top' } } }] }, steps: [HL(1)] },
  { id: 'sankey', note: 'sankey; emphasis.label position left',
    option: { animation: false, series: [{ type: 'sankey', data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }],
      emphasis: { label: { position: 'left' } } }] }, steps: [HL(1)] },
  { id: 'river', note: 'themeRiver; emphasis.label position top',
    option: { animation: false, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', label: { fontSize: 12 }, emphasis: { label: { position: 'top' } },
      data: [['2015/11/08', 10, 'A'], ['2015/11/09', 15, 'A'], ['2015/11/08', 5, 'B'], ['2015/11/09', 8, 'B']] }] }, steps: [HL(0)] },
  { id: 'treemap', note: 'treemap; emphasis.label position insideBottomRight',
    option: { animation: false, series: [{ type: 'treemap', data: [{ name: 'a', value: 6 }, { name: 'b', value: 4 }],
      emphasis: { label: { position: 'insideBottomRight' } } }] }, steps: [HL(1)] },
  { id: 'pictorial', note: 'pictorialBar labels top; emphasis.label position insideBottom',
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {},
      series: [{ type: 'pictorialBar', symbol: 'rect', data: [10, 20], label: { show: true, position: 'top' },
        emphasis: { label: { position: 'insideBottom' } } }] }, steps: [HL(1)] },
  { id: 'effect', note: 'effectScatter labels top; emphasis.label position bottom',
    option: { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'effectScatter', symbolSize: 20, data: [[1, 1], [2, 3]], label: { show: true, position: 'top' },
        emphasis: { scale: false, label: { position: 'bottom' } } }] }, steps: [HL(1)] },
  { id: 'polar', note: "polar bar labels middle (textConfig.inside); emphasis.label position end: the sector's own position, still inside",
    option: { animation: false, color: PALETTE, polar: {}, angleAxis: { type: 'category', data: ['a', 'b', 'c'] }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [3, 5, 4], label: { show: true, position: 'middle' },
        emphasis: { label: { position: 'end' } } }] }, steps: [HL(1), DP(1), HL(0)] },
  { id: 'bar.layout.dy', note: 'labelLayout dy -10; emphasis.label position bottom',
    option: bar({ labelLayout: { dy: -10 }, emphasis: { label: { position: 'bottom' } } }), steps: [HL(1)] },
  { id: 'bar.layout.hide', note: 'labelLayout hideOverlap; emphasis.label position bottom',
    option: bar({ labelLayout: { hideOverlap: true }, emphasis: { label: { position: 'bottom' } } }), steps: [HL(1)] },
  { id: 'bar.select.stroke', note: 'labels top; select border only: the label moves with the border',
    option: bar({ selectedMode: 'single' }), steps: [SEL(1)] },
  // ---- a line's symbols ----
  { id: 'line.right', note: 'line labels on top; emphasis.label position right, rotate -20',
    option: line({ emphasis: { scale: false, label: { position: 'right', rotate: -20 } } }), steps: [HL(1)] },
];

function runsOf(t) {
  const out = [];
  (t.childrenRef ? t.childrenRef() : []).forEach(k => {
    if (k.type === 'tspan') out.push(k);
  });
  return out;
}

function labelOf(el) {
  if (!el) return null;
  let t = el.getTextContent && el.getTextContent();
  if (t) return t;
  // a group (a symbol's, a pictorial bar's, a radar item's): the first
  // element under it that carries a text
  let found = null;
  if (el.traverse) el.traverse(k => { if (!found && k !== el && k.getTextContent && k.getTextContent()) found = k.getTextContent(); });
  return found;
}

// updateInnerText's isInside: textConfig.inside, else a position naming 'inside'
function insideOf(t) {
  const host = t.__hostTarget;
  const tc = (host && host.textConfig) || {};
  return tc.inside == null ? (typeof tc.position === 'string' && tc.position.indexOf('inside') >= 0) : !!tc.inside;
}

function readLabels(chart, edges) {
  const sm = chart.getModel().getSeriesByIndex(0);
  // a graph's or a sankey's links: the edge data's elements
  const data = edges ? sm.getEdgeData() : sm.getData();
  const labels = [];
  data.each(idx => {
    const t = labelOf(data.getItemGraphicEl(idx));
    if (!t) return;
    const m = t.getComputedTransform();
    const ds = t._defaultStyle || {};
    const r = t.getBoundingRect().clone();
    if (m) r.applyTransform(m);
    const runs = runsOf(t);
    labels.push({
      d: idx,
      ignore: !!t.ignore,
      text: t.style.text == null ? '' : String(t.style.text),
      x: hex(m ? m[4] : t.x), y: hex(m ? m[5] : t.y),
      m: (m ? [m[0], m[1], m[2], m[3]] : [1, 0, 0, 1]).map(hex),
      align: t.style.align || ds.align || 'left',
      verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
      rect: [r.x, r.y, r.width, r.height].map(hex),
      fill: runs.length ? String(runs[0].style.fill) : String(t.style.fill || ds.fill),
      inside: insideOf(t),
      fontSize: t.style.fontSize == null ? null : hex(+t.style.fontSize),
    });
  });
  return labels;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(clone(c.option));
    chart._onframe();
    chart.renderToSVGString();
    const rec = { id: c.id, note: c.note, option: clone(c.option), steps: clone(c.steps || []), states: [readLabels(chart, c.edges)] };
    if (c.edges) rec.edges = true;
    for (const s of (c.steps || [])) {
      if (s.drag != null) {
        const t = labelOf(chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(s.drag));
        must(t && t.draggable, 'the label is draggable');
        t.drift(s.dx, s.dy);
        t.trigger('drag');
      }
      else chart.dispatchAction(clone(s));
      chart._onframe();
      chart.renderToSVGString();
      rec.states.push(readLabels(chart, c.edges));
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const lab = (id, st, d) => by(id).states[st].find(l => l.d === d);
  const X = (id, st, d) => { bits.setBigUint64(0, BigInt('0x' + lab(id, st, d).x)); return bits.getFloat64(0); };
  const Y = (id, st, d) => { bits.setBigUint64(0, BigInt('0x' + lab(id, st, d).y)); return bits.getFloat64(0); };
  const guards = [
    { name: 'scatter.alias: hovered, the label is right of the symbol and its emphasis border (x 406)', ok: X('scatter.alias', 1, 1) === 406 },
    { name: 'scatter.top.bottom: hovered, the label is below the symbol at distance 12', ok: Y('scatter.top.bottom', 1, 2) === 150 + 10 + 12 },
    { name: 'scatter.scaled: hovered, right of the symbol scaled 1.1 (240 + 11 + 5)', ok: X('scatter.scaled', 1, 0) === 256 },
    { name: 'bar.insideTop: hovered, inside and inked for it', ok: lab('bar.insideTop', 1, 1).inside && lab('bar.insideTop', 1, 1).fill === '#eee' },
    { name: "bar.item: the item's position over the series', the series' on another bar, back at rest after downplay",
      ok: lab('bar.item', 1, 1).align === 'left' && lab('bar.item', 2, 1).y === lab('bar.item', 0, 1).y && lab('bar.item', 3, 0).verticalAlign === 'top' },
    { name: "bar.select.emph: select then hover, the distances merge over select's position", ok: Y('bar.select.emph', 2, 1) - Y('bar.select.emph', 1, 1) === 10 },
    { name: 'bar.blur: the blurred labels take blur.label.position', ok: [1, 2, 3].every(d => lab('bar.blur', 1, d).inside) && !lab('bar.blur', 1, 0).inside },
    { name: 'funnel.none: nothing moves', ok: JSON.stringify(by('funnel.none').states[0]) === JSON.stringify(by('funnel.none').states[1]) },
    { name: "pie.outer: hovered, the label at the hovered slice's rect centre, the layout's alignment kept",
      ok: lab('pie.outer', 1, 1).x !== lab('pie.outer', 0, 1).x && lab('pie.outer', 1, 1).align === lab('pie.outer', 0, 1).align },
    { name: "bar.select.stroke: the selected bar's border lifts its label by one", ok: Y('bar.select.stroke', 0, 1) - Y('bar.select.stroke', 1, 1) === 1 },
    { name: 'polar: hovered, still inside (#eee)', ok: lab('polar', 1, 1).inside && lab('polar', 1, 1).fill === '#eee' },
    { name: "graph.edge: hovered, on the Line group's box, beforeUpdate's alignment kept",
      ok: Y('graph.edge', 1, 0) < Y('graph.edge', 0, 0) - 100 && lab('graph.edge', 1, 0).align === lab('graph.edge', 0, 0).align
        && lab('graph.edge', 1, 0).verticalAlign === lab('graph.edge', 0, 0).verticalAlign },
    { name: "graph.edge.word: a word calculateTextPosition does not know: the box's corner", ok: X('graph.edge.word', 1, 0) < 100 },
    { name: "bar.word: 'foo' on a bar: its rect's top-left, aligned left / top",
      ok: lab('bar.word', 1, 1).align === 'left' && lab('bar.word', 1, 1).verticalAlign === 'top' },
    { name: "bar.layout.x: the state position over the layout's x", ok: X('bar.layout.x', 1, 1) !== 100 && X('bar.layout.x', 0, 1) === 100 },
    { name: "bar.layout.drag: hovered on its bar, back where it was dragged after", ok: X('bar.layout.drag', 2, 1) !== X('bar.layout.drag', 1, 1)
      && X('bar.layout.drag', 3, 1) === X('bar.layout.drag', 1, 1) && X('bar.layout.drag', 1, 1) === 120 },
    { name: "graph.circular: the labels turned; the emphasis position is the side's (rotateNodeLabel)",
      ok: lab('graph.circular', 0, 0).m[1] !== hex(0) && JSON.stringify(by('graph.circular').states[0]) === JSON.stringify(by('graph.circular').states[1]) },
    { name: 'tree.radial: hovered, moved, its turn kept', ok: X('tree.radial', 1, 2) !== X('tree.radial', 0, 2)
      && lab('tree.radial', 1, 2).m[0] === lab('tree.radial', 0, 2).m[0] },
    { name: "normal.word.*: a normal position zrender does not know: every label at its rect's top-left, left / top",
      ok: ['normal.word.bar', 'normal.word.scatter', 'normal.word.heatmap', 'normal.word.treemap'].every(id =>
        by(id).states[0].every(l => l.align === 'left' && l.verticalAlign === 'top')) && X('normal.word.scatter', 0, 0) === 230 },
    { name: "sankey.edge: hovered, on the curve's rect top", ok: lab('sankey.edge', 1, 1).verticalAlign === 'bottom' && !lab('sankey.edge', 1, 1).inside },
  ];
  if (!process.env.ORACLE_NOGUARD) for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: label/labelStyle.ts createTextConfig, zrender Element._applyStateObj / updateInnerText, label/LabelManager.ts',
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
