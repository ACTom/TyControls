// Upstream's own answers for SERIES SAMPLING (`series.sampling` on a line or a
// bar in a cartesian2d coordinate system; processor/dataSample.ts with
// DataStore.lttbDownSample / minmaxDownSample / downSample): whether a series
// is sampled at all (the count after the dataZoom filter, the base axis' pixel
// size as the grid stands BEFORE the data processing, the rate
// Math.round(count / size) and its `> 1`), which raw rows survive and in which
// order (duplicates included), the value the sampler writes back (average,
// sum, max, min, nearest), and what the rest of the chart makes of the sampled
// data: the line's layout points, an area's stacked-on points, the bars, the
// symbols and their labels, the axis extents, and the rows the axis tooltip
// picks at a few pointer positions.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600, with
// Math.random replaced by the port's xorshift32 (seed 2463534242, reset before
// each chart). Two data processors are registered for the whole run: one at
// PRIORITY.PROCESSOR.FILTER - 1 (999, before the dataZoom filter) and one at
// PRIORITY.PROCESSOR.STATISTIC - 1 (4999, after every filter, before the
// sampler); each snapshots every cartesian2d line / bar series' data as it
// stands -- the view (count, raw indices), the whole value column by raw row,
// the base axis' getExtent() and the device pixel ratio. The three
// SeriesData downsample methods are wrapped (the originals still run) to
// record which one ran and with which rate argument. After setOption the chart
// is rendered once to an SVG string (labels get their transforms there) and the
// live objects are read. The pointer probes dispatch updateAxisPointer
// (mousemove) at integer pixels and read the 'showtip' event. Every chart is
// disposed in a finally.
//
//   node tools/advchart-oracle/sampling.js
//
// writes tests/fixtures/advchart-sampling.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as line-smooth.js / datazoom-window.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000, +Infinity 7ff0000000000000,
//            -Infinity fff0000000000000). Arrays of hex have a readable twin
//            (`...Text`, String(v), '-0' for negative zero) only where noted.
//   option   recorded as fed (JSON only: a null in `data` is a missing value).
//
// Top level
//   source, W, H, seed, api, notes[]
//   cases[]  one per chart:
//     id, groups, note, width, height, option
//     throws     null, or the message upstream threw with (setOption): the
//                chart is not recorded past `series[].stage` / `sampledStore`
//     series[]   every series in series order:
//       index, type, coordSys, samplingOption (seriesModel.get('sampling') as
//       JSON; a function is never used), baseDim ('x' | 'y'), valueDim (the
//       value axis' dim), valueCol (data.mapDimension(valueDim): the dimension
//       sampled, by name with NUL written as '/'), rawCount
//       prefilter  null (no dataZoom in the option), or {count, rawIndices}
//                  at 999
//       stage      null (not cartesian2d line / bar), or at 4999:
//                  count, rawIndices, column (hex per RAW row of valueCol),
//                  baseExtent [hex, hex] (getExtent() then), dpr,
//                  size (|e1 - e0| * dpr, hex) + sizeText,
//                  rate (Math.round(count / size): hex, NaN possible) + rateText
//       ran        null, or {method ('lttb' | 'minmax' | 'downSample'),
//                  rateArg hex (the `1 / rate` handed over)}
//       sampledStore  only when `throws`: the sampled store as it was left:
//                  count (store._count) and indices (the typed array's
//                  contents: an index past its length was dropped)
//       count, rawIndices   after the render
//       values     hex per view row: data.get(valueCol, i) after the render --
//                  what the sampler wrote back for average / sum / max / min /
//                  nearest, the value as parsed otherwise
//       points     line: data.getLayout('points') as [hex, hex] pairs (the
//                  Float32Array; NaN where illegal), else null
//       stackedOn  line with an area: the polygon's shape.stackedOnPoints as
//                  [hex, hex] pairs, else null
//       bars       bar: per view row data.getItemLayout(i) {x, y, width,
//                  height} hex, else null
//       symbols    line: per view row with a graphic element: [viewRow, hex x,
//                  hex y] (the Symbol group's position), else null
//       labels     line: per view row whose symbol carries a drawn label
//                  (getTextContent(), not ignored, not invisible, text not
//                  empty): [viewRow, text, hex x, hex y, align,
//                  verticalAlign] -- x, y the label's global transform
//                  (align / verticalAlign: the label style's, else the
//                  host's _innerTextDefaultStyle)
//                  translation after the render (no rotation in these cases)
//     axes[]     xAxis then yAxis components: dim, index, type,
//                extent [hex, hex] (scale.getExtent()) + extentText,
//                pxSpanFinal hex (|getExtent()| after the render)
//     tips[]     pointer probes: {x, y (integers), shown: null | [{dim, index,
//                value hex + valueText, rows [[seriesIndex, dataIndexInside,
//                dataIndex]]}] (showtip's dataByCoordSys[0].dataByAxis)}
//   guards[]  one per mutation of the transcription: id, mutation, named (the
//             cases that must change), changed (the cases whose recorded
//             count / rawIndices / values the mutated transcription does not
//             reproduce), ok = named is a subset of changed
//
// ---------------------------------------------------------------------------
// The transcription (checked against every recorded series, bit for bit) is
// dataSample.ts (the gate and the rate, the five samplers and indexSampler)
// and DataStore.ts lttbDownSample / minmaxDownSample / downSample, fed with
// `stage` (and, for one guard, `prefilter`). Its output is the final count,
// rawIndices and values.
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every series; a series is sampled exactly when the transcription
// says so; every case that should throw throws and no other does; anchors;
// every guard is ok; two generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-sampling.json');

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
const clone = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));
// a stored value read from a store chunk: undefined (never written) is NaN
const val = v => (typeof v === 'number' ? v : NaN);

// ---------- the capture hooks ----------
let capture = null;
function snapshot(ecModel, api, key) {
  if (!capture) return;
  ecModel.eachSeries(s => {
    const rec = capture.series[s.seriesIndex] || (capture.series[s.seriesIndex] = {});
    const cs = s.coordinateSystem;
    if (!cs || cs.type !== 'cartesian2d') return;
    if (s.subType !== 'line' && s.subType !== 'bar') return;
    const data = s.getData();
    const base = cs.getBaseAxis();
    const valueAxis = cs.getOtherAxis(base);
    const dim = data.mapDimension(valueAxis.dim);
    const store = data.getStore();
    const di = data.getDimensionIndex(dim);
    const rawIndices = [];
    for (let i = 0; i < data.count(); i++) rawIndices.push(data.getRawIndex(i));
    const snap = { count: data.count(), rawIndices };
    if (key === 'stage') {
      const column = [];
      const rawCount = store._rawCount;
      must(typeof rawCount === 'number', 'no raw count on the store');
      for (let r = 0; r < rawCount; r++) column.push(val(store.getByRawIndex(di, r)));
      snap.column = column;
      const e = base.getExtent();
      snap.baseExtent = [e[0], e[1]];
      snap.dpr = api.getDevicePixelRatio();
    }
    rec[key] = snap;
  });
}
echarts.registerProcessor(echarts.PRIORITY.PROCESSOR.FILTER - 1, function (ecModel, api) { snapshot(ecModel, api, 'prefilter'); });
echarts.registerProcessor(echarts.PRIORITY.PROCESSOR.STATISTIC - 1, function (ecModel, api) { snapshot(ecModel, api, 'stage'); });

// the SeriesData prototype, reached through a throwaway chart
const SeriesDataProto = (() => {
  const c = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 100, height: 100 });
  try {
    c.setOption({ xAxis: {}, yAxis: {}, series: [{ type: 'line', data: [[1, 2]] }] });
    return Object.getPrototypeOf(c.getModel().getSeriesByIndex(0).getData());
  } finally {
    c.dispose();
  }
})();
for (const [name, tag] of [['lttbDownSample', 'lttb'], ['minmaxDownSample', 'minmax'], ['downSample', 'downSample']]) {
  const orig = SeriesDataProto[name];
  SeriesDataProto[name] = function (dim, rate) {
    if (capture) {
      const si = this.hostModel && this.hostModel.seriesIndex;
      const rec = capture.series[si] || (capture.series[si] = {});
      must(!rec.ran, 'series ' + si + ' sampled twice');
      rec.ran = { method: tag, rateArg: rate };
    }
    return orig.apply(this, arguments);
  };
}

// ---------- the transcription (with the mutations as switches) ----------

// dataSample.ts samplers
function makeSamplers(mut) {
  return {
    average(frame) {
      let sum = 0;
      let count = 0;
      for (let i = 0; i < frame.length; i++) {
        if (!isNaN(frame[i])) {
          sum += frame[i];
          count++;
        }
      }
      if (mut.avgCountsNaN) count = frame.length;
      return count === 0 ? NaN : sum / count;
    },
    sum(frame) {
      let sum = 0;
      for (let i = 0; i < frame.length; i++) sum += mut.sumNaN ? frame[i] : (frame[i] || 0);
      return sum;
    },
    max(frame) {
      let max = -Infinity;
      for (let i = 0; i < frame.length; i++) frame[i] > max && (max = frame[i]);
      if (mut.maxKeepsInf) return max === -Infinity ? NaN : max;
      return isFinite(max) ? max : NaN;
    },
    min(frame) {
      let min = Infinity;
      for (let i = 0; i < frame.length; i++) frame[i] < min && (min = frame[i]);
      return isFinite(min) ? min : NaN;
    },
    nearest(frame) {
      return mut.nearestLast ? frame[frame.length - 1] : frame[0];
    },
  };
}
const indexSampler = (frame, mut) => (mut.indexFloor ? Math.floor(frame.length / 2) : Math.round(frame.length / 2));

// DataStore.lttbDownSample; `view` raw indices, `col` the value column by raw
// row. The typed array's length caps what is kept; `count` is what upstream
// would set _count to.
function lttb(view, col, rate, mut) {
  const len = view.length;
  const getRawIndex = i => view[i];
  const frameSize = Math.floor(1 / rate);
  let currentRawIndex = getRawIndex(0);
  let maxArea;
  let area;
  let nextRawIndex;
  const cap = Math.min((Math.ceil(len / frameSize) + 2) * 2, len);
  const out = [];
  let sampledIndex = 0;
  const put = v => {
    if (sampledIndex < cap) out.push(v);
    sampledIndex++;
  };
  put(currentRawIndex);
  for (let i = 1; i < len - 1; i += frameSize) {
    const nextFrameStart = Math.min(i + frameSize, len - 1);
    const nextFrameEnd = mut.lttbClassicEnd ? Math.min(i + frameSize * 2, len - 1) : Math.min(i + frameSize * 2, len);
    const avgX = (nextFrameEnd + nextFrameStart) / 2;
    let avgY = 0;
    let nonNaN = 0;
    for (let idx = nextFrameStart; idx < nextFrameEnd; idx++) {
      const y = col[getRawIndex(idx)];
      if (isNaN(y)) continue;
      avgY += y;
      nonNaN++;
    }
    avgY /= mut.lttbAvgNonNaN ? nonNaN : (nextFrameEnd - nextFrameStart);
    const frameStart = i;
    const frameEnd = Math.min(i + frameSize, len);
    const pointAX = mut.lttbPointAX ? i : i - 1;
    const pointAY = col[currentRawIndex];
    maxArea = -1;
    nextRawIndex = mut.lttbRawFix ? getRawIndex(frameStart) : frameStart;
    let firstNaNIndex = -1;
    let countNaN = 0;
    for (let idx = frameStart; idx < frameEnd; idx++) {
      const rawIndex = getRawIndex(idx);
      const y = col[rawIndex];
      if (isNaN(y)) {
        countNaN++;
        if (firstNaNIndex < 0) firstNaNIndex = rawIndex;
        continue;
      }
      area = Math.abs((pointAX - avgX) * (y - pointAY) - (pointAX - idx) * (avgY - pointAY));
      if (mut.lttbTieLast ? area >= maxArea : area > maxArea) {
        maxArea = area;
        nextRawIndex = rawIndex;
      }
    }
    if (!mut.lttbNoNaN && countNaN > 0 && countNaN < frameEnd - frameStart) {
      put(Math.min(firstNaNIndex, nextRawIndex));
      nextRawIndex = Math.max(firstNaNIndex, nextRawIndex);
    }
    put(nextRawIndex);
    currentRawIndex = nextRawIndex;
  }
  put(getRawIndex(len - 1));
  return { indices: out, count: sampledIndex, col };
}

// DataStore.minmaxDownSample
function minmax(view, col, rate, mut) {
  const frameSize = Math.floor(1 / rate);
  const len = view.length;
  const getRawIndex = i => view[i];
  const out = [];
  for (let i = 0; i < len; i += frameSize) {
    let minIndex = i;
    let minValue = col[getRawIndex(minIndex)];
    let maxIndex = i;
    let maxValue = col[getRawIndex(maxIndex)];
    let thisFrameSize = frameSize;
    if (i + frameSize > len) thisFrameSize = len - i;
    for (let k = 0; k < thisFrameSize; k++) {
      const value = col[getRawIndex(i + k)];
      if (mut.minmaxSkipNaNStart && isNaN(minValue)) {
        minValue = value;
        maxValue = value;
        minIndex = maxIndex = i + k;
        continue;
      }
      if (value < minValue) {
        minValue = value;
        minIndex = i + k;
      }
      if (value > maxValue) {
        maxValue = value;
        maxIndex = i + k;
      }
    }
    const rawMinIndex = getRawIndex(minIndex);
    const rawMaxIndex = getRawIndex(maxIndex);
    if (mut.minmaxAlwaysMinFirst ? true : minIndex < maxIndex) {
      out.push(rawMinIndex, rawMaxIndex);
    } else {
      out.push(rawMaxIndex, rawMinIndex);
    }
  }
  return { indices: out, count: out.length, col };
}

// DataStore.downSample: writes into a copy of the column
function downSample(view, colIn, rate, sampleValue, mut) {
  const col = colIn.slice();
  const frameValues = [];
  let frameSize = Math.floor(1 / rate);
  const len = view.length;
  const out = [];
  for (let i = 0; i < len; i += frameSize) {
    if (frameSize > len - i) {
      frameSize = len - i;
      frameValues.length = frameSize;
    }
    for (let k = 0; k < frameSize; k++) frameValues[k] = col[view[i + k]];
    const value = sampleValue(frameValues);
    const at = mut.noLastClamp ? i + indexSampler(frameValues, mut) : Math.min(i + indexSampler(frameValues, mut) || 0, len - 1);
    const sampleFrameIdx = view[at];
    col[sampleFrameIdx] = value;
    out.push(sampleFrameIdx);
  }
  return { indices: out, count: out.length, col };
}

// dataSample.ts reset over the stage; null when the series is not sampled
function transcribe(sr, mut) {
  const st = mut.beforeFilter && sr.prefilter ? Object.assign({}, sr.stage, sr.prefilter) : sr.stage;
  if (!st) return null;
  const sampling = sr.samplingOption;
  const count = st.count;
  if (!(mut.count10 ? count >= 10 : count > 10) || !sampling) return null;
  const size = mut.sizeFinal && sr.finalSize != null ? sr.finalSize : num(st.size);
  const rate = mut.rateFloor ? Math.floor(count / size) : Math.round(count / size);
  if (!(isFinite(rate) && (mut.rateGE1 ? rate >= 1 : rate > 1))) return null;
  const col = st.column.map(num);
  if (sampling === 'lttb') return lttb(st.rawIndices, col, 1 / rate, mut);
  if (sampling === 'minmax') return minmax(st.rawIndices, col, 1 / rate, mut);
  const samplers = makeSamplers(mut);
  if (typeof sampling === 'string' && Object.prototype.hasOwnProperty.call(samplers, sampling)) {
    return downSample(st.rawIndices, col, 1 / rate, samplers[sampling], mut);
  }
  return null;
}

// ---------- data ----------
const r2 = v => Math.round(v * 100) / 100;
function wave(n, phase, shift) {
  const o = [];
  for (let i = 0; i < n; i++) o.push(r2(Math.sin(i * 0.7 + (phase || 0)) * 40 + Math.cos(i * 0.13) * 25 + 50 + (shift || 0)));
  return o;
}
function holes(arr, ranges) {
  const o = arr.slice();
  for (const [a, b] of ranges) for (let i = a; i <= b && i < o.length; i++) o[i] = null;
  return o;
}
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
const T0 = Date.UTC(2020, 0, 1);

// a grid whose plot is `size` wide (or tall) at left 80 / top 60
function grid(size, horizontal, extra) {
  const g = horizontal
    ? { left: 80, right: 80, top: 60, bottom: H - 60 - size, outerBoundsMode: 'none' }
    : { left: 80, right: W - 80 - size, top: 60, bottom: 60, outerBoundsMode: 'none' };
  return Object.assign(g, extra || {});
}
// a category-x line (or bar) chart
function catChart(n, size, series, extra) {
  return Object.assign({
    animation: false,
    tooltip: { trigger: 'axis', renderMode: 'richText' },
    grid: grid(size),
    xAxis: { type: 'category', data: cats(n) },
    yAxis: { type: 'value' },
    series,
  }, extra || {});
}
const line = (sampling, data, more) => Object.assign({ type: 'line', sampling, data }, more || {});

const CASES = [];
const add = (id, groups, note, option, more) => CASES.push(Object.assign({ id, groups, note, option }, more || {}));

// each mode on the same wave, rate 3 (300 rows on 100 px)
for (const m of ['lttb', 'minmax', 'average', 'sum', 'max', 'min', 'nearest']) {
  add('mode-' + m, ['mode'], m + ': 300 rows on 100 px, rate 3', catChart(300, 100, [line(m, wave(300))]));
}
// other rates: even, odd, large
add('lttb-r4', ['mode', 'rate'], 'lttb, 400 rows on 100 px: rate 4', catChart(400, 100, [line('lttb', wave(400, 1))]));
add('lttb-r5', ['mode', 'rate'], 'lttb, 500 rows on 100 px: rate 5', catChart(500, 100, [line('lttb', wave(500, 2))]));
add('lttb-r7-301', ['mode', 'rate'], 'lttb, 301 rows on 43 px: rate 7, a short last frame', catChart(301, 43, [line('lttb', wave(301, 3))]));
add('minmax-r4', ['mode', 'rate'], 'minmax, 402 rows on 100 px: rate 4, a short last frame', catChart(402, 100, [line('minmax', wave(402, 1))]));
add('average-r3-301', ['mode', 'rate'], 'average, 301 rows on 100 px: rate 3, a last frame of one row (the index clamp)', catChart(301, 100, [line('average', wave(301, 4))]));
add('max-r5-503', ['mode', 'rate'], 'max, 503 rows on 100 px: rate 5, a last frame of three', catChart(503, 100, [line('max', wave(503, 5))]));
add('nearest-r2', ['mode', 'rate'], 'nearest, 200 rows on 100 px: rate 2 (round(1/2) = 1: the second row of each pair)', catChart(200, 100, [line('nearest', wave(200, 6))]));
add('sum-r6', ['mode', 'rate'], 'sum, 600 rows on 100 px: rate 6 (round(3) = 3)', catChart(600, 100, [line('sum', wave(600, 7))]));
// the rate's edges and the count gate
add('rate-1.495', ['rate'], '299 rows on 200 px: 1.495 rounds to 1, not sampled', catChart(299, 200, [line('lttb', wave(299))]));
add('rate-1.5', ['rate'], '300 rows on 200 px: 1.5 rounds to 2, sampled', catChart(300, 200, [line('lttb', wave(300))]));
add('rate-1.5-avg', ['rate'], '300 rows on 200 px, average: rate 2', catChart(300, 200, [line('average', wave(300, 8))]));
add('rate-2.5', ['rate'], '250 rows on 100 px: 2.5 rounds to 3', catChart(250, 100, [line('minmax', wave(250, 9))]));
add('count-10', ['rate'], '10 rows on 2 px: rate 5, but count > 10 fails', catChart(10, 2, [line('lttb', wave(10))]));
add('count-11', ['rate'], '11 rows on 2 px: round(5.5) = 6, sampled', catChart(11, 2, [line('average', wave(11))]));
add('count-11-lttb', ['rate'], '11 rows on 2 px, lttb', catChart(11, 2, [line('lttb', wave(11, 1))]));
add('count-10-zoom', ['rate', 'zoom'], '40 rows, a dataZoom leaving 10 on 2 px: not sampled (the count is the filtered one)',
  catChart(40, 2, [line('average', wave(40))], { dataZoom: [{ type: 'inside', startValue: 5, endValue: 14 }] }));
// options that do not sample
add('opt-none', ['option'], "sampling: 'none'", catChart(300, 100, [line('none', wave(300))]));
add('opt-unknown', ['option'], "sampling: 'median' (no such sampler)", catChart(300, 100, [line('median', wave(300))]));
add('opt-true', ['option'], 'sampling: true (not a string, not a function)', catChart(300, 100, [line(true, wave(300))]));
add('opt-empty', ['option'], "sampling: '' (falsy)", catChart(300, 100, [line('', wave(300))]));
add('opt-scatter', ['option'], 'a scatter with sampling: no sampler is registered for scatter',
  catChart(300, 100, [{ type: 'scatter', sampling: 'average', data: wave(300) }]));
// NaN / null runs
const NANS = [[0, 2], [40, 48], [90, 90], [140, 200], [251, 252], [299, 299]];
for (const m of ['lttb', 'minmax', 'average', 'sum', 'max', 'min', 'nearest']) {
  add('nan-' + m, ['nan'], m + ' over null runs (the first rows, a whole frame and more, single holes, the last row)',
    catChart(300, 100, [line(m, holes(wave(300, 2), NANS))]));
}
add('nan-lttb-alt', ['nan'], 'lttb, every third row null, rate 3: a NaN in every frame',
  catChart(300, 100, [line('lttb', wave(300, 3).map((v, i) => (i % 3 === 1 ? null : v)))]));
add('nan-lttb-alt2', ['nan'], 'lttb, 300 rows, every odd row null, rate 2: two indices from every frame',
  catChart(300, 150, [line('lttb', wave(300, 3).map((v, i) => (i % 2 ? null : v)))]));
add('nan-minmax-first', ['nan'], 'minmax, the first row of every frame null (rate 4)',
  catChart(400, 100, [line('minmax', wave(400, 4).map((v, i) => (i % 4 === 0 ? null : v)))]));
add('nan-all', ['nan'], 'average over all null rows', catChart(60, 20, [line('average', holes(wave(60), [[0, 59]]))]));
add('inf-max', ['nan'], "max / min / sum with 'Infinity' and '-Infinity' cells",
  catChart(300, 100, [
    line('max', wave(300).map((v, i) => (i % 37 === 5 ? 'Infinity' : i % 41 === 7 ? '-Infinity' : v))),
    line('min', wave(300, 1).map((v, i) => (i % 37 === 5 ? 'Infinity' : i % 41 === 7 ? '-Infinity' : v))),
    line('sum', wave(300, 2).map((v, i) => (i % 53 === 5 ? 'Infinity' : v))),
  ]));
// all-equal and negative
for (const m of ['lttb', 'minmax', 'average', 'max']) {
  add('equal-' + m, ['equal'], m + ' over 200 equal values (rate 4)', catChart(200, 50, [line(m, Array(200).fill(5))]));
}
for (const m of ['lttb', 'minmax', 'sum']) {
  add('neg-' + m, ['negative'], m + ' over negative values', catChart(300, 100, [line(m, wave(300, 1, -120))]));
}
add('neg-mixed', ['negative'], 'average across zero', catChart(300, 100, [line('average', wave(300, 2, -50))]));
// dataZoom windows: sampling after the filter
add('zoom-lttb', ['zoom'], 'lttb after an inside dataZoom 20-70 % (filter) on 600 rows: 300 left, rate 3',
  catChart(600, 100, [line('lttb', wave(600))], { dataZoom: [{ type: 'inside', start: 20, end: 70 }] }));
add('zoom-average', ['zoom'], 'average after a slider dataZoom startValue 100 / endValue 399',
  catChart(600, 100, [line('average', wave(600, 1))], { dataZoom: [{ type: 'slider', startValue: 100, endValue: 399 }] }));
add('zoom-minmax', ['zoom'], 'minmax after a dataZoom 50-100 %', catChart(600, 100, [line('minmax', wave(600, 2))], { dataZoom: [{ type: 'inside', start: 50, end: 100 }] }));
add('zoom-lttb-nan', ['zoom', 'nan'], 'lttb after a dataZoom startValue 100: a whole null frame -- upstream keeps the VIEW index as a raw index',
  catChart(600, 100, [line('lttb', holes(wave(600, 3), [[100, 103], [160, 175], [250, 252]]))], { dataZoom: [{ type: 'inside', startValue: 100, endValue: 399 }] }));
add('zoom-empty-y', ['zoom', 'nan'], "lttb with a y dataZoom, filterMode 'empty': the values outside 30..80 become NaN",
  catChart(300, 100, [line('lttb', wave(300, 4))], { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'empty', startValue: 30, endValue: 80 }] }));
add('zoom-max', ['zoom'], 'max after a dataZoom 10-40 % on 1000 rows', catChart(1000, 100, [line('max', wave(1000, 5))], { dataZoom: [{ type: 'inside', start: 10, end: 40 }] }));
// stacks and areas
add('stack-lttb', ['stack'], 'two stacked lines, lttb on each (the original values are sampled, the stack is the unsampled one)',
  catChart(300, 100, [line('lttb', wave(300), { stack: 's' }), line('lttb', wave(300, 2), { stack: 's' })]));
add('stack-average', ['stack'], 'two stacked lines, average: the stack result is not averaged',
  catChart(300, 100, [line('average', wave(300), { stack: 's' }), line('average', wave(300, 2), { stack: 's' })]));
add('stack-area-minmax', ['stack', 'area'], 'two stacked areas, minmax and sum',
  catChart(400, 100, [line('minmax', wave(400), { stack: 's', areaStyle: {} }), line('sum', wave(400, 2), { stack: 's', areaStyle: {} })]));
add('stack-mixed', ['stack'], 'a sampled line stacked on an unsampled one',
  catChart(300, 100, [line('none', wave(300), { stack: 's' }), line('max', wave(300, 3), { stack: 's', areaStyle: {} })]));
add('area-average', ['area'], 'an area, average', catChart(300, 100, [line('average', wave(300, 1), { areaStyle: {} })]));
add('area-lttb-nan', ['area', 'nan'], 'an area, lttb over null runs', catChart(300, 100, [line('lttb', holes(wave(300, 2), NANS), { areaStyle: {} })]));
// time and value base axes
const timeData = (n, step, ph) => wave(n, ph).map((v, i) => [T0 + i * step, v]);
add('time-lttb', ['axis'], 'a time x axis, lttb', Object.assign(catChart(0, 100, [line('lttb', timeData(300, 3600e3))]), { xAxis: { type: 'time' } }));
add('time-average', ['axis'], 'a time x axis, average: the kept times are each frame\'s middle, the axis extent shrinks',
  Object.assign(catChart(0, 100, [line('average', timeData(300, 3600e3, 1))]), { xAxis: { type: 'time' } }));
add('value-lttb', ['axis'], 'value x and y: the base axis is x', Object.assign(catChart(0, 100, [line('lttb', wave(300).map((v, i) => [i * 2.5 - 100, v]))]), { xAxis: { type: 'value' } }));
add('value-nearest', ['axis'], 'value x and y, nearest', Object.assign(catChart(0, 100, [line('nearest', wave(300, 1).map((v, i) => [i * 0.75, v]))]), { xAxis: { type: 'value' } }));
add('value-min-unsorted', ['axis'], 'value x and y, min, x not in order', Object.assign(catChart(0, 100, [line('min', wave(300, 2).map((v, i) => [(i * 37) % 300, v]))]), { xAxis: { type: 'value' } }));
// horizontal lines: the base axis is y, the size is the grid height
function hChart(n, size, series, extra) {
  return Object.assign({
    animation: false,
    tooltip: { trigger: 'axis', renderMode: 'richText' },
    grid: grid(size, true),
    xAxis: { type: 'value' },
    yAxis: { type: 'category', data: cats(n) },
    series,
  }, extra || {});
}
add('horiz-lttb', ['horizontal'], 'yAxis category, lttb: 300 rows on a 100 px tall plot', hChart(300, 100, [line('lttb', wave(300))]));
add('horiz-average', ['horizontal'], 'yAxis category, average', hChart(300, 100, [line('average', wave(300, 1))]));
add('horiz-minmax-wide', ['horizontal'], 'yAxis category, minmax: 300 rows on 480 px tall: rate 1, not sampled; the grid width does not count',
  hChart(300, 480, [line('minmax', wave(300, 2))], { grid: { left: 700, right: 80, top: 60, bottom: 60, outerBoundsMode: 'none' } }));
// bars
add('bar-max', ['bar'], 'a bar series with sampling max (bars are sampled too)', catChart(300, 100, [{ type: 'bar', sampling: 'max', data: wave(300) }]));
add('bar-lttb-horiz', ['bar', 'horizontal'], 'a horizontal bar, lttb', hChart(300, 100, [{ type: 'bar', sampling: 'lttb', data: wave(300, 1) }]));
add('bar-default', ['bar', 'option'], 'a bar without sampling: no default', catChart(300, 100, [{ type: 'bar', data: wave(300, 2) }]));
// the size is the grid before the data processing
add('pre-layout', ['rate'], 'grid left 0 with outerBounds: the sampler sees the raw 100 px (rate 2); the final plot is narrower (rate 3 there)',
  catChart(200, 100, [line('lttb', wave(200).map(v => v * 1000))], { grid: { left: 0, right: 700, top: 60, bottom: 60, containLabel: false } }));
// symbols and labels
add('label-average', ['label'], 'average with every symbol and its label: the label prints the raw value at the kept row, placed at the averaged one',
  catChart(40, 20, [line('average', wave(40), { showAllSymbol: true, label: { show: true } })]));
add('label-lttb', ['label'], 'lttb with symbols and labels on a value base axis', Object.assign(catChart(0, 30, [line('lttb', wave(90, 1).map((v, i) => [i, v]), { label: { show: true } })]), { xAxis: { type: 'value' } }));
add('label-minmax-equal', ['label', 'equal'], 'minmax over equal values: every kept row twice, two symbols and two labels on one point',
  catChart(40, 20, [line('minmax', Array(40).fill(3), { showAllSymbol: true, label: { show: true } })]));
add('symbol-auto', ['label'], 'lttb, showAllSymbol auto on a category axis: the symbols that remain are the label-interval ones over the sampled rows',
  catChart(120, 60, [line('lttb', wave(120))]));
// the alternating-null lttb that overflows its index array: upstream throws
add('throws-alt-nan', ['nan'], 'lttb over 41 rows, every odd one null, on 20 px: rate 2 and 42 indices into an array of 41 -- upstream throws in the render',
  catChart(41, 20, [line('lttb', wave(41).map((v, i) => (i % 2 ? null : v)))]), { expectThrow: true });

// ---------- recording ----------
function hexPairs(arr) {
  const o = [];
  for (let i = 0; i + 1 < arr.length; i += 2) o.push([hex(arr[i]), hex(arr[i + 1])]);
  return o;
}

function run(c) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  capture = { series: [] };
  const shown = [];
  chart.on('showtip', e => shown.push(e));
  const rec = { id: c.id, groups: c.groups, note: c.note, width: W, height: H, option: clone(c.option), throws: null, series: [], axes: [], tips: [] };
  try {
    try {
      chart.setOption(clone(c.option));
      chart.renderToSVGString();
    } catch (e) {
      rec.throws = String(e.message);
    }
    const ecModel = chart.getModel();
    const cap = capture;
    capture = null;
    ecModel.eachRawSeries(s => {
      const si = s.seriesIndex;
      const cs = s.coordinateSystem;
      const cr = cap.series[si] || {};
      const data = s.getData();
      const sr = {
        index: si, type: s.subType, coordSys: cs ? cs.type : null,
        samplingOption: s.get('sampling') === undefined ? null : clone(s.get('sampling')),
        baseDim: null, valueDim: null, valueCol: null, rawCount: s.getRawData().count(),
        prefilter: null, stage: null, ran: null,
      };
      if (cs && cs.type === 'cartesian2d') {
        const base = cs.getBaseAxis();
        sr.baseDim = base.dim;
        sr.valueDim = cs.getOtherAxis(base).dim;
        sr.valueCol = String(data.mapDimension(sr.valueDim)).replace(/\0/g, '/');
      }
      if (cr.prefilter && c.option.dataZoom) sr.prefilter = { count: cr.prefilter.count, rawIndices: cr.prefilter.rawIndices };
      if (cr.stage) {
        const st = cr.stage;
        const size = Math.abs(st.baseExtent[1] - st.baseExtent[0]) * (st.dpr || 1);
        const rate = Math.round(st.count / size);
        sr.stage = {
          count: st.count, rawIndices: st.rawIndices, column: st.column.map(hex),
          baseExtent: st.baseExtent.map(hex), dpr: st.dpr, size: hex(size), sizeText: text(size),
          rate: hex(rate), rateText: text(rate),
        };
      }
      if (cr.ran) sr.ran = { method: cr.ran.method, rateArg: hex(cr.ran.rateArg) };
      if (rec.throws) {
        const store = data.getStore();
        sr.sampledStore = { count: store._count, indices: store._indices ? Array.from(store._indices) : null };
        rec.series.push(sr);
        return;
      }
      sr.count = data.count();
      sr.rawIndices = [];
      for (let i = 0; i < data.count(); i++) sr.rawIndices.push(data.getRawIndex(i));
      if (sr.valueDim) {
        const dim = data.mapDimension(sr.valueDim);
        sr.values = [];
        for (let i = 0; i < data.count(); i++) sr.values.push(hex(val(data.get(dim, i))));
      } else {
        sr.values = null;
      }
      sr.points = null;
      sr.stackedOn = null;
      sr.bars = null;
      sr.symbols = null;
      sr.labels = null;
      if (s.subType === 'line' && cs && cs.type === 'cartesian2d') {
        const pts = data.getLayout('points');
        sr.points = pts ? hexPairs(Array.from(pts)) : null;
        const view = chart.getViewOfSeriesModel(s);
        const poly = view && view._polygon;
        if (poly && poly.shape.stackedOnPoints) sr.stackedOn = hexPairs(Array.from(poly.shape.stackedOnPoints));
        sr.symbols = [];
        sr.labels = [];
        for (let i = 0; i < data.count(); i++) {
          const g = data.getItemGraphicEl(i);
          if (!g) continue;
          sr.symbols.push([i, hex(g.x), hex(g.y)]);
          const sp = g.childAt && g.childAt(0);
          const tc = sp && sp.getTextContent && sp.getTextContent();
          if (!tc || tc.ignore || tc.invisible || !tc.style.text) continue;
          const m = tc.transform;
          must(m && m[0] === 1 && m[1] === 0 && m[2] === 0 && m[3] === 1, c.id + ': a label with a rotation or a scale');
          const ds = sp._innerTextDefaultStyle || {};
          sr.labels.push([i, String(tc.style.text), hex(m[4]), hex(m[5]), tc.style.align || ds.align || null,
            tc.style.verticalAlign || ds.verticalAlign || null]);
        }
      }
      if (s.subType === 'bar' && cs && cs.type === 'cartesian2d') {
        sr.bars = [];
        for (let i = 0; i < data.count(); i++) {
          const l = data.getItemLayout(i);
          sr.bars.push(l ? { x: hex(l.x), y: hex(l.y), width: hex(l.width), height: hex(l.height) } : null);
        }
      }
      rec.series.push(sr);
    });
    if (rec.throws) return rec;
    for (const mainType of ['xAxis', 'yAxis']) {
      ecModel.eachComponent(mainType, m => {
        const ax = m.axis;
        const e = ax.scale.getExtent();
        const px = ax.getExtent();
        rec.axes.push({
          dim: ax.dim, index: m.componentIndex, type: ax.type,
          extent: [hex(e[0]), hex(e[1])], extentText: [text(e[0]), text(e[1])],
          pxSpanFinal: hex(Math.abs(px[1] - px[0])),
        });
      });
    }
    // pointer probes: at 10 %, 50 % and 87 % along the base axis, the middle of the other
    const gm = ecModel.getComponent('grid', 0);
    const rect = gm && gm.coordinateSystem.getRect();
    const s0 = ecModel.getSeriesByIndex(0);
    if (rect && s0 && s0.coordinateSystem && s0.coordinateSystem.type === 'cartesian2d' && c.option.tooltip) {
      const baseDim = s0.coordinateSystem.getBaseAxis().dim;
      for (const f of [0.1, 0.5, 0.87]) {
        const x = Math.round(baseDim === 'x' ? rect.x + rect.width * f : rect.x + rect.width / 2);
        const y = Math.round(baseDim === 'x' ? rect.y + rect.height / 2 : rect.y + rect.height * f);
        shown.length = 0;
        chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x, y });
        const tip = { x, y, shown: null };
        if (shown.length) {
          const ev = shown[shown.length - 1];
          const byAxis = (ev.dataByCoordSys && ev.dataByCoordSys[0] && ev.dataByCoordSys[0].dataByAxis) || [];
          tip.shown = byAxis.map(a => ({
            dim: a.axisDim, index: a.axisIndex, value: hex(Number(a.value)), valueText: text(Number(a.value)),
            rows: (a.seriesDataIndices || []).map(q => [q.seriesIndex, q.dataIndexInside, q.dataIndex]),
          }));
        }
        rec.tips.push(tip);
      }
    }
    return rec;
  } finally {
    capture = null;
    chart.dispose();
  }
}

// ---------- guards ----------
const GUARDS = [
  { id: 'G1', mutation: 'the rate floors instead of rounding', mut: { rateFloor: true }, named: ['rate-1.5', 'count-11'] },
  { id: 'G2', mutation: 'a rate of 1 samples', mut: { rateGE1: true }, named: ['horiz-minmax-wide'] },
  { id: 'G3', mutation: 'count >= 10 samples', mut: { count10: true }, named: ['count-10', 'count-10-zoom'] },
  { id: 'G4', mutation: 'lttb: the next frame stops before the last row (textbook lttb)', mut: { lttbClassicEnd: true }, named: ['lttb-r4', 'lttb-r5', 'zoom-lttb'] },
  { id: 'G5', mutation: 'lttb: the next frame\'s mean divides by its numbers only', mut: { lttbAvgNonNaN: true }, named: ['nan-lttb'] },
  { id: 'G6', mutation: 'lttb: a frame with no pick keeps getRawIndex(frameStart), not the view index', mut: { lttbRawFix: true }, named: ['zoom-lttb-nan'] },
  { id: 'G7', mutation: 'lttb: no first-NaN index appended', mut: { lttbNoNaN: true }, named: ['nan-lttb', 'nan-lttb-alt'] },
  { id: 'G8', mutation: 'lttb: a tie takes the later row', mut: { lttbTieLast: true }, named: ['equal-lttb'] },
  { id: 'G9', mutation: 'lttb: point A sits at i, not i - 1', mut: { lttbPointAX: true }, named: ['mode-lttb', 'lttb-r4'] },
  { id: 'G10', mutation: 'minmax: always min then max', mut: { minmaxAlwaysMinFirst: true }, named: ['mode-minmax'] },
  { id: 'G11', mutation: 'minmax: a NaN first row is passed over', mut: { minmaxSkipNaNStart: true }, named: ['nan-minmax-first', 'nan-minmax'] },
  { id: 'G12', mutation: 'average: NaN counted in the divisor', mut: { avgCountsNaN: true }, named: ['nan-average'] },
  { id: 'G13', mutation: 'sum: NaN not taken as 0', mut: { sumNaN: true }, named: ['nan-sum'] },
  { id: 'G14', mutation: 'max: an infinite maximum kept', mut: { maxKeepsInf: true }, named: ['inf-max'] },
  { id: 'G15', mutation: 'nearest: the frame\'s last value', mut: { nearestLast: true }, named: ['mode-nearest', 'nan-nearest'] },
  { id: 'G16', mutation: 'the kept row is floor(frame / 2)', mut: { indexFloor: true }, named: ['mode-average', 'max-r5-503'] },
  { id: 'G17', mutation: 'the kept row is not clamped to the last', mut: { noLastClamp: true }, named: ['average-r3-301'] },
  { id: 'G18', mutation: 'sampled before the dataZoom filter', mut: { beforeFilter: true }, named: ['zoom-lttb', 'zoom-average', 'zoom-minmax', 'count-10-zoom'] },
  { id: 'G19', mutation: 'the size is the final plot, not the grid before processing', mut: { sizeFinal: true }, named: ['pre-layout'] },
];

function seriesDiff(sr, mut) {
  const t = transcribe(sr, mut);
  const wantCount = t ? t.count : sr.stage ? sr.stage.count : null;
  const recCount = sr.throws ? sr.sampledStore.count : sr.count;
  if (sr.stage == null) return [];
  if (wantCount !== recCount) return ['count ' + recCount + ' upstream, ' + wantCount + ' transcribed'];
  if (sr.throws) {
    const want = t ? t.indices : sr.stage.rawIndices;
    if (JSON.stringify(want) !== JSON.stringify(sr.sampledStore.indices)) return ['indices'];
    return [];
  }
  const ri = t ? t.indices : sr.stage.rawIndices;
  for (let i = 0; i < sr.count; i++) if (ri[i] !== sr.rawIndices[i]) return ['rawIndices[' + i + '] ' + sr.rawIndices[i] + ' upstream, ' + ri[i] + ' transcribed'];
  const col = t ? t.col : sr.stage.column.map(num);
  for (let i = 0; i < sr.count; i++) {
    if (hex(val(col[sr.rawIndices[i]])) !== sr.values[i]) return ['values[' + i + ']'];
  }
  return [];
}

function generate() {
  const cases = CASES.map(run);
  // the final plot size, for G19 only (outside the fixture)
  for (const c of cases) {
    for (const sr of c.series) {
      if (!sr.baseDim) continue;
      const ax = c.axes.find(a => a.dim === sr.baseDim && a.index === 0);
      Object.defineProperty(sr, 'finalSize', { value: ax ? num(ax.pxSpanFinal) : null, enumerable: false });
      Object.defineProperty(sr, 'throws', { value: c.throws, enumerable: false, configurable: true });
    }
  }
  return {
    source: 'ECharts ' + echarts.version + ' (' + path.basename(DIST) + ')',
    W, H, seed: SEED,
    api: {
      gate: "dataSample.ts reset: count > 10 && coordSys.type === 'cartesian2d' && sampling (truthy)",
      size: 'Math.abs(baseAxis.getExtent()[1] - [0]) * (api.getDevicePixelRatio() || 1), read in the processing stage (the grid as Grid.create sized it, before containLabel / outerBounds)',
      rate: 'Math.round(count / size); sampled when isFinite(rate) && rate > 1; the methods get 1 / rate and frameSize = Math.floor(1 / (1 / rate))',
    },
    notes: [
      'The sampler runs at PRIORITY.PROCESSOR.STATISTIC (5000), after the stack (900) and the dataZoom filter (1000): it sees the filtered rows, and a stacked series is stacked over the unsampled values.',
      'lttb and minmax keep values; average / sum / max / min / nearest write the frame value into the row at frame start + Math.round(frame / 2) (clamped to the last row) of a CLONED value column -- getRawData() keeps the parsed values, and only the value column (data.mapDimension(valueAxis.dim), the original one for a stacked series) is touched.',
      'lttb: a frame where no row could be scored (all NaN, or point A is NaN) keeps nextRawIndex = frameStart, a VIEW index used as a raw index (zoom-lttb-nan).',
      'lttb: its index array has min((ceil(len / frame) + 2) * 2, len) slots; when more are written (alternating nulls, rate 2, an odd count) the extra index is dropped while _count counts it, and the render throws (throws-alt-nan).',
      'Labels print the raw item (getRawDataItem), not the sampled value; the position is the sampled one (label-average).',
    ],
    cases,
  };
}

function check(g) {
  const out = g;
  const byId = {};
  for (const c of out.cases) byId[c.id] = c;
  for (const c of out.cases) {
    must(!!c.throws === !!CASES.find(k => k.id === c.id).expectThrow, c.id + ': threw ' + c.throws);
    for (const sr of c.series) {
      const d = seriesDiff(sr, {});
      must(!d.length, c.id + '/' + sr.index + ': ' + d.join('; '));
      const t = transcribe(sr, {});
      must(!!t === !!sr.ran, c.id + '/' + sr.index + ': sampled ' + !!sr.ran + ' upstream, ' + !!t + ' transcribed');
      if (sr.stage) must(sr.stage.dpr === 1, c.id + ': dpr ' + sr.stage.dpr);
    }
  }
  // anchors
  must(byId['rate-1.495'].series[0].ran === null && byId['rate-1.5'].series[0].ran !== null, 'rate edges');
  must(byId['count-10'].series[0].ran === null && byId['count-11'].series[0].ran !== null, 'count gate');
  must(byId['opt-scatter'].series[0].stage === null, 'scatter staged');
  must(byId['bar-max'].series[0].ran && byId['bar-max'].series[0].ran.method === 'downSample', 'bar sampled');
  must(byId['horiz-lttb'].series[0].baseDim === 'y', 'horizontal base');
  must(byId['pre-layout'].series[0].stage.sizeText === '100' && num(byId['pre-layout'].axes[0].pxSpanFinal) < 100, 'pre-layout: the final plot did not shrink');
  const zl = byId['zoom-lttb-nan'].series[0];
  must(zl.rawIndices.some(r => r < 100), 'zoom-lttb-nan: no view index taken as raw');
  const me = byId['equal-minmax'].series[0];
  must(me.rawIndices[0] === me.rawIndices[1], 'equal-minmax: no duplicate');
  must(byId['label-average'].series[0].labels.length > 0, 'label-average: no labels');
  must(byId['throws-alt-nan'].series[0].sampledStore.count === 42, 'throws-alt-nan: count');
  return GUARDS.map(gd => {
    const changed = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        let d;
        try {
          d = seriesDiff(sr, gd.mut);
        } catch (e) {
          d = ['threw ' + e.message];
        }
        if (d.length) any = true;
      }
      if (any) changed.push(c.id);
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)) };
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

let g1;
let json1;
let json2;
try {
  g1 = generate();
  g1.guards = check(g1);
  json1 = fmt(g1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(g1), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.guards = check(g2);
  json2 = fmt(g2, '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = g1.guards.filter(gd => !gd.ok);
g1.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nSeries = g1.cases.reduce((n, c) => n + c.series.length, 0);
const nSampled = g1.cases.reduce((n, c) => n + c.series.filter(s => s.ran).length, 0);
console.log(g1.cases.length + ' cases (' + nSeries + ' series, ' + nSampled + ' sampled); ' + (g1.guards.length - bad.length) + '/' + g1.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
