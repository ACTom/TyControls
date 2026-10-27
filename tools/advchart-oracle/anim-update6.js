/*
Upstream's own answers for spec section 242 (R5-E): the update tweens of the
series the port moved at once.

  par     ParallelView.render's update: each row's polyline updateProps its
          points (the series' update timing, its row); an added row is at
          its place at once, a removed one gone.
  river   ThemeRiverView.render's update: a kept layer's ECPolygon
          updateProps points and stackedOnPoints (no row); a new layer
          enters with its clip, a removed one is gone.
  chord   ChordView: a kept piece and a kept ribbon updateProps its shape
          (its row); a removed one fades out (removeElementWithFadeOut).
  lines   LineDraw's Line.updateData: the line updateProps its shape (its
          row); the end symbols are placed from it every frame.

Runs the real ECharts 6.1 development build (D:/Projects/echarts/dist, or
ECHARTS_DIST) in node's server-side mode (SVG renderer), chart._ssr = false,
echarts.env.node switched off, with the clock of animation.js (the global
Date replaced BEFORE the dist loads; setTimeout a queue that never runs),
Math.random the port's xorshift32.

  node tools/advchart-oracle/anim-update6.js

writes tests/fixtures/advchart-anim-update6.json (ORACLE_OUT overrides).
Ends with process.exit().

Numbers are the 16 lowercase hex digits of the IEEE double (big-endian; NaN
7ff8000000000000). A case: id, group, note, W, H, option, probes[], events[]
(sample / merge at t ms after T0). A sample's rec, by probe:
  par    'par<s>/<i>' {pts (the points, flat), n (clips on the line)}
  river  'rv<s>/<name>' {pts, st (stacked-on points, flat), n}
  chord  'cp<s>/<i>' {sh [cx, cy, r0, r, startAngle, endAngle], n, op};
         'ce<s>/<j>' {sh [s1, s2, sStartAngle, sEndAngle, t1, t2,
         tStartAngle, tEndAngle, cx, cy, r], n, op}; 'ch<s>/gone' [{type,
         n, op}] the elements of the group the data no longer holds
  lines  'ln<s>/<i>' {sh [x1, y1, x2, y2, cpx1, cpy1], pc (percent), n,
         from / to: [x, y] of the end symbols}

An option's function is written {$fn: name}: 'idx*100' idx => idx * 100.
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
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-anim-update6.json');

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
const PROBES = {
  // a parallel series' rows: each polyline's points
  par(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'parallel') return;
      const data = sm.getData();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        rec['par' + sm.seriesIndex + '/' + i] = { pts: arr(flat(el.shape.points)), n: nClip(el) };
      });
    });
  },
  // a themeRiver's layers, by name: the polygon's points and stacked-on
  // points
  river(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'themeRiver') return;
      const view = chart.getViewOfSeriesModel(sm);
      const ls = view._layersSeries || [];
      (view._layers || []).forEach((g, k) => {
        if (!g) return;
        const p = g.childAt(0);
        rec['rv' + sm.seriesIndex + '/' + ls[k].name] = { pts: arr(flat(p.shape.points)), st: arr(flat(p.shape.stackedOnPoints)), n: nClip(p) };
      });
    });
  },
  // a chord's pieces and ribbons, and the ones still in its group that the
  // data no longer holds (fading)
  chord(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'chord') return;
      const s = sm.seriesIndex;
      const data = sm.getData();
      const edges = sm.getEdgeData();
      const live = new Set();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (!el) return;
        live.add(el);
        const sh = el.shape;
        rec['cp' + s + '/' + i] = { sh: arr([sh.cx, sh.cy, sh.r0, sh.r, sh.startAngle, sh.endAngle]), n: nClip(el), op: opOf(el) };
      });
      edges.each(j => {
        const el = edges.getItemGraphicEl(j);
        if (!el) return;
        live.add(el);
        const sh = el.shape;
        rec['ce' + s + '/' + j] = { sh: arr([sh.s1[0], sh.s1[1], sh.s2[0], sh.s2[1], sh.sStartAngle, sh.sEndAngle,
          sh.t1[0], sh.t1[1], sh.t2[0], sh.t2[1], sh.tStartAngle, sh.tEndAngle, sh.cx, sh.cy, sh.r]),
          n: nClip(el), op: opOf(el) };
      });
      const gone = [];
      chart.getViewOfSeriesModel(sm).group.eachChild(el => {
        if (live.has(el)) return;
        gone.push({ type: el.type, n: nClip(el), op: opOf(el) });
      });
      rec['ch' + s + '/gone'] = gone;
    });
  },
  // a lines series' rows: the line's shape and percent, the end symbols'
  // places
  lines(chart, rec) {
    chart.getModel().eachSeries(sm => {
      if (sm.subType !== 'lines') return;
      const data = sm.getData();
      data.each(i => {
        const g = data.getItemGraphicEl(i);
        if (!g) return;
        const line = g.childOfName ? g.childOfName('line') : null;
        if (!line) return;
        const sh = line.shape;
        const from = g.childOfName('fromSymbol');
        const to = g.childOfName('toSymbol');
        rec['ln' + sm.seriesIndex + '/' + i] = { sh: arr([sh.x1, sh.y1, sh.x2, sh.y2, sh.cpx1 == null ? NaN : sh.cpx1, sh.cpy1 == null ? NaN : sh.cpy1]),
          pc: hx(sh.percent == null ? 1 : sh.percent), n: nClip(line),
          from: from ? arr([from.x, from.y]) : null, to: to ? arr([to.x, to.y]) : null };
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
const LIN = { animationDurationUpdate: 1000, animationEasingUpdate: 'linear' };
const FNS6 = { 'idx*100': idx => idx * 100 };
Object.assign(FNS, FNS6);

// ---- parallel ----
const PAR = (data, extra) => Object.assign({ animation: true, parallelAxis: [{ dim: 0, max: 10 }, { dim: 1, max: 10 }, { dim: 2, max: 10 }],
  series: [Object.assign({ type: 'parallel', data }, LIN)] }, extra || {});
add('parallel', 'par-move', "a merge changes every row: each polyline updateProps its points from the old ones (update timing, 1000 ms linear, its row)",
  PAR([[1, 2, 3], [4, 5, 6], [7, 8, 9]]), ['par'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [[3, 2, 1], [6, 5, 4], [9, 8, 7]] }] } },
    ...after([0, 1, 16, 100, 500, 999, 1000, 1001], T1)]);
add('parallel', 'par-delay', "the same with animationDelayUpdate idx * 100: each row waits its turn",
  PAR([[1, 2, 3], [4, 5, 6], [7, 8, 9]], { series: [Object.assign({ type: 'parallel', data: [[1, 2, 3], [4, 5, 6], [7, 8, 9]],
    animationDelayUpdate: { $fn: 'idx*100' } }, LIN)] }), ['par'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [[3, 2, 1], [6, 5, 4], [9, 8, 7]] }] } },
    ...after([0, 100, 150, 250, 999, 1100, 1200, 1201], T1)]);
add('parallel', 'par-count', "a merge drops the last row and adds two: the kept ones move, the new ones are at their place at once, the dropped one is gone",
  PAR([[1, 2, 3], [4, 5, 6], [7, 8, 9]]), ['par'],
  [{ t: T1 - 1, do: 'sample' }, { t: T1, do: 'merge', option: { series: [{ data: [[2, 2, 2], [5, 5, 5]] }] } },
    ...after([0, 1, 500, 1001], T1),
    { t: T1 + 2000, do: 'merge', option: { series: [{ data: [[2, 2, 2], [5, 5, 5], [8, 8, 8], [1, 9, 1]] }] } },
    ...after([0, 1, 500, 1001], T1 + 2000)]);

// ---- themeRiver ----
const RV = (data) => ({ animation: true, singleAxis: { type: 'time', top: 40, bottom: 40 },
  series: [Object.assign({ type: 'themeRiver', data }, LIN)] });
add('river', 'rv-move', "a merge changes the values: each kept layer's polygon updateProps its points and stacked-on points (update timing, no row)",
  RV([['2024-01-01', 10, 'a'], ['2024-01-02', 20, 'a'], ['2024-01-03', 15, 'a'], ['2024-01-01', 5, 'b'], ['2024-01-02', 8, 'b'], ['2024-01-03', 12, 'b']]),
  ['river'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [['2024-01-01', 20, 'a'], ['2024-01-02', 10, 'a'], ['2024-01-03', 25, 'a'],
      ['2024-01-01', 15, 'b'], ['2024-01-02', 3, 'b'], ['2024-01-03', 6, 'b']] }] } },
    ...after([0, 1, 16, 100, 500, 999, 1000, 1001], T1)]);
add('river', 'rv-layers', "a merge drops layer b and adds layer c: a is kept and moves, c enters with its clip, b is gone at once",
  RV([['2024-01-01', 10, 'a'], ['2024-01-02', 20, 'a'], ['2024-01-03', 15, 'a'], ['2024-01-01', 5, 'b'], ['2024-01-02', 8, 'b'], ['2024-01-03', 12, 'b']]),
  ['river'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [['2024-01-01', 12, 'a'], ['2024-01-02', 18, 'a'], ['2024-01-03', 9, 'a'],
      ['2024-01-01', 7, 'c'], ['2024-01-02', 7, 'c'], ['2024-01-03', 7, 'c']] }] } },
    ...after([0, 1, 100, 500, 1001], T1)]);

// ---- chord ----
const CH = (links, extra) => Object.assign({ animation: true,
  series: [Object.assign({ type: 'chord', data: [{ name: 'A' }, { name: 'B' }, { name: 'C' }], links }, LIN)] }, extra || {});
add('chord', 'ch-move', "a merge changes the links' values: every piece and every ribbon updateProps its shape (update timing, its row)",
  CH([{ source: 'A', target: 'B', value: 10 }, { source: 'B', target: 'C', value: 5 }, { source: 'C', target: 'A', value: 8 }]), ['chord'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ links: [{ source: 'A', target: 'B', value: 3 }, { source: 'B', target: 'C', value: 12 },
      { source: 'C', target: 'A', value: 8 }] }] } },
    ...after([0, 1, 16, 100, 500, 999, 1000, 1001], T1)]);
add('chord', 'ch-remove', "a merge drops a link and a node: the dropped ribbon and piece fade out (removeElementWithFadeOut), the rest move",
  CH([{ source: 'A', target: 'B', value: 10 }, { source: 'B', target: 'C', value: 5 }, { source: 'C', target: 'A', value: 8 }]), ['chord'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ name: 'A' }, { name: 'B' }], links: [{ source: 'A', target: 'B', value: 10 }] }] } },
    ...after([0, 1, 100, 200, 300, 500, 1001], T1)]);

// ---- lines ----
const LN = (data, extra) => Object.assign({ animation: true, xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 },
  series: [Object.assign({ type: 'lines', coordinateSystem: 'cartesian2d', symbol: ['circle', 'arrow'], symbolSize: 8, data }, LIN)] }, extra || {});
add('lines', 'ln-move', "a merge moves the lines' ends: each Line updateProps its shape (update timing, its row); the end symbols follow the line every frame",
  LN([{ coords: [[1, 1], [5, 5]] }, { coords: [[2, 8], [8, 2]] }]), ['lines'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ coords: [[3, 1], [9, 6]] }, { coords: [[1, 9], [6, 4]] }] }] } },
    ...after([0, 1, 16, 100, 500, 999, 1000, 1001], T1)]);
add('lines', 'ln-curve', "curved lines (curveness 0.3): the control point tweens with the ends",
  LN([{ coords: [[1, 1], [5, 5]] }, { coords: [[2, 8], [8, 2]] }], { series: [Object.assign({ type: 'lines', coordinateSystem: 'cartesian2d',
    lineStyle: { curveness: 0.3 }, data: [{ coords: [[1, 1], [5, 5]] }, { coords: [[2, 8], [8, 2]] }] }, LIN)] }), ['lines'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ coords: [[3, 1], [9, 6]] }, { coords: [[1, 9], [6, 4]] }] }] } },
    ...after([0, 1, 100, 500, 1001], T1)]);
add('lines', 'ln-bend', "a merge that bends a straight line and straightens a curved one (an item's curveness 0 <-> 0.4): the shape's control point is undefined on the straight side",
  LN([{ coords: [[1, 1], [5, 5]] }, { coords: [[2, 8], [8, 2]], lineStyle: { curveness: 0.4 } }]), ['lines'],
  [{ t: T1 - 1, do: 'sample' },
    { t: T1, do: 'merge', option: { series: [{ data: [{ coords: [[3, 1], [9, 6]], lineStyle: { curveness: 0.4 } }, { coords: [[1, 9], [6, 4]] }] }] } },
    ...after([0, 1, 100, 500, 1001], T1)]);

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
    quiet(() => chart.setOption(materialize(clone(c.option))));
    c.events.forEach(ev => {
      NOW = T0 + ev.t;
      const o = clone(ev);
      if (ev.do === 'sample') {
        zr(chart).animation.update();
        refresh(chart);
        o.rec = readRec(chart, c.probes);
      }
      else if (ev.do === 'frame') zr(chart).animation.update();
      else if (ev.do === 'merge') quiet(() => chart.setOption(materialize(clone(ev.option))));
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
  const rec = (id, t, key) => {
    const smp = cs(id).events.filter(q => q.do === 'sample' && q.t === t).pop();
    must(smp, id + ': no sample at ' + t);
    return smp.rec[key];
  };
  const n = v => num(v);
  const mid = (id, key, f) => {
    const a = rec(id, T1 - 1, key), b = rec(id, T1 + 500, key), c = rec(id, T1 + 1001, key);
    return a && b && c && b.n > 0 && f(a) !== f(b) && f(b) !== f(c);
  };
  guard('par-move: a row tweens', mid('par-move', 'par0/1', r => r.pts[1]));
  guard('par-delay: the last row has not started at +150', rec('par-delay', T1 + 150, 'par0/2').pts[1] === rec('par-delay', T1 - 1, 'par0/2').pts[1]);
  guard('rv-move: a layer tweens', mid('rv-move', 'rv0/a', r => r.pts[1]));
  guard('ch-move: a piece tweens', mid('ch-move', 'cp0/0', r => r.sh[5]));
  guard('ch-move: a ribbon tweens', mid('ch-move', 'ce0/0', r => r.sh[5]));
  guard('ch-remove: something fades', rec('ch-remove', T1 + 100, 'ch0/gone').some(e => e.n > 0 && n(e.op) < 1));
  guard('ln-move: a line tweens', mid('ln-move', 'ln0/0', r => r.sh[0]));
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
