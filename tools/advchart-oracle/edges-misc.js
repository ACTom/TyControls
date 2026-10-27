/*
Upstream's own answers for fix batch R5-J (spec section 244b): THE LAST
EDGES OF ROUND FIVE.

  events    every event type chart.on hears. `public`: the types whose
            chart.on handler fires when the chart's message centre triggers
            them -- registerAction's publicEventTypeMap, forwarded in
            _initEvents; `connectOnly`: the message centre's other types
            (enableConnect's listeners: the axis breaks' non-refined
            expandaxisbreak, collapseaxisbreak, toggleaxisbreak); `legacy`:
            the pie / map select events handleLegacySelectEvents triggers on
            the chart itself, each seen fire on a pie. Then cases: a chart,
            three handlers for every public type and `updated` -- a plain
            one, one with the query 'series.nosuch', one with
            {seriesIndex: 5} (an action event has no eventInfo, so no query
            filters it) -- and steps (an action dispatched, a click, a drag,
            a wheel); each step's log: [handler, type, payload] in the order
            they fired, the payload as JSON with `from` (a view's uid) as
            '<from>'.
  append    object items appendData pushes onto a scatter, against the same
            items written in the option from the start (the axes fixed so
            the extents agree): each row's symbol type, its scale (the
            symbol's size / 2), rotation, fill, and its label's text.

Each case is a chart, animation off, 600 x 400 unless it says otherwise.

  node tools/advchart-oracle/edges-misc.js

writes tests/fixtures/advchart-edges-misc.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-misc.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W || 600, height: H || 400 });
  chart._ssr = false;
  return chart;
}
function frame(chart) {
  chart.getZr().storage.getDisplayList(true);
  chart.renderToSVGString();
}
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function zr(chart, name, extra) { chart.getZr().handler.dispatch(name, zev(extra)); }

// ---- events ----
const QUERIES = [['plain', undefined], ['q1', 'series.nosuch'], ['q2', { seriesIndex: 5 }]];
function payloadText(p) {
  // an auto id's NULs as '^' (the fixture holds no NUL: fpjson drops it)
  return JSON.stringify(p, (k, v) => (k === 'from' && typeof v === 'string' ? '<from>' : v)).split('\\u0000').join('^');
}
function publicTypes() {
  const chart = mk();
  try {
    const keys = Object.keys(chart._messageCenter._$handlers).sort();
    const pub = [];
    const conn = [];
    for (const t of keys) {
      let heard = 0;
      const fn = () => { heard++; };
      chart.on(t, fn);
      chart._messageCenter.trigger(t, { type: t });
      chart.off(t, fn);
      (heard ? pub : conn).push(t);
    }
    return { pub, conn };
  }
  finally {
    chart.dispose();
  }
}
const LEGACY = ['pieselectchanged', 'pieselected', 'pieunselected', 'mapselectchanged', 'mapselected', 'mapunselected'];
function legacySeen() {
  // handleSeriesLegacySelectEvents walks the pie series (for the map's
  // names too): a pie fires both families
  const chart = mk();
  const seen = [];
  try {
    chart.setOption({ animation: false, series: [{ type: 'pie', selectedMode: 'multiple', data: [{ name: 'a', value: 1 }, { name: 'b', value: 2 }] }] });
    frame(chart);
    for (const t of LEGACY) chart.on(t, () => { if (!seen.includes(t)) seen.push(t); });
    // the legacy events go to a series that still holds a selection
    chart.dispatchAction({ type: 'select', seriesIndex: 0, dataIndex: [0, 1] });
    chart.dispatchAction({ type: 'unselect', seriesIndex: 0, dataIndex: 0 });
    // the click's (isFromClick) on the slice not selected: it selects
    const el = chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(0);
    const c = el.getBoundingRect().clone();
    c.applyTransform(el.getComputedTransform());
    const x = Math.round(c.x + c.width / 2), y = Math.round(c.y + c.height / 2);
    zr(chart, 'mousemove', { zrX: x, zrY: y });
    zr(chart, 'mousedown', { zrX: x, zrY: y });
    zr(chart, 'mouseup', { zrX: x, zrY: y });
    zr(chart, 'click', { zrX: x, zrY: y });
    return seen.sort();
  }
  finally {
    chart.dispose();
  }
}
function globalOf(el) {
  const r = el.getBoundingRect().clone();
  r.applyTransform(el.getComputedTransform());
  return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
}
const TREE = { name: 'r', children: [{ name: 'a', children: [{ name: 'a1' }, { name: 'a2' }] }, { name: 'b', children: [{ name: 'b1' }] }] };
const EVENT_CASES = [
  { id: 'ev-cartesian', note: 'the toolbox, the dataZoom, the tooltip, the axis pointer and the graph-less adjacency actions on a bar chart',
    option: { animation: false, tooltip: { trigger: 'axis' }, toolbox: { feature: { dataView: {}, magicType: { type: ['line', 'bar'] }, restore: {} } },
      dataZoom: [{ type: 'inside' }], xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: {}, series: [{ type: 'bar', id: 's0', data: [1, 2, 3] }] },
    steps: [{ action: { type: 'dataZoom', start: 10, end: 60 } }, { action: { type: 'restore' } },
      { action: { type: 'changeMagicType', currentType: 'line', newOption: {} } }, { action: { type: 'changeDataView', newOption: {} } },
      { action: { type: 'showTip', seriesIndex: 0, dataIndex: 1 } }, { action: { type: 'hideTip' } },
      { action: { type: 'updateAxisPointer', currTrigger: 'leave' } },
      { action: { type: 'focusNodeAdjacency', seriesIndex: 0, dataIndex: 1 } }, { action: { type: 'unfocusNodeAdjacency', seriesIndex: 0 } }] },
  { id: 'ev-tree', note: "a tree: its actions, a node's click (TreeView dispatches treeExpandAndCollapse), a drag and a wheel (its RoamController dispatches treeRoam)",
    option: { animation: false, series: [{ type: 'tree', id: 's0', roam: true, initialTreeDepth: -1, data: [TREE], left: 60, right: 60, top: 40, bottom: 40 }] },
    steps: [{ action: { type: 'treeExpandAndCollapse', seriesIndex: 0, dataIndex: 2 } },
      { action: { type: 'treeRoam', seriesIndex: 0, dx: 10, dy: -5 } }, { action: { type: 'treeRoam', zoom: 1.5, originX: 300, originY: 200 } },
      { click: 5 }, { drag: [[20, 20], [35, 28], [50, 31]] }, { wheel: [300, 200, 120] }] },
  { id: 'ev-graph', note: "a graph (layout none): its roam through the action and through the RoamController's drag and wheel",
    option: { animation: false, series: [{ type: 'graph', id: 's0', layout: 'none', roam: true, symbolSize: 20,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 30 }, { name: 'c', x: 40, y: 90 }], links: [{ source: 'a', target: 'b' }] }] },
    steps: [{ action: { type: 'graphRoam', dx: 12, dy: 7 } }, { drag: [[300, 200], [315, 210], [330, 222]] }, { wheel: [300, 200, -120] }] },
  { id: 'ev-sankey', note: "a sankey with roam: the RoamController's drag and wheel dispatch sankeyRoam",
    option: { animation: false, series: [{ type: 'sankey', id: 's0', roam: true, left: 100, right: 100, top: 80, bottom: 80,
      data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }], links: [{ source: 'a', target: 'b', value: 3 }, { source: 'a', target: 'c', value: 2 }] }] },
    steps: [{ drag: [[300, 200], [310, 210], [320, 214]] }, { wheel: [300, 200, 120] }, { action: { type: 'sankeyRoam', dx: -8, dy: 4 } }] },
];
function runEventCase(def, types) {
  const chart = mk();
  const log = [];
  try {
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    frame(chart);
    for (const t of types.concat(['updated'])) {
      for (const [h, q] of QUERIES) {
        const fn = p => log.push([h, t, p === undefined ? '' : payloadText(p)]);
        if (q === undefined) chart.on(t, fn); else chart.on(t, JSON.parse(JSON.stringify(q)), fn);
      }
    }
    const steps = [];
    for (const st of def.steps) {
      log.length = 0;
      const rec = Object.assign({}, st);
      if (st.action) chart.dispatchAction(JSON.parse(JSON.stringify(st.action)));
      else if (st.click != null) {
        const el = chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(st.click);
        must(el, def.id + ': no item ' + st.click);
        const [x, y] = globalOf(el);
        rec.at = [x, y];
        zr(chart, 'mousemove', { zrX: x, zrY: y });
        zr(chart, 'mousedown', { zrX: x, zrY: y });
        zr(chart, 'mouseup', { zrX: x, zrY: y });
        zr(chart, 'click', { zrX: x, zrY: y });
      }
      else if (st.drag) {
        const p = st.drag;
        zr(chart, 'mousemove', { zrX: p[0][0], zrY: p[0][1] });
        zr(chart, 'mousedown', { zrX: p[0][0], zrY: p[0][1] });
        for (let i = 1; i < p.length; i++) zr(chart, 'mousemove', { zrX: p[i][0], zrY: p[i][1] });
        zr(chart, 'mouseup', { zrX: p[p.length - 1][0], zrY: p[p.length - 1][1] });
      }
      else if (st.wheel) zr(chart, 'mousewheel', { zrX: st.wheel[0], zrY: st.wheel[1], zrDelta: st.wheel[2] / 120 });
      frame(chart);
      rec.log = log.slice();
      steps.push(rec);
    }
    return { id: def.id, note: def.note, option: def.option, steps };
  }
  finally {
    chart.dispose();
  }
}

// ---- append ----
const AP_HEAD = [[1, 2], { value: [3, 9], symbol: 'rect', symbolSize: 16 }, [5, 4]];
const AP_TAIL = [[20, 3], { value: [21, 6], symbol: 'triangle', symbolSize: [16, 10], symbolRotate: 30, itemStyle: { color: '#ff0000' },
  label: { show: true, formatter: 'M' } }, { value: [24, 2], symbol: 'diamond', symbolOffset: [4, -2], itemStyle: { opacity: 0.5 } }];
function apOption(data) {
  return { animation: false, xAxis: { min: 0, max: 30 }, yAxis: { min: 0, max: 12 },
    series: [{ type: 'scatter', symbolSize: 8, data }] };
}
function symRecs(chart) {
  const d = chart.getModel().getSeriesByIndex(0).getData();
  const out = [];
  for (let i = 0; i < d.count(); i++) {
    const g = d.getItemGraphicEl(i);
    if (!g) { out.push(null); continue; }
    const p = g.childAt(0);
    const tc = p.getTextContent();
    out.push({ symbol: p.shape.symbolType, sx: hex(p.scaleX), sy: hex(p.scaleY), rotation: hex(p.rotation),
      x: hex(g.x + p.x), y: hex(g.y + p.y), fill: p.style.fill, opacity: hex(p.style.opacity == null ? 1 : p.style.opacity),
      label: tc && !tc.ignore ? tc.style.text : null });
  }
  return out;
}
function runAppend() {
  const a = mk(400, 300);
  const b = mk(400, 300);
  try {
    a.setOption(apOption(AP_HEAD.concat(AP_TAIL)));
    frame(a);
    b.setOption(apOption(AP_HEAD.slice()));
    frame(b);
    b.appendData({ seriesIndex: 0, data: JSON.parse(JSON.stringify(AP_TAIL)) });
    for (let i = 0; i < 4; i++) b._onframe();
    frame(b);
    const written = symRecs(a);
    const appended = symRecs(b);
    b.setOption({});
    frame(b);
    const updated = symRecs(b);
    return { W: 400, H: 300, head: AP_HEAD, tail: AP_TAIL, written, appended, updated };
  }
  finally {
    a.dispose();
    b.dispose();
  }
}

// ---- river: themeRiverLayout writes the parsePercent results back into
// the model's own boundaryGap array; a merge that writes boundaryGap -- the
// same text too -- replaces the array (zrUtil.merge clones an array over),
// which the next layout parses at the size it has then ----
const RIVER = { animation: false, singleAxis: { type: 'time', top: 40, bottom: 40 },
  series: [{ type: 'themeRiver', boundaryGap: ['10%', '20%'], data: [['2020/01/01', 10, 'A'], ['2020/01/02', 20, 'A'], ['2020/01/03', 15, 'A'],
    ['2020/01/01', 5, 'B'], ['2020/01/02', 8, 'B'], ['2020/01/03', 12, 'B']] }] };
function runRiverRemerge() {
  const chart = mk();
  const steps = [];
  try {
    chart.setOption(JSON.parse(JSON.stringify(RIVER)));
    frame(chart);
    const rec = (what, op) => {
      frame(chart);
      const li = chart.getModel().getSeriesByIndex(0).getData().getLayout('layoutInfo');
      steps.push({ what, op, gap: li.boundaryGap.map(hex), rectH: hex(li.rect.height) });
    };
    rec('first', null);
    chart.resize({ width: 600, height: 300 });
    rec('resized to 300', { resize: [600, 300] });
    chart.setOption({ series: [{ boundaryGap: ['10%', '20%'] }] });
    rec('merged, the same boundaryGap', { merge: { series: [{ boundaryGap: ['10%', '20%'] }] } });
    chart.resize({ width: 600, height: 400 });
    rec('resized back', { resize: [600, 400] });
    chart.setOption({ series: [{ name: 'river' }] });
    rec('merged, no boundaryGap', { merge: { series: [{ name: 'river' }] } });
    chart.resize({ width: 600, height: 250 });
    rec('resized to 250', { resize: [600, 250] });
    chart.setOption({ series: [{ boundaryGap: [0, '5%'] }] });
    rec('merged, another boundaryGap', { merge: { series: [{ boundaryGap: [0, '5%'] }] } });
    return { option: RIVER, steps };
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const types = publicTypes();
  return {
    source: 'ECharts ' + echarts.version,
    events: { public: types.pub, connectOnly: types.conn, legacy: legacySeen(),
      rendering: ['rendered', 'finished', 'updated'],
      mouse: ['click', 'dblclick', 'mouseover', 'mouseout', 'mousemove', 'mousedown', 'mouseup', 'globalout', 'contextmenu'],
      queries: QUERIES.map(([h, q]) => ({ h, query: q === undefined ? null : q })),
      cases: EVENT_CASES.map(c => runEventCase(c, types.pub)) },
    append: runAppend(),
    river: runRiverRemerge(),
  };
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1);
  json2 = JSON.stringify(generate());
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const ev = out1.events;
const caseOf = id => ev.cases.find(c => c.id === id);
const fired = (c, k, t) => caseOf(c).steps[k].log.filter(l => l[1] === t);
const guards = [
  { name: 'events: the axis breaks\' non-refined types are connect-only; axisbreakchanged is public',
    ok: ['expandaxisbreak', 'collapseaxisbreak', 'toggleaxisbreak'].every(t => ev.connectOnly.includes(t)) && ev.public.includes('axisbreakchanged')
      && ev.connectOnly.length === 3 },
  { name: 'events: the seven the port kept from ChartOn are public',
    ok: ['datazoom', 'restore', 'magictypechanged', 'dataviewchanged', 'showtip', 'hidetip', 'updateaxispointer'].every(t => ev.public.includes(t)) },
  { name: 'events: every legacy select event fires', ok: ev.legacy.length === 6 },
  { name: 'events: no query filters an action event (each fired thrice)',
    ok: ev.cases.every(c => c.steps.every(s => ['plain', 'q1', 'q2'].every(h => s.log.filter(l => l[0] === h).length === s.log.filter(l => l[0] === 'plain').length))) },
  { name: 'events: the datazoom action publishes datazoom then updated',
    ok: JSON.stringify(fired('ev-cartesian', 0, 'datazoom').map(l => l[0])) === '["plain","q1","q2"]' && fired('ev-cartesian', 0, 'updated').length === 3 },
  { name: 'events: focusNodeAdjacency on no graph still publishes its event',
    ok: fired('ev-cartesian', 7, 'focusnodeadjacency').length === 3 && fired('ev-cartesian', 8, 'unfocusnodeadjacency').length === 3 },
  { name: 'events: the tree action publishes treeexpandandcollapse and one updated',
    ok: fired('ev-tree', 0, 'treeexpandandcollapse').length === 3 && fired('ev-tree', 0, 'updated').length === 3 },
  { name: 'events: the tree click publishes treeexpandandcollapse with the seriesId',
    ok: fired('ev-tree', 3, 'treeexpandandcollapse').length === 3 && JSON.parse(fired('ev-tree', 3, 'treeexpandandcollapse')[0][2]).dataIndex === 5 },
  { name: 'events: the tree drag and wheel publish treeroam',
    ok: fired('ev-tree', 4, 'treeroam').length > 0 && fired('ev-tree', 5, 'treeroam').length === 3 },
  { name: 'events: the graph drag and wheel publish graphroam with payloadDisableAnimation',
    ok: fired('ev-graph', 1, 'graphroam').length > 0 && JSON.parse(fired('ev-graph', 2, 'graphroam')[0][2]).animation.duration === 0 },
  { name: 'events: the sankey drag and wheel publish sankeyroam',
    ok: fired('ev-sankey', 0, 'sankeyroam').length > 0 && fired('ev-sankey', 1, 'sankeyroam').length === 3 },
  { name: 'append: every appended row is the written one',
    ok: JSON.stringify(out1.append.appended) === JSON.stringify(out1.append.written)
      && JSON.stringify(out1.append.updated) === JSON.stringify(out1.append.written) },
  { name: 'append: the triangle, its rotation, colour and label; the diamond',
    ok: out1.append.written[4].symbol === 'triangle' && out1.append.written[4].fill === '#ff0000' && out1.append.written[4].label === 'M'
      && out1.append.written[5].symbol === 'diamond' },
  { name: 'river: the same boundaryGap merged again is resolved at the new size; no boundaryGap keeps the px',
    ok: (s => s[1].gap[0] === s[0].gap[0] && s[2].gap[0] !== s[1].gap[0] && s[3].gap[0] === s[2].gap[0] && s[4].gap[0] === s[3].gap[0]
      && s[5].gap[0] === s[4].gap[0] && s[6].gap[0] !== s[5].gap[0])(out1.river.steps) },
];
out1.guards = guards.map(g => ({ name: g.name, ok: !!g.ok }));
console.log('public: ' + ev.public.length + ' ' + JSON.stringify(ev.public));
console.log('connectOnly: ' + JSON.stringify(ev.connectOnly) + ' legacy: ' + JSON.stringify(ev.legacy));
ev.cases.forEach(c => c.steps.forEach((s, k) => console.log(c.id + ' ' + k + ': ' + JSON.stringify(s.log.filter(l => l[0] === 'plain').map(l => l[1] + ' ' + l[2])))));
console.log('river: ' + JSON.stringify(out1.river.steps.map(s => [s.what, s.gap, s.rectH])));
console.log('append: ' + JSON.stringify(out1.append.appended.map(r => r && [r.symbol, r.fill, r.label])));
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
const final = JSON.stringify(out1, null, 1) + '\n';
if (bad.length || json1 !== json2 || final.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written' + (json1 !== json2 ? ' (two generations differ)' : ''));
  process.exit(1);
}
fs.writeFileSync(OUT, final);
console.log('wrote', OUT);
process.exit(0);
