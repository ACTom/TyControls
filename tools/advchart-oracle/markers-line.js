/*
Upstream's own answers for series MARKERS, batch M2: the PICTURE of a markLine
-- the drawn line segment, its two end symbols and its label -- exactly as
chart/helper/Line.ts, LinePath.ts, util/symbol.ts, label/labelStyle.ts and
zrender (graphic/shape/Line.ts, helper/subPixelOptimize.ts, Element.ts
updateInnerText, graphic/Text.ts, core/Transformable.ts, core/PathProxy.ts,
canvas/dashStyle.ts) build them. M1 (markers-layout.js) pinned the model, the
data transform and the end points; this oracle takes those as given and pins
what is drawn on them.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
for every chart case, with Math.random replaced by the port's xorshift32 (seed
2463534242, reset before each chart). After setOption it runs
zr.storage.getDisplayList(true) (every element's beforeUpdate / update /
updateInnerText: Line.beforeUpdate places the symbols and the label here) and
chart.renderToSVGString() (the SVG painter builds every path proxy; the dash
array is read back from the <path> it writes), then reads the live elements:
per series the slave markLine model's lineData (MarkerModel.
getMarkerModelFromSeries, as M1), per line lineData.getItemGraphicEl(i) = the
Line group: childOfName('line') (ECLinePath), 'fromSymbol', 'toSymbol' and
getTextContent() (the label). Every chart is disposed in a finally.

Which ORIGINAL data element a line came from: as M1, every case runs twice --
verbatim (every recorded value comes from this run) and once more with each data
element tagged '__oracleIndex' (both ends of a pair); the tagged run must give
exactly the same pictures, and its tags give `index` / `survived`.

  node tools/advchart-oracle/markers-line.js

writes tests/fixtures/advchart-markers-line.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Conventions (as markers-layout.js / line-smooth.js)
  hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
           lowercase (NaN 7ff8000000000000). Every hex field k has a readable
           twin kText (String(v), '-0' for negative zero).
  val      a raw JS value of the option world, tagged by kind: null (undefined
           or null) | {"n": hex, "t": text} a number | {"s": string} | {"j":
           json} anything else
  json     an option value exactly as upstream holds it (JSON; undefined ->
           null)
  path     [{cmd, args [hex], argsText}] -- a PathProxy's data up to len():
           'M' (x, y), 'L' (x, y), 'C' (6), 'A' (cx, cy, rx, ry, startAngle,
           sweep, 0, clockwise 1 / anticlockwise 0 -- PathProxy.arc after
           normalizeArcAngles), 'R' (x, y, w, h), 'Z' (none)
  m6       a transform matrix [a, b, c, d, e, f] (zrender order: x' = a x +
           c y + e, y' = b x + d y + f) as 6 hex + m6Text; null when the
           element has no transform (needLocalTransform false: zrender draws it
           untransformed)
  colour   a css string exactly as upstream holds it, or null

Top level
  source, W, H, seed, api, notes[], cases[], guards[]
  cases[]  one per chart:
    id, note, width, height, gallery (file name or null), option (as fed;
    null for a gallery case: load examples/advchart/gallery/<gallery>.json
    and feed it verbatim), nan (true: a line of this case is NOT drawn because
    an end point holds NaN -- documented in the note)
    ground   {background: zr.getBackgroundColor() (the option's
             backgroundColor or 'transparent'), isDark: zr.isDarkMode()
             (option darkMode when a boolean, else lum(background) < 0.4)}
    textStyle  json: ecModel.option.textStyle -- the global text style every
             label font part falls back to (defaults fontSize 12, fontStyle /
             fontWeight 'normal', fontFamily 'Microsoft YaHei' when
             navigator.platform starts with 'Win' -- this machine -- else
             'sans-serif'; globalDefault.ts:20-27, 86-94)
    series[] every series whose OWN option has markLine.data, series order:
      seriesIndex, name (option name or null), type, filtered (legend-
      unselected: nothing drawn, `markLine` null), color (the series style
      colour, getVisualFromData(seriesData, 'color'): what every colour
      fallback ends in), seriesName (the host series' name as {a} prints it;
      null when the option has no name -- upstream's generated name holds a
      NUL), markLine: null (filtered) or
        z, zlevel (json: retrieveZInfo, model.get('z') || 0 through series
        markLine -> top-level markLine -> default 5), silent (the LineDraw
        group's silent: markLine.silent || series.silent -- every element
        below inherits it for hit testing), count (lineData.count())
        items[]  one per ORIGINAL element of series.markLine.data, in order:
          index, survived (kept by the transform + filter), dataIndex (its
          index in lineData, or null); when it survived also:
          value, name   val: the merged line item's value / name (what the
                        default text and {b} / {c} read)
          visual        {from, to}: the end's item visuals (M1-proven; input
                        of the picture): symbol, symbolSize, symbolRotate,
                        symbolOffset, symbolKeepAspect (json)
          drawn         false when an end point holds NaN (LineDraw
                        lineNeedsDraw): then line / fromSymbol / toSymbol /
                        label are null
          line          the ECLinePath:
            shape {x1, y1, x2, y2} hex + shapeText: the UN-snapped end points
                  (= the M1 layout; pointAt / tangentAt read these)
            path  the proxy after buildPath (zrender subPixelOptimizeLine
                  applied: M x1 y1, L x2 y2)
            style stroke (colour), lineWidth (hex; the style's, 1 when unset),
                  lineDashType (json: lineStyle.type as held: 'dashed',
                  'dotted', 'solid', a number, an array, null),
                  lineDash ([hex] + lineDashText, or null: the RESOLVED dash
                  the painter uses -- read back from the SVG <path>
                  stroke-dasharray, which prints the doubles exactly),
                  lineDashOffset (hex; the style's, not the SVG's rounded
                  one), opacity (hex), lineCap, lineJoin (string or null),
                  strokeNoScale (bool), fill (null)
            z, z2, zlevel, invisible, silent (the element's own flag)
          fromSymbol / toSymbol   null (symbol 'none', '' or unset), else:
            symbol (the visual type string), shapeType (the drawn shape after
            the 'empty' prefix is stripped: upstream's shape.symbolType; an
            unknown name is drawn as 'rect'), empty (bool: __isEmptyBrush),
            box {x, y, width, height} hex + boxText: the createSymbol box
            (-w/2 + offsetX, -h/2 + offsetY, w, h), x, y, rotation, scaleX,
            scaleY, originX, originY (hex + Text), transform (m6), path (in
            LOCAL coordinates), style {fill, stroke (colour), lineWidth (hex),
            opacity (hex, or null: the style holds `undefined` -- the painter
            treats it as 1)}, z, z2, zlevel
          label         null (not shown), else:
            text          the string drawn ('' draws nothing: no TSpan)
            x, y, rotation, originX, originY, scaleX, scaleY (hex + Text): the
                          text element's own props (Line.beforeUpdate)
            inner         {x, y, rotation, originX, originY} hex + innerText:
                          the innerTransformable after updateInnerText (the
                          label's textConfig rotation / offset -- label.rotate
                          / label.offset -- applied over the props above)
            transform     m6 of the inner transformable (the Line group has
                          no transform)
            align, verticalAlign  the style's after zrender normalizeStyle
                          ('middle' align -> 'center', 'center' valign ->
                          'middle', anything else invalid -> 'left' / 'top');
                          null = unset (the TSpan then uses 'left' / 'top')
            font          style.font (makeFont), fontSize, fontWeight,
                          fontStyle, fontFamily (json: the style's parts)
            style         {fill, stroke (colour or null: not in the style),
                          lineWidth (hex or null), opacity (hex)}
            inkDefault    {fill, stroke, autoStroke} = the text's
                          _defaultStyle set by updateInnerText (outside ink)
            ink           null when text is '' (no TSpan), else the TSpan (what
                          is painted): {fill, stroke (null = none), lineWidth
                          (hex or null), opacity (hex)}
            z, z2, zlevel, silent
guards[]  one per mutation of the transcription: id, mutation, named (the
          cases that must turn red), changed (the cases whose recorded values
          the mutated transcription does not reproduce), ok = named is a
          subset of changed, differs (the first differing fields of each
          named case)

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, bit for bit) takes as
INPUTS: the option as fed (the series' markLine option, the top-level markLine
option merged over MarkLineModel.defaultOption), the M1-proven lineData raw
items (merged line item, from item, to item) and end points, the series colour,
the host series name, ecModel.option.textStyle, and the ground (background,
isDark). It reproduces: MarkLineView.renderSeries (the per-end visuals, the
itemStyle fill fallback, lineStyle.stroke ?? from-end fill, z2), LineDraw
lineNeedsDraw, Line.ts createSymbol / createLine / _updateCommonStl (useStyle,
strokeNoScale, symbol.setColor, symbol opacity, setLabelStyle, the default
text) and beforeUpdate (symbol position / rotation / scale, label placement for
every position, distance scalar and pair, author align / verticalAlign),
util/symbol.ts (createSymbol, the shape makers, setColor, normalizeSymbolSize,
normalizeSymbolOffset), zrender's Line / Rect / roundRect / Circle and the
symbol proxies' buildPath over a recording PathProxy (arc with
normalizeArcAngles / modPI2), subPixelOptimizeLine, canvas/dashStyle
normalizeLineDash + getLineDash, Transformable.getLocalTransform /
needLocalTransform / matrix.rotate, Element.updateInnerText (textConfig rotation
/ offset, outside fill / stroke), Text normalizeStyle / makeFont /
parseFontSize and the TSpan ink rules, labelStyle createTextStyle /
setTokenTextStyle / createTextConfig, dataFormat getFormattedLabel + formatTpl,
number.round, SeriesData.getName, and util/graphic traverseUpdateZ (z, zlevel,
label z2 = running max z2 + 2).

Self-checks (any failure: nothing is written, exit 1): the transcription
reproduces every recorded series (every field, bit for bit); the tagged run
gives the same pictures as the verbatim run and its tags increase; each Line
group holds exactly line / fromSymbol / toSymbol in that order, has no
transform, and neither have its ancestors; drawn lines are exactly the lines
without a NaN end point; the line shape equals the lineData layout; every drawn
line is matched by at least one <path> of the SVG with its series index and its
d numbers (the SSR painter compresses d to 1 decimal: matched within 0.05; a
zero-length L is dropped from d), and all its matches agree on the dasharray
and stroke-width (= style.lineWidth); no NaN in any recorded picture, and a
line is not drawn exactly in the cases marked nan; anchors; every guard is ok;
two generations in the process give identical bytes.
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-markers-line.json');
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
// {k: hex, kText: text} for several numeric props of an object
function nums(o, keys, pre) {
  const r = {};
  for (const k of keys) {
    const v = o[k];
    r[(pre || '') + k] = hex(v);
    r[(pre || '') + k + 'Text'] = text(v);
  }
  return r;
}
const hexOrNull = v => (v == null ? null : hex(v));
const textOrNull = v => (v == null ? null : text(v));
const colour = v => (v == null ? null : (must(typeof v === 'string', 'a colour that is not a string: ' + JSON.stringify(v)), v));
function m6(m) {
  if (!m) return { transform: null, transformText: null };
  return { transform: Array.from(m).slice(0, 6).map(hex), transformText: Array.from(m).slice(0, 6).map(text) };
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

// MarkLineModel.defaultOption (MarkLineModel.ts:115-146)
const ML_DEFAULTS = {
  z: 5, symbol: ['circle', 'arrow'], symbolSize: [8, 16], symbolOffset: 0, precision: 2, tooltip: { trigger: 'item' },
  label: { show: true, position: 'end', distance: 5 }, lineStyle: { type: 'dashed' },
  emphasis: { label: { show: true }, lineStyle: { width: 3 } }, animationEasing: 'linear',
};
const PI = Math.PI;
const PI2 = PI * 2;
const NEUTRAL00 = '#fff'; // tokens.color.neutral00 (visual/tokens.ts:124)
const NEUTRAL99 = '#000'; // tokens.color.neutral99 (visual/tokens.ts:144)

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
// util/symbol.ts:390-411
function normalizeSymbolSize(s) {
  if (!isArray(s)) s = [+s, +s];
  return [s[0] || 0, s[1] || 0];
}
function normalizeSymbolOffset(o, size) {
  if (o == null) return undefined;
  if (!isArray(o)) o = [o, o];
  return [parsePercent(o[0], size[0]) || 0, parsePercent(retrieve2(o[1], o[0]), size[1]) || 0];
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
    case 'line': { // symbolShapeMakers.line + zr Line.buildPath (no subPixelOptimize on the proxy, percent 1)
      ctx.moveTo(x, y + h / 2);
      ctx.lineTo(x + w, y + h / 2);
      break;
    }
    case 'rect': ctx.rect(x, y, w, h); break;
    case 'roundRect': {
      const r = Math.min(w, h) / 4;
      if (!r) ctx.rect(x, y, w, h);
      else roundRectPath(ctx, x, y, w, h, r);
      break;
    }
    case 'square': {
      const size = Math.min(w, h);
      if (mut.squareCentred) ctx.rect(x + (w - size) / 2, y + (h - size) / 2, size, size);
      else ctx.rect(x, y, size, size);
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
      const ay = mut.arrowCentred ? y : y + h / 2;
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

// zrender graphic/helper/subPixelOptimize.ts
function subPixelOptimize(position, lineWidth, positiveOrNegative) {
  if (!lineWidth) return position;
  const doubledPosition = Math.round(position * 2);
  return (doubledPosition + Math.round(lineWidth)) % 2 === 0
    ? doubledPosition / 2
    : (doubledPosition + (positiveOrNegative ? 1 : -1)) / 2;
}
// zr Line.buildPath with subPixelOptimize (graphic/shape/Line.ts:46-81, subPixelOptimize.ts:32-64)
function linePath(s, lineWidth, mut) {
  const ctx = new Proxy(mut);
  let x1 = s.x1;
  let y1 = s.y1;
  let x2 = s.x2;
  let y2 = s.y2;
  if (!mut.noSubPixel && lineWidth) {
    const pos = !mut.subPixelNegative;
    if (Math.round(s.x1 * 2) === Math.round(s.x2 * 2)) x1 = x2 = subPixelOptimize(s.x1, lineWidth, pos);
    if (Math.round(s.y1 * 2) === Math.round(s.y2 * 2)) y1 = y2 = subPixelOptimize(s.y1, lineWidth, pos);
  }
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  return ctx.data;
}
// zr canvas/dashStyle.ts normalizeLineDash + getLineDash (the line has no transform: lineScale 1)
function resolveDash(lineType, lineWidth, mut) {
  if (!(lineType && lineWidth > 0)) return null;
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  if (lineType === 'dashed') return mut.dashed55 ? [5 * lineWidth, 5 * lineWidth] : [4 * lineWidth, 2 * lineWidth];
  if (lineType === 'dotted') return [lineWidth];
  if (typeof lineType === 'number') return mut.dashScaled ? [lineType * lineWidth] : [lineType];
  if (isArray(lineType)) return mut.dashScaled ? lineType.map(v => v * lineWidth) : lineType;
  return null;
}

// zrender core/vector normalize, Transformable.getLocalTransform / needLocalTransform, matrix.rotate
function normalize(v) {
  const d = Math.sqrt(v[0] * v[0] + v[1] * v[1]);
  return d === 0 ? [0, 0] : [v[0] / d, v[1] / d];
}
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

// util/number.ts round
function round10(x) {
  return +(+x).toFixed(10);
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
  must(!/\{@/.test(tpl), 'the transcription does not do {@dim} templates');
  return tpl;
}
// SeriesData.getName via convertOptionIdName (util/model.ts:555-564)
function itemName(item) {
  const n = item && item.name;
  if (n == null) return '';
  return typeof n === 'string' ? n : typeof n === 'number' ? n + '' : '';
}
// zr Text normalizeStyle (graphic/Text.ts:1035-1058) and makeFont / parseFontSize (969-1009)
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
// Element.getOutsideStroke (zr Element.ts:785-799)
function outsideStroke(bg, isDark, mut) {
  if (mut.haloWhite) return 'rgba(255,255,255,1)';
  let arr = typeof bg === 'string' && echarts.color.parse(bg);
  if (!arr) arr = [255, 255, 255, 1];
  const alpha = arr[3];
  for (let i = 0; i < 3; i++) arr[i] = arr[i] * alpha + (isDark ? 0 : 255) * (1 - alpha);
  arr[3] = 1;
  return echarts.color.stringify(arr, 'rgba');
}
const LABEL_POSITIONS = ['start', 'middle', 'end', 'insideStart', 'insideStartTop', 'insideStartBottom', 'insideMiddle',
  'insideMiddleTop', 'insideMiddleBottom', 'insideEnd', 'insideEndTop', 'insideEndBottom'];

// one series' markLine picture. inp: {own, master, seriesOpt, color, seriesName, textStyle, ground, lines: [{rawLine,
// rawFrom, rawTo, from: [x, y], to: [x, y]}]} -> {z, zlevel, silent, count, lines[]}
function transcribe(inp, mut) {
  const own = inp.own;
  const master = inp.master;
  const ML = [own, master];
  const z = chainGet(ML, 'z') || 0;
  const zlevel = chainGet(ML, 'zlevel') || 0;
  const pair = v => (isArray(v) ? v : [v, v]);
  const symbolType = pair(chainGet(ML, 'symbol'));
  const symbolSize = pair(chainGet(ML, 'symbolSize'));
  const symbolRotate = pair(chainGet(ML, 'symbolRotate'));
  const symbolOffset = pair(chainGet(ML, 'symbolOffset'));
  const gts = inp.textStyle || {};
  let maxZ2 = -Infinity; // util/graphic.ts doUpdateZ, carried across the Line groups of the LineDraw group
  const lines = inp.lines.map(L => {
    const out = {};
    // ----- per-end visuals (MarkLineView.ts:395-433) -----
    const visual = (item, k) => {
      const lv = [item, own, master];
      const v = {
        symbol: retrieve2(chainGet(lv, 'symbol', true), symbolType[k]),
        symbolSize: retrieve2(chainGet(lv, 'symbolSize'), symbolSize[k]),
        symbolRotate: retrieve2(chainGet(lv, 'symbolRotate', true), symbolRotate[k]),
        symbolOffset: retrieve2(chainGet(lv, 'symbolOffset', true), symbolOffset[k]),
        symbolKeepAspect: chainGet(lv, 'symbolKeepAspect'),
      };
      const fill = chainGet(sub(lv, 'itemStyle'), 'color');
      v.fill = fill != null ? fill : inp.color;
      return v;
    };
    const vf = visual(L.rawFrom, 0);
    const vt = visual(L.rawTo, 1);
    out.value = val(L.rawLine.value);
    out.name = val(L.rawLine.name);
    const vrec = v => ({ symbol: json(v.symbol), symbolSize: json(v.symbolSize), symbolRotate: json(v.symbolRotate),
      symbolOffset: json(v.symbolOffset), symbolKeepAspect: json(v.symbolKeepAspect) });
    out.visual = { from: vrec(vf), to: vrec(vt) };
    const drawn = !(isNaN(L.from[0]) || isNaN(L.from[1]) || isNaN(L.to[0]) || isNaN(L.to[1]));
    out.drawn = drawn;
    if (!drawn) {
      out.line = out.fromSymbol = out.toSymbol = out.label = null;
      return out;
    }
    // ----- the line (MarkLineView.ts:351-381, Line.ts:124-131, 166-191, 255-260) -----
    const itemLv = [L.rawLine, own, master];
    const LS = sub(itemLv, 'lineStyle');
    let stroke = chainGet(LS, 'color');
    if (stroke == null) stroke = mut.colorSeries ? inp.color : mut.colorFromTo ? vt.fill : vf.fill;
    const lineWidth = retrieve2(chainGet(LS, 'width'), 1);
    const lsOpacity = chainGet(LS, 'opacity');
    const lineType = chainGet(LS, 'type');
    const shape = { x1: L.from[0], y1: L.from[1], x2: L.to[0], y2: L.to[1] };
    const dash = resolveDash(lineType, lineWidth, mut);
    const z2 = retrieve2(chainGet(itemLv, 'z2'), 0);
    out.line = {
      shape: { x1: hex(shape.x1), y1: hex(shape.y1), x2: hex(shape.x2), y2: hex(shape.y2) },
      shapeText: { x1: text(shape.x1), y1: text(shape.y1), x2: text(shape.x2), y2: text(shape.y2) },
      path: decode(linePath(shape, lineWidth, mut)),
      style: {
        stroke: colour(stroke), lineWidth: hex(lineWidth), lineWidthText: text(lineWidth), lineDashType: json(lineType),
        lineDash: dash ? dash.map(hex) : null, lineDashText: dash ? dash.map(text) : null,
        lineDashOffset: hex(retrieve2(chainGet(LS, 'dashOffset'), 0)), lineDashOffsetText: text(retrieve2(chainGet(LS, 'dashOffset'), 0)),
        opacity: hex(retrieve2(lsOpacity, 1)), opacityText: text(retrieve2(lsOpacity, 1)),
        lineCap: retrieve2(chainGet(LS, 'cap'), 'butt'), lineJoin: retrieve2(chainGet(LS, 'join'), null), strokeNoScale: true, fill: null,
      },
      z, z2, zlevel, invisible: false, silent: false,
    };
    // the running z2 (line, fromSymbol, toSymbol are the group's children in this order)
    const runZ2 = v => { maxZ2 = Math.max(v || 0, maxZ2); };
    if (mut.z2PerLine) maxZ2 = -Infinity;
    runZ2(z2);
    // ----- tangent / positions (Line.ts:358-419; LinePath tangentAt = normalize(x2 - x1, y2 - y1)) -----
    const fromPos = [shape.x1 * (1 - 0) + shape.x2 * 0, shape.y1 * (1 - 0) + shape.y2 * 0];
    const toPos = [shape.x1 * (1 - 1) + shape.x2 * 1, shape.y1 * (1 - 1) + shape.y2 * 1];
    const tangent = normalize([shape.x2 - shape.x1, shape.y2 - shape.y1]);
    // ----- the symbols (Line.ts:89-122, 267-292, 391-419; util/symbol.ts) -----
    const sym = (v, isTo) => {
      const type = v.symbol;
      if (!type || type === 'none') return null;
      must(typeof type === 'string' && type.indexOf('image://') !== 0 && type.indexOf('path://') !== 0, 'the transcription draws no image / path symbols');
      const size = normalizeSymbolSize(v.symbolSize);
      const off = normalizeSymbolOffset(v.symbolOffset || 0, size);
      const box = { x: -size[0] / 2 + (mut.noSymbolOffset ? 0 : off[0]), y: -size[1] / 2 + (mut.noSymbolOffset ? 0 : off[1]), width: size[0], height: size[1] };
      if (mut.sizeSquare) box.width = box.height = Math.max(size[0], size[1]);
      const isEmpty = type.indexOf('empty') === 0;
      const shapeType = isEmpty ? type.substr(5, 1).toLowerCase() + type.substr(6) : type;
      const rot = v.symbolRotate;
      let specified = rot == null || isNaN(rot) ? undefined : +rot * Math.PI / 180 || 0;
      if (mut.rotateZeroAuto && specified === 0) specified = undefined;
      let rotation;
      if (specified == null) {
        rotation = mut.noTangentRotation ? 0 : (isTo ? -1 : 1) * Math.PI / 2 - Math.atan2(tangent[1], tangent[0]);
      } else {
        rotation = specified;
      }
      const pos = isTo ? toPos : fromPos;
      const t = { x: pos[0], y: pos[1], rotation, scaleX: 1, scaleY: 1, originX: 0, originY: 0 };
      // setColor (util/symbol.ts:311-328): the line's stroke visual
      let fill = '#000'; // DEFAULT_PATH_STYLE
      let strokeC = null;
      let lw = 1;
      if (isEmpty) {
        strokeC = stroke;
        fill = mut.emptyFilled ? stroke : NEUTRAL00;
        lw = mut.emptyWidth1 ? 1 : 2;
      } else if (shapeType === 'line' && !mut.lineSymbolFill) {
        strokeC = stroke;
      } else {
        fill = stroke;
      }
      runZ2(0);
      return Object.assign({ symbol: type, shapeType, empty: isEmpty },
        { box: { x: hex(box.x), y: hex(box.y), width: hex(box.width), height: hex(box.height) },
          boxText: { x: text(box.x), y: text(box.y), width: text(box.width), height: text(box.height) } },
        nums(t, ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY']), m6(transformOf(t)),
        { path: decode(symbolPath(shapeType, box.x, box.y, box.width, box.height, mut)),
          style: { fill: colour(fill), stroke: colour(strokeC), lineWidth: hex(lw), lineWidthText: text(lw), opacity: hexOrNull(lsOpacity), opacityText: textOrNull(lsOpacity) },
          z, z2: 0, zlevel });
    };
    out.fromSymbol = sym(vf, false);
    out.toSymbol = sym(vt, true);
    // ----- the label (Line.ts:294-337, 421-523; labelStyle.ts; zr Element.updateInnerText, Text) -----
    const LB = sub(itemLv, 'label');
    const show = chainGet(LB, 'show');
    if (!show) {
      out.label = null;
      return out;
    }
    const inheritColor = stroke || NEUTRAL99;
    const rawVal = L.rawLine.value; // retrieveRawValue: getDataItemValue(merged item)
    const name = itemName(L.rawLine);
    let defaultText;
    if (mut.textNameFirst) defaultText = (name !== '' ? name : rawVal == null ? '' : isFinite(rawVal) ? round10(rawVal) : rawVal) + '';
    else defaultText = (rawVal == null ? name : isFinite(rawVal) ? (mut.textNoRound ? +rawVal : round10(rawVal)) : rawVal) + '';
    const formatter = chainGet(LB, 'formatter');
    let str;
    if (typeof formatter === 'string') str = formatTpl(formatter, { seriesName: inp.seriesName, name, value: rawVal }, mut);
    else {
      must(formatter == null, 'the transcription does not call formatter functions');
      str = defaultText;
    }
    // createTextStyle(normal, isAttached): setTokenTextStyle
    const style = {};
    let fc = chainGet(LB, 'color');
    let sc = chainGet(LB, 'textBorderColor');
    if (fc === 'inherit' || fc === 'auto') fc = inheritColor || null;
    if (sc === 'inherit' || sc === 'auto') sc = inheritColor || null;
    if (fc != null) style.fill = fc;
    if (sc != null) style.stroke = sc;
    const tbw = retrieve2(chainGet(LB, 'textBorderWidth'), gts.textBorderWidth);
    if (tbw != null) style.lineWidth = tbw;
    let opacity = retrieve2(chainGet(LB, 'opacity'), gts.opacity);
    if (opacity == null && !mut.labelOpacityOwn) opacity = lsOpacity;
    if (opacity != null) style.opacity = opacity;
    for (const k of ['fontStyle', 'fontWeight', 'fontSize', 'fontFamily']) {
      const v = mut.noGlobalFont ? chainGet(LB, k) : retrieve2(chainGet(LB, k), gts[k]);
      if (v != null) style[k] = v;
    }
    const rawAlign = chainGet(LB, 'align');
    let rawVAlign = chainGet(LB, 'verticalAlign');
    if (rawVAlign == null) rawVAlign = chainGet(LB, 'baseline');
    // createTextConfig: position (nulled by Line), rotation, offset, outsideFill
    const labelRotate = chainGet(LB, 'rotate');
    const labelOffset = chainGet(LB, 'offset');
    const outsideFill = chainGet(LB, 'color') === 'inherit' ? (inheritColor || null) : 'auto';
    // ----- placement (Line.beforeUpdate) -----
    const lp = { x: 0, y: 0, originX: 0, originY: 0, rotation: 0, scaleX: 1, scaleY: 1 };
    let distance = chainGet(LB, 'distance');
    if (!isArray(distance)) distance = [distance, distance];
    if (mut.distanceFirstOnly) distance = [distance[0], distance[0]];
    const distanceX = distance[0] * 1;
    const distanceY = distance[1] * 1;
    const d = normalize([toPos[0] - fromPos[0], toPos[1] - fromPos[1]]);
    const cp = [shape.x1 * (1 - 0.5) + shape.x2 * 0.5, shape.y1 * (1 - 0.5) + shape.y2 * 0.5];
    const dir = mut.noDir ? 1 : tangent[0] < 0 ? -1 : 1;
    let position = chainGet(LB, 'position') || 'middle';
    if (mut.unknownMiddle && LABEL_POSITIONS.indexOf(position) < 0) position = 'middle';
    if (position !== 'start' && position !== 'end') {
      let rotation = -Math.atan2(tangent[1], tangent[0]);
      if (toPos[0] < fromPos[0] && !mut.noFlip) rotation = Math.PI + rotation;
      lp.rotation = rotation;
    }
    let dy;
    let textAlign;
    let textVerticalAlign;
    switch (position) {
      case 'insideStartTop': case 'insideMiddleTop': case 'insideEndTop': case 'middle':
        dy = -distanceY; textVerticalAlign = 'bottom'; break;
      case 'insideStartBottom': case 'insideMiddleBottom': case 'insideEndBottom':
        dy = distanceY; textVerticalAlign = 'top'; break;
      default:
        dy = 0; textVerticalAlign = 'middle';
    }
    const TH = mut.noThreshold ? 0 : 0.8;
    switch (position) {
      case 'end':
        lp.x = d[0] * distanceX + toPos[0];
        lp.y = d[1] * distanceY + toPos[1];
        textAlign = d[0] > TH ? 'left' : (d[0] < -TH ? 'right' : 'center');
        textVerticalAlign = d[1] > TH ? 'top' : (d[1] < -TH ? 'bottom' : 'middle');
        break;
      case 'start':
        lp.x = -d[0] * distanceX + fromPos[0];
        lp.y = -d[1] * distanceY + fromPos[1];
        if (mut.startNotMirrored) {
          textAlign = d[0] > TH ? 'left' : (d[0] < -TH ? 'right' : 'center');
          textVerticalAlign = d[1] > TH ? 'top' : (d[1] < -TH ? 'bottom' : 'middle');
        } else {
          textAlign = d[0] > TH ? 'right' : (d[0] < -TH ? 'left' : 'center');
          textVerticalAlign = d[1] > TH ? 'bottom' : (d[1] < -TH ? 'top' : 'middle');
        }
        break;
      case 'insideStartTop': case 'insideStart': case 'insideStartBottom':
        lp.x = distanceX * dir + fromPos[0];
        lp.y = fromPos[1] + dy;
        textAlign = tangent[0] < 0 ? 'right' : 'left';
        if (!mut.noInsideOrigin) { lp.originX = -distanceX * dir; lp.originY = -dy; }
        break;
      case 'insideMiddleTop': case 'insideMiddle': case 'insideMiddleBottom': case 'middle':
        lp.x = cp[0];
        lp.y = cp[1] + dy;
        textAlign = 'center';
        if (!mut.noInsideOrigin) lp.originY = -dy;
        break;
      case 'insideEndTop': case 'insideEnd': case 'insideEndBottom':
        lp.x = -distanceX * dir + toPos[0];
        lp.y = toPos[1] + dy;
        textAlign = tangent[0] >= 0 ? 'right' : 'left';
        if (!mut.noInsideOrigin) { lp.originX = distanceX * dir; lp.originY = -dy; }
        break;
    }
    const align = normAlign((mut.userAlignIgnored ? null : rawAlign) || textAlign, mut);
    const verticalAlign = normVAlign((mut.userAlignIgnored ? null : rawVAlign) || textVerticalAlign, mut);
    // updateInnerText: copyTransform, textConfig.rotation, textConfig.offset (origin -offset: innerOrigin is false)
    const inner = { x: lp.x, y: lp.y, rotation: lp.rotation, originX: lp.originX, originY: lp.originY, scaleX: 1, scaleY: 1 };
    if (labelRotate != null && !mut.noLabelRotate) inner.rotation = labelRotate * Math.PI / 180;
    if (labelOffset) {
      inner.x += labelOffset[0];
      inner.y += labelOffset[1];
      if (!mut.offsetKeepsOrigin) { inner.originX = -labelOffset[0]; inner.originY = -labelOffset[1]; }
    }
    // outside ink
    let defFill = outsideFill;
    if (defFill == null || defFill === 'auto') defFill = inp.ground.isDark && !mut.darkIgnored ? '#ccc' : '#333';
    defFill = defFill || '#000';
    const defStroke = outsideStroke(inp.ground.background, inp.ground.isDark, mut);
    let ink = null;
    if (str !== '') {
      const useDefaultFill = !('fill' in style);
      const tf = useDefaultFill ? defFill : style.fill;
      let dlw = 0;
      let ts;
      if ('stroke' in style) ts = style.stroke;
      else if (!chainGet(LB, 'backgroundColor') && (!/* autoStroke */ true || useDefaultFill)) { dlw = 2; ts = defStroke; } else ts = null;
      const fillP = tf == null || tf === 'none' ? null : tf;
      const strokeP = ts == null || ts === 'transparent' || ts === 'none' ? null : ts;
      const lwP = strokeP ? (style.lineWidth || dlw) : null;
      const op = retrieve2(style.opacity, 1);
      ink = { fill: colour(fillP), stroke: colour(strokeP), lineWidth: hexOrNull(lwP), lineWidthText: textOrNull(lwP), opacity: hex(op), opacityText: text(op) };
    }
    const stOpacity = retrieve2(style.opacity, 1);
    const labelZ2 = isFinite(maxZ2) ? maxZ2 + 2 : 0;
    out.label = Object.assign({ text: String(str) },
      nums(lp, ['x', 'y', 'rotation', 'originX', 'originY', 'scaleX', 'scaleY']),
      { inner: nums(inner, ['x', 'y', 'rotation', 'originX', 'originY']) }, m6(transformOf(inner)),
      { align: align == null ? null : align, verticalAlign: verticalAlign == null ? null : verticalAlign,
        font: makeFont(style), fontSize: json(style.fontSize), fontWeight: json(style.fontWeight), fontStyle: json(style.fontStyle), fontFamily: json(style.fontFamily),
        style: { fill: colour(style.fill), stroke: colour(style.stroke), lineWidth: hexOrNull(style.lineWidth), lineWidthText: textOrNull(style.lineWidth), opacity: hex(stOpacity), opacityText: text(stOpacity) },
        inkDefault: { fill: defFill, stroke: defStroke, autoStroke: true }, ink,
        z, z2: labelZ2, zlevel, silent: !!chainGet(LB, 'silent') });
    return out;
  });
  const silent = !!(chainGet(ML, 'silent') || (inp.seriesOpt && inp.seriesOpt.silent));
  return { z: json(z), zlevel: json(zlevel), silent, count: inp.lines.length, lines };
}

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const firstOf = v => (isArray(v) ? v[0] : v);
function slaveOf(ec, sm) {
  const master = ec.getComponent('markLine');
  if (!master) return null;
  const MM = Object.getPrototypeOf(master.constructor);
  must(typeof MM.getMarkerModelFromSeries === 'function', 'MarkerModel.getMarkerModelFromSeries not reachable');
  return MM.getMarkerModelFromSeries(sm, 'markLine') || null;
}
function innerFromTo(slave) {
  for (const k of Object.keys(slave)) {
    if (k.startsWith('__ec_inner_') && slave[k] && slave[k].from && slave[k].to) return slave[k];
  }
  return null;
}
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  must(Array.isArray(el.path.data), 'a path proxy was made static');
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};

// the markLine <path> elements of the SVG: [{si, nums, dash, width}]
function svgLinePaths(svg) {
  const out = [];
  const re = /<path\b([^>]*)>/g;
  let m;
  while ((m = re.exec(svg))) {
    const a = m[1];
    const g = n => { const mm = new RegExp('(?:^|\\s)' + n + '="([^"]*)"').exec(a); return mm ? mm[1] : null; };
    const d = g('d');
    if (!d || !/^M[^A-Za-z]*(L[^A-Za-z]*)?$/.test(d)) continue; // a zero-length L is dropped by SVGPathRebuilder
    const si = g('ecmeta_series_index');
    out.push({ si: si == null ? null : +si, nums: d.replace(/[ML]/g, ' ').trim().split(/[\s,]+/).map(Number), dash: g('stroke-dasharray'), width: g('stroke-width'), used: 0 });
  }
  return out;
}

function readElementCommon(el) {
  return { z: el.z, z2: el.z2, zlevel: el.zlevel };
}
function readSymbol(el, typeVisual) {
  if (!el) return null;
  must(el.shape && typeof el.shape.symbolType === 'string', 'a symbol element that is not a SymbolClz (' + el.type + ')');
  const s = el.style;
  const sh = el.shape;
  return Object.assign({ symbol: typeVisual, shapeType: sh.symbolType, empty: !!el.__isEmptyBrush },
    { box: { x: hex(sh.x), y: hex(sh.y), width: hex(sh.width), height: hex(sh.height) },
      boxText: { x: text(sh.x), y: text(sh.y), width: text(sh.width), height: text(sh.height) } },
    nums(el, ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY']), m6(el.transform),
    { path: decode(pathOf(el)),
      style: { fill: colour(s.fill), stroke: colour(s.stroke), lineWidth: hex(s.lineWidth), lineWidthText: text(s.lineWidth), opacity: hexOrNull(s.opacity), opacityText: textOrNull(s.opacity) } },
    readElementCommon(el));
}
function readLabel(t) {
  if (!t || t.ignore) return null;
  const s = t.style;
  const spans = t.childrenRef().filter(c => c.type === 'tspan');
  must(t.childrenRef().length === spans.length && spans.length <= 1, 'a label with ' + t.childrenRef().length + ' children');
  const txt = s.text == null ? '' : String(s.text);
  must((spans.length === 1) === (txt !== ''), 'a label TSpan / text mismatch');
  let ink = null;
  if (spans.length) {
    const ss = spans[0].style;
    const lw = ss.stroke ? ss.lineWidth : null;
    ink = { fill: colour(ss.fill), stroke: colour(ss.stroke || null), lineWidth: hexOrNull(lw), lineWidthText: textOrNull(lw), opacity: hex(ss.opacity), opacityText: text(ss.opacity) };
    must(ss.font === s.font, 'the TSpan font differs from the label font');
  }
  const it = t.innerTransformable;
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  return Object.assign({ text: txt },
    nums(t, ['x', 'y', 'rotation', 'originX', 'originY', 'scaleX', 'scaleY']),
    { inner: nums(it, ['x', 'y', 'rotation', 'originX', 'originY']) }, m6(t.transform),
    { align: s.align == null ? null : s.align, verticalAlign: s.verticalAlign == null ? null : s.verticalAlign,
      font: s.font, fontSize: json(s.fontSize), fontWeight: json(s.fontWeight), fontStyle: json(s.fontStyle), fontFamily: json(s.fontFamily),
      style: { fill: has('fill') ? colour(s.fill) : null, stroke: has('stroke') ? colour(s.stroke) : null,
        lineWidth: has('lineWidth') ? hexOrNull(s.lineWidth) : null, lineWidthText: has('lineWidth') ? textOrNull(s.lineWidth) : null,
        opacity: hex(s.opacity), opacityText: text(s.opacity) },
      inkDefault: { fill: ds.fill, stroke: ds.stroke, autoStroke: ds.autoStroke }, ink },
    readElementCommon(t), { silent: !!t.silent });
}

// every drawn markLine of one series: {block, rows, tags, inputs}
function readSeries(chart, sm, svgPaths) {
  const ec = chart.getModel();
  const slave = slaveOf(ec, sm);
  must(slave, 'no slave markLine model for series ' + sm.seriesIndex);
  const lineData = slave.getData();
  const ft = innerFromTo(slave);
  must(ft, 'markLine from/to data not found');
  const view = chart.getViewOfComponentModel(ec.getComponent('markLine'));
  const draw = view.markerGroupMap.get(sm.id);
  must(draw && draw.group, 'no markLine group for series ' + sm.seriesIndex);
  const group = draw.group;
  for (let p = group; p; p = p.parent) must(!p.transform || p.transform.join() === '1,0,0,1,0,0', 'a transformed ancestor');
  const rows = [];
  const tags = [];
  const inputs = [];
  const drawnGroups = [];
  for (let i = 0; i < lineData.count(); i++) {
    const rawLine = lineData.getRawDataItem(i);
    tags.push(rawLine[TAG]);
    const from = ft.from.getItemLayout(i);
    const to = ft.to.getItemLayout(i);
    const lay = lineData.getItemLayout(i);
    must(lay[0] === from && lay[1] === to, 'the line layout is not [from, to]');
    inputs.push({ rawLine: zrClone(rawLine), rawFrom: zrClone(ft.from.getRawDataItem(i)), rawTo: zrClone(ft.to.getRawDataItem(i)), from: from.slice(), to: to.slice() });
    const ev = (d, k) => ({ symbol: json(d.getItemVisual(i, 'symbol')), symbolSize: json(d.getItemVisual(i, 'symbolSize')),
      symbolRotate: json(d.getItemVisual(i, 'symbolRotate')), symbolOffset: json(d.getItemVisual(i, 'symbolOffset')),
      symbolKeepAspect: json(d.getItemVisual(i, 'symbolKeepAspect')) });
    const row = { value: val(rawLine.value), name: val(rawLine.name), visual: { from: ev(ft.from), to: ev(ft.to) } };
    const g = lineData.getItemGraphicEl(i);
    const hasNaN = isNaN(from[0]) || isNaN(from[1]) || isNaN(to[0]) || isNaN(to[1]);
    row.drawn = !!g;
    must(row.drawn === !hasNaN, 'drawn vs NaN end point at line ' + i);
    if (!g) {
      row.line = row.fromSymbol = row.toSymbol = row.label = null;
      rows.push(row);
      continue;
    }
    drawnGroups.push(g);
    must(!g.transform || g.transform.join() === '1,0,0,1,0,0', 'a transformed Line group');
    const line = g.childOfName('line');
    const fs_ = g.childOfName('fromSymbol');
    const ts_ = g.childOfName('toSymbol');
    const kids = g.childrenRef();
    must(kids[0] === line && kids.length === 1 + !!fs_ + !!ts_ && (!fs_ || kids[1] === fs_) && (!ts_ || kids[kids.length - 1] === ts_), 'the Line group children');
    const ls = line.style;
    const sh = line.shape;
    must(sh.x1 === from[0] && sh.y1 === from[1] && sh.x2 === to[0] && sh.y2 === to[1] && sh.percent === 1 && isNaN(sh.cpx1), 'the line shape is not the layout');
    const lpath = pathOf(line);
    // the SVG path of this line: series index + the d numbers (4 decimals)
    const zeroLen = lpath[4] === lpath[1] && lpath[5] === lpath[2];
    const cands = svgPaths.filter(p => p.si === sm.seriesIndex && (p.nums.length === 4 || (zeroLen && p.nums.length === 2))
      && p.nums.every((v, k) => Math.abs(v - lpath[[1, 2, 4, 5][k]]) <= 0.05 + 1e-9)); // the SSR painter compresses d to 1 decimal
    must(cands.length >= 1, 'no SVG <path> for line ' + i + ' of series ' + sm.seriesIndex);
    must(cands.every(c => c.dash === cands[0].dash && c.width === cands[0].width), 'ambiguous SVG <path> for line ' + i);
    cands.forEach(c => { c.used++; });
    const dash = cands[0].dash == null ? null : cands[0].dash.split(',').map(Number);
    const sw = cands[0].width == null ? 1 : +cands[0].width;
    must(sw === ls.lineWidth, 'the SVG stroke-width ' + sw + ' is not the style lineWidth ' + ls.lineWidth);
    row.line = {
      shape: { x1: hex(sh.x1), y1: hex(sh.y1), x2: hex(sh.x2), y2: hex(sh.y2) },
      shapeText: { x1: text(sh.x1), y1: text(sh.y1), x2: text(sh.x2), y2: text(sh.y2) },
      path: decode(lpath),
      style: {
        stroke: colour(ls.stroke), lineWidth: hex(ls.lineWidth), lineWidthText: text(ls.lineWidth), lineDashType: json(ls.lineDash),
        lineDash: dash ? dash.map(hex) : null, lineDashText: dash ? dash.map(text) : null,
        lineDashOffset: hex(ls.lineDashOffset), lineDashOffsetText: text(ls.lineDashOffset),
        opacity: hex(ls.opacity), opacityText: text(ls.opacity),
        lineCap: ls.lineCap == null ? null : ls.lineCap, lineJoin: ls.lineJoin == null ? null : ls.lineJoin, strokeNoScale: !!ls.strokeNoScale, fill: ls.fill == null ? null : ls.fill,
      },
      z: line.z, z2: line.z2, zlevel: line.zlevel, invisible: !!line.invisible, silent: !!line.silent,
    };
    row.fromSymbol = readSymbol(fs_, ft.from.getItemVisual(i, 'symbol'));
    row.toSymbol = readSymbol(ts_, ft.to.getItemVisual(i, 'symbol'));
    row.label = readLabel(g.getTextContent());
    rows.push(row);
  }
  must(group.childrenRef().length === drawnGroups.length && group.childrenRef().every((c, k) => c === drawnGroups[k]), 'the LineDraw group children are not the drawn lines in order');
  const block = { z: json(slave.get('z') || 0), zlevel: json(slave.get('zlevel') || 0), silent: !!group.silent, count: lineData.count() };
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
    const d = s && s.markLine && s.markLine.data;
    if (!isArray(d)) continue;
    d.forEach((el, i) => {
      if (isArray(el)) el.forEach(e => { if (isObject(e)) e[TAG] = i; });
      else if (isObject(el)) el[TAG] = i;
    });
  }
  return option;
}
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const lined = option => seriesArray(option).map((s, i) => (s && s.markLine && s.markLine.data ? i : -1)).filter(i => i >= 0);

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  const input = JSON.parse(optionText);
  const masterOpt = zrMerge(zrClone(firstOf(input.markLine) || {}), ML_DEFAULTS);
  const marked = lined(input);
  must(marked.length, def.id + ': no series with markLine');
  const base = runChart(JSON.parse(optionText), (chart, svg) => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const svgPaths = svgLinePaths(svg);
    const series = marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      const data = sm.getData();
      const filtered = ec.isSeriesFiltered(sm);
      const c = data.getVisual('style')[data.getVisual('drawType')];
      const opt = seriesArray(input)[si];
      const sr = { seriesIndex: si, name: opt.name == null ? null : String(opt.name), type: sm.subType, filtered,
        color: typeof c === 'string' ? c : null, seriesName: opt.name == null ? null : sm.name, markLine: null };
      if (filtered) return sr;
      const r = readSeries(chart, sm, svgPaths);
      const inp = { own: opt.markLine, master: masterOpt, seriesOpt: opt, color: sr.color, seriesName: sr.seriesName,
        textStyle: ec.option.textStyle, ground, lines: r.inputs };
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
      for (const g of GUARDS) side[key].muts[g.id] = run(g.mut);
      sr.markLine = r;
      return sr;
    });
    // every markLine <path> of the SVG belongs to exactly one recorded line (series with a markLine)
    return { ground, textStyle, series, svgPaths };
  });

  const tagged = runChart(tagOption(JSON.parse(optionText)), (chart, svg) => {
    const ec = chart.getModel();
    const svgPaths = svgLinePaths(svg);
    return marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      return ec.isSeriesFiltered(sm) ? null : readSeries(chart, sm, svgPaths);
    });
  });

  const rec = { id: def.id, note: def.note, width: W, height: H, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    nan: !!def.nan, ground: base.ground, textStyle: base.textStyle, series: [] };
  rec.series = base.series.map((sr, n) => {
    const b = sr.markLine;
    if (!b) return sr;
    const t = tagged[n];
    must(t && JSON.stringify(t.rows) === JSON.stringify(b.rows) && JSON.stringify(t.block) === JSON.stringify(b.block),
      def.id + '/' + sr.seriesIndex + ': the tagged run differs from the verbatim run');
    const nIn = seriesArray(input)[sr.seriesIndex].markLine.data.length;
    for (let j = 0; j < t.tags.length; j++) {
      must(Number.isInteger(t.tags[j]) && t.tags[j] >= 0 && t.tags[j] < nIn && (j === 0 || t.tags[j] > t.tags[j - 1]),
        def.id + '/' + sr.seriesIndex + ': tags ' + JSON.stringify(t.tags));
    }
    const items = [];
    for (let i = 0; i < nIn; i++) {
      const j = t.tags.indexOf(i);
      items.push(Object.assign({ index: i, survived: j >= 0, dataIndex: j >= 0 ? j : null }, j >= 0 ? b.rows[j] : {}));
    }
    return Object.assign({}, sr, { markLine: Object.assign({}, b.block, { items }) });
  });
  return rec;
}

// ============================================================================
// The cases
// ============================================================================
const G = { left: 80.5, right: 60.25, top: 50.75, bottom: 70.4 };
const PTS = [[1, 2], [3, 7], [5, 4], [8, 9]];
// value x value grid 0..10 x 0..10 with a fractional rect (x = 80.5 + 65.925 v, y = 529.6 - 47.885 v)
const vv = (markLine, extra, seriesExtra) => Object.assign({ animation: false, grid: G, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [Object.assign({ type: 'scatter', name: 's0', data: PTS, markLine }, seriesExtra || {})] }, extra || {});
const pairC = (a, b, extraA, extraB) => [Object.assign({ coord: a }, extraA || {}), Object.assign({ coord: b }, extraB || {})];
const pairP = (a, b, extraA, extraB) => [Object.assign({ x: a[0], y: a[1] }, extraA || {}), Object.assign({ x: b[0], y: b[1] }, extraB || {})];
const POS = LABEL_POSITIONS;
// one line per label position; `ends(i)` gives [from, to] coords; the start item carries the position and name
const posLines = (ends, extraStart) => POS.map((p, i) => {
  const e = ends(i);
  return pairC(e[0], e[1], Object.assign({ name: p, label: { position: p } }, extraStart || {}));
});
const WEEK = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const D7 = [120, 132, 101, 134, 90, 230, 210];
const OHLC = [[20, 34, 10, 38], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42], [15, 27, 12, 29], [27, 40, 25, 47]];

const CASES = [
  // ----- defaults, directions -----
  { id: 'D1', note: "defaults: {yAxis: 3.3} (horizontal, from = left), {xAxis: 6.7} (vertical, from = BOTTOM), 1D average: circle + arrow both 8 x 16 (the [8,16] symbolSize quirk: the ARRAY reaches both ends), the arrow's TIP on the end point (the shape maker centres (x, y) and Arrow.buildPath draws its tip there), the circle r = min(8,16)/2 = 4 at the box centre; dashed [4, 2]; label 'end' at distance 5 (left / middle on the horizontal, center / bottom on the vertical); default text = the value",
    option: vv({ data: [{ yAxis: 3.3 }, { xAxis: 6.7 }, { type: 'average' }] }) },
  { id: 'D2', note: 'diagonal pairs in all four directions (up-right, up-left, down-right, down-left): symbol rotation from atan2 of the tangent (from: PI/2 - a, to: -PI/2 - a), end label align from d with the 0.8 threshold (all four are |d.x| < 0.8 -> center; |d.y| < 0.8 -> middle)',
    option: vv({ data: [pairC([1, 1], [4, 6]), pairC([9, 1], [6, 6]), pairC([1, 9], [4, 4]), pairC([9, 9], [6, 4])] }) },
  { id: 'D3', note: "shallow and steep diagonals (px ends) with 'end' and 'start' labels: d.x = 0.8 exactly (80 / 100) is NOT > 0.8 -> center; 0.8 + e -> left; d.y = -0.8 exactly -> middle; 'start' mirrors align / valign",
    option: vv({ data: [pairP([100, 300], [180, 240]), pairP([100, 300], [181, 240]), pairP([300, 300], [360, 220]), pairP([300, 300], [359, 220]),
      pairP([500, 300], [420, 240], { label: { position: 'start' } }), pairP([500, 200], [560, 280], { label: { position: 'start' } }), pairP([600, 400], [700, 400.5], { label: { position: 'start' } })] }) },
  { id: 'D4', note: 'inverse x and inverse y axes: a 1D yAxis line runs right-to-left (from = getExtent()[0] = the RIGHT end), an xAxis line top-to-bottom; arrows / labels follow; a coord pair',
    option: vv({ data: [{ yAxis: 3.3 }, { xAxis: 6.7 }, pairC([2, 2], [7, 5])] }, { xAxis: { type: 'value', min: 0, max: 10, inverse: true }, yAxis: { type: 'value', min: 0, max: 10, inverse: true } }) },
  { id: 'D5', note: 'a zero-length line (both ends the same px point): tangent normalize(0, 0) = [0, 0], atan2(0, 0) = 0 -> from symbol rotation PI/2, to -PI/2; end label d = [0, 0] -> center / middle at the point itself; a middle label rotation -0 (needs no transform term)',
    option: vv({ data: [pairP([200, 200], [200, 200]), pairP([300, 250], [300, 250], { label: { position: 'insideMiddleTop' } })] }) },
  { id: 'D6', note: "px / percent ends ('20%' of 800, '70%' of 600) with fractional px: a diagonal left untouched by subPixelOptimize; a near-vertical px line whose x differ by 0.1 (round(2 x) equal: 600 / 600) is SNAPPED to one x (subPixelOptimize of x1 for both): the drawn line is exactly vertical while the label / symbol rotation use the un-snapped shape; the same for a near-horizontal one (y 150.1 / 150.2)",
    option: vv({ data: [pairP(['20%', 100.3], [600.7, '70%']), pairP([300.1, 100], [300.2, 400]), pairP([400.4, 150.1], [500.6, 150.2])] }) },
  // ----- sub-pixel and widths -----
  { id: 'W1', note: 'horizontal lines at fractional y with lineWidth 1 / 2 / 3 / 0 / 0.4 / 1.5 (subPixelOptimize(y, w, true): (round(2y) + round(w)) even -> round(2y)/2 else (round(2y) + 1)/2; width 0 -> no snap and no dash; round(0.4) = 0 acts like an even width)',
    option: vv({ data: [1.3, 2.3, 3.3, 4.3, 5.3, 6.3].map((y, i) => ({ yAxis: y, lineStyle: { width: [1, 2, 3, 0, 0.4, 1.5][i] } })) }) },
  { id: 'W2', note: 'vertical lines at fractional x with lineWidth 1 / 2 / 3, and a pair whose y differ by 0.1 px (snapped horizontal); dotted width 2 -> [2]; solid',
    option: vv({ data: [1.33, 2.77, 4.05].map((x, i) => ({ xAxis: x, lineStyle: { width: i + 1, type: i === 2 ? 'solid' : 'dotted' } })).concat([pairP([120.3, 333.3], [520.9, 333.4], { lineStyle: { width: 2 } })]) }) },
  // ----- dash / style -----
  { id: 'S1', note: "lineStyle.type per line: 'solid' (null dash), 'dashed' width 1 / 2 / 3 ([4w, 2w]), 'dotted' width 3 ([w]), a number 4 ([4], NOT scaled), an array [5, 3] at width 3 (as is, NOT scaled), dashOffset 2.6 (the style keeps 2.6; SVG prints 3), opacity 0.4 (line, symbols AND the label default opacity), cap 'round', join 'bevel', a colour",
    option: vv({ data: [
      { yAxis: 1, lineStyle: { type: 'solid' } }, { yAxis: 2, lineStyle: { width: 1 } }, { yAxis: 3, lineStyle: { width: 2 } }, { yAxis: 4, lineStyle: { width: 3 } },
      { yAxis: 5, lineStyle: { type: 'dotted', width: 3 } }, { yAxis: 6, lineStyle: { type: 4, width: 2 } }, { yAxis: 7, lineStyle: { type: [5, 3], width: 3 } },
      { yAxis: 8, lineStyle: { type: 'dashed', width: 2, dashOffset: 2.6 } }, { yAxis: 9, lineStyle: { opacity: 0.4, color: '#c00' } },
      { xAxis: 9, lineStyle: { cap: 'round', join: 'bevel', width: 4, type: 'solid' } }] }) },
  { id: 'S2', note: 'series-level markLine lineStyle {color, width 2, type dotted, opacity 0.7} inherited by every line; one item overrides colour, one sets type solid',
    option: vv({ lineStyle: { color: '#08f', width: 2, type: 'dotted', opacity: 0.7 }, data: [{ yAxis: 3 }, { yAxis: 5, lineStyle: { color: '#f80' } }, { yAxis: 7, lineStyle: { type: 'solid' } }] }) },
  // ----- colour fallbacks -----
  { id: 'C1', note: "colour chain: lineStyle.color (item) wins; else the FROM end's itemStyle.color (start item, series markLine itemStyle, top-level markLine itemStyle), else the series colour; an itemStyle.color on the END item only is ignored; a lineStyle.color on the END item only IS used (the merged line item takes it from the end when the start has none)",
    option: vv({ data: [
      pairC([1, 1], [4, 2], { lineStyle: { color: '#101010' } }), pairC([1, 3], [4, 4], { itemStyle: { color: '#00aa00' } }), pairC([1, 5], [4, 6], null, { itemStyle: { color: '#aa00aa' } }),
      pairC([1, 7], [4, 8], null, { lineStyle: { color: '#0000aa' } }), pairC([6, 1], [9, 2])] }, null, { itemStyle: { color: '#123456' } }) },
  { id: 'C2', note: 'series markLine itemStyle.color (feeds the from-end fill -> the line colour) and a second series without it (palette 1); a top-level markLine itemStyle colour reaching a third series',
    option: Object.assign(vv({ itemStyle: { color: '#aa0000' }, data: [{ yAxis: 3 }] }), {
      series: [{ type: 'scatter', name: 's0', data: PTS, markLine: { itemStyle: { color: '#aa0000' }, data: [{ yAxis: 3 }] } },
        { type: 'scatter', name: 's1', data: PTS, markLine: { data: [{ yAxis: 5 }] } },
        { type: 'line', name: 's2', data: PTS, markLine: { data: [{ yAxis: 7 }] } }],
      markLine: { itemStyle: { color: '#777777' } } }) },
  { id: 'C3', note: "candlestick: the series colour is its DEFAULT itemStyle.color '#eb5454' (not the palette); a bar series beside it (palette)",
    option: { animation: false, xAxis: { type: 'category', data: WEEK.slice(0, 6) }, yAxis: { type: 'value' },
      series: [{ type: 'candlestick', data: OHLC, markLine: { data: [{ type: 'max', valueDim: 'highest' }, [{ type: 'min', valueDim: 'lowest' }, { type: 'max', valueDim: 'highest' }]] } },
        { type: 'bar', data: [5, 20, 36, 10, 10, 20], markLine: { data: [{ type: 'average' }] } }] } },
  // ----- symbols -----
  { id: 'Y1', note: "every symbol type on a diagonal: rect / triangle, diamond / pin (pin: arc through modPI2), roundRect (r = min/4, four arcs) / square (min side, at the box's TOP-LEFT, not centred), line (stroked, fill stays the default '#000') / 'star' (unknown: drawn as rect, shapeType 'star'), 'none' / arrow, arrow / 'none', '' / circle ('' = no symbol)",
    option: vv({ data: [pairC([1, 1], [3, 2], { symbol: 'rect' }, { symbol: 'triangle' }), pairC([1, 3], [3, 4], { symbol: 'diamond' }, { symbol: 'pin' }),
      pairC([1, 5], [3, 6], { symbol: 'roundRect' }, { symbol: 'square' }), pairC([1, 7], [3, 8], { symbol: 'line' }, { symbol: 'star' }),
      pairC([5, 1], [7, 2], { symbol: 'none' }, { symbol: 'arrow' }), pairC([5, 3], [7, 4], { symbol: 'arrow' }, { symbol: 'none' }), pairC([5, 5], [7, 6], { symbol: '' }, { symbol: 'circle' })] }) },
  { id: 'Y2', note: "empty symbols: stroke = the line colour, fill '#fff', lineWidth 2 (emptyCircle / emptyArrow / emptyRect / emptyTriangle / emptyDiamond / emptyLine), with a line colour and opacity 0.5 (symbol opacity follows the line)",
    option: vv({ data: [pairC([1, 1], [3, 2], { symbol: 'emptyCircle' }, { symbol: 'emptyArrow' }), pairC([1, 4], [3, 5], { symbol: 'emptyRect', lineStyle: { color: '#0a0', opacity: 0.5 } }, { symbol: 'emptyTriangle' }),
      pairC([1, 7], [3, 8], { symbol: 'emptyDiamond' }, { symbol: 'emptyLine' })] }) },
  { id: 'Y3', note: "symbol sizes: series scalar 10 (both ends 10 x 10); an item [6, 14]; [10] (height 0: normalizeSymbolSize gives [10, 0], circle r 0); 0; the string '14' (+'14' = 14)",
    option: vv({ symbolSize: 10, data: [{ yAxis: 2 }, pairC([1, 4], [3, 5], { symbolSize: [6, 14] }, { symbolSize: [10] }), pairC([1, 7], [3, 8], { symbolSize: 0 }, { symbolSize: '14' })] }) },
  { id: 'Y4', note: "symbolRotate: series 30 (both ends, degrees; the tangent rotation is then NOT applied), an item 0 (specified: no tangent rotation -- the arrow points up), -45, 'abc' (isNaN -> auto); symbolOffset [4, '50%'] (percent of the height), ['-25%'] (y falls back to x's value, percent of the HEIGHT), 5 (both); symbolKeepAspect true (ignored by the built-in shapes)",
    option: vv({ symbolRotate: 30, data: [{ yAxis: 2 }, pairC([1, 4], [3, 5], { symbolRotate: 0 }, { symbolRotate: -45 }), pairC([1, 7], [3, 8], { symbolRotate: 'abc' }, { symbolRotate: 'abc' }),
      pairC([5, 4], [7, 5], { symbolRotate: 'abc', symbolOffset: [4, '50%'] }, { symbolRotate: 'abc', symbolOffset: ['-25%'] }),
      pairC([5, 7], [7, 8], { symbolRotate: 'abc', symbolOffset: 5, symbolKeepAspect: true }, { symbolRotate: 'abc', symbol: 'rect', symbolKeepAspect: true })] }) },
  { id: 'Y5', note: "series-level symbol ['none', 'circle'] and symbolOffset [0, 3] pairs, top-level markLine symbolSize 12 under both series",
    option: Object.assign(vv({ symbol: ['none', 'circle'], symbolOffset: [0, 3], data: [{ xAxis: 3 }, pairC([5, 2], [8, 6])] }), {
      series: [{ type: 'scatter', name: 's0', data: PTS, markLine: { symbol: ['none', 'circle'], symbolOffset: [0, 3], data: [{ xAxis: 3 }, pairC([5, 2], [8, 6])] } },
        { type: 'scatter', name: 's1', data: PTS, markLine: { data: [{ yAxis: 8 }] } }], markLine: { symbolSize: 12 } }) },
  // ----- label positions -----
  { id: 'LP1', note: 'every label position on HORIZONTAL left-to-right lines, distance 7 (series level): inside* use dir 1, align left (start) / right (end), the origin pivots (-distX, -dy) / (0, -dy) / (distX, -dy); rotation -atan2(0, 1) = -0',
    option: vv({ label: { distance: 7 }, data: posLines(i => [[1, 0.5 + i * 0.75], [9, 0.5 + i * 0.75]]) }) },
  { id: 'LP2', note: 'every label position on horizontal RIGHT-TO-LEFT lines, distance [12, 4]: dir -1, rotation PI + (-atan2(0, -1)) = PI - PI = 0, start / end aligns mirrored',
    option: vv({ label: { distance: [12, 4] }, data: posLines(i => [[9, 0.5 + i * 0.75], [1, 0.5 + i * 0.75]]) }) },
  { id: 'LP3', note: 'every label position on VERTICAL upward lines (distance 6): d.y = -1 -> end valign bottom, start top; rotation -atan2(-1, 0) = PI/2',
    option: vv({ label: { distance: 6 }, data: posLines(i => [[0.5 + i * 0.75, 1], [0.5 + i * 0.75, 9]]) }) },
  { id: 'LP4', note: 'every label position on vertical DOWNWARD lines (distance [3, 9])',
    option: vv({ label: { distance: [3, 9] }, data: posLines(i => [[0.5 + i * 0.75, 9], [0.5 + i * 0.75, 1]]) }) },
  { id: 'LP5', note: 'every label position on up-right DIAGONALS (distance [12, 4]): rotated labels, the inside origins pivot about the line point',
    option: vv({ label: { distance: [12, 4] }, data: posLines(i => [[0.5 + (i % 4) * 2.4, 0.5 + Math.floor(i / 4) * 3.2], [2.3 + (i % 4) * 2.4, 3 + Math.floor(i / 4) * 3.2]]) }) },
  { id: 'LP6', note: 'every label position on down-LEFT diagonals (right-to-left: rotation + PI, dir -1, inside aligns flip), distance 8',
    option: vv({ label: { distance: 8 }, data: posLines(i => [[2.3 + (i % 4) * 2.4, 3 + Math.floor(i / 4) * 3.2], [0.5 + (i % 4) * 2.4, 0.5 + Math.floor(i / 4) * 3.2]]) }) },
  { id: 'LP7', note: "an UNKNOWN label position ('top', 'inside', 'left'): no case of the switch places it -> the label sits at the ORIGIN (0, 0) of the chart, rotated like a middle label, align unset, valign middle; a position '' (-> 'middle')",
    option: vv({ data: [pairC([2, 2], [6, 5], { name: 'top', label: { position: 'top' } }), pairC([2, 5], [6, 5], { name: 'inside', label: { position: 'inside' } }), { yAxis: 8, label: { position: 'left' } },
      { yAxis: 9, label: { position: '' } }] }) },
  // ----- label align, rotate, offset, show -----
  { id: 'LA1', note: "author label align / verticalAlign win over the computed ones: align 'right'; 'middle' (normalized to 'center'); 'bogus' (-> 'left'); verticalAlign 'top'; 'center' (-> 'middle'); baseline 'bottom' (the verticalAlign fallback); at insideStart and end",
    option: vv({ data: [{ yAxis: 1, label: { align: 'right', position: 'insideStart' } }, { yAxis: 2, label: { align: 'middle' } }, { yAxis: 3, label: { align: 'bogus', position: 'insideEndTop' } },
      { yAxis: 4, label: { verticalAlign: 'top' } }, { yAxis: 5, label: { verticalAlign: 'center', position: 'insideMiddleBottom' } }, { yAxis: 6, label: { baseline: 'bottom' } },
      pairC([2, 7], [5, 9.5], { label: { align: 'left', verticalAlign: 'bottom', position: 'insideStartTop' } })] }) },
  { id: 'LA2', note: "label.rotate (degrees) and label.offset reach the label through its textConfig and are applied in updateInnerText AFTER Line.beforeUpdate: rotate REPLACES the line-derived rotation (also for 'end' / 'start'); offset adds to x / y and OVERRIDES the inside origin with (-offset) -- the element's own x / y / origin stay Line's, the inner transformable carries the result",
    option: vv({ data: [pairC([1, 1], [4, 3], { label: { position: 'insideStart', rotate: 30 } }), pairC([1, 4], [4, 6], { label: { position: 'insideEndTop', offset: [10, -5] } }),
      pairC([1, 7], [4, 9], { label: { position: 'end', rotate: -90, offset: [3, 4] } }), pairC([6, 1], [9, 3], { label: { position: 'middle', offset: [0, 6] } }),
      pairC([6, 5], [9, 7], { label: { position: 'start', rotate: 0 } })] }) },
  { id: 'LA3', note: "label.show false on the series markLine: no label (the text element exists but is ignored: recorded null); a 1D item turns it back on; a pair whose START item says show true; a pair whose END item alone says show true is shown too (the merged line item takes label from the end when the start has none)",
    option: vv({ label: { show: false }, data: [{ yAxis: 2 }, { yAxis: 4, label: { show: true } }, pairC([2, 6], [6, 8], { name: 'start-on', label: { show: true } }),
      pairC([2, 8], [6, 9.5], { name: 'end-on' }, { label: { show: true } })] }) },
  // ----- label text -----
  { id: 'T1', note: "default texts at markLine precision 12: a 1D average 4.071428571428571 -> toFixed(12) 4.071428571429 -> round(v, 10) '4.0714285714'; {yAxis: 3.3} -> '3.3'; {yAxis: 10/3} -> 3.333333333333 -> '3.3333333333'; a pair with a name only -> the name, a pair with neither -> '' (label element with no TSpan), value '075.50' (a string: isFinite -> round -> '75.5'), a numeric name 5 -> '5', a boolean name -> '' , a non-numeric value 'abc' -> 'abc'",
    option: vv({ precision: 12, data: [{ type: 'average' }, { yAxis: 3.3 }, { yAxis: 10 / 3 }, pairC([1, 1], [2, 2], { name: 'only-name' }), pairC([3, 1], [4, 2]),
      pairC([5, 1], [6, 2], { value: '075.50' }), pairC([7, 1], [8, 2], { name: 5 }), pairC([1, 5], [2, 6], { name: true }), pairC([3, 5], [4, 6], { value: 'abc', name: 'n' })] },
    null, { data: [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [6, 6], [7, 7.5]] }) },
  { id: 'T2', note: "formatter templates on a NAMED series: '{a}|{b}|{c}'; '{c} and {c}' (formatTpl replaces the FIRST occurrence only: the second stays literal); '{d}' (no $var: literal); '{c}' with no value -> 'undefined'; '{b}' with no name -> ''; '{a0}{b0}{c0}' (the indexed forms); a formatter on the series markLine inherited",
    option: vv({ label: { formatter: 'S:{b}' }, data: [{ yAxis: 2, name: 'two', label: { formatter: '{a}|{b}|{c}' } }, { yAxis: 3, label: { formatter: '{c} and {c}' } },
      { yAxis: 4, label: { formatter: '{d}' } }, pairC([1, 5], [3, 6], { label: { formatter: '<{c}>' } }), pairC([4, 5], [6, 6], { label: { formatter: '[{b}]' } }),
      { yAxis: 7, name: 'n7', label: { formatter: '{a0}{b0}{c0}' } }, { yAxis: 8, name: 'inherited' }] }, null, { name: 'Series A' }) },
  { id: 'T3', note: '1D statistics on a category line with a series name: min / max / median default texts (the precision-rounded statistic) and average 145.29 at the default precision 2, a category xAxis line prints the category',
    option: { animation: false, xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'value' },
      series: [{ type: 'line', name: 'L', data: D7, markLine: { data: [{ type: 'min' }, { type: 'max' }, { type: 'average' }, { type: 'median' }, { xAxis: 'Wed' }, { xAxis: 5 }] } }] } },
  // ----- label font / colour / ink -----
  { id: 'F1', note: "label fonts: fontSize 16, fontWeight 'bold', fontFamily 'serif', fontStyle 'italic' per item; fontSize '18px' (kept as is); the rest from the global textStyle (option textStyle {fontSize: 13, fontWeight: 600} over the defaults)",
    option: vv({ data: [{ yAxis: 2, label: { fontSize: 16 } }, { yAxis: 3, label: { fontWeight: 'bold' } }, { yAxis: 4, label: { fontFamily: 'serif' } },
      { yAxis: 5, label: { fontStyle: 'italic' } }, { yAxis: 6, label: { fontSize: '18px' } }, { yAxis: 7 }] }, { textStyle: { fontSize: 13, fontWeight: 600 } }) },
  { id: 'F2', note: "label colours: color '#f0f' (fill set -> no automatic halo); color 'inherit' (the line colour, no halo); textBorderColor '#0f0' + textBorderWidth 3; textBorderWidth 1.5 alone (the automatic halo at 1.5); textBorderColor 'none'; label opacity 0.5; lineStyle opacity 0.6 (label opacity defaults to it)",
    option: vv({ data: [{ yAxis: 2, label: { color: '#f0f' } }, { yAxis: 3, label: { color: 'inherit' }, lineStyle: { color: '#0a7' } }, { yAxis: 4, label: { textBorderColor: '#0f0', textBorderWidth: 3 } },
      { yAxis: 5, label: { textBorderWidth: 1.5 } }, { yAxis: 6, label: { textBorderColor: 'none' } }, { yAxis: 7, label: { opacity: 0.5 } }, { yAxis: 8, lineStyle: { opacity: 0.6 } }] }) },
  { id: 'K1', note: "darkMode: true on a transparent ground: the outside ink '#ccc', halo = transparent blended on BLACK -> 'rgba(0,0,0,1)'",
    option: vv({ data: [{ yAxis: 3 }, pairC([2, 5], [6, 8], { name: 'dark' })] }, { darkMode: true }) },
  { id: 'K2', note: "backgroundColor '#1e1e1e' (darkMode auto: lum < 0.4 -> dark): ink '#ccc', halo 'rgba(30,30,30,1)'",
    option: vv({ data: [{ yAxis: 3 }, { xAxis: 5, label: { position: 'insideEndTop' } }] }, { backgroundColor: '#1e1e1e' }) },
  { id: 'K3', note: "backgroundColor '#1e1e1e' with darkMode false: ink '#333' (forced light), halo 'rgba(30,30,30,1)'",
    option: vv({ data: [{ yAxis: 3 }] }, { backgroundColor: '#1e1e1e', darkMode: false }) },
  { id: 'K4', note: "backgroundColor 'rgba(0,0,0,0.5)' (lum 0.5: light): halo = 0 * 0.5 + 255 * 0.5 = 127.5 per channel -> 'rgba(127.5,127.5,127.5,1)' (no rounding)",
    option: vv({ data: [{ yAxis: 3 }] }, { backgroundColor: 'rgba(0,0,0,0.5)' }) },
  // ----- z / silent / hidden / not drawn / bars -----
  { id: 'Z1', note: 'z / zlevel from the top-level markLine {z: 9, zlevel: 1, silent: true}; z2 on items: a first line z2 10 lifts EVERY later label (label z2 = running max z2 over the LineDraw group so far + 2 = 12), a line z2 -5 with no symbols after it keeps 12; in the second series (markLine z2 1, symbol none, z 3) a z2 -5 line FIRST -> its label z2 -3, the next line takes z2 1 from the series markLine (item -> series markLine -> top-level chain) -> label 3',
    option: Object.assign(vv({ data: [{ yAxis: 2, z2: 10 }, { yAxis: 4 }, { yAxis: 6, z2: -5, symbol: 'none' }] }), {
      series: [{ type: 'scatter', name: 's0', data: PTS, markLine: { data: [{ yAxis: 2, z2: 10 }, { yAxis: 4 }, pairC([2, 6], [5, 6], { z2: -5, symbol: 'none' }, { symbol: 'none' })] } },
        { type: 'scatter', name: 's1', data: PTS, markLine: { symbol: 'none', z: 3, z2: 1, data: [{ yAxis: 8, z2: -5 }, { yAxis: 9 }] } }],
      markLine: { z: 9, zlevel: 1, silent: true } }) },
  { id: 'Z2', note: 'series silent: true (the group is silent), markLine silent on another series, label silent: true on one item (the text element itself)',
    option: Object.assign(vv({ data: [{ yAxis: 2 }] }), { series: [{ type: 'scatter', name: 's0', silent: true, data: PTS, markLine: { data: [{ yAxis: 2 }] } },
      { type: 'scatter', name: 's1', data: PTS, markLine: { silent: true, data: [{ yAxis: 4, label: { silent: true } }] } }] }) },
  { id: 'V1', note: "a top-level markLine whose label and lineStyle are NOT objects (label: false, lineStyle: 7): the master merge keeps the author's key (no overwrite), so the defaults' label object is never reached -- no label -- and the line colour falls back to the start end's fill; the series' own markLine carries no label",
    option: vv({ data: [{ yAxis: 3.3 }, pairC([2, 2], [7, 5])] }, { markLine: { label: false, lineStyle: 7 } }) },
  { id: 'V2', note: "symbolRotate 0 at the series level (a number: the tangent turn is OFF, both symbols unturned on a diagonal); a roundRect end of size [10, 0] (radius min/4 = 0: a plain rect command); a formatter repeating {c} and {b} (each replaced at its FIRST occurrence only); an unknown label position with an offset of 1e-5 (under zrender's 5e-5: no transform at all)",
    option: vv({ symbolRotate: 0, data: [pairC([1, 1], [4, 6], { name: 'nm', label: { formatter: '{c}|{c}|{b}{b}' } }, { symbol: 'roundRect', symbolSize: [10, 0] }),
      pairC([2, 3], [8, 3], { value: 4, label: { position: 'left', offset: [0.00001, 0] } })] }) },
  { id: 'H1', note: 'a legend-unselected series draws no markLine (filtered); the visible one does',
    option: Object.assign(vv({ data: [{ yAxis: 2 }] }), { legend: { selected: { hidden: false } }, series: [{ type: 'scatter', name: 'hidden', data: PTS, markLine: { data: [{ yAxis: 2 }] } },
      { type: 'scatter', name: 'shown', data: PTS, markLine: { data: [{ yAxis: 4 }] } }] }) },
  { id: 'N1', note: 'a line NOT drawn: a pair whose start has only x px ({x: 100}: coordless, kept by the filter, point [100, NaN]) -> lineNeedsDraw false: no Line group, drawn false (the only NaN of the case); the next line is drawn and its label z2 is unaffected',
    nan: true, option: vv({ data: [[{ x: 100 }, { coord: [5, 5] }], { yAxis: 3 }] }) },
  { id: 'B1', note: 'bars on a category x axis, two series: a min/max pair on the second (bar offsets: a diagonal between the bar centres of that series), a 1D average',
    option: { animation: false, xAxis: { type: 'category', data: WEEK.slice(0, 5) }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [5, 20, 36, 10, 10] },
      { type: 'bar', data: [15, 25, 16, 30, 12], markLine: { data: [[{ type: 'min' }, { type: 'max' }], { type: 'average' }] } }] } },
  { id: 'B2', note: 'horizontal bars (category y, value x): the 1D average is vertical (from = the bottom, arrow and end label at the top: center / bottom), {yAxis: Wed} horizontal printing the category',
    option: { animation: false, yAxis: { type: 'category', data: WEEK.slice(0, 5) }, xAxis: { type: 'value' }, series: [{ type: 'bar', data: [15, 25, 16, 30, 12], markLine: { data: [{ type: 'average' }, { yAxis: 'Wed' }] } }] } },
];
const GALLERY_CASES = ['area-pieces', 'bar-stack', 'bar1', 'candlestick-sh', 'line-aqi', 'line-marker', 'line-markline',
  'pictorialBar-body-fill', 'pictorialBar-hill', 'pictorialBar-spirit', 'scatter-anscombe-quartet', 'scatter-weight'];
for (const g of GALLERY_CASES) CASES.push({ id: 'G-' + g, note: 'gallery ' + g + '.json, verbatim', gallery: g });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'no-subpixel', mutation: 'the line path drawn from the raw shape (no subPixelOptimizeLine)', mut: { noSubPixel: true }, named: ['W1', 'W2', 'D6'] },
  { id: 'subpixel-negative', mutation: 'subPixelOptimize with positiveOrNegative false (the odd case goes DOWN half a pixel)', mut: { subPixelNegative: true }, named: ['W1', 'W2'] },
  { id: 'dashed-5-5', mutation: "'dashed' resolved as [5w, 5w] instead of [4w, 2w]", mut: { dashed55: true }, named: ['D1', 'S1'] },
  { id: 'dash-scaled', mutation: 'numeric / array dash multiplied by lineWidth', mut: { dashScaled: true }, named: ['S1'] },
  { id: 'color-series', mutation: "line colour falls back straight to the series colour (the from end's itemStyle ignored)", mut: { colorSeries: true }, named: ['C1', 'C2'] },
  { id: 'color-from-to', mutation: "line colour falls back to the TO end's itemStyle", mut: { colorFromTo: true }, named: ['C1'] },
  { id: 'no-tangent-rotation', mutation: 'symbols not rotated along the line when no symbolRotate is given', mut: { noTangentRotation: true }, named: ['D1', 'D2', 'D5'] },
  { id: 'rotate-zero-auto', mutation: 'symbolRotate 0 treated as unspecified (tangent rotation)', mut: { rotateZeroAuto: true }, named: ['Y4'] },
  { id: 'no-symbol-offset', mutation: 'symbolOffset ignored', mut: { noSymbolOffset: true }, named: ['Y4', 'Y5'] },
  { id: 'size-square', mutation: 'the symbol box made square (max of w, h): no [8, 16] quirk', mut: { sizeSquare: true }, named: ['D1', 'Y3'] },
  { id: 'arrow-centred', mutation: "the arrow's tip at the box top (arrow centred on the end point) instead of at the end point", mut: { arrowCentred: true }, named: ['D1', 'Y1'] },
  { id: 'square-centred', mutation: 'the square symbol centred in its box', mut: { squareCentred: true }, named: ['Y1'] },
  { id: 'no-modpi2', mutation: 'arc start angle normalised by % 2PI instead of modPI2 (round to 1e-8 of PI)', mut: { noModPI2: true }, named: ['Y1'] },
  { id: 'empty-filled', mutation: 'empty symbols filled with the line colour', mut: { emptyFilled: true }, named: ['Y2'] },
  { id: 'empty-width-1', mutation: 'empty symbols stroked at width 1', mut: { emptyWidth1: true }, named: ['Y2'] },
  { id: 'line-symbol-fill', mutation: "the 'line' symbol filled instead of stroked", mut: { lineSymbolFill: true }, named: ['Y1'] },
  { id: 'no-threshold', mutation: "'end' / 'start' align / valign by the sign of d instead of the 0.8 threshold", mut: { noThreshold: true }, named: ['D2', 'D3'] },
  { id: 'start-not-mirrored', mutation: "'start' uses the 'end' align / valign table", mut: { startNotMirrored: true }, named: ['D3', 'LP1'] },
  { id: 'no-inside-origin', mutation: 'inside positions keep origin (0, 0) (rotation about the anchor)', mut: { noInsideOrigin: true }, named: ['LP1', 'LP5'] },
  { id: 'no-dir', mutation: 'inside positions ignore the direction (dir always 1)', mut: { noDir: true }, named: ['LP2', 'LP6'] },
  { id: 'no-flip', mutation: 'no + PI on the label rotation of a right-to-left line', mut: { noFlip: true }, named: ['LP2', 'LP6'] },
  { id: 'distance-first-only', mutation: 'a distance pair read as its first value for both axes', mut: { distanceFirstOnly: true }, named: ['LP2', 'LP4', 'G-line-markline'] },
  { id: 'unknown-middle', mutation: "an unknown label position treated as 'middle'", mut: { unknownMiddle: true }, named: ['LP7'] },
  { id: 'user-align-ignored', mutation: 'author label align / verticalAlign ignored', mut: { userAlignIgnored: true }, named: ['LA1', 'G-scatter-anscombe-quartet'] },
  { id: 'align-no-normalize', mutation: "'middle' align / 'center' valign not normalised", mut: { alignNoNormalize: true }, named: ['LA1'] },
  { id: 'no-label-rotate', mutation: 'label.rotate (textConfig.rotation) ignored', mut: { noLabelRotate: true }, named: ['LA2'] },
  { id: 'offset-keeps-origin', mutation: 'label.offset leaves the inside origin', mut: { offsetKeepsOrigin: true }, named: ['LA2'] },
  { id: 'text-no-round', mutation: 'default text without round(v, 10)', mut: { textNoRound: true }, named: ['T1'] },
  { id: 'text-name-first', mutation: 'default text prefers the name over the value', mut: { textNameFirst: true }, named: ['T1', 'G-bar1'] },
  { id: 'tpl-replace-all', mutation: 'formatTpl replaces every occurrence', mut: { tplReplaceAll: true }, named: ['T2'] },
  { id: 'no-global-font', mutation: 'label font parts without the global textStyle fallback', mut: { noGlobalFont: true }, named: ['F1', 'G-line-markline'] },
  { id: 'label-opacity-own', mutation: 'label opacity not defaulting to lineStyle.opacity', mut: { labelOpacityOwn: true }, named: ['S1', 'F2', 'G-pictorialBar-body-fill'] },
  { id: 'dark-ignored', mutation: "outside ink always '#333'", mut: { darkIgnored: true }, named: ['K1', 'K2'] },
  { id: 'halo-white', mutation: 'the automatic halo always white', mut: { haloWhite: true }, named: ['K1', 'K2', 'K4'] },
  { id: 'z2-per-line', mutation: 'label z2 = this Line group max z2 + 2 (no running max over the earlier lines)', mut: { z2PerLine: true }, named: ['Z1'] },
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
// the recorded series block (items) vs a transcription result (lines in dataIndex order)
function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const ml = sr.markLine;
  const a = {};
  const b = {};
  flat({ z: ml.z, zlevel: ml.zlevel, silent: ml.silent, count: ml.count }, 'block', a);
  flat({ z: t.z, zlevel: t.zlevel, silent: t.silent, count: t.count }, 'block', b);
  for (const it of ml.items) {
    if (!it.survived) continue;
    const { index, survived, dataIndex, ...rest } = it;
    flat(rest, 'line' + dataIndex, a);
    flat(t.lines[dataIndex], 'line' + dataIndex, b);
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
      update: 'setOption, then zr.storage.getDisplayList(true) (beforeUpdate / update / updateInnerText of every element), then chart.renderToSVGString() (the SVG painter builds the path proxies)',
      lineData: "MarkerModel.getMarkerModelFromSeries(series, 'markLine').getData(); fromData / toData = the slave's '__ec_inner_*' record (as M1)",
      line: "lineData.getItemGraphicEl(i) = the Line group: childOfName('line' | 'fromSymbol' | 'toSymbol'), getTextContent(); el.path.data up to len() for the paths",
      dash: 'the resolved dash is read back from the SVG <path> (ecmeta_series_index + the d numbers) stroke-dasharray',
      tag: "a second run with data elements tagged '" + TAG + "' maps lines to original indices",
    },
    notes: [
      'Only cartesian2d series are covered.',
      "The default label font family comes from globalDefault.ts: 'Microsoft YaHei' when navigator.platform starts with 'Win' (node >= 21 has a navigator: 'Win32' on this machine), else 'sans-serif'. The recorded fonts are this machine's; every case records ecModel.option.textStyle.",
      'The dash array is what zrender paints (canvas/dashStyle.ts getLineDash): dashed [4w, 2w], dotted [w], a number n [n], an array as is; none for solid, lineWidth 0, or a falsy type. The SVG prints stroke-dashoffset ROUNDED (Math.round); canvas uses the style value (recorded).',
      'A symbol whose lineStyle.opacity is unset holds style.opacity = undefined (an own property shadowing the default 1): recorded null; every painter treats it as 1.',
      "A label shown with an empty text ('' -- a pair with neither value nor name) has no TSpan: nothing is painted (ink null).",
      "The label is 'outside' always (Line sets textConfig.inside false): the ink is the outside ink '#333' / '#ccc' (dark) with the ground halo, never the series colour unless label.color is 'inherit'.",
      'The line element\'s style holds lineStyle as given; unset keys read the zrender defaults (lineWidth 1, lineCap butt, lineDashOffset 0, opacity 1).',
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
  if (typeof v === 'object') return Object.keys(v).some(k => !/Text$/.test(k) && k !== 't' && scanNaN(v[k]));
  return false;
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    let anyNaN = false;
    let anyUndrawn = false;
    for (const sr of c.series) {
      if (!sr.markLine) continue;
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
      for (const it of sr.markLine.items) {
        if (!it.survived) continue;
        if (scanNaN(it)) anyNaN = true;
        if (!it.drawn) anyUndrawn = true;
      }
    }
    must(!anyNaN, c.id + ': NaN in a recorded picture');
    must(anyUndrawn === c.nan, c.id + ': a line ' + (anyUndrawn ? 'not drawn although the case is not marked nan' : 'expected not drawn'));
  }
  // anchors
  const item = (id, si, i) => byId[id].series.find(s => s.seriesIndex === si).markLine.items[i];
  const n = h => num(h);
  const d1 = item('D1', 0, 0);
  must(d1.toSymbol.shapeType === 'arrow' && d1.toSymbol.boxText.width === '8' && d1.toSymbol.boxText.height === '16' && d1.fromSymbol.boxText.height === '16', 'D1: the [8,16] boxes');
  must(JSON.stringify(d1.line.style.lineDashText) === '["4","2"]', 'D1: dashed [4, 2]');
  must(d1.label.align === 'left' && d1.label.verticalAlign === 'middle' && d1.label.text === '3.3', 'D1: end label');
  must(item('D1', 0, 1).label.align === 'center' && item('D1', 0, 1).label.verticalAlign === 'bottom', 'D1: vertical end label');
  must(item('D3', 0, 0).label.align === 'center' && item('D3', 0, 1).label.align === 'left', 'D3: the 0.8 edge');
  const w = item('W1', 0, 0);
  must(n(w.line.path[0].args[1]) !== n(w.line.shape.y1), 'W1: snapped');
  must(item('T1', 0, 4).label.text === '' && item('T1', 0, 4).label.ink === null, 'T1: empty text');
  must(item('T1', 0, 2).label.text === '3.3333333333', 'T1: round 10');
  must(item('T2', 0, 1).label.text === '3 and {c}', 'T2: first occurrence only');
  must(item('K1', 0, 0).label.ink.fill === '#ccc' && item('K1', 0, 0).label.ink.stroke === 'rgba(0,0,0,1)', 'K1: dark ink');
  must(item('K4', 0, 0).label.ink.stroke === 'rgba(127.5,127.5,127.5,1)', 'K4: fractional halo');
  must(item('Z1', 0, 1).label.z2 === 12, 'Z1: running z2');
  must(item('Y2', 0, 0).fromSymbol.style.fill === '#fff' && item('Y2', 0, 0).fromSymbol.style.lineWidthText === '2', 'Y2: empty brush');
  must(item('LP7', 0, 0).label.xText === '0' && item('LP7', 0, 0).label.yText === '0', 'LP7: unknown position at the origin');
  must(byId.H1.series[0].filtered && byId.H1.series[0].markLine === null, 'H1: hidden series');
  must(!item('N1', 0, 0).drawn && item('N1', 0, 1).drawn, 'N1: not drawn');
  must(byId.C3.series[0].color === '#eb5454', 'C3: candlestick colour');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        if (!sr.markLine) continue;
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
const nLines = out.cases.reduce((a, c) => a + c.series.reduce((b, s) => b + (s.markLine ? s.markLine.items.filter(i => i.survived).length : 0), 0), 0);
console.log(out.cases.length + ' cases (' + nLines + ' lines); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages from upstream');
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
