/*
Upstream's own answers for fix batch R5-G, the interaction part (spec section
244).

  sankey-drag      a drag on a sankey node: the dragNode payloads the view
                   dispatches -- their keys in order, and the seriesId (the
                   model id, '\0name\00'; NUL written as <NUL>)
  sankey-trigger   roam: true with roamTrigger 'selfRect': per probe point,
                   whether a drag that starts there pans (sankeyRoam), the
                   main group's own box deciding (a node a dragNode put
                   outside the box widens it)
  polar-brush      a global brush area over a chart with bars on a polar:
                   barPolar's sector layout has no x, y, width, height, so a
                   rect area selects every bar and a lineX area none -- the
                   brushselected event's dataIndex per series
  gesture-brush    a click that drills a sunburst, zooms a treemap or
                   expands a tree, with a brush component on the chart: the
                   dispatched action's update runs the brush's visual stage,
                   so a brushselected event comes; the events in order
                   (brushselected, updated)

  node tools/advchart-oracle/edges-interact.js

writes tests/fixtures/advchart-edges-interact.json (ORACLE_OUT overrides).
Guards: a seriesId on the dragNode payload and no seriesIndex; a probe inside
the view's box that does not pan and one outside it that does; every polar
bar selected by a rect and none by a lineX; a brushselected for each
gesture. Two generations byte-identical; ends with process.exit().
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-interact.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const clone = o => JSON.parse(JSON.stringify(o));
const nul = s => (typeof s === 'string' ? s.split('\u0000').join('<NUL>') : s);

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
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

const sankeyData = {
  data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
  links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 },
    { source: 'b', target: 'd', value: 4 }, { source: 'c', target: 'd', value: 2 }]
};
add('sankey-drag', 'sd-drag', 'press node a, two moves, release: one dragNode per move',
  { animation: false, series: [Object.assign({ type: 'sankey', name: 'flow', left: 50, right: 50, top: 40, bottom: 40,
    layoutIterations: 0 }, clone(sankeyData))] }, { node: 0, moves: [[10, 6], [24, 10]] });
add('sankey-trigger', 'st-self', "roamTrigger 'selfRect': a node put outside the box by its localX widens the group's own box",
  { animation: false, series: [Object.assign({ type: 'sankey', left: 100, right: 200, top: 60, bottom: 60,
    layoutIterations: 0, roam: true, roamTrigger: 'selfRect', draggable: false }, clone(sankeyData))] },
  { localD: 1.3 });

const polarBar = (brushType, range) => ({
  animation: false,
  polar: { radius: [20, 150] },
  angleAxis: { type: 'value', max: 10 },
  radiusAxis: { type: 'category', data: ['a', 'b', 'c'] },
  brush: {},
  series: [{ type: 'bar', coordinateSystem: 'polar', data: [3, null, 7] },
    { type: 'bar', coordinateSystem: 'polar', data: [2, 4, 1] }]
});
add('polar-brush', 'pb-rect', 'a rect area anywhere: every polar bar is selected', polarBar(),
  { areas: [{ brushType: 'rect', range: [[10, 40], [10, 40]] }] });
add('polar-brush', 'pb-linex', 'a lineX area: none', polarBar(),
  { areas: [{ brushType: 'lineX', range: [0, 600] }] });
add('polar-brush', 'pb-polygon', 'a polygon area: every bar too (its corner test meets NaN)', polarBar(),
  { areas: [{ brushType: 'polygon', range: [[0, 0], [600, 0], [600, 400], [0, 400]] }] });

const hier = [{ name: 'A', children: [{ name: 'a1', value: 3 }, { name: 'a2', value: 2 }] },
  { name: 'B', children: [{ name: 'b1', value: 4 }] }];
add('gesture-brush', 'gb-sunburst', 'a click that drills a sunburst', { animation: false,
  brush: {},
  series: [{ type: 'sunburst', radius: [0, 150], data: clone(hier) }] }, { pick: 'sunburst' });
add('gesture-brush', 'gb-treemap', 'a click that zooms a treemap', { animation: false,
  brush: {},
  series: [{ type: 'treemap', roam: false, breadcrumb: { show: false }, leafDepth: null, data: clone(hier) }] }, { pick: 'treemap' });
add('gesture-brush', 'gb-tree', 'a click that collapses a tree node', { animation: false,
  brush: {},
  series: [{ type: 'tree', symbolSize: 14, initialTreeDepth: -1, data: [{ name: 'r', children: clone(hier) }] }] }, { pick: 'tree' });

function seriesOf(chart, type) {
  let r = null;
  chart.getModel().eachSeries(s => { if (!r && s.subType === type) r = s; });
  return r;
}

const RUN = {
  'sankey-drag': (chart, c) => {
    const s = seriesOf(chart, 'sankey');
    const el = s.getData().getItemGraphicEl(c.node);
    const b = el.getBoundingRect().clone();
    b.applyTransform(el.getComputedTransform());
    let x = Math.round(b.x + b.width / 2), y = Math.round(b.y + b.height / 2);
    const log = [];
    const orig = chart._api.dispatchAction;
    chart._api.dispatchAction = function (p) {
      if (p.type === 'dragNode') log.push({ keys: Object.keys(p), seriesId: nul(p.seriesId), dataIndex: p.dataIndex });
      return orig.apply(this, arguments);
    };
    fire(chart, 'mousedown', x, y);
    for (const m of c.moves) { x += m[0]; y += m[1]; fire(chart, 'mousemove', x, y); frame(chart); }
    fire(chart, 'mouseup', x, y);
    chart._api.dispatchAction = orig;
    return { press: [Math.round(b.x + b.width / 2), Math.round(b.y + b.height / 2)], dispatched: log };
  },
  'sankey-trigger': (chart, c) => {
    chart.dispatchAction({ type: 'dragNode', seriesIndex: 0, dataIndex: 3, localX: c.localD, localY: 0.2 });
    frame(chart);
    const s = seriesOf(chart, 'sankey');
    const probes = [];
    const box = s.layoutInfo;
    const pts = [[box.x + box.width + 5, box.y + box.height * 0.1], [box.x + box.width + 40, box.y + 10],
      [box.x - 20, box.y + 20], [box.x + 3, box.y + box.height - 3], [box.x + box.width * 1.25, box.y + box.height * 0.5]];
    for (const p of pts) {
      const x = Math.round(p[0]), y = Math.round(p[1]);
      let panned = false;
      const orig = chart._api.dispatchAction;
      chart._api.dispatchAction = function (q) { if (q.type === 'sankeyRoam') panned = true; return orig.apply(this, arguments); };
      fire(chart, 'mousedown', x, y);
      fire(chart, 'mousemove', x + 20, y + 5);
      fire(chart, 'mouseup', x + 20, y + 5);
      chart._api.dispatchAction = orig;
      if (panned) {
        // back where it was: the next probe starts from the same view
        chart.dispatchAction({ type: 'sankeyRoam', seriesIndex: 0, dx: -20, dy: -5 });
      }
      frame(chart);
      probes.push({ x, y, panned });
    }
    return { box: [box.x, box.y, box.width, box.height], probes };
  },
  'polar-brush': (chart, c) => {
    let sel = null;
    chart.on('brushselected', e => { sel = e.batch[0].selected.map(s => ({ seriesIndex: s.seriesIndex, dataIndex: s.dataIndex.slice() })); });
    chart.dispatchAction({ type: 'brush', areas: clone(c.areas) });
    frame(chart);
    must(sel, 'no brushselected');
    return { selected: sel };
  },
  'gesture-brush': (chart, c) => {
    const s = seriesOf(chart, c.pick);
    const d = s.getData();
    let pt = null;
    if (c.pick === 'sunburst') {
      d.each(i => {
        if (pt) return;
        const el = d.getItemGraphicEl(i);
        if (!el || d.getName(i) !== 'A') return;
        const sh = el.shape, a = (sh.startAngle + sh.endAngle) / 2, r = (sh.r0 + sh.r) / 2;
        pt = [Math.round(sh.cx + r * Math.cos(a)), Math.round(sh.cy + r * Math.sin(a))];
      });
    } else if (c.pick === 'treemap') {
      d.each(i => {
        if (pt) return;
        if (d.getName(i) !== 'a1') return;
        const el = d.getItemGraphicEl(i);
        const b = el.getBoundingRect().clone();
        b.applyTransform(el.getComputedTransform());
        pt = [Math.round(b.x + b.width / 2), Math.round(b.y + b.height / 2)];
      });
    } else {
      d.each(i => {
        if (pt) return;
        if (d.getName(i) !== 'A') return;
        const el = d.getItemGraphicEl(i);
        const m = el.getComputedTransform();
        pt = [Math.round(m[4]), Math.round(m[5])];
      });
    }
    must(pt, 'no point to click');
    const ev = [];
    chart.on('brushselected', () => ev.push('brushselected'));
    chart.on('updated', () => ev.push('updated'));
    fire(chart, 'mousemove', pt[0], pt[1]);
    fire(chart, 'mousedown', pt[0], pt[1]);
    fire(chart, 'mouseup', pt[0], pt[1]);
    fire(chart, 'click', pt[0], pt[1]);
    frame(chart);
    return { click: pt, events: ev };
  }
};

function run(c) {
  const chart = mk(c.W, c.H);
  try {
    chart.setOption(clone(c.option));
    frame(chart);
    const rec = RUN[c.group](chart, c);
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option };
    ['node', 'moves', 'localD', 'areas', 'pick'].forEach(k => { if (c[k] !== undefined) out[k] = c[k]; });
    return Object.assign(out, rec);
  } finally {
    chart.dispose();
  }
}

function guards(out) {
  const g = [];
  const guard = (name, ok) => { must(ok, 'guard failed: ' + name); g.push(name); };
  const byId = id => out.cases.find(c => c.id === id);
  const sd = byId('sd-drag').dispatched;
  guard('the dragNode payload names the model by seriesId', sd.length === 2 && sd.every(p => p.seriesId && p.keys.indexOf('seriesIndex') < 0));
  const st = byId('st-self');
  const bx = st.box;
  const inBox = p => p.x >= bx[0] && p.x <= bx[0] + bx[2] && p.y >= bx[1] && p.y <= bx[1] + bx[3];
  guard('outside the view box yet in the group\'s own box: pans', st.probes.some(p => !inBox(p) && p.panned));
  guard('outside both: does not', st.probes.some(p => !inBox(p) && !p.panned));
  const pr = byId('pb-rect').selected;
  guard('a rect selects every polar bar', pr.length === 2 && pr[0].dataIndex.length === 3 && pr[1].dataIndex.length === 3);
  guard('a lineX selects none', byId('pb-linex').selected.every(s => s.dataIndex.length === 0));
  for (const id of ['gb-sunburst', 'gb-treemap', 'gb-tree'])
    guard(id + ' brings a brushselected', byId(id).events.indexOf('brushselected') >= 0);
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
  must(a.indexOf('\\u0000') < 0, 'a NUL in the output');
  JSON.parse(a);
  fs.writeFileSync(OUT, a);
  console.log('wrote', OUT, cases.length, 'cases');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  process.exit(1);
}
