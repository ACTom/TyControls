// Upstream's own answers for ANIMATION (batches AN1-AN4): the zrender easing
// functions and cubic-bezier easings sampled bit-exactly, and the per-frame
// state of every element of small charts while their enter / update / leave
// animations run (wf86/anim.md is the prose).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist by default, or
// ECHARTS_DIST) in node with a CONTROLLED CLOCK, and reads the zrender elements
// directly after every frame, never the SVG.
//
//   node tools/advchart-oracle/animation.js
//
// writes tests/fixtures/advchart-animation.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Browser behaviour under node: two switches
//   ssr    echarts.init(null, null, {renderer: 'svg', ssr: true}) is the only
//          DOM-less way in; right after init the instance's _ssr is set back
//          to false, BEFORE the first setOption. Reason: ecModel.ssr (copied
//          from chart._ssr when the GlobalModel is created, echarts.ts:773)
//          changes the animation itself -- PieView.ts:81 swaps every pie
//          enter animation for a scaleX/scaleY 0 -> 1 "from" animation, and
//          LineView.ts:653 `hasAnimation = !ecModel.ssr && ...` drops the line
//          update animation. With _ssr false, setOption also ends with the
//          browser's synchronous zr.flush() (echarts.ts:809), whose
//          animation.update(true) is the t = 0 step below. The SSR SVG painter
//          has no root, so its refresh() is a no-op.
//   env.node  the dist sets env.node = true under node; Series.ts:552 then
//          refuses animation unless ssr, Model.ts:205 (every COMPONENT model:
//          axes, legend ...) and MarkerModel.isAnimationEnabled refuse it
//          outright. The script sets echarts.env.node = false after loading.
//          Other runtime readers: the zrender handler proxy (off under the ssr
//          init anyway), the hover layer (> 3000 elements), axisPointer's
//          global listeners and the tooltip view (also needs a DOM, bails).
//          `envNodeFlipped` records it.
//
// The clock
//   zrender's only time source is animation/Animation.ts getTime() =
//   `new Date().getTime()` (dist: `function getTime() { return new
//   Date().getTime(); }`); Clip.step gets its globalTime from
//   Animation.update, which reads getTime(). The global Date is replaced
//   BEFORE the dist is loaded by a subclass whose zero-argument constructor
//   (and Date.now) returns the variable NOW; every other Date form is the
//   real one. The frame loop (requestAnimationFrame = setTimeout(16) under
//   node) never runs: the script is synchronous and ends with process.exit.
//   Frames:
//     t = 0   setOption at NOW = T0; its closing zr.flush() runs
//             animation.update(true) at T0 (zrender.ts _refresh). That step is
//             where every new Clip takes its start time: Clip.step sets
//             _startTime = globalTime + delay on its FIRST step, so t = 0 is
//             "the frame setOption flushed", not the animateTo call. The
//             script asserts every clip was stepped and reads.
//     t > 0   NOW = T0 + t; zr.animation.update() (a normal rAF frame: clips
//             step, then 'frame' fires; stage.update is null under the ssr
//             init).
//   After every step zr.storage.getDisplayList(true) runs the painter's
//   pre-paint pass (el.update(): transforms, label textContent placement), so
//   derived state is what a painted frame would show.
//
// ---------------------------------------------------------------------------
// Conventions (as line-smooth.js)
//   hex   a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//         lowercase (NaN 7ff8000000000000). Every hex has a readable twin
//         (String(v), '-0' for negative zero).
//   fn    an option value that is a JS function is written {"$fn": NAME}; the
//         port maps NAME to a named handler: 'idx*50' (idx) => idx * 50,
//         'idx*30' (idx) => idx * 30, 'dur:600+idx*100' (idx) => 600 + idx*100.
//
// Top level
//   source, dist, W, H, seed, envNodeFlipped, clock{...}, samplesMs[], notes[]
//   easings
//     ts[] / tsText[]       the sample points: k/64 for k = 0..64, then edges
//                           (tsNote says which are outside the clip domain
//                           [0, 1] -- Clip.step clamps percent to [0, 1]
//                           before easing, so those are the functions alone)
//     names[]               the 31 easing names of zrender animation/easing.ts
//     table[]  {name, kind: 'named' | 'cubic-bezier' | 'unknown',
//              resolved: true when Clip.setEasing found a function (false: the
//              clip runs with NO easing, i.e. linear -- an unknown name, or a
//              cubic-bezier the regexp /cubic-bezier\(([0-9,\.e ]+)\)/ rejects,
//              e.g. a negative control value), values[] hex, valuesText[]}.
//              Each function is the dist's own: the easingFunc of a real Clip
//              (animator.start(name).getClip().easingFunc).
//   cases[]  one per chart run:
//     id, kind ('enter' | 'update' | 'threshold'), chart (the chart family),
//     variant, note, option (as fed to setOption, functions as {"$fn"}),
//     next (update cases: the second setOption, merged), W, H
//     resolved[]  per series: seriesIndex, type, dataCount, animationOption
//                 (getShallow('animation')), threshold (animationThreshold),
//                 enabled (seriesModel.isAnimationEnabled()), duration /
//                 easing / delay and durationUpdate / easingUpdate /
//                 delayUpdate as getShallow reads them (a function -> {"$fn"})
//     clips[]     per sample: the number of Clips in zr.animation's list
//                 AFTER the step (0 = nothing animating)
//     elements[]  every element of every series view (all of them), and every
//                 element of a component view that animated at some sample:
//       id        owner + '/' + path (+ '#label' | '#clip' | '#guide'),
//                 path = child indices from the view's root group at the
//                 element's first sample
//       owner     'series<i>:<type>' | '<mainType><index>'
//       role      'el' | 'label' (host.getTextContent()) | 'clip'
//                 (host.getClipPath()) | 'guide' (host.getTextGuideLine())
//       type      zrender type ('rect', 'sector', 'ec-polyline', 'group' ...)
//       dataIndex getECData(el).dataIndex (null when unset)
//       present   null = present at every sample; else the sample indices
//       final     {key: value} at the LAST sample it was present in: numbers
//                 hex, number arrays flat hex lists, strings / booleans as is;
//                 finalText the twins
//       track     {key: [value per sample]} only for keys whose value is not
//                 the same at every sample it was present (null where absent);
//                 trackText the twins
//       animators [per sample: el.animators.length after the step] or null
//                 when always 0; scopes: the animator scopes seen ('enter',
//                 'update', 'leave', '' ...)
//     keys: x y scaleX scaleY rotation originX originY skewX skewY ignore
//           invisible, style.{opacity fill stroke lineWidth text x y
//           fillOpacity strokeOpacity}, shape.<every own key> (points arrays
//           flattened x0 y0 x1 y1 ...)
//   guards[]  {id, ok, detail} -- independent expectations checked on this run
// ---------------------------------------------------------------------------

const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-animation.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 250, 500, 750, 999, 1000, 1001, 1500];

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
const text = v => (Object.is(v, -0) ? '-0' : String(v));

// ---------- functions in options ----------
const FNS = {
  'idx*50': idx => idx * 50,
  'idx*30': idx => idx * 30,
  'dur:600+idx*100': idx => 600 + idx * 100,
};
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    if (typeof v.$fn === 'string') {
      must(FNS[v.$fn], 'unknown $fn ' + v.$fn);
      return FNS[v.$fn];
    }
    const o = {};
    for (const k of Object.keys(v)) o[k] = materialize(v[k]);
    return o;
  }
  return v;
}
function fnName(f) {
  for (const k of Object.keys(FNS)) if (FNS[k] === f) return { $fn: k };
  return { $fn: '?' };
}
const optVal = v => (typeof v === 'function' ? fnName(v) : v === undefined ? null : v);

// ---------- easings ----------
const EASING_NAMES = [
  'linear',
  'quadraticIn', 'quadraticOut', 'quadraticInOut',
  'cubicIn', 'cubicOut', 'cubicInOut',
  'quarticIn', 'quarticOut', 'quarticInOut',
  'quinticIn', 'quinticOut', 'quinticInOut',
  'sinusoidalIn', 'sinusoidalOut', 'sinusoidalInOut',
  'exponentialIn', 'exponentialOut', 'exponentialInOut',
  'circularIn', 'circularOut', 'circularInOut',
  'elasticIn', 'elasticOut', 'elasticInOut',
  'backIn', 'backOut', 'backInOut',
  'bounceIn', 'bounceOut', 'bounceInOut',
];
const CUBIC_SPECS = [
  'cubic-bezier(0.23,1,0.32,1)', // tooltip's CSS transition curve (TooltipHTMLContent.ts)
  'cubic-bezier(0.25,0.1,0.25,1)', // CSS ease
  'cubic-bezier(0.42,0,1,1)', // CSS ease-in
  'cubic-bezier(0,0,0.58,1)', // CSS ease-out
  'cubic-bezier(0.42,0,0.58,1)', // CSS ease-in-out
  'cubic-bezier(0.5, 0, 0.5, 1)', // blanks inside
  'cubic-bezier(0.1,0.9,0.2,1)',
  'cubic-bezier(0.3333333333333333,0,0.6666666666666666,1)', // x(t) = t: the degenerate root branch
  'cubic-bezier(1e-1,0.5,0.9,5e-1)', // 'e' is in the regexp's class
  'cubic-bezier(0.68,-0.55,0.265,1.55)', // a minus sign: the regexp rejects it -> no easing
  'cubic-bezier(0.5,0.5,0.5)', // three numbers: d = +undefined = NaN -> no easing
];
const UNKNOWN_SPECS = ['foo', 'CubicOut', ''];
function easingTs() {
  const ts = [];
  for (let k = 0; k <= 64; k++) ts.push(k / 64);
  const edges = [1e-9, 1e-6, 0.001, 0.1, 0.2, 0.3, 1 / 3, 0.4, 0.49, 0.499999, 0.500001, 0.6, 2 / 3, 0.7, 0.9, 0.999,
    0.999999, 1 - 1e-9, 1 / 2.75, 2 / 2.75, 2.5 / 2.75, 1 / 2.75 - 1e-12, 2 / 2.75 - 1e-12, 2.5 / 2.75 - 1e-12,
    Number.MIN_VALUE, 1 - Number.EPSILON / 2];
  const outside = [-0.25, -1e-9, 1 + 1e-9, 1.25];
  return { ts: ts.concat(edges, outside), firstOutside: ts.length + edges.length };
}
function easingFuncOf(zr, spec) {
  const target = { v: 0 };
  const animator = zr.animation.animate(target, {});
  animator.when(1000, { v: 1 }).start(spec);
  const clip = animator.getClip();
  must(clip, 'no clip for easing ' + JSON.stringify(spec));
  const f = clip.easingFunc;
  zr.animation.removeAnimator(animator);
  return f;
}
function sampleEasings() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 50, height: 50 });
  try {
    const zr = chart.getZr();
    const { ts, firstOutside } = easingTs();
    const table = [];
    const row = (name, kind) => {
      const f = easingFuncOf(zr, name);
      const values = ts.map(t => (f ? f(t) : t));
      return { name, kind, resolved: typeof f === 'function', values: values.map(hex), valuesText: values.map(text), fns: f };
    };
    EASING_NAMES.forEach(n => table.push(row(n, 'named')));
    CUBIC_SPECS.forEach(n => table.push(row(n, 'cubic-bezier')));
    UNKNOWN_SPECS.forEach(n => table.push(row(n, 'unknown')));
    return {
      ts: ts.map(hex), tsText: ts.map(text),
      tsNote: 'indices 0..64 are k/64; ' + 65 + '..' + (firstOutside - 1) + ' are edges inside [0, 1]; ' + firstOutside
        + '.. are OUTSIDE [0, 1] (never fed by Clip.step, which clamps; the functions alone). An unresolved row holds t itself '
        + '(Clip uses the raw percent when easingFunc is undefined).',
      names: EASING_NAMES.slice(),
      table,
      rawTs: ts,
    };
  }
  finally {
    chart.dispose();
  }
}

// ---------- element snapshots ----------
const TRANSFORM_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation', 'originX', 'originY', 'skewX', 'skewY'];
const STYLE_KEYS = ['opacity', 'fill', 'stroke', 'lineWidth', 'text', 'x', 'y', 'fillOpacity', 'strokeOpacity'];
function flatNums(v, out) {
  for (let i = 0; i < v.length; i++) {
    const e = v[i];
    if (e != null && typeof e === 'object' && e.length != null) flatNums(e, out);
    else out.push(typeof e === 'number' ? e : NaN);
  }
  return out;
}
function enc(v) {
  if (typeof v === 'number') return [hex(v), text(v)];
  if (typeof v === 'string' || typeof v === 'boolean') return [v, v];
  if (v && typeof v === 'object' && v.length != null && typeof v !== 'string') {
    const f = flatNums(v, []);
    return [f.map(hex), f.map(text)];
  }
  if (v && typeof v === 'object' && v.colorStops) {
    const s = JSON.stringify(v);
    return [s, s];
  }
  return undefined;
}
function snap(el) {
  const o = {};
  const put = (k, v) => {
    const e = enc(v);
    if (e !== undefined) o[k] = e;
  };
  for (const k of TRANSFORM_KEYS) if (typeof el[k] === 'number') put(k, el[k]);
  put('ignore', !!el.ignore);
  if (el.invisible != null) put('invisible', !!el.invisible);
  if (el.style) for (const k of STYLE_KEYS) if (el.style[k] != null) put('style.' + k, el.style[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (el.shape[k] != null) put('shape.' + k, el.shape[k]);
  return o;
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// the walk of one view: [{el, role, path}]
function walkView(root) {
  const out = [];
  const visit = (el, p) => {
    out.push({ el, role: 'el', path: p });
    const clip = el.getClipPath && el.getClipPath();
    if (clip) out.push({ el: clip, role: 'clip', path: p + '#clip' });
    const label = el.getTextContent && el.getTextContent();
    if (label) out.push({ el: label, role: 'label', path: p + '#label' });
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    if (guide) out.push({ el: guide, role: 'guide', path: p + '#guide' });
    if (el.isGroup) el.childrenRef().forEach((c, i) => visit(c, p === '' ? String(i) : p + '.' + i));
  };
  visit(root, '');
  return out;
}

function views(chart) {
  const out = [];
  const model = chart.getModel();
  model.eachSeries(s => {
    const v = chart.getViewOfSeriesModel(s);
    if (v) out.push({ owner: 'series' + s.seriesIndex + ':' + s.subType, series: true, group: v.group });
  });
  (chart._componentsViews || []).forEach(v => {
    const m = v.__model;
    if (m && v.group) out.push({ owner: m.mainType + m.componentIndex, series: false, group: v.group });
  });
  return out;
}

// getECData = makeInner() (util/innerStore.ts): an own property '__ec_inner_<n>'
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}

function clipCount(zr) {
  let n = 0;
  for (let c = zr.animation._head; c; c = c.next) n++;
  return n;
}

// ---------- one timeline ----------
// run(chart, sampleTimes) -> {clips[], elements[]}; the chart is at NOW = start
// with its setOption just done.
function recordTimeline(chart, start) {
  const zr = chart.getZr();
  const ids = new Map(); // el -> rec
  const recs = [];
  const clips = [];
  SAMPLES.forEach((t, si) => {
    NOW = start + t;
    if (si === 0) {
      // setOption's own zr.flush() already stepped every clip at NOW = start
      must(t === 0, 'the first sample must be t = 0');
      for (let c = zr.animation._head; c; c = c.next) must(c._inited, 'a clip was not stepped by the setOption flush');
    }
    else {
      zr.animation.update();
    }
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    for (const v of views(chart)) {
      for (const it of walkView(v.group)) {
        let rec = ids.get(it.el);
        if (!rec) {
          const ecd = ecDataOf(it.el);
          rec = {
            id: v.owner + '/' + (it.path === '' ? 'root' : it.path),
            owner: v.owner, series: v.series, role: it.role, type: it.el.type,
            dataIndex: ecd && ecd.dataIndex != null ? ecd.dataIndex : null,
            snaps: new Array(SAMPLES.length).fill(null),
            anim: new Array(SAMPLES.length).fill(0),
            scopes: new Set(),
          };
          ids.set(it.el, rec);
          recs.push(rec);
        }
        rec.snaps[si] = snap(it.el);
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        (it.el.animators || []).forEach(a => rec.scopes.add(a.scope == null ? '' : a.scope));
      }
    }
  });
  // ids must be unique: disambiguate repeats (an element re-created at the same path)
  const seen = new Map();
  const elements = [];
  for (const rec of recs) {
    const presentIdx = [];
    rec.snaps.forEach((s, i) => { if (s) presentIdx.push(i); });
    const keys = new Set();
    presentIdx.forEach(i => Object.keys(rec.snaps[i]).forEach(k => keys.add(k)));
    const lastI = presentIdx[presentIdx.length - 1];
    const final = {};
    const finalText = {};
    const track = {};
    const trackText = {};
    for (const k of [...keys].sort()) {
      const vals = presentIdx.map(i => rec.snaps[i][k]);
      const constant = vals.every(v => v !== undefined && same(v[0], vals[0][0]));
      const last = rec.snaps[lastI][k];
      if (last !== undefined) {
        final[k] = last[0];
        finalText[k] = last[1];
      }
      if (!constant) {
        track[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][0] : null));
        trackText[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][1] : null));
      }
    }
    const everAnim = rec.anim.some(n => n > 0);
    if (!rec.series && !everAnim && Object.keys(track).length === 0) continue;
    let id = rec.id + (rec.role !== 'el' && !rec.id.includes('#') ? '#' + rec.role : '');
    const n = seen.get(id) || 0;
    seen.set(id, n + 1);
    if (n) id += '~' + n;
    elements.push({
      id, owner: rec.owner, role: rec.role, type: rec.type, dataIndex: rec.dataIndex,
      present: presentIdx.length === SAMPLES.length ? null : presentIdx,
      final, finalText,
      track: Object.keys(track).length ? track : null,
      trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null,
      scopes: [...rec.scopes].sort(),
    });
  }
  return { clips, elements };
}

function resolvedOf(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const g = k => optVal(s.getShallow(k));
    out.push({
      seriesIndex: s.seriesIndex, type: s.subType, dataCount: s.getData().count(),
      animationOption: g('animation'), threshold: g('animationThreshold'), enabled: !!s.isAnimationEnabled(),
      duration: g('animationDuration'), easing: g('animationEasing'), delay: g('animationDelay'),
      durationUpdate: g('animationDurationUpdate'), easingUpdate: g('animationEasingUpdate'),
      delayUpdate: g('animationDelayUpdate'),
    });
  });
  return out;
}

// ---------- the charts ----------
const CATS = ['A', 'B', 'C', 'D', 'E'];
const BASE = {
  'bar-v': () => ({
    xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }],
  }),
  'bar-h': () => ({
    yAxis: { type: 'category', data: CATS }, xAxis: { type: 'value' },
    series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }],
  }),
  'bar-stack': () => ({
    xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', stack: 'total', data: [5, 20, 36, 10, 10] },
      { type: 'bar', stack: 'total', data: [8, 12, 6, 3, 15] }],
  }),
  'line-area': () => ({
    xAxis: { type: 'category', boundaryGap: false, data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
    series: [{ type: 'line', areaStyle: {}, data: [120, 132, 101, 134, 90, 230] }],
  }),
  'line-symbols': () => ({
    xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
    series: [{ type: 'line', symbol: 'circle', symbolSize: 8, showSymbol: true, label: { show: true },
      data: [120, 132, 101, 134, 90, 230] }],
  }),
  scatter: () => ({
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', symbolSize: 10, data: [[1, 2], [3, 4], [5, 1], [2, 6], [4, 3]] }],
  }),
  effectScatter: () => ({
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'effectScatter', symbolSize: 10, data: [[1, 2], [3, 4]] }],
  }),
  pie: () => ({
    series: [{ type: 'pie', radius: '60%',
      data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 },
        { name: 'e', value: 25 }] }],
  }),
  'pie-rose': () => ({
    series: [{ type: 'pie', roseType: 'radius', radius: [20, 110],
      data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 },
        { name: 'e', value: 25 }] }],
  }),
  'pie-scale': () => ({
    series: [{ type: 'pie', animationType: 'scale', radius: '60%',
      data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 },
        { name: 'e', value: 25 }] }],
  }),
  funnel: () => ({
    series: [{ type: 'funnel',
      data: [{ name: 'a', value: 100 }, { name: 'b', value: 80 }, { name: 'c', value: 60 }, { name: 'd', value: 40 },
        { name: 'e', value: 20 }] }],
  }),
  gauge: () => ({
    series: [{ type: 'gauge', progress: { show: true }, detail: { valueAnimation: true },
      data: [{ value: 60, name: 'score' }] }],
  }),
  radar: () => ({
    radar: { indicator: [{ name: 'a', max: 100 }, { name: 'b', max: 100 }, { name: 'c', max: 100 },
      { name: 'd', max: 100 }, { name: 'e', max: 100 }] },
    series: [{ type: 'radar', data: [{ value: [60, 70, 80, 50, 40], name: 'p' }, { value: [30, 90, 40, 70, 60], name: 'q' }] }],
  }),
  heatmap: () => ({
    xAxis: { type: 'category', data: ['x0', 'x1', 'x2'] }, yAxis: { type: 'category', data: ['y0', 'y1', 'y2'] },
    visualMap: { min: 0, max: 10, show: false },
    series: [{ type: 'heatmap', data: [[0, 0, 1], [0, 1, 5], [0, 2, 9], [1, 0, 3], [1, 1, 7], [1, 2, 2], [2, 0, 8],
      [2, 1, 4], [2, 2, 6]] }],
  }),
  'bar-label': () => ({
    xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true }, data: [5, 20, 36, 10, -8] }],
  }),
  'bar-markers': () => ({
    xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [5, 20, 36, 10, -8],
      markPoint: { data: [{ type: 'max', name: 'max' }] }, markLine: { data: [{ type: 'average', name: 'avg' }] } }],
  }),
  'line-endlabel': () => ({
    xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
    series: [{ type: 'line', showSymbol: false, endLabel: { show: true, valueAnimation: true },
      data: [120, 132, 101, 134, 90, 230] }],
  }),
  candlestick: () => ({
    xAxis: { type: 'category', data: ['d1', 'd2', 'd3', 'd4'] }, yAxis: { type: 'value' },
    series: [{ type: 'candlestick', data: [[20, 34, 10, 38], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42]] }],
  }),
};

const SINGLE_VARIANT = ['effectScatter', 'bar-label', 'bar-markers', 'line-endlabel'];
const VARIANTS = {
  default: { note: 'the defaults', series: {} },
  override: { note: 'series animationDuration 600, animationEasing linear, animationDelay 100',
    series: { animationDuration: 600, animationEasing: 'linear', animationDelay: 100 } },
  delayFn: { note: 'series animationDelay (idx) => idx * 50 (default duration and easing)',
    series: { animationDelay: { $fn: 'idx*50' } } },
};
const EXTRA_BAR_VARIANTS = {
  durationFn: { note: 'series animationDuration (idx) => 600 + idx * 100, easing quadraticOut',
    series: { animationDuration: { $fn: 'dur:600+idx*100' }, animationEasing: 'quadraticOut' } },
  elastic: { note: 'series animationEasing elasticOut, duration 800 (overshoot)',
    series: { animationDuration: 800, animationEasing: 'elasticOut' } },
  cubicBezier: { note: 'series animationEasing cubic-bezier(0.25,0.1,0.25,1), duration 800',
    series: { animationDuration: 800, animationEasing: 'cubic-bezier(0.25,0.1,0.25,1)' } },
  global: { note: 'ROOT-level animationDuration 600 / animationEasing linear / animationDelay 100 (series inherit)',
    root: { animationDuration: 600, animationEasing: 'linear', animationDelay: 100 } },
};

function applyVariant(opt, v) {
  if (v.series) opt.series.forEach(s => Object.assign(s, JSON.parse(JSON.stringify(v.series))));
  if (v.root) Object.assign(opt, JSON.parse(JSON.stringify(v.root)));
  return opt;
}

// ssr: true only to get a DOM-less zrender with the SSR SVG painter; then the
// instance is told it is NOT ssr before the first setOption, so ecModel.ssr is
// false (PieView and LineView switch their animation off / to 'scale' when
// ecModel.ssr is set) and setOption flushes synchronously as in a browser.
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}

function enterCase(chartName, variantName, v) {
  const option = applyVariant(BASE[chartName](), v);
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(materialize(option));
    const tl = recordTimeline(chart, T_BASE);
    return {
      id: chartName + '.' + variantName, kind: 'enter', chart: chartName, variant: variantName, note: v.note,
      option, next: null, W, H, resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements,
    };
  }
  finally {
    chart.dispose();
  }
}

// update: setOption(option) at T_BASE, run it out (frames to T_BASE + 5000),
// then setOption(next) at T1 = T_BASE + 10000 and record from there.
const T1_OFFSET = 10000;
function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
  must(clipCount(zr) === 0 || chart.getModel().getSeriesByType('effectScatter').length, 'the first render did not settle');
}
function updateCase(id, chartName, note, option, next) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(materialize(option));
    settle(chart, T_BASE);
    NOW = T_BASE + T1_OFFSET;
    chart.setOption(materialize(next));
    const tl = recordTimeline(chart, T_BASE + T1_OFFSET);
    return { id, kind: 'update', chart: chartName, variant: id.split('.').slice(1).join('.'), note, option, next, W, H,
      resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements };
  }
  finally {
    chart.dispose();
  }
}

function updateCases() {
  const out = [];
  const upd = { animationDurationUpdate: 300, animationEasingUpdate: 'linear', animationDelayUpdate: { $fn: 'idx*30' } };
  const withUpd = (o, on) => {
    if (on) o.series.forEach(s => Object.assign(s, JSON.parse(JSON.stringify(upd))));
    return o;
  };
  const updNote = ' (override: series animationDurationUpdate 300, animationEasingUpdate linear, animationDelayUpdate (idx) => idx * 30)';
  for (const on of [false, true]) {
    const tag = on ? 'override' : 'default';
    out.push(updateCase('bar-update.' + tag, 'bar-v', 'bar data values change, same categories' + (on ? updNote : ''),
      withUpd(BASE['bar-v'](), on), withUpd({ series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] }, on)));
    out.push(updateCase('line-update.' + tag, 'line-symbols', 'line data values change, same count' + (on ? updNote : ''),
      withUpd(BASE['line-symbols'](), on),
      withUpd({ series: [{ type: 'line', data: [90, 150, 120, 80, 200, 170] }] }, on)));
    out.push(updateCase('pie-update.' + tag, 'pie', 'pie values change, same names' + (on ? updNote : ''),
      withUpd(BASE.pie(), on),
      withUpd({ series: [{ type: 'pie', data: [{ name: 'a', value: 30 }, { name: 'b', value: 10 }, { name: 'c', value: 20 },
        { name: 'd', value: 25 }, { name: 'e', value: 15 }] }] }, on)));
  }
  out.push(updateCase('bar-label-update.default', 'bar-label', 'bar label valueAnimation: the label text runs from the old value to the new',
    BASE['bar-label'](), { series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] }));
  // enter + leave inside an update: categories shift (A leaves, F enters)
  out.push(updateCase('bar-update.addremove', 'bar-v', 'categories A-E -> B-F: bar A leaves, bar F enters, B-E move',
    BASE['bar-v'](),
    { xAxis: { data: ['B', 'C', 'D', 'E', 'F'] }, series: [{ type: 'bar', data: [20, 36, 10, -8, 25] }] }));
  out.push(updateCase('line-update.addpoint', 'line-symbols', 'a 7th point appended (lineAnimationDiff with a count change)',
    BASE['line-symbols'](),
    { xAxis: { data: ['A', 'B', 'C', 'D', 'E', 'F', 'G'] },
      series: [{ type: 'line', data: [120, 132, 101, 134, 90, 230, 180] }] }));
  out.push(updateCase('line-update.shift', 'line-area', 'the window slides by one category (first point leaves, one enters)',
    BASE['line-area'](),
    { xAxis: { data: ['B', 'C', 'D', 'E', 'F', 'G'] }, series: [{ type: 'line', data: [132, 101, 134, 90, 230, 160] }] }));
  out.push(updateCase('pie-update.addremove', 'pie', 'slice a removed, slice f added',
    BASE.pie(),
    { series: [{ type: 'pie', data: [{ name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 },
      { name: 'e', value: 25 }, { name: 'f', value: 12 }] }] }));
  return out;
}

function thresholdCases() {
  const out = [];
  const six = () => ({
    xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [5, 20, 36, 10, 8, 12] }],
  });
  const run = (variant, note, option) => {
    NOW = T_BASE;
    rngState = SEED;
    const chart = newChart();
    try {
      chart.setOption(materialize(option));
      const tl = recordTimeline(chart, T_BASE);
      return { id: 'threshold.' + variant, kind: 'threshold', chart: 'bar-v', variant, note, option, next: null, W, H,
        resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements };
    }
    finally {
      chart.dispose();
    }
  };
  let o = six();
  o.series[0].animationThreshold = 5;
  out.push(run('above', '6 items, series animationThreshold 5: count > threshold -> no animation', o));
  o = six();
  o.series[0].animationThreshold = 6;
  out.push(run('equal', '6 items, series animationThreshold 6: count == threshold -> animates (the test is >)', o));
  o = six();
  o.animationThreshold = 5;
  out.push(run('rootAbove', '6 items, ROOT animationThreshold 5 (the series inherits it) -> no animation', o));
  o = six();
  o.animation = false;
  out.push(run('rootOff', 'root animation: false -> nothing animates', o));
  o = six();
  o.series[0].animation = false;
  o.series.push({ type: 'line', data: [5, 20, 36, 10, 8, 12] });
  out.push(run('seriesOff', 'series 0 (bar) animation: false, series 1 (line) default', o));
  o = six();
  o.series[0].animationDuration = 0;
  out.push(run('zeroDuration', 'series animationDuration 0 -> getAnimationConfig duration 0 -> attr() at once', o));
  return out;
}

// ---------- independent expectations ----------
function refEasing(name) {
  const PI = Math.PI;
  const E = {
    linear: k => k,
    quadraticIn: k => k * k,
    quadraticOut: k => k * (2 - k),
    quadraticInOut: k => { k *= 2; if (k < 1) return 0.5 * k * k; k -= 1; return -0.5 * (k * (k - 2) - 1); },
    cubicIn: k => k * k * k,
    cubicOut: k => { k -= 1; return k * k * k + 1; },
    cubicInOut: k => { k *= 2; if (k < 1) return 0.5 * k * k * k; k -= 2; return 0.5 * (k * k * k + 2); },
    quarticIn: k => k * k * k * k,
    quarticOut: k => { k -= 1; return 1 - (k * k * k * k); },
    quarticInOut: k => { k *= 2; if (k < 1) return 0.5 * k * k * k * k; k -= 2; return -0.5 * (k * k * k * k - 2); },
    quinticIn: k => k * k * k * k * k,
    quinticOut: k => { k -= 1; return k * k * k * k * k + 1; },
    quinticInOut: k => { k *= 2; if (k < 1) return 0.5 * k * k * k * k * k; k -= 2; return 0.5 * (k * k * k * k * k + 2); },
    sinusoidalIn: k => 1 - Math.cos(k * PI / 2),
    sinusoidalOut: k => Math.sin(k * PI / 2),
    sinusoidalInOut: k => 0.5 * (1 - Math.cos(PI * k)),
    exponentialIn: k => (k === 0 ? 0 : Math.pow(1024, k - 1)),
    exponentialOut: k => (k === 1 ? 1 : 1 - Math.pow(2, -10 * k)),
    exponentialInOut: k => {
      if (k === 0) return 0;
      if (k === 1) return 1;
      k *= 2;
      if (k < 1) return 0.5 * Math.pow(1024, k - 1);
      return 0.5 * (-Math.pow(2, -10 * (k - 1)) + 2);
    },
    circularIn: k => 1 - Math.sqrt(1 - k * k),
    circularOut: k => { k -= 1; return Math.sqrt(1 - (k * k)); },
    circularInOut: k => {
      k *= 2;
      if (k < 1) return -0.5 * (Math.sqrt(1 - k * k) - 1);
      k -= 2;
      return 0.5 * (Math.sqrt(1 - k * k) + 1);
    },
    // a = 1 (the 0.1 fails `a < 1`), s = p / 4 = 0.1, p = 0.4
    elasticIn: k => {
      if (k === 0) return 0;
      if (k === 1) return 1;
      k -= 1;
      return -(1 * Math.pow(2, 10 * k) * Math.sin((k - 0.1) * (2 * PI) / 0.4));
    },
    elasticOut: k => {
      if (k === 0) return 0;
      if (k === 1) return 1;
      return 1 * Math.pow(2, -10 * k) * Math.sin((k - 0.1) * (2 * PI) / 0.4) + 1;
    },
    elasticInOut: k => {
      if (k === 0) return 0;
      if (k === 1) return 1;
      k *= 2;
      if (k < 1) { k -= 1; return -0.5 * (1 * Math.pow(2, 10 * k) * Math.sin((k - 0.1) * (2 * PI) / 0.4)); }
      k -= 1;
      return 1 * Math.pow(2, -10 * k) * Math.sin((k - 0.1) * (2 * PI) / 0.4) * 0.5 + 1;
    },
    backIn: k => { const s = 1.70158; return k * k * ((s + 1) * k - s); },
    backOut: k => { const s = 1.70158; k -= 1; return k * k * ((s + 1) * k + s) + 1; },
    backInOut: k => {
      const s = 1.70158 * 1.525;
      k *= 2;
      if (k < 1) return 0.5 * (k * k * ((s + 1) * k - s));
      k -= 2;
      return 0.5 * (k * k * ((s + 1) * k + s) + 2);
    },
    bounceOut: k => {
      if (k < (1 / 2.75)) return 7.5625 * k * k;
      if (k < (2 / 2.75)) { k -= (1.5 / 2.75); return 7.5625 * k * k + 0.75; }
      if (k < (2.5 / 2.75)) { k -= (2.25 / 2.75); return 7.5625 * k * k + 0.9375; }
      k -= (2.625 / 2.75);
      return 7.5625 * k * k + 0.984375;
    },
  };
  E.bounceIn = k => 1 - E.bounceOut(1 - k);
  E.bounceInOut = k => (k < 0.5 ? E.bounceIn(k * 2) * 0.5 : E.bounceOut(k * 2 - 1) * 0.5 + 0.5);
  return E[name];
}
// a cubic-bezier by bisection on x(t) (monotone for x1, x2 in [0, 1]), then y(t)
function refBezier(x1, y1, x2, y2, p) {
  if (p <= 0) return 0;
  if (p >= 1) return 1;
  const at = (a, b, t) => 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
  let lo = 0;
  let hi = 1;
  for (let i = 0; i < 200; i++) {
    const mid = (lo + hi) / 2;
    if (at(x1, x2, mid) < p) lo = mid; else hi = mid;
  }
  return at(y1, y2, (lo + hi) / 2);
}

function check(gen) {
  const guards = [];
  const E = gen.easingsRaw;
  // G1: every named easing, bit for bit, against the formulas re-typed from easing.ts
  {
    const bad = [];
    E.table.filter(r => r.kind === 'named').forEach(r => {
      const f = refEasing(r.name);
      E.rawTs.forEach((t, i) => { if (hex(f(t)) !== r.values[i]) bad.push(r.name + '@' + text(t)); });
      if (!r.resolved) bad.push(r.name + ' unresolved');
    });
    guards.push({ id: 'easing-formulas', ok: bad.length === 0,
      detail: bad.length ? bad.slice(0, 12).join(', ') : '31 easings x ' + E.rawTs.length + ' samples bit-identical to the re-typed formulas' });
  }
  // G2: a few by hand
  {
    const val = (name, t) => {
      const r = E.table.find(x => x.name === name);
      return r.fns(t);
    };
    const hand = [
      ['quadraticIn', 0.5, 0.25], ['cubicOut', 0.5, 0.875], ['cubicInOut', 0.25, 0.0625], ['cubicInOut', 0.75, 0.9375],
      ['quarticOut', 0.5, 0.9375], ['backIn', 0, 0], ['backOut', 1, 1], ['bounceOut', 1 / 4, 7.5625 / 16],
      ['exponentialIn', 0, 0], ['exponentialOut', 1, 1], ['elasticOut', 0, 0], ['linear', 0.3, 0.3],
    ];
    const bad = hand.filter(([n, t, v]) => val(n, t) !== v).map(([n, t, v]) => n + '(' + t + ')=' + val(n, t) + ' != ' + v);
    guards.push({ id: 'easing-hand', ok: bad.length === 0, detail: bad.length ? bad.join('; ') : hand.length + ' hand values exact' });
  }
  // G3: cubic-bezier against bisection
  {
    const bad = [];
    const specs = [[0.25, 0.1, 0.25, 1], [0.42, 0, 1, 1], [0, 0, 0.58, 1], [0.42, 0, 0.58, 1], [0.23, 1, 0.32, 1]];
    specs.forEach(s => {
      const r = E.table.find(x => x.name === 'cubic-bezier(' + s.join(',') + ')');
      if (!r || !r.resolved) { bad.push(s.join(',') + ' unresolved'); return; }
      E.rawTs.forEach(t => {
        if (t < 0 || t > 1) return;
        const got = r.fns(t);
        const want = refBezier(s[0], s[1], s[2], s[3], t);
        if (!(Math.abs(got - want) < 1e-9)) bad.push(s.join(',') + '@' + text(t) + ': ' + got + ' vs ' + want);
      });
    });
    const neg = E.table.find(x => x.name === 'cubic-bezier(0.68,-0.55,0.265,1.55)');
    if (neg.resolved) bad.push('the negative spec resolved');
    const degen = E.table.find(x => x.name === 'cubic-bezier(0.3333333333333333,0,0.6666666666666666,1)');
    guards.push({ id: 'cubic-bezier', ok: bad.length === 0,
      detail: (bad.length ? bad.slice(0, 8).join('; ') : '5 specs within 1e-9 of bisection; the negative spec unresolved')
        + '; degenerate x(t)=t spec resolved=' + degen.resolved + ' f(0.5)=' + (degen.fns ? degen.fns(0.5) : 'n/a') });
  }
  // G4: linear bar growth (bar-v.override: duration 600, linear, delay 100)
  {
    const c = gen.cases.find(x => x.id === 'bar-v.override');
    const bars = c.elements.filter(e => e.owner.startsWith('series0') && e.type === 'rect' && e.role === 'el' && e.dataIndex != null);
    const bad = [];
    const hexOf = v => hex(v);
    bars.forEach(b => {
      const hFinal = b.final['shape.height'];
      const hF = numOf(hFinal);
      SAMPLES.forEach((t, i) => {
        const pct = Math.min(Math.max((t - 100) / 600, 0), 1);
        const want = (hF - 0) * pct + 0;
        const got = b.track && b.track['shape.height'] ? b.track['shape.height'][i] : hFinal;
        if (got !== hexOf(want)) bad.push('bar ' + b.dataIndex + ' t=' + t + ' got ' + got + ' want ' + hexOf(want));
      });
    });
    guards.push({ id: 'bar-linear-growth', ok: bars.length === 5 && bad.length === 0,
      detail: bad.length ? bad.slice(0, 6).join('; ') : bars.length + ' bars: height = (h - 0) * clamp((t - 100) / 600, 0, 1) + 0 at every sample' });
  }
  // G5: threshold above -> no clips ever
  {
    const above = gen.cases.find(x => x.id === 'threshold.above');
    const equal = gen.cases.find(x => x.id === 'threshold.equal');
    const off = gen.cases.find(x => x.id === 'threshold.rootOff');
    const ok = above.clips.every(n => n === 0) && off.clips.every(n => n === 0) && equal.clips[0] > 0
      && above.resolved[0].enabled === false && equal.resolved[0].enabled === true;
    guards.push({ id: 'threshold', ok, detail: 'above clips ' + above.clips.join(',') + '; equal clips ' + equal.clips.join(',')
      + '; rootOff clips ' + off.clips.join(',') });
  }
  // G6: every enter case with a series element tracked ends at its final value at t = 1500
  {
    const bad = [];
    gen.cases.forEach(c => {
      if (c.chart === 'effectScatter') return;
      if (c.clips[c.clips.length - 1] !== 0) bad.push(c.id + ' still animating at 1500');
    });
    guards.push({ id: 'settled-at-1500', ok: bad.length === 0, detail: bad.length ? bad.join('; ') : 'every non-looping case has no clip left at t = 1500' });
  }
  return guards;
}
function numOf(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}

// ---------- generation ----------
function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const easingsRaw = sampleEasings();
  const cases = [];
  for (const name of Object.keys(BASE)) {
    const vs = SINGLE_VARIANT.includes(name) ? { default: VARIANTS.default } : VARIANTS;
    for (const vn of Object.keys(vs)) cases.push(enterCase(name, vn, vs[vn]));
    if (name === 'bar-v') for (const vn of Object.keys(EXTRA_BAR_VARIANTS)) cases.push(enterCase(name, vn, EXTRA_BAR_VARIANTS[vn]));
  }
  updateCases().forEach(c => cases.push(c));
  thresholdCases().forEach(c => cases.push(c));
  const easings = {
    ts: easingsRaw.ts, tsText: easingsRaw.tsText, tsNote: easingsRaw.tsNote, names: easingsRaw.names,
    table: easingsRaw.table.map(r => ({ name: r.name, kind: r.kind, resolved: r.resolved, values: r.values, valuesText: r.valuesText })),
  };
  const out = {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    dist: DIST.replace(/\\/g, '/'), W, H, seed: SEED, envNodeFlipped: true,
    clock: {
      hook: 'global.Date replaced before require(dist): new Date() / Date.now() return NOW; zrender Animation.getTime() = new Date().getTime()',
      t0: 'setOption at NOW = T0 ends with its own zr.flush() -> animation.update(true) at T0 (chart._ssr forced false); every Clip takes _startTime = T0 + delay on that step',
      frame: 'NOW = T0 + t; zr.animation.update(); zr.storage.getDisplayList(true)',
      T0: T_BASE,
      T0Note: 'the absolute epoch ms matters: Clip._startTime = globalTime + delay is a double near 1.7e12 (ulp 2^-12), so a FRACTIONAL delay (effectScatter ripples: -i/n*period + idx/count) is rounded there and every later percent carries that rounding; integer delays and lives are exact',
      T1Offset: T1_OFFSET,
      update: 'update cases: first setOption at T0, frames to T0 + 5000 (settled), second setOption at T1 = T0 + ' + T1_OFFSET + ', samples relative to T1',
    },
    samplesMs: SAMPLES,
    notes: [
      'Clip time model (zrender animation/Clip.ts:104-152): percent = min(max((now - (tFirstStep + delay)) / life, 0), 1); value = (to - from) * easing(percent) + from (Animator.ts:49-51); the clip ends (done) on the step where percent reaches 1, so the final value is written exactly at that frame.',
      'A delayed element sits at its FROM value from t = 0 on (setToFinal + the clip steps with percent 0 during the delay).',
      'Enter / update animate with setToFinal: true (basicTransition.ts:182): the element holds the final props right after setOption (layout reads them) and the first step writes the from values back.',
      'effectScatter ripples loop forever; its case is never settled.',
    ],
    easings,
    cases,
  };
  return { out, easingsRaw, cases };
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
out.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': ' + gd.detail));
const deterministic = json1 === json2;
const nEl = out.cases.reduce((n, c) => n + c.elements.length, 0);
console.log(out.cases.length + ' cases (' + nEl + ' elements); ' + (out.guards.length - bad.length) + '/' + out.guards.length
  + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic || json1.length >= 5 * 1024 * 1024) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
