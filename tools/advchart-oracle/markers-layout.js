// Upstream's own answers for series MARKERS, batch M1: the model, the data
// transform and the pixel layout of markPoint / markLine / markArea (numbers
// only, nothing about the pictures). wf64/upstream.md is the prose,
// wf64/m1-oracle.md the corrections and additions this oracle found.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models and the views
// directly: the master marker component (ecModel.getComponent(kind)), the slave
// model of each series (MarkerModel.getMarkerModelFromSeries, reached as the
// static of the master's parent class), its data (markPoint: mpData =
// slave.getData(), layout = the symbol point; markLine: lineData =
// slave.getData(), fromData / toData = the makeInner record '__ec_inner_*' on
// the slave, layouts = the end points; markArea: areaData = slave.getData(),
// layout = {points, allClipped}), the item visuals, and the view's per-series
// group (view.markerGroupMap.get(series.id).group: silent, z, zlevel). Every
// chart is disposed in a finally.
//
// Which ORIGINAL data element a surviving marker came from is not visible in
// upstream's data (the transform clones the items), so every case runs twice:
// verbatim (every recorded number comes from this run) and once more with each
// data element tagged by an extra key '__oracleIndex' (both ends of a pair).
// The tag rides through clone / merge into the raw items; the tagged run must
// give exactly the same survivors (every field) as the verbatim one, and its
// tags give `index` / `survived`.
//
//   node tools/advchart-oracle/markers-layout.js
//
// writes tests/fixtures/advchart-markers-layout.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as line-smooth.js / datazoom-slider.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000, +Infinity 7ff0000000000000,
//            -Infinity fff0000000000000). Every hex field has a readable twin
//            (xText beside x; String(v), '-0' for negative zero).
//   val      a raw JS value of the option / transform world, tagged by kind:
//              null            undefined or null
//              {"n": hex, "t": text}   a number (NaN / +-Infinity included)
//              {"s": string}   a string (a category name, a numeric string,
//                              a date string ...), kept as the string
//              {"j": json}     anything else (boolean, array, object)
//   json     an option value exactly as upstream reads it (JSON; undefined ->
//            null): symbol, symbolSize, symbolRotate, symbolOffset,
//            symbolKeepAspect, precision, z, zlevel.
//   pt       [hex x, hex y] with ptText beside it.
//
// Top level
//   source, W, H, seed, api, notes[], cases[], guards[]
//   cases[]  one per chart:
//     id, note, width, height, gallery (file name or null), option (as fed;
//     null for a gallery case: load examples/advchart/gallery/<gallery>.json
//     and feed it verbatim), error (null, or the message setOption threw --
//     then `series` is empty), nan (true: NaN in a coord / value / point is
//     expected in this case and documented in its note)
//     grids[]  every grid in index order: index, rect {x,y,width,height} hex
//              + rectText (grid.coordinateSystem.getRect())
//     series[] every series whose OWN option has markPoint / markLine /
//              markArea with a `data` member (upstream builds a slave model
//              exactly then), series order:
//       seriesIndex, name (option name or null), type, filtered (legend-
//       unselected: no marker drawn, every kind block null), gridIndex,
//       baseAxisDim (seriesModel.getBaseAxis().dim), dataCount (data.count():
//       the view after dataZoom), color (getVisualFromData(seriesData,
//       'color'): the series style colour every marker falls back to, css or
//       null when it is not a string), stack (null, or {option: the series'
//       stack name or null, stackedDimension}: data.getCalculationInfo
//       ('stackedDimension') is set, so the value dim is stacked -- the
//       generated stackResultDimension name holds NULs and is not recorded),
//       coordDims (the data
//       dimension each coord dim maps to and its type: [{coordDim, dataDim,
//       type}]), bar (bar / pictorialBar only: {offset, size} hex + Text =
//       data.getLayout('offset' / 'size'), what getMarkerPosition adds;
//       else null)
//       axes[]   x then y of the series' grid: dim, type, inverse, onBand,
//                effective (scale.getExtent(): clamp / allClipped read it),
//                mapping (scale.getExtentUnsafe(MAPPING) or null: containData
//                reads it when present), px (axis.getExtent(): local pixel,
//                inverse applied), global ([toGlobalCoord(px[0]),
//                toGlobalCoord(px[1])]); extents hex + Text
//       markPoint / markLine / markArea   null when the series has none, else:
//         z, zlevel (json: retrieveZInfo = model.get('z') || 0 / zlevel),
//         silent (the drawn group's silent = marker.silent || series.silent),
//         count (the data count upstream built), and
//         markLine only: precision (json: mlModel.get('precision'))
//         items[]  one per ORIGINAL element of the series' marker data, in order:
//           index, survived (bool: kept by the transform + filter),
//           dataIndex (its index in upstream's marker data, or null) and when
//           it survived:
//           markPoint:
//             coord [val, val]  item.coord after dataTransform (the raw item)
//             values [val, val] mpData.get('x' / 'y'): the stored values the
//                               layout reads (parseDataValue by the coord
//                               dim's type: ordinal keeps the string)
//             value val, name val   the raw item's value / name after transform
//                               (an item placed by px holds NaN / null here,
//                               never read)
//             point pt          mpData.getItemLayout (the symbol position),
//                               pointText beside it
//             symbol, symbolSize, symbolRotate, symbolOffset, symbolKeepAspect
//                               json: mpData.getItemVisual (item -> series
//                               markPoint -> top-level markPoint -> default)
//           markLine:
//             from, to   each: coord, values, point, symbol, symbolSize,
//                        symbolRotate, symbolOffset, symbolKeepAspect (as the
//                        per-end visuals: from/toData.getItemVisual)
//             line       {type, value, name} of the merged line item (the raw
//                        lineData item: merge(line, from), merge(line, to))
//           markArea:
//             lt, rb [val, val]  the two corner coords after the transform and
//                        the +-Infinity fill (item.coord[0] / [1])
//             values [val x4]   areaData.get(x0, y0, x1, y1)
//             name val          the merged item's name
//             points [pt x4]    layout.points ([x0,y0],[x1,y0],[x1,y1],[x0,y1]),
//                               pointsText beside it
//             allClipped bool   layout.allClipped (true: no polygon, no label)
//
// guards[]  one per mutation of the transcription: id, mutation, named (the
//           cases that must turn red), changed (the cases whose recorded
//           values the mutated transcription does not reproduce), ok = named
//           is a subset of changed, differs (the first differing fields of
//           each named case)
//
// ---------------------------------------------------------------------------
// The transcription (checked against every recorded series, bit for bit) is
// markerHelper.ts (dataTransform, getAxisInfo, markerTypeCalculatorWithExtent,
// numCalculate incl. DataStore.getMedian's len = count() quirk and
// getDataExtent, dataFilter, zoneFilter + BoundingRect.intersect, the dim value
// getter + parseDataValue + the store's typed chunks), Series.indicesOfNearest,
// number.getPrecision / parsePercent, MarkPointView (createData,
// updateMarkerLayout, the visual reads), MarkLineView (markLineTransform with
// zrender clone / extend / merge, markLineFilter, updateSingleMarkerEndLayout,
// the per-end visual reads), MarkAreaView (markAreaTransform with mergeAll,
// markAreaFilter, getSingleMarkerEndPoint, allClipped), Cartesian2D.clampData,
// BaseBarSeries.getMarkerPosition (both branches), Model.get / getShallow
// chains (item -> series marker option -> top-level marker option merged
// with the marker defaults), retrieveZInfo. Its inputs are the option as fed
// and these upstream primitives, read while the chart is alive: the series
// data view (count, get), its dimension bookkeeping (mapDimension,
// getDimension, getDimensionInfo, the stack calculation info), the axes
// (dataToCoord, toGlobalCoord, getExtent, scale.parse / contain / getExtent,
// getTicksCoords, axisTick.alignWithLabel), coordSys.dataToPoint / getArea,
// the bar layout offset / size, the series colour, the legend filter.
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every recorded marker block (every field, bit for bit) and every
// error case throws in the transcription too; the tagged run keeps the same
// survivors as the verbatim run; tags increase; the z / zlevel of the drawn
// elements equal the recorded ones; NaN appears only in cases marked nan;
// anchors; every guard is ok; two generations in the process give the same
// bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-markers-layout.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;
const KINDS = ['markPoint', 'markLine', 'markArea'];
const TAG = '__oracleIndex';
const MAPPING = 1; // scaleMapper.ts SCALE_EXTENT_KIND_MAPPING

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
const RK = ['x', 'y', 'width', 'height'];
const rectRec = r => ({
  rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
  rectText: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) },
});
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const pairRec = (name, a) => ({ [name]: [hex(a[0]), hex(a[1])], [name + 'Text']: [text(a[0]), text(a[1])] });
const json = v => (v === undefined ? null : JSON.parse(JSON.stringify(v, (k, x) => (typeof x === 'number' && !isFinite(x) ? String(x) : x))));
function val(v) {
  if (v == null) return null;
  if (typeof v === 'number') return { n: hex(v), t: text(v) };
  if (typeof v === 'string') return { s: v };
  return { j: json(v) };
}
const pt = p => (p ? [hex(p[0]), hex(p[1])] : null);
const ptText = p => (p ? [text(p[0]), text(p[1])] : null);
const coordRec = c => [val(c ? c[0] : undefined), val(c ? c[1] : undefined)];

// ---------- zrender core/util.ts, verbatim in effect for plain JSON-born data ----------
const isArray = Array.isArray;
const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
function zrClone(source) {
  if (source == null || typeof source !== 'object') return source;
  if (isArray(source)) return source.map(zrClone);
  const r = {};
  for (const k in source) if (Object.prototype.hasOwnProperty.call(source, k) && k !== '__proto__') r[k] = zrClone(source[k]);
  return r;
}
function zrMerge(target, source, overwrite) {
  if (!isObject(source) || !isObject(target)) return overwrite ? zrClone(source) : target;
  for (const key in source) {
    if (Object.prototype.hasOwnProperty.call(source, key) && key !== '__proto__') {
      const t = target[key];
      const s = source[key];
      if (isObject(s) && isObject(t) && !isArray(s) && !isArray(t)) zrMerge(t, s, overwrite);
      else if (overwrite || !(key in target)) target[key] = zrClone(s);
    }
  }
  return target;
}
const zrExtend = (t, s) => {
  for (const k in s) if (Object.prototype.hasOwnProperty.call(s, k)) t[k] = s[k];
  return t;
};
const retrieve = (...a) => {
  for (const v of a) if (v != null) return v;
};
const retrieve2 = (a, b) => (a != null ? a : b);

// ---------- the transcription (with the mutations as switches) ----------

// the marker defaults (MarkPointModel.ts:72-94, MarkLineModel.ts:115-146,
// MarkAreaModel.ts:82-108; only what the layout and the visual reads touch)
const DEFAULTS = {
  markPoint: { z: 5, symbol: 'pin', symbolSize: 50 },
  markLine: { z: 5, symbol: ['circle', 'arrow'], symbolSize: [8, 16], symbolOffset: 0, precision: 2 },
  markArea: { z: 1 },
};
// Model.get(key[, ignoreParent]) / getShallow over [own, parent, grandparent...]
function chainGet(levels, key, ownOnly) {
  let v;
  for (let i = 0; i < levels.length; i++) {
    const o = levels[i];
    v = o && typeof o === 'object' ? o[key] : null;
    if (v != null || ownOnly) return v;
  }
  return v;
}

// number.ts getPrecision / getPrecisionSafe / parsePositionOption
function getPrecision(v) {
  v = +v;
  if (isNaN(v)) return 0;
  if (v > 1e-14) {
    let e = 1;
    for (let i = 0; i < 15; i++, e *= 10) if (Math.round(v * e) / e === v) return i;
  }
  const str = v.toString().toLowerCase();
  const eIndex = str.indexOf('e');
  const exp = eIndex > 0 ? +str.slice(eIndex + 1) : 0;
  const sigLen = eIndex > 0 ? eIndex : str.length;
  const dot = str.indexOf('.');
  return Math.max(0, (dot < 0 ? 0 : sigLen - 1 - dot) - exp);
}
function parsePercent(option, base) {
  switch (option) {
    case 'center': case 'middle': option = '50%'; break;
    case 'left': case 'top': option = '0%'; break;
    case 'right': case 'bottom': option = '100%'; break;
  }
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * base;
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}
const hasXOrY = item => !(isNaN(parseFloat(item.x)) && isNaN(parseFloat(item.y)));
const hasXAndY = item => !isNaN(parseFloat(item.x)) && !isNaN(parseFloat(item.y));
const isInfinity = v => !isNaN(v) && !isFinite(v);
const CALC = { min: 1, max: 1, average: 1, median: 1 };

// dataValueHelper.parseDataValue + the store chunk (DataStore dataCtors)
function parseDataValue(value, type) {
  if (type === 'ordinal') return value;
  if (type === 'time' && typeof value !== 'number' && value != null && value !== '-') value = +echarts.number.parseDate(value);
  return value == null || value === '' ? NaN : Number(value);
}
function store(v, type) {
  const t = type || 'float';
  if (t === 'float' || t === 'time') return new Float64Array([v])[0];
  if (t === 'int') return new Int32Array([v])[0];
  return v;
}

class Tx {
  constructor(ctx, input, mut) {
    this.c = ctx;
    this.mut = mut;
    this.input = input; // {seriesOpt, masters: {kind: option}}
  }
  // numCalculate (markerHelper.ts:252-275) with getMedian / getDataExtent
  numCalculate(dim, type) {
    const c = this.c;
    const vals = [];
    for (let i = 0; i < c.count; i++) vals.push(c.get(dim, i));
    if (type === 'average') {
      let sum = 0;
      let count = 0;
      for (const v of vals) if (!isNaN(v)) { sum += v; count++; }
      return sum / count;
    }
    if (type === 'median') {
      const arr = vals.filter(v => !isNaN(v)).sort((a, b) => a - b);
      const len = this.mut.medianNoQuirk ? arr.length : c.count;
      return len === 0 ? 0 : len % 2 === 1 ? arr[(len - 1) / 2] : (arr[len / 2] + arr[len / 2 - 1]) / 2;
    }
    let min = Infinity;
    let max = -Infinity;
    for (const v of vals) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return type === 'max' ? max : min;
  }
  // Series.indicesOfNearest (model/Series.ts:472-519), maxDistance Infinity
  nearest(axisDim, dim, value) {
    const c = this.c;
    const axis = c.axis(axisDim);
    const target = axis.dataToCoord(value);
    const out = [];
    let minDist = Infinity;
    let minDiff = -1;
    let n = 0;
    for (let i = 0; i < c.count; i++) {
      const diff = target - axis.dataToCoord(c.get(dim, i));
      const dist = Math.abs(diff);
      if (dist <= Infinity) {
        if (dist < minDist || (dist === minDist && diff >= 0 && minDiff < 0)) {
          minDist = dist;
          minDiff = diff;
          n = 0;
        }
        if (diff === minDiff) out[n++] = i;
      }
    }
    out.length = n;
    return out;
  }
  isStacked(dim) {
    return !!dim && dim === this.c.stackedDim;
  }
  // markerTypeCalculatorWithExtent (markerHelper.ts:54-90)
  calcWithExtent(type, axisDim, otherDataDim, targetDataDim, otherIdx, targetIdx) {
    const c = this.c;
    const mut = this.mut;
    const coord = [];
    const stacked = !mut.noStackResult && this.isStacked(targetDataDim);
    const calcDim = stacked ? c.stackResultDim : targetDataDim;
    const value = this.numCalculate(calcDim, type);
    const idxs = this.nearest(axisDim, calcDim, value);
    const dataIndex = mut.tieLast ? idxs[idxs.length - 1] : idxs[0];
    coord[otherIdx] = c.get(otherDataDim, dataIndex);
    coord[targetIdx] = mut.statValue ? value : c.get(calcDim, dataIndex);
    const retValue = c.get(targetDataDim, dataIndex);
    const precision = Math.min(getPrecision(c.get(targetDataDim, dataIndex)), 20);
    if (precision >= 0 && !mut.noCoordPrecision) coord[targetIdx] = +coord[targetIdx].toFixed(precision);
    return [coord, retValue];
  }
  // getAxisInfo (markerHelper.ts:176-199)
  axisInfo(item) {
    const c = this.c;
    const r = {};
    if (item.valueIndex != null || item.valueDim != null) {
      r.valueDataDim = item.valueIndex != null ? c.getDimension(item.valueIndex) : item.valueDim;
      r.valueAxisDim = c.coordDimOf(r.valueDataDim);
      r.baseAxisDim = c.otherDim(r.valueAxisDim);
      r.baseDataDim = c.mapDimension(r.baseAxisDim);
    } else {
      r.baseAxisDim = c.baseAxisDim;
      r.valueAxisDim = c.otherDim(r.baseAxisDim);
      r.baseDataDim = c.mapDimension(r.baseAxisDim);
      r.valueDataDim = c.mapDimension(r.valueAxisDim);
    }
    return r;
  }
  // dataTransform (markerHelper.ts:105-174)
  dataTransform(item) {
    if (!item) return undefined;
    const c = this.c;
    const dims = c.dims;
    if (!hasXAndY(item) && !isArray(item.coord)) {
      const ai = this.axisInfo(item);
      item = zrClone(item);
      if (item.type && CALC[item.type] && ai.baseAxisDim && ai.valueAxisDim) {
        const res = this.calcWithExtent(item.type, ai.valueAxisDim, ai.baseDataDim, ai.valueDataDim,
          dims.indexOf(ai.baseAxisDim), dims.indexOf(ai.valueAxisDim));
        item.coord = res[0];
        item.value = res[1];
      } else {
        item.coord = [item.xAxis != null ? item.xAxis : item.radiusAxis, item.yAxis != null ? item.yAxis : item.angleAxis];
      }
    }
    if (item.coord == null) {
      item.coord = [];
      if (item.type && CALC[item.type]) item.value = this.numCalculate(c.mapDimension(c.otherDim(c.baseAxisDim)), item.type);
    } else if (!this.mut.noCoordStat) {
      const coord = item.coord;
      for (let i = 0; i < 2; i++) if (CALC[coord[i]]) coord[i] = this.numCalculate(c.mapDimension(dims[i]), coord[i]);
    }
    return item;
  }
  containData(coord) {
    return this.c.axis('x').containData(coord[0]) && this.c.axis('y').containData(coord[1]);
  }
  // dataFilter (markerHelper.ts:210-220)
  dataFilter(item) {
    if (this.mut.noFilter) return true;
    return item.coord && !hasXOrY(item) ? this.containData(item.coord) : true;
  }
  // Cartesian2D.clampData (Cartesian2D.ts:154-172)
  clampData(data, out) {
    const xs = this.c.axis('x').scale;
    const ys = this.c.axis('y').scale;
    const xe = xs.getExtent();
    const ye = ys.getExtent();
    const x = xs.parse(data[0]);
    const y = ys.parse(data[1]);
    out = out || [];
    out[0] = Math.min(Math.max(Math.min(xe[0], xe[1]), x), Math.max(xe[0], xe[1]));
    out[1] = Math.min(Math.max(Math.min(ye[0], ye[1]), y), Math.max(ye[0], ye[1]));
    return out;
  }
  // BaseBarSeries.getMarkerPosition (BaseBarSeries.ts:97-191)
  markerPosition(value, dims, startingAtTick) {
    const c = this.c;
    const clamp = this.clampData(value);
    const p = c.dataToPoint(clamp);
    if (startingAtTick) {
      ['x', 'y'].forEach((d, idx) => {
        const axis = c.axis(d);
        if (axis.type !== 'category' || dims == null) return;
        const tickCoords = axis.getTicksCoords();
        const alignWithLabel = !this.mut.alignIgnored && axis.getTickModel().get('alignWithLabel');
        let targetTickId = clamp[idx];
        const isEnd = dims[idx] === 'x1' || dims[idx] === 'y1';
        if (isEnd && !alignWithLabel) targetTickId += 1;
        if (tickCoords.length < 2) return;
        if (tickCoords.length === 2) {
          p[idx] = axis.toGlobalCoord(axis.getExtent()[isEnd ? 1 : 0]);
          return;
        }
        let leftCoord;
        let coord;
        let step = 1;
        for (let i = 0; i < tickCoords.length; i++) {
          const tc = tickCoords[i].coord;
          const tv = i === tickCoords.length - 1 ? tickCoords[i - 1].tickValue + step : tickCoords[i].tickValue;
          if (tv === targetTickId) { coord = tc; break; }
          else if (tv < targetTickId) leftCoord = tc;
          else if (leftCoord != null && tv > targetTickId) { coord = (tc + leftCoord) / 2; break; }
          if (i === 1) step = tv - tickCoords[0].tickValue;
        }
        if (coord == null) {
          if (!leftCoord) coord = tickCoords[0].coord;
          else if (leftCoord) coord = tickCoords[tickCoords.length - 1].coord;
        }
        p[idx] = axis.toGlobalCoord(coord);
      });
    } else if (!this.mut.noBarOffset) {
      p[c.csBaseHorizontal ? 0 : 1] += c.barOffset + c.barSize / 2;
    }
    return p;
  }
  storedValues(coord, types) {
    return [0, 1].map(i => store(parseDataValue(coord && coord[i], types[i]), types[i]));
  }
  // the Infinity end / corner onto the axis extent (MarkLineView.ts:238-249, MarkAreaView.ts:206-218)
  infinityToExtent(point, x, y, xFirst, yFirst) {
    if (this.mut.noInfExtent) return;
    const xa = this.c.axis('x');
    const ya = this.c.axis('y');
    if (isInfinity(x)) point[0] = xa.toGlobalCoord(xa.getExtent()[xFirst ? 0 : 1]);
    else if (isInfinity(y)) point[1] = ya.toGlobalCoord(ya.getExtent()[yFirst ? 0 : 1]);
  }
  master(kind) {
    return this.input.masters[kind];
  }
  own(kind) {
    return this.input.seriesOpt[kind];
  }
  block(kind, z) {
    const levels = [this.own(kind), this.master(kind)];
    return {
      z: json(chainGet(levels, 'z') || 0), zlevel: json(chainGet(levels, 'zlevel') || 0),
      silent: !!(chainGet(levels, 'silent') || this.c.seriesSilent),
    };
  }

  // ----- markPoint (MarkPointView.ts:38-92, 114-178, 198-239) -----
  markPoint() {
    const c = this.c;
    const kind = 'markPoint';
    const opt = this.own(kind);
    const out = this.block(kind);
    const src = zrClone(opt.data);
    const items = src.map(it => this.dataTransform(it));
    const keep = items.map(it => this.dataFilter(it));
    const rows = [];
    items.forEach((it, i) => {
      const r = { index: i, survived: keep[i], dataIndex: null };
      if (keep[i]) {
        r.dataIndex = rows.length;
        rows.push(r);
        const lv = [it, opt, this.master(kind)];
        const values = this.storedValues(it.coord, c.dimTypes);
        const rel = chainGet(lv, 'relativeTo') === 'coordinate' && !this.mut.relIgnored;
        const area = c.area;
        const width = rel ? area.width : W;
        const height = rel ? area.height : H;
        const left = rel ? area.x : 0;
        const top = rel ? area.y : 0;
        const xPx = parsePercent(chainGet(lv, 'x'), width) + left;
        const yPx = parsePercent(chainGet(lv, 'y'), height) + top;
        let p;
        if (!isNaN(xPx) && !isNaN(yPx)) p = [xPx, yPx];
        else if (c.isBar) p = this.markerPosition(values);
        else p = c.dataToPoint([values[0], values[1]]);
        if (!isNaN(xPx)) p[0] = xPx;
        if (!isNaN(yPx)) p[1] = yPx;
        Object.assign(r, {
          coord: coordRec(it.coord), values: values.map(val), value: val(it.value), name: val(it.name), point: pt(p), pointText: ptText(p),
          symbol: json(chainGet(lv, 'symbol')), symbolSize: json(chainGet(lv, 'symbolSize')),
          symbolRotate: json(chainGet(lv, 'symbolRotate')), symbolOffset: json(chainGet(lv, 'symbolOffset')),
          symbolKeepAspect: json(chainGet(lv, 'symbolKeepAspect')),
        });
      }
      out.items = out.items || [];
      out.items.push(r);
    });
    out.count = rows.length;
    out.items = out.items || [];
    return out;
  }

  // ----- markLine (MarkLineView.ts:66-261, 296-433, 441-507) -----
  markLineTransform(item) {
    const c = this.c;
    const mut = this.mut;
    let arr;
    if (!isArray(item)) {
      const t = item.type;
      if (t === 'min' || t === 'max' || t === 'average' || t === 'median' || item.xAxis != null || item.yAxis != null) {
        let valueAxisDim;
        let value;
        if (item.yAxis != null || item.xAxis != null) {
          if (mut.xWins) {
            valueAxisDim = item.xAxis != null ? 'x' : 'y';
            value = retrieve(item.xAxis, item.yAxis);
          } else {
            valueAxisDim = item.yAxis != null ? 'y' : 'x';
            value = retrieve(item.yAxis, item.xAxis);
          }
        } else {
          const ai = this.axisInfo(item);
          valueAxisDim = ai.valueAxisDim;
          const dim = !mut.ml1dNotStacked && this.isStacked(ai.valueDataDim) ? c.stackResultDim : ai.valueDataDim;
          value = this.numCalculate(dim, t);
        }
        const valueIndex = valueAxisDim === 'x' ? 0 : 1;
        const baseIndex = 1 - valueIndex;
        const from = zrClone(item);
        const to = { coord: [] };
        from.type = null;
        from.coord = [];
        from.coord[baseIndex] = -Infinity;
        to.coord[baseIndex] = Infinity;
        const precision = chainGet([this.own('markLine'), this.master('markLine')], 'precision');
        if (!mut.noPrecision && precision >= 0 && typeof value === 'number') value = +value.toFixed(Math.min(precision, 20));
        from.coord[valueIndex] = to.coord[valueIndex] = value;
        arr = [from, to, { type: t, valueIndex: item.valueIndex, value }];
      } else {
        arr = [];
      }
    } else {
      arr = item;
    }
    const n = [this.dataTransform(arr[0]), this.dataTransform(arr[1]), zrExtend({}, arr[2])];
    n[2].type = n[2].type || null;
    if (mut.mergeReversed) {
      zrMerge(n[2], n[1]);
      zrMerge(n[2], n[0]);
    } else {
      zrMerge(n[2], n[0]);
      zrMerge(n[2], n[1]);
    }
    return n;
  }
  markLineFilter(item) {
    if (this.mut.noFilter) return true;
    const f = item[0].coord;
    const t = item[1].coord;
    const onlyDim = (d) => {
      const o = 1 - d;
      return isInfinity(f[o]) && isInfinity(t[o]) && f[d] === t[d] && this.c.axis(this.c.dims[d]).containData(f[d]);
    };
    if (f && t && (onlyDim(1) || onlyDim(0))) return true;
    return this.dataFilter(item[0]) && this.dataFilter(item[1]);
  }
  markLine() {
    const c = this.c;
    const kind = 'markLine';
    const opt = this.own(kind);
    const master = this.master(kind);
    const out = this.block(kind);
    out.precision = json(chainGet([opt, master], 'precision'));
    const src = zrClone(opt.data);
    const norm = src.map(it => this.markLineTransform(it));
    const keep = norm.map(n => this.markLineFilter(n));
    const pair = v => (isArray(v) ? v : [v, v]);
    const symbolType = pair(chainGet([opt, master], 'symbol'));
    const symbolSize = pair(chainGet([opt, master], 'symbolSize'));
    const symbolRotate = pair(chainGet([opt, master], 'symbolRotate'));
    const symbolOffset = pair(chainGet([opt, master], 'symbolOffset'));
    out.items = [];
    let count = 0;
    norm.forEach((n, i) => {
      const r = { index: i, survived: keep[i], dataIndex: null };
      out.items.push(r);
      if (!keep[i]) return;
      r.dataIndex = count++;
      const end = (it, isFrom) => {
        const lv = [it, opt, master];
        const values = this.storedValues(it.coord, c.dimTypes);
        const xPx = parsePercent(chainGet(lv, 'x'), W);
        const yPx = parsePercent(chainGet(lv, 'y'), H);
        let p;
        if (!isNaN(xPx) && !isNaN(yPx)) p = [xPx, yPx];
        else {
          p = c.isBar ? this.markerPosition(values) : c.dataToPoint([values[0], values[1]]);
          this.infinityToExtent(p, values[0], values[1], isFrom, isFrom);
          if (!isNaN(xPx)) p[0] = xPx;
          if (!isNaN(yPx)) p[1] = yPx;
        }
        const k = isFrom ? 0 : 1;
        return {
          coord: coordRec(it.coord), values: values.map(val), point: pt(p), pointText: ptText(p),
          symbol: json(retrieve2(chainGet(lv, 'symbol', true), symbolType[k])),
          symbolSize: json(retrieve2(chainGet(lv, 'symbolSize', this.mut.sizeOwnOnly), symbolSize[k])),
          symbolRotate: json(retrieve2(chainGet(lv, 'symbolRotate', true), symbolRotate[k])),
          symbolOffset: json(retrieve2(chainGet(lv, 'symbolOffset', true), symbolOffset[k])),
          symbolKeepAspect: json(chainGet(lv, 'symbolKeepAspect')),
        };
      };
      r.from = end(n[0], true);
      r.to = end(n[1], false);
      r.line = { type: val(n[2].type), value: val(n[2].value), name: val(n[2].name) };
    });
    out.count = count;
    return out;
  }

  // ----- markArea (MarkAreaView.ts:64-230, 259-321, 401-458) -----
  markAreaTransform(item) {
    if (!item[0] || !item[1]) return undefined;
    const lt = this.dataTransform(item[0]);
    const rb = this.dataTransform(item[1]);
    const lc = lt.coord;
    const rc = rb.coord;
    lc[0] = retrieve(lc[0], -Infinity);
    lc[1] = retrieve(lc[1], -Infinity);
    rc[0] = retrieve(rc[0], Infinity);
    rc[1] = retrieve(rc[1], Infinity);
    const res = [{}, lt, rb].reduce((a, b) => zrMerge(a, b));
    res.coord = [lt.coord, rb.coord];
    res.x0 = lt.x;
    res.y0 = lt.y;
    res.x1 = rb.x;
    res.y1 = rb.y;
    return res;
  }
  markAreaFilter(item) {
    if (this.mut.noFilter) return true;
    const f = item.coord[0];
    const t = item.coord[1];
    const i0 = { coord: f, x: item.x0, y: item.y0 };
    const i1 = { coord: t, x: item.x1, y: item.y1 };
    const only = d => isInfinity(f[1 - d]) && isInfinity(t[1 - d]);
    if (f && t && (only(1) || only(0))) return true;
    if (this.mut.zoneOff) return true;
    // zoneFilter + Cartesian2D.containZone + BoundingRect.intersect (touchThreshold 0)
    if (!(i0.coord && i1.coord && !hasXOrY(i0) && !hasXOrY(i1))) return true;
    const d1 = this.c.dataToPoint(i0.coord);
    const d2 = this.c.dataToPoint(i1.coord);
    const a = this.c.area;
    let bx = d1[0];
    let by = d1[1];
    let bw = d2[0] - d1[0];
    let bh = d2[1] - d1[1];
    if (bw < 0) { bx = bx + bw; bw = -bw; }
    if (bh < 0) { by = by + bh; bh = -bh; }
    const ax0 = a.x;
    const ax1 = a.x + a.width;
    const ay0 = a.y;
    const ay1 = a.y + a.height;
    const bx0 = bx;
    const bx1 = bx + bw;
    const by0 = by;
    const by1 = by + bh;
    if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return false;
    return !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
  }
  markArea() {
    const c = this.c;
    const kind = 'markArea';
    const opt = this.own(kind);
    const master = this.master(kind);
    const out = this.block(kind);
    const src = zrClone(opt.data);
    const merged = src.map(it => this.markAreaTransform(it));
    const keep = merged.map(m => this.markAreaFilter(m));
    const types = [c.dimTypes[0], c.dimTypes[1], c.dimTypes[0], c.dimTypes[1]];
    const DIMS = ['x0', 'y0', 'x1', 'y1'];
    const PERM = [['x0', 'y0'], ['x1', 'y0'], ['x1', 'y1'], ['x0', 'y1']];
    out.items = [];
    let count = 0;
    merged.forEach((m, i) => {
      const r = { index: i, survived: keep[i], dataIndex: null };
      out.items.push(r);
      if (!keep[i]) return;
      r.dataIndex = count++;
      const values = DIMS.map((d, k) => store(parseDataValue(m.coord[Math.floor(k / 2)][k % 2], types[k]), types[k]));
      const get = d => values[DIMS.indexOf(d)];
      const lv = [m, opt, master];
      const points = PERM.map(dims => {
        const xPx = parsePercent(chainGet(lv, dims[0]), W);
        const yPx = parsePercent(chainGet(lv, dims[1]), H);
        let p;
        if (!isNaN(xPx) && !isNaN(yPx)) return [xPx, yPx];
        if (c.isBar && !this.mut.noTickSnap) {
          const v0 = [get('x0'), get('y0')];
          const v1 = [get('x1'), get('y1')];
          const c0 = this.clampData(v0);
          const c1 = this.clampData(v1);
          const pv = [];
          pv[0] = dims[0] === 'x0' ? (c0[0] > c1[0] ? v1[0] : v0[0]) : (c0[0] > c1[0] ? v0[0] : v1[0]);
          pv[1] = dims[1] === 'y0' ? (c0[1] > c1[1] ? v1[1] : v0[1]) : (c0[1] > c1[1] ? v0[1] : v1[1]);
          p = this.markerPosition(pv, dims, true);
        } else {
          const q = [get(dims[0]), get(dims[1])];
          if (!this.mut.noClamp) this.clampData(q, q);
          p = c.dataToPoint(q, true);
        }
        this.infinityToExtent(p, get(dims[0]), get(dims[1]), dims[0] === 'x0', dims[1] === 'y0');
        if (!isNaN(xPx)) p[0] = xPx;
        if (!isNaN(yPx)) p[1] = yPx;
        return p;
      });
      const xs = c.axis('x').scale;
      const ys = c.axis('y').scale;
      const xe = xs.getExtent();
      const ye = ys.getExtent();
      const xp = [xs.parse(get('x0')), xs.parse(get('x1'))].sort((a, b) => a - b);
      const yp = [ys.parse(get('y0')), ys.parse(get('y1'))].sort((a, b) => a - b);
      const overlapped = !(xe[0] > xp[1] || xe[1] < xp[0] || ye[0] > yp[1] || ye[1] < yp[0]);
      Object.assign(r, {
        lt: coordRec(m.coord[0]), rb: coordRec(m.coord[1]), values: values.map(val), name: val(m.name),
        points: points.map(pt), pointsText: points.map(ptText), allClipped: this.mut.noAllClipped ? false : !overlapped,
      });
    });
    out.count = count;
    return out;
  }
}

// the transcription of one series: {markPoint, markLine, markArea} blocks
function transcribe(ctx, input, mut) {
  const o = {};
  for (const k of KINDS) {
    const own = input.seriesOpt[k];
    if (!own || !own.data) { o[k] = null; continue; }
    if (ctx.filtered) { o[k] = null; continue; }
    const tx = new Tx(ctx, input, mut);
    o[k] = tx[k]();
  }
  return o;
}

// flatten for the comparison
function flat(v, pre, out) {
  if (v === null || typeof v !== 'object') { out[pre] = JSON.stringify(v); return out; }
  if (isArray(v)) { out[pre + '#'] = String(v.length); v.forEach((x, i) => flat(x, pre + '[' + i + ']', out)); return out; }
  for (const k of Object.keys(v)) flat(v[k], pre + '.' + k, out);
  return out;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => a[k] !== b[k]).map(k => ({ field: k, upstream: a[k] === undefined ? null : a[k], mutated: b[k] === undefined ? null : b[k] }));
}

// ---------- reading upstream ----------
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const firstOf = v => (isArray(v) ? v[0] : v);
function masterInputs(option) {
  const m = {};
  for (const k of KINDS) m[k] = zrMerge(zrClone(firstOf(option[k]) || {}), DEFAULTS[k]);
  return m;
}
function markerMaster(ec, kind) {
  const m = ec.getComponent(kind);
  return m || null;
}
function slaveOf(ec, sm, kind) {
  const master = markerMaster(ec, kind);
  if (!master) return null;
  const MM = Object.getPrototypeOf(master.constructor);
  must(typeof MM.getMarkerModelFromSeries === 'function', 'MarkerModel.getMarkerModelFromSeries not reachable');
  return MM.getMarkerModelFromSeries(sm, kind) || null;
}
function innerFromTo(slave) {
  for (const k of Object.keys(slave)) {
    if (k.startsWith('__ec_inner_') && slave[k] && slave[k].from && slave[k].to) return slave[k];
  }
  return null;
}
function ctxOf(chart, sm) {
  const ec = chart.getModel();
  const data = sm.getData();
  const cs = sm.coordinateSystem;
  const dims = cs.dimensions;
  const isBar = typeof sm.getMarkerPosition === 'function';
  return {
    filtered: ec.isSeriesFiltered(sm),
    seriesSilent: sm.get('silent'),
    dims,
    count: data.count(),
    get: (dim, i) => data.get(dim, i),
    mapDimension: d => data.mapDimension(d),
    getDimension: i => data.getDimension(i),
    coordDimOf: d => { const info = data.getDimensionInfo(d); return info && info.coordDim; },
    stackedDim: data.getCalculationInfo('stackedDimension'),
    stackResultDim: data.getCalculationInfo('stackResultDimension'),
    baseAxisDim: sm.getBaseAxis().dim,
    otherDim: d => (d === 'x' ? 'y' : 'x'),
    axis: d => cs.getAxis(d),
    dataToPoint: (p, clamp) => cs.dataToPoint(p, clamp),
    area: cs.getArea(),
    isBar,
    barOffset: isBar ? data.getLayout('offset') : null,
    barSize: isBar ? data.getLayout('size') : null,
    csBaseHorizontal: cs.getBaseAxis().isHorizontal(),
    dimTypes: dims.map(d => (data.getDimensionInfo(data.mapDimension(d)) || {}).type),
  };
}

function axisRec(axis) {
  const scale = axis.scale;
  const eff = scale.getExtent();
  const mp = scale.getExtentUnsafe(MAPPING, null);
  const px = axis.getExtent();
  const gl = [axis.toGlobalCoord(px[0]), axis.toGlobalCoord(px[1])];
  return Object.assign({ dim: axis.dim, type: axis.type, inverse: !!axis.inverse, onBand: !!axis.onBand },
    pairRec('effective', eff), mp ? pairRec('mapping', mp) : { mapping: null, mappingText: null }, pairRec('px', px), pairRec('global', gl));
}

// the survivors of one kind, in upstream's data order (verbatim or tagged run)
function survivors(chart, sm, kind) {
  const ec = chart.getModel();
  const slave = slaveOf(ec, sm, kind);
  must(slave, 'no slave ' + kind + ' model for series ' + sm.seriesIndex);
  const data = slave.getData();
  must(data, 'no ' + kind + ' data for series ' + sm.seriesIndex);
  const view = chart.getViewOfComponentModel(markerMaster(ec, kind));
  const draw = view.markerGroupMap.get(sm.id);
  must(draw && draw.group, 'no ' + kind + ' group for series ' + sm.seriesIndex);
  const group = draw.group;
  const { z, zlevel } = { z: slave.get('z') || 0, zlevel: slave.get('zlevel') || 0 };
  // every displayable in the group carries the model's z / zlevel (traverseUpdateZ)
  group.traverse(el => {
    if (el.isGroup) return;
    must(el.z === z && el.zlevel === zlevel, kind + ' element z/zlevel ' + el.z + '/' + el.zlevel + ' vs ' + z + '/' + zlevel);
  });
  const block = { z: json(z), zlevel: json(zlevel), silent: !!group.silent };
  const rows = [];
  const tags = [];
  if (kind === 'markPoint') {
    for (let i = 0; i < data.count(); i++) {
      const raw = data.getRawDataItem(i);
      tags.push(raw[TAG]);
      const p = data.getItemLayout(i);
      rows.push({
        coord: coordRec(raw.coord), values: data.dimensions.map(d => val(data.get(d, i))), value: val(raw.value), name: val(raw.name),
        point: pt(p), pointText: ptText(p),
        symbol: json(data.getItemVisual(i, 'symbol')), symbolSize: json(data.getItemVisual(i, 'symbolSize')),
        symbolRotate: json(data.getItemVisual(i, 'symbolRotate')), symbolOffset: json(data.getItemVisual(i, 'symbolOffset')),
        symbolKeepAspect: json(data.getItemVisual(i, 'symbolKeepAspect')),
      });
    }
  } else if (kind === 'markLine') {
    block.precision = json(slave.get('precision'));
    const ft = innerFromTo(slave);
    must(ft, 'markLine from/to data not found');
    must(ft.from.count() === data.count() && ft.to.count() === data.count(), 'markLine data counts differ');
    const end = (d, i) => {
      const raw = d.getRawDataItem(i);
      const p = d.getItemLayout(i);
      return {
        coord: coordRec(raw.coord), values: d.dimensions.map(k => val(d.get(k, i))), point: pt(p), pointText: ptText(p),
        symbol: json(d.getItemVisual(i, 'symbol')), symbolSize: json(d.getItemVisual(i, 'symbolSize')),
        symbolRotate: json(d.getItemVisual(i, 'symbolRotate')), symbolOffset: json(d.getItemVisual(i, 'symbolOffset')),
        symbolKeepAspect: json(d.getItemVisual(i, 'symbolKeepAspect')),
      };
    };
    for (let i = 0; i < data.count(); i++) {
      const raw = data.getRawDataItem(i);
      tags.push(raw[TAG]);
      const lay = data.getItemLayout(i);
      const f = end(ft.from, i);
      const t = end(ft.to, i);
      must(lay && lay[0] === ft.from.getItemLayout(i) && lay[1] === ft.to.getItemLayout(i), 'markLine line layout is not [from, to]');
      rows.push({ from: f, to: t, line: { type: val(raw.type), value: val(raw.value), name: val(raw.name) } });
    }
  } else {
    for (let i = 0; i < data.count(); i++) {
      const raw = data.getRawDataItem(i);
      tags.push(raw[TAG]);
      const lay = data.getItemLayout(i);
      rows.push({
        lt: coordRec(raw.coord[0]), rb: coordRec(raw.coord[1]), values: ['x0', 'y0', 'x1', 'y1'].map(k => val(data.get(k, i))),
        name: val(raw.name), points: lay.points.map(pt), pointsText: lay.points.map(ptText), allClipped: !!lay.allClipped,
      });
      // a drawn polygon exactly when not allClipped, on the layout points
      const el = data.getItemGraphicEl(i);
      must(!!el === !lay.allClipped, 'markArea polygon presence vs allClipped');
    }
  }
  block.count = data.count();
  return { block, rows, tags };
}

function runChart(option, fn) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    let error = null;
    try {
      chart.setOption(option);
    } catch (e) {
      error = e;
    }
    return fn(chart, error);
  } finally {
    try { chart.dispose(); } catch (e) { /* a chart whose render threw */ }
  }
}

function tagOption(option) {
  for (const s of seriesArray(option)) {
    if (!s) continue;
    for (const k of KINDS) {
      const d = s[k] && s[k].data;
      if (!isArray(d)) continue;
      d.forEach((el, i) => {
        if (isArray(el)) el.forEach(e => { if (isObject(e)) e[TAG] = i; });
        else if (isObject(el)) el[TAG] = i;
      });
    }
  }
  return option;
}

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));

function markedSeries(option) {
  const out = [];
  seriesArray(option).forEach((s, i) => {
    if (s && KINDS.some(k => s[k] && s[k].data)) out.push(i);
  });
  return out;
}

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  const input = JSON.parse(optionText);
  const masters = masterInputs(input);
  const marked = markedSeries(input);
  must(marked.length, def.id + ': no series with markers');

  // the verbatim run: every recorded number, and the transcriptions
  const base = runChart(JSON.parse(optionText), (chart, error) => {
    const ec = chart.getModel();
    const tx = {};
    for (const si of marked) {
      const sm = ec.getSeriesByIndex(si);
      const inp = { seriesOpt: seriesArray(input)[si], masters };
      const key = def.id + '/' + si;
      const ctx = ctxOf(chart, sm);
      const res = { base: null, muts: {} };
      const run = mut => {
        try {
          return transcribe(ctx, JSON.parse(JSON.stringify(inp, (k, v) => v)), mut);
        } catch (e) {
          if (e instanceof OracleError) throw e;
          return { threw: String(e.message) };
        }
      };
      res.base = run({});
      for (const g of GUARDS) res.muts[g.id] = run(g.mut);
      tx[key] = res;
    }
    if (error) return { error: String(error.message), tx };
    const grids = [];
    for (let gi = 0; ; gi++) {
      const gm = ec.getComponent('grid', gi);
      if (!gm) break;
      grids.push(Object.assign({ index: gi }, rectRec(gm.coordinateSystem.getRect())));
    }
    const series = marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      const data = sm.getData();
      const cs = sm.coordinateSystem;
      must(cs && cs.type === 'cartesian2d', def.id + '/' + si + ': not cartesian2d');
      const filtered = ec.isSeriesFiltered(sm);
      const color = (() => {
        const c = data.getVisual('style')[data.getVisual('drawType')];
        return typeof c === 'string' ? c : null;
      })();
      const sr = {
        seriesIndex: si, name: sm.option.name == null ? null : String(sm.option.name), type: sm.subType, filtered,
        gridIndex: cs.model.componentIndex, baseAxisDim: sm.getBaseAxis().dim, dataCount: data.count(), color,
        stack: data.getCalculationInfo('stackedDimension') ? {
          option: sm.get('stack') == null ? null : String(sm.get('stack')), stackedDimension: data.getCalculationInfo('stackedDimension'),
        } : null,
        coordDims: cs.dimensions.map(d => ({ coordDim: d, dataDim: data.mapDimension(d), type: (data.getDimensionInfo(data.mapDimension(d)) || {}).type || null })),
        bar: typeof sm.getMarkerPosition === 'function' && !filtered ? Object.assign({}, numRec('offset', data.getLayout('offset')), numRec('size', data.getLayout('size'))) : null,
        axes: [axisRec(cs.getAxis('x')), axisRec(cs.getAxis('y'))],
      };
      for (const k of KINDS) {
        const own = seriesArray(input)[si][k];
        if (!own || !own.data) { sr[k] = null; continue; }
        if (filtered) { sr[k] = null; continue; }
        sr[k] = survivors(chart, sm, k);
      }
      return sr;
    });
    return { error: null, grids, series, tx };
  });

  // the tagged run: which original element each survivor came from
  const tagged = runChart(tagOption(JSON.parse(optionText)), (chart, error) => {
    if (error) return { error: String(error.message) };
    const ec = chart.getModel();
    return { error: null, series: marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      const o = {};
      for (const k of KINDS) {
        const own = seriesArray(input)[si][k];
        o[k] = own && own.data && !ec.isSeriesFiltered(sm) ? survivors(chart, sm, k) : null;
      }
      return o;
    }) };
  });

  Object.assign(side, base.tx);
  must((base.error == null) === (tagged.error == null), def.id + ': the tagged run ' + (tagged.error ? 'threw' : 'did not throw'));
  const rec = {
    id: def.id, note: def.note, width: W, height: H, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    error: base.error, nan: !!def.nan, grids: base.error ? [] : base.grids, series: [],
  };
  if (base.error) return rec;
  rec.series = base.series.map((sr, n) => {
    for (const k of KINDS) {
      if (!sr[k]) continue;
      const b = sr[k];
      const t = tagged.series[n][k];
      must(t && JSON.stringify(t.rows) === JSON.stringify(b.rows) && JSON.stringify(t.block) === JSON.stringify(b.block),
        def.id + '/' + sr.seriesIndex + ' ' + k + ': the tagged run differs from the verbatim run');
      const nIn = seriesArray(input)[sr.seriesIndex][k].data.length;
      for (let j = 0; j < t.tags.length; j++) {
        must(Number.isInteger(t.tags[j]) && t.tags[j] >= 0 && t.tags[j] < nIn && (j === 0 || t.tags[j] > t.tags[j - 1]),
          def.id + '/' + sr.seriesIndex + ' ' + k + ': tags ' + JSON.stringify(t.tags));
      }
      const items = [];
      for (let i = 0; i < nIn; i++) {
        const j = t.tags.indexOf(i);
        items.push(Object.assign({ index: i, survived: j >= 0, dataIndex: j >= 0 ? j : null }, j >= 0 ? b.rows[j] : {}));
      }
      sr[k] = Object.assign({}, b.block, { items });
    }
    return sr;
  });
  return rec;
}

// ---------- the cases ----------
const WEEK = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const D7 = [120, 132, 101, 134, 90, 230, 210];
const cat = (series, extra) => Object.assign({
  xAxis: { type: 'category', data: WEEK.slice(0, Math.max(...series.map(s => s.data.length))) }, yAxis: { type: 'value' },
  series: series.map(s => Object.assign({ type: 'line' }, s)),
}, extra || {});
const vv = (series, extra) => Object.assign({ xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: series.map(s => Object.assign({ type: 'scatter' }, s)) }, extra || {});
const STATS = [{ type: 'min', name: 'Min' }, { type: 'max', name: 'Max' }, { type: 'average', name: 'Avg' }, { type: 'median', name: 'Med' }];
const OHLC = [[20, 34, 10, 38], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42], [15, 27, 12, 29], [27, 40, 25, 47]];

const CASES = [
  // ----- markPoint -----
  { id: 'P1', note: 'markPoint min/max/average/median on a category line: every statistic lands on the NEAREST datum (average 145.28... -> Thu 134; median of 7 = 132), value = that datum',
    option: cat([{ data: D7, markPoint: { data: STATS } }]) },
  { id: 'P2', note: 'median of an even count (4.5 between the data 4 and 5): nearest search tie in pixels, the diff >= 0 rule; average 4.875',
    option: cat([{ data: [5, 1, 9, 3, 7, 2, 8, 4], markPoint: { data: STATS } }], { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] } }) },
  { id: 'P3', note: 'duplicate max / min values: the FIRST row in view order wins (indicesOfNearest [0])',
    option: cat([{ data: [3, 9, 4, 9, 2, 6, 2], markPoint: { data: [{ type: 'max' }, { type: 'min' }] } }]) },
  { id: 'P4', note: 'stacked lines: markPoint position / search on the stack result, value = the RAW datum; the stack result is already addSafe-rounded (0.1 + 0.2 = 0.3), and the coord is then toFixed(precision of the RAW datum): stack t (0.125 + 0.25 = 0.375 -> 0.38; 2.0625 + 3 = 5.0625 -> 5) puts the marker OFF the stacked point; markLine 1D statistics on the stack result (precision 2)',
    option: cat([{ stack: 's', data: [0.1, 0.2, 0.7, 0.4, 0.3] },
      { stack: 's', data: [0.2, 0.1, 0.4, 0.25, 0.15], markPoint: { data: STATS }, markLine: { data: [{ type: 'average' }, { type: 'max' }, { type: 'median' }] } },
      { stack: 't', data: [0.125, 1.5, 2.0625, 0.5, 1] }, { stack: 't', data: [0.25, 1, 3, 0.75, 0.5], markPoint: { data: [{ type: 'min' }, { type: 'max' }, { type: 'median' }] } }]) },
  { id: 'P5', note: "candlestick: valueDim 'highest' / 'lowest' / 'close', valueIndex 1 and 3; the series colour is the candlestick's default itemStyle.color",
    option: { xAxis: { type: 'category', data: WEEK.slice(0, 6) }, yAxis: { type: 'value' },
      series: [{ type: 'candlestick', data: OHLC, markPoint: { data: [{ type: 'max', valueDim: 'highest' }, { type: 'min', valueDim: 'lowest' },
        { type: 'average', valueDim: 'close' }, { type: 'max', valueIndex: 1 }, { type: 'min', valueIndex: 3 }, { type: 'max' }] },
        markLine: { data: [{ type: 'max', valueDim: 'highest' }, [{ type: 'min', valueDim: 'lowest' }, { type: 'max', valueDim: 'highest' }]] } }] } },
  { id: 'P6', note: 'horizontal bars, two per band (category y, value x): statistics on x, the bar offset added on y (a lone bar is centred: offset + size / 2 = 0); markLine average is VERTICAL',
    option: { yAxis: { type: 'category', data: WEEK }, xAxis: { type: 'value' },
      series: [{ type: 'bar', data: D7, markPoint: { data: [{ type: 'max' }, { type: 'min' }, { coord: [150, 'Wed'] }] }, markLine: { data: [{ type: 'average' }] } },
        { type: 'bar', data: D7.map(v => v / 2) }] } },
  { id: 'P7', note: "scatter, two value axes: base x, value y; coord numbers, a numeric STRING coord, 'min'/'max'/'average'/'median' strings inside coord (numCalculate over that dim, not rounded, not the nearest datum), an out-of-extent coord (filtered)",
    option: vv([{ data: [[1, 3], [2.5, 8], [4, 5.5], [6, 1], [8, 7], [9.5, 4.2]], markPoint: { data: [{ type: 'max' }, { type: 'min' }, { type: 'average' },
      { coord: [3, 6] }, { coord: ['5', '2'] }, { coord: ['min', 'max'] }, { coord: ['average', 'median'] }, { coord: [50, 3] }, { xAxis: 'max', yAxis: 4 }] } }]) },
  { id: 'P8', note: "category coords: a category string, an ordinal number, an unknown category (NaN -> filtered), xAxis/yAxis items, an xAxis-only item (y undefined -> filtered), a yAxis 'max' item",
    option: cat([{ data: D7, markPoint: { data: [{ coord: ['Wed', 150] }, { coord: [5, 60] }, { coord: ['Nope', 100] },
      { xAxis: 'Fri', yAxis: 200 }, { xAxis: 1, yAxis: 170, value: 170 }, { xAxis: 'Sat' }, { xAxis: 'Tue', yAxis: 'max' }] } }]) },
  { id: 'P9', note: "x/y px and percent (container), relativeTo 'coordinate' (grid rect), one px end plus yAxis; an x-only item keeps y NaN (kept: hasXOrY skips the filter); 'center'/'middle' (hasXOrY false -> filtered as coordless)",
    nan: true,
    option: cat([{ data: D7, markPoint: { data: [{ x: 100, y: 80 }, { x: '50%', y: '25%' }, { x: '10%', y: '90%', relativeTo: 'coordinate' },
      { x: 0, y: 0, relativeTo: 'coordinate' }, { x: '100%', y: '100%', relativeTo: 'coordinate' }, { x: 300, yAxis: 120 }, { x: 150 },
      { x: 'center', y: 'middle' }, { x: 'right', y: 30 }] } }]) },
  { id: 'P10', note: 'an inside dataZoom window 30..70 %: statistics over the window rows only; a coord outside the window is dropped (containData on the zoomed scale); one inside kept',
    option: cat([{ data: [50, 300, 120, 132, 101, 134, 90, 230, 210, 20], markPoint: { data: [{ type: 'max' }, { type: 'min' }, { type: 'average' },
      { coord: ['Mon', 50] }, { coord: [4, 101] }] }, markLine: { data: [{ type: 'max' }, { xAxis: 1 }, { xAxis: 5 }] } }],
    { xAxis: { type: 'category', data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9'] }, dataZoom: [{ type: 'inside', start: 30, end: 70 }] }) },
  { id: 'P11', note: 'median with NaN rows: getMedian sorts the non-NaN values but indexes with count() INCLUDING the NaN rows: [-,10,20,30,40] -> 30 (not 25), [-,-,10,20,30,40] -> 35; average skips NaN',
    option: cat([{ data: [null, 10, 20, 30, 40], markPoint: { data: [{ type: 'median' }, { type: 'average' }] }, markLine: { data: [{ type: 'median' }] } },
      { data: [null, '-', 10, 20, 30, 40], markPoint: { data: [{ type: 'median' }] }, markLine: { data: [{ type: 'median' }] } }]) },
  { id: 'P12', note: 'median reading past the sorted array (4 values, count 8): NaN -> no nearest datum -> coord [NaN, NaN] -> filtered (markPoint); markLine 1D median NaN -> filtered',
    option: cat([{ data: [null, null, null, null, 10, 20, 30, 40], markPoint: { data: [{ type: 'median' }, { type: 'max' }] }, markLine: { data: [{ type: 'median' }, { type: 'max' }] } }],
      { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] } }) },
  { id: 'P13', note: 'an empty series: min/max give +-Infinity, average 0/0 = NaN, median 0; no datum -> coord NaN -> filtered; px items survive; markLine {yAxis} kept, 1D statistics dropped (median 0 kept when 0 is on the axis)',
    option: { xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [],
      markPoint: { data: [{ type: 'max' }, { type: 'average' }, { type: 'median' }, { x: 100, y: 100 }, { coord: ['Tue', 0.5] }] },
      markLine: { data: [{ type: 'min' }, { type: 'max' }, { type: 'average' }, { type: 'median' }, { yAxis: 0.5 }] } }] } },
  { id: 'P14', note: 'series-level symbol options (symbol, symbolSize [w,h], symbolRotate, symbolOffset, symbolKeepAspect) inherited by items; item overrides; a top-level markPoint symbolSize under both',
    option: Object.assign(cat([{ data: D7, markPoint: { symbol: 'circle', symbolSize: [20, 30], symbolRotate: 30, symbolOffset: [0, '-50%'], symbolKeepAspect: true,
      data: [{ type: 'max' }, { type: 'min', symbol: 'rect', symbolSize: 12, symbolRotate: 0, symbolOffset: 0 }] } },
    { data: D7.map(v => v / 2), markPoint: { data: [{ type: 'max' }, { type: 'min', symbolSize: 20 }] } }]), { markPoint: { symbolSize: 40, symbol: 'diamond' } }) },
  { id: 'P15', note: 'three bars per band: markPoint on the FIRST series (bar offset + size/2 on the base axis; the middle one would be centred) incl. a coord item; a pictorialBar series markPoint too (its own layout group, alone: centred)',
    option: { xAxis: { type: 'category', data: WEEK.slice(0, 5) }, yAxis: { type: 'value' }, series: [
      { type: 'bar', data: [15, 25, 16, 30, 12], markPoint: { data: [{ type: 'max' }, { type: 'min' }, { coord: ['Wed', 20] }, { xAxis: 1, yAxis: 25 }] } }, { type: 'bar', data: [5, 20, 36, 10, 10] },
      { type: 'bar', data: [8, 12, 30, 22, 5] }, { type: 'pictorialBar', symbol: 'circle', data: [10, 14, 8, 26, 18], markPoint: { data: [{ type: 'max' }, { type: 'average' }] } }] } },
  { id: 'P16', note: 'scatter, two value axes, markPoint min/max/average/median + markLine average/min + {xAxis} + 2D coord pair',
    option: vv([{ data: [[10, 8.04], [8, 6.95], [13, 7.58], [9, 8.81], [11, 8.33], [14, 9.96], [6, 7.24], [4, 4.26], [12, 10.84], [7, 4.82], [5, 5.68]],
      markPoint: { data: STATS }, markLine: { data: [{ type: 'average' }, { type: 'min' }, { xAxis: 9 }, [{ coord: [4, 4] }, { coord: [14, 11] }]] } }]) },
  { id: 'P17', note: 'bars on a VALUE x axis with fixed min/max: the scale gets a MAPPING extent wider than the effective one; containData reads the mapping, clampData the effective: a coord at x 0.8 (inside mapping, outside effective) and at 0.5',
    option: { xAxis: { type: 'value', min: 1, max: 5 }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [[1, 5], [2, 7], [3, 3], [4, 8], [5, 6]],
      markPoint: { data: [{ coord: [0.8, 4] }, { coord: [0.5, 4] }, { coord: [5.2, 4] }, { type: 'max' }] }, markLine: { data: [{ xAxis: 0.8 }, { xAxis: 1 }] },
      markArea: { data: [[{ xAxis: 0.8 }, { xAxis: 1.5 }]] } }] } },
  { id: 'P18', note: "time x axis: coord with a date string (parseDate) and a timestamp; markLine {xAxis: date string} (value kept as the string; containData parses it); markArea between two date strings. Every date string carries 'Z' (UTC): parseDate reads a bare 'yyyy-mm-dd' as LOCAL time, which would make the fixture depend on the machine's time zone",
    option: { xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [['2024-01-01T00:00:00Z', 5], ['2024-01-02T00:00:00Z', 9], ['2024-01-04T00:00:00Z', 3], ['2024-01-07T00:00:00Z', 7]],
      markPoint: { data: [{ type: 'max' }, { coord: ['2024-01-03T00:00:00Z', 6] }, { coord: [1704412800000, 4] }] }, markLine: { data: [{ xAxis: '2024-01-05T00:00:00Z' }, { type: 'average' }] },
      markArea: { data: [[{ xAxis: '2024-01-02T00:00:00Z' }, { xAxis: '2024-01-04T00:00:00Z' }]] } }] } },

  // ----- markLine -----
  { id: 'L1', note: 'markLine 1D min/max/average/median (average 145.28571428571428 -> precision 2 -> 145.29, NOT a datum), plus {type: max} with a valueIndex',
    option: cat([{ data: D7, markLine: { data: [{ type: 'min' }, { type: 'max' }, { type: 'average', name: 'Avg' }, { type: 'median' }, { type: 'max', valueIndex: 1 }] } }]) },
  { id: 'L2', note: 'precision 0 on one series markLine, 4 on another, 30 (clamped to 20 in toFixed) on a third',
    option: cat([{ data: D7, markLine: { precision: 0, data: [{ type: 'average' }] } }, { data: D7.map(v => v / 3), markLine: { precision: 4, data: [{ type: 'average' }, { type: 'max' }] } },
      { data: D7.map(v => v / 7), markLine: { precision: 30, data: [{ type: 'average' }] } }]) },
  { id: 'L3', note: "1D constants on a category x axis: {yAxis: 50}, {xAxis: 'Wed'}, {xAxis: 2}, an out-of-extent {yAxis: 1000} (filtered), unknown {xAxis: 'Nope'} (filtered), {xAxis: 3, yAxis: 60} (yAxis wins), {yAxis: '75'} (string kept)",
    option: cat([{ data: D7, markLine: { data: [{ yAxis: 50 }, { xAxis: 'Wed' }, { xAxis: 2 }, { yAxis: 1000 }, { xAxis: 'Nope' }, { xAxis: 3, yAxis: 60, name: 'both' }, { yAxis: '75' }] } }]) },
  { id: 'L4', note: 'value x axis: {xAxis: 3}, {xAxis: 100} (filtered), {yAxis: -1} (filtered), 2D pairs of coords / types / px, a pair whose name / value sit on the END item only (merge picks them from the end)',
    option: vv([{ data: [[0, 1], [2, 4], [5, 3], [7, 8], [9, 6]], markLine: { data: [{ xAxis: 3 }, { xAxis: 100 }, { yAxis: -1 },
      [{ coord: [1, 2] }, { coord: [8, 7] }], [{ type: 'min' }, { type: 'max' }], [{ x: 100, y: 100 }, { x: '50%', y: '80%' }],
      [{ coord: [2, 2], name: 'start' }, { coord: [6, 5], name: 'end', value: 99 }], [{ coord: [3, 3] }, { coord: [6, 5], name: 'endOnly', value: 7 }],
      [{ coord: [1, 2] }, { coord: [20, 7] }]] } }]) },
  { id: 'L5', note: "the merge-order quirk as bar-stack: a pair [{type:'min'},{type:'max'}] -> the line value is the MIN datum (from the start item); plus a pair with x px + yAxis 'max'",
    option: cat([{ type: 'bar', data: D7 }, { type: 'bar', data: [60, 72, 71, 74, 190, 130, 110], markLine: { lineStyle: { type: 'dashed' }, data: [[{ type: 'min' }, { type: 'max' }],
      [{ x: '90%', yAxis: 'max', symbol: 'none' }, { type: 'max', name: 'top', symbol: 'circle' }], [{ type: 'max', name: 'hi' }, { type: 'min', name: 'lo', value: 1 }]] } }]) },
  { id: 'L6', note: 'inverse axes (category x inverse, value y inverse): 1D ends from getExtent()[0] (from) to [1] (to) -> right-to-left / top-to-bottom; 2D pair',
    option: cat([{ data: D7, markLine: { data: [{ type: 'average' }, { xAxis: 'Wed' }, [{ type: 'min' }, { type: 'max' }]] } }],
      { xAxis: { type: 'category', inverse: true, data: WEEK }, yAxis: { type: 'value', inverse: true } }) },
  { id: 'L7', note: 'three bars per band: markLine pair [{type:min},{type:max}] (bar offsets), 1D average (the Infinity end overrides the offset), 1D {xAxis: Wed}',
    option: { xAxis: { type: 'category', data: WEEK.slice(0, 5) }, yAxis: { type: 'value' }, series: [
      { type: 'bar', data: [5, 20, 36, 10, 10] }, { type: 'bar', data: [15, 25, 16, 30, 12], markLine: { data: [[{ type: 'min' }, { type: 'max' }], { type: 'average' }, { xAxis: 'Wed' }] } },
      { type: 'bar', data: [8, 12, 30, 22, 5], markLine: { data: [[{ type: 'min' }, { type: 'max' }]] } }] } },
  { id: 'L8', note: "a top-level markLine {z: -100, precision: 1, symbol: 'none'} master option plus series markLines (inherit z / precision / symbol; one series overrides precision and symbol, one sets silent)",
    option: Object.assign(cat([{ data: D7, markLine: { data: [{ type: 'average' }] } }, { data: D7.map(v => v * 0.7), silent: true, markLine: { precision: 3, symbol: ['arrow', 'circle'], data: [{ type: 'average' }] } }]),
      { markLine: { z: -100, precision: 1, symbol: 'none' } }) },
  { id: 'L9', note: 'series-level symbol options: symbolSize scalar 12 -> both ends 12; per-end symbol / symbolSize / symbolRotate / symbolOffset overrides (own-only for symbol / rotate / offset, WITH the parent for symbolSize)',
    option: cat([{ data: D7, markLine: { symbolSize: 12, symbolRotate: 45, symbolOffset: [0, 5], data: [{ type: 'average' },
      [{ type: 'min', symbol: 'rect', symbolSize: 20, symbolRotate: 10, symbolOffset: [3, 0] }, { type: 'max', symbol: 'triangle' }]] } },
    { data: D7.map(v => v / 2), markLine: { symbol: ['none', 'circle'], data: [{ type: 'average' }, [{ type: 'min', symbolKeepAspect: true }, { type: 'max', symbolSize: 6 }]] } }]) },

  // ----- markArea -----
  { id: 'A1', note: "markArea on a category line: xAxis-only range (infinite y), yAxis-only (infinite x), both, reversed corners, partly outside (clamped), fully outside with finite corners (zone test drops it), yAxis-only fully outside (kept by the only-dim rule, allClipped), px corners, names (lt's wins); an unknown category x range ['Nope', 'Wed'] is KEPT by the only-dim rule (no containData), its x0 corners are NaN and allClipped is false (NaN compares false): upstream builds a polygon with two NaN points (item 8, the documented NaN); 'min' / 'average' strings in the implicit coord",
    nan: true,
    option: cat([{ data: D7, markArea: { data: [[{ xAxis: 'Tue', name: 'tue-thu' }, { xAxis: 'Thu', name: 'ignored' }], [{ yAxis: 100 }, { yAxis: 150 }],
      [{ coord: ['Mon', 100] }, { coord: ['Wed', 200] }], [{ coord: ['Sat', 220] }, { coord: ['Thu', 95] }], [{ xAxis: 'Fri', yAxis: 50 }, { xAxis: 'Sun', yAxis: 1000 }],
      [{ xAxis: 'Mon', yAxis: 500 }, { xAxis: 'Tue', yAxis: 600 }], [{ yAxis: 500 }, { yAxis: 600 }], [{ x: 100, y: 100 }, { x: 200, y: '50%' }],
      [{ xAxis: 'Nope' }, { xAxis: 'Wed' }], [{ xAxis: 'Wed', yAxis: 'min' }, { xAxis: 'Sun', yAxis: 'average' }], [{ coord: [4, 50] }, { coord: [6, 1000] }]] } }]) },
  { id: 'A2', note: 'markArea on a bar series: the getMarkerPosition(startingAtTick) branch snaps category ends to tick coords (x1 takes tick id + 1); value ends clamped',
    option: { xAxis: { type: 'category', data: WEEK.slice(0, 5) }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [15, 25, 16, 30, 12],
      markArea: { data: [[{ xAxis: 'Tue' }, { xAxis: 'Thu' }], [{ xAxis: 'Mon', yAxis: 10 }, { xAxis: 'Mon', yAxis: 20 }], [{ yAxis: 5 }, { yAxis: 18 }],
        [{ xAxis: 'Thu', yAxis: 28 }, { xAxis: 'Tue', yAxis: 50 }], [{ xAxis: 'Fri' }, { xAxis: 'Fri' }]] } }] } },
  { id: 'A3', note: 'the bar markArea with axisTick.alignWithLabel (no +1 on the end tick) on a horizontal bar (category y)',
    option: { yAxis: { type: 'category', data: WEEK.slice(0, 5), axisTick: { alignWithLabel: true } }, xAxis: { type: 'value' }, series: [{ type: 'bar', data: [15, 25, 16, 30, 12],
      markArea: { data: [[{ yAxis: 'Tue' }, { yAxis: 'Thu' }], [{ yAxis: 'Mon', xAxis: 10 }, { yAxis: 'Wed', xAxis: 20 }]] } }] } },
  { id: 'A4', note: "scatter markArea with 'min'/'max' strings in the implicit coord (the data bounding box) and 'average'",
    option: vv([{ data: [[161.2, 51.6], [167.5, 59.0], [159.5, 49.2], [157.0, 63.0], [155.8, 53.6], [170.0, 59.0], [159.1, 47.6]],
      markArea: { data: [[{ xAxis: 'min', yAxis: 'min' }, { xAxis: 'max', yAxis: 'max' }], [{ xAxis: 'average' }, { xAxis: 'max' }]] } }], { xAxis: { type: 'value', scale: true }, yAxis: { type: 'value', scale: true } }) },
  { id: 'A5', note: 'markArea under a dataZoom window 30..70 %: an x range across the window edge (clamped to the SCALE extent), one fully left of it (xAxis-only: kept, allClipped), one with finite corners outside (zone drops)',
    option: cat([{ data: [50, 300, 120, 132, 101, 134, 90, 230, 210, 20], markArea: { data: [[{ xAxis: 'c1' }, { xAxis: 'c4' }], [{ xAxis: 'c0' }, { xAxis: 'c1' }],
      [{ xAxis: 'c0', yAxis: 10 }, { xAxis: 'c1', yAxis: 20 }], [{ xAxis: 'c5' }, { xAxis: 'c9' }]] } }],
    { xAxis: { type: 'category', data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9'] }, dataZoom: [{ type: 'slider', start: 30, end: 70 }] }) },

  { id: 'A6', note: "a category Y axis (value x, line series): a markArea of two empty ends is infinite on both dims; each corner's infinite x goes to the x axis' end, but the `else if` leaves its infinite y where clampData put it -- on the first / last category's BAND CENTRE, not the axis end (a value axis would hide this: its clamped end IS the axis end)",
    option: { xAxis: { type: 'value' }, yAxis: { type: 'category', data: WEEK.slice(0, 5) }, series: [{ type: 'line', data: [[3, 'Mon'], [7, 'Tue'], [5, 'Wed'], [9, 'Thu'], [4, 'Fri']],
      markArea: { data: [[{}, {}], [{ yAxis: 'Tue' }, {}]] } }] } },
  { id: 'A7', note: 'allClipped sorts the two ends first: an x range written backwards and spanning the whole extent ([12, -2] over [0, 10]) overlaps -- unsorted it would read as clipped',
    option: vv([{ data: [[1, 2], [5, 6], [9, 3]], markArea: { data: [[{ xAxis: 12 }, { xAxis: -2 }], [{ xAxis: 12 }, { xAxis: 11 }]] } }], { xAxis: { type: 'value', min: 0, max: 10 } }) },
  { id: 'L10', note: 'a 1D average line on a series with gaps: the statistic itself (not a datum), so the average must skip the NaN rows -- 25, not 20 (a markPoint average would hide it: 20 and 25 both land on the datum 20)',
    option: cat([{ data: [null, 10, 20, 30, 40], markLine: { data: [{ type: 'average' }] } }], { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] } }) },

  // ----- other -----
  { id: 'H1', note: 'a legend-unselected series: its markers are not drawn (filtered, no marker data); the visible series draws its own',
    option: Object.assign(cat([{ name: 'a', data: D7, markPoint: { data: [{ type: 'max' }] }, markLine: { data: [{ type: 'average' }] }, markArea: { data: [[{ xAxis: 'Mon' }, { xAxis: 'Tue' }]] } },
      { name: 'b', data: D7.map(v => v / 2), markPoint: { data: [{ type: 'max' }] }, markLine: { data: [{ type: 'average' }] } }]), { legend: { selected: { a: false } } }) },
  { id: 'Z1', note: 'z / zlevel / silent through the chain: top-level markPoint {z: 7, silent: true}, series markArea {z: 3, zlevel: 1}, a series with silent: true, markLine defaults',
    option: Object.assign(cat([{ data: D7, markPoint: { data: [{ type: 'max' }] }, markLine: { data: [{ type: 'min' }] }, markArea: { z: 3, zlevel: 1, data: [[{ xAxis: 'Mon' }, { xAxis: 'Wed' }]] } },
      { data: D7.map(v => v / 2), silent: true, markArea: { data: [[{ yAxis: 10 }, { yAxis: 40 }]] }, markLine: { data: [{ yAxis: 30 }] } }]), { markPoint: { z: 7, silent: true } }) },
  { id: 'E1', note: 'an invalid markLine 1D element ({name} only: markLineTransform gives [], markLineFilter reads item[0].coord of undefined): upstream THROWS in render',
    option: cat([{ data: D7, markLine: { data: [{ name: 'bad' }] } }]) },
  { id: 'E2', note: 'a markArea element that is not a pair (markAreaTransform returns undefined, markAreaFilter reads item.coord): upstream THROWS in render',
    option: cat([{ data: D7, markArea: { data: [{ xAxis: 'Mon' }] } }]) },
];
const GALLERY_CASES = ['area-pieces', 'area-rainfall', 'bar-rich-text', 'bar-stack', 'bar1', 'candlestick-sh', 'line-aqi', 'line-marker', 'line-markline',
  'line-sections', 'pictorialBar-body-fill', 'pictorialBar-hill', 'pictorialBar-spirit', 'scatter-anscombe-quartet', 'scatter-weight'];
for (const g of GALLERY_CASES) CASES.push({ id: 'G-' + g, note: 'gallery ' + g + '.json, verbatim', gallery: g });

// ---------- the guards ----------
const GUARDS = [
  { id: 'stat-value', mutation: 'markPoint / 2D-end statistic placed at the statistic itself, not on the nearest datum', mut: { statValue: true }, named: ['P1', 'P2', 'P5'] },
  { id: 'no-stack-result', mutation: 'the statistic, search and position on the raw dim instead of the stack result', mut: { noStackResult: true }, named: ['P4'] },
  { id: 'ml1d-not-stacked', mutation: 'markLine 1D statistic over the raw dim (not stack-aware)', mut: { ml1dNotStacked: true }, named: ['P4'] },
  { id: 'no-precision', mutation: 'markLine precision (toFixed) not applied to the 1D value', mut: { noPrecision: true }, named: ['L1', 'L2', 'G-bar1'] },
  { id: 'no-coord-precision', mutation: 'the statistic coord not toFixed(precision of the raw datum)', mut: { noCoordPrecision: true }, named: ['P4'] },
  { id: 'filter-off', mutation: 'dataFilter / markLineFilter / markAreaFilter keep everything', mut: { noFilter: true }, named: ['P7', 'P8', 'P10', 'L3', 'L4', 'A1'] },
  { id: 'zone-off', mutation: 'markAreaFilter without the zone test', mut: { zoneOff: true }, named: ['A1', 'A5'] },
  { id: 'bar-offset', mutation: 'bar getMarkerPosition without offset + size / 2', mut: { noBarOffset: true }, named: ['P6', 'P15', 'L7', 'G-bar-stack'] },
  { id: 'inf-extent', mutation: 'Infinity ends / corners not replaced by the axis extent', mut: { noInfExtent: true }, named: ['L1', 'L3', 'A1'] },
  { id: 'merge-reversed', mutation: 'the line item merged from the END item first', mut: { mergeReversed: true }, named: ['L5', 'G-bar-stack'] },
  { id: 'size-own-only', mutation: 'markLine end symbolSize read own-only (no parent fallthrough)', mut: { sizeOwnOnly: true }, named: ['L1', 'L9', 'G-bar1'] },
  { id: 'median-no-quirk', mutation: 'median indexed by the non-NaN count', mut: { medianNoQuirk: true }, named: ['P11', 'P12'] },
  { id: 'tie-last', mutation: 'the LAST of equally near rows taken', mut: { tieLast: true }, named: ['P3'] },
  { id: 'rel-ignored', mutation: "relativeTo 'coordinate' ignored (container size)", mut: { relIgnored: true }, named: ['P9'] },
  { id: 'no-clamp', mutation: 'markArea corners not clampData-ed before dataToPoint', mut: { noClamp: true }, named: ['A4'] },
  { id: 'no-tick-snap', mutation: 'bar markArea corners not snapped to ticks (the plain clamp + dataToPoint path)', mut: { noTickSnap: true }, named: ['A2'] },
  { id: 'align-ignored', mutation: 'axisTick.alignWithLabel ignored (the end tick always + 1)', mut: { alignIgnored: true }, named: ['A3'] },
  { id: 'all-clipped-off', mutation: 'allClipped never set', mut: { noAllClipped: true }, named: ['A1', 'A5'] },
  { id: 'x-wins', mutation: 'markLine 1D with both xAxis and yAxis: xAxis wins', mut: { xWins: true }, named: ['L3'] },
  { id: 'no-coord-stat', mutation: "'min'/'max'/'average'/'median' strings inside coord left unresolved", mut: { noCoordStat: true }, named: ['P7', 'A4', 'G-scatter-weight', 'G-line-marker'] },
];

// ---------- the run ----------
function generate() {
  const side = {};
  const cases = CASES.map(d => {
    try {
      return recordCase(d, side);
    } catch (e) {
      if (e instanceof OracleError) e.message = d.id + ': ' + e.message;
      throw e;
    }
  });
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED,
    api: {
      master: "ecModel.getComponent('markPoint' | 'markLine' | 'markArea'): the top-level component (the install preprocessor creates it as {} when only series have markers); its option = author option merged over the defaults",
      slave: 'MarkerModel.getMarkerModelFromSeries(series, kind) = Object.getPrototypeOf(master.constructor).getMarkerModelFromSeries: new MarkXModel(series.markX option, master) -- a plain Model chain item -> series.markX -> master',
      markPoint: 'slave.getData() (mpData, dims x / y): getRawDataItem (the transformed item), get, getItemLayout (the point), getItemVisual(symbol*)',
      markLine: "slave.getData() = lineData (no dims; raw items = the merged line items); fromData / toData = slave['__ec_inner_*'].from / .to (dims x / y; layouts = the end points; per-end visuals)",
      markArea: 'slave.getData() (areaData, dims x0 y0 x1 y1): getItemLayout = {points (4 corners), allClipped}; getItemGraphicEl = the polygon or null',
      group: 'chart.getViewOfComponentModel(master).markerGroupMap.get(series.id).group: silent; every displayable z / zlevel',
      tag: "a second run with data elements tagged '" + TAG + "' maps survivors to original indices",
    },
    notes: [
      'Only cartesian2d series are covered (no polar / geo / calendar markers in the gallery).',
      'Recorded point / coord values are the doubles upstream holds (no Float32Array anywhere in the marker path).',
      "A NaN in a surviving item is legal only where the case is marked nan: a markPoint given only x (px) keeps y NaN (hasXOrY skips the filter; SymbolDraw then draws nothing).",
      'E1 / E2: upstream throws inside setOption (the render); the port must skip such elements instead.',
      'A statistic with no nearest datum (empty view, NaN statistic) does not throw: SeriesData.get(dim, undefined) is NaN (DataStore.get range check), getPrecision(NaN) = 0, NaN.toFixed(0) is NaN -> coord [NaN, NaN] -> dataFilter drops it (P12, P13).',
      "Stack results are already addSafe-rounded (processor/dataStack.ts:162); the statistic coord is then toFixed(precision of the RAW datum), which can move a stacked marker OFF its stacked point (P4 stack t: 2.0625 + 3 = 5.0625 drawn at 5).",
      'containData tests the scale MAPPING extent when present (scaleMapper.ts:446-451: bars / candlesticks widen it), clampData and allClipped the EFFECTIVE one (scale.getExtent()). A bar / pictorialBar marker kept by the mapping but outside the effective extent is drawn at the clamped value (P17: markLine xAxis 0.8 drawn at 1); other series types do not clamp markPoint / markLine.',
      'The bar offset is offset + size / 2 of THIS series in its band: 0 for a series alone in its band (a centred bar); pictorialBar lays out in its own group.',
      'markArea: the +-Infinity corner replacement only shows where the clamped corner differs from the axis pixel end: a category axis with boundaryGap (band centre vs axis edge). clampData itself only shows on the affine fast path (both axes linear): on a category axis dataToPoint(pt, true) takes the per-axis path and clamps anyway.',
      "hasXOrY / hasXAndY use parseFloat, so 'center' / 'middle' / 'left' are NOT px there (parsePercent would accept them): {x: 'center', y: 'middle'} becomes a coordless item and is filtered (P9 #7); {x: 'right', y: 30} is px (y numeric) and x resolves to 800.",
      "relativeTo 'coordinate' adds the grid's x / y to px numbers too (x: 0 -> the grid's left edge). markLine / markArea px are always container-relative.",
      'A pair markLine has line type null always (no third element); line value / name come from the START item first: for a type item the start already holds value = its raw datum, so an explicit value on the end item is ignored (L5 #2).',
      "1D markLine given as a string ({yAxis: '75'}, {xAxis: 'Wed'}) keeps the string as the line value (no precision: isNumber is false); containData parses it.",
      'Time axes: parseDate reads a bare yyyy-mm-dd as LOCAL time; P18 uses Z-suffixed strings so the fixture does not depend on the machine time zone (checked identical under TZ=UTC and America/New_York).',
      'dataTransform mutates the option in place for items it does not clone (x AND y given, or coord given as an array): coord [] is written into the px item, and a user coord array has its statistic strings replaced by numbers (markArea also writes the +-Infinity fill into it). A second render sees the numbers. Irrelevant for one render; the fixture always feeds a fresh option.',
    ],
    cases,
  };
  return { out, side };
}

function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const a = {};
  const b = {};
  for (const k of KINDS) {
    flat(sr[k], k, a);
    flat(t[k], k, b);
  }
  return diffFlat(a, b);
}

function isNaNHex(h) {
  return typeof h === 'string' && /^7ff8/.test(h);
}
function scanNaN(v) {
  if (v == null) return false;
  if (typeof v === 'string') return isNaNHex(v);
  if (isArray(v)) return v.some(scanNaN);
  // `values` of an item placed by px hold NaN / undefined by nature (never read): not scanned
  if (typeof v === 'object') return Object.keys(v).some(k => !/Text$/.test(k) && k !== 't' && k !== 'values' && scanNaN(v[k]));
  return false;
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    if (c.error) {
      // the transcription must throw for some marked series too
      const keys = Object.keys(side).filter(k => k.startsWith(c.id + '/'));
      must(keys.some(k => side[k].base.threw), c.id + ': upstream threw (' + c.error + ') but the transcription did not');
      continue;
    }
    let anyNaN = false;
    for (const sr of c.series) {
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
      for (const k of KINDS) {
        if (!sr[k]) continue;
        for (const it of sr[k].items) if (it.survived && scanNaN(it)) anyNaN = true;
      }
    }
    must(anyNaN === c.nan, c.id + ': NaN ' + (anyNaN ? 'leaks into' : 'expected in') + ' a surviving item');
  }
  // anchors
  const item = (id, si, k, i) => byId[id].series.find(s => s.seriesIndex === si)[k].items[i];
  const n = v => (v && v.n ? num(v.n) : v);
  must(n(item('P1', 0, 'markPoint', 2).coord[1]) === 134 && n(item('P1', 0, 'markPoint', 3).coord[1]) === 132, 'P1: average / median on the nearest datum');
  must(item('P4', 1, 'markPoint', 0).coord[1].t === '0.3' && item('P4', 1, 'markPoint', 0).value.t === '0.2', 'P4: stack result 0.3 (toFixed), raw value 0.2');
  must(n(item('P11', 0, 'markLine', 0).line.value) === 30 && n(item('P11', 1, 'markLine', 0).line.value) === 35, 'P11: median quirk 30 / 35');
  must(n(item('P11', 0, 'markPoint', 0).value) === 30, 'P11: markPoint median lands on 30');
  must(!item('P12', 0, 'markPoint', 0).survived, 'P12: NaN median filtered');
  must(item('L1', 0, 'markLine', 2).line.value.t === '145.29', 'L1: average 145.29');
  must(JSON.stringify(item('L1', 0, 'markLine', 0).to.symbolSize) === '[8,16]', 'L1: the [8,16] symbolSize quirk');
  must(item('L3', 0, 'markLine', 5).line.value.t === '60', 'L3: yAxis wins');
  must(!item('L3', 0, 'markLine', 3).survived && !item('L3', 0, 'markLine', 4).survived, 'L3: out-of-extent / unknown filtered');
  must(item('A1', 0, 'markArea', 6).survived && item('A1', 0, 'markArea', 6).allClipped && !item('A1', 0, 'markArea', 5).survived, 'A1: only-dim kept + allClipped, zone drop');
  must(byId.H1.series[0].filtered && byId.H1.series[0].markPoint === null, 'H1: hidden series');
  must(byId.E1.error && byId.E2.error, 'E1 / E2 throw');
  must(byId['L8'].series[0].markLine.z === -100, 'L8: master z');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      if (c.error) continue;
      let any = false;
      for (const sr of c.series) {
        const key = c.id + '/' + sr.seriesIndex;
        const d = seriesDiffs(sr, side, key, gd.id);
        if (d.length) {
          any = true;
          if (gd.named.includes(c.id)) differs.push({ case: key, fields: d.slice(0, 3) });
        }
      }
      if (any) changed.push(c.id);
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(x => changed.includes(x)), differs };
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

// upstream's dev build logs to the console (e.g. 'Invalid markLine data.'); keep the run quiet
const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let g1;
let json1;
let json2;
try {
  g1 = generate();
  if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, fmt(g1.out, '') + '\n');
  g1.out.guards = check(g1);
  json1 = fmt(g1.out, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(g1.out), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.out.guards = check(g2);
  json2 = fmt(g2.out, '') + '\n';
} catch (e) {
  console.error = quiet.error;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message + (process.env.ORACLE_DEBUG ? '\n' + e.stack : '') : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const out = g1.out;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nItems = out.cases.reduce((n, c) => n + c.series.reduce((m, s) => m + KINDS.reduce((q, k) => q + (s[k] ? s[k].items.length : 0), 0), 0), 0);
console.log(out.cases.length + ' cases (' + nItems + ' marker items); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages from upstream');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
