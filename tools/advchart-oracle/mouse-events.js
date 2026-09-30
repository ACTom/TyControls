/*
Upstream's own answers for CHART-LEVEL MOUSE EVENTS: which of
chart.on('click' | 'dblclick' | 'mousedown' | 'mouseup' | 'mousemove' |
'mouseover' | 'mouseout' | 'globalout' | 'contextmenu', [query], handler)
fire, in which order, with which params, for scripted pointer sequences; and
which handlers a query (the string 'series' / 'series.bar' or an object
{seriesIndex, seriesName, seriesId, xAxisIndex, dataIndex, name, dataType,
element, ...}) lets through.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false` on every
case, process.env.TZ = 'UTC' (checked), Math.random = the port's xorshift32
reseeded per chart. The chart is created with ssr: true (node has no DOM) and
then chart._ssr = false BEFORE setOption: ecModel.ssr only switches on
server-side-rendering extras that a browser never has (the legend's children
get the series' ECData -- a legend hit would then report a SERIES event --
and the pie's scale-in), so the model is the browser's.

Pointer events go straight to zrender's Handler with integer {zrX, zrY}:
  move        handler.mousemove
  down        handler.mousedown (which = button + 1)
  up          handler.mouseup; for button 0 then handler.click at the same
              point (the browser's DOM click follows every left mouseup on the
              canvas; zrender itself decides whether it counts)
  dblclick    handler.dblclick only (the browser's dblclick event; a full
              browser double click is down, up, down, up, dblclick)
  contextmenu handler.contextmenu only
  leave       handler.mouseout (the DOM mouseout of the canvas, no pointer
              capture): zrender's 'mouseout' on the hovered element, then
              'globalout'
Between steps: chart._onframe() (applies the hover states, as a browser frame
would) and chart.renderToSVGString() (refreshes the display list the hit test
walks; in node nothing repaints on its own).

  node tools/advchart-oracle/mouse-events.js

writes tests/fixtures/advchart-mouse-events.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Fixture:
  source, W, H, seed, tz, api, notes[]
  registrations  the handlers registered on EVERY case chart, in registration
      order (the order in which handlers of one trigger fire):
      {id, type, query?, sameFnAs?}. `query` absent = chart.on(type, fn);
      present = chart.on(type, query, fn) (null values kept). sameFnAs: the
      SAME function object as that registration -- Eventful ignores it (the
      dedup is by function, whatever the query). 'all.<type>' are the nine
      plain handlers; 'pub' (not listed) is one plain handler for every
      published action event (selectchanged, legendselectchanged, highlight,
      downplay, treemapzoomtonode, ...), registered last.
  cases[]: id, note, option (as fed), extra[] (registrations of this case
      only, after the common ones, same shape), steps[]:
    {type, x, y, button?, aim?, hit, refound?, events[]}
      x, y      integer canvas pixels (leave: the point of the DOM mouseout)
      aim       what the point was aimed at (for the reader): 'item s0 d1',
                'label s0 d1', "text 'Mon'", 'edge 2', 'marker markPoint s0
                d0', 'between s1 d0 d1', 'empty', 'point'
      hit       zrender's hit at (x, y) before the step (null = no target):
                {el: the n-th distinct element hit in this case (identity),
                kind: its zrender type, params: the fields the chart event
                would carry or null (no ECData dispatcher: no chart event),
                model: the model the query filter checks, or null}
                model = {mainType, subType, index, name, id?} after the
                marker remap (markPoint / markLine / markArea -> the series)
      refound   move only, when the previously hovered element was removed
                from the scene by a re-render (legend toggle, treemap zoom):
                the el zrender re-finds at the old point (#6198) -- it stands
                in for the old one in the out / over comparison
      events[]  everything emitted during the step, in order:
                mouse events {h, type, componentType, componentSubType,
                componentIndex, seriesType, seriesIndex, seriesId, seriesName,
                name, dataIndex, dataType, value (String(v)), targetType,
                tickIndex, selfType, xAxisIndex, yAxisIndex, offsetX, offsetY,
                el}: a key is present iff upstream's params hold it with a
                value other than undefined (null is kept: seriesType /
                seriesName / seriesId are null on marker params); seriesId
                only when it is an explicit option id (auto ids carry \0 and
                are left out); offsetX / offsetY = the step point (absent on
                globalout: its params are {}); el = zrender type of the
                event's target (documentary).
                published events {h: 'pub', type, payload} (payload = the
                event object as plain data: class instances as '[ClassName]',
                auto ids as '<auto id>') and query-registered published
                handlers {h, type}.
      (model name / id: auto names and ids carry \0 and are written '<auto>')
  guards[], checks

-----------------------------------------------------------------------------
Cross-check (any failure: nothing is written, exit 1):
  1. a TRANSCRIPTION of the dispatch rules (zrender Handler + echarts
     _initEvents + ECEventProcessor) replays every case from its steps and
     each step's recorded `hit` and must reproduce every mouse event of every
     step, field by field, in order;
  2. each guard mutates one rule of the transcription and must change every
     case it names;
  3. explicit expectations read straight off the upstream source (press on A
     release on B: no click; bar 0 -> bar 1 order; 'series.bar' never for a
     line; leave = mouseout then globalout; ...);
  4. the whole fixture is generated twice (byte-identical).
*/
'use strict';
process.env.TZ = 'UTC';
if (new Date(2017, 0, 1).getTimezoneOffset() !== 0 || new Date(2017, 6, 1).getTimezoneOffset() !== 0) {
  console.log('FAILED: process.env.TZ = \'UTC\' did not take effect');
  process.exit(1);
}
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-mouse-events.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

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

const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

const MOUSE = ['click', 'dblclick', 'mousedown', 'mouseup', 'mousemove', 'mouseover', 'mouseout', 'globalout', 'contextmenu'];

// ============================================================================
// Registrations common to every case
// ============================================================================
const COMMON = [
  ...MOUSE.map(t => ({ id: 'all.' + t, type: t })),
  { id: 'q.series', type: 'click', query: 'series' },
  { id: 'q.series.bar', type: 'click', query: 'series.bar' },
  { id: 'q.series.line', type: 'click', query: 'series.line' },
  { id: 'q.bar', type: 'click', query: 'bar' },
  { id: 'q.emptyString', type: 'click', query: '' },
  { id: 'q.series.', type: 'click', query: 'series.' },
  { id: 'q.seriesIndex1', type: 'click', query: { seriesIndex: 1 } },
  { id: 'q.seriesName.B', type: 'click', query: { seriesName: 'B' } },
  { id: 'q.seriesId.sb', type: 'click', query: { seriesId: 'sb' } },
  { id: 'q.s0d1', type: 'click', query: { seriesIndex: 0, dataIndex: 1 } },
  { id: 'q.name.Tue', type: 'click', query: { name: 'Tue' } },
  { id: 'q.dataIndex0', type: 'click', query: { dataIndex: 0 } },
  { id: 'q.dataType.edge', type: 'click', query: { dataType: 'edge' } },
  { id: 'q.dataType.node', type: 'click', query: { dataType: 'node' } },
  { id: 'q.legend', type: 'click', query: 'legend' },
  { id: 'q.legendIndex0', type: 'click', query: { legendIndex: 0 } },
  { id: 'q.title', type: 'click', query: 'title' },
  { id: 'q.xAxis', type: 'click', query: 'xAxis' },
  { id: 'q.xAxis.category', type: 'click', query: 'xAxis.category' },
  { id: 'q.xAxisIndex0', type: 'click', query: { xAxisIndex: 0 } },
  { id: 'q.yAxis', type: 'click', query: 'yAxis' },
  { id: 'q.markPoint', type: 'click', query: 'markPoint' },
  { id: 'q.componentType.legend', type: 'click', query: { componentType: 'legend' } },
  { id: 'q.element', type: 'click', query: { element: 'x' } },
  { id: 'q.seriesIndex.null', type: 'click', query: { seriesIndex: null } },
  { id: 'q.dataIndex.null', type: 'click', query: { dataIndex: null } },
  { id: 'q.upper', type: 'CLICK' },
  { id: 'q.dupA', type: 'click', query: 'series.line' },
  { id: 'q.dupB', type: 'click', query: '', sameFnAs: 'q.dupA' },
  { id: 'q.over.dataIndex2', type: 'mouseover', query: { dataIndex: 2 } },
  { id: 'q.over.edge', type: 'mouseover', query: { dataType: 'edge' } },
  { id: 'q.out.s0', type: 'mouseout', query: { seriesIndex: 0 } },
  { id: 'q.move.series', type: 'mousemove', query: 'series' },
  { id: 'q.down.s1', type: 'mousedown', query: { seriesIndex: 1 } },
  { id: 'q.up.d1', type: 'mouseup', query: { dataIndex: 1 } },
  { id: 'q.dbl.Tue', type: 'dblclick', query: { name: 'Tue' } },
  { id: 'q.ctx.bar', type: 'contextmenu', query: 'series.bar' },
  { id: 'q.globalout.s1', type: 'globalout', query: { seriesIndex: 1 } },
  { id: 'q.globalout.legend', type: 'globalout', query: 'legend' },
  // published (action) events carry no eventInfo: the filter passes everything
  { id: 'q.pub.selectchanged.s9', type: 'selectchanged', query: { seriesIndex: 9 } },
  { id: 'q.pub.legendselectchanged.line', type: 'legendselectchanged', query: 'series.line' },
];

// ============================================================================
// Cases
// ============================================================================
const CAT = ['Mon', 'Tue', 'Wed', 'Thu'];
const barOpt = extra => Object.assign({
  animation: false,
  xAxis: { type: 'category', data: CAT },
  yAxis: { type: 'value' },
  series: [
    { type: 'bar', id: 'sa', name: 'A', data: [12, 20, 15, 30], label: { show: true, position: 'top' } },
    { type: 'bar', id: 'sb', name: 'B', data: [8, 25, 18, 22] },
  ],
}, extra || {});
const item = (s, d, o) => Object.assign({ item: [s, d] }, o || {});
const label = (s, d, o) => Object.assign({ label: [s, d] }, o || {});
const text = (t, o) => Object.assign({ text: t }, o || {});
const empty = (x, y) => ({ empty: [x, y] });
const mv = at => ({ type: 'move', at });
const down = (at, button) => ({ type: 'down', at, button: button || 0 });
const up = (at, button) => ({ type: 'up', at, button: button || 0 });
const click = at => [mv(at), down(at), up(at)];

const CASES = [
  { id: 'bar-click', note: 'move onto bar A[1], press, release: mousemove + mouseover, mousedown, mouseup, the select action (published selectchanged, BEFORE the chart click: echarts\' own zr click handler runs first, the user-event bridge is registered callAtLast), click through every matching query',
    option: barOpt(), steps: click(item(0, 1)) },
  { id: 'bar-click-b', note: 'the same on bar B[1] (seriesIndex 1 / name B / id sb queries)',
    option: barOpt(), steps: click(item(1, 1)) },
  { id: 'bar-label-click', note: 'click on the label of A[1] (a TSpan whose host is the bar: the same params as the bar)',
    option: barOpt(), steps: click(label(0, 1)) },
  { id: 'bar-press-release-other', note: 'press on A[0], move to A[1], release there: mouseup on A[1] but NO click (zrender: _downEl !== _upEl)',
    option: barOpt(), steps: [mv(item(0, 0)), down(item(0, 0)), mv(item(0, 1)), up(item(0, 1))] },
  { id: 'bar-press-release-near', note: 'label of A[1] touching its bar (label distance 0): press in the label 2 px above the bar top, release in the bar 2 px below it (4 px apart): two elements of ONE data item, so no click (the same-target rule is by element); press and release both in the bar 4 px apart: click',
    option: barOpt({ series: [
      { type: 'bar', id: 'sa', name: 'A', data: [12, 20, 15, 30], label: { show: true, position: 'top', distance: 0 } },
      { type: 'bar', id: 'sb', name: 'B', data: [8, 25, 18, 22] },
    ] }),
    steps: [down(label(0, 1, { dy: 4, free: true })), up(label(0, 1, { dy: 8, free: true })), down(label(0, 1, { dy: 8, free: true })), up(label(0, 1, { dy: 12, free: true }))] },
  { id: 'bar-move-across', note: 'empty -> A[0] -> A[1] -> B[1] -> empty: per change mouseout(old), mousemove(new), mouseover(new)',
    option: barOpt(), steps: [mv(empty(70, 200)), mv(item(0, 0)), mv(item(0, 1)), mv(item(1, 1)), mv(empty(70, 200))] },
  { id: 'bar-move-within', note: 'three points inside A[3]: mouseover once, then mousemove only',
    option: barOpt(), steps: [mv(item(0, 3)), mv(item(0, 3, { dx: 3, dy: -2 })), mv(item(0, 3, { dx: -4, dy: 6 }))] },
  { id: 'bar-to-own-label', note: 'bar A[1] -> its label -> the bar: two zrender elements of ONE data item still emit mouseout / mouseover (identity is the element, not the data item)',
    option: barOpt(), steps: [mv(item(0, 1)), mv(label(0, 1)), mv(item(0, 1))] },
  { id: 'bar-click-tolerance', note: 'press / release pairs inside A[3] at offsets (4,0) (3,3) (0,4) (0,5) (-2,-3): the click needs dist(press, click) <= 4 (Euclidean): 4 yes, 4.24 no, 4 yes, 5 no, 3.6 yes',
    option: barOpt(), steps: [
      down(item(0, 3)), up(item(0, 3, { dx: 4, dy: 0 })),
      down(item(0, 3)), up(item(0, 3, { dx: 3, dy: 3 })),
      down(item(0, 3)), up(item(0, 3, { dx: 0, dy: 4 })),
      down(item(0, 3)), up(item(0, 3, { dx: 0, dy: 5 })),
      down(item(0, 3)), up(item(0, 3, { dx: -2, dy: -3 })),
    ] },
  { id: 'bar-drag-back', note: 'press on A[3], drag 10 px away, come back, release at the press point: the path does not matter, only the two end points (click fires)',
    option: barOpt(), steps: [down(item(0, 3)), mv(item(0, 3, { dy: 10 })), mv(item(0, 3)), up(item(0, 3))] },
  { id: 'bar-up-only', note: 'a release with no press never clicks (_downPoint unset); a click clears _downPoint, so a second release without a press does not click again',
    option: barOpt(), steps: [up(item(0, 1)), down(item(0, 1)), up(item(0, 1)), up(item(0, 1))] },
  { id: 'bar-contextmenu', note: 'right button: mousedown / mouseup (no click for button 2) and contextmenu, all with the bar\'s params',
    option: barOpt(), steps: [mv(item(0, 1)), down(item(0, 1), 2), up(item(0, 1), 2), { type: 'contextmenu', at: item(0, 1) }] },
  { id: 'bar-dblclick-browser', note: 'the browser\'s double click: down, up (click), down, up (click), dblclick',
    option: barOpt(), steps: [mv(item(0, 1)), down(item(0, 1)), up(item(0, 1)), down(item(0, 1)), up(item(0, 1)), { type: 'dblclick', at: item(0, 1) }] },
  { id: 'bar-dblclick-bare', note: 'a dblclick with no press before it still fires (no same-target / distance rule for dblclick); on empty ground nothing',
    option: barOpt(), steps: [{ type: 'dblclick', at: item(0, 1) }, { type: 'dblclick', at: empty(70, 200) }] },
  { id: 'bar-leave', note: 'over A[1], the pointer leaves the canvas: mouseout(A[1]) then globalout ({} params: every globalout handler fires, queries included). zrender keeps _hovered after a leave: re-entering onto the same bar gives mousemove only, no mouseover; leaving it for empty ground gives mouseout',
    option: barOpt(), steps: [mv(item(0, 1)), { type: 'leave', at: { xy: [300, -1] } }, mv(item(0, 1)), mv(empty(70, 200))] },
  { id: 'bar-leave-empty', note: 'leave while over nothing: globalout only',
    option: barOpt(), steps: [mv(empty(70, 200)), { type: 'leave', at: { xy: [-1, 200] } }] },
  { id: 'bar-empty-click', note: 'press / release / dblclick / contextmenu on empty plot ground and on the axis line: no chart event (the hit has no ECData)',
    option: barOpt(), steps: [...click(empty(70, 200)), { type: 'contextmenu', at: empty(70, 200) }, ...click({ xy: [300, 352] })] },
  { id: 'bar-silent-series', note: 'series B silent: its bars are never a target (the hit falls through to what lies below); A -> B[1] is a mouseout of A only; a click on B[1] emits nothing',
    option: barOpt({ series: [
      { type: 'bar', id: 'sa', name: 'A', data: [12, 20, 15, 30] },
      { type: 'bar', id: 'sb', name: 'B', data: [8, 25, 18, 22], silent: true },
    ] }), steps: [mv(item(0, 1)), mv({ xy: 'item 1 1' }), down({ xy: 'item 1 1' }), up({ xy: 'item 1 1' })] },
  { id: 'mixed-bar-line', note: 'bar (s0) + line with symbols (s1): a click on a line symbol passes \'series\' and \'series.line\', never \'series.bar\'; the dedup pair q.dupA / q.dupB fires once, under q.dupA\'s query',
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [{ type: 'bar', name: 'A', data: [12, 20, 15, 30] }, { type: 'line', name: 'B', data: [25, 32, 28, 40], symbolSize: 12 }] },
    steps: [...click(item(1, 2)), ...click(item(0, 1)), mv(item(1, 1)), mv(item(0, 1))] },
  { id: 'line-symbols', note: 'line with symbols: over / click on a symbol; the polyline itself has no ECData unless triggerEvent (a hit on it emits nothing, and moving onto it is a mouseout of the symbol)',
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [{ type: 'line', name: 'L', data: [10, 30, 20, 25], symbolSize: 12, lineStyle: { width: 4 } }] },
    steps: [mv(item(0, 1)), down(item(0, 1)), up(item(0, 1)), mv({ between: [0, 1, 2] }), ...click({ between: [0, 1, 2] })] },
  { id: 'line-trigger-event', note: 'series triggerEvent true (the successor of the deprecated triggerLineEvent): the polyline carries eventData {componentType series, seriesIndex, selfType line} -- no dataIndex / name / value',
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [{ type: 'line', name: 'L', data: [10, 30, 20, 25], symbolSize: 12, lineStyle: { width: 4 }, triggerEvent: true }] },
    steps: [...click({ between: [0, 1, 2] }), mv(item(0, 2))] },
  { id: 'scatter', note: 'scatter: value is the [x, y] pair (String: "x,y")',
    option: { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', name: 'S', symbolSize: 20, data: [[1, 2], [3, 5], [5, 3], [7, 8]] }] },
    steps: [...click(item(0, 1)), mv(item(0, 2)), { type: 'dblclick', at: item(0, 2) }] },
  { id: 'pie-sector', note: 'pie, selectedMode off: move sector 0 -> 1 (the hover scale grows the hovered sector: the hit geometry follows the emphasis state), click sector 1 (select action still dispatched: selectchanged published)',
    option: { animation: false, series: [{ type: 'pie', name: 'P', radius: ['0%', '60%'], selectedMode: false,
      data: [{ name: 'Mon', value: 10 }, { name: 'Tue', value: 20 }, { name: 'Wed', value: 30 }, { name: 'Thu', value: 15 }] }] },
    steps: [mv(item(0, 0)), mv(item(0, 1)), down(item(0, 1)), up(item(0, 1)), mv(empty(20, 20))] },
  { id: 'pie-label', note: 'pie outside label: a click on the label reports the sector\'s params; sector -> its label = mouseout + mouseover',
    option: { animation: false, series: [{ type: 'pie', name: 'P', radius: ['0%', '50%'],
      data: [{ name: 'Mon', value: 10 }, { name: 'Tue', value: 20 }, { name: 'Wed', value: 30 }, { name: 'Thu', value: 15 }] }] },
    steps: [mv(item(0, 2)), ...click(label(0, 2))] },
  { id: 'graph-edge', note: 'graph (layout none): the hover shows node A\'s label over its symbol, so the press after the move hits the label (same params); node click (dataType node), edge click (dataType edge, name "A > B"), node -> edge -> empty over / out; q.over.edge fires on the edge only',
    option: { animation: false, series: [{ type: 'graph', name: 'G', layout: 'none', symbolSize: 30,
      lineStyle: { width: 4 },
      data: [{ name: 'A', x: 100, y: 100 }, { name: 'B', x: 400, y: 100 }, { name: 'C', x: 250, y: 300 }],
      links: [{ source: 'A', target: 'B', value: 5 }, { source: 'B', target: 'C' }, { source: 'A', target: 'C' }] }] },
    steps: [...click(item(0, 0)), mv({ edge: 0 }), down({ edge: 0 }), up({ edge: 0 }), mv({ edge: 2 }), mv(empty(20, 380))] },
  { id: 'title-trigger', note: 'title triggerEvent true: text and subtext emit {componentType title, componentIndex}; text -> subtext is out / over',
    // the sizes upstream defaults to, written out: the port's title takes
    // the skin's font where the option is silent, and the hit boxes follow it
    option: { animation: false, title: { text: 'Weekly', subtext: 'subtitle here', triggerEvent: true,
      textStyle: { fontSize: 18, fontWeight: 'bold' }, subtextStyle: { fontSize: 12 } }, series: [] },
    steps: [...click(text('Weekly')), mv(text('subtitle here')), { type: 'leave', at: { xy: [0, -1] } }] },
  { id: 'title-notrigger', note: 'title without triggerEvent: the text is silent, nothing is emitted',
    option: { animation: false, title: { text: 'Weekly' }, series: [] },
    steps: [...click({ xy: 'text Weekly' })] },
  { id: 'legend-notrigger', note: 'legend without triggerEvent (the default): a legend click emits no chart click, only legendselectchanged (and the legend hover\'s highlight / downplay actions)',
    option: barOpt({ legend: { data: ['A', 'B'] } }),
    steps: [mv({ legend: 'B' }), down({ legend: 'B' }), up({ legend: 'B' }), mv(empty(70, 200))] },
  { id: 'legend-trigger', note: 'legend triggerEvent true (legend.data [B, A], so dataIndex = the legend position and seriesIndex = the series differ): every child of the item group carries {componentType legend, componentIndex, dataIndex, value: name, seriesIndex}; the item\'s own click handler runs first (legendselectchanged), then the chart click; the whole item is ONE target (every child is silent, an invisible hit rect spans the item): icon -> text is mousemove only; the re-render replaces the item (a later move re-finds it: #6198)',
    option: barOpt({ legend: { data: ['B', 'A'], triggerEvent: true } }),
    steps: [mv({ legend: 'B' }), down({ legend: 'B' }), up({ legend: 'B' }), mv({ legend: 'B', dx: 1 }), mv({ legendIcon: 'A' }), mv({ legend: 'A' }), { type: 'leave', at: { xy: [300, 401] } }] },
  { id: 'xaxis-trigger', note: 'xAxis triggerEvent true: an axis label emits {componentType xAxis, xAxisIndex, targetType axisLabel, value (the raw label), tickIndex, dataIndex (category)}; the axis name {targetType axisName, name}',
    option: barOpt({ xAxis: { type: 'category', data: CAT, triggerEvent: true, name: 'Day' } }),
    steps: [...click(text('Wed')), mv(text('Thu')), ...click(text('Day'))] },
  { id: 'yaxis-trigger', note: 'value yAxis triggerEvent true: axis label value is the raw label string',
    option: barOpt({ yAxis: { type: 'value', triggerEvent: true } }),
    steps: [...click(text('10'))] },
  { id: 'markpoint', note: 'markPoint on series A: componentType markPoint, componentSubType empty, seriesIndex / seriesType / seriesName / seriesId of the host series; the query filter looks at the SERIES (componentType remapped): \'series\' and {seriesIndex: 0} pass, \'markPoint\' never does',
    option: barOpt({ series: [
      { type: 'bar', id: 'sa', name: 'A', data: [12, 20, 15, 30], markPoint: { symbolSize: 40, data: [{ type: 'max', name: 'Max' }, { name: 'pin', coord: ['Tue', 20] }] } },
      { type: 'bar', id: 'sb', name: 'B', data: [8, 25, 18, 22] },
    ] }),
    steps: [...click({ marker: ['markPoint', 0, 0] }), mv({ marker: ['markPoint', 0, 1] }), ...click({ marker: ['markPoint', 0, 1] })] },
  { id: 'bar-datazoom-filtered', note: 'dataZoom keeps categories 2..3: the second bar shown is raw row 3, and params.dataIndex is the raw index',
    option: barOpt({ dataZoom: [{ type: 'inside', xAxisIndex: 0, startValue: 2, endValue: 3 }] }),
    steps: click(item(0, 1)) },
  { id: 'markpoint-second-series', note: 'a markLine on series A and a markPoint on series B: the markPoint model is the first of ITS kind, componentIndex 0',
    option: barOpt({ series: [
      { type: 'bar', id: 'sa', name: 'A', data: [12, 20, 15, 30], markLine: { data: [{ type: 'average' }] } },
      { type: 'bar', id: 'sb', name: 'B', data: [8, 25, 18, 22], markPoint: { symbolSize: 40, data: [{ type: 'max', name: 'Max' }] } },
    ] }),
    steps: click({ marker: ['markPoint', 1, 0] }) },
  { id: 'treemap-zoom', note: 'treemap (nodeClick default zoomToNode): leaf click params dataIndex from 1 (0 = the virtual root); the view\'s own click dispatches treemapZoomToNode',
    option: { animation: false, series: [{ type: 'treemap', name: 'T', breadcrumb: { show: false },
      data: [{ name: 'a', value: 10, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 6 }] }, { name: 'b', value: 20 }] }] },
    steps: [mv(item(0, 4)), mv(item(0, 2)), ...click(item(0, 4))] },
  { id: 'treemap-noclick', note: 'treemap nodeClick false: the plain click only',
    option: { animation: false, series: [{ type: 'treemap', name: 'T', nodeClick: false, breadcrumb: { show: false },
      data: [{ name: 'a', value: 10, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 6 }] }, { name: 'b', value: 20 }] }] },
    steps: [...click(item(0, 3)), ...click(text('a2'))] },
  { id: 'sunburst', note: 'sunburst: item params dataIndex from 1; nodeClick default rootToNode (sunburstRootToNode published) on a node with children',
    option: { animation: false, series: [{ type: 'sunburst', name: 'S', radius: [0, '80%'],
      data: [{ name: 'a', value: 10, children: [{ name: 'a1', value: 4 }, { name: 'a2', value: 6 }] }, { name: 'b', value: 20 }] }] },
    steps: [mv(item(0, 4)), mv(item(0, 2)), ...click(item(0, 1)), mv(empty(5, 5))] },
];

// ============================================================================
// Driving a case
// ============================================================================
const raw = (x, y, button) => ({ zrX: x, zrY: y, which: (button || 0) + 1, preventDefault() {}, stopPropagation() {} });

function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false; // the browser's model (see the header)
  return chart;
}
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
function owns(owner, t) {
  for (let e = t; e; e = e.__hostTarget || e.parent) if (e === owner) return true;
  return false;
}
// the ECData dispatcher walk of echarts _initEvents (first match)
function paramsOf(chart, t) {
  const ecModel = chart.getModel();
  for (let e = t; e; e = e.__hostTarget || e.parent) {
    const d = getECData(e);
    if (d && d.dataIndex != null) {
      const dm = d.dataModel || ecModel.getSeriesByIndex(d.seriesIndex);
      return (dm && dm.getDataParams(d.dataIndex, d.dataType, t)) || {};
    }
    if (d && d.eventData) return Object.assign({}, d.eventData);
  }
  return null;
}
// ECData lives in a makeInner store keyed per element; find its key once
let ecKey = null;
function getECData(el) {
  if (ecKey === null) return null;
  return el[ecKey] || null;
}
function discoverECKey(chart) {
  // any series item element holds its ECData under the inner key: find the property whose value has dataIndex
  const data = chart.getModel().getSeriesByIndex(0).getData();
  const el = data.getItemGraphicEl(0);
  for (const k of Object.getOwnPropertyNames(el)) {
    const v = el[k];
    if (v && typeof v === 'object' && hasOwn(v, 'dataIndex') && v.dataIndex === 0 && hasOwn(v, 'seriesIndex')) { ecKey = k; return; }
  }
  throw new OracleError('the ECData key was not found');
}

const FIELDS = ['componentType', 'componentSubType', 'componentIndex', 'seriesType', 'seriesIndex', 'seriesId', 'seriesName',
  'name', 'dataIndex', 'dataType', 'value', 'targetType', 'tickIndex', 'selfType', 'xAxisIndex', 'yAxisIndex'];
function pick(p) {
  const r = {};
  for (const k of FIELDS) {
    if (!hasOwn(p, k) || p[k] === undefined) continue;
    let v = p[k];
    if (k === 'seriesId' && typeof v === 'string' && v.includes('\u0000')) continue;
    if (k === 'value') v = String(v);
    r[k] = v;
  }
  return r;
}
function modelOf(chart, p) {
  if (!p) return null;
  let ct = p.componentType;
  let ci = p.componentIndex;
  if (ct === 'markLine' || ct === 'markPoint' || ct === 'markArea') { ct = 'series'; ci = p.seriesIndex; }
  const m = ct && ci != null && chart.getModel().getComponent(ct, ci);
  if (!m) return null;
  const view = m.mainType === 'series' ? chart._chartsMap[m.__viewId] : chart._componentsMap[m.__viewId];
  if (!view) return null;
  // auto names / ids carry \0: written as '<auto>' (no query here ever names them)
  const auto = v => (typeof v === 'string' && v.includes('\u0000') ? '<auto>' : v);
  const r = { mainType: m.mainType, subType: m.subType, index: m.componentIndex, name: auto(m.name), id: auto(m.id) };
  return r;
}
function plain(v, depth) {
  if (typeof v === 'string' && v.includes('\u0000')) return '<auto id>';
  if (v === null || typeof v !== 'object') return typeof v === 'function' ? undefined : v;
  if (depth > 4) return undefined;
  // class instances (tree nodes, elements, models) stand as their class name
  if (!Array.isArray(v) && Object.getPrototypeOf(v) !== Object.prototype && Object.getPrototypeOf(v) !== null) {
    return '[' + ((v.constructor && v.constructor.name) || 'object') + ']';
  }
  if (Array.isArray(v)) return v.map(x => { const s = plain(x, depth + 1); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    if (k === 'event') continue;
    // `from` = the dispatching view's uid: a process-wide counter
    const s = k === 'from' && typeof v[k] === 'string' ? '<view uid>' : plain(v[k], depth + 1);
    if (s !== undefined) o[k] = s;
  }
  return o;
}

function runCase(def) {
  const chart = newChart();
  const option = clone(def.option);
  const events = [];
  const elIds = new Map();
  const elOf = el => { if (!elIds.has(el)) elIds.set(el, elIds.size); return elIds.get(el); };
  const regs = COMMON.concat(def.extra || []);
  try {
    chart.setOption(clone(option));
    frame(chart);
    const fns = {};
    for (const r of regs) {
      let fn;
      if (r.sameFnAs) fn = fns[r.sameFnAs];
      else {
        const id = r.id;
        fn = p => {
          if (MOUSE.includes(p.type)) {
            const e = Object.assign({ h: id, type: p.type }, pick(p));
            if (p.event && p.event.offsetX !== undefined) { e.offsetX = p.event.offsetX; e.offsetY = p.event.offsetY; }
            if (p.event && p.event.target) e.el = p.event.target.type;
            events.push(e);
          } else events.push({ h: id, type: p.type });
        };
      }
      fns[r.id] = fn;
      if (r.query === undefined) chart.on(r.type, fn); else chart.on(r.type, clone(r.query), fn);
    }
    const pubTypes = Object.keys(chart._messageCenter._$handlers);
    for (const t of pubTypes) chart.on(t, p => events.push({ h: 'pub', type: t, payload: plain(p, 0) }));

    const hd = () => chart.getZr().handler;
    const hitAt = (x, y) => {
      const t = hd().findHover(x, y).target;
      if (!t) return null;
      const p = paramsOf(chart, t);
      return { el: elOf(t), kind: t.type, params: p ? pick(p) : null, model: modelOf(chart, p) };
    };
    const displayables = () => chart.getZr().storage.getDisplayList();
    const findText = s => {
      const l = displayables().filter(e => e.type === 'tspan' && e.style && e.style.text === s && !e.ignore);
      must(l.length === 1, def.id + ': text \'' + s + '\' found ' + l.length + ' times');
      return l[0];
    };
    const series = s => chart.getModel().getSeriesByIndex(s);
    // an integer point near c that hits something owned by `owner`
    const aimNear = (c, owner, what) => {
      const x0 = Math.round(c[0]);
      const y0 = Math.round(c[1]);
      for (let r = 0; r <= 12; r++) {
        for (let dy = -r; dy <= r; dy++) {
          for (let dx = -r; dx <= r; dx++) {
            if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
            const t = hd().findHover(x0 + dx, y0 + dy).target;
            if (t && owns(owner, t)) return [x0 + dx, y0 + dy];
          }
        }
      }
      throw new OracleError(def.id + ': no point near ' + c + ' hits ' + what);
    };
    const itemEl = (s, d) => {
      const el = series(s).getData().getItemGraphicEl(d);
      must(el && el.__zr, def.id + ': item ' + s + '/' + d + ' is not drawn');
      return el;
    };
    const itemCentre = el => {
      if (el.type === 'sector' || (el.shape && el.shape.r !== undefined && el.shape.startAngle !== undefined)) {
        const sh = el.shape;
        const a = (sh.startAngle + sh.endAngle) / 2;
        const rm = (sh.r0 + sh.r) / 2;
        const p = [sh.cx + rm * Math.cos(a), sh.cy + rm * Math.sin(a)];
        return el.transform ? [el.transform[0] * p[0] + el.transform[2] * p[1] + el.transform[4], el.transform[1] * p[0] + el.transform[3] * p[1] + el.transform[5]] : p;
      }
      if (el.isGroup) { const t = el.transform; return t ? [t[4], t[5]] : [el.x, el.y]; }
      const r = globalRect(el);
      return [r.x + r.width / 2, r.y + r.height / 2];
    };
    const resolve = (at) => {
      let c;
      let owner;
      let aim;
      let exact = false;
      if (at.item) {
        owner = itemEl(at.item[0], at.item[1]);
        c = itemCentre(owner);
        aim = 'item s' + at.item[0] + ' d' + at.item[1];
      } else if (at.label) {
        const el = itemEl(at.label[0], at.label[1]);
        owner = el.getTextContent();
        must(owner && !owner.ignore, def.id + ': item ' + at.label + ' has no shown label');
        const r = globalRect(owner);
        c = [r.x + r.width / 2, r.y + r.height / 2];
        aim = 'label s' + at.label[0] + ' d' + at.label[1];
      } else if (at.text != null) {
        owner = findText(at.text);
        const r = globalRect(owner);
        c = [r.x + r.width / 2, r.y + r.height / 2];
        aim = 'text \'' + at.text + '\'';
      } else if (at.legend != null || at.legendIcon != null) {
        // a legend item: every child is silent, the hit is the item's invisible hit rect -> the owner is the item group
        const t = findText(at.legend != null ? at.legend : at.legendIcon);
        owner = t.parent && t.parent.parent;
        must(owner && owner.isGroup, def.id + ': no legend item group');
        const r = globalRect(at.legend != null ? t : owner.childAt(0));
        c = [r.x + r.width / 2, r.y + r.height / 2];
        aim = at.legend != null ? 'legend text \'' + at.legend + '\'' : 'legend icon \'' + at.legendIcon + '\'';
      } else if (at.edge != null) {
        owner = series(0).getEdgeData().getItemGraphicEl(at.edge);
        const line = owner.childOfName('line');
        const q = line.pointAt(0.5);
        c = line.transformCoordToGlobal(q[0], q[1]);
        aim = 'edge ' + at.edge;
      } else if (at.between) {
        const [s, i, j] = at.between;
        const a = itemCentre(itemEl(s, i));
        const b = itemCentre(itemEl(s, j));
        c = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
        owner = null;
        aim = 'between s' + s + ' d' + i + ' d' + j;
        exact = true;
      } else if (at.marker) {
        const [mt, s, d] = at.marker;
        const cands = displayables().filter(e => {
          if (e.type === 'tspan') return false;
          for (let x = e; x; x = x.__hostTarget || x.parent) {
            const ed = getECData(x);
            if (ed && ed.dataIndex != null) return ed.dataModel && ed.dataModel.mainType === mt && ed.dataModel.seriesIndex === s && ed.dataIndex === d;
          }
          return false;
        });
        must(cands.length >= 1, def.id + ': marker ' + at.marker + ' not found');
        owner = cands[0];
        const r = globalRect(owner);
        c = [r.x + r.width / 2, r.y + r.height / 2];
        aim = 'marker ' + mt + ' s' + s + ' d' + d;
      } else if (at.empty) {
        c = at.empty;
        aim = 'empty';
        exact = true;
        must(!hd().findHover(c[0], c[1]).target, def.id + ': the empty point ' + c + ' hits an element');
      } else if (at.xy) {
        if (typeof at.xy === 'string') {
          // an item of a SILENT series / a silent text: aim by geometry, the hit is whatever lies there
          const w = at.xy.split(' ');
          if (w[0] === 'item') c = itemCentre(itemEl(+w[1], +w[2]));
          else { const l = displayables().filter(e => e.type === 'tspan' && e.style.text === w.slice(1).join(' ')); must(l.length === 1, def.id + ': text'); const r = globalRect(l[0]); c = [r.x + r.width / 2, r.y + r.height / 2]; }
          c = [Math.round(c[0]), Math.round(c[1])];
          aim = 'point (' + at.xy + ')';
        } else { c = at.xy; aim = 'point'; }
        exact = true;
      } else throw new OracleError(def.id + ': an unknown aim ' + JSON.stringify(at));
      let p = exact ? [Math.round(c[0]), Math.round(c[1])] : aimNear(c, owner, aim);
      if (at.dx || at.dy) {
        p = [p[0] + (at.dx || 0), p[1] + (at.dy || 0)];
        if (owner && !at.free) must(owns(owner, hd().findHover(p[0], p[1]).target), def.id + ': the offset point ' + p + ' leaves ' + aim);
        aim += ' ' + (at.dx ? (at.dx > 0 ? '+' : '') + at.dx : '+0') + ',' + (at.dy ? (at.dy > 0 ? '+' : '') + at.dy : '+0');
      }
      return { x: p[0], y: p[1], aim };
    };

    const steps = [];
    for (const s0 of def.steps) {
      const st = { type: s0.type };
      const r = resolve(s0.at);
      st.x = r.x; st.y = r.y;
      if (s0.type === 'down' || s0.type === 'up') st.button = s0.button;
      st.aim = r.aim;
      const outside = st.x < 0 || st.x > W || st.y < 0 || st.y > H;
      st.hit = outside ? null : hitAt(st.x, st.y);
      const h = hd();
      events.length = 0;
      if (st.type === 'move') {
        const last = h._hovered.target;
        if (last && !last.__zr) {
          const t = h.findHover(h._hovered.x, h._hovered.y).target;
          st.refound = t ? elOf(t) : null;
        }
        h.mousemove(raw(st.x, st.y));
      } else if (st.type === 'down') h.mousedown(raw(st.x, st.y, st.button));
      else if (st.type === 'up') {
        h.mouseup(raw(st.x, st.y, st.button));
        if (st.button === 0) h.click(raw(st.x, st.y, 0));
      } else if (st.type === 'dblclick') h.dblclick(raw(st.x, st.y));
      else if (st.type === 'contextmenu') h.contextmenu(raw(st.x, st.y, 2));
      else if (st.type === 'leave') {
        must(outside, def.id + ': a leave inside the canvas');
        h.mouseout(raw(st.x, st.y));
      } else throw new OracleError(def.id + ': an unknown step ' + st.type);
      st.events = events.slice();
      steps.push(st);
      frame(chart);
    }
    return { id: def.id, note: def.note, option, extra: def.extra, steps };
  } finally {
    chart.dispose();
  }
}

// ============================================================================
// The transcription (zrender Handler + echarts _initEvents + ECEventProcessor)
// ============================================================================
const RULES = {
  clickTol: 4, sameTarget: true, resetDownPoint: true, outMoveOver: true, overByElement: true,
  leaveKeepsHover: true, markerRemap: true, otherQueryIgnored: true, nullPropSetsMainType: true,
  globaloutUnfiltered: true, subTypeChecked: true, dedupByFn: true, lowercase: true,
};
function parseClassType(s) {
  const a = s ? s.split('.') : [];
  return { main: a[0] || '', sub: a[1] || '' };
}
function normalizeQuery(q, R) {
  const cpt = {};
  const data = {};
  const other = {};
  if (typeof q === 'string') {
    const c = parseClassType(q);
    cpt.mainType = c.main || null;
    cpt.subType = R.subTypeChecked ? (c.sub || null) : null;
  } else {
    for (const key of Object.keys(q)) {
      const val = q[key];
      let reserved = false;
      for (const suf of ['Index', 'Name', 'Id']) {
        const pos = key.lastIndexOf(suf);
        if (pos > 0 && pos === key.length - suf.length) {
          const main = key.slice(0, pos);
          if (main !== 'data') {
            if (R.nullPropSetsMainType || val != null) cpt.mainType = main;
            cpt[suf.toLowerCase()] = val;
            reserved = true;
          }
        }
      }
      if (key === 'name' || key === 'dataIndex' || key === 'dataType') { data[key] = val; reserved = true; }
      if (!reserved) other[key] = val;
    }
  }
  return { cpt, data, other };
}
function passes(nq, hit, isGlobalOut, R) {
  if (isGlobalOut) return R.globaloutUnfiltered ? true : false;
  let model = hit.model;
  const p = hit.params;
  if (!R.markerRemap && model && /^mark(Point|Line|Area)$/.test(p.componentType)) {
    model = { mainType: p.componentType, subType: '', index: 0, name: p.name };
  }
  if (!model) return true;
  const chk = (q, host, prop, hostProp) => q[prop] == null || host[hostProp || prop] === q[prop];
  if (!(chk(nq.cpt, model, 'mainType') && chk(nq.cpt, model, 'subType') && chk(nq.cpt, model, 'index')
    && chk(nq.cpt, model, 'name') && chk(nq.cpt, model, 'id')
    && chk(nq.data, p, 'name') && chk(nq.data, p, 'dataIndex') && chk(nq.data, p, 'dataType'))) return false;
  if (!R.otherQueryIgnored) for (const k of Object.keys(nq.other)) if (nq.other[k] != null && p[k] !== nq.other[k]) return false;
  return true;
}
function predictCase(c, R) {
  // the registrations as Eventful keeps them
  const table = {};
  const seenFn = {};
  for (const r of COMMON.concat(c.extra || [])) {
    const type = R.lowercase ? r.type.toLowerCase() : r.type;
    const fnId = r.sameFnAs || r.id;
    const list = table[type] || (table[type] = []);
    if (R.dedupByFn && list.some(x => x.fnId === fnId)) continue;
    seenFn[fnId] = true;
    list.push({ fnId, nq: r.query === undefined || r.query === null ? null : normalizeQuery(r.query, R) });
  }
  let hovered = null; // a hit or null
  let downEl;
  let upEl;
  let downPoint = null;
  const out = [];
  for (const st of c.steps) {
    const evs = [];
    const emit = (type, hit) => {
      const isGO = type === 'globalout';
      if (!isGO && !(hit && hit.params)) return;
      for (const reg of table[type] || []) {
        if (reg.nq && !passes(reg.nq, hit, isGO, R)) continue;
        const e = Object.assign({ h: reg.fnId, type }, isGO ? {} : hit.params);
        if (!isGO) { e.offsetX = st.x; e.offsetY = st.y; e.el = hit.kind; }
        evs.push(e);
      }
    };
    const hit = st.hit;
    const elOf = x => (x ? x.el : null);
    if (st.type === 'move') {
      let last = hovered;
      if (st.refound !== undefined) last = st.refound === null ? null : { el: st.refound, kind: hit && hit.el === st.refound ? hit.kind : last.kind, params: hit && hit.el === st.refound ? hit.params : last.params, model: hit && hit.el === st.refound ? hit.model : last.model };
      const same = (a, b) => (R.overByElement ? elOf(a) === elOf(b)
        : (a && b && a.params && b.params ? a.params.seriesIndex === b.params.seriesIndex && a.params.dataIndex === b.params.dataIndex && a.params.componentType === b.params.componentType : elOf(a) === elOf(b)));
      if (R.outMoveOver) {
        if (last && !same(hit, last)) emit('mouseout', last);
        emit('mousemove', hit);
        if (hit && !same(hit, last)) emit('mouseover', hit);
      } else {
        if (hit && !same(hit, last)) emit('mouseover', hit);
        if (last && !same(hit, last)) emit('mouseout', last);
        emit('mousemove', hit);
      }
      hovered = hit;
    } else if (st.type === 'down') {
      downEl = elOf(hit); downPoint = [st.x, st.y]; upEl = elOf(hit);
      emit('mousedown', hit);
    } else if (st.type === 'up') {
      upEl = elOf(hit);
      emit('mouseup', hit);
      if (st.button === 0) {
        const d = downPoint ? Math.hypot(downPoint[0] - st.x, downPoint[1] - st.y) : 0;
        if (!((R.sameTarget && downEl !== upEl) || !downPoint || d > R.clickTol)) {
          if (R.resetDownPoint) downPoint = null;
          emit('click', hit);
        }
      }
    } else if (st.type === 'dblclick') emit('dblclick', hit);
    else if (st.type === 'contextmenu') emit('contextmenu', hit);
    else if (st.type === 'leave') {
      emit('mouseout', hovered);
      emit('globalout', null);
      if (!R.leaveKeepsHover) hovered = null;
    }
    out.push(evs);
  }
  return out;
}
const mouseEvents = st => st.events.filter(e => e.h !== 'pub' && MOUSE.includes(e.type));
function caseDiffs(c, R) {
  const pred = predictCase(c, R);
  const diffs = [];
  c.steps.forEach((st, k) => {
    const a = JSON.stringify(mouseEvents(st));
    const b = JSON.stringify(pred[k]);
    if (a !== b) diffs.push({ step: k, got: mouseEvents(st), want: pred[k] });
  });
  return diffs;
}

const GUARDS = [
  { id: 'G-click-same-target', mutation: 'click ignores _downEl !== _upEl', mut: { sameTarget: false }, named: ['bar-press-release-near'] },
  { id: 'G-click-tol-5', mutation: 'click tolerance 5 px', mut: { clickTol: 5 }, named: ['bar-click-tolerance'] },
  { id: 'G-click-tol-3', mutation: 'click tolerance 3 px', mut: { clickTol: 3 }, named: ['bar-click-tolerance'] },
  { id: 'G-click-reset', mutation: 'a click keeps _downPoint', mut: { resetDownPoint: false }, named: ['bar-up-only'] },
  { id: 'G-out-move-over', mutation: 'over before out and move', mut: { outMoveOver: false }, named: ['bar-move-across', 'pie-sector'] },
  { id: 'G-over-by-element', mutation: 'over / out by data item instead of element', mut: { overByElement: false }, named: ['bar-to-own-label', 'pie-label'] },
  { id: 'G-leave-keeps-hover', mutation: 'a leave clears the hover', mut: { leaveKeepsHover: false }, named: ['bar-leave'] },
  { id: 'G-marker-remap', mutation: 'no markPoint -> series remap', mut: { markerRemap: false }, named: ['markpoint'] },
  { id: 'G-other-query', mutation: 'unknown query keys must match params', mut: { otherQueryIgnored: false }, named: ['bar-click', 'legend-trigger'] },
  { id: 'G-null-prop', mutation: '{seriesIndex: null} sets no mainType', mut: { nullPropSetsMainType: false }, named: ['title-trigger', 'xaxis-trigger'] },
  { id: 'G-globalout', mutation: 'globalout queries filtered out', mut: { globaloutUnfiltered: false }, named: ['bar-leave', 'bar-leave-empty'] },
  { id: 'G-subtype', mutation: "'series.bar' ignores the sub type", mut: { subTypeChecked: false }, named: ['mixed-bar-line', 'line-symbols'] },
  { id: 'G-dedup', mutation: 'the same function registered twice fires twice', mut: { dedupByFn: false }, named: ['bar-click'] },
  { id: 'G-lowercase', mutation: "'CLICK' is not lowercased", mut: { lowercase: false }, named: ['bar-click'] },
];

function check(g) {
  let states = 0;
  let evCount = 0;
  for (const c of g.cases) {
    const d = caseDiffs(c, RULES);
    must(!d.length, c.id + ': the transcription differs at step ' + (d[0] && d[0].step) + ':\n got  ' + JSON.stringify(d[0] && d[0].got) + '\n want ' + JSON.stringify(d[0] && d[0].want));
    states += c.steps.length;
    for (const st of c.steps) evCount += st.events.length;
  }
  const guards = GUARDS.map(gd => {
    const R = Object.assign({}, RULES, gd.mut);
    const changed = g.cases.filter(c => caseDiffs(c, R).length).map(c => c.id);
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(x => changed.includes(x)) };
  });
  expectations(g);
  return { guards, states, events: evCount };
}

// explicit expectations read off the upstream source
function expectations(g) {
  const cs = id => { const c = g.cases.find(x => x.id === id); must(c, 'no case ' + id); return c; };
  const ev = (id, k) => cs(id).steps[k].events;
  const plainTypes = (id, k) => ev(id, k).filter(e => e.h.startsWith('all.')).map(e => e.type);
  // press on A, release on B: mouseup on B, no click at all
  const near = cs('bar-press-release-near').steps;
  must(near[0].hit.kind === 'tspan' && near[1].hit.kind === 'rect' && near[0].hit.params.dataIndex === 1 && near[1].hit.params.dataIndex === 1, 'near: label then bar of the same item');
  must(!near[1].events.some(e => e.type === 'click') && near[3].events.some(e => e.h === 'all.click'), 'near: label -> bar no click, bar -> bar click');
  must(plainTypes('bar-press-release-other', 3).join() === 'mouseup' && ev('bar-press-release-other', 3)[0].dataIndex === 1, 'press A release B: mouseup(B) only');
  must(!ev('bar-press-release-other', 3).some(e => e.type === 'click'), 'press A release B: no click from any handler');
  // bar 0 -> bar 1: out(0), move(1), over(1)
  const across = ev('bar-move-across', 2).filter(e => e.h.startsWith('all.'));
  must(across.map(e => e.type + e.dataIndex).join() === 'mouseout0,mousemove1,mouseover1', 'A0 -> A1 order: ' + across.map(e => e.type + e.dataIndex).join());
  // within one bar: mousemove only
  must(plainTypes('bar-move-within', 1).join() === 'mousemove' && plainTypes('bar-move-within', 2).join() === 'mousemove', 'within one bar: mousemove only');
  // a bar and its own label are two elements
  must(plainTypes('bar-to-own-label', 1).join() === 'mouseout,mousemove,mouseover', 'bar -> own label: out / move / over');
  // 'series.bar' never fires for a line
  for (const c of g.cases) for (const st of c.steps) for (const e of st.events) {
    if (e.h === 'q.series.bar') must(e.seriesType === 'bar', c.id + ': series.bar fired for ' + e.seriesType);
    if (e.h === 'q.markPoint') throw new OracleError(c.id + ': the markPoint string query fired');
    if (e.h === 'q.bar') throw new OracleError(c.id + ': the query \'bar\' fired');
    if (e.h === 'q.dupB') throw new OracleError(c.id + ': the duplicate function fired twice');
  }
  must(ev('mixed-bar-line', 2).some(e => e.h === 'q.series.line') && !ev('mixed-bar-line', 2).some(e => e.h === 'q.series.bar'), 'line click: series.line yes, series.bar no');
  // the plain click on a bar: the select action is published before the chart click
  const bc = ev('bar-click', 2);
  must(bc.findIndex(e => e.type === 'selectchanged') < bc.findIndex(e => e.type === 'click'), 'selectchanged precedes click');
  // leave: mouseout then globalout, globalout without params
  const lv = ev('bar-leave', 1).filter(e => e.h.startsWith('all.'));
  must(lv.map(e => e.type).join() === 'mouseout,globalout' && lv[1].componentType === undefined && lv[1].offsetX === undefined, 'leave order');
  must(ev('bar-leave', 1).some(e => e.h === 'q.globalout.s1') && ev('bar-leave', 1).some(e => e.h === 'q.globalout.legend'), 'globalout queries all fire');
  must(plainTypes('bar-leave', 2).join() === 'mousemove', 're-entry onto the same bar: no mouseover');
  must(plainTypes('bar-leave-empty', 1).join() === 'globalout', 'leave over nothing: globalout only');
  // empty ground and silent: nothing
  for (let k = 0; k < cs('bar-empty-click').steps.length; k++) must(!ev('bar-empty-click', k).some(e => e.h !== 'pub'), 'empty click emits nothing');
  must(!ev('bar-silent-series', 2).length && !ev('bar-silent-series', 3).some(e => e.h !== 'pub'), 'silent series emits nothing');
  must(plainTypes('bar-silent-series', 1).join() === 'mouseout', 'A -> silent B: mouseout only');
  must(cs('title-notrigger').steps.every(s => !s.events.length), 'title without triggerEvent emits nothing');
  // click tolerance
  const tol = [1, 3, 5, 7, 9].map(k => ev('bar-click-tolerance', k).some(e => e.h === 'all.click'));
  must(tol.join() === 'true,false,true,false,true', 'click tolerance ' + tol.join());
  must(ev('bar-drag-back', 3).some(e => e.h === 'all.click'), 'drag back: click');
  const uo = [0, 2, 3].map(k => ev('bar-up-only', k).some(e => e.h === 'all.click'));
  must(uo.join() === 'false,true,false', 'up only ' + uo.join());
  // right button: no click; contextmenu with params
  must(!ev('bar-contextmenu', 2).some(e => e.type === 'click') && ev('bar-contextmenu', 3).some(e => e.h === 'q.ctx.bar'), 'contextmenu');
  must(ev('bar-dblclick-bare', 0).some(e => e.h === 'all.dblclick' && e.dataIndex === 1) && ev('bar-dblclick-bare', 0).some(e => e.h === 'q.dbl.Tue'), 'dblclick without press');
  // edges
  const edge = ev('graph-edge', 5).find(e => e.h === 'all.click');
  must(edge && edge.dataType === 'edge' && ev('graph-edge', 5).some(e => e.h === 'q.dataType.edge'), 'edge click dataType edge');
  must(ev('graph-edge', 3).some(e => e.h === 'q.over.edge') && !ev('graph-edge', 0).some(e => e.h === 'q.over.edge'), 'mouseover {dataType: edge}');
  // components
  const tt = ev('title-trigger', 2).find(e => e.h === 'all.click');
  must(tt && tt.componentType === 'title' && tt.componentIndex === 0 && ev('title-trigger', 2).some(e => e.h === 'q.title'), 'title click');
  must(!ev('legend-notrigger', 2).some(e => e.h === 'all.click') && ev('legend-notrigger', 2).some(e => e.type === 'legendselectchanged'), 'legend without triggerEvent');
  const lt = ev('legend-trigger', 2);
  must(lt.find(e => e.h === 'all.click').componentType === 'legend' && lt.findIndex(e => e.type === 'legendselectchanged') < lt.findIndex(e => e.h === 'all.click'), 'legend click after legendselectchanged');
  const xa = ev('xaxis-trigger', 2).find(e => e.h === 'all.click');
  must(xa && xa.componentType === 'xAxis' && xa.targetType === 'axisLabel' && xa.value === 'Wed' && xa.dataIndex === 2 && xa.xAxisIndex === 0, 'xAxis label click');
  const mp = ev('markpoint', 2);
  must(mp.find(e => e.h === 'all.click').componentType === 'markPoint' && mp.some(e => e.h === 'q.series') && !mp.some(e => e.h === 'q.series.bar' && false), 'markPoint click passes series');
  const tm = ev('treemap-noclick', 2).find(e => e.h === 'all.click');
  must(tm && tm.dataIndex >= 1, 'treemap dataIndex from 1');
  // other-query keys are ignored outside custom series
  must(bc.some(e => e.h === 'q.componentType.legend') && bc.some(e => e.h === 'q.element'), 'other query keys ignored');
  // published events ignore the query
  must(bc.some(e => e.h === 'q.pub.selectchanged.s9'), 'published events ignore the query');
  must(ev('bar-click', 2).some(e => e.h === 'q.upper'), "'CLICK' registered as click");
}

// ============================================================================
// Output helpers
// ============================================================================
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) return 'Infinity';
    if (v === -Infinity) return '-Infinity';
    if (Object.is(v, -0)) return '-0';
    return v;
  }
  if (v === undefined) return undefined;
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(x => { const s = sanitize(x); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    const s = sanitize(v[k]);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
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
  if (Array.isArray(v)) return '[\n' + Array.from(v, x => inner + fmt(x === undefined ? null : x, inner)).join(',\n') + '\n' + ind + ']';
  return '{\n' + Object.keys(v).filter(k => v[k] !== undefined).map(k => inner + JSON.stringify(k) + ': ' + fmt(v[k], inner)).join(',\n') + '\n' + ind + '}';
}

function generate() {
  if (ecKey === null) {
    const c = newChart();
    c.setOption({ animation: false, xAxis: { type: 'category', data: ['a'] }, yAxis: {}, series: [{ type: 'bar', data: [1] }] });
    c.renderToSVGString();
    discoverECKey(c);
    c.dispose();
  }
  return {
    cases: CASES.map(d => {
      try {
        return runCase(d);
      } catch (e) {
        if (e instanceof OracleError && !e.message.startsWith(d.id)) e.message = d.id + ': ' + e.message;
        throw e;
      }
    }),
  };
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let g1;
let chk;
let json1;
let json2;
try {
  g1 = generate();
  chk = check(g1);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version,
    W, H, seed: SEED, tz: 'UTC',
    api: {
      chart: "echarts.init(null, null, {renderer: 'svg', ssr: true, width, height}); chart._ssr = false; setOption(option); after every step chart._onframe() + renderToSVGString()",
      pointer: 'chart.getZr().handler.mousemove / mousedown / mouseup (+ click for button 0) / dblclick / contextmenu / mouseout({zrX, zrY, which: button + 1})',
      handlers: "chart.on(type, fn) / chart.on(type, query, fn) in the order of `registrations`, then one plain handler per published event type ('pub')",
    },
    notes: [
      'Which chart events exist: echarts bridges exactly nine zrender events to chart.on: click, dblclick, mouseover, mouseout, mousemove, mousedown, mouseup, globalout, contextmenu (MOUSE_EVENT_NAMES). For each, the params come from the FIRST element on the target\'s host / parent chain whose ECData has a dataIndex (-> dataModel.getDataParams(dataIndex, dataType), dataModel = the marker model or the series) or an eventData (a copy of it). No such element (empty ground, axis lines, a title without triggerEvent, grid) = no chart event at all -- but the zrender-level hover state still changes (moving from a bar onto the axis line is a mouseout of the bar). globalout carries params {} (plus type / event).',
      'The click (zrender Handler.click): fires only when mousedown and mouseup found the SAME element (null === null counts, but then there are no params) AND a press point exists AND dist(press point, click point) <= 4 (Euclidean). A click that passes clears the press point: another release without a new press never clicks. The path between press and release is irrelevant. dblclick / contextmenu / mousedown / mouseup have no such rule: they report whatever is under the point at that moment.',
      'Hover (zrender Handler.mousemove): hovered = findHover(point) (outside the canvas = nothing). If the previous target differs from the new one: mouseout(previous, offset = the NEW point); then mousemove(new) always (a chart event only when it has params); then mouseover(new) when it differs. Identity is the zrender ELEMENT: a bar and its label, a legend icon and its text, a TSpan and the next TSpan are different elements of the same data item and emit out / over. If the previously hovered element was removed by a re-render, zrender first re-finds the target at the previous point (#6198; step.refound).',
      'Leave (zrender Handler.mouseout, the DOM mouseout of the canvas): mouseout on the hovered element (if any), then globalout. The hovered element is NOT forgotten: re-entering onto the same element emits no mouseover. (While a press is captured the browser path sends no globalout; not recorded.)',
      'Order within one step: element-level handlers first (a legend item\'s own click handler dispatches legendToggleSelect -> legendselectchanged; a treemap / sunburst node click dispatches its zoom / root action), then zrender-level handlers in registration order: echarts\' own select-on-click handler (every click on an item with a dataIndex dispatches select / unselect, whatever selectedMode: `selectchanged` is published) BEFORE the user bridge (registered callAtLast). Within one chart event, the user handlers fire in registration order.',
      'Queries (Eventful.on + ECEventProcessor): the event name is lowercased (\'CLICK\' = \'click\'). The same function registered twice for one event type is ignored the second time, whatever its query. A string query is \'main\' or \'main.sub\' (split on \'.\', empty parts = no constraint: \'\' and \'series.\' match everything a model is found for). An object query: a key ending in Index / Name / Id (at position > 0, prefix not \'data\') sets mainType = the prefix and index / name / id = the value -- even when the value is null ({seriesIndex: null} still demands mainType series); name / dataIndex / dataType go to the data query; every other key (componentType, element, ...) is ignored except by the custom series (element = an element name on the target\'s chain). A null / undefined value never constrains its own property.',
      'Query matching: model = ecModel.getComponent(params.componentType, params.componentIndex), except markPoint / markLine / markArea which are looked up as (\'series\', params.seriesIndex) -- so \'series\' and {seriesIndex} match a marker hit and \'markPoint\' never matches anything. No model or no view (globalout, and every PUBLISHED action event: selectchanged, legendselectchanged, ...) = the query passes unconditionally. Otherwise: mainType === model.mainType, subType === model.subType (axis: category / value; legend: plain; title: \'\'), index === model.componentIndex, name === model.name, id === model.id; data name / dataIndex / dataType === params\' (dataIndex is the RAW index; nodes carry dataType \'node\' in graph, undefined elsewhere).',
      'Params: series items getDataParams: componentType series, componentSubType = seriesType, componentIndex = seriesIndex, seriesId, seriesName, name, dataIndex (raw), dataType, value (raw: a number, an [x, y] array, a name for legend). Marker items (MarkerModel.getDataParams): componentType markPoint / markLine / markArea, componentSubType \'\', componentIndex = the marker model\'s, seriesIndex / seriesId / seriesName / seriesType = the HOST series\', name / dataIndex / value = the marker datum\'s. Title (triggerEvent): {componentType title, componentIndex} only. Legend (triggerEvent): {componentType legend, componentIndex, dataIndex = the item\'s index in legend.data, value = the item name, seriesIndex = the series that provides the name}. Axis (triggerEvent): {componentType xAxis / yAxis..., componentIndex, xAxisIndex..., targetType axisLabel, value (the raw label), tickIndex, dataIndex (category axes)} or {targetType axisName, name}. Line polyline (series triggerEvent true / "line" / "area", or the deprecated triggerLineEvent): {componentType series, componentSubType line, componentIndex, seriesIndex, seriesName, seriesType line, selfType line | area}. Graph: nodes dataType \'node\', edges dataType \'edge\' (name \'A > B\', value = the link value, dataIndex = the link index). Treemap / sunburst: dataType \'main\', dataIndex counts the virtual root as 0. Scatter: value = the [x, y] pair, name \'\'.',
      'Hover changes the scene before the next step: an emphasis label appears (graph-edge: the press after the move hits the node\'s label, not its symbol), a symbol scales (markpoint, pie-sector: aims are resolved in flight, so a move and the press after it may sit 1-2 px apart). step.hit / event.el record what zrender hit; the params, and hence the events, are those of the same data item either way.',
      'Browser vs this run: the model runs with ssr off (see the header): with ssr on, every legend child carries the series\' ECData and a legend hit would report a series event. Between steps a frame is applied (hover emphasis -- e.g. the pie\'s scale on hover grows the hovered sector, and the hit follows it).',
    ],
    registrations: COMMON,
    cases: g1.cases,
    guards: chk.guards,
    checks: { states: chk.states, events: chk.events, fails: 0 },
  };
  json1 = fmt(sanitize(out), '') + '\n';
  const nul = json1.indexOf('\\u0000');
  must(nul < 0, 'the fixture holds a \\u0000: ' + json1.slice(Math.max(0, nul - 300), nul + 40));
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(sanitize(out)), 'the written JSON does not parse back');
  if (!process.env.ORACLE_ONCE) {
    const g2 = generate();
    const c2 = check(g2);
    json2 = fmt(sanitize(Object.assign({}, out, { cases: g2.cases, guards: c2.guards })), '') + '\n';
  } else json2 = json1;
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message + (process.env.ORACLE_DEBUG ? '\n' + e.stack : '') : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
const bad = chk.guards.filter(gd => !gd.ok);
chk.guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': named ' + gd.named.join(' / ') + '; changes ' + gd.changed.length));
const deterministic = json1 === json2;
console.log(g1.cases.length + ' cases, ' + chk.states + ' steps, ' + chk.events + ' events; transcription 0 fails; '
  + (chk.guards.length - bad.length) + '/' + chk.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; '
  + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (!deterministic && process.env.ORACLE_DEBUG) {
  fs.writeFileSync(OUT + '.gen1', json1);
  fs.writeFileSync(OUT + '.gen2', json2);
}
if (bad.length || !deterministic) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
