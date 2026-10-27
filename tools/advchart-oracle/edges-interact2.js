/*
Upstream's own answers for fix batch R5-G, the interaction part's second
round (spec section 244).

  dz-action     dataZoom actions whose ends differ in kind ({start, endValue},
                {startValue, end}), category names for startValue / endValue,
                and an end left out keeping what the settled option held:
                after each action the x axis' proxy window (value and
                percent) -- AxisProxy.getDataValueWindow / getDataPercentWindow
  tb-span       the toolbox's dataZoom select dragged narrower (and wider)
                than the axis' host dataZoom allows: _onBrush's setBatch runs
                sliderMove with getMinMaxSpan's minValueSpan / maxValueSpan
                -- the window after the release
  irrelevant    onIrrelevantElement: a drag that starts on a series drawn
                higher over a graph's roam area or over a parallel axis'
                panel does not start that roam or that area select; one that
                starts on blank does -- the actions dispatched
  jitter-brush  a brush area over a jittered scatter: selected by the
                jittered points (jitterLayout runs before the brush's visual
                stage) -- brushselected's dataIndex

  node tools/advchart-oracle/edges-interact2.js

writes tests/fixtures/advchart-edges-interact2.json (ORACLE_OUT overrides).
Doubles as 16 hex digits with a readable twin. Guards: a mixed action's
ends in two kinds; a category name moving the window; the span clamping a
narrower select; a drag on the higher series refused while one on blank is
taken (both for the graph and the parallel); a jittered selection that
the plain points would not give. Two generations byte-identical; ends with
process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-interact2.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const clone = o => JSON.parse(JSON.stringify(o));
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const txt = v => (Object.is(v, -0) ? '-0' : String(v));
const pair = a => ({ hex: a.map(hex), text: a.map(txt) });

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
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function zr(chart) { return chart.getZr(); }
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, x, y) {
  refresh(chart);
  zr(chart).handler[name](zev({ zrX: x, zrY: y }));
  refresh(chart);
}
function frame(chart) { chart._onframe && chart._onframe(); chart.renderToSVGString(); refresh(chart); }

const cases = [];
function add(group, id, note, option, extra) {
  cases.push(Object.assign({ group, id, note, W: 600, H: 400, option }, extra || {}));
}
const CAT = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'];
const catLine = (dz) => ({ animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
  dataZoom: [Object.assign({ type: 'slider' }, dz || {})], series: [{ type: 'line', data: [5, 3, 7, 2, 9, 4, 6, 8, 1, 3] }] });
const valScatter = (dz) => ({ animation: false, xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value' },
  dataZoom: [Object.assign({ type: 'slider' }, dz || {})],
  series: [{ type: 'scatter', data: Array.from({ length: 21 }, (_, i) => [i * 5, (i * 7) % 11]) }] });

add('dz-action', 'dz-mixed', 'one end a percent, the other a value; then the start a value, the end a percent',
  catLine(), { actions: [{ type: 'dataZoom', start: 20, endValue: 7 }, { type: 'dataZoom', startValue: 1, end: 60 }] });
add('dz-action', 'dz-names', 'category names for the values',
  catLine(), { actions: [{ type: 'dataZoom', startValue: 'c', endValue: 'h' }, { type: 'dataZoom', startValue: 'b' }] });
add('dz-action', 'dz-keep', 'an end left out keeps the settled option\'s value end',
  catLine({ startValue: 2, endValue: 6 }), { actions: [{ type: 'dataZoom', start: 50 }, { type: 'dataZoom', end: 100 }] });
add('dz-action', 'dz-value-axis', 'a value axis: startValue with end',
  valScatter(), { actions: [{ type: 'dataZoom', startValue: 15, end: 70 }, { type: 'dataZoom', start: 10, endValue: 90 }] });
add('dz-action', 'dz-both-rangemode', 'both of a pair written: the option\'s rangeMode decides',
  valScatter({ rangeMode: ['value', 'percent'] }), { actions: [{ type: 'dataZoom', start: 10, startValue: 40, end: 80, endValue: 60 }] });

const tbOpt = (dz) => ({ animation: false, toolbox: { feature: { dataZoom: { yAxisIndex: 'none' } } },
  xAxis: { type: 'value', min: 0, max: 100 }, yAxis: { type: 'value' },
  dataZoom: [Object.assign({ type: 'slider', xAxisIndex: 0 }, dz)],
  series: [{ type: 'scatter', data: Array.from({ length: 21 }, (_, i) => [i * 5, (i * 7) % 11]) }] });
add('tb-span', 'tb-min', 'a select narrower than minValueSpan 30', tbOpt({ minValueSpan: 30 }), { drag: [[300, 150], [330, 200]] });
add('tb-span', 'tb-max', 'a select wider than maxValueSpan 20', tbOpt({ maxValueSpan: 20 }), { drag: [[150, 150], [400, 200]] });
add('tb-span', 'tb-minpct', 'a percent minSpan 40 over the data extent', tbOpt({ minSpan: 40 }), { drag: [[300, 150], [330, 200]] });

add('irrelevant', 'ir-graph', 'a graph that roams under a scatter drawn higher: a drag from the scatter is not the graph\'s',
  { animation: false,
    grid: { left: 0, right: 0, top: 0, bottom: 0 },
    xAxis: { type: 'value', min: 0, max: 600, show: false }, yAxis: { type: 'value', min: 0, max: 400, show: false },
    series: [
      { type: 'graph', layout: 'none', roam: true, symbolSize: 20, left: 100, right: 100, top: 80, bottom: 80,
        data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }], links: [{ source: 'a', target: 'b' }] },
      { type: 'scatter', z: 5, symbolSize: 30, data: [[300, 200]] }] },
  { probes: [[300, 200], [250, 150]] });
add('irrelevant', 'ir-graph-equal', 'a scatter at the graph z: equal is relevant, the drag from it roams the graph',
  { animation: false,
    grid: { left: 0, right: 0, top: 0, bottom: 0 },
    xAxis: { type: 'value', min: 0, max: 600, show: false }, yAxis: { type: 'value', min: 0, max: 400, show: false },
    series: [
      { type: 'graph', layout: 'none', roam: true, symbolSize: 20, left: 100, right: 100, top: 80, bottom: 80,
        data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 100 }], links: [{ source: 'a', target: 'b' }] },
      { type: 'scatter', z: 2, symbolSize: 30, data: [[300, 200]] }] },
  { probes: [[300, 200]] });
add('irrelevant', 'ir-parallel', 'a parallel axis under a scatter drawn higher: an area select from the scatter does not start',
  { animation: false,
    grid: { left: 0, right: 0, top: 0, bottom: 0 },
    xAxis: { type: 'value', min: 0, max: 600, show: false }, yAxis: { type: 'value', min: 0, max: 400, show: false },
    parallel: { left: 100, right: 100, top: 60, bottom: 60 },
    parallelAxis: [{ dim: 0, name: 'p' }, { dim: 1, name: 'q' }],
    series: [{ type: 'parallel', data: [[1, 2], [3, 4]] },
      { type: 'scatter', z: 20, symbolSize: 30, data: [[100, 200]] }] },
  { pdrags: [[[100, 200], [100, 260]], [[100, 120], [100, 170]]] });
add('irrelevant', 'ir-parallel-line', "a scatter at z 5, under the axis' own line (z 10, hit across the whole select band): a select starts from on the line and from beside it",
  { animation: false,
    grid: { left: 0, right: 0, top: 0, bottom: 0 },
    xAxis: { type: 'value', min: 0, max: 600, show: false }, yAxis: { type: 'value', min: 0, max: 400, show: false },
    parallel: { left: 100, right: 100, top: 60, bottom: 60 },
    parallelAxis: [{ dim: 0, name: 'p' }, { dim: 1, name: 'q' }],
    series: [{ type: 'parallel', data: [[1, 2], [3, 4]] },
      { type: 'scatter', z: 5, symbolSize: 30, data: [[100, 200]] }] },
  { pdrags: [[[100, 200], [100, 260]], [[107, 200], [107, 260]]] });

const jit = () => {
  const d = [];
  for (let i = 0; i < 24; i++) d.push([CAT[i % 3], (i * 37) % 50]);
  return d;
};
add('jitter-brush', 'jb-x', 'jittered points on a category x axis; a rect over the right half of the first band',
  { animation: false, brush: {}, xAxis: { type: 'category', data: ['a', 'b', 'c'], jitter: 60 }, yAxis: { type: 'value' },
    series: [{ type: 'scatter', symbolSize: 6, data: jit() }] },
  { band: 0 });

function seriesOf(chart, type) {
  let r = null;
  chart.getModel().eachSeries(s => { if (!r && s.subType === type) r = s; });
  return r;
}
function xWindow(chart) {
  const dz = chart.getModel().getComponent('dataZoom', 0);
  const proxy = dz.findRepresentativeAxisProxy();
  const w = proxy.getWindow(); return { value: pair(w.value.slice()), percent: pair(w.percent.slice()) };
}
function logged(chart, fn) {
  const log = [];
  const orig = chart._api.dispatchAction;
  chart._api.dispatchAction = function (p) { log.push(p.type); return orig.apply(this, arguments); };
  try { fn(); } finally { chart._api.dispatchAction = orig; }
  return log;
}

const RUN = {
  'dz-action': (chart, c) => {
    const after = [];
    for (const a of c.actions) { chart.dispatchAction(clone(a)); frame(chart); after.push(xWindow(chart)); }
    return { after };
  },
  'tb-span': (chart, c) => {
    chart.dispatchAction({ type: 'takeGlobalCursor', key: 'dataZoomSelect', dataZoomSelectActive: true });
    frame(chart);
    const [p0, p1] = c.drag;
    fire(chart, 'mousedown', p0[0], p0[1]);
    fire(chart, 'mousemove', (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2);
    fire(chart, 'mousemove', p1[0], p1[1]);
    fire(chart, 'mouseup', p1[0], p1[1]);
    frame(chart);
    return { after: xWindow(chart) };
  },
  'irrelevant': (chart, c) => {
    const out = [];
    for (const p of (c.probes || [])) {
      const log = logged(chart, () => {
        fire(chart, 'mousedown', p[0], p[1]);
        fire(chart, 'mousemove', p[0] + 20, p[1] + 10);
        fire(chart, 'mousemove', p[0] + 40, p[1] + 20);
        fire(chart, 'mouseup', p[0] + 40, p[1] + 20);
      });
      frame(chart);
      if (log.indexOf('graphRoam') >= 0) { chart.dispatchAction({ type: 'graphRoam', seriesIndex: 0, dx: -40, dy: -20 }); frame(chart); }
      out.push({ at: p, roamed: log.indexOf('graphRoam') >= 0 });
    }
    for (const d of (c.pdrags || [])) {
      const [a, b] = d;
      const log = logged(chart, () => {
        fire(chart, 'mousedown', a[0], a[1]);
        fire(chart, 'mousemove', (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
        fire(chart, 'mousemove', b[0], b[1]);
        fire(chart, 'mouseup', b[0], b[1]);
      });
      frame(chart);
      out.push({ at: a, to: b, selected: log.indexOf('axisAreaSelect') >= 0 });
    }
    return { results: out };
  },
  'jitter-brush': (chart, c) => {
    const s = seriesOf(chart, 'scatter');
    const d = s.getData();
    // the band's right half, all heights: [centre, centre + band/2]
    const xa = chart.getModel().getComponent('xAxis', 0).axis;
    const centre = xa.toGlobalCoord(xa.dataToCoord(c.band));
    const half = xa.getBandWidth() / 2;
    const grid = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
    const range = [[centre, centre + half], [grid.y, grid.y + grid.height]];
    let sel = null;
    chart.on('brushselected', e => { sel = e.batch[0].selected[0].dataIndex.slice(); });
    chart.dispatchAction({ type: 'brush', areas: [{ brushType: 'rect', range: range }] });
    frame(chart);
    must(sel, 'no brushselected');
    // the plain points' answer, for the guard
    const plain = [];
    d.each(i => { const p = chart.convertToPixel({ seriesIndex: 0 }, [d.get('x', i), d.get('y', i)]); if (p[0] >= range[0][0] && p[0] <= range[0][1]) plain.push(i); });
    return { range: range.map(pair), selected: sel, plain };
  }
};

function run(c) {
  const chart = mk(c.W, c.H);
  try {
    chart.setOption(clone(c.option));
    frame(chart);
    const rec = RUN[c.group](chart, c);
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option };
    ['actions', 'drag', 'probes', 'pdrags', 'band'].forEach(k => { if (c[k] !== undefined) out[k] = c[k]; });
    return Object.assign(out, rec);
  } finally {
    chart.dispose();
  }
}

function guards(out) {
  const g = [];
  const guard = (name, ok) => { if (!process.env.NOGUARD) must(ok, 'guard failed: ' + name); g.push(name); };
  const byId = id => out.cases.find(c => c.id === id);
  const mixed = byId('dz-mixed').after[0];
  guard('a mixed action: the start 20 percent, the end the value 7', mixed.percent.text[0] === '20' && mixed.value.text[1] === '7');
  guard('a category name moves the window', byId('dz-names').after[0].value.text[0] === '2');
  guard('an end left out keeps the option\'s value end', byId('dz-keep').after[0].value.text[1] === '6');
  const tmin = byId('tb-min').after.value.text;
  guard('the select is widened to minValueSpan', Number(tmin[1]) - Number(tmin[0]) >= 30 - 1e-9);
  const tmax = byId('tb-max').after.value.text;
  guard('the select is narrowed to maxValueSpan', Number(tmax[1]) - Number(tmax[0]) <= 20 + 1e-9);
  const ig = byId('ir-graph').results;
  guard('a drag from the higher scatter does not roam the graph; from blank it does', !ig[0].roamed && ig[1].roamed);
  guard('a scatter at an equal z does not refuse the roam', byId('ir-graph-equal').results[0].roamed);
  const ip = byId('ir-parallel').results;
  guard('an area select from the higher scatter does not start; from blank it does', !ip[0].selected && ip[1].selected);
  const il = byId('ir-parallel-line').results;
  guard('under the axis line (z 10) the z 5 scatter does not refuse it', il[0].selected && il[1].selected);
  const jb = byId('jb-x');
  guard('the jittered selection is not the plain points\'', JSON.stringify(jb.selected) !== JSON.stringify(jb.plain));
  return g;
}

function generate() {
  const out = { source: 'echarts ' + echarts.version + ' (' + path.basename(DIST) + ')', cases: [] };
  for (const c of cases) out.cases.push(run(c));
  out.guards = guards(out);
  return JSON.stringify(out, null, 1) + '\n';
}

try {
  const a = generate();
  const b = generate();
  must(a === b, 'two generations differ');
  JSON.parse(a);
  fs.writeFileSync(OUT, a);
  console.log('wrote', OUT, cases.length, 'cases');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  process.exit(1);
}
