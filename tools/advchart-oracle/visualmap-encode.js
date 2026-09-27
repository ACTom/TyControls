// Upstream's own answers for the visualMap B1 batch (wf54/audit54.md section 1
// recipes 1.1-1.6, section 2 B1 cases K1..K10): the continuous visualMap's
// subtype, extent, range and value state, the completed `target`, the order the
// visuals are applied in (V8's Array.prototype.sort with upstream's
// inconsistent comparator), the per-row colour and opacity the encoder writes,
// the per-series visualMeta colour stops and the line series' gradient built
// from them, and the tooltip marker colour of a line row.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models, the data stores
// and the views directly -- never the SVG text. Every chart is disposed in a
// finally.
//
//   node tools/advchart-oracle/visualmap-encode.js
//
// writes tests/fixtures/advchart-visualmap-encode.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase; NaN is written 7ff8000000000000 (compare NaN as NaN).
//            Every hex field has a readable twin: xText beside x, valuesText
//            beside values, ... (String(v), '-0' for negative zero).
//   colour   {css, r, g, b, a, aText, undef}: css is the string upstream
//            produced or was given (null when undefined); r, g, b are the
//            integers and a the hex alpha of zrender's parse(css)
//            (echarts.color.parse); undef is true when upstream's value was
//            undefined (then r = g = b = 0, a = 0, css null) -- a NaN datum's
//            fill, or inRange {color: null}.
//   paint    a fill or stroke: {kind: 'color', color: colour}, or
//            {kind: 'gradient', type ('linear'), global (boolean), x, y, x2, y2
//            (hex) + xText.., stops: [{offset (hex), offsetText, color: colour}]}
//
// Top level
//   source        ECharts / zrender versions, node and V8
//   W, H          800, 600 -- the canvas of every chart case
//   seed          the xorshift32 seed Math.random runs on
//   api           the upstream calls each kind of value was read with (text)
//   gradientColor [colour, colour]: ecModel.get('gradientColor'), the default
//                 inRange ramp = [modifyHSL(theme[0] '#5070dd', l 0.9), '#5070dd']
//
// subtype[] (K1)   the type defaulter, installCommon.ts:36-51, only when `type`
//                  is absent
//   id, note, option  the whole option fed (visualMap + series: [])
//   subType        'continuous' | 'piecewise' (the model's subType)
//
// charts[] (K2-K7, K9, K10)  one per chart case
//   id, groups (the K cases it serves), note, width, height
//   option         the option exactly as fed to setOption (JSON; the gallery
//                  files are fed verbatim)
//   visualMaps[]   in component order:
//     index, subType
//     extent       [hex, hex] + extentText: asc([min, max])
//     range        [hex, hex] + rangeText: option.range after _resetRange (swap,
//                  clamp into the extent), rangeAuto true when it defaulted to
//                  the extent
//     unboundedRange  the option as written (true/false) or null (unset: true)
//     target       vm.option.target after completeVisualOption, as JSON, KEY
//                  ORDER AS UPSTREAM HOLDS IT (the order is what the sort sees)
//     order        {inRange: [...], outOfRange: [...]}: prepareVisualTypes of
//                  targetVisuals[state] -- the order the encoder applies them in
//     targets      the series indices it targets (isTargetSeries)
//   series[]       every series:
//     index, type, drawType ('fill' | 'stroke'), color (colour: the series style
//     colour = style[drawType], the base the encoder starts from), opacity (hex
//     or null: the series style opacity)
//     targetedBy   visualMap indices, component order
//     dims[]       {vm, dimIndex, dimName}: getDataDimensionIndex(data)
//     rows[]       one per data index:
//       i
//       skip       true when the raw item is {visualMap: false}
//       values[]   {vm, value (hex), valueText, state}: store.get(dim, i) as
//                  the encoder reads it (visualSolution.ts:237-241) and
//                  vm.getValueState(value)
//       color      colour: data.getItemVisual(i, 'style')[drawType] after
//                  setOption (stage 4000 visualMap, then 4500 data itemStyle)
//       opacity    hex or null (+ opacityText): getItemVisual(i, 'style').opacity
//     visualMeta[] data.getVisual('visualMeta'), one per targeting visualMap:
//       vm, dimension, coordDim ('x' | 'y' | null)
//       outerColors  [colour, colour]
//       stops[]    {value (hex), valueText, color (colour)[, coord (hex),
//                  coordText]} -- coord = axis.toGlobalCoord(axis.dataToCoord(
//                  value)) on a cartesian line series whose meta dimension is x/y
//     line series only:
//       grid       {x, y, width, height} hex + text: the cartesian's grid rect
//       lineStyleColorWritten  boolean: series.lineStyle.color written
//       polyline   paint: view._polyline.style.stroke
//       area       paint or null: view._polygon.style.fill (areaStyle only)
//     tooltipMarker (LG only)  {row, color (colour)}: the markerColor in
//                  series.formatTooltip(row, true) -- the fragment the axis
//                  tooltip is built from (tooltipMarkup.ts:488-495)
//     alt (K7 only) {what, values: [hex], valuesText}: the value a wrong port
//                  would read instead (the guard shows its colours differ)
//
// stopValues[] (K8)  getColorStopValues on the extent (ContinuousModel.ts:
//   336-361, accumulated `value += step`): chart, series, vm, extent (hex),
//   extentText, count, values [hex], valuesText -- read back from the visualMeta stops
//   (full range, so stops = the values)
//
// sortCases[] (K5)  {in: [keys in object order], out: [the order]}: out is
//   in.slice().sort(cmp) with upstream's comparator (VisualMapping.ts:431-456)
//   `(t2 === 'color' && t1 !== 'color' && t1.indexOf('color') === 0) ? 1 : -1`
//   and equals VisualMapping.prepareVisualTypes of an object with those keys
//
// parse[]           zrender parse of CSS colour strings:
//   {in, ok: true, r, g, b, a (hex), aText} or {in, ok: false} (parse gave
//   undefined; the encoder then uses [0,0,0,1])
//
// fastLerp[]        zrender fastLerp(n, stops) directly (color.ts:402-438):
//   {id, note, n (hex), nText, colors: [css], result: colour (css is null: the
//   tuple, not a string)}; a stop that does not parse is [0,0,0,1] as
//   setVisualToOption makes it
//
// guards[]          one per mutation of the audit's B1 table:
//   id, mutation, named (the cases that must turn red), changed (the cases on
//   which the mutated transcription below gives a different answer from the
//   recorded upstream one), ok = every named case changed
//
// ---------------------------------------------------------------------------
// Self-checks (any failure: nothing is written, exit 1):
//   - the transcription (subtype rule, asc/_resetRange/getValueState,
//     zrUtil.merge + completeSingle + completeInactive, the V8 TimSort model of
//     prepareVisualTypes, linearMap + fastLerp + modifyAlpha, the per-row
//     pipeline with visualMap:false and the 4500 itemStyle override,
//     getColorStopValues + getVisualMeta, LineView getVisualGradient with
//     clipColorStops and zrender lerp) gives every recorded value bit for bit;
//   - the transcribed modifyHSL gives gradientColor[0];
//   - the tooltip marker is the row's item colour;
//   - the V8 model and prepareVisualTypes agree with Array.prototype.sort on
//     every sort case; the parse transcription (rgb/rgba/hsl/hsla/#hex) gives
//     every parse row; the recorded fastLerp rows are the transcription's;
//   - coverage: every audit-named input is present (the 7 subtype shapes, the
//     sort lists, the parse strings, every colour string the chart options
//     hold), counts at least as stated;
//   - every guard is ok;
//   - two generations in the process give the same bytes.
// Outside the script: run twice and cmp.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visualmap-encode.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
const C = echarts.color;

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

// ---------- number and colour records ----------
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

const UNDEF_COLOUR = { css: null, r: 0, g: 0, b: 0, a: hex(0), aText: '0', undef: true };
function colRec(c) {
  if (c == null) return Object.assign({}, UNDEF_COLOUR);
  // a gradient series colour (K6c): not a colour zrender parses; every row's
  // mapped colour replaces it
  if (typeof c === 'object' && Array.isArray(c.colorStops)) return Object.assign({}, UNDEF_COLOUR, { gradient: true });
  must(typeof c === 'string', 'a colour that is not a string: ' + JSON.stringify(c));
  const p = C.parse(c);
  must(p, 'an upstream colour that does not parse: ' + c);
  must([0, 1, 2].every(k => Number.isInteger(p[k])), 'a non-integer channel in ' + c);
  return { css: c, r: p[0], g: p[1], b: p[2], a: hex(p[3]), aText: text(p[3]), undef: false };
}
function tupRec(t) {
  if (t == null) return Object.assign({}, UNDEF_COLOUR);
  return { css: null, r: t[0], g: t[1], b: t[2], a: hex(t[3]), aText: text(t[3]), undef: false };
}
const tupleOf = rec => (rec.undef ? undefined : [rec.r, rec.g, rec.b, num(rec.a)]);
function sameColour(rec, t) {
  if (t == null) return rec.undef;
  return !rec.undef && rec.r === t[0] && rec.g === t[1] && rec.b === t[2] && rec.a === hex(t[3]);
}
function paintRec(p) {
  if (p && typeof p === 'object') {
    must(p.type === 'linear' && Array.isArray(p.colorStops), 'an unexpected paint ' + JSON.stringify(p).slice(0, 80));
    return {
      kind: 'gradient', type: p.type, global: !!p.global,
      x: hex(p.x), y: hex(p.y), x2: hex(p.x2), y2: hex(p.y2),
      xText: text(p.x), yText: text(p.y), x2Text: text(p.x2), y2Text: text(p.y2),
      stops: p.colorStops.map(s => ({ offset: hex(s.offset), offsetText: text(s.offset), color: colRec(s.color) })),
    };
  }
  return { kind: 'color', color: colRec(p) };
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

// ---------- the transcription (with the audit's mutations as switches) ----------

// installCommon.ts:36-51
function subTypeOf(o, mut) {
  if (o.type) return o.type;
  const splitOrPieces = o.pieces
    ? (mut.piecesNotNil ? true : o.pieces.length > 0)
    : o.splitNumber > 0;
  const cats = mut.dropCategories ? false : o.categories;
  const calc = mut.dropCalculable ? false : o.calculable;
  return !cats && (!splitOrPieces || calc) ? 'continuous' : 'piecewise';
}

// util/number.ts:67-120, verbatim
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

function bankers(x) {
  const f = Math.floor(x);
  const d = x - f;
  if (d > 0.5) return f + 1;
  if (d < 0.5) return f;
  return f % 2 === 0 ? f : f + 1;
}
// color.ts:82-94
function clampByte(i, mut) {
  i = mut.bankers ? bankers(i) : Math.round(i);
  return i < 0 ? 0 : i > 255 ? 255 : i;
}
const clampFloat = f => (f < 0 ? 0 : f > 1 ? 1 : f);
const lerpNumber = (a, b, p) => a + (b - a) * p;

// color.ts:402-438; throws when a mutated index leaves the stops
function fastLerp(n, colors, mut) {
  if (!(colors && colors.length) || !(n >= 0 && n <= 1)) return undefined;
  const value = n * (colors.length - 1);
  const l = Math.floor(value);
  const r = mut.rightPlusOne ? l + 1 : Math.ceil(value);
  const lc = colors[l];
  const rc = colors[r];
  if (!lc || !rc) throw new Error('fastLerp index ' + l + '/' + r + ' outside ' + colors.length + ' stops');
  const dv = value - l;
  let a = clampFloat(lerpNumber(lc[3], rc[3], dv));
  if (mut.alpha8) a = Math.round(a * 255) / 255;
  return [clampByte(lerpNumber(lc[0], rc[0], dv), mut), clampByte(lerpNumber(lc[1], rc[1], dv), mut),
    clampByte(lerpNumber(lc[2], rc[2], dv), mut), a];
}

// color.ts:456-500 on tuples (LineView's clip lerp)
function lerpTuple(p, c0, c1) {
  if (!(p >= 0 && p <= 1)) return undefined;
  return fastLerp(p, [c0, c1], {});
}

// color.ts:305-365, 281-303, 507-528
function hueToRgb(m1, m2, h) {
  if (h < 0) h += 1;
  else if (h > 1) h -= 1;
  if (h * 6 < 1) return m1 + (m2 - m1) * h * 6;
  if (h * 2 < 1) return m2;
  if (h * 3 < 2) return m1 + (m2 - m1) * (2 / 3 - h) * 6;
  return m1;
}
function hslToRgbUnrounded(hDeg, s, l) {
  const h = (((hDeg % 360) + 360) % 360) / 360;
  const m2 = l <= 0.5 ? l * (s + 1) : l + s - l * s;
  const m1 = l * 2 - m2;
  return [hueToRgb(m1, m2, h + 1 / 3) * 255, hueToRgb(m1, m2, h) * 255, hueToRgb(m1, m2, h - 1 / 3) * 255];
}
function rgbaToHsla(rgba) {
  const R = rgba[0] / 255;
  const G = rgba[1] / 255;
  const B = rgba[2] / 255;
  const vMin = Math.min(R, G, B);
  const vMax = Math.max(R, G, B);
  const delta = vMax - vMin;
  const L = (vMax + vMin) / 2;
  let Hh;
  let S;
  if (delta === 0) {
    Hh = 0;
    S = 0;
  } else {
    S = L < 0.5 ? delta / (vMax + vMin) : delta / (2 - vMax - vMin);
    const dR = (((vMax - R) / 6) + (delta / 2)) / delta;
    const dG = (((vMax - G) / 6) + (delta / 2)) / delta;
    const dB = (((vMax - B) / 6) + (delta / 2)) / delta;
    if (R === vMax) Hh = dB - dG;
    else if (G === vMax) Hh = (1 / 3) + dR - dB;
    else if (B === vMax) Hh = (2 / 3) + dG - dR;
    if (Hh < 0) Hh += 1;
    if (Hh > 1) Hh -= 1;
  }
  return [Hh * 360, S, L, rgba[3]];
}
function modifyLightness(t, l) {
  const hsla = rgbaToHsla(t);
  hsla[2] = clampFloat(parseFloat(String(l)));
  const ch = hslToRgbUnrounded(hsla[0], hsla[1], hsla[2]);
  return [clampByte(ch[0], {}), clampByte(ch[1], {}), clampByte(ch[2], {}), hsla[3]];
}
// color.ts:530-541
const modifyAlpha = (t, alpha) => (t == null ? undefined : [t[0], t[1], t[2], clampFloat(alpha)]);

// the parse grammar for the functional and hex forms (color.ts:162-279), JS rounding
function parseCssInt(str, mut) {
  if (str.length && str.charAt(str.length - 1) === '%') return clampByte(parseFloat(str) / 100 * 255, mut);
  return clampByte(parseInt(str, 10), mut);
}
function parseCssFloat(str) {
  if (str.length && str.charAt(str.length - 1) === '%') return clampFloat(parseFloat(str) / 100);
  return clampFloat(parseFloat(str));
}
function parseTranscribed(css, mut) {
  const str = css.replace(/ /g, '').toLowerCase();
  if (str.charAt(0) === '#') {
    if (str.length === 4 || str.length === 5) {
      const iv = parseInt(str.slice(1, 4), 16);
      if (!(iv >= 0 && iv <= 0xfff)) return undefined;
      return [((iv & 0xf00) >> 4) | ((iv & 0xf00) >> 8), (iv & 0xf0) | ((iv & 0xf0) >> 4), (iv & 0xf) | ((iv & 0xf) << 4),
        str.length === 5 ? parseInt(str.slice(4), 16) / 0xf : 1];
    }
    if (str.length === 7 || str.length === 9) {
      const iv = parseInt(str.slice(1, 7), 16);
      if (!(iv >= 0 && iv <= 0xffffff)) return undefined;
      return [(iv & 0xff0000) >> 16, (iv & 0xff00) >> 8, iv & 0xff, str.length === 9 ? parseInt(str.slice(7), 16) / 0xff : 1];
    }
    return undefined;
  }
  const op = str.indexOf('(');
  const ep = str.indexOf(')');
  if (op === -1 || ep + 1 !== str.length) return 'keyword';
  const fname = str.substr(0, op);
  const params = str.substr(op + 1, ep - (op + 1)).split(',');
  if (fname === 'rgba' || fname === 'rgb') {
    let alpha = 1;
    if (fname === 'rgba') {
      if (params.length !== 4) return params.length === 3 ? [+params[0], +params[1], +params[2], 1] : [0, 0, 0, 1];
      alpha = parseCssFloat(params.pop());
    }
    if (params.length < 3) return undefined;
    return [parseCssInt(params[0], mut), parseCssInt(params[1], mut), parseCssInt(params[2], mut),
      params.length === 3 ? alpha : parseCssFloat(params[3])];
  }
  if (fname === 'hsl' || fname === 'hsla') {
    if (params.length !== (fname === 'hsl' ? 3 : 4)) return undefined;
    const ch = hslToRgbUnrounded(parseFloat(params[0]), parseCssFloat(params[1]), parseCssFloat(params[2]));
    return [clampByte(ch[0], mut), clampByte(ch[1], mut), clampByte(ch[2], mut), fname === 'hsla' ? parseCssFloat(params[3]) : 1];
  }
  return undefined;
}

// prepareVisualTypes: the comparator and V8's TimSort for n < 64 (CountAndMakeRun
// then BinaryInsertionSort), wf54/probes/p3-sort.js:13-45
const cmp = (t1, t2) => ((t2 === 'color' && t1 !== 'color' && t1.indexOf('color') === 0) ? 1 : -1);
function v8Sort(input) {
  const a = input.slice();
  const n = a.length;
  if (n < 2) return a;
  let runLength = 2;
  const isDescending = cmp(a[1], a[0]) < 0;
  let previous = a[1];
  for (let idx = 2; idx < n; idx++) {
    const order = cmp(a[idx], previous);
    if (isDescending ? order >= 0 : order < 0) break;
    previous = a[idx];
    runLength++;
  }
  if (isDescending) {
    for (let lo = 0, hi = runLength - 1; lo < hi; lo++, hi--) { const t = a[lo]; a[lo] = a[hi]; a[hi] = t; }
  }
  for (let start = runLength; start < n; start++) {
    const pivot = a[start];
    let left = 0;
    let right = start;
    while (left < right) {
      const mid = left + ((right - left) >> 1);
      if (cmp(pivot, a[mid]) < 0) right = mid; else left = mid + 1;
    }
    for (let p = start; p > left; p--) a[p] = a[p - 1];
    a[left] = pivot;
  }
  return a;
}
function linearInsertion(input) {
  const a = input.slice();
  for (let i = 1; i < a.length; i++) {
    const p = a[i];
    let j = i;
    while (j > 0 && cmp(p, a[j - 1]) < 0) { a[j] = a[j - 1]; j--; }
    a[j] = p;
  }
  return a;
}
// V8's run, then a LINEAR scan from the right instead of the binary search:
// the two agree on every list shorter than eight types
function runThenLinear(input) {
  const a = input.slice();
  const n = a.length;
  if (n < 2) return a;
  let runLength = 2;
  const isDescending = cmp(a[1], a[0]) < 0;
  let previous = a[1];
  for (let idx = 2; idx < n; idx++) {
    const order = cmp(a[idx], previous);
    if (isDescending ? order >= 0 : order < 0) break;
    previous = a[idx];
    runLength++;
  }
  if (isDescending) {
    for (let lo = 0, hi = runLength - 1; lo < hi; lo++, hi--) { const t = a[lo]; a[lo] = a[hi]; a[hi] = t; }
  }
  for (let start = runLength; start < n; start++) {
    const pivot = a[start];
    let left = start;
    while (left > 0 && cmp(pivot, a[left - 1]) < 0) left--;
    for (let p = start; p > left; p--) a[p] = a[p - 1];
    a[left] = pivot;
  }
  return a;
}
function binaryInsertionNoRun(input) {
  const a = input.slice();
  for (let s = 1; s < a.length; s++) {
    const p = a[s];
    let l = 0;
    let r = s;
    while (l < r) {
      const m = l + ((r - l) >> 1);
      if (cmp(p, a[m]) < 0) r = m; else l = m + 1;
    }
    a.splice(s, 1);
    a.splice(l, 0, p);
  }
  return a;
}
const SORTS = {
  v8: v8Sort,
  identity: a => a.slice(),
  reverse: a => a.slice().reverse(),
  linearInsertion,
  binaryInsertionNoRun,
  runThenLinear,
};
const sortTypes = (keys, mut) => SORTS[mut.sort || 'v8'](keys);

const VALID_TYPES = ['color', 'colorHue', 'colorSaturation', 'colorLightness', 'colorAlpha', 'opacity', 'symbol',
  'symbolSize', 'liftZ', 'decal'];
// visualDefault.ts:47-85, the inactive column (non-category)
const INACTIVE = { color: ['rgba(0,0,0,0)'], colorHue: [0, 0], colorSaturation: [0, 0], colorLightness: [0, 0],
  colorAlpha: [0, 0], opacity: [0, 0], symbol: ['none'], symbolSize: [0, 0] };

// zrender util.ts:135-171 (overwrite false)
function zrMerge(target, source) {
  const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v);
  for (const key in source) {
    if (!hasOwn(source, key)) continue;
    if (plain(source[key]) && plain(target[key])) zrMerge(target[key], source[key]);
    else if (!(key in target)) target[key] = clone(source[key]);
  }
  return target;
}

// VisualMapModel.ts:484-562, the target side
function completeTarget(opt, gradientColor, mut) {
  const base = { inRange: opt.inRange, outOfRange: opt.outOfRange };
  const target = opt.target ? clone(opt.target) : {};
  if (mut.shallowMerge) {
    for (const k of ['inRange', 'outOfRange']) if (!(k in target)) target[k] = clone(base[k]);
  } else {
    zrMerge(target, base);
  }
  if (Array.isArray(opt.color) && !target.inRange) {
    target.inRange = { color: mut.noReverse ? opt.color.slice() : opt.color.slice().reverse() };
  }
  target.inRange = target.inRange || { color: gradientColor.slice() };
  if (mut.nullAbsent && target.inRange.color === null) delete target.inRange.color;
  const exist = target.inRange;
  if (exist && !target.outOfRange) {
    const absent = target.outOfRange = {};
    for (const type of Object.keys(exist)) {
      if (!VALID_TYPES.includes(type)) continue;
      const defa = clone(INACTIVE[type]);
      if (defa != null) {
        absent[type] = defa;
        if (type === 'color' && !mut.noOpacityDefault && !hasOwn(absent, 'opacity') && !hasOwn(absent, 'colorAlpha')) {
          absent.opacity = [0, 0];
        }
      }
    }
  }
  return target;
}

// VisualMapping.ts:594-618, 693-705
function visualArray(visual, type) {
  let arr = [];
  if (visual !== null && typeof visual === 'object') arr = Object.keys(visual).map(k => visual[k]);
  else if (visual != null) arr = [visual];
  if (arr.length === 1 && type !== 'color' && type !== 'symbol') arr[1] = arr[0];
  return arr;
}

// the model: extent, range, state (VisualMapModel.ts:413-423, ContinuousModel.ts:143-160, 207-216)
function modelOf(opt, gradientColor, mut) {
  const min = opt.min != null ? opt.min : 0;
  const max = opt.max != null ? opt.max : 200;
  const extent = mut.noAsc ? [min, max] : [Math.min(min, max), Math.max(min, max)];
  let range;
  let rangeAuto = false;
  if (!opt.range || opt.range.auto) {
    range = extent.slice();
    rangeAuto = true;
  } else {
    range = opt.range.slice();
    if (!mut.noSwap && range[0] > range[1]) range.reverse();
    if (!mut.noClamp) {
      range[0] = Math.max(range[0], extent[0]);
      range[1] = Math.min(range[1], extent[1]);
    }
  }
  const ub = opt.unboundedRange != null ? opt.unboundedRange : !mut.ubFalse;
  const target = completeTarget(opt, gradientColor, mut);
  const state = v => ((((ub && range[0] <= extent[0]) || range[0] <= v) && ((ub && range[1] >= extent[1]) || v <= range[1]))
    ? 'inRange' : 'outOfRange');
  const parsed = {};
  for (const st of ['inRange', 'outOfRange']) {
    parsed[st] = {};
    const m = target[st] || {};
    for (const type of Object.keys(m)) {
      if (!VALID_TYPES.includes(type)) continue;
      must(type === 'color' || type === 'opacity', 'the transcription maps color and opacity only, not ' + type);
      const arr = visualArray(m[type], type);
      parsed[st][type] = type === 'color' ? arr.map(c => C.parse(c) || [0, 0, 0, 1]) : arr;
    }
  }
  const normalize = v => ((mut.nanLinear && Number.isNaN(v)) ? 0 : linearMap(v, extent, [0, 1], true));
  // one visual type on a running {color, opacity}; asAlpha = opacity through __alphaForOpacity
  function apply(v, st, type, run, asAlpha) {
    const vis = parsed[st][type];
    const n = normalize(v);
    if (type === 'color') run.color = fastLerp(n, vis, mut);
    else if (asAlpha) run.color = modifyAlpha(run.color, linearMap(n, [0, 1], vis, true));
    else run.opacity = mut.multiplyOpacity ? (run.opacity == null ? 1 : run.opacity) * linearMap(n, [0, 1], vis, true)
      : linearMap(n, [0, 1], vis, true);
  }
  const order = st => sortTypes(Object.keys(target[st] || {}).filter(t => VALID_TYPES.includes(t)), mut);
  return { extent, range, rangeAuto, ub, target, state, apply, order };
}

// ContinuousModel.ts:336-361
function stopValues(ext, mut) {
  if (ext[0] === ext[1]) return ext.slice();
  const count = 200;
  const step = (ext[1] - ext[0]) / count;
  let value = ext[0];
  const out = [];
  for (let i = 0; (mut.loop200 ? i < count : i <= count) && value < ext[1]; i++) {
    out.push(mut.multiplied ? ext[0] + step * i : value);
    value += step;
  }
  out.push(ext[1]);
  return out;
}
// ContinuousModel.ts:245-298 with visualEncoding.ts:86-115 as getColorVisual
function metaOf(model, seriesColor, mut) {
  const colourAt = (v, st) => {
    const run = { color: seriesColor };
    for (const type of model.order(st)) model.apply(v, st, type, run, type === 'opacity');
    return run.color;
  };
  const oVals = stopValues(model.extent, mut);
  const iVals = stopValues(model.range.slice(), mut);
  const stops = [];
  const setStop = (value, st) => stops.push({ value, color: colourAt(value, st) });
  let iIdx = 0;
  let oIdx = 0;
  for (; oIdx < oVals.length && (!iVals.length || oVals[oIdx] <= iVals[0]); oIdx++) {
    if (oVals[oIdx] < iVals[iIdx]) setStop(oVals[oIdx], 'outOfRange');
  }
  for (let first = 1; iIdx < iVals.length; iIdx++, first = 0) {
    if (first && stops.length) setStop(iVals[iIdx], 'outOfRange');
    setStop(iVals[iIdx], 'inRange');
  }
  for (let first = 1; oIdx < oVals.length; oIdx++) {
    if (!iVals.length || iVals[iVals.length - 1] < oVals[oIdx]) {
      if (first) {
        if (stops.length) setStop(stops[stops.length - 1].value, 'outOfRange');
        first = 0;
      }
      setStop(oVals[oIdx], 'outOfRange');
    }
  }
  const TRANSPARENT = [0, 0, 0, 0];
  return {
    stops,
    outer: [stops.length ? stops[0].color : TRANSPARENT, stops.length ? stops[stops.length - 1].color : TRANSPARENT],
  };
}

// LineView.ts:222-366 on the recorded meta (stops with coords)
function clipStops(stops, lo, hi) {
  const out = [];
  let prevOut;
  let prevIn;
  const lerpStop = (s0, s1, cc) => ({ coord: cc, color: lerpTuple((cc - s0.coord) / (s1.coord - s0.coord), s0.color, s1.color) });
  for (const stop of stops) {
    if (stop.coord < lo) {
      prevOut = stop;
    } else if (stop.coord > hi) {
      if (prevIn) out.push(lerpStop(prevIn, stop, hi));
      else if (prevOut) out.push(lerpStop(prevOut, stop, lo), lerpStop(prevOut, stop, hi));
      break;
    } else {
      if (prevOut) { out.push(lerpStop(prevOut, stop, lo)); prevOut = null; }
      out.push(stop);
      prevIn = stop;
    }
  }
  return out;
}
function gradientOf(meta, canvasSize, grid, mut) {
  const TRANSPARENT = [0, 0, 0, 0];
  const stops = meta.stops.map(s => ({ coord: s.coord, color: s.color }));
  const outer = meta.outer.slice();
  const n = stops.length;
  if (n && stops[0].coord > stops[n - 1].coord) {
    stops.reverse();
    if (!mut.noOuterReverse) outer.reverse();
  }
  let inR;
  if (mut.noClip) inR = stops.slice();
  else if (mut.clipGrid) inR = clipStops(stops, grid[0], grid[1]);
  else inR = clipStops(stops, 0, canvasSize);
  const m = inR.length;
  if (!m && n) {
    return { kind: 'color', color: stops[0].coord < 0 ? (outer[1] || stops[n - 1].color) : (outer[0] || stops[0].color) };
  }
  const tiny = mut.tiny0 ? 0 : 10;
  const minC = inR[0].coord - tiny;
  const maxC = inR[m - 1].coord + tiny;
  const span = maxC - minC;
  if (span < 1e-3) return { kind: 'color', color: TRANSPARENT };
  const out = inR.map(s => ({ offset: (s.coord - minC) / span, color: s.color }));
  out.push({ offset: m ? out[m - 1].offset : 0.5, color: outer[1] || TRANSPARENT });
  out.unshift({ offset: m ? out[0].offset : 0.5, color: outer[0] || TRANSPARENT });
  const g = { x: 0, y: 0, x2: 0, y2: 0 };
  g[meta.coordDim] = minC;
  g[meta.coordDim + '2'] = maxC;
  return { kind: 'gradient', global: true, x: g.x, y: g.y, x2: g.x2, y2: g.y2, stops: out };
}
function samePaint(rec, p) {
  if (rec.kind !== p.kind) return false;
  if (p.kind === 'color') return sameColour(rec.color, p.color);
  return rec.global === p.global && rec.x === hex(p.x) && rec.y === hex(p.y) && rec.x2 === hex(p.x2) && rec.y2 === hex(p.y2)
    && rec.stops.length === p.stops.length
    && rec.stops.every((s, k) => s.offset === hex(p.stops[k].offset) && sameColour(s.color, p.stops[k].color));
}

// the whole chart case, from the option and the recorded inputs (store values,
// series colours, meta coords); returns the list of fields that differ from the
// record (empty = the transcription is upstream's)
function vmOptions(option) {
  const v = option.visualMap;
  return v === undefined ? [] : Array.isArray(v) ? v : [v];
}
function seriesOptions(option) {
  const s = option.series;
  return Array.isArray(s) ? s : [s];
}
function transcribeCase(c, gradientColor, mut) {
  const diffs = [];
  const opts = vmOptions(c.option);
  const models = c.visualMaps.map(vr => modelOf(opts[vr.index], gradientColor, mut));
  c.visualMaps.forEach((vr, k) => {
    const m = models[k];
    if (vr.extent.join() !== m.extent.map(hex).join()) diffs.push('vm' + vr.index + ' extent');
    if (vr.range.join() !== m.range.map(hex).join()) diffs.push('vm' + vr.index + ' range');
    if (vr.rangeAuto !== m.rangeAuto) diffs.push('vm' + vr.index + ' rangeAuto');
    if (JSON.stringify(vr.target) !== JSON.stringify(m.target)) diffs.push('vm' + vr.index + ' target');
    for (const st of ['inRange', 'outOfRange']) {
      if (vr.order[st].join() !== m.order(st).join()) diffs.push('vm' + vr.index + ' order ' + st);
    }
  });
  const sOpts = seriesOptions(c.option);
  for (const s of c.series) {
    const sOpt = sOpts[s.index];
    const rawData = s.rawItems;
    const seriesColor = tupleOf(s.color);
    const seriesOpacity = s.opacity == null ? undefined : num(s.opacity);
    let vmOrder = s.targetedBy.slice();
    if (mut.reverseComponents) vmOrder.reverse();
    const valueOf = (vmIdx, i) => {
      if (mut.alt && mut.alt === c.id + '/' + s.index && s.alt) return num(s.alt.values[i]);
      return num(s.rows[i].values.find(x => x.vm === vmIdx).value);
    };
    s.rows.forEach((row, i) => {
      const run = { color: seriesColor, opacity: seriesOpacity };
      const raw = rawData[i];
      const override = () => {
        // style.ts:134-171; every series here reads itemStyle and draws with fill
        if (s.drawType === 'fill' && raw && typeof raw === 'object' && !Array.isArray(raw) && raw.itemStyle) {
          if (raw.itemStyle.color != null) run.color = C.parse(raw.itemStyle.color);
          if (raw.itemStyle.opacity != null) run.opacity = raw.itemStyle.opacity;
        }
      };
      if (mut.visualAfterOverride) override();
      for (const vmIdx of vmOrder) {
        if (!mut.ignoreSkip && raw && raw.visualMap === false) continue;
        const m = models[c.visualMaps.findIndex(vr => vr.index === vmIdx)];
        const v = valueOf(vmIdx, i);
        const st = m.state(v);
        const rec = row.values.find(x => x.vm === vmIdx);
        if (!mut.alt && rec.state !== st) diffs.push('s' + s.index + ' row ' + i + ' state');
        for (const type of m.order(st)) m.apply(v, st, type, run, false);
      }
      if (!mut.visualAfterOverride) override();
      if (!sameColour(row.color, run.color)) diffs.push('s' + s.index + ' row ' + i + ' color');
      if (row.opacity !== hexOrNull(run.opacity)) diffs.push('s' + s.index + ' row ' + i + ' opacity');
    });
    // the visualMeta
    s.visualMeta.forEach(meta => {
      const m = models[c.visualMaps.findIndex(vr => vr.index === meta.vm)];
      const mine = metaOf(m, seriesColor, mut);
      const same = mine.stops.length === meta.stops.length
        && mine.stops.every((st, k) => meta.stops[k].value === hex(st.value) && sameColour(meta.stops[k].color, st.color))
        && sameColour(meta.outerColors[0], mine.outer[0]) && sameColour(meta.outerColors[1], mine.outer[1]);
      if (!same) diffs.push('s' + s.index + ' visualMeta vm' + meta.vm);
    });
    // the line paints, from the recorded meta and coords
    if (s.type === 'line') {
      const used = (mut.firstMeta ? s.visualMeta.slice() : s.visualMeta.slice().reverse())
        .find(mt => mt.coordDim === 'x' || mt.coordDim === 'y');
      let grad = null;
      if (used) {
        const meta = {
          coordDim: used.coordDim,
          stops: used.stops.map(st => ({ coord: num(st.coord), color: tupleOf(st.color) })),
          outer: used.outerColors.map(tupleOf),
        };
        const canvas = used.coordDim === 'x' ? c.width : c.height;
        const g = used.coordDim === 'x' ? [num(s.grid.x), num(s.grid.x) + num(s.grid.width)]
          : [num(s.grid.y), num(s.grid.y) + num(s.grid.height)];
        grad = gradientOf(meta, canvas, g, mut);
      }
      const line = sOpt.lineStyle && sOpt.lineStyle.color != null && !mut.overrideLineStyle
        ? { kind: 'color', color: C.parse(sOpt.lineStyle.color) }
        : grad || { kind: 'color', color: seriesColor };
      if (!samePaint(s.polyline, line)) diffs.push('s' + s.index + ' polyline');
      if (s.area) {
        const area = sOpt.areaStyle && sOpt.areaStyle.color != null ? { kind: 'color', color: C.parse(sOpt.areaStyle.color) }
          : grad || { kind: 'color', color: seriesColor };
        if (!samePaint(s.area, area)) diffs.push('s' + s.index + ' area');
      }
    }
    if (s.tooltipMarker) {
      const row = s.tooltipMarker.row;
      const mine = mut.markerBypass ? seriesColor : tupleOf(s.rows[row].color);
      if (!sameColour(s.tooltipMarker.color, mine)) diffs.push('s' + s.index + ' tooltipMarker');
    }
  }
  return diffs;
}

// ---------- the cases ----------

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);

// K1: the 7 shapes of upstream54 section 2 (T1..T7), then extras
const SUBTYPES = [
  ['T1', '{}', {}],
  ['T2', 'splitNumber 5', { splitNumber: 5 }],
  ['T3', 'pieces [] (empty, truthy)', { pieces: [] }],
  ['T4', 'splitNumber 5 + calculable', { splitNumber: 5, calculable: true }],
  ['T5', 'pieces + calculable (pieces ignored)', { pieces: [{ min: 0, max: 10 }], calculable: true }],
  ['T6', 'categories', { categories: ['a', 'b'] }],
  ['T7', 'splitNumber 0 (ec2)', { splitNumber: 0 }],
  ['X1', 'categories [] (empty, truthy)', { categories: [] }],
  ['X2', 'pieces with one piece', { pieces: [{ min: 0, max: 10 }] }],
  ['X3', "splitNumber '5' (a string compared as a number)", { splitNumber: '5' }],
  ['X4', 'splitNumber -1', { splitNumber: -1 }],
  ['X5', 'calculable alone', { calculable: true }],
  ['X6', 'type written: continuous with splitNumber 5 (the defaulter is not asked)', { type: 'continuous', splitNumber: 5 }],
  ['X7', 'categories + calculable', { categories: ['a'], calculable: true }],
];

const bar = (data, vm, extra) => Object.assign({
  xAxis: { type: 'category', data: cat(data.length) }, yAxis: {}, visualMap: vm, series: [{ type: 'bar', data }],
}, extra || {});

const CHARTS = [
  // K2: extent, range, unboundedRange
  { id: 'K2a', groups: ['K2'], note: 'min 200, max 0: the extent is asc([min, max])',
    option: bar([0, 50, 100, 150, 200], { show: false, type: 'continuous', min: 200, max: 0, inRange: { color: ['#000000', '#ffffff'] } }) },
  { id: 'K2b', groups: ['K2'], note: 'range [300, 30] on [0, 200]: swapped to [30, 300], clamped to [30, 200]; below 30 is out',
    option: bar([0, 20, 30, 100, 200, 300], { show: false, type: 'continuous', min: 0, max: 200, range: [300, 30] }) },
  { id: 'K2c', groups: ['K2'], note: 'range [300, 30] + unboundedRange false: 250 and 300 are out only through the clamp',
    option: bar([0, 20, 30, 100, 200, 250, 300], { show: false, type: 'continuous', min: 0, max: 200, range: [300, 30], unboundedRange: false }) },
  { id: 'K2d', groups: ['K2'], note: 'unboundedRange false, default range: -10 and 300 are out, 0 and 200 in',
    option: bar([-10, 0, 100, 200, 300], { show: false, type: 'continuous', min: 0, max: 200, unboundedRange: false }) },
  { id: 'K2e', groups: ['K2'], note: 'unboundedRange unset (true), default range: -10 and 300 are in (clamped colours)',
    option: bar([-10, 0, 100, 200, 300], { show: false, type: 'continuous', min: 0, max: 200 }) },
  { id: 'K2f', groups: ['K2'], note: 'range [-50, 100] + unboundedRange false: -10 is out only through the clamp',
    option: bar([-10, 0, 50, 100, 150], { show: false, type: 'continuous', min: 0, max: 200, range: [-50, 100], unboundedRange: false }) },
  // K3: target completion
  { id: 'K3a', groups: ['K3'], note: "ec2 color ['#f00','#00f'] (high to low) is reversed into inRange",
    option: bar([0, 25, 50, 100], { show: false, type: 'continuous', min: 0, max: 100, color: ['#f00', '#00f'] }) },
  { id: 'K3b', groups: ['K3'], note: 'inRange {color: null}: every fill undefined',
    option: bar([0, 50, 100], { show: false, type: 'continuous', min: 0, max: 100, inRange: { color: null } }) },
  { id: 'K3c', groups: ['K3'], note: 'no inRange: the default ramp gradientColor from #5070dd',
    option: bar([0, 50, 100, 150, 200], { show: false, type: 'continuous', min: 0, max: 200 }) },
  { id: 'K3d', groups: ['K3'], note: 'range [50, 150], default ramp: 0 and 200 get the inactive colour and opacity 0',
    option: bar([0, 50, 100, 150, 200], { show: false, type: 'continuous', min: 0, max: 200, range: [50, 150] }) },
  { id: 'K3e', groups: ['K3'], note: 'target {inRange: {opacity}} + inRange {color}: per-key merge, keys opacity, color',
    option: bar([0, 50, 100], { show: false, type: 'continuous', min: 0, max: 100, target: { inRange: { opacity: [0.2, 1] } },
      inRange: { color: ['#ff0000', '#0000ff'] } }) },
  // K4: colours
  { id: 'E0', groups: ['K4', 'K7', 'K8'], note: 'dataset-encode0 (gallery), all 9 rows; dimension 0 = score', gallery: 'dataset-encode0',
    alt: { series: 0, what: "the store's x coordinate 'amount' read instead of score", values: d => col(d, 'amount') } },
  { id: 'K4b', groups: ['K4'], note: "#000 -> #010101 on [0, 2]: v 1 half-way, '-' NaN, v 2 = max, v 0",
    option: bar([1, '-', 2, 0], { show: false, type: 'continuous', min: 0, max: 2, inRange: { color: ['#000000', '#010101'] } }) },
  { id: 'K4c', groups: ['K4'], note: 'alpha ramp 0.1 -> 0.5 on [0, 2]: v 1 gives alpha 0.30000000000000004',
    option: bar([0, 1, 2], { show: false, type: 'continuous', min: 0, max: 2, inRange: { color: ['rgba(80,112,221,0.1)', 'rgba(80,112,221,0.5)'] } }) },
  // K5: the order in a visualMeta
  { id: 'K5a', groups: ['K5'], note: "inRange {color: ['grey'], opacity}: sorted opacity, color -> the meta alpha is lost",
    option: { xAxis: { type: 'value' }, yAxis: {}, visualMap: { type: 'continuous', show: false, min: 0, max: 200,
      inRange: { color: ['grey'], opacity: [0, 0.3] } }, series: [{ type: 'line', data: [[0, 0], [1, 50], [2, 100], [3, 200]] }] } },
  { id: 'K5b', groups: ['K5'], note: "inRange {opacity, color: ['grey']}: sorted color, opacity -> the meta alpha is kept",
    option: { xAxis: { type: 'value' }, yAxis: {}, visualMap: { type: 'continuous', show: false, min: 0, max: 200,
      inRange: { opacity: [0, 0.3], color: ['grey'] } }, series: [{ type: 'line', data: [[0, 0], [1, 50], [2, 100], [3, 200]] }] } },
  // K6: precedence
  { id: 'K6a', groups: ['K6'], note: "row 0 itemStyle.color '#ff00ff' wins over the visual; row 2 visualMap:false keeps the series colour",
    option: bar([{ value: 5, itemStyle: { color: '#ff00ff' } }, 5, { value: 5, visualMap: false }, 10],
      { show: false, type: 'continuous', min: 0, max: 10, inRange: { color: ['#000000', '#ffffff'], opacity: [0.2, 1] } }) },
  { id: 'K6c', groups: ['K6'], note: "series itemStyle {gradient, opacity 0.5}: the mapped colour replaces the gradient, the visual opacity the series'; row 2's own opacity 0.3 wins",
    option: { xAxis: { type: 'category', data: cat(3) }, yAxis: {},
      visualMap: { show: false, type: 'continuous', min: 0, max: 10, inRange: { color: ['#000000', '#ffffff'], opacity: [0.2, 1] } },
      series: [{ type: 'bar', itemStyle: { opacity: 0.5, color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
        colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] } },
        data: [0, 5, { value: 10, itemStyle: { opacity: 0.3 } }] }] } },
  { id: 'K6d', groups: ['K6'], note: "scatter: the visual opacity replaces the series' 0.8",
    option: { xAxis: {}, yAxis: {}, visualMap: { show: false, type: 'continuous', min: 0, max: 10,
      inRange: { color: ['#000000', '#ffffff'], opacity: [0.2, 1] } },
      series: [{ type: 'scatter', data: [[1, 2, 0], [3, 4, 5], [5, 6, 10]] }] } },
  { id: 'K6b', groups: ['K6'], note: 'two visualMaps on one series: applied in component order, the second colour wins',
    option: bar([0, 5, 10], [
      { show: false, type: 'continuous', min: 0, max: 10, inRange: { color: ['#ff0000', '#0000ff'] } },
      { show: false, type: 'continuous', min: 0, max: 20, inRange: { color: ['#00ff00', '#ffff00'] } }]) },
  // K7: dimension
  { id: 'K7a', groups: ['K7'], note: 'horizontal bar: the default dimension is y, the category ordinal',
    option: { visualMap: { type: 'continuous', show: false, min: 0, max: 200 }, xAxis: {}, yAxis: { type: 'category', data: ['a', 'b', 'c'] },
      series: [{ type: 'bar', data: [150, 30, 90] }] },
    alt: { series: 0, what: 'the value axis (bar length) read instead of the ordinal', values: d => col(d, 'x') } },
  { id: 'K7b', groups: ['K7'], note: 'stacked line: the raw y, not the stack sum',
    option: { visualMap: { type: 'continuous', show: false, min: 0, max: 200 }, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {},
      series: [{ type: 'line', stack: 's', data: [10, 20] }, { type: 'line', stack: 's', data: [100, 150] }] },
    alt: { series: 1, what: 'the stack sum read instead of the raw y', values: d => col(d, d.getCalculationInfo('stackResultDimension')) } },
  { id: 'K7c', groups: ['K7'], note: 'scatter [x, y, v]: the default dimension is column 2',
    option: { visualMap: { type: 'continuous', show: false, min: 0, max: 200 }, xAxis: {}, yAxis: {},
      series: [{ type: 'scatter', data: [[1, 2, 180], [3, 4, 20]] }] },
    alt: { series: 0, what: 'column 2 read from a store that does not hold it (NaN)', values: d => Array.from({ length: d.count() }, () => NaN) } },
  { id: 'K7d', groups: ['K7'], note: 'dataset without dimension: the last dataset column (its ordinal)',
    option: { visualMap: { type: 'continuous', show: false, min: 0, max: 200 },
      dataset: { source: [['s', 'a', 'p'], [89.3, 58212, 'M'], [57.1, 78254, 'N']] }, xAxis: {}, yAxis: { type: 'category' },
      series: [{ type: 'bar', encode: { x: 'a', y: 'p' } }] } },
  // K7 s1, K8, K9 s0/s1, K10
  { id: 'LG', groups: ['K7', 'K8', 'K9', 'K10'], note: 'line-gradient (gallery): s0 y-gradient on [0, 400], s1 dimension 0 on a category x',
    gallery: 'line-gradient', marker: 10,
    alt: { series: 1, what: 'the default dimension (y) read instead of dimension 0', values: d => col(d, 'y') } },
  // K9 extra
  { id: 'K9c', groups: ['K9'], note: 'max 10000: the stops leave the canvas top, the cut at 0 is lerped; area too',
    option: { xAxis: { type: 'category', data: cat(7) }, yAxis: {}, visualMap: { show: false, type: 'continuous', min: 0, max: 10000 },
      series: [{ type: 'line', areaStyle: {}, data: [120, 200, 150, 80, 70, 110, 130] }] } },
  { id: 'K9d', groups: ['K9'], note: 'y-gradient that needs reversing, range [60, 240] of [0, 300], three colours (outOfRange stops in the meta)',
    option: { xAxis: { type: 'category', data: cat(7) }, yAxis: {}, visualMap: { show: false, type: 'continuous', min: 0, max: 300,
      range: [60, 240], inRange: { color: ['#00ff00', '#ffff00', '#ff0000'] } },
    series: [{ type: 'line', data: [20, 90, 150, 280, 200, 60, 120] }] } },
  { id: 'K9e', groups: ['K9'], note: "authored lineStyle.color '#ff0000': the polyline keeps it, the area takes the gradient",
    option: { xAxis: { type: 'category', data: cat(7) }, yAxis: {}, visualMap: { show: false, type: 'continuous', min: 0, max: 200 },
      series: [{ type: 'line', lineStyle: { color: '#ff0000' }, areaStyle: {}, data: [120, 200, 150, 80, 70, 110, 130] }] } },
  { id: 'K9g', groups: ['K9'], note: 'two visualMetas, y then x: the line takes the LAST one on x or y (x)',
    option: { xAxis: { type: 'value' }, yAxis: {}, visualMap: [
      { show: false, type: 'continuous', dimension: 1, min: 0, max: 10, inRange: { color: ['#00ff00', '#ffff00'] } },
      { show: false, type: 'continuous', dimension: 0, min: 0, max: 10, inRange: { color: ['#0000ff', '#ff0000'] } }],
      series: [{ type: 'line', data: [[0, 5], [2, 8], [5, 3], [10, 6]] }] } },
  { id: 'K9f', groups: ['K9'], note: 'x-gradient on an inverse value x axis (needs reversing), dimension 0',
    option: { xAxis: { type: 'value', inverse: true }, yAxis: {}, visualMap: { show: false, type: 'continuous', dimension: 0, min: 0, max: 10,
      inRange: { color: ['#0000ff', '#ff0000'] } }, series: [{ type: 'line', data: [[0, 5], [2, 8], [5, 3], [10, 6]] }] } },
];

function col(data, dimName) {
  const store = data.getStore();
  const di = data.getDimensionIndex(dimName);
  must(di >= 0, 'no dimension ' + dimName);
  return Array.from({ length: data.count() }, (_, i) => store.get(di, i));
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

let VisualMappingClass = null;

function recordChart(def) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  const option = JSON.parse(optionText);
  return runChart(JSON.parse(optionText), chart => {
    const gm = chart.getModel();
    const vms = gm.findComponents({ mainType: 'visualMap' });
    const rec = { id: def.id, groups: def.groups, note: def.note, width: chart.getWidth(), height: chart.getHeight(), option };
    rec.visualMaps = vms.map(vm => {
      if (!VisualMappingClass) {
        const anyMapping = Object.keys(vm.targetVisuals.inRange).map(k => vm.targetVisuals.inRange[k])[0];
        if (anyMapping) VisualMappingClass = anyMapping.constructor;
      }
      const ext = vm.getExtent();
      const range = vm.option.range;
      const targets = [];
      gm.eachSeries(sm => { if (vm.isTargetSeries(sm)) targets.push(sm.seriesIndex); });
      return {
        index: vm.componentIndex, subType: vm.subType,
        extent: ext.map(hex), extentText: ext.map(text),
        range: range.map(hex), rangeText: range.map(text), rangeAuto: !!range.auto,
        unboundedRange: vm.option.unboundedRange == null ? null : vm.option.unboundedRange,
        target: clone(vm.option.target),
        order: {
          inRange: VisualMappingClass.prepareVisualTypes(vm.targetVisuals.inRange),
          outOfRange: VisualMappingClass.prepareVisualTypes(vm.targetVisuals.outOfRange),
        },
        targets,
      };
    });
    rec.series = [];
    gm.eachSeries(sm => {
      const data = sm.getData();
      const drawType = data.getVisual('drawType');
      const sStyle = data.getVisual('style');
      const store = data.getStore();
      const targeting = vms.filter(vm => vm.isTargetSeries(sm));
      const dims = targeting.map(vm => {
        const dimIndex = vm.getDataDimensionIndex(data);
        return { vm: vm.componentIndex, dimIndex, dimName: data.getDimension(dimIndex) };
      });
      const s = {
        index: sm.seriesIndex, type: sm.subType, drawType, color: colRec(sStyle[drawType]), opacity: hexOrNull(sStyle.opacity),
        targetedBy: targeting.map(vm => vm.componentIndex), dims, rows: [],
      };
      for (let i = 0; i < data.count(); i++) {
        const raw = data.getRawDataItem(i);
        const row = { i };
        if (raw && raw.visualMap === false) row.skip = true;
        row.values = targeting.map((vm, k) => {
          const v = store.get(data.getDimensionIndex(dims[k].dimIndex), i);
          return { vm: vm.componentIndex, value: hex(v), valueText: text(v), state: vm.getValueState(v) };
        });
        const st = data.getItemVisual(i, 'style');
        row.color = colRec(st[drawType]);
        row.opacity = hexOrNull(st.opacity);
        row.opacityText = textOrNull(st.opacity);
        s.rows.push(row);
      }
      // raw items for the transcription (not written)
      Object.defineProperty(s, 'rawItems', { value: Array.from({ length: data.count() }, (_, i) => data.getRawDataItem(i)), enumerable: false });
      const metas = data.getVisual('visualMeta') || [];
      const metaVms = targeting.filter(vm => vm.getDataDimensionIndex(data) >= 0);
      must(metas.length === metaVms.length, def.id + ' s' + sm.seriesIndex + ': ' + metas.length + ' metas for ' + metaVms.length + ' visualMaps');
      const cs = sm.coordinateSystem;
      s.visualMeta = metas.map((meta, k) => {
        const di = data.getDimensionInfo(meta.dimension);
        const coordDim = di && (di.coordDim === 'x' || di.coordDim === 'y') ? di.coordDim : null;
        const axis = coordDim && cs && cs.type === 'cartesian2d' ? cs.getAxis(coordDim) : null;
        return {
          vm: metaVms[k].componentIndex, dimension: meta.dimension, coordDim,
          outerColors: meta.outerColors.map(colRec),
          stops: meta.stops.map(stp => {
            const o = { value: hex(stp.value), valueText: text(stp.value), color: colRec(stp.color) };
            if (axis && sm.subType === 'line') {
              const cc = axis.toGlobalCoord(axis.dataToCoord(stp.value));
              o.coord = hex(cc);
              o.coordText = text(cc);
            }
            return o;
          }),
        };
      });
      if (sm.subType === 'line') {
        const r = cs.getArea ? cs.getArea() : null;
        const g = cs.master.getRect();
        must(!r || (r.x === g.x && r.width === g.width), 'grid rect');
        s.grid = { x: hex(g.x), y: hex(g.y), width: hex(g.width), height: hex(g.height),
          xText: text(g.x), yText: text(g.y), widthText: text(g.width), heightText: text(g.height) };
        const lsc = sm.option.lineStyle && sm.option.lineStyle.color;
        s.lineStyleColorWritten = lsc != null;
        const view = chart.getViewOfSeriesModel(sm);
        must(view._polyline, def.id + ': no polyline');
        s.polyline = paintRec(view._polyline.style.stroke);
        s.area = view._polygon ? paintRec(view._polygon.style.fill) : null;
      }
      if (def.marker != null && sm.subType === 'line') {
        const frag = sm.formatTooltip(def.marker, true);
        const found = [];
        (function walk(o) {
          if (!o || typeof o !== 'object') return;
          if (hasOwn(o, 'markerColor')) found.push(o.markerColor);
          for (const k of Object.keys(o)) if (k !== 'markerColor') walk(o[k]);
        })(frag);
        must(found.length >= 1 && found.every(f => f === found[0]), def.id + ': tooltip marker colours ' + JSON.stringify(found));
        s.tooltipMarker = { row: def.marker, color: colRec(found[0]) };
      }
      if (def.alt && def.alt.series === sm.seriesIndex) {
        const vals = def.alt.values(data);
        s.alt = { what: def.alt.what, values: vals.map(hex), valuesText: vals.map(text) };
      }
      rec.series.push(s);
    });
    return rec;
  });
}

function recordSubtype([id, note, shape]) {
  const option = { visualMap: Object.assign({ show: false }, shape), series: [] };
  const text1 = JSON.stringify(option);
  return runChart(JSON.parse(text1), chart => {
    const vm = chart.getModel().getComponent('visualMap', 0);
    return { id, note, option: JSON.parse(text1), subType: vm.subType };
  });
}

// K5: the sort cases
const TYPE_NAMES = VALID_TYPES;
const AUDIT_LISTS = [
  ['color', 'opacity'], ['opacity', 'color'], ['color', 'colorLightness'], ['colorLightness', 'color'],
  ['color', 'symbol', 'symbolSize', 'opacity'], ['colorSaturation', 'symbol', 'color', 'opacity'],
  ['symbolSize', 'color', 'colorLightness'], ['opacity', 'color', 'symbol', 'symbolSize'],
  ['color', 'colorAlpha', 'opacity'], ['colorHue', 'opacity', 'color'],
  ['symbol', 'colorLightness', 'color', 'opacity', 'symbolSize'], ['color', 'opacity', 'colorHue'],
  ['color', 'colorHue'], ['color', 'symbolSize', 'colorHue'], ['opacity', 'color', 'symbol'],
  [], ['color'], ['opacity'],
  // only lists of eight or more tell runThenLinear from V8
  ['symbol', 'color', 'colorAlpha', 'colorSaturation', 'opacity', 'liftZ', 'colorLightness', 'decal'],
  ['decal', 'liftZ', 'color', 'colorHue', 'colorAlpha', 'symbol', 'opacity', 'colorLightness'],
  ['opacity', 'symbol', 'color', 'colorLightness', 'symbolSize', 'decal', 'colorSaturation', 'liftZ'],
  ['color', 'colorHue', 'symbolSize', 'colorLightness', 'decal', 'liftZ', 'opacity', 'colorAlpha'],
  ['color', 'colorHue', 'opacity', 'colorLightness', 'symbol', 'symbolSize', 'decal', 'colorAlpha', 'liftZ'],
  ['liftZ', 'symbol', 'color', 'colorLightness', 'opacity', 'decal', 'colorAlpha', 'colorSaturation', 'colorHue'],
];
function sortLists() {
  const seen = new Set();
  const lists = [];
  for (const l of AUDIT_LISTS) {
    const k = l.join();
    if (!seen.has(k)) { seen.add(k); lists.push(l.slice()); }
  }
  let s = 0x9e3779b9;
  const u32 = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s; };
  while (lists.length < 60) {
    const p = TYPE_NAMES.slice();
    for (let i = p.length - 1; i > 0; i--) { const j = u32() % (i + 1); const t = p[i]; p[i] = p[j]; p[j] = t; }
    const k = 2 + (u32() % 6);
    let q = p.slice(0, k);
    // keep 'color' in two lists of three
    if (u32() % 3 !== 0 && !q.includes('color')) q[u32() % k] = 'color';
    const key = q.join();
    if (seen.has(key)) continue;
    seen.add(key);
    lists.push(q);
  }
  return lists;
}

// parse
const PARSE_REQUIRED = ['rgba(0,0,180,0.4)', 'rgba(0, 0, 180, 0.4)', 'rgb(30%,0,0)', 'rgb(10%,50%,70%)',
  'hsl(30,100%,30%)', 'hsl(30,100%,70%)', 'hsl(105,100%,80%)', 'hsl(15,50%,40%)', 'hsla(30,100%,30%,0.5)',
  'hsl(30,100%,50%)', 'hsl(390,100%,50%)', '#5070dd', '#5070DD', 'notacolor'];
const PARSE_EXTRA = ['grey', 'gray', 'transparent', 'red', 'white', 'black', '#f00', '#00f', '#fff', '#000', '#000000',
  '#010101', '#ffffff', '#ff00ff', '#ff0000', '#0000ff', '#00ff00', '#ffff00', '#65B581', '#FFCE34', '#FD665F',
  '#cfd2d7', 'rgba(80,112,221,0.1)', 'rgba(80,112,221,0.5)', 'rgba(80,112,221,0.30000000000000004)',
  'rgba(212,220,247,1)', 'rgba(0,0,0,0)', 'rgb(76.5,0,0)', 'rgba(10,20,30)', '#5070dd80', '#f008', 'rgb(300,-5,0)',
  'rgba(0,0,0,1.5)', 'hsl(0,0%,50%)', 'hsl(-30,100%,50%)', '#12345', 'rgb(1,2)', ''];
// the half-way channels (x.5 with x even: JS rounds up, banker's down)
const HALF_WAY = ['rgb(30%,0,0)', 'rgb(10%,50%,70%)', 'hsl(30,100%,30%)', 'hsl(30,100%,70%)', 'hsl(105,100%,80%)',
  'hsl(15,50%,40%)', 'hsla(30,100%,30%,0.5)'];

function colourStringsIn(v, out) {
  if (typeof v === 'string') { if (C.parse(v) && !/^c\d+$/.test(v)) out.add(v); return out; }
  if (v && typeof v === 'object') for (const k of Object.keys(v)) colourStringsIn(v[k], out);
  return out;
}
function recordParse(list) {
  return list.map(css => {
    const p = C.parse(css);
    if (!p) return { in: css, ok: false };
    return { in: css, ok: true, r: p[0], g: p[1], b: p[2], a: hex(p[3]), aText: text(p[3]) };
  });
}

// fastLerp direct
const FAST_LERP = [
  ['F1', 0.5, ['#000000', '#010101'], 'half-way 0.5 -> 1 (banker\'s 0)'],
  ['F2', 0.25, ['#000', '#030303'], '0.75 -> 1'],
  ['F3', 1, ['#000000', '#010101'], 'n = 1: right index = left index'],
  ['F4', NaN, ['#000000', '#ffffff'], 'NaN -> undefined'],
  ['F5', 0.5, ['rgba(80,112,221,0.1)', 'rgba(80,112,221,0.5)'], 'alpha 0.30000000000000004, not rounded'],
  ['F6', 1.0000000000000002, ['#000000', '#ffffff'], 'just above 1 -> undefined'],
  ['F7', 0, ['#5070dd'], 'one stop'],
  ['F8', 0.5, ['#65B581', '#FFCE34', '#FD665F'], 'three stops at 0.5: exactly the middle one'],
  ['F9', 0.3, ['#65B581', '#FFCE34', '#FD665F'], 'three stops at 0.3'],
  ['F10', -0, ['#000000', '#ffffff'], '-0 is >= 0'],
  ['F11', 0.5, ['notacolor', '#ffffff'], 'an unparsable stop is [0,0,0,1]'],
  ['F12', 0.5, ['#000000', '#050505'], '2.5 -> 3 (banker\'s 2)'],
  ['F13', 0.5, ['rgba(0,0,0,0)', 'rgba(0,0,0,1)'], 'alpha 0.5'],
  ['F14', 0.1, ['#000000', '#ffffff'], '25.5 -> 26 (banker\'s 26 too)'],
];
function recordFastLerp() {
  return FAST_LERP.map(([id, n, colors, note]) => {
    const parsed = colors.map(c => C.parse(c) || [0, 0, 0, 1]);
    const r = C.fastLerp(n, parsed);
    return { id, note, n: hex(n), nText: text(n), colors, result: tupRec(r) };
  });
}

// ---------- the guards ----------
const GUARDS = [
  // K1
  { id: 'K1-T3', mutation: 'pieces <> nil instead of pieces.length > 0', kind: 'subtype', mut: { piecesNotNil: true }, named: ['T3'] },
  { id: 'K1-T4', mutation: "drop 'or calculable'", kind: 'subtype', mut: { dropCalculable: true }, named: ['T4', 'T5'] },
  { id: 'K1-T6', mutation: 'drop the categories test', kind: 'subtype', mut: { dropCategories: true }, named: ['T6'] },
  // K2
  { id: 'K2-asc', mutation: 'no asc on [min, max]', mut: { noAsc: true }, named: ['K2a'] },
  { id: 'K2-swap', mutation: 'a reversed range is not swapped', mut: { noSwap: true }, named: ['K2b'] },
  { id: 'K2-clamp', mutation: 'the range is not clamped into the extent', mut: { noClamp: true }, named: ['K2c', 'K2f'] },
  { id: 'K2-unbounded', mutation: 'unboundedRange defaults to false', mut: { ubFalse: true }, named: ['K2e'] },
  // K3
  { id: 'K3-reverse', mutation: 'the ec2 color list is not reversed', mut: { noReverse: true }, named: ['K3a'] },
  { id: 'K3-null', mutation: 'inRange.color null treated as absent', mut: { nullAbsent: true }, named: ['K3b'] },
  { id: 'K3-lightness', mutation: 'gradientColor lightness 0.9 read as 90', kind: 'gradientColor', named: ['K3c'] },
  { id: 'K3-opacity', mutation: 'no opacity [0,0] beside the inactive colour', mut: { noOpacityDefault: true }, named: ['K3d'] },
  { id: 'K3-merge', mutation: 'shallow merge of target and the option states', mut: { shallowMerge: true }, named: ['K3e'] },
  // K4
  { id: 'K4-round', mutation: "FPC banker's Round in fastLerp", mut: { bankers: true }, named: ['K4b', 'F1', 'F12'] },
  { id: 'K4-nan', mutation: 'NaN through TyLinearMap (answers the range low end)', mut: { nanLinear: true }, named: ['K4b'] },
  { id: 'K4-right', mutation: 'rightIndex := leftIndex + 1', mut: { rightPlusOne: true }, named: ['K4b', 'E0', 'F3'] },
  { id: 'K4-alpha8', mutation: 'alpha quantised to 8 bits', mut: { alpha8: true }, named: ['K4c', 'F5'] },
  // K5
  { id: 'K5-identity', mutation: 'visuals applied in object key order (identity)', mut: { sort: 'identity' }, named: ['K5a', 'S:color,opacity'] },
  { id: 'K5-reverse', mutation: 'visuals applied in reversed key order', mut: { sort: 'reverse' }, named: ['S:color,colorLightness'] },
  { id: 'K5-insertion', mutation: 'linear insertion sort with the comparator', mut: { sort: 'linearInsertion' }, named: ['S:color,opacity,colorHue'] },
  { id: 'K5-binary', mutation: 'binary insertion sort without the run', mut: { sort: 'binaryInsertionNoRun' }, named: ['S:color,opacity,colorHue'] },
  { id: 'K5-runlinear', mutation: "V8's run, then a linear scan instead of the binary search", mut: { sort: 'runThenLinear' },
    named: ['S:symbol,color,colorAlpha,colorSaturation,opacity,liftZ,colorLightness,decal'] },
  // K6
  { id: 'K6-after', mutation: 'the visual applied after the itemStyle override', mut: { visualAfterOverride: true }, named: ['K6a'] },
  { id: 'K6-skip', mutation: 'the raw item visualMap:false is ignored', mut: { ignoreSkip: true }, named: ['K6a'] },
  { id: 'K6-order', mutation: 'visualMaps applied in reversed component order', mut: { reverseComponents: true }, named: ['K6b'] },
  { id: 'K6-multiply', mutation: "the visual opacity multiplies the series' instead of replacing it", mut: { multiplyOpacity: true }, named: ['K6c'] },
  // K7
  { id: 'K7-E0', mutation: "store column 0 (x = amount) read for dataset-encode0's dimension 0", mut: { alt: 'E0/0' }, named: ['E0'] },
  { id: 'K7-hbar', mutation: 'default dimension = the value axis', mut: { alt: 'K7a/0' }, named: ['K7a'] },
  { id: 'K7-stack', mutation: 'the stack sum read', mut: { alt: 'K7b/1' }, named: ['K7b'] },
  { id: 'K7-scatter', mutation: 'the third column read from the store (absent)', mut: { alt: 'K7c/0' }, named: ['K7c'] },
  { id: 'K7-LG', mutation: 'line-gradient s1 dimension 0 ignored (default y read)', mut: { alt: 'LG/1' }, named: ['LG'] },
  // K8
  { id: 'K8-multiplied', mutation: 'stop values multiplied (e0 + step * i) instead of accumulated', mut: { multiplied: true }, named: ['E0', 'LG'] },
  { id: 'K8-loop', mutation: 'stop loop i < 200 instead of i <= 200', mut: { loop200: true }, named: ['LG'] },
  // K9
  { id: 'K9-noclip', mutation: 'no clipColorStops', mut: { noClip: true }, named: ['K9c'] },
  { id: 'K9-grid', mutation: 'clipped to the grid instead of the canvas', mut: { clipGrid: true }, named: ['K9c'] },
  { id: 'K9-tiny', mutation: 'tinyExtent 0 instead of 10', mut: { tiny0: true }, named: ['LG', 'K9c', 'K9d', 'K9e', 'K9f'] },
  { id: 'K9-outer', mutation: 'outerColors not reversed with the stops', mut: { noOuterReverse: true }, named: ['LG', 'K9f'] },
  { id: 'K9-linestyle', mutation: 'the gradient overrides an authored lineStyle.color', mut: { overrideLineStyle: true }, named: ['K9e'] },
  { id: 'K9-first', mutation: 'the first visualMeta on x or y, not the last', mut: { firstMeta: true }, named: ['K9g'] },
  // K10
  { id: 'K10-marker', mutation: 'DatumColour bypasses the visual row (series colour)', mut: { markerBypass: true }, named: ['LG'] },
];

// ---------- the run ----------
function generate() {
  VisualMappingClass = null;
  const subtype = SUBTYPES.map(recordSubtype);
  const charts = CHARTS.map(recordChart);
  must(VisualMappingClass && typeof VisualMappingClass.prepareVisualTypes === 'function', 'no VisualMapping class');
  const gradientColor = runChart({ series: [] }, ch => ch.getModel().get('gradientColor').slice());
  const gradientRec = gradientColor.map(colRec);

  // K8
  const stopRec = [];
  const pick = (cid, si) => {
    const c = charts.find(x => x.id === cid);
    const s = c.series.find(x => x.index === si);
    const meta = s.visualMeta[0];
    const vr = c.visualMaps.find(v => v.index === meta.vm);
    must(vr.rangeAuto, cid + ': K8 wants the full range');
    stopRec.push({ chart: cid, series: si, vm: meta.vm, extent: vr.extent, extentText: vr.extentText,
      count: meta.stops.length, values: meta.stops.map(x => x.value), valuesText: meta.stops.map(x => x.valueText) });
  };
  pick('E0', 0);
  pick('LG', 0);
  pick('LG', 1);

  // K5
  const sortCases = sortLists().map(l => {
    const real = l.slice().sort(cmp);
    const obj = {};
    l.forEach(k => { obj[k] = 1; });
    const up = VisualMappingClass.prepareVisualTypes(obj);
    must(up.join() === real.join(), 'prepareVisualTypes and Array.prototype.sort differ on ' + l.join());
    return { in: l, out: real };
  });

  // parse: the named strings, then every colour string the chart options hold
  const inOptions = new Set();
  charts.forEach(c => colourStringsIn(c.option.visualMap, inOptions));
  charts.forEach(c => seriesOptions(c.option).forEach(s => colourStringsIn(s, inOptions)));
  const parseList = Array.from(new Set(PARSE_REQUIRED.concat(PARSE_EXTRA, Array.from(inOptions).sort(),
    gradientColor)));
  const parse = recordParse(parseList);
  const fastLerp = recordFastLerp();

  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version
      + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED,
    api: {
      rowColor: "data.getItemVisual(i, 'style')[data.getVisual('drawType')] after setOption",
      rowOpacity: "data.getItemVisual(i, 'style').opacity",
      rowValue: 'data.getStore().get(data.getDimensionIndex(vm.getDataDimensionIndex(data)), i), as visualSolution.incrementalApplyVisual reads it',
      state: 'vm.getValueState(value)',
      seriesColor: "data.getVisual('style')[drawType] (getVisualFromData(data, 'color'))",
      visualMeta: "data.getVisual('visualMeta'); coord = axis.toGlobalCoord(axis.dataToCoord(stop.value))",
      polyline: 'chart.getViewOfSeriesModel(sm)._polyline.style.stroke',
      area: 'chart.getViewOfSeriesModel(sm)._polygon.style.fill',
      tooltipMarker: 'markerColor of sm.formatTooltip(row, true) (retrieveVisualColorForTooltipMarker)',
      order: 'VisualMapping.prepareVisualTypes(vm.targetVisuals[state])',
      parse: 'echarts.color.parse', fastLerp: 'echarts.color.fastLerp',
    },
    gradientColor: gradientRec,
    subtype, charts, stopValues: stopRec, sortCases, parse, fastLerp,
  };
  return { out, gradientColor, parseList, inOptions };
}

// the self-checks; returns the guards
function check(g) {
  const { out, gradientColor, inOptions } = g;
  const gc = gradientColor;
  // the default ramp through the transcribed modifyHSL
  const accent = C.parse(gc[1]);
  const light = modifyLightness(accent, 0.9);
  must(sameColour(out.gradientColor[0], light), 'modifyHSL(#5070dd, l 0.9) gives ' + light + ', upstream ' + gc[0]);
  must(gc[1] === '#5070dd', 'theme[0] is ' + gc[1]);
  // K1
  for (const r of out.subtype) {
    const shape = Object.assign({}, r.option.visualMap);
    must(subTypeOf(shape, {}) === r.subType, r.id + ': the rule gives ' + subTypeOf(shape, {}) + ', upstream ' + r.subType);
  }
  for (const id of ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7']) must(out.subtype.some(r => r.id === id), 'no subtype case ' + id);
  // the chart cases
  for (const c of out.charts) {
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    const diffs = transcribeCase(c, gc, {});
    must(!diffs.length, c.id + ': the transcription differs from upstream at ' + diffs.slice(0, 6).join('; '));
    for (const s of c.series) {
      if (s.tooltipMarker) {
        must(JSON.stringify(s.tooltipMarker.color) === JSON.stringify(s.rows[s.tooltipMarker.row].color),
          c.id + ' s' + s.index + ': the marker is not the row colour');
      }
    }
  }
  const E0 = out.charts.find(c => c.id === 'E0');
  must(E0.series[0].rows.length === 9, 'dataset-encode0 has ' + E0.series[0].rows.length + ' rows');
  // K8 values against the transcription
  for (const sv of out.stopValues) {
    const mine = stopValues(sv.extent.map(num), {}).map(hex);
    must(mine.join() === sv.values.join(), sv.chart + ' s' + sv.series + ': stop values differ');
  }
  const svE0 = out.stopValues.find(x => x.chart === 'E0');
  const svS1 = out.stopValues.find(x => x.chart === 'LG' && x.series === 1);
  must(svE0.count === 201 && svE0.valuesText[2] === '10.899999999999999', 'E0 stops: ' + svE0.count + ' ' + svE0.valuesText[2]);
  must(svS1.count === 202 && svS1.valuesText[200] === '48.999999999999865', 'LG s1 stops: ' + svS1.count + ' ' + svS1.valuesText[200]);
  // K5
  must(out.sortCases.length >= 60, out.sortCases.length + ' sort cases');
  for (const sc of out.sortCases) must(v8Sort(sc.in).join() === sc.out.join(), 'the V8 model differs on ' + sc.in.join());
  for (const l of AUDIT_LISTS) must(out.sortCases.some(sc => sc.in.join() === l.join()), 'no sort case ' + l.join());
  const tally = {};
  for (const k of ['identity', 'reverse', 'linearInsertion', 'binaryInsertionNoRun', 'runThenLinear']) {
    tally[k] = out.sortCases.filter(sc => SORTS[k](sc.in).join() !== sc.out.join()).length;
    must(tally[k] >= (k === 'runThenLinear' ? 3 : 5), 'only ' + tally[k] + ' sort cases tell ' + k + ' apart');
  }
  // parse
  for (const t of PARSE_REQUIRED) must(out.parse.some(p => p.in === t), 'no parse row for ' + t);
  for (const t of inOptions) must(out.parse.some(p => p.in === t), 'no parse row for the option colour ' + t);
  must(out.parse.filter(p => !p.ok).length >= 1, 'no unparsable string');
  for (const p of out.parse) {
    if (!p.ok) continue;
    must([p.r, p.g, p.b].every(Number.isInteger), p.in + ': a non-integer channel');
    const mine = parseTranscribed(p.in, {});
    if (mine === 'keyword') continue;
    must(mine && mine[0] === p.r && mine[1] === p.g && mine[2] === p.b && hex(mine[3]) === p.a,
      p.in + ': the parse transcription gives ' + JSON.stringify(mine));
  }
  for (const t of HALF_WAY) {
    const p = out.parse.find(x => x.in === t);
    const b = parseTranscribed(t, { bankers: true });
    must(p && !(b[0] === p.r && b[1] === p.g && b[2] === p.b), t + ": banker's rounding does not bite");
  }
  must(out.parse.find(p => p.in === 'rgb(30%,0,0)').r === 77, 'rgb(30%,0,0) is not 77');
  must(out.parse.find(p => p.in === 'rgba(0,0,180,0.4)').a === hex(0.4), 'rgba(0,0,180,0.4) alpha is not 0.4');
  // fastLerp
  for (const f of out.fastLerp) {
    const mine = fastLerp(num(f.n), f.colors.map(c => C.parse(c) || [0, 0, 0, 1]), {});
    must(JSON.stringify(tupRec(mine)) === JSON.stringify(f.result), f.id + ': the fastLerp transcription differs');
  }

  // the guards
  const guards = GUARDS.map(gd => {
    const changed = [];
    if (gd.kind === 'subtype') {
      for (const r of out.subtype) {
        const shape = Object.assign({}, r.option.visualMap);
        if (subTypeOf(shape, gd.mut) !== subTypeOf(shape, {})) changed.push(r.id);
      }
    } else if (gd.kind === 'gradientColor') {
      const wrong = modifyLightness(C.parse(gc[1]), 90);
      const gcWrong = ['rgba(' + wrong.join(',') + ')', gc[1]];
      for (const c of out.charts) {
        let d;
        try { d = transcribeCase(c, gcWrong, {}); } catch (e) { d = ['threw']; }
        if (d.length) changed.push(c.id);
      }
    } else {
      for (const c of out.charts) {
        let d;
        try { d = transcribeCase(c, gc, gd.mut); } catch (e) { d = ['threw: ' + e.message]; }
        if (d.length) changed.push(c.id);
      }
      for (const f of out.fastLerp) {
        let r;
        try { r = JSON.stringify(tupRec(fastLerp(num(f.n), f.colors.map(x => C.parse(x) || [0, 0, 0, 1]), gd.mut))); } catch (e) { r = 'threw'; }
        if (r !== JSON.stringify(f.result)) changed.push(f.id);
      }
      if (gd.mut.sort) {
        for (const sc of out.sortCases) if (SORTS[gd.mut.sort](sc.in).join() !== sc.out.join()) changed.push('S:' + sc.in.join());
      }
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)) };
  });
  return { guards, tally };
}

// the compact writer of box-merge.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(oneLine).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const f = oneLine(v);
  if (f.length + ind.length <= LINE || v === null || typeof v !== 'object') return f;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = v.map(x => fmt(x, inner));
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
let checked;
try {
  g1 = generate();
  checked = check(g1);
  g1.out.guards = checked.guards;
  json1 = fmt(g1.out, '') + '\n';
  const g2 = generate();
  g2.out.guards = check(g2).guards;
  json2 = fmt(g2.out, '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const out = g1.out;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.slice(0, 12).join(', ')
  + (gd.changed.length > 12 ? ', ...' : '')));
const deterministic = json1 === json2;
const rows = out.charts.reduce((n, c) => n + c.series.reduce((m, s) => m + s.rows.length, 0), 0);
console.log(out.subtype.length + ' subtype, ' + out.charts.length + ' chart cases (' + rows + ' rows), ' + out.stopValues.length
  + ' stop lists, ' + out.sortCases.length + ' sort cases (' + Object.keys(checked.tally).map(k => k + ' red on ' + checked.tally[k]).join(', ')
  + '), ' + out.parse.length + ' parse, ' + out.fastLerp.length + ' fastLerp; ' + (out.guards.length - bad.length) + '/'
  + out.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
