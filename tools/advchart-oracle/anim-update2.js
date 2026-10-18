/*
Upstream's own answers for the fix phase, batch F3b: the UPDATE transitions
batches 90-99 (AN3, AN5, AN6) and F3a left out.

  step        a step line's update (chart/line/LineView.ts _doUpdateAnimation,
              `if (step)`): the lineAnimationDiff arrays (Float32) turned into
              steps -- plain number arrays -- the polyline's points tweened
              from the stepped current to the stepped next, its `__points`
              (the diff itself) beside them, the symbols following
              `__points`; the polygon's stackedOnPoints stepped against the
              line's own points; turnPointsIntoStep for 'start', 'middle',
              'end', a vertical base axis, connectNulls.
  axis        the cartesian axes' groupTransition (util/graphic.ts) beyond
              the line, ticks, labels and split lines: the axis name
              ('name', a Text decomposed onto the axis group), minor ticks
              ('minorticks_' + interval + '_' + value, through the axis
              group's matrix), minor split lines ('minor_line_' + value),
              split areas ('area_' + the band's first tick value, a Rect
              from the previous edge).

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32 and zrender's width table measuring text.

  node tools/advchart-oracle/anim-update2.js

writes tests/fixtures/advchart-anim-update2.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000); strings, booleans and counts are plain JSON.

Top level: source, version, seed, measure {firstCode, ratio[] (hex)}, clock
{T0}, notes[], cases[], guards[].

A case: id, group, note, W, H, option, probes[], events[]. The first
setOption is at T0. An event, in order, at t ms after T0:
  {t, do: 'sample', rec}       zr.animation.update(), then what the probes
                               read
  {t, do: 'merge', option}     setOption(option)        (its flush steps)
  {t, do: 'notMerge', option}  setOption(option, true)
  {t, do: 'action', action}    dispatchAction(action)
A sample's rec, by probe:
  line   per line series s: 'line<s>/points', 'line<s>/__points' (only when it
         is not the points array itself), 'line<s>/n' (the polyline's
         animators with a clip), 'line<s>/stackedOnPoints' and
         'line<s>/areaN' (the polygon's), 'line<s>/sym<raw index>' [x, y] of
         each symbol group.
  axis   per cartesian axis view, every leaf of its _axisGroup with an anid:
         'axis:<xAxis|yAxis><index>/<anid>' {x, y, rotation, shape.<k> for
         each number of its shape, n (its animators with a clip)}.

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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-update2.json');

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
// a number array (a typed one too) as hex; undefined items NaN
const arr = a => Array.from(a, x => hex(typeof x === 'number' ? x : NaN));
const nClip = el => el.animators.filter(a => a.getClip()).length;

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

// ---------------------------------------------------------------------------
// the probes
// ---------------------------------------------------------------------------
const PROBES = {
  axis(chart, rec) {
    (chart._componentsViews || []).forEach(v => {
      const m = v && v.__model;
      if (!m || (m.mainType !== 'xAxis' && m.mainType !== 'yAxis') || !v._axisGroup) return;
      const owner = m.mainType + m.componentIndex;
      v._axisGroup.traverse(el => {
        if (el.isGroup || !el.anid) return;
        const o = { x: hex(el.x), y: hex(el.y), rotation: hex(el.rotation), n: nClip(el) };
        if (el.shape) {
          for (const k of Object.keys(el.shape)) {
            if (typeof el.shape[k] === 'number') o['shape.' + k] = hex(el.shape[k]);
          }
        }
        if (el.style && typeof el.style.text === 'string') o.text = el.style.text;
        must(!rec['axis:' + owner + '/' + el.anid], 'two leaves of anid ' + el.anid);
        rec['axis:' + owner + '/' + el.anid] = o;
      });
    });
  },
  line(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'line') return;
      const v = chart.getViewOfSeriesModel(sm);
      const key = 'line' + sm.seriesIndex;
      const pl = v._polyline;
      if (pl) {
        rec[key + '/points'] = arr(pl.shape.points);
        if (pl.shape.__points && pl.shape.__points !== pl.shape.points) rec[key + '/__points'] = arr(pl.shape.__points);
        rec[key + '/n'] = nClip(pl);
      }
      const pg = v._polygon;
      if (pg) {
        rec[key + '/stackedOnPoints'] = arr(pg.shape.stackedOnPoints);
        rec[key + '/areaN'] = nClip(pg);
      }
      const data = v._symbolDraw && v._symbolDraw._data;
      if (data) {
        data.each(i => {
          const el = data.getItemGraphicEl(i);
          if (el) rec[key + '/sym' + data.getRawIndex(i)] = [hex(el.x), hex(el.y)];
        });
      }
    });
  },
};

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CASES = [];
function add(group, id, note, option, probes, events, more) {
  CASES.push(Object.assign({ group, id, note, W: 400, H: 300, option, probes, events }, more));
}
const T1 = 3000;
const after = (ts, from) => ts.map(t => ({ t: from + t, do: 'sample' }));
const S_STEP = [0, 1, 16, 50, 100, 150, 299, 300, 301, 500, 999, 1000, 1001, 1500];
const CATS = ['a', 'b', 'c', 'd', 'e'];
const LIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };

add('step', 'step-start', "a step line ('start', step: true) whose values change: the stepped points tween, __points beside them, the symbols follow __points; 1000 ms linear",
  { animation: true, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 6 },
    series: [Object.assign({ type: 'line', step: true, data: [1, 3, 2, 5, 4] }, LIN)] },
  ['line'],
  [{ t: 0, do: 'sample' }, { t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [2, 1, 4, 3, 5] }] } }, ...after(S_STEP, T1)]);

add('step', 'step-middle-area', "step 'middle' with an area, on the default update timing (300 ms cubicInOut): a category added at the end (a '+' point from where the new datum sits in the old coordinates) and the values moved; the stacked-on points stepped against the line's",
  { animation: true, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 8 },
    series: [{ type: 'line', step: 'middle', areaStyle: {}, data: [1, 3, 2, 5, 4] }] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { xAxis: { data: ['a', 'b', 'c', 'd', 'e', 'f'] }, series: [{ data: [2, 1, 4, 3, 5, 7] }] } },
    ...after(S_STEP, T1)]);

add('step', 'step-end-vertical', "step 'end' on a vertical base axis (a category y axis, the value x): the turn runs along y",
  { animation: true, yAxis: { type: 'category', data: CATS }, xAxis: { type: 'value', max: 6 },
    series: [Object.assign({ type: 'line', step: 'end', data: [1, 3, 2, 5, 4] }, LIN)] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [4, 4, 1, 2, 3] }] } }, ...after(S_STEP, T1)]);

add('step', 'step-connect', "a step line with connectNulls: the nulls filtered out before the turn -- the current and the next stepped arrays differ in length when a null moves (fillArray pads or cuts the current)",
  { animation: true, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 6 },
    series: [Object.assign({ type: 'line', step: 'start', connectNulls: true, data: [1, null, 3, 4, 2] }, LIN)] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [2, 2, null, null, 5] }] } }, ...after(S_STEP, T1)]);

add('step', 'step-stack', "two stacked step lines with areas: the upper one's stacked-on points are the lower one's, stepped against its own line; then a second update 400 ms in, from where the first stopped",
  { animation: true, xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value', max: 14 },
    series: [Object.assign({ type: 'line', step: 'end', stack: 's', areaStyle: {}, data: [1, 3, 2, 5, 4] }, LIN),
      Object.assign({ type: 'line', step: 'end', stack: 's', areaStyle: {}, data: [2, 2, 3, 1, 4] }, LIN)] },
  ['line'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [3, 1, 4, 2, 5] }, { data: [1, 4, 2, 3, 2] }] } },
    ...after([0, 1, 100, 399, 400], T1),
    { t: T1 + 400, do: 'merge', option: { series: [{ data: [5, 5, 5, 5, 5] }, { data: [1, 1, 1, 1, 1] }] } },
    ...after([400, 401, 600, 1000, 1399, 1400, 1401, 2000], T1)]);

const S_AX = [0, 1, 16, 100, 250, 499, 500, 501, 900];
add('axis', 'axis-value', "a value y axis with minor ticks, minor split lines, split areas and an end name, a category x axis with split areas and a middle name: new data doubles the y extent and the grid moves -- every leaf whose anid the old group had tweens from the old one (500 ms cubicInOut, the axis model's update timing); a minor tick of a new interval appears at once",
  { animation: true, xAxis: { type: 'category', data: CATS, name: 'Category', nameLocation: 'middle', nameGap: 28, splitArea: { show: true } },
    yAxis: { type: 'value', name: 'Value', minorTick: { show: true }, minorSplitLine: { show: true }, splitArea: { show: true } },
    series: [{ type: 'bar', data: [12, 30, 22, 50, 41] }] },
  ['axis'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { grid: { left: 70, right: 40 }, series: [{ data: [24, 60, 44, 100, 82] }] } }, ...after(S_AX, T1)]);

add('axis', 'axis-horizontal', "a horizontal value x axis with minor ticks and minor split lines and a start name, a category y axis with a rotated middle name (nameRotate 30); a dataZoom-free merge that changes the categories (the category labels and areas move by their values) and the x extent; the axes' own update timing 800 ms linear",
  { animation: true, yAxis: { type: 'category', data: CATS, name: 'Kind', nameLocation: 'middle', nameRotate: 30, nameGap: 30, splitArea: { show: true },
    animationDurationUpdate: 800, animationEasingUpdate: 'linear' },
    xAxis: { type: 'value', name: 'Amount', nameLocation: 'start', minorTick: { show: true, splitNumber: 4 }, minorSplitLine: { show: true },
      animationDurationUpdate: 800, animationEasingUpdate: 'linear' },
    series: [{ type: 'bar', data: [5, 9, 3, 7, 6] }] },
  ['axis'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { grid: { top: 40, bottom: 50 }, yAxis: { data: ['a', 'b', 'c', 'd'] }, series: [{ data: [15, 30, 8, 22] }] } },
    ...after([0, 1, 16, 100, 400, 799, 800, 801, 1200], T1)]);

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function readRec(chart, probes) {
  const rec = {};
  probes.forEach(p => PROBES[p](chart, rec));
  return rec;
}
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option),
      probes: c.probes, events: [] };
    quiet(() => chart.setOption(c.option));
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart, c.probes);
      }
      else if (ev.do === 'merge') quiet(() => chart.setOption(ev.option));
      else if (ev.do === 'notMerge') quiet(() => chart.setOption(ev.option, true));
      else if (ev.do === 'action') quiet(() => chart.dispatchAction(ev.action));
      else must(false, 'an event it does not know: ' + ev.do);
      out.events.push(o);
    });
    return out;
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
  // a record at the LAST sample at t ms after T0
  const r = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    const v = smp.rec[key];
    if (typeof v === 'string' && /^[0-9a-f]{16}$/.test(v)) return num(v);
    if (Array.isArray(v) && v.every(x => typeof x === 'string')) return v.map(num);
    return v;
  };
  const S = 'step-start';
  guard('a step line tweens: the polyline animates', r(S, T1 + 500, 'line0/n') === 1);
  guard('the stepped points are not the diff: __points beside them',
    r(S, T1 + 500, 'line0/points').length === 2 * (5 * 2 - 1) && r(S, T1 + 500, 'line0/__points').length === 10);
  guard('mid-way, a stepped point between the old and the new', (() => {
    const a = r(S, T1 - 1, 'line0/points')[3];
    const b = r(S, T1 + 1500, 'line0/points')[3];
    const m = r(S, T1 + 500, 'line0/points')[3];
    return m !== a && m !== b && (m - a) * (b - m) > 0;
  })());
  guard('a symbol follows __points', (() => {
    const p = r(S, T1 + 500, 'line0/__points');
    const s = r(S, T1 + 500, 'line0/sym2');
    return p[4] === s[0] && p[5] === s[1];
  })());
  guard("'middle' doubles the turn", r('step-middle-area', T1 + 100, 'line0/points').length === 2 * (6 * 3 - 2));
  guard('the area tweens its stacked-on points', r('step-middle-area', T1 + 100, 'line0/areaN') === 1);
  guard('a vertical base turns along y', (() => {
    const p = r('step-end-vertical', T1 + 500, 'line0/points');
    return p[2] === p[0] && p[3] !== p[1];
  })());
  guard('connectNulls: the stepped arrays differ in length before and after', r('step-connect', T1 - 1, 'line0/points').length
    !== r('step-connect', T1 + 1500, 'line0/points').length);
  guard('a second update starts from the first one layout, not from where it stood (the diff reads the old _points)', (() => {
    const a = r('step-stack', T1 + 399, 'line1/points')[1];
    const b = r('step-stack', T1 + 401, 'line1/points')[1];
    return Math.abs(a - b) > 5;
  })());
  const A = 'axis-value';
  const ax = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    return smp.rec[key];
  };
  guard('the y axis name tweens', ax(A, T1 + 100, 'axis:yAxis0/name') && ax(A, T1 + 100, 'axis:yAxis0/name').n === 1);
  guard('a minor tick tweens', Object.keys(cs(A).events.find(q => q.t === T1 + 100).rec)
    .some(k => /minorticks_/.test(k) && cs(A).events.find(q => q.t === T1 + 100).rec[k].n === 1));
  guard('a minor split line tweens', Object.keys(cs(A).events.find(q => q.t === T1 + 100).rec)
    .some(k => /minor_line_/.test(k) && cs(A).events.find(q => q.t === T1 + 100).rec[k].n === 1));
  guard('a split area tweens', Object.keys(cs(A).events.find(q => q.t === T1 + 100).rec)
    .some(k => /\/area_/.test(k) && cs(A).events.find(q => q.t === T1 + 100).rec[k].n === 1));
  guard('the category x name moves with the grid', ax(A, T1 + 100, 'axis:xAxis0/name').n === 1);
  guard('a rotated middle name', num(ax('axis-horizontal', T1 - 1, 'axis:yAxis0/name').rotation) !== 0);
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
      'events in order at T0 + t; a sample is zr.animation.update() and a read of what the case\'s probes name.',
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
