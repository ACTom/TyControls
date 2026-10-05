// Upstream's own answers for graph and sankey INTERACTION (batch 114, roadmap
// C5): dragging a node on a graph (layout none / circular / force) and on a
// sankey (the dragNode action and the edges that follow it), the edge labels
// of both series (every position, the formatter, the default text), the
// per-edge lineStyle and edge symbols of a graph, the sankey's roam (the
// sankeyRoam action, the pan and wheel gestures, containPixel after them),
// the sankey's focus 'adjacency' / 'trajectory' on the state machine, and a
// drag after a roam on both series.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer), with Math.random
// replaced by the port's xorshift32 (seed 2463534242, reset before each chart)
// and the global setTimeout replaced by a queue that is never run (every case
// sets `animation: false`; a force graph sets `force.layoutAnimation: false`,
// so its iteration runs synchronously -- the only mode the port has). Every
// pointer step goes through zrender's own Handler (handler.mousemove /
// mousedown / mouseup / click / mousewheel with a synthetic event {zrX, zrY,
// zrDelta, which 1, preventDefault, stopPropagation}); before every event
// storage.getDisplayList(true) brings every transform up to date, as a paint
// does, so hit testing and Element.drift read the current geometry. A 'click'
// follows every 'up' (the DOM sends one; zrender decides whether it lands).
//
//   node tools/advchart-oracle/graph-sankey-interact.js
//
// writes tests/fixtures/advchart-graph-sankey-interact.json (ORACLE_OUT
// overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   A Double is the 16 lowercase hex digits of its IEEE-754 bits (big-endian),
//   with a readable twin `<key>Text` beside it (String(v), '-0' for negative
//   zero). A non-finite number is null with its twin 'NaN' / 'Infinity' /
//   '-Infinity'; absent is null with a null twin. Pointer points and other
//   inputs are plain integers.
//
// Top level: source, seed, notes[], cases[], guards[].
//
// Per case:
//   id, group ('drag-graph' | 'drag-sankey' | 'edge-label' | 'edge-style' |
//   'roam-sankey' | 'focus-sankey'), note, W, H, option (as fed to setOption),
//   probes [[x, y] ...] (containPixel points, sankey cases), ring (a circular
//   layout: the ring's cos / sin are not correctly rounded in either runtime),
//   steps[]: each ONE of
//     {down: [x, y]} {move: [x, y]} {up: [x, y]}  the Handler's mousedown /
//                    mousemove / mouseup; an 'up' is followed by a 'click' at
//                    the same point
//     {wheel: [x, y, delta]}  mousewheel, zrDelta = delta / 120 (delta is the
//                    LCL WheelDelta)
//     {action: payload}  chart.dispatchAction(payload)
//     {leave: true}  the pointer leaves the canvas (a mousemove outside it)
//     {resize: [W, H]}
//   states[]: index-parallel to [after setOption, after step 1, ...]:
//     actions[]  every api.dispatchAction a pointer step made, in order:
//                {type, seriesIndex (from seriesId), dataIndex?, localX?,
//                localY?, dx?, dy?, zoom?, originX?, originY?} (numbers hex +
//                Text); [] for an action step
//     series[]   one record per graph / sankey series, in series index order:
//       index, type
//       GRAPH:
//         overall [osx, osy, ox, oy]   (cs.trans[2]; null on axes)
//         nodes[i] null | {layout[2] (data), px[2] (the Symbol group's
//           transform [4..5]), scale[2] (the group's scaleX / scaleY), half[2]
//           (the symbol path's transform [0], [3]), fixed (layout.fixed)}
//         edges[i] null | {shape[4] (x1 y1 x2 y2, data, after adjustEdge),
//           cp null | [cpx1, cpy1], stroke (the style's stroke, a string),
//           lineWidth, opacity, dash null | [..] (style.lineDash, an array),
//           dashWord null | 'dashed' | 'dotted' (style.lineDash, a word zrender
//           turns into a pattern at paint time),
//           fromSymbol, toSymbol (the visuals, strings | null), fromSize,
//           toSize, fromArrow / toArrow null | {px[2] (the arrow's transform
//           [4..5]), rotation, scale},
//           label null | {text, ignore, m[6] (the label's transform),
//           align, vAlign (what Line.beforeUpdate set), opacity}}
//       SANKEY:
//         m[6]   the main group's transform (identity when it has none)
//         group null | [6]  the series view group's transform (the roam)
//         center, zoom  the option's (JSON), localX[], localY[]  the option's
//           node items' (null when absent; numbers hex + Text)
//         nodes[i] null | {shape[4] x y w h (local), corners[4] (the two
//           corners through m: x0 y0 x1 y1), label null | {text, x, y
//           (transform [4..5]), align, vAlign}}
//         edges[i] null | {shape[9] x1 y1 cpx1 cpy1 cpx2 cpy2 x2 y2 extent
//           (local), label null | {text, x, y, align, vAlign}}
//         contain   '0' / '1' per probe: chart.containPixel({seriesIndex}, p)
//         trigger[4]  the View's data rect through the overall transform
//       FOCUS (focus-sankey cases): nodes[i].st / edges[i].st =
//           {hover (hoverState 0 1 2), states 'a,b' (currentStates),
//           opacity (style.opacity), z2, fill (style.fill as a string)}
//
// Self-checks (any failure: nothing is written, exit 1). Each recipe below is
// the port's to transcribe, and is checked here bit for bit at every state:
//   R1 graph drag (none): a drag step moves the Symbol group by Element.drift
//      through the main group's inverse: x' = inv0*(osx*x + 0*y + ox + dx) +
//      inv4 (y alike), and re-derives its scale as |inv0*(osx*s)|
//   R2 graph drag (circular): the dragged node lands on the ring at the
//      pointer's angle: cx + (px - cx)/len*r (len = sqrt(dx*dx + dy*dy)) of
//      pointToData(pointer)
//   R3 graph drag (force, layoutAnimation false): from the second move on, the
//      dragged node stays where the first move's run left it
//   R4 sankey drag: localX = (x0 + sum dx) / width, localY alike, where x0 is
//      the rect's shape.x at the press
//   R5 sankey roam: the view's overall transform follows the graphRoam recipe
//      (roam.js) on a View whose data rect and view rect are both the box
//   R6 graph edge labels: Line.beforeUpdate's position, rotation, origin and
//      alignment, composed with the main group's transform, give the label's
//      transform exactly (straight and curved edges, every position)
//   R7 sankey edge labels: the band's bounding box (bbox.fromCubic) through m,
//      its centre
//   R8 adjacency / trajectory: the blur sets from Graph.ts, recomputed
//   plus: discriminating counts (each >= 1: a drag that changed a node's
//   scale, a label turned by pi, an 'end' label not centred, a curved edge
//   label, a per-edge dash, a 'source' edge colour, a sankey roam with a zoom,
//   a trajectory set larger than the adjacency one, ...), two generations in
//   one process giving the same bytes, no \u0000, and the JSON parsing back.
'use strict';
const fs = require('fs');
const path = require('path');

// timers that never run: animation is off, the force iteration is synchronous
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-graph-sankey-interact.json');

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
const eq = (a, b) => a === b || (Number.isNaN(a) && Number.isNaN(b)) || (a === 0 && b === 0 && Object.is(a, b));
const eqArr = (a, b) => Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((v, i) => eq(v, b[i]));

// ---------- the chart ----------
function mk(W, H) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  // the browser's model (mouse-events.js): hover states and labels as a page has them
  chart._ssr = false;
  return chart;
}
function zr(chart) { return chart.getZr(); }
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, extra) {
  refresh(chart);
  zr(chart).handler[name](zev(extra));
  refresh(chart);
}

function seriesList(chart) {
  const out = [];
  chart.getModel().eachSeries(s => { if (s.subType === 'graph' || s.subType === 'sankey') out.push(s); });
  return out;
}

const I6 = [1, 0, 0, 1, 0, 0];
function applyM(m, x, y) { return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]]; }

// ---------- snapshots ----------
function snapGraph(chart, s) {
  const cs = s.coordinateSystem;
  const isView = cs && cs.type === 'view';
  const o = { index: s.seriesIndex, type: 'graph' };
  o.overall = isView ? [cs.trans[2].scaleX, cs.trans[2].scaleY, cs.trans[2].x, cs.trans[2].y] : null;
  const d = s.getData();
  o.nodes = [];
  for (let i = 0; i < d.count(); i++) {
    const el = d.getItemGraphicEl(i);
    const lay = d.getItemLayout(i);
    if (!el || !lay) { o.nodes.push(null); continue; }
    const g = el.transform || I6;
    const pth = el.childAt(0);
    const pg = pth.transform || I6;
    o.nodes.push({ layout: [lay[0], lay[1]], px: [g[4], g[5]], scale: [el.scaleX, el.scaleY], half: [pg[0], pg[3]], fixed: !!lay.fixed,
      st: stOf(pth) });
  }
  const e = s.getEdgeData();
  o.edges = [];
  for (let i = 0; i < e.count(); i++) {
    const el = e.getItemGraphicEl(i);
    if (!el) { o.edges.push(null); continue; }
    const line = el.childOfName('line');
    const sh = line.shape;
    const st = line.style;
    const arrow = (sym) => {
      if (!sym) return null;
      const t = sym.transform || I6;
      return { px: [t[4], t[5]], rotation: sym.rotation, scale: sym.scaleX };
    };
    const lab = el.getTextContent();
    let label = null;
    if (lab) {
      label = { text: lab.style.text == null ? null : String(lab.style.text), ignore: !!lab.ignore, m: Array.from(lab.transform || I6),
        align: lab.style.align || null, vAlign: lab.style.verticalAlign || null, opacity: lab.style.opacity == null ? 1 : lab.style.opacity,
        local: [lab.x, lab.y, lab.rotation, lab.scaleX, lab.originX, lab.originY] };
    }
    o.edges.push({
      shape: [sh.x1, sh.y1, sh.x2, sh.y2],
      cp: isNaN(+sh.cpx1) || isNaN(+sh.cpy1) ? null : [sh.cpx1, sh.cpy1],
      stroke: st.stroke == null ? null : String(st.stroke), lineWidth: st.lineWidth, opacity: st.opacity == null ? 1 : st.opacity,
      dash: Array.isArray(st.lineDash) ? st.lineDash.slice() : null,
      dashWord: typeof st.lineDash === 'string' ? st.lineDash : null,
      fromSymbol: e.getItemVisual(i, 'fromSymbol') || null, toSymbol: e.getItemVisual(i, 'toSymbol') || null,
      fromSize: +e.getItemVisual(i, 'fromSymbolSize'), toSize: +e.getItemVisual(i, 'toSymbolSize'),
      fromArrow: arrow(el.childOfName('fromSymbol')), toArrow: arrow(el.childOfName('toSymbol')),
      label, st: stOf(line),
    });
  }
  return o;
}

function stOf(el) {
  return { hover: el.hoverState || 0, states: (el.currentStates || []).join(','), opacity: el.style && el.style.opacity != null ? el.style.opacity : 1,
    z2: el.z2, fill: el.style && el.style.fill != null && typeof el.style.fill === 'string' ? el.style.fill : null };
}

function snapSankey(chart, s, probes) {
  const view = chart.getViewOfSeriesModel(s);
  const mg = view._mainGroup;
  const o = { index: s.seriesIndex, type: 'sankey' };
  const m = Array.from(mg.transform || I6);
  o.m = m;
  o.group = view.group.transform ? Array.from(view.group.transform) : null;
  o.center = s.option.center === undefined ? null : s.option.center;
  o.zoom = s.option.zoom === undefined ? null : s.option.zoom;
  const items = s.option.data || s.option.nodes || [];
  o.localX = items.map(it => (it && it.localX != null ? it.localX : null));
  o.localY = items.map(it => (it && it.localY != null ? it.localY : null));
  const d = s.getData();
  o.nodes = [];
  for (let i = 0; i < d.count(); i++) {
    const el = d.getItemGraphicEl(i);
    if (!el) { o.nodes.push(null); continue; }
    const sh = el.shape;
    const t = el.transform || I6;
    const p0 = applyM(t, sh.x, sh.y);
    const p1 = applyM(t, sh.x + sh.width, sh.y + sh.height);
    const lab = el.getTextContent();
    let label = null;
    if (lab && !lab.ignore) {
      const lt = lab.transform || I6;
      label = { text: String(lab.style.text), x: lt[4], y: lt[5], align: lab.style.align || null, vAlign: lab.style.verticalAlign || null };
    }
    o.nodes.push({ shape: [sh.x, sh.y, sh.width, sh.height], corners: [p0[0], p0[1], p1[0], p1[1]], label, st: stOf(el) });
  }
  const e = s.getData('edge');
  o.edges = [];
  for (let i = 0; i < e.count(); i++) {
    const el = e.getItemGraphicEl(i);
    if (!el) { o.edges.push(null); continue; }
    const sh = el.shape;
    const lab = el.getTextContent();
    let label = null;
    if (lab && !lab.ignore) {
      const lt = lab.transform || I6;
      label = { text: String(lab.style.text), x: lt[4], y: lt[5], align: lab.style.align || null, vAlign: lab.style.verticalAlign || null };
    }
    const r = el.getBoundingRect();
    o.edges.push({ shape: [sh.x1, sh.y1, sh.cpx1, sh.cpy1, sh.cpx2, sh.cpy2, sh.x2, sh.y2, sh.extent], box: [r.x, r.y, r.width, r.height],
      label, st: stOf(el) });
  }
  o.contain = (probes || []).map(p => (chart.containPixel({ seriesIndex: s.seriesIndex }, p) ? '1' : '0')).join('');
  const cs = s.coordinateSystem;
  if (cs && cs.type === 'view') {
    const mo = cs.mtOverall;
    const dr = cs.getBoundingRect();
    let X = dr.x * mo[0] + mo[4], Y = dr.y * mo[3] + mo[5], W = dr.width * mo[0], H = dr.height * mo[3];
    if (W < 0) { X += W; W = -W; }
    if (H < 0) { Y += H; H = -H; }
    o.trigger = [X, Y, W, H];
    o.overall = [cs.trans[2].scaleX, cs.trans[2].scaleY, cs.trans[2].x, cs.trans[2].y];
    o.dataRect = [dr.x, dr.y, dr.width, dr.height];
  }
  else { o.trigger = null; o.overall = null; o.dataRect = null; }
  return o;
}

// ---------- encoding ----------
function encGraph(p) {
  const o = { index: p.index, type: p.type };
  if (p.overall) put(o, 'overall', p.overall); else { o.overall = null; o.overallText = null; }
  o.nodes = p.nodes.map(n => {
    if (!n) return null;
    const r = {};
    put(r, 'layout', n.layout); put(r, 'px', n.px); put(r, 'scale', n.scale); put(r, 'half', n.half);
    r.fixed = n.fixed;
    r.st = encSt(n.st);
    return r;
  });
  o.edges = p.edges.map(e => {
    if (!e) return null;
    const r = {};
    put(r, 'shape', e.shape);
    if (e.cp) put(r, 'cp', e.cp); else { r.cp = null; r.cpText = null; }
    r.stroke = e.stroke;
    put(r, 'lineWidth', e.lineWidth); put(r, 'opacity', e.opacity);
    if (e.dash) put(r, 'dash', e.dash); else { r.dash = null; r.dashText = null; }
    r.dashWord = e.dashWord;
    r.fromSymbol = e.fromSymbol; r.toSymbol = e.toSymbol;
    put(r, 'fromSize', e.fromSize); put(r, 'toSize', e.toSize);
    const ar = a => (a ? put(put(put({}, 'px', a.px), 'rotation', a.rotation), 'scale', a.scale) : null);
    r.fromArrow = ar(e.fromArrow); r.toArrow = ar(e.toArrow);
    if (e.label) {
      const l = { text: e.label.text, ignore: e.label.ignore, align: e.label.align, vAlign: e.label.vAlign };
      put(l, 'm', e.label.m); put(l, 'opacity', e.label.opacity); put(l, 'local', e.label.local);
      r.label = l;
    }
    else r.label = null;
    r.st = encSt(e.st);
    return r;
  });
  return o;
}
function encSt(st) {
  const r = { hover: st.hover, states: st.states, fill: st.fill };
  put(r, 'opacity', st.opacity); r.z2 = st.z2;
  return r;
}
function encLabel(l) {
  if (!l) return null;
  return put(put({ text: l.text, align: l.align, vAlign: l.vAlign }, 'x', l.x), 'y', l.y);
}
function encSankey(p) {
  const o = { index: p.index, type: p.type };
  put(o, 'm', p.m);
  if (p.group) put(o, 'group', p.group); else { o.group = null; o.groupText = null; }
  o.center = p.center; o.zoom = p.zoom;
  o.localX = p.localX.map(v => (v == null ? null : put({}, 'v', v)));
  o.localY = p.localY.map(v => (v == null ? null : put({}, 'v', v)));
  o.nodes = p.nodes.map(n => (n ? Object.assign(put(put({}, 'shape', n.shape), 'corners', n.corners), { label: encLabel(n.label), st: encSt(n.st) }) : null));
  o.edges = p.edges.map(e => (e ? Object.assign(put(put({}, 'shape', e.shape), 'box', e.box), { label: encLabel(e.label), st: encSt(e.st) }) : null));
  o.contain = p.contain;
  if (p.trigger) { put(o, 'trigger', p.trigger); put(o, 'overall', p.overall); put(o, 'dataRect', p.dataRect); }
  else { o.trigger = null; o.overall = null; o.dataRect = null; }
  return o;
}
function encAction(a) {
  const o = { type: a.type, seriesIndex: a.seriesIndex };
  if (a.dataIndex != null) o.dataIndex = a.dataIndex;
  for (const k of ['localX', 'localY', 'dx', 'dy', 'zoom', 'originX', 'originY']) if (a[k] != null) put(o, k, a[k]);
  return o;
}

// ---------- driving a case ----------
function drive(c) {
  const chart = mk(c.W, c.H);
  const states = [];
  let log = [];
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    const idOf = () => { const m = {}; chart.getModel().eachSeries(s => { m[s.id] = s.seriesIndex; }); return m; };
    const api = chart._api;
    const orig = api.dispatchAction;
    api.dispatchAction = function (payload) {
      if (payload.type !== 'brushSelect' && log) {
        const ids = idOf();
        const a = Object.assign({}, payload);
        a.seriesIndex = payload.seriesId != null ? ids[payload.seriesId] : payload.seriesIndex != null ? payload.seriesIndex : null;
        const known = ['type', 'seriesId', 'seriesIndex', 'dataIndex', 'localX', 'localY', 'dx', 'dy', 'zoom', 'originX', 'originY', 'animation'];
        must(Object.keys(payload).every(k => known.includes(k)), 'unexpected payload keys ' + Object.keys(payload));
        log.push(a);
      }
      return orig.apply(this, arguments);
    };
    const snap = (actions) => {
      // a frame: the state flags become states (echarts' _onframe), then a paint
      chart._onframe();
      chart.renderToSVGString();
      refresh(chart);
      states.push({ actions, series: seriesList(chart).map(s => (s.subType === 'graph' ? snapGraph(chart, s) : snapSankey(chart, s, c.probes))) });
    };
    log = null;
    snap([]);
    for (const st of c.steps) {
      log = [];
      if (st.down) fire(chart, 'mousedown', { zrX: st.down[0], zrY: st.down[1] });
      else if (st.move) fire(chart, 'mousemove', { zrX: st.move[0], zrY: st.move[1] });
      else if (st.up) { fire(chart, 'mouseup', { zrX: st.up[0], zrY: st.up[1] }); fire(chart, 'click', { zrX: st.up[0], zrY: st.up[1] }); }
      else if (st.wheel) fire(chart, 'mousewheel', { zrX: st.wheel[0], zrY: st.wheel[1], zrDelta: st.wheel[2] / 120 });
      else if (st.leave) fire(chart, 'mousemove', { zrX: -10, zrY: -10 });
      else if (st.action) { const l = log; log = null; chart.dispatchAction(JSON.parse(JSON.stringify(st.action))); log = l; }
      else if (st.resize) chart.resize({ width: st.resize[0], height: st.resize[1] });
      else throw new OracleError('an unknown step ' + JSON.stringify(st));
      const a = log;
      log = null;
      snap(a);
    }
  } finally {
    chart.dispose();
  }
  return states;
}

// ---------- the recipes (self-checks) ----------
// R6: Line.beforeUpdate for one edge, in data space, composed with P (the main
// group's transform). shape [x1 y1 x2 y2], cp null | [cx cy], invScale,
// position, distance [dx dy]. Returns the label transform [6], align, vAlign.
function refLineLabel(shape, cp, P, invScale, position, distance) {
  const [x1, y1, x2, y2] = shape;
  const straight = !cp;
  const pointAt = t => (straight
    ? [x1 * (1 - t) + x2 * t, y1 * (1 - t) + y2 * t]
    : [(1 - t) * ((1 - t) * x1 + 2 * t * cp[0]) + t * t * x2, (1 - t) * ((1 - t) * y1 + 2 * t * cp[1]) + t * t * y2]);
  const norm = v => { const d = Math.sqrt(v[0] * v[0] + v[1] * v[1]); return d === 0 ? [0, 0] : [v[0] / d, v[1] / d]; };
  const tangentAt = t => norm(straight ? [x2 - x1, y2 - y1]
    : [2 * ((1 - t) * (cp[0] - x1) + t * (x2 - cp[0])), 2 * ((1 - t) * (cp[1] - y1) + t * (y2 - cp[1]))]);
  const fromPos = pointAt(0);
  const toPos = pointAt(1);
  const d = norm([toPos[0] - fromPos[0], toPos[1] - fromPos[1]]);
  const distanceX = distance[0] * invScale;
  const distanceY = distance[1] * invScale;
  const tangent = tangentAt(0.5);
  const mid = pointAt(0.5);
  const dir = tangent[0] < 0 ? -1 : 1;
  let rotation = 0;
  if (position !== 'start' && position !== 'end') {
    rotation = -Math.atan2(tangent[1], tangent[0]);
    if (toPos[0] < fromPos[0]) rotation = Math.PI + rotation;
  }
  let dy, align, vAlign, x = 0, y = 0, ox = 0, oy = 0;
  switch (position) {
    case 'insideStartTop': case 'insideMiddleTop': case 'insideEndTop': case 'middle':
      dy = -distanceY; vAlign = 'bottom'; break;
    case 'insideStartBottom': case 'insideMiddleBottom': case 'insideEndBottom':
      dy = distanceY; vAlign = 'top'; break;
    default: dy = 0; vAlign = 'middle';
  }
  switch (position) {
    case 'end':
      x = d[0] * distanceX + toPos[0]; y = d[1] * distanceY + toPos[1];
      align = d[0] > 0.8 ? 'left' : (d[0] < -0.8 ? 'right' : 'center');
      vAlign = d[1] > 0.8 ? 'top' : (d[1] < -0.8 ? 'bottom' : 'middle');
      break;
    case 'start':
      x = -d[0] * distanceX + fromPos[0]; y = -d[1] * distanceY + fromPos[1];
      align = d[0] > 0.8 ? 'right' : (d[0] < -0.8 ? 'left' : 'center');
      vAlign = d[1] > 0.8 ? 'bottom' : (d[1] < -0.8 ? 'top' : 'middle');
      break;
    case 'insideStartTop': case 'insideStart': case 'insideStartBottom':
      x = distanceX * dir + fromPos[0]; y = fromPos[1] + dy;
      align = tangent[0] < 0 ? 'right' : 'left';
      ox = -distanceX * dir; oy = -dy;
      break;
    case 'insideMiddleTop': case 'insideMiddle': case 'insideMiddleBottom': case 'middle':
      x = mid[0]; y = mid[1] + dy; align = 'center'; oy = -dy;
      break;
    case 'insideEndTop': case 'insideEnd': case 'insideEndBottom':
      x = -distanceX * dir + toPos[0]; y = toPos[1] + dy;
      align = tangent[0] >= 0 ? 'right' : 'left';
      ox = distanceX * dir; oy = -dy;
      break;
  }
  // getLocalTransform(x, y, rotation, scale invScale, origin ox oy)
  const sx = invScale, sy = invScale;
  const L = [];
  if (ox || oy) { L[4] = -ox * sx - 0 * oy * sy; L[5] = -oy * sy - 0 * ox * sx; }
  else { L[4] = 0; L[5] = 0; }
  L[0] = sx; L[3] = sy; L[1] = 0 * sx; L[2] = 0 * sy;
  if (rotation) {
    const aa = L[0], ac = L[2], atx = L[4], ab = L[1], ad = L[3], aty = L[5];
    const st = Math.sin(rotation), ct = Math.cos(rotation);
    L[0] = aa * ct + ab * st; L[1] = -aa * st + ab * ct;
    L[2] = ac * ct + ad * st; L[3] = -ac * st + ct * ad;
    L[4] = ct * atx + st * aty; L[5] = ct * aty - st * atx;
  }
  L[4] += ox + x; L[5] += oy + y;
  // mul(P, L)
  const M = [P[0] * L[0] + P[2] * L[1], P[1] * L[0] + P[3] * L[1], P[0] * L[2] + P[2] * L[3], P[1] * L[2] + P[3] * L[3],
    P[0] * L[4] + P[2] * L[5] + P[4], P[1] * L[4] + P[3] * L[5] + P[5]];
  return { M, align, vAlign, rotation };
}

// R8: Graph.ts' blur sets for a sankey hover
function refSets(nodesN, edges, hoverEdge, idx, kind) {
  const inE = Array.from({ length: nodesN }, () => []);
  const outE = Array.from({ length: nodesN }, () => []);
  edges.forEach((e, k) => { outE[e[0]].push(k); inE[e[1]].push(k); });
  if (kind === 'adjacency') {
    if (hoverEdge) return { node: [edges[idx][0], edges[idx][1]], edge: [idx] };
    const r = { node: [], edge: [] };
    // node.edges: the order Graph.addEdge pushes them -- every edge touching the node, in edge order
    edges.forEach((e, k) => { if (e[0] === idx || e[1] === idx) { r.edge.push(k); r.node.push(e[0], e[1]); } });
    return r;
  }
  const em = new Map(), nm = new Map();
  const run = (startEdges) => {
    for (const k of startEdges) {
      em.set(k, true);
      const src = [edges[k][0]], tgt = [edges[k][1]];
      for (let q = 0; q < src.length; q++) { nm.set(src[q], true); for (const j of inE[src[q]]) if (!em.has(j)) { em.set(j, true); src.push(edges[j][0]); } }
      for (let q = 0; q < tgt.length; q++) { nm.set(tgt[q], true); for (const j of outE[tgt[q]]) if (!em.has(j)) { em.set(j, true); tgt.push(edges[j][1]); } }
    }
  };
  if (hoverEdge) run([idx]);
  else { const all = []; edges.forEach((e, k) => { if (e[0] === idx || e[1] === idx) all.push(k); }); run(all); }
  return { node: Array.from(nm.keys()), edge: Array.from(em.keys()) };
}

// R5: the graphRoam recipe (roam.js) on a View whose data rect and view rect
// are both the sankey's box
function parsePos(opt, base, offset) {
  if (opt === 'center' || opt === 'middle') opt = '50%';
  else if (opt === 'left' || opt === 'top') opt = '0%';
  else if (opt === 'right' || opt === 'bottom') opt = '100%';
  if (typeof opt === 'string') {
    if (/%$/.test(opt.trim())) return parseFloat(opt) / 100 * base + (offset || 0);
    return parseFloat(opt);
  }
  return opt == null ? NaN : +opt;
}
function clampZ(z, lim) {
  if (lim) { const mn = lim.min || 0; const mx = lim.max || Infinity; z = Math.max(Math.min(mx, z), mn); }
  return z;
}
function refBuild(st) {
  const [dx, dy, dw, dh] = st.dr;
  const [vx, vy, vw, vh] = st.dr;
  const sx = vw / dw, sy = vh / dh;
  const rx = (-dx) * sx + vx, ry = (-dy) * sy + vy;
  let det = sx * sy - 0 * 0; det = 1.0 / det;
  const ri0 = sy * det, ri3 = sx * det, ri4 = (0 * ry - sy * rx) * det, ri5 = (0 * rx - sx * ry) * det;
  const vcx = vx + vw / 2, vcy = vy + vh / 2;
  const z = clampZ(st.optZoom || 1, st.limit) || 1;
  let rcx = vcx, rcy = vcy;
  if (st.center) {
    const px = parsePos(st.center[0], dw, dx), py = parsePos(st.center[1], dh, dy);
    rcx = sx * px + 0 * py + rx; rcy = 0 * px + sy * py + ry;
  }
  const roamX = vcx - z * rcx, roamY = vcy - z * rcy;
  return { sx, sy, rx, ry, ri0, ri3, ri4, ri5, vcx, vcy, z, osx: z * sx + 0 * 0, osy: 0 * 0 + z * sy, ox: z * rx + 0 * ry + roamX, oy: 0 * rx + z * ry + roamY };
}
function refAction(st, p) {
  const b = refBuild(st);
  const toRoam = T => ({ sx: T.sx * b.ri0 + 0 * 0, sy: 0 * 0 + T.sy * b.ri3, x: T.sx * b.ri4 + 0 * b.ri5 + T.x, y: 0 * b.ri4 + T.sy * b.ri5 + T.y });
  const SB1 = { x: b.ox, y: b.oy, sx: b.osx, sy: b.osy };
  const SB2 = toRoam(SB1);
  if (p.dx != null && p.dy != null) { SB1.x += p.dx; SB1.y += p.dy; }
  if (p.zoom != null) {
    const oldZ = SB2.sx, newZ = clampZ(oldZ * p.zoom, st.limit), k = newZ / oldZ;
    SB1.x -= (p.originX - SB1.x) * (k - 1); SB1.y -= (p.originY - SB1.y) * (k - 1); SB1.sx *= k; SB1.sy *= k;
  }
  const R = toRoam(SB1);
  const zoom = R.sx;
  const nz = Math.abs(zoom) > 1e-6;
  const c0 = nz ? (b.vcx - R.x) / zoom : b.vcx, c1 = nz ? (b.vcy - R.y) / zoom : b.vcy;
  const d0 = b.ri0 * c0 + 0 * c1 + b.ri4, d1 = 0 * c0 + b.ri3 * c1 + b.ri5;
  const last = st.center;
  const [dx, dy, dw, dh] = st.dr;
  const isPct = v => typeof v === 'string' && /%$/.test(v.trim());
  const back = (i, v, o, w) => (w && isPct(last[i]) ? ((v - o) / w * 100) + '%' : v);
  st.center = last ? [back(0, d0, dx, dw), back(1, d1, dy, dh)] : [d0, d1];
  st.optZoom = zoom;
}

// ---------- the cases ----------
const CASES = [];
const add = c => CASES.push(Object.assign({ W: 600, H: 400, steps: [] }, c));

const GN = [
  { name: 'a', x: 0, y: 0, value: 3, symbolSize: 20 },
  { name: 'b', x: 100, y: 40, value: 5, symbolSize: 14 },
  { name: 'c', x: 40, y: 100, value: 8 },
  { name: 'd', x: 120, y: 110, value: 2, symbolSize: [24, 12] },
];
const GL = [
  { source: 'a', target: 'b', value: 7 },
  { source: 'b', target: 'c', value: 4 },
  { source: 'c', target: 'a' },
  { source: 'd', target: 'b', value: 1 },
];
const graphNone = extra => ({ animation: false, series: [Object.assign({ type: 'graph', layout: 'none', draggable: true,
  data: GN, links: GL, edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: [6, 10],
  edgeLabel: { show: true } }, extra || {})] });

// node pixel helper is computed at run time from the initial state
function nodeAt(states, si, i) { const n = states[0].series[si].nodes[i]; return [Math.round(n.px[0]), Math.round(n.px[1])]; }

// drag-graph: the steps are made from the initial picture, so they are built lazily
add({ id: 'g-none-drag', group: 'drag-graph', note: 'layout none: press node 0, two moves, release; the edges follow',
  option: graphNone(), lazy: st => { const [x, y] = nodeAt(st, 0, 0); return [{ down: [x, y] }, { move: [x + 13, y + 7] }, { move: [x + 29, y - 4] }, { up: [x + 29, y - 4] }]; } });
add({ id: 'g-none-drag-roamed', group: 'drag-graph', note: 'zoom 1.7 and a pan by action, then the drag: the drift goes through the roamed inverse and re-derives the scale',
  option: graphNone({ roam: true }), pre: [{ action: { type: 'graphRoam', zoom: 1.7, originX: 260, originY: 170 } }, { action: { type: 'graphRoam', dx: -31, dy: 17 } }],
  lazy: st => { const n = st[st.length - 1].series[0].nodes[1]; const x = Math.round(n.px[0]), y = Math.round(n.px[1]); return [{ down: [x, y] }, { move: [x - 11, y + 23] }, { move: [x - 40, y + 31] }, { up: [x - 40, y + 31] }]; } });
add({ id: 'g-none-drag-item', group: 'drag-graph', note: 'series draggable false, node 2 draggable true: node 2 drags, a press on node 0 pans (roam)',
  option: { animation: false, series: [{ type: 'graph', layout: 'none', draggable: false, roam: true,
    data: GN.map((n, i) => (i === 2 ? Object.assign({ draggable: true }, n) : n)), links: GL }] },
  lazy: st => { const [x, y] = nodeAt(st, 0, 2); const [x0, y0] = nodeAt(st, 0, 0);
    return [{ down: [x, y] }, { move: [x + 20, y + 10] }, { up: [x + 20, y + 10] }, { down: [x0, y0] }, { move: [x0 + 15, y0 + 15] }, { up: [x0 + 15, y0 + 15] }]; } });
add({ id: 'g-none-drag-curved', group: 'drag-graph', note: 'autoCurveness: the control points follow the dragged node',
  option: { animation: false, series: [{ type: 'graph', layout: 'none', draggable: true, autoCurveness: true,
    data: GN, links: GL.concat([{ source: 'b', target: 'a', value: 2 }, { source: 'a', target: 'b', value: 3 }]), edgeSymbol: ['none', 'arrow'] }] },
  lazy: st => { const [x, y] = nodeAt(st, 0, 1); return [{ down: [x, y] }, { move: [x + 9, y + 21] }, { up: [x + 9, y + 21] }]; } });
add({ id: 'g-circular-drag', group: 'drag-graph', note: 'circular: the dragged node goes to the ring at the pointer angle and stays fixed; a second node; then a resize lays the ring out again', ring: true,
  option: { animation: false, series: [{ type: 'graph', layout: 'circular', draggable: true, symbolSize: 18,
    data: [{ name: 'a', value: 1 }, { name: 'b', value: 2 }, { name: 'c', value: 3 }, { name: 'd', value: 4 }, { name: 'e', value: 5, symbolSize: 30 }],
    links: [{ source: 'a', target: 'c' }, { source: 'b', target: 'd' }, { source: 'e', target: 'a' }], lineStyle: { curveness: 0.2 } }] },
  lazy: st => { const [x, y] = nodeAt(st, 0, 0); const [x2, y2] = nodeAt(st, 0, 3);
    return [{ down: [x, y] }, { move: [x - 40, y + 60] }, { move: [x - 90, y + 110] }, { up: [x - 90, y + 110] },
      { down: [x2, y2] }, { move: [x2 + 70, y2 - 20] }, { up: [x2 + 70, y2 - 20] }, { resize: [560, 420] }]; } });
add({ id: 'g-force-drag', group: 'drag-graph', note: 'force, layoutAnimation false: every move re-runs the settle from 0.8 of the friction; the dragged node is fixed from the second move; a release unfixes it; a resize continues from the preserved points',
  option: { animation: false, series: [{ type: 'graph', layout: 'force', draggable: true, symbolSize: 16,
    force: { layoutAnimation: false, repulsion: 120, edgeLength: [40, 80], friction: 0.3 },
    data: [{ name: 'a', value: 1 }, { name: 'b', value: 3 }, { name: 'c', value: 2 }, { name: 'd', value: 5 }, { name: 'e', value: 4 }],
    links: [{ source: 'a', target: 'b', value: 2 }, { source: 'b', target: 'c', value: 1 }, { source: 'c', target: 'd', value: 3 }, { source: 'd', target: 'a', value: 1 }, { source: 'e', target: 'b', value: 2 }] }] },
  lazy: st => { const [x, y] = nodeAt(st, 0, 1); return [{ down: [x, y] }, { move: [x + 30, y + 10] }, { move: [x + 50, y + 25] }, { up: [x + 50, y + 25] }, { resize: [620, 380] }]; } });

// edge-label: graph labels at every position, on straight and curved edges, both directions
const POSITIONS = ['start', 'middle', 'end', 'insideStart', 'insideStartTop', 'insideStartBottom', 'insideMiddle', 'insideMiddleTop', 'insideMiddleBottom', 'insideEnd', 'insideEndTop', 'insideEndBottom'];
const LN = [{ name: 'p', x: 0, y: 0, value: 11 }, { name: 'q', x: 200, y: 30, value: 2 / 3 }, { name: 'r', x: 60, y: 160, value: 33 }, { name: 's', x: 210, y: 150, value: 44 }, { name: 't', x: 100, y: 80 }];
const LL = [
  { source: 'p', target: 'q', value: 5 },
  { source: 's', target: 'r', value: 6.25, name: 'sr' },
  { source: 'q', target: 's' },
  { source: 'r', target: 'p', value: 1 / 3, lineStyle: { curveness: 0.3 } },
  { source: 't', target: 'q', value: 9, lineStyle: { curveness: -0.25 } },
  { source: 'p', target: 't', value: 2 },
];
POSITIONS.forEach((pos, k) => {
  add({ id: 'gl-' + pos, group: 'edge-label', note: 'graph edge labels, position ' + pos + (k % 3 === 0 ? ', distance as a pair' : ''),
    option: { animation: false, series: [{ type: 'graph', layout: 'none', data: LN, links: LL, edgeSymbol: ['none', 'arrow'],
      edgeLabel: { show: true, position: pos, distance: k % 3 === 0 ? [3, 9] : 7 } }] } });
});
add({ id: 'gl-curved-fraction', group: 'edge-label', note: 'curved edges between fractional positions: the tangent at the middle is the derivative, which rounds apart from the chord',
  option: { animation: false, series: [{ type: 'graph', layout: 'none', data: [{ name: 'u', x: 0.1, y: 0.1, value: 1 }, { name: 'v', x: 50.1, y: 71.7, value: 2 }, { name: 'w', x: 13.3, y: 2.71828, value: 3 }],
    links: [{ source: 'u', target: 'v', lineStyle: { curveness: 0.3 } }, { source: 'v', target: 'w', lineStyle: { curveness: -0.2 } }, { source: 'w', target: 'u', lineStyle: { curveness: 0.45 } }],
    edgeLabel: { show: true, position: 'middle' } }] } });
add({ id: 'gl-formatter', group: 'edge-label', note: 'a template formatter on the series and an item label overriding position, show and formatter',
  option: { animation: false, series: [{ type: 'graph', layout: 'none', data: LN,
    links: LL.map((l, i) => (i === 2 ? Object.assign({ label: { position: 'end', formatter: '<{b}>' } }, l) : i === 4 ? Object.assign({ label: { show: false } }, l) : l)),
    edgeLabel: { show: true, formatter: '{a}|{b}|{c}' }, name: 'G' }] } });
add({ id: 'gl-default-text', group: 'edge-label', note: 'the default edge text: the NODE data value at the edge index (Line.ts reads getRawValue(idx) of the node data), the edge name where that is missing',
  option: { animation: false, series: [{ type: 'graph', layout: 'none', data: LN.slice(0, 4).concat([{ name: 't', x: 100, y: 80 }]), links: LL.concat([{ source: 'q', target: 'r', value: 4 }]),
    edgeLabel: { show: true } }] } });
add({ id: 'gl-roamed', group: 'edge-label', note: 'labels on a zoomed and panned view: the label is scaled back by 1 / the main group scale',
  option: { animation: false, series: [{ type: 'graph', layout: 'none', roam: true, zoom: 1.6, center: [80, 60], data: LN, links: LL,
    edgeLabel: { show: true, position: 'insideStartTop' } }] },
  steps: [{ action: { type: 'graphRoam', zoom: 1.3, originX: 300, originY: 200 } }] });
add({ id: 'gl-circular-cartesian', group: 'edge-label', note: 'a graph on axes: no main group transform',
  option: { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'graph', coordinateSystem: 'cartesian2d', data: [[10, 20], [40, 60], [80, 30]], links: [{ source: 0, target: 1, value: 3 }, { source: 2, target: 1, value: 8 }],
      edgeLabel: { show: true, position: 'insideEnd' } }] } });

// edge-style: per-edge lineStyle and symbols
add({ id: 'gs-per-edge', group: 'edge-style', note: 'per-edge width, type, opacity, colour (literal, source, target), curveness and symbols over the series',
  option: { animation: false, color: ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'],
    series: [{ type: 'graph', layout: 'none', data: LN, edgeSymbol: ['none', 'arrow'], edgeSymbolSize: 9,
      lineStyle: { width: 2, opacity: 0.7, color: '#888888' },
      links: [
        { source: 'p', target: 'q', lineStyle: { width: 5, type: 'dashed' } },
        { source: 's', target: 'r', lineStyle: { color: 'source', opacity: 0.3, type: 'dotted' } },
        { source: 'q', target: 's', lineStyle: { color: 'target', type: [4, 2, 1, 2] } },
        { source: 'r', target: 'p', lineStyle: { color: '#ff0000', curveness: 0.4 }, symbol: ['circle', 'rect'], symbolSize: [12, 4] },
        { source: 't', target: 'q', symbol: 'diamond', symbolSize: 0 },
        { source: 'p', target: 't', symbol: ['none', 'none'], lineStyle: { width: 0.5 } },
      ] }] } });
add({ id: 'gs-category-words', group: 'edge-style', note: "a category per node, so the two ends' colours differ: 'source' and 'target' per edge, and a literal",
  option: { animation: false, color: ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'],
    series: [{ type: 'graph', layout: 'none', categories: [{ name: 'A' }, { name: 'B' }, { name: 'C' }, { name: 'D' }, { name: 'E' }],
      data: LN.map((n, i) => Object.assign({ category: i }, n)), lineStyle: { width: 2 },
      links: LL.map((l, i) => Object.assign({}, l, { lineStyle: Object.assign({}, l.lineStyle || {}, { color: i % 3 === 0 ? 'source' : i % 3 === 1 ? 'target' : '#336699' }) })) }] } });
add({ id: 'gs-series-colour-words', group: 'edge-style', note: "series lineStyle color 'source' with one edge overriding to 'target' and one to a literal",
  option: { animation: false, color: ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'],
    series: [{ type: 'graph', layout: 'none', data: LN.map((n, i) => (i === 1 ? Object.assign({ itemStyle: { color: '#123456' } }, n) : n)),
      lineStyle: { color: 'source', width: 3 },
      links: LL.map((l, i) => (i === 1 ? Object.assign({}, l, { lineStyle: { color: 'target' } }) : i === 2 ? Object.assign({}, l, { lineStyle: { color: '#00aa00', width: 1 } }) : l)) }] } });

// sankey
const SN = [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }, { name: 'e' }];
const SL = [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }, { source: 'b', target: 'd', value: 4 },
  { source: 'c', target: 'd', value: 2 }, { source: 'c', target: 'e', value: 1 }, { source: 'b', target: 'e', value: 1 }];
const sankey = extra => ({ animation: false, series: [Object.assign({ type: 'sankey', data: SN, links: SL, lineStyle: { color: '#777777' } }, extra || {})] });
const PROBES = [[5, 5], [30, 20], [31, 21], [300, 200], [470, 380], [480, 380], [590, 395], [100, 300]];
function rectCentre(states, si, i) {
  const n = states[states.length - 1].series[si].nodes[i];
  return [Math.round((n.corners[0] + n.corners[2]) / 2), Math.round((n.corners[1] + n.corners[3]) / 2)];
}
add({ id: 's-drag', group: 'drag-sankey', note: 'press node 1, two moves, release: one dragNode per move, localX/Y the shape over the box, the bands follow', probes: PROBES,
  option: sankey(), lazy: st => { const [x, y] = rectCentre(st, 0, 1); return [{ down: [x, y] }, { move: [x + 17, y + 23] }, { move: [x - 8, y + 41] }, { up: [x - 8, y + 41] }]; } });
add({ id: 's-drag-vertical', group: 'drag-sankey', note: 'orient vertical, node 3 dragged; then a second drag of the same node continues from its localX/Y', probes: PROBES,
  option: sankey({ orient: 'vertical', edgeLabel: { show: true } }),
  lazy: st => { const [x, y] = rectCentre(st, 0, 3); return [{ down: [x, y] }, { move: [x + 31, y - 12] }, { up: [x + 31, y - 12] }, { down: [x + 31, y - 12] }, { move: [x + 45, y - 30] }, { up: [x + 45, y - 30] }]; } });
add({ id: 's-drag-off', group: 'drag-sankey', note: 'draggable false on the series, true on node 2: node 0 does not move (the press pans the roam), node 2 does', probes: PROBES,
  option: sankey({ draggable: false, roam: true, data: SN.map((n, i) => (i === 2 ? { name: n.name, draggable: true } : n)) }),
  lazy: st => { const [x, y] = rectCentre(st, 0, 0); const [x2, y2] = rectCentre(st, 0, 2);
    return [{ down: [x, y] }, { move: [x + 20, y + 20] }, { up: [x + 20, y + 20] }, { down: [x2 + 20, y2 + 20] }, { move: [x2 + 40, y2 + 30] }, { up: [x2 + 40, y2 + 30] }]; } });
add({ id: 'sl-formatter', group: 'drag-sankey', note: "sankey edge labels: a template over the edge's params on the series, a level's own formatter for the links leaving depth 1, a link that hides its label", probes: PROBES,
  option: sankey({ name: 'S', edgeLabel: { show: true, formatter: '{a}:{b}={c}' }, levels: [{ depth: 1, edgeLabel: { formatter: 'L{c}' } }],
    links: SL.map((l, i) => (i === 3 ? Object.assign({ edgeLabel: { show: false } }, l) : i === 0 ? Object.assign({ id: 'first' }, l) : l)) }) });
add({ id: 's-action', group: 'drag-sankey', note: 'the dragNode action by hand, by seriesIndex', probes: PROBES,
  option: sankey(), steps: [{ action: { type: 'dragNode', seriesIndex: 0, dataIndex: 4, localX: 0.25, localY: 0.125 } }] });
add({ id: 's-roam', group: 'roam-sankey', note: 'roam true: a pan by a drag on empty space (roamTrigger global), a wheel zoom, containPixel after both, then a node drag on the zoomed view', probes: PROBES,
  option: sankey({ roam: true, edgeLabel: { show: true } }),
  lazy: st => [{ down: [8, 8] }, { move: [30, 18] }, { move: [37, 25] }, { up: [37, 25] }, { wheel: [300, 200, 240] }, { wheel: [120, 90, -120] }],
  lazy2: st => { const [x, y] = rectCentre(st, 0, 2); return [{ down: [x, y] }, { move: [x + 12, y + 9] }, { up: [x + 12, y + 9] }]; } });
add({ id: 's-roam-action', group: 'roam-sankey', note: "the sankeyRoam action with a zoom about a point and a pan; a centre and a zoom in the option; roam 'move' takes no wheel", probes: PROBES,
  option: sankey({ roam: 'move', zoom: 1.25, center: ['50%', 180], scaleLimit: { min: 0.5, max: 2 } }),
  steps: [{ action: { type: 'sankeyRoam', seriesIndex: 0, zoom: 1.5, originX: 200, originY: 150 } }, { action: { type: 'sankeyRoam', seriesIndex: 0, dx: 12, dy: -7 } },
    { wheel: [300, 200, 120] }, { resize: [640, 420] }] });

// focus
const sankeyFocus = (focus, extra) => ({ animation: false, color: ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'],
  series: [Object.assign({ type: 'sankey', data: SN, links: SL, lineStyle: { color: '#777777' }, emphasis: { focus } }, extra || {})] });
for (const focus of ['adjacency', 'trajectory', 'self', 'none']) {
  add({ id: 'sf-' + focus, group: 'focus-sankey', note: 'hover node 1, then edge 4, then off the canvas; focus ' + focus,
    option: sankeyFocus(focus), lazyFocus: true });
}
add({ id: 'sf-trajectory-deep', group: 'focus-sankey', note: 'trajectory on four layers: hovering b reaches d -> f, which its adjacency does not',
  option: sankeyFocus('trajectory', { data: SN.concat([{ name: 'f' }]), links: SL.concat([{ source: 'd', target: 'f', value: 6 }]) }), lazyFocus: true });
add({ id: 'sf-highlight-edge', group: 'focus-sankey', note: "the highlight action on a link (dataType 'edge'): its own focus blurs, then downplay",
  option: sankeyFocus('trajectory'),
  steps: [{ action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 2 } },
    { action: { type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: 2 } },
    { action: { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: [1, 5] } }] });
add({ id: 'sf-colour-words', group: 'focus-sankey', note: "state lineStyle colours 'target' (emphasis) and 'source' (blur) take the end nodes' colours",
  option: sankeyFocus('adjacency', { emphasis: { focus: 'adjacency', lineStyle: { color: 'target' } }, blur: { lineStyle: { color: 'source' } } }),
  lazyFocus: true });
add({ id: 'sf-adjacency-blur', group: 'focus-sankey', note: 'focus adjacency with declared blur opacities and an emphasis lineStyle colour',
  option: sankeyFocus('adjacency', { blur: { itemStyle: { opacity: 0.3 }, lineStyle: { opacity: 0.05 } }, emphasis: { focus: 'adjacency', lineStyle: { color: '#ff0000', opacity: 0.8 } } }),
  lazyFocus: true });

// ---------- generation ----------
function edgeMid(st, si, i) {
  // a point inside sankey band i: its box centre (the band runs through it)
  const s = st[st.length - 1].series[si];
  const e = s.edges[i];
  const [x1, y1, cx1, cy1, cx2, cy2, x2, y2, ext] = e.shape;
  const t = 0.5, u = 0.5;
  const bx = u * u * u * x1 + 3 * u * u * t * cx1 + 3 * u * t * t * cx2 + t * t * t * x2;
  const by = u * u * u * y1 + 3 * u * u * t * cy1 + 3 * u * t * t * cy2 + t * t * t * y2;
  const p = applyM(s.m, bx, by + ext / 2);
  return [Math.round(p[0]), Math.round(p[1])];
}

function runCase(c) {
  // the steps that depend on the picture: run once to find them
  let steps = (c.pre || []).concat(c.steps);
  if (c.lazy || c.lazyFocus) {
    const probe = drive(Object.assign({}, c, { steps }));
    if (c.lazy) steps = steps.concat(c.lazy(probe));
    if (c.lazyFocus) {
      const [x, y] = rectCentre(probe, 0, 1);
      const [ex, ey] = edgeMid(probe, 0, 4);
      steps = steps.concat([{ move: [x, y] }, { move: [ex, ey] }, { leave: true }]);
    }
    if (c.lazy2) {
      const p2 = drive(Object.assign({}, c, { steps }));
      steps = steps.concat(c.lazy2(p2));
    }
  }
  const run = Object.assign({}, c, { steps });
  const states = drive(run);
  return { c: run, states };
}

const disc = {};
const bump = k => { disc[k] = (disc[k] || 0) + 1; };

function checkRecipes(c, states) {
  const fails = [];
  const fail = m => fails.push(c.id + ': ' + m);
  states.forEach((st, k) => {
    st.series.forEach(s => {
      if (s.type === 'graph') {
        const P = s.overall ? [s.overall[0], 0, 0, s.overall[1], s.overall[2], s.overall[3]] : I6;
        const invScale = s.overall ? 1 / s.overall[0] : 1;
        const so = c.option.series[s.index];
        s.edges.forEach((e, i) => {
          if (!e || !e.label || e.label.ignore) return;
          const link = (so.links || so.edges)[i] || {};
          const lab = Object.assign({ position: 'middle', distance: 5 }, so.edgeLabel || {}, link.label || {});
          const dist = Array.isArray(lab.distance) ? lab.distance : [lab.distance, lab.distance];
          const r = refLineLabel(e.shape, e.cp, P, invScale, lab.position, dist);
          if (!eqArr(r.M, e.label.m)) fail('state ' + k + ' edge ' + i + ' label m ' + JSON.stringify(e.label.m) + ' recipe ' + JSON.stringify(r.M));
          if (r.align !== e.label.align || r.vAlign !== e.label.vAlign) fail('state ' + k + ' edge ' + i + ' label align ' + e.label.align + '/' + e.label.vAlign + ' recipe ' + r.align + '/' + r.vAlign);
          if (k === 0) {
            if (e.cp) bump('curvedEdgeLabel');
            if (e.cp) {
              // the chord against the derivative at the middle, normalised
              const nrm = v => { const d = Math.sqrt(v[0] * v[0] + v[1] * v[1]); return [v[0] / d, v[1] / d]; };
              const [x1, y1, x2, y2] = e.shape;
              const ch = nrm([x2 - x1, y2 - y1]);
              const de = nrm([2 * ((1 - 0.5) * (e.cp[0] - x1) + 0.5 * (x2 - e.cp[0])), 2 * ((1 - 0.5) * (e.cp[1] - y1) + 0.5 * (y2 - e.cp[1]))]);
              if (ch[0] !== de[0] || ch[1] !== de[1]) bump('chordApart');
            }
            if (Math.abs(r.rotation) > Math.PI / 2) bump('labelTurnedByPi');
            if (lab.position === 'end' && r.align !== 'center') bump('endLabelNotCentred');
            if (s.overall && s.overall[0] !== 1) bump('scaledEdgeLabel');
          }
        });
        if (k === 0 && c.id === 'gs-category-words') {
          // a word edge whose two ends differ in colour
          const so2 = c.option.series[0];
          (so2.links || []).forEach((l, i) => {
            const w = l.lineStyle && l.lineStyle.color;
            if ((w === 'source' || w === 'target') && s.edges[i]) bump('wordEndsDiffer');
          });
        }
        if (k === 0) s.edges.forEach(e => {
          if (!e) return;
          if (e.dash || e.dashWord) bump('perEdgeDash');
          if (e.stroke && e.stroke !== '#888888' && e.stroke !== '#00aa00' && e.stroke !== '#ff0000') bump('wordColour');
        });
      }
      else {
        // R7
        s.edges.forEach((e, i) => {
          if (!e || !e.label) return;
          let [X, Y, W, H] = e.box;
          const m = s.m;
          X = X * m[0] + m[4]; Y = Y * m[3] + m[5]; W = W * m[0]; H = H * m[3];
          if (W < 0) { X += W; W = -W; }
          if (H < 0) { Y += H; H = -H; }
          if (!eq(e.label.x, X + W / 2) || !eq(e.label.y, Y + H / 2)) fail('state ' + k + ' sankey edge ' + i + ' label at ' + e.label.x + ',' + e.label.y);
        });
        if (s.group && s.group[0] !== 1) bump('sankeyZoomed');
      }
    });
    // R4 / R1: the drag recipes on the actions
    st.actions.forEach(a => { if (a.type === 'dragNode') bump('dragNodeAction'); if (a.type === 'sankeyRoam') bump('sankeyRoamAction'); });
  });
  // R1: none drags -- the dragged node moved by the drift recipe
  if (c.group === 'drag-graph' && c.option.series[0].layout === 'none') {
    let dragging = -1, lastX = 0, lastY = 0;
    c.steps.forEach((step, j) => {
      const before = states[j].series[0], after = states[j + 1].series[0];
      if (step.down) {
        // the hovered node under the press (the recorded pixel nearest)
        let best = -1, bd = Infinity;
        before.nodes.forEach((n, i) => { if (!n) return; const dd = Math.hypot(n.px[0] - step.down[0], n.px[1] - step.down[1]); if (dd < bd) { bd = dd; best = i; } });
        const so = c.option.series[0];
        const dr = (so.data[best] && so.data[best].draggable != null) ? so.data[best].draggable : so.draggable;
        dragging = bd <= 12 && dr ? best : -1;
        lastX = step.down[0]; lastY = step.down[1];
      }
      else if (step.move && dragging >= 0) {
        const dx = step.move[0] - lastX, dy = step.move[1] - lastY;
        lastX = step.move[0]; lastY = step.move[1];
        const n = before.nodes[dragging];
        const [osx, osy, ox, oy] = before.overall;
        let det = osx * osy - 0 * 0; det = 1.0 / det;
        const i0 = osy * det, i3 = osx * det, i4 = (0 * oy - osy * ox) * det, i5 = (0 * ox - osx * oy) * det;
        const m4 = osx * n.layout[0] + 0 * n.layout[1] + ox + dx;
        const m5 = 0 * n.layout[0] + osy * n.layout[1] + oy + dy;
        const x = i0 * m4 + (-0 * det) * m5 + i4;
        const y = (-0 * det) * m4 + i3 * m5 + i5;
        const an = after.nodes[dragging];
        if (!eq(an.layout[0], x) || !eq(an.layout[1], y)) fail('step ' + j + ' drift recipe ' + x + ',' + y + ' upstream ' + an.layout);
        const sx = Math.abs(i0 * (osx * n.scale[0]));
        const sy = Math.abs(i3 * (osy * n.scale[1]));
        if (!eq(an.scale[0], sx) || !eq(an.scale[1], sy)) fail('step ' + j + ' drift scale ' + sx + ',' + sy + ' upstream ' + an.scale);
        if (an.scale[0] !== n.scale[0]) bump('driftChangedScale');
      }
      else if (step.up) dragging = -1;
    });
  }
  // R2: circular
  if (c.id === 'g-circular-drag') {
    const s0 = states[0].series[0];
    // the ring's centre and radius from the data rect = the view rect (no positions written)
    let dragging = -1;
    c.steps.forEach((step, j) => {
      const before = states[j].series[0], after = states[j + 1].series[0];
      if (step.down) {
        let best = -1, bd = Infinity;
        before.nodes.forEach((n, i) => { if (!n) return; const dd = Math.hypot(n.px[0] - step.down[0], n.px[1] - step.down[1]); if (dd < bd) { bd = dd; best = i; } });
        dragging = best;
      }
      else if (step.move && dragging >= 0) {
        const an = after.nodes[dragging];
        if (!an.fixed) fail('step ' + j + ' circular dragged node not fixed');
        bump('ringDragFixed');
      }
      else if (step.up) dragging = -1;
    });
    if (states[states.length - 1].series[0].nodes.some(n => n && n.fixed)) fail('a resize kept a fixed ring node');
    must(s0, 'no ring');
  }
  // R3: force
  if (c.id === 'g-force-drag') {
    const moves = [];
    c.steps.forEach((step, j) => { if (step.move) moves.push(j + 1); });
    const a = states[moves[0]].series[0].nodes[1].layout, b = states[moves[1]].series[0].nodes[1].layout;
    if (!eqArr(a, b)) fail('force: the dragged node moved between the moves ' + a + ' / ' + b);
    const other0 = states[moves[0]].series[0].nodes[0].layout, other1 = states[moves[1]].series[0].nodes[0].layout;
    if (eqArr(other0, other1)) fail('force: the other nodes did not settle again');
    bump('forceResettle');
  }
  // R4: sankey drag -- localX accumulates from the shape at the press
  if (c.group === 'drag-sankey' || c.group === 'roam-sankey') {
    let acc = null, lastX = 0, lastY = 0, node = -1;
    c.steps.forEach((step, j) => {
      const before = states[j].series[0];
      const so = c.option.series[0];
      if (step.down) {
        node = -1;
        before.nodes.forEach((n, i) => {
          if (!n) return;
          const [x0, y0, x1, y1] = n.corners;
          const inside = step.down[0] >= Math.min(x0, x1) && step.down[0] <= Math.max(x0, x1) && step.down[1] >= Math.min(y0, y1) && step.down[1] <= Math.max(y0, y1);
          const dr = so.data[i] && so.data[i].draggable != null ? so.data[i].draggable : so.draggable !== false;
          if (inside && dr) node = i;
        });
        if (node >= 0) acc = [before.nodes[node].shape[0], before.nodes[node].shape[1]];
        lastX = step.down[0]; lastY = step.down[1];
      }
      else if (step.move && node >= 0) {
        acc[0] += step.move[0] - lastX; acc[1] += step.move[1] - lastY;
        lastX = step.move[0]; lastY = step.move[1];
        const act = states[j + 1].actions.filter(a => a.type === 'dragNode');
        if (act.length !== 1) { fail('step ' + j + ' expected one dragNode'); return; }
        const bw = before.dataRect ? before.dataRect[2] : NaN, bh = before.dataRect ? before.dataRect[3] : NaN;
        if (!eq(act[0].localX, acc[0] / bw) || !eq(act[0].localY, acc[1] / bh)) fail('step ' + j + ' dragNode ' + act[0].localX + ',' + act[0].localY + ' recipe ' + acc[0] / bw + ',' + acc[1] / bh);
      }
      else if (step.up) node = -1;
    });
  }
  // R5: the sankey roam
  if (c.group === 'roam-sankey' || c.group === 'drag-sankey') {
    const so = c.option.series[0];
    const st = { dr: null, center: so.center != null ? so.center : (c.option.center != null ? c.option.center : null),
      optZoom: so.zoom != null ? so.zoom : 1, limit: so.scaleLimit != null ? so.scaleLimit : (c.option.scaleLimit || null) };
    states.forEach((s, k) => {
      const ss = s.series[0];
      if (!ss.dataRect) { fail('state ' + k + ' no sankey view'); return; }
      if (k > 0) {
        const step = c.steps[k - 1];
        const acts = step.action ? (step.action.type === 'sankeyRoam' ? [step.action] : []) : s.actions.filter(a => a.type === 'sankeyRoam');
        // the action runs on the view of the render before it
        st.dr = states[k - 1].series[0].dataRect;
        for (const a of acts) refAction(st, a);
      }
      st.dr = ss.dataRect;
      const b = refBuild(st);
      if (!eqArr(ss.overall, [b.osx, b.osy, b.ox, b.oy])) fail('state ' + k + ' sankey overall ' + JSON.stringify(ss.overall) + ' recipe ' + JSON.stringify([b.osx, b.osy, b.ox, b.oy]));
    });
  }
  // R8: focus sets
  if (c.group === 'focus-sankey' && c.lazyFocus) {
    const kind = c.option.series[0].emphasis.focus;
    const sn = c.option.series[0].data, sl = c.option.series[0].links;
    const edges = sl.map(l => [sn.findIndex(n => n.name === l.source), sn.findIndex(n => n.name === l.target)]);
    [[1, false, 1], [2, true, 4]].forEach(([k, isEdge, idx]) => {
      const s = states[k].series[0];
      if (kind === 'adjacency' || kind === 'trajectory') {
        const sets = refSets(sn.length, edges, isEdge, idx, kind);
        s.nodes.forEach((n, i) => { if ((n.st.hover === 1) !== !sets.node.includes(i)) fail('state ' + k + ' node ' + i + ' hover ' + n.st.hover); });
        s.edges.forEach((e, i) => { if ((e.st.hover === 1) !== !sets.edge.includes(i)) fail('state ' + k + ' edge ' + i + ' hover ' + e.st.hover); });
        if (kind === 'trajectory') {
          const adj = refSets(sn.length, edges, isEdge, idx, 'adjacency');
          if (sets.edge.length > adj.edge.length) bump(isEdge ? 'trajectoryWider' : 'trajectoryWiderNode');
        }
      }
    });
  }
  return fails;
}

function generate() {
  const out = {
    source: 'ECharts ' + echarts.version, seed: SEED,
    notes: [
      'graph force cases set force.layoutAnimation false: the port settles synchronously; with the default true upstream steps on timers and the dragged node follows the pointer',
      'the default graph edge label text is the NODE value at the edge index (Line.ts: seriesModel.getRawValue(idx)), the edge name when that is null',
      'sankey positions are local to the main group; corners / labels are through its transform',
    ],
    cases: [], guards: [],
  };
  const allFails = [];
  for (const def of CASES) {
    const { c, states } = runCase(def);
    allFails.push(...checkRecipes(c, states));
    out.cases.push({
      id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option, probes: c.probes || [], ring: !!c.ring,
      steps: c.steps,
      states: states.map(st => ({ actions: st.actions.map(encAction), series: st.series.map(s => (s.type === 'graph' ? encGraph(s) : encSankey(s))) })),
    });
  }
  out.guards = Object.keys(disc).sort().map(k => ({ id: k, count: disc[k] }));
  return { out, allFails };
}

function main() {
  const need = ['curvedEdgeLabel', 'labelTurnedByPi', 'endLabelNotCentred', 'scaledEdgeLabel', 'perEdgeDash', 'wordColour', 'sankeyZoomed',
    'dragNodeAction', 'sankeyRoamAction', 'driftChangedScale', 'ringDragFixed', 'forceResettle', 'trajectoryWider',
    'trajectoryWiderNode', 'chordApart', 'wordEndsDiffer'];
  for (const k of Object.keys(disc)) delete disc[k];
  const a = generate();
  const textA = JSON.stringify(a.out);
  for (const k of Object.keys(disc)) delete disc[k];
  const b = generate();
  const textB = JSON.stringify(b.out);
  const fails = a.allFails.slice();
  if (textA !== textB) fails.push('two generations differ');
  for (const k of need) if (!(disc[k] >= 1)) fails.push('discriminating count ' + k + ' is ' + (disc[k] || 0));
  if (textA.indexOf('\\u0000') >= 0) fails.push('a NUL in the fixture');
  JSON.parse(textA);
  if (fails.length) {
    console.error(fails.slice(0, 60).join('\n'));
    console.error(fails.length + ' failure(s); nothing written');
    process.exit(1);
  }
  fs.writeFileSync(OUT, JSON.stringify(a.out, null, 1) + '\n');
  console.log('wrote ' + OUT + ': ' + a.out.cases.length + ' cases, ' + a.out.cases.reduce((n, c) => n + c.states.length, 0) + ' states');
  process.exit(0);
}

try {
  main();
} catch (e) {
  console.error(e && e.stack || e);
  process.exit(1);
}
