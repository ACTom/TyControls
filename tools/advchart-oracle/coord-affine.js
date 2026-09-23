// Upstream's own answers for the cartesian coordinate arithmetic: the per-axis
// map (Axis.dataToCoord + the grid's toGlobalCoord), the affine fast path of
// Cartesian2D.dataToPoint (_transform, built from two per-axis calls) and its
// inverse, and what the marks, ticks, onZero lines and axis labels store from
// them.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, renders once to an SVG string, and
// reads the live objects. Every case is W x H with grid.outerBoundsMode 'none'
// unless it says otherwise, and W x H is odd so the rect is fractional, unless
// the case is marked integer.
//
// The recipes (batch 42 audit, S2-S8), in `fl()` = one IEEE double rounding,
// evaluated left to right:
//   P, per axis: e = inverse ? [wh, 0] : [0, wh] (wh = rect.width | height),
//     sum = e0 + e1; onBand: m = (e1 - e0) / count / 2, r = [e0 + m, e1 - m];
//     v' = parse(v) (time: Math.round; interval/log: null or '' -> NaN, else
//     Number; ordinal: Math.round); n = normalize(v') over mapping || effective
//     (log: log(v')/log(base) over the stored log extent `logExtent`);
//     c = linearMap(n, [0,1], r, clamp); global x = c + rect.x,
//     y = (sum - c) + rect.y.
//   A, affine: start = P(xm0, ym0), end = P(xm1, ym1) (P parses, so time
//     mapping ends are Math.round-ed), sx = (end.x - start.x) / xSpan,
//     tx = start.x - xm0 * sx (y the same); taken iff the matrix exists and
//     both values are != null and isFinite; clamp is ignored there.
//   B, axis labels: the label's local point (c, t), c = the local P coord,
//     t = labelOffset + labelDirection * margin, through the axis group
//     matrix [1,0,0,1,X,Y] (x) or [cos(pi/2),-1,1,cos(pi/2),X,Y] (y).
//
// Per case (a grid's fields sit at the case's top level when the chart has one
// grid; with more, they are under grids[], one object per grid):
//   name, group, W, H, option       the canvas and the option as run
//   integer, control, affine, fractional, pinsD4, pinsD5   case flags
//   deferred, why                   a self-check failed (or by design)
//   documentary, note               the rect is the grid-bounds oracle's
//                                   question (outerBounds shrink, containLabel)
//   discriminates                   counts that prove the case bites (below)
//   rect {x,y,width,height}         grid.getRect(), as stored (+ rectText)
//   axes[]                          x axes then y axes of the grid:
//     dim, index, type ('value','category','time','log'), position, inverse,
//     onBand, count (ordinal count or null), base (log base or null),
//     effective[2], mapping[2]|null, logExtent[2]|null (the log-space extent
//     normalize reads), extent[2] (axis.getExtent(), local px),
//     ticks[], tickCoords[] (getTicksCoords, GLOBAL px; on an onBand axis the
//     band edges, shifted by half a band and one more at the end),
//     splitLineShow (the splitLine.show option), splitLineTicks[],
//     splitLineCoords[] (getTicksCoords with the splitLine model, GLOBAL px:
//     every split line upstream builds, before subPixelOptimizeLine and before
//     showMinLine / showMaxLine drop the first / last; band-shifted by the
//     splitLine model's own alignWithLabel),
//     labels[] {tick, x, y, hidden?, transform, localRect} (the label element's
//     x, y: recipe B; transform: the six numbers of its computed transform,
//     or null; localRect: [x, y, width, height] of its text box with the
//     label's textMargin, local to transform -- both as the builder's
//     labelLayoutList holds them),
//     labelOffset, labelRotation (the first label element's rotation, the
//     same on every label of the axis; null without labels), layoutRotation
//     (innerTextLayout's rotation, remRadian(labelRotate - axis rotation),
//     the local rotation the anchor matrix is built with), align and
//     verticalAlign (the label text's), onZeroOf ('y0' or null), onZeroCoord (the pixel of the
//     other axis' 0, P) or null, startValue and valueAxisStart (P of it) for
//     the value axis of a bar or pictorialBar series, else null
//   transform[6]|null, invTransform[6]|null   cartesian._transform/_invTransform
//   area {x,y,width,height}         cartesian.getArea()
//   series[] { index, type, baseDim, offset?, size? (bars), items[],
//              linePoints?, areaLower?, symbols? }
//     items[] { values[2] (as handed to dataToPoint, x then y), point[2]
//               (cart.dataToPoint(values)), path ('affine'|'perAxis'),
//               field? (candlestick: open/close/lowest/highest),
//               stackStart? (stacked bars), class? ('drawn','hidden','none'),
//               layout? {x,y,width,height} (bars and pictorialBar, unclipped),
//               box? [l,t,r,b] (bars, the shape after the clip),
//               floor? (pictorialBar) }
//     linePoints  line: data.getLayout('points') (a Float32Array) as [x, y]
//                 pairs in data order, the double of each float32
//     areaLower   line with areaStyle: the view's stackedOnPoints, likewise
//     symbols     line: each symbol element's [x, y], or null (none drawn)
//   probes[] { kind, dim?, input[], output[], path?, inputString? }
//     dataToPoint       cart.dataToPoint(input); path 'affine' | 'perAxis'
//     dataToPointClamp  cart.dataToPoint(input, true); clamp only per axis
//     pointToData       cart.pointToData(input px); path 'inverse' | 'perAxis'
//     axisPointToData   Axis2D.pointToData(input px) of axis `dim` (per axis,
//                       what the axisPointer reads); output [value]
//     axisPointerPixel  toGlobalCoord(dataToCoord(input[0], true)) of `dim`
//     inputString       the first input was passed as a numeric string
//
// discriminates (per case, summed over grids):
//   compared           coordinates counted below
//   affineVsPerAxis    recorded dataToPoint coordinates on the affine path
//                      (items and non-clamp probes) where A != P
//   maxAffineShiftPx   the largest |A - P| among them (hex + Text)
//   portVsUpstream     coordinates where the port's formula today (Coord.pas
//                      DataToCoord: a + n*(b-a) between global edges, inverse
//                      as 1-n, band inset on global edges; labels L + p*len
//                      with p from the pxInit edges) != upstream: ticks,
//                      onZero, valueAxisStart, item points, non-clamp probe
//                      points, label anchors along the axis
//   logNormalize       log values whose upstream normalize (stored log extent)
//                      != Ln(v)/Ln(base) over Ln(pow ends)/Ln(base)
//   kills              (cases A-H only) per port mutant of the case's kill
//                      list, how many recorded numbers it moves:
//     linearMapVerbatimEnd  linearMap without its verbatim n === 1 -> r1
//     bandFromEdges         the bar band from |(x+w) - x| instead of w
//     pxInitFromEdges       containShape's pxInit from the raw rect's edges
//     shrinkFromEdges       outerBounds 'auto' fed W = (x+w)-x, H = (y+h)-y
//     noBorrowDefault       a lone horizontal key borrows no default (x = 0)
//     autoAsValue           left 'auto' counted as a value (x = 0)
//     cellCentre            a column at its band cell's centre, not coord
//     clipFromOriginal      the clip's width from the unclipped x
//   pins               (cases L only) per property the case pins, how many
//                      recorded numbers or labels show it (see the L cases)
//
// Self-checks (a case that fails any is recorded deferred with the reason and
// the run exits 1):
//   1 transcription: the recipe from rect, inverse, onBand, count and the
//     recorded extents reproduces extent, transform and invTransform bitwise,
//     every item point and dataToPoint probe through the per-call gate, and
//     every pointToData probe; the replay the mutants run on (every recorded
//     number with the recipe that predicts it) reproduces the record.
//   2 P reproduces every tick coord, onZeroCoord, valueAxisStart, area and the
//     axisPointToData / axisPointerPixel probes; P with fixOnBandTicksCoords
//     (the pushed far edge from the boundary tick) reproduces every split-line
//     coord and again every tick coord.
//   3 B reproduces every label element's x and y. And per label, from the
//     frame (cartesianAxisHelper.ts:57-106), the rotation (AxisBuilder.ts:
//     1369-1373) and zrender's matrix code: the element's rotation is
//     -atan2(M1, M0) of M = G * local(c, t, layoutRotation) and the same on
//     every label of the axis; its layoutRotation, align and verticalAlign are
//     innerTextLayout's (AxisBuilder.ts:592-621); the decomposed x, y are the
//     element's; the recorded transform is M decomposed and recomposed
//     (Transformable.ts:186-211, 303-347), bit for bit, and the element's own
//     computed transform.
//   4 line storage: points and stackedOnPoints are Float32Arrays, each is
//     Math.fround of the transcribed point, symbols sit on the points.
//   5 bars: the barGrid recipe reproduces every layout, the BarView clip
//     against getArea() every box; pictorialBar floors are the layout's edge.
//   6 discrimination: an affine case has affineVsPerAxis >= 1; a fractional
//     case portVsUpstream >= 1; a pinsD4 case maxAffineShiftPx > 1; a pinsD5
//     case logNormalize >= 1; a control case affineVsPerAxis = 0 and
//     portVsUpstream = 0; every mutant of a kill list moves >= 1 recorded
//     number (with the barGrid band/width/offset, containShape mapping and
//     rect transcriptions those mutants use reproducing upstream first);
//     every entry of a pins list bites >= 1 time.
//   7 builds: the production build (echarts.min.js) writes the same record.
//   8 determinism: run twice, diff the output (done outside the script).
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase). Non-finite numbers are the strings 'Infinity', '-Infinity',
// 'NaN'; a null input is null. The readable twins (xxxText) sit beside the
// case- and axis-level numbers and the probes; the twin of -0 is '-0'.
//
//   node tools/advchart-oracle/coord-affine.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD_PATH = DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js');
const PROD = require(PROD_PATH);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-coord-affine.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- number writing ----------

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
// finite -> hex; non-finite -> its name; null/undefined -> null
function num(v) {
  if (v == null) return null;
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return 'NaN';
  if (v === Infinity) return 'Infinity';
  if (v === -Infinity) return '-Infinity';
  return hex(v);
}
const text = v => (v == null ? null : Object.is(v, -0) ? '-0' : String(v));
const numArr = a => (a ? Array.from(a, num) : null);
const textArr = a => (a ? Array.from(a, text) : null);
const RECT = ['x', 'y', 'width', 'height'];
const plainRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const numRect = r => ({ x: num(r.x), y: num(r.y), width: num(r.width), height: num(r.height) });
const textRect = r => ({ x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) });
const clone = o => JSON.parse(JSON.stringify(o));
const same = (a, b) => Object.is(a, b);
const sameArr = (a, b) => (a == null && b == null) || (a != null && b != null && a.length === b.length
  && Array.from(a).every((v, i) => same(v, b[i])));
// a different value (NaN equals NaN, and -0 equals 0): what "moves" a pixel
const differs = (a, b) => !(a === b || (Number.isNaN(a) && Number.isNaN(b)));
const fround = Math.fround;

// The port mutants a case must make visible (self-check 6, `kills`): each flag
// changes one step of the transcription the way a port bug would. Empty while
// the recipe itself is checked.
let MUT = {};

// scale extent kinds and depth (scaleMapper.ts)
const EFFECTIVE = 0;
const MAPPING = 1;
const INNERMOST = 3;

// ---------- the upstream transcription (U) ----------
// Everything below reads only the recorded axis state (rect, inverse, onBand,
// count, base, effective, mapping, logExtent), never the live scale.

// number.ts:67-120
function linearMap(val, d0, d1, r0, r1, clamp, noVerbatimEnd) {
  const subDomain = d1 - d0;
  const subRange = r1 - r0;
  if (subDomain === 0) return subRange === 0 ? r0 : (r0 + r1) / 2;
  if (clamp) {
    if (subDomain > 0) {
      if (val <= d0) return r0;
      else if (val >= d1) return r1;
    } else {
      if (val >= d0) return r0;
      else if (val <= d1) return r1;
    }
  } else {
    if (val === d0) return r0;
    if (val === d1 && !noVerbatimEnd) return r1;
  }
  return (val - d0) / subDomain * subRange + r0;
}
// Interval.ts:117-142, Time.ts:271-274, Ordinal.ts:160-176 (numbers only)
function parseU(ar, v) {
  switch (ar.scaleType) {
    case 'time':
      if (typeof v === 'number') return Math.round(v);
      must(v == null, 'parseU: a non-number time value');
      return NaN;
    case 'ordinal':
      if (v == null) return NaN;
      must(typeof v === 'number', 'parseU: a non-number ordinal value');
      return Math.round(v);
    default:
      return v == null || v === '' ? NaN : Number(v);
  }
}
const logTick = (v, base) => Math.log(v) / Math.log(base); // helper.ts:175-185
const mapExtOf = ar => ar.mapping || ar.effective;
// scaleMapper.ts:425-431 (Log.ts:169-171 over the interval stub)
function normalizeU(ar, pv) {
  let val = pv;
  let e = mapExtOf(ar);
  if (ar.scaleType === 'log') {
    val = logTick(pv, ar.base);
    e = ar.logExtent;
  }
  if (e[1] === e[0]) return 0.5;
  return (val - e[0]) / (e[1] - e[0]);
}
// Grid.ts updateAxisExtentTransByGridRect: the local pixel extent
function extentU(ar) {
  return ar.inverse ? [ar.wh, 0] : [0, ar.wh];
}
// Axis.ts:274-283 makeExtentWithBands
function bandExtentU(ar) {
  const e = extentU(ar);
  if (ar.onBand) {
    const size = e[1] - e[0];
    const margin = size / ar.count / 2;
    e[0] += margin;
    e[1] -= margin;
  }
  return e;
}
// Axis.ts:139-143
function localU(ar, v, clamp) {
  const r = bandExtentU(ar);
  return linearMap(normalizeU(ar, parseU(ar, v)), 0, 1, r[0], r[1], clamp, MUT.noVerbatimEnd);
}
// Grid.ts:779-797
function toGlobalU(ar, c) {
  const e = extentU(ar);
  const sum = e[0] + e[1];
  return ar.dim === 'x' ? c + ar.gxy : sum - c + ar.gxy;
}
function toLocalU(ar, g) {
  const e = extentU(ar);
  const sum = e[0] + e[1];
  return ar.dim === 'x' ? g - ar.gxy : sum - g + ar.gxy;
}
const perAxisU = (ar, v, clamp) => toGlobalU(ar, localU(ar, v, clamp));
// Axis.ts:148-151 coordToData + the scales' scale()
function coordToDataU(ar, local, clamp) {
  const r = bandExtentU(ar);
  const t = linearMap(local, r[0], r[1], 0, 1, clamp);
  if (ar.scaleType === 'log') {
    const e = ar.logExtent;
    return Math.pow(ar.base, t * (e[1] - e[0]) + e[0]);
  }
  const e = mapExtOf(ar);
  const v = t * (e[1] - e[0]) + e[0];
  return ar.scaleType === 'ordinal' ? Math.round(v) : v;
}
// Cartesian2D.ts:58-88
function affineU(ax, ay) {
  const ok = a => a.scaleType === 'interval' || a.scaleType === 'time';
  if (!ok(ax) || !ok(ay)) return null;
  const xm = mapExtOf(ax);
  const ym = mapExtOf(ay);
  const start = [perAxisU(ax, xm[0]), perAxisU(ay, ym[0])];
  const end = [perAxisU(ax, xm[1]), perAxisU(ay, ym[1])];
  const xs = xm[1] - xm[0];
  const ys = ym[1] - ym[0];
  if (!xs || !ys) return null;
  const sx = (end[0] - start[0]) / xs;
  const sy = (end[1] - start[1]) / ys;
  return [sx, 0, 0, sy, start[0] - xm[0] * sx, start[1] - ym[0] * sy];
}
// zr matrix.ts:125-147
function invertU(a) {
  const aa = a[0], ac = a[2], atx = a[4], ab = a[1], ad = a[3], aty = a[5];
  let det = aa * ad - ab * ac;
  if (!det) return null;
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
const gateAffine = (M, xv, yv) => !!M && xv != null && isFinite(xv) && yv != null && isFinite(yv);
// Cartesian2D.ts:131-152; zr vector.ts:186-191
function dataToPointU(M, ax, ay, xv, yv, clamp) {
  if (gateAffine(M, xv, yv)) return [M[0] * xv + M[2] * yv + M[4], M[1] * xv + M[3] * yv + M[5]];
  return [perAxisU(ax, xv, clamp), perAxisU(ay, yv, clamp)];
}
// Cartesian2D.ts:171-184
function pointToDataU(Minv, ax, ay, p) {
  if (Minv) return [Minv[0] * p[0] + Minv[2] * p[1] + Minv[4], Minv[1] * p[0] + Minv[3] * p[1] + Minv[5]];
  return [coordToDataU(ax, toLocalU(ax, p[0])), coordToDataU(ay, toLocalU(ay, p[1]))];
}
// Cartesian2D.ts:194-205 from the per-axis global extents
function areaU(ax, ay) {
  const gx = extentU(ax).map(c => toGlobalU(ax, c));
  const gy = extentU(ay).map(c => toGlobalU(ay, c));
  const x = Math.min(gx[0], gx[1]) - 0;
  const y = Math.min(gy[0], gy[1]) - 0;
  return { x, y, width: Math.max(gx[0], gx[1]) - x + 0, height: Math.max(gy[0], gy[1]) - y + 0 };
}
// axisBand.ts calcBandWidth for a category axis (no statistic): px span / len
function categoryBandWidthU(ar) {
  const e = mapExtOf(ar);
  let len = (e[1] - e[0]) + (ar.onBand ? 1 : 0);
  if (len === 0) len = 1;
  const px = extentU(ar);
  return Math.abs(px[1] - px[0]) / len;
}
// Axis.ts getTicksCoords + fixOnBandTicksCoords: the global tick coordinates
function tickListU(r, tickValues, modified) {
  const bw = modified ? categoryBandWidthU(r) : 0;
  const out = [];
  let prev = null;
  tickValues.forEach((tv, i) => {
    let local;
    if (modified && i === tickValues.length - 1 && prev != null && tv === r.effective[1] + 1) local = prev + bw;
    else local = localU(r, tv) - (modified ? bw / 2 : 0);
    prev = local;
    out.push(toGlobalU(r, local));
  });
  return out;
}
// cartesianAxisHelper.ts:57-107 + AxisBuilder.ts:1565-1574: the label's x, y
function labelFrameU(ar, onZeroCoord) {
  const rb = [ar.rect.x, ar.rect.x + ar.rect.width, ar.rect.y, ar.rect.y + ar.rect.height];
  const idx = { left: 0, right: 1, top: 0, bottom: 1, onZero: 2 };
  const pb = ar.dim === 'x' ? [rb[2] - ar.offset, rb[3] + ar.offset] : [rb[0] - ar.offset, rb[1] + ar.offset];
  const onZero = onZeroCoord != null;
  if (onZero) pb[idx.onZero] = Math.max(Math.min(onZeroCoord, pb[1]), pb[0]);
  const pos = onZero ? 'onZero' : ar.position;
  const X = ar.dim === 'y' ? pb[idx[pos]] : rb[0];
  const Y = ar.dim === 'x' ? pb[idx[pos]] : rb[3];
  let dir = { top: -1, bottom: 1, left: -1, right: 1 }[ar.position];
  if (ar.labelInside) dir = -dir;
  const labelOffset = onZero ? pb[idx[ar.position]] - pb[idx.onZero] : 0;
  return { X, Y, labelOffset, t: labelOffset + dir * ar.margin };
}
const CT = Math.cos(Math.PI / 2);
function labelAnchorU(ar, frame, tickValue) {
  const c = localU(ar, tickValue);
  const t = frame.t;
  if (ar.dim === 'x') return [1 * c + 0 * t + frame.X, 0 * c + 1 * t + frame.Y];
  return [CT * c + 1 * t + frame.X, -1 * c + CT * t + frame.Y];
}
// zrender, operation for operation: matrix.ts:47-64 (mul), 83-105 (rotate,
// pivot [0,0]); Transformable.ts:7-11 (the 5e-5 test), 95-103 (needLocal),
// 108-147 (updateTransform), 186-211 (setLocalTransform, which the
// decomposeTransform of a parentless element ends in), 303-347
// (getLocalTransform, origin and anchor 0)
function zrMul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3], m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
function zrRotate(a, rad) {
  const aa = a[0], ac = a[2], atx = a[4], ab = a[1], ad = a[3], aty = a[5];
  const st = Math.sin(rad), ct = Math.cos(rad);
  return [aa * ct + ab * st, -aa * st + ab * ct, ac * ct + ad * st, -ac * st + ct * ad,
    ct * (atx - 0) + st * (aty - 0) + 0, ct * (aty - 0) - st * (atx - 0) + 0];
}
const zrNotAroundZero = v => v > 5e-5 || v < -5e-5;
const zrT = p => Object.assign({ x: 0, y: 0, rotation: 0, scaleX: 1, scaleY: 1, skewX: 0, skewY: 0 }, p);
function zrNeedLocal(t) {
  return zrNotAroundZero(t.rotation) || zrNotAroundZero(t.x) || zrNotAroundZero(t.y)
    || zrNotAroundZero(t.scaleX - 1) || zrNotAroundZero(t.scaleY - 1) || zrNotAroundZero(t.skewX) || zrNotAroundZero(t.skewY);
}
function zrLocal(t) {
  const skewX = t.skewX ? Math.tan(t.skewX) : 0;
  const skewY = t.skewY ? Math.tan(-t.skewY) : 0;
  let m = [t.scaleX, skewY * t.scaleX, skewX * t.scaleY, t.scaleY, 0, 0];
  if (t.rotation) m = zrRotate(m, t.rotation);
  m[4] += 0 + t.x;
  m[5] += 0 + t.y;
  return m;
}
// hadOne: the element already holds a transform array (reset to identity
// when it needs none and has no parent)
function zrUpdate(t, parentM, hadOne) {
  const nl = zrNeedLocal(t);
  if (!(nl || parentM)) return hadOne ? [1, 0, 0, 1, 0, 0] : null;
  const m = nl ? zrLocal(t) : [1, 0, 0, 1, 0, 0];
  if (parentM) return nl ? zrMul(parentM, m) : parentM.slice();
  return m;
}
function zrDecompose(m) {
  let sx = m[0] * m[0] + m[1] * m[1];
  let sy = m[2] * m[2] + m[3] * m[3];
  const rotation = Math.atan2(m[1], m[0]);
  const shearX = Math.PI / 2 + rotation - Math.atan2(m[3], m[2]);
  sy = Math.sqrt(sy) * Math.cos(shearX);
  sx = Math.sqrt(sx);
  return { skewX: shearX, skewY: 0, rotation: -rotation, x: +m[4], y: +m[5], scaleX: sx, scaleY: sy };
}
// number.ts:470-481
const remRadianU = r => { const pi2 = Math.PI * 2; return (r % pi2 + pi2) % pi2; };
const aroundZeroU = v => v > -1e-4 && v < 1e-4;
// AxisBuilder.ts:592-621
function innerTextLayoutU(axisRotation, textRotation, direction) {
  const rotationDiff = remRadianU(textRotation - axisRotation);
  let textAlign;
  let textVerticalAlign;
  if (aroundZeroU(rotationDiff)) {
    textVerticalAlign = direction > 0 ? 'top' : 'bottom';
    textAlign = 'center';
  } else if (aroundZeroU(rotationDiff - Math.PI)) {
    textVerticalAlign = direction > 0 ? 'bottom' : 'top';
    textAlign = 'center';
  } else {
    textVerticalAlign = 'middle';
    if (rotationDiff > 0 && rotationDiff < Math.PI) textAlign = direction > 0 ? 'right' : 'left';
    else textAlign = direction > 0 ? 'left' : 'right';
  }
  return { rotation: rotationDiff, textAlign, textVerticalAlign };
}
// cartesianAxisHelper.ts:63-66, 88-106 + AxisBuilder.ts:1369-1373, 553-558:
// the label rotation (+rotate on zero, -rotate only on a top axis off zero),
// the text layout, and the axis group's matrix G
function labelLayoutU(ar, frame, onZero) {
  const axisRotation = Math.PI / 2 * (ar.dim === 'x' ? 0 : 1);
  const pos = onZero ? 'onZero' : ar.position;
  const raw = pos === 'top' ? -ar.rotate : ar.rotate;           // cfg.raw.labelRotate
  const labelRotation = ((raw != null ? raw : ar.rotate) || 0) * Math.PI / 180;
  let dir = { top: -1, bottom: 1, left: -1, right: 1 }[ar.position];
  if (ar.labelInside) dir = -dir;
  const lay = innerTextLayoutU(axisRotation, labelRotation, dir);
  const G = zrUpdate(zrT({ x: frame.X, y: frame.Y, rotation: axisRotation }), null, false);
  return { axisRotation, labelRotation, dir, layoutRotation: lay.rotation, align: lay.textAlign, verticalAlign: lay.textVerticalAlign, G };
}
// AxisBuilder.ts:1563-1574 + the label's getComputedTransform (S3): the
// product M = G * local(c, t, layoutRotation), decomposed, recomposed as F
function labelMatrixU(ar, frame, lay, tickValue, hadOne) {
  const M = zrUpdate(zrT({ x: localU(ar, tickValue), y: frame.t, rotation: lay.layoutRotation }), lay.G, true);
  const d = zrDecompose(M);
  return { M, d, F: zrUpdate(zrT(d), null, hadOne) };
}
// Axis.ts:167-201 + fixOnBandTicksCoords (:314-354), global: the band-shifted
// list ends in a pushed (extent[1] + 1) at oldLast + bandWidth, and oldLast is
// the boundary tick extent[1] whether or not it was popped as offInterval
function bandTickListU(r, tickValues, modified) {
  const bw = modified ? categoryBandWidthU(r) : 0;
  return tickValues.map((tv, i) => {
    const pushed = modified && i === tickValues.length - 1 && tv === r.effective[1] + 1;
    const local = pushed ? (localU(r, r.effective[1]) - bw / 2) + bw : localU(r, tv) - (modified ? bw / 2 : 0);
    return toGlobalU(r, local);
  });
}
// the port at HEAD for a band-shifted list (Builder.pas CategoryMarks):
// global -> local by the rect's edges, shift, back by the edges
function bandTickListQ(r, tickValues) {
  const bw = categoryBandWidthU(r);
  const L = r.rect.x;
  const B = r.rect.y + r.rect.height;
  const lq = g => (r.dim === 'x' ? g - L : B - g);
  const gq = c => (r.dim === 'x' ? c + L : B - c);
  return tickValues.map((tv, i) => {
    if (i === tickValues.length - 1 && tv === r.effective[1] + 1) return gq((lq(toGlobalU(r, localU(r, r.effective[1]))) - bw / 2) + bw);
    return gq(lq(toGlobalU(r, localU(r, tv))) - bw / 2);
  });
}
// BarView.ts:684-727
function clipU(a, l) {
  const sw = l.width < 0 ? -1 : 1;
  const sh = l.height < 0 ? -1 : 1;
  if (sw < 0) { l.x += l.width; l.width = -l.width; }
  if (sh < 0) { l.y += l.height; l.height = -l.height; }
  const lx0 = l.x;
  const ly0 = l.y;
  const X2 = a.x + a.width;
  const Y2 = a.y + a.height;
  const x = Math.max(l.x, a.x);
  const x2 = Math.min(l.x + l.width, X2);
  const y = Math.max(l.y, a.y);
  const y2 = Math.min(l.y + l.height, Y2);
  const xc = x2 < x;
  const yc = y2 < y;
  l.x = (xc && x > X2) ? x2 : x;
  l.y = (yc && y > Y2) ? y2 : y;
  l.width = xc ? 0 : x2 - (MUT.clipFromOriginal ? lx0 : x);
  l.height = yc ? 0 : y2 - (MUT.clipFromOriginal ? ly0 : y);
  if (sw < 0) { l.x += l.width; l.width = -l.width; }
  if (sh < 0) { l.y += l.height; l.height = -l.height; }
  return { l, clipped: xc || yc };
}
function boxOf(s) {
  return [s.width < 0 ? s.x + s.width : s.x, s.height < 0 ? s.y + s.height : s.y,
    s.width < 0 ? s.x : s.x + s.width, s.height < 0 ? s.y : s.y + s.height];
}

// axisStatistics.ts LINEAR_POSITIVE_MIN_GAP_*
const SINGLE = -2;
const NONE = -1;
// axisStatisticsMetricsImpl.ts metricLiPosMinGapImpl over the raw data of the
// series on one key (value and time axes only here)
function liPosMinGapU(seriesList, dim) {
  const vals = [];
  seriesList.forEach(s => {
    const raw = s.getRawData();
    const dimIdx = raw.getDimensionIndex(raw.mapDimension(dim));
    if (!(dimIdx >= 0)) return;
    const store = raw.getStore();
    for (let i = 0, n = store.count(); i < n; i++) {
      const v = store.get(dimIdx, i);
      if (isFinite(v)) vals.push(v);
    }
  });
  vals.sort((a, b) => a - b);
  let min = Infinity;
  for (let j = 1; j < vals.length; j++) {
    const d = vals[j] - vals[j - 1];
    if (d > 0 && d < min) min = d;
  }
  return isFinite(min) ? min : vals.length > 0 ? SINGLE : NONE;
}
// axisBand.ts calcBandWidth: { w, w2 } over pixel span px (w before the min of 1)
function bandU(b, gap, px) {
  const e = mapExtOf(b);
  const lin = e[1] - e[0];
  if (b.scaleType === 'ordinal') {
    let len = lin + (b.onBand ? 1 : 0);
    if (len === 0) len = 1;
    const w = px / len;
    return { w, w2: !b.onBand && lin && px ? w * lin / px : NaN };
  }
  if (gap > 0 && isFinite(lin) && lin > 0) return { w: px / lin * gap, w2: gap };
  if (gap === SINGLE) {
    const w = px * 0.8;
    return { w, w2: w * lin / px };
  }
  return { w: NaN, w2: NaN };
}
// the bar layout's band (calcBandWidth with min 1)
function layoutBandU(b, gap, px) {
  const w = bandU(b, gap, px).w;
  return Number.isFinite(w) ? Math.max(1, w) : 1;
}
// barGrid.ts calcBarWidthAndOffset over the series on one axis and key
function barWidthOffsetU(seriesList, bw, pp) {
  const infos = seriesList.map(s => ({
    barWidth: pp(s.get('barWidth'), bw),
    barMaxWidth: pp(s.get('barMaxWidth'), bw),
    barMinWidth: pp(s.get('barMinWidth') || 1, bw),
    barGap: s.get('barGap'),
    barCategoryGap: s.get('barCategoryGap'),
    defaultBarGap: s.get('defaultBarGap'),
    stackId: s.get('stack') || '__ec_stack_' + s.seriesIndex,
  }));
  let remainedWidth = bw;
  let autoWidthCount = 0;
  let barCategoryGapOption;
  let barGapOption;
  const stackIdList = [];
  const stackMap = {};
  infos.forEach((info, idx) => {
    if (!idx) barGapOption = info.defaultBarGap || 0;
    const stackId = info.stackId;
    if (!Object.prototype.hasOwnProperty.call(stackMap, stackId)) autoWidthCount++;
    let stackItem = stackMap[stackId];
    if (!stackItem) {
      stackItem = stackMap[stackId] = { width: 0, maxWidth: 0 };
      stackIdList.push(stackId);
    }
    let barWidth = info.barWidth;
    if (barWidth && !stackItem.width) {
      stackItem.width = barWidth;
      barWidth = Math.min(remainedWidth, barWidth);
      remainedWidth -= barWidth;
    }
    if (info.barMaxWidth) stackItem.maxWidth = info.barMaxWidth;
    if (info.barMinWidth) stackItem.minWidth = info.barMinWidth;
    if (info.barGap != null) barGapOption = info.barGap;
    if (info.barCategoryGap != null) barCategoryGapOption = info.barCategoryGap;
  });
  if (barCategoryGapOption == null) barCategoryGapOption = Math.max((35 - stackIdList.length * 4), 15) + '%';
  const barCategoryGapNum = pp(barCategoryGapOption, bw);
  const barGapPercent = pp(barGapOption, 1);
  let autoWidth = (remainedWidth - barCategoryGapNum) / (autoWidthCount + (autoWidthCount - 1) * barGapPercent);
  autoWidth = Math.max(autoWidth, 0);
  stackIdList.forEach(stackId => {
    const column = stackMap[stackId];
    const maxWidth = column.maxWidth;
    const minWidth = column.minWidth;
    if (!column.width) {
      let finalWidth = autoWidth;
      if (maxWidth && maxWidth < finalWidth) finalWidth = Math.min(maxWidth, remainedWidth);
      if (minWidth && minWidth > finalWidth) finalWidth = minWidth;
      if (finalWidth !== autoWidth) {
        column.width = finalWidth;
        remainedWidth -= finalWidth + barGapPercent * finalWidth;
        autoWidthCount--;
      }
    } else {
      let finalWidth = column.width;
      if (maxWidth) finalWidth = Math.min(finalWidth, maxWidth);
      if (minWidth) finalWidth = Math.max(finalWidth, minWidth);
      column.width = finalWidth;
      remainedWidth -= finalWidth + barGapPercent * finalWidth;
      autoWidthCount--;
    }
  });
  autoWidth = (remainedWidth - barCategoryGapNum) / (autoWidthCount + (autoWidthCount - 1) * barGapPercent);
  autoWidth = Math.max(autoWidth, 0);
  let widthSum = 0;
  let lastColumn;
  stackIdList.forEach(stackId => {
    const column = stackMap[stackId];
    if (!column.width) column.width = autoWidth;
    lastColumn = column;
    widthSum += column.width * (1 + barGapPercent);
  });
  if (lastColumn) widthSum -= lastColumn.width * barGapPercent;
  const result = {};
  let offset = -widthSum / 2;
  stackIdList.forEach(stackId => {
    const column = stackMap[stackId];
    result[stackId] = result[stackId] || { offset, width: column.width };
    offset += column.width * (1 + barGapPercent);
  });
  return result;
}
// scaleRawExtentInfo containShape: the mapping predicted for pixel span px
// (value, time and category axes; no dataZoom)
function predictMappingU(b, gaps, px) {
  const eff = b.effective;
  const bb = Object.assign({}, b, { mapping: null });
  let sup = null;
  gaps.forEach(gap => {
    const w2 = bandU(bb, gap, px).w2;
    if (Number.isFinite(w2)) {
      sup = sup || [0, 0];
      if (-w2 / 2 < sup[0]) sup[0] = -w2 / 2;
      if (w2 / 2 > sup[1]) sup[1] = w2 / 2;
    }
  });
  if (!sup) return null;
  if (b.scaleType === 'ordinal') return b.onBand ? null : [Math.min(eff[0], eff[0] + sup[0]), Math.max(eff[1], eff[1] + sup[1])];
  const e = [Math.min(eff[0], eff[0] + sup[0]), Math.max(eff[1], eff[1] + sup[1])];
  return e[0] < eff[0] || e[1] > eff[1] ? e : null;
}

// ---------- the port's formula today (Q), for discrimination only ----------
// Coord.pas:345-363 (BandPxExtent), 451-463 (DataToCoord), 514-525 (edges);
// Scale.pas:540-551 (Normalize; log re-derived from the pow ends); edges: the
// raw TySolveBox edges for 'none' (L = s, R = W - e, size-given R = s + sz),
// otherwise x + w (Layout.pas:1279-1282), assuming the port's rect is upstream's.
function solveEdges(lib, gm, W, H) {
  const pp = lib.number.parsePercent;
  const p = gm.getBoxLayoutParams();
  const edge = (sK, eK, zK, ext) => {
    const s = pp(p[sK], ext), e = pp(p[eK], ext), z = pp(p[zK], ext);
    if (typeof p[sK] === 'string' && /center|middle/.test(p[sK])) return null;
    if (!isNaN(s) && !isNaN(z)) return [s, s + z];
    if (!isNaN(s) && !isNaN(e)) return [s, ext - e];
    if (!isNaN(e) && !isNaN(z)) { const st = ext - e; return [st - z, st]; }
    if (!isNaN(s)) return [s, ext];
    if (!isNaN(e)) return [0, ext - e];
    if (!isNaN(z)) return [0, z];
    return [0, ext];
  };
  const ex = edge('left', 'right', 'width', W);
  const ey = edge('top', 'bottom', 'height', H);
  if (!ex || !ey) return null;
  return { L: ex[0], R: ex[1], T: ey[0], B: ey[1] };
}
function portEdges(lib, gm, rect, W, H) {
  const mode = gm.get('outerBoundsMode', true);
  if (!gm.get('containLabel') && mode != null && mode !== 'auto' && mode !== 'same') {
    const e = solveEdges(lib, gm, W, H);
    if (e) return e;
  }
  return { L: rect.x, R: rect.x + rect.width, T: rect.y, B: rect.y + rect.height };
}
function normalizeQ(ar, v) {
  const m = mapExtOf(ar);
  if (ar.scaleType === 'log') {
    const a = logTick(m[0], ar.base), b = logTick(m[1], ar.base);
    if (b === a) return 0.5;
    return (logTick(v, ar.base) - a) / (b - a);
  }
  return m[1] === m[0] ? 0.5 : (v - m[0]) / (m[1] - m[0]);
}
const pxQ = (ar, E) => (ar.dim === 'x' ? [E.L, E.R] : [E.B, E.T]);
function perAxisQ(ar, v, E) {
  if (v == null || Number.isNaN(v)) return NaN;
  let n = normalizeQ(ar, v);
  if (ar.inverse) n = 1 - n;
  let [a, b] = pxQ(ar, E);
  if (ar.onBand && ar.count > 0) {
    const m = (b - a) / ar.count / 2;
    a = a + m;
    b = b - m;
  }
  return a + n * (b - a);
}
// Builder.pas:2370 (p from the pxInit edges) + Layout.pas:1866-1907
function labelQ(ar, v, E, E0) {
  if (!E0) return NaN;
  const [a0, b0] = pxQ(ar, E0);
  const q0 = perAxisQ(ar, v, E0);
  const p = b0 === a0 ? 0.5 : (q0 - a0) / (b0 - a0);
  return ar.dim === 'x' ? E.L + p * (E.R - E.L) : E.B - p * (E.B - E.T);
}

// ---------- probe values ----------

const FRACS = [0, 0.137, 0.5, 0.731, 1, -0.253, 1.29];
const FRACS_DYADIC = [0, 0.125, 0.5, 0.75, 1, -0.25, 1.25];
const FRACS_DENSE = [0, 0.137, 0.25, 0.5, 0.618, 0.731, 1, -0.253, 1.29, 1e-9, 1 - 1e-9];
function valueAt(ar, f) {
  const outer = mapExtOf(ar);
  if (f === 0) return outer[0];
  if (f === 1) return outer[1];
  if (ar.scaleType === 'log') {
    const e = ar.logExtent;
    return Math.pow(ar.base, e[0] + f * (e[1] - e[0]));
  }
  const v = outer[0] + f * (outer[1] - outer[0]);
  // time: a half millisecond, which parse rounds on the per-axis path only
  return ar.scaleType === 'time' ? Math.floor(v) + 0.5 : v;
}
function probeValues(ar, fracs) {
  if (ar.scaleType === 'ordinal') {
    const n = ar.count;
    return [0, Math.floor((n - 1) / 2), n - 1, -1, n];
  }
  return fracs.map(f => valueAt(ar, f));
}

// ---------- running upstream ----------

function run(c, lib) {
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  try {
    const option = clone(c.option);
    option.animation = false;
    const written = clone(option);
    chart.setOption(option);
    chart.renderToSVGString();
    const ecModel = chart.getModel();
    const fails = [];
    const fail = (check, msg) => fails.push({ check, msg });
    const disc = { compared: 0, affineVsPerAxis: 0, maxAffineShift: 0, portVsUpstream: 0, logNormalize: 0, kills: {}, pins: {} };
    const grids = [];
    ecModel.eachComponent('grid', gm => {
      grids.push(runGrid(c, lib, chart, ecModel, gm, fail, disc));
    });
    must(grids.length > 0, c.name + ': no grid');
    return { option: written, grids, fails, disc };
  } finally {
    chart.dispose();
  }
}

function runGrid(c, lib, chart, ecModel, gm, fail, disc) {
  const cs = gm.coordinateSystem;
  const carts = cs.getCartesians();
  must(carts.length === 1, c.name + ': grid ' + gm.componentIndex + ' has ' + carts.length + ' cartesians');
  const cart = carts[0];
  const rect = plainRect(cs.getRect());
  const E = portEdges(lib, gm, rect, c.W, c.H);
  const E0 = solveEdges(lib, gm, c.W, c.H);
  const tr = cart._transform ? cart._transform.slice() : null;
  const inv = cart._invTransform ? cart._invTransform.slice() : null;
  const tally = (live, q) => {
    disc.compared++;
    if (q !== undefined && differs(q, live)) disc.portVsUpstream++;
  };
  // every recorded number with the recipe that predicts it, replayed under
  // each mutant of the case's kill list
  const thunks = [];
  const replay = (live, f) => thunks.push({ live, f });
  const rawRect = plainRect(lib.helper.getLayoutRect(gm.getBoxLayoutParams(), { width: c.W, height: c.H }));
  const pinSet = new Set(c.pins || []);
  const pin = id => { disc.pins[id] = (disc.pins[id] || 0) + 1; };

  // the axes, x then y, in index order
  const axes = [];
  ['x', 'y'].forEach(dim => {
    cs.getAxes().filter(a => a.dim === dim).sort((a, b) => a.model.componentIndex - b.model.componentIndex).forEach(a => axes.push(a));
  });
  const recs = new Map();
  axes.forEach(axis => {
    const scale = axis.scale;
    const log = scale.type === 'log';
    const r = {
      dim: axis.dim,
      index: axis.model.componentIndex,
      type: axis.type,
      scaleType: scale.type,
      position: axis.position,
      inverse: !!axis.inverse,
      onBand: !!axis.onBand,
      count: scale.type === 'ordinal' ? scale.count() : null,
      base: log ? scale.base : null,
      effective: scale.getExtent().slice(),
      mapping: (m => (m ? m.slice() : null))(scale.getExtentUnsafe(MAPPING, null)),
      logExtent: log ? (scale.getExtentUnsafe(MAPPING, INNERMOST) || scale.getExtentUnsafe(EFFECTIVE, INNERMOST)).slice() : null,
      extent: axis.getExtent().slice(),
      rect,
      wh: axis.dim === 'x' ? rect.width : rect.height,
      gxy: axis.dim === 'x' ? rect.x : rect.y,
      offset: axis.model.get('offset') || 0,
      margin: axis.model.get(['axisLabel', 'margin']),
      labelInside: !!axis.model.get(['axisLabel', 'inside']),
      rotate: axis.model.get(['axisLabel', 'rotate']),
      axis,
    };
    if (log) {
      const st = scale.intervalStub;
      const own = st.getExtentUnsafe(MAPPING) || st.getExtentUnsafe(EFFECTIVE);
      if (!sameArr(own, r.logExtent)) fail(1, r.dim + r.index + ': logExtent is not the interval stub\'s');
    }
    recs.set(axis, r);
  });
  const ax = recs.get(cart.getAxis('x'));
  const ay = recs.get(cart.getAxis('y'));

  // check 1: extents and the matrix
  axes.forEach(axis => {
    const r = recs.get(axis);
    if (!sameArr(r.extent, extentU(r))) fail(1, r.dim + r.index + ': extent ' + JSON.stringify(textArr(r.extent)) + ' is not built from rect');
  });
  const M = affineU(ax, ay);
  if (!sameArr(M, tr)) fail(1, 'transform ' + JSON.stringify(textArr(tr)) + ', the recipe gives ' + JSON.stringify(textArr(M)));
  const Minv = M ? invertU(M) : null;
  if (!sameArr(Minv, inv)) fail(1, 'invTransform ' + JSON.stringify(textArr(inv)) + ', the recipe gives ' + JSON.stringify(textArr(Minv)));
  const Mnow = () => affineU(ax, ay);
  const MinvNow = () => { const m = Mnow(); return m ? invertU(m) : null; };
  for (let i = 0; i < 6; i++) {
    replay(tr ? tr[i] : null, () => { const m = Mnow(); return m ? m[i] : null; });
    replay(inv ? inv[i] : null, () => { const m = MinvNow(); return m ? m[i] : null; });
  }
  axes.forEach(axis => {
    const r = recs.get(axis);
    r.mappingLive = r.mapping ? r.mapping.slice() : null;
    for (let i = 0; i < 2; i++) replay(r.mappingLive ? r.mappingLive[i] : null, () => (r.mapping ? r.mapping[i] : null));
  });
  // check 2: getArea
  const area = plainRect(cart.getArea());
  const aU = areaU(ax, ay);
  if (!RECT.every(k => same(aU[k], area[k]))) fail(2, 'area ' + JSON.stringify(textRect(area)) + ', the recipe gives ' + JSON.stringify(textRect(aU)));

  // log: upstream normalize vs the port's
  const logDisc = (ar, v) => {
    if (ar.scaleType !== 'log' || !(v > 0) || !isFinite(v)) return;
    if (differs(normalizeU(ar, parseU(ar, v)), normalizeQ(ar, v))) disc.logNormalize++;
  };

  // ticks (check 2)
  axes.forEach(axis => {
    const r = recs.get(axis);
    const tc = axis.getTicksCoords();
    r.ticks = tc.map(t => t.tickValue);
    r.tickCoords = tc.map(t => axis.toGlobalCoord(t.coord));
    const modified = tc.length > 0 && tc[0].onBand;
    const wants = tickListU(r, r.ticks, modified);
    tc.forEach((t, i) => {
      const want = wants[i];
      replay(r.tickCoords[i], () => tickListU(r, r.ticks, modified)[i]);
      if (!same(want, r.tickCoords[i])) fail(2, r.dim + r.index + ': tick ' + t.tickValue + ' at ' + text(r.tickCoords[i]) + ', P gives ' + text(want));
      logDisc(r, t.tickValue);
      tally(r.tickCoords[i], modified ? undefined : perAxisQ(r, t.tickValue, E));
    });
    // split lines (check 2): CartesianAxisView.ts:118-128, the coordinates
    // before subPixelOptimizeLine; not replayed and not tallied, so the kill
    // and discrimination counts stay what they were
    const sl = axis.getTicksCoords({ tickModel: axis.model.getModel('splitLine'), breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' });
    r.splitLineShow = !!axis.model.get(['splitLine', 'show']);
    r.splitLineTicks = sl.map(t => t.tickValue);
    r.splitLineCoords = sl.map(t => axis.toGlobalCoord(t.coord));
    r.splitLineBanded = sl.length > 0 && !!sl[0].onBand;
    r.tickBanded = modified;
    const slWant = bandTickListU(r, r.splitLineTicks, r.splitLineBanded);
    sl.forEach((t, i) => {
      if (!same(slWant[i], r.splitLineCoords[i])) fail(2, r.dim + r.index + ': split line ' + t.tickValue + ' at ' + text(r.splitLineCoords[i]) + ', P gives ' + text(slWant[i]));
    });
    // the transcription the split lines use gives the ticks too
    const tkWant = bandTickListU(r, r.ticks, modified);
    if (!sameArr(tkWant, r.tickCoords)) fail(2, r.dim + r.index + ': the split-line transcription misses a tick');
  });

  // onZero (check 2)
  axes.forEach(axis => {
    const r = recs.get(axis);
    const other = axis.getAxesOnZeroOf()[0];
    r.onZeroOf = other ? other.dim + other.model.componentIndex : null;
    r.onZeroCoord = null;
    if (!other) return;
    const o = recs.get(other);
    must(o, c.name + ': onZero axis of another grid');
    r.onZeroCoord = other.toGlobalCoord(other.dataToCoord(0));
    const want = perAxisU(o, 0);
    r.onZeroRec = o;
    replay(r.onZeroCoord, () => perAxisU(o, 0));
    if (!same(want, r.onZeroCoord)) fail(2, r.dim + r.index + ': onZeroCoord ' + text(r.onZeroCoord) + ', P gives ' + text(want));
    tally(r.onZeroCoord, perAxisQ(o, 0, E));
  });

  // labels (check 3)
  axes.forEach(axis => {
    const r = recs.get(axis);
    const frame = labelFrameU(r, r.onZeroCoord);
    r.labelOffset = frame.labelOffset;
    r.labels = [];
    r.labelRotation = null;
    r.layoutRotation = null;
    r.align = null;
    r.verticalAlign = null;
    const view = chart.getViewOfComponentModel(axis.model);
    if (!view || !view.group) return;
    const lay = labelLayoutU(r, frame, r.onZeroCoord != null);
    const layoutList = (axis.axisBuilder && axis.axisBuilder._local && axis.axisBuilder._local.labelLayoutList) || [];
    const lw = v => r.dim + r.index + ': label ' + v;
    view.group.traverse(el => {
      if (el.type !== 'text') return;
      const k = Object.keys(el).find(kk => kk.startsWith('__ec_inner') && el[kk] && el[kk].labelInfo);
      if (!k) return;
      const tick = el[k].labelInfo.tick;
      if (!tick) return;
      const v = tick.value;
      const want = labelAnchorU(r, frame, v);
      if (!same(want[0], el.x) || !same(want[1], el.y)) {
        fail(3, lw(v) + ' at [' + text(el.x) + ', ' + text(el.y) + '], B gives [' + textArr(want) + ']');
      }
      const frameNow = () => labelFrameU(r, r.onZeroRec ? perAxisU(r.onZeroRec, 0) : null);
      replay(el.x, () => labelAnchorU(r, frameNow(), v)[0]);
      replay(el.y, () => labelAnchorU(r, frameNow(), v)[1]);
      const lab = { tick: num(v), x: num(el.x), y: num(el.y) };
      if (el.ignore || el.invisible) lab.hidden = true;
      // the rotation, the text layout, the transform and the local rect (check 3)
      const layout = layoutList.find(l => l && l.label === el);
      must(layout && layout.localRect, c.name + ' ' + lw(v) + ': not in the builder\'s labelLayoutList');
      const live = layout.transform ? Array.from(layout.transform) : null;
      const U = labelMatrixU(r, frame, lay, v, live != null);
      const rotU = -Math.atan2(U.M[1], U.M[0]);
      if (!same(rotU, el.rotation)) fail(3, lw(v) + ': rotation ' + text(el.rotation) + ', -atan2(M1, M0) gives ' + text(rotU));
      if (!same(U.d.x, el.x) || !same(U.d.y, el.y)) fail(3, lw(v) + ': the decomposed x, y are not the element\'s');
      if (!sameArr(U.F, live)) fail(3, lw(v) + ': transform [' + textArr(live) + '], the recompose gives [' + textArr(U.F) + ']');
      const cur = layout.transform ? Array.from(el.getComputedTransform() || []) : null;
      if (!sameArr(cur, live)) fail(3, lw(v) + ': the layout transform is not the element\'s computed transform');
      if (!same(el[k].layoutRotation, lay.layoutRotation)) {
        fail(3, lw(v) + ': layoutRotation ' + text(el[k].layoutRotation) + ', innerTextLayout gives ' + text(lay.layoutRotation));
      }
      if (el.style.align !== lay.align || el.style.verticalAlign !== lay.verticalAlign) {
        fail(3, lw(v) + ': ' + el.style.align + '/' + el.style.verticalAlign + ', innerTextLayout gives ' + lay.align + '/' + lay.verticalAlign);
      }
      if (!r.labels.length) {
        r.labelRotation = el.rotation;
        r.layoutRotation = el[k].layoutRotation;
        r.align = el.style.align;
        r.verticalAlign = el.style.verticalAlign;
      } else if (!same(el.rotation, r.labelRotation)) {
        fail(3, lw(v) + ': rotation ' + text(el.rotation) + ' is not the axis\' ' + text(r.labelRotation));
      }
      const lr = layout.localRect;
      lab.transform = live ? live.map(num) : null;
      lab.localRect = [num(lr.x), num(lr.y), num(lr.width), num(lr.height)];
      r.labels.push(lab);
      tally(r.dim === 'x' ? el.x : el.y, labelQ(r, v, E, E0));
      // what the new cases pin (self-check 6 `pins`), counted per label
      if (pinSet.size) {
        const moved = rr => { const a = labelAnchorU(r, labelFrameU(rr, r.onZeroCoord), v); return differs(a[0], el.x) || differs(a[1], el.y); };
        const s96 = q => q * 96 / 96;
        if (pinSet.has('N1') && r.position === 'top' && r.onZeroCoord != null && r.rotate && Math.sign(el.rotation) === Math.sign(r.rotate)) pin('N1');
        if (pinSet.has('topNegates') && r.position === 'top' && r.onZeroCoord == null && r.rotate && Math.sign(el.rotation) === -Math.sign(r.rotate)) pin('topNegates');
        if (pinSet.has('N2') && moved(Object.assign({}, r, { offset: s96(r.offset), margin: s96(r.margin) }))) pin('N2');
        if (pinSet.has('offsetOutOfT')) {
          const f2 = Object.assign({}, frame, { t: frame.t + lay.dir * r.offset });
          const a = labelAnchorU(r, f2, v);
          if (differs(a[0], el.x) || differs(a[1], el.y)) pin('offsetOutOfT');
        }
        if (pinSet.has('inside') && r.labelInside && moved(Object.assign({}, r, { labelInside: false }))) pin('inside');
      }
    });
  });

  // what the new cases pin, per axis and per rect (self-check 6 `pins`)
  if (pinSet.has('bandedMarks')) {
    axes.forEach(axis => {
      const r = recs.get(axis);
      [[r.tickBanded, r.ticks, r.tickCoords], [r.splitLineBanded, r.splitLineTicks, r.splitLineCoords]].forEach(([banded, vals, coords]) => {
        if (!banded) return;
        const q = bandTickListQ(r, vals);
        coords.forEach((g, i) => { if (differs(q[i], g)) pin('bandedMarks'); });
      });
    });
  }
  if (pinSet.has('alignPerModel')) {
    axes.forEach(axis => {
      const r = recs.get(axis);
      if (!axis.model.get(['axisTick', 'alignWithLabel']) || axis.model.get(['splitLine', 'alignWithLabel'])) return;
      if (r.tickBanded || !r.splitLineBanded) return;
      r.splitLineCoords.forEach((g, i) => { if (differs(g, r.tickCoords[i])) pin('alignPerModel'); });
    });
  }
  if (pinSet.has('popsLast')) {
    // the pushed far edge differs from the one built on the tick before it
    axes.forEach(axis => {
      const r = recs.get(axis);
      const vals = r.splitLineTicks;
      const n = vals.length;
      if (!r.splitLineBanded || n < 2 || vals[n - 1] !== r.effective[1] + 1 || vals[n - 2] === r.effective[1]) return;
      const bw = categoryBandWidthU(r);
      if (differs(toGlobalU(r, (localU(r, vals[n - 2]) - bw / 2) + bw), r.splitLineCoords[n - 1])) pin('popsLast');
    });
  }
  if (pinSet.has('edgesNotSize')) {
    if (differs((rect.x + rect.width) - rect.x, rect.width)) pin('edgesNotSize');
    if (differs((rect.y + rect.height) - rect.y, rect.height)) pin('edgesNotSize');
  }

  // a recorded dataToPoint: check 1 and the discrimination tallies
  const pointOf = (xv, yv, live, clamp, where) => {
    const pathA = gateAffine(tr, xv, yv);
    const want = dataToPointU(M, ax, ay, xv, yv, clamp);
    if (!same(want[0], live[0]) || !same(want[1], live[1])) {
      fail(1, where + ': dataToPoint(' + text(xv) + ', ' + text(yv) + (clamp ? ', clamp' : '') + ') = [' + textArr(live)
        + '], the recipe gives [' + textArr(want) + ']');
    }
    if (!clamp) {
      const P = [perAxisU(ax, xv), perAxisU(ay, yv)];
      const xn = typeof xv === 'string' ? Number(xv) : xv;
      const Q = [perAxisQ(ax, xn, E), perAxisQ(ay, yv, E)];
      for (let d = 0; d < 2; d++) {
        if (pathA) {
          if (differs(P[d], live[d])) disc.affineVsPerAxis++;
          if (Number.isFinite(P[d]) && Number.isFinite(live[d])) disc.maxAffineShift = Math.max(disc.maxAffineShift, Math.abs(P[d] - live[d]));
        }
        if (xv != null && yv != null && Number.isFinite(Number(xv)) && Number.isFinite(yv)) tally(live[d], Q[d]);
      }
      logDisc(ax, xv);
      logDisc(ay, yv);
    }
    return pathA ? 'affine' : 'perAxis';
  };

  // series
  const series = [];
  const H = lib.helper.dataStack;
  ecModel.eachSeries(s => {
    if (s.coordinateSystem !== cart) return;
    const data = s.getData();
    const store = data.getStore();
    const type = s.subType;
    const baseAxis = s.getBaseAxis ? s.getBaseAxis() : null;
    const rec = { index: s.seriesIndex, type, baseDim: baseAxis ? baseAxis.dim : null, items: [] };
    const where = k => 's' + s.seriesIndex + '[' + k + ']';
    const dimIdx = d => {
      let n = data.mapDimension(d);
      if (H.isDimensionStacked(data, n)) n = data.getCalculationInfo('stackResultDimension');
      return data.getDimensionIndex(n);
    };
    const item = (xv, yv, k, extra) => {
      const live = cart.dataToPoint([xv, yv]);
      const it = Object.assign({ values: [num(xv), num(yv)], point: [num(live[0]), num(live[1])] }, extra || {});
      for (let d = 0; d < 2; d++) replay(live[d], () => dataToPointU(Mnow(), ax, ay, xv, yv)[d]);
      it.path = pointOf(xv, yv, live, false, where(k));
      return { it, live };
    };

    if (type === 'bar' || type === 'pictorialBar') {
      const valueAxis = cart.getOtherAxis(baseAxis);
      const v = recs.get(valueAxis);
      const valueH = valueAxis.isHorizontal();
      const valueDim = data.mapDimension(valueAxis.dim);
      const valueDimIdx = data.getDimensionIndex(valueDim);
      const baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim));
      const stackResultDim = data.getCalculationInfo('stackResultDimension');
      const stacked = H.isDimensionStacked(data, valueDim) && !!data.getCalculationInfo('stackedOnSeries');
      const stackedDimIdx = stackResultDim && data.getDimensionIndex(stackResultDim);
      const sv = valueAxis.scale.rawExtentInfo.makeRenderInfo().startValue;
      const vas = valueAxis.toGlobalCoord(valueAxis.dataToCoord(sv));
      const vasU = perAxisU(v, sv);
      if (!same(vasU, vas)) fail(2, where('') + ': valueAxisStart ' + text(vas) + ', P gives ' + text(vasU));
      if (v.startValue != null && (!same(v.startValue, sv) || !same(v.valueAxisStart, vas))) fail(2, v.dim + v.index + ': two series disagree on valueAxisStart');
      if (v.startValue == null) {
        v.startValue = sv;
        v.valueAxisStart = vas;
        tally(vas, perAxisQ(v, sv, E));
        replay(vas, () => perAxisU(v, sv));
      }
      const off = data.getLayout('offset');
      const size = data.getLayout('size');
      const bwLive = data.getLayout('bandWidth');
      rec.offset = num(off);
      rec.size = num(size);
      const minH = s.get('barMinHeight') || 0;
      const clipOn = s.get('clip', true);
      // the band, width and offset from the base axis' pixel span (barGrid.ts)
      const b = recs.get(baseAxis);
      const onKey = [];
      ecModel.eachSeries(o => { if (o.subType === type && o.coordinateSystem === cart && o.getBaseAxis() === baseAxis) onKey.push(o); });
      const gap = b.scaleType === 'ordinal' ? null : liPosMinGapU(onKey, baseAxis.dim);
      const stackId = s.get('stack') || '__ec_stack_' + s.seriesIndex;
      const osFrom = pxSpan => {
        const bw = layoutBandU(b, gap, pxSpan);
        const col = barWidthOffsetU(onKey, bw, lib.number.parsePercent)[stackId];
        return { bw, off: col.offset, size: col.width };
      };
      const pxTrue = Math.abs(b.extent[1] - b.extent[0]);
      const pxEdges = b.dim === 'x' ? (rect.x + rect.width) - rect.x : (rect.y + rect.height) - rect.y;
      if ((c.kills || []).includes('bandFromEdges')) {
        const t = osFrom(pxTrue);
        if (!same(t.bw, bwLive) || !same(t.off, off) || !same(t.size, size)) {
          fail(5, where('') + ': bandWidth/offset/size [' + textArr([bwLive, off, size]) + '], barGrid gives [' + textArr([t.bw, t.off, t.size]) + ']');
        }
      }
      const osNow = () => (MUT.bandFromEdges ? osFrom(pxEdges) : { off, size });
      const predictBar = q => {
        const Mn = Mnow();
        const os = osNow();
        const vasN = perAxisU(v, sv);
        const centre = cc => (MUT.cellCentre ? ((cc - bwLive / 2) + (cc + bwLive / 2)) / 2 : cc);
        let L;
        if (valueH) {
          const coord = dataToPointU(Mn, ax, ay, q.value, q.baseValue);
          let bc = vasN;
          if (stacked) bc = dataToPointU(Mn, ax, ay, q.stackStart, q.baseValue)[0];
          let width = coord[0] - bc;
          if (Math.abs(width) < minH) width = (width < 0 ? -1 : 1) * minH;
          L = { x: bc, y: centre(coord[1]) + os.off, width, height: os.size };
        } else {
          const coord = dataToPointU(Mn, ax, ay, q.baseValue, q.value);
          let bc = vasN;
          if (stacked) bc = dataToPointU(Mn, ax, ay, q.baseValue, q.stackStart)[1];
          let height = coord[1] - bc;
          if (Math.abs(height) < minH) height = (height <= 0 ? -1 : 1) * minH;
          L = { x: centre(coord[0]) + os.off, y: bc, width: os.size, height };
        }
        let S = Object.assign({}, L);
        let hidden = false;
        if (clipOn) {
          const r = clipU(areaU(ax, ay), S);
          S = r.l;
          hidden = r.clipped;
        }
        return { L, box: boxOf(S), hidden };
      };
      for (let k = 0; k < data.count(); k++) {
        const value = store.get(stacked ? stackedDimIdx : valueDimIdx, k);
        const baseValue = store.get(baseDimIdx, k);
        const stackStart = stacked ? +value - store.get(valueDimIdx, k) : undefined;
        const xv = valueH ? value : baseValue;
        const yv = valueH ? baseValue : value;
        const { it } = item(xv, yv, k, stacked ? { stackStart: num(stackStart) } : null);
        const el = data.getItemGraphicEl(k);
        const L = data.getItemLayout(k);
        it.class = !el ? 'none' : el.ignore ? 'hidden' : 'drawn';
        const finiteL = L && RECT.every(q => typeof L[q] === 'number' && Number.isFinite(L[q]));
        it.layout = finiteL ? numRect(L) : null;
        if (type === 'pictorialBar') {
          const f = L ? L[valueH ? 'x' : 'y'] : null;
          it.floor = typeof f === 'number' ? num(f) : null;
        }
        rec.items.push(it);
        if (!finiteL) continue;
        // check 5: barGrid.ts:441-469
        const q = { value, baseValue, stackStart };
        const pred = predictBar(q);
        const want = pred.L;
        RECT.forEach(f => replay(L[f], () => predictBar(q).L[f]));
        const bad = RECT.filter(f => !same(want[f], L[f]));
        if (bad.length) fail(5, where(k) + ': layout ' + JSON.stringify(textRect(L)) + ', the recipe gives ' + JSON.stringify(textRect(want)));
        if (type === 'pictorialBar' || !el) continue;
        must(el.shape && el.shape.width !== undefined, c.name + ' ' + where(k) + ': no rect shape');
        must(!((data.getItemModel(k).get(['itemStyle', 'borderWidth']) || 0) > 0), c.name + ' ' + where(k) + ': a bordered bar');
        const liveBox = boxOf(el.shape);
        it.box = liveBox.map(num);
        for (let i = 0; i < 4; i++) replay(liveBox[i], () => predictBar(q).box[i]);
        const hidden = pred.hidden;
        if (!sameArr(pred.box, liveBox)) {
          fail(5, where(k) + ': box [' + textArr(liveBox) + '], the clip gives [' + textArr(pred.box) + ']');
        }
        if (hidden !== !!el.ignore) fail(5, where(k) + ': ignore ' + !!el.ignore + ', the clip says ' + hidden);
      }
    } else if (type === 'candlestick') {
      const baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim));
      const valueDims = ['open', 'close', 'lowest', 'highest'];
      const valueIdx = data.mapDimensionsAll(cart.getOtherAxis(baseAxis).dim).map(n => data.getDimensionIndex(n));
      const baseIsX = baseAxis.dim === 'x';
      for (let k = 0; k < data.count(); k++) {
        const b = store.get(baseDimIdx, k);
        valueIdx.forEach((vi, j) => {
          const val = store.get(vi, k);
          rec.items.push(item(baseIsX ? b : val, baseIsX ? val : b, k, { field: valueDims[j] }).it);
        });
      }
    } else {
      // scatter, effectScatter, line, graph: the points layout (layout/points.ts)
      // or graph's simpleLayout, both dataToPoint of the [x, y] values
      const xi = dimIdx('x');
      const yi = dimIdx('y');
      const pts = type === 'line' ? data.getLayout('points') : null;
      if (type === 'line') {
        if (!(pts instanceof Float32Array)) fail(4, where('') + ': points is not a Float32Array');
        rec.linePoints = [];
        rec.symbols = [];
      }
      for (let k = 0; k < data.count(); k++) {
        const xv = store.get(xi, k);
        const yv = store.get(yi, k);
        const { it, live } = item(xv, yv, k);
        rec.items.push(it);
        const want = dataToPointU(M, ax, ay, xv, yv);
        if (type === 'line') {
          const px = pts[2 * k], py = pts[2 * k + 1];
          rec.linePoints.push([num(px), num(py)]);
          replay(px, () => fround(dataToPointU(Mnow(), ax, ay, xv, yv)[0]));
          replay(py, () => fround(dataToPointU(Mnow(), ax, ay, xv, yv)[1]));
          if (!same(fround(want[0]), px) || !same(fround(want[1]), py)) {
            fail(4, where(k) + ': vertex [' + text(px) + ', ' + text(py) + '], fround of the recipe [' + textArr(want.map(fround)) + ']');
          }
          const el = data.getItemGraphicEl(k);
          if (el && !el.ignore) {
            rec.symbols.push([num(el.x), num(el.y)]);
            if (!same(el.x, px) || !same(el.y, py)) fail(4, where(k) + ': the symbol is off its vertex');
          } else {
            rec.symbols.push(null);
          }
        } else {
          const L = data.getItemLayout(k);
          if (!L || !same(L[0], live[0]) || !same(L[1], live[1])) fail(1, where(k) + ': itemLayout is not dataToPoint');
        }
      }
      if (type === 'line') {
        const view = chart.getViewOfSeriesModel(s);
        const sop = view && view._stackedOnPoints;
        if (sop && sop.length) {
          if (!(sop instanceof Float32Array)) fail(4, where('') + ': stackedOnPoints is not a Float32Array');
          // helper.ts getStackedOnPoint over prepareDataCoordInfo
          const valueAxis = cart.getOtherAxis(baseAxis);
          const vExt = valueAxis.scale.getExtent();
          const origin = s.get(['areaStyle', 'origin']);
          let valueStart = 0;
          if (origin === 'start') valueStart = vExt[0];
          else if (origin === 'end') valueStart = vExt[1];
          else if (typeof origin === 'number' && !isNaN(origin)) valueStart = origin;
          else if (vExt[0] > 0) valueStart = vExt[0];
          else if (vExt[1] < 0) valueStart = vExt[1];
          const baseDim = data.mapDimension(baseAxis.dim);
          const offset = valueAxis.dim === 'x' ? 1 : 0;
          const over = data.getCalculationInfo('stackedOverDimension');
          const isStacked = H.isDimensionStacked(data, data.mapDimension('x')) || H.isDimensionStacked(data, data.mapDimension('y'));
          rec.areaLower = [];
          for (let k = 0; k < data.count(); k++) {
            let val = NaN;
            if (isStacked) val = data.get(over, k);
            if (isNaN(val)) val = valueStart;
            const sd = [];
            sd[offset] = data.get(baseDim, k);
            sd[1 - offset] = val;
            const want = dataToPointU(M, ax, ay, sd[0], sd[1]);
            const lx = sop[2 * k], ly = sop[2 * k + 1];
            rec.areaLower.push([num(lx), num(ly)]);
            replay(lx, () => fround(dataToPointU(Mnow(), ax, ay, sd[0], sd[1])[0]));
            replay(ly, () => fround(dataToPointU(Mnow(), ax, ay, sd[0], sd[1])[1]));
            if (!same(fround(want[0]), lx) || !same(fround(want[1]), ly)) {
              fail(4, where(k) + ': area lower [' + text(lx) + ', ' + text(ly) + '], fround of the recipe [' + textArr(want.map(fround)) + ']');
            }
          }
        }
      }
    }
    series.push(rec);
  });

  // probes
  const probes = [];
  const fracs = c.dyadic ? FRACS_DYADIC : c.denseProbes ? FRACS_DENSE : FRACS;
  const vx = probeValues(ax, fracs);
  const vy = probeValues(ay, fracs);
  const n = Math.max(vx.length, vy.length);
  const P2 = (kind, input, output, extra) => {
    const p = Object.assign({ kind }, extra || {});
    p.input = input.map(num);
    p.inputText = input.map(text);
    p.output = output.map(num);
    p.outputText = output.map(text);
    probes.push(p);
    return p;
  };
  const d2p = (xv, yv, extra) => {
    const live = cart.dataToPoint([xv, yv]);
    const p = P2('dataToPoint', [typeof xv === 'string' ? Number(xv) : xv, yv], live, extra);
    for (let d = 0; d < 2; d++) replay(live[d], () => dataToPointU(Mnow(), ax, ay, xv, yv)[d]);
    p.path = pointOf(xv, yv, live, false, 'probe dataToPoint');
  };
  for (let i = 0; i < n; i++) d2p(vx[i % vx.length], vy[i % vy.length]);
  const xv = vx[1], yv = vy[1];
  d2p(Infinity, yv);
  d2p(-Infinity, yv);
  d2p(NaN, yv);
  d2p(null, yv);
  d2p(xv, -Infinity);
  d2p(xv, null);
  if (ax.scaleType === 'interval') d2p(String(vx[3]), yv, { inputString: true });
  // clamp
  const beyond = (ar, f) => (ar.scaleType === 'ordinal' ? (f > 1 ? ar.count + 3 : -4) : valueAt(ar, f));
  [[beyond(ax, 3), yv], [xv, yv], [xv, beyond(ay, -1.5)]].forEach(([a, b]) => {
    const live = cart.dataToPoint([a, b], true);
    const p = P2('dataToPointClamp', [a, b], live);
    for (let d = 0; d < 2; d++) replay(live[d], () => dataToPointU(Mnow(), ax, ay, a, b, true)[d]);
    p.path = pointOf(a, b, live, true, 'probe dataToPointClamp');
  });
  // pixels
  const px = [[0.3, 0.6], [0.77, 0.21], [-0.2, 1.15]];
  if (c.denseProbes) px.push([0, 1], [1, 0], [0.5, 0.5]);
  const pixels = px.map(([fx, fy]) => [rect.x + fx * rect.width, rect.y + fy * rect.height]);
  pixels.forEach(p => {
    const live = cart.pointToData(p);
    const want = pointToDataU(Minv, ax, ay, p);
    if (!same(want[0], live[0]) || !same(want[1], live[1])) {
      fail(1, 'pointToData([' + textArr(p) + ']) = [' + textArr(live) + '], the recipe gives [' + textArr(want) + ']');
    }
    const pr = P2('pointToData', p, live);
    for (let d = 0; d < 2; d++) replay(live[d], () => pointToDataU(MinvNow(), ax, ay, p)[d]);
    pr.path = inv ? 'inverse' : 'perAxis';
  });
  [ax, ay].forEach(ar => {
    pixels.forEach(p => {
      const live = ar.axis.pointToData(p);
      const want = coordToDataU(ar, toLocalU(ar, p[ar.dim === 'x' ? 0 : 1]));
      if (!same(want, live)) fail(2, ar.dim + ': Axis2D.pointToData([' + textArr(p) + ']) = ' + text(live) + ', P gives ' + text(want));
      P2('axisPointToData', p, [live], { dim: ar.dim });
      replay(live, () => coordToDataU(ar, toLocalU(ar, p[ar.dim === 'x' ? 0 : 1])));
    });
  });
  [[ax, vx], [ay, vy]].forEach(([ar, vals]) => {
    vals.forEach(v => {
      const live = ar.axis.toGlobalCoord(ar.axis.dataToCoord(v, true));
      const want = perAxisU(ar, v, true);
      if (!same(want, live)) fail(2, ar.dim + ': axisPointer pixel of ' + text(v) + ' = ' + text(live) + ', P gives ' + text(want));
      P2('axisPointerPixel', [v], [live], { dim: ar.dim });
      replay(live, () => perAxisU(ar, v, true));
    });
  });

  // self-check 1: the replay reproduces every recorded number
  MUT = {};
  const replayMisses = thunks.filter(t => differs(t.f(), t.live)).length;
  if (replayMisses) fail(1, replayMisses + ' recorded numbers are not reproduced by their replay');
  // self-check 6: the case's kill list
  const killRect = mut => RECT.filter(k => differs(mut[k], rect[k])).length;
  const underMut = flags => {
    MUT = flags;
    try {
      return thunks.filter(t => differs(t.f(), t.live)).length;
    } finally {
      MUT = {};
    }
  };
  (c.kills || []).forEach(id => {
    let n;
    switch (id) {
      case 'linearMapVerbatimEnd': n = underMut({ noVerbatimEnd: true }); break;
      case 'bandFromEdges': n = underMut({ bandFromEdges: true }); break;
      case 'cellCentre': n = underMut({ cellCentre: true }); break;
      case 'clipFromOriginal': n = underMut({ clipFromOriginal: true }); break;
      case 'pxInitFromEdges': {
        // the containShape mapping predicted from the raw rect's edges instead
        // of its width; the prediction from the width must be upstream's
        const saved = axes.map(a => recs.get(a).mapping);
        n = 0;
        let predicted = 0;
        axes.forEach(axis => {
          const r = recs.get(axis);
          const keys = {};
          ecModel.eachSeries(o => {
            if ((o.subType === 'bar' || o.subType === 'pictorialBar') && o.coordinateSystem === cart && o.getBaseAxis() === axis) {
              (keys[o.subType] = keys[o.subType] || []).push(o);
            }
          });
          const gaps = Object.keys(keys).map(k => (r.scaleType === 'ordinal' ? null : liPosMinGapU(keys[k], r.dim)));
          if (!gaps.length) return;
          predicted++;
          const pxW = r.dim === 'x' ? rawRect.width : rawRect.height;
          const pxE = r.dim === 'x' ? (rawRect.x + rawRect.width) - rawRect.x : (rawRect.y + rawRect.height) - rawRect.y;
          const want = predictMappingU(r, gaps, pxW);
          if (!sameArr(want, r.mappingLive)) fail(6, r.dim + r.index + ': mapping ' + JSON.stringify(textArr(r.mappingLive)) + ', predicted ' + JSON.stringify(textArr(want)));
          r.mapping = predictMappingU(r, gaps, pxE);
        });
        must(predicted > 0, c.name + ': pxInitFromEdges on a chart without a bar base axis');
        n = underMut({});
        axes.forEach((a, i) => { recs.get(a).mapping = saved[i]; });
        break;
      }
      case 'shrinkFromEdges':
        // outerBounds 'auto' fed W = (x+w)-x, H = (y+h)-y
        if (!RECT.every(k => same(rawRect[k], rect[k]))) fail(6, 'rect ' + JSON.stringify(textRect(rect)) + ' is not rawRect ' + JSON.stringify(textRect(rawRect)));
        n = killRect({ x: rect.x, y: rect.y, width: (rect.x + rect.width) - rect.x, height: (rect.y + rect.height) - rect.y });
        break;
      case 'noBorrowDefault':
        n = killRect({ x: 0, y: rect.y, width: rect.width, height: rect.height });
        break;
      case 'autoAsValue':
        n = killRect({ x: 0, y: rect.y, width: rect.width, height: rect.height });
        break;
      default:
        throw new OracleError(c.name + ': unknown mutant ' + id);
    }
    disc.kills[id] = (disc.kills[id] || 0) + n;
  });
  if (c.expectRect) {
    const want = c.expectRect(lib.number.parsePercent, c.W, c.H, gm.getBoxLayoutParams());
    Object.keys(want).forEach(k => {
      if (!same(want[k], rect[k])) fail(6, 'rect.' + k + ' ' + text(rect[k]) + ', expected ' + text(want[k]));
    });
  }

  const axisOut = r => ({
    dim: r.dim,
    index: r.index,
    type: r.type,
    position: r.position,
    inverse: r.inverse,
    onBand: r.onBand,
    count: r.count,
    base: r.base,
    effective: numArr(r.effective),
    effectiveText: textArr(r.effective),
    mapping: numArr(r.mapping),
    mappingText: textArr(r.mapping),
    logExtent: numArr(r.logExtent),
    logExtentText: textArr(r.logExtent),
    extent: numArr(r.extent),
    extentText: textArr(r.extent),
    ticks: numArr(r.ticks),
    ticksText: textArr(r.ticks),
    tickCoords: numArr(r.tickCoords),
    tickCoordsText: textArr(r.tickCoords),
    splitLineShow: r.splitLineShow,
    splitLineTicks: numArr(r.splitLineTicks),
    splitLineTicksText: textArr(r.splitLineTicks),
    splitLineCoords: numArr(r.splitLineCoords),
    splitLineCoordsText: textArr(r.splitLineCoords),
    labels: r.labels,
    labelOffset: num(r.labelOffset),
    labelOffsetText: text(r.labelOffset),
    labelRotation: num(r.labelRotation),
    labelRotationText: text(r.labelRotation),
    layoutRotation: num(r.layoutRotation),
    layoutRotationText: text(r.layoutRotation),
    align: r.align,
    verticalAlign: r.verticalAlign,
    onZeroOf: r.onZeroOf,
    onZeroCoord: num(r.onZeroCoord),
    onZeroCoordText: text(r.onZeroCoord),
    startValue: r.startValue == null ? null : num(r.startValue),
    startValueText: r.startValue == null ? null : text(r.startValue),
    valueAxisStart: r.valueAxisStart == null ? null : num(r.valueAxisStart),
    valueAxisStartText: r.valueAxisStart == null ? null : text(r.valueAxisStart),
  });
  return {
    index: gm.componentIndex,
    affine: !!tr,
    rect: numRect(rect),
    rectText: textRect(rect),
    axes: axes.map(a => axisOut(recs.get(a))),
    transform: numArr(tr),
    transformText: textArr(tr),
    invTransform: numArr(inv),
    invTransformText: textArr(inv),
    area: numRect(area),
    areaText: textRect(area),
    series,
    probes,
  };
}

function runEither(c) {
  let r;
  let productionBuild = false;
  try {
    r = run(c, echarts);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    console.log(c.name + ': the development build threw (' + e.message + ')');
    r = run(c, PROD);
    productionBuild = true;
  }
  // check 7: the production build writes the same record
  if (!productionBuild && PROD !== echarts) {
    const p = run(c, PROD);
    const a = JSON.stringify({ g: r.grids, d: r.disc });
    const b = JSON.stringify({ g: p.grids, d: p.disc });

    if (a !== b) r.fails.push({ check: 7, msg: 'the production build records differently' });
  }
  return Object.assign(r, { productionBuild });
}

// ---------- cases ----------

const cases = [];
function add(group, name, option, extra) {
  extra = extra || {};
  const o = clone(option);
  if (!extra.auto) {
    const g = o.grid;
    o.grid = Array.isArray(g) ? g.map(x => Object.assign({ outerBoundsMode: 'none' }, x)) : Object.assign({ outerBoundsMode: 'none' }, g || {});
  }
  cases.push(Object.assign({ name: group + ' ' + name, group, option: o, W: 611, H: 397 }, extra));
}
const VAL = e => Object.assign({ type: 'value' }, e || {});
const TIME = e => Object.assign({ type: 'time' }, e || {});
const CAT = (n, e) => Object.assign({ type: 'category', data: Array.from({ length: n }, (_, i) => 'c' + i) }, e || {});
const scatter = (data, e) => Object.assign({ type: 'scatter', data }, e || {});
const line = (data, e) => Object.assign({ type: 'line', data }, e || {});
const bar = (data, e) => Object.assign({ type: 'bar', data }, e || {});
const PCT = { left: '11.3%', right: '7.7%', top: 33.3, bottom: '9.1%' };
const E1 = [[44.44, 2.03], [71.23, 2.72], [3.3, 0.35]];
const DAY = 86400000;
const T0 = Date.UTC(2024, 0, 1);
const doc = note => ({ auto: true, documentary: true, note });

// 1: control
add('1', 'control: value x value on the integer grid, dyadic extents', {
  xAxis: VAL({ min: 0, max: 256, interval: 32 }), yAxis: VAL({ min: 0, max: 128, interval: 16 }),
  series: [scatter([[12.5, 33.25], [100.75, 64], [256, 128], [0, 0], [56.125, 7.5]]), line([[0, 8], [64, 40], [128, 72], [192, 104]])],
}, { W: 600, H: 400, integer: true, control: true, dyadic: true });

// 2: value x value, fractional rects
add('2', 'percent grid (E1)', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [scatter(E1)] });
add('2', 'size-given grid', { grid: { left: 37.7, top: 21.9, width: '71.3%', height: 213.37 }, xAxis: VAL(), yAxis: VAL(),
  series: [scatter(E1), line([[5.5, 0.9], [33.1, 1.7], [66.6, 2.9]])] });
add('2', 'end+size grid', { grid: { right: '8.2%', width: 377.7, bottom: 41.3, height: 251.9 }, xAxis: VAL(), yAxis: VAL(),
  series: [scatter([[1.37, 17.3], [8.21, 9.1], [4.4, 3.33], [6.07, 12.9]])] }, { W: 617, H: 389 });
// the rect's stored width and height are not (x+w)-x and (y+h)-y here: a port
// that keeps edges and derives w = Right-Left misses
add('2', 'end+size grid where (x+w)-x != w and (y+h)-y != h', { grid: { right: '18.6%', width: 218.9, bottom: 79.19, height: 126.2 },
  xAxis: VAL(), yAxis: VAL(), series: [scatter([[1.37, 17.3], [8.21, 9.1], [4.4, 3.33]]), bar([[2, 11.1], [6, -4.7], [9, 7.7]])] },
{ W: 617, H: 511 });
add('2', 'outerBounds auto shrink', { grid: { left: 0, right: '3.7%', top: 27.1, bottom: '8.9%' }, xAxis: VAL(), yAxis: VAL(),
  series: [scatter([[1.5, 1234567.89], [7.25, 2345678.1], [4.1, 345678.9]])] },
Object.assign({ W: 587, H: 373 }, doc('outerBounds auto: the rect is shrunk by measured label text (the grid-bounds oracle\'s question); '
  + 'the coordinate arithmetic is exact only on this rect')));
add('2', 'legacy containLabel', { grid: { containLabel: true, left: '3.3%', right: '4.1%', top: 29.3, bottom: '6.7%' }, xAxis: VAL(), yAxis: VAL(),
  series: [scatter([[12.5, 3456.78], [37.9, 1234.5], [21.3, 999.9]])] },
Object.assign({ W: 593, H: 367 }, doc('legacy containLabel: the rect comes from measured label text (the grid-bounds oracle\'s question); '
  + 'the coordinate arithmetic is exact only on this rect')));
add('2', 'two grids', {
  grid: [{ left: '7.3%', width: '38.1%', top: 41.7, height: '61.3%' }, { left: '54.9%', right: '5.3%', top: 41.7, bottom: '17.9%' }],
  xAxis: [VAL({ gridIndex: 0 }), VAL({ gridIndex: 1 })], yAxis: [VAL({ gridIndex: 0 }), VAL({ gridIndex: 1 })],
  series: [scatter(E1), scatter([[0.37, 91.3], [0.81, 13.7], [0.55, 47.1]], { xAxisIndex: 1, yAxisIndex: 1 })],
}, { W: 709, H: 383 });

// 3: inverse
add('3', 'x inverse', { grid: PCT, xAxis: VAL({ inverse: true }), yAxis: VAL(), series: [scatter(E1), line([[10.1, 0.5], [50.5, 1.5], [90.9, 2.5]])] });
add('3', 'y inverse', { grid: PCT, xAxis: VAL(), yAxis: VAL({ inverse: true }), series: [scatter(E1), line([[10.1, 0.5], [50.5, 1.5], [90.9, 2.5]])] });
add('3', 'both inverse, bars', { grid: PCT, xAxis: VAL({ inverse: true }), yAxis: VAL({ inverse: true }),
  series: [bar([[2.8, 4.85], [4.08, 14.75], [4.53, 20.03]]), scatter([[3.1, 7.7]])] }, { W: 505, H: 452 });

// 4: time x value
const daily = n => Array.from({ length: n }, (_, i) => T0 + i * DAY);
add('4', 'daily line and scatter', { grid: PCT, xAxis: TIME(), yAxis: VAL(), series: [
  line(daily(9).map((t, i) => [t, i === 4 ? null : 10 + ((i * 37) % 11) * 1.1])),
  scatter(daily(9).map((t, i) => [t + 3600000 * i, 3 + ((i * 7) % 5) * 0.7]))] });
add('4', 'daily bars', { grid: PCT, xAxis: TIME(), yAxis: VAL(), series: [
  bar(daily(20).filter((_, i) => i !== 7).map((t, i) => [t, 10 + ((i * 37) % 11)]))] });
add('4', 'ms-scale bars: a non-integer containShape mapping (D4)', { grid: PCT, xAxis: TIME(), yAxis: VAL(), series: [
  bar([[T0, 3], [T0 + 7, 5], [T0 + 20, 2]])] }, { pinsD4: true });
add('4', 'time on y, bars lying down', { grid: PCT, xAxis: VAL(), yAxis: TIME(), series: [
  bar([[5, T0], [3, T0 + DAY], [2, T0 + 3 * DAY]])] }, { W: 613, H: 391 });
add('4', 'time x time', { grid: PCT, xAxis: TIME(), yAxis: TIME(), series: [
  scatter([[T0, T0 + 5 * DAY], [T0 + 2 * DAY + 3600000, T0 + DAY], [T0 + 4 * DAY + 1234567, T0 + 3 * DAY + 7654321]])] }, { W: 617, H: 403 });

// 5: log (no matrix)
add('5', 'category x log, bars [0.5,100,1000] (D5)', { grid: PCT, xAxis: CAT(3), yAxis: { type: 'log' }, series: [bar([0.5, 100, 1000])] },
  { pinsD5: true });
add('5', 'value x log [5,50,500]', { grid: PCT, xAxis: VAL(), yAxis: { type: 'log' }, series: [scatter([[1, 5], [2, 50], [3, 500]])] },
  { pinsD5: true });
// base 2: Math.log(2^k)/Math.log(2) === k for every |k| < 29, so only an
// extent reaching 2^31 (log extent [26, 31]) tells the stored log end from the
// re-derived one; [5,50,500] on base 2 does not
add('5', 'log base 2 x value [1e8,1.2e9,2e9]', { grid: PCT, xAxis: { type: 'log', logBase: 2 }, yAxis: VAL(),
  series: [scatter([[1e8, 1], [1.2e9, 2], [2e9, 3]]), line([[1.5e8, 0.5], [7e8, 1.5], [1.9e9, 2.5]])] }, { pinsD5: true, W: 619, H: 401 });

// 6: category
add('6', 'category x value, boundaryGap true: bars and line', { grid: PCT, xAxis: CAT(5), yAxis: VAL(),
  series: [bar([5.1, 3.3, -2.7, 8.9, 4.4]), line([2.2, 6.1, 1.7, 3.9, 7.3])] });
add('6', 'category x value, boundaryGap false: line', { grid: PCT, xAxis: CAT(6, { boundaryGap: false }), yAxis: VAL(),
  series: [line([2.2, 6.1, 1.7, 3.9, 7.3, 0.4])] });
add('6', 'value x category: horizontal bars', { grid: PCT, xAxis: VAL(), yAxis: CAT(4), series: [bar([5.1, 3.3, 8.9, 4.4])] });
add('6', 'category inverse', { grid: PCT, xAxis: CAT(4, { inverse: true }), yAxis: VAL(), series: [bar([5.1, 3.3, 8.9, 4.4])] });
add('6', 'n = 1 category', { grid: PCT, xAxis: CAT(1), yAxis: VAL(), series: [bar([7.7])] });

// 7: degenerate
add('7', 'width-0 grid', { grid: { left: 100, width: 0, top: 33.3, bottom: '9.1%' }, xAxis: VAL(), yAxis: VAL(),
  series: [scatter([[1, 1.3], [2, 2.7]])] }, { W: 600 });
add('7', 'no series, integer grid', { xAxis: VAL(), yAxis: VAL(), series: [] }, { W: 600, H: 400, integer: true, control: true });
add('7', 'no series, percent grid', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [] });
add('7', 'min == max', { grid: PCT, xAxis: VAL({ min: 3, max: 3 }), yAxis: VAL(), series: [scatter([[3, 1.1], [3, 2.9]])] });

// 8: series
add('8', 'scatter and effectScatter', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  scatter([[1.37, 17.3], [8.21, 9.1], [-4.4, 3.33]]), { type: 'effectScatter', data: [[6.07, -12.9], [2.2, 0.7]] }] }, { W: 619, H: 401 });
add('8', 'stacked line areas', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  line([[1, 3], [2, 5], [3.5, 2], [5, 4]], { stack: 's', areaStyle: {} }),
  line([[1, 1], [2, 2.5], [3.5, null], [5, 1.5]], { stack: 's', areaStyle: {} })] }, { W: 619, H: 401 });
add('8', 'bars plain and stacked', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  bar([[1, 5.3], [2, -3.1], [4, 2.2]]), bar([[1, 1.7], [2, 2.9], [4, 1.1]], { stack: 't' }), bar([[1, 0.9], [2, 1.3], [4, 2.6]], { stack: 't' })] },
{ W: 619, H: 401 });
add('8', 'bars barMinHeight', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  bar([[1, 0.01], [2, -0.02], [3, 5.5], [4, 0]], { barMinHeight: 10 })] }, { W: 619, H: 401 });
add('8', 'bars clipped past min and max', { grid: PCT, xAxis: VAL({ min: 1.5, max: 4.5 }), yAxis: VAL({ min: -2, max: 4 }), series: [
  bar([[1, 3], [2, 6], [3, -5], [4, 3.3], [6, 1]])] }, { W: 619, H: 401 });
add('8', 'pictorialBar', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  { type: 'pictorialBar', symbol: 'rect', data: [[1, 5.3], [2, -3.1], [4, 2.2]] }] }, { W: 619, H: 401 });
add('8', 'pictorialBar stacked', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  { type: 'pictorialBar', symbol: 'rect', stack: 't', data: [[1, 5.3], [2, 3.1], [4, 2.2]] },
  { type: 'pictorialBar', symbol: 'rect', stack: 't', data: [[1, 1.7], [2, 2.9], [4, 1.1]] }] }, { W: 619, H: 401 });
add('8', 'candlestick raw points', { grid: PCT, xAxis: CAT(4), yAxis: VAL(), series: [
  { type: 'candlestick', data: [[20.1, 34.3, 10.7, 38.2], [40.5, 35.1, 30.3, 50.9], [31.7, 38.8, 33.3, 44.4], [38.9, 15.2, 5.5, 42.1]] }] });
add('8', 'graph on cartesian', { grid: PCT, xAxis: VAL(), yAxis: VAL(), series: [
  { type: 'graph', coordinateSystem: 'cartesian2d', layout: 'none', data: [[1.3, 2.7], [4.1, 0.9], [2.2, 3.3]],
    links: [{ source: 0, target: 1 }, { source: 1, target: 2 }] }] }, { W: 619, H: 401 });

// 9: probe-dense cartesians
add('9', 'probes: value x value, both inverse', { grid: PCT, xAxis: VAL({ inverse: true }), yAxis: VAL({ inverse: true }),
  series: [scatter(E1)] }, { W: 631, H: 409, denseProbes: true });
add('9', 'probes: time x value, half milliseconds', { grid: PCT, xAxis: TIME(), yAxis: VAL(),
  series: [scatter([[T0 + 0.5, 1.3], [T0 + 1234.5, 2.7], [T0 + 99999, 0.2]])] }, { W: 613, H: 389, denseProbes: true });
add('9', 'probes: category x value', { grid: PCT, xAxis: CAT(7), yAxis: VAL(), series: [bar([1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7])] },
  { W: 613, H: 389, denseProbes: true });
add('9', 'probes: value x log', { grid: PCT, xAxis: VAL(), yAxis: { type: 'log' }, series: [scatter([[1.5, 3], [2.5, 30], [3.5, 700]])] },
  { W: 613, H: 389, denseProbes: true, pinsD5: true });

// A-H: each case makes one port mutant visible in the recorded numbers
// (`kills`: self-check 6 replays the record under the mutant and needs at
// least one number to move).
const kill = (...ids) => ({ kills: ids });
// A: the last category of a band axis is n === 1, which linearMap returns
// verbatim as r1. Only an inverse extent can tell: on [0, w] the computed
// (r1 - r0) * 1 + r0 equals r1 for every w and count (2e6 random trials).
add('A', 'band x inverse, bars to the last category', { grid: { left: 37.7, width: 300.1, top: 33.3, bottom: '9.1%' },
  xAxis: CAT(4, { inverse: true }), yAxis: VAL(), series: [bar([5.1, 3.3, 8.9, 4.4]), line([2.2, 6.1, 1.7, 3.9])] }, kill('linearMapVerbatimEnd'));
add('A', 'band y inverse, horizontal bars to the last category', { grid: { left: '11.3%', right: '7.7%', top: 21.9, height: 201.1 },
  xAxis: VAL(), yAxis: CAT(5, { inverse: true }), series: [bar([5.1, 3.3, 8.9, 4.4, 6.6])] }, kill('linearMapVerbatimEnd'));
// B: the bar band from the stored width, not |(x+w) - x|
const XW = { right: '18.6%', width: 218.9, bottom: 79.19, height: 126.2 }; // 617x511: (x+w)-x != w and (y+h)-y != h
// 5 categories: w/4 and ((x+w)-x)/4 give the same offset and size
add('B', 'category bars where (x+w)-x != w', { grid: XW, xAxis: CAT(5), yAxis: VAL(), series: [bar([5.1, 3.3, 8.9, 4.4, 6.6])] },
  Object.assign({ W: 617, H: 511 }, kill('bandFromEdges')));
add('B', 'value-base bars where (x+w)-x != w', { grid: XW, xAxis: VAL(), yAxis: VAL(),
  series: [bar([[1, 5.3], [2.5, 3.1], [4, 2.2], [7, 4.4]])] }, Object.assign({ W: 617, H: 511 }, kill('bandFromEdges')));
// C: containShape of a single value reads pxInit = the raw rect's width
add('C', 'containShape SINGLE [[3,5]] on a size-given grid where (x+w)-x != w', {
  grid: { left: 88.73, width: '76.7%', top: 57.56, height: 179.73 }, xAxis: VAL(), yAxis: VAL(), series: [bar([[3, 5]])] },
Object.assign({ W: 587, H: 553 }, kill('pxInitFromEdges')));
// D: outerBounds 'auto' with nothing overflowing keeps the raw rect (checked)
add('D', 'outerBounds auto, size-given, no shrink, (x+w)-x != w', { grid: XW, xAxis: VAL(), yAxis: VAL(),
  series: [scatter([[1.37, 1.7], [8.21, 9.1], [4.4, 3.33]])] }, Object.assign({ W: 617, H: 511, auto: true }, kill('shrinkFromEdges')));
// E: one horizontal key: mergeLayoutParam borrows the default left of 15%
add('E', 'grid width only horizontally: the default left is borrowed', { grid: { width: '61.7%', top: 33.3, bottom: '9.1%' },
  xAxis: VAL(), yAxis: VAL(), series: [scatter(E1)] },
Object.assign({ expectRect: (pp, W) => ({ x: pp('15%', W), width: pp('61.7%', W) }) }, kill('noBorrowDefault')));
// F: left 'auto' is a key without a value: the default right of 10% is borrowed
add('F', "left 'auto' with width 300: the default right is borrowed", { grid: { left: 'auto', width: 300, top: 33.3, bottom: '9.1%' },
  xAxis: VAL(), yAxis: VAL(), series: [scatter(E1)] },
Object.assign({ expectRect: (pp, W) => ({ x: W - pp('10%', W) - 300, width: 300 }) }, kill('autoAsValue')));
// G: a column sits at coord + offset, not at the centre of its band cell
add('G', 'category bars, vertical: the cell centre is not the coord', { grid: PCT, xAxis: CAT(7), yAxis: VAL(),
  series: [bar([1, 2, 3, 4, 1, 2, 3])] }, kill('cellCentre'));
add('G', 'category bars, horizontal: the cell centre is not the coord', { grid: PCT, xAxis: VAL(), yAxis: CAT(6),
  series: [bar([1, 2, 3, 4, 1, 2])] }, Object.assign({ W: 619, H: 401 }, kill('cellCentre')));
// H: the clip's width is x2 minus the CLIPPED x
add('H', 'horizontal bars clipped on the left (x min 2)', { grid: PCT, xAxis: VAL({ min: 2, max: 10 }), yAxis: CAT(4),
  series: [bar([5.5, 8.3, 12.7, 0.5])] }, kill('clipFromOriginal'));
add('H', 'horizontal bars on an inverse x, clipped on the right and past max', { grid: PCT, xAxis: VAL({ min: 2, max: 10, inverse: true }),
  yAxis: CAT(4), series: [bar([5.5, 12.7, 8.3, 1.5])] }, kill('clipFromOriginal'));

// L: the axis-label frame beyond bottom/left (batch 43 audit, ORACLE 1). Each
// case names what it pins (`pins`, self-check 6: at least one recorded number
// or label bites):
//   N1            a top axis on the other axis' zero keeps +rotate (the port
//                 negates for every top axis)
//   topNegates    a top axis off zero turns its labels by -rotate
//   N2            offset or margin that v*96/96 moves: a label moves when both
//                 are put through it
//   offsetOutOfT  on zero with an offset: a label moves when the offset is also
//                 added to t = labelOffset + dir*margin
//   inside        axisLabel.inside: a label moves when the direction is not flipped
//   alignPerModel axisTick.alignWithLabel without splitLine's: the split lines
//                 are band-shifted, the ticks are not, and they differ
//   bandedMarks   a band-shifted tick or split line the port's global round trip
//                 (CategoryMarks) misses
//   popsLast      the last category is off the split-line interval: popped, and
//                 the far edge pushed from it (built from the tick before it, the
//                 edge moves)
//   edgesNotSize  (x+w)-x != w and (y+h)-y != h on the rect
const pins = (...ids) => ({ pins: ids });
const NEGC = [5.1, -3.3, 8.9, -1.7, 4.4];
add('L', 'top category x on the y zero, rotate 45 (N1)', { grid: PCT,
  xAxis: CAT(5, { position: 'top', axisLabel: { rotate: 45 } }), yAxis: VAL(), series: [bar(NEGC)] }, pins('N1'));
add('L', 'top category x off the y zero (onZero false), rotate 45', { grid: PCT,
  xAxis: CAT(5, { position: 'top', axisLine: { onZero: false }, axisLabel: { rotate: 45 } }), yAxis: VAL(), series: [bar(NEGC)] },
pins('topNegates'));
add('L', 'top x and right y off zero, offset 2.7, margin 12.3 (N2)', { grid: PCT,
  xAxis: VAL({ position: 'top', scale: true, offset: 2.7, axisLabel: { margin: 12.3 } }),
  yAxis: VAL({ position: 'right', scale: true, offset: 2.7, axisLabel: { margin: 12.3 } }),
  series: [scatter([[23.1, 51.7], [37.9, 88.3], [30.2, 64.9]])] }, pins('N2'));
add('L', 'top x and right y on zero, offset 2.7, margin 12.3: the offset stays out of t', { grid: PCT,
  xAxis: VAL({ position: 'top', offset: 2.7, axisLabel: { margin: 12.3 } }),
  yAxis: VAL({ position: 'right', offset: 2.7, axisLabel: { margin: 12.3 } }),
  series: [scatter([[-13.1, 21.7], [27.9, -18.3], [9.2, 34.9]])] }, pins('offsetOutOfT'));
add('L', 'labels inside on x and on y', { grid: PCT,
  xAxis: CAT(5, { axisLabel: { inside: true } }), yAxis: VAL({ axisLabel: { inside: true } }), series: [bar([5.1, 3.3, 8.9, 1.7, 4.4])] },
pins('inside'));
add('L', 'labels inside on top x and right y, rotate -30', { grid: PCT,
  xAxis: CAT(5, { position: 'top', axisLine: { onZero: false }, axisLabel: { inside: true, rotate: -30 } }),
  yAxis: VAL({ position: 'right', axisLabel: { inside: true, rotate: -30 } }), series: [bar([5.1, 3.3, 8.9, 1.7, 4.4])] },
pins('inside', 'topNegates'));
add('L', 'category x: axisTick alignWithLabel, splitLine not', { grid: PCT,
  xAxis: CAT(6, { axisTick: { alignWithLabel: true }, splitLine: { show: true } }), yAxis: VAL(),
  series: [bar([5.1, 3.3, 8.9, 1.7, 4.4, 6.6])] }, pins('alignPerModel', 'bandedMarks'));
// the last category is off the split lines' interval: fixOnBandTicksCoords pops
// it and pushes the far band edge from it, not from the tick before
add('L', 'category x: splitLine interval 1 over 6 categories pops the off-interval last', { grid: PCT,
  xAxis: CAT(6, { splitLine: { show: true, interval: 1 } }), yAxis: VAL(),
  series: [bar([5.1, 3.3, 8.9, 1.7, 4.4, 6.6])] }, pins('bandedMarks', 'popsLast'));
// 611 x 397: (77.13 + 498.7) - 77.13 != 498.7 and (47.97 + 286.18) - 47.97 != 286.18
const XWH = { left: 77.13, width: 498.7, top: 47.97, height: 286.18 };
add('L', '(x+w)-x != w and (y+h)-y != h: category x inverse, value y inverse', { grid: XWH,
  xAxis: CAT(7, { inverse: true, splitLine: { show: true } }), yAxis: VAL({ inverse: true }),
  series: [bar([5.1, 3.3, -2.7, 8.9, 4.4, 6.6, 2.2])] }, pins('edgesNotSize', 'bandedMarks'));
add('L', '(x+w)-x != w and (y+h)-y != h: value x, category y inverse', { grid: XWH,
  xAxis: VAL(), yAxis: CAT(5, { inverse: true, splitLine: { show: true } }),
  series: [bar([5.1, 3.3, 8.9, 1.7, 4.4])] }, pins('edgesNotSize', 'bandedMarks'));

// ---------- run, check and write ----------

{
  const names = new Set();
  for (const c of cases) {
    if (names.has(c.name)) throw new Error('two cases named ' + c.name);
    names.add(c.name);
  }
}

const CHECKS = [1, 2, 3, 4, 5, 6, 7];
const tally = {};
CHECKS.forEach(k => { tally[k] = [0, 0]; });
const failed = [];

function recordOf(c) {
  const r = runEither(c);
  const affine = r.grids.some(g => g.affine);
  const fractional = !c.integer;
  const d = r.disc;
  // check 6
  if (affine && !c.control && d.affineVsPerAxis < 1) r.fails.push({ check: 6, msg: 'affine, but A = P on every recorded coordinate' });
  if (fractional && d.portVsUpstream < 1) r.fails.push({ check: 6, msg: 'fractional, but the port formula matches upstream everywhere' });
  if (c.pinsD4 && !(d.maxAffineShift > 1)) r.fails.push({ check: 6, msg: 'pinsD4, but |A - P| <= 1 px' });
  if (c.pinsD5 && d.logNormalize < 1) r.fails.push({ check: 6, msg: 'pinsD5, but every log normalize agrees' });
  (c.kills || []).forEach(id => {
    if (!(d.kills[id] >= 1)) r.fails.push({ check: 6, msg: 'mutant ' + id + ' changes no recorded number' });
  });
  (c.pins || []).forEach(id => {
    if (!(d.pins[id] >= 1)) r.fails.push({ check: 6, msg: 'pins ' + id + ', but it bites nowhere' });
  });
  if (c.control && (d.affineVsPerAxis !== 0 || d.portVsUpstream !== 0)) {
    r.fails.push({ check: 6, msg: 'control, but A != P on ' + d.affineVsPerAxis + ' and Q != U on ' + d.portVsUpstream + ' coordinates' });
  }
  const rec = { name: c.name, group: c.group, W: c.W, H: c.H, option: r.option };
  const byCheck = {};
  r.fails.forEach(f => { (byCheck[f.check] = byCheck[f.check] || []).push(f.msg); });
  CHECKS.forEach(k => { tally[k][byCheck[k] ? 1 : 0]++; });
  const miss = Object.keys(byCheck).map(k => 'self-check ' + k + ': ' + byCheck[k].slice(0, 4).join('; ')
    + (byCheck[k].length > 4 ? ' (+' + (byCheck[k].length - 4) + ' more)' : '')).join(' | ');
  if (miss) failed.push(c.name + (c.deferred ? ' (deferred anyway)' : '') + ': ' + miss);
  if (c.deferred || miss) {
    rec.deferred = true;
    rec.why = c.deferred ? c.deferred + (miss ? '; and ' + miss : '') : miss;
  }
  if (c.documentary) {
    rec.documentary = true;
    rec.note = c.note;
  }
  if (r.productionBuild) rec.productionBuild = true;
  rec.integer = !!c.integer;
  rec.control = !!c.control;
  rec.affine = affine;
  rec.fractional = fractional;
  rec.pinsD4 = !!c.pinsD4;
  rec.pinsD5 = !!c.pinsD5;
  rec.discriminates = {
    compared: d.compared,
    affineVsPerAxis: d.affineVsPerAxis,
    maxAffineShiftPx: num(d.maxAffineShift),
    maxAffineShiftPxText: text(d.maxAffineShift),
    portVsUpstream: d.portVsUpstream,
    logNormalize: d.logNormalize,
  };
  if (c.kills) rec.discriminates.kills = d.kills;
  if (c.pins) rec.discriminates.pins = d.pins;
  if (r.grids.length === 1) {
    const g = r.grids[0];
    delete g.index;
    delete g.affine;
    Object.assign(rec, g);
  } else {
    rec.grids = r.grids.map(g => { delete g.affine; return g; });
  }
  return rec;
}

const out = { source: 'ECharts ' + echarts.version, cases: cases.map(recordOf) };

// A compact, deterministic writer: a value whose one-line JSON fits in 150
// characters stays on one line. A number JSON.stringify would write as an
// integer literal past 2^63 goes out in exponent form instead.
const BIG = 9223372036854775808;
function prim(v) {
  if (typeof v === 'number' && Number.isFinite(v) && Math.abs(v) >= BIG && Math.abs(v) < 1e21) return v.toExponential();
  return JSON.stringify(v);
}
function oneLine(v) {
  if (v === null || typeof v !== 'object') return prim(v);
  if (Array.isArray(v)) return '[' + v.map(oneLine).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const flat = oneLine(v);
  if (flat.length + ind.length <= 150 || v === null || typeof v !== 'object') return flat;
  const inner = ind + ' ';
  if (Array.isArray(v)) return '[\n' + v.map(x => inner + fmt(x, inner)).join(',\n') + '\n' + ind + ']';
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n')
    + '\n' + ind + '}';
}
const json = fmt(out, '');

const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks (pass/cases): ' + CHECKS.map(k => k + ' ' + tally[k][0] + '/' + (tally[k][0] + tally[k][1])).join(', '));
fs.writeFileSync(OUT, json + '\n');
const nDef = out.cases.filter(c => c.deferred).length;
const nDoc = out.cases.filter(c => c.documentary && !c.deferred).length;
const all = out.cases.flatMap(c => (c.grids || [c]));
const items = all.reduce((n, g) => n + g.series.reduce((m, s) => m + s.items.length, 0), 0);
const probes = all.reduce((n, g) => n + g.probes.length, 0);
const labels = all.reduce((n, g) => n + g.axes.reduce((m, a) => m + a.labels.length, 0), 0);
console.log('wrote', OUT, (out.cases.length - nDef - nDoc) + ' compared + ' + nDoc + ' documentary + ' + nDef + ' deferred cases; '
  + items + ' items, ' + probes + ' probes, ' + labels + ' labels');
const unexpected = cases.filter(c => !c.deferred).filter(c => out.cases.find(o => o.name === c.name).deferred);
if (unexpected.length) {
  console.log('FAILED: ' + unexpected.length + ' case(s) did not pass the self-checks');
  process.exit(1);
}
process.exit(0);
