/*
Upstream's own answers for spec section 243b (R5-I): the animation edges the
port did not follow.

  candle  CandlestickView._renderNormal: a simple box (candleWidth <= 1.3,
          one stroke from the highest to the lowest point) enters as a full
          box does -- initProps of shape.points out of transInit (every
          point's value coordinate on the open price's), enter timing at the
          row; a candle the data diff ADDS in a later render enters the same
          way; a kept one updateProps its points (update timing, its row).
  funnel  FunnelPiece.updateData: a kept piece updateProps its opacity AND
          its four points (update timing, its row); _updateLabel
          updateProps the label text's style x / y the same way.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32.

  node tools/advchart-oracle/anim-edges.js

writes tests/fixtures/advchart-anim-edges.json (ORACLE_OUT overrides).
Ends with process.exit().

Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000). A case: id, group, note, W, H, option, probes[], rows
(the rows a probe reads, where it does not read them all), events[]
(sample / merge / set (notMerge) / act (dispatchAction) at t ms after T0).
A sample's rec, by probe:
  candle  'cd<s>/<i>' {pts (the eight points, flat), simple, n (clips)}
  funnel  'fn<s>/<i>' {pts (the four points, flat), op, n}; 'fl<s>/<i>'
          {x, y (the text's anchor on the canvas), op, n} for a label shown
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
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-edges.json');

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
const hx = v => hex(typeof v === 'number' ? v : NaN);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
let warnings = 0;
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => { warnings++; };
  console.error = () => { warnings++; };
  try { return fn(); } finally { console.warn = w; console.error = e; }
};
const arr = a => Array.from(a, x => hx(x));
const FNS = { 'pidx*30': (idx, params) => (params && params.index != null ? params.index * 30 : 0) };
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
const nClip = el => (el && el.animators ? el.animators.filter(a => a.getClip()).length : 0);
// [R2-I8] where an element's origin lands on the canvas
function gpos(el) {
  const m = el.getComputedTransform();
  return m ? [m[4], m[5]] : [0, 0];
}
// [r2v] the path's box on the canvas: its own box through its computed
// transform (for a rect symbol the box of the turned, scaled rect)
function gbox(el) {
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return [r.x, r.y, r.width, r.height];
}
const NULMARK = '\u2400';
const idText = s => String(s).split('\u0000').join(NULMARK);

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
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
const flat = pts => {
  const out = [];
  if (!pts) return out;
  for (let i = 0; i < pts.length; i++) {
    const p = pts[i];
    if (p != null && typeof p === 'object') { out.push(p[0], p[1]); }
    else out.push(p);
  }
  return out;
};
const opOf = el => hx(el.style && el.style.opacity != null ? el.style.opacity : 1);
const rowsOf = (c, data) => {
  if (c.rows) return c.rows.filter(i => i < data.count());
  const r = [];
  data.each(i => r.push(i));
  return r;
};
// where a text's anchor (style.x / style.y) lands on the canvas
function textAt(t) {
  t.updateTransform();
  const m = t.getComputedTransform();
  const x = t.style.x || 0;
  const y = t.style.y || 0;
  if (!m) return [x, y];
  return [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]];
}
const PROBES = {
  // a candlestick's boxes: the eight points and whether it is a simple box
  candle(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'candlestick') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec['cd' + sm.seriesIndex + '/' + i] = { pts: arr(flat(el.shape.points)), simple: !!el.__simpleBox, n: nClip(el) };
      });
    });
  },
  // a bar series' rects (cartesian): the shape, whether ignored
  bar(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'bar') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        const sh = el.shape;
        rec['br' + sm.seriesIndex + '/' + i] = { sh: arr([sh.x, sh.y, sh.width, sh.height]), ig: !!el.ignore, n: nClip(el) };
      });
    });
  },
  // a funnel's pieces and their labels
  funnel(chart, rec, c) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'funnel') return;
      const data = sm.getData();
      rowsOf(c, data).forEach(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec['fn' + sm.seriesIndex + '/' + i] = { pts: arr(flat(el.shape.points)), op: opOf(el), n: nClip(el) };
        const t = el.getTextContent();
        if (t && !t.ignore && !t.invisible && t.style && t.style.text) {
          const g = textAt(t);
          rec['fl' + sm.seriesIndex + '/' + i] = { x: hx(g[0]), y: hx(g[1]), op: opOf(t), n: nClip(t) };
        }
      });
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
const LIN = { animationDuration: 1000, animationEasing: 'linear', animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
const FNS6 = { 'idx*100': idx => idx * 100 };
Object.assign(FNS, FNS6);
const ENTER = [0, 1, 16, 100, 500, 999, 1000, 1001];

// ---- candlestick ----
const KDATA = n => {
  const out = [];
  let v = 50;
  for (let i = 0; i < n; i++) {
    const o = v;
    const c = v + ((i * 37) % 11) - 5;
    out.push([o, c, Math.min(o, c) - 3 - (i % 4), Math.max(o, c) + 2 + (i % 3)]);
    v = c;
  }
  return out;
};
const CD = (n, extra) => Object.assign({ animation: true, xAxis: { type: 'category', data: Array.from({ length: n }, (_, i) => 'c' + i) },
  yAxis: { type: 'value', scale: true }, series: [Object.assign({ type: 'candlestick', data: KDATA(n) }, LIN)] }, extra || {});
add('candle', 'cd-simple-enter', "300 candles on 400 px: candleWidth <= 1.3, every box simple -- each still enters, its points out of the open price's (enter timing, its row)",
  CD(300), ['candle'], after(ENTER, 0), { rows: [0, 1, 150, 299] });
add('candle', 'cd-simple-delay', "the same with animationDelay idx * 100: each simple box waits its turn",
  CD(300, { series: [Object.assign({ type: 'candlestick', data: KDATA(300), animationDelay: { $fn: 'idx*100' } }, LIN)] }), ['candle'],
  after([0, 50, 150, 1099, 1100, 1101, 1200, 1300], 0), { rows: [0, 1, 2] });
add('candle', 'cd-add', "a merge adds two candles: the kept ones updateProps their points (update timing, their row), the new ones enter out of transInit (enter timing, their row)",
  CD(4), ['candle'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { xAxis: { data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5'] }, series: [{ data: KDATA(6) }] } },
    ...after(ENTER, T1)]);
add('candle', 'cd-add-delay', "the same with animationDelay idx * 100 and animationDelayUpdate idx * 100",
  CD(4, { series: [Object.assign({ type: 'candlestick', data: KDATA(4), animationDelay: { $fn: 'idx*100' }, animationDelayUpdate: { $fn: 'idx*100' } }, LIN)] }),
  ['candle'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { xAxis: { data: ['c0', 'c1', 'c2', 'c3', 'c4', 'c5'] }, series: [{ data: KDATA(6) }] } },
    ...after([0, 1, 300, 450, 500, 550, 1300, 1450, 1500, 1501], T1)]);
add('candle', 'cd-simple-update', "simple boxes in a merge that changes the values: each updateProps its points",
  CD(300), ['candle'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: KDATA(300).map(r => [r[0] + 4, r[1] + 4, r[2] + 4, r[3] + 4]) }] } },
    ...after([0, 1, 500, 1001], T1)], { rows: [0, 150, 299] });

// ---- bar: a bar clipped past the plot ----
const BR = (data, extra) => Object.assign({ animation: true, animationDuration: 600, animationEasing: 'linear',
  animationDurationUpdate: 1000, animationEasingUpdate: 'linear',
  xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'value', min: 20, max: 100 },
  series: [{ type: 'bar', data }] }, extra || {});
add('bar', 'br-back', "b (10) lies wholly under min 20: BarView keeps it, ignore, its shape clipped to the plot's bottom edge (height 0); a merge to 60 brings it back from there (updateProps, update timing, its row), not out of an enter",
  BR([50, 10, 70]), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [50, 60, 70] }] } }, ...after([0, 1, 300, 600, 999, 1001], T1)]);
add('bar', 'br-out', "c (70) goes to 5, under min: kept and ignored at once, tweening to the edge; then back to 90",
  BR([50, 30, 70]), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [50, 30, 5] }] } }, ...after([0, 1, 500, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { series: [{ data: [50, 30, 90] }] } }, ...after([0, 1, 500, 1001], T1 + 2000)]);
add('bar', 'br-add', "a merge adds d (5), wholly clipped: created, ignored, kept; a second merge to 80 grows it from the edge at update timing",
  BR([50, 30, 70]), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { xAxis: { data: ['a', 'b', 'c', 'd'] }, series: [{ data: [50, 30, 70, 5] }] } },
    ...after([0, 1, 500, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { series: [{ data: [50, 30, 70, 80] }] } }, ...after([0, 1, 300, 601, 1001], T1 + 2000)]);
add('bar', 'br-cat', "the category axis starts at b (min 1): a lies left of the plot, kept, ignored, clipped to the left edge with no width; a merge to min 0 slides it in from that edge (x and width tween, update timing), not grown in place",
  BR([50, 30, 70], { xAxis: { type: 'category', data: ['a', 'b', 'c'], min: 1 } }), ['bar'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { xAxis: { min: 0 } } }, ...after([0, 1, 300, 600, 999, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { xAxis: { min: 1 } } }, ...after([0, 1, 300, 1001], T1 + 2000)]);

// ---- funnel ----
const FN = (data, extra, s) => Object.assign({ animation: true,
  series: [Object.assign({ type: 'funnel', left: 40, width: 260, data }, LIN, s || {})] }, extra || {});
const FD1 = [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }, { name: 'd', value: 80 }];
const FD2 = [{ name: 'a', value: 30 }, { name: 'b', value: 90 }, { name: 'c', value: 20 }, { name: 'd', value: 50 }];
add('funnel', 'fn-update', "a merge changes the values (the order changes): each piece updateProps its opacity and its four points, its outer label's style x / y (update timing, its row)",
  FN(FD1), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD2 }] } }, ...after(ENTER, T1)]);
add('funnel', 'fn-inside', "the same with the labels inside",
  FN(FD1, null, { label: { position: 'inside' } }), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD2 }] } }, ...after([0, 1, 500, 1001], T1)]);
add('funnel', 'fn-delay', "animationDelayUpdate idx * 100: each piece and its label wait their row's turn",
  FN(FD1, null, { animationDelayUpdate: { $fn: 'idx*100' } }), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD2 }] } }, ...after([0, 150, 250, 350, 1101, 1301, 1350], T1)]);
add('funnel', 'fn-add', "a merge adds a row: the new piece fades in (its points set), the kept ones move to make room",
  FN(FD1), ['funnel'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: FD1.concat([{ name: 'e', value: 10 }]) }] } },
    ...after([0, 1, 500, 1001], T1)]);

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  const rec = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    return smp.rec[key];
  };
  const n = v => num(v);
  guard('cd-simple-enter: the boxes are simple', rec('cd-simple-enter', 0, 'cd0/0').simple);
  guard('cd-simple-enter: a simple box tweens', (() => {
    const a = rec('cd-simple-enter', 100, 'cd0/150'), b = rec('cd-simple-enter', 1001, 'cd0/150');
    return a.n > 0 && a.pts[9] !== b.pts[9];
  })());
  guard('cd-add: a new candle enters', (() => {
    const a = rec('cd-add', T1 + 100, 'cd0/5'), b = rec('cd-add', T1 + 1001, 'cd0/5');
    return a && a.n > 0 && a.pts[1] !== b.pts[1] && !a.simple;
  })());
  guard('br-back: b kept and ignored before', (() => { const a = rec('br-back', T1 - 1, 'br0/1'); return a && a.ig && n(a.sh[3]) === 0; })());
  guard('br-back: b comes back on the update timing', (() => {
    const a = rec('br-back', T1 + 600, 'br0/1'), b = rec('br-back', T1 + 999, 'br0/1');
    return a && !a.ig && a.n > 0 && b.n > 0;
  })());
  guard('fn-update: a piece tweens its points', (() => {
    const a = rec('fn-update', T1 - 1, 'fn0/0'), b = rec('fn-update', T1 + 500, 'fn0/0'), c = rec('fn-update', T1 + 1001, 'fn0/0');
    return b.n > 0 && a.pts[1] !== b.pts[1] && b.pts[1] !== c.pts[1];
  })());
  guard('fn-update: a label moves', (() => {
    const a = rec('fn-update', T1 - 1, 'fl0/1'), b = rec('fn-update', T1 + 500, 'fl0/1'), c = rec('fn-update', T1 + 1001, 'fl0/1');
    return a && b && c && a.y !== b.y && b.y !== c.y;
  })());
  return g;
}

// ---------------------------------------------------------------------------
// running
// ---------------------------------------------------------------------------
function readRec(chart, c) {
  const rec = {};
  c.probes.forEach(p => PROBES[p](chart, rec, c));
  return rec;
}
function runCase(c) {
  const chart = mk(c.W, c.H);
  try {
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: clone(c.option),
      probes: c.probes, events: [] };
    if (c.rows) out.rows = c.rows;
    quiet(() => chart.setOption(materialize(clone(c.option))));
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart, c);
      }
      else if (ev.do === 'frame') zr(chart).animation.update();
      else if (ev.do === 'merge') quiet(() => chart.setOption(materialize(clone(ev.option))));
      else if (ev.do === 'set') quiet(() => chart.setOption(materialize(clone(ev.option)), true));
      else if (ev.do === 'act') quiet(() => chart.dispatchAction(clone(ev.action)));
      else must(false, 'an event it does not know: ' + ev.do);
      out.events.push(o);
    });
    return out;
  } finally {
    chart.dispose();
  }
}

function generate() {
  NOW = T0;
  const out = {
    source: DIST, version: echarts.version, seed: SEED,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    clock: { T0 },
    notes: [
      'every chart: chart._ssr false, env.node off, 400 x 300; the first setOption at T0.',
      'events in order at T0 + t; a sample is zr.animation.update(), a refresh of the display list, and a read of what the case\'s probes name.',
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
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
const deterministic = json1 === json2;
const nul = json1.indexOf('\\u0000') >= 0;
let nSamples = 0;
out1.cases.forEach(q => q.events.forEach(e => { if (e.do === 'sample') nSamples++; }));
console.log(out1.cases.length + ' cases; ' + nSamples + ' samples; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes' + (nul ? '; a \\u0000 in the JSON' : '')
  + '; ' + warnings + ' warnings');
if (bad.length || !deterministic || nul) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
