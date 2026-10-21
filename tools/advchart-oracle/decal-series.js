// Upstream's own answers for DECALS ON THE REST OF THE SERIES (fix phase F4a):
//
// decal-aria.js (batch 131) pinned the decal object, its tile and who gets
// one, and what the bars, the slices, the funnel bands and a line's area
// really draw. Every other view that draws an item through its style draws
// the decal too -- zrender's Path.update gives any path whose style holds a
// decal a second path the same shape, filled with the pattern when the path
// itself fills -- and some take it their own way:
//
//   radar        the area polygon: defaults(areaStyle, {decal: itemStyle.decal})
//                (RadarView), drawn only where the area is not ignored (an
//                item's own areaStyle shows it); the points are createSymbol's
//                and keep the item's decal
//   sunburst     SunburstPiece: node.getVisual('decal') -> the pattern
//   treemap      the content rect: normalStyle.decal = nodeStyle.decal
//   both trees   aria: enableAriaDecalForTree -- every node takes the decal
//                of its depth-1 ancestor's name (or data index), over a
//                scope new every call; they take nothing from the chart's
//   candlestick, boxplot, heatmap, chord pieces, themeRiver layers (the
//                last row's style), the gauge's pointer and progress,
//                pictorialBar symbols, the large bar's batch path:
//                useStyle(the item's / the series' style)
//   sankey       nodes (rect.setStyle('decal', ...)); an edge coloured
//                'source' / 'target' takes that node's decal
//   chord        the same for an edge's lineStyle.color 'source' / 'target'
//   custom       a path a renderItem returns with style.decal (an object):
//                createOrUpdatePatternFromDecal; api.visual('decal') is the
//                item's decal visual
//   symbols      Symbol.ts clears the decal (scatter, a line's points, a
//                graph's nodes, a radar's points): nothing
//   legend       a line's own icon (LineSeries.getLegendIcon): its symbol
//                takes the legend style's decal, an empty one too
//
// Every displayable of the display list whose decal element is filled is
// recorded with the ECData it (or its nearest ancestor) carries -- series,
// dataType, dataIndex -- and the pattern. A pattern is its tile: the symbols
// renderOneToVNode was handed (hooked as decal-aria.js does), its size and
// rotation; the symbol's own fill / stroke / lineWidth carry the colour.
//
// TILES of the decal symbols decal-aria.js left out: empty symbols (createSymbol
// strips 'empty', symbolPathSetColor fills them with tokens.color.neutral00,
// strokes them in the colour, lineWidth 2), 'path://' (graphic.makePath fitted
// to the box, 'center' with keepAspect else 'cover': its bounding rect) and
// 'image://' (graphic.makeImage: a ZRImage of the box -- the SSR has no image
// loading, so its onload never re-centres it).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400.
// Every option has `animation: false`.
//
//   node tools/advchart-oracle/decal-series.js
//
// writes tests/fixtures/advchart-decal-series.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex   a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//         lowercase.
//
// Top level: source, W, H, notes[], tiles[], scenarios[], anchors[]
// A tile case: id, decal (the option's decal object), tile
// A tile: {w, h (svgWidth / svgHeight), rotation hex, symbols [{type
//   (symbolType, 'path' or 'image'), empty, x, y, w, h hex (the box
//   createSymbol was given), fill, stroke, lineWidth, bbox [x, y, w, h] hex
//   (a path's bounding rect after the fit; an image's x, y, width, height)}]}
// A scenario: id, note, steps[] {option (raw JSON; renderItem '@name'),
//   merge, record}
// A record
//   error     null | the exception's message
//   patterns[] distinct tiles of this update
//   series[]  per series MODEL, eachRawSeries: {index, type, drawn [{t
//             dataType ('' for main data), i dataIndex (-1: none), k the
//             element's type, p pattern index}] sorted}
//   legend[]  per legend item in order: {name, els [{k, sym, p}]} -- every
//             displayable of the item whose decal element fills
// ---------------------------------------------------------------------------
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-decal-series.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

// ---------- the symbols renderOneToVNode was handed ----------
let vnodeEl = new WeakMap();
function hookPainter(chart) {
  const painter = chart.getZr().painter;
  const orig = painter.renderOneToVNode.bind(painter);
  painter.renderOneToVNode = function (el) {
    const vnode = orig(el);
    if (vnode) vnodeEl.set(vnode, el);
    return vnode;
  };
}
function symRec(el) {
  const st = el.style || {};
  const r = { type: null, empty: !!el.__isEmptyBrush, x: null, y: null, w: null, h: null,
    fill: st.fill == null ? null : String(st.fill), stroke: st.stroke == null ? null : String(st.stroke),
    lineWidth: st.lineWidth == null ? null : hex(st.lineWidth), bbox: null };
  if (el.type === 'image') {
    r.type = 'image';
    r.bbox = [hex(st.x), hex(st.y), hex(st.width), hex(st.height)];
  }
  else if (el.shape && typeof el.shape.symbolType === 'string') {
    const sh = el.shape;
    r.type = sh.symbolType;
    r.x = hex(sh.x); r.y = hex(sh.y); r.w = hex(sh.width); r.h = hex(sh.height);
  }
  else {
    // a 'path://' symbol: makePath fitted the path to the box
    r.type = 'path';
    const b = el.getBoundingRect();
    r.bbox = [hex(b.x), hex(b.y), hex(b.width), hex(b.height)];
  }
  return r;
}
function tileOfPattern(p) {
  must(p.svgElement && Array.isArray(p.svgElement.children), 'a pattern without its svg element');
  const symbols = p.svgElement.children.map(vn => {
    const el = vnodeEl.get(vn);
    must(el, 'a decal vnode not made by renderOneToVNode');
    return symRec(el);
  });
  return { w: p.svgWidth, h: p.svgHeight, rotation: hex(p.rotation), symbols };
}

// ---------- the renderItems (each mirrored in tests/test.advchart.decalseries.pas) ----------
const RENDER = {
  // a bar from the axis to the value, the item's decal visual on it
  decalBar(params, api) {
    const base = api.coord([api.value(0), 0]);
    const top = api.coord([api.value(0), api.value(1)]);
    return { type: 'rect', shape: { x: base[0] - 15, y: top[1], width: 30, height: base[1] - top[1] },
      style: { fill: api.visual('color'), decal: api.visual('decal') } };
  },
  // a circle with a decal written in renderItem, a text beside it that
  // cannot take one, and a polyline that does not fill
  decalLit(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    return { type: 'group', children: [
      { type: 'circle', shape: { cx: p[0], cy: p[1], r: 18 },
        style: { fill: '#91cc75', decal: { symbol: 'circle', dashArrayX: 4, dashArrayY: 4, color: 'red' } } },
      { type: 'text', x: p[0] + 20, y: p[1], style: { text: 'T', fill: '#333', decal: { symbol: 'rect' } } },
      { type: 'polyline', shape: { points: [[p[0] - 20, p[1] + 25], [p[0] + 20, p[1] + 25]] },
        style: { stroke: '#333', fill: null, decal: { symbol: 'rect' } } }] };
  },
};
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (k === 'renderItem' && typeof v[k] === 'string' && v[k][0] === '@') {
        const fn = RENDER[v[k].slice(1)];
        must(fn, 'no renderItem ' + v[k]);
        o[k] = fn;
      }
      else o[k] = materialize(v[k]);
    }
    return o;
  }
  return v;
}

// ---------- a chart ----------
function makeChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  hookPainter(chart);
  return chart;
}

// getECData = makeInner(): an own '__ec_inner_<n>' key; the nearest one up
// the parents that names a series
function ecDataOf(el) {
  for (let e = el; e; e = e.parent) {
    for (const k of Object.keys(e)) {
      if (k.startsWith('__ec_inner_') && e[k] && typeof e[k] === 'object' && e[k].seriesIndex != null) return e[k];
    }
  }
  return null;
}

function record(chart) {
  chart.renderToSVGString();
  const zr = chart.getZr();
  const list = zr.storage.getDisplayList(true);
  const patterns = [];
  const keyOf = new Map();
  function patIndex(pattern) {
    if (keyOf.has(pattern)) return keyOf.get(pattern);
    const rec = tileOfPattern(pattern);
    const sig = JSON.stringify(rec);
    let k = patterns.findIndex(p => JSON.stringify(p) === sig);
    if (k < 0) {
      k = patterns.length;
      patterns.push(rec);
    }
    keyOf.set(pattern, k);
    return k;
  }
  // the legend's content group: its displayables are recorded per item
  const model = chart.getModel();
  const legendEls = new Set();
  const legend = [];
  const lgModel = model.getComponent('legend');
  if (lgModel) {
    const lgView = chart._componentsMap[lgModel.__viewId];
    const content = lgView && lgView.getContentGroup ? lgView.getContentGroup() : null;
    if (content) {
      content.eachChild(g => {
        let name = null;
        const els = [];
        g.traverse(el => {
          legendEls.add(el);
          if (el.type === 'text' && name === null && el.style && typeof el.style.text === 'string') name = el.style.text;
          const de = el.getDecalElement && el.getDecalElement();
          if (de && de.style.fill && !el.invisible) {
            els.push({ k: el.type, sym: el.shape && typeof el.shape.symbolType === 'string' ? el.shape.symbolType : null,
              p: patIndex(de.style.fill) });
          }
        });
        legend.push({ name, els });
      });
    }
  }
  const bySeries = new Map();
  for (const el of list) {
    if (legendEls.has(el) || el.invisible) continue;
    const de = el.getDecalElement && el.getDecalElement();
    if (!de || !de.style.fill) continue;
    const ec = ecDataOf(el);
    must(ec, 'a decal drawn on an element of no series: ' + el.type);
    const s = ec.seriesIndex;
    if (!bySeries.has(s)) bySeries.set(s, []);
    bySeries.get(s).push({ t: ec.dataType && ec.dataType !== 'main' ? ec.dataType : '',
      i: ec.dataIndex == null ? -1 : ec.dataIndex, k: el.type, p: patIndex(de.style.fill) });
  }
  const series = [];
  model.eachRawSeries(s => {
    const drawn = (bySeries.get(s.seriesIndex) || []).slice();
    drawn.sort((a, b) => (a.t < b.t ? -1 : a.t > b.t ? 1 : a.i - b.i || (a.k < b.k ? -1 : a.k > b.k ? 1 : a.p - b.p)));
    series.push({ index: s.seriesIndex, type: s.subType, drawn });
  });
  return { error: null, patterns, series, legend };
}

// ---------- the tile cases ----------
// a 2 x 1 PNG: red then blue
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQv8BD/kD/YURmXYAAAAASUVORK5CYII=';
const TILES = [
  ['empty-circle', { symbol: 'emptyCircle', dashArrayX: [8, 4], dashArrayY: [8, 4] }],
  ['empty-mixed', { symbol: ['emptyRect', 'diamond', 'emptyTriangle'], dashArrayX: [6, 2], dashArrayY: [6, 2], color: 'blue' }],
  ['empty-roundrect', { symbol: 'emptyRoundRect', symbolSize: 0.8, dashArrayX: 10, dashArrayY: 6 }],
  ['path-keep', { symbol: 'path://M0,0L10,0L10,20L0,20Z', dashArrayX: [12, 4], dashArrayY: [8, 4] }],
  ['path-cover', { symbol: 'path://M0,0L10,0L5,10Z', symbolKeepAspect: false, dashArrayX: [12, 4], dashArrayY: [8, 4] }],
  ['path-wide', { symbol: 'path://M0,5L40,5L40,15L0,15Z', symbolSize: 0.5, dashArrayX: [8, 8], dashArrayY: [16, 0] }],
  ['image', { symbol: 'image://' + PNG.slice(0), dashArrayX: [6, 2], dashArrayY: [6, 2] }],
  ['image-mixed', { symbol: ['image://' + PNG, 'circle'], symbolKeepAspect: false, dashArrayX: [4, 4], dashArrayY: [5, 3] }],
  ['line', { symbol: 'line', dashArrayX: [6, 2], dashArrayY: [6, 2] }],
];

function runTile(id, decal) {
  const chart = makeChart();
  try {
    chart.setOption({
      animation: false,
      xAxis: { data: ['a'] }, yAxis: {},
      series: [{ type: 'bar', itemStyle: { decal: JSON.parse(JSON.stringify(decal)) }, data: [1] }],
    });
    chart.renderToSVGString();
    const data = chart.getModel().getSeriesByIndex(0).getData();
    const pattern = data.getVisual('style').decal;
    must(pattern, 'tile ' + id + ': no pattern');
    return { id, decal, tile: tileOfPattern(pattern) };
  } finally {
    chart.dispose();
  }
}

// ---------- the scenarios ----------
const ARIA = { decal: { show: true } };
const CAT = { xAxis: { data: ['a', 'b', 'c', 'd'] }, yAxis: {} };
const TREE = [
  { name: 'A', children: [{ name: 'A1', value: 4 }, { name: 'A2', value: 2, children: [{ name: 'A2x', value: 2 }] }] },
  { name: 'B', value: 3 },
  { name: 'C', children: [{ name: 'C1', value: 2 }, { name: 'C2', value: 1 }] },
];
function treeOwn() {
  const t = JSON.parse(JSON.stringify(TREE));
  t[1].itemStyle = { decal: { symbol: 'triangle', dashArrayX: 6 } };
  t[2].children[0].itemStyle = { decal: { symbol: 'diamond' } };
  return t;
}
const SANKEY_NODES = [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }];
const SANKEY_LINKS = [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }, { source: 'b', target: 'd', value: 4 },
  { source: 'c', target: 'd', value: 2 }];
const SCENARIOS = [
  { id: 'radar', note: 'a radar area takes the item decal through its area style; a series without an area draws none; the points are symbols',
    steps: [
      { option: { aria: ARIA, radar: { indicator: [{ name: 'x', max: 10 }, { name: 'y', max: 10 }, { name: 'z', max: 10 }] },
        series: [
          { type: 'radar', areaStyle: {}, data: [{ name: 'r1', value: [3, 5, 7] }, { name: 'r2', value: [6, 2, 4], itemStyle: { decal: { symbol: 'circle' } } }] },
          { type: 'radar', name: 'plain', data: [{ name: 'r3', value: [8, 8, 2] }] }] } },
      { option: { radar: { indicator: [{ name: 'x', max: 10 }, { name: 'y', max: 10 }, { name: 'z', max: 10 }] },
        series: [{ type: 'radar', itemStyle: { decal: { symbol: 'rect', dashArrayX: 3 } },
          data: [{ name: 'r1', value: [3, 5, 7], areaStyle: {} }, { name: 'r2', value: [6, 2, 4] }] }] } },
    ] },
  { id: 'sunburst', note: 'aria: every node the decal of its depth-1 ancestor, a scope of its own; without aria the series\' and the nodes\' own',
    steps: [
      { option: { aria: ARIA, series: [{ type: 'sunburst', radius: [0, 150], data: TREE }, { type: 'sunburst', center: ['85%', '50%'], radius: 60, data: [{ name: 'B', value: 1 }, { name: 'Q', value: 2 }] }] } },
      { option: { series: [{ type: 'sunburst', radius: [0, 150], itemStyle: { decal: { symbol: 'circle', dashArrayX: 4 } }, data: treeOwn() }] } },
      { option: { aria: ARIA, series: [{ type: 'sunburst', name: 'B', radius: [0, 150], itemStyle: { decal: { symbol: 'pin' } }, data: treeOwn() }] } },
    ] },
  { id: 'treemap', note: 'the content rects: aria by the depth-1 ancestor; without aria the series\' and the nodes\' own',
    steps: [
      { option: { aria: ARIA, series: [{ type: 'treemap', breadcrumb: { show: false }, data: TREE }] } },
      { option: { series: [{ type: 'treemap', breadcrumb: { show: false }, itemStyle: { decal: { symbol: 'circle', dashArrayX: 4 } }, data: treeOwn() }] } },
      { option: { aria: ARIA, series: [{ type: 'treemap', name: 'A', breadcrumb: { show: false }, leafDepth: 1, data: TREE }] } },
    ] },
  { id: 'candle-box', note: 'candlestick bodies and boxplot boxes wear the item\'s decal',
    steps: [
      { option: Object.assign({ aria: ARIA }, CAT, { series: [
        { type: 'candlestick', data: [[2, 4, 1, 5], [4, 3, 2, 5], [3, 3, 2, 4], [3, 5, 2, 6]] },
        { type: 'boxplot', data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6], [1, 3, 4, 6, 7], [2, 2.5, 3, 4, 5]] }] }) },
      { option: Object.assign({}, CAT, { series: [
        { type: 'candlestick', itemStyle: { decal: { symbol: 'circle' } }, data: [[2, 4, 1, 5], { value: [4, 3, 2, 5], itemStyle: { decal: { symbol: 'diamond' } } }] },
        { type: 'boxplot', data: [[1, 2, 3, 4, 5], { value: [2, 3, 4, 5, 6], itemStyle: { decal: { symbol: 'triangle' } } }] }] }) },
    ] },
  { id: 'heatmap', note: 'a heatmap\'s cells on a grid and on a calendar',
    steps: [
      { option: { aria: ARIA, xAxis: { data: ['a', 'b', 'c'] }, yAxis: { data: ['p', 'q'] }, visualMap: { min: 0, max: 5, show: false },
        series: [{ type: 'heatmap', data: [[0, 0, 1], [1, 0, 2], [2, 0, 3], [0, 1, 4], [1, 1, 5], [2, 1, '-']] }] } },
      { option: { calendar: { range: ['2024-01-01', '2024-01-14'], cellSize: 20 }, visualMap: { min: 0, max: 5, show: false },
        series: [{ type: 'heatmap', coordinateSystem: 'calendar', itemStyle: { decal: { symbol: 'circle', dashArrayX: 3, dashArrayY: 3 } },
          data: [['2024-01-02', 1], ['2024-01-05', 3], ['2024-01-09', 5]] }] } },
    ] },
  { id: 'pictorial', note: 'a pictorial bar\'s symbols, repeated or not',
    steps: [
      { option: Object.assign({ aria: ARIA }, CAT, { series: [
        { type: 'pictorialBar', symbol: 'rect', data: [2, 4, 3, 1] },
        { type: 'pictorialBar', symbol: 'circle', symbolRepeat: true, symbolSize: 14, data: [1, 3, 2, 4] }] }) },
    ] },
  { id: 'graph', note: 'a graph\'s nodes are symbols, its edges do not fill: nothing',
    steps: [
      { option: { aria: ARIA, series: [{ type: 'graph', layout: 'none', itemStyle: { decal: { symbol: 'rect' } },
        data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 300, y: 200, symbolSize: 40 }, { name: 'c', x: 200, y: 300 }],
        links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] }] } },
    ] },
  { id: 'sankey', note: 'sankey nodes; edges coloured by their source or target take that node\'s decal',
    steps: [
      { option: { aria: ARIA, series: [{ type: 'sankey', data: SANKEY_NODES, links: SANKEY_LINKS, lineStyle: { color: 'source' } }] } },
      { option: { aria: ARIA, series: [{ type: 'sankey', data: SANKEY_NODES, links: SANKEY_LINKS, lineStyle: { color: 'target' } }] } },
      { option: { series: [{ type: 'sankey', itemStyle: { decal: { symbol: 'circle' } }, data: SANKEY_NODES, links: SANKEY_LINKS }] } },
    ] },
  { id: 'chord', note: 'chord pieces; edges coloured by their source take that node\'s decal',
    steps: [
      { option: { aria: ARIA, series: [{ type: 'chord', data: SANKEY_NODES, links: SANKEY_LINKS, lineStyle: { color: 'source' } }] } },
      { option: { series: [{ type: 'chord', itemStyle: { decal: { symbol: 'circle' } }, data: SANKEY_NODES, links: SANKEY_LINKS, lineStyle: { color: 'target' } }] } },
    ] },
  { id: 'river', note: 'a themeRiver layer takes the style of its last row',
    steps: [
      { option: { aria: ARIA, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', data: [
        ['2024/01/01', 3, 'p'], ['2024/01/02', 4, 'p'], ['2024/01/03', 2, 'p'],
        ['2024/01/01', 2, 'q'], ['2024/01/02', 1, 'q'], ['2024/01/03', 5, 'q']] }] } },
    ] },
  { id: 'gauge', note: 'a gauge\'s pointer and progress take the item\'s decal',
    steps: [
      { option: { aria: ARIA, series: [{ type: 'gauge', progress: { show: true }, data: [{ name: 'g', value: 40 }, { name: 'h', value: 70 }] }] } },
      { option: { series: [{ type: 'gauge', itemStyle: { decal: { symbol: 'circle' } }, data: [{ value: 40 }] }] } },
    ] },
  { id: 'custom', note: 'a renderItem\'s path with api.visual(\'decal\'); a decal written in renderItem; a text and a stroke-only path take none',
    steps: [
      { option: Object.assign({ aria: ARIA }, CAT, { series: [
        { type: 'custom', renderItem: '@decalBar', data: [[0, 2], [1, 4], [2, 3]] },
        { type: 'custom', renderItem: '@decalLit', data: [[3, 5]] }] }) },
      { option: Object.assign({}, CAT, { series: [
        { type: 'custom', renderItem: '@decalBar', itemStyle: { decal: { symbol: 'triangle' } },
          data: [[0, 2], { value: [1, 4], itemStyle: { decal: { symbol: 'circle' } } }, [2, 3]] }] }) },
    ] },
  { id: 'large', note: 'a large bar\'s batch path wears the series\' decal',
    steps: [
      { option: { aria: ARIA, xAxis: { type: 'category' }, yAxis: {}, series: [
        { type: 'bar', large: true, largeThreshold: 20, data: Array.from({ length: 40 }, (_, k) => 1 + (k * 7) % 11) }] } },
    ] },
  { id: 'legend-line', note: 'a line\'s own legend icon: the marker wears the decal, an empty marker too; a bar\'s default icon',
    steps: [
      { option: Object.assign({ aria: ARIA, legend: {} }, CAT, { series: [
        { type: 'line', name: 'L1', data: [1, 2, 3, 4] },
        { type: 'line', name: 'L2', symbol: 'emptyCircle', data: [2, 3, 1, 2] },
        { type: 'line', name: 'L3', symbol: 'none', data: [3, 1, 2, 4] },
        { type: 'scatter', name: 'S', symbol: 'emptyRect', data: [1, 3, 2, 1] },
        { type: 'bar', name: 'B', data: [1, 1, 2, 2] }] }) },
    ] },
  // [R2-F] MapDraw's applyOptionStyleForRegion: a region drawn with a map series' data wears
  // data.getItemVisual(dataIdx, 'decal') -- the item's own, else the series' (a name with no
  // data item too: indexOfName's -1 reads the data's visual); a geo the series draws on takes
  // the same; a geo with no map series none
  { id: 'map', note: "map series regions: an item's own decal, the series' on the rest (a region with no data item too); aria; a geo drawn with a map series' data; a geo alone",
    steps: [
      { option: { series: [{ type: 'map', map: 'decalSquares', itemStyle: { decal: { symbol: 'triangle', dashArrayX: 6 } },
        data: [{ name: 'A', value: 1, itemStyle: { decal: { symbol: 'circle' } } }, { name: 'B', value: 2 }] }] } },
      { option: { aria: ARIA, series: [{ type: 'map', map: 'decalSquares', data: [{ name: 'A', value: 1 }, { name: 'C', value: 3 }] }] } },
      { option: { geo: { map: 'decalSquares' }, series: [{ type: 'map', geoIndex: 0, itemStyle: { decal: { symbol: 'diamond' } },
        data: [{ name: 'B', value: 2, itemStyle: { decal: { symbol: 'rect', dashArrayX: 4 } } }] }] } },
      { option: { geo: { map: 'decalSquares', itemStyle: { decal: { symbol: 'circle' } } } } },
    ] },
];
// [R2-F] the map the 'map' scenario draws: three squares side by side, mirrored in
// tests/test.advchart.decalseries.pas
const DECAL_MAP = { type: 'FeatureCollection', features: ['A', 'B', 'C'].map((n, k) => ({ type: 'Feature', properties: { name: n },
  geometry: { type: 'Polygon', coordinates: [[[k * 10, 0], [k * 10 + 8, 0], [k * 10 + 8, 8], [k * 10, 8], [k * 10, 0]]] } })) };
echarts.registerMap('decalSquares', JSON.stringify(DECAL_MAP));

function runScenario(sc) {
  let chart = makeChart();
  const steps = [];
  try {
    for (let i = 0; i < sc.steps.length; i++) {
      const st = sc.steps[i];
      let rec;
      try {
        const opt = materialize(JSON.parse(JSON.stringify(st.option)));
        if (!st.merge) opt.animation = false;
        chart.setOption(opt, st.merge ? false : true);
        rec = record(chart);
      } catch (e) {
        if (e instanceof OracleError) throw e;
        rec = { error: String(e && e.message || e) };
      }
      steps.push({ i, merge: !!st.merge, option: st.option, record: rec });
      if (rec.error) {
        chart.dispose();
        chart = makeChart();
      }
    }
  } finally {
    chart.dispose();
  }
  return { id: sc.id, note: sc.note, steps };
}

// ---------- generation ----------
function generate() {
  vnodeEl = new WeakMap();
  const tiles = TILES.map(([id, d]) => runTile(id, d));
  const scenarios = SCENARIOS.map(runScenario);
  return { tiles, scenarios };
}

function checks(g) {
  const anchors = [];
  function anchor(name, cond) {
    anchors.push({ name, ok: !!cond });
    must(cond, 'anchor failed: ' + name);
  }
  const step = (id, i) => g.scenarios.find(x => x.id === id).steps[i].record;
  const ser = (r, k) => r.series[k];
  for (const sc of g.scenarios) for (const st of sc.steps) must(!st.record.error, sc.id + '#' + st.i + ' threw: ' + st.record.error);
  const polys = r => r.drawn.filter(d => d.k === 'polygon').length;
  anchor('radar: an area per item of the area series, none on the other; the points wear it either way (createSymbol)',
    polys(ser(step('radar', 0), 0)) === 2 && polys(ser(step('radar', 0), 1)) === 0 && ser(step('radar', 0), 1).drawn.length === 3);
  anchor('radar: the own areaStyle of an item shows its area', polys(ser(step('radar', 1), 0)) === 1);
  anchor('graph: nothing', ser(step('graph', 0), 0).drawn.length === 0);
  anchor('large: one batch path', ser(step('large', 0), 0).drawn.length >= 1 && ser(step('large', 0), 0).drawn[0].i === -1);
  anchor('legend-line: the empty marker wears one', step('legend-line', 0).legend[1].els.length > 0);
  anchor('custom: the text and the polyline take none', ser(step('custom', 0), 1).drawn.length === 1);
  const sb = step('sunburst', 0);
  // the children sorted by value before the walk: Q (2) asks before B (1), and
  // in a scope of its own takes the second palette decal, A's in the first
  const pOf = (r, i) => r.drawn.find(d => d.i === i).p;
  anchor('sunburst: the second sunburst starts its own scope, walking its sorted children',
    pOf(ser(sb, 1), 2) === pOf(ser(sb, 0), 1) && pOf(ser(sb, 1), 1) === pOf(ser(sb, 0), 5));
  anchor('tiles: an empty symbol is filled white and stroked 2', g.tiles[0].tile.symbols.every(s => s.empty && s.lineWidth === hex(2)));
  return { anchors };
}

let g1, g2, c1;
try {
  g1 = generate();
  c1 = checks(g1);
  g2 = generate();
} catch (e) {
  console.log(e instanceof OracleError ? 'SELF-CHECK FAILED: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
function assemble(g, c) {
  return JSON.stringify({
    source: 'decal-series.js: ECharts 6.1 dist, SSR svg, ' + W + ' x ' + H,
    W, H,
    notes: [
      'tiles: the decal symbols decal-aria.js left out -- empty, path://, image:// -- as the SVG painter received them',
      'scenarios: every displayable whose decal element fills, by series / dataType / dataIndex, and the legend icons',
    ],
    tiles: g.tiles, scenarios: g.scenarios, anchors: c.anchors,
  }, null, 1);
}
const json1 = assemble(g1, c1);
const json2 = assemble(g2, c1);
const deterministic = json1 === json2;
const nSteps = g1.scenarios.reduce((n, s) => n + s.steps.length, 0);
console.log(g1.tiles.length + ' tiles, ' + g1.scenarios.length + ' scenarios (' + nSteps + ' steps); '
  + c1.anchors.length + ' anchors; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (!deterministic || json1.indexOf('\\u0000') >= 0) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
JSON.parse(json1);
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
