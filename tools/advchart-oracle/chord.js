/*
Upstream's own answers for roadmap C11, batch 120: the CHORD series (new in
ECharts 6) -- the graph (createGraphFromNodeEdge: node keys id ?? name ??
index, a numeric link end an index, dropped links), the circular layout
(chordLayout.ts: the node values, padAngle and minAngle with their fallbacks,
the scale-all branch, the borrowing pass and its surplusAsMuchAsPossible,
clockwise, startAngle -- endAngle is never read), the node sectors (ChordPiece:
Sector with getSectorCornerRadius' [0, 0, 5, 5], the colour visual, the label
placed by the mid angle, inside or outside, its text the name used as a
template), the ribbons (ChordEdge: the path of two arcs and two cubics, the
fill from 'source' / 'target' / 'gradient' or the prototype's '#000', the
stroke and width from lineStyle), the legend's filter (dataFilter, the graph's
update), the states (emphasis focus adjacency on nodes and edges, the edges'
lineStyle states, blur), the tooltip (formatTooltip's nameValue), the click
events, convertToPixel / containPixel (no coordinate system), and the enter
animation (the view group's scale from 0.01 about the centre, the labels'
fade).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off (the tooltip view runs, its content on the
zrender canvas: renderMode 'richText'; getDom is stubbed on the chart
prototype), with the clock of animation.js (the global Date replaced BEFORE
the dist loads by one whose zero-argument form reads NOW; setTimeout a queue
that never runs), Math.random the port's xorshift32 (seed 2463534242, reset
before every chart) and zrender's width table measuring every string (the
TZrSsrMeasurer of the Pascal tests: `measure` below). Every pointer step goes
through zrender's own Handler with a synthetic event {zrX, zrY, which 1}; a
paint (renderToSVGString) follows every step, so every path is built.

  node tools/advchart-oracle/chord.js

writes tests/fixtures/advchart-chord.json (ORACLE_OUT overrides). Ends with
process.exit().

-----------------------------------------------------------------------------
Numbers that are positions are the 16 lowercase hex digits of the IEEE double
(big-endian; NaN 7ff8000000000000); counts, flags, strings and option values
are plain JSON. Every case's option carries the ECharts 6 palette at its root
(the port's default palette is its skin's).

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, notes[],
cases[], anim {samplesMs, clock, cases[]}, guards[].

A case: id, group, note, W, H, option (as run), series[] (one record per chord
series), legend null | {selected, items[] {name, fill}}, steps[] (the steps as
run, every point resolved to integers), states[] (index-parallel to [after
setOption, after step 1, ...]), convert[] (convert cases), fails[] (recipe
mismatches; must be empty).

A chord series record:
  index, name, count (node data count), edgeCount, group {scaleX, scaleY,
  originX, originY (hex), transform (null or 6 hex)}, order[] (the view
  group's children in order: 'n<raw>' a node sector, 'e<raw>' a ribbon),
  nodes[] by RAW node index: {raw, index (dataIndex, -1 filtered), key (the
    graph id), name (data.getName, '' none), value (hex: node.getValue()),
    layout null | {angle, value, ratio (null: none), cx, cy, r0, r,
    startAngle, endAngle (hex), clockwise}, el null | {cr (cornerRadius as
    set: a hex list), path[] (the PathProxy data, hex), fill (a string, or a
    gradient record), stroke, lineWidth, opacity, z2, label null | {text,
    ignore, x, y (hex: the text's own x / y), align, va, fill, stroke,
    lineWidth, opacity, z2}}}
  edges[] by RAW edge index (the links that survived the graph): {raw, row
    (the option index of the link), index (-1 filtered), source, target (raw
    node indices), value (hex: edge.getValue()), name (edge data name),
    layout null | {s1, s2, t1, t2 ([x, y] hex), sStartAngle, sEndAngle,
    tStartAngle, tEndAngle, cx, cy, r, value (hex), clockwise}, el null |
    {path[] (hex), fill (string | gradient {type, x, y, x2, y2 (hex), global,
    stops [{offset, color}]}), stroke (as set: a string), lineWidth,
    opacity, z2}}

A state (hover / state / action cases): {events[] (click events: dataType,
  dataIndex, name, value), tip null | {which ('item:' or 'edge:' + series +
  ':' + dataIndex), lines[{marker, name, value}]}, series[] (an action case:
  the series records again), els[] -- every element: {k ('n' | 'e'), raw,
  index, hover (hoverState), states ('a,b'), fill, stroke, lineWidth,
  opacity, z2, label null | {ignore, opacity, fill, z2}}}

anim.cases[]: advchart-animation.json's own format (id, kind, chart, variant,
  note, option, next, W, H, resolved, clips, elements).

Guards (any failure: nothing is written, exit 1): R1 the layout recomputed
from the graph's values (chordLayout transcribed) equals upstream's, every
node and edge; R2 every ribbon's PathProxy data recomputed (buildPath with
PathProxy's normalizeArcAngles) equals upstream's; R3 every label's place,
alignment and text recomputed; R4 every gradient ribbon's points are the two
arcs' chord midpoints; named discriminating facts; and the whole fixture
generated twice, byte-identical.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-chord.json');

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
const hexN = v => (v == null ? '7ff8000000000000' : hex(+v));
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const same = (a, b) => Object.is(a, b);
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const isGrad = v => v != null && typeof v === 'object' && Array.isArray(v.colorStops);
function colourRec(v) {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  if (isGrad(v)) {
    return { type: v.type, x: hexN(v.x), y: hexN(v.y), x2: hexN(v.x2), y2: hexN(v.y2), global: !!v.global,
      stops: v.colorStops.map(s => ({ offset: s.offset, color: s.color })) };
  }
  return JSON.stringify(v);
}

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

// ---------- the chart ----------
(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  rngState = SEED;
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function paint(chart) {
  chart._onframe();
  refresh(chart);
  quiet(() => chart.renderToSVGString());
  refresh(chart);
}
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, extra) {
  refresh(chart);
  zr(chart).handler[name](zev(extra));
  refresh(chart);
}
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}
function chordSeries(chart) {
  const out = [];
  chart.getModel().eachSeries(s => { if (s.subType === 'chord') out.push(s); });
  return out;
}

// ---------- the tooltip ----------
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function parseLine(line, rich, where) {
  const row = { marker: null, name: null, value: null };
  let last = 0;
  let stage = 0;
  let afterMarker = false;
  const gap = s => { must(!s || (afterMarker && !s.trim()), where + ': text outside a segment ' + JSON.stringify(s)); };
  SEGMENT.lastIndex = 0;
  let m;
  while ((m = SEGMENT.exec(line))) {
    gap(line.slice(last, m.index));
    last = SEGMENT.lastIndex;
    const st = rich[m[1]];
    must(st, where + ': no rich style ' + m[1]);
    let kind;
    if (st.width != null) kind = 0;
    else if (String(st.fontWeight) === '400') kind = 1;
    else if (String(st.fontWeight) === '900') kind = 2;
    else throw new OracleError(where + ': a segment styled ' + JSON.stringify(st));
    must(kind >= stage, where + ': segments out of order');
    stage = kind + 1;
    afterMarker = kind === 0;
    if (kind === 0) row.marker = st.width === 10 ? 'item' : 'subItem';
    else if (kind === 1) row.name = m[2];
    else row.value = m[2];
  }
  gap(line.slice(last));
  return row;
}
function hookTooltip(chart, rec) {
  const view = tooltipView(chart);
  if (!view) return;
  const show = view._showTooltipContent;
  view._showTooltipContent = function (tooltipModel, html, params) {
    if (Array.isArray(params)) rec.which = 'axis';
    else rec.which = (params.dataType === 'edge' ? 'edge:' : 'item:') + params.seriesIndex + ':' + params.dataIndex;
    return show.apply(this, arguments);
  };
}
function tipNow(chart, rec, where) {
  const view = tooltipView(chart);
  if (!view) return null;
  const c = view._tooltipContent;
  const visible = !!(c && c.el && !c.el.ignore && !c.el.invisible);
  if (!visible || !rec.which) return null;
  const text = String(c.el.style.text);
  const lines = text.split('\n').map(line => parseLine(line, c.el.style.rich || {}, where));
  return { which: rec.which, lines };
}

// ---------------------------------------------------------------------------
// the recipes
// ---------------------------------------------------------------------------
const RADIAN = Math.PI / 180;
const PI2 = Math.PI * 2;
function modPI2(radian) {
  const n = Math.round(radian / Math.PI * 1e8) / 1e8;
  return (n % 2) * Math.PI;
}
// PathProxy.ts normalizeArcAngles
function normalizeArcAngles(angles, anticlockwise) {
  let newStartAngle = modPI2(angles[0]);
  if (newStartAngle < 0) newStartAngle += PI2;
  const delta = newStartAngle - angles[0];
  let newEndAngle = angles[1];
  newEndAngle += delta;
  if (!anticlockwise && newEndAngle - newStartAngle >= PI2) newEndAngle = newStartAngle + PI2;
  else if (anticlockwise && newStartAngle - newEndAngle >= PI2) newEndAngle = newStartAngle - PI2;
  else if (!anticlockwise && newStartAngle > newEndAngle) newEndAngle = newStartAngle + (PI2 - modPI2(newStartAngle - newEndAngle));
  else if (anticlockwise && newStartAngle < newEndAngle) newEndAngle = newStartAngle - (PI2 - modPI2(newEndAngle - newStartAngle));
  angles[0] = newStartAngle;
  angles[1] = newEndAngle;
}
// chordLayout.ts over the graph's own values: the node layouts by node
// dataIndex and the edge layouts by edge dataIndex, or null (no layout)
function layoutRecipe(s) {
  const nodeData = s.getData();
  const graph = nodeData.graph;
  const edgeData = s.getEdgeData();
  if (!edgeData.count()) return null;
  const any = graph.nodes.find(n => n.dataIndex >= 0 && n.getLayout());
  if (!any) return null;
  const { cx, cy, r, r0 } = any.getLayout();
  let padAngle = Math.max((s.get('padAngle') || 0) * RADIAN, 0);
  let minAngle = Math.max((s.get('minAngle') || 0) * RADIAN, 0);
  const startAngle = -s.get('startAngle') * RADIAN;
  const endAngle = startAngle + Math.PI * 2;
  const clockwise = s.get('clockwise');
  const dir = clockwise ? 1 : -1;
  const angles = [startAngle, endAngle];
  normalizeArcAngles(angles, !clockwise);
  const [nStart, nEnd] = angles;
  const totalAngle = nEnd - nStart;
  const allZero = nodeData.getSum('value') === 0 && edgeData.getSum('value') === 0;
  const nodeValues = [];
  let rendered = 0;
  graph.eachEdge(edge => {
    const value = allZero ? 1 : edge.getValue('value');
    if (allZero && (value > 0 || minAngle)) rendered += 2;
    const a = edge.node1.dataIndex;
    const b = edge.node2.dataIndex;
    nodeValues[a] = (nodeValues[a] || 0) + value;
    nodeValues[b] = (nodeValues[b] || 0) + value;
  });
  let sum = 0;
  graph.eachNode(node => {
    const dv = node.getValue('value');
    if (!isNaN(dv)) nodeValues[node.dataIndex] = Math.max(dv, nodeValues[node.dataIndex] || 0);
    if (!allZero && (nodeValues[node.dataIndex] > 0 || minAngle)) rendered++;
    sum += nodeValues[node.dataIndex] || 0;
  });
  if (rendered === 0 || sum === 0) return null;
  if (padAngle * rendered >= Math.abs(totalAngle)) padAngle = Math.max(0, (Math.abs(totalAngle) - minAngle * rendered) / rendered);
  if ((padAngle + minAngle) * rendered >= Math.abs(totalAngle)) minAngle = (Math.abs(totalAngle) - padAngle * rendered) / rendered;
  const unitAngle = (totalAngle - padAngle * rendered * dir) / sum;
  const L = {};
  let deficit = 0;
  let surplus = 0;
  let surplusSpan = 0;
  graph.eachNode(node => {
    const value = nodeValues[node.dataIndex] || 0;
    const span = unitAngle * (sum ? value : 1) * dir;
    if (Math.abs(span) < minAngle) deficit += minAngle - Math.abs(span);
    else {
      surplus += Math.abs(span) - minAngle;
      surplusSpan += Math.abs(span);
    }
    L[node.dataIndex] = { angle: span, value };
  });
  let asMuch = false;
  let scaled = false;
  if (deficit > surplus) {
    scaled = true;
    const scale = deficit / surplus;
    graph.eachNode(node => {
      const sp = L[node.dataIndex].angle;
      if (Math.abs(sp) >= minAngle) Object.assign(L[node.dataIndex], { angle: sp * scale, ratio: scale });
      else Object.assign(L[node.dataIndex], { angle: minAngle, ratio: minAngle === 0 ? 1 : sp / minAngle });
    });
  }
  else {
    graph.eachNode(node => {
      if (asMuch) return;
      const sp = L[node.dataIndex].angle;
      const br = Math.min(sp / surplusSpan, 1);
      if (sp - br * deficit < minAngle) asMuch = true;
    });
  }
  let rest = deficit;
  graph.eachNode(node => {
    if (rest <= 0) return;
    const sp = L[node.dataIndex].angle;
    if (sp > minAngle && minAngle > 0) {
      const br = asMuch ? 1 : Math.min(sp / surplusSpan, 1);
      const borrow = Math.min(sp - minAngle, Math.min(rest, deficit * br));
      rest -= borrow;
      Object.assign(L[node.dataIndex], { angle: sp - borrow, ratio: (sp - borrow) / sp });
    }
    else if (minAngle > 0) {
      Object.assign(L[node.dataIndex], { angle: minAngle, ratio: sp === 0 ? 1 : minAngle / sp });
    }
  });
  let angle = nStart;
  const acc = [];
  graph.eachNode(node => {
    const span = Math.max(L[node.dataIndex].angle, minAngle);
    Object.assign(L[node.dataIndex], { cx, cy, r0, r, startAngle: angle, endAngle: angle + span * dir, clockwise });
    acc[node.dataIndex] = angle;
    angle += (span + padAngle) * dir;
  });
  const E = {};
  graph.eachEdge(edge => {
    const value = allZero ? 1 : edge.getValue('value');
    const span = unitAngle * (sum ? value : 1) * dir;
    const a = edge.node1.dataIndex;
    const sS = acc[a] || 0;
    const sSpan = Math.abs((L[a].ratio || 1) * span);
    const sE = sS + sSpan * dir;
    const b = edge.node2.dataIndex;
    const tS = acc[b] || 0;
    const tSpan = Math.abs((L[b].ratio || 1) * span);
    const tE = tS + tSpan * dir;
    E[edge.dataIndex] = {
      s1: [cx + r0 * Math.cos(sS), cy + r0 * Math.sin(sS)], s2: [cx + r0 * Math.cos(sE), cy + r0 * Math.sin(sE)],
      sStartAngle: sS, sEndAngle: sE,
      t1: [cx + r0 * Math.cos(tS), cy + r0 * Math.sin(tS)], t2: [cx + r0 * Math.cos(tE), cy + r0 * Math.sin(tE)],
      tStartAngle: tS, tEndAngle: tE, cx, cy, r: r0, value, clockwise };
    acc[a] = sE;
    acc[b] = tE;
  });
  return { L, E, scaled, asMuch, minAngle, padAngle };
}
// ChordEdge.buildPath into PathProxy's data
function pathRecipe(sh) {
  const out = [];
  const ratio = 0.7;
  out.push(1, sh.s1[0], sh.s1[1]);
  const arc = (a0, a1) => {
    const ang = [a0, a1];
    normalizeArcAngles(ang, !sh.clockwise);
    out.push(5, sh.cx, sh.cy, sh.r, sh.r, ang[0], ang[1] - ang[0], 0, sh.clockwise ? 1 : 0);
  };
  arc(sh.sStartAngle, sh.sEndAngle);
  out.push(3, (sh.cx - sh.s2[0]) * ratio + sh.s2[0], (sh.cy - sh.s2[1]) * ratio + sh.s2[1],
    (sh.cx - sh.t1[0]) * ratio + sh.t1[0], (sh.cy - sh.t1[1]) * ratio + sh.t1[1], sh.t1[0], sh.t1[1]);
  arc(sh.tStartAngle, sh.tEndAngle);
  out.push(3, (sh.cx - sh.t2[0]) * ratio + sh.t2[0], (sh.cy - sh.t2[1]) * ratio + sh.t2[1],
    (sh.cx - sh.s1[0]) * ratio + sh.s1[0], (sh.cy - sh.s1[1]) * ratio + sh.s1[1], sh.s1[0], sh.s1[1]);
  out.push(6);
  return out;
}

// ---------------------------------------------------------------------------
// reading
// ---------------------------------------------------------------------------
const pathData = el => {
  if (!el.path) el.getBoundingRect();
  must(el.path, 'no path proxy');
  return Array.from(el.path.data).slice(0, el.path.len());
};
const opac = st => (st.opacity == null ? 1 : st.opacity);
function labelRec(el) {
  const tc = el.getTextContent();
  if (!tc) return null;
  return { text: tc.style.text == null ? null : String(tc.style.text), ignore: !!tc.ignore || !!tc.invisible,
    x: hexN(tc.x), y: hexN(tc.y), align: tc.style.align == null ? null : tc.style.align,
    va: tc.style.verticalAlign == null ? null : tc.style.verticalAlign, fill: colourRec(tc.style.fill),
    stroke: colourRec(tc.style.stroke), lineWidth: tc.style.lineWidth == null ? null : hexN(tc.style.lineWidth),
    opacity: hexN(opac(tc.style)), z2: tc.z2 };
}
function readSeries(chart, c, fails) {
  const out = [];
  for (const s of chordSeries(chart)) {
    const where = c.id + ' s' + s.seriesIndex;
    const data = s.getData();
    const graph = data.graph;
    const edgeData = s.getEdgeData();
    const view = chart.getViewOfSeriesModel(s);
    const g = view.group;
    const rec = { index: s.seriesIndex, name: s.name.indexOf('\u0000') >= 0 ? null : s.name, count: data.count(),
      edgeCount: edgeData.count(),
      group: { scaleX: hexN(g.scaleX), scaleY: hexN(g.scaleY), originX: hexN(g.originX), originY: hexN(g.originY),
        transform: g.transform ? Array.from(g.transform).map(hexN) : null },
      order: [], nodes: [], edges: [] };
    const nodeEls = new Map();
    const edgeEls = new Map();
    g.childrenRef().forEach(el => {
      const ecd = ecDataOf(el);
      must(ecd, where + ': a child with no ECData');
      if (ecd.dataType === 'node') {
        const raw = data.getRawIndex(ecd.dataIndex);
        nodeEls.set(raw, el);
        rec.order.push('n' + raw);
      }
      else {
        must(ecd.dataType === 'edge', where + ': a child of data type ' + ecd.dataType);
        const raw = edgeData.getRawIndex(ecd.dataIndex);
        edgeEls.set(raw, el);
        rec.order.push('e' + raw);
      }
    });
    const recipe = layoutRecipe(s);
    // the option row of each link the graph kept: Graph.addEdge's own test
    const rows = [];
    (s.option.edges || s.option.links || []).forEach((link, row) => {
      const end = v => (typeof v === 'number' ? graph.nodes[v] : undefined) || graph.getNodeById(v);
      if (end(link.source) && end(link.target)) rows.push(row);
    });
    must(rows.length === graph.edges.length, where + ': ' + rows.length + ' links kept, the graph has ' + graph.edges.length);
    graph.nodes.forEach((node, raw) => {
      must(node.dataIndex < 0 || data.getRawIndex(node.dataIndex) === raw, where + ': node ' + raw + ' is not raw ' + raw);
      const rawData = s.getRawData();
      const nr = { raw, index: node.dataIndex, key: node.id, name: rawData.getName(raw), value: hexN(rawData.get('value', raw)),
        layout: null, el: null };
      const lay = node.dataIndex >= 0 ? node.getLayout() : null;
      if (lay && lay.cx != null) {
        nr.layout = { angle: hexN(lay.angle), value: hexN(lay.value), ratio: lay.ratio == null ? null : hexN(lay.ratio),
          cx: hexN(lay.cx), cy: hexN(lay.cy), r0: hexN(lay.r0), r: hexN(lay.r), startAngle: hexN(lay.startAngle),
          endAngle: hexN(lay.endAngle), clockwise: !!lay.clockwise };
        const w = recipe && recipe.L[node.dataIndex];
        if (!w) fails.push(where + ' node ' + raw + ': no recipe layout');
        else {
          for (const k of ['angle', 'value', 'ratio', 'startAngle', 'endAngle']) {
            if (!same(w[k], lay[k])) fails.push(where + ' node ' + raw + ' ' + k + ': ' + lay[k] + ', the recipe ' + w[k]);
          }
        }
      }
      const el = nodeEls.get(raw);
      if (el) {
        const cr = el.shape.cornerRadius;
        nr.el = { cr: Array.isArray(cr) ? cr.map(hexN) : [hexN(cr)], path: pathData(el).map(hexN),
          fill: colourRec(el.style.fill), stroke: colourRec(el.style.stroke),
          lineWidth: el.style.lineWidth == null ? null : hexN(el.style.lineWidth), opacity: hexN(opac(el.style)),
          z2: el.z2, label: labelRec(el) };
        // R3: the label's place and alignment
        const lab = el.getTextContent();
        if (lab && lay) {
          const lm = node.getModel().getModel('label');
          const pos = lm.get('position') || 'outside';
          const dist = lm.get('distance') || 0;
          const mid = (lay.startAngle + lay.endAngle) / 2;
          const dx = Math.cos(mid);
          const dy = Math.sin(mid);
          const rr = pos === 'outside' ? lay.r + dist : (lay.r + lay.r0) / 2;
          const ax = dx * rr + lay.cx;
          const ay = dy * rr + lay.cy;
          const al = pos !== 'outside' ? lm.get('align') || 'center' : (dx > 0 ? 'left' : 'right');
          const va = pos !== 'outside' ? lm.get('verticalAlign') || 'middle' : (dy > 0 ? 'top' : 'bottom');
          if (!same(lab.x, ax) || !same(lab.y, ay) || lab.style.align !== al || lab.style.verticalAlign !== va) {
            fails.push(where + ' node ' + raw + ': the label at ' + lab.x + ',' + lab.y + ' ' + lab.style.align + '/' + lab.style.verticalAlign
              + ', the recipe ' + ax + ',' + ay + ' ' + al + '/' + va);
          }
        }
      }
      rec.nodes.push(nr);
    });
    graph.edges.forEach((edge, raw) => {
      must(edgeData.getRawIndex(edge.dataIndex) === raw || edge.dataIndex < 0, where + ': edge ' + raw + ' is not raw ' + raw);
      const er = { raw, row: rows[raw], index: edge.dataIndex, source: graph.nodes.indexOf(edge.node1),
        target: graph.nodes.indexOf(edge.node2),
        value: hexN(edgeData.getStore().getByRawIndex(edgeData.getDimensionIndex('value'), raw)),
        name: edge.dataIndex >= 0 ? edgeData.getName(edge.dataIndex) : null, layout: null, el: null };
      must(edge.dataIndex < 0 || same(edgeData.getStore().getByRawIndex(edgeData.getDimensionIndex('value'), raw), edge.getValue('value')),
        where + ': edge ' + raw + ': the raw value is not the value');
      const lay = edge.dataIndex >= 0 ? edge.getLayout() : null;
      if (lay && lay.s1) {
        er.layout = { s1: lay.s1.map(hexN), s2: lay.s2.map(hexN), t1: lay.t1.map(hexN), t2: lay.t2.map(hexN),
          sStartAngle: hexN(lay.sStartAngle), sEndAngle: hexN(lay.sEndAngle), tStartAngle: hexN(lay.tStartAngle),
          tEndAngle: hexN(lay.tEndAngle), cx: hexN(lay.cx), cy: hexN(lay.cy), r: hexN(lay.r), value: hexN(lay.value),
          clockwise: !!lay.clockwise };
        const w = recipe && recipe.E[edge.dataIndex];
        if (!w) fails.push(where + ' edge ' + raw + ': no recipe layout');
        else {
          for (const k of ['sStartAngle', 'sEndAngle', 'tStartAngle', 'tEndAngle', 'value']) {
            if (!same(w[k], lay[k])) fails.push(where + ' edge ' + raw + ' ' + k + ': ' + lay[k] + ', the recipe ' + w[k]);
          }
          for (const k of ['s1', 's2', 't1', 't2']) {
            if (!same(w[k][0], lay[k][0]) || !same(w[k][1], lay[k][1])) fails.push(where + ' edge ' + raw + ' ' + k);
          }
        }
      }
      const el = edgeEls.get(raw);
      if (el) {
        const pd = pathData(el);
        er.el = { path: pd.map(hexN), fill: colourRec(el.style.fill), stroke: colourRec(el.style.stroke),
          lineWidth: el.style.lineWidth == null ? null : hexN(el.style.lineWidth), opacity: hexN(opac(el.style)), z2: el.z2 };
        // R2: the path
        if (lay && lay.s1) {
          const want = pathRecipe(el.shape);
          if (want.length !== pd.length || want.some((v, k) => !same(v, pd[k]))) {
            fails.push(where + ' edge ' + raw + ': the path ' + pd.join(',') + ', the recipe ' + want.join(','));
          }
        }
        // R4: the gradient's points
        if (isGrad(el.style.fill) && el.style.fill.global) {
          const sh = el.shape;
          const f = el.style.fill;
          if (!same(f.x, (sh.s1[0] + sh.s2[0]) / 2) || !same(f.y, (sh.s1[1] + sh.s2[1]) / 2)
            || !same(f.x2, (sh.t1[0] + sh.t2[0]) / 2) || !same(f.y2, (sh.t1[1] + sh.t2[1]) / 2) || !f.global) {
            fails.push(where + ' edge ' + raw + ': the gradient ' + JSON.stringify(f));
          }
        }
      }
      rec.edges.push(er);
    });
    rec.recipe = recipe ? { scaled: recipe.scaled, asMuch: recipe.asMuch, minAngle: hexN(recipe.minAngle),
      padAngle: hexN(recipe.padAngle) } : null;
    out.push(rec);
  }
  return out;
}
function readLegend(chart) {
  const lm = chart.getModel().getComponent('legend', 0);
  if (!lm) return null;
  const view = chart.getViewOfComponentModel(lm);
  const items = [];
  view.getContentGroup().eachChild(g => {
    if (g.__legendDataIndex == null) return;
    const icon = g.childAt(0);
    const text = g.children().find(x => x.type === 'text');
    items.push({ name: text.style.text, fill: icon.isGroup ? null : colourRec(icon.style.fill) });
  });
  return { selected: clone(lm.option.selected) || null, items };
}
function readEls(chart) {
  const out = [];
  for (const s of chordSeries(chart)) {
    const data = s.getData();
    const edgeData = s.getEdgeData();
    const one = (k, raw, index, el) => {
      const tc = el.getTextContent && el.getTextContent();
      out.push({ s: s.seriesIndex, k, raw, index, hover: el.hoverState || 0, states: (el.currentStates || []).join(','),
        fill: colourRec(el.style.fill), stroke: colourRec(el.style.stroke),
        lineWidth: el.style.lineWidth == null ? null : hexN(el.style.lineWidth), opacity: hexN(opac(el.style)), z2: el.z2,
        label: tc ? { ignore: !!tc.ignore || !!tc.invisible, opacity: hexN(opac(tc.style)), fill: colourRec(tc.style.fill), z2: tc.z2 } : null });
    };
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (el) one('n', data.getRawIndex(i), i, el);
    }
    for (let i = 0; i < edgeData.count(); i++) {
      const el = edgeData.getItemGraphicEl(i);
      if (el) one('e', edgeData.getRawIndex(i), i, el);
    }
  }
  return out;
}

// ---------- point finders ----------
function hoverTarget(chart, x, y) {
  refresh(chart);
  return zr(chart).handler.findHover(x, y).target;
}
function hostOf(el) {
  while (el && !(ecDataOf(el) && ecDataOf(el).dataIndex != null)) el = el.__hostTarget || el.parent;
  return el;
}
function spiral(x0, y0, ok, where) {
  for (let r = 0; r <= 14; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        if (ok(x0 + dx, y0 + dy)) return [x0 + dx, y0 + dy];
      }
    }
  }
  throw new OracleError(where + ': no point found near ' + x0 + ',' + y0);
}
// a node: on its sector's mid angle, halfway through the ring; a ribbon:
// just inside the circle on its source arc's mid angle -- the hover target
// must be that element (a label or a later ribbon over it does not count)
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  const s = chart.getModel().getSeriesByIndex(t.si || 0);
  if (t.node !== undefined) {
    const data = s.getData();
    const idx = data.indexOfRawIndex(t.node);
    const el = data.getItemGraphicEl(idx);
    must(el, where + ': no sector for node ' + t.node);
    const sh = el.shape;
    const mid = (sh.startAngle + sh.endAngle) / 2;
    const rr = (sh.r + sh.r0) / 2;
    return spiral(Math.round(sh.cx + rr * Math.cos(mid)), Math.round(sh.cy + rr * Math.sin(mid)),
      (x, y) => hoverTarget(chart, x, y) === el, where);
  }
  if (t.edge !== undefined) {
    const ed = s.getEdgeData();
    const idx = ed.indexOfRawIndex(t.edge);
    const el = ed.getItemGraphicEl(idx);
    must(el, where + ': no ribbon for edge ' + t.edge);
    const sh = el.shape;
    const mid = (sh.sStartAngle + sh.sEndAngle) / 2;
    const rr = sh.r - (t.depth || 12);
    return spiral(Math.round(sh.cx + rr * Math.cos(mid)), Math.round(sh.cy + rr * Math.sin(mid)),
      (x, y) => hoverTarget(chart, x, y) === el, where);
  }
  throw new OracleError(where + ': an unknown target ' + JSON.stringify(t));
}

// ---------- events ----------
function eventRec(p) {
  const o = { type: p.type, componentType: p.componentType, componentSubType: p.componentSubType,
    seriesIndex: p.seriesIndex, seriesType: p.seriesType, dataType: p.dataType == null ? null : p.dataType,
    dataIndex: p.dataIndex, name: p.name == null ? null : String(p.name),
    value: p.value === undefined ? null : (typeof p.value === 'number' ? hexN(p.value) : String(p.value)),
    valueIsNumber: typeof p.value === 'number', color: colourRec(p.color) };
  return o;
}

// ---------- the conversions ----------
function runConvert(chart, probes) {
  return probes.map(([op, finder, value]) => {
    let out;
    try {
      const r = quiet(() => {
        if (op === 'to') return chart.convertToPixel(finder, value);
        if (op === 'from') return chart.convertFromPixel(finder, value);
        return chart.containPixel(finder, value);
      });
      if (r === undefined) out = { k: 'none' };
      else if (typeof r === 'boolean') out = { k: 'bool', v: r };
      else if (typeof r === 'number') out = { k: 'num', v: hex(r) };
      else if (Array.isArray(r)) out = { k: 'arr', v: r.map(hexN) };
      else throw new OracleError('an unexpected result ' + JSON.stringify(r));
    } catch (e) {
      if (!(e instanceof TypeError)) throw e;
      out = { k: 'throw' };
    }
    return { op, finder: JSON.stringify(finder), value: JSON.stringify(value), out };
  });
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400,
  option: Object.assign({ animation: false, color: PALETTE }, option) }, more || {}));
const chord = (data, links, extra) => Object.assign({ type: 'chord', data, links }, extra || {});
const N = names => names.map(n => ({ name: n }));
const L = list => list.map(([s, t, v]) => ({ source: s, target: t, value: v }));
const D3 = [N(['A', 'B', 'C']), L([['A', 'B', 40], ['B', 'C', 20], ['C', 'A', 10]])];
const D6 = [N(['A', 'B', 'C', 'D', 'E', 'F']),
  L([['A', 'B', 10], ['A', 'C', 15], ['B', 'C', 8], ['C', 'D', 12], ['D', 'A', 5], ['E', 'F', 7], ['F', 'B', 9],
    ['A', 'E', 3], ['D', 'D', 2]])];
const D4 = [N(['A', 'B', 'C', 'D']), L([['A', 'B', 40], ['B', 'C', 20], ['C', 'A', 10], ['D', 'A', 0.5]])];

// ---- layout
add('static', 'basic', 'three nodes, three links: the defaults (padAngle 3, radius 70% / 80%, startAngle 90, labels outside)',
  { series: [chord(...D3)] });
add('static', 'basic-6', 'six nodes, nine links, a self loop (D -> D): the self loop takes twice its value on D',
  { series: [chord(...D6)] });
add('static', 'pad-0', 'padAngle 0: the sectors touch', { series: [chord(...D6, { padAngle: 0 })] });
add('static', 'pad-big', 'padAngle 70 over six nodes: more than the turn, so padAngle takes what minAngle leaves',
  { series: [chord(...D6, { padAngle: 70 })] });
add('static', 'minangle-borrow', 'minAngle 20 and padAngle 5: a tiny node (D) borrows from the others in order until the deficit is met',
  { series: [chord(...D4, { minAngle: 20, padAngle: 5 })] });
add('static', 'minangle-scale', 'every value nought, minAngle 90 over four nodes and one link: the deficit beats the surplus, every angle scaled',
  { series: [chord(N(['A', 'B', 'C', 'D']), [{ source: 'A', target: 'B', value: 0 }], { minAngle: 90 })] });
add('static', 'minangle-asmuch', 'minAngle 80: a node that would fall under minAngle by its share lends as much as it can (surplusAsMuchAsPossible)',
  { series: [chord(N(['A', 'B', 'C', 'D']), L([['A', 'B', 30], ['A', 'C', 1], ['B', 'D', 1], ['A', 'A', 10]]), { minAngle: 80 })] });
add('static', 'minangle-big', 'minAngle 120 over four nodes: more than the turn, so minAngle is cut to fit',
  { series: [chord(...D4, { minAngle: 120 })] });
add('static', 'ccw', 'clockwise false, startAngle 30', { series: [chord(...D6, { clockwise: false, startAngle: 30 })] });
add('static', 'angles', 'startAngle 0 and endAngle 180 (never read: a full turn), centre 40% / 55%, radius 30% / 45%, a box',
  { series: [chord(...D6, { startAngle: 0, endAngle: 180, center: ['40%', '55%'], radius: ['30%', '45%'], left: 40, top: 20, right: 60, bottom: 30 })] });
add('static', 'angles-neg', 'startAngle -135, a single radius (r0 nought), centre in pixels',
  { series: [chord(...D3, { startAngle: -135, radius: '60%', center: [260, 190] })] });
add('static', 'radius-px', 'radius in pixels [100, 130], borderRadius 0 on the series',
  { series: [chord(...D6, { radius: [100, 130], itemStyle: { borderRadius: 0 } })] });

// ---- colours and ribbons
add('static', 'gradient', "lineStyle.color 'gradient': a ribbon between two string colours is a global linear gradient across the two arcs' chords; "
  + "a node coloured by a gradient object leaves its ribbons the prototype's '#000'; one link 'target'",
  { series: [chord(
    [{ name: 'A' }, { name: 'B' }, { name: 'C', itemStyle: { color: '#ff0000' } },
      { name: 'D', itemStyle: { color: { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#00f' }, { offset: 1, color: '#0f0' }] } } }],
    [{ source: 'A', target: 'B', value: 12 }, { source: 'B', target: 'C', value: 8 }, { source: 'C', target: 'A', value: 6 },
      { source: 'D', target: 'A', value: 5 }, { source: 'B', target: 'D', value: 4 }, { source: 'C', target: 'D', value: 3, lineStyle: { color: 'target' } }],
    { lineStyle: { color: 'gradient' } })] });
add('static', 'edge-styles', "per-link lineStyle: a literal colour fills '#000' and strokes, a width, an opacity, 'target'; the series' opacity 0.35",
  { series: [chord(...D4.slice(0, 1), [
    { source: 'A', target: 'B', value: 40 },
    { source: 'B', target: 'C', value: 20, lineStyle: { color: '#0000ff', width: 2 } },
    { source: 'C', target: 'A', value: 10, lineStyle: { color: 'target', opacity: 0.6 } },
    { source: 'D', target: 'B', value: 6, lineStyle: { width: 3 } },
    { source: 'A', target: 'D', value: 4, lineStyle: { color: 'source', opacity: 0.9 } }], { lineStyle: { opacity: 0.35 } })] });
add('static', 'item-style', 'borderRadius 10 on the series, ["10%", 0] on one node, a border, an opacity, a colour',
  { series: [chord(
    [{ name: 'A', itemStyle: { borderRadius: ['10%', 0], borderColor: '#333', borderWidth: 2 } }, { name: 'B', itemStyle: { opacity: 0.5 } },
      { name: 'C', itemStyle: { color: '#123456' } }, { name: 'D' }],
    D4[1], { itemStyle: { borderRadius: 10 } })] });

// ---- labels
add('static', 'labels-inside', "label position 'inside': the ring's middle, centred; one node's label right / top; one hidden; a template",
  { series: [chord(
    [{ name: 'A' }, { name: 'B', label: { align: 'right', verticalAlign: 'top' } }, { name: 'C', label: { show: false } },
      { name: 'D', label: { formatter: '{b}:{c}' } }],
    D4[1], { label: { position: 'inside', fontSize: 14 } })] });
add('static', 'labels-distance', "distance 20 and a series template '{b} ({c})'; a node's own colour; a nameless node of a named series reads the SERIES' name (Model.get('name'))",
  { series: [chord([{ name: 'A', label: { color: '#123456' } }, { value: 30 }, 25, { name: 'D', label: { formatter: null } }],
    L([[0, 1, 9], [1, 2, 7], [2, 3, 5], [3, 0, 3]]), { name: 'Ser', label: { distance: 20 } })] });
add('static', 'labels-index', 'an unnamed series of nameless nodes: the label is the data index; a label coloured inherit',
  { series: [chord([{ value: 5 }, { value: 9 }, 4, {}], L([[0, 1, 2], [1, 2, 3], [3, 0, 1]]), { label: { color: 'inherit' } })] });
add('static', 'labels-overlap', "labelLayout hideOverlap over twelve crowded nodes with long names: the label layout hides the later ones that collide",
  { series: [chord(N(['Alpha one', 'Beta two', 'Gamma three', 'Delta four', 'Epsilon five', 'Zeta six', 'Eta seven', 'Theta eight',
    'Iota nine', 'Kappa ten', 'Lambda eleven', 'Mu twelve']),
  L([[0, 1, 30], [1, 2, 2], [2, 3, 2], [3, 4, 2], [4, 5, 2], [5, 6, 2], [6, 7, 2], [7, 8, 2], [8, 9, 2], [9, 10, 2], [10, 11, 2], [11, 0, 25]]),
  { labelLayout: { hideOverlap: true }, padAngle: 1, label: { fontSize: 26 } })] });
add('static', 'labels-off', 'labels off on the series, one node on',
  { series: [chord([{ name: 'A' }, { name: 'B', label: { show: true } }, { name: 'C' }], D3[1], { label: { show: false } })] });

// ---- values and the graph
add('static', 'allzero', 'every value nought: each link counts one, the angle by the number of link ends',
  { series: [chord(N(['A', 'B', 'C', 'D']), L([['A', 'B', 0], ['B', 'C', 0], ['C', 'A', 0], ['A', 'D', 0], ['D', 'B', 0]]))] });
add('static', 'node-values', "a node's value past its links, a node with a value and no link, a link with no value (NaN restarts the next link's arc at 0), a link value '7'",
  { series: [chord([{ name: 'A', value: 100 }, { name: 'B' }, { name: 'C', value: 12 }, { name: 'D' }, { name: 'E', value: 20 }],
    [{ source: 'A', target: 'B', value: 10 }, { source: 'B', target: 'D' }, { source: 'B', target: 'C', value: 6 },
      { source: 'D', target: 'A', value: '7' }, { source: 'C', target: 'A', value: 4 }])] });
add('static', 'keys', "`nodes` and `edges`: ids beat names, a numeric end is an index, a string end a key, a link to nowhere dropped",
  { series: [{ type: 'chord', nodes: [{ id: 'x', name: 'X' }, { name: 'Y' }, { id: 'z', name: 'Z' }, 'w'],
    edges: [{ source: 'x', target: 'Y', value: 5 }, { source: 1, target: 'z', value: 4 }, { source: 'X', target: 'z', value: 9 },
      { source: '3', target: 0, value: 2 }, { source: 2, target: 0, value: 3 }, { source: 3, target: 1, value: 1 }] }] });
add('static', 'noedges', 'nodes and no links: the layout never runs, nothing is drawn',
  { series: [chord(N(['A', 'B', 'C']), [])] });
add('static', 'two-series', 'two chords side by side, the second clockwise false: the palette continues across them',
  { series: [chord(...D3, { center: ['25%', '50%'], radius: ['40%', '50%'] }),
    chord(N(['P', 'Q', 'R', 'A']), L([['P', 'Q', 3], ['Q', 'R', 5], ['R', 'A', 2]]), { center: ['75%', '50%'], radius: ['40%', '50%'], clockwise: false })] });

// ---- the legend
add('legend', 'legend-selected', 'a legend with B switched off: B and its links are gone, the layout redone, the colours kept',
  { legend: { selected: { B: false } }, series: [chord(...D6)] });
add('legend', 'legend-toggle', 'legend actions: C off, A toggled off, C back on',
  { legend: {}, series: [chord(...D6)] }, { steps: [
    { action: { type: 'legendUnSelect', name: 'C' } },
    { action: { type: 'legendToggleSelect', name: 'A' } },
    { action: { type: 'legendSelect', name: 'C' } }] });

// ---- the states
add('state', 'state-adjacency', "highlight a node and a link, focus 'adjacency' by default: the rest blurred",
  { series: [chord(...D6)] }, { steps: [
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
    { action: { type: 'downplay', seriesIndex: 0, dataIndex: 0 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 3 } },
    { action: { type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: 3 } },
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 3 } }] });
add('state', 'state-declared', "declared emphasis / blur styles: a node's emphasis colour, the links' emphasis lineStyle colour and opacity, blur opacities",
  { series: [chord(...D6, { emphasis: { itemStyle: { color: '#ff0000' }, lineStyle: { color: '#00ff00', opacity: 0.8 } },
    blur: { itemStyle: { opacity: 0.3 }, lineStyle: { opacity: 0.05 }, label: { opacity: 0.4 } } })] }, { steps: [
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
    { action: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 0 } }] });
add('state', 'state-label', 'labels hidden at rest, shown by the emphasis state: the text exists and only the state shows it',
  { series: [chord(...D3, { label: { show: false }, emphasis: { label: { show: true } } })] }, { steps: [
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
    { action: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] });
add('state', 'state-focus', "focus 'self' on the series, 'none' on one link, 'series' on one node",
  { series: [chord([{ name: 'A' }, { name: 'B', emphasis: { focus: 'series' } }, { name: 'C' }, { name: 'D' }],
    [{ source: 'A', target: 'B', value: 40 }, { source: 'B', target: 'C', value: 20, emphasis: { focus: 'none' } },
      { source: 'C', target: 'A', value: 10 }, { source: 'D', target: 'A', value: 5 }], { emphasis: { focus: 'self' } })] }, { steps: [
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
    { action: { type: 'downplay', seriesIndex: 0, dataIndex: 0 } },
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
    { action: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 1 } },
    { action: { type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: 1 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 2 } }] });

// ---- the pointer: hover, tooltip, click
const TIP = { tooltip: { renderMode: 'richText' } };
add('hover', 'hover-basic', 'hover nodes and ribbons through the handler: emphasis, the adjacency blur, the tooltip; clicks on a node and a ribbon',
  Object.assign({}, TIP, { series: [chord(...D6, { name: 'Flows' })] }), { steps: [
    { hover: { node: 0 } }, { hover: { node: 3 } }, { hover: { edge: 1 } }, { hover: { edge: 5 } }, { leave: true },
    { click: { node: 2 } }, { click: { edge: 0 } }, { hover: { node: 5 } }, { leave: true }] });
add('hover', 'hover-filtered', 'a legend filtered B out: the links renumbered (dataIndex vs raw), hovered and clicked',
  Object.assign({}, TIP, { legend: { selected: { B: false } }, series: [chord(...D6)] }), { steps: [
    { hover: { edge: 3 } }, { hover: { edge: 8, depth: 6 } }, { click: { edge: 4 } }, { hover: { node: 3 } }, { leave: true }] });
add('hover', 'hover-nameless', "nameless nodes and an unvalued node: the tooltip's empty name, the layout value",
  Object.assign({}, TIP, { series: [chord([{ value: 5 }, { name: 'B' }, 7], [{ source: 0, target: 1, value: 3 }, { source: 1, target: 2, value: 2 }, { source: 2, target: 0 }])] }), { steps: [
    { hover: { node: 0 } }, { hover: { node: 1 } }, { hover: { edge: 0 } }, { click: { node: 1 } }, { leave: true }] });

// ---- the conversions
add('convert', 'convert', 'convertToPixel / convertFromPixel / containPixel on a chord: no coordinate system, nothing answers',
  { series: [chord(...D3)] }, { convert: [
    ['to', { seriesIndex: 0 }, [1, 2]], ['from', { seriesIndex: 0 }, [300, 200]], ['contain', { seriesIndex: 0 }, [300, 200]],
    ['contain', { seriesIndex: 0 }, [300, 50]], ['contain', { seriesIndex: 0 }, [5, 5]]] });

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  const fails = [];
  const chart = mk(c.W, c.H);
  const events = [];
  chart.on('click', p => events.push(eventRec(p)));
  const tipRec = { which: null };
  try {
    quiet(() => chart.setOption(clone(c.option)));
    hookTooltip(chart, tipRec);
    paint(chart);
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option) };
    rec.series = readSeries(chart, c, fails);
    rec.legend = readLegend(chart);
    rec.steps = [];
    rec.states = [{ events: [], tip: null, els: readEls(chart) }];
    (c.steps || []).forEach((step, i) => {
      const where = c.id + ' step ' + i;
      tipRec.which = null;
      events.length = 0;
      let out;
      if (step.hover !== undefined) {
        const p = resolvePoint(chart, step.hover, where);
        fire(chart, 'mousemove', { zrX: p[0], zrY: p[1] });
        out = { hover: p };
      }
      else if (step.click !== undefined) {
        const p = resolvePoint(chart, step.click, where);
        fire(chart, 'mousemove', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mousedown', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mouseup', { zrX: p[0], zrY: p[1] });
        fire(chart, 'click', { zrX: p[0], zrY: p[1] });
        out = { click: p };
      }
      else if (step.leave) {
        fire(chart, 'mousemove', { zrX: -10, zrY: -10 });
        out = { leave: true };
      }
      else if (step.action) {
        quiet(() => chart.dispatchAction(clone(step.action)));
        out = { action: clone(step.action) };
      }
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      paint(chart);
      rec.steps.push(out);
      const st = { events: events.splice(0), tip: null, els: readEls(chart) };
      if (step.hover !== undefined || step.leave || step.click !== undefined) st.tip = tipNow(chart, tipRec, where);
      if (step.action) {
        st.series = readSeries(chart, c, fails);
        st.legend = readLegend(chart);
      }
      rec.states.push(st);
    });
    if (c.convert) rec.convert = runConvert(chart, c.convert);
    rec.fails = fails;
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// the animations (animation.js' harness: its clock, samples and records)
// ---------------------------------------------------------------------------
const AW = 400;
const AH = 300;
const SAMPLES = [0, 1, 16, 50, 100, 250, 500, 750, 999, 1000, 1001, 1500];
const FNS = { 'idx*50': idx => idx * 50, 'idx*30': idx => idx * 30, 'dur:600+idx*100': idx => 600 + idx * 100 };
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    if (typeof v.$fn === 'string') {
      must(FNS[v.$fn], 'unknown $fn ' + v.$fn);
      return FNS[v.$fn];
    }
    const o = {};
    for (const k of Object.keys(v)) o[k] = materialize(v[k]);
    return o;
  }
  return v;
}
function fnName(f) {
  for (const k of Object.keys(FNS)) if (FNS[k] === f) return { $fn: k };
  return { $fn: '?' };
}
const optVal = v => (typeof v === 'function' ? fnName(v) : v === undefined ? null : v);
const TRANSFORM_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation', 'originX', 'originY', 'skewX', 'skewY'];
const STYLE_KEYS = ['opacity', 'fill', 'stroke', 'lineWidth', 'text', 'x', 'y', 'fillOpacity', 'strokeOpacity'];
const text = v => (Object.is(v, -0) ? '-0' : String(v));
function flatNums(v, out) {
  for (let i = 0; i < v.length; i++) {
    const e = v[i];
    if (e != null && typeof e === 'object' && e.length != null) flatNums(e, out);
    else out.push(typeof e === 'number' ? e : NaN);
  }
  return out;
}
function encA(v) {
  if (typeof v === 'number') return [hex(v), text(v)];
  if (typeof v === 'string' || typeof v === 'boolean') return [v, v];
  if (v && typeof v === 'object' && v.length != null && typeof v !== 'string') {
    const f = flatNums(v, []);
    return [f.map(hex), f.map(text)];
  }
  if (v && typeof v === 'object' && v.colorStops) {
    const s = JSON.stringify(v);
    return [s, s];
  }
  return undefined;
}
function snap(el) {
  const o = {};
  const put = (k, v) => {
    const e = encA(v);
    if (e !== undefined) o[k] = e;
  };
  for (const k of TRANSFORM_KEYS) if (typeof el[k] === 'number') put(k, el[k]);
  put('ignore', !!el.ignore);
  if (el.invisible != null) put('invisible', !!el.invisible);
  if (el.style) for (const k of STYLE_KEYS) if (el.style[k] != null) put('style.' + k, el.style[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (el.shape[k] != null) put('shape.' + k, el.shape[k]);
  return o;
}
const sameJ = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function walkView(root) {
  const out = [];
  const visit = (el, p) => {
    out.push({ el, role: 'el', path: p });
    const cl = el.getClipPath && el.getClipPath();
    if (cl) out.push({ el: cl, role: 'clip', path: p + '#clip' });
    const label = el.getTextContent && el.getTextContent();
    if (label) out.push({ el: label, role: 'label', path: p + '#label' });
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    if (guide) out.push({ el: guide, role: 'guide', path: p + '#guide' });
    if (el.isGroup) el.childrenRef().forEach((ch, i) => visit(ch, p === '' ? String(i) : p + '.' + i));
  };
  visit(root, '');
  return out;
}
function views(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const v = chart.getViewOfSeriesModel(s);
    if (v) out.push({ owner: 'series' + s.seriesIndex + ':' + s.subType, series: true, group: v.group });
  });
  (chart._componentsViews || []).forEach(v => {
    const m = v.__model;
    if (m && v.group) out.push({ owner: m.mainType + m.componentIndex, series: false, group: v.group });
  });
  return out;
}
function clipCount(z) {
  let n = 0;
  for (let cl = z.animation._head; cl; cl = cl.next) n++;
  return n;
}
function recordTimeline(chart, start) {
  const z = chart.getZr();
  const ids = new Map();
  const recs = [];
  const clips = [];
  SAMPLES.forEach((t, si) => {
    NOW = start + t;
    if (si === 0) {
      for (let cl = z.animation._head; cl; cl = cl.next) must(cl._inited, 'a clip was not stepped by the setOption flush');
    }
    else z.animation.update();
    z.storage.getDisplayList(true);
    clips.push(clipCount(z));
    for (const v of views(chart)) {
      for (const it of walkView(v.group)) {
        let rec = ids.get(it.el);
        if (!rec) {
          const ecd = ecDataOf(it.el);
          rec = { id: v.owner + '/' + (it.path === '' ? 'root' : it.path), owner: v.owner, series: v.series, role: it.role,
            type: it.el.type, dataIndex: ecd && ecd.dataIndex != null ? ecd.dataIndex : null,
            snaps: new Array(SAMPLES.length).fill(null), anim: new Array(SAMPLES.length).fill(0), scopes: new Set() };
          ids.set(it.el, rec);
          recs.push(rec);
        }
        rec.snaps[si] = snap(it.el);
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        (it.el.animators || []).forEach(a => rec.scopes.add(a.scope == null ? '' : a.scope));
      }
    }
  });
  const seen = new Map();
  const elements = [];
  for (const rec of recs) {
    const presentIdx = [];
    rec.snaps.forEach((s, i) => { if (s) presentIdx.push(i); });
    const keys = new Set();
    presentIdx.forEach(i => Object.keys(rec.snaps[i]).forEach(k => keys.add(k)));
    const lastI = presentIdx[presentIdx.length - 1];
    const final = {};
    const finalText = {};
    const track = {};
    const trackText = {};
    for (const k of [...keys].sort()) {
      const vals = presentIdx.map(i => rec.snaps[i][k]);
      const constant = vals.every(v => v !== undefined && sameJ(v[0], vals[0][0]));
      const last = rec.snaps[lastI][k];
      if (last !== undefined) {
        final[k] = last[0];
        finalText[k] = last[1];
      }
      if (!constant) {
        track[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][0] : null));
        trackText[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][1] : null));
      }
    }
    const everAnim = rec.anim.some(n => n > 0);
    if (!rec.series && !everAnim && Object.keys(track).length === 0) continue;
    let id = rec.id + (rec.role !== 'el' && !rec.id.includes('#') ? '#' + rec.role : '');
    const n = seen.get(id) || 0;
    seen.set(id, n + 1);
    if (n) id += '~' + n;
    elements.push({ id, owner: rec.owner, role: rec.role, type: rec.type, dataIndex: rec.dataIndex,
      present: presentIdx.length === SAMPLES.length ? null : presentIdx, final, finalText,
      track: Object.keys(track).length ? track : null, trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null, scopes: [...rec.scopes].sort() });
  }
  return { clips, elements };
}
function resolvedOf(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const g = k => optVal(s.getShallow(k));
    out.push({ seriesIndex: s.seriesIndex, type: s.subType, dataCount: s.getData().count(),
      animationOption: g('animation'), threshold: g('animationThreshold'), enabled: !!s.isAnimationEnabled(),
      duration: g('animationDuration'), easing: g('animationEasing'), delay: g('animationDelay'),
      durationUpdate: g('animationDurationUpdate'), easingUpdate: g('animationEasingUpdate'), delayUpdate: g('animationDelayUpdate') });
  });
  return out;
}
const ACASES = [];
const aadd = (id, note, option) => ACASES.push({ id, note, option: Object.assign({ color: PALETTE }, option) });
aadd('chord.default', "a chord's enter: the view group scales from 0.01 about the centre (cubicOut, 1000 ms, no row), every label fades in at its node",
  { series: [chord(...D3)] });
aadd('chord.override', 'the same, duration 600, quadraticIn, delay 100, a centre off the middle, labels inside',
  { series: [chord(...D4, { animationDuration: 600, animationEasing: 'quadraticIn', animationDelay: 100, center: ['35%', '60%'], label: { position: 'inside' } })] });
aadd('chord.delayFn', 'animationDelay (idx) => idx * 50: the group has no row, the labels have theirs',
  { series: [chord(...D6, { animationDelay: { $fn: 'idx*50' } })] });
aadd('chord.labelsOff', 'labels off: only the group scales',
  { series: [chord(...D3, { label: { show: false }, radius: ['50%', '60%'] })] });

function runAnim(ac) {
  const chart = mk(AW, AH);
  try {
    quiet(() => chart.setOption(materialize(ac.option)));
    const tl = recordTimeline(chart, T0);
    const parts = ac.id.split('.');
    return { id: ac.id, kind: 'enter', chart: parts[0], variant: parts[1], note: ac.note, option: ac.option, next: null,
      W: AW, H: AH, resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements };
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  const s0 = id => cs(id).series[0];
  const num = h => {
    bits.setUint32(0, parseInt(h.slice(0, 8), 16));
    bits.setUint32(4, parseInt(h.slice(8), 16));
    return bits.getFloat64(0);
  };
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  const all = [];
  out.cases.forEach(q => q.series.forEach(s => all.push(s)));
  guard('the defaults: r0 70%, r 80% of half the shorter side', num(s0('basic').nodes[0].layout.r0) === 140 && num(s0('basic').nodes[0].layout.r) === 160);
  guard('the default start is twelve o\'clock (-90 degrees, normalised to 3 pi / 2)', num(s0('basic').nodes[0].layout.startAngle) === 3 * Math.PI / 2);
  guard('the default corners are [0, 0, 5, 5]', s0('basic').nodes[0].el.cr.map(num).join() === '0,0,5,5');
  guard('the nodes are drawn before the ribbons', s0('basic').order.join() === 'n0,n1,n2,e0,e1,e2');
  guard('a ribbon is the source colour at 0.2 by default', s0('basic').edges[0].el.fill === '#5070dd' && num(s0('basic').edges[0].el.opacity) === 0.2);
  guard('a self loop counts twice on its node', num(s0('basic-6').nodes[3].layout.value) === 12 + 5 + 2 + 2);
  guard('endAngle is never read', num(s0('angles').nodes[0].layout.startAngle) === 0);
  guard('ccw runs the sectors backwards', !s0('ccw').nodes[0].layout.clockwise && num(s0('ccw').nodes[0].layout.endAngle) < num(s0('ccw').nodes[0].layout.startAngle));
  guard('a borrowing node has a ratio', s0('minangle-borrow').nodes.some(n => n.layout && n.layout.ratio !== null));
  guard('a tiny node keeps its own tiny angle in the layout (restDeficit ran out)', num(s0('minangle-borrow').nodes[3].layout.angle) < 0.05);
  guard('the scale-all branch ran', s0('minangle-scale').recipe.scaled);
  guard('surplusAsMuchAsPossible ran', s0('minangle-asmuch').recipe.asMuch);
  guard('minAngle cut to fit', num(s0('minangle-big').recipe.minAngle) < 120 * RADIAN);
  guard('padAngle cut to fit', num(s0('pad-big').recipe.padAngle) < 70 * RADIAN);
  guard('a gradient ribbon is a global linear gradient', s0('gradient').edges.some(e => e.el && e.el.fill && e.el.fill.global === true));
  guard("a ribbon to a gradient-coloured node is '#000'", s0('gradient').edges.some(e => e.el && e.el.fill === '#000'));
  guard("a literal link colour fills '#000' and strokes", s0('edge-styles').edges.some(e => e.el && e.el.fill === '#000' && e.el.stroke === '#0000ff'));
  guard("'target' takes the target's colour", s0('edge-styles').edges[2].el.fill === s0('edge-styles').nodes[0].el.fill);
  guard('hideOverlap hides some chord labels', s0('labels-overlap').nodes.some(n => n.el.label.ignore));
  guard('labels default outside, in the node colour', s0('basic').nodes.every(n => n.el.label.fill === n.el.fill && !n.el.label.ignore));
  guard('an inside label centres', s0('labels-inside').nodes[0].el.label.align === 'center' && s0('labels-inside').nodes[0].el.label.va === 'middle');
  guard('a nameless node reads the series name', s0('labels-distance').nodes[1].el.label.text === 'Ser');
  guard('an unnamed series\' nameless node reads its index', s0('labels-index').nodes[0].el.label.text === '0');
  guard('the template takes the layout value for a node with none', s0('labels-inside').nodes[3].el.label.text.indexOf('D:') === 0);
  guard('all nought: the ends count', s0('allzero').nodes.every(n => n.layout));
  guard('a NaN link restarts the arc', s0('node-values').edges.some(e => e.layout && num(e.layout.sStartAngle) === 0));
  guard('a link to nowhere is dropped', s0('keys').edges.length < 6);
  guard('no links: nothing drawn', s0('noedges').nodes.every(n => !n.el && !n.layout));
  guard('the legend filters a node and its links', s0('legend-selected').nodes[1].index === -1
    && s0('legend-selected').edges.filter(e => e.index === -1).length === 3);
  guard('the colours stay put', s0('legend-selected').nodes[2].el.fill === s0('basic-6').nodes[2].el.fill);
  guard('legend actions re-lay the chord', cs('legend-toggle').states[1].series[0].count === 5 && cs('legend-toggle').states[2].series[0].count === 4
    && cs('legend-toggle').states[3].series[0].count === 5);
  const st = cs('state-adjacency').states;
  guard('a highlighted node is in emphasis, its ribbons not blurred', st[1].els.some(e => e.k === 'n' && e.raw === 0 && e.states === 'emphasis')
    && st[1].els.some(e => e.k === 'e' && e.raw === 0 && e.states === ''));
  guard('a far ribbon is blurred', st[1].els.some(e => e.k === 'e' && e.raw === 5 && e.states === 'blur'));
  guard('an emphasised ribbon opacity 0.5', st[3].els.some(e => e.k === 'e' && e.raw === 3 && e.states === 'emphasis' && num(e.opacity) === 0.5));
  guard('an emphasis label shows what the normal one hides', cs('state-label').states[1].els.some(e => e.k === 'n' && e.raw === 1 && e.label && !e.label.ignore)
    && cs('state-label').states[2].els.every(e => e.k !== 'n' || (e.label && e.label.ignore)));
  const hv = cs('hover-basic').states;
  guard('the tooltip names a node', hv.some(q => q.tip && /^item:/.test(q.tip.which)));
  guard('the tooltip names a ribbon by its nodes', hv.some(q => q.tip && /^edge:/.test(q.tip.which) && q.tip.lines.some(l => l.name && l.name.indexOf(' > ') > 0)));
  guard('a click on a ribbon is an edge event', hv.some(q => q.events.some(e => e.dataType === 'edge')));
  guard('a filtered link renumbers', cs('hover-filtered').states.some(q => q.tip && /^edge:/.test(q.tip.which)));
  guard('nothing converts on a chord', cs('convert').convert.every(p => (p.op === 'contain' ? p.out.k === 'bool' && p.out.v === false : p.out.k === 'none')));
  const an = id => out.anim.cases.find(q => q.id === id);
  guard('the group scales from 0.01', an('chord.default').elements.some(e => e.id === 'series0:chord/root' && e.track && e.track.scaleX));
  guard('the labels fade', an('chord.default').elements.some(e => e.role === 'label' && e.track && e.track['style.opacity']));
  guard('every animation settles by 1500', out.anim.cases.every(c => c.clips[c.clips.length - 1] === 0));
  guard('discriminating: a ribbon with a stroke', all.some(s => s.edges.some(e => e.el && e.el.stroke === '#0000ff')));
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off (the tooltip view), 600 x 400 (the animations 400 x 300), the ECharts 6 palette at the root.',
      'static cases: animation false; a paint (renderToSVGString) after setOption and after every step builds every path.',
      'pointer steps go through zrender\'s Handler; a click is mousemove, mousedown, mouseup, click at one point.',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart.',
      'anim: animation.js\' harness -- the Date hook, the samples, the element records.',
    ],
    cases: CASES.map(runCase),
    anim: { samplesMs: SAMPLES, clock: { T0 }, cases: ACASES.map(runAnim) },
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
if (process.env.ORACLE_FORCE) fs.writeFileSync(OUT, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
out1.cases.forEach(q => q.fails.slice(0, 8).forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
console.log(out1.cases.length + ' cases, ' + out1.anim.cases.length + ' animation cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
