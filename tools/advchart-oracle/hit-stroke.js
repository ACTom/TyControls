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
// R7-F adds: a fill written 'none' against a clear one, a clear pen, opacity
// 0 (none.*, clear.*, opacity0.*); curves as curves (curve.*: no step of
// tolerance is left for a graph's or a lines' curved edge or the pin);
// turned labels and turned or oblong symbols (turn.*); a pen of infinite
// width across the series (inf.*: never hit, upstream's stroked rect is
// not-a-number, but where it is a treemap's, a radar's area, a line's or a
// label's words).
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
// R7-I adds (r7i.*): a radar with no areaStyle (RadarView builds the polygon
// ignored: never hit) and its other parts; and the clips zrender's isHover
// asks up the parents -- a line's lineGroup (a cartesian's rect widened by
// the line's width, a polar's sector), a large bar's and a candlestick's
// group, a partly clipped candle or box, a lines series' group, a custom
// series' group, the growing clip of an entering line or parallel series
// -- against the series that clip their geometry instead (bars, scatter)
// or not at all (a graph on a cartesian). A case may say
//   tick   the timers setTimeout queued run after setOption (the next
//          macrotask: ParallelView's removeClipPath once its clip is done)
//   t      the option animates: the clock moves t ms past setOption, then
//          zr.animation.update() and the timers -- what the pointer finds
//          that far into the entering animation
// A custom series' renderItem is written '@name' and run as RENDER[name].
// R7-P adds (r7p.*): pens a transform stretches -- a pictorial glyph's
// (the pattern size scaled to an oblong glyph: the pen in the glyph's frame,
// wide across its upright sides, thin across its level ones; rounded, turned
// and mirrored), a graphic element's own scaleX / scaleY (a rect's pen, and a
// strokeNoScale polyline's under scaleY 1, whose line scale is 1).
// R7-O adds (r7o.*): a graph edge's end symbols, which take the pointer as
// the edge's (setItemGraphicEl writes its ECData onto every child of the
// Line group) -- an arrow, an empty circle (its pen lineWidth 2 in its own
// frame, filled with the ground), a diamond and an empty rect, on a view
// scaled equally and on one whose scaleY is not its scaleX (the symbols
// squashed by scaleY / scaleX after their turn); and a scatter's arrow,
// whose barbs reach two thirds of its width out of its unit box's centre
// (r7o.scatter-arrow-barbs: the rays pass under them).
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
// [R7-I] timers queue and run only where a case asks (nothing else here
// ever saw one run: the generation is synchronous)
let TIMERS = [];
global.setTimeout = function (fn) { TIMERS.push(fn); return TIMERS.length; };
global.clearTimeout = function () {};
function flushTimers() {
  for (let guard = 0; TIMERS.length && guard < 100; guard++) {
    const q = TIMERS;
    TIMERS = [];
    q.forEach(fn => fn());
  }
}
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

// [id, option, aims]
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
    ['pie.round-plain', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: { borderRadius: 20 } }), [IT(0, 0)]],
    ['pie.infinite', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: B('Infinity') }), [PT(200, 150, 120)]],
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
    ['line.infinite', cart({ type: 'line', symbol: 'none', data: [5, 5, 7], lineStyle: { width: 'Infinity' } }),
      [PT(200, 150, 120)]],
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
    ['scatter.pin', sc('pin', 30, B(12)), [IT(0, 1)]],
    ['scatter.pin-big', sc('pin', 90, {}), [IT(0, 1)]],
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
      links: GRAPH_LINKS, lineStyle: { width: 12, curveness: 0.3, opacity: 1 } }), [EDGE(0, 0), IT(0, 2)]],
    ['graph.straight-w1', solo({ type: 'graph', layout: 'none', symbolSize: 20, data: GRAPH_NODES_TILT, links: GRAPH_LINKS,
      lineStyle: { width: 1, opacity: 1 } }), [EDGE(0, 0)]],
    ['lines.w12', vv({ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { width: 12, curveness: 0.3, opacity: 1 },
      data: [{ coords: [[1, 2], [9, 8]] }] }), [IT(0, 0)]],
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
    // ---- R7-F: a fill written 'none' is no fill, a clear pen is a pen ----
    ['none.bar', bar(B(8, { color: 'none' })), [IT(0, 1)]],
    ['none.bar-bare', bar({ color: 'none' }), [PT(200, 150, 60)]],
    ['none.bar-item', bar({}, { data: [4, { value: 6, itemStyle: { color: 'none', borderColor: '#000', borderWidth: 6 } }, 8] }),
      [IT(0, 1)]],
    ['none.bar-null', bar(B(8, { color: null })), [IT(0, 1)]],
    ['none.scatter', sc('circle', 20, B(4, { color: 'none' })), [IT(0, 1)]],
    ['none.pie', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: B(6, { color: 'none' }) }), [IT(0, 1)]],
    ['none.funnel', solo({ type: 'funnel', label: { show: false }, data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 },
      { name: 'c', value: 1 }], itemStyle: B(8, { color: 'none' }) }), [IT(0, 1)]],
    ['none.sunburst', solo({ type: 'sunburst', radius: [20, 120], label: { show: false },
      data: [{ name: 'a', value: 3, children: [{ name: 'a1', value: 3 }] }, { name: 'b', value: 2 }],
      itemStyle: B(6, { color: 'none' }) }), [PT(200, 150, 140)]],
    ['none.line-area', cart({ type: 'line', symbol: 'none', data: [5, 5, 7], areaStyle: { color: 'none' },
      lineStyle: { width: 2 } }), [PT(200, 110, 40)]],
    ['none.radar-area', { animation: false, color: PAL, radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 },
      { name: 'r', max: 10 }], radius: 110 }, series: [{ type: 'radar', symbol: 'none', lineStyle: { width: 4 },
      areaStyle: { color: 'none' }, data: [{ value: [8, 6, 7] }] }] }, [PT(200, 150, 120)]],
    ['clear.pie-border', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: { borderColor: 'transparent', borderWidth: 12 } }), [IT(0, 0)]],
    ['clear.scatter-border', sc('circle', 20, { borderColor: 'transparent', borderWidth: 12 }), [IT(0, 1)]],
    ['clear.scatter-rgba', sc('rect', 30, { borderColor: 'rgba(0,0,0,0)', borderWidth: 12 }), [IT(0, 1)]],
    ['clear.funnel-border', solo({ type: 'funnel', label: { show: false }, data: [{ name: 'a', value: 3 },
      { name: 'b', value: 2 }, { name: 'c', value: 1 }], itemStyle: { borderColor: 'transparent', borderWidth: 12 } }),
      [IT(0, 1)]],
    ['clear.heatmap-border', Object.assign(cart({ type: 'heatmap', data: [[0, 0, 1], [1, 1, 2], [2, 0, 3]],
      itemStyle: { borderColor: 'transparent', borderWidth: 10 } }),
      { yAxis: { type: 'category', data: ['p', 'q'] }, visualMap: { show: false, min: 0, max: 3 } }), [IT(0, 1)]],
    ['opacity0.bar', bar(B(8, { opacity: 0 })), [IT(0, 1)]],
    ['opacity0.scatter', sc('circle', 20, B(4, { opacity: 0 })), [IT(0, 1)]],
    ['opacity0.pie', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1, 2, 3],
      itemStyle: { opacity: 0 } }), [IT(0, 1)]],
    // ---- R7-F: curves as curves ----
    ['curve.graph-w1', solo({ type: 'graph', layout: 'none', symbolSize: 20, data: GRAPH_NODES, links: GRAPH_LINKS,
      lineStyle: { width: 1, curveness: 0.5, opacity: 1 } }), [EDGE(0, 0), EDGE(0, 1)]],
    ['curve.lines-w3', vv({ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { width: 3, curveness: -0.4, opacity: 1 },
      data: [{ coords: [[1, 2], [9, 8]] }] }), [IT(0, 0)]],
    ['curve.pin-b4', sc('pin', 40, B(4)), [IT(0, 1)]],
    // ---- R7-F: turned labels ----
    ['turn.label-plate', bar({}, { label: { show: true, position: 'top', rotate: 30, backgroundColor: '#eee', padding: 4,
      borderWidth: 6, borderColor: '#000' } }), [LBL(0, 1)]],
    ['turn.label-text', bar({}, { label: { show: true, position: 'top', rotate: 45, fontSize: 20 } }), [LBL(0, 1)]],
    ['turn.label-stroke', bar({}, { label: { show: true, position: 'top', rotate: -60, fontSize: 20, textBorderWidth: 8,
      textBorderColor: '#fff' } }), [LBL(0, 1)]],
    // ---- R7-F: turned and oblong symbols ----
    ['turn.rect', sc('rect', 30, B(12), { symbolRotate: 30 }), [IT(0, 1)]],
    ['turn.triangle', sc('triangle', 30, B(12), { symbolRotate: 30 }), [IT(0, 1)]],
    ['turn.circle', sc('circle', 20, B(20), { symbolRotate: 30 }), [IT(0, 1)]],
    ['turn.pin', sc('pin', 40, B(6), { symbolRotate: 120 }), [IT(0, 1)]],
    ['turn.roundrect', sc('roundRect', 30, B(6), { symbolRotate: 45 }), [IT(0, 1)]],
    ['turn.diamond-offset', sc('diamond', 30, B(8), { symbolRotate: -40, symbolOffset: [5, -3] }), [IT(0, 1)]],
    ['turn.oblong-rect', sc('rect', [40, 16], B(8)), [IT(0, 1)]],
    ['turn.oblong-circle', sc('circle', [40, 16], B(6), { symbolRotate: 30 }), [IT(0, 1)]],
    ['turn.line-symbol', cart({ type: 'line', symbol: 'rect', symbolSize: 24, symbolRotate: 30, data: [5, 5, 7],
      lineStyle: { width: 1 }, itemStyle: B(8) }), [IT(0, 1)]],
    // ---- R7-F: a pen of infinite width ----
    ['inf.sunburst', solo({ type: 'sunburst', radius: [20, 120], label: { show: false },
      data: [{ name: 'a', value: 3, children: [{ name: 'a1', value: 3 }] }, { name: 'b', value: 2 }],
      itemStyle: B('Infinity') }), [PT(200, 150, 140)]],
    ['inf.funnel', solo({ type: 'funnel', label: { show: false }, data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 },
      { name: 'c', value: 1 }], itemStyle: B('Infinity') }), [PT(200, 150, 150)]],
    ['inf.treemap', solo({ type: 'treemap', breadcrumb: { show: false }, nodeClick: false, roam: false,
      data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }], itemStyle: B('Infinity', { gapWidth: 0 }) }),
      [PT(200, 150, 150)]],
    ['inf.heatmap', Object.assign(cart({ type: 'heatmap', data: [[0, 0, 1], [1, 1, 2], [2, 0, 3]], itemStyle: B('Infinity') }),
      { yAxis: { type: 'category', data: ['p', 'q'] }, visualMap: { show: false, min: 0, max: 3 } }), [PT(200, 150, 150)]],
    ['inf.themeriver', solo({ type: 'themeRiver', label: { show: false }, data: [[0, 3, 'a'], [1, 4, 'a'], [2, 3, 'a'],
      [0, 2, 'b'], [1, 2, 'b'], [2, 3, 'b']], itemStyle: B('Infinity') },
    { singleAxis: { type: 'value', min: 0, max: 2, top: 40, bottom: 40, axisLabel: { show: false } } }), [PT(200, 150, 150)]],
    ['inf.radar-line', { animation: false, color: PAL, radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 },
      { name: 'r', max: 10 }], radius: 110 }, series: [{ type: 'radar', symbol: 'none', lineStyle: { width: 'Infinity' },
      areaStyle: {}, data: [{ value: [8, 6, 7] }] }] }, [PT(200, 150, 150)]],
    ['inf.candle', cart({ type: 'candlestick', barWidth: 30, data: [[3, 7, 1, 9], [6, 4, 2, 8], [4, 6, 3, 7]],
      itemStyle: { borderWidth: 'Infinity' } }), [PT(200, 150, 150)]],
    ['inf.boxplot', cart({ type: 'boxplot', boxWidth: [30, 30], data: [[1, 3, 5, 7, 9], [2, 4, 5, 6, 8], [1, 2, 3, 4, 5]],
      itemStyle: { borderWidth: 'Infinity' } }), [PT(200, 150, 150)]],
    ['inf.sankey', solo({ type: 'sankey', label: { show: false }, data: [{ name: 'a' }, { name: 'b' }],
      links: [{ source: 'a', target: 'b', value: 3 }], itemStyle: B('Infinity'),
      lineStyle: { borderWidth: 'Infinity', borderColor: '#000', opacity: 1 } }), [PT(200, 150, 200)]],
    ['inf.graph-edge', solo({ type: 'graph', layout: 'none', symbolSize: 20, data: GRAPH_NODES, links: GRAPH_LINKS,
      lineStyle: { width: 'Infinity', curveness: 0.3, opacity: 1 } }), [PT(200, 150, 200)]],
    ['inf.lines', vv({ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { width: 'Infinity', opacity: 1 },
      data: [{ coords: [[1, 2], [9, 8]] }] }), [PT(200, 150, 150)]],
    ['inf.parallel', { animation: false, color: PAL, parallelAxis: [{ dim: 0, min: 0, max: 10 }, { dim: 1, min: 0, max: 10 },
      { dim: 2, min: 0, max: 10 }], series: [{ type: 'parallel', lineStyle: { width: 'Infinity', opacity: 1 },
      data: [[5, 5, 2], [2, 8, 8]] }] }, [PT(200, 150, 150)]],
    ['inf.polarbar', { animation: false, color: PAL, polar: { radius: [30, 120] }, angleAxis: { max: 10, axisTick: { show: false } },
      radiusAxis: { type: 'category', data: N },
      series: [{ type: 'bar', coordinateSystem: 'polar', roundCap: true, data: [4, 6, 8], itemStyle: B('Infinity') }] },
      [PT(200, 150, 150)]],
    ['inf.gauge-progress', solo({ type: 'gauge', data: [{ value: 40 }], axisLine: { show: false }, splitLine: { show: false },
      axisTick: { show: false }, axisLabel: { show: false }, pointer: { show: false }, anchor: { show: false },
      title: { show: false }, detail: { show: false },
      progress: { show: true, roundCap: true, width: 14, itemStyle: B('Infinity') } }), [PT(200, 150, 150)]],
    ['inf.gauge-pointer', solo({ type: 'gauge', data: [{ value: 40 }], axisLine: { show: false }, splitLine: { show: false },
      axisTick: { show: false }, axisLabel: { show: false }, anchor: { show: false }, title: { show: false },
      detail: { show: false }, itemStyle: B('Infinity') }), [PT(200, 150, 150)]],
    ['inf.chord', solo({ type: 'chord', label: { show: false }, data: [{ name: 'a' }, { name: 'b' }],
      links: [{ source: 'a', target: 'b', value: 3 }], itemStyle: B('Infinity'),
      lineStyle: { color: '#000', width: 'Infinity', opacity: 1 } }), [PT(200, 150, 150)]],
    ['inf.tree', solo({ type: 'tree', data: [TREE], symbolSize: 16, label: { show: false }, expandAndCollapse: false,
      itemStyle: B('Infinity'), lineStyle: { width: 'Infinity' } }), [PT(200, 150, 200)]],
    ['inf.effect', vv({ type: 'effectScatter', symbolSize: 20, rippleEffect: { number: 0 }, showEffectOn: 'emphasis',
      data: [[2, 2], [5, 5], [8, 8]], itemStyle: B('Infinity') }), [PT(200, 150, 150)]],
    ['inf.pictorial', cart({ type: 'pictorialBar', symbol: 'rect', symbolSize: [40, 30], symbolRepeat: false,
      symbolPosition: 'center', data: [4, 6, 8], itemStyle: B('Infinity') }), [PT(200, 150, 150)]],
    ['inf.graph-node', solo({ type: 'graph', layout: 'none', symbolSize: 20, itemStyle: B('Infinity'), data: GRAPH_NODES,
      links: [], lineStyle: { width: 2 } }), [PT(200, 150, 200)]],
    ['inf.label-plate', bar({}, { label: { show: true, position: 'top', backgroundColor: '#eee', padding: 4,
      borderWidth: 'Infinity', borderColor: '#000' } }), [PT(200, 100, 60)]],
    ['inf.line-symbol', cart({ type: 'line', symbolSize: 16, data: [5, 5, 7], lineStyle: { width: 2 },
      itemStyle: B('Infinity') }), [PT(200, 150, 150)]],
    // ---- R7-F: an item's own, and the other series' symbols ----
    ['clear.scatter-item', sc('rect', 30, {}, { data: [[2, 2], { value: [5, 5],
      itemStyle: { borderColor: 'transparent', borderWidth: 12 } }, [8, 8]] }), [IT(0, 1)]],
    ['none.pie-item', solo({ type: 'pie', radius: [40, 100], label: { show: false }, data: [1,
      { value: 2, itemStyle: { color: 'none', borderColor: '#000', borderWidth: 6 } }, 3] }), [IT(0, 1)]],
    ['none.graph-node', solo({ type: 'graph', layout: 'none', symbolSize: 30, itemStyle: B(4, { color: 'none' }),
      data: GRAPH_NODES, links: [] }), [IT(0, 2)]],
    ['none.line-symbol', cart({ type: 'line', symbolSize: 24, data: [5, 5, 7], lineStyle: { width: 1, color: '#888' },
      itemStyle: B(4, { color: 'none' }) }), [IT(0, 1)]],
    ['none.effect', vv({ type: 'effectScatter', symbolSize: 24, rippleEffect: { number: 0 }, showEffectOn: 'emphasis',
      data: [[2, 2], [5, 5], [8, 8]], itemStyle: B(4, { color: 'none' }) }), [IT(0, 1)]],
    ['none.boxplot', cart({ type: 'boxplot', boxWidth: [40, 40], data: [[1, 3, 5, 7, 9], [2, 4, 5, 6, 8], [1, 2, 3, 4, 5]],
      itemStyle: { color: 'none', borderWidth: 4 } }), [IT(0, 1)]],
    ['none.tree-node', solo({ type: 'tree', data: [TREE], symbolSize: 24, label: { show: false }, expandAndCollapse: false,
      itemStyle: B(4, { color: 'none' }), lineStyle: { width: 1 } }), [PT(200, 150, 200)]],
    ['clear.label-text-border', bar({}, { label: { show: true, position: 'top', fontSize: 20, textBorderWidth: 10,
      textBorderColor: 'transparent' } }), [LBL(0, 1)]],
  ].concat(r7iCases());
}

// ---- R7-I ----
const RAD = (s, more) => Object.assign({ animation: false, color: PAL, radar: { indicator: [{ name: 'p', max: 10 },
  { name: 'q', max: 10 }, { name: 'r', max: 10 }], radius: 110 },
  series: [Object.assign({ type: 'radar', data: [{ value: [8, 6, 7] }] }, s || {})] }, more || {});
const ANIM = o => Object.assign(o, { animation: true, animationDuration: 1000, animationEasing: 'linear',
  animationDurationUpdate: 1000, animationEasingUpdate: 'linear' });
const PAR = (s, more) => Object.assign({ animation: false, color: PAL, parallelAxis: [{ dim: 0, min: 0, max: 10 },
  { dim: 1, min: 0, max: 10 }, { dim: 2, min: 0, max: 10 }],
  series: [Object.assign({ type: 'parallel', lineStyle: { width: 6, opacity: 1 }, data: [[5, 14, 2], [2, 8, 8]] }, s || {})] },
  more || {});
const RENDER = {
  // a rect from the grid's middle out past its right edge
  cuclip: function (params, api) {
    const c = api.coord([api.value(0), api.value(1)]);
    return { type: 'rect', shape: { x: c[0], y: c[1] - 20, width: 200, height: 40 }, style: { fill: '#c00' } };
  },
};
function r7iCases() {
  return [
    // a radar: the polygon is built ignored without an areaStyle -- never hit
    ['r7i.radar-default', RAD(), [PT(200, 150, 130)]],
    ['r7i.radar-plain', RAD({ symbol: 'none', lineStyle: { width: 4 } }), [PT(200, 150, 130)]],
    ['r7i.radar-symbols', RAD({ symbolSize: 14, itemStyle: B(3) }), [PT(200, 150, 130)]],
    ['r7i.radar-area-op0', RAD({ symbol: 'none', areaStyle: { opacity: 0 } }), [PT(200, 150, 130)]],
    ['r7i.radar-emph-area', RAD({ symbol: 'none', emphasis: { areaStyle: { color: '#f00' } } }), [PT(200, 150, 130)]],
    ['r7i.radar-item-area', RAD({ symbol: 'none', data: [{ value: [8, 6, 7] }, { value: [4, 9, 3], areaStyle: {} }] }),
      [PT(200, 150, 130)]],
    ['r7i.radar-circle', RAD({ symbol: 'none' }, { radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 },
      { name: 'r', max: 10 }], radius: 110, shape: 'circle' } }), [PT(200, 150, 130)]],
    // a parallel line out past its axes' max: its clip is gone a macrotask
    // after the first render (no animation), so the line is hit out there
    ['r7i.par-out', PAR(), [IT(0, 0)], { tick: true }],
    // ... and while it enters, cut to the clip growing across the axes
    ['r7i.par-anim', ANIM(PAR()), [IT(0, 0), IT(0, 1)], { t: 300 }],
    ['r7i.par-anim-end', ANIM(PAR()), [IT(0, 0)], { t: 1100 }],
    // a line's group clip: the grid's rect, widened by the line's width
    ['r7i.line-out', cart({ type: 'line', symbol: 'none', data: [5, 14, 7], lineStyle: { width: 8 } }), [POLY(0)]],
    ['r7i.line-out-noclip', cart({ type: 'line', symbol: 'none', clip: false, data: [5, 14, 7], lineStyle: { width: 8 } }),
      [POLY(0)]],
    ['r7i.line-area-out', cart({ type: 'line', symbol: 'none', data: [5, 14, 7], areaStyle: {}, lineStyle: { width: 2 } }),
      [AREA(0)]],
    ['r7i.line-polar-out', { animation: false, color: PAL, polar: { radius: [20, 100] }, angleAxis: { type: 'category', data: N },
      radiusAxis: { max: 10 }, series: [{ type: 'line', coordinateSystem: 'polar', symbol: 'none', lineStyle: { width: 6 },
      data: [5, 14, 7] }] }, [POLY(0)]],
    ['r7i.line-anim', ANIM(cart({ type: 'line', symbol: 'none', data: [5, 5, 7], lineStyle: { width: 8 } })), [PT(150, 150, 130)],
      { t: 400 }],
    // a large bar's group clip, a normal bar's geometry
    ['r7i.bar-large-out', cart({ type: 'bar', large: true, largeThreshold: 1, barWidth: 40, data: [4, 14, 8] }),
      [PT(200, 40, 60)]],
    ['r7i.bar-out', cart({ type: 'bar', barWidth: 40, data: [4, 14, 8] }), [PT(200, 40, 60)]],
    // a candle partly out: its own clip path; a box likewise
    ['r7i.candle-out', cart({ type: 'candlestick', barWidth: 30, data: [[3, 7, 1, 9], [6, 13, 2, 16], [4, 6, 3, 7]] }),
      [PT(200, 40, 60)]],
    ['r7i.boxplot-out', cart({ type: 'boxplot', boxWidth: [30, 30], data: [[1, 3, 5, 7, 9], [2, 4, 5, 12, 16],
      [1, 2, 3, 4, 5]] }), [PT(200, 40, 60)]],
    // a lines series' group clip (clip: true by default)
    ['r7i.lines-out', vv({ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { width: 6, opacity: 1 },
      data: [{ coords: [[2, 2], [11, 7]] }] }), [PT(360, 120, 40)]],
    ['r7i.lines-noclip', vv({ type: 'lines', coordinateSystem: 'cartesian2d', clip: false,
      lineStyle: { width: 6, opacity: 1 }, data: [{ coords: [[2, 2], [11, 7]] }] }), [PT(360, 120, 40)]],
    // a graph on a cartesian clips nothing
    ['r7i.graph-cart-out', vv({ type: 'graph', coordinateSystem: 'cartesian2d', symbolSize: 16,
      data: [[2, 5], [11, 6]], links: [{ source: 0, target: 1 }], lineStyle: { width: 4, opacity: 1 } }),
      [EDGE(0, 0), IT(0, 1)]],
    // a scatter's point out of the grid is not drawn at all
    ['r7i.scatter-out', vv({ type: 'scatter', symbolSize: 20, data: [[5, 5], [5, 10.4]] }), [PT(200, 53, 30)]],
    // a custom series' group clip where it says clip (not by default)
    ['r7i.custom-clip', vv({ type: 'custom', clip: true, renderItem: '@cuclip', data: [[6, 5]] }), [PT(310, 135, 120)]],
    ['r7i.custom-noclip', vv({ type: 'custom', renderItem: '@cuclip', data: [[6, 5]] }), [PT(310, 135, 120)]],
    // a theme river layer's and a sankey's group clip while they enter
    // (removeClipPath once done); the river's rays level only -- its smoothed
    // edges stand a step or two off upstream's on a slant, at rest too, which
    // is not the clip
    ['r7i.river-anim', ANIM(solo({ type: 'themeRiver', label: { show: false }, data: [[0, 3, 'a'], [1, 4, 'a'],
      [2, 3, 'a'], [0, 2, 'b'], [1, 2, 'b'], [2, 3, 'b']] },
    { singleAxis: { type: 'value', min: 0, max: 2, top: 40, bottom: 40, axisLabel: { show: false } } })),
    [Object.assign(PT(200, 150, 150), { dirs: [0, 4] })], { t: 300 }],
    // a thumbnail's window: its contentGroup's clip cuts it (zoomed in on the
    // graph's corner, the window hangs over the content's edge)
    ['r7i.thumb-window', { animation: false, color: PAL, thumbnail: {},
      series: [{ type: 'graph', layout: 'none', roam: true, zoom: 3, center: [100, 60], symbolSize: 20,
        data: GRAPH_NODES, links: GRAPH_LINKS }] }, [{ thumbWin: true }]],
    ['r7i.sankey-anim', ANIM(solo({ type: 'sankey', label: { show: false }, data: [{ name: 'a' }, { name: 'b' }],
      links: [{ source: 'a', target: 'b', value: 3 }], lineStyle: { opacity: 0.5 } })), [PT(200, 150, 200)], { t: 300 }],
    // [R7-O] a graph edge's end symbols: on a view scaled equally (2.6 both ways), then 3 across and 1.5 down
    ['r7o.graph-ends', solo({ type: 'graph', layout: 'none', left: 50, top: 20, width: 260, height: 260, symbolSize: 10,
      edgeSymbol: ['emptyCircle', 'arrow'], edgeSymbolSize: [16, 24], lineStyle: { width: 1, opacity: 1 },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }, { name: 'c', x: 100, y: 0 }],
      links: [{ source: 'a', target: 'c' }, { source: 'a', target: 'b' },
        { source: 'c', target: 'b', symbol: ['diamond', 'emptyRect'], symbolSize: 20 }] }),
    [PT(300, 21, 40), PT(56, 21, 30), PT(300, 270, 40), PT(310, 31, 30)]],
    ['r7o.graph-ends-squash', solo({ type: 'graph', layout: 'none', left: 50, top: 20, width: 300, height: 150, symbolSize: 10,
      edgeSymbol: ['emptyCircle', 'arrow'], edgeSymbolSize: [16, 24], lineStyle: { width: 1, opacity: 1 },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }, { name: 'c', x: 100, y: 0 },
        { name: 'd', x: 0, y: 100, symbol: 'rect', symbolSize: [24, 12], symbolRotate: 30,
          itemStyle: { borderColor: '#000', borderWidth: 3 } }],
      links: [{ source: 'a', target: 'c' }, { source: 'a', target: 'b' },
        { source: 'c', target: 'd', lineStyle: { curveness: 0.3 }, symbol: ['diamond', 'emptyRect'], symbolSize: 20 }] }),
    [PT(340, 21, 40), PT(56, 21, 30), PT(340, 165, 40), PT(345, 30, 30), PT(60, 165, 30)]],
    // a four-pixel empty circle at the ends of an upright edge, scaleX 2, scaleY 1: its unit frame's diagonal holds a one
    // (the pen in the symbol's own frame is not strokeNoScale -- no getLineScale rule); the line of no width takes no pointer
    ['r7o.graph-tiny-ends-squash', solo({ type: 'graph', layout: 'none', left: 100, top: 20, width: 100, height: 100, symbolSize: 0,
      edgeSymbol: ['emptyCircle', 'emptyCircle'], edgeSymbolSize: 4, lineStyle: { width: 0, opacity: 1, color: '#000' },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 0, y: 100 }, { name: 'c', x: 50, y: 50 }],
      links: [{ source: 'a', target: 'b' }] }),
    [PT(100, 20, 8), PT(100, 120, 8)]],
    // drawing out (enter, linear 1000 ms, 400 ms in): the line and its end symbols as drawn at the percent
    ['r7o.graph-squash-anim', ANIM(solo({ type: 'graph', layout: 'none', left: 50, top: 20, width: 300, height: 150,
      symbolSize: 10, edgeSymbol: ['emptyCircle', 'arrow'], edgeSymbolSize: [16, 24], lineStyle: { width: 1, opacity: 1 },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }, { name: 'c', x: 100, y: 0 }],
      links: [{ source: 'a', target: 'c' }, { source: 'a', target: 'b' }] })),
    [PT(56, 21, 30), PT(170, 21, 30), PT(150, 70, 30)], { t: 400 }],
    ['r7o.scatter-arrow-barbs', sc('arrow', 40, {}, { data: [[5, 5]] }), [PT(210, 178, 40), PT(210, 175, 40)]],
    // [R7-P] a pen the element's transform stretches: a pictorial glyph's (its
    // pattern size scaled to the glyph, the pen with it), a graphic element's
    // own scaleX / scaleY (strokeNoScale or not)
    ['r7p.pictorial-oblong', cart({ type: 'pictorialBar', symbol: 'rect', symbolSize: [60, 16], symbolRepeat: false,
      symbolPosition: 'center', data: [4, 6, 8], itemStyle: B(100) }), [IT(0, 1)]],
    ['r7p.pictorial-turned', cart({ type: 'pictorialBar', symbol: 'triangle', symbolSize: [24, 60], symbolRotate: 30,
      symbolRepeat: false, symbolPosition: 'center', data: [4, -6, 8], itemStyle: B(120) },
      { yAxis: { type: 'value', min: -10, max: 10 } }), [IT(0, 1)]],
    ['r7p.pictorial-round', cart({ type: 'pictorialBar', symbol: 'roundRect', symbolSize: [60, 16], symbolRepeat: false,
      symbolPosition: 'center', data: [4, 6, 8], itemStyle: B(100) }), [IT(0, 1)]],
    ['r7p.graphic-scaled', { animation: false, graphic: [{ type: 'rect', x: 140, y: 120, scaleX: 3, scaleY: 1,
      shape: { x: 0, y: 0, width: 40, height: 60 }, style: { fill: null, stroke: '#000', lineWidth: 6 } }] },
      [PT(200, 150, 90)]],
    ['r7p.graphic-noscale', { animation: false, graphic: [{ type: 'polyline', x: 100, y: 160, scaleX: 4, scaleY: 1,
      shape: { points: [[0, 0], [25, -30], [50, 0]] }, style: { fill: null, stroke: '#000', lineWidth: 6, strokeNoScale: true } }] },
      [PT(200, 145, 90)]],
  ].map(c => c.length > 3 ? c : c.concat([{}]));
}
function withRender(option) {
  (option.series || []).forEach(s => {
    if (typeof s.renderItem === 'string' && s.renderItem[0] === '@') {
      const fn = RENDER[s.renderItem.slice(1)];
      must(fn, 'no RENDER ' + s.renderItem);
      s.renderItem = fn;
    }
  });
  return option;
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
  if (a.thumbWin) {
    const tm = chart.getModel().getComponent('thumbnail', 0);
    const v = tm && chart.getViewOfComponentModel(tm);
    must(v && v._windowRect, 'no thumbnail window');
    return v._windowRect;
  }
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
function run(id, option, aims, more) {
  NOW = T_BASE;
  rngState = SEED;
  TIMERS = [];
  more = more || {};
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(withRender(JSON.parse(JSON.stringify(option))));
    chart.getZr().storage.getDisplayList(true);
    if (more.tick) flushTimers();
    if (more.t !== undefined) {
      NOW = T_BASE + more.t;
      chart.getZr().animation.update();
      flushTimers();
    }
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
    if (more.tick) rec.tick = true;
    if (more.t !== undefined) { rec.t = more.t; rec.T0 = T_BASE; }
    return rec;
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(([id, o, aims, more]) => run(id, o, aims, more));
  const by = id => charts.find(c => c.id === id);
  // every case hits its aim somewhere, but the silent one, the one with
  // neither a fill nor a pen, and the infinite pens upstream never hits
  const MISS = ['bar.silent', 'scatter.infinite', 'pie.infinite', 'line.infinite', 'none.bar-bare',
    'inf.sunburst', 'inf.funnel', 'inf.heatmap', 'inf.themeriver', 'inf.candle', 'inf.boxplot', 'inf.sankey',
    'inf.lines', 'inf.parallel', 'inf.polarbar', 'inf.gauge-progress', 'inf.gauge-pointer', 'inf.chord',
    'inf.effect', 'inf.pictorial', 'inf.graph-node', 'r7i.scatter-out',
    'r7i.thumb-window',
    // a graphic element is no series' (x)
    'r7p.graphic-scaled', 'r7p.graphic-noscale'];
  charts.forEach(c => {
    const any = c.rays.some(r => r.seq.split(' ').some(p => p[0] === 's'));
    must(any === !MISS.includes(c.id), c.id + ': hits ' + any);
  });
  // a bar whose 1000 px border took all of its width is hit over most of the grid
  must(by('bar.b1000').rays[4].seq === 's0/1*' + by('bar.b1000').rays[4].n, 'bar.b1000: ' + by('bar.b1000').rays[4].seq);
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-C: per case, rays from each aim\'s centre (the global bounding rect of an item\'s graphic element, a series view\'s '
      + 'polyline / polygon, a graph edge or an item\'s label, rounded; or a point) in eight directions, a pixel a step, out to '
      + 'the half diagonal and 4 (or the point\'s reach) or the canvas\' edge: `seq` what findHover(x, y).target is at each step, '
      + 'run-length encoded -- sS/D the series and data index of the ECData the dispatcher walk finds (sS/eD an edge), sS/- a '
      + 'series\' ECData without a data index, x a target without one, - none.', W, H, charts };
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
