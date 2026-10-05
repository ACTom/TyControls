// Upstream's own answers for WHICH axis labels a cartesian grid draws: the
// category auto interval, the list of labels each axis builds, the end-label
// rule (fixMinMaxLabelShow), axisLabel.hideOverlap, how the pass that shrinks
// the grid (estimate) hands its decision to the drawn one (determine), and the
// ticks, split lines, split areas and minor ticks that follow the labels.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, measuring every string with
// zrender's width table as grid-bounds.js does. Nothing in the dist is patched:
// AxisBuilder.prototype.build and Axis.prototype.calculateCategoryInterval are
// wrapped, reached through a warm chart's objects.
//
//   ratios    the 95 ratios of char codes 32..126, decoded from the width-table
//             string in the dist being run (and checked against the zrender
//             source when D:/Projects/zrender, or ZRENDER_SRC, is there), each
//             one also read back from a 1px Text. fontSize is the size a font
//             string without 'px' measures at.
//   measure   Text.getBoundingRect() width and height for strings x px, among
//             them every label and every sampled category text; the rule must
//             give the same Doubles or the run fails.
//   cases     one record per grid.
//
// Upstream lays a grid's axes out in passes (Grid.ts:207-279, 819-996). Under
// outerBoundsMode auto or same an ESTIMATE pass lays every axis out on the raw
// rect, the grid shrinks by what the estimate's shown labels (and names, under
// outerBoundsContain 'all') overflow, and a DETERMINE pass lays them out again on
// the final rect; that one is drawn. Under none and legacy there is only the
// determine pass. When no margin is positive (noPxChange) the determine pass
// takes the estimate's labels over as they stand (adopted).
//
// Per case:
//   W, H, grid, option   the canvas, which grid of the option, the option as run
//             (animation false; JSON only).
//   mode, contain, outer, clamp, raw, rect   as grid-bounds.js reads them.
//   margin    [t,r,b,l]: grid-bounds.js's shrink transcription fed the estimate
//             (auto and same only, else null). noPxChange: no margin > 0 (null
//             without an estimate).
//   tol       4 ulp(max(W, H)) / the smallest proportion the shrink divided by
//             (1 when it divided by none), as grid-bounds.js: the absolute
//             tolerance for a rect or coordinate the port builds itself.
//   axes      every axis of the grid in getAxes() order (x axes, then y):
//     dim, index (componentIndex), shown (axis.show; a hidden axis has no
//     passes), type, position, onBand, inverse, axisRotate (0 on x, 90 on y).
//     ordinalExtent [e0, e1] (getExtent of the ordinal scale), count
//     (scale.count()) and mappingExtent (the extent normalize maps from) on a
//     category axis, else null.
//     labelShow (axisLabel.show), rotate (axisLabel.rotate as the model has it,
//     so 0 by default), px (the label font's size), hideOverlap (JS truthiness
//     of axisLabel.hideOverlap), showMinLabel / showMaxLabel (null, true or
//     false), optionInterval ('auto' or the number), showAll (a category axis
//     whose interval is exactly 0), minorTickShow (minorTick.show, read on
//     every axis type).
//     axisTick / splitLine / splitArea: show (the model value; axisTick's may
//     be 'auto'), interval ('auto' or the number), alignWithLabel; axisTick
//     also shown (show resolved against the builder's axisTickAutoShow);
//     splitLine also showMinLine / showMaxLine.
//     passes    [estimate, determine] or [determine]. A pass:
//       kind, rect (the grid rect it laid out on), extent (the axis's pixel
//       extent then: [0, size], reversed when inverse), adopted (a determine
//       pass that took the estimate's labels over without laying them out; its
//       labels are the estimate's, field for field, which is checked).
//       category  on a category axis: {auto: true, kind, interval, unitSpan,
//                 extent, sampleStep, maxW, maxH, dw, dh, samples} when the pass
//                 called calculateCategoryInterval (an adopted determine pass
//                 repeats the estimate's call); kind is the call's ctx.kind,
//                 interval its return value ('Infinity' when infinite), unitSpan
//                 dataToCoord(e0 + 1) - dataToCoord(e0) taken at call time and
//                 extent the axis extent then. sampleStep, maxW, maxH, dw, dh
//                 (Infinity allowed; all null when e1 - e0 < 1 returned 0 first)
//                 and samples {values, texts, widths, heights} (parallel arrays:
//                 each sampled category, its formatted text, the widest line and
//                 ONE line's height, before the 1.3) are this generator's
//                 transcription of the call, which reproduces its return value
//                 (checked). {auto: false, interval} when the option names the
//                 interval; null when the pass computed none (labels off) or the
//                 axis is not a category axis.
//       labels    the labels the pass BUILT, in the builder's list order, which
//                 is ascending value order (checked): tick (the value; the raw
//                 ordinal on a category axis), text (as drawn, rich {name|x}
//                 markup stripped), offInterval, notNice, level (time level,
//                 else 0), priority, suggestIgnore, shown (not label.ignore after
//                 the pass), and the geometry: localRect (with the label's
//                 textMargin), bareLocalRect (the margin forced to 0, as
//                 fixMinMaxLabelShow uses it without hideOverlap), each
//                 [x, y, width, height]; transform (six numbers, or null) and
//                 axisAligned. The global rects are BoundingRect.applyTransform
//                 of the local ones through transform (checked, and left out).
//       geometryPartial, geometryKept   a pass of more than 60 labels, not under
//                 hideOverlap, keeps the geometry only of the labels listed in
//                 geometryKept (the first three, the last three and every one
//                 whose shown flag differs from a neighbour's); the others carry
//                 no localRect, bareLocalRect, transform or axisAligned.
//       determine only:
//         ticks       axis.getTicksCoords() as parallel arrays: values, coords
//                     (the axis's local coordinate), globalCoords, drawn (the
//                     tick element is in the scene and not ignored); onBand, one
//                     flag for the list.
//         splitLines  the same, from getTicksCoords with the splitLine model;
//                     drawn: a line_ element is in the scene.
//         splitAreas  the area_ rects in the scene: {values, rects}.
//         minorTicks  {count}: the minor tick elements in the scene.
//
// Self-checks (tallied over the compared cases):
//   width table   as grid-bounds.js; and every label's own box measures by it
//                 (label boxes).
//   recompute     every label's global rect, and its rect with the margin
//                 forced to 0, is its local rect through its transform.
//   autoInterval  axisTickLabelBuilder.ts:351-408 fed the sampled texts, the
//                 wrapped unitSpan and the rotations gives the wrapped return
//                 (Object.is, Infinity included).
//   unitSpan      makeExtentWithBands + linearMap from the pass rect gives the
//                 wrapped unitSpan.
//   built list    scale/helper.ts ordinalScaleCreateTicks from the pass's
//                 interval gives the category labels' values and offInterval.
//   thinning      fixMinMaxLabelShow and hideOverlap (AxisBuilder.ts:1061-1149,
//                 labelLayoutHelper.ts:522-608; BoundingRect and
//                 OrientedBoundingRect intersect, the OBB's negativeSize quirk
//                 included) fed the recorded geometry give every pass's shown
//                 flags.
//   passes        with noPxChange the determine pass is the estimate verbatim;
//                 after a shrink a value, log or time axis re-enters with
//                 suggestIgnore = not shown in the estimate, a category axis
//                 with none.
//   furniture     Axis.ts getTicksCoords / fixOnBandTicksCoords, the tick sync
//                 (AxisBuilder.ts:1154-1181), the split-line ends and the area
//                 pairs give the recorded ticks, split lines and areas.
//   shrink        grid-bounds.js's shrink transcription fed the estimate's shown
//                 labels (and names under 'all') gives rect.
//   drawn         the determine pass's shown flags are the scene's.
// Near-threshold guard: a case in which any intersection quantity the thinning
// transcription compared lies within 2 tol of its threshold (two edges, each
// within tol), or the smaller of a category dw and dh (the one floored) lies
// within 1e-9 (relative) of an integer, is deferred: a ulp could flip it.
//
// A case marked deferred depends on something the port does not do (a label
// font other than 12px, customValues, a string or fractional interval, axis
// breaks, axisLabel width / overflow / minMargin) or failed a check; its upstream
// answer is recorded all the same. A documentary case pins a port test's
// fixture and is compared like any other.
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase), because the Pascal JSON reader misparses integer literals above
// 2^63. Case- and pass-level numbers have a readable twin beside them
// (rectText beside rect, ...); the per-label and per-tick arrays do not, and the
// file is written without whitespace, to stay near 3 MB.
//
//   node tools/advchart-oracle/label-thinning.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// The development build asserts its own invariants and throws where the
// production build carries on; a case that trips one is run through the
// production build instead, which is what a page actually ships, and says so.
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-label-thinning.json');

// This generator's own assertions: never retried through the production build.
class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const RECT = ['x', 'y', 'width', 'height'];
const hexRect = r => (r ? { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) } : null);
const textRect = r => (r ? { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) } : null);
const plainRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const finiteRect = r => r && RECT.every(k => typeof r[k] === 'number' && Number.isFinite(r[k]));
const sameRect = (a, b) => (a === null || b === null ? a === b : RECT.every(k => Object.is(a[k], b[k])));
const sameArr = (a, b) => (a === null || b === null ? a === b
  : a.length === b.length && a.every((v, i) => Object.is(v, b[i])));
const hexArr = a => (a ? a.map(hex) : null);
const textArr = a => (a ? a.map(text) : null);

// The distance to the next Double up, for a positive finite x.
function ulp(x) {
  bits.setFloat64(0, x);
  const hi = bits.getUint32(0);
  const lo = bits.getUint32(4);
  if (lo === 0xffffffff) {
    bits.setUint32(0, hi + 1);
    bits.setUint32(4, 0);
  } else {
    bits.setUint32(4, lo + 1);
  }
  return bits.getFloat64(0) - x;
}

// ---------- the width table (as grid-bounds.js) ----------

const FIRST_CODE = 32;
const LAST_CODE = 126;
const DEFAULT_FONT_SIZE = 12;

function decodeTable(literal, where) {
  // the literal is JavaScript source (a quoted string in the dist, a template
  // literal in the TypeScript source): evaluate it as written
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1,
    where + ': the width table is not ' + (LAST_CODE - FIRST_CODE + 1) + ' characters');
  return s;
}
const mapStr = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m, ZRENDER_SRC + ': no defaultWidthMapStr');
    must(decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  } else {
    console.log('no zrender source at ' + ZRENDER_SRC + ': the width table is read from the dist only');
  }
  return s;
})();
// platform.ts getTextWidthMap: (charCode - OFFSET) / SCALE
const RATIO = Array.from(mapStr, ch => (ch.charCodeAt(0) - 20) / 100);

function measureText(t, font) {
  return new echarts.graphic.Text({ style: { text: t, font } }).getBoundingRect();
}
// Each ratio is what a 1px font measures its character at, and a font with no
// 'px' measures at DEFAULT_FONT_SIZE: the table decoded is the table in use.
RATIO.forEach((r, i) => {
  const ch = String.fromCharCode(FIRST_CODE + i);
  const w = measureText(ch, '1px sans-serif').width;
  must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
});
must(Object.is(measureText('0', 'sans-serif').width, RATIO['0'.charCodeAt(0) - FIRST_CODE] * DEFAULT_FONT_SIZE),
  'a font with no px does not measure at ' + DEFAULT_FONT_SIZE);

// The rule the port implements: per UTF-16 unit, left to right; the widest line;
// px per line.
function lineWidth(line, px) {
  let w = 0;
  for (let i = 0; i < line.length; i++) {
    const c = line.charCodeAt(i);
    const r = c >= FIRST_CODE && c <= LAST_CODE ? RATIO[c - FIRST_CODE] : null;
    w += r == null ? px : r * px;
  }
  return w;
}
function textBox(t, px) {
  const lines = String(t).split('\n');
  return { x: 0, y: 0, width: Math.max(...lines.map(l => lineWidth(l, px))), height: px * lines.length };
}
// zrender contain/text.ts getBoundingRect(text, font, 'center', 'top'), which the
// category auto interval measures with: the widest line, and ONE line high (the
// lines' rects are unioned at y = 0). (text || '') + '' as upstream.
function intervalBox(t, px) {
  const lines = ((t || '') + '').split('\n');
  return { width: Math.max(...lines.map(l => lineWidth(l, px))), height: px };
}
// the px zrender's node measurer reads off a font string (platform.ts)
function fontPx(font) {
  const m = /((?:\d+)?\.?\d*)px/.exec(String(font));
  return (m && +m[1]) || DEFAULT_FONT_SIZE;
}

const measure = [];
const measured = new Set();
function addMeasured(t, px) {
  if (t === '') return; // an empty Text has no line and measures 0 x 0
  const key = px + '\u0000' + t;
  if (measured.has(key)) return;
  measured.add(key);
  const r = measureText(t, px + 'px sans-serif');
  const f = textBox(t, px);
  must(Object.is(r.width, f.width) && Object.is(r.height, f.height),
    JSON.stringify(t) + ' at ' + px + 'px: Text measures ' + r.width + ' x ' + r.height
    + ', the rule gives ' + f.width + ' x ' + f.height);
  measure.push({ text: t, px, width: hex(r.width), widthText: text(r.width), height: hex(r.height), heightText: text(r.height) });
}
const MEASURED = ['0123456789', '1,000', '1,000,000,000', '20,000,000,000', '-40', '1.5', 'Mon', 'Wednesday',
  'Category 10', '\u56fd', '\u00e9', '\ud83d\ude00', 'Ab\tc', 'ab\nlonger line', 'Mon\nl2\nl3'];
for (const px of [9, 12, 14, 16]) MEASURED.forEach(t => addMeasured(t, px));

// rich-text markup {name|text} -> text
const stripRich = s => String(s).replace(/\{([A-Za-z0-9_]+)\|([^{}]*)\}/g, '$2');

// ---------- transcriptions: which labels ----------

// scale/helper.ts ordinalScaleCreateTicks: the ticks (and so the labels) a
// category axis builds at a given interval. JS arithmetic kept as written: a
// string or fractional interval goes through it the way upstream's does.
function ordinalTicks(e0, e1, count, interval) {
  const out = [];
  let start = e0;
  const step = Math.max((interval || 0) + 1, 1);
  if (start !== 0 && step > 1 && count / step > 2) start = Math.round(Math.ceil(start / step) * step);
  if (start !== e0) out.push({ value: e0, offInterval: true });
  let v = start;
  for (; v <= e1; v += step) out.push({ value: v, offInterval: false });
  if (v - step !== e1) out.push({ value: e1, offInterval: true });
  return out;
}

// axisTickLabelBuilder.ts:351-408 calculateCategoryInterval, the model cache
// left out (a fresh chart never reaches it). textOf(v) is the formatted label.
function autoInterval(e0, e1, count, unitSpan, axisRotate, labelRotate, px, textOf) {
  const rotation = (axisRotate - labelRotate) / 180 * Math.PI;
  if (e1 - e0 < 1) return { interval: 0, early: true };
  let step = 1;
  if (count > 40) step = Math.max(1, Math.floor(count / 40));
  const unitW = Math.abs(unitSpan * Math.cos(rotation));
  const unitH = Math.abs(unitSpan * Math.sin(rotation));
  let maxW = 0;
  let maxH = 0;
  const samples = [];
  for (let v = e0; v <= e1; v += step) {
    const t = textOf(v);
    const b = intervalBox(t, px);
    samples.push({ value: v, text: (t || '') + '', width: b.width, height: b.height });
    maxW = Math.max(maxW, b.width * 1.3, 7);
    maxH = Math.max(maxH, b.height * 1.3, 7);
  }
  let dw = maxW / unitW;
  let dh = maxH / unitH;
  if (isNaN(dw)) dw = Infinity;
  if (isNaN(dh)) dh = Infinity;
  return { early: false, step, unitW, unitH, maxW, maxH, dw, dh, samples, interval: Math.max(0, Math.floor(Math.min(dw, dh))) };
}

// number.ts linearMap, not clamped
function linearMap(val, domain, range) {
  const d0 = domain[0];
  const d1 = domain[1];
  const r0 = range[0];
  const r1 = range[1];
  const subDomain = d1 - d0;
  const subRange = r1 - r0;
  if (subDomain === 0) return subRange === 0 ? r0 : (r0 + r1) / 2;
  if (val === d0) return r0;
  if (val === d1) return r1;
  return (val - d0) / subDomain * subRange + r0;
}
// the linear scale mapper's normalize, from the mapping extent
function normalizeOn(m, val) {
  if (m[1] === m[0]) return 0.5;
  return (val - m[0]) / (m[1] - m[0]);
}
// Grid.ts updateAxisExtentTransByGridRect: [0, size], reversed when inverse
function pxExtent(a, rect) {
  const size = a.dim === 'x' ? rect.width : rect.height;
  return a.inverse ? [size, 0] : [0, size];
}
// Axis.ts makeExtentWithBands
function bandExtent(a, ext) {
  const e = ext.slice();
  if (a.onBand) {
    const size = e[1] - e[0];
    const margin = size / a.count / 2;
    e[0] += margin;
    e[1] -= margin;
  }
  return e;
}
// Axis.ts dataToCoord on a category axis
const catCoord = (a, ext, v) => linearMap(normalizeOn(a.mappingExtent, v), [0, 1], bandExtent(a, ext));

// ---------- transcriptions: overlap ----------

// BoundingRect.intersect(a, b, null, {touchThreshold: t}) (BoundingRect.ts:114-180);
// every pair of numbers it compared goes into q (their difference).
function aabbIntersect(a, b, t, q) {
  const ax0 = a.x + t;
  const ax1 = a.x + a.width - t;
  const ay0 = a.y + t;
  const ay1 = a.y + a.height - t;
  const bx0 = b.x + t;
  const bx1 = b.x + b.width - t;
  const by0 = b.y + t;
  const by1 = b.y + b.height - t;
  q.push(ax0 - ax1, ay0 - ay1, bx0 - bx1, by0 - by1);
  if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return false;
  q.push(ax1 - bx0, bx1 - ax0, ay1 - by0, by1 - ay0);
  return !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
}
// OrientedBoundingRect.fromBoundingRect (zrender OrientedBoundingRect.ts)
function obbOf(localRect, m) {
  const x = localRect.x;
  const y = localRect.y;
  const x2 = x + localRect.width;
  const y2 = y + localRect.height;
  let c = [[x, y], [x2, y], [x2, y2], [x, y2]];
  if (m) c = c.map(([px, py]) => [m[0] * px + m[2] * py + m[4], m[1] * px + m[3] * py + m[5]]);
  const axes = [[c[1][0] - c[0][0], c[1][1] - c[0][1]], [c[3][0] - c[0][0], c[3][1] - c[0][1]]].map(([vx, vy]) => {
    const len = Math.sqrt(vx * vx + vy * vy);
    return [vx / len, vy / len];
  });
  const origin = axes.map(ax => ax[0] * c[0][0] + ax[1] * c[0][1]);
  return { c, axes, origin };
}
// _getProjMinMaxOnAxis: `self`'s axis and origin, `corners` projected
function obbProject(self, dim, corners, t) {
  const ax = self.axes[dim];
  const o = self.origin[dim];
  let min = corners[0][0] * ax[0] + corners[0][1] * ax[1] + o;
  let max = min;
  for (let i = 1; i < corners.length; i++) {
    const p = corners[i][0] * ax[0] + corners[i][1] * ax[1] + o;
    min = Math.min(p, min);
    max = Math.max(p, max);
  }
  return [min + t, max - t];
}
// OrientedBoundingRect.intersect without an mtv: the SAT over this's axes, then
// other's. negativeSize is set by each projection and so, when tested, it is
// the OTHER box's (the second projection's) -- a quirk copied as it is.
function obbIntersect(A, B, t, q) {
  function side(self, other) {
    for (let i = 0; i < 2; i++) {
      const e = obbProject(self, i, self.c, t);
      const e2 = obbProject(self, i, other.c, t);
      const negativeSize = e2[1] < e2[0];
      q.push(e2[1] - e2[0], e[1] - e2[0], e[0] - e2[1]);
      if (negativeSize || e[1] < e2[0] || e[0] > e2[1]) return false;
    }
    return true;
  }
  if (!side(A, B)) return false;
  return side(B, A);
}
// labelLayoutHelper.ts labelIntersect: an ignored label never intersects; the
// AABBs first; the OBBs unless both are axis-aligned. g: {rect, localRect,
// transform, axisAligned}.
function labelIntersect(ig, i, j, gi, gj, t, q) {
  if (ig[i] || ig[j]) return false;
  if (!aabbIntersect(gi.rect, gj.rect, t, q)) return false;
  if (gi.axisAligned && gj.axisAligned) return true;
  return obbIntersect(obbOf(gi.localRect, gi.transform), obbOf(gj.localRect, gj.transform), t, q);
}

// AxisBuilder.ts:1061-1149 fixMinMaxLabelShow, then labelLayoutHelper.ts:522-577
// hideOverlap. Every label starts shown (updateAxisLabelChangableProps). spec:
// {type, showAll, hideOverlap, showMinLabel, showMaxLabel}; q collects the
// compared quantities of each threshold: q.fix (t = 0.1), q.hide (t = 0.05).
function thin(labels, spec, q) {
  const n = labels.length;
  const ig = labels.map(() => false);
  const geo = l => ({ rect: l.rect, localRect: l.localRect, transform: l.transform, axisAligned: l.axisAligned });
  const bare = l => ({ rect: l.bareRect, localRect: l.bareLocalRect, transform: l.transform, axisAligned: l.axisAligned });
  if (!spec.showAll) {
    const deal = (opt, out, inn) => {
      const L = labels[out];
      const I = labels[inn];
      if (!L || !I) return;
      if (opt == null) {
        // (customValues without hideOverlap returns here: such a case is deferred)
        if ((spec.type === 'time' && L.notNice) || (spec.type === 'category' && L.offInterval)) {
          ig[out] = true;
          return;
        }
      }
      if (opt === false || L.suggestIgnore) {
        ig[out] = true;
        return;
      }
      if (I.suggestIgnore) {
        ig[inn] = true;
        return;
      }
      const pick = spec.hideOverlap ? geo : bare;
      if (labelIntersect(ig, out, inn, pick(L), pick(I), 0.1, q.fix)) {
        if (opt) ig[inn] = true;
        else ig[out] = true;
      }
    };
    deal(spec.showMinLabel, 0, 1);
    deal(spec.showMaxLabel, n - 1, n - 2);
  }
  if (spec.hideOverlap) {
    const order = labels.map((l, i) => i).filter(i => !ig[i]);
    order.sort((a, b) => ((labels[b].suggestIgnore ? 1 : 0) - (labels[a].suggestIgnore ? 1 : 0))
      || (labels[b].priority - labels[a].priority));
    const kept = [];
    for (const i of order) {
      if (ig[i]) continue;
      let overlapped = false;
      for (let j = 0; j < kept.length; j++) {
        if (labelIntersect(ig, i, kept[j], geo(labels[i]), geo(labels[kept[j]]), 0.05, q.hide)) {
          overlapped = true;
          break;
        }
      }
      if (overlapped) ig[i] = true;
      else kept.push(i);
    }
  }
  return ig.map(v => !v);
}

// ---------- transcriptions: the grid (as grid-bounds.js) ----------

const XY = ['x', 'y'];
const WH = ['width', 'height'];
const XY_TO_MARGIN_IDX = [[3, 1], [0, 2]];
function expandRectOnOneDimension(rect, delta, xy, wh, ltIdx, rbIdx, minSize) {
  const deltaSum = delta[rbIdx] + delta[ltIdx];
  const oldSize = rect[wh];
  rect[wh] += deltaSum;
  minSize = Math.max(0, Math.min(minSize, oldSize));
  if (rect[wh] < minSize) {
    rect[wh] = minSize;
    rect[xy] += (
      delta[ltIdx] >= 0 ? -delta[ltIdx]
        : delta[rbIdx] >= 0 ? oldSize + delta[rbIdx]
          : Math.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[ltIdx] / deltaSum
            : 0
    );
  } else {
    rect[xy] -= delta[ltIdx];
  }
}
function expandOrShrinkRect(rect, delta, shrinkOrExpand, noNegative, minSize) {
  const d = delta.slice();
  if (noNegative) for (let i = 0; i < 4; i++) d[i] = Math.max(0, d[i]);
  if (shrinkOrExpand) for (let i = 0; i < 4; i++) d[i] = -d[i];
  expandRectOnOneDimension(rect, d, 'x', 'width', 3, 1, (minSize && minSize[0]) || 0);
  expandRectOnOneDimension(rect, d, 'y', 'height', 0, 2, (minSize && minSize[1]) || 0);
  return rect;
}
// estimate: [{dim, labels: [{rect, p}], name: {rect, p} | null}] in numbers.
function solveOuterBounds(raw, outer, contain, clamp, estimate) {
  const margin = [0, 0, 0, 0];
  let minP = Infinity;
  function applyProportion(overflow, proportion) {
    if (overflow > 0 && !Number.isNaN(proportion) && proportion > 1e-4) {
      overflow /= proportion;
      minP = Math.min(minP, proportion);
    }
    return overflow;
  }
  function fill(itemRect, xyIdx, proportion) {
    let overflow1 = outer[XY[xyIdx]] - itemRect[XY[xyIdx]];
    let overflow2 = (itemRect[WH[xyIdx]] + itemRect[XY[xyIdx]]) - (outer[WH[xyIdx]] + outer[XY[xyIdx]]);
    overflow1 = applyProportion(overflow1, 1 - proportion);
    overflow2 = applyProportion(overflow2, proportion);
    const minIdx = XY_TO_MARGIN_IDX[xyIdx][0];
    const maxIdx = XY_TO_MARGIN_IDX[xyIdx][1];
    margin[minIdx] = Math.max(margin[minIdx], overflow1);
    margin[maxIdx] = Math.max(margin[maxIdx], overflow2);
  }
  [0, 1].forEach(xyIdx => estimate.filter(a => a.dim === XY[xyIdx]).forEach(a => {
    a.labels.forEach(l => {
      fill(l.rect, xyIdx, l.p);
      fill(l.rect, 1 - xyIdx, NaN);
    });
    if (contain === 'all' && a.name) {
      fill(a.name.rect, xyIdx, a.name.p);
      fill(a.name.rect, 1 - xyIdx, NaN);
    }
  }));
  fill(raw, 0, NaN);
  fill(raw, 1, NaN);
  const rect = expandOrShrinkRect(plainRect(raw), margin, true, true, clamp);
  return { margin, rect, minP: minP === Infinity ? 1 : minP };
}
const OUTER_BOUNDS_DEFAULT = { left: 0, right: 0, top: 0, bottom: 0 };
// number.ts parsePositionSizeOption
function parsePositionSizeOption(option, percentBase) {
  if (typeof option === 'string') {
    if (/%$/.test(option.trim())) return parseFloat(option) / 100 * percentBase + 0;
    return parseFloat(option);
  }
  return option == null ? NaN : +option;
}
const isCenter = loc => loc === 'middle' || loc === 'center';

// ---------- running upstream ----------

const clone = o => JSON.parse(JSON.stringify(o));
// A function, undefined or non-finite number would not survive JSON: the option
// written would not be the option run.
function assertJson(v, where) {
  if (typeof v === 'function' || v === undefined) throw new OracleError(where + ': not JSON');
  if (typeof v === 'number') must(Number.isFinite(v), where + ': a non-finite number');
  if (v && typeof v === 'object') Object.keys(v).forEach(k => assertJson(v[k], where + '.' + k));
}

function render(lib, option, W, H) {
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart.setOption(clone(option));
  chart.renderToSVGString();
  return chart;
}

// getLabelInner(label) is a makeInner store: an '__ec_inner_<n>' key holding
// {labelInfo, layoutRotation}.
function labelInfoOf(label, where) {
  const found = Object.keys(label).filter(k => k.indexOf('__ec_inner_') === 0
    && label[k] && typeof label[k] === 'object' && label[k].labelInfo);
  must(found.length === 1, where + ': ' + found.length + ' inner stores with a labelInfo on the label');
  const info = label[found[0]].labelInfo;
  must(info.tick && typeof info.tick.value === 'number', where + ': the labelInfo has no numeric tick');
  return info;
}

const keyOf = axis => axis.dim + axis.model.componentIndex;

// A deep copy of the builder's label list as it stands.
function snapLabels(b, BR, where) {
  const axis = b._axisModel.axis;
  const scale = axis.scale;
  const ordinal = scale.type === 'ordinal';
  const list = (b._local && b._local.labelLayoutList) || [];
  const labels = list.map((l, k) => {
    const lw = where + ' label ' + k;
    must(l && l.label && l.label.style && typeof l.label.style.text === 'string', lw + ': no label text');
    must(finiteRect(l.rect) && finiteRect(l.localRect), lw + ': no finite rect');
    const tick = labelInfoOf(l.label, lw).tick;
    const value = ordinal ? scale.getRawOrdinalNumber(tick.value) : tick.value;
    must(!ordinal || value === tick.value, lw + ': a sorted category axis');
    let p = scale.normalize(value);
    p = axis.dim === 'y' ? 1 - p : p;
    const transform = l.transform ? Array.from(l.transform) : null;
    // computeLabelGeometry with every margin forced to 0: the text's own box,
    // through the label's transform (BoundingRect.applyTransform, in place)
    const bareLocalRect = plainRect(l.label.getBoundingRect());
    const br = new BR(bareLocalRect.x, bareLocalRect.y, bareLocalRect.width, bareLocalRect.height);
    if (transform) br.applyTransform(transform);
    const bareRect = plainRect(br);
    return {
      value, text: stripRich(l.label.style.text), rawText: l.label.style.text, font: String(l.label.style.font),
      offInterval: !!tick.offInterval, notNice: !!tick.notNice, level: (tick.time && tick.time.level) || 0,
      priority: l.priority, suggestIgnore: !!l.suggestIgnore, shown: !l.label.ignore, p,
      rect: plainRect(l.rect), localRect: plainRect(l.localRect), bareLocalRect, bareRect,
      transform, axisAligned: !!l.axisAligned, layout: l,
    };
  });
  for (let i = 1; i < labels.length; i++) must(labels[i - 1].value < labels[i].value, where + ': the label list is not in value order');
  // the shared record's labelInfoList is the shown labels, the very objects
  const rec = b._shared.ensureRecord(b._axisModel);
  const info = rec.labelInfoList || [];
  const shownLayouts = labels.filter(l => l.shown).map(l => l.layout);
  must(info.length === shownLayouts.length && info.every(li => shownLayouts.indexOf(li) >= 0),
    where + ': labelInfoList is not the shown labels');
  labels.forEach(l => delete l.layout);
  return labels;
}

// What is being captured: RUN.byGrid maps a grid to its passes; RUN.calls the
// calculateCategoryInterval calls.
let RUN = null;

const HOOKED = new Map();
function installHooks(lib) {
  if (HOOKED.has(lib)) return HOOKED.get(lib);
  const warm = render(lib, {
    xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [1, 2] }],
  }, 200, 200);
  const x = warm.getModel().getComponent('grid', 0).coordinateSystem.getAxes()[0];
  const AB = x.axisBuilder.constructor;
  let proto = x;
  while (proto && !Object.prototype.hasOwnProperty.call(proto, 'calculateCategoryInterval')) proto = Object.getPrototypeOf(proto);
  must(proto, 'no calculateCategoryInterval on the axis prototype chain');
  const BR = lib.graphic.BoundingRect;
  warm.dispose();

  const cci = proto.calculateCategoryInterval;
  proto.calculateCategoryInterval = function (ctx) {
    if (!RUN) return cci.apply(this, arguments);
    must(!ctx || ctx.kind === 1 || ctx.kind === 2, 'a ctx.kind ' + (ctx && ctx.kind));
    const se = this.scale.getExtent();
    const unitSpan = this.dataToCoord(se[0] + 1) - this.dataToCoord(se[0]);
    const extent = this.getExtent().slice();
    const r = cci.apply(this, arguments);
    RUN.calls.push({ axis: this, kind: ctx && ctx.kind === 1 ? 'estimate' : 'determine', interval: r, unitSpan, extent,
      building: RUN.building });
    return r;
  };

  const build = AB.prototype.build;
  AB.prototype.build = function (map, extra) {
    if (!RUN || !map) return build.apply(this, arguments);
    const axis = this._axisModel.axis;
    const grid = axis.grid;
    const key = keyOf(axis);
    const where = RUN.name + ' ' + key;
    let passes = RUN.byGrid.get(grid);
    if (!passes) RUN.byGrid.set(grid, passes = []);
    let cur = passes[passes.length - 1];
    const kind = map.axisTickLabelEstimate ? 'estimate' : map.axisTickLabelDetermine ? 'determine' : null;
    if (kind) {
      const before = this._local && this._local.labelLayoutList;
      RUN.building = { key, grid, kind };
      let res;
      try {
        res = build.apply(this, arguments);
      } finally {
        RUN.building = null;
      }
      if (!cur || cur.kind !== kind || cur.named || cur.axes.has(key)) {
        passes.push(cur = { kind, rect: plainRect(grid._rect), axes: new Map(), named: false });
      }
      must(sameRect(cur.rect, grid._rect), where + ': the grid rect moved inside a pass');
      const after = this._local.labelLayoutList;
      const noPxChange = !!(extra && extra.noPxChange);
      must(kind === 'determine' || !noPxChange, where + ': noPxChange in an estimate');
      cur.axes.set(key, {
        builder: this, noPxChange,
        adopted: kind === 'determine' && noPxChange && before != null && before === after,
        extent: axis.getExtent().slice(), labels: snapLabels(this, BR, where + ' ' + kind), name: null,
      });
      return res;
    }
    if (map.axisName) {
      must(cur && cur.axes.has(key), where + ': a name built outside a pass');
      const res = build.apply(this, arguments);
      cur.named = true;
      const rec = this._shared.ensureRecord(this._axisModel);
      const nl = rec.nameLayout;
      cur.axes.get(key).name = nl ? { rect: plainRect(nl.rect), p: isCenter(rec.nameLocation) ? 0.5 : NaN } : null;
      return res;
    }
    return build.apply(this, arguments);
  };
  const out = { BR };
  HOOKED.set(lib, out);
  return out;
}

// the scene elements under a group, by anid
function underGroup(el, g) {
  for (let p = el; p; p = p.parent) if (p === g) return true;
  return false;
}
function sceneOf(chart, axis) {
  const view = chart.getViewOfComponentModel(axis.model);
  must(view && view._axisGroup, 'no axis view group');
  const bg = axis.axisBuilder.group;
  const all = [];
  (function walk(e) {
    all.push(e);
    if (e.childrenRef) e.childrenRef().forEach(walk);
  })(view._axisGroup);
  const out = { ticks: new Map(), lines: new Map(), areas: new Map(), minor: 0, labels: new Map() };
  all.forEach(e => {
    if (!e.anid) return;
    const inB = underGroup(e, bg);
    let m;
    if (inB && (m = /^ticks_(.*)$/.exec(e.anid))) {
      must(!out.ticks.has(m[1]), 'two tick elements ' + e.anid);
      out.ticks.set(m[1], !e.ignore);
    } else if (inB && /^minorticks_/.test(e.anid)) {
      out.minor++;
    } else if (inB && (m = /^label_(.*)$/.exec(e.anid))) {
      out.labels.set(m[1], !e.ignore);
    } else if (!inB && (m = /^line_(.*)$/.exec(e.anid))) {
      must(!out.lines.has(m[1]), 'two split lines ' + e.anid);
      out.lines.set(m[1], true);
    } else if (!inB && (m = /^area_(.*)$/.exec(e.anid))) {
      must(!out.areas.has(m[1]), 'two split areas ' + e.anid);
      out.areas.set(m[1], plainRect(e.shape));
    }
  });
  return out;
}

// axisHelper.ts getOptionCategoryInterval
const optInterval = model => {
  const v = model.get('interval');
  return v == null ? 'auto' : v;
};
const triState = v => (v == null ? null : v);

function run(c, lib) {
  const hooks = installHooks(lib);
  const where = c.name;
  const option = clone(c.option);
  option.animation = false;
  RUN = { name: where, byGrid: new Map(), calls: [], building: null };
  let chart;
  let st;
  try {
    chart = render(lib, option, c.W, c.H);
  } finally {
    st = RUN;
    RUN = null;
  }
  try {
    const gm = chart.getModel().getComponent('grid', c.grid);
    must(gm && gm.coordinateSystem, where + ': no grid ' + c.grid);
    const cs = gm.coordinateSystem;
    const container = { x: 0, y: 0, width: c.W, height: c.H };
    const raw = plainRect(lib.helper.getLayoutRect(gm.getBoxLayoutParams(), container));
    let mode;
    if (gm.get('containLabel')) mode = 'legacy';
    else {
      const m = gm.get('outerBoundsMode', true);
      mode = m === 'same' ? 'same' : m == null || m === 'auto' ? 'auto' : 'none';
    }
    const oc = gm.get('outerBoundsContain', true);
    const contain = oc === 'axisLabel' ? 'axisLabel' : 'all';
    let outer = null;
    let clamp = null;
    if (mode === 'same') outer = plainRect(raw);
    if (mode === 'auto') {
      outer = plainRect(lib.helper.getLayoutRect(gm.get('outerBounds', true) || OUTER_BOUNDS_DEFAULT, container));
    }
    if (mode === 'same' || mode === 'auto') {
      const cw = gm.get('outerBoundsClampWidth', true);
      const ch = gm.get('outerBoundsClampHeight', true);
      clamp = [
        parsePositionSizeOption(cw != null ? cw : '25%', raw.width),
        parsePositionSizeOption(ch != null ? ch : '25%', raw.height),
      ];
    }
    const rect = plainRect(cs.getRect());
    must(finiteRect(rect), where + ': the final rect is not finite');

    const passes = st.byGrid.get(cs) || [];
    const shrinks = mode === 'auto' || mode === 'same';
    must(passes.length === (shrinks ? 2 : 1) && passes[passes.length - 1].kind === 'determine'
      && (!shrinks || passes[0].kind === 'estimate'), where + ': passes ' + passes.map(p => p.kind).join(', '));
    const est = shrinks ? passes[0] : null;
    const det = passes[passes.length - 1];
    must(!est || sameRect(est.rect, raw), where + ': the estimate pass is not on the raw rect');
    must(sameRect(det.rect, rect), where + ': the determine pass is not on the final rect');

    const axes = cs.getAxes().map(axis => {
      const key = keyOf(axis);
      const aw = where + ' ' + key;
      const model = axis.model;
      const scale = axis.scale;
      const cat = axis.type === 'category';
      const labelModel = axis.getLabelModel();
      const shown = !!model.getShallow('show');
      const font = labelModel.getFont();
      const a = {
        dim: axis.dim, index: model.componentIndex, key, shown, type: axis.type, position: axis.position,
        onBand: !!axis.onBand, inverse: !!axis.inverse, axisRotate: axis.isHorizontal() ? 0 : 90,
        ordinalExtent: null, count: null, mappingExtent: null,
        labelShow: !!model.get(['axisLabel', 'show']),
        rotate: triState(model.get(['axisLabel', 'rotate'])),
        labelRotate: labelModel.get('rotate') || 0,
        font, px: fontPx(font),
        hideOverlap: !!model.get(['axisLabel', 'hideOverlap']),
        showMinLabel: triState(model.get(['axisLabel', 'showMinLabel'])),
        showMaxLabel: triState(model.get(['axisLabel', 'showMaxLabel'])),
        optionInterval: optInterval(labelModel),
        minorTickShow: !!model.get(['minorTick', 'show']),
        formatter: labelModel.get('formatter'),
        unsupported: [],
      };
      a.showAll = cat && a.optionInterval === 0;
      [a.showMinLabel, a.showMaxLabel].forEach(v => must(v === null || typeof v === 'boolean', aw + ': showMin/MaxLabel ' + v));
      if (cat) {
        const e = scale.getExtent();
        a.ordinalExtent = [e[0], e[1]];
        a.count = scale.count();
        const mp = scale._mapper;
        must(mp && typeof mp.getExtentUnsafe === 'function', aw + ': no scale mapper');
        const me = (mp.getExtentUnsafe(1) || mp.getExtentUnsafe(0)).slice();
        a.mappingExtent = [me[0], me[1]];
        // the transcription's normalize is the scale's
        [e[0], e[0] + 1, e[1]].forEach(v => must(Object.is(normalizeOn(a.mappingExtent, v), scale.normalize(v)),
          aw + ': normalize(' + v + ') is not the mapping extent\'s'));
      }
      const tm = model.getModel('axisTick');
      const sl = model.getModel('splitLine');
      const sa = model.getModel('splitArea');
      a.axisTick = { show: triState(tm.get('show')), shown: false, interval: optInterval(tm), alignWithLabel: !!tm.get('alignWithLabel') };
      a.splitLine = { show: triState(sl.get('show')), interval: optInterval(sl), alignWithLabel: !!sl.get('alignWithLabel'),
        showMinLine: sl.get('showMinLine') !== false, showMaxLine: sl.get('showMaxLine') !== false };
      a.splitArea = { show: triState(sa.get('show')), interval: optInterval(sa), alignWithLabel: !!sa.get('alignWithLabel') };
      if (shown) {
        let s = tm.get('show');
        if (s === 'auto') {
          s = true;
          const autoShow = axis.axisBuilder._cfg.raw.axisTickAutoShow;
          if (autoShow != null) s = !!autoShow;
        }
        a.axisTick.shown = !!s;
      }
      // what the port does not do
      if (labelModel.get('customValues') || axis.getTickModel().get('customValues')) a.unsupported.push(key + ': customValues');
      if (cat) {
        [['axisLabel', a.optionInterval], ['axisTick', a.axisTick.interval], ['splitLine', a.splitLine.interval],
          ['splitArea', a.splitArea.interval]].forEach(([k, v]) => {
          if (v !== 'auto' && !(typeof v === 'number' && Number.isInteger(v))) {
            a.unsupported.push(key + ': ' + k + '.interval ' + JSON.stringify(v) + ' (string, fractional or function)');
          }
        });
      }
      const breaks = model.get('breaks');
      if (Array.isArray(breaks) && breaks.length) a.unsupported.push(key + ': axis breaks');
      if (labelModel.get('width') != null || labelModel.get('overflow') != null) {
        a.unsupported.push(key + ': axisLabel width / overflow in the measure');
      }
      if (labelModel.get('minMargin') != null) a.unsupported.push(key + ': axisLabel.minMargin');
      if (a.px !== DEFAULT_FONT_SIZE) a.unsupported.push(key + ': a label font other than 12px (the port\'s label font is the theme\'s)');
      must(typeof a.formatter !== 'function', aw + ': a function formatter');

      a.textOf = v => {
        // makeLabelFormatter for a category axis, no formatter or a string one
        const label = scale.getLabel({ value: v });
        return typeof a.formatter === 'string' ? a.formatter.replace('{value}', label != null ? label : '') : label;
      };

      const calls = st.calls.filter(k => k.axis === axis);
      calls.forEach(k => must(k.kind === 'determine' || (k.building && k.building.key === key && k.building.kind === 'estimate'),
        aw + ': an estimate interval outside the axis\'s estimate build'));
      const callOf = kind => {
        const ks = calls.filter(k => k.kind === kind);
        if (!ks.length) return null;
        ks.forEach(k => must(Object.is(k.interval, ks[0].interval) && Object.is(k.unitSpan, ks[0].unitSpan),
          aw + ': two ' + kind + ' interval calls disagree'));
        must(kind === 'determine' || ks.length === 1, aw + ': two estimate interval calls');
        return ks[0];
      };
      a.passes = [];
      [['estimate', est], ['determine', det]].forEach(([k, pass]) => {
        if (!pass) return;
        const s = pass.axes.get(key);
        must(!!s === shown, aw + ': shown ' + shown + ' but ' + (s ? '' : 'not ') + 'built in the ' + k + ' pass');
        if (!s) return;
        const rec = { kind: k, rect: plainRect(pass.rect), extent: s.extent, adopted: s.adopted, noPxChangeFlag: s.noPxChange,
          labels: s.labels, name: s.name, category: null };
        if (cat) {
          if (a.optionInterval !== 'auto') rec.category = { auto: false, interval: a.optionInterval };
          else {
            let call = callOf(k);
            if (k === 'determine' && s.adopted) {
              const ec = callOf('estimate');
              if (ec) {
                must(!call || Object.is(call.interval, ec.interval), aw + ': the adopted determine pass computed another interval');
                call = ec;
              }
            }
            if (call) rec.category = { auto: true, kind: call.kind, interval: call.interval, unitSpan: call.unitSpan, extent: call.extent };
          }
        }
        a.passes.push(rec);
      });
      // the drawn things, determine only
      if (shown) {
        const d = a.passes[a.passes.length - 1];
        const sc = sceneOf(chart, axis);
        const toG = v => axis.toGlobalCoord(v);
        d.sceneLabels = sc.labels;
        d.ticks = axis.getTicksCoords().map(t => ({ value: t.tickValue, coord: t.coord, globalCoord: toG(t.coord),
          onBand: !!t.onBand, drawn: sc.ticks.has(String(t.tickValue)) && sc.ticks.get(String(t.tickValue)) }));
        must(sc.ticks.size === 0 || sc.ticks.size === d.ticks.length, aw + ': ' + sc.ticks.size + ' tick elements, '
          + d.ticks.length + ' ticks');
        d.splitLines = axis.getTicksCoords({ tickModel: model.getModel('splitLine'), breakTicks: 'none',
          pruneByBreak: 'preserve_extent_bound' }).map(t => ({ value: t.tickValue, coord: t.coord, globalCoord: toG(t.coord),
          onBand: !!t.onBand, drawn: sc.lines.has(String(t.tickValue)) }));
        must(sc.lines.size === d.splitLines.filter(t => t.drawn).length, aw + ': a split line not in the list');
        d.splitAreaTicks = axis.getTicksCoords({ tickModel: model.getModel('splitArea'), breakTicks: 'none',
          pruneByBreak: 'preserve_extent_bound' }).map(t => ({ value: t.tickValue, coord: t.coord, onBand: !!t.onBand }));
        d.splitAreas = [];
        d.splitAreaTicks.forEach(t => {
          if (sc.areas.has(String(t.value))) d.splitAreas.push({ value: t.value, rect: sc.areas.get(String(t.value)) });
        });
        must(d.splitAreas.length === sc.areas.size, aw + ': a split area not in the list');
        d.minorTicks = { count: sc.minor };
        // the drawn labels are the determine pass's
        const now = snapLabels(axis.axisBuilder, hooks.BR, aw + ' after render');
        must(now.length === d.labels.length && now.every((l, i) => l.shown === d.labels[i].shown && l.value === d.labels[i].value),
          aw + ': the drawn labels are not the determine pass\'s');
      }
      return a;
    });
    // determine builds all got the grid's noPxChange (a single value per pass)
    const flags = new Set(Array.from(det.axes.values()).map(s => s.noPxChange));
    must(flags.size <= 1, where + ': the determine builds disagree on noPxChange');
    return { option, mode, contain, outer, clamp, raw, rect, axes, noPxChangeFlag: flags.size ? Array.from(flags)[0] : null };
  } finally {
    chart.dispose();
  }
}

function runEither(c) {
  try {
    return run(c, echarts);
  } catch (e) {
    if (e instanceof OracleError) throw e;
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

// ---------- cases ----------

const cases = [];
const add = (name, option, extra) => {
  assertJson(option, name);
  cases.push(Object.assign({ name, option, W: 600, H: 400, grid: 0 }, extra || {}));
};
// a case expected to be deferred, and why; the run must find the same
const deferred = why => ({ deferred: why });
const documentary = note => ({ documentary: true, note });

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const VALS = [120, 200, 150, 80, 70, 110, 130];
const LONG = DAYS.map(d => 'A very long category label ' + d);
const BIG9 = VALS.map(v => v * 1e7);
const BIG10 = VALS.map(v => v * 1e8);
const X68 = '{value} ' + 'X'.repeat(68);
const cats = (n, f) => Array.from({ length: n }, (_, i) => f(i));
const CN = n => cats(n, i => 'Category ' + (i + 1));
const PORTDATA = n => cats(n, i => 10 + ((i + 1) * 37) % 50);
function bar(grid, x, y, data) {
  const o = {};
  if (grid) o.grid = grid;
  o.xAxis = Object.assign({ type: 'category', data: DAYS }, x || {});
  o.yAxis = Object.assign({ type: 'value' }, y || {});
  o.series = [{ type: 'bar', data: data || VALS }];
  return o;
}
// the port's axislabel.pas DrawCats: n "Category i" bars at 900x520
function drawCats(n, axisLabel, axisTick, vertical) {
  const c = { type: 'category', data: CN(n) };
  if (axisLabel) c.axisLabel = axisLabel;
  if (axisTick) c.axisTick = axisTick;
  const v = { type: 'value' };
  return { xAxis: vertical ? v : c, yAxis: vertical ? c : v, series: [{ type: 'bar', data: PORTDATA(n) }] };
}
const P900 = { W: 900, H: 520 };
const cat30 = (x, extra) => Object.assign({ xAxis: Object.assign({ type: 'category', data: CN(30) }, x || {}),
  yAxis: { type: 'value' }, series: [{ type: 'bar', data: cats(30, i => i) }] }, extra || {});
const line30 = x => ({ xAxis: Object.assign({ type: 'category', boundaryGap: false, data: CN(30) }, x || {}),
  yAxis: { type: 'value' }, series: [{ type: 'line', data: cats(30, i => i) }] });
const c12 = x => ({ xAxis: Object.assign({ type: 'category', data: CN(12) }, x || {}), yAxis: { type: 'value' },
  series: [{ type: 'bar', data: PORTDATA(12) }] });
const hbar = x => ({ xAxis: Object.assign({ type: 'value', min: 0, max: 1e9, interval: 1e8 }, x || {}),
  yAxis: { type: 'category', data: DAYS }, series: [{ type: 'bar', data: VALS.map(v => v * 4e6) }] });
const T0 = Date.UTC(2024, 0, 3, 5, 0, 0);
const DAY = 864e5;
const tdata = n => cats(n, i => [T0 + i * DAY * 1.7, i]);
const timeLine = x => ({ useUTC: true, xAxis: Object.assign({ type: 'time' }, x || {}), yAxis: { type: 'value' },
  series: [{ type: 'line', data: tdata(40) }] });
const RAGGED = [['2024-03-01T07:13:00Z', 1], ['2024-03-01T19:48:00Z', 2]];
const ragged = x => ({ useUTC: true, xAxis: Object.assign({ type: 'time' }, x || {}), yAxis: {}, series: [{ type: 'line', data: RAGGED }] });
const longValue = (xl, max) => ({ grid: { left: 0, right: 0 },
  xAxis: { type: 'value', min: 0, max: max || 1000, interval: 100, axisLabel: Object.assign({ formatter: '{value} long-long-label' }, xl) },
  yAxis: { type: 'category', data: DAYS, axisLabel: { show: false } }, series: [{ type: 'bar', data: VALS }] });
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// ordinary charts: the common path
add('plain 7-day bar', bar());
add('line chart, 12 months', { xAxis: { type: 'category', data: MONTHS }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: [820, 932, 901, 934, 1290, 1330, 1320, 1100, 980, 1040, 1180, 1250] }] });
add('value/value scatter', { xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'scatter', data: [[10.0, 8.04], [8.07, 6.95], [13.0, 7.58], [9.05, 8.81], [11.0, 8.33], [14.0, 7.66], [4.0, 4.26]] }] });
add('time line chart, ragged ends', { useUTC: true, xAxis: { type: 'time' }, yAxis: { type: 'value' },
  series: [{ type: 'line', data: [['2024-01-03T05:17:00Z', 3], ['2024-01-19T11:00:00Z', 8], ['2024-02-02T00:00:00Z', 5],
    ['2024-02-20T18:40:00Z', 9]] }] });
add('log y axis', { xAxis: { type: 'category', data: DAYS }, yAxis: { type: 'log' },
  series: [{ type: 'line', data: [3, 40, 250, 1800, 9e3, 7e4, 5e5] }] });

// A. the category auto interval on x
add('A PM4 30 "Category N" at 900x520 (axislabel.pas:465)', drawCats(30), Object.assign({}, P900,
  documentary('the port\'s TestWithNoIntervalTheAxisStillThinsItself fixture: upstream picks 3, labels 1, 5, ..., 29; '
    + 'Category 30 is built off-interval and dropped by fixMinMaxLabelShow')));
add('A 30 "Category N" at 600x400', cat30());
add('A B long categories (grid-bounds B)', bar(null, { data: LONG }));
add('A long categories rotate 45', bar(null, { data: LONG, axisLabel: { rotate: 45 } }));
add('A long categories rotate 90', bar(null, { data: LONG, axisLabel: { rotate: 90 } }));
add('A 30 "Category N" rotate 45', cat30({ axisLabel: { rotate: 45 } }));
add('A 30 "Category N" on top, rotate 45', cat30({ position: 'top', axisLabel: { rotate: 45 } }));
add('A 30 "Category N" inverse', cat30({ inverse: true }));
add('A boundaryGap false, 30 "Category N" line', line30());
add('A N2 two long categories at 200 wide: none shown', bar(null, { data: LONG.slice(0, 2) }, null, [1, 2]), { W: 200 });
add('A three-line labels, 200 wide', bar(null, { data: DAYS.map(d => d + '\nline two is long\nx') }), { W: 200 });
add('A BIG 100 categories, the wide one at 1 is skipped by the sampling',
  { xAxis: { type: 'category', data: cats(100, i => (i === 1 ? 'W'.repeat(40) : 'c' + i)) }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: cats(100, i => i) }] }, { W: 900 });
add('A BIG2 100 categories, the wide one at 2 is sampled',
  { xAxis: { type: 'category', data: cats(100, i => (i === 2 ? 'W'.repeat(40) : 'c' + i)) }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: cats(100, i => i) }] }, { W: 900 });
add('A 120 "cN" at 400x300 (advancechart.pas:1427)',
  { xAxis: { data: cats(120, i => 'c' + i) }, yAxis: {}, series: [{ type: 'bar', data: [1] }] },
  Object.assign({ W: 400, H: 300 }, documentary('TestTheLayoutOwnsTheThinningDecision: upstream interval 13, c0 ... c112')));
add('A formatter string "<{value}>"', cat30({ axisLabel: { formatter: '<{value}>' } }));
add('A one category', bar(null, { data: ['only'] }, null, [1]));
add('A M6 outerBoundsClampWidth 0: the interval is Infinity (grid-bounds M6)',
  bar({ outerBoundsClampWidth: 0 }, null, { axisLabel: { formatter: X68 } }));
add('A M8 outerBoundsClampWidth 100 (grid-bounds M8)', bar({ outerBoundsClampWidth: 100 }, null, { axisLabel: { formatter: X68 } }));
add('A M7 outerBoundsClampWidth "50%" (grid-bounds M7)', bar({ outerBoundsClampWidth: '50%' }, null, { axisLabel: { formatter: X68 } }));
add('A X outerBounds {left:10,width:300} (grid-bounds X)', bar({ outerBounds: { left: 10, width: 300 } }));
add('A M5 outerBounds {left:10,width:300}, big10 (grid-bounds M5)', bar({ outerBounds: { left: 10, width: 300 } }, null, null, BIG10));
add('A O clamp one-sided (grid-bounds O)', bar(null, null, { axisLabel: { formatter: X68 } }));
add('A O3 clamp two-sided (grid-bounds O3)', {
  xAxis: { type: 'category', data: DAYS },
  yAxis: [{ type: 'value', axisLabel: { formatter: '{value} ' + 'X'.repeat(40) } },
    { type: 'value', position: 'right', axisLabel: { formatter: '{value} ' + 'X'.repeat(20) } }],
  series: [{ type: 'bar', data: VALS }, { type: 'line', yAxisIndex: 1, data: VALS }],
});
add('A ED 24 categories, wide y labels, grid left 0: the estimate interval is not the drawn one', {
  grid: { left: 0 }, xAxis: { type: 'category', data: cats(24, i => 'Cat ' + (i + 1)) },
  yAxis: { type: 'value', axisLabel: { formatter: '{value} XXXXXXXXXXXXXXXXXXXX' } }, series: [{ type: 'bar', data: cats(24, i => i) }] });
{
  const N = {
    grid: [{ left: 0, right: '55%', top: 0, bottom: 0 }, { left: '55%', right: 0, top: 0, bottom: 0 }],
    xAxis: [{ type: 'category', data: DAYS, gridIndex: 0 }, { type: 'category', data: DAYS, gridIndex: 1 }],
    yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
    series: [{ type: 'bar', data: BIG9, xAxisIndex: 0, yAxisIndex: 0 }, { type: 'bar', data: VALS, xAxisIndex: 1, yAxisIndex: 1 }],
  };
  add('A two grids (grid-bounds N): grid 0', N);
  add('A two grids (grid-bounds N): grid 1', N, { grid: 1 });
}
// no estimate: a lone determine pass on the raw rect
add('A outerBoundsMode none, 30 "Category N"', cat30(null, { grid: { outerBoundsMode: 'none' } }));
add('A containLabel (legacy), long categories rotate 45 (grid-bounds CL2)', bar({ containLabel: true }, { data: LONG, axisLabel: { rotate: 45 } }));
add('A containLabel (legacy), 120 "cN" at 400x300, labels off, ticks and split lines', { grid: { containLabel: true },
  xAxis: { data: cats(120, i => 'c' + i), axisLabel: { show: false }, axisTick: { show: true }, splitLine: { show: true } },
  yAxis: {}, series: [{ type: 'bar', data: [1] }] }, { W: 400, H: 300 });
add('D outerBoundsMode none, value x 0..1e9 at 400x300', Object.assign(hbar(), { grid: { outerBoundsMode: 'none' } }), { W: 400, H: 300 });
add('A a middle x name wider than the chart at 300x300 (axis-names #47)', {
  xAxis: { type: 'category', data: DAYS, nameLocation: 'middle', name: 'An extremely long axis name that is wider than the chart' },
  yAxis: { type: 'value', name: 'Value' }, series: [{ type: 'bar', data: VALS }] }, { W: 300, H: 300 });

// B. the category auto interval on y
add('B 50 categories on y', { xAxis: { type: 'value' }, yAxis: { type: 'category', data: cats(50, i => 'c' + i) },
  series: [{ type: 'bar', data: cats(50, i => i) }] });
add('B 50 categories on y, rotate 90', { xAxis: { type: 'value' },
  yAxis: { type: 'category', data: cats(50, i => 'c' + i), axisLabel: { rotate: 90 } }, series: [{ type: 'bar', data: cats(50, i => i) }] });
add('B 30 three-line categories on y', { xAxis: { type: 'value' }, yAxis: { type: 'category', data: cats(30, i => 'c' + i + '\nl2\nl3') },
  series: [{ type: 'bar', data: cats(30, i => i) }] });
add('B 30 "Category N" on y, rotate -30', { xAxis: { type: 'value' },
  yAxis: { type: 'category', data: CN(30), axisLabel: { rotate: -30 } }, series: [{ type: 'bar', data: cats(30, i => i) }] });

// C. intervals the option names
add('C interval 0 + showMinLabel false: fixMinMaxLabelShow is skipped', bar(null, { axisLabel: { interval: 0, showMinLabel: false } }));
add('C interval 1 + showMinLabel false', bar(null, { axisLabel: { interval: 1, showMinLabel: false } }));
add('C 8 categories, interval 1', bar(null, { data: cats(8, i => 'c' + i), axisLabel: { interval: 1 } }, null, cats(8, i => i)));
add('C interval 0, long categories, grid left/right 0 (grid-bounds AD)', bar({ left: 0, right: 0 }, { data: LONG, axisLabel: { interval: 0 } }));
add('C IM1 interval -1, long categories, grid left/right 0: not exempt', bar({ left: 0, right: 0 }, { data: LONG, axisLabel: { interval: -1 } }));
add('C 8 "Category N" interval 0 at 900x520 (axislabel.pas)', drawCats(8, { interval: 0 }), Object.assign({}, P900,
  documentary('TestIntervalZeroDrawsEveryLabel')));
add('C 8 "Category N" interval 1 at 900x520 (axislabel.pas)', drawCats(8, { interval: 1 }), Object.assign({}, P900,
  documentary('TestIntervalCountsWhatItSkipsNotWhatItKeeps')));
add('C 10 "Category N" interval 2 at 900x520 (axislabel.pas)', drawCats(10, { interval: 2 }), Object.assign({}, P900,
  documentary('TestIntervalTwoIsEveryThird')));
add('C 8 "Category N" interval -5 at 900x520 (axislabel.pas:498)', drawCats(8, { interval: -5 }), Object.assign({}, P900,
  documentary('TestANegativeIntervalMeansEveryOne')));
add('C 10 "Category N" interval 2, ticks interval 4 at 900x520 (axislabel.pas)', drawCats(10, { interval: 2 }, { interval: 4 }),
  Object.assign({}, P900, documentary('TestTheTicksFollowTheLabelsUnlessToldOtherwise')));
add('C M1 20 categories, min 1, interval 2: aligned from zero', { xAxis: { type: 'category', data: cats(20, i => 'c' + i), min: 1,
  axisLabel: { interval: 2 }, axisTick: { show: true, alignWithLabel: true } }, yAxis: { type: 'value' },
series: [{ type: 'bar', data: cats(20, i => i) }] });
add('C M2 20 categories, min 1, max 6, interval 2', { xAxis: { type: 'category', data: cats(20, i => 'c' + i), min: 1, max: 6,
  axisLabel: { interval: 2 } }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: cats(20, i => i) }] });
add('C 30 "Category N", showMaxLabel true', cat30({ axisLabel: { showMaxLabel: true } }));

// D. never thinned by index, and the end rule
add('D V1 value x 0..1e9 at 400x300', hbar(), { W: 400, H: 300 });
add('D V3 value x at 400, showMin/MaxLabel true', hbar({ axisLabel: { showMinLabel: true, showMaxLabel: true } }), { W: 400, H: 300 });
add('D V4 value x at 400, showMinLabel false', hbar({ axisLabel: { showMinLabel: false } }), { W: 400, H: 300 });
add('D V5 value x at 900', hbar(), { W: 900, H: 300 });
add('D V6 value x at 560: bare boxes 2px apart', hbar(), { W: 560, H: 300 });
add('D Y1 value y 0..100 by 5 at 400x200', { xAxis: { type: 'category', data: ['a', 'b'] },
  yAxis: { type: 'value', min: 0, max: 100, interval: 5 }, series: [{ type: 'bar', data: [1, 2] }] }, { W: 400, H: 200 });
add('D VY value y 0..3000 by 20 at 400x300 (advancechart.pas:694)',
  { xAxis: { data: ['A'] }, yAxis: { min: 0, max: 3000, interval: 20 }, series: [] },
  Object.assign({ W: 400, H: 300 }, documentary('TestACrowdedAxisThinsItsLabels: upstream shows 149 of 151')));
add('D S2 default bar at 300x200', bar(), { W: 300, H: 200 });
add('D log y at 400x150', { xAxis: { type: 'category', data: DAYS }, yAxis: { type: 'log' },
  series: [{ type: 'bar', data: [1, 10, 100, 1e3, 1e4, 1e5, 1e6] }] }, { W: 400, H: 150 });
add('D TM1 time x at 600', timeLine());
add('D TM2 time x at 250', timeLine(), { W: 250, H: 300 });
add('D TM4 time x, showMin/MaxLabel true', timeLine({ axisLabel: { showMinLabel: true, showMaxLabel: true } }));
add('D TM6 07:13..19:48 at 600x400', ragged());
add('D TM7 07:13..19:48, showMin/MaxLabel true', ragged({ axisLabel: { showMinLabel: true, showMaxLabel: true } }));
add('D 07:13..19:48 at 500x300 (time.pas:839)', ragged(), documentary('TestTheRaggedEndKeepsItsTickAndLosesItsLabel'));
cases[cases.length - 1].W = 500;
cases[cases.length - 1].H = 300;
add('D four days at 150x120 (time.pas:861)', { useUTC: true, xAxis: { type: 'time' }, yAxis: {},
  series: [{ type: 'line', data: [['2024-03-01T00:00:00Z', 1], ['2024-03-02T00:00:00Z', 2], ['2024-03-03T00:00:00Z', 3],
    ['2024-03-05T00:00:00Z', 4]] }] }, Object.assign({ W: 150, H: 120 }, documentary('TestTimeLabelsAreNeverThinnedByIndex'),
    deferred('grid box: top and bottom past the container height, which the grid box batch solves')));
add('D SG2 long value labels 0..600, grid left/right 0: the drawn pass hides more', longValue({}, 600), { H: 300 });
// grid-bounds W2 and 'inverse value x', options exactly as grid-bounds.js writes them
add('D W2 (grid-bounds): 20-line y labels, end labels hidden', {
  grid: { top: 10, bottom: 140 },
  xAxis: { type: 'category', data: DAYS },
  yAxis: { type: 'value', min: 0, max: 200, interval: 50,
    axisLabel: { formatter: '{value}' + '\nx'.repeat(19), showMinLabel: false, showMaxLabel: false } },
  series: [{ type: 'bar', data: VALS }],
});
add('D inverse value x (grid-bounds): long labels, end labels hidden', {
  grid: { left: 0, right: 0 },
  xAxis: { type: 'value', inverse: true, min: 0, max: 100, interval: 20,
    axisLabel: { formatter: '{value} eighty-eighty-eighty-eighty-eighty-eighty-eighty', showMinLabel: false, showMaxLabel: false } },
  yAxis: { type: 'category', data: DAYS, axisLabel: { show: false } },
  series: [{ type: 'bar', data: VALS.map(v => v / 3) }],
});
// the labels advchart-axis-labels.json records as not drawn (options as it writes them)
{
  const ab = cs => ({ xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: cs.y, series: [{ type: 'line', data: cs.data }] });
  add('D axis-labels #10 dataMin on 0.00077..0.002', ab({ y: { type: 'value', min: 'dataMin' }, data: [0.0007695205211639404, 0.002] }));
  add('D axis-labels #23 log 1..1e25 interval 1', ab({ y: { type: 'log', interval: 1 }, data: [1, 1e+25] }));
  add('D axis-labels #33 interval 0.7 on 0..5', ab({ y: { type: 'value', interval: 0.7 }, data: [0, 5] }));
  add('D axis-labels #34 min 0 max 5 interval 0.7', ab({ y: { type: 'value', min: 0, max: 5, interval: 0.7 }, data: [0, 5] }));
}

// E. hideOverlap
add('E V2 value x at 400, hideOverlap', hbar({ axisLabel: { hideOverlap: true } }), { W: 400, H: 300 });
add('E V6b value x at 560, hideOverlap: the margins overlap', hbar({ axisLabel: { hideOverlap: true } }), { W: 560, H: 300 });
add('E Y2 value y 0..100 by 5, hideOverlap', { xAxis: { type: 'category', data: ['a', 'b'] },
  yAxis: { type: 'value', min: 0, max: 100, interval: 5, axisLabel: { hideOverlap: true } }, series: [{ type: 'bar', data: [1, 2] }] },
{ W: 400, H: 200 });
add('E SG3 long value labels, showMinLabel true, hideOverlap: the picks invert', longValue({ showMinLabel: true, hideOverlap: true }), { H: 300 });
add('E SG4 0..600, showMinLabel true, hideOverlap', longValue({ showMinLabel: true, hideOverlap: true }, 600), { H: 300 });
add('E SG5 showMin/MaxLabel true, hideOverlap', longValue({ showMinLabel: true, showMaxLabel: true, hideOverlap: true }), { H: 300 });
add('E SG6 long value labels, hideOverlap only', longValue({ hideOverlap: true }), { H: 300 });
add('E AC hideOverlap, interval 0 long categories, grid left/right 0 (grid-bounds AC)',
  bar({ left: 0, right: 0 }, { data: LONG, axisLabel: { interval: 0, hideOverlap: true } }));
add('E TM3 time x at 250, hideOverlap: the levels go first', timeLine({ axisLabel: { hideOverlap: true } }), { W: 250, H: 300 });
add('E R1 30 "Category N" rotate 45, interval 0, hideOverlap: the OBB test', cat30({ axisLabel: { rotate: 45, interval: 0, hideOverlap: true } }));
add('E outerBoundsClamp 100%: the shrink still moves the rect and the picks invert', {
  grid: { left: 0, right: 0, outerBoundsClampWidth: '100%', outerBoundsClampHeight: '100%' },
  xAxis: { type: 'value', min: 0, max: 1000, interval: 100, axisLabel: { hideOverlap: true, formatter: '{value} long-long-label' } },
  yAxis: { type: 'category', data: ['Mon', 'Tue'], axisLabel: { formatter: '{value} XXXXXXXXXXXXXXXXXX' } },
  series: [{ type: 'bar', data: [1, 2] }] }, { H: 300 });

// F. the furniture that follows the labels
add('F T1 boundaryGap true, ticks and split lines', cat30({ axisTick: { show: true }, splitLine: { show: true } }));
add('F T2 boundaryGap false, ticks and split lines', line30({ axisTick: { show: true }, splitLine: { show: true } }));
add('F T3 boundaryGap false, tick interval 0, split interval 2',
  line30({ axisTick: { show: true, interval: 0 }, splitLine: { show: true, interval: 2 } }));
add('F T4 boundaryGap false, minorTick show: no tick sync', line30({ axisTick: { show: true }, minorTick: { show: true } }));
add('F T5 boundaryGap false, labels off', line30({ axisTick: { show: true }, axisLabel: { show: false } }));
add('F T6 boundaryGap true, alignWithLabel', cat30({ axisTick: { show: true, alignWithLabel: true }, splitLine: { show: true } }));
add('F BGF2 8 categories, interval 1, alignWithLabel', { xAxis: { type: 'category', data: cats(8, i => 'c' + i), axisLabel: { interval: 1 },
  axisTick: { show: true, alignWithLabel: true }, splitLine: { show: true } }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: cats(8, i => i) }] });
add('F 12 categories, labels interval 0, ticks shown (axislabel.pas:597 a)', drawCats(12, { interval: 0 }, { show: true }),
  Object.assign({}, P900, documentary('TestAnExplicitTickStrideChangesTheMarksOnScreen, first render: 13 marks')));
add('F 12 categories, labels interval 0, ticks interval 4 (axislabel.pas:597 b)', drawCats(12, { interval: 0 }, { show: true, interval: 4 }),
  Object.assign({}, P900, documentary('TestAnExplicitTickStrideChangesTheMarksOnScreen, second render: upstream 4 marks (0, 5, 10, 12)')));
add('F split lines follow the labels, not axisTick.interval',
  c12({ axisLabel: { interval: 0 }, axisTick: { show: true, interval: 4 }, splitLine: { show: true } }), P900);
add('F labels interval 4, axisTick.interval 0, split lines', c12({ axisLabel: { interval: 4 }, axisTick: { show: true, interval: 0 },
  splitLine: { show: true } }), P900);
add('F labels interval 4, split areas, splitLine interval 0', c12({ axisLabel: { interval: 4 }, splitArea: { show: true },
  splitLine: { show: true, interval: 0 } }), P900);
add('F labels interval 4, axisTick.interval 2, min 1', c12({ min: 1, axisLabel: { interval: 4 }, axisTick: { show: true, interval: 2 } }),
  P900);
add('F 11 categories, interval 4: the closing edge', { xAxis: { type: 'category', data: CN(11), axisLabel: { interval: 4 },
  axisTick: { show: true }, splitLine: { show: true } }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: PORTDATA(11) }] }, P900);
add('F 12 categories, interval 4, ticks and split lines', c12({ axisLabel: { interval: 4 }, axisTick: { show: true }, splitLine: { show: true } }), P900);
add('F 12 categories, interval 4, split areas', c12({ axisLabel: { interval: 4 }, splitArea: { show: true } }), P900);
add('F 12 categories, interval 0, split areas', c12({ axisLabel: { interval: 0 }, splitArea: { show: true } }), P900);
add('F 4 categories, split areas at 400x300 (furniture.pas:531)',
  { xAxis: { data: ['A', 'B', 'C', 'D'], splitArea: { show: true } }, yAxis: { min: 0, max: 100 }, series: [] },
  Object.assign({ W: 400, H: 300 }, documentary('TestSplitAreasStripeEveryOtherBand')));
add('F 120 categories, split lines at 400x300 (advancechart.pas:1468)',
  { xAxis: { data: cats(120, i => 'c' + i), splitLine: { show: true } }, yAxis: { min: 0, max: 100 }, series: [{ type: 'bar', data: [1] }] },
  Object.assign({ W: 400, H: 300 }, documentary('TestTheGridThinsWithTheLabels: 10 split lines')));
add('F 120 categories, splitLine interval 0', { xAxis: { data: cats(120, i => 'c' + i), splitLine: { show: true, interval: 0 } },
  yAxis: {}, series: [{ type: 'bar', data: [1] }] }, { W: 400, H: 300 });
add('F 120 categories, splitArea interval 9', { xAxis: { data: cats(120, i => 'c' + i), splitArea: { show: true, interval: 9 } },
  yAxis: {}, series: [{ type: 'bar', data: [1] }] }, { W: 400, H: 300 });
add('F 120 categories, labels off: ticks and lines still follow the interval', { xAxis: { data: cats(120, i => 'c' + i),
  axisLabel: { show: false }, axisTick: { show: true }, splitLine: { show: true } }, yAxis: {}, series: [{ type: 'bar', data: [1] }] },
{ W: 400, H: 300 });
add('F value x 0..4000 by 10, minor ticks (advancechart.pas:1529)',
  { xAxis: { min: 0, max: 4000, interval: 10, minorTick: { show: true, splitNumber: 4 } }, yAxis: {}, series: [{ type: 'line', data: [1] }] },
  Object.assign({ W: 400, H: 300 }, documentary('TestMinorTicksVanishWhenTheMajorsAreThinned: upstream 401 ticks, 1200 minor')));
add('F value x 0..4000 by 10, no minor ticks: the end ticks sync off',
  { xAxis: { min: 0, max: 4000, interval: 10 }, yAxis: {}, series: [{ type: 'line', data: [1] }] }, { W: 400, H: 300 });
add('F value x 0..40 by 10, minor ticks', { xAxis: { min: 0, max: 40, interval: 10, minorTick: { show: true, splitNumber: 4 } },
  yAxis: {}, series: [{ type: 'line', data: [1] }] }, { W: 400, H: 300 });
add('F time x 07:13..19:48, ticks shown: the ragged ends sync off', ragged({ axisTick: { show: true } }));

// G. the port's axislabel.pas trio
add('G 12 categories, interval 4 at 900x520 (axislabel.pas:548 a)', drawCats(12, { interval: 4 }), Object.assign({}, P900,
  documentary('TestShowMaxLabelReachesTheLayout, first render: 0, 5, 10')));
add('G 12 categories, interval 4, showMaxLabel true (axislabel.pas:548 b)', drawCats(12, { interval: 4, showMaxLabel: true }),
  Object.assign({}, P900, documentary('TestShowMaxLabelReachesTheLayout, second render: upstream 0, 5, 11 (10 overlaps 11 and goes)')));
add('G 12 categories, interval 4, showMinLabel false (axislabel.pas:548 c)', drawCats(12, { interval: 4, showMinLabel: false }),
  Object.assign({}, P900, documentary('TestShowMaxLabelReachesTheLayout, third render: 5, 10')));

// deferred: recorded, not compared
add('fontSize 20 on 30 "Category N"', cat30({ axisLabel: { fontSize: 20 } }),
  deferred('a label font other than 12px'));
add('customValues without hideOverlap', hbar({ axisLabel: { customValues: [0, 1e8, 2e8, 5e8, 9e8, 1e9] } }),
  Object.assign({ W: 400, H: 300 }, deferred('customValues')));
add('customValues with hideOverlap', hbar({ axisLabel: { customValues: [0, 1e8, 2e8, 5e8, 9e8, 1e9], hideOverlap: true } }),
  Object.assign({ W: 400, H: 300 }, deferred('customValues')));
add('interval "2" (a string)', { xAxis: { type: 'category', data: cats(10, i => 'c' + i), axisLabel: { interval: '2' } },
  yAxis: { type: 'value' }, series: [{ type: 'bar', data: cats(10, i => i) }] }, deferred('a string interval'));
add('interval 1.5', { xAxis: { type: 'category', data: cats(10, i => 'c' + i), axisLabel: { interval: 1.5 } },
  yAxis: { type: 'value' }, series: [{ type: 'bar', data: cats(10, i => i) }] }, deferred('a fractional interval'));
add('10 "Category N" interval 2.7 at 900x520 (axislabel.pas:506)', drawCats(10, { interval: 2.7 }),
  Object.assign({}, P900, deferred('a fractional interval: the port takes the whole part, a documented divergence')));
add('axis breaks on a value y axis', { xAxis: { type: 'category', data: DAYS },
  yAxis: { type: 'value', breaks: [{ start: 300, end: 900, gap: '2%' }] },
  series: [{ type: 'bar', data: [120, 200, 150, 1000, 1100, 110, 130] }] }, deferred('axis breaks'));
add('axisLabel width 40 overflow truncate, long categories', bar(null, { data: LONG, axisLabel: { width: 40, overflow: 'truncate' } }),
  deferred('axisLabel width / overflow'));
add('axisLabel width 60 overflow break, long categories', bar(null, { data: LONG, axisLabel: { width: 60, overflow: 'break' } }),
  deferred('axisLabel width / overflow'));
add('axisLabel minMargin 10, value x at 560', hbar({ axisLabel: { minMargin: 10 } }), Object.assign({ W: 560, H: 300 },
  deferred('axisLabel.minMargin')));

// ---------- check and write ----------

{
  const names = new Set();
  for (const c of cases) {
    if (names.has(c.name)) throw new Error('two cases named ' + c.name);
    names.add(c.name);
  }
}

const ulpMax = c => ulp(Math.max(c.W, c.H));
// self-check tally: name -> [ok, all], over the compared cases
const tally = new Map();
const failed = [];
const surprises = [];
// the closest call the guard let through: the smallest |quantity| / tol
const closest = { ratio: Infinity, where: null, q: null, tol: null };
const closestD = { rel: Infinity, where: null, v: null };

// A rect as [x, y, width, height] in hex.
const hexQuad = r => [hex(r.x), hex(r.y), hex(r.width), hex(r.height)];
// geo false: a label of a long pass whose geometry is left out (geometryPartial)
function labelRecord(l, geo) {
  const r = {
    tick: hex(l.value), text: l.text, offInterval: l.offInterval, notNice: l.notNice, level: l.level,
    priority: l.priority, suggestIgnore: l.suggestIgnore, shown: l.shown,
  };
  if (geo) {
    r.localRect = hexQuad(l.localRect);
    r.bareLocalRect = hexQuad(l.bareLocalRect);
    r.transform = hexArr(l.transform);
    r.axisAligned = l.axisAligned;
  }
  return r;
}
// A pass with more labels than this keeps the geometry of the first three, the
// last three and every label whose shown flag differs from a neighbour's; one
// under hideOverlap keeps all of it (every label is a candidate there).
const GEOMETRY_FULL_UP_TO = 60;
function geometryKept(labels, hideOverlap) {
  const n = labels.length;
  if (n <= GEOMETRY_FULL_UP_TO || hideOverlap) return null;
  return labels.map((l, i) => i).filter(i => i < 3 || i >= n - 3
    || (i > 0 && labels[i - 1].shown !== labels[i].shown) || (i < n - 1 && labels[i + 1].shown !== labels[i].shown));
}
// zrender BoundingRect.applyTransform (as axis-names.js), which makes rect from
// localRect and the bare rect from bareLocalRect: the fixture leaves bareRect out.
function rApply(src, m) {
  const t = plainRect(src);
  if (!m) return t;
  if (m[1] < 1e-5 && m[1] > -1e-5 && m[2] < 1e-5 && m[2] > -1e-5) {
    t.x = src.x * m[0] + m[4];
    t.y = src.y * m[3] + m[5];
    t.width = src.width * m[0];
    t.height = src.height * m[3];
    if (t.width < 0) {
      t.x += t.width;
      t.width = -t.width;
    }
    if (t.height < 0) {
      t.y += t.height;
      t.height = -t.height;
    }
    return t;
  }
  const pt = (x, y) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
  const lt = pt(src.x, src.y);
  const rt = pt(src.x + src.width, src.y);
  const rb = pt(src.x + src.width, src.y + src.height);
  const lb = pt(src.x, src.y + src.height);
  t.x = Math.min(lt[0], rb[0], lb[0], rt[0]);
  t.y = Math.min(lt[1], rb[1], lb[1], rt[1]);
  const maxX = Math.max(lt[0], rb[0], lb[0], rt[0]);
  const maxY = Math.max(lt[1], rb[1], lb[1], rt[1]);
  t.width = maxX - t.x;
  t.height = maxY - t.y;
  return t;
}
// A list of ticks as parallel arrays; onBand is one flag for the whole list.
function tickList(list, where) {
  const onBand = list.length ? list[0].onBand : false;
  must(list.every(t => t.onBand === onBand), where + ': a tick list that is only partly on band');
  return {
    onBand, values: list.map(t => hex(t.value)), coords: list.map(t => hex(t.coord)),
    globalCoords: list.map(t => hex(t.globalCoord)), drawn: list.map(t => t.drawn),
  };
}
const intervalOut = v => (v === Infinity ? 'Infinity' : v);
const sameLabel = (a, b) => Object.is(a.value, b.value) && a.text === b.text && a.offInterval === b.offInterval
  && a.notNice === b.notNice && a.level === b.level && a.priority === b.priority && a.suggestIgnore === b.suggestIgnore
  && a.shown === b.shown && sameRect(a.rect, b.rect) && sameRect(a.localRect, b.localRect)
  && sameRect(a.bareRect, b.bareRect) && sameArr(a.transform, b.transform) && a.axisAligned === b.axisAligned;

function recordOf(c) {
  const r = runEither(c);
  const unsupported = [];
  r.axes.forEach(a => a.unsupported.forEach(w => unsupported.indexOf(w) < 0 && unsupported.push(w)));
  r.axes.forEach(a => a.passes.forEach(p => p.labels.forEach(l => {
    if (fontPx(l.font) !== DEFAULT_FONT_SIZE) {
      const w = a.key + ': a label font other than 12px (the port\'s label font is the theme\'s)';
      if (unsupported.indexOf(w) < 0) unsupported.push(w);
    }
  })));
  const isDeferredByNature = unsupported.length > 0;

  const misses = [];
  const near = [];
  const results = [];
  const chk = (name, ok, detail) => {
    results.push([name, !!ok]);
    if (!ok) misses.push(name + ': ' + detail);
  };

  // the shrink
  const est = r.axes.some(a => a.passes.length === 2);
  let margin = null;
  let minP = 1;
  if (r.mode === 'auto' || r.mode === 'same') {
    const estimate = r.axes.filter(a => a.shown).map(a => {
      const e = a.passes[0];
      return { dim: a.dim, labels: e.labels.filter(l => l.shown).map(l => ({ rect: l.rect, p: l.p })), name: e.name };
    });
    const s = solveOuterBounds(r.raw, r.outer, r.contain, r.clamp, estimate);
    margin = s.margin;
    minP = s.minP;
    chk('shrink', sameRect(s.rect, r.rect), 'the shrink transcription gives ' + JSON.stringify(textRect(s.rect))
      + ', upstream ' + JSON.stringify(textRect(r.rect)));
  }
  const noPxChange = margin ? !margin.some(m => m > 0) : null;
  if (margin && r.noPxChangeFlag !== null) {
    chk('noPxChange', r.noPxChangeFlag === noPxChange, 'noPxChange ' + noPxChange + ', the determine builds got ' + r.noPxChangeFlag);
  }
  const tol = 4 * ulpMax(c) / minP;
  const gtol = 2 * tol;

  r.axes.forEach(a => {
    if (!a.shown) return;
    const cat = a.type === 'category';
    const e = a.passes.length === 2 ? a.passes[0] : null;
    const d = a.passes[a.passes.length - 1];
    a.passes.forEach(p => {
      const at = p.kind + ' ' + a.key;
      // every label's own box measures by the table
      p.labels.forEach(l => {
        addMeasured(l.text, fontPx(l.font));
        const b = l.text === '' ? { width: 0, height: 0 } : textBox(l.text, fontPx(l.font));
        chk('label boxes', Object.is(l.bareLocalRect.width, b.width) && Object.is(l.bareLocalRect.height, b.height),
          at + ' ' + JSON.stringify(l.text) + ': the box is ' + l.bareLocalRect.width + ' x ' + l.bareLocalRect.height
          + ', the table gives ' + b.width + ' x ' + b.height);
        chk('recompute', sameRect(rApply(l.localRect, l.transform), l.rect) && sameRect(rApply(l.bareLocalRect, l.transform), l.bareRect),
          at + ' ' + JSON.stringify(l.text) + ': rect or bareRect is not its local rect through the transform');
      });
      // the category interval
      let interval = null;
      if (cat && p.category) {
        if (!p.category.auto) interval = p.category.interval;
        else {
          const k = p.category;
          interval = k.interval;
          const t = autoInterval(a.ordinalExtent[0], a.ordinalExtent[1], a.count, k.unitSpan, a.axisRotate, a.labelRotate, a.px, a.textOf);
          k.t = t;
          chk('autoInterval', Object.is(t.interval, k.interval), at + ': the transcription gives ' + t.interval + ', upstream ' + k.interval);
          if (!t.early) {
            t.samples.forEach(s => addMeasured(s.text, a.px));
            // the one the floor is taken of (on a turned axis the other can be
            // ~1e16, an integer by magnitude alone, and decides nothing)
            const [nm, v] = t.dw <= t.dh ? ['dw', t.dw] : ['dh', t.dh];
            if (Number.isFinite(v) && Math.abs(v - Math.round(v)) <= 1e-9 * Math.abs(v)) near.push(at + ' ' + nm + ' ' + v);
            else if (Number.isFinite(v) && v > 0 && !isDeferredByNature && Math.abs(v - Math.round(v)) / v < closestD.rel) {
              Object.assign(closestD, { rel: Math.abs(v - Math.round(v)) / v, where: c.name + ' ' + at + ' ' + nm, v });
            }
          }
          // the unit from the pass rect
          const ext = pxExtent(a, p.rect);
          chk('unitSpan', sameArr(ext, k.extent) && Object.is(catCoord(a, ext, a.ordinalExtent[0] + 1) - catCoord(a, ext, a.ordinalExtent[0]), k.unitSpan),
            at + ': the unit from the pass rect is ' + (catCoord(a, ext, a.ordinalExtent[0] + 1) - catCoord(a, ext, a.ordinalExtent[0]))
            + ' on [' + ext + '], upstream ' + k.unitSpan + ' on [' + k.extent + ']');
        }
      }
      // the built list
      if (cat) {
        if (!a.labelShow) chk('built list', p.labels.length === 0, at + ': labels off, yet ' + p.labels.length + ' built');
        else {
          const want = interval === null ? null : ordinalTicks(a.ordinalExtent[0], a.ordinalExtent[1], a.count, interval);
          chk('built list', want && want.length === p.labels.length
            && want.every((w, i) => Object.is(w.value, p.labels[i].value) && w.offInterval === p.labels[i].offInterval),
          at + ': the transcription builds ' + JSON.stringify(want) + ', upstream '
            + JSON.stringify(p.labels.map(l => ({ value: l.value, offInterval: l.offInterval }))));
        }
      }
      // the thinning
      if (!(p.kind === 'determine' && p.adopted)) {
        const q = { fix: [], hide: [] };
        const shown = thin(p.labels, a, q);
        chk('thinning', shown.every((s, i) => s === p.labels[i].shown), at + ': the transcription shows '
          + JSON.stringify(p.labels.filter((l, i) => shown[i]).map(l => l.text)) + ', upstream '
          + JSON.stringify(p.labels.filter(l => l.shown).map(l => l.text)));
        q.fix.concat(q.hide).forEach(v => {
          if (Math.abs(v) <= gtol) near.push(at + ' an overlap quantity ' + v);
          else if (!isDeferredByNature && Math.abs(v) / tol < closest.ratio) Object.assign(closest, { ratio: Math.abs(v) / tol, where: c.name + ' ' + at, q: v, tol });
        });
      }
    });
    // the passes
    if (e) {
      if (noPxChange) {
        chk('passes', d.adopted && d.labels.length === e.labels.length && d.labels.every((l, i) => sameLabel(l, e.labels[i])),
          a.key + ': noPxChange, yet the determine pass is not the estimate');
      } else {
        const ok = !d.adopted && (cat ? d.labels.every(l => !l.suggestIgnore)
          : d.labels.length === e.labels.length && d.labels.every((l, i) => Object.is(l.value, e.labels[i].value)
            && l.suggestIgnore === !e.labels[i].shown));
        chk('passes', ok, a.key + ': after the shrink suggestIgnore is ' + JSON.stringify(d.labels.map(l => l.suggestIgnore))
          + ', the estimate showed ' + JSON.stringify(e.labels.map(l => l.shown)));
      }
    } else {
      chk('passes', !d.adopted && d.labels.every(l => !l.suggestIgnore), a.key + ': a lone determine pass with suggestIgnore');
    }
    // the drawn labels
    chk('drawn', d.labels.every(l => d.sceneLabels.get(String(l.value)) === l.shown),
      a.key + ': the scene\'s labels are not the determine pass\'s');

    // the furniture
    const ext = d.extent;
    const labelTicks = cat
      ? (d.category ? ordinalTicks(a.ordinalExtent[0], a.ordinalExtent[1], a.count, d.category.interval) : null)
      : d.labels.map(l => ({ value: l.value, offInterval: false }));
    const ticksFor = (interval, alignWithLabel) => {
      let list;
      if (!cat) list = labelTicks;
      else if (interval === 'auto') list = labelTicks;
      else list = ordinalTicks(a.ordinalExtent[0], a.ordinalExtent[1], a.count, interval);
      if (!list) return null;
      let out = list.map(t => ({ value: t.value, offInterval: t.offInterval, coord: cat ? catCoord(a, ext, t.value) : null, onBand: false }));
      if (cat && a.onBand && !alignWithLabel && out.length) {
        // Axis.ts fixOnBandTicksCoords, calcBandWidth for a category axis
        let len = (a.mappingExtent[1] - a.mappingExtent[0]) + 1;
        if (len === 0) len = 1;
        const bw = Math.abs(ext[1] - ext[0]) / len;
        if (bw) {
          out.forEach(t => { t.coord -= bw / 2; });
          const oldLast = out[out.length - 1];
          if (oldLast.offInterval) out.pop();
          out.push({ value: a.ordinalExtent[1] + 1, offInterval: false, coord: oldLast.coord + bw });
          out = out.map(t => Object.assign(t, { onBand: true }));
        }
      }
      return out;
    };
    const cmpList = (nm, want, got, drawnOf) => {
      if (!want) {
        chk('furniture', got.length === 0 || !got.some(t => t.drawn), a.key + ' ' + nm + ': no interval to transcribe from');
        return;
      }
      const ok = want.length === got.length && want.every((w, i) => Object.is(w.value, got[i].value)
        && w.onBand === got[i].onBand && (!cat || Object.is(w.coord, got[i].coord))
        && (!drawnOf || drawnOf(w, i) === got[i].drawn));
      chk('furniture', ok, a.key + ' ' + nm + ': the transcription gives '
        + JSON.stringify(want.map((w, i) => [w.value, w.onBand, drawnOf ? drawnOf(w, i) : null]))
        + ', upstream ' + JSON.stringify(got.map(t => [t.value, t.onBand, t.drawn === undefined ? null : t.drawn])));
    };
    const hiddenLabel = new Set(d.labels.filter(l => !l.shown).map(l => l.value));
    const tw = ticksFor(a.axisTick.interval, a.axisTick.alignWithLabel);
    cmpList('ticks', tw, d.ticks, w => a.axisTick.shown && !(!a.minorTickShow && !w.onBand && hiddenLabel.has(w.value)));
    const lw = ticksFor(a.splitLine.interval, a.splitLine.alignWithLabel);
    cmpList('split lines', lw, d.splitLines, (w, i) => !!a.splitLine.show && !(i === 0 && !a.splitLine.showMinLine)
      && !(i === lw.length - 1 && !a.splitLine.showMaxLine));
    const aw = ticksFor(a.splitArea.interval, a.splitArea.alignWithLabel);
    const areasWant = a.splitArea.show && aw ? aw.slice(0, -1).map(t => t.value) : [];
    chk('furniture', sameArr(areasWant, d.splitAreas.map(s => s.value)), a.key + ' split areas: the transcription gives '
      + JSON.stringify(areasWant) + ', upstream ' + JSON.stringify(d.splitAreas.map(s => s.value)));
    chk('furniture', a.minorTickShow || d.minorTicks.count === 0, a.key + ': minor ticks without minorTick.show');
  });

  results.forEach(([name, ok]) => {
    if (isDeferredByNature) return;
    const t = tally.get(name) || [0, 0];
    t[1]++;
    if (ok) t[0]++;
    tally.set(name, t);
  });
  if (misses.length) {
    if (isDeferredByNature) console.log(c.name + ' (deferred anyway): ' + misses.length + ' self-check misses');
    else failed.push(c.name + ': ' + misses.join('; '));
  }
  if (!!c.deferred !== isDeferredByNature) {
    surprises.push(c.name + ': ' + (c.deferred ? 'expected deferred (' + c.deferred + '), found nothing unsupported'
      : 'expected compared, found ' + unsupported.join('; ')));
  }

  const rec = { name: c.name, W: c.W, H: c.H, grid: c.grid, option: r.option, mode: r.mode, contain: r.contain };
  rec.outer = hexRect(r.outer);
  rec.outerText = textRect(r.outer);
  rec.clamp = r.clamp ? r.clamp.map(hex) : null;
  rec.clampText = r.clamp ? r.clamp.map(text) : null;
  rec.raw = hexRect(r.raw);
  rec.rawText = textRect(r.raw);
  rec.margin = margin ? margin.map(hex) : null;
  rec.marginText = margin ? margin.map(text) : null;
  rec.noPxChange = noPxChange;
  rec.rect = hexRect(r.rect);
  rec.rectText = textRect(r.rect);
  rec.tol = hex(tol);
  rec.tolText = text(tol);
  rec.axes = r.axes.map(a => {
    const out = {
      dim: a.dim, index: a.index, shown: a.shown, type: a.type, position: a.position, onBand: a.onBand, inverse: a.inverse,
      axisRotate: a.axisRotate,
      ordinalExtent: a.ordinalExtent, count: a.count,
      mappingExtent: hexArr(a.mappingExtent), mappingExtentText: textArr(a.mappingExtent),
      labelShow: a.labelShow, rotate: a.rotate, px: a.px, hideOverlap: a.hideOverlap,
      showMinLabel: a.showMinLabel, showMaxLabel: a.showMaxLabel,
      optionInterval: a.optionInterval, showAll: a.showAll, minorTickShow: a.minorTickShow,
      axisTick: a.axisTick, splitLine: a.splitLine, splitArea: a.splitArea,
      passes: a.passes.map(p => {
        const po = { kind: p.kind, rect: hexRect(p.rect), rectText: textRect(p.rect), extent: hexArr(p.extent), extentText: textArr(p.extent),
          adopted: p.adopted, category: null };
        const k = p.category;
        if (k && !k.auto) po.category = { auto: false, interval: k.interval };
        if (k && k.auto) {
          const t = k.t;
          const fin = v => (t && !t.early ? hex(v) : null);
          const fint = v => (t && !t.early ? text(v) : null);
          po.category = {
            auto: true, kind: k.kind, interval: intervalOut(k.interval),
            unitSpan: hex(k.unitSpan), unitSpanText: text(k.unitSpan), extent: hexArr(k.extent), extentText: textArr(k.extent),
            sampleStep: t && !t.early ? t.step : null,
            maxW: fin(t && t.maxW), maxWText: fint(t && t.maxW), maxH: fin(t && t.maxH), maxHText: fint(t && t.maxH),
            dw: fin(t && t.dw), dwText: fint(t && t.dw), dh: fin(t && t.dh), dhText: fint(t && t.dh),
            samples: t && !t.early ? { values: t.samples.map(s => s.value), texts: t.samples.map(s => s.text),
              widths: t.samples.map(s => hex(s.width)), heights: t.samples.map(s => hex(s.height)) } : null,
          };
        }
        const kept = geometryKept(p.labels, a.hideOverlap);
        if (kept) {
          po.geometryPartial = true;
          po.geometryKept = kept;
        }
        const keptSet = new Set(kept || []);
        po.labels = p.labels.map((l, i) => labelRecord(l, !kept || keptSet.has(i)));
        if (p.kind === 'determine') {
          po.ticks = tickList(p.ticks, c.name + ' ' + a.key + ' ticks');
          po.splitLines = tickList(p.splitLines, c.name + ' ' + a.key + ' split lines');
          po.splitAreas = { values: p.splitAreas.map(s => hex(s.value)), rects: p.splitAreas.map(s => hexQuad(s.rect)) };
          po.minorTicks = p.minorTicks;
        }
        return po;
      }),
    };
    return out;
  });
  const why = [];
  if (c.deferred) why.push(c.deferred);
  if (unsupported.length) why.push(unsupported.join('; '));
  if (misses.length && !isDeferredByNature) why.push('self-check: ' + misses.join('; '));
  if (near.length && !isDeferredByNature) why.push('near threshold: a ulp could flip it (' + near.slice(0, 3).join('; ') + ')');
  if (why.length) {
    rec.deferred = true;
    rec.why = why.join('; and ');
  }
  if (c.documentary) {
    rec.documentary = true;
    rec.note = c.note;
  }
  if (r.productionBuild) rec.productionBuild = true;
  if (!est && (r.mode === 'auto' || r.mode === 'same')) throw new OracleError(c.name + ': no estimate under ' + r.mode);
  return rec;
}

const out = {
  source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
  ratios: {
    firstCode: FIRST_CODE,
    lastCode: LAST_CODE,
    fontSize: DEFAULT_FONT_SIZE,
    ratio: RATIO.map(hex),
    ratioText: RATIO.map(text),
  },
  measure,
  cases: cases.map(recordOf),
};

// A number JSON.stringify would write as an integer literal past 2^63 goes
// out in exponent form instead: marked in the replacer, unquoted afterwards.
const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 0)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
surprises.forEach(s => console.log('deferral not as declared: ' + s));
failed.forEach(f => console.log('self-check failed: ' + f));
out.cases.filter(c => c.deferred).forEach(c => console.log('deferred: ' + c.name + ' -- ' + c.why.slice(0, 300)));
console.log('closest overlap quantity let through: ' + closest.q + ' (' + closest.ratio.toExponential(3) + ' tol) in ' + closest.where);
console.log('closest dw/dh to an integer let through: ' + closestD.v + ' (' + closestD.rel.toExponential(3) + ' relative) in ' + closestD.where);
console.log('self-checks (compared cases): ' + Array.from(tally, ([k, [ok, all]]) => k + ' ' + ok + '/' + all).join(', '));
fs.writeFileSync(OUT, json + '\n');
const d = out.cases.filter(c => c.deferred).length;
console.log('wrote', OUT, (out.cases.length - d) + ' cases + ' + d + ' deferred, ' + measure.length + ' measured strings');
process.exit(0);
