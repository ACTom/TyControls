// Upstream's own answers for graph roam: the View's transforms under the
// center / zoom / scaleLimit / nodeScaleRatio options, under the graphRoam
// action and under the pointer gestures that dispatch it, for the port to be
// held to (batch 45 audit, wf45/audit45.md SS1 and SS3).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer), drives each case
// through its steps, renders after the first setOption and after every step
// (renderToSVGString, so every transform is current), and reads the live
// objects -- never the SVG text, which rounds to 4 decimals. Math.random is the
// port's xorshift32, reseeded for every chart (the force case draws from it).
//
// The recipes (SS1; fl() = one IEEE double rounding, left to right):
//   raw   sx = vw/dw, sy = vh/dh, rx = (-dx)*sx + vx, ry = (-dy)*sy + vy
//         (dataRect dx,dy,dw,dh and viewRect vx,vy,vw,vh as recorded)
//   rawInv det = 1/(sx*sy), ri0 = sy*det, ri3 = sx*det,
//         ri4 = (-(sy*rx))*det, ri5 = (-(sx*ry))*det
//   zoom  z = clamp(zoomOpt || 1, limit) || 1; clamp = max(min(limit.max ||
//         Inf, z), limit.min || 0), only when a scaleLimit object exists
//   centre none/falsy -> (vx + vw/2, vy + vh/2); else each dim through
//         parsePositionOption(c, dw|dh, dx|dy) ('center'/'middle' '50%',
//         'left'/'top' '0%', 'right'/'bottom' '100%'; '..%' parseFloat/100*
//         base + offset; other strings parseFloat; null NaN; else +c), then
//         rc = s*p + r per dim
//   roam  roamX = vcx - z*rcx, roamY = vcy - z*rcy
//   overall osx = z*sx, osy = z*sy, ox = z*rx + roamX, oy = z*ry + roamY
//   overallInv  zrender matrix.invert of [osx,0,0,osy,ox,oy] (6 values)
//   pixel px = osx*x + ox, py = osy*y + oy (== the node group's computed
//         transform [4..5] == cs.dataToPoint)
//   trigger X = dx*osx + ox, Y = dy*osy + oy, W = dw*osx, H = dh*osy (a
//         negative W or H flips: X += W, W = -W); inside iff x >= X &&
//         x <= X+W && y >= Y && y <= Y+H
//   action SS1.3: SB1 = overall; SB2 = toRoam(SB1), toRoam(T) = {sx: T.sx*ri0,
//         sy: T.sy*ri3, x: T.sx*ri4 + T.x, y: T.sy*ri5 + T.y}; dx AND dy
//         non-null -> SB1.x += dx, SB1.y += dy; zoom non-null -> new =
//         clamp(SB2.sx*zoom), k = new/SB2.sx, SB1.x -= (originX - SB1.x)*(k-1)
//         (y alike), SB1.sx *= k, SB1.sy *= k; R = toRoam(SB1); stored zoom =
//         R.sx; c = |R.sx| > 1e-6 ? (vc - R.xy)/R.sx : vc; d = ri0*c0 + ri4
//         (y alike); a dim whose last centre option was a '%' string (and dw
//         != 0) stores (d - dx)/dw*100 + '%', else d; then rebuild
//   nodeScale ns = ((z-1)*(nodeScaleRatio || 1) + 1) / (osx || 1), read
//         (nodeScaleRatio, default 0.6, not climbing) on render, resize,
//         relayout, reset and on a payload with a zoom; a pan keeps it STALE
//   half  [fl(fl(osx*ns)*(w/2)), fl(fl(osy*ns)*(h/2))], w,h = the symbol size
//   wheel d = WheelDelta/120; d = 0 does nothing; f = |d| > 3 ? 1.4 : |d| > 1
//         ? 1.2 : 1.1; zoom = d > 0 ? f : 1/f; payload {zoom, originX: x,
//         originY: y} to the first series (below) whose trigger holds (x,y)
//         or whose roamTrigger is 'global'; nobody -> not consumed
//   drag  a LEFT press on no draggable node arms every pan-enabled series
//         whose trigger holds it (or 'global'); each move goes to the first
//         armed series (below): {dx: x - lastX, dy: y - lastY}, last := (x,y),
//         wherever the pointer is; a left release disarms all; middle and
//         right presses and releases do nothing
//   order the series by zlevel desc, then z desc, then series index asc
//   modes roam true/null: pan + zoom; 'move'/'pan': pan; 'scale'/'zoom':
//         zoom; anything else: neither (a dispatched action still applies)
//   climb center and scaleLimit climb to the option root; zoom and
//         nodeScaleRatio do not
//
// The fixture, top level:
//   source   'ECharts <version>'
//   seed     the xorshift32 seed Math.random restarts from on every chart
//   cases[]  below
//
// Per case:
//   name, group      group 1..11 as in audit45.md SS3.3
//   W, H             the canvas the case starts on
//   option           the option as run (JSON), fed to setOption
//   steps[]          each an object with exactly ONE key:
//     action {dx?,dy?,zoom?,originX?,originY?, +Text twins, seriesIndex?}
//                    dispatchAction({type:'graphRoam', ...}); a missing key
//                    is absent (not null); no seriesIndex = every graph series
//     wheel {x, y, delta}   integer client point and the LCL WheelDelta
//                    (zrDelta = delta/120), the pointer over the canvas
//     drag {button, up, path}   button 1 left | 2 middle | 3 right: pressed
//                    at path[0] (0: no press, path[0] is a move); every later
//                    path point is a move; `up` (1|2|3, 0 none) is released
//                    at the last path point. Integer client points, which
//                    may lie outside the canvas
//     resize [W, H]  chart.resize (the port: SetBounds + a render)
//     relayout true  setOption({series:[{}]}) (the port: Invalidate + render)
//     reset <option>   setOption(option, notMerge) (the port: SetOptionText)
//   probes[]         [x, y] integer pointer points, fixed for the case; each
//                    series record's `contain` answers them in this order
//   gesture          the case has a wheel or drag step (self-check b ran)
//   ring             a circular layout: ring positions are sin/cos-based,
//                    compare layout within 1e-9 (unless TyJsSin/Cos is used);
//                    everything computed FROM the layout stays exact
//   force            a force layout: the layout must stay identical across
//                    all states (roam never re-runs it; the generator checks)
//   dragsNode[]      node indices zrender's Draggable drifts under the press
//                    (node dragging is OUT in the port; Element.drift re-
//                    derives the group's scale even for a 0-px move): their
//                    records are not compared, and nodeScale is read from the
//                    other nodes
//   nonFinite        the case's records hold non-finite numbers (below)
//   documentary, note   recorded for the reader, no port assertion
//   deferred, why    a self-check failed by design (the step and field)
//   discriminates    counts over the case's series-states (self-check c):
//     nonUniformRaw  |raw.sx/raw.sy - 1| > 1e-3
//     zoomDrift      csZoom != the plain product of the nominal zoom factors
//                    applied since the render (clamped the same way)
//     staleScale     nodeScale != nodeScaleIfRecomputed
//     pctCentre      a centre dim is a percent
//     ringRelaid     a relayout/resize state of a ring whose layout moved
//     triggerShrunk  probe points inside the viewRect but outside the trigger
//                    (the trigger shrank or moved off them)
//     clampLanded    after a zoom step, the zoom sits exactly on a limit
//   states[]         index-parallel to [initial render, after step 1, ...]:
//     W, H           the canvas
//     events[]       gesture steps only (else []): every graphroam payload
//                    upstream emitted, in order, as
//                    {series, dx, dy, +Text} | {series, zoom, originX, originY,
//                    +Text}; series = the series index the payload targets
//     nonFinite      how many numbers in this state were non-finite
//     series[]       one record per graph series, in series index order:
//       index
//       dataRect[4], viewRect[4]       x, y, width, height
//       raw[4]          sx, sy, x, y           (cs.trans[0])
//       rawInv[4]       ri0, ri3, ri4, ri5     (cs.mtRawInv)
//       roam[3]         x, y, s                (cs.trans[1])
//       overall[4]      sx, sy, x, y           (cs.trans[2])
//       overallInv[6]   cs.mtOverallInv
//       trigger[4]      X, Y, W, H per the recipe from cs.mtOverall
//       contain         '0'/'1' per probe: cs.containPoint
//       edgeProbes[]    [x hex, y hex, 0|1] (no twins): (X, my), (pred X, my), (fl(X+W), my),
//                       (succ fl(X+W), my), (mx, Y), (mx, pred Y),
//                       (mx, fl(Y+H)), (mx, succ fl(Y+H)); mx = fl(X + W/2),
//                       my = fl(Y + H/2); 1/0 = cs.containPoint; [] when the
//                       trigger is not finite
//       center          null (no centre option anywhere) | [dim, dim], dim =
//                       {kind:'num', v} | {kind:'pct', v, str} (v =
//                       parseFloat(str), String(v)+'%' === str) | {kind:'kw',
//                       str} | {kind:'str', v, str} (v = parseFloat(str)) |
//                       {kind:'null'}: the effective centre option
//                       (getShallow('center'), climbing)
//       zoom            the effective zoom option (getShallow('zoom'); the
//                       roam writes back the UNCLAMPED R.sx here)
//       csZoom          the clamped zoom the View uses
//       nodeScale       the node elements' scaleX (stale across pans), null
//                       without nodes
//       nodeScaleIfRecomputed  ns from the current View
//       nodes[i]        null (no element) | {layout[2] (data space),
//                       px[2] (group computed transform [4..5]), half[2]
//                       (symbol path computed transform [0] and [3]),
//                       label: null | {x, y (label transform [4..5]), align,
//                       vAlign} (the alignment the text is drawn with)}
//       edges[i]        null | {shape[4] x1,y1,x2,y2 (data, after adjustEdge,
//                       before any sub-pixel snap), cp: null (upstream's
//                       cpx1/cpy1 are NaN on a straight edge) | [cpx1, cpy1],
//                       pixelEnds[4] (cs.dataToPoint of both ends),
//                       fromArrow, toArrow: null | {x, y (data), scale,
//                       rotation, px[2] (computed transform [4..5])},
//                       label: null | {px[2]} (transform [4..5]),
//                       lineWidthLocal (lineWidth / getLineScale(): documentary),
//                       snapPath? (documentary snap cases only: the
//                       [x, y] points buildPath hands the context, snapped)}
//
// Every Double is the 16 lowercase hex digits of its IEEE-754 bits (big-
// endian), with a readable twin beside it: `k` hex, `kText` text (arrays
// parallel). A non-finite number is written as null with its twin 'NaN',
// 'Infinity' or '-Infinity' (so null + a text twin = non-finite; null + null =
// absent), and counted in the state's nonFinite. The twin of -0 is '-0'.
// Integers that are inputs (pointer points, deltas, sizes, indices) are plain.
//
// Self-checks (the fixture is not written and the run exits 1 when a case not
// declared deferred fails any):
//   a  the embedded recipe (above; wf45/ref.js, generalised) reproduces every
//      view number, contain and edge-probe boolean, the centre (kind and
//      value), zoom, csZoom, nodeScale (stale-aware) and nodeScaleIfRecomputed,
//      every node px and half, every edge pixelEnds, bit for bit, at every
//      step, and predicts every gesture's emitted payloads (which series, and
//      the numbers); a declared-deferred case records the first step+field
//      that differs
//   b  each gesture case, replayed on a fresh chart with its recorded events
//      dispatched as graphRoam actions in place of the gestures, gives an
//      identical record at every state
//   c  every discriminates count, summed over the fixture, is >= 1
//   d  the whole fixture is generated twice in the process and the two JSON
//      texts are byte-identical
//   e  every non-finite number is classified (null + twin) and appears only
//      in a case declared nonFinite, which must have one
//
//   node tools/advchart-oracle/roam.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-graph-roam.json');

const SEED = 2463534242; // TyGraphForceSeed(0)
let rngState = SEED;
function rnd() {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
}
Math.random = rnd;

class OracleError extends Error {}
function must(cond, msg) { if (!cond) throw new OracleError(msg); }

// ---------- number writing ----------

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
// the neighbouring doubles (finite, non-zero-crossing use only)
function nextUp(v) {
  if (v === 0) return Number.MIN_VALUE;
  bits.setFloat64(0, v);
  const big = bits.getBigUint64(0);
  bits.setBigUint64(0, v > 0 ? big + 1n : big - 1n);
  return bits.getFloat64(0);
}
function nextDown(v) { return -nextUp(-v); }

// A writer context counts the non-finite numbers of one state.
let nfCount = 0;
function isNum(v) { return typeof v === 'number'; }
function hx(v) {
  if (v == null) return null;
  must(isNum(v), 'not a number: ' + JSON.stringify(v));
  if (!Number.isFinite(v)) { nfCount++; return null; }
  return hex(v);
}
const tx = v => (v == null ? null : Object.is(v, -0) ? '-0' : String(v));
// put a number (or an array of numbers) under key, with its twin
function put(o, k, v) {
  if (Array.isArray(v)) { o[k] = v.map(hx); o[k + 'Text'] = v.map(tx); }
  else { o[k] = hx(v); o[k + 'Text'] = tx(v); }
  return o;
}
// equal as the port compares: -0 = +0, NaN = NaN
const eq = (a, b) => a === b || (Number.isNaN(a) && Number.isNaN(b));
const eqArr = (a, b) => a.length === b.length && a.every((v, i) => eq(v, b[i]));

// ---------- the embedded recipe (wf45/ref.js, generalised) ----------

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
  if (lim) {
    const mn = lim.min || 0;
    const mx = lim.max || Infinity;
    z = Math.max(Math.min(mx, z), mn);
  }
  return z;
}
function isPct(v) { return typeof v === 'string' && /%$/.test(v.trim()); }

// st: {dr, vr, center, optZoom, zoom, limit, ratio, ns}
function refSetFromModel(st) { st.zoom = clampZ(st.optZoom || 1, st.limit) || 1; }
function refBuild(st) {
  const [dx, dy, dw, dh] = st.dr;
  const [vx, vy, vw, vh] = st.vr;
  const sx = vw / dw, sy = vh / dh;
  const rx = (-dx) * sx + vx;
  const ry = (-dy) * sy + vy;
  let det = sx * sy - 0 * 0;
  det = 1.0 / det;
  const ri0 = sy * det, ri3 = sx * det;
  const ri4 = (0 * ry - sy * rx) * det;
  const ri5 = (0 * rx - sx * ry) * det;
  const vcx = vx + vw / 2, vcy = vy + vh / 2;
  const z = st.zoom;
  let rcx = vcx, rcy = vcy;
  if (st.center) {
    const px = parsePos(st.center[0], dw, dx);
    const py = parsePos(st.center[1], dh, dy);
    rcx = sx * px + 0 * py + rx;
    rcy = 0 * px + sy * py + ry;
  }
  const roamX = vcx - z * rcx;
  const roamY = vcy - z * rcy;
  const osx = z * sx + 0 * 0;
  const osy = 0 * 0 + z * sy;
  const ox = z * rx + 0 * ry + roamX;
  const oy = 0 * rx + z * ry + roamY;
  // matrix.invert([osx, 0, 0, osy, ox, oy])
  let d2 = osx * osy - 0 * 0;
  d2 = 1.0 / d2;
  const inv = [osy * d2, -0 * d2, -0 * d2, osx * d2, (0 * oy - osy * ox) * d2, (0 * ox - osx * oy) * d2];
  // BoundingRect.applyTransform fast path of dataRect by [osx,0,0,osy,ox,oy]
  let X = dx * osx + ox, Y = dy * osy + oy, W = dw * osx, H = dh * osy;
  if (W < 0) { X += W; W = -W; }
  if (H < 0) { Y += H; H = -H; }
  return { sx, sy, rx, ry, ri0, ri3, ri4, ri5, vcx, vcy, z, roamX, roamY, osx, osy, ox, oy, inv, trigger: [X, Y, W, H] };
}
function refContain(b, x, y) {
  const [X, Y, W, H] = b.trigger;
  return x >= X && x <= X + W && y >= Y && y <= Y + H;
}
function refNodeScale(st, b) { return ((b.z - 1) * (st.ratio || 1) + 1) / (b.osx || 1); }
function toRoam(T, b) {
  return { sx: T.sx * b.ri0 + 0 * 0, sy: 0 * 0 + T.sy * b.ri3, x: T.sx * b.ri4 + 0 * b.ri5 + T.x, y: 0 * b.ri4 + T.sy * b.ri5 + T.y };
}
function refAction(st, p) {
  const b = refBuild(st);
  const SB1 = { x: b.ox, y: b.oy, sx: b.osx, sy: b.osy };
  const SB2 = toRoam(SB1, b);
  if (p.dx != null && p.dy != null) { SB1.x += p.dx; SB1.y += p.dy; }
  if (p.zoom != null) {
    const oldZ = SB2.sx;
    const newZ = clampZ(oldZ * p.zoom, st.limit);
    const k = newZ / oldZ;
    SB1.x -= (p.originX - SB1.x) * (k - 1);
    SB1.y -= (p.originY - SB1.y) * (k - 1);
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
  const back = (i, v, o, w) => (w && isPct(last[i]) ? ((v - o) / w * 100) + '%' : v);
  st.center = last ? [back(0, d0, dx, dw), back(1, d1, dy, dh)] : [d0, d1];
  st.optZoom = zoom;
  refSetFromModel(st);
  if (p.zoom != null) st.ns = refNodeScale(st, refBuild(st));
}

// the roam option as upstream reads it from the option JSON
const has = (o, k) => o != null && o[k] != null;
function optionSeries(option) { return Array.isArray(option.series) ? option.series : [option.series]; }
function refReadModel(option, si) {
  const s = optionSeries(option)[si];
  return {
    center: has(s, 'center') ? s.center : has(option, 'center') ? option.center : null,
    limit: has(s, 'scaleLimit') ? s.scaleLimit : has(option, 'scaleLimit') ? option.scaleLimit : null,
    optZoom: has(s, 'zoom') ? s.zoom : 1,
    ratio: has(s, 'nodeScaleRatio') ? s.nodeScaleRatio : 0.6,
    roam: 'roam' in s ? (s.roam == null ? true : s.roam) : false,
    global: s.roamTrigger === 'global',
    z: has(s, 'z') ? s.z : 2,
    zlevel: has(s, 'zlevel') ? s.zlevel : 0,
    draggable: !!s.draggable,
  };
}
const panMode = r => r === true || r === 'move' || r === 'pan';
const zoomMode = r => r === true || r === 'scale' || r === 'zoom';

// ---------- the live chart ----------

function mk(W, H) {
  rngState = SEED;
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function zrDispatch(chart, name, extra) { chart.getZr().handler.dispatch(name, zev(extra)); }
function graphSeries(chart) {
  const out = [];
  chart.getModel().eachSeriesByType('graph', s => out.push(s));
  return out;
}

function classifyCentre(c) {
  if (c == null) return null;
  must(Array.isArray(c), 'a centre that is not an array: ' + JSON.stringify(c));
  return [0, 1].map(i => {
    const v = c[i];
    if (v == null) return { kind: 'null' };
    if (typeof v === 'number') return { kind: 'num', v };
    if (typeof v === 'string') {
      if (isPct(v)) {
        const n = parseFloat(v);
        must(String(n) + '%' === v, 'a percent centre that is not canonical: ' + JSON.stringify(v));
        return { kind: 'pct', v: n, str: v };
      }
      if (['center', 'middle', 'left', 'top', 'right', 'bottom'].includes(v)) return { kind: 'kw', str: v };
      return { kind: 'str', v: parseFloat(v), str: v };
    }
    throw new OracleError('a centre dim of type ' + typeof v);
  });
}
const sameCentre = (a, b) => JSON.stringify(a, (k, v) => (typeof v === 'number' && Number.isNaN(v) ? 'NaN' : v))
  === JSON.stringify(b, (k, v) => (typeof v === 'number' && Number.isNaN(v) ? 'NaN' : v));

function trArr(m) { return [m[4], m[5]]; }
function snapArrow(sym) {
  if (!sym) return null;
  return { x: sym.x, y: sym.y, scale: sym.scaleX, rotation: sym.rotation, px: trArr(sym.getComputedTransform()) };
}
function snapPathOf(line) {
  const pts = [];
  const rec = (...a) => { pts.push(a.slice(0, 2)); };
  line.buildPath({ moveTo: rec, lineTo: rec, quadraticCurveTo(x1, y1, x, y) { pts.push([x1, y1], [x, y]); },
    bezierCurveTo(a, b, c, d, x, y) { pts.push([a, b], [c, d], [x, y]); }, closePath() {}, rect() {}, arc() {} }, line.shape);
  return pts;
}

// one series' plain snapshot (numbers as numbers)
function snapSeries(chart, s, probes, withSnap, dragged) {
  const cs = s.coordinateSystem;
  const mo = cs.mtOverall;
  const dr = [cs.dataRect.x, cs.dataRect.y, cs.dataRect.width, cs.dataRect.height];
  let X = dr[0] * mo[0] + mo[4], Y = dr[1] * mo[3] + mo[5], W = dr[2] * mo[0], H = dr[3] * mo[3];
  if (W < 0) { X += W; W = -W; }
  if (H < 0) { Y += H; H = -H; }
  const trigger = [X, Y, W, H];
  const contain = probes.map(([x, y]) => (cs.containPoint([x, y]) ? '1' : '0')).join('');
  let edgeProbes = [];
  if (trigger.every(Number.isFinite) && W > 0 && H > 0) {
    const mx = X + W / 2, my = Y + H / 2, R = X + W, B = Y + H;
    edgeProbes = [[X, my], [nextDown(X), my], [R, my], [nextUp(R), my],
      [mx, Y], [mx, nextDown(Y)], [mx, B], [mx, nextUp(B)]].map(([x, y]) => [x, y, cs.containPoint([x, y]) ? 1 : 0]);
  }
  const T = cs.trans;
  const ratio = s.getShallow('nodeScaleRatio', true);
  const d = s.getData();
  const nodes = [];
  let nodeScale = null;
  for (let i = 0; i < d.count(); i++) {
    const el = d.getItemGraphicEl(i);
    const lay = d.getItemLayout(i);
    if (!el || !lay) { nodes.push(null); continue; }
    if (!dragged.includes(i)) {
      if (nodeScale === null) nodeScale = el.scaleX;
      must(el.scaleX === nodeScale && el.scaleY === nodeScale, 'node elements disagree on their scale at ' + i);
    }
    const g = el.getComputedTransform();
    const pth = el.childAt(0);
    const pg = pth.getComputedTransform();
    const lab = pth.getTextContent && pth.getTextContent();
    let label = null;
    if (lab && !lab.ignore && lab.transform) {
      // the alignment zrender draws with (Text.ts: style, else the host's default, else left/top)
      const ds = lab._defaultStyle || {};
      label = { x: lab.transform[4], y: lab.transform[5], align: lab.style.align || ds.align || 'left',
        vAlign: lab.style.verticalAlign || ds.verticalAlign || 'top' };
    }
    let size = d.getItemVisual(i, 'symbolSize');
    if (!Array.isArray(size)) size = [size, size];
    nodes.push({ layout: [lay[0], lay[1]], px: [g[4], g[5]], half: [pg[0], pg[3]], label, size: [+size[0], +size[1]] });
  }
  const e = s.getEdgeData();
  const edges = [];
  for (let i = 0; i < e.count(); i++) {
    const el = e.getItemGraphicEl(i);
    if (!el) { edges.push(null); continue; }
    const line = el.childOfName('line');
    const sh = line.shape;
    const lab = el.getTextContent && el.getTextContent();
    const ls = line.style.strokeNoScale ? line.getLineScale() : 1;
    const rec = {
      shape: [sh.x1, sh.y1, sh.x2, sh.y2],
      cp: isNaN(+sh.cpx1) || isNaN(+sh.cpy1) ? null : [sh.cpx1, sh.cpy1], // LinePath's straight test
      pixelEnds: cs.dataToPoint([sh.x1, sh.y1]).concat(cs.dataToPoint([sh.x2, sh.y2])),
      fromArrow: snapArrow(el.childOfName('fromSymbol')),
      toArrow: snapArrow(el.childOfName('toSymbol')),
      label: lab && !lab.ignore && lab.transform ? { px: trArr(lab.transform) } : null,
      lineWidthLocal: ls ? (line.style.lineWidth || 0) / ls : 0,
    };
    if (withSnap) rec.snapPath = snapPathOf(line);
    edges.push(rec);
  }
  return {
    index: s.seriesIndex, dr,
    vr: [cs.viewRect.x, cs.viewRect.y, cs.viewRect.width, cs.viewRect.height],
    raw: [T[0].scaleX, T[0].scaleY, T[0].x, T[0].y],
    rawInv: [cs.mtRawInv[0], cs.mtRawInv[3], cs.mtRawInv[4], cs.mtRawInv[5]],
    roam: [T[1].x, T[1].y, T[1].scaleX],
    overall: [T[2].scaleX, T[2].scaleY, T[2].x, T[2].y],
    overallInv: Array.from(cs.mtOverallInv),
    trigger, contain, edgeProbes,
    center: classifyCentre(s.getShallow('center')),
    zoom: s.getShallow('zoom'), csZoom: cs.zoom,
    nodeScale,
    nodeScaleIfRecomputed: ((cs.zoom - 1) * (ratio || 1) + 1) / (T[2].scaleX || 1),
    nodes, edges,
  };
}

// the JSON of one series snapshot
function encSeries(p) {
  const o = { index: p.index };
  put(o, 'dataRect', p.dr); put(o, 'viewRect', p.vr); put(o, 'raw', p.raw); put(o, 'rawInv', p.rawInv);
  put(o, 'roam', p.roam); put(o, 'overall', p.overall); put(o, 'overallInv', p.overallInv); put(o, 'trigger', p.trigger);
  o.contain = p.contain;
  o.edgeProbes = p.edgeProbes.map(([x, y, b]) => [hx(x), hx(y), b]);
  o.center = p.center && p.center.map(c => {
    const r = { kind: c.kind };
    if ('v' in c) put(r, 'v', c.v);
    if ('str' in c) r.str = c.str;
    return r;
  });
  put(o, 'zoom', p.zoom); put(o, 'csZoom', p.csZoom);
  put(o, 'nodeScale', p.nodeScale); put(o, 'nodeScaleIfRecomputed', p.nodeScaleIfRecomputed);
  o.nodes = p.nodes.map(n => {
    if (!n) return null;
    const r = {};
    put(r, 'layout', n.layout); put(r, 'px', n.px); put(r, 'half', n.half);
    r.label = n.label ? Object.assign(put(put({}, 'x', n.label.x), 'y', n.label.y), { align: n.label.align, vAlign: n.label.vAlign }) : null;
    return r;
  });
  const arrow = a => (a ? put(put(put(put(put({}, 'x', a.x), 'y', a.y), 'scale', a.scale), 'rotation', a.rotation), 'px', a.px) : null);
  o.edges = p.edges.map(e => {
    if (!e) return null;
    const r = {};
    put(r, 'shape', e.shape);
    if (e.cp) put(r, 'cp', e.cp); else { r.cp = null; r.cpText = null; }
    put(r, 'pixelEnds', e.pixelEnds);
    r.fromArrow = arrow(e.fromArrow);
    r.toArrow = arrow(e.toArrow);
    r.label = e.label ? put({}, 'px', e.label.px) : null;
    put(r, 'lineWidthLocal', e.lineWidthLocal);
    if (e.snapPath) { r.snapPath = e.snapPath.map(q => q.map(hx)); r.snapPathText = e.snapPath.map(q => q.map(tx)); }
    return r;
  });
  return o;
}
function encEvent(ev) {
  const o = { series: ev.series };
  if (ev.zoom != null) { put(o, 'zoom', ev.zoom); put(o, 'originX', ev.originX); put(o, 'originY', ev.originY); }
  else { put(o, 'dx', ev.dx); put(o, 'dy', ev.dy); }
  return o;
}
function encStep(st) {
  if (st.action) {
    const o = {};
    for (const k of ['dx', 'dy', 'zoom', 'originX', 'originY']) if (st.action[k] != null) put(o, k, st.action[k]);
    if (st.action.seriesIndex != null) o.seriesIndex = st.action.seriesIndex;
    return { action: o };
  }
  if (st.drag) return { drag: { button: st.drag.button, up: st.drag.up, path: st.drag.path } };
  return st;
}

// ---------- running a case ----------

function applyGesture(chart, step) {
  if (step.wheel) {
    zrDispatch(chart, 'mousewheel', { zrX: step.wheel.x, zrY: step.wheel.y, zrDelta: step.wheel.delta / 120 });
    return;
  }
  const d = step.drag;
  const pts = d.path;
  let i0 = 0;
  if (d.button) { zrDispatch(chart, 'mousedown', { zrX: pts[0][0], zrY: pts[0][1], which: d.button }); i0 = 1; }
  for (let i = i0; i < pts.length; i++) zrDispatch(chart, 'mousemove', { zrX: pts[i][0], zrY: pts[i][1] });
  const last = pts[pts.length - 1];
  if (d.up) zrDispatch(chart, 'mouseup', { zrX: last[0], zrY: last[1], which: d.up });
}

// Drive the case. `replay` (self-check b) dispatches recorded events in place
// of the gestures. Returns the plain snapshots and the events per state.
function drive(c, replay) {
  const chart = mk(c.W, c.H);
  const states = [];
  let evBuf = [];
  try {
    chart.setOption(c.option);
    const idOf = () => { const m = {}; graphSeries(chart).forEach(s => { m[s.id] = s.seriesIndex; }); return m; };
    chart.on('graphroam', p => {
      const ids = idOf();
      // a dispatched action echoes here too, untargeted; only gesture steps keep events
      const ev = { series: p.seriesId in ids ? ids[p.seriesId] : null };
      if (p.zoom != null) Object.assign(ev, { zoom: p.zoom, originX: p.originX, originY: p.originY });
      else Object.assign(ev, { dx: p.dx, dy: p.dy });
      evBuf.push(ev);
    });
    let W = c.W, H = c.H;
    const snap = (events) => {
      chart.renderToSVGString();
      states.push({ W, H, events, series: graphSeries(chart).map(s => snapSeries(chart, s, c.probes, !!c.snap, c.dragsNode || [])) });
    };
    snap([]);
    c.steps.forEach((st, k) => {
      evBuf = [];
      if (st.action) chart.dispatchAction(Object.assign({ type: 'graphRoam' }, st.action));
      else if (st.wheel || st.drag) {
        if (replay) {
          for (const ev of replay[k + 1]) {
            const q = { type: 'graphRoam', seriesIndex: ev.series };
            if (ev.zoom != null) Object.assign(q, { zoom: ev.zoom, originX: ev.originX, originY: ev.originY });
            else Object.assign(q, { dx: ev.dx, dy: ev.dy });
            chart.dispatchAction(q);
          }
        } else applyGesture(chart, st);
      } else if (st.resize) { [W, H] = st.resize; chart.resize({ width: W, height: H }); }
      else if (st.relayout) chart.setOption({ series: optionSeries(c.option).map(() => ({})) });
      else if (st.reset) chart.setOption(st.reset, true);
      else throw new OracleError('an unknown step ' + JSON.stringify(st));
      if ((st.wheel || st.drag) && !replay) must(evBuf.every(ev => ev.series !== null), 'a gesture event for an unknown series');
      snap(st.wheel || st.drag ? (replay ? replay[k + 1] : evBuf.slice()) : []);
    });
  } finally {
    chart.dispose();
  }
  return states;
}

// self-check a: the recipe, step by step, against the snapshots
function checkRecipe(c, states) {
  const fails = [];
  const fail = (k, si, field, lib, ref) => {
    fails.push('state ' + k + ' series ' + si + ' ' + field + ': upstream ' + JSON.stringify(lib) + ', recipe ' + JSON.stringify(ref));
  };
  let option = c.option;
  let model = optionSeries(option).map((_, si) => refReadModel(option, si));
  const sts = [];
  const init = (k) => {
    states[k].series.forEach((p, si) => {
      const m = model[si];
      const st = sts[si] = { dr: p.dr, vr: p.vr, center: m.center, optZoom: m.optZoom, limit: m.limit, ratio: m.ratio };
      refSetFromModel(st);
      st.ns = refNodeScale(st, refBuild(st));
    });
  };
  const rerender = (k) => {
    states[k].series.forEach((p, si) => {
      const st = sts[si];
      st.dr = p.dr; st.vr = p.vr;
      refSetFromModel(st);
      st.ns = refNodeScale(st, refBuild(st));
    });
  };
  const compare = (k) => {
    states[k].series.forEach((p, si) => {
      const st = sts[si];
      const b = refBuild(st);
      const chk = (field, lib, ref) => {
        const ok = Array.isArray(lib) ? Array.isArray(ref) && eqArr(lib, ref) : eq(lib, ref);
        if (!ok) fail(k, si, field, lib, ref);
      };
      chk('raw', p.raw, [b.sx, b.sy, b.rx, b.ry]);
      chk('rawInv', p.rawInv, [b.ri0, b.ri3, b.ri4, b.ri5]);
      chk('roam', p.roam, [b.roamX, b.roamY, b.z]);
      chk('overall', p.overall, [b.osx, b.osy, b.ox, b.oy]);
      chk('overallInv', p.overallInv, b.inv);
      chk('trigger', p.trigger, b.trigger);
      const cont = c.probes.map(([x, y]) => (refContain(b, x, y) ? '1' : '0')).join('');
      if (cont !== p.contain) fail(k, si, 'contain', p.contain, cont);
      p.edgeProbes.forEach(([x, y, v], j) => { if ((refContain(b, x, y) ? 1 : 0) !== v) fail(k, si, 'edgeProbe ' + j, v, 1 - v); });
      if (!sameCentre(p.center, classifyCentre(st.center))) fail(k, si, 'center', p.center, classifyCentre(st.center));
      chk('zoom', p.zoom, st.optZoom);
      chk('csZoom', p.csZoom, b.z);
      chk('nodeScaleIfRecomputed', p.nodeScaleIfRecomputed, refNodeScale(st, b));
      if (p.nodeScale !== null) chk('nodeScale', p.nodeScale, st.ns);
      p.nodes.forEach((n, i) => {
        if (!n || (c.dragsNode || []).includes(i)) return;
        chk('node ' + i + ' px', n.px, [b.osx * n.layout[0] + 0 * n.layout[1] + b.ox, 0 * n.layout[0] + b.osy * n.layout[1] + b.oy]);
        chk('node ' + i + ' half', n.half, [(b.osx * st.ns) * (n.size[0] / 2), (b.osy * st.ns) * (n.size[1] / 2)]);
      });
      p.edges.forEach((e, i) => {
        if (!e) return;
        const s = e.shape;
        chk('edge ' + i + ' pixelEnds', e.pixelEnds, [b.osx * s[0] + 0 * s[1] + b.ox, 0 * s[0] + b.osy * s[1] + b.oy,
          b.osx * s[2] + 0 * s[3] + b.ox, 0 * s[2] + b.osy * s[3] + b.oy]);
      });
    });
  };
  // the pointer layer
  const armed = [];
  const last = [];
  const order = (pred) => model.map((m, si) => ({ m, si })).filter(({ m }) => pred(m.roam))
    .sort((a, b) => (b.m.zlevel - a.m.zlevel) || (b.m.z - a.m.z) || (a.si - b.si)).map(o => o.si);
  const onDraggable = (k, x, y) => states[k].series.some((p, si) => model[si].draggable
    && p.nodes.some(n => n && Math.hypot(x - n.px[0], y - n.px[1]) <= n.half[0]));
  const inArea = (si, x, y) => model[si].global || refContain(refBuild(sts[si]), x, y);
  const predict = (k, step) => {
    const evs = [];
    const emit = (si, p) => { evs.push(Object.assign({ series: si }, p)); refAction(sts[si], p); };
    if (step.wheel) {
      const d = step.wheel.delta / 120;
      if (d !== 0) {
        const a = Math.abs(d);
        const f = a > 3 ? 1.4 : a > 1 ? 1.2 : 1.1;
        const zoom = d > 0 ? f : 1 / f;
        for (const si of order(zoomMode)) {
          if (inArea(si, step.wheel.x, step.wheel.y)) { emit(si, { zoom, originX: step.wheel.x, originY: step.wheel.y }); break; }
        }
      }
      return evs;
    }
    const dg = step.drag;
    const pts = dg.path;
    let i0 = 0;
    if (dg.button) {
      i0 = 1;
      const [x, y] = pts[0];
      if (dg.button === 1 && !onDraggable(k, x, y)) {
        for (const si of order(panMode)) if (inArea(si, x, y)) { armed[si] = true; last[si] = [x, y]; }
      }
    }
    for (let i = i0; i < pts.length; i++) {
      const [x, y] = pts[i];
      for (const si of order(panMode)) {
        if (!armed[si]) continue;
        const p = { dx: x - last[si][0], dy: y - last[si][1] };
        last[si] = [x, y];
        emit(si, p);
        break;
      }
    }
    if (dg.up === 1) model.forEach((_, si) => { armed[si] = false; });
    return evs;
  };
  init(0);
  compare(0);
  c.steps.forEach((step, j) => {
    const k = j + 1;
    if (step.action) {
      const p = step.action;
      sts.forEach((st, si) => { if (p.seriesIndex == null || p.seriesIndex === si) refAction(st, p); });
    } else if (step.wheel || step.drag) {
      const evs = predict(j, step);
      const lib = states[k].events;
      if (JSON.stringify(evs) !== JSON.stringify(lib)) fail(k, '-', 'events', lib, evs);
    } else if (step.resize || step.relayout) rerender(k);
    else if (step.reset) {
      option = step.reset;
      model = optionSeries(option).map((_, si) => refReadModel(option, si));
      armed.length = 0;
      init(k);
    }
    compare(k);
  });
  return fails;
}

// discriminates, per case
function discriminate(c, states) {
  const d = { nonUniformRaw: 0, zoomDrift: 0, staleScale: 0, pctCentre: 0, ringRelaid: 0, triggerShrunk: 0, clampLanded: 0 };
  let option = c.option;
  let limits = optionSeries(option).map((_, si) => refReadModel(option, si).limit);
  let nominal = states[0].series.map(p => p.csZoom);
  states.forEach((stt, k) => {
    const step = k ? c.steps[k - 1] : null;
    if (step && step.reset) {
      option = step.reset;
      limits = optionSeries(option).map((_, si) => refReadModel(option, si).limit);
      nominal = stt.series.map(p => p.csZoom);
    }
    let zoomed = [];
    if (step && step.action && step.action.zoom != null) {
      stt.series.forEach((p, si) => { if (step.action.seriesIndex == null || step.action.seriesIndex === si) zoomed.push([si, step.action.zoom]); });
    }
    if (step && (step.wheel || step.drag)) zoomed = stt.events.filter(e => e.zoom != null).map(e => [e.series, e.zoom]);
    zoomed.forEach(([si, z]) => { nominal[si] = clampZ(nominal[si] * z, limits[si]); });
    stt.series.forEach((p, si) => {
      if (Math.abs(p.raw[0] / p.raw[1] - 1) > 1e-3) d.nonUniformRaw++;
      if (!eq(p.csZoom, nominal[si])) d.zoomDrift++;
      if (p.nodeScale !== null && !eq(p.nodeScale, p.nodeScaleIfRecomputed)) d.staleScale++;
      if (p.center && p.center.some(x => x.kind === 'pct')) d.pctCentre++;
      if (c.ring && step && (step.relayout || step.resize)) {
        const prev = states[k - 1].series[si];
        if (p.nodes.some((n, i) => n && prev.nodes[i] && !eqArr(n.layout, prev.nodes[i].layout))) d.ringRelaid++;
      }
      const [vx, vy, vw, vh] = p.vr;
      c.probes.forEach(([x, y], j) => {
        if (x >= vx && x <= vx + vw && y >= vy && y <= vy + vh && p.contain[j] === '0') d.triggerShrunk++;
      });
      const lim = limits[si];
      if (lim && zoomed.some(([s]) => s === si) && (p.csZoom === (lim.min || 0) || p.csZoom === (lim.max || Infinity))) d.clampLanded++;
    });
  });
  return d;
}

// ---------- the cases ----------

const TRI = [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 30 }, { name: 'c', x: 40, y: 90 }];
const TRI_LINKS = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }];
const BOX = { left: 50, top: 40, width: 300, height: 100 }; // raw sx 3, sy 1.111
function graph(extra, root) {
  return Object.assign({ animation: false }, root || {}, { series: [Object.assign({ type: 'graph', layout: 'none', roam: true,
    symbolSize: 20, data: TRI, links: TRI_LINKS }, extra)] });
}
const A = (dx, dy) => ({ action: { dx, dy } });
const Z = (zoom, originX, originY, more) => ({ action: Object.assign({ zoom, originX, originY }, more || {}) });
const WH = (x, y, delta) => ({ wheel: { x, y, delta } });
const DR = (button, path, up) => ({ drag: { button, up: up == null ? button : up, path } });

const cases = [];
function add(group, name, option, steps, flags) {
  cases.push(Object.assign({ group, name, W: 400, H: 300, option, steps: steps || [] }, flags || {}));
}

// 1. static options, each on the plain base and on a non-uniform box, then a
//    pan and a zoom so the write-back of each centre kind is on record
const G1STEPS = [A(7, -3), Z(1.2, 180, 130)];
const g1 = [
  ['zoom 2.5', { zoom: 2.5 }],
  ['an absolute centre', { center: [30, 60] }],
  ['a percent centre', { center: ['25%', '75%'] }],
  ['a keyword centre, right top', { center: ['right', 'top'] }],
  ['a keyword centre, center middle', { center: ['center', 'middle'] }],
  ['a keyword centre, left bottom', { center: ['left', 'bottom'] }],
  ['a mixed centre, number and percent', { center: [30, '75%'] }],
  ['a centre of numeric strings', { center: ['30', '40'] }],
  ['zoom 2.5 about a percent centre', { zoom: 2.5, center: ['25%', '75%'] }],
  ['scaleLimit 0.5..2 clamps zoom 5 to 2', { zoom: 5, scaleLimit: { min: 0.5, max: 2 } }],
  ['scaleLimit 0..0 is no limit', { zoom: 3, scaleLimit: { min: 0, max: 0 } }],
  ['zoom 0 is zoom 1', { zoom: 0 }],
  ['nodeScaleRatio 0 behaves as 1, zoom 2', { zoom: 2, nodeScaleRatio: 0 }],
  ['nodeScaleRatio 0.6, zoom 2', { zoom: 2, nodeScaleRatio: 0.6 }],
  ['nodeScaleRatio 2, zoom 2', { zoom: 2, nodeScaleRatio: 2 }],
  ['a root centre climbs', {}, { center: [30, 60] }],
  ['a root scaleLimit climbs', { zoom: 5 }, { scaleLimit: { min: 0.5, max: 2 } }],
  ['a root zoom is ignored', {}, { zoom: 3 }],
  ['a root nodeScaleRatio is ignored, zoom 2', { zoom: 2 }, { nodeScaleRatio: 2 }],
];
for (const [base, bx] of [['plain', {}], ['box 300x100', BOX]]) {
  for (const [n, s, r] of g1) add(1, 'static, ' + base + ': ' + n, graph(Object.assign({}, bx, s), r), G1STEPS);
  add(1, 'static, ' + base + ': roam null is on', graph(Object.assign({}, bx, { roam: null })),
    [WH(200, 90, 120), DR(1, [[200, 90], [210, 95]])], { gesture: true });
}
add(1, 'static, plain: a centre that is not a number makes the view NaN', graph({ center: ['abc', 5] }), [A(4, 2)], { nonFinite: true });
// A data rectangle whose corner is not the origin: a percentage centre is
// offset by that corner, on the way in and on the way back.
const SHIFTED = [{ name: 'a', x: 50, y: -20 }, { name: 'b', x: 150, y: 10 }, { name: 'c', x: 90, y: 70 }];
add(1, 'static, shifted data: a percentage centre is offset by the corner',
  graph({ data: SHIFTED, center: ['30%', '60%'] }), [A(6, -4), Z(1.2, 180, 140), A(-3, 2)]);
// A zoom of nought is one BEFORE the clamp: under a floor of a half it
// stays one.
add(1, 'static, plain: zoom 0 under a scaleLimit floor is one', graph({ zoom: 0, scaleLimit: { min: 0.5, max: 3 } }), [Z(1.4, 200, 150)]);

// 2. action sequences
const SEQ = [A(10, -5), Z(1.1, 100, 80), A(-3, 12), Z(1 / 1.1, 250, 40),
  { action: { dx: 2.5, dy: -1.25, zoom: 1.3, originX: 77.5, originY: 210.25 } }, Z(1.2, 0, 0), A(-40, -40), Z(1 / 1.2, 400, 300)];
add(2, 'sequence, plain: pan, zoom, pan and zoom together', graph({}), SEQ);
add(2, 'sequence, box 300x100: pan, zoom, pan and zoom together', graph(BOX), SEQ);
add(2, 'sequence: scaleLimit 0.5..2 lands on each limit', graph({ scaleLimit: { min: 0.5, max: 2 } }),
  [Z(1.4, 250, 120), Z(1.4, 250, 120), Z(1.4, 250, 120), A(5, 5), Z(1.4, 250, 120), Z(1 / 1.4, 250, 120),
    Z(1 / 1.4, 250, 120), Z(1 / 1.4, 250, 120), Z(1 / 1.4, 250, 120), Z(1 / 1.4, 250, 120), A(-5, 3), Z(1 / 1.4, 250, 120)]);
add(2, 'sequence: in and out by 1.1 drifts the zoom', graph({}),
  [Z(1.1, 123, 77), Z(1 / 1.1, 123, 77), Z(1.1, 123, 77), Z(1 / 1.1, 123, 77), A(3, 3), Z(1.1, 17, 250), Z(1 / 1.1, 17, 250)]);
add(2, 'sequence: a dx without a dy (and a dy without a dx) does not pan', graph({}),
  [{ action: { dx: 5 } }, { action: { dy: 7 } }, A(5, 0), { action: { dy: 4, zoom: 1.2, originX: 200, originY: 150 } }]);
add(2, 'sequence, box 300x100 with scaleLimit: pans and zooms past both limits', graph(Object.assign({ scaleLimit: { min: 0.8, max: 1.5 } }, BOX)),
  [Z(1.2, 200, 90), A(-13, 8), Z(1.2, 60, 60), Z(1.2, 330, 130), A(7.5, -2.25), Z(1 / 1.4, 200, 90), Z(1 / 1.4, 200, 90), A(1, 1)]);

// 3. percent centres round trip
add(3, 'percent centre round trip, plain', graph({ center: ['25%', '60%'] }), [A(10, -5), Z(1.1, 100, 80), A(-7, 3)]);
add(3, 'mixed centre round trip, box 300x100', graph(Object.assign({ center: [30, '60%'] }, BOX)), [A(10, -5), Z(1.1, 100, 80), A(-7, 3)]);
add(3, 'percent centre round trip with zoom 1.7', graph({ center: ['33%', '101%'], zoom: 1.7 }), [Z(1 / 1.2, 310, 20), A(-11, 6), Z(1.4, 5, 290)]);

// 4. the node scale stays stale across pans
{
  const steps = [Z(1.1, 100, 80)];
  for (let k = 0; k < 6; k++) steps.push(A(13 + k, -7 - k));
  steps.push({ relayout: true }, A(1, 1), Z(1.2, 200, 150));
  add(4, 'stale node scale: zoom, six pans, relayout', graph({ links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }],
    edgeSymbol: ['none', 'arrow'] }), steps);
}

// 5. resize after roam, then reset
for (const [n, s] of [['no centre', {}], ['a percent centre', { center: ['25%', '75%'] }]]) {
  const opt = graph(s);
  add(5, 'resize after roam, then reset: ' + n, opt,
    [A(30, 10), Z(1.5, 100, 100), { resize: [600, 300] }, A(5, 5), { resize: [333, 257] }, { reset: opt }, A(1, 2)]);
}

// 6. rings
const RING = [{ name: 'a', symbolSize: 40 }, { name: 'b' }, { name: 'c' }, { name: 'd', symbolSize: 30 }, { name: 'e' }];
const ringLinks = n => Array.from({ length: n }, (_, i) => ({ source: i, target: (i + 1) % n }));
const ring = extra => ({ animation: false, series: [Object.assign({ type: 'graph', layout: 'circular', symbolSize: 20, roam: true,
  data: RING, links: ringLinks(5) }, extra)] });
add(6, 'ring, unpositioned: roam zoom 2, then relayout and resize', ring({}),
  [Z(2, 200, 150), { relayout: true }, { resize: [401, 300] }, A(5, 5), { relayout: true }], { ring: true });
add(6, 'ring, unpositioned: static zoom 3', ring({ zoom: 3 }), [A(-9, 4), { relayout: true }], { ring: true });
{
  const pos = [{ name: 'a', x: 0, y: 0, symbolSize: 40 }, { name: 'b', x: 10, y: 0 }, { name: 'c', x: 10, y: 10 }, { name: 'd', x: 0, y: 10 }];
  const pring = extra => ({ animation: false, series: [Object.assign({ type: 'graph', layout: 'circular', symbolSize: 20, roam: true,
    data: pos, links: ringLinks(4) }, extra)] });
  cases.push({ group: 6, name: 'ring, positioned: roam zoom 2, then relayout', W: 600, H: 400, option: pring({}),
    steps: [Z(2, 300, 200), { relayout: true }, A(3, -3), { relayout: true }], ring: true });
  cases.push({ group: 6, name: 'ring, positioned: static zoom 3', W: 600, H: 400, option: pring({ zoom: 3 }),
    steps: [{ relayout: true }, Z(1 / 1.2, 100, 100), { relayout: true }], ring: true });
}

// 7. force, roamed: the layout never moves
add(7, 'force, roamed: the layout is not re-run', {
  animation: false, series: [{ type: 'graph', layout: 'force', roam: true, symbolSize: 12, force: { layoutAnimation: false },
    data: [1, 2, 3, 4, 5, 6].map(v => ({ name: 'n' + v, value: v })), links: ringLinks(6).concat([{ source: 0, target: 3 }]) }] },
[Z(1.2, 200, 150), A(-17, 9), WH(210, 140, -240), DR(1, [[210, 140], [190, 150], [185, 160]]), Z(1.4, 30, 40)], { force: true, gesture: true });

// 8. arrows and edge labels, straight and curved, uniform view
add(8, 'arrows and labels, straight and curved', graph({
  data: [{ name: 'a', x: 0, y: 0, label: { show: true, position: 'right' } }, { name: 'b', x: 100, y: 30, label: { show: true, position: 'top' } },
    { name: 'c', x: 40, y: 90, label: { show: true } }],
  links: [{ source: 'a', target: 'b', label: { show: true } }, { source: 'b', target: 'c', lineStyle: { curveness: 0.3 }, label: { show: true } },
    { source: 'c', target: 'a' }],
  edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: [6, 10], itemStyle: { borderWidth: 2, borderColor: '#000' } }),
[Z(2, 200, 150), A(7, 3), Z(1 / 1.4, 150, 100), A(-20, 15), { relayout: true }]);
// The series-level label -- the only form the port reads -- off the scaled
// symbol's box, through a zoom, a pan and a relayout, on a uniform and on a
// non-uniform view. NO BORDER: upstream widens a stroked host's box by the
// stroke before it places the label, which the port's label pass does not
// do for any series -- a separate matter from the roam.
add(8, 'series labels right, through the roam', graph({
  label: { show: true, position: 'right' } }),
[Z(2, 200, 150), A(7, 3), Z(1 / 1.4, 150, 100), { relayout: true }]);
add(8, 'series labels top, non-uniform view', graph({
  left: 50, top: 40, width: 300, height: 100,
  label: { show: true, position: 'top' } }),
[Z(2, 200, 90), A(-5, 4), { relayout: true }]);

// 9. gestures
const gest = (name, option, steps, flags) => add(9, name, option, steps, Object.assign({ gesture: true }, flags || {}));
gest('wheel: each delta', graph({}),
  [WH(200, 150, 120), WH(200, 150, -120), WH(250, 120, 240), WH(250, 120, -240), WH(180, 90, 360), WH(180, 90, 480),
    WH(100, 60, 30), WH(100, 60, -30), WH(200, 150, 0), WH(300, 250, -480), WH(301, 249, -360)]);
gest('wheel outside the trigger rect, then inside', graph({}), [WH(20, 20, 120), WH(200, 150, 120), WH(399, 299, -120)]);
gest('roamTrigger global: wheel and drag outside the rect', graph({ roamTrigger: 'global' }),
  [WH(20, 20, 120), DR(1, [[10, 10], [25, 18]]), WH(399, 0, -240)]);
gest('left drag out of the canvas to negative coordinates', graph({}),
  [DR(1, [[200, 150], [215, 157], [216, 160], [-50, -40], [-60, -30]]), DR(0, [[300, 200]], 0)]);
gest('right and middle drags do nothing', graph({}), [DR(3, [[200, 150], [215, 157]]), DR(2, [[200, 150], [215, 157]])]);
gest('a right release mid-drag keeps the drag', graph({}),
  [DR(1, [[200, 150], [205, 150]], 3), DR(0, [[210, 152], [220, 160]], 1), DR(0, [[230, 170]], 0)]);
gest('after zoom 0.5 a press inside the view rect but outside the trigger does not pan', graph({}),
  [Z(0.5, 200, 150), DR(1, [[80, 40], [90, 50]]), WH(80, 40, 120), DR(1, [[200, 150], [210, 150]]), WH(200, 150, -120)]);
gest('a press on a node pans', graph({}), [DR(1, [[67, 30], [72, 35]]), DR(1, [[72, 35], [72, 35]])]);
gest('a press on a draggable node does not pan', graph({ draggable: true }),
  [DR(1, [[67, 30], [67, 30]]), DR(1, [[200, 150], [205, 152]])], { dragsNode: [0] });
for (const r of ['move', 'pan', 'scale', 'zoom', false]) {
  gest("roam '" + r + "'", graph({ roam: r }), [WH(200, 150, 120), DR(1, [[200, 150], [210, 150]]), A(5, 5)]);
}

// 10. two overlapping graphs
{
  const two = s1 => ({ animation: false, series: [
    { type: 'graph', layout: 'none', roam: true, symbolSize: 20, data: TRI, links: TRI_LINKS },
    Object.assign({ type: 'graph', layout: 'none', roam: true, symbolSize: 14,
      data: [{ name: 'p', x: 10, y: 10 }, { name: 'q', x: 60, y: 50 }, { name: 'r', x: 30, y: 25 }], links: [{ source: 'p', target: 'q' }] }, s1)] });
  const steps = [WH(200, 150, 120), DR(1, [[200, 150], [210, 155]]), A(3, 4), Z(1.1, 200, 150, { seriesIndex: 1 }), WH(120, 200, -240),
    DR(1, [[330, 60], [320, 70], [300, 100]])];
  add(10, 'two overlapping graphs, equal z: series 0 takes the gestures', two({}), steps, { gesture: true });
  add(10, 'two overlapping graphs, z 5 on series 1: series 1 takes them', two({ z: 5 }), steps, { gesture: true });
}

// 11. documentary
add(11, 'non-uniform view: stroke and arrows squash (D8, D9)', graph(Object.assign({
  links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }], edgeSymbol: ['none', 'arrow'], edgeSymbolSize: 10,
  lineStyle: { width: 3 }, itemStyle: { borderWidth: 2, borderColor: '#000' },
  data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 100, y: 90 }] }, BOX)),
[Z(2, 200, 90), A(4, 4)], { documentary: true, note: 'upstream keeps lineWidth/sqrt|det| local and scales arrows by 1/scaleX only; the port keeps constant pixels (D8, D9, kept)' });
add(11, 'axis-aligned edges: the data-space sub-pixel snap (D10)', graph({
  data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 0 }, { name: 'c', x: 100, y: 90 }], lineStyle: { width: 1 } }),
[Z(2, 200, 150)], { documentary: true, snap: true, note: 'snapPath is what zrender draws after subPixelOptimize in data units; the port does not snap (D10, out of batch)' });
add(11, 'negative zoom option (D13)', graph({ zoom: -2 }), [A(5, 5), Z(1.1, 200, 150)],
  { documentary: true, deferred: 'D13: decomposeTransform turns a negative scale into rotation pi; the port rejects zoom <= 0', note: 'the port rejects zoom <= 0' });
add(11, 'negative zoom action (D13)', graph({}), [Z(-1, 200, 150), A(3, 4)],
  { documentary: true, deferred: 'D13: a dispatched negative zoom comes back as zoom 1 with a moved centre; the port rejects zoom <= 0', note: 'the port rejects zoom <= 0' });

// ---------- run, check, write ----------

{
  const names = new Set();
  for (const c of cases) { must(!names.has(c.name), 'two cases named ' + c.name); names.add(c.name); }
}
for (const c of cases) {
  const xs = Array.from({ length: 11 }, (_, i) => Math.round(-0.1 * c.W + i * 0.12 * c.W));
  const ys = Array.from({ length: 9 }, (_, j) => Math.round(-0.1 * c.H + j * 0.15 * c.H));
  c.probes = [];
  for (const y of ys) for (const x of xs) c.probes.push([x, y]);
  c.probes.push([80, 40], [20, 20]);
}

const CHECKS = ['a', 'b', 'e'];
function generate() {
  const tally = { a: [0, 0], b: [0, 0], e: [0, 0] };
  const failed = [];
  const totals = { nonUniformRaw: 0, zoomDrift: 0, staleScale: 0, pctCentre: 0, ringRelaid: 0, triggerShrunk: 0, clampLanded: 0 };
  const recs = cases.map(c => {
    let states;
    try { states = drive(c, null); } catch (e) { if (e instanceof OracleError) e.message = c.name + ': ' + e.message; throw e; }
    const fails = { a: checkRecipe(c, states), b: [], e: [] };
    if (c.gesture) {
      const again = drive(c, states.map(s => s.events));
      const enc = ss => ss.map(s => JSON.stringify(s.series.map(encSeries)));
      const A1 = enc(states), A2 = enc(again);
      A1.forEach((s, k) => { if (s !== A2[k]) fails.b.push('state ' + k + ' differs when replayed as actions'); });
    }
    if (c.force) {
      const l0 = JSON.stringify(states[0].series.map(p => p.nodes.map(n => n && n.layout)));
      states.forEach((s, k) => { if (JSON.stringify(s.series.map(p => p.nodes.map(n => n && n.layout))) !== l0) fails.a.push('state ' + k + ': the force layout moved'); });
    }
    const disc = discriminate(c, states);
    const rec = { name: c.name, group: c.group, W: c.W, H: c.H, option: c.option, steps: c.steps.map(encStep), probes: c.probes };
    rec.gesture = !!c.gesture;
    rec.ring = !!c.ring;
    rec.force = !!c.force;
    rec.dragsNode = c.dragsNode || [];
    rec.states = states.map(s => {
      nfCount = 0;
      const o = { W: s.W, H: s.H, events: s.events.map(encEvent) };
      const ser = s.series.map(encSeries);
      o.nonFinite = nfCount;
      o.series = ser;
      return o;
    });
    const nf = rec.states.reduce((n, s) => n + s.nonFinite, 0);
    if (nf && !c.nonFinite) fails.e.push(nf + ' non-finite numbers in a case not declared nonFinite');
    if (!nf && c.nonFinite) fails.e.push('declared nonFinite, but every number is finite');
    rec.nonFinite = !!c.nonFinite;
    let miss = '';
    CHECKS.forEach(k => {
      if (k !== 'b' || c.gesture) tally[k][fails[k].length ? 1 : 0]++;
      if (fails[k].length) miss += (miss ? ' | ' : '') + 'self-check ' + k + ': ' + fails[k].slice(0, 3).join('; ')
        + (fails[k].length > 3 ? ' (+' + (fails[k].length - 3) + ' more)' : '');
    });
    if (miss && !c.deferred) failed.push(c.name + ': ' + miss);
    if (c.documentary) { rec.documentary = true; rec.note = c.note; } else rec.documentary = false;
    if (c.deferred) {
      rec.deferred = true;
      rec.why = c.deferred + (miss ? '; first differences: ' + miss : '; (no self-check failed)');
    } else rec.deferred = false;
    rec.discriminates = disc;
    if (!c.deferred && !c.documentary) Object.keys(totals).forEach(k => { totals[k] += disc[k]; });
    return rec;
  });
  return { out: { source: 'ECharts ' + echarts.version, seed: SEED, cases: recs }, tally, failed, totals };
}

// the compact writer of coord-affine.js: a value whose one-line JSON fits in
// LINE characters stays on one line (coord-affine uses 150; the records here
// are wider and 150 costs a sixth of the file in indentation)
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
    // short one-line items are packed several to a line
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

const { tally, failed, totals } = g1r;
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks (pass/cases): ' + CHECKS.map(k => k + ' ' + tally[k][0] + '/' + (tally[k][0] + tally[k][1])).join(', ')
  + ', d ' + (deterministic ? 'identical' : 'DIFFERENT'));
console.log('discriminates (compared cases): ' + JSON.stringify(totals));
const zeroDisc = Object.keys(totals).filter(k => totals[k] < 1);
if (zeroDisc.length) console.log('self-check c failed: no case bites ' + zeroDisc.join(', '));
const cs = g1r.out.cases;
const nDef = cs.filter(c => c.deferred).length;
const nDoc = cs.filter(c => c.documentary && !c.deferred).length;
const nStates = cs.reduce((n, c) => n + c.states.length, 0);
console.log((cs.length - nDef - nDoc) + ' compared + ' + nDoc + ' documentary + ' + nDef + ' deferred cases; ' + nStates + ' states; '
  + json1.length + ' bytes');
if (failed.length || zeroDisc.length || !deterministic) {
  if (process.env.ORACLE_REJECTS) fs.writeFileSync(process.env.ORACLE_REJECTS, json1);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
