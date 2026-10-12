/*
Upstream's own answers for roadmap D13 part one (BX1), batch 151:
coordinateSystemUsage 'box' -- createBoxLayoutReference (util/layout.ts)
over a component's or a series' boxCoordinateSystem, which
injectCoordSysByOption (core/CoordinateSystem.ts) gives every model whose
`coordinateSystem` is a matrix or a calendar and whose usage
(decideCoordSysUsageKind) is 'box': the refContainer is the host's
dataToLayout of `coord` (a pie's `center` when it has none: getCoord2), the
matrix's rect or a calendar day's contentRect, and the component lays its
box out in it with getLayoutRect. Covered: the grid (Grid.resize -- its rect,
the outer bounds and the names' margin level on the refContainer), the polar
(resizePolar), the title, the legend (both of LegendView's box solves), and
the series pie and chord (getCircleLayout), funnel, sankey, tree, treemap
(the box; the pruning stays on the canvas; the breadcrumb is positioned in
the refContainer), graph with usage 'box' (createView's internal view), and
the ones upstream leaves on the canvas whatever they name (a gauge, a
sunburst, a chord with usage 'data', a box type whose host is not there);
plus the gallery's matrix-stock (five grids and four titles in cells).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
Math.random the port's xorshift32 (seed 2463534242, reset before every
chart) and zrender's width table measuring every string. Every option is run
with animation off.

  node tools/advchart-oracle/box-usage.js

writes tests/fixtures/advchart-box-usage.json (ORACLE_OUT overrides). Ends
with process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON.

Top level: source, version, seed, W, H, measure {firstCode, ratio[] (hex)},
notes[], cases[], guards[].

A case: id, group ('grid' | 'polar' | 'title' | 'legend' | 'series' |
'gallery'), note, gallery (a file under examples/advchart/gallery, fed
verbatim; option is then null) or option (as run), fails[] (recipe
mismatches; must be empty), and:

  matrices[]  {index, rect {x, y, width, height}}
  grids[]     {index, boxed (a boxCoordinateSystem), ref (the refContainer
              when boxed, else null), rect (Grid.getRect(), after the outer
              bounds)}
  polars[]    {index, boxed, ref, cx, cy, r [r0, r1] (the radius axis'
              extent)}
  calls[]     {finder, value, ret} chart.convertToPixel answers ([x, y] hex,
              null for none)
  titles[]    {index, boxed, ref, group [x, y], bg {x, y, width, height}
              (the background rect, global), align, verticalAlign (the text
              element's, null when unset)}
  legends[]   {index, boxed, ref, group [x, y] (the view group's global
              transform), items[] {i (__legendDataIndex), name, t [tx, ty]
              (the item group's global transform), r [x, y, w, h] (its
              bounding rect)}}
  series[]    {seriesIndex, type, boxed, ref, and by type:
                pie / chord / sunburst  sectors[] {i, cx, cy, r0, r} (the
                                        item layouts)
                funnel                  items[] {i, points [[x, y] x 4]}
                sankey / tree / treemap layoutInfo {x, y, width, height}
                                        (seriesModel.layoutInfo), nodes[]
                                        (sankey {i, x, y, dx, dy}; tree {i,
                                        x, y} -- local, laid-out rows only;
                                        treemap {i, x, y, width, height} --
                                        local to the parent), crumbs[]
                                        (treemap: each breadcrumb polygon's
                                        points, global)
                graph                   viewRect {x, y, width, height}, nodes
                                        [] {i, x, y} (dataToPoint of the
                                        layout, global)
                gauge                   centre [cx, cy] of the first sector
                                        in its group}

Guards (any failure: nothing is written, exit 1): every case's recipes (R1
a boxed model's ref is its host's dataToLayout of the coord -- contentRect
or rect --, R2 a sankey's, a tree's and a treemap's layoutInfo is
getLayoutRect of its box params in the ref, a grid with outerBoundsMode
'none' is getLayoutRect in the ref, R3 a model whose host gives it nothing is
laid out as with no coordinateSystem at all: the same chart without the key
answers the same), named discriminating facts, and the whole fixture
generated twice, byte-identical, no \u0000, parsing back.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the random numbers: the port's xorshift32 ----------
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-box-usage.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
const W = 800;
const H = 600;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => {};
  console.error = () => {};
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const rectRec = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const sameNum = (a, b) => Object.is(a, b) || (Number.isNaN(a) && Number.isNaN(b));
const sameRect = (a, b) => sameNum(a.x, b.x) && sameNum(a.y, b.y) && sameNum(a.width, b.width) && sameNum(a.height, b.height);

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m && decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  }
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);
(function checkMeasurer() {
  RATIO.forEach((r, i) => {
    const w = new echarts.graphic.Text({ style: { text: String.fromCharCode(FIRST_CODE + i), font: '1px sans-serif' } }).getBoundingRect().width;
    must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
  });
})();

// ---------- the chart ----------
function mk() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function draw(chart, option) {
  quiet(() => chart.setOption(option));
  chart._onframe();
  quiet(() => chart.renderToSVGString());
}
function globalT(el) {
  const chain = [];
  for (let e = el; e; e = e.parent) chain.unshift(e);
  chain.forEach(e => e.updateTransform());
  const t = el.transform;
  return t ? [t[0], t[1], t[2], t[3], t[4], t[5]] : [1, 0, 0, 1, 0, 0];
}

// the refContainer createBoxLayoutReference takes: the host's dataToLayout of
// getCoordForCoordSysUsageKindBox's coord, contentRect || rect
function refOf(model) {
  const cs = model.boxCoordinateSystem;
  if (!cs) return null;
  let coord = model.getShallow('coord', true);
  if (coord == null && model.mainType === 'series' && model.subType === 'pie') coord = model.getShallow('center');
  const r = cs.dataToLayout(coord);
  return r.contentRect || r.rect;
}
const refRec = model => {
  const r = refOf(model);
  return r ? rectRec(r) : null;
};

function sectorsOf(data) {
  const out = [];
  data.each(i => {
    const l = data.getItemLayout(i);
    if (!l) return;
    out.push({ i, cx: hex(l.cx), cy: hex(l.cy), r0: hex(l.r0), r: hex(l.r) });
  });
  return out;
}

function recordSeries(chart, s) {
  const type = s.subType;
  const rec = { seriesIndex: s.seriesIndex, type, boxed: !!s.boxCoordinateSystem, ref: refRec(s) };
  const data = s.getData();
  if (type === 'pie' || type === 'sunburst') rec.sectors = sectorsOf(data);
  else if (type === 'chord') rec.sectors = sectorsOf(data);
  else if (type === 'funnel') {
    rec.items = [];
    data.each(i => {
      const l = data.getItemLayout(i);
      if (l && l.points) rec.items.push({ i, points: l.points.map(p => [hex(p[0]), hex(p[1])]) });
    });
  }
  else if (type === 'sankey' || type === 'tree' || type === 'treemap') {
    rec.layoutInfo = s.layoutInfo ? rectRec(s.layoutInfo) : null;
    rec.nodes = [];
    data.each(i => {
      const l = data.getItemLayout(i);
      if (!l) return;
      if (type === 'sankey') rec.nodes.push({ i, x: hex(l.x), y: hex(l.y), dx: hex(l.dx), dy: hex(l.dy) });
      else if (type === 'tree') rec.nodes.push({ i, x: hex(l.x), y: hex(l.y) });
      else rec.nodes.push({ i, x: hex(l.x), y: hex(l.y), width: hex(l.width), height: hex(l.height) });
    });
    if (type === 'treemap') {
      const view = chart.getViewOfSeriesModel(s);
      rec.crumbs = [];
      const bc = view._breadcrumb;
      if (bc && bc.group) {
        bc.group.children().forEach(el => {
          if (el.type !== 'polygon') return;
          const t = globalT(el);
          rec.crumbs.push(el.shape.points.map(p => [hex(t[0] * p[0] + t[2] * p[1] + t[4]), hex(t[1] * p[0] + t[3] * p[1] + t[5])]));
        });
      }
    }
  }
  else if (type === 'graph') {
    const cs = s.coordinateSystem;
    rec.view = cs.type;
    rec.viewRect = cs.getViewRect ? rectRec(cs.getViewRect()) : null;
    rec.nodes = [];
    data.each(i => {
      const l = data.getItemLayout(i);
      if (!l) return;
      const p = cs.dataToPoint(l);
      rec.nodes.push({ i, x: hex(p[0]), y: hex(p[1]) });
    });
  }
  else if (type === 'gauge') {
    const view = chart.getViewOfSeriesModel(s);
    let c = null;
    view.group.traverse(e => {
      if (!c && e.type === 'sector') c = [hex(e.shape.cx), hex(e.shape.cy)];
    });
    rec.centre = c;
  }
  return rec;
}

function recordChart(chart, c) {
  const ec = chart.getModel();
  const rec = { matrices: [], grids: [], polars: [], calls: [], titles: [], legends: [], series: [] };
  ec.eachComponent('matrix', m => rec.matrices.push({ index: m.componentIndex, rect: rectRec(m.coordinateSystem.getRect()) }));
  ec.eachComponent('grid', g => rec.grids.push({ index: g.componentIndex, boxed: !!g.boxCoordinateSystem,
    ref: refRec(g), rect: rectRec(g.coordinateSystem.getRect()) }));
  ec.eachComponent('polar', p => {
    const cs = p.coordinateSystem;
    const ext = cs.getRadiusAxis().getExtent();
    rec.polars.push({ index: p.componentIndex, boxed: !!p.boxCoordinateSystem, ref: refRec(p),
      cx: hex(cs.cx), cy: hex(cs.cy), r: [hex(ext[0]), hex(ext[1])] });
  });
  (c.calls || []).forEach(q => {
    const ret = quiet(() => chart.convertToPixel(q.finder, q.value));
    rec.calls.push({ finder: q.finder, value: q.value, ret: Array.isArray(ret) ? ret.map(hex) : null });
  });
  ec.eachComponent('title', t => {
    const view = chart.getViewOfComponentModel(t);
    const g = view.group;
    const kids = g.children();
    const textEl = kids.find(k => k.type === 'text');
    const bgEl = kids.find(k => k.type === 'rect');
    rec.titles.push({ index: t.componentIndex, boxed: !!t.boxCoordinateSystem, ref: refRec(t),
      shown: kids.length > 0,
      group: [hex(g.x), hex(g.y)],
      bg: bgEl ? { x: hex(g.x + bgEl.shape.x), y: hex(g.y + bgEl.shape.y), width: hex(bgEl.shape.width), height: hex(bgEl.shape.height) } : null,
      align: textEl && textEl.style.align != null ? textEl.style.align : null,
      verticalAlign: textEl && textEl.style.verticalAlign != null ? textEl.style.verticalAlign : null });
  });
  ec.eachComponent('legend', l => {
    const view = chart.getViewOfComponentModel(l);
    const t = globalT(view.group);
    rec.legends.push({ index: l.componentIndex, boxed: !!l.boxCoordinateSystem, ref: refRec(l),
      group: [hex(t[4]), hex(t[5])],
      items: view.getContentGroup().children().map(it => {
        const te = it.children().filter(k => k.type === 'text');
        const gt = globalT(it);
        const r = it.getBoundingRect();
        return { i: it.__legendDataIndex, name: te.length ? te[0].style.text : null,
          t: [hex(gt[4]), hex(gt[5])], r: [hex(r.x), hex(r.y), hex(r.width), hex(r.height)] };
      }) });
  });
  ec.eachSeries(s => rec.series.push(recordSeries(chart, s)));
  return rec;
}

// ---------- the cases ----------
const CASES = [];
const add = (group, id, note, option, extra) => CASES.push(Object.assign({ group, id, note, option }, extra || {}));
const gal = (name, note, extra) => CASES.push(Object.assign({ group: 'gallery', id: 'gallery-' + name, note, gallery: name }, extra || {}));

// a matrix whose cells are fractional: 713 / 4 wide, 527 / 7 tall
const MX = () => ({ left: 51, right: 36, top: 33, bottom: 40,
  x: { data: ['a', 'b', 'c'] }, y: { data: ['p', 'q', 'r', 's', 't', 'u'] } });
const CAL = () => ({ range: '2017-02', cellSize: [90, 70], left: 40, top: 60 });
const WEEK = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

add('grid', 'grid-matrix-default', 'a grid over a 3 x 3 range of cells, its default box (10% / 60 / 60) and outer bounds on the cell',
  { matrix: MX(), grid: { coordinateSystem: 'matrix', coord: [['a', 'c'], ['p', 'r']] },
    xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [120, 200, 150, 80, 70, 110, 130] }] },
  { calls: [{ finder: { gridIndex: 0 }, value: ['Wed', 30] }, { finder: { gridIndex: 0 }, value: ['Mon', 0] }, { finder: { gridIndex: 0 }, value: ['Sun', 200] }] });

add('grid', 'grid-matrix-boxes', 'four grids in cells: px / percent edges with outerBoundsMode none, containLabel, axis names on the default box, outerBounds and a size',
  { matrix: MX(),
    grid: [
      { coordinateSystem: 'matrix', coord: ['a', 's'], left: 10, right: '8%', top: 5, bottom: 12, outerBoundsMode: 'none' },
      { coordinateSystem: 'matrix', coord: ['b', 's'], left: 0, right: 0, top: 0, bottom: 0, containLabel: true },
      { coordinateSystem: 'matrix', coord: [['b', 'c'], ['t', 'u']] },
      { coordinateSystem: 'matrix', coord: ['c', 's'], left: 20, top: 10, width: 100, height: 40, outerBounds: { left: 4, right: 4, top: 2, bottom: 2 } }],
    xAxis: [{ gridIndex: 0, type: 'value' }, { gridIndex: 1, type: 'value' }, { gridIndex: 2, type: 'value', name: 'X name' }, { gridIndex: 3, type: 'category', data: ['u', 'v', 'w'] }],
    yAxis: [{ gridIndex: 0, type: 'value' }, { gridIndex: 1, type: 'value' }, { gridIndex: 2, type: 'value', name: 'Y' }, { gridIndex: 3, type: 'value' }],
    series: [
      { type: 'scatter', xAxisIndex: 0, yAxisIndex: 0, data: [[1, 2], [5, 9], [3, 4]] },
      { type: 'line', xAxisIndex: 1, yAxisIndex: 1, data: [[10, 200], [30, 1400], [70, 900]] },
      { type: 'line', xAxisIndex: 2, yAxisIndex: 2, data: [[-3, 2], [4, 7.5], [9, 1]] },
      { type: 'bar', xAxisIndex: 3, yAxisIndex: 3, data: [3, 8, 5] }] },
  { calls: [0, 1, 2].map(g => ({ finder: { gridIndex: g }, value: [3, 4] })).concat([{ finder: { gridIndex: 3 }, value: ['v', 5] }]) });

add('grid', 'grid-matrix-merged', 'a grid on one cell of a merged block: dataToLayout expands it to the block',
  { matrix: Object.assign(MX(), { body: { data: [{ coord: [['a', 'b'], ['q', 'r']], mergeCells: true }] } }),
    grid: { coordinateSystem: 'matrix', coord: ['b', 'r'], left: 30, right: 10, top: 10, bottom: 25 },
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: { type: 'line', data: [[0, 0], [10, 7], [20, 3]] } },
  { calls: [{ finder: { gridIndex: 0 }, value: [10, 7] }] });

add('grid', 'grid-calendar', 'grids in calendar days: the content rect; outerBoundsMode none, and the default box',
  { calendar: CAL(),
    grid: [
      { coordinateSystem: 'calendar', coord: '2017-02-07', left: 2, right: 2, top: 2, bottom: 2, outerBoundsMode: 'none' },
      { coordinateSystem: 'calendar', coord: ['2017-02-15'], left: 4, right: 4, top: 4, bottom: 4 }],
    xAxis: [{ gridIndex: 0, type: 'value', show: false }, { gridIndex: 1, type: 'category', data: ['x', 'y'], show: false }],
    yAxis: [{ gridIndex: 0, type: 'value', show: false }, { gridIndex: 1, type: 'value', show: false }],
    series: [{ type: 'line', xAxisIndex: 0, yAxisIndex: 0, data: [[1, 1], [2, 4]] },
      { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: [2, 5] }] },
  { calls: [{ finder: { gridIndex: 0 }, value: [2, 4] }, { finder: { gridIndex: 1 }, value: ['y', 5] }] });

add('grid', 'grid-fallbacks', "grids whose host gives them nothing: usage 'data', a matrixIndex not there, a coordinate system that hosts no component, a usage word that is neither; and one by matrixId on a second matrix",
  { matrix: [MX(), Object.assign(MX(), { id: 'm2', left: 420, right: 20, top: 300, bottom: 20 })],
    grid: [
      { coordinateSystem: 'matrix', coordinateSystemUsage: 'data', coord: ['a', 'p'] },
      { coordinateSystem: 'matrix', matrixIndex: 3, coord: ['a', 'p'], left: 30, right: 30 },
      { coordinateSystem: 'polar', coord: ['a', 'p'], top: 100, bottom: 100 },
      { coordinateSystem: 'matrix', coordinateSystemUsage: 'sideways', coord: ['a', 'p'], left: 200 },
      { coordinateSystem: 'matrix', matrixId: 'm2', coord: ['c', 'u'], left: 5, right: 5, top: 5, bottom: 5, outerBoundsMode: 'none' }],
    xAxis: [0, 1, 2, 3, 4].map(g => ({ gridIndex: g, type: 'value', show: false })),
    yAxis: [0, 1, 2, 3, 4].map(g => ({ gridIndex: g, type: 'value', show: false })),
    series: [0, 1, 2, 3, 4].map(g => ({ type: 'line', xAxisIndex: g, yAxisIndex: g, data: [[0, 0], [1, 1]] })) },
  { calls: [0, 1, 2, 3, 4].map(g => ({ finder: { gridIndex: g }, value: [1, 1] })),
    twin: o => { [0, 1, 2, 3].forEach(k => { delete o.grid[k].coordinateSystem; delete o.grid[k].coordinateSystemUsage; delete o.grid[k].matrixIndex; delete o.grid[k].coord; }); },
    twinGrids: [0, 1, 2, 3] });

add('polar', 'polar-matrix', 'polars in cells: the default centre and radius, a percentage centre and a mixed radius over a range',
  { matrix: MX(),
    polar: [{ coordinateSystem: 'matrix', coord: ['b', 'q'] },
      { coordinateSystem: 'matrix', coord: [['b', 'c'], ['s', 'u']], center: ['30%', '60%'], radius: ['10%', 40] }],
    angleAxis: [{ polarIndex: 0, type: 'category', data: ['n', 'e', 's', 'w'] }, { polarIndex: 1, type: 'value' }],
    radiusAxis: [{ polarIndex: 0 }, { polarIndex: 1 }],
    series: [{ type: 'bar', coordinateSystem: 'polar', polarIndex: 0, data: [1, 2, 3, 4] },
      { type: 'line', coordinateSystem: 'polar', polarIndex: 1, data: [[1, 10], [3, 200], [2, 300]] }] },
  { calls: [{ finder: { polarIndex: 0 }, value: [2, 'e'] }, { finder: { polarIndex: 1 }, value: [2, 100] }] });

add('polar', 'polar-calendar', 'a polar in a calendar day',
  { calendar: CAL(), polar: { coordinateSystem: 'calendar', coord: '2017-02-21', radius: '90%' },
    angleAxis: { type: 'value' }, radiusAxis: {},
    series: { type: 'line', coordinateSystem: 'polar', data: [[1, 10], [2, 120]] } },
  { calls: [{ finder: { polarIndex: 0 }, value: [1, 10] }] });

add('title', 'title-matrix', "titles in cells: centred, right and bottom with padding, a percentage left over a range, the defaults, a coord that names no cell, and two the host gives nothing (a matrixIndex not there, usage 'data')",
  { matrix: MX(), title: [
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Centre', subtext: 'sub line', coordinateSystem: 'matrix', coord: ['b', 'q'], left: 'center', top: 'middle', backgroundColor: '#eee' },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Right', coordinateSystem: 'matrix', coord: ['c', 'p'], right: 10, bottom: 0, padding: [4, 6], backgroundColor: '#eee' },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Left', coordinateSystem: 'matrix', coord: [['a', 'b'], 'r'], left: '10%', top: 5 },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Plain', subtext: 's', coordinateSystem: 'matrix', coord: ['a', 'p'] },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Gone', coordinateSystem: 'matrix', coord: ['zz', 'p'] },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Canvas', coordinateSystem: 'matrix', matrixIndex: 4, coord: ['a', 'p'], left: 'right' },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Data', coordinateSystem: 'matrix', coordinateSystemUsage: 'data', coord: ['a', 'p'], top: 'bottom' }] },
  { twin: o => { [5, 6].forEach(k => { delete o.title[k].coordinateSystem; delete o.title[k].coordinateSystemUsage; delete o.title[k].matrixIndex; delete o.title[k].coord; }); },
    twinTitles: [5, 6] });

add('title', 'title-calendar', 'titles in calendar days: centred in the content rect, and right-aligned',
  { calendar: CAL(), title: [
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'Day', coordinateSystem: 'calendar', coord: '2017-02-07', left: 'center', top: 'center' },
    { textStyle: { fontSize: 16 }, subtextStyle: { fontSize: 11 }, text: 'R', subtext: 'x', coordinateSystem: 'calendar', coord: ['2017-02-16'], right: 0, top: 0 }] });

add('legend', 'legend-matrix', 'legends in cells: a horizontal one wrapping in its cell, a vertical one on the right of another',
  { matrix: MX(),
    legend: [{ coordinateSystem: 'matrix', coord: ['c', ['p', 'q']] },
      { coordinateSystem: 'matrix', coord: ['a', ['t', 'u']], orient: 'vertical', right: 0, top: 'middle' }],
    xAxis: { show: false }, yAxis: { show: false },
    series: ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta'].map(n => ({ type: 'line', name: n, data: [] })) });

add('legend', 'legend-calendar', 'a legend in a calendar day',
  { calendar: CAL(), legend: { coordinateSystem: 'calendar', coord: '2017-02-22', left: 0 },
    xAxis: { show: false }, yAxis: { show: false },
    series: ['One', 'Two'].map(n => ({ type: 'line', name: n, data: [] })) });

add('series', 'pie-cells', "pies: by coord with a percentage radius, by center read as a coord, by coord with a percentage centre and a ring, on a calendar day by coord and by center, and one whose matrix is not there",
  { matrix: MX(), calendar: Object.assign(CAL(), { top: 330 }), series: [
    { type: 'pie', coordinateSystem: 'matrix', coord: ['a', 'p'], radius: '60%', data: [1, 2, 3] },
    { type: 'pie', coordinateSystem: 'matrix', center: ['b', 'p'], radius: 20, data: [4, 1] },
    { type: 'pie', coordinateSystem: 'matrix', coord: [['b', 'c'], ['q', 'r']], center: ['30%', '40%'], radius: ['20%', '50%'], data: [2, 2, 5] },
    { type: 'pie', coordinateSystem: 'calendar', coord: '2017-02-08', radius: '80%', data: [1, 3] },
    { type: 'pie', coordinateSystem: 'calendar', center: '2017-02-10', radius: 15, data: [3, 1] },
    { type: 'pie', coordinateSystem: 'matrix', matrixIndex: 5, coord: ['a', 'p'], data: [1, 1] }] },
  { twin: o => { delete o.series[5].coordinateSystem; delete o.series[5].matrixIndex; delete o.series[5].coord; }, twinSeries: [5] });

add('series', 'funnel-cells', 'funnels in a matrix cell (a left and a percentage width) and in a calendar day',
  { matrix: MX(), calendar: Object.assign(CAL(), { top: 330 }), series: [
    { type: 'funnel', coordinateSystem: 'matrix', coord: [['b', 'c'], ['p', 'q']], left: 10, width: '50%', data: [5, 3, 1] },
    { type: 'funnel', coordinateSystem: 'calendar', coord: '2017-02-14', data: [2, 1] }] });

const SK_NODES = [{ name: 'A' }, { name: 'B' }, { name: 'C' }, { name: 'D' }];
const SK_LINKS = [{ source: 'A', target: 'B', value: 5 }, { source: 'A', target: 'C', value: 3 }, { source: 'B', target: 'D', value: 4 }, { source: 'C', target: 'D', value: 2 }];
add('series', 'sankey-cells', 'sankeys: the default box over a range of cells, edges at zero in a calendar day, and one whose calendar is not there (one whose matrix is not there throws: createGraphFromNodeEdge asks the matrix for its dimensions)',
  { matrix: MX(), calendar: Object.assign(CAL(), { top: 330 }), series: [
    { type: 'sankey', coordinateSystem: 'matrix', coord: [['a', 'b'], ['p', 'r']], data: SK_NODES, links: SK_LINKS },
    { type: 'sankey', coordinateSystem: 'calendar', coord: '2017-02-15', left: 0, right: 0, top: 0, bottom: 0, label: { show: false }, data: SK_NODES, links: SK_LINKS },
    { type: 'sankey', coordinateSystem: 'calendar', calendarIndex: 9, coord: '2017-02-15', data: SK_NODES, links: SK_LINKS }] },
  { twin: o => { delete o.series[2].coordinateSystem; delete o.series[2].calendarIndex; delete o.series[2].coord; }, twinSeries: [2] });

const TREE = [{ name: 'root', children: [{ name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'b' }, { name: 'c', children: [{ name: 'c1' }] }] }];
add('series', 'tree-cells', 'trees in cells: orthogonal with the default box, radial over a range',
  { matrix: MX(), series: [
    { type: 'tree', coordinateSystem: 'matrix', coord: [['a', 'b'], ['p', 'q']], data: TREE },
    { type: 'tree', coordinateSystem: 'matrix', coord: [['b', 'c'], ['s', 'u']], layout: 'radial', data: TREE }] });

const TM = [{ name: 'A', value: 10, children: [{ name: 'A1', value: 6 }, { name: 'A2', value: 4 }] }, { name: 'B', value: 5 }, { name: 'C', value: 3 }];
add('series', 'treemap-cells', 'treemaps: one over a range of cells with its breadcrumb, one in a calendar day with no breadcrumb',
  { matrix: MX(), calendar: Object.assign(CAL(), { top: 330 }), series: [
    { type: 'treemap', coordinateSystem: 'matrix', coord: [['a', 'c'], ['p', 'r']], data: TM },
    { type: 'treemap', coordinateSystem: 'calendar', coord: '2017-02-23', breadcrumb: { show: false }, data: TM }] });

const GN = [{ name: 'A', x: 0, y: 0 }, { name: 'B', x: 10, y: 5 }, { name: 'C', x: 4, y: 12 }];
const GL = [{ source: 'A', target: 'B' }, { source: 'B', target: 'C' }];
add('series', 'graph-box', "graphs with usage 'box': layout none in a cell, circular over a range, none in a calendar day",
  { matrix: MX(), calendar: Object.assign(CAL(), { top: 330 }), series: [
    { type: 'graph', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: ['a', 'q'], data: GN, links: GL },
    { type: 'graph', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: [['b', 'c'], ['p', 'q']], layout: 'circular', data: GN.map(n => ({ name: n.name })), links: GL },
    { type: 'graph', coordinateSystem: 'calendar', coordinateSystemUsage: 'box', coord: '2017-02-20', data: GN, links: GL }] });

const CN = [{ name: 'A' }, { name: 'B' }, { name: 'C' }];
const CL = [{ source: 'A', target: 'B', value: 3 }, { source: 'B', target: 'C', value: 2 }, { source: 'C', target: 'A', value: 4 }];
add('series', 'chord-cells', "chords: usage 'box' in a cell, on a calendar day, and with no usage (a series' default 'data': the canvas)",
  { matrix: MX(), calendar: Object.assign(CAL(), { top: 330 }), series: [
    { type: 'chord', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: [['a', 'b'], ['p', 'q']], data: CN, links: CL },
    { type: 'chord', coordinateSystem: 'calendar', coordinateSystemUsage: 'box', coord: '2017-02-09', radius: ['60%', '70%'], data: CN, links: CL },
    { type: 'chord', coordinateSystem: 'matrix', coord: ['c', 'u'], radius: ['20%', '25%'], data: CN, links: CL }] },
  { twin: o => { delete o.series[2].coordinateSystem; delete o.series[2].coord; }, twinSeries: [2] });

add('series', 'canvas-types', "a gauge (no usage and 'box') and a sunburst ('box') naming a matrix cell: their layouts read the canvas",
  { matrix: MX(), series: [
    { type: 'gauge', coordinateSystem: 'matrix', coord: ['a', 'p'], radius: '30%', center: ['25%', '50%'], progress: { show: true }, data: [{ value: 40 }] },
    { type: 'gauge', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: ['b', 'p'], radius: '30%', center: ['75%', '50%'], progress: { show: true }, data: [{ value: 70 }] },
    { type: 'sunburst', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: ['c', 'p'], radius: [0, '20%'], data: [{ name: 'x', value: 4, children: [{ name: 'y', value: 2 }] }] }] },
  { twin: o => { o.series.forEach(s => { delete s.coordinateSystem; delete s.coordinateSystemUsage; delete s.coord; }); }, twinSeries: [0, 1, 2] });

gal('matrix-stock', 'the gallery: five grids (time axes with breaks) and four titles in merged cells',
  { calls: [
    { finder: { gridIndex: 0 }, value: [1760578200000, 50.27172021701132] },
    { finder: { gridIndex: 1 }, value: [1760578260000, 714.5643377347881] },
    { finder: { gridIndex: 2 }, value: [1760580240000, -0.001119309246099931] },
    { finder: { gridIndex: 3 }, value: [43, 0] },
    { finder: { gridIndex: 4 }, value: [3, 10178] }] });

function load(c) {
  if (!c.gallery) return clone(c.option);
  return JSON.parse(fs.readFileSync(path.join(GALLERY, c.gallery + '.json'), 'utf8'));
}

function runOne(c, option) {
  const chart = mk();
  try {
    option.animation = false;
    draw(chart, option);
    return { rec: recordChart(chart, c), chart: null };
  } finally {
    chart.dispose();
  }
}

// R1 / R2 / R3 inside one case
function recipes(c, rec, option) {
  const fails = [];
  const chart = mk();
  try {
    option.animation = false;
    draw(chart, option);
    const ec = chart.getModel();
    const r1 = (what, model, got) => {
      if (!model.boxCoordinateSystem) {
        if (got !== null) fails.push(what + ': a ref without a box coordinate system');
        return null;
      }
      const ref = refOf(model);
      if (JSON.stringify(rectRec(ref)) !== JSON.stringify(got)) fails.push(what + ': the ref is not the host\'s dataToLayout');
      return ref;
    };
    ec.eachComponent('grid', g => {
      const r = rec.grids.find(q => q.index === g.componentIndex);
      const ref = r1('grid ' + g.componentIndex, g, r.ref);
      if (ref && g.get('outerBoundsMode', true) === 'none') {
        const lr = echarts.helper.getLayoutRect(g.getBoxLayoutParams(), ref);
        if (!sameRect(lr, g.coordinateSystem.getRect())) fails.push('grid ' + g.componentIndex + ': not getLayoutRect in the ref');
      }
    });
    ec.eachComponent('polar', p => r1('polar ' + p.componentIndex, p, rec.polars.find(q => q.index === p.componentIndex).ref));
    ec.eachComponent('title', t => r1('title ' + t.componentIndex, t, rec.titles.find(q => q.index === t.componentIndex).ref));
    ec.eachComponent('legend', l => r1('legend ' + l.componentIndex, l, rec.legends.find(q => q.index === l.componentIndex).ref));
    ec.eachSeries(s => {
      const r = rec.series.find(q => q.seriesIndex === s.seriesIndex);
      const ref = r1('series ' + s.seriesIndex, s, r.ref);
      if (ref && (s.subType === 'sankey' || s.subType === 'tree' || s.subType === 'treemap')) {
        const lr = echarts.helper.getLayoutRect(s.getBoxLayoutParams(), ref);
        if (!sameRect(lr, s.layoutInfo)) fails.push('series ' + s.seriesIndex + ': the layoutInfo is not getLayoutRect in the ref');
      }
    });
  } finally {
    chart.dispose();
  }
  // R3: what the host gives nothing is what no coordinateSystem gives
  if (c.twin) {
    const o2 = load(c);
    c.twin(o2);
    const tw = runOne(c, o2).rec;
    (c.twinGrids || []).forEach(k => {
      const a = rec.grids.find(q => q.index === k);
      const b = tw.grids.find(q => q.index === k);
      if (a.boxed || JSON.stringify(a.rect) !== JSON.stringify(b.rect)) fails.push('grid ' + k + ': not laid out as with no coordinateSystem');
    });
    (c.twinTitles || []).forEach(k => {
      const a = rec.titles.find(q => q.index === k);
      const b = tw.titles.find(q => q.index === k);
      if (a.boxed || JSON.stringify(a.group) !== JSON.stringify(b.group)) fails.push('title ' + k + ': not laid out as with no coordinateSystem');
    });
    (c.twinSeries || []).forEach(k => {
      const a = rec.series.find(q => q.seriesIndex === k);
      const b = tw.series.find(q => q.seriesIndex === k);
      const strip = q => JSON.stringify(Object.assign({}, q, { boxed: null, ref: null }));
      if (strip(a) !== strip(b)) fails.push('series ' + k + ': not laid out as with no coordinateSystem');
    });
  }
  return fails;
}

function runCase(c) {
  const option = load(c);
  const rec = runOne(c, clone(option)).rec;
  const out = { id: c.id, group: c.group, note: c.note, gallery: c.gallery || null,
    option: c.gallery ? null : clone(c.option), fails: recipes(c, rec, clone(option)) };
  return Object.assign(out, rec);
}

// ---------- the facts ----------
function guards(out) {
  const g = [];
  const guard = (name, fn) => {
    let ok = false;
    try { ok = !!fn(); } catch (e) { ok = false; }
    g.push({ name, ok });
  };
  const by = id => out.cases.find(q => q.id === id);
  const n = h => num(h);
  out.cases.forEach(q => guard(q.id + ': the recipes hold (R1-R3)', () => q.fails.length === 0));
  guard('every case draws something boxed', () => out.cases.every(q =>
    q.grids.concat(q.polars, q.titles, q.legends, q.series).some(r => r.boxed)));
  // the grid
  guard('a default grid shrinks inside its cell, not the canvas', () => {
    const r = by('grid-matrix-default').grids[0];
    return n(r.rect.x) > n(r.ref.x) && n(r.rect.x) + n(r.rect.width) < n(r.ref.x) + n(r.ref.width) && n(r.rect.height) < 200;
  });
  guard('outerBoundsMode none keeps the cell\'s box exactly', () => {
    const r = by('grid-matrix-boxes').grids[0];
    return Object.is(n(r.rect.x), n(r.ref.x) + 10);
  });
  guard('a merged block expands the grid\'s cell', () => {
    const c = by('grid-matrix-merged');
    return n(c.grids[0].ref.width) > n(c.matrices[0].rect.width) / 4 * 1.5;
  });
  guard('a grid in a calendar day takes the content rect (a half pixel in)', () => {
    const r = by('grid-calendar').grids[0];
    return Object.is(n(r.ref.x) % 1, 0.5) && Object.is(n(r.rect.x), n(r.ref.x) + 2);
  });
  guard('fallbacks are on the canvas, matrixId finds the second matrix', () => {
    const c = by('grid-fallbacks');
    return c.grids.slice(0, 4).every(r => !r.boxed) && c.grids[4].boxed
      && n(c.grids[4].ref.x) >= n(c.matrices[1].rect.x);
  });
  // the polar
  guard('a polar\'s default centre is its cell\'s centre', () => {
    const p = by('polar-matrix').polars[0];
    return Object.is(n(p.cx), n(p.ref.width) * 0.5 + n(p.ref.x));
  });
  guard('a polar\'s radius is of half its cell\'s shorter side', () => {
    const p = by('polar-matrix').polars[1];
    return Object.is(n(p.r[0]), Math.min(n(p.ref.width), n(p.ref.height)) / 2 * 0.1) && Object.is(n(p.r[1]), 40);
  });
  // the title
  guard('a centred title is centred on its cell', () => {
    const t = by('title-matrix').titles[0];
    return Math.abs(n(t.group[0]) - (n(t.ref.x) + n(t.ref.width) / 2)) < 1e-9 && t.align === 'center';
  });
  guard('a title whose coord names no column is placed in its row at x nought (getLayoutRect: containerRect.x || 0, left || 0)', () => {
    const t = by('title-matrix').titles[4];
    return Number.isNaN(n(t.ref.x)) && Number.isNaN(n(t.ref.width)) && t.align === 'center'
      && n(t.group[0]) > 0 && n(t.group[0]) < 100 && Object.is(n(t.group[1]), n(t.ref.y) + 15 + 5);
  });
  guard('a title in a calendar day is in its content rect (right 0 keeps the left align: `left || right` is 0)', () => {
    const t = by('title-calendar').titles[1];
    return t.align === 'left' && n(t.group[0]) > n(t.ref.x) && n(t.group[0]) < n(t.ref.x) + n(t.ref.width)
      && Object.is(n(t.group[1]), n(t.ref.y) + 5);
  });
  // the legend
  guard('a legend wraps in its cell: its items stack', () => {
    const l = by('legend-matrix').legends[0];
    return l.items.length === 6 && n(l.items[5].t[1]) > n(l.items[0].t[1]);
  });
  guard('a vertical legend sits on its cell\'s right edge', () => {
    const l = by('legend-matrix').legends[1];
    return n(l.group[0]) < n(l.ref.x) + n(l.ref.width) && n(l.group[0]) > n(l.ref.x);
  });
  // the series
  guard('a pie by center sits at the cell\'s centre', () => {
    const s = by('pie-cells').series[1];
    return Object.is(n(s.sectors[0].cx), n(s.ref.x) + n(s.ref.width) / 2);
  });
  guard('a pie on a calendar day by center sits at the content rect\'s centre', () => {
    const s = by('pie-cells').series[4];
    return Object.is(n(s.sectors[0].cy), n(s.ref.y) + n(s.ref.height) / 2);
  });
  guard('a pie whose matrix is not there is on the canvas', () => {
    const s = by('pie-cells').series[5];
    return !s.boxed && Object.is(n(s.sectors[0].cx), 400);
  });
  guard('a funnel in a calendar day is in it', () => {
    const s = by('funnel-cells').series[1];
    return n(s.items[0].points[0][0]) >= n(s.ref.x);
  });
  guard('a sankey at zero edges fills its day', () => {
    const s = by('sankey-cells').series[1];
    return JSON.stringify(s.layoutInfo) === JSON.stringify(s.ref);
  });
  guard('a radial tree is in its cells', () => {
    const s = by('tree-cells').series[1];
    return s.boxed && n(s.layoutInfo.x) > n(by('tree-cells').matrices[0].rect.x);
  });
  guard('the treemap\'s breadcrumb is in its cells', () => {
    const s = by('treemap-cells').series[0];
    return s.crumbs.length > 0 && n(s.crumbs[0][0][0]) >= n(s.ref.x) && n(s.crumbs[0][0][1]) < n(s.ref.y) + n(s.ref.height);
  });
  guard('a graph with usage box lays its view in the cell', () => {
    const s = by('graph-box').series[0];
    return s.view === 'view' && n(s.viewRect.x) >= n(s.ref.x) && n(s.viewRect.y) >= n(s.ref.y);
  });
  guard('a chord with usage box is in its cell, with none on the canvas', () => {
    const c = by('chord-cells');
    return c.series[0].boxed && !c.series[2].boxed && Object.is(n(c.series[2].sectors[0].cx), 400);
  });
  guard('a gauge and a sunburst naming a cell are on the canvas', () => {
    const c = by('canvas-types');
    return Object.is(n(c.series[0].centre[0]), 200) && Object.is(n(c.series[1].centre[0]), 600)
      && Object.is(n(c.series[2].sectors[0].cx), 400);
  });
  guard('the stock\'s five grids and four titles are in its cells', () => {
    const c = by('gallery-matrix-stock');
    return c.grids.length === 5 && c.grids.every(r => r.boxed) && c.titles.filter(t => t.boxed).length === 4;
  });
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: ' + W + ' x ' + H + ', SVG ssr (chart._ssr false), animation false; the gallery options fed verbatim.',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'a gauge, a sunburst, and a chord with no usage are laid out on the canvas whatever they name: their layouts never ask createBoxLayoutReference (gauge, sunburst) or have no box coordinate system (data usage).',
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
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
out1.cases.forEach(q => q.fails.slice(0, 8).forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
