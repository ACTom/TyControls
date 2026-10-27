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

// ---- splitArea: a gradient written as an area's colour. Cartesian and
// single axes add one Rect per band (rectCoordAxisBuildSplitArea): the
// gradient spans each band's own rect; polar axes and the radar merge
// every band of one colour into one path (mergePath): the gradient spans
// the merged path's bounding rect. Recorded per filled element of the
// view: its kind, its box (getBoundingRect -- no stroke, a fill only), the
// canvas gradient over it (non-global: x * width + x0 ...) with its stops,
// and pixels inside it that nothing else of the chart covers ----
const GR_V = { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: '#ff0000' }, { offset: 1, color: '#0000ff' }] };
const GR_H = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#00c000' }, { offset: 1, color: '#ffff00' }] };
const HIDDEN = { showSymbol: false, lineStyle: { opacity: 0 } };
const SA_CASES = [
  { id: 'sa-value', note: 'a value y axis, the list [vertical gradient, grey]: every other band its own vertical ramp',
    option: { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'], splitArea: { show: false } },
      yAxis: { type: 'value', splitLine: { show: false }, splitArea: { show: true, areaStyle: { color: [GR_V, '#dddddd'] } } },
      series: [Object.assign({ type: 'line', data: [10, 50, 30, 80] }, HIDDEN)] }, axes: [['yAxis', 0]] },
  { id: 'sa-category', note: 'a category x axis, one horizontal gradient: each band its own horizontal ramp',
    option: { xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'], splitArea: { show: true, areaStyle: { color: GR_H } } },
      yAxis: { type: 'value', splitLine: { show: false } },
      series: [Object.assign({ type: 'line', data: [10, 50, 30, 80] }, HIDDEN)] }, axes: [['xAxis', 0]] },
  { id: 'sa-single', note: 'a single axis, [horizontal gradient, grey]',
    option: { singleAxis: { type: 'value', min: 0, max: 100, top: 100, bottom: 100, splitLine: { show: false }, splitArea: { show: true, areaStyle: { color: [GR_H, '#dddddd'] } } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', symbolSize: 0, data: [50] }] }, axes: [['singleAxis', 0]] },
  { id: 'sa-angle', note: 'a polar angle axis, [vertical gradient, grey]: the bands of each colour merged, one ramp over their box',
    option: { polar: { radius: ['20%', '70%'] }, angleAxis: { type: 'value', min: 0, max: 360, interval: 60, splitLine: { show: false }, axisLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false },
      splitArea: { show: true, areaStyle: { color: [GR_V, '#dddddd'] } } }, radiusAxis: { type: 'value', show: false },
      series: [Object.assign({ type: 'line', coordinateSystem: 'polar', data: [[1, 10]] }, HIDDEN)] }, axes: [['angleAxis', 0]] },
  { id: 'sa-radius', note: 'a polar radius axis, [horizontal gradient, grey]: the rings of each colour merged',
    option: { polar: { radius: ['0%', '70%'] }, angleAxis: { type: 'value', show: false }, radiusAxis: { type: 'value', min: 0, max: 100, interval: 20, splitLine: { show: false },
      axisLine: { show: false }, axisTick: { show: false }, axisLabel: { show: false }, splitArea: { show: true, areaStyle: { color: [GR_H, '#dddddd'] } } },
      series: [Object.assign({ type: 'line', coordinateSystem: 'polar', data: [[10, 1]] }, HIDDEN)] }, axes: [['radiusAxis', 0]] },
  { id: 'sa-radar', note: 'a radar (polygon), [vertical gradient, grey]: RadarView merges the bands of one colour',
    option: { radar: { radius: '70%', splitNumber: 4, axisName: { show: false }, axisLine: { show: false }, splitLine: { show: false },
      splitArea: { show: true, areaStyle: { color: [GR_V, '#dddddd'] } }, indicator: [{ max: 10 }, { max: 10 }, { max: 10 }, { max: 10 }, { max: 10 }] },
      series: [{ type: 'radar', symbol: 'none', lineStyle: { opacity: 0 }, data: [{ value: [1, 1, 1, 1, 1] }] }] }, axes: [['radar', 0]] },
  { id: 'sa-radar-circle', note: 'a radar (circle), one horizontal gradient for every ring',
    option: { radar: { shape: 'circle', radius: '70%', splitNumber: 4, axisName: { show: false }, axisLine: { show: false }, splitLine: { show: false },
      splitArea: { show: true, areaStyle: { color: GR_H } }, indicator: [{ max: 10 }, { max: 10 }, { max: 10 }, { max: 10 }] },
      series: [{ type: 'radar', symbol: 'none', lineStyle: { opacity: 0 }, data: [{ value: [1, 1, 1, 1] }] }] }, axes: [['radar', 0]], rings: true },
];
function gradOver(fill, r) {
  return [fill.x * r.width + r.x, fill.y * r.height + r.y, fill.x2 * r.width + r.x, fill.y2 * r.height + r.y];
}
function runSplitAreas() {
  return SA_CASES.map(def => {
    const chart = mk();
    try {
      chart.setOption(Object.assign({ animation: false }, JSON.parse(JSON.stringify(def.option))));
      frame(chart);
      const all = chart.getZr().storage.getDisplayList(true);
      const els = [];
      // a circle radar's rings meet inside one merged path; the port draws
      // a ring an element (no seam upstream, an antialiased one there):
      // pixels within 1.5 px of a ring are not sampled
      let nearRing = () => false;
      if (def.rings) {
        const rc = chart.getModel().getComponent('radar', 0).coordinateSystem;
        const radii = rc.getIndicatorAxes()[0].getTicksCoords().map(c => c.coord);
        nearRing = (x, y) => radii.some(r => Math.abs(Math.hypot(x - rc.cx, y - rc.cy) - r) < 1.5);
      }
      for (const [mt, idx] of def.axes) {
        const view = chart.getViewOfComponentModel(chart.getModel().getComponent(mt, idx));
        view.group.traverse(el => {
          if (el.isGroup || !el.style || !el.style.fill || typeof el.style.fill !== 'object' || !el.style.fill.colorStops) return;
          const r = el.getBoundingRect();
          const g = gradOver(el.style.fill, r);
          // pixels whose centre only this element covers, on a grid over its box
          const samples = [];
          for (let iy = 1; iy < 8; iy++) {
            for (let ix = 1; ix < 8; ix++) {
              const px = Math.floor(r.x + r.width * ix / 8), py = Math.floor(r.y + r.height * iy / 8);
              let mine = true;
              for (const [dx, dy] of [[0.5, 0.5], [0, 0], [1, 0], [0, 1], [1, 1]]) {
                if (!el.contain(px + dx, py + dy) || nearRing(px + dx, py + dy)) mine = false;
                for (const o of all) if (o !== el && !o.ignore && !o.invisible && o.contain && o.contain(px + dx, py + dy)) mine = false;
              }
              if (mine) samples.push([px, py]);
            }
          }
          els.push({ kind: el.type, rect: [hex(r.x), hex(r.y), hex(r.width), hex(r.height)], gradient: g.map(hex),
            stops: el.style.fill.colorStops.map(s => [s.offset, s.color]), samples });
        });
      }
      return { id: def.id, note: def.note, option: def.option, elements: els };
    }
    finally {
      chart.dispose();
    }
  });
}

// ---- zlevel: a component's own zlevel (retrieveZInfo: model.get('zlevel')
// || 0 -- a title's, a legend's, a toolbox's default 0; an axis has none of
// its own and reads the option root's) layers it, and zrender's handler
// finds the hover from the top of the sorted display list, zlevel first; the
// loading mask (zlevel 0 unless written, z 10000) is one more displayable.
// Per probe point: the component whose element is drawn on top there
// (draw) and the one findHover answers (hit; null for none) ----
const ZBOX = { type: 'value', min: 0, max: 10 };
const ZSYM = (extra) => Object.assign({ type: 'scatter', symbol: 'rect', symbolSize: 120, itemStyle: { color: '#0000ff', opacity: 1 }, data: [[5, 5]] }, extra);
const ZTITLE = (extra) => Object.assign({ text: 'TITLE', triggerEvent: true, left: 250, top: 175, textStyle: { fontSize: 40, color: '#00c000' },
  backgroundColor: '#00ff00', padding: 10 }, extra);
const ZL_CASES = [
  { id: 'zl-title-above', note: 'a title of zlevel 2 over a series of zlevel 1: drawn and hit over it',
    option: { title: ZTITLE({ zlevel: 2 }), xAxis: ZBOX, yAxis: ZBOX, series: [ZSYM({ zlevel: 1 })] }, probes: [['title', 0]] },
  { id: 'zl-title-under', note: 'a title of the default zlevel (0, whatever z) under a series of zlevel 1',
    option: { title: ZTITLE({}), xAxis: ZBOX, yAxis: ZBOX, series: [ZSYM({ zlevel: 1 })] }, probes: [['title', 0]] },
  { id: 'zl-root', note: "the root's zlevel 1: the axes (no zlevel of their own) take it, the series and the title (theirs, 0) do not: the axis line over the bar, the title under the axes",
    option: { zlevel: 1, title: ZTITLE({ top: 300, left: 40 }), xAxis: { type: 'category', data: ['a', 'b'], axisLine: { lineStyle: { color: '#ff0000', width: 6 } } }, yAxis: ZBOX,
      series: [{ type: 'bar', barWidth: '90%', itemStyle: { color: '#0000ff' }, data: [5, 5] }] }, probes: [['xAxisLine', 0], ['title', 0]] },
  { id: 'zl-axis', note: 'an x axis of zlevel 2 over a bar of the default zlevel',
    option: { xAxis: { type: 'category', data: ['a', 'b'], zlevel: 2, axisLine: { lineStyle: { color: '#ff0000', width: 6 } } }, yAxis: ZBOX,
      series: [{ type: 'bar', barWidth: '90%', itemStyle: { color: '#0000ff' }, data: [5, 5] }] }, probes: [['xAxisLine', 0]] },
  { id: 'zl-axis-default', note: 'the same at the default zlevel: the bar (z 2) over the axis (z 0)',
    option: { xAxis: { type: 'category', data: ['a', 'b'], axisLine: { lineStyle: { color: '#ff0000', width: 6 } } }, yAxis: ZBOX,
      series: [{ type: 'bar', barWidth: '90%', itemStyle: { color: '#0000ff' }, data: [5, 5] }] }, probes: [['xAxisLine', 0]] },
  { id: 'zl-legend', note: 'a legend of zlevel 2 over a series of zlevel 1',
    option: { legend: { zlevel: 2, left: 250, top: 190, itemWidth: 60, itemHeight: 30, itemStyle: { color: '#ff00ff' }, data: ['s'] }, xAxis: ZBOX, yAxis: ZBOX,
      series: [ZSYM({ name: 's', zlevel: 1 })] }, probes: [['legendItem', 0]] },
  { id: 'zl-toolbox', note: 'a toolbox of zlevel 2 over a series of zlevel 1: its icon is the hover',
    option: { toolbox: { zlevel: 2, left: 280, top: 180, itemSize: 40, feature: { restore: {} } }, xAxis: ZBOX, yAxis: ZBOX,
      series: [ZSYM({ zlevel: 1 })] }, probes: [['toolboxIcon', 0]] },
  { id: 'zl-mask', note: 'the loading mask (zlevel 0) under a series of zlevel 1: the symbol is drawn and hit over it; off the symbol the mask',
    option: { xAxis: ZBOX, yAxis: ZBOX, series: [ZSYM({ zlevel: 1 })] }, loading: {}, probes: [['symbol', 0], ['point', [60, 60]]] },
  { id: 'zl-mask-high', note: 'a loading mask of zlevel 2 over the series of zlevel 1',
    option: { xAxis: ZBOX, yAxis: ZBOX, series: [ZSYM({ zlevel: 1 })] }, loading: { zlevel: 2 }, probes: [['symbol', 0]] },
  { id: 'zl-graphic', note: 'a graphic rect of zlevel 2 over a title of zlevel 1 (the title over the series of 0)',
    option: { title: ZTITLE({ zlevel: 1 }), graphic: { elements: [{ type: 'rect', zlevel: 2, left: 300, top: 195, shape: { width: 40, height: 20 },
      style: { fill: '#ff00ff' } }] }, xAxis: ZBOX, yAxis: ZBOX, series: [ZSYM({})] }, probes: [['point', [315, 205]]] },
  { id: 'zl-progressive', note: 'a large progressive scatter of zlevel 1 drawn chunk by chunk over a title of the default zlevel: its points over the title once drawn',
    option: { title: ZTITLE({}), xAxis: ZBOX, yAxis: ZBOX,
      series: [{ type: 'scatter', zlevel: 1, large: true, largeThreshold: 5, progressive: 4, progressiveThreshold: 5, symbol: 'rect', symbolSize: 30,
        itemStyle: { color: '#0000ff', opacity: 1 }, data: [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5], [6, 6], [7, 7], [8, 8], [5.4, 5], [9, 9]] }] },
    frames: 10, probes: [['point', [315, 205]]] },
];
function zlClassify(chart) {
  const owners = new Map();
  const model = chart.getModel();
  model.eachComponent((mt, m) => {
    const v = mt === 'series' ? chart.getViewOfSeriesModel(m) : chart.getViewOfComponentModel(m);
    if (v && v.group) owners.set(v.group, mt);
  });
  if (chart._loadingFX) owners.set(chart._loadingFX, 'mask');
  return el => {
    for (let e = el; e; e = e.__hostTarget || e.parent) if (owners.has(e)) return owners.get(e);
    return null;
  };
}
function zlProbePoint(chart, kind) {
  const what = kind[0], arg = kind[1];
  if (what === 'point') return arg;
  const centre = el => { const r = el.getBoundingRect().clone(); r.applyTransform(el.getComputedTransform()); return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]; };
  if (what === 'title') {
    let tx = null;
    chart.getViewOfComponentModel(chart.getModel().getComponent('title', 0)).group.traverse(e => { if (e.type === 'text' && !tx) tx = e; });
    return centre(tx);
  }
  if (what === 'symbol') return centre(chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(0));
  if (what === 'xAxisLine') {
    // the line, in the middle of the first bar
    const bar = chart.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(0);
    const r = bar.getBoundingRect().clone(); r.applyTransform(bar.getComputedTransform());
    return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height) - 1];
  }
  if (what === 'legendItem') {
    let icon = null;
    chart.getViewOfComponentModel(chart.getModel().getComponent('legend', 0)).group.traverse(e => { if (!icon && !e.isGroup && e.type !== 'text' && !e.silent) icon = e; });
    return centre(icon);
  }
  if (what === 'toolboxIcon') {
    let icon = null;
    chart.getViewOfComponentModel(chart.getModel().getComponent('toolbox', 0)).group.traverse(e => { if (!icon && !e.isGroup && e.type !== 'text') icon = e; });
    return centre(icon);
  }
  must(false, 'probe ' + what);
}
function runZLevels() {
  return ZL_CASES.map(def => {
    const chart = mk();
    try {
      chart.setOption(Object.assign({ animation: false }, JSON.parse(JSON.stringify(def.option))));
      if (def.loading) chart.showLoading(Object.assign({}, def.loading));
      frame(chart);
      // the progressive chunks, every one
      for (let i = 0; i < (def.frames || 0); i++) { chart._onframe(); frame(chart); }
      if (def.frames) must(!chart._scheduler.unfinished, def.id + ': chunks left');
      const owner = zlClassify(chart);
      const list = chart.getZr().storage.getDisplayList(true);
      const probes = def.probes.map(pk => {
        const at = zlProbePoint(chart, pk);
        const x = at[0], y = at[1];
        let draw = null;
        for (let i = list.length - 1; i >= 0; i--) {
          const el = list[i];
          if (el.ignore || el.invisible || !el.contain || !el.contain(x + 0.5, y + 0.5)) continue;
          if (el.style && el.style.opacity === 0) continue;
          draw = { comp: owner(el), zlevel: el.zlevel, z: el.z, type: el.type };
          break;
        }
        const t = chart.getZr().handler.findHover(x + 0.5, y + 0.5).target;
        return { at: [x, y], probe: pk[0], draw, hit: t ? { comp: owner(t), zlevel: t.zlevel, type: t.type } : null };
      });
      return { id: def.id, note: def.note, option: def.option, loading: def.loading || null, frames: def.frames || 0, probes };
    }
    finally {
      chart.dispose();
    }
  });
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
    splitArea: runSplitAreas(),
    zlevel: runZLevels(),
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
  { name: 'splitArea: a band per gradient Rect on the cartesian and single axes (two of four, four, five of ten)',
    ok: (c => c('sa-value').elements.length === 2 && c('sa-value').elements.every(e => e.kind === 'rect')
      && c('sa-category').elements.length === 4 && c('sa-single').elements.length >= 2)(id => out1.splitArea.find(x => x.id === id)) },
  { name: 'splitArea: one merged path per colour on the polar axes',
    ok: (c => c('sa-angle').elements.length === 1 && c('sa-angle').elements[0].kind === 'path'
      && c('sa-radius').elements.length === 1)(id => out1.splitArea.find(x => x.id === id)) },
  { name: 'splitArea: the radar merges too (one path per gradient colour)',
    ok: (c => c('sa-radar').elements.length === 1 && c('sa-radar-circle').elements.length === 1)(id => out1.splitArea.find(x => x.id === id)) },
  { name: 'splitArea: every element has pixels to sample', ok: out1.splitArea.every(c => c.elements.every(e => e.samples.length >= 4)) },
];
out1.guards = guards.map(g => ({ name: g.name, ok: !!g.ok }));
console.log('public: ' + ev.public.length + ' ' + JSON.stringify(ev.public));
console.log('connectOnly: ' + JSON.stringify(ev.connectOnly) + ' legacy: ' + JSON.stringify(ev.legacy));
ev.cases.forEach(c => c.steps.forEach((s, k) => console.log(c.id + ' ' + k + ': ' + JSON.stringify(s.log.filter(l => l[0] === 'plain').map(l => l[1] + ' ' + l[2])))));
console.log('river: ' + JSON.stringify(out1.river.steps.map(s => [s.what, s.gap, s.rectH])));
out1.splitArea.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.elements.map(e => [e.kind, e.rect, e.gradient, e.samples.length]))));
out1.zlevel.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.probes.map(p => [p.probe, p.at, p.draw && p.draw.comp, p.draw && p.draw.zlevel, p.hit && p.hit.comp]))));
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
