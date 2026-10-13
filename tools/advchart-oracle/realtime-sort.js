// D4 (batch 135): realtimeSort, the bar race. BarView._enableRealtimeSort on a
// bar series over a category axis of a cartesian2d: the first render with
// data dispatches changeAxisOrder with isInitSort (the order of the data
// values, descending; pending, run after setOption's flush); every later
// render registers a zr `rendered` listener that reads every bar's CURRENT
// length (|height| on a horizontal base axis, |width| on a vertical one),
// and when the ticks are no longer in descending order and the new order
// differs inside the axis' extent, removes itself and dispatches
// changeAxisOrder with the new ordinalNumbers. The action writes
// categorySortInfo onto every axis model of componentType (the payload's
// axisId is no query key) and runs a full update: the bars move along the
// base axis on the AXIS model's update timing (the value tween keeps
// running), the axis labels -- anid 'label_' + the RAW ordinal -- move by
// groupTransition, the bar labels' counts go on.
//
// The harness is merge-anim.js' own (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random), with one
// change: zr.animation.stage.update is zr._flush(false), as in a browser, so
// a frame is the clips' step, then the flush and its `rendered` -- which is
// where the race looks at the bars. A FRAME every 20 ms from T0: the events
// of t (a setOption flushes on its own), else NOW = T0 + t and one
// zr.animation.update(); then the record.
//
// Recorded per frame: the clip count; each category axis model's
// categorySortInfo; for every bar series, per data index, the bar's shape
// x / y / width / height and ignore, and its label's text; every leaf of
// every cartesian axis view's _axisGroup that has an anid, BY ANID (a
// label's x / y / rotation and text, a line's ends); and every
// changeAxisOrder event with the frame it came in.
//
// Run: node tools/advchart-oracle/realtime-sort.js
//   -> tests/fixtures/advchart-realtime-sort.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-realtime-sort.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const FRAME = 20;

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

function clipCount(zr) {
  let n = 0;
  for (let c = zr.animation._head; c; c = c.next) n++;
  return n;
}

function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  const zr = chart.getZr();
  // a browser's frame: the step, then the flush (and its `rendered`)
  zr.animation.stage = { update: () => zr._flush(false) };
  return chart;
}

// ---------- the records ----------
// one element: per frame a map key -> [hex or string, text]
function newRec(id, kind) {
  return { id, kind, snaps: [] };
}
function put(o, k, v) {
  if (typeof v === 'number') o[k] = [hex(v), text(v)];
  else if (typeof v === 'string') o[k] = [v, v];
  else if (typeof v === 'boolean') o[k] = [v, String(v)];
}

function barSnap(el) {
  const o = {};
  for (const k of ['x', 'y', 'width', 'height']) put(o, 'shape.' + k, el.shape[k]);
  put(o, 'ignore', !!el.ignore);
  const t = el.getTextContent();
  if (t) put(o, 'text', String(t.style.text));
  put(o, 'animators', (el.animators || []).length);
  return o;
}

function leafSnap(el) {
  const o = {};
  if (el.type === 'text') {
    put(o, 'x', el.x);
    put(o, 'y', el.y);
    put(o, 'rotation', el.rotation);
    put(o, 'text', String(el.style.text));
  }
  else if (el.shape) {
    for (const k of ['x1', 'y1', 'x2', 'y2']) if (typeof el.shape[k] === 'number') put(o, 'shape.' + k, el.shape[k]);
  }
  put(o, 'animators', (el.animators || []).length);
  return o;
}

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

function sortInfos(chart) {
  const out = {};
  const model = chart.getModel();
  for (const t of ['xAxis', 'yAxis']) {
    model.eachComponent(t, m => {
      const si = m.option.categorySortInfo;
      out[t + m.componentIndex] = si ? si.ordinalNumbers.slice() : null;
    });
  }
  return out;
}

function summarize(recs, n) {
  const out = [];
  for (const rec of recs) {
    const keys = new Set();
    rec.snaps.forEach(s => { if (s) Object.keys(s).forEach(k => keys.add(k)); });
    const present = [];
    for (let i = 0; i < n; i++) if (rec.snaps[i]) present.push(i);
    const final = {};
    const finalText = {};
    const track = {};
    const last = rec.snaps[present[present.length - 1]];
    for (const k of [...keys].sort()) {
      const vals = present.map(i => rec.snaps[i][k]);
      const constant = vals.every(v => v !== undefined && v[0] === vals[0][0]);
      if (last && last[k] !== undefined) {
        final[k] = last[k][0];
        finalText[k] = last[k][1];
      }
      if (!constant) {
        track[k] = [];
        for (let i = 0; i < n; i++) {
          const s = rec.snaps[i];
          track[k].push(s && s[k] !== undefined ? s[k][0] : null);
        }
      }
    }
    out.push({ id: rec.id, kind: rec.kind, present: present.length === n ? null : present, final, finalText,
      track: Object.keys(track).length ? track : null });
  }
  return out;
}

function runCase(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  const zr = chart.getZr();
  const events = [];
  let rendered = 0;
  zr.on('rendered', () => { rendered++; });
  chart.on('changeaxisorder', e => {
    const p = JSON.parse(JSON.stringify(e));
    events.push({ at: NOW - T_BASE, payload: p });
  });
  const frames = [];
  for (let t = 0; t <= c.end; t += FRAME) frames.push(t);
  const bars = new Map();
  const leaves = new Map();
  const recs = [];
  const clips = [];
  const sorts = [];
  const renders = [];
  try {
    frames.forEach((t, fi) => {
      NOW = T_BASE + t;
      let flushed = false;
      for (const e of [{ at: 0, type: 'setOption', option: c.option }].concat(c.events)) {
        if (e.at !== t) continue;
        if (e.type === 'setOption' && e.lazy) {
          // [milestone D1-D4] lazyUpdate: merged now, rendered on the next
          // frame -- or by an action dispatched before it
          chart.setOption(JSON.parse(JSON.stringify(e.option)), { lazyUpdate: true });
        }
        else if (e.type === 'setOption') {
          chart.setOption(JSON.parse(JSON.stringify(e.option)), e.notMerge ? true : undefined);
          flushed = true;
        }
        else if (e.type === 'action') chart.dispatchAction(JSON.parse(JSON.stringify(e.payload)));
        else must(false, 'unknown event ' + e.type);
      }
      if (!flushed) zr.animation.update();
      clips.push(clipCount(zr));
      sorts.push(sortInfos(chart));
      renders.push(rendered);
      const model = chart.getModel();
      model.eachSeries(s => {
        if (s.subType !== 'bar') return;
        const d = s.getData();
        for (let i = 0; i < d.count(); i++) {
          const el = d.getItemGraphicEl(i);
          if (!el) continue;
          const id = 'series' + s.seriesIndex + '/' + i;
          let rec = bars.get(id);
          if (!rec) {
            rec = newRec(id, 'bar');
            bars.set(id, rec);
            recs.push(rec);
          }
          rec.snaps[fi] = barSnap(el);
        }
      });
      for (const a of axisLeaves(chart)) {
        let rec = leaves.get(a.id);
        if (!rec) {
          rec = newRec(a.id, a.el.type === 'text' ? 'axisLabel' : 'axisLine');
          leaves.set(a.id, rec);
          recs.push(rec);
        }
        must(!rec.snaps[fi], 'two leaves of anid ' + a.id);
        rec.snaps[fi] = leafSnap(a.el);
      }
    });
  }
  finally {
    chart.dispose();
  }
  return { framesMs: frames, clips, sorts, renders, events, elements: summarize(recs, frames.length) };
}

// ---------- the cases ----------
const CATS = ['A', 'B', 'C', 'D', 'E'];
const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666', '#73c0de'];
const set = (at, option) => ({ at, type: 'setOption', option });
const label = { show: true, position: 'right', valueAnimation: true };
const labelTop = { show: true, position: 'top', valueAnimation: true };

// the gallery's bar race: horizontal bars, the category y axis inverse with
// max 2 (the top three), its own 300 ms, the series' updates 1000 ms linear
function raceH(extra) {
  return Object.assign({
    color: PAL,
    xAxis: { max: 'dataMax' },
    yAxis: { type: 'category', data: CATS, inverse: true, animationDuration: 300, animationDurationUpdate: 300, max: 2 },
    series: [{ realtimeSort: true, name: 'X', type: 'bar', data: [30, 80, 10, 50, 20], label }],
    animationDuration: 0, animationDurationUpdate: 1000, animationEasing: 'linear', animationEasingUpdate: 'linear',
  }, extra || {});
}
// vertical bars on a category x axis, a growing enter (the init sort lands
// in the middle of it)
function raceV(extra, xAxisExtra) {
  return Object.assign({
    color: PAL,
    xAxis: Object.assign({ type: 'category', data: CATS, animationDurationUpdate: 400 }, xAxisExtra || {}),
    yAxis: { type: 'value', max: 100 },
    series: [{ realtimeSort: true, type: 'bar', data: [20, 60, 35, 90, 10], label: labelTop }],
    animationDuration: 500, animationDurationUpdate: 800, animationEasing: 'linear', animationEasingUpdate: 'cubicOut',
  }, extra || {});
}

const CASES = [
  { id: 'race-h', note: 'the gallery\'s race: the init sort at 0 (B D A E C), the top three shown; data at 100 '
    + 'overtakes as the bars grow -- several reorders in the middle of the 1000 ms tween, the bars sliding on '
    + 'the y axis\' 300 ms, the clipped ones ignored; more data at 1300',
  option: raceH(), end: 3600,
  events: [set(100, { series: [{ type: 'bar', data: [30, 80, 95, 50, 85] }] }),
    set(1300, { series: [{ type: 'bar', data: [120, 82, 96, 140, 86] }] })] },
  { id: 'race-v', note: 'vertical bars, the x axis category; the enter grows for 500 ms and the init sort lands on '
    + 'it (the counts restart a frame later); a reorder at every crossing of the 800 ms cubicOut update, the bars '
    + 'sliding on the x axis\' 400 ms',
  option: raceV(), end: 3000,
  events: [set(600, { series: [{ type: 'bar', data: [85, 15, 70, 40, 95] }] }),
    set(1500, { series: [{ type: 'bar', data: [50, 52, 48, 51, 49] }] })] },
  { id: 'race-v-inverse', note: 'the same on an inverse category x axis: the order runs right to left',
    option: raceV({}, { inverse: true }), end: 1800,
    events: [set(600, { series: [{ type: 'bar', data: [85, 15, 70, 40, 95] }] })] },
  { id: 'race-ties', note: 'ties: the sort is V8\'s stable sort, a tie keeps the data order; a tie is not a '
    + 'change (only `value > lastValue` is); an update to all equal values reorders nothing',
  option: raceV({ series: [{ realtimeSort: true, type: 'bar', data: [40, 60, 40, 60, 20], label: labelTop }] }),
  end: 2200,
  events: [set(600, { series: [{ type: 'bar', data: [50, 50, 50, 50, 50] }] }),
    set(1000, { series: [{ type: 'bar', data: [50, 50, 70, 50, 50] }] })] },
  { id: 'race-two-series', note: 'two bar series on the category axis, only the first racing: the second moves '
    + 'with the axis order at ITS OWN update timing (a plain update), the racing one on the axis\' timing',
  option: raceV({ series: [{ realtimeSort: true, type: 'bar', data: [20, 60, 35, 90, 10], label: labelTop },
    { type: 'bar', data: [5, 10, 15, 20, 25] }] }), end: 1800,
  events: [set(600, { series: [{ type: 'bar', data: [85, 15, 70, 40, 95] }, { type: 'bar', data: [25, 20, 15, 10, 5] }] })] },
  { id: 'race-no-change', note: 'an update that keeps the order: the bars grow, no changeAxisOrder after the '
    + 'init sort',
  option: raceH({ animationDurationUpdate: 600 }), end: 1200,
  events: [set(100, { series: [{ type: 'bar', data: [40, 90, 15, 60, 25] }] })] },
  { id: 'race-out-of-view', note: 'max 1: the two hidden bars swap -- the order changed, but not inside the '
    + 'extent: no dispatch (checked every frame); then one of them climbs into view',
  option: raceH({ yAxis: { type: 'category', data: CATS, inverse: true, animationDurationUpdate: 300, max: 1 },
    animationDurationUpdate: 600 }),
  end: 2400,
  events: [set(100, { series: [{ type: 'bar', data: [30, 80, 25, 50, 10] }] }),
    set(900, { series: [{ type: 'bar', data: [30, 80, 25, 50, 99] }] })] },
  { id: 'race-anim-off', note: 'animation false: the bars are at their values at once, so the `rendered` of '
    + 'setOption\'s own flush finds the new order -- the reorder is dispatched inside setOption',
  option: raceH({ animation: false }), end: 200,
  events: [set(100, { series: [{ type: 'bar', data: [90, 80, 10, 50, 20] }] })] },
  { id: 'race-partial-data', note: 'six categories, five data: the sort info has five numbers, setSortInfo puts '
    + 'the unused category after them',
  option: raceV({ xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'], animationDurationUpdate: 400 },
    series: [{ realtimeSort: true, type: 'bar', data: [20, 60, 35, 90, 10], label: labelTop }] }), end: 1600,
  events: [set(600, { series: [{ type: 'bar', data: [85, 15, 70, 40, 95] }] })] },
  { id: 'race-interrupt', note: 'two updates 120 ms apart: the counts go on from their interpolated values, the '
    + 'bars from where they are',
  option: raceH(), end: 2000,
  events: [set(100, { series: [{ type: 'bar', data: [30, 80, 95, 50, 85] }] }),
    set(220, { series: [{ type: 'bar', data: [100, 20, 40, 120, 60] }] })] },
  { id: 'action-change-order', note: 'no race: changeAxisOrder dispatched by hand on a category x axis -- the axis '
    + 'takes the order, the bars update on the series\' timing, the labels transition; no setOption has given the '
    + 'counts a previous value, so each order\'s render counts them again from 0 at enter timing (200 ms); a '
    + 'second one at 600 names three ordinals',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [20, 60, 35, 90, 10], label: labelTop }], animationDuration: 200,
    animationDurationUpdate: 500 },
  end: 1400,
  events: [{ at: 300, type: 'action', payload: { type: 'changeAxisOrder', componentType: 'xAxis', axisId: 0,
    sortInfo: { ordinalNumbers: [3, 1, 2, 0, 4] } } },
  { at: 600, type: 'action', payload: { type: 'changeAxisOrder', componentType: 'xAxis', axisId: 0,
    sortInfo: { ordinalNumbers: [4, 0, 2] } } }] },
  { id: 'action-init-sort-adds', note: '[milestone D1-D4] no race: a lazy merge adds a sixth row, and an init '
    + 'sort dispatched by hand in the same frame renders it -- the bar the init sort\'s render adds takes its '
    + 'layout at once (BarView: isInitSort -> attr), the five it updates likewise',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 100 },
    series: [{ type: 'bar', data: [20, 60, 35, 90, 10] }], animationDuration: 200, animationDurationUpdate: 500 },
  end: 1000,
  events: [{ at: 300, type: 'setOption', lazy: true, option: { xAxis: { data: CATS.concat(['F']) },
    series: [{ data: [20, 60, 35, 90, 10, 70] }] } },
  { at: 300, type: 'action', payload: { type: 'changeAxisOrder', componentType: 'xAxis', axisId: 0, isInitSort: true,
    sortInfo: { ordinalNumbers: [3, 1, 2, 0, 4] } } }] },
  { id: 'action-order-in-flight', note: '[milestone D1-D4] the hand-dispatched orders of action-change-order, the '
    + 'second at 400 while the first one\'s counts (from 0, 200 ms) are still running: they count again from '
    + 'their interpolated values, not from 0',
  option: { color: PAL, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [20, 60, 35, 90, 10], label: labelTop }], animationDuration: 200,
    animationDurationUpdate: 500 },
  end: 1000,
  events: [{ at: 300, type: 'action', payload: { type: 'changeAxisOrder', componentType: 'xAxis', axisId: 0,
    sortInfo: { ordinalNumbers: [3, 1, 2, 0, 4] } } },
  { at: 400, type: 'action', payload: { type: 'changeAxisOrder', componentType: 'xAxis', axisId: 0,
    sortInfo: { ordinalNumbers: [4, 0, 2] } } }] },
  { id: 'race-v-some-kept', note: '[milestone D1-D4] the update at 600 keeps A, B and D: their labels take the '
    + 'value as prevValue (no count), so the reorders after it do not count them again',
  option: raceV(), end: 1800,
  events: [set(600, { series: [{ type: 'bar', data: [20, 60, 70, 90, 95] }] })] },
  { id: 'race-clip-false', note: '[milestone D1-D4] clip: false on the racing series: it clips anyway '
    + '(BarView: needsClip = clip || realtimeSort), the two bars past max ignored',
  option: raceH({ series: [{ realtimeSort: true, name: 'X', type: 'bar', data: [30, 80, 10, 50, 20], label, clip: false }] }),
  end: 2400,
  events: [set(100, { series: [{ type: 'bar', data: [30, 80, 95, 50, 85] }] })] },
  { id: 'race-partial-zero', note: '[milestone D1-D4] race-partial-data with a bar of nought: the category with '
    + 'no bar is Number.MIN_VALUE, above the nought, so the order has moved; the tick past the rows is a '
    + 'difference in view, and every rendered frame dispatches the same order again',
  option: raceV({ xAxis: { type: 'category', data: ['A', 'B', 'C', 'D', 'E', 'F'], animationDurationUpdate: 400 },
    series: [{ realtimeSort: true, type: 'bar', data: [20, 60, 35, 90, 0], label: labelTop }] }), end: 800,
  events: [] },
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
const fi = (c, t) => c.framesMs.indexOf(t);
function guards(cases) {
  const out = [];
  const g = (name, ok, detail) => {
    must(ok, 'guard ' + name + ': ' + detail);
    out.push(name);
  };
  if (process.env.DUMP) {
    for (const c of cases) {
      console.log('CASE', c.id, 'events', JSON.stringify(c.events.map(e => [e.at, e.payload.isInitSort ? 'init' : '',
        e.payload.sortInfo && e.payload.sortInfo.ordinalNumbers.join('')])));
      console.log('  clips', c.clips.join(','));
    }
  }
  // 1. the init sort: dispatched inside the first setOption, isInitSort,
  // the data's order descending, onto the y axis
  {
    const c = byId(cases, 'race-h');
    const e0 = c.events[0];
    g('init-sort-first', e0 && e0.at === 0 && e0.payload.isInitSort === true && e0.payload.componentType === 'yAxis'
      && e0.payload.axisId === 0 && e0.payload.sortInfo.ordinalNumbers.join('') === '13042'
      && c.sorts[0].yAxis0 && c.sorts[0].yAxis0.join('') === '13042', JSON.stringify([e0, c.sorts[0]]));
    // the clipped bars (A and E below the top three after the init sort...)
    // are ignored, and still there
    const hidden = c.elements.filter(e => e.kind === 'bar' && e.finalText.ignore === 'true');
    g('clipped-kept-ignored', hidden.length === 2, JSON.stringify(hidden.map(e => e.id)));
    // reorders in the middle of the update tween, none of them init
    const later = c.events.filter(e => e.at > 100 && e.at < 1300);
    g('race-reorders', later.length >= 2 && later.every(e => !e.payload.isInitSort), JSON.stringify(later));
    // the y axis labels move by their raw ordinal anid
    const lb = c.elements.filter(e => e.id.startsWith('yAxis0/label_') && e.track && e.track.y);
    g('labels-move', lb.length >= 2, JSON.stringify(lb.map(e => e.id)));
  }
  // 2. the init sort lands in the middle of the vertical enter
  {
    const c = byId(cases, 'race-v');
    const b = elOf(c, 'series0/3');
    g('init-sort-mid-enter', c.events[0].at === 0 && c.events[0].payload.componentType === 'xAxis'
      && b && b.track && b.track['shape.height'] && b.track['shape.height'][fi(c, 20)] !== b.final['shape.height'],
    JSON.stringify(b && b.track && b.track['shape.height'].slice(0, 5)));
  }
  // 3. ties keep the data order; the all-equal update dispatches nothing
  {
    const c = byId(cases, 'race-ties');
    g('ties-stable', c.events[0].payload.sortInfo.ordinalNumbers.join('') === '13024',
      JSON.stringify(c.events[0].payload));
    g('ties-no-change', c.events.filter(e => e.at >= 600 && e.at < 1000).length === 0, JSON.stringify(c.events));
  }
  // 4. no change: the init sort only
  {
    const c = byId(cases, 'race-no-change');
    g('no-change-no-event', c.events.length === 1 && c.events[0].payload.isInitSort, JSON.stringify(c.events));
  }
  // 5. out of view: the hidden swap dispatches nothing; the climb does
  {
    const c = byId(cases, 'race-out-of-view');
    g('out-of-view-silent', c.events.filter(e => e.at > 0 && e.at < 900).length === 0, JSON.stringify(c.events));
    g('out-of-view-climb', c.events.filter(e => e.at >= 900).length >= 1, JSON.stringify(c.events));
  }
  // 6. animation off: the reorder inside setOption
  {
    const c = byId(cases, 'race-anim-off');
    g('anim-off-in-setoption', c.events.length === 2 && c.events[1].at === 100
      && c.sorts[fi(c, 100)].yAxis0.join('') === '01342', JSON.stringify([c.events, c.sorts[fi(c, 100)]]));
  }
  // 7. the partial data: five numbers in the event, six in the scale
  {
    const c = byId(cases, 'race-partial-data');
    g('partial-five', c.events[0].payload.sortInfo.ordinalNumbers.length === 5, JSON.stringify(c.events[0]));
  }
  // 8. the hand-dispatched action reorders the axis
  {
    const c = byId(cases, 'action-change-order');
    g('action-sort', c.sorts[fi(c, 300)].xAxis0.join('') === '31204' && c.events.length === 2,
      JSON.stringify([c.sorts[fi(c, 300)], c.events]));
    // the counts start again from 0 (prevValue null)
    const b = elOf(c, 'series0/3');
    g('action-recount', b && b.track && b.track.text && b.track.text[fi(c, 280)] === '90'
      && b.track.text[fi(c, 320)] !== '90' && Number(b.track.text[fi(c, 320)]) < 20,
    JSON.stringify(b && b.track && b.track.text && b.track.text.slice(13, 20)));
  }
  if (process.env.NOSETTLE) return out;
  // race-partial-zero never settles: every rendered frame dispatches again
  for (const c of cases) {
    if (c.id === 'race-partial-zero') continue;
    g('settled-' + c.id, c.clips[c.clips.length - 1] === 0, c.id + ' ' + c.clips.join(','));
  }
  {
    const c = byId(cases, 'race-partial-zero');
    g('partial-zero-redispatches', c.events.filter(e => !e.payload.isInitSort).length >= 10, JSON.stringify(c.events.length));
  }
  return out;
}

function generate() {
  const cases = [];
  for (const c of CASES) {
    const r = runCase(c);
    cases.push({ id: c.id, note: c.note, option: c.option, events: c.events, end: c.end,
      framesMs: r.framesMs, clips: r.clips, renders: r.renders, sorts: r.sorts, sortEvents: r.events,
      elements: r.elements });
  }
  for (const c of cases) {
    c.inputs = c.events;
    c.events = c.sortEvents;
    delete c.sortEvents;
  }
  const gs = guards(cases);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'D4: realtimeSort. A case sets `option` at T0 (its own flush; the init sort runs after it); then a frame '
      + 'every ' + FRAME + ' ms: the inputs at t (setOption: a merge, flushing; action: dispatchAction), else '
      + 'NOW = T0 + t and zr.animation.update() -- whose stage is zr._flush(false), so `rendered` follows each '
      + 'stepped frame -- then the record. elements: bars by series and data index (shape, ignore, label text, '
      + 'animators), axis leaves by owner/anid; track[k][frame] where the value changes, final otherwise; '
      + 'present: the frames an element is there (null: all); finalText the last values as JavaScript prints them. events: every changeaxisorder event, at the frame '
      + 'it came in. sorts: each category axis model\'s categorySortInfo per frame.',
    W, H, seed: SEED, frameMs: FRAME,
    clock: { T0: T_BASE },
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
