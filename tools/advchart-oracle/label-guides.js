// Upstream's own answers for LABEL LINES BEYOND label-line.js: the pie's and
// the funnel's normal-state labelLine.lineStyle (colour, width, type, cap,
// join, dashOffset, miterLimit, opacity) and the line a state alone shows
// (labelLine.show false, emphasis.labelLine.show true); and the lines
// LabelManager._updateLabelLine builds for every other series whose
// elements carry a label and a dataIndex -- heatmap cells, pictorial bars,
// graph and tree symbols, sunburst sectors, sankey nodes, polar bars and a
// calendar's scatter symbols (label/LabelManager.ts processLabelsOverall,
// label/labelGuideHelper.ts setLabelLineStyle / updateLabelLinePoints).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer). The dist is loaded
// through Module._compile with one read-only addition (it must match exactly
// once): inside updateLabelLinePoints, the host's type, path data and
// computed transform, the label's rect as read and its transform, and the
// points before and after limitTurnAngle (label-line.js's hook). After
// setOption the chart is rendered once to an SVG string and every label line
// is read off the live elements; cases with `hover` dispatch each payload,
// run a frame and read the lines again.
//
//   node tools/advchart-oracle/label-guides.js
//
// writes tests/fixtures/advchart-label-guides.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as label-line.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian
//   pts      [[x, y] ...] in hex
//   mat      [m0 .. m5] in hex, or null
//   data     a PathProxy's data array in hex, command codes included
//   style    {key: value}: a number in hex, a string as is, an array of
//            numbers as hex, null for null (only the keys the element has)
//
// cases[]  id, note, W, H, option (as fed)
//   lines[]   every updateLabelLinePoints call: s, d, host (type), path
//             (data | null), targetM (mat), raw ([x, y, w, h] hex: the
//             label's rect as read), labelM (mat), len (hex), pre, post
//   guides[]  every label line after the render, series in order, each
//             series' group in traverse order: s, d, dataType, host (the
//             host element's type), ignore, points, smooth (hex), curved
//             (buildLabelLinePath drew a cubic), style (the normal style),
//             z2, hostZ2, hostFill / hostStroke (the host's style.fill /
//             stroke as strings, or null), states {emphasis, blur, select:
//             {ignore, smooth, style} | null}
//   hover[]   {payload, guides [{s, d, ignore, smooth, points, style}]}
//   (points are where the line is drawn: through its own transform -- a
//   state's x / y)
//
// Self-checks (any failure: nothing is written, exit 1): the patch matches
// once; anchors; two generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');
const Module = require('module');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-guides.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the dist, patched ----------
let SRC = fs.readFileSync(DIST, 'utf8');
function patch(re, fn, what) {
  const hits = SRC.match(re);
  must(hits && hits.length === 1, what + ' is not where it was (' + (hits ? hits.length : 0) + ' matches)');
  SRC = SRC.replace(re, fn);
}
patch(/var labelRect = label\.getBoundingRect\(\)\.clone\(\);\n(\s*)labelRect\.applyTransform\(label\.getComputedTransform\(\)\);/g,
  (m, sp) => 'var labelRect = label.getBoundingRect().clone();\n' + sp + 'var __lgRaw = labelRect.clone();\n'
    + sp + 'labelRect.applyTransform(label.getComputedTransform());', 'the label rect');
patch(/limitTurnAngle\(points, labelLineModel\.get\('minTurnAngle'\)\);\n(\s*)labelLine\.setShape\(\{/g,
  (m, sp) => 'globalThis.__lgHook && globalThis.__lgHook(\'pre\', target, label, __lgRaw, targetTransform, points, len);\n'
    + sp + 'limitTurnAngle(points, labelLineModel.get(\'minTurnAngle\'));\n'
    + sp + 'globalThis.__lgHook && globalThis.__lgHook(\'post\', target, label, __lgRaw, targetTransform, points, len);\n'
    + sp + 'labelLine.setShape({', 'the limitTurnAngle call');
patch(/\n(\s*)function buildLabelLinePath\(path, shape\) \{/g,
  (m, sp) => '\n' + sp + 'globalThis.__lgBuild = function (s) { return buildLabelLinePath; };' + m, 'buildLabelLinePath');
const echarts = (() => {
  const mod = new Module(DIST, module);
  mod.filename = DIST;
  mod.paths = Module._nodeModulePaths(path.dirname(DIST));
  mod._compile(SRC, DIST);
  return mod.exports;
})();
must(typeof echarts.init === 'function', 'the patched dist does not load');
const buildLabelLinePath = globalThis.__lgBuild();
must(typeof buildLabelLinePath === 'function', 'buildLabelLinePath is not exposed');

// ---------- the seeded Math.random (the port's xorshift32) ----------
const SEED = 2463534242;
let rngState = SEED;
function xorshift() {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
}
Math.random = xorshift;

// ---------- number records ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const rect4 = r => [hex(r.x), hex(r.y), hex(r.width), hex(r.height)];
const mat6 = m => (m ? Array.from(m).map(hex) : null);
const pts3 = p => (p ? p.map(q => [hex(q[0]), hex(q[1])]) : null);
const dataHex = d => Array.from(d).map(hex);
const clone = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
const STYLE_KEYS = ['stroke', 'lineWidth', 'opacity', 'lineDash', 'lineDashOffset', 'lineCap', 'lineJoin', 'miterLimit',
  'strokeOpacity', 'fill'];
function styleRec(st) {
  if (!st) return null;
  const r = {};
  for (const k of STYLE_KEYS) {
    if (!(k in st) || st[k] === undefined) continue;
    const v = st[k];
    if (v === null) r[k] = null;
    else if (typeof v === 'number') r[k] = hex(v);
    else if (Array.isArray(v)) r[k] = v.map(x => (typeof x === 'number' ? hex(x) : x));
    else r[k] = String(v);
  }
  return r;
}

// ECData lives in a makeInner store ('__ec_inner_<n>') on every element
let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object'
        && ('dataIndex' in v || 'componentMainType' in v) && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}

// ---------- what the hook keeps ----------
let capture = null;
let pendingLine = null;
globalThis.__lgHook = function (phase, target, label, rawRect, targetTransform, points, len) {
  if (!capture) return;
  if (phase === 'pre') {
    const d = ecData(target);
    pendingLine = {
      s: d ? d.seriesIndex : null,
      d: d && d.dataIndex != null ? d.dataIndex : null,
      host: target.type,
      path: target.path ? dataHex(target.path.data) : null,
      targetM: mat6(targetTransform),
      raw: rect4(rawRect),
      labelM: mat6(label.transform),
      len: hex(+len),
      pre: pts3(points),
    };
    return;
  }
  must(pendingLine, 'a post hook without its pre');
  pendingLine.post = pts3(points);
  capture.lines.push(pendingLine);
  pendingLine = null;
};

// the points where they are drawn: a state moves the line by its x / y
// (a pie's selected slice), not by its shape
function placed(g) {
  g.updateTransform();
  const m = g.transform;
  if (!m) return g.shape.points;
  return g.shape.points.map(q => [m[0] * q[0] + m[2] * q[1] + m[4], m[1] * q[0] + m[3] * q[1] + m[5]]);
}
function curved(shape) {
  let c = false;
  const rec = { moveTo: () => {}, lineTo: () => {}, bezierCurveTo: () => { c = true; } };
  buildLabelLinePath(rec, shape);
  return c;
}

// ---------- the cases ----------
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
const pieData = (n, f) => Array.from({ length: n }, (_, i) => ({ name: 'p' + i, value: f(i) }));
const crowd = n => pieData(n, i => (i * 7) % 11 + 1);
const hov = (idx, s) => idx.map(i => ({ type: 'highlight', seriesIndex: s || 0, dataIndex: i }));
const sel = (idx, s) => idx.map(i => ({ type: 'select', seriesIndex: s || 0, dataIndex: i }));
function pie(seriesExtra, extra) {
  return Object.assign({
    animation: false,
    series: [Object.assign({ type: 'pie', radius: '45%', data: crowd(10) }, seriesExtra)],
  }, extra || {});
}
function funnel(seriesExtra) {
  return {
    animation: false,
    series: [Object.assign({ type: 'funnel', left: '25%', width: '40%', label: { position: 'right' },
      data: pieData(6, i => 100 - i * 15) }, seriesExtra)],
  };
}
const LS_FULL = { color: '#2a6f97', width: 2.5, type: 'dashed', cap: 'round', join: 'bevel', dashOffset: 3, miterLimit: 4, opacity: 0.6 };
const ll = o => Object.assign({ show: true }, o);
// a fan of moves, so the lines have somewhere to go
const FAN = { dx: 26, dy: -22 };
function heat(seriesExtra) {
  const data = [];
  for (let i = 0; i < 5; i++) for (let j = 0; j < 4; j++) data.push([i, j, (i * 7 + j * 3) % 10]);
  return {
    animation: false,
    xAxis: { type: 'category', data: cats(5) },
    yAxis: { type: 'category', data: cats(4) },
    visualMap: { min: 0, max: 10, show: false },
    series: [Object.assign({ type: 'heatmap', label: { show: true }, labelLine: ll(), labelLayout: FAN, data }, seriesExtra)],
  };
}
function pictorial(seriesExtra) {
  return {
    animation: false,
    xAxis: { type: 'category', data: cats(6) },
    yAxis: {},
    series: [Object.assign({ type: 'pictorialBar', symbol: 'rect', label: { show: true, position: 'top' }, labelLine: ll(),
      labelLayout: { dx: 20, dy: -30 }, data: [12, 30, 25, 40, 18, 33] }, seriesExtra)],
  };
}
function graph(seriesExtra) {
  const nodes = Array.from({ length: 7 }, (_, i) => ({ name: 'n' + i, x: 60 + i * 70, y: 80 + ((i * 53) % 5) * 50, value: i }));
  return {
    animation: false,
    series: [Object.assign({ type: 'graph', layout: 'none', symbolSize: 20, label: { show: true }, labelLine: ll(),
      labelLayout: FAN, data: nodes, links: [{ source: 'n0', target: 'n1' }, { source: 'n2', target: 'n4' }] }, seriesExtra)],
  };
}
const treeData = {
  name: 'root', children: [
    { name: 'a', children: [{ name: 'a1', value: 1 }, { name: 'a2', value: 2 }] },
    { name: 'b', children: [{ name: 'b1', value: 3 }] },
    { name: 'c', value: 4 },
  ],
};
function tree(seriesExtra) {
  return {
    animation: false,
    series: [Object.assign({ type: 'tree', data: [treeData], top: 40, bottom: 40, left: 60, right: 120, symbolSize: 10,
      expandAndCollapse: false, labelLine: ll(), labelLayout: FAN }, seriesExtra)],
  };
}
function sunburst(seriesExtra) {
  return {
    animation: false,
    series: [Object.assign({ type: 'sunburst', radius: [20, '45%'], data: treeData.children, label: { show: true },
      labelLine: ll(), labelLayout: { dx: 30, dy: -20 } }, seriesExtra)],
  };
}
function sankey(seriesExtra) {
  return {
    animation: false,
    series: [Object.assign({ type: 'sankey', left: 40, right: 140, top: 40, bottom: 40, layoutIterations: 0,
      data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }, { source: 'b', target: 'd', value: 4 }],
      labelLine: ll(), labelLayout: { dx: 30, dy: -24 } }, seriesExtra)],
  };
}
function polarBar(seriesExtra, polarExtra) {
  return Object.assign({
    animation: false,
    polar: { radius: [30, '70%'] },
    angleAxis: { type: 'category', data: cats(5) },
    radiusAxis: {},
    series: [Object.assign({ type: 'bar', coordinateSystem: 'polar', data: [4, 7, 3, 6, 5], label: { show: true, position: 'middle' },
      labelLine: ll(), labelLayout: { dx: 24, dy: -20 } }, seriesExtra)],
  }, polarExtra || {});
}
function calendar(seriesExtra) {
  const data = [];
  for (let d = 1; d <= 12; d++) data.push(['2024-02-' + String(d).padStart(2, '0'), d]);
  return {
    animation: false,
    calendar: { range: '2024-02', cellSize: [40, 30], top: 60, left: 60 },
    series: [Object.assign({ type: 'scatter', coordinateSystem: 'calendar', symbolSize: 12, label: { show: true, formatter: '{@[1]}' },
      labelLine: ll(), labelLayout: { dx: 14, dy: -14 }, data }, seriesExtra)],
  };
}

const CASES = [
  // ---- the pie's own line, its normal lineStyle ----
  { id: 'pie.ls.full', note: 'labelLine.lineStyle: colour, width, dashed, round cap, bevel join, dashOffset, miterLimit, opacity',
    option: pie({ labelLine: { lineStyle: LS_FULL } }) },
  { id: 'pie.ls.width', note: 'lineStyle width 3 only: the slice\'s colour, the visual opacity',
    option: pie({ labelLine: { lineStyle: { width: 3 } } }) },
  { id: 'pie.ls.dotted', note: 'lineStyle type dotted, width 2', option: pie({ labelLine: { lineStyle: { type: 'dotted', width: 2 } } }) },
  { id: 'pie.ls.array', note: 'lineStyle type [6, 3], dashOffset 2', option: pie({ labelLine: { lineStyle: { type: [6, 3], dashOffset: 2 } } }) },
  { id: 'pie.ls.item', note: 'an item\'s own labelLine.lineStyle over the series\'',
    option: pie({ labelLine: { lineStyle: { color: '#888' } },
      data: crowd(10).map((d, i) => (i % 3 === 0 ? Object.assign({ labelLine: { lineStyle: { color: '#c23531', width: 2 } } }, d) : d)) }) },
  { id: 'pie.ls.itemopacity', note: 'itemStyle.opacity 0.5: the line\'s opacity is the visual\'s',
    option: pie({ itemStyle: { opacity: 0.5 } }) },
  { id: 'pie.ls.emph', note: 'a coloured normal line, emphasis lineStyle width 3', hover: hov([1, 4]),
    option: pie({ labelLine: { lineStyle: { color: '#123', width: 1.5 } }, emphasis: { labelLine: { lineStyle: { width: 3 } } } }) },
  { id: 'pie.emph.only', note: 'labelLine.show false, emphasis.labelLine.show true: the line hidden at rest, shown under emphasis',
    hover: hov([0, 3]), option: pie({ labelLine: { show: false }, emphasis: { labelLine: { show: true } } }) },
  { id: 'pie.emph.only.style', note: 'as pie.emph.only, the line\'s lineStyle', hover: hov([2]),
    option: pie({ labelLine: { show: false, lineStyle: { color: '#555', width: 2 } }, emphasis: { labelLine: { show: true } } }) },
  { id: 'pie.emph.only.select', note: 'labelLine.show false, emphasis true: selected, hidden', hover: sel([1, 5]),
    option: pie({ selectedMode: 'multiple', labelLine: { show: false }, emphasis: { labelLine: { show: true } } }) },
  { id: 'pie.select.only', note: 'labelLine.show false, select.labelLine.show true', hover: sel([1, 5]),
    option: pie({ selectedMode: 'multiple', labelLine: { show: false }, select: { labelLine: { show: true } } }) },
  { id: 'pie.label.emph.only', note: 'label and line shown only under emphasis', hover: hov([0, 6]),
    option: pie({ label: { show: false }, labelLine: { show: false }, emphasis: { label: { show: true }, labelLine: { show: true } } }) },
  // ---- the funnel's own line ----
  { id: 'funnel.ls.full', note: 'a funnel\'s labelLine.lineStyle', option: funnel({ labelLine: { lineStyle: LS_FULL } }) },
  { id: 'funnel.ls.width', note: 'a funnel\'s lineStyle width 2.5', option: funnel({ labelLine: { lineStyle: { width: 2.5 } } }) },
  { id: 'funnel.emph.only', note: 'a funnel: labelLine.show false, emphasis true', hover: hov([1, 3]),
    option: funnel({ labelLine: { show: false }, emphasis: { labelLine: { show: true } } }) },
  // ---- the general lines on other series ----
  { id: 'heatmap', note: 'heatmap cells: rect hosts', option: heat({}) },
  { id: 'heatmap.style', note: 'heatmap, lineStyle and length2', option: heat({ labelLine: ll({ length2: 8, lineStyle: { color: '#333', width: 2, cap: 'round' } }) }) },
  { id: 'heatmap.emph', note: 'heatmap, labelLine shown only under emphasis', hover: hov([3, 7]),
    option: heat({ labelLine: { show: false }, emphasis: { labelLine: { show: true } } }) },
  { id: 'pictorial', note: 'pictorial bars', option: pictorial({}) },
  { id: 'pictorial.circle', note: 'pictorial bars of repeated circles', option: pictorial({ symbol: 'circle', symbolRepeat: true, symbolSize: 12 }) },
  { id: 'graph', note: 'a graph\'s symbols on a view', option: graph({}) },
  { id: 'graph.zoom', note: 'a graph zoomed 1.4: the view\'s transform', option: graph({ zoom: 1.4 }) },
  { id: 'graph.style', note: 'a graph, lineStyle and showAbove', option: graph({ labelLine: ll({ showAbove: true, lineStyle: { color: '#a00', type: 'dashed' } }) }) },
  { id: 'tree', note: 'a tree\'s symbols', option: tree({}) },
  { id: 'tree.radial', note: 'a radial tree', option: tree({ layout: 'radial' }) },
  { id: 'sunburst', note: 'sunburst sectors', option: sunburst({}) },
  { id: 'sunburst.round', note: 'sunburst sectors with rounded corners', option: sunburst({ itemStyle: { borderRadius: 6 } }) },
  { id: 'sankey', note: 'sankey nodes', option: sankey({}) },
  { id: 'polarbar', note: 'bars on a polar grid', option: polarBar({}) },
  { id: 'polarbar.radial', note: 'radial bars on a polar grid', option: polarBar({},
    { angleAxis: {}, radiusAxis: { type: 'category', data: cats(5) } }) },
  { id: 'calendar', note: 'a scatter on a calendar', option: calendar({}) },
  // ---- without labelLayout: the rect as read before the host's alignment ----
  { id: 'heatmap.radius', note: 'heatmap cells with rounded corners, no labelLayout', option: heat({ itemStyle: { borderRadius: 6 }, labelLayout: undefined }) },
  { id: 'graph.plain', note: 'a graph, labels on the right, no labelLayout', option: graph({ label: { show: true, position: 'right' }, labelLayout: undefined }) },
  { id: 'graph.offset', note: 'a zoomed graph whose symbols are offset', option: graph({ zoom: 1.2, symbolOffset: [4, -3] }) },
  { id: 'graph.hover', note: 'a graph line under emphasis: its lineStyle', hover: hov([1, 3]),
    option: graph({ emphasis: { labelLine: { lineStyle: { width: 3, color: '#222' } } } }) },
  { id: 'tree.plain', note: 'a tree, no labelLayout', option: tree({ labelLayout: undefined }) },
  { id: 'tree.radial.plain', note: 'a radial tree, no labelLayout', option: tree({ layout: 'radial', labelLayout: undefined }) },
  { id: 'sunburst.plain', note: 'sunburst labels, no labelLayout', option: sunburst({ labelLayout: undefined }) },
  { id: 'sunburst.emph', note: 'a sunburst line shown under emphasis only', hover: hov([1, 4]),
    option: sunburst({ labelLine: { show: false }, emphasis: { labelLine: { show: true } } }) },
  { id: 'sankey.plain', note: 'sankey nodes, no labelLayout', option: sankey({ labelLayout: undefined }) },
  { id: 'polarbar.round', note: 'rounded polar bars', option: polarBar({ itemStyle: { borderRadius: 5 } }) },
  { id: 'pictorial.horiz', note: 'horizontal pictorial bars', option: Object.assign(pictorial({ label: { show: true, position: 'right' } }),
    { xAxis: {}, yAxis: { type: 'category', data: cats(6) } }) },
];

// ---------- one case ----------
function stateRec(g, name) {
  const st = g.states && g.states[name];
  if (!st) return null;
  return {
    ignore: st.ignore == null ? null : !!st.ignore,
    smooth: st.shape && st.shape.smooth != null ? hex(+st.shape.smooth) : null,
    style: styleRec(st.style),
  };
}
function guideRec(s, el, g) {
  const d = ecData(el);
  return {
    s: s.seriesIndex,
    d: d && d.dataIndex != null ? d.dataIndex : null,
    dataType: d && d.dataType != null ? d.dataType : null,
    host: el.type,
    ignore: !!g.ignore,
    points: pts3(placed(g)),
    smooth: hex(+g.shape.smooth || 0),
    curved: curved(g.shape),
    style: styleRec(g.style),
    z2: g.z2,
    hostZ2: el.z2,
    hostFill: el.style && el.style.fill != null ? String(el.style.fill) : null,
    hostStroke: el.style && el.style.stroke != null ? String(el.style.stroke) : null,
    states: { emphasis: stateRec(g, 'emphasis'), blur: stateRec(g, 'blur'), select: stateRec(g, 'select') },
  };
}
function eachGuide(chart, fn) {
  chart.getModel().eachSeries(s => {
    chart.getViewOfSeriesModel(s).group.traverse(el => {
      if (el.ignore) return true;
      const g = el.getTextGuideLine && el.getTextGuideLine();
      if (!g) return;
      fn(s, el, g);
    });
  });
}
function runCase(c) {
  rngState = SEED;
  capture = { lines: [] };
  pendingLine = null;
  const w = c.W || W;
  const h = c.H || H;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: w, height: h });
  try {
    chart.setOption(c.option);
    chart.renderToSVGString();
    const lines = capture.lines;
    capture = null;
    const guides = [];
    eachGuide(chart, (s, el, g) => guides.push(guideRec(s, el, g)));
    const hover = [];
    for (const payload of c.hover || []) {
      chart.dispatchAction(payload);
      chart._onframe();
      const rec = [];
      eachGuide(chart, (s, el, g) => {
        const d = ecData(el);
        rec.push({
          s: s.seriesIndex,
          d: d && d.dataIndex != null ? d.dataIndex : null,
          ignore: !!g.ignore,
          smooth: hex(+g.shape.smooth || 0),
          points: pts3(placed(g)),
          style: styleRec(g.style),
        });
      });
      hover.push({ payload, guides: rec });
      const back = payload.type === 'select' ? 'unselect' : 'downplay';
      chart.dispatchAction(Object.assign({}, payload, { type: back }));
      chart._onframe();
    }
    return { id: c.id, note: c.note, W: w, H: h, option: clone(c.option), lines, guides, hover };
  } finally {
    capture = null;
    chart.dispose();
  }
}

// ---------- generation ----------
function generate() {
  const cases = CASES.map(runCase);
  const byId = {};
  for (const c of cases) byId[c.id] = c;
  const shown = id => byId[id].guides.filter(g => !g.ignore).length;
  // anchors
  must(byId['pie.ls.full'].guides.length === 10 && byId['pie.ls.full'].guides.every(g => g.style.stroke === '#2a6f97'
    && g.style.lineCap === 'round' && g.style.lineJoin === 'bevel'), 'anchor: a pie line takes its lineStyle');
  must(byId['pie.ls.width'].guides.every(g => g.style.lineWidth === hex(3)), 'anchor: a pie line takes its width');
  must(byId['pie.emph.only'].guides.length > 0 && shown('pie.emph.only') === 0, 'anchor: an emphasis-only pie line is hidden at rest');
  must(byId['pie.emph.only'].hover.every(h => h.guides.some(g => !g.ignore)), 'anchor: an emphasis-only pie line shows when hovered');
  for (const id of ['heatmap', 'pictorial', 'graph', 'tree', 'sunburst', 'sankey', 'polarbar', 'calendar']) {
    must(shown(id) > 0, 'anchor: ' + id + ' draws label lines');
    must(byId[id].lines.length > 0, 'anchor: ' + id + ' routes its lines');
  }
  return {
    source: 'ECharts 6.1 dist (' + path.basename(DIST) + '), label/LabelManager.ts, label/labelGuideHelper.ts, chart/pie/PieView.ts, chart/funnel/FunnelView.ts',
    W, H, seed: SEED,
    cases,
  };
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
