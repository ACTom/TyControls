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
    // (R7-AJ) a brush's covers: its controller's group, mounted on the root apart from the view's
    if (v._brushController && v._brushController.group) v._brushController.group.traverse(el => { if (!m.has(el)) m.set(el, name); });
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
      // (a copy: dispatchAction writes an inner key into the payload, its
      // number the order the dist's modules made their inners in)
      if (s.act) chart.dispatchAction(JSON.parse(JSON.stringify(s.act)));
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
// [R7-AJ] N scatter points, lines rows, bar values -- deterministic
const PS = n => Array.from({ length: n }, (_, i) => [(i * 37) % 100 / 10, (i * 53) % 100 / 10]);
const PL = n => Array.from({ length: n }, (_, i) => ({ coords: [[(i * 37) % 100 / 10, (i * 53) % 100 / 10],
  [(i * 71) % 100 / 10, (i * 29) % 100 / 10]] }));
const PB = n => Array.from({ length: n }, (_, i) => 1 + (i * 37) % 9);
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
    // ---- R7-AJ: the title in the display list, sorted with everything else ----
    // (TitleView: the text and the subtext z2 10, the background Rect z2 0, all at the title's z)
    // a thumbnail (z 10) over the title (z 6)
    { id: 'vo-title-thumb', option: NA({ title: { text: 'Title', left: 0, top: 0, backgroundColor: '#eeeeee' },
      thumbnail: { left: 0, top: 0, width: 120, height: 80 },
      series: [{ type: 'graph', layout: 'none', roam: true, data: [{ x: 0, y: 0 }, { x: 100, y: 50 }], links: [{ source: 0, target: 1 }] }] }) },
    // a brush cover (z 10000) over it
    { id: 'vo-title-brush', option: NA(Object.assign({}, XY, { title: { text: 'Title', left: 'center', top: 'middle', backgroundColor: '#eeeeee' },
      brush: { xAxisIndex: 0 }, series: [SC()] })),
      steps: [{ act: { type: 'brush', areas: [{ brushType: 'lineX', coordRange: [2, 8], xAxisIndex: 0 }] } }] },
    // the toolbox at the title's z: its icons over the frame, under the text
    { id: 'vo-title-toolbox', option: NA(Object.assign({}, XY, { title: { text: 'Title', left: 0, top: 0, backgroundColor: '#eeeeee' },
      toolbox: { left: 0, top: 0, feature: { restore: {}, saveAsImage: {} } }, series: [SC()] })) },
    // a parallel axis (z 10) over it
    { id: 'vo-title-parallel', option: NA({ title: { text: 'Title', left: 'center', top: 'middle', backgroundColor: '#eeeeee' },
      parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }], series: [{ type: 'parallel', data: [[1, 2, 3], [3, 2, 1]] }] }) },
    // a title of z 20 over a legend of z 4, under a slider of z 30
    { id: 'vo-title-z', option: NA(Object.assign({}, XY, { title: { text: 'Title', left: 0, top: 0, z: 20, backgroundColor: '#eeeeee' },
      legend: { left: 0, top: 0 }, dataZoom: [{ type: 'slider', top: 0, left: 0, z: 30 }], series: [SC([[1, 1]], { name: 'A' })] })) },
    // a title of z -1: under the axes
    { id: 'vo-title-under', option: NA(Object.assign({}, XY, { title: { text: 'Title', left: 'center', top: 'middle', z: -1, backgroundColor: '#eeeeee' },
      series: [SC()] })) },
    // a title on a zlevel of its own, and one on the root's
    { id: 'vo-title-zl', option: NA(Object.assign({}, XY, { title: [{ text: 'A', zlevel: 2 }, { text: 'B', subtext: 's', left: 'right' }],
      legend: {}, series: [SC([[1, 1]], { name: 'A' })] })) },
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
    // an effect shown with no trailLength: the default 0.2 trails
    { id: 'zl-default-length', anim: true, option: A(Object.assign({}, XY, { series: [LN(2, { effect: { show: true,
      period: 1, symbol: 'circle', symbolSize: 8, delay: 0 } })], legend: {} })), steps: [{ t: 100 }] },
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
    // ---- R7-AJ: a progressive run's own level (getZLevelKey: more rows than
    // getProgressiveThreshold), one incremental layer per zlevel ----
    // a lines series with no effect, more rows than its threshold, under the axes
    { id: 'zl-prog-lines', option: NA(Object.assign({}, XY, { series: [{ type: 'lines', coordinateSystem: 'cartesian2d',
      z: -1, progressive: 20, progressiveThreshold: 50, lineStyle: { color: '#ff0000', width: 1 },
      data: PL(60) }], legend: {}, title: { text: 'T' } })) },
    // and of the default z: the axes under it, the legend and the title over it
    { id: 'zl-prog-lines-z2', option: NA(Object.assign({}, XY, { series: [{ type: 'lines', coordinateSystem: 'cartesian2d',
      progressive: 20, progressiveThreshold: 50, data: PL(60) }], legend: {}, title: { text: 'T' } })) },
    // two runs side by side: their keys (ids) differ -- a level each; a series between
    { id: 'zl-prog-two', option: NA(Object.assign({}, XY, { series: [SC(PS(30), { progressive: 10, progressiveThreshold: 20 }),
      SC(PS(30), { progressive: 10, progressiveThreshold: 20 }), { type: 'line', data: [[1, 1], [9, 9]] },
      SC(PS(30), { z: 4, progressive: 10, progressiveThreshold: 20 })] })) },
    // a run of no more rows than its threshold has no key
    { id: 'zl-prog-at', option: NA(Object.assign({}, XY, { series: [SC(PS(20), { progressive: 10, progressiveThreshold: 20 }),
      { type: 'line', data: [[1, 1], [9, 9]] }] })) },
    // large: a scatter's threshold 1e4, a lines series' 2e4 -- unless written
    { id: 'zl-prog-large', option: NA(Object.assign({}, XY, { series: [SC(PS(40), { large: true, largeThreshold: 10 }),
      { type: 'lines', coordinateSystem: 'cartesian2d', large: true, largeThreshold: 10, data: PL(40) },
      SC(PS(40), { large: true, largeThreshold: 10, progressiveThreshold: 30 })] })) },
    // progressive switched off: the key is the rows' and the threshold's alone
    { id: 'zl-prog-off', option: NA(Object.assign({}, XY, { series: [SC(PS(30), { progressive: 0, progressiveThreshold: 20 })],
      title: { text: 'T' } })) },
    // two incremental runs on user zlevels 0 and 2, a graphic on 1 between: a layer each
    { id: 'zl-prog-user', option: NA(Object.assign({}, XY, { xAxis: { type: 'category' }, series: [
      { type: 'bar', large: true, largeThreshold: 5, progressive: 10, progressiveThreshold: 20, data: PB(40) },
      { type: 'bar', zlevel: 2, large: true, largeThreshold: 5, progressive: 10, progressiveThreshold: 20, data: PB(40) }],
      graphic: [{ type: 'rect', zlevel: 1, shape: { x: 0, y: 0, width: 100, height: 100 } }] })) },
    // a dataZoom that filters the rows below the threshold: the key is the data's count
    { id: 'zl-prog-dz', option: NA(Object.assign({}, XY, { series: [SC(PS(40), { progressive: 10, progressiveThreshold: 30 })],
      dataZoom: [{ type: 'inside', xAxisIndex: 0, filterMode: 'filter', startValue: 0, endValue: 4 }] })),
      steps: [{ act: { type: 'dataZoom', startValue: 0, endValue: 10 } }] },
    // two trails of one trailLength, more rows than their threshold: the ids
    // their keys (a level each), not the trailLength (one shared)
    { id: 'zl-prog-trails', anim: true, option: A(Object.assign({}, XY, { series: [
      LN(2, { progressiveThreshold: 50, data: PL(60) }), LN(2, { progressiveThreshold: 50, data: PL(60) })] })),
      steps: [{ t: 100 }] },
    // preventIncremental: a heatmap on a geo (lng / lat) is not progressive, on a grid it is
    { id: 'zl-prog-heat-geo', option: NA({ geo: { map: 'vl-sq' }, visualMap: { min: 0, max: 1, show: false },
      xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e', 'f'] }, yAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] },
      series: [{ type: 'heatmap', coordinateSystem: 'geo', progressive: 10, progressiveThreshold: 20,
        data: Array.from({ length: 30 }, (_, i) => [(i * 37) % 100 / 10, (i * 53) % 100 / 10, (i % 10) / 10]) },
      { type: 'heatmap', progressive: 10, progressiveThreshold: 20,
        data: Array.from({ length: 30 }, (_, i) => [i % 6, Math.floor(i / 6), (i % 10) / 10]) }] }) },
  ];
}

function generate() {
  const charts = cases().map(run);
  const by = id => charts.find(c => c.id === id);
  // self-checks: what the cases are for
  must(by('vo-merge-two').recs[1].roots.slice(-2).join(' ') === 'xAxis1 timeline0', 'vo-merge-two: the old key first');
  must(by('vo-rm-x').recs[1].roots[by('vo-rm-x').recs[1].roots.length - 1] === 'xAxis0', 'vo-rm-x: brand new last');
  // (R7-AJ) the title's runs: the frame z2 0 under the toolbox's icons, the text z2 10 over them; a thumbnail over it
  const runAt = (id, step, view, z2) => by(id).recs[step].dl.findIndex(r => r[0] === view && (z2 == null || r[3] === z2));
  must(runAt('vo-title-toolbox', 0, 'title0', 0) < runAt('vo-title-toolbox', 0, 'toolbox0', 0)
    && runAt('vo-title-toolbox', 0, 'toolbox0', 0) < runAt('vo-title-toolbox', 0, 'title0', 10), 'vo-title-toolbox: frame, icons, text');
  must(runAt('vo-title-thumb', 0, 'title0', 10) < runAt('vo-title-thumb', 0, 'thumbnail0', null), 'vo-title-thumb: the thumbnail over the title');
  must(runAt('vo-title-brush', 1, 'title0', 10) < runAt('vo-title-brush', 1, 'brush0', null), 'vo-title-brush: the cover over the title');
  must(by('zl-under').recs[0].zl.S0 === 0 && by('zl-under').recs[0].zl.xAxis0 === 1, 'zl-under: the trail under the axes');
  must(by('zl-off-after').recs[2].zl.S0 === 1, 'zl-off-after: the level stays');
  must(by('zl-prog-lines').recs[0].zl.S0 === 0 && by('zl-prog-lines').recs[0].zl.xAxis0 === 1, 'zl-prog-lines: the run under the axes');
  must(!by('zl-prog-at').recs[0].zl.S0 && !by('zl-prog-at').recs[0].zl.S1, 'zl-prog-at: no key at the threshold');
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
