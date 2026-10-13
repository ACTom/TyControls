// D5 UT2 (batch 137): universalTransition, combine and separate -- many old
// elements morphing into one new one (combineMorph) and one old element into
// many new ones (separateMorph), paired by groupId / dataGroupId and by a list
// seriesKey against single keys.
//
// Two parts, both from the real ECharts 6.1 dist:
//   engine  the pieces UT2 adds to the port's engine, on what real zrender
//           elements answer: PathProxy.getBoundingRect on path data,
//           Path.getBoundingRect with a stroke (the hover threshold,
//           strokeNoScale under a scale), setLocalTransform followed by
//           updateTransform (a separated piece's transform), sortPaths.
//   charts  a sequence of setOption calls (the first at T0; each next one
//           after the previous has run out -- T + 10000 -- or `after` ms into
//           it; notMerge unless the step says merge), recorded at the last
//           one's T + each sample: every item element of the new series --
//           whether it is morphing, the morph path its replaced buildPath
//           draws, its style, its transform and shape keys -- and, while it is
//           combining (__isCombineMorphing), every child it draws in its place
//           (childrenRef): morphing or not, its path, its style; and every
//           other path of the new series' views.
// The clock harness is animation.js' (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames).
// Run: node tools/advchart-oracle/universal-transition2.js
//   -> tests/fixtures/advchart-universal-transition2.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-universal-transition2.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 150, 250, 300, 400, 499, 500, 501, 750, 1000, 1500];
// the gallery cases draw 507 symbols: fewer samples, digests for the paths
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

// ---------- functions in options ----------
const FNS = {
  // universalTransition.delay(index, count)
  'ut2': (idx, count) => 30 + idx * 40 + count * 10,
  // the gallery's Math.random() * 400, made deterministic
  'gal': (idx, count) => idx * 7919 % count / count * 400,
  'idx*50': idx => idx * 50,
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
// the dist's own code
// ---------------------------------------------------------------------------
const SRC = fs.readFileSync(DIST, 'utf8');
function slice(from, to) {
  const a = SRC.indexOf(from);
  must(a >= 0, 'the dist has no ' + JSON.stringify(from));
  const b = SRC.indexOf(to, a + from.length);
  must(b > a, 'the dist has no ' + JSON.stringify(to) + ' after ' + JSON.stringify(from));
  must(SRC.indexOf(from, a + 1) < 0, 'the dist has two ' + JSON.stringify(from));
  return SRC.slice(a, b);
}
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;
const PathProxy = new echarts.graphic.Rect({ shape: { x: 0, y: 0, width: 1, height: 1 } }).getUpdatedPathProxy().constructor;
const G = echarts.graphic;
// hilbert and sortPaths, cut out of the bundle
const SORT = new Function('map', slice('function hilbert(x, y, minX, minY, maxX, maxY) {', '    function defaultDividePath(param) {')
  + '\nreturn { sortPaths: sortPaths, hilbert: hilbert };')(echarts.util.map);

function builtData(el) {
  const pp = new PathProxy(false);
  pp.beginPath();
  el.buildPath(pp, el.shape, false);
  return Array.from(pp.data.slice(0, pp.len()));
}
function proxyData(el) {
  const pp = el.getUpdatedPathProxy();
  return Array.from(pp.data.slice(0, pp.len()));
}
function bboxOf(data) {
  const r = PathProxy.prototype.getBoundingRect.call({ data, _len: data.length });
  return [r.x, r.y, r.width, r.height];
}

// ---------------------------------------------------------------------------
// the engine cases
// ---------------------------------------------------------------------------
function engineCases() {
  const cases = [];
  const mk = (type, shape, attrs, style) => {
    const el = new G[type]({ shape });
    if (attrs) el.attr(attrs);
    if (style) el.setStyle(style);
    return el;
  };
  // PathProxy.getBoundingRect
  const S = {
    'rect': mk('Rect', { x: 10, y: 20, width: 60, height: 40 }),
    'rect.neg': mk('Rect', { x: 75.5, y: 220, width: 69, height: -19.375 }),
    'rect.r': mk('Rect', { x: 10, y: 20, width: 60, height: 40, r: 6 }),
    'sector': mk('Sector', { cx: 200, cy: 150, r0: 0, r: 75, startAngle: -Math.PI / 2, endAngle: 0.4, clockwise: true }),
    'sector.ring': mk('Sector', { cx: 200, cy: 150, r0: 40, r: 90, startAngle: 1, endAngle: 3.5, clockwise: true }),
    'sector.anti': mk('Sector', { cx: 100, cy: 100, r0: 0, r: 50, startAngle: 2, endAngle: 0.3, clockwise: false }),
    'sector.full': mk('Sector', { cx: 0, cy: 0, r0: 0, r: 30, startAngle: 0, endAngle: Math.PI * 2, clockwise: true }),
    'sector.corner': mk('Sector', { cx: 150, cy: 150, r0: 20, r: 80, startAngle: 0.2, endAngle: 1.9, clockwise: true, cornerRadius: 6 }),
    'circle': mk('Circle', { cx: 5, cy: 7, r: 3 }),
    'polygon': mk('Polygon', { points: [[0, 0], [40, 5], [55, 40], [20, 60], [-10, 30]] }),
    'quad': echarts.graphic.makePath('M0,0Q20,40,40,0L40,20Z', {}, null, 'center'),
    'arcfirst': mk('Arc', { cx: 30, cy: 30, r: 20, startAngle: 0.3, endAngle: 2.2, clockwise: true }),
    'symbol.circle': echarts.helper.createSymbol('circle', -1, -1, 2, 2),
    'symbol.triangle': echarts.helper.createSymbol('triangle', -1, -1, 2, 2),
    'symbol.diamond': echarts.helper.createSymbol('diamond', -1, -1, 2, 2),
    'cubic': echarts.graphic.makePath('M0,0C10,-20,30,40,50,0C60,-10,70,30,40,40Z', {}, null, 'center'),
  };
  for (const id of Object.keys(S)) {
    const d = proxyData(S[id]);
    cases.push({ id: 'bbox.' + id, kind: 'bbox', data: hexes(d), out: hexes(bboxOf(d)) });
  }
  // Path.getBoundingRect: the stroke grows it (the hover threshold without a fill,
  // the line scale under strokeNoScale)
  const PR = [
    ['circle.strokeonly', () => mk('Circle', { cx: 5, cy: 7, r: 3 }, null, { fill: null, stroke: '#000', lineWidth: 2 })],
    ['rect.stroke', () => mk('Rect', { x: 10.25, y: 20, width: 61, height: 40.5 }, null, { fill: '#f00', stroke: '#000', lineWidth: 3 })],
    ['circle.noscale', () => mk('Circle', { cx: 0, cy: 0, r: 1 }, { x: 40, y: 30, scaleX: 5, scaleY: 5 },
      { fill: '#fff', stroke: '#000', lineWidth: 2, strokeNoScale: true })],
    ['circle.noscale.flat', () => mk('Circle', { cx: 0, cy: 0, r: 1 }, { x: 40, y: 30, scaleX: 1, scaleY: 7 },
      { fill: '#fff', stroke: '#000', lineWidth: 2, strokeNoScale: true })],
    ['sector.thin', () => mk('Sector', { cx: 200, cy: 150, r0: 0, r: 75, startAngle: 0.1, endAngle: 0.4, clockwise: true }),
      null],
    ['sector.stroke', () => mk('Sector', { cx: 200, cy: 150, r0: 0, r: 75, startAngle: 0.1, endAngle: 0.4, clockwise: true }, null,
      { fill: '#0f0', stroke: '#fff', lineWidth: 0.5 })],
    ['rect.zerowidth', () => mk('Rect', { x: 10, y: 20, width: 60, height: 40 }, null, { fill: '#f00', stroke: '#000', lineWidth: 0 })],
  ];
  for (const [id, f] of PR) {
    const el = f();
    el.updateTransform();
    const m = el.transform;
    const r = el.getBoundingRect();
    cases.push({ id: 'pathrect.' + id, kind: 'pathrect', data: hexes(proxyData(el)),
      style: { fill: el.style.fill == null ? null : String(el.style.fill), stroke: el.style.stroke == null ? null : String(el.style.stroke),
        lineWidth: hex(el.style.lineWidth), strokeNoScale: !!el.style.strokeNoScale },
      m: m ? hexes(m) : null, out: hexes([r.x, r.y, r.width, r.height]) });
  }
  // setLocalTransform, then the transform an element with no parent computes
  const MS = [
    [1, 0, 0, 1, 30.5, 40.25], [10, 0, 0, 10, 100, 80], [2, 0, 0, 3, 0, 0], [1, 0, 0, 1, 0, 0],
    [8.660254037844387, 5, -2.5, 4.330127018922194, 120.5, 60.75], [-3, 0, 0, 2, 7, 9], [0.5, 0.25, -0.125, 2, -11, 3.5],
    [1, 0, 0, 1, 1e-5, 0],
  ];
  for (const m of MS) {
    const el = new G.Rect({ shape: { x: 0, y: 0, width: 1, height: 1 } });
    el.setLocalTransform(m.slice());
    el.updateTransform();
    cases.push({ id: 'recompose', kind: 'recompose', m: hexes(m), out: el.transform ? hexes(el.transform) : null });
  }
  // sortPaths: the centres (with the translation) on the hilbert curve
  const SORTS = [
    ['rects', () => [[0, 0, 10, 10], [50, 0, 10, 10], [0, 50, 10, 10], [50, 50, 10, 10], [25, 25, 10, 10]]
      .map(([x, y, w, h]) => mk('Rect', { x, y, width: w, height: h }))],
    ['moved', () => [[0, 0], [10, 3], [3, 10], [7, 7], [-5, 2]].map(([x, y]) => mk('Circle', { cx: 0, cy: 0, r: 2 }, { x, y, scaleX: 3 }))],
    ['same', () => [0, 1, 2, 3].map(() => mk('Rect', { x: 5, y: 5, width: 1, height: 1 }))],
    ['line', () => [9, 1, 5, 3, 7].map(x => mk('Rect', { x, y: 0, width: 1, height: 1 }))],
    ['stroked', () => [[0, 0, 2], [20, 0, 6], [10, 10, 1]].map(([x, y, lw]) =>
      mk('Circle', { cx: x, cy: y, r: 3 }, null, { fill: null, stroke: '#000', lineWidth: lw }))],
  ];
  for (const [id, f] of SORTS) {
    const list = f();
    list.forEach((p, i) => { p.__sortIdx = i; });
    const sorted = SORT.sortPaths(list);
    cases.push({ id: 'sort.' + id, kind: 'sort',
      paths: list.map(p => {
        p.updateTransform();
        return { data: hexes(proxyData(p)), m: p.transform ? hexes(p.transform) : null,
          stroke: p.style.stroke == null ? null : String(p.style.stroke), fill: p.style.fill == null ? null : String(p.style.fill),
          lineWidth: hex(p.style.lineWidth) };
      }),
      out: sorted.map(p => p.__sortIdx) });
  }
  return cases;
}

// ---------------------------------------------------------------------------
// the charts
// ---------------------------------------------------------------------------
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
function snapOf(el, groupOf) {
  const o = {};
  for (const k of SNAP_KEYS) if (typeof el[k] === 'number') o[k] = hex(el[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (typeof el.shape[k] === 'number') o['shape.' + k] = hex(el.shape[k]);
  if (groupOf) for (const k of SNAP_KEYS) if (typeof groupOf[k] === 'number') o['g.' + k] = hex(groupOf[k]);
  return o;
}
// a key whose every sample holds the same value is written once
function compact(arr) {
  const first = JSON.stringify(arr[0]);
  return arr.every(x => JSON.stringify(x) === first) ? arr[0] : arr;
}

// one timeline: the new series' item elements, their children while they
// combine, and the views' other paths
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
        pieces: [] }, base);
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
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        itemPaths(el).forEach((p, k) => {
          seen.add(p);
          const r = rec('s' + s.seriesIndex + '/' + i + '/' + k, { series: s.seriesIndex, type: p.type,
            seriesType: s.subType, dataIndex: i, item: true });
          r.present[si] = true;
          const comb = !!p.__isCombineMorphing;
          r.comb[si] = comb;
          const morphing = p.__morphT >= 0 && !comb;
          r.morph[si] = morphing;
          if (morphing) r.d[si] = pathOut(builtData(p));
          putStyle(r, p, si);
          const parent = p.parent && p.parent !== view.group && p.parent.parent ? p.parent : null;
          const sn = snapOf(p, parent);
          for (const k2 of Object.keys(sn)) {
            (r.snap[k2] = r.snap[k2] || new Array(N).fill(null))[si] = sn[k2];
          }
          r.anim[si] = p.animators.length + (parent ? parent.animators.length : 0);
          if (comb) {
            // THE CHILDREN it draws in its place
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
          item: false });
        r.present[si] = true;
        const op = e.style.opacity == null ? null : hex(e.style.opacity);
        (r.style.opacity = r.style.opacity || new Array(N).fill(null))[si] = op;
        r.anim[si] = e.animators.length;
      });
    });
  });
  const out = order.map(r => {
    const o = { id: r.id, series: r.series, type: r.type, seriesType: r.seriesType, item: r.item };
    if (r.item) o.dataIndex = r.dataIndex;
    o.present = r.present.every(x => x) ? null : r.present;
    o.morph = r.morph.some(x => x) ? r.morph : null;
    if (o.morph) o.d = r.d;
    o.style = {};
    for (const k of Object.keys(r.style)) o.style[k] = compact(r.style[k]);
    o.snap = {};
    for (const k of Object.keys(r.snap)) o.snap[k] = compact(r.snap[k]);
    o.anim = compact(r.anim);
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

const T_GAP = 10000;
function runCase(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    const zr = chart.getZr();
    let t = T_BASE;
    c.steps.forEach((st, i) => {
      if (i > 0) {
        if (st.after == null) {
          for (let k = 16; k <= 5000; k += 250) step(zr, t + k);
          zr.storage.getDisplayList(true);
          must(clipCount(zr) === 0, c.id + ': step ' + (i - 1) + ' did not settle');
          t += T_GAP;
        }
        else {
          for (const k of [16, st.after / 2, st.after]) step(zr, t + k);
          t += st.after;
        }
      }
      NOW = t;
      chart.setOption(materialize(st.option), i > 0 && !st.merge);
    });
    const tl = record(chart, t, c.samples, c.digest);
    const resolved = [];
    chart.getModel().eachSeries(s => resolved.push({ seriesIndex: s.seriesIndex, type: s.subType, id: s.id.replace(/\0/g, '<0>'),
      ut: !!s.isUniversalTransitionEnabled(), animation: !!s.isAnimationEnabled(), count: s.getData().count() }));
    return { resolved, clips: tl.clips, elements: tl.elements };
  }
  finally {
    chart.dispose();
  }
}

// the default palette, written out so the port (whose palette is its skin's)
// paints the same colours
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const CATS = ['A', 'B', 'C', 'D'];
const VALS = [5, 20, 36, 10];
const VALS2 = [12, 8, 15, 30];
const named = (names, vals) => names.map((n, i) => ({ name: n, value: vals[i] }));
const cartN = (series, cats, extra) => Object.assign({ color: PALETTE, xAxis: { type: 'category', data: cats || CATS },
  yAxis: { type: 'value' }, series }, extra || {});
const valueN = (series, extra) => Object.assign({ color: PALETTE, xAxis: { type: 'value', scale: true },
  yAxis: { type: 'value', scale: true }, series }, extra || {});
const solo = (series, extra) => Object.assign({ color: PALETTE, series: [series] }, extra || {});
const barS = (extra, vals) => Object.assign({ type: 'bar', universalTransition: true, data: vals || VALS }, extra || {});
const pieS = (extra, data) => Object.assign({ type: 'pie', universalTransition: true, radius: '60%', label: { show: false },
  data: data || named(CATS, VALS) }, extra || {});
const ut = extra => Object.assign({ enabled: true }, extra);
const LIST = ['a', 'b'];
// two bar series (ids a and b) and a pie whose seriesKey lists both
const bars2 = (uta, utb) => cartN([barS({ id: 'a', universalTransition: ut(uta || {}) }),
  barS({ id: 'b', universalTransition: ut(utb || {}) }, VALS2)]);
const pieAB = (u, extra) => solo(pieS(Object.assign({ id: 'p', universalTransition: ut(Object.assign({ seriesKey: LIST.slice() }, u || {})) },
  extra || {})));

// ---------- the gallery's scatter-aggregate-bar, its own data ----------
function gallery() {
  const g = JSON.parse(fs.readFileSync(path.join(GALLERY, 'scatter-aggregate-bar.json'), 'utf8'));
  const female = g.series[0].data;
  const male = g.series[1].data;
  const avg = (data, dim) => {
    let total = 0;
    for (let i = 0; i < data.length; i++) total += data[i][dim];
    return (total /= data.length);
  };
  const scatterOption = { color: PALETTE, xAxis: { scale: true }, yAxis: { scale: true }, series: [
    { type: 'scatter', id: 'female', dataGroupId: 'female', universalTransition: { enabled: true, delay: { $fn: 'gal' } }, data: female },
    { type: 'scatter', id: 'male', dataGroupId: 'male', universalTransition: { enabled: true, delay: { $fn: 'gal' } }, data: male },
  ] };
  const barOption = { color: PALETTE, xAxis: { type: 'category', data: ['Female', 'Male'] }, yAxis: {}, series: [
    { type: 'bar', id: 'total', data: [{ value: avg(male, 0), groupId: 'male' }, { value: avg(female, 0), groupId: 'female' }],
      universalTransition: { enabled: true, seriesKey: ['female', 'male'], delay: { $fn: 'gal' } } },
  ] };
  return { scatterOption, barOption };
}
// ---------- the gallery's bar-drilldown, its first level ----------
const DRILL = {
  color: PALETTE, xAxis: { data: ['Animals', 'Fruits', 'Cars'] }, yAxis: {}, dataGroupId: '', animationDurationUpdate: 500,
  series: { type: 'bar', id: 'sales', data: [{ value: 5, groupId: 'animals' }, { value: 2, groupId: 'fruits' },
    { value: 4, groupId: 'cars' }], universalTransition: { enabled: true, divideShape: 'clone' } },
};
const DRILL_ANIMALS = {
  xAxis: { data: ['Cats', 'Dogs', 'Cows', 'Sheep', 'Pigs'] },
  series: { type: 'bar', id: 'sales', dataGroupId: 'animals', data: [4, 2, 1, 2, 1],
    universalTransition: { enabled: true, divideShape: 'clone' } },
};

function chartCases() {
  const list = [];
  const add = (id, note, steps, opts) => list.push(Object.assign({ id, note, steps, samples: SAMPLES, digest: false }, opts || {}));
  const s = (option, after, merge) => ({ option, after: after == null ? null : after, merge: !!merge });
  // ---- combine and separate on a list seriesKey ----
  add('bars2-pie', 'bar series a and b become a pie whose seriesKey is [a, b]: each slice combines the two bars of its name '
    + '(split into 2 sectors, one __morphT shared through `during`)', [s(bars2()), s(pieAB())]);
  add('pie-bars2', 'the pie (seriesKey [a, b]) becomes series a and b: each slice separates into the two bars of its name '
    + '(the sector split in 2)', [s(pieAB()), s(bars2())]);
  add('bars2-pie.delay', 'as bars2-pie, universalTransition.delay (idx, count) => 30 + idx * 40 + count * 10 on the pie: '
    + 'each child morphs on its own, the style on (k, count)', [s(bars2()), s(pieAB({ delay: { $fn: 'ut2' } }))]);
  add('pie-bars2.delay', 'as pie-bars2, the delay on the bars (the series of the first new item decides)',
    [s(pieAB()), s(bars2({ delay: { $fn: 'ut2' } }, { delay: { $fn: 'ut2' } }))]);
  add('bars2-pie.clone', 'as bars2-pie, the pie divides by clone: two whole copies of each slice (opacity 1 stays 1)',
    [s(bars2()), s(pieAB({ divideShape: 'clone' }))]);
  add('pie-bars2.clone', 'as pie-bars2, the old pie divides by clone (the old item\'s divideShape)',
    [s(pieAB({ divideShape: 'clone' })), s(bars2())]);
  add('bars2-pie.timing', 'the pie\'s update timing: 700 ms linear, delay idx * 50 (idx: the flattened new index)',
    [s(bars2()), s(pieAB({}, { animationDurationUpdate: 700, animationEasingUpdate: 'linear', animationDelayUpdate: { $fn: 'idx*50' } }))]);
  // ---- groups ----
  add('bar-pie.rootgroup', 'the root option\'s dataGroupId "r" groups all four bars; the pie has one slice named "r": '
    + 'four bars combine into it', [s(cartN([barS()], null, { dataGroupId: 'r' })), s(solo(pieS({}, [{ name: 'r', value: 10 }])))]);
  add('bar-pie.datagroup', 'dataGroupId "all" on both: many to many, diffed again by id -- A and B one to one, E enters',
    [s(cartN([barS({ dataGroupId: 'all' })])), s(solo(pieS({ dataGroupId: 'all' }, named(['A', 'B', 'E'], [3, 4, 5]))))]);
  const pts = [
    { name: 'p0', value: [10, 20], groupId: 'g1' }, { name: 'p1', value: [14, 26], groupId: 'g1' },
    { name: 'p2', value: [18, 22], groupId: 'g1' }, { name: 'p3', value: [22, 30], groupId: 'g1' },
    { name: 'p4', value: [26, 24], groupId: 'g1' }, { name: 'p5', value: [30, 40], groupId: 'g2' },
    { name: 'p6', value: [34, 12], groupId: 'g3' }, { name: 'p7', value: [38, 18], groupId: 'g3' },
    { name: 'p8', value: [42, 15], groupId: 'g3' }, { name: 'Q', value: [46, 35] }, { name: 'R', value: [50, 28] },
  ];
  add('scatter-bar.groups', 'item groupIds: g1 (five points) combine into bar g1, g2 (one point) morphs one to one, g4 has no old '
    + 'item and enters, the ungrouped Q matches bar Q by id, g3 and R go', [
    s(valueN([{ type: 'scatter', id: 's', universalTransition: true, symbolSize: 14, data: pts }])),
    s(cartN([barS({ id: 's' }, [9, 14, 6, 11])], ['g1', 'g2', 'g4', 'Q']))]);
  const pts2 = [
    { name: 'q0', value: [10, 20], groupId: 'g1' }, { name: 'q1', value: [20, 25], groupId: 'g1' },
    { name: 'q2', value: [30, 22], groupId: 'g1' }, { name: 'q3', value: [40, 30], groupId: 'g1' },
    { name: 'q4', value: [15, 40], groupId: 'g2' }, { name: 'q5', value: [25, 42], groupId: 'g2' },
    { name: 'q6', value: [35, 38], groupId: 'g2' }, { name: 'q7', value: [45, 10], groupId: 'g3' },
    { name: 'Q', value: [50, 15] }, { name: 'z', value: [55, 18], groupId: 'Q' },
  ];
  add('bar-scatter.groups', 'bar g1 separates into four points, bar g2 is null (no element): its three points fade in (enter '
    + 'timing, the first new index), g3 one to one, Q into the point named Q and the point grouped Q', [
    s(cartN([barS({ id: 's' }, [5, null, 8, 4])], ['g1', 'g2', 'g3', 'Q'])),
    s(valueN([{ type: 'scatter', id: 's', universalTransition: true, symbolSize: 12, data: pts2 }]))]);
  // ---- symbols divided ----
  const tri = divide => valueN([{ type: 'scatter', id: 'k', symbol: 'triangle', symbolRotate: 30, symbolSize: 40,
    universalTransition: ut(divide ? { divideShape: divide } : {}),
    data: [{ name: 'T', value: [10, 10] }, { name: 'U', value: [30, 25] }] }]);
  const many = valueN([{ type: 'scatter', id: 'k', universalTransition: true, symbolSize: 10, data: [
    { name: 'm0', value: [5, 5], groupId: 'T' }, { name: 'm1', value: [8, 14], groupId: 'T' },
    { name: 'm2', value: [14, 6], groupId: 'T' }, { name: 'm3', value: [12, 12], groupId: 'T' },
    { name: 'm4', value: [28, 30], groupId: 'U' }, { name: 'm5', value: [34, 22], groupId: 'U' }] }]);
  add('scatter-scatter.split', 'turned triangles (30 deg, size 40) separate into small circles, divideShape split on the old '
    + 'series: the triangle\'s polygon divided at its scale', [s(tri('split')), s(many)]);
  add('scatter-scatter.clone', 'the same with the scatter type\'s default divideShape (clone: an object, not `true`, lets the '
    + 'type default in): copies of the triangle, opacity '
    + '1 - (1 - 0.8)^(1/count)', [s(tri(null)), s(many)]);
  add('scatter-scatter.combine', 'the small circles combine back into the triangles (the new path divided by split, polygons)',
    [s(many), s(tri('split'))]);
  add('scatter-scatter.combine.clone', 'the circles combine into the triangles divided by the scatter type\'s default '
    + 'clone: copies of the triangle, opacity 1 - (1 - 0.8)^(1/count)', [s(many), s(tri(null))]);
  add('line-bar.combine', 'a line\'s empty circles (stroked) grouped x (2) and y (3) combine into bars x and y', [
    s(cartN([{ type: 'line', id: 'l', universalTransition: true, data: [{ value: 3, groupId: 'x' }, { value: 6, groupId: 'x' },
      { value: 4, groupId: 'y' }, { value: 8, groupId: 'y' }, { value: 5, groupId: 'y' }] }], ['A', 'B', 'C', 'D', 'E'])),
    s(cartN([barS({ id: 'l' }, [9, 17])], ['x', 'y']))]);
  // ---- the gallery ----
  const g = gallery();
  add('agg.scatter-bar', 'the gallery\'s scatter-aggregate-bar: 260 and 247 points combine into two bars (seriesKey '
    + '[female, male] against the scatters\' ids, dataGroupId against the bars\' groupIds), delay idx * 7919 % count / count * 400',
  [s(g.scatterOption), s(g.barOption)], { samples: SAMPLES_BIG, digest: true });
  add('agg.bar-scatter', 'and back: the bars separate into the points (oldDataMapForSplit)',
    [s(g.barOption), s(g.scatterOption)], { samples: SAMPLES_BIG, digest: true });
  add('drill.down', 'the gallery\'s bar-drilldown, merged as the example does: Animals separates into five bars (clone)',
    [s(DRILL), s(DRILL_ANIMALS, null, true)]);
  add('drill.up', 'and back up (merged): the five bars combine into Animals (the new path cloned)',
    [s(DRILL), s(DRILL_ANIMALS, null, true), s(DRILL, null, true)]);
  // ---- in flight ----
  add('bars2-pie-bars2.inflight', '200 ms into bars2-pie, the bars again: each combining slice separates from its children '
    + 'as they are', [s(bars2()), s(pieAB()), s(bars2(), 200)]);
  add('pie-bars2-pie.inflight', '200 ms into pie-bars2, the pie again: the morphing bars combine', [s(pieAB()), s(bars2()), s(pieAB(), 200)]);
  add('bars2-pie-bar.inflight', '200 ms into bars2-pie, one bar series with the same list key: one to one by id, from a '
    + 'combining slice -- combined again (forceManyOne)', [s(bars2()), s(pieAB()),
    s(cartN([barS({ id: 'q', universalTransition: ut({ seriesKey: ['b', 'a'] }) })]), 200)]);
  add('bars2-pie-bars2.delay.inflight', '570 ms into bars2-pie.delay (one child of each slice done, one not), the bars again',
    [s(bars2()), s(pieAB({ delay: { $fn: 'ut2' } })), s(bars2({ delay: { $fn: 'ut2' } }, { delay: { $fn: 'ut2' } }), 570)]);
  const L3 = ['a', 'b', 'c'];
  const bars3 = cartN([barS({ id: 'a' }), barS({ id: 'b' }, VALS2), barS({ id: 'c' }, [7, 9, 11, 13])]);
  const pie3 = solo(pieS({ id: 'p', universalTransition: ut({ seriesKey: L3.slice() }) }));
  const pts3 = [];
  [['A', 4], ['B', 1], ['C', 2], ['D', 3]].forEach(([g, n], gi) => {
    for (let i = 0; i < n; i++) pts3.push({ name: g + i, value: [10 + gi * 20 + i * 4, 15 + i * 6], groupId: g });
  });
  add('bars3-pie-scatter.inflight', '200 ms into three bar series combining into a pie (three children a slice), points '
    + 'with the same list key: A into four points (the children cloned round), B into one (combined again, into a circle '
    + 'divided by clone), C into two (the children cut to two), D into three', [s(bars3), s(pie3),
    s(valueN([{ type: 'scatter', id: 's', symbolSize: 12, universalTransition: ut({ seriesKey: L3.slice() }), data: pts3 }]), 200)]);
  return list;
}

// ---------------------------------------------------------------------------
// guards
// ---------------------------------------------------------------------------
function guards(engine, charts) {
  const byId = id => {
    const c = charts.find(x => x.id === id);
    must(c, 'no case ' + id);
    return c;
  };
  const items = c => c.elements.filter(e => e.item);
  const morphs = c => items(c).filter(e => e.morph);
  const combs = c => items(c).filter(e => e.comb);
  const at = (c, arr, t) => (Array.isArray(arr) ? arr[c.samples.indexOf(t)] : arr);
  // engine
  must(engine.some(c => c.kind === 'pathrect' && c.id.includes('strokeonly')), 'no stroke-only rect');
  must(engine.filter(c => c.kind === 'recompose').some(c => c.out === null), 'no recompose without a transform');
  must(engine.find(c => c.id === 'sort.rects').out.join() !== '0,1,2,3,4', 'sort.rects did not reorder');
  // combine: every slice two children, morphing at the first sample, none at the end
  for (const id of ['bars2-pie', 'bars2-pie.delay', 'bars2-pie.clone', 'bars2-pie.timing']) {
    const c = byId(id);
    must(combs(c).length === 4, id + ': not four combining slices but ' + combs(c).length);
    for (const e of combs(c)) {
      must(e.pieces.length === 2, id + ' ' + e.id + ': not two children');
      must(e.comb[0], id + ' ' + e.id + ': not combining at 0');
      must(!e.comb[e.comb.length - 1], id + ' ' + e.id + ': still combining at the end');
    }
    must(morphs(c).length === 0, id + ': a slice morphs by itself');
  }
  {
    // one __morphT through during: the synchronous first step hands it to both children at once
    const c = byId('bars2-pie');
    const e = combs(c)[0];
    must(e.pieces[0].morph[0] && e.pieces[1].morph[0], 'bars2-pie: the children do not morph from the start');
    must(JSON.stringify(e.pieces[0].d[0]) !== JSON.stringify(e.pieces[0].d[6]), 'bars2-pie: a child does not move');
    const d = byId('bars2-pie.delay');
    const ed = combs(d)[0];
    must(ed.pieces[0].morph[0], 'delay: an individual child does not morph at 0');
    must(JSON.stringify(ed.pieces[1].d[c.samples.indexOf(50)]) === JSON.stringify(ed.pieces[1].d[0])
      && JSON.stringify(ed.pieces[1].d[c.samples.indexOf(100)]) !== JSON.stringify(ed.pieces[1].d[0]), 'delay: child 1 not held to 90 ms');
    const cl = byId('bars2-pie.clone');
    must(JSON.stringify(combs(cl)[0].pieces[0].d) !== JSON.stringify(combs(c)[0].pieces[0].d), 'clone: the children are the split\'s');
    const cc = byId('scatter-scatter.combine.clone');
    must(combs(cc).length === 2 && combs(cc)[0].pieces.every(pc => Array.isArray(pc.style.opacity) && pc.style.opacity[0] === hex(0.8)
      && pc.style.opacity[9] !== hex(0.8)),
      'combine.clone: the children\'s opacity is not fitted');
  }
  // separate: eight bars morph
  for (const id of ['pie-bars2', 'pie-bars2.delay', 'pie-bars2.clone']) {
    must(morphs(byId(id)).length === 8, id + ': not eight morphs but ' + morphs(byId(id)).length);
  }
  must(JSON.stringify(byId('pie-bars2.delay').elements) !== JSON.stringify(byId('pie-bars2').elements), 'pie-bars2.delay = pie-bars2');
  must(JSON.stringify(byId('pie-bars2.clone').elements) !== JSON.stringify(byId('pie-bars2').elements), 'pie-bars2.clone = pie-bars2');
  {
    const c = byId('bar-pie.rootgroup');
    must(combs(c).length === 1 && combs(c)[0].pieces.length === 4, 'rootgroup: not one slice of four children');
    const dg = byId('bar-pie.datagroup');
    must(morphs(dg).length === 2 && combs(dg).length === 0, 'datagroup: not two one-to-one morphs');
  }
  {
    const c = byId('scatter-bar.groups');
    const byIdx = i => items(c).find(e => e.dataIndex === i);
    must(byIdx(0).comb && byIdx(0).pieces.length === 5, 'groups: g1 is not five children');
    must(byIdx(1).morph && !byIdx(1).comb, 'groups: g2 does not morph one to one');
    must(!byIdx(2).morph && !byIdx(2).comb, 'groups: g4 morphs');
    must(byIdx(3).morph, 'groups: Q does not morph');
  }
  {
    const c = byId('bar-scatter.groups');
    const byIdx = i => items(c).find(e => e.dataIndex === i);
    for (const i of [0, 1, 2, 3, 7, 8, 9]) must(byIdx(i).morph, 'bar-scatter.groups: ' + i + ' does not morph');
    for (const i of [4, 5, 6]) {
      must(!byIdx(i).morph && at(c, byIdx(i).style.opacity, 0) === hex(0), 'bar-scatter.groups: ' + i + ' does not fade in');
    }
  }
  for (const id of ['scatter-scatter.split', 'scatter-scatter.clone']) must(morphs(byId(id)).length === 6, id + ': not six morphs');
  must(JSON.stringify(byId('scatter-scatter.split').elements) !== JSON.stringify(byId('scatter-scatter.clone').elements),
    'split = clone on the triangles');
  must(combs(byId('scatter-scatter.combine')).length === 2, 'scatter-scatter.combine: not two combining');
  must(combs(byId('line-bar.combine')).length === 2, 'line-bar.combine: not two combining');
  {
    const c = byId('agg.scatter-bar');
    must(combs(c).length === 2 && combs(c).map(e => e.pieces.length).sort().join() === '247,260', 'agg.scatter-bar: not 260 + 247');
    const b = byId('agg.bar-scatter');
    must(morphs(b).length === 507, 'agg.bar-scatter: not 507 morphs but ' + morphs(b).length);
  }
  must(morphs(byId('drill.down')).length === 5, 'drill.down: not five morphs');
  must(combs(byId('drill.up')).length === 1 && combs(byId('drill.up'))[0].pieces.length === 5, 'drill.up: not one of five');
  {
    // in flight: separated from the children as they were, combined from morphing bars
    must(morphs(byId('bars2-pie-bars2.inflight')).length === 8, 'inflight: not eight morphs');
    must(JSON.stringify(morphs(byId('bars2-pie-bars2.inflight'))[0].d[0]) !== JSON.stringify(morphs(byId('pie-bars2'))[0].d[0]),
      'inflight: separated from the settled slices');
    must(combs(byId('pie-bars2-pie.inflight')).length === 4, 'pie-bars2-pie.inflight: not four combining');
    must(combs(byId('bars2-pie-bar.inflight')).length === 4, 'bars2-pie-bar.inflight: not four combining');
    must(morphs(byId('bars2-pie-bars2.delay.inflight')).length === 8, 'delay.inflight: not eight morphs');
    const c3 = byId('bars3-pie-scatter.inflight');
    must(morphs(c3).length === 9 && combs(c3).length === 1 && combs(c3)[0].pieces.length === 3,
      'bars3-pie-scatter.inflight: not nine morphs and one point of three children');
  }
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const engine = engineCases();
  const charts = chartCases().map(c => Object.assign(c, runCase(c)));
  guards(engine, charts);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'D5 UT2: engine = PathProxy.getBoundingRect, Path.getBoundingRect with a stroke, setLocalTransform + updateTransform, '
      + 'sortPaths, on what real elements answer; charts = steps of setOption (the first at T0; a next one after the previous ran '
      + 'out, T + 10000, or `after` ms into it; notMerge unless `merge`), recorded at the last T + samples. Each element: an item '
      + 'path of a new series (id s<series>/<dataIndex>/<path>) or another path of its view (s<series>/x/<k>); morph[i] = '
      + '__morphT >= 0 and not combining, d[i] the replaced buildPath\'s PathProxy data (codes M1 L2 C3); comb[i] = '
      + '__isCombineMorphing, pieces = its childrenRef() in order (present, morph, d, style); style = the effective fill / '
      + 'stroke / lineWidth / opacity, snap = the path\'s transform and shape keys, g.* its Symbol group\'s -- a key the same '
      + 'at every sample written once. Every number is the hex of its double; a digest case writes a path as fnv<count>:<FNV-1a '
      + '32 of the hexes joined by ",">.',
    W, H, seed: SEED, clock: { T0: T_BASE, gap: T_GAP },
    engine, charts,
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
