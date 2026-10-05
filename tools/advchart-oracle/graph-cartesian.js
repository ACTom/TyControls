// Upstream's own answers for a graph laid out on a cartesian grid: where each
// node lands, how each edge bends, what each node and edge is called, and how
// big the axes grow.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode. ON AXES THE LAYOUT IS ALREADY
// PIXELS -- upstream stores dataToPoint(value) as the node's layout -- so
// nothing here maps it again, unlike the view oracles beside this one. Every
// case pins the grid in pixels, so the plot rectangle does not depend on how
// wide anybody's font draws an axis label.
//
//   node tools/advchart-oracle/graph-cartesian.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-graph-cartesian.json');

// Nothing on axes should ever draw a random number; count them to be sure.
let draws = 0;
Math.random = function () { draws++; return 0.5; };

function fin(v) { return typeof v === 'number' && isFinite(v); }
function num(v) { return fin(v) ? v : null; }
function colour(c) {
  if (typeof c === 'string') return c;
  if (c && Array.isArray(c.colorStops) && c.colorStops.length) return c.colorStops[0].color;
  return null;
}
// How an edge's third point reads to the view -- see graph-legend.js.
function bendOf(pts) {
  const cp = pts && pts[2];
  if (cp == null) return 'straight';
  if (isNaN(+cp[0]) || isNaN(+cp[1])) return 'nancurve';
  if (!isFinite(cp[0]) || !isFinite(cp[1])) return 'hidden';
  return 'curve';
}

function captureSeries(s) {
  const cs = s.coordinateSystem;
  const d = s.getData();
  const e = s.getEdgeData();
  const area = cs.getArea ? cs.getArea() : null;
  const xs = cs.getAxis('x').scale.getExtent();
  const ys = cs.getAxis('y').scale.getExtent();
  const nodes = [];
  for (let i = 0; i < d.count(); i++) {
    const p = d.getItemLayout(i);
    const placed = !!p && fin(p[0]) && fin(p[1]);
    const style = d.getItemVisual(i, 'style') || {};
    nodes.push({ raw: d.getRawIndex(i), placed, px: placed ? p[0] : null, py: placed ? p[1] : null,
      x: num(d.get('x', i)), y: num(d.get('y', i)), name: d.getName(i), fill: colour(style.fill) });
  }
  const edges = [];
  for (let i = 0; i < e.count(); i++) {
    const pts = e.getItemLayout(i);
    const orig = (pts && pts.__original) || pts;
    const bend = bendOf(orig);
    const cp = orig && orig[2];
    const ends = !!pts && [pts[0], pts[1]].every(q => q && isFinite(q[0]) && isFinite(q[1]));
    const tip = s.formatTooltip(i, false, 'edge');
    const style = e.getItemVisual(i, 'style') || {};
    edges.push({ raw: e.getRawIndex(i), bend, ends,
      cpx: bend === 'curve' ? cp[0] : null, cpy: bend === 'curve' ? cp[1] : null,
      tipName: tip && tip.name, tipValue: (tip && !tip.noValue) ? num(+tip.value) : null,
      stroke: colour(style.stroke) });
  }
  return { index: s.seriesIndex, name: s.name,
    area: area ? [area.x, area.y, area.width, area.height] : null,
    xExtent: xs, yExtent: ys, nodes, edges };
}

function run(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.width, height: c.height });
  try {
    draws = 0;
    chart.setOption(c.option);
    const model = chart.getModel();
    const graphs = [];
    model.eachSeriesByType('graph', function (s) { graphs.push(captureSeries(s)); });
    if (draws) throw new Error(c.name + ': ' + draws + ' random draws');
    return { name: c.name, width: c.width, height: c.height, option: c.option, graphs };
  } finally {
    chart.dispose();
  }
}

// ---------- the fixtures ----------
const GRID = { left: 60, right: 40, top: 40, bottom: 40 };
const P3 = ['#111111', '#222222', '#333333'];
const cases = [];
// NO AXIS TAKES ANY ROOM. v6 shrinks the grid only for labels that overflow
// the canvas, and the port does not have that rule yet (it reserves every
// label's width, the way containLabel did). With the labels and ticks hidden
// both sides lay the plot out as the grid rectangle exactly, and what is left
// to compare is the graph.
//
// AND NO VALUE AXIS LANDS WHERE THE TWO NICE RULES PART. Upstream picks a tick
// step with nice(span / 5, round) -- 1, 2, 3, 5 or 10 -- and the port still
// uses a 1, 2, 2.5, 5 ladder without rounding; a span of 7 is a step of 1 there
// and 2 here. That is its own batch. Every extent below is one the two agree
// on, so a position that differs is the graph's doing.
function quiet(axis) {
  if (Array.isArray(axis)) return axis.map(quiet);
  return Object.assign({}, axis, { axisLabel: { show: false }, axisTick: { show: false } });
}
const add = (name, option, extra) => {
  const o = Object.assign({ animation: false, color: P3, grid: GRID }, option);
  if (o.xAxis) o.xAxis = quiet(o.xAxis);
  if (o.yAxis) o.yAxis = quiet(o.yAxis);
  cases.push(Object.assign({ name, width: 600, height: 400, option: o }, extra || {}));
};
const chainLinks = n => Array.from({ length: n - 1 }, (_, i) => ({ source: i, target: i + 1 }));

add('graph-grid', {
  tooltip: {},
  xAxis: { type: 'category', boundaryGap: false, data: ['Mon', 'Tue', 'Wed', 'Very Loooong Thu', 'Fri', 'Sat', 'Sun'] },
  yAxis: { type: 'value' },
  series: [{ type: 'graph', layout: 'none', coordinateSystem: 'cartesian2d', symbolSize: 40,
    label: { show: true }, edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: [4, 10],
    data: [842, 1276, 2288, 393, 893, 3559, 5374], links: chainLinks(7), lineStyle: { color: '#2f4554' } }] });
add('a category axis with a gap', {
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [3, 7, 2, 9], links: chainLinks(4) }] });
add('both axes value, bare numbers', {
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [3, 5, 8], links: chainLinks(3) }] });
add('a category y axis', {
  xAxis: { type: 'value' }, yAxis: { type: 'category', data: ['p', 'q', 'r'] },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [10, 20, 30], links: chainLinks(3) }] });
add('value arrays with extra columns and numeric names', {
  xAxis: { type: 'value' }, yAxis: { type: 'value', scale: true },
  series: [{ type: 'graph', name: 'China', coordinateSystem: 'cartesian2d',
    data: [{ name: 1800, value: [985, 32, 321675013, 'China', 1800] }, { name: 1810, value: [1100, 34, 350542958, 'China', 1810] },
      { name: 1820, value: [1500, 40, 380055273, 'China', 1820] }, { name: 1830, value: [900, 36, 402373519, 'China', 1830] }],
    links: [{ source: 0, target: 1 }, { source: 1, target: 2 }, { source: '1820', target: '1830' }, { source: 1830, target: 0 }],
    edgeSymbol: ['none', 'arrow'], symbolSize: 5 }] });
add('missing values', {
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d',
    data: [5, '-', [2, '-'], { value: [3, 4] }, ['-', 6]], links: chainLinks(5) }] });
add('curveness on axes is authored in pixels', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [100, 900, 300],
    links: chainLinks(3), lineStyle: { curveness: 0.3 } }] });
add('auto curveness on axes', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', autoCurveness: true, data: [100, 900, 300],
    links: [{ source: 0, target: 1 }, { source: 0, target: 1 }, { source: 1, target: 0 }, { source: 1, target: 2 },
      { source: 2, target: 1, lineStyle: { curveness: -0.5 } }] }] });
// The filter takes the LAST node out, so no survivor is renumbered and every
// key still matches -- and the first link goes with it, so a link's position
// among the survivors is one less than its raw index. Asked by position, the
// table answers for the wrong link.
add('auto curveness on axes after a filter', {
  legend: { selected: { A: false } },
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', autoCurveness: true,
    categories: [{ name: 'A' }, { name: 'B' }],
    data: [{ value: 3, category: 1 }, { value: 8, category: 1 }, { value: 5 }, { value: 6, category: 0 }],
    links: [{ source: 3, target: 0 }, { source: 0, target: 1 }, { source: 0, target: 1 }, { source: 1, target: 0 }] }] });
add('layout force is not run on axes', {
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', layout: 'force', force: { layoutAnimation: false }, coordinateSystem: 'cartesian2d',
    data: [[1, 2], [3, 1], [2, 5]], links: chainLinks(3) }] });
add('layout circular is not run on axes', {
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', layout: 'circular', coordinateSystem: 'cartesian2d', autoCurveness: true,
    data: [[1, 2], [3, 1], [2, 5]], links: [{ source: 0, target: 1 }, { source: 0, target: 1 }, { source: 1, target: 2 }] }] });
add('the item x and y are not positions on axes', {
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d',
    data: [{ value: [1, 2], x: 500, y: 600 }, { value: [4, 3], x: -100, y: 0 }], links: chainLinks(2) }] });
add('categories and a legend filter on axes', {
  legend: { selected: { B: false } },
  xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', categories: [{ name: 'A' }, { name: 'B' }],
    data: [{ value: 5, category: 0 }, { value: 9, category: 1 }, { value: 2, category: 0 }, { value: 8 }],
    links: chainLinks(4).concat([{ source: 0, target: 2 }]) }] });
add('a series-level category on axes', {
  legend: { selected: { B: false } },
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', category: 1, categories: [{ name: 'A' }, { name: 'B' }],
    data: [{ value: 5, category: 0 }, { value: 9 }, { value: 2, category: 0 }], links: chainLinks(3) }] });
add('nodes beside a dataset', {
  dataset: { source: [[1, 100], [2, 200], [3, 300]] },
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', nodes: [[5, 6], [8, 9]], edges: [{ source: 0, target: 1 }] }] });
add('a value off the axis is not clipped', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', max: 10 },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [2, 50, 4], links: chainLinks(3) }] });
add('a second y axis', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: [{ type: 'value' }, { type: 'value', position: 'right' }],
  series: [{ type: 'line', data: [1, 2, 3] },
    { type: 'graph', coordinateSystem: 'cartesian2d', yAxisIndex: 1, data: [500, 100, 300], links: chainLinks(3) }] });
add('legend single over several graphs', {
  legend: { selectedMode: 'single' },
  xAxis: { type: 'value' }, yAxis: { type: 'value', scale: true },
  series: ['P', 'Q', 'R'].map((n, k) => ({ type: 'graph', name: n, coordinateSystem: 'cartesian2d',
    data: [[1 + k, 10 * (k + 1)], [2 + k, 12 * (k + 1)], [4 + k, 15 * (k + 1)]], links: chainLinks(3) })) });
add('a category axis with no data collects', {
  xAxis: { type: 'category' }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [4, 8, 6], links: chainLinks(3) }] });
add('named nodes on a category axis keep their names', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d',
    data: [{ name: 'first', value: 3 }, 5, { name: 'third', value: 4 }], links: chainLinks(3) }] });
add('an edge with a value', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [3, 5, 4],
    links: [{ source: 0, target: 1, value: 42 }, { source: 1, target: 2 }] }] });
add('edges coloured by their ends on axes', {
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value' },
  series: [{ type: 'graph', coordinateSystem: 'cartesian2d', categories: [{ name: 'A' }, { name: 'B' }],
    data: [{ value: 3, category: 0 }, { value: 5, category: 1 }, { value: 4, category: 1, itemStyle: { color: '#ff0000' } }],
    links: chainLinks(3), lineStyle: { color: 'target' } }] });

const out = { source: 'ECharts ' + echarts.version, cases: cases.map(run) };
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote', OUT, out.cases.length, 'cases');
process.exit(0);
