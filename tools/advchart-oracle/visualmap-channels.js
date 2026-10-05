// Upstream's own answers for the visualMap B3 batch (wf54/audit54.md section 2
// B3, cases C1..C7, recipes 1.4/1.5): the visual channels other than colour and
// opacity -- colorHue, colorSaturation, colorLightness and colorAlpha on the
// running colour, symbol, symbolSize and liftZ -- the item visuals of the
// per-datum series (pie, funnel, radar, gauge, graph) and of line symbols as
// their views draw them, the by-datum legend swatch (with its zero-alpha
// rescue), and the continuous component's controller symbolSize (the bar
// trapezoid, the handle thumb scale and the horizontal handle-label offset).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models, the data and the
// views directly -- never the SVG text. Every chart is disposed in a finally.
//
//   node tools/advchart-oracle/visualmap-channels.js
//
// writes tests/fixtures/advchart-visualmap-channels.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as visualmap-encode.js / visualmap-view.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase; every hex field has a readable twin (xText beside x).
//   colour   {css, r, g, b, a, aText, undef}: css is the string upstream
//            produced or was given; r, g, b the integers and a the hex alpha of
//            zrender's parse(css); undef true when upstream's value was
//            undefined (then css null, r = g = b = 0, a = 0). A paint that is
//            the string 'none' is {css: 'none', none: true, ...zeros}.
//   matrix   [m0..m5] hex + ...Text: zrender's [a, b, c, d, tx, ty]
//
// Top level
//   source, W, H, seed, api (how each value was read), notes[]
//   palette       ecModel.get('color'): the theme palette (the per-data palette
//                 of pie/funnel rows no visual touched)
//   gradientColor [colour, colour]: the default inRange ramp
//   legendInactiveColor  colour: legend inactiveColor (unselected swatches)
//   hsl[]         direct zrender calls (echarts.color.modifyHSL / modifyAlpha):
//                 {id, note, fn ('modifyHSL' | 'modifyAlpha'), color (css), h, s,
//                 l, alpha (each hex or null, + ...Text), result (colour)}
//   cases[]       one per chart:
//     id, groups (the audit cases it serves), note, width, height
//     gallery      the gallery file name or null; option: the option exactly as
//                  fed (null for graph-life-expectancy, 494 KB: load the gallery
//                  file, fed verbatim)
//     visualMaps[] in component order: index, subType, show, extent [hex, hex],
//                  range [hex, hex] (+Text), target (the completed option,
//                  JSON, key order as upstream holds it), controller (idem),
//                  order {inRange: [...], outOfRange: [...]} (prepareVisualTypes
//                  of targetVisuals[state]: the order the encoder applies them
//                  in), targets (series indices)
//     series[]     every series:
//       index, type, name, filtered (legend-filtered: not drawn, no rows),
//       drawType, colorBy, colorBySeries, colorFromPalette (the series-level
//       flag), color (colour: style[drawType], the base the encoder starts
//       from), opacity (hex|null), symbol (string|null), symbolSize ([hex..] |
//       null, + symbolSizeArray: true when upstream holds an array), targetedBy,
//       dims [{vm, dimIndex, dimName}]
//       rows[]     one per data index (not for filtered series):
//         i, name, skip (raw item {visualMap: false}), values [{vm, value (hex),
//         valueText, state}]
//         fill      colour: getItemVisual(i, 'style')[drawType] after every stage
//         stroke    colour|null: getItemVisual(i, 'style').stroke (context)
//         opacity   hex|null (+Text): getItemVisual(i, 'style').opacity
//         symbol    string|null: getItemVisual(i, 'symbol')
//         symbolSize [hex..]|null (+Text, symbolSizeArray)
//         liftZ     hex|null (+Text)
//         drawn     what the view drew for the row, by series type:
//           scatter/line/graph (SymbolDraw): null when no symbol element, else
//             {symbolType (the path's shape.symbolType), fill, stroke (colour|
//             null), lineWidth, opacity (hex|null), z2, scaleX, scaleY (hex)}
//           bar: {fill, opacity} of the rect; pie: {fill, opacity} of the sector; funnel: {fill, opacity} of the
//             polygon
//           radar: {polylineStroke, polygonFill, polygonOpacity, polygonIgnore,
//             symbols: [{symbolType, fill, stroke, lineWidth, opacity, z2,
//             scaleX, scaleY}]}
//           gauge: {pointerFill, pointerOpacity, progressFill (colour|null)}
//     legend       null, or {index, type, items[]}: per legend data item in
//                  order: name, branch ('series' | 'datum'), seriesIndex,
//                  dataIndex (datum: provider.indexOfName), selected,
//                  visualFill (colour: the style fill handed to _createItem
//                  BEFORE the zero-alpha rescue -- series colour or the item
//                  visual), visualOpacity (hex|null), icon {type, symbolType,
//                  fill, stroke, opacity (hex|null), lineWidth (hex|null)}
//     controllers[] (C5 cases) per shown continuous visualMap: vm, orient,
//                  itemSize, extent, interval, handleEnds (hex + Text),
//                  calculable, handleSize, hs (parsed handle size, hex),
//                  controllerSymbolSize {inRange, outOfRange} (the completed
//                  controller arrays, hex), barSymbolSize {inRange: at the
//                  interval ends, outOfRange: at the extent ends} (hex:
//                  getControllerVisual(v, 'symbolSize', {forceState})),
//                  barLocal (matrix: the bar group's local transform, as in
//                  visualmap-view.js), outOfRange/inRange {points} (bar-local,
//                  hex + Text), handles[] (calculable): {thumb {x, y, scaleX,
//                  scaleY, toGroup, global (matrices as in visualmap-view.js)},
//                  symbolSize (hex), label {string, x, y}} -- label x/y in
//                  view-group coordinates
//   guards[]      one per mutation: id, mutation, named (cases or case/series
//                 that must turn red), changed, ok
//
// ---------------------------------------------------------------------------
// Self-checks (any failure: nothing is written, exit 1):
//   - the transcription (zrUtil.merge + completeSingle + completeInactive, V8's
//     sort of prepareVisualTypes, linearMap + fastLerp + modifyHSL (rgba2hsla,
//     clampCssAngle, hsla2rgba with Math.round) + modifyAlpha, doMapToArray,
//     the numeric and fixed mappings, the per-row pipeline with visualMap:false,
//     the 4500 data itemStyle/symbol overrides and the per-data palette, the
//     SymbolDraw/Radar setColor rule, the funnel's own opacity, the legend
//     branches with the zero-alpha rescue, completeController's symbolSize with
//     the continuous ss0 = ss1 / 3, the bar trapezoid, the handle thumbs and the
//     horizontal label offset) gives every recorded value bit for bit;
//   - the direct hsl rows are the transcription's;
//   - audit anchors (scatter-aqi-color v = 9 -> symbolSize 402851eb851eb852;
//     C2 s0 red, s1 green; C4 indices; C7 swatch alpha 0.2);
//   - every guard is ok;
//   - two generations in the process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visualmap-channels.json');
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
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const numRecN = (name, v) => ({ [name]: hexOrNull(v), [name + 'Text']: textOrNull(v) });
const pairRec = (name, a) => ({ [name]: a.map(hex), [name + 'Text']: a.map(text) });

const UNDEF_COLOUR = { css: null, r: 0, g: 0, b: 0, a: hex(0), aText: '0', undef: true };
function colRec(c) {
  if (c == null) return Object.assign({}, UNDEF_COLOUR);
  if (c === 'none') return Object.assign({}, UNDEF_COLOUR, { css: 'none', undef: false, none: true });
  must(typeof c === 'string', 'a colour that is not a string: ' + JSON.stringify(c).slice(0, 80));
  const p = C.parse(c);
  must(p, 'an upstream colour that does not parse: ' + c);
  must([0, 1, 2].every(k => Number.isInteger(p[k])), 'a non-integer channel in ' + c);
  return { css: c, r: p[0], g: p[1], b: p[2], a: hex(p[3]), aText: text(p[3]), undef: false };
}
const colRecOrNull = c => (c == null ? null : colRec(c));
const tupleOf = rec => (rec == null || rec.undef || rec.none ? undefined : [rec.r, rec.g, rec.b, num(rec.a)]);
function sameColour(rec, t) {
  if (t === 'none') return !!(rec && rec.none);
  if (t == null) return !!(rec && rec.undef);
  return !!rec && !rec.undef && !rec.none && rec.r === t[0] && rec.g === t[1] && rec.b === t[2] && rec.a === hex(t[3]);
}
function sizeRec(name, v) {
  if (v == null) return { [name]: null, [name + 'Text']: null, [name + 'Array']: false };
  const arr = Array.isArray(v) ? v : [v];
  must(arr.every(x => typeof x === 'number'), name + ' not numeric: ' + JSON.stringify(v));
  return { [name]: arr.map(hex), [name + 'Text']: arr.map(text), [name + 'Array']: Array.isArray(v) };
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);

// ---------- the transcription (with the audit's mutations as switches) ----------

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
function clampAngle(i, mut) {
  if (mut.hueWrap) {
    i = Math.round(i);
    return ((i % 360) + 360) % 360;
  }
  if (!mut.hueNoRound) i = Math.round(i);
  return i < 0 ? 0 : i > 360 ? 360 : i;
}
const clampFloat = f => (f < 0 ? 0 : f > 1 ? 1 : f);
const lerpNumber = (a, b, p) => a + (b - a) * p;

// color.ts:402-438
function fastLerp(n, colors, mut) {
  if (!(colors && colors.length) || !(n >= 0 && n <= 1)) return undefined;
  const value = n * (colors.length - 1);
  const l = Math.floor(value);
  const r = Math.ceil(value);
  const lc = colors[l];
  const rc = colors[r];
  const dv = value - l;
  return [clampByte(lerpNumber(lc[0], rc[0], dv), mut), clampByte(lerpNumber(lc[1], rc[1], dv), mut),
    clampByte(lerpNumber(lc[2], rc[2], dv), mut), clampFloat(lerpNumber(lc[3], rc[3], dv))];
}

// color.ts:305-365 (hsla2rgba, cssHueToRgb), 281-303 (rgba2hsla), 507-541
function hueToRgb(m1, m2, h) {
  if (h < 0) h += 1;
  else if (h > 1) h -= 1;
  if (h * 6 < 1) return m1 + (m2 - m1) * h * 6;
  if (h * 2 < 1) return m2;
  if (h * 3 < 2) return m1 + (m2 - m1) * (2 / 3 - h) * 6;
  return m1;
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
function hslaToRgba(hsla, mut) {
  const h = (((hsla[0] % 360) + 360) % 360) / 360;
  const s = clampFloat(hsla[1]);
  const l = clampFloat(hsla[2]);
  const m2 = l <= 0.5 ? l * (s + 1) : l + s - l * s;
  const m1 = l * 2 - m2;
  return [clampByte(hueToRgb(m1, m2, h + 1 / 3) * 255, mut), clampByte(hueToRgb(m1, m2, h) * 255, mut),
    clampByte(hueToRgb(m1, m2, h - 1 / 3) * 255, mut), mut.alphaReset ? 1 : hsla[3]];
}
// modifyHSL on a tuple (upstream holds a css string; parse(stringify(t)) = t)
function modifyHSL(t, h, s, l, mut) {
  if (t == null) return undefined;
  const hsla = rgbaToHsla(t);
  if (mut.satIntoLight && s != null) { l = s; s = null; }
  if (h != null) hsla[0] = clampAngle(h, mut);
  if (s != null) hsla[1] = clampFloat(s);
  if (l != null) hsla[2] = clampFloat(l);
  return hslaToRgba(hsla, mut);
}
const modifyAlpha = (t, alpha) => (t == null || alpha == null ? undefined : [t[0], t[1], t[2], clampFloat(alpha)]);

// prepareVisualTypes: V8's TimSort for n < 64 (CountAndMakeRun, then
// BinaryInsertionSort), as visualmap-encode.js
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
const SORTS = { v8: v8Sort, identity: a => a.slice(), linearInsertion, binaryInsertionNoRun };
const sortTypes = (keys, mut) => SORTS[mut.sort || 'v8'](keys);

const VALID_TYPES = ['color', 'colorHue', 'colorSaturation', 'colorLightness', 'colorAlpha', 'opacity', 'symbol',
  'symbolSize', 'liftZ', 'decal'];
// visualDefault.ts:47-85, the inactive column (non-category); liftZ and decal have none
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
  zrMerge(target, base);
  if (Array.isArray(opt.color) && !target.inRange) target.inRange = { color: opt.color.slice().reverse() };
  target.inRange = target.inRange || { color: gradientColor.slice() };
  const exist = target.inRange;
  if (exist && !target.outOfRange) {
    const absent = target.outOfRange = {};
    for (const type of Object.keys(exist)) {
      if (!VALID_TYPES.includes(type)) continue;
      if (mut.noInactiveLightness && type === 'colorLightness') continue;
      const defa = clone(INACTIVE[type]);
      if (defa != null) {
        absent[type] = defa;
        if (type === 'color' && !hasOwn(absent, 'opacity') && !hasOwn(absent, 'colorAlpha')) absent.opacity = [0, 0];
      }
    }
  }
  return target;
}

// VisualMapModel.ts:564-618 + ContinuousModel.ts:163-175, symbolSize only
function completeControllerSymbolSize(opt, itemSize0, mut) {
  const base = { inRange: opt.inRange, outOfRange: opt.outOfRange };
  const controller = opt.controller ? clone(opt.controller) : {};
  zrMerge(controller, base);
  // completeSingle (a missing inRange gets a colour ramp: no symbolSize)
  if (Array.isArray(opt.color) && !controller.inRange) controller.inRange = { color: opt.color.slice().reverse() };
  controller.inRange = controller.inRange || { color: [] };
  const exists = (controller.inRange || {}).symbolSize || (controller.outOfRange || {}).symbolSize;
  const out = {};
  for (const state of ['inRange', 'outOfRange']) {
    const visuals = controller[state] || {};
    let ss = visuals.symbolSize != null ? clone(visuals.symbolSize) : (exists ? clone(exists) : [itemSize0, itemSize0]);
    must(Array.isArray(ss), 'a non-array controller symbolSize');
    let max = -Infinity;
    for (const v of ss) if (v > max) max = v;
    if (!mut.noRescale) ss = ss.map(v => linearMap(v, [0, max], [0, itemSize0], true));
    if (!mut.noThird && ss[0] !== ss[1]) ss[0] = ss[1] / 3;
    out[state] = ss;
  }
  return out;
}

// VisualMapping.ts:594-618 (normalizeVisualRange)
function visualArray(visual, type) {
  let arr = [];
  if (visual !== null && typeof visual === 'object') arr = Object.keys(visual).map(k => visual[k]);
  else if (visual != null) arr = [visual];
  if (arr.length === 1 && type !== 'color' && type !== 'symbol') arr[1] = arr[0];
  return arr;
}

// the continuous model (VisualMapModel.ts:413-423, ContinuousModel.ts:143-160, 207-216)
function modelOf(opt, gradientColor, mut) {
  const min = opt.min != null ? opt.min : 0;
  const max = opt.max != null ? opt.max : 200;
  const extent = [Math.min(min, max), Math.max(min, max)];
  let range;
  if (!opt.range || opt.range.auto) {
    range = extent.slice();
  } else {
    range = opt.range.slice();
    if (range[0] > range[1]) range.reverse();
    range[0] = Math.max(range[0], extent[0]);
    range[1] = Math.min(range[1], extent[1]);
  }
  const ub = opt.unboundedRange != null ? opt.unboundedRange : true;
  const target = completeTarget(opt, gradientColor, mut);
  const state = v => ((((ub && range[0] <= extent[0]) || range[0] <= v) && ((ub && range[1] >= extent[1]) || v <= range[1]))
    ? 'inRange' : 'outOfRange');
  const parsed = {};
  for (const st of ['inRange', 'outOfRange']) {
    parsed[st] = {};
    const m = target[st] || {};
    for (const type of Object.keys(m)) {
      if (!VALID_TYPES.includes(type)) continue;
      must(type !== 'decal', 'the transcription does not map decal');
      const arr = visualArray(m[type], type);
      parsed[st][type] = type === 'color' ? arr.map(c => C.parse(c) || [0, 0, 0, 1]) : arr;
    }
  }
  const normalize = v => linearMap(v, extent, [0, 1], true);
  // one visual type on the running item visuals (VisualMapping.ts visualHandlers)
  function apply(v, st, type, run) {
    const vis = parsed[st][type];
    const n = normalize(v);
    const numeric = () => linearMap(n, [0, 1], vis, true);
    switch (type) {
      case 'color':
        run.color = fastLerp(n, vis, mut);
        run.fromPalette = false;
        break;
      case 'colorHue':
        run.color = modifyHSL(run.color, numeric(), null, null, mut);
        run.fromPalette = false;
        break;
      case 'colorSaturation':
        run.color = modifyHSL(run.color, null, numeric(), null, mut);
        run.fromPalette = false;
        break;
      case 'colorLightness':
        run.color = modifyHSL(run.color, null, null, numeric(), mut);
        run.fromPalette = false;
        break;
      case 'colorAlpha':
        if (!mut.alphaIgnored) run.color = modifyAlpha(run.color, numeric());
        run.fromPalette = false;
        break;
      case 'opacity':
        run.opacity = numeric();
        break;
      case 'symbol': {
        // doMapToArray, VisualMapping.ts:627-632
        const x = linearMap(n, [0, 1], [0, vis.length - 1], true);
        const k = mut.symbolTrunc ? Math.trunc(x) : mut.symbolBankers ? bankers(x) : Math.round(x);
        run.symbol = vis[k] || {};
        break;
      }
      case 'symbolSize':
        if (!mut.symbolSizeIgnored) run.symbolSize = numeric();
        break;
      case 'liftZ':
        // doMapFixed: the first visual, whatever the value
        if (!mut.liftZIgnored) run.liftZ = mut.liftZLinear ? numeric() : vis[0];
        break;
      default:
        throw new OracleError('no transcription for ' + type);
    }
  }
  const order = st => sortTypes(Object.keys(target[st] || {}).filter(t => VALID_TYPES.includes(t)), mut);
  const orderUnmutated = st => v8Sort(Object.keys(target[st] || {}).filter(t => VALID_TYPES.includes(t)));
  return { extent, range, target, state, apply, order, orderUnmutated, normalize };
}

const vmOptions = option => {
  const v = option.visualMap;
  return v === undefined ? [] : Array.isArray(v) ? v : [v];
};
const seriesOptions = option => {
  const s = option.series;
  return Array.isArray(s) ? s : [s];
};
const isObj = v => v !== null && typeof v === 'object' && !Array.isArray(v);

// symbol.ts symbolPathSetColor after Symbol.ts useStyle(item style)
function symbolDrawn(symbol, fill, itemStroke, mut, lineSeries, seriesColour) {
  const empty = typeof symbol === 'string' && symbol.indexOf('empty') === 0;
  const colour = (mut.lineSeriesColour && lineSeries) ? seriesColour : fill;
  if (empty) {
    return { fill: mut.emptyFilled ? colour : [255, 255, 255, 1], stroke: colour, lineWidth: 2 };
  }
  return { fill: colour, stroke: itemStroke, lineWidth: null };
}

// the whole chart case from the option and the recorded inputs (values,
// series visuals, palette, recorded view matrices); returns the differing
// fields (empty = the transcription is upstream's)
function transcribeCase(c, top, mut) {
  const diffs = [];
  const opts = vmOptions(c.option);
  const gradientColor = top.gradientColor.map(r => r.css);
  const models = c.visualMaps.map(vr => modelOf(opts[vr.index], gradientColor, mut));
  c.visualMaps.forEach((vr, k) => {
    const m = models[k];
    if (JSON.stringify(vr.target) !== JSON.stringify(m.target)) diffs.push('vm' + vr.index + ' target');
    for (const st of ['inRange', 'outOfRange']) {
      if (vr.order[st].join() !== m.orderUnmutated(st).join()) diffs.push('vm' + vr.index + ' order ' + st);
    }
  });
  const sOpts = seriesOptions(c.option);
  const palette = top.palette;
  const scopes = new Map();
  const paletteColour = (s, name) => {
    const key = s.type + '-' + s.colorBy;
    let sc = scopes.get(key);
    if (!sc) { sc = { idx: 0, names: new Map() }; scopes.set(key, sc); }
    if (sc.names.has(name)) return sc.names.get(name);
    const col = palette[sc.idx];
    if (name) sc.names.set(name, col);
    sc.idx = (sc.idx + 1) % palette.length;
    return col;
  };
  const rowsBySeries = new Map();
  for (const s of c.series) {
    if (s.filtered) continue;
    const sOpt = sOpts[s.index];
    const seriesColor = tupleOf(s.color);
    const ignoreAll = (mut.graphIgnored && s.type === 'graph') || (mut.radarIgnored && s.type === 'radar')
      || (mut.gaugeIgnored && s.type === 'gauge');
    const out = [];
    s.rows.forEach((row, i) => {
      const raw = s.rawItems[i];
      const run = {
        color: seriesColor, opacity: s.opacity == null ? undefined : num(s.opacity),
        symbol: s.symbol, symbolSize: s.symbolSize == null ? undefined : (s.symbolSizeArray ? s.symbolSize.map(num) : num(s.symbolSize[0])),
        liftZ: undefined, fromPalette: s.colorFromPalette,
      };
      if (mut.basePalette && !s.colorBySeries) run.color = C.parse(palette[i % palette.length]);
      for (const vmIdx of s.targetedBy) {
        if (ignoreAll) break;
        if (raw && raw.visualMap === false) continue;
        const m = models[c.visualMaps.findIndex(vr => vr.index === vmIdx)];
        const rec = row.values.find(x => x.vm === vmIdx);
        const v = num(rec.value);
        const st = m.state(v);
        if (rec.state !== st) diffs.push('s' + s.index + ' row ' + i + ' state');
        for (const type of m.order(st)) m.apply(v, st, type, run);
      }
      // 4500: dataStyleTask, dataSymbolTask (the raw item's own keys), then the palette
      if (isObj(raw) && isObj(raw.itemStyle)) {
        if (raw.itemStyle.color != null) { run.color = C.parse(raw.itemStyle.color); run.fromPalette = false; }
        if (raw.itemStyle.opacity != null) run.opacity = raw.itemStyle.opacity;
      }
      if (isObj(raw)) {
        if (raw.symbol != null) run.symbol = raw.symbol;
        if (raw.symbolSize != null) run.symbolSize = raw.symbolSize;
      }
      if (run.fromPalette && !s.colorBySeries && !mut.skipKeepsSeries) {
        run.color = C.parse(paletteColour(s, row.name || String(i)));
      }
      const tag = 's' + s.index + ' row ' + i;
      if (!sameColour(row.fill, run.color)) diffs.push(tag + ' fill');
      if (row.opacity !== hexOrNull(run.opacity)) diffs.push(tag + ' opacity');
      if (row.symbol !== (run.symbol == null ? null : run.symbol)) diffs.push(tag + ' symbol');
      const ss = run.symbolSize == null ? null : (Array.isArray(run.symbolSize) ? run.symbolSize : [run.symbolSize]).map(hex);
      if (JSON.stringify(row.symbolSize) !== JSON.stringify(ss)) diffs.push(tag + ' symbolSize');
      if (row.liftZ !== hexOrNull(run.liftZ)) diffs.push(tag + ' liftZ');
      out.push(run);
      // what the view drew
      const d = row.drawn;
      const fill = tupleOf(row.fill);
      const itemStroke = row.stroke ? tupleOf(row.stroke) : undefined;
      if (s.type === 'scatter' || s.type === 'line' || s.type === 'graph' || s.type === 'effectScatter') {
        const noSymbol = (row.symbol === 'none' && !mut.noneDrawn) || (s.type === 'line' && s.showSymbol === false);
        if (noSymbol) {
          if (d !== null) diffs.push(tag + ' drawn (expected none)');
        } else if (d === null) {
          diffs.push(tag + ' drawn (missing)');
        } else {
          const want = symbolDrawn(row.symbol, fill, itemStroke, mut, s.type === 'line', seriesColor);
          if (!sameColour(d.fill, want.fill)) diffs.push(tag + ' drawn fill');
          if (want.stroke !== undefined || d.stroke) {
            if (!(want.stroke === undefined ? d.stroke == null : sameColour(d.stroke, want.stroke))) diffs.push(tag + ' drawn stroke');
          }
          if (want.lineWidth != null && d.lineWidth !== hex(want.lineWidth)) diffs.push(tag + ' drawn lineWidth');
          const op = row.opacity != null ? row.opacity : (d.opacity == null ? null : hex(1));
          if (d.opacity !== op) diffs.push(tag + ' drawn opacity');
          const sz = row.symbolSize.map(num);
          const wh = sz.length === 1 ? [sz[0], sz[0]] : sz;
          if (d.scaleX !== hex((wh[0] || 0) / 2) || d.scaleY !== hex((wh[1] || 0) / 2)) diffs.push(tag + ' drawn scale');
          const z2 = 100 + (row.liftZ == null || mut.liftZNotDrawn ? 0 : num(row.liftZ));
          if (d.z2 !== z2) diffs.push(tag + ' drawn z2');
        }
      } else if (s.type === 'bar') {
        // the rect's own opacity is 1 or unset when the item has none (context only)
        const op = row.opacity != null ? row.opacity : (d.opacity == null ? null : hex(1));
        if (!sameColour(d.fill, fill) || d.opacity !== op) diffs.push(tag + ' drawn rect');
      } else if (s.type === 'pie') {
        // as the bar: an unset item opacity is drawn as 1 or unset
        const op = row.opacity != null ? row.opacity : (d.opacity == null ? null : hex(1));
        if (!sameColour(d.fill, fill) || d.opacity !== op) diffs.push(tag + ' drawn sector');
      } else if (s.type === 'funnel') {
        // FunnelView.ts:59-78: the polygon's opacity is the item model's itemStyle.opacity (default 1)
        const own = isObj(raw) && isObj(raw.itemStyle) && raw.itemStyle.opacity != null ? raw.itemStyle.opacity
          : (sOpt.itemStyle && sOpt.itemStyle.opacity != null ? sOpt.itemStyle.opacity : 1);
        const op = mut.funnelVisualOpacity ? (row.opacity == null ? 1 : num(row.opacity)) : own;
        if (!sameColour(d.fill, fill) || d.opacity !== hex(op)) diffs.push(tag + ' drawn polygon');
      } else if (s.type === 'radar') {
        const lsc = sOpt.lineStyle && sOpt.lineStyle.color;
        if (!sameColour(d.polylineStroke, lsc != null ? C.parse(lsc) : fill)) diffs.push(tag + ' drawn polyline');
        const asc = sOpt.areaStyle && sOpt.areaStyle.color;
        if (!sameColour(d.polygonFill, asc != null ? C.parse(asc) : fill)) diffs.push(tag + ' drawn polygon');
        if (d.polygonIgnore !== !sOpt.areaStyle) diffs.push(tag + ' drawn polygon ignore');
        for (const sym of d.symbols) {
          const want = symbolDrawn(row.symbol, fill, itemStroke, mut, false, seriesColor);
          if (!sameColour(sym.fill, want.fill)) diffs.push(tag + ' drawn radar symbol');
          const sz = row.symbolSize.map(num);
          const wh = sz.length === 1 ? [sz[0], sz[0]] : sz;
          if (sym.scaleX !== hex(wh[0] / 2) || sym.scaleY !== hex(wh[1] / 2)) diffs.push(tag + ' drawn radar symbol scale');
        }
      } else if (s.type === 'gauge') {
        if (!sameColour(d.pointerFill, fill)) diffs.push(tag + ' drawn pointer');
        if (d.progressFill && !sameColour(d.progressFill, fill)) diffs.push(tag + ' drawn progress');
      }
    });
    rowsBySeries.set(s.index, out);
  }

  // the legend (LegendView.ts:190-320, getLegendStyle 600-680)
  if (c.legend) {
    const inactive = tupleOf(top.legendInactiveColor);
    for (const it of c.legend.items) {
      const tag = 'legend ' + it.name;
      const s = c.series.find(x => x.index === it.seriesIndex);
      let visual;
      let visualOpacity;
      if (it.branch === 'series' || mut.legendSeriesColour) {
        visual = tupleOf(s.color);
        visualOpacity = it.branch === 'series' ? (s.opacity == null ? undefined : num(s.opacity)) : undefined;
      } else {
        const r = rowsBySeries.get(s.index)[it.dataIndex];
        visual = r.color;
        visualOpacity = r.opacity;
      }
      if (!mut.legendSeriesColour && !sameColour(it.visualFill, visual)) diffs.push(tag + ' visual');
      let swatch = visual;
      if (it.branch === 'datum' && swatch && swatch[3] === 0 && !mut.noRescue) swatch = [swatch[0], swatch[1], swatch[2], 0.2];
      const iconFill = it.selected ? swatch : inactive;
      if (!sameColour(it.icon.fill, iconFill)) diffs.push(tag + ' icon fill');
      if (it.selected && it.branch === 'datum' && it.icon.opacity !== hexOrNull(visualOpacity)) diffs.push(tag + ' icon opacity');
    }
  }

  // the controllers
  for (const ct of c.controllers || []) {
    const tag = 'controller vm' + ct.vm;
    const opt = opts[ct.vm];
    const m = models[c.visualMaps.findIndex(vr => vr.index === ct.vm)];
    const is = ct.itemSize.map(num);
    const ss = completeControllerSymbolSize(opt, is[0], mut);
    for (const st of ['inRange', 'outOfRange']) {
      if (JSON.stringify(ct.controllerSymbolSize[st]) !== JSON.stringify(ss[st].map(hex))) diffs.push(tag + ' symbolSize ' + st);
    }
    const ssAt = (v, st) => linearMap(m.normalize(v), [0, 1], visualArray(ss[st], 'symbolSize'), true);
    const interval = ct.interval.map(num);
    const extent = ct.extent.map(num);
    const bar = { inRange: interval.map(v => ssAt(v, 'inRange')), outOfRange: extent.map(v => ssAt(v, 'outOfRange')) };
    for (const st of ['inRange', 'outOfRange']) {
      if (JSON.stringify(ct.barSymbolSize[st]) !== JSON.stringify(bar[st].map(hex))) diffs.push(tag + ' barSymbolSize ' + st);
    }
    const ends = interval.map(v => linearMap(v, extent, [0, is[1]], true));
    const pts = (e, sz) => [[is[0] - sz[0], e[0]], [is[0], e[0]], [is[0], e[1]], [is[0] - sz[1], e[1]]];
    const want = { outOfRange: pts([0, is[1]], bar.outOfRange), inRange: pts(ends, bar.inRange) };
    for (const st of ['inRange', 'outOfRange']) {
      if (JSON.stringify(ct[st].points) !== JSON.stringify(want[st].map(p => p.map(hex)))) diffs.push(tag + ' points ' + st);
    }
    if (ct.handles) {
      const L = ct.barLocal.map(num);
      const alignL = transformDirection('left', L);
      ct.handles.forEach((hd, i) => {
        const val = linearMap(ends[i], [0, is[1]], extent, true);
        const sz = ssAt(val, m.state(val));
        if (hd.symbolSize !== hex(sz)) diffs.push(tag + ' handle ' + i + ' symbolSize');
        const th = { x: is[0] - sz / 2, y: ends[i], scale: sz / is[0] };
        if (hd.thumb.x !== hex(th.x) || hd.thumb.y !== hex(th.y) || hd.thumb.scaleX !== hex(th.scale) || hd.thumb.scaleY !== hex(th.scale)) {
          diffs.push(tag + ' handle ' + i + ' thumb');
        }
        // graphic.getTransform(thumb, viewGroup) = barLocal * (thumbLocal * I)
        const T = mul(L, mul([th.scale, 0 * th.scale, 0 * th.scale, th.scale, th.x, th.y], [1, 0, 0, 1, 0, 0]));
        if (JSON.stringify(hd.thumb.toGroup) !== JSON.stringify(T.map(hex))) diffs.push(tag + ' handle ' + i + ' toGroup');
        const hs = num(ct.hs);
        const tp = [T[0] * hs + T[4], T[1] * hs + T[5]];
        if (ct.orient !== 'vertical' && !mut.noOffset) {
          tp[1] += (alignL === 'left' || alignL === 'top') ? (is[0] - sz) / 2 : (is[0] - sz) / -2;
        }
        if (hd.label.x !== hex(tp[0]) || hd.label.y !== hex(tp[1])) diffs.push(tag + ' handle ' + i + ' label');
      });
    }
  }
  return diffs;
}

// zrender matrix.mul, graphic.transformDirection (visualmap-view.js)
function mul(m1, m2) {
  return [
    m1[0] * m2[0] + m1[2] * m2[1],
    m1[1] * m2[0] + m1[3] * m2[1],
    m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4],
    m1[1] * m2[4] + m1[3] * m2[5] + m1[5],
  ];
}
function transformDirection(direction, m) {
  const hBase = (m[4] === 0 || m[5] === 0 || m[0] === 0) ? 1 : Math.abs(2 * m[4] / m[0]);
  const vBase = (m[4] === 0 || m[5] === 0 || m[2] === 0) ? 1 : Math.abs(2 * m[4] / m[2]);
  const x = direction === 'left' ? -hBase : direction === 'right' ? hBase : 0;
  const y = direction === 'top' ? -vBase : direction === 'bottom' ? vBase : 0;
  const v = [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  return Math.abs(v[0]) > Math.abs(v[1]) ? (v[0] > 0 ? 'right' : 'left') : (v[1] > 0 ? 'bottom' : 'top');
}

// ---------- the cases ----------
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);
const vm = (seriesIndex, inRange, extra) => Object.assign({ show: false, type: 'continuous', min: 0, max: 1, seriesIndex, inRange }, extra || {});
const barS = data => ({ type: 'bar', data });
const bars = (list) => ({
  xAxis: { type: 'category', data: cat(Math.max(...list.map(x => x[1].length))) }, yAxis: {},
  visualMap: list.map((x, k) => vm(k, x[0], x[2])), series: list.map(x => barS(x[1])),
});
const pieData = vals => vals.map((v, i) => (typeof v === 'object' ? Object.assign({ name: 'p' + i }, v) : { name: 'p' + i, value: v }));

const pieCustom = gallery('pie-custom');

const CASES = [
  { id: 'C1', groups: ['C1'], note: 'partial colour channels, one visualMap per bar series (seriesIndex): s0 colorLightness 0.2/0.5/0.7 on #5070dd; '
    + 's1 colorSaturation 0 (150.5: JS 151, banker\'s 150) and 0.3; s2 colorHue 200.4 -> 200, 359.6 -> 360 (= 0); s3 colorHue [0, 400]: '
    + '400 and 396 clamp to 360, 30 is half-way; s4 colorLightness keeps alpha 0.5; s5 colorAlpha overwrites it; s6 #ff0000 lightness '
    + '0.15/0.85 (76.5/178.5 half-way); s7 lightness on the series colour (palette[7]); s8 hue on grey (no effect); s9 key order '
    + 'colorLightness, color (sorted color first)',
  option: bars([
    [{ color: ['#5070dd'], colorLightness: [0.2, 0.7] }, [0, 0.6, 1]],
    [{ color: ['#5070dd'], colorSaturation: [0, 0.3] }, [0, 1, 0.5]],
    [{ color: ['#5070dd'], colorHue: [200.4, 359.6] }, [0, 1, 0.5]],
    [{ color: ['#5070dd'], colorHue: [0, 400] }, [1, 0.9, 0.99, 0.075]],
    [{ color: ['rgba(80,112,221,0.5)'], colorLightness: [0.3, 0.3] }, [0, 1]],
    [{ color: ['rgba(80,112,221,0.5)'], colorAlpha: [0.2, 0.9] }, [0, 1, 0.5]],
    [{ color: ['#ff0000'], colorLightness: [0.15, 0.85] }, [0, 1, 0.5, 0.25]],
    [{ colorLightness: [0.2, 0.8] }, [0, 1, 0.5]],
    [{ color: ['#808080'], colorHue: [120, 120] }, [0, 1]],
    [{ colorLightness: [0.3, 0.3], color: ['#ff0000'] }, [0, 1]],
  ]) },
  { id: 'C2', groups: ['C2'], note: "s0 inRange {color: ['#ff0000'], opacity: [1, 1], colorHue: [120, 120]}: V8 sorts colorHue, opacity, color -> red "
    + '(the hue is lost); s1 {color, colorHue} -> green',
  option: bars([
    [{ color: ['#ff0000'], opacity: [1, 1], colorHue: [120, 120] }, [0, 0.5, 1]],
    [{ color: ['#ff0000'], colorHue: [120, 120] }, [0, 0.5, 1]],
  ]) },
  { id: 'C3a', groups: ['C3'], note: "pie-custom (gallery): colorLightness [0, 1] on [80, 600] from the series itemStyle.color '#c23531'",
    gallery: 'pie-custom' },
  { id: 'C3b', groups: ['C3'], note: 'pie-custom plus a legend: the by-datum swatches are the item visuals',
    option: Object.assign(clone(pieCustom), { legend: { top: 'bottom' } }) },
  { id: 'C3c', groups: ['C3'], note: 'pie without a series colour: colorLightness [0.2, 0.8] starts from the series colour #5070dd for every slice; '
    + 'rows 1 and 3 (visualMap:false) take the per-data palette in request order (palette[0], palette[1])',
  option: { legend: {}, visualMap: { show: false, min: 0, max: 100, inRange: { colorLightness: [0.2, 0.8] } },
    series: [{ type: 'pie', data: pieData([10, { value: 30, visualMap: false }, 50, { value: 70, visualMap: false }, 90]) }] } },
  { id: 'C4a', groups: ['C4'], note: "symbol ['circle', 'rect', 'triangle', 'diamond'] on [0, 100] at 16, 17, 50, 83, 84: Math.round(n * 3) = 0, 1, 2, 2, 3",
    option: { xAxis: {}, yAxis: {}, visualMap: { show: false, min: 0, max: 100, dimension: 2, inRange: { symbol: ['circle', 'rect', 'triangle', 'diamond'] } },
      series: [{ type: 'scatter', data: [[1, 1, 16], [2, 2, 17], [3, 3, 50], [4, 4, 83], [5, 5, 84]] }] } },
  { id: 'C4b', groups: ['C4'], note: "symbol ['circle', 'none', 'pin'] at 25 (0.5: JS 1 'none', banker's 0), 75 (1.5 -> 2), 0: the 'none' row draws nothing",
    option: { xAxis: {}, yAxis: {}, visualMap: { show: false, min: 0, max: 100, dimension: 2, inRange: { symbol: ['circle', 'none', 'pin'] } },
      series: [{ type: 'scatter', data: [[1, 1, 25], [2, 2, 75], [3, 3, 0]] }] } },
  { id: 'C4c', groups: ['C4'], note: "symbol + symbolSize, range [20, 80]: outOfRange completes to symbol 'none' and symbolSize [0, 0]",
    option: { xAxis: {}, yAxis: {}, visualMap: { show: false, min: 0, max: 100, dimension: 2, range: [20, 80],
      inRange: { symbol: ['circle', 'rect'], symbolSize: [6, 18] } },
    series: [{ type: 'scatter', data: [[1, 1, 10], [2, 2, 20], [3, 3, 50], [4, 4, 80], [5, 5, 90]] }] } },
  { id: 'C5a', groups: ['C5'], note: 'scatter-aqi-color (gallery): vm0 symbolSize [10, 70] on dimension 2 (v 9 -> 12.16), vm1 colorLightness '
    + '[0.9, 0.5] on dimension 6; vm0 controller symbolSize rescaled to itemWidth 30 then ss0 = 30 / 3', gallery: 'scatter-aqi-color', controllers: true },
  { id: 'C5b', groups: ['C5'], note: 'controller symbolSize [10, 30], vertical, calculable, shown: rescaled to itemWidth 20, ss0 = 20 / 3; range [25, 75]',
    controllers: true,
    option: { xAxis: {}, yAxis: {}, visualMap: { type: 'continuous', min: 0, max: 100, dimension: 2, calculable: true, range: [25, 75],
      inRange: { symbolSize: [10, 30] } },
    series: [{ type: 'scatter', data: [[1, 1, 0], [2, 2, 30], [3, 3, 60], [4, 4, 100]] }] } },
  { id: 'C5c', groups: ['C5'], note: 'controller symbolSize [10, 30], horizontal, calculable, range [20, 80]: the handle labels move by (itemWidth - ss) / 2',
    controllers: true,
    option: { xAxis: {}, yAxis: {}, visualMap: { type: 'continuous', min: 0, max: 100, dimension: 2, calculable: true, range: [20, 80],
      orient: 'horizontal', left: 'center', inRange: { symbolSize: [10, 30], color: ['#5070dd', '#dd4444'] } },
    series: [{ type: 'scatter', data: [[1, 1, 0], [2, 2, 30], [3, 3, 60], [4, 4, 100]] }] } },
  { id: 'C5d', groups: ['C5'], note: 'range [0.1, 0.4] on [0, 7], itemHeight 150: the upper handle maps back to 0.4000000000000001, '
    + 'which is OUT of range, so it takes the out-of-range controller size (5), not the in-range one',
    controllers: true,
    option: { xAxis: {}, yAxis: {}, visualMap: { type: 'continuous', min: 0, max: 7, dimension: 2, calculable: true, range: [0.1, 0.4],
      itemHeight: 150, controller: { inRange: { symbolSize: [10, 30] }, outOfRange: { symbolSize: [5, 5] } } },
    series: [{ type: 'scatter', data: [[1, 1, 0], [2, 2, 0.2], [3, 3, 5]] }] } },
  { id: 'C6', groups: ['C6'], note: 'liftZ [5, 10] (doMapFixed: always 5, never interpolated) with range [0, 50]: out-of-range rows get no liftZ (no inactive default); '
    + 'the symbol z2 is 100 + liftZ',
  option: { xAxis: {}, yAxis: {}, visualMap: { show: false, min: 0, max: 100, dimension: 2, range: [0, 50],
    inRange: { color: ['#000000', '#ffffff'], liftZ: [5, 10] } },
  series: [{ type: 'scatter', data: [[1, 1, 10], [2, 2, 40], [3, 3, 60], [4, 4, 90]] }, { type: 'scatter', symbol: 'emptyRect', data: [[5, 5, 20]] }] } },
  { id: 'C7a', groups: ['C7'], note: 'pie, range [300, 600]: rows below get rgba(0,0,0,0) + opacity 0; the legend swatch alpha is rescued to 0.2 (its opacity stays 0)',
    option: { legend: {}, visualMap: { show: false, min: 0, max: 600, range: [300, 600], inRange: { color: ['#ff0000', '#0000ff'] } },
      series: [{ type: 'pie', data: pieData([100, 200, 350, 500]) }] } },
  { id: 'C7b', groups: ['C7'], note: "pie, outOfRange {color: ['rgba(200,0,0,0)']} (no opacity default): swatch rgba(200,0,0,0.2)",
    option: { legend: {}, visualMap: { show: false, min: 0, max: 600, range: [300, 600], inRange: { color: ['#ff0000', '#0000ff'] },
      outOfRange: { color: ['rgba(200,0,0,0)'] } }, series: [{ type: 'pie', data: pieData([100, 200, 350, 500]) }] } },
  { id: 'C7c', groups: ['C7'], note: 'pie, inRange {colorAlpha: [0, 1]} on the series colour: the lowest row has alpha 0 -> swatch 0.2',
    option: { legend: {}, visualMap: { show: false, min: 0, max: 100, inRange: { colorAlpha: [0, 1] } },
      series: [{ type: 'pie', data: pieData([0, 40, 100]) }] } },
  { id: 'C7d', groups: ['C7'], note: 'funnel, range [50, 100]: the out-of-range row is rgba(0,0,0,0) with item opacity 0, but FunnelView draws the polygon at '
    + 'the item model opacity (1); swatch alpha 0.2, opacity 0',
  option: { legend: {}, visualMap: { show: false, min: 0, max: 100, range: [50, 100], inRange: { color: ['#ff0000', '#0000ff'] } },
    series: [{ type: 'funnel', data: [{ name: 'a', value: 30 }, { name: 'b', value: 70 }, { name: 'c', value: 100 }] }] } },
  { id: 'C7e', groups: ['C7'], note: 'pie, inRange {colorLightness} only, range [300, 600]: outOfRange completes to colorLightness [0, 0] -> black, opaque',
    option: { legend: {}, visualMap: { show: false, min: 0, max: 600, range: [300, 600], inRange: { colorLightness: [0.3, 0.7] } },
      series: [{ type: 'pie', itemStyle: { color: '#c23531' }, data: pieData([100, 350, 500]) }] } },
  { id: 'L1', groups: ['line'], note: "line symbols take the row colour: s0 default emptyCircle (fill '#fff', stroke = row colour, lineWidth 2), "
    + "s1 symbol 'circle' (fill = row colour; row 1 itemStyle.color '#00aa00' wins), s2 its own visualMap with colorLightness + symbolSize",
  option: { xAxis: { type: 'category', data: cat(3) }, yAxis: {},
    visualMap: [{ show: false, min: 0, max: 100, seriesIndex: [0, 1], inRange: { color: ['#ff0000', '#0000ff'] } },
      { show: false, min: 0, max: 100, seriesIndex: 2, inRange: { color: ['#00ff00'], colorLightness: [0.3, 0.6], symbolSize: [4, 12] } }],
    series: [{ type: 'line', showSymbol: true, data: [0, 50, 100] },
      { type: 'line', symbol: 'circle', data: [10, { value: 60, itemStyle: { color: '#00aa00' } }, 90] },
      { type: 'line', symbol: 'rect', data: [20, 45, 70] }] } },
  { id: 'R1', groups: ['radar'], note: 'radar2 (gallery): 28 radar series, default dimension = the last indicator; by-datum scroll legend', gallery: 'radar2' },
  { id: 'R2', groups: ['radar'], note: 'radar with areaStyle and symbols: polyline, polygon and symbol fills follow the row; symbolSize from the visualMap',
    option: { legend: {}, radar: { indicator: [{ max: 100 }, { max: 100 }, { max: 100 }] },
      visualMap: { show: false, min: 0, max: 100, inRange: { color: ['#ff0000', '#0000ff'], symbolSize: [4, 10] } },
      series: [{ type: 'radar', areaStyle: {}, data: [{ name: 'A', value: [10, 20, 30] }, { name: 'B', value: [60, 70, 80] }] }] } },
  { id: 'G1', groups: ['gauge'], note: 'gauge with progress: the pointer and the progress arc take the row colour',
    option: { series: [{ type: 'gauge', progress: { show: true }, data: [{ value: 30, name: 'x' }, { value: 70, name: 'y' }] }],
      visualMap: { show: false, min: 0, max: 100, inRange: { color: ['#ff0000', '#0000ff'] } } } },
  { id: 'GL', groups: ['graph'], note: "graph-life-expectancy (gallery): dimension 1, default ramp; legend selectedMode 'single' filters every series but China",
    gallery: 'graph-life-expectancy', omitOption: true },
];

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

function symbolElRec(p) {
  return Object.assign({ symbolType: p.shape && p.shape.symbolType != null ? p.shape.symbolType : null,
    fill: colRecOrNull(p.style.fill), stroke: colRecOrNull(p.style.stroke) },
  numRecN('lineWidth', p.style.lineWidth), numRecN('opacity', p.style.opacity), { z2: p.z2 },
  numRec('scaleX', p.scaleX), numRec('scaleY', p.scaleY));
}

function drawnOf(chart, sm, data, i) {
  const el = data.getItemGraphicEl(i);
  switch (sm.subType) {
    case 'scatter':
    case 'line':
    case 'graph':
    case 'effectScatter': {
      if (!el) return null;
      const p = el.childAt(0);
      must(p && !p.isGroup, 'a symbol group without a path');
      return symbolElRec(p);
    }
    case 'bar':
      must(el && el.type === 'rect', 'no bar rect');
      return Object.assign({ fill: colRec(el.style.fill) }, numRecN('opacity', el.style.opacity));
    case 'pie':
      must(el && el.type === 'sector', 'no pie sector');
      return Object.assign({ fill: colRec(el.style.fill) }, numRecN('opacity', el.style.opacity));
    case 'funnel':
      must(el && el.type === 'polygon', 'no funnel polygon');
      return Object.assign({ fill: colRec(el.style.fill) }, numRecN('opacity', el.style.opacity));
    case 'radar': {
      must(el && el.isGroup, 'no radar item group');
      const pl = el.childAt(0);
      const pg = el.childAt(1);
      const syms = [];
      el.childAt(2).eachChild(p => syms.push(symbolElRec(p)));
      return Object.assign({ polylineStroke: colRec(pl.style.stroke), polygonFill: colRec(pg.style.fill) },
        numRecN('polygonOpacity', pg.style.opacity), { polygonIgnore: !!pg.ignore, symbols: syms });
    }
    case 'gauge': {
      const view = chart.getViewOfSeriesModel(sm);
      const prog = view._progressEls && view._progressEls[i];
      return Object.assign({ pointerFill: el ? colRec(el.style.fill) : null }, numRecN('pointerOpacity', el ? el.style.opacity : null),
        { progressFill: prog ? colRec(prog.style.fill) : null });
    }
    default:
      throw new OracleError('no drawn record for ' + sm.subType);
  }
}

function legendRec(chart, gm) {
  const lm = gm.getComponent('legend');
  if (!lm) return null;
  const view = chart.getViewOfComponentModel(lm);
  const items = view.getContentGroup().children().filter(g => !g.newline);
  const names = lm.getData().map(m => m.get('name')).filter(n => n !== '' && n !== '\n');
  const out = [];
  let k = 0;
  for (const name of names) {
    let rec = null;
    const sm = gm.getSeriesByName(name)[0];
    if (sm) {
      const d = sm.getData();
      const style = d.getVisual('style');
      rec = { name, branch: 'series', seriesIndex: sm.seriesIndex, dataIndex: null, visualFill: colRec(style[sm.visualDrawType]),
        visualOpacity: hexOrNull(style.opacity) };
    } else {
      gm.eachRawSeries(s => {
        if (rec || !s.legendVisualProvider || !s.legendVisualProvider.containName(name)) return;
        const pr = s.legendVisualProvider;
        const idx = pr.indexOfName(name);
        const style = pr.getItemVisual(idx, 'style');
        must(s.getData().getName(idx) === name, 'legend ' + name + ': the provider index is not the data index');
        rec = { name, branch: 'datum', seriesIndex: s.seriesIndex, dataIndex: idx, visualFill: colRec(style.fill),
          visualOpacity: hexOrNull(style.opacity) };
      });
    }
    if (!rec) continue;
    const g = items[k++];
    must(g, 'legend ' + name + ': no item group');
    const txt = g.children().find(ch => ch.type === 'text');
    must(txt && txt.style.text === name, 'legend item ' + k + ' is ' + (txt && txt.style.text) + ', not ' + name);
    const icon = g.childAt(0);
    must(!icon.isGroup, 'legend ' + name + ': a group icon');
    rec.selected = lm.isSelected(name);
    rec.icon = Object.assign({ type: icon.type, symbolType: icon.shape && icon.shape.symbolType != null ? icon.shape.symbolType : null,
      fill: colRecOrNull(icon.style.fill), stroke: colRecOrNull(icon.style.stroke) },
    numRecN('opacity', icon.style.opacity), numRecN('lineWidth', icon.style.lineWidth));
    out.push(rec);
  }
  must(k === items.length, 'legend: ' + items.length + ' item groups, ' + k + ' matched');
  return { index: lm.componentIndex, type: lm.subType, items: out };
}

function controllerRec(chart, vmModel) {
  const view = chart.getViewOfComponentModel(vmModel);
  const shapes = view._shapes;
  const is = vmModel.itemSize;
  const extent = vmModel.getExtent();
  const interval = vmModel.getSelected();
  const ends = interval.map(v => linearMap(v, extent, [0, is[1]], true));
  const ssF = (v, st) => view.getControllerVisual(v, 'symbolSize', { forceState: st, convertOpacityToAlpha: true });
  const ctl = vmModel.option.controller;
  const calculable = !!vmModel.get('calculable');
  const handleSize = vmModel.get('handleSize');
  const hs = typeof handleSize === 'string' && handleSize.lastIndexOf('%') >= 0 ? parseFloat(handleSize) / 100 * is[0] : parseFloat(handleSize);
  const main = shapes.mainGroup;
  const rec = Object.assign({ vm: vmModel.componentIndex, orient: vmModel.get('orient') }, pairRec('itemSize', is), pairRec('extent', extent),
    pairRec('interval', interval), pairRec('handleEnds', ends), { calculable, handleSize }, numRec('hs', hs), {
      controllerSymbolSize: { inRange: ctl.inRange.symbolSize.map(hex), outOfRange: ctl.outOfRange.symbolSize.map(hex) },
      controllerSymbolSizeText: { inRange: ctl.inRange.symbolSize.map(text), outOfRange: ctl.outOfRange.symbolSize.map(text) },
      barSymbolSize: { inRange: interval.map(v => hex(ssF(v, 'inRange'))), outOfRange: extent.map(v => hex(ssF(v, 'outOfRange'))) },
      barSymbolSizeText: { inRange: interval.map(v => text(ssF(v, 'inRange'))), outOfRange: extent.map(v => text(ssF(v, 'outOfRange'))) },
    }, pairRec('barLocal', main.getLocalTransform()), {
      outOfRange: { points: shapes.outOfRange.shape.points.map(p => p.map(hex)), pointsText: shapes.outOfRange.shape.points.map(p => p.map(text)) },
      inRange: { points: shapes.inRange.shape.points.map(p => p.map(hex)), pointsText: shapes.inRange.shape.points.map(p => p.map(text)) },
    });
  must(main.parent === view.group, 'the bar group is not a direct child of the view group');
  if (calculable) {
    rec.handles = [0, 1].map(i => {
      const th = shapes.handleThumbs[i];
      const lb = shapes.handleLabels[i];
      const val = linearMap(ends[i], [0, is[1]], extent, true);
      return {
        thumb: Object.assign(numRec('x', th.x), numRec('y', th.y), numRec('scaleX', th.scaleX), numRec('scaleY', th.scaleY),
          pairRec('toGroup', echarts.graphic.getTransform(th, view.group)), pairRec('global', echarts.graphic.getTransform(th))),
        symbolSize: hex(view.getControllerVisual(val, 'symbolSize')), symbolSizeText: text(view.getControllerVisual(val, 'symbolSize')),
        label: Object.assign({ string: lb.style.text }, numRec('x', lb.style.x), numRec('y', lb.style.y)),
      };
    });
  }
  return rec;
}

function recordCase(def) {
  const source = def.gallery ? gallery(def.gallery) : def.option;
  const optionText = JSON.stringify(source);
  const option = JSON.parse(optionText);
  return runChart(JSON.parse(optionText), chart => {
    const gm = chart.getModel();
    const vms = gm.findComponents({ mainType: 'visualMap' });
    const rec = { id: def.id, groups: def.groups, note: def.note, width: chart.getWidth(), height: chart.getHeight(),
      gallery: def.gallery || null, option: def.omitOption ? null : option };
    rec.visualMaps = vms.map(m => {
      must(m.subType === 'continuous', def.id + ': a ' + m.subType + ' visualMap');
      if (!VisualMappingClass) {
        const any = Object.keys(m.targetVisuals.inRange).map(k => m.targetVisuals.inRange[k])[0];
        if (any) VisualMappingClass = any.constructor;
      }
      const targets = [];
      gm.eachRawSeries(sm => { if (m.isTargetSeries(sm)) targets.push(sm.seriesIndex); });
      return Object.assign({ index: m.componentIndex, subType: m.subType, show: m.get('show') !== false },
        pairRec('extent', m.getExtent()), pairRec('range', m.option.range), {
          target: clone(m.option.target), controller: clone(m.option.controller),
          order: {
            inRange: VisualMappingClass.prepareVisualTypes(m.targetVisuals.inRange),
            outOfRange: VisualMappingClass.prepareVisualTypes(m.targetVisuals.outOfRange),
          },
          targets,
        });
    });
    rec.series = [];
    gm.eachRawSeries(sm => {
      const data = sm.getData();
      const drawType = data.getVisual('drawType');
      const sStyle = data.getVisual('style');
      const filtered = gm.isSeriesFiltered(sm);
      const targeting = vms.filter(m => m.isTargetSeries(sm));
      const s = Object.assign({
        index: sm.seriesIndex, type: sm.subType, name: sm.name, filtered, drawType, colorBy: sm.getColorBy(),
        colorBySeries: sm.isColorBySeries(), colorFromPalette: !!data.getVisual('colorFromPalette'),
        color: colRec(sStyle[drawType]), opacity: hexOrNull(sStyle.opacity),
        symbol: data.getVisual('symbol') == null ? null : data.getVisual('symbol'),
      }, sizeRec('symbolSize', data.getVisual('symbolSize')), {
        targetedBy: targeting.map(m => m.componentIndex),
        dims: targeting.map(m => {
          const dimIndex = m.getDataDimensionIndex(data);
          return { vm: m.componentIndex, dimIndex, dimName: data.getDimension(dimIndex) };
        }),
      });
      if (sm.subType === 'line') s.showSymbol = sm.get('showSymbol') !== false;
      Object.defineProperty(s, 'rawItems', { value: Array.from({ length: data.count() }, (_, i) => data.getRawDataItem(i)), enumerable: false });
      if (filtered) {
        s.rows = null;
        rec.series.push(s);
        return;
      }
      const store = data.getStore();
      s.rows = [];
      for (let i = 0; i < data.count(); i++) {
        const raw = data.getRawDataItem(i);
        const st = data.getItemVisual(i, 'style');
        const row = { i, name: data.getName(i) };
        if (raw && raw.visualMap === false) row.skip = true;
        row.values = targeting.map((m, k) => {
          const v = store.get(data.getDimensionIndex(s.dims[k].dimIndex), i);
          return { vm: m.componentIndex, value: hex(v), valueText: text(v), state: m.getValueState(v) };
        });
        const sym = data.getItemVisual(i, 'symbol');
        must(sym == null || typeof sym === 'string', def.id + ': a non-string symbol ' + JSON.stringify(sym));
        const lz = data.getItemVisual(i, 'liftZ');
        Object.assign(row, { fill: colRec(st[drawType]), stroke: colRecOrNull(st.stroke) }, numRecN('opacity', st.opacity),
          { symbol: sym == null ? null : sym }, sizeRec('symbolSize', data.getItemVisual(i, 'symbolSize')), numRecN('liftZ', lz),
          { drawn: drawnOf(chart, sm, data, i) });
        s.rows.push(row);
      }
      rec.series.push(s);
    });
    rec.legend = legendRec(chart, gm);
    if (def.controllers) rec.controllers = vms.filter(m => m.get('show') !== false).map(m => controllerRec(chart, m));
    return rec;
  });
}

// direct zrender calls
const HSL = [
  ['H1', 'modifyHSL', '#5070dd', null, null, 0.2, null, 'lightness 0.2'],
  ['H2', 'modifyHSL', '#5070dd', null, null, 0.5, null, 'lightness 0.5'],
  ['H3', 'modifyHSL', '#5070dd', null, null, 0.7, null, 'lightness 0.7'],
  ['H4', 'modifyHSL', '#5070dd', null, 0.3, null, null, 'saturation 0.3'],
  ['H5', 'modifyHSL', '#5070dd', null, 0, null, null, "saturation 0: 150.5 -> 151 (banker's 150)"],
  ['H6', 'modifyHSL', '#5070dd', 359.6, null, null, null, 'hue 359.6 -> 360 (= 0)'],
  ['H7', 'modifyHSL', '#5070dd', 200.4, null, null, null, 'hue 200.4 -> 200'],
  ['H8', 'modifyHSL', '#5070dd', 30, null, null, null, "hue 30: 150.5 -> 151 (banker's 150)"],
  ['H9', 'modifyHSL', '#5070dd', 400, null, null, null, 'hue 400 clamps to 360 (wrapping would give 40)'],
  ['H10', 'modifyHSL', '#5070dd', -0.4, null, null, null, 'hue -0.4 -> -0'],
  ['H11', 'modifyHSL', 'rgba(80,112,221,0.5)', null, null, 0.3, null, 'alpha 0.5 kept'],
  ['H12', 'modifyHSL', '#ff0000', null, null, 0.15, null, "76.5 -> 77 (banker's 76)"],
  ['H13', 'modifyHSL', '#808080', 120, null, null, null, 'hue on grey: no effect'],
  ['H14', 'modifyHSL', '#5070dd', null, null, 1.5, null, 'lightness clamped to 1'],
  ['H15', 'modifyAlpha', 'rgba(80,112,221,0.5)', null, null, null, 0.2, 'alpha replaced'],
  ['H16', 'modifyAlpha', '#5070dd', null, null, null, 1.5, 'alpha clamped to 1'],
  ['H17', 'modifyAlpha', '#5070dd', null, null, null, null, 'alpha null -> undefined'],
];
function recordHsl() {
  return HSL.map(([id, fn, color, h, s, l, alpha, note]) => {
    const r = fn === 'modifyHSL' ? C.modifyHSL(color, h, s, l) : C.modifyAlpha(color, alpha);
    return Object.assign({ id, note, fn, color }, numRecN('h', h), numRecN('s', s), numRecN('l', l), numRecN('alpha', alpha), { result: colRec(r) });
  });
}
function transcribeHsl(r, mut) {
  const t = C.parse(r.color);
  const n = x => (x == null ? null : num(x));
  return r.fn === 'modifyHSL' ? modifyHSL(t, n(r.h), n(r.s), n(r.l), mut) : (mut.alphaIgnored ? t : modifyAlpha(t, n(r.alpha)));
}

// ---------- the guards ----------
const GUARDS = [
  { id: 'C1-round', mutation: "FPC banker's Round in hsla2rgba/fastLerp", mut: { bankers: true }, named: ['C1/s1', 'C1/s3', 'C1/s6', 'H5', 'H8', 'H12'] },
  { id: 'C1-hueround', mutation: 'hue not rounded before hsla2rgba', mut: { hueNoRound: true }, named: ['C1/s2', 'H6', 'H7'] },
  { id: 'C1-huewrap', mutation: 'hue wrapped (mod 360) instead of clamped to 0..360', mut: { hueWrap: true }, named: ['C1/s3', 'H9'] },
  { id: 'C1-alpha', mutation: 'modifyHSL resets the alpha to 1', mut: { alphaReset: true }, named: ['C1/s4', 'H11'] },
  { id: 'C1-channel', mutation: 'colorSaturation written into the lightness', mut: { satIntoLight: true }, named: ['C1/s1', 'H4'] },
  { id: 'C1-coloralpha', mutation: 'colorAlpha ignored', mut: { alphaIgnored: true }, named: ['C1/s5', 'C7c', 'H15'] },
  { id: 'C2-identity', mutation: 'visuals applied in object key order', mut: { sort: 'identity' }, named: ['C2/s0'] },
  { id: 'C2-insertion', mutation: 'linear insertion sort with the comparator', mut: { sort: 'linearInsertion' }, named: ['C2/s0'] },
  { id: 'C2-binary', mutation: 'binary insertion sort without the run', mut: { sort: 'binaryInsertionNoRun' }, named: ['C2/s0'] },
  { id: 'C3-palette', mutation: 'partial colour starts from the per-data palette colour, not the series colour', mut: { basePalette: true },
    named: ['C3a', 'C3c'] },
  { id: 'C3-skip', mutation: 'a visualMap:false pie row keeps the series colour instead of the per-data palette', mut: { skipKeepsSeries: true },
    named: ['C3c'] },
  { id: 'C3-legend', mutation: 'by-datum legend swatches take the series colour', mut: { legendSeriesColour: true },
    named: ['C3b', 'C3c', 'C7a', 'R1', 'R2'] },
  { id: 'C4-trunc', mutation: 'Trunc instead of JS Math.round for the symbol index', mut: { symbolTrunc: true }, named: ['C4a', 'C4b'] },
  { id: 'C4-bankers', mutation: "banker's rounding for the symbol index", mut: { symbolBankers: true }, named: ['C4b'] },
  { id: 'C4-none', mutation: "a 'none' symbol drawn", mut: { noneDrawn: true }, named: ['C4b', 'C4c'] },
  { id: 'C5-third', mutation: 'no ss0 = ss1 / 3 for the continuous controller', mut: { noThird: true }, named: ['C5a', 'C5b', 'C5c'] },
  { id: 'C5-rescale', mutation: 'controller symbolSize not rescaled to itemSize[0]', mut: { noRescale: true }, named: ['C5a', 'C5b', 'C5c'] },
  { id: 'C5-offset', mutation: 'horizontal handle label not moved by (itemSize0 - symbolSize) / 2', mut: { noOffset: true }, named: ['C5c'] },
  { id: 'C5-size', mutation: 'the visualMap symbolSize ignored (the series symbolSize kept)', mut: { symbolSizeIgnored: true },
    named: ['C5a', 'C4c', 'L1', 'R2'] },
  { id: 'C6-ignored', mutation: 'liftZ ignored', mut: { liftZIgnored: true }, named: ['C6'] },
  { id: 'C6-linear', mutation: 'liftZ interpolated like symbolSize instead of the first visual', mut: { liftZLinear: true }, named: ['C6'] },
  { id: 'C6-z2', mutation: 'liftZ not added to the symbol z2', mut: { liftZNotDrawn: true }, named: ['C6'] },
  { id: 'C7-rescue', mutation: 'no zero-alpha rescue in the by-datum legend', mut: { noRescue: true }, named: ['C7a', 'C7b', 'C7c', 'C7d'] },
  { id: 'C7-funnel', mutation: 'the funnel polygon takes the visual opacity', mut: { funnelVisualOpacity: true }, named: ['C7d'] },
  { id: 'C7-lightness', mutation: 'completeInactive gives colorLightness no [0, 0] default', mut: { noInactiveLightness: true }, named: ['C7e'] },
  { id: 'L-series', mutation: 'line symbols painted in the series colour (the port today)', mut: { lineSeriesColour: true }, named: ['L1'] },
  { id: 'L-empty', mutation: "an empty symbol filled with the colour instead of '#fff'", mut: { emptyFilled: true }, named: ['L1', 'C6'] },
  { id: 'R-ignored', mutation: 'radar ignores the visualMap', mut: { radarIgnored: true }, named: ['R1', 'R2'] },
  { id: 'G-ignored', mutation: 'gauge ignores the visualMap', mut: { gaugeIgnored: true }, named: ['G1'] },
  { id: 'GL-ignored', mutation: 'graph nodes ignore the visualMap', mut: { graphIgnored: true }, named: ['GL'] },
];

// ---------- the run ----------
function generate() {
  VisualMappingClass = null;
  const cases = CASES.map(recordCase);
  must(VisualMappingClass, 'no VisualMapping class');
  const top = runChart({ series: [], legend: {} }, ch => {
    const gm = ch.getModel();
    return { palette: gm.get('color').slice(), gradientColor: gm.get('gradientColor').map(colRec),
      legendInactiveColor: colRec(gm.getComponent('legend').get('inactiveColor')) };
  });
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version
      + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED,
    api: {
      rowFill: "data.getItemVisual(i, 'style')[data.getVisual('drawType')] after setOption",
      rowOpacity: "data.getItemVisual(i, 'style').opacity",
      rowSymbol: "data.getItemVisual(i, 'symbol' | 'symbolSize' | 'liftZ')",
      rowValue: 'data.getStore().get(data.getDimensionIndex(vm.getDataDimensionIndex(data)), i); state = vm.getValueState(value)',
      drawnSymbol: 'data.getItemGraphicEl(i).childAt(0) (the Symbol path): style.fill/stroke/lineWidth/opacity, z2, scaleX/Y',
      drawnPie: 'data.getItemGraphicEl(i) (sector / funnel polygon) style.fill, style.opacity',
      drawnRadar: 'data.getItemGraphicEl(i): childAt(0) polyline, childAt(1) polygon, childAt(2) symbol group',
      drawnGauge: 'data.getItemGraphicEl(i) (pointer) style.fill; view._progressEls[i].style.fill',
      legend: "legend view getContentGroup() item groups in order: childAt(0) the icon; branch as LegendView.render (getSeriesByName, else legendVisualProvider); visualFill = the style fill handed to _createItem",
      controller: "view._shapes (mainGroup, inRange, outOfRange, handleThumbs, handleLabels); view.getControllerVisual(v, 'symbolSize', ...)",
      hsl: 'echarts.color.modifyHSL(color, h, s, l) / modifyAlpha(color, alpha)',
    },
    notes: [
      'colorHue/Saturation/Lightness/Alpha start from the item colour AT THAT MOMENT (getItemVisual style[drawType]): the series colour, or what an earlier visual type of the same state wrote. Setting any colour channel clears colorFromPalette, so the per-data palette (4500, pie/funnel colorBy data) never replaces it; a visualMap:false row keeps colorFromPalette and takes the palette colour in request order (C3c: palette[0], palette[1]).',
      'hsla2rgba rounds with Math.round (JS, half up) and clampCssAngle rounds the hue then clamps to 0..360 (not wraps). Clamping before rounding is the same function, so that audit mutation is not observable; wrapping is.',
      "liftZ uses doMapFixed for every mapping method: the FIRST visual value, never interpolated (C6: [5, 10] gives 5 everywhere). It has no inactive default, so out-of-range rows get none. Symbol.ts adds it once to the symbol path's z2 (100).",
      "symbol uses doMapToArray: visual[Math.round(linearMap(n, [0, 1], [0, len - 1], true))] || {}; outOfRange completes to ['none'] and SymbolDraw draws nothing for 'none'.",
      'SymbolDraw (scatter, line, graph) paints with the item style: the row colour goes to fill, or for an empty* symbol to stroke with fill #fff and lineWidth 2 -- also for line series (the port paints line symbols in the series colour).',
      'FunnelView (FunnelView.ts:59-78) overwrites the polygon opacity with the item model itemStyle.opacity (default 1): the visual opacity 0 of an out-of-range row is NOT drawn (the fill rgba(0,0,0,0) hides it). Pie sectors keep the visual opacity.',
      'The by-datum legend (LegendView.ts:269-279) lifts a zero alpha to 0.2 in the swatch fill, but the swatch opacity still inherits the item opacity (0 under the default outOfRange completion: C7a/C7d), so the rescued swatch is invisible there; with an explicit outOfRange colour and no opacity (C7b) it shows at 0.2. The series-name branch uses the series colour (data.getVisual style), never a visual.',
      "Pie, funnel, radar, gauge and graph all take the visualMap colour (none is skipped). Graph: legend-filtered series (selectedMode 'single' in graph-life-expectancy) are not encoded and not drawn: filtered true, rows null.",
      "The continuous controller symbolSize: completeController rescales so the max is itemSize[0], then ContinuousModel sets ss0 = ss1 / 3 whenever ss0 != ss1 (scatter-aqi-color: [10, 70] -> [4.28.., 30] -> [10, 30]). The handle thumbs use getControllerVisual(value) with the value's own state; the horizontal handle label moves by +-(itemSize0 - ss) / 2 (dist/echarts.js:90640-90643).",
    ],
    palette: top.palette, gradientColor: top.gradientColor, legendInactiveColor: top.legendInactiveColor,
    hsl: recordHsl(), cases,
  };
  return { out, top };
}

function caseUnits(c, diffs) {
  // the case id, and case/sN for every series with a differing field
  const units = new Set();
  if (diffs.length) units.add(c.id);
  for (const d of diffs) {
    const m = /^s(\d+) /.exec(d);
    if (m) units.add(c.id + '/s' + m[1]);
  }
  return Array.from(units);
}

function check(g) {
  const { out } = g;
  const top = { palette: out.palette, gradientColor: out.gradientColor, legendInactiveColor: out.legendInactiveColor };
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    if (!c.option) c.option = gallery(c.gallery);
    const diffs = transcribeCase(c, top, {});
    must(!diffs.length, c.id + ': the transcription differs from upstream at ' + diffs.slice(0, 6).join('; '));
  }
  for (const r of out.hsl) {
    must(sameColour(r.result, transcribeHsl(r, {})), r.id + ': the hsl transcription differs');
  }
  // audit anchors
  const aqi = byId.C5a.series[0];
  const r9 = aqi.rows.find(r => r.values.find(v => v.vm === 0).valueText === '9');
  must(r9 && r9.symbolSize[0] === '402851eb851eb852', 'scatter-aqi-color v 9 symbolSize ' + (r9 && r9.symbolSizeText));
  const c2 = byId.C2.series;
  must(c2[0].rows.every(r => r.fill.r === 255 && r.fill.g === 0 && r.fill.b === 0), 'C2 s0 is not red');
  must(c2[1].rows.every(r => r.fill.r === 0 && r.fill.g === 255 && r.fill.b === 0), 'C2 s1 is not green');
  must(byId.C4a.series[0].rows.map(r => r.symbol).join() === 'circle,rect,triangle,triangle,diamond', 'C4a symbols ' + byId.C4a.series[0].rows.map(r => r.symbol));
  must(byId.C4b.series[0].rows[0].symbol === 'none' && byId.C4b.series[0].rows[0].drawn === null, 'C4b row 0');
  for (const id of ['C7a', 'C7b', 'C7c', 'C7d']) {
    must(byId[id].legend.items.some(it => it.visualFill.a === hex(0) && it.icon.fill.a === hex(0.2)), id + ': no rescued swatch');
  }
  must(byId.C3c.series[0].rows[1].fill.css === out.palette[0] && byId.C3c.series[0].rows[3].fill.css === out.palette[1], 'C3c palette rows');
  must(byId.GL.series.filter(s => !s.filtered).length === 1 && byId.GL.series.find(s => !s.filtered).rows.length === 81, 'GL shape');

  const guards = GUARDS.map(gd => {
    const changed = [];
    for (const c of out.cases) {
      let d;
      try { d = transcribeCase(c, top, gd.mut); } catch (e) { d = ['threw: ' + e.message]; }
      changed.push(...caseUnits(c, d));
    }
    for (const r of out.hsl) {
      let same;
      try { same = sameColour(r.result, transcribeHsl(r, gd.mut)); } catch (e) { same = false; }
      if (!same) changed.push(r.id);
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(n => changed.includes(n)) };
  });
  return guards;
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

// the option of an omitOption case is loaded for the check only, never written
function serialise(out) {
  const copy = Object.assign({}, out, {
    cases: out.cases.map(c => (CASES.find(d => d.id === c.id).omitOption ? Object.assign({}, c, { option: null }) : c)),
  });
  return fmt(copy, '') + '\n';
}

let g1;
let json1;
let json2;
try {
  g1 = generate();
  g1.out.guards = check(g1);
  json1 = serialise(g1.out);
  const g2 = generate();
  g2.out.guards = check(g2);
  json2 = serialise(g2.out);
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const out = g1.out;
const bad = out.guards.filter(gd => !gd.ok);
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named '
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.slice(0, 14).join(', ')
  + (gd.changed.length > 14 ? ', ...' : '')));
const deterministic = json1 === json2;
const rows = out.cases.reduce((n, c) => n + c.series.reduce((m, s) => m + (s.rows ? s.rows.length : 0), 0), 0);
console.log(out.cases.length + ' cases (' + rows + ' rows), ' + out.hsl.length + ' hsl rows; ' + (out.guards.length - bad.length) + '/'
  + out.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
