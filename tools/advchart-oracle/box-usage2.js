/*
Upstream's own answers for roadmap D13 part two (BX2), batch 154:
coordinateSystemUsage 'box' for the rest of what ECharts 6.1 lets a matrix
cell or a calendar day host, and for the two hosts a series may also take a
point from.

THE COMPONENTS (Matrix.create / Calendar.create inject into every component,
decideCoordSysUsageKind's component default is 'box', and each layout asks
createBoxLayoutReference for its refContainer):
  visualMap         VisualMapView.positionGroup (positionElement in the ref;
                    the item align's 'auto' still reads the canvas)
  dataZoom slider   SliderZoomView._resetLocation (getLayoutRect in the ref;
                    the 'ph' defaults mix the ref's size with the target
                    grid's rect, and a slider with no target grid reads the
                    canvas)
  toolbox           ToolboxView.render (getLayoutRect and positionElement in
                    the ref, with the padding)
  timeline          SliderTimelineView's getViewRect (getLayoutRect in the
                    ref, with the padding)
  thumbnail         ThumbnailView.render (getLayoutRect in the ref)
  radar             Radar.resize (centre and radius in the ref)
  singleAxis        Single.resize (getLayoutRect in the ref)
  parallel          Parallel.resize (getLayoutRect in the ref)
  geo               geoCreator.resizeGeo (getLayoutRect with the aspect and
                    applyPreserveAspect, or layoutCenter / layoutSize, in the
                    ref)
THE SERIES:
  a map series with usage 'box' (its own geo laid out by resizeGeo in the
  first declared series' ref);
  a pie (usage 'box' by default) and a chord (usage 'box' written) whose
  host is a cartesian or a geo: those have no dataToLayout, so
  createBoxLayoutReference({enableLayoutOnlyByCenter}) takes the host's
  dataToPoint of the coord (a pie's center when it has none) as the centre,
  and the view rect is the canvas'; and a pie's or a chord's coord widens
  the cartesian's axes (scaleRawExtentInfoCreateDeal's boxCoordinateSystem
  branch);
  the series that lay themselves out on the canvas whatever they name, with
  usage 'data' on a matrix: the matrix is their coordinateSystem, and
  convertToPixel through the series answers the matrix's dataToPoint.
THE INTERACTION in cells: updateAxisPointer at a point in a grid in a cell,
findHover, convertFromPixel and containPixel through it; graphRoam and
geoRoam (by action and by the wheel) on a graph and a geo in cells.
THE GALLERY: matrix-mini-bar-geo (twenty grids and ten geos in cells; the map
a stand-in square per canton, as MX3's oracle registers it).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node = false and getDom stubbed (so the roam controllers listen,
as geo-roam.js does), Math.random the port's xorshift32 (seed 2463534242,
reset before every chart), zrender's width table measuring every string,
animation off.

  node tools/advchart-oracle/box-usage2.js

writes tests/fixtures/advchart-box-usage2.json (ORACLE_OUT overrides). Ends
with process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON.

Top level: source, version, seed, W, H, measure {firstCode, ratio[] (hex)},
maps[] {name, text (the GeoJSON registered)}, notes[], cases[], guards[].

A case: id, group, note, gallery (a file under examples/advchart/gallery,
fed verbatim; option is then null) or option (as run), fails[] (recipe
mismatches; must be empty), steps[] (interaction: {action: payload} or
{wheel: [x, y, delta]} -- delta the LCL WheelDelta, zrender's wheelDelta is
delta / 120), and states[] index-parallel to [after setOption, after each
step], each:

  matrices[]    {index, rect}
  grids[]       {index, boxed, ref, rect}
  visualMaps[]  {index, boxed, ref, group [x, y] (the view group's)}
  sliders[]     {index, boxed, ref, location [x, y], size [w, h]}
  toolboxes[]   {index, boxed, ref, group [x, y]}
  timelines[]   {index, boxed, ref, main [x, y], label [x, y] (the two
                groups')}
  thumbnails[]  {index, boxed, ref, box (the background rect), content}
  radars[]      {index, boxed, ref, cx, cy, r0, r}
  singles[]     {index, boxed, ref, rect}
  parallels[]   {index, boxed, ref, rect, axes[] {dim, position [x, y]}}
  geos[]        {index, boxed, ref, view (getViewRect, before roam),
                roam [6] (getRoamTransform)}
  series[]      {seriesIndex, type, boxed, by type: pie / chord sectors[]
                {i, cx, cy, r0, r}; map view (its geo's getViewRect); graph
                nodes[] {i, x, y} (dataToPoint, global)}
  extents[]     {dim, index, extent [lo, hi]} every cartesian axis' scale
  calls[]       {finder, value, ret} convertToPixel ([..] hex, null)
  backs[]       {finder, value, ret} convertFromPixel
  contains[]    {finder, value, ret} containPixel (true / false)
  hovers[]      {at [x, y], hit null | {seriesIndex, dataIndex}} findHover
                (the first state only)
  axes[]        {dim, index, status, value (hex, shown only), sdi [[series,
                dataIndex, dataIndexInside]]} the axisPointer model's axes
  tip           null (no tooltip component) or {visible, show (the
                content's _show), which ('axis:' + series/dataIndex@axis
                per row), anchor [x, y] hex} -- the content's size stubbed
                80 x 40 (tooltip-actions.js)

Guards (any failure: nothing is written, exit 1): every case's recipes (R1
a boxed model's ref is its host's dataToLayout of its coord, R2 a single's,
a parallel's and a thumbnail's box is getLayoutRect of its box params in the
ref, R3 a model the host gives nothing is laid out as with no
coordinateSystem at all), named facts, and the whole fixture generated
twice, byte-identical, no \u0000, parsing back.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-box-usage2.json');
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
  const l = console.log;
  console.warn = () => {};
  console.error = () => {};
  console.log = () => {};
  try { return fn(); } finally { console.warn = w; console.error = e; console.log = l; }
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

// ---------- the maps ----------
const sq = (name, x0, y0, x1, y1) => ({ type: 'Feature', properties: { name },
  geometry: { type: 'Polygon', coordinates: [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]] } });
const MAPS = [
  { name: 'bx2sq', json: { type: 'FeatureCollection', features: [sq('A', 0, 0, 4, 3), sq('B', 4, 0, 6, 3), sq('C', 1, 3, 3, 5)] } },
  // the gallery's stand-in: a square per canton it names (matrix3.js)
  { name: 'target_map', json: { type: 'FeatureCollection', features:
    ['Valais', 'Ticino', 'Graub\u00fcnden', 'Uri', 'Lucerne', 'Neuch\u00e2tel', 'Jura', 'Vaud', 'Thurgau', 'Schwyz']
      .map((name, i) => sq(name, i, 0, i + 1, 1)) } },
];
MAPS.forEach(m => { m.text = JSON.stringify(m.json); echarts.registerMap(m.name, m.text); });

// ---------- the chart ----------
(function enableRoam() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();
function mk() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function settle(chart) {
  chart._onframe();
  quiet(() => chart.renderToSVGString());
  chart.getZr().storage.getDisplayList(true);
}
function globalT(el) {
  const chain = [];
  for (let e = el; e; e = e.parent) chain.unshift(e);
  chain.forEach(e => e.updateTransform());
  const t = el.transform;
  return t ? [t[0], t[1], t[2], t[3], t[4], t[5]] : [1, 0, 0, 1, 0, 0];
}
// the tooltip view watched (tooltip-actions.js): what it shows and where
function watchTooltip(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  const view = m ? chart.getViewOfComponentModel(m) : null;
  const w = { which: null, anchor: null, view };
  if (!view) return w;
  const content = view._tooltipContent;
  must(content, 'no tooltip content');
  content.getSize = () => [80, 40];
  const show = view._showTooltipContent;
  view._showTooltipContent = function (tooltipModel, html, params, ticket, x, y) {
    if (Array.isArray(params)) {
      w.which = 'axis:' + params.map(q => q.seriesIndex + '/' + q.dataIndex + '@' + q.axisDim + q.axisIndex).join(',');
    } else if (params && params.componentType === 'series') {
      w.which = 'item:' + params.seriesIndex + ':' + params.dataIndex;
    } else w.which = 'other';
    w.anchor = [x, y];
    return show.apply(this, arguments);
  };
  return w;
}
function tipRec(w) {
  if (!w || !w.view) return null;
  const c = w.view._tooltipContent;
  const vis = !!(c && c.el && !c.el.ignore && !c.el.invisible);
  return { visible: vis, show: !!c._show, which: vis ? w.which : null, anchor: vis && w.anchor ? w.anchor.map(hex) : null };
}
function fire(chart, name, extra) {
  const zr = chart.getZr();
  zr.storage.getDisplayList(true);
  zr.handler.dispatch(name, Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra));
}

// the refContainer createBoxLayoutReference takes
function refOf(model) {
  const cs = model.boxCoordinateSystem;
  if (!cs || !cs.dataToLayout) return null;
  const coord = model.getShallow('coord', true);
  const r = cs.dataToLayout(coord);
  return r.contentRect || r.rect;
}
const refRec = model => {
  const r = refOf(model);
  return r ? rectRec(r) : null;
};
const base = model => ({ index: model.componentIndex, boxed: !!model.boxCoordinateSystem, ref: refRec(model) });
const viewOf = (chart, model) => chart.getViewOfComponentModel(model);

function sectorsOf(data) {
  const out = [];
  data.each(i => {
    const l = data.getItemLayout(i);
    if (!l) return;
    out.push({ i, cx: hex(l.cx), cy: hex(l.cy), r0: hex(l.r0), r: hex(l.r) });
  });
  return out;
}

function recordState(chart, c, first, w) {
  const ec = chart.getModel();
  const rec = { tip: tipRec(w), matrices: [], grids: [], visualMaps: [], sliders: [], toolboxes: [], timelines: [], thumbnails: [],
    radars: [], singles: [], parallels: [], geos: [], series: [], extents: [], calls: [], backs: [], contains: [],
    hovers: [], axes: [] };
  ec.eachComponent('matrix', m => rec.matrices.push({ index: m.componentIndex, rect: rectRec(m.coordinateSystem.getRect()) }));
  ec.eachComponent('grid', g => rec.grids.push(Object.assign(base(g), { rect: rectRec(g.coordinateSystem.getRect()) })));
  ec.eachComponent('visualMap', v => {
    const t = globalT(viewOf(chart, v).group);
    rec.visualMaps.push(Object.assign(base(v), { group: [hex(t[4]), hex(t[5])] }));
  });
  ec.eachComponent('dataZoom', d => {
    if (d.subType !== 'slider') return;
    const view = viewOf(chart, d);
    rec.sliders.push(Object.assign(base(d), { location: [hex(view._location.x), hex(view._location.y)],
      size: [hex(view._size[0]), hex(view._size[1])] }));
  });
  ec.eachComponent('toolbox', t => {
    const g = viewOf(chart, t).group;
    rec.toolboxes.push(Object.assign(base(t), { group: [hex(g.x), hex(g.y)] }));
  });
  ec.eachComponent('timeline', t => {
    const view = viewOf(chart, t);
    rec.timelines.push(Object.assign(base(t), { main: [hex(view._mainGroup.x), hex(view._mainGroup.y)],
      label: [hex(view._labelGroup.x), hex(view._labelGroup.y)] }));
  });
  ec.eachComponent('thumbnail', t => {
    const view = viewOf(chart, t);
    rec.thumbnails.push(Object.assign(base(t), { box: view._bgRect ? rectRec(view._bgRect.shape) : null,
      content: view._contentRect ? rectRec(view._contentRect) : null }));
  });
  ec.eachComponent('radar', r => {
    const cs = r.coordinateSystem;
    rec.radars.push(Object.assign(base(r), { cx: hex(cs.cx), cy: hex(cs.cy), r0: hex(cs.r0), r: hex(cs.r) }));
  });
  ec.eachComponent('singleAxis', s => rec.singles.push(Object.assign(base(s), { rect: rectRec(s.coordinateSystem.getRect()) })));
  ec.eachComponent('parallel', p => {
    const cs = p.coordinateSystem;
    rec.parallels.push(Object.assign(base(p), { rect: rectRec(cs.getRect()),
      axes: cs.dimensions.map(dim => ({ dim, position: cs.getAxisLayout(dim).position.map(hex) })) }));
  });
  ec.eachComponent('geo', g => {
    const cs = g.coordinateSystem;
    rec.geos.push(Object.assign(base(g), { view: rectRec(cs.getViewRect()),
      roam: cs.getRoamTransform().slice(0, 6).map(hex) }));
  });
  ec.eachSeries(s => {
    const type = s.subType;
    const r = { seriesIndex: s.seriesIndex, type, boxed: !!s.boxCoordinateSystem };
    const data = s.getData();
    if (type === 'pie' || type === 'chord') r.sectors = sectorsOf(data);
    else if (type === 'map') r.view = rectRec(s.coordinateSystem.getViewRect());
    else if (type === 'graph') {
      const cs = s.coordinateSystem;
      r.view = cs.getViewRect ? rectRec(cs.getViewRect()) : null;
      r.roam = cs.getRoamTransform ? cs.getRoamTransform().slice(0, 6).map(hex) : null;
      r.nodes = [];
      data.each(i => {
        const l = data.getItemLayout(i);
        if (!l) return;
        const p = cs.dataToPoint(l);
        r.nodes.push({ i, x: hex(p[0]), y: hex(p[1]) });
      });
    }
    rec.series.push(r);
  });
  ['xAxis', 'yAxis'].forEach(main => ec.eachComponent(main, a => {
    if (!a.axis) return;
    const e = a.axis.scale.getExtent();
    rec.extents.push({ dim: main, index: a.componentIndex, extent: [hex(e[0]), hex(e[1])] });
  }));
  const ret = v => (Array.isArray(v) ? v.map(hex) : null);
  (c.calls || []).forEach(q => rec.calls.push({ finder: q.finder, value: q.value, ret: ret(quiet(() => chart.convertToPixel(q.finder, q.value))) }));
  (c.backs || []).forEach(q => rec.backs.push({ finder: q.finder, value: q.value, ret: ret(quiet(() => chart.convertFromPixel(q.finder, q.value))) }));
  (c.contains || []).forEach(q => rec.contains.push({ finder: q.finder, value: q.value, ret: !!quiet(() => chart.containPixel(q.finder, q.value)) }));
  // before any step only: a tooltip box drawn after one is a hit target in
  // node (a rich Text), not in the port
  (first ? c.hovers || [] : []).forEach(at => {
    chart.getZr().storage.getDisplayList(true);
    const t = chart.getZr().handler.findHover(at[0], at[1]).target;
    let hit = null;
    for (let e = t; e && !hit; e = e.parent) {
      const ed = Object.keys(e).filter(k => k.startsWith('__ec_inner_')).map(k => e[k]).find(v => v && typeof v === 'object' && v.dataIndex != null);
      if (ed && ed.seriesIndex != null) hit = { seriesIndex: ed.seriesIndex, dataIndex: ed.dataIndex };
    }
    rec.hovers.push({ at, hit });
  });
  const ap = ec.getComponent('axisPointer');
  const info = ap && ap.coordSysAxesInfo;
  if (info) {
    Object.keys(info.axesInfo).forEach(key => {
      const ai = info.axesInfo[key];
      const o = ai.axisPointerModel.option;
      const shown = o.status === 'show';
      rec.axes.push({ dim: ai.axis.dim, index: ai.axis.model.componentIndex, status: o.status || 'hide',
        value: shown && typeof o.value === 'number' ? hex(o.value) : null,
        sdi: shown ? (o.seriesDataIndices || []).map(b => [b.seriesIndex, b.dataIndex, b.dataIndexInside]) : [] });
    });
  }
  return rec;
}

// ---------- the cases ----------
const CASES = [];
const add = (group, id, note, option, extra) => CASES.push(Object.assign({ group, id, note, option }, extra || {}));

// BX1's matrix (fractional cells: 713 / 4 wide, 527 / 7 tall) and calendar
const MX = () => ({ left: 51, right: 36, top: 33, bottom: 40,
  x: { data: ['a', 'b', 'c'] }, y: { data: ['p', 'q', 'r', 's', 't', 'u'] } });
const CAL = () => ({ range: '2017-02', cellSize: [90, 70], left: 40, top: 330 });

add('component', 'visualmap-cells', "visualMaps: a continuous one with its defaults in a cell, a piecewise one on a cell's right over a range, a continuous one in a calendar day, and one whose matrix is not there",
  { matrix: MX(), calendar: CAL(),
    visualMap: [
      { type: 'continuous', min: 0, max: 10, itemHeight: 40, coordinateSystem: 'matrix', coord: ['a', 'q'], textStyle: { fontSize: 10 } },
      { type: 'piecewise', pieces: [{ min: 0, max: 3 }, { min: 3, max: 10 }], coordinateSystem: 'matrix', coord: ['c', ['r', 's']], right: 5, top: 'middle', textStyle: { fontSize: 10 } },
      { type: 'continuous', min: 0, max: 10, itemHeight: 30, calculable: true, coordinateSystem: 'calendar', coord: '2017-02-14', left: 'center', top: 2, textStyle: { fontSize: 10 } },
      { type: 'continuous', min: 0, max: 10, coordinateSystem: 'matrix', matrixIndex: 3, coord: ['a', 'p'], right: 10, top: 10, textStyle: { fontSize: 10 } }],
    series: [{ type: 'scatter', coordinateSystem: 'calendar', data: [['2017-02-02', 3], ['2017-02-03', 8]] }] },
  { twin: o => { const v = o.visualMap[3]; delete v.coordinateSystem; delete v.matrixIndex; delete v.coord; }, twinOf: 'visualMaps', twinIdx: [3] });

add('component', 'slider-cells', "sliders: one in a cell with its defaults (the 'ph' places mix the cell's size with its grid's rect), one in a cell with written edges, a vertical one in a calendar day",
  { matrix: MX(), calendar: CAL(),
    grid: { left: 60, right: 60, top: 40, height: 200 },
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    dataZoom: [
      { type: 'slider', xAxisIndex: 0, coordinateSystem: 'matrix', coord: ['b', 'u'], showDetail: false, showDataShadow: false },
      { type: 'slider', xAxisIndex: 0, coordinateSystem: 'matrix', coord: [['a', 'b'], 's'], left: 5, right: 5, top: 5, height: 20, showDetail: false, showDataShadow: false },
      { type: 'slider', yAxisIndex: 0, orient: 'vertical', coordinateSystem: 'calendar', coord: '2017-02-21', showDetail: false, showDataShadow: false }],
    series: [{ type: 'line', data: [[0, 1], [5, 9], [10, 4]] }] });

add('component', 'toolbox-cells', 'toolboxes: one with its defaults (right, top) in a cell, a vertical one centred over a range, one in a calendar day with a padding',
  { matrix: MX(), calendar: CAL(),
    toolbox: [
      { coordinateSystem: 'matrix', coord: ['a', 'p'], feature: { restore: {}, saveAsImage: {} } },
      { coordinateSystem: 'matrix', coord: ['b', ['q', 's']], orient: 'vertical', left: 'center', top: 'middle', feature: { restore: {}, saveAsImage: {}, dataView: {} } },
      { coordinateSystem: 'calendar', coord: '2017-02-08', left: 0, bottom: 0, padding: [3, 4], itemSize: 10, feature: { restore: {} } }] });

add('component', 'timeline-matrix', 'a timeline over a range of cells, with written edges',
  { matrix: MX(),
    timeline: { coordinateSystem: 'matrix', coord: [['a', 'c'], 'u'], left: 10, right: 10, bottom: 2, height: 40, axisType: 'category', data: ['2001', '2002', '2003', '2004'], label: { fontSize: 10 } },
    options: [{}, {}, {}, {}] });

add('component', 'timeline-calendar', 'a timeline in a calendar day with its default box (left 20%, right 20%, bottom 0, height 40)',
  { calendar: CAL(),
    timeline: { coordinateSystem: 'calendar', coord: '2017-02-15', axisType: 'category', data: ['x', 'y'], label: { show: false }, controlStyle: { show: false } },
    options: [{}, {}] });

const GN = [{ name: 'A', x: 0, y: 0 }, { name: 'B', x: 10, y: 5 }, { name: 'C', x: 4, y: 12 }];
const GL = [{ source: 'A', target: 'B' }, { source: 'B', target: 'C' }];
add('component', 'thumbnail-cells', "a thumbnail with its defaults (right 1, bottom 1, 25% x 25%) in a cell, over a graph on the canvas with roam",
  { matrix: MX(),
    thumbnail: { coordinateSystem: 'matrix', coord: [['b', 'c'], ['s', 'u']] },
    series: [{ type: 'graph', layout: 'none', roam: true, data: GN, links: GL }] });

const RADAR_IND = [{ name: 'p', max: 10 }, { name: 'q', max: 10 }, { name: 'r', max: 10 }, { name: 's', max: 10 }];
add('component', 'radar-cells', 'radars: the default centre and radius in a cell, a percentage centre and a mixed radius over a range, one in a calendar day',
  { matrix: MX(), calendar: CAL(),
    radar: [
      { coordinateSystem: 'matrix', coord: ['a', 'p'], indicator: RADAR_IND, axisName: { show: false } },
      { coordinateSystem: 'matrix', coord: [['b', 'c'], ['q', 's']], center: ['40%', '60%'], radius: [10, '70%'], indicator: RADAR_IND, axisName: { show: false } },
      { coordinateSystem: 'calendar', coord: '2017-02-16', radius: '90%', indicator: RADAR_IND, axisName: { show: false } }],
    series: [
      { type: 'radar', radarIndex: 0, data: [{ value: [3, 5, 7, 9] }] },
      { type: 'radar', radarIndex: 1, data: [{ value: [8, 2, 4, 6] }] },
      { type: 'radar', radarIndex: 2, data: [{ value: [1, 2, 3, 4] }] }] },
  { calls: [{ finder: { seriesIndex: 0 }, value: [3, 5, 7, 9] }] });

add('component', 'single-cells', 'single axes: the default box (5% each) in a cell, a written box over a range, one in a calendar day',
  { matrix: MX(), calendar: CAL(),
    singleAxis: [
      { coordinateSystem: 'matrix', coord: ['a', 'r'], type: 'value', min: 0, max: 10 },
      { coordinateSystem: 'matrix', coord: [['b', 'c'], 'r'], type: 'category', data: ['m', 'n', 'o'], top: 10, height: 30, left: '10%', right: 0 },
      { coordinateSystem: 'calendar', coord: '2017-02-22', type: 'value', min: 0, max: 4, orient: 'vertical', left: 30, width: 20 }],
    series: [
      { type: 'scatter', coordinateSystem: 'singleAxis', singleAxisIndex: 0, data: [2, 7] },
      { type: 'scatter', coordinateSystem: 'singleAxis', singleAxisIndex: 1, data: ['n'] },
      { type: 'scatter', coordinateSystem: 'singleAxis', singleAxisIndex: 2, data: [1] }] },
  { calls: [{ finder: { singleAxisIndex: 0 }, value: 7 }, { finder: { singleAxisIndex: 1 }, value: 'o' }, { finder: { singleAxisIndex: 2 }, value: 3 }] });

add('component', 'parallel-cells', 'parallels: a written box over a range of cells, a vertical one in a calendar day',
  { matrix: MX(), calendar: CAL(),
    parallel: [
      { coordinateSystem: 'matrix', coord: [['a', 'c'], ['p', 'q']], left: 20, right: 20, top: 10, bottom: 10 },
      { coordinateSystem: 'calendar', coord: '2017-02-23', layout: 'vertical', left: 5, right: 5, top: 5, bottom: 5 }],
    parallelAxis: [
      { parallelIndex: 0, dim: 0, min: 0, max: 10 }, { parallelIndex: 0, dim: 1, min: 0, max: 10 }, { parallelIndex: 0, dim: 2, min: 0, max: 10 },
      { parallelIndex: 1, dim: 0, min: 0, max: 5 }, { parallelIndex: 1, dim: 1, min: 0, max: 5 }],
    series: [
      { type: 'parallel', parallelIndex: 0, data: [[1, 5, 9]] },
      { type: 'parallel', parallelIndex: 1, data: [[1, 4]] }] });

add('component', 'geo-cells', 'geos: the default box (centred, with the aspect) in a cell, layoutCenter and layoutSize in the cell, a written box over a range, one in a calendar day, and one whose matrix is not there',
  { matrix: MX(), calendar: CAL(),
    geo: [
      { map: 'bx2sq', coordinateSystem: 'matrix', coord: ['a', 'p'] },
      { map: 'bx2sq', coordinateSystem: 'matrix', coord: ['b', 'p'], layoutCenter: ['40%', '50%'], layoutSize: '80%' },
      { map: 'bx2sq', coordinateSystem: 'matrix', coord: [['a', 'c'], ['q', 'r']], left: 10, right: 30, top: 5, bottom: 5, aspectScale: 1 },
      { map: 'bx2sq', coordinateSystem: 'calendar', coord: '2017-02-09', top: 0, bottom: 0 },
      { map: 'bx2sq', coordinateSystem: 'matrix', matrixIndex: 2, coord: ['a', 'p'], left: 0, width: 100 }] },
  { calls: [0, 1, 2, 3, 4].map(g => ({ finder: { geoIndex: g }, value: [2, 1.5] })),
    twin: o => { const g = o.geo[4]; delete g.coordinateSystem; delete g.matrixIndex; delete g.coord; }, twinOf: 'geos', twinIdx: [4] });

add('series', 'pie-cartesian', "pies on a cartesian: by coord with a pixel radius, by center read as a coord with a percentage radius (of the canvas), a ring by coord on the second y axis; each one's coord widens the axes",
  { grid: { left: 60, right: 40, top: 40, bottom: 40 },
    xAxis: { type: 'value' }, yAxis: [{ type: 'value' }, { type: 'value', position: 'right' }],
    series: [
      { type: 'line', data: [[2, 3], [6, 5]] },
      { type: 'pie', coordinateSystem: 'cartesian2d', coord: [10, 20], radius: 30, data: [1, 2] },
      { type: 'pie', coordinateSystem: 'cartesian2d', center: [-4, 8], radius: '10%', data: [3, 1, 2] },
      { type: 'pie', coordinateSystem: 'cartesian2d', yAxisIndex: 1, coord: [5, 100], radius: ['8%', 40], data: [1, 1] }] },
  { calls: [{ finder: { gridIndex: 0 }, value: [10, 20] }, { finder: { xAxisIndex: 0, yAxisIndex: 1 }, value: [5, 100] }] });

add('series', 'pie-category', 'a pie on a category axis: its coord names a category; and one with no coord and its default center (no such category: no centre)',
  { xAxis: { type: 'category', data: ['m', 'n', 'o'] }, yAxis: { type: 'value' },
    series: [
      { type: 'bar', data: [4, 6, 2] },
      { type: 'pie', coordinateSystem: 'cartesian2d', coord: ['n', 9], radius: 25, data: [1, 2] }] },
  { calls: [{ finder: { gridIndex: 0 }, value: ['n', 9] }] });

const CN = [{ name: 'A' }, { name: 'B' }, { name: 'C' }];
const CL = [{ source: 'A', target: 'B', value: 3 }, { source: 'B', target: 'C', value: 2 }, { source: 'C', target: 'A', value: 4 }];
add('series', 'points-geo', "on a geo and a cartesian: a chord with usage 'box' by coord on each, a pie by coord on the geo, a chord with usage 'data' (no point)",
  { geo: { map: 'bx2sq', left: 300, top: 300, width: 400, height: 200, roam: true },
    xAxis: { type: 'value' }, yAxis: { type: 'value' }, grid: { left: 40, top: 40, width: 200, height: 200 },
    series: [
      { type: 'chord', coordinateSystem: 'geo', coordinateSystemUsage: 'box', coord: [2, 1.5], radius: ['10%', '12%'], data: CN, links: CL },
      { type: 'chord', coordinateSystem: 'cartesian2d', coordinateSystemUsage: 'box', coord: [3, 4], radius: [20, 25], data: CN, links: CL },
      { type: 'pie', coordinateSystem: 'geo', coord: [5, 1], radius: 20, data: [1, 2] },
      { type: 'chord', coordinateSystem: 'cartesian2d', coord: [3, 4], radius: ['30%', '32%'], data: CN, links: CL },
      { type: 'scatter', data: [[0, 0], [2, 2]] }] },
  { steps: [{ action: { type: 'geoRoam', geoIndex: 0, zoom: 2, originX: 500, originY: 400 } }] });

add('series', 'map-box', "map series with usage 'box': its own geo in a cell, layoutCenter and layoutSize in a calendar day, and one with usage 'data' on a matrix (its own geo on the canvas)",
  { matrix: MX(), calendar: CAL(),
    series: [
      { type: 'map', map: 'bx2sq', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: ['b', 'q'], data: [{ name: 'A', value: 1 }] },
      { type: 'map', map: 'target_map', coordinateSystem: 'calendar', coordinateSystemUsage: 'box', coord: '2017-02-10', layoutCenter: ['50%', '50%'], layoutSize: '90%', data: [] },
      { type: 'map', map: 'bx2sq', name: 'other', mapValueCalculation: 'sum', coordinateSystem: 'matrix', coord: ['c', 'u'], left: 100, top: 100, width: 300, height: 100, data: [] }] },
  { calls: [{ finder: { seriesIndex: 0 }, value: [2, 1.5] }, { finder: { seriesIndex: 1 }, value: [3, 0.5] }, { finder: { seriesIndex: 2 }, value: [2, 1.5] }] });

const SK_NODES = [{ name: 'A' }, { name: 'B' }, { name: 'C' }];
const SK_LINKS = [{ source: 'A', target: 'B', value: 5 }, { source: 'A', target: 'C', value: 3 }];
add('series', 'data-usage-matrix', "series laid out on the canvas whatever they name, with usage 'data' on a matrix: convertToPixel through a treemap, a chord, a gauge and a sunburst answers the matrix's dataToPoint; a tree's own view takes the matrix's place (nothing), and a sankey with its default box usage has none (a sankey with usage 'data' on a matrix throws in its view's render)",
  { matrix: MX(),
    series: [
      { type: 'tree', coordinateSystem: 'matrix', coordinateSystemUsage: 'data', data: [{ name: 'r', children: [{ name: 'x' }] }] },
      { type: 'treemap', coordinateSystem: 'matrix', coordinateSystemUsage: 'data', data: [{ name: 'x', value: 2 }, { name: 'y', value: 1 }] },
      { type: 'chord', coordinateSystem: 'matrix', data: CN, links: CL },
      { type: 'gauge', coordinateSystem: 'matrix', data: [{ value: 30 }] },
      { type: 'sunburst', coordinateSystem: 'matrix', data: [{ name: 'x', value: 2 }] },
      { type: 'sankey', coordinateSystem: 'matrix', coord: ['c', 'u'], data: SK_NODES, links: SK_LINKS }] },
  { calls: [0, 1, 2, 3, 4, 5].map(s => ({ finder: { seriesIndex: s }, value: ['b', 'r'] })) });

add('interact', 'grid-pointer', 'a grid in a cell: updateAxisPointer at a point in it, findHover on its bars, convertFromPixel and containPixel through it',
  { matrix: MX(),
    grid: [{ coordinateSystem: 'matrix', coord: [['a', 'b'], ['q', 's']], left: 30, right: 10, top: 10, bottom: 20 },
      { coordinateSystem: 'matrix', coord: ['c', 'u'], left: 5, right: 5, top: 5, bottom: 5 }],
    tooltip: { trigger: 'axis' },
    xAxis: [{ gridIndex: 0, type: 'category', data: ['m', 'n', 'o', 'p'] }, { gridIndex: 1, type: 'value', show: false }],
    yAxis: [{ gridIndex: 0, type: 'value' }, { gridIndex: 1, type: 'value', show: false }],
    series: [{ type: 'bar', data: [5, 9, 3, 7] }, { type: 'scatter', xAxisIndex: 1, yAxisIndex: 1, data: [[1, 1], [2, 3]] }] },
  { steps: [{ action: { type: 'updateAxisPointer', currTrigger: 'mousemove', x: 300, y: 250 } },
    { action: { type: 'updateAxisPointer', currTrigger: 'mousemove', x: 600, y: 520 } },
    { action: { type: 'updateAxisPointer', currTrigger: 'mousemove', x: 20, y: 300 } }],
    hovers: [[298, 360], [378, 300], [300, 100], [457, 385]],
    backs: [{ finder: { gridIndex: 0 }, value: [300, 250] }, { finder: { gridIndex: 1 }, value: [650, 530] }],
    contains: [{ finder: { gridIndex: 0 }, value: [300, 250] }, { finder: { gridIndex: 0 }, value: [600, 180] }, { finder: { gridIndex: 1 }, value: [650, 530] }] });

add('interact', 'datazoom-cell-grid', "a dataZoom on a grid in a cell: an inside one and a slider on the canvas whose 'ph' places follow the cell's grid; a window by action",
  { matrix: MX(),
    grid: { coordinateSystem: 'matrix', coord: [['a', 'b'], ['p', 'r']], left: 40, right: 10, top: 10, bottom: 30 },
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    dataZoom: [{ type: 'inside', xAxisIndex: 0 }, { type: 'slider', xAxisIndex: 0, showDetail: false, showDataShadow: false }],
    series: [{ type: 'line', data: [[0, 2], [4, 9], [8, 3], [12, 6], [16, 1]] }] },
  { steps: [{ action: { type: 'dataZoom', dataZoomIndex: 0, start: 20, end: 60 } }],
    calls: [{ finder: { gridIndex: 0 }, value: [8, 3] }],
    backs: [{ finder: { gridIndex: 0 }, value: [200, 150] }] });

add('interact', 'roam-cells', "a graph with usage 'box' and a geo, each in a cell with roam: zoom and pan by action, then a wheel on each, and a wheel outside both",
  { matrix: MX(),
    geo: { map: 'bx2sq', coordinateSystem: 'matrix', coord: [['b', 'c'], ['r', 't']], roam: true },
    series: [{ type: 'graph', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: [['a', 'b'], ['p', 'q']], roam: true, data: GN, links: GL }] },
  { steps: [
    { action: { type: 'graphRoam', seriesIndex: 0, zoom: 2, originX: 150, originY: 100 } },
    { action: { type: 'graphRoam', seriesIndex: 0, dx: 12, dy: -7 } },
    { action: { type: 'geoRoam', geoIndex: 0, zoom: 1.5, originX: 500, originY: 300 } },
    { action: { type: 'geoRoam', geoIndex: 0, dx: -20, dy: 10 } },
    { wheel: [600, 160, 120] },
    { wheel: [520, 320, -120] },
    { wheel: [100, 500, 120] }],
    calls: [{ finder: { geoIndex: 0 }, value: [2, 1.5] }] });

const gal = (name, note, extra) => CASES.push(Object.assign({ group: 'gallery', id: 'gallery-' + name, note, gallery: name }, extra || {}));
gal('matrix-mini-bar-geo', 'the gallery: twenty grids and ten geos in cells (the map a square per canton)',
  { calls: [{ finder: { geoIndex: 0 }, value: [0.5, 0.5] }, { finder: { geoIndex: 9 }, value: [9.5, 0.5] },
    { finder: { gridIndex: 0 }, value: [100, 2] }, { finder: { gridIndex: 39 }, value: [100, 2] }] });

// [D9-D14 mutation round] cases added after the batch
add('series', 'map-data-default', "a map series naming a matrix cell with no usage written, the first (and only) of its map: a series' default usage is 'data', so its own geo is laid out on the canvas by its box",
  { matrix: MX(),
    series: [{ type: 'map', map: 'target_map', coordinateSystem: 'matrix', coord: ['b', 'q'], left: 100, top: 100, width: 300, height: 100, data: [] }] },
  { calls: [{ finder: { seriesIndex: 0 }, value: [3, 0.5] }] });

add('component', 'geo-no-column', "geos whose coord names a row and no column (dataToLayout: no x, no width; a y and a height) and a day off the calendar's range (no x, no y; a width and a height): resizeGeo still lays each out -- getLayoutRect's `|| 0`, the aspect from the height -- and a map series with usage 'box' the same way",
  { matrix: MX(), calendar: CAL(),
    geo: [
      { map: 'bx2sq', coordinateSystem: 'matrix', coord: ['zz', 'p'] },
      { map: 'bx2sq', coordinateSystem: 'matrix', coord: ['zz', 'q'], left: 10, width: 50 },
      { map: 'bx2sq', coordinateSystem: 'matrix', coord: ['zz', 'r'], left: 5, top: 10, height: 30 },
      { map: 'bx2sq', coordinateSystem: 'calendar', coord: '2019-01-01' }],
    series: [{ type: 'map', map: 'target_map', coordinateSystem: 'matrix', coordinateSystemUsage: 'box', coord: ['zz', 's'], data: [] }] },
  { calls: [0, 1, 2, 3].map(g => ({ finder: { geoIndex: g }, value: [2, 1.5] })).concat([{ finder: { seriesIndex: 0 }, value: [3, 0.5] }]) });

function load(c) {
  if (!c.gallery) return clone(c.option);
  return JSON.parse(fs.readFileSync(path.join(GALLERY, c.gallery + '.json'), 'utf8'));
}

function runOne(c, option) {
  const chart = mk();
  try {
    option.animation = false;
    quiet(() => chart.setOption(option));
    settle(chart);
    const w = watchTooltip(chart);
    const states = [recordState(chart, c, true, w)];
    (c.steps || []).forEach(st => {
      if (st.action) quiet(() => chart.dispatchAction(clone(st.action)));
      else if (st.wheel) quiet(() => fire(chart, 'mousewheel', { zrX: st.wheel[0], zrY: st.wheel[1], zrDelta: st.wheel[2] / 120 }));
      settle(chart);
      states.push(recordState(chart, c, false, w));
    });
    return states;
  } finally {
    chart.dispose();
  }
}

// R1 / R2 / R3
function recipes(c, states, option) {
  const fails = [];
  const chart = mk();
  try {
    option.animation = false;
    quiet(() => chart.setOption(option));
    settle(chart);
    const ec = chart.getModel();
    const st = states[0];
    const r1 = (what, model, got) => {
      if (!model.boxCoordinateSystem || !model.boxCoordinateSystem.dataToLayout) {
        if (got !== null) fails.push(what + ': a ref without a box coordinate system');
        return null;
      }
      const ref = refOf(model);
      if (JSON.stringify(rectRec(ref)) !== JSON.stringify(got)) fails.push(what + ": the ref is not the host's dataToLayout");
      return ref;
    };
    const comps = { visualMap: 'visualMaps', toolbox: 'toolboxes', timeline: 'timelines', thumbnail: 'thumbnails',
      radar: 'radars', singleAxis: 'singles', parallel: 'parallels', geo: 'geos' };
    Object.keys(comps).forEach(main => ec.eachComponent(main, m => {
      const r = st[comps[main]].find(q => q.index === m.componentIndex);
      const ref = r1(main + ' ' + m.componentIndex, m, r.ref);
      if (ref && (main === 'singleAxis' || main === 'parallel')) {
        const lr = echarts.helper.getLayoutRect(m.getBoxLayoutParams(), ref);
        if (!sameRect(lr, m.coordinateSystem.getRect())) fails.push(main + ' ' + m.componentIndex + ': not getLayoutRect in the ref');
      }
    }));
    ec.eachComponent('dataZoom', d => {
      if (d.subType !== 'slider') return;
      r1('slider ' + d.componentIndex, d, st.sliders.find(q => q.index === d.componentIndex).ref);
    });
  } finally {
    chart.dispose();
  }
  if (c.twin) {
    const o2 = load(c);
    c.twin(o2);
    const tw = runOne(Object.assign({}, c, { steps: [] }), o2)[0];
    c.twinIdx.forEach(k => {
      const a = states[0][c.twinOf].find(q => q.index === k);
      const b = tw[c.twinOf].find(q => q.index === k);
      const strip = q => JSON.stringify(Object.assign({}, q, { boxed: null, ref: null }));
      if (a.boxed || strip(a) !== strip(b)) fails.push(c.twinOf + ' ' + k + ': not laid out as with no coordinateSystem');
    });
  }
  return fails;
}

function runCase(c) {
  const option = load(c);
  const states = runOne(c, clone(option));
  return { id: c.id, group: c.group, note: c.note, gallery: c.gallery || null,
    option: c.gallery ? null : clone(c.option), steps: clone(c.steps || []),
    fails: recipes(c, states, clone(option)), states };
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
  const s0 = id => by(id).states[0];
  const n = h => num(h);
  const inRef = (x, y, r) => x >= n(r.x) && x <= n(r.x) + n(r.width) && y >= n(r.y) && y <= n(r.y) + n(r.height);
  out.cases.forEach(q => guard(q.id + ': the recipes hold (R1-R3)', () => q.fails.length === 0));
  guard('a visualMap with its defaults sits at its cell\'s bottom left', () => {
    const v = s0('visualmap-cells').visualMaps[0];
    return v.boxed && inRef(n(v.group[0]), n(v.group[1]), v.ref);
  });
  guard('a visualMap whose matrix is not there is on the canvas', () => !s0('visualmap-cells').visualMaps[3].boxed);
  guard('a slider with written edges is in its cells', () => {
    const s = s0('slider-cells').sliders[1];
    return Object.is(n(s.location[0]), n(s.ref.x) + 5) && Object.is(n(s.location[1]), n(s.ref.y) + 5);
  });
  guard('a slider\'s ph right is its cell\'s width less the grid\'s right edge (the two frames mixed): it starts at the cell\'s x plus the grid\'s', () => {
    const s = s0('slider-cells').sliders[0];
    return s.boxed && Object.is(n(s.location[0]), n(s.ref.x) + 60) && Object.is(n(s.size[0]), 680);
  });
  guard('a toolbox with its defaults is at its cell\'s top right', () => {
    const t = s0('toolbox-cells').toolboxes[0];
    return inRef(n(t.group[0]), n(t.group[1]), t.ref) && n(t.group[0]) > n(t.ref.x) + n(t.ref.width) / 2;
  });
  guard('the timeline is in its cells', () => {
    const t = s0('timeline-matrix').timelines[0];
    return t.boxed && inRef(n(t.main[0]), n(t.main[1]), t.ref);
  });
  guard('a thumbnail fills a quarter of its cells at their bottom right', () => {
    const t = s0('thumbnail-cells').thumbnails[0];
    return t.boxed && Object.is(n(t.box.width), n(t.ref.width) * 0.25);
  });
  guard('a radar\'s default centre is its cell\'s centre', () => {
    const r = s0('radar-cells').radars[0];
    return Object.is(n(r.cx), n(r.ref.width) * 0.5 + n(r.ref.x));
  });
  guard('a single axis\' default box is 5% in from its cell', () => {
    const s = s0('single-cells').singles[0];
    return Object.is(n(s.rect.x), n(s.ref.x) + n(s.ref.width) * 0.05);
  });
  guard('a parallel lays its axes out in its cells', () => {
    const p = s0('parallel-cells').parallels[0];
    return p.axes.every(a => n(a.position[0]) >= n(p.ref.x));
  });
  guard('a geo in a cell is in it', () => {
    const q = s0('geo-cells').geos[0];
    return q.boxed && n(q.view.x) >= n(q.ref.x) && n(q.view.x) + n(q.view.width) <= n(q.ref.x) + n(q.ref.width) + 1e-9;
  });
  guard('a geo whose matrix is not there is on the canvas', () => !s0('geo-cells').geos[4].boxed);
  guard('a pie by coord on a cartesian sits on the point', () => {
    const c = s0('pie-cartesian');
    const p = c.calls[0].ret;
    const s = c.series[1].sectors[0];
    return Object.is(n(s.cx), n(p[0])) && Object.is(n(s.cy), n(p[1]));
  });
  guard('the pies\' coords widen the axes (the line alone spans 2..6 by 3..5)', () => {
    const x = s0('pie-cartesian').extents.find(e => e.dim === 'xAxis');
    return n(x.extent[0]) <= -4 && n(x.extent[1]) >= 10;
  });
  guard('a pie\'s percentage radius is of the canvas', () => Object.is(n(s0('pie-cartesian').series[2].sectors[0].r), 30));
  guard('a pie by a category coord sits on its band', () => {
    const c = s0('pie-category');
    return Object.is(n(c.series[1].sectors[0].cx), n(c.calls[0].ret[0]));
  });
  guard('a chord with usage box on a geo follows the roam; one with usage data stays on the canvas', () => {
    const c = by('points-geo');
    return !Object.is(c.states[0].series[0].sectors[0].cx, c.states[1].series[0].sectors[0].cx)
      && Object.is(n(c.states[0].series[3].sectors[0].cx), 400);
  });
  guard('a map with usage box lays its geo in its cell', () => {
    const c = s0('map-box');
    return c.series[0].boxed && n(c.series[0].view.x) > n(c.matrices[0].rect.x) && n(c.series[0].view.width) < 200;
  });
  guard('usage data on a matrix answers convertToPixel through the matrix', () =>
    s0('data-usage-matrix').calls.slice(1, 5).every(q => q.ret && q.ret[0] === s0('data-usage-matrix').calls[1].ret[0]));
  guard('a tree on its own view and a sankey with its default box usage answer nothing', () =>
    s0('data-usage-matrix').calls[0].ret === null && s0('data-usage-matrix').calls[5].ret === null);
  guard('the pointer in the cell\'s grid shows its x axis', () => by('grid-pointer').states[1].axes.some(a => a.dim === 'x' && a.status === 'show'));
  guard('the pointer outside every grid hides them', () => by('grid-pointer').states[3].axes.every(a => a.status !== 'show'));
  guard('findHover finds a bar in the cell', () => s0('grid-pointer').hovers.some(h => h.hit && h.hit.seriesIndex === 0));
  guard('containPixel is in the cell\'s grid only', () => {
    const c = s0('grid-pointer').contains;
    return c[0].ret && !c[1].ret && c[2].ret;
  });
  guard('the graph in its cell zooms and pans', () => {
    const c = by('roam-cells');
    return c.states[0].series[0].nodes[1].x !== c.states[1].series[0].nodes[1].x
      && c.states[1].series[0].nodes[1].x !== c.states[2].series[0].nodes[1].x;
  });
  guard('the geo in its cell zooms', () => {
    const c = by('roam-cells');
    return c.states[2].geos[0].roam[0] !== c.states[3].geos[0].roam[0];
  });
  guard('a wheel on the graph zooms it, outside both changes nothing', () => {
    const c = by('roam-cells');
    return JSON.stringify(c.states[5].series) !== JSON.stringify(c.states[4].series)
      && JSON.stringify(c.states[7].series) === JSON.stringify(c.states[6].series)
      && JSON.stringify(c.states[7].geos) === JSON.stringify(c.states[6].geos);
  });
  guard('a wheel on the geo zooms it', () => {
    const c = by('roam-cells');
    return JSON.stringify(c.states[6].geos) !== JSON.stringify(c.states[5].geos);
  });
  guard('a dataZoom window on a grid in a cell moves its pixels', () => {
    const c = by('datazoom-cell-grid');
    return c.states[0].calls[0].ret[0] !== c.states[1].calls[0].ret[0] && c.states[0].sliders[0].boxed === false;
  });
  guard('the axis tooltip of a grid in a cell shows at the pointer', () => {
    const t = by('grid-pointer').states[1].tip;
    return t.visible && t.which.indexOf('axis:') === 0 && Object.is(num(t.anchor[0]), 300);
  });
  guard('the gallery\'s twenty grids and ten geos are in its cells', () => {
    const c = s0('gallery-matrix-mini-bar-geo');
    return c.grids.length === 20 && c.grids.every(r => r.boxed) && c.geos.length === 10 && c.geos.every(r => r.boxed);
  });
  // [D9-D14 mutation round]
  guard('a map naming a cell with no usage is on the canvas, by its own box', () => {
    const s = s0('map-data-default').series[0];
    return !s.boxed && Object.is(n(s.view.x), 100);
  });
  guard('a geo in a coord of no column is laid out from x nought with finite numbers', () => {
    const c = s0('geo-no-column');
    return c.geos.length === 4 && c.geos.every(r => r.boxed && Number.isNaN(n(r.ref.x)) && Number.isFinite(n(r.view.x))
      && Number.isFinite(n(r.view.width))) && c.calls.every(q => q.ret && Number.isFinite(n(q.ret[0])))
      && Object.is(n(c.geos[1].view.x), 10);
  });
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    maps: MAPS.map(m => ({ name: m.name, text: m.text })),
    notes: [
      'every chart: ' + W + ' x ' + H + ', SVG ssr (chart._ssr false, env.node false, getDom stubbed), animation false; the gallery options fed verbatim.',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'a wheel is zrender\'s mousewheel with wheelDelta = delta / 120.',
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
if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, json1);
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
