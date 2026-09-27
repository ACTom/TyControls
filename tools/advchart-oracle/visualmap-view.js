// Upstream's own answers for the visualMap B2 batch (wf54/audit54.md section 1.7,
// section 2 B2 cases V1..V8): the continuous visualMap component drawn
// statically -- the item align, the bar group's transform (the four-row table of
// ContinuousView._createBarGroup), the two bar polygons and their 101-stop
// object-bounding-box gradients, the clip, the end texts, the calculable handles
// and their labels, the invisible indicator, the background rect and where
// positionGroup puts the whole view group.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the models and the views
// directly -- never the SVG text. VisualMapView.prototype.renderBackground and
// .positionGroup are wrapped (the originals still run) so the group's bounding
// rect is captured at the two moments upstream reads it. Every chart is disposed
// in a finally.
//
//   node tools/advchart-oracle/visualmap-view.js
//
// writes tests/fixtures/advchart-visualmap-view.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase. Every hex field has a readable twin (xText beside x,
//            pointsText beside points, ...; String(v), '-0' for negative zero).
//   rect     {x, y, width, height} hex + rectText {x, y, width, height}
//   matrix   [m0..m5] hex + ...Text: zrender's 2x3 [a, b, c, d, tx, ty]; a point
//            maps to (a*x + c*y + tx, b*x + d*y + ty)
//   colour   {css, r, g, b, a, aText, undef}: css is the string upstream
//            produced, r/g/b/a zrender's parse of it (a hex), as in
//            visualmap-encode.js
//   paint    {kind: 'color', color} or {kind: 'gradient', type, global, x, y,
//            x2, y2 (hex + text), stops: [{offset (hex), offsetText, color}]}
//
// Text sizes. Node has no canvas: every string is measured by zrender's built-in
// width table. measure[] holds the RAW measurer answer per (string, font):
// width = measureWidth, height = getLineHeight(font) (echarts.format.getTextRect,
// i.e. what a TSpan is built from). A Text element's own getBoundingRect() is
// NOT that: Text.getBoundingRect unions its single TSpan rect with itself, so
// width = (x + w) - x ('High Score': measured 59.519999999999996, element
// 59.51999999999998). Both are recorded; the transcription derives the second.
//
// Top level
//   source, W, H, seed, api (how each value was read), notes[]
//   measure[]   {string, font, width, widthText, height, heightText}
//   cases[]     one per chart:
//     id, groups (the audit cases it serves), note, width, height
//     option       the option as fed (gallery files verbatim)
//     visualMaps[] in component order:
//       index, subType, show (option.show !== false)
//       resolved   the model's inputs to the view:
//         orient, inverse, align (option.align as merged, 'auto' by default),
//         itemAlignDerived (left/right/top/bottom read back from the bar group's
//         scaleX and the table row; upstream does not store it),
//         itemSize [hex, hex] (+Text), padding (the option as written, JSON) and
//         paddingNorm [t, r, b, l] hex, textGap hex, text (option.text or null),
//         calculable, precision, extent [hex, hex], range (option.range after
//         _resetRange), interval (view._dataInterval = getSelected()),
//         handleEnds (view._handleEnds), boxOption (option.left/right/top/
//         bottom/width/height as merged, JSON: absent = undefined),
//         boxParams (getBoxLayoutParams(), JSON), handleSize (option string),
//         backgroundColor, borderColor (colour), borderWidth hex,
//         contentColor, inactiveColor (colour), controller, target (the
//         completed option objects, JSON, key order as upstream holds it),
//         barSymbolSize {inRange: [hex, hex], outOfRange: [hex, hex]}:
//         getControllerVisual(interval[i] / extent[i], 'symbolSize',
//         {forceState}), handleSymbolSize {sketch: [..], real: [..]} (calculable
//         only): getControllerVisual(linearMap(end, [0, itemSize1], extent, true),
//         'symbolSize') at the sketch ends [0, itemSize1] and the real ends
//       view (show only):
//         group    {x, y (+Text), matrix} the view group after positionGroup
//         bar      the bar group (ContinuousView _shapes.mainGroup):
//                  x, y, rotation, scaleX, scaleY (hex + text), local =
//                  getLocalTransform(), toGroup = graphic.getTransform(bar,
//                  viewGroup) (what _applyTransform uses), global =
//                  graphic.getTransform(bar) (includes the group translation)
//         clip     the gradient group's clip Rect shape {x, y, width, height, r}
//         outOfRange, inRange  {points [[hex, hex] x4] (+Text) in bar-local
//                  coordinates, fill (paint; non-global (0,0)->(0,1) gradient),
//                  rect (the polygon's bounding rect)}
//         texts[]  (option.text only) {end (0 = low end, at -textGap; 1 = high
//                  end), string, x, y (style, view-group coords), gx, gy (global),
//                  align, verticalAlign, font, fill, rect}
//         handles[] (calculable only) per handle index:
//                  thumb {x, y, scaleX, scaleY, toGroup, global, fill, stroke,
//                  lineWidth, strokeNoScale, rect (getBoundingRect, local, with
//                  the stroke), pathRect (the path alone)}
//                  label {string, x, y, gx, gy, align, verticalAlign, font, fill,
//                  rect}
//         indicator {invisible, labelInvisible}: both true in every static case
//         background {shape {x, y, width, height, r (null when unset)}, gx, gy,
//                  z2, fill, stroke (colour), lineWidth, rect (its bounding rect:
//                  the shape through fromLine, grown by the stroke when
//                  lineWidth > 0)}
//         bboxBackground  {rect: viewGroup.getBoundingRect() as renderBackground
//                  read it (after _updateView(true): polygons and handles at the
//                  SKETCH ends [0, itemSize1]), tree}
//         bboxPosition    {before {x, y} (the group before positionGroup), rect:
//                  getBoundingRect() as positionElement read it (now with the
//                  background and the real ends), layoutRect (getLayoutRect(
//                  {width, height} + boxParams, [0,0,W,H]) -- no margin),
//                  after {x, y}, tree}
//         tree     the view group's children at that moment, recursively:
//                  {name, type, included (= !ignore && !invisible: what
//                  Group.getBoundingRect unions), local (matrix), rect,
//                  children} (+ text/sx/sy/align/verticalAlign for texts,
//                  ). Names: handleLabel0/1,
//                  indicatorLabel, bar, gradientBar, outOfRange, inRange,
//                  thumb0/1, indicator, endText0/1, background.
//
// guards[]  one per mutation: id, mutation, named (the cases that must turn
//           red), changed (the cases whose recorded values the mutated
//           transcription does not reproduce), ok = named is a subset of changed,
//           differs (for each named case, the first differing fields: field,
//           upstream, mutated)
//
// ---------------------------------------------------------------------------
// The transcription (checked against every recorded field, bit for bit) is the
// layout of ContinuousView/VisualMapView/helper.getItemAlign/layout.ts with
// zrender's Transformable.getLocalTransform, matrix.mul/rotate, vector
// applyTransform, graphic.transformDirection, BoundingRect.applyTransform/union,
// Group/Text/Path bounding rects and positionElement. Its inputs are `resolved`,
// measure[], the handle thumbs' local path rects (captured) and -- for the
// gradient stops -- upstream's own getControllerVisual colour at each sample
// value (the colour arithmetic is B1's, visualmap-encode.js); the sample-value
// loop itself is transcribed. The stop lists for the gradient mutations are
// computed while each chart is alive and kept outside the fixture.
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every case; the helper's getLayoutRect gives the captured group
// move; the text element rects follow from measure[]; the view group has no
// children when show is false; every guard is ok; two generations in the
// process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visualmap-view.json');
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
const RK = ['x', 'y', 'width', 'height'];
const rectRec = r => ({
  rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
  rectText: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) },
});
const rectOf = rr => ({ x: num(rr.rect.x), y: num(rr.rect.y), width: num(rr.rect.width), height: num(rr.rect.height) });
const matRec = (name, m) => ({ [name]: m.map(hex), [name + 'Text']: m.map(text) });
const pairRec = (name, a) => ({ [name]: a.map(hex), [name + 'Text']: a.map(text) });
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });

const UNDEF_COLOUR = { css: null, r: 0, g: 0, b: 0, a: hex(0), aText: '0', undef: true };
function colRec(c) {
  if (c == null) return Object.assign({}, UNDEF_COLOUR);
  must(typeof c === 'string', 'a colour that is not a string: ' + JSON.stringify(c));
  const p = C.parse(c);
  must(p, 'an upstream colour that does not parse: ' + c);
  return { css: c, r: p[0], g: p[1], b: p[2], a: hex(p[3]), aText: text(p[3]), undef: false };
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

// ---------- the transcription (with the mutations as switches) ----------

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

// number.ts parsePercent (parsePositionOption), as box-merge.js
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
// zrender contain/text.ts parsePercent (the handle size)
function parsePercentZr(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}
function cssArray(v) {
  if (typeof v === 'number') return [v, v, v, v];
  if (v.length === 2) return [v[0], v[1], v[0], v[1]];
  if (v.length === 3) return [v[0], v[1], v[2], v[1]];
  return v;
}

// layout.ts getLayoutRect, verbatim (container {x: 0, y: 0, width, height})
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
  // new BoundingRect flips a negative size
  let x = 0 + left + margin[3];
  let y = 0 + top + margin[0];
  if (width < 0) { x = x + width; width = -width; }
  if (height < 0) { y = y + height; height = -height; }
  return { x, y, width, height, margin };
}

// visualMap/helper.ts:40-72
const PARAMS_SET = [['left', 'right', 'width'], ['top', 'bottom', 'height']];
function getItemAlign(inp, mut) {
  if (inp.align != null && inp.align !== 'auto') return inp.align;
  const realIndex = inp.orient === 'horizontal' ? 1 : 0;
  const reals = PARAMS_SET[realIndex];
  const fakeValue = [0, null, 10];
  const layoutInput = {};
  for (let i = 0; i < 3; i++) {
    layoutInput[PARAMS_SET[1 - realIndex][i]] = fakeValue[i];
    layoutInput[reals[i]] = i === 2 ? inp.itemSize[0] : inp.boxOption[reals[i]];
  }
  const rParam = [['x', 'width', 3], ['y', 'height', 0]][realIndex];
  const rect = getLayoutRect(layoutInput, W, H, mut.alignNoMargin ? 0 : inp.padding);
  const term = mut.alignNoMargin || mut.alignNoTerm ? 0 : (rect.margin[rParam[2]] || 0);
  const ec = realIndex === 0 ? W : H;
  return reals[term + rect[rParam[0]] + rect[rParam[1]] * 0.5 < ec * 0.5 ? 0 : 1];
}

// zrender matrix.ts mul/rotate, vector.applyTransform, Transformable.getLocalTransform
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
  const pts = [[s.x, s.y], [s.x + s.width, s.y], [s.x + s.width, s.y + s.height], [s.x, s.y + s.height]].map(p => applyT(p, m));
  // lt, rb, lb, rt in zrender's argument order
  const [lt, rt, rb, lb] = pts;
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
// text.ts adjustTextX/Y; a plain one-line Text: its TSpan rect unioned with itself
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
  return groupRect([{ rect: span, m: IDENT() }]);
}
// a polygon's PathProxy bounding rect (M, L..., Z; no stroke)
function polyRect(points) {
  let x0 = Number.MAX_VALUE; let y0 = Number.MAX_VALUE; let x1 = -Number.MAX_VALUE; let y1 = -Number.MAX_VALUE;
  for (const p of points) {
    x0 = Math.min(x0, p[0]); y0 = Math.min(y0, p[1]); x1 = Math.max(x1, p[0]); y1 = Math.max(y1, p[1]);
  }
  return { x: x0, y: y0, width: x1 - x0, height: y1 - y0 };
}

// ContinuousModel.getSelected, number.asc
function getSelected(range, extent) {
  const d = range.slice().sort((a, b) => a - b);
  d[0] > extent[1] && (d[0] = extent[1]);
  d[1] > extent[1] && (d[1] = extent[1]);
  d[0] < extent[0] && (d[0] = extent[0]);
  d[1] < extent[0] && (d[1] = extent[0]);
  return d;
}

// ContinuousView._makeColorGradient's sample loop; colourAt is upstream's
// getControllerVisual(v, 'color', {forceState, convertOpacityToAlpha: true})
function gradientStops(interval, colourAt, mut) {
  const sampleNumber = 100;
  const stops = [];
  const step = (interval[1] - interval[0]) / sampleNumber;
  stops.push({ color: colourAt(interval[0]), offset: 0, value: interval[0] });
  let acc = interval[0];
  for (let i = 1; i < (mut.stops100 ? sampleNumber - 1 : sampleNumber); i++) {
    const v = mut.accumulated ? (acc += step) : interval[0] + step * i;
    if (v > interval[1]) break;
    stops.push({ color: colourAt(v), offset: i / sampleNumber, value: v });
  }
  stops.push({ color: colourAt(interval[1]), offset: 1, value: interval[1] });
  return stops;
}
const GRADIENT_MUTS = { base: {}, accumulated: { accumulated: true }, stops100: { stops100: true }, fromTarget: {} };
const gradientKey = mut => (mut.accumulated ? 'accumulated' : mut.stops100 ? 'stops100' : mut.ctrlFromTarget ? 'fromTarget' : 'base');
const stopsText = stops => stops.map(s => hex(s.offset) + '@' + s.color).join(' ');

// ContinuousView._createBarGroup, the four-row table
function barTable(orient, inverse, itemAlign, mut) {
  const isVertical = orient === 'vertical';
  const bottom = itemAlign === 'bottom';
  const left = itemAlign === 'left';
  let row = !isVertical && !inverse ? 0 : !isVertical && inverse ? 1 : isVertical && !inverse ? 2 : 3;
  if (mut.wrongRow) row = (row + 1) % 4;
  const f = s => (mut.noFlip ? 1 : s);
  switch (row) {
    case 0: return { row, scaleX: f(bottom ? 1 : -1), rotation: Math.PI / 2 };
    case 1: return { row, scaleX: f(bottom ? -1 : 1), rotation: -Math.PI / 2 };
    case 2: return { row, scaleX: f(left ? 1 : -1), scaleY: -1 };
    default: return { row, scaleX: f(left ? 1 : -1) };
  }
}

// formatValueText for a single value (dataBound = [-Infinity, Infinity])
function formatValue(v, precision, mut) {
  return v === -Infinity ? 'min' : v === Infinity ? 'max' : (+v).toFixed(Math.min(mut.precisionIgnored ? 0 : precision, 20));
}

// expandOrShrinkRect(rect, 2, false, true) then BoundingRect.intersect's overlap
function expand2(r) {
  const o = Object.assign({}, r);
  o.width += 2 + 2;
  o.x -= 2;
  o.height += 2 + 2;
  o.y -= 2;
  return o;
}
function overlaps(a, b) {
  const ax0 = a.x + 0; const ax1 = a.x + a.width - 0; const ay0 = a.y + 0; const ay1 = a.y + a.height - 0;
  const bx0 = b.x + 0; const bx1 = b.x + b.width - 0; const by0 = b.y + 0; const by1 = b.y + b.height - 0;
  if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return false;
  return !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
}

// decode a record's `resolved` into numbers
function decode(vm) {
  const r = vm.resolved;
  const n = a => a.map(num);
  return {
    show: vm.show, orient: r.orient, inverse: r.inverse, align: r.align,
    itemSize: n(r.itemSize), padding: r.padding, paddingNorm: n(r.paddingNorm), textGap: num(r.textGap),
    text: r.text, calculable: r.calculable, precision: r.precision, extent: n(r.extent), range: n(r.range),
    boxOption: r.boxOption, boxParams: r.boxParams, handleSize: r.handleSize,
    borderWidth: num(r.borderWidth), borderColor: r.borderColor.css, backgroundColor: r.backgroundColor.css,
    barSymbolSize: { inRange: n(r.barSymbolSize.inRange), outOfRange: n(r.barSymbolSize.outOfRange) },
    handleSymbolSize: r.handleSymbolSize ? { sketch: n(r.handleSymbolSize.sketch), real: n(r.handleSymbolSize.real) } : null,
    font: r.font,
  };
}

function findNode(tree, name) {
  for (const n of tree) {
    if (n.name === name) return n;
    if (n.children) {
      const f = findNode(n.children, name);
      if (f) return f;
    }
  }
  return null;
}

// the whole static layout; returns the flat field map compared with flatRecord
function model(vm, side, mut) {
  const o = {};
  const inp = decode(vm);
  if (inp.show === false && !mut.ignoreShow) {
    o.shown = 'false';
    return o;
  }
  o.shown = 'true';
  const view = vm.view || {};
  const [is0, is1] = inp.itemSize;
  const vertical = inp.orient === 'vertical';
  const itemAlign = getItemAlign(inp, mut);
  const inverse = mut.ignoreInverse ? false : inp.inverse;
  const tb = barTable(inp.orient, inverse, itemAlign, mut);
  const L = localTransform(tb, mut);
  const T = mul(L, IDENT());
  T.forEach((v, i) => { o['bar.m' + i] = hex(v); });
  o['clip'] = [0, 0, is0, is1, 3].map(hex).join(',');

  const interval = getSelected(inp.range, inp.extent);
  const ends = interval.map(v => linearMap(v, inp.extent, [0, is1], true));
  const barPoints = (e, ss) => [[is0 - ss[0], e[0]], [is0, e[0]], [is0, e[1]], [is0 - ss[1], e[1]]];
  const sketchEnds = [0, is1];
  const polys = phaseEnds => ({
    out: barPoints([0, is1], inp.barSymbolSize.outOfRange),
    in: barPoints(phaseEnds, inp.barSymbolSize.inRange),
  });
  const finalPolys = polys(ends);
  finalPolys.out.forEach((p, k) => { o['out.p' + k] = hex(p[0]) + ',' + hex(p[1]); });
  finalPolys.in.forEach((p, k) => { o['in.p' + k] = hex(p[0]) + ',' + hex(p[1]); });
  const g = side ? side[gradientKey(mut)] : null;
  o['out.stops'] = g ? stopsText(g.out) : 'n/a';
  o['in.stops'] = g ? stopsText(g.in) : 'n/a';

  // end texts
  const texts = [];
  if (inp.text) {
    for (const e of [0, 1]) {
      let s = inp.text[mut.textSwap ? e : 1 - e];
      s = s != null ? s + '' : '';
      const pos = applyT([is0 / 2, e === 0 ? -inp.textGap : is1 + inp.textGap], T);
      const dir = transformDirection(e === 0 ? 'bottom' : 'top', T);
      const t = { string: s, x: pos[0], y: pos[1], font: inp.font,
        verticalAlign: vertical ? dir : 'middle', align: vertical ? 'center' : dir };
      texts.push(t);
      o['text' + e] = [s, hex(t.x), hex(t.y), t.align, t.verticalAlign].join('|');
    }
  }

  // handles and labels, per phase
  const hs = parsePercentZr(inp.handleSize, mut.handleFromIs1 ? is1 : is0);
  const alignL = transformDirection('left', T);
  const handlePhase = (phase, phaseEnds, tree) => {
    const ss = inp.handleSymbolSize[phase === 'bg' && !mut.sketchIgnored ? 'sketch' : 'real'];
    const thumbs = [];
    const labels = [];
    for (const i of [0, 1]) {
      const sc = ss[i] / is0;
      const th = { x: is0 - ss[i] / 2, y: phaseEnds[i], scaleX: sc, scaleY: sc };
      const Lth = localTransform(th, mut);
      const Tth = mul(L, mul(Lth, IDENT()));
      const tp = applyT([hs, 0], mut.labelNoThumb ? T : Tth);
      if (!vertical) tp[1] += (alignL === 'left' || alignL === 'top') ? (is0 - ss[i]) / 2 : (is0 - ss[i]) / -2;
      thumbs.push({ th, Lth, rect: rectOf(findNode(tree, 'thumb' + i)) });
      labels.push({ string: formatValue(interval[i], inp.precision, mut), x: tp[0], y: tp[1], font: inp.font,
        verticalAlign: 'middle', align: vertical ? alignL : 'center' });
    }
    // the 6.1.0 build has no overlap push (see notes): an overlapping pair stays
    return { thumbs, labels, overlap: overlaps(expand2(textRect(labels[0])), expand2(textRect(labels[1]))) };
  };
  const bgTree = view.bboxBackground ? view.bboxBackground.tree : [];
  const posTree = view.bboxPosition ? view.bboxPosition.tree : [];
  let hBg = null;
  let hPos = null;
  if (inp.calculable) {
    hBg = handlePhase('bg', mut.sketchIgnored ? ends : sketchEnds, bgTree);
    hPos = handlePhase('pos', ends, posTree);
    for (const i of [0, 1]) {
      const th = hPos.thumbs[i].th;
      o['h' + i] = [hex(th.x), hex(th.y), hex(th.scaleX)].join(',');
      o['h' + i + '.fill'] = g ? (i === 0 ? g.in[0].color : g.in[g.in.length - 1].color) : 'n/a';
      const lb = hPos.labels[i];
      o['l' + i] = [lb.string, hex(lb.x), hex(lb.y), lb.align, lb.verticalAlign].join('|');
    }
  }

  // the view group's bounding rect at a phase
  const viewChildren = (phaseEnds, h) => {
    const p = polys(phaseEnds);
    const gradientBar = groupRect([{ rect: polyRect(p.out), m: IDENT() }, { rect: polyRect(p.in), m: IDENT() }]);
    const barKids = [{ rect: gradientBar, m: IDENT() }];
    if (h) h.thumbs.forEach(t => barKids.push({ rect: t.rect, m: t.Lth }));
    const kids = [];
    if (h) h.labels.forEach(l => kids.push({ rect: textRect(l), m: IDENT() }));
    kids.push({ rect: groupRect(barKids), m: L });
    texts.forEach(t => kids.push({ rect: textRect(t), m: IDENT() }));
    return kids;
  };
  const bbBg = groupRect(viewChildren(mut.sketchIgnored ? ends : sketchEnds, hBg));
  RK.forEach(k => { o['bboxBg.' + k] = hex(bbBg[k]); });

  // renderBackground
  let pad = cssArray(inp.padding || 0);
  if (mut.paddingOrder) pad = [pad[0], pad[3], pad[2], pad[1]];
  const shape = { x: bbBg.x - pad[3], y: bbBg.y - pad[0], width: bbBg.width + pad[3] + pad[1], height: bbBg.height + pad[0] + pad[2] };
  RK.forEach(k => { o['bg.' + k] = hex(shape[k]); });
  const bgRect = {
    x: Math.min(shape.x, shape.x + shape.width), y: Math.min(shape.y, shape.y + shape.height),
  };
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

  // positionGroup
  const posKids = viewChildren(ends, hPos);
  posKids.push({ rect: bgRect, m: IDENT() });
  const bbPos = groupRect(posKids);
  RK.forEach(k => { o['bboxPos.' + k] = hex(bbPos[k]); });
  const lp = { width: bbPos.width, height: bbPos.height };
  for (const k of Object.keys(inp.boxParams)) if (lp[k] == null) lp[k] = inp.boxParams[k];
  const lr = getLayoutRect(lp, W, H, mut.posMargin ? inp.padding : undefined);
  RK.forEach(k => { o['layout.' + k] = hex(lr[k]); });
  o['group.x'] = hex(0 + (lr.x - bbPos.x));
  o['group.y'] = hex(0 + (lr.y - bbPos.y));
  return o;
}

// the same fields read from a record
function flatRecord(vm) {
  const o = {};
  if (!vm.show) {
    o.shown = 'false';
    return o;
  }
  o.shown = 'true';
  const v = vm.view;
  v.bar.toGroup.forEach((h, i) => { o['bar.m' + i] = h; });
  o['clip'] = ['x', 'y', 'width', 'height', 'r'].map(k => v.clip[k]).join(',');
  v.outOfRange.points.forEach((p, k) => { o['out.p' + k] = p.join(','); });
  v.inRange.points.forEach((p, k) => { o['in.p' + k] = p.join(','); });
  const st = paint => paint.stops.map(s => s.offset + '@' + s.color.css).join(' ');
  o['out.stops'] = st(v.outOfRange.fill);
  o['in.stops'] = st(v.inRange.fill);
  if (v.texts) v.texts.forEach(t => { o['text' + t.end] = [t.string, t.x, t.y, t.align, t.verticalAlign].join('|'); });
  if (v.handles) {
    v.handles.forEach((hd, i) => {
      o['h' + i] = [hd.thumb.x, hd.thumb.y, hd.thumb.scaleX].join(',');
      o['h' + i + '.fill'] = hd.thumb.fill.css;
      const lb = hd.label;
      o['l' + i] = [lb.string, lb.x, lb.y, lb.align, lb.verticalAlign].join('|');
    });
  }
  RK.forEach(k => { o['bboxBg.' + k] = v.bboxBackground.rect[k]; });
  RK.forEach(k => { o['bg.' + k] = v.background.shape[k]; });
  RK.forEach(k => { o['bboxPos.' + k] = v.bboxPosition.rect[k]; });
  RK.forEach(k => { o['layout.' + k] = v.bboxPosition.layoutRect[k]; });
  o['group.x'] = v.group.x;
  o['group.y'] = v.group.y;
  return o;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => a[k] !== b[k]).map(k => ({ field: k, upstream: a[k] === undefined ? null : a[k], mutated: b[k] === undefined ? null : b[k] }));
}

// a stop-list difference as its first differing stop (offset@css) and the counts
function compactDiff(f) {
  if (!/stops$/.test(f.field) || f.upstream == null || f.mutated == null) return f;
  const u = f.upstream.split(' ');
  const m = f.mutated.split(' ');
  let i = 0;
  while (i < u.length && i < m.length && u[i] === m[i]) i++;
  return { field: f.field, stop: i, upstream: u[i] === undefined ? null : u[i], mutated: m[i] === undefined ? null : m[i],
    upstreamCount: u.length, mutatedCount: m.length };
}

// ---------- capturing the two bounding-rect reads ----------
let CAPTURE = new Map();
let hooked = false;
function nameOf(view, group, el, textCounter) {
  const s = view._shapes;
  if (el === s.mainGroup) return 'bar';
  if (el === s.inRange) return 'inRange';
  if (el === s.outOfRange) return 'outOfRange';
  if (el === s.indicator) return 'indicator';
  if (el === s.indicatorLabel) return 'indicatorLabel';
  if (s.handleThumbs && s.handleThumbs.indexOf(el) >= 0) return 'thumb' + s.handleThumbs.indexOf(el);
  if (s.handleLabels && s.handleLabels.indexOf(el) >= 0) return 'handleLabel' + s.handleLabels.indexOf(el);
  if (el.parent === s.mainGroup && el.isGroup) return 'gradientBar';
  if (el.parent === group && el.type === 'rect') return 'background';
  if (el.parent === group && el.type === 'text') return 'endText' + textCounter.n++;
  return '?' + el.type;
}
function captureTree(view, group) {
  const counter = { n: 0 };
  const walk = el => {
    const r = el.getBoundingRect();
    const node = Object.assign({ name: nameOf(view, group, el, counter), type: el.type,
      included: !(el.ignore || el.invisible), invisible: !!el.invisible, ignore: !!el.ignore },
    matRec('local', el.getLocalTransform()), rectRec(r));
    if (el.type === 'text') {
      Object.assign(node, { text: el.style.text }, numRec('sx', el.style.x || 0), numRec('sy', el.style.y || 0),
        { align: el.style.align == null ? null : el.style.align, verticalAlign: el.style.verticalAlign == null ? null : el.style.verticalAlign });
    }
    if (el.isGroup) node.children = el.children().map(walk);
    return node;
  };
  return group.children().map(walk);
}
function hookViews() {
  if (hooked) return;
  runChart({ series: [], visualMap: { type: 'continuous' } }, ch => {
    const vm = ch.getModel().getComponent('visualMap', 0);
    const view = ch.getViewOfComponentModel(vm);
    const cproto = Object.getPrototypeOf(view);
    const vproto = Object.getPrototypeOf(cproto);
    must(!hasOwn(cproto, 'renderBackground') && !hasOwn(cproto, 'positionGroup'), 'ContinuousView overrides the hooked methods');
    must(hasOwn(vproto, 'renderBackground') && hasOwn(vproto, 'positionGroup'), 'VisualMapView has no renderBackground/positionGroup');
    const origBg = vproto.renderBackground;
    const origPos = vproto.positionGroup;
    vproto.renderBackground = function (group) {
      const cap = { bg: Object.assign(rectRec(group.getBoundingRect().clone()), { tree: captureTree(this, group) }) };
      CAPTURE.set(this, cap);
      return origBg.call(this, group);
    };
    vproto.positionGroup = function (group) {
      const cap = CAPTURE.get(this);
      must(cap && !cap.pos, 'positionGroup without a renderBackground, or twice');
      const before = { x: group.x, y: group.y };
      must(!group.needLocalTransform(), 'the view group has a transform before positionGroup');
      const r = group.getBoundingRect().clone();
      cap.pos = Object.assign(numRec('beforeX', before.x), numRec('beforeY', before.y), rectRec(r), { tree: captureTree(this, group) });
      const model = this.visualMapModel;
      const params = model.getBoxLayoutParams();
      const lr = echarts.helper.getLayoutRect(echarts.util.defaults({ width: r.width, height: r.height }, params),
        { x: 0, y: 0, width: W, height: H });
      cap.pos.layout = { layoutRect: rectRec(lr).rect, layoutRectText: rectRec(lr).rectText, lr };
      const res = origPos.call(this, group);
      cap.pos.after = { x: group.x, y: group.y };
      must(Object.is(group.x, before.x + (lr.x - r.x)) && Object.is(group.y, before.y + (lr.y - r.y)),
        'positionGroup did not move the group by layoutRect - rect');
      return res;
    };
  });
  hooked = true;
}

// ---------- the cases ----------
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const barOpt = (vm, data) => ({
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: {}, visualMap: vm,
  series: [{ type: 'bar', data: data || [10, 50, 90] }],
});
const V = (o) => Object.assign({ type: 'continuous', min: 0, max: 100 }, o);

const CASES = [
  { id: 'V1', groups: ['V1'], note: 'default vertical at left 0 / bottom 0: group (15, 585)', option: barOpt(V({})) },
  { id: 'V2', groups: ['V2', 'V4'], note: "dataset-encode0 (gallery): horizontal, left 'center', text ['High Score', 'Low Score']",
    gallery: 'dataset-encode0' },
  { id: 'V3a', groups: ['V3'], note: 'vertical right 10: the item align is right, the bar flipped (scaleX -1)', option: barOpt(V({ right: 10 })) },
  { id: 'V3b', groups: ['V3'], note: 'vertical left 380: right only through the padding margin (15 + 395 + 10 >= 400; without it 380 + 10 < 400)',
    option: barOpt(V({ left: 380, text: ['H', 'L'] })) },
  { id: 'V3c', groups: ['V3'], note: 'vertical left 370: right only through the extra margin term (15 + 385 + 10 >= 400; without the term 395 < 400)',
    option: barOpt(V({ left: 370 })) },
  { id: 'V3d', groups: ['V3'], note: 'vertical right 10, calculable: the handle labels align right', option: barOpt(V({ right: 10, calculable: true })) },
  { id: 'V4a', groups: ['V4'], note: 'horizontal inverse (row 1, auto align bottom), text, calculable',
    option: barOpt(V({ orient: 'horizontal', inverse: true, left: 'center', text: ['High', 'Low'], calculable: true })) },
  { id: 'V4b', groups: ['V4'], note: 'vertical inverse (row 3, auto align left), text, calculable',
    option: barOpt(V({ inverse: true, text: ['High', 'Low'], calculable: true })) },
  { id: 'V4c', groups: ['V4'], note: "horizontal align 'top' (row 0, scaleX -1), text",
    option: barOpt(V({ orient: 'horizontal', align: 'top', left: 'center', text: ['High', 'Low'] })) },
  { id: 'V4d', groups: ['V4'], note: "vertical align 'right' (row 2, scaleX -1), text, calculable",
    option: barOpt(V({ align: 'right', text: ['High', 'Low'], calculable: true })) },
  { id: 'V4e', groups: ['V4'], note: "horizontal inverse align 'top' (row 1, scaleX 1), text, calculable",
    option: barOpt(V({ orient: 'horizontal', inverse: true, align: 'top', left: 'center', text: ['High', 'Low'], calculable: true })) },
  { id: 'V4f', groups: ['V4'], note: "vertical inverse align 'right' (row 3, scaleX -1), text",
    option: barOpt(V({ inverse: true, align: 'right', text: ['High', 'Low'] })) },
  { id: 'V5', groups: ['V5'], note: "inRange colour ['rgba(0,0,0,0)', 'rgba(0,0,0,1)'] on [10, 100.3]: the bar's 101 stops",
    option: barOpt(V({ min: 10, max: 100.3, inRange: { color: ['rgba(0,0,0,0)', 'rgba(0,0,0,1)'] } })) },
  { id: 'V6', groups: ['V6'], note: "calendar-charts vm1 shape: controller.inRange {opacity [0.3, 0.6]} + inRange {color ['grey'], opacity [0, 0.3]}",
    option: barOpt({ min: 0, max: 1000, inRange: { color: ['grey'], opacity: [0, 0.3] },
      controller: { inRange: { opacity: [0.3, 0.6] }, outOfRange: { color: '#ccc' } }, orient: 'horizontal', left: '10%', bottom: 20 },
    [100, 500, 900]) },
  { id: 'V6b', groups: ['V6'], note: 'calendar-charts (gallery): both visualMaps', gallery: 'calendar-charts' },
  { id: 'V7', groups: ['V7'], note: "heatmap-cartesian's visualMap on a bar series: calculable horizontal, bottom '15%', [0, 10]",
    option: barOpt({ min: 0, max: 10, calculable: true, orient: 'horizontal', left: 'center', bottom: '15%' }, [1, 5, 9]) },
  { id: 'V7b', groups: ['V7'], note: 'heatmap-cartesian (gallery), verbatim', gallery: 'heatmap-cartesian' },
  { id: 'V7c', groups: ['V7'], note: 'calculable horizontal, range [4.9, 5.1]: the two labels overlap and stay where they are (the 6.1.0 build has no push)',
    option: barOpt({ min: 0, max: 10, range: [4.9, 5.1], calculable: true, orient: 'horizontal', left: 'center', bottom: '15%' }, [1, 5, 9]) },
  { id: 'V7d', groups: ['V7'], note: 'calculable vertical, range [2, 7], precision 2: the background bbox is taken at the sketch ends [0, 140]',
    option: barOpt({ min: 0, max: 10, range: [2, 7], precision: 2, calculable: true }, [1, 5, 9]) },
  { id: 'V8', groups: ['V8'], note: 'show false: nothing drawn', option: barOpt(V({ show: false })) },
  { id: 'V9a', groups: ['extra'], note: "itemWidth 30, itemHeight '200' (a string, parseFloat)", option: barOpt(V({ itemWidth: 30, itemHeight: '200' })) },
  { id: 'V9b', groups: ['extra'], note: 'padding [5, 10, 20, 30], text', option: barOpt(V({ padding: [5, 10, 20, 30], text: ['High', 'Low'] })) },
  { id: 'V9c', groups: ['extra'], note: "borderWidth 1, borderColor '#333', backgroundColor '#eee': the stroke half-width enters the position bbox",
    option: barOpt(V({ borderWidth: 1, borderColor: '#333', backgroundColor: '#eee' })) },
  { id: 'V9d', groups: ['extra'], note: 'vertical text, textGap 20', option: barOpt(V({ text: ['High', 'Low'], textGap: 20 })) },
  { id: 'V9e', groups: ['extra'], note: 'precision 2, calculable, horizontal, range [1.234, 7.891] on [0, 10]',
    option: barOpt({ min: 0, max: 10, range: [1.234, 7.891], precision: 2, calculable: true, orient: 'horizontal', left: 'center' }, [1, 5, 9]) },
  { id: 'V9f', groups: ['extra'], note: "vertical left 'center', top 'middle', text", option: barOpt(V({ left: 'center', top: 'middle', text: ['High', 'Low'] })) },
  { id: 'V9g', groups: ['extra'], note: "horizontal right '10%', top 40, calculable", option: barOpt(V({ orient: 'horizontal', right: '10%', top: 40, calculable: true })) },
  // batch 55's gap cases: values that are not round, so (x + w) - x and the
  // text's (y - h/2 + h/2) - h/2 differ from the short forms
  { id: 'V9h', groups: ['extra'], note: 'vertical text, textGap 0.1, padding [5.3, 7.1, 2.9] (three: the left is the right)',
    option: barOpt(V({ text: ['High', 'Low'], textGap: 0.1, padding: [5.3, 7.1, 2.9] })) },
  { id: 'V9i', groups: ['extra'], note: "horizontal, itemWidth 20.3, itemHeight 140.7, handleSize '97%', calculable, text",
    option: barOpt(V({ orient: 'horizontal', itemWidth: 20.3, itemHeight: 140.7, handleSize: '97%', calculable: true, text: ['High', 'Low'] })) },
  { id: 'V9j', groups: ['extra'], note: 'inRange {opacity} with no colour: the bar is contentColor with an alpha ramp',
    option: barOpt(V({ inRange: { opacity: [0.3, 1] } })) },
  { id: 'V9k', groups: ['extra'], note: 'horizontal, itemWidth 20.7, itemHeight 139.3, alone: the turned bar is the only child of the sketch rect',
    option: barOpt(V({ orient: 'horizontal', itemWidth: 20.7, itemHeight: 139.3 })) },
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

const BOX = ['left', 'right', 'top', 'bottom', 'width', 'height'];
function boxJson(o) {
  const r = {};
  for (const k of BOX) if (o[k] !== undefined) r[k] = o[k];
  return r;
}
function textRec(el, G) {
  const s = el.style;
  const g = echarts.vector.applyTransform([], [s.x, s.y], G);
  const r = el.getBoundingRect();
  must(typeof s.font === 'string' && s.font, 'a text with no font');
  measureRaw(s.text, s.font);
  return Object.assign({ string: s.text }, numRec('x', s.x), numRec('y', s.y), numRec('gx', g[0]), numRec('gy', g[1]),
    { align: s.align, verticalAlign: s.verticalAlign, font: s.font, fill: colRec(s.fill) }, rectRec(r));
}
function polyRec(el) {
  return Object.assign({ points: el.shape.points.map(p => p.map(hex)), pointsText: el.shape.points.map(p => p.map(text)),
    fill: paintRec(el.style.fill) }, rectRec(el.getBoundingRect()));
}

function recordVM(chart, vmModel, side, key) {
  const view = chart.getViewOfComponentModel(vmModel);
  const opt = vmModel.option;
  const show = vmModel.get('show') !== false;
  const shapes = view._shapes;
  const is = vmModel.itemSize;
  const extent = vmModel.getExtent();
  const calculable = !!vmModel.get('calculable');
  const interval = vmModel.getSelected();
  const ss = (v, st) => view.getControllerVisual(v, 'symbolSize', { forceState: st, convertOpacityToAlpha: true });
  const ssH = v => view.getControllerVisual(v, 'symbolSize');
  const endVal = e => linearMap(e, [0, is[1]], extent, true);
  const ends = interval.map(v => linearMap(v, extent, [0, is[1]], true));
  const ts = vmModel.textStyleModel;
  must(ts.get('align') == null && ts.get('verticalAlign') == null, key + ': textStyle align/verticalAlign set');
  const font = new echarts.graphic.Text({ style: echarts.helper.createTextStyle(ts, { text: 'x' }) }).style.font;
  const resolved = {
    orient: vmModel.get('orient'), inverse: !!vmModel.get('inverse'), align: opt.align,
    itemSize: is.map(hex), itemSizeText: is.map(text), padding: clone(opt.padding),
    paddingNorm: cssArray(opt.padding || 0).map(hex), paddingNormText: cssArray(opt.padding || 0).map(text),
    textGap: hex(vmModel.get('textGap')), textGapText: text(vmModel.get('textGap')),
    text: opt.text ? clone(opt.text) : null, calculable, precision: opt.precision,
    extent: extent.map(hex), extentText: extent.map(text), range: opt.range.map(hex), rangeText: opt.range.map(text),
    interval: interval.map(hex), intervalText: interval.map(text),
    handleEnds: ends.map(hex), handleEndsText: ends.map(text),
    boxOption: boxJson(opt), boxParams: boxJson(vmModel.getBoxLayoutParams()),
    handleSize: vmModel.get('handleSize'),
    backgroundColor: colRec(vmModel.get('backgroundColor')), borderColor: colRec(vmModel.get('borderColor')),
    borderWidth: hex(vmModel.get('borderWidth')), borderWidthText: text(vmModel.get('borderWidth')),
    contentColor: colRec(vmModel.get('contentColor')), inactiveColor: colRec(vmModel.get('inactiveColor')),
    font,
    controller: clone(opt.controller), target: clone(opt.target),
    barSymbolSize: {
      inRange: interval.map(v => hex(ss(v, 'inRange'))), outOfRange: extent.map(v => hex(ss(v, 'outOfRange'))),
    },
  };
  if (calculable) {
    resolved.handleSymbolSize = { sketch: [0, is[1]].map(e => hex(ssH(endVal(e)))), real: ends.map(e => hex(ssH(endVal(e)))) };
  }
  if (!show) must(view.group.children().length === 0, key + ': show false but the view group has children');

  // the gradient stop lists: upstream's colour at the transcribed sample values
  const colourAt = st => v => view.getControllerVisual(v, 'color', { forceState: st, convertOpacityToAlpha: true });
  const sd = {};
  for (const k of Object.keys(GRADIENT_MUTS)) {
    const saved = vmModel.controllerVisuals;
    if (k === 'fromTarget') vmModel.controllerVisuals = vmModel.targetVisuals;
    try {
      sd[k] = { in: gradientStops(interval, colourAt('inRange'), GRADIENT_MUTS[k]),
        out: gradientStops(extent, colourAt('outOfRange'), GRADIENT_MUTS[k]) };
    } finally {
      vmModel.controllerVisuals = saved;
    }
  }
  side[key] = sd;

  const rec = { index: vmModel.componentIndex, subType: vmModel.subType, show, resolved };
  if (!show) return rec;

  const cap = CAPTURE.get(view);
  must(cap && cap.bg && cap.pos, key + ': the bounding-rect reads were not captured');
  const group = view.group;
  const G = group.getLocalTransform();
  const main = shapes.mainGroup;
  const gradientBar = main.childAt(0);
  must(gradientBar.isGroup && gradientBar.childAt(0) === shapes.outOfRange && gradientBar.childAt(1) === shapes.inRange,
    key + ': the gradient group is not [outOfRange, inRange]');
  const clip = gradientBar.getClipPath().shape;
  const kids = group.children();
  const bgEl = kids[kids.length - 1];
  must(bgEl.type === 'rect' && bgEl.z2 === -1, key + ': the last child is not the background');
  const endTexts = kids.filter(el => el.type === 'text' && el !== shapes.indicatorLabel
    && !(shapes.handleLabels && shapes.handleLabels.indexOf(el) >= 0));
  must(endTexts.length === (opt.text ? 2 : 0), key + ': ' + endTexts.length + ' end texts');

  const sc = main.scaleX;
  const orient = resolved.orient;
  const inv = resolved.inverse;
  resolved.itemAlignDerived = orient === 'vertical' ? (sc === 1 ? 'left' : 'right') : (inv ? (sc === -1 ? 'bottom' : 'top') : (sc === 1 ? 'bottom' : 'top'));

  const bgShape = bgEl.shape;
  const bgG = echarts.vector.applyTransform([], [bgShape.x, bgShape.y], G);
  const viewRec = {
    group: Object.assign(numRec('x', group.x), numRec('y', group.y), matRec('matrix', G)),
    bar: Object.assign(numRec('x', main.x), numRec('y', main.y), numRec('rotation', main.rotation), numRec('scaleX', main.scaleX),
      numRec('scaleY', main.scaleY), matRec('local', main.getLocalTransform()),
      matRec('toGroup', echarts.graphic.getTransform(main, group)), matRec('global', echarts.graphic.getTransform(main))),
    clip: { x: hex(clip.x), y: hex(clip.y), width: hex(clip.width), height: hex(clip.height), r: hex(clip.r) },
    outOfRange: polyRec(shapes.outOfRange),
    inRange: polyRec(shapes.inRange),
  };
  if (opt.text) viewRec.texts = endTexts.map((el, e) => Object.assign({ end: e }, textRec(el, G)));
  if (calculable) {
    viewRec.handles = [0, 1].map(i => {
      const th = shapes.handleThumbs[i];
      const lb = shapes.handleLabels[i];
      return {
        thumb: Object.assign(numRec('x', th.x), numRec('y', th.y), numRec('scaleX', th.scaleX), numRec('scaleY', th.scaleY),
          matRec('toGroup', echarts.graphic.getTransform(th, group)), matRec('global', echarts.graphic.getTransform(th)),
          { fill: colRec(th.style.fill), stroke: colRec(th.style.stroke) }, numRec('lineWidth', th.style.lineWidth),
          { strokeNoScale: !!th.style.strokeNoScale }, rectRec(th.getBoundingRect()),
          { pathRect: rectRec(th.path.getBoundingRect()).rect, pathRectText: rectRec(th.path.getBoundingRect()).rectText }),
        label: textRec(lb, G),
      };
    });
  }
  viewRec.indicator = { invisible: !!shapes.indicator.invisible, labelInvisible: !!shapes.indicatorLabel.invisible };
  viewRec.background = Object.assign({
    shape: { x: hex(bgShape.x), y: hex(bgShape.y), width: hex(bgShape.width), height: hex(bgShape.height),
      r: bgShape.r == null ? null : hex(bgShape.r) },
    shapeText: { x: text(bgShape.x), y: text(bgShape.y), width: text(bgShape.width), height: text(bgShape.height) },
  }, numRec('gx', bgG[0]), numRec('gy', bgG[1]), { z2: bgEl.z2, fill: colRec(bgEl.style.fill), stroke: colRec(bgEl.style.stroke) },
  numRec('lineWidth', bgEl.style.lineWidth), rectRec(bgEl.getBoundingRect()));
  viewRec.bboxBackground = { rect: cap.bg.rect, rectText: cap.bg.rectText, tree: cap.bg.tree };
  viewRec.bboxPosition = {
    before: { x: cap.pos.beforeX, y: cap.pos.beforeY }, rect: cap.pos.rect, rectText: cap.pos.rectText,
    layoutRect: cap.pos.layout.layoutRect, layoutRectText: cap.pos.layout.layoutRectText,
    after: Object.assign(numRec('x', cap.pos.after.x), numRec('y', cap.pos.after.y)), tree: cap.pos.tree,
  };
  must(Object.is(cap.pos.after.x, group.x) && Object.is(cap.pos.after.y, group.y), key + ': the group moved after positionGroup');
  rec.view = viewRec;
  return rec;
}

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  CAPTURE = new Map();
  return runChart(JSON.parse(optionText), chart => {
    const vms = chart.getModel().findComponents({ mainType: 'visualMap' });
    must(vms.length >= 1, def.id + ': no visualMap');
    const visualMaps = vms.map(m => {
      must(m.subType === 'continuous', def.id + ': a ' + m.subType + ' visualMap');
      return recordVM(chart, m, side, def.id + '/' + m.componentIndex);
    });
    return { id: def.id, groups: def.groups, note: def.note, width: chart.getWidth(), height: chart.getHeight(),
      option: JSON.parse(optionText), visualMaps };
  });
}

// ---------- the guards ----------
const GUARDS = [
  { id: 'V1-posmargin', mutation: 'the background padding also used as the positionGroup margin', mut: { posMargin: true }, named: ['V1'] },
  { id: 'V2-cos0', mutation: 'exact cos = 0 (sin = +-1) for the +-pi/2 bar rotation instead of Math.cos(Math.PI / 2)', mut: { cos0: true },
    named: ['V2'] },
  { id: 'V2-text', mutation: 'text[0] put at the low end (text[e] instead of text[1 - e])', mut: { textSwap: true }, named: ['V2'] },
  { id: 'V3-align', mutation: 'getItemAlign without the padding (neither in getLayoutRect nor as the extra term)', mut: { alignNoMargin: true },
    named: ['V3b', 'V3c'] },
  { id: 'V3-term', mutation: 'getItemAlign without the extra (margin[3|0] || 0) term', mut: { alignNoTerm: true }, named: ['V3c'] },
  { id: 'V3-flip', mutation: 'scaleX never flipped by the item align', mut: { noFlip: true }, named: ['V3a', 'V3d', 'V4c', 'V4d', 'V4f'] },
  { id: 'V4-row', mutation: 'the next row of the four-row table taken', mut: { wrongRow: true },
    named: ['V1', 'V2', 'V4a', 'V4b', 'V4c', 'V4d', 'V4e', 'V4f'] },
  { id: 'V4-inverse', mutation: 'inverse ignored', mut: { ignoreInverse: true }, named: ['V4a', 'V4b', 'V4e', 'V4f'] },
  { id: 'V5-accumulated', mutation: 'bar gradient sample value accumulated (v += step) instead of v0 + step * i', mut: { accumulated: true },
    named: ['V5'] },
  { id: 'V5-stops', mutation: '100 stops instead of 101 (the sample loop stops at i < 99)', mut: { stops100: true }, named: ['V5'] },
  { id: 'V6-controller', mutation: 'the bar colours from the target visuals instead of the controller', mut: { ctrlFromTarget: true },
    named: ['V6'] },
  { id: 'V7-handlesize', mutation: "handle size '120%' taken of itemSize[1] instead of itemSize[0]", mut: { handleFromIs1: true },
    named: ['V7'] },
  { id: 'V7-thumb', mutation: 'the handle label point transformed through the bar group only, not the thumb', mut: { labelNoThumb: true },
    named: ['V7'] },
  { id: 'V7-sketch', mutation: 'the background bbox taken at the real handle ends instead of the sketch ends [0, itemSize1]',
    mut: { sketchIgnored: true }, named: ['V7d'] },
  { id: 'V8-show', mutation: 'show false ignored (the component drawn)', mut: { ignoreShow: true }, named: ['V8'] },
  { id: 'X-precision', mutation: 'precision ignored in the handle labels (toFixed(0))', mut: { precisionIgnored: true }, named: ['V7d', 'V9e'] },
  { id: 'X-stroke', mutation: "the background's stroke not in the position bbox", mut: { bgStrokeIgnored: true }, named: ['V9c'] },
  { id: 'X-padding', mutation: 'padding [t, r, b, l] read as [t, l, b, r] for the background', mut: { paddingOrder: true }, named: ['V9b'] },
];

// ---------- the run ----------
function generate() {
  MEASURE = new Map();
  hookViews();
  const side = {};
  const cases = CASES.map(d => recordCase(d, side));
  measureRaw('\u56fd', cases[0].visualMaps[0].resolved.font);
  const measure = Array.from(MEASURE.values())
    .sort((a, b) => (a.font === b.font ? (a.string < b.string ? -1 : a.string > b.string ? 1 : 0) : a.font < b.font ? -1 : 1))
    .map(m => ({ string: m.string, font: m.font, width: hex(m.width), widthText: text(m.width), height: hex(m.height), heightText: text(m.height) }));
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version
      + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED,
    api: {
      view: 'chart.getViewOfComponentModel(visualMapModel); view._shapes (mainGroup, inRange, outOfRange, handleThumbs, handleLabels, indicator, indicatorLabel)',
      bboxBackground: 'VisualMapView.prototype.renderBackground wrapped: group.getBoundingRect() before the original runs',
      bboxPosition: 'VisualMapView.prototype.positionGroup wrapped: group.getBoundingRect() before, group.x/y after; layoutRect = echarts.helper.getLayoutRect(defaults({width, height}, getBoxLayoutParams()), [0,0,W,H])',
      transforms: 'el.getLocalTransform(); echarts.graphic.getTransform(el, viewGroup) and getTransform(el)',
      measure: 'echarts.format.getTextRect(string, font): zrender measureWidth + getLineHeight (the built-in width table)',
      symbolSize: "view.getControllerVisual(v, 'symbolSize', ...)",
      gradient: "polygon.style.fill (LinearGradient(0, 0, 0, 1), non-global); colours = view.getControllerVisual(v, 'color', {forceState, convertOpacityToAlpha: true})",
    },
    notes: [
      "The echarts SOURCE tree (src/component/visualMap/ContinuousView.ts:626-703) pushes overlapping handle labels apart (BoundingRect.intersect with a direction MTV, HANDLE_LABEL_MERGE_MARGIN 2, hdlIdx 'all'); the 6.1.0 dist build this oracle runs (dist/echarts.js:90618-90652) has no such code. V7c records the dist behaviour: the two labels overlap and are not moved. The port follows the fixture.",
      "The horizontal handle-label offset (itemSize0 - symbolSize) / +-2 is 0 in every case here: the controller symbolSize is itemSize0 unless a controller symbolSize is written (B3).",
      "The handle thumb's local rect (the path:// icon fitted into handleSize, grown by the stroke: lineWidth 2, strokeNoScale) is an INPUT to the transcription (captured at both reads); it is not re-derived from the icon path. Under the V7-handlesize mutation the transcription keeps the recorded thumb rect: what turns red there is the label position [handleSize, 0] through the thumb.",
      'The gradient stop colours are upstream getControllerVisual answers (B1 arithmetic, visualmap-encode.js); the sample-value loop is transcribed. Mutated stop lists are computed while each chart is alive and are not written.',
      'Text rects: a Text element unions its TSpan rect with itself, so its width is (x + w) - x, not the measured width (High Score: 59.519999999999996 measured, 59.51999999999998 in the rect).',
      'The indicator and its label are invisible in every static case and so outside both bounding rects (Group.getBoundingRect skips invisible children).',
    ],
    measure, cases,
  };
  return { out, side };
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    byId[c.id] = c;
    for (const vm of c.visualMaps) {
      const key = c.id + '/' + vm.index;
      const d = diffFlat(flatRecord(vm), model(vm, side[key], {}));
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 4).map(x => x.field + ' (' + x.upstream + ' vs ' + x.mutated + ')').join('; '));
      if (vm.show) {
        const v = vm.view;
        must(v.indicator.invisible && v.indicator.labelInvisible, key + ': a visible indicator');
        const texts = (v.texts || []).concat((v.handles || []).map(h => h.label));
        for (const t of texts) {
          const r = textRect({ string: t.string, font: t.font, x: num(t.x), y: num(t.y), align: t.align, verticalAlign: t.verticalAlign });
          must(RK.every(k => hex(r[k]) === t.rect[k]), key + ': the text rect of ' + JSON.stringify(t.string) + ' does not follow from measure[]');
          must(num(t.gx) === num(t.x) + num(v.group.x) && num(t.gy) === num(t.y) + num(v.group.y), key + ': text global != local + group');
        }
      }
    }
  }
  // audit anchors
  const v1 = byId.V1.visualMaps[0].view;
  must(v1.group.xText === '15' && v1.group.yText === '585', 'V1 group at ' + v1.group.xText + ',' + v1.group.yText);
  const v2 = byId.V2.visualMaps[0].view;
  must(v2.group.xText === '328.68' && v2.group.yText === '585', 'V2 group at ' + v2.group.xText + ',' + v2.group.yText);
  must(v2.texts[1].string === 'High Score' && v2.texts[1].yText === '-9.999999999999991', 'V2 High Score y ' + v2.texts[1].yText);
  must(v2.inRange.fill.stops.length === 101 && v2.inRange.fill.stops[1].offset === '3f847ae147ae147b', 'V2 bar stops');
  const v7 = byId.V7.visualMaps[0].view;
  must(v7.handles[0].label.yText === '-34' && v7.handles[0].label.string === '0' && v7.handles[1].label.string === '10', 'V7 labels');
  {
    const hv = byId.V7c.visualMaps[0].view.handles.map(h => h.label);
    const lr = hv.map(l => expand2(textRect({ string: l.string, font: l.font, x: num(l.x), y: num(l.y), align: l.align, verticalAlign: l.verticalAlign })));
    must(overlaps(lr[0], lr[1]), 'V7c: the labels do not overlap');
  }
  must(byId.V3b.visualMaps[0].resolved.itemAlignDerived === 'right' && byId.V3c.visualMaps[0].resolved.itemAlignDerived === 'right', 'V3b/c align');
  must(!byId.V8.visualMaps[0].show && !byId.V8.visualMaps[0].view, 'V8 drew something');
  const rows = new Set();
  for (const c of out.cases) {
    for (const vm of c.visualMaps) {
      if (vm.view) rows.add(barTable(vm.resolved.orient, vm.resolved.inverse, vm.resolved.itemAlignDerived, {}).row + ':' + vm.view.bar.scaleXText);
    }
  }
  for (const r of ['0:1', '0:-1', '1:1', '1:-1', '2:1', '2:-1', '3:1', '3:-1']) must(rows.has(r), 'no case hits table row/scaleX ' + r);

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const vm of c.visualMaps) {
        const key = c.id + '/' + vm.index;
        let d;
        try {
          d = diffFlat(flatRecord(vm), model(vm, side[key], gd.mut));
        } catch (e) {
          d = [{ field: 'threw', upstream: null, mutated: String(e.message) }];
        }
        if (d.length) {
          any = true;
          if (gd.named.includes(c.id)) differs.push({ case: key, fields: d.slice(0, 3).map(compactDiff) });
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
try {
  g1 = generate();
  g1.out.guards = check(g1);
  json1 = fmt(g1.out, '') + '\n';
  const g2 = generate();
  g2.out.guards = check(g2);
  json2 = fmt(g2.out, '') + '\n';
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
const vmCount = out.cases.reduce((n, c) => n + c.visualMaps.length, 0);
console.log(out.cases.length + ' cases (' + vmCount + ' visualMaps), ' + out.measure.length + ' measured strings; '
  + (out.guards.length - bad.length) + '/' + out.guards.length + ' guards; two generations '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
