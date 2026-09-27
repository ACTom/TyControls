// Upstream's own answers for scaleCalcAlign: a radar indicator aligned onto
// the dummy [0, splitNumber] interval-1 scale, and a cartesian axis with
// alignTicks aligned onto its reference axis (batch 48 audit, wf48/audit48.md
// SS1 and SS3).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer), renders once, and
// reads the scale internals directly -- never the SVG text. A case the
// development build throws on is re-run through the production build
// (echarts.min.js) and says so (build 'prod', devError).
//
// The recipe (SS1; every step one IEEE double operation, JS evaluation order;
// it is embedded below and every recorded field is reproduced from `input`
// bit for bit):
//   round(x,p)      NaN p -> x; else p = min(max(0,p),20); +x.toFixed(p)
//   qE(v)           v === 0 -> 0; e = floor(log(v)/LN10); v/10^e >= 10 -> e+1
//   niceMin(v)      round(10^qE(v), -qE(v))                  (niceMin(0) = 1)
//   inc(iv)         e = qE(iv); f = Math.round(iv/10^e); !f -> 1, 2 -> 3,
//                   3 -> 5, else f*2; round(f*10^e, -e)
//   ivPrec(iv)      getPrecision(iv) + 2
//   accPrec(ext,px,a)  span = |ext1-ext0|; non-finite or 0 -> NaN;
//                   d = log(2*|a|*span)/LN10; q = log(|px|)/LN10;
//                   p = max(0, ceil(-d+q)); non-finite -> NaN (px 0 -> 0)
//   ensureValid(e,fix)  e0 === e1: non-zero x = |e0|, !fix1 -> e1 += x/2,
//                   e0 -= x/2; fix1 -> only e0 -= x/2; zero -> e1 = 1; then a
//                   non-finite end -> [0,1]; e1 < e0 -> reverse
//   ref             n = T.length-1; n 1: t0 = t1 = 0, seg 1; n 2: i0 = |T0-T1|,
//                   i1 = |T1-T2|, equal -> seg 2, else seg 1 and t0 = i0/i1
//                   (i0 < i1) or t1 = i1/i0; n >= 3: t0 = (1-(T0-X0)/refIv)%1,
//                   t1 = (1-(Xn-Tn)/refIv)%1, seg = n - !!t0 - !!t1
//   E               ensureValid(effMM in interval space, fix); a log target's
//                   effMM goes through log(v)/log(base) first
//   both fixed      min = E0, max = E1, iv = (max-min)/(seg+t0+t1);
//                   p = accPrec([max,min], px, 0.5/seg); minNice = t0 ?
//                   round(min+iv*t0,p) : min; maxNice = t1 ? round(max-iv*t1,p)
//                   : max; THEN iv = round(iv,p) when p is finite
//   otherwise       iv = isLog ? max(10^qE(E1-E0), 1) : niceMin((E1-E0)/seg),
//                   p = ivPrec(iv); 50 x { if cb() break; iv = isLog ?
//                   iv*max(base,2) : inc(iv); p = ivPrec(iv) } -- an exhausted
//                   loop stores the interval one step PAST the last pass
//     min fixed     min = E0; minNice = t0 ? round(min+iv*t0,p) : min;
//                   maxNice = round(minNice+iv*seg,p); max = round(maxNice+
//                   iv*t1,p); stop when max >= E1
//     max fixed     the mirror; stop when min <= E0
//     neither       minNice = round(ceil(E0/iv)*iv,p), maxNice =
//                   round(floor(E1/iv)*iv,p), cnt = Math.round((maxNice-
//                   minNice)/iv); cnt <= seg: more = seg-cnt, z = incl0||isLog;
//                   pair = z && E0 === 0 ? [0,more] : z && E1 === 0 ? [more,0]
//                   : h = floor(more/2), more even ? [h,h] : (min+max) <
//                   (E0+E1) ? [h,h+1] : [h+1,h] -- min, max of the LAST pass
//                   that wrote them (NaN before: the test is false); minNice
//                   = round(minNice-iv*pair0,p), maxNice = round(maxNice+
//                   iv*pair1,p), min = round(minNice-iv*t0,p), max =
//                   round(maxNice+iv*t1,p); stop when min <= E0 && max >= E1
//   write back      extent [min,max]; cfg {interval iv, intervalCount seg,
//                   intervalPrecision p (NOT clamped; NaN allowed), niceExtent
//                   [minNice,maxNice]}; log: outer end i = the effMM end whose
//                   log equals the new end (log(effMM0) first), else
//                   base^end; a fixed end whose interval extent did not
//                   change keeps effMM i
//   ticks           iv falsy -> []; ext0 < ne0 -> ext0; k = 0..count: tick =
//                   min(tick, ne1), k == count -> ne1, push, tick =
//                   round(tick+iv,p), equal to the last -> stop; ext1 > last
//                   -> ext1. Log outer ticks: an interval tick equal to an
//                   extent end -> that outer end, else base^tick
//   label           addCommas(toFixed(v, min(getPrecision(v), 20))) of the
//                   tick (the outer tick on a log axis)
//   radar           n = Math.round(max(sn || 5, 1)); ref = 0..n, iv 1; raw:
//                   max > 0 && !min -> min = 0, else min < 0 && !max -> max =
//                   0; fix = written ends; eff = written ends, else the data;
//                   incl0 = !scale: both > 0 && !fix0 -> eff0 = 0, both < 0
//                   && !fix1 -> eff1 = 0; eff0 > eff1 -> swap the VALUES only
//                   (fix stays by index; inverse toggles); px = |r - r0|
//   ring coords     k-th ring of spoke i at dataToCoord_i(tick_k) =
//                   linearMap(normalize(tick)) : t = (tick-e0)/(e1-e0) (0.5
//                   when e1 === e0); t === 0 -> r0, t === 1 -> r, else
//                   t*(r-r0)+r0
//   ring count      polygon: min over spokes of (ticks-1); circle: axis 0's;
//                   split lines drawn = ringCount + 1
//   cartesian px    the grid rect from the OPTION only (getLayoutRect of the
//                   grid box params), before outerBounds / containLabel
//                   shrink it: the align pass runs inside Grid#update, before
//                   its closing resize
//
// The fixture, top level:
//   source          'ECharts <version>'
//   checks          the self-check tally the file was written with
//   guards[]        {mutation, what, named[], changed[]}: each mutation of
//                   the recipe (self-check 4) and the compared cases whose
//                   recomputed out it changes; a `named` case must be among
//                   them. The audit named A1 for niceRound and C6 for
//                   roundedIvForNice; neither bites (A1 reaches 5 from 1 and
//                   from 5 alike; C6 rounds to the same 2 places), so
//                   NR-min0 and RIV stand in for them
//   cases[]         below
//
// Per case:
//   name, kind ('radar'|'cartesian'), scope ('B' radar | 'C' cartesian |
//   'out': unit level only -- none at present; E10 was one until the port
//   had dataZoom), canvas {w, h}, option (as run, animation false),
//   build ('dev'|'prod'), devError (prod only)
//   documentary, note     recorded for the reader
//   deferred, why         a self-check failed by design
//   radar           (radar only) r0, r (+Text): the spoke pixel extent;
//                   shape 'polygon'|'circle'; ringCount (-1 when a spoke has
//                   no ticks); linesDrawn (split-line subpaths upstream built)
//   grid            (cartesian only) optionRect, finalRect {x,y,width,height}
//                   (+Text); referenceAxes[] ('y0', ...): the axes some
//                   aligned axis aligns to
//   axes[]          one per ALIGNED axis (none when upstream aligned none):
//     path          'radar0.i2' | 'y1'
//     alignTo       'dummy' (radar) | 'y0' ...
//     input         effMM [hex,hex] (makeFinal, pow space on a log axis;
//                   NaN = 7ff8000000000000), fix [b,b] (fixMM || any
//                   zoomFixMM: axisAlignTicks.ts:161-165, either end pinned
//                   by a dataZoom fixes both), fixMM [b,b] (makeFinal's,
//                   zoom pins included), zoomFixMM [b,b], zoomPercent,
//                   zoomValue [hex,hex] | null (the dataZoom window over the
//                   axis: its axis proxy's getWindow(); null without one),
//                   incl0, isLog, base (hex), reversed
//                   (tggAxInv), px (hex, the span align saw), splitNumber
//                   (radar n, else null), refTicks[], refExpTicks[] (hex),
//                   refInterval (hex)
//     out           t0, t1 (hex), seg, validExt[2], extent[2] (interval
//                   space), outerExtent[2] (log: pow space) | null,
//                   interval, intervalPrecision (hex | null when NaN),
//                   intervalCount, niceExtent[2], ticks[] (interval space),
//                   outerTicks[] (log) | null, labels[] (strings),
//                   tickCoords[] (radar: dataToCoord of each tick, local px
//                   from the centre) | null, passes, exhausted, inverse
//                   t0, t1, seg, validExt, passes and exhausted are the
//                   recipe's; everything else is read from upstream
//     pxFinal       (cartesian) the final pixel span, documentary
//     text          String(v) twins ('-0' for -0, 'NaN'): effMM, zoomPercent,
//                   zoomValue, px, base,
//                   refInterval, t0, t1, validExt, extent, outerExtent,
//                   interval, intervalPrecision, niceExtent, ticks,
//                   outerTicks, tickCoords
//
// Self-checks (the script writes nothing and exits 1 when a non-deferred case
// fails one, or when self-check 4 or d fails):
//   1 recipe: the embedded recipe recomputes every upstream field of `out`
//     from `input` alone, Object.is on every number, labels string-equal; a
//     radar axis is also recomputed from the OPTION (raw rule + splitNumber)
//     and must give the same input and out; a cartesian px must equal the
//     option rect's span, and the rect Grid#update started from; the zoom
//     rule (AxisProxy.reset sets zoomMM only for an end off 0% / 100%;
//     makeFinal pins it: effMM i = window value i, fixMM i = zoomFixMM i =
//     true) gives zoomFixMM from zoomPercent, every pinned effMM end is its
//     zoomValue bit for bit, and fix is fixMM || either zoomFixMM
//   2 twins: parseFloat(text) has the bits of the hex beside it
//   3 invariants: ticks.length === intervalCount + 1 + (ext0 < ne0) + (ext1 >
//     last) unless interval is 0 (then []); radar intervalCount ===
//     splitNumber and linesDrawn === ringCount + 1; !exhausted -> extent
//     contains validExt
//   4 guards: every recipe mutation below changes >= 1 compared case, among
//     them the one named for it
//   d the JSON is generated twice in-process and must be byte-identical
//
// Doubles are 16 lowercase hex digits of the IEEE-754 bits, big-endian.
//
//   node tools/advchart-oracle/scale-align.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-scale-align.json');

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
const hexArr = a => (a ? a.map(hex) : null);
const textArr = a => (a ? a.map(text) : null);
const same = (a, b) => Object.is(a, b);
const sameArr = (a, b) => (a == null && b == null) || (a != null && b != null && a.length === b.length && a.every((v, i) => same(v, b[i])));
const clone = o => JSON.parse(JSON.stringify(o));
const RECT = ['x', 'y', 'width', 'height'];
const plainRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const hexRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const textRect = r => ({ x: text(r.x), y: text(r.y), width: text(r.width), height: text(r.height) });

// ---------- the recipe (wf48/audit/recipe.js, with the self-check 4 mutations) ----------
// M holds the mutation being tried (self-check 4); {} is the recipe itself.
let M = {};
const LN10 = Math.LN10;

function round(x, p) {                       // number.ts:222-236
  if (isNaN(p)) return +x;
  p = Math.min(Math.max(0, p), 20);
  return +(+x).toFixed(p);
}
function roundStr(x, p) {
  if (isNaN(p)) return '' + x;
  p = Math.min(Math.max(0, p), 20);
  return (+x).toFixed(p);
}
function quantityExponent(v) {               // number.ts:581-598
  if (v === 0) return 0;
  let e = Math.floor(M.log10 ? Math.log10(v) : Math.log(v) / LN10);
  if (v / Math.pow(10, e) >= 10) e++;
  return e;
}
const quantity = v => Math.pow(10, quantityExponent(v));
function niceMin(v) {                        // number.ts:614-673, NICE_MODE_MIN
  const e = quantityExponent(v);
  const x10 = Math.pow(10, e);
  let nf = 1;
  if (M.niceRound) {                         // mutation: NICE_MODE_ROUND
    const f = v / x10;
    nf = f < 1.5 ? 1 : f < 2.5 ? 2 : f < 4 ? 3 : f < 7 ? 5 : 10;
  }
  return round(nf * x10, -e);
}
function increaseInterval(iv) {              // scale/helper.ts:125-144
  const e = quantityExponent(iv);
  const x10 = Math.pow(10, e);
  let f = Math.round(iv / x10);
  if (M.inc125) {                            // mutation: a 1-2-5 step table
    if (!f) f = 1; else if (f === 1) f = 2; else if (f === 2) f = 5; else f *= 2;
  } else if (!f) f = 1; else if (f === 2) f = 3; else if (f === 3) f = 5; else f *= 2;
  return round(f * x10, -e);
}
function getPrecisionSafe(val) {             // number.ts:297-308
  const str = val.toString().toLowerCase();
  const ei = str.indexOf('e');
  const exp = ei > 0 ? +str.slice(ei + 1) : 0;
  const sig = ei > 0 ? ei : str.length;
  const dot = str.indexOf('.');
  const dec = dot < 0 ? 0 : sig - 1 - dot;
  return Math.max(0, dec - exp);
}
function getPrecision(val) {                 // number.ts:265-291
  val = +val;
  if (isNaN(val)) return 0;
  if (val > 1e-14) {
    let e = 1;
    for (let i = 0; i < 15; i++, e *= 10) if (Math.round(val * e) / e === val) return i;
  }
  return getPrecisionSafe(val);
}
const getIntervalPrecision = iv => getPrecision(iv) + 2;
function getAcceptableTickPrecision(ext, pxSpan, a) {  // number.ts:339-369
  const span = Math.abs(ext[1] - ext[0]);
  if (!isFinite(span) || span === 0) return NaN;
  if (M.px0NaN && pxSpan === 0) return NaN;  // mutation
  const lg = M.log10 ? Math.log10 : x => Math.log(x) / LN10;
  const d = lg(2 * Math.abs(a || 1) * Math.abs(span));
  const px = lg(Math.abs(pxSpan));
  let p = Math.max(0, Math.ceil(-d + px));
  if (!isFinite(p)) p = NaN;
  return p;
}
function ensureValidExtent(raw, fix) {       // scale/helper.ts:224-276
  const e = raw.slice();
  if (e[0] === e[1]) {
    if (e[0] !== 0) {
      const x = Math.abs(e[0]);
      if (!fix[1] || M.flatBoth) { e[1] += x / 2; e[0] -= x / 2; } else e[0] -= x / 2;
    } else e[1] = 1;
  }
  if (!(e[0] != null && isFinite(e[0])) || !(e[1] != null && isFinite(e[1]))) { e[0] = 0; e[1] = 1; }
  if (e[1] < e[0]) e.reverse();
  return e;
}
const clampP = p => (M.clampStored && !isNaN(p) ? Math.min(Math.max(0, p), 20) : p);

// ref {ticks, expTicks, interval}; tgt {ext (interval space), fix, incl0, isLog, base, px}
function scaleCalcAlign(ref, tgt) {          // axisAlignTicks.ts:44-360
  const T = ref.ticks, X = ref.expTicks, n = T.length - 1;
  let t0, t1, seg;
  if (n === 1) { t0 = t1 = 0; seg = 1; }
  else if (n === 2) {
    const i0 = Math.abs(T[0] - T[1]), i1 = Math.abs(T[1] - T[2]);
    t0 = t1 = 0;
    if (i0 === i1) seg = 2; else { seg = 1; if (i0 < i1) t0 = i0 / i1; else t1 = i1 / i0; }
  } else {
    t0 = (1 - (T[0] - X[0]) / ref.interval) % 1;
    t1 = (1 - (X[n] - T[n]) / ref.interval) % 1;
    seg = n - (t0 ? 1 : 0) - (t1 ? 1 : 0);
  }
  const fix = tgt.fix;
  const E = ensureValidExtent(tgt.ext, fix);
  let min, max, iv, p, maxNice, minNice, passes = 0, exhausted = false;
  const inc = () => { iv = tgt.isLog ? iv * Math.max(tgt.base, 2) : increaseInterval(iv); p = clampP(getIntervalPrecision(iv)); };
  const loop = cb => {
    let g = 0;
    for (; g < 50; g++) {
      passes++;
      if (cb()) break;
      if (M.noExtraInc && g === 49) break;   // mutation: no step after the last pass
      inc();
    }
    exhausted = g >= 50 || (M.noExtraInc && g === 49);
  };
  if (fix[0] && fix[1]) {
    min = E[0]; max = E[1];
    iv = (max - min) / (seg + t0 + t1);
    p = clampP(getAcceptableTickPrecision([max, min], tgt.px, 0.5 / seg));
    if (M.roundedIvForNice && p != null && isFinite(p)) iv = round(iv, p);   // mutation
    minNice = t0 ? round(min + iv * t0, p) : min;
    maxNice = t1 ? round(max - iv * t1, p) : max;
    if (p != null && isFinite(p)) iv = round(iv, p);
  } else {
    const span = E[1] - E[0];
    iv = tgt.isLog ? Math.max(quantity(span), 1) : niceMin(span / seg);
    p = clampP(getIntervalPrecision(iv));
    if (fix[0]) {
      min = E[0];
      loop(() => {
        minNice = t0 ? round(min + iv * t0, p) : min;
        maxNice = round(minNice + iv * seg, p);
        max = round(maxNice + iv * t1, p);
        return max >= E[1];
      });
    } else if (fix[1]) {
      max = E[1];
      loop(() => {
        maxNice = t1 ? round(max - iv * t1, p) : max;
        minNice = round(maxNice - iv * seg, p);
        min = round(minNice - iv * t0, p);
        return min <= E[0];
      });
    } else {
      loop(() => {
        if (M.freshCentring) { min = undefined; max = undefined; }   // mutation
        minNice = round(Math.ceil(E[0] / iv) * iv, p);
        maxNice = round(Math.floor(E[1] / iv) * iv, p);
        const cnt = Math.round((maxNice - minNice) / iv);
        if (cnt <= seg) {
          const more = seg - cnt;
          const z = tgt.incl0 || tgt.isLog;
          let pair;
          if (z && E[0] === 0) pair = [0, more];
          else if (z && E[1] === 0) pair = [more, 0];
          else {
            const h = Math.floor(more / 2);
            pair = more % 2 === 0 ? [h, h] : (min + max) < (E[0] + E[1]) ? [h, h + 1] : [h + 1, h];
          }
          minNice = round(minNice - iv * pair[0], p);
          maxNice = round(maxNice + iv * pair[1], p);
          min = round(minNice - iv * t0, p);
          max = round(maxNice + iv * t1, p);
          if (min <= E[0] && max >= E[1]) return true;
        }
        return false;
      });
    }
  }
  return { t0, t1, seg, validExt: E, extent: [min, max], interval: iv, precision: p, intervalCount: seg,
    niceExtent: [minNice, maxNice], passes, exhausted };
}

// Interval#getTicks with intervalCount (Interval.ts:215-288), no breaks
function getTicks(extent, cfg) {
  const iv = cfg.interval, ne = cfg.niceExtent, p = cfg.precision;
  const cnt = M.noIntervalCount ? null : cfg.intervalCount;
  const ticks = [];
  if (!iv) return ticks;
  if (extent[0] < ne[0]) ticks.push(extent[0]);
  for (let tick = ne[0], k = 0; ; k++) {
    if (cnt == null) { if (tick > ne[1] || !isFinite(tick) || !isFinite(ne[1])) break; }
    else { if (k > cnt) break; tick = Math.min(tick, ne[1]); if (k === cnt) tick = ne[1]; }
    ticks.push(tick);
    tick = round(tick + iv, p);
    if (tick === ticks[ticks.length - 1]) break;
    if (ticks.length > 3000) return [];
  }
  const last = ticks.length ? ticks[ticks.length - 1] : ne[1];
  if (extent[1] > last) ticks.push(extent[1]);
  return ticks;
}
function addCommas(s) {
  const parts = (s + '').split('.');
  return parts[0].replace(/(\d{1,3})(?=(?:\d{3})+(?!\d))/g, '$1,') + (parts.length > 1 ? '.' + parts[1] : '');
}
const getLabel = v => addCommas(roundStr(v, getPrecision(v) || 0));   // Interval.ts:316-339

// Radar raw extent (RadarModel.ts:137-142 + scaleRawExtentInfo.ts:240-324)
function radarRaw(ind, dataVals, scaleOpt) {
  ind = Object.assign({}, ind);
  if (ind.max != null && ind.max > 0 && !ind.min) ind.min = 0;
  else if (ind.min != null && ind.min < 0 && !ind.max) ind.max = 0;
  let dlo = Infinity, dhi = -Infinity;
  dataVals.forEach(v => { if (v != null && isFinite(v)) { dlo = Math.min(dlo, v); dhi = Math.max(dhi, v); } });
  const eff = [ind.min != null ? Number(ind.min) : null, ind.max != null ? Number(ind.max) : null];
  let fix = [eff[0] != null, eff[1] != null];
  if (eff[0] == null) eff[0] = dlo;
  if (eff[1] == null) eff[1] = dhi;
  if (!isFinite(eff[0])) eff[0] = NaN;
  if (!isFinite(eff[1])) eff[1] = NaN;
  const incl0 = !scaleOpt;
  if (incl0) {
    if (eff[0] > 0 && eff[1] > 0 && !fix[0]) eff[0] = 0;
    if (eff[0] < 0 && eff[1] < 0 && !fix[1]) eff[1] = 0;
  }
  let inv = false;
  if (eff[0] > eff[1]) {
    eff.reverse();
    inv = true;
    if (M.flagsSwapped) fix = [fix[1], fix[0]];   // mutation
  }
  return { ext: eff, fix, incl0, inverse: inv };
}
function ensureValidSplitNumber(v, d) {      // scale/helper.ts:283-288
  v = Math.max(v || d, 1);
  if (M.bankers) {                           // mutation: FPC Round (half to even)
    const r = Math.round(v);
    return v - Math.floor(v) === 0.5 && r % 2 !== 0 ? r - 1 : r;
  }
  return Math.round(v);
}
const dummyTicks = n => Array.from({ length: n + 1 }, (_, i) => i);

// Axis#dataToCoord on a radar spoke: normalize then linearMap([0,1] -> [r0,r])
function spokeCoord(v, ext, r0, r) {
  const t = ext[1] === ext[0] ? 0.5 : (v - ext[0]) / (ext[1] - ext[0]);
  if (t === 0) return r0;
  if (t === 1) return r;
  return (t - 0) / 1 * (r - r0) + r0;
}

// Everything `out` holds, from `input` (plus, on radar, the spoke's [r0, r]).
function recompute(inp, spoke) {
  const ref = { ticks: inp.refTicks, expTicks: inp.refExpTicks, interval: inp.refInterval };
  const effLin = inp.isLog ? inp.effMM.map(v => Math.log(v) / Math.log(inp.base)) : inp.effMM;
  const r = scaleCalcAlign(ref, { ext: effLin, fix: inp.fix, incl0: inp.incl0, isLog: inp.isLog, base: inp.base, px: inp.px });
  const ticks = getTicks(r.extent, r);
  let outerExtent = null, outerTicks = null;
  if (inp.isLog) {
    // updateIntervalOrLogScaleForNiceOrAligned (axisHelper.ts:323-360) through the
    // lookup LogScale#setExtent left: from = log(effMM), to = effMM
    const outOf = v => (v === effLin[0] ? inp.effMM[0] : v === effLin[1] ? inp.effMM[1] : Math.pow(inp.base, v));
    outerExtent = r.extent.map(outOf);
    [0, 1].forEach(i => { if (inp.fix[i] && r.extent[i] === effLin[i]) outerExtent[i] = inp.effMM[i]; });
    // LogScale#getTicks: lookup from the new interval extent to the new outer extent
    outerTicks = ticks.map(t => (t === r.extent[0] ? outerExtent[0] : t === r.extent[1] ? outerExtent[1] : Math.pow(inp.base, t)));
  }
  const labels = (outerTicks || ticks).map(getLabel);
  const tickCoords = spoke ? ticks.map(t => spokeCoord(t, r.extent, spoke[0], spoke[1])) : null;
  return { t0: r.t0, t1: r.t1, seg: r.seg, validExt: r.validExt, extent: r.extent, outerExtent, interval: r.interval,
    intervalPrecision: r.precision, intervalCount: r.intervalCount, niceExtent: r.niceExtent, ticks, outerTicks, labels,
    tickCoords, passes: r.passes, exhausted: r.exhausted };
}

// ---------- running upstream ----------

// Grid#update wrapped once per build: the rect and every axis' pixel extent at
// its entry, i.e. what the align pass inside it reads.
const gridEntries = new Map();
function wrapGrid(lib) {
  const ch = lib.init(null, null, { renderer: 'svg', ssr: true, width: 100, height: 100 });
  let GP;
  try {
    ch.setOption({ xAxis: {}, yAxis: {}, series: [] });
    GP = Object.getPrototypeOf(ch.getModel().getComponent('grid').coordinateSystem);
  } finally {
    ch.dispose();
  }
  if (GP.__scaleAlignWrapped) return;
  const orig = GP.update;
  GP.update = function () {
    const list = gridEntries.get(this) || [];
    list.push({ rect: plainRect(this.getRect()), px: new Map(this._axesList.map(a => [a, a.getExtent().slice()])) });
    gridEntries.set(this, list);
    return orig.apply(this, arguments);
  };
  GP.__scaleAlignWrapped = true;
}

const axisName = a => a.dim + a.index;

// the split-line subpaths RadarView built (the merged paths with fill 'none')
function radarLinesDrawn(chart) {
  const view = chart._componentsViews.find(v => v && v.type === 'radar');
  must(view, 'no radar view');
  let n = 0;
  view.group.traverse(el => {
    if (el.type !== 'path' || !el.style || el.style.fill !== 'none') return;
    if (!el.path) el.createPathProxy();
    if (el.path.len() === 0) el.buildPath(el.path, el.shape, false);
    const nop = () => {};
    el.path.rebuildPath({ moveTo() { n++; }, lineTo: nop, arc: nop, closePath: nop, bezierCurveTo: nop,
      quadraticCurveTo: nop, rect: nop, ellipse: nop }, 1);
  });
  return n;
}

// The dataZoom window over an axis model: the first dataZoom whose targets
// include it (the axis has one proxy, whichever dataZoom hosts it).
function zoomWindowOf(ecModel, dim, index) {
  let win = null;
  ecModel.eachComponent('dataZoom', dz => {
    if (win) return;
    const proxy = dz.getAxisProxy(dim, index);
    if (proxy) {
      const w = proxy.getWindow();
      win = { percent: w.percent.slice(), value: w.value.slice() };
    }
  });
  return win;
}
// AxisProxy.ts reset: zoomMM i is set only for an end off 0% / 100%;
// makeFinal pins such an end (zoomFixMM i = true).
function zoomRule(percent, value) {
  const zoomMM = [null, null];
  if (percent) {
    if (percent[0] !== 0) zoomMM[0] = value[0];
    if (percent[1] !== 100) zoomMM[1] = value[1];
  }
  return { zoomMM, zoomFixMM: zoomMM.map(v => v != null) };
}
// axisAlignTicks.ts:161-165: either end zoom-pinned fixes both ends
const alignFix = (fixMM, zoomFixMM) => {
  const any = !M.zoomOneSided && (zoomFixMM[0] || zoomFixMM[1]);
  return [!!(fixMM[0] || any), !!(fixMM[1] || any)];
};

function readAxis(axis, extra, win) {
  const scale = axis.scale;
  const isLog = scale.type === 'log';
  const lin = isLog ? scale.intervalStub : scale;
  const cfg = lin.getConfig();
  const fin = scale.rawExtentInfo.makeFinal();
  return {
    input: {
      effMM: fin.effMM.slice(), fix: alignFix(fin.fixMM, fin.zoomFixMM), fixMM: fin.fixMM.map(b => !!b),
      zoomFixMM: fin.zoomFixMM.map(b => !!b), zoomPercent: win ? win.percent : null, zoomValue: win ? win.value : null,
      incl0: !!fin.incl0, isLog, base: isLog ? scale.base : 10, reversed: !!fin.tggAxInv,
    },
    up: {
      extent: lin.getExtent(), outerExtent: isLog ? scale.getExtent() : null, interval: cfg.interval,
      intervalPrecision: cfg.intervalPrecision, intervalCount: cfg.intervalCount, niceExtent: cfg.niceExtent ? cfg.niceExtent.slice() : null,
      ticks: lin.getTicks().map(t => t.value), outerTicks: isLog ? scale.getTicks().map(t => t.value) : null,
      labels: scale.getTicks().map(t => scale.getLabel(t)), inverse: !!axis.inverse,
    },
    extra,
  };
}

function run(c, lib) {
  gridEntries.clear();
  const chart = lib.init(null, null, { renderer: 'svg', ssr: true, width: c.canvas.w, height: c.canvas.h });
  try {
    const option = clone(c.option);
    option.animation = false;
    const written = clone(option);
    chart.setOption(option);
    chart.renderToSVGString();
    const ecModel = chart.getModel();
    const res = { option: written, axes: [] };
    if (c.kind === 'radar') {
      const rm = ecModel.getComponent('radar', 0);
      const radar = rm.coordinateSystem;
      const axes = radar.getIndicatorAxes();
      // the raw rule reads the option as written (the model's indicators may carry the pre-pass)
      const ro = written.radar;
      const inds = ro.indicator;
      const sn = ensureValidSplitNumber(rm.get('splitNumber'), 5);
      const rows = [];
      written.series.forEach(s => { if (s.type === 'radar') (s.data || []).forEach(d => rows.push(d.value)); });
      res.radar = { r0: radar.r0, r: radar.r, shape: rm.get('shape') === 'circle' ? 'circle' : 'polygon', linesDrawn: radarLinesDrawn(chart) };
      axes.forEach((ax, i) => {
        const a = readAxis(ax, null);
        const px = ax.getExtent();
        must(px[0] === radar.r0 && px[1] === radar.r, c.name + ': spoke ' + i + ' extent is not [r0, r]');
        a.path = 'radar0.i' + i;
        a.alignTo = 'dummy';
        a.input.px = Math.abs(px[1] - px[0]);
        a.input.splitNumber = sn;
        a.input.refTicks = dummyTicks(sn);
        a.input.refExpTicks = dummyTicks(sn);
        a.input.refInterval = 1;
        a.up.tickCoords = ax.getTicksCoords().map(t => t.coord);
        a.dataToCoord = a.up.ticks.map(t => ax.dataToCoord(t));
        a.spoke = [px[0], px[1]];
        a.ctx = { ind: inds[i], data: rows.map(r => (Array.isArray(r) ? r[i] : undefined)), scale: ro.scale, sn: ro.splitNumber };
        res.axes.push(a);
      });
      const tk = res.axes.map(a => a.up.ticks.length - 1);
      res.radar.ringCount = res.radar.shape === 'circle' ? tk[0] : Math.min(...tk);
    } else {
      const gm = ecModel.getComponent('grid', 0);
      const cs = gm.coordinateSystem;
      const entries = gridEntries.get(cs) || [];
      must(entries.length === 1, c.name + ': Grid#update ran ' + entries.length + ' times');
      const entry = entries[0];
      const optionRect = plainRect(lib.helper.getLayoutRect(gm.getBoxLayoutParams(), { width: c.canvas.w, height: c.canvas.h }));
      res.grid = { optionRect, entryRect: entry.rect, finalRect: plainRect(cs.getRect()), referenceAxes: [] };
      const all = cs.getAxes().slice().sort((a, b) => (a.dim === b.dim ? a.index - b.index : a.dim < b.dim ? -1 : 1));
      all.forEach(ax => {
        if (!ax.__alignTo) return;
        const ref = ax.__alignTo;
        const refLin = ref.scale.type === 'log' ? ref.scale.intervalStub : ref.scale;
        const a = readAxis(ax, null, zoomWindowOf(ecModel, ax.dim, ax.model.componentIndex));
        const ent = entry.px.get(ax);
        a.path = axisName(ax);
        a.alignTo = axisName(ref);
        if (!res.grid.referenceAxes.includes(a.alignTo)) res.grid.referenceAxes.push(a.alignTo);
        a.input.px = Math.abs(ent[1] - ent[0]);
        a.input.splitNumber = null;
        a.input.refTicks = refLin.getTicks().map(t => t.value);
        a.input.refExpTicks = refLin.getTicks({ expandToNicedExtent: true }).map(t => t.value);
        a.input.refInterval = refLin.getConfig().interval;
        a.up.tickCoords = null;
        a.pxFinal = Math.abs(ax.getExtent()[1] - ax.getExtent()[0]);
        a.optionSpan = ax.dim === 'x' ? optionRect.width : optionRect.height;
        a.expectInverse = !!ax.model.get('inverse') !== !!(a.input.reversed && !ecModel.get('legacyMinMaxDontInverseAxis'));
        res.axes.push(a);
      });
    }
    return res;
  } finally {
    chart.dispose();
  }
}

function runEither(c) {
  try {
    return Object.assign(run(c, echarts), { build: 'dev' });
  } catch (e) {
    if (e instanceof OracleError) throw e;
    return Object.assign(run(c, PROD), { build: 'prod', devError: String(e.message || e) });
  }
}

// ---------- cases ----------

const cases = [];
function add(c) {
  cases.push(Object.assign({ canvas: { w: 600, h: 400 } }, c));
}

// B: radar
function radar(name, indicator, rows, extra, more) {
  add(Object.assign({ name, kind: 'radar', scope: 'B',
    option: { radar: Object.assign({ indicator }, extra || {}), series: [{ type: 'radar', data: rows.map(v => ({ value: v })) }] } }, more || {}));
}
const V1 = [[4200, 3000, 20000, 35000, 50000, 18000], [5000, 14000, 28000, 26000, 42000, 21000]];
const IND_MAX = [{ name: 'Sales', max: 6500 }, { name: 'Admin', max: 16000 }, { name: 'IT', max: 30000 },
  { name: 'Support', max: 38000 }, { name: 'Dev', max: 52000 }, { name: 'Market', max: 25000 }];
radar('R1-52000-sn3', IND_MAX, V1, { splitNumber: 3 });
radar('R1-sn5', IND_MAX, V1, { splitNumber: 5 });
radar('R1-sn7', IND_MAX, V1, { splitNumber: 7 });
const IND_MM = [{ name: 'a', min: 10, max: 97 }, { name: 'b', min: -3, max: 7 }, { name: 'c', min: 0.1, max: 0.85 },
  { name: 'd', min: 1000, max: 1234 }, { name: 'e', min: -100, max: -7 }];
const V2 = [[50, 2, 0.5, 1100, -50]];
radar('R2-sn3', IND_MM, V2, { splitNumber: 3 });
radar('R2-sn5', IND_MM, V2, { splitNumber: 5 });
radar('R2-a-sn7', IND_MM, V2, { splitNumber: 7 });
radar('R2b-sn7-r180', IND_MM, V2, { splitNumber: 7, radius: 180 });
const IND_NONE = [{ name: 'p' }, { name: 'q' }, { name: 'r' }, { name: 's' }, { name: 't' }, { name: 'u' }];
const V3 = [[4300, 10000, 28000, 35000, 50000, 19000], [5000, 14000, 28000, 31000, 42000, 21000]];
[3, 5, 7].forEach(sn => radar('R3-sn' + sn, IND_NONE, V3, { splitNumber: sn }));
const V3b = [[1, 7, 0.37, 123, 999, 1.5]];
radar('R3b-7-sn3', IND_NONE, V3b, { splitNumber: 3 });
radar('R3b-sn5', IND_NONE, V3b, { splitNumber: 5 });
radar('R3b-sn7', IND_NONE, V3b, { splitNumber: 7 });
const V4 = [[-37, -5, -0.2, -1234, 12, -8], [-12, -83, -0.9, -300, -45, 30]];
[3, 5, 7].forEach(sn => radar('R4-sn' + sn, IND_NONE, V4, { splitNumber: sn }));
[3, 5].forEach(sn => radar('R4s-sn' + sn, IND_NONE, V4, { splitNumber: sn, scale: true }));
const IND_ONE = [{ name: 'minPos', min: 20 }, { name: 'minNeg', min: -50 }, { name: 'maxNeg', max: -10 },
  { name: 'maxZero', max: 0 }, { name: 'minZero', min: 0 }, { name: 'max0.5', max: 0.5 }];
const V5 = [[57, -13, -77, -3, 44, 0.12], [83, 12, -22, -40, 7, 0.31]];
[3, 5, 7].forEach(sn => radar('R5-sn' + sn, IND_ONE, V5, { splitNumber: sn }));
[3, 5, 7].forEach(sn => radar('R6-scale-sn' + sn, IND_NONE, V3, { splitNumber: sn, scale: true }));
radar('R-stale', [{ name: 'i0' }, { name: 'i1' }], [[3, 1], [7, 6]], { splitNumber: 2, scale: true });
radar('R-stale-sn3', [{ name: 'i0' }, { name: 'i1' }], [[1, 1], [2, 16]], { splitNumber: 3, scale: true });
radar('FLAT-BOTHFIX', [{ name: 'f', min: 50, max: 50 }], [[50]], { splitNumber: 5 });
radar('FLATscale', [{ name: 'f' }], [[50]], { splitNumber: 5, scale: true });
radar('FLAT-min50', [{ name: 'f', min: 50 }], [[50]], { splitNumber: 5 });
radar('R7-flat', IND_NONE.slice(0, 3), [[7, 7, 7]], {});
radar('R7-flat-scale', IND_NONE.slice(0, 3), [[7, 7, 7]], { scale: true });
radar('R7-zero', IND_NONE.slice(0, 3), [[0, 0, 0]], {});
radar('NODATA', IND_NONE.slice(0, 3), [], {});
radar('REV', [{ name: 'rv', min: 10, max: 5 }], [[7]], { splitNumber: 5 });
radar('REV-min3', [{ name: 'rv', min: 3 }], [[1]], { splitNumber: 5 });
radar('R8', [{ name: 'x', max: 50 }, { name: 'y', min: 10, max: 5 }, { name: 'z', min: 3 }], [[80, 7, 1]], {});
radar('SN0', IND_NONE.slice(0, 3), [[4, 9, 13]], { splitNumber: 0 });
radar('SN1', IND_NONE.slice(0, 3), [[4, 9, 13]], { splitNumber: 1 });
radar('SN2.5', IND_NONE.slice(0, 3), [[4, 9, 13]], { splitNumber: 2.5 });
radar('SN2.6', IND_NONE.slice(0, 3), [[4, 9, 13]], { splitNumber: 2.6 });
radar('SN-4', IND_NONE.slice(0, 3), [[4, 9, 13]], { splitNumber: -4 });
radar('LOG10-BOUNDARY', [{ name: 'a', max: 5000 }, { name: 'b', max: 50 }], [[1, 1]], { splitNumber: 5, radius: [0, 10000] });
radar('PX0', [{ name: 'a', max: 6500 }], [[1]], { splitNumber: 3, radius: [50, 50] });
radar('TINY', [{ name: 'a', min: 0, max: 1e-25 }, { name: 'b', max: 10 }], [[0, 1]], { splitNumber: 5 });
radar('HUGEOFF', [{ name: 'a', min: 1e6, max: 1e6 + 1e-9 }], [[1e6]], { splitNumber: 5 });
radar('BIGP', [{ name: 'a', min: 0.1, max: 0.1000003 }], [[0.1]], { splitNumber: 7 });
radar('SN1-MIXED', [{ name: 'a' }], [[-3], [7]], { splitNumber: 1 });
radar('SN1-MIXEDscale', [{ name: 'a' }], [[-3], [7]], { splitNumber: 1, scale: true });
radar('THOUSANDS', [{ name: 'a', max: 20000 }, { name: 'b', max: 1234567 }], [[1, 1]], { splitNumber: 5 });
const IND_P6 = [{ name: 'S', max: 6500 }, { name: 'A', max: 16000 }, { name: 'B', min: -50 }];
radar('P6-rings', IND_P6, [[4200, 3000, -13]], { splitNumber: 3 });
radar('CIRCLE', IND_P6, [[4200, 3000, -13]], { splitNumber: 3, shape: 'circle' });
radar('R-ring-r0', IND_P6, [[4200, 3000, -13]], { splitNumber: 3, radius: [40, 160] });

// C: cartesian alignTicks
const CAT = ['a', 'b', 'c', 'd', 'e', 'f'];
function cart(name, option, more) {
  add(Object.assign({ name, kind: 'cartesian', scope: 'C', option }, more || {}));
}
function dual(name, y0, y1, d0, d1, extra, more) {
  cart(name, Object.assign({
    xAxis: { type: 'category', data: CAT.slice(0, Math.max(d0.length, d1.length)) },
    yAxis: [Object.assign({ type: 'value' }, y0), Object.assign({ type: 'value' }, y1)],
    series: [{ type: 'line', data: d0, yAxisIndex: 0 }, { type: 'line', data: d1, yAxisIndex: 1 }],
  }, extra || {}), more);
}
const R4V = [10, 250, 120, 80];
const R3V = [10, 90, 50, 40];
const T1 = [1, 23.7, 12, 5];
dual('A1', {}, { alignTicks: true }, R4V, T1);
dual('A2', {}, { alignTicks: true }, R4V, [1, 171, 12, 5]);
dual('A3', {}, { alignTicks: true }, [10, 1200, 120, 80], [0.001, 0.037, 0.02, 0.01]);
dual('A4', {}, { alignTicks: true }, R4V, [-13, 41, 12, 5]);
dual('A4b', {}, { alignTicks: true }, R4V, [-41, 13, 12, 5]);
dual('A5', {}, { alignTicks: true }, R4V, [-3, -77, -12, -50]);
dual('A6', {}, { alignTicks: true }, [-30, 90, 12, 50], [1, 7, 2, 3]);
dual('A7', {}, { alignTicks: true, scale: true }, R4V, [103, 147, 120, 110]);
dual('A7b', {}, { alignTicks: true, scale: true }, [0, 6, 3, 2], [1003, 1047, 1020, 1010]);
dual('A7c', {}, { alignTicks: true, scale: true }, [0, 120, 3, 2], [0.5, 0.53, 0.51, 0.52]);
dual('B1', { min: 3, max: 97 }, { alignTicks: true }, R3V, T1);
dual('B2', { max: 97 }, { alignTicks: true }, R3V, T1);
dual('B3', { min: 3 }, { alignTicks: true }, R3V, T1);
dual('B4', { min: 0, max: 5, splitNumber: 1 }, { alignTicks: true }, [1, 4], [1, 23.7]);
dual('B5', { min: 0, max: 13, splitNumber: 1 }, { alignTicks: true }, [1, 12], [1, 23.7]);
dual('B6', { min: -3, max: 10, splitNumber: 1 }, { alignTicks: true }, [1, 9], [1, 23.7]);
dual('B7', { min: 0, max: 20, splitNumber: 2 }, { alignTicks: true }, [1, 19], [1, 23.7]);
dual('C1', {}, { alignTicks: true, min: 0, max: 30 }, R4V, T1);
dual('C2', {}, { alignTicks: true, min: 0, max: 7 }, R4V, [1, 6.7, 2, 5]);
dual('C3', {}, { alignTicks: true, min: 3.3, max: 17.9 }, R4V, [4, 16, 12, 5]);
dual('C4', {}, { alignTicks: true, min: 5 }, R4V, [6, 23.7, 12, 7]);
dual('C5', {}, { alignTicks: true, max: 30 }, R4V, T1);
dual('C6', { min: 3, max: 97 }, { alignTicks: true, min: -1, max: 30 }, R3V, T1);
dual('C7', {}, { alignTicks: true, min: 'dataMin' }, R4V, [4.2, 23.7, 12, 5]);
dual('C8', { min: 3, max: 97 }, { alignTicks: true, min: 0 }, R3V, T1);
dual('C9', { min: 3, max: 97 }, { alignTicks: true, max: 30 }, R3V, T1);
dual('C10', { min: 3, max: 97 }, { alignTicks: true }, R3V, [-4, 23.7, 12, 5]);
dual('D1', { type: 'log' }, { type: 'log', alignTicks: true }, [1, 1000, 30, 5], [2, 170, 20, 5]);
dual('D2', {}, { type: 'log', alignTicks: true }, R4V, [2, 17000, 20, 5]);
dual('D3', { type: 'log' }, { alignTicks: true }, [1, 100000, 30, 5], T1);
dual('D4', { type: 'log' }, { type: 'log', logBase: 2, alignTicks: true }, [1, 1000, 30, 5], [1, 300, 20, 5]);
dual('D5', {}, { type: 'log', alignTicks: true, min: 1, max: 1000 }, R4V, [2, 170, 20, 5]);
dual('D6', {}, { type: 'log', alignTicks: true }, R4V, [0.002, 0.3, 0.02, 0.05]);
// the self-check 4 discriminators the p2 set lacks (A1 and C6 do not bite): a
// reference with t0 = t1 = 0.85 (3..97: seg 3), so an interval below span/seg
// can still cover the target
dual('NR-min0', { min: 3, max: 97 }, { alignTicks: true, min: 0 }, R3V, [1, 4.5, 2, 3],
  null, { note: 'min fixed, span/seg 1.5: NICE_MODE_MIN starts at 1, which covers ([0, 4.7]); NICE_MODE_ROUND would start at 2' });
dual('NR-neither', { min: 3, max: 97 }, { alignTicks: true }, R3V, [-3, 4.5, 1, 2],
  null, { note: 'neither end fixed: interval 2 covers; NICE_MODE_ROUND would start at 3' });
dual('RIV', { min: 3, max: 97 }, { alignTicks: true, min: -3, max: 1.5 }, R3V, [-2, 1, 0, 1],
  null, { note: 'both fixed, t0 = t1 = 0.85, p 3: minNice from the UNROUNDED interval is -2.186 (rounded: -2.187)' });
dual('RIV-small', { min: 3, max: 97 }, { alignTicks: true, min: -1, max: 1 }, R3V, [-0.5, 0.5, 0, 0.2],
  null, { canvas: { w: 600, h: 150 }, note: 'both fixed at px 5, p 1: niceExtent [-0.6, 0.6] (rounded interval: [-0.7, 0.7])' });
// Port mutation guards (batch 48): whether zero is included matters only when
// the data touches zero -- scale:true must NOT include it; and a fixed log end
// that did not move keeps the value it came in as, not 10^log10(v).
radar('R-scale-zero-sn3', [{ name: 'z' }], [[0], [8]], { splitNumber: 3, scale: true });
dual('Z0-scale', {}, { alignTicks: true, scale: true }, R4V, [0, 8, 3, 5],
  null, { note: 'scale:true target touching zero: an odd spare segment is centred, not all put above zero' });
dual('D7-logmin3', {}, { type: 'log', alignTicks: true, min: 3 }, R4V, [4, 170, 20, 5],
  null, { note: 'log target fixed at 3: the low end stays 3, not 10^log10(3)' });
function three(name, yAxis, note) {
  cart(name, {
    xAxis: { type: 'category', data: CAT.slice(0, 4) }, yAxis,
    series: [{ type: 'line', data: R4V }, { type: 'line', yAxisIndex: 1, data: T1 }, { type: 'line', yAxisIndex: 2, data: [0.3, 7, 2, 1] }],
  }, note ? { note } : undefined);
}
three('E1', [{ type: 'value' }, { type: 'value', alignTicks: true }, { type: 'value', alignTicks: true }], 'y0 plain: y1 and y2 align to it');
three('E2', [{ type: 'value', alignTicks: true }, { type: 'value', alignTicks: true }, { type: 'value', alignTicks: true }],
  'every axis asks: the first (y0) is the reference');
three('E3', [{ type: 'value', alignTicks: true }, { type: 'value' }, { type: 'value' }],
  'the lowest-index plain axis (y1) is the reference');
cart('E4', {
  xAxis: { type: 'category', data: CAT.slice(0, 4) },
  yAxis: [{ type: 'value', alignTicks: true }, { type: 'value', alignTicks: true, interval: 4 }],
  series: [{ type: 'line', data: R4V }, { type: 'line', yAxisIndex: 1, data: T1 }],
}, { note: 'an axis with an interval never aligns and becomes the reference' });
cart('E6', {
  yAxis: { type: 'category', data: CAT.slice(0, 4) },
  xAxis: [{ type: 'value' }, { type: 'value', alignTicks: true }],
  series: [{ type: 'bar', data: R4V }, { type: 'bar', xAxisIndex: 1, data: T1 }],
}, { note: 'horizontal: x1 aligns to x0, px is the option rect width' });
cart('E7', {
  xAxis: [{ type: 'category', data: CAT.slice(0, 4) }, { type: 'value', alignTicks: true }],
  yAxis: { type: 'value' },
  series: [{ type: 'line', data: R4V }],
}, { note: 'the only other x axis is a category axis: nothing aligns (axes [])' });
cart('E8', {
  xAxis: { type: 'category', data: CAT.slice(0, 4) },
  yAxis: [{ type: 'time' }, { type: 'value', alignTicks: true }],
  series: [{ type: 'line', data: [1e12, 1.1e12, 1.2e12, 1.3e12] }, { type: 'line', yAxisIndex: 1, data: T1 }],
}, { note: 'a time axis is never a reference: nothing aligns (axes [])' });
cart('E9', {
  xAxis: { type: 'category', data: CAT.slice(0, 4) },
  yAxis: [{ type: 'value', splitNumber: 3 }, { type: 'value', alignTicks: true }],
  series: [{ type: 'line', data: R4V }, { type: 'line', yAxisIndex: 1, data: T1 }],
});
function zoomed(name, start, end, note) {
  cart(name, {
    xAxis: { type: 'category', data: CAT.slice(0, 4) },
    yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true }],
    dataZoom: [{ type: 'inside', yAxisIndex: [0, 1], start, end }],
    series: [{ type: 'line', data: R4V }, { type: 'line', yAxisIndex: 1, data: T1 }],
  }, { note });
}
zoomed('E10', 10, 90, 'dataZoom pins both ends (zoomFixMM) at the window values: the both-fixed branch (audit SS4)');
zoomed('E10b', 0, 90, 'dataZoom pins the max end only, and that fixes BOTH ends for the align (axisAlignTicks.ts:161-165): the both-fixed branch from [0, 21.33]');
zoomed('E10c', 10, 100, 'dataZoom pins the min end only, and that fixes BOTH ends for the align: the both-fixed branch');
cart('E12', {
  xAxis: { type: 'category', data: CAT.slice(0, 4) },
  yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true, scale: true }],
  series: [{ type: 'line', data: R4V }, { type: 'line', yAxisIndex: 1, data: [7, 7, 7, 7] }],
});
function dualRef(name, ref, tData) {
  cart(name, {
    xAxis: { type: 'category', data: ['a', 'b'] },
    yAxis: [Object.assign({ type: 'value' }, ref), { type: 'value', alignTicks: true, scale: true }],
    series: [{ type: 'line', data: [1, 2] }, { type: 'line', yAxisIndex: 1, data: tData }],
  });
}
dualRef('S1', { min: 0, max: 20, splitNumber: 2 }, [3, 7]);
dualRef('S2', { min: 0, max: 20, splitNumber: 2 }, [1, 6]);
dualRef('S3', { min: 0, max: 30, splitNumber: 3 }, [1, 2]);
dualRef('S4', { min: 0, max: 30, splitNumber: 3 }, [1, 16]);
function pxcase(name, canvas, grid, note) {
  cart(name, Object.assign(grid ? { grid } : {}, {
    xAxis: { type: 'category', data: ['a', 'b'] },
    yAxis: [{}, { alignTicks: true, min: 0, max: 7.123 }],
    series: [{ type: 'line', data: [10, 250] }, { type: 'line', yAxisIndex: 1, data: [1, 2] }],
  }), { canvas, note });
}
pxcase('PX-255', { w: 600, h: 400 }, null, 'both ends fixed: the precision reads the pixel span');
pxcase('OB-74', { w: 600, h: 400 }, { top: 60, bottom: 60, outerBounds: { top: 150, bottom: 150 } },
  'final px 74 but the align pass saw the option rect (280): p 3, not 2');
pxcase('SMALL-150', { w: 600, h: 150 }, null, 'a 600x150 canvas: px 5, p 1');
cart('SV-lo', {
  xAxis: { type: 'category', data: CAT.slice(0, 4) },
  yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true, scale: true, startValue: 2 }],
  series: [{ type: 'bar', data: R4V }, { type: 'bar', yAxisIndex: 1, data: [5, 23.7, 12, 8] }],
}, { note: 'a written startValue below the data fixes the min end (C10): the min-fixed branch' });
cart('SV-hi', {
  xAxis: { type: 'category', data: CAT.slice(0, 4) },
  yAxis: [{ type: 'value' }, { type: 'value', alignTicks: true, scale: true, startValue: -1 }],
  series: [{ type: 'bar', data: R4V }, { type: 'bar', yAxisIndex: 1, data: [-5, -23.7, -12, -8] }],
}, { note: 'a written startValue above the data fixes the max end (C10): the max-fixed branch' });

// self-check 4: each mutation and the case it must change
const GUARDS = [
  ['freshCentring', ['S1', 'S3', 'S4', 'R-stale'], 'min/max read fresh per pass instead of carried from the last pass that wrote them'],
  ['log10', ['LOG10-BOUNDARY'], 'Math.log10 in place of log(x)/LN10'],
  ['bankers', ['SN2.5'], 'splitNumber rounded half to even (FPC Round)'],
  ['noIntervalCount', ['R1-52000-sn3'], 'getTicks without the intervalCount branch'],
  ['inc125', ['R3b-7-sn3'], 'increaseInterval stepping 1-2-5'],
  ['niceRound', ['NR-min0'], 'NICE_MODE_ROUND in place of NICE_MODE_MIN for the first interval (the audit named A1, which does not bite)'],
  ['roundedIvForNice', ['RIV'], 'both fixed: the rounded interval used for minNice/maxNice (the audit named C6, which does not bite)'],
  ['flagsSwapped', ['REV-min3'], 'the fix flags swapped together with the reversed values'],
  ['flatBoth', ['FLAT-BOTHFIX'], 'a flat extent opened both ways although max is fixed'],
  ['px0NaN', ['PX0'], 'pixel span 0 gives precision NaN'],
  ['clampStored', ['TINY'], 'intervalPrecision clamped to 0..20 when stored'],
  ['noExtraInc', ['SN1-MIXED'], 'no increaseInterval after the 50th failed pass'],
  ['finalPx', ['OB-74'], 'the final (outerBounds) pixel span in place of the option rect'],
  ['devicePx', ['R2-a-sn7'], 'device pixels (x1.5, PPI 144) in place of CSS pixels'],
  ['zoomOneSided', ['E10b', 'E10c'], 'a dataZoom pin fixes only its own end (not both) for the align'],
];

// ---------- run, check and write ----------

{
  const names = new Set();
  for (const c of cases) { must(!names.has(c.name), 'two cases named ' + c.name); names.add(c.name); }
  const fin = v => typeof v !== 'number' || !isFinite(v) || Math.abs(v) < 9223372036854775808;
  const walk = v => (v && typeof v === 'object' ? Object.values(v).every(walk) : fin(v));
  cases.forEach(c => must(walk(c.option), c.name + ': an option number >= 2^63 (the Pascal reader misparses it)'));
}
wrapGrid(echarts);
wrapGrid(PROD);

const UP_FIELDS = ['extent', 'outerExtent', 'interval', 'intervalPrecision', 'intervalCount', 'niceExtent', 'ticks', 'outerTicks', 'labels', 'tickCoords'];
function diffFields(a, b) {
  const bad = [];
  UP_FIELDS.forEach(k => {
    const x = a[k], y = b[k];
    const ok = Array.isArray(x) || Array.isArray(y)
      ? (x == null && y == null) || (x != null && y != null && x.length === y.length && x.every((v, i) => (typeof v === 'string' ? v === y[i] : same(v, y[i]))))
      : same(x, y);
    if (!ok) bad.push(k + ' ' + JSON.stringify(x) + ' vs ' + JSON.stringify(y));
  });
  return bad;
}

// The recompute a mutation is judged by: radar from the OPTION (raw rule and
// splitNumber included), cartesian from `input` (px swapped for finalPx).
function mutatedOut(a, kind) {
  if (kind === 'radar') {
    const n = ensureValidSplitNumber(a.ctx.sn, 5);
    const raw = radarRaw(a.ctx.ind, a.ctx.data, a.ctx.scale);
    const inp = Object.assign({}, a.input, { effMM: raw.ext, fix: raw.fix, incl0: raw.incl0, splitNumber: n,
      refTicks: dummyTicks(n), refExpTicks: dummyTicks(n), px: M.devicePx ? a.input.px * 1.5 : a.input.px });
    return recompute(inp, a.spoke);
  }
  let px = a.input.px;
  if (M.finalPx) px = a.pxFinal;
  if (M.devicePx) px *= 1.5;
  return recompute(Object.assign({}, a.input, { px, fix: alignFix(a.input.fixMM, a.input.zoomFixMM) }), null);
}

function generate() {
  const tally = { 1: [0, 0], 2: [0, 0], 3: [0, 0] };
  const failed = [];
  const runs = cases.map(c => {
    let r;
    try { r = runEither(c); } catch (e) { if (e instanceof OracleError) e.message = c.name + ': ' + e.message; throw e; }
    return r;
  });
  const recs = cases.map((c, ci) => {
    const r = runs[ci];
    const fails = { 1: [], 2: [], 3: [] };
    const rec = { name: c.name, kind: c.kind, scope: c.scope, canvas: c.canvas, option: r.option, build: r.build };
    if (r.devError) rec.devError = r.devError;
    rec.documentary = !!c.documentary;
    if (c.note) rec.note = c.note;
    if (c.kind === 'radar') {
      const rd = r.radar;
      rec.radar = { r0: hex(rd.r0), r: hex(rd.r), r0Text: text(rd.r0), rText: text(rd.r), shape: rd.shape, ringCount: rd.ringCount, linesDrawn: rd.linesDrawn };
      if (rd.linesDrawn !== rd.ringCount + 1) fails[3].push('linesDrawn ' + rd.linesDrawn + ' != ringCount + 1 (' + (rd.ringCount + 1) + ')');
    } else {
      const g = r.grid;
      if (!RECT.every(k => same(g.optionRect[k], g.entryRect[k]))) fails[1].push('Grid#update started from ' + JSON.stringify(g.entryRect) + ', not the option rect');
      rec.grid = { optionRect: hexRect(g.optionRect), optionRectText: textRect(g.optionRect), finalRect: hexRect(g.finalRect),
        finalRectText: textRect(g.finalRect), referenceAxes: g.referenceAxes };
    }
    rec.axes = r.axes.map(a => {
      const f1 = [], f2 = [], f3 = [];
      const mine = recompute(a.input, c.kind === 'radar' ? a.spoke : null);
      const up = a.up;
      // 1: the recipe from input reproduces upstream
      diffFields(mine, up).forEach(d => f1.push(a.path + ': ' + d));
      if (up.intervalCount !== mine.seg) f1.push(a.path + ': intervalCount ' + up.intervalCount + ' != seg ' + mine.seg);
      if (c.kind === 'radar') {
        const raw = radarRaw(a.ctx.ind, a.ctx.data, a.ctx.scale);
        if (!sameArr(raw.ext, a.input.effMM) || raw.fix[0] !== a.input.fix[0] || raw.fix[1] !== a.input.fix[1] || raw.incl0 !== a.input.incl0)
          f1.push(a.path + ': the raw rule gives ' + JSON.stringify(raw) + ', makeFinal ' + JSON.stringify(a.input));
        if (raw.inverse !== up.inverse || raw.inverse !== a.input.reversed) f1.push(a.path + ': inverse ' + up.inverse + ' vs raw rule ' + raw.inverse);
        const viaOpt = mutatedOut(a, 'radar');
        diffFields(viaOpt, up).forEach(d => f1.push(a.path + ' (from the option): ' + d));
        if (!sameArr(a.dataToCoord, up.tickCoords)) f1.push(a.path + ': getTicksCoords != dataToCoord of the ticks');
      } else {
        if (!same(a.input.px, a.optionSpan)) f1.push(a.path + ': align px ' + a.input.px + ' != option rect span ' + a.optionSpan);
        if (a.expectInverse !== up.inverse) f1.push(a.path + ': inverse ' + up.inverse + ' != option xor reversed');
        // the zoom rule: zoomFixMM from the window, pinned ends at its values
        const z = zoomRule(a.input.zoomPercent, a.input.zoomValue);
        if (!sameArr(z.zoomFixMM.map(Number), a.input.zoomFixMM.map(Number)))
          f1.push(a.path + ': zoomFixMM ' + JSON.stringify(a.input.zoomFixMM) + ', the zoom rule gives ' + JSON.stringify(z.zoomFixMM));
        [0, 1].forEach(i => {
          if (z.zoomMM[i] != null && !same(z.zoomMM[i], a.input.effMM[i]))
            f1.push(a.path + ': pinned effMM ' + i + ' is ' + a.input.effMM[i] + ', the window gives ' + z.zoomMM[i]);
          if (z.zoomFixMM[i] && !a.input.fixMM[i]) f1.push(a.path + ': zoom-pinned end ' + i + ' is not in fixMM');
        });
      }
      // 3: invariants
      if (up.interval === 0) {
        if (up.ticks.length) f3.push(a.path + ': interval 0 but ' + up.ticks.length + ' ticks');
      } else {
        const ne = up.niceExtent, ext = up.extent, tk = up.ticks;
        // the counted loop ends on ne1 (k === count), so `last` is ne1
        const want = up.intervalCount + 1 + (ext[0] < ne[0] ? 1 : 0) + (ext[1] > ne[1] ? 1 : 0);
        if (tk.length !== want) f3.push(a.path + ': ' + tk.length + ' ticks, want ' + want);
      }
      if (c.kind === 'radar' && up.intervalCount !== a.input.splitNumber) f3.push(a.path + ': intervalCount ' + up.intervalCount + ' != splitNumber ' + a.input.splitNumber);
      if (!mine.exhausted && !(up.extent[0] <= mine.validExt[0] && up.extent[1] >= mine.validExt[1]))
        f3.push(a.path + ': extent ' + JSON.stringify(up.extent) + ' does not contain ' + JSON.stringify(mine.validExt));
      // the record
      const inp = a.input;
      const o = {
        path: a.path, alignTo: a.alignTo,
        input: { effMM: hexArr(inp.effMM), fix: inp.fix, fixMM: inp.fixMM, zoomFixMM: inp.zoomFixMM,
          zoomPercent: hexArr(inp.zoomPercent), zoomValue: hexArr(inp.zoomValue), incl0: inp.incl0, isLog: inp.isLog, base: hex(inp.base), reversed: inp.reversed,
          px: hex(inp.px), splitNumber: inp.splitNumber, refTicks: hexArr(inp.refTicks), refExpTicks: hexArr(inp.refExpTicks), refInterval: hex(inp.refInterval) },
        out: { t0: hex(mine.t0), t1: hex(mine.t1), seg: mine.seg, validExt: hexArr(mine.validExt), extent: hexArr(up.extent), outerExtent: hexArr(up.outerExtent),
          interval: hex(up.interval), intervalPrecision: isNaN(up.intervalPrecision) ? null : hex(up.intervalPrecision), intervalCount: up.intervalCount,
          niceExtent: hexArr(up.niceExtent), ticks: hexArr(up.ticks), outerTicks: hexArr(up.outerTicks), labels: up.labels, tickCoords: hexArr(up.tickCoords),
          passes: mine.passes, exhausted: mine.exhausted, inverse: up.inverse },
      };
      if (c.kind === 'cartesian') o.pxFinal = hex(a.pxFinal);
      o.text = { effMM: textArr(inp.effMM), zoomPercent: textArr(inp.zoomPercent), zoomValue: textArr(inp.zoomValue), px: text(inp.px), base: text(inp.base), refInterval: text(inp.refInterval), t0: text(mine.t0), t1: text(mine.t1),
        validExt: textArr(mine.validExt), extent: textArr(up.extent), outerExtent: textArr(up.outerExtent), interval: text(up.interval),
        intervalPrecision: text(up.intervalPrecision), niceExtent: textArr(up.niceExtent), ticks: textArr(up.ticks), outerTicks: textArr(up.outerTicks),
        tickCoords: textArr(up.tickCoords) };
      if (c.kind === 'cartesian') o.text.pxFinal = text(a.pxFinal);
      // 2: every twin parses back to the bits beside it
      const pairs = [[o.input.effMM, o.text.effMM], [o.input.zoomPercent, o.text.zoomPercent], [o.input.zoomValue, o.text.zoomValue], [o.input.px, o.text.px], [o.input.base, o.text.base], [o.input.refInterval, o.text.refInterval],
        [o.out.t0, o.text.t0], [o.out.t1, o.text.t1], [o.out.validExt, o.text.validExt], [o.out.extent, o.text.extent],
        [o.out.outerExtent, o.text.outerExtent], [o.out.interval, o.text.interval], [o.out.niceExtent, o.text.niceExtent],
        [o.out.ticks, o.text.ticks], [o.out.outerTicks, o.text.outerTicks], [o.out.tickCoords, o.text.tickCoords]];
      if (o.pxFinal) pairs.push([o.pxFinal, o.text.pxFinal]);
      pairs.forEach(([h, t]) => {
        const hs = Array.isArray(h) ? h : [h], ts = Array.isArray(t) ? t : [t];
        if (h == null && t == null) return;
        if (h == null || t == null || hs.length !== ts.length) { f2.push(a.path + ': twin shape'); return; }
        hs.forEach((x, i) => { if (hex(parseFloat(ts[i])) !== x) f2.push(a.path + ': ' + ts[i] + ' is not ' + x); });
      });
      if (o.out.intervalPrecision == null ? o.text.intervalPrecision !== 'NaN' : hex(parseFloat(o.text.intervalPrecision)) !== o.out.intervalPrecision)
        f2.push(a.path + ': intervalPrecision twin');
      fails[1].push(...f1);
      fails[2].push(...f2);
      fails[3].push(...f3);
      return o;
    });
    [1, 2, 3].forEach(k => { tally[k][fails[k].length ? 1 : 0]++; });
    const miss = [1, 2, 3].filter(k => fails[k].length).map(k => 'self-check ' + k + ': ' + fails[k].slice(0, 3).join('; ')
      + (fails[k].length > 3 ? ' (+' + (fails[k].length - 3) + ' more)' : '')).join(' | ');
    if (miss && !c.deferred) failed.push(c.name + ': ' + miss);
    if (c.deferred) {
      rec.deferred = true;
      rec.why = c.deferred + (miss ? '; first differences: ' + miss : '; (no self-check failed)');
    } else rec.deferred = false;
    return rec;
  });

  // 4: guards, over the compared (not deferred, not documentary) cases
  const guards = GUARDS.map(([mutation, named, what]) => {
    M = { [mutation]: true };
    const changed = [];
    try {
      cases.forEach((c, ci) => {
        if (c.deferred || c.documentary) return;
        const hit = runs[ci].axes.some(a => diffFields(mutatedOut(a, c.kind), a.up).length > 0);
        if (hit) changed.push(c.name);
      });
    } finally {
      M = {};
    }
    return { mutation, what, named, changed, ok: named.some(n => changed.includes(n)) };
  });
  const out = {
    source: 'ECharts ' + echarts.version,
    checks: null,
    guards: guards.map(g => ({ mutation: g.mutation, what: g.what, named: g.named, changed: g.changed })),
    cases: recs,
  };
  return { out, tally, failed, guards };
}

// the compact writer of roam.js
const LINE = 250;
function oneLine(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(oneLine).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).map(k => JSON.stringify(k) + ':' + oneLine(v[k])).join(',') + '}';
}
function fmt(v, ind) {
  const flat = oneLine(v);
  if (flat.length + ind.length <= LINE || v === null || typeof v !== 'object') return flat;
  const inner = ind + ' ';
  if (Array.isArray(v)) {
    const items = v.map(x => fmt(x, inner));
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
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n')
    + '\n' + ind + '}';
}
const CHECKS = [1, 2, 3];
const tallyText = t => CHECKS.map(k => k + ' ' + t[k][0] + '/' + (t[k][0] + t[k][1])).join(', ');

let g1, json1;
try {
  g1 = generate();
  g1.out.checks = tallyText(g1.tally) + ', 4 ' + g1.guards.filter(g => g.ok).length + '/' + g1.guards.length;
  json1 = fmt(g1.out, '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  process.exit(1);
}
// self-check d
const g2 = generate();
g2.out.checks = tallyText(g2.tally) + ', 4 ' + g2.guards.filter(g => g.ok).length + '/' + g2.guards.length;
const deterministic = json1 === fmt(g2.out, '') + '\n';

const { tally, failed, guards } = g1;
failed.forEach(f => console.log('self-check failed: ' + f));
const badGuards = guards.filter(g => !g.ok);
guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.mutation + ': named ' + g.named.join('/') + '; changes '
  + g.changed.length + ' case(s): ' + g.changed.join(', ')));
console.log('self-checks (pass/cases): ' + tallyText(tally) + ', 4 ' + (guards.length - badGuards.length) + '/' + guards.length
  + ', d ' + (deterministic ? 'identical' : 'DIFFERENT'));
const cs = g1.out.cases;
const prod = cs.filter(c => c.build === 'prod').map(c => c.name);
if (prod.length) console.log('through the production build: ' + prod.join(', '));
const count = k => cs.filter(c => c.scope === k).length;
const nAxes = cs.reduce((n, c) => n + c.axes.length, 0);
const nDef = cs.filter(c => c.deferred).length;
console.log('scope B ' + count('B') + ', C ' + count('C') + ', out ' + count('out') + ' cases (' + nDef + ' deferred); '
  + nAxes + ' aligned axes; ' + json1.length + ' bytes');
if (failed.length || badGuards.length || !deterministic) {
  if (process.env.ORACLE_REJECTS) fs.writeFileSync(process.env.ORACLE_REJECTS, json1);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
