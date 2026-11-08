/*
Upstream's own answers for fix batch R7-AH (spec section 288): THE ROOT'S
VIEWS AND THE LAYERS.

From the real ECharts 6.1 dist, rendered by zrender's canvas painter on a
stand-in canvas (every layer a canvas of its own, each recording nothing but
its id), the clock replaced. Each case is a chart, 400 x 300 unless it says
otherwise, set up and then stepped: a step sets an option (`set`, with
`opts` -- notMerge, replaceMerge), dispatches an action (`act`), resizes
(`size`: [w, h]) or moves the clock (`t`, ms after T0: zr.animation.update(),
then a refresh). After every step (the first: after the option) the record
holds:

  roots   the zrender root's groups in order: a component view's mainType +
          componentIndex, a series view's 'S' + seriesIndex (prepareView's
          order: a view kept stays where it was, a new one goes after every
          one there is). Groups no view owns are left out.
  zl      every model's zlevel as allocateZlevels left it (model.get('zlevel'),
          null where none): 'xAxis0', 'S0', 'markPoint0' ...
  layers  the painter's built-in layers in order: [zlevel, zlevel2,
          motionBlur, lastFrameAlpha (hex; null without motion blur)]
  dl      the display list (storage.getDisplayList(true)) as runs: each a
          displayable's view (as in roots; a text the host's), zlevel, z,
          z2, incremental -- consecutive alike merged, with their count.

  node tools/advchart-oracle/view-layers.js

writes tests/fixtures/advchart-view-layers.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().
*/
'use strict';
const fs = require('fs');
const path = require('path');

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
global.requestAnimationFrame = function () { return 0; };

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-view-layers.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};

// ---------- the stand-in canvas: a context that takes everything ----------
function fakeCanvas(w, h) {
  const c = { nodeName: 'CANVAS', width: w, height: h, style: {}, setAttribute() {}, getAttribute() { return null; },
    addEventListener() {}, removeEventListener() {} };
  const ctx = new Proxy({ canvas: c }, {
    get: (t, k) => {
      if (k in t) return t[k];
      if (k === 'measureText') return s => ({ width: String(s).length * 6 });
      if (k === 'getImageData') return () => ({ data: [] });
      if (k === 'getLineDash') return () => [];
      if (k === 'createLinearGradient' || k === 'createRadialGradient') return () => ({ addColorStop() {} });
      if (k === 'createPattern') return () => ({});
      if (k === 'isPointInPath') return () => false;
      if (typeof k === 'string' && /^[a-z]/.test(k)) return function () {};
      return undefined;
    },
    set: (t, k, v) => { t[k] = v; return true; },
  });
  c.getContext = () => ctx;
  return c;
}
echarts.setPlatformAPI({ createCanvas() { return fakeCanvas(300, 150); } });

function viewTags(chart) {
  const m = new Map();
  for (const v of chart._componentsViews) {
    if (!v.__model) continue;
    const name = v.__model.mainType + v.__model.componentIndex;
    v.group.traverse(el => { m.set(el, name); });
  }
  for (const v of chart._chartsViews) {
    const name = 'S' + v.__model.seriesIndex;
    v.group.traverse(el => { m.set(el, name); });
  }
  return m;
}
function rootsOf(chart) {
  const out = [];
  for (const g of chart.getZr().storage.getRoots()) {
    const v = chart._componentsViews.find(cv => cv.group === g);
    const cv = chart._chartsViews.find(cv => cv.group === g);
    if (v && v.__model) out.push(v.__model.mainType + v.__model.componentIndex);
    else if (cv) out.push('S' + cv.__model.seriesIndex);
  }
  return out;
}
function zlOf(chart) {
  const out = {};
  chart.getModel().eachComponent((t, m) => {
    const z = m.get('zlevel');
    out[(t === 'series' ? 'S' : t) + m.componentIndex] = typeof z === 'number' ? z : null;
  });
  return out;
}
function layersOf(chart) {
  const p = chart.getZr().painter;
  return p._i.layerStack.map(k => {
    const L = p._i.layers[k.zl][k.zl2];
    return [k.zl, k.zl2, !!L.motionBlur, L.motionBlur ? hex(L.lastFrameAlpha) : null];
  }).filter(r => r[0] !== 314159);
}
function dlOf(chart) {
  const m = viewTags(chart);
  const runs = [];
  for (const el of chart.getZr().storage.getDisplayList(true)) {
    let t = m.get(el);
    if (!t && el.__hostTarget) t = m.get(el.__hostTarget);
    if (!t) { let p = el.parent; while (p && !m.get(p)) p = p.parent; if (p) t = m.get(p); }
    if (!t) continue;
    const k = [t, el.zlevel, el.z, el.z2, !!el.incremental];
    const last = runs[runs.length - 1];
    if (last && last[0] === k[0] && last[1] === k[1] && last[2] === k[2] && last[3] === k[3] && last[4] === k[4]) last[5]++;
    else runs.push(k.concat([1]));
  }
  return runs;
}

function run(c) {
  NOW = T0;
  rngState = SEED;
  const w = c.w || 400;
  const h = c.h || 300;
  const dom = fakeCanvas(w, h);
  const nodeWas = echarts.env.node;
  if (c.anim) echarts.env.node = false;
  const chart = echarts.init(dom, null, { renderer: 'canvas', width: w, height: h, devicePixelRatio: 1 });
  const recs = [];
  const snap = () => {
    recs.push({ roots: rootsOf(chart), zl: zlOf(chart), layers: layersOf(chart), dl: dlOf(chart) });
  };
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    chart.getZr().refreshImmediately(true);
    snap();
    for (const s of c.steps || []) {
      if (s.set) chart.setOption(JSON.parse(JSON.stringify(s.set)), s.opts || false);
      if (s.act) chart.dispatchAction(s.act);
      if (s.size) chart.resize({ width: s.size[0], height: s.size[1] });
      if (s.t != null) { NOW = T0 + s.t; chart.getZr().animation.update(); }
      chart.getZr().refreshImmediately(true);
      snap();
    }
  }
  finally {
    chart.dispose();
    echarts.env.node = nodeWas;
  }
  return Object.assign({ id: c.id, option: c.option }, c.w ? { w: c.w, h: c.h } : {}, c.anim ? { anim: true } : {},
    { steps: c.steps || [], recs });
}

const XY = { xAxis: { type: 'value', min: 0, max: 10 }, yAxis: { type: 'value', min: 0, max: 10 } };
const SC = (d, more) => Object.assign({ type: 'scatter', data: d || [[1, 1]] }, more || {});
const LN = (z, more) => Object.assign({ type: 'lines', coordinateSystem: 'cartesian2d', z,
  lineStyle: { color: '#ff0000', width: 2, opacity: 1 },
  effect: { show: true, trailLength: 0.4, period: 1, symbol: 'circle', symbolSize: 8, delay: 0 },
  data: [{ coords: [[1, 5], [9, 5]] }] }, more || {});
const A = (o) => Object.assign({ animation: true, animationDuration: 0, animationDurationUpdate: 0 }, o);
const NA = (o) => Object.assign({ animation: false }, o);
const SQ = { type: 'FeatureCollection', features: [{ type: 'Feature', properties: { name: 'A' },
  geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] } }] };
echarts.registerMap('vl-sq', JSON.stringify(SQ));
const MAPS = [{ name: 'vl-sq', text: JSON.stringify(SQ) }];

function cases() {
  return [
    // ---- the root's views (prepareView) ----
    // every kind at once: componentsMap's keys in topological order
    { id: 'vo-all', option: NA(Object.assign({}, XY, { series: [SC()], legend: {}, title: { text: 'T' },
      toolbox: { feature: { restore: {} } }, timeline: { data: ['a'] }, dataZoom: [{ type: 'slider' }],
      visualMap: { type: 'continuous', min: 0, max: 1, seriesIndex: 0 }, graphic: [{ type: 'rect', shape: { width: 5, height: 5 } }],
      calendar: { range: '2020-01' }, geo: { map: 'vl-sq' }, radar: { indicator: [{ max: 1 }, { max: 1 }, { max: 1 }] },
      polar: {}, angleAxis: {}, radiusAxis: {}, singleAxis: {}, matrix: { x: { data: ['a'] }, y: { data: ['b'] } } })) },
    // a merge: a new index of an old type, then a new type -- the old key first
    { id: 'vo-merge-two', option: NA(Object.assign({}, XY, { series: [SC()], legend: {} })),
      steps: [{ set: { xAxis: [{}, { type: 'value' }], timeline: { data: ['a'] } } }] },
    // a title new to the model after the legend's key went in empty
    { id: 'vo-merge-title', option: NA(Object.assign({}, XY, { series: [SC()] })),
      steps: [{ set: { title: { text: 'x' }, legend: {} } }, { set: { visualMap: { min: 0, max: 1 } } }] },
    // replaceMerge: a model mapped by index is brand new (its view last), by id kept
    { id: 'vo-rm-x', option: NA(Object.assign({}, XY, { series: [SC()] })),
      steps: [{ set: { xAxis: { type: 'value' } }, opts: { replaceMerge: ['xAxis'] } }] },
    { id: 'vo-rm-x-id', option: NA(Object.assign({}, XY, { xAxis: { id: 'a', type: 'value' }, series: [SC()] })),
      steps: [{ set: { xAxis: { id: 'a', type: 'value' } }, opts: { replaceMerge: ['xAxis'] } }] },
    { id: 'vo-rm-legend', option: NA(Object.assign({}, XY, { series: [SC()], legend: {}, title: { text: 'a' } })),
      steps: [{ set: { legend: {} }, opts: { replaceMerge: ['legend'] } }] },
    { id: 'vo-rm-series', option: NA(Object.assign({}, XY, { series: [SC(), SC([[2, 2]])], legend: {} })),
      steps: [{ set: { series: [SC([[3, 3]])] }, opts: { replaceMerge: ['series'] } }] },
    // notMerge: every component's view anew, after the series' it keeps
    { id: 'vo-nm', option: NA(Object.assign({}, XY, { series: [SC()], legend: {} })),
      steps: [{ set: NA(Object.assign({}, XY, { series: [SC()], legend: {}, title: { text: 'n' } })), opts: { notMerge: true } }] },
    // a timeline's frames: a frame's new models go after every view
    { id: 'vo-tl', option: { baseOption: NA(Object.assign({ timeline: { data: ['a', 'b', 'c'] } }, XY, { series: [SC()] })),
      options: [{}, { legend: {}, title: { text: 'x' } }, { visualMap: { type: 'continuous', min: 0, max: 1 } }] },
      steps: [{ act: { type: 'timelineChange', currentIndex: 1 } }, { act: { type: 'timelineChange', currentIndex: 2 } },
        { act: { type: 'timelineChange', currentIndex: 0 } }] },
    { id: 'vo-tl-rm', option: { baseOption: NA(Object.assign({ timeline: { data: ['a', 'b'], replaceMerge: ['xAxis'] } }, XY, { series: [SC()] })),
      options: [{ xAxis: { type: 'value' } }, { xAxis: { type: 'value', min: 0 } }] },
      steps: [{ act: { type: 'timelineChange', currentIndex: 1 } }] },
    // a media switch at a resize
    { id: 'vo-media', option: { baseOption: NA(Object.assign({}, XY, { series: [SC()] })),
      media: [{ query: { maxWidth: 500 }, option: { legend: {}, title: { text: 'x' } } },
        { query: { minWidth: 501 }, option: { visualMap: { type: 'continuous', min: 0, max: 1 } } }] },
      steps: [{ size: [600, 300] }, { size: [400, 300] }] },
    // ---- the components' order at one z and z2 ----
    { id: 'vo-z4', option: NA(Object.assign({}, XY, { series: [SC([[1, 1]], { name: 'A' })], legend: { left: 0, top: 0 },
      visualMap: { type: 'piecewise', min: 0, max: 1, left: 0, top: 0 }, dataZoom: [{ type: 'slider', left: 0, top: 0 }],
      timeline: { data: ['a', 'b'], left: 0, top: 0 }, toolbox: { feature: { restore: {} }, left: 0, top: 0 },
      title: { text: 'T', left: 0, top: 0, backgroundColor: '#eee' } })) },
    { id: 'vo-z4-merge', option: NA(Object.assign({}, XY, { series: [SC([[1, 1]], { name: 'A' })], legend: { left: 0, top: 0 } })),
      steps: [{ set: { visualMap: { type: 'piecewise', min: 0, max: 1, left: 0, top: 0 } } },
        { set: { timeline: { data: ['a', 'b'], left: 0, top: 0 } } }] },
    { id: 'vo-geo-radar', option: NA({ geo: { map: 'vl-sq' }, radar: { indicator: [{ max: 1 }, { max: 1 }, { max: 1 }] },
      series: [{ type: 'radar', data: [{ value: [1, 1, 1] }] }] }) },
    // ---- allocateZlevels ----
    { id: 'zl-under', anim: true, option: A(Object.assign({}, XY, { series: [LN(-1)], legend: {}, title: { text: 'T' } })),
      steps: [{ t: 100 }] },
    { id: 'zl-default', anim: true, option: A(Object.assign({}, XY, { series: [LN(2)], legend: {}, title: { text: 'T' } })),
      steps: [{ t: 100 }] },
    { id: 'zl-between', anim: true, option: A(Object.assign({}, XY, { series: [SC([[2, 2]]), LN(2), SC([[3, 3]])] })),
      steps: [{ t: 100 }] },
    { id: 'zl-keys', anim: true, option: A(Object.assign({}, XY, { series: [LN(2), LN(2),
      LN(2, { effect: { show: true, trailLength: 0.2, period: 1, symbolSize: 8 } })] })), steps: [{ t: 100 }] },
    { id: 'zl-markers', anim: true, option: A(Object.assign({}, XY, { series: [LN(2, { markPoint: { data: [{ coord: [5, 5] }] } }),
      SC([[2, 2]], { markLine: { data: [{ yAxis: 3 }] } })] })), steps: [{ t: 100 }] },
    // a component of the trail's z: before the series in the sort, on the level under it
    { id: 'zl-calendar', anim: true, option: A(Object.assign({}, XY, { series: [LN(2)], calendar: { range: '2020-01', top: 200 },
      legend: {} })), steps: [{ t: 100 }] },
    { id: 'zl-own', anim: true, option: A(Object.assign({}, XY, { series: [LN(2, { zlevel: 3 }), SC([[2, 2]])] })), steps: [{ t: 100 }] },
    { id: 'zl-mk-series', option: NA(Object.assign({}, XY, { series: [SC([[2, 2]], { zlevel: 3, markPoint: { data: [{ coord: [5, 5] }] } })] })) },
    { id: 'zl-off', anim: true, option: A(Object.assign({}, XY, { series: [LN(2, { effect: { show: false, trailLength: 0.4 } })], legend: {} })) },
    { id: 'zl-off-after', anim: true, option: A(Object.assign({}, XY, { series: [LN(2)], legend: {} })),
      steps: [{ t: 100 }, { set: { series: [{ effect: { show: false } }] } }, { set: { legend: { zlevel: 0 } } }] },
    { id: 'zl-big', option: NA(Object.assign({}, XY, { series: [SC(Array.from({ length: 3500 }, (_, i) => [i % 10, (i * 7) % 10]))],
      legend: {}, title: { text: 'T' } })) },
    { id: 'zl-big-under', option: NA(Object.assign({}, XY, { series: [SC(Array.from({ length: 150 }, (_, i) => [(i * 37) % 100 / 10, (i * 53) % 100 / 10]),
      { z: -1, symbolSize: 4, progressive: 50, progressiveThreshold: 100 })] })) },
    { id: 'zl-graphic', anim: true, option: A(Object.assign({}, XY, { series: [LN(-1)],
      graphic: [{ type: 'rect', shape: { x: 10, y: 10, width: 20, height: 20 } }, { type: 'rect', z: -5, shape: { x: 40, y: 10, width: 20, height: 20 } }] })),
      steps: [{ t: 100 }] },
  ];
}

function generate() {
  const charts = cases().map(run);
  const by = id => charts.find(c => c.id === id);
  // self-checks: what the cases are for
  must(by('vo-merge-two').recs[1].roots.slice(-2).join(' ') === 'xAxis1 timeline0', 'vo-merge-two: the old key first');
  must(by('vo-rm-x').recs[1].roots[by('vo-rm-x').recs[1].roots.length - 1] === 'xAxis0', 'vo-rm-x: brand new last');
  must(by('zl-under').recs[0].zl.S0 === 0 && by('zl-under').recs[0].zl.xAxis0 === 1, 'zl-under: the trail under the axes');
  must(by('zl-off-after').recs[2].zl.S0 === 1, 'zl-off-after: the level stays');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node, zrender canvas painter on stand-in canvases',
    note: 'R7-AH: per case and step, the root\'s views in order, every model\'s zlevel after allocateZlevels, the '
      + 'painter\'s layers (zlevel, zlevel2, motionBlur, lastFrameAlpha) and the display list as runs of '
      + '[view, zlevel, z, z2, incremental, count].', W: 400, H: 300, T0, maps: MAPS, charts };
}

let j1, j2;
try {
  j1 = JSON.stringify(generate(), null, 1) + '\n';
  j2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (j1 !== j2) { console.log('FAILED: two generations differ'); process.exit(1); }
fs.writeFileSync(OUT, j1);
console.log('wrote', OUT, j1.length, 'bytes');
process.exit(0);
