// D5 UT3 (batch 138): universalTransition, the direction -- childGroupId and the
// parent / child sniffing of transitionBetween: drilling down (the new items'
// groupId among the old items' childGroupIds: the old side keyed by its
// childGroupId) and back up (the new items' childGroupId among the old items'
// groupIds: the new side keyed by its childGroupId), the groups read off the
// encoded itemGroupId / itemChildGroupId dimensions or the raw items, the
// gallery's bar-multi-drilldown level by level, and the treemap <-> sunburst
// transition of the gallery's treemap-sunburst-transition.
//
// From the real ECharts 6.1 dist: a sequence of setOption calls (the first at
// T0; each next one after the previous has run out -- T + 10000 -- or `after`
// ms into it; notMerge unless the step says merge), recorded at the last one's
// T + each sample: every item element of the new series -- whether it is
// morphing, the morph path its replaced buildPath draws, its style, its
// transform and shape keys -- and, while it is combining
// (__isCombineMorphing), every child it draws in its place (childrenRef); and
// every other path of the new series' views (with the item it belongs to,
// where it is in an item's group). Each case also writes the
// direction transitionBetween chose for each of its batches (read by running
// the dist's own sniffing on the flattened items) and the groups it read.
// The clock harness is animation.js' (the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames).
// Run: node tools/advchart-oracle/universal-transition3.js
//   -> tests/fixtures/advchart-universal-transition3.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-universal-transition3.json');
// the gallery's treemap-sunburst-transition reads its data from the examples repository
const EXAMPLES_DATA = process.env.ECHARTS_EXAMPLES_DATA || 'D:/Projects/echarts-examples/public/data/asset/data';

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
const FNS = {};
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
// the dist's own code: getGroupId and flattenDataDiffItems, cut out of the
// bundle -- the groups each side of a transition reads
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
const FLAT = new Function('each', 'warn', 'DATA_COUNT_THRESHOLD',
  slice('function getDimension(data, visualDimension) {', '    function fadeInElement(newEl, newSeries, newIndex) {')
  + '\nreturn { flattenDataDiffItems: flattenDataDiffItems };')(echarts.util.each, () => {}, 1e4);

// THE DIRECTION transitionBetween picks, on the dist's flattened items (the
// rule of universalTransition.ts transcribed: 0 none, 1 parent -> child, 2
// child -> parent)
function directionOf(oldItems, newItems) {
  const oldGroupIds = new Map();
  const oldChildGroupIds = new Map();
  for (const item of oldItems) {
    if (item.groupId) oldGroupIds.set(item.groupId, true);
    if (item.childGroupId) oldChildGroupIds.set(item.childGroupId, true);
  }
  for (const it of newItems) {
    if (oldChildGroupIds.get(it.groupId)) return 1;
    if (it.childGroupId && oldGroupIds.get(it.childGroupId)) return 2;
  }
  return 0;
}
const sideOf = model => {
  const out = [];
  model.eachSeries(s => out.push({ data: s.getData(), dataGroupId: s.get('dataGroupId'), divide: undefined }));
  return out;
};
const groupsOf = items => items.map(it => [it.groupId === undefined ? null : String(it.groupId),
  it.childGroupId === undefined ? null : String(it.childGroupId)]);

function builtData(el) {
  const pp = new PathProxy(false);
  pp.beginPath();
  el.buildPath(pp, el.shape, false);
  return Array.from(pp.data.slice(0, pp.len()));
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
      // the item a path of a group-shaped item element belongs to (a
      // treemap leaf's background)
      const owner = new Map();
      data.each(i => {
        const el = data.getItemGraphicEl(i);
        if (el && el.isGroup) el.traverse(e => { if (e instanceof Path) owner.set(e, i); });
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
    if (r.item) o.dataIndex = r.dataIndex;
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
    let oldItems = null;
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
      if (i === c.steps.length - 1 && i > 0) oldItems = FLAT.flattenDataDiffItems(sideOf(chart.getModel()));
      NOW = t;
      // a step may dispatch an action instead (milestone D5-D8)
      if (st.action) chart.dispatchAction(JSON.parse(JSON.stringify(st.action)));
      else chart.setOption(materialize(st.option), i > 0 && !st.merge);
    });
    const newItems = FLAT.flattenDataDiffItems(sideOf(chart.getModel()));
    const tl = record(chart, t, c.samples, c.digest);
    const resolved = [];
    chart.getModel().eachSeries(s => resolved.push({ seriesIndex: s.seriesIndex, type: s.subType, id: s.id.replace(/\0/g, '<0>'),
      ut: !!s.isUniversalTransitionEnabled(), animation: !!s.isAnimationEnabled(), count: s.getData().count() }));
    const out = { resolved, clips: tl.clips, elements: tl.elements };
    if (oldItems) {
      out.direction = directionOf(oldItems, newItems);
      if (!c.digest) {
        out.oldGroups = groupsOf(oldItems);
        out.newGroups = groupsOf(newItems);
      }
    }
    return out;
  }
  finally {
    chart.dispose();
  }
}

// the default palette, written out so the port (whose palette is its skin's)
// paints the same colours
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];

// ---------- the gallery's bar-multi-drilldown, every level ----------
const LEVELS = [
  [['Animals', 3, 'things', 'animals'], ['Fruits', 3, 'things', 'fruits'], ['Cars', 2, 'things', 'cars']],
  [['Dogs', 3, 'animals', 'dogs'], ['Cats', 4, 'animals', 'cats'], ['Birds', 3, 'animals', 'birds']],
  [['Pomes', 3, 'fruits', 'pomes'], ['Berries', 4, 'fruits', 'berries'], ['Citrus', 9, 'fruits', 'citrus']],
  [['SUV', 5, 'cars', 'suv'], ['Sports', 3, 'cars', 'sports']],
  [['Corgi', 5, 'dogs'], ['Bulldog', 6, 'dogs'], ['Shiba Inu', 7, 'dogs']],
  [['American Shorthair', 2, 'cats'], ['British Shorthair', 9, 'cats'], ['Bengal', 2, 'cats'], ['Birman', 2, 'cats']],
  [['Goose', 1, 'birds'], ['Owl', 2, 'birds'], ['Eagle', 8, 'birds']],
  [['Apple', 9, 'pomes'], ['Pear', 2, 'pomes'], ['Kiwi', 1, 'pomes']],
  [['Blackberries', 7, 'berries'], ['Cranberries', 2, 'berries'], ['Strawberries', 9, 'berries'], ['Grapes', 4, 'berries']],
  [['Oranges', 3, 'citrus'], ['Grapefruits', 7, 'citrus'], ['Tangerines', 8, 'citrus'], ['Lemons', 7, 'citrus'],
    ['Limes', 3, 'citrus'], ['Kumquats', 2, 'citrus'], ['Citrons', 3, 'citrus'], ['Tengelows', 3, 'citrus'], ['Uglifruit', 1, 'citrus']],
  [['Mazda CX-30', 7, 'suv'], ['BMW X2', 7, 'suv'], ['Ford Bronco Sport', 2, 'suv'], ['Toyota RAV4', 9, 'suv'], ['Porsche Macan', 4, 'suv']],
  [['Porsche 718 Cayman', 2, 'sports'], ['Porsche 911 Turbo', 2, 'sports'], ['Ferrari F8', 4, 'sports']],
];
const LEVEL = {};
for (const data of LEVELS) {
  LEVEL[data[0][2]] = {
    color: PALETTE, xAxis: { type: 'category' }, yAxis: { minInterval: 1 }, animationDurationUpdate: 500,
    series: { type: 'bar', dimensions: ['x', 'y', 'groupId', 'childGroupId'],
      encode: { x: 'x', y: 'y', itemGroupId: 'groupId', itemChildGroupId: 'childGroupId' },
      data, universalTransition: { enabled: true, divideShape: 'clone' } },
  };
}

// ---------- the gallery's treemap-sunburst-transition, its own data ----------
function packageSize() {
  const file = path.join(EXAMPLES_DATA, 'echarts-package-size.json');
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  const treemapOption = { color: PALETTE, series: [{ type: 'treemap', id: 'echarts-package-size', animationDurationUpdate: 1000,
    roam: false, nodeClick: false, data: data.children, universalTransition: true, label: { show: true },
    breadcrumb: { show: false } }] };
  const sunburstOption = { color: PALETTE, series: [{ type: 'sunburst', id: 'echarts-package-size', radius: ['20%', '90%'],
    animationDurationUpdate: 1000, nodeClick: false, data: data.children, universalTransition: true,
    itemStyle: { borderWidth: 1, borderColor: 'rgba(255,255,255,.5)' }, label: { show: false } }] };
  return { treemapOption, sunburstOption };
}

const cart = (series, cats, extra) => Object.assign({ color: PALETTE, xAxis: Object.assign({ type: 'category' }, cats ? { data: cats } : {}),
  yAxis: { type: 'value' }, series }, extra || {});
const solo = (series, extra) => Object.assign({ color: PALETTE, series: [series] }, extra || {});
const barS = (extra, data) => Object.assign({ type: 'bar', universalTransition: true, data }, extra || {});
const pieS = (extra, data) => Object.assign({ type: 'pie', universalTransition: true, radius: '60%', label: { show: false },
  data }, extra || {});
const it = (name, value, groupId, childGroupId) => {
  const o = { name, value };
  if (groupId !== undefined) o.groupId = groupId;
  if (childGroupId !== undefined) o.childGroupId = childGroupId;
  return o;
};
const names = data => data.map(d => d.name);

function chartCases() {
  const list = [];
  const add = (id, note, steps, opts) => list.push(Object.assign({ id, note, steps, samples: SAMPLES, digest: false }, opts || {}));
  const s = (option, after, merge) => ({ option, after: after == null ? null : after, merge: !!merge });
  const L = id => LEVEL[id];
  // ---- the gallery's levels, merged as the example does ----
  add('multi.down', 'bar-multi-drilldown, things -> animals: the new groupId "animals" is an old childGroupId (parent -> '
    + 'child, the old side keyed by its childGroupId): Animals separates into three bars (clone), Fruits and Cars leave',
    [s(L('things')), s(L('animals'), null, true)]);
  add('multi.down2', 'two levels down, things -> animals -> dogs: Dogs separates into three',
    [s(L('things')), s(L('animals'), null, true), s(L('dogs'), null, true)]);
  add('multi.up', 'things -> animals -> things: the new childGroupId "animals" is an old groupId (child -> parent, the new '
    + 'side keyed by its childGroupId): the three bars combine into Animals, Fruits and Cars enter',
    [s(L('things')), s(L('animals'), null, true), s(L('things'), null, true)]);
  add('multi.up2', 'two levels down and back up, the last step animals -> things',
    [s(L('things')), s(L('animals'), null, true), s(L('dogs'), null, true), s(L('animals'), null, true),
      s(L('things'), null, true)]);
  add('multi.up.leaf', 'things -> fruits -> citrus -> fruits: nine leaves (childGroupId "NaN": the encoded column, never '
    + 'written, is a float one) combine into Citrus', [s(L('things')), s(L('fruits'), null, true), s(L('citrus'), null, true),
    s(L('fruits'), null, true)]);
  add('multi.down.notmerge', 'things -> cars with notMerge (a new view): SUV and Sports separate out of Cars',
    [s(L('things')), s(L('cars'))]);
  add('multi.siblings.leaf', 'dogs -> cats: leaves with no children both sides, no common group -- no transition',
    [s(L('things')), s(L('animals'), null, true), s(L('dogs'), null, true), s(L('cats'), null, true)]);
  add('multi.siblings.mid', 'animals -> fruits: no direction, the groups differ -- no transition',
    [s(L('things')), s(L('animals'), null, true), s(L('fruits'), null, true)]);
  // ---- interrupted ----
  add('multi.down.up.inflight', '200 ms into things -> animals, things again: the separating bars combine back',
    [s(L('things')), s(L('animals'), null, true), s(L('things'), 200, true)]);
  add('multi.up.down.inflight', '200 ms into animals -> things, animals again: the combining Animals separates from its '
    + 'children', [s(L('things')), s(L('animals'), null, true), s(L('things'), null, true), s(L('animals'), 200, true)]);
  add('multi.down.down.inflight', '200 ms into things -> animals, dogs: Dogs separates from where its morph was',
    [s(L('things')), s(L('animals'), null, true), s(L('dogs'), 200, true)]);
  // ---- raw items' childGroupId, across types ----
  const top = [it('Animals', 6, 'things', 'animals'), it('Fruits', 4, 'things', 'fruits'), it('Cars', 3, 'things', 'cars')];
  const kids = [it('Dogs', 3, 'animals'), it('Cats', 2, 'animals'), it('Pomes', 4, 'fruits'), it('Vans', 1, 'vans')];
  add('item.bar-pie.down', 'raw items: bars with childGroupIds -> slices grouped by them: Animals splits into two sectors '
    + '(split), Fruits one to one, Cars leaves, Vans enters', [s(cart([barS({ id: 'k' }, top)], names(top))),
    s(solo(pieS({ id: 'k' }, kids)))]);
  add('item.pie-bar.up', 'and back up: Dogs and Cats combine into the Animals bar, Pomes one to one into Fruits',
    [s(solo(pieS({ id: 'k' }, kids))), s(cart([barS({ id: 'k' }, top)], names(top)))]);
  add('item.nomatch', 'a childGroupId that matches nothing: no direction, the groupIds pair the items (g separates in two, '
    + 'h one to one)', [s(cart([barS({ id: 'k' }, [it('A', 5, 'g', 'zzz'), it('B', 3, 'h', 'yyy')])], ['A', 'B'])),
    s(cart([barS({ id: 'k' }, [it('a1', 2, 'g'), it('a2', 3, 'g'), it('b1', 3, 'h')])], ['a1', 'a2', 'b1']))]);
  add('item.undefined', 'child -> parent where a new item has no childGroupId: its key is "undefined", which pairs it with '
    + 'the old item whose groupId is the string "undefined"', [
    s(cart([barS({ id: 'k' }, [it('d1', 2, 'dogs'), it('d2', 3, 'dogs'), it('u', 4, 'undefined')])], ['d1', 'd2', 'u'])),
    s(cart([barS({ id: 'k' }, [it('Dogs', 5, 'animals', 'dogs'), it('Lone', 1)])], ['Dogs', 'Lone']))]);
  const bothOld = [it('P', 4, 'top', 'kids'), it('Q', 3, 'mid')];
  add('item.both.c2p', 'both directions present, the child -> parent item first: it wins (Q into n0)', [
    s(cart([barS({ id: 'k' }, bothOld)], ['P', 'Q'])),
    s(cart([barS({ id: 'k' }, [it('n0', 2, 'zz', 'mid'), it('n1', 5, 'kids')])], ['n0', 'n1']))]);
  add('item.both.p2c', 'both directions present, the parent -> child item first: it wins (P into n1)', [
    s(cart([barS({ id: 'k' }, bothOld)], ['P', 'Q'])),
    s(cart([barS({ id: 'k' }, [it('n1', 5, 'kids'), it('n0', 2, 'zz', 'mid')])], ['n1', 'n0']))]);
  add('item.both.sameitem', 'one new item both ways: parent -> child is asked first', [
    s(cart([barS({ id: 'k' }, bothOld)], ['P', 'Q'])),
    s(cart([barS({ id: 'k' }, [it('n2', 5, 'kids', 'mid'), it('n3', 2, 'kids')])], ['n2', 'n3']))]);
  // ---- with a list seriesKey ----
  const LIST = ['a', 'b'];
  const ab = cart([
    barS({ id: 'a', universalTransition: { enabled: true } }, [it('A', 5, 'ra', 'ka'), it('B', 4, 'ra', 'kc')]),
    barS({ id: 'b', universalTransition: { enabled: true } }, [it('A', 3, 'rb', 'kb'), it('B', 2, 'rb', 'kd')]),
  ], ['A', 'B']);
  const merged = cart([barS({ id: 'n', universalTransition: { enabled: true, seriesKey: LIST.slice() } },
    [it('a1', 2, 'ka'), it('a2', 3, 'ka'), it('b1', 1, 'kb'), it('b2', 2, 'kb'), it('b3', 4, 'kb')])],
  ['a1', 'a2', 'b1', 'b2', 'b3']);
  add('list.down', 'two bar series a and b with childGroupIds -> one series whose seriesKey lists them (many old series '
    + 'in one batch): parent -> child, A of a separates into two, A of b into three', [s(ab), s(merged)]);
  const upA = cart([
    barS({ id: 'a', universalTransition: { enabled: true } }, [it('A', 5, 'ra', 'ka'), it('B', 4, 'ra', 'kc')]),
    barS({ id: 'b', universalTransition: { enabled: true } }, [it('A', 3, 'rb', 'kb'), it('B', 2, 'rb', 'kd')]),
  ], ['A', 'B']);
  add('list.up', 'and back up: the list series splits into a and b (one batch, oldDataMapForSplit), child -> parent -- '
    + 'the bars grouped ka combine into A of a, kb into A of b', [s(merged), s(upA)]);
  // ---- the encoded dimensions, numbers ----
  const numDims = { dimensions: ['x', 'y', 'g', 'c'], encode: { x: 'x', y: 'y', itemGroupId: 'g', itemChildGroupId: 'c' } };
  add('encode.numeric', 'numeric group columns (float dimensions): the groups are the numbers\' strings, a missing child '
    + 'is "NaN"', [
    s(cart([barS(Object.assign({ id: 'k' }, numDims), [['A', 3, 0, 1], ['B', 4, 0, 2]])], null)),
    s(cart([barS(Object.assign({ id: 'k' }, numDims), [['a1', 1, 1], ['a2', 2, 1], ['b1', 5, 2]])], null))]);
  add('encode.numeric.up', 'and back up', [
    s(cart([barS(Object.assign({ id: 'k' }, numDims), [['a1', 1, 1], ['a2', 2, 1], ['b1', 5, 2]])], null)),
    s(cart([barS(Object.assign({ id: 'k' }, numDims), [['A', 3, 0, 1], ['B', 4, 0, 2]])], null))]);
  // a text column whose first value is '' (ordinal: '' is text), a '-' that
  // tells nothing, a declared int column (Int32Array: 1.7 is 1, -0.5 is 0)
  const mixedOld = { dimensions: ['x', 'y', { name: 'g' }, { name: 'c', type: 'int' }],
    encode: { x: 'x', y: 'y', itemGroupId: 'g', itemChildGroupId: 'c' } };
  const mixedNew = { dimensions: ['x', 'y', 'g'], encode: { x: 'x', y: 'y', itemGroupId: 'g' } };
  add('encode.mixed', 'an ordinal group column led by "", a declared int child column (1.7 -> "1", -0.5 -> "0"): '
    + 'A separates into a and b, B into d, C into c', [
    s(cart([barS(Object.assign({ id: 'k' }, mixedOld), [['A', 3, '', '1.7'], ['B', 4, '-', 2.2], ['C', 2, '7', -0.5]])], null)),
    s(cart([barS(Object.assign({ id: 'k' }, mixedNew), [['a', 1, 1], ['b', 2, 1], ['c', 3, 0], ['d', 4, 2]])], null))]);
  // ---- the gallery's treemap <-> sunburst ----
  const tm = packageSize();
  add('tm-sb', 'treemap-sunburst-transition: the treemap becomes the sunburst (the same tree, every id the same: one to '
    + 'one, rects into sectors)', [s(tm.treemapOption), s(tm.sunburstOption)], { samples: SAMPLES_BIG, digest: true });
  add('sb-tm', 'and the sunburst becomes the treemap', [s(tm.sunburstOption), s(tm.treemapOption)],
    { samples: SAMPLES_BIG, digest: true });
  add('tm-sb-tm.inflight', '300 ms into tm-sb, the treemap again: each rect morphs from the frame its sector was drawing',
    [s(tm.treemapOption), s(tm.sunburstOption), s(tm.treemapOption, 300)], { samples: SAMPLES_BIG, digest: true });
  // ---- milestone D5-D8: a drilled sunburst, a treemap into itself ----
  const small = () => [{ id: 'a', name: 'a', children: [{ id: 'a1', name: 'a1', value: 3 }, { id: 'a2', name: 'a2', value: 5 }] },
    { id: 'b', name: 'b', value: 4 }, { id: 'c', name: 'c', children: [{ id: 'c1', name: 'c1', value: 2 }] }];
  const sbSmall = { color: PALETTE, series: [{ type: 'sunburst', id: 'pk', radius: ['20%', '90%'], animationDurationUpdate: 1000,
    nodeClick: false, universalTransition: true, label: { show: false }, data: small() }] };
  const tmSmall = pal => ({ color: pal, series: [{ type: 'treemap', id: 'pk', animationDurationUpdate: 1000, roam: false,
    nodeClick: false, universalTransition: true, label: { show: false }, breadcrumb: { show: false }, data: small() }] });
  add('sb.drilled-tm', 'a sunburst drilled to a (sunburstRootToNode: the return circle is the virtual root\'s piece, data index 0) '
    + 'becomes a treemap of the same tree', [s(sbSmall), { action: { type: 'sunburstRootToNode', targetNode: 'a' }, after: null,
      merge: false }, s(tmSmall(PALETTE))], { digest: true });
  add('tm-tm.recolor', 'the same treemap with a new palette: one view, its own update -- a treemap keeps no old style, so the '
    + 'transition animates no style', [s(tmSmall(PALETTE)), s(tmSmall(PALETTE.slice().reverse()))], { digest: true });
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
  const dir = (id, want) => must(byId(id).direction === want, id + ': direction ' + byId(id).direction + ', not ' + want);
  for (const id of ['multi.down', 'multi.down2', 'multi.down.notmerge', 'item.bar-pie.down', 'item.both.p2c',
    'item.both.sameitem', 'list.down', 'encode.numeric', 'encode.mixed', 'multi.down.down.inflight', 'multi.up.down.inflight']) dir(id, 1);
  for (const id of ['multi.up', 'multi.up2', 'multi.up.leaf', 'item.pie-bar.up', 'item.undefined', 'item.both.c2p',
    'list.up', 'encode.numeric.up', 'multi.down.up.inflight']) dir(id, 2);
  for (const id of ['multi.siblings.leaf', 'multi.siblings.mid', 'item.nomatch', 'tm-sb', 'sb-tm', 'tm-sb-tm.inflight']) dir(id, 0);
  must(morphs(byId('multi.down')).length === 3 && combs(byId('multi.down')).length === 0, 'multi.down: not three morphs');
  must(morphs(byId('multi.down2')).length === 3, 'multi.down2: not three morphs');
  must(combs(byId('multi.up')).length === 1 && combs(byId('multi.up'))[0].pieces.length === 3, 'multi.up: not one of three');
  must(combs(byId('multi.up2')).length === 1 && combs(byId('multi.up2'))[0].pieces.length === 3, 'multi.up2: not one of three');
  must(combs(byId('multi.up.leaf')).length === 1 && combs(byId('multi.up.leaf'))[0].pieces.length === 9,
    'multi.up.leaf: not one of nine');
  must(morphs(byId('multi.down.notmerge')).length === 2, 'multi.down.notmerge: not two morphs');
  for (const id of ['multi.siblings.leaf', 'multi.siblings.mid']) {
    must(morphs(byId(id)).length === 0 && combs(byId(id)).length === 0, id + ': transitions');
  }
  must(combs(byId('multi.down.up.inflight')).length === 1, 'multi.down.up.inflight: not combining');
  must(morphs(byId('multi.up.down.inflight')).length === 3, 'multi.up.down.inflight: not three morphs');
  must(morphs(byId('multi.down.down.inflight')).length === 3, 'multi.down.down.inflight: not three morphs');
  {
    const c = byId('item.bar-pie.down');
    must(morphs(c).length === 3, 'item.bar-pie.down: not three morphs but ' + morphs(c).length);
    must(!items(c).find(e => e.dataIndex === 3).morph, 'item.bar-pie.down: Vans morphs');
    must(combs(byId('item.pie-bar.up')).length === 1 && morphs(byId('item.pie-bar.up')).length === 1,
      'item.pie-bar.up: not one combine and one morph');
  }
  must(morphs(byId('item.nomatch')).length === 3, 'item.nomatch: not three morphs');
  {
    const c = byId('item.undefined');
    must(combs(c).length === 1 && items(c).find(e => e.dataIndex === 1).morph, 'item.undefined: Lone does not morph from u');
  }
  {
    const c2p = byId('item.both.c2p');
    must(items(c2p).find(e => e.dataIndex === 0).morph && !items(c2p).find(e => e.dataIndex === 1).morph,
      'item.both.c2p: not n0 alone');
    const p2c = byId('item.both.p2c');
    must(items(p2c).find(e => e.dataIndex === 0).morph && !items(p2c).find(e => e.dataIndex === 1).morph,
      'item.both.p2c: not n1 alone');
  }
  must(morphs(byId('list.down')).length === 5, 'list.down: not five morphs');
  must(combs(byId('list.up')).length === 2, 'list.up: not two combining');
  must(morphs(byId('encode.numeric')).length === 3, 'encode.numeric: not three morphs');
  must(byId('encode.numeric').oldGroups.map(g => g.join('|')).join() === '0|1,0|2', 'encode.numeric: the old groups');
  must(byId('encode.numeric').newGroups.map(g => g[1]).join() === 'NaN,NaN,NaN', 'encode.numeric: the missing child');
  must(byId('encode.mixed').oldGroups.map(g => g.join('|')).join() === '|1,-|2,7|0', 'encode.mixed: the old groups '
    + JSON.stringify(byId('encode.mixed').oldGroups));
  must(morphs(byId('encode.mixed')).length === 4, 'encode.mixed: not four morphs');
  // a column never written is a float one: the missing child is NaN's string
  must(byId('multi.up.leaf').oldGroups.every(g => g[1] === 'NaN'), 'multi.up.leaf: a leaf\'s child is not "NaN"');
  must(morphs(byId('tm-sb')).length > 600, 'tm-sb: few morphs ' + morphs(byId('tm-sb')).length);
  must(morphs(byId('sb-tm')).length > 600, 'sb-tm: few morphs ' + morphs(byId('sb-tm')).length);
  must(morphs(byId('tm-sb-tm.inflight')).length > 600, 'tm-sb-tm.inflight: few morphs');
  must(JSON.stringify(morphs(byId('tm-sb-tm.inflight'))[0].d[0]) !== JSON.stringify(morphs(byId('sb-tm'))[0].d[0]),
    'tm-sb-tm.inflight: morphs from the settled sectors');
}

function generate() {
  NOW = T_BASE;
  rngState = SEED;
  const charts = chartCases().map(c => Object.assign(c, runCase(c)));
  guards(charts);
  return {
    source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + ') + zrender 6.1.0, node SSR (svg), controlled clock',
    note: 'D5 UT3: steps of setOption (the first at T0; a next one after the previous ran out, T + 10000, or `after` ms '
      + 'into it; notMerge unless `merge`), recorded at the last T + samples. Each element: an item path of a new series (id '
      + 's<series>/<dataIndex>/<path>) or another path of its view (s<series>/x/<k>); morph[i] = __morphT >= 0 and not '
      + 'combining, d[i] the replaced buildPath\'s PathProxy data (codes M1 L2 C3); comb[i] = __isCombineMorphing, pieces = '
      + 'its childrenRef() in order (present, morph, d, style); style = the effective fill / stroke / lineWidth / opacity, '
      + 'snap = the path\'s transform and shape keys, g.* its parent group\'s -- a key the same at every sample written '
      + 'once. direction: 0 none, 1 parent -> child, 2 child -> parent, sniffed on the dist\'s flattenDataDiffItems of '
      + 'every old and every new series; oldGroups / newGroups: [groupId, childGroupId] per flattened item (null for '
      + 'undefined). Every number is the hex of its double; a digest case writes a path as fnv<count>:<FNV-1a 32 of the '
      + 'hexes joined by ",">.',
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
