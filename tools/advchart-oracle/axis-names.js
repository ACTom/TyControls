// Upstream's own answers for where a cartesian axis puts its NAME: the anchor
// (nameLocation start / end / middle, nameGap, inverse, offset, onZero), the text
// layout (align, verticalAlign, rotation), the margin the name keeps (the
// nameMarginLevel tables, or nameTextStyle.textMargin / minMargin), and the moves
// nameMoveOverlap makes to clear the labels -- in the pass that shrinks the grid
// and in the one that is drawn.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, measuring every string with zrender's
// width table as grid-bounds.js does:
//
//   ratios    the 95 ratios of char codes 32..126, decoded from the width-table
//             string in the dist being run (and checked against the zrender
//             source when D:/Projects/zrender, or ZRENDER_SRC, is there), each
//             one also read back from a 1px Text. fontSize is the size a font
//             string without 'px' measures at.
//   measure   Text.getBoundingRect() width and height for strings x px, among
//             them every name and every line of one; the generator's own
//             reading of the rule must give the same Doubles or the run fails.
//   cases     one record per grid.
//
// Upstream builds a grid's axes in passes (Grid.ts:955-996): every axis's
// labels first, then every axis's name. Under outerBoundsMode auto or same with
// outerBoundsContain 'all' an ESTIMATE pass lays the axes out on the raw rect and
// the grid shrinks by what its labels and names overflow; the DETERMINE pass then
// lays them out again on the final rect, and that one is drawn. Both are read in
// the one real run, by wrapping AxisBuilder.prototype.build (which pass, and the
// nameMarginLevel it hands the name), the shared context's resolveAxisNameOverlap
// (the name before any move) and BoundingRect.intersect (each obstacle tested
// and the translation it gave).
//
// Per case:
//   W, H      the canvas, which is the container the margin level is taken
//             against. grid: which grid of the option the record is about.
//   option    as run (animation false). Only JSON: no formatter functions.
//   mode, contain   as grid-bounds.js reads them.
//   rect      the final grid rect: coordinateSystem.getRect().
//   tol       4 ulp(max(W, H)) / the smallest proportion the shrink divided by
//             (1 when it divided by none), as grid-bounds.js: the absolute
//             tolerance for anything the port builds from its own label boxes.
//   axes      every axis of the grid in getAxes() order (x axes, then y):
//     shown       axis.show; a hidden axis has no passes.
//     spec        the name options as the recipe reads them (this generator's
//                 reading, which the checks below hold to upstream): text
//                 (String(name) when name is truthy, else null), location
//                 (null -> 'end'), gap (nameGap || 0; absent -> 15), rotate
//                 (nameRotate in radians, null = auto), align / verticalAlign
//                 (nameTextStyle overrides or null), margin (kind 'level',
//                 'textMargin' or 'minMargin' and its four values; minMargin wins
//                 and is halved), moveOverlap (nameMoveOverlap; null / 'auto' ->
//                 !grid.containLabel; false without a name).
//     estimate    the estimate pass (auto or same with contain 'all' only), else
//                 null. determine: the drawn pass.
//   A pass:
//     rect        the grid rect the pass laid out on. container: W x H. level:
//                 the nameMarginLevel the pass handed this axis's name.
//     cfg         the AxisBuilder frame: position, rotation, labelOffset,
//                 nameDirection, axis.getExtent(), axis.inverse,
//                 shouldNameMoveOverlap.
//     dirVec      the shared record's axis direction (cos -r, sin -r).
//     labels      rec.labelInfoList in LIST order (sorted by distance from the
//                 axis origin; the moves walk it in this order): text, rect
//                 (global, with the label's textMargin), localRect, transform,
//                 axisAligned, ignore; layoutIndex, the label's index in the
//                 builder's labelLayoutList, which is the order the
//                 stOccupiedRect union takes them in; tick and p, the tick value
//                 and proportion grid-bounds.js records.
//     stOccupiedRect  the labels' union in the axis's standard frame, widened to
//                 the axis line (middle names only), or null.
//     name        null when there is no name, else: location, text, lines (the
//                 TSpan texts drawn), align, verticalAlign, localRotation (the
//                 text's rotation in the axis frame), box (Text.getBoundingRect),
//                 localRect (box plus margin), and before any move: anchor
//                 (x, y), transform (the six numbers of the composite
//                 transform), preRect (the global rect); axisAligned; moveDir
//                 (the move direction handed to the resolver, null when
//                 nameMoveOverlap is off); translations (every one applied, in
//                 order: from 'own' / 'perpendicular' / 'occupied', axis for a
//                 perpendicular list, label = the index in that list, x, y);
//                 then finalAnchor, finalTransform, rect (after the moves) and
//                 rotation (the Text's rotation once decomposed, -atan2(m1, m0)).
//
// Self-checks, each on every pass of every name:
//   a transcription of the recipe (the level from the pass rect, dirVec,
//   the text layout, the box measured with the table, the anchor and composite
//   transform, localRect, the pre-move rect, stOccupiedRect, every obstacle
//   tested and every translation, the final anchor, transform and rect, the
//   decomposed rotation) must reproduce upstream with Object.is; under auto and
//   same, grid-bounds.js's shrink transcription fed the estimate pass's labels
//   (and names, under 'all') must reproduce the final rect. A case whose name
//   needs something the port does not do (an OBB test: the AABBs meet and a
//   rect is turned; truncation, padding, lineHeight, a font or colour of its
//   own, an unknown nameLocation, a label font other than 12px) or that fails a
//   check is recorded all the same, deferred, with the reason.
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside them (rectText beside rect, ...),
// because the Pascal JSON reader misparses integer literals above 2^63.
//
//   node tools/advchart-oracle/axis-names.js
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
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-names.json');

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

const measure = [];
const measured = new Set();
function addMeasured(t, px) {
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

// ---------- transcriptions: zrender ----------

// Transformable.ts:7-11, 95-103: an element whose x, y and rotation are all
// within 5e-5 of 0 (scale 1, no skew) has no local transform.
const EPSILON = 5e-5;
const isNotAroundZero = v => v > EPSILON || v < -EPSILON;
const identity = () => [1, 0, 0, 1, 0, 0];
// matrix.ts rotate, pivot [0, 0]
function mRotate(a, rad) {
  const aa = a[0];
  const ac = a[2];
  const atx = a[4];
  const ab = a[1];
  const ad = a[3];
  const aty = a[5];
  const st = Math.sin(rad);
  const ct = Math.cos(rad);
  return [aa * ct + ab * st, -aa * st + ab * ct, ac * ct + ad * st, -ac * st + ct * ad,
    ct * (atx - 0) + st * (aty - 0) + 0, ct * (aty - 0) - st * (atx - 0) + 0];
}
// Transformable.getLocalTransform for x, y and rotation (no origin, anchor, scale
// or skew), null when needLocalTransform() says there is none
function mLocal(x, y, rotation) {
  if (!(isNotAroundZero(rotation) || isNotAroundZero(x) || isNotAroundZero(y))) return null;
  // m[4] = m[5] = 0; m[0] = sx; m[3] = sy; m[1] = skewY * sx; m[2] = skewX * sy
  let m = [1, 0 * 1, 0 * 1, 1, 0, 0];
  if (rotation) m = mRotate(m, rotation);
  m[4] += 0 + x;
  m[5] += 0 + y;
  return m;
}
// matrix.ts mul(out, m1, m2)
function mMul(m1, m2) {
  return [m1[0] * m2[0] + m1[2] * m2[1], m1[1] * m2[0] + m1[3] * m2[1],
    m1[0] * m2[2] + m1[2] * m2[3], m1[1] * m2[2] + m1[3] * m2[3],
    m1[0] * m2[4] + m1[2] * m2[5] + m1[4], m1[1] * m2[4] + m1[3] * m2[5] + m1[5]];
}
// matrix.ts invert
function mInvert(a) {
  const aa = a[0];
  const ac = a[2];
  const atx = a[4];
  const ab = a[1];
  const ad = a[3];
  const aty = a[5];
  let det = aa * ad - ab * ac;
  must(det, 'a singular transform');
  det = 1.0 / det;
  return [ad * det, -ab * det, -ac * det, aa * det, (ac * aty - ad * atx) * det, (ab * atx - aa * aty) * det];
}
// Transformable.updateTransform of a child: its local transform after the parent's
function mCompose(parent, local) {
  if (local) return parent ? mMul(parent, local) : local;
  return parent ? parent.slice() : null;
}
// BoundingRect.applyTransform
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
// BoundingRect.union, for finite rects
function rUnion(a, b) {
  const x = Math.min(b.x, a.x);
  const y = Math.min(b.y, a.y);
  a.width = Math.max(b.x + b.width, a.x + a.width) - x;
  a.height = Math.max(b.y + b.height, a.y + a.height) - y;
  a.x = x;
  a.y = y;
}
// graphic.ts isBoundingRectAxisAligned
const isAxisAligned = m => !m
  || (Math.abs(m[1]) < 1e-5 && Math.abs(m[2]) < 1e-5) || (Math.abs(m[0]) < 1e-5 && Math.abs(m[3]) < 1e-5);

// util/graphic.ts:608-672 (as grid-bounds.js)
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

// BoundingRect.intersect(a, b, mtv, {direction, bidirectional: false,
// touchThreshold: 0.05}) (BoundingRect.ts:114-180, 323-379, 441-517): whether the
// rects, each shrunk by 0.05 a side, overlap, and when they do the shortest
// translation of b along the direction that clears it.
function aabbIntersect(a, b, direction) {
  const t = 0.05;
  const ax0 = a.x + t;
  const ax1 = a.x + a.width - t;
  const ay0 = a.y + t;
  const ay1 = a.y + a.height - t;
  const bx0 = b.x + t;
  const bx1 = b.x + b.width - t;
  const by0 = b.y + t;
  const by1 = b.y + b.height - t;
  if (ax0 > ax1 || ay0 > ay1 || bx0 > bx1 || by0 > by1) return { overlap: false, mtv: null };
  const overlap = !(ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0);
  if (!overlap) return { overlap, mtv: null };
  const dirCos = Math.cos(direction);
  const dirSin = Math.sin(direction);
  const nearZero = v => Math.abs(v) < 1e-10;
  const len = p => Math.sqrt(p.x * p.x + p.y * p.y);
  let dirMinTv = { x: Infinity, y: Infinity };
  function calcDirMTV(minTv) {
    const squareMag = minTv.y * minTv.y + minTv.x * minTv.x;
    const dotProd = dirSin * minTv.y + dirCos * minTv.x;
    if (nearZero(dotProd)) {
      if (nearZero(minTv.x) && nearZero(minTv.y)) dirMinTv = { x: 0, y: 0 };
      return;
    }
    const tmp = { x: squareMag * dirCos / dotProd, y: squareMag * dirSin / dotProd };
    if (nearZero(tmp.x) && nearZero(tmp.y)) {
      dirMinTv = { x: 0, y: 0 };
      return;
    }
    if (dirCos * tmp.x + dirSin * tmp.y > 0 && len(tmp) < len(dirMinTv)) dirMinTv = tmp;
  }
  function oneDim(a0, a1, b0, b1, dim, zeroDim) {
    const d0 = Math.abs(a1 - b0);
    const d1 = Math.abs(b1 - a0);
    if (a1 < b0 || b1 < a0) return;
    calcDirMTV({ [dim]: d0, [zeroDim]: 0 });
    calcDirMTV({ [dim]: -d1, [zeroDim]: 0 });
  }
  oneDim(ax0, ax1, bx0, bx1, 'x', 'y');
  oneDim(ay0, ay1, by0, by1, 'y', 'x');
  return { overlap, mtv: dirMinTv };
}

// ---------- transcriptions: the name recipe ----------

// AxisBuilder.ts:87-90, as [top, right, bottom, left]
const CENTER_LEVELS = [[1, 2, 1, 2], [5, 3, 5, 3], [8, 3, 8, 3]];
const ENDS_LEVELS = [[0, 1, 0, 1], [0, 3, 0, 3], [0, 3, 0, 3]];
const DEFAULT_NAME_GAP = 15; // axisDefault.ts:47
const isCenter = loc => loc === 'middle' || loc === 'center';
const KNOWN_LOCATIONS = ['start', 'end', 'middle', 'center'];
// util/number.ts:470-481
function remRadian(r) {
  const pi2 = Math.PI * 2;
  return (r % pi2 + pi2) % pi2;
}
const isRadianAroundZero = v => v > -1e-4 && v < 1e-4;
// AxisBuilder.ts:592-620
function innerTextLayout(axisRotation, textRotation, direction) {
  const diff = remRadian(textRotation - axisRotation);
  let align;
  let vAlign;
  if (isRadianAroundZero(diff)) {
    vAlign = direction > 0 ? 'top' : 'bottom';
    align = 'center';
  } else if (isRadianAroundZero(diff - Math.PI)) {
    vAlign = direction > 0 ? 'bottom' : 'top';
    align = 'center';
  } else {
    vAlign = 'middle';
    align = diff > 0 && diff < Math.PI ? (direction > 0 ? 'right' : 'left') : (direction > 0 ? 'left' : 'right');
  }
  return { rotation: diff, align, vAlign };
}
// AxisBuilder.ts:1022-1053
function endTextLayout(rotation, textPosition, textRotate, extent) {
  const diff = remRadian(textRotate - rotation);
  const inverse = extent[0] > extent[1];
  const onLeft = (textPosition === 'start' && !inverse) || (textPosition !== 'start' && inverse);
  let align;
  let vAlign;
  if (isRadianAroundZero(diff - Math.PI / 2)) {
    vAlign = onLeft ? 'bottom' : 'top';
    align = 'center';
  } else if (isRadianAroundZero(diff - Math.PI * 1.5)) {
    vAlign = onLeft ? 'top' : 'bottom';
    align = 'center';
  } else {
    vAlign = 'middle';
    align = diff < Math.PI * 1.5 && diff > Math.PI / 2 ? (onLeft ? 'left' : 'right') : (onLeft ? 'right' : 'left');
  }
  return { rotation: diff, align, vAlign };
}
// contain/text.ts adjustTextX / adjustTextY
const adjustX = (x, w, align) => (align === 'right' ? x - w : align === 'center' ? x - w / 2 : x);
const adjustY = (y, h, vAlign) => (vAlign === 'middle' ? y - h / 2 : vAlign === 'bottom' ? y - h : y);
// zrender util normalizeCssArray
function normalizeCssArray(v) {
  if (typeof v === 'number') return [v, v, v, v];
  if (v.length === 2) return [v[0], v[1], v[0], v[1]];
  if (v.length === 3) return [v[0], v[1], v[2], v[1]];
  return v.slice();
}

// The name options, read as upstream reads them (S1): AxisBuilder.ts:519-541,
// 853-930, labelStyle.ts:464-480, Grid.ts:938.
function nameSpecOf(axisOpt, gridOpt) {
  const has = !!axisOpt.name;
  const nts = axisOpt.nameTextStyle || {};
  let margin;
  if (nts.minMargin != null) {
    const h = typeof nts.minMargin !== 'number' ? 0 : nts.minMargin / 2;
    margin = { kind: 'minMargin', value: [h, h, h, h] };
  } else if (nts.textMargin != null) {
    margin = { kind: 'textMargin', value: normalizeCssArray(nts.textMargin) };
  } else {
    margin = { kind: 'level', value: null };
  }
  let move = axisOpt.nameMoveOverlap;
  if (move == null || move === 'auto') move = !(gridOpt && gridOpt.containLabel);
  return {
    has,
    text: has ? String(axisOpt.name) : null,
    location: axisOpt.nameLocation == null ? 'end' : axisOpt.nameLocation,
    gap: ('nameGap' in axisOpt ? axisOpt.nameGap : DEFAULT_NAME_GAP) || 0,
    rotate: axisOpt.nameRotate == null ? null : axisOpt.nameRotate * Math.PI / 180,
    align: nts.align || null,
    verticalAlign: nts.verticalAlign || null,
    margin,
    moveOverlap: has && !!move,
  };
}

// One pass of one axis, from its spec, its frame and the pass's label geometry:
//   own    this axis's pass record (cfg, labels)
//   perps  the perpendicular axes' pass records, in componentIndex order
function transcribeAxis(spec, dim, own, perps, W, H) {
  const cfg = own.cfg;
  const rect = own.rect;
  // Grid.ts:976-982
  const level = dim === 'y' ? (rect.width <= W * 0.5 ? 0 : 2) : (rect.height <= H * 0.5 ? 0 : 1);
  // new Point(x, y) stores x || 0: a -0 (sin -0 on an x axis) is kept as 0
  const dirVecOf = c => [Math.cos(-c.rotation) || 0, Math.sin(-c.rotation) || 0];
  const dirVec = dirVecOf(cfg);
  const G = mLocal(cfg.position[0], cfg.position[1], cfg.rotation);
  const ext = cfg.extent;

  // AxisBuilder.ts resetOverlapRecordToShared: the shown labels in
  // labelLayoutList order, into the axis's standard frame, then the axis line
  let stOcc = null;
  if (spec.has && isCenter(spec.location)) {
    const inv = G ? mInvert(G) : identity();
    own.labels.slice().sort((a, b) => a.layoutIndex - b.layoutIndex).forEach(li => {
      const r = rApply(li.localRect, li.transform ? mMul(inv, li.transform) : inv);
      if (stOcc) rUnion(stOcc, r);
      else stOcc = r;
    });
    if (stOcc) {
      const lo = Math.min(ext[0], ext[1]);
      rUnion(stOcc, { x: lo, y: 0, width: Math.max(ext[0], ext[1]) - lo, height: 1 });
    }
  }
  const out = { level, dirVec, G, stOcc, name: null };
  if (!spec.has) return out;

  // AxisBuilder.ts:853-873: the anchor in the standard frame, the move direction
  const loc = spec.location;
  const gap = spec.gap;
  const s = cfg.inverse ? -1 : 1;
  let px = 0;
  let py = 0;
  const mv = { x: 0, y: 0 };
  if (loc === 'start') {
    px = ext[0] - s * gap;
    mv.x = -s;
  } else if (loc === 'end') {
    px = ext[1] + s * gap;
    mv.x = s;
  } else {
    px = (ext[0] + ext[1]) / 2;
    py = cfg.labelOffset + cfg.nameDirection * gap;
    mv.y = cfg.nameDirection;
  }
  const mt = mRotate(identity(), cfg.rotation);
  const moveDir = [mt[0] * mv.x + mt[2] * mv.y + mt[4], mt[1] * mv.x + mt[3] * mv.y + mt[5]];

  // :875-892, 927-930
  const layout = isCenter(loc)
    ? innerTextLayout(cfg.rotation, spec.rotate != null ? spec.rotate : cfg.rotation, cfg.nameDirection)
    : endTextLayout(cfg.rotation, loc, spec.rotate || 0, ext);
  const align = spec.align || layout.align;
  const vAlign = spec.verticalAlign || layout.vAlign;

  // Text.ts / parseText.ts: the widest line, px a line
  const lines = spec.text.split('\n');
  const w = Math.max(...lines.map(l => lineWidth(l, DEFAULT_FONT_SIZE)));
  const h = DEFAULT_FONT_SIZE * lines.length;
  const box = { x: adjustX(0, w, align), y: adjustY(0, h, vAlign), width: w, height: h };

  // the composite transform: the transform group's, then the text's
  const M = mCompose(G, mLocal(px, py, layout.rotation));
  must(M, 'a name with no transform');

  // labelLayoutHelper.ts:161-213
  const margin = spec.margin.kind === 'level' ? (isCenter(loc) ? CENTER_LEVELS : ENDS_LEVELS)[level] : spec.margin.value;
  const localRect = plainRect(box);
  if (spec.margin.kind !== 'minMargin') expandOrShrinkRect(localRect, margin, false, false);
  const preRect = rApply(localRect, M);
  if (spec.margin.kind === 'minMargin') expandOrShrinkRect(preRect, margin, false, false);
  const axisAligned = isAxisAligned(M);

  // AxisBuilder.ts:423-437 and Grid.ts:1050-1073
  const tested = [];
  const translations = [];
  let obb = false;
  const cur = { anchor: [M[4], M[5]], transform: M.slice(), rect: plainRect(preRect) };
  if (spec.moveOverlap) {
    const direction = Math.atan2(moveDir[1], moveDir[0]);
    const tryMove = (baseRect, baseAligned, from) => {
      if (obb) return; // past an OBB test the name is not where this transcription thinks
      tested.push(from);
      const r = aabbIntersect(baseRect, cur.rect, direction);
      if (!r.overlap) return;
      if (!(baseAligned && axisAligned)) {
        obb = true;
        return;
      }
      cur.anchor[0] += r.mtv.x;
      cur.anchor[1] += r.mtv.y;
      cur.transform[4] += r.mtv.x;
      cur.transform[5] += r.mtv.y;
      cur.rect.x += r.mtv.x;
      cur.rect.y += r.mtv.y;
      translations.push(Object.assign({}, from, { x: r.mtv.x, y: r.mtv.y }));
    };
    if (isCenter(loc)) {
      if (stOcc) tryMove(rApply(stOcc, G), isAxisAligned(G), { from: 'occupied' });
    } else {
      const linear = (list, baseDirVec, from) => {
        const sameDir = moveDir[0] * baseDirVec[0] + moveDir[1] * baseDirVec[1] >= 0;
        for (let i = 0; i < list.length; i++) {
          const k = sameDir ? i : list.length - 1 - i;
          if (!list[k].ignore) tryMove(list[k].rect, list[k].axisAligned, Object.assign({}, from, { label: k }));
        }
      };
      linear(own.labels, dirVec, { from: 'own' });
      perps.forEach(p => linear(p.labels, dirVecOf(p.cfg), { from: 'perpendicular', axis: p.key }));
    }
  }
  out.name = {
    location: loc, text: spec.text, lines, align, verticalAlign: vAlign, localRotation: layout.rotation,
    moveDir: spec.moveOverlap ? moveDir : null, box, anchor: [M[4], M[5]], transform: M, localRect, preRect,
    axisAligned, tested, translations, obb,
    finalAnchor: cur.anchor, finalTransform: cur.transform, rect: cur.rect, rotation: -Math.atan2(M[1], M[0]),
  };
  return out;
}

// Grid.ts:864-924 and util/graphic.ts:608-672 (as grid-bounds.js).
const XY = ['x', 'y'];
const WH = ['width', 'height'];
const XY_TO_MARGIN_IDX = [[3, 1], [0, 2]];
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

// The builder's frame and label geometry, as they stand.
function snapAxis(b, where) {
  const model = b._axisModel;
  const axis = model.axis;
  const cfg = b._cfg;
  const rec = b._shared.ensureRecord(model);
  const list = rec.labelInfoList;
  must(Array.isArray(list), where + ': labelInfoList is not an array');
  const layoutList = (b._local && b._local.labelLayoutList) || [];
  const ordinal = axis.scale.type === 'ordinal';
  const labels = list.map((li, k) => {
    const lw = where + ' label ' + k;
    must(li && li.label && li.label.style && typeof li.label.style.text === 'string', lw + ': no label text');
    must(finiteRect(li.rect) && finiteRect(li.localRect), lw + ': no finite rect');
    const info = labelInfoOf(li.label, lw);
    // getTickValueOutermost
    const tick = ordinal ? axis.scale.getRawOrdinalNumber(info.tick.value) : info.tick.value;
    let p = axis.scale.normalize(tick);
    p = axis.dim === 'y' ? 1 - p : p;
    must(typeof p === 'number' && !Number.isNaN(p), lw + ': proportion ' + p);
    const layoutIndex = layoutList.indexOf(li);
    must(layoutIndex >= 0, lw + ': not in the labelLayoutList');
    return {
      text: li.label.style.text, font: String(li.label.style.font), layoutIndex, tick, p,
      rect: plainRect(li.rect), localRect: plainRect(li.localRect),
      transform: li.transform ? Array.from(li.transform) : null,
      axisAligned: !!li.axisAligned, ignore: !!li.label.ignore,
    };
  });
  const G = rec.transGroup.transform;
  return {
    cfg: {
      position: cfg.position.slice(), rotation: cfg.rotation, labelOffset: cfg.labelOffset,
      nameDirection: cfg.nameDirection, extent: axis.getExtent().slice(), inverse: !!axis.inverse,
      shouldNameMoveOverlap: !!cfg.shouldNameMoveOverlap,
    },
    G: G ? Array.from(G) : null,
    dirVec: [rec.dirVec.x, rec.dirVec.y],
    labels,
    stOcc: rec.stOccupiedRect ? plainRect(rec.stOccupiedRect) : null,
  };
}
const sameLabel = (a, b) => a.text === b.text && a.layoutIndex === b.layoutIndex && sameRect(a.rect, b.rect)
  && sameRect(a.localRect, b.localRect) && sameArr(a.transform, b.transform)
  && a.axisAligned === b.axisAligned && a.ignore === b.ignore;
const sameSnap = (a, b) => sameArr(a.cfg.position, b.cfg.position) && Object.is(a.cfg.rotation, b.cfg.rotation)
  && Object.is(a.cfg.labelOffset, b.cfg.labelOffset) && a.cfg.nameDirection === b.cfg.nameDirection
  && sameArr(a.cfg.extent, b.cfg.extent) && a.cfg.inverse === b.cfg.inverse
  && a.cfg.shouldNameMoveOverlap === b.cfg.shouldNameMoveOverlap && sameArr(a.dirVec, b.dirVec)
  && sameRect(a.stOcc, b.stOcc) && a.labels.length === b.labels.length && a.labels.every((l, i) => sameLabel(l, b.labels[i]));

// What is being captured: RUN.byGrid maps a grid (coordinate system) to its
// passes; CAP is the name being built.
let RUN = null;
let CAP = null;

// Which obstacle list a base rect handed to BoundingRect.intersect came from.
function classify(cap, a) {
  const own = cap.rec.labelInfoList || [];
  const k = own.findIndex(li => li.rect === a);
  if (k >= 0) return { from: 'own', label: k, aligned: !!own[k].axisAligned };
  const perp = cap.dim === 'x' ? 'y' : 'x';
  const recs = cap.ctx.recordMap[perp] || [];
  for (let i = 0; i < recs.length; i++) {
    const list = (recs[i] && recs[i].labelInfoList) || [];
    const j = list.findIndex(li => li.rect === a);
    if (j >= 0) return { from: 'perpendicular', axis: perp + i, label: j, aligned: !!list[j].axisAligned };
  }
  return { from: 'occupied', aligned: isAxisAligned(cap.rec.transGroup.transform) };
}

function snapName(b, cap, where) {
  const rec = b._shared.ensureRecord(b._axisModel);
  const nl = rec.nameLayout;
  if (!nl) {
    must(!cap.resolved && !cap.calls.length, where + ': moved a name that is not there');
    return null;
  }
  const el = nl.label;
  const st = el.style;
  const children = el.childrenRef ? el.childrenRef() : [];
  const final = { x: el.x, y: el.y, T: Array.from(nl.transform), rect: plainRect(nl.rect) };
  const pre = cap.pre || final;
  // each test's translation: the state before the next test (or the final
  // state) less the state before this one
  const states = cap.calls.map(c => c.before).concat([final]);
  const translations = [];
  let obb = false;
  cap.calls.forEach((c, i) => {
    const next = states[i + 1];
    const from = { from: c.base.from };
    if (c.base.axis) from.axis = c.base.axis;
    if (c.base.label != null) from.label = c.base.label;
    if (c.overlap && !(c.base.aligned && nl.axisAligned)) {
      obb = true;
      translations.push(Object.assign(from, { obb: true, x: next.x - c.before.x, y: next.y - c.before.y }));
      return;
    }
    if (!c.overlap) {
      must(next.x === c.before.x && next.y === c.before.y, where + ': a test that did not overlap moved the name');
      return;
    }
    const [mx, my] = c.mtv;
    must(Object.is(next.x, c.before.x + mx) && Object.is(next.y, c.before.y + my)
      && Object.is(next.T[4], c.before.T[4] + mx) && Object.is(next.T[5], c.before.T[5] + my)
      && Object.is(next.rect.x, c.before.rect.x + mx) && Object.is(next.rect.y, c.before.rect.y + my),
    where + ': the move applied is not the translation the test returned');
    translations.push(Object.assign(from, { x: mx, y: my }));
  });
  return {
    location: rec.nameLocation, text: String(st.text), lines: children.map(c => c.style && c.style.text),
    childTypes: children.map(c => c.type), align: st.align, verticalAlign: st.verticalAlign,
    font: String(st.font), fill: st.fill, width: st.width, isTruncated: !!el.isTruncated,
    padding: st.padding, lineHeight: st.lineHeight, marginType: st.__marginType,
    localRotation: el.__oracleLocalRotation,
    box: plainRect(el.getBoundingRect()), localRect: plainRect(nl.localRect),
    anchor: [pre.x, pre.y], transform: pre.T, preRect: pre.rect, axisAligned: !!nl.axisAligned,
    moveDir: cap.dir, resolved: cap.resolved, tested: cap.calls.map(c => c.base), translations,
    obb: obb || !!nl.obb,
    finalAnchor: [final.x, final.y], finalTransform: final.T, rect: final.rect, rotation: el.rotation,
    rectObject: nl.rect,
  };
}

const HOOKED = new Map();
function installHooks(lib) {
  if (HOOKED.has(lib)) return HOOKED.get(lib);
  const warm = render(lib, {
    xAxis: { type: 'category', data: ['a'], name: 'n' }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [1] }],
  }, 200, 200);
  const x = warm.getModel().getComponent('grid', 0).coordinateSystem.getAxes()[0];
  const AB = x.axisBuilder.constructor;
  const nl = x.axisBuilder._shared.ensureRecord(x.model).nameLayout;
  const defaults = { font: String(nl.label.style.font), fill: nl.label.style.fill };
  const BR = lib.graphic.BoundingRect;
  must(nl.rect instanceof BR, 'the name rect is not the BoundingRect the library exports');
  warm.dispose();
  must(/(^|\s)12px(\s|$)/.test(defaults.font), 'the default name font ' + defaults.font + ' is not 12px');

  // the text's own rotation, before decomposeTransform folds the group's in
  const proto = lib.graphic.Text.prototype;
  const decompose = proto.decomposeTransform;
  proto.decomposeTransform = function () {
    if (this.anid === 'name') this.__oracleLocalRotation = this.rotation;
    return decompose.apply(this, arguments);
  };

  const intersect = BR.intersect;
  BR.intersect = function (a, b, mtv, opt) {
    const cap = CAP && CAP.inResolve && b === CAP.nl.rect ? CAP : null;
    let before = null;
    let base = null;
    if (cap) {
      before = { x: cap.nl.label.x, y: cap.nl.label.y, T: Array.from(cap.nl.transform), rect: plainRect(b) };
      base = classify(cap, a);
      must(opt && Object.is(opt.direction, Math.atan2(cap.dir[1], cap.dir[0])) && opt.bidirectional === false
        && opt.touchThreshold === 0.05, 'a name test with other options');
    }
    const r = intersect.apply(this, arguments);
    if (cap) cap.calls.push({ before, base, overlap: r, mtv: mtv ? [mtv.x, mtv.y] : null });
    return r;
  };

  const build = AB.prototype.build;
  AB.prototype.build = function (map, extra) {
    if (!RUN || !map) return build.apply(this, arguments);
    const axis = this._axisModel.axis;
    const grid = axis.grid;
    const key = keyOf(axis);
    const where = RUN.name + ' ' + key;
    const sh = this._shared;
    if (!sh.__oracleHooked) {
      sh.__oracleHooked = true;
      const resolve = sh.resolveAxisNameOverlap;
      sh.resolveAxisNameOverlap = function (cfg, ctx, am, nameLayout, dirVec, rec) {
        const cap = CAP;
        if (cap) {
          must(!cap.resolved && am === cap.builder._axisModel, where + ': an unexpected resolve');
          Object.assign(cap, {
            resolved: true, inResolve: true, nl: nameLayout, rec, ctx, dim: am.axis.dim, dir: [dirVec.x, dirVec.y],
            pre: { x: nameLayout.label.x, y: nameLayout.label.y, T: Array.from(nameLayout.transform), rect: plainRect(nameLayout.rect) },
          });
        }
        try {
          return resolve.apply(this, arguments);
        } finally {
          if (cap) cap.inResolve = false;
        }
      };
    }
    let passes = RUN.byGrid.get(grid);
    if (!passes) RUN.byGrid.set(grid, passes = []);
    let cur = passes[passes.length - 1];
    const kind = map.axisTickLabelEstimate ? 'estimate' : map.axisTickLabelDetermine ? 'determine' : null;
    if (kind) {
      const res = build.apply(this, arguments);
      if (!cur || cur.kind !== kind || cur.named || cur.axes.has(key)) {
        passes.push(cur = { kind, rect: plainRect(grid._rect), axes: new Map(), named: false });
      }
      must(sameRect(cur.rect, grid._rect), where + ': the grid rect moved inside a pass');
      cur.axes.set(key, Object.assign(snapAxis(this, where), { builder: this, index: axis.model.componentIndex, dim: axis.dim }));
      return res;
    }
    if (map.axisName) {
      must(cur && cur.axes.has(key) && !cur.axes.get(key).nameBuilt, where + ': a name built outside a pass');
      must(!CAP, where + ': a name built inside another');
      CAP = { builder: this, calls: [], pre: null, resolved: false, dir: null };
      let cap;
      let res;
      try {
        res = build.apply(this, arguments);
      } finally {
        cap = CAP;
        CAP = null;
      }
      cur.named = true;
      const a = cur.axes.get(key);
      a.nameBuilt = true;
      a.level = extra && extra.nameMarginLevel;
      a.name = snapName(this, cap, where);
      // nothing a name build does may touch the frame or any label of the pass
      cur.axes.forEach((v, k) => must(sameSnap(v, snapAxis(v.builder, where)), where + ': ' + k + ' changed under a name build'));
      return res;
    }
    return build.apply(this, arguments);
  };
  HOOKED.set(lib, defaults);
  return defaults;
}

function run(c, lib) {
  const defaults = installHooks(lib);
  const where = c.name;
  const option = clone(c.option);
  option.animation = false;
  RUN = { name: where, byGrid: new Map() };
  let chart;
  try {
    chart = render(lib, option, c.W, c.H);
  } finally {
    const r = RUN;
    RUN = null;
    CAP = null;
    c.runState = r;
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

    // the passes: [estimate, determine] under auto and same, else [determine]
    const passes = c.runState.byGrid.get(cs) || [];
    const shrinks = mode === 'auto' || mode === 'same';
    must(passes.length === (shrinks ? 2 : 1) && passes[passes.length - 1].kind === 'determine'
      && (!shrinks || passes[0].kind === 'estimate'), where + ': passes ' + passes.map(p => p.kind).join(', '));
    const est = shrinks ? passes[0] : null;
    const det = passes[passes.length - 1];
    must(!est || sameRect(est.rect, raw), where + ': the estimate pass is not on the raw rect');
    must(sameRect(det.rect, rect), where + ': the determine pass is not on the final rect');
    must(!est || est.named === (contain === 'all'), where + ': names in the estimate pass under contain ' + contain);

    const gridOpt = (Array.isArray(option.grid) ? option.grid[c.grid] : option.grid) || {};
    const axes = cs.getAxes().map(axis => {
      const key = keyOf(axis);
      const opts = option[axis.dim + 'Axis'];
      const axisOpt = (Array.isArray(opts) ? opts[axis.model.componentIndex] : opts) || {};
      const shown = !!axis.model.getShallow('show');
      const out = { dim: axis.dim, index: axis.model.componentIndex, key, shown, spec: nameSpecOf(axisOpt, gridOpt),
        estimate: null, determine: null };
      [['estimate', est], ['determine', det]].forEach(([k, pass]) => {
        if (!pass) return;
        const a = pass.axes.get(key);
        must(!!a === shown, where + ' ' + key + ': shown ' + shown + ' but ' + (a ? '' : 'not ') + 'built in the ' + k + ' pass');
        if (!a || !pass.named) return;
        must(a.nameBuilt, where + ' ' + key + ': no name build in the ' + k + ' pass');
        out[k] = Object.assign({ rect: pass.rect }, a);
      });
      if (out.determine && out.determine.name) {
        // the drawn name is the one the determine pass left
        const nl = axis.axisBuilder._shared.ensureRecord(axis.model).nameLayout;
        const n = out.determine.name;
        must(nl && nl.rect === n.rectObject && Object.is(nl.label.x, n.finalAnchor[0]) && Object.is(nl.label.y, n.finalAnchor[1])
          && sameRect(plainRect(nl.rect), n.rect), where + ' ' + key + ': the drawn name is not the determine pass\'s');
      }
      return out;
    });
    // for the shrink self-check: the estimate pass's labels, and names under 'all'
    const estimate = est ? axes.filter(a => a.shown).map(a => {
      const e = est.axes.get(a.key);
      const n = est.named && e.name;
      return { dim: a.dim, labels: e.labels.map(l => ({ rect: l.rect, p: l.p })),
        name: n ? { rect: n.rect, p: isCenter(n.location) ? 0.5 : NaN } : null };
    }) : null;
    return { option, mode, contain, outer, clamp, raw, rect, axes, estimate, defaults };
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

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const VALS = [120, 200, 150, 80, 70, 110, 130];
const NEG = [120, -200, 150, 80, -70, 110, 130];
function bar(x, y, extra, data) {
  return Object.assign({
    xAxis: Object.assign({ type: 'category', data: DAYS }, x || {}),
    yAxis: Object.assign({ type: 'value' }, y || {}),
    series: [{ type: 'bar', data: data || VALS }],
  }, extra || {});
}
const DAY = { name: 'Day' };
const VALUE = { name: 'Value' };
const middle = o => Object.assign({ nameLocation: 'middle' }, o);

// where the name goes
add('end names (the default)', bar(DAY, VALUE));
add('start names', bar({ name: 'Day', nameLocation: 'start' }, { name: 'Value', nameLocation: 'start' }));
add('middle names, nameGap 25 on x and 30 on y',
  bar(middle({ name: 'Day', nameGap: 25 }), middle({ name: 'Value', nameGap: 30 })));
add('center names are middle names, default gap',
  bar({ name: 'Day', nameLocation: 'center' }, { name: 'Value', nameLocation: 'center' }));
add('inverse x and y, end names: the x line on zero runs along the top',
  bar({ name: 'Day', inverse: true }, { name: 'Value', inverse: true }));
add('inverse x off zero and inverse y, end names',
  bar({ name: 'Day', inverse: true, axisLine: { onZero: false } }, { name: 'Value', inverse: true }));
add('inverse x and y, start names',
  bar({ name: 'Day', inverse: true, nameLocation: 'start' }, { name: 'Value', inverse: true, nameLocation: 'start' }));
add('inverse x and y, middle names',
  bar(middle({ name: 'Day', inverse: true }), middle({ name: 'Value', inverse: true })));
add('negative data, end names: the x name follows the line on zero', {
  xAxis: { type: 'category', data: DAYS, name: 'Day' }, yAxis: { type: 'value', name: 'Value' },
  series: [{ type: 'line', data: NEG }],
});
add('negative data, middle names: the x name stays with the labels', {
  xAxis: middle({ type: 'category', data: DAYS, name: 'Day' }), yAxis: middle({ type: 'value', name: 'Value' }),
  series: [{ type: 'line', data: NEG }],
});
add('x offset 20 and y offset 30 on zero, end names', bar({ name: 'Day', offset: 20 }, { name: 'Value', offset: 30 }));
add('x offset 20 and y offset 30 on zero, middle names',
  bar(middle({ name: 'Day', offset: 20 }), middle({ name: 'Value', offset: 30 })));
add('x offset 20 off zero and y offset 30, end names',
  bar({ name: 'Day', offset: 20, axisLine: { onZero: false } }, { name: 'Value', offset: 30 }));
add('x offset 30, middle x name: the offset counts once', bar(middle({ name: 'Day', offset: 30 }), { name: 'Value', offset: 20 }));
add('x axis on top, end names', bar({ name: 'Day', position: 'top' }, VALUE));
add('x axis on top, middle x name', bar(middle({ name: 'Day', position: 'top' }), VALUE));
add('y axis on the right, end names', bar(DAY, { name: 'Value', position: 'right' }));
add('y axis on the right, middle y name', bar(DAY, middle({ name: 'Value', position: 'right' })));
add('nameRotate 90 on end names', bar({ name: 'Day', nameRotate: 90 }, { name: 'Value', nameRotate: 90 }));
add('nameRotate 45 on end names: turned rects that meet nothing',
  bar({ name: 'Day', nameRotate: 45 }, { name: 'Value', nameRotate: 45 }));
// margin levels
const SMALL = { grid: { left: '30%', right: '30%', top: '30%', bottom: '30%' } };
add('small grid (30% insets), end names: level 0', bar(DAY, VALUE, SMALL));
add('small grid (30% insets), middle names: level 0', bar(middle(DAY), middle(VALUE), SMALL));
add('level flip: the x level is 1 in the estimate pass, 0 in the determine pass',
  bar(middle(DAY), VALUE, { grid: { left: 60, right: 60, top: 10, bottom: 180 } }));
add('two-line end names', bar({ name: 'Line one\nLine two' }, { name: 'Line one\nLine two' }));
add('two-line middle names', bar(middle({ name: 'Line one\nLine two' }), middle({ name: 'Line one\nLine two' })));
// moves
add('y end name, gap 0: moved up clear of the top label', bar(DAY, { name: 'A long axis name', nameGap: 0 }));
add('y end name, gap 0, nameMoveOverlap false: not moved',
  bar(DAY, { name: 'A long axis name', nameGap: 0, nameMoveOverlap: false }));
add('value x, three-line end name, gap 0: moved right past the last label', {
  xAxis: { type: 'value', name: 'Revenue\nin\nUSD', nameGap: 0 }, yAxis: { type: 'category', data: DAYS },
  series: [{ type: 'bar', data: VALS.map(v => v * 1e4) }],
});
add('middle y name, gap 5: moved left clear of the labels', bar(DAY, middle({ name: 'Value', nameGap: 5 })));
add('labels hidden, middle names: nothing to move from',
  bar(middle({ name: 'Day', axisLabel: { show: false } }), middle({ name: 'Value', axisLabel: { show: false } })));
add('two left y axes, middle names: a parallel axis never moves a name', {
  xAxis: { type: 'category', data: DAYS },
  yAxis: [middle({ type: 'value', name: 'A' }), middle({ type: 'value', position: 'left', offset: 60, name: 'B' })],
  series: [{ type: 'bar', data: VALS }, { type: 'line', yAxisIndex: 1, data: VALS.map(v => v * 1000) }],
});
add('two left y axes, end names: the x name tests both y label lists', {
  xAxis: { type: 'category', data: DAYS, name: 'Day' },
  yAxis: [{ type: 'value', name: 'A' }, { type: 'value', position: 'left', offset: 60, name: 'B' }],
  series: [{ type: 'bar', data: VALS }, { type: 'line', yAxisIndex: 1, data: VALS.map(v => v * 1000) }],
});
add('x labels rotate 45, middle x name clears the turned labels',
  bar(middle({ name: 'Day', data: DAYS.map(d => d + 'nesday'), axisLabel: { rotate: 45, interval: 0 } }), VALUE));
add('value x and value y, middle names: the ticks are shown and never in the way', {
  xAxis: middle({ type: 'value', name: 'X' }), yAxis: middle({ type: 'value', name: 'Y' }),
  series: [{ type: 'scatter', data: [[1, 2], [3, 4]] }],
});
// reading the options
add('nameGap null is 0 (x), nameGap -10 is kept (y)', bar({ name: 'Day', nameGap: null }, { name: 'Value', nameGap: -10 }));
add('nameTextStyle align left (x), align left + verticalAlign top (y)',
  bar({ name: 'Day', nameTextStyle: { align: 'left' } }, { name: 'Value', nameTextStyle: { align: 'left', verticalAlign: 'top' } }));
add('nameTextStyle textMargin [2,4,6,8] (x) and 5 (y) replace the level table',
  bar({ name: 'Day', nameTextStyle: { textMargin: [2, 4, 6, 8] } }, { name: 'Value', nameTextStyle: { textMargin: 5 } }));
add('nameTextStyle minMargin 10 widens the global rect by 5',
  bar({ name: 'Day', nameTextStyle: { minMargin: 10 } }, { name: 'Value', nameTextStyle: { minMargin: 10 } }));
add('nameTextStyle width and overflow are dead for names',
  bar({ name: 'A very long axis name', nameTextStyle: { width: 30, overflow: 'break' } },
    { name: 'Value', nameTextStyle: { width: 20, overflow: 'truncate' } }));
add('containLabel: names drawn, never moved',
  bar(DAY, { name: 'A long axis name', nameGap: 0 }, { grid: { containLabel: true } }));
add('hidden y axis: no y name, the x name meets no y labels', bar(DAY, { name: 'Value', show: false }));
add('name 0 is no name, name 1.5 is "1.5"', bar({ name: 0 }, { name: 1.5 }));
add('name true is "true", name false is no name', bar({ name: true }, { name: false }));
add('name " " is a name', bar({ name: ' ' }, VALUE));
// the grid shrinks by the names
const TIGHT = { left: 40, right: 10, top: 10, bottom: 30 };
add('shrink: end names, contain all', bar(DAY, VALUE, { grid: TIGHT }));
add('shrink: end names, contain axisLabel', bar(DAY, VALUE, { grid: Object.assign({ outerBoundsContain: 'axisLabel' }, TIGHT) }));
add('shrink: middle names gap 30 / 40, contain all',
  bar(middle({ name: 'Day', nameGap: 30 }), middle({ name: 'Value', nameGap: 40 }), { grid: TIGHT }));
add('shrink: 300x300, a middle x name wider than the chart',
  bar(middle({ name: 'An extremely long axis name that is wider than the chart' }), VALUE), { W: 300, H: 300 });
// grid-bounds.js's name cases, options exactly as it writes them
const NAMED_X = { name: 'Day of the week', nameLocation: 'end' };
const NAMED_Y = { name: 'Revenue in dollars (USD)', nameLocation: 'middle', nameGap: 60 };
const BIG9 = VALS.map(v => v * 1e7);
function gb(grid, x, y, data) {
  const o = {};
  if (grid) o.grid = grid;
  o.xAxis = Object.assign({ type: 'category', data: DAYS }, x || {});
  o.yAxis = Object.assign({ type: 'value' }, y || {});
  o.series = [{ type: 'bar', data: data || VALS }];
  return o;
}
add('grid-bounds I: names, outerBoundsContain all', gb({ outerBoundsContain: 'all' }, NAMED_X, NAMED_Y));
add('grid-bounds I2: names, outerBoundsContain axisLabel', gb({ outerBoundsContain: 'axisLabel' }, NAMED_X, NAMED_Y));
add('grid-bounds I3: y name middle, big9', gb(null, null, NAMED_Y, BIG9));
add('grid-bounds Z4: y name at the end overflows the top, grid top 10', gb({ top: 10 }, null, { name: 'Revenue (USD)' }));
add('grid-bounds Z6: outerBoundsMode same + names, the level differs per pass',
  gb({ outerBoundsMode: 'same' }, NAMED_X, NAMED_Y));
add('grid-bounds CL9: containLabel with names',
  gb({ containLabel: true }, { name: 'Day of the week' }, { name: 'Revenue', nameLocation: 'middle', nameGap: 60 }));

// deferred: recorded, not compared
add('nameRotate 30 on a middle x name: an OBB move',
  bar(middle({ name: 'Day', nameRotate: 30 }), middle({ name: 'Value', nameRotate: 0 })),
  deferred('an OBB move (nameRotate 30) is not done'));
add('nameRotate 45 on start names, gap 0: an OBB test',
  bar({ name: 'Day', nameLocation: 'start', nameRotate: 45, nameGap: 0 },
    { name: 'Value', nameLocation: 'start', nameRotate: 45, nameGap: 0 }),
  deferred('an OBB move (nameRotate 45) is not done'));
add('nameTruncate maxWidth 40',
  bar({ name: 'A very long axis name', nameTruncate: { maxWidth: 40 } }, { name: 'A very long axis name', nameTruncate: { maxWidth: 40 } }),
  deferred('nameTruncate is not done'));
add('nameTruncate maxWidth 40, ellipsis "~"',
  bar({ name: 'A very long axis name', nameTruncate: { maxWidth: 40, ellipsis: '~' } }, { name: 'Short', nameTruncate: { maxWidth: 40 } }),
  deferred('nameTruncate is not done'));
add('nameTruncate maxWidth 50, two lines', bar({ name: 'Line number one\nLine two', nameTruncate: { maxWidth: 50 } }, { name: 'V' }),
  deferred('nameTruncate is not done'));
add('nameTextStyle padding',
  bar({ name: 'Day', nameTextStyle: { verticalAlign: 'top', padding: [4, 6, 8, 10] } }, { name: 'Value', nameTextStyle: { padding: [4, 6, 8, 10] } }),
  deferred('nameTextStyle.padding is not done'));
add('nameTextStyle lineHeight 20',
  bar({ name: 'Line one\nLine two', nameTextStyle: { lineHeight: 20 } }, { name: 'Line one\nLine two', nameTextStyle: { lineHeight: 20 } }),
  deferred('nameTextStyle.lineHeight is not done'));
add('nameTextStyle fontSize 16 and colour',
  bar({ name: 'Day', nameTextStyle: { fontSize: 16, color: '#f00' } }, { name: 'Value', nameTextStyle: { fontSize: 16 } }),
  deferred('the name font and colour are the theme\'s'));
add('global textStyle colour and fontSize 14', bar(DAY, VALUE, { textStyle: { color: '#00f', fontSize: 14 } }),
  deferred('the name and label fonts and colours are the theme\'s'));
add('axisLine colour reaches the name', bar({ name: 'Day', axisLine: { lineStyle: { color: '#0a0' } } }, VALUE),
  deferred('the name colour is the theme\'s'));
add('nameLocation "foo": middle anchor, end layout', bar({ name: 'Day', nameLocation: 'foo' }, { name: 'Value', nameLocation: 'foo' }),
  deferred('an unknown nameLocation is read as \'end\' by the port'));

// ---------- run, check and write ----------

{
  const names = new Set();
  for (const c of cases) {
    if (names.has(c.name)) throw new Error('two cases named ' + c.name);
    names.add(c.name);
  }
}

const ulpMax = c => ulp(Math.max(c.W, c.H));
// self-check tally: name -> [ok, all], over the compared cases' passes
const tally = new Map();
const failed = [];
const surprises = [];

// What the port does not do yet, found in a pass's name and labels.
function unsupported(a, pass, defaults) {
  const why = [];
  if (pass.labels.some(l => !/(^|\s)12px(\s|$)/.test(l.font))) why.push('a label font other than 12px');
  const n = pass.name;
  if (!n) return why;
  const at = a.key + ' ' + n.location;
  if (KNOWN_LOCATIONS.indexOf(n.location) < 0) why.push(at + ': an unknown nameLocation');
  if (n.obb) why.push(at + ': an OBB test');
  if (n.width != null || n.isTruncated) why.push(at + ': truncation');
  if (n.padding != null) why.push(at + ': padding');
  if (n.lineHeight != null) why.push(at + ': lineHeight');
  if (n.font !== defaults.font) why.push(at + ': font ' + n.font);
  if (n.fill !== defaults.fill) why.push(at + ': colour ' + n.fill);
  if (n.childTypes.some(t => t !== 'tspan')) why.push(at + ': a box behind the text');
  return why;
}

// The transcription against upstream, one pass of one axis: [check, ok, detail].
function checkPass(c, r, a, k) {
  const pass = a[k];
  const own = Object.assign({ key: a.key }, pass);
  const perps = r.axes.filter(b => b.shown && b.dim !== a.dim && b[k])
    .sort((x, y) => x.index - y.index).map(b => Object.assign({ key: b.key }, b[k]));
  const t = transcribeAxis(a.spec, a.dim, own, perps, c.W, c.H);
  const out = [];
  const chk = (name, ok, detail) => out.push([name, !!ok, ok ? null : detail]);
  chk('level', pass.level === t.level, 'level ' + t.level + ', upstream ' + pass.level);
  chk('dirVec', sameArr(t.dirVec, pass.dirVec), 'dirVec ' + t.dirVec + ', upstream ' + pass.dirVec);
  chk('group transform', sameArr(t.G, pass.G), 'group transform ' + t.G + ', upstream ' + pass.G);
  chk('stOccupiedRect', sameRect(t.stOcc, pass.stOcc), 'stOcc ' + JSON.stringify(t.stOcc) + ', upstream ' + JSON.stringify(pass.stOcc));
  chk('moveOverlap', pass.cfg.shouldNameMoveOverlap === a.spec.moveOverlap, 'moveOverlap ' + a.spec.moveOverlap);
  const u = pass.name;
  chk('has name', !!u === !!t.name, 'name ' + !!t.name + ', upstream ' + !!u);
  if (!u || !t.name) return out;
  const n = t.name;
  chk('location', u.location === n.location, 'location ' + n.location + ', upstream ' + u.location);
  chk('text', u.text === n.text && u.lines.length === n.lines.length && u.lines.every((l, i) => l === n.lines[i]),
    'lines ' + JSON.stringify(n.lines) + ', upstream ' + JSON.stringify(u.lines));
  chk('layout', u.align === n.align && u.verticalAlign === n.verticalAlign && Object.is(u.localRotation, n.localRotation),
    n.align + '/' + n.verticalAlign + ' ' + n.localRotation + ', upstream ' + u.align + '/' + u.verticalAlign + ' ' + u.localRotation);
  chk('box', sameRect(u.box, n.box), 'box ' + JSON.stringify(n.box) + ', upstream ' + JSON.stringify(u.box));
  chk('anchor', sameArr(u.anchor, n.anchor), 'anchor ' + n.anchor + ', upstream ' + u.anchor);
  chk('transform', sameArr(u.transform, n.transform), 'transform ' + n.transform + ', upstream ' + u.transform);
  chk('localRect', sameRect(u.localRect, n.localRect), 'localRect ' + JSON.stringify(n.localRect) + ', upstream ' + JSON.stringify(u.localRect));
  chk('preRect', sameRect(u.preRect, n.preRect), 'preRect ' + JSON.stringify(n.preRect) + ', upstream ' + JSON.stringify(u.preRect));
  chk('axisAligned', u.axisAligned === n.axisAligned, 'axisAligned ' + n.axisAligned);
  chk('rotation', Object.is(u.rotation, n.rotation), 'rotation ' + n.rotation + ', upstream ' + u.rotation);
  if (u.resolved) chk('moveDir', sameArr(u.moveDir, n.moveDir), 'moveDir ' + n.moveDir + ', upstream ' + u.moveDir);
  if (u.obb || n.obb) return out; // the rest needs the OBB the transcription does not have
  const sameFrom = (x, y) => x.from === y.from && x.axis === y.axis && x.label === y.label;
  chk('tests', u.tested.length === n.tested.length && u.tested.every((x, i) => sameFrom(x, n.tested[i])),
    'tested ' + JSON.stringify(n.tested) + ', upstream ' + JSON.stringify(u.tested.map(x => ({ from: x.from, axis: x.axis, label: x.label }))));
  chk('translations', u.translations.length === n.translations.length
    && u.translations.every((x, i) => sameFrom(x, n.translations[i]) && Object.is(x.x, n.translations[i].x) && Object.is(x.y, n.translations[i].y)),
  'translations ' + JSON.stringify(n.translations) + ', upstream ' + JSON.stringify(u.translations));
  chk('final', sameArr(u.finalAnchor, n.finalAnchor) && sameArr(u.finalTransform, n.finalTransform) && sameRect(u.rect, n.rect),
    'final ' + n.finalAnchor + ' ' + JSON.stringify(n.rect) + ', upstream ' + u.finalAnchor + ' ' + JSON.stringify(u.rect));
  return out;
}

function passRecord(pass, W, H) {
  const cfg = pass.cfg;
  const out = {
    rect: hexRect(pass.rect), rectText: textRect(pass.rect), container: { width: W, height: H }, level: pass.level,
    cfg: {
      position: hexArr(cfg.position), positionText: textArr(cfg.position),
      rotation: hex(cfg.rotation), rotationText: text(cfg.rotation),
      labelOffset: hex(cfg.labelOffset), labelOffsetText: text(cfg.labelOffset),
      nameDirection: cfg.nameDirection,
      extent: hexArr(cfg.extent), extentText: textArr(cfg.extent),
      inverse: cfg.inverse, shouldNameMoveOverlap: cfg.shouldNameMoveOverlap,
    },
    dirVec: hexArr(pass.dirVec), dirVecText: textArr(pass.dirVec),
    labels: pass.labels.map(l => ({
      text: l.text, layoutIndex: l.layoutIndex, tick: hex(l.tick), tickText: text(l.tick), p: hex(l.p), pText: text(l.p),
      rect: hexRect(l.rect), rectText: textRect(l.rect), localRect: hexRect(l.localRect), localRectText: textRect(l.localRect),
      transform: hexArr(l.transform), transformText: textArr(l.transform), axisAligned: l.axisAligned, ignore: l.ignore,
    })),
    stOccupiedRect: hexRect(pass.stOcc), stOccupiedRectText: textRect(pass.stOcc),
    name: null,
  };
  const n = pass.name;
  if (n) {
    out.name = {
      location: n.location, text: n.text, lines: n.lines, align: n.align, verticalAlign: n.verticalAlign,
      localRotation: hex(n.localRotation), localRotationText: text(n.localRotation),
      box: hexRect(n.box), boxText: textRect(n.box), localRect: hexRect(n.localRect), localRectText: textRect(n.localRect),
      anchor: hexArr(n.anchor), anchorText: textArr(n.anchor),
      transform: hexArr(n.transform), transformText: textArr(n.transform),
      preRect: hexRect(n.preRect), preRectText: textRect(n.preRect), axisAligned: n.axisAligned,
      moveDir: hexArr(n.moveDir), moveDirText: textArr(n.moveDir),
      translations: n.translations.map(m => Object.assign({ from: m.from }, m.axis ? { axis: m.axis } : {},
        m.label != null ? { label: m.label } : {}, m.obb ? { obb: true } : {},
        { x: hex(m.x), xText: text(m.x), y: hex(m.y), yText: text(m.y) })),
      finalAnchor: hexArr(n.finalAnchor), finalAnchorText: textArr(n.finalAnchor),
      finalTransform: hexArr(n.finalTransform), finalTransformText: textArr(n.finalTransform),
      rect: hexRect(n.rect), rectText: textRect(n.rect),
      rotation: hex(n.rotation), rotationText: text(n.rotation),
    };
  }
  return out;
}

function recordOf(c) {
  const r = runEither(c);
  const why = [];
  // what the port does not do yet
  r.axes.forEach(a => ['estimate', 'determine'].forEach(k => {
    if (a[k]) unsupported(a, a[k], r.defaults).forEach(w => why.indexOf(w) < 0 && why.push(w));
  }));
  const unsupportedFound = why.length > 0;
  // the transcription
  const misses = [];
  const missed = new Set();
  r.axes.forEach(a => ['estimate', 'determine'].forEach(k => {
    if (!a[k]) return;
    checkPass(c, r, a, k).forEach(([name, ok, detail]) => {
      if (!unsupportedFound) {
        const t = tally.get(name) || [0, 0];
        t[1]++;
        if (ok) t[0]++;
        tally.set(name, t);
      }
      if (!ok) {
        misses.push(k + ' ' + a.key + ': ' + detail);
        missed.add(name);
      }
    });
  }));
  // the shrink
  let minP = 1;
  if (r.estimate) {
    const s = solveOuterBounds(r.raw, r.outer, r.contain, r.clamp, r.estimate);
    minP = s.minP;
    const ok = sameRect(s.rect, r.rect);
    if (!unsupportedFound) {
      const t = tally.get('shrink') || [0, 0];
      t[1]++;
      if (ok) t[0]++;
      tally.set('shrink', t);
    }
    if (!ok) {
      misses.push('the shrink transcription gives ' + JSON.stringify(textRect(s.rect)) + ', upstream ' + JSON.stringify(textRect(r.rect)));
      missed.add('shrink');
    }
  }
  if (misses.length) {
    if (unsupportedFound) console.log(c.name + ' (deferred anyway): the transcription misses ' + Array.from(missed).join(', '));
    else failed.push(c.name + ': ' + misses.join('; '));
  }
  if (!!c.deferred !== unsupportedFound) {
    surprises.push(c.name + ': ' + (c.deferred ? 'expected deferred (' + c.deferred + '), found nothing unsupported'
      : 'expected compared, found ' + why.join('; ')));
  }

  // measure every name string and every line of one at its font's size
  r.axes.forEach(a => ['estimate', 'determine'].forEach(k => {
    const n = a[k] && a[k].name;
    if (!n) return;
    const m = /(\d+(?:\.\d+)?)px/.exec(n.font);
    const px = m ? +m[1] : DEFAULT_FONT_SIZE;
    [n.text].concat(n.lines).forEach(t => typeof t === 'string' && addMeasured(t, px));
  }));

  const rec = { name: c.name, W: c.W, H: c.H, grid: c.grid, option: r.option, mode: r.mode, contain: r.contain };
  rec.rect = hexRect(r.rect);
  rec.rectText = textRect(r.rect);
  const tol = 4 * ulpMax(c) / minP;
  rec.tol = hex(tol);
  rec.tolText = text(tol);
  rec.axes = r.axes.map(a => {
    const s = a.spec;
    return {
      dim: a.dim, index: a.index, shown: a.shown,
      spec: {
        text: s.text, location: s.location, gap: hex(s.gap), gapText: text(s.gap),
        rotate: s.rotate == null ? null : hex(s.rotate), rotateText: s.rotate == null ? null : text(s.rotate),
        align: s.align, verticalAlign: s.verticalAlign,
        margin: { kind: s.margin.kind, value: hexArr(s.margin.value), valueText: textArr(s.margin.value) },
        moveOverlap: s.moveOverlap,
      },
      estimate: a.estimate ? passRecord(a.estimate, c.W, c.H) : null,
      determine: a.determine ? passRecord(a.determine, c.W, c.H) : null,
    };
  });
  const reasons = [];
  if (c.deferred) reasons.push(c.deferred);
  if (unsupportedFound) reasons.push(why.join('; '));
  if (misses.length && !unsupportedFound) reasons.push('self-check: ' + misses.join('; '));
  if (reasons.length) {
    rec.deferred = true;
    rec.why = reasons.join('; and ');
  }
  if (r.productionBuild) rec.productionBuild = true;
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
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
surprises.forEach(s => console.log('deferral not as declared: ' + s));
failed.forEach(f => console.log('self-check failed: ' + f));
console.log('self-checks (compared cases): ' + Array.from(tally, ([k, [ok, all]]) => k + ' ' + ok + '/' + all).join(', '));
fs.writeFileSync(OUT, json + '\n');
const d = out.cases.filter(c => c.deferred).length;
console.log('wrote', OUT, (out.cases.length - d) + ' cases + ' + d + ' deferred, ' + measure.length + ' measured strings');
process.exit(0);
