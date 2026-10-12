/*
Upstream's own answers for roadmap D6, batch 139: KEYFRAME ANIMATION and the
rest of the TRANSITION LANGUAGE on graphic and custom elements --
animation/customGraphicKeyframeAnimation.ts (applyKeyframeAnimation: the
keyframes sorted by percent, one animator per animatable object ('', style,
shape, extra) made with el.animate(key, loop, true) and scoped 'keyframe',
the other animators' tracks on the same keys stopped, the values before it
saved; duration defaulting to the enter animation's, delay, easing for the
clip and per keyframe, loop; stopPreviousKeyframeAnimationAndRestore before
an element is updated again), animation/customGraphicTransition.ts (the
`extra` object beside shape: its final props, its transition -- `transition:
'all'`, the word 'extra', `extra.transition` -- its enterFrom and leaveTo;
`style.transition: 'all'`, `shape.transition: 'all'`; the enter / update
animation overrides carrying `additive`), and zrender's Animator underneath
(Track.addKeyframe with a keyframe's easing, prepare's percent and fillArray,
step across keyframes and across a loop's restart, the discrete values,
additive tracks and Track.setFinished reaching the track added to).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32 and zrender's width table measuring text.

  node tools/advchart-oracle/keyframe-animation.js

writes tests/fixtures/advchart-keyframe-animation.json (ORACLE_OUT
overrides). Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, notes[], cases[], guards[].

A case: id, group, note, W, H, option (as run; a custom series' renderItem
is '@name', mirrored in tests/test.advchart.keyframeanimation.pas), samplesMs
(the first state's), steps[] (each {merge option, samplesMs} | {wait ms}),
states[] (the first setOption, then every merge: {samples[]}).

A sample: {t (ms after that state's setOption), els {key: snap}}. A key is a
graphic element's id, or a custom element's 's<series>:<raw index>' with
'/<child>' for each level down, and '#label' for a textContent.

A snap: the eleven transform props (x, y, rotation, scaleX, scaleY, originX,
originY, skewX, skewY, anchorX, anchorY); 'style.<k>' for opacity, fill,
stroke, lineWidth, text, fontSize where el.style[k] (the prototype's
included) is not null; 'shape.<k>' and 'extra.<k>' for every own key that is
not null and not transition / enterFrom / leaveTo; n, the element's
animators that still have a clip (an animator whose every track another one
stopped stays in el.animators with no clip; the port frees it). A custom
textContent ('#label') has no opacity and no n: LabelManager fades a new
series label in on its own animator, which the port does not do for a
custom series' textContent.

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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-keyframe-animation.json');

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
function valRec(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(valRec);
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
function customSeries(chart) {
  const out = [];
  chart.getModel().eachRawSeries(s => {
    if (s.subType === 'custom') out.push(s);
  });
  return out;
}

// ---------------------------------------------------------------------------
// the renderItems (each mirrored in tests/test.advchart.keyframeanimation.pas)
// ---------------------------------------------------------------------------
const RENDER = {
  // item 0: a rect with a looping keyframe on its rotation and its style's
  // opacity, and a textContent with a keyframe of its own; item 1: a circle
  // whose shape keyframes only while its y is at most 100; item 2: a group
  // scaling once, a child looping its x, a child taking the series' duration
  kfItem(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const i = params.dataIndex;
    if (i === 0) {
      return { type: 'rect', x: x, y: y, shape: { x: -10, y: -10, width: 20, height: 20 }, style: { fill: '#5070dd' },
        keyframeAnimation: { duration: 600, loop: true, keyframes: [
          { percent: 0.5, rotation: 1, style: { opacity: 0.4 } },
          { percent: 1, rotation: 0, style: { opacity: 1 } }] },
        textContent: { style: { text: 'A', fill: '#000000' },
          keyframeAnimation: { duration: 300, keyframes: [{ percent: 1, style: { fill: '#ff0000' } }] } },
        textConfig: { position: 'top' } };
    }
    if (i === 1) {
      return { type: 'circle', x: x, y: y, shape: { r: 10 }, style: { fill: '#b6d634' },
        keyframeAnimation: y > 100 ? null : { duration: 1000, keyframes: [
          { percent: 0.3, shape: { r: 20 } },
          { percent: 1, shape: { r: 5 }, easing: 'elasticOut' }] } };
    }
    return { type: 'group', x: x, y: y,
      keyframeAnimation: { duration: 800, keyframes: [{ percent: 0.5, scaleX: 2 }, { percent: 1, scaleX: 1 }] },
      children: [
        { type: 'rect', shape: { x: -5, y: -5, width: 10, height: 10 }, style: { fill: '#ff994d' },
          keyframeAnimation: { duration: 400, loop: true, keyframes: [{ percent: 1, x: 20 }] } },
        { type: 'circle', shape: { r: 3 }, style: { fill: '#000000' },
          keyframeAnimation: { keyframes: [{ percent: 1, shape: { r: 6 } }] } }] };
  },
  // a transition language item: extra with enterFrom, 'all' on the style
  // and the shape, and an additive update on x
  trItem(params, api) {
    const x = api.value(0);
    const y = api.value(1);
    const i = params.dataIndex;
    if (i === 0) {
      return { type: 'rect', x: x, y: y, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' },
        extra: { k: y, enterFrom: { k: 0 } }, transition: ['x', 'extra'] };
    }
    return { type: 'circle', x: x, y: y, shape: { r: y / 10, transition: 'all' },
      style: { fill: y > 100 ? '#ff0000' : '#b6d634', lineWidth: y / 20, stroke: '#333333', transition: 'all' },
      updateAnimation: { duration: 400, easing: 'linear', additive: true } };
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

// ---------------------------------------------------------------------------
// reading the elements
// ---------------------------------------------------------------------------
const TKEYS = ['x', 'y', 'rotation', 'scaleX', 'scaleY', 'originX', 'originY', 'skewX', 'skewY', 'anchorX', 'anchorY'];
const SNAP_STYLE = ['opacity', 'fill', 'stroke', 'lineWidth', 'text', 'fontSize'];
const SKIP = { transition: 1, enterFrom: 1, leaveTo: 1 };
function snap(el, isLabel) {
  const o = {};
  for (const k of TKEYS) o[k] = hex(el[k]);
  if (el.style) {
    for (const k of SNAP_STYLE) {
      if (isLabel && k === 'opacity') continue;
      if (el.style[k] != null) o['style.' + k] = valRec(el.style[k]);
    }
  }
  if (el.shape && !el.isGroup) {
    for (const k of Object.keys(el.shape)) {
      if (SKIP[k] || el.shape[k] == null) continue;
      o['shape.' + k] = valRec(el.shape[k]);
    }
  }
  if (el.extra) {
    for (const k of Object.keys(el.extra)) {
      if (SKIP[k] || el.extra[k] == null) continue;
      o['extra.' + k] = valRec(el.extra[k]);
    }
  }
  if (!isLabel) o.n = el.animators.filter(a => a.getClip()).length;
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
  customSeries(chart).forEach(s => {
    const cv = chart.getViewOfSeriesModel(s);
    if (!cv) return;
    const data = s.getData();
    const walkC = (el, key) => {
      els[key] = snap(el);
      const tc = el.getTextContent && el.getTextContent();
      if (tc) els[key + '#label'] = snap(tc, true);
      if (el.isGroup) el.childrenRef().forEach((c, k) => walkC(c, key + '/' + k));
    };
    cv.group.childrenRef().forEach(el => {
      const ecd = ecDataOf(el);
      must(ecd && ecd.dataIndex != null, 'a custom root without a data index');
      walkC(el, 's' + s.seriesIndex + ':' + data.getRawIndex(ecd.dataIndex));
    });
  });
  return els;
}
function samplesOf(chart, start, times) {
  const z = zr(chart);
  return times.map(t => {
    NOW = start + t;
    z.animation.update();
    refresh(chart);
    return { t, els: readEls(chart) };
  });
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
function add(group, id, note, option, more) {
  CASES.push(Object.assign({ group, id, note, W: 400, H: 300, option, steps: [] }, more));
}

const S1 = [0, 1, 100, 199, 200, 250, 300, 350, 400, 499, 500, 600, 700, 800, 900, 1000, 1001, 1500];
add('keyframe', 'kf-graphic', "graphic keyframes: a missing 0% (from the current value) with a keyframe's easing; keyframes out of order with a bounceOut one and the clip's quadraticInOut; style colours and opacity with the shape and a delay; points of changing length; extra, a number and a discrete text; a text's discrete text and its fontSize; the enter duration when none is written (600); a group (no style, no shape); a cubic-bezier keyframe; an array of two on the root (the second stops the first's x)",
  { animation: true, animationDuration: 600, graphic: [
    { type: 'rect', id: 'move', x: 20, y: 20, shape: { width: 40, height: 20 }, style: { fill: '#5070dd' },
      keyframeAnimation: { duration: 1000, keyframes: [{ percent: 0.5, x: 200, easing: 'cubicOut' }, { percent: 1, x: 50, y: 100 }] } },
    { type: 'rect', id: 'order', x: 100, y: 150, shape: { x: -20, y: -10, width: 40, height: 20 }, style: { fill: '#b6d634' },
      keyframeAnimation: { duration: 800, easing: 'quadraticInOut', keyframes: [
        { percent: 1, rotation: 0, scaleX: 1 }, { percent: 0, rotation: 1, scaleX: 2 },
        { percent: 0.3, rotation: -0.5, scaleX: 0.5, easing: 'bounceOut' }] } },
    { type: 'circle', id: 'sty', x: 300, y: 60, shape: { r: 20 }, style: { fill: '#b6d634', opacity: 1 },
      keyframeAnimation: { duration: 600, delay: 200, keyframes: [
        { percent: 0, style: { fill: '#ff0000', opacity: 0.2 }, shape: { r: 5 } },
        { percent: 0.6, style: { fill: 'rgba(0,0,255,0.5)' }, shape: { r: 30 } },
        { percent: 1, style: { fill: '#b6d634', opacity: 1 }, shape: { r: 20 } }] } },
    { type: 'polygon', id: 'pts', shape: { points: [[10, 250], [60, 250], [35, 200]] }, style: { fill: '#ff994d' },
      keyframeAnimation: { duration: 1000, keyframes: [
        { percent: 0.5, shape: { points: [[10, 280], [90, 250], [35, 180], [5, 5]] } },
        { percent: 1, shape: { points: [[10, 250], [60, 250]] } }] } },
    { type: 'rect', id: 'ext', x: 150, y: 250, shape: { width: 30, height: 30 }, style: { fill: '#0ca8df' }, extra: { k: 1, s: 'a' },
      keyframeAnimation: { duration: 500, keyframes: [{ percent: 0.5, extra: { k: 10 } }, { percent: 1, extra: { k: 2, s: 'b' } }] } },
    { type: 'text', id: 'txt', x: 250, y: 200, style: { text: 'one', fill: '#333333', fontSize: 14 },
      keyframeAnimation: { duration: 900, keyframes: [
        { percent: 0.4, style: { text: 'two', fill: '#ff0000' } }, { percent: 1, style: { text: 'three', fontSize: 20 } }] } },
    { type: 'rect', id: 'nodur', x: 20, y: 200, shape: { width: 30, height: 10 }, style: { fill: '#fac858' },
      keyframeAnimation: { keyframes: [{ percent: 1, x: 120 }] } },
    { type: 'group', id: 'grp', x: 200, y: 120,
      keyframeAnimation: { duration: 700, keyframes: [{ percent: 0.5, scaleX: 2, scaleY: 0.5, style: { opacity: 0 } }, { percent: 1, scaleX: 1, scaleY: 1 }] },
      children: [{ type: 'rect', id: 'grp.r', shape: { x: -10, y: -10, width: 20, height: 20 }, style: { fill: '#0ca8df' } }] },
    { type: 'rect', id: 'cubic', x: 300, y: 250, shape: { width: 20, height: 20 }, style: { fill: '#3ba272' },
      keyframeAnimation: { duration: 1000, keyframes: [{ percent: 0, y: 250 }, { percent: 1, y: 150, easing: 'cubic-bezier(0.3, 0.1, 0.2, 1)' }] } },
    { type: 'rect', id: 'two', x: 0, y: 0, shape: { width: 10, height: 10 }, style: { fill: '#9a60b4' },
      keyframeAnimation: [{ duration: 400, keyframes: [{ percent: 1, x: 100 }] },
        { duration: 1000, easing: 'linear', keyframes: [{ percent: 1, y: 100, x: 50 }] }] }] },
  { samplesMs: S1 });

add('keyframe', 'kf-off', 'animation off: no keyframe runs, every element at its own props',
  { animation: false, graphic: [
    { type: 'rect', id: 'off', x: 20, y: 20, shape: { width: 40, height: 20 }, style: { fill: '#5070dd' },
      keyframeAnimation: { duration: 1000, keyframes: [{ percent: 0, x: 0 }, { percent: 1, x: 200 }] } }] },
  { samplesMs: [0, 500] });

const SL = [0, 50, 100, 101, 150, 300, 499, 500, 501, 700, 900, 901, 1300, 1700, 2000];
add('loop', 'kf-loop', "loops: x out and back with a delay; y and opacity with no 0% and no 100% keyframe; a shape and a colour under sinusoidalInOut; a full turn -- then an update mid-loop: a new non-looping keyframe from the restored x; a style change that stops and restores (no keyframe); 'all' with a keyframe on the opacity the update transition animates (its track stopped back to its start); a transition on x beside a root keyframe on x (a root keyframe does not stop it)",
  { animation: true, graphic: [
    { type: 'rect', id: 'lp1', x: 0, y: 20, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' },
      keyframeAnimation: { duration: 400, loop: true, delay: 100, keyframes: [
        { percent: 0, x: 0 }, { percent: 0.5, x: 100, easing: 'quadraticOut' }, { percent: 1, x: 0 }] } },
    { type: 'rect', id: 'lp2', x: 50, y: 80, shape: { width: 20, height: 20 }, style: { fill: '#b6d634', opacity: 1 },
      keyframeAnimation: { duration: 300, loop: true, keyframes: [
        { percent: 0.25, y: 120, style: { opacity: 0.3 } }, { percent: 0.75, y: 60, style: { opacity: 0.9 } }] } },
    { type: 'circle', id: 'lp3', x: 200, y: 150, shape: { r: 10 }, style: { fill: '#ff994d' },
      keyframeAnimation: { duration: 500, loop: true, easing: 'sinusoidalInOut', keyframes: [
        { percent: 0.5, shape: { r: 30 }, style: { fill: '#0000ff' } }, { percent: 1, shape: { r: 10 }, style: { fill: '#ff994d' } }] } },
    { type: 'rect', id: 'lp4', x: 300, y: 200, shape: { width: 20, height: 20 }, style: { fill: '#fac858' },
      keyframeAnimation: { duration: 600, loop: true, keyframes: [{ percent: 1, rotation: 6.283185307179586 }] } }] },
  { samplesMs: SL, steps: [
    { merge: { graphic: [
      { id: 'lp1', keyframeAnimation: { duration: 1000, keyframes: [{ percent: 1, x: 300 }] } },
      { id: 'lp2', style: { fill: '#ff0000' } },
      { id: 'lp3', shape: { r: 40 }, style: { fill: '#000000', opacity: 0.8 }, transition: 'all',
        keyframeAnimation: { duration: 400, keyframes: [{ percent: 1, style: { opacity: 0.5 } }] } },
      { id: 'lp4', x: 350, transition: ['x'],
        keyframeAnimation: { duration: 600, loop: true, keyframes: [{ percent: 0.5, x: 250 }, { percent: 1, x: 350 }] } }] },
      samplesMs: [0, 1, 100, 250, 400, 500, 600, 1000, 1001, 1500] }] });

add('additive', 'kf-additive', "additive updates: x 0 to 200 over 1000 ms, then 300 ms in an additive 400 ms to 100 (ending first: the track it adds to is finished with it), an additive 1200 ms cubicOut to 50 (ending last), an additive colour, and the same move without additive (the first one stopped)",
  { animation: true, graphic: [
    { type: 'rect', id: 'ad1', x: 0, y: 20, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' } },
    { type: 'rect', id: 'ad2', x: 0, y: 80, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' } },
    { type: 'circle', id: 'adc', x: 100, y: 200, shape: { r: 10 }, style: { fill: '#ff0000' } },
    { type: 'rect', id: 'adn', x: 0, y: 140, shape: { width: 20, height: 20 }, style: { fill: '#5070dd' } }] },
  { samplesMs: [0, 1000], steps: [
    { merge: { graphic: [
      { id: 'ad1', x: 200, transition: ['x'], updateAnimation: { duration: 1000, easing: 'linear' } },
      { id: 'ad2', x: 200, transition: ['x'], updateAnimation: { duration: 1000, easing: 'linear' } },
      { id: 'adc', style: { fill: '#0000ff' }, transition: 'style', updateAnimation: { duration: 1000, easing: 'linear' } },
      { id: 'adn', x: 200, transition: ['x'], updateAnimation: { duration: 1000, easing: 'linear' } }] },
      samplesMs: [0, 100, 300] },
    { merge: { graphic: [
      { id: 'ad1', x: 100, transition: ['x'], updateAnimation: { duration: 400, easing: 'linear', additive: true } },
      { id: 'ad2', x: 50, transition: ['x'], updateAnimation: { duration: 1200, easing: 'cubicOut', additive: true } },
      { id: 'adc', style: { fill: '#00ff00' }, transition: 'style', updateAnimation: { duration: 500, additive: true } },
      { id: 'adn', x: 100, transition: ['x'], updateAnimation: { duration: 400, easing: 'linear' } }] },
      samplesMs: [0, 1, 100, 200, 300, 400, 500, 699, 700, 701, 800, 1000, 1200, 1500] }] });

add('transition', 'kf-transition', "the transition language on extra and 'all': extra's enterFrom with an enterAnimation; transition 'all' moving extra; extra.transition naming one key; the word 'extra' with an updateAnimation and a delay; style.transition 'all' and shape.transition 'all'; the words 'shape' and 'style'; then removes with a leaveTo on extra and on the style given in the remove itself, and one with none",
  { animation: true, graphic: [
    { type: 'rect', id: 'tx', x: 50, y: 50, shape: { width: 40, height: 20 }, style: { fill: '#5070dd', opacity: 1, enterFrom: { opacity: 0 } },
      extra: { k: 10, enterFrom: { k: 0 } }, enterAnimation: { duration: 400, easing: 'linear' } },
    { type: 'rect', id: 'ta', x: 50, y: 120, shape: { width: 40, height: 20 }, style: { fill: '#b6d634' }, extra: { k: 1, j: 2 } },
    { type: 'rect', id: 'tl', x: 50, y: 190, shape: { width: 40, height: 20 }, style: { fill: '#ff994d' }, extra: { k: 1 } },
    { type: 'circle', id: 'ts', x: 250, y: 80, shape: { r: 10 }, style: { fill: '#0ca8df', lineWidth: 1, stroke: '#000000' } },
    { type: 'circle', id: 'tsa', x: 250, y: 160, shape: { r: 10, cx: 0 }, style: { fill: '#fac858' } }] },
  { samplesMs: [0, 1, 100, 200, 400, 401, 1000, 1001], steps: [
    { merge: { graphic: [
      { id: 'tx', extra: { k: 20 }, transition: 'all' },
      { id: 'ta', extra: { k: 5, j: 9, transition: ['k'] } },
      { id: 'tl', extra: { k: 3 }, transition: ['extra'], updateAnimation: { duration: 300, easing: 'linear', delay: 50 } },
      { id: 'ts', style: { fill: '#ff0000', lineWidth: 5, transition: 'all' }, shape: { r: 30, transition: 'all' } },
      { id: 'tsa', shape: { r: 30, cx: 20 }, style: { fill: '#000000' }, transition: ['shape', 'style'] }] },
      samplesMs: [0, 1, 50, 100, 250, 300, 351, 500, 501, 1000] },
    { merge: { graphic: [
      { id: 'tl', $action: 'remove', extra: { leaveTo: { k: 0 } }, style: { leaveTo: { opacity: 0 } } },
      { id: 'ta', $action: 'remove' }] },
      samplesMs: [0, 1, 250, 500, 501] }] });

add('custom', 'kf-custom', "custom elements: a looping rotation and opacity with a textContent keyframing its fill; a circle's shape keyframes with an elasticOut keyframe; a group scaling once with a looping child and a child on the series' duration (800) -- then new data: every element stopped and restored before the default ['x', 'y'] transition, the circle (now below 100) keyframes no more, the others start again",
  { animation: true, series: [{ type: 'custom', coordinateSystem: 'none', renderItem: '@kfItem', animationDuration: 800,
    data: [[50, 60], [150, 60], [250, 60]] }] },
  { samplesMs: [0, 1, 100, 150, 300, 301, 450, 600, 601, 800, 1000, 1200], steps: [
    { merge: { series: [{ data: [[60, 70], [150, 160], [260, 60]] }] },
      samplesMs: [0, 1, 100, 200, 300, 301, 600, 1000, 1001] }] });

add('custom', 'kf-custom-tr', "custom transitions: extra with its enterFrom, transition ['x', 'extra']; a circle with shape.transition 'all' and style.transition 'all' under an additive updateAnimation, updated twice 200 ms apart",
  { animation: true, series: [{ type: 'custom', coordinateSystem: 'none', renderItem: '@trItem', animationDuration: 500,
    data: [[50, 60], [150, 60]] }] },
  { samplesMs: [0, 1, 250, 500, 501], steps: [
    { merge: { series: [{ data: [[100, 90], [150, 120]] }] }, samplesMs: [0, 1, 100, 200] },
    { merge: { series: [{ data: [[150, 120], [150, 200]] }] }, samplesMs: [0, 1, 100, 200, 300, 400, 401, 600, 1000] }] });

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const rec = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option),
      samplesMs: c.samplesMs, steps: clone(c.steps), states: [] };
    let start = NOW;
    quiet(() => chart.setOption(materialize(c.option)));
    rec.states.push({ samples: samplesOf(chart, start, c.samplesMs) });
    let clock = start + c.samplesMs[c.samplesMs.length - 1];
    c.steps.forEach((step, i) => {
      if (step.wait !== undefined) {
        clock += step.wait;
        NOW = clock;
        zr(chart).animation.update();
        return;
      }
      must(step.merge && step.samplesMs, c.id + ' step ' + i + ': a merge with its samples');
      NOW = clock;
      start = clock;
      quiet(() => chart.setOption(materialize(step.merge)));
      rec.states.push({ samples: samplesOf(chart, start, step.samplesMs) });
      clock = start + step.samplesMs[step.samplesMs.length - 1];
    });
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
  // a value: case, state, sample time, key, prop
  const v = (id, si, t, key, prop) => {
    const smp = cs(id).states[si].samples.find(q => q.t === t);
    must(smp, id + ': no sample at ' + t);
    const e = smp.els[key];
    if (!e) return undefined;
    const r = e[prop];
    return typeof r === 'string' && /^[0-9a-f]{16}$/.test(r) ? num(r) : r;
  };
  const K = 'kf-graphic';
  guard('a missing 0% starts from the current x', v(K, 0, 0, 'move', 'x') === 20);
  guard("a keyframe's cubicOut eases its segment", v(K, 0, 250, 'move', 'x') > 20 + (200 - 20) / 2);
  guard('the second keyframe runs back', v(K, 0, 1000, 'move', 'x') === 50 && v(K, 0, 1000, 'move', 'y') === 100);
  guard('keyframes are sorted by percent: rotation starts at 1', v(K, 0, 0, 'order', 'rotation') === 1);
  guard('the order case ends at its 100% keyframe', v(K, 0, 800, 'order', 'rotation') === 0);
  guard('a delay holds the 0% keyframe', v(K, 0, 100, 'sty', 'style.fill') === 'rgba(255,0,0,1)' && v(K, 0, 100, 'sty', 'shape.r') === 5);
  guard('a colour keyframe interpolates in rgba', /^rgba\(/.test(v(K, 0, 400, 'sty', 'style.fill')));
  guard('points keep the length of the last keyframe where it is shorter',
    Array.isArray(v(K, 0, 500, 'pts', 'shape.points')) && v(K, 0, 500, 'pts', 'shape.points').length === 3);
  guard('extra animates a number', (v(K, 0, 250, 'ext', 'extra.k')) === 10);
  guard('extra switches a text discretely', v(K, 0, 499, 'ext', 'extra.s') === 'a' && v(K, 0, 500, 'ext', 'extra.s') === 'b');
  guard("a text's text switches discretely", v(K, 0, 300, 'txt', 'style.text') === 'one' && v(K, 0, 400, 'txt', 'style.text') === 'two'
    && v(K, 0, 900, 'txt', 'style.text') === 'three');
  guard('no duration takes the enter duration (600)', v(K, 0, 600, 'nodur', 'x') === 120 && v(K, 0, 500, 'nodur', 'x') < 120);
  guard('a group keyframes its scale, not a style it has not', v(K, 0, 350, 'grp', 'scaleX') === 2 && v(K, 0, 350, 'grp', 'style.opacity') === undefined);
  guard('a cubic-bezier keyframe', v(K, 0, 500, 'cubic', 'y') !== 200);
  guard('the second root keyframe animation stops the first on x', v(K, 0, 400, 'two', 'x') === 20 && v(K, 0, 1000, 'two', 'x') === 50);
  const endEls = cs(K).states[0].samples.find(q => q.t === 1500).els;
  guard('everything ends', Object.keys(endEls).every(k => endEls[k].n === 0));
  guard('the first root keyframe animator of two is gone once its x is stopped', v(K, 0, 100, 'two', 'n') === 1);
  guard('animation off runs nothing', v('kf-off', 0, 0, 'off', 'x') === 20 && v('kf-off', 0, 0, 'off', 'n') === 0);
  const L = 'kf-loop';
  guard('a loop holds its delay', v(L, 0, 50, 'lp1', 'x') === 0);
  guard('a loop restarts', v(L, 0, 500, 'lp1', 'x') === 0 && v(L, 0, 300, 'lp1', 'x') > 99);
  guard('a loop with no 0% starts from the current y', v(L, 0, 0, 'lp2', 'y') === 80);
  guard('loops keep running', cs(L).states[0].samples.find(q => q.t === 2000).els.lp1.n === 1);
  guard('a new keyframe starts from the restored x', v(L, 1, 0, 'lp1', 'x') === 0 && v(L, 1, 1000, 'lp1', 'x') === 300);
  guard('an update without a keyframe restores', v(L, 1, 0, 'lp2', 'y') === 80 && v(L, 1, 0, 'lp2', 'style.opacity') === 1
    && v(L, 1, 0, 'lp2', 'n') === 0);
  guard('the restored r is where the update transition starts', v(L, 1, 0, 'lp3', 'shape.r') === 10);
  guard('a keyframe on the opacity stops the update transition there', v(L, 1, 400, 'lp3', 'style.opacity') === 0.5);
  guard('a root keyframe beside a transition on x', v(L, 1, 250, 'lp4', 'x') !== v(L, 1, 250, 'lp4', 'x') + 1 && v(L, 1, 100, 'lp4', 'n') >= 2);
  const A = 'kf-additive';
  guard('an additive move adds to the running one', v(A, 2, 100, 'ad1', 'x') !== v(A, 2, 100, 'adn', 'x'));
  guard('an additive track that ends first finishes the one it adds to', v(A, 2, 700, 'ad1', 'x') === v(A, 2, 1000, 'ad1', 'x'));
  guard('an additive colour', /^rgba\(/.test(v(A, 2, 200, 'adc', 'style.fill')));
  guard('without additive the first one stops', v(A, 2, 400, 'adn', 'x') === 100);
  const T = 'kf-transition';
  guard("extra's enterFrom", v(T, 0, 0, 'tx', 'extra.k') === 0 && v(T, 0, 400, 'tx', 'extra.k') === 10);
  guard("'all' moves extra", v(T, 1, 250, 'tx', 'extra.k') > 10 && v(T, 1, 250, 'tx', 'extra.k') < 20);
  guard('extra.transition names k only', v(T, 1, 250, 'ta', 'extra.k') > 1 && v(T, 1, 0, 'ta', 'extra.j') === 9);
  guard("the word 'extra' with a delay", v(T, 1, 50, 'tl', 'extra.k') === 1 && v(T, 1, 351, 'tl', 'extra.k') === 3);
  guard("style.transition 'all' and shape.transition 'all'", v(T, 1, 250, 'ts', 'shape.r') > 10 && v(T, 1, 250, 'ts', 'style.lineWidth') > 1);
  guard('a leaveTo on extra', v(T, 2, 250, 'tl', 'extra.k') < 3 && v(T, 2, 501, 'tl', 'x') === undefined);
  guard('a remove with none is gone at once', v(T, 2, 0, 'ta', 'x') === undefined);
  const C = 'kf-custom';
  guard('a custom loop', v(C, 0, 300, 's0:0', 'rotation') === 1 && v(C, 0, 600, 's0:0', 'rotation') === 0);
  guard("a textContent's keyframe", v(C, 0, 300, 's0:0#label', 'style.fill') === 'rgba(255,0,0,1)');
  guard("the series' duration for a keyframe with none", v(C, 0, 800, 's0:2/1', 'shape.r') === 6 && v(C, 0, 600, 's0:2/1', 'shape.r') < 6);
  guard('custom: restored before the transition', v(C, 1, 0, 's0:0', 'rotation') === 0);
  guard('custom: no keyframe on the next render stops it', v(C, 1, 1000, 's0:1', 'shape.r') === 10);
  const CT = 'kf-custom-tr';
  guard("custom extra's enterFrom", v(CT, 0, 0, 's0:0', 'extra.k') === 0 && v(CT, 0, 500, 's0:0', 'extra.k') === 60);
  guard('custom additive style', /^rgba\(/.test(v(CT, 2, 100, 's0:1', 'style.fill')));
  return g;
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    clock: { T0 },
    notes: [
      'every chart: chart._ssr false, env.node off, 400 x 300.',
      'each state samples the clock at its samplesMs after its setOption (the first, then each merge at the instant the previous state\'s last sample left).',
      'a custom series\' renderItem is a JavaScript function here and a Pascal handler in the port.',
    ],
    cases: CASES.map(runCase),
  };
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
out1.cases.forEach(q => q.states.forEach(s => { nSamples += s.samples.length; }));
console.log(out1.cases.length + ' cases; ' + nSamples + ' samples; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : ''));
if (bad.length || !deterministic || nul || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
