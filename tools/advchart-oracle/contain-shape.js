// Upstream's own answers for containShape: a bar or pictorialBar series on a
// value, log or time base axis (or a category base axis with boundaryGap
// false) widens the axis' MAPPING extent by half a data-space band on each side,
// while ticks, onZero and clamping keep reading the EFFECTIVE extent.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, renders once to an SVG string, and
// reads the scale internals directly. Every case is 600x400 with
// grid.outerBoundsMode 'none' unless it says otherwise, so the grid rect is
// (90, 65, 450, 255).
//
// Per case:
//   W, H, option   the canvas and the option as run (animation false).
//   rawRect        getLayoutRect(grid.getBoxLayoutParams(), the canvas): the
//                  rect before outerBounds shrinks it. Its width (height) is the
//                  pixel span of an x (y) axis while the scale is niced, which
//                  is the px the data-space band w2 is computed with (pxInit).
//   rect           coordinateSystem.getRect(): the final rect (pxFinal).
//   transform      cartesian._transform, the affine fast path of dataToPoint
//                  [sx, 0, 0, sy, tx, ty], or null (a log or category axis).
//   axes           every axis of grid 0, x axes then y axes:
//     dim, index, type, inverse, onBand (category with boundaryGap truthy)
//     containShapeOption   model.get('containShape', true) as the option has
//                          it (null when absent)
//     ctnShp               scale.rawExtentInfo._i.ctnShp: whether the axis
//                          asks for the widening at all
//     aligned              alignTicks aligned this axis to another (upstream
//                          then never computes a mapping for it)
//     zoomFixMM            rawExtentInfo._i.zoomFixMM: a dataZoom end that is
//                          not at 0% / 100% pins that end of the mapping
//     zoomPercent, zoomValue   the dataZoom window over this axis (its axis
//                          proxy's getWindow(): percent and value), or null
//                          when no dataZoom targets it. Transcription inputs:
//                          self-check 7 derives zoomFixMM and the pinned
//                          effective ends from them
//     effective            scale.getExtent(): ticks, onZero and clamp read it
//     mapping              scale.getExtentUnsafe(MAPPING) or null: normalize,
//                          dataToCoord, the band span and the affine matrix read
//                          it when it is there
//     effectiveLin, mappingLin   (log only) the same two in the log space
//     px                   axis.getExtent(), the final local pixel extent
//     ticks, tickCoords    getTicksCoords(): the tick values and their GLOBAL
//                          pixel coordinates (toGlobalCoord of the coord)
//     onZeroOf             getAxesOnZeroOf() as 'x0', 'y1', ...
//     keys                 the axis' containShape keys in series order: 'bar',
//                          'pictorialBar' (cartesian2d), 'candlestick',
//                          'boxplot'; per key gap (liPosMinGap: a hex double,
//                          'SINGLE' or 'NONE'; null on a category axis, which
//                          keeps none) and w2 (the data-space band, or null)
//     supplement           [-w2/2, w2/2] unioned over the keys, or null
//     discouraged          the supplement exists, so an orthogonal axis whose
//                          axisLine.onZero is 'auto' does not sit on this one
//   series         per series in index order: type, filtered (legend-filtered:
//                  no layout, no items), baseDim, baseIndex, bandWidth, offset,
//                  size (data.getLayout; null for a series that has none), and
//                  for bar and pictorialBar one item per raw data index:
//     class        'drawn' (a graphic element, not ignored), 'hidden' (clipped
//                  away whole), 'none' (no element: NaN layout)
//     layout       data.getItemLayout: [x, y, width, height], unclipped, signed,
//                  or null when not all four are finite
//     box          the drawn shape after clipping, normalized: [l, t, r, b]
//     floor        (pictorialBar only) the layout's edge on the value axis
//   discriminating (G8) pxFinal would have predicted another mapping.
//   portStyleUlps  (G9 only) the most a box built the port's way today
//                  (a + n*(b-a) per axis) is off upstream's, in ulps.
//
// gap, w2, supplement and discouraged are not read from upstream: they are a
// transcription of axisStatisticsMetricsImpl.ts / axisBand.ts /
// scaleRawExtentInfo.ts, and they are valid because self-check 1 reproduces
// the mapping from them bit for bit.
//
// Self-checks (a case that fails any is recorded deferred with the reason):
//   1 mapping: liPosMinGap per key from the raw data of the series that are not
//     legend-filtered, w2 with px = rawRect's width (height), the supplement and
//     the mapping reproduce `mapping` (and `mappingLin`) bit for bit, or its
//     absence. Where rect differs from rawRect and pxFinal would predict
//     another mapping, the case counts as discriminating.
//   2 bandWidth: the layout band from rect's span, the mapping linear span and
//     the gap reproduces data.getLayout('bandWidth') bit for bit.
//   3 transform: the recipe from (rect.x, rect.y, rect.width, rect.height) and
//     the mapping ends reproduces cart._transform; every bar and pictorialBar
//     item's layout is reproduced bit for bit by the bar layout's arithmetic
//     over that dataToPoint (affine when the matrix exists, per axis
//     otherwise); px equals the extent built from rect.
//   4 ticks: every tick lies in the effective extent (on an onBand category
//     axis the ticks are the band edges, 0..count), getTicksCoords agrees with
//     scale.getTicks on a numeric axis, and every tick coordinate equals the
//     per-axis mapping of its tick (onBand category axes excepted).
//   5 onZero: getAxesOnZeroOf equals the rule over effective extents and
//     `discouraged`.
//   6 ctnShp: the flag equals the rule over the option and the series.
//   7 zoom: AxisProxy.reset sets zoomMM[i] = window value i for an end whose
//     percent is not exactly 0 (start) / 100 (end); makeFinal pins such an
//     end (effMM[i] = zoomMM[i], fixMM[i] = zoomFixMM[i] = true) and the nice
//     step leaves a pinned end alone. So zoomFixMM equals [percent0 !== 0,
//     percent1 !== 100] ([false, false] without a dataZoom) and every pinned
//     effective end equals its window value bit for bit. Self-check 1 feeds
//     this derived zoomFixMM (not the one read) to the mapping prediction,
//     which leaves a pinned end unwidened on a non-ordinal axis.
//
// A deferred case depends on something the port does not have (alignTicks on
// a base axis, candlestick widening); its upstream answer is recorded all the
// same.
// A documentary case (default outerBounds, pxInit != pxFinal) is compared on
// ctnShp, effective and mapping only: its final rect is the grid-bounds
// oracle's question. logTolerance marks the log cases, whose ends go through
// Math.pow and Math.log.
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside the case- and axis-level ones
// (rectText beside rect, ...), because the Pascal JSON reader misparses integer
// literals above 2^63. Item arrays carry hex only. The readable twin of -0 is
// '-0'.
//
//   node tools/advchart-oracle/contain-shape.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// The development build asserts its own invariants and throws where the
// production build carries on; a case that trips one is run through the
// production build instead, which is what a page actually ships, and says so.
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-contain-shape.json');

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
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const hexOrNull = v => (v == null ? null : hex(v));
const textOrNull = v => (v == null ? null : text(v));
const hexArr = a => (a ? a.map(hex) : null);
const textArr = a => (a ? a.map(text) : null);
const same = (a, b) => Object.is(a, b);
const sameArr = (a, b) => (a == null && b == null) || (a != null && b != null && a.length === b.length && a.every((v, i) => same(v, b[i])));
function ulps(a, b) {
  if (Object.is(a, b)) return 0;
  if (!Number.isFinite(a) || !Number.isFinite(b)) return Infinity;
  bits.setFloat64(0, a);
  const ia = bits.getBigInt64(0);
  bits.setFloat64(0, b);
  const ib = bits.getBigInt64(0);
  const oa = ia < 0n ? -(ia & 0x7fffffffffffffffn) : ia;
  const ob = ib < 0n ? -(ib & 0x7fffffffffffffffn) : ib;
  const d = oa - ob;
  return Number(d < 0n ? -d : d);
}
const RECT = ['x', 'y', 'width', 'height'];
const plainRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const finiteRect = r => r && RECT.every(k => typeof r[k] === 'number' && Number.isFinite(r[k]));
const sameRect = (a, b) => RECT.every(k => Object.is(a[k], b[k]));
const hexRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const textRect = r => ({ x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) });
const clone = o => JSON.parse(JSON.stringify(o));

// scale extent kinds and depth (scaleMapper.ts)
const EFFECTIVE = 0;
const MAPPING = 1;
const INNERMOST = 3;
// axisStatistics.ts LINEAR_POSITIVE_MIN_GAP_*
const SINGLE = -2;
const NONE = -1;
const FALLBACK_BAND_WIDTH_RATIO = 0.8; // axisBand.ts
const isFiniteNum = v => v != null && isFinite(v); // isNullableNumberFinite

// ---------- transcriptions ----------

// R0: the series types whose key has a containShape handler, and on which
// coordinate system (null: any) -- barGrid.ts, candlestick, boxplot.
const HANDLED = { bar: 'cartesian2d', pictorialBar: 'cartesian2d', candlestick: null, boxplot: null };

// The keys on an axis, in series order: a series joins a key on its BASE axis
// only. Legend-filtered series still join (they are associated before the
// legend filters them).
function keysOnAxis(ecModel, axis) {
  const keys = [];
  ecModel.eachRawSeries(s => {
    const cs = HANDLED[s.subType];
    if (cs === undefined) return;
    if (!s.coordinateSystem || (cs && s.coordinateSystem.type !== cs)) return;
    if (s.getBaseAxis() !== axis) return;
    let k = keys.find(e => e.key === s.subType);
    if (!k) keys.push(k = { key: s.subType, series: [] });
    k.series.push(s);
  });
  return keys;
}

// R0: scaleRawExtentInfo.ts determineRequireContainShape
function ctnShpRule(axis, keys) {
  let opt = axis.model.get('containShape', true);
  if (opt == null && !axis.onBand) opt = true;
  return !!opt && keys.length > 0;
}

// R2: axisStatisticsMetricsImpl.ts metricLiPosMinGapImpl, over the raw data
// of the key's series that are not legend-filtered.
function liPosMinGap(ecModel, axis, key) {
  const log = axis.scale.type === 'log';
  const base = log ? axis.scale.base : null;
  const vals = [];
  key.series.forEach(s => {
    if (ecModel.isSeriesFiltered(s)) return;
    const raw = s.getRawData();
    const dimIdx = raw.getDimensionIndex(raw.mapDimension(axis.dim));
    if (!(dimIdx >= 0)) return;
    const store = raw.getStore();
    for (let i = 0, n = store.count(); i < n; i++) {
      let v = store.get(dimIdx, i);
      if (isFinite(v) && (!log || v > 0)) {
        if (log) v = Math.log(v) / Math.log(base);
        vals.push(v);
      }
    }
  });
  vals.sort((a, b) => a - b);
  let min = Infinity;
  for (let j = 1; j < vals.length; j++) {
    const d = vals[j] - vals[j - 1];
    if (d > 0 && d < min) min = d;
  }
  return isFiniteNum(min) ? min : vals.length > 0 ? SINGLE : NONE;
}

// axisBand.ts calcBandWidth with one key's statistic (or none, on a category
// axis): { w, w2 }, before the layout's min of 1.
function bandOf(axis, gap, linSpan, pxSpan) {
  const out = { w: NaN, w2: NaN };
  if (!isFiniteNum(linSpan)) linSpan = NaN;
  if (axis.scale.type === 'ordinal') {
    let len = linSpan + (axis.onBand ? 1 : 0);
    if (len === 0) len = 1;
    out.w = pxSpan / len;
    if (!axis.onBand && linSpan && pxSpan) out.w2 = out.w * linSpan / pxSpan;
    return out;
  }
  let bw = -Infinity;
  let onlySingular = false;
  if (gap != null) {
    if (gap > 0) {
      bw = gap;
      onlySingular = false;
    } else if (gap === SINGLE) {
      onlySingular = true;
    }
  }
  if (isFiniteNum(linSpan) && linSpan > 0 && isFiniteNum(bw)) {
    out.w = pxSpan / linSpan * bw;
    out.w2 = bw;
  } else if (onlySingular) {
    out.w = pxSpan * FALLBACK_BAND_WIDTH_RATIO;
    out.w2 = out.w * linSpan / pxSpan;
  }
  return out;
}

// R-zoom: AxisProxy.ts reset (setZoomMM only off 0% / 100%) and
// scaleRawExtentInfo.ts makeFinal (a set zoomMM end pins effMM and zoomFixMM).
// win: { percent, value } or null. Returns { zoomMM, zoomFixMM }.
function zoomRule(win) {
  const zoomMM = [null, null];
  if (win) {
    if (win.percent[0] !== 0) zoomMM[0] = win.value[0];
    if (win.percent[1] !== 100) zoomMM[1] = win.value[1];
  }
  return { zoomMM, zoomFixMM: zoomMM.map(v => v != null) };
}

// The dataZoom window over an axis: the first dataZoom whose targets include
// it (the axis has one proxy, whichever dataZoom hosts it).
function zoomWindowOf(ecModel, axis) {
  let win = null;
  ecModel.eachComponent('dataZoom', dz => {
    if (win) return;
    const proxy = dz.getAxisProxy(axis.dim, axis.model.componentIndex);
    if (proxy) {
      const w = proxy.getWindow();
      win = { percent: w.percent.slice(), value: w.value.slice() };
    }
  });
  return win;
}

const linOf = (scale, v) => (scale.type === 'log' ? Math.log(v) / Math.log(scale.base) : v);

// R3-R5: the supplement and the mapping extent predicted for pixel span px.
// eff/effLin: the effective extent (pow ends and log ends on a log axis).
function predictMapping(axis, keys, eff, effLin, zoomFixMM, px) {
  const scale = axis.scale;
  const linSpan = effLin[1] - effLin[0];
  let sup = null;
  const perKey = keys.map(k => {
    const w2 = bandOf(axis, k.gap, linSpan, px).w2;
    if (isFiniteNum(w2)) {
      sup = sup || [0, 0];
      if (-w2 / 2 < sup[0]) sup[0] = -w2 / 2;
      if (w2 / 2 > sup[1]) sup[1] = w2 / 2;
    }
    return isFiniteNum(w2) ? w2 : null;
  });
  if (!sup) return { perKey, sup, mapping: null, mappingLin: null };
  let mapping = null;
  if (scale.type === 'ordinal') {
    if (!axis.onBand) mapping = [Math.min(eff[0], eff[0] + sup[0]), Math.max(eff[1], eff[1] + sup[1])];
  } else {
    const log = scale.type === 'log';
    const tin = v => linOf(scale, v);
    // LogScale transformOut: the lookup returns the effective pow ends verbatim
    const tout = v => (!log ? v : v === effLin[0] ? eff[0] : v === effLin[1] ? eff[1] : Math.pow(scale.base, v));
    const e = eff.slice();
    if (!zoomFixMM[0]) e[0] = Math.min(e[0], tout(tin(e[0]) + sup[0]));
    if (!zoomFixMM[1]) e[1] = Math.max(e[1], tout(tin(e[1]) + sup[1]));
    if (e[0] < eff[0] || e[1] > eff[1]) mapping = e;
  }
  const mappingLin = mapping && scale.type === 'log' ? mapping.map(v => linOf(scale, v)) : null;
  return { perKey, sup, mapping, mappingLin };
}

// The per-axis path: Axis.dataToCoord (normalize over the mapping, else the
// effective extent; linearMap onto the extent with bands) and the grid's
// toGlobalCoord. `ext` is the axis' local pixel extent, `gxy` the rect's x or y.
function linearMap(val, r0, r1) {
  // number.ts linearMap over the domain [0, 1], no clamp
  if (val === 0) return r0;
  if (val === 1) return r1;
  return (val - 0) / 1 * (r1 - r0) + r0;
}
function normalizeOf(a, v) {
  const lin = a.type === 'log' ? Math.log(v) / Math.log(a.base) : v;
  const m = a.type === 'log' ? (a.mappingLin || a.effectiveLin) : (a.mapping || a.effective);
  if (m[1] === m[0]) return 0.5;
  return (lin - m[0]) / (m[1] - m[0]);
}
function perAxisGlobal(a, v) {
  const ext = a.pxBuilt.slice();
  if (a.onBand) {
    const margin = (ext[1] - ext[0]) / a.count / 2;
    ext[0] += margin;
    ext[1] -= margin;
  }
  const c = linearMap(normalizeOf(a, v), ext[0], ext[1]);
  return a.dim === 'x' ? c + a.gxy : (a.pxBuilt[0] + a.pxBuilt[1]) - c + a.gxy;
}

// R8: Cartesian2D.calcAffineTransform
function affineOf(ax, ay) {
  const affinable = a => (a.type === 'value' || a.type === 'time') && a.scaleType !== 'ordinal';
  if (!affinable(ax) || !affinable(ay)) return null;
  const xm = ax.mapping || ax.effective;
  const ym = ay.mapping || ay.effective;
  const start = [perAxisGlobal(ax, xm[0]), perAxisGlobal(ay, ym[0])];
  const end = [perAxisGlobal(ax, xm[1]), perAxisGlobal(ay, ym[1])];
  const xs = xm[1] - xm[0];
  const ys = ym[1] - ym[0];
  if (!xs || !ys) return null;
  const sx = (end[0] - start[0]) / xs;
  const sy = (end[1] - start[1]) / ys;
  return [sx, 0, 0, sy, start[0] - xm[0] * sx, start[1] - ym[0] * sy];
}
function dataToPoint(m, ax, ay, xv, yv) {
  if (m && xv != null && isFinite(xv) && yv != null && isFinite(yv)) {
    return [m[0] * xv + m[2] * yv + m[4], m[1] * xv + m[3] * yv + m[5]];
  }
  return [perAxisGlobal(ax, xv), perAxisGlobal(ay, yv)];
}

// R9: Grid.ts fixAxisOnZero / canOnZeroToAxis
function onZeroRule(axesMap, recs) {
  const records = {};
  const out = {};
  const can = (opt, other) => {
    if (!other) return false;
    const r = recs.get(other);
    const e = r.effective;
    const valid = isFiniteNum(e[0]) && isFiniteNum(e[1]) && e[0] <= e[1];
    const inside = valid && (e[0] === 0 || e[1] === 0 || (e[0] < 0 && e[1] > 0));
    let ok = other.type !== 'category' && other.type !== 'time' && inside;
    if (ok && opt === 'auto' && r.discouraged) ok = false;
    return ok;
  };
  const fix = (axis, otherDim) => {
    const others = axesMap[otherDim];
    const opt = axis.model.get(['axisLine', 'onZero']);
    const idx = axis.model.get(['axisLine', 'onZeroAxisIndex']);
    let found = null;
    if (opt) {
      if (idx != null) {
        if (can(opt, others[idx])) found = others[idx];
      } else {
        for (const k of Object.keys(others)) {
          if (can(opt, others[k]) && !records[others[k].dim + '_' + others[k].index]) {
            found = others[k];
            break;
          }
        }
      }
    }
    if (found) records[found.dim + '_' + found.index] = true;
    out[axis.dim + axis.model.componentIndex] = found ? [found.dim + found.model.componentIndex] : [];
  };
  Object.keys(axesMap.x).forEach(k => fix(axesMap.x[k], 'y'));
  Object.keys(axesMap.y).forEach(k => fix(axesMap.y[k], 'x'));
  return out;
}

function boxOf(s) {
  return [
    s.width < 0 ? s.x + s.width : s.x,
    s.height < 0 ? s.y + s.height : s.y,
    s.width < 0 ? s.x : s.x + s.width,
    s.height < 0 ? s.y : s.y + s.height,
  ];
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
    const gm = ecModel.getComponent('grid', 0);
    const cs = gm.coordinateSystem;
    const carts = cs.getCartesians();
    const cart = carts[0];
    const rawRect = plainRect(lib.helper.getLayoutRect(gm.getBoxLayoutParams(), { width: c.W, height: c.H }));
    const rect = plainRect(cs.getRect());
    must(finiteRect(rawRect) && finiteRect(rect), c.name + ': a rect is not finite');
    const transform = cart._transform ? cart._transform.slice() : null;
    const fails = [];
    const fail = (check, msg) => fails.push({ check, msg });

    // the axes, x then y, in index order
    const axesMap = { x: {}, y: {} };
    const axes = [];
    ['x', 'y'].forEach(dim => {
      cs.getAxes().filter(a => a.dim === dim).sort((a, b) => a.model.componentIndex - b.model.componentIndex).forEach(a => {
        axesMap[dim][a.model.componentIndex] = a;
        axes.push(a);
      });
    });
    const recs = new Map();
    axes.forEach(axis => {
      const scale = axis.scale;
      const info = scale.rawExtentInfo;
      must(info && info._i, c.name + ': ' + axis.dim + ': no rawExtentInfo._i');
      const r = {
        dim: axis.dim,
        index: axis.model.componentIndex,
        type: axis.type,
        scaleType: scale.type,
        inverse: !!axis.inverse,
        onBand: !!axis.onBand,
        base: scale.type === 'log' ? scale.base : null,
        count: scale.type === 'ordinal' ? scale.count() : null,
        containShapeOption: axis.model.get('containShape', true),
        ctnShp: !!info._i.ctnShp,
        aligned: !!axis.__alignTo,
        zoomFixMM: info._i.zoomFixMM.slice(),
        zoomWindow: zoomWindowOf(ecModel, axis),
        effective: scale.getExtent().slice(),
        mapping: (m => (m ? m.slice() : null))(scale.getExtentUnsafe(MAPPING, null)),
        px: axis.getExtent().slice(),
      };
      if (scale.type === 'log') {
        r.effectiveLin = scale.getExtentUnsafe(EFFECTIVE, INNERMOST).slice();
        r.mappingLin = (m => (m ? m.slice() : null))(scale.getExtentUnsafe(MAPPING, INNERMOST));
      }
      const tc = axis.getTicksCoords();
      r.ticks = tc.map(t => t.tickValue);
      r.tickCoords = tc.map(t => axis.toGlobalCoord(t.coord));
      r.onZeroOf = axis.getAxesOnZeroOf ? axis.getAxesOnZeroOf().map(o => o.dim + o.model.componentIndex) : [];
      // the pixel extent rebuilt from rect (Grid.ts updateAxisExtentTransByGridRect)
      const wh = axis.dim === 'x' ? rect.width : rect.height;
      r.pxBuilt = axis.inverse ? [wh, 0] : [0, wh];
      r.gxy = axis.dim === 'x' ? rect.x : rect.y;
      r.keys = keysOnAxis(ecModel, axis);
      r.keys.forEach(k => { k.gap = scale.type === 'ordinal' ? null : liPosMinGap(ecModel, axis, k); });
      recs.set(axis, r);
    });

    // check 6: ctnShp
    axes.forEach(axis => {
      const r = recs.get(axis);
      const want = ctnShpRule(axis, r.keys);
      if (want !== r.ctnShp) fail(6, r.dim + r.index + ': ctnShp is ' + r.ctnShp + ', the rule gives ' + want);
    });

    // check 7: zoomFixMM and the pinned ends from the dataZoom window
    axes.forEach(axis => {
      const r = recs.get(axis);
      const z = zoomRule(r.zoomWindow);
      r.zoomFixMMRule = z.zoomFixMM;
      if (z.zoomFixMM[0] !== r.zoomFixMM[0] || z.zoomFixMM[1] !== r.zoomFixMM[1]) {
        fail(7, r.dim + r.index + ': zoomFixMM ' + JSON.stringify(r.zoomFixMM) + ', the rule gives ' + JSON.stringify(z.zoomFixMM));
      }
      [0, 1].forEach(i => {
        if (z.zoomMM[i] != null && !same(z.zoomMM[i], r.effective[i])) {
          fail(7, r.dim + r.index + ': pinned end ' + i + ' is ' + r.effective[i] + ', the window gives ' + z.zoomMM[i]);
        }
      });
    });

    // check 1: the mapping from pxInit (and not from pxFinal where they differ)
    let discriminating = false;
    axes.forEach(axis => {
      const r = recs.get(axis);
      const effLin = r.scaleType === 'log' ? r.effectiveLin : r.effective;
      const pxInit = axis.dim === 'x' ? rawRect.width : rawRect.height;
      const pxFinal = axis.dim === 'x' ? rect.width : rect.height;
      let p = { perKey: r.keys.map(() => null), sup: null, mapping: null, mappingLin: null };
      // an aligned axis goes through scaleCalcAlign, which never adopts a mapping
      if (r.ctnShp && !r.aligned) p = predictMapping(axis, r.keys, r.effective, effLin, r.zoomFixMMRule, pxInit);
      r.keys.forEach((k, i) => { k.w2 = p.perKey[i]; });
      r.supplement = p.sup;
      r.discouraged = !!p.sup;
      if (!sameArr(p.mapping, r.mapping)) {
        fail(1, r.dim + r.index + ': mapping ' + JSON.stringify(textArr(r.mapping)) + ', predicted from pxInit '
          + pxInit + ': ' + JSON.stringify(textArr(p.mapping)));
      }
      if (r.scaleType === 'log' && !sameArr(p.mappingLin, r.mappingLin)) {
        fail(1, r.dim + r.index + ': mappingLin ' + JSON.stringify(textArr(r.mappingLin)) + ', predicted '
          + JSON.stringify(textArr(p.mappingLin)));
      }
      if (r.ctnShp && !r.aligned && pxInit !== pxFinal) {
        const q = predictMapping(axis, r.keys, r.effective, effLin, r.zoomFixMMRule, pxFinal);
        if (!sameArr(q.mapping, p.mapping)) {
          discriminating = true;
          if (sameArr(q.mapping, r.mapping)) fail(1, r.dim + r.index + ': pxFinal reproduces the mapping too');
        }
      }
    });

    // check 5: onZero
    const oz = onZeroRule(axesMap, recs);
    axes.forEach(axis => {
      const r = recs.get(axis);
      const want = oz[r.dim + r.index];
      if (JSON.stringify(want) !== JSON.stringify(r.onZeroOf)) {
        fail(5, r.dim + r.index + ': onZeroOf ' + JSON.stringify(r.onZeroOf) + ', the rule gives ' + JSON.stringify(want));
      }
    });

    // check 4: ticks
    axes.forEach(axis => {
      const r = recs.get(axis);
      if (!sameArr(r.px, r.pxBuilt)) fail(3, r.dim + r.index + ': px ' + JSON.stringify(r.px) + ' is not built from rect');
      if (r.ticks.length) {
        // an onBand axis has one tick more than categories: its ticks are the
        // band edges, the last one at count
        const hi = r.onBand ? r.effective[1] + 1 : r.effective[1];
        if (!(r.ticks[0] >= r.effective[0]) || !(r.ticks[r.ticks.length - 1] <= hi)) {
          fail(4, r.dim + r.index + ': ticks ' + JSON.stringify(r.ticks) + ' leave the effective extent');
        }
      }
      if (r.scaleType !== 'ordinal') {
        const all = axis.scale.getTicks().map(t => t.value);
        if (!sameArr(all, r.ticks)) fail(4, r.dim + r.index + ': getTicksCoords and scale.getTicks disagree');
      }
      if (!r.onBand) {
        r.ticks.forEach((t, i) => {
          const want = perAxisGlobal(r, t);
          if (!same(want, r.tickCoords[i])) {
            fail(4, r.dim + r.index + ': tick ' + t + ' at ' + r.tickCoords[i] + ', per axis ' + want);
          }
        });
      }
    });

    // check 3: the transform
    const ax = recs.get(cart.getAxis('x'));
    const ay = recs.get(cart.getAxis('y'));
    const affine = affineOf(ax, ay);
    if (!sameArr(affine, transform)) {
      fail(3, 'transform ' + JSON.stringify(textArr(transform)) + ', the recipe gives ' + JSON.stringify(textArr(affine)));
    }

    // the series
    const series = [];
    ecModel.eachRawSeries(s => {
      const data = s.getData();
      const filtered = ecModel.isSeriesFiltered(s);
      const baseAxis = s.getBaseAxis ? s.getBaseAxis() : null;
      const rec = {
        index: s.seriesIndex,
        type: s.subType,
        filtered,
        baseDim: baseAxis ? baseAxis.dim : null,
        baseIndex: baseAxis ? baseAxis.model.componentIndex : null,
      };
      const lay = k => { const v = filtered ? null : data.getLayout(k); return typeof v === 'number' ? v : null; };
      const bw = lay('bandWidth');
      const off = lay('offset');
      const size = lay('size');
      rec.bandWidth = hexOrNull(bw);
      rec.bandWidthText = textOrNull(bw);
      rec.offset = hexOrNull(off);
      rec.offsetText = textOrNull(off);
      rec.size = hexOrNull(size);
      rec.sizeText = textOrNull(size);
      rec.items = [];
      const isBar = s.subType === 'bar' || s.subType === 'pictorialBar';
      if (!isBar || filtered || s.coordinateSystem !== cart) {
        series.push(rec);
        return;
      }
      const b = recs.get(baseAxis);
      // check 2: the layout band
      if (bw != null) {
        const key = b.keys.find(k => k.key === s.subType);
        const span = b.scaleType === 'log' ? (b.mappingLin || b.effectiveLin) : (b.mapping || b.effective);
        let w = bandOf(baseAxis, key ? key.gap : null, span[1] - span[0], Math.abs(b.pxBuilt[1] - b.pxBuilt[0])).w;
        w = isFiniteNum(w) ? Math.max(1, w) : 1;
        if (!same(w, bw)) fail(2, 's' + s.seriesIndex + ': bandWidth ' + bw + ', R7 gives ' + w);
      }
      // check 3: every item's layout (barGrid.ts createProgressiveLayout)
      const valueAxis = cart.getOtherAxis(baseAxis);
      const v = recs.get(valueAxis);
      const valueH = valueAxis.isHorizontal();
      const store = data.getStore();
      const valueDim = data.mapDimension(valueAxis.dim);
      const valueDimIdx = data.getDimensionIndex(valueDim);
      const baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim));
      const stackResultDim = data.getCalculationInfo('stackResultDimension');
      const stacked = lib.helper.dataStack.isDimensionStacked(data, valueDim) && !!data.getCalculationInfo('stackedOnSeries');
      const stackedDimIdx = stackResultDim && data.getDimensionIndex(stackResultDim);
      const sv = valueAxis.scale.rawExtentInfo.makeRenderInfo().startValue;
      const valueAxisStart = perAxisGlobal(v, sv);
      const barMinHeight = s.get('barMinHeight') || 0;
      const count = s.getRawData().count();
      for (let rI = 0; rI < count; rI++) {
        const k = data.indexOfRawIndex(rI);
        const el = k >= 0 ? data.getItemGraphicEl(k) : null;
        const L = k >= 0 ? data.getItemLayout(k) : null;
        const item = { class: !el ? 'none' : el.ignore ? 'hidden' : 'drawn' };
        item.layout = L && finiteRect(L) ? RECT.map(q => hex(L[q])) : null;
        const host = !el ? null : s.subType === 'pictorialBar' ? el.__pictorialBarRect : el;
        must(!el || (host && host.shape && host.shape.width !== undefined), c.name + ' s' + s.seriesIndex + '[' + rI + ']: no rect shape');
        item.box = host && finiteRect(host.shape) ? boxOf(host.shape).map(hex) : null;
        if (s.subType === 'pictorialBar') {
          const f = L ? L[valueH ? 'x' : 'y'] : null;
          item.floor = typeof f === 'number' && Number.isFinite(f) ? hex(f) : null;
        }
        rec.items.push(item);
        if (!L || k < 0 || s.subType === 'pictorialBar' && !finiteRect(L)) continue;
        const value = store.get(stacked ? stackedDimIdx : valueDimIdx, k);
        const baseValue = store.get(baseDimIdx, k);
        let baseCoord = valueAxisStart;
        const stackStart = stacked ? +value - store.get(valueDimIdx, k) : undefined;
        let want;
        if (valueH) {
          const coord = dataToPoint(affine, ax, ay, value, baseValue);
          if (stacked) baseCoord = dataToPoint(affine, ax, ay, stackStart, baseValue)[0];
          let width = coord[0] - baseCoord;
          if (Math.abs(width) < barMinHeight) width = (width < 0 ? -1 : 1) * barMinHeight;
          want = { x: baseCoord, y: coord[1] + off, width, height: size };
        } else {
          const coord = dataToPoint(affine, ax, ay, baseValue, value);
          if (stacked) baseCoord = dataToPoint(affine, ax, ay, baseValue, stackStart)[1];
          let height = coord[1] - baseCoord;
          if (Math.abs(height) < barMinHeight) height = (height <= 0 ? -1 : 1) * barMinHeight;
          want = { x: coord[0] + off, y: baseCoord, width: size, height };
        }
        const bad = RECT.filter(q => !same(want[q], L[q]));
        if (bad.length) {
          fail(3, 's' + s.seriesIndex + '[' + rI + ']: layout ' + JSON.stringify(textRect(L)) + ', the recipe gives '
            + JSON.stringify(textRect(want)));
        }
      }
      // the port's per-axis arithmetic today (a + n*(b-a) between rect edges)
      if (c.portStyle) {
        let worst = 0;
        const edge = (a, lo, hi) => (a.inverse ? [hi, lo] : [lo, hi]);
        const [xa, xb] = edge(ax, rect.x, rect.x + rect.width);
        const [yb, ya] = edge(ay, rect.y, rect.y + rect.height);
        const port = (a, p0, p1, val) => { const m = a.mapping || a.effective; return p0 + ((val - m[0]) / (m[1] - m[0])) * (p1 - p0); };
        for (let k = 0; k < data.count(); k++) {
          const L = data.getItemLayout(k);
          const px = port(ax, xa, xb, store.get(baseDimIdx, k));
          const py = port(ay, ya, yb, store.get(valueDimIdx, k));
          const pb = port(ay, ya, yb, sv);
          const x0 = px + off;
          const x1 = px + off + size;
          const pBox = [Math.min(x0, x1), Math.min(py, pb), Math.max(x0, x1), Math.max(py, pb)];
          const uBox = boxOf(L);
          for (let i = 0; i < 4; i++) worst = Math.max(worst, ulps(pBox[i], uBox[i]));
        }
        rec.portStyleUlps = worst;
      }
      series.push(rec);
    });

    return { option: written, rawRect, rect, transform, axes: axes.map(a => recs.get(a)), series, fails, discriminating };
  } finally {
    chart.dispose();
  }
}

function runEither(c) {
  try {
    return run(c, echarts);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

// ---------- cases ----------

const cases = [];
// grid.outerBoundsMode 'none' unless the case brings its own grid behaviour
// (auto: true), so the rect is the layout-option rect and pxInit = pxFinal
function add(group, name, option, extra) {
  extra = extra || {};
  const o = clone(option);
  if (!extra.auto) o.grid = Object.assign({ outerBoundsMode: 'none' }, o.grid || {});
  cases.push(Object.assign({ name: group + ' ' + name, group, option: o, W: 600, H: 400 }, extra));
}
const VAL = e => Object.assign({ type: 'value' }, e || {});
const bar = (data, e) => Object.assign({ type: 'bar', data }, e || {});
const vv = (series, x, y, rest) => Object.assign({ xAxis: VAL(x), yAxis: VAL(y), series }, rest || {});
const A = [[1, 5], [2, -3], [4, 2]];
const Z = [[-2, 5], [1, 3], [3, 2]];
const DAY = 86400000;
const T0 = Date.UTC(2024, 0, 1);
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
const deferred = why => ({ deferred: why });

// G1: value base
add('G1', 'A [[1,5],[2,-3],[4,2]]', vv([bar(A)]));
add('G1', 'Z crossing zero [[-2,5],[1,3],[3,2]]', vv([bar(Z)]));
add('G1', 'K6 uneven gaps x=1,1.5,4,10', vv([bar([[1, 5], [1.5, 3], [4, 2], [10, 1]])]));
add('G1', 'scale:true x=3,4,6', vv([bar([[3, 5], [4, 2], [6, 3]])], { scale: true }));
add('G1', 'min 0 max 10 x=1,2,3 (the barlayout twin)', vv([bar([[1, 5], [2, 3], [3, 4]])], { min: 0, max: 10 }));
add('G1', 'min 1 max 4', vv([bar(A)], { min: 1, max: 4 }));
add('G1', 'min dataMin max dataMax', vv([bar(A)], { min: 'dataMin', max: 'dataMax' }));
add('G1', 'interval 1, gap .5', vv([bar([[0, 5], [0.5, 3], [3, 2]])], { interval: 1 }));
add('G1', 'splitNumber 2', vv([bar(A)], { splitNumber: 2 }));
add('G1', 'inverse', vv([bar(A)], { inverse: true }));
add('G1', "base values null, '-', '2.5'", vv([bar([[null, 5], ['-', 3], ['2.5', 1], [1, 2], [3, 4]])]));
add('G1', "value '-' at x=1", vv([bar([[1, '-'], [1.5, 3], [4, 2]])]));
add('G1', 'two series, union gap .5', vv([bar([[0, 5], [0.5, 3], [3, 2]]), bar([[1, 2], [2, 3]])]));
add('G1', 'duplicate x across series', vv([bar([[1, 5], [1, 3]]), bar([[1, 2], [4, 3]])]));
add('G1', 'stacked', vv([bar(A.map(p => [p[0], Math.abs(p[1])]), { stack: 't' }), bar([[1, 1], [2, 1], [4, 1]], { stack: 't' })]));
add('G1', 'legend-filtered series', vv([bar([[1, 5], [3, 3]], { name: 'a' }), bar([[1.5, 2]], { name: 'b' })], null, null,
  { legend: { selected: { b: false } } }));
add('G1', 'line plus bar on a shared base', vv([{ type: 'line', data: [[0.2, 1], [0.3, 2]] }, bar([[1, 5], [3, 3]])]));
add('G1', 'empty bar plus bar', vv([bar([]), bar(A)]));
add('G1', 'barWidth 20', vv([bar(A, { barWidth: 20 })]));
add('G1', 'barWidth 50%', vv([bar(A, { barWidth: '50%' })]));
add('G1', 'barWidth 150%', vv([bar(A, { barWidth: '150%' })]));
add('G1', 'barMaxWidth 10', vv([bar(A, { barMaxWidth: 10 })]));
add('G1', 'barMinWidth 30 over a band of 1', vv([bar([[0, 5], [0.01, 3], [100, 2]], { barMinWidth: 30 })]));
add('G1', 'barCategoryGap 0%', vv([bar(A, { barCategoryGap: '0%' })]));
add('G1', 'barGap 50%, two series', vv([bar(A), bar([[1, 2], [2, 1], [4, 1]], { barGap: '50%' })]));
add('G1', 'floor: min 0 max 100000', vv([bar([[1, 5], [2, 3], [3, 4]])], { min: 0, max: 100000 }));

// G2: degenerate
add('G2', 'single [[3,5]]', vv([bar([[3, 5]])]));
add('G2', 'single [[3,5]] scale', vv([bar([[3, 5]])], { scale: true }));
add('G2', 'single [[5,5]] scale', vv([bar([[5, 5]])], { scale: true }));
add('G2', 'all equal [[2,5],[2,3]]', vv([bar([[2, 5], [2, 3]])]));
add('G2', '[[5,5]] scale max 5', vv([bar([[5, 5]])], { scale: true, max: 5 }));
add('G2', 'all zero', vv([bar([[0, 5], [0, 3]])]));
add('G2', 'all zero min 0', vv([bar([[0, 5], [0, 3]])], { min: 0 }));
add('G2', 'all zero min 0 max 0', vv([bar([[0, 5]])], { min: 0, max: 0 }));
add('G2', 'line at 0 plus an empty bar', vv([{ type: 'line', data: [[0, 5]] }, bar([])]));
add('G2', 'line at 0 plus a legend-filtered bar', vv([{ type: 'line', name: 'a', data: [[0, 5]] }, bar([[0, 3], [2, 2]], { name: 'b' })],
  null, null, { legend: { selected: { b: false } } }));
add('G2', 'line at 0 alone', vv([{ type: 'line', data: [[0, 5]] }]));
add('G2', 'containShape false', vv([bar(Z)], { containShape: false }));
add('G2', 'containShape 0', vv([bar(Z)], { containShape: 0 }));
add('G2', 'containShape false, all zero', vv([bar([[0, 5]])], { containShape: false }));
add('G2', 'containShape true', vv([bar([[1, 5], [2, 3]])], { containShape: true }));

// G3: log (compared with a tolerance: Math.pow and Math.log)
const logT = { logTolerance: true };
add('G3', 'log 1,10,100', { xAxis: { type: 'log' }, yAxis: VAL(), series: [bar([[1, 5], [10, 3], [100, 2]])] }, logT);
add('G3', 'log 2,3,50', { xAxis: { type: 'log' }, yAxis: VAL(), series: [bar([[2, 5], [3, 3], [50, 2]])] }, logT);
add('G3', 'log single 10', { xAxis: { type: 'log' }, yAxis: VAL(), series: [bar([[10, 5]])] }, logT);
add('G3', 'log single 1', { xAxis: { type: 'log' }, yAxis: VAL(), series: [bar([[1, 5]])] }, logT);
add('G3', 'log with -1 and 0', { xAxis: { type: 'log' }, yAxis: VAL(), series: [bar([[-1, 5], [0, 3], [10, 2], [20, 1]])] }, logT);

// G4: time
add('G4', 'time gaps 1 d and 2 d', { xAxis: { type: 'time' }, yAxis: VAL(), series: [bar([[T0, 5], [T0 + DAY, 3], [T0 + 3 * DAY, 2]])] });
add('G4', 'time single', { xAxis: { type: 'time' }, yAxis: VAL(), series: [bar([[T0, 5]])] });
add('G4', 'time on y (bars lying down)', { yAxis: { type: 'time' }, xAxis: VAL(), series: [bar([[5, T0], [3, T0 + DAY], [2, T0 + 3 * DAY]])] });
add('G4', 'time stacked', { xAxis: { type: 'time' }, yAxis: VAL(), series: [
  bar([[T0, 5], [T0 + DAY, 3], [T0 + 3 * DAY, 2]], { stack: 't' }), bar([[T0, 1], [T0 + DAY, 2], [T0 + 3 * DAY, 1]], { stack: 't' })] });

// G5: category, boundaryGap false
const bgf = (n, x, grid) => ({ grid, xAxis: Object.assign({ type: 'category', boundaryGap: false, data: cats(n) }, x || {}), yAxis: VAL(),
  series: [bar(cats(n).map((_, i) => i + 1))] });
add('G5', 'boundaryGap false, 4 categories', bgf(4));
add('G5', 'boundaryGap false, 7 categories', bgf(7));
add('G5', 'boundaryGap false, 12 categories on 400 px', bgf(12, null, { left: 0, width: 400 }), { W: 800 });
add('G5', 'boundaryGap false, 12 categories on 403 px', bgf(12, null, { left: 0, width: 403 }), { W: 800 });
add('G5', 'boundaryGap false, 1 category', bgf(1));
add('G5', 'boundaryGap false, containShape false', bgf(4, { containShape: false }));
add('G5', 'boundaryGap true, containShape true', { xAxis: { type: 'category', containShape: true, data: cats(3) }, yAxis: VAL(),
  series: [bar([5, 3, 2])] });

// G6: pictorialBar
add('G6', 'pictorialBar alone x=1,2,4', vv([{ type: 'pictorialBar', symbol: 'rect', data: A }]));
add('G6', 'bar gap 1 plus pictorialBar gap 3', vv([bar([[1, 5], [2, 3]]), { type: 'pictorialBar', symbol: 'rect', data: [[1, 2], [4, 3]] }]));

// G7: onZero (bars crossing zero on x)
add('G7', 'y onZero absent', vv([bar(Z)]));
add('G7', "y onZero 'auto'", vv([bar(Z)], null, { axisLine: { onZero: 'auto' } }));
add('G7', 'y onZero true', vv([bar(Z)], null, { axisLine: { onZero: true } }));
add('G7', 'y onZero false', vv([bar(Z)], null, { axisLine: { onZero: false } }));
add('G7', 'y onZeroAxisIndex 0', vv([bar(Z)], null, { axisLine: { onZeroAxisIndex: 0 } }));
add('G7', 'scatter crossing zero', vv([{ type: 'scatter', data: Z }]));
add('G7', 'line crossing zero plus an empty bar', vv([{ type: 'line', data: [[-2, 5], [3, 2]] }, bar([])]));

// G8: default outerBounds, where pxInit may differ from pxFinal (PX2, PX3 and
// the twin; only PX3's two would predict different mappings, the run counts it
// as discriminating). effective, mapping and ctnShp
// depend on pxInit only and are compared; rect, band and boxes are the
// grid-bounds oracle's question.
const doc = note => ({ auto: true, documentary: true, note });
add('G8', 'PX single, wide y labels, 537x333', vv([bar([[1234.567, 123456789]])]), Object.assign({ W: 537, H: 333 },
  doc('outerBounds auto, though nothing shrinks here: rect is rawRect')));
add('G8', 'PX2 single, y labels 1e10, grid left 0, 611x377', vv([bar([[7.3, 12345678901]])], null, null, { grid: { left: 0 } }),
  Object.assign({ W: 611, H: 377 }, doc('outerBounds auto; pxInit and pxFinal agree on the mapping')));
add('G8', 'PX3 equal, y labels 1e9, scale, grid left 0, 583x377',
  vv([bar([[3.3, 1234567890], [3.3, 5]])], { scale: true }, null, { grid: { left: 0 } }),
  Object.assign({ W: 583, H: 377 }, doc('outerBounds auto; only pxInit reproduces the mapping')));
add('G8', 'grid-bounds twin: boundaryGap false, long labels, interval 1, grid left/right 0', {
  grid: { left: 0, right: 0 },
  xAxis: { type: 'category', boundaryGap: false, data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(d => d + ' long label text'),
    axisLabel: { interval: 1 } },
  yAxis: VAL(), series: [bar([120, 200, 150, 80, 70, 110, 130])],
}, doc('the grid-bounds fixture\'s case of the same name; mapping [-0.5, 6.5] from pxInit 600'));

// G9: value x value, where a box built the port's way (a + n*(b-a) per axis)
// is off upstream's affine path by 2 ulps or more
const G9 = { portStyle: true };
const PCT = { left: '11.3%', right: '7.7%', top: 33.3, bottom: '9.1%' };
add('G9', 'affine 463x462', vv([bar([[2.0999999999999996, 8.7], [3.3599999999999994, -6.46], [3.9799999999999995, 4.78], [4.51, 11.26],
  [5.779999999999999, 12.77], [7.1899999999999995, 5.39], [8.6, 16.05], [9.39, -3.95]])]), Object.assign({ W: 463, H: 462 }, G9));
add('G9', 'affine percent grid 775x279', vv([bar([[-0.3999999999999999, 3.08], [1.4300000000000002, 3.97], [2.4800000000000004, 1.89],
  [3.3700000000000006, 9.49], [4.300000000000001, 17.53]])], null, null, { grid: PCT }), Object.assign({ W: 775, H: 279 }, G9));
add('G9', 'affine 536x330', vv([bar([[0, 10.76], [1.73, 15.47], [3.58, 0.18], [5.09, -0.79], [6.9799999999999995, 9.15], [8.5, -7.1]])]),
  Object.assign({ W: 536, H: 330 }, G9));
const G9D = [[2.5999999999999996, 0.88], [3.55, 18.4], [4.25, 12.64]];
add('G9', 'affine percent grid, scale, 744x495', vv([bar(G9D)], { scale: true }, null, { grid: PCT }), Object.assign({ W: 744, H: 495 }, G9));
add('G9', 'affine percent grid 601x328', vv([bar([[1.6, 12.2], [2.6, 1.86], [3.09, 20.86], [4.68, 21.06], [6.08, -3.74], [7.3, 6.83],
  [9.09, 10.82], [9.16, -6.86]])], null, null, { grid: PCT }), Object.assign({ W: 601, H: 328 }, G9));
add('G9', 'affine scale 664x321', vv([bar([[2.7, 12.13], [2.89, 14.71], [4.73, -7.32], [5.3500000000000005, -5.46]])], { scale: true }),
  Object.assign({ W: 664, H: 321 }, G9));
add('G9', 'affine percent grid, both inverse, 505x452', vv([bar([[2.8, 4.85], [4.08, 14.75], [4.53, 20.03]])], { inverse: true },
  { inverse: true }, { grid: PCT }), Object.assign({ W: 505, H: 452 }, G9));
add('G9', 'affine percent grid, scale, both inverse, 744x495', vv([bar(G9D)], { scale: true, inverse: true }, { inverse: true },
  { grid: PCT }), Object.assign({ W: 744, H: 495 }, G9));

// G10: dataZoom. An end off 0% / 100% is pinned at the window value
// (zoomFixMM): the nice step and the containShape widening leave it alone,
// and bars past it are clipped; an end at 0% / 100% widens as usual.
const DZ = [[1, 5], [2, -3], [4, 2], [6, 1], [8, 3]];
const dz = (start, end) => ({ dataZoom: [{ type: 'inside', start, end }] });
add('G10', 'dataZoom inside 0-50', vv([bar(DZ)], null, null, dz(0, 50)));
add('G10', 'dataZoom inside 10-90', vv([bar(DZ)], null, null, dz(10, 90)));
add('G10', 'dataZoom inside 0-50, the smallest gap outside the window',
  vv([bar([[1, 5], [2, -3], [3.5, 2], [6, 1], [6.25, 3]])], null, null, dz(0, 50)),
  { note: 'the band is the smallest gap of the RAW data (0.25, between 6 and 6.25, both filtered out), not of the window (1)' });

// deferred: upstream's answer recorded, the port has no such thing yet
add('D', 'alignTicks on a base axis', {
  xAxis: [VAL(), VAL({ alignTicks: true })], yAxis: VAL(),
  series: [bar([[1, 5], [2, 3], [4, 2]]), bar([[3, 5], [5, 3], [9, 2]], { xAxisIndex: 1 })],
}, deferred('alignTicks: the aligned base axis x1 gets no mapping (scaleCalcAlign never adopts one); the port has no alignTicks'));
add('D', 'candlestick on a value base', vv([{ type: 'candlestick', data: [[1, 2, 3, 1, 4], [2, 3, 2, 1, 4], [4, 2, 3, 1, 5]] }]),
  deferred('candlestick widens its base axis too; the port\'s candlestick uses a fixed 8 px band and no containShape'));

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
let discriminatingCount = 0;

function axisOut(r) {
  const o = {
    dim: r.dim,
    index: r.index,
    type: r.type,
    inverse: r.inverse,
    onBand: r.onBand,
    containShapeOption: r.containShapeOption == null ? null : r.containShapeOption,
    ctnShp: r.ctnShp,
    aligned: r.aligned,
    zoomFixMM: r.zoomFixMM,
    zoomPercent: r.zoomWindow ? hexArr(r.zoomWindow.percent) : null,
    zoomPercentText: r.zoomWindow ? textArr(r.zoomWindow.percent) : null,
    zoomValue: r.zoomWindow ? hexArr(r.zoomWindow.value) : null,
    zoomValueText: r.zoomWindow ? textArr(r.zoomWindow.value) : null,
    effective: hexArr(r.effective),
    effectiveText: textArr(r.effective),
    mapping: hexArr(r.mapping),
    mappingText: textArr(r.mapping),
  };
  if (r.scaleType === 'log') {
    o.effectiveLin = hexArr(r.effectiveLin);
    o.effectiveLinText = textArr(r.effectiveLin);
    o.mappingLin = hexArr(r.mappingLin);
    o.mappingLinText = textArr(r.mappingLin);
  }
  o.px = hexArr(r.px);
  o.pxText = textArr(r.px);
  o.ticks = hexArr(r.ticks);
  o.ticksText = textArr(r.ticks);
  o.tickCoords = hexArr(r.tickCoords);
  o.tickCoordsText = textArr(r.tickCoords);
  o.onZeroOf = r.onZeroOf;
  o.keys = r.keys.map(k => ({
    key: k.key,
    gap: k.gap == null ? null : k.gap === SINGLE ? 'SINGLE' : k.gap === NONE ? 'NONE' : hex(k.gap),
    gapText: k.gap == null ? null : k.gap === SINGLE ? 'SINGLE' : k.gap === NONE ? 'NONE' : text(k.gap),
    w2: hexOrNull(k.w2),
    w2Text: textOrNull(k.w2),
  }));
  o.supplement = hexArr(r.supplement);
  o.supplementText = textArr(r.supplement);
  o.discouraged = r.discouraged;
  return o;
}

function recordOf(c) {
  const r = runEither(c);
  const rec = { name: c.name, group: c.group, W: c.W, H: c.H, option: r.option };
  const byCheck = {};
  r.fails.forEach(f => { (byCheck[f.check] = byCheck[f.check] || []).push(f.msg); });
  CHECKS.forEach(k => { tally[k][byCheck[k] ? 1 : 0]++; });
  if (r.discriminating) discriminatingCount++;
  const miss = Object.keys(byCheck).map(k => 'self-check ' + k + ': ' + byCheck[k].join('; ')).join(' | ');
  if (miss) failed.push(c.name + (c.deferred ? ' (deferred anyway)' : '') + ': ' + miss);
  if (c.deferred || miss) {
    rec.deferred = true;
    rec.why = c.deferred ? c.deferred + (miss ? '; and ' + miss : '') : miss;
  }
  if (c.documentary) rec.documentary = true;
  if (c.note) rec.note = c.note;
  if (c.logTolerance) rec.logTolerance = true;
  if (r.discriminating) rec.discriminating = true;
  if (r.productionBuild) rec.productionBuild = true;
  rec.rawRect = hexRect(r.rawRect);
  rec.rawRectText = textRect(r.rawRect);
  rec.rect = hexRect(r.rect);
  rec.rectText = textRect(r.rect);
  rec.transform = hexArr(r.transform);
  rec.transformText = textArr(r.transform);
  rec.axes = r.axes.map(axisOut);
  rec.series = r.series;
  if (c.portStyle) {
    const u = Math.max(...r.series.filter(s => s.portStyleUlps != null).map(s => s.portStyleUlps));
    must(u >= 2, c.name + ': the port-style box is only ' + u + ' ulps off; not a discriminator');
    rec.portStyleUlps = u;
    r.series.forEach(s => { delete s.portStyleUlps; });
  }
  return rec;
}

const out = { source: 'ECharts ' + echarts.version, cases: cases.map(recordOf) };

// A number JSON.stringify would write as an integer literal past 2^63 goes
// out in exponent form instead: marked in the replacer, unquoted afterwards.
const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks (pass/cases): ' + CHECKS.map(k => k + ' ' + tally[k][0] + '/' + (tally[k][0] + tally[k][1])).join(', ')
  + '; discriminating pxInit/pxFinal: ' + discriminatingCount);
fs.writeFileSync(OUT, json + '\n');
const d = out.cases.filter(c => c.deferred).length;
const items = out.cases.reduce((n, c) => n + c.series.reduce((m, s) => m + s.items.length, 0), 0);
console.log('wrote', OUT, (out.cases.length - d) + ' cases + ' + d + ' deferred, ' + items + ' items');
// unexpected failures (a case not deferred by design) fail the run
const unexpected = cases.filter(c => !c.deferred).filter(c => out.cases.find(o => o.name === c.name).deferred);
if (unexpected.length) {
  console.log('FAILED: ' + unexpected.length + ' case(s) did not pass the self-checks');
  process.exit(1);
}
process.exit(0);
