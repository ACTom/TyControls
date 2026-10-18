/*
Upstream's own answers for the fix phase, batch F3b: the two engine pieces
batch 87 (AN1) left out -- GRADIENT INTERPOLATION and PAUSE / RESUME.

zrender 6.1 animation/Animator.ts: Track.addKeyframe parses a gradient
object (colorStops != null) into its numbers and its stops' colours (rgba
arrays); a linear one against a linear one, a radial against a radial,
interpolates -- prepare pads the shorter stop list of each keyframe and the
last one with its last stop (fillColorStops, in place, either side), step
writes a NEW object each frame: x, y, every stop's offset and colour
(interpolate1DArray, rgba2String with r, g, b floored), global the next
frame's, then x2, y2 or r. A linear against a radial, or a colour against a
gradient, is discrete: an animateTo (no discrete allowed) jumps to the end,
a keyframe animation (discrete allowed) switches at the keyframe.
animation/Animation.ts pause / resume (the clock is the wall clock less the
paused stretches; the frame loop skips update() while paused, a flush does
not), Clip.ts pause / resume (a paused clip's step adds the delta to its
paused time; a loop's restart forgets it), Animator.ts pause / resume.

Reached through the graphic component: style.fill and style.stroke
gradients under `transition: ['style']` (Path.getAnimationStyleProps names
fill and stroke), under keyframeAnimation, and the chart's
getZr().animation.pause() / resume() and an element's animators[k].pause().

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs, so
the frame loop never runs and never sleeps: every step is by hand),
Math.random the port's xorshift32 and zrender's width table measuring text.

  node tools/advchart-oracle/anim-engine2.js

writes tests/fixtures/advchart-anim-engine2.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, notes[], cases[], guards[].

A case: id, group, note, W, H, option, events[]. An event, in order, at t
ms after T0 (the first setOption is at T0):
  {t, do: 'sample', els}       the frame loop's step (zr.animation.update()
                               unless the chart's animation is paused), then
                               every graphic element by id
  {t, do: 'merge', option}     setOption(option) -- its flush steps every
                               clip, paused or not
  {t, do: 'pause'} / 'resume'  getZr().animation.pause() / resume()
  {t, do: 'pauseAnimator', id, k} / 'resumeAnimator'
                               el.animators[k].pause() / resume() on the
                               element of that id

A snap: the transform props x, y, rotation, scaleX, scaleY; 'style.<k>' for
opacity, fill, stroke where not null -- a colour string as it is, a gradient
as {type, x, y, x2, y2 | r (hex; null when the object has none), global
(as it is, null for none), stops: [[offset hex, colour as it is], ...]};
'shape.<k>' for every own key not null and not transition / enterFrom /
leaveTo; n, the element's animators that still have a clip.

Guards (any failure: nothing is written, exit 1): named discriminating facts
and the whole fixture generated twice, byte-identical.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

// ---------- the random numbers: the port's xorshift32 ----------
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ZRENDER_SRC = process.env.ZRENDER_SRC || 'D:/Projects/zrender/src/core/platform.ts';
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-engine2.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const hexOrNull = v => (v == null ? null : hex(+v));
function valRec(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(valRec);
  if (typeof v === 'object' && v.colorStops != null) {
    const o = { type: v.type == null ? null : v.type, x: hexOrNull(v.x), y: hexOrNull(v.y) };
    if (v.type === 'radial') o.r = hexOrNull(v.r);
    else { o.x2 = hexOrNull(v.x2); o.y2 = hexOrNull(v.y2); }
    o.global = v.global == null ? null : v.global;
    o.stops = v.colorStops.map(s => [hexOrNull(s.offset), s.color == null ? null : s.color]);
    return o;
  }
  return JSON.stringify(v);
}

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
  if (fs.existsSync(ZRENDER_SRC)) {
    const m = /const defaultWidthMapStr = (`[^`]*`)/.exec(fs.readFileSync(ZRENDER_SRC, 'utf8'));
    must(m && decodeTable(m[1], ZRENDER_SRC) === s, 'the dist and the zrender source disagree on the width table');
  }
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

// ---------- the chart ----------
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  rngState = SEED;
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }

// GraphicView's inner store: {id, type, isNew, option, width, height}
function gInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'isNew' in el[k]) return el[k];
  }
  return null;
}
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'seriesIndex' in el[k]) return el[k];
  }
  return null;
}
const enc = id => (id == null ? null : String(id).split('\u0000').join('~'));
function graphicView(chart) {
  return (chart._componentsViews || []).find(v => v && v.type === 'graphic') || null;
}
function graphicEl(chart, id) {
  let found = null;
  const view = graphicView(chart);
  if (view) view.group.traverse(el => {
    const inn = gInner(el);
    if (inn && enc(inn.id) === id) found = el;
  });
  must(found, 'no graphic element ' + id);
  return found;
}

// ---------------------------------------------------------------------------
// reading the elements
// ---------------------------------------------------------------------------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY'];
const SNAP_STYLE = ['opacity', 'fill', 'stroke'];
const SKIP = { transition: 1, enterFrom: 1, leaveTo: 1 };
function snap(el) {
  const o = {};
  for (const k of TKEYS) o[k] = hex(el[k]);
  if (el.style) {
    for (const k of SNAP_STYLE) {
      if (el.style[k] != null) o['style.' + k] = valRec(el.style[k]);
    }
  }
  if (el.shape && !el.isGroup) {
    for (const k of Object.keys(el.shape)) {
      if (SKIP[k] || el.shape[k] == null) continue;
      o['shape.' + k] = valRec(el.shape[k]);
    }
  }
  o.n = el.animators.filter(a => a.getClip()).length;
  return o;
}
function readEls(chart) {
  const els = {};
  const view = graphicView(chart);
  const walk = g => g.childrenRef().forEach(el => {
    const inn = gInner(el);
    must(inn, 'a graphic element with no inner store');
    els[enc(inn.id)] = snap(el);
    if (el.isGroup) walk(el);
  });
  if (view) walk(view.group);
  chart.getModel().eachRawSeries(sm => {
    if (sm.subType !== 'custom') return;
    const cv = chart.getViewOfSeriesModel(sm);
    if (!cv) return;
    const data = sm.getData();
    cv.group.childrenRef().forEach(el => {
      const ecd = ecDataOf(el);
      must(ecd && ecd.dataIndex != null, 'a custom root without a data index');
      els['s' + sm.seriesIndex + ':' + data.getRawIndex(ecd.dataIndex)] = snap(el);
    });
  });
  return els;
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
function add(group, id, note, option, events, more) {
  CASES.push(Object.assign({ group, id, note, W: 400, H: 300, option, events }, more));
}
const samples = ts => ts.map(t => ({ t, do: 'sample' }));
const lin = (x, y, x2, y2, stops, global) => {
  const o = { type: 'linear', x, y, x2, y2, colorStops: stops.map(([offset, color]) => ({ offset, color })) };
  if (global !== undefined) o.global = global;
  return o;
};
const rad = (x, y, r, stops, global) => {
  const o = { type: 'radial', x, y, r, colorStops: stops.map(([offset, color]) => ({ offset, color })) };
  if (global !== undefined) o.global = global;
  return o;
};

// ---- gradients ----
// A GRAPHIC element's gradient cannot show a style transition: the merge
// writes the new option into the old option object in place (zrUtil.merge),
// and the element's style.fill IS that object -- from and to are one. A
// custom series' renderItem returns new objects every render, so the old
// element keeps the old gradient: the transitions are read there.
const GRADS = [
  lin(0, 0, 0, 1, [[0, '#5070dd'], [1, '#b6d634']]),
  lin(0.25, 0.1, 0.75, 1, [[0.2, 'rgba(255,0,0,0.5)'], [0.9, '#00ff00']]),
  lin(0, 0, 1, 0, [[0, '#ff0000'], [1, '#0000ff']]),
  lin(0, 0, 0, 1, [[0, '#00ff00'], [0.5, '#ffffff'], [1, '#000000']]),
  lin(0, 0, 1, 1, [[0, '#ff0000'], [0.5, '#00ff00'], [1, '#0000ff']]),
  lin(1, 0, 0, 1, [[0, '#333333'], [1, '#cccccc']]),
  rad(0.5, 0.5, 0.5, [[0, 'rgba(255,255,255,0.8)'], [1, '#5070dd']]),
  rad(10, 20, 40, [[0, '#fac858'], [1, 'rgba(0,0,0,0.1)']], true),
  lin(0, 0, 1, 0, [[0, '#000000'], [1, '#ff994d']]),
  lin(1, 1, 0, 0, [[0, '#9a60b4'], [1, '#3ba272']]),
  rad(0.5, 0.5, 0.5, [[0, '#ffffff'], [1, '#000000']]),
  '#ff0000',
  '#00ff00',
  lin(0, 0, 0, 1, [[0, 'red'], [1, 'transparent']]),
  lin(0, 0, 0, 1, [[0, 'blue'], [1, 'rgba(10,20,30,0.25)']]),
  '#eeeeee',
];
// a rect at (x, y) whose fill is GRADS[k] (and stroke GRADS[ks], width 4,
// when ks >= 0), transitioning its style on update: duration d linear (0:
// the series' own update timing)
const RENDER = {
  gradItem(params, api) {
    const k = api.value(2);
    const ks = api.value(3);
    const d = api.value(4);
    const el = { type: 'rect', x: api.value(0), y: api.value(1), shape: { width: 60, height: 40 },
      style: { fill: clone(GRADS[k]) }, transition: ['style'] };
    if (ks >= 0) {
      el.style.stroke = clone(GRADS[ks]);
      el.style.lineWidth = 4;
    }
    if (d > 0) el.updateAnimation = { duration: d, easing: 'linear' };
    return el;
  },
};
function materialize(v) {
  if (Array.isArray(v)) return v.map(materialize);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (k === 'renderItem' && typeof v[k] === 'string' && v[k][0] === '@') {
        const fn = RENDER[v[k].slice(1)];
        must(fn, 'no renderItem ' + v[k]);
        o[k] = fn;
      }
      else o[k] = materialize(v[k]);
    }
    return o;
  }
  return v;
}
const S_UPD = [0, 1, 100, 150, 300, 450, 599, 600, 601, 900];
add('gradient', 'grad-update', "custom rects (renderItem gradItem, GRADS by index) whose style.fill goes gradient to gradient under transition ['style']: linear 2 stops to 2 (geometry, offsets, colours with alpha); linear 2 to 3 stops (the from list padded with its last stop); linear 3 to 2 (the target's padded: the interpolated end has three stops); radial to radial with global, on the series' update timing (cubicOut 400); a stroke gradient beside a colour fill; a linear to a radial (discrete: it jumps); a colour to a gradient and a gradient to a colour (discrete); named colours and 'transparent' in the stops",
  { animation: true, series: [{ type: 'custom', coordinateSystem: 'none', renderItem: '@gradItem',
    animationDurationUpdate: 400, animationEasingUpdate: 'cubicOut',
    data: [[10, 10, 0, -1, 600], [90, 10, 2, -1, 600], [170, 10, 4, -1, 600], [250, 10, 6, -1, 0],
      [10, 80, 15, 8, 600], [90, 80, 0, -1, 600], [170, 80, 11, -1, 600], [250, 80, 0, -1, 600],
      [10, 150, 13, -1, 600]] }] },
  [...samples([0, 100]), { t: 200, do: 'merge', option: { series: [{
    data: [[10, 10, 1, -1, 600], [90, 10, 3, -1, 600], [170, 10, 5, -1, 600], [250, 10, 7, -1, 0],
      [10, 80, 15, 9, 600], [90, 80, 10, -1, 600], [170, 80, 0, -1, 600], [250, 80, 12, -1, 600],
      [10, 150, 14, -1, 600]] }] } },
  ...S_UPD.map(t => ({ t: 200 + t, do: 'sample' }))]);

add('gradient', 'grad-keyframe', "a keyframe animation on style.fill through three linear gradients (a missing 0%: from the current one) with a keyframe's own easing, a loop on a radial one, and a keyframe from a linear gradient to a colour (discrete allowed: it switches at the keyframe)",
  { animation: true, graphic: [
    { type: 'rect', id: 'k3', x: 10, y: 10, shape: { width: 80, height: 50 },
      style: { fill: lin(0, 0, 0, 1, [[0, '#5070dd'], [1, '#b6d634']]) },
      keyframeAnimation: { duration: 1000, keyframes: [
        { percent: 0.4, style: { fill: lin(0, 0, 1, 0, [[0, '#ff0000'], [0.5, '#ffffff'], [1, '#00ff00']]) }, easing: 'quadraticIn' },
        { percent: 1, style: { fill: lin(1, 1, 0, 0, [[0, '#000000'], [1, '#ffffff']]) } }] } },
    { type: 'circle', id: 'kl', x: 200, y: 50, shape: { r: 30 },
      style: { fill: rad(0.5, 0.5, 0.2, [[0, '#ffffff'], [1, '#5070dd']]) },
      keyframeAnimation: { duration: 400, loop: true, keyframes: [
        { percent: 0.5, style: { fill: rad(0.3, 0.7, 0.8, [[0, '#fac858'], [1, '#ee6666']]) } },
        { percent: 1, style: { fill: rad(0.5, 0.5, 0.2, [[0, '#ffffff'], [1, '#5070dd']]) } }] } },
    { type: 'rect', id: 'kc', x: 300, y: 10, shape: { width: 50, height: 50 },
      style: { fill: lin(0, 0, 0, 1, [[0, '#5070dd'], [1, '#b6d634']]) },
      keyframeAnimation: { duration: 600, keyframes: [{ percent: 0.5, style: { fill: '#ff0000' } }, { percent: 1, style: { fill: '#00ff00' } }] } }] },
  samples([0, 1, 100, 200, 250, 299, 300, 301, 400, 500, 600, 700, 800, 1000, 1001, 1200]));

// ---- pause ----
const ENTER = { duration: 1000, easing: 'linear' };
add('pause', 'pause-chart', "the chart's animation paused at 300 and resumed at 700: no sample in between moves, after it every clip goes on 400 ms behind; a second pause and a resume while running do nothing; then a merge during a second pause (1300-1600): its flush steps every clip once, at the clock less the paused time so far, and the new clips start there",
  { animation: true, graphic: [
    { type: 'rect', id: 'a', x: 200, y: 20, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' },
      enterFrom: { x: 0 }, enterAnimation: ENTER },
    { type: 'rect', id: 'b', x: 200, y: 80, shape: { width: 20, height: 20 }, style: { fill: '#b6d634', opacity: 1 },
      enterFrom: { x: 100, style: { opacity: 0 } }, enterAnimation: { duration: 1600, easing: 'cubicOut', delay: 100 } }] },
  [...samples([0, 1, 150, 300]), { t: 300, do: 'pause' }, ...samples([301, 450]), { t: 500, do: 'pause' },
    ...samples([600, 700]), { t: 700, do: 'resume' }, ...samples([700, 701, 900, 1100]), { t: 1100, do: 'resume' },
    ...samples([1200, 1300]), { t: 1300, do: 'pause' }, ...samples([1400]),
    { t: 1450, do: 'merge', option: { graphic: [
      { id: 'a', x: 50, transition: ['x'], updateAnimation: { duration: 500, easing: 'linear' } },
      { type: 'rect', id: 'c', x: 300, y: 200, shape: { width: 20, height: 20 }, style: { fill: '#ff994d' },
        enterFrom: { y: 0 }, enterAnimation: { duration: 400, easing: 'linear' } }] } },
    ...samples([1450, 1500, 1600]), { t: 1600, do: 'resume' },
    ...samples([1601, 1700, 1800, 1900, 2000, 2200, 2500, 3000])]);

add('pause', 'pause-animator', "one element's animator paused at 200 and resumed at 600 while the chart runs: that clip counts each frame's delta as paused time and holds its value; the other element runs on; a loop's animator paused across where it would restart, then resumed (its restart forgets the paused time)",
  { animation: true, graphic: [
    { type: 'rect', id: 'p', x: 200, y: 20, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' },
      enterFrom: { x: 0 }, enterAnimation: ENTER },
    { type: 'rect', id: 'q', x: 200, y: 80, shape: { width: 20, height: 20 }, style: { fill: '#b6d634' },
      enterFrom: { x: 0 }, enterAnimation: ENTER },
    { type: 'rect', id: 'lp', x: 0, y: 150, shape: { width: 20, height: 20 }, style: { fill: '#ff994d' },
      keyframeAnimation: { duration: 300, loop: true, keyframes: [{ percent: 0, x: 0 }, { percent: 1, x: 300 }] } }] },
  [...samples([0, 100, 200]), { t: 200, do: 'pauseAnimator', id: 'p', k: 0 }, { t: 250, do: 'pauseAnimator', id: 'lp', k: 0 },
    ...samples([250, 300, 400, 500, 600]), { t: 600, do: 'resumeAnimator', id: 'p', k: 0 }, { t: 650, do: 'resumeAnimator', id: 'lp', k: 0 },
    ...samples([650, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600])]);

// [fin] the flush of a merge that touches only a series steps the graphic's clips too: one
// zrender animation holds every clip (the port's drivers flush one another while paused)
add('pause', 'pause-series-merge', "the chart's animation paused at 300; at 500 a merge that changes only the bar series' data: its flush steps the graphic element's entering clip to the clock (500), though the graphic was not in the merge; resumed at 700 the clip goes on 400 ms behind",
  { animation: true, xAxis: { type: 'category', data: ['p', 'q'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [3, 5] }],
    graphic: [{ type: 'rect', id: 'a', x: 200, y: 20, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' },
      enterFrom: { x: 0 }, enterAnimation: ENTER }] },
  [...samples([0, 1, 150, 300]), { t: 300, do: 'pause' }, ...samples([400]),
    { t: 500, do: 'merge', option: { series: [{ data: [4, 2] }] } },
    ...samples([500, 600, 700]), { t: 700, do: 'resume' }, ...samples([701, 900, 1100, 1300, 1500])]);

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option), events: [] };
    quiet(() => chart.setOption(materialize(c.option)));
    let paused = false;
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const out = clone(ev);
      const anim = zr(chart).animation;
      if (ev.do === 'sample') {
        if (!anim._paused) anim.update();
        refresh(chart);
        out.els = readEls(chart);
      }
      else if (ev.do === 'merge') quiet(() => chart.setOption(materialize(ev.option)));
      else if (ev.do === 'pause') anim.pause();
      else if (ev.do === 'resume') anim.resume();
      else if (ev.do === 'pauseAnimator') graphicEl(chart, ev.id).animators[ev.k].pause();
      else if (ev.do === 'resumeAnimator') graphicEl(chart, ev.id).animators[ev.k].resume();
      else must(false, 'an event it does not know: ' + ev.do);
      paused = anim._paused;
      rec.events.push(out);
    });
    must(!paused, c.id + ' ends paused');
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  // the value of a prop at the LAST sample at t
  const v = (id, t, key, prop) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    const e = smp.els[key];
    if (!e) return undefined;
    const r = e[prop];
    return typeof r === 'string' && /^[0-9a-f]{16}$/.test(r) ? num(r) : r;
  };
  const G = 'grad-update';
  const fillAt = (t, r) => v(G, t, 's0:' + r, 'style.fill');
  guard('a gradient tween writes new objects: rgba stops mid-way', typeof fillAt(500, 0) === 'object'
    && /^rgba\(/.test(fillAt(500, 0).stops[0][1]));
  guard('the geometry moves', num(fillAt(500, 0).x) > 0 && num(fillAt(500, 0).x) < 0.25);
  guard('two stops to three: three stops mid-way', fillAt(500, 1).stops.length === 3);
  guard('three to two: the end itself has three stops', fillAt(1100, 2).stops.length === 3
    && fillAt(1100, 2).stops[2][1] === fillAt(1100, 2).stops[1][1]);
  guard('the end of an interpolation is rgba, not the colour written', fillAt(1100, 0).stops[1][1] === 'rgba(0,255,0,1)');
  guard('radial interpolates its r', num(fillAt(350, 3).r) > 0.5 && num(fillAt(350, 3).r) < 40
    && fillAt(350, 3).global === true);
  guard('a stroke gradient', typeof v(G, 500, 's0:4', 'style.stroke') === 'object'
    && /^rgba\(/.test(v(G, 500, 's0:4', 'style.stroke').stops[0][1]));
  guard('linear to radial jumps', fillAt(201, 5).type === 'radial' && fillAt(201, 5).stops[0][1] === '#ffffff');
  guard('a colour to a gradient jumps', typeof fillAt(201, 6) === 'object' && fillAt(201, 6).stops[0][1] === '#5070dd');
  guard('a gradient to a colour jumps', fillAt(201, 7) === '#00ff00');
  guard('named colours and transparent parse', /^rgba\(/.test(fillAt(500, 8).stops[1][1]));
  const K = 'grad-keyframe';
  guard('a keyframe gradient from the current one (its own two stops: the padding went to the last keyframe)', v(K, 0, 'k3', 'style.fill').stops.length === 2
    && v(K, 0, 'k3', 'style.fill').stops[0][1] === 'rgba(80,112,221,1)');
  guard("a keyframe's easing on its segment", typeof v(K, 200, 'k3', 'style.fill') === 'object');
  guard('a gradient to a colour keyframe switches', typeof v(K, 299, 'kc', 'style.fill') === 'object'
    && v(K, 300, 'kc', 'style.fill') === '#ff0000');
  guard('a looping radial', v(K, 1200, 'kl', 'n') === 1);
  const P = 'pause-chart';
  guard('paused: nothing moves', v(P, 450, 'a', 'x') === v(P, 300, 'a', 'x') && v(P, 700, 'a', 'x') === v(P, 300, 'a', 'x'));
  guard('resumed: 400 ms behind', v(P, 900, 'a', 'x') === 200 * (500 / 1000));
  guard('the merge while paused steps the clips', v(P, 1450, 'b', 'x') !== v(P, 1400, 'b', 'x'));
  guard('a new clip during a pause holds until the resume', v(P, 1500, 'c', 'y') === v(P, 1600, 'c', 'y'));
  guard('everything ends', v(P, 3000, 'a', 'n') === 0 && v(P, 3000, 'b', 'n') === 0 && v(P, 3000, 'c', 'n') === 0);
  const A = 'pause-animator';
  guard('a paused animator holds', v(A, 500, 'p', 'x') === v(A, 200, 'p', 'x'));
  guard('the other runs on', v(A, 500, 'q', 'x') > v(A, 200, 'q', 'x'));
  guard('a resumed animator ends late', v(A, 1100, 'p', 'x') < 200 && v(A, 1500, 'p', 'x') === 200);
  guard('a paused loop holds', v(A, 400, 'lp', 'x') === v(A, 300, 'lp', 'x'));
  const S = 'pause-series-merge';
  guard('a series-only merge while paused steps the graphic clip', v(S, 600, 'a', 'x') !== v(S, 400, 'a', 'x')
    && v(S, 600, 'a', 'x') === v(S, 700, 'a', 'x'));
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    clock: { T0 },
    notes: [
      'every chart: chart._ssr false, env.node off, 400 x 300; the first setOption at T0.',
      'events in order at T0 + t; a sample is the frame loop\'s step (none while the chart\'s animation is paused) and a read of every graphic element.',
      'the frame loop never runs by itself here (no requestAnimationFrame), so it never sleeps and never resets the paused time.',
    ],
    cases: CASES.map(runCase),
  };
  out.grads = GRADS;
  out.guards = guards(out);
  return out;
}
let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (process.env.ORACLE_FORCE) fs.writeFileSync(OUT, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
let nSamples = 0;
out1.cases.forEach(q => q.events.forEach(e => { if (e.do === 'sample') nSamples++; }));
console.log(out1.cases.length + ' cases; ' + nSamples + ' samples; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
