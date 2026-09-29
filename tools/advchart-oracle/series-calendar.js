/*
Upstream's own answers for the NON-HEATMAP series on a CALENDAR, batch H4:
scatter, effectScatter, graph and pie laid out by coord/calendar/Calendar.ts.
What each one draws and where, exactly as layout/points.ts (scatter /
effectScatter: dataToPoint([time, value]) -> the cell CENTRE),
chart/helper/SymbolDraw.ts + Symbol.ts + EffectSymbol.ts (the symbol path, its
scale = symbolSize / 2, rotation, offset, z2 100; the ripple paths, z2 99),
chart/graph/simpleLayout.ts + simpleLayoutHelper.ts + adjustEdge.ts (node
placement: `hasValue` over the coordinate dims; straight / curved edge points),
chart/pie/pieLayout.ts + util/layout.ts getCircleLayout /
getViewRectAndCenterForCircleLayout / createBoxLayoutReference (the pie's
refContainer = dataToLayout(center).contentRect, its viewRect, centre and radii)
and zrender (createSymbol paths, Element.updateInnerText, Text / TSpan) build
them. It sits beside heatmap-calendar.js (the heatmap cells) and
calendar-layout.js (the calendar picture): this oracle pins where the other four
series land on the calendar and how they sit in the paint order among the
calendar's day cells (z2 0), heatmap cells (1), pie sectors (2), split lines
(20), calendar names (30), ripples (99), symbols (100) and symbol labels (102).

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
with Math.random replaced by the port's xorshift32 (seed 2463534242, reset
before each chart) and process.env.TZ = 'UTC' set inside this script before
anything touches Date (checked: a script that runs under another zone stops).
After setOption it runs zr.storage.getDisplayList(true) (every element's
update: transforms, updateInnerText, TSpan layout) and reads the live models,
coordinate systems, views and the display list. Every chart is disposed in a
finally. Every case is recorded from the DEVELOPMENT build (dist/echarts.js)
and must record identically through the PRODUCTION build (dist/echarts.min.js);
a case marked `prod` would be recorded from production (none is: no case here
trips a development-only throw).

  node tools/advchart-oracle/series-calendar.js

writes tests/fixtures/advchart-series-calendar.json (ORACLE_OUT overrides;
ORACLE_DUMP=<file> also writes the record before the checks, for debugging).

THE EFFECT RIPPLES ARE A STATIC FRAME. EffectSymbol.startEffectAnimation creates
the ripple paths at scale 0.5 and hands them two looping animators (scale ->
rippleScale / 2, style.opacity -> 0, over `period` ms, with a per-ripple delay).
Nothing here ever steps zrender's animation loop, so every ripple is recorded as
it stands before its first frame: scale 0.5 inside a ripple group scaled by the
symbol size (net radius = the symbol's), opacity as styled (no own key: 1). The
animators are recorded (targets, keyframes, delay, life, loop) so the port can
drive the same animation; the frame at time t is NOT recorded.

-----------------------------------------------------------------------------
Numbers are plain JSON numbers written by JSON.stringify (shortest round-trip
form). Values JSON has no form for:
  null        NaN in a number field (e.g. the layout of an unplaced node), or an
              undefined value inside an array
  "-0" / "Infinity" / "-Infinity"   those doubles, as strings (the writer counts
              them and prints the count)
  an absent key   upstream holds undefined
A colour is a css string exactly as upstream holds it (or null).

Top level
  source, W, H, seed, tz ('UTC'), api {...}, notes[], symbolPaths, cases[],
  guards[]
  symbolPaths  {symbolType: [{cmd, args}]}: the PathProxy commands of every
    symbol type drawn anywhere in the fixture, built by createSymbol(type, -1,
    -1, 2, 2) (the unit box every symbol and ripple path uses; its scale makes
    the real size) -- checked identical for every element of that type
    (M L C Q A Z R as heatmap-calendar.js: A = cx, cy, rx, ry, startAngle,
    sweep, 0, clockwise 1)
  cases[]  one per chart:
    id, note, gallery (file name or null), option (as fed; null for a gallery
    case: load examples/advchart/gallery/<gallery>.json and feed it VERBATIM),
    productionBuild (bool), devError (null)
    ground     {background, isDark}
    textStyle  ecModel.option.textStyle (the global text style)
    calendars[] one per calendar (as heatmap-calendar.js): index, id, rect
               {x, y, width, height}, cellSize [sw, sh], lineWidth (the
               contentRect inset is lineWidth / 2 per side), orient, firstDay,
               range, startTime, endTime, fweek, lweek, weeks, allDay, z, zlevel,
               splitLine
    paintRuns  the WHOLE display list in paint order, run-length encoded:
               [{owner, index, type, group, zlevel, z, z2, n}]. owner 'calendar'
               (group 'day' | 'split' | 'edge' | 'year' | 'month' | 'week'),
               'series' (index = series index, type = series type, group
               'symbol' (a symbol path: scatter / effectScatter / graph node),
               'ripple' (an effectScatter ripple path), 'edge' (a graph edge
               line), 'edgeSymbol' (a graph edge-end symbol), 'sector' (a pie
               sector), 'cell' (a heatmap cell), 'label' (a TSpan / Text of a
               label), 'labelLine' (a label guide line), 'mark' (anything
               else)), 'component' (a component's elements: group 'mark' /
               'label'), 'other'
    series[]   EVERY series, series order: seriesIndex, type, name (option name
               or null), recorded (false for heatmap: those are heatmap-
               calendar.js's; present for the paint order only), calendarIndex
               (null when not on a calendar). A recorded series also:
      filtered (legend-unselected), color (the series visual colour), z, zlevel
      (series z || 0, zlevel || 0), dimensions, dimensionTypes, count, and per
      type:
      scatter / effectScatter:
        rows[] one per data element:
          index, raw (json of getRawDataItem), time (the store's time: a
          number, parseDate of a string; null = NaN), value (the store's value
          dim), point ([x, y] = data.getItemLayout(i) = dataToPoint([time,
          value]) -- the cell centre; [null, null] = NaN), drawn (a symbol
          element exists), skip (null, or the FIRST reason it is not drawn:
          'time' (NaN time), 'before' / 'after' (dataToPoint's clamp), 'none'
          (symbol 'none'))
          symbol   null, or
            x, y          the symbol GROUP's position (= point)
            type          the symbol type (the visual: Symbol.getSymbolType())
            pathType      the path's shape.symbolType: createSymbol strips an
                          'empty' prefix ('emptyCircle' -> 'circle')
            emptyBrush    the path's __isEmptyBrush (fill '#fff', stroke = the
                          colour, lineWidth 2)
            keepAspect    shape.symbolKeepAspect (bool)
            size          [w, h] = normalizeSymbolSize(the symbolSize visual)
            path          {x, y, scaleX, scaleY, rotation}: the symbol path
                          inside the group -- scale = size / 2 (the unit path is
                          the -1..1 box), x / y = normalizeSymbolOffset (0 0
                          when no offset), rotation = symbolRotate in radians
            transform     the path's GLOBAL m6 (group translate x path local)
            style         the path's own style keys (null = own undefined;
                          zrender's own `blend: null` is not recorded)
            z, z2 (100), zlevel, silent (isSilent()), paint (display index)
            label         null (no text content / ignored) or LABEL below
          effect   effectScatter only (null when no symbol):
            showEffectOn, brushType, rippleScale, period (ms), number,
            effectOffset (idx / count), rippleColor (null = unset: the symbol
            colour), color (the symbol visual fill)
            group   {x, y, scaleX, scaleY, rotation}: the ripple group (scale =
                    the symbol size, x / y = the offset, rotation = the rotate)
            ripples[]  [] when showEffectOn is 'emphasis' (no ripple drawn)
              type, x, y, scaleX, scaleY (0.5: the static frame), rotation,
              style (own keys: fill, stroke by brushType, strokeNoScale),
              z, z2 (99), zlevel, silent, paint,
              anim [{target ('' = the element, 'style'), loop, delay (ms),
                     life (ms), tracks {prop: [[time, value], ...]}}]
      graph:
        nodes[] one per node: index, raw, time (the store's time dim -- the
          GRAPH store types it by guessOrdinal like any dim: a string date
          stays the RAW STRING (dimensionTypes 'ordinal'), a number stays a
          number; a float-guessed time dim holds Number(raw): NaN for a string),
          value, hasValue (any coordinate dim non-NaN by JS isNaN -- a raw date
          string counts as NaN!), layout ([x, y] or [null, null]), placed
          (finite layout), drawn, symbol (as above: the node label is
          symbol.label)
        edges[] one per valid link: index, source, target (node data
          indices), curveness (retrieve3(lineStyle.curveness, -null, 0): "-0"
          when unset = straight), original (the
          layout points before adjustEdge: [[x1, y1], [x2, y2]] plus the control
          point when curved), points (the final layout, after adjustEdge shortened
          it to the end symbols), drawn, line (null, or {shape {x1, y1, x2, y2,
          cpx1, cpy1, percent}, style, z, z2, zlevel, silent, paint}),
          fromSymbol / toSymbol (null, or {type, x, y, rotation, scaleX, scaleY,
          shape {x, y, width, height}, ignore, style, z, z2, zlevel, paint}),
          label (the edge label, on the line)
      pie:
        layout  coord (the coordinate fed to the calendar: series.coord, else
                series.center), coordFrom ('coord' | 'center'), refContainer
                (dataToLayout(coord).contentRect: NaN when out of range),
                viewRect (getLayoutRect(pie box params, refContainer)), cx, cy
                (the refContainer centre when coordFrom is 'center', else
                parsePercent(center, viewRect) + viewRect.x / y), r0, r
                (parsePercent(radius, min(viewRect w, h) / 2)), startAngle,
                endAngle, clockwise (after normalizeArcAngles)
        rows[] index, raw, value, name, layout {angle, startAngle, endAngle,
               clockwise, cx, cy, r0, r}, drawn, sector (null or {shape {cx,
               cy, r0, r, startAngle, endAngle, clockwise, cornerRadius}, style,
               z, z2, zlevel, silent, paint}), label
      LABEL (any host):
        text, lines (TSpan count), ignore (text.ignore / invisible), textConfig
        {position, distance, offset, rotation, inside, local}, layoutRect (the
        host rect the position is computed on: getBoundingRect then the host's
        global transform; null when textConfig has no position -- a pie label
        is placed by its own x / y), own {x, y, rotation, originX, originY,
        scaleX, scaleY} (the Text's own transformable), inner {x, y, rotation,
        originX, originY} (the innerTransformable), align, verticalAlign
        (author else computed else 'left' / 'top'), font, style {fill, stroke,
        lineWidth, opacity, backgroundColor}, inkDefault {fill, stroke,
        align, verticalAlign}, ink {fill, stroke, lineWidth, opacity} (what the
        TSpans draw), tspans [{text, x, y, textAlign, textBaseline}], z, z2,
        zlevel, silent, paint, guideLine (null or {points, style, z, z2, paint})
  guards[]  one per mutation of the transcription: id, mutation, named, changed,
            ok (named is a subset of changed), differs

-----------------------------------------------------------------------------
The transcription (checked against every recorded series, Object.is on every
field it produces) takes as INPUTS: each series option as fed merged over the
type's defaults (checked against upstream's own on the keys read), EVERY
calendar's {rect, sw, sh, lineWidth, orient, firstDay, range}, the series'
calendar index, the symbol visual colour per row, and the raw rows / nodes /
links. It reproduces: the time store (parseDataValue; the graph's guessOrdinal
dims), the calendar clamp and cell centre on civil day numbers, the drawn test
(NaN point, symbol 'none'), the symbol type / size / offset / rotation and the
path scale, z / z2 / zlevel, the ripple group transform, count, scale, z2, fill
/ stroke and animator delay / life / targets, the graph hasValue placement,
edge original points (+ curveness control point) and drawn test, and the pie
refContainer, viewRect (getLayoutRect), centre, radii and sector angles.
Labels, symbol path commands and styles beyond fill / stroke are RECORDED, not
transcribed (the label placement is checked against calculateTextPosition on
the recorded layoutRect).
Self-checks (any failure: nothing is written, exit 1): TZ is UTC; the
transcription reproduces every recorded series; every scatter / effectScatter /
graph point is the calendar cell centre recomputed independently from the
recorded calendar record; every pie centre is the centre of upstream's own
dataToLayout(coord).contentRect; the display list is sorted by (zlevel, z,
z2); the production build records every case identically; anchors; every guard
is ok; two generations in the process give identical bytes.
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
const PROD_PATH = DIST.replace(/echarts(\.min)?\.js$/, 'echarts.min.js');
const PROD = require(PROD_PATH);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-series-calendar.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;
const DAY = 86400000;

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

// ---------- zrender core/util.ts, in effect for plain JSON-born data ----------
const isArray = Array.isArray;
const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
function zrClone(source) {
  if (source == null || typeof source !== 'object') return source;
  if (isArray(source)) return source.map(zrClone);
  if (ArrayBuffer.isView(source)) return Array.from(source);
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
const json = v => (v === undefined ? null : zrClone(v));
const isItemObject = raw => isObject(raw) && !isArray(raw) && !(raw instanceof Date);
const dataItemValue = raw => (isItemObject(raw) ? raw.value : raw);
function chainGet(levels, key) {
  let v;
  for (let i = 0; i < levels.length; i++) {
    const o = levels[i];
    v = o && typeof o === 'object' ? o[key] : undefined;
    if (v != null) return v;
  }
  return v;
}
const PI = Math.PI;
const PI2 = PI * 2;
const RADIAN = PI / 180;
const pt = p => (p ? [p[0], p[1]] : null);

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================

// the series defaults on the keys the transcription reads (ScatterSeries / EffectScatterSeries / GraphSeries /
// PieSeries defaultOption)
const DEFAULTS = {
  scatter: { z: 2, symbolSize: 10 },
  effectScatter: { z: 2, symbolSize: 10, showEffectOn: 'render', rippleEffect: { period: 4, scale: 2.5, brushType: 'fill', number: 3 } },
  graph: { z: 2, symbol: 'circle', symbolSize: 10, lineStyle: { color: '#86878c', width: 1, opacity: 0.5 } },
  pie: { z: 2, left: 0, top: 0, right: 0, bottom: 0, center: ['50%', '50%'], radius: [0, '50%'], clockwise: true, startAngle: 90, endAngle: 'auto', padAngle: 0, minAngle: 0 },
};
const READ_KEYS = {
  scatter: ['z', 'zlevel', 'symbol', 'symbolSize', 'symbolRotate', 'symbolOffset'],
  effectScatter: ['z', 'zlevel', 'symbol', 'symbolSize', 'symbolRotate', 'symbolOffset', 'showEffectOn', 'rippleEffect'],
  graph: ['z', 'zlevel', 'symbol', 'symbolSize', 'symbolRotate', 'symbolOffset', 'lineStyle'],
  pie: ['z', 'zlevel', 'center', 'coord', 'radius', 'clockwise', 'startAngle', 'endAngle', 'padAngle', 'minAngle', 'roseType', 'left', 'top', 'right', 'bottom', 'width', 'height'],
};

// ---- util/number.ts parseDate(...).getTime() and dataValueHelper.ts parseDataValue, under TZ = UTC ----
const TIME_REG = /^(?:(\d{4})(?:[-\/](\d{1,2})(?:[-\/](\d{1,2})(?:[T ](\d{1,2})(?::(\d{1,2})(?::(\d{1,2})(?:[.,](\d+))?)?)?(Z|[\+\-]\d\d:?\d\d)?)?)?)?)?$/;
function parseDateTime(v) {
  if (typeof v === 'string') {
    const m = TIME_REG.exec(v);
    if (!m) return NaN;
    let hour = +m[4] || 0;
    if (m[8] && m[8].toUpperCase() !== 'Z') hour -= +m[8].slice(0, 3);
    return new Date(Date.UTC(+m[1], +(m[2] || 1) - 1, +m[3] || 1, hour, +(m[5] || 0), +m[6] || 0, m[7] ? +m[7].substring(0, 3) : 0)).getTime();
  }
  if (v == null) return NaN;
  return new Date(Math.round(v)).getTime();
}
// the store: parseDataValue(value, {type: 'time'}) / {type: 'float'}
function storeTime(v) {
  if (typeof v !== 'number' && v != null && v !== '-') v = parseDateTime(v);
  return v == null || v === '' ? NaN : Number(v);
}
const storeFloat = v => (v == null || v === '' ? NaN : Number(v));
// sourceHelper.ts guessOrdinal for a dim with no declared type: the first up-to-5 rows decide
function guessType(rows, k) {
  for (let i = 0; i < rows.length && i < 5; i++) {
    const val = dataItemValue(rows[i]);
    if (!isArray(val)) return 'float';
    const v = val[k];
    if (v != null && isFinite(Number(v)) && v !== '') return 'float';
    if (typeof v === 'string' && v !== '-') return 'ordinal';
  }
  return 'float';
}
const storeOf = (type, v) => (type === 'ordinal' ? v : type === 'time' ? storeTime(v) : storeFloat(v));

// ---- calendar-layout.js's civil-day transcription of Calendar.getDateInfo / dataToPoint / dataToLayout ----
const dnOf = t => Math.floor(t / DAY);
const weekday = dn => (((dn % 7) + 7) % 7 + 4) % 7;
const dayOf = (dn, fd) => Math.abs((weekday(dn) + 7 - fd) % 7);
// dataToPoint(data, clamp = true): data[0] only -> {skip, point}
function calendarPoint(cal, date, mut) {
  const S = dnOf(cal.startTime);
  const E = dnOf(cal.endTime);
  const fweek = dayOf(S, cal.firstDay);
  const t = parseDateTime(date); // getDateInfo: parseDate(date).getTime()
  if (Number.isNaN(t)) return { skip: 'time', point: [NaN, NaN] };
  if (!mut.clampOff) {
    if (!(t >= S * DAY)) return { skip: 'before', point: [NaN, NaN] };
    if (!(t < E * DAY + DAY)) return { skip: 'after', point: [NaN, NaN] };
  }
  const dn = dnOf(t);
  const nth = Math.floor((dn - S + fweek) / 7);
  const day = dayOf(dn, cal.firstDay);
  const { rect, sw, sh } = cal;
  const p = cal.orient === 'vertical' ? [rect.x + day * sw + sw / 2, rect.y + nth * sh + sh / 2] : [rect.x + nth * sw + sw / 2, rect.y + day * sh + sh / 2];
  return { skip: null, point: p };
}
// util/graphic.ts expandOrShrinkRect(rect, delta, shrink = true, noNegative = true)
function shrinkRect(r, delta) {
  const o = { x: r.x, y: r.y, width: r.width, height: r.height };
  const d = -Math.max(0, delta);
  const one = (xy, wh) => {
    const deltaSum = d + d;
    const oldSize = o[wh];
    o[wh] += deltaSum;
    const minSize = Math.max(0, Math.min(0, oldSize));
    if (o[wh] < minSize) {
      o[wh] = minSize;
      o[xy] += (d >= 0 ? -d : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * d / deltaSum : 0);
    } else {
      o[xy] -= d;
    }
  };
  one('x', 'width');
  one('y', 'height');
  return o;
}
// dataToLayout(coord): {rect, contentRect}
function calendarLayout(cal, coord, mut) {
  const c = calendarPoint(cal, isArray(coord) ? coord[0] : coord, mut);
  const r = { x: c.point[0] - cal.sw / 2, y: c.point[1] - cal.sh / 2, width: cal.sw, height: cal.sh };
  return { rect: r, contentRect: shrinkRect(r, cal.lw / 2) };
}

// ---- util/number.ts parsePositionOption / parsePositionSizeOption ----
function parsePercent(option, percentBase, percentOffset) {
  switch (option) {
    case 'center': case 'middle': option = '50%'; break;
    case 'left': case 'top': option = '0%'; break;
    case 'right': case 'bottom': option = '100%'; break;
  }
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * percentBase + (percentOffset || 0);
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}
// util/layout.ts getLayoutRect(positionInfo, containerRect), margin 0, no aspect
function getLayoutRect(p, c) {
  const margin = [0, 0, 0, 0];
  const cw = c.width;
  const ch = c.height;
  let left = parsePercent(p.left, cw);
  let top = parsePercent(p.top, ch);
  const right = parsePercent(p.right, cw);
  const bottom = parsePercent(p.bottom, ch);
  let width = parsePercent(p.width, cw);
  let height = parsePercent(p.height, ch);
  const vm = margin[2] + margin[0];
  const hm = margin[1] + margin[3];
  if (isNaN(width)) width = cw - right - hm - left;
  if (isNaN(height)) height = ch - bottom - vm - top;
  if (isNaN(left)) left = cw - right - width - hm;
  if (isNaN(top)) top = ch - bottom - height - vm;
  switch (p.left || p.right) {
    case 'center': left = cw / 2 - width / 2 - margin[3]; break;
    case 'right': left = cw - width - hm; break;
  }
  switch (p.top || p.bottom) {
    case 'middle': case 'center': top = ch / 2 - height / 2 - margin[0]; break;
    case 'bottom': top = ch - height - vm; break;
  }
  left = left || 0;
  top = top || 0;
  if (isNaN(width)) width = cw - hm - left - (right || 0);
  if (isNaN(height)) height = ch - vm - top - (bottom || 0);
  return { x: (c.x || 0) + left + margin[3], y: (c.y || 0) + top + margin[0], width, height };
}
// zrender normalizeArcAngles (core/PathProxy.ts)
function modPI2(radian) {
  const n = Math.round(radian / PI * 1e8) / 1e8;
  return (n % 2) * PI;
}
function normalizeArcAngles(angles, anticlockwise) {
  let s = modPI2(angles[0]);
  if (s < 0) s += PI2;
  const delta = s - angles[0];
  let e = angles[1];
  e += delta;
  if (!anticlockwise && e - s >= PI2) e = s + PI2;
  else if (anticlockwise && s - e >= PI2) e = s - PI2;
  else if (!anticlockwise && s > e) e = s + (PI2 - modPI2(s - e));
  else if (anticlockwise && s < e) e = s - (PI2 - modPI2(e - s));
  angles[0] = s;
  angles[1] = e;
}

// util/symbol.ts normalizeSymbolSize / normalizeSymbolOffset
function normalizeSymbolSize(s, mut) {
  if (!isArray(s)) s = [+s, +s];
  if (mut.sizeArrayOneDoubled && s.length === 1) return [s[0] || 0, s[0] || 0];
  return [s[0] || 0, s[1] || 0];
}
function normalizeSymbolOffset(o, size, mut) {
  if (o == null) return undefined;
  if (!isArray(o)) o = [o, o];
  return [parsePercent(o[0], size[0]) || 0, parsePercent(retrieve2(o[1], o[0]), mut.offsetBaseWidth ? size[0] : size[1]) || 0];
}

// one symbol (Symbol.ts / EffectSymbol.ts) at `point` for an item: the fields the record holds
function symbolOf(S, item, point, z, zlevel, mut) {
  const IT = isItemObject(item) ? item : {};
  const type = retrieve2(IT.symbol, S.symbol) || 'circle';
  const size = normalizeSymbolSize(retrieve2(IT.symbolSize, S.symbolSize), mut);
  const rot = retrieve2(IT.symbolRotate, S.symbolRotate);
  const rotation = mut.rotateDegrees ? (rot || 0) : (rot || 0) * PI / 180 || 0;
  const offset = normalizeSymbolOffset(retrieve2(IT.symbolOffset, S.symbolOffset), size, mut);
  const k = mut.sizeFull ? 1 : 2;
  const mp = mut.valueOffsets && IT.__value != null && isFinite(IT.__value) ? [point[0], point[1] + IT.__value] : point;
  // createSymbol: 'emptyXxx' -> the path type 'xxx' with an empty brush
  const empty = type.indexOf('empty') === 0;
  const pathType = empty ? type.substr(5, 1).toLowerCase() + type.substr(6) : type;
  return {
    x: mp[0], y: mp[1], type, pathType, emptyBrush: empty, size,
    path: { x: offset ? offset[0] : 0, y: offset ? offset[1] : 0, scaleX: size[0] / k, scaleY: size[1] / k, rotation },
    z, z2: mut.z2Zero ? 0 : 100, zlevel, offset, rotation,
  };
}

// scatter / effectScatter: inp {type, S (merged), cal, rows [{raw, color}], count}
function transcribePoints(inp, mut) {
  const S = inp.S;
  const cal = inp.cal;
  const z = mut.zDefault0 ? inp.userZ || 0 : S.z || 0;
  const zlevel = S.zlevel || 0;
  const valueType = guessType(inp.rows.map(r => r.raw), 1);
  const rows = inp.rows.map((R, idx) => {
    const raw = R.raw;
    const rv = dataItemValue(raw);
    must(isArray(rv), 'a scatter row that is not an array');
    const time = storeTime(rv[0]);
    const value = storeOf(valueType, rv[1]);
    const c = calendarPoint(cal, time, mut);
    let skip = c.skip;
    const point = c.point;
    const IT = Object.assign({}, isItemObject(raw) ? raw : {}, { __value: typeof value === 'number' ? value : NaN });
    const type = retrieve2(IT.symbol, S.symbol) || 'circle';
    if (skip == null && mut.valueSkips && isNaN(value)) skip = 'value';
    if (skip == null && type === 'none') skip = 'none';
    const out = { time, value, point: [point[0], point[1]], drawn: skip == null, skip };
    if (skip != null) {
      out.symbol = null;
      if (inp.type === 'effectScatter') out.effect = null;
      return out;
    }
    const sy = symbolOf(S, IT, point, z, zlevel, mut);
    out.symbol = { x: sy.x, y: sy.y, type: sy.type, pathType: sy.pathType, emptyBrush: sy.emptyBrush, size: sy.size, path: sy.path, z: sy.z, z2: sy.z2, zlevel: sy.zlevel };
    if (inp.type === 'effectScatter') {
      const RE = [isItemObject(raw) ? raw.rippleEffect : undefined, S.rippleEffect];
      const showEffectOn = S.showEffectOn;
      const rippleScale = chainGet(RE, 'scale');
      const brushType = chainGet(RE, 'brushType');
      const period = chainGet(RE, 'period') * 1000;
      const number = chainGet(RE, 'number');
      const effectOffset = idx / inp.count;
      const rippleColor = chainGet(RE, 'color');
      const color = R.color;
      const eff = { showEffectOn, brushType, rippleScale, period, number, effectOffset, rippleColor: json(rippleColor), color,
        group: { x: sy.offset ? sy.offset[0] : 0, y: sy.offset ? sy.offset[1] : 0, scaleX: mut.rippleGroupUnscaled ? 1 : sy.size[0], scaleY: mut.rippleGroupUnscaled ? 1 : sy.size[1], rotation: sy.rotation },
        ripples: [] };
      if (showEffectOn === 'render') {
        const col = rippleColor || color;
        for (let i = 0; i < number; i++) {
          const s0 = mut.rippleFinal ? rippleScale / 2 : 0.5;
          const delay = -i / number * period + effectOffset;
          eff.ripples.push({ type: sy.pathType, scaleX: s0, scaleY: s0, fill: brushType === 'fill' ? col : null, stroke: brushType === 'stroke' ? col : null,
            z, z2: mut.rippleZ2Same ? 100 : 99, zlevel,
            anim: [{ target: '', delay, life: period, to: rippleScale / 2 }, { target: 'style', delay, life: period, to: 0 }] });
        }
      }
      out.effect = eff;
    }
    return out;
  });
  return { z, zlevel, rows };
}

// graph: inp {S, cal, nodes [{raw, color}], links [{source, target (node indices), raw}]}
function transcribeGraph(inp, mut) {
  const S = inp.S;
  const cal = inp.cal;
  const z = mut.zDefault0 ? inp.userZ || 0 : S.z || 0;
  const zlevel = S.zlevel || 0;
  const raws = inp.nodes.map(n => n.raw);
  const types = mut.graphTimeTyped ? ['time', guessType(raws, 1)] : [guessType(raws, 0), guessType(raws, 1)];
  const nodes = inp.nodes.map(N => {
    const rv = dataItemValue(N.raw);
    const vals = [0, 1].map(k => storeOf(types[k], isArray(rv) ? rv[k] : k === 0 ? rv : undefined));
    const nan = vals.map(v => isNaN(v)); // the global isNaN: a raw string that is not numeric is NaN
    const hasValue = mut.graphAllDims ? !nan[0] && !nan[1] : !nan[0] || !nan[1];
    const layout = hasValue ? calendarPoint(cal, vals[0], mut).point : [NaN, NaN];
    const placed = !isNaN(layout[0]) && !isNaN(layout[1]);
    const IT = Object.assign({}, isItemObject(N.raw) ? N.raw : {}, { __value: typeof vals[1] === 'number' ? vals[1] : NaN });
    const type = retrieve2(IT.symbol, S.symbol) || 'circle';
    const drawn = placed && type !== 'none';
    const sy = drawn ? symbolOf(S, IT, layout, z, zlevel, mut) : null;
    return { time: vals[0], value: vals[1], hasValue, layout: [layout[0], layout[1]], placed, drawn,
      symbol: sy && { x: sy.x, y: sy.y, type: sy.type, pathType: sy.pathType, emptyBrush: sy.emptyBrush, size: sy.size, path: sy.path, z: sy.z, z2: sy.z2, zlevel: sy.zlevel } };
  });
  const edges = inp.links.map(L => {
    const cv = mut.noCurve ? 0 : retrieve2(chainGet([L.raw && L.raw.lineStyle, S.lineStyle], 'curveness'), -0);
    const p1 = nodes[L.source].layout.slice();
    const p2 = nodes[L.target].layout.slice();
    const pts = [p1, p2];
    if (+cv) pts.push([(p1[0] + p2[0]) / 2 - (p1[1] - p2[1]) * cv, (p1[1] + p2[1]) / 2 - (p2[0] - p1[0]) * cv]);
    const drawn = !(isNaN(p1[0]) || isNaN(p1[1]) || isNaN(p2[0]) || isNaN(p2[1]));
    return { curveness: cv, original: pts, drawn };
  });
  return { z, zlevel, dimensionTypes: types, nodes, edges };
}

// pie: inp {S, cal, rows [raw]}
function transcribePie(inp, mut) {
  const S = inp.S;
  const cal = inp.cal;
  const z = mut.zDefault0 ? inp.userZ || 0 : S.z || 0;
  const zlevel = S.zlevel || 0;
  must(!S.roseType && !S.minAngle && !S.padAngle, 'the transcription does no roseType / minAngle / padAngle');
  const coordFrom = S.coord != null ? 'coord' : 'center';
  const coord = S.coord != null ? S.coord : S.center;
  const lay = calendarLayout(cal, coord, mut);
  const refContainer = mut.pieRect ? lay.rect : lay.contentRect;
  const refPoint = [refContainer.x + refContainer.width / 2, refContainer.y + refContainer.height / 2];
  const viewRect = getLayoutRect({ left: S.left, top: S.top, right: S.right, bottom: S.bottom, width: S.width, height: S.height }, refContainer);
  let center;
  if (coordFrom === 'center' && !mut.pieCenterViewRect) center = refPoint;
  else {
    const c = isArray(S.center) ? S.center : [S.center, S.center];
    center = mut.pieCenterViewRect && coordFrom === 'center' ? [parsePercent('50%', viewRect.width) + viewRect.x, parsePercent('50%', viewRect.height) + viewRect.y]
      : [parsePercent(c[0], viewRect.width) + viewRect.x, parsePercent(c[1], viewRect.height) + viewRect.y];
  }
  let radius = S.radius;
  if (!isArray(radius)) radius = [0, radius];
  const width = parsePercent(viewRect.width, W);
  const height = parsePercent(viewRect.height, H);
  const size = mut.percentMax ? Math.max(width, height) : Math.min(width, height);
  const r0 = parsePercent(radius[0], size / 2);
  const r = parsePercent(radius[1], size / 2);
  const cx = center[0];
  const cy = center[1];
  // pieLayout.ts
  let startAngle = (mut.startAngleSign ? 1 : -1) * S.startAngle * RADIAN;
  let endAngle = S.endAngle;
  endAngle = endAngle === 'auto' ? startAngle - PI2 : -endAngle * RADIAN;
  const values = inp.rows.map(raw => storeFloat(dataItemValue(raw)));
  let valid = 0;
  let sum = 0;
  for (const v of values) if (!isNaN(v)) { valid++; sum += v; }
  const unitRadian = Math.PI / (sum || valid) * 2;
  const clockwise = S.clockwise;
  const dir = clockwise ? 1 : -1;
  const angles = [startAngle, endAngle];
  normalizeArcAngles(angles, !clockwise);
  [startAngle, endAngle] = angles;
  let cur = startAngle;
  const rows = values.map((v, idx) => {
    if (isNaN(v)) return { value: v, layout: { angle: NaN, startAngle: NaN, endAngle: NaN, clockwise, cx, cy, r0, r } };
    const angle = v * unitRadian;
    must(!(angle < 0), 'a negative pie value');
    const e = cur + dir * angle;
    const o = { value: v, layout: { angle, startAngle: cur, endAngle: e, clockwise, cx, cy, r0, r } };
    cur = e;
    return o;
  });
  return { z, zlevel, layout: { coord: json(coord), coordFrom, refContainer, viewRect, cx, cy, r0, r, startAngle, endAngle, clockwise }, rows };
}

// ============================================================================
// Reading upstream
// ============================================================================
const seriesArray = option => (option.series == null ? [] : [].concat(option.series));
const calArray = o => (o.calendar == null ? [] : isArray(o.calendar) ? o.calendar : [o.calendar]);
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const sameRect = (a, b) => Object.is(a.x, b.x) && Object.is(a.y, b.y) && Object.is(a.width, b.width) && Object.is(a.height, b.height);
const m6 = t => (t ? Array.from(t).slice(0, 6) : null);

// ---- zrender PathProxy decode ----
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
const pathOf = el => {
  if (!el.path) el.getBoundingRect();
  if (!el.path.data || el.path.len() === 0) { el.path = null; el.getBoundingRect(); }
  return Array.prototype.slice.call(el.path.data, 0, el.path.len());
};

function ownStyle(s) {
  const r = {};
  for (const k of Object.keys(s).sort()) {
    if (k === 'blend' && s.blend == null) continue;
    if (k === 'text') continue;
    const v = s[k];
    r[k] = v === undefined ? null : typeof v === 'object' && v !== null && !isArray(v) ? '(object)' : zrClone(v);
  }
  return r;
}

// zr contain/text.ts calculateTextPosition (as heatmap-calendar.js)
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
  if (textPosition instanceof Array) {
    x += zrParsePercent(textPosition[0], rect.width);
    y += zrParsePercent(textPosition[1], rect.height);
  } else {
    switch (textPosition) {
      case 'left': x -= distance; y += halfHeight; break;
      case 'right': x += distance + width; y += halfHeight; break;
      case 'top': x += width / 2; y -= distance; break;
      case 'bottom': x += width / 2; y += height + distance; break;
      case 'inside': x += width / 2; y += halfHeight; break;
      case 'insideLeft': x += distance; y += halfHeight; break;
      case 'insideRight': x += width - distance; y += halfHeight; break;
      case 'insideTop': x += width / 2; y += distance; break;
      case 'insideBottom': x += width / 2; y += height - distance; break;
      case 'insideTopLeft': x += distance; y += distance; break;
      case 'insideTopRight': x += width - distance; y += distance; break;
      case 'insideBottomLeft': x += distance; y += height - distance; break;
      case 'insideBottomRight': x += width - distance; y += height - distance; break;
    }
  }
  return { x, y };
}

function readLabel(host, displayIndex, classes) {
  const t = host.getTextContent();
  if (!t) return null;
  const s = t.style;
  must(!s.rich, 'a rich label');
  const kids = t.childrenRef();
  const spans = kids.filter(k => k.type === 'tspan');
  kids.forEach(k => classes.set(k, 'label'));
  classes.set(t, 'label');
  const txt = s.text == null ? null : String(s.text);
  let ink = null;
  if (spans.length) {
    const inks = spans.map(sp => ({ fill: sp.style.fill == null ? null : sp.style.fill, stroke: sp.style.stroke || null, lineWidth: sp.style.stroke ? sp.style.lineWidth : null, opacity: sp.style.opacity }));
    must(inks.every(k => JSON.stringify(k) === JSON.stringify(inks[0])), 'TSpans with different inks');
    ink = inks[0];
  }
  const tc = host.textConfig || {};
  let layoutRect = null;
  if (tc.position != null) {
    const BR = echarts.graphic.BoundingRect;
    const lr = tc.layoutRect ? BR.create(tc.layoutRect) : BR.create(host.getBoundingRect());
    if (!tc.local && host.transform) lr.applyTransform(host.transform);
    layoutRect = rect4(lr);
    // the placement is calculateTextPosition on that rect (+ offset)
    const c = calculateTextPosition(tc.position, tc.distance, layoutRect);
    const off = tc.offset || [0, 0];
    if (!t.ignore) must(Object.is(t.innerTransformable.x, c.x + off[0]) && Object.is(t.innerTransformable.y, c.y + off[1]), 'the label placement is not calculateTextPosition on the host rect');
  }
  const it = t.innerTransformable;
  const ds = t._defaultStyle || {};
  const has = k => k in s;
  const p = spans.length ? displayIndex.get(spans[0]) : undefined;
  const gl = host.getTextGuideLine && host.getTextGuideLine();
  let guideLine = null;
  if (gl) {
    classes.set(gl, 'labelLine');
    const gp = displayIndex.get(gl);
    guideLine = { ignore: !!gl.ignore, points: gl.shape.points ? gl.shape.points.map(pt) : null, style: ownStyle(gl.style), z: gl.z, z2: gl.z2, paint: gp === undefined ? null : gp };
  }
  return { text: txt, lines: spans.length, ignore: !!(t.ignore || t.invisible),
    textConfig: { position: json(tc.position), distance: json(tc.distance), offset: json(tc.offset), rotation: json(tc.rotation), inside: json(tc.inside), local: !!tc.local },
    layoutRect,
    own: { x: t.x, y: t.y, rotation: t.rotation, originX: t.originX, originY: t.originY, scaleX: t.scaleX, scaleY: t.scaleY },
    inner: it ? { x: it.x, y: it.y, rotation: it.rotation, originX: it.originX, originY: it.originY } : null,
    transform: m6(t.transform),
    align: s.align || ds.align || 'left', verticalAlign: s.verticalAlign || ds.verticalAlign || 'top',
    font: s.font,
    style: { fill: has('fill') ? json(s.fill) : null, stroke: has('stroke') ? json(s.stroke) : null, lineWidth: has('lineWidth') ? json(s.lineWidth) : null,
      opacity: json(s.opacity), backgroundColor: json(s.backgroundColor) },
    inkDefault: { fill: json(ds.fill), stroke: json(ds.stroke), align: json(ds.align), verticalAlign: json(ds.verticalAlign) }, ink,
    tspans: spans.map(sp => ({ text: sp.style.text, x: sp.style.x, y: sp.style.y, textAlign: sp.style.textAlign, textBaseline: sp.style.textBaseline })),
    z: t.z, z2: t.z2, zlevel: t.zlevel, silent: !!t.silent, paint: p === undefined ? null : p, guideLine };
}

// a symbol path element (a Symbol group's child 0) -> the record; symbolPaths collects the unit path per type
function readSymbolPath(el, displayIndex, classes, symbolPaths, cls) {
  classes.set(el, cls || 'symbol');
  const type = el.shape.symbolType;
  must(el.shape.x === -1 && el.shape.y === -1 && el.shape.width === 2 && el.shape.height === 2, 'a symbol not built in the -1..1 box');
  const cmds = JSON.stringify(decode(pathOf(el)));
  const key = type + (el.shape.symbolKeepAspect ? '|keepAspect' : '');
  if (symbolPaths[key] === undefined) symbolPaths[key] = cmds;
  else must(symbolPaths[key] === cmds, 'two ' + key + ' symbols with different paths');
  const p = displayIndex.get(el);
  return { type, emptyBrush: !!el.__isEmptyBrush, keepAspect: !!el.shape.symbolKeepAspect, x: el.x, y: el.y, scaleX: el.scaleX, scaleY: el.scaleY, rotation: el.rotation,
    transform: m6(el.transform), style: ownStyle(el.style), z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.isSilent(), paint: p === undefined ? null : p };
}
function readAnimators(el) {
  return (el.animators || []).map(a => {
    const tracks = {};
    for (const k of Object.keys(a._tracks)) tracks[k] = a._tracks[k].keyframes.map(f => [f.time, f.value]);
    return { target: a.targetName || '', loop: !!a._loop, delay: a._delay, life: a._maxTime, tracks };
  });
}

// the Symbol (or EffectSymbol) element of a row -> {symbol, effect}
function readSymbolEl(el, isEffect, data, idx, displayIndex, classes, symbolPaths) {
  for (let p = el.parent; p; p = p.parent) must(!p.transform || p.transform.join() === '1,0,0,1,0,0', 'a transformed ancestor');
  const symbolGroup = isEffect ? el.childAt(0) : el;
  if (isEffect) must(symbolGroup.x === 0 && symbolGroup.y === 0 && symbolGroup.scaleX === 1 && symbolGroup.scaleY === 1 && symbolGroup.rotation === 0, 'an effect symbol group with a transform');
  must(el.scaleX === 1 && el.scaleY === 1 && el.rotation === 0 && symbolGroup.childCount() === 1, 'a symbol group with a scale / rotation or several paths');
  const pathEl = symbolGroup.childAt(0);
  const pr = readSymbolPath(pathEl, displayIndex, classes, symbolPaths);
  const size = data.getItemVisual(idx, 'symbolSize');
  const sz = isArray(size) ? [size[0] || 0, size[1] || 0] : [+size || 0, +size || 0];
  const symbol = { x: el.x, y: el.y, type: symbolGroup.getSymbolType(), pathType: pr.type, emptyBrush: pr.emptyBrush, keepAspect: pr.keepAspect, size: sz,
    path: { x: pr.x, y: pr.y, scaleX: pr.scaleX, scaleY: pr.scaleY, rotation: pr.rotation },
    transform: pr.transform, style: pr.style, z: pr.z, z2: pr.z2, zlevel: pr.zlevel, silent: pr.silent, paint: pr.paint,
    label: readLabel(pathEl, displayIndex, classes) };
  if (!isEffect) return { symbol };
  const rg = el.childAt(1);
  const cfg = el._effectCfg;
  must(cfg, 'an effect symbol without its config');
  const ripples = rg.childrenRef().map(r => {
    const rr = readSymbolPath(r, displayIndex, classes, symbolPaths, 'ripple');
    return { type: rr.type, x: rr.x, y: rr.y, scaleX: rr.scaleX, scaleY: rr.scaleY, rotation: rr.rotation, style: rr.style, z: rr.z, z2: rr.z2, zlevel: rr.zlevel,
      silent: rr.silent, paint: rr.paint, anim: readAnimators(r) };
  });
  const effect = { showEffectOn: cfg.showEffectOn, brushType: cfg.brushType, rippleScale: cfg.rippleScale, period: cfg.period, number: cfg.rippleNumber,
    effectOffset: cfg.effectOffset, rippleColor: json(cfg.rippleEffectColor), color: json(cfg.color),
    group: { x: rg.x, y: rg.y, scaleX: rg.scaleX, scaleY: rg.scaleY, rotation: rg.rotation }, ripples };
  return { symbol, effect };
}

// the calendar record + the transcription's calendar input (as heatmap-calendar.js)
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

// the independent recomputation of a cell centre from the RECORDED calendar (no shared helper but the date parse)
function centreFromCalendarRecord(cal, date) {
  const t = parseDateTime(date);
  if (!(t >= cal.startTime && t < cal.endTime + DAY)) return null;
  const dn = Math.floor(t / DAY);
  const S = Math.floor(cal.startTime / DAY);
  const wd = d => ((d % 7) + 7 + 4) % 7;
  const row = d => Math.abs((wd(d) + 7 - cal.firstDay) % 7);
  must(row(S) === cal.fweek, 'the recomputed fweek differs from upstream');
  const nth = Math.floor((dn - S + row(S)) / 7);
  const [sw, sh] = cal.cellSize;
  return cal.orient === 'horizontal' ? [cal.rect.x + nth * sw + sw / 2, cal.rect.y + row(dn) * sh + sh / 2]
    : [cal.rect.x + row(dn) * sw + sw / 2, cal.rect.y + nth * sh + sh / 2];
}
const samePt = (a, b) => (a === null && b === null) || (a && b && Object.is(a[0], b[0]) && Object.is(a[1], b[1]));
function checkCentre(cal, date, point, what) {
  const re = centreFromCalendarRecord(cal.rec, date);
  if (re === null) must(isNaN(point[0]) && isNaN(point[1]), what + ': the recomputation has no cell but upstream has ' + point);
  else must(samePt(point, re), what + ': ' + JSON.stringify(point) + ' is not the recomputed cell centre ' + JSON.stringify(re));
}
function skipOfPoint(cs, time) {
  const p = cs.dataToPoint([time]);
  if (!isNaN(p[0]) && !isNaN(p[1])) return null;
  const di = cs.getDateInfo(time);
  if (Number.isNaN(di.time)) return 'time';
  return di.time < cs.getRangeInfo().start.time ? 'before' : 'after';
}

function readPoints(chart, sm, cal, displayIndex, classes, symbolPaths) {
  const data = sm.getData();
  const isEffect = sm.subType === 'effectScatter';
  const cs = sm.coordinateSystem;
  must(data.dimensions[0] === 'time' && data.dimensions[1] === 'value' && data.getDimensionInfo('time').type === 'time', 'scatter dims ' + data.dimensions);
  const rows = [];
  const inputs = [];
  for (let i = 0; i < data.count(); i++) {
    must(data.getRawIndex(i) === i, 'a filtered calendar series');
    const raw = data.getRawDataItem(i);
    const time = data.get('time', i);
    const value = data.get('value', i);
    const lay = data.getItemLayout(i);
    must(lay && lay.length === 2, 'row ' + i + ': no point layout');
    const point = [lay[0], lay[1]];
    // the point is dataToPoint([time, value]) = the cell centre, recomputed from the recorded calendar
    must(samePt(point, cs.dataToPoint([time, value])), 'row ' + i + ': the layout is not dataToPoint');
    checkCentre(cal, time, point, 'row ' + i);
    const el = data.getItemGraphicEl(i);
    const color = data.getItemVisual(i, 'style').fill;
    inputs.push({ raw: zrClone(raw), color });
    let skip = skipOfPoint(cs, time);
    if (skip == null && data.getItemVisual(i, 'symbol') === 'none') skip = 'none';
    must((skip == null) === !!el, 'row ' + i + ': drawn is not the SymbolDraw test (' + skip + ')');
    const row = { index: i, raw: json(raw), time, value, point, drawn: !!el, skip };
    if (el) {
      const r = readSymbolEl(el, isEffect, data, i, displayIndex, classes, symbolPaths);
      row.symbol = r.symbol;
      if (isEffect) row.effect = r.effect;
    } else {
      row.symbol = null;
      if (isEffect) row.effect = null;
    }
    rows.push(row);
  }
  return { rows, inputs };
}

function readGraph(chart, sm, cal, displayIndex, classes, symbolPaths) {
  const data = sm.getData();
  const edata = sm.getEdgeData();
  const cs = sm.coordinateSystem;
  must(data.dimensions[0] === 'time' && data.dimensions[1] === 'value', 'graph dims ' + data.dimensions);
  const nodes = [];
  const inputs = [];
  for (let i = 0; i < data.count(); i++) {
    const raw = data.getRawDataItem(i);
    const time = data.get('time', i);
    const value = data.get('value', i);
    const hasValue = !isNaN(time) || !isNaN(value);
    const lay = data.getItemLayout(i);
    const layout = [lay[0], lay[1]];
    if (hasValue) {
      must(samePt(layout, cs.dataToPoint([time, value])), 'node ' + i + ': the layout is not dataToPoint');
      checkCentre(cal, time, layout, 'node ' + i);
    } else must(isNaN(layout[0]) && isNaN(layout[1]), 'node ' + i + ': placed without a value');
    const placed = !isNaN(layout[0]) && !isNaN(layout[1]);
    const el = data.getItemGraphicEl(i);
    inputs.push({ raw: zrClone(raw), color: data.getItemVisual(i, 'style').fill });
    const node = { index: i, raw: json(raw), time: json(time), value, hasValue, layout, placed, drawn: !!el };
    node.symbol = el ? readSymbolEl(el, false, data, i, displayIndex, classes, symbolPaths).symbol : null;
    nodes.push(node);
  }
  const graph = sm.getGraph();
  const edges = [];
  const links = [];
  for (let i = 0; i < edata.count(); i++) {
    const edge = graph.getEdgeByIndex(i);
    const raw = edata.getRawDataItem(i);
    const pts = edata.getItemLayout(i);
    const orig = (pts && pts.__original) || pts;
    const el = edata.getItemGraphicEl(i);
    must(!sm.get('autoCurveness'), 'autoCurveness');
    // simpleLayoutEdge: retrieve3(lineStyle.curveness, -getCurvenessForEdge (null without autoCurveness: -0), 0)
    const cv = retrieve2(edge.getModel().get(['lineStyle', 'curveness']), -0);
    links.push({ source: edge.node1.dataIndex, target: edge.node2.dataIndex, raw: zrClone(raw) });
    const e = { index: i, source: edge.node1.dataIndex, target: edge.node2.dataIndex, curveness: cv,
      original: orig.map(pt), points: pts.map(pt), drawn: !!el, line: null, fromSymbol: null, toSymbol: null, label: null };
    if (el) {
      const line = el.childOfName('line');
      classes.set(line, 'edge');
      const lp = displayIndex.get(line);
      const sh = line.shape;
      e.line = { shape: { x1: sh.x1, y1: sh.y1, x2: sh.x2, y2: sh.y2, cpx1: json(sh.cpx1), cpy1: json(sh.cpy1), percent: sh.percent },
        style: ownStyle(line.style), z: line.z, z2: line.z2, zlevel: line.zlevel, silent: !!line.isSilent(), paint: lp === undefined ? null : lp };
      for (const nm of ['fromSymbol', 'toSymbol']) {
        const s = el.childOfName(nm);
        if (!s) continue;
        classes.set(s, 'edgeSymbol');
        const p = displayIndex.get(s);
        e[nm] = { type: s.shape.symbolType, x: s.x, y: s.y, rotation: s.rotation, scaleX: s.scaleX, scaleY: s.scaleY, shape: rect4(s.shape), ignore: !!s.ignore,
          style: ownStyle(s.style), z: s.z, z2: s.z2, zlevel: s.zlevel, paint: p === undefined ? null : p };
      }
      e.label = readLabel(line, displayIndex, classes);
    }
    edges.push(e);
  }
  return { nodes, edges, inputs, links };
}

function readPie(chart, sm, cal, displayIndex, classes) {
  const data = sm.getData();
  const cs = sm.coordinateSystem || sm.boxCoordinateSystem;
  must(cs && cs.type === 'calendar', 'a pie not on its calendar');
  const vdim = data.mapDimension('value');
  must(data.getDimensionInfo(vdim).type === 'float', 'a pie value dim ' + data.getDimensionInfo(vdim).type);
  const rows = [];
  const inputs = [];
  const layout0 = data.getItemLayout(0);
  const view = data.getLayout('viewRect');
  // upstream's own dataToLayout(coord).contentRect: its centre is the pie centre (coord from 'center')
  const coordOpt = sm.getShallow('coord', true);
  const coordFrom = coordOpt != null ? 'coord' : 'center';
  const coord = coordOpt != null ? coordOpt : sm.getShallow('center');
  const ref = cs.dataToLayout(coord);
  const refContainer = rect4(ref.contentRect);
  for (let i = 0; i < data.count(); i++) {
    const raw = data.getRawDataItem(i);
    inputs.push(zrClone(raw));
    const l = data.getItemLayout(i);
    const el = data.getItemGraphicEl(i);
    const row = { index: i, raw: json(raw), value: data.get(vdim, i), name: data.getName(i),
      layout: { angle: l.angle, startAngle: l.startAngle, endAngle: l.endAngle, clockwise: l.clockwise, cx: l.cx, cy: l.cy, r0: l.r0, r: l.r }, drawn: !!el, sector: null, label: null };
    if (el) {
      classes.set(el, 'sector');
      const sh = el.shape;
      const p = displayIndex.get(el);
      row.sector = { shape: { cx: sh.cx, cy: sh.cy, r0: sh.r0, r: sh.r, startAngle: sh.startAngle, endAngle: sh.endAngle, clockwise: sh.clockwise, cornerRadius: json(sh.cornerRadius) },
        style: ownStyle(el.style), z: el.z, z2: el.z2, zlevel: el.zlevel, silent: !!el.isSilent(), paint: p === undefined ? null : p };
      row.label = readLabel(el, displayIndex, classes);
    }
    rows.push(row);
  }
  const ld = { coord: json(coord), coordFrom, refContainer, viewRect: view ? rect4(view) : null,
    cx: layout0 ? layout0.cx : null, cy: layout0 ? layout0.cy : null, r0: layout0 ? layout0.r0 : null, r: layout0 ? layout0.r : null };
  // pieLayout's series-level data (startAngle / endAngle / clockwise after normalizeArcAngles): from the first sector
  const first = rows.find(r => !isNaN(r.layout.startAngle));
  ld.startAngle = first ? first.layout.startAngle : null;
  ld.clockwise = layout0 ? layout0.clockwise : null;
  if (coordFrom === 'center' && layout0) {
    must(Object.is(layout0.cx, refContainer.x + refContainer.width / 2) && Object.is(layout0.cy, refContainer.y + refContainer.height / 2), 'the pie centre is not the contentRect centre');
  }
  return { layout: ld, rows, inputs };
}

// the display list, run-length encoded by owner (as heatmap-calendar.js, with per-element classes)
function paintRuns(chart, list, cals, classes) {
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
    let x = el;
    let viaHost = false;
    let calKid = null;
    let o = null;
    let cls = null;
    while (x) {
      if (owners.has(x)) { o = owners.get(x); break; }
      if (calGroup.has(x)) calKid = x;
      if (cls == null && classes.has(x)) cls = classes.get(x);
      if (x.parent) x = x.parent;
      else if (x.__hostTarget) { viaHost = true; x = x.__hostTarget; } else x = null;
    }
    let rec;
    if (!o) rec = { owner: 'other', index: null, type: null, group: null };
    else if (o.owner === 'calendar') {
      must(calKid && !viaHost, 'a calendar element outside the classified children');
      rec = { owner: 'calendar', index: o.index, type: null, group: calGroup.get(calKid) };
    } else if (o.owner === 'series') {
      const g = cls === 'labelLine' ? 'labelLine' : viaHost ? 'label' : o.type === 'heatmap' ? 'cell' : cls || 'mark';
      rec = { owner: 'series', index: o.index, type: o.type, group: g };
    } else rec = { owner: 'component', index: o.index, type: o.type, group: viaHost ? 'label' : 'mark' };
    Object.assign(rec, { zlevel: el.zlevel, z: el.z, z2: el.z2 });
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
const RECORDED = ['scatter', 'effectScatter', 'graph', 'pie'];

function recordWith(E, def, optionText, side, symbolPaths) {
  const input = JSON.parse(optionText);
  return runChart(E, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const list = zr.storage.getDisplayList(true);
    const displayIndex = new Map();
    list.forEach((el, i) => displayIndex.set(el, i));
    const classes = new Map();
    const ground = { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() };
    const textStyle = json(ec.option.textStyle);
    const cals = [];
    ec.eachComponent('calendar', (cm, ci) => cals.push(readCalendar(cm, ci, calArray(input)[ci])));
    must(cals.length === calArray(input).length, 'calendar count ' + cals.length);
    const calIndexOf = cs => {
      const k = cals.findIndex(c => c.cs === cs);
      return k < 0 ? null : k;
    };
    let nRecorded = 0;
    const series = seriesArray(input).map((opt, si) => {
      const sm = ec.getSeriesByIndex(si);
      must(sm && sm.subType === opt.type, 'series ' + si + ' is not a ' + opt.type);
      const calIndex = calIndexOf(sm.coordinateSystem || sm.boxCoordinateSystem);
      const recorded = RECORDED.includes(opt.type);
      const base = { seriesIndex: si, type: opt.type, name: opt.name == null ? null : String(opt.name), recorded, calendarIndex: calIndex };
      if (!recorded) return base;
      nRecorded++;
      must(calIndex != null, 'a ' + opt.type + ' not on a calendar');
      const data = sm.getData();
      const filtered = ec.isSeriesFiltered(sm);
      const st = data.getVisual('style');
      const color = st ? st[data.getVisual('drawType')] : null;
      const S = zrMerge(zrClone(opt), DEFAULTS[opt.type]);
      for (const k of READ_KEYS[opt.type]) {
        must(JSON.stringify(json(sm.option[k])) === JSON.stringify(json(S[k])), 'series ' + si + ': the option ' + k + ' is not the fed option over the defaults: ' + JSON.stringify(sm.option[k]));
      }
      const z = sm.get('z') || 0;
      const zlevel = sm.get('zlevel') || 0;
      const sr = Object.assign(base, { filtered, color: json(color), z, zlevel, dimensions: data.dimensions.slice(), dimensionTypes: data.dimensions.map(d => data.getDimensionInfo(d).type), count: data.count() });
      if (filtered) return sr;
      const cal = cals[calIndex];
      const key = def.id + '/' + si;
      let inp;
      let tr;
      if (opt.type === 'scatter' || opt.type === 'effectScatter') {
        const r = readPoints(chart, sm, cal, displayIndex, classes, symbolPaths);
        sr.rows = r.rows;
        inp = { type: opt.type, S, count: data.count(), rows: r.inputs };
        tr = transcribePoints;
      } else if (opt.type === 'graph') {
        const r = readGraph(chart, sm, cal, displayIndex, classes, symbolPaths);
        sr.nodes = r.nodes;
        sr.edges = r.edges;
        inp = { S, nodes: r.inputs, links: r.links };
        tr = transcribeGraph;
      } else {
        const r = readPie(chart, sm, cal, displayIndex, classes);
        sr.layout = r.layout;
        sr.rows = r.rows;
        inp = { S, rows: r.inputs };
        tr = transcribePie;
      }
      inp.userZ = opt.z;
      const cin = cals.map(k => k.inp);
      const run = mut => {
        try {
          return tr(Object.assign(zrClone(inp), { cal: cin[mut.calendarZero ? 0 : calIndex] }), mut);
        } catch (e) {
          if (e instanceof OracleError && !Object.keys(mut).length) throw e;
          return { threw: String(e.message) };
        }
      };
      side[key] = { type: opt.type, base: run({}), muts: {} };
      for (const gd of GUARDS) side[key].muts[gd.id] = run(gd.mut);
      return sr;
    });
    must(nRecorded > 0, 'no recorded series');
    const runs = paintRuns(chart, list, cals, classes);
    return { ground, textStyle, calendars: cals.map(c => c.rec), paintRuns: runs, series };
  });
}

function recordCase(def, side, symbolPaths) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  let productionBuild = false;
  let devError = null;
  let base;
  let local = {};
  try {
    base = recordWith(echarts, def, optionText, local, symbolPaths);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    devError = String(e.message);
    local = {};
    base = recordWith(PROD, def, optionText, local, symbolPaths);
    productionBuild = true;
  }
  must(!!def.prod === productionBuild, productionBuild ? 'the development build threw (' + devError + ') although the case is not marked prod' : 'expected the development build to throw');
  if (!productionBuild) {
    const p = recordWith(PROD, def, optionText, {}, {});
    must(JSON.stringify(sanitize(p)) === JSON.stringify(sanitize(base)), 'the production build records differently');
  }
  Object.assign(side, local);
  return Object.assign({ id: def.id, note: def.note, gallery: def.gallery || null, option: def.gallery ? null : JSON.parse(optionText),
    productionBuild, devError }, base);
}

// ============================================================================
// The cases
// ============================================================================
const pad2 = n => (n < 10 ? '0' + n : '' + n);
const feb = d => '2017-02-' + pad2(d);
const SYMBOLS = ['circle', 'rect', 'roundRect', 'triangle', 'diamond', 'pin', 'arrow', 'none', 'emptyCircle'];
const calFeb = extra => Object.assign({ range: '2017-02', cellSize: 40, left: 60, top: 60 }, extra || {});
const one = (calendar, series, extra) => Object.assign({ animation: false, calendar, series: [].concat(series) }, extra || {});

const CASES = [
  { id: 'S1', note: "scatter symbol types on 40 px cells, symbolSize 16, one item each Feb 1..9: circle, rect, roundRect, triangle, diamond, pin, arrow, 'none' (NOT drawn: skip 'none'), emptyCircle (fill '#fff' + stroke = the colour, lineWidth 2); every symbol a unit -1..1 path scaled by size / 2 (8) at the cell centre, z2 100, series itemStyle opacity default 0.8",
    option: one(calFeb(), { type: 'scatter', coordinateSystem: 'calendar', symbolSize: 16, data: SYMBOLS.map((s, k) => ({ value: [feb(k + 1), k + 1], symbol: s })) }) },
  { id: 'S2', note: "symbolSize / symbolRotate / symbolOffset: series symbolSize [20, 10], symbolRotate 45, symbolOffset [5, '-50%'] (y = -50% of the HEIGHT 10 = -5); items: symbolSize 6, [8] (a one-element array: [8, 0] -- the height is 0), [12, 18], 0 (drawn, scale 0), '14' (a string: +'14'), symbolRotate -30, symbolRotate 0, symbolOffset '25%' (both = 25% of each size), symbolOffset [0, 10], symbol 'rect' with symbolRotate 90",
    option: one(calFeb(), { type: 'scatter', coordinateSystem: 'calendar', symbolSize: [20, 10], symbolRotate: 45, symbolOffset: [5, '-50%'],
      data: [[feb(1), 1], { value: [feb(2), 2], symbolSize: 6 }, { value: [feb(3), 3], symbolSize: [8] }, { value: [feb(4), 4], symbolSize: [12, 18] }, { value: [feb(5), 5], symbolSize: 0 },
        { value: [feb(6), 6], symbolSize: '14' }, { value: [feb(7), 7], symbolRotate: -30 }, { value: [feb(8), 8], symbolRotate: 0 }, { value: [feb(9), 9], symbolOffset: '25%' },
        { value: [feb(10), 10], symbolOffset: [0, 10] }, { value: [feb(11), 11], symbol: 'rect', symbolRotate: 90 }] }) },
  { id: 'S3', note: "scatter data forms, labels shown with the DEFAULT text (the value dim: '-' prints '-'): [date, 5]; '-' value (DRAWN: the value is ignored); null value (drawn); a date-only row [date] (drawn); '2017-01-31' (before) and '2017-03-01' (after: not drawn); 'garbage' and '' (NaN time: not drawn); three rows on Feb 5 ('2017-02-05', '2017-02-05 18:00', the timestamp) -- all drawn at the same centre, data order; a timestamp Feb 20 00:00Z + 0.4 (rounded); '2017-02-28 23:59:59' (drawn); second series: label formatter '{c}' (the raw array), position 'right', on the same days",
    option: one(calFeb(), [{ type: 'scatter', coordinateSystem: 'calendar', label: { show: true },
      data: [[feb(1), 5], [feb(2), '-'], [feb(3), null], [feb(4)], ['2017-01-31', 1], ['2017-03-01', 2], ['garbage', 3], ['', 4], [feb(5), 6], [feb(5) + ' 18:00', 7], [Date.UTC(2017, 1, 5), 8],
        [Date.UTC(2017, 1, 20) + 0.4, 9], ['2017-02-28 23:59:59', 10]] },
    { type: 'scatter', coordinateSystem: 'calendar', symbolSize: 6, label: { show: true, formatter: '{c}', position: 'right' }, data: [[feb(10), 1], [feb(11), '-'], ['2017-03-02', 3]] }]) },
  { id: 'S4', note: "scatter item styles and labels: series itemStyle {color '#c00', borderColor '#000', borderWidth 1, opacity 0.5}; items: itemStyle color '#0a0', opacity 1, borderWidth 3; labels: default position, 'inside', 'bottom' with distance 2, offset [4, -6], rotate 30, color '#00f' + fontSize 16",
    option: one(calFeb(), { type: 'scatter', coordinateSystem: 'calendar', symbolSize: 18, itemStyle: { color: '#c00', borderColor: '#000', borderWidth: 1, opacity: 0.5 }, label: { show: true },
      data: [[feb(1), 1], { value: [feb(2), 2], itemStyle: { color: '#0a0' } }, { value: [feb(3), 3], itemStyle: { opacity: 1, borderWidth: 3 } }, { value: [feb(4), 4], label: { position: 'inside' } },
        { value: [feb(5), 5], label: { position: 'bottom', distance: 2 } }, { value: [feb(6), 6], label: { offset: [4, -6] } }, { value: [feb(7), 7], label: { rotate: 30 } },
        { value: [feb(8), 8], label: { color: '#00f', fontSize: 16 } }] }) },
  { id: 'E1', note: "effectScatter, rippleEffect brushType 'stroke' (defaults scale 2.5, period 4 s, number 3): the static frame = the symbol (z2 100) + 3 ripple rings at scale 0.5 in a ripple group scaled by the symbol size (net radius = the symbol radius), stroke = the colour, no fill, z2 99, silent; rows Feb 6, Feb 7 (item rippleEffect {number 5, scale 1.5}), '2017-03-01' (after: nothing), '-' value on Feb 8 (drawn); symbolSize 12; labels shown",
    option: one(calFeb(), { type: 'effectScatter', coordinateSystem: 'calendar', symbolSize: 12, rippleEffect: { brushType: 'stroke' }, label: { show: true },
      data: [[feb(6), 5], { value: [feb(7), 1], rippleEffect: { number: 5, scale: 1.5 } }, ['2017-03-01', 2], [feb(8), '-']] }) },
  { id: 'E2', note: "effectScatter brushType 'fill', rippleEffect {scale 4, number 2, period 2, color '#f0f'} (the ripples fill with '#f0f', the symbol keeps its colour), symbolSize [12, 8], symbolOffset [3, 3] and symbolRotate 30 (the ripple GROUP takes the offset and rotation), itemStyle color '#123', zlevel 1 (symbols and ripples on a layer of their own)",
    option: one(calFeb(), { type: 'effectScatter', coordinateSystem: 'calendar', zlevel: 1, symbolSize: [12, 8], symbolOffset: [3, 3], symbolRotate: 30, itemStyle: { color: '#123' },
      rippleEffect: { brushType: 'fill', scale: 4, number: 2, period: 2, color: '#f0f' }, data: [[feb(13), 1], [feb(14), 2], [feb(15), 3]] }) },
  { id: 'E3', note: "effectScatter showEffectOn 'emphasis': NO ripples in the static frame (they start on hover); symbol 'diamond', series z 3",
    option: one(calFeb(), { type: 'effectScatter', coordinateSystem: 'calendar', showEffectOn: 'emphasis', symbol: 'diamond', z: 3, data: [[feb(20), 1], [feb(21), 2]] }) },
  { id: 'G1', note: "graph on a calendar, 5 nodes 4 links, edgeSymbol ['circle', 'arrow'] size [6, 10], labels: the first node's date is a STRING, so the graph's time dim is guessed ORDINAL and keeps raw strings (isNaN('2017-02-01') is true): node 0 [Feb 1, 5] placed via its value; node 1 [Feb 3, '-'] NOT placed (both dims NaN by isNaN: no symbol, its edge not drawn); node 2 ['garbage', 3] hasValue (the value) but dataToPoint NaN: not placed; node 3 [a timestamp (Feb 10), '-'] placed (a raw number is not NaN); node 4 [Feb 15, 8] placed. Links 0>1 (not drawn), 0>4, 4>3 (lineStyle curveness 0.2: a control point), 2>3 (not drawn); the edges shortened to the end symbols by adjustEdge",
    option: one(calFeb(), { type: 'graph', coordinateSystem: 'calendar', symbolSize: 14, edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: [6, 10], label: { show: true },
      data: [[feb(1), 5], [feb(3), '-'], ['garbage', 3], [Date.UTC(2017, 1, 10), '-'], [feb(15), 8]],
      links: [{ source: 0, target: 1 }, { source: 0, target: 4 }, { source: 4, target: 3, lineStyle: { curveness: 0.2 } }, { source: 2, target: 3 }] }) },
  { id: 'G2', note: "graph whose FIRST node date is a timestamp: the time dim is guessed FLOAT, so the later string dates are Number('2017-02-05') = NaN -- those nodes have a value (hasValue) but dataToPoint(NaN) is NaN: not placed; only the timestamp nodes land. Named nodes with labels (the default formatter '{b}': the name), series symbol 'rect', itemStyle color '#0a0', lineStyle {color '#000', width 2}",
    option: one(calFeb(), { type: 'graph', coordinateSystem: 'calendar', symbol: 'rect', itemStyle: { color: '#0a0' }, lineStyle: { color: '#000', width: 2 }, label: { show: true },
      data: [{ name: 'a', value: [Date.UTC(2017, 1, 2), 1] }, { name: 'b', value: [feb(5), 2] }, { name: 'c', value: [Date.UTC(2017, 1, 22, 12), 3] }],
      links: [{ source: 'a', target: 'b' }, { source: 'a', target: 'c' }] }) },
  { id: 'P1', note: "pies on a NON-SQUARE cell (cellSize [60, 40], calendar borderWidth 1: contentRect 59 x 39, min 39): A center Feb 1 radius 12 (absolute), labels inside '{c}'; B Feb 8 radius '80%' (of 39 / 2); C Feb 15 radius ['30%', '90%']; D center '2017-03-05' (OUT of range: dataToLayout clamps x / y to NaN but keeps the cell size -> NaN centre, viewRect 0, 0, 59, 39); E NO center (the default ['50%', '50%'] is fed to the calendar as a date: NaN); F coord '2017-02-22' + center ['30%', '70%'] (a coord: the centre is the percent of the cell's contentRect); G center Feb 9 with width '50%' (the viewRect shrinks to the left half: the radius '100%' follows it, the centre does NOT); H center Feb 10, startAngle 0, clockwise false; values with a '-' (NaN: no angle)",
    option: one(calFeb({ cellSize: [60, 40] }), [
      { type: 'pie', coordinateSystem: 'calendar', center: feb(1), radius: 12, label: { show: true, position: 'inside', formatter: '{c}' }, data: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }, { name: 'z', value: 3 }] },
      { type: 'pie', coordinateSystem: 'calendar', center: feb(8), radius: '80%', label: { show: false }, data: [3, 1, 4, 1, 5] },
      { type: 'pie', coordinateSystem: 'calendar', center: feb(15), radius: ['30%', '90%'], label: { show: false }, data: [2, '-', 7] },
      { type: 'pie', coordinateSystem: 'calendar', center: '2017-03-05', radius: 10, label: { show: false }, data: [1, 1] },
      { type: 'pie', coordinateSystem: 'calendar', label: { show: false }, data: [1, 2] },
      { type: 'pie', coordinateSystem: 'calendar', coord: '2017-02-22', center: ['30%', '70%'], radius: '40%', label: { show: false }, data: [1, 2] },
      { type: 'pie', coordinateSystem: 'calendar', center: '2017-02-09', width: '50%', radius: '100%', label: { show: false }, data: [5, 5] },
      { type: 'pie', coordinateSystem: 'calendar', center: '2017-02-10', radius: '70%', startAngle: 0, clockwise: false, label: { show: false }, data: [1, 3] }]) },
  { id: 'P2', note: "two calendars (ids 'jan' January 30 px, 'feb' February [50, 30] borderWidth 3): pies by calendarIndex 1, by calendarId 'jan', and with neither (calendar 0); radius '100%' (the contentRect of the [50, 30] cell with a 1.5 inset: 47 x 27 -> 13.5); outside labels with names",
    option: { animation: false, calendar: [{ id: 'jan', range: '2017-01', cellSize: 30, top: 40 }, { id: 'feb', range: '2017-02', cellSize: [50, 30], top: 330, itemStyle: { borderWidth: 3 } }],
      series: [{ type: 'pie', coordinateSystem: 'calendar', calendarIndex: 1, center: feb(14), radius: '100%', data: [{ name: 'p', value: 2 }, { name: 'q', value: 1 }] },
        { type: 'pie', coordinateSystem: 'calendar', calendarId: 'jan', center: '2017-01-18', radius: '90%', label: { show: false }, data: [1, 1, 1] },
        { type: 'pie', coordinateSystem: 'calendar', center: '2017-01-04', radius: 8, label: { show: false }, data: [4, 1] }] } },
  { id: 'Z1', note: "paint order on ONE calendar (z 2): a heatmap (cells z2 1, not recorded here), a pie (sectors z2 2), a graph (edges z2 0: ABOVE the day rects, BELOW the heatmap cells; nodes z2 100), an effectScatter (ripples 99, symbol 100) and a scatter (symbols 100, labels 102) -- split lines 20 and calendar names 30 in between",
    option: { animation: false, visualMap: { min: 0, max: 10, show: false, seriesIndex: 0 }, calendar: calFeb(),
      series: [{ type: 'heatmap', coordinateSystem: 'calendar', data: [[feb(1), 3], [feb(2), 6], [feb(3), 9], [feb(8), 4], [feb(9), 7]] },
        { type: 'pie', coordinateSystem: 'calendar', center: feb(10), radius: 15, label: { show: false }, data: [1, 2] },
        { type: 'graph', coordinateSystem: 'calendar', symbolSize: 8, data: [[feb(1), 1], [feb(9), 2]], links: [{ source: 0, target: 1 }] },
        { type: 'effectScatter', coordinateSystem: 'calendar', symbolSize: 8, data: [[feb(2), 1]] },
        { type: 'scatter', coordinateSystem: 'calendar', symbolSize: 8, label: { show: true }, data: [[feb(3), 1], [feb(8), 2]] }] } },
  { id: 'Z2', note: "z against the calendar: scatter z 1 (its symbols paint BELOW the calendar's day rects), scatter z 3 (above everything of the calendar), scatter zlevel 1; calendar z 2",
    option: { animation: false, calendar: calFeb(),
      series: [{ z: 1 }, { z: 3 }, { zlevel: 1 }].map((x, k) => Object.assign({ type: 'scatter', coordinateSystem: 'calendar', symbolSize: 20, label: { show: true }, data: [[feb(k + 1), k + 1]] }, x)) } },
];
for (const [name, note] of [
  ['calendar-charts', 'calendar-charts.json verbatim: graph series 0 on calendar 0 (Feb 2017 vertical: 7 nodes of Feb, 6 links, edgeSymbol arrow), effectScatter 2 on calendar 1 and scatter 3 on calendar 2 (365 rows of 2017 each: only the calendar\'s own month is drawn, the rest clamped \'before\' / \'after\'); heatmaps 1 and 4 paint only'],
  ['calendar-effectscatter', "calendar-effectscatter.json verbatim: dark ground '#404a59', two calendars (2016 H1 / H2), scatter 'Steps' on each (366 rows, the symbolSize callback DROPPED: the default 10), effectScatter 'Top 12' on each (zlevel 1, brushType 'stroke', itemStyle shadowBlur 10)"],
  ['calendar-graph', "calendar-graph.json verbatim: graph series 0 on the vertical Feb-Mar 2017 calendar (cellSize 40, firstDay 1), 7 nodes, symbolSize 15, itemStyle color 'yellow' + shadow, lineStyle '#D10E00'; the heatmap paints only"],
  ['calendar-pie', "calendar-pie.json verbatim: vertical Feb 2017 calendar with 80 x 80 cells, the label-only scatter (symbolSize 0, label offset [-30, -30]: the day number callback DROPPED, the default text is the value) and 28 pies, radius 30, labels inside '{c}'"],
  ['calendar-lunar', "calendar-lunar.json verbatim: the two label-only scatter series (symbolSize 0, silent, 365 rows [date, 1, lunar name, festival] of 2017 on a March 2017 calendar: all but March clamped; the formatter callbacks DROPPED: the default text is the value 1); the heatmap paints only"],
]) CASES.push({ id: 'G-' + name, gallery: name, note: note + ' (examples/advchart/gallery, JS callbacks dropped: fed as is)' });

// ============================================================================
// The guards
// ============================================================================
const GUARDS = [
  { id: 'z2-zero', mutation: 'the symbol z2 0 instead of 100', mut: { z2Zero: true }, named: ['S1', 'E1', 'G1', 'G-calendar-charts'] },
  { id: 'ripple-z2-same', mutation: 'the ripple z2 100 (as the symbol) instead of 99', mut: { rippleZ2Same: true }, named: ['E1', 'E2'] },
  { id: 'value-skips', mutation: "a NaN value ('-', null, missing) hides the point (the heatmap's rule)", mut: { valueSkips: true }, named: ['S3', 'E1'] },
  { id: 'value-offsets', mutation: 'the value takes part in the position (y + value)', mut: { valueOffsets: true }, named: ['S1', 'S3', 'E1', 'G1', 'G-calendar-pie'] },
  { id: 'clamp-off', mutation: 'dates outside the range placed (dataToPoint / dataToLayout without the clamp)', mut: { clampOff: true }, named: ['S3', 'E1', 'P1', 'G-calendar-charts', 'G-calendar-effectscatter', 'G-calendar-lunar'] },
  { id: 'pie-rect', mutation: 'the pie refContainer = dataToLayout().rect instead of contentRect', mut: { pieRect: true }, named: ['P1', 'P2'] },
  { id: 'percent-max', mutation: 'a percent radius against max(w, h) / 2 instead of min', mut: { percentMax: true }, named: ['P1', 'P2'] },
  { id: 'pie-center-viewrect', mutation: 'a centre-from-center pie centred on its viewRect instead of the contentRect centre', mut: { pieCenterViewRect: true }, named: ['P1'] },
  { id: 'start-angle-sign', mutation: 'startAngle not negated', mut: { startAngleSign: true }, named: ['P1', 'G-calendar-pie'] },
  { id: 'graph-all-dims', mutation: 'a graph node placed only when EVERY coordinate dim is non-NaN', mut: { graphAllDims: true }, named: ['G1'] },
  { id: 'graph-time-typed', mutation: "the graph time dim typed 'time' (string dates parsed in the store, as scatter)", mut: { graphTimeTyped: true }, named: ['G1', 'G2'] },
  { id: 'no-curve', mutation: 'edge curveness ignored', mut: { noCurve: true }, named: ['G1'] },
  { id: 'size-full', mutation: 'the path scale = symbolSize instead of symbolSize / 2', mut: { sizeFull: true }, named: ['S1', 'S2', 'G1'] },
  { id: 'size-array-one', mutation: 'a one-element symbolSize array doubled instead of [a, 0]', mut: { sizeArrayOneDoubled: true }, named: ['S2'] },
  { id: 'offset-base-width', mutation: 'a percent symbolOffset y against the width', mut: { offsetBaseWidth: true }, named: ['S2'] },
  { id: 'rotate-degrees', mutation: 'symbolRotate not converted to radians', mut: { rotateDegrees: true }, named: ['S2', 'E2'] },
  { id: 'ripple-final', mutation: 'the ripples at their LAST frame (rippleScale / 2) instead of the first (0.5)', mut: { rippleFinal: true }, named: ['E1', 'E2', 'G-calendar-effectscatter'] },
  { id: 'ripple-group-unscaled', mutation: 'the ripple group not scaled by the symbol size', mut: { rippleGroupUnscaled: true }, named: ['E1', 'E2'] },
  { id: 'calendar-zero', mutation: 'every series on calendar 0 (calendarIndex / calendarId ignored)', mut: { calendarZero: true }, named: ['P2', 'G-calendar-charts', 'G-calendar-effectscatter'] },
  { id: 'z-default-0', mutation: 'the series z default 0 instead of 2', mut: { zDefault0: true }, named: ['S1', 'P1', 'G1'] },
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
const pickSym = s => s && { x: s.x, y: s.y, type: s.type, pathType: s.pathType, emptyBrush: s.emptyBrush, size: s.size, path: s.path, z: s.z, z2: s.z2, zlevel: s.zlevel };
// the recorded fields the transcription produces, in the transcription's shape
function upstreamView(sr) {
  if (sr.type === 'scatter' || sr.type === 'effectScatter') {
    return { z: sr.z, zlevel: sr.zlevel, rows: sr.rows.map(r => {
      const o = { time: r.time, value: r.value, point: r.point, drawn: r.drawn, skip: r.skip, symbol: pickSym(r.symbol) };
      if (sr.type === 'effectScatter') {
        const e = r.effect;
        o.effect = e && { showEffectOn: e.showEffectOn, brushType: e.brushType, rippleScale: e.rippleScale, period: e.period, number: e.number, effectOffset: e.effectOffset,
          rippleColor: e.rippleColor, color: e.color, group: e.group,
          ripples: e.ripples.map(p => ({ type: p.type, scaleX: p.scaleX, scaleY: p.scaleY, fill: p.style.fill, stroke: p.style.stroke, z: p.z, z2: p.z2, zlevel: p.zlevel,
            anim: p.anim.map(a => ({ target: a.target, delay: a.delay, life: a.life, to: a.tracks[a.target === 'style' ? 'opacity' : 'scaleX'].slice(-1)[0][1] })) })) };
      }
      return o;
    }) };
  }
  if (sr.type === 'graph') {
    return { z: sr.z, zlevel: sr.zlevel, dimensionTypes: sr.dimensionTypes,
      nodes: sr.nodes.map(n => ({ time: n.time, value: n.value, hasValue: n.hasValue, layout: n.layout, placed: n.placed, drawn: n.drawn, symbol: pickSym(n.symbol) })),
      edges: sr.edges.map(e => ({ curveness: e.curveness, original: e.original, drawn: e.drawn })) };
  }
  const L = sr.layout;
  return { z: sr.z, zlevel: sr.zlevel, layout: { coord: L.coord, coordFrom: L.coordFrom, refContainer: L.refContainer, viewRect: L.viewRect, cx: L.cx, cy: L.cy, r0: L.r0, r: L.r,
    startAngle: L.startAngle, clockwise: L.clockwise }, rows: sr.rows.map(r => ({ value: r.value, layout: r.layout })) };
}
function transcribedView(t) {
  if (t.layout) {
    const L = t.layout;
    const first = t.rows.find(r => !isNaN(r.layout.startAngle));
    return { z: t.z, zlevel: t.zlevel, layout: { coord: L.coord, coordFrom: L.coordFrom, refContainer: L.refContainer, viewRect: L.viewRect, cx: L.cx, cy: L.cy, r0: L.r0, r: L.r,
      startAngle: first ? first.layout.startAngle : null, clockwise: L.clockwise }, rows: t.rows };
  }
  return t;
}
function seriesDiffs(sr, side, key, which) {
  const res = side[key];
  must(res, key + ': no transcription');
  const t = which ? res.muts[which] : res.base;
  if (t.threw) return [{ field: 'threw', upstream: null, mutated: t.threw }];
  const a = flat(sanitizeForDiff(upstreamView(sr)), 's', {});
  const b = flat(sanitizeForDiff(transcribedView(t)), 's', {});
  return diffFlat(a, b);
}
function sanitizeForDiff(v) {
  if (v === null || typeof v !== 'object') return v;
  if (isArray(v)) return v.map(sanitizeForDiff);
  const o = {};
  for (const k of Object.keys(v)) o[k] = sanitizeForDiff(v[k]);
  return o;
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    for (const sr of c.series) {
      if (!sr.recorded || sr.filtered) continue;
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, null);
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, +(process.env.ORACLE_NDIFF || 4)).map(x => JSON.stringify(x)).join('; '));
    }
  }
  // anchors
  const S = (id, si) => byId[id].series.find(s => s.seriesIndex === si);
  const s1 = S('S1', 0).rows;
  must(s1[0].point[0] === 60 + 40 / 2 && s1[0].point[1] === 60 + 3 * 40 + 20 && s1[0].symbol.path.scaleX === 8 && s1[0].symbol.z2 === 100 && s1[0].symbol.z === 2
    && s1[7].skip === 'none' && !s1[7].drawn && s1[8].symbol.style.fill === '#fff' && s1[8].symbol.style.lineWidth === 2, 'S1: Feb 1 at the cell centre (60 + 20, 60 + 3 * 40 + 20), scale 8, z2 100, none, emptyCircle');
  const s2 = S('S2', 0).rows;
  must(s2[0].symbol.path.y === -5 && s2[0].symbol.path.x === 5 && s2[2].symbol.size[1] === 0 && s2[4].symbol.path.scaleX === 0 && s2[4].drawn
    && Object.is(s2[7].symbol.path.rotation, 0) && s2[8].symbol.path.x === s2[8].symbol.size[0] * 0.25, 'S2: sizes / offsets');
  const s3 = S('S3', 0).rows;
  must(s3[1].drawn && s3[1].value !== s3[1].value && s3[2].drawn && s3[3].drawn && s3[4].skip === 'before' && s3[5].skip === 'after' && s3[6].skip === 'time' && s3[7].skip === 'time'
    && samePt(s3[8].point, s3[9].point) && samePt(s3[8].point, s3[10].point) && s3[1].symbol.label.text === '-', 'S3: data forms');
  const e1 = S('E1', 0).rows;
  must(e1[0].effect.ripples.length === 3 && e1[0].effect.ripples[0].z2 === 99 && e1[0].effect.ripples[0].scaleX === 0.5 && e1[0].effect.group.scaleX === 12
    && e1[0].effect.ripples[0].style.fill === null && e1[1].effect.ripples.length === 5 && e1[2].skip === 'after' && e1[3].drawn, 'E1: ripples');
  must(S('E3', 0).rows[0].effect.ripples.length === 0, 'E3: no ripples on emphasis');
  const g1 = S('G1', 0);
  must(g1.dimensionTypes[0] === 'ordinal' && g1.nodes[0].placed && !g1.nodes[1].placed && !g1.nodes[1].hasValue && g1.nodes[2].hasValue && !g1.nodes[2].placed && g1.nodes[3].placed
    && g1.nodes[4].placed && !g1.edges[0].drawn && g1.edges[1].drawn && g1.edges[2].original.length === 3 && !g1.edges[3].drawn, 'G1: graph placement');
  must(S('G2', 0).dimensionTypes[0] === 'float' && !S('G2', 0).nodes[1].placed && S('G2', 0).nodes[1].hasValue, 'G2: float time dim');
  const p1 = S('P1', 0).layout;
  must(p1.cx === 60 + 30 && p1.refContainer.width === 59 && p1.r === 12, 'P1: pie A centre / contentRect');
  must(S('P1', 1).layout.r === 39 / 2 * 0.8 && isNaN(S('P1', 3).layout.cx) && isNaN(S('P1', 4).layout.cx) && S('P1', 5).layout.coordFrom === 'coord', 'P1: percent radius, NaN, coord');
  must(byId.P2.series[0].calendarIndex === 1 && byId.P2.series[1].calendarIndex === 0 && byId.P2.series[2].calendarIndex === 0, 'P2: calendar reference');
  // paint order on one calendar (Z1): day 0 < graph edge 0 < heatmap cell 1 < pie 2 < split 20 < names 30 < ripple 99 < symbol 100 < label 102
  const z1 = byId.Z1.paintRuns.filter(r => r.zlevel === 0 && r.z === 2);
  const firstOf = pred => z1.findIndex(pred);
  const order = [r => r.owner === 'calendar' && r.group === 'day', r => r.type === 'graph' && r.group === 'edge', r => r.type === 'heatmap' && r.group === 'cell',
    r => r.type === 'pie' && r.group === 'sector', r => r.owner === 'calendar' && r.group === 'split', r => r.owner === 'calendar' && r.group === 'week',
    r => r.type === 'effectScatter' && r.group === 'ripple', r => r.type === 'scatter' && r.group === 'symbol', r => r.type === 'scatter' && r.group === 'label'].map(firstOf);
  must(order.every((k, i) => k >= 0 && (i === 0 || k > order[i - 1])), 'Z1: the paint order ' + order);
  // the symbol paths were collected
  must(['circle', 'rect', 'roundRect', 'triangle', 'diamond', 'pin', 'arrow'].every(t => out.symbolPaths[t]), 'symbol paths');
  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        if (!sr.recorded || sr.filtered) continue;
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
  const symbolPathsText = {};
  const cases = CASES.map(d => {
    try {
      return recordCase(d, side, symbolPathsText);
    } catch (e) {
      if (e instanceof OracleError) e.message = d.id + ': ' + e.message;
      throw e;
    }
  });
  const symbolPaths = {};
  for (const k of Object.keys(symbolPathsText).sort()) symbolPaths[k] = JSON.parse(symbolPathsText[k]);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED, tz: 'UTC',
    api: {
      update: "echarts.init(null, null, {renderer: 'svg', ssr: true, width: 800, height: 600}); setOption; zr.storage.getDisplayList(true) (transforms, updateInnerText, TSpan layout); no animation frame is ever stepped",
      points: "scatter / effectScatter: getData(): get('time' / 'value', i), getItemLayout(i) (= coordinateSystem.dataToPoint([time, value]), checked), getItemGraphicEl(i) = the Symbol group (EffectSymbol: [Symbol, ripple group]); the symbol path = group.childAt(0): shape.symbolType, x / y / scale / rotation, transform, style, z / z2 / zlevel, getTextContent(); ripples = rippleGroup children, their animators (_tracks keyframes, _delay, _maxTime, _loop); EffectSymbol._effectCfg",
      graph: "getData() (nodes: get('time' / 'value'), getItemLayout, getItemGraphicEl), getEdgeData() (getItemLayout = the points after adjustEdge, .__original before), getGraph().getEdgeByIndex(i).node1 / node2 .dataIndex, the edge Line group's children 'line' / 'fromSymbol' / 'toSymbol'",
      pie: "getData(): getItemLayout(i) {angle, startAngle, endAngle, clockwise, cx, cy, r0, r}, getLayout('viewRect'), getItemGraphicEl(i) = the Sector; coordinateSystem.dataToLayout(series.coord ?? series.center).contentRect (the refContainer, upstream's own call)",
      calendar: 'as heatmap-calendar.js: getRect, getCellWidth / Height, _lineWidth, getOrient, getFirstDayOfWeek, getRangeInfo, dataToPoint, getDateInfo',
      paint: 'zr.storage.getDisplayList(true); an element is owned by the first view group found climbing el.parent, then el.__hostTarget (a label Text / guide line -> its host); its group is the class the reader gave it (symbol / ripple / edge / edgeSymbol / sector / label / labelLine)',
      production: 'every case must record identically through dist/echarts.min.js',
    },
    notes: [
      'TIMEZONE: the script sets process.env.TZ = UTC before touching Date. Date strings are local = UTC here; a numeric timestamp lands on its UTC wall date only here (heatmap-calendar.js, calendar-layout.js).',
      'Scatter / effectScatter: the store dims are time (a TIME dim: strings parsed by parseDate) + value; the point is dataToPoint([time, value]) with the default clamp: data[0] only -- the VALUE IS IGNORED (a \'-\' / null / missing value is still drawn at the cell centre, its default label text is \'-\'); a NaN time or a date outside [first day, last day + 1 day) gives [NaN, NaN] and no symbol; symbol \'none\' gives no symbol either; a time of day, a timestamp and a date string of the same day all land on the same cell centre; duplicates all draw, data order. No clip (the calendar has no getArea).',
      'The symbol: a Symbol group at the point (scale 1) holding ONE path built by createSymbol(type, -1, -1, 2, 2) -- the unit box -- with scaleX / scaleY = symbolSize / 2, x / y = normalizeSymbolOffset(symbolOffset, size) (percent of that axis\' size), rotation = symbolRotate * PI / 180, z = series z (default 2), z2 = 100, zlevel = series zlevel; strokeNoScale true. normalizeSymbolSize: a number n -> [n, n]; a one-element array [a] -> [a, 0]; a string -> +s. Symbol paths per type are in symbolPaths. The label z2 is 102 (the running max z2 + 2).',
      "effectScatter: the EffectSymbol = [the Symbol, a ripple group]. The ripple group is scaled by the symbol SIZE (both axes; not size / 2), offset and rotated like the symbol; with showEffectOn 'render' it holds rippleEffect.number ripple paths of the same symbol type at scale 0.5 (so the static ripple matches the symbol exactly), z2 99, silent, fill = the colour ('fill') or stroke = the colour ('stroke', lineWidth default 1, strokeNoScale), colour = rippleEffect.color || the symbol colour. Each ripple loops two animators over period * 1000 ms: scale 0.5 -> rippleScale / 2 and opacity 1 -> 0, delay = -i / number * period + idx / count (the effectOffset is NOT scaled by the period: a fraction of a millisecond). With showEffectOn 'emphasis' the static frame has no ripples.",
      "Graph: the node data dims are 'time' and 'value' but NOT typed by the calendar (createGraphFromNodeEdge passes plain names): both are guessOrdinal-ed. A string date first -> the time dim is ORDINAL and keeps the raw string; simpleLayout's hasValue uses JS isNaN, which is true for a date string -- so a string-dated node is placed only when its VALUE is numeric (G1 node 1), while a timestamp-dated node is placed even with a '-' value (G1 node 3). A timestamp first -> the time dim is FLOAT and later string dates become NaN: unplaced (G2). A placed node lands on dataToPoint(date) = the cell centre (clamped). Edges: straight [p1, p2] (+ the curveness control point), not drawn when either end is NaN; adjustEdge then shortens the points to the end symbols (the fixture keeps both).",
      "Graph paint order: edge lines and edge symbols have z2 0 -- on a calendar they paint ABOVE the day rects but BELOW heatmap cells (z2 1), pie sectors (2) and the split lines (20); node symbols have z2 100.",
      "Pie: coordinateSystemUsage 'box'. The coordinate is series.coord when set, else series.center (the DEFAULT center ['50%', '50%'] is fed too: parseDate('50%') is NaN -> every number NaN). refContainer = calendar.dataToLayout(coord).contentRect (CLAMPED: out of range -> NaN); viewRect = getLayoutRect(the pie's left / top / right / bottom / width / height, refContainer) -- out of range, dataToLayout gives x / y NaN but width / height = the cell size (so the contentRect is NaN, NaN, sw - lw, sh - lw and the viewRect 0, 0, sw - lw, sh - lw: a percent radius is still a number, cx / cy are NaN; the sectors are still created, with a NaN centre); the centre is the refContainer centre when the coordinate came from center (whatever the viewRect), else parsePercent(center[i], viewRect size) + viewRect.x / y. r0 / r = parsePercent(radius, min(viewRect.width, viewRect.height) / 2): an absolute radius ignores the cell. Sectors: z2 2, angles from startAngle 90 clockwise as any pie.",
      "Paint order at the calendar's z 2 (component elements are added before chart elements; ties keep insertion order): day rects 0 < graph edges 0 < heatmap cells 1 < pie sectors 2 < heatmap labels 3 < split / edge lines 20 < calendar names 30 < ripples 99 < symbols 100 < symbol labels 102. A series z other than 2 or a zlevel moves the whole series (Z2).",
      'Not recorded: emphasis / blur / select states, hover, tooltip, the ripple animation after its first frame (the animators are), the heatmap series (heatmap-calendar.js), the calendar picture (calendar-layout.js). Labels, symbol path commands and styles beyond fill / stroke are recorded but NOT transcribed.',
    ],
    symbolPaths,
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
const rec = out.cases.flatMap(c => c.series.filter(s => s.recorded && !s.filtered));
const count = t => rec.filter(s => s.type === t).length;
console.log(out.cases.length + ' cases (' + ['scatter', 'effectScatter', 'graph', 'pie'].map(t => count(t) + ' ' + t).join(', ') + '); ' + (out.guards.length - bad.length) + '/' + out.guards.length
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
