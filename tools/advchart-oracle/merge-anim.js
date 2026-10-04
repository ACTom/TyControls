// AN6 (batch 99): a MERGE setOption as an update of the same models. Upstream
// keeps every model a merge maps onto (Global.ts _mergeOption), so the views
// prepareView finds by '_ec_' + model.id + '_' + model.type are the old ones:
// the series views diff their data, the cartesian axis views groupTransition
// their leaves by anid (CartesianAxisView.render), the marker views
// (MarkPointView / MarkLineView, one component view each) update their
// SymbolDraw / LineDraw by series id, and the elements kept keep their
// hoverState, their __highByOuter bits and their select state. A model a
// replaceMerge removes has no view any more (disposed: gone at once); one it
// brings in by index is brandNew (__requireNewView): a new view, entering --
// an axis so replaced does not transition. A lazyUpdate merges at once and
// renders in the next frame's _onframe, after that frame's step.
//
// The harness is full-update-anim.js' own, copied: the replaced Date before
// the dist, chart._ssr = false, env.node = false, the seeded Math.random,
// hand-stepped frames. A STEP IS ONE FRAME: at each sample time t (ms after
// T1) the events of t, then NOW = T1 + t and zr.animation.update(), unless a
// synchronous setOption flushed. Recorded per sample: every element of every
// series view and of every marker view, by identity (full-update-anim.js'
// records, plus the marker views: owner markPoint<i> / markLine<i>); every
// leaf of every cartesian axis view's _axisGroup that has an anid, BY ANID;
// and which view object each series and axis model has (a number per view,
// in the order first seen).
//
// Run: node tools/advchart-oracle/merge-anim.js
//   -> tests/fixtures/advchart-merge-anim.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-merge-anim.json');

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

// EVERY series view (a removed one too), and the marker views
function viewsOf(chart) {
  const out = [];
  for (const v of chart._chartsViews) {
    const s = v.__model;
    if (!s) continue;
    out.push({ owner: 'series' + s.seriesIndex + ':' + s.subType, group: v.group });
  }
  for (const v of chart._componentsViews) {
    const m = v.__model;
    if (!m || (m.mainType !== 'markPoint' && m.mainType !== 'markLine')) continue;
    out.push({ owner: m.mainType + m.componentIndex, group: v.group });
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

function stateAnims(el) {
  return (el.animators || []).filter(a => a.__fromStateTransition).map(a => a.__fromStateTransition + ':' + (a.targetName || ''));
}
function scopesOf(el) {
  return (el.animators || []).map(a => (a.scope == null ? '' : a.scope) + ':' + (a.targetName || '')).sort().join(' ');
}

// the view object of every series and axis model, numbered in the order
// first seen ('-' for none)
function viewIds(chart, numbering) {
  const num = v => {
    if (!v) return '-';
    if (!numbering.has(v)) numbering.set(v, numbering.size);
    return numbering.get(v);
  };
  const out = {};
  const model = chart.getModel();
  model.eachRawSeries(s => { out['series' + s.seriesIndex] = num(chart._chartsMap[s.__viewId]); });
  for (const t of ['xAxis', 'yAxis']) {
    model.eachComponent(t, m => { out[t + m.componentIndex] = num(chart._componentsMap[m.__viewId]); });
  }
  return out;
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

// the place to point at for an element: a rect's centre, a symbol group's
// position
function aimOf(chart, seriesIndex, dataIndex) {
  const model = chart.getModel().getSeriesByIndex(seriesIndex);
  const data = model.getData();
  const el = data.getItemGraphicEl(dataIndex);
  must(el, 'no element for ' + seriesIndex + '/' + dataIndex);
  if (el.type === 'rect') {
    const s = el.shape;
    return [Math.round(s.x + s.width / 2), Math.round(s.y + s.height / 2)];
  }
  return [Math.round(el.x), Math.round(el.y)];
}

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
    if (e.series != null) { o.series = e.series; o.index = e.index; }
    if (e.payload) o.payload = e.payload;
    if (e.option) o.option = e.option;
    if (e.opts) o.opts = e.opts;
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
// synchronous setOption flushed), then the record
function loopOn(chart, c, t1) {
  const zr = chart.getZr();
  const h = zr.handler;
  const events = c.events.map(e => Object.assign({}, e));
  const ids = new Map();
  const axisIds = new Map();
  const recs = [];
  const clips = [];
  const views = [];
  const numbering = new Map();
  const views0 = viewIds(chart, numbering);
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
        const opts = e.opts ? JSON.parse(JSON.stringify(e.opts)) : {};
        chart.setOption(JSON.parse(JSON.stringify(e.option)), opts);
        // a lazy one renders in the frame below
        if (!opts.lazyUpdate) flushed = true;
      }
      else must(false, 'unknown event ' + e.type);
    }
    if (!flushed) zr.animation.update();
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    views.push(viewIds(chart, numbering));
    for (const v of viewsOf(chart)) {
      for (const it of walkView(v.group)) {
        let rec = ids.get(it.el);
        if (!rec) {
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
  return { clips, views0, views, elements: summarize(recs), events: eventsOut(events) };
}

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
const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
const yShown = { type: 'value', axisLine: { show: true }, axisTick: { show: true } };
const merge = (at, option, opts) => (opts ? { at, type: 'setOption', option, opts } : { at, type: 'setOption', option });

const barOpt = () => ({
  color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: yShown,
  series: [{ name: 's0', type: 'bar', data: [5, 20, 36, 10, 8] }],
});
const twoBars = () => ({
  color: PAL, legend: {}, xAxis: { type: 'category', data: CATS }, yAxis: yShown,
  series: [{ id: 'a', name: 'a', type: 'bar', data: [5, 20, 36, 10, 8] },
    { id: 'b', name: 'b', type: 'bar', data: [8, 12, 6, 30, 4] },
    { id: 'c', name: 'c', type: 'bar', data: [3, 9, 14, 7, 11] }],
});

const CASES = [
  { id: 'merge-bar-data', note: 'merge new bar data at 0: the series view diffs (500 ms update at the new row), the y '
    + 'axis groupTransitions its leaves by anid (the extent 40 -> 60); again at 700 back down',
  option: barOpt(),
  events: [merge(0, { series: [{ data: [15, 8, 58, 25, 4] }] }), merge(700, { series: [{ data: [6, 21, 30, 9, 7] }] })] },
  { id: 'merge-add-series', note: 'merge adding a series at 0: s1 is a new view (its bars enter, 1000 ms), s0\'s bars '
    + 'narrow and move (update), the axes transition',
  option: barOpt(),
  events: [merge(0, { series: [{}, { name: 's1', type: 'bar', data: [12, 30, 24, 50, 18] }] })] },
  { id: 'replace-remove-series', note: 'three series with ids; replaceMerge series keeps a and c at 0: b is removed (its '
    + 'view disposed, gone at once), a and c keep their views and indices (c stays series 2) and update, the axes '
    + 'transition',
  option: twoBars(),
  events: [merge(0, { series: [{ id: 'a', data: [6, 22, 30, 12, 9] }, { id: 'c', data: [4, 10, 50, 8, 12] }] },
    { replaceMerge: ['series'] })] },
  { id: 'merge-ymax', note: 'merge yAxis max 80 at 0: the bars shrink (update), the y axis leaves move; max 30 at 600, '
    + 'clipping C',
  option: barOpt(),
  events: [merge(0, { yAxis: { max: 80 } }), merge(600, { yAxis: { max: 50 } })] },
  { id: 'merge-markers', note: 'a bar with markPoint max and markLine average; merge new data at 0: the marker views are '
    + 'kept -- the markPoint symbol moves (its group x / y at update timing), the markLine\'s line tweens its ends',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: yShown,
    series: [{ name: 's0', type: 'bar', data: [5, 20, 36, 10, 8],
      markPoint: { data: [{ type: 'max', name: 'max' }] },
      markLine: { data: [{ type: 'average', name: 'avg' }] } }] },
  events: [merge(0, { series: [{ data: [15, 8, 28, 25, 4] }] })] },
  { id: 'merge-hover', note: 'hover bar C at 0; merge new values at 400: C is reused, still hovered, its shape tweens; '
    + 'out at 900',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
    series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }] },
  events: [{ at: 0, type: 'over', series: 0, index: 2 }, merge(400, { series: [{ data: [15, 8, 30, 25, 4] }] }),
    { at: 900, type: 'out' }] },
  { id: 'merge-highlight-line', note: 'highlight a line symbol by action at 0; merge new values at 400 (the symbol is '
    + 'reused, its highlight held); downplay at 800',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
    series: [{ type: 'line', data: [5, 20, 36, 10, 18] }] },
  events: [{ at: 0, type: 'action', payload: { type: 'highlight', seriesIndex: 0, dataIndex: 2 } },
    merge(400, { series: [{ data: [8, 15, 30, 22, 12] }] }),
    { at: 800, type: 'action', payload: { type: 'downplay', seriesIndex: 0, dataIndex: 2 } }] },
  { id: 'merge-select', note: 'select bar C by action at 0 (selectedMode single); merge new values at 400: the model keeps '
    + 'its selectedMap, the reused bar its select state',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40 },
    series: [{ type: 'bar', selectedMode: 'single', data: [5, 20, 36, 10, 8] }] },
  events: [{ at: 0, type: 'action', payload: { type: 'select', seriesIndex: 0, dataIndex: 2 } },
    merge(400, { series: [{ data: [15, 8, 30, 25, 4] }] })] },
  { id: 'merge-interrupt', note: 'merge at 0, again at 150 while everything moves (synchronous: the new tweens start '
    + 'where the last frame left them, the flush steps them all at 150)',
  option: barOpt(),
  events: [merge(0, { series: [{ data: [15, 8, 58, 25, 4] }] }), merge(150, { series: [{ data: [30, 2, 12, 40, 20] }] })] },
  { id: 'merge-lazy', note: 'the same, the second one lazyUpdate: it merges at once and renders in the frame of 150, AFTER '
    + 'that frame stepped the running tweens -- the new ones start from there',
  option: barOpt(),
  events: [merge(0, { series: [{ data: [15, 8, 58, 25, 4] }] }),
    merge(150, { series: [{ data: [30, 2, 12, 40, 20] }] }, { lazyUpdate: true })] },
  { id: 'merge-legend-hide', note: 'merge legend.selected {b: false} at 0: b\'s view is kept and remove()d -- its bars '
    + 'fade (200 ms); {b: true} at 700: it enters again',
  option: twoBars(),
  events: [merge(0, { legend: { selected: { b: false } } }), merge(700, { legend: { selected: { b: true } } })] },
  { id: 'replace-axis', note: 'replaceMerge xAxis at 0 with a new category axis (no id): brandNew, a new view -- its '
    + 'leaves appear at once, no transition; the y axis (merged) transitions; the bars update',
  option: { color: PAL, xAxis: { id: 'x0', type: 'category', data: CATS }, yAxis: yShown,
    series: [{ name: 's0', type: 'bar', data: [5, 20, 36, 10, 8] }] },
  events: [merge(0, { xAxis: { type: 'category', data: CATS }, series: [{ data: [15, 8, 58, 25, 4] }] },
    { replaceMerge: ['xAxis'] })] },
  { id: 'replace-axis-same-id', note: 'no axis has an id; replaceMerge yAxis at 0 with a new value axis: brandNew, its '
    + 'regenerated id the removed one -- still a new view (__requireNewView): its leaves appear at once; the x axis '
    + '(merged) is kept; the bars update',
  option: barOpt(),
  events: [merge(0, { yAxis: { type: 'value', axisLine: { show: true }, axisTick: { show: true } },
    series: [{ data: [15, 8, 58, 25, 4] }] }, { replaceMerge: ['yAxis'] })] },
  { id: 'replace-hover', note: 'hover bar C at 0; replaceMerge series at 400 with an unnamed bar series: brand new, its '
    + 'regenerated id the old one, but a new view -- new elements, entering, no hover state; out at 900',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 40, min: -10 },
    series: [{ type: 'bar', data: [5, 20, 36, 10, -8] }] },
  events: [{ at: 0, type: 'over', series: 0, index: 2 },
    merge(400, { series: [{ type: 'bar', data: [15, 8, 30, 25, 4] }] }, { replaceMerge: ['series'] }),
    { at: 900, type: 'out' }] },
  { id: 'merge-type-change', note: 'merge series 1 from bar to line at 0: a new model class at the same id, a new view '
    + '(the bars gone at once, the line enters); s0 updates, the axes transition',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: yShown,
    series: [{ name: 's0', type: 'bar', data: [5, 20, 36, 10, 8] }, { name: 's1', type: 'bar', data: [8, 12, 6, 30, 4] }] },
  events: [merge(0, { series: [{}, { type: 'line', data: [8, 12, 6, 50, 4] }] })] },
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
  if (process.env.DUMP) {
    for (const c of cases) {
      console.log('CASE', c.id, 'clips', c.clips.join(','));
      console.log('  views', JSON.stringify(c.views[0]), JSON.stringify(c.views[c.views.length - 1]));
      for (const e of c.elements) {
        if (e.role === 'axis' && !process.env.DUMPAXIS) continue;
        console.log('  ', e.id, e.type, 'di', e.dataIndex, 'pres', e.present ? e.present.length : 'all',
          'sc0', e.scopes ? JSON.stringify(e.scopes[0]) : '-', 'st', e.track && e.track.states ? 'S' : '');
      }
    }
  }
  // 1. a merge groupTransitions the value axis: matched leaves update at 0
  {
    const c = byId(cases, 'merge-bar-data');
    const ax = c.elements.filter(e => e.owner === 'yAxis0');
    const moving = ax.filter(e => e.scopes && e.scopes[si(0)].startsWith('update'));
    g('merge-axis-transition', moving.some(e => e.id.includes('/label_')) && moving.some(e => e.id.includes('/line_'))
      && moving.some(e => e.id.includes('/ticks_')), moving.map(e => e.id).join(' '));
    g('merge-views-kept', c.views.every(v => same(v, c.views0)), JSON.stringify([c.views0, c.views[0]]));
    const bars = c.elements.filter(e => e.owner === 'series0:bar' && e.type === 'rect');
    g('merge-bars-update', bars.length === 5 && bars.every(e => e.scopes && e.scopes[si(0)] === 'update:shape'),
      JSON.stringify(bars.map(e => e.scopes && e.scopes[si(0)])));
  }
  // 2. replaceMerge: b gone at once (no leave), a and c kept
  {
    const c = byId(cases, 'replace-remove-series');
    const b = c.elements.filter(e => e.owner.startsWith('series1:'));
    g('replace-removed-at-once', b.length === 0 && c.views[0].series1 === undefined,
      JSON.stringify([b.map(e => e.id), c.views[0]]));
    g('replace-kept-views', c.views0.series0 === c.views[si(0)].series0 && c.views0.series2 === c.views[si(0)].series2
      && c.views0.yAxis0 === c.views[si(0)].yAxis0, JSON.stringify([c.views0, c.views[si(0)]]));
  }
  // 3. markers: the markPoint symbol is the same element, updating
  {
    const c = byId(cases, 'merge-markers');
    const mp = c.elements.filter(e => e.owner.startsWith('markPoint') && e.role === 'el' && e.type === 'group'
      && e.dataIndex === 0);
    g('marker-point-kept', mp.length === 1 && !mp[0].present && mp[0].scopes && mp[0].scopes[si(0)].includes('update'),
      JSON.stringify(mp.map(e => [e.id, e.present, e.scopes && e.scopes[si(0)]])));
    const ml = c.elements.filter(e => e.owner.startsWith('markLine') && e.type === 'ec-line');
    g('marker-line-kept', ml.length === 1 && !ml[0].present && ml[0].scopes && ml[0].scopes[si(0)].includes('update'),
      JSON.stringify(ml.map(e => [e.id, e.present, e.scopes && e.scopes[si(0)]])));
  }
  // 4. a hover, a highlight and a select held through the merge
  {
    const c = byId(cases, 'merge-hover');
    const b = c.elements.find(e => e.owner === 'series0:bar' && e.dataIndex === 2 && e.type === 'rect');
    const st = b.trackText.states;
    g('hover-held-merge', st[si(401)] === 'emphasis' && st[si(800)] === 'emphasis' && st[si(1000)] === '',
      JSON.stringify(st));
    const s = byId(cases, 'merge-select');
    const sb = s.elements.find(e => e.owner === 'series0:bar' && e.dataIndex === 2 && e.type === 'rect');
    // select from the action on, through the merge, never dropped
    g('select-held-merge', !sb.track || !sb.track.states, JSON.stringify(sb.trackText && sb.trackText.states));
    g('select-held-merge-final', sb.finalText.states === 'select', JSON.stringify(sb.finalText.states));
  }
  // 5. the lazy merge starts from the frame's step, the synchronous one from
  // the frame before
  {
    const a = elOf(byId(cases, 'merge-interrupt'), 'series0:bar/0');
    const b = elOf(byId(cases, 'merge-lazy'), 'series0:bar/0');
    g('lazy-after-the-step', !!(a && b && a.track && b.track && a.track['shape.height'][si(150)] !== b.track['shape.height'][si(150)]
      && a.track['shape.height'][si(116)] === b.track['shape.height'][si(116)]),
    JSON.stringify([a && a.trackText['shape.height'], b && b.trackText['shape.height']]));
  }
  // 6. the legend hides b through a merge: its view kept and remove()d -- its bars fade
  {
    const c = byId(cases, 'merge-legend-hide');
    const off = c.elements.filter(e => e.owner === 'series1:bar' && e.type === 'rect' && e.scopes
      && e.scopes[si(0)].includes('leave:'));
    g('merge-legend-fade', off.length === 5, JSON.stringify(off.map(e => e.id)));
  }
  // 7. a replaced axis is a new view: none of its leaves move
  {
    const c = byId(cases, 'replace-axis');
    const x = c.elements.filter(e => e.owner === 'xAxis0' && e.scopes && e.scopes.some(s => s !== ''));
    const y = c.elements.filter(e => e.owner === 'yAxis0' && e.scopes && e.scopes[si(0)].startsWith('update'));
    g('replaced-axis-new-view', x.length === 0 && y.length > 0 && c.views0.xAxis0 !== c.views[si(0)].xAxis0
      && c.views0.yAxis0 === c.views[si(0)].yAxis0, JSON.stringify([x.map(e => e.id), y.length, c.views0, c.views[0]]));
  }
  // 7a. the same with the id regenerated: a new view all the same
  {
    const c = byId(cases, 'replace-axis-same-id');
    const y = c.elements.filter(e => e.owner === 'yAxis0' && e.scopes && e.scopes.some(s => s !== ''));
    const all = c.elements.filter(e => e.owner === 'yAxis0');
    g('replaced-axis-same-id-new-view', y.length === 0 && all.length > 0 && c.views0.yAxis0 !== c.views[si(0)].yAxis0
      && c.views0.xAxis0 === c.views[si(0)].xAxis0, JSON.stringify([y.map(e => e.id), c.views0, c.views[0]]));
  }
  // 7b. a brand new series takes no hover with it
  {
    const c = byId(cases, 'replace-hover');
    const fresh = c.elements.filter(e => e.owner === 'series0:bar' && e.type === 'rect' && e.present
      && e.present[0] === si(400));
    g('replace-hover-new-elements', fresh.length === 5 && fresh.every(e => e.scopes[si(400)] === 'enter:shape'
      && e.finalText.states === '' && !(e.track && e.track.states)), JSON.stringify(fresh.map(e => [e.id, e.scopes[si(400)]])));
  }
  // 8. a type change: a new view
  {
    const c = byId(cases, 'merge-type-change');
    const bars = c.elements.filter(e => e.owner === 'series1:bar');
    g('type-change-new-view', bars.length === 0 && c.views0.series1 !== c.views[si(0)].series1
      && c.views0.series0 === c.views[si(0)].series0, JSON.stringify([bars.map(e => e.id), c.views0, c.views[0]]));
  }
  for (const c of cases) g('settled-' + c.id, c.clips[c.clips.length - 1] === 0, c.id + ' ' + c.clips.join(','));
  return out;
}

function generate() {
  const cases = [];
  for (const c of CASES) {
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, option: c.option, events: r.events, clips: r.clips, views0: r.views0,
      views: r.views,
      elements: r.elements });
  }
  const gs = guards(cases);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'AN6: a merge setOption as an update. A case sets `option` at T0 and settles; then at each sample t of '
      + 'samplesMs: the events at t (over: handler.mousemove at x,y; out: mousemove at 3,3; action: dispatchAction; '
      + 'setOption: chart.setOption(option, opts || {}) -- a merge, opts may carry replaceMerge and lazyUpdate; a '
      + 'synchronous one flushes on its own), then NOW = T1 + t and one zr.animation.update() unless a synchronous '
      + 'setOption flushed (a lazy one renders inside that frame), then the record. Elements as '
      + 'advchart-full-update-anim.json, plus the marker views (owner markPoint<i> / markLine<i>, recorded by '
      + 'identity). views: per sample, the view object of every series and axis model, numbered in the order first '
      + 'seen (the numbering starts with the settled render).',
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
