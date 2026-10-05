// Upstream's own answers for graph hover focus: emphasis.focus 'adjacency' /
// 'self' / 'series' / none, the blur it spreads, the blurScope it spreads
// over, and the emphasis / blur looks each element takes, for the port to be
// held to (batch 46 audit, wf46/audit46.md SS1 and SS3).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, 400x300), drives
// each case by zrender pointer events (mousemove at an integer point; leave =
// a mousemove outside the canvas, which zrender treats as the pointer having
// left), runs a frame after every step (chart._onframe, so the hover flags
// have turned into element states) and reads the live elements -- never the
// SVG text.
//
// The recipe (SS1; every option below sets layout 'none', explicit x/y, and a
// box equal to the data extent, so the view is the identity and a node's
// symbol-path scale IS its pixel half-extent -- the generator checks it):
//   focus   node: data[i].emphasis.X ?? categories[cat].emphasis.X ??
//           series.emphasis.X; edge: links[j].emphasis.X ?? series.emphasis.X
//           (X = focus, blurScope, disabled, scale). Legacy: series
//           focusNodeAdjacency != null (false too) with emphasis.focus == null
//           means 'adjacency'
//   mode    falsy or 'none' -> none; 'series'; 'adjacency' (exact); any other
//           truthy value -> self
//   rows    node row = position among the rendered (legend-kept) nodes; edge
//           row = position among the valid, surviving links (both ends
//           rendered). Upstream's dataIndex is the row; the fixture keys edges
//           by LINK (their index in option links) and nodes by NAME
//   sets    node n: edges = its incident edges (a self-loop once), nodes =
//           both ends of each (duplicates kept; an isolated node: both
//           empty, so the node itself is NOT listed); edge e: {edges [e],
//           nodes [n1, n2]}
//   hover   on element X of series s (its symbol, its label, or its line):
//           1 everything returns to N (the previous hover is left first)
//           2 X disabled -> stop (nothing changes, X included)
//           3 mode none -> X is E, stop
//           4 series t is blurred unless blurScope 'series' and t != s, or
//             blurScope 'coordinateSystem' (the default) and t is on another
//             coordinate system (each view graph owns one), or mode 'series'
//             and t = s
//           5 in every blurred t: every element B (symbol, label, line,
//             arrowheads); mode adjacency: the node ROWS and edge ROWS of X's
//             sets go back to N in t (t != s too: the index leak)
//           6 X is E (over its own B)
//   leave   everything N
//   looks   (normal = the element's rest value; lift(c) = each channel
//           c * (1 - (-0.1)) | 0, clamped at 255)
//     node B    opacity = blur.itemStyle.opacity (item ?? category ?? series)
//               ?? normal * 0.1; nothing else changes
//     node E    fill = emphasis.itemStyle.color ?? lift(fill); stroke and
//               lineWidth from emphasis.itemStyle.borderColor / borderWidth;
//               opacity unchanged; half = normal half * ratio, ratio =
//               max(1.1, 3 / (symbolSize[1] / 2)) for scale null/true, a
//               finite scale > 0 as is, else 1; z2 + 10
//     label     B: blur.label.opacity (cascade) ?? normal * 0.1; E: opacity
//               unchanged, z2 + 10, shown (emphasis.label.show defaults true)
//     edge B    opacity = blur.lineStyle.opacity (link ?? series) ?? normal
//               * 0.1
//     edge E    stroke = emphasis.lineStyle.color ?? lift(stroke); lineWidth
//               and opacity from emphasis.lineStyle or unchanged (no width
//               boost); z2 + 10 (0 -> 10: still below every node's 100)
//     arrows    follow the line: B = the declared blur.lineStyle.opacity ??
//               their own normal * 0.1; E fill = the line's E stroke,
//               opacity = emphasis.lineStyle.opacity ?? unchanged
//     disabled  an element with emphasis.disabled still takes the B STATE
//               when another hover blurs it, but it has no default-state
//               proxy (toggleHoverEmphasis never installs one): only a
//               DECLARED blur opacity changes it; with none it keeps its
//               normal look (symbol, label, line and arrowheads alike)
//     N         every field equals the rest record
//
// The fixture, top level:
//   source   'ECharts <version>'
//   cases[]  below
//
// Per case:
//   name, group        group 'G1'..'G7' (compared) or 'D' (documentary), as
//                      in audit46.md SS3
//   W, H               400, 300
//   option             the option as run (JSON), fed to setOption
//   steps[]            each an object with exactly ONE key:
//     hover [x, y]     an integer client point; mousemove there
//     leave true       the pointer leaves the canvas (the port: MouseLeave)
//     action {...}     documentary only: dispatchAction(payload)
//   records[]          index-parallel to [rest, after step 1, ...]:
//     hit              null at rest, after a leave and after an action; else
//                      what zrender's findHover answers at the point, walked
//                      up to the element carrying the datum:
//                      {kind:'node', series, name, via:'symbol'|'label'} |
//                      {kind:'edge', series, link, via:'line'|'arrow'|
//                      'edgeLabel'} | {kind:'item', series, dataIndex, via}
//                      (a non-graph series) | {kind:'component', component}
//                      (a legend item: its ECData ssrType) | {kind:'none'}
//     series[]         one per GRAPH series, in series index order:
//       index
//       nodes[]        the rendered nodes in data order:
//         name, row    row = upstream dataIndex (== the port's view row)
//         state        'N' | 'B' | 'E' (from the symbol path's currentStates)
//         opacity      the symbol's style.opacity after states apply
//         fill, fillBytes      zrender's string and its [r, g, b, a] bytes
//                              (a = round(alpha * 255))
//         stroke, strokeBytes, lineWidth   null (all three) when there is no
//                              border, else the border
//         half         [sx, sy]: the symbol path's scale (= the pixel half-
//                      extents: the view is the identity)
//         z2           integer (compare the ORDER it implies, not the value)
//         label        null | {state, opacity, ignore, z2}
//       edges[]        the surviving edges in upstream row order:
//         link, row    link = index in option links (the port's Row); row =
//                      upstream dataIndex
//         zeroLength   the line is a point (a straight self-loop: the port
//                      emits no element for it, N4) -- skip it
//         state, opacity, stroke, strokeBytes, lineWidth, z2
//         fromArrow, toArrow   null | {state, opacity, fill, fillBytes}
//     others[]         documentary, non-graph series only: {index, type,
//                      items: [{state, opacity}]}
//   documentary, note  recorded for the reader, no port assertion
//   deferred, why      a self-check failed by design
//   pixelGuard         the case carries a pixel guard (audit SS3)
//   discriminates      per wrong model, how many of the case's records it
//                      gets wrong (below); totals over the compared cases
//                      must each be >= 1
//
// Every Double (opacity, lineWidth, half) is the 16 lowercase hex digits of
// its IEEE-754 bits (big-endian) with a readable twin beside it: `k` hex,
// `kText` text (arrays parallel). A non-finite number is null with its twin
// 'NaN' / 'Infinity' / '-Infinity'; null + null = absent. Pointer points,
// indices, z2 and colour bytes are plain integers.
//
// Wrong models (discriminates): each is the reference predictor with one
// mutation; a record counts when the mutated prediction differs from it.
//   neighboursWouldBeE     adjacency members become E instead of N
//   isolatedSelfKept       a node's set always lists the node itself (seen
//                          only through the global index leak)
//   emptySetBlursNothing   an isolated node's hover blurs nothing
//   sharedEndEdgeKept      an edge hover also keeps the edges sharing an end
//   seriesOnlyEmphasis     focus/blurScope/disabled/scale read at series level
//   labelHitToNode         a label hit is not mapped to its node (no change)
//   arrowDatum             arrowheads keep datum -1 (stay N)
//   labelNoState           captions do not follow their node
//   unknownFocusIsNone     'adjacency'-less truthy values (true, 'foo') = none
//   legacyFalseIsNone      focusNodeAdjacency:false gives no focus
//   seriesModeBlursOwn     focus 'series' blurs its own series (like self)
//   scopeIgnored           the default scope blurs the other view graph
//   globalWithoutLeak      global adjacency blurs other series fully
//   leaveKeepsBlur         a leave changes nothing
//   declaredBlurMultiplied a declared blur opacity is also multiplied by 0.1
//   ratioFromWidth         the scale ratio reads symbolSize[0]
//   declaredColourIgnored  an explicit emphasis colour is lifted over
//   crossedEmphasisStyles  node and edge emphasis styles overlaid into one
//   edgeWidthBoost         a hovered edge gains 1px of width
//   noZ2Lift               no z2 lift on emphasis
//   edgeLiftAboveNodes     a hovered edge is lifted above the nodes
//   disabledBlurDims       a disabled element blurred by another hover dims
//                          by 0.1 like the others
//   rowNotLink             (count) surviving edges whose row != link
//   translucentEmphasis    (count) E edges with opacity < 1, where an overlay
//                          double draw shows
//
// Self-checks (the fixture is not written and the run exits 1 when a case not
// declared deferred fails any):
//   1  every hover point: the hit names the element the case aims at, and
//      the point is unambiguous for a port that hit-tests the symbol shape and
//      edges with a 4px slop (a node centre: outside every other symbol and
//      label grown by 4; an edge midpoint: within 1px of its line, outside
//      every symbol and label grown by 4 and farther than 4 + lw/2 from every
//      other line; a label centre: 2px inside its box, outside every symbol
//      and other label grown by 4, farther than 4 + lw/2 from every line)
//   2  every leave record deep-equals the rest record
//   3  values: the reference predictor (looks above, from the option and the
//      rest record) equals every record, field by field
//   4  states: the SS1.2 pattern recomputed from the option alone (links,
//      names, cascade, legend filter, scope) equals every record's states
//      (symbols, labels, lines, arrowheads)
//   5  the edge keys are a bijection onto the valid, surviving links, and
//      the node names onto the rendered nodes
//   6  every chart is disposed in a finally (created == disposed)
//   d  the whole fixture is generated twice in the process and the two JSON
//      texts are byte-identical
//   c  every discriminates total is >= 1
//
//   node tools/advchart-oracle/focus-adjacency.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-graph-focus.json');

class OracleError extends Error {}
function must(cond, msg) { if (!cond) throw new OracleError(msg); }
const clone = v => JSON.parse(JSON.stringify(v));

// upstream logs deprecations (focusNodeAdjacency); keep them off the report
const warnings = [];
console.warn = (...a) => warnings.push(a.join(' '));

// ---------- number writing ----------

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function hx(v) {
  if (v == null) return null;
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (!Number.isFinite(v)) return null;
  return hex(v);
}
const tx = v => (v == null ? null : Object.is(v, -0) ? '-0' : String(v));
function put(o, k, v) {
  if (Array.isArray(v)) { o[k] = v.map(hx); o[k + 'Text'] = v.map(tx); }
  else { o[k] = hx(v); o[k + 'Text'] = tx(v); }
  return o;
}

// ---------- colours (own parser, cross-checked against zrender's) ----------

function parseColour(s) {
  if (s == null || s === 'none') return null;
  must(typeof s === 'string', 'a colour that is not a string: ' + JSON.stringify(s));
  let r, g, b, a = 1;
  let m;
  if ((m = /^#([0-9a-f]{3})$/i.exec(s))) {
    [r, g, b] = m[1].split('').map(h => parseInt(h + h, 16));
  } else if ((m = /^#([0-9a-f]{6})$/i.exec(s))) {
    r = parseInt(m[1].slice(0, 2), 16); g = parseInt(m[1].slice(2, 4), 16); b = parseInt(m[1].slice(4, 6), 16);
  } else if ((m = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/.exec(s))) {
    r = +m[1]; g = +m[2]; b = +m[3]; if (m[4] != null) a = +m[4];
  } else if (s === 'red') { r = 255; g = 0; b = 0; }
  else throw new OracleError('an unparsed colour ' + s);
  const bytes = [r, g, b, Math.round(a * 255)];
  const z = echarts.color.parse(s);
  must(z && z[0] === r && z[1] === g && z[2] === b && z[3] === a, 'colour parsers disagree on ' + s + ': ' + JSON.stringify(z));
  return bytes;
}
// states.ts liftColor = zrender lift(c, -0.1)
function liftBytes(bytes) {
  return bytes.slice(0, 3).map(c => Math.min(255, Math.max(0, c * (1 - (-0.1)) | 0))).concat([bytes[3]]);
}
const sameBytes = (a, b) => (a === null ? b === null : b !== null && a.length === b.length && a.every((v, i) => v === b[i]));

// ---------- the live chart ----------

let created = 0, disposed = 0;
function mk(W, H) {
  created++;
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}
function kill(chart) { chart.dispose(); disposed++; }
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1, target: null }, extra); }
function moveTo(chart, x, y) {
  chart.getZr().handler.dispatch('mousemove', zev({ zrX: x, zrY: y, offsetX: x, offsetY: y }));
  chart._onframe();
}
function settle(chart) { chart.renderToSVGString(); chart._onframe(); }

function ecData(el) {
  for (const k of Object.keys(el)) {
    if (k.indexOf('__ec_inner_') !== 0) continue;
    const v = el[k];
    if (v && typeof v === 'object' && ('dataIndex' in v || 'seriesIndex' in v || 'componentMainType' in v)) return v;
  }
  return null;
}
const optionSeries = option => (Array.isArray(option.series) ? option.series : [option.series]);
function linksOf(s) { return s.option.links || s.option.edges || []; }
function stateOf(el) {
  const cs = el.currentStates || [];
  return cs.indexOf('emphasis') >= 0 ? 'E' : cs.indexOf('blur') >= 0 ? 'B' : 'N';
}
const HOVER = ['N', 'B', 'E'];
const opac = el => (el.style.opacity == null ? 1 : el.style.opacity);

// the rendered elements of one graph series, by name / link
function graphEls(s) {
  const d = s.getData();
  const nodes = [];
  for (let i = 0; i < d.count(); i++) {
    const g = d.getItemGraphicEl(i);
    if (!g) continue;
    nodes.push({ name: d.getName(i), row: i, g, path: g.childAt(0) });
  }
  const e = s.getEdgeData();
  const links = linksOf(s);
  const edges = [];
  for (let i = 0; i < e.count(); i++) {
    const g = e.getItemGraphicEl(i);
    if (!g) continue;
    const link = links.indexOf(e.getRawDataItem(i));
    must(link >= 0, 'an edge whose raw item is not in option links (row ' + i + ')');
    edges.push({ link, row: i, g, line: g.childOfName('line') });
  }
  return { nodes, edges };
}

function snapColour(o, k, s) {
  o[k] = s == null ? null : s;
  o[k + 'Bytes'] = parseColour(s);
}
function snapNode(n, viewGraph) {
  const p = n.path;
  const st = stateOf(p);
  must(HOVER[p.hoverState || 0] === st, 'node ' + n.name + ': hoverState and currentStates disagree');
  if (viewGraph) {
    const m = n.g.getComputedTransform();
    must(!m || (m[0] === 1 && m[3] === 1 && m[1] === 0 && m[2] === 0), 'node ' + n.name + ': the view is not the identity');
  }
  const o = { name: n.name, row: n.row, state: st, opacity: opac(p) };
  snapColour(o, 'fill', p.style.fill);
  const border = p.style.stroke != null && p.style.stroke !== 'none' && p.style.lineWidth > 0;
  if (border) { snapColour(o, 'stroke', p.style.stroke); o.lineWidth = p.style.lineWidth; }
  else { o.stroke = null; o.strokeBytes = null; o.lineWidth = null; }
  o.rawLineWidth = p.style.lineWidth;   // internal: the predictor's base
  o.half = [p.scaleX, p.scaleY];
  o.z2 = p.z2;
  const lab = p.getTextContent && p.getTextContent();
  o.label = lab ? { state: stateOf(lab), opacity: opac(lab), ignore: !!lab.ignore, z2: lab.z2 } : null;
  return o;
}
function snapArrow(a) {
  if (!a) return null;
  const o = { state: stateOf(a), opacity: opac(a) };
  snapColour(o, 'fill', a.__isEmptyBrush ? a.style.stroke : a.style.fill);
  return o;
}
function snapEdge(e) {
  const l = e.line;
  const st = stateOf(l);
  must(HOVER[l.hoverState || 0] === st, 'edge ' + e.link + ': hoverState and currentStates disagree');
  const sh = l.shape;
  const o = { link: e.link, row: e.row,
    zeroLength: sh.x1 === sh.x2 && sh.y1 === sh.y2 && (sh.cpx1 == null || isNaN(+sh.cpx1)),
    state: st, opacity: opac(l) };
  snapColour(o, 'stroke', l.style.stroke);
  o.lineWidth = l.style.lineWidth;
  o.z2 = l.z2;
  o.fromArrow = snapArrow(e.g.childOfName('fromSymbol'));
  o.toArrow = snapArrow(e.g.childOfName('toSymbol'));
  return o;
}
function snapshot(chart, hit) {
  const series = [];
  const others = [];
  chart.getModel().eachSeries(s => {
    if (s.subType === 'graph') {
      const els = graphEls(s);
      const view = s.coordinateSystem && s.coordinateSystem.type === 'view';
      series.push({ index: s.seriesIndex, nodes: els.nodes.map(n => snapNode(n, view)), edges: els.edges.map(snapEdge) });
    } else {
      const d = s.getData();
      const items = [];
      for (let i = 0; i < d.count(); i++) {
        const g = d.getItemGraphicEl(i);
        items.push(g ? { state: stateOf(g), opacity: opac(g) } : null);
      }
      others.push({ index: s.seriesIndex, type: s.subType, items });
    }
  });
  const r = { hit, series };
  if (others.length) r.others = others;
  return r;
}

// what zrender answers at (x, y), walked up (findEventDispatcher's walk) to
// the element that carries the datum
function hitAt(chart, x, y) {
  const h = chart.getZr().handler.findHover(x, y);
  let el = h.target;
  if (!el) return { kind: 'none' };
  let via = null;
  let viaLabel = false;
  while (el) {
    if (!via) {
      if (el.name === 'line') via = 'line';
      else if (el.name === 'fromSymbol' || el.name === 'toSymbol') via = 'arrow';
    }
    if (el.type === 'text' && el.__hostTarget) viaLabel = true;
    const ec = ecData(el);
    // a component's element (a legend item) carries a series datum too: its ssrType tells
    if (ec && ec.ssrType && ec.ssrType !== 'chart') return { kind: 'component', component: ec.ssrType };
    if (ec && ec.seriesIndex != null && ec.dataIndex != null) {
      const s = chart.getModel().getSeriesByIndex(ec.seriesIndex);
      if (s.subType === 'graph' && ec.dataType === 'edge') {
        return { kind: 'edge', series: ec.seriesIndex, link: linksOf(s).indexOf(s.getEdgeData().getRawDataItem(ec.dataIndex)),
          via: viaLabel ? 'edgeLabel' : via || 'line' };
      }
      if (s.subType === 'graph') {
        return { kind: 'node', series: ec.seriesIndex, name: s.getData().getName(ec.dataIndex), via: viaLabel ? 'label' : 'symbol' };
      }
      return { kind: 'item', series: ec.seriesIndex, dataIndex: ec.dataIndex, via: viaLabel ? 'label' : 'shape' };
    }
    if (ec && ec.componentMainType) return { kind: 'component', component: ec.componentMainType };
    el = el.__hostTarget || el.parent;
  }
  return { kind: 'none' };
}

// ---------- geometry at rest: aim points and the unambiguity check ----------

function globalRect(el) {
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return [r.x, r.y, r.width, r.height];
}
function restGeometry(chart) {
  const geo = { nodes: [], labels: [], edges: [], edgeLabels: [], legend: [] };
  chart.getModel().eachSeries(s => {
    if (s.subType !== 'graph') return;
    const els = graphEls(s);
    for (const n of els.nodes) {
      const m = n.path.getComputedTransform();
      geo.nodes.push({ series: s.seriesIndex, name: n.name, c: [m[4], m[5]], half: [Math.abs(m[0]), Math.abs(m[3])] });
      const lab = n.path.getTextContent();
      if (lab && !lab.ignore) geo.labels.push({ series: s.seriesIndex, name: n.name, box: globalRect(lab) });
    }
    for (const e of els.edges) {
      const l = e.line;
      const sh = l.shape;
      const p1 = l.transformCoordToGlobal(sh.x1, sh.y1), p2 = l.transformCoordToGlobal(sh.x2, sh.y2);
      const curved = !(sh.cpx1 == null || isNaN(+sh.cpx1));
      const mid = l.pointAt(0.5);
      geo.edges.push({ series: s.seriesIndex, link: e.link, p1, p2, curved, lw: l.style.lineWidth || 1,
        mid: l.transformCoordToGlobal(mid[0], mid[1]) });
      const lab = e.g.getTextContent && e.g.getTextContent();
      if (lab && !lab.ignore) geo.edgeLabels.push({ series: s.seriesIndex, link: e.link, box: globalRect(lab) });
    }
  });
  chart._componentsViews.filter(v => v.type === 'legend.plain').forEach(lv => {
    lv.getContentGroup().children().forEach(g => { geo.legend.push({ box: globalRect(g) }); });
  });
  return geo;
}
function segDist(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  const L2 = dx * dx + dy * dy;
  let t = L2 ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2 : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}
const SLOP = 4;
const inEllipse = (p, n, grow) => ((p[0] - n.c[0]) / (n.half[0] + grow)) ** 2 + ((p[1] - n.c[1]) / (n.half[1] + grow)) ** 2 <= 1;
const inBox = (p, b, grow) => p[0] >= b[0] - grow && p[0] <= b[0] + b[2] + grow && p[1] >= b[1] - grow && p[1] <= b[1] + b[3] + grow;
// problems with aiming `aim` at point p (empty = unambiguous)
function ambiguity(geo, aim, p) {
  const bad = [];
  const sr = aim.series || 0;
  const isN = n => aim.node != null && n.series === sr && n.name === aim.node;
  const isLabOf = l => aim.label != null && l.series === sr && l.name === aim.label;
  const isE = e => aim.edge != null && e.series === sr && e.link === aim.edge;
  if (aim.node != null) {
    const me = geo.nodes.find(isN);
    must(me, 'no node ' + aim.node);
    if (!(((p[0] - me.c[0]) / me.half[0]) ** 2 + ((p[1] - me.c[1]) / me.half[1]) ** 2 <= 0.25)) bad.push('not well inside its symbol');
    geo.nodes.forEach(n => { if (!isN(n) && inEllipse(p, n, SLOP)) bad.push('near node ' + n.name); });
    geo.labels.forEach(l => { if (!(l.series === sr && l.name === aim.node) && inBox(p, l.box, SLOP)) bad.push('near label ' + l.name); });
  } else if (aim.edge != null) {
    const me = geo.edges.find(isE);
    must(me && !me.curved, 'no straight edge ' + aim.edge);
    if (segDist(p, me.p1, me.p2) > 1) bad.push('more than 1px off its line');
    geo.nodes.forEach(n => { if (inEllipse(p, n, SLOP)) bad.push('near node ' + n.name); });
    geo.labels.forEach(l => { if (inBox(p, l.box, SLOP)) bad.push('near label ' + l.name); });
    geo.edges.forEach(e => { if (!isE(e) && !e.curved && segDist(p, e.p1, e.p2) <= SLOP + e.lw / 2) bad.push('near edge ' + e.link); });
  } else if (aim.label != null) {
    const me = geo.labels.find(isLabOf);
    must(me, 'no label ' + aim.label);
    if (!inBox(p, me.box, -2)) bad.push('not 2px inside its box');
    geo.nodes.forEach(n => { if (inEllipse(p, n, SLOP)) bad.push('near node ' + n.name); });
    geo.labels.forEach(l => { if (!isLabOf(l) && inBox(p, l.box, SLOP)) bad.push('near label ' + l.name); });
    geo.edges.forEach(e => { if (!e.curved && segDist(p, e.p1, e.p2) <= SLOP + e.lw / 2) bad.push('near edge ' + e.link); });
  }
  return bad;
}
function aimPoint(geo, aim) {
  const sr = aim.series || 0;
  if (aim.at) return aim.at.slice();
  if (aim.node != null) { const n = geo.nodes.find(q => q.series === sr && q.name === aim.node); must(n, 'no node ' + aim.node); return n.c.map(Math.round); }
  if (aim.edge != null) { const e = geo.edges.find(q => q.series === sr && q.link === aim.edge); must(e, 'no edge ' + aim.edge); return e.mid.map(Math.round); }
  const ctr = b => [Math.round(b[0] + b[2] / 2), Math.round(b[1] + b[3] / 2)];
  if (aim.label != null) { const l = geo.labels.find(q => q.series === sr && q.name === aim.label); must(l, 'no label ' + aim.label); return ctr(l.box); }
  if (aim.edgeLabel != null) { const l = geo.edgeLabels.find(q => q.series === sr && q.link === aim.edgeLabel); must(l, 'no edge label ' + aim.edgeLabel); return ctr(l.box); }
  if (aim.legend != null) { must(geo.legend[aim.legend], 'no legend item ' + aim.legend); return ctr(geo.legend[aim.legend].box); }
  throw new OracleError('an aim without a target ' + JSON.stringify(aim));
}
function expectedHit(aim) {
  const sr = aim.series || 0;
  if (aim.node != null) return { kind: 'node', series: sr, name: aim.node, via: 'symbol' };
  if (aim.label != null) return { kind: 'node', series: sr, name: aim.label, via: 'label' };
  if (aim.edge != null) return { kind: 'edge', series: sr, link: aim.edge, via: 'line' };
  if (aim.edgeLabel != null) return { kind: 'edge', series: sr, link: aim.edgeLabel, via: 'edgeLabel' };
  if (aim.legend != null) return { kind: 'component', component: 'legend' };
  return null;   // a free point: recorded, not checked
}

// ---------- the reference predictor (SS1, from the option alone) ----------

const dig = (o, ks) => { for (const k of ks) { if (o == null) return undefined; o = o[k]; } return o; };
const first = (...vs) => { for (const v of vs) if (v != null) return v; return undefined; };

function refModel(option) {
  const leg = Array.isArray(option.legend) ? option.legend[0] : option.legend;
  const sel = (leg && leg.selected) || {};
  return optionSeries(option).map((s, si) => {
    const cs = s.type === 'graph' && s.coordinateSystem !== 'cartesian2d' ? 'view' + si : 'grid' + (s.xAxisIndex || 0);
    if (s.type !== 'graph') return { si, type: s.type, cs };
    const cats = s.categories || [];
    const data = s.data || s.nodes || [];
    const nodes = [];
    data.forEach(n => {
      const cat = typeof n.category === 'number' ? cats[n.category] : null;
      if (cat && sel[cat.name] === false) return;
      nodes.push({ name: n.name, row: nodes.length, item: n, cat });
    });
    const byName = new Map(nodes.map(n => [n.name, n]));
    const edges = [];
    (s.links || s.edges || []).forEach((l, j) => {
      const a = byName.get(l.source), b = byName.get(l.target);
      if (a && b) edges.push({ link: j, row: edges.length, src: a.row, tgt: b.row, item: l });
    });
    const legacy = dig(s, ['emphasis', 'focus']) == null && s.focusNodeAdjacency != null;
    return { si, type: 'graph', cs, s, nodes, edges, byName, legacy };
  });
}
// the emphasis/blur property of a node or an edge, through the cascade
function nodeProp(m, n, ks, mut) {
  const own = mut.seriesOnlyEmphasis && ks[0] === 'emphasis' ? undefined : first(dig(n.item, ks), dig(n.cat, ks));
  let v = first(own, dig(m.s, ks));
  if (v == null && ks[0] === 'emphasis' && ks[1] === 'focus' && m.legacy && !mut.legacyFalseIsNone) v = 'adjacency';
  if (v == null && ks[0] === 'emphasis' && ks[1] === 'focus' && m.legacy && mut.legacyFalseIsNone && m.s.focusNodeAdjacency) v = 'adjacency';
  return v;
}
function edgeProp(m, e, ks, mut) {
  const own = mut.seriesOnlyEmphasis && ks[0] === 'emphasis' ? undefined : dig(e.item, ks);
  let v = first(own, dig(m.s, ks));
  if (v == null && ks[0] === 'emphasis' && ks[1] === 'focus' && m.legacy && !mut.legacyFalseIsNone) v = 'adjacency';
  if (v == null && ks[0] === 'emphasis' && ks[1] === 'focus' && m.legacy && mut.legacyFalseIsNone && m.s.focusNodeAdjacency) v = 'adjacency';
  return v;
}
function modeOf(v, mut) {
  if (!v || v === 'none') return 'none';
  if (v === 'series') return 'series';
  if (v === 'adjacency') return 'adjacency';
  if (mut.unknownFocusIsNone && v !== 'self') return 'none';
  return 'self';
}
function nodeSet(m, row, mut) {
  const es = m.edges.filter(e => e.src === row || e.tgt === row);
  const set = { edge: es.map(e => e.row), node: [] };
  es.forEach(e => set.node.push(e.src, e.tgt));
  if (mut.isolatedSelfKept) set.node.push(row);
  return set;
}
function edgeSet(m, row, mut) {
  const e = m.edges[row];
  if (mut.sharedEndEdgeKept) {
    const es = m.edges.filter(q => q.src === e.src || q.tgt === e.src || q.src === e.tgt || q.tgt === e.tgt);
    return { edge: es.map(q => q.row), node: [e.src, e.tgt] };
  }
  return { edge: [row], node: [e.src, e.tgt] };
}
// states: per graph series {nodes: [st per row], edges: [st per row], labels, arrows}
function blankStates(model) {
  return model.map(m => (m.type === 'graph' ? { nodes: m.nodes.map(() => 'N'), edges: m.edges.map(() => 'N') } : null));
}
function predictStates(model, aim, mut) {
  const st = blankStates(model);
  if (!aim) return st;
  if ((aim.label != null || aim.edgeLabel != null) && mut.labelHitToNode) return st;
  const si = aim.series || 0;
  const m = model[si];
  let kind, row;
  if (aim.node != null || aim.label != null) { kind = 'node'; row = m.byName.get(aim.node != null ? aim.node : aim.label).row; }
  else { kind = 'edge'; const link = aim.edge != null ? aim.edge : aim.edgeLabel; row = m.edges.find(e => e.link === link).row; }
  const prop = ks => (kind === 'node' ? nodeProp(m, m.nodes[row], ks, mut) : edgeProp(m, m.edges[row], ks, mut));
  const mark = () => { st[si][kind === 'node' ? 'nodes' : 'edges'][row] = 'E'; };
  if (prop(['emphasis', 'disabled'])) return st;
  let mode = modeOf(prop(['emphasis', 'focus']), mut);
  if (mode === 'series' && mut.seriesModeBlursOwn) mode = 'self';
  if (mode === 'none') { mark(); return st; }
  const set = mode === 'adjacency' ? (kind === 'node' ? nodeSet(m, row, mut) : edgeSet(m, row, mut)) : null;
  if (set && mut.emptySetBlursNothing && kind === 'node' && set.edge.length === 0) { mark(); return st; }
  const scope = prop(['emphasis', 'blurScope']) || 'coordinateSystem';
  model.forEach((t, ti) => {
    const same = ti === si;
    const sameCS = t.cs === m.cs;
    const skip = (scope === 'series' && !same) || (scope === 'coordinateSystem' && !sameCS && !mut.scopeIgnored)
      || (mode === 'series' && same);
    if (skip || t.type !== 'graph') return;
    const ts = st[ti];
    ts.nodes = ts.nodes.map(() => 'B');
    ts.edges = ts.edges.map(() => 'B');
    if (set && !(mut.globalWithoutLeak && !same)) {
      set.node.forEach(r => { if (r < ts.nodes.length) ts.nodes[r] = 'N'; });
      set.edge.forEach(r => { if (r < ts.edges.length) ts.edges[r] = 'N'; });
    }
  });
  if (set && mut.neighboursWouldBeE) {
    set.node.forEach(r => { st[si].nodes[r] = 'E'; });
    set.edge.forEach(r => { st[si].edges[r] = 'E'; });
  }
  mark();
  return st;
}

// the full expected record from the rest record, the states and the option
function ratioOf(m, n, mut) {
  const scale = nodeProp(m, n, ['emphasis', 'scale'], mut);
  let size = first(n.item.symbolSize, m.s.symbolSize, 10);
  if (!Array.isArray(size)) size = [size, size];
  const h = (mut.ratioFromWidth ? size[0] : size[1]) / 2;
  return scale == null || scale === true ? Math.max(1.1, 3 / h) : isFinite(scale) && scale > 0 ? +scale : 1;
}
function expectLabel(rl, state, declared, dis, mut) {
  if (!rl) return null;
  const s = mut.labelNoState ? 'N' : state;
  const o = Object.assign({}, rl, { state: s });
  if (s === 'B') o.opacity = declared != null ? (mut.declaredBlurMultiplied ? declared * 0.1 : declared) : dis ? rl.opacity : rl.opacity * 0.1;
  if (s === 'E') { o.ignore = false; if (!mut.noZ2Lift) o.z2 = rl.z2 + 10; }
  return o;
}
function expectNode(m, n, rn, state, mut) {
  const o = Object.assign({}, rn, { state });
  // a disabled element takes the blur STATE but has no default-state proxy:
  // only a declared blur opacity changes it
  const dis = !!nodeProp(m, n, ['emphasis', 'disabled'], mut) && !mut.disabledBlurDims;
  if (state === 'B') {
    const d = nodeProp(m, n, ['blur', 'itemStyle', 'opacity'], mut);
    o.opacity = d != null ? (mut.declaredBlurMultiplied ? d * 0.1 : d) : dis ? rn.opacity : rn.opacity * 0.1;
  } else if (state === 'E') {
    const col = nodeProp(m, n, ['emphasis', 'itemStyle', 'color'], mut);
    const lineCol = mut.crossedEmphasisStyles ? dig(m.s, ['emphasis', 'lineStyle', 'color']) : undefined;
    const c = mut.declaredColourIgnored ? undefined : first(col, lineCol);
    o.fill = undefined;   // the lifted string is not predicted; the bytes are
    o.fillBytes = c != null ? parseColour(c) : liftBytes(rn.fillBytes);
    const bc = nodeProp(m, n, ['emphasis', 'itemStyle', 'borderColor'], mut);
    const bw = nodeProp(m, n, ['emphasis', 'itemStyle', 'borderWidth'], mut);
    if (bc != null) {
      o.stroke = undefined; o.strokeBytes = parseColour(bc);
      o.lineWidth = bw != null ? bw : rn.rawLineWidth;
    }
    const r = ratioOf(m, n, mut);
    o.half = [rn.half[0] * r, rn.half[1] * r];
    if (!mut.noZ2Lift) o.z2 = rn.z2 + 10;
  }
  o.label = expectLabel(rn.label, state, nodeProp(m, n, ['blur', 'label', 'opacity'], mut), dis, mut);
  return o;
}
function expectArrow(ra, state, declaredBlur, eStroke, eOpacity, dis, mut) {
  if (!ra) return null;
  const s = mut.arrowDatum ? 'N' : state;
  const o = Object.assign({}, ra, { state: s });
  if (s === 'B') o.opacity = declaredBlur != null ? (mut.declaredBlurMultiplied ? declaredBlur * 0.1 : declaredBlur) : dis ? ra.opacity : ra.opacity * 0.1;
  if (s === 'E') { o.fill = undefined; o.fillBytes = eStroke; if (eOpacity != null) o.opacity = eOpacity; }
  return o;
}
function expectEdge(m, e, re, state, mut) {
  const o = Object.assign({}, re, { state });
  const db = edgeProp(m, e, ['blur', 'lineStyle', 'opacity'], mut);
  const dis = !!edgeProp(m, e, ['emphasis', 'disabled'], mut) && !mut.disabledBlurDims;
  let eStroke = null, eOp;
  if (state === 'B') o.opacity = db != null ? (mut.declaredBlurMultiplied ? db * 0.1 : db) : dis ? re.opacity : re.opacity * 0.1;
  else if (state === 'E') {
    const col = edgeProp(m, e, ['emphasis', 'lineStyle', 'color'], mut);
    const itemCol = mut.crossedEmphasisStyles ? dig(m.s, ['emphasis', 'itemStyle', 'color']) : undefined;
    const c = mut.declaredColourIgnored ? undefined : first(col, itemCol);
    eStroke = c != null ? parseColour(c) : liftBytes(re.strokeBytes);
    o.stroke = undefined; o.strokeBytes = eStroke;
    const w = first(edgeProp(m, e, ['emphasis', 'lineStyle', 'width'], mut),
      mut.crossedEmphasisStyles ? dig(m.s, ['emphasis', 'itemStyle', 'borderWidth']) : undefined);
    o.lineWidth = w != null ? w : mut.edgeWidthBoost ? re.lineWidth + 1 : re.lineWidth;
    eOp = edgeProp(m, e, ['emphasis', 'lineStyle', 'opacity'], mut);
    if (eOp != null) o.opacity = eOp;
    if (mut.edgeLiftAboveNodes) o.z2 = 1000;
    else if (!mut.noZ2Lift) o.z2 = re.z2 + 10;
  }
  o.fromArrow = expectArrow(re.fromArrow, state, db, eStroke, eOp, dis, mut);
  o.toArrow = expectArrow(re.toArrow, state, db, eStroke, eOp, dis, mut);
  return o;
}
function predictRecord(model, rest, prev, step, aim, mut) {
  if (step.leave && mut.leaveKeepsBlur) return prev;
  const st = predictStates(model, step.leave ? null : aim, mut);
  return {
    series: rest.series.map(rs => {
      const m = model[rs.index];
      const ss = st[rs.index];
      return { index: rs.index,
        nodes: rs.nodes.map(rn => { const n = m.byName.get(rn.name); return expectNode(m, n, rn, ss.nodes[n.row], mut); }),
        edges: rs.edges.map(re => { const e = m.edges.find(q => q.link === re.link); return expectEdge(m, e, re, ss.edges[e.row], mut); }) };
    }),
  };
}

// field-by-field comparison; `undefined` in the prediction = not predicted
function diffRec(pred, rec, onlyStates) {
  const out = [];
  const cmp = (where, p, r) => {
    if (p === undefined) return;
    if (p === null || r === null || typeof p !== 'object') {
      if (!(p === r || (typeof p === 'number' && Object.is(p, r)))) out.push(where + ': expected ' + JSON.stringify(p) + ', got ' + JSON.stringify(r));
      return;
    }
    if (Array.isArray(p)) {
      if (!Array.isArray(r) || p.length !== r.length) { out.push(where + ': length'); return; }
      p.forEach((v, i) => cmp(where + '[' + i + ']', v, r[i]));
      return;
    }
    for (const k of Object.keys(p)) {
      if (k === 'rawLineWidth') continue;
      if (onlyStates && !['series', 'nodes', 'edges', 'label', 'fromArrow', 'toArrow', 'state', 'index'].includes(k)) continue;
      cmp(where + '.' + k, p[k], r[k]);
    }
  };
  pred.series.forEach((ps, i) => cmp('series ' + ps.index, ps, rec.series[i]));
  return out;
}

// ---------- running a case ----------

function drive(c) {
  const chart = mk(c.W, c.H);
  const records = [];
  try {
    chart.setOption(clone(c.option));
    settle(chart);
    const geo = restGeometry(chart);
    c.points = c.aims.map(a => (a.leave || a.action ? null : aimPoint(geo, a)));
    c.ambiguous = c.aims.map((a, k) => (c.points[k] ? ambiguity(geo, a, c.points[k]) : []));
    records.push(snapshot(chart, null));
    c.aims.forEach((a, k) => {
      let hit = null;
      if (a.leave) moveTo(chart, -1, -1);
      else if (a.action) { chart.dispatchAction(clone(a.action)); chart._onframe(); }
      else {
        const [x, y] = c.points[k];
        hit = hitAt(chart, x, y);
        moveTo(chart, x, y);
      }
      settle(chart);
      records.push(snapshot(chart, hit));
    });
  } finally {
    kill(chart);
  }
  return records;
}

const MUTS = ['neighboursWouldBeE', 'isolatedSelfKept', 'emptySetBlursNothing', 'sharedEndEdgeKept', 'seriesOnlyEmphasis',
  'labelHitToNode', 'arrowDatum', 'labelNoState', 'unknownFocusIsNone', 'legacyFalseIsNone', 'seriesModeBlursOwn',
  'scopeIgnored', 'globalWithoutLeak', 'leaveKeepsBlur', 'declaredBlurMultiplied', 'ratioFromWidth',
  'declaredColourIgnored', 'crossedEmphasisStyles', 'edgeWidthBoost', 'noZ2Lift', 'edgeLiftAboveNodes', 'disabledBlurDims'];
const COUNTS = ['rowNotLink', 'translucentEmphasis'];

function checkCase(c, records) {
  const f = { 1: [], 2: [], 3: [], 4: [], 5: [] };
  const disc = {};
  MUTS.concat(COUNTS).forEach(k => { disc[k] = 0; });
  const rest = records[0];
  // 1: hit and unambiguity
  c.aims.forEach((a, k) => {
    if (!c.points[k]) return;
    const want = expectedHit(a);
    const got = records[k + 1].hit;
    if (want && JSON.stringify(want) !== JSON.stringify(got)) f[1].push('step ' + (k + 1) + ': aimed ' + JSON.stringify(want) + ', hit ' + JSON.stringify(got));
    if (c.ambiguous[k].length) f[1].push('step ' + (k + 1) + ' at ' + c.points[k] + ': ' + c.ambiguous[k].join(', '));
  });
  // 2: leave == rest
  c.aims.forEach((a, k) => {
    if (a.leave && JSON.stringify(records[k + 1]) !== JSON.stringify(rest)) f[2].push('step ' + (k + 1) + ': the leave record differs from rest');
  });
  // 5: key bijections
  const model = refModel(c.option);
  rest.series.forEach(rs => {
    const m = model[rs.index];
    const links = rs.edges.map(e => e.link);
    const want = m.edges.map(e => e.link);
    if (JSON.stringify(links) !== JSON.stringify(want)) f[5].push('series ' + rs.index + ': edge links ' + JSON.stringify(links) + ', expected ' + JSON.stringify(want));
    if (new Set(links).size !== links.length) f[5].push('series ' + rs.index + ': duplicate links');
    rs.edges.forEach(e => { const me = m.edges.find(q => q.link === e.link); if (!me || me.row !== e.row) f[5].push('series ' + rs.index + ' link ' + e.link + ': row ' + e.row); });
    const names = rs.nodes.map(n => n.name);
    if (JSON.stringify(names) !== JSON.stringify(m.nodes.map(n => n.name))) f[5].push('series ' + rs.index + ': nodes ' + JSON.stringify(names));
    if (new Set(names).size !== names.length) f[5].push('series ' + rs.index + ': duplicate names');
  });
  // 3 / 4 and the wrong models (only where the predictor applies)
  if (!c.noModel) {
    c.aims.forEach((a, k) => {
      const rec = records[k + 1];
      const pred = predictRecord(model, rest, records[k], a, a, {});
      diffRec(pred, rec, true).slice(0, 3).forEach(d => f[4].push('step ' + (k + 1) + ' ' + d));
      diffRec(pred, rec, false).slice(0, 3).forEach(d => f[3].push('step ' + (k + 1) + ' ' + d));
      MUTS.forEach(mu => {
        const mp = predictRecord(model, rest, records[k], a, a, { [mu]: true });
        if (diffRec(mp, rec, false).length) disc[mu]++;
      });
    });
  }
  records.forEach(r => r.series.forEach(s => s.edges.forEach(e => {
    if (r === rest && e.row !== e.link) disc.rowNotLink++;
    if (e.state === 'E' && e.opacity < 1) disc.translucentEmphasis++;
  })));
  return { f, disc };
}

// ---------- the cases ----------

// canonical graph: A-B, B-C, A-C, C-D, E-E (self-loop), F isolated; the box
// equals the data extent, so the view is the identity (pixels = data)
const G_NODES = [
  { name: 'A', x: 60, y: 60 }, { name: 'B', x: 260, y: 60 }, { name: 'C', x: 160, y: 150 },
  { name: 'D', x: 320, y: 230 }, { name: 'E', x: 60, y: 250 }, { name: 'F', x: 250, y: 260 },
];
const G_LINKS = [
  { source: 'A', target: 'B' }, { source: 'B', target: 'C' }, { source: 'A', target: 'C' },
  { source: 'C', target: 'D' }, { source: 'E', target: 'E' },
];
function boxOf(nodes) {
  const xs = nodes.map(n => n.x), ys = nodes.map(n => n.y);
  const x0 = Math.min(...xs), y0 = Math.min(...ys);
  return { left: x0, top: y0, width: Math.max(...xs) - x0, height: Math.max(...ys) - y0 };
}
function gs(extra, nodes, links) {
  nodes = clone(nodes || G_NODES);
  links = clone(links || G_LINKS);
  return Object.assign({ type: 'graph', layout: 'none' }, boxOf(nodes), {
    symbolSize: 20, label: { show: true, position: 'right' },
    itemStyle: { color: '#5070dd' }, lineStyle: { color: '#336699' },
    data: nodes, links }, extra || {});
}
function opt(series, root) { return Object.assign({ animation: false, tooltip: { show: false } }, root || {}, { series: Array.isArray(series) ? series : [series] }); }
// with per-item tweaks: fn(series) edits the series in place
function tweak(series, fn) { fn(series); return series; }

const N = (node, series) => (series ? { node, series } : { node });
const EG = (edge, series) => (series ? { edge, series } : { edge });
const LB = label => ({ label });
const LV = { leave: true };

const cases = [];
function add(group, name, option, aims, flags) {
  cases.push(Object.assign({ group, name, W: 400, H: 300, option, aims }, flags || {}));
}

// G1: the canonical graph, focus adjacency
const ALL = [];
['A', 'B', 'C', 'D', 'E', 'F'].forEach(n => ALL.push(N(n), LV));
[0, 1, 2, 3].forEach(e => ALL.push(EG(e), LV));
add('G1', 'canonical graph, adjacency: every node, every reachable edge, leave after each; then A, D, e1 without a leave',
  opt(gs({ emphasis: { focus: 'adjacency' } })), ALL.concat([N('A'), N('D'), EG(1), LV]), { pixelGuard: true });

// G2: focus modes
const MODE_STEPS = [N('C'), EG(1), LV, N('F'), LV, N('A'), LV];
[
  ['self', { emphasis: { focus: 'self' } }],
  ['series', { emphasis: { focus: 'series' } }],
  ["'none'", { emphasis: { focus: 'none' } }],
  ['unset', {}],
  ['true (self)', { emphasis: { focus: true } }],
  ["'foo' (self)", { emphasis: { focus: 'foo' } }],
  ["'ADJACENCY' is case-sensitive (self)", { emphasis: { focus: 'ADJACENCY' } }],
  ['0 (none)', { emphasis: { focus: 0 } }],
  ['legacy focusNodeAdjacency:false (adjacency)', { focusNodeAdjacency: false }],
  ['legacy focusNodeAdjacency:true (adjacency)', { focusNodeAdjacency: true }],
  ["legacy focusNodeAdjacency:true under an explicit focus 'self'", { focusNodeAdjacency: true, emphasis: { focus: 'self' } }],
].forEach(([n, x]) => add('G2', 'mode: ' + n, opt(gs(x)), MODE_STEPS));

// G3: the cascade
const CASC = [N('C'), LV, N('A'), LV, EG(1), LV];
add('G3', 'cascade: data[2].emphasis.focus adjacency alone', opt(tweak(gs(), s => { s.data[2].emphasis = { focus: 'adjacency' }; })), CASC);
add('G3', 'cascade: links[1].emphasis.focus adjacency alone', opt(tweak(gs(), s => { s.links[1].emphasis = { focus: 'adjacency' }; })), CASC);
add('G3', 'cascade: categories[1].emphasis.focus adjacency (C in category 1)', opt(tweak(gs({
  categories: [{ name: 'k0' }, { name: 'k1', emphasis: { focus: 'adjacency' } }] }), s => { s.data.forEach((n, i) => { n.category = i === 2 ? 1 : 0; }); })), CASC);
add('G3', "cascade: series adjacency, data[2].emphasis.focus 'none'", opt(tweak(gs({ emphasis: { focus: 'adjacency' } }), s => { s.data[2].emphasis = { focus: 'none' }; })), CASC);
add('G3', 'cascade: series adjacency, data[2].emphasis.disabled (blurred by F, it keeps its look)',
  opt(tweak(gs({ emphasis: { focus: 'adjacency' } }), s => { s.data[2].emphasis = { disabled: true }; })), CASC.concat([N('F'), LV]));
add('G3', 'cascade: series adjacency, links[1].emphasis.disabled (blurred by A, it keeps its look)',
  opt(tweak(gs({ emphasis: { focus: 'adjacency' } }), s => { s.links[1].emphasis = { disabled: true }; })), CASC);
add('G3', 'cascade: disabled node and link under a declared blur (the declared opacity does apply)',
  opt(tweak(gs({ emphasis: { focus: 'adjacency' }, blur: { itemStyle: { opacity: 0.3 }, lineStyle: { opacity: 0.2 }, label: { opacity: 0.4 } },
    edgeSymbol: ['none', 'arrow'] }), s => { s.data[2].emphasis = { disabled: true }; s.links[1].emphasis = { disabled: true }; })),
  [N('F'), LV, N('C'), LV, EG(1), LV]);
add('G3', "cascade: series self, links[1].emphasis.focus adjacency, data[0].emphasis.focus 'series'",
  opt(tweak(gs({ emphasis: { focus: 'self' } }), s => { s.links[1].emphasis = { focus: 'adjacency' }; s.data[0].emphasis = { focus: 'series' }; })), CASC);

// G4: label hover (long names so the label box is wide and off the symbol)
const LONG = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot'];
const L_NODES = G_NODES.map((n, i) => Object.assign({}, n, { name: LONG[i] }));
const L_LINKS = G_LINKS.map(l => ({ source: LONG['ABCDEF'.indexOf(l.source)], target: LONG['ABCDEF'.indexOf(l.target)] }));
add('G4', "label hover: position 'right', adjacency; the label box centre of Charlie, of Delta, Echo's symbol then its label, Foxtrot's label (isolated)",
  opt(gs({ emphasis: { focus: 'adjacency' } }, L_NODES, L_LINKS)), [LB('Charlie'), LV, LB('Delta'), LV, N('Echo'), LB('Echo'), LV, LB('Foxtrot'), LV]);
add('G4', "label hover: self focus, a label then an edge without a leave",
  opt(gs({ emphasis: { focus: 'self' } }, L_NODES, L_LINKS)), [LB('Charlie'), EG(3), LV]);

// G5: visuals
const ADJ = { focus: 'adjacency' };
add('G5', 'visuals: defaults (edge opacity 0.5), a node and an edge', opt(gs({ emphasis: ADJ })), [N('C'), LV, EG(1), LV], { pixelGuard: true });
add('G5', 'visuals: lineStyle.opacity 0.9 blurs to 0.09000000000000001',
  opt(gs({ emphasis: ADJ, lineStyle: { color: '#336699', opacity: 0.9 } })), [N('C'), LV, EG(1), LV]);
add('G5', 'visuals: lineStyle.opacity 1, an edge hover', opt(gs({ emphasis: ADJ, lineStyle: { color: '#336699', opacity: 1 } })), [EG(1), LV, EG(3), LV], { pixelGuard: true });
add('G5', 'visuals: declared blur itemStyle 0.3, lineStyle 0.2, label 0.4',
  opt(gs({ emphasis: ADJ, blur: { itemStyle: { opacity: 0.3 }, lineStyle: { opacity: 0.2 }, label: { opacity: 0.4 } } })), [N('C'), LV, EG(1), LV]);
add('G5', 'visuals: declared blur at item, category and link level over the series',
  opt(tweak(gs({ emphasis: ADJ, blur: { itemStyle: { opacity: 0.3 }, lineStyle: { opacity: 0.2 } },
    categories: [{ name: 'k0' }, { name: 'k1', blur: { itemStyle: { opacity: 0.7 }, label: { opacity: 0.6 } } }] }), s => {
    s.data.forEach((n, i) => { n.category = i === 4 ? 1 : 0; });
    s.data[3].blur = { itemStyle: { opacity: 0.5 }, label: { opacity: 0.25 } };
    s.links[0].blur = { lineStyle: { opacity: 0.25 } };
  })), [N('F'), LV, N('C'), LV]);
add('G5', 'visuals: emphasis.lineStyle width 4 and a colour; an edge hover, then a node hover (its edges stay width 1)',
  opt(gs({ emphasis: { focus: 'adjacency', lineStyle: { width: 4, color: '#ff0000' } } })), [EG(1), LV, N('C'), LV]);
add('G5', 'visuals: emphasis.lineStyle opacity 1 on a translucent edge', opt(gs({ emphasis: { focus: 'adjacency', lineStyle: { opacity: 1 } } })), [EG(3), LV]);
add('G5', 'visuals: emphasis.itemStyle colour, border colour and width 3; a node hover (the neighbour unchanged), then an edge hover',
  opt(gs({ emphasis: { focus: 'adjacency', itemStyle: { color: '#ff0000', borderColor: '#000', borderWidth: 3 } } })), [N('C'), LV, EG(1), LV]);
add('G5', 'visuals: emphasis.scale false', opt(gs({ emphasis: { focus: 'adjacency', scale: false } })), [N('C'), LV]);
add('G5', 'visuals: emphasis.scale 2', opt(gs({ emphasis: { focus: 'adjacency', scale: 2 } })), [N('C'), LV]);
add('G5', 'visuals: data[2].emphasis.scale 1.5 over the series default', opt(tweak(gs({ emphasis: ADJ }), s => { s.data[2].emphasis = { scale: 1.5 }; })), [N('C'), LV, N('A'), LV]);
add('G5', 'visuals: symbolSize 4 (ratio max(1.1, 3/2) = 1.5)', opt(gs({ emphasis: ADJ, symbolSize: 4 })), [N('C'), LV]);
add('G5', 'visuals: symbolSize [40, 4] (ratio from the height: 1.5 on both axes)', opt(gs({ emphasis: ADJ, symbolSize: [40, 4] })), [N('C'), LV, N('D'), LV]);
add('G5', 'visuals: symbolSize [40, 10] (3/5 < 1.1: ratio 1.1)', opt(gs({ emphasis: ADJ, symbolSize: [40, 10] })), [N('C'), LV]);
add('G5', "visuals: edgeSymbol ['circle', 'arrow'], a node hover then an edge hover",
  opt(gs({ emphasis: ADJ, edgeSymbol: ['circle', 'arrow'] })), [N('C'), LV, EG(1), LV]);
add('G5', "visuals: edgeSymbol ['none', 'arrow'] with emphasis.lineStyle colour and opacity 1 and a declared blur",
  opt(gs({ emphasis: { focus: 'adjacency', lineStyle: { color: '#00ff00', opacity: 1 } }, blur: { lineStyle: { opacity: 0.2 } }, edgeSymbol: ['none', 'arrow'] })),
  [EG(1), LV, N('C'), LV]);

// G6: index mapping: a dangling link at links[1], and a legend hiding D
const DANGLE = G_LINKS.slice(0, 1).concat([{ source: 'A', target: 'ZZ' }], G_LINKS.slice(1));
add('G6', 'index mapping: a dangling link at links[1]', opt(gs({ emphasis: ADJ }, G_NODES, DANGLE)), [N('C'), LV, EG(2), LV, EG(4), LV]);
add('G6', 'index mapping: a dangling link at links[1] and a legend hiding D (category k1)',
  opt(tweak(gs({ emphasis: ADJ, categories: [{ name: 'k0' }, { name: 'k1' }] }, G_NODES, DANGLE), s => {
    s.data.forEach((n, i) => { n.category = i === 3 ? 1 : 0; });
  }), { legend: { data: ['k0', 'k1'], selected: { k1: false }, top: 0, left: 0 } }),
  [N('C'), LV, EG(2), LV, EG(3), LV, N('E'), LV]);

// G7: two view graphs side by side; series 1 has the same topology under other names
const S0 = [{ name: 'A', x: 20, y: 40 }, { name: 'B', x: 160, y: 40 }, { name: 'C', x: 90, y: 130 },
  { name: 'D', x: 170, y: 210 }, { name: 'E', x: 20, y: 250 }, { name: 'F', x: 120, y: 270 }];
const RN = { A: 'P', B: 'Q', C: 'R', D: 'S', E: 'T', F: 'U' };
const S1 = S0.map(n => ({ name: RN[n.name], x: n.x + 200, y: n.y }));
const S1L = G_LINKS.map(l => ({ source: RN[l.source], target: RN[l.target] }));
const TWO = [N('C'), LV, N('F'), LV, EG(1), LV, N('R', 1), LV];
[
  ['adjacency, default scope: the other graph is untouched', { focus: 'adjacency' }],
  ["adjacency, blurScope 'series'", { focus: 'adjacency', blurScope: 'series' }],
  ["adjacency, blurScope 'global': the index leak", { focus: 'adjacency', blurScope: 'global' }],
  ["series, blurScope 'global': the other graph fully blurred", { focus: 'series', blurScope: 'global' }],
  ["self, blurScope 'global'", { focus: 'self', blurScope: 'global' }],
].forEach(([n, em]) => add('G7', 'two view graphs: ' + n, opt([gs({ emphasis: em }, S0), gs({}, S1, S1L)]), TWO));

// documentary
add('D', 'cartesian graph and a bar: default scope leaks the index sets into the bar (a4)', opt([
  { type: 'graph', coordinateSystem: 'cartesian2d', symbolSize: 20, itemStyle: { color: '#5070dd' }, lineStyle: { color: '#336699' },
    emphasis: { focus: 'adjacency' }, data: [[1, 1], [3, 3], [5, 1], [7, 3]].map((v, i) => ({ name: 'n' + i, value: v })),
    links: [{ source: 'n0', target: 'n1' }, { source: 'n1', target: 'n2' }, { source: 'n2', target: 'n3' }] },
  { type: 'bar', data: [[1, 2], [2, 2], [3, 2], [4, 2]] }], { xAxis: { type: 'value' }, yAxis: { type: 'value' } }),
[N('n1'), LV], { documentary: true, noModel: true, note: 'SS4 OUT: cross-series blur between a graph and a non-graph series; the bar keeps rows 0..2 by the node set' });
add('D', "label.show false: the hovered node's emphasis label appears, the neighbours' stay hidden",
  opt(gs({ emphasis: ADJ, label: { show: false } })), [N('C'), LV], { documentary: true, note: 'SS4 OUT: emphasis labels' });
add('D', 'edge-label hover emphasises the edge (a2)', opt(gs({ emphasis: ADJ, edgeLabel: { show: true, formatter: 'edge {c}' } })),
  [{ edgeLabel: 3 }, LV], { documentary: true, note: 'SS4 OUT: edge labels' });
add('D', 'highlight / downplay payloads (dataType omitted = node; edge numbering; name; the node-0 fallback; notBlur; the self-loop)',
  opt(gs({ emphasis: ADJ })), [
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } }, { action: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 1 } }, { action: { type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: 1 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 4 } }, { action: { type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: 4 } },
    { action: { type: 'highlight', seriesIndex: 0, name: 'D' } }, { action: { type: 'downplay', seriesIndex: 0, name: 'D' } },
    { action: { type: 'highlight', seriesIndex: 0 } }, { action: { type: 'downplay', seriesIndex: 0 } },
    { action: { type: 'highlight', seriesIndex: 0, name: 'nope' } }, { action: { type: 'downplay', seriesIndex: 0, name: 'nope' } },
    { action: { type: 'highlight', seriesIndex: 0, dataIndex: 2, notBlur: true } }, { action: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } },
  ], { documentary: true, noModel: true, note: 'SS4 OUT: the port has no action API' });
add('D', 'legend hover on a category name that no node carries: blur by node 0 (A)', opt(tweak(gs({ emphasis: ADJ,
  categories: [{ name: 'cat0' }, { name: 'cat1' }] }), s => { s.data.forEach((n, i) => { n.category = i < 3 ? 0 : 1; }); }),
{ legend: { data: ['cat0', 'cat1'], top: 0, left: 0, orient: 'vertical' } }),
[{ legend: 1 }, LV], { documentary: true, noModel: true, note: 'SS4 OUT: legend hover' });
add('D', "a dangling link under blurScope 'global': the leak indexes rows, not links",
  opt([gs({ emphasis: { focus: 'adjacency', blurScope: 'global' } }, S0, G_LINKS.slice(0, 1).concat([{ source: 'A', target: 'ZZ' }], G_LINKS.slice(1))),
    gs({}, S1, S1L)]), [N('C'), LV, EG(3), LV],
  { documentary: true, note: 'rows are upstream dataIndex; a port keyed by link leaks into the wrong edges of series 1' });

// ---------- run, check, write ----------

{
  const names = new Set();
  for (const c of cases) { must(!names.has(c.name), 'two cases named ' + c.name); names.add(c.name); }
}
const CHECKS = ['1', '2', '3', '4', '5'];
function encNode(n) {
  const o = { name: n.name, row: n.row, state: n.state };
  put(o, 'opacity', n.opacity);
  o.fill = n.fill; o.fillBytes = n.fillBytes;
  o.stroke = n.stroke; o.strokeBytes = n.strokeBytes;
  put(o, 'lineWidth', n.lineWidth);
  put(o, 'half', n.half);
  o.z2 = n.z2;
  o.label = n.label && put({ state: n.label.state }, 'opacity', n.label.opacity);
  if (o.label) { o.label.ignore = n.label.ignore; o.label.z2 = n.label.z2; }
  return o;
}
function encArrow(a) {
  if (!a) return null;
  const o = { state: a.state };
  put(o, 'opacity', a.opacity);
  o.fill = a.fill; o.fillBytes = a.fillBytes;
  return o;
}
function encEdge(e) {
  const o = { link: e.link, row: e.row, zeroLength: e.zeroLength, state: e.state };
  put(o, 'opacity', e.opacity);
  o.stroke = e.stroke; o.strokeBytes = e.strokeBytes;
  put(o, 'lineWidth', e.lineWidth);
  o.z2 = e.z2;
  o.fromArrow = encArrow(e.fromArrow);
  o.toArrow = encArrow(e.toArrow);
  return o;
}
function encRecord(r) {
  const o = { hit: r.hit, series: r.series.map(s => ({ index: s.index, nodes: s.nodes.map(encNode), edges: s.edges.map(encEdge) })) };
  if (r.others) o.others = r.others.map(s => ({ index: s.index, type: s.type, items: s.items.map(it => it && put({ state: it.state }, 'opacity', it.opacity)) }));
  return o;
}
function encStep(a, pt) {
  if (a.leave) return { leave: true };
  if (a.action) return { action: a.action };
  return { hover: pt };
}

function generate() {
  const tally = {};
  CHECKS.forEach(k => { tally[k] = [0, 0]; });
  const failed = [];
  const totals = {};
  MUTS.concat(COUNTS).forEach(k => { totals[k] = 0; });
  const recs = cases.map(c => {
    let records;
    try { records = drive(c); } catch (e) { if (e instanceof OracleError) e.message = c.name + ': ' + e.message; throw e; }
    const { f, disc } = checkCase(c, records);
    let miss = '';
    CHECKS.forEach(k => {
      if ((k === '3' || k === '4') && c.noModel) return;
      tally[k][f[k].length ? 1 : 0]++;
      if (f[k].length) miss += (miss ? ' | ' : '') + 'self-check ' + k + ': ' + f[k].slice(0, 3).join('; ') + (f[k].length > 3 ? ' (+' + (f[k].length - 3) + ' more)' : '');
    });
    if (miss && !c.deferred) failed.push(c.name + ': ' + miss);
    const rec = { name: c.name, group: c.group, W: c.W, H: c.H, option: c.option,
      steps: c.aims.map((a, k) => encStep(a, c.points[k])) };
    rec.documentary = !!c.documentary;
    if (c.documentary) rec.note = c.note;
    rec.deferred = !!c.deferred;
    if (c.deferred) rec.why = c.deferred + (miss ? '; first differences: ' + miss : '; (no self-check failed)');
    rec.pixelGuard = !!c.pixelGuard;
    rec.discriminates = disc;
    rec.records = records.map(encRecord);
    if (!c.deferred && !c.documentary) Object.keys(totals).forEach(k => { totals[k] += disc[k]; });
    return rec;
  });
  return { out: { source: 'ECharts ' + echarts.version, cases: recs }, tally, failed, totals };
}

// the compact writer of roam.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(oneLine).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const flat = oneLine(v);
  if (flat.length + ind.length <= LINE || v === null || typeof v !== 'object') return flat;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = v.map(x => fmt(x, inner));
    if (items.every(t => !t.includes('\n'))) {
      const lines = [];
      let cur = '';
      for (const t of items) {
        if (cur && inner.length + cur.length + 1 + t.length + 1 > LINE) { lines.push(cur); cur = ''; }
        cur += (cur ? ',' : '') + t;
      }
      lines.push(cur);
      return '[\n' + lines.map(l => inner + l).join(',\n') + '\n' + ind + ']';
    }
    return '[\n' + items.map(x => inner + x).join(',\n') + '\n' + ind + ']';
  }
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n')
    + '\n' + ind + '}';
}

let g1r, json1;
try {
  g1r = generate();
  json1 = fmt(g1r.out, '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  process.exit(1);
}
// self-check d
const json2 = fmt(generate().out, '') + '\n';
const deterministic = json1 === json2;
// self-check 6
const allDisposed = created === disposed && created === 2 * cases.length;

const { tally, failed, totals } = g1r;
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks (pass/cases): ' + CHECKS.map(k => k + ' ' + tally[k][0] + '/' + (tally[k][0] + tally[k][1])).join(', ')
  + ', 6 ' + disposed + '/' + created + ' disposed, d ' + (deterministic ? 'identical' : 'DIFFERENT'));
console.log('discriminates (compared cases): ' + JSON.stringify(totals));
const zeroDisc = Object.keys(totals).filter(k => totals[k] < 1);
if (zeroDisc.length) console.log('self-check c failed: no case bites ' + zeroDisc.join(', '));
if (warnings.length) console.log(warnings.length + ' upstream warnings (e.g. ' + warnings[0].slice(0, 100) + ')');
const cs = g1r.out.cases;
const nDef = cs.filter(c => c.deferred).length;
const nDoc = cs.filter(c => c.documentary && !c.deferred).length;
const nRec = cs.reduce((n, c) => n + c.records.length, 0);
console.log((cs.length - nDef - nDoc) + ' compared + ' + nDoc + ' documentary + ' + nDef + ' deferred cases; ' + nRec + ' records; '
  + json1.length + ' bytes');
if (failed.length || zeroDisc.length || !deterministic || !allDisposed) {
  if (process.env.ORACLE_REJECTS) fs.writeFileSync(process.env.ORACLE_REJECTS, json1);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
