/*
Upstream's own answers for fix batch R2-F (spec section 223): A TEXT'S
DASHED STROKE AND ITS PHASE. zrender's Text hands a stroking TSpan its
style's lineDash and `lineDashOffset || 0` (Text.ts _updatePlainTexts; a rich
token's lineDash is retrieve2(the token's, the block's), the phase always the
block's), and brushText sets ctx.setLineDash(normalizeLineDash(lineDash,
lineWidth)) and ctx.lineDashOffset before strokeText. A graphic text writes
lineDash and lineDashOffset in its style as they are; a label writes
textBorderType and textBorderDashOffset (labelStyle.ts: the label's, else the
global textStyle's) -- label-halo.js holds those.

Three parts:
  static  graphic texts (plain and rich) and their TSpans as zrender holds
          them after a paint: text, stroke, lineWidth, the lineDash as
          written, the lineDashOffset, the pattern normalizeLineDash makes.
  anim    the gallery's graphic-stroke-animation (its option verbatim from
          examples/advchart/gallery): a looping keyframe animation of the
          text's style -- lineDash [0, 200] to [200, 0] and lineDashOffset 0
          to 200 by 70 %, then the fill -- sampled on the animation clock
          (the clock of keyframe-animation.js: the global Date replaced
          before the dist loads, chart._ssr false, env.node off), each
          sample the Text's style values and its TSpan's.
  series  [R2-I2] a series' own stroke dash and its phase: lineStyle.type /
          dashOffset (getLineStyle's lineDash / lineDashOffset) and
          itemStyle.borderType / borderDashOffset (getItemStyle's), the
          item's own over the series' key by key -- on bars, a line, scatter
          symbols, radar rings, graph edges, lines, parallel lines, tree
          edges and map regions; and a text box's border (Text.ts
          _renderBackground: rectStyle.lineDash = style.borderDash,
          lineDashOffset = style.borderDashOffset || 0; labelStyle.ts writes a
          label's borderType as borderDash): each element's lineWidth, the
          lineDash as written, the lineDashOffset, the pattern
          normalizeLineDash makes against the width.

  node tools/advchart-oracle/text-dash.js

writes tests/fixtures/advchart-text-dash.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().

Numbers are the 16 lowercase hex digits of the IEEE double (big-endian);
an array of numbers is an array of them; strings plain.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-text-dash.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery', 'graphic-stroke-animation.json');

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
function valRec(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(valRec);
  return JSON.stringify(v);
}

// zrender canvas/dashStyle.ts, transcribed
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : Array.isArray(lineType) ? lineType : null;
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
function gInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'isNew' in el[k]) return el[k];
  }
  return null;
}
function graphicTexts(chart) {
  const view = (chart._componentsViews || []).find(v => v && v.type === 'graphic');
  must(view, 'no graphic view');
  const out = [];
  const walk = g => g.childrenRef().forEach(el => {
    if (el.type === 'text') out.push({ id: String(gInner(el).id), el });
    if (el.isGroup) walk(el);
  });
  walk(view.group);
  return out;
}
function spanOf(s) {
  const lw = s.lineWidth;
  const pat = normalizeLineDash(s.lineDash, lw);
  return {
    text: s.text == null ? null : String(s.text),
    stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: lw == null ? null : hex(lw),
    lineDash: s.lineDash == null ? null : valRec(s.lineDash),
    lineDashOffset: s.lineDashOffset == null ? null : hex(s.lineDashOffset),
    pattern: pat == null ? null : pat.map(hex),
  };
}
function spansOf(el) {
  const kids = el.childrenRef ? el.childrenRef() : [];
  return kids.filter(k => k.type === 'tspan').map(k => spanOf(k.style));
}

// ---------- static: graphic texts ----------
const g = (id, style) => ({ type: 'text', id, x: 40, y: 40, style: Object.assign({ fontSize: 20 }, style) });
const STATIC = [
  { id: 'plain', note: 'a graphic text with lineDash [4, 2] and lineDashOffset 3',
    option: { graphic: [g('t', { text: 'Abc', stroke: '#ff0000', lineWidth: 2, lineDash: [4, 2], lineDashOffset: 3 })] } },
  { id: 'words', note: "lineDash 'dashed' and 'dotted' on a graphic text (normalizeLineDash against lineWidth 3), no offset",
    option: { graphic: [g('a', { text: 'Ab', stroke: '#ff0000', lineWidth: 3, lineDash: 'dashed' }),
      g('b', { text: 'Cd', stroke: '#00ff00', lineWidth: 3, lineDash: 'dotted', y: 80 })] } },
  { id: 'zeros', note: 'lineDash [0, 200], the gallery start: a dash of no length',
    option: { graphic: [g('z', { text: 'Ab', stroke: '#000', lineWidth: 1, lineDash: [0, 200], lineDashOffset: 0 })] } },
  { id: 'no-stroke', note: 'lineDash with no stroke: the TSpan has no lineDash (Text.ts sets it only with a stroke)',
    option: { graphic: [g('n', { text: 'Ab', lineDash: [4, 2], lineDashOffset: 5 })] } },
  { id: 'negative', note: 'a negative lineDashOffset', option: { graphic: [g('m', { text: 'Ab', stroke: '#000', lineWidth: 2, lineDash: [6, 3], lineDashOffset: -4 })] } },
  { id: 'rich', note: "a rich graphic text: the block lineDash [5, 1] and offset 2, token a's own lineDash [1, 1] and offset 9 (the phase stays the block's), token b nothing",
    option: { graphic: [g('r', { text: '{a|Aa}{b|Bb}', stroke: '#0000ff', lineWidth: 2, lineDash: [5, 1], lineDashOffset: 2,
      rich: { a: { lineDash: [1, 1], lineDashOffset: 9 }, b: {} } })] } },
];

function runStatic(c) {
  const chart = mk(400, 300);
  try {
    chart.setOption(Object.assign({ animation: false }, c.option));
    chart.renderToSVGString();
    refresh(chart);
    const texts = graphicTexts(chart).map(t => ({ id: t.id, spans: spansOf(t.el) }));
    return { id: c.id, note: c.note, option: c.option, texts };
  } finally {
    chart.dispose();
  }
}

// ---------- anim: the gallery's stroke animation ----------
const ANIM_TIMES = [0, 1, 300, 1050, 1800, 2099, 2100, 2250, 2399, 2400, 2700, 2999, 3000, 3001, 3300, 4050];
function runAnim() {
  const option = JSON.parse(fs.readFileSync(GALLERY, 'utf8'));
  const chart = mk(800, 500);
  try {
    chart.setOption(option);
    const z = chart.getZr();
    const samples = ANIM_TIMES.map(t => {
      NOW = T0 + t;
      z.animation.update();
      refresh(chart);
      const ts = graphicTexts(chart);
      must(ts.length === 1, 'one text');
      const el = ts[0].el;
      return {
        t,
        style: { lineDash: valRec(el.style.lineDash), lineDashOffset: valRec(el.style.lineDashOffset),
          fill: valRec(el.style.fill), stroke: valRec(el.style.stroke) },
        spans: spansOf(el),
      };
    });
    return { gallery: 'graphic-stroke-animation', W: 800, H: 500, samples };
  } finally {
    chart.dispose();
  }
}

// ---------- series: a series' stroke dash and phase [R2-I2] ----------
function strokeRec(role, s, i, st, extra) {
  const lw = st.lineWidth;
  const pat = normalizeLineDash(st.lineDash, lw);
  return Object.assign({ role, s, i,
    lineWidth: lw == null ? null : hex(lw),
    lineDash: st.lineDash == null ? null : valRec(st.lineDash),
    lineDashOffset: st.lineDashOffset == null ? null : hex(st.lineDashOffset),
    pattern: pat == null ? null : pat.map(hex) }, extra || {});
}
const views = chart => chart._chartsViews || [];
function eachSeriesOf(chart, type, fn) {
  chart.getModel().eachSeries(sm => { if (sm.subType === type) fn(sm, sm.getData(), chart.getViewOfSeriesModel(sm)); });
}
// a label's (or a graphic text's) box: the Rect children of its Text, the
// block's first, then each token's
function boxRecs(role, s, i, t) {
  const out = [];
  (t.childrenRef ? t.childrenRef() : []).forEach((k, n) => {
    if (k.type === 'rect' && k.style.stroke) out.push(strokeRec(role, s, i, k.style, { n: out.length }));
  });
  return out;
}
const PICK = {
  bar: chart => { const r = []; eachSeriesOf(chart, 'bar', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(strokeRec('bar', sm.seriesIndex, i, el.style)); })); return r; },
  line: chart => { const r = []; eachSeriesOf(chart, 'line', (sm, d, v) => { if (v._polyline) r.push(strokeRec('line', sm.seriesIndex, -1, v._polyline.style)); }); return r; },
  scatter: chart => { const r = []; eachSeriesOf(chart, 'scatter', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(strokeRec('symbol', sm.seriesIndex, i, el.childAt(0).style)); })); return r; },
  radar: chart => { const r = []; eachSeriesOf(chart, 'radar', (sm, d) => d.each(i => { const g = d.getItemGraphicEl(i); if (g) r.push(strokeRec('radar', sm.seriesIndex, i, g.childAt(0).style)); })); return r; },
  graph: chart => { const r = []; eachSeriesOf(chart, 'graph', sm => { const ed = sm.getEdgeData(); ed.each(i => { const el = ed.getItemGraphicEl(i); if (el) r.push(strokeRec('edge', sm.seriesIndex, i, el.childOfName('line').style)); }); }); return r; },
  lines: chart => { const r = []; eachSeriesOf(chart, 'lines', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(strokeRec('lines', sm.seriesIndex, i, el.childOfName('line').style)); })); return r; },
  parallel: chart => { const r = []; eachSeriesOf(chart, 'parallel', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(strokeRec('parallel', sm.seriesIndex, i, el.style)); })); return r; },
  tree: chart => { const r = []; eachSeriesOf(chart, 'tree', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el && el.__edge) r.push(strokeRec('treeEdge', sm.seriesIndex, i, el.__edge.style)); })); return r; },
  map: chart => {
    const r = [];
    eachSeriesOf(chart, 'map', (sm, d, v) => {
      const regions = [];
      v.group.traverse(el => { if (el.type === 'compound' || el.type === 'polygon') regions.push(el); });
      regions.forEach((el, n) => { if (el.style && el.style.stroke) r.push(strokeRec('region', sm.seriesIndex, n, el.style)); });
    });
    return r;
  },
  barLabelBox: chart => { const r = []; eachSeriesOf(chart, 'bar', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); const t = el && el.getTextContent(); if (t) r.push(...boxRecs('labelBox', sm.seriesIndex, i, t)); })); return r; },
  graphicBox: chart => graphicTexts(chart).reduce((a, t) => a.concat(boxRecs('graphicBox', -1, t.id, t.el)), []),
  // [R2-I3] a graph's node symbols (the Symbol's path), with the pen's colour
  graphNode: chart => { const r = []; eachSeriesOf(chart, 'graph', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(strokeRec('node', sm.seriesIndex, i, el.childAt(0).style, { stroke: el.childAt(0).style.stroke || null })); })); return r; },
  // [R2-I3] bars with the pen's colour
  // [R2-I4] a bar's pen whatever it is: a colour string, or a gradient as
  // its type, coordinates, global and stops
  barPen: chart => { const r = []; eachSeriesOf(chart, 'bar', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (!el) return;
    const s = el.style.stroke;
    const extra = s && typeof s === 'object' && s.colorStops
      ? { strokeGrad: { type: s.type, x: s.x, y: s.y, x2: s.x2 == null ? null : s.x2, y2: s.y2 == null ? null : s.y2, r: s.r == null ? null : s.r,
        global: !!s.global, stops: s.colorStops.map(c => [c.offset, c.color]) } }
      : { stroke: s || null };
    r.push(strokeRec('bar', sm.seriesIndex, i, el.style, extra)); })); return r; },
  barStroke: chart => { const r = []; eachSeriesOf(chart, 'bar', (sm, d) => d.each(i => { const el = d.getItemGraphicEl(i); if (el) r.push(strokeRec('bar', sm.seriesIndex, i, el.style, { stroke: el.style.stroke || null })); })); return r; },
  // [R2-I3] an SVG map's own stroked shapes, in the geo view's order
  svgGeo: chart => {
    const r = [];
    for (const v of chart._componentsViews) {
      if (!v || v.type !== 'geo') continue;
      v.group.traverse(el => { if (!el.isGroup && el.type !== 'tspan' && el.type !== 'text' && el.style && el.style.stroke) { const st = Object.create(el.style); if (el.style.lineDashOffset != null) st.lineDashOffset = Number(el.style.lineDashOffset); r.push(strokeRec('svg', -1, r.length, st, { raw: el.style.lineDashOffset == null ? null : String(el.style.lineDashOffset) })); } });
    }
    return r;
  },
};
const CAT = { type: 'category', data: ['a', 'b', 'c'] };
const VAL = { type: 'value' };
const SQ = [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]];
const SQ2 = [[[10, 0], [20, 0], [20, 10], [10, 10], [10, 0]]];
const MAPJSON = { type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: SQ } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: SQ2 } }] };
const SERIES = [
  { id: 'bar', note: 'bars: itemStyle borderType [4, 2], borderDashOffset 3; the second item\'s own borderDashOffset 7 over it',
    pick: 'bar', option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 2, borderType: [4, 2], borderDashOffset: 3 },
      data: [5, { value: 7, itemStyle: { borderDashOffset: 7 } }, 3] }] } },
  { id: 'line', note: "a line: lineStyle type 'dashed' (against width 3), dashOffset 5",
    pick: 'line', option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'line', showSymbol: false, lineStyle: { width: 3, type: 'dashed', dashOffset: 5 }, data: [5, 7, 3] }] } },
  { id: 'scatter', note: "scatter symbols: borderType 'dotted' (width 3), borderDashOffset -2",
    pick: 'scatter', option: { xAxis: VAL, yAxis: VAL, series: [{ type: 'scatter', symbolSize: 20, itemStyle: { borderColor: '#000', borderWidth: 3, borderType: 'dotted', borderDashOffset: -2 }, data: [[1, 2], [3, 4]] }] } },
  { id: 'radar', note: 'radar rings: the series lineStyle [6, 3] offset 2; an item\'s own dashOffset 7; an item\'s own type dotted (the series\' offset)',
    pick: 'radar', option: { radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
      series: [{ type: 'radar', lineStyle: { type: [6, 3], dashOffset: 2 }, data: [{ value: [5, 6, 7] }, { value: [3, 4, 5], lineStyle: { dashOffset: 7 } },
        { value: [8, 2, 4], lineStyle: { type: 'dotted', width: 2 } }] }] } },
  { id: 'graph', note: "graph edges: the series lineStyle 'dashed' offset 4; an edge's own dashOffset 9; an edge's own type [2, 2]",
    pick: 'graph', option: { series: [{ type: 'graph', layout: 'none', lineStyle: { type: 'dashed', dashOffset: 4, width: 2 },
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 50, y: 80 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c', lineStyle: { dashOffset: 9 } }, { source: 'c', target: 'a', lineStyle: { type: [2, 2] } }] }] } },
  { id: 'lines', note: 'lines: the series lineStyle [5, 5] offset 1; an item\'s own dashOffset 6',
    pick: 'lines', option: { xAxis: VAL, yAxis: VAL, series: [{ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: { type: [5, 5], dashOffset: 1, width: 2 },
      data: [{ coords: [[0, 0], [10, 10]] }, { coords: [[0, 10], [10, 0]], lineStyle: { dashOffset: 6 } }] }] } },
  { id: 'parallel', note: "parallel lines: the series lineStyle 'dashed' offset 3; an item's own dashOffset 8",
    pick: 'parallel', option: { parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }], series: [{ type: 'parallel', lineStyle: { type: 'dashed', dashOffset: 3, width: 2 },
      data: [[1, 2, 3], { value: [3, 2, 1], lineStyle: { dashOffset: 8 } }] }] } },
  { id: 'tree', note: "tree edges: the series lineStyle 'dashed' offset 2, a node's own dashOffset 6",
    pick: 'tree', option: { series: [{ type: 'tree', lineStyle: { type: 'dashed', dashOffset: 2, width: 2 }, initialTreeDepth: -1,
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b', lineStyle: { dashOffset: 6 } }] }] }] } },
  { id: 'map', note: "map regions: itemStyle borderType 'dashed' (width 2), borderDashOffset 3; region B's own borderDashOffset 10",
    pick: 'map', option: { series: [{ type: 'map', map: 'r2i2dash', itemStyle: { borderColor: '#000', borderWidth: 2, borderType: 'dashed', borderDashOffset: 3 },
      data: [{ name: 'A', value: 1 }, { name: 'B', value: 2, itemStyle: { borderDashOffset: 10 } }] }] } },
  { id: 'labelBox', note: "a bar label's box: borderType 'dashed' with a background (the border drawn first at twice the width), borderDashOffset 2; a rich token's own borderType [3, 1] and borderDashOffset 5 (no background)",
    pick: 'barLabelBox', option: { xAxis: CAT, yAxis: VAL, series: [{ type: 'bar', label: { show: true, position: 'top', backgroundColor: '#eee', borderColor: '#000', borderWidth: 1,
      borderType: 'dashed', borderDashOffset: 2, padding: 4, formatter: ['{a|x} y'].join(''), rich: { a: { borderColor: '#f00', borderWidth: 2, borderType: [3, 1], borderDashOffset: 5 } } },
      data: [5, 7] }] } },
  { id: 'graphicBox', note: 'a graphic text\'s box: style.borderDash [6, 2] and borderDashOffset 4 as written; a negative offset on another',
    pick: 'graphicBox', option: { graphic: [g('gb', { text: 'Box', borderColor: '#000', borderWidth: 2, borderDash: [6, 2], borderDashOffset: 4, padding: 3 }),
      g('gn', { text: 'Neg', y: 80, borderColor: '#00f', borderWidth: 1, borderDash: 'dotted', borderDashOffset: -3, backgroundColor: '#ff0' })] } },
  // [R2-I3]
  { id: 'graphNode', note: "[R2-I3] graph nodes: the series' border #333333 at 2, dashed, at 3; a its own borderDashOffset 7; b in category k by NAME ([2, 1] at 1); c an emptyCircle (its colour at 2, the series' dash against 2); d its own borderType 'solid'; e its own borderColor and width 5",
    pick: 'graphNode', option: { color: ['#5070dd'], series: [{ type: 'graph', layout: 'none', symbolSize: 20, itemStyle: { borderColor: '#333333', borderWidth: 2, borderType: 'dashed', borderDashOffset: 3 },
      categories: [{ name: 'k', itemStyle: { borderType: [2, 1], borderDashOffset: 1 } }],
      data: [{ name: 'a', x: 0, y: 0, itemStyle: { borderDashOffset: 7 } }, { name: 'b', x: 100, y: 0, category: 'k' }, { name: 'c', x: 50, y: 80, symbol: 'emptyCircle' },
        { name: 'd', x: 150, y: 80, itemStyle: { borderType: 'solid' } }, { name: 'e', x: 200, y: 0, itemStyle: { borderColor: '#ff0000', borderWidth: 5 } }], links: [] }] } },
  { id: 'barItem', note: "[R2-I3] bars: the series' border #000 at 2, dashed; item 0 its own borderType [6, 2]; item 1 its own borderColor #ff0000 and width 4 (the dash against 4); item 2 its own 'solid'; item 3 its own borderType 'dotted' and borderDashOffset 5",
    pick: 'barStroke', option: { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: VAL, series: [{ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 2, borderType: 'dashed' },
      data: [{ value: 5, itemStyle: { borderType: [6, 2] } }, { value: 7, itemStyle: { borderColor: '#ff0000', borderWidth: 4 } }, { value: 3, itemStyle: { borderType: 'solid' } },
        { value: 4, itemStyle: { borderType: 'dotted', borderDashOffset: 5 } }] }] } },
  { id: 'svgGeo', note: "[R2-I3] an SVG map's own stroke-dashoffset (parseAttributes keeps the string, the canvas reads a number): a rect [4 2] at 3, a path [5 5] at -2, a circle whose group says 6; the geo at the SVG's own size (an unnamed shape has no strokeNoScale)",
    pick: 'svgGeo', option: { geo: { map: 'r2i3svg', left: 0, top: 0, width: 100, height: 100 } } },
  // [R2-I4]
  { id: 'barItemLong', note: "[R2-I4] bars: the series' border #000 at 2, dashed; item 0 its own borderType of six numbers, item 1 of five; item 2 its own borderColor a linear gradient; item 3 a radial one at width 3 with its own dotted -- the store kept neither",
    pick: 'barPen', option: { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: VAL, series: [{ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 2, borderType: 'dashed' },
      data: [{ value: 5, itemStyle: { borderType: [6, 2, 3, 1, 2, 4] } }, { value: 7, itemStyle: { borderType: [5, 1, 1, 1, 1] } },
        { value: 3, itemStyle: { borderColor: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } } },
        { value: 4, itemStyle: { borderWidth: 3, borderType: 'dotted', borderColor: { type: 'radial', x: 0.5, y: 0.5, r: 0.5, colorStops: [{ offset: 0, color: '#00ff00' }, { offset: 1, color: '#ff00ff' }] } } }] }] } },
];
// [R2-I3] an SVG map whose shapes carry their own dash and phase
const SVGMAP = '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
  + '<rect x="0" y="0" width="40" height="40" fill="#cccccc" stroke="#000000" stroke-width="2" stroke-dasharray="4 2" stroke-dashoffset="3"/>'
  + '<path d="M50 0 L90 0 L90 40 Z" fill="#cccccc" stroke="#000000" stroke-width="1" stroke-dasharray="5,5" stroke-dashoffset="-2"/>'
  + '<g stroke-dashoffset="6"><circle cx="20" cy="70" r="15" fill="none" stroke="#0000ff" stroke-width="1" stroke-dasharray="3 3"/></g>'
  + '</svg>';
// [R2-I3] node has no DOMParser: jsdom's (as geo-svg.js), set only when the
// SVG map is registered
let svgDomReady = false;
function svgDom() {
  if (svgDomReady) return;
  const { JSDOM } = require(process.env.JSDOM_PATH || 'D:/Projects/xterm.js/node_modules/jsdom');
  global.DOMParser = new JSDOM('').window.DOMParser;
  svgDomReady = true;
}
function runSeries(c) {
  echarts.registerMap('r2i2dash', MAPJSON);
  svgDom();
  echarts.registerMap('r2i3svg', { svg: SVGMAP });
  const chart = mk(400, 300);
  try {
    chart.setOption(Object.assign({ animation: false }, c.option));
    chart.renderToSVGString();
    refresh(chart);
    return { id: c.id, note: c.note, option: c.option, items: PICK[c.pick](chart) };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
    clock: { T0 },
    static: STATIC.map(runStatic),
    anim: runAnim(),
  };
  out.series = SERIES.map(runSeries);
  out.maps = [{ name: 'r2i2dash', text: JSON.stringify(MAPJSON) }, { name: 'r2i3svg', text: SVGMAP }];
  const st = id => out.static.find(c => c.id === id);
  const at = t => out.anim.samples.find(s => s.t === t);
  const arr = h => (h == null ? null : h.map(num));
  out.guards = [
    { name: 'plain: [4, 2] and 3', ok: JSON.stringify(arr(st('plain').texts[0].spans[0].pattern)) === '[4,2]'
      && num(st('plain').texts[0].spans[0].lineDashOffset) === 3 },
    { name: "words: 'dashed' against 3 is [12, 6]", ok: JSON.stringify(arr(st('words').texts[0].spans[0].pattern)) === '[12,6]' },
    { name: 'no stroke: no lineDash', ok: st('no-stroke').texts[0].spans[0].lineDash === null },
    { name: "rich: token a's own dash, the block's phase", ok: st('rich').texts[0].spans.some(s => s.text === 'Aa'
      && JSON.stringify(arr(s.pattern)) === '[1,1]' && num(s.lineDashOffset) === 2) },
    { name: 'anim: the dash grows', ok: num(at(1050).spans[0].pattern[0]) > 50 && num(at(1050).spans[0].pattern[0]) < 150 },
    { name: 'anim: the phase moves', ok: num(at(1050).spans[0].lineDashOffset) > 0 && num(at(2100).spans[0].lineDashOffset) === 200 },
    { name: 'anim: it loops', ok: num(at(3001).spans[0].lineDashOffset) < 1 },
  ];
  const sr = id => out.series.find(c => c.id === id).items;
  const off = r => (r.lineDashOffset == null ? null : num(r.lineDashOffset));
  out.guards.push(
    { name: 'series bar: 3, the item\'s 7', ok: sr('bar').length === 3 && off(sr('bar')[0]) === 3 && off(sr('bar')[1]) === 7 },
    { name: 'series line: dashed [12, 6] at 5', ok: JSON.stringify(sr('line')[0].pattern.map(num)) === '[12,6]' && off(sr('line')[0]) === 5 },
    { name: 'series radar: the item\'s 7, the dotted item the series\' 2', ok: off(sr('radar')[1]) === 7 && off(sr('radar')[2]) === 2
      && JSON.stringify(sr('radar')[2].pattern.map(num)) === '[2]' },
    { name: 'series graph: 4, 9, 4 with [2, 2]', ok: sr('graph').map(off).join() === '4,9,4' },
    { name: 'series lines / parallel / tree / map carry the offsets', ok: sr('lines').map(off).join() === '1,6'
      && sr('parallel').map(off).join() === '3,8' && sr('tree').map(off).join() === '2,6'
      && sr('map').map(off).sort().join() === '10,3' },
    { name: 'labelBox: the block\'s dashed against twice the width, at 2; the token\'s [3, 1] at 5', ok: sr('labelBox').some(r => off(r) === 2
      && JSON.stringify(r.pattern.map(num)) === '[8,4]') && sr('labelBox').some(r => off(r) === 5 && JSON.stringify(r.pattern.map(num)) === '[3,1]') },
    { name: 'graphicBox: [6, 2] at 4, dotted at -3', ok: sr('graphicBox').map(off).join() === '4,-3' },
    // [R2-I3]
    { name: 'graphNode: every node has a pen; the empty one at 2 in its colour; d solid', ok: sr('graphNode').length === 5
      && sr('graphNode').map(off).join() === '7,1,3,3,3' && num(sr('graphNode')[2].lineWidth) === 2 && sr('graphNode')[3].pattern === null
      && sr('graphNode')[4].stroke === '#ff0000' },
    { name: 'barItem: the own borderType of each item borderType and the width it goes against', ok: JSON.stringify(sr('barItem')[0].pattern.map(num)) === '[6,2]'
      && JSON.stringify(sr('barItem')[1].pattern.map(num)) === '[16,8]' && sr('barItem')[2].pattern === null
      && JSON.stringify(sr('barItem')[3].pattern.map(num)) === '[2]' && off(sr('barItem')[3]) === 5 },
    { name: 'svgGeo: the strings 3, -2 and 6', ok: sr('svgGeo').map(r => r.raw).join() === '3,-2,6' },
    // [R2-I4]
    { name: 'barItemLong: six and five numbers as written, a linear and a radial pen', ok: JSON.stringify(sr('barItemLong')[0].pattern.map(num)) === '[6,2,3,1,2,4]'
      && JSON.stringify(sr('barItemLong')[1].pattern.map(num)) === '[5,1,1,1,1]' && sr('barItemLong')[2].strokeGrad.type === 'linear'
      && sr('barItemLong')[3].strokeGrad.type === 'radial' && JSON.stringify(sr('barItemLong')[3].pattern.map(num)) === '[3]' },
  );
  return out;
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
out1.static.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.texts.map(t => t.spans.map(s => [s.text, s.lineDash, s.pattern && s.pattern.map(num), s.lineDashOffset && num(s.lineDashOffset)])))));
out1.series.forEach(c => console.log('series ' + c.id + ': ' + JSON.stringify(c.items.map(r => [r.role, r.i, r.lineDash, r.pattern && r.pattern.map(num), r.lineDashOffset && num(r.lineDashOffset)]))));
out1.anim.samples.forEach(s => console.log('t ' + s.t + ': ' + JSON.stringify(s.spans.map(q => [q.pattern && q.pattern.map(num), q.lineDashOffset && num(q.lineDashOffset)])) + ' fill ' + s.style.fill));
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
