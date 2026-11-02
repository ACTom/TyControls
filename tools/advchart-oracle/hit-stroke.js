// Round 7 R7-C: what zrender's hit test finds at the points around a stroked
// element -- Path.contain (the stroked bounding rect first, then the stroke
// within half the line width of the outline, at least strokeContainThreshold
// (5) where the path has no fill, then the fill), Displayable.rectContain for
// a text's spans -- per shape kind the port draws: rects (bars, rounded,
// fill-less, horizontal, heatmap cells, a treemap's), sectors (a pie's, a
// rounded one's, a sunburst's), sausages (a round-capped polar bar, a gauge's
// progress), polylines and polygons (a line, its area, a radar, a funnel, a
// theme river, a parallel line), K-line and boxplot paths, symbols (circle,
// rect, roundRect, triangle, diamond, pin, arrow, empty, path://, effect
// scatter, pictorial bar), beziers (graph edges, lines, sankey links, chord
// ribbons, tree edges) and labels (a plate with a border, a border alone, a
// text stroke), and the large paths (LargeSymbolPath, LargeLineDraw's
// LargeLinesPath, a large bar).
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false,
// animation off): each case set, then for each aim -- an element (an item's
// graphic element, a series view's polyline or polygon, a graph edge, an
// item's label), a polyline's first point (two rays, along the line and
// back) or a point -- rays from the aim's centre (its global bounding
// rect's, rounded; a point's own; then 0.3 right and 0.2 down, off the pixel
// grid) in eight directions, one pixel a step (a
// diagonal step one pixel on each axis), out to the aim's reach (the rect's
// half diagonal and four, or the point's own) or the canvas' edge. At each
// point zr's handler.findHover(x, y).target, written as
//   sS/D   the ECData found walking __hostTarget / parent from the target
//          (echarts' event dispatcher walk): series S, data index D
//   sS/eD  the same with dataType 'edge'
//   sS/-   a series' ECData with no data index (a line's polyline)
//   x      a target with no series ECData
//   -      none
// run-length encoded: `code*count code*count ...`.
// Run: node tools/advchart-oracle/hit-stroke.js -> tests/fixtures/advchart-hit-stroke.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-hit-stroke.json');
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
const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const W = 400;
const H = 300;

const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666'];
const N = ['A', 'B', 'C'];
const B = (w, more) => Object.assign({ borderColor: '#000', borderWidth: w }, more || {});
const cart = (s, more) => Object.assign({ animation: false, color: PAL, xAxis: { type: 'category', data: N },
  yAxis: { type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const vv = (s, more) => Object.assign({ animation: false, color: PAL, xAxis: { type: 'value', min: 0, max: 10 },
  yAxis: { type: 'value', min: 0, max: 10 }, series: Array.isArray(s) ? s : [s] }, more || {});
const solo = (s, more) => Object.assign({ animation: false, color: PAL, series: Array.isArray(s) ? s : [s] }, more || {});
const bar = (is, more) => cart(Object.assign({ type: 'bar', data: [4, 6, 8], barWidth: 60, itemStyle: is }, more || {}));
const sc = (sym, size, is, more) => vv(Object.assign({ type: 'scatter', symbol: sym, symbolSize: size,
  data: [[2, 2], [5, 5], [8, 8]], itemStyle: is }, more || {}));
const IT = (s, d) => ({ s, d });
const LBL = (s, d) => ({ s, d, label: true });
const POLY = s => ({ s, poly: 'polyline' });
const AREA = s => ({ s, poly: 'polygon' });
const EDGE = (s, e) => ({ s, edge: e });
const PT = (x, y, r) => ({ at: [x, y], r });
const START = (s, r) => ({ s, poly: 'polyline', start: true, r, dirs: [0, 4] });
const GRAPH_NODES = [{ name: 'a', x: 100, y: 150 }, { name: 'b', x: 300, y: 150 }, { name: 'c', x: 200, y: 60 }];
// a straight edge off the horizontal: upstream's ECLinePath snaps a level or an
// upright one to the half pixel (subPixelOptimize), which the port does not do
const GRAPH_NODES_TILT = [{ name: 'a', x: 100, y: 150 }, { name: 'b', x: 300, y: 160 }, { name: 'c', x: 200, y: 60 }];
const GRAPH_LINKS = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }];
const TREE = { name: 'r', children: [{ name: 'a' }, { name: 'b' }] };

// [id, option, aims, tol]: tol, where given, the steps a run's ends may lie
// off upstream's in the port -- a curve it holds as points (a graph's or a
// lines' curved edge sampled into a polyline, the pin symbol's outline)
function cases() {
  return [
    // ---- rects ----
    ['bar.b20', bar(B(20)), [IT(0, 1)]],
    ['bar.b1000', bar({}, { barWidth: 20, data: [4, { value: 6, itemStyle: B(1000) }, 8] }), [IT(0, 1)]],
    ['bar.b4', bar(B(4)), [IT(0, 1)]],
    ['bar.round', bar(B(12, { borderRadius: 16 })), [IT(0, 1)]],
    ['bar.round-top', bar(B(12, { borderRadius: [20, 20, 0, 0] })), [IT(0, 1)]],
    ['bar.clear', bar(B(2, { color: 'transparent' })), [IT(0, 1)]],
    ['bar.clear-w8', bar(B(8, { color: 'rgba(0,0,0,0)' })), [IT(0, 1)]],
    ['bar.transparent-border', bar({ borderColor: 'transparent', borderWidth: 12 }), [IT(0, 1)]],
    ['bar.border-no-colour', bar({ borderWidth: 12 }), [IT(0, 1)]],
    ['bar.horizontal', Object.assign(bar(B(12)), { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'category', data: N } }),
      [IT(0, 1)]],
    ['bar.stack', cart([{ type: 'bar', stack: 's', data: [2, 3, 4], barWidth: 60, itemStyle: B(10) },
      { type: 'bar', stack: 's', data: [3, 3, 3], barWidth: 60, itemStyle: B(10, { borderColor: '#f00' }) }]), [IT(0, 1), IT(1, 1)]],
    ['heatmap.b10', Object.assign(cart({ type: 'heatmap', data: [[0, 0, 1], [1, 1, 2], [2, 0, 3]], itemStyle: B(10) }),
      { yAxis: { type: 'category', data: ['p', 'q'] }, visualMap: { show: false, min: 0, max: 3 } }), [IT(0, 1)]],
    ['treemap.b10', solo({ type: 'treemap', breadcrumb: { show: false }, nodeClick: false, roam: false,
      data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }], itemStyle: B(10, { gapWidth: 0 }) }), [IT(0, 1), IT(0, 2)]],
    // ---- sectors ----
    ['pie.b16', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3], itemStyle: B(16) }),
      [IT(0, 0), IT(0, 2)]],
    ['pie.default', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3] }), [IT(0, 0)]],
    ['pie.whole', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1], itemStyle: B(16) }),
      [IT(0, 0)]],
    ['pie.round', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: B(10, { borderRadius: 12 }) }), [IT(0, 0)]],
    ['pie.clear', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: B(2, { color: 'transparent' }) }), [IT(0, 1)]],
    ['sunburst.b10', solo({ type: 'sunburst', radius: [20, 120], label: { show: false },
      data: [{ name: 'a', value: 3, children: [{ name: 'a1', value: 3 }] }, { name: 'b', value: 2 }], itemStyle: B(10) }),
      [PT(200, 150, 140)]],
    ['polarbar.round', { animation: false, color: PAL, polar: { radius: [30, 120] }, angleAxis: { max: 10, axisTick: { show: false } },
      radiusAxis: { type: 'category', data: N },
      series: [{ type: 'bar', coordinateSystem: 'polar', roundCap: true, data: [4, 6, 8], itemStyle: B(10) }] }, [IT(0, 2)]],
    ['gauge.progress', solo({ type: 'gauge', data: [{ value: 40 }], axisLine: { show: false }, splitLine: { show: false },
      axisTick: { show: false }, axisLabel: { show: false }, pointer: { show: false }, anchor: { show: false },
      title: { show: false }, detail: { show: false },
      progress: { show: true, roundCap: true, width: 14, itemStyle: B(10) } }), [PT(200, 150, 150)]],
    ['gauge.pointer', solo({ type: 'gauge', data: [{ value: 40 }], axisLine: { show: false }, splitLine: { show: false },
      axisTick: { show: false }, axisLabel: { show: false }, anchor: { show: false }, title: { show: false },
      detail: { show: false }, itemStyle: B(10) }), [IT(0, 0)]],
    // ---- polylines and polygons ----
    ['line.w12', cart({ type: 'line', symbol: 'none', data: [5, 5, 7], lineStyle: { width: 12 } }), [POLY(0), START(0, 20)]],
    ['line.w1', cart({ type: 'line', symbol: 'none', data: [5, 5, 7], lineStyle: { width: 1 } }), [POLY(0)]],
    ['line.w0', cart({ type: 'line', data: [5, 5, 7], symbolSize: 16, lineStyle: { width: 0 }, itemStyle: B(12) }),
      [POLY(0), IT(0, 1)]],
    ['line.smooth', cart({ type: 'line', symbol: 'none', smooth: true, data: [2, 8, 3], lineStyle: { width: 8 } }),
      [POLY(0)]],
    ['line.area', cart({ type: 'line', symbol: 'none', data: [5, 5, 7], areaStyle: {}, lineStyle: { width: 2 } }),
      [AREA(0), PT(200, 110, 40)]],
    ['line.step', cart({ type: 'line', symbol: 'none', step: 'middle', data: [3, 6, 4], lineStyle: { width: 10 } }),
      [POLY(0)]],
    ['radar.w12', { animation: false, color: PAL, radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 },
      { name: 'r', max: 10 }], radius: 110 }, series: [{ type: 'radar', symbol: 'none', lineStyle: { width: 12 },
      data: [{ value: [8, 6, 7] }] }] }, [IT(0, 0)]],
    ['radar.area', { animation: false, color: PAL, radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 },
      { name: 'r', max: 10 }], radius: 110 }, series: [{ type: 'radar', symbolSize: 14, itemStyle: B(8),
      lineStyle: { width: 4 }, areaStyle: {}, data: [{ value: [8, 6, 7] }] }] }, [IT(0, 0)]],
    ['funnel.b12', solo({ type: 'funnel', label: { show: false }, data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 },
      { name: 'c', value: 1 }], itemStyle: B(12) }), [IT(0, 1)]],
    ['themeriver.b10', solo({ type: 'themeRiver', label: { show: false }, data: [[0, 3, 'a'], [1, 4, 'a'], [2, 3, 'a'],
      [0, 2, 'b'], [1, 2, 'b'], [2, 3, 'b']], itemStyle: B(10) },
    { singleAxis: { type: 'value', min: 0, max: 2, top: 40, bottom: 40, axisLabel: { show: false } } }), [PT(200, 150, 150)]],
    ['parallel.w12', { animation: false, color: PAL, parallelAxis: [{ dim: 0, min: 0, max: 10 }, { dim: 1, min: 0, max: 10 },
      { dim: 2, min: 0, max: 10 }], series: [{ type: 'parallel', lineStyle: { width: 12, opacity: 1 },
      data: [[5, 5, 2], [2, 8, 8]] }] }, [IT(0, 0)]],
    ['candle.b8', cart({ type: 'candlestick', barWidth: 30, data: [[3, 7, 1, 9], [6, 4, 2, 8], [4, 6, 3, 7]],
      itemStyle: { borderWidth: 8 } }), [IT(0, 0), IT(0, 1)]],
    ['boxplot.b8', cart({ type: 'boxplot', boxWidth: [30, 30], data: [[1, 3, 5, 7, 9], [2, 4, 5, 6, 8], [1, 2, 3, 4, 5]],
      itemStyle: { borderWidth: 8 } }), [IT(0, 1)]],
    // ---- symbols ----
    ['scatter.circle', sc('circle', 20, B(20)), [IT(0, 1)]],
    ['scatter.circle-b2', sc('circle', 20, B(2)), [IT(0, 1)]],
    ['scatter.rect', sc('rect', 30, B(12)), [IT(0, 1)]],
    ['scatter.roundrect', sc('roundRect', 30, B(12)), [IT(0, 1)]],
    ['scatter.triangle', sc('triangle', 30, B(12)), [IT(0, 1)]],
    ['scatter.diamond', sc('diamond', 30, B(12)), [IT(0, 1)]],
    ['scatter.pin', sc('pin', 30, B(12)), [IT(0, 1)], 2],
    ['scatter.arrow', sc('arrow', 30, B(12)), [IT(0, 1)]],
    ['scatter.empty', sc('emptyCircle', 20, {}), [IT(0, 1)]],
    ['scatter.empty-b10', sc('emptyRect', 20, B(10)), [IT(0, 1)]],
    ['scatter.path', sc('path://M0 0L10 0L5 10Z', 30, B(12)), [IT(0, 1)]],
    // a pen of infinite width: its stroked rect is not-a-number, the symbol never hit
    ['scatter.infinite', sc('circle', 20, B('Infinity')), [PT(210, 143, 40)]],
    ['scatter.clear', sc('circle', 20, B(2, { color: 'transparent' })), [IT(0, 1)]],
    ['scatter.path-turned', sc('path://M0 0L10 0L5 10Z', 30, B(12), { symbolRotate: 30 }), [IT(0, 1)]],
    ['effect.b12', vv({ type: 'effectScatter', symbolSize: 20, rippleEffect: { number: 0 }, showEffectOn: 'emphasis',
      data: [[2, 2], [5, 5], [8, 8]], itemStyle: B(12) }), [IT(0, 1)]],
    ['pictorial.b10', cart({ type: 'pictorialBar', symbol: 'rect', symbolSize: [40, 30], symbolRepeat: false,
      symbolPosition: 'center', data: [4, 6, 8], itemStyle: B(10) }), [IT(0, 1)]],
    // ---- beziers ----
    ['graph.edges', solo({ type: 'graph', layout: 'none', symbolSize: 20, itemStyle: B(10), data: GRAPH_NODES,
      links: GRAPH_LINKS, lineStyle: { width: 12, curveness: 0.3, opacity: 1 } }), [EDGE(0, 0), IT(0, 2)], 1],
    ['graph.straight-w1', solo({ type: 'graph', layout: 'none', symbolSize: 20, data: GRAPH_NODES_TILT, links: GRAPH_LINKS,
      lineStyle: { width: 1, opacity: 1 } }), [EDGE(0, 0)]],
    ['lines.w12', vv({ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { width: 12, curveness: 0.3, opacity: 1 },
      data: [{ coords: [[1, 2], [9, 8]] }] }), [IT(0, 0)], 1],
    ['lines.straight', vv({ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { width: 2, opacity: 1 },
      data: [{ coords: [[1, 5], [9, 6]] }] }), [IT(0, 0)]],
    ['sankey.b12', solo({ type: 'sankey', label: { show: false }, data: [{ name: 'a' }, { name: 'b' }],
      links: [{ source: 'a', target: 'b', value: 3 }], itemStyle: B(12),
      lineStyle: { borderWidth: 12, borderColor: '#000', opacity: 1 } }), [EDGE(0, 0), IT(0, 0)]],
    ['chord.w12', solo({ type: 'chord', label: { show: false }, data: [{ name: 'a' }, { name: 'b' }],
      links: [{ source: 'a', target: 'b', value: 3 }], itemStyle: B(8),
      lineStyle: { color: '#000', width: 12, opacity: 1 } }), [EDGE(0, 0), IT(0, 0)]],
    ['tree.w12', solo({ type: 'tree', data: [TREE], symbolSize: 16, label: { show: false }, expandAndCollapse: false,
      itemStyle: B(8), lineStyle: { width: 12 } }), [PT(200, 150, 200)]],
    // ---- labels ----
    ['label.plate', bar({}, { label: { show: true, position: 'top', backgroundColor: '#eee', padding: 4, borderWidth: 12,
      borderColor: '#000' } }), [LBL(0, 1)]],
    ['label.border-only', bar({}, { label: { show: true, position: 'top', padding: 4, borderWidth: 12, borderColor: '#000' } }),
      [LBL(0, 1)]],
    ['label.text-stroke', bar({}, { label: { show: true, position: 'top', fontSize: 20, textBorderWidth: 10,
      textBorderColor: '#fff' } }), [LBL(0, 1)]],
    ['label.inside', bar({}, { label: { show: true, position: 'inside', fontSize: 20 } }), [LBL(0, 1)]],
    ['label.plate-text-stroke', bar({}, { label: { show: true, position: 'top', fontSize: 20, backgroundColor: '#eee',
      padding: 1, textBorderWidth: 10, textBorderColor: '#fff' } }), [LBL(0, 1)]],
    // ---- flags ----
    ['bar.silent', bar(B(20), { silent: true }), [IT(0, 1)]],
    // ---- large paths ----
    ['scatter.large', sc('circle', 10, B(10), { large: true, largeThreshold: 1 }), [PT(200, 150, 30)]],
    ['lines.large', vv({ type: 'lines', coordinateSystem: 'cartesian2d', large: true, largeThreshold: 1,
      lineStyle: { width: 12, opacity: 1 }, data: [{ coords: [[1, 5], [9, 5]] }, { coords: [[1, 2], [9, 8]] }] }),
      [PT(200, 150, 40)]],
    ['bar.large', bar(B(10), { large: true, largeThreshold: 1 }), [PT(200, 150, 60)]],
  ];
}

// ECData lives in a makeInner store keyed per element: the key is found once
let ecKey = null;
function ecDataOf(el) {
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (v && typeof v === 'object' && !Array.isArray(v) && hasOwn(v, 'seriesIndex') && hasOwn(v, 'dataIndex')) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
function codeOf(t) {
  if (!t) return '-';
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const d = ecDataOf(e);
    if (d && d.dataIndex != null) return 's' + d.seriesIndex + '/' + (d.dataType === 'edge' ? 'e' : '') + d.dataIndex;
    if (d && d.seriesIndex != null) return 's' + d.seriesIndex + '/-';
    if (d && d.eventData) return 'x';
  }
  return 'x';
}
function globalRect(el) {
  el.updateTransform && el.updateTransform();
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform ? el.getComputedTransform() : el.transform;
  if (m) r.applyTransform(m);
  return r;
}
function aimEl(chart, a) {
  const model = chart.getModel().getSeriesByIndex(a.s);
  must(model, 'no series ' + a.s);
  if (a.poly) {
    const v = chart._chartsMap[model.__viewId];
    const e = a.poly === 'polyline' ? v._polyline : v._polygon;
    must(e, 'no ' + a.poly);
    return e;
  }
  if (a.edge != null) {
    const e = model.getEdgeData().getItemGraphicEl(a.edge);
    must(e, 'no edge ' + a.edge);
    return e;
  }
  const e = model.getData().getItemGraphicEl(a.d);
  must(e, 'no item ' + a.s + '/' + a.d);
  if (a.label) {
    const t = e.getTextContent();
    must(t, 'no label ' + a.s + '/' + a.d);
    return t;
  }
  return e;
}
// the rays run off the pixel grid: a shape whose edge falls on a whole pixel
// is tested in its own frame upstream (a symbol: the point taken back
// through the scale), where 21 / 15 against -1.4 + 2.8 is a rounding apart
// -- a tie this fixture is not about
const OFF = [0.3, 0.2];
const DIRS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]];
function run(id, option, aims, tol) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    chart.getZr().storage.getDisplayList(true);
    const handler = chart.getZr().handler;
    const rays = [];
    aims.forEach(a => {
      let o, reach;
      if (a.at) {
        o = [a.at[0] + OFF[0], a.at[1] + OFF[1]];
        reach = a.r;
      }
      else if (a.start) {
        // a polyline's first point, rounded (a ray along its first segment
        // runs past its end: the stroked rect cuts containStroke's reach)
        const p0 = aimEl(chart, a).shape.points;  // flat: x0, y0, x1, ...
        o = [Math.round(p0[0]) + OFF[0], Math.round(p0[1]) + OFF[1]];
        must(isFinite(o[0]) && isFinite(o[1]), id + ': no first point');
        reach = a.r;
      }
      else {
        const r = globalRect(aimEl(chart, a));
        must(isFinite(r.x) && isFinite(r.width), id + ': the aim has no rect');
        o = [Math.round(r.x + r.width / 2) + OFF[0], Math.round(r.y + r.height / 2) + OFF[1]];
        reach = Math.ceil(Math.sqrt(r.width * r.width + r.height * r.height) / 2) + 4;
      }
      DIRS.forEach((d, di) => {
        if (a.dirs && a.dirs.indexOf(di) < 0) return;
        let seq = [];
        let n = 0;
        for (let k = 0; k <= reach; k++) {
          const x = o[0] + d[0] * k, y = o[1] + d[1] * k;
          if (x < 0 || y < 0 || x >= W || y >= H) break;
          const c = codeOf(handler.findHover(x, y).target);
          if (seq.length && seq[seq.length - 1][0] === c) seq[seq.length - 1][1]++;
          else seq.push([c, 1]);
          n++;
        }
        rays.push({ o, d, n, seq: seq.map(p => p[0] + '*' + p[1]).join(' ') });
      });
    });
    const rec = { id, option, rays };
    if (tol) rec.tol = tol;
    return rec;
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(([id, o, aims, tol]) => run(id, o, aims, tol));
  const by = id => charts.find(c => c.id === id);
  // every case hits its aim somewhere, but the silent one and the infinite pen
  charts.forEach(c => {
    const any = c.rays.some(r => r.seq.split(' ').some(p => p[0] === 's'));
    must(any === !['bar.silent', 'scatter.infinite'].includes(c.id), c.id + ': hits ' + any);
  });
  // a bar whose 1000 px border took all of its width is hit over most of the grid
  must(by('bar.b1000').rays[4].seq === 's0/1*' + by('bar.b1000').rays[4].n, 'bar.b1000: ' + by('bar.b1000').rays[4].seq);
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-C: per case, rays from each aim\'s centre (the global bounding rect of an item\'s graphic element, a series view\'s '
      + 'polyline / polygon, a graph edge or an item\'s label, rounded; or a point) in eight directions, a pixel a step, out to '
      + 'the half diagonal and 4 (or the point\'s reach) or the canvas\' edge: `seq` what findHover(x, y).target is at each step, '
      + 'run-length encoded -- sS/D the series and data index of the ECData the dispatcher walk finds (sS/eD an edge), sS/- a '
      + 'series\' ECData without a data index, x a target without one, - none. `tol`: the steps a run\'s ends may lie off '
      + 'these where the port holds a curve as points.', W, H, charts };
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
