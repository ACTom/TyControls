// Upstream's own answers for the dataZoom SLIDER picture (wf60/upstream.md
// section 4 with 1.2 / 1.3; the processing is datazoom-window.js): where
// SliderZoomView puts the slider (_resetLocation with the box-layout merge and
// the 'ph' placeholders), the percent range and handle ends (_resetInterval),
// the sliderGroup flip / rotation and the view-group offset _positionGroup takes
// from the bounding rect of the sliderGroup BEFORE _updateView ran, and then
// every element as the first render leaves it: background, click panel, filler,
// frame (subPixelOptimize), the two handles (the icon fitted by createSymbol /
// makePath 'center', path data as the proxy holds it), the move handle and its
// icon, the invisible move zone, the three data-shadow groups (polygon +
// polyline, clip rects) and the two handle labels (text, position, alignment).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models and the views
// directly -- never the SVG text. SliderZoomView.prototype._positionGroup and
// ._resetLocation are wrapped (the originals still run): the first to read the
// sliderGroup's bounding rect (and each child's) at the moment upstream reads
// it, the second to catch the layout params object after the 'ph'
// substitution (a temporary Object.prototype.aspect getter: getLayoutRect reads
// positionInfo.aspect). Nothing is painted: in SSR setOption leaves every
// element's global `transform` unset, which is what the strokeNoScale handles'
// getLineScale() sees (1). The storage's display list (the paint order) is read
// last, per chart, because building it computes the transforms. Every chart is
// disposed in a finally.
//
//   node tools/advchart-oracle/datazoom-slider.js
//
// writes tests/fixtures/advchart-datazoom-slider.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as visualmap-view.js / datazoom-window.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000). Every hex field has a readable
//            twin (xText beside x; String(v), '-0' for negative zero); null when
//            absent (twin null).
//   rect     {x, y, width, height} hex + rectText
//   matrix   [a, b, c, d, tx, ty] hex + ...Text: zrender's 2x3; a point maps to
//            (a*x + c*y + tx, b*x + d*y + ty)
//   colour   {css, r, g, b, a, aText, undef}: css the string upstream holds,
//            r/g/b/a zrender's parse (a hex); undef true for undefined / null
//   num-or-string  a layout param: {num: hex, text} for a number, the string
//            itself for a string ('ph', '85%'), null for null or an own
//            undefined (both parse to NaN)
//   path     [{cmd ('M' | 'L' | 'C' | 'Q' | 'A' | 'Z' | 'R'), args [hex],
//            argsText}] -- the element's PathProxy data (el.path.data up to
//            len()): A args are cx, cy, rx, ry, startAngle, deltaAngle, psi,
//            clockwise (1) / anticlockwise (0). A path:// icon whose source
//            proxy holds more than 11 numbers was stored as a Float32Array
//            (PathProxy.toStatic), so every value is exactly a float32 and the
//            fit was rounded to float32 at each store (transformPath: points
//            once, arc cx / cy twice: *= s then += t); a shorter one stays in
//            doubles (the self-check asserts every value of a > 11-number
//            path:// icon is a float32).
//
// Text sizes: measure[] holds zrender's own measurer answer per (string, font)
// (echarts.format.getTextRect: measureWidth + getLineHeight), as in
// visualmap-view.js; a Text element's rect unions its TSpan rect with itself
// (width = (x + w) - x). The transcription derives every label rect from it.
//
// Top level
//   source, W, H, seed, api (how each value was read), notes[]
//   measure[]   {string, font, width, widthText, height, heightText}
//   cases[]     one per chart:
//     id, groups, note, width, height, gallery (file name or null), option (as
//     fed; null for the big gallery files: load the gallery file, fed verbatim)
//     dataZooms[] every dataZoom component in component order. inside / select
//       (the toolbox's) ones: {index, subType} only. Sliders:
//       index, subType 'slider', show (get('show') !== false), noTarget -- when
//       not shown or without a target: nothing else (the view group is empty)
//       resolved   the model's inputs to the view:
//         orient, inverse (the FIRST target axis model's inverse), firstTarget
//         {dim, index}, labelAxis {dim, index, type} (the representative
//         proxy's axis: what the labels format), brushSelect, showDataShadow
//         (JSON), showDetail, handleLabelShow (handleLabel.show || false),
//         handleIcon, moveHandleIcon (strings), handleSize, moveHandleSize
//         (JSON), labelPrecision (JSON, null), labelFormatter (string | null),
//         borderRadius (JSON), z, zlevel, edgeGap (defaultLocationEdgeGap)
//         colours: fillerColor, borderColor, dataBackgroundColor (deprecated),
//         backgroundColor, handleColor (deprecated) -- colour records
//         handleStyle, moveHandleStyle (getItemStyle()), dataBackground,
//         selectedDataBackground {area (getAreaStyle()), line (getLineStyle())}:
//         {fill, stroke (colour), lineWidth, opacity (hex | null)}
//         textStyle {fill (getTextColor(), colour), font (getFont())}
//         layoutInput   the user's own left/right/top/bottom/width/height (JSON)
//         layoutMerged  the model option's six after mergeDefaultAndTheme's
//                       mergeLayoutParam (JSON; an own undefined key omitted)
//         layoutParams  the object getLayoutRect got ('ph' substituted), each
//                       key num-or-string
//         refContainer {x, y, width, height} (numbers), coordRect (rect:
//         _findCoordRect -- the final grid rect), location {x, y} (hex + Text),
//         size [length, thickness] (hex), window {value, percent,
//         percentInverted [hex, hex], valuePrecision hex} (the representative
//         proxy's getWindow()), range (_range = getPercentRange()), handleEnds,
//         handleWidth, handleHeight (hex), moveHandleHeight (brushSelect: the
//         parsePercent'ed option, else null)
//         scaleLabels [s0, s1] | null: category / time only, the scale's own
//                       getLabel({value: Math.round(window.value[i])}) (an
//                       INPUT to the transcription: category name / time format)
//       shadow     null (no series chosen or showDataShadow false), or:
//         seriesIndex, seriesType, thisDim, infoOtherDim (info.otherDim),
//         otherDim (the one used: candlestick getShadowDim() 'open'),
//         otherAxisInverse (bool | null), thisAxisType, count (raw rows),
//         thisDataExtent, otherDataExtent (data.getDataExtent, raw: [hex, hex]),
//         drawn (the three groups exist), area / line: the polygon / polyline
//         points [[hex, hex]] + Text (sliderGroup-local, before the flip)
//       view
//         group      {x, y (+Text), matrix} after _positionGroup
//         sliderGroup {scaleX, scaleY, rotation (hex + Text), local, toGroup
//                    (graphic.getTransform(sliderGroup, group)), global}
//         position   what _positionGroup read: sliderRect (sliderGroup.
//                    getBoundingRect() -- sliderGroup-local, no transform yet),
//                    children [{role, included (!ignore && !invisible), local
//                    (matrix at that moment), rect}], groupRect (group.
//                    getBoundingRect([sliderGroup]) with the flip / rotation),
//                    group {x, y}
//         elements[] every displayable of the view in PAINT order (the storage
//                    display list: zlevel, z, z2, stable):
//                    role (background, clickPanel, filler, frame, handle0,
//                    handle1, moveHandle, moveHandleIcon, moveZone,
//                    shadowPolygon{i}, shadowPolyline{i}, label0, label1),
//                    painted (false only for a label whose text is '': a
//                    ZRText paints through its TSpans and '' makes none; such
//                    labels come last, in traversal order),
//                    type, parent (the parent's role: group, sliderGroup,
//                    shadow{i}), z, z2, zlevel, silent, invisible, ignore,
//                    x, y, scaleX, scaleY, rotation (hex + Text), local, global
//                    (graphic.getTransform(el): the view group included),
//                    style {fill, stroke (colour), lineWidth, opacity (hex),
//                    strokeNoScale}, rect (el.getBoundingRect(), local, with the
//                    stroke), globalRect (rect through global) and by type:
//                      rect: shape {x, y, width, height, r (JSON)}, subPixelOptimize
//                      path (the handles and the move icon): iconKind ('symbol':
//                      a built-in name, with shape {symbolType, x, y, width,
//                      height}; 'path': a path:// icon), path, pathRect
//                      (el.path.getBoundingRect(): no stroke)
//                      polygon / polyline: points 'area' / 'line' (the shadow's
//                      arrays), pathLen
//                      text: text, textX, textY (style x / y, view-group
//                      coords; x / y are the element's own, 0), align,
//                      verticalAlign, font, fill (no style record)
//         shadowGroups[] {i, selected (i === 1), local, clip {x, y, width,
//                    height} (hex + Text), rect (the group's getBoundingRect())}
//         finalSliderRect  sliderGroup.getBoundingRect() after the render
//         finalGroupRect   group.getBoundingRect() (labels only when visible) +
//                    finalGroupGlobalRect (through the group matrix)
//   guards[]  one per mutation: id, mutation, named (cases that must change),
//             changed (cases the mutated transcription no longer reproduces),
//             ok = named is a subset of changed, differs (the first differing
//             fields of each named case)
//
// ---------------------------------------------------------------------------
// The transcription (checked field by field against every recorded value, bit
// for bit): the box-layout merge (mergeLayoutParam over the slider defaults),
// _resetLocation (positionInfo, the 'ph' substitution, getLayoutRect),
// _resetInterval, createSymbol (the handleIcon 'path://' prefix rule, built-in
// symbol shapes, makePath 'center': createPathProxyFromString with processArc,
// toStatic's Float32Array for len > 11, centerGraphic, calculateTransform,
// transformPath with its float32 stores) and PathProxy.getBoundingRect (fromLine
// / fromCubic with cubicExtrema / fromQuadratic / fromArc, PathProxy.arc's
// normalizeArcAngles), the handle width and placement, Rect.buildPath with
// subPixelOptimizeRect and the rounded-rect path, the move handle / icon / zone,
// the data shadow (extents, step, stride, the accumulated coordinate, time
// coordinates, empty values) and the clip segments, Path.getBoundingRect's
// stroke inflation (fill -> lineWidth, no fill -> max(lineWidth,
// strokeContainThreshold 5), strokeNoScale with the unset transform -> 1),
// Group.getBoundingRect (BoundingRect.applyTransform fast path / 4 corners,
// union with itself), the sliderGroup table with Math.cos(Math.PI / 2), the
// group offset, graphic.getTransform / transformDirection, the label text
// (showDetail, labelPrecision 'auto', toFixed, labelFormatter string) and
// position, the text rects from measure[], and the paint order (a stable sort
// on z2 over the traversal). Its inputs are `resolved`, each element's
// effective style, measure[] and -- for the shadow -- the raw store values of
// the two dims (data.each([thisDim, otherDim]) on getRawData(), kept in memory
// only: the port rebuilds them from the option).
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every slider; _positionGroup moved the group by location minus the
// rect it read; the captured layout params give the location / size through
// upstream's own getLayoutRect; every element's style is the resolved one;
// every value of a path:// icon longer than 11 numbers is a float32; anchors
// (upstream.md 4.3: groups D1 (122.79999995231628, 584.5), D2 (122.5, 585), D3
// (120.7000000178814, 585), D6b (722.5, 548.5), D8b (755.5,
// 522.4999999999998); D1 handle fitted rect and width 6.000000536441803, D1
// positionGroup sliderRect x / y / height; D4 handles at 151 / 449; D5 ends
// 199.99799999999996 / 400.002; D21 shows the host window 10-50; D16b shadow
// dim 'open'; D20 draws nothing; dataset-encode1 has no slider); every guard
// is ok (each named case changes); the fixture holds no  ;
// the written JSON parses back; two generations in the process give the same
// bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-datazoom-slider.json');
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

// ---------- number, rect, matrix and colour records ----------
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
const RK = ['x', 'y', 'width', 'height'];
const rectRec = (name, r) => ({
  [name]: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
  [name + 'Text']: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) },
});
const rectOf = rr => ({ x: num(rr.x), y: num(rr.y), width: num(rr.width), height: num(rr.height) });
const rectKey = r => RK.map(k => hex(r[k])).join(',');
const rectKeyRec = rr => RK.map(k => rr[k]).join(',');
const matRec = (name, m) => ({ [name]: Array.from(m).map(hex), [name + 'Text']: Array.from(m).map(text) });
const pairRec = (name, a) => ({ [name]: a.map(hex), [name + 'Text']: a.map(text) });
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const numRecN = (name, v) => ({ [name]: hexOrNull(v), [name + 'Text']: textOrNull(v) });
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const arr = v => (v == null ? [] : Array.isArray(v) ? v : [v]);
const J = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

const UNDEF_COLOUR = { css: null, r: 0, g: 0, b: 0, a: hex(0), aText: '0', undef: true };
function colRec(c) {
  if (c == null) return Object.assign({}, UNDEF_COLOUR);
  must(typeof c === 'string', 'a colour that is not a string: ' + JSON.stringify(c));
  const p = C.parse(c);
  must(p, 'an upstream colour that does not parse: ' + c);
  return { css: c, r: p[0], g: p[1], b: p[2], a: hex(p[3]), aText: text(p[3]), undef: false };
}
function styleRec(s) {
  return Object.assign({ fill: colRec(s.fill), stroke: colRec(s.stroke) }, numRecN('lineWidth', s.lineWidth),
    numRecN('opacity', s.opacity));
}

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
const asc = a => (a[0] > a[1] ? [a[1], a[0]] : [a[0], a[1]]);

// number.ts parsePositionOption (layout params; also handleSize / moveHandleSize: SliderZoomView's parsePercent)
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

// layout.ts getLayoutRect (container {0, 0, cw, ch}, no margin, no aspect)
function getLayoutRect(p, cw, ch) {
  let left = parsePos(p.left, cw);
  let top = parsePos(p.top, ch);
  const right = parsePos(p.right, cw);
  const bottom = parsePos(p.bottom, ch);
  let width = parsePos(p.width, cw);
  let height = parsePos(p.height, ch);
  const vm = 0 + 0;
  const hm = 0 + 0;
  if (isNaN(width)) width = cw - right - hm - left;
  if (isNaN(height)) height = ch - bottom - vm - top;
  if (isNaN(left)) left = cw - right - width - hm;
  if (isNaN(top)) top = ch - bottom - height - vm;
  switch (p.left || p.right) {
    case 'center':
      left = cw / 2 - width / 2 - 0;
      break;
    case 'right':
      left = cw - width - hm;
      break;
  }
  switch (p.top || p.bottom) {
    case 'middle':
    case 'center':
      top = ch / 2 - height / 2 - 0;
      break;
    case 'bottom':
      top = ch - height - vm;
      break;
  }
  left = left || 0;
  top = top || 0;
  if (isNaN(width)) width = cw - hm - left - (right || 0);
  if (isNaN(height)) height = ch - vm - top - (bottom || 0);
  let x = 0 + left + 0;
  let y = 0 + top + 0;
  if (width < 0) { x = x + width; width = -width; }
  if (height < 0) { y = y + height; height = -height; }
  return { x, y, width, height };
}

// Component.mergeDefaultAndTheme + layout.ts mergeLayoutParam over the slider
// defaults (right / top / width / height 'ph', left / bottom null)
const BOX = ['left', 'right', 'top', 'bottom', 'width', 'height'];
const HV_NAMES = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
const SLIDER_BOX_DEFAULTS = { right: 'ph', top: 'ph', width: 'ph', height: 'ph', left: null, bottom: null };
function boxMerge(input) {
  const target = {};
  for (const k of BOX) target[k] = hasOwn(input, k) ? input[k] : SLIDER_BOX_DEFAULTS[k];
  const hasValue = (o, name) => o[name] != null && o[name] !== 'auto';
  const merge = names => {
    const newParams = {};
    let newValueCount = 0;
    const merged = {};
    let mergedValueCount = 0;
    for (const name of names) merged[name] = target[name];
    for (const name of names) {
      if (hasOwn(input, name)) newParams[name] = merged[name] = input[name];
      if (hasValue(newParams, name)) newValueCount++;
      if (hasValue(merged, name)) mergedValueCount++;
    }
    if (mergedValueCount === 2 || !newValueCount) return merged;
    if (newValueCount >= 2) return newParams;
    for (const name of names) {
      if (!hasOwn(newParams, name) && hasOwn(target, name)) {
        newParams[name] = target[name];
        break;
      }
    }
    return newParams;
  };
  const out = {};
  for (const names of HV_NAMES) {
    const r = merge(names);
    for (const n of names) out[n] = r[n];
  }
  return out;
}
const boxJson = o => {
  const r = {};
  for (const k of BOX) if (hasOwn(o, k) && o[k] !== undefined) r[k] = o[k];
  return r;
};
const numOrStr = v => (typeof v === 'number' ? { num: hex(v), text: text(v) } : v === undefined ? null : v);
const numOrStrKey = v => (v == null ? 'null' : typeof v === 'object' ? v.num : 's:' + v);

// ---------- zrender matrices ----------
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
const IDENT = () => [1, 0, 0, 1, 0, 0];
// Transformable.getLocalTransform (no origin, anchor or skew)
function localTransform(t, mut) {
  const sx = t.scaleX == null ? 1 : t.scaleX;
  const sy = t.scaleY == null ? 1 : t.scaleY;
  const rotation = t.rotation || 0;
  const x = t.x || 0;
  const y = t.y || 0;
  const m = [];
  m[4] = m[5] = 0;
  m[0] = sx;
  m[3] = sy;
  m[1] = 0 * sx;
  m[2] = 0 * sy;
  if (rotation) {
    const aa = m[0]; const ac = m[2]; const atx = m[4]; const ab = m[1]; const ad = m[3]; const aty = m[5];
    const st = mut.cos0 ? (rotation > 0 ? 1 : -1) : Math.sin(rotation);
    const ct = mut.cos0 ? 0 : Math.cos(rotation);
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * (atx - 0) + st * (aty - 0) + 0;
    m[5] = ct * (aty - 0) - st * (atx - 0) + 0;
  }
  m[4] += 0 + x;
  m[5] += 0 + y;
  return m;
}
const applyT = (v, m) => [m[0] * v[0] + m[2] * v[1] + m[4], m[1] * v[0] + m[3] * v[1] + m[5]];
// graphic.getTransform(target, ancestor): mat = local * mat, walking up
function chainTransform(locals) {
  let mat = IDENT();
  for (const l of locals) mat = mul(l, mat);
  return mat;
}
// graphic.ts transformDirection
function transformDirection(direction, m) {
  const hBase = (m[4] === 0 || m[5] === 0 || m[0] === 0) ? 1 : Math.abs(2 * m[4] / m[0]);
  const vBase = (m[4] === 0 || m[5] === 0 || m[2] === 0) ? 1 : Math.abs(2 * m[4] / m[2]);
  const v = applyT([
    direction === 'left' ? -hBase : direction === 'right' ? hBase : 0,
    direction === 'top' ? -vBase : direction === 'bottom' ? vBase : 0,
  ], m);
  return Math.abs(v[0]) > Math.abs(v[1]) ? (v[0] > 0 ? 'right' : 'left') : (v[1] > 0 ? 'bottom' : 'top');
}
// BoundingRect.applyTransform / union
function rectTransform(s, m) {
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const t = { x: s.x * m[0] + m[4], y: s.y * m[3] + m[5], width: s.width * m[0], height: s.height * m[3] };
    if (t.width < 0) { t.x += t.width; t.width = -t.width; }
    if (t.height < 0) { t.y += t.height; t.height = -t.height; }
    return t;
  }
  const tp = p => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]];
  const lt = tp([s.x, s.y]);
  const rt = tp([s.x + s.width, s.y]);
  const rb = tp([s.x + s.width, s.y + s.height]);
  const lb = tp([s.x, s.y + s.height]);
  const x = Math.min(lt[0], rb[0], lb[0], rt[0]);
  const y = Math.min(lt[1], rb[1], lb[1], rt[1]);
  return { x, y, width: Math.max(lt[0], rb[0], lb[0], rt[0]) - x, height: Math.max(lt[1], rb[1], lb[1], rt[1]) - y };
}
function union(a, b) {
  const x = Math.min(b.x, a.x);
  const y = Math.min(b.y, a.y);
  a.width = (isFinite(a.x) && isFinite(a.width)) ? Math.max(b.x + b.width, a.x + a.width) - x : b.width;
  a.height = (isFinite(a.y) && isFinite(a.height)) ? Math.max(b.y + b.height, a.y + a.height) - y : b.height;
  a.x = x;
  a.y = y;
}
// Group.getBoundingRect over [{rect, m}] (included children only)
function groupRect(children) {
  let r = null;
  for (const c of children) {
    const t = rectTransform(c.rect, c.m);
    r = r || Object.assign({}, t);
    union(r, t);
  }
  return r || { x: 0, y: 0, width: 0, height: 0 };
}

// ---------- text rects (text.ts adjustTextX/Y; one line, TSpan unioned with itself) ----------
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
  // an empty string makes no TSpan: ZRText.getBoundingRect is the bare (0, 0, 0, 0)
  if (t.string === '') return { x: 0, y: 0, width: 0, height: 0 };
  const m = measureRaw(t.string, t.font);
  const textY = adjustY(t.y, m.height, t.verticalAlign || 'top') + m.height / 2;
  const span = { x: adjustX(t.x, m.width, t.align || 'left'), y: adjustY(textY, m.height, 'middle'), width: m.width, height: m.height };
  return groupRect([{ rect: span, m: IDENT() }]);
}

// ---------- zrender curve.ts / bbox.ts ----------
const EPS = 1e-8;
const isAroundZero = v => v > -EPS && v < EPS;
const isNotAroundZero = v => v > EPS || v < -EPS;
function cubicAt(p0, p1, p2, p3, t) {
  const onet = 1 - t;
  return onet * onet * (onet * p0 + 3 * t * p1) + t * t * (t * p3 + 3 * onet * p2);
}
function cubicExtrema(p0, p1, p2, p3, extrema) {
  const b = 6 * p2 - 12 * p1 + 6 * p0;
  const a = 9 * p1 + 3 * p3 - 3 * p0 - 9 * p2;
  const c = 3 * p1 - 3 * p0;
  let n = 0;
  if (isAroundZero(a)) {
    if (isNotAroundZero(b)) {
      const t1 = -c / b;
      if (t1 >= 0 && t1 <= 1) extrema[n++] = t1;
    }
  } else {
    const disc = b * b - 4 * a * c;
    if (isAroundZero(disc)) {
      extrema[0] = -b / (2 * a);
    } else if (disc > 0) {
      const discSqrt = Math.sqrt(disc);
      const t1 = (-b + discSqrt) / (2 * a);
      const t2 = (-b - discSqrt) / (2 * a);
      if (t1 >= 0 && t1 <= 1) extrema[n++] = t1;
      if (t2 >= 0 && t2 <= 1) extrema[n++] = t2;
    }
  }
  return n;
}
function quadraticAt(p0, p1, p2, t) {
  const onet = 1 - t;
  return onet * (onet * p0 + 2 * t * p1) + t * t * p2;
}
function quadraticExtremum(p0, p1, p2) {
  const divider = p0 + p2 - 2 * p1;
  return divider === 0 ? 0.5 : (p0 - p1) / divider;
}
function fromLine(x0, y0, x1, y1, min, max) {
  min[0] = Math.min(x0, x1);
  min[1] = Math.min(y0, y1);
  max[0] = Math.max(x0, x1);
  max[1] = Math.max(y0, y1);
}
function fromCubic(x0, y0, x1, y1, x2, y2, x3, y3, min, max, mut) {
  if (mut.cubicControlBox) {
    min[0] = Math.min(x0, x1, x2, x3); min[1] = Math.min(y0, y1, y2, y3);
    max[0] = Math.max(x0, x1, x2, x3); max[1] = Math.max(y0, y1, y2, y3);
    return;
  }
  const xDim = [];
  const yDim = [];
  let n = cubicExtrema(x0, x1, x2, x3, xDim);
  min[0] = Infinity; min[1] = Infinity; max[0] = -Infinity; max[1] = -Infinity;
  for (let i = 0; i < n; i++) {
    const x = cubicAt(x0, x1, x2, x3, xDim[i]);
    min[0] = Math.min(x, min[0]);
    max[0] = Math.max(x, max[0]);
  }
  n = cubicExtrema(y0, y1, y2, y3, yDim);
  for (let i = 0; i < n; i++) {
    const y = cubicAt(y0, y1, y2, y3, yDim[i]);
    min[1] = Math.min(y, min[1]);
    max[1] = Math.max(y, max[1]);
  }
  min[0] = Math.min(x0, min[0]); max[0] = Math.max(x0, max[0]);
  min[0] = Math.min(x3, min[0]); max[0] = Math.max(x3, max[0]);
  min[1] = Math.min(y0, min[1]); max[1] = Math.max(y0, max[1]);
  min[1] = Math.min(y3, min[1]); max[1] = Math.max(y3, max[1]);
}
function fromQuadratic(x0, y0, x1, y1, x2, y2, min, max) {
  const tx = Math.max(Math.min(quadraticExtremum(x0, x1, x2), 1), 0);
  const ty = Math.max(Math.min(quadraticExtremum(y0, y1, y2), 1), 0);
  const x = quadraticAt(x0, x1, x2, tx);
  const y = quadraticAt(y0, y1, y2, ty);
  min[0] = Math.min(x0, x2, x);
  min[1] = Math.min(y0, y2, y);
  max[0] = Math.max(x0, x2, x);
  max[1] = Math.max(y0, y2, y);
}
const PI2 = Math.PI * 2;
function fromArc(x, y, rx, ry, startAngle, endAngle, anticlockwise, min, max, mut) {
  const diff = Math.abs(startAngle - endAngle);
  if (!mut.arcNoExtremes && diff % PI2 < 1e-4 && diff > 1e-4) {
    min[0] = x - rx; min[1] = y - ry; max[0] = x + rx; max[1] = y + ry;
    return;
  }
  const start = [Math.cos(startAngle) * rx + x, Math.sin(startAngle) * ry + y];
  const end = [Math.cos(endAngle) * rx + x, Math.sin(endAngle) * ry + y];
  min[0] = Math.min(start[0], end[0]); min[1] = Math.min(start[1], end[1]);
  max[0] = Math.max(start[0], end[0]); max[1] = Math.max(start[1], end[1]);
  if (mut.arcNoExtremes) return;
  startAngle = startAngle % PI2;
  if (startAngle < 0) startAngle = startAngle + PI2;
  endAngle = endAngle % PI2;
  if (endAngle < 0) endAngle = endAngle + PI2;
  if (startAngle > endAngle && !anticlockwise) endAngle += PI2;
  else if (startAngle < endAngle && anticlockwise) startAngle += PI2;
  if (anticlockwise) {
    const tmp = endAngle;
    endAngle = startAngle;
    startAngle = tmp;
  }
  for (let angle = 0; angle < endAngle; angle += Math.PI / 2) {
    if (angle > startAngle) {
      const ex = Math.cos(angle) * rx + x;
      const ey = Math.sin(angle) * ry + y;
      min[0] = Math.min(ex, min[0]); min[1] = Math.min(ey, min[1]);
      max[0] = Math.max(ex, max[0]); max[1] = Math.max(ey, max[1]);
    }
  }
}

// ---------- PathProxy ----------
const CMD = { M: 1, L: 2, C: 3, Q: 4, A: 5, Z: 6, R: 7 };
const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };
const CMD_ARGS = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 };
function modPI2(radian) {
  const n = Math.round(radian / Math.PI * 1e8) / 1e8;
  return (n % 2) * Math.PI;
}
function normalizeArcAngles(angles, anticlockwise) {
  let newStartAngle = modPI2(angles[0]);
  if (newStartAngle < 0) newStartAngle += PI2;
  const delta = newStartAngle - angles[0];
  let newEndAngle = angles[1];
  newEndAngle += delta;
  if (!anticlockwise && newEndAngle - newStartAngle >= PI2) newEndAngle = newStartAngle + PI2;
  else if (anticlockwise && newStartAngle - newEndAngle >= PI2) newEndAngle = newStartAngle - PI2;
  else if (!anticlockwise && newStartAngle > newEndAngle) newEndAngle = newStartAngle + (PI2 - modPI2(newStartAngle - newEndAngle));
  else if (anticlockwise && newStartAngle < newEndAngle) newEndAngle = newStartAngle - (PI2 - modPI2(newEndAngle - newStartAngle));
  angles[0] = newStartAngle;
  angles[1] = newEndAngle;
}
class Proxy {
  constructor() { this.data = []; }
  addData(...a) { for (const v of a) this.data.push(v); }
  moveTo(x, y) { this.addData(CMD.M, x, y); }
  lineTo(x, y) { this.addData(CMD.L, x, y); }
  bezierCurveTo(x1, y1, x2, y2, x3, y3) { this.addData(CMD.C, x1, y1, x2, y2, x3, y3); }
  quadraticCurveTo(x1, y1, x2, y2) { this.addData(CMD.Q, x1, y1, x2, y2); }
  arc(cx, cy, r, startAngle, endAngle, anticlockwise) {
    const a = [startAngle, endAngle];
    normalizeArcAngles(a, anticlockwise);
    this.addData(CMD.A, cx, cy, r, r, a[0], a[1] - a[0], 0, anticlockwise ? 0 : 1);
  }
  rect(x, y, w, h) { this.addData(CMD.R, x, y, w, h); }
  closePath() { this.addData(CMD.Z); }
}
// PathProxy.getBoundingRect
function pathBBox(data, mut) {
  const min1 = [Number.MAX_VALUE, Number.MAX_VALUE];
  const max1 = [-Number.MAX_VALUE, -Number.MAX_VALUE];
  const min2 = [Number.MAX_VALUE, Number.MAX_VALUE];
  const max2 = [-Number.MAX_VALUE, -Number.MAX_VALUE];
  let xi = 0; let yi = 0; let x0 = 0; let y0 = 0;
  let i;
  for (i = 0; i < data.length;) {
    const cmd = data[i++];
    const isFirst = i === 1;
    if (isFirst) {
      xi = data[i]; yi = data[i + 1]; x0 = xi; y0 = yi;
    }
    switch (cmd) {
      case CMD.M:
        xi = x0 = data[i++];
        yi = y0 = data[i++];
        min2[0] = x0; min2[1] = y0; max2[0] = x0; max2[1] = y0;
        break;
      case CMD.L:
        fromLine(xi, yi, data[i], data[i + 1], min2, max2);
        xi = data[i++]; yi = data[i++];
        break;
      case CMD.C:
        fromCubic(xi, yi, data[i++], data[i++], data[i++], data[i++], data[i], data[i + 1], min2, max2, mut);
        xi = data[i++]; yi = data[i++];
        break;
      case CMD.Q:
        fromQuadratic(xi, yi, data[i++], data[i++], data[i], data[i + 1], min2, max2);
        xi = data[i++]; yi = data[i++];
        break;
      case CMD.A: {
        const cx = data[i++]; const cy = data[i++]; const rx = data[i++]; const ry = data[i++];
        const startAngle = data[i++];
        const endAngle = data[i++] + startAngle;
        i += 1;
        const anticlockwise = !data[i++];
        if (isFirst) {
          x0 = Math.cos(startAngle) * rx + cx;
          y0 = Math.sin(startAngle) * ry + cy;
        }
        fromArc(cx, cy, rx, ry, startAngle, endAngle, anticlockwise, min2, max2, mut);
        xi = Math.cos(endAngle) * rx + cx;
        yi = Math.sin(endAngle) * ry + cy;
        break;
      }
      case CMD.R: {
        x0 = xi = data[i++];
        y0 = yi = data[i++];
        const width = data[i++];
        const height = data[i++];
        fromLine(x0, y0, x0 + width, y0 + height, min2, max2);
        break;
      }
      case CMD.Z:
        xi = x0; yi = y0;
        break;
      default:
        must(false, 'an unknown path command ' + cmd);
    }
    min1[0] = Math.min(min1[0], min2[0]); min1[1] = Math.min(min1[1], min2[1]);
    max1[0] = Math.max(max1[0], max2[0]); max1[1] = Math.max(max1[1], max2[1]);
  }
  if (i === 0) min1[0] = min1[1] = max1[0] = max1[1] = 0;
  // new BoundingRect flips a negative size (never here)
  return { x: min1[0], y: min1[1], width: max1[0] - min1[0], height: max1[1] - min1[1] };
}

// tool/path.ts createPathProxyFromString (+ processArc), then toStatic
function vMag(v) { return Math.sqrt(v[0] * v[0] + v[1] * v[1]); }
function vRatio(u, v) { return (u[0] * v[0] + u[1] * v[1]) / (vMag(u) * vMag(v)); }
function vAngle(u, v) { return (u[0] * v[1] < u[1] * v[0] ? -1 : 1) * Math.acos(vRatio(u, v)); }
function processArc(x1, y1, x2, y2, fa, fs, rx, ry, psiDeg, cmd, p) {
  const psi = psiDeg * (Math.PI / 180.0);
  const xp = Math.cos(psi) * (x1 - x2) / 2.0 + Math.sin(psi) * (y1 - y2) / 2.0;
  const yp = -1 * Math.sin(psi) * (x1 - x2) / 2.0 + Math.cos(psi) * (y1 - y2) / 2.0;
  const lambda = (xp * xp) / (rx * rx) + (yp * yp) / (ry * ry);
  if (lambda > 1) {
    rx *= Math.sqrt(lambda);
    ry *= Math.sqrt(lambda);
  }
  const f = (fa === fs ? -1 : 1)
    * Math.sqrt((((rx * rx) * (ry * ry)) - ((rx * rx) * (yp * yp)) - ((ry * ry) * (xp * xp)))
      / ((rx * rx) * (yp * yp) + (ry * ry) * (xp * xp))) || 0;
  const cxp = f * rx * yp / ry;
  const cyp = f * -ry * xp / rx;
  const cx = (x1 + x2) / 2.0 + Math.cos(psi) * cxp - Math.sin(psi) * cyp;
  const cy = (y1 + y2) / 2.0 + Math.sin(psi) * cxp + Math.cos(psi) * cyp;
  const theta = vAngle([1, 0], [(xp - cxp) / rx, (yp - cyp) / ry]);
  const u = [(xp - cxp) / rx, (yp - cyp) / ry];
  const v = [(-1 * xp - cxp) / rx, (-1 * yp - cyp) / ry];
  let dTheta = vAngle(u, v);
  if (vRatio(u, v) <= -1) dTheta = Math.PI;
  if (vRatio(u, v) >= 1) dTheta = 0;
  if (dTheta < 0) {
    const n = Math.round(dTheta / Math.PI * 1e6) / 1e6;
    dTheta = Math.PI * 2 + (n % 2) * Math.PI;
  }
  p.addData(cmd, cx, cy, rx, ry, theta, dTheta, psi, fs);
}
function parseSvgPath(str, mut) {
  const p = new Proxy();
  const commandReg = /([mlvhzcqtsa])([^mlvhzcqtsa]*)/ig;
  const numberReg = /-?([0-9]*\.)?[0-9]+([eE]-?[0-9]+)?/g;
  let cpx = 0; let cpy = 0; let subpathX = cpx; let subpathY = cpy;
  let prevCmd;
  const cmdList = str ? str.match(commandReg) : null;
  if (cmdList) {
    for (let l = 0; l < cmdList.length; l++) {
      const cmdText = cmdList[l];
      let cmdStr = cmdText.charAt(0);
      let cmd;
      const q = (cmdText.match(numberReg) || []).map(parseFloat);
      const pLen = q.length;
      let off = 0;
      while (off < pLen) {
        let ctlPtx; let ctlPty; let rx; let ry; let psi; let fa; let fs;
        let x1 = cpx; let y1 = cpy;
        let len; let pathData;
        switch (cmdStr) {
          case 'l': cpx += q[off++]; cpy += q[off++]; cmd = CMD.L; p.addData(cmd, cpx, cpy); break;
          case 'L': cpx = q[off++]; cpy = q[off++]; cmd = CMD.L; p.addData(cmd, cpx, cpy); break;
          case 'm': cpx += q[off++]; cpy += q[off++]; cmd = CMD.M; p.addData(cmd, cpx, cpy); subpathX = cpx; subpathY = cpy; cmdStr = 'l'; break;
          case 'M': cpx = q[off++]; cpy = q[off++]; cmd = CMD.M; p.addData(cmd, cpx, cpy); subpathX = cpx; subpathY = cpy; cmdStr = 'L'; break;
          case 'h': cpx += q[off++]; cmd = CMD.L; p.addData(cmd, cpx, cpy); break;
          case 'H': cpx = q[off++]; cmd = CMD.L; p.addData(cmd, cpx, cpy); break;
          case 'v': cpy += q[off++]; cmd = CMD.L; p.addData(cmd, cpx, cpy); break;
          case 'V': cpy = q[off++]; cmd = CMD.L; p.addData(cmd, cpx, cpy); break;
          case 'C':
            cmd = CMD.C;
            p.addData(cmd, q[off++], q[off++], q[off++], q[off++], q[off++], q[off++]);
            cpx = q[off - 2]; cpy = q[off - 1];
            break;
          case 'c':
            cmd = CMD.C;
            p.addData(cmd, q[off++] + cpx, q[off++] + cpy, q[off++] + cpx, q[off++] + cpy, q[off++] + cpx, q[off++] + cpy);
            cpx += q[off - 2]; cpy += q[off - 1];
            break;
          case 'S':
          case 's':
            ctlPtx = cpx; ctlPty = cpy;
            len = p.data.length; pathData = p.data;
            if (prevCmd === CMD.C) {
              ctlPtx += cpx - pathData[len - 4];
              ctlPty += cpy - pathData[len - 3];
            }
            cmd = CMD.C;
            if (cmdStr === 'S') {
              x1 = q[off++]; y1 = q[off++]; cpx = q[off++]; cpy = q[off++];
            } else {
              x1 = cpx + q[off++]; y1 = cpy + q[off++]; cpx += q[off++]; cpy += q[off++];
            }
            p.addData(cmd, ctlPtx, ctlPty, x1, y1, cpx, cpy);
            break;
          case 'Q': x1 = q[off++]; y1 = q[off++]; cpx = q[off++]; cpy = q[off++]; cmd = CMD.Q; p.addData(cmd, x1, y1, cpx, cpy); break;
          case 'q': x1 = q[off++] + cpx; y1 = q[off++] + cpy; cpx += q[off++]; cpy += q[off++]; cmd = CMD.Q; p.addData(cmd, x1, y1, cpx, cpy); break;
          case 'T':
          case 't':
            ctlPtx = cpx; ctlPty = cpy;
            len = p.data.length; pathData = p.data;
            if (prevCmd === CMD.Q) {
              ctlPtx += cpx - pathData[len - 4];
              ctlPty += cpy - pathData[len - 3];
            }
            if (cmdStr === 'T') { cpx = q[off++]; cpy = q[off++]; } else { cpx += q[off++]; cpy += q[off++]; }
            cmd = CMD.Q;
            p.addData(cmd, ctlPtx, ctlPty, cpx, cpy);
            break;
          case 'A':
          case 'a':
            rx = q[off++]; ry = q[off++]; psi = q[off++]; fa = q[off++]; fs = q[off++];
            x1 = cpx; y1 = cpy;
            if (cmdStr === 'A') { cpx = q[off++]; cpy = q[off++]; } else { cpx += q[off++]; cpy += q[off++]; }
            cmd = CMD.A;
            processArc(x1, y1, cpx, cpy, fa, fs, rx, ry, psi, cmd, p);
            break;
          default:
            off = pLen; // an unknown command letter consumes nothing upstream either
        }
      }
      if (cmdStr === 'z' || cmdStr === 'Z') {
        cmd = CMD.Z;
        p.addData(cmd);
        cpx = subpathX; cpy = subpathY;
      }
      prevCmd = cmd;
    }
  }
  // toStatic: a Float32Array when there are more than 11 numbers
  const f32 = !mut.noFloat32 && p.data.length > 11;
  return { data: f32 ? p.data.map(Math.fround) : p.data.slice(), f32 };
}
// graphic.ts centerGraphic
function centerGraphic(rect, bRect) {
  const aspect = bRect.width / bRect.height;
  let width = rect.height * aspect;
  let height;
  if (width <= rect.width) {
    height = rect.height;
  } else {
    width = rect.width;
    height = width / aspect;
  }
  const cx = rect.x + rect.width / 2;
  const cy = rect.y + rect.height / 2;
  return { x: cx - width / 2, y: cy - height / 2, width, height };
}
// BoundingRect.calculateTransform
function calculateTransform(a, b) {
  const sx = b.width / a.width;
  const sy = b.height / a.height;
  let out = IDENT();
  out = [out[0], out[1], out[2], out[3], out[4] + -a.x, out[5] + -a.y];
  out = [out[0] * sx, out[1] * sy, out[2] * sx, out[3] * sy, out[4] * sx, out[5] * sy];
  out = [out[0], out[1], out[2], out[3], out[4] + b.x, out[5] + b.y];
  return out;
}
// tool/transformPath.ts (the R case is broken upstream and never reached)
function transformPath(src, m) {
  const st = src.f32 ? Math.fround : v => v;
  const data = src.data;
  for (let i = 0; i < data.length;) {
    const cmd = data[i++];
    let j = i;
    let nPoint = 0;
    switch (cmd) {
      case CMD.M: case CMD.L: nPoint = 1; break;
      case CMD.C: nPoint = 3; break;
      case CMD.Q: nPoint = 2; break;
      case CMD.A: {
        const x = m[4]; const y = m[5];
        const sx = Math.sqrt(m[0] * m[0] + m[1] * m[1]);
        const sy = Math.sqrt(m[2] * m[2] + m[3] * m[3]);
        const angle = Math.atan2(-m[1] / sy, m[0] / sx);
        data[i] = st(data[i] * sx); data[i] = st(data[i] + x); i++;
        data[i] = st(data[i] * sy); data[i] = st(data[i] + y); i++;
        data[i] = st(data[i] * sx); i++;
        data[i] = st(data[i] * sy); i++;
        data[i] = st(data[i] + angle); i++;
        data[i] = st(data[i] + angle); i++;
        i += 2;
        j = i;
        break;
      }
      case CMD.Z: break;
      default: must(false, 'transformPath: command ' + cmd);
    }
    for (let k = 0; k < nPoint; k++) {
      const q = applyT([data[i++], data[i++]], m);
      data[j++] = st(q[0]);
      data[j++] = st(q[1]);
    }
  }
}
// graphic.ts makePath(str, {}, rect, 'center'); returns the element's data and rects
function makePathCenter(str, rect, mut) {
  const src = parseSvgPath(str, mut);
  const raw = pathBBox(src.data, mut);
  const target = centerGraphic(rect, raw);
  const m = calculateTransform(raw, target);
  transformPath(src, m);
  return { data: src.data.slice(), f32: src.f32, rawRect: raw, pathRect: pathBBox(src.data, mut), kind: 'path' };
}
// Rect.buildPath's rounded-rect helper (graphic/helper/roundRect.ts)
function roundRectPath(ctx, shape) {
  let x = shape.x; let y = shape.y; let width = shape.width; let height = shape.height;
  const r = shape.r;
  let r1; let r2; let r3; let r4;
  if (width < 0) { x = x + width; width = -width; }
  if (height < 0) { y = y + height; height = -height; }
  if (typeof r === 'number') {
    r1 = r2 = r3 = r4 = r;
  } else if (r instanceof Array) {
    if (r.length === 1) { r1 = r2 = r3 = r4 = r[0]; } else if (r.length === 2) { r1 = r3 = r[0]; r2 = r4 = r[1]; } else if (r.length === 3) { r1 = r[0]; r2 = r4 = r[1]; r3 = r[2]; } else { r1 = r[0]; r2 = r[1]; r3 = r[2]; r4 = r[3]; }
  } else {
    r1 = r2 = r3 = r4 = 0;
  }
  let total;
  if (r1 + r2 > width) { total = r1 + r2; r1 *= width / total; r2 *= width / total; }
  if (r3 + r4 > width) { total = r3 + r4; r3 *= width / total; r4 *= width / total; }
  if (r2 + r3 > height) { total = r2 + r3; r2 *= height / total; r3 *= height / total; }
  if (r1 + r4 > height) { total = r1 + r4; r1 *= height / total; r4 *= height / total; }
  ctx.moveTo(x + r1, y);
  ctx.lineTo(x + width - r2, y);
  r2 !== 0 && ctx.arc(x + width - r2, y + r2, r2, -Math.PI / 2, 0);
  ctx.lineTo(x + width, y + height - r3);
  r3 !== 0 && ctx.arc(x + width - r3, y + height - r3, r3, 0, Math.PI / 2);
  ctx.lineTo(x + r4, y + height);
  r4 !== 0 && ctx.arc(x + r4, y + height - r4, r4, Math.PI / 2, Math.PI);
  ctx.lineTo(x, y + r1);
  r1 !== 0 && ctx.arc(x + r1, y + r1, r1, Math.PI, Math.PI * 1.5);
  ctx.closePath();
}
// subPixelOptimize.ts
function subPixelOptimize(position, lineWidth, positiveOrNegative) {
  if (!lineWidth) return position;
  const doubledPosition = Math.round(position * 2);
  return (doubledPosition + Math.round(lineWidth)) % 2 === 0 ? doubledPosition / 2 : (doubledPosition + (positiveOrNegative ? 1 : -1)) / 2;
}
function subPixelOptimizeRect(shape, lineWidth) {
  const out = { x: shape.x, y: shape.y, width: shape.width, height: shape.height };
  if (!lineWidth) return out;
  out.x = subPixelOptimize(shape.x, lineWidth, true);
  out.y = subPixelOptimize(shape.y, lineWidth, true);
  out.width = Math.max(subPixelOptimize(shape.x + shape.width, lineWidth, false) - out.x, shape.width === 0 ? 0 : 1);
  out.height = Math.max(subPixelOptimize(shape.y + shape.height, lineWidth, false) - out.y, shape.height === 0 ? 0 : 1);
  return out;
}
// Rect.buildPath
function rectPathData(shape, opt) {
  const ctx = new Proxy();
  let s = shape;
  if (opt.subPixelOptimize) {
    s = subPixelOptimizeRect(shape, opt.lineWidth);
    s.r = shape.r;
  }
  if (!s.r) ctx.rect(s.x, s.y, s.width, s.height);
  else roundRectPath(ctx, s);
  return ctx.data;
}
// symbol.ts: the built-in symbol shapes this oracle uses
const BUILTIN_SYMBOLS = ['line', 'rect', 'roundRect', 'square', 'circle', 'diamond', 'pin', 'arrow', 'triangle'];
function symbolPathData(type, x, y, w, h) {
  const ctx = new Proxy();
  if (BUILTIN_SYMBOLS.indexOf(type) < 0) type = 'rect';
  switch (type) {
    case 'rect': ctx.rect(x, y, w, h); break;
    case 'square': { const size = Math.min(w, h); ctx.rect(x, y, size, size); break; }
    case 'roundRect': roundRectPath(ctx, { x, y, width: w, height: h, r: Math.min(w, h) / 4 }); break;
    case 'circle': {
      const cx = x + w / 2; const cy = y + h / 2; const r = Math.min(w, h) / 2;
      ctx.moveTo(cx + r, cy);
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      break;
    }
    case 'diamond': {
      const cx = x + w / 2; const cy = y + h / 2; const hw = w / 2; const hh = h / 2;
      ctx.moveTo(cx, cy - hh); ctx.lineTo(cx + hw, cy); ctx.lineTo(cx, cy + hh); ctx.lineTo(cx - hw, cy); ctx.closePath();
      break;
    }
    case 'triangle': {
      const cx = x + w / 2; const cy = y + h / 2; const hw = w / 2; const hh = h / 2;
      ctx.moveTo(cx, cy - hh); ctx.lineTo(cx + hw, cy + hh); ctx.lineTo(cx - hw, cy + hh); ctx.closePath();
      break;
    }
    default: must(false, 'built-in symbol not transcribed: ' + type);
  }
  return ctx.data;
}
// symbol.ts createSymbol(symbolType, x, y, w, h, color, keepAspect = true)
function createSymbol(symbolType, x, y, w, h, mut) {
  if (symbolType.indexOf('empty') === 0) symbolType = symbolType.substr(5, 1).toLowerCase() + symbolType.substr(6);
  must(symbolType.indexOf('image://') !== 0, 'image:// icons are not transcribed');
  if (symbolType.indexOf('path://') === 0) return makePathCenter(symbolType.slice(7), { x, y, width: w, height: h }, mut);
  const data = symbolPathData(symbolType, x, y, w, h);
  return { data, f32: false, pathRect: pathBBox(data, mut), kind: 'symbol', symbolType };
}
// Path.getBoundingRect: the path rect grown by the stroke
function strokeRect(pathRect, pathLen, style, lineScale, mut, isPolyline) {
  const hasStroke = !(style.stroke == null || style.stroke === 'none' || !(style.lineWidth > 0));
  if (!(hasStroke && pathLen > 0)) return pathRect;
  const r = Object.assign({}, pathRect);
  let w = style.lineWidth;
  const hasFill = style.fill != null && style.fill !== 'none';
  if (!hasFill) {
    if (!(isPolyline && mut.polylineLwOnly)) w = Math.max(w, 5);
  }
  if (isPolyline && mut.polylineNoStroke) return pathRect;
  if (lineScale > 1e-10) {
    r.width += w / lineScale;
    r.height += w / lineScale;
    r.x -= w / lineScale / 2;
    r.y -= w / lineScale / 2;
  }
  return r;
}
function segs(data) {
  const out = [];
  for (let i = 0; i < data.length;) {
    const c = data[i++];
    const n = CMD_ARGS[c];
    must(n != null, 'a path command ' + c);
    out.push({ cmd: CMD_NAME[c], args: data.slice(i, i + n).map(hex), argsText: data.slice(i, i + n).map(text) });
    i += n;
  }
  return out;
}
const segsKey = s => s.map(g => g.cmd + g.args.join(',')).join(';');

// the data shadow points (SliderZoomView._renderDataShadow)
function dataExtent(vals) {
  let mn = Infinity;
  let mx = -Infinity;
  for (const v of vals) {
    if (v < mn) mn = v;
    if (v > mx) mx = v;
  }
  return [mn, mx];
}
function shadowPoints(sv, L, T, isTime, mut) {
  const n = sv.thisVals.length;
  const thisExt = dataExtent(sv.thisVals);
  let otherExt = dataExtent(sv.otherVals);
  const off = (otherExt[1] - otherExt[0]) * 0.3;
  otherExt = [otherExt[0] - off, otherExt[1] + off];
  const area = [[L, 0], [0, 0]];
  const line = [];
  const step = L / Math.max(1, n - 1);
  const norm = L / (thisExt[1] - thisExt[0]);
  let coord = -step;
  const stride = mut.noStride ? 0 : Math.round(n / L);
  let lastIsEmpty;
  for (let index = 0; index < n; index++) {
    const tv = sv.thisVals[index];
    const ov = sv.otherVals[index];
    if (stride > 0 && index % stride) {
      if (!isTime) coord += step;
      continue;
    }
    if (mut.coordMultiplied) coord = isTime ? (+tv - thisExt[0]) * norm : index * step;
    else if (mut.timeByIndex) coord = coord + step;
    else coord = isTime ? (+tv - thisExt[0]) * norm : coord + step;
    const isEmpty = ov == null || isNaN(ov) || ov === '';
    const oc = isEmpty ? 0 : linearMap(ov, otherExt, [0, T], true);
    if (isEmpty && !lastIsEmpty && index) {
      area.push([area[area.length - 1][0], 0]);
      line.push([line[line.length - 1][0], 0]);
    } else if (!isEmpty && lastIsEmpty) {
      area.push([coord, 0]);
      line.push([coord, 0]);
    }
    if (!isEmpty) {
      area.push([coord, oc]);
      line.push([coord, oc]);
    }
    lastIsEmpty = isEmpty;
  }
  return { area, line, thisExt, otherExtRaw: dataExtent(sv.otherVals) };
}
function polyPathData(points, close) {
  const ctx = new Proxy();
  if (points && points.length >= 2) {
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) ctx.lineTo(points[i][0], points[i][1]);
    close && ctx.closePath();
  }
  return ctx.data;
}
const ptsKey = pts => pts.map(p => hex(p[0]) + ',' + hex(p[1])).join(' ');

// the whole static picture of one slider; returns the flat field map
function model(sl, side, mut) {
  const o = {};
  if (!sl.show || sl.noTarget) {
    o.drawn = 'false';
    return o;
  }
  o.drawn = 'true';
  const r = sl.resolved;
  const view = sl.view;
  const elStyle = role => {
    const e = view.elements.find(x => x.role === role);
    must(e, 'no element ' + role);
    return { fill: e.style.fill.css, stroke: e.style.stroke.css, lineWidth: e.style.lineWidth == null ? undefined : num(e.style.lineWidth) };
  };
  const horizontal = r.orient === 'horizontal';

  // box merge and _resetLocation
  const merged = boxMerge(r.layoutInput);
  o.layoutMerged = JSON.stringify(boxJson(merged));
  const cr = rectOf(r.coordRect);
  const mhs = r.brushSelect ? (mut.moveHandleOption ? r.moveHandleSize : 7) : 0;
  const edgeGap = r.edgeGap || 0;
  const positionInfo = horizontal
    ? { right: W - cr.x - cr.width, top: H - 30 - edgeGap - mhs, width: cr.width, height: 30 }
    : { right: edgeGap, top: cr.y, width: 30, height: cr.height };
  const params = {};
  for (const k of BOX) if (hasOwn(merged, k)) params[k] = merged[k];
  for (const k of ['right', 'top', 'width', 'height']) if (params[k] === 'ph') params[k] = positionInfo[k];
  o.layoutParams = BOX.filter(k => hasOwn(params, k)).map(k => k + '=' + numOrStrKey(numOrStr(params[k]))).join(' ');
  const lr = getLayoutRect(params, W, H);
  if (mut.leftFromX && horizontal && isNaN(parsePos(params.left, W)) && merged.width === 'ph') lr.x = cr.x;
  const loc = { x: lr.x, y: lr.y };
  const size = horizontal ? [lr.width, lr.height] : [lr.height, lr.width];
  const [L, T] = size;
  o.location = hex(loc.x) + ',' + hex(loc.y);
  o.size = hex(L) + ',' + hex(T);

  // _resetInterval
  const w = r.window;
  const range = (mut.percentInverted ? w.percentInverted : w.percent).map(num);
  o.range = range.map(hex).join(',');
  const ends = [linearMap(range[0], [0, 100], [0, L], true), linearMap(range[1], [0, 100], [0, L], true)];
  o.handleEnds = ends.map(hex).join(',');
  const hi = asc(ends);

  // handles
  let icon = r.handleIcon;
  if (BUILTIN_SYMBOLS.indexOf(icon) < 0 && icon.indexOf('path://') < 0 && icon.indexOf('image://') < 0) icon = 'path://' + icon;
  const hp = createSymbol(icon, -1, 0, 2, 2, mut);
  const hh = parsePos(r.handleSize, T);
  const hw = hp.pathRect.width / hp.pathRect.height * hh;
  o.handleWidth = hex(hw);
  o.handleHeight = hex(hh);
  const hStyle = elStyle('handle0');
  const lineScaleH = mut.lineScaleLocal ? Math.sqrt(Math.abs((hh / 2) * (hh / 2))) : 1;
  const hRect = strokeRect(hp.pathRect, hp.data.length, hStyle, lineScaleH, mut, false);
  const hRectPos = strokeRect(hp.pathRect, hp.data.length, hStyle, 1, mut, false);

  // move handle
  let mh = null;
  let iconP = null;
  let iconY = 0;
  if (r.brushSelect) {
    mh = parsePos(r.moveHandleSize, T);
    const iconSize = mh * 0.8;
    iconP = createSymbol(r.moveHandleIcon, -iconSize / 2, -iconSize / 2, iconSize, iconSize, mut);
    iconY = T + mh / 2 - 0.5;
    o.moveHandleHeight = hex(mh);
  }

  // shadow
  const sh = sl.shadow;
  let pts = null;
  if (sh && sh.drawn) {
    const sv = side;
    must(sv && sv.thisVals, 'no shadow values in memory');
    pts = shadowPoints(sv, L, T, sh.thisAxisType === 'time', mut);
    o['shadow.thisExt'] = pts.thisExt.map(hex).join(',');
    o['shadow.otherExt'] = pts.otherExtRaw.map(hex).join(',');
    o['shadow.area'] = ptsKey(pts.area);
    o['shadow.line'] = ptsKey(pts.line);
  }

  // the shapes, as a function of the phase ('pos' = _positionGroup time, 'final')
  const borderR = r.borderRadius || 0;
  const frameStyle = elStyle('frame');
  const shapes = phase => {
    const fin = phase === 'final';
    const kids = [];
    const add = (role, shape, data, style, m, extra) => {
      const pr = pathBBox(data, mut);
      const rect = strokeRect(pr, data.length, style, extra && extra.lineScale != null ? extra.lineScale : 1, mut, extra && extra.polyline);
      kids.push(Object.assign({ role, shape, data, rect, m, included: !(extra && extra.invisible) }, extra || {}));
    };
    const full = { x: 0, y: 0, width: L, height: T };
    add('background', full, rectPathData(full, {}), elStyle('background'), IDENT());
    add('clickPanel', full, rectPathData(full, {}), elStyle('clickPanel'), IDENT());
    const fShape = fin ? { x: hi[0], y: 0, width: hi[1] - hi[0], height: T } : { x: 0, y: 0, width: 0, height: 0 };
    add('filler', fShape, rectPathData(fShape, {}), elStyle('filler'), IDENT());
    const frShape = { x: 0, y: 0, width: L, height: T, r: borderR };
    add('frame', frShape, rectPathData(frShape, { subPixelOptimize: !mut.noSubPixel, lineWidth: frameStyle.lineWidth }), frameStyle, IDENT());
    for (const i of [0, 1]) {
      const t = fin ? { x: ends[i] + (mut.noHandleInset ? 0 : (i ? -1 : 1)), y: T / 2 - hh / 2, scaleX: hh / 2, scaleY: hh / 2 } : {};
      kids.push({ role: 'handle' + i, data: hp.data, rect: fin ? hRect : hRectPos, m: localTransform(t, mut), t, included: true });
    }
    if (r.brushSelect) {
      const mShape = fin ? { r: [0, 0, 2, 2], x: hi[0], y: T - 0.5, width: hi[1] - hi[0], height: mh } : { r: [0, 0, 2, 2], x: 0, y: T - 0.5, width: 0, height: mh };
      add('moveHandle', mShape, rectPathData(mShape, {}), elStyle('moveHandle'), IDENT());
      const it = { x: fin ? hi[0] + (hi[1] - hi[0]) / 2 : 0, y: iconY };
      const iRect = strokeRect(iconP.pathRect, iconP.data.length, elStyle('moveHandleIcon'), 1, mut, false);
      kids.push({ role: 'moveHandleIcon', data: iconP.data, rect: iRect, m: localTransform(it, mut), t: it, included: true });
      const expand = Math.min(T / 2, Math.max(mh, 10));
      const zShape = fin ? { x: hi[0], y: T - expand, width: hi[1] - hi[0], height: mh + expand } : { x: 0, y: T - expand, width: 0, height: mh + expand };
      add('moveZone', zShape, rectPathData(zShape, {}), elStyle('moveZone'), IDENT(), { invisible: true });
    }
    if (pts) {
      for (let i = 0; i < 3; i++) {
        const pa = polyPathData(pts.area, true);
        const pl = polyPathData(pts.line, false);
        const ra = strokeRect(pathBBox(pa, mut), pa.length, elStyle('shadowPolygon' + i), 1, mut, false);
        const rl = strokeRect(pathBBox(pl, mut), pl.length, elStyle('shadowPolyline' + i), 1, mut, true);
        const g = groupRect([{ rect: ra, m: IDENT() }, { rect: rl, m: IDENT() }]);
        kids.push({ role: 'shadow' + i, rect: g, m: IDENT(), included: true, kidsRects: { poly: ra, line: rl }, pa, pl });
      }
    }
    return kids;
  };
  const posKids = shapes(mut.posAfterUpdate ? 'final' : 'pos');
  const finKids = shapes('final');

  // the sliderGroup transform
  const inverse = r.inverse;
  const oai = mut.ignoreOtherInverse ? undefined : (sh ? sh.otherAxisInverse : undefined);
  const sgT = horizontal && !inverse ? { scaleY: oai ? 1 : -1, scaleX: 1 }
    : horizontal && inverse ? { scaleY: oai ? 1 : -1, scaleX: -1 }
      : !horizontal && !inverse ? { scaleY: oai ? -1 : 1, scaleX: 1, rotation: Math.PI / 2 }
        : { scaleY: oai ? -1 : 1, scaleX: -1, rotation: Math.PI / 2 };
  const Lsg = localTransform(sgT, mut);
  o['sg.local'] = Lsg.map(hex).join(',');

  // _positionGroup
  const incl = kids => kids.filter(k => k.included).map(k => ({ rect: k.rect, m: k.m }));
  const sgPos = groupRect(incl(posKids));
  o['pos.sliderRect'] = rectKey(sgPos);
  if (!mut.posAfterUpdate) posKids.forEach(k => { o['pos.kid.' + k.role] = rectKey(k.rect) + '|' + k.included + '|' + k.m.map(hex).join(','); });
  const posRect = groupRect([{ rect: sgPos, m: Lsg }]);
  o['pos.groupRect'] = rectKey(posRect);
  const gx = loc.x - (isNaN(posRect.x) ? 0 : posRect.x);
  const gy = loc.y - (isNaN(posRect.y) ? 0 : posRect.y);
  o.group = hex(gx) + ',' + hex(gy);
  const G = localTransform({ x: gx, y: gy }, mut);
  o['group.m'] = G.map(hex).join(',');
  const toGroup = chainTransform([Lsg]);
  o['sg.toGroup'] = toGroup.map(hex).join(',');
  o['sg.global'] = chainTransform([Lsg, G]).map(hex).join(',');

  // the elements after _updateView
  const roleEls = {};
  for (const k of finKids) {
    if (/^shadow\d$/.test(k.role)) {
      const i = +k.role.slice(6);
      const seg = [0, hi[0], hi[1], L];
      const clip = { x: seg[i], y: 0, width: seg[i + 1] - seg[i], height: T };
      o['el.' + k.role + '.clip'] = rectKey(clip);
      o['el.' + k.role + '.rect'] = rectKey(k.rect);
      o['el.' + k.role + '.local'] = k.m.map(hex).join(',');
      const gm = chainTransform([k.m, Lsg, G]);
      roleEls['shadowPolygon' + i] = { rect: k.kidsRects.poly, global: chainTransform([IDENT(), k.m, Lsg, G]), local: IDENT(), pathLen: k.pa.length };
      roleEls['shadowPolyline' + i] = { rect: k.kidsRects.line, global: chainTransform([IDENT(), k.m, Lsg, G]), local: IDENT(), pathLen: k.pl.length };
      void gm;
      continue;
    }
    const e = { rect: k.rect, local: k.m, global: chainTransform([k.m, Lsg, G]) };
    if (k.shape) e.shape = k.shape;
    if (/^handle|moveHandleIcon/.test(k.role)) e.path = segsKey(segs(k.data));
    roleEls[k.role] = e;
  }
  for (const role of Object.keys(roleEls)) {
    const e = roleEls[role];
    o['el.' + role + '.rect'] = rectKey(e.rect);
    o['el.' + role + '.local'] = e.local.map(hex).join(',');
    o['el.' + role + '.global'] = e.global.map(hex).join(',');
    o['el.' + role + '.grect'] = rectKey(rectTransform(e.rect, e.global));
    if (e.shape) o['el.' + role + '.shape'] = RK.map(k => hex(e.shape[k])).join(',') + (e.shape.r != null ? '|r=' + JSON.stringify(e.shape.r) : '');
    if (e.path) o['el.' + role + '.path'] = e.path;
    if (e.pathLen != null) o['el.' + role + '.pathLen'] = String(e.pathLen);
  }

  // labels (_updateDataInfo)
  const labelText = i => {
    if (!r.showDetail) return '';
    let p = r.labelPrecision;
    if (p == null || p === 'auto') p = num(w.valuePrecision);
    if (mut.precisionIgnored) p = 0;
    const value = num(w.value[i]);
    let valueStr;
    if (value == null || isNaN(value)) valueStr = '';
    else if (r.labelAxis.type === 'category' || r.labelAxis.type === 'time') valueStr = r.scaleLabels[i];
    else valueStr = isFinite(p) ? (+value).toFixed(Math.min(Math.max(0, p), 20)) : value + '';
    return typeof r.labelFormatter === 'string' ? r.labelFormatter.replace('{value}', valueStr) : valueStr;
  };
  const labels = [0, 1].map(i => {
    const dir = transformDirection(i === 0 ? 'right' : 'left', toGroup);
    const offset = hw / 2 + (mut.noLabelGap ? 0 : 5);
    const pt = applyT([hi[i] + (i === 0 ? -offset : offset), T / 2], toGroup);
    const t = { string: labelText(i), x: pt[0], y: pt[1], font: r.textStyle.font,
      verticalAlign: horizontal ? 'middle' : dir, align: horizontal ? dir : 'center' };
    const rect = textRect(t);
    o['el.label' + i] = [t.string, hex(t.x), hex(t.y), t.align, t.verticalAlign].join('|');
    o['el.label' + i + '.rect'] = rectKey(rect);
    o['el.label' + i + '.grect'] = rectKey(rectTransform(rect, chainTransform([IDENT(), G])));
    return { rect, invisible: !r.handleLabelShow, string: t.string };
  });

  // the final rects
  const sgFin = groupRect(incl(finKids));
  o['final.sliderRect'] = rectKey(sgFin);
  const gKids = labels.filter(l => !l.invisible).map(l => ({ rect: l.rect, m: IDENT() }));
  gKids.push({ rect: sgFin, m: Lsg });
  const gFin = groupRect(gKids);
  o['final.groupRect'] = rectKey(gFin);
  o['final.groupGlobalRect'] = rectKey(rectTransform(gFin, G));

  // paint order: the traversal, stable-sorted on z2 (zlevel and z are the component's)
  const Z2 = { background: -40, clickPanel: 0, filler: 0, frame: 0, handle0: 5, handle1: 5, moveHandle: 0, moveHandleIcon: 0, moveZone: 0, label0: 10, label1: 10 };
  const trav = ['label0', 'label1', 'background', 'clickPanel', 'filler', 'frame', 'handle0', 'handle1'];
  if (r.brushSelect) trav.push('moveHandle', 'moveHandleIcon', 'moveZone');
  if (pts) for (let i = 0; i < 3; i++) { trav.push('shadowPolygon' + i, 'shadowPolyline' + i); Z2['shadowPolygon' + i] = -20; Z2['shadowPolyline' + i] = -19; }
  const texts = labels.map(l => l.string);
  const unpainted = trav.filter(role => /^label/.test(role) && texts[+role.slice(5)] === '');
  const order = trav.filter(role => unpainted.indexOf(role) < 0).map((role, k) => ({ role, k }))
    .sort((a, b) => (Z2[a.role] - Z2[b.role]) || (a.k - b.k)).map(x => x.role);
  o.paint = order.concat(unpainted).join(',');
  o.painted = order.map(() => true).concat(unpainted.map(() => false)).join(',');
  return o;
}

// the same fields read from a record
function flatRecord(sl) {
  const o = {};
  if (!sl.show || sl.noTarget) {
    o.drawn = 'false';
    return o;
  }
  o.drawn = 'true';
  const r = sl.resolved;
  const v = sl.view;
  o.layoutMerged = JSON.stringify(r.layoutMerged);
  o.layoutParams = BOX.filter(k => hasOwn(r.layoutParams, k)).map(k => k + '=' + numOrStrKey(r.layoutParams[k])).join(' ');
  o.location = r.location.x + ',' + r.location.y;
  o.size = r.size.join(',');
  o.range = r.range.join(',');
  o.handleEnds = r.handleEnds.join(',');
  o.handleWidth = r.handleWidth;
  o.handleHeight = r.handleHeight;
  if (r.moveHandleHeight != null) o.moveHandleHeight = r.moveHandleHeight;
  const sh = sl.shadow;
  if (sh && sh.drawn) {
    o['shadow.thisExt'] = sh.thisDataExtent.join(',');
    o['shadow.otherExt'] = sh.otherDataExtent.join(',');
    o['shadow.area'] = sh.area.map(p => p.join(',')).join(' ');
    o['shadow.line'] = sh.line.map(p => p.join(',')).join(' ');
  }
  o['sg.local'] = v.sliderGroup.local.join(',');
  o['pos.sliderRect'] = rectKeyRec(v.position.sliderRect);
  v.position.children.forEach(k => { o['pos.kid.' + k.role] = rectKeyRec(k.rect) + '|' + k.included + '|' + k.local.join(','); });
  o['pos.groupRect'] = rectKeyRec(v.position.groupRect);
  o.group = v.group.x + ',' + v.group.y;
  o['group.m'] = v.group.matrix.join(',');
  o['sg.toGroup'] = v.sliderGroup.toGroup.join(',');
  o['sg.global'] = v.sliderGroup.global.join(',');
  for (const g of v.shadowGroups) {
    o['el.shadow' + g.i + '.clip'] = rectKeyRec(g.clip);
    o['el.shadow' + g.i + '.rect'] = rectKeyRec(g.rect);
    o['el.shadow' + g.i + '.local'] = g.local.join(',');
  }
  for (const e of v.elements) {
    if (e.type === 'text') {
      o['el.' + e.role] = [e.text, e.textX, e.textY, e.align, e.verticalAlign].join('|');
      o['el.' + e.role + '.rect'] = rectKeyRec(e.rect);
      o['el.' + e.role + '.grect'] = rectKeyRec(e.globalRect);
      continue;
    }
    o['el.' + e.role + '.rect'] = rectKeyRec(e.rect);
    o['el.' + e.role + '.local'] = e.local.join(',');
    o['el.' + e.role + '.global'] = e.global.join(',');
    o['el.' + e.role + '.grect'] = rectKeyRec(e.globalRect);
    if (e.type === 'rect') o['el.' + e.role + '.shape'] = RK.map(k => e.shape[k]).join(',') + (e.shape.r != null ? '|r=' + JSON.stringify(e.shape.r) : '');
    if (e.path) o['el.' + e.role + '.path'] = segsKey(e.path);
    if (e.pathLen != null) o['el.' + e.role + '.pathLen'] = String(e.pathLen);
  }
  o['final.sliderRect'] = rectKeyRec(v.finalSliderRect);
  o['final.groupRect'] = rectKeyRec(v.finalGroupRect);
  o['final.groupGlobalRect'] = rectKeyRec(v.finalGroupGlobalRect);
  o.paint = v.elements.map(e => e.role).join(',');
  o.painted = v.elements.map(e => e.painted).join(',');
  return o;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => a[k] !== b[k]).map(k => ({ field: k, upstream: a[k] === undefined ? null : a[k], mutated: b[k] === undefined ? null : b[k] }));
}
const clip80 = s => (s != null && s.length > 160 ? s.slice(0, 160) + '...' : s);

// =====================================================================
// Recording
// =====================================================================
let CAPTURE = new Map();
let hooked = false;
function hookProto() {
  if (hooked) return;
  runChart({ xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {}, series: [{ type: 'line', data: [1, 2] }], dataZoom: [{}] }, ch => {
    const dz = ch.getModel().getComponent('dataZoom', 0);
    const view = ch.getViewOfComponentModel(dz);
    const proto = Object.getPrototypeOf(view);
    must(hasOwn(proto, '_positionGroup') && hasOwn(proto, '_resetLocation'), 'SliderZoomView has no _positionGroup / _resetLocation');
    const origPos = proto._positionGroup;
    const origLoc = proto._resetLocation;
    proto._resetLocation = function () {
      let seen = null;
      const desc = Object.getOwnPropertyDescriptor(Object.prototype, 'aspect');
      must(!desc, 'Object.prototype.aspect already exists');
      Object.defineProperty(Object.prototype, 'aspect', {
        configurable: true,
        get() {
          if (BOX.some(k => hasOwn(this, k))) seen = Object.assign({}, this);
          return undefined;
        },
      });
      try {
        return origLoc.apply(this, arguments);
      } finally {
        delete Object.prototype.aspect;
        const cap = CAPTURE.get(this) || {};
        cap.layoutParams = seen;
        CAPTURE.set(this, cap);
      }
    };
    proto._positionGroup = function () {
      const sg = this._displayables.sliderGroup;
      must(!sg.needLocalTransform(), 'the sliderGroup has a transform before _positionGroup');
      const cap = CAPTURE.get(this) || {};
      const sliderRect = sg.getBoundingRect().clone();
      const children = sg.childrenRef().map(c => Object.assign({ role: roleOf(this, c), included: !(c.ignore || c.invisible) },
        matRec('local', c.getLocalTransform()), rectRec('rect', c.getBoundingRect())));
      const res = origPos.apply(this, arguments);
      const groupRect = this.group.getBoundingRect([sg]).clone();
      cap.pos = { sliderRect, children, groupRect, group: { x: this.group.x, y: this.group.y } };
      must(Object.is(this.group.x, this._location.x - (isNaN(groupRect.x) ? 0 : groupRect.x))
        && Object.is(this.group.y, this._location.y - (isNaN(groupRect.y) ? 0 : groupRect.y)), '_positionGroup did not move the group by location - rect');
      CAPTURE.set(this, cap);
      return res;
    };
  });
  hooked = true;
}
function roleOf(view, el) {
  const d = view._displayables;
  const sg = d.sliderGroup;
  if (d.handleLabels && d.handleLabels.indexOf(el) >= 0) return 'label' + d.handleLabels.indexOf(el);
  if (d.handleLabels && el.parent && d.handleLabels.indexOf(el.parent) >= 0) return 'label' + d.handleLabels.indexOf(el.parent);
  if (el === sg) return 'sliderGroup';
  if (d.handles && d.handles.indexOf(el) >= 0) return 'handle' + d.handles.indexOf(el);
  if (el === d.filler) return 'filler';
  if (el === d.moveHandle) return 'moveHandle';
  if (el === d.moveHandleIcon) return 'moveHandleIcon';
  if (el === d.moveZone) return 'moveZone';
  const segs = d.dataShadowSegs || [];
  if (segs.indexOf(el) >= 0) return 'shadow' + segs.indexOf(el);
  if (el.parent && segs.indexOf(el.parent) >= 0) return (el.type === 'polygon' ? 'shadowPolygon' : 'shadowPolyline') + segs.indexOf(el.parent);
  if (el.parent === sg && el.type === 'rect') {
    const i = sg.childrenRef().indexOf(el);
    if (i === 0) return 'background';
    if (i === 1) return 'clickPanel';
    if (el.subPixelOptimize) return 'frame';
  }
  return '?' + el.type;
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

function elementRec(view, el, role) {
  const G = echarts.graphic.getTransform(el);
  const rec = { role, type: el.type, parent: el.parent === view.group ? 'group' : roleOf(view, el.parent),
    z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.silent, invisible: !!el.invisible, ignore: !!el.ignore };
  Object.assign(rec, numRec('x', el.x), numRec('y', el.y), numRec('scaleX', el.scaleX), numRec('scaleY', el.scaleY),
    numRec('rotation', el.rotation), matRec('local', el.getLocalTransform()), matRec('global', G));
  const s = el.style;
  if (el.type === 'text') {
    must(typeof s.font === 'string' && s.font, 'a text with no font');
    measureRaw(s.text, s.font);
    const r = el.getBoundingRect().clone();
    const gr = new echarts.graphic.BoundingRect(0, 0, 0, 0);
    echarts.graphic.BoundingRect.applyTransform(gr, r, G);
    return Object.assign(rec, { text: s.text }, numRec('textX', s.x), numRec('textY', s.y),
      { align: s.align, verticalAlign: s.verticalAlign, font: s.font, fill: colRec(s.fill) },
      rectRec('rect', r), rectRec('globalRect', gr));
  }
  rec.style = Object.assign({ fill: colRec(s.fill), stroke: colRec(s.stroke) }, numRecN('lineWidth', s.lineWidth), numRecN('opacity', s.opacity),
    { strokeNoScale: !!s.strokeNoScale });
  const r = el.getBoundingRect().clone();
  if (el.type === 'rect') {
    const sh = el.shape;
    rec.shape = { x: hex(sh.x), y: hex(sh.y), width: hex(sh.width), height: hex(sh.height), r: sh.r == null ? null : J(sh.r) };
    rec.shapeText = { x: text(sh.x), y: text(sh.y), width: text(sh.width), height: text(sh.height) };
    rec.subPixelOptimize = !!el.subPixelOptimize;
  } else if (el.type === 'polygon' || el.type === 'polyline') {
    rec.points = el.type === 'polygon' ? 'area' : 'line';
    rec.pathLen = el.path.len();
  } else {
    must(el.path && el.path.len() > 0, role + ': a path element without path data');
    const data = Array.from(el.path.data).slice(0, el.path.len());
    rec.path = segs(data);
    rec.iconKind = el.shape && el.shape.symbolType != null ? 'symbol' : 'path';
    if (rec.iconKind === 'symbol') {
      const sh = el.shape;
      rec.shape = { symbolType: sh.symbolType, x: hex(sh.x), y: hex(sh.y), width: hex(sh.width), height: hex(sh.height) };
    }
    const pr = el.path.getBoundingRect();
    Object.assign(rec, rectRec('pathRect', pr));
  }
  const gr = new echarts.graphic.BoundingRect(0, 0, 0, 0);
  echarts.graphic.BoundingRect.applyTransform(gr, r, G);
  return Object.assign(rec, rectRec('rect', r), rectRec('globalRect', gr));
}

function recordSlider(chart, dz, userDz, side, key) {
  const view = chart.getViewOfComponentModel(dz);
  const rec = { index: dz.componentIndex, subType: 'slider', show: dz.get('show') !== false, noTarget: !!dz.noTarget() };
  if (!rec.show || rec.noTarget) {
    must(view.group.children().length === 0, key + ': an undrawn slider whose group has children');
    return { rec, view: null };
  }
  must(view.group.parent == null, key + ': the view group has a parent');
  const cap = CAPTURE.get(view);
  must(cap && cap.pos && cap.layoutParams, key + ': the _resetLocation / _positionGroup reads were not captured');
  const d = view._displayables;
  const sg = d.sliderGroup;
  const group = view.group;
  const proxy = dz.findRepresentativeAxisProxy();
  const win = proxy.getWindow();
  const axisModel = proxy.getAxisModel();
  const scale = axisModel.axis.scale;
  const first = dz.getFirstTargetAxisModel();
  let firstTarget = null;
  dz.eachTargetAxis((dim, idx) => { if (!firstTarget) firstTarget = { dim, index: idx }; });
  const axisType = axisModel.axis.type;
  const ts = dz.getModel('textStyle');
  const lf = dz.get('labelFormatter');
  must(lf == null || typeof lf === 'string', key + ': a function labelFormatter');
  const lp = cap.layoutParams;
  const layoutParams = {};
  for (const k of BOX) if (hasOwn(lp, k)) layoutParams[k] = numOrStr(lp[k]);
  const ref = { x: 0, y: 0, width: chart.getWidth(), height: chart.getHeight() };
  const lr = echarts.helper.getLayoutRect(lp, ref);
  const isV = view._orient === 'vertical';
  must(Object.is(lr.x, view._location.x) && Object.is(lr.y, view._location.y)
    && Object.is(isV ? lr.height : lr.width, view._size[0]) && Object.is(isV ? lr.width : lr.height, view._size[1]),
  key + ': the captured layout params do not give the location / size');
  const coordRect = view._findCoordRect();
  const itemStyle = m => styleRec(m.getItemStyle());
  const bgStyles = name => ({ area: styleRec(dz.getModel([name, 'areaStyle']).getAreaStyle()), line: styleRec(dz.getModel([name, 'lineStyle']).getLineStyle()) });
  const resolved = {
    orient: view._orient, inverse: !!(first && first.get('inverse')), firstTarget,
    labelAxis: { dim: axisModel.mainType === 'xAxis' ? 'x' : axisModel.mainType === 'yAxis' ? 'y' : axisModel.mainType, index: axisModel.componentIndex, type: axisType },
    brushSelect: !!dz.get('brushSelect'), showDataShadow: J(dz.get('showDataShadow')), showDetail: !!dz.get('showDetail'),
    handleLabelShow: !!((dz.get('handleLabel') || {}).show),
    handleIcon: dz.get('handleIcon'), moveHandleIcon: dz.get('moveHandleIcon'),
    handleSize: J(dz.get('handleSize')), moveHandleSize: J(dz.get('moveHandleSize')),
    labelPrecision: J(dz.get('labelPrecision')), labelFormatter: lf == null ? null : lf,
    borderRadius: J(dz.get('borderRadius')), z: dz.get('z'), zlevel: dz.get('zlevel') || 0,
    edgeGap: dz.get('defaultLocationEdgeGap', true),
    fillerColor: colRec(dz.get('fillerColor')), borderColor: colRec(dz.get('borderColor')),
    dataBackgroundColor: colRec(dz.get('dataBackgroundColor')), backgroundColor: colRec(dz.get('backgroundColor')),
    handleColor: colRec(dz.get('handleColor')),
    handleStyle: itemStyle(dz.getModel('handleStyle')), moveHandleStyle: itemStyle(dz.getModel('moveHandleStyle')),
    dataBackground: bgStyles('dataBackground'), selectedDataBackground: bgStyles('selectedDataBackground'),
    textStyle: { fill: colRec(ts.getTextColor()), font: ts.getFont() },
    layoutInput: J(boxJson(userDz || {})), layoutMerged: J(boxJson(dz.option)), layoutParams,
    refContainer: ref,
  };
  Object.assign(resolved, rectRec('coordRect', coordRect),
    { location: Object.assign(numRec('x', view._location.x), numRec('y', view._location.y)) },
    pairRec('size', view._size),
    { window: Object.assign(pairRec('value', win.value), pairRec('percent', win.percent), pairRec('percentInverted', win.percentInverted),
      numRec('valuePrecision', win.valuePrecision)) },
    pairRec('range', view._range), pairRec('handleEnds', view._handleEnds),
    numRec('handleWidth', view._handleWidth), numRec('handleHeight', view._handleHeight));
  resolved.moveHandleHeight = null;
  if (resolved.brushSelect) Object.assign(resolved, numRec('moveHandleHeight', echarts.number.parsePercent(dz.get('moveHandleSize'), view._size[1])));
  resolved.scaleLabels = (axisType === 'category' || axisType === 'time')
    ? win.value.map(v => (v == null || isNaN(v) ? null : scale.getLabel({ value: Math.round(v) }))) : null;

  // the data shadow
  const info = view._dataShadowInfo;
  let shadow = null;
  if (info) {
    const data = info.series.getRawData();
    const segsList = d.dataShadowSegs || [];
    const drawn = segsList.length > 0;
    shadow = { seriesIndex: info.series.seriesIndex, seriesType: info.series.subType, thisDim: info.thisDim,
      infoOtherDim: info.otherDim == null ? null : info.otherDim, otherDim: drawn ? view._shadowDim : null,
      otherAxisInverse: info.otherAxisInverse == null ? null : !!info.otherAxisInverse, thisAxisType: info.thisAxis.type,
      count: data.count(), drawn };
    if (drawn) {
      const thisVals = [];
      const otherVals = [];
      data.each([info.thisDim, view._shadowDim], (a, b) => { thisVals.push(a); otherVals.push(b); });
      side[key] = { thisVals, otherVals };
      Object.assign(shadow, pairRec('thisDataExtent', data.getDataExtent(info.thisDim)), pairRec('otherDataExtent', data.getDataExtent(view._shadowDim)));
      const ptsRec = p => ({ pts: p.map(q => q.map(hex)), txt: p.map(q => q.map(text)) });
      const a = ptsRec(view._shadowPolygonPts);
      const l = ptsRec(view._shadowPolylinePts);
      Object.assign(shadow, { area: a.pts, areaText: a.txt, line: l.pts, lineText: l.txt });
    }
  }

  // the elements (recorded before anything computes a transform)
  const elements = [];
  const collect = el => {
    if (el.isGroup) { el.childrenRef().forEach(collect); return; }
    elements.push(elementRec(view, el, roleOf(view, el)));
  };
  collect(group);
  const shadowGroups = (d.dataShadowSegs || []).map((g, i) => {
    const c = g.getClipPath();
    must(c && c.type === 'rect', key + ': a shadow group without a rect clip');
    return Object.assign({ i, selected: i === 1 }, matRec('local', g.getLocalTransform()),
      { clip: { x: hex(c.shape.x), y: hex(c.shape.y), width: hex(c.shape.width), height: hex(c.shape.height) },
        clipText: { x: text(c.shape.x), y: text(c.shape.y), width: text(c.shape.width), height: text(c.shape.height) } },
      rectRec('rect', g.getBoundingRect().clone()));
  });
  const G = group.getLocalTransform();
  const fgr = group.getBoundingRect().clone();
  const fgg = new echarts.graphic.BoundingRect(0, 0, 0, 0);
  echarts.graphic.BoundingRect.applyTransform(fgg, fgr, G);
  const viewRec = {
    group: Object.assign(numRec('x', group.x), numRec('y', group.y), matRec('matrix', G)),
    sliderGroup: Object.assign(numRec('scaleX', sg.scaleX), numRec('scaleY', sg.scaleY), numRec('rotation', sg.rotation),
      matRec('local', sg.getLocalTransform()), matRec('toGroup', echarts.graphic.getTransform(sg, group)), matRec('global', echarts.graphic.getTransform(sg))),
    position: Object.assign(rectRec('sliderRect', cap.pos.sliderRect), { children: cap.pos.children }, rectRec('groupRect', cap.pos.groupRect),
      { group: Object.assign(numRec('x', cap.pos.group.x), numRec('y', cap.pos.group.y)) }),
    elements, shadowGroups,
  };
  Object.assign(viewRec, rectRec('finalSliderRect', sg.getBoundingRect().clone()), rectRec('finalGroupRect', fgr), rectRec('finalGroupGlobalRect', fgg));
  rec.resolved = resolved;
  rec.shadow = shadow;
  rec.view = viewRec;
  return { rec, view };
}

function recordCase(def, side) {
  const src = def.gallery ? JSON.parse(fs.readFileSync(path.join(GALLERY, def.gallery + '.json'), 'utf8')) : def.option;
  const optionText = JSON.stringify(src);
  CAPTURE = new Map();
  return runChart(JSON.parse(optionText), chart => {
    const gm = chart.getModel();
    const userDzs = arr(src.dataZoom);
    const dzs = gm.findComponents({ mainType: 'dataZoom' });
    const views = [];
    const dataZooms = dzs.map(dz => {
      if (dz.subType !== 'slider') return { index: dz.componentIndex, subType: dz.subType };
      const key = def.id + '/' + dz.componentIndex;
      const r = recordSlider(chart, dz, userDzs[dz.componentIndex], side, key);
      if (r.view) views.push(r);
      return r.rec;
    });
    // the paint order last: building the display list computes the transforms
    const list = chart.getZr().storage.getDisplayList(true);
    // every other text on the chart too -- the axis labels decide where a
    // containLabel grid lands, and the slider sits by the grid -- and each
    // axis' labels as the axis lays them out, drawn or not
    for (const el of list) {
      if (el.type === 'tspan' && typeof el.style.text === 'string' && el.style.text !== '') measureRaw(el.style.text, el.style.font);
    }
    for (const mainType of ['xAxis', 'yAxis']) {
      for (const am of gm.findComponents({ mainType })) {
        if (!am.axis || !am.axis.getViewLabels) continue;
        const font = am.getModel('axisLabel').getFont();
        for (const vl of am.axis.getViewLabels()) {
          if (typeof vl.formattedLabel === 'string' && vl.formattedLabel !== '') measureRaw(vl.formattedLabel, font);
        }
      }
    }
    for (const { rec, view } of views) {
      const mine = list.filter(el => {
        for (let p = el; p; p = p.parent) if (p === view.group) return true;
        return false;
      });
      // a Text is painted through its TSpan children (none for an empty string)
      const roles = [];
      for (const el of mine) {
        const role = roleOf(view, el);
        if (/^label/.test(role)) {
          must(el.type === 'tspan', 'a label listed as ' + el.type);
          if (roles.indexOf(role) >= 0) continue;
        }
        must(roles.indexOf(role) < 0, 'paint list role ' + role + ' twice');
        roles.push(role);
      }
      const painted = roles.map(role => {
        const e = rec.view.elements.find(x => x.role === role);
        must(e, 'paint list role ' + role + ' not recorded');
        return Object.assign(e, { painted: true });
      });
      const unpainted = rec.view.elements.filter(e => roles.indexOf(e.role) < 0);
      must(unpainted.every(e => e.type === 'text' && e.text === ''), def.id + '/' + rec.index + ': unpainted ' + unpainted.map(e => e.role));
      rec.view.elements = painted.concat(unpainted.map(e => Object.assign(e, { painted: false })));
    }
    return { id: def.id, groups: def.groups, note: def.note, width: chart.getWidth(), height: chart.getHeight(),
      gallery: def.gallery || null, option: JSON.parse(optionText), dataZooms };
  });
}

// ---------- the cases ----------
const cat = n => Array.from({ length: n }, (_, i) => 'c' + i);
const V20 = [12.34, 45.67, 23.456, 78.9, 34.5, 56.78, 90.12, 11.1, 67.89, 43.21, 29.99, 88.8, 14.7, 63.3, 51.05, 37.7, 72.25, 19.9, 84.4, 58.6];
const catLine = (dz, extra, type) => Object.assign({
  xAxis: { type: 'category', data: cat(20) }, yAxis: { type: 'value' },
  series: [{ type: type || 'line', data: V20 }], dataZoom: dz,
}, extra || {});
const XS = Array.from({ length: 11 }, (_, i) => [i * 10, (i * 37) % 23]);
const valLine = (dz, extra) => Object.assign({ xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: XS }], dataZoom: dz }, extra || {});
const hBar = (dz, yAxis) => ({
  xAxis: { type: 'value' }, yAxis: Object.assign({ type: 'category', data: cat(20) }, yAxis || {}),
  series: [{ type: 'bar', data: V20 }], dataZoom: dz,
});
const DAY = 86400000;
const T0 = Date.UTC(2020, 0, 1);
const timeData = Array.from({ length: 20 }, (_, i) => [T0 + i * DAY + (i % 3) * 3600000 * 5, V20[i]]);
const timeLine = (dz) => ({ useUTC: true, xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: timeData }], dataZoom: dz });
const big = Array.from({ length: 2000 }, (_, i) => [i, Math.round((Math.sin(i / 37) * 40 + Math.cos(i / 11) * 13 + 60) * 100) / 100]);
const CANDLE = V20.map((v, i) => [v, V20[(i + 3) % 20], Math.min(v, V20[(i + 3) % 20]) - 2.5, Math.max(v, V20[(i + 3) % 20]) + 3.25]);

const CASES = [
  { id: 'D1', groups: ['D1'], note: 'default horizontal slider on a 20-category line: shadow, brushSelect; group (122.79999995231628, 584.5)', option: catLine([{ type: 'slider' }]) },
  { id: 'D2', groups: ['D2'], note: 'brushSelect false: no move handle, location y 555, group (122.5, 585)', option: catLine([{ type: 'slider', brushSelect: false }]) },
  { id: 'D3', groups: ['D3'], note: 'brushSelect false, showDataShadow false: group (120.7000000178814, 585) from the handles', option: catLine([{ type: 'slider', brushSelect: false, showDataShadow: false }]) },
  { id: 'D3b', groups: ['D3'], note: 'showDataShadow false with brushSelect: the move icon still sets min x', option: catLine([{ type: 'slider', showDataShadow: false }]) },
  { id: 'D4', groups: ['D4'], note: 'start 25 end 75 on 20 categories: handles at 151 / 449; percent (not percentInverted) drives the ends', option: catLine([{ type: 'slider', start: 25, end: 75 }]) },
  { id: 'D5', groups: ['D5'], note: 'value x, start 33.333 end 66.667: non-integer handle ends 199.99799999999996 / 400.002', option: valLine([{ type: 'slider', start: 33.333, end: 66.667 }]) },
  { id: 'D6', groups: ['D6'], note: 'category x inverse, 20-70: sliderGroup scaleX -1', option: catLine([{ type: 'slider', start: 20, end: 70 }], { xAxis: { type: 'category', data: cat(20), inverse: true } }) },
  { id: 'D6b', groups: ['D6'], note: 'value x inverse and y inverse (upstream.md 4.3 row: group (722.5, 548.5))', option: { xAxis: { type: 'value', inverse: true }, yAxis: { inverse: true }, series: [{ type: 'line', data: XS }], dataZoom: [{ start: 20, end: 80 }] } },
  { id: 'D7', groups: ['D7'], note: 'y axis inverse: otherAxisInverse -> sliderGroup scaleY 1 (not flipped)', option: catLine([{ type: 'slider', start: 10, end: 60 }], { yAxis: { type: 'value', inverse: true } }) },
  { id: 'D8', groups: ['D8'], note: 'vertical slider (yAxisIndex 0) on a horizontal bar chart, shadow: rotation pi/2 with the cos residue', option: hBar([{ type: 'slider', yAxisIndex: 0, start: 10, end: 60 }]) },
  { id: 'D8b', groups: ['D8'], note: 'vertical slider on a category-x bar chart (upstream.md 4.3: group (755.5, 522.4999999999998)); the shadow plots index vs category', option: { xAxis: { type: 'category', data: cat(20) }, yAxis: {}, series: [{ type: 'bar', data: V20 }], dataZoom: [{ type: 'slider', yAxisIndex: 0, start: 20, end: 80 }] } },
  { id: 'D9', groups: ['D9'], note: 'vertical, y category inverse: scaleX -1 with the rotation', option: hBar([{ type: 'slider', yAxisIndex: 0, start: 10, end: 60 }], { inverse: true }) },
  { id: 'D9b', groups: ['D9'], note: 'vertical, x value inverse (otherAxisInverse): scaleY -1 with the rotation', option: { xAxis: { type: 'value', inverse: true }, yAxis: { type: 'category', data: cat(20) }, series: [{ type: 'bar', data: V20 }], dataZoom: [{ type: 'slider', yAxisIndex: 0, start: 30, end: 90 }] } },
  { id: 'D10', groups: ['D10'], note: "custom handleIcon path:// with arcs (> 11 numbers: float32 store) and handleSize '80%'",
    option: catLine([{ type: 'slider', start: 20, end: 80, handleSize: '80%', handleIcon: 'path://M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4v1.3h1.3v-1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z' }]) },
  { id: 'D10b', groups: ['D10'], note: 'a short handleIcon without the path:// prefix (prefixed; 10 numbers: stays in doubles), handleSize 20 (a number)',
    option: catLine([{ type: 'slider', start: 15, end: 65, handleSize: 20, handleIcon: 'M0,0L2.3,10.7L4.1,0Z' }]) },
  { id: 'D11', groups: ['D11'], note: "built-in handleIcon 'circle' (Symbol shape, arc path in doubles): handle width = handle height", option: catLine([{ type: 'slider', start: 25, end: 75, handleIcon: 'circle' }]) },
  { id: 'D11b', groups: ['D11'], note: "handleIcon 'roundRect' (arcs), moveHandleIcon a cubic bulging past its end points (fromCubic extremes)",
    option: catLine([{ type: 'slider', start: 30, end: 70, handleIcon: 'roundRect', moveHandleIcon: 'path://M0,0C0,-10,10,-10,10,0Z' }]) },
  { id: 'D12a', groups: ['D12'], note: 'handleLabel show, value axis, labelPrecision auto (2)', option: valLine([{ type: 'slider', start: 12.3456, end: 87.6543, handleLabel: { show: true } }]) },
  { id: 'D12b', groups: ['D12'], note: "handleLabel show, labelPrecision 3, labelFormatter '{value} x'", option: valLine([{ type: 'slider', start: 12.3456, end: 87.6543, handleLabel: { show: true }, labelPrecision: 3, labelFormatter: '{value} x' }]) },
  { id: 'D12c', groups: ['D12'], note: 'handleLabel show, category axis (the category names)', option: catLine([{ type: 'slider', start: 25, end: 75, handleLabel: { show: true } }]) },
  { id: 'D12d', groups: ['D12'], note: 'handleLabel show, time axis (useUTC: the scale label of the rounded window)', option: timeLine([{ type: 'slider', start: 13, end: 77, handleLabel: { show: true } }]) },
  { id: 'D12g', groups: ['D12'], note: 'handleLabel show, time axis over three years: the bottom unit a month, the label a day', option: { useUTC: true, xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: Array.from({ length: 36 }, (_, i) => [Date.UTC(2018, i, 1), V20[i % 20]]) }], dataZoom: [{ type: 'slider', start: 10, end: 90, handleLabel: { show: true } }] } },
  { id: 'D12e', groups: ['D12'], note: 'handleLabel show with showDetail false: empty labels', option: catLine([{ type: 'slider', start: 25, end: 75, handleLabel: { show: true }, showDetail: false }]) },
  { id: 'D12f', groups: ['D12'], note: 'vertical, handleLabel show: verticalAlign from transformDirection, align center', option: hBar([{ type: 'slider', yAxisIndex: 0, start: 10, end: 60, handleLabel: { show: true } }]) },
  { id: 'D13a', groups: ['D13'], note: '{bottom: 10}: the vertical triple becomes {height: ph, bottom: 10}, top undefined', option: catLine([{ type: 'slider', bottom: 10 }]) },
  { id: 'D13b', groups: ['D13'], note: '{left: 50, right: 80}: two given -> exactly those two (width undefined)', option: catLine([{ type: 'slider', left: 50, right: 80 }]) },
  { id: 'D13c', groups: ['D13'], note: "{top: '85%', height: 20}", option: catLine([{ type: 'slider', top: '85%', height: 20 }]) },
  { id: 'D13d', groups: ['D13'], note: "{left: 50}: one given -> {width: ph, left: 50}", option: catLine([{ type: 'slider', left: 50 }]) },
  { id: 'D13e', groups: ['D13'], note: 'vertical {left: 10, top: 40, bottom: 30}', option: hBar([{ type: 'slider', yAxisIndex: 0, left: 10, top: 40, bottom: 30 }]) },
  { id: 'D14a', groups: ['D14'], note: "grid left '11.1%' right '9.7%': coordRect x 88.8 -> location x 88.79999999999995 (W - right - width); length 633.6 (frame subPixelOptimize)",
    option: catLine([{ type: 'slider', start: 10, end: 90 }], { grid: { left: '11.1%', right: '9.7%' } }) },
  { id: 'D14b', groups: ['D14'], note: 'grid left 80 right 86.7: length 633.3 -> the optimized frame (633.5) is longer than the slider',
    option: catLine([{ type: 'slider', start: 10, end: 90 }], { grid: { left: 80, right: 86.7 } }) },
  { id: 'D14c', groups: ['D14'], note: "vertical on a grid of non-integer height (top '10.3%', bottom '11.1%')", option: Object.assign(hBar([{ type: 'slider', yAxisIndex: 0, start: 10, end: 60 }]), { grid: { top: '10.3%', bottom: '11.1%' } }) },
  { id: 'D15', groups: ['D15'], note: "shadow with '-' / null gaps in the other dim (leading, inner runs, trailing)",
    option: catLine([{ type: 'slider' }], { series: [{ type: 'line', data: ['-', 12, 30, '-', null, 25, 40, '-', 18, 22, 35, '-', '-', 28, 33, 15, 20, 27, '-', '-'] }] }) },
  { id: 'D16a', groups: ['D16'], note: 'bar series shadow', option: catLine([{ type: 'slider', start: 5, end: 95 }], null, 'bar') },
  { id: 'D16b', groups: ['D16'], note: "candlestick series: the shadow's other dim is getShadowDim() 'open'",
    option: { xAxis: { type: 'category', data: cat(20) }, yAxis: { scale: true }, series: [{ type: 'candlestick', data: CANDLE }], dataZoom: [{ type: 'slider', start: 10, end: 90 }] } },
  { id: 'D17', groups: ['D17'], note: 'time x axis: the shadow coordinate is (t - t0) * L / span, not the step', option: timeLine([{ type: 'slider', start: 20, end: 80 }]) },
  { id: 'D18', groups: ['D18'], note: '2000 rows on a 600 px slider: stride round(2000 / 600) = 3, the skipped rows still advance the coordinate',
    option: { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', showSymbol: false, data: big }], dataZoom: [{ type: 'slider', start: 40, end: 60 }] } },
  { id: 'D19', groups: ['D19'], note: 'customised: fillerColor, dataBackground, selectedDataBackground, handleStyle (borderWidth 2), moveHandleStyle (stroke), borderColor, backgroundColor, borderRadius 4, moveHandleSize 10',
    option: catLine([{ type: 'slider', start: 20, end: 60, fillerColor: 'rgba(255,0,0,0.25)', borderColor: '#345', backgroundColor: 'rgba(10,20,30,0.1)', borderRadius: 4, moveHandleSize: 10,
      dataBackground: { lineStyle: { color: '#123456', width: 1.5 }, areaStyle: { color: '#abcdef', opacity: 0.4 } },
      selectedDataBackground: { lineStyle: { color: '#654321', width: 3.7 }, areaStyle: { color: '#fedcba', opacity: 0.6 } },
      handleStyle: { color: '#eee', borderColor: '#333', borderWidth: 2 }, moveHandleStyle: { color: '#999', borderColor: '#111', borderWidth: 1.5, opacity: 0.7 } }]) },
  { id: 'D20a', groups: ['D20'], note: 'show false: nothing drawn', option: catLine([{ type: 'slider', show: false }]) },
  { id: 'D20b', groups: ['D20'], note: 'xAxisIndex 5 (no such axis): noTarget, nothing drawn', option: catLine([{ type: 'slider', xAxisIndex: 5 }]) },
  { id: 'D21', groups: ['D21'], note: 'inside (host, 10-50) then slider (60-90, not host): the slider shows the host window', option: catLine([{ type: 'inside', start: 10, end: 50 }, { type: 'slider', start: 60, end: 90 }]) },
  { id: 'D10c', groups: ['D10'], note: 'a handle icon with a turned elliptical large arc (acos of an oblique ratio, an arc past a quarter point) and a half-disc move icon', option: catLine([{ type: 'slider', start: 20, end: 70, handleIcon: 'path://M0,0A6,4,20,1,1,10,3L10,12A5,5,0,0,0,0,12Z', moveHandleIcon: 'path://M0,0A5,5,0,0,1,10,0Z' }]) },
  { id: 'D23', groups: ['D23'], note: 'an inside dataZoom empties y outside 30-70 %: the slider shadow still reads the raw, unemptied values', option: catLine([{ type: 'inside', yAxisIndex: 0, filterMode: 'empty', start: 30, end: 70 }, { type: 'slider', xAxisIndex: 0 }]) },
  { id: 'D24', groups: ['D24'], note: 'the first series a pictorialBar (no shadow from it under auto): the shadow is the second series, the line', option: { xAxis: { type: 'category', data: cat(20) }, yAxis: { type: 'value' }, series: [{ type: 'pictorialBar', symbol: 'rect', data: V20 }, { type: 'line', data: V20.slice().reverse() }], dataZoom: [{ type: 'slider' }] } },
  { id: 'D22', groups: ['D22'], note: 'two grids, slider xAxisIndex [0, 1]: the first axis grid gives the rect, the first series the shadow',
    option: {
      grid: [{ bottom: '55%' }, { top: '55%' }],
      xAxis: [{ type: 'category', gridIndex: 0, data: cat(20) }, { type: 'category', gridIndex: 1, data: cat(20) }],
      yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      series: [{ type: 'line', data: V20 }, { type: 'bar', xAxisIndex: 1, yAxisIndex: 1, data: V20.map(v => v * 3) }],
      dataZoom: [{ type: 'slider', xAxisIndex: [0, 1], start: 30, end: 70 }],
    } },
  // the gallery
  { id: 'G-candlestick-sh-2015', groups: ['gallery'], note: 'candlestick-sh-2015 (gallery), verbatim', gallery: 'candlestick-sh-2015', omitOption: true },
  { id: 'G-area-rainfall', groups: ['gallery'], note: 'area-rainfall (gallery), verbatim', gallery: 'area-rainfall', omitOption: true },
  { id: 'G-line-aqi', groups: ['gallery'], note: 'line-aqi (gallery), verbatim', gallery: 'line-aqi', omitOption: true },
  { id: 'G-grid-multiple', groups: ['gallery'], note: 'grid-multiple (gallery), verbatim', gallery: 'grid-multiple', omitOption: true },
  { id: 'G-mix-zoom-on-value', groups: ['gallery'], note: 'mix-zoom-on-value (gallery), verbatim', gallery: 'mix-zoom-on-value', omitOption: true },
  { id: 'G-area-simple', groups: ['gallery'], note: 'area-simple (gallery), verbatim: 20000 rows, stride > 1', gallery: 'area-simple', omitOption: true },
  { id: 'G-dataset-encode1', groups: ['gallery'], note: "dataset-encode1 (gallery), verbatim: only the toolbox's 'select' dataZooms, no slider", gallery: 'dataset-encode1', omitOption: true },
  { id: 'G-bar-gradient', groups: ['gallery'], note: 'bar-gradient (gallery), verbatim: one inside dataZoom, no slider', gallery: 'bar-gradient' },
  { id: 'G-line-function', groups: ['gallery'], note: 'line-function (gallery), verbatim: inside dataZooms only', gallery: 'line-function', omitOption: true },
];

// ---------- the guards ----------
const GUARDS = [
  { id: 'pos-after-update', mutation: '_positionGroup reads the bounding rect after _updateView (handles scaled and placed, filler / move handle / icon at the window)', mut: { posAfterUpdate: true }, named: ['D1', 'D4', 'D8'] },
  { id: 'polyline-no-stroke', mutation: 'no stroke inflation on the shadow polyline', mut: { polylineNoStroke: true }, named: ['D1', 'D8'] },
  { id: 'polyline-lw', mutation: 'polyline inflation = lineWidth instead of max(lineWidth, 5)', mut: { polylineLwOnly: true }, named: ['D1', 'D8'] },
  { id: 'handle-no-inset', mutation: 'handle x without the +-1 inset', mut: { noHandleInset: true }, named: ['D1', 'D4', 'D5'] },
  { id: 'percent-inverted', mutation: 'handle ends from window.percentInverted instead of window.percent', mut: { percentInverted: true }, named: ['D4', 'D5'] },
  { id: 'coord-multiplied', mutation: 'shadow coordinate index * step instead of the accumulated coord += step', mut: { coordMultiplied: true }, named: ['D1', 'D18'] },
  { id: 'other-inverse-ignored', mutation: 'otherAxisInverse ignored in the sliderGroup flip', mut: { ignoreOtherInverse: true }, named: ['D7', 'D9b', 'D6b'] },
  { id: 'move-handle-option', mutation: 'the moveHandleSize option (10) used for the location instead of the constant 7', mut: { moveHandleOption: true }, named: ['D19'] },
  { id: 'left-from-x', mutation: 'left taken as coordRect.x instead of W - right - width', mut: { leftFromX: true }, named: ['D14a'] },
  { id: 'no-subpixel', mutation: 'frame without subPixelOptimize', mut: { noSubPixel: true }, named: ['D14a', 'D14b'] },
  { id: 'no-label-gap', mutation: 'label offset without the +5 gap', mut: { noLabelGap: true }, named: ['D12a', 'D12c', 'D12f'] },
  { id: 'cos0', mutation: 'exact cos = 0 for the pi/2 sliderGroup rotation instead of Math.cos(Math.PI / 2)', mut: { cos0: true }, named: ['D8', 'D8b', 'D9'] },
  { id: 'no-float32', mutation: 'a path:// icon source kept in doubles (no toStatic Float32Array, no float32 stores)', mut: { noFloat32: true }, named: ['D1', 'D10'] },
  { id: 'line-scale-local', mutation: "the strokeNoScale handles' line scale taken from their own scale (handleHeight / 2) instead of the unset transform (1)", mut: { lineScaleLocal: true }, named: ['D1', 'D4'] },
  { id: 'cubic-control-box', mutation: 'cubic segments bounded by their control points instead of fromCubic extremes', mut: { cubicControlBox: true }, named: ['D11b'] },
  { id: 'arc-no-extremes', mutation: 'arc segments bounded by their end points only (no full-circle case, no quadrant extremes)', mut: { arcNoExtremes: true }, named: ['D11'] },
  { id: 'no-stride', mutation: 'every row plotted (stride ignored)', mut: { noStride: true }, named: ['D18', 'G-area-simple'] },
  { id: 'time-by-index', mutation: 'a time axis shadow stepped like a category one', mut: { timeByIndex: true }, named: ['D17'] },
  { id: 'precision-ignored', mutation: 'labelPrecision / valuePrecision ignored (toFixed(0))', mut: { precisionIgnored: true }, named: ['D12a', 'D12b'] },
];

// ---------- the run ----------
function generate() {
  MEASURE = new Map();
  hookProto();
  const side = {};
  const cases = CASES.map(d => recordCase(d, side));
  return {
    out: {
      source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
      W, H, seed: SEED,
      api: {
        view: 'chart.getViewOfComponentModel(dataZoomModel); view._displayables (sliderGroup, filler, handles, handleLabels, moveHandle, moveHandleIcon, moveZone, dataShadowSegs); view._location, _size, _range, _handleEnds, _handleWidth, _handleHeight, _orient, _dataShadowInfo, _shadowDim, _shadowPolygonPts, _shadowPolylinePts, _findCoordRect()',
        position: 'SliderZoomView.prototype._positionGroup wrapped: sliderGroup.getBoundingRect() and each child before the original runs; group.getBoundingRect([sliderGroup]) and group.x / y after',
        layoutParams: 'SliderZoomView.prototype._resetLocation wrapped with a temporary Object.prototype.aspect getter: getLayoutRect reads positionInfo.aspect of the substituted layout params',
        window: 'dz.findRepresentativeAxisProxy().getWindow(); scaleLabels = axis.scale.getLabel({value: Math.round(v)})',
        styles: "dz.getModel('handleStyle' | 'moveHandleStyle').getItemStyle(); dz.getModel([name, 'areaStyle' | 'lineStyle']).getAreaStyle() / getLineStyle(); textStyle getTextColor() / getFont()",
        elements: 'el.getBoundingRect() (Path: with the stroke; strokeNoScale sees the unset transform -> line scale 1), el.getLocalTransform(), echarts.graphic.getTransform(el) (pure), el.path.data up to len(), el.path.getBoundingRect()',
        paint: 'zr.storage.getDisplayList(true) filtered to the view group, read after everything else (it computes the transforms)',
        shadowValues: 'getRawData().each([thisDim, otherDim]) -- in memory only',
        measure: 'echarts.format.getTextRect(string, font): zrender measureWidth + getLineHeight (the built-in width table)',
      },
      notes: [
        'Only the dist build was run; every function transcribed here reads the same in src at 30076ae (upstream.md section 0).',
        "In SSR nothing is painted during setOption, so every element's global `transform` stays unset: the handles' strokeNoScale line scale is 1 in every rect read here (_positionGroup's and the final ones). A painted frame would give 1 / 15 for the default handle; that is not what _positionGroup ever sees on the first render.",
        'The handle / move-icon path data of a path:// icon is the source PathProxy after toStatic (Float32Array when it holds more than 11 numbers) rewritten by transformPath: point coordinates are stored once as float32, an arc centre twice (*= scale, then += translate), radii once. The element proxy itself is a plain array holding those values (appendPath copies them).',
        "processArc (the default handle icon has 'a' segments) uses Math.acos, Math.sqrt, Math.cos / sin of 0; the fitted rect relies on V8's values.",
        "A built-in symbol icon ('circle', 'roundRect') is a Symbol path built in doubles (never toStatic'd before the first paint).",
        'The time-axis label text (scaleLabels) is an INPUT: the scale formatter of the rounded window end (useUTC in these cases); category labels are the category names.',
        'moveZone and invisible labels are skipped by Group.getBoundingRect but recorded with their own rects; the paint list holds them (invisible elements are listed, not drawn).',
        'The data shadow reads getRawData(): unfiltered and unsampled. The polygon starts with [L, 0], [0, 0]; a polyline with fewer than 2 points has no path (rect 0,0,0,0).',
      ],
      measure: Array.from(MEASURE.values())
        .sort((a, b) => (a.font === b.font ? (a.string < b.string ? -1 : a.string > b.string ? 1 : 0) : a.font < b.font ? -1 : 1))
        .map(m => ({ string: m.string, font: m.font, width: hex(m.width), widthText: text(m.width), height: hex(m.height), heightText: text(m.height) })),
      cases,
    },
    side,
  };
}

function sliderDiffs(c, sl, side, mut) {
  return diffFlat(flatRecord(sl), model(sl, side[c.id + '/' + sl.index], mut));
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    for (const sl of c.dataZooms) {
      if (sl.subType !== 'slider') continue;
      const key = c.id + '/' + sl.index;
      const d = sliderDiffs(c, sl, side, {});
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 4).map(x => x.field + ' (' + clip80(x.upstream) + ' vs ' + clip80(x.mutated) + ')').join('; '));
      if (!sl.view) continue;
      const r = sl.resolved;
      // element styles are the resolved ones
      const el = role => sl.view.elements.find(e => e.role === role);
      const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
      must(same(el('filler').style.fill, r.fillerColor), key + ': filler fill');
      must(same(el('background').style.fill, r.backgroundColor), key + ': background fill');
      must(el('frame').style.stroke.css === (r.dataBackgroundColor.css || r.borderColor.css), key + ': frame stroke');
      for (const i of [0, 1]) {
        must(same(el('handle' + i).style.stroke, r.handleStyle.stroke) && el('handle' + i).style.strokeNoScale, key + ': handle style');
        must(same(el('handle' + i).style.fill, r.handleColor.undef ? r.handleStyle.fill : r.handleColor), key + ': handle fill');
        const lb = el('label' + i);
        must(lb.invisible === !r.handleLabelShow && lb.font === r.textStyle.font, key + ': label visibility / font');
      }
      if (r.brushSelect) must(same(el('moveHandle').style.fill, r.moveHandleStyle.fill), key + ': move handle fill');
      if (sl.shadow && sl.shadow.drawn) {
        for (let i = 0; i < 3; i++) {
          const bg = i === 1 ? r.selectedDataBackground : r.dataBackground;
          must(same(el('shadowPolygon' + i).style.fill, bg.area.fill) && same(el('shadowPolyline' + i).style.stroke, bg.line.stroke)
            && el('shadowPolyline' + i).style.lineWidth === bg.line.lineWidth, key + ': shadow styles');
        }
      }
      for (const e of sl.view.elements) {
        if (!e.path) continue;
        const isPathIcon = e.iconKind === 'path';
        if (isPathIcon && e.path.reduce((n, s) => n + 1 + s.args.length, 0) > 11) {
          for (const s of e.path) for (const a of s.args) must(Math.fround(num(a)) === num(a), key + ' ' + e.role + ': a float32 path value is not a float32');
        }
      }
    }
  }
  // upstream.md anchors
  const sl = (id, k) => byId[id].dataZooms.find(z => z.subType === 'slider' && (k == null || z.index === k));
  const grp = id => sl(id).view.group;
  const eqG = (id, x, y) => must(grp(id).xText === x && grp(id).yText === y, id + ' group at ' + grp(id).xText + ',' + grp(id).yText + ' (want ' + x + ',' + y + ')');
  eqG('D1', '122.79999995231628', '584.5');
  eqG('D2', '122.5', '585');
  eqG('D3', '120.7000000178814', '585');
  eqG('D8b', '755.5', '522.4999999999998');
  eqG('D6b', '722.5', '548.5');
  const d1 = sl('D1');
  must(d1.resolved.handleWidthText === '6.000000536441803', 'D1 handle width ' + d1.resolved.handleWidthText);
  const h0 = d1.view.elements.find(e => e.role === 'handle0');
  must(JSON.stringify(h0.pathRectText) === JSON.stringify({ x: '-0.20000001788139343', y: '0', width: '0.40000003576278687', height: '2' }), 'D1 fitted handle rect ' + JSON.stringify(h0.pathRectText));
  // upstream.md 4.3 quotes width 605.2999999523163 from its probe chart; the last accumulated shadow coord of this
  // chart's data differs in the last bit, so only x, y, height are exact anchors here
  {
    const t = d1.view.position.sliderRectText;
    must(t.x === '-2.799999952316284' && t.y === '-0.5' && t.height === '37' && Math.abs(+t.width - 605.3) < 1e-6, 'D1 position rect ' + JSON.stringify(t));
  }
  const d4 = sl('D4');
  must(d4.view.elements.find(e => e.role === 'handle0').xText === '151' && d4.view.elements.find(e => e.role === 'handle1').xText === '449', 'D4 handles');
  must(JSON.stringify(sl('D5').resolved.handleEndsText) === JSON.stringify(['199.99799999999996', '400.002']), 'D5 handle ends');
  must(sl('D21', 1).resolved.rangeText.join() === '10,50', 'D21 host window ' + sl('D21', 1).resolved.rangeText);
  must(sl('D16b').shadow.otherDim === 'open', 'D16b shadow dim ' + sl('D16b').shadow.otherDim);
  must(!sl('D20a').show && sl('D20b').noTarget, 'D20 anchors');
  must(!byId['G-dataset-encode1'].dataZooms.some(z => z.subType === 'slider'), 'dataset-encode1 has a slider');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const s of c.dataZooms) {
        if (s.subType !== 'slider') continue;
        let d;
        try {
          d = sliderDiffs(c, s, side, gd.mut);
        } catch (e) {
          d = [{ field: 'threw', upstream: null, mutated: String(e.message) }];
        }
        if (d.length) {
          any = true;
          if (gd.named.includes(c.id)) differs.push({ case: c.id + '/' + s.index, fields: d.slice(0, 3).map(f => ({ field: f.field, upstream: clip80(f.upstream), mutated: clip80(f.mutated) })) });
        }
      }
      if (any) changed.push(c.id);
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
  g1.out.guards = check(g1);
  json1 = serialise(g1.out);
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(JSON.parse(JSON.stringify(serialiseObject(g1.out)))), 'the written JSON does not parse back to the record');
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
  + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nSliders = out.cases.reduce((n, c) => n + c.dataZooms.filter(z => z.subType === 'slider').length, 0);
console.log(out.cases.length + ' cases (' + nSliders + ' sliders), ' + out.measure.length + ' measured strings; '
  + (out.guards.length - bad.length) + '/' + out.guards.length + ' guards; two generations '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
