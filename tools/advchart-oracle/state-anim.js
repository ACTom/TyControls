// AN3b (batch 94): state transitions -- emphasis, blur and select through
// el.stateTransition (the series' stateAnimation, 300 ms cubicOut by default).
// The harness is animation-update.js' own, copied (that script generates and
// exits on load): the replaced Date before the dist, chart._ssr = false,
// env.node = false, the seeded Math.random, hand-stepped frames and the same
// element records, plus z2 and the state bookkeeping.
//
// A STEP IS ONE FRAME. At each sample time t (ms after T1): the events of t
// (pointer moves through zr.handler, dispatchAction, a notMerge setOption),
// then NOW = T1 + t and zr.animation.update() -- every clip steps, then
// 'frame' runs echarts' _onframe, whose applyChangedStates turns the flags
// into state lists (useStates), which is where a transition's animators are
// made. They first step on the NEXT frame. A setOption flushes on its own
// (its clips start at once); its sample then makes no further frame.
//
// Run: node tools/advchart-oracle/state-anim.js
//   -> tests/fixtures/advchart-state-anim.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-state-anim.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 150, 200, 250, 300, 301, 350, 400, 450, 500, 501, 550, 600, 650,
  700, 750, 800, 801, 850, 900, 1000, 1100, 1200, 1500];

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
    out.push({ el, role: 'el', path: p });
    const label = el.getTextContent && el.getTextContent();
    if (label) out.push({ el: label, role: 'label', path: p + '#label' });
    const guide = el.getTextGuideLine && el.getTextGuideLine();
    if (guide) out.push({ el: guide, role: 'guide', path: p + '#guide' });
    if (el.isGroup) el.childrenRef().forEach((c, i) => visit(c, p === '' ? String(i) : p + '.' + i));
  };
  visit(root, '');
  return out;
}

function seriesViews(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const v = chart.getViewOfSeriesModel(s);
    if (v) out.push({ owner: 'series' + s.seriesIndex + ':' + s.subType, seriesIndex: s.seriesIndex, group: v.group });
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

// the state animators of an element: their __fromStateTransition names
function stateAnims(el) {
  return (el.animators || []).filter(a => a.__fromStateTransition).map(a => a.__fromStateTransition + ':' + (a.targetName || ''));
}

// ---------- the timeline ----------
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

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
  // a Symbol group
  return [Math.round(el.x), Math.round(el.y)];
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
    let id = rec.id + (rec.role !== 'el' && !rec.id.includes('#') ? '#' + rec.role : '');
    const n = seen.get(id) || 0;
    seen.set(id, n + 1);
    if (n) id += '~' + n;
    const everAnim = rec.anim.some(x => x > 0);
    const everState = rec.stateAnim.some(x => x !== '');
    elements.push({
      id, owner: rec.owner, role: rec.role, type: rec.type, dataIndex: rec.dataIndex,
      present: presentIdx.length === SAMPLES.length ? null : presentIdx,
      final, finalText,
      track: Object.keys(track).length ? track : null,
      trackText: Object.keys(track).length ? trackText : null,
      animators: everAnim ? rec.anim : null,
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
    if (e.series != null) { o.series = e.series; o.index = e.index; }
    if (e.payload) o.payload = e.payload;
    if (e.option) o.option = e.option;
    return o;
  });
}

// the frame loop: at each sample, its events, then one frame (unless a
// setOption flushed), then the record
function loopOn(chart, c, t1) {
  const zr = chart.getZr();
  const h = zr.handler;
  const events = c.events.map(e => Object.assign({}, e));
  const ids = new Map();
  const recs = [];
  const clips = [];
  SAMPLES.forEach((t, si) => {
    NOW = t1 + t;
    let flushed = false;
    for (const e of events) {
      if (e.at !== t) continue;
      if (e.type === 'over') {
        const [x, y] = aimOf(chart, e.series, e.index);
        e.x = x;
        e.y = y;
        h.mousemove(raw(x, y));
      }
      else if (e.type === 'out') {
        e.x = 3;
        e.y = 3;
        h.mousemove(raw(e.x, e.y));
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
          const ecd = ecDataOf(it.el);
          rec = {
            id: v.owner + '/' + (it.path === '' ? 'root' : it.path),
            owner: v.owner, role: it.role, type: it.el.type,
            dataIndex: ecd && ecd.dataIndex != null ? ecd.dataIndex : null,
            snaps: new Array(SAMPLES.length).fill(null),
            anim: new Array(SAMPLES.length).fill(0),
            stateAnim: new Array(SAMPLES.length).fill(''),
            transition: new Array(SAMPLES.length).fill(''),
          };
          ids.set(it.el, rec);
          recs.push(rec);
        }
        rec.snaps[si] = snap(it.el);
        rec.anim[si] = it.el.animators ? it.el.animators.length : 0;
        rec.stateAnim[si] = stateAnims(it.el).join(' ');
        const st = it.el.stateTransition;
        rec.transition[si] = st ? st.duration + '/' + st.easing + '/' + (st.delay == null ? '' : st.delay) : '';
      }
    }
  });
  return { clips, elements: summarize(recs), events: eventsOut(events) };
}

// one case: `first` (or `option`) set at T0 and settled; then at T1 the
// events. A live case (`live`) sets `option` AT T1 instead (an event at 0),
// after `first` if given, so its enter or update animation is running.
function runCase(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    const t1 = T_BASE + T1_OFFSET;
    const settled = c.live ? c.first : c.option;
    if (settled) {
      chart.setOption(JSON.parse(JSON.stringify(settled)));
      settle(chart, T_BASE);
    }
    const events = c.live ? [{ at: 0, type: 'setOption', option: c.option }].concat(c.events) : c.events;
    return loopOn(chart, { events }, t1);
  }
  finally {
    chart.dispose();
  }
}

// ---------- the cases ----------
const CATS = ['A', 'B', 'C', 'D', 'E'];
const C0 = '#5470c6';
const C1 = '#91cc75';
const barOpt = extra => Object.assign({
  color: [C0, C1],
  xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
  series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }],
}, extra || {});
const barSeries = s => barOpt({ series: [Object.assign({ type: 'bar', data: [5, 20, 36, 10, -8] }, s)] });
const pieOpt = s => ({
  color: [C0, C1, '#fac858', '#ee6666'],
  series: [Object.assign({ type: 'pie', radius: '50%',
    data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'c', value: 30 }, { name: 'd', value: 15 }] }, s || {})],
});
const scatterOpt = s => ({
  color: [C0],
  xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
  series: [Object.assign({ type: 'scatter', symbolSize: 10, data: [[1, 2], [3, 4], [5, 1], [2, 6]] }, s || {})],
});
const lineOpt = s => ({
  color: [C0],
  xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
  series: [Object.assign({ type: 'line', data: [5, 20, 36, 10, 18] }, s || {})],
});

const CASES = [
  { id: 'bar-hover', note: 'hover bar C at 0, out at 500: the fill lifts and comes back, 300 ms cubicOut each way',
    option: barOpt(), events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
  { id: 'bar-hover-again', note: 'hover at 0, out at 100 (mid-transition), over again at 200: each from the current value',
    option: barOpt(), events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 100, type: 'out' },
      { at: 200, type: 'over', series: 0, index: 2 }, { at: 800, type: 'out' }] },
  { id: 'bar-hover-move', note: 'hover C at 0, move to D at 150: C leaves and D enters in the same frame',
    option: barOpt(), events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 150, type: 'over', series: 0, index: 3 },
      { at: 700, type: 'out' }] },
  { id: 'bar-action', note: 'dispatchAction highlight at 0, downplay at 500',
    option: barOpt(), events: [{ at: 0, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
      { at: 500, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'bar-select', note: 'selectedMode single: select at 0 (border colour assigned, width tweened 1 -> 2), unselect at 500',
    option: barSeries({ selectedMode: 'single' }), events: [
      { at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 3 } },
      { at: 500, type: 'action', payload: { type: 'unselect', seriesIndex: 0, dataIndex: 3 } }] },
  { id: 'bar-select-hover', note: 'select B at 0, hover B at 400 (the lift from the select fill), out at 800',
    option: barSeries({ selectedMode: 'single', select: { itemStyle: { color: '#ee6666' } } }), events: [
      { at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 1 } },
      { at: 400, type: 'over', series: 0, index: 1 }, { at: 800, type: 'out' }] },
  { id: 'bar-focus', note: 'two series, emphasis.focus series: hovering series 0 blurs series 1 (opacity 1 -> 0.1), out at 500',
    option: barOpt({ series: [{ type: 'bar', emphasis: { focus: 'series' }, data: [5, 20, 36, 10, -8] },
      { type: 'bar', emphasis: { focus: 'series' }, data: [8, 12, 6, 30, 4] }] }),
    events: [{ at: 0, type: 'over', series: 0, index: 1 }, { at: 500, type: 'out' }] },
  { id: 'bar-focus-action', note: 'highlight with focus self by action at 0 (the others blur), downplay at 500',
    option: barSeries({ emphasis: { focus: 'self' } }), events: [
      { at: 0, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
      { at: 500, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } }] },
  { id: 'bar-state-override', note: 'stateAnimation {duration: 600, easing: linear, delay: 50}',
    option: barSeries({ stateAnimation: { duration: 600, easing: 'linear', delay: 50 } }),
    events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 800, type: 'out' }] },
  { id: 'bar-state-root', note: 'a root-level stateAnimation {duration: 200, easing: quadraticIn} reaches the series',
    option: barOpt({ stateAnimation: { duration: 200, easing: 'quadraticIn' } }),
    events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
  { id: 'bar-state-zero', note: 'stateAnimation.duration 0: no transition, the state is set at once',
    option: barSeries({ stateAnimation: { duration: 0 } }),
    events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
  { id: 'bar-animation-off', note: 'animation: false: no stateTransition at all, the state is set at once',
    option: barOpt({ animation: false }),
    events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
  { id: 'pie-hover', note: 'hover slice b at 0: r grows by scaleSize 5, the fill lifts; out at 500',
    option: pieOpt(), events: [{ at: 0, type: 'over', series: 0, index: 1 }, { at: 500, type: 'out' }] },
  { id: 'pie-select', note: 'select b at 0: the slice, its label and its label line slide by selectedOffset; unselect at 500',
    option: pieOpt({ selectedMode: 'single' }), events: [
      { at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 1 } },
      { at: 500, type: 'action', payload: { type: 'unselect', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'pie-select-switch', note: 'single mode: select b at 0, select c at 150 (b slides back from mid-way)',
    option: pieOpt({ selectedMode: 'single' }), events: [
      { at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 1 } },
      { at: 150, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 2 } }] },
  { id: 'scatter-hover', note: 'hover a symbol at 0: its path scales by max(1.1, 3 / (size / 2)); out at 500',
    option: scatterOpt(), events: [{ at: 0, type: 'over', series: 0, index: 1 }, { at: 500, type: 'out' }] },
  { id: 'scatter-hover-scale', note: 'emphasis.scale 1.6 and an emphasis colour',
    option: scatterOpt({ emphasis: { scale: 1.6, itemStyle: { color: '#ee6666' } } }),
    events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
  { id: 'line-hover', note: 'hover a line symbol at 0: the symbol path scales, the polyline goes bolder and lifts; out at 500',
    option: lineOpt(), events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
  { id: 'line-focus', note: 'line and bar, focus series on the line: hovering a line symbol blurs the bars',
    option: { color: [C0, C1], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'line', emphasis: { focus: 'series' }, data: [5, 20, 36, 10, 18] },
        { type: 'bar', data: [8, 12, 6, 30, 4] }] },
    events: [{ at: 0, type: 'over', series: 0, index: 3 }, { at: 500, type: 'out' }] },
];


// THE INTERPLAY with the enter and update animations: `live` cases set
// `option` AT T1 (after `first`, settled at T0, when given), so their clips
// run when the state changes
const LIVE = [
  { id: 'scatter-enter-hover', live: true, note: 'highlight a symbol 300 ms into its enter (scale 0 -> 5, opacity 0 -> 0.8; '
    + 'too small to hover yet): saveCurrentToNormalState keeps the enter\'s FINAL values (saveTo), the transition starts from '
    + 'the current ones; downplay at 600',
    option: scatterOpt(), events: [{ at: 300, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
      { at: 600, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'scatter-enter-hover-zero', live: true, note: 'as scatter-enter-hover with stateAnimation.duration 0: no transition, '
    + 'the running enter animators get __changeFinalValue (they land on the emphasis scale, then back on the normal one)',
    option: scatterOpt({ stateAnimation: { duration: 0 } }),
    events: [{ at: 300, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
      { at: 600, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 1 } }] },
  { id: 'bar-update-hover', live: true, note: 'values change (update tween of the shape, 500 cubicInOut); highlight C at 100 '
    + '(the fill transition rides beside the shape tween); downplay at 700',
    first: barOpt(), option: barOpt({ series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] }),
    events: [{ at: 100, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
      { at: 700, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } }] },
  { id: 'pie-update-hover', live: true, note: 'values change (the shape tweens, 500 cubicInOut); hover b at 100: the emphasis '
    + 'shape is the normal shape (the update\'s finals, saveTo) with r + 5, so the angles finish in the state\'s 300 ms; out at 700',
    first: pieOpt(), option: pieOpt({ data: [{ name: 'a', value: 25 }, { name: 'b', value: 10 }, { name: 'c', value: 30 },
      { name: 'd', value: 15 }] }),
    events: [{ at: 100, type: 'over', series: 0, index: 1 }, { at: 700, type: 'out' }] },
];

// THE OTHER TYPES on the shared state machine, by action (no aim needed)
const act = (series, index, at, type) => ({ at, type: 'action', payload: { type, seriesIndex: series, dataIndex: index } });
const hl = (s, i, at, out) => [act(s, i, at, 'highlight'), act(s, i, out, 'downplay')];
const TYPES = [
  { id: 'funnel-action', note: 'funnel: highlight b at 0 (lift), downplay at 500',
    option: { color: [C0, C1, '#fac858', '#ee6666'], series: [{ type: 'funnel',
      data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }, { name: 'd', value: 80 }] }] },
    events: hl(0, 1, 0, 500) },
  { id: 'heatmap-action', note: 'heatmap cells (visualMap colours): highlight a cell at 0, downplay at 500',
    option: { xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { min: 0, max: 10, show: false, inRange: { color: ['#313695', '#a50026'] } },
      series: [{ type: 'heatmap', data: [[0, 0, 1], [1, 0, 5], [2, 0, 9], [0, 1, 3], [1, 1, 7], [2, 1, 2]] }] },
    events: hl(0, 4, 0, 500) },
  { id: 'candlestick-action', note: 'candlestick: highlight the second box at 0 (border 2, lift), downplay at 500',
    option: { xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 40 },
      series: [{ type: 'candlestick', data: [[20, 30, 10, 35], [30, 18, 12, 33], [18, 25, 15, 28]] }] },
    events: hl(0, 1, 0, 500) },
  { id: 'pictorial-action', note: 'pictorialBar (rect glyphs): highlight a bar at 0, downplay at 500',
    option: { color: [C0], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'pictorialBar', symbol: 'rect', data: [5, 20, 36, 10, 18] }] },
    events: hl(0, 2, 0, 500) },
  { id: 'sunburst-action', note: 'sunburst: highlight a node at 0 (focus descendant: the others blur to 0.2), downplay at 500',
    option: { color: [C0, C1, '#fac858'], series: [{ type: 'sunburst', radius: [0, '80%'],
      data: [{ name: 'a', children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 6 }] },
        { name: 'b', children: [{ name: 'b1', value: 5 }] }, { name: 'c', value: 3 }] }] },
    events: hl(0, 1, 0, 500) },
  { id: 'effectScatter-action', note: 'effectScatter: highlight a symbol at 0 (scale, lift), downplay at 500; the ripples loop on',
    option: { color: [C0], xAxis: { type: 'value', min: 0, max: 8 }, yAxis: { type: 'value', min: 0, max: 8 },
      series: [{ type: 'effectScatter', symbolSize: 10, data: [[1, 2], [3, 4], [5, 1]] }] },
    events: hl(0, 1, 0, 500) },
  { id: 'line-area-action', note: 'an area line highlighted whole at 0 (the polyline and the polygon), downplay at 500',
    option: { color: [C0], xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
      series: [{ type: 'line', areaStyle: {}, emphasis: { areaStyle: { color: '#ee6666' } }, data: [5, 20, 36, 10, 18] }] },
    events: [{ at: 0, type: 'action', payload: { type: 'highlight', seriesIndex: 0 } },
      { at: 500, type: 'action', payload: { type: 'downplay', seriesIndex: 0 } }] },
  { id: 'pie-select-initial', live: true, note: 'a slice selected in the data at the first render: updateStates applies '
    + 'the select WITH its transition before the flush of setOption, so the slice slides out while the pie sweeps',
    option: pieOpt({ selectedMode: 'single', data: [{ name: 'a', value: 10 }, { name: 'b', value: 20, selected: true },
      { name: 'c', value: 30 }, { name: 'd', value: 15 }] }), events: [] },
  { id: 'bar-focus-label', note: 'focus series with labels shown: hovering series 0 blurs series 1, its labels too (a Text '
    + 'animates its opacity only); out at 500',
    option: barOpt({ series: [{ type: 'bar', label: { show: true }, emphasis: { focus: 'series' }, data: [5, 20, 36, 10, -8] },
      { type: 'bar', label: { show: true }, emphasis: { focus: 'series' }, data: [8, 12, 6, 30, 4] }] }),
    events: [{ at: 0, type: 'over', series: 0, index: 2 }, { at: 500, type: 'out' }] },
];

// a full update under a held state: notMerge setOption while selected or
// hovered (clearStates, the render, then prevStates without a transition and
// applyElementStates with one)
const NOTMERGE = [
  { id: 'bar-select-notmerge', note: 'select D at 0; at 400 the option again (notMerge) with new values; unselect at 800',
    option: barSeries({ selectedMode: 'single' }), events: [
      { at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 3 } },
      { at: 400, type: 'setOption', option: barSeries({ selectedMode: 'single', data: [15, 8, 30, 25, 4] }) },
      { at: 800, type: 'action', payload: { type: 'unselect', seriesIndex: 0, dataIndex: 3 } }] },
  { id: 'pie-select-notmerge', note: 'select b at 0; at 400 the option again (notMerge), b now selected in the data',
    option: pieOpt({ selectedMode: 'single' }), events: [
      { at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 1 } },
      { at: 400, type: 'setOption', option: pieOpt({ selectedMode: 'single', data: [{ name: 'a', value: 10 },
        { name: 'b', value: 20, selected: true }, { name: 'c', value: 30 }, { name: 'd', value: 15 }] }) }] },
  { id: 'bar-hover-notmerge', note: 'highlight C at 0; at 400 the option again (notMerge) with new values; downplay at 800',
    option: barOpt(), events: [
      { at: 0, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
      { at: 400, type: 'setOption', option: barOpt({ series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] }) },
      { at: 800, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } }] },
];

// [batch 108] appended after every other case and after their guards, so
// nothing earlier moves: a boxplot box highlighted (the border 1 -> 2, the
// white fill lifted, z2 + 10; the shadow is set but this port draws none),
// and the other boxes blurred by focus 'self'
const LATE_TYPES = [
  { id: 'boxplot-action', note: "boxplot: highlight the second box at 0 (border 2, lift, focus 'self' blurs the others), downplay at 500",
    option: { color: [C0], xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 60 },
      series: [{ type: 'boxplot', emphasis: { focus: 'self' },
        data: [[10, 20, 25, 32, 45], [5, 18, 22, 30, 40], [15, 24, 30, 36, 52]] }] },
    events: hl(0, 1, 0, 500) },
  { id: 'boxplot-enter-hover', live: true, note: 'highlight a box 300 ms into its enter (the points grow from the median, 800 ms): '
    + 'the border transition runs beside the shape tween on the same element; downplay at 600',
    option: { color: [C0], xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 0, max: 60 },
      series: [{ type: 'boxplot', data: [[10, 20, 25, 32, 45], [5, 18, 22, 30, 40], [15, 24, 30, 36, 52]] }] },
    events: hl(0, 1, 300, 600) },
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
function guards(cases) {
  const out = [];
  const g = (name, ok, detail) => {
    must(ok, 'guard ' + name + ': ' + detail);
    out.push(name);
  };
  // 1. the default: 300 ms cubicOut, first step on the frame after the one
  // that applied the state (sample 1), done at 301
  {
    const c = byId(cases, 'bar-hover');
    const bar = elOf(c, 'series0:bar/2');
    const fill = bar.trackText['style.fill'];
    const i1 = SAMPLES.indexOf(1);
    const i301 = SAMPLES.indexOf(301);
    const i150 = SAMPLES.indexOf(150);
    g('default-transition', fill[0] === C0 && fill[i1] === 'rgba(84,112,198,1)' && fill[i301] === 'rgba(92,123,217,1)'
      && bar.transition.every(x => x === '300/cubicOut/'),
    JSON.stringify([fill[0], fill[i1], fill[i150], fill[i301], bar.transition[0]]));
    // the channel at 150: floor((92 - 84) * cubicOut(149/300) + 84)
    const w = (k => { k -= 1; return k * k * k + 1; })(149 / 300);
    const r = Math.floor((92 - 84) * w + 84);
    g('floored-channels', fill[i150].startsWith('rgba(' + r + ','), fill[i150] + ' r=' + r);
  }
  // 2. animation off and duration 0: never a state animator, the state set at once
  for (const id of ['bar-state-zero', 'bar-animation-off']) {
    const c = byId(cases, id);
    const f = elOf(c, 'series0:bar/2').trackText['style.fill'];
    g('instant-' + id, c.elements.every(e => !e.stateAnimators) && f[0] === 'rgba(92,123,217,1)', id + ' ' + f[0]);
  }
  // 3. animation off: no stateTransition is set
  g('off-no-transition', byId(cases, 'bar-animation-off').elements.every(e => !e.transition), 'bar-animation-off');
  // 4. every case comes to rest (the ripples of an effectScatter loop on)
  for (const c of cases) {
    if (c.id.startsWith('effectScatter')) continue;
    g('settled-' + c.id, c.clips[c.clips.length - 1] === 0, c.id + ' ' + c.clips.join(','));
  }
  // 5. the pie's select slides the label and the label line with the slice
  {
    const c = byId(cases, 'pie-select');
    const s = elOf(c, 'series0:pie/1');
    const l = elOf(c, 'series0:pie/1#label');
    const gl = elOf(c, 'series0:pie/1#guide');
    g('pie-select-moves', !!(s && s.track && s.track.x && l && l.track && l.track.x && gl && gl.track && gl.track.x),
      'pie-select');
  }
  // 6. the override's delay and duration: nothing moves before 51, at rest from 651
  {
    const c = byId(cases, 'bar-state-override');
    const f = elOf(c, 'series0:bar/2').trackText['style.fill'];
    g('override-timing', f[SAMPLES.indexOf(50)] === 'rgba(84,112,198,1)' && f[SAMPLES.indexOf(600)] !== 'rgba(92,123,217,1)'
      && f[SAMPLES.indexOf(700)] === 'rgba(92,123,217,1)', f.join(' '));
  }
  return out;
}

function generate() {
  const cases = [];
  for (const c of CASES.concat(LIVE, NOTMERGE, TYPES)) {
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, live: !!c.live, first: c.first || null, option: c.option,
      events: r.events, clips: r.clips, elements: r.elements });
  }
  const gs = guards(cases);
  for (const c of LATE_TYPES) {
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, live: !!c.live, first: c.first || null, option: c.option,
      events: r.events, clips: r.clips, elements: r.elements });
  }
  {
    const c = byId(cases, 'boxplot-action');
    const box = elOf(c, 'series0:boxplot/1');
    const lw = box && box.track ? box.track['style.lineWidth'] : null;
    must(c.clips[c.clips.length - 1] === 0, 'guard settled-boxplot-action');
    must(!!(lw && box.transition && box.transition.every(x => x === '300/cubicOut/')),
      'guard boxplot-border: ' + JSON.stringify(lw));
    gs.push('settled-boxplot-action', 'boxplot-border');
    must(byId(cases, 'boxplot-enter-hover').clips.slice(-1)[0] === 0, 'guard settled-boxplot-enter-hover');
    gs.push('settled-boxplot-enter-hover');
  }
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'AN3b: state transitions. A case sets `option` at T0 and settles (a live case: `first` settled at T0, `option` at '
      + 'T1 as an event at 0); then at each sample t of samplesMs: the events at t (over: handler.mousemove at x,y; out: '
      + 'mousemove at 3,3; action: dispatchAction; setOption: notMerge, which flushes on its own), then NOW = T1 + t and one '
      + 'zr.animation.update() unless a setOption flushed (clips step, then _onframe applies the changed states), then the '
      + 'record. Element keys as advchart-animation-update.json, plus z2, states (currentStates joined), style.stroke "null" '
      + 'for a path without one; stateAnimators: per sample the element\'s animators with __fromStateTransition, as '
      + 'name:targetName; transition: el.stateTransition as duration/easing/delay.',
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
