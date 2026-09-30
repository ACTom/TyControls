/*
Upstream's own answers for TREE INTERACTION (batch T3): expand / collapse by
the treeExpandAndCollapse action and by a click (T3a), the view transform of a
tree -- the option zoom / center / scaleLimit / nodeScaleRatio in the first
frame, and the treeRoam action with the gestures that dispatch it (T3b) --
and the hover emphasis / blur per emphasis.focus plus the tooltip (T3c).
Research: wf81/upstream.md (the facts) and wf81/port.md (the plan); the first
frame itself is tools/advchart-oracle/tree.js, whose row / symbol / label /
edge record this fixture reuses field for field.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true), 800 x 600
unless a step resizes, `animation: false` on every case, process.env.TZ =
'UTC' set in this script (checked), Math.random = the port's xorshift32
reseeded per chart (the tree draws none). Pointer events go straight to
zrender's Handler (mousedown / mousemove / mouseup / click / mousewheel with
{zrX, zrY, which: 1}), and chart.renderToSVGString() runs before EVERY
pointer event: the hit test walks the last painted display list, and in SSR
nothing repaints on its own. chart._onframe() after a hover / leave turns the
hover flags into element states.

  node tools/advchart-oracle/tree-interact.js

writes tests/fixtures/advchart-tree-interact.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
THE FRESH-FRAME RULE (upstream.md 1.5 / 1.6, port.md 5). With animation false
upstream's redraw after a toggle leaves GHOST curve edges (the removed child's
edge stays in the main group), stale polyline forks, and appends new elements
at the end of the paint order. The port must draw the clean frame. So every
state is ALSO rendered on a SHADOW chart: a fresh chart of the same option
with `collapsed: !isExpand` written on every row whose isExpand now differs
from its initial value, and the live chart's (written-back) center / zoom.
The generator asserts that every live row equals the shadow's row (isExpand,
layout, symbol, label: Object.is on every field) and then records:
  rows       from the LIVE chart, with every `paint` index taken from the shadow
  edges      from the SHADOW (no ghosts, no stale forks)
  paintRuns  from the SHADOW (a fresh render's order)
  ghostEdges the number of ghost edges the live chart holds (documentary:
             never draw them)
The one exception is the view's span-0 rule: when the visible layout has zero
extent on an axis, upstream takes that axis' min / max from the PREVIOUS
render of the view (the shadow, being a first render, uses min - 1 / max + 1).
It changes the picture only under a zoom or a centre; there the LIVE transform
is recorded (it is what upstream shows) and state.spanFromHistory is true.

-----------------------------------------------------------------------------
Numbers are JSON numbers (shortest round trip); NaN in a number field is null;
-0 / Infinity / -Infinity are the strings "-0" / "Infinity" / "-Infinity"; an
absent key means upstream holds undefined.

Top level: source, W, H, seed, tz, api, notes[], symbolPaths (as tree.json),
cases[], tooltips[], guards[], checks.

cases[]: id, part ('T3a' | 'T3b' | 'T3c'), note, option (as fed, animation
  false, ONE tree series), steps[], states[] (index 0 = the first frame, k =
  after steps[k - 1]).
  steps[] (every pointer coordinate is an integer client point; `row` names
  the node a point was aimed at, for the reader):
    {type: 'toggle', dataIndex}         dispatchAction({type:
        'treeExpandAndCollapse', seriesIndex: 0, dataIndex}); never row 0 and
        never out of range (upstream corrupts / throws: port-only refusals)
    {type: 'roam', dx?, dy?}            dispatchAction({type: 'treeRoam',
        seriesIndex: 0, dx, dy}); a missing key is absent from the payload
        (dx alone is NO pan: both must be present)
    {type: 'zoom', factor, originX, originY}   dispatchAction({type:
        'treeRoam', seriesIndex: 0, zoom: factor, originX, originY})
    {type: 'click', x, y, upX, upY, row?, hitSensitive?}   left mousedown at
        (x, y), a mousemove to (upX, upY) when it differs, mouseup and click
        there. hitSensitive: the points lie within a few px of a hit boundary
        (zrender's geometry, not the port's forgiving slop): compare the
        outcome with the recorded `targets`, not with the port's own hits
    {type: 'drag', path: [[x, y], ...], row?}   left press at path[0], a
        mousemove per later point, release + click at the last
    {type: 'wheel', x, y, delta}        mousewheel, zrDelta = delta / 120 (the
        LCL WheelDelta, as graph-roam.json)
    {type: 'hover', x, y, row}          mousemove onto the node, _onframe
    {type: 'leave', x, y}               mousemove onto empty ground, _onframe
    {type: 'resize', width, height}     chart.resize (the port: SetBounds)
    {type: 'reset'}                     dispose + init + setOption(option): the
        port's SetOptionText (clears toggles AND the roam; upstream's own
        setOption keeps a written-back roam, but cannot shrink a live tree
        without throwing at animation false, so it is not recordable)
  states[]:
    W, H
    events[]   what upstream emitted during the step, in order:
               {type: 'treeExpandAndCollapse', dataIndex} | {type: 'treeRoam',
               dx?, dy?, zoom?, originX?, originY?} (the payload's keys as
               dispatched) | {type: 'click', dataIndex, dataType} (the
               generic ECharts click event)
    targets    click / drag only: {down, up, click}, each null or {kind:
               'symbol' | 'label' | 'edge', row}: zrender's _downEl, _upEl and
               the element the click is dispatched to (edge row = its owner)
    layoutInfo, mainGroup    as tree.json (the box; the main group's local
               offset: the box corner, or its centre when radial)
    view       dataRect [x, y, w, h] = the (adjusted) min / max below; min [2],
               max [2] (TreeView._min / _max after the adjustment); span0
               [bool, bool] (the laid-out points have zero extent on x / y);
               group {x, y, scaleX, scaleY} (the outer view group = the
               overall transform); groupTransform (its m6 or null);
               mainTransform (the main group's computed m6 or null); center,
               zoom (seriesModel.option.center / zoom: the option, or what a
               roam wrote back -- a percentage centre stays a '..%' string);
               nodeScale (every symbol group's scaleX: the compensation
               ((zoom - 1) * nodeScaleRatio + 1) / zoom, null with no node)
    spanFromHistory   the live view took an axis from the previous render
    rows[], edges[]   tree.json's row and edge records (see tree.js); rows
               symbol.group.scaleX / scaleY = nodeScale; symbol.global = the
               node's pixel; symbol.transform = the path's global m6; label
               layoutRect / inner / transform follow the zoomed path
    paintRuns  tree.json's run-length paint list (from the shadow)
    ghostEdges upstream's leftover edges (documentary)
    hover      hover states only: {row, target {kind, row}, elements[]}: per
               DRAWN row in row order {row, symbol {states, fill, stroke,
               lineWidth, opacity, scaleX, scaleY, z2}, label null | {states,
               opacity (the Text's style), inkFill, inkOpacity (what its TSpans
               draw), fontSize, z2}, edge null | {owner, states, stroke,
               lineWidth, opacity, z2}}. states [] = normal, ['blur'],
               ['emphasis']. `edge` is the row's OWN edge: curve = its incoming
               Bezier, polyline = its outgoing fork (TreeView's __edge)

tooltips[]: id, option, dataIndex, template (a string formatter: lines hold
  nulls, `visible` is the formatted text), markup (seriesModel.formatTooltip(row,
  false, 'main'): {type, name, value, noValue}), params (getDataParams(row):
  name, value (raw), collapsed, color, treeAncestors [{name, dataIndex,
  value}]), lines [{marker, name, value}] and visible (the real TooltipView,
  renderMode richText, showTip; marker 'item' or null).

-----------------------------------------------------------------------------
Cross-check (any failure: nothing is written, exit 1). A TRANSCRIPTION of the
interaction rules replays every case from its option and steps and must
reproduce, Object.is, every predicted field of every state:
  - the toggle state (initial isExpand, the XOR per toggle, leaves wrap,
    drawn set, empty-symbol fill / stroke through the chain, edge owners and
    ink);
  - the view: bbox with the span-0 history rule, View raw / roam / overall
    (roam.js's recipe), option center / zoom incl. write-back, nodeScale
    (stale on a pan), every node pixel, path transform and label rect /
    anchor / matrix (inputs: the recorded layout, path local and textConfig:
    the first frame is tree.js's to check);
  - the gestures: the pan / zoom payloads each drag / wheel emits (roam modes,
    roamTrigger global / selfRect, wheel factors) and the click rule (same
    element, <= 4 px, expandAndCollapse === true), given the recorded hit
    targets;
  - the hover: every element's state, fill, stroke, width, opacity, scale, z2,
    and the edge-follows-its-node rule in upstream's un-blur order;
  - the tooltip markup, the rendered lines and the params.
Then each guard mutates one rule of the transcription and must change every
case it names. The whole fixture is generated twice (byte-identical).
*/
'use strict';
process.env.TZ = 'UTC';
if (new Date(2017, 0, 1).getTimezoneOffset() !== 0 || new Date(2017, 6, 1).getTimezoneOffset() !== 0
  || new Date(2017, 0, 1).getTime() !== Date.UTC(2017, 0, 1)) {
  console.log('FAILED: process.env.TZ = \'UTC\' did not take effect');
  process.exit(1);
}
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-tree-interact.json');

const W0 = 800;
const H0 = 600;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

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

// ---------- zrender core/util, for JSON-born data ----------
const isArray = Array.isArray;
const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
function zrClone(source) {
  if (source == null || typeof source !== 'object') return source;
  if (isArray(source)) return source.map(zrClone);
  if (ArrayBuffer.isView(source)) return Array.from(source);
  const r = {};
  for (const k in source) if (hasOwn(source, k) && k !== '__proto__') r[k] = zrClone(source[k]);
  return r;
}
function zrMerge(target, source, overwrite) {
  if (!isObject(source) || !isObject(target)) return overwrite ? zrClone(source) : target;
  for (const key in source) {
    if (hasOwn(source, key) && key !== '__proto__') {
      const t = target[key];
      const s = source[key];
      if (isObject(s) && isObject(t) && !isArray(s) && !isArray(t)) zrMerge(t, s, overwrite);
      else if (overwrite || !(key in target)) target[key] = zrClone(s);
    }
  }
  return target;
}
const retrieve2 = (a, b) => (a != null ? a : b);
const json = v => (v === undefined ? null : zrClone(v));
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const m6 = t => (t ? Array.from(t).slice(0, 6) : null);

// TreeSeriesModel.defaultOption on the keys the transcription reads
const DEFAULTS = {
  z: 2, left: '12%', top: '12%', right: '12%', bottom: '12%', layout: 'orthogonal', edgeShape: 'curve', edgeForkPosition: '50%',
  roam: false, roamTrigger: 'global', nodeScaleRatio: 0.4, center: null, zoom: 1,
  orient: 'LR', symbol: 'emptyCircle', symbolSize: 7, expandAndCollapse: true, initialTreeDepth: 2,
  lineStyle: { color: '#cfd2d7', width: 1.5, curveness: 0.5 }, itemStyle: { color: 'lightsteelblue', borderWidth: 1.5 }, label: { show: true },
};
const mergedOption = opt => zrMerge(zrClone(opt), DEFAULTS);
const READ_KEYS = ['layout', 'edgeShape', 'roam', 'roamTrigger', 'nodeScaleRatio', 'center', 'zoom', 'scaleLimit', 'expandAndCollapse', 'initialTreeDepth', 'lineStyle', 'itemStyle', 'leaves', 'emphasis', 'blur'];

// ---- util/number.ts parsePositionOption ----
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
const isPct = v => typeof v === 'string' && /%$/.test(v.trim());

// ---- zrender matrix / Transformable (tree.js) ----
function mul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3], m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
function rotateM(a, rad) {
  const aa = a[0]; const ac = a[2]; const atx = a[4]; const ab = a[1]; const ad = a[3]; const aty = a[5];
  const st = Math.sin(rad);
  const ct = Math.cos(rad);
  return [aa * ct + ab * st, -aa * st + ab * ct, ac * ct + ad * st, -ac * st + ct * ad, ct * (atx - 0) + st * (aty - 0) + 0, ct * (aty - 0) - st * (atx - 0) + 0];
}
const notAroundZero = v => v > 5e-5 || v < -5e-5;
const TT = t => Object.assign({ x: 0, y: 0, scaleX: 1, scaleY: 1, rotation: 0, originX: 0, originY: 0 }, t);
const needLocal = t => notAroundZero(t.rotation) || notAroundZero(t.x) || notAroundZero(t.y) || notAroundZero(t.scaleX - 1) || notAroundZero(t.scaleY - 1);
function localM(t) {
  const ox = t.originX || 0;
  const oy = t.originY || 0;
  const sx = t.scaleX;
  const sy = t.scaleY;
  let m = [];
  if (ox || oy) {
    const dx = ox + 0;
    const dy = oy + 0;
    m[4] = -dx * sx - 0 * dy * sy;
    m[5] = -dy * sy - 0 * dx * sx;
  } else m[4] = m[5] = 0;
  m[0] = sx;
  m[3] = sy;
  m[1] = 0 * sx;
  m[2] = 0 * sy;
  if (t.rotation || 0) m = rotateM(m, t.rotation);
  m[4] += ox + t.x;
  m[5] += oy + t.y;
  return m;
}
function compose(parentM, t) {
  t = TT(t);
  const need = needLocal(t);
  if (!need && !parentM) return null;
  let m = need ? localM(t) : [1, 0, 0, 1, 0, 0];
  if (parentM) m = need ? mul(parentM, m) : parentM.slice();
  return m;
}
function applyRect(r, m) {
  if (!m) return r;
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const o = { x: r.x * m[0] + m[4], y: r.y * m[3] + m[5], width: r.width * m[0], height: r.height * m[3] };
    if (o.width < 0) { o.x += o.width; o.width = -o.width; }
    if (o.height < 0) { o.y += o.height; o.height = -o.height; }
    return o;
  }
  const pt = (x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const lt = pt(r.x, r.y);
  const rt = pt(r.x + r.width, r.y);
  const rb = pt(r.x + r.width, r.y + r.height);
  const lb = pt(r.x, r.y + r.height);
  const x = Math.min(lt[0], rb[0], lb[0], rt[0]);
  const y = Math.min(lt[1], rb[1], lb[1], rt[1]);
  return { x, y, width: Math.max(lt[0], rb[0], lb[0], rt[0]) - x, height: Math.max(lt[1], rb[1], lb[1], rt[1]) - y };
}
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}
function calculateTextPosition(position, distance, rect) {
  const textPosition = position || 'inside';
  distance = distance != null ? distance : 5;
  const height = rect.height;
  const width = rect.width;
  const halfHeight = height / 2;
  let x = rect.x;
  let y = rect.y;
  if (textPosition instanceof Array) {
    x += zrParsePercent(textPosition[0], rect.width);
    y += zrParsePercent(textPosition[1], rect.height);
  } else {
    switch (textPosition) {
      case 'left': x -= distance; y += halfHeight; break;
      case 'right': x += distance + width; y += halfHeight; break;
      case 'top': x += width / 2; y -= distance; break;
      case 'bottom': x += width / 2; y += height + distance; break;
      case 'inside': x += width / 2; y += halfHeight; break;
      case 'insideLeft': x += distance; y += halfHeight; break;
      case 'insideRight': x += width - distance; y += halfHeight; break;
      case 'insideTop': x += width / 2; y += distance; break;
      case 'insideBottom': x += width / 2; y += height - distance; break;
      case 'insideTopLeft': x += distance; y += distance; break;
      case 'insideTopRight': x += width - distance; y += distance; break;
      case 'insideBottomLeft': x += distance; y += height - distance; break;
      case 'insideBottomRight': x += width - distance; y += height - distance; break;
    }
  }
  return { x, y };
}
function mget(levels, p) {
  const pa = isArray(p) ? p : [p];
  for (const lv of levels) {
    let o = lv;
    for (const k of pa) {
      o = o && typeof o === 'object' ? o[k] : null;
      if (o == null) break;
    }
    if (o != null) return o;
  }
  return undefined;
}
const storeFloat = v => (v == null || v === '' ? NaN : Number(v));

// ---- zrender tool/color parse + lift(c, -0.1) (states.ts liftColor) ----
const NAMED = { lightsteelblue: [176, 196, 222], red: [255, 0, 0], white: [255, 255, 255], black: [0, 0, 0], green: [0, 128, 0], blue: [0, 0, 255], orange: [255, 165, 0] };
function parseColor(s) {
  if (typeof s !== 'string') return null;
  const t = s.replace(/ /g, '').toLowerCase();
  if (NAMED[t]) return NAMED[t].concat([1]);
  if (/^#[0-9a-f]{3}$/.test(t)) return [1, 2, 3].map(i => parseInt(t[i] + t[i], 16)).concat([1]);
  if (/^#[0-9a-f]{6}$/.test(t)) return [1, 3, 5].map(i => parseInt(t.substr(i, 2), 16)).concat([1]);
  const m = /^rgba?\((.*)\)$/.exec(t);
  if (m) { const p = m[1].split(',').map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; }
  return null;
}
function liftColor(c) {
  const a = parseColor(c);
  must(a, 'the transcription cannot parse the colour ' + JSON.stringify(c));
  for (let i = 0; i < 3; i++) {
    a[i] = a[i] * 1.1 | 0;
    if (a[i] > 255) a[i] = 255; else if (a[i] < 0) a[i] = 0;
  }
  return 'rgba(' + a.join(',') + ')';
}
const hasPaint = c => c != null && c !== 'none';
// zrender Path.getInsideTextFill: an inside label's ink follows its host's CURRENT fill
function lum(c) { const a = parseColor(c); return a ? (0.299 * a[0] + 0.587 * a[1] + 0.114 * a[2]) * a[3] / 255 + (1 - a[3]) * 0 : 0; }
function insideTextFill(fill) {
  if (fill === 'none') return '#333';
  if (typeof fill === 'string') { const l = lum(fill); return l > 0.5 ? '#333' : l > 0.2 ? '#eee' : '#ccc'; }
  return fill ? '#ccc' : '#333';
}

// ============================================================================
// Reading upstream (tree.js readers, the view added)
// ============================================================================
const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };
const CMD_ARGS = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 };
function decode(data) {
  const out = [];
  for (let i = 0; i < data.length;) {
    const c = data[i++];
    must(CMD_NAME[c], 'an unknown path command ' + c);
    const n = CMD_ARGS[c];
    out.push({ cmd: CMD_NAME[c], args: Array.prototype.slice.call(data, i, i + n) });
    i += n;
  }
  return out;
}
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  if (!el.path.data || el.path.len() === 0) { el.path = null; el.getBoundingRect(); }
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};
function ownStyle(s) {
  const r = {};
  for (const k of Object.keys(s).sort()) {
    if (k === 'blend' && s.blend == null) continue;
    if (k === 'text') continue;
    const v = s[k];
    r[k] = v === undefined ? null : typeof v === 'object' && v !== null && !isArray(v) ? '(object)' : zrClone(v);
  }
  return r;
}
function readLabel(host, displayIndex, classes) {
  const t = host.getTextContent();
  if (!t || t.ignore || t.invisible) return null;
  const s = t.style;
  must(!s.rich, 'a rich label');
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  const boxes = kids.filter(k => k.type === 'rect');
  must(kids.length === spans.length + boxes.length && boxes.length <= 1, 'a label with unexpected children');
  spans.forEach(k => classes.set(k, 'label'));
  boxes.forEach(k => classes.set(k, 'labelBg'));
  classes.set(t, 'label');
  const txt = s.text == null ? null : String(s.text);
  let ink = null;
  if (spans.length) {
    const inks = spans.map(sp => ({ fill: sp.style.fill == null ? null : sp.style.fill, stroke: sp.style.stroke || null, lineWidth: sp.style.stroke ? sp.style.lineWidth : null, opacity: sp.style.opacity }));
    must(inks.every(k => JSON.stringify(k) === JSON.stringify(inks[0])), 'TSpans with different inks');
    ink = inks[0];
  }
  const tc = host.textConfig || {};
  must(tc.position != null, 'a tree label without a textConfig position');
  const BR = echarts.graphic.BoundingRect;
  const lr = tc.layoutRect ? BR.create(tc.layoutRect) : BR.create(host.getBoundingRect());
  if (!tc.local && host.transform) lr.applyTransform(host.transform);
  const layoutRect = rect4(lr);
  const it = t.innerTransformable;
  const c = calculateTextPosition(tc.position, tc.distance, layoutRect);
  const off = tc.offset || [0, 0];
  must(Object.is(it.x, c.x + off[0]) && Object.is(it.y, c.y + off[1]), 'the label placement is not calculateTextPosition on the host rect');
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  const p = spans.length ? displayIndex.get(spans[0]) : undefined;
  let background = null;
  if (boxes.length) {
    const b = boxes[0];
    const bp = displayIndex.get(b);
    background = { shape: rect4(b.shape), style: ownStyle(b.style), paint: bp === undefined ? null : bp };
  }
  return { text: txt, lines: spans.length,
    textConfig: { position: json(tc.position), distance: json(tc.distance), offset: json(tc.offset), rotation: json(tc.rotation), origin: json(tc.origin), inside: json(tc.inside), local: !!tc.local },
    layoutRect,
    inner: { x: it.x, y: it.y, rotation: it.rotation, originX: it.originX, originY: it.originY },
    transform: m6(t.transform),
    align: s.align || ds.align || 'left', verticalAlign: s.verticalAlign || ds.verticalAlign || 'top',
    font: s.font, padding: json(s.padding),
    style: { fill: has('fill') ? json(s.fill) : null, stroke: has('stroke') ? json(s.stroke) : null, lineWidth: has('lineWidth') ? json(s.lineWidth) : null,
      opacity: json(s.opacity), backgroundColor: json(s.backgroundColor) },
    inkDefault: { fill: json(ds.fill), stroke: json(ds.stroke), align: json(ds.align), verticalAlign: json(ds.verticalAlign) }, ink, background,
    tspans: spans.map(sp => ({ text: sp.style.text, x: sp.style.x, y: sp.style.y, textAlign: sp.style.textAlign, textBaseline: sp.style.textBaseline })),
    z: t.z, z2: t.z2, zlevel: t.zlevel, silent: !!t.silent, paint: p === undefined ? null : p };
}
function readSymbol(el, data, idx, displayIndex, classes, symbolPaths) {
  must(el.childCount() === 1, 'a symbol group with several children');
  const pe = el.childAt(0);
  classes.set(pe, 'symbol');
  const type = pe.shape.symbolType;
  must(pe.shape.x === -1 && pe.shape.y === -1 && pe.shape.width === 2 && pe.shape.height === 2, 'a symbol not built in the -1..1 box');
  const cmds = decode(pathOf(pe));
  const bbox = rect4(pe.path.getBoundingRect());
  const rec = JSON.stringify({ bbox, commands: cmds });
  if (symbolPaths[type] === undefined) symbolPaths[type] = rec;
  else must(symbolPaths[type] === rec, 'two ' + type + ' symbols with different paths');
  const size = data.getItemVisual(idx, 'symbolSize');
  const sz = isArray(size) ? [size[0] || 0, size[1] || 0] : [+size || 0, +size || 0];
  const p = displayIndex.get(pe);
  const gt = el.transform;
  return { group: { x: el.x, y: el.y, scaleX: el.scaleX, scaleY: el.scaleY, rotation: el.rotation }, global: gt ? [gt[4], gt[5]] : [el.x, el.y],
    type: el.getSymbolType(), pathType: type, emptyBrush: !!pe.__isEmptyBrush, size: sz,
    path: { x: pe.x, y: pe.y, scaleX: pe.scaleX, scaleY: pe.scaleY, rotation: pe.rotation }, transform: m6(pe.transform), style: ownStyle(pe.style),
    ink: { fill: json(pe.style.fill), stroke: json(pe.style.stroke), lineWidth: json(pe.style.lineWidth), opacity: json(pe.style.opacity) },
    z: pe.z, z2: pe.z2, zlevel: pe.zlevel, silent: !!pe.isSilent(), paint: p === undefined ? null : p,
    label: readLabel(pe, displayIndex, classes) };
}
function readEdge(e, i, node, displayIndex) {
  const ep = displayIndex.get(e);
  const isCurve = e.type === 'bezier-curve';
  const sh = e.shape;
  return { owner: i, kind: isCurve ? 'curve' : 'polyline', elType: e.type,
    from: isCurve ? node.parentNode.dataIndex : i, to: isCurve ? [i] : node.children.map(c => c.dataIndex), lineStyleOf: i,
    shape: isCurve ? { x1: sh.x1, y1: sh.y1, cpx1: sh.cpx1, cpy1: sh.cpy1, cpx2: sh.cpx2, cpy2: sh.cpy2, x2: sh.x2, y2: sh.y2, percent: sh.percent }
      : { parentPoint: sh.parentPoint.slice(), childPoints: sh.childPoints.map(q => q.slice()), orient: sh.orient, forkPosition: json(sh.forkPosition) },
    commands: decode(pathOf(e)), style: ownStyle(e.style),
    ink: { stroke: json(e.style.stroke), lineWidth: json(e.style.lineWidth), opacity: json(e.style.opacity), lineDash: json(e.style.lineDash) },
    z: e.z, z2: e.z2, zlevel: e.zlevel, silent: !!e.isSilent(), paint: ep === undefined ? null : ep };
}
function paintRuns(chart, list, classes) {
  const ec = chart.getModel();
  const owners = new Map();
  ec.eachComponent((mainType, cm) => {
    const v = chart.getViewOfComponentModel(cm);
    if (v && v.group) owners.set(v.group, { owner: 'component', index: cm.componentIndex, type: mainType });
  });
  ec.eachSeries(sm => {
    const v = chart.getViewOfSeriesModel(sm);
    if (v && v.group) owners.set(v.group, { owner: 'series', index: sm.seriesIndex, type: sm.subType });
  });
  const runs = [];
  list.forEach(el => {
    let x = el;
    let viaHost = false;
    let o = null;
    let cls = null;
    while (x) {
      if (owners.has(x)) { o = owners.get(x); break; }
      if (cls == null && classes.has(x)) cls = classes.get(x);
      if (x.parent) x = x.parent;
      else if (x.__hostTarget) { viaHost = true; x = x.__hostTarget; } else x = null;
    }
    let rec;
    if (!o) rec = { owner: 'other', index: null, type: null, group: null };
    else if (o.owner === 'series') rec = { owner: 'series', index: o.index, type: o.type, group: cls || (viaHost ? 'label' : 'mark') };
    else rec = { owner: 'component', index: o.index, type: o.type, group: viaHost ? 'label' : 'mark' };
    Object.assign(rec, { zlevel: el.zlevel, z: el.z, z2: el.z2 });
    const last = runs[runs.length - 1];
    if (last && ['owner', 'index', 'type', 'group', 'zlevel', 'z', 'z2'].every(k => last[k] === rec[k])) last.n++;
    else runs.push(Object.assign(rec, { n: 1 }));
  });
  return runs;
}

// The whole frame of series 0: view, rows, edges (read from __edge: trustworthy on a fresh chart only)
function readFrame(chart, symbolPaths) {
  chart.renderToSVGString();
  const zr = chart.getZr();
  const list = zr.storage.getDisplayList(true);
  const displayIndex = new Map();
  list.forEach((el, i) => displayIndex.set(el, i));
  const classes = new Map();
  const sm = chart.getModel().getSeriesByIndex(0);
  must(sm && sm.subType === 'tree', 'series 0 is not a tree');
  const data = sm.getData();
  const tree = data.tree;
  const view = chart.getViewOfSeriesModel(sm);
  const g = view.group;
  const mg = view._mainGroup;
  must(mg.parent === g && mg.scaleX === 1 && mg.scaleY === 1 && mg.rotation === 0, 'the main group is not a plain translate');
  const rows = [];
  const edges = [];
  const ownedEdges = new Set();
  const points = [];
  let nodeScale = null;
  for (let i = 0; i < data.count(); i++) {
    const node = tree.getNodeByDataIndex(i);
    must(node && node.dataIndex === i, 'row ' + i + ': no node');
    const raw = data.getRawDataItem(i);
    const L = data.getItemLayout(i);
    const laidOut = !!(L && !isNaN(L.x) && !isNaN(L.y));
    if (laidOut) points.push([+L.x, +L.y]);
    const im = data.getItemModel(i);
    const leaves = im.parentModel !== sm;
    const el = data.getItemGraphicEl(i);
    const row = { index: i, name: node.name, valueWritten: raw && hasOwn(raw, 'value') ? json(raw.value) : undefined,
      values: data.dimensions.map(d => data.get(d, i)), value: node.getValue(), depth: node.depth, height: node.height, isExpand: node.isExpand,
      parent: node.parentNode ? node.parentNode.dataIndex : null, children: node.children.map(c => c.dataIndex), leaves,
      chain: leaves ? ['item', 'leaves', 'series'] : ['item', 'series'], laidOut,
      layout: L ? (L.rawX !== undefined ? { x: L.x, y: L.y, rawX: L.rawX, rawY: L.rawY } : { x: L.x, y: L.y }) : null, drawn: !!el, symbol: null, label: null };
    if (el) {
      must(el.parent === mg, 'row ' + i + ': a symbol outside the main group');
      if (nodeScale === null) nodeScale = el.scaleX;
      must(el.scaleX === nodeScale && el.scaleY === nodeScale, 'row ' + i + ': a node scale that differs from the others');
      const sy = readSymbol(el, data, i, displayIndex, classes, symbolPaths);
      row.label = sy.label;
      delete sy.label;
      row.symbol = sy;
      const e = el.__edge;
      if (e && e.parent === mg) {
        classes.set(e, 'edge');
        ownedEdges.add(e);
        edges.push(readEdge(e, i, node, displayIndex));
      }
    }
    rows.push(row);
  }
  // anything in the main group that is neither a node nor an owned edge: upstream's animation-false ghosts
  let ghostEdges = 0;
  mg.childrenRef().forEach(k => {
    if (k.getSymbolPath) return;
    if (!ownedEdges.has(k)) { ghostEdges++; classes.set(k, 'edge'); }
  });
  const min = view._min.slice();
  const max = view._max.slice();
  let pmin = null;
  let pmax = null;
  if (points.length) {
    pmin = points[0].slice(); pmax = points[0].slice();
    points.forEach(p => { pmin[0] = Math.min(pmin[0], p[0]); pmin[1] = Math.min(pmin[1], p[1]); pmax[0] = Math.max(pmax[0], p[0]); pmax[1] = Math.max(pmax[1], p[1]); });
  }
  const vrec = {
    dataRect: [min[0], min[1], max[0] - min[0], max[1] - min[1]], min, max,
    span0: pmin ? [pmax[0] - pmin[0] === 0, pmax[1] - pmin[1] === 0] : null,
    group: { x: g.x, y: g.y, scaleX: g.scaleX, scaleY: g.scaleY }, groupTransform: m6(g.transform), mainTransform: m6(mg.transform),
    center: json(sm.option.center), zoom: json(sm.option.zoom), nodeScale,
  };
  const li = sm.layoutInfo;
  return { sm, view, data, mg, layoutInfo: rect4(li), mainGroup: { x: mg.x, y: mg.y }, viewRec: vrec, rows, edges, ghostEdges,
    paintRuns: paintRuns(chart, list, classes) };
}

// the hover state of every drawn row's symbol, label and own edge
function readHover(chart) {
  const sm = chart.getModel().getSeriesByIndex(0);
  const data = sm.getData();
  const mg = chart.getViewOfSeriesModel(sm)._mainGroup;
  const out = [];
  for (let i = 0; i < data.count(); i++) {
    const el = data.getItemGraphicEl(i);
    if (!el) continue;
    const p = el.getSymbolPath();
    const tc = p.getTextContent();
    const e = el.__edge;
    let label = null;
    if (tc && !tc.ignore && !tc.invisible) {
      const spans = tc.childrenRef().filter(k => k.type === 'tspan');
      label = { states: tc.currentStates.slice(), opacity: json(tc.style.opacity), inkFill: spans.length ? json(spans[0].style.fill) : null,
        inkOpacity: spans.length ? json(spans[0].style.opacity) : null, fontSize: json(tc.style.fontSize), z2: tc.z2 };
    }
    out.push({ row: i,
      symbol: { states: p.currentStates.slice(), fill: json(p.style.fill), stroke: json(p.style.stroke), lineWidth: json(p.style.lineWidth), opacity: json(p.style.opacity),
        scaleX: p.scaleX, scaleY: p.scaleY, z2: p.z2 },
      label,
      edge: e && e.parent === mg ? { owner: i, states: e.currentStates.slice(), stroke: json(e.style.stroke), lineWidth: json(e.style.lineWidth), opacity: json(e.style.opacity), z2: e.z2 } : null });
  }
  return out;
}

// which node / label / edge a zrender element belongs to
function targetOf(chart, el) {
  if (!el) return null;
  const sm = chart.getModel().getSeriesByIndex(0);
  const data = sm.getData();
  let kind = null;
  let x = el;
  if (el.type === 'tspan' || el.type === 'text' || (el.parent && el.parent.type === 'text')) {
    kind = 'label';
    while (x && !x.__hostTarget) x = x.parent;
    x = x ? x.__hostTarget : null;
  }
  for (let i = 0; i < data.count(); i++) {
    const g = data.getItemGraphicEl(i);
    if (!g) continue;
    const p = g.getSymbolPath();
    if (x === p) return { kind: kind || 'symbol', row: i };
    if (g.__edge === el) return { kind: 'edge', row: i };
  }
  return { kind: 'other', row: null };
}

// ============================================================================
// Driving a case
// ============================================================================
const raw = (x, y, extra) => Object.assign({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} }, extra || {});
function newChart(W, H) {
  rngState = SEED;
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}
// the pixel of a drawn node, from its group's global transform
function nodePixel(chart, row) {
  chart.renderToSVGString();
  const data = chart.getModel().getSeriesByIndex(0).getData();
  const el = data.getItemGraphicEl(row);
  must(el, 'aimed at row ' + row + ', which is not drawn');
  const t = el.transform;
  return t ? [t[4], t[5]] : [el.x, el.y];
}
// the fresh-frame option: collapsed written where isExpand now differs from the initial state, the live roam
function shadowOption(option, initial, live, center, zoom) {
  const o = zrClone(option);
  const s = o.series[0];
  const items = [];
  (function walk(list) { list.forEach(it => { items.push(it); if (it.children) walk(it.children); }); })(s.data);
  for (let i = 1; i < live.length; i++) if (live[i] !== initial[i]) items[i - 1].collapsed = !live[i];
  if (center != null) s.center = zrClone(center);
  if (zoom != null) s.zoom = zoom;
  return o;
}
const TRANSFORM_FIELD = /^s\.rows\[\d+\]\.(symbol\.(global|transform)|label\.(layoutRect|inner|transform))/;
const VIEW_FIELD = /^v\.(dataRect|min|max|group|groupTransform|mainTransform)/;

function flat(v, pre, out) {
  if (v === null || v === undefined || typeof v !== 'object') { out[pre] = v; return out; }
  if (isArray(v)) { out[pre + '#'] = v.length; v.forEach((x, i) => flat(x, pre + '[' + i + ']', out)); return out; }
  for (const k of Object.keys(v)) if (v[k] !== undefined) flat(v[k], pre + '.' + k, out);
  return out;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => !Object.is(a[k], b[k])).map(k => ({ field: k, upstream: a[k] === undefined ? '(absent)' : a[k], other: b[k] === undefined ? '(absent)' : b[k] }));
}
const stripPaint = rows => rows.map(r => {
  const c = zrClone(r);
  if (c.symbol) delete c.symbol.paint;
  if (c.label) { delete c.label.paint; if (c.label.background) delete c.label.background.paint; }
  return c;
});
function structural(rows) {
  return rows.map(r => ({ index: r.index, isExpand: r.isExpand, leaves: r.leaves, laidOut: r.laidOut, layout: r.layout, drawn: r.drawn }));
}

const stats = { shadowStates: 0, shadowFields: 0, spanFromHistory: 0, ghostStates: 0 };

function runCase(def, symbolPaths) {
  const option = zrClone(def.option);
  option.animation = false;
  must(option.series.length === 1 && option.series[0].type === 'tree', def.id + ': one tree series');
  let W = def.W || W0;
  let H = def.H || H0;
  let chart = newChart(W, H);
  const events = [];
  const listen = c => {
    c.on('treeExpandAndCollapse', p => events.push({ type: 'treeExpandAndCollapse', dataIndex: p.dataIndex }));
    c.on('treeRoam', p => {
      const e = { type: 'treeRoam' };
      for (const k of ['dx', 'dy', 'zoom', 'originX', 'originY']) if (p[k] !== undefined) e[k] = p[k];
      events.push(e);
    });
    c.on('click', p => events.push({ type: 'click', dataIndex: p.dataIndex, dataType: p.dataType == null ? null : p.dataType }));
  };
  const steps = [];
  const states = [];
  let initial = null;
  let hovering = false;
  let rrng = def.randomToggles ? def.randomToggles.seed >>> 0 : 0;
  const rnd = () => { let x = rrng; x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; rrng = x; return x / 4294967296; };
  try {
    chart.setOption(option);
    listen(chart);
    const snap = (targets, hover) => {
      const live = readFrame(chart, symbolPaths);
      const isExp = live.rows.map(r => r.isExpand);
      if (!initial) initial = isExp.slice();
      // the shadow: a fresh chart of the flipped option with the live roam
      const sopt = shadowOption(option, initial, isExp, live.sm.option.center, live.sm.option.zoom);
      const sc = newChart(W, H);
      let shadow;
      try {
        sc.setOption(sopt);
        shadow = readFrame(sc, symbolPaths);
      } finally {
        sc.dispose();
      }
      must(shadow.ghostEdges === 0, def.id + ': a fresh chart with ghost edges');
      const spanFromHistory = JSON.stringify(live.viewRec.min) !== JSON.stringify(shadow.viewRec.min) || JSON.stringify(live.viewRec.max) !== JSON.stringify(shadow.viewRec.max);
      if (spanFromHistory) must(live.viewRec.span0.some(x => x), def.id + ': the live and fresh view boxes differ without a span-0 axis');
      // live == shadow, field by field (paint aside; the transform only where the span-0 history applies; structure only while hovering)
      const a = hover ? flat(structural(live.rows), 's.rows', {}) : flat(stripPaint(live.rows), 's.rows', {});
      const b = hover ? flat(structural(shadow.rows), 's.rows', {}) : flat(stripPaint(shadow.rows), 's.rows', {});
      Object.assign(a, flat(live.viewRec, 'v', {}), flat(live.layoutInfo, 'li', {}), flat(live.mainGroup, 'mg', {}));
      Object.assign(b, flat(shadow.viewRec, 'v', {}), flat(shadow.layoutInfo, 'li', {}), flat(shadow.mainGroup, 'mg', {}));
      // a re-used symbol path holds no OWN opacity key where a new one holds opacity 1 (the prototype default): the same ink
      const d = diffFlat(a, b).filter(x => !(spanFromHistory && (TRANSFORM_FIELD.test(x.field) || VIEW_FIELD.test(x.field)))
        && !(/\.symbol\.style\.opacity$/.test(x.field) && x.upstream === '(absent)' && x.other === 1));
      must(!d.length, def.id + ' state ' + states.length + ': the live chart differs from the fresh flipped-option chart at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
      stats.shadowStates++;
      stats.shadowFields += Object.keys(a).length;
      if (spanFromHistory) stats.spanFromHistory++;
      if (live.ghostEdges) stats.ghostStates++;
      // rows from the live chart, paint indices from the shadow
      const rows = live.rows.map((r, i) => {
        const s = shadow.rows[i];
        if (r.symbol) { r.symbol.paint = s.symbol.paint; if (!hover) r.symbol.style = s.symbol.style; }
        if (r.label) {
          r.label.paint = s.label ? s.label.paint : null;
          if (r.label.background) r.label.background.paint = s.label && s.label.background ? s.label.background.paint : null;
        }
        return r;
      });
      const st = { W, H, events: events.splice(0), layoutInfo: live.layoutInfo, mainGroup: live.mainGroup, view: live.viewRec, spanFromHistory, rows, edges: shadow.edges,
        paintRuns: shadow.paintRuns, ghostEdges: live.ghostEdges };
      if (targets) st.targets = targets;
      if (hover) st.hover = hover;
      states.push(st);
    };
    snap(null, null);
    const input = def.randomToggles ? Array.from({ length: def.randomToggles.n }, () => ({ type: 'toggle', random: true })) : def.steps;
    for (const s0 of input) {
      const st = Object.assign({}, s0);
      let targets = null;
      let hover = null;
      const h = () => chart.getZr().handler;
      must(!(hovering && st.type !== 'leave' && st.type !== 'hover'), def.id + ': a non-hover step while hovering');
      if (st.type === 'toggle') {
        if (st.random) {
          const data = chart.getModel().getSeriesByIndex(0).getData();
          const drawn = [];
          for (let i = 1; i < data.count(); i++) if (data.getItemGraphicEl(i)) drawn.push(i);
          st.dataIndex = (rnd() < 0.8 && drawn.length) ? drawn[Math.floor(rnd() * drawn.length)] : 1 + Math.floor(rnd() * (data.count() - 1));
          delete st.random;
        }
        must(st.dataIndex >= 1, def.id + ': a toggle of row 0');
        chart.dispatchAction({ type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: st.dataIndex });
      } else if (st.type === 'roam') {
        const p = { type: 'treeRoam', seriesIndex: 0 };
        if (st.dx !== undefined) p.dx = st.dx;
        if (st.dy !== undefined) p.dy = st.dy;
        chart.dispatchAction(p);
      } else if (st.type === 'zoom') {
        chart.dispatchAction({ type: 'treeRoam', seriesIndex: 0, zoom: st.factor, originX: st.originX, originY: st.originY });
      } else if (st.type === 'click' || st.type === 'drag') {
        let pts;
        if (st.type === 'click') {
          if (st.at) {
            const p = nodePixel(chart, st.at.row);
            st.row = st.at.row;
            st.x = Math.round(p[0]) + (st.at.dx || 0);
            st.y = Math.round(p[1]) + (st.at.dy || 0);
            st.upX = st.x + (st.at.upDx || 0);
            st.upY = st.y + (st.at.upDy || 0);
            delete st.at;
          } else if (st.midEdge != null) {
            chart.renderToSVGString();
            const data = chart.getModel().getSeriesByIndex(0).getData();
            const e = data.getItemGraphicEl(st.midEdge).__edge;
            const q = e.pointAt(0.5);
            const g = e.transformCoordToGlobal(q[0], q[1]);
            st.row = st.midEdge;
            st.x = st.upX = Math.round(g[0]);
            st.y = st.upY = Math.round(g[1]);
            delete st.midEdge;
          }
          if (st.upX === undefined) { st.upX = st.x; st.upY = st.y; }
          pts = st.upX === st.x && st.upY === st.y ? [[st.x, st.y]] : [[st.x, st.y], [st.upX, st.upY]];
        } else {
          if (st.fromRow != null) {
            const p = nodePixel(chart, st.fromRow);
            const x0 = Math.round(p[0]);
            const y0 = Math.round(p[1]);
            st.row = st.fromRow;
            st.path = st.rel.map(q => [x0 + q[0], y0 + q[1]]);
            delete st.fromRow; delete st.rel;
          }
          pts = st.path;
        }
        chart.renderToSVGString();
        const hd = h();
        hd.mousedown(raw(pts[0][0], pts[0][1]));
        const down = hd._downEl;
        for (let i = 1; i < pts.length; i++) hd.mousemove(raw(pts[i][0], pts[i][1]));
        const last = pts[pts.length - 1];
        hd.mouseup(raw(last[0], last[1]));
        const up = hd._upEl;
        const clickEl = hd.findHover(last[0], last[1]).target;
        targets = { down: targetOf(chart, down), up: targetOf(chart, up), click: targetOf(chart, clickEl) };
        hd.click(raw(last[0], last[1]));
        // park the pointer on empty ground: the frame is read without the hover a moving press leaves behind
        chart.renderToSVGString();
        must(!hd.findHover(1, 1).target, def.id + ': (1, 1) is not empty ground');
        hd.mousemove(raw(1, 1));
        chart._onframe();
      } else if (st.type === 'wheel') {
        chart.renderToSVGString();
        h().mousewheel(raw(st.x, st.y, { zrDelta: st.delta / 120 }));
      } else if (st.type === 'hover') {
        const p = nodePixel(chart, st.row);
        st.x = Math.round(p[0]);
        st.y = Math.round(p[1]);
        chart.renderToSVGString();
        const t = targetOf(chart, h().findHover(st.x, st.y).target);
        must(t && t.row === st.row && (t.kind === 'symbol' || t.kind === 'label'), def.id + ': the hover point does not hit row ' + st.row + ' (' + JSON.stringify(t) + ')');
        h().mousemove(raw(st.x, st.y));
        chart._onframe();
        hover = { row: st.row, target: t, elements: null };
        hovering = true;
      } else if (st.type === 'leave') {
        if (st.x === undefined) { st.x = 1; st.y = 1; }
        chart.renderToSVGString();
        must(!h().findHover(st.x, st.y).target, def.id + ': the leave point hits an element');
        h().mousemove(raw(st.x, st.y));
        chart._onframe();
        hovering = false;
      } else if (st.type === 'resize') {
        W = st.width; H = st.height;
        chart.resize({ width: W, height: H });
      } else if (st.type === 'reset') {
        chart.dispose();
        chart = newChart(W, H);
        chart.setOption(option);
        listen(chart);
        events.length = 0;
        initial = null;
      } else throw new OracleError(def.id + ': an unknown step ' + JSON.stringify(st));
      if (hover) { chart.renderToSVGString(); hover.elements = readHover(chart); }
      steps.push(st);
      snap(targets, hover);
    }
  } finally {
    chart.dispose();
  }
  return { id: def.id, part: def.part, note: def.note, option, steps, states };
}

// ---------- tooltips (series-text.js withTooltips / parseLine) ----------
function withTooltips(fn) {
  const probe = newChart(W0, H0);
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const getDom = proto.getDom;
  const wasNode = echarts.env.node;
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
  try {
    return fn();
  } finally {
    proto.getDom = getDom;
    echarts.env.node = wasNode;
  }
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
function runTooltip(def) {
  return withTooltips(() => {
    const chart = newChart(W0, H0);
    try {
      const option = zrClone(def.option);
      option.animation = false;
      option.tooltip = Object.assign({ trigger: 'item', renderMode: 'richText', showDelay: 0, transitionDuration: 0 }, def.tooltip || {});
      chart.setOption(option);
      chart.dispatchAction({ type: 'showTip', seriesIndex: 0, dataIndex: def.dataIndex });
      const sm = chart.getModel().getSeriesByIndex(0);
      const mk = sm.formatTooltip(def.dataIndex, false, 'main');
      const pr = sm.getDataParams(def.dataIndex);
      const tv = chart.getViewOfComponentModel(chart.getModel().getComponent('tooltip', 0));
      const content = tv && tv._tooltipContent;
      must(content && content._show && content.el, def.id + ': no tooltip shown');
      const text = String(content.el.style.text);
      const template = typeof option.tooltip.formatter === 'string' || (def.option.series[0].tooltip && typeof def.option.series[0].tooltip.formatter === 'string');
      const lines = text.split('\n').map(line => (template ? { marker: null, name: null, value: null } : parseLine(line, content.el.style.rich || {}, def.id)));
      return { id: def.id, option, dataIndex: def.dataIndex, template,
        markup: { type: mk.type, name: mk.name, value: json(mk.value), noValue: !!mk.noValue },
        params: { name: pr.name, value: json(pr.value), collapsed: pr.collapsed, color: json(pr.color), dataIndex: pr.dataIndex,
          treeAncestors: pr.treeAncestors.map(a => ({ name: a.name, dataIndex: a.dataIndex, value: json(a.value) })) },
        lines, visible: text.replace(SEGMENT, '$2') };
    } finally {
      chart.dispose();
    }
  });
}

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================
function buildNodes(S) {
  const nodes = [];
  (function mk(item, parent, depth) {
    const n = { idx: nodes.length, item, parent, depth, children: [] };
    nodes.push(n);
    (item.children || []).forEach(c => n.children.push(mk(c, n, depth + 1)));
    return n;
  })({ name: S.name, children: S.data }, null, 0);
  return nodes;
}
function initialExpand(nodes, S) {
  let treeDepth = 0;
  nodes.forEach(n => { if (n.depth > treeDepth) treeDepth = n.depth; });
  const eac = S.expandAndCollapse;
  const d = (eac && S.initialTreeDepth >= 0) ? S.initialTreeDepth : treeDepth;
  return nodes.map(n => (n.item && n.item.collapsed != null ? !n.item.collapsed : n.depth <= d));
}
const panMode = r => r === true || r === 'move' || r === 'pan';
const zoomMode = r => r === true || r === 'scale' || r === 'zoom';

// View (roam.js's recipe): st {dr, center, optZoom, limit, ratio, box}
function clampZ(z, lim) {
  if (lim) { const mn = lim.min || 0; const mx = lim.max || Infinity; z = Math.max(Math.min(mx, z), mn); }
  return z;
}
function viewBuild(st, mut) {
  const [dx, dy, dw, dh] = st.dr;
  const [vx, vy, vw, vh] = st.dr;
  const sx = vw / dw;
  const sy = vh / dh;
  const rx = (-dx) * sx + vx;
  const ry = (-dy) * sy + vy;
  let det = sx * sy - 0 * 0;
  det = 1.0 / det;
  const ri0 = sy * det;
  const ri3 = sx * det;
  const ri4 = (0 * ry - sy * rx) * det;
  const ri5 = (0 * rx - sx * ry) * det;
  const vcx = vx + vw / 2;
  const vcy = vy + vh / 2;
  const z = st.zoom;
  let rcx = vcx;
  let rcy = vcy;
  if (st.center) {
    const base = mut.centerPctOfBox ? [st.box.x, st.box.y, st.box.width, st.box.height] : st.dr;
    const px = parsePos(st.center[0], base[2], base[0]);
    const py = parsePos(st.center[1], base[3], base[1]);
    rcx = sx * px + 0 * py + rx;
    rcy = 0 * px + sy * py + ry;
  }
  const roamX = vcx - z * rcx;
  const roamY = vcy - z * rcy;
  return { sx, sy, rx, ry, ri0, ri3, ri4, ri5, vcx, vcy, z, osx: z * sx + 0 * 0, osy: 0 * 0 + z * sy, ox: z * rx + 0 * ry + roamX, oy: 0 * rx + z * ry + roamY };
}
function viewFromModel(st, mut) { st.zoom = clampZ(st.optZoom || 1, st.limit) || 1; st.b = viewBuild(st, mut); }
function nodeScaleOf(st, mut) {
  const ratio = mut.ratioDefault06 && !st.ratioWritten ? 0.6 : st.ratio;
  return ((st.b.z - 1) * (mut.ratioNoOr1 ? ratio : (ratio || 1)) + 1) / (st.b.osx || 1);
}
function toRoam(T, b) {
  return { sx: T.sx * b.ri0 + 0 * 0, sy: 0 * 0 + T.sy * b.ri3, x: T.sx * b.ri4 + 0 * b.ri5 + T.x, y: 0 * b.ri4 + T.sy * b.ri5 + T.y };
}
function viewAction(st, p, mut) {
  const b = st.b;
  const SB1 = { x: b.ox, y: b.oy, sx: b.osx, sy: b.osy };
  const SB2 = toRoam(SB1, b);
  if (mut.panDxOnly ? p.dx != null : (p.dx != null && p.dy != null)) { SB1.x += p.dx; SB1.y += (p.dy || 0); }
  if (p.zoom != null) {
    const oldZ = SB2.sx;
    const newZ = mut.noScaleLimit ? oldZ * p.zoom : clampZ(oldZ * p.zoom, st.limit);
    const k = newZ / oldZ;
    if (!mut.zoomOriginIgnored) {
      SB1.x -= (p.originX - SB1.x) * (k - 1);
      SB1.y -= (p.originY - SB1.y) * (k - 1);
    } else {
      SB1.x -= (b.vcx - SB1.x) * (k - 1);
      SB1.y -= (b.vcy - SB1.y) * (k - 1);
    }
    SB1.sx *= k;
    SB1.sy *= k;
  }
  const R = toRoam(SB1, b);
  const zoom = R.sx;
  const nz = Math.abs(zoom) > 1e-6;
  const c0 = nz ? (b.vcx - R.x) / zoom : b.vcx;
  const c1 = nz ? (b.vcy - R.y) / zoom : b.vcy;
  const d0 = b.ri0 * c0 + 0 * c1 + b.ri4;
  const d1 = 0 * c0 + b.ri3 * c1 + b.ri5;
  const last = st.center;
  const [dx, dy, dw, dh] = st.dr;
  const back = (i, v, o, w) => (!mut.pctWrittenAsPx && w && isPct(last[i]) ? ((v - o) / w * 100) + '%' : v);
  st.center = last ? [back(0, d0, dx, dw), back(1, d1, dy, dh)] : [d0, d1];
  st.optZoom = zoom;
  viewFromModel(st, mut);
  if (p.zoom != null) st.ns = nodeScaleOf(st, mut);
}

// the unit rect of a symbol type grown by its stroke, through its global transform (Path.getBoundingRect + applyTransform)
function hostRect(bb, ink, pathM, mut) {
  let r = { x: bb.x, y: bb.y, width: bb.width, height: bb.height };
  const hasStroke = !(ink.stroke == null || ink.stroke === 'none' || !(ink.lineWidth > 0));
  if (hasStroke) {
    const M = pathM;
    const lineScale = M && Math.abs(M[0] - 1) > 1e-10 && Math.abs(M[3] - 1) > 1e-10 ? Math.sqrt(Math.abs(M[0] * M[3] - M[2] * M[1])) : 1;
    let w = ink.lineWidth;
    if (!(ink.fill != null && ink.fill !== 'none')) w = Math.max(w, 4);
    if (lineScale > 1e-10) { r.width += w / lineScale; r.height += w / lineScale; r.x -= w / lineScale / 2; r.y -= w / lineScale / 2; }
  }
  return applyRect(r, pathM);
}

// the replay of one case: predicted fields per state
function replayCase(c, bbox, mut) {
  const S = mergedOption(c.option.series[0]);
  const nodes = buildNodes(S);
  const init = initialExpand(nodes, S);
  let cur = init.slice();
  const eac = S.expandAndCollapse;
  let hist = null;
  const vs = { center: S.center, optZoom: S.zoom, limit: S.scaleLimit, ratio: S.nodeScaleRatio, ratioWritten: hasOwn(c.option.series[0], 'nodeScaleRatio') };
  const radial = S.layout === 'radial';
  const polyline = S.edgeShape === 'polyline' && !radial;
  const out = [];
  let normal = null;

  const leavesOf = (n, e) => (mut.xorAfterLeaves ? !(n.children.length && init[n.idx]) : !(n.children.length && e[n.idx]));
  const levelsOf = (n, e) => (leavesOf(n, e) ? [n.item, S.leaves || {}, S] : [n.item, S]);
  const drawnOf = e => nodes.map(n => {
    if (n.idx === 0) return false;
    let p = n;
    while (p.parent && p.parent.idx !== 0) { p = p.parent; if (!e[p.idx]) return false; }
    return p.parent !== null && p.parent.idx === 0 && p === nodes[0].children[0];
  });
  function render(rec) {
    const pts = rec.rows.filter(r => r.laidOut).map(r => [r.layout.x, r.layout.y]);
    const min = pts[0].slice();
    const max = pts[0].slice();
    pts.forEach(p => { min[0] = Math.min(min[0], p[0]); min[1] = Math.min(min[1], p[1]); max[0] = Math.max(max[0], p[0]); max[1] = Math.max(max[1], p[1]); });
    for (const k of [0, 1]) {
      if (max[k] - min[k] === 0) {
        const useOld = hist && !mut.span0PlusMinusOne;
        min[k] = useOld ? hist.min[k] : min[k] - 1;
        max[k] = useOld ? hist.max[k] : max[k] + 1;
      }
    }
    hist = { min, max };
    vs.dr = [min[0], min[1], max[0] - min[0], max[1] - min[1]];
    vs.box = rec.layoutInfo;
    viewFromModel(vs, mut);
    vs.ns = nodeScaleOf(vs, mut);
  }
  function frame(rec, hoverState) {
    const drawn = drawnOf(cur);
    const b = vs.b;
    const group = { x: b.ox, y: b.oy, scaleX: b.osx, scaleY: b.osy };
    const groupM = compose(null, group);
    const mainM = compose(groupM, rec.mainGroup);
    const p = { view: { dataRect: vs.dr.slice(), min: hist.min.slice(), max: hist.max.slice(), group, groupTransform: groupM, mainTransform: mainM,
      center: vs.center == null ? null : zrClone(vs.center), zoom: vs.optZoom, nodeScale: drawn.some(x => x) ? vs.ns : null }, rows: [], edges: [] };
    nodes.forEach(n => {
      const r = rec.rows[n.idx];
      const pr = { isExpand: cur[n.idx], leaves: leavesOf(n, cur), drawn: drawn[n.idx] };
      if (drawn[n.idx]) {
        const L = r.layout;
        let nodeM = compose(mainM, { x: L.x, y: L.y, scaleX: vs.ns, scaleY: vs.ns });
        if (mut.pixelZSum && nodeM) nodeM = [nodeM[0], nodeM[1], nodeM[2], nodeM[3], b.osx * (rec.mainGroup.x + L.x) + b.ox, b.osy * (rec.mainGroup.y + L.y) + b.oy];
        const sy = r.symbol;
        const pathM = compose(nodeM, sy.path);
        pr.symbol = { group: { scaleX: vs.ns, scaleY: vs.ns }, global: nodeM ? [nodeM[4], nodeM[5]] : [L.x, L.y], transform: pathM };
        if (!hoverState) {
          const lv = levelsOf(n, cur);
          const color = mget(lv, ['itemStyle', 'color']);
          const collapsedFill = mut.fillFromInitial ? init[n.idx] === false && n.children.length !== 0 : cur[n.idx] === false && n.children.length !== 0;
          if (sy.type.indexOf('empty') === 0) pr.symbol.ink = { fill: collapsedFill ? color : '#fff', stroke: color };
          else { const bc = mget(lv, ['itemStyle', 'borderColor']); pr.symbol.ink = { fill: color, stroke: bc != null ? bc : null }; }
        }
        if (r.label) {
          const tc = r.label.textConfig;
          const rr = hostRect(bbox[sy.pathType], sy.ink, pathM, mut);
          const cp = calculateTextPosition(tc.position, tc.distance, rr);
          const inner = { x: cp.x, y: cp.y, rotation: 0, originX: 0, originY: 0 };
          let innerOrigin = false;
          if (tc.origin && tc.rotation != null) { innerOrigin = true; inner.originX = -inner.x + rr.width * 0.5 + rr.x; inner.originY = -inner.y + rr.height * 0.5 + rr.y; }
          if (tc.rotation != null) inner.rotation = tc.rotation;
          if (tc.offset) { inner.x += tc.offset[0]; inner.y += tc.offset[1]; if (!innerOrigin) { inner.originX = -tc.offset[0]; inner.originY = -tc.offset[1]; } }
          pr.label = { layoutRect: rr, inner, transform: compose(null, inner) };
        }
      }
      p.rows.push(pr);
      // edges (the fresh frame's)
      if (drawn[n.idx]) {
        const lv = levelsOf(n, cur);
        const ink = { stroke: mget(lv, ['lineStyle', 'color']), lineWidth: mget(lv, ['lineStyle', 'width']) };
        if (!radial || S.edgeShape === 'curve') {
          if (S.edgeShape === 'curve' && n.parent && n.parent.idx !== 0) p.edges.push({ owner: n.idx, kind: 'curve', ink });
          if (polyline && n.children.length && cur[n.idx]) p.edges.push({ owner: n.idx, kind: 'polyline', ink });
        }
      }
    });
    return p;
  }
  // T3c: the hover, in upstream's order
  function hoverOf(h, nrec) {
    const drawn = drawnOf(cur);
    const hn = nodes[h];
    const lv = levelsOf(hn, cur);
    let focus = mget(lv, ['emphasis', 'focus']);
    const disabled = mget(lv, ['emphasis', 'disabled']);
    const sym = {};
    const edge = {};
    const own = {};
    nrec.edges.forEach(e => { own[e.owner] = e; });
    nodes.forEach(n => { if (drawn[n.idx]) { sym[n.idx] = 'normal'; if (own[n.idx]) edge[n.idx] = 'normal'; } });
    if (!(disabled && !mut.disabledKeepsBlur)) {
      if (mut.ancestorAsSelf && focus === 'ancestor') focus = 'self';
      const blur = !(focus == null || focus === 'none' || focus === 'series' || (mut.adjacencyAsNone && focus === 'adjacency'));
      if (blur || (disabled && mut.disabledKeepsBlur)) {
        Object.keys(sym).forEach(k => { sym[k] = 'blur'; });
        Object.keys(edge).forEach(k => { edge[k] = 'blur'; });
      }
      const follow = (i, to) => {
        if (!own[i]) return;
        const pa = nodes[i].parent;
        const parentBlurred = pa && drawn[pa.idx] && sym[pa.idx] === 'blur';
        const check = mut.edgeFollowsAlways || (mut.unblurNoParentCheck && to === 'normal') ? false : parentBlurred;
        if (!check) edge[i] = to;
      };
      const anc = n => { const a = []; for (let p = n; p; p = p.parent) a.push(p.idx); return a.reverse(); };
      const desc = n => { const a = []; (function w(x) { a.push(x.idx); x.children.forEach(w); })(n); return a; };
      const list = focus === 'ancestor' ? anc(hn) : focus === 'descendant' ? desc(hn) : focus === 'relative' ? anc(hn).concat(desc(hn)) : null;
      if (!(disabled && mut.disabledKeepsBlur)) {
        if (blur && list) list.forEach(i => { if (drawn[i] && sym[i] === 'blur') { sym[i] = 'normal'; follow(i, 'normal'); } });
        sym[h] = 'emphasis';
        follow(h, 'emphasis');
      }
    }
    const nrow = i => nrec.rows[i];
    const elements = [];
    nodes.forEach(n => {
      if (!drawn[n.idx]) return;
      const i = n.idx;
      const lvi = levelsOf(n, cur);
      const r = nrow(i);
      const ni = r.symbol.ink;
      const s = { states: sym[i] === 'normal' ? [] : [sym[i]], fill: ni.fill, stroke: ni.stroke, lineWidth: ni.lineWidth, opacity: ni.opacity, scaleX: r.symbol.path.scaleX, scaleY: r.symbol.path.scaleY, z2: r.symbol.z2 };
      let lab = null;
      if (r.label) lab = { states: s.states.slice(), opacity: r.label.style.opacity, inkFill: r.label.ink ? r.label.ink.fill : null, inkOpacity: r.label.ink ? r.label.ink.opacity : null, z2: r.label.z2 };
      if (sym[i] === 'blur') {
        const bo = mget(lvi, ['blur', 'itemStyle', 'opacity']);
        s.opacity = bo != null ? bo : mut.blurAbsolute ? 0.1 : (ni.opacity == null ? 1 : ni.opacity) * 0.1;
        if (lab) { const lo = mget(lvi, ['blur', 'label', 'opacity']); lab.opacity = lo != null ? lo : mut.blurAbsolute ? 0.1 : (lab.opacity == null ? 1 : lab.opacity) * 0.1; lab.inkOpacity = lab.opacity; }
      } else if (sym[i] === 'emphasis') {
        const es = {};
        const set = (k, v) => { if (v != null) es[k] = v; };
        set('fill', mget(lvi, ['emphasis', 'itemStyle', 'color']));
        set('stroke', mget(lvi, ['emphasis', 'itemStyle', 'borderColor']));
        set('lineWidth', mget(lvi, ['emphasis', 'itemStyle', 'borderWidth']));
        set('opacity', mget(lvi, ['emphasis', 'itemStyle', 'opacity']));
        if (hasPaint(ni.fill) || hasPaint(ni.stroke)) {
          if (!hasPaint(es.fill) && hasPaint(ni.fill)) { es.fill = liftColor(ni.fill); if (mut.liftStrokeToo && !hasPaint(es.stroke) && hasPaint(ni.stroke)) es.stroke = liftColor(ni.stroke); } else if (!hasPaint(es.stroke) && hasPaint(ni.stroke)) es.stroke = liftColor(ni.stroke);
        }
        Object.assign(s, es);
        const hs = mget(lvi, ['emphasis', 'scale']);
        const ratio = mut.hoverScaleFixed ? 1.1 : (hs == null || hs === true ? Math.max(1.1, 3 / r.symbol.path.scaleY) : (isFinite(hs) && hs > 0 ? +hs : 1));
        s.scaleX = r.symbol.path.scaleX * ratio;
        s.scaleY = r.symbol.path.scaleY * ratio;
        s.z2 += 10;
        if (lab) {
          const lc = mget(lvi, ['emphasis', 'label', 'color']);
          const insideInk = r.label.style.fill == null && !mut.insideInkFixed && lab.inkFill === insideTextFill(ni.fill);
          if (lc != null) lab.inkFill = lc; else if (insideInk) lab.inkFill = insideTextFill(s.fill);
          lab.z2 += 10;
        }
      }
      let ed = null;
      if (own[i]) {
        const e = own[i];
        const lve = levelsOf(nodes[e.lineStyleOf], cur);
        ed = { owner: i, states: edge[i] === 'normal' ? [] : [edge[i]], stroke: e.ink.stroke, lineWidth: e.ink.lineWidth, opacity: e.ink.opacity, z2: e.z2 };
        if (edge[i] === 'blur') { const bo = mget(lve, ['blur', 'lineStyle', 'opacity']); ed.opacity = bo != null ? bo : mut.blurAbsolute ? 0.1 : (e.ink.opacity == null ? 1 : e.ink.opacity) * 0.1; }
        if (edge[i] === 'emphasis') {
          const ec = mget(lve, ['emphasis', 'lineStyle', 'color']);
          const ew = mget(lve, ['emphasis', 'lineStyle', 'width']);
          ed.stroke = ec != null ? ec : liftColor(e.ink.stroke);
          if (ew != null) ed.lineWidth = ew;
          ed.z2 += 10;
        }
      }
      elements.push({ row: i, symbol: s, label: lab, edge: ed });
    });
    return elements;
  }
  // gestures: the payloads a drag / wheel emits, the click rule
  function selfRectHolds(rec, x, y) {
    let r = null;
    rec.rows.forEach(row => {
      if (!row.symbol) return;
      const q = hostRect(bbox[row.symbol.pathType], row.symbol.ink, row.symbol.transform, mut);
      if (!r) r = Object.assign({}, q);
      else { const x2 = Math.max(r.x + r.width, q.x + q.width); const y2 = Math.max(r.y + r.height, q.y + q.height); r.x = Math.min(r.x, q.x); r.y = Math.min(r.y, q.y); r.width = x2 - r.x; r.height = y2 - r.y; }
    });
    return !!r && x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;
  }
  const triggerHolds = (rec, x, y) => (S.roamTrigger === 'selfRect' ? selfRectHolds(rec, x, y) : true);
  const wheelFactor = d => {
    const a = Math.abs(d);
    const f = mut.wheelGe3 ? (a >= 3 ? 1.4 : a > 1 ? 1.2 : 1.1) : (a > 3 ? 1.4 : a > 1 ? 1.2 : 1.1);
    return d > 0 ? f : 1 / f;
  };

  // state 0
  render(c.states[0]);
  out.push(Object.assign({ events: [] }, frame(c.states[0])));
  normal = c.states[0];
  c.steps.forEach((st, k) => {
    const rec = c.states[k + 1];
    const prev = c.states[k];
    const events = [];
    let rerender = false;
    let hover = null;
    if (st.type === 'toggle') {
      events.push({ type: 'treeExpandAndCollapse', dataIndex: st.dataIndex });
      doToggle(st.dataIndex);
      rerender = true;
    } else if (st.type === 'roam' || st.type === 'zoom') {
      const p = {};
      if (st.type === 'roam') { if (st.dx !== undefined) p.dx = st.dx; if (st.dy !== undefined) p.dy = st.dy; } else Object.assign(p, { zoom: st.factor, originX: st.originX, originY: st.originY });
      events.push(Object.assign({ type: 'treeRoam' }, p));
      viewAction(vs, p, mut);
    } else if (st.type === 'wheel') {
      const d = st.delta / 120;
      if (d !== 0 && zoomMode(S.roam) && triggerHolds(prev, st.x, st.y)) {
        const p = { zoom: wheelFactor(d), originX: st.x, originY: st.y };
        events.push(Object.assign({ type: 'treeRoam' }, p));
        viewAction(vs, p, mut);
      }
    } else if (st.type === 'click' || st.type === 'drag') {
      const pts = st.type === 'click' ? (st.upX === st.x && st.upY === st.y ? [[st.x, st.y]] : [[st.x, st.y], [st.upX, st.upY]]) : st.path;
      const t = rec.targets;
      const armed = panMode(S.roam) && triggerHolds(prev, pts[0][0], pts[0][1]) && !(mut.clickNoPan && t.down && (t.down.kind === 'symbol' || t.down.kind === 'label'));
      if (armed) {
        for (let i = 1; i < pts.length; i++) {
          const p = { dx: pts[i][0] - pts[i - 1][0], dy: pts[i][1] - pts[i - 1][1] };
          events.push(Object.assign({ type: 'treeRoam' }, p));
          viewAction(vs, p, mut);
        }
      }
      const a = pts[0];
      const z = pts[pts.length - 1];
      const dist = Math.sqrt((z[0] - a[0]) * (z[0] - a[0]) + (z[1] - a[1]) * (z[1] - a[1]));
      const same = mut.clickCompareRow ? (t.down && t.up && t.down.row === t.up.row && t.down.row != null) || (!t.down && !t.up)
        : JSON.stringify(t.down) === JSON.stringify(t.up);
      const near = mut.clickDistLt4 ? dist < 4 : mut.clickDistLe5 ? dist <= 5 : dist <= 4;
      if (same && near && t.click && (t.click.kind === 'symbol' || t.click.kind === 'label')) {
        const strict = mut.eacTruthy ? !!eac : eac === true;
        if (strict) { events.push({ type: 'treeExpandAndCollapse', dataIndex: t.click.row }); doToggle(t.click.row); rerender = true; }
        events.push({ type: 'click', dataIndex: t.click.row, dataType: 'main' });
      }
    } else if (st.type === 'hover') {
      hover = st.row;
    } else if (st.type === 'leave') {
      // nothing changes: the frame must equal the normal frame again
    } else if (st.type === 'resize') {
      rerender = true;
    } else if (st.type === 'reset') {
      cur = init.slice();
      hist = null;
      Object.assign(vs, { center: S.center, optZoom: S.zoom });
      rerender = true;
    }
    if (rerender) render(rec);
    const p = Object.assign({ events }, frame(rec, hover != null));
    if (hover != null) p.hover = { row: hover, elements: hoverOf(hover, normal) };
    else normal = rec;
    out.push(p);
  });
  return out;

  function doToggle(i) {
    const wasOpen = cur[i];
    cur[i] = !cur[i];
    const n = nodes[i];
    if (mut.toggleResetsDescendants && wasOpen) (function w(x) { x.children.forEach(ch => { cur[ch.idx] = init[ch.idx]; w(ch); }); })(n);
    if (mut.revealOpensChildren && !wasOpen) n.children.forEach(ch => { cur[ch.idx] = true; });
  }
}

// the recorded fields the replay predicts, in the replay's shape
function recordedView(c) {
  return c.states.map(s => {
    const drawn = s.rows.map(r => r.drawn);
    const r = { events: s.events,
      view: { dataRect: s.view.dataRect, min: s.view.min, max: s.view.max, group: s.view.group, groupTransform: s.view.groupTransform, mainTransform: s.view.mainTransform,
        center: s.view.center, zoom: s.view.zoom, nodeScale: s.view.nodeScale },
      rows: s.rows.map(row => {
        const o = { isExpand: row.isExpand, leaves: row.leaves, drawn: row.drawn };
        if (row.symbol) {
          o.symbol = { group: { scaleX: row.symbol.group.scaleX, scaleY: row.symbol.group.scaleY }, global: row.symbol.global, transform: row.symbol.transform };
          if (!s.hover) o.symbol.ink = { fill: row.symbol.ink.fill, stroke: row.symbol.ink.stroke };
        }
        if (row.label) o.label = { layoutRect: row.label.layoutRect, inner: row.label.inner, transform: row.label.transform };
        return o;
      }),
      edges: s.edges.map(e => ({ owner: e.owner, kind: e.kind, ink: { stroke: e.ink.stroke, lineWidth: e.ink.lineWidth } })) };
    must(drawn.length === s.rows.length, 'rows');
    if (s.hover) r.hover = { row: s.hover.row, elements: s.hover.elements.map(e => ({ row: e.row, symbol: e.symbol, label: e.label ? { states: e.label.states, opacity: e.label.opacity, inkFill: e.label.inkFill, inkOpacity: e.label.inkOpacity, z2: e.label.z2 } : null, edge: e.edge })) };
    return r;
  });
}
function caseDiffs(c, bbox, mut) {
  let p;
  try {
    p = replayCase(c, bbox, mut);
  } catch (e) {
    if (!Object.keys(mut).length) throw e;
    return [{ field: 'threw', upstream: null, other: String(e.message) }];
  }
  return diffFlat(flat(recordedView(c), 'c', {}), flat(p, 'c', {}));
}
function tooltipOf(t, mut) {
  const S = mergedOption(t.option.series[0]);
  const nodes = buildNodes(S);
  const init = initialExpand(nodes, S);
  const n = nodes[t.dataIndex];
  const names = [];
  for (let q = n; q && (mut.pathFromVroot || q.idx !== 0); q = q.parent) names.push(q.idx === 0 ? (S.name == null ? '' : String(S.name)) : (q.item.name == null ? '' : String(q.item.name)));
  const name = names.reverse().join('.');
  const iv = n.item.value;
  const value = storeFloat(isArray(iv) ? iv[0] : iv);
  const noValue = isNaN(value) || value == null;
  const addCommas = v => { const s = String(v).split('.'); return s[0].replace(/(\d{1,3})(?=(?:\d{3})+(?!\d))/g, '$1,') + (s.length > 1 ? '.' + s[1] : ''); };
  const line = { marker: null, name, value: noValue ? (mut.nanAsDash ? '-' : null) : addCommas(value) };
  const anc = [];
  for (let q = n; q; q = q.parent) anc.push({ name: q.idx === 0 ? (S.name == null ? '' : String(S.name)) : (q.item.name == null ? '' : String(q.item.name)), dataIndex: q.idx, value: json(q.item.value) });
  return { markup: { type: 'nameValue', name, value, noValue }, lines: t.template ? null : [line],
    params: { name: n.item.name == null ? '' : String(n.item.name), value: json(n.item.value), collapsed: !init[n.idx], dataIndex: n.idx, treeAncestors: anc.reverse() } };
}
function tooltipDiffs(t, mut) {
  const p = tooltipOf(t, mut);
  const rec = { markup: t.markup, lines: t.template ? null : t.lines, params: { name: t.params.name, value: t.params.value, collapsed: t.params.collapsed, dataIndex: t.params.dataIndex, treeAncestors: t.params.treeAncestors } };
  return diffFlat(flat(rec, 't', {}), flat(p, 't', {}));
}

// ============================================================================
// The cases
// ============================================================================
const T7 = () => ({ name: 'A', value: 1, children: [
  { name: 'B', value: 2, children: [{ name: 'D', value: 4 }, { name: 'E', value: 5 }] },
  { name: 'C', value: 3, children: [{ name: 'F', value: 6 }, { name: 'G', value: 7 }] }] });
const T4 = () => ({ name: 'A', value: 1, children: [
  { name: 'B', value: 2, children: [{ name: 'D', value: 4, children: [{ name: 'D1', children: [{ name: 'D11' }] }, { name: 'D2' }] }, { name: 'E', value: 5 }] },
  { name: 'C', value: 3 }] });
const TA = () => ({ name: 'R', children: [
  { name: 'X', children: [{ name: 'x1' }, { name: 'x2' }, { name: 'x3' }] },
  { name: 'Y' },
  { name: 'Z', children: [{ name: 'z1', children: [{ name: 'z11' }, { name: 'z12' }] }, { name: 'z2' }] }] });
const TD = () => ({ name: 'r', children: [
  { name: 'a', children: [{ name: 'a1', children: [{ name: 'a11', children: [{ name: 'a111' }, { name: 'a112' }] }, { name: 'a12' }] }, { name: 'a2' }] },
  { name: 'b' },
  { name: 'c', children: [{ name: 'c1' }, { name: 'c2', children: [{ name: 'c21' }] }] }] });
const chain = (n, k) => (k >= n ? { name: 'n' + k } : { name: 'n' + k, children: [chain(n, k + 1)] });
function randomTree(seed) {
  let s = seed >>> 0;
  const rnd = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
  let counter = 0;
  const gen = depth => {
    const n = { name: 'n' + (counter++), value: Math.floor(rnd() * 100) };
    if (depth < 4 && counter < 22) {
      const k = Math.floor(rnd() * (depth === 0 ? 5 : 4));
      if (k > 0) { n.children = []; for (let i = 0; i < k && counter < 22; i++) n.children.push(gen(depth + 1)); }
    }
    if (rnd() < 0.12) n.collapsed = rnd() < 0.5;
    return n;
  };
  return gen(0);
}
const one = (series, extra) => Object.assign({ animation: false, series: [Object.assign({ type: 'tree' }, series)] }, extra || {});
const tg = d => ({ type: 'toggle', dataIndex: d });
const clickAt = (row, dx, dy, upDx, upDy) => ({ type: 'click', at: { row, dx: dx || 0, dy: dy || 0, upDx: upDx || 0, upDy: upDy || 0 } });
const hov = row => ({ type: 'hover', row });
const LEAVE = { type: 'leave' };
const wh = (x, y, delta) => ({ type: 'wheel', x, y, delta });
const dr = path => ({ type: 'drag', path });

const CASES = [
  // ======================= T3a: the toggle through the action =======================
  { id: 'A-T7-LR', part: 'T3a', note: 'T7 LR: collapse B (filled disc, D / E gone, the layout re-runs: A and C move), expand B, collapse C, collapse the ROOT (one node at (0, 228): span 0 on x and y, invisible at zoom 1), expand it again', option: one({ data: [T7()] }), steps: [tg(2), tg(2), tg(5), tg(1), tg(1)] },
  { id: 'A-T7-RL', part: 'T3a', note: 'T7 RL: collapse B, collapse C, expand B', option: one({ data: [T7()], orient: 'RL' }), steps: [tg(2), tg(5), tg(2)] },
  { id: 'A-T7-TB', part: 'T3a', note: 'T7 TB: collapse B, collapse C, expand B', option: one({ data: [T7()], orient: 'TB' }), steps: [tg(2), tg(5), tg(2)] },
  { id: 'A-T7-BT', part: 'T3a', note: 'T7 BT: collapse B, collapse C, expand B', option: one({ data: [T7()], orient: 'BT' }), steps: [tg(2), tg(5), tg(2)] },
  { id: 'A-T7-radial', part: 'T3a', note: 'T7 radial: collapse B (its label turns OUTWARD: a collapsed inner node takes the leaf side rule), collapse C, expand B, collapse the root (the root label falls through to the atan2 branch)', option: one({ data: [T7()], layout: 'radial' }), steps: [tg(2), tg(5), tg(2), tg(1)] },
  { id: 'A-TA-poly-LR', part: 'T3a', note: 'TA all open, polyline LR: collapse X (its fork goes: a collapsed node owns no fork), collapse z1, expand X, collapse Z', option: one({ data: [TA()], initialTreeDepth: -1, edgeShape: 'polyline' }), steps: [tg(2), tg(8), tg(2), tg(7)] },
  { id: 'A-TA-poly-TB30', part: 'T3a', note: "TA all open, polyline TB edgeForkPosition '30%': collapse Z, collapse z1 (hidden), expand Z (z1 stays collapsed: filled)", option: one({ data: [TA()], initialTreeDepth: -1, edgeShape: 'polyline', orient: 'TB', edgeForkPosition: '30%' }), steps: [tg(7), tg(8), tg(7)] },
  { id: 'A-leaves-styled', part: 'T3a', note: "label left, leaves {label right, itemStyle color red, lineStyle color '#0a0'}: collapsing B moves it into the LEAVES model at once (red fill + stroke, label right, its incoming edge '#0a0'); expanding restores", option: one({ data: [T7()], label: { position: 'left' }, leaves: { label: { position: 'right' }, itemStyle: { color: 'red' }, lineStyle: { color: '#0a0' } } }), steps: [tg(2), tg(2)] },
  { id: 'A-TD-radial-leaves', part: 'T3a', note: 'TD radial, leaves.label right, default depth 2 (a1 / c2 collapsed with children): open a1 (a11 at depth 4 appears COLLAPSED -> filled; the depth rule is not re-read), open c2, collapse a', option: one({ data: [TD()], layout: 'radial', leaves: { label: { position: 'right' } } }), steps: [tg(3), tg(12), tg(2)] },
  { id: 'A-T4-depth', part: 'T3a', note: 'T4 (D at depth 3 closed by the default depth 2): open D -> D1 (has a child) FILLED, D2 hollow; toggle hidden D11 (no visible change); collapse B; expand B (D stays open: the state lives on the node); open D1 (D11, toggled open, is a leaf: no change)', option: one({ data: [T4()] }), steps: [tg(3), tg(5), tg(2), tg(2), tg(4)] },
  { id: 'A-TD-itd1-hidden', part: 'T3a', note: 'TD initialTreeDepth 1: toggle hidden a1 (now open), open a -> a1 appears OPEN with a11 (collapsed, filled) and a12; open a11', option: one({ data: [TD()], initialTreeDepth: 1 }), steps: [tg(3), tg(2), tg(4)] },
  { id: 'A-leaf', part: 'T3a', note: 'toggle the leaf D twice: isExpand flips (false -> true -> false: D is depth 3 > 2), nothing drawn changes, the event fires', option: one({ data: [T7()] }), steps: [tg(3), tg(3)] },
  { id: 'A-eac-false', part: 'T3a', note: 'expandAndCollapse false (everything open by the depth rule): the ACTION still toggles', option: one({ data: [T7()], expandAndCollapse: false }), steps: [tg(2), tg(2)] },
  { id: 'A-multi-root', part: 'T3a', note: 'an extra root (rows 8..10, never drawn): toggling it changes nothing visible; then collapse B', option: one({ data: [T7(), { name: 'Other', children: [{ name: 'o1' }, { name: 'o2' }] }] }), steps: [tg(8), tg(2)] },
  { id: 'A-collapsed-flags', part: 'T3a', note: 'per-item collapsed flags at initialTreeDepth 1 (tree.js X-collapsed): open B (collapsed: true), toggle the collapsed-flag leaf C, collapse D (collapsed: false), open d1',
    option: one({ data: [{ name: 'A', children: [
      { name: 'B', collapsed: true, children: [{ name: 'b1' }] },
      { name: 'C', collapsed: true },
      { name: 'D', collapsed: false, children: [{ name: 'd1', children: [{ name: 'd11', collapsed: false, children: [{ name: 'd111' }] }] }, { name: 'd2', collapsed: false }] },
      { name: 'E', children: [] }] }], initialTreeDepth: 1, label: { position: 'left' }, leaves: { label: { position: 'right' } } }), steps: [tg(2), tg(4), tg(5), tg(5), tg(6)] },
  { id: 'A-resize', part: 'T3a', note: 'collapse B, then resize to 700 x 500 (the toggle survives: the layout re-runs in the new box), expand B', option: one({ data: [T7()] }), steps: [tg(2), { type: 'resize', width: 700, height: 500 }, tg(2)] },
  { id: 'A-reset', part: 'T3a', note: "collapse B, then reset (the port's SetOptionText; upstream: a fresh chart): the first frame again", option: one({ data: [T7()] }), steps: [tg(2), { type: 'reset' }] },
];
// random sequences (8 toggles: 80% on a drawn node, 20% on any row >= 1, hidden ones included)
const RVARIANTS = [
  ['LR', {}], ['RL', { orient: 'RL' }], ['TB', { orient: 'TB' }], ['BT', { orient: 'BT', initialTreeDepth: 3 }], ['radial', { layout: 'radial' }],
  ['poly-LR', { edgeShape: 'polyline', initialTreeDepth: -1 }], ['poly-TB30', { edgeShape: 'polyline', orient: 'TB', edgeForkPosition: '30%', initialTreeDepth: 1 }],
  ['leaves', { label: { position: 'left' }, leaves: { label: { position: 'right' }, itemStyle: { color: 'red' }, lineStyle: { color: '#0a0' } } }],
  ['zoom-LR', { zoom: 1.7, center: ['40%', 60] }], ['zoom-radial', { layout: 'radial', zoom: 1.3, center: [10, -20], initialTreeDepth: 1 }],
];
RVARIANTS.forEach(([name, v], i) => CASES.push({ id: 'R-' + name, part: 'T3a', note: 'a random tree (seeded, <= 22 nodes, some collapsed flags) ' + JSON.stringify(v) + ': 8 random toggles', option: one(Object.assign({ data: [randomTree(0x9e3779b9 + i * 7919)] }, v)), randomToggles: { n: 8, seed: 0x85ebca6b + i } }));
CASES.push(
  // ======================= T3a: the click =======================
  { id: 'G-click', part: 'T3a', note: 'T7: click B at its centre (toggles: the treeExpandAndCollapse event, then the generic click), click B again at its NEW position, click the leaf D (event, no picture), click empty ground, click the middle of the edge A -> B (an edge never toggles)', option: one({ data: [T7()] }),
    steps: [clickAt(2), clickAt(2), clickAt(3), { type: 'click', x: 20, y: 20 }, { type: 'click', midEdge: 2 }] },
  { id: 'G-label', part: 'T3a', note: "label position 'left' distance 20: a click on B's label, 30 px left of the node, toggles B (the label bubbles to its host); 20 px below it hits nothing", option: one({ data: [T7()], label: { position: 'left', distance: 20 } }),
    steps: [clickAt(2, -30, 0), clickAt(2, -30, 20)] },
  { id: 'G-release', part: 'T3a', note: 'symbolSize 20, no labels (the disc r = 11 holds every point): press on B, release 3 px away (toggles), 4 px (toggles: dist <= 4), 5 px (NO click: dist > 4, same element)', option: one({ data: [T7()], symbolSize: 20, label: { show: false } }),
    steps: [clickAt(2, 0, 0, 0, 3), clickAt(2, 0, 0, 0, 4), clickAt(2, 0, 0, 3, 4)] },
  { id: 'G-label-vs-disc', part: 'T3a', note: "label 'left' distance 0: press on B's label and release 4 px right on B's disc -- two different elements, NO click; then press and release on the label 3 px apart (toggles). hitSensitive: zrender's own hit geometry", option: one({ data: [T7()], label: { position: 'left', distance: 0 } }),
    steps: [Object.assign(clickAt(2, -7, 0, 4, 0), { hitSensitive: true }), Object.assign(clickAt(2, -9, 0, 3, 0), { hitSensitive: true })] },
  { id: 'G-eac-false', part: 'T3a', note: 'expandAndCollapse false: a click on B does NOT toggle (the generic click event fires); the action still does', option: one({ data: [T7()], expandAndCollapse: false }), steps: [clickAt(2), tg(2)] },
  { id: 'G-eac-1', part: 'T3a', note: 'expandAndCollapse 1 (truthy, not === true): the depth rule applies (truthy) but a click does NOT toggle', option: one({ data: [T7()], expandAndCollapse: 1 }), steps: [clickAt(2), clickAt(5)] },
  { id: 'G-roam-click', part: 'T3a', note: 'roam true: press on B and release 3 px away: the press pans (a node is not draggable: one treeRoam dx 0 dy 3) AND the release clicks (toggles B)', option: one({ data: [T7()], roam: true }), steps: [clickAt(2, 0, 0, 0, 3)] },
  { id: 'G-click-after-roam', part: 'T3a', note: 'roam true: drag the empty ground, wheel in, then click B where it now is (toggles), then click C', option: one({ data: [T7()], roam: true }), steps: [dr([[20, 20], [40, 30], [60, 50]]), wh(300, 300, 120), clickAt(2), clickAt(5)] },
  // ======================= T3b: the first frame under zoom / center =======================
  { id: 'V-zoom2', part: 'T3b', note: 'zoom 2: group (-304, -228, 2); A at (-112, 372); nodeScale 0.7 -> symbol scale (2 * 0.7) * 3.5 = 4.8999999999999995; labels not scaled', option: one({ data: [T7()], zoom: 2 }), steps: [] },
  { id: 'V-center100', part: 'T3b', note: 'center [100, 100] (bbox-local px): group (204, 128, 1)', option: one({ data: [T7()], center: [100, 100] }), steps: [] },
  { id: 'V-center50pct', part: 'T3b', note: "center ['50%', '50%'] = the bbox centre = the identity", option: one({ data: [T7()], center: ['50%', '50%'] }), steps: [] },
  { id: 'V-center0pct-zoom2', part: 'T3b', note: "center ['0%', '0%'] (the bbox corner, NOT the box / canvas), zoom 2: group (304, 76, 2)", option: one({ data: [T7()], center: ['0%', '0%'], zoom: 2 }), steps: [] },
  { id: 'V-center40pct-zoom1.7', part: 'T3b', note: "center ['40%', 60], zoom 1.7: non-integer; pixel = (z*x + 0*y) + ((z*GX + 0*GY) + tx), NOT z*(GX + x) + tx", option: one({ data: [T7()], center: ['40%', 60], zoom: 1.7 }), steps: [] },
  { id: 'V-radial-zoom1.3', part: 'T3b', note: 'radial, zoom 1.3, center [10, -20] (the main group sits at the box centre)', option: one({ data: [T7()], layout: 'radial', zoom: 1.3, center: [10, -20] }), steps: [] },
  { id: 'V-limit', part: 'T3b', note: 'zoom 3 with scaleLimit {max: 2}: drawn at 2, option.zoom stays 3', option: one({ data: [T7()], zoom: 3, scaleLimit: { max: 2 } }), steps: [] },
  { id: 'V-ratio0', part: 'T3b', note: 'zoom 2, nodeScaleRatio 0: `|| 1` makes it 1 -> nodeScale ((2-1)*1+1)/2 = 1: the symbols grow with the full zoom', option: one({ data: [T7()], zoom: 2, nodeScaleRatio: 0 }), steps: [] },
  { id: 'V-ratio1', part: 'T3b', note: 'zoom 2, nodeScaleRatio 1 (the same as 0)', option: one({ data: [T7()], zoom: 2, nodeScaleRatio: 1 }), steps: [] },
  { id: 'V-solo-zoom2', part: 'T3b', note: 'a single node with zoom 2: span 0 on both axes -> min - 1 .. max + 1 (a first render)', option: one({ data: [{ name: 'solo' }], zoom: 2, label: { position: 'right' } }), steps: [] },
  { id: 'V-chain-zoom2', part: 'T3b', note: "a chain of 4, LR, zoom 2, center ['30%', '30%']: y-span 0 -> a 2 px tall bbox; the y percentage is of that", option: one({ data: [chain(3, 0)], initialTreeDepth: -1, zoom: 2, center: ['30%', '30%'] }), steps: [] },
  { id: 'V-TB-zoom0.6', part: 'T3b', note: 'TB zoom 0.6 (zoom out: nodeScale 1.2666...)', option: one({ data: [T7()], orient: 'TB', zoom: 0.6 }), steps: [] },
  { id: 'V-RL-center', part: 'T3b', note: "RL center ['0%', '100%']", option: one({ data: [T7()], orient: 'RL', center: ['0%', '100%'] }), steps: [] },
  { id: 'V-left-zoom2', part: 'T3b', note: "label 'left' at zoom 2: the label anchor follows the ZOOMED symbol rect (half-extent s + lw/2 with s the global symbol scale); the font is not scaled", option: one({ data: [T7()], zoom: 2, label: { position: 'left' } }), steps: [] },
  { id: 'V-rect-zoom1.5', part: 'T3b', note: "symbol 'rect' [12, 8] (filled, no stroke), labels right, zoom 1.5, center [300, 200]", option: one({ data: [T7()], symbol: 'rect', symbolSize: [12, 8], label: { position: 'right' }, zoom: 1.5, center: [300, 200] }), steps: [] },
  { id: 'V-radial-TA', part: 'T3b', note: "TA radial all open, zoom 0.8, center ['60%', '45%']; the radial label rotation about the symbol centre is unaffected", option: one({ data: [TA()], layout: 'radial', initialTreeDepth: -1, zoom: 0.8, center: ['60%', '45%'] }), steps: [] },
  // ======================= T3b: roam =======================
  { id: 'M-action', part: 'T3b', note: 'roam false: the ACTION still roams: pan (10, 5); zoom 2 about (400, 300); dx alone (NO pan: both needed; the payload and event still carry dx); pan (-30, 12.5); zoom 0.5 about (100, 500) (a zoom re-applies the node scale, a pan does not)', option: one({ data: [T7()] }),
    steps: [{ type: 'roam', dx: 10, dy: 5 }, { type: 'zoom', factor: 2, originX: 400, originY: 300 }, { type: 'roam', dx: 10 }, { type: 'roam', dx: -30, dy: 12.5 }, { type: 'zoom', factor: 0.5, originX: 100, originY: 500 }] },
  { id: 'M-gestures', part: 'T3b', note: 'roam true: a drag on empty ground (two moves: two treeRoam events), wheel +1 notch at (200, 150) (x1.1), wheel -5 notches (1/1.4), a drag starting ON node B (pans: nodes are not draggable)', option: one({ data: [T7()], roam: true }),
    steps: [dr([[20, 20], [30, 25], [50, 45]]), wh(200, 150, 120), wh(200, 150, -600), { type: 'drag', fromRow: 2, rel: [[0, 0], [10, 0], [20, 0]] }] },
  { id: 'M-wheel-factors', part: 'T3b', note: 'roam true: wheel deltas 1, 2, 3, 4 and -2 notches: factor |d| > 3 ? 1.4 : |d| > 1 ? 1.2 : 1.1 (3 -> 1.2, 4 -> 1.4)', option: one({ data: [T7()], roam: true }),
    steps: [wh(400, 300, 120), wh(400, 300, 240), wh(400, 300, 360), wh(400, 300, 480), wh(400, 300, -240)] },
  { id: 'M-move', part: 'T3b', note: "roam 'move': a drag pans, the wheel does nothing", option: one({ data: [T7()], roam: 'move' }), steps: [dr([[20, 20], [50, 45]]), wh(200, 150, 120)] },
  { id: 'M-scale', part: 'T3b', note: "roam 'scale': a drag does nothing, the wheel zooms", option: one({ data: [T7()], roam: 'scale' }), steps: [dr([[20, 20], [50, 45]]), wh(200, 150, 120)] },
  { id: 'M-default', part: 'T3b', note: 'roam unset (false): no gesture roams', option: one({ data: [T7()] }), steps: [dr([[400, 300], [420, 310], [450, 330]]), wh(400, 300, 120)] },
  { id: 'M-limit', part: 'T3b', note: 'roam true, scaleLimit {min 0.5, max 1.5}: 4 x wheel +5 notches saturate at 1.5 (x1.4 each, clamped; a saturated step still emits its event and keeps the pointer fixed), then 5 x -5 at 0.5', option: one({ data: [T7()], roam: true, scaleLimit: { min: 0.5, max: 1.5 } }),
    steps: Array.from({ length: 4 }, () => wh(200, 150, 600)).concat(Array.from({ length: 5 }, () => wh(200, 150, -600))) },
  { id: 'M-selfRect', part: 'T3b', note: "roam true, roamTrigger 'selfRect' (the symbols + edges bbox, no labels: (91.5, 143.5, 617, 313) at identity): wheel inside zooms, wheel outside does not, a drag starting outside does not pan, one starting inside does", option: one({ data: [T7()], roam: true, roamTrigger: 'selfRect' }),
    steps: [wh(400, 300, 120), wh(40, 40, 120), dr([[40, 40], [60, 60]]), dr([[300, 300], [320, 290]])] },
  { id: 'M-pct', part: 'T3b', note: "center ['40%', 60] zoom 1.7, roam true: a pan and a wheel write the centre back as ['..%', number] (a percentage dim stays a percentage)", option: one({ data: [T7()], roam: true, center: ['40%', 60], zoom: 1.7 }), steps: [dr([[20, 20], [35, 28]]), wh(250, 250, -120)] },
  { id: 'M-then-toggle-LR', part: 'T3b', note: 'roam true: pan + wheel x1.2, then collapse B (the new view re-derives from the WRITTEN-BACK centre / zoom: bit-identical to a fresh chart carrying them), collapse the ROOT (span 0: upstream keeps the previous render\'s bbox -> A stays near (111.2, 360), a fresh chart would put it at (-192.8, 360)), expand it', option: one({ data: [T7()], roam: true }),
    steps: [dr([[20, 20], [50, 45]]), wh(200, 150, 360), tg(2), tg(1), tg(1)] },
  { id: 'M-then-toggle-radial', part: 'T3b', note: 'the same on radial', option: one({ data: [T7()], roam: true, layout: 'radial' }), steps: [dr([[20, 20], [50, 45]]), wh(200, 150, 360), tg(2), tg(1), tg(1)] },
  { id: 'M-zoom-root', part: 'T3b', note: "option zoom 2, center ['30%', '70%'] (no roam): collapse the root (span 0 from history: the live transform differs from a fresh chart), expand it, collapse B", option: one({ data: [T7()], zoom: 2, center: ['30%', '70%'] }), steps: [tg(1), tg(1), tg(2)] },
  // ======================= T3c: hover =======================
);
for (const f of [undefined, 'self', 'series', 'ancestor', 'descendant', 'relative', 'adjacency', 'none']) {
  CASES.push({ id: 'F-' + (f || 'unset'), part: 'T3c', note: 'T7, emphasis.focus ' + JSON.stringify(f) + ', hover B, then leave (all back to normal)', option: one(Object.assign({ data: [T7()] }, f ? { emphasis: { focus: f } } : {})), steps: [hov(2), LEAVE] });
}
const T7C = () => { const t = T7(); t.children[1].collapsed = true; return t; };
CASES.push(
  { id: 'F-ancestor-root', part: 'T3c', note: "'ancestor', hover the root A: everything else blurs", option: one({ data: [T7()], emphasis: { focus: 'ancestor' } }), steps: [hov(1)] },
  { id: 'F-descendant-root', part: 'T3c', note: "'descendant', hover the root A: nothing blurs", option: one({ data: [T7()], emphasis: { focus: 'descendant' } }), steps: [hov(1)] },
  { id: 'F-ancestor-leaf', part: 'T3c', note: "'ancestor', hover the leaf D: A, B, D (and B's, D's edges) normal / emphasis, the rest blurred", option: one({ data: [T7()], emphasis: { focus: 'ancestor' } }), steps: [hov(3)] },
  { id: 'F-descendant-collapsed', part: 'T3c', note: "'descendant', C collapsed: true, hover C: its descendants have no elements -> only C un-blurs, its edge stays blurred (parent A blurred)", option: one({ data: [T7C()], emphasis: { focus: 'descendant' } }), steps: [hov(5)] },
  { id: 'F-default-collapsed', part: 'T3c', note: 'no focus, C collapsed (filled): hover C lifts its colour fill', option: one({ data: [T7C()] }), steps: [hov(5)] },
  { id: 'F-poly-default', part: 'T3c', note: "polyline, no focus, hover B: B's OWN edge is its outgoing fork (to D, E): emphasised", option: one({ data: [T7()], edgeShape: 'polyline' }), steps: [hov(2)] },
  { id: 'F-poly-descendant', part: 'T3c', note: "polyline 'descendant', hover B", option: one({ data: [T7()], edgeShape: 'polyline', emphasis: { focus: 'descendant' } }), steps: [hov(2)] },
  { id: 'F-poly-ancestor-leaf', part: 'T3c', note: "polyline 'ancestor', hover the leaf D (D owns no fork)", option: one({ data: [T7()], edgeShape: 'polyline', emphasis: { focus: 'ancestor' } }), steps: [hov(3)] },
  { id: 'F-poly-ancestor-B', part: 'T3c', note: "polyline 'ancestor', hover B", option: one({ data: [T7()], edgeShape: 'polyline', emphasis: { focus: 'ancestor' } }), steps: [hov(2)] },
  { id: 'F-item-focus', part: 'T3c', note: "item-level emphasis.focus 'self' on B only: hovering B blurs the rest; hovering C (no focus) blurs nothing", option: one({ data: [{ name: 'A', children: [{ name: 'B', emphasis: { focus: 'self' }, children: [{ name: 'D' }] }, { name: 'C' }] }] }), steps: [hov(2), LEAVE, hov(4)] },
  { id: 'F-leaves-focus', part: 'T3c', note: "leaves.emphasis.focus 'ancestor': the leaf D reads it (hover D); the inner B does not (hover B: no blur)", option: one({ data: [T7()], leaves: { emphasis: { focus: 'ancestor' } } }), steps: [hov(3), LEAVE, hov(2)] },
  { id: 'F-disabled', part: 'T3c', note: "emphasis {disabled: true, focus: 'self'}: no emphasis AND no blur", option: one({ data: [T7()], emphasis: { disabled: true, focus: 'self' } }), steps: [hov(2)] },
  { id: 'F-blur-declared', part: 'T3c', note: "'self' with blur {itemStyle opacity 0.5, lineStyle opacity 0.3, label opacity 0.2}: taken as is", option: one({ data: [T7()], emphasis: { focus: 'self' }, blur: { itemStyle: { opacity: 0.5 }, lineStyle: { opacity: 0.3 }, label: { opacity: 0.2 } } }), steps: [hov(2)] },
  { id: 'F-opacity', part: 'T3c', note: "'self' with itemStyle opacity 0.5 and lineStyle opacity 0.5: blur = normal x 0.1 = 0.05", option: one({ data: [T7()], emphasis: { focus: 'self' }, itemStyle: { opacity: 0.5 }, lineStyle: { opacity: 0.5 } }), steps: [hov(2)] },
  { id: 'F-scale-false', part: 'T3c', note: 'emphasis.scale false: no hover growth', option: one({ data: [T7()], emphasis: { scale: false } }), steps: [hov(2)] },
  { id: 'F-scale-2', part: 'T3c', note: 'emphasis.scale 2: x2', option: one({ data: [T7()], emphasis: { scale: 2 } }), steps: [hov(2)] },
  { id: 'F-size2', part: 'T3c', note: 'symbolSize 2: the default hover factor max(1.1, 3 / (size / 2)) = 3', option: one({ data: [T7()], symbolSize: 2 }), steps: [hov(2)] },
  { id: 'F-styles', part: 'T3c', note: "emphasis {itemStyle {color red, borderColor blue}, lineStyle {color green, width 4}, label {color orange, fontSize 20}}: declared, no lift", option: one({ data: [T7()], emphasis: { itemStyle: { color: 'red', borderColor: 'blue' }, lineStyle: { color: 'green', width: 4 }, label: { color: 'orange', fontSize: 20 } } }), steps: [hov(2)] },
  { id: 'F-fill-only', part: 'T3c', note: "emphasis.itemStyle.color red only: the fill is declared, so the STROKE is lifted instead", option: one({ data: [T7()], emphasis: { itemStyle: { color: 'red' } } }), steps: [hov(2)] },
  { id: 'F-circle', part: 'T3c', note: "symbol 'circle' (fill = colour, no stroke): the fill lifts", option: one({ data: [T7()], symbol: 'circle' }), steps: [hov(2)] },
  { id: 'F-label-left', part: 'T3c', note: "label 'left', 'descendant', hover B: the hover scale grows the symbol rect, so B's label anchor moves with it", option: one({ data: [T7()], label: { position: 'left' }, emphasis: { focus: 'descendant' } }), steps: [hov(2)] },
  { id: 'F-zoomed', part: 'T3c', note: "zoom 2 and 'relative', hover B", option: one({ data: [T7()], zoom: 2, emphasis: { focus: 'relative' } }), steps: [hov(2)] },
  { id: 'F-radial', part: 'T3c', note: "radial 'ancestor', hover the leaf G", option: one({ data: [T7()], layout: 'radial', emphasis: { focus: 'ancestor' } }), steps: [hov(7)] },
  { id: 'F-after-roam', part: 'T3c', note: "roam true: pan and wheel, then 'descendant' hover B, leave", option: one({ data: [T7()], roam: true, emphasis: { focus: 'descendant' } }), steps: [dr([[20, 20], [50, 45]]), wh(200, 150, 120), hov(2), LEAVE] },
);

const TIPTREE = () => ({ name: 'A', value: 1, children: [
  { name: 'B', value: [2, 20], children: [{ name: 'D', value: 4 }, { name: 'E' }] },
  { name: 'C', value: 'x', collapsed: true, children: [{ name: 'F', value: 6 }] },
  { name: 'K', value: 1234567.5, children: [{ name: 'k1', value: -9876 }, { name: 12 }] }] });
const TIPS = [];
[1, 2, 3, 4, 5, 7, 8, 9].forEach(r => TIPS.push({ id: 'tip-' + r, option: one({ name: 'S', data: [TIPTREE()] }), dataIndex: r }));
TIPS.push({ id: 'tip-unnamed-3', option: one({ data: [TIPTREE()] }), dataIndex: 3 });
TIPS.push({ id: 'tip-fmt-2', option: one({ name: 'S', data: [TIPTREE()], tooltip: { formatter: '{b}: {c}' } }), dataIndex: 2 });
TIPS.push({ id: 'tip-fmt-4', option: one({ name: 'S', data: [TIPTREE()], tooltip: { formatter: '{b}: {c}' } }), dataIndex: 4 });
TIPS.push({ id: 'tip-depth-D', option: one({ name: 'S', data: [T4()] }), dataIndex: 3 });
TIPS.push({ id: 'tip-depth-E', option: one({ name: 'S', data: [T4()] }), dataIndex: 7 });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'xor-after-leaves', mutation: 'the leaves model read from the INITIAL isExpand (the toggle mask applied after LeafModelled)', mut: { xorAfterLeaves: true }, named: ['A-leaves-styled', 'A-T7-LR', 'R-leaves'] },
  { id: 'fill-from-initial', mutation: 'the collapsed-with-children fill from the initial isExpand', mut: { fillFromInitial: true }, named: ['A-T7-LR', 'A-T4-depth', 'A-TD-itd1-hidden'] },
  { id: 'toggle-resets-descendants', mutation: "collapsing a node resets its descendants' toggles", mut: { toggleResetsDescendants: true }, named: ['A-T4-depth'] },
  { id: 'reveal-opens-children', mutation: 'opening a node opens its children (the depth rule not kept)', mut: { revealOpensChildren: true }, named: ['A-T4-depth', 'A-TD-radial-leaves'] },
  { id: 'span0-plus-minus-one', mutation: 'a span-0 axis always min - 1 .. max + 1 (the previous render ignored)', mut: { span0PlusMinusOne: true }, named: ['M-then-toggle-LR', 'M-then-toggle-radial', 'M-zoom-root'] },
  { id: 'pixel-z-times-sum', mutation: 'pixel = z * (GX + x) + tx instead of (z*x) + ((z*GX) + tx)', mut: { pixelZSum: true }, named: ['V-center40pct-zoom1.7'] },
  { id: 'center-pct-of-box', mutation: 'a percentage centre of the series box instead of the laid-out bbox', mut: { centerPctOfBox: true }, named: ['V-center0pct-zoom2', 'V-center40pct-zoom1.7', 'M-pct'] },
  { id: 'ratio-no-or-1', mutation: 'nodeScaleRatio used raw (0 not replaced by 1)', mut: { ratioNoOr1: true }, named: ['V-ratio0'] },
  { id: 'ratio-default-0.6', mutation: "the default nodeScaleRatio 0.6 (graph's) instead of the tree's 0.4", mut: { ratioDefault06: true }, named: ['V-zoom2', 'M-gestures'] },
  { id: 'pan-dx-only', mutation: 'a pan applied when only dx is present', mut: { panDxOnly: true }, named: ['M-action'] },
  { id: 'zoom-origin-ignored', mutation: 'a zoom about the view centre instead of the pointer', mut: { zoomOriginIgnored: true }, named: ['M-action', 'M-gestures'] },
  { id: 'pct-written-as-px', mutation: 'a percentage centre written back as a number', mut: { pctWrittenAsPx: true }, named: ['M-pct'] },
  { id: 'no-scale-limit', mutation: 'scaleLimit ignored by a roam', mut: { noScaleLimit: true }, named: ['M-limit'] },
  { id: 'wheel-ge-3', mutation: 'wheel factor 1.4 from |d| >= 3 (instead of > 3)', mut: { wheelGe3: true }, named: ['M-wheel-factors'] },
  { id: 'click-dist-lt-4', mutation: 'a click needs dist < 4 (instead of <= 4)', mut: { clickDistLt4: true }, named: ['G-release'] },
  { id: 'click-dist-le-5', mutation: 'a click allows dist <= 5', mut: { clickDistLe5: true }, named: ['G-release'] },
  { id: 'click-compare-row', mutation: 'a click compares the node (row), not the element (label vs disc)', mut: { clickCompareRow: true }, named: ['G-label-vs-disc'] },
  { id: 'eac-truthy', mutation: 'a click toggles on a truthy expandAndCollapse (instead of === true)', mut: { eacTruthy: true }, named: ['G-eac-1'] },
  { id: 'click-no-pan', mutation: 'a press on a node does not arm the pan', mut: { clickNoPan: true }, named: ['G-roam-click', 'M-gestures'] },
  { id: 'unblur-no-parent-check', mutation: "an un-blurred node's edge follows without the parent-blurred check", mut: { unblurNoParentCheck: true }, named: ['F-descendant', 'F-poly-descendant'] },
  { id: 'edge-follows-always', mutation: "the hovered node's edge follows even under a blurred parent", mut: { edgeFollowsAlways: true }, named: ['F-self', 'F-descendant-collapsed'] },
  { id: 'lift-stroke-too', mutation: 'the default emphasis lifts the stroke as well as the fill', mut: { liftStrokeToo: true }, named: ['F-unset', 'F-default-collapsed'] },
  { id: 'ancestor-as-self', mutation: "'ancestor' treated as 'self' on a tree", mut: { ancestorAsSelf: true }, named: ['F-ancestor', 'F-ancestor-leaf', 'F-radial'] },
  { id: 'adjacency-as-none', mutation: "'adjacency' on a tree treated as no focus (instead of 'self')", mut: { adjacencyAsNone: true }, named: ['F-adjacency'] },
  { id: 'disabled-keeps-blur', mutation: 'emphasis.disabled suppresses the emphasis but still blurs', mut: { disabledKeepsBlur: true }, named: ['F-disabled'] },
  { id: 'blur-absolute', mutation: 'blur opacity 0.1 absolute (not normal x 0.1)', mut: { blurAbsolute: true }, named: ['F-opacity'] },
  { id: 'inside-ink-fixed', mutation: "an inside label keeps its normal ink when the host's emphasis fill changes", mut: { insideInkFixed: true }, named: ['F-fill-only'] },
  { id: 'hover-scale-fixed', mutation: 'the default hover factor 1.1 (not max(1.1, 3 / (size / 2)))', mut: { hoverScaleFixed: true }, named: ['F-size2'] },
  { id: 'tip-path-from-vroot', mutation: 'the tooltip path starts at the virtual root (series name)', mut: { pathFromVroot: true }, named: ['tip-3', 'tip-unnamed-3'], tooltip: true },
  { id: 'tip-nan-as-dash', mutation: "a NaN / missing tooltip value shown as '-'", mut: { nanAsDash: true }, named: ['tip-4', 'tip-5'], tooltip: true },
];

// ============================================================================
// Output helpers (tree.js)
// ============================================================================
let specials = 0;
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) { specials++; return 'Infinity'; }
    if (v === -Infinity) { specials++; return '-Infinity'; }
    if (Object.is(v, -0)) { specials++; return '-0'; }
    return v;
  }
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return v;
  if (isArray(v)) return v.map(x => { const s = sanitize(x); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    const s = sanitize(v[k]);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + Array.from(v, x => oneLine(x === undefined ? null : x)).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const f = oneLine(v);
  if (f.length + ind.length <= LINE || v === null || typeof v !== 'object') return f;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = Array.from(v, x => fmt(x === undefined ? null : x, inner));
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
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
}

// ============================================================================
// Generate and check
// ============================================================================
function generate() {
  const symbolPathsText = {};
  const cases = CASES.map(d => {
    try {
      return runCase(d, symbolPathsText);
    } catch (e) {
      if (e instanceof OracleError && !e.message.startsWith(d.id)) e.message = d.id + ': ' + e.message;
      throw e;
    }
  });
  const tooltips = TIPS.map(runTooltip);
  const symbolPaths = {};
  for (const k of Object.keys(symbolPathsText).sort()) symbolPaths[k] = JSON.parse(symbolPathsText[k]);
  return { cases, tooltips, symbolPaths };
}

function check(g) {
  const bbox = {};
  for (const k of Object.keys(g.symbolPaths)) bbox[k] = g.symbolPaths[k].bbox;
  let fields = 0;
  let states = 0;
  for (const c of g.cases) {
    // the option upstream holds is the fed one over the defaults, on the keys the transcription reads
    const d = caseDiffs(c, bbox, {});
    must(!d.length, c.id + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
    fields += Object.keys(flat(recordedView(c), 'c', {})).length;
    states += c.states.length;
  }
  for (const t of g.tooltips) {
    const d = tooltipDiffs(t, {});
    must(!d.length, t.id + ': the tooltip transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
    fields += Object.keys(flat(t, 't', {})).length;
  }
  // the colour lift agrees with zrender's own
  for (const col of ['lightsteelblue', '#fff', '#cfd2d7', 'red', '#0a0', 'rgba(10,20,30,0.5)']) must(liftColor(col) === echarts.color.lift(col, -0.1), 'liftColor(' + col + ') ' + liftColor(col) + ' vs ' + echarts.color.lift(col, -0.1));
  // anchors from upstream.md
  const byId = {};
  g.cases.forEach(c => { byId[c.id] = c; });
  const st = (id, k) => byId[id].states[k];
  const px = (id, k, r) => st(id, k).rows[r].symbol.global;
  const eqA = (a, b) => a.length === b.length && a.every((x, i) => Object.is(x, b[i]));
  const grp = (id, k) => { const v = st(id, k).view.group; return [v.x, v.y, v.scaleX]; };
  must(eqA(grp('V-zoom2', 0), [-304, -228, 2]) && eqA(px('V-zoom2', 0, 1), [-112, 372]), 'V-zoom2 anchors');
  must(st('V-zoom2', 0).rows[1].symbol.transform[0] === 4.8999999999999995 && st('V-zoom2', 0).view.nodeScale === 0.7, 'V-zoom2 symbol scale');
  must(eqA(grp('V-center100', 0), [204, 128, 1]) && eqA(px('V-center100', 0, 1), [300, 428]), 'V-center100');
  must(eqA(grp('V-center0pct-zoom2', 0), [304, 76, 2]), 'V-center0pct-zoom2');
  must(eqA(grp('M-gestures', 1), [30, 25, 1]) && JSON.stringify(st('M-gestures', 1).view.center) === '[274,203]', 'M-gestures drag');
  must(eqA(grp('M-gestures', 2), [13, 12.499999999999972, 1.1]), 'M-gestures wheel +1');
  must(eqA(grp('M-action', 2), [-380, -290, 2]) && JSON.stringify(st('M-action', 2).view.center) === '[342,259]', 'M-action zoom');
  must(st('M-limit', 4).view.group.scaleX === 1.5 && st('M-limit', 9).view.group.scaleX === 0.5, 'M-limit saturation');
  must(st('M-then-toggle-LR', 4).spanFromHistory && st('M-then-toggle-LR', 4).rows[1].symbol.global[0] > 100, 'M-then-toggle-LR: the root collapse keeps the old bbox');
  must(st('A-leaves-styled', 1).rows[2].symbol.ink.fill === 'red' && st('A-leaves-styled', 1).edges.find(e => e.owner === 2).ink.stroke === '#0a0', 'A-leaves-styled');
  must(st('A-T4-depth', 1).rows[4].symbol.ink.fill === 'lightsteelblue' && st('A-T4-depth', 1).rows[6].symbol.ink.fill === '#fff', 'A-T4-depth: D1 filled, D2 hollow');
  must(st('G-release', 1).events.some(e => e.type === 'treeExpandAndCollapse') && st('G-release', 2).events.some(e => e.type === 'treeExpandAndCollapse') && !st('G-release', 3).events.some(e => e.type === 'treeExpandAndCollapse'), 'G-release: 3, 4 toggle; 5 does not');
  must(!st('G-label-vs-disc', 1).events.length && st('G-label-vs-disc', 2).events.some(e => e.type === 'treeExpandAndCollapse'), 'G-label-vs-disc');
  const hb = (id, k) => st(id, k).hover.elements;
  const el = (id, k, r) => hb(id, k).find(e => e.row === r);
  must(el('F-descendant', 1, 2).edge.states.join() === 'blur' && el('F-self', 1, 2).edge.states.join() === 'blur' && el('F-unset', 1, 2).edge.states.join() === 'emphasis', 'focus edge rule');
  must(el('F-unset', 1, 2).symbol.stroke === 'lightsteelblue' && el('F-unset', 1, 2).symbol.fill === 'rgba(255,255,255,1)', 'default lift');
  must(g.tooltips.find(t => t.id === 'tip-3').markup.name === 'A.B.D', 'tooltip path');
  // every guard: every named case must change
  const guards = GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    if (gd.tooltip) {
      for (const t of g.tooltips) { const d = tooltipDiffs(t, gd.mut); if (d.length) { changed.push(t.id); if (gd.named.includes(t.id)) differs.push({ case: t.id, fields: d.slice(0, 3) }); } }
    } else {
      for (const c of g.cases) { const d = caseDiffs(c, bbox, gd.mut); if (d.length) { changed.push(c.id); if (gd.named.includes(c.id)) differs.push({ case: c.id, fields: d.slice(0, 3) }); } }
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(x => changed.includes(x)), differs };
  });
  return { guards, fields, states };
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let g1;
let chk;
let json1;
let json2;
let nSpecial = 0;
try {
  g1 = generate();
  chk = check(g1);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W: W0, H: H0, seed: SEED, tz: 'UTC',
    api: {
      chart: "echarts.init(null, null, {renderer: 'svg', ssr: true, width, height}); setOption(option, animation false); renderToSVGString() before every pointer event and before every read",
      toggle: "dispatchAction({type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex}) (update: the whole pipeline re-runs)",
      roam: "dispatchAction({type: 'treeRoam', seriesIndex: 0, dx, dy | zoom, originX, originY}) (update none: the view group re-derives from the written-back center / zoom; the node scale is re-applied only with a zoom)",
      pointer: 'chart.getZr().handler.mousedown / mousemove / mouseup / click / mousewheel({zrX, zrY, which: 1, zrDelta}); hover = mousemove + chart._onframe()',
      frame: 'rows / view from the live chart; edges / paintRuns / paint indices from a fresh chart of the flipped option (the fresh-frame rule)',
      tooltip: "TooltipView with renderMode 'richText' (env.node off, getDom stubbed), showTip {seriesIndex 0, dataIndex}; seriesModel.formatTooltip(row, false, 'main'); getDataParams(row)",
    },
    notes: [
      'T3a. A toggle is exactly the same option with `collapsed` flipped on that row (the shadow check holds on every state of every case): initialTreeDepth is read only when the tree is built; a revealed child keeps its own isExpand (A-T4-depth: D1 filled, D2 hollow); toggles below a collapsed ancestor persist (A-T4-depth, A-TD-itd1-hidden); a collapsed inner node takes the LEAVES model at once (A-leaves-styled: red, label right, its incoming edge #0a0); a leaf toggle flips isExpand and fires the event with no picture change (A-leaf); the action is not gated by expandAndCollapse (A-eac-false). Never toggle row 0 (upstream corrupts the layout) or a row out of range (upstream throws): the port refuses both.',
      'The click: zrender fires `click` only when mousedown and mouseup hit the SAME ELEMENT (a label and its disc are two) and the press and click points are <= 4 px apart (G-release: 3, 4 toggle, 5 does not; G-label-vs-disc). Only expandAndCollapse === true wires the click (G-eac-1: 1 does not). A label click toggles its node (G-label); an edge never toggles (G-click). Events: treeExpandAndCollapse {dataIndex}, then the generic click {dataIndex}. With roam, a press on a node also arms the pan (nodes are not draggable): G-roam-click emits treeRoam AND toggles. The recorded `targets` are zrender\'s hits; the port\'s hit slop is larger (7.5 vs 4.5 px): steps marked hitSensitive rely on zrender geometry.',
      'Upstream animation-false artefacts NOT recorded (the port draws the fresh frame): ghost curve edges after a collapse (state.ghostEdges counts them), stale polyline forks, new elements appended to the paint order.',
      'T3b. The view: dataRect = bbox of the laid-out (x, y) in main-group-local coords (Math.min / max from the first point); a zero-extent axis takes the PREVIOUS render\'s min / max for that axis (spanFromHistory), or min - 1 / max + 1 on a first render (V-solo-zoom2, V-chain-zoom2); the adjusted values are stored. raw = identity (sx = w / w = 1, rx = -x + x = 0). zoom = clamp(option.zoom || 1, scaleLimit) || 1. centre: null -> the bbox centre, else parsePositionOption(c, bbox w | h, bbox x | y) (a percentage is of the BBOX). roam x = vc - z * c. overall = roam x raw, on the OUTER view group; the main group is its child at (GX, GY). Node pixel = (z*x + 0*y) + ((z*GX + 0*GY) + tx) (zrender composition; V-center40pct-zoom1.7 tells it from z*(GX + x) + tx).',
      'Node scale: symbol GROUP scale = ((zoom - 1) * (nodeScaleRatio || 1) + 1) / overall.scaleX (nodeScaleRatio default 0.4; 0 means 1: V-ratio0); set at render and after a zoom action, not after a pan. Path scale = size / 2 (unchanged); drawn half-size = (z * ns) * (size / 2) (4.8999999999999995 for zoom 2, size 7). The ring (lineWidth 2) and the edges (1.5) keep their screen width (strokeNoScale); edge geometry scales with the full zoom; labels are NOT scaled, their anchor follows the zoomed symbol rect.',
      'Roam action: overall pan by (dx, dy) only when BOTH are present; zoom k = clamp(oldZoom * zoom) / oldZoom about (originX, originY); then center = rawInverse((vc - roam) / zoom) and zoom written into the option (a percentage centre dim is written back as a percentage), and the view re-derived from them (round trip: 5 -> 5.000000000000028). Gestures (roam true | move / pan | scale / zoom): each mousemove of a left drag = one treeRoam {dx, dy}; wheel zrDelta d != 0 -> {zoom: (|d| > 3 ? 1.4 : |d| > 1 ? 1.2 : 1.1)^sign(d), originX, originY}; roamTrigger selfRect = inside the symbols + edges bbox (no labels). The action is never gated by roam (M-action on roam false).',
      "Roam then toggle: the new view is built from the new bbox and the written-back center / zoom -- identical to a fresh chart carrying them -- except the span-0 axis rule (M-then-toggle-*, M-zoom-root: the LIVE transform is recorded). The port's FTreeBox is that history; clearing it with the option is safe (upstream cannot shrink a live tree by setOption at animation false).",
      "T3c. focus is read through the HOVERED node's chain (item -> leaves when leaf-modelled -> series). none / series / unset: no blur. Any other string ('self', 'adjacency', unknown): blur every symbol, label and edge of the series. 'ancestor' (root ... self), 'descendant' (self, pre-order) and 'relative' (their concat) then un-blur those rows IN THAT ORDER. Then the hovered node enters emphasis. A row's OWN edge (curve: incoming; polyline: its outgoing fork) follows its node into normal / emphasis ONLY IF the parent's symbol is not blurred at that moment. emphasis.disabled: nothing at all.",
      'Looks: emphasis symbol fill = declared or lift(fill) (c * 1.1 | 0, "rgba(r,g,b,a)"); the stroke is lifted only when the fill was declared (F-fill-only) or absent; scale x (emphasis.scale true / unset: max(1.1, 3 / (size / 2)); a number; false: 1); z2 + 10. Label z2 + 10, emphasis.label.color. Edge stroke declared or lifted, width only if declared, z2 + 10. Blur: opacity = declared blur.*.opacity or normal x 0.1 (symbol / label: itemStyle, edge: lineStyle); colours, size, z2 unchanged.',
      "Tooltip: one nameValue block, no marker; name = the dotted path from the REAL root ('A.B.D'); value = the first value dimension; NaN / missing -> no value at all (not '-'); thousands commas. params.collapsed = !isExpand; treeAncestors from the virtual root (series name, value undefined -> absent) down to the node.",
    ],
    symbolPaths: g1.symbolPaths,
    cases: g1.cases,
    tooltips: g1.tooltips,
    guards: chk.guards,
    checks: { states: chk.states, transcriptionFields: chk.fields, shadowStates: stats.shadowStates, shadowFields: stats.shadowFields, spanFromHistoryStates: stats.spanFromHistory, ghostStates: stats.ghostStates, fails: 0 },
  };
  specials = 0;
  const s1 = sanitize(out);
  nSpecial = specials;
  json1 = fmt(s1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(s1), 'the written JSON does not parse back');
  if (!process.env.ORACLE_ONCE) {
    const g2 = generate();
    const c2 = check(g2);
    const out2 = Object.assign({}, out, { symbolPaths: g2.symbolPaths, cases: g2.cases, tooltips: g2.tooltips, guards: c2.guards });
    json2 = fmt(sanitize(out2), '') + '\n';
  } else json2 = json1;
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message + (process.env.ORACLE_DEBUG ? '\n' + e.stack : '') : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const bad = chk.guards.filter(gd => !gd.ok);
chk.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': named ' + gd.named.join(' / ') + '; changes ' + gd.changed.length));
const deterministic = json1 === json2;
console.log(g1.cases.length + ' cases, ' + chk.states + ' states, ' + g1.tooltips.length + ' tooltips; transcription ' + chk.fields + ' fields, 0 fails; shadow ' + stats.shadowStates / (process.env.ORACLE_ONCE ? 1 : 2) + ' states agree; '
  + stats.spanFromHistory / (process.env.ORACLE_ONCE ? 1 : 2) + ' span-from-history states; ' + stats.ghostStates / (process.env.ORACLE_ONCE ? 1 : 2) + ' states with upstream ghosts; '
  + (chk.guards.length - bad.length) + '/' + chk.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + nSpecial + ' -0/Infinity; '
  + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
