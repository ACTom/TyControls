// AN5 (batch 96): full-update transitions -- a legend toggle, a dataZoom and
// a roam, which upstream renders as a full update of the SAME option (no
// setOption): a series the legend switches off is its view's remove() (a
// bar fades, a line's symbols fade and shrink, the polyline goes at once), a
// series switched back on enters as new (its view kept no data), the rest
// update; the axes groupTransition their labels, ticks, split lines and line
// by anid (util/graphic.ts groupTransition); a dataZoom from the inside roam
// or a realtime slider carries `animation: {easing: 'cubicOut', duration:
// 100}` in its payload, which overrides every enter / update / leave timing
// of that update (basicTransition.ts getAnimationConfig); a graph pan is
// `{duration: 0}`. Also a hover held through a legend toggle and through a
// notMerge setOption (the reused element keeps its hoverState and its
// __highByOuter bits).
//
// The harness is state-anim.js' own, copied: the replaced Date before the
// dist, chart._ssr = false, env.node = false, the seeded Math.random,
// hand-stepped frames. A STEP IS ONE FRAME: at each sample time t (ms after
// T1) the events of t, then NOW = T1 + t and zr.animation.update(), unless a
// setOption flushed. Recorded per sample: every element of every series view
// (removed views too: their elements fade in their groups), by identity, as
// state-anim.js records them, plus the scopes of its animators; and every
// leaf of every cartesian axis view's _axisGroup that has an anid, BY ANID
// (each render makes new ones): x, y, rotation, the shape's keys, the text.
//
// Run: node tools/advchart-oracle/full-update-anim.js
//   -> tests/fixtures/advchart-full-update-anim.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-full-update-anim.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 101, 116, 150, 200, 201, 250, 300, 301, 350, 400, 401, 416, 450, 500, 501,
  600, 700, 701, 716, 750, 800, 801, 900, 1000, 1100, 1200, 1201, 1300, 1500, 1700, 1701, 1800, 2000];

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

// ---------- element snapshots ----------
const TRANSFORM_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation', 'originX', 'originY'];
const STYLE_KEYS = ['opacity', 'fill', 'stroke', 'lineWidth', 'text', 'x', 'y', 'strokePercent'];
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
  if (typeof el.z2 === 'number') put('z2', el.z2);
  put('states', (el.currentStates || []).join(','));
  if (el.style) for (const k of STYLE_KEYS) if (el.style[k] != null) put('style.' + k, el.style[k]);
  if (el.style && el.style.stroke === null && el.type !== 'text') put('style.stroke', 'null');
  if (el.shape) for (const k of Object.keys(el.shape)) if (el.shape[k] != null) put('shape.' + k, el.shape[k]);
  return o;
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// the walk of one view: [{el, role, path}]
function walkView(root) {
  const out = [];
  const visit = (el, p) => {
    out.push({ el, role: 'el', path: p, host: el });
    const label = el.getTextContent && el.getTextContent();
    if (label) out.push({ el: label, role: 'label', path: p + '#label', host: el });
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    if (guide) out.push({ el: guide, role: 'guide', path: p + '#guide', host: el });
    if (el.isGroup) el.childrenRef().forEach((c, i) => visit(c, p === '' ? String(i) : p + '.' + i));
  };
  visit(root, '');
  return out;
}

// EVERY series view, a removed one too (a legend's switched-off series keeps
// its view; its elements fade in its group)
function seriesViews(chart) {
  const out = [];
  for (const v of chart._chartsViews) {
    const s = v.__model;
    if (!s) continue;
    out.push({ owner: 'series' + s.seriesIndex + ':' + s.subType, group: v.group });
  }
  return out;
}

// the cartesian axis views: their _axisGroup's leaves with an anid
function axisLeaves(chart) {
  const out = [];
  for (const v of chart._componentsViews) {
    const m = v.__model;
    if (!m || (m.mainType !== 'xAxis' && m.mainType !== 'yAxis') || !v._axisGroup) continue;
    const owner = m.mainType + m.componentIndex;
    v._axisGroup.traverse(el => {
      if (!el.isGroup && el.anid) out.push({ owner, el, id: owner + '/' + el.anid });
    });
  }
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

// the state animators of an element: their __fromStateTransition names
function stateAnims(el) {
  return (el.animators || []).filter(a => a.__fromStateTransition).map(a => a.__fromStateTransition + ':' + (a.targetName || ''));
}
// the scopes of its animators, sorted
function scopesOf(el) {
  return (el.animators || []).map(a => (a.scope == null ? '' : a.scope) + ':' + (a.targetName || '')).sort().join(' ');
}

// ---------- the timeline ----------
function raw(x, y, extra) {
  return Object.assign({ zrX: x, zrY: y, which: 1, cancelBubble: false, preventDefault() {}, stopPropagation() {} },
    extra || {});
}

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
  let live = 0;
  for (let c = zr.animation._head; c; c = c.next) if (!c.loop) live++;
  must(live === 0, 'the first render did not settle');
}

// the place to point at for an element: a rect's centre, a sector's middle,
// a symbol group's position
function aimOf(chart, seriesIndex, dataIndex) {
  const model = chart.getModel().getSeriesByIndex(seriesIndex);
  const data = model.getData();
  const el = data.getItemGraphicEl(dataIndex);
  must(el, 'no element for ' + seriesIndex + '/' + dataIndex);
  if (el.type === 'rect') {
    const s = el.shape;
    return [Math.round(s.x + s.width / 2), Math.round(s.y + s.height / 2)];
  }
  if (el.type === 'sector') {
    const s = el.shape;
    const mid = (s.startAngle + s.endAngle) / 2;
    const r = (s.r0 + s.r) / 2;
    return [Math.round(s.cx + Math.cos(mid) * r), Math.round(s.cy + Math.sin(mid) * r)];
  }
  return [Math.round(el.x), Math.round(el.y)];
}

// a slider dataZoom's places: a handle's centre, a point on its panel at a
// fraction of its length
function sliderView(chart) {
  const v = chart._componentsViews.find(x => x.__model && x.__model.mainType === 'dataZoom' && x._displayables);
  must(v, 'no slider view');
  return v;
}
function sliderAim(chart, what) {
  const v = sliderView(chart);
  const g = v._displayables.sliderGroup;
  const tr = g.transform || [1, 0, 0, 1, 0, 0];
  const app = p => [Math.round(tr[0] * p[0] + tr[2] * p[1] + tr[4]), Math.round(tr[1] * p[0] + tr[3] * p[1] + tr[5])];
  if (what === 'handle0' || what === 'handle1') return app([v._handleEnds[what === 'handle0' ? 0 : 1], v._size[1] / 2]);
  must(typeof what === 'number', 'unknown slider aim ' + what);
  return app([v._size[0] * what, v._size[1] / 2]);
}

// summarize the per-sample records into fixture elements
function summarize(recs) {
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
    let id = rec.id;
    if (!rec.axis) id += (rec.role !== 'el' && !rec.id.includes('#') ? '#' + rec.role : '');
    const n = seen.get(id) || 0;
    seen.set(id, n + 1);
    if (n) id += '~' + n;
    const everAnim = rec.anim.some(x => x > 0);
    const everState = rec.stateAnim.some(x => x !== '');
    // the data index (a label's or a label line's: its host's) where it
    // changes: a legend's filter moves the rows of a pie
    const diSet = new Set(presentIdx.map(i => rec.dis[i]));
    elements.push({
      id, owner: rec.owner, role: rec.role, type: rec.type, dataIndex: rec.dataIndex,
      dataIndices: diSet.size > 1 ? rec.dis : null,
      present: presentIdx.length === SAMPLES.length ? null : presentIdx,
      final, finalText,
      track: Object.keys(track).length ? track : null,
      trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null,
      scopes: everAnim ? rec.scopes : null,
      stateAnimators: everState ? rec.stateAnim : null,
      transition: rec.transition.some(x => x !== '') ? rec.transition : null,
    });
  }
  return elements;
}

function eventsOut(events) {
  return events.map(e => {
    const o = { at: e.at, type: e.type };
    if (e.x != null) { o.x = e.x; o.y = e.y; }
    if (e.delta != null) o.delta = e.delta;
    if (e.series != null) { o.series = e.series; o.index = e.index; }
    if (e.payload) o.payload = e.payload;
    if (e.option) o.option = e.option;
    return o;
  });
}

function newRec(id, owner, role, type, dataIndex, axis) {
  return {
    id, owner, role, type, dataIndex, axis,
    snaps: new Array(SAMPLES.length).fill(null),
    anim: new Array(SAMPLES.length).fill(0),
    dis: new Array(SAMPLES.length).fill(null),
    scopes: new Array(SAMPLES.length).fill(''),
    stateAnim: new Array(SAMPLES.length).fill(''),
    transition: new Array(SAMPLES.length).fill(''),
  };
}

// the frame loop: at each sample, its events, then one frame (unless a
// setOption flushed), then the record
function loopOn(chart, c, t1) {
  const zr = chart.getZr();
  const h = zr.handler;
  const events = c.events.map(e => Object.assign({}, e));
  const ids = new Map();
  const axisIds = new Map();
  const recs = [];
  const clips = [];
  const payloads = [];
  let last = [0, 0];
  // every update's payload, its animation part ("(none)" for none) -- the
  // inside roam and the slider dispatch through the API, not the instance
  const proto = Object.getPrototypeOf(chart.getModel());
  const od = proto.setUpdatePayload;
  proto.setUpdatePayload = function (p) {
    if (p && p.type && (p.type === 'dataZoom' || p.type.startsWith('legend'))) {
      payloads.push({ at: NOW - t1, type: p.type,
        animation: p.animation === undefined ? '(none)' : JSON.parse(JSON.stringify(p.animation)) });
    }
    return od.call(this, p);
  };
  SAMPLES.forEach((t, si) => {
    NOW = t1 + t;
    let flushed = false;
    for (const e of events) {
      if (e.at !== t) continue;
      const pt = () => {
        if (e.aim != null) {
          const p = sliderAim(chart, e.aim);
          e.x = p[0];
          e.y = p[1];
        }
        else if (e.dx != null) {
          e.x = last[0] + e.dx;
          e.y = last[1] + e.dy;
        }
        last = [e.x, e.y];
        return [e.x, e.y];
      };
      if (e.type === 'over') {
        const [x, y] = aimOf(chart, e.series, e.index);
        e.x = x;
        e.y = y;
        last = [x, y];
        h.mousemove(raw(x, y));
      }
      else if (e.type === 'out') {
        e.x = 3;
        e.y = 3;
        last = [3, 3];
        h.mousemove(raw(e.x, e.y));
      }
      else if (e.type === 'move' || e.type === 'down' || e.type === 'up' || e.type === 'click') {
        const [x, y] = pt();
        const name = { move: 'mousemove', down: 'mousedown', up: 'mouseup', click: 'click' }[e.type];
        h[name](raw(x, y));
      }
      else if (e.type === 'wheel') {
        const [x, y] = pt();
        h.mousewheel(raw(x, y, { zrDelta: e.delta }));
      }
      else if (e.type === 'action') chart.dispatchAction(JSON.parse(JSON.stringify(e.payload)));
      else if (e.type === 'setOption') {
        chart.setOption(JSON.parse(JSON.stringify(e.option)), true);
        flushed = true;
      }
      else must(false, 'unknown event ' + e.type);
    }
    if (!flushed) zr.animation.update();
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    for (const v of seriesViews(chart)) {
      for (const it of walkView(v.group)) {
        let rec = ids.get(it.el);
        if (!rec) {
          // a label's and a label line's: its host's
          const ecd = ecDataOf(it.host);
          rec = newRec(v.owner + '/' + (it.path === '' ? 'root' : it.path), v.owner, it.role, it.el.type,
            ecd && ecd.dataIndex != null ? ecd.dataIndex : null, false);
          ids.set(it.el, rec);
          recs.push(rec);
        }
        rec.snaps[si] = snap(it.el);
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        const hd = ecDataOf(it.host);
        rec.dis[si] = hd && hd.dataIndex != null ? hd.dataIndex : null;
        rec.scopes[si] = scopesOf(it.el);
        rec.stateAnim[si] = stateAnims(it.el).join(' ');
        const st = it.el.stateTransition;
        rec.transition[si] = st ? st.duration + '/' + st.easing + '/' + (st.delay == null ? '' : st.delay) : '';
      }
    }
    for (const a of axisLeaves(chart)) {
      let rec = axisIds.get(a.id);
      if (!rec) {
        rec = newRec(a.id, a.owner, 'axis', a.el.type, null, true);
        axisIds.set(a.id, rec);
        recs.push(rec);
      }
      must(rec.snaps[si] === null, 'two elements of anid ' + a.id);
      rec.type = a.el.type;
      rec.snaps[si] = snap(a.el);
      rec.anim[si] = a.el.animators ? a.el.animators.length : 0;
      rec.scopes[si] = scopesOf(a.el);
    }
  });
  proto.setUpdatePayload = od;
  return { clips, elements: summarize(recs), events: eventsOut(events), payloads };
}

// one case: `option` set at T0 and settled; then at T1 the events
function runCase(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    const t1 = T_BASE + T1_OFFSET;
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    settle(chart, T_BASE);
    return loopOn(chart, { events: c.events }, t1);
  }
  finally {
    chart.dispose();
  }
}

// ---------- the cases ----------
const CATS = ['A', 'B', 'C', 'D', 'E'];
const CATS10 = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];
const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
const toggle = (at, name) => ({ at, type: 'action', payload: { type: 'legendToggleSelect', name } });
const yShown = { type: 'value', axisLine: { show: true }, axisTick: { show: true } };

const stackOpt = () => ({
  color: PAL, legend: {}, xAxis: { type: 'category', data: CATS }, yAxis: yShown,
  series: [{ name: 's0', type: 'bar', stack: 'a', data: [5, 20, 36, 10, 8] },
    { name: 's1', type: 'bar', stack: 'a', data: [8, 12, 6, 30, 4] }],
});
const zoomBars = dz => ({
  color: PAL, xAxis: { type: 'category', data: CATS10 }, yAxis: { type: 'value' },
  dataZoom: [dz],
  series: [{ name: 'b', type: 'bar', data: [5, 20, 36, 10, 8, 14, 27, 3, 18, 22] },
    { name: 'l', type: 'line', data: [12, 8, 20, 25, 16, 30, 11, 9, 24, 15] }],
});

const CASES = [
  { id: 'legend-bar-stack', note: 'stacked bars: s0 switched off at 0 (its bars fade, 200 ms cubicOut; s1 drops onto the '
    + 'base, 500 ms update; the y axis groupTransitions its labels, ticks and split lines by tick value), back on at 700 '
    + '(s0 enters from 0, 1000 ms; s1 lifts again)',
  option: stackOpt(), events: [toggle(0, 's0'), toggle(700, 's0')] },
  { id: 'legend-interrupt', note: 'stacked bars: s0 off at 0 and back on at 150, while everything still moves -- its bars '
    + 'are fading (they fade on, the returning series enters as new), s1 and the axis leaves are half way (each new '
    + 'tween starts where the old one has got to)',
  option: stackOpt(), events: [toggle(0, 's0'), toggle(150, 's0')] },
  { id: 'legend-bar-negative', note: 'side by side, s0 has negatives: off at 0, the y extent loses its negative half and the '
    + 'x axis on zero slides down with its ticks (anid line, ticks_*); back on at 700. The bars of s1 widen and move',
  option: { color: PAL, legend: {}, xAxis: { type: 'category', data: CATS, axisTick: { show: true } }, yAxis: yShown,
    series: [{ name: 's0', type: 'bar', data: [5, -20, 36, 10, -8] }, { name: 's1', type: 'bar', data: [8, 12, 6, 30, 4] }] },
  events: [toggle(0, 's0'), toggle(700, 's0')] },
  { id: 'legend-line', note: 'two lines: s1 off at 0 (its polyline gone at once, its symbols fade and shrink, 200 ms; s0\'s '
    + 'points tween through lineAnimationDiff on the new y axis), back on at 700 (its clip grows again)',
  option: { color: PAL, legend: {}, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ name: 's0', type: 'line', data: [5, 20, 36, 10, 18] }, { name: 's1', type: 'line', data: [40, 52, 30, 61, 45] }] },
  events: [toggle(0, 's1'), toggle(700, 's1')] },
  { id: 'legend-pie', note: 'a pie filtered by name: b off at 0 (its slice fades; the rest tween their angles, their labels and '
    + 'label lines move), back on at 700 (b sweeps its endAngle out of its own start at update timing)',
  option: { color: PAL, legend: {}, series: [{ type: 'pie', radius: '50%',
    data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 }] }] },
  events: [toggle(0, 'b'), toggle(700, 'b')] },
  { id: 'legend-hover-held', note: 'hover s1\'s bar C at 0, s0 off at 100: the hovered bar keeps its emphasis while it drops '
    + '(the render re-applies its states), out at 900',
  option: stackOpt(), events: [{ at: 0, type: 'over', series: 1, index: 2 }, toggle(100, 's0'), { at: 900, type: 'out' }] },
  { id: 'notmerge-hover', note: 'hover bar C at 0; at 400 the option again (notMerge) with new values: C is reused, still '
    + 'hovered, its shape tweens; out at 900',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
    series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }] },
  events: [{ at: 0, type: 'over', series: 0, index: 2 },
    { at: 400, type: 'setOption', option: { color: PAL, xAxis: { type: 'category', data: CATS },
      yAxis: { type: 'value', max: 40, min: -10 }, series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] } },
    { at: 900, type: 'out' }] },
  { id: 'notmerge-highlight-line', note: 'highlight a line symbol by action at 0; at 400 notMerge with new values (the symbol '
    + 'is reused, its highlight held); downplay at 800',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
    series: [{ type: 'line', data: [5, 20, 36, 10, 18] }] },
  events: [{ at: 0, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
    { at: 400, type: 'setOption', option: { color: PAL, xAxis: { type: 'category', data: CATS },
      yAxis: { type: 'value', max: 40 }, series: [{ type: 'line', data: [8, 15, 30, 22, 12] }] } },
    { at: 800, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } }] },
  { id: 'datazoom-action', note: 'dispatchAction dataZoom 20..70 at 0: no animation in the payload, the model\'s update '
    + 'timing (500 cubicInOut); the bars leaving fade 200 ms; back to 0..100 at 800 (the returning ones enter, 1000 ms)',
  option: zoomBars({ type: 'inside' }),
  events: [{ at: 0, type: 'action', payload: { type: 'dataZoom', dataZoomIndex: 0, start: 20, end: 70 } },
    { at: 800, type: 'action', payload: { type: 'dataZoom', dataZoomIndex: 0, start: 0, end: 100 } }] },
  { id: 'datazoom-wheel', note: 'the inside zoom by the wheel at 0 and at 300: its payload {cubicOut, 100} overrides every '
    + 'timing of the update -- enter, update and leave alike, the axes too',
  option: zoomBars({ type: 'inside' }),
  events: [{ at: 0, type: 'move', x: 250, y: 150 }, { at: 0, type: 'wheel', x: 250, y: 150, delta: 3 },
    { at: 300, type: 'wheel', x: 250, y: 150, delta: 3 }] },
  { id: 'datazoom-pan', note: 'the inside zoom panned by a drag at 0 (zoomed in first through the option, 30..70): the payload of the roam, '
    + 'payload {cubicOut, 100} again; a second drag at 300',
  option: zoomBars({ type: 'inside', start: 30, end: 70 }),
  events: [{ at: 0, type: 'move', x: 300, y: 80 }, { at: 0, type: 'down', x: 300, y: 80 },
    { at: 0, type: 'move', x: 240, y: 80 }, { at: 0, type: 'up', x: 240, y: 80 },
    { at: 300, type: 'move', x: 300, y: 80 }, { at: 300, type: 'down', x: 300, y: 80 },
    { at: 300, type: 'move', x: 360, y: 80 }, { at: 300, type: 'up', x: 360, y: 80 }] },
  { id: 'datazoom-slider', note: 'a realtime slider: the right handle dragged 60 px left at 0 ({cubicOut, 100, delay 0}); a '
    + 'click on its panel at 400 recentres it -- not realtime, `animation: null`, the model\'s update timing',
  option: zoomBars({ type: 'slider', bottom: 10, height: 24 }),
  events: [{ at: 0, type: 'move', aim: 'handle1' }, { at: 0, type: 'down', aim: 'handle1' },
    { at: 0, type: 'move', dx: -60, dy: 0 }, { at: 0, type: 'up', dx: 0, dy: 0 },
    { at: 400, type: 'move', aim: 0.93 }, { at: 400, type: 'down', aim: 0.93 }, { at: 400, type: 'up', aim: 0.93 },
    { at: 400, type: 'click', aim: 0.93 }] },
  { id: 'graph-roam', note: 'a graph panned by the mouse at 0: View.updateTransform with {duration: 0}, nothing animates',
  option: { series: [{ type: 'graph', layout: 'none', roam: true, symbolSize: 20,
    data: [{ name: 'a', x: 100, y: 100 }, { name: 'b', x: 300, y: 120 }, { name: 'c', x: 200, y: 250 }],
    links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] }] },
  events: [{ at: 0, type: 'move', x: 60, y: 60 }, { at: 0, type: 'down', x: 60, y: 60 }, { at: 0, type: 'move', x: 90, y: 70 },
    { at: 0, type: 'up', x: 90, y: 70 }] },
];

// ---------- the compact writer of animation.js ----------
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

// ---------- guards ----------
const byId = (cs, id) => cs.find(c => c.id === id);
const elOf = (c, id) => c.elements.find(e => e.id === id);
const si = t => SAMPLES.indexOf(t);
function guards(cases) {
  const out = [];
  const g = (name, ok, detail) => {
    must(ok, 'guard ' + name + ': ' + detail);
    out.push(name);
  };
  // 1. a switched-off bar fades: leave scope, opacity 1 -> 0 over 200 ms
  // cubicOut, gone after; the kept series' bars update (500 ms)
  {
    const c = byId(cases, 'legend-bar-stack');
    const off = c.elements.filter(e => e.owner === 'series0:bar' && e.type === 'rect' && e.present
      && e.present[0] === 0);
    g('legend-leave-fade', off.length >= 5 && off.every(e => e.scopes && e.scopes[si(0)].includes('leave:style')
      && e.present && !e.present.includes(si(250))), JSON.stringify(off.map(e => e.present)));
    const kept = c.elements.filter(e => e.owner === 'series1:bar' && e.type === 'rect' && e.scopes);
    g('legend-update', kept.length === 5 && kept.every(e => e.scopes[si(0)] === 'update:shape' && e.scopes[si(501)] === ''),
      JSON.stringify(kept.map(e => [e.scopes[si(0)], e.scopes[si(501)]])));
    // 2. back on: new elements entering, 1000 ms
    const back = c.elements.filter(e => e.owner === 'series0:bar' && e.type === 'rect' && e.present
      && e.present[0] === si(700));
    g('legend-reshown-enters', back.length === 5 && back.every(e => e.scopes[si(700)] === 'enter:shape'
      && e.scopes[si(1500)] === 'enter:shape' && e.scopes[si(1701)] === ''), JSON.stringify(back.map(e => e.scopes)));
  }
  // 3. the y axis: matched labels tween by anid at update timing, unmatched
  // ones appear at once
  {
    const c = byId(cases, 'legend-bar-stack');
    const ax = c.elements.filter(e => e.owner === 'yAxis0');
    const moving = ax.filter(e => e.scopes && e.scopes[si(0)].startsWith('update'));
    g('axis-group-transition', moving.length >= 3 && moving.some(e => e.id.includes('/label_'))
      && moving.some(e => e.id.includes('/line_')) && moving.some(e => e.id.includes('/ticks_')),
    moving.map(e => e.id).join(' '));
    const fresh = ax.filter(e => e.present && e.present[0] === si(0) && !e.scopes);
    g('axis-unmatched-instant', fresh.length > 0, fresh.map(e => e.id).join(' '));
  }
  // 3b. an interrupted transition starts from where the leaf has got to
  {
    const c = byId(cases, 'legend-interrupt');
    const l = elOf(c, 'yAxis0/label_20');
    const y = l && l.track && l.track.y;
    // the new tween's first frame writes its from: the last frame's value,
    // neither end of either layout
    g('axis-from-current', !!(y && y[si(150)] === y[si(116)] && y[si(150)] !== y[si(0)]
      && y[si(150)] !== y[y.length - 1] && l.scopes[si(150)].startsWith('update')),
      JSON.stringify(l && l.trackText && l.trackText.y));
  }
  // 4. the x axis line slides with the zero
  {
    const c = byId(cases, 'legend-bar-negative');
    const line = elOf(c, 'xAxis0/line');
    g('axis-line-onzero', !!(line && line.track && line.track['shape.y1']), JSON.stringify(line && line.track));
  }
  // 5. the payload: the wheel's updates and leaves are 100 ms cubicOut; the
  // action's 500; the slider's drag 100, its click (null) 500
  {
    const w = byId(cases, 'datazoom-wheel');
        g('wheel-payload', w.payloads.length >= 1 && w.payloads[0].animation && w.payloads[0].animation.duration === 100
      && w.clips[si(0)] > 0, JSON.stringify([w.payloads, w.clips]));
    const a = byId(cases, 'datazoom-action');
    g('action-no-payload', a.clips[si(250)] > 0 && a.clips[si(501)] === 0, a.clips.join(','));
    const pn = byId(cases, 'datazoom-pan');
    g('pan-payload', pn.payloads.length === 2 && pn.payloads.every(p => p.animation && p.animation.duration === 100)
      && pn.clips[si(0)] > 0 && pn.clips[si(101)] === 0 && pn.clips[si(300)] > 0 && pn.clips[si(401)] === 0,
    JSON.stringify([pn.payloads, pn.clips]));
    const s = byId(cases, 'datazoom-slider');
    const drag = s.payloads.find(p => p.at === 0);
    const click = s.payloads.find(p => p.at === 400);
    g('slider-payloads', !!(drag && drag.animation && drag.animation.duration === 100 && drag.animation.delay === 0
      && click && click.animation === null && s.clips[si(101)] === 0 && s.clips[si(450)] > 0 && s.clips[si(1500)] === 0),
    JSON.stringify([s.payloads, s.clips]));
  }
  // 6. a pan is instant
  g('roam-instant', byId(cases, 'graph-roam').clips.every(n => n === 0), byId(cases, 'graph-roam').clips.join(','));
  // 7. the hover held: through the legend's update and through notMerge
  {
    const c = byId(cases, 'legend-hover-held');
    const b = c.elements.find(e => e.owner === 'series1:bar' && e.dataIndex === 2 && e.type === 'rect');
    const st = b.trackText.states || b.track.states;
    g('hover-held-legend', st[si(101)] === 'emphasis' && st[si(800)] === 'emphasis' && st[si(1000)] === '',
      JSON.stringify(st));
    const n = byId(cases, 'notmerge-hover');
    const nb = n.elements.find(e => e.owner === 'series0:bar' && e.dataIndex === 2 && e.type === 'rect');
    const ns = nb.trackText.states || nb.track.states;
    g('hover-held-notmerge', ns[si(401)] === 'emphasis' && ns[si(800)] === 'emphasis' && ns[si(1000)] === '',
      JSON.stringify(ns));
  }
  // 8. everything comes to rest
  if (process.env.DUMP) {
    const w = byId(cases, 'datazoom-wheel');
    for (const e of w.elements) if (e.animators && e.animators[si(150)]) console.log('LIVE', e.id, e.scopes[si(150)]);
  }
  for (const c of cases) g('settled-' + c.id, c.clips[c.clips.length - 1] === 0, c.id + ' ' + c.clips.join(','));
  return out;
}

function generate() {
  const cases = [];
  for (const c of CASES) {
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, option: c.option, events: r.events, payloads: r.payloads, clips: r.clips,
      elements: r.elements });
  }
  const gs = guards(cases);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'AN5: full-update transitions. A case sets `option` at T0 and settles; then at each sample t of samplesMs: the '
      + 'events at t (over: handler.mousemove at x,y; out: mousemove at 3,3; move / down / up / click / wheel: the '
      + 'handler at x,y, a wheel with zrDelta delta; action: dispatchAction; setOption: notMerge, which flushes on its '
      + 'own), then NOW = T1 + t and one zr.animation.update() unless a setOption flushed, then the record. Series '
      + 'elements as advchart-state-anim.json (every series view, a removed one too; the dataIndex of a label or a '
      + 'label line is the one of its host, dataIndices the per-sample ones where they change), plus scopes: per sample the '
      + 'element\'s animators as scope:targetName, sorted. Axis elements: owner xAxis<i> / yAxis<i>, id owner/anid, '
      + 'role axis, recorded BY ANID (each render makes new ones). payloads: every action dispatched, with its animation '
      + 'part ("(none)" for none).',
    W, H, seed: SEED,
    clock: { T0: T_BASE, T1Offset: T1_OFFSET },
    samplesMs: SAMPLES,
    guards: gs,
    cases,
  };
}

let json1;
let json2;
try {
  json1 = fmt(generate(), '') + '\n';
  json1 = json1.replace(/\\u0000/g, '\\u2400');
  json2 = fmt(generate(), '') + '\n';
  json2 = json2.replace(/\\u0000/g, '\\u2400');
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
