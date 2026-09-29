/*
Upstream's own answers for the CALENDAR coordinate system and the calendar
component's picture: coord/calendar/CalendarModel.ts (defaults, cellSize and
box normalisation), coord/calendar/Calendar.ts (_initRangeOption,
_getRangeInfo, getDateInfo, dataToPoint / dataToLayout / dataToCalendarLayout,
_update) and component/calendar/CalendarView.ts (day rects, split lines, edge
lines, year / month / day labels), with util/layout.ts mergeLayoutParam /
getLayoutRect, util/number.ts parseDate / parsePercent, util/format.ts
formatTplSimple, util/graphic.ts expandOrShrinkRect, core/locale.ts and
zrender's Text / TSpan / Polyline / Rect / canvas/dashStyle.ts.

Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
ECHARTS_DIST) in node's server-side mode (SVG renderer, ssr: true) at 800 x 600
with Math.random replaced by the port's xorshift32 (seed 2463534242, reset
before each chart) and process.env.TZ = 'UTC' set inside this script before
anything touches Date (checked: a script that runs under another zone stops).
After setOption it runs zr.storage.getDisplayList(true) (every element's
update: the Text elements lay out their TSpans) and reads the live models, the
coordinate system and the calendar view's group -- never the SVG text. Every
case is recorded again through the PRODUCTION build (dist/echarts.min.js) and
must record identically. Every chart is disposed in a finally.

  node tools/advchart-oracle/calendar-layout.js

writes tests/fixtures/advchart-calendar-layout.json (ORACLE_OUT overrides;
ORACLE_DUMP=<file> also writes the record before the checks, for debugging).

-----------------------------------------------------------------------------
Numbers are plain JSON numbers written by JSON.stringify (shortest round-trip
form: they parse back to the same double). Values JSON has no form for:
  null        NaN (a number field that is null IS NaN -- e.g. dataToPoint of
              an out-of-range date), or an undefined value inside an array
  "-0" / "Infinity" / "-Infinity"   those doubles, as strings (none occur
              today; the writer counts them and prints the count)
  an absent key   upstream holds undefined (or the element does not have it)

Top level
  source, W, H, seed, tz ('UTC'), api {...}, notes[], cases[], guards[]
  cases[]  id, note, gallery (file name or null), theme (the echarts.init
           theme name or null), option (exactly as fed: for a gallery case the
           gallery JSON with `series` removed -- nothing else touched),
    ground     {background: zr.getBackgroundColor(), isDark: zr.isDarkMode()}
    textStyle  ecModel.option.textStyle (the global text style every label font
               part falls back to; fontFamily 'Microsoft YaHei' on this Windows
               machine, 'sans-serif' elsewhere -- globalDefault.ts)
    locale     the chart locale's name ('EN' in node/SSR)
    paintRuns  the WHOLE display list (zr.storage.getDisplayList) run-length
               encoded: [{cal (calendar index, null = not a calendar
               element), group, n}] -- the global paint order when several
               calendars share one chart (all z 2: every calendar's day rects
               paint before any calendar's split lines, ...)
    calendars[]  one per calendar component, component order:
      index
      input        the calendar option as fed (null when absent)
      box          {left, right, top, bottom, width, height}: the model's
                   option after both normalisation passes (null = upstream holds
                   null; absent = undefined)
      cellSizeOption  the model's option.cellSize after normalisation (always a
                   2-array; 'auto' where a size is computed)
      layoutParams the object handed to getLayoutRect: box + width / height =
                   cellSize * cellNumbers for a numeric cellSize
      rect         {x, y, width, height}: coordinateSystem.getRect()
      cellSize     [sw, sh] as used (after 'auto')
      lineWidth    Calendar._lineWidth = itemStyle borderWidth || 0: the
                   contentRect inset source
      orient, firstDay (Calendar._firstDayOfWeek = +dayLabel.firstDay)
      z, zlevel    the component's z / zlevel options (json)
      rangeOption  model.option.range AFTER the chart ran (a reversed array
                   pair has been reversed IN PLACE by _initRangeOption)
      rangeInfo    getRangeInfo() whole: range [start, end] as 'yyyy-MM-dd',
                   start / end {y, m, d (strings), day (row in the week 0..6),
                   time (ms), formatedDate, dateTime (the Date object's
                   getTime())}, allDay, weeks, nthWeek, fweek, lweek
      counts       {rect, polyline, text, day, split, edge, year, month,
                   week}: elements per kind and per group
      dayRects     null (no day) or the day cells, which are the FIRST children
                   of the group and paint consecutively (guarded):
        paintFirst the display-list index of the first day rect (day k paints
                   at paintFirst + k)
        common     {width, height (= cellSize, guarded), z, z2, zlevel, silent,
                   cursor, style} shared by EVERY day rect (guarded: the
                   generator stops if one differs)
        xy         [x0, y0, x1, y1, ...]: shape.x / shape.y of day k (start +
                   k days) at xy[2k], xy[2k + 1]
      textCommon   {year?, month?, week?}: per label group, the part every
                   label of the group shares (from the first label that has a
                   TSpan): {z, z2, zlevel, silent (el.silent === true), cursor
                   (a Text's default 'pointer'), originX, originY, scaleX,
                   scaleY, style (the Text's own style keys MINUS text, x, y,
                   align, verticalAlign: fill, fontStyle, fontWeight, fontSize,
                   fontFamily, font, ...), tspan (the TSpan style MINUS text,
                   x, y, textAlign: textBaseline, font, fill, stroke,
                   lineWidth, opacity; null when no label of the group has a
                   TSpan)}
      elements[]   the rest of the group -- polylines, then texts -- in group
                   order = paint order (guarded), each:
        kind       'polyline' | 'text'
        group      'split' (month split polylines) | 'edge' (the two edge
                   polylines) | 'year' | 'month' | 'week' (day-of-week labels)
        paint      display-list index (a Text: its TSpan's; null for a label
                   whose text is empty / undefined: no TSpan, nothing painted)
        polyline:  points [[x, y], ...] (14 for a split line, 2 for an edge),
                   smooth, dash (zrender normalizeLineDash(style.lineDash,
                   style.lineWidth) as the painters resolve it: null = solid),
                   z, z2, zlevel, silent, cursor, style (the element's OWN
                   style keys exactly as upstream holds them: stroke, fill
                   null, lineWidth, lineDash = the raw type 'solid' / 'dashed'
                   / [5, 3], + opacity, lineDashOffset, lineCap, shadow* when
                   set; absent = the zrender default)
        text:      text (style.text; absent = undefined), x, y, rotation (the
                   ELEMENT transform: the year label is placed here, rotated
                   PI/2 for left / right = SVG matrix(0,-1,1,0,x,y), reading
                   bottom to top; month / week labels have x = y = 0),
                   styleX, styleY (style.x / style.y: where month / week
                   labels are placed; absent on the year label), align,
                   verticalAlign (style), tspans [{text, x, y, textAlign}]
                   (what zrender draws after the Text layout: textBaseline
                   'middle' and y moved by verticalAlign -- bottom: -fontSize/2,
                   top: +fontSize/2 for one line), own (present only when this
                   label differs from textCommon[group]: its full common part)
      probes[]     per probe date (input kept EXACTLY as given: string, number
                   or null):
        input
        info       getDateInfo(input): {y, m, d, day, time, formatedDate}
        point      dataToPoint([input]) (clamp: NaN pair outside the range)
        layout     dataToLayout([input]): {rect, contentRect} (clamped)
        cal        dataToCalendarLayout([input], false): {center, tl, tr, br,
                   bl} (UNclamped: dates outside the range get real cells, a
                   negative week before the start)
  guards[]  id, mutation, named (cases the mutated transcription must turn
            red), changed (cases it does turn red), ok (named subset of changed)

-----------------------------------------------------------------------------
The transcription (checked against every calendar, bit for bit, Object.is)
works on CIVIL DAY NUMBERS (days since 1970-01-01 of the wall date) instead of
Date objects: dn = floor(time / 86400000), weekday = (dn + 4) mod 7, day =
|(weekday + 7 - firstDay) % 7|, S / E = dn of the range ends, fweek = day(S),
lweek = day(E), allDay = E - S + 1, weeks = floor((allDay + fweek + 6) / 7),
and for ANY date (before, inside or after the range)
      nthWeek(dn) = floor((dn - S + fweek) / 7)
(upstream reaches it through _getRangeInfo([start, date]), reversed for a date
before the start; guard: the two agree on every probe and label anchor).
  centre   horizontal [rect.x + nth*sw + sw/2, rect.y + day*sh + sh/2];
           vertical   [rect.x + day*sw + sw/2, rect.y + nth*sh + sh/2]
  tl ...   centre -/+ sw/2, -/+ sh/2 (the ROUND TRIP: a day rect's x is
           (rect.x + nth*sw + sw/2) - sw/2, not rect.x + nth*sw)
  contentRect  expandOrShrinkRect(rect, lw/2, shrink, noNegative): width +=
           (-lw/2) + (-lw/2), then x -= -lw/2 (same for height / y); a size
           that would go negative collapses to 0 at the centre
  box      mergeLayoutParam twice (the count-based pass of
           mergeDefaultAndTheme, then CalendarModel's ignoreSize pass),
           cellSize normalisation, then echarts.helper.getLayoutRect
  view     CalendarView.render as documented in `notes`
Self-checks (any failure: nothing is written, exit 1): TZ is UTC; the
transcription reproduces every calendar; the group holds exactly rects, then
polylines, then texts, with no transform on the group; the group order is the
paint order; the compact dayRects / textCommon forms are lossless;
rect count == allDay; split polylines == 1 + (month firsts in
(start, end]) + 1, plus 2 edges when splitLine.show; cell centre = rect.x +
nthWeek*sw + sw/2 for every probe; contentRect = rect shrunk by lineWidth/2;
the day-label anchors have day 0 and nthWeek -1 ('start') / weeks ('end');
the production build records identically; every guard is ok; two generations
in the process give identical bytes.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-calendar-layout.json');
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

const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const isArray = Array.isArray;
const isObject = v => v !== null && (typeof v === 'object' || typeof v === 'function');
function clone(v) {
  if (v == null || typeof v !== 'object') return v;
  if (isArray(v)) return v.map(clone);
  const r = {};
  for (const k of Object.keys(v)) r[k] = clone(v[k]);
  return r;
}
// zrender util.merge without overwrite (the default / theme fill)
function zrMerge(target, source) {
  if (!isObject(source) || !isObject(target)) return target;
  for (const key of Object.keys(source)) {
    const t = target[key];
    const s = source[key];
    if (isObject(s) && isObject(t) && !isArray(s) && !isArray(t)) zrMerge(t, s);
    else if (!(key in target)) target[key] = clone(s);
  }
  return target;
}

// ============================================================================
// The transcription (with the guards' mutations as switches)
// ============================================================================

// util/number.ts parseDate -> getTime(), under TZ=UTC (a zone-less string is local = UTC)
const TIME_REG = /^(?:(\d{4})(?:[-\/](\d{1,2})(?:[-\/](\d{1,2})(?:[T ](\d{1,2})(?::(\d{1,2})(?::(\d{1,2})(?:[.,](\d+))?)?)?(Z|[\+\-]\d\d:?\d\d)?)?)?)?)?$/;
function parseTime(v) {
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
const dnOf = t => Math.floor(t / DAY);
const weekday = dn => (((dn % 7) + 7) % 7 + 4) % 7;
const dayOf = (dn, fd) => Math.abs((weekday(dn) + 7 - fd) % 7);
function civil(dn) {
  const d = new Date(dn * DAY);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate() };
}
const pad2 = n => (n < 10 ? '0' + n : '' + n);
function fmtDn(dn) {
  const c = civil(dn);
  return c.y + '-' + pad2(c.m) + '-' + pad2(c.d);
}
const dnFromYMD = (y, m, d) => Date.UTC(y, m - 1, d) / DAY;

// util/number.ts parsePercent
function parsePercent(percent, all) {
  switch (percent) {
    case 'center': case 'middle': percent = '50%'; break;
    case 'left': case 'top': percent = '0%'; break;
    case 'right': case 'bottom': percent = '100%'; break;
  }
  if (typeof percent === 'string') {
    if (/%$/.test(percent.trim())) return parseFloat(percent) / 100 * all;
    return parseFloat(percent);
  }
  return percent == null ? NaN : +percent;
}

// util/layout.ts mergeLayoutParam, verbatim
const HV_NAMES = [['width', 'left', 'right'], ['height', 'top', 'bottom']];
const LOC = ['left', 'right', 'top', 'bottom', 'width', 'height'];
function mergeLayoutParam(targetOption, newOption, ignoreSize) {
  if (!isArray(ignoreSize)) ignoreSize = [ignoreSize, ignoreSize];
  const hasValue = (obj, name) => obj[name] != null && obj[name] !== 'auto';
  const merge = (names, hvIdx) => {
    const newParams = {};
    let newValueCount = 0;
    const merged = {};
    let mergedValueCount = 0;
    names.forEach(n => { merged[n] = targetOption[n]; });
    names.forEach(n => {
      if (hasOwn(newOption, n)) newParams[n] = merged[n] = newOption[n];
      if (hasValue(newParams, n)) newValueCount++;
      if (hasValue(merged, n)) mergedValueCount++;
    });
    if (ignoreSize[hvIdx]) {
      if (hasValue(newOption, names[1])) merged[names[2]] = null;
      else if (hasValue(newOption, names[2])) merged[names[1]] = null;
      return merged;
    }
    if (mergedValueCount === 2 || !newValueCount) return merged;
    else if (newValueCount >= 2) return newParams;
    for (let i = 0; i < names.length; i++) {
      const n = names[i];
      if (!hasOwn(newParams, n) && hasOwn(targetOption, n)) {
        newParams[n] = targetOption[n];
        break;
      }
    }
    return newParams;
  };
  const h = merge(HV_NAMES[0], 0);
  const v = merge(HV_NAMES[1], 1);
  HV_NAMES[0].forEach(n => { targetOption[n] = h[n]; });
  HV_NAMES[1].forEach(n => { targetOption[n] = v[n]; });
}
const sizeCalculable = (o, hv) => o[HV_NAMES[hv][0]] != null || (o[HV_NAMES[hv][1]] != null && o[HV_NAMES[hv][2]] != null);

// Component.mergeDefaultAndTheme + CalendarModel.init / mergeAndNormalizeLayoutParams
function normaliseBox(userOpt, themeCal) {
  const raw = {};
  for (const k of LOC) if (hasOwn(userOpt, k)) raw[k] = userOpt[k];
  const opt = clone(userOpt);
  zrMerge(opt, themeCal || {});
  zrMerge(opt, { left: 80, top: 60, cellSize: 20 });
  mergeLayoutParam(opt, raw, undefined);
  let cs = opt.cellSize;
  if (!isArray(cs)) cs = opt.cellSize = [cs, cs];
  if (cs.length === 1) cs[1] = cs[0];
  const ignore = [0, 1].map(hv => {
    if (sizeCalculable(raw, hv)) cs[hv] = 'auto';
    return cs[hv] != null && cs[hv] !== 'auto';
  });
  mergeLayoutParam(opt, raw, ignore);
  return opt;
}

// util/graphic.ts expandOrShrinkRect(rect, delta, shrink = true, noNegative = true), 4 equal deltas
function shrinkRect(r, delta, mut) {
  const o = { x: r.x, y: r.y, width: r.width, height: r.height };
  const d = -Math.max(0, delta);
  const one = (xy, wh) => {
    const deltaSum = d + d;
    const oldSize = o[wh];
    o[wh] += deltaSum;
    const minSize = Math.max(0, Math.min(0, oldSize));
    if (o[wh] < minSize) {
      o[wh] = minSize;
      if (mut.collapseKeepsX) o[xy] -= d;
      else o[xy] += (d >= 0 ? -d : d >= 0 ? oldSize + d : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * d / deltaSum : 0);
    } else {
      o[xy] -= d;
    }
  };
  one('x', 'width');
  one('y', 'height');
  return o;
}

// util/format.ts formatTplSimple: String.replace with a STRING pattern -> the first occurrence only, and the
// replacement's $-patterns ($&, $$, ...) are live
function formatTplSimple(tpl, params, mut) {
  for (const key of Object.keys(params)) {
    if (mut.tplAll) tpl = tpl.split('{' + key + '}').join(String(params[key]));
    else tpl = tpl.replace('{' + key + '}', params[key]);
  }
  return tpl;
}
function formatLabel(formatter, params, mut) {
  if (typeof formatter === 'string' && formatter) return formatTplSimple(formatter, params, mut);
  return params.nameMap;
}

// i18n/langEN.ts / langZH.ts (the only registered locales; getLocaleModel is a CASE-SENSITIVE key lookup)
const LOCALES = {
  EN: { monthAbbr: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    dayOfWeekAbbr: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] },
  ZH: { monthAbbr: ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'],
    dayOfWeekAbbr: ['日', '一', '二', '三', '四', '五', '六'] },
};
function localeFor(nameMap, chartLocale, mut) {
  if (nameMap && mut.cnIsZH && String(nameMap).toLowerCase() === 'cn') return LOCALES.ZH;
  if (nameMap && mut.caseInsensitive && LOCALES[String(nameMap).toUpperCase()]) return LOCALES[String(nameMap).toUpperCase()];
  return (nameMap && hasOwn(LOCALES, nameMap) && LOCALES[nameMap]) || LOCALES[chartLocale];
}
function monthNames(nameMap, chartLocale, mut) {
  if (!nameMap || typeof nameMap === 'string') return localeFor(nameMap, chartLocale, mut).monthAbbr;
  return nameMap;
}
function dayNames(nameMap, chartLocale, mut) {
  if (!nameMap || typeof nameMap === 'string') return localeFor(nameMap, chartLocale, mut).dayOfWeekAbbr.map(v => v[0]);
  return nameMap;
}

// zrender canvas/dashStyle.ts normalizeLineDash
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
    : typeof lineType === 'number' ? [lineType] : isArray(lineType) ? lineType : null;
}

// the whole calendar, from its inputs
function transcribe(inp, mut) {
  const { rect, sw, sh, orient, firstDay: fd, lw, chartLocale } = inp;
  const horiz = orient === 'horizontal';
  const S = dnOf(parseTime(inp.range[0]));
  const E = dnOf(parseTime(inp.range[1]));
  const fweek = dayOf(S, fd);
  const lweek = dayOf(E, fd);
  const allDay = E - S + 1;
  const weeks = Math.floor((allDay + fweek + 6) / 7);
  const nthOf = dn => (mut.noFweek ? Math.floor((dn - S) / 7) : Math.floor((dn - S + fweek) / 7));
  const centre = dn => {
    const nth = nthOf(dn);
    const day = dayOf(dn, fd);
    return horiz ? [rect.x + nth * sw + sw / 2, rect.y + day * sh + sh / 2]
      : [rect.x + day * sw + sw / 2, rect.y + nth * sh + sh / 2];
  };
  const corners = dn => {
    const c = centre(dn);
    if (mut.tlDirect) {
      const nth = nthOf(dn);
      const day = dayOf(dn, fd);
      const tl = horiz ? [rect.x + nth * sw, rect.y + day * sh] : [rect.x + day * sw, rect.y + nth * sh];
      return { center: c, tl, tr: [tl[0] + sw, tl[1]], br: [tl[0] + sw, tl[1] + sh], bl: [tl[0], tl[1] + sh] };
    }
    return { center: c, tl: [c[0] - sw / 2, c[1] - sh / 2], tr: [c[0] + sw / 2, c[1] - sh / 2], br: [c[0] + sw / 2, c[1] + sh / 2],
      bl: [c[0] - sw / 2, c[1] + sh / 2] };
  };
  const out = { rangeInfo: { range: [fmtDn(S), fmtDn(E)], startTime: S * DAY, endTime: E * DAY, startDay: fweek, endDay: lweek, allDay, weeks,
    nthWeek: weeks - 1, fweek, lweek }, elements: [], probes: [], anchors: [] };

  // day rects
  for (let dn = S; dn <= E; dn++) {
    const tl = corners(dn).tl;
    out.elements.push({ kind: 'rect', group: 'day', shape: [tl[0], tl[1], sw, sh] });
  }
  // split lines
  const dates = [S];
  const s0 = civil(S);
  let y = s0.y;
  let m = s0.m;
  for (;;) {
    m++;
    if (m > 12) { m = 1; y++; }
    const f = dnFromYMD(y, m, 1);
    if (f > E) break;
    dates.push(f);
  }
  if (!mut.noEndLine) dates.push(E + 1);
  const tlpoints = [];
  const blpoints = [];
  const firstDayPoints = [];
  for (const d of dates) {
    firstDayPoints.push(corners(d).tl);
    const pts = [];
    for (let i = 0; i < 7; i++) {
      const c = corners(d + i);
      const day = dayOf(d + i, fd);
      pts[2 * day] = c.tl;
      pts[2 * day + 1] = horiz ? c.bl : c.tr;
    }
    tlpoints.push(pts[0]);
    blpoints.push(pts[pts.length - 1]);
    if (inp.split.show) out.elements.push({ kind: 'polyline', group: 'split', points: pts });
  }
  if (inp.split.show) {
    const edges = p => {
      const rs = [p[0].slice(), p[p.length - 1].slice()];
      const idx = horiz ? 0 : 1;
      const half = mut.noEdgeExtend ? 0 : inp.split.lineWidth / 2;
      rs[0][idx] = rs[0][idx] - half;
      rs[1][idx] = rs[1][idx] + half;
      return rs;
    };
    out.elements.push({ kind: 'polyline', group: 'edge', points: edges(tlpoints) });
    out.elements.push({ kind: 'polyline', group: 'edge', points: edges(blpoints) });
  }
  // year
  const yl = inp.yearLabel;
  if (yl.show) {
    const pos = yl.position || (!horiz ? 'top' : 'left');
    const points = [tlpoints[tlpoints.length - 1], blpoints[0]];
    const xc = (points[0][0] + points[1][0]) / 2;
    const yc = (points[0][1] + points[1][1]) / 2;
    const idx = horiz ? 0 : 1;
    const posPoints = { top: [xc, points[idx][1]], bottom: [xc, points[1 - idx][1]], left: [points[1 - idx][0], yc], right: [points[idx][0], yc] };
    const sy = civil(S).y + '';
    const ey = civil(E).y + '';
    let name = sy;
    if (+ey > +sy) name = name + '-' + ey;
    const text = formatLabel(yl.formatter, { start: sy, end: ey, nameMap: name }, mut);
    const p = posPoints[pos];
    let x = p[0];
    let yy = p[1];
    let al = ['center', 'bottom'];
    const margin = yl.margin;
    if (pos === 'bottom') { yy += margin; al = ['center', 'top']; }
    else if (pos === 'left') x -= margin;
    else if (pos === 'right') { x += margin; al = ['center', 'top']; }
    else yy -= margin;
    const rotation = (pos === 'left' || pos === 'right') && !mut.noYearRotate ? Math.PI / 2 : 0;
    out.elements.push({ kind: 'text', group: 'year', text, x, y: yy, rotation, align: al[0], verticalAlign: al[1] });
  }
  // months
  const ml = inp.monthLabel;
  if (ml.show) {
    const names = monthNames(ml.nameMap, chartLocale, mut);
    const termPoints = [tlpoints, blpoints];
    const idx = ml.position === 'start' ? 0 : 1;
    const axis = horiz ? 0 : 1;
    const margin = ml.position === 'start' ? -ml.margin : ml.margin;
    const isCenter = ml.align === 'center';
    for (let i = 0; i < termPoints[idx].length - 1; i++) {
      const tmp = termPoints[idx][i].slice();
      if (isCenter) tmp[axis] = ((mut.monthCentreFromTl ? tlpoints[i] : firstDayPoints[i])[axis] + termPoints[0][i + 1][axis]) / 2;
      const c = civil(dates[i]);
      const mStr = pad2(c.m);
      const text = formatLabel(ml.formatter, { yyyy: c.y + '', yy: (c.y + '').slice(2), MM: mStr, M: +mStr, nameMap: names[+mStr - 1] }, mut);
      let align = 'left';
      let vAlign = 'top';
      let x = tmp[0];
      let yy = tmp[1];
      if (horiz) {
        yy = yy + margin;
        if (isCenter) align = 'center';
        if (ml.position === 'start') vAlign = 'bottom';
      } else {
        x = x + margin;
        if (isCenter) vAlign = 'middle';
        if (ml.position === 'start') align = 'right';
      }
      out.elements.push({ kind: 'text', group: 'month', text, x, y: yy, rotation: 0, align, verticalAlign: vAlign });
    }
  }
  // week (day-of-week) labels
  const dl = inp.dayLabel;
  if (dl.show) {
    const names = dayNames(dl.nameMap, chartLocale, mut);
    const isStart = dl.position === 'start';
    let start = E + (7 - lweek);
    let margin = mut.noPercentMargin ? +dl.margin : parsePercent(dl.margin, Math.min(sh, sw));
    if (isStart) {
      start = mut.startAnchorWeek0 ? S - fweek : S - (7 + fweek);
      margin = -margin;
    }
    out.anchors.push({ dn: start, day: dayOf(start, fd), nth: nthOf(start), expectNth: isStart ? -1 : weeks });
    for (let i = 0; i < 7; i++) {
      const c = corners(start + i).center;
      const text = names[Math.abs((i + fd) % 7)];
      let x = c[0];
      let yy = c[1];
      let align = 'center';
      let vAlign = 'middle';
      if (horiz) {
        x = x + margin + (isStart ? 1 : -1) * sw / 2;
        align = isStart ? 'right' : 'left';
      } else {
        yy = yy + margin + (isStart ? 1 : -1) * sh / 2;
        vAlign = isStart ? 'bottom' : 'top';
      }
      out.elements.push({ kind: 'text', group: 'week', text, x, y: yy, rotation: 0, align, verticalAlign: vAlign });
    }
  }
  // probes
  for (const input of inp.probeInputs) {
    const t = parseTime(input);
    const dn = dnOf(t);
    const inRange = t >= S * DAY && t < E * DAY + DAY;
    const cal = corners(dn);
    const point = inRange ? cal.center : [NaN, NaN];
    const r = { x: point[0] - sw / 2, y: point[1] - sh / 2, width: sw, height: sh };
    const cr = shrinkRect(r, mut.fullInset ? lw : lw / 2, mut);
    out.probes.push({ input, point, rect: r, contentRect: cr, cal, dn, day: dayOf(dn, fd), nth: nthOf(dn) });
  }
  return out;
}

// ============================================================================
// Reading upstream
// ============================================================================

const plainStyle = st => {
  const o = {};
  for (const k of Object.keys(st)) if (st[k] !== undefined) o[k] = clone(st[k]);
  return o;
};
const pt2 = p => [p[0], p[1]];
const rect4 = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
function dateInfo(di) {
  return { y: di.y, m: di.m, d: di.d, day: di.day, time: di.time, formatedDate: di.formatedDate };
}

function readCalendar(chart, cm, ci, userCal, probeExtra, displayIndex) {
  const ec = chart.getModel();
  const cs = cm.coordinateSystem;
  const view = chart.getViewOfComponentModel(cm);
  const group = view.group;
  must(group.x === 0 && group.y === 0 && group.rotation === 0 && group.scaleX === 1 && group.scaleY === 1, 'the calendar group is transformed');
  const r = cs.getRect();
  const ri = cs.getRangeInfo();
  const sw = cs.getCellWidth();
  const sh = cs.getCellHeight();
  const orient = cs.getOrient();
  const opt = cm.option;
  const box = {};
  for (const k of LOC) if (k in opt) box[k] = opt[k] === undefined ? undefined : opt[k];
  const weeks = ri.weeks || 1;
  const cellNumbers = orient === 'horizontal' ? [weeks, 7] : [7, weeks];
  const layoutParams = cm.getBoxLayoutParams();
  const cso = cm.getCellSize();
  [0, 1].forEach(i => { if (cso[i] != null && cso[i] !== 'auto') layoutParams[['width', 'height'][i]] = cso[i] * cellNumbers[i]; });

  const rec = {
    index: ci,
    input: userCal == null ? null : clone(userCal),
    box, cellSizeOption: clone(cso), layoutParams: clone(layoutParams),
    rect: rect4(r), cellSize: [sw, sh], lineWidth: cs._lineWidth, orient, firstDay: cs.getFirstDayOfWeek(),
    z: cm.get('z'), zlevel: cm.get('zlevel'),
    rangeOption: clone(opt.range),
    rangeInfo: { range: ri.range.slice(), start: Object.assign(dateInfo(ri.start), { dateTime: ri.start.date.getTime() }),
      end: Object.assign(dateInfo(ri.end), { dateTime: ri.end.date.getTime() }), allDay: ri.allDay, weeks: ri.weeks, nthWeek: ri.nthWeek,
      fweek: ri.fweek, lweek: ri.lweek },
  };

  // elements
  const kids = group.children();
  const kindOf = el => (el.type === 'rect' ? 'rect' : el.type === 'polyline' ? 'polyline' : el.type === 'text' ? 'text' : el.type);
  const kinds = kids.map(kindOf);
  const order = { rect: 0, polyline: 1, text: 2 };
  must(kinds.every(k => k in order), 'an unexpected element kind ' + kinds.find(k => !(k in order)));
  for (let i = 1; i < kinds.length; i++) must(order[kinds[i]] >= order[kinds[i - 1]], 'the group is not rects, polylines, texts');
  const els = kids.map(el => {
    const kind = kindOf(el);
    const base = { kind, group: null, paint: null };
    const common = { z: el.z, z2: el.z2, zlevel: el.zlevel, silent: el.silent === true, cursor: el.cursor };
    if (kind === 'rect') {
      const s = el.shape;
      return Object.assign(base, { shape: [s.x, s.y, s.width, s.height] }, common, { style: plainStyle(el.style), _el: el });
    }
    if (kind === 'polyline') {
      return Object.assign(base, { points: el.shape.points.map(pt2), smooth: el.shape.smooth, dash: normalizeLineDash(el.style.lineDash, el.style.lineWidth) },
        common, { style: plainStyle(el.style), _el: el });
    }
    const spans = (el.childrenRef ? el.childrenRef() : el._children) || [];
    return Object.assign(base, { text: el.style.text, x: el.x, y: el.y, rotation: el.rotation, originX: el.originX, originY: el.originY,
      scaleX: el.scaleX, scaleY: el.scaleY,
      tspans: spans.map(s => ({ text: s.style.text, x: s.style.x, y: s.style.y, textAlign: s.style.textAlign, textBaseline: s.style.textBaseline,
        font: s.style.font, fill: s.style.fill, stroke: s.style.stroke, lineWidth: s.style.lineWidth, opacity: s.style.opacity })) },
      common, { style: plainStyle(el.style), _el: el, _paintEl: spans[0] });
  });
  for (const e of els) {
    const p = displayIndex.get(e._paintEl || e._el);
    e.paint = p === undefined ? null : p;
  }
  // paint order within the calendar = group order
  const painted = els.filter(e => e.paint != null);
  // a Text whose text is empty / undefined lays out no TSpan: nothing of it is painted (paint null)
  must(els.every(e => e.paint != null || (e.kind === 'text' && e.tspans.length === 0)), 'a calendar element is not in the display list');
  for (let i = 1; i < painted.length; i++) must(painted[i].paint > painted[i - 1].paint, 'the group order is not the paint order');

  // inputs for the transcription
  const labels = name => {
    const lm = cm.getModel(name);
    return { show: lm.get('show'), position: lm.get('position'), margin: lm.get('margin'), align: lm.get('align'), formatter: lm.get('formatter'),
      nameMap: lm.get('nameMap') };
  };
  const probeInputs = autoProbes(ri).concat(probeExtra || []);
  const inp = {
    rect: rect4(r), sw, sh, orient, firstDay: cs.getFirstDayOfWeek(), lw: cs._lineWidth, chartLocale: chartLocaleName(ec),
    range: ri.range.slice(),
    split: { show: cm.get(['splitLine', 'show']), lineWidth: cm.getModel(['splitLine', 'lineStyle']).getLineStyle().lineWidth },
    yearLabel: labels('yearLabel'), monthLabel: labels('monthLabel'), dayLabel: labels('dayLabel'), probeInputs,
  };
  rec.probes = probeInputs.map(input => {
    const di = cs.getDateInfo(input);
    const lay = cs.dataToLayout([input]);
    const cal = cs.dataToCalendarLayout([input], false);
    return { input, info: dateInfo(di), point: pt2(cs.dataToPoint([input])), layout: { rect: rect4(lay.rect), contentRect: rect4(lay.contentRect) },
      cal: { center: pt2(cal.center), tl: pt2(cal.tl), tr: pt2(cal.tr), br: pt2(cal.br), bl: pt2(cal.bl) },
      _nthUp: cs._getRangeInfo([ri.start.time, di.formatedDate]).nthWeek };
  });
  return { rec, els, inp, cs, ri };
}

function chartLocaleName(ec) {
  const lm = ec.getLocaleModel();
  const ma = lm.get(['time', 'monthAbbr']);
  const hit = Object.keys(LOCALES).find(k => JSON.stringify(LOCALES[k].monthAbbr) === JSON.stringify(ma));
  must(hit, 'an unknown chart locale');
  return hit;
}

// the probe dates derived from the range (+ the case's own)
function autoProbes(ri) {
  const S = dnOf(ri.start.time);
  const E = dnOf(ri.end.time);
  const s = fmtDn(S);
  const e = fmtDn(E);
  const ce = civil(E);
  return [s, e, fmtDn(S + Math.floor((E - S) / 2)), fmtDn(S - 1), fmtDn(E + 1), s + ' 13:00', e + 'T23:59:59.999Z', s + 'T03:00:00+08:00',
    S * DAY, S * DAY + 86399999.6, ce.y + '/' + ce.m + '/' + ce.d];
}

// ============================================================================
// Running a case
// ============================================================================

function runChart(E, def, option, fn) {
  rngState = SEED;
  const chart = E.init(null, def.theme || null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(option);
    chart.getZr().storage.getDisplayList(true);
    return fn(chart);
  } finally {
    chart.dispose();
  }
}

const calArray = o => (o.calendar == null ? [] : isArray(o.calendar) ? o.calendar : [o.calendar]);

function recordWith(E, def, optionText) {
  const input = JSON.parse(optionText);
  return runChart(E, def, JSON.parse(optionText), chart => {
    const ec = chart.getModel();
    const zr = chart.getZr();
    const list = zr.storage.getDisplayList(true);
    const displayIndex = new Map();
    list.forEach((el, i) => displayIndex.set(el, i));
    const cals = [];
    ec.eachComponent('calendar', (cm, ci) => {
      cals.push(readCalendar(chart, cm, ci, calArray(input)[ci], def.probes && def.probes[ci], displayIndex));
    });
    must(cals.length === calArray(input).length, 'calendar count ' + cals.length);
    // the whole display list, for the paint runs
    const owner = new Map();
    cals.forEach((c, ci) => c.els.forEach(e => owner.set(e._paintEl || e._el, { e, ci })));
    const groupOf = list.map(el => {
      const o = owner.get(el);
      return o ? { e: o.e, cal: o.ci } : { e: null, cal: null };
    });
    return { ground: { background: zr.getBackgroundColor(), isDark: !!zr.isDarkMode() }, textStyle: clone(ec.option.textStyle),
      locale: chartLocaleName(ec), cals, groupOf };
  });
}

function finishCase(def, base, side) {
  const cals = base.cals.map((c, ci) => {
    const key = def.id + '/' + ci;
    side[key] = { inp: c.inp, rec: c.rec, els: c.els, cs: c.cs };
    // classify with the transcription's element list (same order, same kinds -- checked in check())
    const t = transcribe(c.inp, {});
    must(t.elements.length === c.els.length, key + ': the transcription has ' + t.elements.length + ' elements, upstream ' + c.els.length);
    c.els.forEach((e, i) => {
      must(t.elements[i].kind === e.kind, key + ': element ' + i + ' is a ' + e.kind + ', the transcription says ' + t.elements[i].kind);
      e.group = t.elements[i].group;
    });
    const counts = { rect: 0, polyline: 0, text: 0, day: 0, split: 0, edge: 0, year: 0, month: 0, week: 0 };
    c.els.forEach(e => { counts[e.kind]++; counts[e.group]++; });
    // day rects -> one compact block (lossless: every rect must share the common part, be sw x sh and paint consecutively)
    const rects = c.els.filter(e => e.kind === 'rect');
    const commonOf = e => ({ z: e.z, z2: e.z2, zlevel: e.zlevel, silent: e.silent, cursor: e.cursor, style: e.style });
    let dayRects = null;
    if (rects.length) {
      const common = Object.assign({ width: rects[0].shape[2], height: rects[0].shape[3] }, commonOf(rects[0]));
      const ct = JSON.stringify(common);
      rects.forEach((e, i) => {
        must(JSON.stringify(Object.assign({ width: e.shape[2], height: e.shape[3] }, commonOf(e))) === ct, key + ': day rect ' + i + ' differs from the first');
        must(e.paint === rects[0].paint + i, key + ': day rects do not paint consecutively');
        must(Object.is(e.shape[2], c.rec.cellSize[0]) && Object.is(e.shape[3], c.rec.cellSize[1]), key + ': a day rect is not sw x sh');
      });
      const xy = [];
      rects.forEach(e => xy.push(e.shape[0], e.shape[1]));
      dayRects = { paintFirst: rects[0].paint, common, xy };
    }
    // texts -> a common part per label group (lossless: checked)
    const TEXT_OWN_STYLE = ['text', 'x', 'y', 'align', 'verticalAlign'];
    const TSPAN_OWN = ['text', 'x', 'y', 'textAlign'];
    const textCommonOf = e => {
      const style = {};
      for (const k of Object.keys(e.style)) if (!TEXT_OWN_STYLE.includes(k)) style[k] = e.style[k];
      const tspan = e.tspans.length ? {} : null;
      if (tspan) for (const k of Object.keys(e.tspans[0])) if (!TSPAN_OWN.includes(k)) tspan[k] = e.tspans[0][k];
      return { z: e.z, z2: e.z2, zlevel: e.zlevel, silent: e.silent, cursor: e.cursor, originX: e.originX, originY: e.originY, scaleX: e.scaleX, scaleY: e.scaleY, style, tspan };
    };
    const textCommon = {};
    const elements = [];
    for (const e of c.els) {
      if (e.kind === 'rect') continue;
      if (e.kind === 'polyline') {
        const o = {};
        for (const k of Object.keys(e)) if (k[0] !== '_') o[k] = e[k];
        elements.push(o);
        continue;
      }
      const tc = textCommonOf(e);
      if (!textCommon[e.group] || (!textCommon[e.group].tspan && tc.tspan)) textCommon[e.group] = tc;
      elements.push({ kind: 'text', group: e.group, paint: e.paint, text: e.text, x: e.x, y: e.y, rotation: e.rotation, styleX: e.style.x, styleY: e.style.y,
        align: e.style.align, verticalAlign: e.style.verticalAlign, tspans: e.tspans.map(t => ({ text: t.text, x: t.x, y: t.y, textAlign: t.textAlign })), _e: e });
    }
    for (const o of elements) {
      if (o.kind !== 'text') continue;
      const e = o._e;
      delete o._e;
      const mine = textCommonOf(e);
      const com = Object.assign({}, textCommon[o.group], { tspan: mine.tspan ? textCommon[o.group].tspan : null });
      if (JSON.stringify(mine) !== JSON.stringify(com)) o.own = mine;
      must(e.tspans.length <= 1, key + ': a label with ' + e.tspans.length + ' tspans');
    }
    const probes = c.rec.probes.map(p => {
      const o = Object.assign({}, p);
      delete o._nthUp;
      return o;
    });
    return Object.assign({}, c.rec, { counts, dayRects, textCommon, elements, probes });
  });
  // paint runs
  const runs = [];
  for (const g of base.groupOf) {
    const cal = g.e ? g.cal : null;
    const grp = g.e ? g.e.group : 'other';
    const last = runs[runs.length - 1];
    if (last && last.cal === cal && last.group === grp) last.n++;
    else runs.push({ cal, group: grp, n: 1 });
  }
  return { ground: base.ground, textStyle: base.textStyle, locale: base.locale, paintRuns: runs, calendars: cals };
}

const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));

function recordCase(def, side) {
  let option = def.option;
  if (def.gallery) {
    option = gallery(def.gallery);
    delete option.series;
  }
  const optionText = JSON.stringify(option);
  const base = recordWith(echarts, def, optionText);
  const out = finishCase(def, base, side);
  const p = finishCase(def, recordWith(PROD, def, optionText), {});
  must(JSON.stringify(sanitize(p)) === JSON.stringify(sanitize(out)), def.id + ': the production build records differently');
  return Object.assign({ id: def.id, note: def.note, gallery: def.gallery || null, theme: def.theme || null, option: JSON.parse(optionText) }, out);
}

// ============================================================================
// The cases
// ============================================================================
const cal1 = (c, extra) => Object.assign({ calendar: c }, extra || {});
const CASES = [
  // ----- box and size (upstream.md 2.1) -----
  { id: 'B1', note: "the default box: {range: '2017'} -> left 80, top 60, 53 x 7 cells of 20: rect 80,60,1060,140 overflows the 800 canvas (nothing clamps)",
    option: cal1({ range: '2017' }) },
  { id: 'B2', note: "{top: 450, right: 5, cellSize: ['auto', 20]} (calendar-horizontal's third): the default left 80 is kept (count pass: left 80 + right 5 = 2 values), width = 800 - 5 - 80 = 715, sw = 715 / 53",
    option: cal1({ top: 450, range: '2015', cellSize: ['auto', 20], right: 5 }) },
  { id: 'B3', note: "{cellSize: ['auto', 20]} (calendar-horizontal's first): no right -> getLayoutRect's width W - right(NaN) - left is NaN, and its final fallback gives W - left - (right || 0) = 720; sw = 720 / 53",
    option: cal1({ range: '2017', cellSize: ['auto', 20] }) },
  { id: 'B4', note: "{top: 120, left: 'center'} half year: left 'center' -> x = 400 - width/2", option: cal1({ top: 120, left: 'center', range: ['2016-01-01', '2016-06-30'] }) },
  { id: 'B5', note: "{right: 10}: the ignoreSize pass nulls the default left (raw has right, not left) -> x = 800 - 10 - 100", option: cal1({ right: 10, range: '2017-02' }) },
  { id: 'B6', note: '{left: 10, right: 10, cellSize: 30}: left AND right make the width calculable -> cellSize[0] is FORCED to auto (156), the numeric 30 survives only vertically',
    option: cal1({ left: 10, right: 10, cellSize: 30, range: '2017-02' }) },
  { id: 'B7', note: "{left: '10%', width: '50%', height: 100}: width -> auto (400 / 53), height -> auto (100 / 7)", option: cal1({ left: '10%', width: '50%', height: 100, range: '2017' }) },
  { id: 'B8', note: "{cellSize: ['auto']}: a 1-array is doubled -> both auto: width 800 - 80, height 600 - 60", option: cal1({ cellSize: ['auto'], range: '2017' }) },
  { id: 'B9', note: "vertical {left: 520, bottom: 10, cellSize: [20, 'auto']} (calendar-vertical's third): the default top 60 is kept with bottom 10 -> height 530, sh = 530 / 53",
    option: cal1({ left: 520, cellSize: [20, 'auto'], bottom: 10, orient: 'vertical', range: '2017', dayLabel: { margin: 5 } }) },
  { id: 'B10', note: '{width: 400}: width set -> cellSize[0] auto', option: cal1({ width: 400, range: '2017' }) },
  { id: 'B11', note: 'cellSize [30] (1-array -> [30, 30])', option: cal1({ cellSize: [30], range: '2017-02' }) },
  { id: 'B12', note: 'cellSize 25 (a single number -> [25, 25])', option: cal1({ cellSize: 25, range: '2017-02' }) },
  { id: 'B13', note: 'cellSize [25, 15] (a 2-array)', option: cal1({ cellSize: [25, 15], range: '2017-02' }) },
  { id: 'B14', note: "percent right / bottom: {right: '5%', bottom: '10%'}: the ignoreSize pass nulls the default left and top -> x = 800 - 40 - w, y = 600 - 60 - h",
    option: cal1({ right: '5%', bottom: '10%', range: '2017-02' }) },
  { id: 'B15', note: "calendar-graph's box: {top: 'middle', left: 'center', vertical, cellSize 40}, two months", option: cal1({ top: 'middle', left: 'center', orient: 'vertical', cellSize: 40, range: ['2017-02', '2017-03-31'] }) },
  { id: 'B16', note: "calendar-lunar's box: {left: 'center', top: 'middle', cellSize [70, 70], vertical}", option: cal1({ left: 'center', top: 'middle', cellSize: [70, 70], orient: 'vertical', range: '2017-03' }) },
  { id: 'B17', note: "word positions: {left: 'right', top: 'bottom'} -> right / bottom aligned (getLayoutRect's switch)", option: cal1({ left: 'right', top: 'bottom', range: '2017-02' }) },
  { id: 'B18', note: "{top: 10, bottom: 10, height: '50%'}: top AND bottom -> cellSize[1] auto; count pass: 3 values -> all kept; getLayoutRect uses height 300 and top 10",
    option: cal1({ top: 10, bottom: 10, height: '50%', range: '2017-02' }) },
  { id: 'B19', note: '{left: null, right: 20}: an explicit null left (the default 80 is not filled: the key exists)', option: cal1({ left: null, right: 20, range: '2017-02' }) },
  { id: 'B20', note: "{cellSize: null}: zrender merge keeps the null (the key exists) -> [null, null] -> both sizes 'auto'-like (not specified): width 800 - 80, height 600 - 60",
    option: cal1({ cellSize: null, range: '2017-02' }) },
  { id: 'B21', note: "{width: 'auto'}: width != null makes it calculable -> cellSize[0] 'auto' and the option keeps width 'auto'; getLayoutRect parses it NaN -> the fallback W - left = 720, sw = 144",
    option: cal1({ width: 'auto', range: '2017-02' }) },
  { id: 'B22', note: "{left: 30, right: 30, cellSize: ['auto', 13], borderWidth 0.5} (calendar-heatmap's box, leap year 2016)", option: cal1({ top: 120, left: 30, right: 30, cellSize: ['auto', 13], range: '2016', itemStyle: { borderWidth: 0.5 }, yearLabel: { show: false } }) },
  // ----- orient -----
  { id: 'O1', note: "vertical '2017': rect 80,60,140,1060; month labels right / middle; day labels centre / bottom above the first row", option: cal1({ orient: 'vertical', range: '2017' }) },
  { id: 'O2', note: 'vertical Feb 2017, firstDay 1, cellSize 40', option: cal1({ orient: 'vertical', cellSize: 40, range: '2017-02', dayLabel: { firstDay: 1 } }) },
  { id: 'O3', note: 'horizontal Feb 2017, firstDay 1, cellSize 40 (O2 turned)', option: cal1({ cellSize: 40, range: '2017-02', dayLabel: { firstDay: 1 } }) },
  // ----- range forms -----
  { id: 'R1', note: 'range as the NUMBER 2017 (toString -> /^\\d{4}$/)', option: cal1({ range: 2017 }) },
  { id: 'R2', note: "range '2017/2' (a month through the [\\/|-] class)", option: cal1({ range: '2017/2' }) },
  { id: 'R3', note: "range '2017-02-05': one day -> 1 rect, 2 split lines + 2 edges; weeks 1", option: cal1({ range: '2017-02-05' }) },
  { id: 'R4', note: "range ['2017-02', '2017-03-31']: an array taken as is ('2017-02' parses to Feb 1)", option: cal1({ range: ['2017-02', '2017-03-31'] }) },
  { id: 'R5', note: "range ['2017-03-31', '2017-02-01']: a reversed pair is swapped (and the option array reversed IN PLACE: rangeOption)", option: cal1({ range: ['2017-03-31', '2017-02-01'] }) },
  { id: 'R6', note: "range ['2017-02']: a 1-element array is unwrapped -> the month", option: cal1({ range: ['2017-02'] }) },
  { id: 'R7', note: "range ['2016-11-01', '2017-02-28'] spans two years: the year label reads '2016-2017'", option: cal1({ range: ['2016-11-01', '2017-02-28'] }) },
  { id: 'R8', note: "range '2016-02': leap February (29 days)", option: cal1({ range: '2016-02' }) },
  { id: 'R9', note: "range ['2017-02-15', '2017-04-10']: starts mid-month -> the first split line and month label hang on Feb 15, the next on Mar 1 / Apr 1",
    option: cal1({ range: ['2017-02-15', '2017-04-10'] }) },
  { id: 'R10', note: "range '2017-12': the end + 1 day line falls on 2018-01-01", option: cal1({ range: '2017-12' }) },
  { id: 'R11', note: 'range as two numeric timestamps [Feb 1, Feb 28 2017 00:00Z] (UTC here: a local-time port must treat them as UTC wall dates only under TZ=UTC)',
    option: cal1({ range: [1485907200000, 1488240000000] }) },
  { id: 'R12', note: "range '2017-2-5' (single-digit month / day, one day)", option: cal1({ range: '2017-2-5' }) },
  // ----- firstDay -----
  { id: 'F0', note: 'firstDay 0 (explicit)', option: cal1({ range: '2017-02', dayLabel: { firstDay: 0 } }) },
  { id: 'F1', note: 'firstDay 1', option: cal1({ range: '2017-02', dayLabel: { firstDay: 1 } }) },
  { id: 'F3', note: 'firstDay 3', option: cal1({ range: '2017-02', dayLabel: { firstDay: 3 } }) },
  { id: 'F6', note: 'firstDay 6', option: cal1({ range: '2017-02', dayLabel: { firstDay: 6 } }) },
  { id: 'F7', note: "firstDay '1' (a string: +firstDay)", option: cal1({ range: '2017-02', dayLabel: { firstDay: '1' } }) },
  // ----- labels -----
  { id: 'L1', note: "dayLabel 'end', monthLabel 'end' + align 'left', yearLabel 'top' + formatter '{start}-{end}|{nameMap}' (-> '2017-2017|2017')",
    option: cal1({ range: '2017-02', dayLabel: { position: 'end' }, monthLabel: { position: 'end', align: 'left' }, yearLabel: { position: 'top', formatter: '{start}-{end}|{nameMap}' } }) },
  { id: 'L2', note: 'yearLabel position top / bottom / left / right, HORIZONTAL (four calendars stacked)',
    option: { calendar: ['top', 'bottom', 'left', 'right'].map((p, i) => ({ top: 40 + i * 140, range: '2017-02', yearLabel: { position: p } })) } },
  { id: 'L3', note: 'yearLabel position top / bottom / left / right, VERTICAL (four calendars side by side)',
    option: { calendar: ['top', 'bottom', 'left', 'right'].map((p, i) => ({ orient: 'vertical', left: 60 + i * 190, top: 80, range: '2017-02', yearLabel: { position: p } })) } },
  { id: 'L4', note: "monthLabel align 'left' (position start) horizontal; vertical: monthLabel 'end' + align 'left', dayLabel 'end'",
    option: { calendar: [{ range: ['2017-02-15', '2017-04-10'], monthLabel: { align: 'left' } },
      { orient: 'vertical', left: 500, top: 60, range: ['2017-02-15', '2017-04-10'], monthLabel: { position: 'end', align: 'left' }, dayLabel: { position: 'end' } }] } },
  { id: 'L5', note: "margins: dayLabel '50%' (parsePercent against min(sw, sh)), monthLabel 0, yearLabel 5; second calendar dayLabel '25%' with an auto 13.x cell",
    option: { calendar: [{ range: '2017-02', dayLabel: { margin: '50%' }, monthLabel: { margin: 0 }, yearLabel: { margin: 5 } },
      { top: 300, right: 20, cellSize: ['auto', 30], range: '2017', dayLabel: { margin: '25%' } }] } },
  { id: 'L6', note: 'show:false for yearLabel / monthLabel / dayLabel / splitLine one at a time (four calendars): the element groups disappear, the others keep their places',
    option: { calendar: [{ top: 40, range: '2017-02', yearLabel: { show: false } }, { top: 200, range: '2017-02', monthLabel: { show: false } },
      { top: 360, range: '2017-02', dayLabel: { show: false } }, { left: 400, top: 40, range: '2017-02', splitLine: { show: false } }] } },
  { id: 'L7', note: "nameMap 'cn' (NOT a preset: falls back to the chart locale EN), 'ZH', 'EN', 'zh' (case-sensitive: EN)",
    option: { calendar: ['cn', 'ZH', 'EN', 'zh'].map((n, i) => ({ top: 40 + i * 140, range: '2017-02', dayLabel: { nameMap: n }, monthLabel: { nameMap: n } })) } },
  { id: 'L8', note: "array nameMaps: dayLabel 8 entries (the 8th never read) + firstDay 1; monthLabel 12 custom; dayLabel 5 entries (indices 5, 6 -> undefined text); monthLabel 1 entry (Feb -> undefined)",
    option: { calendar: [
      { top: 40, range: '2017-02', dayLabel: { firstDay: 1, nameMap: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] }, monthLabel: { nameMap: ['M1', 'M2', 'M3', 'M4', 'M5', 'M6', 'M7', 'M8', 'M9', 'M10', 'M11', 'M12'] } },
      { top: 250, range: '2017-02', dayLabel: { nameMap: ['a', 'b', 'c', 'd', 'e'] }, monthLabel: { nameMap: ['only'] } }] } },
  { id: 'L9', note: "string formatters: month '{yyyy}-{MM} {M} {yy} {nameMap}', year '{start}-{end}|{nameMap}' over two years; repeats: month '{M}/{M}' and year '{start}{start}' (FIRST occurrence only); key order: '{MM}{M}' -> MM first, '{yy}{yyyy}' -> yyyy first",
    option: { calendar: [
      { top: 40, range: ['2016-11-01', '2017-02-28'], monthLabel: { formatter: '{yyyy}-{MM} {M} {yy} {nameMap}' }, yearLabel: { formatter: '{start}-{end}|{nameMap}' } },
      { top: 220, range: '2017-02', monthLabel: { formatter: '{M}/{M}' }, yearLabel: { formatter: '{start}{start}' } },
      { top: 400, range: '2017-02', monthLabel: { formatter: '{MM}{M}|{yy}{yyyy}' }, yearLabel: { formatter: '' } }] } },
  { id: 'L10', note: "String.replace $-patterns are live: monthLabel nameMap ['$&x', '$$', ...] with formatter '<{nameMap}>' -> '<{nameMap}x>' and '<$>'",
    option: { calendar: [{ range: ['2017-01', '2017-02-28'], monthLabel: { formatter: '<{nameMap}>', nameMap: ['$&x', '$$', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l'] } }] } },
  { id: 'L11', note: 'label style overrides: colour / fontSize / fontWeight / fontFamily / fontStyle on each label',
    option: cal1({ range: '2017-02', dayLabel: { color: '#c00', fontSize: 16, fontWeight: 'bold' }, monthLabel: { color: '#0a0', fontSize: 9, fontStyle: 'italic', fontFamily: 'serif' },
      yearLabel: { color: '#00c', fontSize: 30, fontWeight: 'normal', fontFamily: 'monospace' } }) },
  { id: 'L12', note: "global textStyle {fontFamily 'serif', fontSize 14, fontWeight 'bold', color '#123456'}: the day / month labels take family / size / weight from it (colour: the label default wins), the year label keeps its own sans-serif / 20 / bolder",
    option: cal1({ range: '2017-02' }, { textStyle: { fontFamily: 'serif', fontSize: 14, fontWeight: 'bold', color: '#123456' } }) },
  { id: 'L13', note: "garbage margins (documenting JS coercion): monthLabel 'start' margin '10%' -> -'10%' = NaN; yearLabel margin '7' on 'left' -> x - '7' = number; dayLabel margin '3' -> parsePercent 3",
    option: cal1({ range: '2017-02', monthLabel: { margin: '10%' }, yearLabel: { margin: '7' }, dayLabel: { margin: '3' } }) },
  { id: 'L14', note: 'labels silent: true on each label model -> the texts are silent', option: cal1({ range: '2017-02', dayLabel: { silent: true }, monthLabel: { silent: true }, yearLabel: { silent: true } }) },
  // ----- style -----
  { id: 'S1', note: "itemStyle {color '#eee', borderColor '#333', borderWidth 0.5}: lineWidth 0.5 -> contentRect inset 0.25", option: cal1({ range: '2017-02', itemStyle: { color: '#eee', borderColor: '#333', borderWidth: 0.5 } }) },
  { id: 'S2', note: 'itemStyle borderWidth 0: _lineWidth 0 -> contentRect = rect', option: cal1({ range: '2017-02', itemStyle: { borderWidth: 0 } }) },
  { id: 'S3', note: 'itemStyle borderWidth 3: inset 1.5', option: cal1({ range: '2017-02', itemStyle: { borderWidth: 3 } }) },
  { id: 'S4', note: 'splitLine.show false: no split / edge polylines, the labels still use the collected points', option: cal1({ range: '2017-02', splitLine: { show: false } }) },
  { id: 'S5', note: "splitLine.lineStyle {color '#f00', width 3, type 'dashed'}: edges extended by 1.5, dash [12, 6]", option: cal1({ range: '2017-02', splitLine: { lineStyle: { color: '#f00', width: 3, type: 'dashed' } } }) },
  { id: 'S6', note: 'a cell smaller than the border: cellSize 2, borderWidth 3 -> the contentRect collapses to 0 x 0 at the cell centre', option: cal1({ range: '2017-02', cellSize: 2, itemStyle: { borderWidth: 3 } }) },
  { id: 'S7', note: "itemStyle {opacity 0.5, borderType 'dotted', borderRadius 4, shadowBlur 3}; splitLine.lineStyle {type [5, 3], cap 'round', opacity 0.3, dashOffset 2}",
    option: cal1({ range: '2017-02', itemStyle: { opacity: 0.5, borderType: 'dotted', borderRadius: 4, shadowBlur: 3, shadowColor: '#000' },
      splitLine: { lineStyle: { type: [5, 3], cap: 'round', opacity: 0.3, dashOffset: 2 } } }) },
  { id: 'S8', note: 'z 5, zlevel 1 on the calendar: every element carries them', option: cal1({ range: '2017-02', z: 5, zlevel: 1 }) },
  // ----- dark -----
  { id: 'D1', note: 'darkMode: true: nothing in the calendar picture changes (colours are the light defaults)', option: cal1({ range: '2017-02' }, { darkMode: true }) },
  { id: 'D2', note: "backgroundColor '#100C2A' (zr dark mode on): nothing in the calendar picture changes", option: cal1({ range: '2017-02' }, { backgroundColor: '#100C2A' }) },
  { id: 'D3', note: "echarts.init(.., 'dark') -- the built-in dark THEME: its calendar block recolours the cells / labels (the split line keeps the light default)",
    theme: 'dark', option: cal1({ range: '2017-02' }) },
  // ----- probes with odd inputs -----
  { id: 'P1', note: "odd probe inputs: '' (TIME_REG matches the empty string -> Invalid Date), null, 'garbage', '2017-02-10T23:30:00-02:00' (UTC Feb 11 01:30), 1486684800000.4, '2017-02-10 25:00' (TIME_REG takes hour 25: rolls to Feb 11 01:00), '2017-02-10T12:00', '2017' (Jan 1: before the range)",
    option: cal1({ range: '2017-02' }), probes: { 0: ['', null, 'garbage', '2017-02-10T23:30:00-02:00', 1486684800000.4, '2017-02-10 25:00', '2017-02-10T12:00', '2017'] } },
];
// the gallery, verbatim minus series
for (const f of fs.readdirSync(GALLERY).filter(f => /^calendar-.*\.json$/.test(f) || f === 'custom-calendar-icon.json').sort()) {
  const name = f.replace(/\.json$/, '');
  CASES.push({ id: 'G-' + name, gallery: name, note: 'examples/advchart/gallery/' + f + ' verbatim with `series` removed' });
}

// ============================================================================
// Checks
// ============================================================================

function flat(v, p, out) {
  if (v !== null && typeof v === 'object') {
    for (const k of Object.keys(v)) flat(v[k], p + '.' + k, out);
  } else out[p] = v;
  return out;
}
// the transcription vs upstream, per calendar: [path, upstream, transcribed][]
function calDiffs(s, t) {
  const { rec, els } = s;
  const a = {};
  const b = {};
  const ri = rec.rangeInfo;
  flat({ range: ri.range, startTime: ri.start.time, endTime: ri.end.time, startDay: ri.start.day, endDay: ri.end.day, allDay: ri.allDay, weeks: ri.weeks,
    nthWeek: ri.nthWeek, fweek: ri.fweek, lweek: ri.lweek }, 'rangeInfo', a);
  flat(t.rangeInfo, 'rangeInfo', b);
  a.count = els.length;
  b.count = t.elements.length;
  const n = Math.min(els.length, t.elements.length);
  for (let i = 0; i < n; i++) {
    const e = els[i];
    const te = t.elements[i];
    const p = 'el' + i;
    a[p + '.kind'] = e.kind;
    b[p + '.kind'] = te.kind;
    if (e.kind !== te.kind) continue;
    if (e.kind === 'rect') { flat(e.shape, p + '.shape', a); flat(te.shape, p + '.shape', b); }
    else if (e.kind === 'polyline') { flat(e.points, p + '.points', a); flat(te.points, p + '.points', b); }
    else {
      const isYear = te.group === 'year';
      flat({ text: e.text, x: isYear ? e.x : e.style.x, y: isYear ? e.y : e.style.y, rotation: e.rotation, align: e.style.align, verticalAlign: e.style.verticalAlign,
        other: isYear ? [e.style.x, e.style.y] : [e.x, e.y] }, p, a);
      flat({ text: te.text, x: te.x, y: te.y, rotation: te.rotation, align: te.align, verticalAlign: te.verticalAlign, other: isYear ? [undefined, undefined] : [0, 0] }, p, b);
    }
  }
  rec.probes.forEach((pr, i) => {
    const tp = t.probes[i];
    flat({ point: pr.point, rect: pr.layout.rect, contentRect: pr.layout.contentRect, cal: pr.cal, day: pr.info.day, nth: pr._nthUp }, 'probe' + i, a);
    flat({ point: tp.point, rect: tp.rect, contentRect: tp.contentRect, cal: tp.cal, day: tp.day, nth: tp.nth }, 'probe' + i, b);
  });
  const out = [];
  for (const k of new Set(Object.keys(a).concat(Object.keys(b)))) {
    if (!Object.is(a[k], b[k])) out.push([k, a[k], b[k]]);
  }
  return out;
}

// the box + size, recomputed
function boxDiffs(s, theme) {
  const { rec, inp } = s;
  // the themes (default, dark) have no calendar box keys: the theme merge cannot move the box
  const opt = normaliseBox(rec.input || {}, null);
  const d = [];
  for (const k of LOC) {
    if (!Object.is(opt[k], rec.box[k]) || (k in opt) !== (k in rec.box)) d.push(['box.' + k, rec.box[k], opt[k]]);
  }
  if (JSON.stringify(opt.cellSize) !== JSON.stringify(rec.cellSizeOption)) d.push(['cellSizeOption', rec.cellSizeOption, opt.cellSize]);
  const weeks = rec.rangeInfo.weeks || 1;
  const cellNumbers = rec.orient === 'horizontal' ? [weeks, 7] : [7, weeks];
  const params = {};
  for (const k of LOC) params[k] = opt[k];
  const spec = i => opt.cellSize[i] != null && opt.cellSize[i] !== 'auto';
  [0, 1].forEach(i => { if (spec(i)) params[['width', 'height'][i]] = opt.cellSize[i] * cellNumbers[i]; });
  const r = echarts.helper.getLayoutRect(params, { width: W, height: H });
  for (const k of ['x', 'y', 'width', 'height']) if (!Object.is(r[k], rec.rect[k])) d.push(['rect.' + k, rec.rect[k], r[k]]);
  const sw = spec(0) ? opt.cellSize[0] : r.width / cellNumbers[0];
  const sh = spec(1) ? opt.cellSize[1] : r.height / cellNumbers[1];
  if (!Object.is(sw, rec.cellSize[0])) d.push(['sw', rec.cellSize[0], sw]);
  if (!Object.is(sh, rec.cellSize[1])) d.push(['sh', rec.cellSize[1], sh]);
  return d;
}

// the named claims of the task, recomputed independently
function claimChecks(c, s) {
  const { rec, els } = s;
  const key = c.id + '/' + rec.index;
  const t = transcribe(s.inp, {});
  const ri = rec.rangeInfo;
  // rect count == allDay
  must(els.filter(e => e.kind === 'rect').length === ri.allDay, key + ': rect count ' + els.filter(e => e.kind === 'rect').length + ' != allDay ' + ri.allDay);
  // split polylines == 1 + month firsts in (start, end] + 1 (+ 2 edges)
  const S = dnOf(ri.start.time);
  const E = dnOf(ri.end.time);
  let firsts = 0;
  for (let dn = S + 1; dn <= E; dn++) if (civil(dn).d === 1) firsts++;
  const polys = els.filter(e => e.kind === 'polyline').length;
  const expectPolys = s.inp.split.show ? firsts + 2 + 2 : 0;
  must(polys === expectPolys, key + ': ' + polys + ' polylines, expected ' + expectPolys);
  // the cell centre formula for every probe, and the two nthWeek forms agree
  const sw = rec.cellSize[0];
  const sh = rec.cellSize[1];
  rec.probes.forEach((p, i) => {
    const time = parseTime(p.input);
    must(Object.is(time, p.info.time) || (Number.isNaN(time) && Number.isNaN(p.info.time)), key + ': probe ' + i + ' time');
    const dn = dnOf(time);
    const nth = Math.floor((dn - S + ri.fweek) / 7);
    must(Object.is(nth, p._nthUp) || (Number.isNaN(nth) && Number.isNaN(p._nthUp)), key + ': probe ' + i + ' nthWeek ' + p._nthUp + ' vs floor((dn - S + fweek) / 7) = ' + nth);
    const day = dayOf(dn, rec.firstDay);
    const cx = rec.orient === 'horizontal' ? rec.rect.x + nth * sw + sw / 2 : rec.rect.x + day * sw + sw / 2;
    const cy = rec.orient === 'horizontal' ? rec.rect.y + day * sh + sh / 2 : rec.rect.y + nth * sh + sh / 2;
    const same = (u, v) => Object.is(u, v) || (Number.isNaN(u) && Number.isNaN(v));
    must(same(cx, p.cal.center[0]) && same(cy, p.cal.center[1]), key + ': probe ' + i + ' centre');
    const inRange = time >= ri.start.time && time < ri.end.time + DAY;
    must(inRange ? same(cx, p.point[0]) && same(cy, p.point[1]) : Number.isNaN(p.point[0]) && Number.isNaN(p.point[1]), key + ': probe ' + i + ' clamp');
    // contentRect = rect shrunk by lineWidth / 2 (width first, then x)
    const r = p.layout.rect;
    const cr = p.layout.contentRect;
    const h = rec.lineWidth / 2;
    if (r.width - rec.lineWidth >= 0) {
      must(same(cr.width, r.width + (-h + -h)) && same(cr.x, r.x - -h) && same(cr.height, r.height + (-h + -h)) && same(cr.y, r.y - -h), key + ': probe ' + i + ' contentRect');
    } else {
      must(cr.width === 0 && same(cr.x, r.x + r.width / 2), key + ': probe ' + i + ' collapsed contentRect');
    }
  });
  // the day-label anchors: day 0, nthWeek -1 / weeks
  for (const an of t.anchors) {
    must(an.day === 0 && an.nth === an.expectNth, key + ': the day-label anchor is day ' + an.day + ' week ' + an.nth);
    must(Object.is(an.nth, s.cs._getRangeInfo([ri.start.time, fmtDn(an.dn)]).nthWeek), key + ': the anchor week through upstream');
  }
  // week labels sit on the anchor column
  const weekEls = els.filter(e => e.group === 'week');
  if (weekEls.length) {
    const isStart = s.inp.dayLabel.position === 'start';
    const m = parsePercent(s.inp.dayLabel.margin, Math.min(sh, sw));
    weekEls.forEach((e, i) => {
      const nth = isStart ? -1 : ri.weeks;
      if (rec.orient === 'horizontal') {
        const cx = rec.rect.x + nth * sw + sw / 2;
        must(Object.is(e.style.x, cx + (isStart ? -m : m) + (isStart ? 1 : -1) * sw / 2) && Object.is(e.style.y, rec.rect.y + i * sh + sh / 2), key + ': week label ' + i);
      } else {
        const cy = rec.rect.y + nth * sh + sh / 2;
        must(Object.is(e.style.y, cy + (isStart ? -m : m) + (isStart ? 1 : -1) * sh / 2) && Object.is(e.style.x, rec.rect.x + i * sw + sw / 2), key + ': week label ' + i);
      }
    });
  }
}

const GUARDS = [
  { id: 'M1', mutation: 'nthWeek ignores fweek: floor((dn - S) / 7)', mut: { noFweek: true }, named: ['B5', 'F1', 'R4', 'O2'] },
  { id: 'M2', mutation: 'the day rect / corners taken directly as rect.x + nth*sw (no centre round trip)', mut: { tlDirect: true }, named: ['B2', 'B3', 'B7', 'B8', 'L5'] },
  { id: 'M3', mutation: 'contentRect shrunk by lineWidth instead of lineWidth / 2', mut: { fullInset: true }, named: ['B1', 'S1', 'S3'] },
  { id: 'M4', mutation: 'a collapsing contentRect keeps x -= delta (no centring)', mut: { collapseKeepsX: true }, named: ['S6'] },
  { id: 'M5', mutation: 'no split line at end + 1 day (months only)', mut: { noEndLine: true }, named: ['B1', 'R3', 'S4'] },
  { id: 'M6', mutation: 'edge lines not extended by the split lineWidth / 2', mut: { noEdgeExtend: true }, named: ['B1', 'S5'] },
  { id: 'M7', mutation: "the 'start' day-label anchor in week 0 (start - fweek) instead of week -1", mut: { startAnchorWeek0: true }, named: ['B1', 'F1'] },
  { id: 'M8', mutation: 'dayLabel margin not parsePercent-ed (+margin)', mut: { noPercentMargin: true }, named: ['L5'] },
  { id: 'M9', mutation: 'formatTplSimple replaces every occurrence, literally (no $-patterns)', mut: { tplAll: true }, named: ['L9', 'L10'] },
  { id: 'M10', mutation: "nameMap 'cn' as the ZH preset (ECharts 4)", mut: { cnIsZH: true }, named: ['L7', 'G-calendar-lunar', 'G-calendar-charts'] },
  { id: 'M10b', mutation: 'string nameMap looked up case-insensitively', mut: { caseInsensitive: true }, named: ['L7'] },
  { id: 'M11', mutation: 'month label centre from the week line top point (tlpoints[i]) instead of the first-day cell', mut: { monthCentreFromTl: true }, named: ['B1', 'R9'] },
  { id: 'M12', mutation: 'year label left / right not rotated', mut: { noYearRotate: true }, named: ['B1', 'L2'] },
];

function check(g) {
  const { out, side } = g;
  for (const c of out.cases) {
    c.calendars.forEach(cal => {
      const key = c.id + '/' + cal.index;
      const s = side[key];
      const d = calDiffs(s, transcribe(s.inp, {}));
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
      const bd = boxDiffs(s, c.theme);
      must(!bd.length, key + ': the box recomputation differs at ' + bd.slice(0, 4).map(x => JSON.stringify(x)).join('; '));
      claimChecks(c, s);
    });
  }
  // anchors (upstream.md's probe numbers)
  const byId = {};
  out.cases.forEach(c => { byId[c.id] = c; });
  const cal = (id, i) => byId[id].calendars[i || 0];
  const rectIs = (r, x, y, w, h) => r.x === x && r.y === y && r.width === w && r.height === h;
  must(rectIs(cal('B1').rect, 80, 60, 1060, 140) && cal('B1').counts.rect === 365 && cal('B1').counts.polyline === 15 && cal('B1').counts.text === 20, 'B1: rect, 365 / 15 / 20');
  must(rectIs(cal('B2').rect, 80, 450, 715, 140), 'B2: rect');
  must(rectIs(cal('B3').rect, 80, 60, 720, 140), 'B3: rect');
  must(rectIs(cal('B4').rect, 130, 120, 540, 140), 'B4: rect');
  must(rectIs(cal('B5').rect, 690, 60, 100, 140), 'B5: rect');
  must(rectIs(cal('B6').rect, 10, 60, 780, 210) && cal('B6').cellSize[0] === 156, 'B6: rect, forced auto');
  must(rectIs(cal('B7').rect, 80, 60, 400, 100), 'B7: rect');
  must(rectIs(cal('B8').rect, 80, 60, 720, 540), 'B8: rect');
  must(rectIs(cal('B9').rect, 520, 60, 140, 530) && cal('B9').cellSize[1] === 10, 'B9: rect');
  const b1e = cal('B1').elements.filter(e => e.group === 'edge');
  must(JSON.stringify(b1e[0].points) === '[[79.5,60],[1140.5,60]]' && JSON.stringify(b1e[1].points) === '[[79.5,200],[1120.5,200]]', 'B1: edges');
  const b1y = cal('B1').elements.find(e => e.group === 'year');
  must(b1y.x === 50 && b1y.y === 130 && b1y.rotation === Math.PI / 2 && b1y.text === '2017' && cal('B1').textCommon.year.z2 === 30 && cal('B1').dayRects.common.z2 === 0, 'B1: year label');
  must(cal('R3').counts.rect === 1 && cal('R3').counts.polyline === 4, 'R3: one day');
  must(cal('R5').rangeInfo.range.join() === '2017-02-01,2017-03-31' && cal('R5').rangeOption.join() === '2017-02-01,2017-03-31', 'R5: swapped in place');
  must(cal('R7').elements.find(e => e.group === 'year').text === '2016-2017', 'R7: two-year label');
  must(cal('L1').elements.find(e => e.group === 'year').text === '2017-2017|2017', 'L1: formatter');
  must(cal('L7', 0).elements.find(e => e.group === 'month').text === 'Feb' && cal('L7', 1).elements.find(e => e.group === 'month').text === '2月', 'L7: cn is EN, ZH is ZH');
  must(cal('S6').probes[0].layout.contentRect.width === 0, 'S6: collapsed');
  must(cal('S1').probes[0].layout.contentRect.x === cal('S1').probes[0].layout.rect.x + 0.25, 'S1: 0.25 inset');
  return GUARDS.map(gd => {
    const changed = [];
    for (const c of out.cases) {
      let any = false;
      for (const cl of c.calendars) {
        const s = side[c.id + '/' + cl.index];
        let t;
        try {
          t = transcribe(s.inp, gd.mut);
        } catch (e) {
          any = true;
          continue;
        }
        if (calDiffs(s, t).length) any = true;
      }
      if (any) changed.push(c.id);
    }
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(x => changed.includes(x)) };
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
      update: "echarts.init(null, theme, {renderer: 'svg', ssr: true, width: 800, height: 600}); setOption; zr.storage.getDisplayList(true) (every element updated, Text laid out into TSpans)",
      model: "ecModel.getComponent('calendar', i): option (box keys, cellSize, range after the run), getBoxLayoutParams(), getCellSize(), get('z' / 'zlevel')",
      coordSys: 'calendarModel.coordinateSystem: getRect, getCellWidth / Height, _lineWidth, getOrient, getFirstDayOfWeek, getRangeInfo, getDateInfo, dataToPoint([d]), dataToLayout([d]), dataToCalendarLayout([d], false), _getRangeInfo([start.time, formatedDate]).nthWeek (for the guard)',
      view: 'chart.getViewOfComponentModel(calendarModel).group.children(): Rect / Polyline / Text in group order; el.shape, el.style (own keys), el.x / y / rotation / originX / originY / scaleX / scaleY, el.z / z2 / zlevel / silent / cursor; a Text: childrenRef() = its TSpans (style.x / y / textAlign / textBaseline / font / fill / stroke / lineWidth / opacity)',
      production: 'every case is recorded again through dist/echarts.min.js and must record identically',
    },
    notes: [
      'TIMEZONE: the script sets process.env.TZ = UTC before touching Date. Upstream parses a zone-less date string as LOCAL time and reads every calendar quantity through local getters (useUTC is ignored), so string dates give the same picture in any zone whose DST does not switch at local midnight; a NUMERIC timestamp (probes, R11) is a UTC instant and lands on the UTC wall date only here.',
      'All elements of a calendar: z = the calendar z (default 2), zlevel = its zlevel; z2: day rects 0, split + edge polylines 20, labels 30. With several calendars in one chart the display list sorts by (zlevel, z, z2) stably, so ALL calendars\' day rects paint first, then all split lines, then all labels (paintRuns).',
      'Day rects: one per day from start to end (civil days), shape = dataToCalendarLayout(day, false).tl + [sw, sh] -- the tl is (centre) - sw/2, where centre = rect.x + nth*sw + sw/2: the round trip is not always rect.x + nth*sw bit for bit. Style = itemStyle.getItemStyle() (fill, stroke, lineWidth + whatever else the user set: opacity, lineDash from borderType, shadow*, ...); cursor \'default\'. No inset, no subPixelOptimize.',
      'Split lines: one per date in [start, month firsts after the start month while <= end, end + 1 day]: a 14-point polyline, points[2*day] = tl and points[2*day + 1] = bl (horizontal) / tr (vertical) of the 7 consecutive days from that date (a staircase). Then 2 edge lines: [first, last] of the collected points[0] (tl) and points[13] (bl) of every split line, extended by lineStyle.lineWidth / 2 along the orient axis at both ends. splitLine.show false draws none but the points are still collected.',
      "Year label (element x / y / rotation, style align / verticalAlign, z2 30): pts = [last split line's points[0], first split line's points[13]]; xc, yc their means; idx = horizontal ? 0 : 1; top [xc, pts[idx].y] y -= margin (center / bottom); bottom [xc, pts[1-idx].y] y += margin (center / top); left [pts[1-idx].x, yc] x -= margin (center / bottom, rotation PI/2); right [pts[idx].x, yc] x += margin (center / top, PI/2). Default position: horizontal 'left', vertical 'top'. Text: start year, + '-' + end year when later; formatter params {start, end, nameMap}.",
      "Month labels (style x / y / align / verticalAlign, z2 30): one per split line except the last; point = (position === 'start' ? points[0] : points[13]) of split line i; align 'center' moves the along-axis coordinate to (tl(date i) + points[0] of line i+1) / 2; margin negated for 'start'; horizontal y += margin, align center (if centred) else left, vAlign bottom ('start') else top; vertical x += margin, vAlign middle (if centred) else top, align right ('start') else left. Text nameMap[month - 1]; formatter params {yyyy, yy, MM, M (number), nameMap}. margin is NOT percent-parsed (JS coercion applies).",
      "Week labels (style x / y, z2 30): anchor = 'start' ? start - (7 + fweek) : end + (7 - lweek) days (day 0; week -1 / weeks); i = 0..6: centre of anchor + i; text nameMap[|(i + firstDay) % 7|]; margin = parsePercent(margin, min(sw, sh)), negated for 'start'; horizontal x = cx + margin + (start ? 1 : -1) * sw / 2, align right / left, vAlign middle; vertical y = cy + margin + (start ? 1 : -1) * sh / 2, vAlign bottom / top, align center.",
      "nameMap: a string is a CASE-SENSITIVE key into the registered locales ('EN', 'ZH' only); anything else (the gallery's 'cn', 'zh', 'en') falls back to the chart locale, EN in node/SSR. Months = time.monthAbbr, days = time.dayOfWeekShort or the first character of time.dayOfWeekAbbr (EN S M T W T F S, ZH 日 一 二 ...). An array is indexed Sunday = 0 / January = 0; a missing entry gives an undefined text (drawn as nothing).",
      "Formatter: a non-empty string -> formatTplSimple: for each param in insertion order, tpl.replace('{key}', value) -- FIRST occurrence only, and $-patterns in the value are live ($& = the matched '{key}', $$ = '$'). '' or null -> the plain name. (Functions cannot come from JSON.)",
      "Label fonts: createTextStyle over the label model: fontStyle / fontWeight / fontSize / fontFamily fall back to the global textStyle; the year label's defaults (sans-serif, bolder, 20) win over the global textStyle; colours: dayLabel / monthLabel '#54555a', yearLabel '#86878c'.",
      'Compaction: the day rects are one dayRects block (common part + flat xy), and every label shares the textCommon of its group unless it carries `own` (both checked lossless) -- the fixture stays well under 2 MB.',
      "Label layout in zrender (recorded, not transcribed): the TSpan gets textBaseline 'middle' and y = styleY - fontSize/2 (verticalAlign bottom), + fontSize/2 (top), unchanged (middle); x = styleX with textAlign = align. A NaN style.y (L13) lays the TSpan out as if y were 0. A label whose text is undefined (a short nameMap array) has no TSpan and paints nothing.",
      "Theme: darkMode / a dark backgroundColor change NOTHING in the calendar picture (D1, D2). The built-in 'dark' THEME (echarts.init(.., 'dark'), D3) recolours through its calendar block: cell fill rgba(0,0,0,1), cell border rgba(58,62,68,1), month / year labels rgba(203,203,206,1), day labels rgba(179,180,183,1); the split line keeps '#54555a' (the dark theme has no calendar splitLine) and the global textStyle gains color rgba(203,203,206,1) (unused by the labels, which have their own colour).",
    ],
    cases,
  };
  return { out, side };
}

const quiet = { error: console.error, warn: console.warn, log: console.log };
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
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ' (' + gd.mutation + '): named ' + gd.named.join(' / ') + '; changes ' + gd.changed.length + ': ' + gd.changed.join(', ')));
const deterministic = json1 === json2;
const nCal = out.cases.reduce((a, c) => a + c.calendars.length, 0);
const nEl = out.cases.reduce((a, c) => a + c.calendars.reduce((b, k) => b + k.elements.length + k.counts.rect, 0), 0);
console.log(out.cases.length + ' cases (' + nCal + ' calendars, ' + nEl + ' elements); ' + (out.guards.length - bad.length) + '/' + out.guards.length + ' guards; two generations '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + nSpecial + ' -0/Infinity values; ' + logged.length + ' console messages from upstream'
  + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
