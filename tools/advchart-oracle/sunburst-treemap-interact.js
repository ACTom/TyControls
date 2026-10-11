// Upstream's own answers for sunburst and treemap INTERACTION (batch 115,
// roadmap C6): the sunburst's drill-down (a click on a piece, the return
// circle -- the virtual root's piece -- and the sunburstRootToNode action) and
// its transition; the treemap's click (nodeClick 'zoomToNode', a leaf root's
// rootToNode under leafDepth), the breadcrumb's clicks, the treemapZoomToNode
// / treemapRootToNode actions, the roam (treemapMove from a drag, treemapRender
// from the wheel) and the drill-down transition; hover and tooltip on both;
// containPixel on the sunburst; and the action events every gesture emits.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false
// (the browser's model), with the clock of animation.js: the global Date is
// replaced BEFORE the dist loads by one whose zero-argument form reads NOW,
// echarts.env.node is switched off (zrender animates; TooltipView runs, its
// content on the zrender canvas -- renderMode 'richText'; getDom is stubbed on
// the chart prototype as tooltip-finish.js does), Math.random is the port's
// xorshift32 (seed 2463534242, reset before each chart) and setTimeout is a
// queue that never runs (no case waits on a timer: the tooltip shows at once,
// showDelay 0). Every pointer step goes through zrender's own Handler with a
// synthetic event {zrX, zrY, zrDelta, which 1, preventDefault,
// stopPropagation}; before and after every event storage.getDisplayList(true)
// brings every transform up to date, as a paint does.
//
//   node tools/advchart-oracle/sunburst-treemap-interact.js
//
// writes tests/fixtures/advchart-sunburst-treemap-interact.json (ORACLE_OUT
// overrides). Ends with process.exit().
//
// ---------------------------------------------------------------------------
// The clock
//   NOW starts at T0 = 1700000000000 for every case. setOption runs at T0; a
//   case that animates first settles: {tick: 5000} steps the clock 5 s and runs
//   one frame (zr.animation.update()), so every enter animation has ended
//   before the first gesture. A gesture or an action renders and returns; the
//   clips its render made take their FIRST step -- their start time -- on the
//   next frame ({tick: dt}: NOW += dt, one frame), exactly as the port's
//   AnimTick does.
//
// Conventions
//   A Double is the 16 lowercase hex digits of its IEEE-754 bits (big-endian),
//   with a readable twin `<key>Text` beside it (String(v), '-0' for negative
//   zero); NaN / Infinity are null with the twin 'NaN' / 'Infinity'; absent is
//   null with a null twin. Pointer points are plain integers.
//
// Top level: source, seed, measure{...} (treemap.js' width table: the port
//   measures with it), notes[], cases[], guards[].
//
// Per case:
//   id, group ('sb-drill' | 'sb-action' | 'sb-hover' | 'sb-anim' |
//   'tm-click' | 'tm-crumb' | 'tm-action' | 'tm-roam' | 'tm-hover' |
//   'tm-anim'), note, W, H, option (as fed to setOption), probes [[x, y] ...]
//   (sunburst containPixel points), steps[]: each ONE of
//     {click: [x, y]}   Handler mousedown, mouseup, click at one point
//     {drag: [[x, y], ...]}  mousedown at the first, mousemove at each next,
//                       mouseup + click at the last
//     {hover: [x, y]}   mousemove
//     {wheel: [x, y, delta]}  mousewheel, zrDelta = delta / 120 (the LCL
//                       WheelDelta)
//     {action: payload} chart.dispatchAction(payload)
//     {resize: [W, H]}  chart.resize({width, height})
//     {tick: dt}        NOW += dt, one frame
//     {leave: true}     a mousemove outside the canvas
//   states[]: index-parallel to [after setOption, after step 1, ...]:
//     events[]  every action event the step emitted, in order:
//               {type (lowercase, as emitted), seriesIndex (from seriesId),
//               target (targetNode's dataIndex: a node object, or a string
//               resolved in that series; null), targetNodeId (as written,
//               or null), direction ('drillDown' | 'rollUp' | null),
//               rootRect null | [x, y, w, h] (hex)}
//     tip       null | {which: 'item:<series>:<dataIndex>', lines[{marker,
//               name, value}]}  (hover steps of a case with a tooltip)
//     clips     the number of clips still running after the step
//     series[]  one record per sunburst / treemap, in series index order:
//       index, type
//       SUNBURST:
//         viewRoot  the view root's dataIndex (0: the virtual root)
//         pieces[]  every piece in the view's group, ordered by dataIndex
//                   (the virtual piece -- the return circle -- has v true):
//           di, v, sh[6] (cx cy r0 r startAngle endAngle), cr (cornerRadius
//           as set: a number or [4]) , fill (style.fill as a string), op
//           (style.opacity), z2, hover (hoverState) and states
//           ('a,b' currentStates) in a hover case,
//           label null | {text (null when none), x, y, rot, align, vAlign,
//           ignore, op}
//         contain   '0' / '1' per probe: chart.containPixel({seriesIndex}, p)
//       TREEMAP:
//         viewRoot, root[4]  the tree root's layout x y width height
//         nodes[]   every node with an element in the view's storage, by
//                   dataIndex: {di, g[2] (its group's x, y: local),
//                   bg / ct null | {sh[4] x y w h (local), t null | [2]
//                   (the global translation: transform[4..5]), op, inv
//                   (invisible), fill, z2, hover, states,
//                   label null | {text, t[2], op, ign, align, vAlign}}}
//         ghosts[]  every rect under the container group that is in no
//                   storage (a deleted element still leaving): {di, kind
//                   'bg' | 'ct', sh[4], t, op}
//         crumbs[]  the breadcrumb, left to right: {di, text, pts[] (global:
//                   the polygon's points through its group), lx, ly (the
//                   text's global translation)}
//         state     the view's _state ('ready' | 'animating')
//
// Self-checks (any failure: nothing is written, exit 1):
//   R1 sunburst drill layout: with the view root at depth d, rPerLevel =
//      (r - r0) / (height(viewRoot) + 1), the view root a full turn on the
//      second ring and the return circle r0 .. r0 + rPerLevel on the first
//   R2 the return circle's layout outlives a roll-up: containPixel stays true
//   R3 zoomToNode: estimateRootSize (Math.pow(area, 0.5) and all) and the
//      clamp give the root's size; calculateRootPosition centres the target
//   R4 treemapMove: the root moves by the pointer's delta; a move of 3 px or
//      less on both axes is dropped (its delta lost, not carried)
//   R5 treemapRender: the root rect scaled about the pointer by the matrix
//      recipe of _onZoom, the zoom clamped by scaleLimit
//   R6 a kept piece's shape at a sample is from + (to - from) * cubicInOut(p)
//   R7 a treemap group's x at a sample is from + (to - from) * quinticInOut(p)
//   R8 a click while the treemap animates does nothing
//   plus discriminating counts (each >= 1), two generations in one process
//   giving the same bytes, no \u0000, and the JSON parsing back.
'use strict';
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
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-sunburst-treemap-interact.json');

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

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const tx = v => (v == null ? null : Object.is(v, -0) ? '-0' : String(v));
function hx(v) {
  if (v == null) return null;
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (!Number.isFinite(v)) return null;
  return hex(v);
}
function put(o, k, v) {
  if (Array.isArray(v)) { o[k] = v.map(hx); o[k + 'Text'] = v.map(tx); }
  else { o[k] = hx(v); o[k + 'Text'] = tx(v); }
  return o;
}

// ---------- zrender's width table (treemap.js) ----------
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
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, extra) {
  refresh(chart);
  zr(chart).handler[name](zev(extra));
  refresh(chart);
}
function clipCount(chart) {
  let n = 0;
  for (let c = zr(chart).animation._head; c; c = c.next) n++;
  return n;
}
function eventDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && el[k].eventData) return el[k].eventData;
  }
  return null;
}
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}
function hierSeries(chart) {
  const out = [];
  chart.getModel().eachSeries(s => { if (s.subType === 'sunburst' || s.subType === 'treemap') out.push(s); });
  return out;
}
function nodeOf(s, di) { return s.getData().tree.getNodeByDataIndex(di); }

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
    rec.which = Array.isArray(params) ? 'axis' : 'item:' + params.seriesIndex + ':' + params.dataIndex;
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

// ---------- snapshots ----------
function labelRecSb(el) {
  const t = el.getTextContent();
  if (!t) return null;
  const o = { text: t.style.text == null ? null : String(t.style.text) };
  put(o, 'x', t.x); put(o, 'y', t.y); put(o, 'rot', t.rotation);
  o.align = t.style.align == null ? null : t.style.align;
  o.vAlign = t.style.verticalAlign == null ? null : t.style.verticalAlign;
  o.ignore = !!t.ignore;
  put(o, 'op', t.style.opacity == null ? 1 : t.style.opacity);
  return o;
}
function snapSunburst(chart, s, withStates) {
  const v = chart.getViewOfSeriesModel(s);
  const o = { index: s.seriesIndex, type: 'sunburst', viewRoot: s.getViewRoot().dataIndex };
  const pieces = [];
  for (const el of v.group.children()) {
    const ecd = ecDataOf(el);
    const p = { di: ecd ? ecd.dataIndex : null, v: el === v.virtualPiece };
    const sh = el.shape;
    put(p, 'sh', [sh.cx, sh.cy, sh.r0, sh.r, sh.startAngle, sh.endAngle]);
    if (Array.isArray(sh.cornerRadius)) put(p, 'cr', sh.cornerRadius.slice());
    else put(p, 'cr', sh.cornerRadius == null ? 0 : sh.cornerRadius);
    p.fill = el.style.fill == null ? null : String(el.style.fill);
    put(p, 'op', el.style.opacity == null ? 1 : el.style.opacity);
    p.z2 = el.z2;
    if (withStates) {
      p.hover = el.hoverState || 0;
      p.states = (el.currentStates || []).join(',');
    }
    p.label = labelRecSb(el);
    pieces.push(p);
  }
  pieces.sort((a, b) => (a.v ? -1 : a.di) - (b.v ? -1 : b.di));
  o.pieces = pieces;
  return o;
}
function rectRec(el, withStates) {
  if (!el) return null;
  const o = {};
  put(o, 'sh', [el.shape.x, el.shape.y, el.shape.width, el.shape.height]);
  if (el.transform) put(o, 't', [el.transform[4], el.transform[5]]);
  else { o.t = null; o.tText = null; }
  put(o, 'op', el.style.opacity == null ? 1 : el.style.opacity);
  o.inv = !!el.invisible;
  o.fill = el.style.fill == null ? null : String(el.style.fill);
  o.z2 = el.z2;
  if (withStates) {
    o.hover = el.hoverState || 0;
    o.states = (el.currentStates || []).join(',');
  }
  const t = el.getTextContent();
  if (t) {
    const l = { text: t.style.text == null ? null : String(t.style.text) };
    if (t.transform) put(l, 't', [t.transform[4], t.transform[5]]);
    else put(l, 't', [t.x, t.y]);
    put(l, 'op', t.style.opacity == null ? 1 : t.style.opacity);
    l.ign = !!t.ignore;
    l.inv = !!t.invisible;
    l.align = t.style.align == null ? null : t.style.align;
    l.vAlign = t.style.verticalAlign == null ? null : t.style.verticalAlign;
    // the drawn lines: zrender's truncation of the moment (Text._updateSubTexts)
    l.lines = t.childrenRef().map(k => String(k.style.text));
    o.label = l;
  }
  else o.label = null;
  return o;
}
function snapTreemap(chart, s, withStates, seen) {
  const v = chart.getViewOfSeriesModel(s);
  const o = { index: s.seriesIndex, type: 'treemap', viewRoot: s.getViewRoot().dataIndex };
  const rl = s.getData().tree.root.getLayout();
  if (rl) put(o, 'root', [rl.x, rl.y, rl.width, rl.height]);
  else { o.root = null; o.rootText = null; }
  const st = v._storage;
  const known = new Set();
  o.nodes = [];
  const n = s.getData().count();
  for (let i = 0; i < n; i++) {
    const g = st.nodeGroup[i];
    if (!g) continue;
    known.add(g);
    if (st.background[i]) { known.add(st.background[i]); seen.set(st.background[i], { di: i, kind: 'bg' }); }
    if (st.content[i]) { known.add(st.content[i]); seen.set(st.content[i], { di: i, kind: 'ct' }); }
    const rec = { di: i };
    put(rec, 'g', [g.x, g.y]);
    rec.bg = rectRec(st.background[i], withStates);
    rec.ct = rectRec(st.content[i], withStates);
    o.nodes.push(rec);
  }
  o.ghosts = [];
  const cg = v._containerGroup;
  if (cg) {
    cg.traverse(el => {
      if (el.type !== 'rect' || known.has(el)) return;
      // a ghost is a rect an earlier snapshot saw in the storage: the node it was drawn for
      // (its ECData may name another: setItemGraphicEl on a leaf's group renumbers all below it)
      const who = seen.get(el);
      must(who, 'a rect under the container that was never in the storage');
      const r = rectRec(el, false);
      r.di = who.di;
      r.kind = who.kind;
      const ecd = ecDataOf(el);
      r.ecDi = ecd ? ecd.dataIndex : null;
      o.ghosts.push(r);
    });
  }
  o.crumbs = [];
  const bc = v._breadcrumb && v._breadcrumb.group;
  if (bc) {
    const m = bc.transform || [1, 0, 0, 1, 0, 0];
    for (const el of bc.children()) {
      const ev = eventDataOf(el);
      const c = { di: ev && ev.nodeData ? ev.nodeData.dataIndex : null };
      const t = el.getTextContent();
      c.text = t && t.style.text != null ? String(t.style.text) : null;
      const pts = [];
      for (const p of el.shape.points) pts.push(m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]);
      put(c, 'pts', pts);
      if (t && t.transform) put(c, 'l', [t.transform[4], t.transform[5]]);
      else { c.l = null; c.lText = null; }
      o.crumbs.push(c);
    }
  }
  o.state = v._state;
  return o;
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
  for (let r = 0; r <= 12; r++) {
    for (let dy = -r; dy <= r; dy++) {
      for (let dx = -r; dx <= r; dx++) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
        if (ok(x0 + dx, y0 + dy)) return [x0 + dx, y0 + dy];
      }
    }
  }
  throw new OracleError(where + ': no point found near ' + x0 + ',' + y0);
}
function sbPoint(chart, si, di, virt, where) {
  const s = chart.getModel().getSeriesByIndex(si);
  const v = chart.getViewOfSeriesModel(s);
  const piece = virt ? v.virtualPiece : v.group.children().find(el => el !== v.virtualPiece && ecDataOf(el).dataIndex === di);
  must(piece, where + ': no piece ' + di);
  const sh = piece.shape;
  const mid = (sh.startAngle + sh.endAngle) / 2;
  const rr = sh.r0 === 0 && Math.abs(sh.endAngle - sh.startAngle - 2 * Math.PI) < 1e-6 ? sh.r / 2 : (sh.r + sh.r0) / 2;
  const x0 = Math.round(sh.cx + rr * Math.cos(mid));
  const y0 = Math.round(sh.cy + rr * Math.sin(mid));
  return spiral(x0, y0, (x, y) => hostOf(hoverTarget(chart, x, y)) === piece, where);
}
function tmGlobalRect(el) {
  const m = el.transform || [1, 0, 0, 1, 0, 0];
  return [el.shape.x + m[4], el.shape.y + m[5], el.shape.width, el.shape.height];
}
function tmPoint(chart, si, di, where) {
  const s = chart.getModel().getSeriesByIndex(si);
  const v = chart.getViewOfSeriesModel(s);
  refresh(chart);
  const el = v._storage.content[di] || v._storage.background[di];
  must(el, where + ': no rect for ' + di);
  const r = tmGlobalRect(el);
  const x0 = Math.round(r[0] + r[2] / 2);
  const y0 = Math.round(r[1] + r[3] / 2);
  return spiral(x0, y0, (x, y) => {
    const t = v.findTarget(x, y);
    return t && t.node.dataIndex === di && hoverTarget(chart, x, y) != null;
  }, where);
}
function crumbPoint(chart, si, k, where) {
  const s = chart.getModel().getSeriesByIndex(si);
  const v = chart.getViewOfSeriesModel(s);
  refresh(chart);
  const bc = v._breadcrumb.group;
  const el = bc.children()[k];
  must(el, where + ': no crumb ' + k);
  const m = bc.transform || [1, 0, 0, 1, 0, 0];
  const pts = el.shape.points;
  let sx = 0;
  let sy = 0;
  for (const p of pts) { sx += p[0]; sy += p[1]; }
  const x0 = Math.round(sx / pts.length + m[4]);
  const y0 = Math.round(sy / pts.length + m[5]);
  return spiral(x0, y0, (x, y) => hostOf(hoverTarget(chart, x, y)) === el || hoverTarget(chart, x, y) === el
    || (hoverTarget(chart, x, y) && hoverTarget(chart, x, y).__hostTarget === el), where);
}
function resolvePoint(chart, t, where) {
  if (Array.isArray(t)) return t.slice();
  if (t.sb !== undefined) return sbPoint(chart, t.si || 0, t.sb, false, where);
  if (t.sbV) return sbPoint(chart, t.si || 0, 0, true, where);
  if (t.tm !== undefined) return tmPoint(chart, t.si || 0, t.tm, where);
  if (t.crumb !== undefined) return crumbPoint(chart, t.si || 0, t.crumb, where);
  throw new OracleError(where + ': an unknown target ' + JSON.stringify(t));
}

// ---------- events ----------
const ACTION_EVENTS = ['sunburstroottonode', 'treemapzoomtonode', 'treemaproottonode', 'treemapmove', 'treemaprender'];
function seriesIndexOfId(chart, id) {
  let out = null;
  chart.getModel().eachSeries(s => { if (s.id === id) out = s.seriesIndex; });
  return out;
}
function eventRec(chart, p) {
  const o = { type: p.type };
  o.seriesIndex = p.seriesId != null ? seriesIndexOfId(chart, p.seriesId) : null;
  let target = null;
  if (p.targetNode && typeof p.targetNode === 'object') target = p.targetNode.dataIndex;
  else if (typeof p.targetNode === 'string' && o.seriesIndex != null) {
    const s = chart.getModel().getSeriesByIndex(o.seriesIndex);
    const n = s.getData().tree.root.getNodeById(p.targetNode);
    target = n ? n.dataIndex : null;
  }
  o.target = target;
  o.targetNode = typeof p.targetNode === 'string' ? p.targetNode : null;
  o.targetNodeId = p.targetNodeId == null ? null : String(p.targetNodeId);
  o.direction = p.direction == null ? null : p.direction;
  if (p.rootRect) put(o, 'rootRect', [p.rootRect.x, p.rootRect.y, p.rootRect.width, p.rootRect.height]);
  else { o.rootRect = null; o.rootRectText = null; }
  return o;
}

// ---------- a case ----------
function runCase(c) {
  let W = c.W;
  let H = c.H;
  const chart = mk(W, H);
  const events = [];
  for (const t of ACTION_EVENTS) chart.on(t, p => events.push(eventRec(chart, p)));
  const tipRec = { which: null };
  const states = [];
  const steps = [];
  const withStates = !!c.states;
  const seen = new Map();
  const snap = () => {
    // a frame's echarts half: the state flags become states (applyChangedStates)
    chart._onframe();
    refresh(chart);
    const st = { events: events.splice(0), clips: clipCount(chart), tip: null, series: [] };
    for (const s of hierSeries(chart)) {
      const r = s.subType === 'sunburst' ? snapSunburst(chart, s, withStates) : snapTreemap(chart, s, withStates, seen);
      if (s.subType === 'sunburst' && c.probes) r.contain = c.probes.map(p => (chart.containPixel({ seriesIndex: s.seriesIndex }, p) ? '1' : '0'));
      st.series.push(r);
    }
    return st;
  };
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    hookTooltip(chart, tipRec);
    refresh(chart);
    states.push(snap());
    c.steps.forEach((step, i) => {
      const where = c.id + ' step ' + i;
      let out;
      tipRec.which = null;
      if (step.click !== undefined) {
        const p = resolvePoint(chart, step.click, where);
        fire(chart, 'mousedown', { zrX: p[0], zrY: p[1] });
        fire(chart, 'mouseup', { zrX: p[0], zrY: p[1] });
        fire(chart, 'click', { zrX: p[0], zrY: p[1] });
        out = { click: p };
      }
      else if (step.drag) {
        const pts = step.drag.map(t => resolvePoint(chart, t, where));
        fire(chart, 'mousedown', { zrX: pts[0][0], zrY: pts[0][1] });
        for (let k = 1; k < pts.length; k++) fire(chart, 'mousemove', { zrX: pts[k][0], zrY: pts[k][1] });
        const e = pts[pts.length - 1];
        fire(chart, 'mouseup', { zrX: e[0], zrY: e[1] });
        fire(chart, 'click', { zrX: e[0], zrY: e[1] });
        out = { drag: pts };
      }
      else if (step.hover !== undefined) {
        const p = resolvePoint(chart, step.hover, where);
        fire(chart, 'mousemove', { zrX: p[0], zrY: p[1] });
        out = { hover: p };
      }
      else if (step.wheel) {
        fire(chart, 'mousewheel', { zrX: step.wheel[0], zrY: step.wheel[1], zrDelta: step.wheel[2] / 120 });
        out = { wheel: step.wheel.slice() };
      }
      else if (step.action) {
        chart.dispatchAction(JSON.parse(JSON.stringify(step.action)));
        out = { action: step.action };
      }
      else if (step.resize) {
        W = step.resize[0];
        H = step.resize[1];
        chart.resize({ width: W, height: H });
        out = { resize: step.resize.slice() };
      }
      else if (step.tick !== undefined) {
        NOW += step.tick;
        zr(chart).animation.update();
        out = { tick: step.tick };
      }
      else if (step.leave) {
        fire(chart, 'mousemove', { zrX: -10, zrY: -10 });
        out = { leave: true };
      }
      else throw new OracleError(where + ': an unknown step ' + JSON.stringify(step));
      steps.push(out);
      const st = snap();
      if (step.hover !== undefined || step.leave) st.tip = tipNow(chart, tipRec, where);
      states.push(st);
    });
  } finally {
    chart.dispose();
  }
  return { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option,
    probes: c.probes || null, states: withStates, steps, statesList: states };
}

// ---------- the cases ----------
const SB_DATA = [
  { name: 'a', children: [
    { name: 'a1', value: 3, children: [{ name: 'a11', value: 1 }, { name: 'a12', value: 2 }] },
    { name: 'a2', value: 2 }] },
  { name: 'b', value: 4, children: [{ name: 'b1', value: 4 }] },
  { name: 'c', value: 1 },
];
const TM_DATA = [
  { name: 'a', children: [
    { name: 'a1', value: 6, children: [{ name: 'a11', value: 4 }, { name: 'a12', value: 2 }] },
    { name: 'a2', value: 4 }] },
  { name: 'b', children: [{ name: 'b1', value: 3 }, { name: 'b2', value: 3 }] },
  { name: 'c', value: 4 },
];
// sunburst rows (pre-order): 0 root, 1 a, 2 a1, 3 a11, 4 a12, 5 a2, 6 b, 7 b1, 8 c
// treemap rows: 0 root, 1 a, 2 a1, 3 a11, 4 a12, 5 a2, 6 b, 7 b1, 8 b2, 9 c
const clone = v => JSON.parse(JSON.stringify(v));
const SB_PROBES = [[200, 200], [210, 200], [200, 150], [250, 250], [380, 200], [5, 5], [200, 120], [140, 200]];
function sb(extra, top) {
  return Object.assign({ animation: false, series: [Object.assign({ type: 'sunburst', name: 'S', animation: false, data: clone(SB_DATA) }, extra || {})] }, top || {});
}
function tm(extra, top) {
  return Object.assign({ animation: false, series: [Object.assign({ type: 'treemap', name: 'T', animation: false, data: clone(TM_DATA) }, extra || {})] }, top || {});
}
const TM_BORDERED = [
  { itemStyle: { borderWidth: 3, gapWidth: 2 } },
  { itemStyle: { borderWidth: 2, gapWidth: 1, borderColor: '#aaa' } },
  { itemStyle: { borderWidth: 1, gapWidth: 1 } },
];

const CASES = [
  // ---------------- sunburst ----------------
  { id: 'sb-drill', group: 'sb-drill', note: 'click a root piece, then a piece of the drilled view, the view root itself (nothing), the return circle twice; a leaf; a resize keeps the view root',
    W: 400, H: 400, option: sb(), probes: SB_PROBES,
    steps: [{ click: { sb: 1 } }, { click: { sb: 2 } }, { click: { sb: 2 } }, { click: { sbV: true } }, { click: { sbV: true } },
      { click: { sb: 8 } }, { resize: [320, 380] }, { click: { sbV: true } }] },
  { id: 'sb-drill-noname', group: 'sb-drill', note: 'a series with no name: the return circle has no words; a drill to a node with value 0 hidden',
    W: 400, H: 400, option: { animation: false, series: [{ type: 'sunburst', data: [
      { name: 'p', children: [{ name: 'p1', value: 2 }, { name: 'p0', value: 0 }, { name: 'p2', value: 1, children: [{ name: 'p21', value: 1 }] }] },
      { name: 'q', value: 3 }] }] }, probes: SB_PROBES,
    steps: [{ click: { sb: 1 } }, { click: { sb: 4 } }, { click: { sbV: true } }] },
  { id: 'sb-drill-shape', group: 'sb-drill', note: "radius [20, '80%'], startAngle 30, clockwise false, a level radius (levels are by absolute depth), cornerRadius 4, label rotate 'tangential' and align 'left'",
    W: 420, H: 360, option: sb({ radius: [20, '80%'], startAngle: 30, clockwise: false, itemStyle: { borderRadius: 4 },
      label: { rotate: 'tangential', align: 'left' }, levels: [{}, {}, { radius: [100, 130] }] }), probes: SB_PROBES,
    steps: [{ click: { sb: 1 } }, { click: { sb: 2 } }, { click: { sbV: true } }] },
  { id: 'sb-nodeclick', group: 'sb-drill', note: "nodeClick false on the series, 'rootToNode' on level 2 (item -> level -> series): a root piece does nothing, a level-2 piece drills; 'link' on an item without a link does nothing",
    W: 400, H: 400, option: sb({ nodeClick: false, levels: [{}, {}, { nodeClick: 'rootToNode' }] }),
    steps: [{ click: { sb: 1 } }, { click: { sb: 2 } }, { click: { sbV: true } }, { click: { sbV: true } }, { click: { sb: 7 } }] },
  { id: 'sb-action', group: 'sb-action', note: 'sunburstRootToNode by id (the name), by targetNodeId, an unknown id, the root by the series name; on two sunbursts with no query and with a seriesIndex',
    W: 600, H: 300, option: { animation: false, series: [
      { type: 'sunburst', name: 'S', center: ['25%', '50%'], data: clone(SB_DATA) },
      { type: 'sunburst', name: 'U', center: ['75%', '50%'], data: [{ name: 'a', children: [{ name: 'a1', value: 1 }, { name: 'zz', value: 2 }] }, { name: 'b', value: 2 }] }] },
    steps: [{ action: { type: 'sunburstRootToNode', targetNode: 'a1' } }, { action: { type: 'sunburstRootToNode', seriesIndex: 1, targetNodeId: 'zz' } },
      { action: { type: 'sunburstRootToNode', seriesIndex: 0, targetNode: 'nope' } }, { action: { type: 'sunburstRootToNode', targetNode: 'b' } },
      { action: { type: 'sunburstRootToNode', seriesIndex: 0, targetNode: 'S' } }, { resize: [500, 260] }] },
  { id: 'sb-hover', group: 'sb-hover', note: 'tooltip and focus descendant after a drill: a piece, the return circle (dataIndex 0), the view root, off the chart',
    W: 400, H: 400, states: true, option: sb({}, { tooltip: { renderMode: 'richText' } }),
    steps: [{ action: { type: 'sunburstRootToNode', targetNode: 'a' } }, { hover: { sb: 2 } }, { hover: { sbV: true } }, { hover: { sb: 1 } }, { leave: true },
      { hover: { sb: 3 } }, { action: { type: 'sunburstRootToNode', targetNode: 'S' } }, { hover: { sb: 6 } }, { leave: true }] },
  { id: 'sb-anim', group: 'sb-anim', note: 'the drill-down transition with the default timings (update 500 cubicInOut, enter 1000 cubicOut): kept pieces and labels move, the return circle and new pieces grow r from r0, new labels fade',
    W: 400, H: 400, option: sb({ animation: true }, { animation: true }),
    steps: [{ tick: 5000 }, { click: { sb: 1 } }, { tick: 16 }, { tick: 84 }, { tick: 150 }, { tick: 166 }, { tick: 100 }, { tick: 300 }, { tick: 400 },
      { click: { sbV: true } }, { tick: 16 }, { tick: 134 }, { tick: 250 }, { tick: 300 }, { tick: 600 }] },
  { id: 'sb-anim-opts', group: 'sb-anim', note: "animationDurationUpdate 300, animationEasingUpdate 'linear', animationDuration 400, animationEasing 'quadraticOut', animationDelayUpdate 50; a drill by action then a roll-up by action",
    W: 400, H: 400, option: sb({ animation: true, animationDurationUpdate: 300, animationEasingUpdate: 'linear', animationDuration: 400,
      animationEasing: 'quadraticOut', animationDelayUpdate: 50 }, { animation: true }),
    steps: [{ tick: 5000 }, { action: { type: 'sunburstRootToNode', targetNode: 'b' } }, { tick: 16 }, { tick: 100 }, { tick: 100 }, { tick: 150 }, { tick: 200 },
      { action: { type: 'sunburstRootToNode', targetNode: 'S' } }, { tick: 16 }, { tick: 120 }, { tick: 200 }, { tick: 400 }] },
  // ---------------- treemap ----------------
  { id: 'tm-click', group: 'tm-click', note: 'click a leaf (zoomToNode: centred, the size by estimateRootSize), then another; nodeClick on a node far out of view',
    W: 600, H: 400, option: tm(),
    steps: [{ click: { tm: 3 } }, { click: { tm: 4 } }, { click: { tm: 9 } }, { click: { tm: 7 } }] },
  { id: 'tm-click-ratio', group: 'tm-click', note: 'zoomToNodeRatio 0.5 and a border / gap per level: estimateRootSize grows the root, the border terms and the clamp by scaleLimit max 2',
    W: 600, H: 400, option: tm({ zoomToNodeRatio: 0.5, levels: clone(TM_BORDERED), scaleLimit: { max: 2 } }),
    steps: [{ click: { tm: 4 } }, { click: { tm: 7 } }, { click: { tm: 9 } }] },
  { id: 'tm-click-big', group: 'tm-click', note: 'a deep small leaf: zoomToNode makes the root several times the box; the default scaleLimit (max 5) caps it',
    W: 600, H: 400, option: tm({ data: [
      { name: 'big', value: 90 },
      { name: 'small', children: [{ name: 's1', value: 6, children: [{ name: 's11', value: 1 }, { name: 's12', value: 5 }] }, { name: 's2', value: 4 }] }] }),
    steps: [{ click: { tm: 4 } }, { click: { crumb: 0 } }, { click: { tm: 5 } }] },
  { id: 'tm-leafdepth', group: 'tm-click', note: 'leafDepth 1: a click on a leaf root drills (rootToNode), again one level down, the breadcrumb root rolls up',
    W: 600, H: 400, option: tm({ leafDepth: 1 }),
    steps: [{ click: { tm: 1 } }, { click: { tm: 2 } }, { click: { crumb: 0 } }, { click: { tm: 6 } }, { click: { crumb: 0 } }] },
  { id: 'tm-nodeclick', group: 'tm-click', note: "nodeClick false (no zoom, no drill even on a leaf root under leafDepth); nodeClick 'link' with no link does nothing",
    W: 600, H: 400, option: { animation: false, series: [
      { type: 'treemap', name: 'T', animation: false, data: clone(TM_DATA), nodeClick: false, leafDepth: 1, left: 0, right: '50%' },
      { type: 'treemap', name: 'L', animation: false, data: clone(TM_DATA), nodeClick: 'link', left: '50%', right: 0 }] },
    steps: [{ click: { tm: 1, si: 0 } }, { click: { tm: 3, si: 1 } }] },
  { id: 'tm-crumb', group: 'tm-crumb', note: 'the breadcrumb: zoom into a leaf, click the middle crumb (zoomToNode a), the root crumb (zoomToNode root: the default size)',
    W: 600, H: 400, option: tm(),
    steps: [{ click: { tm: 3 } }, { click: { crumb: 1 } }, { click: { crumb: 0 } }, { click: { tm: 7 } }, { click: { crumb: 2 } }] },
  { id: 'tm-crumb-roam', group: 'tm-crumb', note: 'the breadcrumb after a pan finds the node under the centre with the transforms of the last paint',
    W: 600, H: 400, option: tm(),
    steps: [{ drag: [[300, 200], [380, 220]] }, { drag: [[300, 200], [150, 180]] }, { wheel: [450, 120, 120] }] },
  { id: 'tm-action', group: 'tm-action', note: 'treemapZoomToNode by id, treemapRootToNode by targetNodeId, an unknown id, the root back by the series name; a resize keeps the view root',
    W: 600, H: 400, option: tm(),
    steps: [{ action: { type: 'treemapZoomToNode', targetNode: 'a1' } }, { action: { type: 'treemapRootToNode', targetNodeId: 'b' } },
      { action: { type: 'treemapZoomToNode', targetNode: 'nope' } }, { action: { type: 'treemapZoomToNode', targetNode: 'b2' } },
      { resize: [500, 360] }, { action: { type: 'treemapRootToNode', seriesIndex: 0, targetNode: 'T' } }] },
  { id: 'tm-roam', group: 'tm-roam', note: 'a drag pans by treemapMove; moves of 3 px or less are dropped; the wheel zooms about the pointer (treemapRender); a click after a roam zooms to the node',
    W: 600, H: 400, option: tm(),
    steps: [{ drag: [[300, 200], [302, 201], [310, 210], [311, 212], [340, 230]] }, { wheel: [200, 150, 120] }, { wheel: [200, 150, 120] },
      { wheel: [400, 300, -120] }, { wheel: [100, 100, 360] }, { click: { tm: 5 } }] },
  { id: 'tm-roam-limit', group: 'tm-roam', note: 'scaleLimit {min 0.5, max 1.5} clamps the wheel; the clamp holds the rect where it is',
    W: 600, H: 400, option: tm({ scaleLimit: { min: 0.5, max: 1.5 } }),
    steps: [{ wheel: [300, 200, 120] }, { wheel: [300, 200, 120] }, { wheel: [300, 200, 120] }, { wheel: [300, 200, 120] }, { wheel: [100, 50, 120] },
      { wheel: [300, 200, -120] }, { wheel: [300, 200, -120] }, { wheel: [300, 200, -120] }, { wheel: [300, 200, -120] }, { wheel: [300, 200, -120] }, { wheel: [300, 200, -120] }] },
  { id: 'tm-roam-move', group: 'tm-roam', note: "roam 'move': the wheel does nothing, a drag pans",
    W: 600, H: 400, option: tm({ roam: 'move' }),
    steps: [{ wheel: [150, 200, 120] }, { drag: [[150, 200], [170, 205]] }, { wheel: [300, 200, -120] }] },
  { id: 'tm-roam-off', group: 'tm-roam', note: "roam false with roamTrigger 'selfRect': a drag does nothing and its release, within 4 px, is a click",
    W: 600, H: 400, option: tm({ roam: false, roamTrigger: 'selfRect' }),
    steps: [{ drag: [[450, 200], [470, 210]] }, { drag: [[150, 200], [152, 202]] }, { wheel: [300, 200, 120] }] },
  { id: 'tm-hover', group: 'tm-hover', note: 'tooltip and emphasis: a leaf (its group dispatches: both rects lifted, z2 + 10), a parent through its border, the breadcrumb, off the chart',
    W: 600, H: 400, states: true, option: tm({ levels: clone(TM_BORDERED) }, { tooltip: { renderMode: 'richText' } }),
    steps: [{ hover: { tm: 3 } }, { hover: [21, 200] }, { hover: { tm: 9 } }, { hover: { crumb: 0 } }, { leave: true }, { click: { tm: 3 } }, { hover: { tm: 4 } }, { leave: true }] },
  { id: 'tm-anim-zoom', group: 'tm-anim', note: 'the zoomToNode transition (900 ms quinticInOut): the root group slides and grows, new nodes come in from the parent corner and fade',
    W: 600, H: 400, option: tm({ animation: true }, { animation: true }),
    steps: [{ tick: 5000 }, { click: { tm: 3 } }, { tick: 16 }, { tick: 84 }, { tick: 200 }, { tick: 250 }, { tick: 300 }, { tick: 200 },
      { click: { crumb: 0 } }, { tick: 16 }, { tick: 300 }, { tick: 300 }, { tick: 400 }] },
  { id: 'tm-anim-big', group: 'tm-anim', note: 'a zoom that grows the root: rects keep, scale and leave the view (made invisible at the end)',
    W: 600, H: 400, option: tm({ animation: true, data: [
      { name: 'big', value: 90 },
      { name: 'small', children: [{ name: 's1', value: 6, children: [{ name: 's11', value: 1 }, { name: 's12', value: 5 }] }, { name: 's2', value: 4 }] }] }, { animation: true }),
    steps: [{ tick: 5000 }, { click: { tm: 4 } }, { tick: 16 }, { tick: 300 }, { tick: 300 }, { tick: 400 }] },
  { id: 'tm-anim-drill', group: 'tm-anim', note: 'leafDepth 1: rootToNode drill (the deleted nodes fade, the new ones come in), a click while it runs does nothing, then a roll-up from the breadcrumb',
    W: 600, H: 400, option: tm({ animation: true, leafDepth: 1 }, { animation: true }),
    steps: [{ tick: 5000 }, { click: { tm: 1 } }, { tick: 16 }, { tick: 150 }, { click: { tm: 2 } }, { tick: 300 }, { tick: 450 },
      { click: { crumb: 0 } }, { tick: 16 }, { tick: 250 }, { tick: 300 }, { tick: 400 }] },
  { id: 'tm-anim-opts', group: 'tm-anim', note: "animationDurationUpdate 400, animationEasing 'linear' (the treemap animates with animationEasing); a pan while it runs does nothing, after it pans and does not animate (the pointer leaves the canvas: no hover, whose state transition is not ported)",
    W: 600, H: 400, option: tm({ animation: true, animationDurationUpdate: 400, animationEasing: 'linear' }, { animation: true }),
    steps: [{ tick: 5000 }, { action: { type: 'treemapZoomToNode', targetNode: 'b1' } }, { tick: 16 }, { tick: 100 }, { tick: 200 }, { tick: 200 },
      { drag: [[300, 30], [320, -5]] }, { tick: 600 }, { drag: [[300, 30], [340, -5]] }, { tick: 16 }] },
];

// ---------- the guards ----------
const H = 1e-12;
function guards(out) {
  const g = [];
  const guard = (id, ok, detail) => g.push({ id, ok: !!ok, detail: detail || '' });
  const cs = id => out.find(c => c.id === id);
  const num = (o, k, i) => { const t = o[k + 'Text']; const v = i === undefined ? t : t[i]; return v == null ? NaN : Number(v); };
  // R1
  {
    const c = cs('sb-drill');
    const st = c.statesList[1].series[0];
    const vr = st.pieces.find(p => p.di === 1 && !p.v);
    const vp = st.pieces.find(p => p.v);
    // r = 150 (75% of 200); a's height 3 (a leaf is 1) -> levels 4, rPerLevel 150 / 4
    guard('R1 the view root is a full turn on the second ring', vr && Math.abs(num(vr, 'sh', 5) - num(vr, 'sh', 4) - 2 * Math.PI) < 1e-9
      && num(vr, 'sh', 2) === 150 / 4 && num(vr, 'sh', 3) === 150 / 4 * 2, JSON.stringify(vr && vr.shText));
    guard('R1 the return circle is r0 .. r0 + rPerLevel', vp && num(vp, 'sh', 2) === 0 && num(vp, 'sh', 3) === 150 / 4 && vp.di === 0, JSON.stringify(vp && vp.shText));
  }
  // R2
  {
    const c = cs('sb-drill');
    const last = c.statesList[5].series[0];
    guard('R2 back at the root, the return circle is gone but containPixel at the centre stays true',
      last.viewRoot === 0 && !last.pieces.some(p => p.v) && last.contain[0] === '1' && c.statesList[0].series[0].contain[0] === '0',
      JSON.stringify(last.contain));
  }
  // R3: estimateRootSize recipe on tm-click-ratio's first click (a12, row 4)
  {
    const c = cs('tm-click-ratio');
    const o = c.option.series[0];
    const W = c.W - 40;
    const Hh = c.H - 100;
    const values = { 4: 2, 2: 6, 1: 10, 0: 20 };
    const sums = { 2: 6, 1: 10, 0: 20 };
    const parent = { 4: 2, 2: 1, 1: 0 };
    const depth = { 2: 2, 1: 1, 0: 0 };
    let area = W * Hh * o.zoomToNodeRatio;
    let cur = 4;
    while (parent[cur] !== undefined) {
      const p = parent[cur];
      area *= sums[p] / values[cur];
      const bw = o.levels[depth[p]].itemStyle.borderWidth;
      area += 4 * bw * bw + (3 * bw + Math.max(bw, 0)) * Math.pow(area, 0.5);
      cur = p;
    }
    if (area < W * Hh) area = W * Hh;
    let zoom = Math.pow(area / (W * Hh), 0.5);
    zoom = Math.min(Math.max(zoom, 0.2), 2);
    const root = c.statesList[1].series[0];
    guard('R3 zoomToNode sizes the root by estimateRootSize and the clamp', num(root, 'root', 2) === W * zoom && num(root, 'root', 3) === Hh * zoom,
      root.rootText.join(' ') + ' vs ' + (W * zoom));
  }
  // R4: the drag in tm-roam: 300,200 -> 302,201 (dropped) -> 310,210 (+8,+9) -> 311,212 (dropped) -> 340,230 (+29,+18)
  {
    const c = cs('tm-roam');
    const before = c.statesList[0].series[0];
    const after = c.statesList[1].series[0];
    const moves = c.statesList[1].events.filter(e => e.type === 'treemapmove');
    guard('R4 two moves dispatched, the small ones dropped', moves.length === 2, JSON.stringify(moves.map(e => e.rootRectText)));
    guard('R4 the root moved by the two kept deltas', num(after, 'root', 0) === num(before, 'root', 0) + 8 + 29 && num(after, 'root', 1) === num(before, 'root', 1) + 9 + 18,
      after.rootText.join(' '));
  }
  // R5: the first wheel of tm-roam, about (200, 150), container at (20, 50)
  {
    const c = cs('tm-roam');
    const before = c.statesList[1].series[0];
    const after = c.statesList[2].series[0];
    const rx = num(before, 'root', 0);
    const ry = num(before, 'root', 1);
    const rw = num(before, 'root', 2);
    const rh = num(before, 'root', 3);
    const lw = 560;
    const cur = (rw / lw) || 1;
    const nz = Math.min(Math.max(cur * 1.1, 0.2), 5);
    const s = nz / cur;
    const mx = 200 - 20;
    const my = 150 - 50;
    const m4 = (-mx) * s + mx;
    const m5 = (-my) * s + my;
    guard('R5 treemapRender scales the root rect about the pointer', num(after, 'root', 0) === rx * s + m4 && num(after, 'root', 1) === ry * s + m5
      && num(after, 'root', 2) === lw * ((rw * s) / lw), after.rootText.join(' '));
  }
  // R6: sb-anim, piece a2 (row 5) kept through the drill; update 500 ms cubicInOut from the first frame
  {
    const c = cs('sb-anim');
    const from = c.statesList[1].series[0].pieces.find(p => p.di === 5 && !p.v);
    const to = c.statesList[9].series[0].pieces.find(p => p.di === 5 && !p.v);
    const at = c.statesList[5].series[0].pieces.find(p => p.di === 5 && !p.v);
    const p = (84 + 150) / 500;
    const e = p < 0.5 ? 4 * p * p * p : ((p - 1) * (2 * p - 2) * (2 * p - 2) + 1);
    const k = 5;
    const want = num(from, 'sh', k) + (num(to, 'sh', k) - num(from, 'sh', k)) * e;
    guard('R6 a kept piece moves by cubicInOut from the first frame', from && to && at && Math.abs(num(at, 'sh', k) - want) < 1e-9,
      at && at.shText[k] + ' vs ' + want);
  }
  // R7: tm-anim-zoom's root group x, 900 ms quinticInOut
  {
    const c = cs('tm-anim-zoom');
    const g0 = c.statesList[1].series[0].nodes.find(n => n.di === 0);
    const gEnd = c.statesList[8].series[0].nodes.find(n => n.di === 0);
    const gAt = c.statesList[5].series[0].nodes.find(n => n.di === 0);
    const p = (84 + 200) / 900;
    const e = p < 0.5 ? 16 * p * p * p * p * p : 1 + 16 * (p - 1) * (p - 1) * (p - 1) * (p - 1) * (p - 1);
    const want = num(g0, 'g', 0) + (num(gEnd, 'g', 0) - num(g0, 'g', 0)) * e;
    guard('R7 the root group slides by quinticInOut', Math.abs(num(gAt, 'g', 0) - want) < 1e-9 && num(gEnd, 'g', 0) !== num(g0, 'g', 0),
      gAt.gText[0] + ' vs ' + want);
  }
  // R8
  {
    const c = cs('tm-anim-drill');
    const at = c.statesList[5];
    guard('R8 a click while the treemap animates does nothing', at.events.length === 0 && at.series[0].viewRoot === 1 && at.series[0].state === 'animating',
      JSON.stringify(at.events));
  }
  // discriminating counts
  const all = [];
  out.forEach(c => c.statesList.forEach((st, i) => all.push({ c, st, i })));
  const count = f => all.filter(f).length;
  guard('a drillDown event', count(x => x.st.events.some(e => e.direction === 'drillDown')) >= 1);
  guard('a rollUp event', count(x => x.st.events.some(e => e.direction === 'rollUp')) >= 1);
  guard('a ghost leaving', count(x => x.st.series.some(s => s.type === 'treemap' && s.ghosts.length > 0)) >= 1);
  guard('a treemap label fading in', count(x => x.st.series.some(s => s.type === 'treemap' && s.nodes.some(n => n.ct && n.ct.label && n.ct.label.op !== hex(1) && n.ct.label.op !== hex(0)))) >= 1);
  guard('a sunburst piece growing', count(x => x.c.group === 'sb-anim' && x.st.clips > 0) >= 1);
  guard('a zoomToNode root larger than the box', count(x => x.c.id === 'tm-click-big' && x.st.series[0].rootText && Number(x.st.series[0].rootText[2]) > 560) >= 1);
  guard('a breadcrumb', count(x => x.st.series.some(s => s.type === 'treemap' && s.crumbs.length > 2)) >= 1);
  guard('a tooltip on the return circle', count(x => x.st.tip && x.st.tip.which === 'item:0:0') >= 1);
  guard('a blurred sunburst piece', count(x => x.st.series.some(s => s.type === 'sunburst' && s.pieces.some(p => p.states && p.states.includes('blur')))) >= 1);
  guard('a hovered treemap rect', count(x => x.st.series.some(s => s.type === 'treemap' && s.nodes.some(n => n.ct && n.ct.states && n.ct.states.includes('emphasis')))) >= 1);
  return g;
}

function generate() {
  const out = CASES.map(runCase);
  const g = guards(out);
  const measure = { firstCode: FIRST_CODE, lastCode: LAST_CODE, ratio: RATIO.map(hex), ratioText: RATIO.map(tx) };
  const doc = {
    source: 'tools/advchart-oracle/sunburst-treemap-interact.js against ' + path.basename(DIST) + ' (ECharts 6.1)',
    seed: SEED,
    measure,
    notes: [
      'Every case is a new chart; the clock is NOW = 1700000000000 at setOption and only {tick} steps advance it.',
      'A click is mousedown, mouseup, click at one point; a drag is mousedown, mousemoves, mouseup, click.',
      'Points named by a node were resolved on the picture of the time (an integer point the node is hit at) and are written as numbers.',
      'events: the action events (sunburstroottonode, treemapzoomtonode, treemaproottonode, treemapmove, treemaprender), seriesId resolved to the index, targetNode to its dataIndex.',
    ],
    cases: out.map(c => ({ id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option, probes: c.probes,
      withStates: c.states, steps: c.steps, states: c.statesList })),
    guards: g,
  };
  return { doc, bad: g.filter(x => !x.ok) };
}

try {
  const a = generate();
  if (a.bad.length) {
    for (const b of a.bad) console.error('GUARD FAILED: ' + b.id + ' -- ' + b.detail);
    // ORACLE_DEBUG writes the failing document anyway, for a look; never the fixture
    if (process.env.ORACLE_DEBUG) fs.writeFileSync(process.env.ORACLE_DEBUG, JSON.stringify(a.doc, null, 1));
    process.exit(1);
  }
  const textA = JSON.stringify(a.doc, null, 1);
  const b = generate();
  const textB = JSON.stringify(b.doc, null, 1);
  must(textA === textB, 'two generations differ');
  must(!textA.includes('\\u0000'), 'a \\u0000 in the output');
  JSON.parse(textA);
  fs.writeFileSync(OUT, textA + '\n');
  let states = 0;
  a.doc.cases.forEach(c => { states += c.states.length; });
  console.log('wrote ' + OUT + ': ' + a.doc.cases.length + ' cases, ' + states + ' states, ' + a.doc.guards.length + ' guards');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e.stack);
  process.exit(1);
}
