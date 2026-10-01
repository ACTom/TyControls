// AN3 (batch 90): update and leave cases beyond tests/fixtures/advchart-animation.json.
// The harness is animation.js' own, copied (that script generates and exits on load):
// the replaced Date before the dist, chart._ssr = false, env.node = false, the
// seeded Math.random, hand-stepped frames and the same element records.
// Run: node tools/advchart-oracle/animation-update.js
//   -> tests/fixtures/advchart-animation-update.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-animation-update.json');

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
  must(clipCount(zr) === 0, 'the first render did not settle');
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

// ECharts' merge of `next` into `option` for the shapes the main fixture
// uses: objects merge key by key, a component list (series, xAxis ...)
// merges item by item, any other array (data) is replaced.
const COMPONENTS = ['series', 'xAxis', 'yAxis', 'radar', 'visualMap', 'dataZoom', 'legend', 'title', 'grid'];
function mergeOpt(a, b, key) {
  if (b === undefined) return JSON.parse(JSON.stringify(a));
  if (a === undefined || a === null || b === null || typeof a !== 'object' || typeof b !== 'object')
    return JSON.parse(JSON.stringify(b));
  if (COMPONENTS.includes(key)) {
    const aa = Array.isArray(a) ? a : [a];
    const bb = Array.isArray(b) ? b : [b];
    const out = [];
    for (let i = 0; i < Math.max(aa.length, bb.length); i++) out.push(mergeOpt(aa[i], bb[i], ''));
    return Array.isArray(a) || Array.isArray(b) || out.length > 1 ? out : out[0];
  }
  if (Array.isArray(a) || Array.isArray(b)) return JSON.parse(JSON.stringify(b));
  const o = {};
  for (const k of Object.keys(a)) o[k] = mergeOpt(a[k], b[k], k);
  for (const k of Object.keys(b)) if (!(k in a)) o[k] = JSON.parse(JSON.stringify(b[k]));
  return o;
}

// THE MAIN FIXTURE'S UPDATE CASES, AS THE PORT SETS THEM: the merged option
// with notMerge. Guard: every series element records exactly as the merge
// run does; no component element animates (notMerge recreates the axis
// views, so there is no old group to transition from).
function twins() {
  const main = JSON.parse(fs.readFileSync(path.join(ROOT, 'tests', 'fixtures', 'advchart-animation.json'), 'utf8'));
  const out = [];
  for (const c of main.cases) {
    if (c.kind !== 'update') continue;
    const merged = mergeOpt(c.option, c.next, '');
    const m = runUpdate(c.option, c.next, undefined, null);
    const n = runUpdate(c.option, merged, true, null);
    const ser = els => els.filter(e => e.owner.startsWith('series'));
    const comp = els => els.filter(e => !e.owner.startsWith('series'));
    must(JSON.stringify(ser(m.elements)) === JSON.stringify(ser(c.elements)), c.id + ': the merge rerun differs from the main fixture');
    const same = JSON.stringify(ser(m.elements)) === JSON.stringify(ser(n.elements));
    const compStill = comp(n.elements).every(e => !e.animators);
    must(same, c.id + ': notMerge series elements differ from merge');
    must(compStill, c.id + ': a component animates under notMerge');
    out.push({ id: c.id, merged, clips: n.clips, seriesSame: same, componentsStill: compStill });
  }
  return out;
}

const CATS = ['A', 'B', 'C', 'D', 'E'];
const barV = () => ({
  xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }],
});
const UPD = { animationDurationUpdate: 300, animationEasingUpdate: 'linear', animationDelayUpdate: { $fn: 'idx*30' } };
const upd = o => { o.series.forEach(s => Object.assign(s, JSON.parse(JSON.stringify(UPD)))); return o; };

function cases() {
  const out = [];
  // the delay of a moved bar is its NEW index's: B..E move from 1..4 to 0..3
  out.push(updateCase('bar-update.shiftdelay',
    'categories A-E -> B-F with animationDelayUpdate (idx) => idx * 30: the moved bars wait by their NEW index',
    upd(barV()),
    upd({ xAxis: { type: 'category', data: ['B', 'C', 'D', 'E', 'F'] }, yAxis: { type: 'value' },
      series: [{ type: 'bar', data: [20, 36, 10, -8, 25] }] })));
  // a third option 250 ms into the second's tween: every bar goes on from
  // where it is, not from where the second option put it
  out.push(updateCase('bar-update.inflight',
    'values change, and change again 250 ms into the tween (from the current, in-flight shape)',
    barV(), { xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
      series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] },
    { steps: [16, 100, 250], next: { xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
      series: [{ type: 'bar', data: [30, 2, 12, 18, 20] }] } }));
  // a whole series goes: the view's remove fades every bar
  out.push(updateCase('bar-update.seriesremove',
    'two bar series -> one: the first updates, the second view is removed at once (its group leaves the zr root)',
    { xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
      series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }, { type: 'bar', data: [3, 6, 9, 12, 15] }] },
    { xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
      series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] }));
  // scatter: index-keyed, one symbol leaves (opacity and scale to 0), the
  // rest move (group x/y, no index) and grow (path scale, update timing)
  out.push(updateCase('scatter-update.default',
    'scatter: four symbols move and grow (symbolSize 10 -> 14), the fifth leaves',
    { xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'scatter', symbolSize: 10, data: [[1, 2], [3, 4], [5, 1], [2, 6], [4, 3]] }] },
    { xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'scatter', symbolSize: 14, data: [[2, 3], [3, 5], [6, 2], [1, 1]] }] }));
  out.push(updateCase('scatter-update.override',
    'scatter as default, with the update override (300 / linear / delay idx * 30) and a symbol added',
    upd({ xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'scatter', symbolSize: 10, data: [[1, 2], [3, 4], [5, 1]] }] }),
    upd({ xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'scatter', symbolSize: 10, data: [[2, 3], [3, 5], [6, 2], [7, 7]] }] })));
  // the 3000 px cutoff: the added point sits far outside the old coordinates
  out.push(updateCase('line-update.cutoff',
    'a point appended far outside the old value range: the bounding diff passes 3000 px and the line is set, not tweened',
    { xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value' },
      series: [{ type: 'line', data: [1, 2, 3] }] },
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D'] }, yAxis: { type: 'value' },
      series: [{ type: 'line', data: [1, 2, 3, 100000] }] }));
  // an area line with a point appended: the added point AND its base start
  // where the old axes put them (the x axis has a category more)
  out.push(updateCase('line-update.areaadd',
    'area line, a 7th point appended: the new point and its stacked-on point start in the old coordinates',
    { xAxis: { type: 'category', boundaryGap: false, data: ['A', 'B', 'C', 'D', 'E', 'F'] },
      yAxis: { type: 'value', min: 50, max: 250 },
      series: [{ type: 'line', areaStyle: {}, data: [120, 132, 101, 134, 90, 230] }] },
    { xAxis: { type: 'category', boundaryGap: false, data: ['A', 'B', 'C', 'D', 'E', 'F', 'G'] },
      yAxis: { type: 'value', min: 50, max: 250 },
      series: [{ type: 'line', areaStyle: {}, data: [120, 132, 101, 134, 90, 230, 160] }] }));
  // a null filled in: the old point is not a number, so it starts at the new
  out.push(updateCase('line-update.nullfill',
    'a null point gets a value: its tween starts at its new place (lineAnimationDiff, NaN current)',
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E'] }, yAxis: { type: 'value', max: 200 },
      series: [{ type: 'line', data: [120, null, 101, 134, 90] }] },
    { xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E'] }, yAxis: { type: 'value', max: 200 },
      series: [{ type: 'line', data: [110, 150, 101, 120, 90] }] }));
  // the clip changes with the pen: initProps to the new rect at ENTER timing
  out.push(updateCase('line-update.clip',
    'lineStyle width 2 -> 12: the clip rect grows by the half pen, at enter timing (line: 1000 linear)',
    { xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 10 },
      series: [{ type: 'line', data: [3, 7, 5] }] },
    { xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', max: 10 },
      series: [{ type: 'line', lineStyle: { width: 12 }, data: [3, 7, 5] }] }));
  // a named series moves from index 0 to 1: its view goes with the NAME, and
  // the unnamed series now at 0 is a new view, which enters
  out.push(updateCase('bar-update.namedmove',
    'series s moves from index 0 to 1: it updates (same model id), the new unnamed series 0 enters',
    { xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
      series: [{ type: 'bar', name: 's', data: [5, 20, 36, 10, -8] }, { type: 'bar', data: [3, 6, 9, 12, 15] }] },
    { xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
      series: [{ type: 'bar', data: [2, 4, 6, 8, 10] }, { type: 'bar', name: 's', data: [15, 8, 30, 25, 4] }] }));
  // an added slice of a pie whose animationType is 'scale': r from r0 at
  // enter timing
  out.push(updateCase('pie-update.scale',
    'animationType scale: slice f is added (r from r0, enter timing), a is removed',
    { series: [{ type: 'pie', animationType: 'scale', radius: '60%',
      data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }] }] },
    { series: [{ type: 'pie', animationType: 'scale', radius: '60%',
      data: [{ name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'f', value: 12 }] }] }));
  return out;
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const out = {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'AN3 supplement to advchart-animation.json: the same harness (tools/advchart-oracle/animation.js). '
      + 'The port sets its option whole (notMerge), so: twins = each main-fixture update case set as the merged option with notMerge '
      + '(guarded: series elements identical to the merge run, no component animating; clips are the notMerge counts); '
      + 'cases = further update cases, every option set whole with notMerge. mid: frames at T1 + steps, then mid.next at T1 + '
      + 'the last step, recorded from there.',
    W, H, seed: SEED,
    clock: { T0: T_BASE, T1Offset: T1_OFFSET },
    samplesMs: SAMPLES,
    twins: twins(),
    cases: cases(),
  };
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
