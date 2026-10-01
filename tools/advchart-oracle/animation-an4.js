// AN4 (batch 92): labels, markers, continuous and pointer animation cases beyond
// tests/fixtures/advchart-animation.json and advchart-animation-update.json.
// The harness is animation-update.js' own, copied (that script generates and exits on load):
// the replaced Date before the dist, chart._ssr = false, env.node = false, the
// seeded Math.random, hand-stepped frames and the same element records.
// Run: node tools/advchart-oracle/animation-an4.js
//   -> tests/fixtures/advchart-animation-an4.json
'use strict';
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-animation-an4.json');

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

// the compact writer of animation.js
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

// ---------- AN3: update and leave cases the main fixture does not hold ----------

function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}

const T1_OFFSET = 10000;
function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
  // a ripple loops for ever: settled is no clip but the looping ones
  let rest = 0;
  for (let c = zr.animation._head; c; c = c.next) if (!c.loop) rest++;
  must(rest === 0, 'the first render did not settle');
}

// setOption(option) at T0, settled; setOption(next, setOpts) at T1 = T0 +
// 10000. With `mid`: frames at T1 + each of mid.steps, then
// setOption(mid.next, setOpts) at T1 + the last step, recorded from there.
// The port's Option is notMerge, so every AN3 case sets its options whole
// with notMerge: true.
function runUpdate(option, next, setOpts, mid) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(materialize(option));
    settle(chart, T_BASE);
    const t1 = T_BASE + T1_OFFSET;
    NOW = t1;
    chart.setOption(materialize(next), setOpts);
    let start = t1;
    if (mid) {
      const zr = chart.getZr();
      for (const t of mid.steps) {
        NOW = t1 + t;
        zr.animation.update();
      }
      start = t1 + mid.steps[mid.steps.length - 1];
      NOW = start;
      chart.setOption(materialize(mid.next), setOpts);
    }
    const tl = recordTimeline(chart, start);
    return { resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements };
  }
  finally {
    chart.dispose();
  }
}
function updateCase(id, note, option, next, mid) {
  const r = runUpdate(option, next, true, mid);
  return { id, kind: 'update', note, option, next, mid: mid || null, W, H,
    resolved: r.resolved, clips: r.clips, elements: r.elements };
}


// ---------- AN4: enter cases (one option at T0, recorded from T0) ----------
function runEnter(option) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(materialize(option));
    const tl = recordTimeline(chart, T_BASE);
    return { resolved: resolvedOf(chart), clips: tl.clips, elements: tl.elements };
  }
  finally {
    chart.dispose();
  }
}
function enterCase(id, note, option) {
  const r = runEnter(option);
  return { id, kind: 'enter', note, option, W, H, resolved: r.resolved, clips: r.clips, elements: r.elements };
}

// ---------- AN4: the axis pointer ----------
// The pointer group is added to the zr root by BaseAxisPointer.render, not to
// a component view: these roots are walked as 'axisPointer/<k>.<path>'.
function pointerRoots(chart) {
  const inViews = new Set(views(chart).map(v => v.group));
  return chart.getZr().storage._roots.filter(r => !inViews.has(r));
}
// A move is dispatched at NOW = T1 (updateAxisPointer, mousemove); nothing
// flushes there (dispatchAction flushes only with opt.flush), so the clips
// start at the FIRST frame after it. Sample 0 is read before any frame (the
// tween's setToFinal has put the target there); every later sample is
// NOW = T1 + t, update, getDisplayList.
function recordPointer(chart, start, moves) {
  const zr = chart.getZr();
  const recs = new Map();
  const order = [];
  const clips = [];
  const sampleAt = [];
  SAMPLES.forEach((t, si) => {
    for (const m of moves) {
      if (m.at > 0 && m.at <= t && !m.done) {
        // a later move dispatched between samples, at its own instant, with
        // the frames before it run
        NOW = start + m.at;
        zr.animation.update();
        chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x: m.x, y: m.y });
        m.done = true;
      }
    }
    NOW = start + t;
    if (si > 0) zr.animation.update();
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    pointerRoots(chart).forEach((root, k) => {
      for (const it of walkView(root)) {
        if (it.el.isGroup) continue;
        const id = 'axisPointer/' + k + (it.path === '' ? '' : '.' + it.path) + (it.role !== 'el' ? '#' + it.role : '');
        let rec = recs.get(id);
        if (!rec) {
          rec = { id, type: it.el.type, snaps: new Array(SAMPLES.length).fill(null), anim: new Array(SAMPLES.length).fill(0), scopes: new Set() };
          recs.set(id, rec);
          order.push(rec);
        }
        rec.snaps[si] = snap(it.el);
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        (it.el.animators || []).forEach(a => rec.scopes.add(a.scope == null ? '' : a.scope));
      }
    });
    sampleAt.push(t);
  });
  const elements = order.map(rec => {
    const keys = new Set();
    rec.snaps.forEach(s => s && Object.keys(s).forEach(k => keys.add(k)));
    const final = {};
    const finalText = {};
    const track = {};
    const trackText = {};
    const present = [];
    rec.snaps.forEach((s, i) => { if (s) present.push(i); });
    const last = rec.snaps[present[present.length - 1]];
    for (const k of [...keys].sort()) {
      const vals = present.map(i => rec.snaps[i][k]);
      const constant = vals.every(v => v !== undefined && same(v[0], vals[0][0]));
      if (last[k] !== undefined) { final[k] = last[k][0]; finalText[k] = last[k][1]; }
      if (!constant) {
        track[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][0] : null));
        trackText[k] = rec.snaps.map(s => (s && s[k] !== undefined ? s[k][1] : null));
      }
    }
    const everAnim = rec.anim.some(n => n > 0);
    return { id: rec.id, owner: 'axisPointer', role: 'el', type: rec.type,
      present: present.length === SAMPLES.length ? null : present, final, finalText,
      track: Object.keys(track).length ? track : null, trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null, scopes: [...rec.scopes].sort() };
  });
  return { clips, elements };
}
// option at T0, settled; the first move at T0 + 6000 (the first show is
// direct), frames to settle it; then `moves` from T1 = T0 + 10000 (each move:
// {at: ms after T1, x, y}; at 0 is dispatched at T1 itself)
function pointerCase(id, note, option, first, moves) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(materialize(option));
    settle(chart, T_BASE);
    const zr = chart.getZr();
    NOW = T_BASE + 6000;
    chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x: first.x, y: first.y });
    for (let t = 16; t <= 2000; t += 250) {
      NOW = T_BASE + 6000 + t;
      zr.animation.update();
    }
    zr.storage.getDisplayList(true);
    must(clipCount(zr) === 0, id + ': the first show did not settle');
    const t1 = T_BASE + T1_OFFSET;
    NOW = t1;
    const ms = moves.map(m => Object.assign({ done: false }, m));
    ms.filter(m => m.at === 0).forEach(m => {
      chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x: m.x, y: m.y });
      m.done = true;
    });
    const tl = recordPointer(chart, t1, ms);
    return { id, kind: 'pointer', note, option, first, moves, W, H, clips: tl.clips, elements: tl.elements };
  }
  finally {
    chart.dispose();
  }
}

const CATS5 = ['A', 'B', 'C', 'D', 'E'];
// emphasis disabled: the axis trigger's highlight would add state
// transitions (AN3b) to the clip count
const ptrBar = (tip, extra) => Object.assign({
  tooltip: Object.assign({ trigger: 'axis' }, tip || {}),
  xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
  series: [{ type: 'bar', emphasis: { disabled: true }, data: [5, 20, 36, 10, -8] }],
}, extra || {});

function an4Cases() {
  const out = [];
  // ---- valueAnimation ----
  out.push(enterCase('bar-label.precision',
    'valueAnimation, precision auto: fractional values count with max(getPrecision(0), getPrecision(value)) decimals',
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true },
        data: [1.5, 2.25, 3.125, -0.5, 7] }] }));
  out.push(enterCase('bar-label.fixed',
    'valueAnimation, label.precision 1: round(x, 1), printed by Number#toString',
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true, precision: 1 },
        data: [12.34, 20, 0.07, 9.99, 3] }] }));
  out.push(enterCase('bar-label.formatter',
    'valueAnimation with a string formatter: {c} is the interpolated value, {b} the name',
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true, formatter: '{b}:{c} pts' },
        data: [5, 20, 36, 10, -8] }] }));
  out.push(enterCase('gauge.formatter',
    'gauge detail with valueAnimation and a {value} formatter, value 37.5',
    { series: [{ type: 'gauge', detail: { valueAnimation: true, formatter: '{value}%' },
      data: [{ value: 37.5, name: 'rate' }] }] }));
  // ---- line endLabel ----
  out.push(enterCase('line-endlabel.smooth',
    'endLabel on a smooth line: polyline.getPointOn solves the cubic for the clip edge',
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
      series: [{ type: 'line', smooth: true, showSymbol: false, endLabel: { show: true },
        data: [120, 132, 101, 134, 90, 230] }] }));
  out.push(enterCase('line-endlabel.nulls',
    'endLabel with a null: the label waits on the last point before the gap (connectNulls false)',
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
      series: [{ type: 'line', showSymbol: false, endLabel: { show: true },
        data: [120, 132, null, 134, 90, 230] }] }));
  out.push(enterCase('line-endlabel.novalue',
    'endLabel valueAnimation false, a formatter: the text stays, the label still rides the clip',
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
      series: [{ type: 'line', name: 'S', showSymbol: false, endLabel: { show: true, valueAnimation: false, formatter: '{a} {c}' },
        data: [120, 132, 101, 134, 90, 230] }] }));
  out.push(enterCase('line-endlabel.vertical',
    'endLabel on a vertical base axis (yAxis category): the clip grows up, dim y',
    { yAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, xAxis: { type: 'value' },
      series: [{ type: 'line', showSymbol: false, endLabel: { show: true },
        data: [120, 132, 101, 134, 90, 230] }] }));
  // ---- markers ----
  out.push(enterCase('bar-markers.positions',
    'markLine labels at start / insideEndTop / middle and a markPoint min of symbolSize 30',
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', data: [5, 20, 36, 10, -8],
        markPoint: { symbolSize: 30, data: [{ type: 'min', name: 'min' }] },
        markLine: { data: [
          { type: 'average', name: 'avg', label: { position: 'start' } },
          { yAxis: 30, name: 'thirty', label: { position: 'insideEndTop' } },
          [{ coord: ['A', 5] }, { coord: ['E', 25] }]] } }] }));
  out.push(enterCase('bar-markers.off',
    'markLine animation: false (still); a markPoint on each series: the one whose series animation is off holds still, the other pops in',
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', data: [5, 20, 36, 10, -8],
        markPoint: { data: [{ type: 'max', name: 'max' }] },
        markLine: { animation: false, data: [{ type: 'average', name: 'avg' }] } },
      { type: 'bar', animation: false, data: [3, 6, 9, 12, 15],
        markPoint: { data: [{ type: 'max', name: 'max' }] } }] }));
  // ---- effectScatter ----
  out.push(enterCase('effectScatter.custom',
    'rippleEffect period 2, scale 4, number 2, brushType stroke, three symbols of size 16',
    { xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'effectScatter', symbolSize: 16, rippleEffect: { period: 2, scale: 4, number: 2, brushType: 'stroke' },
        data: [[1, 2], [3, 4], [2, 1]] }] }));
  out.push(enterCase('effectScatter.emphasis',
    "showEffectOn 'emphasis': no ripple until hovered; the symbols still pop in",
    { xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'effectScatter', showEffectOn: 'emphasis', symbolSize: 10, data: [[1, 2], [3, 4]] }] }));
  // ---- updates (notMerge) ----
  out.push(updateCase('bar-label-update.inflight',
    'valueAnimation labels change, and change again 250 ms in: the count goes on from the interpolated value',
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true }, data: [5, 20, 36, 10, -8] }] },
    { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true }, data: [15, 8, 30, 25, 4] }] },
    { steps: [16, 100, 250], next: { xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value' },
      series: [{ type: 'bar', label: { show: true, position: 'top', valueAnimation: true }, data: [30, 2, 12, 18, 20] }] } }));
  out.push(updateCase('gauge-update.default',
    'gauge 60 -> 25: pointer from the old rotation, progress from the old end, the detail counts down at update timing',
    { series: [{ type: 'gauge', progress: { show: true }, detail: { valueAnimation: true }, data: [{ value: 60, name: 'score' }] }] },
    { series: [{ type: 'gauge', progress: { show: true }, detail: { valueAnimation: true }, data: [{ value: 25, name: 'score' }] }] }));
  out.push(updateCase('pie-update.inflight',
    'pie values change, and change again 250 ms in: every label jumps to its last layout and moves on from there',
    { series: [{ type: 'pie', radius: '50%', data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }] }] },
    { series: [{ type: 'pie', radius: '50%', data: [{ name: 'a', value: 30 }, { name: 'b', value: 20 }, { name: 'c', value: 10 }] }] },
    { steps: [16, 100, 250], next: { series: [{ type: 'pie', radius: '50%',
      data: [{ name: 'a', value: 5 }, { name: 'b', value: 40 }, { name: 'c', value: 15 }] }] } }));
  out.push(updateCase('effectScatter-update.move',
    'effectScatter symbols move: the group slides, the ripples run on',
    { xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'effectScatter', symbolSize: 10, data: [[1, 2], [3, 4]] }] },
    { xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'effectScatter', symbolSize: 10, data: [[2, 3], [5, 5]] }] }));
  out.push(updateCase('line-endlabel-update.default',
    'endLabel line, values change: the clip runs again (enter timing), the end label rides it from the start',
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value', max: 250 },
      series: [{ type: 'line', showSymbol: false, endLabel: { show: true }, data: [120, 132, 101, 134, 90, 230] }] },
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value', max: 250 },
      series: [{ type: 'line', showSymbol: false, endLabel: { show: true }, data: [100, 150, 120, 80, 200, 140] }] }));
  // ---- the axis pointer ----
  out.push(pointerCase('axisPointer.line',
    'tooltip trigger axis, line pointer: B -> D slides 200 ms exponentialOut (category band 60 > 15)',
    ptrBar(), { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.shadow',
    'shadow pointer: the band slides B -> D',
    ptrBar({ axisPointer: { type: 'shadow' } }), { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.inflight',
    'B -> D, then -> A 100 ms in: the second slide starts where the first has got to',
    ptrBar(), { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }, { at: 100, x: 90, y: 150 }]));
  out.push(pointerCase('axisPointer.override',
    'tooltip.axisPointer animationDurationUpdate 600, animationEasingUpdate linear',
    ptrBar({ axisPointer: { animationDurationUpdate: 600, animationEasingUpdate: 'linear' } }),
    { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.axisOwn',
    "the axis' own axisPointer over the tooltip's: xAxis.axisPointer 600 / linear wins over tooltip.axisPointer 300 / cubicOut",
    ptrBar({ axisPointer: { animationDurationUpdate: 300, animationEasingUpdate: 'cubicOut' } },
      { xAxis: { type: 'category', data: CATS5, axisPointer: { animationDurationUpdate: 600, animationEasingUpdate: 'linear' } } }),
    { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.off',
    'tooltip.axisPointer animation false: the pointer jumps',
    ptrBar({ axisPointer: { animation: false } }), { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.dense',
    '40 categories: the band (7.5 px) is under the 15 px threshold, the pointer jumps',
    { tooltip: { trigger: 'axis' }, xAxis: { type: 'category', data: Array.from({ length: 40 }, (_, i) => 'c' + i) },
      yAxis: { type: 'value' }, series: [{ type: 'bar', emphasis: { disabled: true }, data: Array.from({ length: 40 }, (_, i) => (i * 7) % 23) }] },
    { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.valueSnap',
    'a value x axis under a tooltip snaps (modelHelper: not category and triggered by the tooltip), so it slides by |extent| / count > 15',
    { tooltip: { trigger: 'axis' }, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'line', emphasis: { disabled: true }, data: [[1, 5], [2, 9], [3, 4], [4, 8]] }] },
    { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  out.push(pointerCase('axisPointer.rootOff',
    'root animation false: the tooltip pointer keeps its own animation \'auto\' and still slides',
    ptrBar(null, { animation: false }), { x: 150, y: 150 }, [{ at: 0, x: 270, y: 150 }]));
  return out;
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const out = {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'AN4 supplement to advchart-animation.json and advchart-animation-update.json: the same harness. '
      + 'enter: one option at T0. update: as animation-update.js (notMerge, T1 = T0 + 10000, mid). '
      + 'pointer: option at T0, settled; updateAxisPointer (mousemove) at T0 + 6000, settled (the first show is direct); '
      + 'the moves from T1: a move at 0 is dispatched at T1 and sample 0 is read with no frame run (setToFinal), every later '
      + 'sample runs a frame at T1 + t; a move at m > 0 runs a frame at T1 + m and is dispatched there. axisPointer/<k>: the k-th '
      + 'zr root that is no view group (BaseAxisPointer adds its group to the zr root).',
    W, H, seed: SEED,
    clock: { T0: T_BASE, T1Offset: T1_OFFSET },
    samplesMs: SAMPLES,
    cases: an4Cases(),
  };
  // guards
  const byId = id => out.cases.find(c => c.id === id);
  const g = [];
  const ptr = byId('axisPointer.line');
  g.push({ id: 'pointer-slides', ok: ptr.clips.some(n => n > 0) });
  g.push({ id: 'pointer-off-still', ok: byId('axisPointer.off').clips.every(n => n === 0) });
  g.push({ id: 'pointer-dense-still', ok: byId('axisPointer.dense').clips.every(n => n === 0) });
  g.push({ id: 'pointer-value-snaps', ok: byId('axisPointer.valueSnap').clips.some(n => n > 0) });
  // markLine animation false: still; the markPoint of the series whose animation is off: still; the other's pops in
  const offEls = byId('bar-markers.off').elements;
  g.push({ id: 'markers-off-still', ok: offEls.filter(e => e.owner.startsWith('markLine')).every(e => !e.animators)
    && offEls.filter(e => e.owner.startsWith('markPoint') && e.animators).length === 1 });
  g.push({ id: 'ripples-loop', ok: byId('effectScatter.custom').clips[SAMPLES.length - 1] === 3 * 2 * 2 });
  g.push({ id: 'emphasis-no-ripple', ok: byId('effectScatter.emphasis').clips[SAMPLES.length - 1] === 0 });
  for (const x of g) must(x.ok, 'guard ' + x.id);
  out.guards = g;
  return out;
}

let json1;
let json2;
try {
  const g1 = generate();
  json1 = fmt(g1, '') + '\n';
  must(!json1.includes('\\u0000'), 'the fixture holds a \\u0000');
  json2 = fmt(generate(), '') + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (json1 !== json2) {
  console.log('FAILED: two generations differ');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT, json1.length, 'bytes');
process.exit(0);
