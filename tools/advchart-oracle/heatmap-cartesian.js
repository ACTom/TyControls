/*
Upstream's own answers for the HEATMAP series on a cartesian2d grid, batch H1:
each cell's rect, style and label exactly as chart/heatmap/HeatmapView.ts
_renderOnGridLike, HeatmapSeries.ts, coord/axisBand.ts calcBandWidth,
visual/style.ts (seriesStyleTask / dataStyleTask), visual/visualSolution.ts
incrementalApplyVisual + visual/helper.ts, model/mixin/dataFormat.ts,
label/labelStyle.ts, data/SeriesData.ts getName, util/graphic.ts
traverseUpdateZ and zrender (graphic/shape/Rect.ts + graphic/helper/roundRect.ts,
core/PathProxy.ts getBoundingRect + core/bbox.ts, graphic/Path.ts
getBoundingRect / getInsideTextFill / getInsideTextStroke, Element.ts
updateInnerText, contain/text.ts calculateTextPosition, graphic/Text.ts,
canvas/dashStyle.ts, svg/mapStyleToAttrs.ts + svg/helper.ts normalizeColor)
build them. The visualMap's colour / opacity per row is recorded as upstream's
own models compute it (B1-B4 pinned the mapping itself); this oracle pins how
the heatmap composes it with the series and item styles and draws the cells.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
for every chart case, with Math.random replaced by the port's xorshift32 (seed
2463534242, reset before each chart). After setOption it runs
zr.storage.getDisplayList(true) (every element's update: updateInnerText places
the labels) and chart.renderToSVGString() (the SVG painter maps every cell's
style to attributes), then reads the live elements: per heatmap series its data
(getRawIndex, getRawDataItem, get, getName, getItemVisual), the coordinate
system (dataToPoint, the axes and scales) and per row data.getItemGraphicEl(i)
= the cell Rect (undefined when skipped) and rect.getTextContent() (the label).
Every chart is disposed in a finally.

The DEVELOPMENT build throws on a heatmap without a visualMap and on a
cartesian that is not category x category with boundaryGap (HeatmapView.ts:
111-115, 183-190); the PRODUCTION build (dist/echarts.min.js, next to
ECHARTS_DIST) carries on. A case marked `prod` is recorded from the production
build and must throw in development; every other case is recorded from the
development build and must record identically through the production build.

  node tools/advchart-oracle/heatmap-cartesian.js

writes tests/fixtures/advchart-heatmap-cartesian.json (ORACLE_OUT overrides;
ORACLE_DUMP=<file> also writes the record before the checks, for debugging).

-----------------------------------------------------------------------------
Conventions (as markers-area.js)
  hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
           lowercase (NaN 7ff8000000000000, +Infinity 7ff0000000000000).
           Every hex field k has a readable twin kText (String(v), '-0' for
           negative zero).
  json     an option value exactly as upstream holds it (JSON; undefined ->
           null; +-Infinity / NaN inside -> their String)
  rect     {x, y, width, height} hex, with rectText {x, y, width, height}
  pt       [hex x, hex y], with a Text twin
  path     [{cmd, args [hex], argsText}] -- a PathProxy's data up to len():
           'R' (x, y, w, h) for a plain cell; a round-rect cell is M L [A] L
           [A] L [A] L [A] Z, A = (cx, cy, rx, ry, startAngle, sweep, 0,
           clockwise 1) after PathProxy normalizeArcAngles
  paint    a style colour exactly as upstream holds it: a css string or null
  vis      an item visual style object, OWN keys only, sorted: each value a
           number {n: hex, t: text} or json (an own key holding undefined is
           recorded null -- the palette branch of seriesStyleTask re-assigns
           `stroke` even when unset)

Top level
  source, W, H, seed, api, notes[], cases[], guards[]
  cases[]  one per chart:
    id, note, width, height, gallery (file name or null), option (as fed;
    null for a gallery case: load examples/advchart/gallery/<gallery>.json and
    feed it verbatim), nan (true: a drawn cell of this case has NaN geometry --
    only on a non-category axis, documented in the note), productionBuild
    (bool), devError (the development build's message, or null)
    ground   {background: zr.getBackgroundColor(), isDark: zr.isDarkMode()}
    textStyle  json: ecModel.option.textStyle -- the global text style every
             label font part falls back to (defaults fontSize 12, fontStyle /
             fontWeight 'normal', fontFamily 'Microsoft YaHei' when
             navigator.platform starts with 'Win' -- this machine -- else
             'sans-serif'; globalDefault.ts)
    series[] every series of type 'heatmap', series order:
      seriesIndex, name (option name or null), filtered (legend-unselected:
      nothing drawn, `heatmap` null), color (paint: the series visual colour
      data.getVisual('style').fill -- the palette colour unless
      series.itemStyle.color is set), seriesName (the name {a} prints; null
      when the option has no name -- upstream's generated one holds a NUL),
      heatmap: null (filtered) or
        z, zlevel (json: series z || 0 -- default 2 -- and zlevel || 0),
        silent (the view group's silent = !!series.silent: every cell and
          label inherits it for hit testing; echarts.ts:2508)
        seriesStyle  vis: data.getVisual('style') -- the series itemStyle
          (own keys over ITEM_STYLE_KEY_MAP), fill = the palette colour when
          itemStyle.color is falsy
        cell     {width, height} hex + Text: the size of every cell = band +
          0.5 (null when no cell is drawn)
        count (data.count(): the rows left after a dataZoom 'filter'), rawCount
        (series.data length), hasItemOption (some row is an object with more
        than a value)
        grid + gridText  rect: the grid's coordinate rect (cs.master.getRect())
        axes {x, y}: {type, onBand (boundaryGap), inverse, extent + extentText
          (scale.getExtent(): the dataZoom window, ordinal numbers on a
          category axis), px + pxText (axis.getExtent(): LOCAL pixels -- the
          band uses |px[1] - px[0]|), categories (json: the ordinal meta, null
          on a non-category axis)}
        rows[]   one per ORIGINAL data element (series.data order):
          index, dataIndex (its index in the data, null when a dataZoom in
          'filter' mode removed it -- nothing else is recorded then); else:
          raw         json: data.getRawDataItem -- as upstream HOLDS it (it adds
                      emphasis.label.show to items that have label.show)
          parsed + parsedText  [x, y, value] hex: data.get -- ordinal numbers
                      on a category axis (a category name resolved, a number
                      KEPT as written: 2.5 stays 2.5), NaN for '-', null,
                      missing, an unknown name or an unparsable string
          name        data.getName(i): what {b} prints
          point + pointText  pt: coordinateSystem.dataToPoint([x, y]) (an
                      ordinal scale rounds x / y with Math.round there; NaN in
                      -> NaN out)
          vm          null when no visualMap targets the series, else {vms:
                      [{index, value (hex) + valueText, state ('inRange' /
                      'outOfRange'), skipped (the raw item has visualMap:
                      false)}] in component order, color (paint: the colour
                      the visualMaps wrote, null when none), colorWritten,
                      opacity (hex or null) + opacityText, opacityWritten} --
                      THE VISUALMAP'S RESOLVED COLOUR per row, computed by
                      upstream's own models (getDataDimensionIndex, store.get,
                      getValueState, targetVisuals[state] applied in
                      prepareVisualTypes order, each seeded with what the row
                      holds so far)
          visual      vis: data.getItemVisual(i, 'style') -- the cell style:
                      seriesStyle, then what the visualMaps wrote, then the
                      item's own itemStyle keys (they win)
          drawn       bool: a cell exists
          skip        null (drawn) or why not, the FIRST failing test in
                      HeatmapView's order: 'value' / 'x' / 'y' (NaN), 'x<' /
                      'x>' / 'y<' / 'y>' (outside the scale extent)
          rect        null (not drawn) or the cell Rect:
            shape {x, y, width, height} hex + Text, r (json: borderRadius
              through item itemStyle -> series itemStyle; null = none)
            path (the proxy after buildPath), bbox + bboxText (rect:
              PathProxy.getBoundingRect), rect + rectText (rect:
              Path.getBoundingRect() -- bbox grown by the stroke when stroke
              is set (not 'none') and lineWidth > 0: + lineWidth, or
              max(lineWidth, 5) without a fill, half each side; the cell has
              no transform, so this is the label's rect)
            style {fill, stroke (paint), lineWidth, opacity, lineDashOffset,
              miterLimit, shadowBlur, shadowOffsetX, shadowOffsetY,
              fillOpacity, strokeOpacity (hex + Text or null), lineDash (json:
              borderType as held), lineCap, lineJoin, shadowColor (json),
              strokeNoScale (bool)} after useStyle (unset keys read zrender's
              DEFAULT_PATH_STYLE: fill '#000', lineWidth 1, opacity 1 ...)
            svg (the SVG painter's attributes for the <path>, read back):
              {fill ('none' for 'none' / 'transparent'), fillOpacity (hex or
              null = absent = 1), stroke (string or null = absent),
              strokeWidth (hex or null = absent = 1), strokeOpacity (hex or
              null), dash ([hex] + dashText or null), dashOffset (hex or
              null), lineCap, lineJoin, miterLimit (string or null)}
            z, z2 (0 on a cartesian cell), zlevel, silent (el.isSilent())
          label       null (not drawn or not shown), else:
            text          style.text: the formatted string or the default text
                          String(rawValue[2]) ('-' when that is null)
            lines         the number of TSpans (0 for '')
            position      json: textConfig.position (label.position through
                          item -> series, default 'inside'; 'outside' -> 'top')
            distance      hex + Text: textConfig.distance (default 5)
            rect, rectText  the rect the label is placed against (= rect.rect)
            x, y, rotation, originX, originY, scaleX, scaleY (hex + Text): the
                          text element's own props (0 / 0 / 0 / 0 / 0 / 1 / 1)
            inner         {x, y, rotation, originX, originY} hex + innerText:
                          the innerTransformable after updateInnerText
                          (calculateTextPosition on `rect`, then label.rotate /
                          label.offset)
            transform     m6 of the inner transformable (null: none)
            align, verticalAlign  as laid out: the style's (author) value, else
                          the calculated one, else 'left' / 'top'
            authorAlign, authorVerticalAlign  the style's after zrender
                          normalizeStyle; null = unset
            inside        bool: the inside ink rule applies (position a string
                          containing 'inside' AND the cell has a fill)
            font          style.font (makeFont), fontSize, fontWeight,
                          fontStyle, fontFamily (json: the style's parts)
            style         {fill, stroke (colour or null: not in the style),
                          lineWidth (hex or null), opacity (hex: label.opacity,
                          else the global textStyle's, else the CELL STYLE's
                          opacity -- defaultOpacity -- else 1), backgroundColor
                          (json or null)}
            inkDefault    {fill, stroke, autoStroke, align, verticalAlign} =
                          the text's _defaultStyle set by updateInnerText
                          (inside: getInsideTextFill / getInsideTextStroke of
                          the cell fill, alpha included; outside: '#333' /
                          '#ccc' and the ground halo)
            ink           null when no TSpan, else the TSpans (all the same):
                          {fill, stroke (null = none), lineWidth (hex or null),
                          opacity (hex)}
            z, z2 (2: the running max z2 of the view group, 0, + 2), zlevel,
            silent (label.silent)
guards[]  one per mutation of the transcription: id, mutation, named (the
          cases that must turn red), changed (the cases whose recorded values
          the mutated transcription does not reproduce), ok = named is a
          subset of changed, differs (the first differing fields of each
          named case)

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, bit for bit) takes as
INPUTS: the option as fed (the series option merged over
HeatmapSeries.defaultOption -- checked against upstream's own on the keys read),
the series palette colour, the host series name, ecModel.option.textStyle, the
ground, the axes (type, onBand, scale extent, px extent, categories) and per
kept row the raw item, the parsed [x, y, value], the raw index, the point and
what the visualMaps wrote. It reproduces: seriesStyleTask / dataStyleTask
(makeStyleMapper over ITEM_STYLE_KEY_MAP, the palette fill, the stage order
series -> visualMap -> item), SeriesData.getName (item name via
convertOptionIdName, the category filled in at init, and the runtime fallback
that reads the FILTERED store at the RAW index), calcBandWidth for category /
other axes, HeatmapView's skip test, rect and borderRadius, zrender Rect /
roundRect buildPath, PathProxy.getBoundingRect (fromLine, fromArc), Path
getBoundingRect (stroke growth), dataFormat getFormattedLabel (formatTpl with
the whole value array as {c}, the {@dim} / {@[n]} pass through
retrieveRawValue / getDimensionIndex) and the default text, labelStyle
createTextStyle (no inheritColor: 'inherit' -> null; defaultOpacity = the cell
style opacity) / createTextConfig, contain/text calculateTextPosition,
Element.updateInnerText (inside / outside ink, rotation / offset),
Path.getInsideTextFill / getInsideTextStroke (lum with alpha),
Element.getOutsideStroke, Text normalizeStyle / makeFont / parseFontSize and the
TSpan ink rules, svg mapStyleToAttrs + normalizeColor + dashStyle, and
util/graphic traverseUpdateZ (z, zlevel, label z2).

Self-checks (any failure: nothing is written, exit 1): the transcription
reproduces every recorded series (every field, bit for bit); the heatmap dims
are x, y, value; `drawn` is exactly HeatmapView's skip test on upstream's own
values; each drawn cell is an untransformed Rect without subPixelOptimize,
all cells of a series have one size, and the view group holds exactly the
drawn cells in data order; raw indices increase; the recorded label placement
equals calculateTextPosition (+ offset) on the recorded rect; every drawn cell
is matched by an SVG <path> with its series and data index whose d starts
within 0.05 of the path start (or is empty for a NaN path), and all matches
agree; the cell colour is the visualMap's wherever the item has no colour of
its own; NaN appears exactly in the cases marked nan; the development build
throws exactly for the cases marked prod, and the production build records
every other case identically; anchors; every guard is ok; two generations in
the process give identical bytes.
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// the development build throws on a heatmap without a visualMap and on non-category / boundaryGap-false axes
// (HeatmapView.ts:111-115, 173-180); the production build carries on. A case that trips one is recorded from the
// production build instead -- what a page actually ships -- and says so (as category-minmax.js).
const PROD_PATH = DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js');
const PROD = require(PROD_PATH);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-heatmap-cartesian.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;

// This generator's own assertions: never retried through the production build.
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
const paint = v => (v == null ? null : typeof v === 'string' ? v : json(v));
function m6(m, key) {
  key = key || 'transform';
  if (!m) return { [key]: null, [key + 'Text']: null };
  return { [key]: Array.from(m).slice(0, 6).map(hex), [key + 'Text']: Array.from(m).slice(0, 6).map(text) };
}
function rectRec(r, key) {
  return { [key]: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
    [key + 'Text']: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) } };
}
const pt = p => [hex(p[0]), hex(p[1])];
const ptText = p => [text(p[0]), text(p[1])];
const pair = (a, key) => ({ [key]: a.map(hex), [key + 'Text']: a.map(text) });

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

// HeatmapSeries.defaultOption (HeatmapSeries.ts:96-133); tokens.color.primary = '#3c3c41' (visual/tokens.ts)
const HM_DEFAULTS = {
  coordinateSystem: 'cartesian2d', z: 2, geoIndex: 0, blurSize: 30, pointSize: 20, maxOpacity: 1, minOpacity: 0,
  select: { itemStyle: { borderColor: '#3c3c41' } },
};
const DIMS = ['x', 'y', 'value'];
const PI = Math.PI;
const PI2 = PI * 2;
const MAXV = Number.MAX_VALUE;

// Model getShallow / get over [own, parent, grandparent ...]
function chainGet(levels, key) {
  let v;
  for (let i = 0; i < levels.length; i++) {
    const o = levels[i];
    v = o && typeof o === 'object' ? o[key] : undefined;
    if (v != null) return v;
  }
  return v;
}
const sub = (levels, key) => levels.map(o => (o && typeof o === 'object' ? o[key] : undefined));
const isItemObject = raw => isObject(raw) && !isArray(raw) && !(raw instanceof Date);

// zrender contain/text.ts parsePercent
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}

// ---- zrender PathProxy (a recorder) + normalizeArcAngles (core/PathProxy.ts:60-101, 293-314) ----
function modPI2(radian) {
  const n = Math.round(radian / PI * 1e8) / 1e8;
  return (n % 2) * PI;
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
  moveTo(x, y) { this.data.push(CMD.M, x, y); }
  lineTo(x, y) { this.data.push(CMD.L, x, y); }
  rect(x, y, w, h) { this.data.push(CMD.R, x, y, w, h); }
  closePath() { this.data.push(CMD.Z); }
  arc(cx, cy, r, startAngle, endAngle, anticlockwise) {
    const a = [startAngle, endAngle];
    normalizeArcAngles(a, anticlockwise);
    this.data.push(CMD.A, cx, cy, r, r, a[0], a[1] - a[0], 0, anticlockwise ? 0 : 1);
  }
}

// zrender graphic/helper/roundRect.ts buildPath (number or array r)
function roundRectPath(ctx, shape, mut) {
  let x = shape.x;
  let y = shape.y;
  let width = shape.width;
  let height = shape.height;
  const r = shape.r;
  let r1;
  let r2;
  let r3;
  let r4;
  if (width < 0) { x = x + width; width = -width; }
  if (height < 0) { y = y + height; height = -height; }
  if (typeof r === 'number') r1 = r2 = r3 = r4 = r;
  else if (r instanceof Array) {
    if (r.length === 1) r1 = r2 = r3 = r4 = r[0];
    else if (r.length === 2) { r1 = r3 = r[0]; r2 = r4 = r[1]; }
    else if (r.length === 3) { r1 = r[0]; r2 = r4 = r[1]; r3 = r[2]; }
    else { r1 = r[0]; r2 = r[1]; r3 = r[2]; r4 = r[3]; }
  } else r1 = r2 = r3 = r4 = 0;
  let total;
  if (!mut.radiusUnclamped) {
    if (r1 + r2 > width) { total = r1 + r2; r1 *= width / total; r2 *= width / total; }
    if (r3 + r4 > width) { total = r3 + r4; r3 *= width / total; r4 *= width / total; }
    if (r2 + r3 > height) { total = r2 + r3; r2 *= height / total; r3 *= height / total; }
    if (r1 + r4 > height) { total = r1 + r4; r1 *= height / total; r4 *= height / total; }
  }
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
// zrender graphic/shape/Rect.ts buildPath (subPixelOptimize is false on a heatmap cell)
function rectPath(shape, mut) {
  const ctx = new Proxy();
  const zeroArray = isArray(shape.r) && shape.r.every(v => !v);
  if (!shape.r || (mut.radiusZeroArrayPlain && zeroArray)) ctx.rect(shape.x, shape.y, shape.width, shape.height);
  else roundRectPath(ctx, shape, mut);
  return ctx.data;
}

// ---- zrender core/bbox.ts, PathProxy.getBoundingRect (490-597) over M / L / A / R / Z ----
function fromLine(x0, y0, x1, y1, min, max) {
  min[0] = Math.min(x0, x1);
  min[1] = Math.min(y0, y1);
  max[0] = Math.max(x0, x1);
  max[1] = Math.max(y0, y1);
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

// zrender Transformable needLocalTransform + getLocalTransform (the inner text transformable)
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

// util/format.ts formatTpl for one params object (String.prototype.replace: FIRST occurrence only; a value array
// replaces as String(array) = 'x,y,v')
const TPL_VAR_ALIAS = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
function formatTpl(tpl, params, mut) {
  const $vars = ['seriesName', 'name', 'value'];
  const rep = (s, from, to) => (mut.tplReplaceAll ? s.split(from).join(String(to)) : s.replace(from, to));
  for (let i = 0; i < $vars.length; i++) {
    const alias = TPL_VAR_ALIAS[i];
    tpl = rep(tpl, '{' + alias + '}', '{' + alias + '0}');
  }
  for (let k = 0; k < $vars.length; k++) {
    let v = params[$vars[k]];
    if (mut.valueLastOnly && $vars[k] === 'value' && isArray(v)) v = v[2];
    tpl = rep(tpl, '{' + TPL_VAR_ALIAS[k] + '0}', v);
  }
  return tpl;
}
// dataFormat.ts:141-167 the {@dim} / {@[n]} pass after formatTpl, retrieveRawValue(data, idx, dim) with
// SeriesData.getDimensionIndex (_recognizeDimIndex: a number or a number-like string that is not a dim name ->
// that index; a dim name -> its index; anything else -> -1)
function dimTemplates(str, rawValue, mut) {
  if (mut.dimTemplateIgnored) return str;
  return str.replace(/\{@(.+?)\}/g, function (origin, dimStr) {
    const len = dimStr.length;
    let dimLoose = dimStr;
    if (dimLoose.charAt(0) === '[' && dimLoose.charAt(len - 1) === ']') dimLoose = +dimLoose.slice(1, len - 1);
    let dimIndex;
    if (typeof dimLoose === 'number' || (dimLoose != null && !isNaN(dimLoose) && DIMS.indexOf(dimLoose) < 0)) dimIndex = +dimLoose;
    else dimIndex = DIMS.indexOf(dimLoose);
    const v = !(rawValue instanceof Array) ? rawValue : rawValue[dimIndex];
    return v != null ? v + '' : '';
  });
}
// util/model.ts convertOptionIdName (555-564)
function convertOptionIdName(v, def) {
  if (v == null) return def;
  return typeof v === 'string' ? v : typeof v === 'number' ? v + '' : def;
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
// zrender tool/color lum (color.ts:558-564)
function lum(c, backgroundLum, mut) {
  const arr = echarts.color.parse(c);
  if (arr && mut && mut.lumIgnoresAlpha) arr[3] = 1;
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
      const fillLum = lum(pathFill, 0, mut);
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
const POSITIONS = { left: 1, right: 1, top: 1, bottom: 1, inside: 1, insideLeft: 1, insideRight: 1, insideTop: 1, insideBottom: 1,
  insideTopLeft: 1, insideTopRight: 1, insideBottomLeft: 1, insideBottomRight: 1 };

// canvas/dashStyle.ts normalizeLineDash (getLineDash: no strokeNoScale -> no lineScale division)
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : isArray(lineType) ? lineType : null;
}
// svg/helper.ts normalizeColor
function normalizeColor(color) {
  let opacity;
  if (!color || color === 'transparent') color = 'none';
  else if (typeof color === 'string' && color.indexOf('rgba') > -1) {
    const arr = echarts.color.parse(color);
    if (arr) {
      color = 'rgb(' + arr[0] + ',' + arr[1] + ',' + arr[2] + ')';
      opacity = arr[3];
    }
  }
  return { color, opacity: opacity == null ? 1 : opacity };
}
// svg/mapStyleToAttrs.ts for a Path (not forceUpdate: SSR); a gradient paint server prints 'url'
const DEFAULT_PATH_STYLE = { fill: '#000', stroke: null, strokePercent: 1, fillOpacity: 1, strokeOpacity: 1, lineDashOffset: 0, lineWidth: 1,
  lineCap: 'butt', miterLimit: 10, strokeNoScale: false, strokeFirst: false,
  shadowBlur: 0, shadowOffsetX: 0, shadowOffsetY: 0, shadowColor: '#000', opacity: 1, blend: 'source-over' };
function svgAttrs(st) {
  const r = { fill: null, fillOpacity: null, stroke: null, strokeWidth: null, strokeOpacity: null, dash: null, dashOffset: null, lineCap: null, lineJoin: null, miterLimit: null };
  const opacity = st.opacity == null ? 1 : st.opacity;
  if (st.fill != null && st.fill !== 'none') {
    const f = normalizeColor(st.fill);
    r.fill = typeof f.color === 'string' ? f.color : 'url';
    const fo = st.fillOpacity != null ? st.fillOpacity * f.opacity * opacity : f.opacity * opacity;
    if (fo < 1) r.fillOpacity = fo;
  } else {
    r.fill = 'none';
  }
  if (st.stroke != null && st.stroke !== 'none') {
    const s = normalizeColor(st.stroke);
    r.stroke = typeof s.color === 'string' ? s.color : 'url';
    const sw = st.lineWidth || 0;
    const so = st.strokeOpacity != null ? st.strokeOpacity * s.opacity * opacity : s.opacity * opacity;
    if (sw !== 1) r.strokeWidth = sw;
    if (so < 1) r.strokeOpacity = so;
    if (st.lineDash) {
      const d = st.lineWidth > 0 && normalizeLineDash(st.lineDash, st.lineWidth);
      if (d) {
        r.dash = d;
        const off = Math.round(st.lineDashOffset || 0);
        if (off) r.dashOffset = off;
      }
    }
    for (const k of ['lineCap', 'miterLimit', 'lineJoin']) {
      if (st[k] !== DEFAULT_PATH_STYLE[k]) {
        const v = st[k] || DEFAULT_PATH_STYLE[k];
        if (v) r[k] = String(v);
      }
    }
  }
  return r;
}
function svgRec(r) {
  return { fill: r.fill, fillOpacity: hexOrNull(r.fillOpacity), fillOpacityText: textOrNull(r.fillOpacity), stroke: r.stroke,
    strokeWidth: hexOrNull(r.strokeWidth), strokeWidthText: textOrNull(r.strokeWidth), strokeOpacity: hexOrNull(r.strokeOpacity), strokeOpacityText: textOrNull(r.strokeOpacity),
    dash: r.dash ? r.dash.map(hex) : null, dashText: r.dash ? r.dash.map(text) : null, dashOffset: hexOrNull(r.dashOffset), dashOffsetText: textOrNull(r.dashOffset),
    lineCap: r.lineCap, lineJoin: r.lineJoin, miterLimit: r.miterLimit };
}

const ITEM_STYLE_KEYS = [['fill', 'color'], ['stroke', 'borderColor'], ['lineWidth', 'borderWidth'], ['opacity', 'opacity'],
  ['shadowBlur', 'shadowBlur'], ['shadowOffsetX', 'shadowOffsetX'], ['shadowOffsetY', 'shadowOffsetY'], ['shadowColor', 'shadowColor'],
  ['lineDash', 'borderType'], ['lineDashOffset', 'borderDashOffset'], ['lineCap', 'borderCap'], ['lineJoin', 'borderJoin'], ['miterLimit', 'borderMiterLimit']];
const TEXT_PROPS_BOX = ['padding', 'borderWidth', 'borderRadius', 'borderDashOffset', 'backgroundColor', 'borderColor', 'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY'];
const STYLE_NUM_KEYS = ['lineWidth', 'opacity', 'lineDashOffset', 'miterLimit', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY', 'fillOpacity', 'strokeOpacity'];
// a style as held (own + inherited keys read through; absent = null)
function styleRec(s) {
  const r = { fill: paint(s.fill), stroke: paint(s.stroke) };
  for (const k of STYLE_NUM_KEYS) {
    r[k] = hexOrNull(s[k]);
    r[k + 'Text'] = textOrNull(s[k]);
  }
  Object.assign(r, { lineDash: json(s.lineDash), lineCap: json(s.lineCap), lineJoin: json(s.lineJoin), shadowColor: json(s.shadowColor), strokeNoScale: !!s.strokeNoScale });
  return r;
}
// the item visual style (a plain object): its OWN keys only
function visualRec(s) {
  const r = {};
  for (const k of Object.keys(s).sort()) {
    const v = s[k];
    r[k] = typeof v === 'number' ? { n: hex(v), t: text(v) } : json(v);
  }
  return r;
}
// makeStyleMapper(ITEM_STYLE_KEY_MAP, true) over one itemStyle option (own keys, no parent)
function mapItemStyle(o) {
  const s = {};
  if (!o || typeof o !== 'object') return s;
  for (const [k, from] of ITEM_STYLE_KEYS) if (o[from] != null) s[k] = o[from];
  return s;
}

// calcBandWidth (coord/axisBand.ts:83-150): a category axis -> pxSpan / (extent span + onBand), 0 -> 1;
// any other axis (no fromStat, no min) -> NaN
function bandOf(ax, mut) {
  if (ax.type !== 'category') return mut.nonCategoryZero ? 0 : NaN;
  const span = mut.bandFromCount ? ax.categories.length - 1 : ax.extent[1] - ax.extent[0];
  let len = span + (ax.onBand || mut.onBandIgnored ? 1 : 0);
  if (len === 0 && !mut.len0Kept) len = 1;
  return Math.abs(ax.px[1] - ax.px[0]) / len;
}

// one heatmap series' picture. inp: {seriesOpt (merged over HM_DEFAULTS), color, seriesName, textStyle, ground,
// axes {x, y}, rows: [{raw, parsed [x, y, v], point, vm: null | {wrote: {color?, opacity?}}}] (the kept rows, data
// order)} -> {block, rows[]}
function transcribe(inp, mut) {
  const S = inp.seriesOpt;
  const z = mut.zDefault0 ? 0 : S.z || 0;
  const zlevel = S.zlevel || 0;
  const silent = mut.silentIgnored ? false : !!S.silent;
  const gts = inp.textStyle || {};
  const ax = inp.axes.x;
  const ay = inp.axes.y;
  // seriesStyleTask (visual/style.ts:66-120): the series itemStyle (own keys), fill = the palette colour when falsy
  const seriesStyle = mapItemStyle(S.itemStyle);
  must(typeof seriesStyle.fill !== 'function' && seriesStyle.fill !== 'auto' && seriesStyle.stroke !== 'auto', 'the transcription does no colour callbacks / auto');
  // the palette branch re-assigns fill AND stroke (style.ts:94-99): an unset stroke becomes an OWN undefined key
  if (!seriesStyle.fill) {
    seriesStyle.fill = inp.color;
    seriesStyle.stroke = seriesStyle.stroke; // eslint-disable-line no-self-assign
  }
  // HeatmapView._renderOnGridLike (HeatmapView.ts:160-332)
  const cellW = bandOf(ax, mut) + (mut.noHalfPx ? 0 : 0.5);
  const cellH = bandOf(ay, mut) + (mut.noHalfPx ? 0 : 0.5);
  const xe = ax.extent;
  const ye = ay.extent;
  // the name dim: the FIRST category coord dim (createSeriesData.ts injectOrdinalMeta:77-102)
  const nameDim = ax.type === 'category' ? 0 : ay.type === 'category' ? 1 : -1;
  const nameAxis = nameDim === 0 ? ax : ay;
  let maxZ2 = -Infinity;
  let cell = null;
  const rows = inp.rows.map((IT, dataIndex) => {
    const raw = IT.raw;
    const isObj = isItemObject(raw);
    const [x, y, v] = IT.parsed;
    // the visual style: series style, then visualMap (stage 4000), then the item itemStyle (dataStyleTask, 4500)
    const style = Object.assign({}, seriesStyle);
    const itemStyle = isObj ? mapItemStyle(raw.itemStyle) : {};
    const applyVm = () => {
      if (!IT.vm || mut.vmIgnored) return;
      if ('color' in IT.vm.wrote && !(mut.seriesColorOverVm && S.itemStyle && S.itemStyle.color)) style.fill = IT.vm.wrote.color;
      if ('opacity' in IT.vm.wrote && !mut.vmOpacityIgnored) style.opacity = IT.vm.wrote.opacity;
    };
    if (mut.itemUnderVm) { Object.assign(style, itemStyle); applyVm(); } else { applyVm(); Object.assign(style, itemStyle); }
    // SeriesData.getName (SeriesData.ts:731-741): _nameList[rawIndex] -- the item's name (_doInit, 650-658), else
    // the category of the row's own name-dim value filled in at init (makeIdFromName) -- and only when that is
    // still null (a category that does not exist) the runtime fallback getIdNameFromStore(data, nameDim, rawIndex),
    // which reads the FILTERED store at the RAW index (DataStore.get maps it through the filter): another row's
    // category, or NaN -> '' past the filtered count
    let name = isObj ? convertOptionIdName(raw.name, null) : null;
    if (name == null && nameDim >= 0 && !mut.nameNoCategory) {
      name = convertOptionIdName(nameAxis.categories[IT.parsed[nameDim]], null);
      if (name == null && !mut.nameRuntimeOwnRow) {
        const at = IT.rawIndex;
        const ord = at >= 0 && at < inp.rows.length ? inp.rows[at].parsed[nameDim] : NaN;
        name = convertOptionIdName(nameAxis.categories[ord], null);
      }
    }
    if (name == null) name = '';
    const out = { name, visual: visualRec(style) };
    // skip: empty / out-of-extent data (HeatmapView.ts:216-227)
    let skip = null;
    if (isNaN(v) && !mut.nanValueDrawn) skip = 'value';
    else if (isNaN(x)) skip = 'x';
    else if (isNaN(y)) skip = 'y';
    else if (!mut.extentOpen) {
      if (mut.extentStrict ? x <= xe[0] : x < xe[0]) skip = 'x<';
      else if (mut.extentStrict ? x >= xe[1] : x > xe[1]) skip = 'x>';
      else if (mut.extentStrict ? y <= ye[0] : y < ye[0]) skip = 'y<';
      else if (mut.extentStrict ? y >= ye[1] : y > ye[1]) skip = 'y>';
    }
    out.drawn = skip == null;
    out.skip = skip;
    if (skip != null) {
      out.rect = out.label = null;
      return out;
    }
    const point = IT.point;
    const r = mut.radiusSeriesOnly ? chainGet([S.itemStyle], 'borderRadius') : chainGet([isObj ? raw.itemStyle : undefined, S.itemStyle], 'borderRadius');
    const shape = { x: point[0] - (mut.notCentred ? 0 : cellW / 2), y: point[1] - (mut.notCentred ? 0 : cellH / 2), width: cellW, height: cellH, r };
    if (!cell) cell = { width: cellW, height: cellH };
    const pdata = rectPath(shape, mut);
    const st = Object.assign(Object.create(DEFAULT_PATH_STYLE), style);
    const bbox = pathBBox(pdata);
    const hasStroke = !(st.stroke == null || st.stroke === 'none' || !(st.lineWidth > 0));
    const hasFill = st.fill != null && st.fill !== 'none';
    // Path.getBoundingRect (Path.ts:339-392): the stroke grows the rect (no transform: lineScale 1)
    let rect = bbox;
    if (hasStroke && pdata.length > 0 && !mut.rectNoStroke) {
      rect = Object.assign({}, bbox);
      let w = st.lineWidth;
      if (!hasFill && !mut.noFillThreshold) w = Math.max(w, 5);
      rect.width += w;
      rect.height += w;
      rect.x -= w / 2;
      rect.y -= w / 2;
    }
    maxZ2 = Math.max(0, maxZ2); // every cartesian cell has z2 0 (util/graphic.ts doUpdateZ over the view group)
    out.rect = Object.assign({ shape: Object.assign(nums(shape, ['x', 'y', 'width', 'height']), { r: json(r) }), path: decode(pdata) },
      rectRec(bbox, 'bbox'), rectRec(rect, 'rect'),
      { style: styleRec(st), svg: svgRec(svgAttrs(st)), z, z2: 0, zlevel, silent });
    // ----- the label (HeatmapView.ts:280-300, labelStyle.ts, zr Element.updateInnerText, Text) -----
    const LB = [isObj ? raw.label : undefined, S.label];
    const show = chainGet(LB, 'show');
    if (!show) {
      out.label = null;
      return out;
    }
    const rawValue = isObj ? raw.value : raw;
    let formatter = chainGet(LB, 'formatter');
    let str;
    if (typeof formatter === 'string') {
      str = dimTemplates(formatTpl(formatter, { seriesName: inp.seriesName, name, value: rawValue }, mut), rawValue, mut);
    } else {
      must(formatter == null, 'the transcription does not call formatter functions');
      str = '-';
      if (rawValue && rawValue[2] != null) str = mut.defaultTextParsed ? v + '' : rawValue[2] + '';
    }
    // createTextStyle(normal, isAttached = true), no inheritColor, defaultOpacity = the visual style's opacity
    const ts = {};
    const inheritColor = mut.inheritIsFill ? style.fill : undefined;
    let fc = chainGet(LB, 'color');
    let sc = chainGet(LB, 'textBorderColor');
    let opacity = retrieve2(chainGet(LB, 'opacity'), gts.opacity);
    if (fc === 'inherit' || fc === 'auto') fc = inheritColor || null;
    if (sc === 'inherit' || sc === 'auto') sc = inheritColor || null;
    if (fc != null) ts.fill = fc;
    if (sc != null) ts.stroke = sc;
    const tbw = retrieve2(chainGet(LB, 'textBorderWidth'), gts.textBorderWidth);
    if (tbw != null) ts.lineWidth = tbw;
    if (opacity == null && !mut.labelOpacityOwn) opacity = style.opacity;
    if (opacity != null) ts.opacity = opacity;
    for (const k of ['fontStyle', 'fontWeight', 'fontSize', 'fontFamily']) {
      const x2 = mut.noGlobalFont ? chainGet(LB, k) : retrieve2(chainGet(LB, k), gts[k]);
      if (x2 != null) ts[k] = x2;
    }
    let rawAlign = chainGet(LB, 'align');
    let rawVAlign = chainGet(LB, 'verticalAlign');
    if (rawVAlign == null) rawVAlign = chainGet(LB, 'baseline');
    for (const k of TEXT_PROPS_BOX) {
      const x2 = chainGet(LB, k);
      if (x2 != null) ts[k] = x2;
    }
    if ((ts.backgroundColor === 'auto' || ts.backgroundColor === 'inherit') && inheritColor) ts.backgroundColor = inheritColor;
    for (const o of LB) must(!(o && typeof o === 'object' && o.rich), 'the transcription does not do rich labels');
    must(chainGet(LB, 'textBorderType') == null && chainGet(LB, 'textBorderDashOffset') == null, 'the transcription does not do text border dashes');
    if (mut.userAlignIgnored) rawAlign = rawVAlign = null;
    const authorAlign = normAlign(rawAlign, mut);
    const authorVAlign = normVAlign(rawVAlign, mut);
    // createTextConfig (labelStyle.ts:340-383): no defaultOutsidePosition
    let position = chainGet(LB, 'position') || (mut.positionDefaultTop ? 'top' : 'inside');
    if (position === 'outside' && !mut.outsideNotTop) position = 'top';
    const distance = mut.distanceIgnored ? 5 : retrieve2(chainGet(LB, 'distance'), 5);
    const labelOffset = chainGet(LB, 'offset');
    let labelRotate = chainGet(LB, 'rotate');
    if (labelRotate != null) labelRotate *= Math.PI / 180;
    const outsideFill = chainGet(LB, 'color') === 'inherit' ? (inheritColor || null) : 'auto';
    // updateInnerText on the cell's bounding rect (no transform anywhere)
    const calc = calculateTextPosition(position, distance, rect);
    const inner = { x: calc.x, y: calc.y, rotation: 0, originX: 0, originY: 0, scaleX: 1, scaleY: 1 };
    if (labelRotate != null && !mut.noLabelRotate) inner.rotation = labelRotate;
    if (labelOffset) {
      inner.x += labelOffset[0];
      inner.y += labelOffset[1];
      if (!mut.offsetKeepsOrigin) { inner.originX = -labelOffset[0]; inner.originY = -labelOffset[1]; }
    }
    // the ink (Element.ts:697-735): inside needs a fill
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
    const lines = textStr === '' ? 0 : textStr.split('\n').length;
    let ink = null;
    if (textStr !== '') {
      const useDefaultFill = !('fill' in ts);
      const tf = useDefaultFill ? defFill : ts.fill;
      const bgDrawn = !!ts.backgroundColor && !mut.bgAutoStroke;
      let dlw = 0;
      let tsk;
      if ('stroke' in ts) tsk = ts.stroke;
      else if (!bgDrawn && useDefaultFill) { dlw = 2; tsk = defStroke; } else tsk = null;
      const fillP = tf == null || tf === 'none' ? null : tf;
      const strokeP = tsk == null || tsk === 'transparent' || tsk === 'none' ? null : tsk;
      const lwP = strokeP ? (ts.lineWidth || dlw) : null;
      const op = retrieve2(ts.opacity, 1);
      ink = { fill: colour(fillP), stroke: colour(strokeP), lineWidth: hexOrNull(lwP), lineWidthText: textOrNull(lwP), opacity: hex(op), opacityText: text(op) };
    }
    const labelZ2 = isFinite(maxZ2) ? maxZ2 + 2 : 0;
    const stOpacity = retrieve2(ts.opacity, 1);
    const lp = { x: 0, y: 0, rotation: 0, originX: 0, originY: 0, scaleX: 1, scaleY: 1 };
    out.label = Object.assign({ text: str == null ? null : String(str), lines, position: json(position),
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
  const block = { z: json(z), zlevel: json(zlevel), silent, seriesStyle: visualRec(seriesStyle),
    cell: cell ? Object.assign(nums(cell, ['width', 'height'])) : null };
  return { block, rows };
}

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  must(Array.isArray(el.path.data), 'a path proxy was made static');
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};

// the <path> elements of the SVG with a series and data index: [{si, di, m0 [x, y] (the first coordinate pair of
// d), attrs}]
function svgPaths(svg) {
  const out = [];
  const re = /<path\b([^>]*)>/g;
  let mm;
  while ((mm = re.exec(svg))) {
    const a = mm[1];
    const g = n => { const r = new RegExp('(?:^|\\s)' + n + '="([^"]*)"').exec(a); return r ? r[1] : null; };
    const si = g('ecmeta_series_index');
    const di = g('ecmeta_data_index');
    if (si == null || di == null) continue;
    const numOrNull = s => (s == null ? null : Number(s));
    const fill = g('fill');
    const stroke = g('stroke');
    const dash = g('stroke-dasharray');
    const d = g('d') || '';
    const m0 = /^M(\S+) (\S+?)(?=[A-Za-z ])/.exec(d);
    out.push({ si: +si, di: +di, d, m0: m0 ? [Number(m0[1]), Number(m0[2])] : null,
      attrs: { fill: fill != null && /^url\(/.test(fill) ? 'url' : fill, fillOpacity: numOrNull(g('fill-opacity')),
        stroke: stroke != null && /^url\(/.test(stroke) ? 'url' : stroke, strokeWidth: numOrNull(g('stroke-width')), strokeOpacity: numOrNull(g('stroke-opacity')),
        dash: dash == null ? null : dash.split(',').map(Number), dashOffset: numOrNull(g('stroke-dashoffset')),
        lineCap: g('stroke-linecap'), lineJoin: g('stroke-linejoin'), miterLimit: g('stroke-miterlimit') } });
  }
  return out;
}

function readLabel(el) {
  const t = el.getTextContent();
  if (!t || t.ignore) return null;
  const s = t.style;
  must(!s.rich, 'a rich heatmap label');
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  const txt = s.text == null ? null : String(s.text);
  must(kids.every(k => k.type === 'tspan' || (k.type === 'rect' && s.backgroundColor)), 'a plain label with children ' + kids.map(k => k.type).join());
  must((spans.length >= 1) === (txt != null && txt !== ''), 'a label TSpan / text mismatch');
  let ink = null;
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
  const it = t.innerTransformable;
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  const tc = el.textConfig;
  const rect = el.getBoundingRect().clone();
  rect.applyTransform(el.transform);
  const position = tc.position;
  const inside = typeof position === 'string' && position.indexOf('inside') >= 0 && el.hasFill();
  return Object.assign({ text: txt, lines: spans.length, position: json(position), distance: hex(tc.distance), distanceText: text(tc.distance) },
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

// visualSolution.incrementalApplyVisual (visualSolution.ts:199-252) for one row, run on upstream's own visualMap
// models and mappings: the visuals every targeting visualMap WRITES (component order), each seeded with what the
// row holds so far (the series style colour / opacity). -> null (no visualMap targets the series) or
// {vms: [{index, value, state, skipped}], wrote: {color?, opacity?}}
function vmOf(ec, sm, data, i) {
  const vms = [];
  ec.eachComponent('visualMap', vm => { if (vm.isTargetSeries(sm)) vms.push(vm); });
  if (!vms.length) return null;
  const ss = data.getVisual('style');
  const drawType = data.getVisual('drawType');
  const cur = { color: ss[drawType], opacity: ss.opacity };
  const wrote = {};
  const rec = [];
  const raw = data.getRawDataItem(i);
  for (const vm of vms) {
    if (raw && raw.visualMap === false) {
      rec.push({ index: vm.componentIndex, value: null, valueText: null, state: null, skipped: true });
      continue;
    }
    const dim = vm.getDataDimensionIndex(data);
    must(dim != null, 'a visualMap without a data dimension');
    const value = data.getStore().get(data.getDimensionIndex(dim), i);
    const state = vm.getValueState(value);
    const mappings = vm.targetVisuals[state];
    const anyMapping = mappings[Object.keys(mappings)[0]];
    const types = anyMapping.constructor.prepareVisualTypes(mappings);
    for (const type of types) {
      if (!mappings[type]) continue;
      mappings[type].applyVisual(value, k => (k === 'color' || k === 'opacity' ? cur[k] : undefined), (k, v) => {
        if (k === 'color' || k === 'opacity') { cur[k] = v; wrote[k] = v; } else must(k === 'symbol' || k === 'symbolSize' || k === 'liftZ', 'a visual ' + k);
      });
    }
    rec.push({ index: vm.componentIndex, value: hex(value), valueText: text(value), state, skipped: false });
  }
  return { vms: rec, wrote };
}
function vmRec(v) {
  if (!v) return null;
  const w = v.wrote;
  return { vms: v.vms, color: 'color' in w ? paint(w.color) : null, colorWritten: 'color' in w,
    opacity: 'opacity' in w ? hexOrNull(w.opacity) : null, opacityText: 'opacity' in w ? textOrNull(w.opacity) : null, opacityWritten: 'opacity' in w };
}

function axisRec(axis) {
  const scale = axis.scale;
  const e = scale.getExtent().slice();
  const px = axis.getExtent().slice();
  const cats = axis.type === 'category' ? scale.getOrdinalMeta().categories.slice() : null;
  return { raw: { type: axis.type, onBand: !!axis.onBand, inverse: !!axis.inverse, extent: e, px, categories: cats },
    rec: Object.assign({ type: axis.type, onBand: !!axis.onBand, inverse: !!axis.inverse }, pair(e, 'extent'), pair(px, 'px'),
      { categories: cats ? json(cats) : null }) };
}

// HeatmapView.ts:216-227 on upstream's values: the FIRST failing test in upstream's || order, null = drawn
function skipOf(p, xe, ye) {
  return isNaN(p[2]) ? 'value' : isNaN(p[0]) ? 'x' : isNaN(p[1]) ? 'y' : p[0] < xe[0] ? 'x<' : p[0] > xe[1] ? 'x>' : p[1] < ye[0] ? 'y<' : p[1] > ye[1] ? 'y>' : null;
}

// every row of one heatmap series: {block, rows (per data index), rawIndices, inputs}
function readSeries(chart, sm, svgList) {
  const ec = chart.getModel();
  const data = sm.getData();
  const view = chart.getViewOfSeriesModel(sm);
  const group = view.group;
  for (let p = group; p; p = p.parent) must(!p.transform || p.transform.join() === '1,0,0,1,0,0', 'a transformed ancestor');
  const cs = sm.coordinateSystem;
  must(cs && cs.type === 'cartesian2d', 'not cartesian2d');
  const dims = [data.mapDimension('x'), data.mapDimension('y'), data.mapDimension('value')];
  must(JSON.stringify(dims) === JSON.stringify(DIMS) && JSON.stringify(data.dimensions) === JSON.stringify(DIMS), 'heatmap dims ' + JSON.stringify(dims));
  const gridRect = cs.master.getRect();
  const ax = axisRec(cs.getAxis('x'));
  const ay = axisRec(cs.getAxis('y'));
  const rows = [];
  const inputs = [];
  const rawIndices = [];
  const drawn = [];
  let cell = null;
  for (let i = 0; i < data.count(); i++) {
    const rawIndex = data.getRawIndex(i);
    rawIndices.push(rawIndex);
    const raw = data.getRawDataItem(i);
    const parsed = [data.get('x', i), data.get('y', i), data.get('value', i)];
    const point = cs.dataToPoint([parsed[0], parsed[1]]);
    const vm = vmOf(ec, sm, data, i);
    inputs.push({ raw: zrClone(raw), rawIndex, parsed, point: point.slice(), vm });
    const el = data.getItemGraphicEl(i);
    const row = Object.assign({ raw: json(raw) }, pair(parsed, 'parsed'), { name: data.getName(i) }, { point: pt(point), pointText: ptText(point) },
      { vm: vmRec(vm), visual: visualRec(data.getItemVisual(i, 'style')), drawn: !!el, skip: skipOf(parsed, ax.raw.extent, ay.raw.extent) });
    must((row.skip == null) === !!el, 'cell ' + i + ': drawn is not the HeatmapView skip test (' + row.skip + ')');
    if (!el) {
      row.rect = row.label = null;
      rows.push(row);
      continue;
    }
    drawn.push(el);
    must(el.type === 'rect' && !el.transform && !el.needLocalTransform() && !el.subPixelOptimize, 'cell ' + i + ' is not a plain untransformed Rect');
    must(el.style !== data.getItemVisual(i, 'style'), 'the cell style is the visual object itself');
    const sh = el.shape;
    if (!cell) cell = { width: sh.width, height: sh.height };
    must(Object.is(sh.width, cell.width) && Object.is(sh.height, cell.height), 'cells of different sizes');
    const cands = svgList.filter(p => p.si === sm.seriesIndex && p.di === i);
    must(cands.length >= 1, 'no SVG <path> for cell ' + i + ' of series ' + sm.seriesIndex);
    must(cands.every(c => JSON.stringify(c.attrs) === JSON.stringify(cands[0].attrs)), 'ambiguous SVG <path> for cell ' + i);
    const pdata = pathOf(el);
    const near = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || Math.abs(a - b) <= 0.05 + 1e-9;
    // the SVG path builder drops a path with NaN coordinates: d = ''
    const nanStart = Number.isNaN(pdata[1]) || Number.isNaN(pdata[2]);
    must(nanStart ? cands[0].d === '' : cands[0].m0 && near(cands[0].m0[0], pdata[1]) && near(cands[0].m0[1], pdata[2]), 'the SVG path does not start at the path start for cell ' + i + ': ' + JSON.stringify(cands[0].m0) + ' vs ' + pdata.slice(1, 3));
    const bb = el.path.getBoundingRect();
    const rect = el.getBoundingRect();
    row.rect = Object.assign({ shape: Object.assign(nums(sh, ['x', 'y', 'width', 'height']), { r: json(sh.r) }), path: decode(pdata) },
      rectRec(bb, 'bbox'), rectRec(rect, 'rect'),
      { style: styleRec(el.style), svg: svgRec(cands[0].attrs), z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.isSilent() });
    row.label = readLabel(el);
    if (row.label) {
      const t = el.getTextContent();
      const tc = el.textConfig;
      const c = calculateTextPosition(tc.position, tc.distance, el.getBoundingRect());
      const off = tc.offset || [0, 0];
      must(Object.is(t.innerTransformable.x, c.x + off[0]) && Object.is(t.innerTransformable.y, c.y + off[1]), 'the label placement is not calculateTextPosition on the rect at cell ' + i);
    }
    rows.push(row);
  }
  must(group.childrenRef().length === drawn.length && group.childrenRef().every((c, k) => c === drawn[k]), 'the view group children are not the drawn cells in order');
  for (let k = 1; k < rawIndices.length; k++) must(rawIndices[k] > rawIndices[k - 1], 'raw indices not increasing');
  const ss = data.getVisual('style');
  const block = { z: json(sm.get('z') || 0), zlevel: json(sm.get('zlevel') || 0), silent: !!group.silent, seriesStyle: visualRec(ss),
    cell: cell ? nums(cell, ['width', 'height']) : null };
  return { block, rows, rawIndices, inputs, grid: rectRec(gridRect, 'grid'), axes: { x: ax, y: ay }, hasItemOption: !!data.hasItemOption, count: data.count() };
}

function runChart(E, option, fn) {
  rngState = SEED;
  const chart = E.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(option);
    chart.getZr().storage.getDisplayList(true);
    const svg = chart.renderToSVGString();
    return fn(chart, svg);
  } finally {
    chart.dispose();
  }
}

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const heatmaps = option => seriesArray(option).map((s, i) => (s && s.type === 'heatmap' ? i : -1)).filter(i => i >= 0);

function recordWith(E, def, optionText, side) {
  const input = JSON.parse(optionText);
  const hms = heatmaps(input);
  must(hms.length, 'no heatmap series');
  return runChart(E, JSON.parse(optionText), (chart, svg) => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const svgList = svgPaths(svg);
    const series = hms.map(si => {
      const sm = ec.getSeriesByIndex(si);
      const data = sm.getData();
      const filtered = ec.isSeriesFiltered(sm);
      const c = data.getVisual('style')[data.getVisual('drawType')];
      const opt = seriesArray(input)[si];
      const sr = { seriesIndex: si, name: opt.name == null ? null : String(opt.name), filtered, color: paint(c),
        seriesName: opt.name == null ? null : sm.name, heatmap: null };
      if (filtered) return sr;
      const r = readSeries(chart, sm, svgList);
      // the series option as upstream holds it = the option as fed merged over HM_DEFAULTS (checked on the keys read)
      const seriesOpt = zrMerge(zrClone(opt), HM_DEFAULTS);
      for (const k of ['itemStyle', 'label', 'z', 'zlevel', 'silent']) {
        must(JSON.stringify(json(sm.option[k]) || {}) === JSON.stringify(json(seriesOpt[k]) || {}), 'the series option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(sm.option[k]));
      }
      const inp = { seriesOpt, color: c, seriesName: sr.seriesName, textStyle: ec.option.textStyle, ground,
        axes: { x: r.axes.x.raw, y: r.axes.y.raw }, rows: r.inputs };
      const key = def.id + '/' + si;
      const run = mut => {
        try {
          return transcribe(zrClone(inp), mut);
        } catch (e) {
          if (e instanceof OracleError && !Object.keys(mut).length) throw e;
          return { threw: String(e.message) };
        }
      };
      side[key] = { base: run({}), muts: {} };
      for (const gd of GUARDS) side[key].muts[gd.id] = run(gd.mut);
      // one row per ORIGINAL data element
      const optData = opt.data || [];
      const rows = [];
      for (let k = 0; k < optData.length; k++) {
        const j = r.rawIndices.indexOf(k);
        rows.push(Object.assign({ index: k, dataIndex: j >= 0 ? j : null }, j >= 0 ? r.rows[j] : {}));
      }
      must(r.rawIndices.every(k => k < optData.length), 'a raw index beyond the option data');
      sr.heatmap = Object.assign({}, r.block, { count: r.count, rawCount: optData.length, hasItemOption: r.hasItemOption }, r.grid, {
        axes: { x: r.axes.x.rec, y: r.axes.y.rec } }, { rows });
      return sr;
    });
    return { ground, textStyle, series };
  });
}

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  let productionBuild = false;
  let devError = null;
  let base;
  let local = {};
  try {
    base = recordWith(echarts, def, optionText, local);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    devError = String(e.message);
    local = {};
    base = recordWith(PROD, def, optionText, local);
    productionBuild = true;
  }
  must(!!def.prod === productionBuild, productionBuild ? 'the development build threw (' + devError + ') although the case is not marked prod' : 'expected the development build to throw');
  if (!productionBuild) {
    const p = recordWith(PROD, def, optionText, {});
    must(JSON.stringify(p) === JSON.stringify(base), 'the production build records differently');
  }
  Object.assign(side, local);
  return Object.assign({ id: def.id, note: def.note, width: W, height: H, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    nan: !!def.nan, productionBuild, devError }, base);
}

// ============================================================================
// The cases
// ============================================================================
const G = { left: 80.5, right: 60.25, top: 50.75, bottom: 70.4 };
const cats = (p, n) => Array.from({ length: n }, (_, i) => p + i);
const lattice = (nx, ny, f) => {
  const d = [];
  for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) d.push([i, j, f(i, j)]);
  return d;
};
const f11 = (i, j) => (i * 7 + j * 3) % 11;
// a category x category chart: nx x ny categories 'x0'.. / 'y0'.., the default continuous visualMap 0..10
const hm = (nx, ny, data, extra, seriesExtra) => Object.assign({ animation: false, grid: G, xAxis: { type: 'category', data: cats('x', nx) },
  yAxis: { type: 'category', data: cats('y', ny) }, visualMap: { min: 0, max: 10 },
  series: [Object.assign({ type: 'heatmap', name: 'H', data }, seriesExtra || {})] }, extra || {});
const WEEK = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const POS13 = ['top', 'bottom', 'left', 'right', 'inside', 'insideLeft', 'insideRight', 'insideTop', 'insideBottom', 'insideTopLeft', 'insideTopRight', 'insideBottomLeft', 'insideBottomRight'];
const BAND_FILLS = ['#ffffff', '#808080', '#04c26d', 'rgba(255,255,255,0.4)', 'rgba(255,255,255,0.5)', 'rgba(255,255,255,0.2)', 'rgba(0,0,0,0.4)', '#333333',
  'transparent', 'hsl(0,0%,100%)', 'hsla(0,0%,100%,0.3)'];
// items {value: [k % cols, floor(k / cols), v], ...extra} over a cols-wide lattice
const items = (extras, cols) => extras.map((e, k) => Object.assign({ value: [k % cols, Math.floor(k / cols), (k * 3) % 11] }, e));

const CASES = [
  // ----- geometry -----
  { id: 'G1', note: "3 x 2 categories on a fractional grid, [x, y, v] arrays, the default continuous visualMap 0..10: cell = (band + 0.5) centred on dataToPoint; values 0 and 10 on the range edges, 12 and -1 BEYOND min / max but still inRange (the default unbounded range: they take the end colours), 7.5 between stops; no opacity is written",
    option: hm(3, 2, [[0, 0, 0], [1, 0, 5], [2, 0, 10], [0, 1, 12], [1, 1, -1], [2, 1, 7.5]]) },
  { id: 'G2', note: 'a 1 x 1 grid: one cell spanning the whole grid plus the half pixel', option: hm(1, 1, [[0, 0, 4]]) },
  { id: 'G3', note: 'a 24 x 7 grid without labels (the gallery case has them): 168 cells, quarter values',
    option: hm(24, 7, lattice(24, 7, (i, j) => f11(i, j) + (i % 4) * 0.25)) },
  { id: 'G4', note: 'inverse x AND inverse y (4 x 3): the points run right-to-left / top-to-bottom, the cell size is unchanged (the band uses |px span|)',
    option: hm(4, 3, lattice(4, 3, f11), { xAxis: { type: 'category', inverse: true, data: cats('x', 4) }, yAxis: { type: 'category', inverse: true, data: cats('y', 3) } }, { label: { show: true } }) },
  { id: 'G5', note: "the forms of x / y on WEEK x [am, pm]: a category name ('Tue', 'pm'), an index, 2.5 (the store keeps 2.5 -- inside the extent -- but dataToPoint rounds it with Math.round: drawn ON the x3 band, name ''), -1 and 7 (outside the scale extent [0, 6]: skipped), 'Nope' (NaN: skipped), 6.9999 / 6.4 / -0.4 (skipped: the extent test sees the UNROUNDED value), y 'nope' (NaN), y 2 / -0.5 (outside [0, 1]); labels '{b}' print the names",
    option: { animation: false, grid: G, xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'category', data: ['am', 'pm'] }, visualMap: { min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'F', label: { show: true, formatter: '{b}' },
        data: [['Tue', 'am', 3], [2, 'pm', 4], [2.5, 0, 5], [-1, 0, 6], [7, 1, 7], ['Nope', 0, 8], [6.9999, 1, 2], [0, 'nope', 1], [0, 2, 9], [1, -0.5, 3], ['Sun', 'pm', 1], [6.4, 0, 2], [-0.4, 1, 3]] }] } },
  { id: 'G6', note: "value forms (labels shown: default text = String(raw value)): 5, '-', null, a missing third value, 'abc' (all but 5 NaN: skipped); '07' (parsed 7, text '07'), '1e1' (10, text '1e1'), ' 3 ' (3, text ' 3 '), 0, 5.25, 'Infinity' (parsed +Infinity: drawn)",
    option: hm(4, 3, [[0, 0, 5], [1, 0, '-'], [2, 0, null], [3, 0], [0, 1, 'abc'], [1, 1, '07'], [2, 1, '1e1'], [3, 1, ' 3 '], [0, 2, 0], [1, 2, 5.25], [2, 2, 'Infinity']], null, { label: { show: true } }) },
  { id: 'G7', note: "dataZoom windows in 'filter' mode on both axes (inside x 30..70 % of 10 categories, slider y 20..80 % of 6): the rows outside are REMOVED from the data (dataIndex null); the band is |px| / (window span + 1); four extra rows first -- [0, 2] (filtered out), [4.5, 2] (kept; drawn on the x5 band: Math.round), [3, 2], ['Nope', 2] (NaN is never filtered): a row whose own category does not exist gets its name from getIdNameFromStore reading the FILTERED store at its RAW index -- the 4.5 cell's '{b}' label prints the NEXT kept row's category 'x3', the NaN row's name is another row's category",
    option: hm(10, 6, [[0, 2, 1], [4.5, 2, 5], [3, 2, 3], ['Nope', 2, 4]].concat(lattice(10, 6, f11)), { dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 30, end: 70 }, { type: 'slider', yAxisIndex: 0, start: 20, end: 80 }] }, { label: { show: true, formatter: '{b}' } }) },
  { id: 'G8', note: "dataZoom filterMode 'none' on both axes (x startValue 2 .. endValue 5, y 1 .. 3 of 8 x 5): every row stays in the data; the view skips the ones outside the scale extent (skip x< / x> / y< / y>)",
    option: hm(8, 5, lattice(8, 5, f11), { dataZoom: [{ type: 'inside', xAxisIndex: 0, filterMode: 'none', startValue: 2, endValue: 5 }, { type: 'inside', yAxisIndex: 0, filterMode: 'none', startValue: 1, endValue: 3 }] }, { label: { show: true } }) },
  { id: 'G9', note: "a grid given as left '7.7%', top 33.3, width 511.1, height 377.7 (5 x 4): fractional band widths",
    option: hm(5, 4, lattice(5, 4, f11), { grid: { left: '7.7%', top: 33.3, width: 511.1, height: 377.7 } }) },
  { id: 'G10', note: "two heatmaps on one grid, each with its own visualMap (seriesIndex): series B (z 3) has inRange ['#fff', '#c00'] and labels; its cells cover A's",
    option: { animation: false, grid: G, xAxis: { type: 'category', data: cats('x', 4) }, yAxis: { type: 'category', data: cats('y', 3) },
      visualMap: [{ seriesIndex: 0, min: 0, max: 10 }, { seriesIndex: 1, min: 0, max: 10, inRange: { color: ['#fff', '#c00'] }, show: false }],
      series: [{ type: 'heatmap', name: 'A', data: lattice(4, 3, f11) }, { type: 'heatmap', name: 'B', z: 3, label: { show: true }, data: [[0, 0, 3], [3, 2, 8], [1, 1, 5]] }] } },
  { id: 'G11', note: 'two grids side by side (a percent right / left each), a heatmap on each (3 x 2 and 5 x 3); one visualMap targets both',
    option: { animation: false, grid: [{ left: 50.5, right: '55%', top: 60, bottom: 80 }, { left: '52%', right: 40.25, top: 60, bottom: 80 }],
      xAxis: [{ type: 'category', data: cats('a', 3), gridIndex: 0 }, { type: 'category', data: cats('b', 5), gridIndex: 1 }],
      yAxis: [{ type: 'category', data: cats('c', 2), gridIndex: 0 }, { type: 'category', data: cats('d', 3), gridIndex: 1 }],
      visualMap: { min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'L', data: lattice(3, 2, f11) }, { type: 'heatmap', name: 'R', xAxisIndex: 1, yAxisIndex: 1, data: lattice(5, 3, f11) }] } },
  { id: 'G12', prod: true, note: "PRODUCTION build (the development build throws 'must have two axes with boundaryGap true'): x boundaryGap false -- the band is |px| / span (no + 1), the cells sit on the ticks and the end cells overhang the grid by half a cell",
    option: hm(4, 3, lattice(4, 3, f11), { xAxis: { type: 'category', boundaryGap: false, data: cats('x', 4) } }, { label: { show: true } }) },
  { id: 'G13', prod: true, note: 'PRODUCTION build: a 1 x 1 grid with boundaryGap false on both axes: span 0 -> len 0 -> 1 (Fix #2728): the cell is the whole px span + 0.5 on each axis',
    option: hm(1, 1, [[0, 0, 6]], { xAxis: { type: 'category', boundaryGap: false, data: ['x0'] }, yAxis: { type: 'category', boundaryGap: false, data: ['y0'] } }, { label: { show: true } }) },
  { id: 'G14', prod: true, nan: true, note: "PRODUCTION build ('must have two category axes' in development): a VALUE x axis: calcBandWidth has no band for it -> width NaN, x NaN; the cells are still added (NaN rects; SVG prints NaN) and their labels sit at NaN x; the category y keeps its band",
    option: { animation: false, grid: G, xAxis: { type: 'value' }, yAxis: { type: 'category', data: ['a', 'b'] }, visualMap: { min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'V', label: { show: true }, data: [[0, 0, 5], [1.5, 1, 3], [3, 0, 8]] }] } },
  { id: 'G15', prod: true, nan: true, note: "PRODUCTION build: two TIME axes: both sizes NaN, every cell rect NaN; the name is '' (no category dim)",
    option: { animation: false, grid: G, xAxis: { type: 'time' }, yAxis: { type: 'time' }, visualMap: { min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'T', data: [[Date.UTC(2024, 0, 1), Date.UTC(2024, 0, 1), 5], [Date.UTC(2024, 0, 2), Date.UTC(2024, 0, 3), 2]] }] } },
  { id: 'G16', prod: true, note: "PRODUCTION build ('must use with visualMap'): NO visualMap: every cell takes the series palette colour ('#5070dd', the second series '#b6d634'); inside labels on it (no visualMap record: vm null)",
    option: { animation: false, grid: G, xAxis: { type: 'category', data: cats('x', 3) }, yAxis: { type: 'category', data: cats('y', 2) },
      series: [{ type: 'heatmap', name: 'P', label: { show: true }, data: [[0, 0, 1], [1, 1, 2]] }, { type: 'heatmap', name: 'Q', label: { show: true }, data: [[2, 0, 3], [0, 1, 4]] }] } },
  { id: 'G17', prod: true, note: 'PRODUCTION build: a visualMap with seriesIndex 0 only: series 1 (no visualMap -> the development build throws) keeps its palette colour; series 0 is coloured',
    option: { animation: false, grid: G, xAxis: { type: 'category', data: cats('x', 3) }, yAxis: { type: 'category', data: cats('y', 2) }, visualMap: { seriesIndex: 0, min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'C', data: lattice(3, 1, f11) }, { type: 'heatmap', name: 'U', data: [[0, 1, 4], [2, 1, 9]] }] } },
  { id: 'G18', note: "hasItemOption: arrays mixed with {value} items; the label chain item -> series (series label show false, formatter '{b}|{c}'): items with label.show true print it -- names: an item name 'named', a numeric name 7 -> '7', a BOOLEAN name (convertOptionIdName drops it -> the category name)",
    option: hm(3, 2, [[0, 0, 1], { value: [1, 0, 2] }, { value: [2, 0, 3], name: 'named', label: { show: true } }, { value: [0, 1, 4], label: { show: true } },
      { value: [1, 1, 5], name: 7, label: { show: true } }, { value: [2, 1, 6], name: true, label: { show: true } }], null, { label: { show: false, formatter: '{b}|{c}' } }) },
  // ----- style -----
  { id: 'S1', note: "item itemStyle (after the visualMap: it wins): color '#c00'; borderColor '#000' + borderWidth 2 (label rect grows 1 each side); opacity 0.5 (label opacity defaults to it); borderType 'dashed' at 1 ([4, 2]); borderDashOffset 2.6 (SVG 3); shadow keys; borderCap / borderJoin / borderMiterLimit; color 'none' + borderColor '#000' (no fill: the inside label takes OUTSIDE ink, the rect grows max(1, 5)); color 'transparent' (kept); labels shown",
    option: hm(4, 3, items([{ itemStyle: { color: '#c00' } }, { itemStyle: { borderColor: '#000', borderWidth: 2 } }, { itemStyle: { opacity: 0.5 } },
      { itemStyle: { borderType: 'dashed', borderWidth: 1, borderColor: '#333' } }, { itemStyle: { borderType: 'dashed', borderWidth: 1, borderColor: '#333', borderDashOffset: 2.6 } },
      { itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.5)', shadowOffsetX: 2, shadowOffsetY: 3 } },
      { itemStyle: { borderColor: '#036', borderWidth: 4, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4 } },
      { itemStyle: { color: 'none', borderColor: '#000', borderWidth: 1 } }, { itemStyle: { color: 'transparent' } }, {}], 4), null, { label: { show: true } }) },
  { id: 'S2', note: "borderRadius (shape.r; the item chain item -> series): series 4 on plain cells; items [2, 8], [0, 0, 0, 0] (truthy: the round-rect path with no arcs), 100 (clamped by the r1 + r2 > width scaling), [3], [1, 2, 3], [5, 0, 10, 0], 0 (falsy: a plain rect), 6 with borderWidth 2; labels shown on the arc bboxes",
    option: hm(4, 3, items([{}, { itemStyle: { borderRadius: [2, 8] } }, { itemStyle: { borderRadius: [0, 0, 0, 0] } }, { itemStyle: { borderRadius: 100 } }, { itemStyle: { borderRadius: [3] } },
      { itemStyle: { borderRadius: [1, 2, 3] } }, { itemStyle: { borderRadius: [5, 0, 10, 0] } }, { itemStyle: { borderRadius: 0 } }, { itemStyle: { borderRadius: 6, borderWidth: 2, borderColor: '#fff' } }], 3),
    null, { itemStyle: { borderRadius: 4 }, label: { show: true } }) },
  { id: 'S3', note: "series itemStyle {color '#0a0', opacity 0.6, borderColor '#fff', borderWidth 1}: the visualMap colour REPLACES the series colour, opacity and border stay (label opacity 0.6); the rect grows 0.5 each side",
    option: hm(3, 2, lattice(3, 2, f11), null, { itemStyle: { color: '#0a0', opacity: 0.6, borderColor: '#fff', borderWidth: 1 }, label: { show: true } }) },
  { id: 'S4', note: "items with visualMap: false keep the series palette colour (the encoder skips them); one also has an item colour",
    option: hm(3, 1, [[0, 0, 2], { value: [1, 0, 8], visualMap: false }, { value: [2, 0, 5], visualMap: false, itemStyle: { color: '#123' } }], null, { label: { show: true } }) },
  // ----- visualMap -----
  { id: 'V1', note: "continuous inRange ['#313695', '#ffffbf', '#a50026'], min -10 max 30: -10 / 30 on the edges, 0 / 10 / 20 / 5.5 between the stops, -20 / 40 beyond min / max yet inRange (unboundedRange: the end colours)",
    option: hm(4, 2, [[0, 0, -20], [1, 0, -10], [2, 0, 0], [3, 0, 10], [0, 1, 20], [1, 1, 30], [2, 1, 40], [3, 1, 5.5]], { visualMap: { min: -10, max: 30, inRange: { color: ['#313695', '#ffffbf', '#a50026'] } } }, { label: { show: true } }) },
  { id: 'V2', note: 'continuous range [2, 8] of 0..10: values below 2 / above 8 take the outOfRange visuals (colour + opacity)',
    option: hm(6, 2, lattice(6, 2, (i, j) => i * 2 + j), { visualMap: { min: 0, max: 10, range: [2, 8] } }) },
  { id: 'V3', note: "continuous range [1, 9] of 0..10, inRange {color ['#ddd', '#036'], opacity [0.3, 1]}, outOfRange {color '#999', opacity 0.2}: the vm writes style.opacity (in and out of range); the label opacity follows the cell's",
    option: hm(4, 2, [[0, 0, 0], [1, 0, 2.5], [2, 0, 5], [3, 0, 10], [0, 1, 12], [1, 1, -3], [2, 1, 7], [3, 1, 9]], { visualMap: { min: 0, max: 10, range: [1, 9], inRange: { color: ['#ddd', '#036'], opacity: [0.3, 1] }, outOfRange: { color: '#999', opacity: 0.2 } } }, { label: { show: true } }) },
  { id: 'V4', note: "piecewise pieces [0, 3] '#0a0', [3, 6] '#fa0', > 6 '#c00', outOfRange '#ccc': values -1, 0, 3, 4.5, 6, 9, 20",
    option: hm(4, 2, [[0, 0, -1], [1, 0, 0], [2, 0, 3], [3, 0, 4.5], [0, 1, 6], [1, 1, 9], [2, 1, 20]],
      { visualMap: { type: 'piecewise', pieces: [{ min: 0, max: 3, color: '#0a0' }, { min: 3, max: 6, color: '#fa0' }, { gt: 6, color: '#c00' }], outOfRange: { color: '#ccc' } } }, { label: { show: true } }) },
  { id: 'V5', note: 'piecewise splitNumber 4 over 0..12 with piece 1 deselected (selected {1: false}): its values go outOfRange',
    option: hm(7, 1, lattice(7, 1, i => i * 2), { visualMap: { type: 'piecewise', min: 0, max: 12, splitNumber: 4, selected: { 1: false } } }, { label: { show: true } }) },
  { id: 'V6', note: 'visualMap dimension 0: the colour follows x (0..3), not the value',
    option: hm(4, 2, lattice(4, 2, f11), { visualMap: { min: 0, max: 3, dimension: 0 } }) },
  // ----- labels -----
  { id: 'L1', note: "labels shown with the global textStyle {fontSize 13, fontWeight 600}: default text, 'inside', ink bands against the vm colours",
    option: hm(6, 3, lattice(6, 3, (i, j) => i * 2 - j), { textStyle: { fontSize: 13, fontWeight: 600 } }, { label: { show: true } }) },
  { id: 'L2', note: "formatter templates on a NAMED series 'Temps' over WEEK x [am, pm] (series '{a}|{b}|{c}': {c} = the raw value ARRAY printed 'Mon,am,3'); items: '{@[2]}', '{@value}', '{@x}/{@y}' (raw x / y as written), '{@[5]}' -> '', '{@nope}' -> '', '{c} {c}' (first only), '' -> '', '{@1}' (number-like: dim 1), '{@[]}' (dim 0), '{b0}'",
    option: { animation: false, grid: G, xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'category', data: ['am', 'pm'] }, visualMap: { min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'Temps', label: { show: true, formatter: '{a}|{b}|{c}' },
        data: [['Mon', 'am', 3], { value: [1, 0, 4], label: { formatter: '{@[2]}' } }, { value: ['Wed', 0, 5.5], label: { formatter: '{@value}' } }, { value: ['Thu', 'am', 6], label: { formatter: '{@x}/{@y}' } },
          { value: [4, 0, 7], label: { formatter: '{@[5]}' } }, { value: [5, 0, 8], label: { formatter: '{@nope}' } }, { value: [6, 0, 9], label: { formatter: '{c} {c}' } },
          { value: [0, 1, 1], label: { formatter: '' } }, { value: [1, 1, 2], label: { formatter: '{@1}' } }, { value: [2, 1, 3], label: { formatter: '{@[]}' } }, { value: [3, 1, 4], label: { formatter: '{b0}' } }] }] } },
  { id: 'L3', note: "every position (13) + 'outside' (-> 'top') + an array ['30%', 5]; series label distance 8",
    option: hm(4, 4, items(POS13.concat(['outside']).map(p => ({ label: { position: p } })).concat([{ label: { position: ['30%', 5] } }]), 4), null, { label: { show: true, distance: 8 } }) },
  { id: 'L4', note: "label colours and placement: color '#f0f' (no auto stroke); color 'inherit' -> NULL (no inheritColor on a heatmap: the automatic inside ink); textBorderColor 'inherit' + textBorderWidth 3 on a 'bottom' label (-> null: the automatic halo, at width 3); opacity 0.5; backgroundColor '#ff0' on a 'top' label (no automatic halo); rotate 45; offset [10, -5]; align 'right' + verticalAlign 'top'; align 'middle' -> 'center'; baseline 'bottom'; silent",
    option: hm(4, 3, items([{ label: { color: '#f0f' } }, { label: { color: 'inherit' } }, { label: { textBorderColor: 'inherit', textBorderWidth: 3, position: 'bottom' } }, { label: { opacity: 0.5 } },
      { label: { backgroundColor: '#ff0', position: 'top' } }, { label: { rotate: 45 } }, { label: { offset: [10, -5] } }, { label: { align: 'right', verticalAlign: 'top' } },
      { label: { align: 'middle' } }, { label: { baseline: 'bottom' } }, { label: { silent: true } }], 4), null, { label: { show: true } }) },
  { id: 'L5', note: "inside ink bands against item colours WITH alpha (lum over black): '#fff' '#333'; '#808080' (0.502) '#333'; '#04c26d' (exactly 0.5) '#eee'; rgba(255,255,255,0.4) '#eee'; 0.5 alpha (exactly 0.5) '#eee'; 0.2 alpha (exactly 0.2) '#ccc'; rgba(0,0,0,0.4) '#ccc'; '#333' (0.19999) '#ccc'; 'transparent' '#ccc'; hsl white '#333'; hsla 0.3 '#eee'; the last cell keeps its vm colour",
    option: hm(4, 3, items(BAND_FILLS.map(c => ({ itemStyle: { color: c } })).concat([{}]), 4), null, { label: { show: true } }) },
  { id: 'L6', note: "darkMode true + backgroundColor '#1e1e1e': inside labels stroked only when DARK ('#333' on light fills); a 'top' label '#ccc' with the halo 'rgba(30,30,30,1)'",
    option: hm(4, 2, items([{}, { itemStyle: { color: '#fff' } }, { itemStyle: { color: '#222' } }, { label: { position: 'top' } }, { itemStyle: { color: '#ffffbf' } }, {}, {}, {}], 4),
      { darkMode: true, backgroundColor: '#1e1e1e' }, { label: { show: true } }) },
  { id: 'L7', note: "labels on stroked cells (series borderColor '#fff', borderWidth 3: the label rect grows 1.5 each side): 'top', 'bottom', 'insideTop' items; an item color 'none' + borderWidth 1 (growth max(1, 5) = 2.5, outside ink); borderWidth 0.5",
    option: hm(3, 2, items([{ label: { position: 'top' } }, { label: { position: 'bottom' } }, { label: { position: 'insideTop' } }, { itemStyle: { color: 'none', borderWidth: 1 }, label: { position: 'insideTop' } },
      { itemStyle: { borderWidth: 0.5 } }, {}], 3), null, { itemStyle: { borderColor: '#fff', borderWidth: 3 }, label: { show: true } }) },
  // ----- z / silent / hidden -----
  { id: 'Z1', note: "series z 5, zlevel 1, silent true (the view group silent: every cell isSilent); label.silent; emphasis {itemStyle shadow, label show} -- the emphasis state is NOT recorded (note only)",
    option: hm(2, 2, lattice(2, 2, f11), null, { z: 5, zlevel: 1, silent: true, label: { show: true, silent: true }, emphasis: { itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.5)' }, label: { show: true } } }) },
  { id: 'Z2', note: 'a legend-unselected heatmap draws nothing (filtered, heatmap null); the shown one does',
    option: { animation: false, grid: G, legend: { selected: { hidden: false } }, xAxis: { type: 'category', data: cats('x', 2) }, yAxis: { type: 'category', data: cats('y', 2) }, visualMap: { min: 0, max: 10 },
      series: [{ type: 'heatmap', name: 'hidden', data: [[0, 0, 1]] }, { type: 'heatmap', name: 'shown', data: [[1, 1, 9]] }] } },
];
CASES.push({ id: 'G-heatmap-cartesian', gallery: 'heatmap-cartesian', note: "gallery heatmap-cartesian.json, verbatim: 24 x 7 'Punch Card' with '-' holes (skipped), a calculable horizontal continuous visualMap 0..10 (values 11-14 beyond max: still inRange, the end colour), labels shown (default text), grid height 50 % top 10 %" });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'no-half-px', mutation: 'the cell size without the + 0.5', mut: { noHalfPx: true }, named: ['G1', 'G2'] },
  { id: 'band-from-count', mutation: 'the band span from the category count instead of the scale extent', mut: { bandFromCount: true }, named: ['G7'] },
  { id: 'onband-ignored', mutation: 'len = span + 1 even without boundaryGap', mut: { onBandIgnored: true }, named: ['G12'] },
  { id: 'len0-kept', mutation: 'len 0 not replaced by 1', mut: { len0Kept: true }, named: ['G13'] },
  { id: 'non-category-zero', mutation: 'a non-category axis gives band 0 instead of NaN', mut: { nonCategoryZero: true }, named: ['G14', 'G15'] },
  { id: 'not-centred', mutation: 'the cell starts at the point instead of centring on it', mut: { notCentred: true }, named: ['G1', 'G4'] },
  { id: 'extent-open', mutation: 'rows outside the scale extent drawn', mut: { extentOpen: true }, named: ['G5', 'G8'] },
  { id: 'extent-strict', mutation: 'the scale extent tested open (edges skipped)', mut: { extentStrict: true }, named: ['G1', 'G8'] },
  { id: 'nan-value-drawn', mutation: 'a NaN value not skipped', mut: { nanValueDrawn: true }, named: ['G6'] },
  { id: 'vm-ignored', mutation: 'the visualMap visuals not applied', mut: { vmIgnored: true }, named: ['G1', 'V1', 'V4'] },
  { id: 'vm-opacity-ignored', mutation: 'the visualMap opacity not applied', mut: { vmOpacityIgnored: true }, named: ['V2', 'V3'] },
  { id: 'item-under-vm', mutation: 'the visualMap applied AFTER the item itemStyle', mut: { itemUnderVm: true }, named: ['S1', 'L5'] },
  { id: 'series-color-over-vm', mutation: 'a series itemStyle.color wins over the visualMap', mut: { seriesColorOverVm: true }, named: ['S3'] },
  { id: 'default-text-parsed', mutation: 'the default text from the parsed value instead of the raw one', mut: { defaultTextParsed: true }, named: ['G6'] },
  { id: 'value-last-only', mutation: '{c} prints value[2] instead of the whole value array', mut: { valueLastOnly: true }, named: ['L2'] },
  { id: 'dim-template-ignored', mutation: '{@dim} / {@[n]} left unreplaced', mut: { dimTemplateIgnored: true }, named: ['L2'] },
  { id: 'tpl-replace-all', mutation: 'formatTpl replaces every occurrence', mut: { tplReplaceAll: true }, named: ['L2'] },
  { id: 'name-no-category', mutation: "no category name: an unnamed row's name is ''", mut: { nameNoCategory: true }, named: ['G5', 'L2', 'G18'] },
  { id: 'name-runtime-own-row', mutation: "the runtime name fallback reads the row's own value (no raw-index-through-the-filter read)", mut: { nameRuntimeOwnRow: true }, named: ['G7'] },
  { id: 'label-opacity-own', mutation: 'the label opacity not defaulting to the cell style opacity', mut: { labelOpacityOwn: true }, named: ['S1', 'S3', 'V3'] },
  { id: 'inherit-is-fill', mutation: "label 'inherit' colours resolve to the cell fill (as other series do)", mut: { inheritIsFill: true }, named: ['L4'] },
  { id: 'radius-series-only', mutation: 'borderRadius from the series only', mut: { radiusSeriesOnly: true }, named: ['S2'] },
  { id: 'radius-zero-array-plain', mutation: 'an all-zero radius array drawn as a plain rect', mut: { radiusZeroArrayPlain: true }, named: ['S2'] },
  { id: 'radius-unclamped', mutation: 'the corner radii not scaled down to fit', mut: { radiusUnclamped: true }, named: ['S2'] },
  { id: 'rect-no-stroke', mutation: 'the label rect not grown by the stroke', mut: { rectNoStroke: true }, named: ['S1', 'S3', 'L7'] },
  { id: 'no-fill-threshold', mutation: 'a fill-less stroked cell grows its rect by lineWidth, not max(lineWidth, 5)', mut: { noFillThreshold: true }, named: ['S1', 'L7'] },
  { id: 'position-default-top', mutation: "the default label position 'top'", mut: { positionDefaultTop: true }, named: ['L1', 'G-heatmap-cartesian'] },
  { id: 'outside-not-top', mutation: "position 'outside' not mapped to 'top'", mut: { outsideNotTop: true }, named: ['L3'] },
  { id: 'distance-ignored', mutation: 'label.distance ignored (always 5)', mut: { distanceIgnored: true }, named: ['L3'] },
  { id: 'inside-as-outside', mutation: 'inside positions use the outside ink', mut: { insideAsOutside: true }, named: ['L1', 'L5', 'G-heatmap-cartesian'] },
  { id: 'lum-ignores-alpha', mutation: "the inside band lum ignores the fill's alpha", mut: { lumIgnoresAlpha: true }, named: ['L5'] },
  { id: 'bands-inclusive', mutation: 'the lum bands compared with >= instead of >', mut: { bandsInclusive: true }, named: ['L5'] },
  { id: 'inside-stroke-never', mutation: 'no automatic inside stroke', mut: { insideStrokeNever: true }, named: ['L1', 'L6'] },
  { id: 'dark-ignored', mutation: 'the ground never dark (outside ink, inside stroke)', mut: { darkIgnored: true }, named: ['L6'] },
  { id: 'no-global-font', mutation: 'label font parts without the global textStyle fallback', mut: { noGlobalFont: true }, named: ['L1', 'G-heatmap-cartesian'] },
  { id: 'no-label-rotate', mutation: 'label.rotate ignored', mut: { noLabelRotate: true }, named: ['L4'] },
  { id: 'offset-keeps-origin', mutation: 'label.offset leaves the origin at 0', mut: { offsetKeepsOrigin: true }, named: ['L4'] },
  { id: 'user-align-ignored', mutation: 'author label align / verticalAlign ignored', mut: { userAlignIgnored: true }, named: ['L4'] },
  { id: 'align-no-normalize', mutation: "'middle' align not normalised", mut: { alignNoNormalize: true }, named: ['L4'] },
  { id: 'bg-auto-stroke', mutation: 'a label backgroundColor does not suppress the automatic stroke', mut: { bgAutoStroke: true }, named: ['L4'] },
  { id: 'z-default-0', mutation: 'the series z default 0 instead of 2', mut: { zDefault0: true }, named: ['G1', 'G-heatmap-cartesian'] },
  { id: 'silent-ignored', mutation: 'series.silent ignored', mut: { silentIgnored: true }, named: ['Z1'] },
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
const TRANSCRIBED_ROW_KEYS = ['name', 'visual', 'drawn', 'skip', 'rect', 'label'];
// the recorded series block vs a transcription result (rows in dataIndex order)
function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const hm = sr.heatmap;
  const a = {};
  const b = {};
  flat({ z: hm.z, zlevel: hm.zlevel, silent: hm.silent, seriesStyle: hm.seriesStyle, cell: hm.cell }, 'block', a);
  flat(t.block, 'block', b);
  for (const row of hm.rows) {
    if (row.dataIndex == null) continue;
    const pick = {};
    for (const k of TRANSCRIBED_ROW_KEYS) pick[k] = row[k];
    const tr = t.rows[row.dataIndex];
    const tpick = {};
    for (const k of TRANSCRIBED_ROW_KEYS) tpick[k] = tr[k];
    flat(pick, 'row' + row.index, a);
    flat(tpick, 'row' + row.index, b);
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
      update: 'setOption, then zr.storage.getDisplayList(true) (update / updateInnerText of every element), then chart.renderToSVGString() (the SVG painter maps the cell styles)',
      data: "series.getData(): count, getRawIndex, getRawDataItem, get('x' / 'y' / 'value', i), getName, getItemVisual(i, 'style'), getVisual('style'); coordinateSystem.dataToPoint([x, y]); axis.scale.getExtent(), axis.getExtent(), axis.onBand / inverse, scale.getOrdinalMeta().categories",
      cell: "data.getItemGraphicEl(i) = the Rect (undefined when skipped); el.path.data up to len(); el.path.getBoundingRect(); el.getBoundingRect(); el.getTextContent() = the label; the view group (getViewOfSeriesModel) holds exactly the drawn cells in data order",
      visualMap: 'each targeting visualMap (component order): vm.getDataDimensionIndex(data), store.get(dim, i), vm.getValueState(value), vm.targetVisuals[state] mappings applied in VisualMapping.prepareVisualTypes order (visualSolution.incrementalApplyVisual), recording what they write',
      svg: 'the SVG <path> with ecmeta_series_index / ecmeta_data_index: fill, fill-opacity, stroke, stroke-width, stroke-opacity, stroke-dasharray, stroke-dashoffset, stroke-linecap / -linejoin / -miterlimit (absent attributes recorded null); the first coordinate pair of d is checked against the path start',
      production: "a case whose development-build run throws is recorded from dist/echarts.min.js (productionBuild true, devError the message); every other case must record identically through both builds",
    },
    notes: [
      'Only cartesian2d heatmaps are covered (not calendar / matrix / geo). Emphasis / blur / select states, tooltip, hover layers and progressive (incremental) rendering are out of scope; the cell of a series with more than `progressiveThreshold` (3000) rows is rendered incrementally by upstream -- no case reaches it.',
      "The default label font family comes from globalDefault.ts: 'Microsoft YaHei' when navigator.platform starts with 'Win' (node >= 21 has a navigator: 'Win32' on this machine), else 'sans-serif'. The recorded fonts are this machine's; every case records ecModel.option.textStyle.",
      'A cell is a Rect centred on dataToPoint([x, y]) of size (bandWidth + 0.5) x (bandHeight + 0.5): the half pixel hides the seams. bandWidth = |px extent| / (scale extent span + 1) on a category axis with boundaryGap (onBand), / span without (0 -> 1); on any other axis upstream has no band (calcBandWidth without fromStat) and the size is NaN -- the development build throws instead.',
      "A row is skipped (no cell, no label) when its value, x or y is NaN, or x / y lies outside the axis SCALE extent (closed interval); dataZoom's 'filter' mode removes rows from the data before that (dataIndex null).",
      'The cell style is the visual style: the series itemStyle (fill = the palette colour when unset), then what the visualMaps write (colour, opacity), then the item itemStyle (it overrides the visualMap). No subPixelOptimize, no z2 (0): the label z2 is 2.',
      "Label: show only through the chain item.label -> series.label (hasItemOption; default off). Default text = String(rawValue[2]) -- the RAW option value, not the parsed number ('07' stays '07'); a string formatter replaces it ({c} = the whole value array as 'x,y,v', {@[n]} / {@dim} = the raw value of that dim). Position default 'inside'; the label opacity defaults to the cell style opacity; there is NO inheritColor: 'inherit' colours become null (the automatic ink).",
      'svg: what the SVG painter prints -- rgba colours split into rgb + fill-opacity / stroke-opacity (x style.opacity), stroke-width printed when not 1, stroke-dashoffset rounded.',
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
    for (const sr of c.series) {
      if (!sr.heatmap) continue;
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
      for (const row of sr.heatmap.rows) {
        if (row.dataIndex == null) continue;
        // the visualMap colour is the cell colour wherever the item has no colour of its own
        const raw = row.raw;
        const itemColour = raw && !Array.isArray(raw) && typeof raw === 'object' && raw.itemStyle && raw.itemStyle.color != null;
        if (row.vm && row.vm.colorWritten && !itemColour) must(JSON.stringify(row.visual.fill) === JSON.stringify(row.vm.color), key + ': row ' + row.index + ' is not the visualMap colour');
        if (row.drawn && (scanNaN(row.rect) || scanNaN(row.label))) anyNaN = true;
      }
    }
    must(anyNaN === c.nan, c.id + ': ' + (anyNaN ? 'NaN although the case is not marked nan' : 'expected NaN'));
  }
  // anchors
  const hmOf = (id, si) => byId[id].series.find(s => s.seriesIndex === si).heatmap;
  const row = (id, si, i) => hmOf(id, si).rows[i];
  const n = h => num(h);
  const g1 = hmOf('G1', 0);
  must(g1.cell.widthText === '220.25' && n(g1.cell.width) === 659.25 / 3 + 0.5 && g1.z === 2 && g1.rows[0].label === null, 'G1: cell = band + 0.5, z 2, no label');
  must(n(g1.rows[0].rect.shape.x) === n(g1.rows[0].point[0]) - n(g1.cell.width) / 2 && g1.rows[0].rect.path.map(c => c.cmd).join('') === 'R', 'G1: centred R');
  must(g1.rows[3].vm.vms[0].state === 'inRange' && g1.rows[3].visual.fill === 'rgba(80,112,221,1)', 'G1: 12 beyond max is inRange at the end colour');
  must(row('G5', 0, 2).drawn && row('G5', 0, 2).name === '' && row('G5', 0, 3).skip === 'x<' && row('G5', 0, 4).skip === 'x>' && row('G5', 0, 5).skip === 'x'
    && row('G5', 0, 11).skip === 'x>' && row('G5', 0, 12).skip === 'x<' && row('G5', 0, 7).skip === 'y', 'G5: skip reasons');
  must(row('G5', 0, 2).pointText[0] === row('L2', 0, 3).pointText[0], 'G5: 2.5 is drawn on the x3 band (Math.round)');
  must(row('G6', 0, 1).skip === 'value' && row('G6', 0, 5).label.text === '07' && row('G6', 0, 6).label.text === '1e1' && row('G6', 0, 10).drawn, 'G6: raw default text');
  must(row('G7', 0, 0).dataIndex === null && row('G7', 0, 1).label.text === 'x3' && row('G7', 0, 1).rect.shape.x === row('G7', 0, 29).rect.shape.x && row('G7', 0, 29).name === 'x5', 'G7: the name read through the filter, the 4.5 cell on x5');
  must(byId.G12.productionBuild && /boundaryGap/.test(byId.G12.devError) && hmOf('G12', 0).cell.widthText === '220.25', 'G12: production, band / span');
  must(hmOf('G13', 0).cell.widthText === '659.75', 'G13: len 0 -> 1');
  must(hmOf('G14', 0).cell.widthText === 'NaN' && hmOf('G14', 0).cell.heightText === '239.925', 'G14: NaN width');
  must(hmOf('G16', 0).rows[0].visual.fill === '#5070dd' && hmOf('G16', 1).rows[0].visual.fill === '#b6d634' && hmOf('G16', 0).rows[0].vm === null, 'G16: palette');
  must(row('G18', 0, 5).name === 'x2' && row('G18', 0, 4).name === '7' && row('G18', 0, 3).label.text === 'x0|0,1,4' && row('G18', 0, 1).label === null, 'G18: names, chain');
  must(row('S1', 0, 0).visual.fill === '#c00' && row('S1', 0, 7).label.inside === false && n(row('S1', 0, 7).rect.rect.y) === n(row('S1', 0, 7).rect.bbox.y) - 2.5, 'S1: item colour, none');
  must(row('S2', 0, 2).rect.path.map(c => c.cmd).join('') === 'MLLLLZ' && row('S2', 0, 7).rect.path.map(c => c.cmd).join('') === 'R', 'S2: radius paths');
  must(row('S4', 0, 1).vm.vms[0].skipped && row('S4', 0, 1).visual.fill === '#5070dd', 'S4: visualMap false');
  must(row('V3', 0, 0).vm.vms[0].state === 'outOfRange' && row('V3', 0, 0).label.style.opacityText === '0.2', 'V3: outOfRange opacity reaches the label');
  must(row('V5', 0, 2).label.style.opacityText === '0', 'V5: a deselected piece hides its label');
  must(row('L4', 0, 1).label.style.fill === null && row('L4', 0, 1).label.ink.fill === '#333', 'L4: inherit -> null');
  must(row('L5', 0, 2).label.inkDefault.fill === '#eee' && row('L5', 0, 5).label.inkDefault.fill === '#ccc', 'L5: exact band edges');
  must(hmOf('Z1', 0).silent && row('Z1', 0, 0).rect.silent && row('Z1', 0, 0).rect.z === 5 && row('Z1', 0, 0).label.z2 === 2, 'Z1: silent, z');
  must(byId.Z2.series[0].filtered && byId.Z2.series[0].heatmap === null, 'Z2: hidden series');
  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        if (!sr.heatmap) continue;
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
  console.warn = quiet.warn;
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
const nRows = out.cases.reduce((a, c) => a + c.series.reduce((b, s) => b + (s.heatmap ? s.heatmap.rows.length : 0), 0), 0);
const nCells = out.cases.reduce((a, c) => a + c.series.reduce((b, s) => b + (s.heatmap ? s.heatmap.rows.filter(r => r.drawn).length : 0), 0), 0);
const prod = out.cases.filter(c => c.productionBuild).map(c => c.id);
if (prod.length) console.log('through the production build:', prod.join(', '));
console.log(out.cases.length + ' cases (' + nRows + ' rows, ' + nCells + ' cells); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages from upstream');
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
