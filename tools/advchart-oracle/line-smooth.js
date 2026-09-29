// Upstream's own answers for the LINE SERIES' `smooth` / `smoothMonotone`: the
// smoothed polyline (ECPolyline) and the smoothed area polygon (ECPolygon) as
// chart/line/poly.ts builds them (wf63/upstream-smooth.md is the prose).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 800 x 600 for every
// chart case, with Math.random replaced by the port's xorshift32 (seed
// 2463534242, reset before each chart), and reads the view directly:
// chart.getViewOfSeriesModel(lineSeries)._polyline / ._polygon, their `shape`
// (points, stackedOnPoints, smooth, stackedOnSmooth, smoothMonotone,
// connectNulls) and their PathProxy data. Nothing is painted in SSR setOption, so
// the path is built by el.getBoundingRect() (Path.getBoundingRect: createPathProxy,
// beginPath, buildPath into the element's own proxy -- a plain number[] of
// doubles, never toStatic'ed; the canvas painter WOULD toStatic it into a
// Float32Array, see notes) and read as el.path.data up to el.path.len(). Every
// chart is disposed in a finally.
//
//   node tools/advchart-oracle/line-smooth.js
//
// writes tests/fixtures/advchart-line-smooth.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions (as visualmap-view.js / datazoom-slider.js)
//   hex      a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//            lowercase (NaN 7ff8000000000000, +Infinity 7ff0000000000000).
//            Every hex field has a readable twin (xText beside x; String(v),
//            '-0' for negative zero).
//   points   [[x, y], ...] hex pairs + pointsText. A point is ILLEGAL when
//            either coordinate is not finite (helper.isPointIllegal); an index
//            past the array end reads `undefined`, which is illegal too.
//   path     [{cmd, args [hex], argsText}] -- the PathProxy data up to len():
//            cmd 'M' (x, y), 'L' (x, y), 'C' (cp1x, cp1y, cp2x, cp2y, x, y),
//            'Z' (no args). ECPolyline / ECPolygon emit nothing else.
//   digest   sha1 (lowercase hex) of an ASCII string:
//              pointsDigest  every value of the flat points array (x0 y0 x1 y1
//                            ...) as its 16 hex digits, concatenated, no
//                            separators
//              pathDigest    per command its letter then its args' 16 hex
//                            digits, concatenated ('M4069...C...Z')
//   rect     {x, y, width, height} hex + rectText: el.path.getBoundingRect()
//            (the path alone, no stroke): PathProxy.getBoundingRect with
//            bbox.fromLine / fromCubic (curve extrema, curve.cubicExtrema)
//
// Top level
//   source, W, H, seed, head (the truncation size: 200), api, notes[]
//   cases[]  one per chart:
//     id, note, width, height, gallery (file name or null), option (as fed;
//     null for a gallery case: load examples/advchart/gallery/<gallery>.json
//     and feed it verbatim)
//     series[]  every LINE series in series order (other types are skipped):
//       seriesIndex, name (option.name; null when unset: upstream's generated
//       default 'series\0<i>' holds a NUL), coordSys ('cartesian2d' | 'polar'),
//       baseAxisDim ('x' | 'y' | 'angle' | 'radius'), dataCount (data.count()
//       after dataZoom filtering and sampling), rawCount (getRawData().count())
//       resolved
//         smoothOption   seriesModel.get('smooth') as JSON (true / false /
//                        number / string / null)
//         smooth         hex + Text: the polyline shape's smooth =
//                        getSmooth(smoothOption) (LineView.ts:118-120)
//         smoothMonotone the shape's (seriesModel.get('smoothMonotone')), JSON:
//                        null | 'x' | 'y' | 'none'
//         connectNulls   bool (the shape's)
//         stepOption     seriesModel.get('step') as JSON
//         step           view._step: the step actually applied (false on polar)
//         area           bool: !areaStyleModel.isEmpty() (a polygon exists)
//         stack          seriesModel.get('stack') | null
//         stackedOn      null, or {seriesIndex, smoothOption, smoothMonotone}
//                        of data.getCalculationInfo('stackedOnSeries')
//         stackedOnSmooth  hex + Text (area only): the polygon shape's
//                        stackedOnSmooth = getSmooth(stackedOn.smoothOption),
//                        0 when not stacked
//       line   the ECPolyline:
//         pointsKind     'float32' (the layout's Float32Array: every value is a
//                        float32) | 'array' (step: turnPointsIntoStep's number[])
//         count          points.length / 2
//         truncated      count > head: points and path below hold only the head
//         points (+Text) all points, or the first `head` when truncated
//         pointsDigest   over ALL points
//         layoutPoints (+Text)  step only: data.getLayout('points') -- the
//                        float32 input turnPointsIntoStep got (never truncated
//                        in these cases)
//         path           all commands, or the first `head` when truncated
//         pathCount      the number of commands, pathLen (path.len(): numbers
//                        incl. the command codes), pathDigest (ALL commands)
//         rect (+Text)   the path's bounding rect
//       area   null, or the ECPolygon:
//         pointsSameAsLine  true: the polygon's points IS the polyline's array
//         stackedOnPoints (+Text, head-truncated like points), stackedOnKind,
//         stackedOnDigest, path, pathCount, pathLen, pathDigest, rect
//       symbols  null (no symbols, or count > head), or [[dataIndex, x, y]]
//                (hex) for every item with a graphic element: the symbol's
//                position (the layout point, before any step)
//
// guards[]  one per mutation of the transcription: id, mutation, named (the
//           cases that must turn red), changed (the cases whose recorded
//           values the mutated transcription does not reproduce), ok = named
//           is a subset of changed, differs (the first differing fields of
//           each named case)
//
// ---------------------------------------------------------------------------
// The transcription (checked against every recorded series, bit for bit) is
// LineView.ts getSmooth + turnPointsIntoStep, poly.ts drawSegment /
// ECPolyline.buildPath / ECPolygon.buildPath over a PathProxy-like recorder, and
// PathProxy.getBoundingRect with bbox.fromLine / fromCubic and
// curve.cubicExtrema / cubicAt. Its inputs are `resolved` and the recorded points
// (layoutPoints for step). For the f64 guard it also needs the points BEFORE the
// Float32Array store: they are recomputed while each chart is alive
// (coordSys.dataToPoint of the store values, as layout/points.ts and
// helper.getStackedOnPoint do), checked to round (Math.fround) to the recorded
// points, and kept outside the fixture.
//
// Self-checks (any failure: nothing is written, exit 1): the transcription
// reproduces every series (points digest, path, rect, smooth); the recomputed
// doubles round to the recorded float32 points; step points follow from
// layoutPoints; symbols sit on the layout points; no path argument and no rect
// value is NaN or infinite; anchors; every guard is ok; two generations in the
// process give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-line-smooth.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

const W = 800;
const H = 600;
const HEAD = 200;

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
const RK = ['x', 'y', 'width', 'height'];
const rectRec = r => ({
  rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
  rectText: { x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) },
});
const numRec = (name, v) => ({ [name]: hex(v), [name + 'Text']: text(v) });
const sha1 = s => crypto.createHash('sha1').update(s, 'ascii').digest('hex');
const clone = v => (v === undefined ? null : JSON.parse(JSON.stringify(v)));

const CMD = { M: 1, L: 2, C: 3, Q: 4, A: 5, Z: 6, R: 7 };
const CMD_NAME = { 1: 'M', 2: 'L', 3: 'C', 4: 'Q', 5: 'A', 6: 'Z', 7: 'R' };
const CMD_ARGS = { 1: 2, 2: 2, 3: 6, 4: 4, 5: 8, 6: 0, 7: 4 };

// a flat PathProxy data array -> [{cmd, args (numbers)}]
function commands(data, len) {
  const out = [];
  for (let i = 0; i < len;) {
    const c = data[i++];
    must(CMD_NAME[c], 'an unknown path command ' + c);
    const n = CMD_ARGS[c];
    const args = [];
    for (let k = 0; k < n; k++) args.push(data[i++]);
    out.push({ cmd: CMD_NAME[c], args });
  }
  return out;
}
const pathRec = cmds => cmds.map(c => ({ cmd: c.cmd, args: c.args.map(hex), argsText: c.args.map(text) }));
const pathDigest = cmds => sha1(cmds.map(c => c.cmd + c.args.map(hex).join('')).join(''));
const pointsDigest = flat => sha1(Array.from(flat, hex).join(''));
const pairs = flat => {
  const o = [];
  for (let i = 0; i + 1 < flat.length; i += 2) o.push([flat[i], flat[i + 1]]);
  return o;
};
const pointsRec = (name, flat, limit) => {
  const p = pairs(flat).slice(0, limit == null ? undefined : limit);
  return { [name]: p.map(q => q.map(hex)), [name + 'Text']: p.map(q => q.map(text)) };
};
const flatOf = rows => {
  const o = [];
  for (const r of rows) o.push(num(r[0]), num(r[1]));
  return o;
};

// ---------- the transcription (with the mutations as switches) ----------

// LineView.ts:118-120
function getSmooth(smooth, mut) {
  if (mut.smoothParse && typeof smooth === 'string') return parseFloat(smooth) || 0;
  let s = typeof smooth === 'number' ? smooth : (smooth ? 0.5 : 0);
  if (mut.smoothClamp) s = Math.min(Math.max(s, 0), 1);
  return s;
}

// helper.ts:136-144; `undefined` (a read past the end) is illegal
const isPointIllegal = (a, b) => !isFinite(a) || !isFinite(b);

// LineView.ts:152-214 (baseIndex: 0 when the base axis is x / radius)
function turnPointsIntoStep(points, basePoints, baseIndex, stepTurnAt, connectNulls) {
  const stepPoints = [];
  let i = 0;
  const stepPt = [];
  const pt = [];
  const nextPt = [];
  const filteredPoints = [];
  if (connectNulls) {
    for (i = 0; i < points.length; i += 2) {
      const reference = basePoints || points;
      if (!isPointIllegal(reference[i], reference[i + 1])) filteredPoints.push(points[i], points[i + 1]);
    }
    points = filteredPoints;
  }
  for (i = 0; i < points.length - 2; i += 2) {
    nextPt[0] = points[i + 2];
    nextPt[1] = points[i + 3];
    pt[0] = points[i];
    pt[1] = points[i + 1];
    stepPoints.push(pt[0], pt[1]);
    switch (stepTurnAt) {
      case 'end':
        stepPt[baseIndex] = nextPt[baseIndex];
        stepPt[1 - baseIndex] = pt[1 - baseIndex];
        stepPoints.push(stepPt[0], stepPt[1]);
        break;
      case 'middle': {
        const middle = (pt[baseIndex] + nextPt[baseIndex]) / 2;
        const stepPt2 = [];
        stepPt[baseIndex] = stepPt2[baseIndex] = middle;
        stepPt[1 - baseIndex] = pt[1 - baseIndex];
        stepPt2[1 - baseIndex] = nextPt[1 - baseIndex];
        stepPoints.push(stepPt[0], stepPt[1]);
        stepPoints.push(stepPt2[0], stepPt2[1]);
        break;
      }
      default:
        stepPt[baseIndex] = pt[baseIndex];
        stepPt[1 - baseIndex] = nextPt[1 - baseIndex];
        stepPoints.push(stepPt[0], stepPt[1]);
    }
  }
  stepPoints.push(points[i++], points[i++]);
  return stepPoints;
}

// a PathProxy that only records (addData appends the arguments unchanged)
class Recorder {
  constructor() { this.data = []; }
  moveTo(x, y) { this.data.push(CMD.M, x, y); }
  lineTo(x, y) { this.data.push(CMD.L, x, y); }
  bezierCurveTo(a, b, c, d, e, f) { this.data.push(CMD.C, a, b, c, d, e, f); }
  closePath() { this.data.push(CMD.Z); }
}

const mathMin = Math.min;
const mathMax = Math.max;
// poly.ts:36-210, verbatim but for the mutation switches
function drawSegment(ctx, points, start, segLen, allLen, dir, smooth, smoothMonotone, connectNulls, mut) {
  let prevX;
  let prevY;
  let cpx0;
  let cpy0;
  let cpx1;
  let cpy1;
  let idx = start;
  let k = 0;
  if (mut.monotoneIgnored) smoothMonotone = null;
  for (; k < segLen; k++) {
    let x = points[idx * 2];
    let y = points[idx * 2 + 1];
    if (idx >= allLen || idx < 0) break;
    if (isPointIllegal(x, y)) {
      if (connectNulls) {
        idx += dir;
        continue;
      }
      break;
    }
    if (idx === start) {
      ctx[dir > 0 ? 'moveTo' : 'lineTo'](x, y);
      cpx0 = x;
      cpy0 = y;
    } else {
      let dx = x - prevX;
      let dy = y - prevY;
      // Ignore tiny segment.
      if (!mut.noTiny && (dx * dx + dy * dy) < 0.5) {
        if (mut.tinyPrev) {
          prevX = x;
          prevY = y;
        }
        idx += dir;
        continue;
      }
      if (smooth > 0) {
        let nextIdx = idx + dir;
        let nextX = points[nextIdx * 2];
        let nextY = points[nextIdx * 2 + 1];
        // Ignore duplicate point
        while (!mut.noDup && nextX === x && nextY === y && k < segLen) {
          k++;
          nextIdx += dir;
          idx += dir;
          nextX = points[nextIdx * 2];
          nextY = points[nextIdx * 2 + 1];
          x = points[idx * 2];
          y = points[idx * 2 + 1];
          dx = x - prevX;
          dy = y - prevY;
        }
        let tmpK = k + 1;
        if (connectNulls && !mut.noNextSearch) {
          while (isPointIllegal(nextX, nextY) && tmpK < segLen) {
            tmpK++;
            nextIdx += dir;
            nextX = points[nextIdx * 2];
            nextY = points[nextIdx * 2 + 1];
          }
        }
        let ratioNextSeg = 0.5;
        let vx = 0;
        let vy = 0;
        let nextCpx0;
        let nextCpy0;
        if (tmpK >= segLen || isPointIllegal(nextX, nextY)) {
          // Is last point
          if (mut.endMirror) {
            cpx1 = x - (x - prevX) * smooth * 0.5;
            cpy1 = y - (y - prevY) * smooth * 0.5;
          } else {
            cpx1 = x;
            cpy1 = y;
          }
        } else {
          vx = nextX - prevX;
          vy = nextY - prevY;
          const dx0 = x - prevX;
          const dx1 = nextX - x;
          const dy0 = y - prevY;
          const dy1 = nextY - y;
          let lenPrevSeg;
          let lenNextSeg;
          if (smoothMonotone === 'x') {
            lenPrevSeg = Math.abs(dx0);
            lenNextSeg = Math.abs(dx1);
            const d = vx > 0 ? 1 : -1;
            cpx1 = x - d * lenPrevSeg * smooth;
            cpy1 = y;
            nextCpx0 = x + d * lenNextSeg * smooth;
            nextCpy0 = y;
          } else if (smoothMonotone === 'y') {
            lenPrevSeg = Math.abs(dy0);
            lenNextSeg = Math.abs(dy1);
            const d = vy > 0 ? 1 : -1;
            cpx1 = x;
            cpy1 = y - d * lenPrevSeg * smooth;
            nextCpx0 = x;
            nextCpy0 = y + d * lenNextSeg * smooth;
          } else {
            lenPrevSeg = Math.sqrt(dx0 * dx0 + dy0 * dy0);
            lenNextSeg = Math.sqrt(dx1 * dx1 + dy1 * dy1);
            ratioNextSeg = mut.ratioHalf ? 0.5 : lenNextSeg / (lenNextSeg + lenPrevSeg);
            cpx1 = x - vx * smooth * (1 - ratioNextSeg);
            cpy1 = y - vy * smooth * (1 - ratioNextSeg);
            nextCpx0 = x + vx * smooth * ratioNextSeg;
            nextCpy0 = y + vy * smooth * ratioNextSeg;
            if (!mut.noClamp) {
              nextCpx0 = mathMin(nextCpx0, mathMax(nextX, x));
              nextCpy0 = mathMin(nextCpy0, mathMax(nextY, y));
              nextCpx0 = mathMax(nextCpx0, mathMin(nextX, x));
              nextCpy0 = mathMax(nextCpy0, mathMin(nextY, y));
            }
            vx = nextCpx0 - x;
            vy = nextCpy0 - y;
            cpx1 = x - vx * lenPrevSeg / lenNextSeg;
            cpy1 = y - vy * lenPrevSeg / lenNextSeg;
            if (!mut.noClamp) {
              cpx1 = mathMin(cpx1, mathMax(prevX, x));
              cpy1 = mathMin(cpy1, mathMax(prevY, y));
              cpx1 = mathMax(cpx1, mathMin(prevX, x));
              cpy1 = mathMax(cpy1, mathMin(prevY, y));
            }
            vx = x - cpx1;
            vy = y - cpy1;
            nextCpx0 = x + vx * lenNextSeg / lenPrevSeg;
            nextCpy0 = y + vy * lenNextSeg / lenPrevSeg;
          }
        }
        ctx.bezierCurveTo(cpx0, cpy0, cpx1, cpy1, x, y);
        cpx0 = nextCpx0;
        cpy0 = nextCpy0;
      } else {
        ctx.lineTo(x, y);
      }
    }
    prevX = x;
    prevY = y;
    idx += dir;
  }
  return k;
}

// the connectNulls trim of both buildPaths (poly.ts:253-265 / 377-389)
function trim(points, connectNulls, mut) {
  let i = 0;
  let len = points.length / 2;
  if (connectNulls && !mut.noTrim) {
    for (; len > 0; len--) if (!isPointIllegal(points[len * 2 - 2], points[len * 2 - 1])) break;
    for (; i < len; i++) if (!isPointIllegal(points[i * 2], points[i * 2 + 1])) break;
  }
  return { i, len };
}
// ECPolyline.buildPath, poly.ts:245-274
function buildPolyline(points, s, mut) {
  const ctx = new Recorder();
  let { i, len } = trim(points, s.connectNulls, mut);
  while (i < len) {
    i += drawSegment(ctx, points, i, len, len, 1, s.smooth, s.smoothMonotone, s.connectNulls, mut) + 1;
  }
  return ctx.data;
}
// reverse a recorded forward run [M p0 (C|L ...)*] into a backward one starting with lineTo
function reversedRun(data) {
  const cmds = commands(data, data.length);
  const out = new Recorder();
  const pts = [];
  for (const c of cmds) pts.push(c.args.slice(c.args.length - 2));
  out.lineTo(pts[pts.length - 1][0], pts[pts.length - 1][1]);
  for (let j = cmds.length - 1; j >= 1; j--) {
    const c = cmds[j];
    const p = pts[j - 1];
    if (c.cmd === 'C') out.bezierCurveTo(c.args[2], c.args[3], c.args[0], c.args[1], p[0], p[1]);
    else out.lineTo(p[0], p[1]);
  }
  return out.data;
}
// ECPolygon.buildPath, poly.ts:369-407
function buildPolygon(points, stackedOnPoints, s, mut) {
  const ctx = new Recorder();
  let { i, len } = trim(points, s.connectNulls, mut);
  const baseSmooth = mut.baseStraight ? 0 : (mut.baseOwnSmooth ? s.smooth : s.stackedOnSmooth);
  const baseMono = mut.baseMonoFromStackedOn ? s.stackedOnMonotone : s.smoothMonotone;
  while (i < len) {
    const k = drawSegment(ctx, points, i, len, len, 1, s.smooth, s.smoothMonotone, s.connectNulls, mut);
    if (mut.baseForward) {
      // the base smoothed left to right over the same k points, then walked backwards
      const fwd = new Recorder();
      const sub = Array.prototype.slice.call(stackedOnPoints, i * 2, (i + k) * 2);
      drawSegment(fwd, sub, 0, k, k, 1, baseSmooth, baseMono, s.connectNulls, mut);
      if (fwd.data.length) ctx.data.push(...reversedRun(fwd.data));
    } else {
      drawSegment(ctx, stackedOnPoints, i + k - 1, k, len, -1, baseSmooth, baseMono, s.connectNulls, mut);
    }
    i += k + 1;
    ctx.closePath();
  }
  return ctx.data;
}

// zrender curve.ts:14-38, 140-172 (the isAroundZero(disc) branch sets
// extrema[0] but leaves n at 0: verbatim)
const EPSILON = 1e-8;
const isAroundZero = v => v > -EPSILON && v < EPSILON;
const isNotAroundZero = v => v > EPSILON || v < -EPSILON;
function cubicAt(p0, p1, p2, p3, t) {
  const onet = 1 - t;
  return onet * onet * (onet * p0 + 3 * t * p1) + t * t * (t * p3 + 3 * onet * p2);
}
function cubicExtrema(p0, p1, p2, p3, extrema) {
  const b = 6 * p2 - 12 * p1 + 6 * p0;
  const a = 9 * p1 + 3 * p3 - 3 * p0 - 9 * p2;
  const c = 3 * p1 - 3 * p0;
  let n = 0;
  if (isAroundZero(a)) {
    if (isNotAroundZero(b)) {
      const t1 = -c / b;
      if (t1 >= 0 && t1 <= 1) extrema[n++] = t1;
    }
  } else {
    const disc = b * b - 4 * a * c;
    if (isAroundZero(disc)) {
      extrema[0] = -b / (2 * a);
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
// PathProxy.getBoundingRect for M / L / C / Z, bbox.fromLine / fromCubic
function pathRect(data, mut) {
  const min = [Number.MAX_VALUE, Number.MAX_VALUE];
  const max = [-Number.MAX_VALUE, -Number.MAX_VALUE];
  const min2 = [Number.MAX_VALUE, Number.MAX_VALUE];
  const max2 = [-Number.MAX_VALUE, -Number.MAX_VALUE];
  let xi = 0;
  let yi = 0;
  let x0 = 0;
  let y0 = 0;
  let i;
  const ext = [];
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
      case CMD.L: {
        const x1 = data[i];
        const y1 = data[i + 1];
        min2[0] = mathMin(xi, x1); min2[1] = mathMin(yi, y1);
        max2[0] = mathMax(xi, x1); max2[1] = mathMax(yi, y1);
        xi = data[i++];
        yi = data[i++];
        break;
      }
      case CMD.C: {
        const [c1x, c1y, c2x, c2y, x3, y3] = [data[i++], data[i++], data[i++], data[i++], data[i], data[i + 1]];
        min2[0] = Infinity; min2[1] = Infinity; max2[0] = -Infinity; max2[1] = -Infinity;
        if (!mut.bboxEnds) {
          let n = cubicExtrema(xi, c1x, c2x, x3, ext);
          for (let j = 0; j < n; j++) {
            const x = cubicAt(xi, c1x, c2x, x3, ext[j]);
            min2[0] = mathMin(x, min2[0]);
            max2[0] = mathMax(x, max2[0]);
          }
          n = cubicExtrema(yi, c1y, c2y, y3, ext);
          for (let j = 0; j < n; j++) {
            const y = cubicAt(yi, c1y, c2y, y3, ext[j]);
            min2[1] = mathMin(y, min2[1]);
            max2[1] = mathMax(y, max2[1]);
          }
        }
        min2[0] = mathMin(xi, min2[0]); max2[0] = mathMax(xi, max2[0]);
        min2[0] = mathMin(x3, min2[0]); max2[0] = mathMax(x3, max2[0]);
        min2[1] = mathMin(yi, min2[1]); max2[1] = mathMax(yi, max2[1]);
        min2[1] = mathMin(y3, min2[1]); max2[1] = mathMax(y3, max2[1]);
        xi = data[i++];
        yi = data[i++];
        break;
      }
      case CMD.Z:
        xi = x0;
        yi = y0;
        break;
      default:
        throw new OracleError('pathRect: command ' + cmd);
    }
    min[0] = mathMin(min[0], min2[0]); min[1] = mathMin(min[1], min2[1]);
    max[0] = mathMax(max[0], max2[0]); max[1] = mathMax(max[1], max2[1]);
  }
  if (i === 0) min[0] = min[1] = max[0] = max[1] = 0;
  return { x: min[0], y: min[1], width: max[0] - min[0], height: max[1] - min[1] };
}

// decode a series record (and, for truncated / f64 runs, the side data)
function inputs(sr, sd, mut) {
  const r = sr.resolved;
  const f64 = mut.f64 && sd;
  let points;
  let stacked = null;
  const baseIndex = sr.baseAxisDim === 'x' || sr.baseAxisDim === 'radius' ? 0 : 1;
  if (f64) {
    points = sd.doubles.slice();
    stacked = sd.stackedDoubles ? sd.stackedDoubles.slice() : null;
    if (r.step) {
      if (stacked) stacked = turnPointsIntoStep(stacked, points, baseIndex, r.step, r.connectNulls);
      points = turnPointsIntoStep(points, null, baseIndex, r.step, r.connectNulls);
    }
  } else {
    points = sr.line.truncated ? sd.points : flatOf(sr.line.points);
    if (sr.area) stacked = sr.area.truncated ? sd.stackedOnPoints : flatOf(sr.area.stackedOnPoints);
  }
  let smooth = getSmooth(r.smoothOption, mut);
  if (mut.stepKillsSmooth && r.step) smooth = 0;
  const s = {
    smooth, smoothMonotone: r.smoothMonotone, connectNulls: r.connectNulls,
    stackedOnSmooth: r.stackedOn ? getSmooth(r.stackedOn.smoothOption, mut) : 0,
    stackedOnMonotone: r.stackedOn ? r.stackedOn.smoothMonotone : null,
  };
  return { points, stacked, s, baseIndex };
}

// the flat field map a series' transcription gives
function model(sr, sd, mut) {
  const o = {};
  const { points, stacked, s, baseIndex } = inputs(sr, sd, mut);
  o.smooth = hex(s.smooth);
  if (sr.line.layoutPoints) {
    const step = turnPointsIntoStep(flatOf(sr.line.layoutPoints), null, baseIndex, sr.resolved.step, s.connectNulls);
    o['line.stepPoints'] = pointsDigest(step);
  }
  o['line.pointsDigest'] = pointsDigest(points);
  const lineData = buildPolyline(points, s, mut);
  const lc = commands(lineData, lineData.length);
  o['line.path'] = JSON.stringify(pathRec(lc.slice(0, HEAD)).map(c => [c.cmd].concat(c.args)));
  o['line.pathCount'] = String(lc.length);
  o['line.pathLen'] = String(lineData.length);
  o['line.pathDigest'] = pathDigest(lc);
  const lr = pathRect(lineData, mut);
  RK.forEach(k => { o['line.rect.' + k] = hex(lr[k]); });
  if (sr.area) {
    o.stackedOnSmooth = hex(s.stackedOnSmooth);
    o['area.stackedOnDigest'] = pointsDigest(stacked);
    const areaData = buildPolygon(points, stacked, s, mut);
    const ac = commands(areaData, areaData.length);
    o['area.path'] = JSON.stringify(pathRec(ac.slice(0, HEAD)).map(c => [c.cmd].concat(c.args)));
    o['area.pathCount'] = String(ac.length);
    o['area.pathLen'] = String(areaData.length);
    o['area.pathDigest'] = pathDigest(ac);
    const ar = pathRect(areaData, mut);
    RK.forEach(k => { o['area.rect.' + k] = hex(ar[k]); });
  }
  return o;
}
// the same fields read from a record
function flatRecord(sr) {
  const o = {};
  o.smooth = sr.resolved.smooth;
  if (sr.line.layoutPoints) o['line.stepPoints'] = sr.line.pointsDigest;
  o['line.pointsDigest'] = sr.line.pointsDigest;
  o['line.path'] = JSON.stringify(sr.line.path.map(c => [c.cmd].concat(c.args)));
  o['line.pathCount'] = String(sr.line.pathCount);
  o['line.pathLen'] = String(sr.line.pathLen);
  o['line.pathDigest'] = sr.line.pathDigest;
  RK.forEach(k => { o['line.rect.' + k] = sr.line.rect[k]; });
  if (sr.area) {
    o.stackedOnSmooth = sr.resolved.stackedOnSmooth;
    o['area.stackedOnDigest'] = sr.area.stackedOnDigest;
    o['area.path'] = JSON.stringify(sr.area.path.map(c => [c.cmd].concat(c.args)));
    o['area.pathCount'] = String(sr.area.pathCount);
    o['area.pathLen'] = String(sr.area.pathLen);
    o['area.pathDigest'] = sr.area.pathDigest;
    RK.forEach(k => { o['area.rect.' + k] = sr.area.rect[k]; });
  }
  return o;
}
function diffFlat(a, b) {
  const keys = Array.from(new Set(Object.keys(a).concat(Object.keys(b))));
  return keys.filter(k => a[k] !== b[k]).map(k => ({ field: k, upstream: a[k] === undefined ? null : a[k], mutated: b[k] === undefined ? null : b[k] }));
}
// a long path field as its first differing command
function compactDiff(f) {
  if (!/\.path$/.test(f.field) || f.upstream == null || f.mutated == null) return f;
  const u = JSON.parse(f.upstream);
  const m = JSON.parse(f.mutated);
  let i = 0;
  while (i < u.length && i < m.length && JSON.stringify(u[i]) === JSON.stringify(m[i])) i++;
  const t = c => (c ? c[0] + ' ' + c.slice(1).map(h => text(num(h))).join(' ') : null);
  return { field: f.field, command: i, upstream: t(u[i]), mutated: t(m[i]), upstreamCount: u.length, mutatedCount: m.length };
}

// ---------- reading upstream ----------
function doublesOf(chart, seriesModel, dataCoordInfo) {
  // layout/points.ts:45-92 without the Float32Array store; helper.ts:114-134
  const data = seriesModel.getData();
  const coordSys = seriesModel.coordinateSystem;
  const dims = coordSys.dimensions.map(d => data.mapDimension(d)).slice(0, 2);
  const stackResultDim = data.getCalculationInfo('stackResultDimension');
  const isStacked = d => !!d && d === data.getCalculationInfo('stackedDimension');
  if (isStacked(dims[0])) dims[0] = stackResultDim;
  if (isStacked(dims[1])) dims[1] = stackResultDim;
  const store = data.getStore();
  const i0 = data.getDimensionIndex(dims[0]);
  const i1 = data.getDimensionIndex(dims[1]);
  const out = [];
  for (let i = 0; i < data.count(); i++) {
    const p = coordSys.dataToPoint([store.get(i0, i), store.get(i1, i)], null, []);
    out.push(p[0], p[1]);
  }
  let stacked = null;
  if (dataCoordInfo) {
    stacked = [];
    for (let i = 0; i < data.count(); i++) {
      let value = NaN;
      if (dataCoordInfo.stacked) value = data.get(data.getCalculationInfo('stackedOverDimension'), i);
      if (isNaN(value)) value = dataCoordInfo.valueStart;
      const sd = [];
      sd[dataCoordInfo.baseDataOffset] = data.get(dataCoordInfo.baseDim, i);
      sd[1 - dataCoordInfo.baseDataOffset] = value;
      const p = coordSys.dataToPoint(sd);
      stacked.push(p[0], p[1]);
    }
  }
  return { doubles: out, stackedDoubles: stacked };
}
// helper.ts prepareDataCoordInfo / getValueStart (the parts getStackedOnPoint reads)
function dataCoordInfoOf(seriesModel) {
  const data = seriesModel.getData();
  const coordSys = seriesModel.coordinateSystem;
  const baseAxis = coordSys.getBaseAxis();
  const valueAxis = coordSys.getOtherAxis(baseAxis);
  const origin = seriesModel.getModel('areaStyle').get('origin');
  const extent = valueAxis.scale.getExtent();
  let valueStart = 0;
  if (origin === 'start') valueStart = extent[0];
  else if (origin === 'end') valueStart = extent[1];
  else if (typeof origin === 'number' && !isNaN(origin)) valueStart = origin;
  else if (extent[0] > 0) valueStart = extent[0];
  else if (extent[1] < 0) valueStart = extent[1];
  const dims = coordSys.dimensions.map(d => data.mapDimension(d));
  const isStacked = d => !!d && d === data.getCalculationInfo('stackedDimension');
  return {
    valueStart,
    stacked: isStacked(dims[0]) || isStacked(dims[1]),
    baseDim: data.mapDimension(baseAxis.dim),
    baseDataOffset: valueAxis.dim === 'x' || valueAxis.dim === 'radius' ? 1 : 0,
  };
}

function recordSeries(chart, sm, side, key) {
  const view = chart.getViewOfSeriesModel(sm);
  const data = sm.getData();
  const coordSys = sm.coordinateSystem;
  const pl = view._polyline;
  const pg = view._polygon || null;
  must(pl && pl.type === 'ec-polyline', key + ': no ECPolyline');
  const isArea = !sm.getModel('areaStyle').isEmpty();
  must(!!pg === isArea && (!pg || pg.type === 'ec-polygon'), key + ': polygon presence');
  const stackedOnSeries = data.getCalculationInfo('stackedOnSeries') || null;
  const smoothOption = sm.get('smooth');
  const sh = pl.shape;
  must(sh.connectNulls === sm.get('connectNulls') && sh.smoothMonotone === sm.get('smoothMonotone'), key + ': shape vs model');
  const resolved = Object.assign({ smoothOption: clone(smoothOption) }, numRec('smooth', sh.smooth), {
    smoothMonotone: clone(sh.smoothMonotone), connectNulls: !!sh.connectNulls,
    stepOption: clone(sm.get('step')), step: clone(view._step), area: isArea,
    stack: sm.get('stack') == null ? null : sm.get('stack'),
    stackedOn: stackedOnSeries ? { seriesIndex: stackedOnSeries.seriesIndex, smoothOption: clone(stackedOnSeries.get('smooth')),
      smoothMonotone: clone(stackedOnSeries.get('smoothMonotone')) } : null,
  });
  if (pg) {
    Object.assign(resolved, numRec('stackedOnSmooth', pg.shape.stackedOnSmooth));
    must(pg.shape.smooth === sh.smooth && pg.shape.smoothMonotone === sh.smoothMonotone && pg.shape.connectNulls === sh.connectNulls,
      key + ': polygon shape differs from the polyline shape');
  }

  // the path, built on demand
  pl.getBoundingRect();
  const lData = Array.prototype.slice.call(pl.path.data, 0, pl.path.len());
  must(Array.isArray(pl.path.data), key + ': the polyline proxy was made static');
  const lc = commands(lData, lData.length);
  const points = pl.shape.points;
  const isF32 = points instanceof Float32Array;
  must(isF32 || Array.isArray(points), key + ': points of kind ' + (points && points.constructor.name));
  const count = points.length / 2;
  const truncated = count > HEAD || lc.length > HEAD;
  const line = Object.assign({ pointsKind: isF32 ? 'float32' : 'array', count, truncated },
    pointsRec('points', points, truncated ? HEAD : null), { pointsDigest: pointsDigest(points) });
  const layout = data.getLayout('points');
  if (view._step) {
    must(layout instanceof Float32Array && !truncated, key + ': step layout points');
    Object.assign(line, pointsRec('layoutPoints', layout));
  } else {
    must(points === layout, key + ': the polyline points are not the layout points');
  }
  Object.assign(line, { path: pathRec(lc.slice(0, HEAD)), pathCount: lc.length, pathLen: lData.length, pathDigest: pathDigest(lc) },
    rectRec(pl.path.getBoundingRect()));

  let area = null;
  const sd = { points: Array.from(points) };
  if (pg) {
    pg.getBoundingRect();
    must(Array.isArray(pg.path.data), key + ': the polygon proxy was made static');
    const aData = Array.prototype.slice.call(pg.path.data, 0, pg.path.len());
    const ac = commands(aData, aData.length);
    const so = pg.shape.stackedOnPoints;
    const soF32 = so instanceof Float32Array;
    const aTrunc = so.length / 2 > HEAD || ac.length > HEAD;
    area = Object.assign({ pointsSameAsLine: pg.shape.points === points, stackedOnKind: soF32 ? 'float32' : 'array', truncated: aTrunc },
      pointsRec('stackedOnPoints', so, aTrunc ? HEAD : null), { stackedOnDigest: pointsDigest(so) },
      { path: pathRec(ac.slice(0, HEAD)), pathCount: ac.length, pathLen: aData.length, pathDigest: pathDigest(ac) },
      rectRec(pg.path.getBoundingRect()));
    must(area.pointsSameAsLine, key + ': the polygon points are not the polyline points');
    sd.stackedOnPoints = Array.from(so);
  }

  // the doubles before the Float32Array store (side only), checked to round to the record
  const dci = pg ? dataCoordInfoOf(sm) : null;
  Object.assign(sd, doublesOf(chart, sm, dci));
  must(sd.doubles.length === layout.length && sd.doubles.every((v, i) => Object.is(Math.fround(v), layout[i])
    || (Number.isNaN(v) && Number.isNaN(layout[i]))), key + ': the recomputed layout points do not round to the Float32Array');
  if (pg) {
    const f = sd.stackedDoubles.map(Math.fround);
    const baseIndex = coordSys.getBaseAxis().dim === 'x' || coordSys.getBaseAxis().dim === 'radius' ? 0 : 1;
    const want = view._step ? turnPointsIntoStep(f, Array.from(layout), baseIndex, view._step, sh.connectNulls) : f;
    const so = pg.shape.stackedOnPoints;
    must(want.length === so.length && want.every((v, i) => Object.is(v, so[i]) || (Number.isNaN(v) && Number.isNaN(so[i]))),
      key + ': the recomputed stacked-on points do not match the shape');
  }
  side[key] = sd;

  // symbols
  let symbols = null;
  if (data.count() <= HEAD) {
    symbols = [];
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) continue;
      must(Object.is(el.x, layout[i * 2]) && Object.is(el.y, layout[i * 2 + 1]), key + ': symbol ' + i + ' is not on its layout point');
      symbols.push([i, hex(el.x), hex(el.y)]);
    }
    if (!symbols.length) symbols = null;
  }

  return {
    seriesIndex: sm.seriesIndex, name: sm.option.name == null ? null : String(sm.option.name), coordSys: coordSys.type,
    baseAxisDim: coordSys.getBaseAxis().dim, dataCount: data.count(), rawCount: sm.getRawData().count(), resolved, line, area, symbols,
  };
}

// ---------- the cases ----------
const gallery = name => JSON.parse(fs.readFileSync(path.join(GALLERY, name + '.json'), 'utf8'));
const CAT12 = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const UPS = [120, 132, 101, 134, 290, 230, 210, 182, 191, 234, 330, 310];
const PLATEAU = [10, 10, 10, 60, 5, 5, 30, 32, 90, 88];
const cat = (series, extra) => Object.assign({
  xAxis: { type: 'category', data: CAT12.slice(0, Math.max(...series.map(s => s.data.length))) }, yAxis: { type: 'value' },
  series: series.map(s => Object.assign({ type: 'line' }, s)),
}, extra || {});
const val = (series, extra) => Object.assign({
  xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: series.map(s => Object.assign({ type: 'line' }, s)),
}, extra || {});
const UNEVEN = [[0, 3], [0.5, 8], [3, 2], [3.4, 9], [7, 6], [7.2, 1], [12, 4], [20, 10]];
const GAPS = [3, 7, null, 5, 9, '-', 2, 6, 4];
const EDGE_GAPS = [null, '-', 4, 9, 3, 8, null];

const CASES = [
  { id: 'S1', note: 'smooth true on a category line of 12 values with ups and downs', option: cat([{ smooth: true, data: UPS }]) },
  { id: 'S2a', note: 'smooth 0.2', option: cat([{ smooth: 0.2, data: UPS }]) },
  { id: 'S2b', note: 'smooth 0.8', option: cat([{ smooth: 0.8, data: UPS }]) },
  { id: 'S2c', note: 'smooth 1', option: cat([{ smooth: 1, data: UPS }]) },
  { id: 'S2d', note: 'smooth 1.5: used as is (no clamp); the extreme clamps bound the control points', option: cat([{ smooth: 1.5, data: UPS }]) },
  { id: 'S2e', note: 'smooth -0.3: a number, not > 0: straight L segments', option: cat([{ smooth: -0.3, data: UPS }]) },
  { id: 'S2f', note: 'smooth 0: straight', option: cat([{ smooth: 0, data: UPS }]) },
  { id: 'S2g', note: "smooth '0.5' (a string): not a number, truthy -> 0.5", option: cat([{ smooth: '0.5', data: UPS }]) },
  { id: 'S2h', note: "smooth '0' (a string): truthy -> 0.5 (not 0)", option: cat([{ smooth: '0', data: UPS }]) },
  { id: 'S2i', note: "smooth '0.3' (a string): truthy -> 0.5 (not 0.3)", option: cat([{ smooth: '0.3', data: UPS }]) },
  { id: 'S2j', note: "smooth '' (empty string): falsy -> 0", option: cat([{ smooth: '', data: UPS }]) },
  { id: 'S2k', note: 'smooth false (the default): straight', option: cat([{ smooth: false, data: UPS }]) },
  { id: 'M1', note: 'a plateau and sharp turns, smoothMonotone unset (the length-ratio branch)', option: cat([{ smooth: true, data: PLATEAU }]) },
  { id: 'M2', note: "the same, smoothMonotone 'x': horizontal tangents, x-distance control points", option: cat([{ smooth: true, smoothMonotone: 'x', data: PLATEAU }]) },
  { id: 'M3', note: "the same, smoothMonotone 'y' on an x-category line: vertical tangents", option: cat([{ smooth: true, smoothMonotone: 'y', data: PLATEAU }]) },
  { id: 'M4', note: "smoothMonotone 'x' with smooth 0.7 on an inverse x axis (vx < 0: dir -1)",
    option: cat([{ smooth: 0.7, smoothMonotone: 'x', data: PLATEAU }], { xAxis: { type: 'category', inverse: true, data: CAT12.slice(0, 10) } }) },
  { id: 'M5', note: "smoothMonotone 'none' written out: the length-ratio branch", option: cat([{ smooth: true, smoothMonotone: 'none', data: PLATEAU }]) },
  { id: 'M6', note: "smoothMonotone 'x' on a value x axis that turns back: prev and next share an x, so vx is 0 and the tangent's sign is -1 (vx > 0 ? 1 : -1)", option: { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', smooth: true, smoothMonotone: 'x', data: [[0, 0], [5, 5], [0, 10], [8, 12], [3, 20]] }] } },
  { id: 'V1', note: 'a value x axis with uneven x spacing (the length ratio matters)', option: val([{ smooth: true, data: UNEVEN }]) },
  { id: 'V2', note: "the same with smoothMonotone 'x'", option: val([{ smooth: true, smoothMonotone: 'x', data: UNEVEN }]) },
  { id: 'V3', note: 'uneven spacing, smooth 0.35, symbols off', option: val([{ smooth: 0.35, showSymbol: false, data: UNEVEN }]) },
  { id: 'H1', note: 'a horizontal line: category y axis, value x axis',
    option: { yAxis: { type: 'category', data: CAT12 }, xAxis: { type: 'value' }, series: [{ type: 'line', smooth: true, data: UPS }] } },
  { id: 'H2', note: "the horizontal line with smoothMonotone 'y' (vy < 0 going up the category axis: dir -1)",
    option: { yAxis: { type: 'category', data: CAT12 }, xAxis: { type: 'value' }, series: [{ type: 'line', smooth: true, smoothMonotone: 'y', data: UPS }] } },
  { id: 'H3', note: "the horizontal line, inverse y axis, smoothMonotone 'y' (dir +1), area",
    option: { yAxis: { type: 'category', inverse: true, data: CAT12 }, xAxis: { type: 'value' },
      series: [{ type: 'line', smooth: true, smoothMonotone: 'y', areaStyle: {}, data: UPS }] } },
  { id: 'I1', note: 'inverse x and y axes, smooth true, area', option: cat([{ smooth: true, areaStyle: {}, data: UPS }],
    { xAxis: { type: 'category', inverse: true, data: CAT12 }, yAxis: { type: 'value', inverse: true } }) },
  { id: 'N1', note: 'null gaps (null and "-"), connectNulls false: three runs, each smoothed on its own', option: cat([{ smooth: true, data: GAPS }]) },
  { id: 'N2', note: 'the same, connectNulls true: one run, the gap skipped and the next point searched across it',
    option: cat([{ smooth: true, connectNulls: true, data: GAPS }]) },
  { id: 'N3', note: 'gaps at the start and the end, connectNulls false', option: cat([{ smooth: true, data: EDGE_GAPS }]) },
  { id: 'N4', note: 'gaps at the start and the end, connectNulls true (the trim)', option: cat([{ smooth: true, connectNulls: true, data: EDGE_GAPS }]) },
  { id: 'N5', note: 'area with gaps and edge gaps, connectNulls true: the base still has points under the nulls',
    option: cat([{ smooth: true, connectNulls: true, areaStyle: {}, data: [null, 4, 9, null, 3, '-', 8, 5, null] }]) },
  { id: 'N6', note: 'area with gaps, connectNulls false: one closed polygon per run', option: cat([{ smooth: true, areaStyle: {}, data: GAPS }]) },
  { id: 'N7', note: 'every value null: an empty path', option: cat([{ smooth: true, data: [null, '-', null] }]) },
  { id: 'N8', note: "gaps with smoothMonotone 'x', connectNulls true", option: cat([{ smooth: true, smoothMonotone: 'x', connectNulls: true, data: GAPS }]) },
  { id: 'D1', note: 'duplicate consecutive points in the middle (value x axis)',
    option: val([{ smooth: true, data: [[0, 1], [1, 4], [1, 4], [2, 2], [3, 5], [3, 5], [3, 5], [4, 3]] }]) },
  { id: 'D2', note: 'duplicate points at the start and the end',
    option: val([{ smooth: true, data: [[0, 1], [0, 1], [1, 4], [2, 2], [3, 5], [3, 5]] }]) },
  { id: 'D3', note: 'tiny segments (squared length < 0.5 px) skipped; point 4 is tiny from the skipped point 3 but not from the drawn point 2, so it is drawn; the skipped tiny points still act as the NEXT point of the one before',
    option: val([{ smooth: true, data: [[0, 1], [0.001, 1.001], [1, 4], [1.0015, 4.002], [1.0045, 4.006], [2, 2], [3, 5], [3.001, 5]] }]) },
  { id: 'D4', note: 'tiny segments on a straight line (smooth 0): skipped too', option: val([{ smooth: 0, data: [[0, 1], [0.001, 1.001], [1, 4], [2, 2], [2.001, 2]] }]) },
  { id: 'D5', note: 'duplicate points in a stacked area (the base has them too)',
    option: val([{ smooth: true, stack: 's', areaStyle: {}, data: [[0, 1], [1, 4], [1, 4], [2, 2], [3, 5]] },
      { smooth: true, stack: 's', areaStyle: {}, data: [[0, 2], [1, 1], [1, 1], [2, 3], [3, 1]] }]) },
  { id: 'P1', note: 'a single point: M only', option: cat([{ smooth: true, data: [5] }]) },
  { id: 'P2', note: 'two points: one C whose control points are the end points', option: cat([{ smooth: true, data: [5, 9] }]) },
  { id: 'P3', note: 'three points', option: cat([{ smooth: true, data: [5, 9, 2] }]) },
  { id: 'P4', note: 'a single point with an area', option: cat([{ smooth: true, areaStyle: {}, data: [5] }]) },
  { id: 'A1', note: 'smooth area, not stacked: the base (valueStart) straight (stackedOnSmooth 0)', option: cat([{ smooth: true, areaStyle: {}, data: UPS }]) },
  { id: 'A2', note: "smooth area with areaStyle.origin 'end'", option: cat([{ smooth: 0.4, areaStyle: { origin: 'end' }, data: UPS }]) },
  { id: 'K1', note: 'two stacked smooth areas: the upper base is the lower line, smoothed backwards',
    option: cat([{ smooth: true, stack: 't', areaStyle: {}, data: UPS }, { smooth: true, stack: 't', areaStyle: {}, data: [220, 182, 191, 234, 290, 330, 310, 123, 442, 321, 90, 149] }]) },
  { id: 'K2', note: 'stacked: lower smooth false, upper smooth true (the upper base straight)',
    option: cat([{ smooth: false, stack: 't', areaStyle: {}, data: UPS }, { smooth: true, stack: 't', areaStyle: {}, data: [220, 182, 191, 234, 290, 330, 310, 123, 442, 321, 90, 149] }]) },
  { id: 'K3', note: 'stacked: lower smooth 0.8, upper smooth false (the upper base smoothed 0.8, its top straight)',
    option: cat([{ smooth: 0.8, stack: 't', areaStyle: {}, data: UPS }, { smooth: false, stack: 't', areaStyle: {}, data: [220, 182, 191, 234, 290, 330, 310, 123, 442, 321, 90, 149] }]) },
  { id: 'K4', note: "stacked: lower smoothMonotone 'x', upper none: the base uses the UPPER series' smoothMonotone",
    option: cat([{ smooth: true, smoothMonotone: 'x', stack: 't', areaStyle: {}, data: UPS }, { smooth: true, stack: 't', areaStyle: {}, data: [220, 182, 191, 234, 290, 330, 310, 123, 442, 321, 90, 149] }]) },
  { id: 'K5', note: 'stacked with a null in the lower series and one in the upper, connectNulls false',
    option: cat([{ smooth: true, stack: 't', areaStyle: {}, data: [120, 132, null, 134, 290, 230, 210] }, { smooth: true, stack: 't', areaStyle: {}, data: [220, 182, 191, 234, null, 330, 310] }]) },
  { id: 'K6', note: 'three stacked smooth lines, only the top one an area, smooth 0.3 / true / 0.6',
    option: cat([{ smooth: 0.3, stack: 't', data: UPS }, { smooth: true, stack: 't', data: UPS.slice().reverse() }, { smooth: 0.6, stack: 't', areaStyle: {}, data: UPS }]) },
  { id: 'T1', note: 'step true with smooth true: the step points smoothed (C commands, axis-aligned)', option: cat([{ step: true, smooth: true, data: UPS }]) },
  { id: 'T2', note: "step 'middle' with smooth true and an area", option: cat([{ step: 'middle', smooth: true, areaStyle: {}, data: UPS }]) },
  { id: 'T3', note: "step 'end', smooth 0.6, connectNulls true, nulls, area", option: cat([{ step: 'end', smooth: 0.6, connectNulls: true, areaStyle: {}, data: GAPS }]) },
  { id: 'T4', note: 'step true, smooth true on a value x axis with uneven spacing', option: val([{ step: 'start', smooth: true, data: UNEVEN }]) },
  { id: 'TM1', note: 'smooth on a time axis',
    option: { xAxis: { type: 'time' }, yAxis: { type: 'value' }, series: [{ type: 'line', smooth: true,
      data: [[1704067200000, 5], [1704153600000, 9], [1704412800000, 3], [1704499200000, 7], [1705017600000, 12], [1705104000000, 4], [1706745600000, 8]] }] } },
  { id: 'Z1', note: "an inside dataZoom window 20..60 %, filterMode 'filter' (default): only the window's points",
    option: cat([{ smooth: true, data: UPS }], { dataZoom: [{ type: 'inside', start: 20, end: 60 }] }) },
  { id: 'Z2', note: "the same with filterMode 'none': every point, the ones outside the grid clipped by the line group's clip rect",
    option: cat([{ smooth: true, data: UPS }], { dataZoom: [{ type: 'inside', start: 20, end: 60, filterMode: 'none' }] }) },
  { id: 'SY1', note: 'smooth with symbols (symbolSize 10, showAllSymbol): symbols stay on the points',
    option: cat([{ smooth: true, symbol: 'circle', symbolSize: 10, showAllSymbol: true, data: UPS }]) },
  { id: 'L1', note: 'log y axis with 0 and a negative value: non-finite points (illegal) break the line like nulls',
    option: cat([{ smooth: true, data: [3, 30, 0, 300, 20, -5, 7, 100] }], { yAxis: { type: 'log' } }) },
  { id: 'L2', note: 'the log line with connectNulls true', option: cat([{ smooth: true, connectNulls: true, data: [3, 30, 0, 300, 20, -5, 7, 100] }], { yAxis: { type: 'log' } }) },
  { id: 'PO1', note: 'polar (angle category, radius value), smooth true, step true: step is ignored on polar',
    option: { polar: {}, angleAxis: { type: 'category', data: CAT12 }, radiusAxis: {}, series: [{ type: 'line', coordinateSystem: 'polar', smooth: true, step: true, data: UPS }] } },
];
// every gallery file with a smoothed LINE series (pie-custom's smooth is a pie
// labelLine's, scatter-matrix's a parallel series': not line series)
const GALLERY_CASES = ['area-pieces', 'area-stack-gradient', 'area-time-axis', 'bump-chart', 'candlestick-brush', 'candlestick-sh-2015',
  'candlestick-sh', 'candlestick-touch', 'dataset-link', 'line-draggable', 'line-graphic', 'line-pen', 'line-sections', 'line-smooth',
  'line-tooltip-touch', 'line-y-category', 'multiple-x-axis', 'pictorialBar-dotted'];
for (const g of GALLERY_CASES) CASES.push({ id: 'G-' + g, note: 'gallery ' + g + '.json, verbatim', gallery: g });

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

function recordCase(def, side) {
  const optionText = JSON.stringify(def.gallery ? gallery(def.gallery) : def.option);
  return runChart(JSON.parse(optionText), chart => {
    const lines = chart.getModel().getSeries().filter(s => s.subType === 'line');
    must(lines.length >= 1, def.id + ': no line series');
    const series = lines.map(sm => recordSeries(chart, sm, side, def.id + '/' + sm.seriesIndex));
    if (def.gallery) must(series.some(s => s.resolved.smooth !== hex(0)), def.id + ': no smoothed line series');
    return { id: def.id, note: def.note, width: chart.getWidth(), height: chart.getHeight(), gallery: def.gallery || null,
      option: def.gallery ? null : JSON.parse(optionText), series };
  });
}

// ---------- the guards ----------
const GUARDS = [
  { id: 'f64', mutation: 'control points computed from the double points (before the Float32Array store)', mut: { f64: true }, named: ['S1', 'K1', 'TM1'] },
  { id: 'monotone', mutation: 'smoothMonotone ignored (always the length-ratio branch)', mut: { monotoneIgnored: true }, named: ['M2', 'M3', 'M4', 'V2', 'H2', 'H3'] },
  { id: 'ratio', mutation: 'the neighbouring-segment length ratio ignored (constant 0.5 split)', mut: { ratioHalf: true }, named: ['S1', 'V1', 'V3'] },
  { id: 'ends', mutation: 'the last point of a run smoothed with a half-length cp (instead of cp1 = the point)', mut: { endMirror: true }, named: ['S1', 'P2', 'N1'] },
  { id: 'base-straight', mutation: 'the area base never smoothed (stackedOnSmooth taken as 0)', mut: { baseStraight: true }, named: ['K1', 'K3', 'K6'] },
  { id: 'base-own-smooth', mutation: "the area base smoothed with the series' own smooth instead of the stacked-on series'", mut: { baseOwnSmooth: true }, named: ['K2', 'K3', 'A1'] },
  { id: 'base-monotone', mutation: "the area base with the stacked-on series' smoothMonotone instead of its own", mut: { baseMonoFromStackedOn: true }, named: ['K4'] },
  { id: 'base-forward', mutation: 'the area base smoothed left to right and then reversed (instead of smoothed walking backwards)', mut: { baseForward: true }, named: ['K1'] },
  { id: 'clamp', mutation: "the 'avoid exceeding extreme' min/max clamps skipped", mut: { noClamp: true }, named: ['S1', 'M1', 'S2d'] },
  { id: 'tiny', mutation: 'tiny segments (squared length < 0.5) not skipped', mut: { noTiny: true }, named: ['D3', 'D4'] },
  { id: 'tiny-prev', mutation: 'a skipped tiny point becomes the previous point (upstream keeps the last DRAWN one)', mut: { tinyPrev: true }, named: ['D3'] },
  { id: 'dup', mutation: 'the duplicate-next-point loop removed', mut: { noDup: true }, named: ['D1', 'D2', 'D5'] },
  { id: 'next-search', mutation: 'connectNulls: the next legal point not searched across a gap', mut: { noNextSearch: true }, named: ['N2', 'N8'] },
  { id: 'trim', mutation: 'connectNulls: leading / trailing illegal points not trimmed', mut: { noTrim: true }, named: ['N4', 'N5'] },
  { id: 'smooth-parse', mutation: "a string smooth parsed as a number ('0' -> 0, '0.3' -> 0.3)", mut: { smoothParse: true }, named: ['S2h', 'S2i'] },
  { id: 'smooth-clamp', mutation: 'smooth clamped to [0, 1]', mut: { smoothClamp: true }, named: ['S2d'] },
  { id: 'step-wins', mutation: 'step turns smooth off', mut: { stepKillsSmooth: true }, named: ['T1', 'T2', 'T3'] },
  { id: 'bbox-ends', mutation: "the path rect from each curve's end points only (no cubic extrema)", mut: { bboxEnds: true }, named: ['M3', 'I1'] },
];

// ---------- the run ----------
function generate() {
  const side = {};
  const cases = CASES.map(d => recordCase(d, side));
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version
      + ' (V8 ' + process.versions.v8 + ')',
    W, H, seed: SEED, head: HEAD,
    api: {
      view: 'chart.getViewOfSeriesModel(lineSeriesModel): _polyline (ECPolyline), _polygon (ECPolygon | null), _step',
      shape: 'polyline.shape {points, smooth, smoothMonotone, connectNulls}; polygon.shape adds {stackedOnPoints, stackedOnSmooth}',
      path: 'el.getBoundingRect() builds el.path (beginPath + buildPath into a plain number[]); el.path.data up to el.path.len(); rect = el.path.getBoundingRect()',
      layoutPoints: "seriesData.getLayout('points') (layout/points.ts with forceStoreInTypedArray: a Float32Array)",
      symbols: 'seriesData.getItemGraphicEl(i).x / .y',
      stackedOn: "seriesData.getCalculationInfo('stackedOnSeries')",
    },
    notes: [
      'The points are a Float32Array (layout/points.ts, registered as pointsLayout(\'line\', true)); coordSys.dataToPoint computes doubles and the store rounds each to float32. stackedOnPoints likewise (LineView getStackedOnPoints, createFloat32Array). Everything after that is double arithmetic on float32-exact inputs: the control points are NOT rounded.',
      'The path here is the doubles buildPath wrote (Path.getBoundingRect / the SVG painter never call toStatic). The CANVAS painter calls path.toStatic() right after buildPath, which turns a proxy of more than 11 numbers into a Float32Array: on canvas every path number is rounded to float32 once more before drawing. The recorded path is the pre-toStatic doubles.',
      "getSmooth: a number is used as is (no clamp: 1.5 stays 1.5, -0.3 draws straight because only smooth > 0 curves); anything else is truthiness -> 0.5 / 0, so the strings '0', '0.3' give 0.5 and '' gives 0.",
      'Step wins over nothing: turnPointsIntoStep rewrites the points and the polyline is still smoothed with the series smooth. Every step segment is axis-aligned, and the min/max clamps keep the control points on it, so the curves are straight in effect but are C commands.',
      'On polar, step is forced off (view._step false); smooth applies.',
      'Tiny segments: a point whose squared distance from the previous DRAWN point is < 0.5 is skipped, smooth or not (drawSegment), and k still counts it.',
      "Sampling (series.sampling, processor/dataSample.ts) runs before the layout on cartesian2d when count > 10 and round(count / axis pixel length) > 1: the smoothed points are the sampled ones. No case here samples.",
      "The line group's clip rect (createGridClipPath) is independent of smooth; the smoothed curve is clipped like the straight one.",
      'Symbols sit on the layout points (float32), never on the curve; with step they sit on the pre-step points.',
      'Truncated series (count > head or more than head commands): points / stackedOnPoints / path hold the first head entries; the digests cover everything.',
    ],
    cases,
  };
  return { out, side };
}

function seriesDiffs(sr, side, key, mut) {
  const sd = side[key];
  return diffFlat(flatRecord(sr), model(sr, sd, mut));
}

function check(g) {
  const { out, side } = g;
  const byId = {};
  for (const c of out.cases) {
    byId[c.id] = c;
    must(c.width === W && c.height === H, c.id + ': canvas ' + c.width + 'x' + c.height);
    for (const sr of c.series) {
      const key = c.id + '/' + sr.seriesIndex;
      const d = seriesDiffs(sr, side, key, {});
      must(!d.length, key + ': the transcription differs at ' + d.slice(0, 3).map(x => JSON.stringify(compactDiff(x))).join('; '));
      for (const part of [sr.line, sr.area]) {
        if (!part) continue;
        for (const cmd of part.path) for (const a of cmd.args) must(isFinite(num(a)), key + ': a non-finite path argument');
        RK.forEach(k => must(part.pathCount === 0 || isFinite(num(part.rect[k])), key + ': a non-finite rect'));
      }
      if (sr.line.pointsKind === 'float32') {
        for (const p of sr.line.points) for (const v of p) must(Number.isNaN(num(v)) || Object.is(Math.fround(num(v)), num(v)), key + ': a float32 point that is not a float32');
      }
      must(sr.resolved.step === false || sr.line.pointsKind === 'array', key + ': step points not an array');
    }
  }
  // anchors
  const s1 = byId.S1.series[0];
  must(s1.line.path[0].cmd === 'M' && s1.line.path.slice(1).every(c => c.cmd === 'C') && s1.line.pathCount === 12, 'S1: M + 11 C');
  must(byId.S2e.series[0].line.path.slice(1).every(c => c.cmd === 'L'), 'S2e: straight');
  must(byId.S2h.series[0].resolved.smoothText === '0.5' && byId.S2j.series[0].resolved.smoothText === '0', "S2h / S2j: '0' -> 0.5, '' -> 0");
  must(byId.S2d.series[0].resolved.smoothText === '1.5', 'S2d: 1.5 kept');
  must(byId.T1.series[0].line.pointsKind === 'array' && byId.T1.series[0].line.path.slice(1).every(c => c.cmd === 'C'), 'T1: step points smoothed');
  must(byId.PO1.series[0].resolved.step === false && byId.PO1.series[0].resolved.stepOption === true, 'PO1: step off on polar');
  must(byId.P1.series[0].line.pathCount === 1 && byId.N7.series[0].line.pathCount === 0, 'P1 / N7 path counts');
  must(byId.N1.series[0].line.path.filter(c => c.cmd === 'M').length === 3, 'N1: three runs');
  must(byId.N2.series[0].line.path.filter(c => c.cmd === 'M').length === 1, 'N2: one run');
  must(byId.K1.series[1].resolved.stackedOn.seriesIndex === 0 && byId.K1.series[1].resolved.stackedOnSmoothText === '0.5', 'K1 stackedOn');
  must(byId.A1.series[0].resolved.stackedOnSmoothText === '0', 'A1 base smooth 0');
  must(out.cases.some(c => c.series.some(s => s.line.truncated)), 'no truncated series');
  for (const id of ['D3', 'D4']) {
    const l = byId[id].series[0].line;
    must(l.pathCount < l.count, id + ': no tiny segment skipped (' + l.pathCount + ' commands for ' + l.count + ' points)');
  }

  return GUARDS.map(gd => {
    const changed = [];
    const differs = [];
    for (const c of out.cases) {
      let any = false;
      for (const sr of c.series) {
        const key = c.id + '/' + sr.seriesIndex;
        let d;
        try {
          d = seriesDiffs(sr, side, key, gd.mut);
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

let g1;
let json1;
let json2;
try {
  g1 = generate();
  g1.out.guards = check(g1);
  json1 = fmt(g1.out, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(g1.out), 'the written JSON does not parse back to the record');
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
const nSeries = out.cases.reduce((n, c) => n + c.series.length, 0);
console.log(out.cases.length + ' cases (' + nSeries + ' line series); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
