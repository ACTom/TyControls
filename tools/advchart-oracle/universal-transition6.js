// Round 6 R6-C: universalTransition, the structural gaps -- the style track
// past fill / stroke / lineWidth / opacity (the shadow's four keys,
// fillOpacity / strokeOpacity, gradients and their colour stops), an old
// series the legend has switched off (it stays in the store: its items have
// no element, so the new items they pair with fade in), the children of a
// combining host (each one hit, at the host's place in the display list; a
// host that leaves while it combines draws its children), the encoded group
// dimensions read from the store (a dataset, seriesLayoutBy 'row', a time
// dimension through parseDate, an ordinal one through its ordinalMeta), and
// the view groups of a tree and a sankey (removeEl bakes what the render left).
//
// From the real ECharts 6.1 dist, the way universal-transition5.js does it: a
// sequence of steps -- setOption calls (the first at T0; each next one after
// the previous has run out -- T + 10000 -- or `after` ms into it; notMerge
// unless the step says merge) or dispatchAction ones -- recorded at the last
// one's T + each sample: every item path of the new series (getPathList of its
// item graphic element, in order) -- whether it is morphing, the morph path,
// its style (fill -- a colour or a gradient --, stroke, lineWidth, opacity,
// the shadow's four keys, fillOpacity, strokeOpacity), its transform and shape
// keys -- and, while it combines, every child it draws in its place; every
// other path of the new series' views (its opacity); and where a case asks,
// the pointer at each combining child (findHover and the ecData it reaches),
// the display list's order of the item paths, and every path drawn under a
// series view (a leaving host's children).
// The clock harness is animation.js' (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames, the display list built after each).
// Run: node tools/advchart-oracle/universal-transition6.js
//   -> tests/fixtures/advchart-universal-transition6.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-universal-transition6.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const SAMPLES = [0, 1, 16, 50, 100, 150, 250, 300, 400, 499, 500, 501, 750, 1000, 1500];

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

// ---------- the renderItems (each mirrored in tests/test.advchart.universaltransition6.pas) ----------
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const FNS = {
  // a column whose fill and stroke have opacities of their own
  opRect(params, api) {
    const p = api.coord([api.value(0), api.value(1)]);
    const b = api.coord([api.value(0), 0]);
    return {
      type: 'rect', shape: { x: p[0] - 8, y: p[1], width: 16, height: b[1] - p[1] },
      style: { fill: api.visual('color'), fillOpacity: 0.4, stroke: '#ff994d', lineWidth: 2, strokeOpacity: 0.6 },
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
  zr.storage.getDisplayList(true);
}
function itemPaths(el) {
  const out = [];
  if (!el) return out;
  el.traverse(e => {
    if ((e instanceof Path) && !e.disableMorphing && !e.invisible && !e.ignore) out.push(e);
  });
  return out;
}
// getECData = makeInner(): an own property '__ec_inner_<n>'
function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}
// a colour as it is, a gradient as its numbers
function colourOf(v) {
  if (v == null) return null;
  if (typeof v === 'object' && v.colorStops) {
    const g = { type: v.type === 'radial' ? 'radial' : 'linear', global: !!v.global };
    for (const k of ['x', 'y', 'x2', 'y2', 'r']) if (typeof v[k] === 'number') g[k] = hex(v[k]);
    g.stops = v.colorStops.map(s => [hex(s.offset), String(s.color)]);
    return g;
  }
  return String(v);
}
function styleOf(el) {
  const s = el.style;
  const num = v => (v == null ? null : hex(v));
  return { fill: colourOf(s.fill), stroke: colourOf(s.stroke), lineWidth: num(s.lineWidth), opacity: num(s.opacity),
    shadowBlur: num(s.shadowBlur), shadowOffsetX: num(s.shadowOffsetX), shadowOffsetY: num(s.shadowOffsetY),
    shadowColor: s.shadowColor == null ? null : String(s.shadowColor),
    fillOpacity: num(s.fillOpacity), strokeOpacity: num(s.strokeOpacity),
    lineDashOffset: num(s.lineDashOffset), miterLimit: num(s.miterLimit) };
}
const SNAP_KEYS = ['x', 'y', 'scaleX', 'scaleY', 'rotation'];
function snapOf(el) {
  const o = {};
  for (const k of SNAP_KEYS) if (typeof el[k] === 'number') o[k] = hex(el[k]);
  if (el.shape) for (const k of Object.keys(el.shape)) if (typeof el.shape[k] === 'number') o['shape.' + k] = hex(el.shape[k]);
  return o;
}
function compact(arr) {
  const first = JSON.stringify(arr[0]);
  return arr.every(x => JSON.stringify(x) === first) ? arr[0] : arr;
}
function restOf(p) {
  const m = p.getComputedTransform();
  return { d: builtData(p), m: m ? Array.from(m) : null };
}
// the series views' groups: a path drawn under one is the chart's
function viewGroups(chart) {
  return (chart._chartsViews || []).map(v => v.group);
}
function underViews(el, groups) {
  for (let e = el; e; e = e.parent) if (groups.indexOf(e) >= 0) return true;
  return false;
}

// one timeline
function record(chart, start, c) {
  const samples = c.samples;
  const zr = chart.getZr();
  const N = samples.length;
  const recs = new Map();
  const order = [];
  const pathOut = d => hexes(d);
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
  const hits = [];
  const orders = [];
  const display = [];
  samples.forEach((t, si) => {
    NOW = start + t;
    if (si > 0) zr.animation.update();
    const list = zr.storage.getDisplayList(true);
    clips.push(clipCount(zr));
    const model = chart.getModel();
    const pathId = new Map();
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
          const id = 's' + s.seriesIndex + '/' + i + '/' + k;
          pathId.set(p, id);
          const r = rec(id, { series: s.seriesIndex, type: p.type, seriesType: s.subType, dataIndex: i, path: k, item: true });
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
          if (comb) {
            p.childrenRef().forEach((ch, ci) => {
              pathId.set(ch, id + '#' + ci);
              let pc = r.pieces[ci];
              if (!pc) {
                pc = r.pieces[ci] = { present: new Array(N).fill(false), morph: new Array(N).fill(false),
                  d: new Array(N).fill(null), style: {} };
              }
              pc.present[si] = true;
              pc.morph[si] = ch.__morphT >= 0;
              pc.d[si] = pathOut(builtData(ch));
              putStyle(pc, ch, si);
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
    // THE POINTER AT EACH COMBINING CHILD: findHover at the middle of its
    // box, rounded (where the child holds it), the ecData its parents reach
    if (c.hitAt && c.hitAt.indexOf(t) >= 0) {
      const probes = [];
      for (const el of list) {
        if (!(el instanceof Path) || !el.parent || !el.parent.__isCombineMorphing) continue;
        const b = el.getBoundingRect();
        // (a whole pixel: the control's hit test takes integers)
        const x = Math.round(b.x + b.width / 2);
        const y = Math.round(b.y + b.height / 2);
        if (!el.contain(x, y)) continue;
        const hv = zr.handler.findHover(x, y);
        let e = hv && hv.target;
        let ec = null;
        while (e && !(ec = ecDataOf(e))) e = e.parent;
        probes.push({ of: pathId.get(el) || null, x: hex(x), y: hex(y), hit: !!(hv && hv.target),
          child: !!(hv && hv.target === el), series: ec ? ec.seriesIndex : null, dataIndex: ec ? ec.dataIndex : null });
      }
      hits.push({ sample: si, probes });
    }
    // THE DISPLAY LIST'S ORDER of the item paths and the children drawn in
    // their places
    if (c.order) orders.push(list.filter(el => pathId.has(el)).map(el => pathId.get(el)));
    // EVERY PATH DRAWN UNDER A SERIES VIEW, a leaving host's children too
    if (c.display) {
      const groups = viewGroups(chart);
      display.push(list.filter(el => (el instanceof Path) && underViews(el, groups)).map(el => ({
        d: digest(builtData(el)), opacity: el.style.opacity == null ? null : hex(el.style.opacity),
        child: !!(el.parent && el.parent.__isCombineMorphing), type: el.type })));
    }
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
  const res = { clips, elements: out };
  if (c.hitAt) res.hits = hits;
  if (c.order) res.orders = orders;
  if (c.display) res.display = display;
  return res;
}

function restPaths(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    const data = s.getData();
    data.each(i => {
      itemPaths(data.getItemGraphicEl(i)).forEach((p, k) => {
        const r = restOf(p);
        out.push({ id: 's' + s.seriesIndex + '/' + i + '/' + k, type: p.type, d: hexes(r.d), m: r.m ? hexes(r.m) : null });
      });
    });
  });
  return out;
}

// universalTransition.ts' getGroupId over the dist's SeriesData: what each
// item is keyed by (the encoded dimension's value through its ordinalMeta,
// the item's groupId / childGroupId, the dataGroupId, the id)
function groupsOf(chart) {
  const out = [];
  chart.getModel().getSeries().forEach(s => {
    const data = s.getData();
    const dimOf = vd => {
      for (const d of data.dimensions) {
        const info = data.getDimensionInfo(d);
        if (info && info.otherDims[vd] === 0) return d;
      }
      return undefined;
    };
    const byDim = (i, dim) => {
      const info = data.getDimensionInfo(dim);
      const v = data.get(info.name, i);
      if (info.ordinalMeta) return info.ordinalMeta.categories[v] || v + '';
      return v + '';
    };
    const gDim = dimOf('itemGroupId');
    const cDim = dimOf('itemChildGroupId');
    const dg = s.get('dataGroupId');
    const g = [];
    const ch = [];
    for (let i = 0; i < data.count(); i++) {
      const raw = data.getRawDataItem(i);
      if (gDim) g.push(byDim(i, gDim));
      else if (raw && raw.groupId) g.push(raw.groupId + '');
      else g.push(dg || data.getId(i));
      if (cDim) ch.push(byDim(i, cDim));
      else if (raw && raw.childGroupId) ch.push(raw.childGroupId + '');
      else ch.push(null);
    }
    const z = v => (v == null ? v : String(v).split(String.fromCharCode(0)).join('<0>'));
    out.push({ seriesIndex: s.seriesIndex, id: z(s.id), filtered: chart.getModel().isSeriesFiltered(s), groups: g.map(z),
      childGroups: ch.map(z) });
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
    let oldGroups = null;
    c.steps.forEach((st, i) => {
      if (i > 0) {
        if (st.after == null) {
          for (let k = 16; k <= 5000; k += 250) step(zr, t + k);
          must(clipCount(zr) === 0, c.id + ': step ' + (i - 1) + ' did not settle');
          t += T_GAP;
        }
        else {
          for (const k of [16, st.after / 2, st.after]) step(zr, t + k);
          t += st.after;
        }
      }
      if (i === c.steps.length - 1 && i > 0) {
        if (st.after == null) oldRest = restPaths(chart);
        oldGroups = groupsOf(chart);
      }
      NOW = t;
      if (st.action) chart.dispatchAction(Object.assign({}, st.action));
      else {
        const opts = Object.assign({ notMerge: i > 0 && !st.merge }, st.opts ? materialize(st.opts) : {});
        chart.setOption(materialize(st.option), opts);
      }
    });
    const tl = record(chart, t, c);
    const resolved = [];
    chart.getModel().eachSeries(s => resolved.push({ seriesIndex: s.seriesIndex, type: s.subType, id: s.id.replace(/\0/g, '<0>'),
      ut: !!s.isUniversalTransitionEnabled(), animation: !!s.isAnimationEnabled(), count: s.getData().count() }));
    const newGroups = groupsOf(chart);
    for (let k = 16; k <= 5000; k += 250) step(zr, t + 1500 + k);
    const newRest = restPaths(chart);
    const out = { resolved, clips: tl.clips, elements: tl.elements, newRest, oldGroups, newGroups };
    if (tl.hits) out.hits = tl.hits;
    if (tl.orders) out.orders = tl.orders;
    if (tl.display) out.display = tl.display;
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
const vcart = (series, extra) => Object.assign({ color: PALETTE, xAxis: { type: 'value', min: 0, max: 4 },
  yAxis: { type: 'value', min: 0, max: 10 }, series }, extra || {});
const UT = { universalTransition: true };
const barS = (extra, data) => Object.assign({ type: 'bar', id: 'k', data: data || items(VALS) }, UT, extra || {});
const pieS = (extra, data) => Object.assign({ type: 'pie', id: 'k', radius: '60%', label: { show: false },
  data: data || items(VALS) }, UT, extra || {});
const customS = (fn, extra) => Object.assign({ type: 'custom', id: 'k', renderItem: { $fn: fn },
  data: NAMES.map((n, i) => ({ name: n, value: [i, VALS[i]] })) }, UT, extra || {});
const lin = (stops, extra) => Object.assign({ type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
  colorStops: stops.map((c, i) => ({ offset: i / (stops.length - 1), color: c })) }, extra || {});
const rad = (stops) => ({ type: 'radial', x: 0.5, y: 0.5, r: 0.5, colorStops: stops.map((c, i) => ({ offset: i / (stops.length - 1), color: c })) });
const SH1 = { shadowBlur: 10, shadowColor: 'rgba(255,0,0,0.8)', shadowOffsetX: 4, shadowOffsetY: 2 };
const SH2 = { shadowBlur: 4, shadowColor: 'rgba(0,0,255,0.4)', shadowOffsetX: -2, shadowOffsetY: 6 };

function chartCases() {
  const list = [];
  const add = (id, note, steps, opts) => list.push(Object.assign({ id, note, steps, samples: SAMPLES }, opts || {}));
  const s = (option, after, merge, opts) => {
    const o = { option, after: after == null ? null : after, merge: !!merge };
    if (opts) o.opts = opts;
    return o;
  };
  const act = (action, after) => ({ action, after: after == null ? null : after, merge: false });
  // ---- 1. THE STYLE TRACK ----
  add('style.shadow-pie', 'bars casting a shadow into slices with none: the four keys tween to the prototype\'s (0 and #000)',
    [s(cart([barS({ itemStyle: SH1 })])), s(solo(pieS()))]);
  add('style.pie-shadow', 'slices into bars casting one: no own key on the old side, the new shadow from the start',
    [s(solo(pieS())), s(cart([barS({ itemStyle: SH1 })]))]);
  add('style.shadow-shadow', 'one shadow into another', [s(cart([barS({ itemStyle: SH1 })])), s(solo(pieS({ itemStyle: SH2 })))]);
  add('style.grad-grad', 'a linear gradient into another: the stops interpolated',
    [s(cart([barS({ itemStyle: { color: lin(['#ff0000', '#0000ff']) } })])),
      s(solo(pieS({ itemStyle: { color: lin(['#00ff00', '#ffff00'], { x2: 1, y2: 0 }) } })))]);
  add('style.grad3-grad2', 'three stops into two (the shorter filled with its last)',
    [s(cart([barS({ itemStyle: { color: lin(['#ff0000', '#00ff00', '#0000ff']) } })])),
      s(solo(pieS({ itemStyle: { color: lin(['#ffffff', '#000000']) } })))]);
  add('style.grad2-grad3', 'two stops into three',
    [s(cart([barS({ itemStyle: { color: lin(['#ffffff', '#000000']) } })])),
      s(solo(pieS({ itemStyle: { color: lin(['#ff0000', '#00ff00', '#0000ff']) } })))]);
  add('style.radial-radial', 'a radial gradient into another',
    [s(cart([barS({ itemStyle: { color: rad(['#ff0000', '#0000ff']) } })])),
      s(solo(pieS({ itemStyle: { color: rad(['#00ff00', '#ffff00']) } })))]);
  add('style.radial-linear', 'a radial gradient into a linear one (no track)',
    [s(cart([barS({ itemStyle: { color: rad(['#ff0000', '#0000ff']) } })])),
      s(solo(pieS({ itemStyle: { color: lin(['#00ff00', '#ffff00']) } })))]);
  add('style.grad-col', 'a gradient into a colour (no track)', [s(cart([barS({ itemStyle: { color: lin(['#ff0000', '#0000ff']) } })])),
    s(solo(pieS()))]);
  add('style.col-grad', 'a colour into a gradient (no track)', [s(cart([barS()])),
    s(solo(pieS({ itemStyle: { color: lin(['#00ff00', '#ffff00']) } })))]);
  add('style.alpha-grad', 'stops with alpha into stops with alpha',
    [s(cart([barS({ itemStyle: { color: lin(['rgba(255,0,0,0.8)', 'rgba(0,0,255,0.2)']) } })])),
      s(solo(pieS({ itemStyle: { color: lin(['rgba(0,255,0,0.4)', 'rgba(255,255,0,0.6)']) } })))]);
  add('style.opacity-custom-bar', 'a custom rect with fillOpacity 0.4 and strokeOpacity 0.6 into bars: both tween to 1',
    [s(cart([customS('opRect')])), s(cart([barS()]))]);
  add('style.bar-opacity-custom', 'bars into the custom rect: no own key on the old side, 0.4 and 0.6 from the start',
    [s(cart([barS()])), s(cart([customS('opRect')]))]);
  add('style.dash-pie', 'bars with a dashed border shifted by 6 (borderDashOffset) into slices with a solid border: '
    + 'lineDashOffset tweens to the prototype\'s 0',
    [s(cart([barS({ itemStyle: { borderColor: '#ff994d', borderWidth: 2, borderType: 'dashed', borderDashOffset: 6 } })])),
      s(solo(pieS({ itemStyle: { borderColor: '#ffffff', borderWidth: 1 } })))]);
  add('style.miter-pie', 'bars whose border has a miter limit of 4 into slices with a border: miterLimit tweens to the '
    + 'prototype\'s 10', [s(cart([barS({ itemStyle: { borderColor: '#ff994d', borderWidth: 2, borderMiterLimit: 4 } })])),
      s(solo(pieS({ itemStyle: { borderColor: '#ffffff', borderWidth: 1 } })))]);
  add('style.same-bar', 'the same bars (one element each): the saved old style\'s shadow and gradient tween to the new',
    [s(cart([barS({ itemStyle: Object.assign({ color: lin(['#ff0000', '#0000ff']) }, SH1) })])),
      s(cart([barS({ itemStyle: { color: lin(['#00ff00', '#ffff00']) } })]))]);
  // a combine: the scatter's shadowed symbols into one bar a group
  const SCAT = [];
  for (let i = 0; i < 6; i++) SCAT.push({ value: [(i % 3) + 0.5, 2 + i], groupId: ['A', 'B'][i % 2] });
  const scatS = (extra) => Object.assign({ type: 'scatter', id: 's', symbolSize: 20,
    universalTransition: { enabled: true, seriesKey: 'k' }, data: SCAT }, extra || {});
  const gBars = (extra) => Object.assign({ type: 'bar', id: 'b', name: 'bb', universalTransition: { enabled: true, seriesKey: 'k' },
    data: [{ name: 'A', groupId: 'A', value: 6 }, { name: 'B', groupId: 'B', value: 9 }] }, extra || {});
  const gCart = series => ({ color: PALETTE, legend: {}, xAxis: { type: 'category', data: ['A', 'B'] },
    yAxis: { type: 'value', min: 0, max: 10 }, series });
  const sCart = series => ({ color: PALETTE, legend: {}, xAxis: { type: 'value', min: 0, max: 3 },
    yAxis: { type: 'value', min: 0, max: 10 }, series });
  add('style.combine-shadow', 'shadowed symbols combining into bars: each child\'s shadow from its symbol\'s',
    [s(sCart([scatS({ itemStyle: SH1 })])), s(gCart([gBars()]))]);
  add('style.combine-grad', 'symbols filled with a gradient combining into bars filled with another: each child\'s stops '
    + 'interpolated', [s(sCart([scatS({ itemStyle: { color: lin(['#ff0000', '#0000ff']) } })])),
      s(gCart([gBars({ itemStyle: { color: lin(['#00ff00', '#ffff00']) } })]))]);
  // ---- 2. AN OLD SERIES THE LEGEND SWITCHED OFF ----
  const barN = (id, name, vals) => Object.assign({ type: 'bar', id, name, data: items(vals) }, UT);
  const two = () => cart([barN('a', 'sa', VALS), barN('b', 'sb', [2, 4, 6, 8])], { legend: {} });
  const pieB = () => solo(pieS({ id: 'b' }, items([2, 4, 6, 8])));
  add('filtered.toggled-pie', 'b switched off by the legend, then a pie of id b: its slices fade in (b is in the store, its '
    + 'items have no element)', [s(two()), act({ type: 'legendToggleSelect', name: 'sb' }), s(pieB())]);
  add('filtered.selected-pie', 'the same with legend.selected switching b off from the start',
    [s(Object.assign(two(), { legend: { selected: { sb: false } } })), s(pieB())]);
  add('filtered.shown-pie', 'the control: b shown, its bars morph into the slices', [s(two()), s(pieB())]);
  add('filtered.toggled-pie-marked', 'b, with a markPoint, switched off by the legend, then a pie of id b: its slices fade in '
    + 'all the same', [s(cart([barN('a', 'sa', VALS), Object.assign(barN('b', 'sb', [2, 4, 6, 8]),
      { markPoint: { data: [{ type: 'max' }] } })], { legend: {} })), act({ type: 'legendToggleSelect', name: 'sb' }), s(pieB())]);
  add('filtered.merge-marked', 'b (seriesKey kb, a markPoint) switched off, then a merge adding a pie of seriesKey kb: b stays '
    + 'off (and keeps its markers), its items in the store have no element, the slices fade in',
    [s(cart([barN('a', 'sa', VALS), Object.assign(barN('b', 'sb', [2, 4, 6, 8]), { universalTransition: { enabled: true, seriesKey: 'kb' },
      markPoint: { data: [{ type: 'max' }] } })], { legend: {} })), act({ type: 'legendToggleSelect', name: 'sb' }),
      s({ series: [{ id: 'a' }, { id: 'b' }, pieS({ id: 'p', center: ['75%', '50%'], radius: '25%',
        universalTransition: { enabled: true, seriesKey: 'kb' } }, items([2, 4, 6, 8]))] }, null, true)]);
  add('filtered.kept-a', 'a kept and shown, b switched off and turned into a pie',
    [s(two()), act({ type: 'legendToggleSelect', name: 'sb' }),
      s({ color: PALETTE, xAxis: { type: 'category', data: NAMES }, yAxis: {},
        series: [barN('a', 'sa', VALS), pieS({ id: 'b', center: ['75%', '50%'], radius: '25%' }, items([2, 4, 6, 8]))] })]);
  add('filtered.toggled-scatter', 'b switched off, then scatter symbols of id b (their pop-in stopped: they fade in)',
    [s(two()), act({ type: 'legendToggleSelect', name: 'sb' }),
      s(cart([{ type: 'scatter', id: 'b', universalTransition: true, data: [2, 4, 6, 8] }]))]);
  // ---- 3. A COMBINING HOST'S CHILDREN ----
  add('sub.hit', 'symbols combining into bars: every child is hit and names its host, at the host\'s place in the list',
    [s(sCart([scatS()])), s(gCart([gBars()]))], { hitAt: [16, 100, 250, 400], order: true });
  add('sub.hit-pie', 'a bar separating into slices of a group (one to many) and two combining back: the pointer on each',
    [s(gCart([gBars()])), s(sCart([scatS()])), s(gCart([gBars()]))], { hitAt: [100, 250], order: true });
  add('sub.leave', 'symbols combining into bars, and the legend switching the bars off 100 ms in: the host fades, its '
    + 'children are drawn (and go on morphing) until it is removed',
    [s(sCart([scatS()])), s(gCart([gBars()])), act({ type: 'legendToggleSelect', name: 'bb' }, 100)], { display: true });
  add('sub.leave-control', 'the same bars at rest when the legend switches them off',
    [s(sCart([scatS()])), s(gCart([gBars()])), act({ type: 'legendToggleSelect', name: 'bb' })], { display: true });
  // ---- 4. THE ENCODED GROUP DIMENSIONS, from the store ----
  const DS = [['p', 'v', 'grp'], [0.5, 2, 'A'], [1.5, 3, 'B'], [2.5, 4, 'A'], [0.5, 5, 'B'], [1.5, 6, 'A'], [2.5, 7, 'B']];
  const dsScat = (extra) => Object.assign({ type: 'scatter', id: 's', symbolSize: 16, universalTransition: { enabled: true, seriesKey: 'k' },
    encode: { x: 'p', y: 'v', itemGroupId: 'grp' } }, extra || {});
  add('enc.dataset', 'a dataset\'s symbols grouped by its grp column into bars A and B',
    [s(Object.assign(sCart([dsScat()]), { dataset: { source: DS } })), s(gCart([gBars()]))]);
  add('enc.dataset-back', 'and the bars back into the dataset\'s symbols (one to many by the group)',
    [s(gCart([gBars()])), s(Object.assign(sCart([dsScat()]), { dataset: { source: DS } }))]);
  const DSROW = [DS.map(r => r[0]), DS.map(r => r[1]), DS.map(r => r[2])];
  add('enc.dataset-renamed', 'the series\' own dimensions over the dataset\'s (a, b, c): grp names no dimension, so the '
    + 'groups are the ids and nothing pairs', [s(Object.assign(sCart([dsScat({ dimensions: ['a', 'b', 'c'],
      encode: { x: 0, y: 1, itemGroupId: 'grp' } })]), { dataset: { source: DS } })), s(gCart([gBars()]))]);
  add('enc.dataset-dims-empty', 'the series\' own dimensions an empty list: it is given (no header names), so grp names no '
    + 'dimension -- x and y take the first free ones, the groups are the ids and nothing pairs',
    [s(Object.assign(sCart([dsScat({ dimensions: [] })]), { dataset: { source: DS } })), s(gCart([gBars()]))]);
  add('enc.dataset-row', 'the same dataset laid out by row (seriesLayoutBy: \'row\')',
    [s(Object.assign(sCart([dsScat({ seriesLayoutBy: 'row' })]), { dataset: { source: DSROW } })), s(gCart([gBars()]))]);
  const DAYS = ['2017-02-01', '2017-02-04'];
  const DST = [['p', 'v', 'day'], [0.5, 2, DAYS[0]], [1.5, 3, DAYS[1]], [2.5, 4, DAYS[0]], [0.5, 5, DAYS[1]]];
  const msOf = d => String(+echarts.time.parse(d));
  const tBars = () => ({ type: 'bar', id: 'b', universalTransition: { enabled: true, seriesKey: 'k' },
    data: DAYS.map((d, i) => ({ name: msOf(d), value: 4 + i })) });
  add('enc.dataset-time', 'a dataset\'s time column as the group (parseDate: the group is the number of ms)',
    [s(Object.assign(sCart([dsScat({ encode: { x: 'p', y: 'v', itemGroupId: 'day' } })]),
      { dataset: { source: DST, dimensions: ['p', 'v', { name: 'day', type: 'time' }] } })),
      s({ color: PALETTE, xAxis: { type: 'category', data: DAYS.map(msOf) }, yAxis: { type: 'value', min: 0, max: 10 }, series: [tBars()] })]);
  add('enc.own-time', 'the series\' own data with a time dimension as the group',
    [s(sCart([{ type: 'scatter', id: 's', universalTransition: { enabled: true, seriesKey: 'k' },
      dimensions: ['p', 'v', { name: 'day', type: 'time' }], encode: { x: 'p', y: 'v', itemGroupId: 'day' },
      data: DST.slice(1) }])),
      s({ color: PALETTE, xAxis: { type: 'category', data: DAYS.map(msOf) }, yAxis: { type: 'value', min: 0, max: 10 }, series: [tBars()] })]);
  add('enc.own-ordinal-empty', 'an ordinal group column holding \'\' (no axis holds it: the store keeps the strings, no '
    + 'ordinalMeta) -- the x symbols combine, the empty ones find no bar',
    [s(sCart([{ type: 'scatter', id: 's', universalTransition: { enabled: true, seriesKey: 'k' },
      dimensions: ['p', 'v', { name: 'g', type: 'ordinal' }], encode: { x: 'p', y: 'v', itemGroupId: 'g' },
      data: [[0.5, 2, 'x'], [1.5, 3, ''], [2.5, 4, 'x'], [0.5, 5, '']] }])),
      s({ color: PALETTE, xAxis: { type: 'category', data: ['x', '1'] }, yAxis: { type: 'value', min: 0, max: 10 },
        series: [{ type: 'bar', id: 'b', universalTransition: { enabled: true, seriesKey: 'k' },
          data: [{ name: 'x', value: 5 }, { name: '1', value: 7 }] }] })]);
  add('enc.category-index', 'symbols on a category axis written by category index, grouped by that dimension: the group is '
    + 'the category\'s name (the axis\' ordinalMeta)',
    [s({ color: PALETTE, xAxis: { type: 'category', data: ['A', 'B'] }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', id: 's', symbolSize: 16, universalTransition: { enabled: true, seriesKey: 'k' },
        encode: { x: 0, y: 1, itemGroupId: 0 }, data: [[0, 2], [1, 3], [0, 4], [1, 5]] }] }),
      s(gCart([gBars()]))]);
  add('enc.partial-x', 'symbols on a category axis whose encode writes y alone: x takes the first dimension nobody holds '
    + '(the group dimension does not hold it), so the group is that coordinate -- the category\'s name',
    [s({ color: PALETTE, xAxis: { type: 'category', data: ['A', 'B'] }, yAxis: { type: 'value', min: 0, max: 10 },
      series: [{ type: 'scatter', id: 's', symbolSize: 16, universalTransition: { enabled: true, seriesKey: 'k' },
        encode: { y: 1, itemGroupId: 0 }, data: [[0, 2], [1, 3], [0, 4], [1, 5]] }] }),
      s(gCart([gBars()]))]);
  add('enc.dataset-child', 'a dataset\'s child group column drilling down from bars (childGroupId -> groupId)',
    [s(gCart([gBars({ data: [{ name: 'A', value: 6, childGroupId: 'A' }, { name: 'B', value: 9, childGroupId: 'B' }] })])),
      s(Object.assign(sCart([dsScat({ encode: { x: 'p', y: 'v', itemGroupId: 'grp' } })]), { dataset: { source: DS } }))]);
  // [spec 255] a group list gives the dimension its first entry names --
  // unless that entry reaches none or names it again further on
  // (getGroupIdDimension's otherDims.itemGroupId === 0)
  add('enc.list-first', 'itemGroupId [grp, p]: grp is the group, the symbols combine',
    [s(Object.assign(sCart([dsScat({ encode: { x: 'p', y: 'v', itemGroupId: ['grp', 'p'] } })]), { dataset: { source: DS } })),
      s(gCart([gBars()]))]);
  add('enc.list-gap', 'itemGroupId [nope, grp]: place 0 a gap -- no group dimension, the groups are the ids',
    [s(Object.assign(sCart([dsScat({ encode: { x: 'p', y: 'v', itemGroupId: ['nope', 'grp'] } })]), { dataset: { source: DS } })),
      s(gCart([gBars()]))]);
  add('enc.list-twice', 'itemGroupId [grp, grp]: named again, so not place 0 -- no group dimension',
    [s(Object.assign(sCart([dsScat({ encode: { x: 'p', y: 'v', itemGroupId: ['grp', 'grp'] } })]), { dataset: { source: DS } })),
      s(gCart([gBars()]))]);
  add('enc.own-list-gap', 'own data, itemGroupId [nope, g]: no group dimension',
    [s(sCart([{ type: 'scatter', id: 's', symbolSize: 16, universalTransition: { enabled: true, seriesKey: 'k' },
      dimensions: ['p', 'v', 'g'], encode: { x: 'p', y: 'v', itemGroupId: ['nope', 'g'] },
      data: DS.slice(1) }])), s(gCart([gBars()]))]);
  add('enc.own-list-twice', 'own data, itemGroupId [g, g]: named again -- no group dimension',
    [s(sCart([{ type: 'scatter', id: 's', symbolSize: 16, universalTransition: { enabled: true, seriesKey: 'k' },
      dimensions: ['p', 'v', 'g'], encode: { x: 'p', y: 'v', itemGroupId: ['g', 'g'] },
      data: DS.slice(1) }])), s(gCart([gBars()]))]);
  add('enc.own-list-first', 'own data, itemGroupId [g, v]: g',
    [s(sCart([{ type: 'scatter', id: 's', symbolSize: 16, universalTransition: { enabled: true, seriesKey: 'k' },
      dimensions: ['p', 'v', 'g'], encode: { x: 'p', y: 'v', itemGroupId: ['g', 'v'] },
      data: DS.slice(1) }])), s(gCart([gBars()]))]);
  // ---- 5. THE VIEW GROUPS ----
  const TREE = (names) => [{ name: 'r', children: names.map(n => ({ name: n, value: VALS[NAMES.indexOf(n)] })) }];
  // (the node colours written: the port's default tree ink is its skin's)
  const treeS = (names, extra) => Object.assign({ type: 'tree', id: 't', expandAndCollapse: false, symbol: 'circle', symbolSize: 10,
    itemStyle: { color: '#ffffff', borderColor: '#5070dd', borderWidth: 2 },
    universalTransition: { enabled: true, seriesKey: 'kk' }, data: TREE(names) }, extra || {});
  const kkBar = (names) => ({ type: 'bar', id: 'b', universalTransition: { enabled: true, seriesKey: 'kk' },
    data: names.map(n => ({ name: n, value: VALS[NAMES.indexOf(n)] })) });
  const Z15 = { roam: true, zoom: 1.5, center: ['40%', '50%'] };
  const Z12 = { roam: true, zoom: 1.2, center: ['40%', '50%'] };
  // (TreeView's render runs before the transition: updateProps of the view
  // group sets it to its new transform at once -- setToFinal -- and the old
  // nodes, still in the group leaving, are baked under it by removeEl)
  add('view.tree-bar.kept', 'a zoomed tree keeping A and D at another zoom while B and C go to bars of its seriesKey: the old '
    + 'nodes leave under the view group\'s NEW transform', [s(solo(treeS(NAMES, Z15))), s(cart([treeS(['A', 'D'], Z12), kkBar(['B', 'C'])]))]);
  add('view.tree-bar.kept.same', 'the same keeping the zoom (the group\'s transform does not change)',
    [s(solo(treeS(NAMES, Z15))), s(cart([treeS(['A', 'D'], Z15), kkBar(['B', 'C'])]))]);
  add('view.tree-bar.kept.inflight', '200 ms into a merge that zooms the tree\'s view (its group tweening), the tree keeps A and D '
    + 'at another zoom', [s(solo(treeS(NAMES))), s({ series: [Object.assign({ id: 't' }, Z15)] }, null, true),
      Object.assign(s(cart([treeS(['A', 'D'], Z12), kkBar(['B', 'C'])])), { after: 200 })]);
  add('view.tree-bar.kept.slide', '200 ms into a merge that gives the zoomed tree C and D (its nodes sliding to their new '
    + 'places), the tree keeps A and D while B and C go to bars: the old nodes leave from where they slide',
    [s(solo(treeS(['A', 'B', 'C'], Z15))), s(solo(treeS(NAMES, Z15)), null, true),
      Object.assign(s(cart([treeS(['A', 'D'], Z15), kkBar(['B', 'C'])])), { after: 200 })]);
  add('view.tree-bar', 'every node of a zoomed tree to bars (the tree\'s view disposed: its nodes stay in their groups)',
    [s(solo(treeS(NAMES, Z15))), s(cart([kkBar(NAMES)]))]);
  add('view.tree-bar.inflight', '200 ms into the zoom, every node to bars (the group where its tween is)',
    [s(solo(treeS(NAMES))), s({ series: [Object.assign({ id: 't' }, Z15)] }, null, true),
      Object.assign(s(cart([kkBar(NAMES)])), { after: 200 })]);
  const sankeyS = (names, extra) => Object.assign({ type: 'sankey', id: 'sk', universalTransition: { enabled: true, seriesKey: 'kk' },
    data: names.map(n => ({ name: n })),
    links: [{ source: 'A', target: 'C', value: 5 }, { source: 'B', target: 'D', value: 3 }, { source: 'A', target: 'D', value: 2 }]
      .filter(l => names.indexOf(l.source) >= 0 && names.indexOf(l.target) >= 0) }, extra || {});
  add('view.sankey-bar.kept', 'a sankey keeping A, C and D while B goes to a bar: the render emptied its main group, so the '
    + 'old node leaves with no group at all', [s(solo(sankeyS(NAMES))), s(cart([sankeyS(['A', 'C', 'D']), kkBar(['B'])]))]);
  add('view.sankey-bar', 'every sankey node to bars (the view disposed: the nodes stay in their groups)',
    [s(solo(sankeyS(NAMES))), s(cart([kkBar(NAMES)]))]);
  add('view.sankey-zoom-bar', 'a zoomed sankey (its view group scaled) into bars',
    [s(solo(sankeyS(NAMES, { roam: true, zoom: 1.5, center: ['40%', '50%'] }))), s(cart([kkBar(NAMES)]))]);
  add('view.sankey-zoom-bar.inflight', '200 ms into a merge that zooms the sankey (its view group tweening), every node to '
    + 'bars: the nodes start under the group where its tween is',
    [s(solo(sankeyS(NAMES, { roam: true }))), s({ series: [{ id: 'sk', zoom: 1.5, center: ['40%', '50%'] }] }, null, true),
      Object.assign(s(cart([kkBar(NAMES)])), { after: 200 })]);
  add('view.sankey-zoom-bar.inflight-plain', 'the same with the sankey\'s own transition off (its seriesKey kk still '
    + 'batches it): the merge morphs nothing, the disposed nodes start under the group where its tween is',
    [s(solo(sankeyS(NAMES, { roam: true, universalTransition: { enabled: false, seriesKey: 'kk' } }))),
      s({ series: [{ id: 'sk', zoom: 1.5, center: ['40%', '50%'] }] }, null, true),
      Object.assign(s(cart([kkBar(NAMES)])), { after: 200 })]);
  add('view.sankey-zoom-bar.kept', 'a zoomed sankey keeping A, C and D at another zoom while B goes to a bar',
    [s(solo(sankeyS(NAMES, { roam: true, zoom: 1.5, center: ['40%', '50%'] }))),
      s(cart([sankeyS(['A', 'C', 'D'], { roam: true, zoom: 1.2, center: ['40%', '50%'] }), kkBar(['B'])]))]);
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
  const tweens = (c, key) => itemsOf(c).filter(e => Array.isArray(e.style[key]));
  const fades = c => itemsOf(c).filter(e => Array.isArray(e.style.opacity) && e.style.opacity[0] === hex(0));
  // 1. the style track
  for (const k of ['shadowBlur', 'shadowOffsetX', 'shadowOffsetY', 'shadowColor']) {
    must(tweens(byId('style.shadow-pie'), k).length === 4, 'style.shadow-pie: ' + k + ' does not tween');
    must(tweens(byId('style.shadow-shadow'), k).length === 4, 'style.shadow-shadow: ' + k + ' does not tween');
    must(tweens(byId('style.pie-shadow'), k).length === 0, 'style.pie-shadow: ' + k + ' tweens');
  }
  must(itemsOf(byId('style.shadow-pie')).every(e => e.style.shadowColor[e.style.shadowColor.length - 1] === 'rgba(0,0,0,1)'),
    'style.shadow-pie: the shadow does not end at the prototype\'s #000');
  for (const id of ['style.grad-grad', 'style.grad3-grad2', 'style.grad2-grad3', 'style.radial-radial', 'style.alpha-grad', 'style.same-bar']) {
    must(tweens(byId(id), 'fill').length === 4, id + ': the gradient does not tween');
  }
  for (const id of ['style.radial-linear', 'style.grad-col', 'style.col-grad']) {
    must(tweens(byId(id), 'fill').length === 0, id + ': the fill tweens');
    must(morphs(byId(id)).length === 4, id + ': not four morphs');
  }
  must(itemsOf(byId('style.grad3-grad2')).every(e => e.style.fill[0].stops.length === 3), 'style.grad3-grad2: not three stops');
  must(tweens(byId('style.opacity-custom-bar'), 'fillOpacity').length === 4
    && tweens(byId('style.opacity-custom-bar'), 'strokeOpacity').length === 4, 'style.opacity-custom-bar: no tween');
  must(itemsOf(byId('style.bar-opacity-custom')).every(e => e.style.fillOpacity === hex(0.4) && e.style.strokeOpacity === hex(0.6)),
    'style.bar-opacity-custom: not 0.4 / 0.6 throughout');
  must(morphs(byId('style.same-bar')).length === 0, 'style.same-bar: a morph');
  must(tweens(byId('style.dash-pie'), 'lineDashOffset').length === 4, 'style.dash-pie: lineDashOffset does not tween');
  must(tweens(byId('style.miter-pie'), 'miterLimit').length === 4, 'style.miter-pie: miterLimit does not tween');
  must(tweens(byId('style.same-bar'), 'shadowBlur').length === 4, 'style.same-bar: the shadow does not tween');
  must(combs(byId('style.combine-shadow')).length === 2, 'style.combine-shadow: not two combining');
  must(combs(byId('style.combine-shadow')).every(e => e.pieces.every(p => Array.isArray(p.style.shadowBlur))),
    'style.combine-shadow: a child\'s shadow does not tween');
  must(combs(byId('style.combine-grad')).length === 2
    && combs(byId('style.combine-grad')).every(e => e.pieces.every(p => Array.isArray(p.style.fill))),
    'style.combine-grad: a child\'s gradient does not tween');
  // 2. the switched-off series
  for (const id of ['filtered.toggled-pie', 'filtered.selected-pie', 'filtered.toggled-scatter', 'filtered.toggled-pie-marked']) {
    must(byId(id).oldGroups.find(g => g.id === 'b').filtered, id + ': b not filtered');
    must(morphs(byId(id)).length === 0 && fades(byId(id)).length === 4, id + ': not four fading in');
  }
  must(fades(byId('filtered.kept-a')).length === 4, 'filtered.kept-a: not four fading in');
  must(fades(byId('filtered.merge-marked')).length === 4 && morphs(byId('filtered.merge-marked')).length === 0,
    'filtered.merge-marked: not four fading in');
  must(morphs(byId('filtered.shown-pie')).length === 4, 'filtered.shown-pie: not four morphs');
  // 3. the children
  for (const id of ['sub.hit', 'sub.hit-pie']) {
    const c = byId(id);
    const probes = [].concat(...c.hits.map(h => h.probes));
    must(probes.length >= 8, id + ': ' + probes.length + ' probes');
    must(probes.filter(p => p.child).length >= 8 && probes.every(p => !p.child || p.dataIndex !== null),
      id + ': a child hit names no datum');
  }
  must(byId('sub.hit').hits.every(h => h.probes.some(p => p.child && p.of && /#[1-9]/.test(p.of))),
    'sub.hit: no child past the first is hit');
  {
    const d = byId('sub.leave').display;
    must(d[0].filter(x => x.child).length === 6, 'sub.leave: not six children drawn at first');
    must(d[d.length - 1].filter(x => x.child).length === 0, 'sub.leave: children drawn at the end');
    const c = byId('sub.leave-control').display;
    must(c.every(x => x.every(y => !y.child)), 'sub.leave-control: a child');
  }
  // 4. the encoded groups
  const oldG = (id, sid) => byId(id).oldGroups.find(g => g.id === sid).groups.join(',');
  const newG = (id, sid) => byId(id).newGroups.find(g => g.id === sid).groups.join(',');
  must(oldG('enc.dataset', 's') === 'A,B,A,B,A,B', 'enc.dataset: ' + oldG('enc.dataset', 's'));
  must(oldG('enc.dataset-row', 's') === 'A,B,A,B,A,B', 'enc.dataset-row: ' + oldG('enc.dataset-row', 's'));
  must(newG('enc.dataset-back', 's') === 'A,B,A,B,A,B', 'enc.dataset-back: ' + newG('enc.dataset-back', 's'));
  must(oldG('enc.dataset-time', 's') === [DAYSMS[0], DAYSMS[1], DAYSMS[0], DAYSMS[1]].join(','), 'enc.dataset-time: ' + oldG('enc.dataset-time', 's'));
  must(oldG('enc.own-time', 's') === oldG('enc.dataset-time', 's'), 'enc.own-time: ' + oldG('enc.own-time', 's'));
  // (an ordinal dimension no axis holds keeps its strings: no ordinalMeta, '' stays '')
  must(oldG('enc.own-ordinal-empty', 's') === 'x,,x,', 'enc.own-ordinal-empty: ' + oldG('enc.own-ordinal-empty', 's'));
  must(combs(byId('enc.own-ordinal-empty')).length === 1, 'enc.own-ordinal-empty: not one combining');
  must(oldG('enc.category-index', 's') === 'A,B,A,B', 'enc.category-index: ' + oldG('enc.category-index', 's'));
  must(oldG('enc.partial-x', 's') === 'A,B,A,B', 'enc.partial-x: ' + oldG('enc.partial-x', 's'));
  must(combs(byId('enc.partial-x')).length === 2, 'enc.partial-x: not two combining');
  for (const id of ['enc.dataset', 'enc.dataset-row', 'enc.dataset-time', 'enc.own-time', 'enc.category-index']) {
    must(combs(byId(id)).length === 2, id + ': not two combining');
  }
  must(morphs(byId('enc.dataset-back')).length === 6, 'enc.dataset-back: not six morphs');
  must(combs(byId('enc.dataset-renamed')).length === 0 && morphs(byId('enc.dataset-renamed')).length === 0,
    'enc.dataset-renamed: something pairs');
  must(morphs(byId('enc.dataset-child')).length === 6, 'enc.dataset-child: not six morphs');
  // 5. the view groups
  for (const id of ['view.tree-bar.kept', 'view.tree-bar.kept.same', 'view.tree-bar.kept.inflight', 'view.tree-bar.kept.slide',
    'view.sankey-bar.kept',
    'view.sankey-zoom-bar.kept']) {
    must(morphs(byId(id)).filter(e => e.seriesType === 'bar').length >= 1, id + ': no bar morphs');
  }
  for (const id of ['view.tree-bar', 'view.tree-bar.inflight', 'view.sankey-bar', 'view.sankey-zoom-bar',
    'view.sankey-zoom-bar.inflight', 'view.sankey-zoom-bar.inflight-plain']) {
    must(morphs(byId(id)).length === 4, id + ': not four morphs');
  }
  {
    // the kept tree's old nodes start under its new transform: the same in
    // flight as at rest, not the same as where the zoom is kept
    const st = c => morphs(byId(c)).filter(e => e.seriesType === 'bar').map(e => e.d[0].join(','));
    const a = st('view.tree-bar.kept.inflight');
    const b = st('view.tree-bar.kept');
    const c = st('view.tree-bar.kept.same');
    must(a.length === 2 && b.length === 2 && c.length === 2 && a.every((x, i) => x === b[i]) && b.every((x, i) => x !== c[i]),
      'view.tree-bar.kept: the old nodes do not start under the new transform');
    // the disposed view's at rest are not where its tween is
    const d = st('view.tree-bar');
    const e = st('view.tree-bar.inflight');
    must(d.length === 4 && e.length === 4 && d.every((x, i) => x !== e[i]), 'view.tree-bar.inflight: the nodes start at rest');
  }
}
const DAYSMS = ['2017-02-01', '2017-02-04'].map(d => String(+echarts.time.parse(d)));

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const charts = chartCases().map(c => Object.assign(c, runCase(c)));
  guards(charts);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'R6-C: steps of setOption or dispatchAction (the first at T0; a next one after the previous ran out, T + 10000, '
      + 'or `after` ms into it; notMerge unless `merge`), recorded at the last T + samples. Each element: an item path of a '
      + 'new series (id s<series>/<dataIndex>/<path>) or another path of its view (s<series>/x/<k>); morph[i] = __morphT >= 0 '
      + 'and not combining, d[i] the replaced buildPath\'s PathProxy data (codes M1 L2 C3 Q4 A5 Z6 R7); comb[i] = '
      + '__isCombineMorphing, pieces = its childrenRef() in order; style = fill (a colour, or a gradient: type, x / y / x2 / y2 '
      + 'or r, global, stops [offset, colour]), stroke, lineWidth, opacity, shadowBlur, shadowOffsetX, shadowOffsetY, '
      + 'shadowColor, fillOpacity, strokeOpacity, lineDashOffset, miterLimit (the prototype\'s where not own) -- a key the same at every sample written '
      + 'once. hits: at the samples a case names, findHover at the middle of each combining child\'s box, rounded (where the child '
      + 'contains it): whether the child is the target, the ecData its parents reach. orders: the display list\'s item paths '
      + 'and children (<id>#<k>) in order. display: every path drawn under a series view (digest, opacity, a child or not). '
      + 'oldGroups / newGroups: getGroupId and the child group per item of every series (the dist\'s SeriesData). oldRest / '
      + 'newRest: every item path at rest. Every number is the hex of its double.',
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
