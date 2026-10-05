// Upstream's own answers for a graph's categories in the legend: which nodes a
// legend keeps, where they go, what colour everything is, and what the legend
// offers.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, with Math.random replaced by the
// port's seeded xorshift32 as in graph-force.js, and writes every graph
// series' surviving nodes and edges, their colours and the legend's names to
// tests/fixtures/advchart-graph-legend.json.
//
//   node tools/advchart-oracle/graph-legend.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-graph-legend.json');

const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};

function num(v) { return (typeof v === 'number' && isFinite(v)) ? v : null; }
// A gradient is written down as its first stop, which is the solid the port
// degrades one to.
function colour(c) {
  if (typeof c === 'string') return c;
  if (c && Array.isArray(c.colorStops) && c.colorStops.length) return c.colorStops[0].color;
  return null;
}
// How an edge's third point reads to the view: none at all, a point with a
// not-a-number half (isStraightLine draws it straight), a point that is a
// number but not a finite one (the canvas refuses it), or a real curve.
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
  const k = s.getCategoriesData();
  const nodes = [];
  for (let i = 0; i < d.count(); i++) {
    const p = d.getItemLayout(i);
    const ok = p && num(p[0]) !== null && num(p[1]) !== null;
    const q = ok ? cs.dataToPoint(p) : null;
    const style = d.getItemVisual(i, 'style') || {};
    nodes.push({ raw: d.getRawIndex(i), px: ok ? q[0] : null, py: ok ? q[1] : null,
      fill: colour(style.fill), symbol: d.getItemVisual(i, 'symbol') || null });
  }
  const edges = [];
  for (let i = 0; i < e.count(); i++) {
    const pts = e.getItemLayout(i);
    // THE LAYOUT'S OWN POINT, from before adjustEdge cut the curve back at a
    // node carrying a symbol -- the cut rewrites pts[2] in place, and the
    // port keeps the layout's point and trims when it draws.
    const orig = (pts && pts.__original) || pts;
    const cp = orig && orig[2];
    const bend = bendOf(orig);

    const ok = bend === 'curve';
    const q = ok ? cs.dataToPoint(cp) : null;
    const style = e.getItemVisual(i, 'style') || {};
    // adjustEdge has already cut the ends back where a symbol sits, in place.
    const ends = !!pts && [pts[0], pts[1]].every(p => p && isFinite(p[0]) && isFinite(p[1]));
    edges.push({ raw: e.getRawIndex(i), bend, ends, cpx: ok ? q[0] : null, cpy: ok ? q[1] : null,
      stroke: colour(style.stroke) });
  }
  const cats = [];
  for (let i = 0; i < k.count(); i++) {
    const st = k.getItemVisual(i, 'style');
    cats.push({ name: k.getName(i), fill: st ? colour(st.fill) : null });
  }
  const sstyle = d.getVisual('style') || {};
  return { index: s.seriesIndex, seriesFill: colour(sstyle.fill), nodes, edges, cats };
}

function run(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.width, height: c.height });
  try {
    rngState = SEED;
    chart.setOption(c.option);
    const model = chart.getModel();
    const graphs = [];
    model.eachSeriesByType('graph', function (s) { graphs.push(captureSeries(s)); });
    const legends = model.findComponents({ mainType: 'legend' }).map(L => {
      const names = L.getData().map(m => m.get('name'));
      return { names, selected: names.map(n => L.isSelected(n)) };
    });
    let resized = null;
    if (c.resize) {
      rngState = SEED;
      chart.resize({ width: c.resize[0], height: c.resize[1] });
      const g2 = [];
      model.eachSeriesByType('graph', function (s) { g2.push(captureSeries(s)); });
      resized = { width: c.resize[0], height: c.resize[1], graphs: g2 };
    }
    return { name: c.name, width: c.width, height: c.height, colours: !!c.colours,
      option: c.option, graphs, legends, resized };
  } finally {
    chart.dispose();
  }
}

// ---------- the fixtures ----------
const P3 = ['#111111', '#222222', '#333333'];
const P4 = ['#111111', '#222222', '#333333', '#444444'];
function base(extra, series) {
  return Object.assign({ animation: false, color: P3,
    series: [Object.assign({ type: 'graph', layout: 'none', name: 'G', autoCurveness: true,
      categories: [{ name: 'X' }, { name: 'Y' }],
      data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 },
        { name: 'c', x: 20, y: 5, category: 0 }, { name: 'd', x: 5, y: 9 }],
      links: [{ source: 'a', target: 'c' }, { source: 'a', target: 'c' },
        { source: 'b', target: 'c' }, { source: 'c', target: 'd' }] }, series || {})] }, extra || {});
}

const cases = [];
const add = (name, option, extra) => cases.push(Object.assign({ name, width: 400, height: 300, colours: true, option }, extra || {}));

add('no legend at all', base());
add('a legend of everything', base({ legend: {} }));
add('Y switched off', base({ legend: { selected: { Y: false } } }));
add('X switched off', base({ legend: { selected: { X: false } } }));
add('X off without being listed', base({ legend: { data: ['Y'], selected: { X: false } } }));
add('off by every falsy word', base({ legend: { selected: { X: null, Y: 0 } } }));
add('a hidden legend still filters', base({ legend: { show: false, selected: { X: false } } }));
add('two legends, one says no', base({ legend: [{}, { selected: { Y: false } }] }));
add('single mode keeps the first', base({ legend: { selectedMode: 'single' } }));
add('single mode with a nameless first category',
  base({ legend: { selectedMode: 'single' } }, { categories: [{}, { name: 'X' }] }));
add('an index past the end and a name nobody declared',
  base({ legend: {} }, { data: [{ name: 'a', x: 0, y: 0, category: 5 }, { name: 'b', x: 10, y: 0, category: 1 },
    { name: 'c', x: 20, y: 5, category: 'Nope' }, { name: 'd', x: 5, y: 9 }] }));
add('the same, with no legend', base({}, { data: [{ name: 'a', x: 0, y: 0, category: 5 },
  { name: 'b', x: 10, y: 0, category: 1 }, { name: 'c', x: 20, y: 5, category: 'Nope' }, { name: 'd', x: 5, y: 9 }] }));
add('a numeric string category is a name', base({ legend: {} }, {
  data: [{ name: 'a', x: 0, y: 0, category: '1' }, { name: 'b', x: 10, y: 0, category: 1 },
    { name: 'c', x: 20, y: 5, category: 0 }, { name: 'd', x: 5, y: 9 }] }));
add('categories written as bare strings', base({ legend: {} }, { categories: ['X', 'Y'],
  data: [{ name: 'a', x: 0, y: 0, category: 'X' }, { name: 'b', x: 10, y: 0, category: 1 },
    { name: 'c', x: 20, y: 5, category: 0 }, { name: 'd', x: 5, y: 9 }] }));
add('no categories and a legend', base({ legend: {} }, { categories: [] }));
add('a numeric category name', base({ legend: { selected: { '5': false } } }, { categories: [{ name: 5 }, { name: 'Y' }],
  data: [{ name: 'a', x: 0, y: 0, category: '5' }, { name: 'b', x: 10, y: 0, category: 1 },
    { name: 'c', x: 20, y: 5, category: 0 }, { name: 'd', x: 5, y: 9 }] }));
add('a category naming the series itself', base({ legend: {} }, {
  data: [{ name: 'a', x: 0, y: 0, category: 'G' }, { name: 'b', x: 10, y: 0, category: 1 },
    { name: 'c', x: 20, y: 5, category: 0 }, { name: 'd', x: 5, y: 9 }] }));
add('two categories of one name', base({ legend: { selected: { X: false } } }, {
  categories: [{ name: 'X', itemStyle: { color: '#ff0000' } }, { name: 'X' }],
  data: [{ name: 'a', x: 0, y: 0, category: 'X' }, { name: 'b', x: 10, y: 0, category: 0 },
    { name: 'c', x: 20, y: 5, category: 1 }, { name: 'd', x: 5, y: 9 }] }));
add('duplicates by name colour by the last', base({}, {
  categories: [{ name: 'X', itemStyle: { color: '#ff0000' } }, { name: 'X' }],
  data: [{ name: 'a', x: 0, y: 0, category: 'X' }, { name: 'b', x: 10, y: 0, category: 0 },
    { name: 'c', x: 20, y: 5, category: 1 }, { name: 'd', x: 5, y: 9 }] }));

// ---------- colours ----------
add('a category colour, a node colour, a category symbol', base({}, {
  categories: [{ name: 'X' }, { name: 'Y', symbol: 'rect', symbolSize: 20 }],
  data: [{ name: 'n0', x: 0, y: 0, category: 1, itemStyle: { color: '#ff0000' } }, { name: 'n1', x: 10, y: 0, category: 1 },
    { name: 'n2', x: 20, y: 5, category: 0 }, { name: 'n3', x: 5, y: 9 }],
  links: [{ source: 0, target: 1 }, { source: 1, target: 2 }], autoCurveness: false,
  lineStyle: { color: 'source' } }));
add('edges coloured by their target', base({}, {
  categories: [{ name: 'X' }, { name: 'Y' }],
  data: [{ name: 'n0', x: 0, y: 0, category: 1, itemStyle: { color: '#ff0000' } }, { name: 'n1', x: 10, y: 0, category: 0 }],
  links: [{ source: 1, target: 0 }], autoCurveness: false, lineStyle: { color: 'target' } }));
add('the series palette before the chart one', base({}, { color: ['#aa0000', '#00aa00'],
  categories: [{ name: 'X' }, { name: 'Y', itemStyle: { color: '#0000ff' } }] }));
add('a series itemStyle colours every category', base({}, { itemStyle: { color: '#abcdef' } }));
add('two graphs share one palette cursor', { animation: false, color: P4, series: [
  { type: 'graph', layout: 'none', name: 'G1', categories: [{ name: 'X' }, { name: 'Y' }],
    data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 1, y: 1, category: 1 }] },
  { type: 'graph', layout: 'none', name: 'G2', categories: [{ name: 'Z' }, { name: 'X' }],
    data: [{ name: 'c', x: 0, y: 0, category: 0 }, { name: 'd', x: 1, y: 1, category: 1 }] }] });
add('a graph switched off takes no slot', { animation: false, color: P4,
  legend: { data: ['G1', 'Z', 'W'], selected: { G1: false } }, series: [
    { type: 'graph', layout: 'none', name: 'G1', categories: [{ name: 'X' }, { name: 'Y' }],
      data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 1, y: 1, category: 1 }] },
    { type: 'graph', layout: 'none', name: 'G2', categories: [{ name: 'Z' }, { name: 'W' }],
      data: [{ name: 'c', x: 0, y: 0, category: 0 }, { name: 'd', x: 1, y: 1, category: 1 }] }] });
add('nameless categories take fresh slots', { animation: false, color: P4, series: [
  { type: 'graph', layout: 'none', categories: [{}, {}, { name: 'X' }],
    data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 1, y: 1, category: 1 }, { name: 'c', x: 2, y: 0, category: 2 }] },
  { type: 'graph', layout: 'none', categories: [{}],
    data: [{ name: 'd', x: 0, y: 0, category: 0 }] }] });
add('a long palette then a short one', { animation: false, color: ['#aaaaaa', '#bbbbbb'], series: [
  { type: 'graph', layout: 'none', color: ['#111111', '#222222', '#333333', '#444444', '#555555'],
    categories: [{ name: 'P' }, { name: 'Q' }, { name: 'R' }],
    data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 1, y: 1, category: 2 }] },
  { type: 'graph', layout: 'none', categories: [{ name: 'S' }],
    data: [{ name: 'c', x: 0, y: 0, category: 0 }] }] });
add('a pie slice and a category share a name', { animation: false, color: P4,
  legend: { selected: { X: false } }, series: [
    base().series[0],
    { type: 'pie', data: [{ name: 'X', value: 1 }, { name: 'Q', value: 2 }] }] });

// ---------- batch 31 audit: the chain, the scope, the series name ----------
const catsXY = [{ name: 'X' }, { name: 'Y' }];
const dataXY = [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 },
  { name: 'c', x: 20, y: 5, category: 0 }];
add('a graph off by its series name, which the legend does not list', { animation: false, color: P4,
  legend: { data: ['Z', 'W'], selected: { G1: false } }, series: [
    { type: 'graph', layout: 'none', name: 'G1', categories: catsXY, data: dataXY },
    { type: 'graph', layout: 'none', name: 'G2', categories: [{ name: 'Z' }, { name: 'W' }],
      data: [{ name: 'c', x: 0, y: 0, category: 0 }, { name: 'd', x: 1, y: 1, category: 1 }] }] });
add('a series-level category', base({ legend: { selected: { Y: false } } }, { category: 1,
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0 },
    { name: 'c', x: 20, y: 5, category: null }, { name: 'd', x: 5, y: 9, category: 'X' }] }));
add('a series-level category by name', base({}, { category: 'Y',
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0 }, { name: 'c', x: 20, y: 5 }] }));
add('a root-level category', base({ category: 1, legend: {} }, {
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0 }, { name: 'c', x: 20, y: 5 }] }));
add('a root itemStyle colours every category', base({ itemStyle: { color: '#abcdef' } }, {
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a series colour beats a root one', base({ itemStyle: { color: '#abcdef' } }, { itemStyle: { color: '#123456' },
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a gradient category takes no slot', base({ legend: {} }, {
  categories: [{ name: 'X', itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 1, y2: 0,
    colorStops: [{ offset: 0, color: '#00ff00' }, { offset: 1, color: '#0000ff' }] } } }, { name: 'Y' }],
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a gradient series colour colours every category', base({}, {
  itemStyle: { color: { type: 'radial', x: 0.5, y: 0.5, r: 0.5,
    colorStops: [{ offset: 0, color: '#ff00ff' }, { offset: 1, color: '#000000' }] } },
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a category painted none', base({ legend: {} }, {
  categories: [{ name: 'X', itemStyle: { color: 'none' } }, { name: 'Y' }],
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a category colour nobody can paint takes no slot', base({ legend: {} }, {
  categories: [{ name: 'X', itemStyle: { color: 'reddish' } }, { name: 'Y' }],
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a falsy category colour goes to the palette', base({ legend: {} }, {
  categories: [{ name: 'X', itemStyle: { color: '' } }, { name: 'Y', itemStyle: { color: 0 } }, { name: 'Z' }],
  itemStyle: { color: '#abcdef' },
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }, { name: 'c', x: 5, y: 5, category: 2 }] }));
add('a null category colour asks the series', base({}, {
  categories: [{ name: 'X', itemStyle: { color: null } }, { name: 'Y' }], itemStyle: { color: '#abcdef' },
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 }] }));
add('a failed pick is remembered by name', { animation: false, color: ['#aaaaaa', '#bbbbbb'], series: [
  { type: 'graph', layout: 'none', color: ['#111111', '#222222', '#333333', '#444444', '#555555'],
    categories: [{ name: 'P' }, { name: 'Q' }, { name: 'R' }],
    data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 1, y: 1, category: 2 }] },
  { type: 'graph', layout: 'none', color: ['#a10000', '#a20000'], categories: [{ name: 'S' }, {}],
    data: [{ name: 'c', x: 0, y: 0, category: 0 }, { name: 'd', x: 1, y: 1, category: 1 }] },
  { type: 'graph', layout: 'none', categories: [{ name: 'S' }, { name: 'T' }],
    data: [{ name: 'e', x: 0, y: 0, category: 0 }, { name: 'f', x: 1, y: 1, category: 1 }] }] });
add('a nameless pick past a short own palette asks the chart', { animation: false, color: ['#aaaaaa', '#bbbbbb', '#cccccc'], series: [
  { type: 'graph', layout: 'none', color: ['#111111', '#222222', '#333333', '#444444', '#555555'],
    categories: [{ name: 'P' }, { name: 'Q' }, { name: 'R' }],
    data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 1, y: 1, category: 2 }] },
  { type: 'graph', layout: 'none', color: ['#a10000', '#a20000'], categories: [{}, { name: 'S' }],
    data: [{ name: 'c', x: 0, y: 0, category: 0 }, { name: 'd', x: 1, y: 1, category: 1 }] }] });
add('a node\'s own colour follows its row through the filter', base({ legend: { selected: { X: false } } }, {
  data: [{ name: 'a', x: 0, y: 0, category: 0, itemStyle: { color: '#ff0000' } },
    { name: 'b', x: 10, y: 0, category: 1 },
    { name: 'c', x: 20, y: 5, category: 1, itemStyle: { color: '#00ff00' } }, { name: 'd', x: 5, y: 9 }],
  links: [{ source: 'b', target: 'c' }, { source: 'c', target: 'd' }], lineStyle: { color: 'target' } }));
add('an empty category name finds the last nameless one', base({}, {

  categories: [{ itemStyle: { color: '#ff0000' } }, { name: 'X' }, { itemStyle: { color: '#00ff00' } }],
  data: [{ name: 'a', x: 0, y: 0, category: '' }, { name: 'b', x: 10, y: 0, category: 1 }, { name: 'c', x: 5, y: 5, category: false }] }));
add('a boolean category goes when there is a legend', base({ legend: {} }, {
  data: [{ name: 'a', x: 0, y: 0, category: true }, { name: 'b', x: 10, y: 0, category: false },
    { name: 'c', x: 20, y: 5, category: 0 }] }));
add('a ring measures the average of a pair', { animation: false, color: P3, series: [{

  type: 'graph', layout: 'circular', categories: [{ name: 'A', symbolSize: [60, 10] }, { name: 'B', symbolSize: [30] }],
  data: [{ name: 'a', category: 0 }, { name: 'b', category: 0 }, { name: 'c', category: 1 }, { name: 'd' }] }] }, { width: 600, height: 400 });
add('a ring of pairs from the series', { animation: false, color: P3, series: [{
  type: 'graph', layout: 'circular', symbolSize: [80, 20],
  data: [{ name: 'a', symbolSize: 10 }, { name: 'b' }, { name: 'c' }] }] }, { width: 600, height: 400 });
add('a ring of one-element pairs from the series', { animation: false, color: P3, series: [{
  type: 'graph', layout: 'circular', symbolSize: [80],
  data: [{ name: 'a', symbolSize: 40 }, { name: 'b' }, { name: 'c' }] }] }, { width: 600, height: 400 });
const loose = [{ name: 'p', category: 0 }, { name: 'q', category: 0 }, { name: 'x', category: 1 }];
const looseLinks = [{ source: 'x', target: 'p' }, { source: 'p', target: 'q' }, { source: 'p', target: 'q' }, { source: 'q', target: 'p' }];
add('a stale control point from nodes nobody placed', { animation: false, color: P3,
  legend: { selected: { B: false } }, series: [{ type: 'graph', layout: 'force', autoCurveness: true,
    force: { layoutAnimation: false, initLayout: 'none' }, categories: [{ name: 'A' }, { name: 'B' }],
    data: loose, links: looseLinks }] });
add('the same stale point with an arrow', { animation: false, color: P3,
  legend: { selected: { B: false } }, series: [{ type: 'graph', layout: 'force', autoCurveness: true,
    edgeSymbol: ['none', 'arrow'],
    force: { layoutAnimation: false, initLayout: 'none' }, categories: [{ name: 'A' }, { name: 'B' }],
    data: loose, links: looseLinks }] });

// ---------- layouts under the filter ----------

const curvNodes = [{ name: 'x', x: 50, y: 50, category: 1 }, { name: 'p', x: 0, y: 0, category: 0 }, { name: 'q', x: 100, y: 0, category: 0 }];
const curvNodesAfter = [{ name: 'p', x: 0, y: 0, category: 0 }, { name: 'q', x: 100, y: 0, category: 0 }, { name: 'x', x: 50, y: 50, category: 1 }];
const curvLinks = [{ source: 'x', target: 'p' }, { source: 'p', target: 'q' }, { source: 'p', target: 'q' }, { source: 'q', target: 'p' }];
for (const layout of ['none', 'circular', 'force']) {
  for (const [label, data] of [['before', curvNodes], ['after', curvNodesAfter]]) {
    for (const off of [false, true]) {
      const series = { type: 'graph', layout, autoCurveness: true, categories: [{ name: 'A' }, { name: 'B' }],
        data, links: curvLinks };
      if (layout === 'force') series.force = { layoutAnimation: false };
      add('curveness, ' + layout + ', the removed node ' + label + (off ? ', B off' : ', all on'),
        { animation: false, color: P3, legend: off ? { selected: { B: false } } : {}, series: [series] });
    }
  }
}
add('a stale control point, and a resize that drops it', { animation: false, color: P3,
  legend: { selected: { B: false } }, series: [{ type: 'graph', layout: 'force', autoCurveness: true,
    force: { layoutAnimation: false }, categories: [{ name: 'A' }, { name: 'B' }],
    data: curvNodesAfter, links: curvLinks }] }, { resize: [500, 400] });
add('a stale control point from a ring', { animation: false, color: P3,
  legend: { selected: { B: false } }, series: [{ type: 'graph', layout: 'force', autoCurveness: true,
    force: { layoutAnimation: false, initLayout: 'circular' }, categories: [{ name: 'A' }, { name: 'B' }],
    data: curvNodesAfter, links: curvLinks }] });
add('force with a category off', { animation: false, color: P3, legend: { selected: { B: false } }, series: [{
  type: 'graph', layout: 'force', force: { layoutAnimation: false }, categories: [{ name: 'A' }, { name: 'B' }],
  data: [{ name: 'a', category: 0, value: 1 }, { name: 'b', category: 1, value: 5 }, { name: 'c', category: 0, value: 3 },
    { name: 'd', value: 2 }, { name: 'e', category: 1, value: 4 }],
  links: [{ source: 0, target: 1 }, { source: 1, target: 2 }, { source: 2, target: 3 }, { source: 3, target: 4 }, { source: 0, target: 3 }] }] });
add('force from a ring with a category off', { animation: false, color: P3, legend: { selected: { A: false } }, series: [{
  type: 'graph', layout: 'force', force: { layoutAnimation: false, initLayout: 'circular' }, categories: [{ name: 'A' }, { name: 'B' }],
  data: [{ name: 'a', category: 0, value: 1 }, { name: 'b', category: 1, value: 5 }, { name: 'c', category: 1, value: 3 },
    { name: 'd', value: 2 }], links: [{ source: 1, target: 2 }, { source: 2, target: 3 }] }] });
add('a ring re-spaced by a big category switched off', { animation: false, color: P3, legend: { selected: { B: false } }, series: [{
  type: 'graph', layout: 'circular', categories: [{ name: 'A', symbolSize: 10 }, { name: 'B', symbolSize: 80 }],
  data: [{ name: 'a', category: 0 }, { name: 'b', category: 0 }, { name: 'c', category: 0 }, { name: 'x', category: 1 }] }] }, { width: 600, height: 400 });
add('the same ring with everything on', { animation: false, color: P3, legend: {}, series: [{
  type: 'graph', layout: 'circular', categories: [{ name: 'A', symbolSize: 10 }, { name: 'B', symbolSize: 80 }],
  data: [{ name: 'a', category: 0 }, { name: 'b', category: 0 }, { name: 'c', category: 0 }, { name: 'x', category: 1 }] }] }, { width: 600, height: 400 });
add('the view does not re-fit when the far node goes', { animation: false, color: P3, legend: { selected: { B: false } }, series: [{
  type: 'graph', layout: 'none', categories: [{ name: 'A' }, { name: 'B' }],
  data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 100, y: 50, category: 0 }, { name: 'far', x: 1000, y: 500, category: 1 }] }] }, { width: 600, height: 400 });
add('every category off', { animation: false, color: P3, legend: { selected: { A: false, B: false } }, series: [{
  type: 'graph', layout: 'force', force: { layoutAnimation: false }, categories: [{ name: 'A' }, { name: 'B' }],
  data: [{ name: 'a', category: 0 }, { name: 'b', category: 1 }], links: [{ source: 0, target: 1 }] }] });

const out = { source: 'ECharts ' + echarts.version, seed: SEED, cases: cases.map(run) };
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote', OUT, out.cases.length, 'cases');
process.exit(0);
