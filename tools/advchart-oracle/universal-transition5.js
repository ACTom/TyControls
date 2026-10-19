// Round 2 R2-D: universalTransition, what was left -- a heatmap on a calendar
// and on a matrix, a lines series drawn as polylines (polyline: true), a
// candlestick's simple boxes (a wick, no body) and dojis, a custom series'
// own enter animation (stopAnimation(newEl) stops it where it is), a lines
// series' arrow while its line is drawing in, a bar's background (showBackground:
// a path no animator runs, faded in), the text of a host while it combines,
// and a graph whose view group tweens (an animated merge of zoom / center)
// when the transition takes nodes off it.
//
// From the real ECharts 6.1 dist, the way universal-transition4.js does it: a
// sequence of setOption calls (the first at T0; each next one after the
// previous has run out -- T + 10000 -- or `after` ms into it; notMerge unless
// the step says merge), recorded at the last one's T + each sample: every
// item path of the new series (getPathList of its item graphic element, in
// order) -- whether it is morphing, the morph path its replaced buildPath
// draws, its style, its transform and shape keys, its text -- and, while it
// combines, every child it draws in its place; and every other path of the
// new series' views (its opacity).
// The clock harness is animation.js' (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames).
// Run: node tools/advchart-oracle/universal-transition5.js
//   -> tests/fixtures/advchart-universal-transition5.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-universal-transition5.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 150, 250, 300, 400, 499, 500, 501, 750, 1000, 1500];
// the gallery cases draw hundreds of paths: fewer samples, digests for the paths
const SAMPLES_BIG = [0, 16, 100, 250, 400, 600, 900, 1500];

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
  if (v === undefined) v = NaN;
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexes = a => Array.from(a, hex);
// FNV-1a (32 bits) over the hexes joined by ','
function fnv(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}
function digest(nums) {
  const hx = hexes(nums);
  return 'fnv' + hx.length + ':' + fnv(hx.join(','));
}

// ---------- the renderItems (each mirrored in tests/test.advchart.universaltransition5.pas) ----------
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const FNS = {
  // a bar's column as a rect, a circle on its top
  pin(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    const b = api.coord([api.value(0), 0]);
    return {
      type: 'group',
      children: [
        { type: 'rect', shape: { x: p[0] - 8, y: p[1], width: 16, height: b[1] - p[1] }, style: { fill: api.visual('color') } },
        { type: 'circle', shape: { cx: p[0], cy: p[1], r: 6 }, style: { fill: '#ffd10a' } },
      ],
    };
  },
  // a column that enters from 30 px to the right of where it rests
  enterRect(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    const b = api.coord([api.value(0), 0]);
    return {
      type: 'rect', shape: { x: p[0] - 8, y: p[1], width: 16, height: b[1] - p[1] },
      style: { fill: api.visual('color') }, enterFrom: { x: 30 }, enterAnimation: { duration: 1000 },
    };
  },
  // a column that enters from opacity 0
  fadeRect(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    const b = api.coord([api.value(0), 0]);
    return {
      type: 'rect', shape: { x: p[0] - 8, y: p[1], width: 16, height: b[1] - p[1] },
      style: { fill: api.visual('color'), enterFrom: { opacity: 0 } }, enterAnimation: { duration: 1000 },
    };
  },
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

// ---------------------------------------------------------------------------
// the charts
// ---------------------------------------------------------------------------
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;
const PathProxy = new echarts.graphic.Rect({ shape: { x: 0, y: 0, width: 1, height: 1 } }).getUpdatedPathProxy().constructor;

function builtData(el) {
  const pp = new PathProxy(false);
  pp.beginPath();
  el.buildPath(pp, el.shape, false);
  return Array.from(pp.data.slice(0, pp.len()));
}
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function clipCount(zr) {
  let n = 0;
  for (let c = zr.animation._head; c; c = c.next) n++;
  return n;
}
function step(zr, t) {
  NOW = t;
  zr.animation.update();
}
function itemPaths(el) {
  const out = [];
  if (!el) return out;
  el.traverse(e => {
    if ((e instanceof Path) && !e.disableMorphing && !e.invisible && !e.ignore) out.push(e);
  });
  return out;
}
function styleOf(el) {
  const s = el.style;
  const col = v => (v == null ? null : String(v));
  return { fill: col(s.fill), stroke: col(s.stroke), lineWidth: s.lineWidth == null ? null : hex(s.lineWidth),
    opacity: s.opacity == null ? null : hex(s.opacity) };
}
const SNAP_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation'];
function snapOf(el) {
  const o = {};
  for (const k of SNAP_KEYS) if (typeof el[k] === 'number') o[k] = hex(el[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (typeof el.shape[k] === 'number') o['shape.' + k] = hex(el.shape[k]);
  return o;
}
// a key whose every sample holds the same value is written once
function compact(arr) {
  const first = JSON.stringify(arr[0]);
  return arr.every(x => JSON.stringify(x) === first) ? arr[0] : arr;
}
// the static path data and the computed transform of a path at rest
function restOf(p) {
  const m = p.getComputedTransform();
  return { d: builtData(p), m: m ? Array.from(m) : null };
}

// one timeline: the new series' item paths, their children while they
// combine, their texts, and the views' other paths
function record(chart, start, samples, useDigest) {
  const zr = chart.getZr();
  const N = samples.length;
  const recs = new Map();
  const order = [];
  const pathOut = d => (useDigest ? digest(d) : hexes(d));
  const rec = (id, base) => {
    let r = recs.get(id);
    if (!r) {
      r = Object.assign({ id, present: new Array(N).fill(false), morph: new Array(N).fill(false),
        comb: new Array(N).fill(false), d: new Array(N).fill(null), style: {}, snap: {}, anim: new Array(N).fill(0),
        pieces: [], text: null }, base);
      recs.set(id, r);
      order.push(r);
    }
    return r;
  };
  const putStyle = (r, p, si) => {
    const st = styleOf(p);
    for (const k2 of Object.keys(st)) {
      (r.style[k2] = r.style[k2] || new Array(N).fill(null))[si] = st[k2];
    }
  };
  const clips = [];
  samples.forEach((t, si) => {
    NOW = start + t;
    if (si > 0) zr.animation.update();
    zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    const model = chart.getModel();
    model.eachSeries(s => {
      const view = chart.getViewOfSeriesModel(s);
      const data = s.getData();
      const seen = new Set();
      const owner = new Map();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (el && el.isGroup) el.traverse(e => { if (e instanceof Path) owner.set(e, i); });
        itemPaths(el).forEach((p, k) => {
          seen.add(p);
          const r = rec('s' + s.seriesIndex + '/' + i + '/' + k, { series: s.seriesIndex, type: p.type,
            seriesType: s.subType, dataIndex: i, path: k, item: true });
          r.present[si] = true;
          const comb = !!p.__isCombineMorphing;
          r.comb[si] = comb;
          const morphing = p.__morphT >= 0 && !comb;
          r.morph[si] = morphing;
          if (morphing) r.d[si] = pathOut(builtData(p));
          putStyle(r, p, si);
          const sn = snapOf(p);
          for (const k2 of Object.keys(sn)) {
            (r.snap[k2] = r.snap[k2] || new Array(N).fill(null))[si] = sn[k2];
          }
          r.anim[si] = p.animators.length;
          // THE TEXT on the path: where it is drawn, its opacity
          const tx = p.getTextContent && p.getTextContent();
          if (tx && !tx.ignore && !tx.invisible) {
            if (!r.text) r.text = { x: new Array(N).fill(null), y: new Array(N).fill(null), opacity: new Array(N).fill(null) };
            const m = tx.getComputedTransform();
            r.text.x[si] = hex((m ? m[4] : 0) + (tx.style.x || 0));
            r.text.y[si] = hex((m ? m[5] : 0) + (tx.style.y || 0));
            r.text.opacity[si] = tx.style.opacity == null ? null : hex(tx.style.opacity);
          }
          if (comb) {
            p.childrenRef().forEach((c, ci) => {
              let pc = r.pieces[ci];
              if (!pc) {
                pc = r.pieces[ci] = { present: new Array(N).fill(false), morph: new Array(N).fill(false),
                  d: new Array(N).fill(null), style: {} };
              }
              pc.present[si] = true;
              pc.morph[si] = c.__morphT >= 0;
              pc.d[si] = pathOut(builtData(c));
              putStyle(pc, c, si);
            });
          }
        });
      });
      let k = 0;
      view.group.traverse(e => {
        if (!(e instanceof Path) || seen.has(e)) return;
        const r = rec('s' + s.seriesIndex + '/x/' + (k++), { series: s.seriesIndex, type: e.type, seriesType: s.subType,
          item: false, owner: owner.has(e) ? owner.get(e) : undefined });
        r.present[si] = true;
        const op = e.style.opacity == null ? null : hex(e.style.opacity);
        (r.style.opacity = r.style.opacity || new Array(N).fill(null))[si] = op;
        r.anim[si] = e.animators.length;
      });
    });
  });
  const out = order.map(r => {
    const o = { id: r.id, series: r.series, type: r.type, seriesType: r.seriesType, item: r.item };
    if (r.item) {
      o.dataIndex = r.dataIndex;
      o.path = r.path;
    }
    else if (r.owner !== undefined) o.owner = r.owner;
    o.present = r.present.every(x => x) ? null : r.present;
    o.morph = r.morph.some(x => x) ? r.morph : null;
    if (o.morph) o.d = r.d;
    o.style = {};
    for (const k of Object.keys(r.style)) o.style[k] = compact(r.style[k]);
    o.snap = {};
    for (const k of Object.keys(r.snap)) o.snap[k] = compact(r.snap[k]);
    o.anim = compact(r.anim);
    if (r.text) o.text = { x: r.text.x, y: r.text.y, opacity: compact(r.text.opacity) };
    if (r.comb.some(x => x)) {
      o.comb = r.comb;
      o.pieces = r.pieces.map(pc => {
        const style = {};
        for (const k of Object.keys(pc.style)) style[k] = compact(pc.style[k]);
        return { present: pc.present, morph: pc.morph, d: pc.d, style };
      });
    }
    return o;
  });
  return { clips, elements: out };
}

// every item path of every series at rest: its PathProxy data and computed
// transform (what a morph reads off it)
function restPaths(chart, useDigest) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const data = s.getData();
    data.each(i => {
      itemPaths(data.getItemGraphicEl(i)).forEach((p, k) => {
        const r = restOf(p);
        out.push({ id: 's' + s.seriesIndex + '/' + i + '/' + k, type: p.type,
          d: useDigest ? digest(r.d) : hexes(r.d), m: r.m ? hexes(r.m) : null });
      });
    });
  });
  return out;
}

const T_GAP = 10000;
function runCase(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    const zr = chart.getZr();
    let t = T_BASE;
    let oldRest = null;
    c.steps.forEach((st, i) => {
      if (i > 0) {
        if (st.after == null) {
          for (let k = 16; k <= 5000; k += 250) step(zr, t + k);
          zr.storage.getDisplayList(true);
          // (an effect scatter's ripples loop for ever)
          must(c.loops || clipCount(zr) === 0, c.id + ': step ' + (i - 1) + ' did not settle');
          t += T_GAP;
        }
        else {
          // (each frame drawn: the display list built, every beforeUpdate run --
          // a Line group places its end symbols there)
          for (const k of [16, st.after / 2, st.after]) {
            step(zr, t + k);
            zr.storage.getDisplayList(true);
          }
          t += st.after;
        }
      }
      if (i === c.steps.length - 1 && i > 0 && st.after == null) oldRest = restPaths(chart, c.digest);
      NOW = t;
      const opts = Object.assign({ notMerge: i > 0 && !st.merge }, st.opts ? materialize(st.opts) : {});
      chart.setOption(materialize(st.option), opts);
    });
    const tl = record(chart, t, c.samples, c.digest);
    const resolved = [];
    chart.getModel().eachSeries(s => resolved.push({ seriesIndex: s.seriesIndex, type: s.subType, id: s.id.replace(/\0/g, '<0>'),
      ut: !!s.isUniversalTransitionEnabled(), animation: !!s.isAnimationEnabled(), count: s.getData().count() }));
    // the new paths at rest, once everything has run out
    for (let k = 16; k <= 5000; k += 250) step(zr, t + 1500 + k);
    zr.storage.getDisplayList(true);
    const newRest = restPaths(chart, c.digest);
    const out = { resolved, clips: tl.clips, elements: tl.elements, newRest };
    if (oldRest) out.oldRest = oldRest;
    return out;
  }
  finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const NAMES = ['A', 'B', 'C', 'D'];
const VALS = [5, 8, 3, 6];
const items = (vals, extra) => NAMES.map((n, i) => Object.assign({ name: n, value: vals[i] }, extra ? extra(i) : {}));
const cart = (series, extra) => Object.assign({ color: PALETTE, xAxis: { type: 'category', data: NAMES },
  yAxis: { type: 'value' }, series }, extra || {});
const solo = (series, extra) => Object.assign({ color: PALETTE, series: Array.isArray(series) ? series : [series] }, extra || {});
const polar = (series, extra) => Object.assign({ color: PALETTE, polar: { radius: [20, '75%'] },
  angleAxis: { type: 'category', data: NAMES }, radiusAxis: {}, series }, extra || {});
const vcart = (series, extra) => Object.assign({ color: PALETTE, xAxis: { type: 'value', min: 0, max: 4 },
  yAxis: { type: 'value', min: 0, max: 10 }, series }, extra || {});
const UT = { universalTransition: true };
const barS = (extra, data) => Object.assign({ type: 'bar', id: 'k', data: data || items(VALS) }, UT, extra || {});
const pieS = (extra, data) => Object.assign({ type: 'pie', id: 'k', radius: '60%', label: { show: false },
  data: data || items(VALS) }, UT, extra || {});
const polarS = (extra, data) => Object.assign({ type: 'bar', id: 'k', coordinateSystem: 'polar', data: data || items(VALS) },
  UT, extra || {});
const pictS = (extra, data) => Object.assign({ type: 'pictorialBar', id: 'k', symbol: 'rect', symbolRepeat: true,
  symbolSize: [20, 10], data: data || items(VALS) }, UT, extra || {});
const customS = (fn, extra) => Object.assign({ type: 'custom', id: 'k', renderItem: { $fn: fn },
  data: NAMES.map((n, i) => ({ name: n, value: [i, VALS[i]] })) }, UT, extra || {});
const VM = { min: 0, max: 10, show: false, inRange: { color: ['#5070dd', '#ff994d'] } };

function chartCases() {
  const list = [];
  const add = (id, note, steps, opts) => list.push(Object.assign({ id, note, steps, samples: SAMPLES, digest: false }, opts || {}));
  const s = (option, after, merge, opts) => {
    const o = { option, after: after == null ? null : after, merge: !!merge };
    if (opts) o.opts = opts;
    return o;
  };
  const pair = (tid, note, other, opts) => {
    add('bar-' + tid, 'bars into ' + note, [s(cart([barS()])), s(other())], opts);
    add(tid + '-bar', note + ' into bars', [s(other()), s(cart([barS()]))], opts);
  };
  // ---- a heatmap on a calendar and on a matrix ----
  const DAYS = ['2017-02-01', '2017-02-04', '2017-02-07', '2017-02-10'];
  pair('heatcal', 'heatmap cells on a calendar (the day\'s content rect)', () => ({ color: PALETTE,
    calendar: { range: '2017-02', cellSize: 30, top: 60, left: 40 }, visualMap: VM,
    series: [{ type: 'heatmap', id: 'k', coordinateSystem: 'calendar', universalTransition: true,
      data: NAMES.map((n, i) => ({ name: n, value: [DAYS[i], VALS[i]] })) }] }));
  pair('heatmatrix', 'heatmap cells on a matrix (the cell\'s rect)', () => ({ color: PALETTE,
    matrix: { x: { data: NAMES }, y: { data: ['u', 'v'] } }, visualMap: VM,
    series: [{ type: 'heatmap', id: 'k', coordinateSystem: 'matrix', universalTransition: true,
      data: NAMES.map((n, i) => ({ name: n, value: [n, i % 2 ? 'v' : 'u', VALS[i]] })) }] }));
  // ---- lines drawn as polylines ----
  const polyS = () => ({ type: 'lines', id: 'k', coordinateSystem: 'cartesian2d', polyline: true, universalTransition: true,
    lineStyle: { width: 2 },
    data: NAMES.map((n, i) => ({ name: n, coords: [[i, 0], [i + 0.3, VALS[i] / 2], [i + 0.1, VALS[i] * 0.8], [i + 0.6, VALS[i]]] })) });
  pair('polylines', 'polylines (one Polyline path an item, no enter animation)', () => vcart([polyS()]));
  // ---- a candlestick's simple boxes and dojis ----
  const CANDLE_STYLE = { color: '#eb5454', color0: '#47b262', borderColor: '#eb5454', borderColor0: '#47b262' };
  pair('candle.simple', 'simple boxes (a candle of 1 px: the wick alone, moveTo / lineTo)', () => cart([{ type: 'candlestick',
    id: 'k', universalTransition: true, barWidth: 1, itemStyle: CANDLE_STYLE,
    data: VALS.map((v, i) => (i % 2 ? [v, v - 2, v - 3, v + 1] : [v - 2, v, v - 3, v + 1])) }]));
  pair('candle.doji', 'dojis (open equals close: a body of no height and its wicks)', () => cart([{ type: 'candlestick',
    id: 'k', universalTransition: true, itemStyle: CANDLE_STYLE,
    data: VALS.map((v, i) => (i % 2 ? [v, v, v - 3, v + 1] : [v - 2, v, v - 3, v + 1])) }]));
  // ---- a custom series' own enter animation ----
  add('bar-custom.enter', 'bars into a custom series whose rects enter from x 30 (enterFrom): the transition stops that '
    + 'animation where it is -- at its start', [s(cart([barS()])), s(cart([customS('enterRect')]))]);
  add('bar-custom.fade', 'bars into a custom series whose rects enter from opacity 0 (style.enterFrom): stopped at '
    + 'its start too', [s(cart([barS()])), s(cart([customS('fadeRect')]))]);
  add('pie-custom.pin.enter', 'slices into a custom group of two (no enter animation of its own): the control case',
    [s(solo(pieS())), s(cart([customS('pin')]))]);
  // ---- a lines series' end symbols ----
  const arrowS = (extra) => Object.assign({ type: 'lines', id: 'k', coordinateSystem: 'cartesian2d', universalTransition: true,
    symbol: ['none', 'arrow'], symbolSize: 10, lineStyle: { curveness: 0.4 },
    data: NAMES.map((n, i) => ({ name: n, coords: [[i, 0], [i + 0.8, VALS[i]]] })) }, extra || {});
  add('bar-lines.arrow', 'bars into curved lines with an arrow at the end', [s(cart([barS()])), s(vcart([arrowS()]))]);
  add('lines.arrow-bar', 'curved lines with arrows into bars', [s(vcart([arrowS()])), s(cart([barS()]))]);
  add('lines.arrow-bar.inflight', '200 ms into curved lines drawing in (their percent and the arrows\' scale going up), bars: '
    + 'the lines morph from where they are', [s(vcart([])), s(vcart([arrowS()])), s(cart([barS()]), 200)]);
  add('lines.arrow-pie.inflight', 'the same into pie slices (the line and the arrow combine)',
    [s(vcart([])), s(vcart([arrowS()])), s(solo(pieS()), 200)]);
  // ---- a bar's background ----
  add('pie-bar.bg', 'slices into bars with showBackground: the backgrounds (no animator) fade in',
    [s(solo(pieS())), s(cart([barS({ showBackground: true })]))]);
  add('pie-polar.bg', 'slices into polar bars with showBackground', [s(solo(pieS())), s(polar([polarS({ showBackground: true })]))]);
  // ---- the text of a host while it combines ----
  add('label.pict-bar', 'glyphs combining into bars whose labels show on top: a combining host\'s text is laid out on '
    + 'its own shape (the children are drawn in its place)', [s(cart([pictS()])), s(cart([barS({ label: { show: true, position: 'top' } })]))]);
  add('label.pin-bar', 'a custom rect and circle combining into bars with labels inside',
    [s(cart([customS('pin')])), s(cart([barS({ label: { show: true } })]))]);
  // ---- a graph whose view group tweens ----
  const GY1 = [0, 7, 2, 10];
  const grS = (names, extra) => Object.assign({ type: 'graph', id: 'g', layout: 'none', roam: true,
    universalTransition: { enabled: true, seriesKey: 'kk' },
    data: names.map(n => {
      const i = NAMES.indexOf(n);
      return { name: n, x: i * 10, y: GY1[i], value: GY1[i] };
    }),
    links: [] }, extra || {});
  const ZOOM = { zoom: 1.6, center: [12, 4] };
  const ZOOM2 = { zoom: 1.2, center: [12, 4] };
  const kept = zoom => s(cart([grS(['A', 'D'], zoom), barS({ id: 'b', universalTransition: { enabled: true, seriesKey: 'kk' } },
    [{ name: 'B', value: 8 }, { name: 'C', value: 3 }])]));
  const keptAt = (zoom, after) => Object.assign(kept(zoom), { after });
  // (GraphView's render runs before the transition: updateProps of the main
  // group sets it to its new transform at once -- setToFinal -- and the old
  // nodes, still in the group fading out, are baked under it by removeEl)
  add('graph-roam-bar.kept.inflight', '200 ms into a merge that zooms the graph\'s view (its group tweening), the graph keeps '
    + 'A and D at another zoom and B and C go to bars of its seriesKey: the old nodes leave the view under the group\'s '
    + 'NEW transform (set at once by the render before the transition)',
    [s(solo(grS(NAMES))), s({ series: [Object.assign({ id: 'g' }, ZOOM)] }, null, true), keptAt(ZOOM2, 200)]);
  add('graph-roam-bar.kept', 'the same once the zoom has run out',
    [s(solo(grS(NAMES))), s({ series: [Object.assign({ id: 'g' }, ZOOM)] }, null, true), kept(ZOOM2)]);
  add('graph-roam-bar.kept.same', 'the same keeping the zoom (the group\'s transform does not change)',
    [s(solo(grS(NAMES))), s({ series: [Object.assign({ id: 'g' }, ZOOM)] }, null, true), kept(ZOOM)]);
  add('graph-roam-bar.inflight', '200 ms into the zoom, every node to bars (the graph\'s view disposed: its nodes are off '
    + 'their groups)', [s(solo(grS(NAMES))), s({ series: [Object.assign({ id: 'g' }, ZOOM)] }, null, true),
      s(cart([barS({ id: 'b', universalTransition: { enabled: true, seriesKey: 'kk' } })]), 200)]);
  return list;
}

// ---------------------------------------------------------------------------
// guards
// ---------------------------------------------------------------------------
function guards(charts) {
  const byId = id => {
    const c = charts.find(x => x.id === id);
    must(c, 'no case ' + id);
    return c;
  };
  const itemsOf = c => c.elements.filter(e => e.item);
  const morphs = c => itemsOf(c).filter(e => e.morph);
  const combs = c => itemsOf(c).filter(e => e.comb);
  const atLeast = (id, n, what) => must(what(byId(id)).length >= n, id + ': ' + what(byId(id)).length + ' < ' + n);
  for (const tid of ['heatcal', 'heatmatrix', 'polylines', 'candle.simple', 'candle.doji']) {
    atLeast('bar-' + tid, 4, morphs);
    atLeast(tid + '-bar', 4, morphs);
  }
  // the simple boxes are a wick alone: two numbers a point, M and L
  must(byId('bar-candle.simple').newRest.every(r => r.d.length === 6 && r.d[0] === hex(1) && r.d[3] === hex(2)),
    'bar-candle.simple: not a wick alone');
  must(byId('bar-candle.doji').newRest.filter(r => r.d[2] === r.d[8]).length === 2, 'bar-candle.doji: not two bodies of no height');
  // the polylines: a Polyline of four points, no fill
  must(byId('bar-polylines').newRest.every(r => r.type === 'polyline' && r.d.length === 12), 'bar-polylines: not polylines');
  must(byId('bar-polylines').elements.filter(e => e.item).every(e => e.style.fill === null), 'bar-polylines: a fill');
  // the custom enter animations, stopped before their first step: the
  // paths rest where renderItem put them, at full opacity, from the start
  atLeast('bar-custom.enter', 4, morphs);
  atLeast('bar-custom.fade', 4, morphs);
  must(byId('bar-custom.enter').elements.filter(e => e.item).every(e => e.snap.x === hex(0)),
    'bar-custom.enter: the rects move');
  must(byId('bar-custom.enter').newRest.every(r => r.m === null), 'bar-custom.enter: not at rest where renderItem put them');
  must(byId('bar-custom.fade').elements.filter(e => e.item).every(e => e.style.opacity === hex(1)),
    'bar-custom.fade: the rects fade');
  must(byId('bar-custom.enter').elements.filter(e => e.item).every(e => Array.isArray(e.anim) && Math.max(...e.anim) === 1),
    'bar-custom.enter: an animator besides the morph');
  must(morphs(byId('pie-custom.pin.enter')).length === 8, 'pie-custom.pin.enter: not eight morphs');
  // the arrows
  must(morphs(byId('bar-lines.arrow')).length === 8, 'bar-lines.arrow: not eight morphs (a line and an arrow each)');
  must(combs(byId('lines.arrow-bar')).length === 4, 'lines.arrow-bar: not four combining');
  must(combs(byId('lines.arrow-bar.inflight')).length === 4, 'lines.arrow-bar.inflight: not four combining');
  must(combs(byId('lines.arrow-pie.inflight')).length === 4, 'lines.arrow-pie.inflight: not four combining');
  // the backgrounds fade in
  const fades = c => c.elements.filter(e => !e.item && Array.isArray(e.style.opacity)).length;
  must(fades(byId('pie-bar.bg')) === 4, 'pie-bar.bg: the backgrounds do not fade in');
  must(fades(byId('pie-polar.bg')) === 4, 'pie-polar.bg: the backgrounds do not fade in');
  // the combining hosts' texts
  must(combs(byId('label.pict-bar')).length === 4 && byId('label.pict-bar').elements.filter(e => e.text).length === 4,
    'label.pict-bar: not four combining with texts');
  must(combs(byId('label.pin-bar')).length === 4 && byId('label.pin-bar').elements.filter(e => e.text).length === 4,
    'label.pin-bar: not four combining with texts');
  // the graph's nodes
  atLeast('graph-roam-bar.kept.inflight', 2, morphs);
  atLeast('graph-roam-bar.kept', 2, morphs);
  atLeast('graph-roam-bar.inflight', 4, morphs);
  atLeast('graph-roam-bar.kept.same', 2, morphs);
  {
    // the nodes off the kept view start under its new transform: the same
    // in flight as at rest, not the same as where the zoom is kept
    const fr = c => itemsOf(byId(c)).filter(e => e.morph && e.seriesType === 'bar').map(e => e.d[0][1]);
    const a = fr('graph-roam-bar.kept.inflight');
    const b = fr('graph-roam-bar.kept');
    const c = fr('graph-roam-bar.kept.same');
    must(a.length === 2 && b.length === 2 && c.length === 2 && a.every((x, i) => x === b[i]) && b.every((x, i) => x !== c[i]),
      'graph-roam-bar: the old nodes do not start under the new transform');
  }
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const charts = chartCases().map(c => Object.assign(c, runCase(c)));
  guards(charts);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'R2-D: steps of setOption (the first at T0; a next one after the previous ran out, T + 10000, or `after` ms into '
      + 'it; notMerge unless `merge`), recorded at the last T + samples. Each element: '
      + 'an item path of a new series (id s<series>/<dataIndex>/<path>, the path its place in getPathList) or another path '
      + 'of its view (s<series>/x/<k>, owner the item whose group holds it); morph[i] = __morphT >= 0 and not combining, '
      + 'd[i] the replaced buildPath\'s PathProxy data (codes M1 L2 C3 Q4 A5 Z6 R7); comb[i] = __isCombineMorphing, pieces = '
      + 'its childrenRef() in order; style = the effective fill / stroke / lineWidth / opacity, snap = the path\'s transform '
      + 'and shape keys -- a key the same at every sample written once; text = the textContent\'s computed translation plus '
      + 'its style x / y, and its opacity. oldRest / newRest: every item path at rest before the last step and after it has '
      + 'run out (PathProxy data, computed transform). Every number is the hex of its double.',
    W, H, seed: SEED, clock: { T0: T_BASE, gap: T_GAP },
    charts,
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
