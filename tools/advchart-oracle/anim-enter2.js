// F3a (fix phase, 2026-10-18): the ENTER animations of the six series the
// AN2 batch left still -- pictorialBar, graph, tree, treemap, sunburst and
// sankey -- as the real build runs them.
// The harness is animation-an4.js' own, copied (that script generates and
// exits on load): the replaced Date before the dist, chart._ssr = false,
// env.node = false, the seeded Math.random, hand-stepped frames and the same
// element records. Every case is one option set at T0 and recorded from T0
// (sample 0 is setOption's own flush).
// Run: node tools/advchart-oracle/anim-enter2.js
//   -> tests/fixtures/advchart-anim-enter2.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-enter2.json');

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

// ---------- the cases ----------
const CATS3 = ['A', 'B', 'C'];
const TREE = [{ name: 'root', children: [
  { name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] },
  { name: 'b', children: [{ name: 'b1' }] },
  { name: 'c' }] }];
const HIER = [
  { name: 'a', value: 10, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 6 }] },
  { name: 'b', value: 5, children: [{ name: 'b1', value: 5 }] },
  { name: 'c', value: 3 }];
const SANKEY_NODES = [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }];
const SANKEY_LINKS = [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 },
  { source: 'b', target: 'd', value: 4 }, { source: 'c', target: 'd', value: 2 }];
const GRAPH_NODES = [{ name: 'a', x: 10, y: 10 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 50, y: 100 },
  { name: 'd', x: 120, y: 120 }];
const GRAPH_LINKS = [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' },
  { source: 'a', target: 'd' }];

function enter2Cases() {
  const out = [];
  // ---- pictorialBar ----
  out.push(enterCase('pictorial.single',
    'one glyph per bar: the path scales 0 -> symbolScale at enter timing and the row; the label on the bar rect fades',
    { xAxis: { type: 'category', data: CATS3 }, yAxis: { type: 'value' },
      series: [{ type: 'pictorialBar', symbol: 'rect', label: { show: true, position: 'top' }, data: [10, 20, 30] }] }));
  out.push(enterCase('pictorial.repeat',
    'symbolRepeat: every glyph of the column scales from 0 at its place',
    { xAxis: { type: 'category', data: ['A', 'B'] }, yAxis: { type: 'value' },
      series: [{ type: 'pictorialBar', symbol: 'circle', symbolRepeat: true, symbolSize: [20, 10], data: [10, 20] }] }));
  out.push(enterCase('pictorial.clip',
    'symbolClip: the glyphs are set at once, the clip rect grows along the value axis (initProps at the row)',
    { xAxis: { type: 'category', data: ['A', 'B'] }, yAxis: { type: 'value', max: 30 },
      series: [{ type: 'pictorialBar', symbol: 'circle', symbolRepeat: 'fixed', symbolClip: true, symbolSize: [20, 10],
        label: { show: true, position: 'top' }, data: [10, 20] }] }));
  out.push(enterCase('pictorial.horizontal',
    'a category y axis, a negative value: the scale along x is mirrored (symbolScale[0] * pxSign)',
    { yAxis: { type: 'category', data: ['A', 'B'] }, xAxis: { type: 'value' },
      series: [{ type: 'pictorialBar', symbol: 'triangle', symbolSize: ['100%', '60%'], label: { show: true },
        data: [12, -6] }] }));
  out.push(enterCase('pictorial.timing',
    'animationDuration 600, linear, delay idx*50; item 1 writes animation: false (ItemModel.isAnimationEnabled): set at once',
    { xAxis: { type: 'category', data: CATS3 }, yAxis: { type: 'value' },
      series: [{ type: 'pictorialBar', symbol: 'roundRect', symbolRepeat: true, symbolSize: [16, 8],
        animationDuration: 600, animationEasing: 'linear', animationDelay: { $fn: 'idx*50' },
        data: [6, { value: 9, animation: false }, 12] }] }));
  // ---- graph ----
  out.push(enterCase('graph.none',
    'layout none: Symbol pop-in (scale 0 -> size / 2, opacity 0 -> 1), labels fade, the edges draw out (percent), their arrows and labels ride the percent',
    { series: [{ type: 'graph', layout: 'none', symbolSize: 20, label: { show: true }, edgeSymbol: ['circle', 'arrow'],
      edgeLabel: { show: true }, data: GRAPH_NODES, links: GRAPH_LINKS }] }));
  out.push(enterCase('graph.curved',
    'curved edges (curveness 0.3) with arrows and labels: the percent cuts the quadratic, the label rides its middle',
    { series: [{ type: 'graph', layout: 'none', symbolSize: 16, label: { show: true }, edgeSymbol: ['none', 'arrow'],
      lineStyle: { curveness: 0.3 }, edgeLabel: { show: true, formatter: 'e' },
      data: [{ name: 'a', x: 0, y: 40 }, { name: 'b', x: 60, y: 0 }, { name: 'c', x: 120, y: 30 }, { name: 'd', x: 90, y: 100 },
        { name: 'e', x: 20, y: 110 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' },
        { source: 'd', target: 'e' }, { source: 'e', target: 'a' }] }] }));
  out.push(enterCase('graph.timing',
    'animationDuration 400, cubicOut, delay idx*50; node opacity 0.6; no labels',
    { series: [{ type: 'graph', layout: 'none', symbolSize: [24, 12], itemStyle: { opacity: 0.6 },
      animationDuration: 400, animationEasing: 'cubicOut', animationDelay: { $fn: 'idx*50' },
      data: GRAPH_NODES, links: GRAPH_LINKS }] }));
  // ---- tree ----
  out.push(enterCase('tree.default',
    'orthogonal LR, curve edges: the node groups slide from the root at update timing (no row), the symbol paths pop in at enter timing (700 linear), the edges grow from the root, the labels fade',
    { series: [{ type: 'tree', data: TREE }] }));
  out.push(enterCase('tree.polyline',
    'orient TB, edgeShape polyline: a parent\'s TreePath from one child point to its children',
    { series: [{ type: 'tree', orient: 'TB', edgeShape: 'polyline', data: TREE }] }));
  out.push(enterCase('tree.radial',
    'layout radial: the same slides in the radial frame, the labels turned',
    { series: [{ type: 'tree', layout: 'radial', data: TREE }] }));
  out.push(enterCase('tree.timing',
    'animationDuration 300, animationDurationUpdate 600, animationEasingUpdate linear, symbolSize 10',
    { series: [{ type: 'tree', symbolSize: 10, animationDuration: 300, animationDurationUpdate: 600,
      animationEasingUpdate: 'linear', data: TREE }] }));
  // ---- treemap ----
  out.push(enterCase('treemap.default',
    'the first render does not animate the rects (no old); LabelManager fades the leaves\' labels',
    { series: [{ type: 'treemap', data: HIER }] }));
  out.push(enterCase('treemap.upper',
    'upperLabel shown, animationDuration 500 linear: the parents\' upper labels fade too',
    { series: [{ type: 'treemap', upperLabel: { show: true }, animationDuration: 500, animationEasing: 'linear',
      data: HIER }] }));
  // ---- sunburst ----
  out.push(enterCase('sunburst.default',
    'every piece r from r0 at enter timing (1000 cubicInOut) and its row; the labels fade',
    { series: [{ type: 'sunburst', data: HIER }] }));
  out.push(enterCase('sunburst.timing',
    'animationDuration 600, linear, delay idx*50, radius [20, 120]',
    { series: [{ type: 'sunburst', radius: [20, 120], animationDuration: 600, animationEasing: 'linear',
      animationDelay: { $fn: 'idx*50' }, data: HIER }] }));
  // ---- sankey ----
  out.push(enterCase('sankey.default',
    'one clip rect on the main group: x - 10, y - 10, width 0 -> width + 20 (1000 linear, no row); no label fades (disableLabelAnimation)',
    { series: [{ type: 'sankey', data: SANKEY_NODES, links: SANKEY_LINKS }] }));
  out.push(enterCase('sankey.vertical',
    'orient vertical: the same clip, the bounding rect of the vertical layout',
    { series: [{ type: 'sankey', orient: 'vertical', data: SANKEY_NODES, links: SANKEY_LINKS }] }));
  out.push(enterCase('sankey.timing',
    'animationDuration 500, cubicOut; nodeWidth 30, no border',
    { series: [{ type: 'sankey', nodeWidth: 30, itemStyle: { borderWidth: 0 }, animationDuration: 500,
      animationEasing: 'cubicOut', data: SANKEY_NODES, links: SANKEY_LINKS }] }));
  // ---- off ----
  out.push(enterCase('off.series',
    'animation: false on each series: nothing animates',
    { xAxis: { type: 'category', data: CATS3, show: false }, yAxis: { type: 'value', show: false },
      series: [
        { type: 'pictorialBar', animation: false, symbol: 'rect', label: { show: true }, data: [10, 20, 30] },
        { type: 'graph', animation: false, layout: 'none', label: { show: true }, left: 0, top: 0, width: 100, height: 100,
          data: GRAPH_NODES, links: GRAPH_LINKS },
        { type: 'sunburst', animation: false, center: [300, 200], radius: [0, 60], data: HIER },
        { type: 'sankey', animation: false, left: 200, top: 10, width: 150, height: 100, data: SANKEY_NODES,
          links: SANKEY_LINKS }] }));
  out.push(enterCase('off.threshold',
    'animationThreshold 3 on a 4-node graph and a 4-leaf tree: isAnimationEnabled is false -- the symbols and edges are set at once; the tree\'s slides do not run either (updateProps reads isAnimationEnabled too)',
    { series: [
      { type: 'graph', animationThreshold: 3, layout: 'none', left: 0, width: 150, data: GRAPH_NODES, links: GRAPH_LINKS },
      { type: 'tree', animationThreshold: 3, left: 220, data: TREE }] }));
  return out;
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const out = {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'F3a: the enter animations of pictorialBar, graph, tree, treemap, sunburst and sankey. One option at T0, '
      + 'recorded from T0 (sample 0 is the setOption flush); the element records of animation.js.',
    W, H, seed: SEED,
    clock: { T0: T_BASE },
    samplesMs: SAMPLES,
    cases: enter2Cases(),
  };
  const byId = id => out.cases.find(c => c.id === id);
  const anim = (c, pred) => c.elements.filter(e => e.animators && pred(e));
  const g = [];
  // independent expectations
  g.push({ id: 'pictorial-glyphs-scale', ok: anim(byId('pictorial.single'), e => e.type === 'path').length === 3 });
  g.push({ id: 'pictorial-clip-only', ok: anim(byId('pictorial.clip'), e => e.role === 'clip').length === 2
    && anim(byId('pictorial.clip'), e => e.type === 'path').length === 0 });
  g.push({ id: 'pictorial-item-off', ok: anim(byId('pictorial.timing'), e => e.dataIndex === 1).length === 0
    && anim(byId('pictorial.timing'), e => e.dataIndex === 0).length > 0 });
  g.push({ id: 'graph-lines-draw', ok: anim(byId('graph.none'), e => e.type === 'ec-line').length === 4 });
  g.push({ id: 'tree-slides', ok: anim(byId('tree.default'), e => e.type === 'group'
    && e.scopes.indexOf('update') >= 0).length > 0 });
  g.push({ id: 'treemap-labels-only', ok: anim(byId('treemap.default'), e => e.role !== 'label').length === 0
    && anim(byId('treemap.default'), e => e.role === 'label').length > 0 });
  g.push({ id: 'sunburst-r', ok: anim(byId('sunburst.default'), e => e.type === 'sector').length === 6 });
  g.push({ id: 'sankey-clip-only', ok: anim(byId('sankey.default'), e => e.role !== 'clip').length === 0
    && anim(byId('sankey.default'), e => e.role === 'clip').length === 1 });
  g.push({ id: 'off-still', ok: byId('off.series').clips.every(n => n === 0) });
  g.push({ id: 'threshold-graph-still', ok: anim(byId('off.threshold'), e => e.owner === 'series0:graph').length === 0 });
  g.push({ id: 'threshold-tree-still', ok: anim(byId('off.threshold'), e => e.owner === 'series1:tree').length === 0 });
  for (const c of out.cases) {
    g.push({ id: 'settled:' + c.id, ok: c.clips[SAMPLES.length - 1] === 0 });
  }
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
