/*
Upstream's own answers for series MARKERS, batch M3: the PICTURE of a markPoint
-- each marker's symbol and its label -- exactly as MarkPointView.renderSeries,
chart/helper/SymbolDraw.ts, Symbol.ts, util/symbol.ts, label/labelStyle.ts,
model/mixin/dataFormat.ts, chart/helper/labelHelper.ts and zrender
(Element.ts updateInnerText, graphic/Path.ts getBoundingRect / getInsideTextFill
/ getInsideTextStroke, contain/text.ts calculateTextPosition, core/PathProxy.ts
+ core/bbox.ts + core/curve.ts, core/BoundingRect.ts applyTransform,
core/Transformable.ts, graphic/Text.ts, canvas/dashStyle.ts,
svg/mapStyleToAttrs.ts) build them. M1 (markers-layout.js) pinned the model,
the data transform and the symbol points; this oracle takes those as given and
pins what is drawn on them. M2 (markers-line.js) is the sibling for markLine.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
for every chart case, with Math.random replaced by the port's xorshift32 (seed
2463534242, reset before each chart). After setOption it runs
zr.storage.getDisplayList(true) (every element's update: transforms, then
updateInnerText places the labels) and chart.renderToSVGString() (the SVG
painter builds every path proxy and prints the painted stroke width / dash),
then reads the live elements: per series the slave markPoint model's mpData
(MarkerModel.getMarkerModelFromSeries, as M1), per marker
mpData.getItemGraphicEl(i) = the Symbol group, its only child the symbol path
(SymbolClz) and symbolPath.getTextContent() (the label). Every chart is
disposed in a finally.

Which ORIGINAL data element a marker came from: as M1, every case runs twice --
verbatim (every recorded value comes from this run) and once more with each data
element tagged '__oracleIndex'; the tagged run must give exactly the same
pictures, and its tags give `index` / `survived`.

  node tools/advchart-oracle/markers-point.js

writes tests/fixtures/advchart-markers-point.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Conventions (as markers-line.js)
  hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
           lowercase (NaN 7ff8000000000000). Every hex field k has a readable
           twin kText (String(v), '-0' for negative zero).
  val      a raw JS value of the option world, tagged by kind: null (undefined
           or null) | {"n": hex, "t": text} a number | {"s": string} | {"j":
           json} anything else
  json     an option value exactly as upstream holds it (JSON; undefined ->
           null)
  rect     {x, y, width, height} hex, with rectText {x, y, width, height}
  path     [{cmd, args [hex], argsText}] -- a PathProxy's data up to len():
           'M' (x, y), 'L' (x, y), 'C' (6), 'A' (cx, cy, rx, ry, startAngle,
           sweep, 0, clockwise 1 / anticlockwise 0 -- PathProxy.arc after
           normalizeArcAngles), 'R' (x, y, w, h), 'Z' (none)
  m6       a transform matrix [a, b, c, d, e, f] (zrender order: x' = a x +
           c y + e, y' = b x + d y + f) as 6 hex + a Text twin; null when the
           element has none (zrender draws it untransformed)
  colour   a css string exactly as upstream holds it, or null

Top level
  source, W, H, seed, api, notes[], cases[], guards[]
  cases[]  one per chart:
    id, note, width, height, gallery (file name or null), option (as fed;
    null for a gallery case: load examples/advchart/gallery/<gallery>.json
    and feed it verbatim), nan (true: a marker of this case is NOT drawn
    because its point holds NaN -- documented in the note)
    ground   {background: zr.getBackgroundColor() (the option's
             backgroundColor or 'transparent'), isDark: zr.isDarkMode()
             (option darkMode when a boolean, else lum(background) < 0.4)}
    textStyle  json: ecModel.option.textStyle -- the global text style every
             label font part falls back to (defaults fontSize 12, fontStyle /
             fontWeight 'normal', fontFamily 'Microsoft YaHei' when
             navigator.platform starts with 'Win' -- this machine -- else
             'sans-serif'; globalDefault.ts:20-27, 86-94)
    series[] every series whose OWN option has markPoint.data, series order:
      seriesIndex, name (option name or null), type, filtered (legend-
      unselected: nothing drawn, `markPoint` null), color (the series style
      colour, getVisualFromData(seriesData, 'color'): the fill every marker
      falls back to), seriesName (the host series' name as {a} prints it;
      null when the option has no name -- upstream's generated name holds a
      NUL), markPoint: null (filtered) or
        z, zlevel (json: retrieveZInfo, model.get('z') || 0 through series
        markPoint -> top-level markPoint -> default 5), silent (the SymbolDraw
        group's silent: markPoint.silent || series.silent -- every element
        below inherits it for hit testing), count (mpData.count()),
        dims [{name, type}] (mpData's dimensions: x / y typed like the series'
        coord dims), labelDims (mpData.mapDimensionsAll('defaultedLabel'): the
        LAST dim whose type is not 'ordinal' / 'time'; [] when none)
        items[]  one per ORIGINAL element of series.markPoint.data, in order:
          index, survived (kept by the transform + filter), dataIndex (its
          index in mpData, or null); when it survived also:
          value, name   val: the raw (transformed) item's value / name (what
                        the default text and {b} / {c} read)
          point, pointText  [hex, hex]: mpData.getItemLayout (M1-proven)
          visual        json: the item visuals symbol, symbolSize,
                        symbolRotate, symbolOffset, symbolKeepAspect (item ->
                        series markPoint -> top-level markPoint -> default,
                        getShallow WITH parent fallback), and fill (colour: the
                        visual style fill = itemStyle.color, or the series
                        colour when that is falsy; the label's inheritColor)
          drawn         false when the point holds NaN or the symbol visual is
                        'none' (SymbolDraw symbolNeedsDraw): then symbol and
                        label are null
          symbol        the Symbol group and its symbol path:
            symbol (the visual; a falsy one is drawn as 'circle'), shapeType
            (the drawn shape: upstream's shape.symbolType after the 'empty'
            prefix is stripped; an unknown name is BUILT as 'rect' but keeps
            its name here), empty (bool: __isEmptyBrush),
            shape {x, y, width, height} + shapeText: the createSymbol box --
            ALWAYS the unit box (-1, -1, 2, 2),
            group {x, y (hex + Text): the point, transform (m6 of the group:
            translate(point), null at (0, 0))},
            x, y, rotation, scaleX, scaleY, originX, originY (hex + Text): the
            path's own props (x / y = normalizeSymbolOffset(symbolOffset,
            size), percents of the SIZE; rotation = symbolRotate deg -> rad;
            scale = size / 2),
            local (m6: the path's local transform, null when needLocalTransform
            is false), transform (m6: the path's GLOBAL transform = group x
            local, what the painter uses),
            path (in LOCAL coordinates of the unit box),
            bbox + bboxText (rect: PathProxy.getBoundingRect of that path),
            lineScale (hex + Text: getLineScale() of the global transform --
            sqrt|det| unless m[0] OR m[3] is within 1e-10 of 1, then 1),
            style {fill, stroke (colour), lineWidth (hex + Text), opacity (hex
            + Text), lineDash (json: borderType as held), lineDashOffset (hex +
            Text), strokeNoScale (bool)} after useStyle + setColor,
            paint (read back from the SVG <path>: what is painted, in LOCAL
            units because the stroke is not scaled): {stroke (bool: a stroke
            is painted), strokeWidth (hex + Text: lineWidth / lineScale, null
            without stroke), dash ([hex] + dashText: the resolved dash /
            lineScale, or null)},
            z, z2, zlevel, silent (el.isSilent(): its own or an ancestor's)
          label         null (not shown), else:
            text          style.text: a string, or null (no value and no
                          formatter: nothing is painted)
            rich          bool: the label has rich styles (its text is drawn
                          token by token; ink is then null and not transcribed)
            lines         the number of TSpans (text lines) or null (rich)
            position      json: textConfig.position ('inside' default;
                          'outside' -> 'top')
            distance      hex + Text: textConfig.distance (default 5)
            rect, rectText  the rect the label is placed against: the symbol
                          path's getBoundingRect() (grown by the stroke when
                          one is set: lineWidth / lineScale, at least 5 when
                          there is no fill) transformed by its GLOBAL transform
            x, y, rotation, originX, originY, scaleX, scaleY (hex + Text): the
                          text element's own props (0 / 0 / 0 / 0 / 0 / 1 / 1)
            inner         {x, y, rotation, originX, originY} hex + innerText:
                          the innerTransformable after updateInnerText
                          (calculateTextPosition on `rect` + the pin rule, then
                          label.rotate / label.offset)
            transform     m6 of the inner transformable
            align, verticalAlign  as laid out: the style's (author) value, else
                          the calculated one, else 'left' / 'top'
            authorAlign, authorVerticalAlign  the style's after zrender
                          normalizeStyle ('middle' align -> 'center', 'center'
                          valign -> 'middle', invalid -> 'left' / 'top'); null
                          = unset
            inside        bool: the inside ink rule applies (position a string
                          containing 'inside' AND the path has a fill)
            font          style.font (makeFont), fontSize, fontWeight,
                          fontStyle, fontFamily (json: the style's parts)
            style         {fill, stroke (colour or null: not in the style),
                          lineWidth (hex or null), opacity (hex),
                          backgroundColor (json or null)}
            inkDefault    {fill, stroke, autoStroke, align, verticalAlign} =
                          the text's _defaultStyle set by updateInnerText
                          (inside: getInsideTextFill / getInsideTextStroke of
                          the path fill; outside: '#333' / '#ccc' and the
                          ground halo)
            ink           null when rich or no TSpan, else the TSpans (all the
                          same): {fill, stroke (null = none), lineWidth (hex or
                          null), opacity (hex)}
            z, z2, zlevel, silent
guards[]  one per mutation of the transcription: id, mutation, named (the
          cases that must turn red), changed (the cases whose recorded values
          the mutated transcription does not reproduce), ok = named is a
          subset of changed, differs (the first differing fields of each
          named case)

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, bit for bit) takes as
INPUTS: the option as fed (the series' markPoint option, the top-level
markPoint option merged over MarkPointModel.defaultOption), the M1-proven mpData
raw items and points, mpData's dimension types, the series colour, the host
series name, ecModel.option.textStyle, and the ground (background, isDark). It
reproduces: MarkPointView.renderSeries (the visual chain, getItemStyle, the fill
fallback, z2), SymbolDraw symbolNeedsDraw, Symbol.ts _createSymbol /
_updateCommon (the unit box, scale = size / 2, rotation, offset, useStyle,
setColor, strokeNoScale, setLabelStyle with its inheritColor / defaultOpacity,
the default text), util/symbol.ts (createSymbol, the shape makers and proxies'
buildPath over a recording PathProxy with normalizeArcAngles / modPI2,
SymbolClz.calculateTextPosition's pin rule, normalizeSymbolSize /
normalizeSymbolOffset), labelHelper getDefaultLabel + dimensionHelper
defaultedLabel + dataProvider retrieveRawValue, dataFormat getFormattedLabel +
formatTpl, labelStyle createTextStyle / setTokenTextStyle / createTextConfig,
zrender Transformable getLocalTransform / needLocalTransform / updateTransform /
getLineScale, matrix.mul / rotate, PathProxy.getBoundingRect with bbox.fromLine
/ fromCubic / fromArc and curve.cubicExtrema / cubicAt, Path.getBoundingRect
(stroke growth), BoundingRect.applyTransform, contain/text
calculateTextPosition, Element.updateInnerText (inside / outside ink,
textConfig rotation / offset), Path.getInsideTextFill / getInsideTextStroke
(zrender tool/color lum), Element.getOutsideFill / getOutsideStroke, Text
normalizeStyle / makeFont / parseFontSize and the TSpan ink rules,
canvas/dashStyle normalizeLineDash + getLineDash and the SVG stroke width, and
util/graphic traverseUpdateZ (z, zlevel, label z2 = running max z2 + 2).

Self-checks (any failure: nothing is written, exit 1): the transcription
reproduces every recorded series (every field, bit for bit); the tagged run
gives the same pictures as the verbatim run and its tags increase; each drawn
marker is a Symbol group at its point holding exactly one SymbolClz path, the
group chain above it has no transform, and the SymbolDraw group holds exactly
the drawn markers in data order; drawn markers are exactly the markers with a
non-NaN point and a symbol other than 'none'; the recorded label placement
equals calculateTextPosition (+ pin rule, rotate, offset) on the recorded rect;
every drawn symbol is matched by at least one SVG <path> with its series and
data index and its transform, and all matches agree; no NaN in any recorded
picture, and a marker is not drawn for a NaN point exactly in the cases marked
nan; anchors; every guard is ok; two generations in the process give
identical bytes.
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-markers-point.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;
const TAG = '__oracleIndex';

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
const json = v => (v === undefined ? null : JSON.parse(JSON.stringify(v, (k, x) => (typeof x === 'number' && !isFinite(x) ? String(x) : x))));
function val(v) {
  if (v == null) return null;
  if (typeof v === 'number') return { n: hex(v), t: text(v) };
  if (typeof v === 'string') return { s: v };
  return { j: json(v) };
}
function nums(o, keys) {
  const r = {};
  for (const k of keys) {
    r[k] = hex(o[k]);
    r[k + 'Text'] = text(o[k]);
  }
  return r;
}
const hexOrNull = v => (v == null ? null : hex(v));
const textOrNull = v => (v == null ? null : text(v));
const colour = v => (v == null ? null : (must(typeof v === 'string', 'a colour that is not a string: ' + JSON.stringify(v)), v));
function m6(m, key) {
  key = key || 'transform';
  if (!m) return { [key]: null, [key + 'Text']: null };
  return { [key]: Array.from(m).slice(0, 6).map(hex), [key + 'Text']: Array.from(m).slice(0, 6).map(text) };
}
function rectRec(r, key) {
  return { [key]: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
    [key + 'Text']: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) } };
}

// ---------- the path proxy commands ----------
const CMD = { M: 1, L: 2, C: 3, Q: 4, A: 5, Z: 6, R: 7 };
const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };
const CMD_ARGS = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 };
function decode(data) {
  const out = [];
  for (let i = 0; i < data.length;) {
    const c = data[i++];
    must(CMD_NAME[c], 'an unknown path command ' + c);
    const n = CMD_ARGS[c];
    const args = data.slice(i, i + n);
    i += n;
    out.push({ cmd: CMD_NAME[c], args: args.map(hex), argsText: args.map(text) });
  }
  return out;
}

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
const retrieve2 = (a, b) => (a != null ? a : b);

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================

// MarkPointModel.defaultOption (MarkPointModel.ts:72-94)
const MP_DEFAULTS = {
  z: 5, symbol: 'pin', symbolSize: 50, tooltip: { trigger: 'item' },
  label: { show: true, position: 'inside' }, itemStyle: { borderWidth: 2 }, emphasis: { label: { show: true } },
};
const PI = Math.PI;
const PI2 = PI * 2;
const NEUTRAL00 = '#fff'; // tokens.color.neutral00 (visual/tokens.ts:124)
const MAXV = Number.MAX_VALUE;

// Model getShallow / get over [own, parent, grandparent ...]
function chainGet(levels, key, ownOnly) {
  let v;
  for (let i = 0; i < levels.length; i++) {
    const o = levels[i];
    v = o && typeof o === 'object' ? o[key] : undefined;
    if (v != null || ownOnly) return v;
  }
  return v;
}
const sub = (levels, key) => levels.map(o => (o && typeof o === 'object' ? o[key] : undefined));

// util/number.ts parsePositionOption (= parsePercent)
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
// zrender contain/text.ts parsePercent
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}
// util/symbol.ts:390-411
function normalizeSymbolSize(s) {
  if (!isArray(s)) s = [+s, +s];
  return [s[0] || 0, s[1] || 0];
}
function normalizeSymbolOffset(o, size, mut) {
  if (o == null) return undefined;
  if (!isArray(o)) o = [o, o];
  return [parsePercent(o[0], size[0]) || 0, parsePercent(retrieve2(o[1], o[0]), mut.offsetWidthPercent ? size[0] : size[1]) || 0];
}

// ---- zrender PathProxy (a recorder) + normalizeArcAngles (core/PathProxy.ts:60-101, 293-314) ----
function modPI2(radian) {
  const n = Math.round(radian / PI * 1e8) / 1e8;
  return (n % 2) * PI;
}
function normalizeArcAngles(angles, anticlockwise, mut) {
  let newStartAngle = mut.noModPI2 ? angles[0] % PI2 : modPI2(angles[0]);
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
  constructor(mut) { this.data = []; this.mut = mut; }
  moveTo(x, y) { this.data.push(CMD.M, x, y); }
  lineTo(x, y) { this.data.push(CMD.L, x, y); }
  bezierCurveTo(a, b, c, d, e, f) { this.data.push(CMD.C, a, b, c, d, e, f); }
  rect(x, y, w, h) { this.data.push(CMD.R, x, y, w, h); }
  closePath() { this.data.push(CMD.Z); }
  arc(cx, cy, r, startAngle, endAngle, anticlockwise) {
    const a = [startAngle, endAngle];
    normalizeArcAngles(a, anticlockwise, this.mut);
    this.data.push(CMD.A, cx, cy, r, r, a[0], a[1] - a[0], 0, anticlockwise ? 0 : 1);
  }
}

// zrender graphic/helper/roundRect.ts (a number r only)
function roundRectPath(ctx, x, y, width, height, r) {
  if (width < 0) { x = x + width; width = -width; }
  if (height < 0) { y = y + height; height = -height; }
  let r1 = r;
  let r2 = r;
  let r3 = r;
  let r4 = r;
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

const BUILT = { line: 1, rect: 1, roundRect: 1, square: 1, circle: 1, diamond: 1, pin: 1, arrow: 1, triangle: 1 };
// util/symbol.ts SymbolClz.buildPath (293-307) with the shape makers (199-265) and the proxies' buildPath
function symbolPath(shapeType, x, y, w, h, mut) {
  const ctx = new Proxy(mut);
  let t = shapeType;
  if (t === 'none') return ctx.data;
  if (!BUILT[t]) t = 'rect';
  switch (t) {
    case 'line': // symbolShapeMakers.line + zr Line.buildPath (the proxy has no subPixelOptimize, percent 1)
      ctx.moveTo(x, y + h / 2);
      ctx.lineTo(x + w, y + h / 2);
      break;
    case 'rect': ctx.rect(x, y, w, h); break;
    case 'roundRect': {
      const r = Math.min(w, h) / 4;
      if (!r) ctx.rect(x, y, w, h);
      else roundRectPath(ctx, x, y, w, h, r);
      break;
    }
    case 'square': {
      const size = Math.min(w, h);
      ctx.rect(x, y, size, size);
      break;
    }
    case 'circle': {
      const cx = x + w / 2;
      const cy = y + h / 2;
      const r = Math.min(w, h) / 2;
      ctx.moveTo(cx + r, cy);
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      break;
    }
    case 'diamond': {
      const cx = x + w / 2;
      const cy = y + h / 2;
      const width = w / 2;
      const height = h / 2;
      ctx.moveTo(cx, cy - height);
      ctx.lineTo(cx + width, cy);
      ctx.lineTo(cx, cy + height);
      ctx.lineTo(cx - width, cy);
      ctx.closePath();
      break;
    }
    case 'triangle': {
      const cx = x + w / 2;
      const cy = y + h / 2;
      const width = w / 2;
      const height = h / 2;
      ctx.moveTo(cx, cy - height);
      ctx.lineTo(cx + width, cy + height);
      ctx.lineTo(cx - width, cy + height);
      ctx.closePath();
      break;
    }
    case 'pin': {
      // util/symbol.ts:102-141: (px, py) = the CUSP at the box centre, the head above it
      const px = x + w / 2;
      const py = y + h / 2;
      const pw = w / 5 * 3;
      const ph = Math.max(pw, h);
      const r = pw / 2;
      const dy = r * r / (ph - r);
      const cy = py - ph + r + dy;
      const angle = Math.asin(dy / r);
      const dx = Math.cos(angle) * r;
      const tanX = Math.sin(angle);
      const tanY = Math.cos(angle);
      const cpLen = r * 0.6;
      const cpLen2 = r * 0.7;
      ctx.moveTo(px - dx, cy + dy);
      ctx.arc(px, cy, r, Math.PI - angle, Math.PI * 2 + angle);
      ctx.bezierCurveTo(px + dx - tanX * cpLen, cy + dy + tanY * cpLen, px, py - cpLen2, px, py);
      ctx.bezierCurveTo(px, py - cpLen2, px - dx + tanX * cpLen, cy + dy + tanY * cpLen, px - dx, cy + dy);
      ctx.closePath();
      break;
    }
    case 'arrow': {
      // the shape maker puts (x, y) at the box CENTRE, and Arrow.buildPath draws its TIP there
      const ax = x + w / 2;
      const ay = y + h / 2;
      const height = h;
      const dx = w / 3 * 2;
      ctx.moveTo(ax, ay);
      ctx.lineTo(ax + dx, ay + height);
      ctx.lineTo(ax, ay + height / 4 * 3);
      ctx.lineTo(ax - dx, ay + height);
      ctx.lineTo(ax, ay);
      ctx.closePath();
      break;
    }
  }
  return ctx.data;
}

// ---- zrender core/curve.ts cubicAt / cubicExtrema, core/bbox.ts, PathProxy.getBoundingRect (490-597) ----
const CURVE_EPS = 1e-8;
const aroundZero = v => v > -CURVE_EPS && v < CURVE_EPS;
const notAroundZeroC = v => v > CURVE_EPS || v < -CURVE_EPS;
function cubicAt(p0, p1, p2, p3, t) {
  const onet = 1 - t;
  return onet * onet * (onet * p0 + 3 * t * p1) + t * t * (t * p3 + 3 * onet * p2);
}
function cubicExtrema(p0, p1, p2, p3, extrema) {
  const b = 6 * p2 - 12 * p1 + 6 * p0;
  const a = 9 * p1 + 3 * p3 - 3 * p0 - 9 * p2;
  const c = 3 * p1 - 3 * p0;
  let n = 0;
  if (aroundZero(a)) {
    if (notAroundZeroC(b)) {
      const t1 = -c / b;
      if (t1 >= 0 && t1 <= 1) extrema[n++] = t1;
    }
  } else {
    const disc = b * b - 4 * a * c;
    if (aroundZero(disc)) {
      extrema[0] = -b / (2 * a); // NOT counted: n stays 0 (curve.ts:156-158)
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
function fromLine(x0, y0, x1, y1, min, max) {
  min[0] = Math.min(x0, x1);
  min[1] = Math.min(y0, y1);
  max[0] = Math.max(x0, x1);
  max[1] = Math.max(y0, y1);
}
function fromCubic(x0, y0, x1, y1, x2, y2, x3, y3, min, max) {
  const xDim = [];
  const yDim = [];
  let n = cubicExtrema(x0, x1, x2, x3, xDim);
  min[0] = Infinity;
  min[1] = Infinity;
  max[0] = -Infinity;
  max[1] = -Infinity;
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
  min[0] = Math.min(x0, min[0]);
  max[0] = Math.max(x0, max[0]);
  min[0] = Math.min(x3, min[0]);
  max[0] = Math.max(x3, max[0]);
  min[1] = Math.min(y0, min[1]);
  max[1] = Math.max(y0, max[1]);
  min[1] = Math.min(y3, min[1]);
  max[1] = Math.max(y3, max[1]);
}
function fromArc(x, y, rx, ry, startAngle, endAngle, anticlockwise, min, max) {
  const diff = Math.abs(startAngle - endAngle);
  if (diff % PI2 < 1e-4 && diff > 1e-4) {
    min[0] = x - rx;
    min[1] = y - ry;
    max[0] = x + rx;
    max[1] = y + ry;
    return;
  }
  const start = [Math.cos(startAngle) * rx + x, Math.sin(startAngle) * ry + y];
  const end = [Math.cos(endAngle) * rx + x, Math.sin(endAngle) * ry + y];
  min[0] = Math.min(start[0], end[0]);
  min[1] = Math.min(start[1], end[1]);
  max[0] = Math.max(start[0], end[0]);
  max[1] = Math.max(start[1], end[1]);
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
      min[0] = Math.min(ex, min[0]);
      min[1] = Math.min(ey, min[1]);
      max[0] = Math.max(ex, max[0]);
      max[1] = Math.max(ey, max[1]);
    }
  }
}
function pathBBox(data) {
  const min = [MAXV, MAXV];
  const max = [-MAXV, -MAXV];
  const min2 = [MAXV, MAXV];
  const max2 = [-MAXV, -MAXV];
  let xi = 0;
  let yi = 0;
  let x0 = 0;
  let y0 = 0;
  let i;
  for (i = 0; i < data.length;) {
    const cmd = data[i++];
    const isFirst = i === 1;
    if (isFirst) {
      xi = data[i];
      yi = data[i + 1];
      x0 = xi;
      y0 = yi;
    }
    switch (cmd) {
      case CMD.M:
        xi = x0 = data[i++];
        yi = y0 = data[i++];
        min2[0] = x0; min2[1] = y0; max2[0] = x0; max2[1] = y0;
        break;
      case CMD.L:
        fromLine(xi, yi, data[i], data[i + 1], min2, max2);
        xi = data[i++];
        yi = data[i++];
        break;
      case CMD.C:
        fromCubic(xi, yi, data[i++], data[i++], data[i++], data[i++], data[i], data[i + 1], min2, max2);
        xi = data[i++];
        yi = data[i++];
        break;
      case CMD.A: {
        const cx = data[i++];
        const cy = data[i++];
        const rx = data[i++];
        const ry = data[i++];
        const startAngle = data[i++];
        const endAngle = data[i++] + startAngle;
        i += 1;
        const anticlockwise = !data[i++];
        if (isFirst) {
          x0 = Math.cos(startAngle) * rx + cx;
          y0 = Math.sin(startAngle) * ry + cy;
        }
        fromArc(cx, cy, rx, ry, startAngle, endAngle, anticlockwise, min2, max2);
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
        xi = x0;
        yi = y0;
        break;
      default:
        must(false, 'pathBBox: command ' + cmd);
    }
    min[0] = Math.min(min[0], min2[0]);
    min[1] = Math.min(min[1], min2[1]);
    max[0] = Math.max(max[0], max2[0]);
    max[1] = Math.max(max[1], max2[1]);
  }
  if (i === 0) min[0] = min[1] = max[0] = max[1] = 0;
  return { x: min[0], y: min[1], width: max[0] - min[0], height: max[1] - min[1] };
}

// ---- zrender Transformable (needLocalTransform, getLocalTransform, updateTransform, getLineScale), matrix ----
const EPSILON = 5e-5;
const notAroundZero = v => v > EPSILON || v < -EPSILON;
function needLocalTransform(t) {
  return notAroundZero(t.rotation) || notAroundZero(t.x) || notAroundZero(t.y) || notAroundZero(t.scaleX - 1) || notAroundZero(t.scaleY - 1);
}
function localTransform(t) {
  const m = [];
  const ox = t.originX || 0;
  const oy = t.originY || 0;
  const sx = t.scaleX;
  const sy = t.scaleY;
  const rotation = t.rotation || 0;
  if (ox || oy) {
    m[4] = -ox * sx - 0 * oy * sy;
    m[5] = -oy * sy - 0 * ox * sx;
  } else {
    m[4] = m[5] = 0;
  }
  m[0] = sx;
  m[3] = sy;
  m[1] = 0 * sx;
  m[2] = 0 * sy;
  if (rotation) {
    const aa = m[0]; const ac = m[2]; const atx = m[4]; const ab = m[1]; const ad = m[3]; const aty = m[5];
    const st = Math.sin(rotation);
    const ct = Math.cos(rotation);
    m[0] = aa * ct + ab * st;
    m[1] = -aa * st + ab * ct;
    m[2] = ac * ct + ad * st;
    m[3] = -ac * st + ct * ad;
    m[4] = ct * (atx - 0) + st * (aty - 0) + 0;
    m[5] = ct * (aty - 0) - st * (atx - 0) + 0;
  }
  m[4] += ox + t.x;
  m[5] += oy + t.y;
  return m;
}
const transformOf = t => (needLocalTransform(t) ? localTransform(t) : null);
function mul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1], m1[0] * m2[2] + m1[2] * m2[3],
    m1[1] * m2[2] + m1[3] * m2[3], m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
// Transformable.updateTransform (first render: no previous matrix)
function globalOf(local, parent) {
  if (!(local || parent)) return null;
  if (!parent) return local.slice();
  return local ? mul(parent, local) : parent.slice();
}
function lineScaleOf(m, mut) {
  if (mut.lineScaleUnguarded) return m ? Math.sqrt(Math.abs(m[0] * m[3] - m[2] * m[1])) : 1;
  return m && Math.abs(m[0] - 1) > 1e-10 && Math.abs(m[3] - 1) > 1e-10 ? Math.sqrt(Math.abs(m[0] * m[3] - m[2] * m[1])) : 1;
}
// BoundingRect.applyTransform (BoundingRect.ts:246-292)
function applyTransform(s, m) {
  if (!m) return { x: s.x, y: s.y, width: s.width, height: s.height };
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    const t = { x: s.x * m[0] + m[4], y: s.y * m[3] + m[5], width: s.width * m[0], height: s.height * m[3] };
    if (t.width < 0) { t.x += t.width; t.width = -t.width; }
    if (t.height < 0) { t.y += t.height; t.height = -t.height; }
    return t;
  }
  const pts = [[s.x, s.y], [s.x + s.width, s.y], [s.x + s.width, s.y + s.height], [s.x, s.y + s.height]]
    .map(p => [m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5]]);
  // lt, rt, rb, lb; min / max in upstream's argument order (lt, rb, lb, rt)
  const [lt, rt, rb, lb] = pts;
  const x = Math.min(lt[0], rb[0], lb[0], rt[0]);
  const y = Math.min(lt[1], rb[1], lb[1], rt[1]);
  return { x, y, width: Math.max(lt[0], rb[0], lb[0], rt[0]) - x, height: Math.max(lt[1], rb[1], lb[1], rt[1]) - y };
}

// util/format.ts formatTpl for one params object (String.prototype.replace: FIRST occurrence only)
const TPL_VAR_ALIAS = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
function formatTpl(tpl, params, mut) {
  const $vars = ['seriesName', 'name', 'value'];
  const rep = (s, from, to) => (mut.tplReplaceAll ? s.split(from).join(String(to)) : s.replace(from, to));
  for (let i = 0; i < $vars.length; i++) {
    const alias = TPL_VAR_ALIAS[i];
    tpl = rep(tpl, '{' + alias + '}', '{' + alias + '0}');
  }
  for (let k = 0; k < $vars.length; k++) tpl = rep(tpl, '{' + TPL_VAR_ALIAS[k] + '0}', params[$vars[k]]);
  must(!/\{@(.+?)\}/.test(tpl), 'the transcription does not do {@dim} templates');
  return tpl;
}
// SeriesData.getName via convertOptionIdName (util/model.ts:555-564)
function itemName(item) {
  const n = item && item.name;
  if (n == null) return '';
  return typeof n === 'string' ? n : typeof n === 'number' ? n + '' : '';
}
// zr Text makeFont / parseFontSize (graphic/Text.ts:969-1009), normalizeStyle (1035-1058)
function parseFontSize(fontSize) {
  if (typeof fontSize === 'string' && (fontSize.indexOf('px') !== -1 || fontSize.indexOf('rem') !== -1 || fontSize.indexOf('em') !== -1)) return fontSize;
  if (!isNaN(+fontSize)) return fontSize + 'px';
  return 12 + 'px';
}
function makeFont(s) {
  let font = '';
  if (s.fontSize != null || s.fontFamily || s.fontWeight) {
    font = [s.fontStyle, s.fontWeight, parseFontSize(s.fontSize), s.fontFamily || 'sans-serif'].join(' ');
  }
  return (font && font.trim()) || s.textFont || s.font;
}
function normAlign(a, mut) {
  if (a === 'middle' && !mut.alignNoNormalize) a = 'center';
  return a == null || { left: 1, right: 1, center: 1 }[a] ? a : 'left';
}
function normVAlign(a, mut) {
  if (a === 'center' && !mut.alignNoNormalize) a = 'middle';
  return a == null || { top: 1, bottom: 1, middle: 1 }[a] ? a : 'top';
}
// zrender tool/color lum (color.ts:558-564) over the css parser
function lum(c, backgroundLum) {
  const arr = echarts.color.parse(c);
  return arr ? (0.299 * arr[0] + 0.587 * arr[1] + 0.114 * arr[2]) * arr[3] / 255 + (1 - arr[3]) * backgroundLum : 0;
}
// Element.getOutsideStroke (zr Element.ts:785-799)
function outsideStroke(bg, isDark) {
  let arr = typeof bg === 'string' && echarts.color.parse(bg);
  if (!arr) arr = [255, 255, 255, 1];
  const alpha = arr[3];
  for (let i = 0; i < 3; i++) arr[i] = arr[i] * alpha + (isDark ? 0 : 255) * (1 - alpha);
  arr[3] = 1;
  return echarts.color.stringify(arr, 'rgba');
}
// Path.getInsideTextFill / getInsideTextStroke (zr graphic/Path.ts:266-301)
function insideTextFill(pathFill, mut) {
  if (pathFill !== 'none') {
    if (typeof pathFill === 'string') {
      const fillLum = lum(pathFill, 0);
      if (mut.bandsInclusive ? fillLum >= 0.5 : fillLum > 0.5) return '#333';
      if (mut.bandsInclusive ? fillLum >= 0.2 : fillLum > 0.2) return '#eee';
      return '#ccc';
    } else if (pathFill) {
      return '#ccc';
    }
  }
  return '#333';
}
function insideTextStroke(pathFill, textFill, isDark, mut) {
  if (mut.insideStrokeNever) return undefined;
  if (typeof pathFill === 'string') {
    const isDarkMode = !!isDark;
    const isDarkLabel = lum(textFill, 0) < 0.4;
    if (isDarkMode === isDarkLabel) return pathFill;
  }
  return undefined;
}
// zr contain/text.ts calculateTextPosition (216-327)
function calculateTextPosition(position, distance, rect) {
  const textPosition = position || 'inside';
  distance = distance != null ? distance : 5;
  const height = rect.height;
  const width = rect.width;
  const halfHeight = height / 2;
  let x = rect.x;
  let y = rect.y;
  let textAlign = 'left';
  let textVerticalAlign = 'top';
  if (textPosition instanceof Array) {
    x += zrParsePercent(textPosition[0], rect.width);
    y += zrParsePercent(textPosition[1], rect.height);
    textAlign = null;
    textVerticalAlign = null;
  } else {
    switch (textPosition) {
      case 'left': x -= distance; y += halfHeight; textAlign = 'right'; textVerticalAlign = 'middle'; break;
      case 'right': x += distance + width; y += halfHeight; textVerticalAlign = 'middle'; break;
      case 'top': x += width / 2; y -= distance; textAlign = 'center'; textVerticalAlign = 'bottom'; break;
      case 'bottom': x += width / 2; y += height + distance; textAlign = 'center'; break;
      case 'inside': x += width / 2; y += halfHeight; textAlign = 'center'; textVerticalAlign = 'middle'; break;
      case 'insideLeft': x += distance; y += halfHeight; textVerticalAlign = 'middle'; break;
      case 'insideRight': x += width - distance; y += halfHeight; textAlign = 'right'; textVerticalAlign = 'middle'; break;
      case 'insideTop': x += width / 2; y += distance; textAlign = 'center'; break;
      case 'insideBottom': x += width / 2; y += height - distance; textAlign = 'center'; textVerticalAlign = 'bottom'; break;
      case 'insideTopLeft': x += distance; y += distance; break;
      case 'insideTopRight': x += width - distance; y += distance; textAlign = 'right'; break;
      case 'insideBottomLeft': x += distance; y += height - distance; textVerticalAlign = 'bottom'; break;
      case 'insideBottomRight': x += width - distance; y += height - distance; textAlign = 'right'; textVerticalAlign = 'bottom'; break;
    }
  }
  return { x, y, align: textAlign, verticalAlign: textVerticalAlign };
}
// canvas/dashStyle.ts normalizeLineDash
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : isArray(lineType) ? lineType : null;
}
const ITEM_STYLE_KEYS = [['fill', 'color'], ['stroke', 'borderColor'], ['lineWidth', 'borderWidth'], ['opacity', 'opacity'],
  ['shadowBlur', 'shadowBlur'], ['shadowOffsetX', 'shadowOffsetX'], ['shadowOffsetY', 'shadowOffsetY'], ['shadowColor', 'shadowColor'],
  ['lineDash', 'borderType'], ['lineDashOffset', 'borderDashOffset'], ['lineCap', 'borderCap'], ['lineJoin', 'borderJoin'], ['miterLimit', 'borderMiterLimit']];
const TEXT_PROPS_BOX = ['padding', 'borderWidth', 'borderRadius', 'borderDashOffset', 'backgroundColor', 'borderColor', 'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY'];

// dimensionHelper summarizeDimensions: defaultedLabel = the LAST coord dim whose type may be a label
function labelDimsOf(dims, mut) {
  const out = [];
  for (const d of dims) {
    if (mut.labelDimAlwaysY) { if (d.name === 'y') out[0] = d.name; continue; }
    if (!(d.type === 'ordinal' || d.type === 'time')) {
      if (mut.labelDimFirst && out.length) continue;
      out[0] = d.name;
    }
  }
  return out;
}

// one series' markPoint picture. inp: {own, master, seriesOpt, color, seriesName, textStyle, ground, dims,
// items: [{raw, point}]} -> {z, zlevel, silent, count, dims, labelDims, markers[]}
function transcribe(inp, mut) {
  const own = inp.own;
  const master = inp.master;
  const MP = mut.noSeriesLevel ? [master] : [own, master];
  const z = chainGet(MP, 'z') || 0;
  const zlevel = chainGet(MP, 'zlevel') || 0;
  const gts = inp.textStyle || {};
  const labelDims = labelDimsOf(inp.dims, mut);
  const groupSilent = !!(chainGet(MP, 'silent') || (inp.seriesOpt && inp.seriesOpt.silent));
  let maxZ2 = -Infinity; // util/graphic.ts doUpdateZ, carried across the Symbol groups of the SymbolDraw group
  const markers = inp.items.map(IT => {
    const raw = IT.raw;
    const point = IT.point;
    const lv = [raw].concat(MP);
    const out = { value: val(raw.value), name: val(raw.name), point: [hex(point[0]), hex(point[1])], pointText: [text(point[0]), text(point[1])] };
    // ----- visuals (MarkPointView.ts:135-178) -----
    const v = {
      symbol: chainGet(lv, 'symbol'), symbolSize: chainGet(lv, 'symbolSize'), symbolRotate: chainGet(lv, 'symbolRotate'),
      symbolOffset: chainGet(lv, 'symbolOffset'), symbolKeepAspect: chainGet(lv, 'symbolKeepAspect'),
    };
    const IS = sub(lv, 'itemStyle');
    const style = {};
    for (const [k, o] of ITEM_STYLE_KEYS) {
      if (mut.fillIgnoresItem && k === 'fill') continue;
      const x = chainGet(IS, o);
      if (x != null) style[k] = x;
    }
    if (mut.fillNullCheck ? style.fill == null : !style.fill) style.fill = inp.color;
    const z2 = retrieve2(chainGet(lv, 'z2'), 0);
    out.visual = { symbol: json(v.symbol), symbolSize: json(v.symbolSize), symbolRotate: json(v.symbolRotate),
      symbolOffset: json(v.symbolOffset), symbolKeepAspect: json(v.symbolKeepAspect), fill: colour(style.fill) };
    // ----- SymbolDraw symbolNeedsDraw (SymbolDraw.ts:51-59) -----
    const drawn = !isNaN(point[0]) && !isNaN(point[1]) && v.symbol !== 'none' && !(mut.emptyStringNone && v.symbol === '');
    out.drawn = drawn;
    if (!drawn) {
      out.symbol = out.label = null;
      return out;
    }
    // ----- Symbol._createSymbol / _updateCommon (Symbol.ts:63-96, 155-358) -----
    const type = v.symbol || 'circle';
    must(typeof type === 'string' && type.indexOf('image://') !== 0 && type.indexOf('path://') !== 0, 'the transcription draws no image / path symbols');
    let size = normalizeSymbolSize(v.symbolSize);
    if (mut.sizeFirstOnly) size = [size[0], size[0]];
    if (mut.keepAspectUniform && v.symbolKeepAspect) size = [Math.min(size[0], size[1]), Math.min(size[0], size[1])];
    const isEmpty = type.indexOf('empty') === 0;
    const shapeType = isEmpty ? type.substr(5, 1).toLowerCase() + type.substr(6) : type;
    const box = mut.pinInBox ? { x: -size[0] / 2, y: -size[1] / 2, width: size[0], height: size[1] } : { x: -1, y: -1, width: 2, height: 2 };
    const t = { x: 0, y: 0, rotation: 0, scaleX: mut.pinInBox ? 1 : size[0] / 2, scaleY: mut.pinInBox ? 1 : size[1] / 2, originX: 0, originY: 0 };
    const rot = v.symbolRotate;
    t.rotation = mut.rotateNaNKept ? (rot || 0) * Math.PI / 180 : (rot || 0) * Math.PI / 180 || 0;
    if (mut.rotateNegated) t.rotation = -t.rotation;
    const off = normalizeSymbolOffset(v.symbolOffset, size, mut);
    if (off && !mut.noOffset) {
      t.x = mut.offsetScaled ? off[0] * t.scaleX : off[0];
      t.y = mut.offsetScaled ? off[1] * t.scaleY : off[1];
    }
    // useStyle (a new object over DEFAULT_PATH_STYLE: fill '#000', lineWidth 1 ...) + setColor (util/symbol.ts:311-328)
    const st = Object.assign({ fill: '#000', stroke: null, lineWidth: 1, opacity: 1, lineDash: null, lineDashOffset: 0 }, style);
    const visualColor = style.fill;
    if (isEmpty) {
      st.stroke = visualColor;
      st.fill = mut.emptyFilled ? visualColor : NEUTRAL00;
      if (!mut.emptyKeepsWidth) st.lineWidth = 2;
    } else if (shapeType === 'line' && !mut.lineNotStroked) {
      st.stroke = visualColor;
    } else {
      st.fill = visualColor;
    }
    // transforms: the Symbol group at the point (scale 1), the path inside it
    const g = { x: point[0], y: point[1], rotation: 0, scaleX: 1, scaleY: 1, originX: 0, originY: 0 };
    const gT = transformOf(g);
    const local = transformOf(t);
    const global = globalOf(local, gT);
    const pdata = symbolPath(shapeType, box.x, box.y, box.width, box.height, mut);
    const bbox = pathBBox(pdata);
    const lineScale = lineScaleOf(global, mut);
    const hasStroke = !(st.stroke == null || st.stroke === 'none' || !(st.lineWidth > 0));
    const hasFill = st.fill != null && st.fill !== 'none';
    // Path.getBoundingRect (Path.ts:339-392): the stroke grows the rect (strokeNoScale: / lineScale)
    let rectLocal = bbox;
    if (hasStroke && pdata.length > 0 && !mut.rectNoStroke) {
      rectLocal = Object.assign({}, bbox);
      let w = st.lineWidth;
      if (!hasFill && !mut.noFillThreshold) w = Math.max(w, 5);
      if (lineScale > 1e-10) {
        rectLocal.width += w / lineScale;
        rectLocal.height += w / lineScale;
        rectLocal.x -= w / lineScale / 2;
        rectLocal.y -= w / lineScale / 2;
      }
    }
    // painted stroke (svg/mapStyleToAttrs.ts:60-95, canvas/dashStyle getLineDash)
    const paintStroke = st.stroke != null && st.stroke !== 'none';
    let paintWidth = null;
    let paintDash = null;
    if (paintStroke) {
      paintWidth = lineScale ? (st.lineWidth || 0) / lineScale : 0;
      let d = st.lineDash && st.lineWidth > 0 && normalizeLineDash(st.lineDash, st.lineWidth);
      if (d && lineScale && lineScale !== 1) d = d.map(x => x / lineScale);
      paintDash = d || null;
    }
    maxZ2 = Math.max(z2 || 0, maxZ2);
    if (mut.z2PerMarker) maxZ2 = z2 || 0;
    out.symbol = Object.assign({ symbol: v.symbol, shapeType, empty: isEmpty },
      rectRec(box, 'shape'),
      { group: Object.assign(nums(g, ['x', 'y']), m6(gT)) },
      nums(t, ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY']), m6(local, 'local'), m6(global),
      { path: decode(pdata) }, rectRec(bbox, 'bbox'), { lineScale: hex(lineScale), lineScaleText: text(lineScale) },
      { style: { fill: colour(st.fill), stroke: colour(st.stroke), lineWidth: hex(st.lineWidth), lineWidthText: text(st.lineWidth),
        opacity: hex(st.opacity), opacityText: text(st.opacity), lineDash: json(st.lineDash),
        lineDashOffset: hex(st.lineDashOffset), lineDashOffsetText: text(st.lineDashOffset), strokeNoScale: true } },
      { paint: { stroke: paintStroke, strokeWidth: hexOrNull(paintWidth), strokeWidthText: textOrNull(paintWidth),
        dash: paintDash ? paintDash.map(hex) : null, dashText: paintDash ? paintDash.map(text) : null } },
      { z, z2, zlevel, silent: groupSilent });
    // ----- the label (Symbol.ts:315-331, labelStyle.ts, zr Element.updateInnerText, Text) -----
    const LB = sub(lv, 'label');
    const show = chainGet(LB, 'show');
    if (!show || (mut.size0HidesLabel && (!size[0] || !size[1]))) {
      out.label = null;
      return out;
    }
    const inheritColor = visualColor;
    // text: getFormattedLabel (formatter via the label chain), else getDefaultLabel
    const formatter = chainGet(LB, 'formatter');
    let str;
    if (typeof formatter === 'string') {
      str = formatTpl(formatter, { seriesName: inp.seriesName, name: itemName(raw), value: raw.value }, mut);
    } else {
      must(formatter == null, 'the transcription does not call formatter functions');
      if (!labelDims.length) str = null; // getDefaultLabel returns undefined
      else {
        const dim = labelDims[0];
        const dimIndex = inp.dims.findIndex(d => d.name === dim);
        let rv;
        if (mut.textFromCoord) rv = raw.coord ? raw.coord[dimIndex] : undefined;
        else rv = isArray(raw.value) ? raw.value[dimIndex] : raw.value;
        if (mut.textRounded && typeof rv === 'number') rv = +rv.toFixed(10);
        str = rv != null ? rv + '' : null;
      }
    }
    // createTextStyle(normal, isAttached = true): setTextStyleCommon + setTokenTextStyle
    const ts = {};
    let fc = chainGet(LB, 'color');
    let sc = chainGet(LB, 'textBorderColor');
    let opacity = retrieve2(chainGet(LB, 'opacity'), gts.opacity);
    if (fc === 'inherit' || fc === 'auto') fc = inheritColor || null;
    if (sc === 'inherit' || sc === 'auto') sc = inheritColor || null;
    if (fc != null) ts.fill = fc;
    if (sc != null) ts.stroke = sc;
    const tbw = retrieve2(chainGet(LB, 'textBorderWidth'), gts.textBorderWidth);
    if (tbw != null) ts.lineWidth = tbw;
    if (opacity == null && !mut.labelOpacityOwn) opacity = style.opacity; // defaultOpacity: symbolStyle.opacity
    if (opacity != null) ts.opacity = opacity;
    for (const k of ['fontStyle', 'fontWeight', 'fontSize', 'fontFamily']) {
      const x = mut.noGlobalFont ? chainGet(LB, k) : retrieve2(chainGet(LB, k), gts[k]);
      if (x != null) ts[k] = x;
    }
    let rawAlign = chainGet(LB, 'align');
    let rawVAlign = chainGet(LB, 'verticalAlign');
    if (rawVAlign == null) rawVAlign = chainGet(LB, 'baseline');
    for (const k of TEXT_PROPS_BOX) {
      const x = chainGet(LB, k);
      if (x != null) ts[k] = x;
    }
    if ((ts.backgroundColor === 'auto' || ts.backgroundColor === 'inherit') && inheritColor) ts.backgroundColor = inheritColor;
    let rich = false;
    for (const o of LB) if (o && typeof o === 'object' && o.rich) rich = true;
    if (mut.userAlignIgnored) rawAlign = rawVAlign = null;
    const authorAlign = normAlign(rawAlign, mut);
    const authorVAlign = normVAlign(rawVAlign, mut);
    // createTextConfig (labelStyle.ts:340-383)
    let position = chainGet(LB, 'position') || 'inside';
    if (position === 'outside' && !mut.outsideNotTop) position = 'top';
    if (mut.unknownInside && typeof position === 'string' && !(position in POSITIONS)) position = 'inside';
    const distance = mut.distanceIgnored ? 5 : retrieve2(chainGet(LB, 'distance'), 5);
    const labelOffset = chainGet(LB, 'offset');
    let labelRotate = chainGet(LB, 'rotate');
    if (labelRotate != null) labelRotate *= Math.PI / 180;
    const outsideFill = chainGet(LB, 'color') === 'inherit' ? (inheritColor || null) : 'auto';
    // updateInnerText: the rect = the path's bounding rect in GLOBAL coordinates
    const rect = mut.rectNoOffset ? applyTransform(rectLocal, globalOf(transformOf(Object.assign({}, t, { x: 0, y: 0 })), gT)) : applyTransform(rectLocal, global);
    const calc = calculateTextPosition(position, distance, rect);
    if (mut.arrayAlignLeft && calc.align == null) { calc.align = 'left'; calc.verticalAlign = 'top'; }
    // SymbolClz.calculateTextPosition (util/symbol.ts:284-291): the pin's label sits at 0.4 of the rect height
    const pinRule = mut.pinRuleAnyInside ? (typeof position === 'string' && position.indexOf('inside') === 0) : position === 'inside';
    if (shapeType === 'pin' && pinRule && !mut.pinRuleOff) calc.y = rect.y + rect.height * 0.4;
    const inner = { x: calc.x, y: calc.y, rotation: 0, originX: 0, originY: 0, scaleX: 1, scaleY: 1 };
    if (labelRotate != null && !mut.noLabelRotate) inner.rotation = labelRotate;
    if (labelOffset) {
      inner.x += labelOffset[0];
      inner.y += labelOffset[1];
      if (!mut.offsetKeepsOrigin) { inner.originX = -labelOffset[0]; inner.originY = -labelOffset[1]; }
    }
    // the ink (Element.ts:697-735)
    const isInside = !mut.insideAsOutside && typeof position === 'string' && position.indexOf('inside') >= 0 && hasFill;
    let defFill;
    let defStroke;
    const isDark = inp.ground.isDark && !mut.darkIgnored;
    if (isInside) {
      defFill = insideTextFill(st.fill, mut);
      defStroke = insideTextStroke(st.fill, defFill, isDark, mut);
    } else {
      defFill = outsideFill;
      if (defFill == null || defFill === 'auto') defFill = isDark ? '#ccc' : '#333';
      defStroke = outsideStroke(inp.ground.background, isDark);
    }
    defFill = defFill || '#000';
    const textStr = str == null ? '' : String(str);
    let lines = null;
    let ink = null;
    if (!rich) {
      lines = textStr === '' ? 0 : textStr.split('\n').length;
      if (textStr !== '') {
        const useDefaultFill = !('fill' in ts);
        const tf = useDefaultFill ? defFill : ts.fill;
        const bgDrawn = !!ts.backgroundColor && !mut.bgAutoStroke;
        let dlw = 0;
        let tsk;
        if ('stroke' in ts) tsk = ts.stroke;
        else if (!bgDrawn && (!/* autoStroke */ true || useDefaultFill)) { dlw = 2; tsk = defStroke; } else tsk = null;
        const fillP = tf == null || tf === 'none' ? null : tf;
        const strokeP = tsk == null || tsk === 'transparent' || tsk === 'none' ? null : tsk;
        const lwP = strokeP ? (ts.lineWidth || dlw) : null;
        const op = retrieve2(ts.opacity, 1);
        ink = { fill: colour(fillP), stroke: colour(strokeP), lineWidth: hexOrNull(lwP), lineWidthText: textOrNull(lwP), opacity: hex(op), opacityText: text(op) };
      }
    }
    const labelZ2 = isFinite(maxZ2) ? maxZ2 + 2 : 0;
    const stOpacity = retrieve2(ts.opacity, 1);
    const lp = { x: 0, y: 0, rotation: 0, originX: 0, originY: 0, scaleX: 1, scaleY: 1 };
    out.label = Object.assign({ text: str == null ? null : String(str), rich, lines, position: json(position),
      distance: hex(distance), distanceText: text(distance) }, rectRec(rect, 'rect'),
    nums(lp, ['x', 'y', 'rotation', 'originX', 'originY', 'scaleX', 'scaleY']),
    { inner: nums(inner, ['x', 'y', 'rotation', 'originX', 'originY']) }, m6(transformOf(inner)),
    { align: authorAlign || calc.align || 'left', verticalAlign: authorVAlign || calc.verticalAlign || 'top',
      authorAlign: authorAlign == null ? null : authorAlign, authorVerticalAlign: authorVAlign == null ? null : authorVAlign,
      inside: isInside,
      font: makeFont(ts), fontSize: json(ts.fontSize), fontWeight: json(ts.fontWeight), fontStyle: json(ts.fontStyle), fontFamily: json(ts.fontFamily),
      style: { fill: colour(ts.fill), stroke: colour(ts.stroke), lineWidth: hexOrNull(ts.lineWidth), lineWidthText: textOrNull(ts.lineWidth),
        opacity: hex(stOpacity), opacityText: text(stOpacity), backgroundColor: json(ts.backgroundColor) },
      inkDefault: { fill: defFill, stroke: defStroke == null ? null : defStroke, autoStroke: true,
        align: calc.align == null ? null : calc.align, verticalAlign: calc.verticalAlign == null ? null : calc.verticalAlign }, ink,
      z, z2: labelZ2, zlevel, silent: !!chainGet(LB, 'silent') });
    return out;
  });
  return { z: json(z), zlevel: json(zlevel), silent: groupSilent, count: inp.items.length,
    dims: inp.dims.map(d => ({ name: d.name, type: d.type })), labelDims, markers };
}
const POSITIONS = { left: 1, right: 1, top: 1, bottom: 1, inside: 1, insideLeft: 1, insideRight: 1, insideTop: 1, insideBottom: 1,
  insideTopLeft: 1, insideTopRight: 1, insideBottomLeft: 1, insideBottomRight: 1 };

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const firstOf = v => (isArray(v) ? v[0] : v);
function slaveOf(ec, sm) {
  const master = ec.getComponent('markPoint');
  if (!master) return null;
  const MM = Object.getPrototypeOf(master.constructor);
  must(typeof MM.getMarkerModelFromSeries === 'function', 'MarkerModel.getMarkerModelFromSeries not reachable');
  return MM.getMarkerModelFromSeries(sm, 'markPoint') || null;
}
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  must(Array.isArray(el.path.data), 'a path proxy was made static');
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};

// the symbol <path> elements of the SVG: [{si, di, m (6 numbers or null), stroke, width, dash}]
function svgSymbolPaths(svg) {
  const out = [];
  const re = /<path\b([^>]*)>/g;
  let mm;
  while ((mm = re.exec(svg))) {
    const a = mm[1];
    const g = n => { const r = new RegExp('(?:^|\\s)' + n + '="([^"]*)"').exec(a); return r ? r[1] : null; };
    const si = g('ecmeta_series_index');
    const di = g('ecmeta_data_index');
    if (si == null || di == null) continue;
    const tr = g('transform');
    let m = null;
    if (tr) {
      let r = /^matrix\(([^)]*)\)$/.exec(tr);
      if (r) m = r[1].split(',').map(Number);
      else {
        r = /^translate\(([^ ]*) ([^)]*)\)$/.exec(tr);
        must(r, 'an SVG transform ' + tr);
        m = [1, 0, 0, 1, +r[1], +r[2]];
      }
    }
    const stroke = g('stroke');
    out.push({ si: +si, di: +di, m, stroke: stroke != null && stroke !== 'none', width: g('stroke-width'), dash: g('stroke-dasharray') });
  }
  return out;
}
function svgMatch(p, m) {
  if (!m) return p.m == null;
  if (p.m == null) return false;
  return [0, 1, 2, 3].every(k => Math.abs(p.m[k] - m[k]) <= 5e-4 + 1e-9) && [4, 5].every(k => Math.abs(p.m[k] - m[k]) <= 5e-5 + 1e-9);
}

function readSymbol(g, el, vis, svgPaths, si, di) {
  const s = el.style;
  const sh = el.shape;
  const bb = el.path.getBoundingRect();
  const cands = svgPaths.filter(p => p.si === si && p.di === di && svgMatch(p, el.transform));
  must(cands.length >= 1, 'no SVG <path> for marker ' + di + ' of series ' + si);
  must(cands.every(c => c.stroke === cands[0].stroke && c.width === cands[0].width && c.dash === cands[0].dash), 'ambiguous SVG <path> for marker ' + di);
  const c = cands[0];
  const pw = c.stroke ? (c.width == null ? 1 : +c.width) : null;
  const pd = c.stroke && c.dash != null ? c.dash.split(',').map(Number) : null;
  const local = el.needLocalTransform() ? el.getLocalTransform([]) : null;
  const ls = el.getLineScale();
  return Object.assign({ symbol: vis, shapeType: sh.symbolType, empty: !!el.__isEmptyBrush },
    rectRec(sh, 'shape'),
    { group: Object.assign(nums(g, ['x', 'y']), m6(g.transform)) },
    nums(el, ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY']), m6(local, 'local'), m6(el.transform),
    { path: decode(pathOf(el)) }, rectRec(bb, 'bbox'), { lineScale: hex(ls), lineScaleText: text(ls) },
    { style: { fill: colour(s.fill), stroke: colour(s.stroke), lineWidth: hex(s.lineWidth), lineWidthText: text(s.lineWidth),
      opacity: hex(s.opacity), opacityText: text(s.opacity), lineDash: json(s.lineDash),
      lineDashOffset: hex(s.lineDashOffset), lineDashOffsetText: text(s.lineDashOffset), strokeNoScale: !!s.strokeNoScale } },
    { paint: { stroke: c.stroke, strokeWidth: hexOrNull(pw), strokeWidthText: textOrNull(pw), dash: pd ? pd.map(hex) : null, dashText: pd ? pd.map(text) : null } },
    { z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.isSilent() });
}
function readLabel(el) {
  const t = el.getTextContent();
  if (!t || t.ignore) return null;
  const s = t.style;
  const rich = !!s.rich;
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  const txt = s.text == null ? null : String(s.text);
  let ink = null;
  let lines = null;
  if (!rich) {
    must(kids.every(k => k.type === 'tspan' || (k.type === 'rect' && s.backgroundColor)), 'a plain label with children ' + kids.map(k => k.type).join());
    lines = spans.length;
    must((spans.length >= 1) === (txt != null && txt !== ''), 'a label TSpan / text mismatch');
    if (spans.length) {
      const inks = spans.map(sp => {
        const ss = sp.style;
        must(ss.font === s.font, 'the TSpan font differs from the label font');
        const lw = ss.stroke ? ss.lineWidth : null;
        return { fill: colour(ss.fill), stroke: colour(ss.stroke || null), lineWidth: hexOrNull(lw), lineWidthText: textOrNull(lw), opacity: hex(ss.opacity), opacityText: text(ss.opacity) };
      });
      must(inks.every(k => JSON.stringify(k) === JSON.stringify(inks[0])), 'TSpans with different inks');
      ink = inks[0];
    }
  }
  const it = t.innerTransformable;
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  const tc = el.textConfig;
  // the rect updateInnerText placed the label against (Element.ts:606-620): upstream's own methods
  const rect = el.getBoundingRect().clone();
  rect.applyTransform(el.transform);
  const position = tc.position;
  const inside = typeof position === 'string' && position.indexOf('inside') >= 0 && el.hasFill();
  return Object.assign({ text: txt, rich, lines, position: json(position), distance: hex(tc.distance), distanceText: text(tc.distance) },
    rectRec(rect, 'rect'),
    nums(t, ['x', 'y', 'rotation', 'originX', 'originY', 'scaleX', 'scaleY']),
    { inner: nums(it, ['x', 'y', 'rotation', 'originX', 'originY']) }, m6(t.transform),
    { align: s.align || ds.align || 'left', verticalAlign: s.verticalAlign || ds.verticalAlign || 'top',
      authorAlign: s.align == null ? null : s.align, authorVerticalAlign: s.verticalAlign == null ? null : s.verticalAlign,
      inside,
      font: s.font, fontSize: json(s.fontSize), fontWeight: json(s.fontWeight), fontStyle: json(s.fontStyle), fontFamily: json(s.fontFamily),
      style: { fill: has('fill') ? colour(s.fill) : null, stroke: has('stroke') ? colour(s.stroke) : null,
        lineWidth: has('lineWidth') ? hexOrNull(s.lineWidth) : null, lineWidthText: has('lineWidth') ? textOrNull(s.lineWidth) : null,
        opacity: hex(s.opacity), opacityText: text(s.opacity), backgroundColor: json(s.backgroundColor) },
      inkDefault: { fill: ds.fill, stroke: ds.stroke == null ? null : ds.stroke, autoStroke: ds.autoStroke,
        align: ds.align == null ? null : ds.align, verticalAlign: ds.verticalAlign == null ? null : ds.verticalAlign }, ink,
      z: t.z, z2: t.z2, zlevel: t.zlevel, silent: !!t.silent });
}

// every marker of one series: {block, rows, tags, inputs}
function readSeries(chart, sm, svgPaths) {
  const ec = chart.getModel();
  const slave = slaveOf(ec, sm);
  must(slave, 'no slave markPoint model for series ' + sm.seriesIndex);
  const data = slave.getData();
  const view = chart.getViewOfComponentModel(ec.getComponent('markPoint'));
  const draw = view.markerGroupMap.get(sm.id);
  must(draw && draw.group, 'no markPoint group for series ' + sm.seriesIndex);
  const group = draw.group;
  for (let p = group; p; p = p.parent) must(!p.transform || p.transform.join() === '1,0,0,1,0,0', 'a transformed ancestor');
  const dims = data.dimensions.map(d => ({ name: d, type: data.getDimensionInfo(d).type }));
  const rows = [];
  const tags = [];
  const inputs = [];
  const drawnGroups = [];
  for (let i = 0; i < data.count(); i++) {
    const raw = data.getRawDataItem(i);
    tags.push(raw[TAG]);
    const point = data.getItemLayout(i);
    inputs.push({ raw: zrClone(raw), point: point.slice() });
    const vs = data.getItemVisual(i, 'style');
    const row = { value: val(raw.value), name: val(raw.name), point: [hex(point[0]), hex(point[1])], pointText: [text(point[0]), text(point[1])],
      visual: { symbol: json(data.getItemVisual(i, 'symbol')), symbolSize: json(data.getItemVisual(i, 'symbolSize')),
        symbolRotate: json(data.getItemVisual(i, 'symbolRotate')), symbolOffset: json(data.getItemVisual(i, 'symbolOffset')),
        symbolKeepAspect: json(data.getItemVisual(i, 'symbolKeepAspect')), fill: colour(vs.fill) } };
    const g = data.getItemGraphicEl(i);
    row.drawn = !!g;
    must(row.drawn === (!isNaN(point[0]) && !isNaN(point[1]) && data.getItemVisual(i, 'symbol') !== 'none'), 'drawn vs point / symbol at marker ' + i);
    if (!g) {
      row.symbol = row.label = null;
      rows.push(row);
      continue;
    }
    drawnGroups.push(g);
    must(g.x === point[0] && g.y === point[1] && g.rotation === 0 && g.scaleX === 1 && g.scaleY === 1 && !g.silent, 'the Symbol group is not at the point');
    const kids = g.childrenRef();
    must(kids.length === 1 && kids[0].shape && typeof kids[0].shape.symbolType === 'string', 'the Symbol group children');
    const el = kids[0];
    must(el.z2 === retrieve2(data.getItemVisual(i, 'z2'), 100), 'the symbol z2 is not the visual z2');
    row.symbol = readSymbol(g, el, json(data.getItemVisual(i, 'symbol')), svgPaths, sm.seriesIndex, i);
    row.label = readLabel(el);
    // the label placement is calculateTextPosition on the recorded rect (+ the pin rule, rotate, offset)
    if (row.label) {
      const t = el.getTextContent();
      const tc = el.textConfig;
      const r = el.getBoundingRect().clone();
      r.applyTransform(el.transform);
      const c = calculateTextPosition(tc.position, tc.distance, r);
      if (el.shape.symbolType === 'pin' && tc.position === 'inside') c.y = r.y + r.height * 0.4;
      const off = tc.offset || [0, 0];
      must(t.innerTransformable.x === c.x + off[0] && t.innerTransformable.y === c.y + off[1], 'the label placement is not calculateTextPosition on the rect at marker ' + i);
    }
    rows.push(row);
  }
  must(group.childrenRef().length === drawnGroups.length && group.childrenRef().every((c, k) => c === drawnGroups[k]), 'the SymbolDraw group children are not the drawn markers in order');
  const block = { z: json(slave.get('z') || 0), zlevel: json(slave.get('zlevel') || 0), silent: !!group.silent, count: data.count(),
    dims, labelDims: data.mapDimensionsAll('defaultedLabel').slice() };
  return { block, rows, tags, inputs };
}

function runChart(option, fn) {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(option);
    chart.getZr().storage.getDisplayList(true);
    const svg = chart.renderToSVGString();
    return fn(chart, svg);
  } finally {
    chart.dispose();
  }
}

function tagOption(option) {
  for (const s of seriesArray(option)) {
    const d = s && s.markPoint && s.markPoint.data;
    if (!isArray(d)) continue;
    d.forEach((el, i) => { if (isObject(el)) el[TAG] = i; });
  }
  return option;
}
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const pointed = option => seriesArray(option).map((s, i) => (s && s.markPoint && s.markPoint.data ? i : -1)).filter(i => i >= 0);

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  const input = JSON.parse(optionText);
  const masterOpt = zrMerge(zrClone(firstOf(input.markPoint) || {}), MP_DEFAULTS);
  const marked = pointed(input);
  must(marked.length, def.id + ': no series with markPoint');
  const base = runChart(JSON.parse(optionText), (chart, svg) => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const svgPaths = svgSymbolPaths(svg);
    const series = marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      const data = sm.getData();
      const filtered = ec.isSeriesFiltered(sm);
      const c = data.getVisual('style')[data.getVisual('drawType')];
      const opt = seriesArray(input)[si];
      const sr = { seriesIndex: si, name: opt.name == null ? null : String(opt.name), type: sm.subType, filtered,
        color: typeof c === 'string' ? c : null, seriesName: opt.name == null ? null : sm.name, markPoint: null };
      if (filtered) return sr;
      const r = readSeries(chart, sm, svgPaths);
      const inp = { own: opt.markPoint, master: masterOpt, seriesOpt: opt, color: sr.color, seriesName: sr.seriesName,
        textStyle: ec.option.textStyle, ground, dims: r.block.dims, items: r.inputs };
      const key = def.id + '/' + si;
      const run = mut => {
        try {
          return transcribe(zrClone(inp), mut);
        } catch (e) {
          if (e instanceof OracleError) throw e;
          return { threw: String(e.stack) };
        }
      };
      side[key] = { base: run({}), muts: {} };
      for (const gd of GUARDS) side[key].muts[gd.id] = run(gd.mut);
      sr.markPoint = r;
      return sr;
    });
    return { ground, textStyle, series };
  });

  const tagged = runChart(tagOption(JSON.parse(optionText)), (chart, svg) => {
    const ec = chart.getModel();
    const svgPaths = svgSymbolPaths(svg);
    return marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      return ec.isSeriesFiltered(sm) ? null : readSeries(chart, sm, svgPaths);
    });
  });

  const rec = { id: def.id, note: def.note, width: W, height: H, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    nan: !!def.nan, ground: base.ground, textStyle: base.textStyle, series: [] };
  rec.series = base.series.map((sr, n) => {
    const b = sr.markPoint;
    if (!b) return sr;
    const t = tagged[n];
    must(t && JSON.stringify(t.rows) === JSON.stringify(b.rows) && JSON.stringify(t.block) === JSON.stringify(b.block),
      def.id + '/' + sr.seriesIndex + ': the tagged run differs from the verbatim run');
    const nIn = seriesArray(input)[sr.seriesIndex].markPoint.data.length;
    for (let j = 0; j < t.tags.length; j++) {
      must(Number.isInteger(t.tags[j]) && t.tags[j] >= 0 && t.tags[j] < nIn && (j === 0 || t.tags[j] > t.tags[j - 1]),
        def.id + '/' + sr.seriesIndex + ': tags ' + JSON.stringify(t.tags));
    }
    const items = [];
    for (let i = 0; i < nIn; i++) {
      const j = t.tags.indexOf(i);
      items.push(Object.assign({ index: i, survived: j >= 0, dataIndex: j >= 0 ? j : null }, j >= 0 ? b.rows[j] : {}));
    }
    return Object.assign({}, sr, { markPoint: Object.assign({}, b.block, { items }) });
  });
  return rec;
}

// ============================================================================
// The cases
// ============================================================================
const G = { left: 80.5, right: 60.25, top: 50.75, bottom: 70.4 };
const PTS = [[1, 2], [3, 7], [5, 4], [8, 9]];
const WEEK = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const D7 = [120, 132, 101, 134, 90, 230, 210];
const OHLC = [[20, 34, 10, 38], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42], [15, 27, 12, 29], [27, 40, 25, 47]];
// value x value grid 0..10 x 0..10 with a fractional rect (x = 80.5 + 65.925 v, y = 529.6 - 47.885 v); scatter symbols
// 7 px so that no marker path coincides with a series symbol in the SVG match
const vv = (markPoint, extra, seriesExtra) => Object.assign({ animation: false, grid: G, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [Object.assign({ type: 'scatter', name: 's0', symbolSize: 7, data: PTS, markPoint }, seriesExtra || {})] }, extra || {});
const cat = (series, extra) => Object.assign({ animation: false, grid: G, xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'value' }, series }, extra || {});
// n items on a 4-column lattice of coords, each extended by extras[i]
const lattice = (extras, cols) => extras.map((e, i) => Object.assign({ coord: [1.2 + (i % (cols || 4)) * (8.4 / ((cols || 4) - 1)), 8.5 - Math.floor(i / (cols || 4)) * 2.4], value: i + 1 }, e));
const POS13 = ['top', 'bottom', 'left', 'right', 'inside', 'insideLeft', 'insideRight', 'insideTop', 'insideBottom', 'insideTopLeft', 'insideTopRight', 'insideBottomLeft', 'insideBottomRight'];
const BAND_FILLS = ['#ffffff', '#04c26d', '#808080', '#033992', '#333333', '#000000', 'rgba(255,255,255,0.3)', '#5070dd', '#eb5454', 'transparent'];

const CASES = [
  // ----- defaults on each series kind -----
  { id: 'D1', note: "defaults on a category line: pin, symbolSize 50 -> the UNIT pin (box -1,-1,2,2) scaled 25 x 25 at the point (the cusp on the datum, the head above); min / max / average / median items (value = the datum the statistic landed on); label 'inside' -> the pin rule y = rect.y + rect.height * 0.4 (= point - 26.142857...); default text = the value; series colour #5070dd (lum 0.45) -> inside ink '#eee' with stroke = the fill (light mode, light label); z 5, glyph z2 0, label z2 2",
    option: cat([{ type: 'line', name: 'L', data: D7, markPoint: { data: [{ type: 'max' }, { type: 'min' }, { type: 'average' }, { type: 'median' }] } }]) },
  { id: 'D2', note: "two bar series per band: markPoints at the bar centres of each series (M1 layout); series 1 palette #b6d634 (lum 0.73 -> ink '#333', NO stroke: dark label in light mode), series 0 #5070dd; an {xAxis, yAxis, value} item prints its VALUE (182.2), not the coord (183); a coord item without value has NO text",
    option: cat([{ type: 'bar', name: 'A', data: [5, 20, 36, 10, 10, 20, 18], markPoint: { data: [{ type: 'max' }, { type: 'min' }] } },
      { type: 'bar', name: 'B', data: [15, 25, 16, 30, 12, 8, 22], markPoint: { data: [{ type: 'max' }, { xAxis: 5, yAxis: 18.3, value: 182.2 }, { coord: ['Wed', 10] }] } }]) },
  { id: 'D3', note: "scatter on two value axes: statistics, a coord item whose value is an ARRAY [3, 8] -> the default text reads value[dimIndex of the label dim] = value[1] = '8' (labelDims = [y]: the LAST non-ordinal / time dim); a coord item without value -> no text; a numeric-string value '075.50' is printed as held",
    option: vv({ data: [{ type: 'max' }, { type: 'min' }, { type: 'average' }, { coord: [5, 5], value: [3, 8] }, { coord: [2, 8] }, { coord: [7, 2], value: '075.50' }] }) },
  { id: 'D4', note: "candlestick: the series colour is its DEFAULT itemStyle.color '#eb5454' (lum 0.5066 > 0.5 -> inside ink '#333', no stroke); valueDim items; a bar beside it on the palette",
    option: { animation: false, grid: G, xAxis: { type: 'category', data: WEEK.slice(0, 6) }, yAxis: { type: 'value' },
      series: [{ type: 'candlestick', name: 'K', data: OHLC, markPoint: { data: [{ type: 'max', valueDim: 'highest' }, { type: 'min', valueDim: 'lowest' }, { type: 'average', valueDim: 'close' }] } },
        { type: 'bar', name: 'V', data: [5, 20, 36, 10, 10, 20], markPoint: { data: [{ type: 'max' }] } }] } },
  { id: 'D5', note: "horizontal bars (category y, value x): labelDims = [x] (y is ordinal), so a value array [1, 2] prints value[0] = '1'; max / min print the datum",
    option: { animation: false, grid: G, yAxis: { type: 'category', data: WEEK.slice(0, 5) }, xAxis: { type: 'value' },
      series: [{ type: 'bar', name: 'H', data: [15, 25, 16, 30, 12], markPoint: { data: [{ type: 'max' }, { type: 'min' }, { coord: [20, 'Wed'], value: [1, 2] }] } }] } },
  { id: 'D6', note: "a time x axis: labelDims = [y] ('time' is skipped like 'ordinal'); max / min on the value",
    option: { animation: false, grid: G, xAxis: { type: 'time' }, yAxis: { type: 'value' },
      series: [{ type: 'line', name: 'T', data: [[Date.UTC(2024, 0, 1), 5], [Date.UTC(2024, 0, 2), 9], [Date.UTC(2024, 0, 3), 4], [Date.UTC(2024, 0, 4), 7]], markPoint: { data: [{ type: 'max' }, { type: 'min' }] } }] } },
  { id: 'D7', note: "a scatter on a category x AND a category y axis: labelDims = [] (both ordinal) -> getDefaultLabel returns undefined: NO default text even with a value; a formatter still prints",
    option: { animation: false, grid: G, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['p', 'q', 'r'] },
      series: [{ type: 'scatter', name: 'CC', symbolSize: 7, data: [['a', 'p'], ['b', 'q'], ['c', 'r']], markPoint: { data: [{ coord: ['b', 'q'], value: 5 }, { coord: ['c', 'p'], value: 6, label: { formatter: 'v={c}' } }] } }] } },
  // ----- symbols -----
  { id: 'Y1', note: "every symbol type at size 30 (scale 15): circle, rect, roundRect (r = min/4 = 0.5 in the unit box, four arcs), square, triangle, diamond, pin, arrow (tip at the point, body BELOW), line (fill AND stroke = the colour, lineWidth 2: the rect grows by 2/lineScale), 'star' (unknown: built as rect, shapeType 'star'), '' (falsy: drawn as 'circle', symbol visual stays ''); inside labels centred (pin: 0.4)",
    option: vv({ symbolSize: 30, data: lattice([{ symbol: 'circle' }, { symbol: 'rect' }, { symbol: 'roundRect' }, { symbol: 'square' }, { symbol: 'triangle' }, { symbol: 'diamond' },
      { symbol: 'pin' }, { symbol: 'arrow' }, { symbol: 'line' }, { symbol: 'star' }, { symbol: '' }]) }) },
  { id: 'Y2', note: "empty symbols: stroke = the fill colour, fill '#fff', lineWidth 2 even with itemStyle.borderWidth 5 / borderColor '#000' (setColor overrides both); emptyPin keeps the pin rule (shape.symbolType 'pin'); inside ink of '#fff' = '#333' without stroke; 'top' labels sit above the stroke-grown rect",
    option: vv({ symbolSize: 26, data: lattice([{ symbol: 'emptyCircle' }, { symbol: 'emptyRect' }, { symbol: 'emptyRoundRect' }, { symbol: 'emptyTriangle' }, { symbol: 'emptyDiamond' },
      { symbol: 'emptyPin' }, { symbol: 'emptyArrow' }, { symbol: 'emptyLine' }, { symbol: 'emptyCircle', itemStyle: { borderWidth: 5, borderColor: '#000' } },
      { symbol: 'emptyRect', label: { position: 'top' } }, { symbol: 'emptyPin', label: { position: 'top' } }]) }) },
  { id: 'Y3', note: "symbolSize pairs: a [w, h] pin is the UNIT pin stretched (scaleX = w/2, scaleY = h/2), NOT a pin built in a w x h box (a pin built there has height max(0.6w, h)): [30, 60], [60, 20]; rect [40, 10]; circle [40, 10] (a unit circle stretched into an ellipse); [10] (-> [10, 0]: scaleY 0, lineScale 0); the string '14'; [0, 20] (scaleX 0); labels inside and top",
    option: vv({ data: lattice([{ symbolSize: [30, 60] }, { symbolSize: [60, 20] }, { symbol: 'rect', symbolSize: [40, 10] }, { symbol: 'circle', symbolSize: [40, 10] },
      { symbolSize: [10] }, { symbolSize: '14' }, { symbol: 'rect', symbolSize: [0, 20] }, { symbolSize: [30, 60], label: { position: 'top' } },
      { symbol: 'rect', symbolSize: [40, 10], label: { position: 'top' } }]) }) },
  { id: 'Y4', note: "symbolSize 0: the symbol is drawn (scale 0, transform matrix(0,0,0,0,x,y)) and the label is KEPT at the point (pin rule: rect height 0 -> y = point; 'right' at point + 5); symbol 'none' draws neither symbol nor label (drawn false); symbol '' draws a circle; null symbol falls back to the series-level 'rect'",
    option: vv({ symbol: 'rect', data: lattice([{ symbolSize: 0, symbol: 'pin' }, { symbolSize: 0, symbol: 'pin', label: { position: 'right' } }, { symbol: 'none' }, { symbol: '' }, { symbol: null },
      { symbolSize: 0, symbol: 'circle', label: { position: 'top' } }]) }) },
  { id: 'Y5', note: "symbolRotate (degrees, zrender rotation = +deg * PI / 180: counter-clockwise on screen): pin 30, pin -45, arrow 90, rect [40, 20] 45 with a 'top' label (the rect is the axis-aligned bbox of the rotated shape), 'abc' (NaN * ... || 0 -> 0), the string '30', 180 on a pin with its inside label (the 0.4 rule on the rotated bbox)",
    option: vv({ symbolSize: 30, data: lattice([{ symbolRotate: 30 }, { symbolRotate: -45 }, { symbol: 'arrow', symbolRotate: 90 }, { symbol: 'rect', symbolSize: [40, 20], symbolRotate: 45, label: { position: 'top' } },
      { symbolRotate: 'abc' }, { symbolRotate: '30' }, { symbolRotate: 180 }]) }) },
  { id: 'Y6', note: "symbolOffset -> the path's x / y in px (the group frame: NOT rotated or scaled), percents of the SIZE: [0, '-50%'] on a pin 50 (-25), [10, 5], '50%' (both, of w and of h), ['-25%'] (y falls back to x's value but takes a percent of the HEIGHT), [0, '50%'] with symbolRotate 45 and a 'top' label (the rect moves with the offset), 0",
    option: vv({ data: lattice([{ symbolOffset: [0, '-50%'] }, { symbolOffset: [10, 5] }, { symbol: 'rect', symbolSize: [40, 20], symbolOffset: '50%' },
      { symbol: 'rect', symbolSize: [40, 20], symbolOffset: ['-25%'] }, { symbol: 'rect', symbolSize: [40, 20], symbolOffset: [0, '50%'], symbolRotate: 45, label: { position: 'top' } },
      { symbolOffset: 0 }]) }) },
  { id: 'Y7', note: 'symbolKeepAspect true on rect [40, 20], pin [30, 50], circle [40, 20]: no effect on the built-in shapes (only image:// and path:// use it)',
    option: vv({ symbolKeepAspect: true, data: lattice([{ symbol: 'rect', symbolSize: [40, 20] }, { symbolSize: [30, 50] }, { symbol: 'circle', symbolSize: [40, 20] }]) }) },
  { id: 'Y8', note: "series-level markPoint symbol options {symbol 'circle', symbolSize [20, 30], symbolRotate 30, symbolOffset [0, '-50%'], symbolKeepAspect} inherited by items, item overrides; a top-level markPoint {symbolSize 40, symbol 'diamond'} under a second series without its own",
    option: cat([{ type: 'line', name: 'a', data: D7, markPoint: { symbol: 'circle', symbolSize: [20, 30], symbolRotate: 30, symbolOffset: [0, '-50%'], symbolKeepAspect: true,
      data: [{ type: 'max' }, { type: 'min', symbol: 'rect', symbolSize: 16, symbolRotate: 0 }] } },
    { type: 'line', name: 'b', data: D7.map(v => v / 2), markPoint: { data: [{ type: 'max' }, { type: 'min', symbolSize: 24 }] } }], { markPoint: { symbolSize: 40, symbol: 'diamond' } }) },
  { id: 'Y9', note: "a STROKED pin (borderColor '#000', borderWidth 4, lineScale 25): the label rect grows by 4 / 25 local units (2 px each side), so the 0.4 rule lands on the grown rect (rect.y - 2 + (h + 4) * 0.4); the same with a 'top' label; an emptyPin (stroke = the colour at width 2) with 'top'",
    option: vv({ data: lattice([{ itemStyle: { borderColor: '#000', borderWidth: 4 } }, { itemStyle: { borderColor: '#000', borderWidth: 4 }, label: { position: 'top' } },
      { symbol: 'emptyPin', label: { position: 'top' } }, { itemStyle: { borderColor: '#000', borderWidth: 4 }, symbolSize: [30, 60] }]) }) },
  { id: 'Y10', note: "stretched unit shapes: roundRect [40, 10] / [10, 40] (r = 0.5 in the unit box -> elliptical 10 x 2.5 px corners), circle [40, 10] with 'bottom', triangle [30, 50] with 'left', diamond rotated 30 with 'right' (the rotated bbox: four transformed corners), a rotated circle (its bbox is the rotated unit square's hull, not the ellipse's)",
    option: vv({ data: lattice([{ symbol: 'roundRect', symbolSize: [40, 10] }, { symbol: 'roundRect', symbolSize: [10, 40], label: { position: 'top' } }, { symbol: 'circle', symbolSize: [40, 10], label: { position: 'bottom' } },
      { symbol: 'triangle', symbolSize: [30, 50], label: { position: 'left' } }, { symbol: 'diamond', symbolSize: [30, 40], symbolRotate: 30, label: { position: 'right' } },
      { symbol: 'circle', symbolSize: [40, 20], symbolRotate: 30, label: { position: 'top' } }]) }) },
  { id: 'Y11', note: "NEGATIVE symbol sizes (normalizeSymbolSize keeps them: only 0 / NaN become 0): -20 flips the pin (head BELOW the point; its inside label at 0.4 of the flipped rect, applyTransform's fast path swaps the negative extent), [-30, 20] rect with a 'top' label, -20 rect rotated 30 (lineScale sqrt|det| = 10)",
    option: vv({ data: lattice([{ symbolSize: -20 }, { symbol: 'rect', symbolSize: [-30, 20], label: { position: 'top' } }, { symbol: 'rect', symbolSize: -20, symbolRotate: 30, itemStyle: { borderColor: '#000' } }]) }) },
  // ----- itemStyle -----
  { id: 'S1', note: "itemStyle: color '#c00' (item); borderColor '#000' + borderWidth 3 (stroke painted at 3 / lineScale in local units; a 'top' label rises by 1.5 px); opacity 0.5 (the label's default opacity too); borderType 'dashed' with borderColor (dash [4w, 2w] / lineScale); 'dotted'; a number array [6, 3] (as is / lineScale); borderWidth 0 with borderColor (a stroke attr of width 0, no rect growth); borderColor 'none'; borderDashOffset 3 (held)",
    option: vv({ symbol: 'rect', symbolSize: [36, 24], data: lattice([{ itemStyle: { color: '#c00' } }, { itemStyle: { borderColor: '#000', borderWidth: 3 }, label: { position: 'top' } },
      { itemStyle: { opacity: 0.5 } }, { itemStyle: { borderColor: '#000', borderType: 'dashed' } }, { itemStyle: { borderColor: '#000', borderType: 'dotted', borderWidth: 3 } },
      { itemStyle: { borderColor: '#000', borderType: [6, 3] } }, { itemStyle: { borderColor: '#000', borderWidth: 0 }, label: { position: 'top' } },
      { itemStyle: { borderColor: 'none' }, label: { position: 'top' } }, { itemStyle: { borderColor: '#000', borderType: 'dashed', borderDashOffset: 3 } }]) }) },
  { id: 'S2', note: "fill fallbacks: series itemStyle.color '#123456' (= the series colour); the series markPoint itemStyle.color; the top-level markPoint itemStyle.color under a second series; item color '' (falsy -> the series colour); 'none' with borderColor (no fill: the label falls back to OUTSIDE ink although 'inside', and the rect grows by max(lineWidth, 5)); 'transparent' (a string fill: lum 0 -> '#ccc', its inside stroke 'transparent' paints nothing)",
    option: Object.assign(cat([{ type: 'line', name: 'a', data: D7, itemStyle: { color: '#123456' }, markPoint: { data: [{ type: 'max' }, { type: 'min', itemStyle: { color: '' } },
      { coord: ['Tue', 180], value: 1, itemStyle: { color: 'none', borderColor: '#000' } }, { coord: ['Thu', 180], value: 2, itemStyle: { color: 'none', borderColor: '#000' }, label: { position: 'top' } },
      { coord: ['Sat', 180], value: 3, itemStyle: { color: 'transparent' } }] } },
    { type: 'line', name: 'b', data: D7.map(v => v / 2), markPoint: { itemStyle: { color: '#0a0' }, data: [{ type: 'max' }] } },
    { type: 'line', name: 'c', data: D7.map(v => v / 3), markPoint: { data: [{ type: 'max' }] } }]), { markPoint: { itemStyle: { color: '#777' } } }) },
  { id: 'S3', note: "getLineScale's guard: it is 1 unless BOTH m[0] and m[3] differ from 1 by 1e-10 -- a rect [2, 30] (scaleX 1) has lineScale 1 (not sqrt 15), so its stroke (borderWidth 4) is painted at 4 and grows the rect by 4 local units = 4 px across but 60 px down; [30, 2] likewise; [2, 2] (scale 1: no local transform, the path's transform = the group's); labels top / right",
    option: vv({ symbol: 'rect', itemStyle: { borderColor: '#000', borderWidth: 4 }, label: { position: 'top' }, data: lattice([{ symbolSize: [2, 30] }, { symbolSize: [2, 30], label: { position: 'right' } },
      { symbolSize: [30, 2] }, { symbolSize: [30, 2], label: { position: 'right' } }, { symbolSize: [2, 2] }, { symbolSize: [30, 20] }]) }) },
  // ----- label positions -----
  { id: 'L1', note: "every calculateTextPosition position on a rect [40, 24] with label.distance 8 (series level): top / bottom / left / right outside (outside ink '#333' + white halo), inside* positions (inside ink from the fill)",
    option: vv({ symbol: 'rect', symbolSize: [40, 24], label: { distance: 8 }, data: lattice(POS13.map(p => ({ label: { position: p } }))) }) },
  { id: 'L2', note: "every position on the default pin 50 (distance 5): the 0.4 rule ONLY for exactly 'inside' (insideTop etc. use the plain table on the pin's rect x in [-15, 15], y in [-43.57, 0] around the point); 'outside' -> 'top'; 'start' (unknown: rect.x / rect.y, left / top, outside ink); an array ['50%', '0%'] and [10, 20] (offsets from the rect's corner, align / valign null -> laid out left / top, outside ink)",
    option: vv({ data: lattice(POS13.concat(['outside', 'start', ['50%', '0%'], [10, 20]]).map(p => ({ label: { position: p } })), 5) }) },
  { id: 'L3', note: "label.rotate / offset / align: rotate 45 (inner rotation, origin 0 -> about the anchor); offset [10, -5] (anchor moves, origin = -offset); rotate -90 + offset [3, 4]; author align 'right' + verticalAlign 'bottom' (win over the calculated center / middle); align 'middle' -> 'center'; verticalAlign 'center' -> 'middle'; baseline 'top' (the verticalAlign fallback); align 'bogus' -> 'left'",
    option: vv({ data: lattice([{ label: { rotate: 45 } }, { label: { offset: [10, -5] } }, { label: { rotate: -90, offset: [3, 4] } }, { label: { align: 'right', verticalAlign: 'bottom' } },
      { label: { align: 'middle' } }, { label: { verticalAlign: 'center' } }, { label: { baseline: 'top' } }, { label: { align: 'bogus' } }]) }) },
  { id: 'L8', note: "label.rotate / offset on OUTSIDE positions: 'right' rotate 90; 'top' offset [0, -10]; 'left' rotate -30 + offset [5, 5]; 'bottom' on a rotated (45) rect",
    option: vv({ symbol: 'rect', symbolSize: [30, 20], data: lattice([{ label: { position: 'right', rotate: 90 } }, { label: { position: 'top', offset: [0, -10] } },
      { label: { position: 'left', rotate: -30, offset: [5, 5] } }, { symbolRotate: 45, label: { position: 'bottom' } }]) }) },
  // ----- label text -----
  { id: 'L4', note: "formatter templates on a NAMED series: '{a}|{b}|{c}'; '{c} and {c}' (formatTpl replaces the FIRST occurrence only); '{d}' (no $var: literal); '{c}' with no value -> 'undefined', with value null -> 'null'; '{b}' with no name -> ''; '{a0}{b0}{c0}'; a value array in {c} -> '3,8'; a series-level formatter inherited; a top-level markPoint formatter under a second series",
    option: Object.assign(vv({ label: { formatter: 'S:{b}' }, data: lattice([{ name: 'n0', label: { formatter: '{a}|{b}|{c}' } }, { label: { formatter: '{c} and {c}' } }, { label: { formatter: '{d}' } },
      { value: undefined, label: { formatter: '<{c}>' } }, { value: null, label: { formatter: '<{c}>' } }, { label: { formatter: '[{b}]' } }, { name: 'n5', label: { formatter: '{a0}{b0}{c0}' } }, { value: [3, 8], label: { formatter: '{c}' } },
      { name: 'inherited' }]) }, null, { name: 'Series A' }), { markPoint: { label: { formatter: 'top:{c}' } } }) },
  { id: 'L5', note: "default texts = String(value) with NO rounding (unlike markLine): 0.1 + 0.2 -> '0.30000000000000004', 1e21 -> '1e+21', 1.5e-7 -> '1.5e-7' (JS number-to-string), 0 -> '0', a string 'abc', true -> 'true'; a coord item whose value (99) differs from its coord -> '99'; px items: no value -> no text; px + type 'average' -> dataTransform puts the STATISTIC (5.5, not a datum: numCalculate on the y column) in value",
    option: vv({ data: lattice([{ value: 0.1 + 0.2 }, { value: 1e21 }, { value: 1.5e-7 }, { value: 0 }, { value: 'abc' }, { value: true }, { coord: [3, 3], value: 99 },
      { x: 150, y: 120, coord: null, value: undefined }, { x: '60%', y: '20%', coord: null, type: 'average' }]) }) },
  { id: 'L6', note: "label fonts: fontSize 16, fontWeight 'bold', fontFamily 'serif', fontStyle 'italic' per item; fontSize '18px' (kept as is); the rest from the global textStyle (option textStyle {fontSize: 13, fontWeight: 600})",
    option: vv({ data: lattice([{ label: { fontSize: 16 } }, { label: { fontWeight: 'bold' } }, { label: { fontFamily: 'serif' } }, { label: { fontStyle: 'italic' } }, { label: { fontSize: '18px' } }, {}]) },
      { textStyle: { fontSize: 13, fontWeight: 600 } }) },
  { id: 'L7', note: "label colours: color '#f0f' (style fill -> no automatic stroke); color 'inherit' (= the visual fill); textBorderColor '#0f0' + textBorderWidth 3; textBorderWidth 1.5 alone (the inside stroke at 1.5); textBorderColor 'none'; label opacity 0.5; backgroundColor '#ff0' (a box: no automatic stroke); show false (null); a two-line formatter (two TSpans); color 'inherit' on an OUTSIDE ('top') label (outsideFill = the visual fill)",
    option: vv({ data: lattice([{ label: { color: '#f0f' } }, { label: { color: 'inherit' } }, { label: { textBorderColor: '#0f0', textBorderWidth: 3 } }, { label: { textBorderWidth: 1.5 } },
      { label: { textBorderColor: 'none' } }, { label: { opacity: 0.5 } }, { label: { backgroundColor: '#ff0' } }, { label: { show: false } }, { name: 'two', label: { formatter: '{b}\n{c}' } },
      { label: { color: 'inherit', position: 'top' } }]) }) },
  // ----- ink bands and grounds -----
  { id: 'K1', note: "inside ink bands on a light ground (rect 34 x 22): lum > 0.5 '#333', > 0.2 '#eee', else '#ccc'; fills #fff (1), #04c26d (exactly 0.5 -> '#eee'), #808080 (0.502 -> '#333'), #033992 (exactly 0.2 -> '#ccc'), #333 (0.19999 -> '#ccc'), #000, rgba(255,255,255,0.3) (lum 0.3 over black -> '#eee'), #5070dd, #eb5454 (0.5066 -> '#333'), 'transparent'; stroke = the fill exactly for the light labels ('#eee' / '#ccc': dark mode false === dark label false)",
    option: vv({ symbol: 'rect', symbolSize: [34, 22], data: lattice(BAND_FILLS.map(c => ({ itemStyle: { color: c } }))) }) },
  { id: 'K2', note: "the same fills with darkMode true: inside stroke = the fill exactly for the DARK label '#333' (lum < 0.4); outside ('top') labels '#ccc' with the halo blended on black 'rgba(0,0,0,1)'",
    option: vv({ symbol: 'rect', symbolSize: [34, 22], data: lattice(BAND_FILLS.map(c => ({ itemStyle: { color: c } })).concat([{ label: { position: 'top' } }])) }, { darkMode: true }) },
  { id: 'K3', note: "backgroundColor '#1e1e1e' (darkMode auto: lum < 0.4): default pins with inside ink (#5070dd -> '#eee', NOT stroked in dark mode) and a 'top' label '#ccc' + halo 'rgba(30,30,30,1)'; empty symbols ('#fff' fill -> '#333' stroked with '#fff' in dark mode)",
    option: vv({ data: lattice([{}, { label: { position: 'top' } }, { symbol: 'emptyCircle', symbolSize: 30 }, { symbol: 'emptyRect', symbolSize: 30, label: { position: 'bottom' } }]) }, { backgroundColor: '#1e1e1e' }) },
  { id: 'K4', note: "backgroundColor 'rgba(0,0,0,0.5)' (lum 0.5: light): outside halo = 0 * 0.5 + 255 * 0.5 = 127.5 per channel -> 'rgba(127.5,127.5,127.5,1)'",
    option: vv({ data: lattice([{ label: { position: 'top' } }, {}]) }, { backgroundColor: 'rgba(0,0,0,0.5)' }) },
  // ----- z / silent / hidden / not drawn / relativeTo -----
  { id: 'Z1', note: "z / zlevel / silent from the top-level markPoint {z: 9, zlevel: 1, silent: true}; item z2: a first marker z2 10 lifts EVERY later label (label z2 = the running max z2 over the SymbolDraw group so far + 2 = 12); a z2 -5 marker after it keeps 12; the second series (markPoint z 3, z2 1) has a z2 -5 marker FIRST -> its label z2 -3, the next takes z2 1 from the series markPoint -> label 3; label.silent on one item",
    option: Object.assign(vv({ data: [] }), { series: [{ type: 'scatter', name: 's0', symbolSize: 7, data: PTS, markPoint: { data: lattice([{ z2: 10 }, {}, { z2: -5 }]) } },
      { type: 'scatter', name: 's1', symbolSize: 7, data: PTS, markPoint: { z: 3, z2: 1, data: lattice([{ z2: -5, coord: [2, 2] }, { coord: [6, 2] }, { coord: [8, 2], label: { silent: true } }]) } }],
    markPoint: { z: 9, zlevel: 1, silent: true } }) },
  { id: 'Z2', note: 'series silent: true (the SymbolDraw group is silent: every symbol isSilent), markPoint silent on another series',
    option: Object.assign(vv({ data: [] }), { series: [{ type: 'scatter', name: 's0', silent: true, symbolSize: 7, data: PTS, markPoint: { data: [{ coord: [2, 2], value: 1 }] } },
      { type: 'scatter', name: 's1', symbolSize: 7, data: PTS, markPoint: { silent: true, data: [{ coord: [6, 6], value: 2 }] } }] }) },
  { id: 'H1', note: 'a legend-unselected series draws no markPoint (filtered); the visible one does',
    option: Object.assign(vv({ data: [] }), { legend: { selected: { hidden: false } }, series: [{ type: 'scatter', name: 'hidden', symbolSize: 7, data: PTS, markPoint: { data: [{ coord: [2, 2], value: 1 }] } },
      { type: 'scatter', name: 'shown', symbolSize: 7, data: PTS, markPoint: { data: [{ coord: [6, 6], value: 2 }] } }] }) },
  { id: 'N1', note: 'a marker NOT drawn: {x: 100} (only x px: hasXOrY keeps it, point [100, NaN]) -> symbolNeedsDraw false: no Symbol group, no label (the only NaN of the case); the next marker is drawn and its label z2 is unaffected',
    nan: true, option: vv({ data: [{ x: 100 }, { coord: [5, 5], value: 3 }] }) },
  { id: 'R1', note: "px-placed markers: {x: '20%', y: '30%'} of the container, relativeTo 'coordinate' {x: '50%', y: '0%'} (the grid rect's top edge centre), numbers {x: 100, y: 80}, a coord item with a px y override; no value -> no text except the one with value",
    option: vv({ data: [{ x: '20%', y: '30%' }, { x: '50%', y: '0%', relativeTo: 'coordinate', value: 7 }, { x: 100, y: 80 }, { coord: [5, 5], y: 50, value: 5 }] }) },
];
const GALLERY_CASES = ['bar1', 'line-marker', 'candlestick-sh', 'scatter-weight', 'bar-rich-text'];
const GALLERY_NOTES = {
  'bar-rich-text': "gallery bar-rich-text.json, verbatim: a size-1 pin offset [0, '50%'] with a RICH label (formatter '{a|{a}\\n}{b|{b} }{c|{c}}', box, padding, position 'right', distance 20): text, placement, style, inkDefault recorded; rich text layout and its per-token ink are NOT (ink null)",
};
for (const g of GALLERY_CASES) CASES.push({ id: 'G-' + g, note: GALLERY_NOTES[g] || 'gallery ' + g + '.json, verbatim', gallery: g });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'no-series-level', mutation: 'the series markPoint option skipped in every chain (item -> top-level -> default)', mut: { noSeriesLevel: true }, named: ['Y8', 'L1'] },
  { id: 'size-first-only', mutation: 'a [w, h] symbolSize read as [w, w]', mut: { sizeFirstOnly: true }, named: ['Y3', 'Y7'] },
  { id: 'shape-in-box', mutation: 'the symbol built in a w x h box at scale 1 instead of the unit box scaled by size / 2', mut: { pinInBox: true }, named: ['D1', 'Y3'] },
  { id: 'no-modpi2', mutation: 'arc start angle normalised by % 2PI instead of modPI2 (round to 1e-8 of PI)', mut: { noModPI2: true }, named: ['D1'] },
  { id: 'offset-width-percent', mutation: "the offset's y percent taken of the WIDTH", mut: { offsetWidthPercent: true }, named: ['Y6'] },
  { id: 'offset-scaled', mutation: 'the offset applied in the scaled frame (times size / 2)', mut: { offsetScaled: true }, named: ['Y6', 'Y8'] },
  { id: 'no-offset', mutation: 'symbolOffset ignored', mut: { noOffset: true }, named: ['Y6', 'G-bar-rich-text'] },
  { id: 'rotate-negated', mutation: 'symbolRotate applied clockwise (negated)', mut: { rotateNegated: true }, named: ['Y5'] },
  { id: 'rotate-nan-kept', mutation: "a non-numeric symbolRotate kept as NaN (no '|| 0')", mut: { rotateNaNKept: true }, named: ['Y5'] },
  { id: 'fill-ignores-item', mutation: 'itemStyle.color ignored (always the series colour)', mut: { fillIgnoresItem: true }, named: ['S2', 'K1', 'G-candlestick-sh'] },
  { id: 'fill-null-check', mutation: "the fill fallback only for a null colour ('' kept)", mut: { fillNullCheck: true }, named: ['S2'] },
  { id: 'empty-keeps-width', mutation: 'empty symbols keep itemStyle.borderWidth instead of 2', mut: { emptyKeepsWidth: true }, named: ['Y2'] },
  { id: 'empty-filled', mutation: 'empty symbols filled with the colour', mut: { emptyFilled: true }, named: ['Y2', 'K3'] },
  { id: 'line-not-stroked', mutation: "the 'line' symbol not stroked", mut: { lineNotStroked: true }, named: ['Y1'] },
  { id: 'empty-string-none', mutation: "symbol '' treated as 'none' (not drawn)", mut: { emptyStringNone: true }, named: ['Y1', 'Y4'] },
  { id: 'size0-hides-label', mutation: 'a zero symbolSize hides the label', mut: { size0HidesLabel: true }, named: ['Y4', 'Y3'] },
  { id: 'keep-aspect-uniform', mutation: 'symbolKeepAspect makes the built-in shapes uniform (min side)', mut: { keepAspectUniform: true }, named: ['Y7', 'Y8'] },
  { id: 'text-from-coord', mutation: "the default text reads the item's coord on the label dim instead of its value", mut: { textFromCoord: true }, named: ['D2', 'L5', 'G-bar1'] },
  { id: 'label-dim-first', mutation: 'the default label dim is the FIRST non-ordinal / time dim', mut: { labelDimFirst: true }, named: ['D3'] },
  { id: 'label-dim-always-y', mutation: 'the default label dim is always y', mut: { labelDimAlwaysY: true }, named: ['D5', 'D7'] },
  { id: 'text-rounded', mutation: 'the default text rounded like markLine (toFixed(10))', mut: { textRounded: true }, named: ['L5'] },
  { id: 'pin-rule-off', mutation: "no pin rule: a pin's inside label centred on its rect", mut: { pinRuleOff: true }, named: ['D1', 'Y2'] },
  { id: 'pin-rule-any-inside', mutation: "the pin rule for every 'inside*' position", mut: { pinRuleAnyInside: true }, named: ['L2'] },
  { id: 'rect-no-offset', mutation: "the label rect without the path's offset", mut: { rectNoOffset: true }, named: ['Y6'] },
  { id: 'rect-no-stroke', mutation: 'the label rect not grown by the stroke', mut: { rectNoStroke: true }, named: ['S1', 'S3', 'Y1'] },
  { id: 'line-scale-unguarded', mutation: 'getLineScale = sqrt|det| always (no m[0] / m[3] near-1 guard)', mut: { lineScaleUnguarded: true }, named: ['S3'] },
  { id: 'no-fill-threshold', mutation: 'a fill-less stroked path grows its rect by lineWidth, not max(lineWidth, 5)', mut: { noFillThreshold: true }, named: ['S2'] },
  { id: 'inside-as-outside', mutation: 'inside positions use the outside ink', mut: { insideAsOutside: true }, named: ['D1', 'K1'] },
  { id: 'inside-stroke-never', mutation: 'no automatic inside stroke', mut: { insideStrokeNever: true }, named: ['D1', 'K1', 'K2'] },
  { id: 'bands-inclusive', mutation: 'the lum bands compared with >= instead of >', mut: { bandsInclusive: true }, named: ['K1'] },
  { id: 'dark-ignored', mutation: 'the ground never dark (outside ink, inside stroke)', mut: { darkIgnored: true }, named: ['K2', 'K3'] },
  { id: 'distance-ignored', mutation: 'label.distance ignored (always 5)', mut: { distanceIgnored: true }, named: ['L1', 'G-bar-rich-text'] },
  { id: 'outside-not-top', mutation: "position 'outside' not mapped to 'top'", mut: { outsideNotTop: true }, named: ['L2'] },
  { id: 'array-align-left', mutation: "an array position gives align 'left' / valign 'top' instead of null", mut: { arrayAlignLeft: true }, named: ['L2'] },
  { id: 'unknown-inside', mutation: "an unknown position treated as 'inside'", mut: { unknownInside: true }, named: ['L2'] },
  { id: 'z2-per-marker', mutation: "label z2 = this marker's z2 + 2 (no running max)", mut: { z2PerMarker: true }, named: ['Z1'] },
  { id: 'label-opacity-own', mutation: 'label opacity not defaulting to itemStyle.opacity', mut: { labelOpacityOwn: true }, named: ['S1'] },
  { id: 'tpl-replace-all', mutation: 'formatTpl replaces every occurrence', mut: { tplReplaceAll: true }, named: ['L4'] },
  { id: 'no-global-font', mutation: 'label font parts without the global textStyle fallback', mut: { noGlobalFont: true }, named: ['L6', 'D1'] },
  { id: 'no-label-rotate', mutation: 'label.rotate ignored', mut: { noLabelRotate: true }, named: ['L3'] },
  { id: 'offset-keeps-origin', mutation: 'label.offset leaves the origin at 0', mut: { offsetKeepsOrigin: true }, named: ['L3'] },
  { id: 'user-align-ignored', mutation: 'author label align / verticalAlign ignored', mut: { userAlignIgnored: true }, named: ['L3'] },
  { id: 'align-no-normalize', mutation: "'middle' align / 'center' valign not normalised", mut: { alignNoNormalize: true }, named: ['L3'] },
  { id: 'bg-auto-stroke', mutation: 'a label backgroundColor does not suppress the automatic stroke', mut: { bgAutoStroke: true }, named: ['L7'] },
];

// ============================================================================
// The run
// ============================================================================
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
// the recorded series block (items) vs a transcription result (markers in dataIndex order)
function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const mp = sr.markPoint;
  const a = {};
  const b = {};
  flat({ z: mp.z, zlevel: mp.zlevel, silent: mp.silent, count: mp.count, dims: mp.dims, labelDims: mp.labelDims }, 'block', a);
  flat({ z: t.z, zlevel: t.zlevel, silent: t.silent, count: t.count, dims: t.dims, labelDims: t.labelDims }, 'block', b);
  for (const it of mp.items) {
    if (!it.survived) continue;
    const { index, survived, dataIndex, ...rest } = it;
    flat(rest, 'marker' + dataIndex, a);
    flat(t.markers[dataIndex], 'marker' + dataIndex, b);
  }
  return diffFlat(a, b);
}

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
      update: 'setOption, then zr.storage.getDisplayList(true) (update / updateInnerText of every element), then chart.renderToSVGString() (the SVG painter builds the path proxies and prints the painted stroke)',
      mpData: "MarkerModel.getMarkerModelFromSeries(series, 'markPoint').getData(): getRawDataItem, getItemLayout, getItemVisual, mapDimensionsAll('defaultedLabel')",
      symbol: 'mpData.getItemGraphicEl(i) = the Symbol group; childAt(0) = the symbol path (SymbolClz); el.path.data up to len(); el.path.getBoundingRect(); el.getLineScale(); el.getTextContent() = the label',
      paint: 'the SVG <path> with ecmeta_series_index / ecmeta_data_index and the element transform (matrix rounded to 3 / 4 decimals): stroke, stroke-width (absent = 1), stroke-dasharray',
      tag: "a second run with data elements tagged '" + TAG + "' maps markers to original indices",
    },
    notes: [
      'Only cartesian2d series are covered; image:// and path:// symbols are not (keepAspect only matters there). matrix-stock is not a case: its grids are placed by the matrix coordinate system.',
      "The default label font family comes from globalDefault.ts: 'Microsoft YaHei' when navigator.platform starts with 'Win' (node >= 21 has a navigator: 'Win32' on this machine), else 'sans-serif'. The recorded fonts are this machine's; every case records ecModel.option.textStyle.",
      'The symbol path is always the UNIT shape (createSymbol(type, -1, -1, 2, 2)) scaled by symbolSize / 2 about the point; symbolOffset is the path x / y in px (not scaled, not rotated); rotation is +deg in zrender (counter-clockwise on screen).',
      'strokeNoScale: the painter strokes at lineWidth / lineScale in LOCAL units (= lineWidth px when the scale is uniform); the dash is divided by lineScale as well. lineScale is 1 when either diagonal term of the global matrix is within 1e-10 of 1.',
      "The label is placed on the symbol path's getBoundingRect() (grown by the stroke) transformed by the path's GLOBAL transform (group translate x path local), then calculateTextPosition; a pin with position exactly 'inside' takes y = rect.y + rect.height * 0.4.",
      "Rich labels (bar-rich-text) record text, placement, style and inkDefault only: their token layout and per-token ink are out of scope (ink null).",
      'A label with text null (no value and no formatter, or no label dim) has no TSpan: nothing is painted (ink null, lines 0).',
    ],
    cases,
  };
  return { out, side };
}

function isNaNHex(h) {
  return typeof h === 'string' && /^7ff8/.test(h);
}
function scanNaN(v) {
  if (v == null) return false;
  if (typeof v === 'string') return isNaNHex(v);
  if (isArray(v)) return v.some(scanNaN);
  if (typeof v === 'object') return Object.keys(v).some(k => !/Text$/.test(k) && k !== 't' && k !== 'point' && scanNaN(v[k]));
  return false;
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    let anyNaN = false;
    let anyNaNPoint = false;
    for (const sr of c.series) {
      if (!sr.markPoint) continue;
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
      for (const it of sr.markPoint.items) {
        if (!it.survived) continue;
        if (scanNaN(it)) anyNaN = true;
        if (it.point.some(isNaNHex)) {
          anyNaNPoint = true;
          must(!it.drawn, key + ': a NaN point drawn');
        }
      }
    }
    must(!anyNaN, c.id + ': NaN in a recorded picture');
    must(anyNaNPoint === c.nan, c.id + ': ' + (anyNaNPoint ? 'a NaN point although the case is not marked nan' : 'expected a NaN point'));
  }
  // anchors
  const item = (id, si, i) => byId[id].series.find(s => s.seriesIndex === si).markPoint.items[i];
  const n = h => num(h);
  const d1 = item('D1', 0, 0);
  must(d1.symbol.shapeText.x === '-1' && d1.symbol.shapeText.width === '2' && d1.symbol.scaleXText === '25', 'D1: the unit pin scaled 25');
  must(Math.abs(n(d1.label.inner.y) - (n(d1.point[1]) - 26.142857142857142)) < 1e-9 && d1.label.inkDefault.fill === '#eee' && d1.label.ink.stroke === '#5070dd', 'D1: pin label at 0.4, ink');
  must(d1.label.z2 === 2 && d1.symbol.z === 5 && d1.symbol.z2 === 0, 'D1: z / z2');
  must(item('D2', 1, 1).label.text === '182.2' && item('D2', 1, 2).label.text === null, 'D2: value text, no text');
  must(item('D3', 0, 3).label.text === '8', 'D3: value array on y');
  must(byId.D4.series[0].color === '#eb5454' && item('D4', 0, 0).label.inkDefault.fill === '#333', 'D4: candlestick colour');
  must(item('D5', 0, 2).label.text === '1', 'D5: label dim x');
  must(item('D7', 0, 0).label.text === null && item('D7', 0, 1).label.text === 'v=6', 'D7: no label dim');
  must(item('Y1', 0, 10).symbol.shapeType === 'circle' && item('Y1', 0, 9).symbol.shapeType === 'star', 'Y1: empty string / unknown');
  must(item('Y2', 0, 8).symbol.style.lineWidthText === '2' && item('Y2', 0, 8).symbol.style.fill === '#fff', 'Y2: empty brush');
  must(item('Y4', 0, 0).label && n(item('Y4', 0, 0).label.inner.y) === n(item('Y4', 0, 0).point[1]) && !item('Y4', 0, 2).drawn && item('Y4', 0, 2).label === null, 'Y4: size 0 keeps the label, none kills it');
  must(item('S3', 0, 0).symbol.lineScaleText === '1', 'S3: line scale guard');
  must(item('S2', 0, 2).label.inside === false, 'S2: fill none -> outside ink');
  must(item('K1', 0, 1).label.inkDefault.fill === '#eee' && item('K1', 0, 3).label.inkDefault.fill === '#ccc', 'K1: exact band edges');
  must(item('K4', 0, 0).label.ink.stroke === 'rgba(127.5,127.5,127.5,1)', 'K4: fractional halo');
  must(item('Z1', 0, 1).label.z2 === 12 && item('Z1', 0, 2).label.z2 === 12, 'Z1: running z2');
  must(item('L5', 0, 0).label.text === '0.30000000000000004', 'L5: no rounding');
  must(item('L4', 0, 1).label.text.endsWith(' and {c}'), 'L4: first occurrence only');
  must(byId.H1.series[0].filtered && byId.H1.series[0].markPoint === null, 'H1: hidden series');
  must(!item('N1', 0, 0).drawn && item('N1', 0, 1).drawn, 'N1: not drawn');
  must(byId['G-bar-rich-text'].series[0].markPoint.items[0].label.rich, 'bar-rich-text: rich');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        if (!sr.markPoint) continue;
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

// upstream's dev build logs to the console; keep the run quiet
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
const nMarkers = out.cases.reduce((a, c) => a + c.series.reduce((b, s) => b + (s.markPoint ? s.markPoint.items.filter(i => i.survived).length : 0), 0), 0);
console.log(out.cases.length + ' cases (' + nMarkers + ' markers); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages from upstream');
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
