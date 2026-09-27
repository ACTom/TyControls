// Upstream's own answers for the visualMap B4 batch (wf54/audit54.md section 1.8
// and section 2 B4; upstream54.md sections 3.6, 4.3, 7.4, all re-verified here):
// the PIECEWISE visualMap -- the piece list the model holds after resetMethods
// (splitNumber with its precision auto-derivation and write-back, pieces with
// min/max/lt/lte/gt/gte/value and reformIntervals, categories reversed when
// vertical), the selected map, the completed target and controller visuals and
// the mappings built from them, the per-row encoding of the targeted series
// (piece index, state, colour, opacity, symbol, symbolSize), the piecewise
// visualMeta and the line gradient built from it, and PiecewiseView: the item
// groups (symbol + label), the ends texts, layout.box, the background and where
// positionGroup puts the view group.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models, the data stores
// and the views directly -- never the SVG text. VisualMapView.prototype.
// renderBackground and .positionGroup and PiecewiseView.prototype._enableHoverLink
// are wrapped (the originals still run) to capture the group's bounding rect at
// the two moments upstream reads it and to tag each item group with its piece
// index. Every chart is disposed in a finally.
//
//   node tools/advchart-oracle/visualmap-piecewise.js
//
// writes tests/fixtures/advchart-visualmap-piecewise.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as visualmap-encode.js / visualmap-view.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (+Infinity 7ff0000000000000, -Infinity fff0000000000000,
//            NaN 7ff8000000000000). Every hex field has a readable twin (xText
//            beside x; String(v), '-0' for negative zero).
//   colour   {css, r, g, b, a, aText, undef}: css is the string upstream produced
//            or was given, r/g/b/a zrender's parse of it (a hex); undef true when
//            upstream's value was undefined (css null, zeros).
//   rect     {x, y, width, height} hex + rectText.
//   paint    {kind: 'color', color} | {kind: 'gradient', type, global, x, y, x2,
//            y2 (hex + text), stops [{offset, offsetText, color}]}
//
// Text sizes: measure[] holds zrender's own measurer answer per (string, font)
// (echarts.format.getTextRect: measureWidth + getLineHeight), as in
// visualmap-view.js. A Text element's rect unions its TSpan rect with itself:
// width = (x + w) - x; the transcription derives it from measure[].
//
// Top level
//   source, W, H, seed, api, notes[], gradientColor [colour, colour]
//   measure[]   {string, font, width, widthText, height, heightText}
//   cases[]     one per chart:
//     id, groups (the audit cases it serves), note, width, height, gallery (file
//     name or null), componentOnly (true: no series record), option (the option
//     as fed; null for the big gallery files line-aqi and candlestick-brush:
//     load the gallery file, fed verbatim)
//     visualMaps[] in component order:
//       index, subType ('piecewise'), show, mode ('splitNumber' | 'pieces' |
//       'categories': PiecewiseModel._mode)
//       resolved  the model's inputs to the view: orient, inverse, align (option,
//                 'auto' by default), itemSize [hex, hex], itemGap, textGap
//                 (hex), padding (option JSON) + paddingNorm [t, r, b, l] hex,
//                 text (option.text or null), showLabel (option.showLabel or
//                 null), itemSymbol, selectedMode, font, textStyle {align,
//                 verticalAlign, opacity} (null when unset), boxOption,
//                 boxParams (JSON), backgroundColor, borderColor (colour),
//                 borderWidth (hex), contentColor, inactiveColor (colour)
//       model     extent [hex, hex]; splitNumber and precision AS THE MODEL HOLDS
//                 THEM after resetMethods (the splitNumber path writes both
//                 back); precisionOption (the option as written, or null);
//                 minOpen, maxOpen, formatter (string or null), categories
//                 (option.categories or null); selected (option.selected after
//                 _resetSelected, JSON, key order as upstream holds it);
//                 optionInRange, optionOutOfRange (option.inRange/outOfRange
//                 after completeVisualOption -- the piece visual types are
//                 completed into them), target, controller (the completed
//                 objects, JSON, key order as upstream holds it); order
//                 {inRange, outOfRange} = prepareVisualTypes(targetVisuals
//                 [state]), controllerOrder (idem, controllerVisuals); targets
//                 (series indices)
//       mappings  {target|controller: {inRange|outOfRange: [{type, method
//                 ('piecewise' | 'category'), visual (JSON of the mapping's
//                 option.visual), visualDefault (the category default slot
//                 visual[-1], JSON, or null), categories (the mapping's own
//                 categories after the trailing pop, or null), hasSpecialVisual
//                 (piecewise), alpha (true for the hidden __alphaForOpacity
//                 colorAlpha mapping)}]}}
//       pieces[]  getPieceList() in model order: k, index (null for categories),
//                 interval [hex, hex] + intervalText (null for categories),
//                 close [0|1, 0|1] (null), value (hex for a number, null) +
//                 valueText (String(value) or null) + valueString (a category
//                 string or null), text, visual (piece.visual: null, or the
//                 visual types in handler order, colours as colour records),
//                 originIndex (the mapping clone's, null for categories), key
//                 (getSelectedMapKey), selected (option.selected[key]),
//                 representValue (hex + Text; a category string in
//                 representString), state (getValueState(representValue))
//       view      (show only)
//         itemAlign  view._getItemAlign(); labels (the items carry a label =
//                    showLabel), endsText (the view order, or null)
//         group      {x, y} after positionGroup
//         children[] the view group's children in drawn order, before the
//                    background: {kind: 'endText' | 'piece', pieceIndex (the
//                    model index; piece only), x, y (after layout.box), rect
//                    (the child group's own getBoundingRect), symbol (piece):
//                    {symbolType, shape {x, y, width, height}, fill, stroke
//                    (colour | null), lineWidth, silent, rect}, label (piece,
//                    null when not drawn) / text (endText): {string, x, y,
//                    align, verticalAlign, font, fill, opacity (hex | null),
//                    rect}}
//         bboxBackground  {rect}: the group's rect as renderBackground read it
//         background      {shape, fill, stroke (colour), lineWidth, z2, rect}
//         bboxPosition    {before {x, y}, rect (with the background), layoutRect
//                         (getLayoutRect({width, height} + boxParams, [0, 0, W,
//                         H]), no margin), after {x, y}}
//     series[] (not componentOnly) the targeted series: index, type, drawType,
//       color (colour: style[drawType], the base), opacity (hex | null), symbol
//       (string | null), symbolSize (JSON | null), targetedBy, dims [{vm,
//       dimIndex, dimName}]
//       rows[]    one per data index: i, rawIndex, skip (raw item {visualMap:
//                 false}), values [{vm, value (hex | null), valueText,
//                 valueString (a string store value or null), piece
//                 (VisualMapping.findPieceIndex(value, pieceList), null when none),
//                 closest (the normaliser's findPieceIndex(..., true)), state}],
//                 fill (colour), opacity (hex | null + Text), symbol (JSON |
//                 null), symbolSize (JSON | null)
//       visualMeta[]  data.getVisual('visualMeta'): vm, dimension, coordDim,
//                 outerColors [colour, colour], stops [{value, valueText, color,
//                 coord (line on x/y only), coordText}]
//       line only: grid (rect hex + text), lineStyleColorWritten, polyline
//                 (paint), area (paint | null)
//   guards[]    one per mutation: id, mutation, named (cases that must turn
//               red), changed (cases the mutated transcription no longer
//               reproduces), ok = named is a subset of changed, differs (the
//               first differing fields of each named case)
//
// ---------------------------------------------------------------------------
// The transcription (checked field by field against every recorded value) is
// the preprocessor, PiecewiseModel (resetMethods, reformIntervals with V8's sort,
// formatValueText with JS toFixed, _resetSelected, completeVisualOption +
// VisualMapModel.completeVisualOption, getValueState, getRepresentValue,
// getVisualMeta), VisualMapping (piecewise and category normalisers,
// findPieceIndex, getSpecifiedVisual, preprocessForPiecewise /
// preprocessForSpecifiedCategory, normalizeVisualRange, the colour / opacity /
// colorAlpha / symbol / symbolSize handlers, fastLerp + stringify), the per-row
// encoder with the 4500 itemStyle override, LineView's getVisualGradient +
// clipColorStops, and PiecewiseView (item order, symbol shapes, label and ends
// text positions, text rects from measure[], layout.box, renderBackground,
// positionGroup / getLayoutRect). Its inputs are the option as fed, `resolved`,
// measure[], the recorded store values and the recorded axis coords of the
// visualMeta stops.
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every case; the written JSON parses back to the record; audit anchors (P2 precision 5, P3 171.42857999999998,
// P5 the value piece deleted, the vertical categories reversed, p5 (d) ys 0,
// 23, 47 ...); every guard is ok; two generations in the process give the same
// bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visualmap-piecewise.json');
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

// ---------- number, rect and colour records ----------
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
const RK = ['x', 'y', 'width', 'height'];
const rectRec = r => ({
  rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
  rectText: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) },
});
const rectOf = rr => ({ x: num(rr.rect.x), y: num(rr.rect.y), width: num(rr.rect.width), height: num(rr.rect.height) });
const rectKey = r => RK.map(k => hex(r[k])).join(',');
const recRectKey = rr => RK.map(k => rr.rect[k]).join(',');

const UNDEF_COLOUR = { css: null, r: 0, g: 0, b: 0, a: hex(0), aText: '0', undef: true };
function colRec(c) {
  if (c == null) return Object.assign({}, UNDEF_COLOUR);
  must(typeof c === 'string', 'a colour that is not a string: ' + JSON.stringify(c).slice(0, 80));
  const p = C.parse(c);
  must(p, 'an upstream colour that does not parse: ' + JSON.stringify(c));
  must([0, 1, 2].every(k => Number.isInteger(p[k])), 'a non-integer channel in ' + c);
  return { css: c, r: p[0], g: p[1], b: p[2], a: hex(p[3]), aText: text(p[3]), undef: false };
}
const colRecOrNull = c => (c == null ? null : colRec(c));
const colKey = c => (c == null ? 'undef' : JSON.stringify(colRec(c)));
const recColKey = rec => (rec == null ? 'null' : rec.undef ? 'undef' : JSON.stringify(rec));
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
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const json = v => (v === undefined ? 'undefined' : JSON.stringify(v));

// ---------- text measurement (zrender's own measurer) ----------
let MEASURE = new Map();
function measureRaw(string, font) {
  const key = font + '\u0001' + string;
  let m = MEASURE.get(key);
  if (!m) {
    const r = echarts.format.getTextRect(string, font);
    m = { string, font, width: r.width, height: r.height };
    MEASURE.set(key, m);
  }
  return m;
}

// =====================================================================
// The transcription (mutations as switches in `mut`)
// =====================================================================

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

// zrender color.ts: clampCssByte / clampCssFloat, fastLerp, stringify, modifyAlpha
const clampByte = i => { i = Math.round(i); return i < 0 ? 0 : i > 255 ? 255 : i; };
const clampFloat = f => (f < 0 ? 0 : f > 1 ? 1 : f);
const lerpNumber = (a, b, p) => a + (b - a) * p;
function fastLerp(n, colors) {
  if (!(colors && colors.length) || !(n >= 0 && n <= 1)) return undefined;
  const value = n * (colors.length - 1);
  const l = Math.floor(value);
  const r = Math.ceil(value);
  const lc = colors[l];
  const rc = colors[r];
  const dv = value - l;
  return [clampByte(lerpNumber(lc[0], rc[0], dv)), clampByte(lerpNumber(lc[1], rc[1], dv)),
    clampByte(lerpNumber(lc[2], rc[2], dv)), clampFloat(lerpNumber(lc[3], rc[3], dv))];
}
function stringifyRgba(t) {
  if (!t || !t.length) return undefined;
  return 'rgba(' + t[0] + ',' + t[1] + ',' + t[2] + ',' + t[3] + ')';
}
function modifyAlpha(css, alpha) {
  const t = css ? C.parse(css) : undefined;
  if (t && alpha != null) {
    const u = t.slice();
    u[3] = clampFloat(alpha);
    return stringifyRgba(u);
  }
  return undefined;
}
// color.ts lerp (strings in, 'rgba' string out), for clipColorStops
function lerpCss(p, c0, c1) {
  if (!(p >= 0 && p <= 1)) return undefined;
  const t = fastLerp(p, [C.parse(c0), C.parse(c1)]);
  return stringifyRgba(t);
}

// V8's Array.prototype.sort for n < 64 (CountAndMakeRun, then BinaryInsertionSort),
// with any comparator; as visualmap-encode.js
function v8Sort(input, cmp) {
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
const typeCmp = (t1, t2) => ((t2 === 'color' && t1 !== 'color' && t1.indexOf('color') === 0) ? 1 : -1);
const prepareVisualTypes = keys => v8Sort(keys, typeCmp);

// VisualMapping.visualHandlers key order (listVisualTypes, retrieveVisuals)
const VISUAL_TYPES = ['color', 'colorHue', 'colorSaturation', 'colorLightness', 'colorAlpha', 'decal', 'opacity', 'liftZ',
  'symbol', 'symbolSize'];
const CATEGORY_DEFAULT_VISUAL_INDEX = -1;
const isObject = v => typeof v === 'function' || (!!v && typeof v === 'object');

// visualDefault.ts
const VISUAL_DEFAULT = {
  color: { active: ['#006edd', '#e0ffff'], inactive: ['rgba(0,0,0,0)'] },
  colorHue: { active: [0, 360], inactive: [0, 0] },
  colorSaturation: { active: [0.3, 1], inactive: [0, 0] },
  colorLightness: { active: [0.9, 0.5], inactive: [0, 0] },
  colorAlpha: { active: [0.3, 1], inactive: [0, 0] },
  opacity: { active: [0.3, 1], inactive: [0, 0] },
  symbol: { active: ['circle', 'roundRect', 'diamond'], inactive: ['none'] },
  symbolSize: { active: [10, 50], inactive: [0, 0] },
};
function visualDefaultGet(type, key, isCategory) {
  const value = clone((VISUAL_DEFAULT[type] || {})[key]);
  return isCategory ? (Array.isArray(value) ? value[value.length - 1] : value) : value;
}

// VisualMapping.findPieceIndex (VisualMapping.ts:475-540)
function findPieceIndex(value, pieceList, findClosest, mut) {
  mut = mut || {};
  let possibleI;
  let abs = Infinity;
  const updatePossible = (val, index) => {
    const newAbs = Math.abs(val - value);
    if (newAbs < abs) {
      abs = newAbs;
      possibleI = index;
    }
  };
  for (let i = 0; i < pieceList.length; i++) {
    const pieceValue = pieceList[i].value;
    if (pieceValue != null && !mut.noValuePass) {
      if (pieceValue === value || (typeof pieceValue === 'string' && pieceValue === value + '')) return i;
      findClosest && updatePossible(pieceValue, i);
    }
  }
  const lt = (close, a, b) => ((close || mut.closeIgnored) ? a <= b : a < b);
  for (let i = 0; i < pieceList.length; i++) {
    const piece = pieceList[i];
    const interval = piece.interval;
    const close = piece.close;
    if (interval) {
      if (interval[0] === -Infinity) {
        if (lt(close[1], value, interval[1])) return i;
      } else if (interval[1] === Infinity) {
        if (lt(close[0], interval[0], value)) return i;
      } else if (lt(close[0], interval[0], value) && lt(close[1], value, interval[1])) {
        return i;
      }
      findClosest && updatePossible(interval[0], i);
      findClosest && updatePossible(interval[1], i);
    }
  }
  if (findClosest) {
    if (mut.noClosest) return undefined;
    return value === Infinity ? pieceList.length - 1 : value === -Infinity ? 0 : possibleI;
  }
  return undefined;
}

// one VisualMapping (VisualMapping.ts:173-206 + handlers + normalisers), piecewise
// and category only
function makeMapping(option, mut) {
  const o = clone(option);
  const m = { type: o.type, method: o.mappingMethod, option: o };
  if (o.mappingMethod === 'piecewise') {
    normalizeVisualRange(o, false);
    o.hasSpecialVisual = false;
    o.pieceList.forEach((piece, index) => {
      piece.originIndex = index;
      if (piece.visual != null) o.hasSpecialVisual = true;
    });
  } else if (o.mappingMethod === 'category') {
    must(o.categories, 'a category mapping without categories');
    const categories = o.categories;
    const categoryMap = o.categoryMap = {};
    let visual = option.visual;
    categories.forEach((cate, index) => { categoryMap[cate] = index; });
    if (!Array.isArray(visual)) {
      const arr = [];
      if (isObject(visual)) {
        for (const cate of Object.keys(visual)) {
          const index = categoryMap[cate];
          arr[index != null ? index : CATEGORY_DEFAULT_VISUAL_INDEX] = visual[cate];
        }
      } else {
        arr[CATEGORY_DEFAULT_VISUAL_INDEX] = visual;
      }
      visual = arr;
    } else {
      visual = clone(visual);
    }
    setVisualToOption(o, visual);
    for (let i = categories.length - 1; i >= 0; i--) {
      if (visual[i] == null) {
        delete categoryMap[categories[i]];
        categories.pop();
      }
    }
  } else {
    throw new OracleError('no transcription for mapping method ' + o.mappingMethod);
  }
  const normalize = value => {
    if (o.mappingMethod === 'piecewise') {
      const pieceIndex = findPieceIndex(value, o.pieceList, true, mut);
      if (pieceIndex != null) return linearMap(pieceIndex, [0, o.pieceList.length - 1], [0, 1], true);
      return undefined;
    }
    const index = o.categoryMap[value];
    return index == null ? CATEGORY_DEFAULT_VISUAL_INDEX : index;
  };
  const specified = value => {
    if (o.hasSpecialVisual && !mut.specialIgnored) {
      const piece = o.pieceList[findPieceIndex(value, o.pieceList, false, mut)];
      if (piece && piece.visual) return piece.visual[m.type];
    }
    return undefined;
  };
  const doMapCategory = n => o.visual[n];
  const doMapToArray = n => o.visual[Math.round(linearMap(n, [0, 1], [0, o.visual.length - 1], true))] || {};
  const numeric = (n, value) => {
    if (o.mappingMethod === 'category') return doMapCategory(n);
    let r = specified(value);
    if (r == null) r = linearMap(n, [0, 1], o.visual, true);
    return r;
  };
  m.mapValueToVisual = value => {
    const n = normalize(value);
    switch (m.type) {
      case 'color': {
        if (o.mappingMethod === 'category') return doMapCategory(n);
        let r = specified(value);
        if (r == null) r = stringifyRgba(fastLerp(n, o.parsedVisual));
        return r;
      }
      case 'symbol': {
        if (o.mappingMethod === 'category') return doMapCategory(n);
        let r = specified(value);
        if (r == null) r = doMapToArray(n);
        return r;
      }
      case 'opacity':
      case 'symbolSize':
      case 'colorAlpha':
        return numeric(n, value);
      case 'liftZ':
        return o.visual[0];
      default:
        throw new OracleError('no transcription for the visual type ' + m.type);
    }
  };
  m.applyVisual = (value, getter, setter) => {
    const v = m.mapValueToVisual(value);
    if (m.type === 'colorAlpha') setter('color', modifyAlpha(getter('color'), v));
    else setter(m.type, v);
  };
  return m;
}
// VisualMapping.ts:594-618, 693-705
function normalizeVisualRange(o, isCategory) {
  const visual = o.visual;
  const arr = [];
  if (isObject(visual)) {
    for (const k of Object.keys(visual)) arr.push(visual[k]);
  } else if (visual != null) {
    arr.push(visual);
  }
  if (!isCategory && arr.length === 1 && o.type !== 'color' && o.type !== 'symbol') arr[1] = arr[0];
  setVisualToOption(o, arr);
}
function setVisualToOption(o, arr) {
  o.visual = arr;
  if (o.type === 'color') o.parsedVisual = arr.map(item => C.parse(item) || [0, 0, 0, 1]);
}

// zrender util.ts merge (overwrite false)
function zrMerge(target, source) {
  const plain = v => v !== null && typeof v === 'object' && !Array.isArray(v);
  for (const key in source) {
    if (!hasOwn(source, key)) continue;
    if (plain(source[key]) && plain(target[key])) zrMerge(target[key], source[key]);
    else if (!(key in target)) target[key] = clone(source[key]);
  }
  return target;
}
function mapVisual(visual, cb) {
  if (Array.isArray(visual)) return visual.map(v => cb(v));
  if (isObject(visual)) {
    const o = {};
    for (const k of Object.keys(visual)) o[k] = cb(visual[k]);
    return o;
  }
  return cb(visual);
}
function eachVisual(visual, cb) {
  if (isObject(visual)) for (const k of Object.keys(visual)) cb(visual[k]);
  else cb(visual);
}

// preprocessor.ts (ec2 splitList, start/end)
function preprocess(opt) {
  const o = clone(opt);
  if (hasOwn(o, 'splitList') && !hasOwn(o, 'pieces')) {
    o.pieces = o.splitList;
    delete o.splitList;
  }
  if (Array.isArray(o.pieces)) {
    for (const piece of o.pieces) {
      if (isObject(piece)) {
        if (hasOwn(piece, 'start') && !hasOwn(piece, 'min')) piece.min = piece.start;
        if (hasOwn(piece, 'end') && !hasOwn(piece, 'max')) piece.max = piece.end;
      }
    }
  }
  return o;
}

// util/number.ts reformIntervals (number.ts:716-756); dist/echarts.js:8168
function reformIntervals(list, mut) {
  const littleThan = (a, b, lg) => a.interval[lg] < b.interval[lg]
    || (a.interval[lg] === b.interval[lg]
      && ((a.close[lg] - b.close[lg] === (!lg ? 1 : -1)) || (!lg && littleThan(a, b, 1))));
  if (!mut.noSort) {
    const sorted = v8Sort(list, (a, b) => (littleThan(a, b, 0) ? -1 : 1));
    list.length = 0;
    sorted.forEach(x => list.push(x));
  }
  let curr = -Infinity;
  let currClose = 1;
  for (let i = 0; i < list.length;) {
    const interval = list[i].interval;
    const close = list[i].close;
    for (let lg = 0; lg < 2; lg++) {
      if (!mut.noClampSweep && interval[lg] <= curr) {
        interval[lg] = curr;
        close[lg] = !lg ? 1 - currClose : 1;
      }
      curr = interval[lg];
      currClose = close[lg];
    }
    if (!mut.noSplice && interval[0] === interval[1] && close[0] * close[1] !== 1) list.splice(i, 1);
    else i++;
  }
  return list;
}

// VisualMapModel.formatValueText (VisualMapModel.ts:351-408)
function formatValueText(env, value, isCategory, edgeSymbols) {
  const dataBound = [-Infinity, Infinity];
  const formatter = env.formatter;
  edgeSymbols = edgeSymbols || ['<', '>'];
  let isMinMax = false;
  if (Array.isArray(value)) {
    value = value.slice();
    isMinMax = true;
  }
  const toFixed = val => (val === dataBound[0] ? 'min' : val === dataBound[1] ? 'max' : (+val).toFixed(Math.min(env.precision, 20)));
  const textValue = isCategory ? value : (isMinMax ? [toFixed(value[0]), toFixed(value[1])] : toFixed(value));
  if (typeof formatter === 'string') {
    return formatter.replace('{value}', isMinMax ? textValue[0] : textValue).replace('{value2}', isMinMax ? textValue[1] : textValue);
  }
  must(formatter == null, 'a function formatter');
  if (isMinMax) {
    if (value[0] === dataBound[0]) return edgeSymbols[0] + ' ' + textValue[1];
    if (value[1] === dataBound[1]) return edgeSymbols[1] + ' ' + textValue[0];
    return textValue[0] + ' - ' + textValue[1];
  }
  return textValue;
}

const MODEL_DEFAULTS = { min: 0, max: 200, splitNumber: 5, precision: 0, orient: 'vertical', inverse: false, selectedMode: 'multiple',
  itemSymbol: 'roundRect', minOpen: false, maxOpen: false };

// the whole piecewise model from the option as fed (+ env: gradientColor,
// inactiveColor, contentColor, itemSize); PiecewiseModel.ts:130-163, 443-595
function buildModel(rawOpt, env, mut) {
  const opt = preprocess(rawOpt);
  const get = k => (opt[k] != null ? opt[k] : MODEL_DEFAULTS[k]);
  const min = get('min');
  const max = get('max');
  const extent = mut.noAsc ? [min, max] : [Math.min(min, max), Math.max(min, max)];
  const orient = get('orient');
  const inverse = get('inverse');
  const mode = opt.pieces && opt.pieces.length > 0 ? 'pieces' : opt.categories ? 'categories' : 'splitNumber';
  const isCategory = !!opt.categories;
  const fenv = { formatter: opt.formatter, precision: get('precision') };
  const pieceList = [];
  let splitNumberOut = get('splitNumber');
  const reverse = () => {
    if (mut.noCategoryReverse && mode === 'categories') return;
    if (orient === 'vertical' ? !inverse : inverse) pieceList.reverse();
  };
  if (mode === 'splitNumber') {
    let precision = Math.min(get('precision'), 20);
    let splitNumber = Math.max(parseInt(get('splitNumber'), 10), 1);
    splitNumberOut = splitNumber;
    let splitStep = (extent[1] - extent[0]) / splitNumber;
    while (!mut.noAutoPrecision && +splitStep.toFixed(precision) !== splitStep && precision < 5) precision++;
    if (!mut.noWriteBack) fenv.precision = precision;
    splitStep = +splitStep.toFixed(precision);
    if (get('minOpen')) pieceList.push({ interval: [-Infinity, extent[0]], close: [0, 0] });
    for (let index = 0, curr = extent[0]; index < splitNumber; curr += splitStep, index++) {
      const lo = mut.multiplied ? extent[0] + splitStep * index : curr;
      const hi = index === splitNumber - 1 && !mut.lastNotExtent ? extent[1] : lo + splitStep;
      pieceList.push({ interval: [lo, hi], close: [1, 1] });
    }
    if (get('maxOpen')) pieceList.push({ interval: [extent[1], Infinity], close: [0, 0] });
    reformIntervals(pieceList, mut);
    pieceList.forEach((piece, index) => {
      piece.index = index;
      piece.text = formatValueText(fenv, piece.interval);
    });
  } else if (mode === 'categories') {
    for (const cate of opt.categories) pieceList.push({ text: formatValueText(fenv, cate, true), value: cate });
    reverse();
  } else {
    opt.pieces.forEach((raw, index) => {
      const item = { text: '', index };
      if (!isObject(raw)) raw = { value: raw };
      if (raw.label != null) item.text = raw.label;
      if (hasOwn(raw, 'value')) {
        const value = item.value = raw.value;
        item.interval = [value, value];
        item.close = [1, 1];
      } else {
        const interval = item.interval = [];
        const close = item.close = [0, 0];
        const closeList = [1, 0, 1];
        const useMinMax = [];
        for (let lg = 0; lg < 2; lg++) {
          const names = [['gte', 'gt', 'min'], ['lte', 'lt', 'max']][lg];
          for (let i = 0; i < 3 && interval[lg] == null; i++) {
            interval[lg] = raw[names[i]];
            close[lg] = closeList[i];
            useMinMax[lg] = i === 2;
          }
          if (interval[lg] == null) interval[lg] = [-Infinity, Infinity][lg];
        }
        if (useMinMax[0] && interval[1] === Infinity) close[0] = 0;
        if (useMinMax[1] && interval[0] === -Infinity) close[1] = 0;
        if (interval[0] === interval[1] && close[0] && close[1]) item.value = interval[0];
      }
      // VisualMapping.retrieveVisuals: handler order
      let visual = null;
      for (const t of VISUAL_TYPES) {
        if (hasOwn(raw, t)) {
          visual = visual || {};
          visual[t] = raw[t];
        }
      }
      item.visual = visual;
      pieceList.push(item);
    });
    reverse();
    reformIntervals(pieceList, mut);
    for (const piece of pieceList) {
      const close = piece.close;
      const edges = [['<', '\u2264'][close[1]], ['>', '\u2265'][close[0]]];
      piece.text = piece.text || formatValueText(fenv, piece.value != null ? piece.value : piece.interval, false, edges);
    }
  }

  // _resetSelected
  const selected = opt.selected ? clone(opt.selected) : {};
  const keyOf = piece => (mode === 'categories' ? piece.value + '' : piece.index + '');
  for (const piece of pieceList) {
    const key = keyOf(piece);
    if (!hasOwn(selected, key)) selected[key] = true;
  }
  if (get('selectedMode') === 'single' && !mut.noSingle) {
    let hasSel = false;
    for (const piece of pieceList) {
      const key = keyOf(piece);
      if (selected[key]) {
        if (hasSel) selected[key] = false;
        else hasSel = true;
      }
    }
  }

  // completeVisualOption: PiecewiseModel.ts:169-210, VisualMapModel.ts:484-619
  const option = { inRange: clone(opt.inRange), outOfRange: clone(opt.outOfRange), target: clone(opt.target), controller: clone(opt.controller) };
  for (const k of ['inRange', 'outOfRange', 'target', 'controller']) if (option[k] === undefined) delete option[k];
  const typesInPieces = {};
  for (const piece of opt.pieces || []) {
    for (const t of VISUAL_TYPES) if (hasOwn(piece, t)) typesInPieces[t] = 1;
  }
  const has = (obj, st, t) => !!(obj && obj[st] && hasOwn(obj[st], t));
  if (!mut.noPieceDefaults) {
    for (const t of Object.keys(typesInPieces)) {
      let exists = false;
      for (const st of ['inRange', 'outOfRange']) exists = exists || has(option, st, t) || has(option.target, st, t);
      if (!exists) {
        for (const st of ['inRange', 'outOfRange']) (option[st] || (option[st] = {}))[t] = visualDefaultGet(t, st === 'inRange' ? 'active' : 'inactive', isCategory);
      }
    }
  }
  const base = { inRange: option.inRange, outOfRange: option.outOfRange };
  const target = option.target || (option.target = {});
  const controller = option.controller || (option.controller = {});
  zrMerge(target, base);
  zrMerge(controller, base);
  const completeSingle = b => {
    if (Array.isArray(opt.color) && !b.inRange) b.inRange = { color: opt.color.slice().reverse() };
    b.inRange = b.inRange || { color: env.gradientColor };
  };
  completeSingle(target);
  completeSingle(controller);
  // completeInactive(target, 'inRange', 'outOfRange')
  if (target.inRange && !target.outOfRange) {
    const absent = target.outOfRange = {};
    for (const t of Object.keys(target.inRange)) {
      if (!VISUAL_TYPES.includes(t)) continue;
      const defa = visualDefaultGet(t, 'inactive', isCategory);
      if (defa != null) {
        absent[t] = defa;
        if (t === 'color' && !hasOwn(absent, 'opacity') && !hasOwn(absent, 'colorAlpha')) absent.opacity = [0, 0];
      }
    }
  }
  // completeController
  {
    const symbolExists = (controller.inRange || {}).symbol || (controller.outOfRange || {}).symbol;
    const symbolSizeExists = (controller.inRange || {}).symbolSize || (controller.outOfRange || {}).symbolSize;
    const itemSymbol = mut.itemSymbolIgnored ? null : get('itemSymbol');
    const defaultSymbol = itemSymbol || 'roundRect';
    for (const st of ['inRange', 'outOfRange']) {
      let visuals = controller[st];
      if (!visuals) visuals = controller[st] = { color: isCategory ? env.inactiveColor : [env.inactiveColor] };
      if (visuals.symbol == null) visuals.symbol = (symbolExists && clone(symbolExists)) || (isCategory ? defaultSymbol : [defaultSymbol]);
      if (visuals.symbolSize == null) {
        visuals.symbolSize = (symbolSizeExists && clone(symbolSizeExists)) || (isCategory ? env.itemSize[0] : [env.itemSize[0], env.itemSize[0]]);
      }
      visuals.symbol = mapVisual(visuals.symbol, s => (s === 'none' ? defaultSymbol : s));
      const ss = visuals.symbolSize;
      if (ss != null) {
        let mx = -Infinity;
        eachVisual(ss, v => { if (v > mx) mx = v; });
        visuals.symbolSize = mapVisual(ss, v => linearMap(v, [0, mx], [0, env.itemSize[0]], true));
      }
    }
  }

  // resetVisual: the mappings (visualSolution.createVisualMappings)
  const makeMappings = (src, forController) => {
    const out = {};
    for (const st of ['inRange', 'outOfRange']) {
      const ms = {};
      const hidden = {};
      const visualsOf = src[st] || {};
      for (const t of Object.keys(visualsOf)) {
        if (!VISUAL_TYPES.includes(t)) continue;
        const mo = { type: t, visual: visualsOf[t] };
        if (mode === 'categories') {
          mo.mappingMethod = 'category';
          mo.categories = clone(opt.categories);
        } else {
          mo.dataExtent = extent.slice();
          mo.mappingMethod = 'piecewise';
          mo.pieceList = pieceList.map(p => {
            const c = clonePiece(p);
            if (st !== 'inRange' && !mut.outOfRangeKeepsPieceVisual) c.visual = null;
            return c;
          });
        }
        ms[t] = makeMapping(mo, mut);
        if (t === 'opacity') hidden.alpha = makeMapping(Object.assign({}, mo, { type: 'colorAlpha' }), mut);
      }
      out[st] = { mappings: ms, alpha: hidden.alpha || null, order: prepareVisualTypes(Object.keys(ms)) };
    }
    return out;
  };
  const targetVisuals = makeMappings(target);
  const controllerVisuals = makeMappings(controller, true);

  const model = {
    mode, extent, orient, inverse, isCategory, pieceList, selected, option, target, controller, targetVisuals, controllerVisuals,
    splitNumber: splitNumberOut, precision: fenv.precision, keyOf, env,
  };
  model.getValueState = value => {
    const index = findPieceIndex(value, pieceList, false, mut);
    if (index == null) return 'outOfRange';
    if (mut.selectedIgnored) return 'inRange';
    return selected[keyOf(pieceList[index])] ? 'inRange' : 'outOfRange';
  };
  model.getRepresentValue = piece => {
    if (isCategory) return piece.value;
    if (piece.value != null) return piece.value;
    const iv = piece.interval || [];
    if (iv[0] === -Infinity && iv[1] === Infinity) return 0;
    if (mut.repFinite) {
      if (iv[0] === -Infinity) return iv[1];
      if (iv[1] === Infinity) return iv[0];
    }
    return (iv[0] + iv[1]) / 2;
  };
  // VisualMapView.getControllerVisual
  model.getControllerVisual = (value, cluster, opts) => {
    opts = opts || {};
    const visualObj = {};
    if (cluster === 'color') visualObj.color = env.contentColor;
    const set = controllerVisuals[opts.forceState || model.getValueState(value)];
    for (let type of set.order) {
      let mapping = set.mappings[type];
      if (opts.convertOpacityToAlpha && type === 'opacity') {
        type = 'colorAlpha';
        mapping = set.alpha;
      }
      const depends = cluster === 'color' ? !!(type && type.indexOf(cluster) === 0) : type === cluster;
      if (depends && mapping) mapping.applyVisual(value, k => visualObj[k], (k, v) => { visualObj[k] = v; });
    }
    return visualObj[cluster];
  };
  return model;
}
function clonePiece(p) {
  const c = {};
  for (const k of Object.keys(p)) c[k] = Array.isArray(p[k]) ? p[k].slice() : (p[k] && typeof p[k] === 'object' ? clone(p[k]) : p[k]);
  return c;
}

// visualEncoding.ts getColorVisual + PiecewiseModel.getVisualMeta (:353-411)
function visualMetaOf(model, seriesColour, mut) {
  if (model.isCategory) return { stops: [], outerColors: [] };
  const getColorVisual = (value, state) => {
    const set = model.targetVisuals[state];
    const res = { color: seriesColour };
    for (const type of set.order) {
      const mapping = type === 'opacity' ? set.alpha : set.mappings[type];
      if (mapping) mapping.applyVisual(value, k => res[k], (k, v) => { res[k] = v; });
    }
    return res.color;
  };
  const stops = [];
  const outerColors = ['', ''];
  const setStop = (interval, state) => {
    const rep = model.getRepresentValue({ interval });
    if (!state) state = model.getValueState(rep);
    const color = getColorVisual(rep, state);
    if (interval[0] === -Infinity) outerColors[0] = color;
    else if (interval[1] === Infinity) outerColors[1] = color;
    else stops.push({ value: interval[0], color }, { value: interval[1], color });
  };
  const list = model.pieceList.slice();
  if (!list.length) {
    list.push({ interval: [-Infinity, Infinity] });
  } else {
    let edge = list[0].interval[0];
    if (edge !== -Infinity) list.unshift({ interval: [-Infinity, edge] });
    edge = list[list.length - 1].interval[1];
    if (edge !== Infinity) list.push({ interval: [edge, Infinity] });
  }
  let curr = -Infinity;
  for (const piece of list) {
    const interval = piece.interval;
    if (interval) {
      if (interval[0] > curr && !mut.noGapFill) setStop([curr, interval[0]], 'outOfRange');
      setStop(interval.slice());
      curr = interval[1];
    }
  }
  return { stops, outerColors };
}

// LineView.ts clipColorStops + getVisualGradient, on the recorded coords
function clipStops(stops, maxSize) {
  const out = [];
  let prevOut;
  let prevIn;
  const lerpStop = (s0, s1, cc) => ({ coord: cc, color: lerpCss((cc - s0.coord) / (s1.coord - s0.coord), s0.color, s1.color) });
  for (const stop of stops) {
    if (stop.coord < 0) {
      prevOut = stop;
    } else if (stop.coord > maxSize) {
      if (prevIn) out.push(lerpStop(prevIn, stop, maxSize));
      else if (prevOut) out.push(lerpStop(prevOut, stop, 0), lerpStop(prevOut, stop, maxSize));
      break;
    } else {
      if (prevOut) { out.push(lerpStop(prevOut, stop, 0)); prevOut = null; }
      out.push(stop);
      prevIn = stop;
    }
  }
  return out;
}
function gradientOf(meta, canvasSize, mut) {
  const stops = meta.stops.map(s => ({ coord: s.coord, color: s.color }));
  const outer = meta.outer.slice();
  const n = stops.length;
  if (n && stops[0].coord > stops[n - 1].coord) {
    stops.reverse();
    outer.reverse();
  }
  const inR = clipStops(stops, canvasSize);
  const m = inR.length;
  if (!m && n) return { kind: 'color', color: stops[0].coord < 0 ? (outer[1] || stops[n - 1].color) : (outer[0] || stops[0].color) };
  const tiny = mut.tiny0 ? 0 : 10;
  const minC = inR[0].coord - tiny;
  const maxC = inR[m - 1].coord + tiny;
  const span = maxC - minC;
  if (span < 1e-3) return { kind: 'color', color: 'transparent' };
  const out = inR.map(s => ({ offset: (s.coord - minC) / span, color: s.color }));
  out.push({ offset: m ? out[m - 1].offset : 0.5, color: outer[1] || 'transparent' });
  out.unshift({ offset: m ? out[0].offset : 0.5, color: outer[0] || 'transparent' });
  const g = { x: 0, y: 0, x2: 0, y2: 0 };
  g[meta.coordDim] = minC;
  g[meta.coordDim + '2'] = maxC;
  return { kind: 'gradient', global: true, x: g.x, y: g.y, x2: g.x2, y2: g.y2, stops: out };
}
function paintKey(p) {
  if (p.kind === 'color') return 'color ' + colKey(p.color);
  return ['gradient', p.global, hex(p.x), hex(p.y), hex(p.x2), hex(p.y2)].join(' ') + ' | '
    + p.stops.map(s => hex(s.offset) + '@' + colKey(s.color)).join(' ');
}
function recPaintKey(rec) {
  if (rec.kind === 'color') return 'color ' + recColKey(rec.color);
  return ['gradient', rec.global, rec.x, rec.y, rec.x2, rec.y2].join(' ') + ' | '
    + rec.stops.map(s => s.offset + '@' + recColKey(s.color)).join(' ');
}

// ---------- the view (PiecewiseView.ts, VisualMapView.ts, helper.ts, layout.ts) ----------

// number.ts parsePercent (parsePositionOption), as visualmap-view.js
function parsePos(option, base) {
  switch (option) {
    case 'center':
    case 'middle':
      option = '50%';
      break;
    case 'left':
    case 'top':
      option = '0%';
      break;
    case 'right':
    case 'bottom':
      option = '100%';
      break;
  }
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * base + 0;
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}
function cssArray(v) {
  if (typeof v === 'number') return [v, v, v, v];
  if (v.length === 2) return [v[0], v[1], v[0], v[1]];
  if (v.length === 3) return [v[0], v[1], v[2], v[1]];
  return v;
}
// layout.ts getLayoutRect (container [0, 0, W, H]), as visualmap-view.js
function getLayoutRect(p, cw, ch, margin) {
  margin = cssArray(margin || 0);
  let left = parsePos(p.left, cw);
  let top = parsePos(p.top, ch);
  const right = parsePos(p.right, cw);
  const bottom = parsePos(p.bottom, ch);
  let width = parsePos(p.width, cw);
  let height = parsePos(p.height, ch);
  const vm = margin[2] + margin[0];
  const hm = margin[1] + margin[3];
  if (isNaN(width)) width = cw - right - hm - left;
  if (isNaN(height)) height = ch - bottom - vm - top;
  if (isNaN(left)) left = cw - right - width - hm;
  if (isNaN(top)) top = ch - bottom - height - vm;
  switch (p.left || p.right) {
    case 'center':
      left = cw / 2 - width / 2 - margin[3];
      break;
    case 'right':
      left = cw - width - hm;
      break;
  }
  switch (p.top || p.bottom) {
    case 'middle':
    case 'center':
      top = ch / 2 - height / 2 - margin[0];
      break;
    case 'bottom':
      top = ch - height - vm;
      break;
  }
  left = left || 0;
  top = top || 0;
  if (isNaN(width)) width = cw - hm - left - (right || 0);
  if (isNaN(height)) height = ch - vm - top - (bottom || 0);
  let x = 0 + left + margin[3];
  let y = 0 + top + margin[0];
  if (width < 0) { x = x + width; width = -width; }
  if (height < 0) { y = y + height; height = -height; }
  return { x, y, width, height, margin };
}
// visualMap/helper.ts:40-72
const PARAMS_SET = [['left', 'right', 'width'], ['top', 'bottom', 'height']];
function getItemAlignVertical(inp) {
  if (inp.align != null && inp.align !== 'auto') return inp.align;
  const realIndex = 0;
  const reals = PARAMS_SET[realIndex];
  const fakeValue = [0, null, 10];
  const layoutInput = {};
  for (let i = 0; i < 3; i++) {
    layoutInput[PARAMS_SET[1 - realIndex][i]] = fakeValue[i];
    layoutInput[reals[i]] = i === 2 ? inp.itemSize[0] : inp.boxOption[reals[i]];
  }
  const rect = getLayoutRect(layoutInput, W, H, inp.padding);
  const term = rect.margin[3] || 0;
  return reals[term + rect.x + rect.width * 0.5 < W * 0.5 ? 0 : 1];
}
// zrender BoundingRect.applyTransform / union, Group.getBoundingRect (translations only here)
function rectTranslate(s, x, y) {
  // applyTransform fast path with m = [1, 0, 0, 1, 0 + x, 0 + y]
  const t = { x: s.x * 1 + (0 + x), y: s.y * 1 + (0 + y), width: s.width * 1, height: s.height * 1 };
  if (t.width < 0) { t.x += t.width; t.width = -t.width; }
  if (t.height < 0) { t.y += t.height; t.height = -t.height; }
  return t;
}
function union(a, b) {
  const x = Math.min(b.x, a.x);
  const y = Math.min(b.y, a.y);
  a.width = (isFinite(a.x) && isFinite(a.width)) ? Math.max(b.x + b.width, a.x + a.width) - x : b.width;
  a.height = (isFinite(a.y) && isFinite(a.height)) ? Math.max(b.y + b.height, a.y + a.height) - y : b.height;
  a.x = x;
  a.y = y;
}
function groupRect(children) {
  let r = null;
  for (const c of children) {
    const t = rectTranslate(c.rect, c.x || 0, c.y || 0);
    r = r || Object.assign({}, t);
    union(r, t);
  }
  return r || { x: 0, y: 0, width: 0, height: 0 };
}
function adjustX(x, w, align) {
  if (align === 'right') x -= w;
  else if (align === 'center') x -= w / 2;
  return x;
}
function adjustY(y, h, va) {
  if (va === 'middle') y -= h / 2;
  else if (va === 'bottom') y -= h;
  return y;
}
function textRect(t) {
  const m = measureRaw(t.string, t.font);
  const textY = adjustY(t.y, m.height, t.verticalAlign || 'top') + m.height / 2;
  const span = { x: adjustX(t.x, m.width, t.align || 'left'), y: adjustY(textY, m.height, 'middle'), width: m.width, height: m.height };
  return groupRect([{ rect: span }]);
}
// symbol.ts shape makers + the path's PathProxy rect (no stroke)
function symbolPathRect(type, w, h, mut) {
  switch (type) {
    case 'rect':
    case 'roundRect':
    case 'diamond':
    case 'triangle':
      return { x: 0, y: 0, width: w, height: h };
    case 'circle': {
      const cx = 0 + w / 2;
      const cy = 0 + h / 2;
      const r = Math.min(w, h) / 2;
      if (mut.circleAsRect) return { x: 0, y: 0, width: w, height: h };
      return { x: cx - r, y: cy - r, width: (cx + r) - (cx - r), height: (cy + r) - (cy - r) };
    }
    default:
      throw new OracleError('no transcription for the item symbol ' + JSON.stringify(type));
  }
}

// the whole view: returns the flat field map
function viewModel(inp, model, mut) {
  const o = {};
  const [iw, ih] = inp.itemSize;
  const vertical = inp.orient === 'vertical';
  const itemAlign = vertical ? getItemAlignVertical(inp) : (!inp.align || inp.align === 'auto' ? 'left' : inp.align);
  o.itemAlign = itemAlign;
  let list = model.pieceList.map((piece, index) => ({ piece, index }));
  let endsText = inp.text;
  const inverse = inp.inverse;
  if ((inp.orient === 'horizontal' ? inverse : !inverse) && !mut.viewNoReverse) list.reverse();
  else if (endsText && !mut.endsNoReverse && !mut.endsFollowOrient) endsText = endsText.slice().reverse();
  if (endsText && mut.endsFollowOrient && inp.orient === 'horizontal') endsText = endsText.slice().reverse();
  const showLabel = mut.showLabelAlways ? true : (inp.showLabel != null ? inp.showLabel : !endsText);
  o.labels = String(showLabel);
  o.endsText = endsText ? JSON.stringify(endsText) : 'null';
  const children = [];
  const endChild = (t, end) => {
    if (!t) return;
    const tx = { string: t, x: showLabel ? (itemAlign === 'right' ? iw : 0) : iw / 2, y: ih / 2, align: showLabel ? itemAlign : 'center',
      verticalAlign: 'middle', font: inp.font };
    children.push({ kind: 'endText', end, text: tx, rect: groupRect([{ rect: textRect(tx) }]) });
  };
  if (endsText) endChild(endsText[0], 0);
  for (const it of list) {
    const piece = it.piece;
    const rep = model.getRepresentValue(piece);
    const symbolType = model.getControllerVisual(rep, 'symbol');
    const fill = model.getControllerVisual(rep, 'color');
    must(typeof symbolType === 'string', 'a non-string item symbol ' + JSON.stringify(symbolType));
    const symRect = symbolPathRect(symbolType, iw, ih, mut);
    const kids = [{ rect: symRect }];
    let label = null;
    if (showLabel) {
      const state = model.getValueState(rep);
      const align = inp.textStyle.align || itemAlign;
      label = { string: piece.text, x: align === 'right' ? -inp.textGap : iw + inp.textGap, y: ih / 2, align,
        verticalAlign: inp.textStyle.verticalAlign || 'middle', font: inp.font,
        opacity: inp.textStyle.opacity != null ? inp.textStyle.opacity : (state === 'outOfRange' && !mut.labelOpacityIgnored ? 0.5 : 1) };
      kids.push({ rect: textRect(label) });
    }
    children.push({ kind: 'piece', pieceIndex: it.index, symbolType, fill, symRect, label, rect: groupRect(kids) });
  }
  if (endsText) endChild(endsText[1], 1);
  // layout.box (layout.ts:74-141), no max size
  let x = 0;
  let y = 0;
  const gap = inp.itemGap;
  children.forEach((c, idx) => {
    const rect = c.rect;
    const next = children[idx + 1];
    const nextRect = next && next.rect;
    let nextX;
    let nextY;
    if (!vertical) {
      const moveX = rect.width + (nextRect && !mut.noNextTerm ? (-nextRect.x + rect.x) : 0);
      nextX = x + moveX;
    } else {
      const moveY = rect.height + (nextRect && !mut.noNextTerm ? (-nextRect.y + rect.y) : 0);
      nextY = y + moveY;
    }
    c.x = x;
    c.y = y;
    if (!vertical) x = nextX + gap;
    else y = nextY + gap;
  });
  children.forEach((c, k) => {
    const p = 'c' + k + '.';
    o[p + 'kind'] = c.kind;
    o[p + 'pos'] = hex(c.x) + ',' + hex(c.y);
    o[p + 'rect'] = rectKey(c.rect);
    if (c.kind === 'endText') {
      o[p + 'end'] = String(c.end);
      o[p + 'text'] = [c.text.string, hex(c.text.x), hex(c.text.y), c.text.align, c.text.verticalAlign].join('|');
    } else {
      o[p + 'piece'] = String(c.pieceIndex);
      o[p + 'symbol'] = c.symbolType + '|' + colKey(c.fill) + '|' + rectKey(c.symRect);
      o[p + 'label'] = c.label ? [c.label.string, hex(c.label.x), hex(c.label.y), c.label.align, c.label.verticalAlign, hex(c.label.opacity)].join('|') : 'null';
    }
  });
  // renderBackground
  const bb = groupRect(children);
  o.bboxBg = rectKey(bb);
  const pad = cssArray(inp.padding || 0);
  const shape = { x: bb.x - pad[3], y: bb.y - pad[0], width: bb.width + pad[3] + pad[1], height: bb.height + pad[0] + pad[2] };
  o.bgShape = rectKey(shape);
  const bgRect = { x: Math.min(shape.x, shape.x + shape.width), y: Math.min(shape.y, shape.y + shape.height) };
  bgRect.width = Math.max(shape.x, shape.x + shape.width) - bgRect.x;
  bgRect.height = Math.max(shape.y, shape.y + shape.height) - bgRect.y;
  const stroke = inp.borderColor;
  if (!mut.bgStrokeIgnored && !(stroke == null || stroke === 'none' || !(inp.borderWidth > 0))) {
    let w = inp.borderWidth;
    const fill = inp.backgroundColor;
    if (!(fill != null && fill !== 'none')) w = Math.max(w, 4);
    bgRect.width += w / 1;
    bgRect.height += w / 1;
    bgRect.x -= w / 1 / 2;
    bgRect.y -= w / 1 / 2;
  }
  o.bgRect = rectKey(bgRect);
  // positionGroup
  const bp = groupRect(children.concat([{ rect: bgRect }]));
  o.bboxPos = rectKey(bp);
  const lp = { width: bp.width, height: bp.height };
  for (const k of Object.keys(inp.boxParams)) if (lp[k] == null) lp[k] = inp.boxParams[k];
  const lr = getLayoutRect(lp, W, H);
  o.layout = rectKey(lr);
  o.group = hex(0 + (lr.x - bp.x)) + ',' + hex(0 + (lr.y - bp.y));
  return o;
}
function viewRecord(v) {
  const o = {};
  o.itemAlign = v.itemAlign;
  o.labels = String(v.labels);
  o.endsText = v.endsText ? JSON.stringify(v.endsText) : 'null';
  v.children.forEach((c, k) => {
    const p = 'c' + k + '.';
    o[p + 'kind'] = c.kind;
    o[p + 'pos'] = c.x + ',' + c.y;
    o[p + 'rect'] = recRectKey(c);
    if (c.kind === 'endText') {
      o[p + 'end'] = String(c.end);
      o[p + 'text'] = [c.text.string, c.text.x, c.text.y, c.text.align, c.text.verticalAlign].join('|');
    } else {
      o[p + 'piece'] = String(c.pieceIndex);
      o[p + 'symbol'] = c.symbol.symbolType + '|' + recColKey(c.symbol.fill) + '|' + recRectKey(c.symbol);
      o[p + 'label'] = c.label ? [c.label.string, c.label.x, c.label.y, c.label.align, c.label.verticalAlign, c.label.opacity].join('|') : 'null';
    }
  });
  o.bboxBg = recRectKey(v.bboxBackground);
  o.bgShape = RK.map(k => v.background.shape[k]).join(',');
  o.bgRect = recRectKey(v.background);
  o.bboxPos = recRectKey(v.bboxPosition);
  o.layout = RK.map(k => v.bboxPosition.layoutRect[k]).join(',');
  o.group = v.group.x + ',' + v.group.y;
  return o;
}

// ---------- the model fields, transcribed and recorded ----------
function visualJson(visual) {
  if (visual == null) return null;
  const r = {};
  for (const k of Object.keys(visual)) r[k] = k === 'color' && typeof visual[k] === 'string' ? colRec(visual[k]) : clone(visual[k]);
  return r;
}
function mappingJson(set) {
  const out = [];
  for (const t of Object.keys(set.mappings)) out.push(mappingRecOf(set.mappings[t], false));
  if (set.alpha) out.push(mappingRecOf(set.alpha, true));
  return out;
}
function mappingRecOf(m, alpha) {
  const o = m.option;
  const vis = o.visual;
  return {
    type: m.type, method: m.method, visual: clone(vis),
    visualDefault: o.mappingMethod === 'category' && vis[CATEGORY_DEFAULT_VISUAL_INDEX] !== undefined ? clone(vis[CATEGORY_DEFAULT_VISUAL_INDEX]) : null,
    categories: o.mappingMethod === 'category' ? clone(o.categories) : null,
    hasSpecialVisual: o.mappingMethod === 'piecewise' ? !!o.hasSpecialVisual : null,
    alpha,
  };
}
function modelFields(model) {
  const o = {};
  o.mode = model.mode;
  o.extent = model.extent.map(hex).join(',');
  o.splitNumber = String(model.splitNumber);
  o.precision = String(model.precision);
  o.selected = JSON.stringify(model.selected);
  o.optionInRange = json(model.option.inRange);
  o.optionOutOfRange = json(model.option.outOfRange);
  o.target = json(model.target);
  o.controller = json(model.controller);
  for (const st of ['inRange', 'outOfRange']) {
    o['order.' + st] = model.targetVisuals[st].order.join(',');
    o['controllerOrder.' + st] = model.controllerVisuals[st].order.join(',');
    o['mappings.target.' + st] = JSON.stringify(mappingJson(model.targetVisuals[st]));
    o['mappings.controller.' + st] = JSON.stringify(mappingJson(model.controllerVisuals[st]));
  }
  o.pieceCount = String(model.pieceList.length);
  model.pieceList.forEach((p, k) => {
    const pre = 'p' + k + '.';
    o[pre + 'index'] = p.index == null ? 'null' : String(p.index);
    o[pre + 'interval'] = p.interval ? p.interval.map(hex).join(',') + ' ' + p.close.join(',') : 'null';
    o[pre + 'value'] = p.value == null ? 'null' : typeof p.value === 'number' ? hex(p.value) : 's:' + p.value;
    o[pre + 'text'] = p.text;
    o[pre + 'visual'] = JSON.stringify(visualJson(p.visual));
    const key = model.keyOf(p);
    o[pre + 'key'] = key;
    o[pre + 'selected'] = String(!!model.selected[key]);
    const rep = model.getRepresentValue(p);
    o[pre + 'rep'] = typeof rep === 'number' ? hex(rep) : 's:' + rep;
    o[pre + 'state'] = model.getValueState(rep);
  });
  return o;
}
function modelRecordFields(vm) {
  const o = {};
  const m = vm.model;
  o.mode = vm.mode;
  o.extent = m.extent.join(',');
  o.splitNumber = String(m.splitNumber);
  o.precision = String(m.precision);
  o.selected = JSON.stringify(m.selected);
  o.optionInRange = json(m.optionInRange);
  o.optionOutOfRange = json(m.optionOutOfRange);
  o.target = json(m.target);
  o.controller = json(m.controller);
  for (const st of ['inRange', 'outOfRange']) {
    o['order.' + st] = m.order[st].join(',');
    o['controllerOrder.' + st] = m.controllerOrder[st].join(',');
    o['mappings.target.' + st] = JSON.stringify(vm.mappings.target[st]);
    o['mappings.controller.' + st] = JSON.stringify(vm.mappings.controller[st]);
  }
  o.pieceCount = String(vm.pieces.length);
  vm.pieces.forEach((p, k) => {
    const pre = 'p' + k + '.';
    o[pre + 'index'] = p.index == null ? 'null' : String(p.index);
    o[pre + 'interval'] = p.interval ? p.interval.join(',') + ' ' + p.close.join(',') : 'null';
    o[pre + 'value'] = p.valueString != null ? 's:' + p.valueString : p.value == null ? 'null' : p.value;
    o[pre + 'text'] = p.text;
    o[pre + 'visual'] = JSON.stringify(p.visual);
    o[pre + 'key'] = p.key;
    o[pre + 'selected'] = String(p.selected);
    o[pre + 'rep'] = p.representString != null ? 's:' + p.representString : p.representValue;
    o[pre + 'state'] = p.state;
  });
  return o;
}
function diffFlat(a, b, prefix) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => a[k] !== b[k]).map(k => ({ field: prefix + k, upstream: a[k] === undefined ? null : a[k], mutated: b[k] === undefined ? null : b[k] }));
}

// ---------- the series (rows, visualMeta, line paints) ----------
const vmOptions = option => {
  const v = option.visualMap;
  return v === undefined ? [] : Array.isArray(v) ? v : [v];
};
const seriesOptions = option => (Array.isArray(option.series) ? option.series : [option.series]);
function seriesDiffs(c, models, mut) {
  const diffs = [];
  const sOpts = seriesOptions(c.option);
  for (const s of c.series || []) {
    const sOpt = sOpts[s.index];
    const rawData = s.rawItems;
    s.rows.forEach((row, i) => {
      const run = { color: s.color.css, opacity: s.opacity == null ? undefined : num(s.opacity), symbol: s.symbol == null ? undefined : s.symbol,
        symbolSize: s.symbolSize == null ? undefined : clone(s.symbolSize) };
      const raw = rawData[i];
      const tag = 's' + s.index + '.r' + i + '.';
      for (const vmIdx of s.targetedBy) {
        if (raw && raw.visualMap === false) continue;
        const model = models[vmIdx];
        const rv = row.values.find(x => x.vm === vmIdx);
        const v = rv.valueString != null ? rv.valueString : num(rv.value);
        const piece = findPieceIndex(v, model.pieceList, false, mut);
        const closest = findPieceIndex(v, model.pieceList, true, mut);
        const st = model.getValueState(v);
        if (String(piece == null ? null : piece) !== String(rv.piece)) diffs.push({ field: tag + 'piece', upstream: rv.piece, mutated: piece == null ? null : piece });
        if (String(closest == null ? null : closest) !== String(rv.closest)) diffs.push({ field: tag + 'closest', upstream: rv.closest, mutated: closest == null ? null : closest });
        if (st !== rv.state) diffs.push({ field: tag + 'state', upstream: rv.state, mutated: st });
        const set = model.targetVisuals[st];
        for (const type of set.order) {
          const mp = set.mappings[type];
          if (mp) mp.applyVisual(v, k => run[k], (k, val) => { run[k] = val; });
        }
      }
      // 4500: the data itemStyle / symbol overrides (style.ts, symbol.ts)
      if (isObject(raw) && !Array.isArray(raw)) {
        if (isObject(raw.itemStyle)) {
          if (s.drawType === 'fill' && raw.itemStyle.color != null) run.color = raw.itemStyle.color;
          if (raw.itemStyle.opacity != null) run.opacity = raw.itemStyle.opacity;
        }
        if (raw.symbol != null) run.symbol = raw.symbol;
        if (raw.symbolSize != null) run.symbolSize = raw.symbolSize;
      }
      if (recColKey(row.fill) !== colKey(run.color)) diffs.push({ field: tag + 'fill', upstream: row.fill.css, mutated: run.color == null ? null : run.color });
      if (row.opacity !== hexOrNull(run.opacity)) diffs.push({ field: tag + 'opacity', upstream: row.opacityText, mutated: textOrNull(run.opacity) });
      if (json(row.symbol) !== json(run.symbol == null ? null : run.symbol)) diffs.push({ field: tag + 'symbol', upstream: row.symbol, mutated: run.symbol });
      if (json(row.symbolSize) !== json(run.symbolSize == null ? null : run.symbolSize)) diffs.push({ field: tag + 'symbolSize', upstream: row.symbolSize, mutated: run.symbolSize });
    });
    s.visualMeta.forEach(meta => {
      const mine = visualMetaOf(models[meta.vm], s.color.css, mut);
      const tag = 's' + s.index + '.meta' + meta.vm + '.';
      const a = meta.stops.map(st => st.value + '@' + recColKey(st.color)).join(' ');
      const b = mine.stops.map(st => hex(st.value) + '@' + colKey(st.color)).join(' ');
      if (a !== b) diffs.push({ field: tag + 'stops', upstream: a.slice(0, 200), mutated: b.slice(0, 200) });
      const oa = meta.outerColors.map(recColKey).join(' ');
      const ob = mine.outerColors.map(x => (x === '' ? 'undef' : colKey(x))).join(' ');
      if (oa !== ob) diffs.push({ field: tag + 'outer', upstream: oa, mutated: ob });
    });
    if (s.type === 'line') {
      const used = s.visualMeta.slice().reverse().find(mt => mt.coordDim === 'x' || mt.coordDim === 'y');
      let grad = null;
      if (used) {
        const mine = visualMetaOf(models[used.vm], s.color.css, mut);
        must(mine.stops.length === used.stops.length || mut.noGapFill || Object.keys(mut).length, 'meta stop count');
        const coords = used.stops.map(st => num(st.coord));
        if (mine.stops.length === coords.length) {
          const meta = { coordDim: used.coordDim, stops: mine.stops.map((st, k) => ({ coord: coords[k], color: st.color })), outer: mine.outerColors };
          grad = gradientOf(meta, used.coordDim === 'x' ? c.width : c.height, mut);
        } else {
          grad = { kind: 'color', color: 'mismatch' };
        }
      }
      const line = sOpt.lineStyle && sOpt.lineStyle.color != null ? { kind: 'color', color: sOpt.lineStyle.color } : grad || { kind: 'color', color: s.color.css };
      const lk = line.color === 'mismatch' ? 'mismatch' : paintKey(line);
      if (recPaintKey(s.polyline) !== lk) diffs.push({ field: 's' + s.index + '.polyline', upstream: recPaintKey(s.polyline).slice(0, 200), mutated: lk.slice(0, 200) });
      if (s.area) {
        const area = sOpt.areaStyle && sOpt.areaStyle.color != null ? { kind: 'color', color: sOpt.areaStyle.color } : grad || { kind: 'color', color: s.color.css };
        const ak = area.color === 'mismatch' ? 'mismatch' : paintKey(area);
        if (recPaintKey(s.area) !== ak) diffs.push({ field: 's' + s.index + '.area', upstream: recPaintKey(s.area).slice(0, 200), mutated: ak.slice(0, 200) });
      }
    }
  }
  return diffs;
}

// decode a record's `resolved` into the view's inputs
function viewInputs(vm) {
  const r = vm.resolved;
  return {
    orient: r.orient, inverse: r.inverse, align: r.align, itemSize: r.itemSize.map(num), itemGap: num(r.itemGap), textGap: num(r.textGap),
    padding: r.padding, text: r.text, showLabel: r.showLabel, font: r.font, textStyle: r.textStyle,
    boxOption: r.boxOption, boxParams: r.boxParams, borderWidth: num(r.borderWidth), borderColor: r.borderColor.css,
    backgroundColor: r.backgroundColor.css,
  };
}
function envOf(vm, top) {
  return {
    gradientColor: top.gradientColor.map(x => x.css), inactiveColor: vm.resolved.inactiveColor.css, contentColor: vm.resolved.contentColor.css,
    itemSize: vm.resolved.itemSize.map(num),
  };
}

// every difference of a case under a mutation
function caseDiffs(c, top, mut) {
  const opts = vmOptions(c.option);
  const diffs = [];
  const models = {};
  for (const vm of c.visualMaps) {
    const model = buildModel(opts[vm.index], envOf(vm, top), mut);
    models[vm.index] = model;
    diffs.push(...diffFlat(modelRecordFields(vm), modelFields(model), 'vm' + vm.index + '.'));
    if (vm.view) diffs.push(...diffFlat(viewRecord(vm.view), viewModel(viewInputs(vm), model, mut), 'vm' + vm.index + '.view.'));
  }
  diffs.push(...seriesDiffs(c, models, mut));
  return diffs;
}

// =====================================================================
// Recording
// =====================================================================
let CAPTURE = new Map();
let hooked = false;
function hookViews() {
  if (hooked) return;
  runChart({ series: [], visualMap: { type: 'piecewise' } }, ch => {
    const vm = ch.getModel().getComponent('visualMap', 0);
    const view = ch.getViewOfComponentModel(vm);
    const pproto = Object.getPrototypeOf(view);
    const vproto = Object.getPrototypeOf(pproto);
    must(!hasOwn(pproto, 'renderBackground') && !hasOwn(pproto, 'positionGroup'), 'PiecewiseView overrides the hooked methods');
    must(hasOwn(vproto, 'renderBackground') && hasOwn(vproto, 'positionGroup'), 'VisualMapView has no renderBackground/positionGroup');
    must(hasOwn(pproto, '_enableHoverLink'), 'PiecewiseView has no _enableHoverLink');
    const origHover = pproto._enableHoverLink;
    pproto._enableHoverLink = function (itemGroup, pieceIndex) {
      itemGroup.__oraclePieceIndex = pieceIndex;
      return origHover.call(this, itemGroup, pieceIndex);
    };
    const origBg = vproto.renderBackground;
    const origPos = vproto.positionGroup;
    vproto.renderBackground = function (group) {
      CAPTURE.set(this, { bg: rectRec(group.getBoundingRect().clone()) });
      return origBg.call(this, group);
    };
    vproto.positionGroup = function (group) {
      const cap = CAPTURE.get(this);
      must(cap && !cap.pos, 'positionGroup without a renderBackground, or twice');
      const before = { x: group.x, y: group.y };
      must(!group.needLocalTransform(), 'the view group has a transform before positionGroup');
      const r = group.getBoundingRect().clone();
      const params = this.visualMapModel.getBoxLayoutParams();
      const lr = echarts.helper.getLayoutRect(echarts.util.defaults({ width: r.width, height: r.height }, params), { x: 0, y: 0, width: W, height: H });
      const res = origPos.call(this, group);
      cap.pos = Object.assign({ before: Object.assign(numRec('x', before.x), numRec('y', before.y)) }, rectRec(r), {
        layoutRect: rectRec(lr).rect, layoutRectText: rectRec(lr).rectText, after: Object.assign(numRec('x', group.x), numRec('y', group.y)) });
      must(Object.is(group.x, before.x + (lr.x - r.x)) && Object.is(group.y, before.y + (lr.y - r.y)), 'positionGroup did not move the group by layoutRect - rect');
      return res;
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

let VisualMappingClass = null;
const BOX = ['left', 'right', 'top', 'bottom', 'width', 'height'];
function boxJson(o) {
  const r = {};
  for (const k of BOX) if (o[k] !== undefined) r[k] = o[k];
  return r;
}
function textRecOf(el) {
  const s = el.style;
  must(typeof s.font === 'string' && s.font, 'a text with no font');
  measureRaw(s.text, s.font);
  return Object.assign({ string: s.text }, numRec('x', s.x), numRec('y', s.y),
    { align: s.align, verticalAlign: s.verticalAlign, font: s.font, fill: colRec(s.fill) }, numRecN('opacity', s.opacity), rectRec(el.getBoundingRect()));
}
function mappingRec(m, alpha) {
  const o = m.option;
  const vis = o.visual;
  return {
    type: alpha ? 'colorAlpha' : m.type, method: m.mappingMethod, visual: clone(vis),
    visualDefault: m.mappingMethod === 'category' && vis[CATEGORY_DEFAULT_VISUAL_INDEX] !== undefined ? clone(vis[CATEGORY_DEFAULT_VISUAL_INDEX]) : null,
    categories: m.mappingMethod === 'category' ? clone(o.categories) : null,
    hasSpecialVisual: m.mappingMethod === 'piecewise' ? !!o.hasSpecialVisual : null,
    alpha,
  };
}
function mappingsRec(set) {
  const out = [];
  for (const t of Object.keys(set)) out.push(mappingRec(set[t], false));
  if (set.__alphaForOpacity) out.push(mappingRec(set.__alphaForOpacity, true));
  return out;
}

function recordVM(chart, vmModel, key) {
  must(vmModel.subType === 'piecewise', key + ': a ' + vmModel.subType + ' visualMap');
  const opt = vmModel.option;
  const show = opt.show !== false;
  const view = chart.getViewOfComponentModel(vmModel);
  if (!VisualMappingClass) {
    const any = Object.keys(vmModel.controllerVisuals.inRange).map(k => vmModel.controllerVisuals.inRange[k])[0];
    if (any) VisualMappingClass = any.constructor;
  }
  must(VisualMappingClass, 'no VisualMapping class');
  const ts = vmModel.textStyleModel;
  const font = new echarts.graphic.Text({ style: echarts.helper.createTextStyle(ts, { text: 'x' }) }).style.font;
  const gm = chart.getModel();
  const targets = [];
  gm.eachSeries(sm => { if (vmModel.isTargetSeries(sm)) targets.push(sm.seriesIndex); });
  const nullish = v => (v === undefined ? null : v);
  const rec = {
    index: vmModel.componentIndex, subType: vmModel.subType, show, mode: vmModel._mode,
    resolved: Object.assign({
      orient: vmModel.get('orient'), inverse: !!vmModel.get('inverse'), align: opt.align,
    }, pairRec('itemSize', vmModel.itemSize), numRec('itemGap', vmModel.get('itemGap')), numRec('textGap', vmModel.get('textGap')), {
      padding: clone(opt.padding), paddingNorm: cssArray(opt.padding || 0).map(hex), paddingNormText: cssArray(opt.padding || 0).map(text),
      text: opt.text ? clone(opt.text) : null, showLabel: nullish(vmModel.get('showLabel', true)), itemSymbol: vmModel.get('itemSymbol'),
      selectedMode: nullish(opt.selectedMode), font,
      textStyle: { align: nullish(ts.get('align')), verticalAlign: nullish(ts.get('verticalAlign')), opacity: nullish(ts.get('opacity')) },
      boxOption: boxJson(opt), boxParams: boxJson(vmModel.getBoxLayoutParams()),
      backgroundColor: colRec(vmModel.get('backgroundColor')), borderColor: colRec(vmModel.get('borderColor')),
    }, numRec('borderWidth', vmModel.get('borderWidth')), {
      contentColor: colRec(vmModel.get('contentColor')), inactiveColor: colRec(vmModel.get('inactiveColor')),
    }),
  };
  const ext = vmModel.getExtent();
  const vopt = vmOptions(chart.__oracleOption)[vmModel.componentIndex];
  rec.model = Object.assign(pairRec('extent', ext), {
    splitNumber: opt.splitNumber, precision: opt.precision, precisionOption: vopt.precision == null ? null : vopt.precision,
    minOpen: !!opt.minOpen, maxOpen: !!opt.maxOpen, formatter: typeof opt.formatter === 'string' ? opt.formatter : null,
    categories: opt.categories ? clone(opt.categories) : null, selected: clone(opt.selected),
    optionInRange: clone(opt.inRange), optionOutOfRange: clone(opt.outOfRange), target: clone(opt.target), controller: clone(opt.controller),
    order: {
      inRange: VisualMappingClass.prepareVisualTypes(vmModel.targetVisuals.inRange),
      outOfRange: VisualMappingClass.prepareVisualTypes(vmModel.targetVisuals.outOfRange),
    },
    controllerOrder: {
      inRange: VisualMappingClass.prepareVisualTypes(vmModel.controllerVisuals.inRange),
      outOfRange: VisualMappingClass.prepareVisualTypes(vmModel.controllerVisuals.outOfRange),
    },
    targets,
  });
  must(typeof opt.formatter !== 'function', key + ': a function formatter');
  rec.mappings = {
    target: { inRange: mappingsRec(vmModel.targetVisuals.inRange), outOfRange: mappingsRec(vmModel.targetVisuals.outOfRange) },
    controller: { inRange: mappingsRec(vmModel.controllerVisuals.inRange), outOfRange: mappingsRec(vmModel.controllerVisuals.outOfRange) },
  };
  const firstMapping = Object.keys(vmModel.targetVisuals.inRange).map(k => vmModel.targetVisuals.inRange[k])[0];
  const mappingPieces = firstMapping && firstMapping.option.pieceList;
  rec.pieces = vmModel.getPieceList().map((p, k) => {
    const pr = { k, index: p.index == null ? null : p.index };
    if (p.interval) Object.assign(pr, pairRec('interval', p.interval), { close: p.close.slice() });
    else Object.assign(pr, { interval: null, intervalText: null, close: null });
    pr.value = typeof p.value === 'number' ? hex(p.value) : null;
    pr.valueText = p.value == null ? null : String(p.value);
    pr.valueString = typeof p.value === 'string' ? p.value : null;
    pr.text = p.text;
    pr.visual = visualJson(p.visual);
    pr.originIndex = mappingPieces ? mappingPieces[k].originIndex : null;
    pr.key = vmModel.getSelectedMapKey(p);
    pr.selected = !!opt.selected[pr.key];
    const rep = vmModel.getRepresentValue(p);
    if (typeof rep === 'number') Object.assign(pr, numRec('representValue', rep), { representString: null });
    else Object.assign(pr, { representValue: null, representValueText: null, representString: rep });
    pr.state = vmModel.getValueState(rep);
    return pr;
  });
  if (!show) {
    must(view.group.children().length === 0, key + ': show false but the view group has children');
    return rec;
  }
  const cap = CAPTURE.get(view);
  must(cap && cap.bg && cap.pos, key + ': the bounding-rect reads were not captured');
  const group = view.group;
  const kids = group.children();
  const bgEl = kids[kids.length - 1];
  must(bgEl.type === 'rect' && bgEl.z2 === -1, key + ': the last child is not the background');
  const endsText = (() => {
    let t = opt.text;
    const inv = vmModel.get('inverse');
    if (vmModel.get('orient') === 'horizontal' ? inv : !inv) return t ? t.slice() : null;
    return t ? t.slice().reverse() : null;
  })();
  let labels = null;
  const children = kids.slice(0, -1).map(g => {
    must(g.isGroup, key + ': a non-group child');
    const base = Object.assign(numRec('x', g.x), numRec('y', g.y), rectRec(g.getBoundingRect()));
    if (g.__oraclePieceIndex == null) {
      must(g.childCount() === 1 && g.childAt(0).type === 'text', key + ': an ends-text group that is not one text');
      // an end-0 text is always the first child, an end-1 text the last before the background
      return Object.assign({ kind: 'endText', end: kids.indexOf(g) === 0 ? 0 : 1 }, base, { text: textRecOf(g.childAt(0)) });
    }
    const sym = g.childAt(0);
    const lab = g.childCount() > 1 ? g.childAt(1) : null;
    must(g.childCount() <= 2 && (!lab || lab.type === 'text'), key + ': an item group of ' + g.childCount());
    labels = labels == null ? !!lab : labels;
    must(labels === !!lab, key + ': labels on some items only');
    return Object.assign({ kind: 'piece', pieceIndex: g.__oraclePieceIndex }, base, {
      symbol: Object.assign({ symbolType: sym.shape.symbolType, shape: { x: sym.shape.x, y: sym.shape.y, width: sym.shape.width, height: sym.shape.height },
        fill: colRecOrNull(sym.style.fill), stroke: colRecOrNull(sym.style.stroke) }, numRecN('lineWidth', sym.style.lineWidth),
      { silent: !!sym.silent }, rectRec(sym.getBoundingRect())),
      label: lab ? textRecOf(lab) : null,
    });
  });
  const bgShape = bgEl.shape;
  rec.view = {
    itemAlign: view._getItemAlign(), labels: labels == null ? false : labels, endsText,
    group: Object.assign(numRec('x', group.x), numRec('y', group.y)),
    children,
    bboxBackground: cap.bg,
    background: Object.assign({
      shape: { x: hex(bgShape.x), y: hex(bgShape.y), width: hex(bgShape.width), height: hex(bgShape.height), r: bgShape.r == null ? null : hex(bgShape.r) },
      shapeText: { x: text(bgShape.x), y: text(bgShape.y), width: text(bgShape.width), height: text(bgShape.height) },
    }, { z2: bgEl.z2, fill: colRecOrNull(bgEl.style.fill), stroke: colRecOrNull(bgEl.style.stroke) }, numRec('lineWidth', bgEl.style.lineWidth),
    rectRec(bgEl.getBoundingRect())),
    bboxPosition: cap.pos,
  };
  must(Object.is(num(cap.pos.after.x), group.x) && Object.is(num(cap.pos.after.y), group.y), key + ': the group moved after positionGroup');
  return rec;
}

function recordSeries(chart, def, vms) {
  const gm = chart.getModel();
  const out = [];
  gm.eachSeries(sm => {
    const targeting = vms.filter(vm => vm.isTargetSeries(sm));
    if (!targeting.length) return;
    const data = sm.getData();
    const drawType = data.getVisual('drawType');
    const sStyle = data.getVisual('style');
    const store = data.getStore();
    const dims = targeting.map(vm => {
      const dimIndex = vm.getDataDimensionIndex(data);
      return { vm: vm.componentIndex, dimIndex, dimName: data.getDimension(dimIndex) };
    });
    const sym = data.getVisual('symbol');
    const ss = data.getVisual('symbolSize');
    must(typeof sym !== 'function' && typeof ss !== 'function', def.id + ': a symbol callback');
    const s = {
      index: sm.seriesIndex, type: sm.subType, drawType, color: colRec(sStyle[drawType]), opacity: hexOrNull(sStyle.opacity),
      symbol: sym == null ? null : clone(sym), symbolSize: ss == null ? null : clone(ss),
      targetedBy: targeting.map(vm => vm.componentIndex), dims, rows: [],
    };
    for (let i = 0; i < data.count(); i++) {
      const raw = data.getRawDataItem(i);
      const row = { i, rawIndex: data.getRawIndex(i) };
      if (raw && raw.visualMap === false) row.skip = true;
      row.values = targeting.map((vm, k) => {
        const v = store.get(data.getDimensionIndex(dims[k].dimIndex), i);
        const pl = vm.getPieceList();
        const piece = VisualMappingClass.findPieceIndex(v, pl);
        const closest = VisualMappingClass.findPieceIndex(v, pl, true);
        return {
          vm: vm.componentIndex, value: typeof v === 'number' ? hex(v) : null, valueText: String(v), valueString: typeof v === 'string' ? v : null,
          piece: piece == null ? null : piece, closest: closest == null ? null : closest, state: vm.getValueState(v),
        };
      });
      const st = data.getItemVisual(i, 'style');
      row.fill = colRec(st[drawType]);
      Object.assign(row, numRecN('opacity', st.opacity));
      const isym = data.getItemVisual(i, 'symbol');
      const iss = data.getItemVisual(i, 'symbolSize');
      row.symbol = isym == null ? null : clone(isym);
      row.symbolSize = iss == null ? null : clone(iss);
      s.rows.push(row);
    }
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
        outerColors: meta.outerColors.map(x => (x === '' ? Object.assign({}, UNDEF_COLOUR, { css: '' }) : colRec(x))),
        stops: meta.stops.map(stp => {
          const o = { value: hex(stp.value), valueText: text(stp.value), color: colRec(stp.color) };
          if (axis && sm.subType === 'line') Object.assign(o, numRec('coord', axis.toGlobalCoord(axis.dataToCoord(stp.value))));
          return o;
        }),
      };
    });
    if (sm.subType === 'line') {
      const g = cs.master.getRect();
      s.grid = Object.assign(rectRec(g));
      s.lineStyleColorWritten = !!(sm.option.lineStyle && sm.option.lineStyle.color != null);
      const view = chart.getViewOfSeriesModel(sm);
      must(view._polyline, def.id + ': no polyline');
      s.polyline = paintRec(view._polyline.style.stroke);
      s.area = view._polygon ? paintRec(view._polygon.style.fill) : null;
    }
    out.push(s);
  });
  return out;
}

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));

function recordCase(def) {
  const source = def.gallery ? gallery(def.gallery) : def.option;
  const optionText = JSON.stringify(source);
  CAPTURE = new Map();
  return runChart(JSON.parse(optionText), chart => {
    chart.__oracleOption = JSON.parse(optionText);
    const vms = chart.getModel().findComponents({ mainType: 'visualMap' });
    must(vms.length >= 1, def.id + ': no visualMap');
    const rec = {
      id: def.id, groups: def.groups, note: def.note, width: chart.getWidth(), height: chart.getHeight(),
      gallery: def.gallery || null, componentOnly: !!def.componentOnly, option: JSON.parse(optionText),
    };
    rec.visualMaps = vms.map(m => recordVM(chart, m, def.id + '/' + m.componentIndex));
    if (!def.componentOnly) rec.series = recordSeries(chart, def, vms);
    return rec;
  });
}

// ---------- the cases ----------
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);
const barOpt = (vm, data) => ({
  xAxis: { type: 'category', data: cat((data || [10, 50, 90]).length) }, yAxis: {}, visualMap: vm,
  series: [{ type: 'bar', data: data || [10, 50, 90] }],
});
const P = o => Object.assign({ type: 'piecewise' }, o);
const scatterCat = (vm, data) => ({ xAxis: {}, yAxis: {}, visualMap: vm, series: [{ type: 'scatter', data }] });

const CASES = [
  // the splitNumber path
  { id: 'S1', groups: ['S'], note: 'splitNumber 5 on [0, 100] (vertical default); rows on the piece ends, outside the extent and between',
    option: barOpt(P({ min: 0, max: 100 }), [-10, 0, 20, 30, 50, 99.5, 100, 150]) },
  { id: 'S2', groups: ['S'], note: "splitNumber 5 on [0, 1000], horizontal, left 'center' (calendar-heatmap shape)",
    option: barOpt(P({ min: 0, max: 1000, orient: 'horizontal', left: 'center', top: 65 }), [0, 199, 200, 201, 999, 1000]) },
  { id: 'P2', groups: ['P2', 'S'], note: 'splitNumber 3 on [0, 100]: splitStep 33.333.. -> precision auto 5, written back into the labels',
    option: barOpt(P({ min: 0, max: 100, splitNumber: 3 }), [10, 33.33333, 33.333333, 66.66666, 90]) },
  { id: 'P3', groups: ['P3', 'S'], note: 'splitNumber 7 on [0, 200] minOpen maxOpen: precision 5 and the ACCUMULATED curr (171.42857999999998)',
    option: barOpt(P({ min: 0, max: 200, splitNumber: 7, minOpen: true, maxOpen: true }), [-5, 0, 28.57143, 171.42858, 171.42857999999998, 200, 250]) },
  { id: 'S4', groups: ['S'], note: 'splitNumber 4 on [0, 10] with precision 2 written: splitStep 2.5 kept at precision 2',
    option: barOpt(P({ min: 0, max: 10, splitNumber: 4, precision: 2 }), [1, 2.5, 7.5, 10]) },
  { id: 'S5', groups: ['S'], note: "splitNumber '4' (a string, parseInt), min 90 > max 10 (asc), precision 1 auto to 1",
    option: barOpt(P({ min: 90, max: 10, splitNumber: '4', precision: 1 }), [10, 30, 50, 70, 90]) },
  { id: 'S6', groups: ['S'], note: "type 'piecewise' written with calculable true: calculable changes nothing in a piecewise model",
    option: barOpt(P({ min: 0, max: 100, splitNumber: 4, calculable: true }), [10, 60]) },
  { id: 'S7', groups: ['S', 'P10'], note: 'splitNumber 4 on [0, 200], horizontal inverse (P10): the view reverses, the model does not',
    option: barOpt(P({ min: 0, max: 200, splitNumber: 4, orient: 'horizontal', inverse: true }), [0, 50, 100, 150, 200]) },
  { id: 'S8', groups: ['S'], note: "splitNumber 5 on [0, 100], outOfRange {color: '#999'}, selected {1: false, 3: false}: unselected rows and items",
    option: barOpt(P({ min: 0, max: 100, outOfRange: { color: '#999' }, selected: { 1: false, 3: false } }), [10, 30, 50, 70, 90, 120]) },
  { id: 'S9', groups: ['S'], note: 'splitNumber 3 on [0, 1] precision 0 -> 5; vertical inverse (the model list not reversed; the view keeps low at top)',
    option: barOpt(P({ min: 0, max: 1, splitNumber: 3, inverse: true }), [0.1, 0.5, 0.9]) },
  // the pieces path
  { id: 'P4', groups: ['P4'], note: 'pieces given unsorted [>150, (50,100], (100,150] #f00, <=50 label low]: reformIntervals sorts them',
    option: barOpt({ pieces: [{ gt: 150 }, { gt: 50, lte: 100 }, { gt: 100, lte: 150, color: '#f00' }, { lte: 50, label: 'low' }] }, [10, 50, 75, 100, 125, 150, 175]) },
  { id: 'P5', groups: ['P5'], note: 'pieces [{value 100 #000}, {min 50, max 150}, {min 150}]: the value piece is clipped to [150,150] close [0,1] and SPLICED out',
    option: barOpt({ pieces: [{ value: 100, color: '#000' }, { min: 50, max: 150 }, { min: 150 }] }, [40, 50, 100, 150, 160]) },
  { id: 'P6', groups: ['P6'], note: 'pieces with symbol only: the piece visual types complete inRange/outOfRange (no colour at all), scatter',
    option: { xAxis: {}, yAxis: {}, visualMap: { pieces: [{ lt: 100, symbol: 'rect' }, { gte: 100, symbol: 'circle' }] },
      series: [{ type: 'scatter', data: [[0, 50], [1, 99], [2, 100], [3, 180]] }] } },
  { id: 'P7', groups: ['P7'], note: "pieces, selectedMode 'single', selected {0: false}: only the first selected piece stays",
    option: barOpt({ pieces: [{ lt: 100 }, { gte: 100, lt: 150 }, { gte: 150 }], selectedMode: 'single', selected: { 0: false } }, [50, 120, 170]) },
  { id: 'P11', groups: ['P11'], note: 'overlapping pieces [0,100], [50,150], (150,150): -> [0,100], (100,150]; the empty (150,150) deleted',
    option: barOpt({ pieces: [{ gte: 0, lte: 100 }, { gte: 50, lte: 150 }, { gt: 150, lt: 150 }] }, [0, 75, 100, 101, 150, 151]) },
  { id: 'P12', groups: ['P12'], note: 'lt/gte/gt mix with rows on every open and closed end: <50, [50,100], >100',
    option: barOpt({ pieces: [{ lt: 50, color: '#00f' }, { gte: 50, lte: 100, color: '#0f0' }, { gt: 100, color: '#f00' }] }, [49.999, 50, 100, 100.001]) },
  { id: 'P13', groups: ['P13'], note: 'pieces with gaps (gt 1 lt 3, gt 5 lt 7) and outOfRange #999: rows in the gaps and on the open ends',
    option: barOpt({ pieces: [{ gt: 1, lt: 3, color: '#f00' }, { gt: 5, lt: 7, color: '#00f' }], outOfRange: { color: '#999' } }, [0, 1, 2, 3, 4, 5, 6, 7, 8]) },
  { id: 'P14', groups: ['P14'], note: "fractional ends at precision 0 (labels round: 1.5 -> '2'), a value piece, a label; formatter '{value} to {value2}'",
    option: barOpt({ pieces: [{ gt: 1.5, lte: 2.25 }, { value: 3, label: 'three' }, { gt: 3.5 }], formatter: '{value} to {value2}' }, [2, 3, 4]) },
  { id: 'P15', groups: ['P15'], note: 'ec2 splitList with start/end (the preprocessor renames them to pieces min/max)',
    option: barOpt({ splitList: [{ start: 0, end: 50 }, { start: 50, end: 100, color: '#123456' }] }, [25, 50, 75]) },
  { id: 'P16', groups: ['P16'], note: "pieces with colours, selected {0: false}, outOfRange {color: '#999'}: the deselected piece's own colour is NOT used",
    option: barOpt({ pieces: [{ lte: 50, color: '#f00' }, { gt: 50, color: '#00f' }], selected: { 0: false }, outOfRange: { color: '#999' } }, [10, 90]) },
  { id: 'P17', groups: ['P17'], note: 'pieces with opacity and symbolSize visuals on a scatter (completion adds opacity/symbolSize defaults, not colour)',
    option: { xAxis: {}, yAxis: {}, visualMap: { pieces: [{ lt: 10, opacity: 0.3, symbolSize: 5 }, { gte: 10, opacity: 0.9 }], dimension: 1 },
      series: [{ type: 'scatter', data: [[0, 5], [1, 15], [2, 10]] }] } },
  { id: 'P18', groups: ['P18'], note: 'a value piece is the CLOSEST piece of a value in none: 4 -> the value 5, 8 -> the interval from 10; outOfRange two colours',
    option: barOpt({ pieces: [{ value: 5 }, { gte: 10, lte: 20 }], outOfRange: { color: ['#f00', '#00f'] } }, [4, 8, 5, 15, 25]) },
  { id: 'P19', groups: ['P19'], note: 'a tie on the low end sorted by its close: reversed to [(0, 5], [0, 10]], the run test puts [0, 10] first (the high end would not) and (0, 5] is emptied',
    option: barOpt({ pieces: [{ gte: 0, lte: 10 }, { gt: 0, lte: 5 }] }, [0, 3, 7]) },
  { id: 'P20', groups: ['P20'], note: '{min: 10} alone: min with an open max opens the low end, (10, Infinity); 10 is in no piece',
    option: barOpt({ pieces: [{ min: 10 }] }, [5, 10, 20]) },
  { id: 'P21', groups: ['P21'], note: '{gte: 5, lte: 5}: a closed point gets a value (text 5, the value pass); (5, Infinity) after it',
    option: barOpt({ pieces: [{ gte: 5, lte: 5 }, { gt: 5 }] }, [5, 6]) },
  // the categories path
  { id: 'C1', groups: ['T6', 'P8'], note: "categories ['a','c','e'] vertical: the piece list is REVERSED; a string column, 'x' not a category",
    option: scatterCat(P({ categories: ['a', 'c', 'e'], dimension: 2, inRange: { color: ['#f00', '#0f0', '#00f'] }, outOfRange: { color: '#ddd' } }),
      [[1, 2, 'a'], [2, 3, 'c'], [3, 4, 'e'], [4, 5, 'x']]) },
  { id: 'C2', groups: ['T6'], note: "categories horizontal (not reversed), selected {c: false}, left 'center'",
    option: scatterCat(P({ categories: ['a', 'c', 'e'], dimension: 2, orient: 'horizontal', left: 'center', selected: { c: false },
      inRange: { color: ['#f00', '#0f0', '#00f'] } }), [[1, 2, 'a'], [2, 3, 'c'], [3, 4, 'e']]) },
  { id: 'C3', groups: ['P9'], note: "categories with an object colour {a, e, '': default}: 'c' has no visual, the default slot [-1]",
    option: scatterCat(P({ categories: ['a', 'c', 'e'], dimension: 2, inRange: { color: { a: '#f00', e: '#00f', '': '#888' } } }),
      [[1, 2, 'a'], [2, 3, 'c'], [3, 4, 'e'], [4, 5, 'x']]) },
  { id: 'C4', groups: ['P8'], note: 'categories on a category-axis dimension: the store holds ordinals, never a category -> every row outOfRange',
    option: { xAxis: { type: 'category', data: ['a', 'c', 'e'] }, yAxis: {},
      visualMap: P({ categories: ['a', 'c', 'e'], dimension: 0, inRange: { color: ['#f00', '#0f0', '#00f'] } }), series: [{ type: 'bar', data: [1, 2, 3] }] } },
  // the view
  { id: 'V1', groups: ['view'], note: 'showLabel false (vertical): items only, no labels; selectedMode false (silent items)',
    option: barOpt(P({ min: 0, max: 100, showLabel: false, selectedMode: false })) },
  { id: 'V2', groups: ['view'], note: "itemSymbol 'circle', horizontal, text ['High', 'Low']: the circle rect x = w/2 - r",
    option: barOpt(P({ min: 0, max: 100, itemSymbol: 'circle', orient: 'horizontal', left: 'center', text: ['High', 'Low'] })) },
  { id: 'V3', groups: ['view', 'p5d'], note: "vertical text ['High', 'Low'] (p5 d): labels hidden, ends centred; layout.box's next-rect term gives ys 0, 23, 47 ...",
    option: barOpt(P({ min: 0, max: 100, text: ['High', 'Low'] })) },
  { id: 'V4', groups: ['view'], note: "vertical right 10, text, showLabel true: item align right, labels at -textGap, ends at x itemWidth",
    option: barOpt(P({ min: 0, max: 100, right: 10, text: ['High', 'Low'], showLabel: true })) },
  { id: 'V5', groups: ['view'], note: "text ['High', ''] horizontal: the empty end draws nothing",
    option: barOpt(P({ min: 0, max: 100, orient: 'horizontal', text: ['High', ''] })) },
  { id: 'V6', groups: ['view'], note: 'itemWidth 30, itemHeight 20, itemGap 5, textGap 5, padding [5, 10], border 1 #333 on #eee, top middle',
    option: barOpt(P({ min: 0, max: 100, itemWidth: 30, itemHeight: 20, itemGap: 5, textGap: 5, padding: [5, 10], borderWidth: 1,
      borderColor: '#333', backgroundColor: '#eee', top: 'middle' })) },
  { id: 'V7', groups: ['view'], note: "horizontal inverse with text ['High', 'Low'] and showLabel: the ends are NOT reversed (the list is)",
    option: barOpt(P({ min: 0, max: 100, splitNumber: 3, orient: 'horizontal', inverse: true, text: ['High', 'Low'], showLabel: true, bottom: 10 })) },
  { id: 'V8', groups: ['view'], note: 'show false: nothing drawn, the model still encodes', option: barOpt(P({ min: 0, max: 100, show: false }), [10, 90]) },
  { id: 'V9', groups: ['view'], note: 'itemWidth 20.3, itemHeight 14.1 vertical left 380: item align from getItemAlign; non-round sizes',
    option: barOpt(P({ min: 0, max: 100, itemWidth: 20.3, itemHeight: 14.1, left: 380, itemSymbol: 'circle' })) },
  // line series with a piecewise visualMeta
  { id: 'L1', groups: ['meta'], note: 'line with areaStyle, splitNumber 4 on [0, 200] on y: the visualMeta stops, the gradient on polyline and area',
    option: { xAxis: { type: 'category', data: cat(7) }, yAxis: {}, visualMap: P({ show: false, min: 0, max: 200, splitNumber: 4 }),
      series: [{ type: 'line', areaStyle: {}, data: [20, 90, 150, 180, 200, 60, 120] }] } },
  { id: 'L2', groups: ['meta'], note: 'line on x (dimension 0) with gap pieces and minOpen/maxOpen-free outer colours',
    option: { xAxis: { type: 'value' }, yAxis: {}, visualMap: { show: false, dimension: 0, pieces: [{ gte: 2, lt: 4, color: '#f00' }, { gte: 6, lte: 8, color: '#00f' }] },
      series: [{ type: 'line', data: [[0, 1], [3, 2], [5, 3], [7, 2], [10, 4]] }] } },
  // the gallery
  { id: 'G-area-pieces', groups: ['gallery'], note: 'area-pieces (gallery), verbatim: gt/lt pieces on x, rows on the open ends', gallery: 'area-pieces' },
  { id: 'G-line-sections', groups: ['gallery'], note: 'line-sections (gallery), verbatim: lte/gt pieces on x', gallery: 'line-sections' },
  { id: 'G-line-aqi', groups: ['gallery'], note: 'line-aqi (gallery), verbatim: 6 coloured pieces, outOfRange #999, right 10 top 50', gallery: 'line-aqi', omitOption: true },
  { id: 'G-candlestick-brush', groups: ['gallery'], note: 'candlestick-brush (gallery), verbatim: value pieces +-1 on the bar series 5, dimension 2', gallery: 'candlestick-brush',
    omitOption: true },
  { id: 'G-calendar-heatmap', groups: ['gallery'], note: 'calendar-heatmap (gallery), verbatim: the component only (the heatmap series is not recorded)',
    gallery: 'calendar-heatmap', componentOnly: true },
];

// ---------- the guards ----------
const GUARDS = [
  { id: 'reform-splice', mutation: 'reformIntervals does not splice an emptied piece', mut: { noSplice: true }, named: ['P5', 'P11'] },
  { id: 'reform-sort', mutation: 'reformIntervals does not sort', mut: { noSort: true }, named: ['P4'] },
  { id: 'reform-clamp', mutation: 'reformIntervals does not clamp an end at or below curr', mut: { noClampSweep: true }, named: ['P11', 'S1'] },
  { id: 'split-multiplied', mutation: 'splitNumber piece ends multiplied (e0 + step * i) instead of the accumulated curr', mut: { multiplied: true }, named: ['P3'] },
  { id: 'split-writeback', mutation: 'the auto precision not written back (the labels use the option precision)', mut: { noWriteBack: true }, named: ['P2', 'P3', 'S9'] },
  { id: 'split-autoprecision', mutation: 'no precision auto-derivation (splitStep rounded at the option precision)', mut: { noAutoPrecision: true }, named: ['P2', 'P3'] },
  { id: 'split-last', mutation: 'the last piece ends at curr + splitStep instead of the extent max', mut: { lastNotExtent: true }, named: ['P2', 'P3'] },
  { id: 'extent-asc', mutation: 'no asc on [min, max]', mut: { noAsc: true }, named: ['S5'] },
  { id: 'categories-reverse', mutation: 'categories not reversed when vertical', mut: { noCategoryReverse: true }, named: ['C1'] },
  { id: 'find-close', mutation: 'findPieceIndex ignores the close flags (always <=)', mut: { closeIgnored: true }, named: ['P12', 'P13', 'G-area-pieces'] },
  { id: 'find-value', mutation: 'findPieceIndex without the value pass (value pieces found through their [v, v] interval only)', mut: { noValuePass: true },
    named: ['C1'] },
  { id: 'normalize-closest', mutation: 'the piecewise normaliser without the closest fallback (undefined outside every piece)', mut: { noClosest: true }, named: ['S1', 'P13'] },
  { id: 'selected-ignored', mutation: 'selected ignored (every piece in range)', mut: { selectedIgnored: true }, named: ['S8', 'P7', 'C2', 'P16'] },
  { id: 'selected-single', mutation: "selectedMode 'single' not enforced", mut: { noSingle: true }, named: ['P7'] },
  { id: 'outofrange-piece-visual', mutation: 'the outOfRange mappings keep the piece visuals', mut: { outOfRangeKeepsPieceVisual: true }, named: ['P16'] },
  { id: 'special-visual', mutation: 'piece visuals ignored (getSpecifiedVisual never answers)', mut: { specialIgnored: true },
    named: ['P12', 'G-line-aqi', 'G-candlestick-brush', 'G-line-sections'] },
  { id: 'piece-defaults', mutation: 'completeVisualOption does not complete the visual types found in pieces', mut: { noPieceDefaults: true }, named: ['P6', 'P17'] },
  { id: 'represent-finite', mutation: 'the represent value of an open-ended piece is its finite end instead of +-Infinity', mut: { repFinite: true },
    named: ['G-line-aqi', 'P3'] },
  { id: 'meta-gap', mutation: 'getVisualMeta does not fill the gaps with outOfRange stops', mut: { noGapFill: true }, named: ['G-area-pieces', 'P13', 'L2'] },
  { id: 'view-reverse', mutation: 'the view list not reversed (vertical low at the top)', mut: { viewNoReverse: true }, named: ['S1', 'S7', 'G-line-aqi'] },
  { id: 'view-ends-reverse', mutation: 'the ends text not reversed when the list is not', mut: { endsNoReverse: true }, named: ['V2', 'V5'] },
  { id: 'view-ends-orient', mutation: 'the ends text reversed whenever horizontal (also when the list is reversed)', mut: { endsFollowOrient: true }, named: ['V7'] },
  { id: 'view-showlabel', mutation: 'showLabel defaults to true even with text', mut: { showLabelAlways: true }, named: ['V2', 'V3'] },
  { id: 'view-next-term', mutation: "layout.box without the next child's rect term", mut: { noNextTerm: true }, named: ['V3', 'V2'] },
  { id: 'view-label-opacity', mutation: 'an outOfRange item label not at opacity 0.5', mut: { labelOpacityIgnored: true }, named: ['S8', 'C2', 'P7'] },
  { id: 'view-itemsymbol', mutation: 'itemSymbol ignored (roundRect)', mut: { itemSymbolIgnored: true }, named: ['V2', 'V9'] },
  { id: 'view-bg-stroke', mutation: "the background's stroke not in the position bbox", mut: { bgStrokeIgnored: true }, named: ['V6'] },
  { id: 'line-tiny', mutation: 'the line gradient tinyExtent 0 instead of 10', mut: { tiny0: true }, named: ['L1', 'L2', 'G-line-aqi', 'G-area-pieces'] },
  { id: 'view-circle-rect', mutation: 'a circle item measured as the full item rect', mut: { circleAsRect: true }, named: ['V2', 'V9'] },
];

// ---------- the run ----------
function generate() {
  MEASURE = new Map();
  VisualMappingClass = null;
  hookViews();
  const cases = CASES.map(recordCase);
  const gradientColor = runChart({ series: [] }, ch => ch.getModel().get('gradientColor').slice()).map(colRec);
  const measure = Array.from(MEASURE.values())
    .sort((a, b) => (a.font === b.font ? (a.string < b.string ? -1 : a.string > b.string ? 1 : 0) : a.font < b.font ? -1 : 1))
    .map(m => ({ string: m.string, font: m.font, width: hex(m.width), widthText: text(m.width), height: hex(m.height), heightText: text(m.height) }));
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED,
    api: {
      pieces: 'vm.getPieceList(); key = vm.getSelectedMapKey(piece); state = vm.getValueState(vm.getRepresentValue(piece))',
      model: 'vm.option after setOption: splitNumber, precision, selected, inRange, outOfRange, target, controller; vm._mode',
      mappings: 'vm.targetVisuals / vm.controllerVisuals [state]: own keys, then the hidden __alphaForOpacity; mapping.option.visual, categories, hasSpecialVisual',
      order: 'VisualMapping.prepareVisualTypes(vm.targetVisuals[state]) / (vm.controllerVisuals[state])',
      rows: "data.getStore().get(dimIndex, i); VisualMapping.findPieceIndex(v, pieceList[, true]); vm.getValueState(v); data.getItemVisual(i, 'style' | 'symbol' | 'symbolSize')",
      visualMeta: "data.getVisual('visualMeta'); coord = axis.toGlobalCoord(axis.dataToCoord(stop.value))",
      line: 'chart.getViewOfSeriesModel(sm)._polyline.style.stroke / ._polygon.style.fill',
      view: 'view.group children in order (item groups tagged through a wrapped _enableHoverLink); view._getItemAlign(); the symbol path shape/style/getBoundingRect; the label Text style/getBoundingRect',
      bbox: 'VisualMapView.prototype.renderBackground / positionGroup wrapped: group.getBoundingRect() before the originals run; layoutRect = echarts.helper.getLayoutRect(defaults({width, height}, getBoxLayoutParams()), [0,0,W,H])',
      measure: 'echarts.format.getTextRect(string, font)',
    },
    notes: [
      'The 6.1.0 dist build and the src tree agree on every piecewise function this oracle exercises: PiecewiseModel (dist/echarts.js:91088-91473 = src/component/visualMap/PiecewiseModel.ts), PiecewiseView (dist 91475-91637 = PiecewiseView.ts), reformIntervals (dist 8168-8195 = src/util/number.ts:716-756), VisualMapping.findPieceIndex / normalizers (dist 59242-59291, 59520-59540 = src/visual/VisualMapping.ts:475-540, 711-732), layout.box (dist 18135-18184 = src/util/layout.ts:74-141), helper.getItemAlign (dist 90225-90246 = helper.ts:40-72), getControllerVisual (VisualMapView.ts:104-152), formatValueText (dist 89638 = VisualMapModel.ts:351-408).',
      'reformIntervals sorts with V8 Array.prototype.sort and a comparator that never answers 0 (littleThan ? -1 : 1); on lists this short V8 is a stable binary insertion sort, so ties keep their order after normalizeReverse.',
      'splitNumber pieces: the piece ends are the ACCUMULATED curr (curr += splitStep) with splitStep rounded at the auto precision; the last piece ends exactly at the extent max. The auto precision (at most 5) is WRITTEN BACK to option.precision before the labels are formatted.',
      'Pieces: a piece that reformIntervals collapses to a point without both ends closed is spliced out, and its original index disappears from the selected map (P5: keys 1, 2). A value piece inside another piece is always collapsed and deleted (P5); the value pass of findPieceIndex only matters for surviving value pieces (candlestick-brush) and categories.',
      'Categories: the piece list is reversed when vertical and not inverse (C1: e, c, a); the category MAPPING keeps option.categories order (categoryMap a:0, c:1, e:2); preprocessForSpecifiedCategory then walks i from the end and, for every visual[i] == null, deletes categoryMap[categories[i]] but pops the LAST category (src/visual/VisualMapping.ts:584-591; dist/echarts.js:59418-59424): the C3 colour object has no c, so categoryMap loses c (c falls to the default slot visual[-1] = #888) while the categories list of the mapping loses e (recorded [a, c]); only categoryMap is ever read. A category dimension that is a category AXIS holds ordinals, so no row ever matches (C4).',
      'Unselected pieces: rows and items take the outOfRange mappings, whose pieceList copies have visual = null, so a piece colour never shows for a deselected piece (P16). The item label of an outOfRange piece is drawn at opacity 0.5.',
      "The item symbol is createSymbol(controller symbol, 0, 0, itemWidth, itemHeight, controller colour): the controller symbolSize is not used. A circle item's rect is [w/2 - r, h/2 - r, (cx + r) - (cx - r), ...] with r = min(w, h)/2 (V2, V9).",
      "layout.box: move = rect.height + (-next.rect.y + rect.y) (vertical; x/width horizontal). The term is non-zero only when a child's rect does not start at 0: an ends text next to an item (V3: 'High' at y 1 -> items at 23, 47, ...). In line-aqi every child is an item group whose rect starts at y 0, so the term is 0 there (items at 0, 24, 48, ...): the audit's 'line-aqi red without the next-rect term' does not hold; V3 carries that guard.",
      'getRepresentValue: [-Infinity, b] -> -Infinity, [a, Infinity] -> Infinity, [-Infinity, Infinity] -> 0, a value -> the value, else (a + b) / 2; the item colour and the label opacity come from that value (findPieceIndex of +-Infinity lands in the open piece).',
      'getVisualMeta supplements [-Infinity, first low] and [last high, Infinity], fills every gap with an outOfRange stop pair, and sends the open ends to outerColors. LineView then clips and builds the gradient exactly as for the continuous meta (visualmap-encode.js).',
      'Rows of line-aqi and candlestick-brush are the rows left after their dataZoom filter (rawIndex is the source index).',
    ],
    gradientColor, measure, cases,
  };
  return out;
}

// the self-checks; returns the guards
function check(out) {
  const top = { gradientColor: out.gradientColor };
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    const d = caseDiffs(c, top, {});
    must(!d.length, c.id + ': the transcription differs at ' + d.slice(0, 4).map(x => x.field + ' (' + x.upstream + ' vs ' + x.mutated + ')').join('; '));
    for (const vm of c.visualMaps) {
      if (!vm.view) continue;
      for (const ch of vm.view.children) {
        const t = ch.kind === 'endText' ? ch.text : ch.label;
        if (!t) continue;
        const r = textRect({ string: t.string, font: t.font, x: num(t.x), y: num(t.y), align: t.align, verticalAlign: t.verticalAlign });
        must(RK.every(k => hex(r[k]) === t.rect[k]), c.id + ': the text rect of ' + JSON.stringify(t.string) + ' does not follow from measure[]');
      }
    }
  }
  // audit anchors
  const P2 = byId.P2.visualMaps[0];
  must(P2.model.precision === 5 && P2.pieces[0].text === '0.00000 - 33.33333' && P2.pieces[1].intervalText.join() === '33.33333,66.66666', 'P2 anchor');
  const P3 = byId.P3.visualMaps[0];
  must(P3.pieces.some(p => p.intervalText && p.intervalText[0] === '171.42857999999998'), 'P3 anchor: ' + P3.pieces.map(p => p.intervalText).join(' '));
  const P5 = byId.P5.visualMaps[0];
  must(P5.pieces.length === 2 && JSON.stringify(P5.model.selected) === '{"1":true,"2":true}', 'P5 anchor');
  const C1 = byId.C1.visualMaps[0];
  must(C1.pieces.map(p => p.valueString).join() === 'e,c,a', 'C1 anchor');
  must(byId.C2.visualMaps[0].pieces.map(p => p.valueString).join() === 'a,c,e', 'C2 anchor');
  const V3 = byId.V3.visualMaps[0].view.children.map(ch => ch.yText).join();
  must(V3 === '0,23,47,71,95,119,142', 'V3 (p5 d) ys ' + V3);
  const aqi = byId['G-line-aqi'].visualMaps[0].view;
  must(aqi.children.map(ch => ch.yText).join() === '0,24,48,72,96,120' && aqi.group.xText + ',' + aqi.group.yText === '755,65', 'line-aqi view');
  must(byId.C4.series[0].rows.every(r => r.values[0].state === 'outOfRange'), 'C4 rows');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let d;
      try {
        d = caseDiffs(c, top, gd.mut);
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
  // Array.from: a hole (a sparse category visual) is written null, as JSON.stringify does
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
  g1.guards = check(g1);
  json1 = serialise(g1);
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
const rows = out.cases.reduce((n, c) => n + (c.series || []).reduce((m, s) => m + s.rows.length, 0), 0);
console.log(out.cases.length + ' cases (' + rows + ' rows), ' + out.measure.length + ' measured strings; ' + (out.guards.length - bad.length) + '/'
  + out.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
