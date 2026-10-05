// Upstream's own answers for the dataZoom PROCESSING (wf60/upstream.md sections
// 1-3, 5 and 6; the slider picture of section 4 is out of scope): which axes each
// dataZoom targets and in which orient, the rangePropMode of each end, the
// settledOption it reads, which dataZoom hosts which AxisProxy, the 0%-100% base
// (ScaleRawExtentInfo noZoomEffMM) each hosted axis is reset against, the window
// calculateDataWindow returns (value, percent, percentInverted, valuePrecision)
// and the min/max spans, the zoomMM it pins on the axis, the rows every filter
// mode keeps (rawIndices), the approximate extents it sets, the values 'empty'
// NaNs out, the base the orthogonal (non-zoomed) axes are then built from, and,
// after the full update, each axis's scale extent / fixMM / zoomFixMM /
// interval / ticks and each kept row's layout.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models, the proxies, the
// raw-extent infos and the data stores directly -- never the SVG text.
// AxisProxy.prototype.calculateDataWindow is wrapped (the original still runs)
// to read the axis pixel extent at the moment the window is computed (the final
// resize changes it later), and DataZoomModel.prototype.setCalculatedRange is
// wrapped to snapshot every series' rows and approximate extents at the end of
// the dataZoom processor (before line sampling). Every chart is disposed in a
// finally.
//
//   node tools/advchart-oracle/datazoom-window.js
//
// writes tests/fixtures/advchart-datazoom-window.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as visualmap-encode.js / visualmap-piecewise.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (+Infinity 7ff0000000000000, -Infinity fff0000000000000,
//            NaN 7ff8000000000000). Every hex field has a readable twin (xText
//            beside x; String(v), '-0' for negative zero). A hex field that can
//            be absent is null (and its twin null).
//   NaN in an option  JSON cannot carry NaN, so a case option that holds one is
//            recorded with the NaN written as null and a top-level marker
//            `__nan: ['dataZoom.0.start', ...]` listing the dotted paths (array
//            indices as numbers; `dataZoom.start` when dataZoom is an object).
//            The option FED to setOption is the recorded one with every listed
//            path set back to NaN and without the `__nan` key.
//   dims     series dimensions are referred to by their index in
//            data.dimensions; dimNames gives the names with every NUL written as
//            '/' (the stack dims are '__\0ecstackresult_...'), so the fixture
//            holds no \u0000.
//
// Top level
//   source, W, H, seed, api (the upstream call behind each field), notes[]
//   cases[]  one per chart:
//     id, groups, note, width, height, gallery (file name or null), option (as
//     fed, see above; null for the big gallery files: load the gallery file,
//     fed verbatim)
//     dataZooms[] in component order (the toolbox's internal 'select' dataZooms
//       -- one per x axis then per y axis, appended after the user's -- included):
//       index, subType ('slider' | 'inside' | 'select'), orient, noTarget
//       targets    [{dim ('x' | 'y'), axisIndex}] in eachTargetAxis order
//       hosts      the targets whose AxisProxy this dataZoom hosts (proxy.hostedBy)
//       rangePropMode [m0, m1] ('percent' | 'value')
//       settled    dz.settledOption after init: only the keys present, in upstream
//                  key order (start, end, startValue, endValue, throttle as
//                  written; a value-mode end's percent key is present with null);
//                  NaN written as the string 'NaN'
//       filterMode dz.get('filterMode') -- the mode this dataZoom filters its
//                  hosted axes with
//       window     findRepresentativeAxisProxy().getWindow() (first hosted proxy,
//                  else the first targeted one), or null (noTarget):
//                  {value [hex, hex], percent [hex, hex], percentInverted
//                  [hex, hex], valuePrecision hex (NaN possible)} + ...Text
//       minMaxSpan the same proxy's getMinMaxSpan(): minSpan, minValueSpan,
//                  maxSpan, maxValueSpan (hex | null) + Text, or null
//     axes[]  every xAxis then yAxis component:
//       dim, index, gridIndex, type ('category' | 'value' | 'time' | 'log'),
//       categoryCount (category: model.getCategories().length, else null)
//       zoomed     an AxisProxy exists; hostedBy its host's dataZoom index or null
//       pxSpan     |axis.getExtent()| read INSIDE calculateDataWindow (the raw
//                  grid rect), hex | null (not zoomed) + Text
//       pxSpanFinal |axis.getExtent()| after the render (hex + Text)
//       dataMM, noZoom  scale.rawExtentInfo internals after the update: the data
//                  union and noZoomEffMM ([hex, hex] + Text). For a zoomed axis
//                  noZoom is the proxy's _extent (the 0%-100% base); for the
//                  others it is what the coordinate system built from the
//                  (filtered, sampled) data.
//       zoomMM     [hex | null, hex | null] + Text (null: that end not pinned)
//       extent     scale.getExtent() after the update [hex, hex] + Text
//       fixMM, zoomFixMM  [bool, bool] (the raw-extent info after makeFinal)
//       interval   value: scale.getConfig().interval; log: the interval stub's
//                  (log space); category / time: null. hex | null + Text
//       ticks      scale.getTicks() values [hex] + Text (null for category)
//     series[]  every series (eachRawSeries):
//       index, type, name, filtered (legend-deselected: nothing else recorded)
//       coordinateSystem, xAxisIndex, yAxisIndex
//       dimNames, axisDims {x: [dim], y: [dim]} (data.mapDimensionsAll),
//       stackedDim, stackResultDim (dim | null; getCalculationInfo)
//       rawCount   getRawData().count()
//       count, rawIndices  after the full update (data.getRawIndex(i), i < count)
//       stage      null, or -- when the rows or approximate extents at the end of
//                  the dataZoom processor differ from the final ones (line
//                  sampling) -- {count, rawIndices, approx} at that moment
//       approx     for each dim mapped to a ZOOMED axis of this series (axis dim
//                  order x, y; mapDimensionsAll order): {coordDim, dim, extent
//                  [hex, hex] | null + Text} (data._approximateExtent: null when
//                  none was set)
//       emptied    only when a host of one of the series' axes filters with
//                  'empty': [{coordDim, dim, values}] for each dim of that axis,
//                  values[rawRow] = the processed store value (hex, NaN possible)
//                  or null for a row not in the data + valuesText
//       layout     line / scatter: per kept row [hex x, hex y] (null when not a
//                  finite point; a line reads the Float32 'points' layout); bar:
//                  {x, y, width, height} hex (getItemLayout); other types null.
//                  layoutText beside it.
//   guards[]  one per mutation: id, mutation, named (cases that must change),
//             changed (cases the mutated transcription no longer reproduces), ok
//             = named is a subset of changed, differs (first differing fields of
//             each named case)
//
// ---------------------------------------------------------------------------
// The transcription (checked field by field against every recorded value):
// the toolbox internal-option creator for the 'select' dataZooms, the subtype
// defaulter, _fillSpecifiedTargetAxis / queryReferringComponents
// (MULTIPLE_REFERRING: index, array, 'all', 'none', false, nonexistent),
// _fillAutoTargetAxisByOrient (first axis + the same grid), the auto orient,
// retrieveRawOption + _updateRangeUse + _doInit (settledOption), the
// first-dataZoom-hosts rule, overallReset's order (reset every hosted axis of a
// dataZoom, then filter them), ScaleRawExtentInfo (the approximate-extent union
// over getDataDimensionsOnAxis with the log filter, min/max, boundaryGap,
// category 0..n-1, needIncludeZero, the reversal, startValue / bar
// requireStartValue, log sanitize), _updateMinMaxSpan, calculateDataWindow
// (linearMap, asc, sliderMove with addSafe / getPrecision / getPrecisionSafe,
// getAcceptableTickPrecision, round = +toFixed, the clamp, the 0 / 100 snap with
// ceil / floor), the setZoomMM rule, filterData ('none', 'weakFilter', 'empty',
// 'filter' through selectRange, then setApproximateExtent),
// findRepresentativeAxisProxy, and the alignTicks rule
// (prepareAlignToInCoordSysCreate + getAlignTo: an aligned axis is reset last
// with the percentInverted of the axis it aligns to, which wins over its own
// start / end). Its inputs are the option as fed, each axis's type,
// categoryCount, category names (the ordinal meta, in memory only) and
// recorded pxSpan, each series' dims (dimNames, axisDims, stack dims, axis
// indices, filtered) and the raw store values (getRawData().getStore(), kept
// in memory only -- the port rebuilds them from the option). The base of a
// non-zoomed axis is computed after all dataZooms, from the final rows of a
// sampled series (the coordinate system update runs after the sampling
// processor).
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every case; the anchors (W2 [5, 14], W4 33.33 / 66.67
// precision 2, W5 base [0, 1100], W6 [24, 156], W7 131, W9 modes and windows,
// W10 shifts, W12 spans, W16 [3, 7], A1 y1 [6.68, 26.77], T2 / T3 targets,
// T4 / T5 orients, T5 / T6 y windows, T7 host window, T9 noTarget, F3's y base
// equal to F4's, F5 bottom series empty, area-simple sampled after the zoom);
// every zoom-pinned end is the scale extent end after the update (except a
// zero-span window, which the nice step widens); every guard is ok; the
// fixture holds no \u0000; the written JSON parses back to the record; two
// generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-datazoom-window.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- the seeded Math.random (the port's xorshift32) ----------
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

// ---------- number records ----------
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
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const hexOrNull = v => (v == null ? null : hex(v));
const textOrNull = v => (v == null ? null : text(v));
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const numRecN = (name, v) => ({ [name]: hexOrNull(v), [name + 'Text']: textOrNull(v) });
const pairRec = (name, a) => ({ [name]: a.map(hex), [name + 'Text']: a.map(text) });
const pairRecN = (name, a) => ({ [name]: a.map(hexOrNull), [name + 'Text']: a.map(textOrNull) });
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const arr = v => (v == null ? [] : Array.isArray(v) ? v : [v]);
const J = v => JSON.stringify(v === undefined ? null : v);
// a deep copy that keeps +-Infinity and NaN (a JSON round trip would not)
function clone(v) {
  if (Array.isArray(v)) return v.map(clone);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = clone(v[k]);
    return o;
  }
  return v;
}

// ---------- the NaN-in-option convention ----------
function encodeNaN(v, p, paths) {
  if (typeof v === 'number') {
    must(Number.isFinite(v) || Number.isNaN(v), 'an infinite number in an option at ' + p);
    if (Number.isNaN(v)) { paths.push(p); return null; }
    return v;
  }
  if (Array.isArray(v)) return v.map((x, i) => encodeNaN(x, p ? p + '.' + i : String(i), paths));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) if (v[k] !== undefined) o[k] = encodeNaN(v[k], p ? p + '.' + k : k, paths);
    return o;
  }
  must(typeof v !== 'function' && v !== undefined, 'an option value JSON cannot carry at ' + p);
  return v;
}
function recordOption(src) {
  const paths = [];
  const o = encodeNaN(src, '', paths);
  if (paths.length) o.__nan = paths;
  return o;
}
function fedOption(rec) {
  const o = JSON.parse(JSON.stringify(rec));
  const paths = o.__nan || [];
  delete o.__nan;
  for (const p of paths) {
    const keys = p.split('.');
    let t = o;
    for (let i = 0; i < keys.length - 1; i++) t = t[Array.isArray(t) ? +keys[i] : keys[i]];
    const last = keys[keys.length - 1];
    must(t[Array.isArray(t) ? +last : last] === null, 'the __nan path ' + p + ' is not null');
    t[Array.isArray(t) ? +last : last] = NaN;
  }
  return o;
}

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================

// util/number.ts:67-120
function linearMap(val, domain, range, clamp) {
  const d0 = domain[0];
  const d1 = domain[1];
  const r0 = range[0];
  const r1 = range[1];
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
    if (val === d1) return r1;
  }
  return (val - d0) / subDomain * subRange + r0;
}
// util/number.ts:222-237 (TO_FIXED_SUPPORTED_PRECISION_MAX = 20)
function round(x, precision, mut) {
  if (isNaN(precision)) return +x;
  precision = Math.min(Math.max(0, precision), 20);
  if (mut && mut.mathRound) {
    const e = Math.pow(10, precision);
    return Math.round(x * e) / e;
  }
  return +(+x).toFixed(precision);
}
// util/number.ts:265-315
function getPrecisionSafe(val) {
  const str = val.toString().toLowerCase();
  const eIndex = str.indexOf('e');
  const exp = eIndex > 0 ? +str.slice(eIndex + 1) : 0;
  const significandPartLen = eIndex > 0 ? eIndex : str.length;
  const dotIndex = str.indexOf('.');
  const decimalPartLen = dotIndex < 0 ? 0 : significandPartLen - 1 - dotIndex;
  return Math.max(0, decimalPartLen - exp);
}
function getPrecision(val) {
  val = +val;
  if (isNaN(val)) return 0;
  if (val > 1e-14) {
    let e = 1;
    for (let i = 0; i < 15; i++, e *= 10) {
      if (Math.round(val * e) / e === val) return i;
    }
  }
  return getPrecisionSafe(val);
}
// util/number.ts:454-462
function addSafe(val0, val1, mut) {
  if (mut && mut.plainAdd) return val0 + val1;
  const maxPrecision = Math.max(getPrecision(val0), getPrecision(val1));
  const sum = val0 + val1;
  return maxPrecision > 20 ? sum : round(sum, maxPrecision);
}
// util/number.ts:339-369
function getAcceptableTickPrecision(dataExtent, pxSpan, pxDiffAcceptable) {
  const dataSpan = Math.abs(dataExtent[1] - dataExtent[0]);
  if (!isFinite(dataSpan) || dataSpan === 0) return NaN;
  const dataExp2 = Math.log(2 * Math.abs(pxDiffAcceptable || 1) * Math.abs(dataSpan)) / Math.LN10;
  const pxExp = Math.log(Math.abs(pxSpan)) / Math.LN10;
  let precision = Math.max(0, Math.ceil(-dataExp2 + pxExp));
  if (!isFinite(precision)) precision = NaN;
  return precision;
}
// asc on two numbers with the (a, b) => a - b comparator: V8 swaps iff cmp(a1, a0) < 0
function asc2(a) {
  if (a[1] - a[0] < 0) { const t = a[0]; a[0] = a[1]; a[1] = t; }
  return a;
}
// component/helper/sliderMove.ts
function restrict(value, extend) {
  return Math.min(extend[1] != null ? extend[1] : Infinity, Math.max(extend[0] != null ? extend[0] : -Infinity, value));
}
function getSpanSign(handleEnds, handleIndex) {
  const dist = handleEnds[handleIndex] - handleEnds[1 - handleIndex];
  return { span: Math.abs(dist), sign: dist > 0 ? -1 : dist < 0 ? 1 : handleIndex ? -1 : 1 };
}
function sliderMove(delta, handleEnds, extent, handleIndex, minSpan, maxSpan, mut) {
  if (mut.noShift) {
    handleEnds[0] = restrict(handleEnds[0], extent);
    handleEnds[1] = restrict(handleEnds[1], extent);
    return handleEnds;
  }
  delta = delta || 0;
  const extentSpan = addSafe(extent[1], -extent[0], mut);
  if (minSpan != null) minSpan = restrict(minSpan, [0, extentSpan]);
  if (maxSpan != null) maxSpan = Math.max(maxSpan, minSpan != null ? minSpan : 0);
  if (handleIndex === 'all') {
    let handleSpan = Math.abs(addSafe(handleEnds[1], -handleEnds[0], mut));
    handleSpan = restrict(handleSpan, [0, extentSpan]);
    minSpan = maxSpan = restrict(handleSpan, [minSpan, maxSpan]);
    handleIndex = 0;
  }
  handleEnds[0] = restrict(handleEnds[0], extent);
  handleEnds[1] = restrict(handleEnds[1], extent);
  const originalDistSign = getSpanSign(handleEnds, handleIndex);
  handleEnds[handleIndex] += delta;
  const extentMinSpan = minSpan || 0;
  const realExtent = extent.slice();
  if (originalDistSign.sign < 0) realExtent[0] = addSafe(realExtent[0], extentMinSpan, mut);
  else realExtent[1] = addSafe(realExtent[1], -extentMinSpan, mut);
  handleEnds[handleIndex] = restrict(handleEnds[handleIndex], realExtent);
  let currDistSign = getSpanSign(handleEnds, handleIndex);
  if (minSpan != null && (currDistSign.sign !== originalDistSign.sign || currDistSign.span < minSpan)) {
    handleEnds[1 - handleIndex] = addSafe(handleEnds[handleIndex], originalDistSign.sign * minSpan, mut);
  }
  currDistSign = getSpanSign(handleEnds, handleIndex);
  if (maxSpan != null && currDistSign.span > maxSpan) {
    handleEnds[1 - handleIndex] = addSafe(handleEnds[handleIndex], currDistSign.sign * maxSpan, mut);
  }
  return handleEnds;
}

// util/number.ts parseDate (TIME_REG), only the explicit-offset branch (the
// local-time branch would make the fixture depend on the host's time zone)
const TIME_REG = /^(?:(\d{4})(?:[-\/](\d{1,2})(?:[-\/](\d{1,2})(?:[T ](\d{1,2})(?::(\d{1,2})(?::(\d{1,2})(?:[.,](\d+))?)?)?(Z|[\+\-]\d\d:?\d\d)?)?)?)?)?$/;
function parseDateMs(value) {
  if (typeof value !== 'string') return value == null ? NaN : Math.round(value);
  const m = TIME_REG.exec(value);
  if (!m) return NaN;
  must(m[8], 'a date string without an offset (local time): ' + value);
  let hour = +m[4] || 0;
  if (m[8].toUpperCase() !== 'Z') hour -= +m[8].slice(0, 3);
  return Date.UTC(+m[1], +(m[2] || 1) - 1, +m[3] || 1, hour, +(m[5] || 0), +m[6] || 0, m[7] ? +m[7].substring(0, 3) : 0);
}
// Scale#parse per scale type (scale/Ordinal.ts, Interval.ts, Time.ts; Log uses Interval's)
function scaleParse(ax, val) {
  if (ax.type === 'category') {
    if (val == null) return NaN;
    if (typeof val === 'string') {
      // OrdinalMeta.getOrdinal: createHashMap(categories), a later duplicate overwrites
      const k = ax.categories.lastIndexOf(val);
      return k < 0 ? NaN : k;
    }
    return Math.round(val);
  }
  if (ax.type === 'time') return typeof val === 'number' ? Math.round(val) : parseDateMs(val);
  return val == null || val === '' ? NaN : Number(val);
}
const isValidNumberForExtent = v => v != null && isFinite(v);
const isValidBoundsForExtent = (a, b) => isValidNumberForExtent(a) && isValidNumberForExtent(b) && a <= b;
const isNullableNumberFinite = v => v != null && isFinite(v);
// LogScale.sanitize
function logSanitize(value, dataExtent) {
  if (isValidBoundsForExtent(dataExtent[0], dataExtent[1]) && isNullableNumberFinite(value) && value <= 0) value = dataExtent[0];
  return value;
}
// parsePercent(x, 1) of util/number.ts (parsePositionOption)
function parsePercent1(option) {
  switch (option) {
    case 'center': case 'middle': option = '50%'; break;
    case 'left': case 'top': option = '0%'; break;
    case 'right': case 'bottom': option = '100%'; break;
    default: break;
  }
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * 1 + 0;
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}
function parseBoundaryGap(ax, aopt) {
  if (ax.type === 'category') return [0, 0];
  let bg = hasOwn(aopt, 'boundaryGap') ? aopt.boundaryGap : [0, 0];
  if (typeof bg === 'boolean') bg = null;
  const a = Array.isArray(bg) ? bg : [bg, bg];
  const item = o => parsePercent1(typeof o === 'boolean' ? 0 : o) || 0;
  return [item(a[0]), item(a[1])];
}
function parseMinMax(ax, v) {
  return v == null ? null : (typeof v === 'number' && isNaN(v)) ? NaN : scaleParse(ax, v);
}

// the series state the processor sees
function storeExtent(s, dim, logFilter, mut) {
  let min = Infinity;
  let max = -Infinity;
  const col = s.vals[dim];
  for (const ri of s.indices) {
    if (mut.emptyAdapts && s.hidden.has(ri)) continue;
    const v = col[ri];
    if (!logFilter || v > 0) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
  }
  return [min, max];
}
function dimsOnAxis(s, axisDim) {
  const out = [];
  for (const d of s.rec.axisDims[axisDim] || []) {
    const e = (s.rec.stackedDim != null && d === s.rec.stackedDim) ? s.rec.stackResultDim : d;
    if (!out.includes(e)) out.push(e);
  }
  return out;
}
const BAR_TYPES = ['bar', 'pictorialBar'];
function baseAxisDim(ctx, s) {
  const tx = ctx.axis('x', s.rec.xAxisIndex).type;
  const ty = ctx.axis('y', s.rec.yAxisIndex).type;
  if (tx === 'category') return 'x';
  if (ty === 'category') return 'y';
  if (tx === 'time') return 'x';
  if (ty === 'time') return 'y';
  return 'x';
}
function seriesOnAxis(ctx, states, dim, idx) {
  return states.filter(s => s.rec.coordinateSystem === 'cartesian2d' && s.rec[dim + 'AxisIndex'] === idx);
}
// coord/scaleRawExtentInfo.ts: scaleRawExtentInfoCreateDeal + the ScaleRawExtentInfo constructor
function computeBase(ctx, states, dim, idx, mut) {
  const ax = ctx.axis(dim, idx);
  const aopt = ax.opt;
  const isOrd = ax.type === 'category';
  const ext = [Infinity, -Infinity];
  let requireStartValue = false;
  for (const s of seriesOnAxis(ctx, states, dim, idx)) {
    for (const d of dimsOnAxis(s, dim)) {
      const e = s.approx[d] || storeExtent(s, d, ax.type === 'log', mut);
      if (isValidBoundsForExtent(e[0], e[1])) {
        if (e[0] < ext[0]) ext[0] = e[0];
        if (e[1] > ext[1]) ext[1] = e[1];
      }
    }
    if (BAR_TYPES.includes(s.rec.type) && baseAxisDim(ctx, s) !== dim) requireStartValue = true;
  }
  must(aopt.dataMin == null && aopt.dataMax == null, 'axis dataMin/dataMax are not transcribed');
  const dataMM = ext.slice();
  const span0 = dataMM[1] - dataMM[0];
  if (!(isFinite(span0) && span0 >= 0)) dataMM[0] = dataMM[1] = NaN;
  const nz = [];
  const fix = [false, false];
  must(typeof aopt.min !== 'function' && typeof aopt.max !== 'function', 'min/max callbacks are not transcribed');
  if (aopt.min === 'dataMin') { nz[0] = dataMM[0]; fix[0] = true; } else { nz[0] = parseMinMax(ax, aopt.min); fix[0] = nz[0] != null; }
  if (aopt.max === 'dataMax') { nz[1] = dataMM[1]; fix[1] = true; } else { nz[1] = parseMinMax(ax, aopt.max); fix[1] = nz[1] != null; }
  const bg = parseBoundaryGap(ax, aopt);
  const span = !isOrd ? (dataMM[1] - dataMM[0] || Math.abs(dataMM[0])) : null;
  const catEmptyArray = isOrd && Array.isArray(aopt.data) && !aopt.data.length;
  const len = ax.categoryCount;
  if (nz[0] == null) nz[0] = isOrd ? (catEmptyArray ? dataMM[0] : len ? 0 : NaN) : dataMM[0] - bg[0] * span;
  if (nz[1] == null) nz[1] = isOrd ? (catEmptyArray ? dataMM[1] : len ? len - 1 : NaN) : dataMM[1] + bg[1] * span;
  if (!isValidNumberForExtent(nz[0])) nz[0] = NaN;
  if (!isValidNumberForExtent(nz[1])) nz[1] = NaN;
  const incl0Applicable = ax.type === 'value';
  const incl0 = incl0Applicable && !aopt.scale && !mut.noIncludeZero;
  if (incl0) {
    if (nz[0] > 0 && nz[1] > 0 && !fix[0]) nz[0] = 0;
    if (nz[0] < 0 && nz[1] < 0 && !fix[1]) nz[1] = 0;
  }
  if (nz[0] > nz[1]) nz.reverse();
  let startValue = parseMinMax(ax, aopt.startValue);
  const startValueSpecified = startValue != null;
  if (!isNullableNumberFinite(startValue) && requireStartValue) startValue = ax.type === 'log' ? 1 : 0;
  if (isNullableNumberFinite(startValue) && (startValueSpecified || !incl0Applicable || incl0)) {
    if (startValue < nz[0] && !fix[0]) { nz[0] = startValue; fix[0] = true; } else if (startValue > nz[1] && !fix[1]) { nz[1] = startValue; fix[1] = true; }
  }
  if (ax.type === 'log') {
    nz[0] = logSanitize(nz[0], dataMM);
    nz[1] = logSanitize(nz[1], dataMM);
  }
  return { dataMM, noZoom: nz };
}

// DataZoomModel: target axes and orient (_resetTarget and helpers)
const DZ_DIMS = ['x', 'y', 'radius', 'angle', 'single'];
function referring(ctx, dim, index, id) {
  must(id == null, 'axis ids are not transcribed');
  if (index == null) return null;
  const list = ctx.axesOf(dim);
  if (index === 'none' || index === false) return [];
  if (index === 'all') return list.map((_, i) => i);
  const out = [];
  for (const i of arr(index)) if (list[i]) out.push(i);
  return out;
}
function resolveTargets(ctx, o, mut) {
  const map = [];
  let specified = false;
  for (const dim of DZ_DIMS) {
    const got = referring(ctx, dim, o[dim + 'AxisIndex'], o[dim + 'AxisId']);
    if (got == null) continue;
    specified = true;
    const list = [];
    for (const i of got) if (!list.includes(i)) list.push(i);
    map.push({ dim, list });
  }
  let orient;
  if (specified) {
    let first;
    for (const m of map) if (!first && m.list.length) first = m.dim;
    orient = o.orient || (mut.orientLast ? ((map.filter(m => m.list.length).pop() || {}).dim === 'y' ? 'vertical' : 'horizontal')
      : first === 'y' ? 'vertical' : 'horizontal');
  } else {
    orient = o.orient || 'horizontal';
    const axisDim = orient === 'vertical' ? 'y' : 'x';
    const list = ctx.axesOf(axisDim);
    if (list.length) {
      const got = [0];
      const grid0 = list[0].gridIndex || 0;
      for (let i = 1; i < list.length; i++) if (mut.autoAllAxes || (list[i].gridIndex || 0) === grid0) got.push(i);
      map.push({ dim: axisDim, list: got });
    } else {
      must(false, 'the auto target without an axis of the orient dim is not transcribed');
    }
  }
  const targets = [];
  for (const m of map) for (const i of m.list) targets.push({ dim: m.dim, axisIndex: i });
  return { targets, orient, noTarget: !targets.length };
}
// retrieveRawOption + _updateRangeUse + _doInit
function rangeModes(o, mut) {
  const settled = {};
  for (const k of ['start', 'end', 'startValue', 'endValue', 'throttle']) if (hasOwn(o, k)) settled[k] = o[k];
  const modes = ['percent', 'percent'];
  [['start', 'startValue'], ['end', 'endValue']].forEach((names, i) => {
    const p = settled[names[0]] != null;
    const v = settled[names[1]] != null;
    if (mut.percentAlways) return;
    if (p && !v) modes[i] = 'percent';
    else if (!p && v) modes[i] = 'value';
    else if (o.rangeMode) modes[i] = o.rangeMode[i];
    else if (p) modes[i] = 'percent';
  });
  [['start', 'startValue'], ['end', 'endValue']].forEach((names, i) => {
    if (modes[i] === 'value') settled[names[0]] = null;
  });
  return { modes, settled };
}
// the toolbox's internal 'select' dataZooms (component/toolbox/feature/DataZoom.ts)
function toolboxSelects(ctx, option) {
  const tb = arr(option.toolbox)[0];
  if (!tb || !tb.feature || tb.feature.dataZoom == null) return [];
  const f = tb.feature.dataZoom;
  const out = [];
  for (const dim of ['x', 'y']) {
    let index = f[dim + 'AxisIndex'];
    must(f[dim + 'AxisId'] == null, 'toolbox axis ids are not transcribed');
    if (index == null) index = 'all';
    for (const i of referring(ctx, dim, index, null)) {
      out.push({ type: 'select', $fromToolbox: true, filterMode: f.filterMode || 'filter', [dim + 'AxisIndex']: i });
    }
  }
  return out;
}

// AxisProxy._updateMinMaxSpan
function minMaxSpan(ax, o, dataExtent, mut) {
  const spans = {};
  for (const mm of ['min', 'max']) {
    let percentSpan = mut.spansIgnored ? undefined : o[mm + 'Span'];
    let valueSpan = mut.spansIgnored ? undefined : o[mm + 'ValueSpan'];
    if (valueSpan != null) valueSpan = scaleParse(ax, valueSpan);
    if (valueSpan != null) percentSpan = linearMap(dataExtent[0] + valueSpan, dataExtent, [0, 100], true);
    else if (percentSpan != null) valueSpan = linearMap(percentSpan, [0, 100], dataExtent, true) - dataExtent[0];
    spans[mm + 'Span'] = percentSpan;
    spans[mm + 'ValueSpan'] = valueSpan;
  }
  return spans;
}
// AxisProxy.calculateDataWindow
function calculateDataWindow(ax, settled, modes, dataExtent, spans, pxSpan, mut) {
  const percentExtent = [0, 100];
  const percentWindow = [];
  const valueWindow = [];
  let hasPropModeValue = false;
  const needRound = [false, false];
  ['start', 'end'].forEach((prop, idx) => {
    let boundPercent = settled[prop];
    let boundValue = settled[prop + 'Value'];
    if (modes[idx] === 'percent') {
      if (boundPercent == null) boundPercent = percentExtent[idx];
      boundValue = linearMap(boundPercent, percentExtent, dataExtent);
      needRound[idx] = true;
    } else {
      hasPropModeValue = true;
      if (boundValue == null) boundValue = dataExtent[idx];
      else {
        boundValue = scaleParse(ax, boundValue);
        if (ax.type === 'log' && !mut.noLogSanitize) boundValue = logSanitize(boundValue, dataExtent);
      }
      boundPercent = linearMap(boundValue, dataExtent, percentExtent);
      if (mut.valueRounded) needRound[idx] = true;
    }
    valueWindow[idx] = boundValue == null || isNaN(boundValue) ? dataExtent[idx] : boundValue;
    percentWindow[idx] = boundPercent == null || isNaN(boundPercent) ? percentExtent[idx] : boundPercent;
  });
  if (!mut.noAsc) {
    asc2(valueWindow);
    asc2(percentWindow);
  }
  const restrictSet = (fromWindow, toWindow, fromExtent, toExtent, toValue) => {
    const suffix = toValue ? 'Span' : 'ValueSpan';
    sliderMove(0, fromWindow, fromExtent, 'all', spans['min' + suffix], spans['max' + suffix], mut);
    for (let i = 0; i < 2; i++) {
      toWindow[i] = linearMap(fromWindow[i], fromExtent, toExtent, true);
      if (toValue) needRound[i] = true;
    }
  };
  if (hasPropModeValue) restrictSet(valueWindow, percentWindow, dataExtent, percentExtent, false);
  else restrictSet(percentWindow, valueWindow, percentExtent, dataExtent, true);
  const isOrdOrTime = ax.type === 'category' || ax.type === 'time';
  const precision = isOrdOrTime ? 0 : getAcceptableTickPrecision(valueWindow, mut.finalPxSpan ? ax.pxSpanFinal : pxSpan, 0.5);
  [[0, Math.ceil], [1, Math.floor]].forEach(([idx, ceilOrFloor]) => {
    if (!needRound[idx] || !isFinite(precision)) return;
    if (!mut.noRound) valueWindow[idx] = round(valueWindow[idx], precision, mut);
    valueWindow[idx] = Math.min(dataExtent[1], Math.max(dataExtent[0], valueWindow[idx]));
    if (percentWindow[idx] === percentExtent[idx]) {
      valueWindow[idx] = dataExtent[idx];
      if (isOrdOrTime) valueWindow[idx] = ceilOrFloor(valueWindow[idx]);
    }
  });
  const percentInverted = [linearMap(valueWindow[0], dataExtent, percentExtent, true), linearMap(valueWindow[1], dataExtent, percentExtent, true)];
  return { value: valueWindow, percent: percentWindow, percentInverted, valuePrecision: precision };
}
// AxisProxy.filterData
function filterData(ctx, states, t, dz, win, mut) {
  const filterMode = dz.filterMode;
  const w = mut.percentForAxis ? win.percent : win.value;
  if (filterMode === 'none') return;
  for (const s of seriesOnAxis(ctx, states, t.dim, t.axisIndex)) {
    const dims = s.rec.axisDims[t.dim] || [];
    if (!dims.length) continue;
    if (filterMode === 'weakFilter') {
      s.indices = s.indices.filter(ri => {
        let leftOut;
        let rightOut;
        let hasValue;
        for (const d of dims) {
          const value = s.vals[d][ri];
          const thisHasValue = !isNaN(value);
          const thisLeftOut = value < w[0];
          const thisRightOut = value > w[1];
          if (thisHasValue && !thisLeftOut && !thisRightOut) return true;
          thisHasValue && (hasValue = true);
          thisLeftOut && (leftOut = true);
          thisRightOut && (rightOut = true);
        }
        if (mut.weakKeepsAllNaN && !hasValue) return true;
        return !!(hasValue && leftOut && rightOut);
      });
    } else {
      for (const d of dims) {
        if (filterMode === 'empty') {
          s.emptiedDims.add(d);
          for (const ri of s.indices) {
            const v = s.vals[d][ri];
            if (!(v >= w[0] && v <= w[1])) {
              s.vals[d][ri] = NaN;
              s.hidden.add(ri);
            }
          }
        } else {
          s.indices = s.indices.filter(ri => {
            const v = s.vals[d][ri];
            return (v >= w[0] && v <= w[1]) || (isNaN(v) && !mut.filterDropsNaN);
          });
        }
      }
    }
    for (const d of dims) s.approx[d] = w.slice();
  }
}

// coord/axisAlignTicks prepareAlignToInCoordSysCreate: per grid and dim, over the
// value / log axes in index order, the lowest-index axis without alignTicks (or,
// when all request it, the lowest-index one) is the one the others align to
function alignToMap(c, axOpts) {
  const m = new Map();
  for (const dim of ['x', 'y']) {
    const byGrid = new Map();
    for (const a of c.axes) {
      if (a.dim !== dim || (a.type !== 'value' && a.type !== 'log')) continue;
      const o = axOpts[dim][a.index] || {};
      must(o.breaks == null, c.id + ': axis breaks are not transcribed');
      if (!byGrid.has(a.gridIndex)) byGrid.set(a.gridIndex, []);
      byGrid.get(a.gridIndex).push(a.index);
    }
    for (const idxs of byGrid.values()) {
      idxs.sort((p, q) => p - q);
      let to;
      const need = [];
      for (let i = idxs.length - 1; i >= 0; i--) {
        const o = axOpts[dim][idxs[i]] || {};
        if (o.alignTicks && o.interval == null) need.push(idxs[i]);
        else to = idxs[i];
      }
      if (to == null) to = need.pop();
      if (to != null) for (const i of need) m.set(dim + i, dim + to);
    }
  }
  return m;
}

// the whole processor on one case: returns the flat field map
function simulate(c, mut) {
  const option = fedOption(c.option);
  const axOpts = { x: arr(option.xAxis), y: arr(option.yAxis) };
  const axRec = {};
  for (const a of c.axes) {
    axRec[a.dim + a.index] = {
      type: a.type, categoryCount: a.categoryCount, categories: a.categories, opt: axOpts[a.dim][a.index] || {},
      pxSpan: a.pxSpan == null ? null : num(a.pxSpan), pxSpanFinal: num(a.pxSpanFinal), gridIndex: a.gridIndex,
    };
  }
  const ctx = {
    axis: (dim, idx) => { const r = axRec[dim + idx]; must(r, c.id + ': no axis ' + dim + idx); return r; },
    axesOf: dim => (dim === 'x' || dim === 'y' ? c.axes.filter(a => a.dim === dim).map(a => axRec[a.dim + a.index]) : []),
  };
  const mkState = s => ({
    rec: s, indices: Array.from({ length: s.rawCount }, (_, i) => i), vals: s.store.map(col => (col ? Float64Array.from(col) : null)),
    approx: {}, hidden: new Set(), emptiedDims: new Set(),
  });
  const visible = c.series.filter(s => !s.filtered);
  const states = visible.map(mkState);
  const initial = visible.map(mkState);
  // the dataZoom list: the user's (subtype defaulter: slider), then the toolbox's
  const dzs = arr(option.dataZoom).map(o => Object.assign({ subType: o.type || 'slider', o }))
    .concat(toolboxSelects(ctx, option).map(o => ({ subType: 'select', o })));
  dzs.forEach((dz, k) => {
    dz.index = k;
    Object.assign(dz, resolveTargets(ctx, dz.o, mut), rangeModes(dz.o, mut));
    dz.filterMode = dz.o.filterMode || 'filter';
  });
  // proxies: one per axis, hosted by the first dataZoom that targets it
  const host = new Map();
  for (const dz of dzs) for (const t of dz.targets) if (!host.has(t.dim + t.axisIndex) || mut.hostLast) host.set(t.dim + t.axisIndex, dz.index);
  const proxy = new Map();
  const alignTo = alignToMap(c, axOpts);
  const reset = (dz, t, alignToPercentInverted) => {
    const key = t.dim + t.axisIndex;
    const ax = ctx.axis(t.dim, t.axisIndex);
    const base = computeBase(ctx, mut.baseUnfiltered ? initial : states, t.dim, t.axisIndex, mut);
    const dataExtent = base.noZoom.slice();
    const spans = minMaxSpan(ax, dz.o, dataExtent, mut);
    must(ax.pxSpan != null, c.id + ': ' + key + ' reset without a recorded pxSpan');
    let opt = dz.settled;
    if (alignToPercentInverted) {
      // zrender defaults(target, source): the TARGET's start / end (the alignTo axis's
      // percentInverted) win; only keys null in the target are copied from settledOption
      opt = { start: alignToPercentInverted[0], end: alignToPercentInverted[1] };
      for (const k of Object.keys(dz.settled)) if (opt[k] == null || (mut.alignUserWins && dz.settled[k] != null)) opt[k] = dz.settled[k];
    }
    const win = calculateDataWindow(ax, opt, dz.modes, dataExtent, spans, ax.pxSpan, mut);
    const w = mut.percentForAxis ? win.percent : win.value;
    const zoomMM = [win.percent[0] !== 0 || mut.pinEnds ? w[0] : null, win.percent[1] !== 100 || mut.pinEnds ? w[1] : null];
    proxy.set(key, { host: dz.index, base, win, spans, zoomMM });
  };
  for (const dz of dzs) {
    const mine = dz.targets.filter(t => host.get(t.dim + t.axisIndex) === dz.index);
    if (mut.interleaved) {
      for (const t of mine) { reset(dz, t); filterData(ctx, states, t, dz, proxy.get(t.dim + t.axisIndex).win, mut); }
    } else {
      // overallReset: an axis aligned (alignTicks) to another axis this dataZoom targets is reset last,
      // with that axis's percentInverted
      const needAlign = [];
      for (const t of mine) {
        const to = alignTo.get(t.dim + t.axisIndex);
        if (to && !mut.noAlign && dz.targets.some(u => u.dim + u.axisIndex === to)) needAlign.push([t, to]);
        else reset(dz, t);
      }
      for (const [t, to] of needAlign) {
        must(proxy.has(to), c.id + ': the alignTo axis ' + to + ' was not reset first');
        reset(dz, t, proxy.get(to).win.percentInverted);
      }
      for (const t of mine) filterData(ctx, states, t, dz, proxy.get(t.dim + t.axisIndex).win, mut);
    }
  }
  const F = {};
  // the stage record of every series (end of the processor)
  for (const s of states) {
    const r = s.rec;
    F['s' + r.index + '.rawIndices'] = J(s.indices);
    F['s' + r.index + '.approx'] = J(approxList(r, (d) => s.approx[d]));
    // the dims of every axis of this series whose host filters with 'empty'
    let emptied = null;
    const kept = new Set(s.indices);
    for (const ad of ['x', 'y']) {
      if (r.coordinateSystem !== 'cartesian2d') continue;
      const p = proxy.get(ad + r[ad + 'AxisIndex']);
      if (!p || dzs[p.host].filterMode !== 'empty') continue;
      emptied = emptied || [];
      for (const d of r.axisDims[ad]) {
        emptied.push({ coordDim: ad, dim: d, values: Array.from({ length: r.rawCount }, (_, ri) => (kept.has(ri) ? hex(s.vals[d][ri]) : null)) });
      }
    }
    F['s' + r.index + '.emptied'] = J(emptied);
  }
  // the coordinate-system update: the other axes from the filtered (and sampled) rows
  for (const s of states) if (s.rec.stage) s.indices = s.rec.rawIndices.slice();
  for (const a of c.axes) {
    const key = a.dim + a.index;
    const p = proxy.get(key);
    const tag = 'axis.' + key + '.';
    F[tag + 'zoomed'] = J(!!p);
    F[tag + 'hostedBy'] = J(p ? p.host : null);
    const base = p ? p.base : computeBase(ctx, states, a.dim, a.index, mut);
    F[tag + 'dataMM'] = J(base.dataMM.map(hex));
    F[tag + 'noZoom'] = J(base.noZoom.map(hex));
    F[tag + 'zoomMM'] = J(p ? p.zoomMM.map(hexOrNull) : [null, null]);
  }
  for (const dz of dzs) {
    const tag = 'dz' + dz.index + '.';
    F[tag + 'subType'] = J(dz.subType);
    F[tag + 'orient'] = J(dz.orient);
    F[tag + 'noTarget'] = J(dz.noTarget);
    F[tag + 'targets'] = J(dz.targets);
    F[tag + 'hosts'] = J(dz.targets.filter(t => host.get(t.dim + t.axisIndex) === dz.index));
    F[tag + 'rangePropMode'] = J(dz.modes);
    F[tag + 'settled'] = J(settledJson(dz.settled));
    F[tag + 'filterMode'] = J(dz.filterMode);
    // findRepresentativeAxisProxy
    let rep = null;
    for (const t of dz.targets) {
      const p = proxy.get(t.dim + t.axisIndex);
      if (p && p.host === dz.index) { rep = p; break; }
      if (!rep) rep = p;
    }
    F[tag + 'window'] = J(rep ? windowHex(rep.win) : null);
    F[tag + 'minMaxSpan'] = J(rep ? spansHex(rep.spans) : null);
  }
  return F;
}
function approxList(r, get) {
  return r.approxDims.map(a => { const e = get(a.dim); return { coordDim: a.coordDim, dim: a.dim, extent: e ? e.map(hex) : null }; });
}
function settledJson(s) {
  const o = {};
  for (const k of Object.keys(s)) o[k] = typeof s[k] === 'number' && isNaN(s[k]) ? 'NaN' : s[k];
  return o;
}
const windowHex = w => ({ value: w.value.map(hex), percent: w.percent.map(hex), percentInverted: w.percentInverted.map(hex), valuePrecision: hex(w.valuePrecision) });
const SPAN_KEYS = ['minSpan', 'minValueSpan', 'maxSpan', 'maxValueSpan'];
const spansHex = s => { const o = {}; for (const k of SPAN_KEYS) o[k] = hexOrNull(s[k]); return o; };

// the same flat map read from a record
function flatRecord(c) {
  const F = {};
  for (const s of c.series) {
    if (s.filtered) continue;
    const st = s.stage || s;
    F['s' + s.index + '.rawIndices'] = J(st.rawIndices);
    F['s' + s.index + '.approx'] = J(st.approx.map(a => ({ coordDim: a.coordDim, dim: a.dim, extent: a.extent })));
    F['s' + s.index + '.emptied'] = J(s.emptied == null ? null : s.emptied.map(e => ({ coordDim: e.coordDim, dim: e.dim, values: e.values })));
  }
  for (const a of c.axes) {
    const tag = 'axis.' + a.dim + a.index + '.';
    F[tag + 'zoomed'] = J(a.zoomed);
    F[tag + 'hostedBy'] = J(a.hostedBy);
    F[tag + 'dataMM'] = J(a.dataMM);
    F[tag + 'noZoom'] = J(a.noZoom);
    F[tag + 'zoomMM'] = J(a.zoomMM);
  }
  for (const dz of c.dataZooms) {
    const tag = 'dz' + dz.index + '.';
    F[tag + 'subType'] = J(dz.subType);
    F[tag + 'orient'] = J(dz.orient);
    F[tag + 'noTarget'] = J(dz.noTarget);
    F[tag + 'targets'] = J(dz.targets);
    F[tag + 'hosts'] = J(dz.hosts);
    F[tag + 'rangePropMode'] = J(dz.rangePropMode);
    F[tag + 'settled'] = J(dz.settled);
    F[tag + 'filterMode'] = J(dz.filterMode);
    F[tag + 'window'] = J(dz.window ? { value: dz.window.value, percent: dz.window.percent, percentInverted: dz.window.percentInverted, valuePrecision: dz.window.valuePrecision } : null);
    F[tag + 'minMaxSpan'] = J(dz.minMaxSpan ? (() => { const o = {}; for (const k of SPAN_KEYS) o[k] = dz.minMaxSpan[k]; return o; })() : null);
  }
  return F;
}
function caseDiffs(c, mut) {
  const a = flatRecord(c);
  const b = simulate(c, mut);
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => a[k] !== b[k]).map(k => ({
    field: k, upstream: a[k] === undefined ? null : a[k].slice(0, 240), mutated: b[k] === undefined ? null : b[k].slice(0, 240),
  }));
}

// =====================================================================
// Recording
// =====================================================================
let CAP = null;
let hooked = false;
const SINGLE_REFERRING = { useDefault: true, enableAll: false, enableNone: false };
function hookProto() {
  if (hooked) return;
  runChart({ xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {}, series: [{ type: 'line', data: [1, 2] }], dataZoom: [{}] }, ch => {
    const dz = ch.getModel().getComponent('dataZoom', 0);
    const px = dz.findRepresentativeAxisProxy();
    const pproto = Object.getPrototypeOf(px);
    must(hasOwn(pproto, 'calculateDataWindow') && hasOwn(pproto, 'reset'), 'AxisProxy has no calculateDataWindow');
    const origCdw = pproto.calculateDataWindow;
    pproto.calculateDataWindow = function (opt) {
      if (CAP) {
        const m = this.getAxisModel();
        const e = m.axis.getExtent();
        must(!CAP.cdw.has(m.uid), 'calculateDataWindow twice on one axis');
        CAP.cdw.set(m.uid, { pxSpan: Math.abs(e[1] - e[0]) });
      }
      return origCdw.call(this, opt);
    };
    let dproto = Object.getPrototypeOf(dz);
    while (dproto && !hasOwn(dproto, 'setCalculatedRange')) dproto = Object.getPrototypeOf(dproto);
    must(dproto, 'DataZoomModel has no setCalculatedRange');
    const origScr = dproto.setCalculatedRange;
    dproto.setCalculatedRange = function (opt) {
      if (CAP && !CAP.stage) {
        const stage = new Map();
        this.ecModel.eachSeries(sm => {
          const d = sm.getData();
          stage.set(sm.seriesIndex, {
            count: d.count(), rawIndices: Array.from({ length: d.count() }, (_, i) => d.getRawIndex(i)),
            approx: Object.assign({}, d._approximateExtent),
          });
        });
        CAP.stage = stage;
      }
      return origScr.call(this, opt);
    };
  });
  hooked = true;
}

function runChart(option, fn) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(option);
    return fn(chart);
  } finally {
    chart.dispose();
  }
}

const safeName = n => String(n).replace(/\0/g, '/');
function windowRec(w) {
  return Object.assign(pairRec('value', w.value), pairRec('percent', w.percent), pairRec('percentInverted', w.percentInverted), numRec('valuePrecision', w.valuePrecision));
}
function spansRec(s) {
  const o = {};
  for (const k of SPAN_KEYS) Object.assign(o, numRecN(k, s[k]));
  return o;
}

function recordCase(def) {
  const src = def.gallery ? JSON.parse(fs.readFileSync(path.join(GALLERY, def.gallery + '.json'), 'utf8')) : def.option;
  const optRec = recordOption(src);
  const fed = fedOption(optRec);
  CAP = { cdw: new Map(), stage: null };
  try {
    return runChart(fed, chart => recordChart(def, chart, optRec));
  } finally {
    CAP = null;
  }
}

function recordChart(def, chart, optRec) {
  const gm = chart.getModel();
  const rec = { id: def.id, groups: def.groups, note: def.note, width: chart.getWidth(), height: chart.getHeight(), gallery: def.gallery || null, option: optRec };
  for (const t of ['singleAxis', 'radiusAxis', 'angleAxis', 'parallelAxis']) must(!gm.getComponent(t), def.id + ': a ' + t + ' (not transcribed)');
  // the dataZooms
  const dzModels = gm.findComponents({ mainType: 'dataZoom' });
  const proxyOf = new Map();
  rec.dataZooms = dzModels.map(dz => {
    const targets = [];
    dz.eachTargetAxis((dim, axisIndex) => targets.push({ dim, axisIndex }));
    const hosts = [];
    for (const t of targets) {
      const p = dz.getAxisProxy(t.dim, t.axisIndex);
      must(p, def.id + ': no proxy on a target');
      const m = gm.getComponent(t.dim + 'Axis', t.axisIndex);
      must(!proxyOf.has(m.uid) || proxyOf.get(m.uid) === p, def.id + ': two proxies on one axis');
      proxyOf.set(m.uid, p);
      if (p.hostedBy(dz)) hosts.push(t);
    }
    const px = dz.findRepresentativeAxisProxy();
    const settled = {};
    for (const k of Object.keys(dz.settledOption)) {
      const v = dz.settledOption[k];
      settled[k] = typeof v === 'number' && isNaN(v) ? 'NaN' : v;
    }
    return {
      index: dz.componentIndex, subType: dz.subType, orient: dz.getOrient(), noTarget: dz.noTarget(), targets, hosts,
      rangePropMode: dz.getRangePropMode(), settled, filterMode: dz.get('filterMode'),
      window: px ? windowRec(px.getWindow()) : null, minMaxSpan: px ? spansRec(px.getMinMaxSpan()) : null,
    };
  });
  // the axes
  const hostIndex = p => dzModels.findIndex(dz => p.hostedBy(dz));
  rec.axes = [];
  const zoomedDims = new Map(); // axis key -> true
  for (const mainType of ['xAxis', 'yAxis']) {
    gm.eachComponent(mainType, m => {
      const axis = m.axis;
      const scale = axis.scale;
      const info = scale.rawExtentInfo;
      must(info && info._i, def.id + ': ' + mainType + m.componentIndex + ' has no raw extent info');
      const i = info._i;
      const p = proxyOf.get(m.uid);
      const cdw = CAP.cdw.get(m.uid);
      must(!!p === !!cdw, def.id + ': a proxy without a calculateDataWindow (or the reverse) on ' + mainType + m.componentIndex);
      if (p) {
        must(p._extent.length === 2 && p._extent.every((v, k) => Object.is(v, i.noZoomEffMM[k])), def.id + ': proxy._extent is not noZoomEffMM');
        zoomedDims.set(axis.dim + m.componentIndex, true);
      }
      const type = axis.type;
      const fin = axis.getExtent();
      const a = {
        dim: axis.dim, index: m.componentIndex, gridIndex: m.getCoordSysModel().componentIndex, type,
        categoryCount: type === 'category' ? m.getCategories().length : null,
        zoomed: !!p, hostedBy: p ? hostIndex(p) : null,
      };
      Object.assign(a, numRecN('pxSpan', cdw ? cdw.pxSpan : null), numRec('pxSpanFinal', Math.abs(fin[1] - fin[0])),
        pairRec('dataMM', i.dataMM), pairRec('noZoom', i.noZoomEffMM),
        pairRecN('zoomMM', [0, 1].map(k => (i.zoomMM[k] == null ? null : i.zoomMM[k]))), pairRec('extent', scale.getExtent()),
        { fixMM: i.fixMM.slice(), zoomFixMM: i.zoomFixMM.slice() });
      const interval = type === 'value' ? scale.getConfig().interval : type === 'log' ? scale.intervalStub.getConfig().interval : null;
      Object.assign(a, numRecN('interval', interval));
      if (type === 'category') Object.assign(a, { ticks: null, ticksText: null });
      else {
        const ticks = scale.getTicks().map(t => t.value);
        Object.assign(a, { ticks: ticks.map(hex), ticksText: ticks.map(text) });
      }
      Object.defineProperty(a, 'categories', { value: type === 'category' ? scale.getOrdinalMeta().categories.map(x => x) : null, enumerable: false });
      rec.axes.push(a);
    });
  }
  // the series
  rec.series = [];
  gm.eachRawSeries(sm => {
    const filtered = gm.isSeriesFiltered(sm);
    const s = { index: sm.seriesIndex, type: sm.subType, name: safeName(sm.name), filtered };
    if (filtered) { rec.series.push(s); return; }
    const data = sm.getData();
    const raw = sm.getRawData();
    const names = data.dimensions.slice();
    const di = n => { const k = names.indexOf(n); must(k >= 0, def.id + ': a dim not in data.dimensions'); return k; };
    const cs = sm.get('coordinateSystem');
    s.coordinateSystem = cs;
    s.xAxisIndex = cs === 'cartesian2d' ? sm.getReferringComponents('xAxis', SINGLE_REFERRING).models[0].componentIndex : null;
    s.yAxisIndex = cs === 'cartesian2d' ? sm.getReferringComponents('yAxis', SINGLE_REFERRING).models[0].componentIndex : null;
    s.dimNames = names.map(safeName);
    s.axisDims = { x: data.mapDimensionsAll('x').map(di), y: data.mapDimensionsAll('y').map(di) };
    const sd = data.getCalculationInfo('stackedDimension');
    const sr = data.getCalculationInfo('stackResultDimension');
    s.stackedDim = sd ? di(sd) : null;
    s.stackResultDim = sr && sd ? di(sr) : null;
    s.rawCount = raw.count();
    s.count = data.count();
    s.rawIndices = Array.from({ length: s.count }, (_, i) => data.getRawIndex(i));
    // the dims of zoomed axes
    const approxDims = [];
    for (const ad of ['x', 'y']) {
      if (cs !== 'cartesian2d' || !zoomedDims.has(ad + s[ad + 'AxisIndex'])) continue;
      for (const d of s.axisDims[ad]) approxDims.push({ coordDim: ad, dim: d });
    }
    const approxOf = ext => approxDims.map(a => {
      const e = ext[names[a.dim]];
      return Object.assign({ coordDim: a.coordDim, dim: a.dim }, e ? pairRec('extent', e) : { extent: null, extentText: null });
    });
    s.approx = approxOf(data._approximateExtent || {});
    const stage = CAP.stage && CAP.stage.get(sm.seriesIndex);
    s.stage = null;
    if (stage) {
      const sa = approxOf(stage.approx);
      if (J(stage.rawIndices) !== J(s.rawIndices) || J(sa) !== J(s.approx)) s.stage = { count: stage.count, rawIndices: stage.rawIndices, approx: sa };
    }
    // 'empty' hosts
    s.emptied = null;
    const store = data.getStore();
    for (const ad of ['x', 'y']) {
      if (cs !== 'cartesian2d') continue;
      const m = gm.getComponent(ad + 'Axis', s[ad + 'AxisIndex']);
      const p = proxyOf.get(m.uid);
      if (!p || p._dataZoomModel.get('filterMode') !== 'empty') continue;
      s.emptied = s.emptied || [];
      for (const d of s.axisDims[ad]) {
        const values = new Array(s.rawCount).fill(null);
        const idx = data.getDimensionIndex(names[d]);
        for (let i = 0; i < s.count; i++) values[data.getRawIndex(i)] = store.get(idx, i);
        s.emptied.push({ coordDim: ad, dim: d, values: values.map(v => (v == null ? null : hex(v))), valuesText: values.map(v => (v == null ? null : text(v))) });
      }
    }
    // the layout
    s.layout = null;
    s.layoutText = null;
    if (s.type === 'line' || s.type === 'scatter') {
      const pts = data.getLayout('points');
      const pt = i => {
        if (pts && pts.length === 2 * s.count) return [pts[2 * i], pts[2 * i + 1]];
        const l = data.getItemLayout(i);
        return l ? [l[0], l[1]] : null;
      };
      must(s.count === 0 || pt(0) != null, def.id + ' s' + s.index + ': no point layout');
      const list = Array.from({ length: s.count }, (_, i) => pt(i));
      s.layout = list.map(p => (p && isFinite(p[0]) && isFinite(p[1]) ? p.map(hex) : null));
      s.layoutText = list.map(p => (p && isFinite(p[0]) && isFinite(p[1]) ? p.map(text) : null));
    } else if (s.type === 'bar') {
      const list = Array.from({ length: s.count }, (_, i) => data.getItemLayout(i));
      const RK = ['x', 'y', 'width', 'height'];
      s.layout = list.map(l => (l ? Object.fromEntries(RK.map(k => [k, hex(l[k])])) : null));
      s.layoutText = list.map(l => (l ? Object.fromEntries(RK.map(k => [k, text(l[k])])) : null));
    }
    // the transcription's inputs kept in memory only
    const rs = raw.getStore();
    must(!rs.getIndices || raw.count() === rs.count(), def.id + ': a raw store with indices');
    const used = new Set(s.axisDims.x.concat(s.axisDims.y));
    if (s.stackResultDim != null) used.add(s.stackResultDim);
    const storeCols = names.map((n, k) => {
      if (!used.has(k)) return null;
      const idx = raw.getDimensionIndex(n);
      return Array.from({ length: s.rawCount }, (_, i) => rs.get(idx, i));
    });
    Object.defineProperty(s, 'store', { value: storeCols, enumerable: false });
    Object.defineProperty(s, 'approxDims', { value: approxDims, enumerable: false });
    rec.series.push(s);
  });
  return rec;
}

// ---------- the cases ----------
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);
// 20 values with fractions (the value axis precision shows)
const V20 = [12.34, 45.67, 23.456, 78.9, 34.5, 56.78, 90.12, 11.1, 67.89, 43.21, 29.99, 88.8, 14.7, 63.3, 51.05, 37.7, 72.25, 19.9, 84.4, 58.6];
const catChart = (type, dz, n, extra) => Object.assign({
  xAxis: { type: 'category', data: cat(n || 20) }, yAxis: { type: 'value' },
  series: [{ type, data: V20.concat(V20).slice(0, n || 20) }], dataZoom: dz,
}, extra || {});
const pts101 = (f) => Array.from({ length: 11 }, (_, i) => [i * 10, f(i)]);
const XS = Array.from({ length: 11 }, (_, i) => [i * 10, (i * 37) % 23]);
const scatterChart = (dz, data, xAxis, extra) => Object.assign({
  xAxis: Object.assign({ type: 'value' }, xAxis || {}), yAxis: { type: 'value' },
  series: [{ type: 'scatter', data: data || XS }], dataZoom: dz,
}, extra || {});
const DAY = 86400000;
const T0 = Date.UTC(2020, 0, 1);
const timeData = Array.from({ length: 20 }, (_, i) => [T0 + i * DAY, V20[i]]);
const timeChart = dz => ({ useUTC: true, xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: timeData }], dataZoom: dz });
const twoGrids = (dz, xType) => ({
  grid: [{ bottom: '55%' }, { top: '55%' }],
  xAxis: [{ type: xType || 'category', gridIndex: 0, data: xType === 'value' ? undefined : cat(20) }, { type: xType || 'category', gridIndex: 1, data: xType === 'value' ? undefined : cat(20) }],
  yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
  series: [{ type: 'line', data: V20 }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: V20.map(v => v * 3) }], dataZoom: dz,
});
function clean(o) { return JSON.parse(JSON.stringify(o)); }

const CASES = [
  // window / model
  { id: 'W1', groups: ['W'], note: "untyped dataZoom object {} on a 20-category bar: the subtype defaulter gives 'slider'; full window, no zoomMM",
    option: catChart('bar', {}) },
  { id: 'W2', groups: ['W'], note: '{start 25, end 75} on 20 categories: 4.75 -> 5, 14.25 -> 14; percentInverted from the rounded values',
    option: catChart('line', [{ start: 25, end: 75 }]) },
  { id: 'W3', groups: ['W'], note: '{start 12.5, end 87.5} on 21 categories [0, 20]: exactly 2.5 -> 3 and 17.5 -> 18 (toFixed on the exact binary value)',
    option: catChart('line', [{ start: 12.5, end: 87.5 }], 21) },
  { id: 'W3b', groups: ['W'], note: 'start 250/19 on 20 categories: 250/19/100*19 is not exactly 2.5 in binary -- toFixed(0) rounds the exact value',
    option: catChart('line', [{ start: 250 / 19, end: 1850 / 19 }]) },
  { id: 'W3n', groups: ['W'], note: 'value x on [-100, 0], start 62.875 end 90: the window end lands on -37.125 at precision 2 (toFixed rounds away from zero, Math.round would not)',
    option: scatterChart([{ start: 62.875, end: 90 }], Array.from({ length: 11 }, (_, i) => [-100 + i * 10, i])) },
  { id: 'W4', groups: ['W'], note: 'value x scatter {start 33.333, end 66.667}: precision 2 from getAcceptableTickPrecision, value [33.33, 66.67], percent kept',
    option: scatterChart([{ start: 33.333, end: 66.667 }]) },
  { id: 'W4c', groups: ['W'], note: 'containLabel with long y labels: the precision uses the RAW grid width (pxSpan 760 -> 2), not the final one (pxSpanFinal 684.8 -> 1); window 15.123-87.123',
    option: scatterChart([{ start: 15.123, end: 87.123 }], XS.map(p => [p[0], p[1] * 1e7]), null, { grid: { left: 20, right: 20, containLabel: true } }) },
  { id: 'W5', groups: ['W'], note: 'value x without scale, data 1000..1100: needIncludeZero makes the base [0, 1100]; start 20 -> 220',
    option: scatterChart([{ start: 20 }], XS.map(p => [p[0] + 1000, p[1]])) },
  { id: 'W6', groups: ['W'], note: 'axis min -20 max 200, 20% / 80% -> 24 / 156',
    option: scatterChart([{ start: 20, end: 80 }], null, { min: -20, max: 200 }) },
  { id: 'W7', groups: ['W'], note: 'log x (base [1, 1000]), 13% / 77%: percent linear in raw space, 130.87 -> 131',
    option: { xAxis: { type: 'log' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [[1, 1], [10, 3], [100, 5], [1000, 2]] }], dataZoom: [{ start: 13, end: 77 }] } },
  { id: 'W7b', groups: ['W'], note: 'log x, {startValue -5, endValue 500}: LogScale.sanitize maps the non-positive startValue to the data min (1)',
    option: { xAxis: { type: 'log' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [[1, 1], [10, 3], [100, 5], [1000, 2]] }], dataZoom: [{ startValue: -5, endValue: 500 }] } },
  { id: 'W8a', groups: ['W'], note: 'time x line, 13% / 77%: the window rounded to integer ms (precision 0); useUTC',
    option: timeChart([{ start: 13, end: 77 }]) },
  { id: 'W8b', groups: ['W'], note: "time x, startValue / endValue as ISO strings with Z (parseDate's UTC branch), never rounded",
    option: timeChart([{ startValue: '2020-01-05T00:00:00Z', endValue: '2020-01-12T12:30:00.250Z' }]) },
  { id: 'W16', groups: ['W'], note: "category {startValue 'c3', endValue 'c7'}: OrdinalScale.parse of a category name; percent = ordinal / 19 * 100",
    option: catChart('bar', [{ startValue: 'c3', endValue: 'c7' }]) },
  { id: 'W9a', groups: ['W'], note: '{startValue 30} only: modes [value, percent], end 100%', option: scatterChart([{ startValue: 30 }]) },
  { id: 'W9b', groups: ['W'], note: '{start 10, end 90, startValue 50, endValue 60}: percent wins -> [10, 90]',
    option: scatterChart([{ start: 10, end: 90, startValue: 50, endValue: 60 }]) },
  { id: 'W9c', groups: ['W'], note: 'the same plus rangeMode [value, value] -> [50, 60]',
    option: scatterChart([{ start: 10, end: 90, startValue: 50, endValue: 60, rangeMode: ['value', 'value'] }]) },
  { id: 'W9d', groups: ['W'], note: 'mixed {startValue 30, end 66.667}: value mode anywhere -> sliderMove in value space; the percent end recomputed from its value, its value still rounded',
    option: scatterChart([{ startValue: 30, end: 66.667 }]) },
  { id: 'W9e', groups: ['W'], note: '{startValue 12.345678, endValue 67.891234}: value-mode ends are never rounded',
    option: scatterChart([{ startValue: 12.345678, endValue: 67.891234 }]) },
  { id: 'W10a', groups: ['W'], note: 'reversed {start 80, end 20}: asc -> [20, 80]', option: scatterChart([{ start: 80, end: 20 }]) },
  { id: 'W10b', groups: ['W'], note: '{start -10, end 50}: sliderMove shifts keeping the span -> [0, 60]', option: scatterChart([{ start: -10, end: 50 }]) },
  { id: 'W10c', groups: ['W'], note: '{startValue -10, endValue 50} -> [0, 60]', option: scatterChart([{ startValue: -10, endValue: 50 }]) },
  { id: 'W10d', groups: ['W'], note: '{start 60, end 130} -> [30, 100]', option: scatterChart([{ start: 60, end: 130 }]) },
  { id: 'W10e', groups: ['W'], note: '{startValue -50, endValue 250}: wider than the extent -> the whole extent', option: scatterChart([{ startValue: -50, endValue: 250 }]) },
  { id: 'W11a', groups: ['W'], note: "{start NaN, end 50}: NaN counts as given (percent mode), then falls back to 0 (the NaN is fed through the option's __nan marker)",
    option: scatterChart([{ start: NaN, end: 50 }]) },
  { id: 'W11b', groups: ['W'], note: 'zero-span base (scale: true, every x = 5): precision NaN -> no rounding, no clamp, no 0/100 snap; both ends pinned',
    option: scatterChart([{ start: 30, end: 70 }], [[5, 1], [5, 2], [5, 3]], { scale: true }) },
  { id: 'W11c', groups: ['W'], note: 'empty series data on a value x: base [NaN, NaN] -> value window NaN, zoomMM NaN',
    option: { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [] }], dataZoom: [{ start: 30, end: 70 }] } },
  { id: 'W12a', groups: ['W'], note: 'minSpan 20 with 40-45 -> [40, 60]', option: scatterChart([{ start: 40, end: 45, minSpan: 20 }]) },
  { id: 'W12b', groups: ['W'], note: 'maxValueSpan 30 with 0-90 -> [0, 30] (the value span turned into a percent span)', option: scatterChart([{ start: 0, end: 90, maxValueSpan: 30 }]) },
  { id: 'W12c', groups: ['W'], note: 'minValueSpan 5 days on a time axis with 40-42%', option: timeChart([{ start: 40, end: 42, minValueSpan: 5 * DAY }]) },
  { id: 'W12d', groups: ['W'], note: 'minSpan 10 AND minValueSpan 30 with 40-45: the value span wins (-> [40, 70])', option: scatterChart([{ start: 40, end: 45, minSpan: 10, minValueSpan: 30 }]) },
  { id: 'W13a', groups: ['W'], note: 'bars on a value y zoomed (yAxisIndex 0 -> vertical), 20-80: the bar startValue 0 in the base',
    option: catChart('bar', [{ yAxisIndex: 0, start: 20, end: 80 }]) },
  { id: 'W13b', groups: ['W'], note: 'bars on a value x (the base axis: containShape), zoom 50-100: the 50% end is pinned, the 100% end is not, so contain-shape widens it (base 105, extent end 110)',
    option: scatterChart([{ start: 50, end: 100 }], null, null, { series: [{ type: 'bar', data: XS.map(p => [p[0] + 5, p[1] + 1]) }] }) },
  { id: 'W13c', groups: ['W'], note: 'the same bars zoomed 10-90: both ends pinned, no contain-shape expansion',
    option: scatterChart([{ start: 10, end: 90 }], null, null, { series: [{ type: 'bar', data: XS.map(p => [p[0] + 5, p[1] + 1]) }] }) },
  { id: 'W14', groups: ['W'], note: "boundaryGap ['10%', '10%'] on a scale value x (data 50..150 -> base [40, 160]), 25-75",
    option: scatterChart([{ start: 25, end: 75 }], XS.map(p => [p[0] + 50, p[1]]), { scale: true, boundaryGap: ['10%', '10%'] }) },
  { id: 'W15', groups: ['W'], note: '{start -10.1, end 50.2}: shifted into the extent; addSafe turns the span 60.300000000000004 into 60.3, so the end percent is exactly 60.3',
    option: scatterChart([{ start: -10.1, end: 50.2 }]) },
  // targets / hosting
  { id: 'W14b', groups: ['W'], note: "boundaryGap ['30%', '30%'] with 0-50: the 0% end is the base's (20), measured once before the filter -- re-measured from the kept rows it would be 35 (splitNumber 20: a step of 5 keeps it)",
    option: scatterChart([{ start: 0, end: 50 }], XS.map(p => [p[0] + 50, p[1]]), { scale: true, boundaryGap: ['30%', '30%'], splitNumber: 20 }) },
  { id: 'T1', groups: ['T'], note: 'xAxisIndex [0, 1] over two grids, 30-70', option: twoGrids([{ xAxisIndex: [0, 1], start: 30, end: 70 }]) },
  { id: 'T2', groups: ['T'], note: 'auto target with two grids: only x0 (the first x axis and those on its grid)', option: twoGrids([{ start: 30, end: 70 }]) },
  { id: 'T2b', groups: ['T'], note: 'auto target, two x axes on ONE grid: both are targeted', option: {
    xAxis: [{ type: 'category', data: cat(20) }, { type: 'category', data: cat(20), position: 'top' }], yAxis: { type: 'value' },
    series: [{ type: 'line', data: V20 }, { type: 'line', xAxisIndex: 1, data: V20.map(v => v / 2) }], dataZoom: [{ start: 30, end: 70 }] } },
  { id: 'T3', groups: ['T'], note: '{xAxis value, yAxis category} + dataZoom [{}]: x0 (the auto choice ignores the axis type)',
    option: { xAxis: { type: 'value' }, yAxis: { type: 'category', data: cat(20) }, series: [{ type: 'bar', data: V20 }], dataZoom: [{}] } },
  { id: 'T4', groups: ['T'], note: 'yAxisIndex 0 -> vertical', option: scatterChart([{ yAxisIndex: 0, start: 20, end: 80 }]) },
  { id: 'T5', groups: ['T'], note: '{xAxisIndex 0, yAxisIndex 0}: horizontal; both axes reset before either is filtered -> y window [6, 14]',
    option: scatterChart([{ xAxisIndex: 0, yAxisIndex: 0, start: 30, end: 70 }]) },
  { id: 'T6', groups: ['T'], note: '[{x 30-70}, {y 20-80}]: the y base comes from the x-filtered data -> [3.8, 15.2]',
    option: scatterChart([{ xAxisIndex: 0, start: 30, end: 70 }, { yAxisIndex: 0, start: 20, end: 80 }]) },
  { id: 'T7', groups: ['T'], note: '[inside 10-50, slider 60-90] on one axis: the first hosts; the slider shows 10-50',
    option: scatterChart([{ type: 'inside', start: 10, end: 50 }, { type: 'slider', start: 60, end: 90 }]) },
  { id: 'T8', groups: ['T'], note: "xAxisIndex 'all' over two grids", option: twoGrids([{ xAxisIndex: 'all', start: 30, end: 70 }]) },
  { id: 'T9a', groups: ['T'], note: 'xAxisIndex 3 (nonexistent): specified but empty -> noTarget', option: scatterChart([{ xAxisIndex: 3, start: 30, end: 70 }]) },
  { id: 'T9b', groups: ['T'], note: "xAxisIndex 'none' -> noTarget", option: scatterChart([{ xAxisIndex: 'none', start: 30, end: 70 }]) },
  { id: 'T9c', groups: ['T'], note: "{xAxisIndex 'none', yAxisIndex 0}: the auto orient takes the first dim with a target -> vertical",
    option: scatterChart([{ xAxisIndex: 'none', yAxisIndex: 0, start: 30, end: 70 }]) },
  { id: 'T10', groups: ['T'], note: 'legend-deselected series B on the zoomed y: the base comes from A only',
    option: { legend: { selected: { B: false } }, xAxis: { type: 'category', data: cat(20) }, yAxis: { type: 'value' },
      series: [{ name: 'A', type: 'line', data: V20 }, { name: 'B', type: 'line', data: V20.map(v => v * 10) }], dataZoom: [{ yAxisIndex: 0, start: 10, end: 90 }] } },
  { id: 'T11', groups: ['T'], note: "toolbox dataZoom feature {yAxisIndex: 'none'}: one internal 'select' dataZoom per x axis, appended; the user's slider hosts",
    option: Object.assign(catChart('line', [{ start: 20, end: 60 }]), { toolbox: { feature: { dataZoom: { yAxisIndex: 'none' } } } }) },
  { id: 'A1', groups: ['T', 'align'], note: 'yAxisIndex [0, 1], y1 alignTicks (aligned to y0), 20-80: y1 is reset last with y0\'s percentInverted, which WINS over its own start / end (zrender defaults keeps the target\'s keys)',
    option: { xAxis: { type: 'category', data: cat(20) }, yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true }],
      series: [{ type: 'line', data: V20 }, { type: 'line', yAxisIndex: 1, data: V20.map(v => v * 0.37 + 0.11) }], dataZoom: [{ yAxisIndex: [0, 1], start: 20, end: 80 }] } },
  { id: 'A2', groups: ['T', 'align'], note: 'the same in value mode (startValue 5, endValue 30): percentInverted fills start / end, but the value mode reads startValue / endValue in y1 space',
    option: { xAxis: { type: 'category', data: cat(20) }, yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true }],
      series: [{ type: 'line', data: V20 }, { type: 'line', yAxisIndex: 1, data: V20.map(v => v * 0.37 + 0.11) }], dataZoom: [{ yAxisIndex: [0, 1], startValue: 5, endValue: 30 }] } },
  // filtering
  { id: 'A3', groups: ['T', 'align'], note: 'yAxisIndex [0, 1] where y0 asks alignTicks (aligned to y1): y0 comes FIRST among the targets but is still reset after y1',
    option: { xAxis: { type: 'category', data: cat(20) }, yAxis: [{ type: 'value', alignTicks: true }, { type: 'value' }],
      series: [{ type: 'line', data: V20 }, { type: 'line', yAxisIndex: 1, data: V20.map(v => v * 0.37 + 0.11) }], dataZoom: [{ yAxisIndex: [0, 1], start: 20, end: 80 }] } },
  { id: 'F1', groups: ['F'], note: "filter on x 20-80 with '-' / null on the zoomed dim (kept) and on the other dim",
    option: scatterChart([{ start: 20, end: 80 }], [[0, 1], [10, 2], ['-', 3], [30, '-'], [null, 5], [50, 6], [60, null], [70, 8], [90, 9], [100, 10]]) },
  { id: 'F2', groups: ['F'], note: "weakFilter on a candlestick's y (4 dims) 30-70: rows straddling the window kept, rows fully outside and the all-NaN row removed",
    option: { xAxis: { type: 'category', data: cat(8) }, yAxis: { type: 'value', scale: true },
      series: [{ type: 'candlestick', data: [[10, 20, 5, 25], [40, 45, 38, 50], [2, 3, 1, 4], ['-', '-', '-', '-'], [5, 95, 1, 99], [80, 90, 75, 99], [60, 20, 10, 65], [30, '-', 25, 35]] }],
      dataZoom: [{ yAxisIndex: 0, start: 30, end: 70, filterMode: 'weakFilter' }] } },
  { id: 'F3', groups: ['F'], note: "'empty' on a line x 30-70: rows kept, x NaN'ed outside, the y axis NOT adapted",
    option: { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: XS }], dataZoom: [{ start: 30, end: 70, filterMode: 'empty' }] } },
  { id: 'F4', groups: ['F'], note: "'none': nothing filtered, no approximate extent, the axis still pinned",
    option: { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: XS }], dataZoom: [{ start: 30, end: 70, filterMode: 'none' }] } },
  { id: 'F4b', groups: ['F'], note: "'filter' on the same line (the orthogonal y adapts; compare F3 / F4)",
    option: { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: XS }], dataZoom: [{ start: 30, end: 70 }] } },
  { id: 'F5', groups: ['F'], note: 'two stacked lines zoomed on y 20-80: both the raw y and the stack-result dim are filtered (mapDimensionsAll), so the bottom series loses every row',
    option: { xAxis: { type: 'category', data: cat(5) }, yAxis: { type: 'value' },
      series: [{ type: 'line', stack: 'a', data: [1, 2, 3, 4, 5] }, { type: 'line', stack: 'a', data: [10, 20, 30, 40, 50] }], dataZoom: [{ yAxisIndex: 0, start: 20, end: 80 }] } },
  { id: 'F5b', groups: ['F'], note: 'two stacked bars of similar size zoomed on y 10-90 (filter)',
    option: { xAxis: { type: 'category', data: cat(6) }, yAxis: { type: 'value' },
      series: [{ type: 'bar', stack: 'a', data: [5, 12, 20, 7, 15, 3] }, { type: 'bar', stack: 'a', data: [6, 9, 4, 18, 11, 2] }], dataZoom: [{ yAxisIndex: 0, start: 10, end: 90 }] } },
  { id: 'F6', groups: ['F'], note: 'a y zoom on a category-x bar + line chart: rows filtered by y, the category x base stays 0..n-1',
    option: { xAxis: { type: 'category', data: cat(20) }, yAxis: { type: 'value' },
      series: [{ type: 'bar', data: V20 }, { type: 'line', data: V20.map(v => v + 20) }], dataZoom: [{ yAxisIndex: 0, start: 20, end: 80 }] } },
  // the gallery
  { id: 'G-line-function', groups: ['gallery'], note: 'line-function (gallery), verbatim: two inside value-mode dataZooms on x and y, filterMode none', gallery: 'line-function', omitOption: true },
  { id: 'G-area-simple', groups: ['gallery'], note: 'area-simple (gallery), verbatim: inside + slider 0-10 on 20000 rows, then lttb sampling (stage differs)', gallery: 'area-simple', omitOption: true },
  { id: 'G-grid-multiple', groups: ['gallery'], note: 'grid-multiple (gallery), verbatim: xAxisIndex [0, 1] over two grids, 30-70, toolbox selects', gallery: 'grid-multiple', omitOption: true },
  { id: 'G-mix-zoom-on-value', groups: ['gallery'], note: "mix-zoom-on-value (gallery), verbatim: x 94-100 then a y slider with filterMode 'empty'", gallery: 'mix-zoom-on-value', omitOption: true },
  { id: 'G-line-aqi', groups: ['gallery'], note: "line-aqi (gallery), verbatim: startValue '2014-06-01' parsed as a category", gallery: 'line-aqi', omitOption: true },
  { id: 'G-candlestick-brush', groups: ['gallery'], note: 'candlestick-brush (gallery), verbatim: inside + slider 98-100 over two grids', gallery: 'candlestick-brush', omitOption: true },
  { id: 'G-candlestick-sh-2015', groups: ['gallery'], note: 'candlestick-sh-2015 (gallery), verbatim: default full window, y scale', gallery: 'candlestick-sh-2015', omitOption: true },
  { id: 'G-dataset-encode1', groups: ['gallery'], note: "dataset-encode1 (gallery), verbatim: no user dataZoom; toolbox feature dataZoom {} -> 8 internal 'select' dataZooms host every axis",
    gallery: 'dataset-encode1', omitOption: true },
  { id: 'G-area-rainfall', groups: ['gallery'], note: 'area-rainfall (gallery), verbatim: slider + inside 65-85, y1 alignTicks (not zoomed)', gallery: 'area-rainfall', omitOption: true },
  { id: 'G-bar-gradient', groups: ['gallery'], note: 'bar-gradient (gallery), verbatim: one inside dataZoom, full window', gallery: 'bar-gradient' },
];

// ---------- the guards ----------
const GUARDS = [
  { id: 'no-shift', mutation: 'sliderMove clips each end instead of shifting the window (span kept)', mut: { noShift: true }, named: ['W10b', 'W10c', 'W10d', 'W12a'] },
  { id: 'no-round', mutation: 'the percent-derived value ends are not rounded', mut: { noRound: true }, named: ['W2', 'W3b', 'W4'] },
  { id: 'math-round', mutation: 'round with Math.round(x * 10^p) / 10^p instead of +toFixed(p)', mut: { mathRound: true }, named: ['W3n'] },
  { id: 'percent-for-axis', mutation: 'the percent window pins the axis, filters and sets the approximate extents instead of the value window', mut: { percentForAxis: true }, named: ['W2', 'W4', 'W6'] },
  { id: 'pin-ends', mutation: 'the 0% / 100% ends are pinned too (setZoomMM always)', mut: { pinEnds: true }, named: ['W1', 'W9a', 'W13b', 'G-bar-gradient'] },
  { id: 'filter-drops-nan', mutation: "'filter' drops NaN values on the zoomed dim", mut: { filterDropsNaN: true }, named: ['F1'] },
  { id: 'weak-keeps-allnan', mutation: "'weakFilter' keeps the all-NaN rows", mut: { weakKeepsAllNaN: true }, named: ['F2'] },
  { id: 'empty-adapts', mutation: "'empty' rows no longer count for the orthogonal axis base", mut: { emptyAdapts: true }, named: ['F3'] },
  { id: 'host-last', mutation: 'the LAST dataZoom targeting an axis hosts its proxy', mut: { hostLast: true }, named: ['T7'] },
  { id: 'auto-all-axes', mutation: 'the auto target takes every axis of the dim, ignoring the grid rule', mut: { autoAllAxes: true }, named: ['T2'] },
  { id: 'percent-always', mutation: "rangePropMode is always ['percent', 'percent']", mut: { percentAlways: true }, named: ['W9a', 'W9c', 'W10c', 'G-line-function', 'G-line-aqi'] },
  { id: 'no-include-zero', mutation: 'needIncludeZero ignored in the base', mut: { noIncludeZero: true }, named: ['W5'] },
  { id: 'no-asc', mutation: 'start > end not swapped (no asc on the windows)', mut: { noAsc: true }, named: ['W10a'] },
  { id: 'base-unfiltered', mutation: "a dataZoom's base ignores the rows earlier dataZooms filtered out", mut: { baseUnfiltered: true }, named: ['T6'] },
  { id: 'interleaved', mutation: 'one dataZoom resets and filters each axis in turn (x filtered before y is reset)', mut: { interleaved: true }, named: ['T5'] },
  { id: 'orient-last', mutation: 'the auto orient follows the LAST target dim', mut: { orientLast: true }, named: ['T5'] },
  { id: 'final-pxspan', mutation: 'the precision uses the final axis length instead of the raw grid rect', mut: { finalPxSpan: true }, named: ['W4c'] },
  { id: 'no-align', mutation: 'an axis with alignTicks is reset from its own start / end like any other', mut: { noAlign: true }, named: ['A1'] },
  { id: 'align-user-wins', mutation: "with alignTo, the dataZoom's own start / end win over the alignTo axis's percentInverted", mut: { alignUserWins: true }, named: ['A1'] },
  { id: 'no-log-sanitize', mutation: 'a value-mode end on a log axis is not sanitized (a non-positive startValue kept)', mut: { noLogSanitize: true }, named: ['W7b'] },
  { id: 'plain-add', mutation: 'sliderMove adds without addSafe (no getPrecision rounding of the sums)', mut: { plainAdd: true }, named: ['W15'] },
  { id: 'value-rounded', mutation: 'value-mode ends are rounded too', mut: { valueRounded: true }, named: ['W9e'] },
  { id: 'spans-ignored', mutation: 'minSpan / maxSpan / minValueSpan / maxValueSpan ignored', mut: { spansIgnored: true }, named: ['W12a', 'W12b', 'W12c'] },
];

// ---------- the run ----------
function generate() {
  hookProto();
  const cases = CASES.map(recordCase);
  return {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED,
    api: {
      dataZooms: "gm.findComponents({mainType: 'dataZoom'}); dz.subType, getOrient(), noTarget(), eachTargetAxis, getAxisProxy(dim, i).hostedBy(dz), getRangePropMode(), settledOption, get('filterMode')",
      window: 'dz.findRepresentativeAxisProxy().getWindow() / .getMinMaxSpan()',
      pxSpan: 'Math.abs(axis.getExtent()[1] - axis.getExtent()[0]) read in a wrapped AxisProxy.prototype.calculateDataWindow; pxSpanFinal the same after setOption',
      axes: 'axis.scale.rawExtentInfo._i: dataMM, noZoomEffMM, zoomMM, fixMM, zoomFixMM; scale.getExtent(); scale.getConfig().interval (log: scale.intervalStub.getConfig()); scale.getTicks()[k].value',
      series: 'eachRawSeries; isSeriesFiltered; getData() / getRawData(); data.mapDimensionsAll(x|y); getCalculationInfo(stackedDimension | stackResultDimension); data.getRawIndex(i); data._approximateExtent; data.getStore().get(dimIndex, i)',
      stage: 'a wrapped DataZoomModel.prototype.setCalculatedRange: at its first call (the end of the dataZoom processor) every series getData() rows and _approximateExtent',
      layout: "line / scatter: data.getLayout('points') (Float32Array) or data.getItemLayout(i); bar: data.getItemLayout(i)",
    },
    notes: [
      'The dist build agrees with the src tree on every function transcribed here (upstream.md section 0-3: calculateDataWindow dist 80134, sliderMove 64686, the number utils 7657-7967, ScaleRawExtentInfo 35058-35262, DataZoomModel 79679-80000, dataZoomProcessor 80422-80510, the toolbox creator 82156).',
      "The toolbox's feature.dataZoom (even {}) injects one internal dataZoom of subtype 'select' per x axis and then per y axis ('none' / false / an index list narrow it), APPENDED after the user's dataZooms; filterMode = feature.filterMode || 'filter'. They host every axis no user dataZoom targets (G-dataset-encode1: 8 of them, full windows, rows outside the full base are none, but the approximate extents are set).",
      "mapDimensionsAll of a stacked series' value axis holds the raw value dim AND the stack-result dim, and 'filter' selects on each: with a window on the stacked sums the bottom series can lose every row (F5).",
      'A value axis that is zoomed takes its base (noZoom) at reset time from the rows earlier dataZooms left; the other axes are built by the coordinate-system update after ALL processors, i.e. after line sampling (area-simple: lttb) -- their base comes from the sampled rows.',
      "'empty' replaces the SeriesData by data.map (count unchanged) and sets the approximate extent on the new one; the orthogonal axis base still sees every row (F3 y base = F4's).",
      "alignTicks (A1): AxisProxy.reset does opt = defaults({start: a[0], end: a[1]}, settledOption); zrender's defaults(target, source) only copies source keys that are null in the TARGET, so the aligned-to axis's percentInverted wins over the dataZoom's own start / end (upstream.md 2.1 says the opposite). In value mode (A2) start / end are not read, so the own startValue / endValue apply.",
      'A zero-span window (W11b) is widened by the nice step even though both ends are zoom-pinned: the scale extent is not the window there.',
      'The option fed for W11a carries NaN; see the __nan convention in the header.',
    ],
    cases,
  };
}

// the self-checks; returns the guards
function check(out) {
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    const d = caseDiffs(c, {});
    must(!d.length, c.id + ': the transcription differs at ' + d.slice(0, 4).map(x => x.field + ' (' + x.upstream + ' vs ' + x.mutated + ')').join('; '));
    // a pinned end is the scale extent end after the update
    for (const a of c.axes) {
      // a zero-span window is widened by the nice step (intervalScaleEnsureValidExtent), pinned or not (W11b)
      if (a.zoomMM[0] != null && a.zoomMM[0] === a.zoomMM[1]) continue;
      for (let k = 0; k < 2; k++) {
        if (a.zoomMM[k] == null || Number.isNaN(num(a.zoomMM[k]))) continue;
        must(a.extent[k] === a.zoomMM[k], c.id + ' ' + a.dim + a.index + ': the pinned end ' + a.zoomMMText[k] + ' is not the extent end ' + a.extentText[k]);
        must(a.zoomFixMM[k] && a.fixMM[k], c.id + ' ' + a.dim + a.index + ': a pinned end not zoom-fixed');
      }
    }
  }
  // upstream.md anchors
  const win = (id, k) => byId[id].dataZooms[k || 0].window;
  const eqT = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const ax = (id, key) => byId[id].axes.find(a => a.dim + a.index === key);
  must(eqT(win('W2').valueText, ['5', '14']) && eqT(win('W2').percentInvertedText, ['26.31578947368421', '73.68421052631578']), 'W2 anchor ' + win('W2').valueText);
  must(eqT(win('W3').valueText, ['3', '18']), 'W3 anchor ' + win('W3').valueText);
  must(eqT(win('W4').valueText, ['33.33', '66.67']) && eqT(win('W4').percentText, ['33.333', '66.667']) && win('W4').valuePrecisionText === '2', 'W4 anchor');
  must(eqT(ax('W5', 'x0').noZoomText, ['0', '1100']) && win('W5').valueText[0] === '220', 'W5 anchor');
  must(eqT(win('W6').valueText, ['24', '156']), 'W6 anchor ' + win('W6').valueText);
  must(eqT(ax('W7', 'x0').noZoomText, ['1', '1000']) && win('W7').valueText[0] === '131', 'W7 anchor ' + win('W7').valueText);
  must(eqT(win('W16').valueText, ['3', '7']), 'W16 anchor ' + win('W16').valueText);
  must(eqT(byId.A1.axes.find(a => a.dim + a.index === 'y1').zoomMMText, ['6.68', '26.77']), 'A1 anchor');
  must(eqT(byId.W9a.dataZooms[0].rangePropMode, ['value', 'percent']), 'W9a anchor');
  must(eqT(win('W9b').valueText, ['10', '90']) && eqT(win('W9c').valueText, ['50', '60']), 'W9b/c anchor');
  must(eqT(win('W10a').valueText, ['20', '80']) && eqT(win('W10b').valueText, ['0', '60']) && eqT(win('W10c').valueText, ['0', '60'])
    && eqT(win('W10d').valueText, ['30', '100']) && eqT(win('W10e').valueText, ['0', '100']), 'W10 anchors');
  must(eqT(win('W12a').valueText, ['40', '60']) && eqT(win('W12b').valueText, ['0', '30']), 'W12 anchors ' + win('W12a').valueText + ' ' + win('W12b').valueText);
  must(eqT(byId.T2.dataZooms[0].targets, [{ dim: 'x', axisIndex: 0 }]) && eqT(byId.T3.dataZooms[0].targets, [{ dim: 'x', axisIndex: 0 }]), 'T2/T3 anchor');
  must(byId.T4.dataZooms[0].orient === 'vertical' && byId.T5.dataZooms[0].orient === 'horizontal', 'T4/T5 orient anchor');
  const t5y = byId.T5.axes.find(a => a.dim === 'y');
  must(eqT(t5y.zoomMMText, ['6', '14']), 'T5 anchor ' + t5y.zoomMMText);
  must(eqT(win('T6', 1).valueText, ['3.8', '15.2']), 'T6 anchor ' + win('T6', 1).valueText);
  must(eqT(win('T7', 1).valueText, ['10', '50']) && byId.T7.dataZooms[1].hosts.length === 0, 'T7 anchor');
  must(byId.T9a.dataZooms[0].noTarget && byId.T9b.dataZooms[0].noTarget, 'T9 anchor');
  must(eqT(ax('F3', 'y0').noZoom, ax('F4', 'y0').noZoom) && !eqT(ax('F4b', 'y0').dataMM, ax('F4', 'y0').dataMM), 'F3/F4 anchor');
  must(byId.F5.series[0].count === 0, 'F5 anchor: the bottom stacked series keeps ' + byId.F5.series[0].count);
  must(byId['G-area-simple'].series[0].stage != null, 'area-simple: the sampling did not change the rows');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let d;
      try {
        d = caseDiffs(c, gd.mut);
      } catch (e) {
        d = [{ field: 'threw', upstream: null, mutated: String(e.message) }];
      }
      if (d.length) {
        changed.push(c.id);
        if (gd.named.includes(c.id)) differs.push({ case: c.id, fields: d.slice(0, 3) });
      }
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)), differs };
  });
}

// the compact writer of box-merge.js
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
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner))
    .join(',\n') + '\n' + ind + '}';
}
// the option of an omitOption case is kept for the check only, never written
function serialiseObject(out) {
  return Object.assign({}, out, {
    cases: out.cases.map(c => (CASES.find(d => d.id === c.id).omitOption ? Object.assign({}, c, { option: null }) : c)),
  });
}
const serialise = out => fmt(serialiseObject(out), '') + '\n';

let g1;
let json1;
let json2;
try {
  g1 = generate();
  g1.guards = check(g1);
  json1 = serialise(g1);
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(JSON.parse(JSON.stringify(serialiseObject(g1)))), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.guards = check(g2);
  json2 = serialise(g2);
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const out = g1;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const rows = out.cases.reduce((n, c) => n + c.series.reduce((m, s) => m + (s.rawIndices ? s.rawIndices.length : 0), 0), 0);
console.log(out.cases.length + ' cases (' + rows + ' kept rows); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
