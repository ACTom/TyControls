/*
Upstream's own answers for the HEATMAP series on a CALENDAR, batch H2: each
cell's rect, style and label exactly as chart/heatmap/HeatmapView.ts
_renderOnGridLike (the calendar branch: coordSys.dataToLayout([time]).contentRect,
z2 1), chart/heatmap/HeatmapSeries.ts (dimensions time + value),
data/helper/dataValueHelper.ts parseDataValue + util/number.ts parseDate (the
store's time / value), coord/calendar/Calendar.ts (getDateInfo, dataToPoint's
clamp, dataToLayout + util/graphic.ts expandOrShrinkRect), visual/style.ts +
visual/visualSolution.ts (the cell style), model/mixin/dataFormat.ts,
label/labelStyle.ts, util/graphic.ts traverseUpdateZ and zrender (Rect /
roundRect, PathProxy.getBoundingRect, Path.getBoundingRect / getInsideTextFill /
getInsideTextStroke, Element.updateInnerText, contain/text.ts
calculateTextPosition, Text / TSpan) build them. It is heatmap-cartesian.js's
record on calendar-layout.js's coordinate system: the geometry and the calendar
picture themselves are pinned there; this oracle pins where a heatmap row lands
on the calendar, whether it lands at all, and how its cell and label sit in the
paint order among the calendar's day cells, split lines and names.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
with Math.random replaced by the port's xorshift32 (seed 2463534242, reset
before each chart) and process.env.TZ = 'UTC' set inside this script before
anything touches Date (checked: a script that runs under another zone stops).
After setOption it runs zr.storage.getDisplayList(true) (every element's
update: updateInnerText places the labels, the Texts lay out their TSpans) and
reads the live models, the coordinate systems, the views and the display list.
Every chart is disposed in a finally.

The DEVELOPMENT build throws on a heatmap without a visualMap
(HeatmapView.ts:111-115); the PRODUCTION build (dist/echarts.min.js, next to
ECHARTS_DIST) carries on. A case marked `prod` is recorded from the production
build and must throw in development; every other case is recorded from the
development build and must record identically through the production build.

  node tools/advchart-oracle/heatmap-calendar.js

writes tests/fixtures/advchart-heatmap-calendar.json (ORACLE_OUT overrides;
ORACLE_DUMP=<file> also writes the record before the checks, for debugging).

-----------------------------------------------------------------------------
Numbers are plain JSON numbers written by JSON.stringify (shortest round-trip
form: they parse back to the same double), as calendar-layout.js. Values JSON
has no form for:
  null        NaN in a number field (e.g. `time` of an unparsable date), or an
              undefined value inside an array
  "-0" / "Infinity" / "-Infinity"   those doubles, as strings (the writer
              counts them and prints the count: C3's 'Infinity' value)
  an absent key   upstream holds undefined
A colour is a css string exactly as upstream holds it (or null).

Top level
  source, W, H, seed, tz ('UTC'), api {...}, notes[], cases[], guards[]
  cases[]  one per chart:
    id, note, gallery (file name or null), option (as fed; null for a gallery
    case: load examples/advchart/gallery/<gallery>.json and feed it VERBATIM,
    series and all), productionBuild (bool), devError (the development build's
    message, or null)
    ground     {background: zr.getBackgroundColor(), isDark: zr.isDarkMode()}
    textStyle  ecModel.option.textStyle (the global text style every label
               font part falls back to; fontFamily 'Microsoft YaHei' on this
               Windows machine, 'sans-serif' elsewhere -- globalDefault.ts)
    calendars[]  one per calendar component (the geometry the cells come from;
               the full calendar picture is calendar-layout.js's):
      index, id (the option id or null), rect {x, y, width, height},
      cellSize [sw, sh], lineWidth (Calendar._lineWidth = itemStyle borderWidth
      || 0: the contentRect inset is lineWidth / 2 per side), orient, firstDay,
      range ['yyyy-MM-dd', 'yyyy-MM-dd'], startTime, endTime (ms of the first /
      last day's local = UTC midnight), fweek, lweek, weeks, allDay, z, zlevel,
      splitLine (bool: splitLine.show)
    paintRuns  the WHOLE display list (zr.storage.getDisplayList) in paint
               order, run-length encoded: [{owner, index, type, group, zlevel,
               z, z2, n}] -- consecutive elements with the same six keys form one
               run. owner 'calendar' (index = calendar index, type null, group
               'day' | 'split' | 'edge' | 'year' | 'month' | 'week'), 'series'
               (index = series index, type = the series type, group 'cell' (a
               heatmap cell) | 'label' (a TSpan of a label: series-owned text
               content) | 'mark' (any other element of a non-heatmap series)),
               'component' (index = component index, type = its mainType, e.g.
               'visualMap', group 'mark' / 'label'), or 'other' (nothing owns it:
               index / type / group null)
    series[]   EVERY series, series order:
      seriesIndex, type, name (option name or null), recorded (true only for a
      heatmap: every other series is present for the paint order only, marked
      recorded false and nothing else), calendarIndex (the calendar its
      coordinate system is, null when not on a calendar)
      heatmap series also: filtered (legend-unselected: nothing drawn, `heatmap`
      null), color (the series visual colour data.getVisual('style').fill --
      the palette colour unless series itemStyle.color is set), seriesName (the
      name {a} prints; null when the option has no name), heatmap: null or
        dimensions  the store dims: ['time', 'value'] plus value0, value1, ...
          for every further element of the FIRST row's value
          (getDataItemValue(data[0]).length) -- the visualMap's default
          dimension is the LAST of them
        dimensionTypes  per dim: 'time', then 'float' or 'ordinal' (guessOrdinal
          over the first up-to-5 rows: the first value that is not null / '-'
          decides -- a non-numeric string -> 'ordinal'; an ordinal dim keeps the
          RAW values in the store)
        z, zlevel (series z || 0 -- default 2 -- and zlevel || 0), silent (the
          view group's silent = !!series.silent: every cell inherits it)
        seriesStyle  the series visual style data.getVisual('style') (own keys,
          as `style` below)
        count (data.count() = the rows: nothing filters a calendar series),
        hasItemOption
        rows[] one per data element, raw order:
          index
          raw      json: data.getRawDataItem as upstream HOLDS it
          time     data.get('time', i): the store's parse of raw[0] (a number
                   kept AS IS, fraction and all; a string through parseDate --
                   zone-less = local = UTC here, 'Z' / '+hh:mm' offsets with the
                   MINUTES IGNORED; '-', null, '' -> NaN)
          value    data.get('value', i): on a 'float' value dim Number(raw[1])
                   ('-', null, '', missing, 'abc' -> NaN; true -> 1; the string
                   "Infinity" here is +Infinity); on an 'ordinal' value dim the
                   RAW value as written (a string -- "Infinity" is then the
                   string --, a number, null; absent = undefined)
          name     data.getName(i): what {b} prints ('' unless the item has a
                   name)
          vm       null when no visualMap targets the series, else {vms:
                   [{index, value (the store value of the visualMap's dim: raw
                   on an ordinal dim; absent = undefined), state, skipped}],
                   color (the colour the visualMaps wrote, null when none OR
                   when they wrote undefined -- colorWritten tells), colorWritten,
                   opacity, opacityWritten} -- computed by upstream's own models
          style    the visual style = the cell's own style keys (el.style own
                   keys == data.getItemVisual(i, 'style'), checked; zrender
                   also adds an own `blend: null`, not recorded): the series
                   itemStyle, then what the visualMaps wrote, then the item's own
                   itemStyle keys. An ABSENT key reads zrender's
                   DEFAULT_PATH_STYLE (fill '#000', stroke none, lineWidth 1,
                   opacity 1, ...); a key recorded null is an own key holding
                   undefined, which SHADOWS the default: stroke null = no stroke
                   (the palette branch always leaves one), fill null = NO FILL
                   (a visualMap that maps a NaN / non-numeric value writes an
                   undefined colour: C4, C21, C22 -- the cell is invisible and
                   its label takes the outside ink)
          drawn    bool: a cell exists
          skip     null (drawn) or why not, the FIRST failing test in upstream's
                   order: 'value' (value NaN), 'time' (time NaN -> dataToLayout
                   NaN), 'before' / 'after' (the time, Math.round-ed, is before
                   the first day's midnight / at or after the day after the last
                   day: dataToPoint's clamp)
          rect     null (not drawn) or the cell Rect:
            shape {x, y, width, height}: EXACTLY dataToLayout([time]).contentRect
              (checked against upstream's own call and against an independent
              recomputation from the calendar record)
            r      json: borderRadius through item itemStyle -> series itemStyle
                   (null = none)
            path   null = the plain rect command R(shape); else the PathProxy
                   commands [{cmd, args}] (round rect: M L [A] L [A] L [A] L [A]
                   Z, A = cx, cy, rx, ry, startAngle, sweep, 0, clockwise 1)
            bbox   null = shape; else PathProxy.getBoundingRect
            rect   null = bbox; else Path.getBoundingRect (grown by the stroke:
                   + lineWidth, or max(lineWidth, 5) without a fill) = the rect
                   the label is placed against
            z, z2 (1), zlevel, silent (el.isSilent())
            paint  the cell's display-list index
          label    null (not drawn or not shown), else:
            text          style.text: the formatted string or the default text
                          String(rawValue[2]) -- '-' when the raw value has no
                          third element (the usual [date, value] row)
            lines         the number of TSpans (0 for '')
            position      json: textConfig.position (default 'inside';
                          'outside' -> 'top')
            distance      textConfig.distance (default 5)
            inner         {x, y, rotation, originX, originY}: the
                          innerTransformable after updateInnerText
                          (calculateTextPosition on the cell rect, then
                          label.rotate / label.offset); the Text element's own
                          transform is the identity (checked)
            transform     m6 of the inner transformable (null: none)
            align, verticalAlign  as laid out: the style's (author) value, else
                          the calculated one, else 'left' / 'top'
            authorAlign, authorVerticalAlign  the style's; null = unset
            inside        bool: the inside ink rule applies
            font, fontSize, fontWeight, fontStyle, fontFamily
            style         {fill, stroke, lineWidth, opacity, backgroundColor}:
                          the Text style (null = not in the style); opacity =
                          label.opacity, else the global textStyle's, else the
                          CELL style opacity, else 1
            inkDefault    {fill, stroke, autoStroke, align, verticalAlign}: the
                          text's _defaultStyle set by updateInnerText
            ink           null when no TSpan, else {fill, stroke (null = none),
                          lineWidth (null = no stroke), opacity}: what the TSpans
                          draw (the halo = stroke + lineWidth)
            tspans        [{text, x, y, textAlign, textBaseline}] (RECORDED, not
                          transcribed: zrender's Text layout, as calendar-layout)
            z, z2 (3: the running max z2 of the view group -- the cells' 1 --
                  + 2), zlevel, silent (label.silent)
            paint         the display-list index of the first TSpan (null: none)
  guards[]  one per mutation of the transcription: id, mutation, named (the
            cases that must turn red), changed (the cases the mutated
            transcription does not reproduce), ok = named is a subset of
            changed, differs (the first differing fields of each named case)

-----------------------------------------------------------------------------
The transcription (checked against every recorded heatmap series, Object.is on
every field) takes as INPUTS: the series option as fed merged over
HeatmapSeries.defaultOption (checked against upstream's own on the keys read),
the palette colour, the host series name, ecModel.option.textStyle, the ground,
EVERY calendar's {rect, sw, sh, lineWidth, orient, firstDay, range start / end
day} plus the series' calendar index, and per row the raw item and what the
visualMaps wrote. It reproduces: parseDataValue for the time and value dims,
the calendar clamp and cell on civil day numbers (calendar-layout.js's
transcription: dn = floor(round(time) / 86400000), day = |(weekday + 7 -
firstDay) % 7|, nth = floor((dn - S + fweek) / 7), centre = rect.x + nth*sw +
sw/2 (horizontal; vertical swaps), rect = centre - sw/2, contentRect =
expandOrShrinkRect(rect, lineWidth / 2)), HeatmapView's skip test, the style
stages, getName, the default text / formatter templates, borderRadius and the
round-rect path, the bounding rects, createTextStyle / createTextConfig,
calculateTextPosition, updateInnerText's ink, Text makeFont, and traverseUpdateZ
(z, zlevel, label z2).
Self-checks (any failure: nothing is written, exit 1): TZ is UTC; the heatmap
dims are time + value; the transcription reproduces every recorded series; each
drawn cell's shape is dataToLayout([time]).contentRect (upstream's call) AND the
independent recomputation from the recorded calendar (rect, cellSize, lineWidth,
range, orient, firstDay); an undrawn row's reason matches upstream's values;
cells are untransformed Rects with z2 1, the view group holds exactly the drawn
cells in data order and they paint in data order; el.style own keys == the item
visual; the display list is sorted by (zlevel, z, z2); the recorded label
placement equals calculateTextPosition (+ offset) on the cell rect; the
development build throws exactly for the cases marked prod and the production
build records every other case identically; anchors; every guard is ok; two
generations in the process give identical bytes.
*/
'use strict';
process.env.TZ = 'UTC';
if (new Date(2017, 0, 1).getTimezoneOffset() !== 0 || new Date(2017, 6, 1).getTimezoneOffset() !== 0
  || new Date(2017, 0, 1).getTime() !== Date.UTC(2017, 0, 1)) {
  console.log('FAILED: process.env.TZ = \'UTC\' did not take effect (offset ' + new Date(2017, 0, 1).getTimezoneOffset() + ')');
  process.exit(1);
}
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// the development build throws on a heatmap without a visualMap (HeatmapView.ts:111-115); the production build
// carries on. A case that trips it is recorded from the production build instead and says so (as heatmap-cartesian.js).
const PROD_PATH = DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js');
const PROD = require(PROD_PATH);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-heatmap-calendar.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;
const DAY = 86400000;

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

// ---------- zrender core/util.ts, verbatim in effect for plain JSON-born data ----------
const isArray = Array.isArray;
const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
function zrClone(source) {
  if (source == null || typeof source !== 'object') return source;
  if (isArray(source)) return source.map(zrClone);
  const r = {};
  for (const k in source) if (hasOwn(source, k) && k !== '__proto__') r[k] = zrClone(source[k]);
  return r;
}
function zrMerge(target, source, overwrite) {
  if (!isObject(source) || !isObject(target)) return overwrite ? zrClone(source) : target;
  for (const key in source) {
    if (hasOwn(source, key) && key !== '__proto__') {
      const t = target[key];
      const s = source[key];
      if (isObject(s) && isObject(t) && !isArray(s) && !isArray(t)) zrMerge(t, s, overwrite);
      else if (overwrite || !(key in target)) target[key] = zrClone(s);
    }
  }
  return target;
}
const retrieve2 = (a, b) => (a != null ? a : b);
// an option value as upstream holds it (JSON; undefined -> null) -- non-finite numbers are left to sanitize()
const json = v => (v === undefined ? null : zrClone(v));

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================

// HeatmapSeries.defaultOption (HeatmapSeries.ts:107-135); tokens.color.primary = '#3c3c41' (visual/tokens.ts)
const HM_DEFAULTS = {
  coordinateSystem: 'cartesian2d', z: 2, geoIndex: 0, blurSize: 30, pointSize: 20, maxOpacity: 1, minOpacity: 0,
  select: { itemStyle: { borderColor: '#3c3c41' } },
};
// the store dims: time + value, then one float dim per further element of the FIRST row's value (Source.ts
// determineSourceDimensions: getDataItemValue(data[0]).length), named value0, value1, ... -- the visualMap's default
// dimension is the LAST of them
const dataItemValue = raw => (isItemObject(raw) ? raw.value : raw);
function dimsOf(rows, mut) {
  const dims = ['time', 'value'];
  if (mut.dimsFixed || !rows.length) return dims;
  const v0 = dataItemValue(rows[0].raw);
  const n = (isArray(v0) && v0.length) || 1;
  for (let k = 2; k < n; k++) dims.push('value' + (k - 2));
  return dims;
}
// createDimensions.ts + sourceHelper.ts guessOrdinal for a dim with no declared type (every dim but time): the first
// up-to-5 rows decide -- a number-like value (finite Number(v), not '') -> float; a string other than '-' -> ORDINAL
// (the store then keeps the raw value: no ordinalMeta); null / undefined / '-' / a non-finite number -> look further;
// a row whose value is not an array -> float
function dimTypeOf(rows, k, mut) {
  if (k === 0) return 'time';
  if (mut.noOrdinalGuess) return 'float';
  for (let i = 0; i < rows.length && i < 5; i++) {
    const val = dataItemValue(rows[i].raw);
    if (!isArray(val)) return 'float';
    const v = val[k];
    const beStr = typeof v === 'string';
    if (v != null && isFinite(Number(v)) && v !== '') return 'float';
    if (beStr && v !== '-') return 'ordinal';
  }
  return 'float';
}
const PI = Math.PI;
const PI2 = PI * 2;
const MAXV = Number.MAX_VALUE;

// Model getShallow / get over [own, parent, ...]
function chainGet(levels, key) {
  let v;
  for (let i = 0; i < levels.length; i++) {
    const o = levels[i];
    v = o && typeof o === 'object' ? o[key] : undefined;
    if (v != null) return v;
  }
  return v;
}
const isItemObject = raw => isObject(raw) && !isArray(raw) && !(raw instanceof Date);

// ---- util/number.ts parseDate(...).getTime() and dataValueHelper.ts parseDataValue, under TZ = UTC ----
const TIME_REG = /^(?:(\d{4})(?:[-\/](\d{1,2})(?:[-\/](\d{1,2})(?:[T ](\d{1,2})(?::(\d{1,2})(?::(\d{1,2})(?:[.,](\d+))?)?)?(Z|[\+\-]\d\d:?\d\d)?)?)?)?)?$/;
function parseDateTime(v, mut) {
  if (typeof v === 'string') {
    const m = TIME_REG.exec(v);
    if (!m) return NaN;
    let hour = +m[4] || 0;
    let minute = +(m[5] || 0);
    if (m[8] && m[8].toUpperCase() !== 'Z') {
      hour -= +m[8].slice(0, 3);
      // upstream drops the offset's minutes; the mutation honours them
      if (mut.offsetMinutes) minute -= (m[8][0] === '-' ? -1 : 1) * +m[8].slice(-2);
    }
    // zone-less = local: new Date(y, m, d, ...) -- equal to Date.UTC here (TZ = UTC); a year < 100 does not occur
    return new Date(Date.UTC(+m[1], +(m[2] || 1) - 1, +m[3] || 1, hour, minute, +m[6] || 0, m[7] ? +m[7].substring(0, 3) : 0)).getTime();
  }
  if (v == null) return NaN;
  return new Date(Math.round(v)).getTime();
}
// the store: parseDataValue(value, {type: 'time'}) / {type: 'float'}
function storeTime(v, mut) {
  if (typeof v !== 'number' && v != null && v !== '-') v = parseDateTime(v, mut);
  return v == null || v === '' ? NaN : Number(v);
}
const storeFloat = v => (v == null || v === '' ? NaN : Number(v));

// ---- calendar-layout.js's civil-day transcription of Calendar.getDateInfo / dataToPoint / dataToLayout ----
const dnOf = t => Math.floor(t / DAY);
const weekday = dn => (((dn % 7) + 7) % 7 + 4) % 7;
const dayOf = (dn, fd) => Math.abs((weekday(dn) + 7 - fd) % 7);
function shrinkRect(r, delta) {
  // util/graphic.ts expandOrShrinkRect(rect, delta, shrink = true, noNegative = true), 4 equal deltas
  const o = { x: r.x, y: r.y, width: r.width, height: r.height };
  const d = -Math.max(0, delta);
  const one = (xy, wh) => {
    const deltaSum = d + d;
    const oldSize = o[wh];
    o[wh] += deltaSum;
    const minSize = Math.max(0, Math.min(0, oldSize));
    if (o[wh] < minSize) {
      o[wh] = minSize;
      o[xy] += (d >= 0 ? -d : d >= 0 ? oldSize + d : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * d / deltaSum : 0);
    } else {
      o[xy] -= d;
    }
  };
  one('x', 'width');
  one('y', 'height');
  return o;
}
// the cell of `time` on calendar `cal` -> {skip, shape}
function calendarCell(cal, time, mut) {
  const fd = mut.firstDayIgnored ? 0 : cal.firstDay;
  const S = dnOf(cal.startTime);
  const E = dnOf(cal.endTime);
  const fweek = dayOf(S, fd);
  // getDateInfo: parseDate(number) = new Date(Math.round(time))
  const t = mut.timeNoRound ? time : parseDateTime(time, mut);
  if (Number.isNaN(t)) return { skip: 'time', shape: null };
  if (!mut.clampOff) {
    if (!(t >= S * DAY)) return { skip: 'before', shape: null };
    if (!(t < E * DAY + DAY)) return { skip: 'after', shape: null };
  }
  const dn = mut.dayNearest ? Math.round(t / DAY) : dnOf(t);
  const nth = mut.noFweek ? Math.floor((dn - S) / 7) : Math.floor((dn - S + fweek) / 7);
  const day = dayOf(dn, fd);
  const horiz = mut.orientIgnored ? true : cal.orient === 'horizontal';
  const { rect, sw, sh } = cal;
  const c = horiz ? [rect.x + nth * sw + sw / 2, rect.y + day * sh + sh / 2] : [rect.x + day * sw + sw / 2, rect.y + nth * sh + sh / 2];
  const r = { x: c[0] - sw / 2, y: c[1] - sh / 2, width: sw, height: sh };
  if (mut.rectNotContent) return { skip: null, shape: r };
  return { skip: null, shape: shrinkRect(r, mut.fullInset ? cal.lw : cal.lw / 2) };
}

// ---- zrender PathProxy (a recorder) + normalizeArcAngles (core/PathProxy.ts) ----
const CMD = { M: 1, L: 2, C: 3, Q: 4, A: 5, Z: 6, R: 7 };
const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };
const CMD_ARGS = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 };
function decode(data) {
  const out = [];
  for (let i = 0; i < data.length;) {
    const c = data[i++];
    must(CMD_NAME[c], 'an unknown path command ' + c);
    const n = CMD_ARGS[c];
    out.push({ cmd: CMD_NAME[c], args: Array.prototype.slice.call(data, i, i + n) });
    i += n;
  }
  return out;
}
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
function roundRectPath(ctx, shape) {
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
// zrender graphic/shape/Rect.ts buildPath (subPixelOptimize is false on a heatmap cell)
function rectPath(shape) {
  const ctx = new Proxy();
  if (!shape.r) ctx.rect(shape.x, shape.y, shape.width, shape.height);
  else roundRectPath(ctx, shape);
  return ctx.data;
}

// ---- zrender core/bbox.ts, PathProxy.getBoundingRect over M / L / A / R / Z ----
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
const transformOf = t => (needLocalTransform({ rotation: t.rotation, x: t.x, y: t.y, scaleX: 1, scaleY: 1 })
  ? localTransform({ x: t.x, y: t.y, rotation: t.rotation, originX: t.originX, originY: t.originY, scaleX: 1, scaleY: 1 }) : null);

// util/format.ts formatTpl for one params object (String.prototype.replace: FIRST occurrence only; a value array
// replaces as String(array) = 'date,v')
const TPL_VAR_ALIAS = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
function formatTpl(tpl, params, mut) {
  const $vars = ['seriesName', 'name', 'value'];
  const rep = (s, from, to) => (mut.tplReplaceAll ? s.split(from).join(String(to)) : s.replace(from, to));
  for (let i = 0; i < $vars.length; i++) {
    const alias = TPL_VAR_ALIAS[i];
    tpl = rep(tpl, '{' + alias + '}', '{' + alias + '0}');
  }
  for (let k = 0; k < $vars.length; k++) tpl = rep(tpl, '{' + TPL_VAR_ALIAS[k] + '0}', params[$vars[k]]);
  return tpl;
}
// dataFormat.ts the {@dim} / {@[n]} pass after formatTpl, retrieveRawValue(data, idx, dim) with
// SeriesData.getDimensionIndex (a number or a number-like string that is not a dim name -> that index; a dim name ->
// its index; anything else -> -1)
function dimTemplates(str, rawValue, DIMS, mut) {
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
// util/model.ts convertOptionIdName
function convertOptionIdName(v, def) {
  if (v == null) return def;
  return typeof v === 'string' ? v : typeof v === 'number' ? v + '' : def;
}
// zr Text makeFont / parseFontSize, normalizeStyle
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
function normAlign(a) {
  if (a === 'middle') a = 'center';
  return a == null || { left: 1, right: 1, center: 1 }[a] ? a : 'left';
}
function normVAlign(a) {
  if (a === 'center') a = 'middle';
  return a == null || { top: 1, bottom: 1, middle: 1 }[a] ? a : 'top';
}
// zrender tool/color lum
function lum(c, backgroundLum) {
  const arr = echarts.color.parse(c);
  return arr ? (0.299 * arr[0] + 0.587 * arr[1] + 0.114 * arr[2]) * arr[3] / 255 + (1 - arr[3]) * backgroundLum : 0;
}
// Element.getOutsideStroke
function outsideStroke(bg, isDark) {
  let arr = typeof bg === 'string' && echarts.color.parse(bg);
  if (!arr) arr = [255, 255, 255, 1];
  const alpha = arr[3];
  for (let i = 0; i < 3; i++) arr[i] = arr[i] * alpha + (isDark ? 0 : 255) * (1 - alpha);
  arr[3] = 1;
  return echarts.color.stringify(arr, 'rgba');
}
// Path.getInsideTextFill / getInsideTextStroke
function insideTextFill(pathFill) {
  if (pathFill !== 'none') {
    if (typeof pathFill === 'string') {
      const fillLum = lum(pathFill, 0);
      if (fillLum > 0.5) return '#333';
      if (fillLum > 0.2) return '#eee';
      return '#ccc';
    } else if (pathFill) {
      return '#ccc';
    }
  }
  return '#333';
}
function insideTextStroke(pathFill, textFill, isDark) {
  if (typeof pathFill === 'string') {
    const isDarkMode = !!isDark;
    const isDarkLabel = lum(textFill, 0) < 0.4;
    if (isDarkMode === isDarkLabel) return pathFill;
  }
  return undefined;
}
// zr contain/text.ts parsePercent + calculateTextPosition
function zrParsePercent(value, maxValue) {
  if (typeof value === 'string') {
    if (value.lastIndexOf('%') >= 0) return parseFloat(value) / 100 * maxValue;
    return parseFloat(value);
  }
  return value;
}
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

const ITEM_STYLE_KEYS = [['fill', 'color'], ['stroke', 'borderColor'], ['lineWidth', 'borderWidth'], ['opacity', 'opacity'],
  ['shadowBlur', 'shadowBlur'], ['shadowOffsetX', 'shadowOffsetX'], ['shadowOffsetY', 'shadowOffsetY'], ['shadowColor', 'shadowColor'],
  ['lineDash', 'borderType'], ['lineDashOffset', 'borderDashOffset'], ['lineCap', 'borderCap'], ['lineJoin', 'borderJoin'], ['miterLimit', 'borderMiterLimit']];
const TEXT_PROPS_BOX = ['padding', 'borderWidth', 'borderRadius', 'borderDashOffset', 'backgroundColor', 'borderColor', 'shadowColor', 'shadowBlur', 'shadowOffsetX', 'shadowOffsetY'];
const DEFAULT_PATH_STYLE = { fill: '#000', stroke: null, strokePercent: 1, fillOpacity: 1, strokeOpacity: 1, lineDashOffset: 0, lineWidth: 1,
  lineCap: 'butt', miterLimit: 10, strokeNoScale: false, strokeFirst: false,
  shadowBlur: 0, shadowOffsetX: 0, shadowOffsetY: 0, shadowColor: '#000', opacity: 1, blend: 'source-over' };
// a style's OWN keys, sorted; an own key holding undefined is recorded null (it SHADOWS the zrender default: an
// undefined fill is no fill at all, not '#000')
function ownStyle(s) {
  const r = {};
  for (const k of Object.keys(s).sort()) {
    must(!(typeof s[k] === 'number' && Number.isNaN(s[k])), 'a NaN style value ' + k);
    r[k] = s[k] === undefined ? null : zrClone(s[k]);
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
// the compact forms of the rect record (shared by upstream and the transcription)
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const sameRect = (a, b) => Object.is(a.x, b.x) && Object.is(a.y, b.y) && Object.is(a.width, b.width) && Object.is(a.height, b.height);
function compactRect(shape, pdata, bbox, rect) {
  const plain = pdata.length === 5 && pdata[0] === CMD.R && Object.is(pdata[1], shape.x) && Object.is(pdata[2], shape.y)
    && Object.is(pdata[3], shape.width) && Object.is(pdata[4], shape.height);
  return { path: plain ? null : decode(pdata), bbox: sameRect(bbox, shape) ? null : rect4(bbox), rect: sameRect(rect, bbox) ? null : rect4(rect) };
}

// one heatmap series' picture. inp: {seriesOpt (merged over HM_DEFAULTS), color, seriesName, textStyle, ground,
// cals [{rect, sw, sh, lw, orient, firstDay, startTime, endTime}], calIndex, rows [{raw, vm: null | {wrote}}]}
function transcribe(inp, mut) {
  const S = inp.seriesOpt;
  const z = mut.zDefault0 ? 0 : S.z || 0;
  const zlevel = S.zlevel || 0;
  const silent = mut.silentIgnored ? false : !!S.silent;
  const gts = inp.textStyle || {};
  const cal = inp.cals[mut.calendarZero ? 0 : inp.calIndex];
  // seriesStyleTask: the series itemStyle (own keys), fill = the palette colour when falsy -- the palette branch
  // re-assigns fill AND stroke (style.ts): an unset stroke becomes an OWN undefined key
  const seriesStyle = mapItemStyle(S.itemStyle);
  must(typeof seriesStyle.fill !== 'function' && seriesStyle.fill !== 'auto' && seriesStyle.stroke !== 'auto', 'the transcription does no colour callbacks / auto');
  if (!seriesStyle.fill) {
    seriesStyle.fill = inp.color;
    seriesStyle.stroke = seriesStyle.stroke; // eslint-disable-line no-self-assign
  }
  const dims = dimsOf(inp.rows, mut);
  const types = dims.map((_, k) => dimTypeOf(inp.rows, k, mut));
  const cellZ2 = mut.z2Zero ? 0 : 1;
  let maxZ2 = -Infinity;
  const rows = inp.rows.map(IT => {
    const raw = IT.raw;
    const isObj = isItemObject(raw);
    const rawValue = isObj ? raw.value : raw;
    const time = storeTime(isArray(rawValue) ? rawValue[0] : undefined, mut);
    // parseDataValue: an ordinal dim keeps the raw value (a string, null, undefined ...)
    const rv = isArray(rawValue) ? rawValue[1] : undefined;
    const value = types[1] === 'ordinal' ? rv : storeFloat(rv);
    // the visual style: series style, then visualMap (stage 4000), then the item itemStyle (dataStyleTask, 4500)
    const style = Object.assign({}, seriesStyle);
    const itemStyle = isObj ? mapItemStyle(raw.itemStyle) : {};
    const applyVm = () => {
      if (!IT.vm || mut.vmIgnored) return;
      if ('color' in IT.vm.wrote) style.fill = IT.vm.wrote.color;
      if ('opacity' in IT.vm.wrote) style.opacity = IT.vm.wrote.opacity;
    };
    if (mut.itemUnderVm) { Object.assign(style, itemStyle); applyVm(); } else { applyVm(); Object.assign(style, itemStyle); }
    // SeriesData.getName: the item's name (convertOptionIdName), else '' (no category dim on a calendar)
    let name = isObj && !mut.nameNoItem ? convertOptionIdName(raw.name, null) : null;
    if (name == null) name = '';
    const out = { time, value, name, style: ownStyle(style) };
    // skip: an empty value, then a NaN contentRect (HeatmapView.ts calendar branch)
    let skip = null;
    let shape = null;
    if (isNaN(value) && !mut.nanValueDrawn) skip = 'value';
    else {
      const c = calendarCell(cal, time, mut);
      skip = c.skip;
      shape = c.shape;
    }
    out.drawn = skip == null;
    out.skip = skip;
    if (skip != null) {
      out.rect = out.label = null;
      return out;
    }
    const r = mut.radiusSeriesOnly ? chainGet([S.itemStyle], 'borderRadius') : chainGet([isObj ? raw.itemStyle : undefined, S.itemStyle], 'borderRadius');
    const sh = { x: shape.x, y: shape.y, width: shape.width, height: shape.height, r };
    const pdata = rectPath(sh);
    const st = Object.assign(Object.create(DEFAULT_PATH_STYLE), style);
    const bbox = pathBBox(pdata);
    const hasStroke = !(st.stroke == null || st.stroke === 'none' || !(st.lineWidth > 0));
    const hasFill = st.fill != null && st.fill !== 'none';
    // Path.getBoundingRect: the stroke grows the rect (no transform: lineScale 1)
    let rect = bbox;
    if (hasStroke && pdata.length > 0 && !mut.rectNoStroke) {
      rect = Object.assign({}, bbox);
      let w = st.lineWidth;
      if (!hasFill) w = Math.max(w, 5);
      rect.width += w;
      rect.height += w;
      rect.x -= w / 2;
      rect.y -= w / 2;
    }
    maxZ2 = Math.max(cellZ2, maxZ2); // util/graphic.ts traverseUpdateZ over the view group: the running max z2
    out.rect = Object.assign({ shape: rect4(sh), r: json(r) }, compactRect(sh, pdata, bbox, rect), { z, z2: cellZ2, zlevel, silent });
    // ----- the label (HeatmapView.ts setLabelStyle, labelStyle.ts, zr Element.updateInnerText, Text) -----
    const LB = [isObj ? raw.label : undefined, S.label];
    const show = chainGet(LB, 'show');
    if (!show) {
      out.label = null;
      return out;
    }
    let formatter = chainGet(LB, 'formatter');
    let str;
    if (typeof formatter === 'string') {
      str = dimTemplates(formatTpl(formatter, { seriesName: inp.seriesName, name, value: rawValue }, mut), rawValue, dims, mut);
    } else {
      must(formatter == null, 'the transcription does not call formatter functions');
      str = '-';
      if (mut.defaultTextValue) str = value + '';
      else if (rawValue && rawValue[2] != null) str = rawValue[2] + '';
    }
    // createTextStyle(normal, isAttached = true), no inheritColor, defaultOpacity = the visual style's opacity
    const ts = {};
    let fc = chainGet(LB, 'color');
    let sc = chainGet(LB, 'textBorderColor');
    let opacity = retrieve2(chainGet(LB, 'opacity'), gts.opacity);
    if (fc === 'inherit' || fc === 'auto') fc = null;
    if (sc === 'inherit' || sc === 'auto') sc = null;
    if (fc != null) ts.fill = fc;
    if (sc != null) ts.stroke = sc;
    const tbw = retrieve2(chainGet(LB, 'textBorderWidth'), gts.textBorderWidth);
    if (tbw != null) ts.lineWidth = tbw;
    if (opacity == null && !mut.labelOpacityOwn) opacity = style.opacity;
    if (opacity != null) ts.opacity = opacity;
    for (const k of ['fontStyle', 'fontWeight', 'fontSize', 'fontFamily']) {
      const x2 = retrieve2(chainGet(LB, k), gts[k]);
      if (x2 != null) ts[k] = x2;
    }
    let rawAlign = chainGet(LB, 'align');
    let rawVAlign = chainGet(LB, 'verticalAlign');
    if (rawVAlign == null) rawVAlign = chainGet(LB, 'baseline');
    for (const k of TEXT_PROPS_BOX) {
      const x2 = chainGet(LB, k);
      if (x2 != null) ts[k] = x2;
    }
    for (const o of LB) must(!(o && typeof o === 'object' && o.rich), 'the transcription does not do rich labels');
    must(chainGet(LB, 'textBorderType') == null && chainGet(LB, 'textBorderDashOffset') == null, 'the transcription does not do text border dashes');
    const authorAlign = normAlign(rawAlign);
    const authorVAlign = normVAlign(rawVAlign);
    // createTextConfig: no defaultOutsidePosition
    let position = chainGet(LB, 'position') || (mut.positionDefaultTop ? 'top' : 'inside');
    if (position === 'outside') position = 'top';
    const distance = retrieve2(chainGet(LB, 'distance'), 5);
    const labelOffset = chainGet(LB, 'offset');
    let labelRotate = chainGet(LB, 'rotate');
    if (labelRotate != null) labelRotate *= Math.PI / 180;
    const outsideFill = chainGet(LB, 'color') === 'inherit' ? null : 'auto';
    // updateInnerText on the cell's bounding rect (no transform anywhere)
    const calc = calculateTextPosition(position, distance, rect);
    const inner = { x: calc.x, y: calc.y, rotation: 0, originX: 0, originY: 0 };
    if (labelRotate != null) inner.rotation = labelRotate;
    if (labelOffset) {
      inner.x += labelOffset[0];
      inner.y += labelOffset[1];
      inner.originX = -labelOffset[0];
      inner.originY = -labelOffset[1];
    }
    // the ink: inside needs a fill
    const isInside = !mut.insideAsOutside && typeof position === 'string' && position.indexOf('inside') >= 0 && hasFill;
    let defFill;
    let defStroke;
    const isDark = inp.ground.isDark;
    if (isInside) {
      defFill = insideTextFill(st.fill);
      defStroke = insideTextStroke(st.fill, defFill, isDark);
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
      const bgDrawn = !!ts.backgroundColor;
      let dlw = 0;
      let tsk;
      if ('stroke' in ts) tsk = ts.stroke;
      else if (!bgDrawn && useDefaultFill) { dlw = 2; tsk = defStroke; } else tsk = null;
      const fillP = tf == null || tf === 'none' ? null : tf;
      const strokeP = tsk == null || tsk === 'transparent' || tsk === 'none' ? null : tsk;
      ink = { fill: fillP, stroke: strokeP, lineWidth: strokeP ? (ts.lineWidth || dlw) : null, opacity: retrieve2(ts.opacity, 1) };
    }
    const labelZ2 = mut.labelZ2Fixed ? 2 : isFinite(maxZ2) ? maxZ2 + 2 : 0;
    out.label = { text: str == null ? null : String(str), lines, position: json(position), distance,
      inner, transform: transformOf(inner),
      align: authorAlign || calc.align || 'left', verticalAlign: authorVAlign || calc.verticalAlign || 'top',
      authorAlign: authorAlign == null ? null : authorAlign, authorVerticalAlign: authorVAlign == null ? null : authorVAlign,
      inside: isInside,
      font: makeFont(ts), fontSize: json(ts.fontSize), fontWeight: json(ts.fontWeight), fontStyle: json(ts.fontStyle), fontFamily: json(ts.fontFamily),
      style: { fill: 'fill' in ts ? ts.fill : null, stroke: 'stroke' in ts ? ts.stroke : null, lineWidth: 'lineWidth' in ts ? ts.lineWidth : null,
        opacity: retrieve2(ts.opacity, 1), backgroundColor: json(ts.backgroundColor) },
      inkDefault: { fill: defFill, stroke: defStroke == null ? null : defStroke, autoStroke: true,
        align: calc.align == null ? null : calc.align, verticalAlign: calc.verticalAlign == null ? null : calc.verticalAlign }, ink,
      z, z2: labelZ2, zlevel, silent: !!chainGet(LB, 'silent') };
    return out;
  });
  const block = { dimensions: dims, dimensionTypes: types, z, zlevel, silent, seriesStyle: ownStyle(seriesStyle) };
  return { block, rows };
}

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const calArray = o => (o.calendar == null ? [] : isArray(o.calendar) ? o.calendar : [o.calendar]);
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  must(Array.isArray(el.path.data), 'a path proxy was made static');
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};
const pad2 = n => (n < 10 ? '0' + n : '' + n);
function fmtDn(dn) {
  const d = new Date(dn * DAY);
  return d.getUTCFullYear() + '-' + pad2(d.getUTCMonth() + 1) + '-' + pad2(d.getUTCDate());
}

function readLabel(el, displayIndex) {
  const t = el.getTextContent();
  if (!t || t.ignore) return null;
  const s = t.style;
  must(!s.rich, 'a rich heatmap label');
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  const txt = s.text == null ? null : String(s.text);
  must(kids.every(k => k.type === 'tspan' || (k.type === 'rect' && s.backgroundColor)), 'a plain label with children ' + kids.map(k => k.type).join());
  must((spans.length >= 1) === (txt != null && txt !== ''), 'a label TSpan / text mismatch');
  must(t.x === 0 && t.y === 0 && t.rotation === 0 && t.originX === 0 && t.originY === 0 && t.scaleX === 1 && t.scaleY === 1, 'a label Text with its own transform');
  let ink = null;
  if (spans.length) {
    const inks = spans.map(sp => {
      const ss = sp.style;
      must(ss.font === s.font, 'the TSpan font differs from the label font');
      return { fill: ss.fill == null ? null : ss.fill, stroke: ss.stroke || null, lineWidth: ss.stroke ? ss.lineWidth : null, opacity: ss.opacity };
    });
    must(inks.every(k => JSON.stringify(k) === JSON.stringify(inks[0])), 'TSpans with different inks');
    ink = inks[0];
  }
  const it = t.innerTransformable;
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  const tc = el.textConfig;
  const position = tc.position;
  const inside = typeof position === 'string' && position.indexOf('inside') >= 0 && el.hasFill();
  const p = spans.length ? displayIndex.get(spans[0]) : undefined;
  return { text: txt, lines: spans.length, position: json(position), distance: tc.distance,
    inner: { x: it.x, y: it.y, rotation: it.rotation, originX: it.originX, originY: it.originY }, transform: t.transform ? Array.from(t.transform).slice(0, 6) : null,
    align: s.align || ds.align || 'left', verticalAlign: s.verticalAlign || ds.verticalAlign || 'top',
    authorAlign: s.align == null ? null : s.align, authorVerticalAlign: s.verticalAlign == null ? null : s.verticalAlign,
    inside,
    font: s.font, fontSize: json(s.fontSize), fontWeight: json(s.fontWeight), fontStyle: json(s.fontStyle), fontFamily: json(s.fontFamily),
    style: { fill: has('fill') ? s.fill : null, stroke: has('stroke') ? s.stroke : null, lineWidth: has('lineWidth') ? s.lineWidth : null,
      opacity: s.opacity, backgroundColor: json(s.backgroundColor) },
    inkDefault: { fill: ds.fill, stroke: ds.stroke == null ? null : ds.stroke, autoStroke: ds.autoStroke,
      align: ds.align == null ? null : ds.align, verticalAlign: ds.verticalAlign == null ? null : ds.verticalAlign }, ink,
    tspans: spans.map(sp => ({ text: sp.style.text, x: sp.style.x, y: sp.style.y, textAlign: sp.style.textAlign, textBaseline: sp.style.textBaseline })),
    z: t.z, z2: t.z2, zlevel: t.zlevel, silent: !!t.silent, paint: p === undefined ? null : p };
}

// visualSolution.incrementalApplyVisual for one row, run on upstream's own visualMap models and mappings: the
// visuals every targeting visualMap WRITES (component order), each seeded with what the row holds so far
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
      rec.push({ index: vm.componentIndex, value: null, state: null, skipped: true });
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
    rec.push({ index: vm.componentIndex, value, state, skipped: false });
  }
  return { vms: rec, wrote };
}
function vmRec(v) {
  if (!v) return null;
  const w = v.wrote;
  return { vms: v.vms, color: 'color' in w ? json(w.color) : null, colorWritten: 'color' in w,
    opacity: 'opacity' in w ? json(w.opacity) : null, opacityWritten: 'opacity' in w };
}

// the calendar record + the transcription's calendar input
function readCalendar(cm, ci, userCal) {
  const cs = cm.coordinateSystem;
  const r = cs.getRect();
  const ri = cs.getRangeInfo();
  const rec = { index: ci, id: userCal && userCal.id != null ? userCal.id : null, rect: rect4(r), cellSize: [cs.getCellWidth(), cs.getCellHeight()],
    lineWidth: cs._lineWidth, orient: cs.getOrient(), firstDay: cs.getFirstDayOfWeek(), range: ri.range.slice(),
    startTime: ri.start.time, endTime: ri.end.time, fweek: ri.fweek, lweek: ri.lweek, weeks: ri.weeks, allDay: ri.allDay,
    z: json(cm.get('z')), zlevel: json(cm.get('zlevel')), splitLine: !!cm.get(['splitLine', 'show']) };
  const inp = { rect: rect4(r), sw: rec.cellSize[0], sh: rec.cellSize[1], lw: rec.lineWidth, orient: rec.orient, firstDay: rec.firstDay,
    startTime: ri.start.time, endTime: ri.end.time };
  return { rec, inp, cs, cm };
}

// HeatmapView's calendar branch on upstream's values: the FIRST failing test, null = drawn
function skipOf(cs, time, value) {
  if (isNaN(value)) return 'value';
  const lay = cs.dataToLayout([time]);
  const sh = lay.contentRect || lay.rect;
  if (!Number.isNaN(sh.x) && !Number.isNaN(sh.y)) return null;
  const di = cs.getDateInfo(time);
  if (Number.isNaN(di.time)) return 'time';
  const ri = cs.getRangeInfo();
  return di.time < ri.start.time ? 'before' : 'after';
}

// the independent recomputation of a cell from the RECORDED calendar (no mutation switches, no shared helper but
// the date parse): what the task names "recompute the cell rect from the calendar"
function cellFromCalendarRecord(cal, time) {
  const t = new Date(Math.round(time)).getTime();
  if (!(t >= cal.startTime && t < cal.endTime + DAY)) return null;
  const dn = Math.floor(t / DAY);
  const S = Math.floor(cal.startTime / DAY);
  const wd = d => ((d % 7) + 7 + 4) % 7; // 1970-01-01 is a Thursday
  const row = d => Math.abs((wd(d) + 7 - cal.firstDay) % 7);
  const nth = Math.floor((dn - S + row(S)) / 7);
  must(row(S) === cal.fweek, 'the recomputed fweek differs from upstream');
  const [sw, sh] = cal.cellSize;
  const horiz = cal.orient === 'horizontal';
  const cx = horiz ? cal.rect.x + nth * sw + sw / 2 : cal.rect.x + row(dn) * sw + sw / 2;
  const cy = horiz ? cal.rect.y + row(dn) * sh + sh / 2 : cal.rect.y + nth * sh + sh / 2;
  const h = cal.lineWidth / 2;
  const r = { x: cx - sw / 2, y: cy - sh / 2, width: sw, height: sh };
  const one = (xy, wh) => {
    const old = r[wh];
    r[wh] = old + (-h + -h);
    if (r[wh] < 0) { r[wh] = 0; r[xy] = r[xy] + old / 2; } else r[xy] = r[xy] - -h;
  };
  one('x', 'width');
  one('y', 'height');
  return r;
}

// every row of one heatmap series
function readSeries(chart, sm, cal, displayIndex) {
  const ec = chart.getModel();
  const data = sm.getData();
  const view = chart.getViewOfSeriesModel(sm);
  const group = view.group;
  for (let p = group; p; p = p.parent) must(!p.transform || p.transform.join() === '1,0,0,1,0,0', 'a transformed ancestor');
  const cs = sm.coordinateSystem;
  must(cs && cs.type === 'calendar' && cs === cal.cs, 'not on its calendar');
  must(data.dimensions[0] === 'time' && data.dimensions[1] === 'value' && data.dimensions.slice(2).every((d, k) => d === 'value' + k)
    && data.mapDimension('time') === 'time' && data.mapDimension('value') === 'value' && data.getDimensionInfo('time').type === 'time'
    && data.dimensions.slice(1).every(d => ['float', 'ordinal'].includes(data.getDimensionInfo(d).type) && !data.getDimensionInfo(d).ordinalMeta),
  'heatmap dims ' + JSON.stringify(data.dimensions));
  const rows = [];
  const inputs = [];
  const drawn = [];
  for (let i = 0; i < data.count(); i++) {
    must(data.getRawIndex(i) === i, 'a filtered calendar series');
    const raw = data.getRawDataItem(i);
    const time = data.get('time', i);
    const value = data.get('value', i);
    const vm = vmOf(ec, sm, data, i);
    inputs.push({ raw: zrClone(raw), vm });
    const el = data.getItemGraphicEl(i);
    const visual = data.getItemVisual(i, 'style');
    const row = { index: i, raw: json(raw), time, value, name: data.getName(i), vm: vmRec(vm), style: ownStyle(visual), drawn: !!el, skip: skipOf(cs, time, value) };
    must((row.skip == null) === !!el, 'row ' + i + ': drawn is not the HeatmapView skip test (' + row.skip + ')');
    if (!el) {
      if (row.skip !== 'value') must(cellFromCalendarRecord(cal.rec, time) === null, 'row ' + i + ': skipped (' + row.skip + ') but the recomputation has a cell');
      row.rect = row.label = null;
      rows.push(row);
      continue;
    }
    drawn.push(el);
    must(el.type === 'rect' && !el.transform && !el.needLocalTransform() && !el.subPixelOptimize, 'row ' + i + ' is not a plain untransformed Rect');
    // (zrender adds an own `blend: null` to the cell style: the default 'source-over' either way)
    const elOwn = Object.keys(el.style).filter(k => !(k === 'blend' && el.style.blend == null));
    must(el.style !== visual && elOwn.join() === Object.keys(visual).join() && elOwn.every(k => Object.is(el.style[k], visual[k])),
      'row ' + i + ': the cell style own keys are not the item visual');
    const sh = el.shape;
    // the cell is exactly upstream's dataToLayout([time]).contentRect ...
    const lay = cs.dataToLayout([time]);
    must(sameRect(sh, lay.contentRect), 'row ' + i + ': the cell is not dataToLayout(time).contentRect');
    // ... and the independent recomputation from the recorded calendar
    const re = cellFromCalendarRecord(cal.rec, time);
    must(re && sameRect(sh, re), 'row ' + i + ': the cell ' + JSON.stringify(rect4(sh)) + ' is not the recomputation from the calendar ' + JSON.stringify(re));
    const pdata = pathOf(el);
    const bb = el.path.getBoundingRect();
    const rect = el.getBoundingRect();
    const p = displayIndex.get(el);
    must(p !== undefined, 'row ' + i + ': the cell is not in the display list');
    row.rect = Object.assign({ shape: rect4(sh), r: json(sh.r) }, compactRect(sh, pdata, bb, rect),
      { z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.isSilent(), paint: p });
    must(el.z2 === 1, 'row ' + i + ': cell z2 ' + el.z2);
    row.label = readLabel(el, displayIndex);
    if (row.label) {
      const t = el.getTextContent();
      const tc = el.textConfig;
      const c = calculateTextPosition(tc.position, tc.distance, el.getBoundingRect());
      const off = tc.offset || [0, 0];
      must(Object.is(t.innerTransformable.x, c.x + off[0]) && Object.is(t.innerTransformable.y, c.y + off[1]), 'the label placement is not calculateTextPosition on the rect at row ' + i);
    }
    rows.push(row);
  }
  must(group.childrenRef().length === drawn.length && group.childrenRef().every((c, k) => c === drawn[k]), 'the view group children are not the drawn cells in order');
  for (let k = 1; k < drawn.length; k++) must(displayIndex.get(drawn[k]) > displayIndex.get(drawn[k - 1]), 'the cells do not paint in data order');
  const ss = data.getVisual('style');
  const block = { dimensions: data.dimensions.slice(), dimensionTypes: data.dimensions.map(d => data.getDimensionInfo(d).type), z: sm.get('z') || 0, zlevel: sm.get('zlevel') || 0, silent: !!group.silent, seriesStyle: ownStyle(ss) };
  return { block, rows, inputs, hasItemOption: !!data.hasItemOption, count: data.count() };
}

// the display list, run-length encoded by owner
function paintRuns(chart, list, cals) {
  const ec = chart.getModel();
  const owners = new Map();
  ec.eachComponent((mainType, cm) => {
    const v = chart.getViewOfComponentModel(cm);
    if (v && v.group) owners.set(v.group, { owner: mainType === 'calendar' ? 'calendar' : 'component', index: cm.componentIndex, type: mainType === 'calendar' ? null : mainType, cm });
  });
  ec.eachSeries(sm => {
    const v = chart.getViewOfSeriesModel(sm);
    if (v && v.group) owners.set(v.group, { owner: 'series', index: sm.seriesIndex, type: sm.subType });
  });
  // the calendar groups: rects, then polylines (the last two are the edges when the split line shows), then texts
  // (year when shown, months, then the 7 week labels when shown) -- as calendar-layout.js's group order
  const calGroup = new Map();
  for (const c of cals) {
    const kids = chart.getViewOfComponentModel(c.cm).group.children();
    const polys = kids.filter(k => k.type === 'polyline');
    const texts = kids.filter(k => k.type === 'text');
    polys.forEach((p, i) => calGroup.set(p, c.rec.splitLine && i >= polys.length - 2 ? 'edge' : 'split'));
    const yearShown = !!c.cm.get(['yearLabel', 'show']);
    const weekShown = !!c.cm.get(['dayLabel', 'show']);
    texts.forEach((t, i) => calGroup.set(t, yearShown && i === 0 ? 'year' : weekShown && i >= texts.length - 7 ? 'week' : 'month'));
    kids.filter(k => k.type === 'rect').forEach(r => calGroup.set(r, 'day'));
    must(kids.every(k => calGroup.has(k)), 'calendar ' + c.rec.index + ': an unclassified element');
  }
  const runs = [];
  let prev = null;
  list.forEach((el, i) => {
    // climb: a TSpan's parent is its Text; a label Text's __hostTarget is its host element
    let x = el;
    let viaHost = false;
    let calKid = null;
    let o = null;
    while (x) {
      if (owners.has(x)) { o = owners.get(x); break; }
      if (calGroup.has(x)) calKid = x;
      if (x.parent) x = x.parent;
      else if (x.__hostTarget) { viaHost = true; x = x.__hostTarget; } else x = null;
    }
    let rec;
    if (!o) rec = { owner: 'other', index: null, type: null, group: null };
    else if (o.owner === 'calendar') {
      must(calKid && !viaHost, 'a calendar element outside the classified children');
      rec = { owner: 'calendar', index: o.index, type: null, group: calGroup.get(calKid) };
    } else if (o.owner === 'series') {
      rec = { owner: 'series', index: o.index, type: o.type, group: viaHost ? 'label' : o.type === 'heatmap' ? 'cell' : 'mark' };
    } else rec = { owner: 'component', index: o.index, type: o.type, group: viaHost ? 'label' : 'mark' };
    Object.assign(rec, { zlevel: el.zlevel, z: el.z, z2: el.z2 });
    // zrender's display list is sorted by (zlevel, z, z2), ties in insertion order
    if (prev) must(prev.zlevel < el.zlevel || (prev.zlevel === el.zlevel && (prev.z < el.z || (prev.z === el.z && prev.z2 <= el.z2))), 'the display list is not sorted at ' + i);
    prev = el;
    const last = runs[runs.length - 1];
    if (last && ['owner', 'index', 'type', 'group', 'zlevel', 'z', 'z2'].every(k => last[k] === rec[k])) last.n++;
    else runs.push(Object.assign(rec, { n: 1 }));
  });
  return runs;
}

function runChart(E, option, fn) {
  rngState = SEED;
  const chart = E.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(option);
    chart.getZr().storage.getDisplayList(true);
    return fn(chart);
  } finally {
    chart.dispose();
  }
}

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));

function recordWith(E, def, optionText, side) {
  const input = JSON.parse(optionText);
  return runChart(E, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const list = zr.storage.getDisplayList(true);
    const displayIndex = new Map();
    list.forEach((el, i) => displayIndex.set(el, i));
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const cals = [];
    ec.eachComponent('calendar', (cm, ci) => cals.push(readCalendar(cm, ci, calArray(input)[ci])));
    must(cals.length === calArray(input).length, 'calendar count ' + cals.length);
    const calIndexOf = cs => {
      const k = cals.findIndex(c => c.cs === cs);
      return k < 0 ? null : k;
    };
    let nHeatmaps = 0;
    const series = seriesArray(input).map((opt, si) => {
      const sm = ec.getSeriesByIndex(si);
      must(sm && sm.subType === opt.type, 'series ' + si + ' is not a ' + opt.type);
      const calIndex = calIndexOf(sm.coordinateSystem);
      const base = { seriesIndex: si, type: opt.type, name: opt.name == null ? null : String(opt.name), recorded: opt.type === 'heatmap', calendarIndex: calIndex };
      if (opt.type !== 'heatmap') return base;
      nHeatmaps++;
      must(calIndex != null, 'a heatmap not on a calendar');
      const data = sm.getData();
      const filtered = ec.isSeriesFiltered(sm);
      const c = data.getVisual('style')[data.getVisual('drawType')];
      const sr = Object.assign(base, { filtered, color: json(c), seriesName: opt.name == null ? null : sm.name, heatmap: null });
      if (filtered) return sr;
      const r = readSeries(chart, sm, cals[calIndex], displayIndex);
      // the series option as upstream holds it = the option as fed merged over HM_DEFAULTS (checked on the keys read)
      const seriesOpt = zrMerge(zrClone(opt), HM_DEFAULTS);
      for (const k of ['itemStyle', 'label', 'z', 'zlevel', 'silent']) {
        must(JSON.stringify(json(sm.option[k]) || {}) === JSON.stringify(json(seriesOpt[k]) || {}), 'the series option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(sm.option[k]));
      }
      const inp = { seriesOpt, color: c, seriesName: sr.seriesName, textStyle: ec.option.textStyle, ground, cals: cals.map(k => k.inp), calIndex, rows: r.inputs };
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
      must(r.count === (opt.data || []).length, 'a row count that is not the option data length');
      sr.heatmap = Object.assign({}, r.block, { count: r.count, hasItemOption: r.hasItemOption, rows: r.rows });
      return sr;
    });
    must(nHeatmaps > 0, 'no heatmap series');
    const runs = paintRuns(chart, list, cals);
    return { ground, textStyle, calendars: cals.map(c => c.rec), paintRuns: runs, series };
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
    must(JSON.stringify(sanitize(p)) === JSON.stringify(sanitize(base)), 'the production build records differently');
  }
  Object.assign(side, local);
  return Object.assign({ id: def.id, note: def.note, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    productionBuild, devError }, base);
}

// ============================================================================
// The cases
// ============================================================================
const VM = { min: 0, max: 10, show: false };
const hmc = (calendar, data, seriesExtra, extra) => Object.assign({ animation: false, visualMap: VM, calendar,
  series: [Object.assign({ type: 'heatmap', coordinateSystem: 'calendar', data }, seriesExtra || {})] }, extra || {});
const febDays = f => Array.from({ length: 28 }, (_, i) => ['2017-02-' + pad2(i + 1), f(i)]);
const f11 = i => (i * 7 + 3) % 11;
const POS13 = ['top', 'bottom', 'left', 'right', 'inside', 'insideLeft', 'insideRight', 'insideTop', 'insideBottom', 'insideTopLeft', 'insideTopRight', 'insideBottomLeft', 'insideBottomRight'];
// items {value: ['2017-02-dd', v], ...extra} from Feb 1
const items = extras => extras.map((e, k) => Object.assign({ value: ['2017-02-' + pad2(k + 1), (k * 3) % 11] }, e));

const CASES = [
  { id: 'C1', note: "the default calendar {range: '2017-02'} (cell 20, borderWidth 1 -> contentRect inset 0.5: every cell 19 x 19 at +0.5), every February day with a value, a hidden continuous visualMap 0..10; rows OUTSIDE the range -- '2016-12-25', '2017-01-31' (before), '2017-03-01', '2018-01-01' (after) -- are skipped by dataToLayout's clamp (NaN); no labels",
    option: hmc({ range: '2017-02' }, [['2016-12-25', 3], ['2017-01-31', 4]].concat(febDays(f11)).concat([['2017-03-01', 5], ['2018-01-01', 6]])) },
  { id: 'C2', note: "date forms on Feb 2017 (cell 31.5 x 27.25), labels '{@time}' print the raw date: '2017-02-03 13:00' (same cell as the 3rd), '2017-02-04T23:59:59.999Z', '2017-02-05T03:00:00+08:00' (UTC Feb 4 19:00: the Feb 4 cell), '2017-02-07T00:20:00+00:30' (upstream drops the offset MINUTES: '+00' -> Feb 7 00:20, although the instant is Feb 6 23:50), '2017-02-08T00:00:00-05:30' (hour + 5 -> Feb 8 05:00), a numeric timestamp (Feb 10 00:00Z), Feb 11 00:00Z + 86399999.6 (the store keeps the fraction, getDateInfo rounds it to Feb 12 00:00: the Feb 12 cell), '2017/2/13', '2017-2-14', '2017-02-15T12:00', '2017-02' (Feb 1), '2017' (Jan 1: before), 'garbage' and '' (NaN time), null (NaN), '2017-02-28 23:59:59', '2017-02-28 24:00' (hour 24 rolls to Mar 1: after), true (parseDate(true) = new Date(1): 1970, before)",
    option: hmc({ range: '2017-02', cellSize: [31.5, 27.25] }, [['2017-02-03', 1], ['2017-02-03 13:00', 2], ['2017-02-04T23:59:59.999Z', 3], ['2017-02-05T03:00:00+08:00', 4],
      ['2017-02-07T00:20:00+00:30', 5], ['2017-02-08T00:00:00-05:30', 6], [Date.UTC(2017, 1, 10), 7], [Date.UTC(2017, 1, 11) + 86399999.6, 8], ['2017/2/13', 9], ['2017-2-14', 10],
      ['2017-02-15T12:00', 0], ['2017-02', 1], ['2017', 2], ['garbage', 3], ['', 4], [null, 5], ['2017-02-28 23:59:59', 6], ['2017-02-28 24:00', 7], [true, 8]],
    { label: { show: true, formatter: '{@time}' } }) },
  { id: 'C3', note: "value forms (cell 30), labels with the DEFAULT text = String(rawValue[2]) -- '-' on every [date, value] row: 5; '-', null, missing ([date] only), 'abc', '' (NaN: skipped); '07' (7), '1e1' (10), ' 3 ' (3), 0, -2, 5.25, 'Infinity' (+Infinity: drawn, the visualMap's end colour), true (1), false (0); [date, 5, 99] -> '99', [date, 5, 'txt'] -> 'txt', [date, 5, null] -> '-', [date, 5, 0] -> '0', {value: [date, 6, 'obj']} -> 'obj', {value: [date, 7]} -> '-', [date, 8, 'a', 'b'] -> 'a'",
    option: hmc({ range: '2017-02', cellSize: 30 }, [['2017-02-01', 5], ['2017-02-02', '-'], ['2017-02-03', null], ['2017-02-04'], ['2017-02-05', 'abc'], ['2017-02-06', '07'], ['2017-02-07', '1e1'],
      ['2017-02-08', ' 3 '], ['2017-02-09', 0], ['2017-02-10', -2], ['2017-02-11', 5.25], ['2017-02-12', 'Infinity'], ['2017-02-13', ''], ['2017-02-14', true], ['2017-02-15', 5, 99],
      ['2017-02-16', 5, 'txt'], ['2017-02-17', 5, null], ['2017-02-18', 5, 0], { value: ['2017-02-19', 6, 'obj'] }, { value: ['2017-02-20', 7] }, ['2017-02-21', 8, 'a', 'b'], ['2017-02-22', false]],
    { label: { show: true } }) },
  { id: 'C4', note: "duplicate days: four rows land on Feb 3 ('2017-02-03' 2 'A', '2017-02-03' 9 'B', '2017-02-03 18:00' 5 'C', the timestamp 7 'D') -- all drawn, the same contentRect, painted in data order (the LAST row's cell and label on top; all cells paint before all labels); '2017-02-03T23:00:00-02:00' 3 'F' is Feb 4 01:00 (the Feb 4 cell, with 'E'); a '-' value on Feb 4 ('G') is skipped. The FIRST row has three elements, so the store has a third dim value0 and the visualMap's default dimension is IT: the letters are NaN there -> the visualMap writes an undefined colour -> an own fill undefined = NO fill (not '#000'): the cells are invisible and the labels take the OUTSIDE ink",
    option: hmc({ range: '2017-02', cellSize: 30 }, [['2017-02-03', 2, 'A'], ['2017-02-03', 9, 'B'], ['2017-02-03 18:00', 5, 'C'], [Date.UTC(2017, 1, 3), 7, 'D'], ['2017-02-04', 1, 'E'],
      ['2017-02-03T23:00:00-02:00', 3, 'F'], ['2017-02-04', '-', 'G']], { label: { show: true } }) },
  { id: 'C5', note: "formatter templates on a NAMED series 'Hm' (series label '{b}|{c}|{@value}': {b} = '' unless the item has a name, {c} = the whole raw value array 'date,v'); items: name 'nm', name 7 -> '7', name true (dropped: ''); formatters '{a}', '{@time}', '{@[2]}' (a third element), '{@[1]}', '{c} {c}' (first only), '' -> '', '{b0}', '{@[5]}' -> ''",
    option: hmc({ range: '2017-02', cellSize: 30 }, [['2017-02-01', 3], ['2017-02-02', '07'], { value: ['2017-02-03', 4], name: 'nm' }, { value: ['2017-02-04', 5], name: 7 }, { value: ['2017-02-05', 6], name: true },
      { value: ['2017-02-06', 7], label: { formatter: '{a}' } }, { value: ['2017-02-07 09:30', 8], label: { formatter: '{@time}' } }, { value: ['2017-02-08', 9, 'third'], label: { formatter: '{@[2]}' } },
      { value: ['2017-02-09', ' 3 '], label: { formatter: '{@[1]}' } }, { value: ['2017-02-10', 1], label: { formatter: '{c} {c}' } }, { value: ['2017-02-11', 2], label: { formatter: '' } },
      { value: ['2017-02-12', 3], label: { formatter: '{b0}' } }, { value: ['2017-02-13', 4], label: { formatter: '{@[5]}' } }],
    { name: 'Hm', label: { show: true, formatter: '{b}|{c}|{@value}' } }) },
  { id: 'C6', note: "label placement on 40 px cells (contentRect 39 x 39): every position (13) + 'outside' (-> 'top') + ['30%', 5]; series distance 8; then rotate 45, offset [5, -3], align 'right' + verticalAlign 'top', color '#f0f', textBorderColor '#000' + textBorderWidth 2, fontSize 16 + fontWeight 'bold', backgroundColor '#ff0' (no automatic halo), opacity 0.5, color 'inherit' (-> null: the automatic ink), silent",
    option: hmc({ range: '2017-02', cellSize: 40, left: 40 }, items(POS13.concat(['outside']).map(p => ({ label: { position: p } })).concat([{ label: { position: ['30%', 5] } },
      { label: { rotate: 45 } }, { label: { offset: [5, -3] } }, { label: { align: 'right', verticalAlign: 'top' } }, { label: { color: '#f0f' } }, { label: { textBorderColor: '#000', textBorderWidth: 2 } },
      { label: { fontSize: 16, fontWeight: 'bold' } }, { label: { backgroundColor: '#ff0' } }, { label: { opacity: 0.5 } }, { label: { color: 'inherit' } }, { label: { silent: true } }])),
    { label: { show: true, distance: 8 } }) },
  { id: 'C7', note: "cell styles on 36 px cells: series itemStyle {borderColor '#fff', borderWidth 2, borderRadius 4, opacity 0.9} (the label rect grows 1 each side); items: borderRadius [2, 8], 100 (clamped), 0 (a plain rect), [0, 0, 0, 0] (truthy: the round-rect path without arcs); item color '#c00' (beats the visualMap); borderColor '#000' + borderWidth 1; opacity 0.5 (the label opacity follows); color 'none' (outside ink, rect grows max(2, 5)); borderType 'dashed'; shadowBlur 6 + shadowColor; visualMap: false (keeps the palette colour); labels shown",
    option: hmc({ range: '2017-02', cellSize: 36, left: 40 }, items([{}, { itemStyle: { borderRadius: [2, 8] } }, { itemStyle: { borderRadius: 100 } }, { itemStyle: { borderRadius: 0 } },
      { itemStyle: { borderRadius: [0, 0, 0, 0] } }, { itemStyle: { color: '#c00' } }, { itemStyle: { borderColor: '#000', borderWidth: 1 } }, { itemStyle: { opacity: 0.5 } },
      { itemStyle: { color: 'none' } }, { itemStyle: { borderType: 'dashed' } }, { itemStyle: { shadowBlur: 6, shadowColor: 'rgba(0,0,0,0.5)' } }, { visualMap: false }]),
    { itemStyle: { borderColor: '#fff', borderWidth: 2, borderRadius: 4, opacity: 0.9 }, label: { show: true } }) },
  { id: 'C8', note: "series itemStyle.color '#0a0': the visualMap colour REPLACES it (the series colour record keeps '#0a0'); an item colour wins over both; labels shown",
    option: hmc({ range: '2017-02', cellSize: 30 }, items([{}, {}, { itemStyle: { color: '#123' } }, {}]), { itemStyle: { color: '#0a0' }, label: { show: true } }) },
  { id: 'C9', note: 'the calendar border moves the heatmap cell: four calendars with itemStyle.borderWidth 0 (contentRect = rect), 0.5 (inset 0.25), 3 (inset 1.5) and cellSize 2 + borderWidth 3 (the contentRect COLLAPSES to 0 x 0 at the cell centre: still drawn, x is not NaN); one heatmap per calendar (calendarIndex 0..3), labels on the first and third',
    option: { animation: false, visualMap: VM,
      calendar: [{ top: 40, range: '2017-02', cellSize: 30, itemStyle: { borderWidth: 0 } }, { top: 290, range: '2017-02', cellSize: 30, itemStyle: { borderWidth: 0.5 } },
        { top: 40, left: 400, range: '2017-02', cellSize: 30, itemStyle: { borderWidth: 3 } }, { top: 400, left: 500, range: '2017-02', cellSize: 2, itemStyle: { borderWidth: 3 } }],
      series: [0, 1, 2, 3].map(ci => Object.assign({ type: 'heatmap', coordinateSystem: 'calendar', calendarIndex: ci, data: febDays(f11).filter((_, k) => k % 3 === ci % 3) },
        ci % 2 === 0 ? { label: { show: true } } : {})) } },
  { id: 'C10', note: "VERTICAL calendar, firstDay 1, range ['2017-02-15', '2017-04-10'] in a box {left 100.5, right 413.25, top 40, bottom 33.3} (both cell sizes 'auto': fractional); rows every 3 days from Feb 12 to Apr 13 (the first and last outside the range), labels shown",
    option: hmc({ orient: 'vertical', left: 100.5, right: 413.25, top: 40, bottom: 33.3, range: ['2017-02-15', '2017-04-10'], dayLabel: { firstDay: 1 } },
      Array.from({ length: 21 }, (_, k) => [fmtDn(Date.UTC(2017, 1, 12) / DAY + 3 * k), f11(k)]), { label: { show: true } }) },
  { id: 'C11', note: "two calendars with ids ('first' Jan, 'second' Feb 25 x 18 cells): series A calendarIndex 1, B calendarId 'first', C with neither (calendar 0 = January: its February rows are all 'after'), D calendarId 'second'",
    option: { animation: false, visualMap: VM, calendar: [{ id: 'first', range: '2017-01', top: 40 }, { id: 'second', range: '2017-02', top: 300, cellSize: [25, 18] }],
      series: [{ type: 'heatmap', name: 'A', coordinateSystem: 'calendar', calendarIndex: 1, data: febDays(f11).slice(0, 6) },
        { type: 'heatmap', name: 'B', coordinateSystem: 'calendar', calendarId: 'first', data: [['2017-01-01', 2], ['2017-01-15', 5], ['2017-01-31', 9]] },
        { type: 'heatmap', name: 'C', coordinateSystem: 'calendar', data: [['2017-02-01', 2], ['2017-01-20', 8]] },
        { type: 'heatmap', name: 'D', coordinateSystem: 'calendar', calendarId: 'second', data: [['2017-02-20', 4], ['2017-02-28', 10]] }] } },
  { id: 'C12', note: "continuous visualMap range [2, 8] of 0..10, inRange {color ['#ddd', '#036'], opacity [0.3, 1]}, outOfRange {color '#999', opacity 0.2}: the vm writes style.opacity; the label opacity follows the cell's",
    option: hmc({ range: '2017-02', cellSize: 30 }, febDays(i => i % 11).slice(0, 11), { label: { show: true } },
      { visualMap: { min: 0, max: 10, range: [2, 8], inRange: { color: ['#ddd', '#036'], opacity: [0.3, 1] }, outOfRange: { color: '#999', opacity: 0.2 } } }) },
  { id: 'C13', note: "piecewise visualMap pieces [0, 3] '#0a0', [3, 6] '#fa0', > 6 '#c00', outOfRange '#ccc': values -1, 0, 3, 4.5, 6, 9, 20; labels shown",
    option: hmc({ range: '2017-02', cellSize: 30 }, [-1, 0, 3, 4.5, 6, 9, 20].map((v, k) => ['2017-02-' + pad2(k + 1), v]), { label: { show: true } },
      { visualMap: { type: 'piecewise', pieces: [{ min: 0, max: 3, color: '#0a0' }, { min: 3, max: 6, color: '#fa0' }, { gt: 6, color: '#c00' }], outOfRange: { color: '#ccc' } } }) },
  { id: 'C14', prod: true, note: "PRODUCTION build ('Heatmap must use with visualMap' in development): NO visualMap: every cell takes its series palette colour ('#5070dd', the second series '#b6d634'); inside labels on it (vm null)",
    option: { animation: false, calendar: { range: '2017-02', cellSize: 30 },
      series: [{ type: 'heatmap', name: 'P', coordinateSystem: 'calendar', label: { show: true }, data: [['2017-02-01', 1], ['2017-02-02', 2]] },
        { type: 'heatmap', name: 'Q', coordinateSystem: 'calendar', label: { show: true }, data: [['2017-02-03', 3], ['2017-02-04', 4]] }] } },
  { id: 'C15', note: "z / z2 / zlevel: series 0 z 1 (BELOW the calendar's z 2: the day rects paint over its cells); series 1 z 3 (above the split lines and the calendar names; its labels too); series 2 option z2 50 (IGNORED: the cell z2 stays 1, the label 3); series 3 zlevel 1 (a layer of its own, after everything at zlevel 0); all with labels",
    option: { animation: false, visualMap: VM, calendar: { range: '2017-02', cellSize: 30 },
      series: [{ z: 1 }, { z: 3 }, { z2: 50 }, { zlevel: 1 }].map((x, k) => Object.assign({ type: 'heatmap', coordinateSystem: 'calendar', label: { show: true },
        data: febDays(f11).filter((_, j) => j % 4 === k) }, x)) } },
  { id: 'C16', note: 'calendar z 3: the calendar (day rects, lines, names) now paints entirely over the default-z (2) heatmap cells and their labels',
    option: hmc({ range: '2017-02', cellSize: 30, z: 3 }, febDays(f11).slice(0, 5), { label: { show: true } }) },
  { id: 'C17', note: 'a legend-unselected heatmap draws nothing (filtered, heatmap null); the shown one does',
    option: { animation: false, visualMap: VM, legend: { selected: { hidden: false } }, calendar: { range: '2017-02', cellSize: 30 },
      series: [{ type: 'heatmap', name: 'hidden', coordinateSystem: 'calendar', data: [['2017-02-01', 1]] }, { type: 'heatmap', name: 'shown', coordinateSystem: 'calendar', data: [['2017-02-02', 9]] }] } },
  { id: 'C18', note: "firstDay: January 2017 horizontal on two calendars, firstDay 1 (Monday rows first: Jan 1, a Sunday, sits in row 6 of week 0) and firstDay 6; the same rows on both",
    option: { animation: false, visualMap: VM, calendar: [{ top: 40, range: '2017-01', cellSize: 25, dayLabel: { firstDay: 1 } }, { top: 300, range: '2017-01', cellSize: 25, dayLabel: { firstDay: 6 } }],
      series: [0, 1].map(ci => ({ type: 'heatmap', coordinateSystem: 'calendar', calendarIndex: ci, label: { show: true }, data: [1, 2, 7, 8, 9, 15, 29, 31].map((d, k) => ['2017-01-' + pad2(d), f11(k)]) })) } },
  { id: 'C19', note: "a range across two years ['2016-11-15', '2017-02-10'] (fweek 2): rows on '2016-11-14' (before), '2016-11-15', '2016-12-31', '2017-01-01', '2017-02-10', '2017-02-11' (after), '2016-02-29' (before)",
    option: hmc({ range: ['2016-11-15', '2017-02-10'], cellSize: 12, left: 60 }, [['2016-11-14', 1], ['2016-11-15', 2], ['2016-12-31', 3], ['2017-01-01', 4], ['2017-02-10', 5], ['2017-02-11', 6], ['2016-02-29', 7]]) },
  { id: 'C20', note: "darkMode true + backgroundColor '#1e1e1e', series silent true (every cell isSilent), label.silent: inside labels stroked only when the ink is dark; a 'top' label '#ccc' with the ground halo",
    option: hmc({ range: '2017-02', cellSize: 30 }, items([{}, { itemStyle: { color: '#fff' } }, { itemStyle: { color: '#222' } }, { label: { position: 'top' } }, { itemStyle: { color: '#ffffbf' } }]),
      { silent: true, label: { show: true, silent: true } }, { darkMode: true, backgroundColor: '#1e1e1e' }) },
  { id: 'C21', note: "[date, value, extra] rows with NUMERIC extras (the first row has three elements: dims time, value, value0): series 0's visualMap (default dimension = the LAST dim) colours by the extra, series 1's (dimension 1) by the value; a later row with only two elements has value0 NaN (series 0: no fill); labels '{@value0}'",
    option: { animation: false, calendar: { range: '2017-02', cellSize: 30 },
      visualMap: [{ seriesIndex: 0, min: 0, max: 10, show: false }, { seriesIndex: 1, dimension: 1, min: 0, max: 10, show: false }],
      series: [0, 1].map(si => ({ type: 'heatmap', coordinateSystem: 'calendar', label: { show: true, formatter: '{@value0}' },
        data: [[2, 9, 1], [3, 1, 9], [4, 5, 5], [5, 7]].map(([d, v, x]) => (x === undefined ? ['2017-02-' + pad2(d + si * 7), v] : ['2017-02-' + pad2(d + si * 7), v, x])) })) } },
  { id: 'C22', note: "the VALUE dim guessed ORDINAL (the first row's value 'x' is a non-numeric string: guessOrdinal Must) -- the store keeps every raw value: 'x' (isNaN: skipped), '5' (a string: drawn), 7, null (isNaN(null) is false: DRAWN), '' (isNaN('') is false: drawn), '-' and a missing value (NaN / undefined: skipped); the visualMap maps the raw values (value records hold the strings); labels '{@value}'",
    option: hmc({ range: '2017-02', cellSize: 30 }, [['2017-02-01', 'x'], ['2017-02-02', '5'], ['2017-02-03', 7], ['2017-02-04', null], ['2017-02-05', ''], ['2017-02-06', '-'], ['2017-02-07']],
      { label: { show: true, formatter: '[{@value}]' } }) },
  { id: 'C23', note: "the value dim guess looks PAST null / '-' leading rows (up to 5): rows null, '-', then 'abc' -> ordinal; a second series whose first rows are null, '-', then 4 -> float; a third series whose 'Infinity' first row makes it ordinal (Number('Infinity') is not finite)",
    option: { animation: false, visualMap: VM, calendar: { range: '2017-02', cellSize: 30 },
      series: [[null, '-', 'abc', 3, '6'], [null, '-', 4, 'abc', '6'], ['Infinity', 2, '8']].map((vals, si) => ({ type: 'heatmap', coordinateSystem: 'calendar', label: { show: true },
        data: vals.map((v, k) => ['2017-02-' + pad2(si * 7 + k + 1), v]) })) } },
];
for (const [name, note] of [
  ['calendar-simple', "calendar-simple.json verbatim: {range: '2017'}, 365 rows, a hidden continuous visualMap 0..10000"],
  ['calendar-heatmap', "calendar-heatmap.json verbatim: calendar borderWidth 0.5 (inset 0.25) on 'auto' x 13 cells, leap 2016 (366 rows), a shown piecewise visualMap, a title"],
  ['calendar-horizontal', 'calendar-horizontal.json verbatim: three calendars (2017, 2016, 2015), one heatmap each by calendarIndex, a shown calculable continuous visualMap'],
  ['calendar-vertical', 'calendar-vertical.json verbatim: three vertical calendars (2015, 2016, 2017 with bottom 10 / cellSize [20, auto]), one heatmap each'],
  ['calendar-lunar', "calendar-lunar.json verbatim: its heatmap (series 2, 365 rows of 2017 on a March 2017 calendar: all but March skipped 'before' / 'after') coloured by a visualMap with inRange opacity 0.3; the two scatter series (label-only lunar dates) are NOT recorded (recorded false) but paint in paintRuns"],
  ['calendar-charts', "calendar-charts.json verbatim: heatmap series 1 (2017 rows on calendar 0 = Feb 2017: the rest skipped; the visualMap with opacity [0, 0.3]) and series 4 (on calendar 3); the graph / effectScatter / scatter series are NOT recorded but paint in paintRuns"],
  ['calendar-graph', "calendar-graph.json verbatim: heatmap series 1 (2017 rows on the Feb-Mar 2017 vertical calendar, piecewise visualMap); the graph series is NOT recorded but paints in paintRuns"],
]) CASES.push({ id: 'G-' + name, gallery: name, note: note + ' (examples/advchart/gallery, harvested with real dates at acf43175)' });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'rect-not-content', mutation: 'the cell is dataToLayout().rect instead of contentRect', mut: { rectNotContent: true }, named: ['C1', 'C9', 'G-calendar-simple', 'G-calendar-heatmap'] },
  { id: 'full-inset', mutation: 'the contentRect shrunk by lineWidth instead of lineWidth / 2 per side', mut: { fullInset: true }, named: ['C1', 'C9', 'G-calendar-heatmap'] },
  { id: 'z2-zero', mutation: 'the cell z2 0 instead of 1 (the label z2 follows: 2)', mut: { z2Zero: true }, named: ['C1', 'C3', 'G-calendar-simple'] },
  { id: 'label-z2-fixed', mutation: 'the label z2 2 (as on a cartesian) instead of the running max z2 + 2 = 3', mut: { labelZ2Fixed: true }, named: ['C3', 'C6'] },
  { id: 'clamp-off', mutation: 'dates outside the range drawn (dataToLayout without the clamp)', mut: { clampOff: true }, named: ['C1', 'C2', 'C19', 'G-calendar-lunar', 'G-calendar-charts'] },
  { id: 'no-fweek', mutation: 'the week column ignores the first week offset: floor((dn - S) / 7)', mut: { noFweek: true }, named: ['C1', 'C10', 'C19'] },
  { id: 'first-day-ignored', mutation: 'dayLabel.firstDay ignored (0)', mut: { firstDayIgnored: true }, named: ['C10', 'C18'] },
  { id: 'orient-ignored', mutation: 'a vertical calendar laid out horizontally', mut: { orientIgnored: true }, named: ['C10', 'G-calendar-vertical', 'G-calendar-lunar'] },
  { id: 'calendar-zero', mutation: 'every series on calendar 0 (calendarIndex / calendarId ignored)', mut: { calendarZero: true }, named: ['C9', 'C11', 'C18', 'G-calendar-horizontal', 'G-calendar-charts'] },
  { id: 'offset-minutes', mutation: "a '+hh:mm' offset honours its minutes (upstream drops them)", mut: { offsetMinutes: true }, named: ['C2'] },
  { id: 'time-no-round', mutation: 'getDateInfo without Math.round (a fractional timestamp floors to its own day)', mut: { timeNoRound: true }, named: ['C2'] },
  { id: 'day-nearest', mutation: 'the day of a time of day rounded to the nearest midnight instead of floored', mut: { dayNearest: true }, named: ['C2', 'C4'] },
  { id: 'nan-value-drawn', mutation: 'a NaN value not skipped', mut: { nanValueDrawn: true }, named: ['C3', 'C4'] },
  { id: 'default-text-value', mutation: "the default label text String(value) instead of rawValue[2] / '-'", mut: { defaultTextValue: true }, named: ['C3', 'C6'] },
  { id: 'name-no-item', mutation: "the item name ignored ({b} always '')", mut: { nameNoItem: true }, named: ['C5'] },
  { id: 'tpl-replace-all', mutation: 'formatTpl replaces every occurrence', mut: { tplReplaceAll: true }, named: ['C5'] },
  { id: 'dim-template-ignored', mutation: '{@dim} / {@[n]} left unreplaced', mut: { dimTemplateIgnored: true }, named: ['C2', 'C5'] },
  { id: 'vm-ignored', mutation: 'the visualMap visuals not applied', mut: { vmIgnored: true }, named: ['C1', 'C12', 'C13', 'G-calendar-simple'] },
  { id: 'item-under-vm', mutation: 'the visualMap applied AFTER the item itemStyle', mut: { itemUnderVm: true }, named: ['C7', 'C8', 'C20'] },
  { id: 'label-opacity-own', mutation: 'the label opacity not defaulting to the cell style opacity', mut: { labelOpacityOwn: true }, named: ['C7', 'C12'] },
  { id: 'radius-series-only', mutation: 'borderRadius from the series only', mut: { radiusSeriesOnly: true }, named: ['C7'] },
  { id: 'rect-no-stroke', mutation: 'the label rect not grown by the stroke', mut: { rectNoStroke: true }, named: ['C7'] },
  { id: 'position-default-top', mutation: "the default label position 'top'", mut: { positionDefaultTop: true }, named: ['C3', 'C6'] },
  { id: 'inside-as-outside', mutation: 'inside positions use the outside ink', mut: { insideAsOutside: true }, named: ['C3', 'C20'] },
  { id: 'no-ordinal-guess', mutation: 'every value dim float (no guessOrdinal)', mut: { noOrdinalGuess: true }, named: ['C4', 'C22', 'C23'] },
  { id: 'dims-fixed', mutation: 'the store dims always time + value (no value0 ... from the first row)', mut: { dimsFixed: true }, named: ['C4', 'C21'] },
  { id: 'z-default-0', mutation: 'the series z default 0 instead of 2', mut: { zDefault0: true }, named: ['C1', 'G-calendar-simple'] },
  { id: 'silent-ignored', mutation: 'series.silent ignored', mut: { silentIgnored: true }, named: ['C20'] },
];

// ============================================================================
// Checks
// ============================================================================
function flat(v, pre, out) {
  if (v === null || v === undefined || typeof v !== 'object') { out[pre] = v; return out; }
  if (isArray(v)) { out[pre + '#'] = v.length; v.forEach((x, i) => flat(x, pre + '[' + i + ']', out)); return out; }
  for (const k of Object.keys(v)) if (v[k] !== undefined) flat(v[k], pre + '.' + k, out);
  return out;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => !Object.is(a[k], b[k])).map(k => ({ field: k, upstream: a[k] === undefined ? '(absent)' : a[k], mutated: b[k] === undefined ? '(absent)' : b[k] }));
}
const TRANSCRIBED_ROW_KEYS = ['time', 'value', 'name', 'style', 'drawn', 'skip', 'rect', 'label'];
const strip = (o, keys) => {
  if (!o) return o;
  const r = Object.assign({}, o);
  for (const k of keys) delete r[k];
  return r;
};
function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const hm = sr.heatmap;
  const a = {};
  const b = {};
  flat({ dimensions: hm.dimensions, dimensionTypes: hm.dimensionTypes, z: hm.z, zlevel: hm.zlevel, silent: hm.silent, seriesStyle: hm.seriesStyle }, 'block', a);
  flat(t.block, 'block', b);
  hm.rows.forEach((row, i) => {
    const pick = {};
    for (const k of TRANSCRIBED_ROW_KEYS) pick[k] = row[k];
    pick.rect = strip(pick.rect, ['paint']);
    pick.label = strip(pick.label, ['paint', 'tspans']);
    const tr = t.rows[i];
    const tpick = {};
    for (const k of TRANSCRIBED_ROW_KEYS) tpick[k] = tr[k];
    flat(pick, 'row' + i, a);
    flat(tpick, 'row' + i, b);
  });
  return diffFlat(a, b);
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    for (const sr of c.series) {
      if (!sr.recorded || !sr.heatmap) continue;
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
      for (const row of sr.heatmap.rows) {
        const raw = row.raw;
        const itemColour = raw && !isArray(raw) && typeof raw === 'object' && raw.itemStyle && raw.itemStyle.color != null;
        if (row.vm && row.vm.colorWritten && !itemColour) must(JSON.stringify(row.style.fill === undefined ? null : row.style.fill) === JSON.stringify(row.vm.color), key + ': row ' + row.index + ' is not the visualMap colour');
        if (row.label && row.label.paint != null) must(row.label.paint > row.rect.paint, key + ': a label paints before its cell');
      }
    }
  }
  // anchors
  const hmOf = (id, si) => byId[id].series.find(s => s.seriesIndex === si).heatmap;
  const row = (id, si, i) => hmOf(id, si).rows[i];
  const rectIs = (r, x, y, w, h) => r.x === x && r.y === y && r.width === w && r.height === h;
  must(rectIs(row('C1', 0, 2).rect.shape, 80.5, 120.5, 19, 19) && row('C1', 0, 0).skip === 'before' && row('C1', 0, 1).skip === 'before' && row('C1', 0, 30).skip === 'after'
    && row('C1', 0, 31).skip === 'after' && row('C1', 0, 2).rect.z === 2 && row('C1', 0, 2).rect.z2 === 1 && row('C1', 0, 2).rect.path === null, 'C1: Feb 1 (a Wednesday: row 3 of week 0) at 80.5,120.5 19 x 19, clamp, z 2 / z2 1');
  const c2 = hmOf('C2', 0);
  must(rectIs(c2.rows[1].rect.shape, c2.rows[0].rect.shape.x, c2.rows[0].rect.shape.y, c2.rows[0].rect.shape.width, c2.rows[0].rect.shape.height), 'C2: 13:00 in the same cell');
  must(sameRect(c2.rows[3].rect.shape, c2.rows[2].rect.shape), 'C2: +08:00 lands on the day before');
  must(c2.rows[4].time === Date.UTC(2017, 1, 7, 0, 20) && c2.rows[7].time === Date.UTC(2017, 1, 11) + 86399999.6, 'C2: the minutes dropped, the fraction kept');
  must(['time', 'time', 'time'].every((s, k) => c2.rows[13 + k].skip === s) && c2.rows[12].skip === 'before' && c2.rows[17].skip === 'after' && c2.rows[18].skip === 'before', 'C2: skip reasons');
  must(row('C3', 0, 0).label.text === '-' && row('C3', 0, 14).label.text === '99' && row('C3', 0, 16).label.text === '-' && row('C3', 0, 17).label.text === '0' && row('C3', 0, 1).skip === 'value'
    && row('C3', 0, 13).value === 1 && row('C3', 0, 0).label.z2 === 3, 'C3: default texts');
  const c4 = hmOf('C4', 0);
  must([0, 1, 2, 3].every(k => sameRect(c4.rows[k].rect.shape, c4.rows[0].rect.shape)) && sameRect(c4.rows[5].rect.shape, c4.rows[4].rect.shape) && c4.rows[6].skip === 'value', 'C4: duplicates');
  must(row('C5', 0, 0).label.text === '|2017-02-01,3|3' && row('C5', 0, 2).label.text === 'nm|2017-02-03,4|4' && row('C5', 0, 5).label.text === 'Hm', 'C5: templates');
  const c9 = byId.C9;
  must(rectIs(row('C9', 0, 0).rect.shape, c9.calendars[0].rect.x, c9.calendars[0].rect.y + 3 * 30, 30, 30) && row('C9', 3, 0).rect.shape.width === 0, 'C9: borderWidth 0 / collapse');
  must(byId.C11.series[2].calendarIndex === 0 && hmOf('C11', 2).rows[0].skip === 'after' && byId.C11.series[1].calendarIndex === 0 && byId.C11.series[3].calendarIndex === 1, 'C11: calendar reference');
  must(byId.C14.productionBuild && /visualMap/.test(byId.C14.devError) && row('C14', 0, 0).style.fill === '#5070dd' && row('C14', 1, 0).style.fill === '#b6d634', 'C14: production, palette');
  must(row('C15', 2, 0).rect.z2 === 1 && row('C15', 0, 0).rect.z === 1 && row('C15', 3, 0).rect.zlevel === 1, 'C15: z2 option ignored');
  must(byId.C17.series[0].filtered && byId.C17.series[0].heatmap === null, 'C17: hidden series');
  must(row('C2', 0, 7).rect.shape.x === 143.5 && row('C2', 0, 7).rect.shape.y === 60.5, 'C2: the fractional timestamp rounds to Feb 12');
  must(row('C4', 0, 0).style.fill === null && row('C4', 0, 0).drawn && row('C4', 0, 0).label.inside === false && hmOf('C4', 0).dimensions.join() === 'time,value,value0'
    && hmOf('C4', 0).dimensionTypes[2] === 'ordinal', 'C4: the ordinal third dim, no fill');
  must(hmOf('C22', 0).dimensionTypes[1] === 'ordinal' && row('C22', 0, 3).drawn && row('C22', 0, 3).value === null && row('C22', 0, 1).value === '5' && row('C22', 0, 0).skip === 'value', 'C22: ordinal value dim');
  must(row('C21', 0, 0).vm.vms[0].value === 1 && row('C21', 1, 0).vm.vms[0].value === 9, 'C21: the default visualMap dimension is the extra');
  must(!byId['G-calendar-lunar'].series[0].recorded && byId['G-calendar-lunar'].series[2].recorded, 'G-calendar-lunar: marks');
  // paint order: a heatmap cell (z 2, z2 1) paints after every day rect and before every split line of its calendar
  for (const c of out.cases) {
    const runs = c.paintRuns;
    let at = 0;
    const pos = runs.map(r => { const p = at; at += r.n; return p; });
    for (const sr of c.series) {
      if (!sr.recorded || !sr.heatmap || sr.heatmap.z !== 2 || sr.heatmap.zlevel !== 0) continue;
      const cal = c.calendars[sr.calendarIndex];
      if (cal.z !== 2 || cal.zlevel !== 0) continue;
      for (const r of sr.heatmap.rows) {
        if (!r.drawn) continue;
        runs.forEach((run, k) => {
          if (run.owner !== 'calendar' || run.index !== cal.index) return;
          if (run.group === 'day') must(pos[k] + run.n <= r.rect.paint, c.id + ': a day rect paints after a cell');
          else must(pos[k] > r.rect.paint, c.id + ': a calendar line / name paints before a cell');
        });
      }
    }
  }
  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        if (!sr.recorded || !sr.heatmap) continue;
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

// ============================================================================
// Output
// ============================================================================
let specials = 0;
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) { specials++; return 'Infinity'; }
    if (v === -Infinity) { specials++; return '-Infinity'; }
    if (Object.is(v, -0)) { specials++; return '-0'; }
    return v;
  }
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return v;
  if (isArray(v)) return v.map(x => { const s = sanitize(x); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    const s = sanitize(v[k]);
    if (s !== undefined) o[k] = s;
  }
  return o;
}

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
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
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
    W, H, seed: SEED, tz: 'UTC',
    api: {
      update: "echarts.init(null, null, {renderer: 'svg', ssr: true, width: 800, height: 600}); setOption; zr.storage.getDisplayList(true) (every element updated: updateInnerText places the labels, the Texts lay out their TSpans)",
      data: "series.getData(): count, getRawIndex, getRawDataItem, get('time' / 'value', i), getName, getItemVisual(i, 'style'), getVisual('style'), getItemGraphicEl(i) = the cell Rect (undefined when skipped); el.shape / style / z / z2 / zlevel / isSilent(), el.path (PathProxy) up to len(), el.path.getBoundingRect(), el.getBoundingRect(), el.getTextContent() = the label (innerTransformable, _defaultStyle, childrenRef() = its TSpans)",
      calendar: "seriesModel.coordinateSystem === ecModel.getComponent('calendar', i).coordinateSystem (the calendar index); getRect, getCellWidth / Height, _lineWidth, getOrient, getFirstDayOfWeek, getRangeInfo; dataToLayout([time]).contentRect (the cell check), getDateInfo (the skip reason)",
      visualMap: 'each targeting visualMap (component order): vm.getDataDimensionIndex(data), store.get(dim, i), vm.getValueState(value), vm.targetVisuals[state] mappings applied in VisualMapping.prepareVisualTypes order (visualSolution.incrementalApplyVisual), recording what they write',
      paint: 'zr.storage.getDisplayList(true); an element is owned by the first view group (chart.getViewOfComponentModel / getViewOfSeriesModel) found climbing el.parent, then el.__hostTarget (a label Text -> its host)',
      production: 'a case whose development-build run throws is recorded from dist/echarts.min.js (productionBuild true, devError the message); every other case must record identically through both builds',
    },
    notes: [
      'TIMEZONE: the script sets process.env.TZ = UTC before touching Date. A zone-less date string is LOCAL time upstream, and the calendar reads every quantity through local getters, so string dates give the same cells in any zone whose DST does not switch at local midnight; a NUMERIC timestamp is a UTC instant and lands on the UTC wall date only here (calendar-layout.js). An offset string (\'Z\', \'+08:00\') is an instant too: C2\'s \'+08:00\' row lands on the day BEFORE its written date.',
      'Dimensions on a calendar: time (a time dim: the store parses strings with parseDate and keeps numbers as they are, fraction included) + value (float: Number(v); null / \'\' / \'-\' / non-numeric -> NaN, true -> 1, false -> 0). parseDate applies an offset\'s HOURS only (hour -= +offset.slice(0, 3)): \'+00:30\' shifts nothing, \'-05:30\' shifts 5 hours.',
      'A row is skipped when its value is NaN, else when dataToLayout([time]).contentRect has a NaN x / y: a NaN time, or a time (Math.round-ed by getDateInfo) outside [first day 00:00, last day + 1 day 00:00) -- dataToPoint clamps by default. The time of day never matters inside the range: the cell is the date\'s civil day.',
      'The cell = dataToLayout([time]).contentRect: the calendar cell (centre -/+ sw/2, sh/2) shrunk by the CALENDAR\'s itemStyle.borderWidth / 2 on every side (default borderWidth 1: 0.5; 0 -> the whole cell; a border wider than the cell collapses the contentRect to 0 x 0 at the centre, still drawn). No 0.5 overlap (unlike the cartesian cell), no clip, no subPixelOptimize.',
      'Paint order: the cell Rect has z2 1, z = the series z (default 2), zlevel = the series zlevel; the series option z2 is ignored. The label z2 is the running max z2 of the view group + 2 = 3 (util/graphic traverseUpdateZ). With the calendar at its default z 2 the display list runs: all calendars\' day rects (z2 0), then every heatmap cell (z2 1, series order, data order), then the heatmap LABELS (z2 3), then the calendar split / edge lines (z2 20) and names (z2 30) -- the split lines paint OVER the heatmap labels -- then scatter symbols (z2 100). Duplicate days all draw, the later row on top.',
      "Dimensions: time + value, plus value0, value1, ... when the FIRST row's value has more than two elements -- and the visualMap's default dimension is the LAST dim, so [date, value, extra] data is coloured by the EXTRA (C21; set visualMap.dimension 1 for the value). Every non-time dim is type-guessed (guessOrdinal over the first up-to-5 rows): a non-numeric string first (after null / '-') makes it ORDINAL and the store keeps raw values -- then the skip test is JS isNaN on the raw value: '5', null and '' are DRAWN, 'x', '-' and undefined are skipped (C22, C23). A visualMap mapping a NaN / non-numeric value writes colour undefined: the cell has NO fill (C4).",
      'Style = the visual style: the series itemStyle (fill = the palette colour when unset), then what the visualMaps write (colour, opacity), then the item itemStyle (it beats the visualMap). No visualMap: the development build throws; production draws the palette colour (C14).',
      "Label: shown only through item.label -> series.label (default off). Default text = String(rawValue[2]) -- a [date, value] row has no third element, so the default text is '-'. {b} = '' unless the item has a name; {c} = the whole raw value array ('2017-02-01,3'); {@time} / {@[0]} = the raw date as written; {@value} / {@[1]} = the raw value as written. Position default 'inside' on the cell's bounding rect (grown by the cell stroke); the label opacity defaults to the cell style opacity; 'inherit' colours become null (no inheritColor).",
      'Not recorded: emphasis / blur / select states, tooltip, hover layers, progressive (incremental) rendering (no series here exceeds progressiveThreshold 3000), the calendar picture itself (calendar-layout.js), and every non-heatmap series (they appear only as paintRuns).',
    ],
    cases,
  };
  return { out, side };
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let g1;
let nSpecial = 0;
let json1;
let json2;
try {
  g1 = generate();
  if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, fmt(sanitize(g1.out), '') + '\n');
  g1.out.guards = check(g1);
  specials = 0;
  const s1 = sanitize(g1.out);
  nSpecial = specials;
  json1 = fmt(s1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(s1), 'the written JSON does not parse back to the record');
  const g2 = generate();
  g2.out.guards = check(g2);
  json2 = fmt(sanitize(g2.out), '') + '\n';
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
const hms = out.cases.flatMap(c => c.series.filter(s => s.recorded && s.heatmap));
const nRows = hms.reduce((a, s) => a + s.heatmap.rows.length, 0);
const nCells = hms.reduce((a, s) => a + s.heatmap.rows.filter(r => r.drawn).length, 0);
const prod = out.cases.filter(c => c.productionBuild).map(c => c.id);
if (prod.length) console.log('through the production build:', prod.join(', '));
console.log(out.cases.length + ' cases (' + hms.length + ' heatmap series, ' + nRows + ' rows, ' + nCells + ' cells); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + nSpecial + ' -0/Infinity values; ' + logged.length + ' console messages from upstream'
  + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
