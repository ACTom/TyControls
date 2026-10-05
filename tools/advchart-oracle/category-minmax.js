// Upstream's own answers for min / max / startValue on a CATEGORY axis: which
// ordinal extent the axis ends up with (and whether it turns blank or inverse),
// where every category lands, which labels, ticks and split lines the narrowed
// axis builds, how bars, lines, areas and scatter outside the extent are
// clipped, which line symbols are created, and where the axis pointer shows.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, renders once to an SVG string, and
// reads the live objects; the pointer probes then dispatch updateAxisPointer
// at integer pixels. Every case is 600x400 with grid 50/50/40/40 and
// outerBoundsMode 'none' unless it says otherwise, so the rect is
// (50, 40, 500, 320). Categories are a..j and the bar data
// [5,20,36,10,10,20,8,15,30,12] unless the case says otherwise.
//
// Top level: source (the ECharts version), cap (CAP below), probeValues (the
// ordinals -3..13 that contain[] and coords[] are taken at), cases[].
//
// Per case:
//   name, group, W, H, option   the canvas and the option as run (animation
//             false; JSON only).
//   deferred, why               deferred by declaration (upstream answer
//             recorded, the port does not do it) or a self-check failed.
//   productionBuild             the development build threw; the record is
//             the production build's.
//   rect      grid coordinateSystem.getRect() {x,y,width,height} (+ rectText)
//   area      cartesian.getArea() {x,y,width,height} (+ areaText)
//   axes[]    x axes, then y axes:
//     dim, index, type, inverse (final, after the backwards-means-inverse
//     toggle), px[2] (axis.getExtent(), local pixels, + pxText)
//     effective[2] (scale.getExtent(), + effectiveText), mapping[2] | null
//     (getExtentUnsafe(MAPPING): containShape's widening, + mappingText)
//     category axes only (null / absent on a value axis):
//       onBand, blank (scale.isBlank()), nCat (ordinalMeta categories length)
//       ctnShp (rawExtentInfo asks for containShape)
//       raw {dataMM[2], noZoomEffMM[2], fixMM[2], isBlank, tggAxInv,
//            startValue}   rawExtentInfo._i as TEXT (readable twins; NaN,
//            Infinity, -0 spelled out; startValue null when unset)
//       count     scale.count() as TEXT ('-Infinity' on a blank axis)
//       bandWidth axis.getBandWidth() (calcBandWidth with min 1; 1 on a blank
//                 axis) (+ bandWidthText); bandW: the same before the min of
//                 1 (|px1-px0| / (mapSpan + onBand)), null when not finite --
//                 the band fixOnBandTicksCoords shifts by
//       contain[17]  scale.contain(v) for v = -3..13 (PROBE_VALUES)
//       coords[17]   toGlobalCoord(dataToCoord(v)) for v = -3..13, hex only
//                    (NaN on a blank axis)
//       interval  {option: 'auto' | number (axisLabel.interval), used: the
//                 label interval the axis built with ('Infinity' when the auto
//                 interval is infinite; null on a blank axis), unitSpan: hex |
//                 null (+ unitSpanText) -- dataToCoord(e0+1) - dataToCoord(e0)
//                 as calculateCategoryInterval computes it, when auto and
//                 e1 - e0 >= 1 (below that it returns 0 before computing one);
//                 negative on an inverse axis}
//       labels[]  getViewLabels() in order: {value (the ordinal; -0 written as
//                 0 -- the extent's hex keeps the sign), text (the formatted
//                 label, '' outside the categories), offInterval, shown (the
//                 label_<value> element is in the scene, not ignored, and its
//                 text is not empty: drawn in the SVG)}
//       ticks, splitLines   getTicksCoords() with the axisTick / splitLine
//                 model as parallel arrays: values, globalCoords (hex),
//                 drawn (a ticks_<value> / line_<value> element is in the
//                 scene and not ignored), and onBand (one flag for the list)
//       splitAreas  the values of the area_<value> elements in the scene
//   series[]  in index order: index, type, filtered (legend-filtered)
//     bar:     bandWidth, offset, size (data.getLayout, hex + Text) and
//              items[] per raw data index {class ('drawn' | 'hidden': clipped
//              away whole | 'none': no element), layout [x,y,w,h] hex |
//              null (data.getItemLayout, unclipped, signed), box [l,t,r,b] hex
//              | null (the drawn shape after the clip, normalized)}
//     line:    points[] per data item [x, y] as FLOAT32 bit patterns (8 hex
//              digits; data.getLayout('points') is a Float32Array), every item
//              including the ones outside the extent; clip {x,y,width,height}
//              hex (+ clipText): the clip path on the line group, or null;
//              symbols[]: the data indices that got a symbol element
//     scatter: symbols[] the data indices with a symbol element and
//              symbolPoints[] their element [x, y] (hex doubles)
//   discriminates  (a discriminating case only) {kind: 'clip' |
//             'unitSpan', ...}: clip: clipWithoutCeil, clipWithoutFloor
//             [x,y,w,h] hex (the two port mutants' rects); unitSpan: maxW
//             (+ Text), closedFormUnitSpan (+ Text), closedFormInterval
//   probes[]  (pointer cases) one per dispatched point, in dispatch order:
//     x, y (the integer pixels dispatched), axisDim, axisValue (the
//     updateAxisPointer event's value on the category axis, or null),
//     dataIndex, seriesIndex (the event's, or null), pointer: null (nothing
//     shown) | {type: 'line', shape [x1,y1,x2,y2] hex} | {type: 'rect',
//     shape [x,y,width,height] hex} -- the pointer element's shape before
//     subPixelOptimize (the Line carries subPixelOptimize: true)
//
// Self-checks (a case that fails any is recorded deferred with the reason and
// the run exits 1; tallied as pass/cases):
//   1 extent: the S1 transcription -- min/max/startValue parsed (null unset;
//     string: category lookup, no trim, NaN if absent; else JS ToNumber then
//     Math.round; 'dataMin'/'dataMax' pins dataMM), defaults 0 / nCat-1 (NaN
//     without categories; dataMM for a declared empty list), NaN for a
//     non-finite end, reversal toggles inverse unless
//     legacyMinMaxDontInverseAxis, startValue widens and pins an unpinned end,
//     setExtent refuses a reversed or non-finite pair ([Infinity, -Infinity]
//     stays) -- gives raw, effective, count, inverse and blank.
//   2 mapping: ctnShp from the option and the bar keys; w2 = w * span / px
//     with px from the rect; mapping = [min(e0, e0 - w2/2), max(e1, e1 + w2/2)]
//     off-band, or none.
//   3 coords: band-inset extent (count from the effective extent), normalize
//     over mapping || effective (0.5 when flat), linearMap with verbatim ends,
//     toGlobalCoord; gives every coords[v], the px, the area, and bandWidth
//     (max(1, w), 1 when w is NaN); contain[v] = inside mapping || effective
//     and 0 <= v < nCat.
//   4 ticks: ordinalScaleCreateTicks from the used interval gives the labels'
//     values and offInterval; with axisTick / splitLine interval ('auto'
//     follows the labels) and fixOnBandTicksCoords (shift by bandW / 2, drop a
//     trailing offInterval tick, push e1 + 1 at last + bandW) it gives ticks
//     and splitLines values and coords; the auto unitSpan equals
//     coord(e0+1) - coord(e0) over mapping || effective; split areas are the
//     splitArea tick list minus its last.
//   5 bars: bandWidth = max(1, w); every layout is the bar recipe over the
//     per-axis dataToPoint; every box is BarView's cartesian clip of the
//     layout against the area (none when clip is false), hidden iff clipped
//     whole.
//   6 lines: points = Math.fround(dataToPoint) for every item; clip = the
//     area, x/y -= lw/2, w/h += lw, w = ceil(w), x not whole -> x = floor(x)
//     and w + 1; clip false widens the value direction by max(w, h) each way;
//     symbols = (the non-offInterval label ordinals when showAllSymbol is
//     false, or 'auto' and a symbol * 1.5 exceeds a band) and (inside
//     area +- 0.1 when clip is on); scatter: inside getArea(0.1) when clip is
//     on, at dataToPoint (scatter keeps doubles: one layout per item).
//   7 pointer: inside the grid, t = linearMap(local, band-inset extent,
//     [0, 1]), v = Math.round(t * (m1 - m0) + m0), shown iff not blank and
//     contain(v); dataIndex / seriesIndex: per series the items whose coord is
//     within 0.5 px of coord(v) (pixel distance, a tie goes to diff >= 0), the
//     series whose first such item's ordinal is closest to v wins (its first
//     item; with min 5 max 5 every item sits on one pixel: dataIndex 0);
//     axisValue = v (axisPointer.snap is off, checked; -0 stays -0 upstream and
//     is written 0); the
//     line at toGlobalCoord(dataToCoord(value,
//     clamp)) across the other axis' global extent, the shadow rect
//     [max(lo, p - bw/2), min(p + bw/2, hi)] with bw = max(1, w).
//   disc: (cases marked discriminates) clip: the clip rect without the
//     ceil step, and without the floor + width++ step, both differ from
//     upstream's; unitSpan: the closed-form len / (count - 1) interval differs
//     from the one used (and the transcription from upstream's unitSpan gives
//     the one used, under check 4).
//   prod: the production build writes the same record.
//
// Deferred by declaration (and checked by nature; a mismatch is reported as
// "deferral not as declared" and fails the run):
//   declared-empty category list (xAxis.data: []) whose extent comes from the
//   series data (upstream's backward-compatibility path); a count past
//   CAP = 2^20 categories in the window (the port guards it).
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside the case- and axis-level ones; item
// arrays carry hex only; line points are Float32 bits (8 hex digits). The
// readable twin of -0 is '-0'.
//
//   node tools/advchart-oracle/category-minmax.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD_PATH = DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js');
const PROD = require(PROD_PATH);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-category-minmax.json');

// This generator's own assertions: never retried through the production build.
class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function hex32(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat32(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const hexOrNull = v => (v == null ? null : hex(v));
const textOrNull = v => (v == null ? null : text(v));
const hexArr = a => (a ? a.map(hex) : null);
const textArr = a => (a ? a.map(text) : null);
const same = (a, b) => Object.is(a, b);
const sameArr = (a, b) => (a == null && b == null) || (a != null && b != null && a.length === b.length && a.every((v, i) => same(v, b[i])));
const RECT = ['x', 'y', 'width', 'height'];
const plainRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const hexRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const textRect = r => ({ x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) });
const sameRect = (a, b) => RECT.every(k => same(a[k], b[k]));
const finiteRect = r => r && RECT.every(k => typeof r[k] === 'number' && Number.isFinite(r[k]));
const clone = o => JSON.parse(JSON.stringify(o));
const isFiniteNum = v => v != null && isFinite(v);

const MAPPING = 1; // scaleMapper.ts SCALE_EXTENT_KIND_MAPPING
const CAP = 2 ** 20; // the port's category-count guard (audit D8)
const PROBE_VALUES = Array.from({ length: 17 }, (_, i) => i - 3);

// ---------- transcriptions ----------

// ECMAScript ToNumber for what JSON can carry (null is handled by the caller).
const JS_WS = /^[\s\uFEFF\xA0]+|[\s\uFEFF\xA0]+$/g;
function stringToNumber(s) {
  const t = s.replace(JS_WS, '');
  if (t === '') return 0;
  if (/^[+-]?Infinity$/.test(t)) return t[0] === '-' ? -Infinity : Infinity;
  if (/^0[xX][0-9a-fA-F]+$/.test(t)) return parseInt(t.slice(2), 16);
  if (/^0[oO][0-7]+$/.test(t)) return parseInt(t.slice(2), 8);
  if (/^0[bB][01]+$/.test(t)) return parseInt(t.slice(2), 2);
  if (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t)) return parseFloat(t);
  return NaN;
}
function arrayToString(a) {
  return a.map(e => (e == null ? '' : Array.isArray(e) ? arrayToString(e) : typeof e === 'object' ? '[object Object]' : String(e))).join(',');
}
function toNumber(v) {
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (typeof v === 'number') return v;
  if (typeof v === 'string') return stringToNumber(v);
  if (Array.isArray(v)) return stringToNumber(arrayToString(v));
  return NaN; // a plain object: '[object Object]'
}

// scaleRawExtentInfo.ts parseAxisModelMinMax + Ordinal.ts parse
function parseOrdinal(v, catMap) {
  if (v == null) return null;
  if (typeof v === 'number' && v !== v) return NaN;
  if (typeof v === 'string') {
    const o = catMap.get(v);
    return o == null ? NaN : o;
  }
  return Math.round(toNumber(v));
}

// S1: the ordinal branch of the ScaleRawExtentInfo constructor, makeFinal and
// the adopt step (scaleRawExtentInfo.ts:180-361, 706-721).
// inp: {min, max, startValue (the option values), cats (the category values),
// declaredEmpty (axis data is []), dataMM (the union of the series' ordinals,
// [Infinity, -Infinity] when none), optionInverse, legacy}
function ordinalExtent(inp) {
  const catMap = new Map();
  inp.cats.forEach((c, i) => catMap.set(c, i)); // createHashMap: a later duplicate wins
  const nCat = inp.cats.length;
  const dataMM = inp.dataMM.slice();
  if (!(isFinite(dataMM[1] - dataMM[0]) && dataMM[1] - dataMM[0] >= 0)) dataMM[0] = dataMM[1] = NaN;
  const eff = [];
  const fix = [false, false];
  if (inp.min === 'dataMin') {
    eff[0] = dataMM[0];
    fix[0] = true;
  } else {
    eff[0] = parseOrdinal(inp.min, catMap);
    fix[0] = eff[0] != null;
  }
  if (inp.max === 'dataMax') {
    eff[1] = dataMM[1];
    fix[1] = true;
  } else {
    eff[1] = parseOrdinal(inp.max, catMap);
    fix[1] = eff[1] != null;
  }
  if (eff[0] == null) eff[0] = inp.declaredEmpty ? dataMM[0] : nCat ? 0 : NaN;
  if (eff[1] == null) eff[1] = inp.declaredEmpty ? dataMM[1] : nCat ? nCat - 1 : NaN;
  if (!isFiniteNum(eff[0])) eff[0] = NaN;
  if (!isFiniteNum(eff[1])) eff[1] = NaN;
  const isBlank = !!inp.declaredEmpty || eff[0] !== eff[0] || eff[1] !== eff[1] || !nCat;
  let tgg = false;
  if (eff[0] > eff[1]) {
    eff.reverse();
    tgg = true;
  }
  // a category axis is never asked for a default startValue (requireStartValue
  // is false: no bar has its value axis here), and needIncludeZero does not apply
  const sv = parseOrdinal(inp.startValue, catMap);
  if (isFiniteNum(sv)) {
    if (sv < eff[0] && !fix[0]) {
      eff[0] = sv;
      fix[0] = true;
    } else if (sv > eff[1] && !fix[1]) {
      eff[1] = sv;
      fix[1] = true;
    }
  }
  const valid = isFiniteNum(eff[0]) && isFiniteNum(eff[1]) && eff[0] <= eff[1];
  const effective = valid ? eff.slice() : [Infinity, -Infinity];
  return {
    raw: { dataMM, noZoomEffMM: eff, fixMM: fix, isBlank, tggAxInv: tgg, startValue: sv },
    effective,
    count: effective[1] - effective[0] + 1,
    blank: isBlank,
    inverse: inp.optionInverse !== (tgg && !inp.legacy),
  };
}

// contain-shape.js R0: the series types whose key has a containShape handler
const HANDLED = { bar: 'cartesian2d', pictorialBar: 'cartesian2d', candlestick: null, boxplot: null };
function keysOnAxis(ecModel, axis) {
  const keys = [];
  ecModel.eachRawSeries(s => {
    const cs = HANDLED[s.subType];
    if (cs === undefined) return;
    if (!s.coordinateSystem || (cs && s.coordinateSystem.type !== cs)) return;
    if (s.getBaseAxis() !== axis) return;
    if (keys.indexOf(s.subType) < 0) keys.push(s.subType);
  });
  return keys;
}
// scaleRawExtentInfo.ts determineRequireContainShape
function ctnShpRule(containShapeOption, onBand, keys) {
  let opt = containShapeOption;
  if (opt == null && !onBand) opt = true;
  return !!opt && keys.length > 0;
}
// axisBand.ts calcBandWidthForCategoryAxis: {w, w2}
function catBand(span, onBand, pxSpan) {
  if (!isFiniteNum(span)) span = NaN;
  let len = span + (onBand ? 1 : 0);
  if (len === 0) len = 1;
  const w = pxSpan / len;
  const w2 = !onBand && span && pxSpan ? w * span / pxSpan : NaN;
  return { w, w2 };
}
// S2: the ordinal mapping (containShape's ordinal branch)
function predictMapping(ctnShp, onBand, eff, px) {
  if (!ctnShp || onBand) return null;
  const w2 = catBand(eff[1] - eff[0], onBand, px).w2;
  if (!isFiniteNum(w2)) return null;
  return [Math.min(eff[0], eff[0] + -w2 / 2), Math.max(eff[1], eff[1] + w2 / 2)];
}

// number.ts linearMap, no clamp
function linearMap(val, d0, d1, r0, r1) {
  const sd = d1 - d0;
  const sr = r1 - r0;
  if (sd === 0) return sr === 0 ? r0 : (r0 + r1) / 2;
  if (val === d0) return r0;
  if (val === d1) return r1;
  return (val - d0) / sd * sr + r0;
}
// S3 per axis: g = {dim, onBand, count, effective, mapping, px, gxy}
function bandExtent(g) {
  const e = g.px.slice();
  if (g.onBand) {
    const m = (e[1] - e[0]) / g.count / 2;
    e[0] += m;
    e[1] -= m;
  }
  return e;
}
function normalizeOf(g, v) {
  const m = g.mapping || g.effective;
  if (m[1] === m[0]) return 0.5;
  return (v - m[0]) / (m[1] - m[0]);
}
function localCoord(g, v, clamp) {
  const e = bandExtent(g);
  let t = normalizeOf(g, v);
  if (clamp) {
    if (t <= 0) return e[0];
    if (t >= 1) return e[1];
  }
  return linearMap(t, 0, 1, e[0], e[1]);
}
const toGlobal = (g, c) => (g.dim === 'x' ? c + g.gxy : (g.px[0] + g.px[1]) - c + g.gxy);
const toLocal = (g, p) => (g.dim === 'x' ? p - g.gxy : (g.px[0] + g.px[1]) - p + g.gxy);
const globalCoord = (g, v, clamp) => toGlobal(g, localCoord(g, v, clamp));
const globalExtent = g => [toGlobal(g, g.px[0]), toGlobal(g, g.px[1])];
// Cartesian2D.getArea
function areaOf(gx, gy, tol) {
  tol = tol || 0;
  const xe = globalExtent(gx);
  const ye = globalExtent(gy);
  const x = Math.min(xe[0], xe[1]) - tol;
  const y = Math.min(ye[0], ye[1]) - tol;
  return { x, y, width: Math.max(xe[0], xe[1]) - x + tol, height: Math.max(ye[0], ye[1]) - y + tol };
}
const rectContain = (r, x, y) => x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height;

// scale/helper.ts ordinalScaleCreateTicks
function ordinalTicks(e0, e1, count, interval) {
  const out = [];
  let start = e0;
  const step = Math.max((interval || 0) + 1, 1);
  if (start !== 0 && step > 1 && count / step > 2) start = Math.round(Math.ceil(start / step) * step);
  if (start !== e0) out.push({ value: e0, offInterval: true });
  let v = start;
  for (; v <= e1; v += step) out.push({ value: v, offInterval: false });
  if (v - step !== e1) out.push({ value: e1, offInterval: true });
  return out;
}
// Axis.ts getTicksCoords + fixOnBandTicksCoords (the band is calcBandWidth's w,
// always positive: upstream's quirk on an inverse axis)
function tickCoords(g, list, alignWithLabel, bandW) {
  let out = list.map(t => ({ value: t.value, offInterval: t.offInterval, coord: localCoord(g, t.value) }));
  let onBand = false;
  if (g.onBand && !alignWithLabel && out.length && bandW) {
    out.forEach(t => { t.coord -= bandW / 2; });
    const last = out[out.length - 1];
    if (last.offInterval) out.pop();
    out.push({ value: g.effective[1] + 1, offInterval: false, coord: last.coord + bandW });
    onBand = true;
  }
  return { values: out.map(t => t.value), coords: out.map(t => toGlobal(g, t.coord)), onBand };
}

// BarView.ts clip.cartesian2d over a copy; returns {layout, clipped}
function clipBar(area, L) {
  const l = { x: L.x, y: L.y, width: L.width, height: L.height };
  const sw = l.width < 0 ? -1 : 1;
  const sh = l.height < 0 ? -1 : 1;
  if (sw < 0) { l.x += l.width; l.width = -l.width; }
  if (sh < 0) { l.y += l.height; l.height = -l.height; }
  const X2 = area.x + area.width;
  const Y2 = area.y + area.height;
  const x = Math.max(l.x, area.x);
  const x2 = Math.min(l.x + l.width, X2);
  const y = Math.max(l.y, area.y);
  const y2 = Math.min(l.y + l.height, Y2);
  const xc = x2 < x;
  const yc = y2 < y;
  l.x = (xc && x > X2) ? x2 : x;
  l.y = (yc && y > Y2) ? y2 : y;
  l.width = xc ? 0 : x2 - x;
  l.height = yc ? 0 : y2 - y;
  if (sw < 0) { l.x += l.width; l.width = -l.width; }
  if (sh < 0) { l.y += l.height; l.height = -l.height; }
  return { layout: l, clipped: xc || yc };
}
function boxOf(s) {
  return [
    s.width < 0 ? s.x + s.width : s.x,
    s.height < 0 ? s.y + s.height : s.y,
    s.width < 0 ? s.x : s.x + s.width,
    s.height < 0 ? s.y : s.y + s.height,
  ];
}
// createClipPathFromCoordSys.ts createGridClipPath + LineView createLineClipPath
// (without: 'ceil' or 'floor' leaves that step out -- the port mutants a
// discriminating case must be told apart from)
function lineClip(area, lineWidth, clip, baseHorizontal, without) {
  let x = area.x - lineWidth / 2;
  const y = area.y - lineWidth / 2;
  let width = area.width + lineWidth;
  const height = area.height + lineWidth;
  if (without !== 'ceil') width = Math.ceil(width);
  if (without !== 'floor' && x !== Math.floor(x)) {
    x = Math.floor(x);
    width++;
  }
  const r = { x, y, width, height };
  if (!clip) {
    const e = Math.max(r.width, r.height);
    if (baseHorizontal) {
      r.y -= e;
      r.height += e * 2;
    } else {
      r.x -= e;
      r.width += e * 2;
    }
  }
  return r;
}

// ---------- running upstream ----------

let RUN = null;
const HOOKED = new Map();
function installHooks(lib) {
  if (HOOKED.has(lib)) return;
  const warm = lib.init(null, null, { renderer: 'svg', ssr: true, width: 200, height: 200 });
  warm.setOption({ animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [1, 2] }] });
  warm.renderToSVGString();
  let proto = warm.getModel().getComponent('xAxis', 0).axis;
  while (proto && !Object.prototype.hasOwnProperty.call(proto, 'calculateCategoryInterval')) proto = Object.getPrototypeOf(proto);
  must(proto, 'no calculateCategoryInterval on the axis prototype chain');
  warm.dispose();
  const cci = proto.calculateCategoryInterval;
  proto.calculateCategoryInterval = function () {
    if (!RUN) return cci.apply(this, arguments);
    const se = this.scale.getExtent();
    const unitSpan = this.dataToCoord(se[0] + 1) - this.dataToCoord(se[0]);
    const r = cci.apply(this, arguments);
    RUN.calls.push({ axis: this, interval: r, unitSpan });
    return r;
  };
  HOOKED.set(lib, true);
}

// the axis view's elements by anid (label-thinning.js sceneOf)
function sceneOf(chart, axis) {
  const view = chart.getViewOfComponentModel(axis.model);
  const out = { ticks: new Map(), lines: new Map(), areas: [], labels: new Map() };
  if (!view || !view._axisGroup) return out;
  const bg = axis.axisBuilder && axis.axisBuilder.group;
  const under = (e, g) => { for (let p = e; p; p = p.parent) if (p === g) return true; return false; };
  (function walk(e) {
    if (e.anid) {
      const inB = bg && under(e, bg);
      let m;
      if (inB && (m = /^ticks_(.*)$/.exec(e.anid))) out.ticks.set(m[1], !e.ignore);
      else if (inB && (m = /^label_(.*)$/.exec(e.anid))) out.labels.set(m[1], !e.ignore && !!(e.style && e.style.text));
      else if (!inB && (m = /^line_(.*)$/.exec(e.anid))) out.lines.set(m[1], !e.ignore);
      else if (!inB && (m = /^area_(.*)$/.exec(e.anid))) out.areas.push(m[1]);
    }
    if (e.childrenRef) e.childrenRef().forEach(walk);
  })(view._axisGroup);
  return out;
}

const optInterval = model => { const v = model.get('interval'); return v == null ? 'auto' : v; };

function run(c, lib) {
  installHooks(lib);
  const option = clone(c.option);
  option.animation = false;
  const written = clone(option);
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  RUN = { calls: [] };
  let st;
  try {
    try {
      chart.setOption(option);
      chart.renderToSVGString();
    } finally {
      st = RUN;
      RUN = null;
    }
    const fails = [];
    const fail = (check, msg) => fails.push({ check, msg });
    const ecModel = chart.getModel();
    const gm = ecModel.getComponent('grid', 0);
    const cs = gm.coordinateSystem;
    const cart = cs.getCartesians()[0];
    const rect = plainRect(cs.getRect());
    must(finiteRect(rect), c.name + ': the rect is not finite');
    const area = plainRect(cart.getArea());
    const legacy = !!ecModel.get('legacyMinMaxDontInverseAxis');
    const nature = [];
    const disc = {};

    // ----- the axes
    const axes = [];
    ['x', 'y'].forEach(dim => cs.getAxes().filter(a => a.dim === dim).sort((a, b) => a.model.componentIndex - b.model.componentIndex)
      .forEach(a => axes.push(a)));
    const geo = new Map();
    const recs = axes.map(axis => {
      const scale = axis.scale;
      const cat = scale.type === 'ordinal';
      const model = axis.model;
      const wh = axis.dim === 'x' ? rect.width : rect.height;
      const g = {
        dim: axis.dim, onBand: !!axis.onBand, effective: scale.getExtent().slice(),
        mapping: (m => (m ? m.slice() : null))(scale.getExtentUnsafe(MAPPING, null)),
        px: axis.getExtent().slice(), gxy: axis.dim === 'x' ? rect.x : rect.y,
      };
      g.count = cat ? scale.count() : null;
      geo.set(axis, g);
      const r = { axis, dim: axis.dim, index: model.componentIndex, type: axis.type, inverse: !!axis.inverse, g };
      if (!sameArr(g.px, axis.inverse ? [wh, 0] : [0, wh])) fail(3, axis.dim + ': px ' + JSON.stringify(g.px) + ' is not built from the rect');
      if (!cat) return r;

      // check 1: the extent
      const info = scale.rawExtentInfo._i;
      const cats = scale.getOrdinalMeta().categories.slice();
      r.nCat = cats.length;
      must(model.getCategories().length === cats.length, c.name + ': getCategories and ordinalMeta disagree');
      const declared = model.getCategories(true);
      const declaredEmpty = !!(declared && !declared.length);
      const dataMM = [Infinity, -Infinity];
      ecModel.eachSeries(s => {
        if (!s.coordinateSystem || s.coordinateSystem !== cart) return;
        const data = s.getData();
        const dimName = data.mapDimension(axis.dim);
        if (dimName == null) return;
        const di = data.getDimensionIndex(dimName);
        const store = data.getStore();
        for (let i = 0, n = store.count(); i < n; i++) {
          const v = store.get(di, i);
          if (isFinite(v)) {
            if (v < dataMM[0]) dataMM[0] = v;
            if (v > dataMM[1]) dataMM[1] = v;
          }
        }
      });
      const t = ordinalExtent({
        min: model.get('min', true), max: model.get('max', true), startValue: model.get('startValue', true),
        cats, declaredEmpty, dataMM, optionInverse: !!model.get('inverse'), legacy,
      });
      r.raw = {
        dataMM: info.dataMM.slice(), noZoomEffMM: info.noZoomEffMM.slice(), fixMM: info.fixMM.slice(),
        isBlank: !!info.isBlank, tggAxInv: !!info.tggAxInv, startValue: info.startValue == null ? null : info.startValue,
      };
      const rawBad = ['dataMM', 'noZoomEffMM', 'fixMM'].filter(k => !sameArr(t.raw[k], r.raw[k]))
        .concat(['isBlank', 'tggAxInv', 'startValue'].filter(k => !same(t.raw[k] == null ? null : t.raw[k], r.raw[k])));
      if (rawBad.length) {
        fail(1, axis.dim + ': raw ' + rawBad.join(',') + ' ' + JSON.stringify(rawBad.map(k => String(r.raw[k])))
          + ', the transcription gives ' + JSON.stringify(rawBad.map(k => String(t.raw[k]))));
      }
      r.blank = !!scale.isBlank();
      if (!sameArr(t.effective, g.effective)) fail(1, axis.dim + ': effective ' + textArr(g.effective) + ', transcribed ' + textArr(t.effective));
      if (!same(t.count, g.count)) fail(1, axis.dim + ': count ' + g.count + ', transcribed ' + t.count);
      if (t.blank !== r.blank) fail(1, axis.dim + ': blank ' + r.blank + ', transcribed ' + t.blank);
      if (t.inverse !== r.inverse) fail(1, axis.dim + ': inverse ' + r.inverse + ', transcribed ' + t.inverse);
      if (declaredEmpty && isFiniteNum(info.noZoomEffMM[0]) && isFiniteNum(info.noZoomEffMM[1])) {
        nature.push('declared-empty category list: extent from the series data');
      }
      if (g.count > CAP) nature.push('category count ' + g.count + ' past the cap ' + CAP);

      // check 2: the mapping
      r.ctnShp = !!info.ctnShp;
      const keys = keysOnAxis(ecModel, axis);
      const ctn = ctnShpRule(model.get('containShape', true), g.onBand, keys);
      if (ctn !== r.ctnShp) fail(2, axis.dim + ': ctnShp ' + r.ctnShp + ', the rule gives ' + ctn);
      const pm = predictMapping(r.ctnShp, g.onBand, g.effective, Math.abs(g.px[1] - g.px[0]));
      if (!sameArr(pm, g.mapping)) fail(2, axis.dim + ': mapping ' + JSON.stringify(textArr(g.mapping)) + ', predicted ' + JSON.stringify(textArr(pm)));

      // check 3: coords, contain, band width
      const ms = (g.mapping || g.effective);
      const band = catBand(ms[1] - ms[0], g.onBand, Math.abs(g.px[1] - g.px[0]));
      r.bandW = isFiniteNum(band.w) ? band.w : null;
      r.bandWidth = axis.getBandWidth();
      const bwWant = isFiniteNum(band.w) ? Math.max(1, band.w) : 1;
      if (!same(bwWant, r.bandWidth)) fail(3, axis.dim + ': getBandWidth ' + r.bandWidth + ', the recipe gives ' + bwWant);
      r.contain = PROBE_VALUES.map(v => !!scale.contain(v));
      r.coords = PROBE_VALUES.map(v => axis.toGlobalCoord(axis.dataToCoord(v)));
      PROBE_VALUES.forEach((v, i) => {
        const want = globalCoord(g, v);
        if (!same(want, r.coords[i])) fail(3, axis.dim + ': coord(' + v + ') ' + r.coords[i] + ', the recipe gives ' + want);
        const cw = v >= ms[0] && v <= ms[1] && v >= 0 && v < cats.length;
        if (cw !== r.contain[i]) fail(3, axis.dim + ': contain(' + v + ') ' + r.contain[i] + ', the rule gives ' + cw);
      });

      // labels, ticks, split lines, split areas
      const sc = sceneOf(chart, axis);
      const labelModel = axis.getLabelModel();
      const optI = optInterval(labelModel);
      must(optI === 'auto' || (typeof optI === 'number' && Number.isInteger(optI)), c.name + ': axisLabel.interval ' + JSON.stringify(optI));
      const calls = st.calls.filter(k => k.axis === axis);
      calls.forEach(k => must(same(k.interval, calls[0].interval) && same(k.unitSpan, calls[0].unitSpan),
        c.name + ': calculateCategoryInterval answered differently across calls'));
      // calculateCategoryInterval returns 0 before it computes a unitSpan when e1 - e0 < 1
      const early = !(g.effective[1] - g.effective[0] >= 1);
      r.interval = { option: optI, used: optI === 'auto' ? (calls.length ? calls[0].interval : null) : optI,
        unitSpan: optI === 'auto' && calls.length && !early ? calls[0].unitSpan : null };
      const views = r.blank ? [] : axis.getViewLabels();
      r.labels = views.map(l => ({ value: l.tick.value, text: l.formattedLabel, offInterval: !!l.tick.offInterval,
        shown: sc.labels.get(String(l.tick.value)) === true }));
      const tm = axis.getTickModel();
      const tl = axis.getTicksCoords({ tickModel: tm });
      r.ticks = { values: tl.map(k => k.tickValue), globalCoords: tl.map(k => axis.toGlobalCoord(k.coord)),
        drawn: tl.map(k => sc.ticks.get(String(k.tickValue)) === true), onBand: tl.length ? !!tl[0].onBand : false };
      const lm = model.getModel('splitLine');
      const ll = axis.getTicksCoords({ tickModel: lm });
      r.splitLines = { values: ll.map(k => k.tickValue), globalCoords: ll.map(k => axis.toGlobalCoord(k.coord)),
        drawn: ll.map(k => sc.lines.get(String(k.tickValue)) === true), onBand: ll.length ? !!ll[0].onBand : false };
      r.splitAreas = sc.areas.map(Number);

      // check 4
      if (!r.blank) {
        must(r.interval.used != null, c.name + ': ' + axis.dim + ': no label interval');
        const e = g.effective;
        const built = ordinalTicks(e[0], e[1], g.count, r.interval.used);
        const lv = r.labels.map(l => [l.value, l.offInterval]);
        const bv = built.map(l => [l.value, l.offInterval]);
        if (JSON.stringify(lv) !== JSON.stringify(bv) || !r.labels.every((l, i) => same(l.value, built[i].value))) {
          fail(4, axis.dim + ': labels ' + JSON.stringify(lv) + ', the transcription gives ' + JSON.stringify(bv));
        }
        const listFor = m => { const iv = optInterval(m); return iv === 'auto' ? built : ordinalTicks(e[0], e[1], g.count, iv); };
        const cmp = (nm, got, m) => {
          const want = tickCoords(g, listFor(m), m.get('alignWithLabel'), r.bandW);
          if (!sameArr(want.values, got.values) || !sameArr(want.coords, got.globalCoords) || want.onBand !== got.onBand) {
            fail(4, axis.dim + ' ' + nm + ': ' + JSON.stringify(got.values.map((v, i) => v + '@' + got.globalCoords[i]))
              + ', the transcription gives ' + JSON.stringify(want.values.map((v, i) => v + '@' + want.coords[i])));
          }
        };
        cmp('ticks', r.ticks, tm);
        cmp('split lines', r.splitLines, lm);
        const am = model.getModel('splitArea');
        if (am.get('show')) {
          const aw = tickCoords(g, listFor(am), am.get('alignWithLabel'), r.bandW).values.slice(0, -1);
          if (!sameArr(aw, r.splitAreas)) fail(4, axis.dim + ': split areas ' + JSON.stringify(r.splitAreas) + ', transcribed ' + JSON.stringify(aw));
        } else if (r.splitAreas.length) fail(4, axis.dim + ': split areas without splitArea.show');
        if (r.interval.unitSpan != null) {
          const us = localCoord(g, e[0] + 1) - localCoord(g, e[0]);
          if (!same(us, r.interval.unitSpan)) fail(4, axis.dim + ': unitSpan ' + r.interval.unitSpan + ', the recipe gives ' + us);
        }
        if (c.discriminates === 'unitSpan') {
          // axisTickLabelBuilder.ts calculateCategoryInterval on a horizontal
          // axis with unrotated labels: maxW over the sampled labels (width *
          // 1.3, at least 7; zrender's text measure), dw = maxW / |unitSpan|,
          // dh = Infinity, interval = floor(dw). Fed upstream's unitSpan it must
          // give the interval used; fed the closed form len / (count - 1) (no
          // mapping) it must give another.
          must(axis.isHorizontal() && !labelModel.get('rotate') && r.interval.unitSpan != null, c.name + ': not a plain auto x axis');
          const step = g.count > 40 ? Math.max(1, Math.floor(g.count / 40)) : 1;
          const font = labelModel.getFont();
          let maxW = 0;
          for (let v = e[0]; v <= e[1]; v += step) {
            const txt = new lib.graphic.Text({ style: { text: (cats[v] == null ? '' : cats[v]) + '', font } });
            maxW = Math.max(maxW, txt.getBoundingRect().width * 1.3, 7);
          }
          const len = Math.abs(g.px[1] - g.px[0]);
          const closed = len / (g.count - 1);
          const ivUp = Math.floor(maxW / Math.abs(r.interval.unitSpan));
          const ivClosed = Math.floor(maxW / closed);
          Object.assign(disc, { maxW: hex(maxW), maxWText: text(maxW), closedFormUnitSpan: hex(closed), closedFormUnitSpanText: text(closed),
            closedFormInterval: ivClosed });
          if (ivUp !== r.interval.used) fail(4, axis.dim + ': the interval from upstream\'s unitSpan is ' + ivUp + ', upstream used ' + r.interval.used);
          if (ivClosed === r.interval.used) fail('disc', axis.dim + ': the closed-form unitSpan gives the same interval ' + ivClosed);
        }
      }
      return r;
    });
    const gx = geo.get(cart.getAxis('x'));
    const gy = geo.get(cart.getAxis('y'));
    const areaWant = areaOf(gx, gy);
    if (!sameRect(areaWant, area)) fail(3, 'area ' + JSON.stringify(area) + ', the recipe gives ' + JSON.stringify(areaWant));
    const catAxis = cart.getAxesByScale('ordinal')[0];

    // per-axis dataToPoint (a category axis never takes the affine path)
    must(!cart._transform, c.name + ': an affine transform on a category grid');
    const point = (xv, yv) => [globalCoord(gx, xv), globalCoord(gy, yv)];

    // ----- the series
    const series = [];
    ecModel.eachRawSeries(s => {
      const filtered = ecModel.isSeriesFiltered(s);
      const rec = { index: s.seriesIndex, type: s.subType, filtered };
      series.push(rec);
      if (filtered) return;
      must(s.coordinateSystem === cart, c.name + ': a series off the grid');
      const data = s.getData();
      const store = data.getStore();
      const baseAxis = s.getBaseAxis();
      const valueAxis = cart.getOtherAxis(baseAxis);
      const di = dim => data.getDimensionIndex(data.mapDimension(dim));
      const stackDim = data.getCalculationInfo('stackResultDimension');
      const clipOn = !!s.get('clip', true);
      if (s.subType === 'bar') {
        const lay = k => { const v = data.getLayout(k); return typeof v === 'number' ? v : null; };
        const bw = lay('bandWidth');
        const off = lay('offset');
        const size = lay('size');
        Object.assign(rec, { bandWidth: hexOrNull(bw), bandWidthText: textOrNull(bw), offset: hexOrNull(off), offsetText: textOrNull(off),
          size: hexOrNull(size), sizeText: textOrNull(size) });
        // check 5: the band, the layouts, the boxes
        const gb = geo.get(baseAxis);
        const ms = gb.mapping || gb.effective;
        let w = catBand(ms[1] - ms[0], gb.onBand, Math.abs(gb.px[1] - gb.px[0])).w;
        w = isFiniteNum(w) ? Math.max(1, w) : 1;
        if (!same(w, bw)) fail(5, 's' + s.seriesIndex + ': bandWidth ' + bw + ', the recipe gives ' + w);
        const valueH = valueAxis.isHorizontal();
        const gv = geo.get(valueAxis);
        const valueDim = data.mapDimension(valueAxis.dim);
        const stacked = echarts.helper.dataStack.isDimensionStacked(data, valueDim) && !!data.getCalculationInfo('stackedOnSeries');
        const vIdx = data.getDimensionIndex(valueDim);
        const bIdx = di(baseAxis.dim);
        const sIdx = stackDim && data.getDimensionIndex(stackDim);
        const sv = valueAxis.scale.rawExtentInfo.makeRenderInfo().startValue;
        const vStart = globalCoord(gv, sv);
        const minH = s.get('barMinHeight') || 0;
        rec.items = [];
        const n = s.getRawData().count();
        for (let rI = 0; rI < n; rI++) {
          const k = data.indexOfRawIndex(rI);
          const el = k >= 0 ? data.getItemGraphicEl(k) : null;
          const L = k >= 0 ? data.getItemLayout(k) : null;
          const item = { class: !el ? 'none' : el.ignore ? 'hidden' : 'drawn' };
          item.layout = L && finiteRect(L) ? RECT.map(q => hex(L[q])) : null;
          item.box = el && finiteRect(el.shape) ? boxOf(el.shape).map(hex) : null;
          rec.items.push(item);
          if (!L || k < 0) continue;
          const value = store.get(stacked ? sIdx : vIdx, k);
          const baseValue = store.get(bIdx, k);
          let baseCoord = vStart;
          const stackStart = stacked ? +value - store.get(vIdx, k) : undefined;
          let want;
          if (valueH) {
            const p = point(value, baseValue);
            if (stacked) baseCoord = point(stackStart, baseValue)[0];
            let width = p[0] - baseCoord;
            if (Math.abs(width) < minH) width = (width < 0 ? -1 : 1) * minH;
            want = { x: baseCoord, y: p[1] + off, width, height: size };
          } else {
            const p = point(baseValue, value);
            if (stacked) baseCoord = point(baseValue, stackStart)[1];
            let height = p[1] - baseCoord;
            if (Math.abs(height) < minH) height = (height <= 0 ? -1 : 1) * minH;
            want = { x: p[0] + off, y: baseCoord, width: size, height };
          }
          if (!sameRect(want, L)) fail(5, 's' + s.seriesIndex + '[' + rI + ']: layout ' + JSON.stringify(textRect(L)) + ', the recipe gives ' + JSON.stringify(textRect(want)));
          if (!el) continue;
          const cl = clipOn ? clipBar(area, L) : { layout: L, clipped: false };
          const bx = boxOf(cl.layout);
          if (!sameArr(bx, boxOf(el.shape))) fail(5, 's' + s.seriesIndex + '[' + rI + ']: box ' + JSON.stringify(boxOf(el.shape)) + ', the clip gives ' + JSON.stringify(bx));
          if (cl.clipped !== !!el.ignore) fail(5, 's' + s.seriesIndex + '[' + rI + ']: ignore ' + !!el.ignore + ', clipped whole ' + cl.clipped);
        }
        return;
      }
      if (s.subType !== 'line' && s.subType !== 'scatter') return;
      // line: a Float32Array layout; scatter: one [x, y] layout per item (doubles)
      const isLine = s.subType === 'line';
      let pts = data.getLayout('points');
      if (isLine) {
        must(pts instanceof Float32Array && pts.length === data.count() * 2, c.name + ' s' + s.seriesIndex + ': points are not a Float32Array of 2n');
      } else {
        must(!pts, c.name + ' s' + s.seriesIndex + ': a scatter with a points layout');
        pts = [];
        for (let i = 0; i < data.count(); i++) {
          const L = data.getItemLayout(i);
          pts.push(L ? L[0] : NaN, L ? L[1] : NaN);
        }
      }
      const rnd = isLine ? Math.fround : (v => v);
      const xDim = data.mapDimension('x');
      const yDim = data.mapDimension('y');
      const xIdx = data.getDimensionIndex(echarts.helper.dataStack.isDimensionStacked(data, xDim) ? stackDim : xDim);
      const yIdx = data.getDimensionIndex(echarts.helper.dataStack.isDimensionStacked(data, yDim) ? stackDim : yDim);
      const want = [];
      for (let i = 0; i < data.count(); i++) {
        const p = point(store.get(xIdx, i), store.get(yIdx, i));
        want.push([rnd(p[0]), rnd(p[1])]);
        if (!same(want[i][0], pts[2 * i]) || !same(want[i][1], pts[2 * i + 1])) {
          fail(6, 's' + s.seriesIndex + '[' + i + ']: point ' + pts[2 * i] + ',' + pts[2 * i + 1] + ', the recipe gives ' + want[i]);
        }
      }
      const syms = [];
      const symEls = [];
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        if (el) {
          syms.push(i);
          symEls.push(el);
        }
      }
      rec.symbols = syms;
      const baseH = baseAxis.isHorizontal();
      if (s.subType === 'line') {
        rec.points = want.map((_, i) => [hex32(pts[2 * i]), hex32(pts[2 * i + 1])]);
        const view = chart.getViewOfSeriesModel(s);
        const cp = view._lineGroup && view._lineGroup.getClipPath();
        rec.clip = cp ? hexRect(cp.shape) : null;
        rec.clipText = cp ? textRect(cp.shape) : null;
        const lw = s.get(['lineStyle', 'width']) || 0;
        const cw = lineClip(areaOf(gx, gy), lw, clipOn, baseH);
        if (!cp || !sameRect(cw, cp.shape)) fail(6, 's' + s.seriesIndex + ': clip ' + JSON.stringify(cp && plainRect(cp.shape)) + ', the recipe gives ' + JSON.stringify(cw));
        if (c.discriminates === 'clip' && cp) {
          // the case must tell both port mutants apart from upstream
          ['ceil', 'floor'].forEach(k => {
            const m = lineClip(areaOf(gx, gy), lw, clipOn, baseH, k);
            disc['clipWithout' + k[0].toUpperCase() + k.slice(1)] = RECT.map(q => hex(m[q]));
            if (sameRect(m, cp.shape)) fail('disc', 's' + s.seriesIndex + ': the clip without the ' + k + ' step is upstream\'s too');
          });
        }
        // the symbols
        let ignore = null;
        const showAll = s.get('showAllSymbol');
        if (!(showAll && showAll !== 'auto') && catAxis) {
          let canAll = false;
          if (showAll === 'auto') {
            const cg = geo.get(catAxis);
            let avail = Math.abs(cg.px[1] - cg.px[0]) / catAxis.scale.count();
            if (isNaN(avail)) avail = 0;
            canAll = true;
            const len = data.count();
            const step = Math.max(1, Math.round(len / 5));
            for (let i = 0; i < len; i += step) {
              let sz = data.getItemVisual(i, 'symbolSize');
              if (!Array.isArray(sz)) sz = [sz, sz];
              if (sz[catAxis.isHorizontal() ? 1 : 0] * 1.5 > avail) { canAll = false; break; }
            }
          }
          if (!canAll) {
            const cr = recs.find(q => q.axis === catAxis);
            const keep = new Set(cr.labels.filter(l => !l.offInterval).map(l => l.value));
            const ci = di(catAxis.dim);
            ignore = i => !keep.has(store.get(ci, i));
          }
        }
        let clipShape = null;
        if (clipOn) {
          clipShape = areaOf(gx, gy);
          clipShape.x -= 0.1;
          clipShape.y -= 0.1;
          clipShape.width += 0.2;
          clipShape.height += 0.2;
        }
        const showSymbol = s.get('showSymbol');
        const sw = [];
        for (let i = 0; i < data.count(); i++) {
          const p = want[i];
          if (!showSymbol || isNaN(p[0]) || isNaN(p[1])) continue;
          if (ignore && ignore(i)) continue;
          if (clipShape && !rectContain(clipShape, p[0], p[1])) continue;
          sw.push(i);
        }
        if (!sameArr(sw, syms)) fail(6, 's' + s.seriesIndex + ': symbols ' + JSON.stringify(syms) + ', the rule gives ' + JSON.stringify(sw));
      } else {
        rec.symbolPoints = symEls.map(el => [hex(el.x), hex(el.y)]);
        const clipShape = clipOn ? areaOf(gx, gy, 0.1) : null;
        const sw = [];
        for (let i = 0; i < data.count(); i++) {
          const p = want[i];
          if (isNaN(p[0]) || isNaN(p[1])) continue;
          if (clipShape && !rectContain(clipShape, p[0], p[1])) continue;
          sw.push(i);
        }
        if (!sameArr(sw, syms)) fail(6, 's' + s.seriesIndex + ': scatter symbols ' + JSON.stringify(syms) + ', the rule gives ' + JSON.stringify(sw));
        symEls.forEach((el, j) => {
          const p = want[syms[j]];
          if (!same(el.x, p[0]) || !same(el.y, p[1])) fail(6, 's' + s.seriesIndex + '[' + syms[j] + ']: symbol at ' + el.x + ',' + el.y + ', dataToPoint ' + p);
        });
      }
    });

    // ----- the pointer probes
    const probes = [];
    if (c.probes) {
      must(catAxis, c.name + ': pointer probes without a category axis');
      const cg = geo.get(catAxis);
      const cr = recs.find(q => q.axis === catAxis);
      const other = geo.get(cart.getOtherAxis(catAxis));
      const zr = chart.getZr();
      const apInfo = ecModel.getComponent('axisPointer', 0).coordSysAxesInfo;
      const infos = Object.keys(apInfo.axesInfo).map(k => apInfo.axesInfo[k]).filter(i => i.axis === catAxis);
      must(infos.length === 1 && !infos[0].snap, c.name + ': the category axis pointer snaps (or is not collected)');
      let last = null;
      chart.on('updateAxisPointer', e => { last = e; });
      c.probes.forEach(([x, y]) => {
        must(Number.isInteger(x) && Number.isInteger(y), c.name + ': a probe off the integer grid');
        last = null;
        chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x, y });
        zr.refreshImmediately();
        const ai = last && last.axesInfo ? last.axesInfo.filter(a => a.axisDim === catAxis.dim) : [];
        const kind = el => String(el.type).toLowerCase();
        const els = zr.storage.getDisplayList(true).filter(el => el.z === 50 && (kind(el) === 'line' || kind(el) === 'rect') && !el.ignore && !el.invisible);
        must(els.length <= 1, c.name + ': ' + els.length + ' pointer elements');
        const el = els[0];
        const pr = {
          x, y, axisDim: catAxis.dim,
          axisValue: ai.length ? ai[0].value : null,
          dataIndex: last && last.dataIndex != null ? last.dataIndex : null,
          seriesIndex: last && last.seriesIndex != null ? last.seriesIndex : null,
          pointer: !el ? null : kind(el) === 'line'
            ? { type: 'line', shape: [el.shape.x1, el.shape.y1, el.shape.x2, el.shape.y2] }
            : { type: 'rect', shape: [el.shape.x, el.shape.y, el.shape.width, el.shape.height] },
        };
        probes.push(pr);
        // check 7
        const inside = [gx, gy].every(g => { const l = toLocal(g, g.dim === 'x' ? x : y); return l >= Math.min(g.px[0], g.px[1]) && l <= Math.max(g.px[0], g.px[1]); });
        let val = null;
        if (inside) {
          const e = bandExtent(cg);
          const t = linearMap(toLocal(cg, catAxis.dim === 'x' ? x : y), e[0], e[1], 0, 1);
          const m = cg.mapping || cg.effective;
          val = Math.round(t * (m[1] - m[0]) + m[0]);
        }
        const shown = inside && !cr.blank && val >= (cg.mapping || cg.effective)[0] && val <= (cg.mapping || cg.effective)[1]
          && val >= 0 && val < cr.nCat;
        const where = 'probe ' + x + ',' + y;
        if (!shown) {
          if (pr.axisValue != null || pr.pointer || pr.dataIndex != null) fail(7, where + ': shown at ' + pr.axisValue + ', the rule hides it');
          return;
        }
        // axisTrigger.ts buildPayloadsBySeries + Series.indicesOfNearest: per
        // series the items within 0.5 px of the value's coord (pixel distance,
        // ties to diff >= 0); the series whose nearest value is closest wins
        let minDist = Number.MAX_VALUE;
        let minDiff = -1;
        let snap = val;
        let batch = [];
        const target = localCoord(cg, val);
        ecModel.eachSeries(s => {
          if (s.coordinateSystem !== cart) return;
          const data = s.getData();
          const ci = data.getDimensionIndex(data.mapDimension(catAxis.dim));
          const store = data.getStore();
          let near = [];
          let nd = Infinity;
          let ndiff = -1;
          for (let i = 0; i < store.count(); i++) {
            const diff = target - localCoord(cg, store.get(ci, i));
            const dist = Math.abs(diff);
            if (dist <= 0.5) {
              if (dist < nd || (dist === nd && diff >= 0 && ndiff < 0)) {
                nd = dist;
                ndiff = diff;
                near = [];
              }
              if (diff === ndiff) near.push(i);
            }
          }
          if (!near.length) return;
          const nv = store.get(ci, near[0]);
          if (!isFiniteNum(nv)) return;
          const diff = val - nv;
          const dist = Math.abs(diff);
          if (dist <= minDist) {
            if (dist < minDist || (diff >= 0 && minDiff < 0)) {
              minDist = dist;
              minDiff = diff;
              snap = nv;
              batch = [];
            }
            near.forEach(i => batch.push({ seriesIndex: s.seriesIndex, dataIndex: data.getRawIndex(i) }));
          }
        });
        // axisInfo.snap is off here (checked above), so the value stays v
        void snap;
        const di = batch.length ? batch[0].dataIndex : null;
        const si = batch.length ? batch[0].seriesIndex : null;
        if (!same(pr.dataIndex, di) || !same(pr.seriesIndex, si)) fail(7, where + ': dataIndex ' + pr.seriesIndex + '/' + pr.dataIndex + ', the rule gives ' + si + '/' + di);
        if (!same(pr.axisValue, val)) fail(7, where + ': axisValue ' + pr.axisValue + ', the rule gives ' + val);
        if (!pr.pointer) { fail(7, where + ': no pointer element'); return; }
        const p = globalCoord(cg, val, true);
        const oe = globalExtent(other);
        const dx = catAxis.dim === 'x';
        let wantShape;
        if (pr.pointer.type === 'line') {
          wantShape = dx ? [p, oe[0], p, oe[1]] : [oe[0], p, oe[1], p];
        } else {
          const ms = cg.mapping || cg.effective;
          let bw = catBand(ms[1] - ms[0], cg.onBand, Math.abs(cg.px[1] - cg.px[0])).w;
          bw = isFiniteNum(bw) ? Math.max(1, bw) : 1;
          const te = globalExtent(cg);
          const lo = Math.max(Math.min(te[0], te[1]), p - bw / 2);
          const hi = Math.min(p + bw / 2, Math.max(te[0], te[1]));
          wantShape = dx ? [lo, oe[0], hi - lo, oe[1] - oe[0]] : [oe[0], lo, oe[1] - oe[0], hi - lo];
        }
        if (!sameArr(wantShape, pr.pointer.shape)) fail(7, where + ': pointer ' + JSON.stringify(pr.pointer.shape) + ', the rule gives ' + JSON.stringify(wantShape));
      });
    }

    if (c.discriminates && !Object.keys(disc).length) fail('disc', 'nothing was measured to discriminate');
    return { option: written, rect, area, axes: recs, series, probes, fails, nature, disc };
  } finally {
    chart.dispose();
  }
}

function axisOut(r) {
  const g = r.g;
  const o = { dim: r.dim, index: r.index, type: r.type, inverse: r.inverse, px: hexArr(g.px), pxText: textArr(g.px),
    effective: hexArr(g.effective), effectiveText: textArr(g.effective), mapping: hexArr(g.mapping), mappingText: textArr(g.mapping) };
  if (r.type !== 'category') return o;
  const tx = v => (v == null ? null : text(v));
  return Object.assign(o, {
    onBand: g.onBand, blank: r.blank, nCat: r.nCat, ctnShp: r.ctnShp,
    raw: { dataMM: r.raw.dataMM.map(tx), noZoomEffMM: r.raw.noZoomEffMM.map(tx), fixMM: r.raw.fixMM, isBlank: r.raw.isBlank,
      tggAxInv: r.raw.tggAxInv, startValue: tx(r.raw.startValue) },
    count: text(g.count),
    bandWidth: hex(r.bandWidth), bandWidthText: text(r.bandWidth), bandW: hexOrNull(r.bandW), bandWText: textOrNull(r.bandW),
    contain: r.contain,
    coords: r.coords.map(hex),
    interval: { option: r.interval.option, used: r.interval.used === Infinity ? 'Infinity' : r.interval.used, unitSpan: hexOrNull(r.interval.unitSpan), unitSpanText: textOrNull(r.interval.unitSpan) },
    labels: r.labels,
    ticks: { values: r.ticks.values, globalCoords: r.ticks.globalCoords.map(hex), drawn: r.ticks.drawn, onBand: r.ticks.onBand },
    splitLines: { values: r.splitLines.values, globalCoords: r.splitLines.globalCoords.map(hex), drawn: r.splitLines.drawn,
      onBand: r.splitLines.onBand },
    splitAreas: r.splitAreas,
  });
}
function probeOut(p) {
  return Object.assign({}, p, { pointer: p.pointer ? { type: p.pointer.type, shape: p.pointer.shape.map(hex) } : null });
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
  // the production build writes the same record
  const view = x => JSON.stringify({ a: x.axes.map(axisOut), s: x.series, p: x.probes.map(probeOut), d: x.disc, f: x.fails.map(f => f.check) });
  if (!productionBuild && PROD !== echarts) {
    const p = run(c, PROD);
    if (view(p) !== view(r)) r.fails.push({ check: 'prod', msg: 'the production build records differently' });
  }
  return Object.assign(r, { productionBuild });
}

// ---------- cases ----------

const cases = [];
const GRID = { left: 50, right: 50, top: 40, bottom: 40, outerBoundsMode: 'none' };
function add(group, name, option, extra) {
  extra = extra || {};
  const o = clone(option);
  o.grid = Object.assign({}, GRID, o.grid || {});
  cases.push(Object.assign({ name: group + ' ' + name, group, option: o, W: 600, H: 400 }, extra));
}
const deferred = why => ({ deferred: why });
const T = 'abcdefghij'.split('');
const V10 = [5, 20, 36, 10, 10, 20, 8, 15, 30, 12];
const CAT = x => Object.assign({ type: 'category', data: T }, x || {});
const bar = (data, e) => Object.assign({ type: 'bar', data: data || V10 }, e || {});
const line = (data, e) => Object.assign({ type: 'line', data: data || V10 }, e || {});
// a category x axis (x: its extra keys) over a value y axis
const cx = (x, series, rest) => Object.assign({ xAxis: CAT(x), yAxis: { type: 'value' }, series: series || [bar()] }, rest || {});
// a category y axis (bars lying down)
const cy = (y, series, rest) => Object.assign({ yAxis: CAT(y), xAxis: { type: 'value' }, series: series || [bar()] }, rest || {});
const cats = (n, f) => Array.from({ length: n }, (_, i) => f(i));

// A. parse and extent
add('A', 'none', cx());
add('A', 'min 2 max 6', cx({ min: 2, max: 6 }));
add('A', "min 'c' max 'g'", cx({ min: 'c', max: 'g' }));
add('A', 'min 2.4 max 6.6', cx({ min: 2.4, max: 6.6 }));
add('A', 'min 2.5 max 6.5', cx({ min: 2.5, max: 6.5 }));
add('A', 'min -2.5 max 5.5', cx({ min: -2.5, max: 5.5 }));
add('A', 'min -0.5', cx({ min: -0.5 }));
add('A', 'min -2 max 12', cx({ min: -2, max: 12 }));
add('A', 'min 6 max 2: backwards means inverse', cx({ min: 6, max: 2 }));
add('A', 'min 6 max 2 inverse: the toggles cancel', cx({ min: 6, max: 2, inverse: true }));
add('A', 'min 6 max 2 legacyMinMaxDontInverseAxis', cx({ min: 6, max: 2 }, null, { legacyMinMaxDontInverseAxis: true }));
add('A', 'min 12', cx({ min: 12 }));
add('A', 'max -3', cx({ max: -3 }));
add('A', 'min 3', cx({ min: 3 }));
add('A', 'max 4', cx({ max: 4 }));
add('A', 'min 5 max 5', cx({ min: 5, max: 5 }));
add('A', 'min 5 max 5 boundaryGap false', cx({ min: 5, max: 5, boundaryGap: false }));
add('A', 'min true max false', cx({ min: true, max: false }));
add('A', 'min [3]', cx({ min: [3] }));
add('A', 'min [] max 6', cx({ min: [], max: 6 }));
add('A', "dataMin/dataMax, pairs 'c' and 'h'", cx({ min: 'dataMin', max: 'dataMax' }, [bar([['c', 5], ['h', 20]])]));
add('A', 'dataMin/dataMax, 6 plain values', cx({ min: 'dataMin', max: 'dataMax' }, [bar(V10.slice(0, 6))]));
add('A', 'dataMin/dataMax option keys are not unioned', cx({ min: 'dataMin', max: 'dataMax', dataMin: -3, dataMax: 14 },
  [bar(V10.slice(2, 6).map((v, i) => ['cdef'[i], v]))]));
add('A', 'dataMax, 12 plain values', cx({ max: 'dataMax' }, [bar(V10.concat([7, 9]))]));
add('A', 'dataMin/dataMax, legend-hidden B', cx({ min: 'dataMin', max: 'dataMax' },
  [bar([['c', 1], ['f', 2]], { name: 'A' }), bar([['b', 1], ['h', 2]], { name: 'B' })],
  { legend: { data: ['A', 'B'], selected: { B: false } } }));
add('A', 'min 1 startValue 15', cx({ min: 1, startValue: 15 }));
add('A', 'startValue 15', cx({ startValue: 15 }));
add('A', 'startValue -3', cx({ startValue: -3 }));
add('A', "startValue 'c'", cx({ startValue: 'c' }));
add('A', 'max 4 startValue 7: a pinned end ignores it', cx({ max: 4, startValue: 7 }));
const YEARS = cats(10, i => 2015 + i);
add('A', 'numeric categories 2015..2024, min 2018: an ordinal, not a name', cx({ data: YEARS, min: 2018 }));
add('A', "numeric categories 2015..2024, min '2018': a name", cx({ data: YEARS, min: '2018' }));
add('A', 'collected categories (no data), min 1', { xAxis: { type: 'category', min: 1 }, yAxis: { type: 'value' },
  series: [bar(T.map((t, i) => [t, V10[i]]))] });
add('A', 'y category min 2 max 5', cy({ min: 2, max: 5 }));
add('A', 'y category min 2 max 5 inverse', cy({ min: 2, max: 5, inverse: true }));

// B. blank
add('B', "min 'zz'", cx({ min: 'zz' }));
add('B', "min ''", cx({ min: '' }));
add('B', "min ' c': no trim", cx({ min: ' c' }));
add('B', "min '3': no numeric fallback", cx({ min: '3' }));
add('B', "min 'Infinity'", cx({ min: 'Infinity' }));
add('B', 'min {}', cx({ min: {} }));
add('B', "min ['c']", cx({ min: ['c'] }));
add('B', 'dataMin, no series', cx({ min: 'dataMin' }, []));
add('B', 'no categories at all, min 1 max 3: blank by the count alone', { xAxis: { type: 'category', min: 1, max: 3 },
  yAxis: { type: 'value' }, series: [] });
add('B', 'data [] with name pairs', cx({ data: [] }, [bar([['a', 1], ['b', 2], ['c', 3]])]));

// deferred by declaration
const D9 = deferred('declared-empty category list: extent from the series data (upstream\'s backward-compatibility path; '
  + 'the port draws nothing)');
add('B', 'data [] with plain values', cx({ data: [] }), D9);
add('B', 'data [] with plain values, min 1', cx({ data: [], min: 1 }), D9);
add('B', 'min 1e300', cx({ min: 1e300 }), deferred('category count past the port\'s cap: guarded, a documented divergence'));

// C. bars
add('C', 'min 2 max 6 boundaryGap false: the mapping', cx({ min: 2, max: 6, boundaryGap: false }));
add('C', 'stacked min 2 max 5', cx({ min: 2, max: 5 }, [bar(null, { stack: 's' }), bar(V10.map(v => v / 2), { stack: 's' })]));
add('C', 'min 2 max 6 clip false', cx({ min: 2, max: 6 }, [bar(null, { clip: false })]));
add('C', 'y category min 2 max 5 boundaryGap false', cy({ min: 2, max: 5, boundaryGap: false }));
add('C', 'min 5 max 5, two series: all at the centre', cx({ min: 5, max: 5 }, [bar(), bar(V10.map(v => v / 2))]));
add('C', 'min -2 max 12, two series', cx({ min: -2, max: 12 }, [bar(), bar(V10.map(v => v / 2))]));
add('C', 'min 2 max 6, 4-item series', cx({ min: 2, max: 6 }, [bar(V10.slice(0, 4))]));

// D. lines, areas and scatter
add('D', 'line min 2 max 6', cx({ min: 2, max: 6 }, [line()]));
add('D', 'line min 2 max 6 boundaryGap false', cx({ min: 2, max: 6, boundaryGap: false }, [line()]));
add('D', 'line min 2 max 6 clip false', cx({ min: 2, max: 6 }, [line(null, { clip: false })]));
add('D', 'line min 2 max 6 lineWidth 3: the fractional clip', cx({ min: 2, max: 6 }, [line(null, { lineStyle: { width: 3 } })]));
add('D', 'line min -2 max 12', cx({ min: -2, max: 12 }, [line()]));
add('D', 'area stack min 2 max 5', cx({ min: 2, max: 5 }, [line(null, { stack: 's', areaStyle: {} }),
  line(V10.map(v => v / 2), { stack: 's', areaStyle: {} })]));
add('D', 'scatter min 2 max 5', cx({ min: 2, max: 5 }, [{ type: 'scatter', data: V10 }]));
add('D', 'scatter min 2 max 5 clip false', cx({ min: 2, max: 5 }, [{ type: 'scatter', data: V10, clip: false }]));
add('D', 'line on a y category min 2 max 5', cy({ min: 2, max: 5 }, [line()]));
add('D', 'line on a y category min 2 max 5 clip false', cy({ min: 2, max: 5 }, [line(null, { clip: false })]));

// D, discriminating: a fractional area x and width + lineWidth not whole, so
// both the ceil and the floor + width++ step of the clip show
add('D', 'area line min 2 max 6 on a fractional grid (left 50.3, width 499.3): ceil and floor both show',
  cx({ min: 2, max: 6 }, [line(null, { areaStyle: {} })], { grid: { left: 50.3, width: 499.3 } }), { discriminates: 'clip' });

// E. labels and ticks
const P3GRID = { left: 60, right: 60, top: 40, bottom: 60 };
const CN = cats(60, i => 'Cat-' + String(i).padStart(2, '0'));
const p3 = x => ({ grid: P3GRID, xAxis: Object.assign({ type: 'category', data: CN }, x), yAxis: { type: 'value' },
  series: [bar(CN.map((_, i) => (i % 7) + 1))] });
add('E', '60 categories', p3({}));
add('E', '60 categories min 10 max 29', p3({ min: 10, max: 29 }));
add('E', '60 categories min 10 max 19', p3({ min: 10, max: 19 }));
add('E', '60 categories min 1 max 58', p3({ min: 1, max: 58 }));
add('E', '60 categories min 3 max 50 boundaryGap false: unitSpan over the mapping', p3({ min: 3, max: 50, boundaryGap: false }));
const C20 = cats(20, i => 'c' + i);
const c20 = x => ({ xAxis: Object.assign({ type: 'category', data: C20 }, x), yAxis: { type: 'value' }, series: [bar(C20.map((_, i) => i + 1))] });
const W900 = { W: 900 };
// found by search: upstream's unitSpan over the mapping [2.5, 50.5] (407 / 48)
// gives interval 10, the closed form 407 / 47 gives 9
add('E', '"Category N" x60 min 3 max 50 boundaryGap false at W 507: the auto interval needs the mapping', {
  xAxis: { type: 'category', data: cats(60, i => 'Category ' + (i + 1)), boundaryGap: false, min: 3, max: 50 }, yAxis: { type: 'value' },
  series: [bar(cats(60, i => (i % 7) + 1))] }, { W: 507, discriminates: 'unitSpan' });
add('E', '20 categories min 1 interval 2', c20({ min: 1, axisLabel: { interval: 2 } }), W900);
add('E', '20 categories min 1 max 6 interval 2', c20({ min: 1, max: 6, axisLabel: { interval: 2 } }), W900);
add('E', '20 categories min 1 max 7 interval 2', c20({ min: 1, max: 7, axisLabel: { interval: 2 } }), W900);
add('E', '20 categories min 5 max 15 interval 3', c20({ min: 5, max: 15, axisLabel: { interval: 3 } }), W900);
add('E', '20 categories min 5 max 15 interval 3 showMin/MaxLabel', c20({ min: 5, max: 15,
  axisLabel: { interval: 3, showMinLabel: true, showMaxLabel: true } }), W900);
add('E', '20 categories min 5 max 15 interval 3 boundaryGap false', c20({ min: 5, max: 15, boundaryGap: false,
  axisLabel: { interval: 3 }, axisTick: { show: true }, splitLine: { show: true } }), W900);
const C12 = cats(12, i => 'Category ' + (i + 1));
add('E', '12 categories min 1, labels 4, ticks 2, split lines and areas', { xAxis: { type: 'category', data: C12, min: 1,
  axisLabel: { interval: 4 }, axisTick: { show: true, interval: 2 }, splitLine: { show: true }, splitArea: { show: true } },
yAxis: { type: 'value' }, series: [bar(C12.map((_, i) => 10 + ((i + 1) * 37) % 50))] }, W900);
add('E', 'min 2 max 6 inverse: onBand ticks by an absolute band', cx({ min: 2, max: 6, inverse: true, axisTick: { show: true },
  splitLine: { show: true } }));
add('E', "min -2 max 12 formatter '{value}kg' interval 0", cx({ min: -2, max: 12, axisLabel: { formatter: '{value}kg', interval: 0 } }));
add('E', 'min -2 max 12 interval 0', cx({ min: -2, max: 12, axisLabel: { interval: 0 } }));

// F. symbol thinning (by the label ordinals)
const lineN = (n, x, s) => ({ xAxis: Object.assign({ type: 'category', data: cats(n, i => 'c' + i) }, x), yAxis: { type: 'value' },
  series: [line(cats(n, i => i + 1), s)] });
add('F', 'S1 20 categories interval 2 showAllSymbol false', lineN(20, { axisLabel: { interval: 2 } }, { showAllSymbol: false }));
add('F', 'S2 20 categories min 1 max 6 interval 2 showAllSymbol false', lineN(20, { min: 1, max: 6, axisLabel: { interval: 2 } },
  { showAllSymbol: false }));
add('F', 'S3 20 categories min 1 interval 2 showAllSymbol false', lineN(20, { min: 1, axisLabel: { interval: 2 } }, { showAllSymbol: false }));
add('F', 'S4 20 categories min 1 max 6 interval 2 auto', lineN(20, { min: 1, max: 6, axisLabel: { interval: 2 } }));
add('F', 'S6 name pairs from c1 (index != ordinal), min 1 max 6 interval 2 showAllSymbol false', {
  xAxis: { type: 'category', data: cats(20, i => 'c' + i), min: 1, max: 6, axisLabel: { interval: 2 } }, yAxis: { type: 'value' },
  series: [line(cats(19, i => ['c' + (i + 1), i + 2]), { showAllSymbol: false })] });
add('F', 'S5 200 categories min 3 max 150 auto', lineN(200, { min: 3, max: 150 }));

// G. the axis pointer, dispatched at integer pixels (y = 200 inside the grid)
const TIP = { tooltip: { trigger: 'axis', renderMode: 'richText' } };
const at = (...xs) => xs.map(x => [x, 200]);
add('G', 'bar min 2 max 6', cx({ min: 2, max: 6 }, null, TIP), { probes: at(40, 50, 99, 100, 149, 150, 549, 550) });
add('G', 'bar min 2 max 6 shadow', cx({ min: 2, max: 6 }, null, { tooltip: { trigger: 'axis', renderMode: 'richText',
  axisPointer: { type: 'shadow' } } }), { probes: at(50, 60, 300, 545, 549) });
add('G', 'line min 2 max 6 boundaryGap false', cx({ min: 2, max: 6, boundaryGap: false }, [line()], TIP), { probes: at(50, 112, 113, 550) });
add('G', 'bar min -2 max 12', cx({ min: -2, max: 12 }, null, TIP), { probes: at(51, 90, 110, 120, 420, 540) });
add('G', 'bar min 2 max 6, 4-item series', cx({ min: 2, max: 6 }, [bar(V10.slice(0, 4))], TIP), { probes: at(60, 160, 260, 360, 460) });
add('G', 'bar min 2 max 6 inverse', cx({ min: 2, max: 6, inverse: true }, null, TIP), { probes: at(60, 545) });
add('G', 'bar min 5 max 5', cx({ min: 5, max: 5 }, null, TIP), { probes: at(300) });
add('G', 'bar y category min 2 max 5', cy({ min: 2, max: 5 }, null, TIP), { probes: [[300, 40], [300, 100], [300, 200], [300, 359], [300, 360]] });

// ---------- run, check and write ----------

{
  const names = new Set();
  for (const c of cases) {
    if (names.has(c.name)) throw new Error('two cases named ' + c.name);
    names.add(c.name);
  }
}

const CHECKS = [1, 2, 3, 4, 5, 6, 7, 'disc', 'prod'];
const tally = {};
CHECKS.forEach(k => { tally[k] = [0, 0]; });
const failed = [];
const surprises = [];

function recordOf(c) {
  const r = runEither(c);
  const rec = { name: c.name, group: c.group, W: c.W, H: c.H, option: r.option };
  const byCheck = {};
  r.fails.forEach(f => { (byCheck[f.check] = byCheck[f.check] || []).push(f.msg); });
  const applies = { 5: r.series.some(s => s.type === 'bar' && !s.filtered),
    6: r.series.some(s => (s.type === 'line' || s.type === 'scatter') && !s.filtered), 7: !!c.probes, disc: !!c.discriminates };
  CHECKS.forEach(k => { if (applies[k] !== false && !c.deferred) tally[k][byCheck[k] ? 1 : 0]++; });
  const miss = Object.keys(byCheck).map(k => 'self-check ' + k + ': ' + byCheck[k].slice(0, 4).join('; ')
    + (byCheck[k].length > 4 ? ' (+' + (byCheck[k].length - 4) + ')' : '')).join(' | ');
  if (miss) failed.push(c.name + (c.deferred ? ' (deferred anyway)' : '') + ': ' + miss);
  if (!!c.deferred !== (r.nature.length > 0)) {
    surprises.push(c.name + ': ' + (c.deferred ? 'declared deferred (' + c.deferred + '), found nothing the port does not do'
      : 'declared compared, found ' + r.nature.join('; ')));
  }
  if (c.deferred || miss || r.nature.length) {
    rec.deferred = true;
    rec.why = [c.deferred, !c.deferred && r.nature.length ? r.nature.join('; ') : null, miss || null].filter(Boolean).join('; and ');
  }
  if (r.productionBuild) rec.productionBuild = true;
  rec.rect = hexRect(r.rect);
  rec.rectText = textRect(r.rect);
  rec.area = hexRect(r.area);
  rec.areaText = textRect(r.area);
  rec.axes = r.axes.map(axisOut);
  rec.series = r.series;
  if (c.probes) rec.probes = r.probes.map(probeOut);
  if (c.discriminates) rec.discriminates = Object.assign({ kind: c.discriminates }, r.disc);
  return rec;
}

const out = { source: 'ECharts ' + echarts.version, cap: CAP, probeValues: PROBE_VALUES, cases: cases.map(recordOf) };

// A compact, deterministic writer (coord-affine.js): a value whose one-line
// JSON fits in 150 characters stays on one line. A number JSON.stringify would
// write as an integer literal past 2^63 goes out in exponent form instead.
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
surprises.forEach(s => console.log('deferral not as declared: ' + s));
failed.forEach(f => console.log('self-check failed: ' + f));
out.cases.filter(c => c.deferred).forEach(c => console.log('deferred: ' + c.name + ' -- ' + c.why.slice(0, 300)));
console.log('self-checks (pass/cases): ' + CHECKS.map(k => k + ' ' + tally[k][0] + '/' + (tally[k][0] + tally[k][1])).join(', '));
fs.writeFileSync(OUT, json + '\n');
const nDef = out.cases.filter(c => c.deferred).length;
const probes = out.cases.reduce((n, c) => n + (c.probes ? c.probes.length : 0), 0);
console.log('wrote', OUT, (out.cases.length - nDef) + ' compared + ' + nDef + ' deferred cases; ' + probes + ' pointer probes');
const unexpected = cases.filter(c => !c.deferred).filter(c => out.cases.find(o => o.name === c.name).deferred);
if (unexpected.length || surprises.length) {
  console.log('FAILED: ' + unexpected.length + ' case(s) did not pass the self-checks, ' + surprises.length + ' deferral surprise(s)');
  process.exit(1);
}
process.exit(0);
