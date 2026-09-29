/*
Upstream's own answers for series MARKERS, batch M4: the PICTURE of a markArea
-- each area's polygon and its label -- exactly as MarkAreaView.renderSeries,
model/mixin/itemStyle.ts, label/labelStyle.ts, model/mixin/dataFormat.ts,
MarkerModel.getDataParams, util/graphic.ts traverseUpdateZ and zrender
(tool/color.ts parse / modifyAlpha / lum, graphic/shape/Polygon.ts +
graphic/helper/poly.ts, graphic/Path.ts useStyle / getBoundingRect /
getInsideTextFill / getInsideTextStroke, core/PathProxy.ts getBoundingRect +
core/bbox.ts fromLine, Element.ts updateInnerText, contain/text.ts
calculateTextPosition, graphic/Text.ts, canvas/dashStyle.ts,
svg/mapStyleToAttrs.ts + svg/helper.ts normalizeColor) build them. M1
(markers-layout.js) pinned the model, the data transform, the corner points and
allClipped; this oracle takes the points as given and pins what is drawn on
them. M2 (markers-line.js) and M3 (markers-point.js) are the siblings.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
for every chart case, with Math.random replaced by the port's xorshift32 (seed
2463534242, reset before each chart). After setOption it runs
zr.storage.getDisplayList(true) (every element's update: updateInnerText places
the labels) and chart.renderToSVGString() (the SVG painter maps every polygon's
style to attributes), then reads the live elements: per series the slave
markArea model's areaData (MarkerModel.getMarkerModelFromSeries, as M1), per
area areaData.getItemGraphicEl(i) = the Polygon (null when allClipped) and
polygon.getTextContent() (the label). Every chart is disposed in a finally.

Which ORIGINAL data element an area came from: as M1, every case runs twice --
verbatim (every recorded value comes from this run) and once more with both
ends of every data pair tagged '__oracleIndex'; the tagged run must give
exactly the same pictures, and its tags give `index` / `survived`.

  node tools/advchart-oracle/markers-area.js

writes tests/fixtures/advchart-markers-area.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Conventions (as markers-point.js)
  hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
           lowercase (NaN 7ff8000000000000, +Infinity 7ff0000000000000,
           -Infinity fff0000000000000). Every hex field k has a readable twin
           kText (String(v), '-0' for negative zero).
  val      a raw JS value of the option world, tagged by kind: null (undefined
           or null) | {"n": hex, "t": text} a number | {"s": string} | {"j":
           json} anything else
  json     an option value exactly as upstream holds it (JSON; undefined ->
           null)
  rect     {x, y, width, height} hex, with rectText {x, y, width, height}
  pt       [hex x, hex y], with a Text twin
  path     [{cmd, args [hex], argsText}] -- a PathProxy's data up to len():
           'M' (x, y), 'L' (x, y), 'Z' (none) (a polygon draws nothing else)
  paint    a style colour exactly as upstream holds it: a css string, a
           gradient object (json), or null (undefined / null)

Top level
  source, W, H, seed, api, notes[], cases[], guards[]
  cases[]  one per chart:
    id, note, width, height, gallery (file name or null), option (as fed;
    null for a gallery case: load examples/advchart/gallery/<gallery>.json and
    feed it verbatim), nan (true: an area of this case holds NaN corner points
    -- its polygon, rect and label are NaN, documented in the note)
    ground   {background: zr.getBackgroundColor() (the option's
             backgroundColor or 'transparent'), isDark: zr.isDarkMode()
             (option darkMode when a boolean, else lum(background) < 0.4)}
    textStyle  json: ecModel.option.textStyle -- the global text style every
             label font part falls back to (defaults fontSize 12, fontStyle /
             fontWeight 'normal', fontFamily 'Microsoft YaHei' when
             navigator.platform starts with 'Win' -- this machine -- else
             'sans-serif'; globalDefault.ts:20-27, 86-94)
    series[] every series whose OWN option has markArea.data, series order:
      seriesIndex, name (option name or null), type, filtered (legend-
      unselected: nothing drawn, `markArea` null), color (paint: the series
      colour getVisualFromData(seriesData, 'color') -- what the fill / stroke
      fall back to), seriesName (the host series' name as {a} prints it; null
      when the option has no name -- upstream's generated name holds a NUL),
      markArea: null (filtered) or
        z, zlevel (json: retrieveZInfo, model.get('z') || 0 through series
        markArea -> top-level markArea -> default 1), silent (the polygon
        group's silent: markArea.silent || series.silent -- every polygon
        inherits it for hit testing), count (areaData.count()),
        extent {x, y}: [hex, hex] + extentText -- the x / y SCALE extents
        (scale.getExtent(): the dataZoom window) allClipped tests against
        items[]  one per ORIGINAL element of series.markArea.data, in order:
          index, survived (kept by the transform + filter), dataIndex (its
          index in areaData, or null); when it survived also:
          name, value   val: the merged item's name / value (mergeAll([{}, lt,
                        rb]): lt's keys win; what the default text and {b} /
                        {c} read)
          points, pointsText  [pt x 4]: the layout corners (M1-proven)
                        [x0,y0], [x1,y0], [x1,y1], [x0,y1]
          parsed, parsedText  [hex x 4]: scale.parse of the stored x0, y0, x1,
                        y1 (+-Infinity for an open side)
          allClipped    bool: the area does not overlap the scale extents on
                        some dim (after sorting each pair): no polygon, no
                        label
          visual        {fill, stroke (paint), z2 (json)}: the item visuals
                        renderSeries stores -- itemStyle.color, else the series
                        colour through modifyAlpha(c, 0.4) when a string;
                        itemStyle.borderColor, else the series colour;
                        retrieve2(z2, 0) through the item chain
          polygon       null (allClipped) or the Polygon:
            shape {points (pt x 4 + pointsText), smooth (json)},
            path (the proxy after buildPath: M L L L Z),
            bbox + bboxText (rect: PathProxy.getBoundingRect of that path),
            rect + rectText (rect: Path.getBoundingRect(): bbox grown by the
              stroke -- lineWidth, or max(lineWidth, 5) without a fill --
              half each side, when a stroke is set and lineWidth > 0; the
              polygon has no transform, so this is the label's rect),
            style {fill, stroke (paint), lineWidth, opacity, lineDashOffset,
              miterLimit, shadowBlur, shadowOffsetX, shadowOffsetY,
              fillOpacity, strokeOpacity (hex + Text), lineDash (json:
              borderType as held), lineCap, lineJoin, shadowColor (json),
              strokeNoScale (bool)} after useStyle (unset keys read zrender's
              DEFAULT_PATH_STYLE: fill '#000', lineWidth 1, lineCap 'butt',
              miterLimit 10, opacity 1, shadowColor '#000' ... -- but a key
              the item style holds as undefined stays undefined),
            svg (the SVG painter's attributes for the <polygon>, read back):
              {fill (string; a gradient's 'url(#..)' as 'url'), fillOpacity
              (hex or null = absent = 1), stroke (string or null = absent),
              strokeWidth (hex or null = absent = 1), strokeOpacity (hex or
              null), dash ([hex] + dashText or null: stroke-dasharray, the
              resolved dash), dashOffset (hex or null), lineCap, lineJoin,
              miterLimit (string or null)},
            z, z2 (json), zlevel, silent (el.isSilent(): its own or the
            group's)
          label         null (allClipped, or not shown), else:
            text          style.text: the formatted string or the default
                          (the merged item's name, '' when none)
            lines         the number of TSpans (0 for '')
            position      json: textConfig.position (label.position || 'inside'
                          through the chain; default 'top'; 'outside' -> 'top')
            distance      hex + Text: textConfig.distance (default 5)
            rect, rectText  the rect the label is placed against (= polygon
                          rect)
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
                          containing 'inside' AND the polygon has a fill)
            font          style.font (makeFont), fontSize, fontWeight,
                          fontStyle, fontFamily (json: the style's parts)
            style         {fill, stroke (colour or null: not in the style),
                          lineWidth (hex or null), opacity (hex; 1 when unset --
                          markArea passes NO defaultOpacity), backgroundColor
                          (json or null)}
            inkDefault    {fill, stroke, autoStroke, align, verticalAlign} =
                          the text's _defaultStyle set by updateInnerText
                          (inside: getInsideTextFill / getInsideTextStroke of
                          the polygon fill, alpha included; outside: '#333' /
                          '#ccc' and the ground halo)
            ink           null when no TSpan, else the TSpans (all the same):
                          {fill, stroke (null = none), lineWidth (hex or null),
                          opacity (hex)}
            z, z2, zlevel, silent
guards[]  one per mutation of the transcription: id, mutation, named (the
          cases that must turn red), changed (the cases whose recorded values
          the mutated transcription does not reproduce), ok = named is a
          subset of changed, differs (the first differing fields of each
          named case)

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, bit for bit) takes as
INPUTS: the option as fed (the series' markArea option, the top-level markArea
option merged over MarkAreaModel.defaultOption), the M1-proven areaData raw
(merged) items, corner points and scale-parsed corner values, the scale
extents, the series colour, the host series name, ecModel.option.textStyle,
and the ground (background, isDark). It reproduces: MarkAreaView.renderSeries
(allClipped with numberUtil.asc, getItemStyle over ITEM_STYLE_KEY_MAP, the
fill / stroke fallbacks with zrender modifyAlpha, z2, the polygon only when not
allClipped, useStyle over DEFAULT_PATH_STYLE, setLabelStyle with defaultText
getName || '' and inheritColor modifyAlpha(fill, 1) / neutral99, group silent),
zrender poly buildPath, PathProxy.getBoundingRect (fromLine), Path
getBoundingRect (stroke growth), dataFormat getFormattedLabel + MarkerModel
getDataParams + formatTpl, labelStyle createTextStyle / createTextConfig,
contain/text calculateTextPosition, Element.updateInnerText (inside / outside
ink, textConfig rotation / offset), Path.getInsideTextFill /
getInsideTextStroke (lum with alpha), Element.getOutsideFill /
getOutsideStroke, Text normalizeStyle / makeFont / parseFontSize and the TSpan
ink rules, svg mapStyleToAttrs + normalizeColor + canvas/dashStyle getLineDash,
and util/graphic traverseUpdateZ (z, zlevel, label z2 = running max z2 + 2 over
the series' drawn polygons).

Self-checks (any failure: nothing is written, exit 1): the transcription
reproduces every recorded series (every field, bit for bit); the tagged run
gives the same pictures as the verbatim run and its tags increase; the merged
item's name / label / itemStyle / z2 equal zrender merge({}, lt) then merge
with rb (no overwrite) of the option pair; a polygon exists exactly when the
layout is not allClipped, its shape points are the layout points, it has no
transform and neither have its ancestors, and the markArea group holds exactly
the drawn polygons in data order; the recorded label placement equals
calculateTextPosition (+ offset) on the recorded rect; every drawn polygon is
matched by at least one SVG <polygon> with its series and data index whose
points (printed rounded) are within 0.05 of the layout, and all matches agree;
NaN appears exactly in the cases marked nan; anchors; every guard is ok; two
generations in the process give identical bytes.
*/
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-markers-area.json');
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

// MarkAreaModel.defaultOption (MarkAreaModel.ts:82-108)
const MA_DEFAULTS = {
  z: 1, tooltip: { trigger: 'item' }, animation: false,
  label: { show: true, position: 'top' }, itemStyle: { borderWidth: 0 },
  emphasis: { label: { show: true, position: 'top' } },
};
const NEUTRAL99 = '#000'; // tokens.color.neutral99 (visual/tokens.ts:144)
const MAXV = Number.MAX_VALUE;

// Model getShallow / get over [own, parent, grandparent ...]
function chainGet(levels, key, skipEmpty) {
  let v;
  for (let i = 0; i < levels.length; i++) {
    const o = levels[i];
    v = o && typeof o === 'object' ? o[key] : undefined;
    if (skipEmpty && v === '') continue;
    if (v != null) return v;
  }
  return v;
}
const sub = (levels, key) => levels.map(o => (o && typeof o === 'object' ? o[key] : undefined));

// zrender contain/text.ts parsePercent
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}

// zrender tool/color.ts clampCssFloat / modifyAlpha / stringify (the css parser `parse` is upstream's primitive)
const clampCssFloat = f => (f < 0 ? 0 : f > 1 ? 1 : f);
function modifyAlpha(c, alpha, mut) {
  const arr = echarts.color.parse(c);
  if (arr && alpha != null) {
    arr[3] = mut.alphaMultiplied ? clampCssFloat(arr[3] * alpha) : clampCssFloat(alpha);
    return 'rgba(' + arr[0] + ',' + arr[1] + ',' + arr[2] + ',' + arr[3] + ')';
  }
  return mut.unparsableKept ? c : undefined;
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

// canvas/dashStyle.ts normalizeLineDash (+ getLineDash: no strokeNoScale -> no lineScale division)
function normalizeLineDash(lineType, lineWidth, mut) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? (mut.dashed55 ? [5 * lineWidth, 5 * lineWidth] : [4 * lineWidth, 2 * lineWidth])
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? (mut.dashScaled ? [lineType * lineWidth] : [lineType])
        : isArray(lineType) ? (mut.dashScaled ? lineType.map(v => v * lineWidth) : lineType) : null;
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
function svgAttrs(st, mut) {
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
      const d = st.lineWidth > 0 && normalizeLineDash(st.lineDash, st.lineWidth, mut);
      if (d) {
        r.dash = d;
        const off = Math.round(st.lineDashOffset || 0);
        if (off) r.dashOffset = off;
      }
    }
    for (const [k, a] of [['lineCap', 'lineCap'], ['miterLimit', 'miterLimit'], ['lineJoin', 'lineJoin']]) {
      if (st[k] !== DEFAULT_PATH_STYLE[k]) {
        const v = st[k] || DEFAULT_PATH_STYLE[k];
        if (v) r[a] = String(v);
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

// ---- PathProxy.getBoundingRect over M / L / Z (core/PathProxy.ts:490-597, core/bbox.ts fromLine) ----
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
    if (i === 1) {
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
        min2[0] = Math.min(xi, data[i]);
        min2[1] = Math.min(yi, data[i + 1]);
        max2[0] = Math.max(xi, data[i]);
        max2[1] = Math.max(yi, data[i + 1]);
        xi = data[i++];
        yi = data[i++];
        break;
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

// zrender Transformable needLocalTransform + getLocalTransform (the inner text transformable: no scale, origin)
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
const ITEM_STYLE_KEYS = [['fill', 'color'], ['stroke', 'borderColor'], ['lineWidth', 'borderWidth'], ['opacity', 'opacity'],
  ['shadowBlur', 'shadowBlur'], ['shadowOffsetX', 'shadowOffsetX'], ['shadowOffsetY', 'shadowOffsetY'], ['shadowColor', 'shadowColor'],
  ['lineDash', 'borderType'], ['lineDashOffset', 'borderDashOffset'], ['lineCap', 'borderCap'], ['lineJoin', 'borderJoin'], ['miterLimit', 'borderMiterLimit']];
const TEXT_PROPS_BOX = ['padding', 'borderWidth', 'borderRadius', 'borderDashOffset', 'backgroundColor', 'borderColor', 'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY'];
const STYLE_NUM_KEYS = ['lineWidth', 'opacity', 'lineDashOffset', 'miterLimit', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY', 'fillOpacity', 'strokeOpacity'];
function styleRec(s) {
  const r = { fill: paint(s.fill), stroke: paint(s.stroke) };
  for (const k of STYLE_NUM_KEYS) {
    r[k] = hexOrNull(s[k]);
    r[k + 'Text'] = textOrNull(s[k]);
  }
  Object.assign(r, { lineDash: json(s.lineDash), lineCap: json(s.lineCap), lineJoin: json(s.lineJoin), shadowColor: json(s.shadowColor), strokeNoScale: !!s.strokeNoScale });
  return r;
}

// one series' markArea picture. inp: {own, master, seriesOpt, color, seriesName, textStyle, ground, extent {x, y},
// items: [{raw, points, parsed}]} -> {z, zlevel, silent, count, extent, areas[]}
function transcribe(inp, mut) {
  const own = inp.own;
  const master = inp.master;
  const MA = mut.noSeriesLevel ? [master] : [own, master];
  const z = mut.zDefault ? 1 : chainGet(MA, 'z') || 0;
  const zlevel = chainGet(MA, 'zlevel') || 0;
  const gts = inp.textStyle || {};
  const groupSilent = !!(chainGet(MA, 'silent') || (!mut.silentMarkerOnly && inp.seriesOpt && inp.seriesOpt.silent));
  const xe = inp.extent.x;
  const ye = inp.extent.y;
  let maxZ2 = -Infinity; // util/graphic.ts doUpdateZ, carried across the polygons of the series' group
  const areas = inp.items.map(IT => {
    const raw = IT.raw;
    const pv = IT.parsed;
    const out = { name: val(raw.name), value: val(raw.value), points: IT.points.map(pt), pointsText: IT.points.map(ptText),
      parsed: pv.map(hex), parsedText: pv.map(text) };
    // ----- allClipped (MarkAreaView.ts:285-303) -----
    const xp = [pv[0], pv[2]];
    const yp = [pv[1], pv[3]];
    if (!mut.noAsc) {
      xp.sort((a, b) => a - b);
      yp.sort((a, b) => a - b);
    }
    const overlapped = !(xe[0] > xp[1] || xe[1] < xp[0] || ye[0] > yp[1] || ye[1] < yp[0]);
    const allClipped = mut.noAllClipped ? false : !overlapped;
    out.allClipped = allClipped;
    // ----- visuals (MarkAreaView.ts:305-320) -----
    const lv = [raw].concat(MA);
    const IS = sub(lv, 'itemStyle');
    const style = {};
    for (const [k, o] of ITEM_STYLE_KEYS) {
      const x = chainGet(IS, o);
      if (x != null) style[k] = x;
    }
    const color = inp.color;
    const noFill = mut.fillNullCheck ? style.fill == null : mut.transparentFalsy ? (!style.fill || style.fill === 'transparent') : !style.fill;
    if (noFill) {
      style.fill = color;
      if (typeof style.fill === 'string' && !mut.fillNoAlpha) style.fill = modifyAlpha(style.fill, 0.4, mut);
    }
    if (!style.stroke && !mut.strokeNoFallback) style.stroke = mut.strokeFromFill ? style.fill : color;
    const z2 = retrieve2(chainGet(lv, 'z2'), 0);
    out.visual = { fill: paint(style.fill), stroke: paint(style.stroke), z2: json(z2) };
    if (allClipped) {
      out.polygon = out.label = null;
      return out;
    }
    // ----- the Polygon (MarkAreaView.ts:324-375, zr graphic/helper/poly.ts) -----
    const P = IT.points;
    const pdata = [CMD.M, P[0][0], P[0][1]];
    for (let i = 1; i < P.length; i++) pdata.push(CMD.L, P[i][0], P[i][1]);
    if (!mut.noClosePath) pdata.push(CMD.Z);
    // useStyle: a new object over DEFAULT_PATH_STYLE with the item style's OWN keys (an own undefined stays undefined)
    const st = Object.assign(Object.create(DEFAULT_PATH_STYLE), style);
    const bbox = pathBBox(pdata);
    const hasStroke = !(st.stroke == null || st.stroke === 'none' || !(st.lineWidth > 0));
    const hasFill = st.fill != null && st.fill !== 'none';
    // Path.getBoundingRect (Path.ts:339-392): the stroke grows the rect (no strokeNoScale: lineScale 1)
    let rect = bbox;
    if (hasStroke && pdata.length > 0 && !mut.rectNoStroke) {
      rect = Object.assign({}, bbox);
      let w = st.lineWidth;
      if (!hasFill && !mut.noFillThreshold) w = Math.max(w, mut.threshold4 ? 4 : 5);
      if (mut.rectStrokeHalved) w /= 2;
      rect.width += w;
      rect.height += w;
      rect.x -= w / 2;
      rect.y -= w / 2;
    }
    maxZ2 = Math.max(z2 || 0, maxZ2);
    if (mut.z2PerArea) maxZ2 = z2 || 0;
    out.polygon = Object.assign({ shape: { points: P.map(pt), pointsText: P.map(ptText), smooth: 0 }, path: decode(pdata) },
      rectRec(bbox, 'bbox'), rectRec(rect, 'rect'),
      { style: styleRec(st), svg: svgRec(svgAttrs(st, mut)), z, z2: json(z2), zlevel, silent: groupSilent });
    // ----- the label (MarkAreaView.ts:377-386, labelStyle.ts, zr Element.updateInnerText, Text) -----
    const LB = sub(lv, 'label');
    const show = chainGet(LB, 'show');
    if (!show) {
      out.label = null;
      return out;
    }
    const inheritColor = mut.inheritRaw ? style.fill : mut.inheritNeutral ? NEUTRAL99
      : typeof style.fill === 'string' ? modifyAlpha(style.fill, 1, mut) : NEUTRAL99;
    // text: getFormattedLabel (the label formatter through the chain), else the default text
    let formatter = chainGet(LB, 'formatter');
    let str;
    if (mut.formatterEmptyFallsBack && formatter === '') formatter = undefined;
    if (typeof formatter === 'string') {
      str = formatTpl(formatter, { seriesName: inp.seriesName, name: itemName(raw), value: raw.value }, mut);
    } else {
      must(formatter == null, 'the transcription does not call formatter functions');
      str = mut.defaultTextNull ? (itemName(raw) || null) : itemName(raw) || '';
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
    if (opacity == null && mut.labelOpacityFromItem) opacity = style.opacity; // markArea passes no defaultOpacity
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
    for (const o of LB) must(!(o && typeof o === 'object' && o.rich), 'the transcription does not do rich labels');
    if (mut.userAlignIgnored) rawAlign = rawVAlign = null;
    const authorAlign = normAlign(rawAlign, mut);
    const authorVAlign = normVAlign(rawVAlign, mut);
    // createTextConfig (labelStyle.ts:340-383)
    let position = chainGet(LB, 'position', mut.positionEmptyTop) || 'inside';
    if (position === 'outside' && !mut.outsideNotTop) position = 'top';
    if (mut.unknownInside && typeof position === 'string' && !(position in POSITIONS)) position = 'inside';
    const distance = mut.distanceIgnored ? 5 : retrieve2(chainGet(LB, 'distance'), 5);
    const labelOffset = chainGet(LB, 'offset');
    let labelRotate = chainGet(LB, 'rotate');
    if (labelRotate != null) labelRotate *= Math.PI / 180;
    const outsideFill = chainGet(LB, 'color') === 'inherit' ? (inheritColor || null) : 'auto';
    // updateInnerText: the rect = the polygon's bounding rect (no transform anywhere)
    const calc = calculateTextPosition(position, distance, rect);
    if (mut.arrayAlignLeft && calc.align == null) { calc.align = 'left'; calc.verticalAlign = 'top'; }
    const inner = { x: calc.x, y: calc.y, rotation: 0, originX: 0, originY: 0, scaleX: 1, scaleY: 1 };
    if (labelRotate != null && !mut.noLabelRotate) inner.rotation = labelRotate;
    if (labelOffset) {
      inner.x += labelOffset[0];
      inner.y += labelOffset[1];
      if (!mut.offsetKeepsOrigin) { inner.originX = -labelOffset[0]; inner.originY = -labelOffset[1]; }
    }
    // the ink (Element.ts:697-735): inside needs canBeInsideText = hasFill
    const isInside = !mut.insideAsOutside && typeof position === 'string' && position.indexOf('inside') >= 0 && !!(hasFill || mut.noFillInside);
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
  return { z: json(z), zlevel: json(zlevel), silent: groupSilent, count: inp.items.length,
    extent: { x: xe.map(hex), y: ye.map(hex) }, extentText: { x: xe.map(text), y: ye.map(text) }, areas };
}

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const firstOf = v => (isArray(v) ? v[0] : v);
function slaveOf(ec, sm) {
  const master = ec.getComponent('markArea');
  if (!master) return null;
  const MM = Object.getPrototypeOf(master.constructor);
  must(typeof MM.getMarkerModelFromSeries === 'function', 'MarkerModel.getMarkerModelFromSeries not reachable');
  return MM.getMarkerModelFromSeries(sm, 'markArea') || null;
}
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  must(Array.isArray(el.path.data), 'a path proxy was made static');
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};

// the <polygon> elements of the SVG: [{si, di, points, attrs}]
function svgPolygons(svg) {
  const out = [];
  const re = /<polygon\b([^>]*)>/g;
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
    out.push({ si: +si, di: +di, points: g('points').split(' ').map(Number),
      attrs: { fill: fill != null && /^url\(/.test(fill) ? 'url' : fill, fillOpacity: numOrNull(g('fill-opacity')),
        stroke: stroke != null && /^url\(/.test(stroke) ? 'url' : stroke, strokeWidth: numOrNull(g('stroke-width')), strokeOpacity: numOrNull(g('stroke-opacity')),
        dash: dash == null ? null : dash.split(',').map(Number), dashOffset: numOrNull(g('stroke-dashoffset')),
        lineCap: g('stroke-linecap'), lineJoin: g('stroke-linejoin'), miterLimit: g('stroke-miterlimit') } });
  }
  return out;
}

function readPolygon(el, layoutPoints, svgPolys, si, di) {
  must(el.type === 'polygon' && !el.transform && !el.needLocalTransform(), 'area ' + di + ' is not an untransformed Polygon');
  const sh = el.shape;
  must(sh.points.length === 4 && sh.points.every((p, k) => Object.is(p[0], layoutPoints[k][0]) && Object.is(p[1], layoutPoints[k][1])), 'the polygon points are not the layout points at area ' + di);
  const cands = svgPolys.filter(p => p.si === si && p.di === di);
  must(cands.length >= 1, 'no SVG <polygon> for area ' + di + ' of series ' + si);
  must(cands.every(c => JSON.stringify(c.attrs) === JSON.stringify(cands[0].attrs)), 'ambiguous SVG <polygon> for area ' + di);
  const near = (a, b) => (Number.isNaN(a) && Number.isNaN(b)) || Math.abs(a - b) <= 0.05 + 1e-9;
  must(cands[0].points.length === 8 && sh.points.every((p, k) => near(cands[0].points[2 * k], p[0]) && near(cands[0].points[2 * k + 1], p[1])), 'SVG polygon points differ at area ' + di);
  const rect = el.getBoundingRect();
  const bb = el.path.getBoundingRect();
  return Object.assign({ shape: { points: sh.points.map(pt), pointsText: sh.points.map(ptText), smooth: json(sh.smooth) }, path: decode(pathOf(el)) },
    rectRec(bb, 'bbox'), rectRec(rect, 'rect'),
    { style: styleRec(el.style), svg: svgRec(cands[0].attrs), z: el.z, z2: json(el.z2), zlevel: el.zlevel, silent: !!el.isSilent() });
}
function readLabel(el) {
  const t = el.getTextContent();
  if (!t || t.ignore) return null;
  const s = t.style;
  must(!s.rich, 'a rich markArea label');
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

// every area of one series: {block, rows, tags, inputs}
function readSeries(chart, sm, svgPolys) {
  const ec = chart.getModel();
  const slave = slaveOf(ec, sm);
  must(slave, 'no slave markArea model for series ' + sm.seriesIndex);
  const data = slave.getData();
  const view = chart.getViewOfComponentModel(ec.getComponent('markArea'));
  const draw = view.markerGroupMap.get(sm.id);
  must(draw && draw.group, 'no markArea group for series ' + sm.seriesIndex);
  const group = draw.group;
  for (let p = group; p; p = p.parent) must(!p.transform || p.transform.join() === '1,0,0,1,0,0', 'a transformed ancestor');
  const cs = sm.coordinateSystem;
  must(cs && cs.type === 'cartesian2d', 'not cartesian2d');
  const xs = cs.getAxis('x').scale;
  const ys = cs.getAxis('y').scale;
  const extent = { x: xs.getExtent().slice(), y: ys.getExtent().slice() };
  const rows = [];
  const tags = [];
  const inputs = [];
  const drawn = [];
  for (let i = 0; i < data.count(); i++) {
    const raw = data.getRawDataItem(i);
    tags.push(raw[TAG]);
    const lay = data.getItemLayout(i);
    const points = lay.points.map(p => p.slice());
    const parsed = [xs.parse(data.get('x0', i)), ys.parse(data.get('y0', i)), xs.parse(data.get('x1', i)), ys.parse(data.get('y1', i))];
    inputs.push({ raw: zrClone(raw), points, parsed });
    const vs = data.getItemVisual(i, 'style');
    const row = { name: val(raw.name), value: val(raw.value), points: points.map(pt), pointsText: points.map(ptText),
      parsed: parsed.map(hex), parsedText: parsed.map(text), allClipped: !!lay.allClipped,
      visual: { fill: paint(vs.fill), stroke: paint(vs.stroke), z2: json(data.getItemVisual(i, 'z2')) } };
    const el = data.getItemGraphicEl(i);
    must(!!el === !lay.allClipped, 'polygon presence vs allClipped at area ' + i);
    if (!el) {
      row.polygon = row.label = null;
      rows.push(row);
      continue;
    }
    drawn.push(el);
    must(el.z2 === data.getItemVisual(i, 'z2'), 'the polygon z2 is not the visual z2');
    row.polygon = readPolygon(el, lay.points, svgPolys, sm.seriesIndex, i);
    row.label = readLabel(el);
    if (row.label) {
      const t = el.getTextContent();
      const tc = el.textConfig;
      const r = el.getBoundingRect().clone();
      const c = calculateTextPosition(tc.position, tc.distance, r);
      const off = tc.offset || [0, 0];
      must(Object.is(t.innerTransformable.x, c.x + off[0]) && Object.is(t.innerTransformable.y, c.y + off[1]), 'the label placement is not calculateTextPosition on the rect at area ' + i);
    }
    rows.push(row);
  }
  must(group.childrenRef().length === drawn.length && group.childrenRef().every((c, k) => c === drawn[k]), 'the markArea group children are not the drawn polygons in order');
  const block = { z: json(slave.get('z') || 0), zlevel: json(slave.get('zlevel') || 0), silent: !!group.silent, count: data.count(),
    extent: { x: extent.x.map(hex), y: extent.y.map(hex) }, extentText: { x: extent.x.map(text), y: extent.y.map(text) } };
  return { block, rows, tags, inputs, extent };
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
    const d = s && s.markArea && s.markArea.data;
    if (!isArray(d)) continue;
    d.forEach((el, i) => { if (isArray(el)) el.forEach(e => { if (isObject(e)) e[TAG] = i; }); });
  }
  return option;
}
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const areaed = option => seriesArray(option).map((s, i) => (s && s.markArea && s.markArea.data ? i : -1)).filter(i => i >= 0);
const MERGE_KEYS = ['name', 'label', 'itemStyle', 'z2', 'emphasis'];
// MarkerModel fillLabel (MarkerModel.ts:41-43, 166-178): defaultEmphasis(item, 'label', ['show']) on BOTH ends before the merge
function fillLabel(opt) {
  if (opt) {
    opt.label = opt.label || {};
    opt.emphasis = opt.emphasis || {};
    opt.emphasis.label = opt.emphasis.label || {};
    if (!Object.prototype.hasOwnProperty.call(opt.emphasis.label, 'show') && Object.prototype.hasOwnProperty.call(opt.label, 'show')) opt.emphasis.label.show = opt.label.show;
  }
  return opt;
}

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  const input = JSON.parse(optionText);
  const masterOpt = zrMerge(zrClone(firstOf(input.markArea) || {}), MA_DEFAULTS);
  const marked = areaed(input);
  must(marked.length, def.id + ': no series with markArea');
  const base = runChart(JSON.parse(optionText), (chart, svg) => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const svgPolys = svgPolygons(svg);
    const series = marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      const data = sm.getData();
      const filtered = ec.isSeriesFiltered(sm);
      const c = data.getVisual('style')[data.getVisual('drawType')];
      const opt = seriesArray(input)[si];
      const sr = { seriesIndex: si, name: opt.name == null ? null : String(opt.name), type: sm.subType, filtered,
        color: paint(c), seriesName: opt.name == null ? null : sm.name, markArea: null };
      if (filtered) return sr;
      const r = readSeries(chart, sm, svgPolys);
      const inp = { own: opt.markArea, master: masterOpt, seriesOpt: opt, color: c, seriesName: sr.seriesName,
        textStyle: ec.option.textStyle, ground, extent: r.extent, items: r.inputs };
      const key = def.id + '/' + si;
      const run = mut => {
        try {
          return transcribe(zrClone(inp), mut);
        } catch (e) {
          if (e instanceof OracleError && !Object.keys(mut).length) throw e; // a mutation may reach a must(): it just changed
          return { threw: String(e.message) };
        }
      };
      side[key] = { base: run({}), muts: {} };
      for (const gd of GUARDS) side[key].muts[gd.id] = run(gd.mut);
      sr.markArea = r;
      return sr;
    });
    return { ground, textStyle, series };
  });

  const tagged = runChart(tagOption(JSON.parse(optionText)), (chart, svg) => {
    const ec = chart.getModel();
    const svgPolys = svgPolygons(svg);
    return marked.map(si => {
      const sm = ec.getSeriesByIndex(si);
      return ec.isSeriesFiltered(sm) ? null : readSeries(chart, sm, svgPolys);
    });
  });

  const rec = { id: def.id, note: def.note, width: W, height: H, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    nan: !!def.nan, ground: base.ground, textStyle: base.textStyle, series: [] };
  rec.series = base.series.map((sr, n) => {
    const b = sr.markArea;
    if (!b) return sr;
    const t = tagged[n];
    must(t && JSON.stringify(t.rows) === JSON.stringify(b.rows) && JSON.stringify(t.block) === JSON.stringify(b.block),
      def.id + '/' + sr.seriesIndex + ': the tagged run differs from the verbatim run');
    const optData = seriesArray(input)[sr.seriesIndex].markArea.data;
    const nIn = optData.length;
    for (let j = 0; j < t.tags.length; j++) {
      must(Number.isInteger(t.tags[j]) && t.tags[j] >= 0 && t.tags[j] < nIn && (j === 0 || t.tags[j] > t.tags[j - 1]),
        def.id + '/' + sr.seriesIndex + ': tags ' + JSON.stringify(t.tags));
      // the merged item = mergeAll([{}, lt, rb]) of the option pair (no overwrite: lt's keys win, objects merge deep)
      const pair = optData[t.tags[j]];
      const merged = zrMerge(zrMerge({}, fillLabel(zrClone(pair[0]))), fillLabel(zrClone(pair[1])));
      const raw = b.inputs[j].raw;
      for (const k of MERGE_KEYS) {
        must(JSON.stringify(json(raw[k])) === JSON.stringify(json(merged[k])), def.id + '/' + sr.seriesIndex + ': merged ' + k + ' of area ' + j + ' is not merge(lt, rb)');
      }
    }
    const items = [];
    for (let i = 0; i < nIn; i++) {
      const j = t.tags.indexOf(i);
      items.push(Object.assign({ index: i, survived: j >= 0, dataIndex: j >= 0 ? j : null }, j >= 0 ? b.rows[j] : {}));
    }
    return Object.assign({}, sr, { markArea: Object.assign({}, b.block, { items }) });
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
// value x value grid 0..10 x 0..10 with a fractional rect (x = 80.5 + 65.925 v, y = 529.6 - 47.885 v); scatter symbols 7 px
const vv = (markArea, extra, seriesExtra) => Object.assign({ animation: false, grid: G, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [Object.assign({ type: 'scatter', name: 's0', symbolSize: 7, data: PTS, markArea }, seriesExtra || {})] }, extra || {});
const cat = (series, extra) => Object.assign({ animation: false, grid: G, xAxis: { type: 'category', data: WEEK }, yAxis: { type: 'value' }, series }, extra || {});
// n areas on a lattice of cells (cols columns): each area named 'a<i>' unless its extras set name; an extra is either
// the lt item's extras or {lt, rb}
function cells(extras, cols) {
  cols = cols || 4;
  const rows = Math.ceil(extras.length / cols);
  const dx = 9.6 / cols;
  const dy = 9.4 / rows;
  return extras.map((e, i) => {
    const c = i % cols;
    const r = Math.floor(i / cols);
    const x0 = 0.3 + c * dx;
    const yTop = 9.6 - r * dy;
    const pair = e && (e.lt || e.rb) ? e : { lt: e };
    return [Object.assign({ name: 'a' + i, coord: [x0, yTop] }, pair.lt || {}), Object.assign({ coord: [x0 + dx * 0.72, yTop - dy * 0.62] }, pair.rb || {})];
  });
}
const POS13 = ['top', 'bottom', 'left', 'right', 'inside', 'insideLeft', 'insideRight', 'insideTop', 'insideBottom', 'insideTopLeft', 'insideTopRight', 'insideBottomLeft', 'insideBottomRight'];
const BAND_FILLS = ['#ffffff', '#808080', '#04c26d', 'rgba(255,255,255,0.4)', 'rgba(255,255,255,0.5)', 'rgba(255,255,255,0.2)', 'rgba(0,0,0,0.4)', '#333333',
  'transparent', 'hsl(0,0%,100%)', 'hsla(0,0%,100%,0.3)'];
const GRAD = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#c00' }, { offset: 1, color: '#00c' }] };

const CASES = [
  // ----- defaults, geometry -----
  { id: 'D1', note: "defaults on a category line (series colour #5070dd): an xAxis-only range Tue..Thu named (infinite y -> the polygon spans the grid height; label 'top' at rect centre x, rect.y - 5, center / bottom), a yAxis-only range (infinite x -> spans the grid width), a both-dim area, reversed corners (lt = the lower-right: same polygon points permuted, same rect), an UNNAMED area (default text '' -> the label exists, no TSpan). fill = modifyAlpha('#5070dd', 0.4) = 'rgba(80,112,221,0.4)', stroke '#5070dd' at borderWidth 0 (not stroked: the rect is not grown; the SVG still prints stroke with stroke-width 0); outside ink '#333' + white halo; z 1, polygon z2 0, label z2 2",
    option: cat([{ type: 'line', name: 'L', data: D7, markArea: { data: [[{ xAxis: 'Tue', name: 'tue-thu' }, { xAxis: 'Thu' }], [{ yAxis: 100, name: 'y100-150' }, { yAxis: 150 }],
      [{ coord: ['Mon', 100], name: 'both' }, { coord: ['Wed', 200] }], [{ coord: ['Sat', 220], name: 'reversed' }, { coord: ['Thu', 95] }], [{ xAxis: 'Fri' }, { xAxis: 'Sun' }]] } }]) },
  { id: 'D2', note: "value x value areas with fractional pixels: both dims, partly outside (clamped into the grid: the polygon stops at the grid edge), reversed x only, px corners {x: 100, y: 100} / {x: '60%', y: '40%'} (container percents), a zero-height area (y0 = y1: rect height 0, 'top' label still placed)",
    option: vv({ data: [[{ coord: [1.3, 8.7], name: 'both' }, { coord: [3.9, 6.2] }], [{ coord: [8.5, 3], name: 'outside' }, { coord: [12, -3] }], [{ coord: [7, 9.5], name: 'rev-x' }, { coord: [4.6, 8.2] }],
      [{ x: 100, y: 100, name: 'px' }, { x: '60%', y: '40%' }], [{ coord: [2, 2.5], name: 'flat' }, { coord: [5, 2.5] }]] }) },
  { id: 'D3', note: "allClipped: an x range [12, 11] outside the 0..10 extent (xAxis-only: kept by the only-dim rule, allClipped -> NO polygon and NO label); [12, -2] written backwards spanning the extent (sorted first: overlaps, drawn); a yAxis-only range above the extent (allClipped); a normal area after them keeps label z2 2 (clipped areas are not in the group)",
    option: vv({ data: [[{ xAxis: 12, name: 'clipped' }, { xAxis: 11 }], [{ xAxis: 12, name: 'spans' }, { xAxis: -2 }], [{ yAxis: 15, name: 'above' }, { yAxis: 20 }], [{ coord: [2, 3], name: 'ok' }, { coord: [4, 1] }]] }) },
  { id: 'D4', note: "a slider dataZoom window 30..70 % on 10 categories (scale extent [3, 6]): a range across the window's left edge (clamped to the window), one fully left of it (allClipped), one inside, one with the whole axis (c0..c9: clamped both sides)",
    option: cat([{ type: 'line', name: 'Z', data: [50, 300, 120, 132, 101, 134, 90, 230, 210, 20], markArea: { data: [[{ xAxis: 'c1', name: 'edge' }, { xAxis: 'c4' }], [{ xAxis: 'c0', name: 'left' }, { xAxis: 'c1' }],
      [{ xAxis: 'c4', name: 'in' }, { xAxis: 'c5' }], [{ xAxis: 'c0', name: 'all' }, { xAxis: 'c9' }]] } }],
    { xAxis: { type: 'category', data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9'] }, dataZoom: [{ type: 'slider', start: 30, end: 70 }] }) },
  { id: 'D5', note: "bar series: corners snapped to the category TICKS (getMarkerPosition startingAtTick: the end corner takes tick id + 1), labels on those rects (x1 = Mon on both corners still spans one band); a second bar series' area in its own colour #b6d634 with an 'inside' label",
    option: cat([{ type: 'bar', name: 'A', data: [15, 25, 16, 30, 12, 20, 18], markArea: { data: [[{ xAxis: 'Tue', name: 'tue-thu' }, { xAxis: 'Thu' }], [{ xAxis: 'Mon', yAxis: 10, name: 'mon' }, { xAxis: 'Mon', yAxis: 20 }], [{ yAxis: 5, name: 'y' }, { yAxis: 18 }]] } },
      { type: 'bar', name: 'B', data: [5, 15, 26, 20, 22, 10, 8], markArea: { label: { position: 'inside' }, data: [[{ xAxis: 'Sat', name: 'sat' }, { xAxis: 'Sun' }]] } }]) },
  { id: 'D6', note: "a horizontal bar (category y with axisTick.alignWithLabel: no + 1 on the end tick) and a candlestick on a category x: the candlestick colour is its default '#eb5454' -> fill 'rgba(235,84,84,0.4)' (inside label: lum 0.5066 * 0.4 = 0.2026 > 0.2 -> '#eee', stroked with the fill in light mode)",
    option: { animation: false, grid: [{ left: 80.5, right: '55%', top: 50.75, bottom: 70.4 }, { left: '52%', right: 60.25, top: 50.75, bottom: 70.4 }],
      yAxis: [{ type: 'category', data: WEEK.slice(0, 5), axisTick: { alignWithLabel: true }, gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      xAxis: [{ type: 'value', gridIndex: 0 }, { type: 'category', data: WEEK.slice(0, 6), gridIndex: 1 }],
      series: [{ type: 'bar', name: 'H', data: [15, 25, 16, 30, 12], markArea: { data: [[{ yAxis: 'Tue', name: 'tue-thu' }, { yAxis: 'Thu' }], [{ yAxis: 'Mon', xAxis: 10, name: 'mon-wed' }, { yAxis: 'Wed', xAxis: 20 }]] } },
        { type: 'candlestick', name: 'K', xAxisIndex: 1, yAxisIndex: 1, data: OHLC, markArea: { label: { position: 'inside' }, data: [[{ xAxis: 'Tue', name: 'k' }, { xAxis: 'Thu' }], [{ yAxis: 20, name: 'band' }, { yAxis: 30 }]] } }] } },
  { id: 'D7', note: "a category Y axis on a line series: two empty ends (infinite both dims: x to the axis ends, y left on the first / last band CENTRE by the `else if` -- M1's A6), a yAxis-only Tue range; labels on those rects",
    option: { animation: false, grid: G, xAxis: { type: 'value' }, yAxis: { type: 'category', data: WEEK.slice(0, 5) }, series: [{ type: 'line', name: 'V', data: [[3, 'Mon'], [7, 'Tue'], [5, 'Wed'], [9, 'Thu'], [4, 'Fri']],
      markArea: { data: [[{ name: 'all' }, {}], [{ yAxis: 'Tue', name: 'tue' }, {}]] } }] } },
  { id: 'D8', note: "a time x axis: an area between two UTC date strings and one between timestamps; the default text is the name",
    option: { animation: false, grid: G, xAxis: { type: 'time' }, yAxis: { type: 'value' },
      series: [{ type: 'line', name: 'T', data: [[Date.UTC(2024, 0, 1), 5], [Date.UTC(2024, 0, 2), 9], [Date.UTC(2024, 0, 3), 4], [Date.UTC(2024, 0, 5), 7]],
        markArea: { data: [[{ xAxis: '2024-01-02T00:00:00Z', name: 'jan2-4' }, { xAxis: '2024-01-04T00:00:00Z' }], [{ xAxis: Date.UTC(2024, 0, 1, 12), yAxis: 5, name: 'ts' }, { xAxis: Date.UTC(2024, 0, 2, 6), yAxis: 8 }]] } }] } },
  { id: 'N1', note: "an unknown category x range ['Nope', 'Wed'] is kept by the only-dim rule (no containData), its x0 parses to NaN (OrdinalScale.parse of an unknown name), allClipped is false (every NaN comparison is false) -> upstream DRAWS a polygon with two NaN corners: its bbox, rect and label placement are NaN (the documented NaN); the next area is normal",
    nan: true, option: cat([{ type: 'line', name: 'L', data: D7, markArea: { data: [[{ xAxis: 'Nope', name: 'nan' }, { xAxis: 'Wed' }], [{ xAxis: 'Fri', name: 'ok' }, { xAxis: 'Sat' }]] } }]) },
  // ----- itemStyle -----
  { id: 'S1', note: "itemStyle per area: color '#c00' (kept: NO alpha change); borderColor '#000' + borderWidth 3 (the rect grows 1.5 each side: the 'top' label rises 1.5); opacity 0.5 (style.opacity: SVG fill-opacity 0.4 * 0.5; the label opacity stays 1 -- markArea passes no defaultOpacity); borderType 'dashed' at borderWidth 2 ([8, 4]); 'dotted' at 3 ([3]); a number 5 ([5], not scaled); an array [6, 3] at 2 (as is); 'solid' (no dash); 'dashed' at borderWidth 0 (no stroke, no dash, no growth); borderDashOffset 2.6 (style keeps 2.6, SVG prints round 3); borderCap 'round' + borderJoin 'bevel' + borderMiterLimit 4; shadowBlur 10 + shadowColor + offsets (style keys only)",
    option: vv({ data: cells([{ itemStyle: { color: '#c00' } }, { itemStyle: { borderColor: '#000', borderWidth: 3 } }, { itemStyle: { opacity: 0.5 } },
      { itemStyle: { borderType: 'dashed', borderWidth: 2 } }, { itemStyle: { borderType: 'dotted', borderWidth: 3 } }, { itemStyle: { borderType: 5, borderWidth: 1 } },
      { itemStyle: { borderType: [6, 3], borderWidth: 2 } }, { itemStyle: { borderType: 'solid', borderWidth: 2 } }, { itemStyle: { borderType: 'dashed', borderWidth: 0 } },
      { itemStyle: { borderType: 'dashed', borderWidth: 1, borderDashOffset: 2.6 } }, { itemStyle: { borderWidth: 4, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4 } },
      { itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.5)', shadowOffsetX: 2, shadowOffsetY: 3 } }]) }) },
  { id: 'S2', note: "item colour strings kept as held: 'rgba(0,128,255,0.3)', 'hsl(120, 50%, 50%)', 'hsla(20,80%,40%,0.6)', '#abc', '#11223344' (8-digit), 'transparent' (truthy: KEPT -- no series fallback; inside ink '#ccc' with the stroke 'transparent' that paints nothing), 'none' + borderColor '#000' + borderWidth 1 (no fill: the 'insideTop' label takes OUTSIDE ink; the rect grows by max(1, 5)), '' (falsy -> the series colour at alpha 0.4), 'foo' (an unparsable string kept; lum 0 -> '#ccc'; inheritColor = modifyAlpha('foo', 1) = undefined -> label color 'inherit' falls back to the automatic ink); labels 'insideTop'",
    option: vv({ label: { position: 'insideTop' }, data: cells([{ itemStyle: { color: 'rgba(0,128,255,0.3)' } }, { itemStyle: { color: 'hsl(120, 50%, 50%)' } }, { itemStyle: { color: 'hsla(20,80%,40%,0.6)' } },
      { itemStyle: { color: '#abc' } }, { itemStyle: { color: '#11223344' } }, { itemStyle: { color: 'transparent' } }, { itemStyle: { color: 'none', borderColor: '#000', borderWidth: 1 } },
      { itemStyle: { color: '' } }, { itemStyle: { color: 'foo' }, label: { color: 'inherit' } }]) }) },
  { id: 'S3', note: "the SERIES colour fallbacks (one area per series, label 'inside'): 'rgba(255,0,0,0.8)' -> fill alpha REPLACED 'rgba(255,0,0,0.4)', stroke 'rgba(255,0,0,0.8)'; 'hsl(200, 60%, 40%)' -> 'rgba(41,122,163,0.4)' (hsl parsed to rounded bytes, the stroke keeps the hsl string); 'transparent' -> modifyAlpha gives 'rgba(0,0,0,0.4)': a visible DARK veil; '#ff000080' -> 'rgba(255,0,0,0.4)'; 'foo' (unparsable) -> modifyAlpha returns undefined: style.fill is an own undefined -> NO fill (useStyle does not fall back to '#000'), stroke 'foo', the 'inside' label takes outside ink",
    option: Object.assign(vv({}), { series: ['rgba(255,0,0,0.8)', 'hsl(200, 60%, 40%)', 'transparent', '#ff000080', 'foo'].map((c, i) => ({ type: 'bar', name: 'b' + i, itemStyle: { color: c }, data: [[i * 2 + 1, 1]], barWidth: 4,
      markArea: { label: { position: 'inside' }, data: [[{ name: 'c' + i, coord: [i * 2 + 0.2, 9] }, { coord: [i * 2 + 1.7, 3] }]] } })), xAxis: { type: 'value', min: 0, max: 10 } }) },
  { id: 'S4', note: "the itemStyle chain: series markArea itemStyle {color '#0a0', borderColor '#050', borderWidth 2} under the items (item overrides color); the TOP-LEVEL markArea itemStyle {color '#777', opacity 0.6} under a second series without its own; a borderColor '' (falsy -> the series colour) with borderWidth 2; borderColor 'none' with borderWidth 4 (not stroked: no growth)",
    option: Object.assign(vv({}), { series: [{ type: 'scatter', name: 'a', symbolSize: 7, data: PTS, markArea: { itemStyle: { color: '#0a0', borderColor: '#050', borderWidth: 2 },
      data: cells([{}, { itemStyle: { color: '#c0c' } }, { itemStyle: { borderColor: '' } }, { itemStyle: { borderColor: 'none', borderWidth: 4 } }], 4).slice(0, 4) } },
    { type: 'scatter', name: 'b', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'top-level', coord: [2, 3] }, { coord: [8, 1] }]] } }], markArea: { itemStyle: { color: '#777', opacity: 0.6 } } }) },
  { id: 'S5', note: "non-string colours: a bar series with a GRADIENT itemStyle.color -> the fallback fill is the gradient object unchanged (not modifyAlpha'd), stroke the gradient; inheritColor = neutral99 '#000' (label color 'inherit' -> '#000'); an inside label on a gradient -> '#ccc' without stroke; an item gradient colour on a string-coloured series; SVG fill = a paint server ('url')",
    option: Object.assign(vv({}), { series: [{ type: 'bar', name: 'g', itemStyle: { color: GRAD }, data: [[1, 1]], barWidth: 4,
      markArea: { data: [[{ name: 'inherit', coord: [0.5, 9], label: { color: 'inherit' } }, { coord: [3, 6] }], [{ name: 'inside', coord: [3.5, 9], label: { position: 'inside' } }, { coord: [6, 6] }]] } },
    { type: 'scatter', name: 's', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'item-grad', coord: [6.5, 9], itemStyle: { color: GRAD }, label: { position: 'insideBottom', color: 'inherit' } }, { coord: [9.5, 6] }]] } }], xAxis: { type: 'value', min: 0, max: 10 } }) },
  { id: 'S6', note: "stroke growth of the label rect (Path.getBoundingRect): borderWidth 4 with a fill (rect +2 each side), fill 'none' + borderWidth 1 (max(1, 5) = 5: +2.5 each side), fill 'none' + borderWidth 8 (+4), 'transparent' fill + borderWidth 1 dashed (a fill: +0.5, scatter-weight's recipe), borderWidth 0.5 (+0.25); labels top / insideTop / bottom / right / left",
    option: vv({ data: cells([{ itemStyle: { borderWidth: 4 } }, { itemStyle: { color: 'none', borderWidth: 1 }, label: { position: 'insideTop' } }, { itemStyle: { color: 'none', borderWidth: 8 }, label: { position: 'bottom' } },
      { itemStyle: { color: 'transparent', borderWidth: 1, borderType: 'dashed' } }, { itemStyle: { borderWidth: 0.5 }, label: { position: 'right' } }, { itemStyle: { borderWidth: 4 }, label: { position: 'left' } }], 3) }) },
  { id: 'S7', note: "merge semantics of the pair (mergeAll([{}, lt, rb]), no overwrite, objects deep): lt itemStyle {color} + rb itemStyle {borderColor, borderWidth} -> both; lt label {position 'insideTop'} + rb label {color '#f00', position 'bottom'} -> insideTop in '#f00'; the name from rb when lt has none; lt name '' hides rb's name (key present); lt name null hides it too; a numeric name 5 -> '5'; the value from rb reaches {c}; label.show false on rb only hides the label; z2 from rb",
    option: vv({ data: cells([{ lt: { itemStyle: { color: '#39c' } }, rb: { itemStyle: { borderColor: '#036', borderWidth: 3 } } },
      { lt: { label: { position: 'insideTop' } }, rb: { label: { color: '#f00', position: 'bottom' } } },
      { lt: { name: undefined }, rb: { name: 'from-rb' } }, { lt: { name: '' }, rb: { name: 'hidden' } }, { lt: { name: null }, rb: { name: 'hidden-too' } },
      { lt: { name: 5 } }, { lt: { label: { formatter: '{b}={c}' } }, rb: { value: 42 } }, { rb: { label: { show: false } } }, { rb: { z2: 3 } }]) }) },
  // ----- labels -----
  { id: 'L1', note: "every calculateTextPosition position (13) with label.distance 8 at series level: outside ones ('#333' + halo), inside ones against the series fill 'rgba(80,112,221,0.4)' (lum 0.1797 -> '#ccc', stroked with the fill in light mode)",
    option: vv({ label: { distance: 8 }, data: cells(POS13.map(p => ({ label: { position: p } }))) }) },
  { id: 'L2', note: "position edge cases (distance 5): 'outside' -> 'top'; '' -> 'inside' (getShallow stops at the empty string, then || 'inside' -- NOT the default 'top'); null -> the default 'top'; 'start' (unknown: rect.x / rect.y, left / top, outside ink); ['50%', '50%'] and [10, 20] (offsets from the rect's corner: align / valign null -> laid out left / top; outside ink); 'insideTop' with distance 0; 'left' with distance 12",
    option: vv({ data: cells([{ label: { position: 'outside' } }, { label: { position: '' } }, { label: { position: null } }, { label: { position: 'start' } }, { label: { position: ['50%', '50%'] } },
      { label: { position: [10, 20] } }, { label: { position: 'insideTop', distance: 0 } }, { label: { position: 'left', distance: 12 } }], 4) }) },
  { id: 'L3', note: "label.rotate / offset / align: rotate 45 on 'top' (inner rotation about the anchor); offset [10, -5] (anchor moves, origin = -offset); rotate -90 + offset [3, 4] on 'insideLeft'; author align 'right' + verticalAlign 'top'; align 'middle' -> 'center'; verticalAlign 'center' -> 'middle'; baseline 'top' (the verticalAlign fallback); align 'bogus' -> 'left'",
    option: vv({ data: cells([{ label: { rotate: 45 } }, { label: { offset: [10, -5] } }, { label: { rotate: -90, offset: [3, 4], position: 'insideLeft' } }, { label: { align: 'right', verticalAlign: 'top' } },
      { label: { align: 'middle' } }, { label: { verticalAlign: 'center' } }, { label: { baseline: 'top' } }, { label: { align: 'bogus' } }]) }) },
  { id: 'L4', note: "formatter templates on a NAMED series ('Series A'): '{a}|{b}|{c}' with value 7; '{c} and {c}' (first occurrence only); '{d}' literal; '{c}' with no value -> 'undefined', value null -> 'null'; '{b}' with no name -> ''; '{a0}{b0}{c0}'; formatter '' -> '' (a string: formatTpl('') -- the NAME is not used); a series-level formatter 'S:{b}' inherited by the last item (it shadows the top-level markArea formatter 'top:{b}' -- see L4b)",
    option: Object.assign(vv({ label: { formatter: 'S:{b}' }, data: cells([{ label: { formatter: '{a}|{b}|{c}' }, value: 7 }, { label: { formatter: '{c} and {c}' }, value: 3 }, { label: { formatter: '{d}' } },
      { label: { formatter: '<{c}>' } }, { value: null, label: { formatter: '<{c}>' } }, { name: undefined, label: { formatter: '[{b}]' } }, { label: { formatter: '{a0}{b0}{c0}' }, value: 1.5 },
      { label: { formatter: '' } }, {}]) }, null, { name: 'Series A' }),
    { markArea: { label: { formatter: 'top:{b}' } } }) },
  { id: 'L4b', note: "the top-level markArea formatter reaching a second series that has none of its own (the first overrides at series level)",
    option: Object.assign(vv({}), { series: [{ type: 'scatter', name: 'p', symbolSize: 7, data: PTS, markArea: { label: { formatter: 'own:{b}' }, data: [[{ name: 'x', coord: [1, 9] }, { coord: [4, 6] }]] } },
      { type: 'scatter', name: 'q', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'y', coord: [5, 9] }, { coord: [9, 6] }]] } }], markArea: { label: { formatter: 'top:{b}|{a}' } } }) },
  { id: 'L5', note: "default texts = the merged item's NAME (never the value): a plain name; a numeric name 12.5 -> '12.5'; a boolean name -> '' (convertOptionIdName drops it); a two-line name 'a\\nb' (two TSpans); no name with a value 9 -> '' (no TSpan)",
    option: vv({ data: cells([{ name: 'plain' }, { name: 12.5 }, { name: true }, { name: 'a\nb' }, { name: undefined, value: 9 }], 3) }) },
  { id: 'L6', note: "label fonts: fontSize 16, fontWeight 'bold', fontFamily 'serif', fontStyle 'italic' per item; fontSize '18px' (kept as is); the rest from the global textStyle (option textStyle {fontSize: 13, fontWeight: 600})",
    option: vv({ data: cells([{ label: { fontSize: 16 } }, { label: { fontWeight: 'bold' } }, { label: { fontFamily: 'serif' } }, { label: { fontStyle: 'italic' } }, { label: { fontSize: '18px' } }, {}], 3) },
      { textStyle: { fontSize: 13, fontWeight: 600 } }) },
  { id: 'L7', note: "label colours: color '#f0f' (a style fill -> no automatic stroke); color 'inherit' on the series fallback fill (= modifyAlpha(fill, 1) = 'rgba(80,112,221,1)', outsideFill too); 'inherit' on item colour '#c00' ('rgba(204,0,0,1)'); 'inherit' on an 'inside' label; textBorderColor 'inherit' + textBorderWidth 3; textBorderWidth 1.5 alone (the automatic halo at 1.5); textBorderColor 'none'; label opacity 0.5; backgroundColor '#ff0' (a box: no automatic stroke); show false (null)",
    option: vv({ data: cells([{ label: { color: '#f0f' } }, { label: { color: 'inherit' } }, { itemStyle: { color: '#c00' }, label: { color: 'inherit' } }, { label: { color: 'inherit', position: 'inside' } },
      { label: { textBorderColor: 'inherit', textBorderWidth: 3 } }, { label: { textBorderWidth: 1.5 } }, { label: { textBorderColor: 'none' } }, { label: { opacity: 0.5 } },
      { label: { backgroundColor: '#ff0' } }, { label: { show: false } }]) }) },
  // ----- ink bands and grounds -----
  { id: 'K1', note: "inside ink bands ('inside' labels) against the polygon fill WITH its alpha (lum = rgb lum * a over black): '#fff' (1 -> '#333'), '#808080' (0.502 -> '#333'), '#04c26d' (exactly 0.5 -> '#eee'), rgba(255,255,255,0.4) (0.4 -> '#eee'), rgba(255,255,255,0.5) (exactly 0.5 -> '#eee'), rgba(255,255,255,0.2) (exactly 0.2 -> '#ccc'), rgba(0,0,0,0.4) (0), '#333' (0.19999), 'transparent' (0: '#ccc', its stroke 'transparent' paints nothing), hsl(0,0%,100%) (1), hsla(0,0%,100%,0.3) (0.3 -> '#eee'); plus the series fallback 'rgba(80,112,221,0.4)' (0.18 -> '#ccc'); stroke = the fill for the light labels in light mode",
    option: vv({ label: { position: 'inside' }, data: cells(BAND_FILLS.map(c => ({ itemStyle: { color: c } })).concat([{}])) }) },
  { id: 'K2', note: "the same fills with darkMode true: the inside stroke = the fill exactly for the DARK label '#333'; an outside ('top') label '#ccc' with the halo blended on black 'rgba(0,0,0,1)'",
    option: vv({ label: { position: 'inside' }, data: cells(BAND_FILLS.map(c => ({ itemStyle: { color: c } })).concat([{ label: { position: 'top' } }])) }, { darkMode: true }) },
  { id: 'K3', note: "backgroundColor '#1e1e1e' (darkMode auto: lum < 0.4): default 'top' labels '#ccc' + halo 'rgba(30,30,30,1)'; an inside label on the series fill ('#ccc', NOT stroked: a light label in dark mode); an inside label on '#fff' ('#333' stroked with '#fff')",
    option: vv({ data: cells([{}, { label: { position: 'inside' } }, { itemStyle: { color: '#fff' }, label: { position: 'inside' } }], 3) }, { backgroundColor: '#1e1e1e' }) },
  { id: 'K4', note: "backgroundColor 'rgba(0,0,0,0.5)' (lum 0.5: light): outside halo = 0 * 0.5 + 255 * 0.5 = 127.5 per channel -> 'rgba(127.5,127.5,127.5,1)'",
    option: vv({ data: cells([{}, { label: { position: 'bottom' } }], 2) }, { backgroundColor: 'rgba(0,0,0,0.5)' }) },
  // ----- z / silent / hidden -----
  { id: 'Z1', note: "z / zlevel / silent from the top-level markArea {z: 3, zlevel: 1, silent: true}; item z2: a first area z2 10 lifts EVERY later label (label z2 = running max of the drawn polygons' z2 so far + 2 = 12); an allClipped area with z2 50 does NOT count (not in the group); a z2 -5 area keeps 12; the second series (markArea z 0 -> 0, z2 1 at series level) with a z2 -5 area FIRST -> its label -3, the next takes z2 1 -> 3; label.silent on one item",
    option: Object.assign(vv({}), { series: [{ type: 'scatter', name: 's0', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'z10', z2: 10, coord: [0.5, 9.5] }, { coord: [2, 8] }],
      [{ name: 'clipped', z2: 50, xAxis: 20 }, { xAxis: 30 }], [{ name: 'plain', coord: [3, 9.5] }, { coord: [4.5, 8] }], [{ name: 'neg', z2: -5, coord: [5.5, 9.5] }, { coord: [7, 8] }]] } },
    { type: 'scatter', name: 's1', symbolSize: 7, data: PTS, markArea: { z: 0, z2: 1, data: [[{ name: 'neg', z2: -5, coord: [0.5, 5] }, { coord: [2, 3.5] }], [{ name: 'series-z2', coord: [3, 5] }, { coord: [4.5, 3.5] }],
      [{ name: 'silent-label', coord: [5.5, 5], label: { silent: true } }, { coord: [7, 3.5] }]] } }], markArea: { z: 3, zlevel: 1, silent: true } }) },
  { id: 'Z2', note: 'series silent: true (the polygon group is silent: every polygon isSilent); markArea silent on another series; neither on a third',
    option: Object.assign(vv({}), { series: [{ type: 'scatter', name: 's0', silent: true, symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'a', coord: [1, 9] }, { coord: [3, 7] }]] } },
      { type: 'scatter', name: 's1', symbolSize: 7, data: PTS, markArea: { silent: true, data: [[{ name: 'b', coord: [4, 9] }, { coord: [6, 7] }]] } },
      { type: 'scatter', name: 's2', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'c', coord: [7, 9] }, { coord: [9, 7] }]] } }] }) },
  { id: 'H1', note: 'a legend-unselected series draws no markArea (filtered); the visible one does',
    option: Object.assign(vv({}), { legend: { selected: { hidden: false } }, series: [{ type: 'scatter', name: 'hidden', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 'h', coord: [1, 9] }, { coord: [3, 7] }]] } },
      { type: 'scatter', name: 'shown', symbolSize: 7, data: PTS, markArea: { data: [[{ name: 's', coord: [5, 9] }, { coord: [8, 7] }]] } }] }) },
];
const GALLERY_CASES = ['area-rainfall', 'line-sections', 'scatter-weight'];
const GALLERY_NOTES = {
  'area-rainfall': "gallery area-rainfall.json, verbatim: two line series with markArea {silent: true, itemStyle {opacity: 0.3}} xAxis-only ranges under a dataZoom window 65..85 %: fill 'rgba(r,g,b,0.4)' of each series colour painted at opacity 0.3 (SVG fill-opacity 0.12); no names -> '' labels (no TSpan); silent polygons",
  'line-sections': "gallery line-sections.json, verbatim: itemStyle.color 'rgba(255, 173, 177, 0.4)' kept as held (spaces and all); named 'top' labels; inheritColor would be 'rgba(255,173,177,1)'",
  'scatter-weight': "gallery scatter-weight.json, verbatim: 'transparent' fill kept, dashed borderWidth 1 in the series colour (dash [4, 2]); the rect grows 0.5 each side; named 'top' labels; silent",
};
for (const g of GALLERY_CASES) CASES.push({ id: 'G-' + g, note: GALLERY_NOTES[g] || 'gallery ' + g + '.json, verbatim', gallery: g });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'no-series-level', mutation: 'the series markArea option skipped in every chain (item -> top-level -> default)', mut: { noSeriesLevel: true }, named: ['S4', 'L1', 'L4'] },
  { id: 'z-default', mutation: 'z always the default 1 (the chain ignored)', mut: { zDefault: true }, named: ['Z1'] },
  { id: 'silent-marker-only', mutation: "the group's silent ignores series.silent", mut: { silentMarkerOnly: true }, named: ['Z2'] },
  { id: 'no-asc', mutation: 'allClipped compares the corner values unsorted', mut: { noAsc: true }, named: ['D3'] },
  { id: 'no-all-clipped', mutation: 'allClipped never set (every area drawn)', mut: { noAllClipped: true }, named: ['D3', 'D4', 'Z1'] },
  { id: 'fill-no-alpha', mutation: 'the series-colour fill fallback without modifyAlpha(0.4)', mut: { fillNoAlpha: true }, named: ['D1', 'K1', 'G-area-rainfall'] },
  { id: 'alpha-multiplied', mutation: "modifyAlpha multiplies the colour's alpha instead of replacing it", mut: { alphaMultiplied: true }, named: ['S3'] },
  { id: 'unparsable-kept', mutation: 'modifyAlpha of an unparsable colour returns it unchanged (instead of undefined)', mut: { unparsableKept: true }, named: ['S3', 'S2'] },
  { id: 'fill-null-check', mutation: "the fill fallback only for a null colour ('' kept)", mut: { fillNullCheck: true }, named: ['S2'] },
  { id: 'transparent-falsy', mutation: "a 'transparent' itemStyle.color treated as unset (series fallback)", mut: { transparentFalsy: true }, named: ['S2', 'G-scatter-weight'] },
  { id: 'stroke-no-fallback', mutation: 'the stroke does not fall back to the series colour', mut: { strokeNoFallback: true }, named: ['D1', 'S6'] },
  { id: 'stroke-from-fill', mutation: "the stroke falls back to the (alpha'd) fill instead of the series colour", mut: { strokeFromFill: true }, named: ['D1', 'G-scatter-weight'] },
  { id: 'no-close-path', mutation: 'the polygon path without the closing Z', mut: { noClosePath: true }, named: ['D1'] },
  { id: 'rect-no-stroke', mutation: 'the label rect not grown by the stroke', mut: { rectNoStroke: true }, named: ['S1', 'S6', 'G-scatter-weight'] },
  { id: 'rect-stroke-halved', mutation: 'the label rect grown by lineWidth / 2 in total (lineWidth / 4 per side)', mut: { rectStrokeHalved: true }, named: ['S1', 'S6'] },
  { id: 'no-fill-threshold', mutation: 'a fill-less stroked polygon grows its rect by lineWidth, not max(lineWidth, 5)', mut: { noFillThreshold: true }, named: ['S6'] },
  { id: 'threshold-4', mutation: "the fill-less growth floor 4 (Path.ts's `== null ? 4` branch) instead of strokeContainThreshold 5", mut: { threshold4: true }, named: ['S6'] },
  { id: 'dashed-5-5', mutation: "'dashed' resolved as [5w, 5w] instead of [4w, 2w]", mut: { dashed55: true }, named: ['S1', 'G-scatter-weight'] },
  { id: 'dash-scaled', mutation: 'numeric / array dash multiplied by lineWidth', mut: { dashScaled: true }, named: ['S1'] },
  { id: 'inherit-raw', mutation: 'inheritColor = the fill as held (no modifyAlpha(fill, 1))', mut: { inheritRaw: true }, named: ['L7', 'S5'] },
  { id: 'inherit-neutral', mutation: 'inheritColor always neutral99', mut: { inheritNeutral: true }, named: ['L7'] },
  { id: 'label-opacity-from-item', mutation: 'the label opacity defaults to itemStyle.opacity (as markPoint)', mut: { labelOpacityFromItem: true }, named: ['S1', 'G-area-rainfall'] },
  { id: 'default-text-null', mutation: "no name -> text null instead of ''", mut: { defaultTextNull: true }, named: ['D1', 'L5', 'G-area-rainfall'] },
  { id: 'formatter-empty-falls-back', mutation: "formatter '' falls back to the default text", mut: { formatterEmptyFallsBack: true }, named: ['L4'] },
  { id: 'tpl-replace-all', mutation: 'formatTpl replaces every occurrence', mut: { tplReplaceAll: true }, named: ['L4'] },
  { id: 'position-empty-top', mutation: "label.position '' skipped in the chain (-> the default 'top')", mut: { positionEmptyTop: true }, named: ['L2'] },
  { id: 'outside-not-top', mutation: "position 'outside' not mapped to 'top'", mut: { outsideNotTop: true }, named: ['L2'] },
  { id: 'unknown-inside', mutation: "an unknown position treated as 'inside'", mut: { unknownInside: true }, named: ['L2'] },
  { id: 'array-align-left', mutation: "an array position gives align 'left' / valign 'top' instead of null", mut: { arrayAlignLeft: true }, named: ['L2'] },
  { id: 'distance-ignored', mutation: 'label.distance ignored (always 5)', mut: { distanceIgnored: true }, named: ['L1', 'L2'] },
  { id: 'inside-as-outside', mutation: 'inside positions use the outside ink', mut: { insideAsOutside: true }, named: ['K1', 'L1', 'D6'] },
  { id: 'no-fill-inside', mutation: 'inside ink even when the polygon has no fill', mut: { noFillInside: true }, named: ['S2', 'S3'] },
  { id: 'lum-ignores-alpha', mutation: "the inside band lum ignores the fill's alpha", mut: { lumIgnoresAlpha: true }, named: ['K1', 'L1', 'D6'] },
  { id: 'inside-stroke-never', mutation: 'no automatic inside stroke', mut: { insideStrokeNever: true }, named: ['K1', 'K2'] },
  { id: 'bands-inclusive', mutation: 'the lum bands compared with >= instead of >', mut: { bandsInclusive: true }, named: ['K1'] },
  { id: 'dark-ignored', mutation: 'the ground never dark (outside ink, inside stroke)', mut: { darkIgnored: true }, named: ['K2', 'K3'] },
  { id: 'z2-per-area', mutation: "label z2 = this polygon's z2 + 2 (no running max)", mut: { z2PerArea: true }, named: ['Z1'] },
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
// the recorded series block (items) vs a transcription result (areas in dataIndex order)
function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const ma = sr.markArea;
  const a = {};
  const b = {};
  flat({ z: ma.z, zlevel: ma.zlevel, silent: ma.silent, count: ma.count, extent: ma.extent, extentText: ma.extentText }, 'block', a);
  flat({ z: t.z, zlevel: t.zlevel, silent: t.silent, count: t.count, extent: t.extent, extentText: t.extentText }, 'block', b);
  for (const it of ma.items) {
    if (!it.survived) continue;
    const { index, survived, dataIndex, ...rest } = it;
    flat(rest, 'area' + dataIndex, a);
    flat(t.areas[dataIndex], 'area' + dataIndex, b);
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
      update: 'setOption, then zr.storage.getDisplayList(true) (update / updateInnerText of every element), then chart.renderToSVGString() (the SVG painter maps the polygon styles)',
      areaData: "MarkerModel.getMarkerModelFromSeries(series, 'markArea').getData(): getRawDataItem, getItemLayout {points, allClipped}, get(x0 / y0 / x1 / y1) through axis.scale.parse, getItemVisual('style' / 'z2')",
      polygon: 'areaData.getItemGraphicEl(i) = the Polygon (null when allClipped); el.path.data up to len(); el.path.getBoundingRect(); el.getBoundingRect(); el.getTextContent() = the label',
      svg: 'the SVG <polygon> with ecmeta_series_index / ecmeta_data_index: fill, fill-opacity, stroke, stroke-width, stroke-opacity, stroke-dasharray, stroke-dashoffset, stroke-linecap / -linejoin / -miterlimit (absent attributes recorded null)',
      tag: "a second run with both ends of each data pair tagged '" + TAG + "' maps areas to original indices",
    },
    notes: [
      'Only cartesian2d series are covered. Emphasis / blur states, tooltip and decal are out of scope.',
      "The default label font family comes from globalDefault.ts: 'Microsoft YaHei' when navigator.platform starts with 'Win' (node >= 21 has a navigator: 'Win32' on this machine), else 'sans-serif'. The recorded fonts are this machine's; every case records ecModel.option.textStyle.",
      "The polygon is M p0 L p1 L p2 L p3 Z over the layout corners [x0,y0], [x1,y0], [x1,y1], [x0,y1] (zrender poly buildPath, smooth 0); it has no transform, so the label is placed against Path.getBoundingRect() directly -- the path bbox grown by the stroke when stroke is set (not 'none') and lineWidth > 0: + lineWidth (max(lineWidth, 5) without a fill), half each side.",
      "Fill: itemStyle.color through item -> series markArea -> top-level markArea when truthy (kept exactly as held: 'transparent', rgba, hsl, gradients, even an unparsable string), else the series colour -- through zrender modifyAlpha(c, 0.4) when it is a string: parse, REPLACE the alpha, 'rgba(r,g,b,0.4)'; an unparsable series colour gives undefined = no fill. Stroke: itemStyle.borderColor when truthy, else the series colour as is; drawn only with borderWidth > 0 (default 0).",
      "Label: default text = the merged item's name ('' -- no TSpan -- when none); a string formatter (even '') replaces it; {a} = the host series name, {b} = the name, {c} = the merged item's value. inheritColor (label color / textBorderColor 'inherit') = modifyAlpha(fill, 1) for a string fill (undefined for an unparsable one -> the automatic ink), else '#000' (neutral99). The label opacity is NOT defaulted from itemStyle.opacity (unlike markPoint / markLine).",
      "Inside ink (a position containing 'inside' and a fill) reads the fill's lum WITH its alpha over black: the default alpha-0.4 fills land in the '#ccc' / '#eee' bands (light labels), stroked with the fill in light mode.",
      "svg: what the SVG painter prints -- rgba colours split into rgb + fill-opacity / stroke-opacity (x style.opacity), 'transparent' printed 'none', a gradient printed as a paint server (recorded 'url'); stroke-width printed even at 0 (the canvas painter does not stroke at lineWidth 0); stroke-dashoffset rounded.",
      'A polygon with NaN corners (N1) is drawn by upstream; its bbox / rect / label coordinates are NaN.',
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
      if (!sr.markArea) continue;
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
      for (const it of sr.markArea.items) if (it.survived && scanNaN(it)) anyNaN = true;
    }
    must(anyNaN === c.nan, c.id + ': ' + (anyNaN ? 'NaN although the case is not marked nan' : 'expected NaN'));
  }
  // anchors
  const item = (id, si, i) => byId[id].series.find(s => s.seriesIndex === si).markArea.items[i];
  const n = h => num(h);
  const d1 = item('D1', 0, 0);
  must(d1.visual.fill === 'rgba(80,112,221,0.4)' && d1.visual.stroke === '#5070dd' && d1.polygon.style.lineWidthText === '0', 'D1: fallbacks');
  must(d1.polygon.path.map(c => c.cmd).join('') === 'MLLLZ' && d1.label.position === 'top' && d1.label.text === 'tue-thu', 'D1: path, label');
  must(n(d1.label.inner.y) === n(d1.polygon.rect.y) - 5 && d1.label.inkDefault.fill === '#333' && d1.label.z2 === 2 && d1.polygon.z === 1, 'D1: top label, z');
  must(JSON.stringify(d1.polygon.rect) === JSON.stringify(d1.polygon.bbox), 'D1: no stroke growth at width 0');
  must(item('D1', 0, 4).label.text === '' && item('D1', 0, 4).label.ink === null, 'D1: unnamed');
  must(item('D3', 0, 0).allClipped && item('D3', 0, 0).polygon === null && item('D3', 0, 0).label === null && !item('D3', 0, 1).allClipped, 'D3: allClipped');
  must(item('S1', 0, 0).visual.fill === '#c00' && item('S1', 0, 2).polygon.svg.fillOpacityText === '0.2' && item('S1', 0, 2).label.style.opacityText === '1', 'S1: colour, opacity');
  must(JSON.stringify(item('S1', 0, 3).polygon.svg.dashText) === '["8","4"]', 'S1: dashed');
  must(n(item('S1', 0, 1).polygon.rect.y) === n(item('S1', 0, 1).polygon.bbox.y) - 1.5, 'S1: stroke growth');
  must(item('S2', 0, 5).visual.fill === 'transparent' && item('S2', 0, 6).label.inside === false, 'S2: transparent kept, none -> outside');
  must(item('S3', 2, 0).visual.fill === 'rgba(0,0,0,0.4)' && item('S3', 0, 0).visual.fill === 'rgba(255,0,0,0.4)' && item('S3', 4, 0).polygon.style.fill === null, 'S3: series fallbacks');
  must(n(item('S6', 0, 1).polygon.rect.y) === n(item('S6', 0, 1).polygon.bbox.y) - 2.5, 'S6: no-fill threshold');
  must(item('S7', 0, 3).label.text === '' && item('S7', 0, 2).label.text === 'from-rb' && item('S7', 0, 7).label === null, 'S7: merge');
  must(item('L2', 0, 1).label.position === 'inside' && item('L2', 0, 0).label.position === 'top', 'L2: empty / outside');
  must(item('L4', 0, 7).label.text === '' && item('L4', 0, 1).label.text === '3 and {c}', 'L4: formatter');
  must(item('L7', 0, 1).label.style.fill === 'rgba(80,112,221,1)', 'L7: inherit');
  must(item('K1', 0, 2).label.inkDefault.fill === '#eee' && item('K1', 0, 5).label.inkDefault.fill === '#ccc' && item('K1', 0, 11).label.inkDefault.fill === '#ccc', 'K1: bands');
  must(item('K4', 0, 0).label.ink.stroke === 'rgba(127.5,127.5,127.5,1)', 'K4: fractional halo');
  must(item('Z1', 0, 2).label.z2 === 12 && item('Z1', 0, 3).label.z2 === 12 && item('Z1', 1, 0).label.z2 === -3, 'Z1: running z2');
  must(byId.H1.series[0].filtered && byId.H1.series[0].markArea === null, 'H1: hidden series');
  must(item('G-area-rainfall', 0, 0).polygon.svg.fillOpacityText === '0.12' || item('G-area-rainfall', 0, 0).polygon === null, 'area-rainfall: 0.4 x 0.3');

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        if (!sr.markArea) continue;
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
const nAreas = out.cases.reduce((a, c) => a + c.series.reduce((b, s) => b + (s.markArea ? s.markArea.items.filter(i => i.survived).length : 0), 0), 0);
console.log(out.cases.length + ' cases (' + nAreas + ' areas); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages from upstream');
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
