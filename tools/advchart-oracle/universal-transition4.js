// Fix phase F3c: universalTransition, the rest -- every element type upstream
// morphs (a funnel's polygon, a bar on a polar, a pictorialBar's glyphs, a
// map's regions, a custom series' elements, a lines series' line and its end
// symbols), mixed batches of them, the labels riding the morph frames, the
// same-type sunburst / treemap batches (one view: animateElementStyles), and
// setOption's `transition` option (transitionSeriesFromOpt).
//
// From the real ECharts 6.1 dist: a sequence of setOption calls (the first at
// T0; each next one after the previous has run out -- T + 10000 -- or `after`
// ms into it; notMerge unless the step says merge; `opts` adds to the second
// argument), recorded at the last one's T + each sample: every item path of
// the new series (getPathList of its item graphic element, in order) --
// whether it is morphing, the morph path its replaced buildPath draws, its
// style, its transform and shape keys, its text (the textContent's computed
// place and opacity) -- and, while it is combining (__isCombineMorphing),
// every child it draws in its place (childrenRef); and every other path of
// the new series' views (with the item it belongs to, where it is in an
// item's group).
// The clock harness is animation.js' (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames).
// Run: node tools/advchart-oracle/universal-transition4.js
//   -> tests/fixtures/advchart-universal-transition4.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-universal-transition4.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery');
const MAPS_DIR = path.join(ROOT, 'examples', 'advchart', 'maps');

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

// ---------- the renderItems (each mirrored in tests/test.advchart.universaltransition4.pas) ----------
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
// the gallery's pie-parliament-transition, its data and its layout
const PARL_DATA = [
  { value: 800, name: 'A' }, { value: 635, name: 'B' }, { value: 580, name: 'C' },
  { value: 484, name: 'D' }, { value: 300, name: 'E' }, { value: 200, name: 'F' },
];
const PARL_RADIUS = ['30%', '80%'];
const PARL_ANGLES = (function () {
  const sum = PARL_DATA.reduce((s, cur) => s + cur.value, 0);
  const angles = [];
  const startAngle = -Math.PI / 2;
  let curAngle = startAngle;
  PARL_DATA.forEach(item => {
    angles.push(curAngle);
    curAngle += (item.value / sum) * Math.PI * 2;
  });
  angles.push(startAngle + Math.PI * 2);
  return angles;
})();
function parliamentLayout(startAngle, endAngle, totalAngle, r0, r1, size) {
  const rowsCount = Math.ceil((r1 - r0) / size);
  const points = [];
  let r = r0;
  for (let i = 0; i < rowsCount; i++) {
    const totalRingSeatsNumber = Math.round((totalAngle * r) / size);
    const newSize = (totalAngle * r) / totalRingSeatsNumber;
    for (let k = Math.floor((startAngle * r) / newSize) * newSize;
      k < Math.floor((endAngle * r) / newSize) * newSize - 1e-6; k += newSize) {
      const angle = k / r;
      points.push([Math.cos(angle) * r, Math.sin(angle) * r]);
    }
    r += size;
  }
  return points;
}
const FNS = {
  // the gallery's parliament: a group of circles, one per seat
  parliament(params, api) {
    const idx = params.dataIndex;
    const viewSize = Math.min(api.getWidth(), api.getHeight());
    const r0 = ((parseFloat(PARL_RADIUS[0]) / 100) * viewSize) / 2;
    const r1 = ((parseFloat(PARL_RADIUS[1]) / 100) * viewSize) / 2;
    const cx = api.getWidth() * 0.5;
    const cy = api.getHeight() * 0.5;
    const size = viewSize / 50;
    const points = parliamentLayout(PARL_ANGLES[idx], PARL_ANGLES[idx + 1], Math.PI * 2, r0, r1, size + 3);
    return {
      type: 'group',
      children: points.map(pt => ({
        type: 'circle',
        shape: { cx: cx + pt[0], cy: cy + pt[1], r: size / 2 },
        style: { fill: PALETTE[idx % PALETTE.length] },
      })),
    };
  },
  // a bar's column as a rect, a circle on its top, and a text (no path)
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
  // one rect, its fill the visual colour, the rect turned 15 degrees about its centre
  tile(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    return {
      type: 'rect', x: p[0], y: p[1], rotation: Math.PI / 12,
      shape: { x: -10, y: -10, width: 20, height: 20 }, style: { fill: api.visual('color') },
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

// ---------- the maps ----------
function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
function rev(r) { return r.slice().reverse(); }
function feat(name, geometry) {
  return { type: 'Feature', properties: { name }, geometry };
}
// four regions with data -- a square, a triangle, a square with a hole, two
// squares -- a line and one region no data names
const UT4 = {
  type: 'FeatureCollection',
  features: [
    feat('A', { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] }),
    feat('B', { type: 'Polygon', coordinates: [[[12, 0], [22, 0], [17, 10], [12, 0]]] }),
    feat('C', { type: 'Polygon', coordinates: [sq(0, 12, 10, 22), rev(sq(3, 15, 7, 19))] }),
    feat('D', { type: 'MultiPolygon', coordinates: [[sq(12, 12, 16, 16)], [sq(18, 18, 22, 22)]] }),
    feat('E', { type: 'LineString', coordinates: [[25, 0], [25, 22]] }),
    feat('X', { type: 'Polygon', coordinates: [sq(27, 0, 32, 5)] }),
  ],
};
const USA_SPECIAL = {
  Alaska: { left: -131, top: 25, width: 15 },
  Hawaii: { left: -110, top: 28, width: 5 },
  'Puerto Rico': { left: -76, top: 26, width: 2 },
};
const MAPS = [
  { name: 'ut4', text: JSON.stringify(UT4), special: null },
  { name: 'USA', text: fs.readFileSync(path.join(MAPS_DIR, 'USA.json'), 'utf8'), special: USA_SPECIAL },
];
function registerMaps() {
  for (const m of MAPS) {
    if (m.special) echarts.registerMap(m.name, m.text, m.special);
    else echarts.registerMap(m.name, m.text);
  }
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
          must(clipCount(zr) === 0, c.id + ': step ' + (i - 1) + ' did not settle');
          t += T_GAP;
        }
        else {
          for (const k of [16, st.after / 2, st.after]) step(zr, t + k);
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
const hcart = (series, extra) => Object.assign({ color: PALETTE, yAxis: { type: 'category', data: NAMES },
  xAxis: { type: 'value' }, series }, extra || {});
const solo = (series, extra) => Object.assign({ color: PALETTE, series: Array.isArray(series) ? series : [series] }, extra || {});
const polar = (series, extra) => Object.assign({ color: PALETTE, polar: { radius: [20, '75%'] },
  angleAxis: { type: 'category', data: NAMES }, radiusAxis: {}, series }, extra || {});
const UT = { universalTransition: true };
const barS = (extra, data) => Object.assign({ type: 'bar', id: 'k', data: data || items(VALS) }, UT, extra || {});
const pieS = (extra, data) => Object.assign({ type: 'pie', id: 'k', radius: '60%', label: { show: false },
  data: data || items(VALS) }, UT, extra || {});
const funnelS = (extra, data) => Object.assign({ type: 'funnel', id: 'k', label: { show: false }, data: data || items(VALS) },
  UT, extra || {});
const polarS = (extra, data) => Object.assign({ type: 'bar', id: 'k', coordinateSystem: 'polar', data: data || items(VALS) },
  UT, extra || {});
const pictS = (extra, data) => Object.assign({ type: 'pictorialBar', id: 'k', symbol: 'rect', symbolRepeat: true,
  symbolSize: [20, 10], data: data || items(VALS) }, UT, extra || {});
// the region colours written out (the port's defaults are its skin's)
const MAP_STYLE = { areaColor: '#e8ecf4', borderColor: '#9aa0aa', borderWidth: 0.5 };
const mapS = (extra, data) => Object.assign({ type: 'map', id: 'k', map: 'ut4', itemStyle: MAP_STYLE,
  data: data || items(VALS) }, UT, extra || {});
const linesS = (extra) => Object.assign({ type: 'lines', id: 'k', coordinateSystem: 'cartesian2d',
  data: NAMES.map((n, i) => ({ name: n, coords: [[i, 0], [i + 0.5, VALS[i]]] })) }, UT, extra || {});
const customS = (fn, extra) => Object.assign({ type: 'custom', id: 'k', renderItem: { $fn: fn },
  data: NAMES.map((n, i) => ({ name: n, value: [i, VALS[i]] })) }, UT, extra || {});
const vcart = (series, extra) => Object.assign({ color: PALETTE, xAxis: { type: 'value', min: 0, max: 4 },
  yAxis: { type: 'value', min: 0, max: 10 }, series }, extra || {});

function galleryOption(file) {
  const o = JSON.parse(fs.readFileSync(path.join(GALLERY, file), 'utf8'));
  if (o.color == null) o.color = PALETTE;
  // a map's region colours written out too
  const ser = Array.isArray(o.series) ? o.series : [o.series];
  for (const s of ser) if (s && s.type === 'map' && s.itemStyle == null) s.itemStyle = MAP_STYLE;
  return o;
}

function chartCases() {
  const list = [];
  const add = (id, note, steps, opts) => list.push(Object.assign({ id, note, steps, samples: SAMPLES, digest: false }, opts || {}));
  const s = (option, after, merge, opts) => {
    const o = { option, after: after == null ? null : after, merge: !!merge };
    if (opts) o.opts = opts;
    return o;
  };
  // ---- a funnel ----
  add('bar-funnel', 'four bars into a funnel of the same names: rects into polygons, one to one',
    [s(cart([barS()])), s(solo(funnelS()))]);
  add('funnel-bar', 'and back', [s(solo(funnelS())), s(cart([barS()]))]);
  // ---- a bar on a polar ----
  // (the same id and type would keep the one bar view, whose rects then take the sectors' shape keys)
  const KK = { universalTransition: { enabled: true, seriesKey: 'kk' } };
  add('bar-polar', 'cartesian bars into radial bars on a polar (sectors), one seriesKey',
    [s(cart([barS(Object.assign({ id: 'c' }, KK))])), s(polar([polarS(Object.assign({ id: 'p' }, KK))]))]);
  add('polar-pie', 'polar bars into pie slices', [s(polar([polarS()])), s(solo(pieS()))]);
  add('pie-polar.round', 'pie slices into polar bars with roundCap (sausages)',
    [s(solo(pieS())), s(polar([polarS({ roundCap: true })]))]);
  const tpolar = (series, extra) => Object.assign({ color: PALETTE, polar: { radius: [20, '75%'] },
    radiusAxis: { type: 'category', data: NAMES }, angleAxis: { max: 10 }, series }, extra || {});
  add('pie-polar.sausage', 'pie slices into tangential polar bars with roundCap (Sausages: split as polygons)',
    [s(solo(pieS())), s(tpolar([polarS({ roundCap: true })]))]);
  add('polar.sausage-bar', 'and the sausages into bars, one seriesKey',
    [s(tpolar([polarS(Object.assign({ id: 'p', roundCap: true }, KK))])), s(cart([barS(Object.assign({ id: 'c' }, KK))]))]);
  add('polar.radius-bar', 'polar bars with a border radius (rounded sectors) into cartesian bars',
    [s(polar([polarS(Object.assign({ id: 'p', itemStyle: { borderRadius: 6 } }, KK))])),
      s(cart([barS(Object.assign({ id: 'c' }, KK))]))]);
  // ---- a pictorialBar ----
  add('bar-pict', 'bars into repeated rect glyphs: one rect separates into each column\'s glyphs',
    [s(cart([barS()])), s(cart([pictS()]))]);
  add('pict-bar', 'and back: the glyphs combine into each bar', [s(cart([pictS()])), s(cart([barS()]))]);
  add('pict.single-pie', 'single circle glyphs (no repeat), turned, into pie slices',
    [s(cart([pictS({ symbol: 'circle', symbolRepeat: false, symbolSize: [30, 30], symbolRotate: 30 })])), s(solo(pieS()))]);
  // ---- a map ----
  add('map-bar', 'a map\'s regions into bars by name (a region of two polygons is one path; one with a hole too)',
    [s(solo(mapS())), s(cart([barS()]))]);
  add('bar-map', 'and back (the region no data names fades in)', [s(cart([barS()])), s(solo(mapS()))]);
  // ---- a custom series ----
  add('bar-custom.pin', 'bars into a custom series drawing a group of a rect and a circle per item: each bar separates '
    + 'into two', [s(cart([barS()])), s(cart([customS('pin')]))]);
  add('custom.pin-pie', 'and the two combine into pie slices', [s(cart([customS('pin')])), s(solo(pieS()))]);
  add('custom.tile-bar', 'a custom series of turned rects (a transform on the path) into bars',
    [s(vcart([customS('tile')])), s(cart([barS()]))]);
  // ---- a lines series ----
  add('bar-lines', 'bars into lines (each a line path)', [s(cart([barS()])), s(vcart([linesS()]))]);
  add('lines.sym-pie', 'lines with end symbols (three paths an item) into pie slices',
    [s(vcart([linesS({ symbol: ['circle', 'arrow'], symbolSize: 10 })])), s(solo(pieS()))]);
  // ---- a mixed batch ----
  add('mixed.list', 'a bar series a and a funnel b combine into one pie whose seriesKey lists them',
    [s(cart([barS({ id: 'a' }), funnelS({ id: 'b', width: '30%', left: '65%' })])),
      s(solo(pieS({ id: 'p', universalTransition: { enabled: true, seriesKey: ['a', 'b'] } })))]);
  add('mixed.split', 'and the pie splits back into the bars and the funnel',
    [s(solo(pieS({ id: 'p', universalTransition: { enabled: true, seriesKey: ['a', 'b'] } }))),
      s(Object.assign(cart([barS({ id: 'a' }), funnelS({ id: 'b', width: '30%', left: '65%' })])))]);
  // ---- the labels ----
  add('label.pie-bar', 'pie slices into bars whose labels show on top: each label rides its bar\'s morph frame',
    [s(solo(pieS())), s(cart([barS({ label: { show: true, position: 'top' } })]))]);
  add('label.bar-hbar', 'vertical bars into horizontal ones under one seriesKey, the labels inside / right',
    [s(cart([barS({ id: 'a', universalTransition: { enabled: true, seriesKey: 'kk' }, label: { show: true } })])),
      s(hcart([barS({ id: 'b', universalTransition: { enabled: true, seriesKey: 'kk' },
        label: { show: true, position: 'right' } })]))]);
  add('label.bar-pie', 'bars into slices whose labels are outside (laid out by the pie, not by the slice)',
    [s(cart([barS()])), s(solo(pieS({ label: { show: true } })))]);
  add('label.funnel-polar', 'a funnel into polar bars with labels inside',
    [s(solo(funnelS())), s(polar([polarS({ label: { show: true, position: 'middle' } })]))]);
  // ---- the same type, one view ----
  const small = () => [{ id: 'a', name: 'a', children: [{ id: 'a1', name: 'a1', value: 3 }, { id: 'a2', name: 'a2', value: 5 }] },
    { id: 'b', name: 'b', value: 4 }, { id: 'c', name: 'c', children: [{ id: 'c1', name: 'c1', value: 2 }] }];
  const small2 = () => [{ id: 'a', name: 'a', children: [{ id: 'a1', name: 'a1', value: 6 }, { id: 'a2', name: 'a2', value: 1 }] },
    { id: 'b', name: 'b', value: 2 }, { id: 'd', name: 'd', value: 5 }];
  const sb = (pal, data) => ({ color: pal, series: [{ type: 'sunburst', id: 'pk', radius: ['20%', '90%'], animationDurationUpdate: 1000,
    nodeClick: false, universalTransition: true, label: { show: false }, data }] });
  const tm = (pal, data) => ({ color: pal, series: [{ type: 'treemap', id: 'pk', animationDurationUpdate: 1000, roam: false,
    nodeClick: false, universalTransition: true, label: { show: false }, breadcrumb: { show: false }, data }] });
  const REV = PALETTE.slice().reverse();
  add('sb-sb.recolor', 'the same sunburst with a new palette: one view keeps its pieces -- each fades its style from the '
    + 'old one saved (animateElementStyles)', [s(sb(PALETTE, small())), s(sb(REV, small()))]);
  add('sb-sb.data', 'the same sunburst with other data (c and c1 gone, d new): the kept pieces restyle, d enters',
    [s(sb(PALETTE, small())), s(sb(PALETTE, small2()))]);
  const small3 = () => [{ id: 'a', name: 'a', children: [{ id: 'a1', name: 'a1', value: 6 }, { id: 'a2', name: 'a2', value: 1 }] },
    { id: 'b', name: 'b', value: 2 }, { id: 'c', name: 'c', children: [{ id: 'c1', name: 'c1', value: 5 }] }];
  add('tm-tm.data', 'the same treemap with other values and a new palette: one view, no style saved -- nothing of the '
    + 'transition', [s(tm(PALETTE, small())), s(tm(REV, small3()))], { digest: true });
  // ---- setOption's transition ----
  const T = (from, to) => ({ transition: { from, to } });
  add('opt.index', 'a bar series a into a pie b: no key pairs them, transition {from: seriesIndex 0, to: seriesIndex 0} '
    + 'does', [s(cart([barS({ id: 'a' })])), s(solo(pieS({ id: 'b' })), null, false, T({ seriesIndex: 0 }, { seriesIndex: 0 }))]);
  add('opt.id', 'the same by seriesId', [s(cart([barS({ id: 'a' })])),
    s(solo(pieS({ id: 'b' })), null, false, T({ seriesId: 'a' }, { seriesId: 'b' }))]);
  add('opt.off', 'the new series has universalTransition off: the transition option does not ask',
    [s(cart([barS({ id: 'a' })])), s(solo(pieS({ id: 'b', universalTransition: false })), null, false,
      T({ seriesIndex: 0 }, { seriesIndex: 0 }))]);
  add('opt.missing', 'from a series index the old option does not have: nothing transitions -- and the key batch, '
    + 'which would pair the same ids, is not asked either', [s(cart([barS()])),
    s(solo(pieS()), null, false, T({ seriesIndex: 3 }, { seriesIndex: 0 }))]);
  add('opt.array', 'two transitions in a list: a -> c and b -> d (two old bar series into two pies)', [
    s(cart([barS({ id: 'a' }), barS({ id: 'b', data: items([2, 4, 6, 8]) })])),
    s(solo([pieS({ id: 'c', center: ['25%', '50%'], radius: '30%' }), pieS({ id: 'd', center: ['75%', '50%'], radius: '30%' })]),
      null, false, { transition: [{ from: { seriesIndex: 0 }, to: { seriesIndex: 0 } },
        { from: { seriesId: 'b' }, to: { seriesIndex: 1 } }] })]);
  add('opt.many', 'from two old series to one (a list of finders): their items pair by group', [
    s(cart([barS({ id: 'a', dataGroupId: 'g' }), barS({ id: 'b', dataGroupId: 'h', data: items([2, 4, 6, 8]) })])),
    s(solo(pieS({ id: 'c', data: [{ name: 'G', value: 3, groupId: 'g' }, { name: 'H', value: 5, groupId: 'h' }] })),
      null, false, T([{ seriesIndex: 0 }, { seriesIndex: 1 }], { seriesIndex: 0 }))]);
  add('opt.groupbug', 'the new side reads the OLD series\' dataGroupId at its index (transitionSeriesFromOpt): the '
    + 'old bars grouped g, the new pie grouped z -- both keyed g, many to many, by id one to one', [
    s(cart([barS({ id: 'a', dataGroupId: 'g' })])),
    s(solo(pieS({ id: 'b', dataGroupId: 'z' })), null, false, T({ seriesIndex: 0 }, { seriesIndex: 0 }))]);
  add('opt.dimension', 'a finder\'s dimension changes nothing (upstream reads it into groupIdDim and never uses it)', [
    s(cart([barS({ id: 'a' })])), s(solo(pieS({ id: 'b' })), null, false,
      T({ seriesIndex: 0, dimension: 1 }, { seriesIndex: 0, dimension: 0 }))]);
  add('opt.custom', 'the same custom series with the transition option: its items are made anew (isUniversalTransition'
    + 'Enabled for the series it names) and each morphs from its old element', [
    s(vcart([customS('tile', { universalTransition: false })])),
    s(vcart([customS('tile', { universalTransition: false, data: NAMES.map((n, i) => ({ name: n, value: [i + 0.5, VALS[3 - i]] })) })]),
      null, true, T({ seriesIndex: 0 }, { seriesIndex: 0 }))]);
  // ---- interrupted ----
  add('bar-pict.inflight', '200 ms into bars -> glyphs, the bars again: each bar combines the glyphs where they are',
    [s(cart([barS()])), s(cart([pictS()])), s(cart([barS()]), 200)]);
  // ---- the gallery's ----
  add('gal.pict-bar', 'pictorialBar-bar-transition: the vehicles\' glyphs into bars (merged, as the page does)',
    [s(galleryOption('pictorialBar-bar-transition.json')), s(galleryOption('pictorialBar-bar-transition.2.json'), null, true)],
    { samples: SAMPLES_BIG, digest: true });
  add('gal.bar-pict', 'and the bars back into glyphs',
    [s(galleryOption('pictorialBar-bar-transition.json')), s(galleryOption('pictorialBar-bar-transition.2.json'), null, true),
      s(galleryOption('pictorialBar-bar-transition.3.json'), null, true)], { samples: SAMPLES_BIG, digest: true });
  add('gal.map-bar', 'map-bar-morph: the USA\'s states into bars (notMerge, as the page does)',
    [s(galleryOption('map-bar-morph.json')), s(galleryOption('map-bar-morph.2.json'))], { samples: SAMPLES_BIG, digest: true });
  add('gal.bar-map', 'and the bars back into states',
    [s(galleryOption('map-bar-morph.2.json')), s(galleryOption('map-bar-morph.json'))], { samples: SAMPLES_BIG, digest: true });
  const parlPie = { color: PALETTE, series: [{ type: 'pie', id: 'distribution', radius: PARL_RADIUS, label: { show: false },
    universalTransition: true, animationDurationUpdate: 1000, data: PARL_DATA }] };
  const parl = { color: PALETTE, series: [{ type: 'custom', id: 'distribution', data: PARL_DATA, coordinateSystem: 'none',
    universalTransition: true, animationDurationUpdate: 1000, renderItem: { $fn: 'parliament' } }] };
  add('gal.pie-parl', 'pie-parliament-transition: each slice separates into its seats (merged, as the page does)',
    [s(parlPie), s(parl, null, true)], { samples: SAMPLES_BIG, digest: true });
  add('gal.parl-pie', 'and the seats combine into the slices', [s(parlPie), s(parl, null, true), s(parlPie, null, true)],
    { samples: SAMPLES_BIG, digest: true });
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
  const items = c => c.elements.filter(e => e.item);
  const morphs = c => items(c).filter(e => e.morph);
  const combs = c => items(c).filter(e => e.comb);
  const atLeast = (id, n, what) => must(what(byId(id)).length >= n, id + ': ' + what(byId(id)).length + ' < ' + n);
  const none = id => must(morphs(byId(id)).length === 0 && combs(byId(id)).length === 0, id + ': transitions');
  for (const id of ['bar-funnel', 'funnel-bar', 'bar-polar', 'polar-pie', 'pie-polar.round', 'polar.radius-bar',
    'map-bar', 'bar-map', 'custom.tile-bar', 'bar-lines', 'opt.index', 'opt.id', 'opt.off', 'opt.dimension', 'opt.groupbug',
    'label.pie-bar', 'label.bar-hbar', 'label.bar-pie', 'label.funnel-polar', 'opt.custom']) atLeast(id, 4, morphs);
  must(morphs(byId('bar-pict')).length > 8, 'bar-pict: the glyphs do not morph');
  must(combs(byId('pict-bar')).length === 4, 'pict-bar: not four combining');
  must(morphs(byId('bar-custom.pin')).length === 8, 'bar-custom.pin: not eight morphs');
  must(combs(byId('custom.pin-pie')).length === 4, 'custom.pin-pie: not four combining');
  must(combs(byId('lines.sym-pie')).length === 4, 'lines.sym-pie: not four combining');
  none('opt.missing');
  atLeast('opt.array', 8, morphs);
  atLeast('mixed.list', 4, combs);
  must(byId('sb-sb.recolor').elements.some(e => e.item && Array.isArray(e.style.fill)), 'sb-sb.recolor: no style moves');
  none('sb-sb.recolor');
  none('tm-tm.data');
  must(byId('label.pie-bar').elements.some(e => e.text && new Set(e.text.x).size > 2), 'label.pie-bar: no text moves');
  must(morphs(byId('gal.map-bar')).length > 40, 'gal.map-bar: few morphs');
  must(morphs(byId('gal.bar-map')).length > 40, 'gal.bar-map: few morphs');
  must(combs(byId('gal.parl-pie')).length === 6, 'gal.parl-pie: not six combining');
  must(morphs(byId('gal.pie-parl')).length > 100, 'gal.pie-parl: few morphs');
}

const NO_GUARDS = process.env.UT4_NO_GUARDS === '1';
function generate() {
  NOW = T_BASE;
  rngState = SEED;
  registerMaps();
  const charts = chartCases().map(c => Object.assign(c, runCase(c)));
  if (!NO_GUARDS) guards(charts);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'F3c: steps of setOption (the first at T0; a next one after the previous ran out, T + 10000, or `after` ms into '
      + 'it; notMerge unless `merge`; `opts` added to the second argument), recorded at the last T + samples. Each element: '
      + 'an item path of a new series (id s<series>/<dataIndex>/<path>, the path its place in getPathList) or another path '
      + 'of its view (s<series>/x/<k>, owner the item whose group holds it); morph[i] = __morphT >= 0 and not combining, '
      + 'd[i] the replaced buildPath\'s PathProxy data (codes M1 L2 C3 Q4 A5 Z6 R7); comb[i] = __isCombineMorphing, pieces = '
      + 'its childrenRef() in order; style = the effective fill / stroke / lineWidth / opacity, snap = the path\'s transform '
      + 'and shape keys -- a key the same at every sample written once; text = the textContent\'s computed translation plus '
      + 'its style x / y, and its opacity. oldRest / newRest: every item path at rest before the last step and after it has '
      + 'run out (PathProxy data, computed transform). Every number is the hex of its double; a digest case writes a path '
      + 'as fnv<count>:<FNV-1a 32 of the hexes joined by ",">.',
    W, H, seed: SEED, clock: { T0: T_BASE, gap: T_GAP },
    maps: MAPS.map(m => ({ name: m.name, text: m.text, special: m.special })),
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
