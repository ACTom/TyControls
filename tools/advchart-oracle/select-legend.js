/*
Upstream's own answers for the SELECT state, series selectedMode, the
select / unselect / toggleSelect / highlight / downplay actions and the
events they publish, hover focus / blur / blurScope across series, the
emphasis / select / blur looks (incl. the pie's selectedOffset and label
states), and the legend: click toggling, selectedMode, the inactive colours
of its items, legend hover -> series highlight, and the series / pie-slice
filtering a toggle causes. The rules are transcribed in
wf87/states.md (file:line into echarts 6.1 / zrender 6.1).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false` on every
case, process.env.TZ = 'UTC' (checked), Math.random = the port's xorshift32
reseeded per chart. Like mouse-events.js: the chart is created with
ssr: true and then chart._ssr = false BEFORE setOption (the browser's
model), pointer events go straight to zrender's Handler with integer
{zrX, zrY}, and after EVERY step chart._onframe() (applies the state flags,
as a browser frame would) + chart.renderToSVGString() (refreshes the display
list the hit test walks). The recorded state is read from the live elements
after that frame.

  node tools/advchart-oracle/select-legend.js

writes tests/fixtures/advchart-select-legend.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Steps (case.steps[]):
  {type: 'move', x, y, aim, hit}   handler.mousemove
  {type: 'click', x, y, aim, hit}  handler.mousemove, mousedown, mouseup and
                                   click at the same point (one step, one
                                   frame after it: the browser's full click
                                   without a frame in between)
  {type: 'action', payload}        chart.dispatchAction(payload)
  step 0 is always {type: 'init'}: the state right after setOption + frame.
  hit (pointer steps; the zrender target at (x, y) BEFORE the step):
    {el: element id (the n-th distinct element seen in this case), kind:
    zrender type, hd: the highlight dispatcher = the OUTERMOST element on the
    host / parent chain flagged highDownDispatcher, as {s, i} (series index,
    INNER data index) or {legend: legend item index} or null; dp: the select
    dispatcher = the FIRST element on the chain whose ECData has a dataIndex,
    {s, i, dt?} or null; legend: the legend item name or null}
  refound (pointer steps, only when the element hovered before the step was
    removed by a re-render): the hit zrender re-finds at the old point and
    uses as the "previous" target (#6198; a re-rendered legend item under a
    resting pointer is therefore NOT a new mouseover)
Per step:
  events[]  every published event in order, {type, payload} (payload = the
            event object as plain data; fromActionPayload kept; auto series
            ids '<auto id>'; `from` '<view uid>'), incl. the legacy
            pieselectchanged / pieselected / pieunselected / mapselect...
            (handlers are registered for them, which is what makes upstream
            emit them: ecIns.isSilent), and the chart-level 'click' mouse
            event reduced to {type: 'click', payload: {componentType,
            seriesIndex, dataIndex, name}} (only to show the order).
            brushselected (published by the full build's brush component
            after every full update, no brush in any case) is left out.
  state     {series[], legend?}
    series[s] = {s, type, shown (not filtered by the legend), selectedMap
      (option.selectedMap: null | 'all' | {name: bool}), selectedIndices
      (getSelectedDataIndices(): RAW indices), items[] (one per INNER index;
      [] when not shown), poly? (line: the polyline)}
    item = {i (inner), d (raw), name, el (element id), st (currentStates),
      sel (el.selected), hs (hoverState 0 normal / 1 blur / 2 emphasis), px
      (the element has echarts' default state proxy = emphasis not
      disabled), hbo (__highByOuter bits of the data item's graphic el: the
      bar, the sector, the Symbol GROUP), z2, fill, stroke, lineWidth,
      opacity, rest {...}, label?, guide?} plus
        pie    x, y (the element's translation = the selectedOffset), r,
               a0 / a1 (shape start / end angle), rest {.., x, y, r}
        bar    bx, by, bw, bh (the rect shape)
        line   the SYMBOL PATH (childAt(0) of the Symbol group): sx / sy
               (its scale = half size), gx / gy (the group position), ghs
               (the group's hoverState), phbo (the PATH's __highByOuter:
               Symbol.highlight marks the path); rest {.., sx, sy}
      rest = the element's normal ("rest") values: zrender keeps the value a
      state replaced in el._normalState; a key no state touched is the
      current value
      label = {st, px, has (which state objects exist: e / b / s), ignore,
      fill, opacity, z2, x, y, rest {ignore, fill, opacity, z2, x, y}} (the
      attached text; its state list always equals the host's); guide = {st,
      x, y, ignore} (pie label line)
    poly = {st, hs, stroke, lineWidth, opacity, z2, rest}
    legend = {selected (option.selected), items[{name, icon {fill, stroke,
      lineWidth, opacity} | 'group', text {fill}}]}
  Numbers are JSON numbers (shortest round-trip form of the double).
  Colours are upstream's strings as they are ('#5070dd', lifted ones
  'rgba(88,123,243,1)').
  hbo bit values: a highlightKey maps to a digit in order of first use in
  the PROCESS (upstream keeps the map module-global); only which bits are
  set matters.

Cross-check (any failure: nothing is written, exit 1):
  1. a TRANSCRIPTION of the rules (states.md) -- flags (hoverState, selected,
     __highByOuter, the polyline flag), the selection model, the legend
     model, the event sequence with payloads, and every recorded visual
     (states list, z2 incl. the creep, fill / stroke / lineWidth / opacity,
     pie translation / r, symbol scale, label states / ignore / fill /
     opacity / z2 / position, label line, polyline, legend icon / text
     colours) -- replays every case from its option, its steps and the
     recorded hits, taking only the element STRUCTURE from the recording
     (which elements exist, their ids and rest values), and must reproduce
     every step exactly (1e-9 relative on doubles);
  2. each guard mutates one rule and must change every case it names;
  3. explicit expectations read straight off the upstream source;
  4. the whole fixture is generated twice (byte-identical).
  ORACLE_DIFFS=n lists the first n transcription diffs of every case;
  ORACLE_ONCE=1 skips the second generation; ORACLE_PROBE=<id>|* dumps raw
  runs.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-select-legend.json');

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

// ============================================================================
// Cases
// ============================================================================
const CAT = ['Mon', 'Tue', 'Wed', 'Thu'];
const PIE_DATA = [{ name: 'Mon', value: 10 }, { name: 'Tue', value: 20 }, { name: 'Wed', value: 30 }, { name: 'Thu', value: 15 }];
const pieOpt = (s, top) => Object.assign({ animation: false,
  series: [Object.assign({ type: 'pie', name: 'P', radius: ['0%', '50%'], data: clone(PIE_DATA) }, s || {})] }, top || {});
const barS = (name, data, extra) => Object.assign({ type: 'bar', name, data }, extra || {});
const A_DATA = [12, 20, 15, 30];
const B_DATA = [8, 25, 18, 22];
const barOpt = (a, b, top) => Object.assign({ animation: false,
  xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
  series: [barS('A', A_DATA, a), barS('B', B_DATA, b)] }, top || {});
const SUN_DATA = [{ name: 'A', children: [{ name: 'a1', value: 2 }, { name: 'a2', children: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }] }] },
  { name: 'B', children: [{ name: 'b1', value: 4 }] }];
const lineS = (name, data, extra) => Object.assign({ type: 'line', name, data, symbolSize: 12 }, extra || {});

const item = (s, d) => ({ item: [s, d] });
const legend = name => ({ legend: name });
const empty = (x, y) => ({ empty: [x || 5, y || 5] });
const mv = at => ({ type: 'move', at });
const ck = at => ({ type: 'click', at });
const act = payload => ({ type: 'action', payload });

const CASES = [
  // ---------------------------------------------------------------- pie select
  { id: 'pie-single', note: "pie selectedMode 'single': hover slice 1, click it (select: offset 10 along the mid angle, z2 +9 under the +10 of the hover), click slice 2 (1 unselected), click slice 2 again (the element is selected: the click dispatches unselect), move off",
    option: pieOpt({ selectedMode: 'single' }), steps: [mv(item(0, 1)), ck(item(0, 1)), ck(item(0, 2)), ck(item(0, 2)), mv(empty())] },
  { id: 'pie-multiple', note: "pie 'multiple': click 0, click 2 (both kept), click 0 (unselect 0 only)",
    option: pieOpt({ selectedMode: 'multiple' }), steps: [ck(item(0, 0)), ck(item(0, 2)), ck(item(0, 0)), mv(empty())] },
  { id: 'pie-series', note: "pie 'series': a click selects every slice (selectedMap 'all'); a click on a selected slice unselects ALL (unselect on 'series' clears the map); again all",
    option: pieOpt({ selectedMode: 'series' }), steps: [ck(item(0, 1)), ck(item(0, 3)), ck(item(0, 3)), mv(empty())] },
  { id: 'pie-off', note: 'pie without selectedMode: every item click still dispatches select (select + selectchanged published, selected [] -- nothing changes); legacy pie events need a series in `selected`, so none',
    option: pieOpt(), steps: [ck(item(0, 1)), ck(item(0, 1)), mv(empty())] },
  { id: 'pie-offset', note: "selectedOffset 25, 'single', data[3].selected true (selected at load through _initSelectedMapFromData); click 0 moves the selection",
    option: pieOpt({ selectedMode: 'single', selectedOffset: 25, data: [{ name: 'Mon', value: 10 }, { name: 'Tue', value: 20 }, { name: 'Wed', value: 30 }, { name: 'Thu', value: 15, selected: true }] }),
    steps: [ck(item(0, 0)), mv(empty())] },
  { id: 'pie-select-style', note: "'multiple' with select.itemStyle {color, borderColor, borderWidth} + select.label.color, emphasis.scaleSize 12: select look; hovering a SELECTED slice lifts the SELECT colour (savePathStates keeps selectFill)",
    option: pieOpt({ selectedMode: 'multiple', select: { itemStyle: { color: '#222222', borderColor: '#ff0000', borderWidth: 3 }, label: { color: '#ff0000' } }, emphasis: { scaleSize: 12 } }),
    steps: [ck(item(0, 1)), mv(empty()), mv(item(0, 1)), mv(item(0, 2)), mv(empty())] },
  { id: 'pie-hover-creep', note: "'single': a selected slice hovered on and off: every state switch sets z2 = CURRENT z2 + 9 (select) / + 10 (emphasis) -- the z2 creeps up while any state stays applied; it returns to rest only when the state list empties",
    option: pieOpt({ selectedMode: 'single' }), steps: [ck(item(0, 1)), mv(empty()), mv(item(0, 1)), mv(empty()), mv(item(0, 1)), mv(empty()), ck(item(0, 1)), mv(empty())] },
  { id: 'pie-dup-names', note: "'multiple', two slices named 'a': selection is keyed by NAME -- clicking slice 0 selects slices 0 and 2 (isSelected), while getSelectedDataIndices lists raw 0 only; clicking slice 2 (selected) unselects the name",
    option: pieOpt({ selectedMode: 'multiple', data: [{ name: 'a', value: 10 }, { name: 'b', value: 20 }, { name: 'a', value: 30 }] }),
    steps: [ck(item(0, 0)), ck(item(0, 2)), ck(item(0, 1)), mv(empty())] },
  // ---------------------------------------------------------------- bar / line select
  { id: 'bar-single', note: "bar A 'single', B without selectedMode: A1, A2, B1 (B: no change; the selectchanged still lists A), A2 again (unselect). Default bar select look: borderColor #3c3c41, borderWidth 2",
    option: barOpt({ selectedMode: 'single' }), steps: [ck(item(0, 1)), ck(item(0, 2)), ck(item(1, 1)), ck(item(0, 2)), mv(empty())] },
  { id: 'bar-multiple-style', note: "bar A 'multiple', select {itemStyle.color #000000, label {show, color}}, data[2].select.disabled: clicks 0, 2 (the map gets Wed true but isSelected is false: no select state, and a second click dispatches select again), 1; hover the selected A0 (lift of the SELECT colour)",
    option: barOpt({ selectedMode: 'multiple', select: { itemStyle: { color: '#000000' }, label: { show: true, color: '#ff0000' } },
      data: [12, 20, { value: 15, select: { disabled: true } }, 30] }),
    steps: [ck(item(0, 0)), ck(item(0, 2)), ck(item(0, 2)), ck(item(0, 1)), mv(item(0, 0)), mv(empty())] },
  { id: 'bar-series', note: "bar A 'series': one click selects the whole series, a click on any selected bar clears it",
    option: barOpt({ selectedMode: 'series' }), steps: [ck(item(0, 1)), ck(item(0, 3)), mv(empty())] },
  { id: 'bar-off', note: 'bars without selectedMode: click A1 = select action, selectchanged {selected: []}, no state',
    option: barOpt(), steps: [ck(item(0, 1)), mv(empty())] },
  { id: 'line-select', note: "line 0 'single' (no select style for line: the select state is only z2 + 9 on the symbol path), line 1 'multiple' with select.itemStyle {color, borderColor, borderWidth}",
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [lineS('L', [10, 30, 20, 25], { selectedMode: 'single' }), lineS('M', [5, 12, 40, 8], { selectedMode: 'multiple', select: { itemStyle: { color: '#ff0000', borderColor: '#000000', borderWidth: 2 } } })] },
    steps: [ck(item(0, 1)), ck(item(0, 2)), ck(item(1, 2)), ck(item(1, 0)), mv(empty())] },
  // ---------------------------------------------------------------- select actions
  { id: 'action-select-bar', note: "A and B 'multiple': select {seriesIndex 0, dataIndex [0, 2]}, unselect {dataIndex 0}, toggleSelect [1, 2], select by seriesName + name, select {dataIndex 3} with no series (every series), toggleSelect by seriesId",
    option: barOpt({ id: 'sa', selectedMode: 'multiple' }, { id: 'sb', selectedMode: 'multiple' }),
    steps: [act({ type: 'select', seriesIndex: 0, dataIndex: [0, 2] }), act({ type: 'unselect', seriesIndex: 0, dataIndex: 0 }),
      act({ type: 'toggleSelect', seriesIndex: 0, dataIndex: [1, 2] }), act({ type: 'select', seriesName: 'B', name: 'Wed' }),
      act({ type: 'select', dataIndex: 3 }), act({ type: 'toggleSelect', seriesId: 'sb', dataIndex: 3 })] },
  { id: 'action-select-single', note: "A 'single': select [0, 2] keeps the LAST; select by dataIndexInside; unselect by name",
    option: barOpt({ selectedMode: 'single' }),
    steps: [act({ type: 'select', seriesIndex: 0, dataIndex: [0, 2] }), act({ type: 'select', seriesIndex: 0, dataIndexInside: 1 }), act({ type: 'unselect', seriesIndex: 0, name: 'Tue' })] },
  { id: 'action-select-pie', note: "pie 'single': select by name (legacy pieselected), toggleSelect (no legacy event), select by dataIndex, unselect (selected [] -> no legacy event)",
    option: pieOpt({ selectedMode: 'single' }),
    steps: [act({ type: 'select', seriesIndex: 0, name: 'Wed' }), act({ type: 'toggleSelect', seriesIndex: 0, name: 'Wed' }),
      act({ type: 'select', seriesIndex: 0, dataIndex: 1 }), act({ type: 'unselect', seriesIndex: 0, dataIndex: 1 })] },
  // ---------------------------------------------------------------- highlight / downplay
  { id: 'highlight-bar', note: 'highlight / downplay by dataIndex, the whole series, seriesName + name, highlightKey bits: an element highlighted by action ignores hover in / out (__highByOuter); only when every bit is cleared does it leave emphasis',
    option: barOpt(),
    steps: [act({ type: 'highlight', seriesIndex: 0, dataIndex: 1 }), mv(item(0, 1)), mv(empty()), act({ type: 'downplay', seriesIndex: 0, dataIndex: 1 }),
      act({ type: 'highlight', seriesIndex: 1 }), act({ type: 'downplay', seriesIndex: 1 }), act({ type: 'highlight', seriesName: 'A', name: 'Wed' }),
      act({ type: 'downplay', seriesName: 'A', name: 'Wed' }), act({ type: 'highlight', seriesIndex: 0, dataIndex: 0, highlightKey: 7 }),
      act({ type: 'highlight', seriesIndex: 0, dataIndex: 0 }), act({ type: 'downplay', seriesIndex: 0, dataIndex: 0 }),
      act({ type: 'downplay', seriesIndex: 0, dataIndex: 0, highlightKey: 7 })] },
  { id: 'highlight-focus', note: "bars focus 'series': highlight A1 blurs B; highlight B0 first leaves all blur, then blurs A -- including A1, which keeps its __highByOuter but shows blur; downplay A1; highlight with notBlur",
    option: barOpt({ emphasis: { focus: 'series' } }, { emphasis: { focus: 'series' } }),
    steps: [act({ type: 'highlight', seriesIndex: 0, dataIndex: 1 }), act({ type: 'highlight', seriesIndex: 1, dataIndex: 0 }),
      act({ type: 'downplay', seriesIndex: 0, dataIndex: 1 }), act({ type: 'downplay', seriesIndex: 1, dataIndex: 0 }),
      act({ type: 'highlight', seriesIndex: 0, dataIndex: 2, notBlur: true }), mv(item(1, 1)), mv(empty())] },
  { id: 'highlight-pie', note: 'pie highlight / downplay by name, then the whole series',
    option: pieOpt(), steps: [act({ type: 'highlight', seriesIndex: 0, name: 'Tue' }), act({ type: 'downplay', seriesIndex: 0, name: 'Tue' }), act({ type: 'highlight', seriesIndex: 0 }), act({ type: 'downplay', seriesIndex: 0 })] },
  { id: 'highlight-line', note: 'line with symbols: highlight by dataIndex marks the SYMBOL PATH (Symbol.highlight: enterEmphasis(childAt(0))) and the polyline; hovering the symbol then leaving it clears the emphasis anyway (the group, the hover dispatcher, has no __highByOuter)',
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' }, series: [lineS('L', [10, 30, 20, 25])] },
    steps: [act({ type: 'highlight', seriesIndex: 0, dataIndex: 2 }), mv(item(0, 2)), mv(empty()), act({ type: 'highlight', seriesIndex: 0, dataIndex: 1 }), act({ type: 'downplay', seriesIndex: 0, dataIndex: 1 }), act({ type: 'highlight', seriesIndex: 0 }), act({ type: 'downplay', seriesIndex: 0 })] },
  // ---------------------------------------------------------------- legend
  { id: 'legend-bar-toggle', note: 'legend click on B: downplay B, legendToggleSelect (legendselectchanged {name, selected}), highlight B -- B is filtered out, A re-laid out alone; B\'s legend item takes the inactive colours; click again',
    option: barOpt({}, {}, { legend: {} }), steps: [ck(legend('B')), mv(empty()), ck(legend('B')), mv(empty())] },
  { id: 'legend-hover-bar', note: 'legend hover: over A = highlight {seriesName A} (every bar of A), A -> B = downplay A then highlight B, off = downplay B',
    option: barOpt({}, {}, { legend: {} }), steps: [mv(legend('A')), mv(legend('B')), mv(empty())] },
  { id: 'legend-hover-focus', note: "bars focus 'series': the legend highlight blurs the other series (blurSeriesFromHighlightPayload: the focus of the element at dataIndex 0)",
    option: barOpt({ emphasis: { focus: 'series' } }, { emphasis: { focus: 'series' } }, { legend: {} }), steps: [mv(legend('A')), mv(empty())] },
  { id: 'legend-single', note: "legend selectedMode 'single': at load only the first item stays on; click B (A off, B on); click B again (unSelect is a no-op in single, the event still fires)",
    option: barOpt({}, {}, { legend: { selectedMode: 'single' } }), steps: [ck(legend('B')), ck(legend('B')), mv(empty())] },
  { id: 'legend-mode-false', note: 'legend selectedMode false: the hit rect is silent too -- no hover highlight, no click',
    option: barOpt({}, {}, { legend: { selectedMode: false } }), steps: [mv({ xy: 'legend A' }), ck({ xy: 'legend A' }), mv(empty())] },
  { id: 'legend-pie', note: "pie 'multiple' + legend on the slice names: select Wed, legend off Tue (the slice is filtered: inner indices shift, the pie re-lays out; Wed stays selected by name), click Thu (inner 2, raw 3: selectchanged lists RAW indices), legend Tue back on",
    option: pieOpt({ selectedMode: 'multiple' }, { legend: {} }),
    steps: [ck(item(0, 2)), ck(legend('Tue')), mv(empty()), ck(item(0, 3)), ck(legend('Tue')), mv(empty())] },
  { id: 'legend-hover-pie', note: 'legend hover on a slice name: highlight {name} (no seriesName: every series is asked; the pie finds the slice by name)',
    option: pieOpt({}, { legend: {} }), steps: [mv(legend('Wed')), mv(legend('Mon')), mv(empty())] },
  { id: 'legend-actions', note: 'legendUnSelect / legendSelect / legendToggleSelect / legendInverseSelect / legendAllSelect: event payloads and filtering; an unknown name only enters the map',
    option: barOpt({}, {}, { legend: {} }),
    steps: [act({ type: 'legendUnSelect', name: 'A' }), act({ type: 'legendSelect', name: 'A' }), act({ type: 'legendToggleSelect', name: 'B' }),
      act({ type: 'legendInverseSelect' }), act({ type: 'legendAllSelect' }), act({ type: 'legendUnSelect', name: 'Nope' })] },
  { id: 'legend-inactive-custom', note: 'inactiveColor / inactiveBorderColor / inactiveBorderWidth 3 / textStyle.color; A has a border (itemStyle borderWidth 1), B none; both off at load (legend.selected), then A back on. A numeric inactiveBorderWidth is NOT used: lineWidth keeps the active value (only \'auto\' is resolved)',
    option: barOpt({ itemStyle: { borderWidth: 1, borderColor: '#000000' } }, {}, { legend: { inactiveColor: '#ff0000', inactiveBorderColor: '#00ff00', inactiveBorderWidth: 3, textStyle: { color: '#123456' }, selected: { A: false, B: false } } }),
    steps: [act({ type: 'legendToggleSelect', name: 'A' })] },
  { id: 'legend-hoverlink-false', note: 'series B legendHoverLink false: hovering its legend item dispatches highlight with excludeSeriesId [B] (nothing lights); A still highlights',
    option: barOpt({ id: 'sa' }, { id: 'sb', legendHoverLink: false }, { legend: {} }), steps: [mv(legend('B')), mv(legend('A')), mv(empty())] },
  // ---------------------------------------------------------------- focus / blur
  { id: 'focus-series-coord', note: "bar A, bar B, line C on one grid and a pie P, all focus 'series' (blurScope default coordinateSystem): hovering A1 blurs B and C (the polyline too), not P (no coordinate system: only its own series counts)",
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [barS('A', A_DATA, { emphasis: { focus: 'series' } }), barS('B', B_DATA, { emphasis: { focus: 'series' } }), lineS('C', [5, 12, 40, 8], { emphasis: { focus: 'series' } }),
        { type: 'pie', name: 'P', center: [520, 80], radius: [0, 40], label: { show: false }, emphasis: { focus: 'series' }, data: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }] }] },
    steps: [mv(item(0, 1)), mv(item(3, 0)), mv(empty())] },
  { id: 'focus-series-global', note: "the same with blurScope 'global': the pie is blurred too; hovering the pie blurs every cartesian series",
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [barS('A', A_DATA, { emphasis: { focus: 'series', blurScope: 'global' } }), barS('B', B_DATA, { emphasis: { focus: 'series', blurScope: 'global' } }), lineS('C', [5, 12, 40, 8], { emphasis: { focus: 'series', blurScope: 'global' } }),
        { type: 'pie', name: 'P', center: [520, 80], radius: [0, 40], label: { show: false }, emphasis: { focus: 'series', blurScope: 'global' }, data: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }] }] },
    steps: [mv(item(0, 1)), mv(item(3, 0)), mv(empty())] },
  { id: 'focus-self-series-scope', note: "bars focus 'self' blurScope 'series' with labels: the other bars of A (and their labels, opacity x 0.1) blur, B untouched",
    option: barOpt({ emphasis: { focus: 'self', blurScope: 'series' }, label: { show: true, position: 'top' } }, { label: { show: true, position: 'top' } }),
    steps: [mv(item(0, 1)), mv(item(0, 2)), mv(empty())] },
  { id: 'focus-two-grids', note: "two grids: A (grid 0), B (grid 1), C (grid 0), focus 'series' coordinateSystem: hovering A blurs C only",
    option: { animation: false, grid: [{ bottom: '55%' }, { top: '55%' }],
      xAxis: [{ type: 'category', data: CAT, gridIndex: 0 }, { type: 'category', data: CAT, gridIndex: 1 }], yAxis: [{ type: 'value', gridIndex: 0 }, { type: 'value', gridIndex: 1 }],
      series: [barS('A', A_DATA, { emphasis: { focus: 'series' } }), barS('B', B_DATA, { xAxisIndex: 1, yAxisIndex: 1, emphasis: { focus: 'series' } }), barS('C', [3, 6, 9, 12], { emphasis: { focus: 'series' } })] },
    steps: [mv(item(0, 1)), mv(item(1, 2)), mv(empty())] },
  { id: 'focus-pie-self', note: "pie focus 'self': the other slices, their labels and label lines blur; hover moves between slices",
    option: pieOpt({ emphasis: { focus: 'self' } }), steps: [mv(item(0, 1)), mv(item(0, 2)), mv(empty())] },
  { id: 'emphasis-label', note: "bar A label hidden, emphasis.label {show, color}: the hovered bar shows its label; B focus 'series' blur.itemStyle.opacity 0.3 (declared, not x 0.1); A's focus 'series' blurs B with the declared value",
    option: barOpt({ label: { show: false }, emphasis: { focus: 'series', label: { show: true, color: '#ff0000' } } }, { blur: { itemStyle: { opacity: 0.3 } } }),
    steps: [mv(item(0, 1)), mv(empty())] },
  { id: 'line-focus', note: "two lines focus 'series': hovering a symbol of L lifts its path, bolds nothing (no emphasis lineStyle), puts L's polyline in emphasis (onHoverStateChange) and blurs M (symbols + polyline)",
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [lineS('L', [10, 30, 20, 25], { emphasis: { focus: 'series' } }), lineS('M', [5, 12, 40, 8], { emphasis: { focus: 'series' } })] },
    steps: [mv(item(0, 1)), mv(empty())] },
  { id: 'emphasis-disabled', note: 'bar A emphasis.disabled: not a highlight dispatcher -- hover and the highlight action change nothing, the click still selects',
    option: barOpt({ selectedMode: 'single', emphasis: { disabled: true, focus: 'series' } }),
    steps: [mv(item(0, 1)), act({ type: 'highlight', seriesIndex: 0, dataIndex: 1 }), ck(item(0, 1)), mv(empty())] },
  // ---------------------------------------------------------------- focus / blur on more types (batch 90)
  { id: 'focus-funnel-self', note: "funnel focus 'self' (no coordinate system): hovering a band blurs the others, their labels and label lines; the hovered band's emphasis label (shown by default) and lift; highlight by dataIndex with the series blurred first; downplay",
    option: { animation: false, series: [{ type: 'funnel', name: 'F', left: 100, width: 300, top: 40, bottom: 40, emphasis: { focus: 'self' },
      data: [{ name: 'a', value: 60 }, { name: 'b', value: 40 }, { name: 'c', value: 20 }] }] },
    steps: [mv(item(0, 1)), mv(item(0, 0)), mv(empty()), act({ type: 'highlight', seriesIndex: 0, dataIndex: 2 }), act({ type: 'downplay', seriesIndex: 0, dataIndex: 2 })] },
  { id: 'focus-heatmap-scatter', note: "a heatmap (focus 'series') and a scatter (focus 'self', blurScope 'series') on one grid: a cell blurs the scatter; a symbol blurs its own series' other symbols (the scatter's group is the dispatcher, its path grows by max(1.1, 3 / r)); a highlight of one symbol sets the GROUP's bit (no Symbol.highlight for a scatter) and its hover does not clear it",
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { min: 0, max: 3, show: false, seriesIndex: 0 },
      series: [{ type: 'heatmap', name: 'H', emphasis: { focus: 'series' }, data: [[0, 0, 1], [1, 0, 2], [2, 1, 3]] },
        { type: 'scatter', name: 'S', symbolSize: 14, emphasis: { focus: 'self', blurScope: 'series' }, data: [[0, 1], [1, 1], [2, 0]] }] },
    steps: [mv(item(0, 1)), mv(item(1, 0)), mv(empty()), act({ type: 'highlight', seriesIndex: 1, dataIndex: 2 }), mv(item(1, 2)), mv(empty()), act({ type: 'downplay', seriesIndex: 1, dataIndex: 2 })] },
  { id: 'focus-candlestick', note: "a candlestick (focus 'series') and a line on one grid: hovering a candle blurs the line (symbols and polyline) and gives the candle the series' default emphasis border width 2; highlight the whole candlestick, downplay",
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value', scale: true },
      series: [{ type: 'candlestick', name: 'K', emphasis: { focus: 'series' }, data: [[20, 30, 10, 35], [30, 25, 20, 40], [25, 32, 22, 36], [32, 28, 26, 38]] },
        lineS('L', [22, 28, 30, 33])] },
    steps: [mv(item(0, 1)), mv(empty()), act({ type: 'highlight', seriesIndex: 0 }), act({ type: 'downplay', seriesIndex: 0 })] },
  { id: 'focus-truthy-other', note: "bar A focus 'adjacency' (truthy, none of the words: blurs everything in scope, its own series included) and blurScope 'nope' (neither 'series' nor 'coordinateSystem': global, the pie too); an element held by an action is NOT spared (only focus 'self' spares)",
    option: { animation: false, xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' },
      series: [barS('A', A_DATA, { emphasis: { focus: 'adjacency', blurScope: 'nope' } }), barS('B', B_DATA),
        { type: 'pie', name: 'P', center: [520, 80], radius: [0, 40], label: { show: false }, data: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }] }] },
    steps: [mv(item(0, 1)), mv(empty()), act({ type: 'highlight', seriesIndex: 0, dataIndex: 2, notBlur: true }), mv(item(0, 0)), mv(empty())] },
  { id: 'focus-sunburst', note: "sunburst, default focus 'descendant' (SunburstSeries.ts:271, SunburstPiece.ts:152-160): hovering a node blurs the series, then its own subtree leaves the blur; the series' default blur opacities (item 0.2, label 0.1); a highlight blurs by the focus of the node it names",
    option: { animation: false, series: [{ type: 'sunburst', name: 'U', radius: [0, '80%'], data: SUN_DATA }] },
    steps: [mv(item(0, 1)), mv(item(0, 3)), mv(empty()), act({ type: 'highlight', seriesIndex: 0, dataIndex: 5 }), act({ type: 'downplay', seriesIndex: 0, dataIndex: 5 })] },
  { id: 'focus-sunburst-ancestor', note: "sunburst focus 'ancestor' on the series, 'relative' on one node: the ancestors (the root's index has no element) or the ancestors and the subtree leave the blur",
    option: { animation: false, series: [{ type: 'sunburst', name: 'U', radius: [0, '80%'], emphasis: { focus: 'ancestor' },
      data: [{ name: 'A', children: [{ name: 'a1', value: 2 }, { name: 'a2', emphasis: { focus: 'relative' }, children: [{ name: 'x', value: 1 }, { name: 'y', value: 2 }] }] }, { name: 'B', children: [{ name: 'b1', value: 4 }] }] }] },
    steps: [mv(item(0, 4)), mv(item(0, 3)), mv(empty())] },
  { id: 'focus-self-held', note: "bar A focus 'self' blurScope 'series': an element held by an action IS spared when its own series blurs (states.ts:478-480); a highlight with focus 'self' blurs the series but spares the held bar",
    option: barOpt({ emphasis: { focus: 'self', blurScope: 'series' } }),
    steps: [act({ type: 'highlight', seriesIndex: 0, dataIndex: 2 }), mv(item(0, 0)), mv(empty()), act({ type: 'highlight', seriesIndex: 0, dataIndex: 1 })] },
];

// ============================================================================
// Driving a case
// ============================================================================
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false; // the browser's model (mouse-events.js header)
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
let ecKey = null;
function getECData(el) {
  return (ecKey && el[ecKey]) || null;
}
function discoverECKey() {
  const c = newChart();
  c.setOption({ animation: false, xAxis: { type: 'category', data: ['a'] }, yAxis: {}, series: [{ type: 'bar', data: [1] }] });
  c.renderToSVGString();
  const el = c.getModel().getSeriesByIndex(0).getData().getItemGraphicEl(0);
  for (const k of Object.getOwnPropertyNames(el)) {
    const v = el[k];
    if (v && typeof v === 'object' && hasOwn(v, 'dataIndex') && v.dataIndex === 0 && hasOwn(v, 'seriesIndex')) ecKey = k;
  }
  c.dispose();
  must(ecKey, 'the ECData key was not found');
}
function plain(v, depth) {
  if (typeof v === 'string' && v.includes('\u0000')) return '<auto id>';
  if (v === null || typeof v !== 'object') return typeof v === 'function' ? undefined : v;
  if (depth > 5) return undefined;
  if (!Array.isArray(v) && Object.getPrototypeOf(v) !== Object.prototype && Object.getPrototypeOf(v) !== null) {
    return '[' + ((v.constructor && v.constructor.name) || 'object') + ']';
  }
  if (Array.isArray(v)) return v.map(x => { const s = plain(x, depth + 1); return s === undefined ? null : s; });
  const o = {};
  for (const k of Object.keys(v)) {
    if (k === 'event') continue;
    const s = k === 'from' && typeof v[k] === 'string' ? '<view uid>' : plain(v[k], depth + 1);
    if (s !== undefined) o[k] = s;
  }
  return o;
}
const opac = st => (st.opacity == null ? 1 : st.opacity);
const NOTES = [
  'Flags vs states: hover / highlight / blur only set el.hoverState (0 normal, 1 blur, 2 emphasis) and select only el.selected; the next frame (applyElementStates) turns them into el.useStates([select if selected and a select state exists] + [emphasis if hoverState 2 | blur if hoverState 1, if that state exists]). The order is always select first, then emphasis / blur, so emphasis / blur win where both set a property.',
  'Default state proxy (every element whose emphasis is not disabled): emphasis = declared emphasis style, plus a lift of the fill (each channel * 1.1 | 0, clamped, written rgba(r,g,b,a)) taken from the SELECT fill when select is in the same list and declares one, else the rest fill; the stroke is lifted only when the fill was not; z2 = CURRENT z2 + 10. select = declared select style, z2 = CURRENT z2 + 9. blur = declared blur opacity, else (already blurred ? current opacity : current opacity * 0.1). A state object that does not exist (a label without emphasis / select state) gets no z2 lift; blur always gets its opacity.',
  'z2 creeps: the lift is added to the element\'s CURRENT z2 at every state switch while any state stays applied (a selected slice hovered on and off: 11, 21, 31, 40, 50, ...); it returns to the rest z2 only when the state list empties. Compare the order z2 implies, or replay the creep (the transcription does).',
  'A full update (legend toggle) clears every element\'s states (rest values), re-applies the PREVIOUS state list, then the new one (updateStates: useStates(prevStates) then applyElementStates) -- the creep continues through it. Reused elements keep their hoverState / selected / __highByOuter flags; elements created by the update start from 0.',
  'Select on click: echarts\' own zr click handler (before the user click handler) finds the FIRST element on the host / parent chain with an ECData dataIndex and dispatches unselect if that element is selected, else select -- whatever selectedMode (selectedMode off: nothing changes, but select + selectchanged are still published). Payload {type, dataType?, dataIndexInside: inner index, seriesIndex, isFromClick: true}.',
  'Selection model (model/Series.ts): keyed by data NAME (name || id): items sharing a name select together. single / true: the map is {lastName: true}; multiple: map[name] = true; series: the map becomes the string \'all\'. unselect on series mode or map \'all\' clears the whole map; otherwise map[name] = false. isSelected = map \'all\' or map[name], and not data select.disabled (a disabled item enters the map and getSelectedDataIndices but never shows select). getSelectedDataIndices lists RAW indices in map insertion order (\'all\': the shown raw indices).',
  'Events of select / unselect / toggleSelect: first the non-refined event (type lowercased: select / unselect / toggleselect, payload = a copy of the action payload), then selectchanged {selected: [{dataIndex: raw[], seriesIndex}] over the SHOWN series with a non-empty selection, isFromClick, fromAction (the action type as dispatched), fromActionPayload, escapeConnect: true}. Legacy (only with handlers registered): isFromClick -> mapselectchanged then pieselectchanged; fromAction select -> mapselected, pieselected; unselect -> mapunselected, pieunselected; each fired once per PIE series listed in selected (the map* variants too -- the legacy code filters subType pie for both), payload {type, seriesId, name (of the payload\'s item), selected (the map, or \'all\')}.',
  'highlight / downplay actions: first allLeaveBlur (every blurred series back to normal), then for highlight without notBlur and without emphasis.disabled blurSeries by the focus of the element at the payload\'s (first) data index, then the view: every queried item (all when no dataIndex / name) enters emphasis with bit highlightKey-digit (0 without a key) in __highByOuter; downplay clears the bit and leaves emphasis only when no bit is left. Hover in / out never touches an element with __highByOuter. Line with ONE dataIndex: the polyline is flagged and Symbol.highlight() marks the SYMBOL PATH (not the group, not the key digit) -- the group, which is the hover dispatcher, has no bit, so hovering it and leaving clears the emphasis.',
  'Hover (zrender over / out): out = allLeaveBlur, then the dispatcher (the OUTERMOST highDownDispatcher on the chain: the bar, the pie sector, the Symbol GROUP) leaves emphasis; over = blurSeries(focus, blurScope of the dispatcher), then the dispatcher and its children enter emphasis. blurSeries: focus none / missing -> nothing; blurScope default coordinateSystem; every SHOWN series t is blurred (every element of its view, hoverState 1) unless blurScope series and t != s, or coordinateSystem and t sits on another coordinate system (grid index; a series without one only matches itself), or focus series and t = s; with focus self the elements of s carrying __highByOuter are spared. The hovered element then enters emphasis over its own blur.',
  'Line: every symbol group change of hoverState, and the polyline\'s own, set the polyline\'s flag to the same state (onHoverStateChange -> _changePolyState); the polyline has emphasis (stroke lifted, z2 + 10) and blur (opacity x 0.1) states, never select.',
  'Pie: select state = translation (cos(mid) * selectedOffset, sin(mid) * selectedOffset), mid = (startAngle + endAngle) / 2 of the layout, selectedOffset of the SERIES (default 10); the label\'s select state is its laid-out position + the same offset and the label line is translated too; emphasis state = r + emphasis.scaleSize (default 5, scale default true). Legend on slice names: toggling a name off filters the slice (dataFilter) -- inner indices shift, the pie re-lays out, the selection (by name) survives.',
  'Legend click (not triggerEvent): downplay {seriesName | name}, legendToggleSelect {name} (legendselectchanged {name, selected: every legend data name -> isSelected}), highlight -- after the hover\'s own highlight. selectedMode false makes the hit rect silent too: no hover highlight, no click, nothing. selectedMode single: at load the first selected name (or the first name) is selected and all others set false; unSelect is a no-op, so clicking the one selected item changes nothing but still publishes. After every legend action every name of the selected map is written back through select / unSelect (the option.selected map ends up listing every legend name).',
  'Legend visuals: text fill = textStyle.color (default #54555a) or inactiveColor (default #cfd2d7); icon fill = the series / slice colour or inactiveColor; icon stroke = inherit (the visual stroke) or inactiveBorderColor (default #cfd2d7); icon lineWidth = borderWidth auto (2 when the visual lineWidth > 0, else 0); inactive with inactiveBorderWidth auto: 2 only when the visual lineWidth > 0 AND the icon had a stroke, else 0 -- a NUMERIC inactiveBorderWidth is ignored (the active lineWidth stays).',
  'emphasis.disabled: the element is no highlight dispatcher (hover and highlight do nothing) and has NO default state proxy: its select state is the raw declared style without the z2 lift.',
];
const LEGACY = ['pieselectchanged', 'pieselected', 'pieunselected', 'mapselectchanged', 'mapselected', 'mapunselected'];

function snapshot(chart, elId) {
  const ecModel = chart.getModel();
  const out = { series: [] };
  ecModel.eachRawSeries(sm => {
    const s = sm.seriesIndex;
    const shown = !ecModel.isSeriesFiltered(sm);
    const rec = { s, type: sm.subType, shown, selectedMap: sm.option.selectedMap == null ? null : clone(sm.option.selectedMap), selectedIndices: shown ? sm.getSelectedDataIndices() : null, items: [] };
    if (shown) {
      const data = sm.getData();
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        rec.items.push(el ? itemRec(sm.subType, el, i, data, elId) : { i, d: data.getRawIndex(i), name: data.getName(i), el: null });
      }
      if (sm.subType === 'line') {
        const view = chart._chartsMap[sm.__viewId];
        const p = view._polyline;
        rec.poly = p ? pathRec(p, elId, true) : null;
      }
    }
    out.series.push(rec);
  });
  const lm = ecModel.getComponent('legend', 0);
  if (lm) {
    const view = chart._componentsMap[lm.__viewId];
    const items = [];
    view.getContentGroup().eachChild(g => {
      if (g.__legendDataIndex == null) return;
      const icon = g.childAt(0);
      const text = g.children().find(c => c.type === 'text');
      items.push({ name: text.style.text, icon: icon.isGroup ? 'group' : { fill: icon.style.fill, stroke: icon.style.stroke, lineWidth: icon.style.lineWidth, opacity: opac(icon.style) }, text: { fill: text.style.fill } });
    });
    out.legend = { selected: clone(lm.option.selected), items };
  }
  return out;
}
function restOf(el) {
  const ns = el._normalState || {};
  const st = ns.style || el.style;
  const kv = k => (k in ns ? ns[k] : el[k]);
  return { ns, st, kv };
}
function pathRec(p, elId, poly) {
  const { st, kv } = restOf(p);
  const r = { el: elId(p), st: p.currentStates.slice(), hs: p.hoverState || 0, px: !!p.stateProxy };
  if (!poly) r.sel = !!p.selected;
  Object.assign(r, { z2: p.z2, fill: p.style.fill, stroke: p.style.stroke, lineWidth: p.style.lineWidth, opacity: opac(p.style) });
  r.rest = { z2: kv('z2'), fill: st.fill, stroke: st.stroke, lineWidth: st.lineWidth, opacity: opac(st) };
  if (poly) { delete r.fill; delete r.rest.fill; }
  return r;
}
function itemRec(type, el, i, data, elId) {
  const isSymbol = type === 'line' || type === 'scatter';
  const p = isSymbol ? el.childAt(0) : el;
  const r = Object.assign({ i, d: data.getRawIndex(i), name: data.getName(i) }, pathRec(p, elId));
  r.hbo = el.__highByOuter || 0;
  const { ns, kv } = restOf(p);
  if (type === 'pie') {
    Object.assign(r, { x: p.x, y: p.y, r: p.shape.r, a0: p.shape.startAngle, a1: p.shape.endAngle });
    Object.assign(r.rest, { x: kv('x'), y: kv('y'), r: ns.shape ? ns.shape.r : p.shape.r });
  } else if (type === 'bar') {
    Object.assign(r, { bx: p.shape.x, by: p.shape.y, bw: p.shape.width, bh: p.shape.height });
  } else if (isSymbol) {
    Object.assign(r, { sx: p.scaleX, sy: p.scaleY, gx: el.x, gy: el.y, ghs: el.hoverState || 0, phbo: p.__highByOuter || 0 });
    Object.assign(r.rest, { sx: kv('scaleX'), sy: kv('scaleY') });
  }
  const t = p.getTextContent();
  if (t) {
    const lr = restOf(t);
    r.label = { st: t.currentStates.slice(), px: !!t.stateProxy, has: ['emphasis', 'blur', 'select'].filter(k => t.states[k]).map(k => k[0]).join(''), ignore: !!t.ignore, fill: t.style.fill, opacity: opac(t.style), z2: t.z2, x: t.x, y: t.y,
      rest: { ignore: !!lr.kv('ignore'), fill: lr.st.fill, opacity: opac(lr.st), z2: lr.kv('z2'), x: lr.kv('x'), y: lr.kv('y') } };
  }
  const g = p.getTextGuideLine();
  if (g) r.guide = { st: g.currentStates.slice(), x: g.x, y: g.y, ignore: !!g.ignore };
  return r;
}

function runCase(def) {
  const chart = newChart();
  const option = clone(def.option);
  const events = [];
  const elIds = new Map();
  const elId = el => { if (!elIds.has(el)) elIds.set(el, elIds.size); return elIds.get(el); };
  try {
    chart.setOption(clone(option));
    frame(chart);
    const pubTypes = Object.keys(chart._messageCenter._$handlers).concat(LEGACY);
    // brushselected: the full build's brush component publishes it after every
    // full update (no brush in any case here): left out
    for (const t of pubTypes) if (t !== 'brushselected') chart.on(t, p => events.push({ type: t, payload: plain(p, 0) }));
    chart.on('click', p => events.push({ type: 'click', payload: { componentType: p.componentType, seriesIndex: p.seriesIndex, dataIndex: p.dataIndex, name: p.name } }));

    const hd = () => chart.getZr().handler;
    const displayables = () => chart.getZr().storage.getDisplayList();
    const series = s => chart.getModel().getSeriesByIndex(s);
    const inLegend = e => { for (let x = e; x; x = x.parent) if (x.__legendDataIndex != null) return true; return false; };
    const findText = (s, lg) => {
      const l = displayables().filter(e => e.type === 'tspan' && e.style && e.style.text === s && !e.ignore && (!lg || inLegend(e)));
      must(l.length === 1, def.id + ': text \'' + s + '\' found ' + l.length + ' times');
      return l[0];
    };
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
      const data = series(s).getData();
      const el = data.getItemGraphicEl(data.indexOfRawIndex(d));
      must(el && el.__zr, def.id + ': item ' + s + '/' + d + ' is not drawn');
      return el;
    };
    const itemCentre = el => {
      if (el.type === 'sector') {
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
    const resolve = at => {
      if (at.item) {
        const owner = itemEl(at.item[0], at.item[1]);
        const p = aimNear(itemCentre(owner), owner, 'item');
        return { x: p[0], y: p[1], aim: 'item s' + at.item[0] + ' d' + at.item[1] };
      }
      if (at.legend != null) {
        const t = findText(at.legend, true);
        const owner = t.parent && t.parent.parent;
        must(owner && owner.isGroup && owner.__legendDataIndex != null, def.id + ': no legend item group');
        const r = globalRect(t);
        const p = aimNear([r.x + r.width / 2, r.y + r.height / 2], owner, 'legend');
        return { x: p[0], y: p[1], aim: 'legend \'' + at.legend + '\'' };
      }
      if (at.empty) {
        must(!hd().findHover(at.empty[0], at.empty[1]).target, def.id + ': the empty point hits an element');
        return { x: at.empty[0], y: at.empty[1], aim: 'empty' };
      }
      if (at.xy) {
        // a silent legend item: aim at its text by geometry
        const name = at.xy.split(' ').slice(1).join(' ');
        const t = findText(name, true);
        const r = globalRect(t);
        return { x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2), aim: 'point (' + at.xy + ')' };
      }
      throw new OracleError(def.id + ': an unknown aim ' + JSON.stringify(at));
    };
    const hitAt = (x, y) => hitOf(hd().findHover(x, y).target);
    const hitOf = t => {
      if (!t) return null;
      let hdEl = null;
      let dp = null;
      let lg = null;
      for (let e = t; e; e = e.__hostTarget || e.parent) {
        if (e.__highDownDispatcher) hdEl = e;
        const d = getECData(e);
        if (!dp && d && d.dataIndex != null) dp = { s: d.seriesIndex, i: d.dataIndex, dt: d.dataType };
        if (lg == null && e.__legendDataIndex != null) lg = e;
      }
      let hdRec = null;
      if (hdEl) {
        if (hdEl.__legendDataIndex != null) hdRec = { legend: hdEl.__legendDataIndex };
        else { const d = getECData(hdEl); hdRec = { s: d.seriesIndex, i: d.dataIndex }; }
      }
      if (dp && dp.dt == null) delete dp.dt;
      const lgName = lg ? lg.children().find(c => c.type === 'text').style.text : null;
      return { el: elId(t), kind: t.type, hd: hdRec, dp, legend: lgName };
    };

    const steps = [{ type: 'init', events: events.splice(0), state: snapshot(chart, elId) }];
    for (const s0 of def.steps) {
      const st = { type: s0.type };
      events.length = 0;
      if (s0.type === 'action') {
        st.payload = clone(s0.payload);
        chart.dispatchAction(clone(s0.payload));
      } else {
        const r = resolve(s0.at);
        Object.assign(st, { x: r.x, y: r.y, aim: r.aim, hit: hitAt(r.x, r.y) });
        const h = hd();
        // the previously hovered element was removed by a re-render: zrender
        // re-finds the target at the old point first (#6198)
        const last = h._hovered.target;
        if (last && !last.__zr) st.refound = hitOf(h.findHover(h._hovered.x, h._hovered.y).target);
        h.mousemove(raw(st.x, st.y));
        if (s0.type === 'click') {
          h.mousedown(raw(st.x, st.y));
          h.mouseup(raw(st.x, st.y));
          h.click(raw(st.x, st.y));
        }
      }
      frame(chart);
      st.events = events.splice(0);
      st.state = snapshot(chart, elId);
      steps.push(st);
    }
    return { id: def.id, note: def.note, option, steps };
  } finally {
    chart.dispose();
  }
}

// ============================================================================
// The transcription (states.md): a mirror of upstream's flags and models,
// replayed from each case's option, its steps and the recorded hits; the
// element structure (which element exists, its rest values, its id) is taken
// from the recording, everything else is predicted and compared.
// ============================================================================
const RULES = {
  singleKeepsLast: true, seriesUnselectClears: true, clickToggles: true, selectedRaw: true, selectByName: true,
  offsetCosSin: true, z2FromCurrent: true, selectLift: 9, emphasisLift: 10, blurFactor: 0.1, blurFromCurrent: true,
  scopeCoordSys: true, focusSeriesSparesOwn: true, selfBlursOwn: true, hoverRespectsHbo: true, highlightLeavesBlur: true,
  legendSingleNoUnselect: true, legendInactiveWidthAutoOnly: true, legendClickDownplayFirst: true, liftFromSelectFill: true,
  selectDisabledHonoured: true, legacyNeedsSelected: true, symbolHighlightOnPath: true, pieLabelFollowsOffset: true,
  disabledHasNoProxy: true, labelLiftNeedsState: true, rerenderRestoresPrevStates: true, refindRemovedHover: true,
  selfSparesHeld: true, truthyFocusBlurs: true, unknownScopeGlobal: true, candleEmphasisWidth: true, funnelEmphasisLabel: true,
  sunburstDescendant: true, focusIndicesLeaveBlur: true, sunburstBlurDefaults: true,
};

// ---- small helpers --------------------------------------------------------
const has = v => v != null && v !== 'none';
function parseColor(c) {
  if (typeof c !== 'string') return null;
  let m = /^#([0-9a-f]{6})$/i.exec(c);
  if (m) { const n = parseInt(m[1], 16); return [n >> 16 & 255, n >> 8 & 255, n & 255, 1]; }
  m = /^#([0-9a-f]{3})$/i.exec(c);
  if (m) return [0, 1, 2].map(k => parseInt(m[1][k] + m[1][k], 16)).concat([1]);
  m = /^rgba?\(([^)]*)\)$/.exec(c);
  if (m) { const p = m[1].split(',').map(Number); return [p[0], p[1], p[2], p.length > 3 ? p[3] : 1]; }
  return null;
}
function liftColor(c) {
  const a = parseColor(c);
  if (!a) return c;
  for (let i = 0; i < 3; i++) { a[i] = a[i] * (1 - (-0.1)) | 0; if (a[i] > 255) a[i] = 255; else if (a[i] < 0) a[i] = 0; }
  return 'rgba(' + a.join(',') + ')';
}
const get = (o, p) => { let v = o; for (const k of p) { if (v == null) return undefined; v = v[k]; } return v; };
const styleOf = is => {
  const r = {};
  if (!is) return r;
  if (is.color != null) r.fill = is.color;
  if (is.borderColor != null) r.stroke = is.borderColor;
  if (is.borderWidth != null) r.lineWidth = is.borderWidth;
  if (is.opacity != null) r.opacity = is.opacity;
  return r;
};
const lineStyleOf = ls => {
  const r = {};
  if (!ls) return r;
  if (ls.color != null) r.stroke = ls.color;
  if (ls.width != null && ls.width !== 'bolder') r.lineWidth = ls.width;
  if (ls.opacity != null) r.opacity = ls.opacity;
  return r;
};
const sameList = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
let highlightDigits = {};
let nextDigit = 1;
function digitOf(key) {
  if (key == null) return 0;
  if (highlightDigits[key] == null) highlightDigits[key] = nextDigit++;
  return highlightDigits[key];
}

// ---- the element simulator (zrender useStates + echarts' state proxies) ----
// el = {rest: {...}, cur: {...}, list: [], proxy, has: {emphasis, blur, select}}
// build(stateName, el, targetList) -> state object (or null)
function useStates(el, list, build, R) {
  if (sameList(list, el.list)) return;
  if (!list.length) { el.cur = Object.assign({}, el.rest); el.list = []; return; }
  const objs = [];
  for (const n of list) { const o = build(n, el, list); if (o) objs.push(o); }
  const merged = {};
  const style = {};
  for (const o of objs) { Object.assign(merged, o); if (o.style) Object.assign(style, o.style); }
  const next = Object.assign({}, el.rest, style);
  for (const k of ['z2', 'x', 'y', 'r', 'sx', 'sy', 'ignore']) if (merged[k] != null) next[k] = merged[k];
  el.cur = next;
  el.list = list.slice();
}
function clearStates(el) {
  el.cur = Object.assign({}, el.rest);
  el.list = [];
}
// the default-state proxy (util/states.ts createEmphasisDefaultState /
// createSelectDefaultState / createBlurDefaultState) around a raw state
function proxied(raw, name, el, list, R, lifts) {
  if (!el.proxy) return raw;
  if (name === 'emphasis') {
    let st = raw ? Object.assign({}, raw) : null;
    if (lifts && lifts.path) {
      const hasSel = list.includes('select');
      const fromFill = hasSel && R.liftFromSelectFill ? (lifts.selectFill || lifts.normalFill) : lifts.normalFill;
      const fromStroke = hasSel && R.liftFromSelectFill ? (lifts.selectStroke || lifts.normalStroke) : lifts.normalStroke;
      if (has(fromFill) || has(fromStroke)) {
        st = st || {};
        const es = Object.assign({}, st.style || {});
        if (es.fill === 'inherit') es.fill = fromFill;
        else if (!has(es.fill) && has(fromFill)) es.fill = liftColor(fromFill);
        else if (!has(es.stroke) && has(fromStroke)) es.stroke = liftColor(fromStroke);
        st.style = es;
      }
    }
    if (st && st.z2 == null) st.z2 = (R.z2FromCurrent ? el.cur.z2 : el.rest.z2) + R.emphasisLift;
    return st;
  }
  if (name === 'select') {
    if (!raw) return raw;
    const st = Object.assign({}, raw);
    if (st.z2 == null) st.z2 = (R.z2FromCurrent ? el.cur.z2 : el.rest.z2) + R.selectLift;
    return st;
  }
  if (name === 'blur') {
    const st = Object.assign({}, raw || {});
    const bs = Object.assign({}, st.style || {});
    if (bs.opacity == null) {
      const hasBlur = el.list.includes('blur');
      const from = R.blurFromCurrent ? el.cur.opacity : el.rest.opacity;
      bs.opacity = hasBlur ? el.cur.opacity : (from == null ? 1 : from) * R.blurFactor;
    }
    st.style = bs;
    return st;
  }
  return raw;
}

function predictCase(c, R) {
  highlightDigits = {};
  nextDigit = 1;
  const opt = c.option;
  const SO = opt.series;
  const legendOpt = opt.legend;
  const cats = get(opt, ['xAxis', 'data']) || get(opt, ['xAxis', 0, 'data']);
  // a sunburst's data is its tree, pre-order, the virtual root at 0 (data/Tree.ts)
  const flatTree = so => {
    const out = [{ name: so.name, parent: -1, item: null }];
    const walk = (list, parent) => { for (const d of list || []) { const k = out.length; out.push({ name: d.name, parent, item: d }); walk(d.children, k); } };
    walk(so.data, 0);
    return out;
  };
  const S = SO.map((so, s) => {
    const type = so.type;
    const tree = type === 'sunburst' ? flatTree(so) : null;
    const rawData = tree ? tree.map(t => ({ name: t.name, selected: false, selectDisabled: false, parent: t.parent, item: t.item }))
      : so.data.map((d, k) => {
        const o = d != null && typeof d === 'object' && !Array.isArray(d) ? d : null;
        const name = type === 'pie' || type === 'funnel' ? o.name : cats ? cats[k] : undefined;
        return { name, selected: !!(o && o.selected), selectDisabled: !!get(o, ['select', 'disabled']) };
      });
    const xAxes = [].concat(opt.xAxis || []);
    const coord = ['pie', 'funnel', 'sunburst'].includes(type) ? null : 'grid' + ((xAxes[so.xAxisIndex || 0] || {}).gridIndex || 0);
    return {
      s, type, so, name: so.name, id: so.id, mode: so.selectedMode, coord, rawData,
      focus: get(so, ['emphasis', 'focus']) != null ? get(so, ['emphasis', 'focus']) : type === 'sunburst' && R.sunburstDescendant ? 'descendant' : undefined,
      scope: get(so, ['emphasis', 'blurScope']), disabled: !!get(so, ['emphasis', 'disabled']),
      hoverLink: so.legendHoverLink !== false, map: null, idxMap: {}, isBlured: false,
    };
  });
  // ---- legend model (LegendModel.ts) ----
  const L = legendOpt ? { mode: legendOpt.selectedMode === undefined ? true : legendOpt.selectedMode, selected: clone(legendOpt.selected || {}) } : null;
  if (L) {
    const potential = [];
    const available = [];
    for (const x of S) {
      available.push(x.name);
      if (x.type === 'pie') { for (const d of x.rawData) { available.push(d.name); potential.push(d.name); } } else if (x.name != null) potential.push(x.name);
    }
    L.data = [];
    for (const n of legendOpt.data || potential) if (!L.data.includes(n)) L.data.push(n);
    L.available = available;
    if (L.data.length && L.mode === 'single') {
      const first = L.data.find(n => legendIsSelected(n));
      legendSelect(first != null ? first : L.data[0]);
    }
  }
  function legendIsSelected(n) {
    return !(hasOwn(L.selected, n) && !L.selected[n]) && L.available.includes(n);
  }
  function legendSelect(n) {
    if (L.mode === 'single') for (const d of L.data) L.selected[d] = false;
    L.selected[n] = true;
  }
  function legendUnSelect(n) {
    if (L.mode !== 'single' || !R.legendSingleNoUnselect) L.selected[n] = false;
  }
  const shown = x => !L || legendIsSelected(x.name);
  const inner = x => x.rawData.map((d, k) => k).filter(k => !(L && x.type === 'pie') || legendIsSelected(x.rawData[k].name));
  // ---- series selection (model/Series.ts) ----
  const keyOf = (x, raw) => (R.selectByName ? x.rawData[raw].name : String(raw));
  function innerSelect(x, raws) {
    if (!x.mode || !raws.length) return;
    if (x.mode === 'series') x.map = 'all';
    else if (x.mode === 'multiple') {
      if (!x.map || typeof x.map !== 'object') x.map = {};
      for (const r of raws) { x.map[keyOf(x, r)] = true; x.idxMap[keyOf(x, r)] = r; }
    } else if (x.mode === 'single' || x.mode === true) {
      const r = R.singleKeepsLast ? raws[raws.length - 1] : raws[0];
      x.map = { [keyOf(x, r)]: true };
      x.idxMap = { [keyOf(x, r)]: r };
    }
  }
  function unselect(x, raws) {
    if (!x.map) return;
    if (R.seriesUnselectClears && (x.mode === 'series' || x.map === 'all')) { x.map = {}; x.idxMap = {}; return; }
    if (x.map === 'all') x.map = {};
    for (const r of raws) { x.map[keyOf(x, r)] = false; x.idxMap[keyOf(x, r)] = -1; }
  }
  function isSelected(x, raw) {
    if (!x.map) return false;
    return !!(x.map === 'all' || x.map[keyOf(x, raw)]) && !(R.selectDisabledHonoured && x.rawData[raw].selectDisabled);
  }
  function toggle(x, raws) {
    for (const r of raws) (isSelected(x, r) ? unselect : innerSelect)(x, [r]);
  }
  function selectedIndices(x) {
    if (x.map === 'all') return inner(x).slice();
    const out = [];
    for (const k of Object.keys(x.idxMap)) if (x.idxMap[k] >= 0) out.push(x.idxMap[k]);
    if (!R.selectedRaw) { const inn = inner(x); return out.map(r => inn.indexOf(r)); }
    return out;
  }
  for (const x of S) { const raws = x.rawData.map((d, k) => k).filter(k => x.rawData[k].selected); if (raws.length) innerSelect(x, raws); }

  // ---- element flags ----
  // node per item: g (dispatcher / Symbol group) and p (the path; === g unless line)
  const nodes = new Map();
  const polyFlag = new Map();
  const keyNode = (s, raw) => s + ':' + raw;
  function freshNode(x, raw) {
    const p = { hs: 0, hbo: 0, sel: false };
    const g = x.type === 'line' || x.type === 'scatter' ? { hs: 0, hbo: 0, sym: true, s: x.s } : p;
    return { g, p, x, raw };
  }
  // structure from a recorded snapshot: which elements exist (by element id)
  let elOfKey = new Map();
  function syncStructure(state) {
    const next = new Map();
    for (const rec of state.series) {
      const x = S[rec.s];
      for (const it of rec.items) {
        if (it.el == null) continue;
        const k = keyNode(rec.s, it.d);
        const same = elOfKey.get(k) === it.el && nodes.has(k);
        next.set(k, same ? nodes.get(k) : freshNode(x, it.d));
      }
      if (!rec.shown || !rec.poly) polyFlag.delete(rec.s);
      else if (!polyFlag.has(rec.s)) polyFlag.set(rec.s, 0);
    }
    nodes.clear();
    for (const [k, v] of next) nodes.set(k, v);
    elOfKey = new Map();
    for (const rec of state.series) for (const it of rec.items) if (it.el != null) elOfKey.set(keyNode(rec.s, it.d), it.el);
  }
  const FLAG = { emphasis: 2, normal: 0, blur: 1 };
  function doChange(o, name) {
    const v = FLAG[name];
    if (o.sym && (o.hs || 0) !== v && polyFlag.has(o.s)) polyFlag.set(o.s, v); // LineView _changePolyState
    o.hs = v;
  }
  const traverse = n => (n.g === n.p ? [n.p] : [n.g, n.p]);
  const isDispatcher = n => !n.x.disabled;
  function enterEmphasis(n, digit, onPath) {
    const t = onPath ? n.p : n.g;
    t.hbo |= 1 << digit;
    for (const o of onPath ? [n.p] : traverse(n)) doChange(o, 'emphasis');
  }
  function leaveEmphasis(n, digit, onPath) {
    const t = onPath ? n.p : n.g;
    t.hbo &= ~(1 << digit);
    if (!t.hbo) for (const o of onPath ? [n.p] : traverse(n)) if (o.hs === 2) doChange(o, 'normal');
  }
  function hoverEnter(n) {
    if (R.hoverRespectsHbo && n.g.hbo) return;
    for (const o of traverse(n)) doChange(o, 'emphasis');
  }
  function hoverLeave(n) {
    if (R.hoverRespectsHbo && n.g.hbo) return;
    for (const o of traverse(n)) if (o.hs === 2) doChange(o, 'normal');
  }
  const seriesNodes = s => Array.from(nodes.values()).filter(n => n.x.s === s);
  // ecData.focus of an item's element: the tree family's words become the
  // data indices that leave the blur again (SunburstPiece.ts:152-160)
  function focusOf(x, raw) {
    if (x.type !== 'sunburst') return x.focus;
    const it = x.rawData[raw].item;
    const f = get(it, ['emphasis', 'focus']) != null ? get(it, ['emphasis', 'focus']) : x.focus;
    const anc = () => { const r = []; for (let k = raw; k >= 0; k = x.rawData[k].parent) r.push(k); return r.reverse(); };
    const desc = () => { const r = []; x.rawData.forEach((d, k) => { for (let p = k; p >= 0; p = x.rawData[p].parent) if (p === raw) { r.push(k); break; } }); return r; };
    if (f === 'relative') return anc().concat(desc());
    if (f === 'ancestor') return anc();
    if (f === 'descendant') return desc();
    return f;
  }
  function blurSeries(ts, focus, scope) {
    if (ts == null || !focus || focus === 'none') return;
    if (!R.truthyFocusBlurs && !['self', 'series'].includes(focus)) return;
    scope = scope || 'coordinateSystem';
    if (!R.unknownScopeGlobal && scope !== 'series') scope = 'coordinateSystem';
    const tx = S[ts];
    for (const x of S) {
      if (!shown(x)) continue;
      const same = x === tx;
      const sameCoord = x.coord && tx.coord ? x.coord === tx.coord : same;
      if ((scope === 'series' && !same) || (R.scopeCoordSys && scope === 'coordinateSystem' && !sameCoord)
        || (R.focusSeriesSparesOwn && focus === 'series' && same) || (!R.selfBlursOwn && focus === 'self' && same)) continue;
      if (polyFlag.has(x.s)) polyFlag.set(x.s, 1);
      for (const n of seriesNodes(x.s)) {
        for (const o of traverse(n)) {
          if (R.selfSparesHeld && o.hbo && same && focus === 'self') continue;
          doChange(o, 'blur');
        }
      }
      // leaveBlurOfIndices -- on EVERY series blurred, by the target's indices
      if (Array.isArray(focus) && R.focusIndicesLeaveBlur) {
        for (const k of focus) {
          const n = nodes.get(keyNode(x.s, k));
          if (n) for (const o of traverse(n)) if (o.hs === 1) doChange(o, 'normal');
        }
      }
      x.isBlured = true;
    }
  }
  function allLeaveBlur() {
    for (const x of S) {
      if (x.isBlured) {
        if (polyFlag.has(x.s) && polyFlag.get(x.s) === 1) polyFlag.set(x.s, 0);
        for (const n of seriesNodes(x.s)) for (const o of traverse(n)) if (o.hs === 1) doChange(o, 'normal');
      }
      x.isBlured = false;
    }
  }
  const nodeAtInner = (x, i) => { const r = inner(x)[i]; return r == null ? null : nodes.get(keyNode(x.s, r)) || null; };
  function queryInner(x, p) {
    const inn = inner(x);
    const one = (kind, v) => (kind === 'raw' ? inn.indexOf(v) : inn.findIndex(r => x.rawData[r].name === v));
    if (p.dataIndexInside != null) return p.dataIndexInside;
    if (p.dataIndex != null) return Array.isArray(p.dataIndex) ? p.dataIndex.map(v => one('raw', v)) : one('raw', p.dataIndex);
    if (p.name != null) return Array.isArray(p.name) ? p.name.map(v => one('name', v)) : one('name', p.name);
    return undefined;
  }
  const matches = (x, p) => (p.seriesIndex == null || [].concat(p.seriesIndex).includes(x.s))
    && (p.seriesName == null || [].concat(p.seriesName).includes(x.name)) && (p.seriesId == null || [].concat(p.seriesId).includes(x.id))
    && !(p.excludeSeriesId && x.id != null && p.excludeSeriesId.includes(x.id));

  // ---- actions (core/echarts.ts doDispatchAction / updateDirectly) ----
  let events;
  let structureAfterUpdate;
  let rerendered = false;
  function dispatch(p) {
    const t = p.type;
    if (t === 'highlight' || t === 'downplay') {
      if (R.highlightLeavesBlur) allLeaveBlur();
      const list = S.filter(x => matches(x, p));
      if (t === 'highlight' && !p.notBlur) {
        for (const x of list) {
          if (x.disabled) continue;
          let q = queryInner(x, p);
          q = (Array.isArray(q) ? q[0] : q) || 0;
          const n = nodeAtInner(x, q) || seriesNodes(x.s)[0];
          if (n) blurSeries(x.s, focusOf(x, n.raw), x.scope); else if (x.focus != null) blurSeries(x.s, x.focus, x.scope);
        }
      }
      const digit = digitOf(p.highlightKey);
      for (const x of list) {
        const q = queryInner(x, p);
        if (x.type === 'line' && !Array.isArray(q) && q != null && q >= 0) {
          polyFlag.set(x.s, t === 'highlight' ? 2 : 0);
          const n = nodeAtInner(x, q);
          if (n) (t === 'highlight' ? enterEmphasis : leaveEmphasis)(n, 0, R.symbolHighlightOnPath);
          continue;
        }
        if (x.type === 'line' && q == null) polyFlag.set(x.s, t === 'highlight' ? 2 : 0);
        const targets = q == null ? seriesNodes(x.s) : [].concat(q).map(i => nodeAtInner(x, i)).filter(Boolean);
        for (const n of targets) if (isDispatcher(n)) (t === 'highlight' ? enterEmphasis : leaveEmphasis)(n, digit);
      }
      events.push({ type: t, payload: Object.assign({}, p, { type: t }) });
      return;
    }
    if (t === 'select' || t === 'unselect' || t === 'toggleSelect') {
      for (const x of S.filter(y => matches(y, p))) {
        let q = queryInner(x, p);
        if (!Array.isArray(q)) q = [q];
        const raws = q.map(i => inner(x)[i]);
        if (t === 'toggleSelect') toggle(x, raws); else if (t === 'select') innerSelect(x, raws); else unselect(x, raws);
        for (const n of seriesNodes(x.s)) n.p.sel = isSelected(x, n.raw);
      }
      const selected = [];
      for (const x of S) { if (!shown(x)) continue; const idx = selectedIndices(x); if (idx.length) selected.push({ dataIndex: idx, seriesIndex: x.s }); }
      events.push({ type: t.toLowerCase(), payload: Object.assign({}, p, { type: t.toLowerCase() }) });
      events.push({ type: 'selectchanged', payload: { type: 'selectchanged', selected, isFromClick: !!p.isFromClick, fromAction: t, fromActionPayload: p, escapeConnect: true } });
      const legacy = p.isFromClick ? 'selectchanged' : t === 'select' ? 'selected' : t === 'unselect' ? 'unselected' : null;
      if (legacy) {
        for (const pre of ['map', 'pie']) {
          for (const x of S) {
            if (x.type !== 'pie') continue;
            const hits = R.legacyNeedsSelected ? selected.filter(e => e.seriesIndex === x.s).length : 1;
            for (let k = 0; k < hits; k++) {
              let q = queryInner(x, p);
              if (Array.isArray(q)) q = q[0];
              const raw = inner(x)[q];
              events.push({ type: pre + legacy, payload: { type: pre + legacy, seriesId: x.id != null ? x.id : '<auto id>', name: raw == null ? '' : x.rawData[raw].name, selected: typeof x.map === 'string' ? x.map : Object.assign({}, x.map) } });
            }
          }
        }
      }
      return;
    }
    const LEG = { legendToggleSelect: 'legendselectchanged', legendSelect: 'legendselected', legendUnSelect: 'legendunselected', legendAllSelect: 'legendselectall', legendInverseSelect: 'legendinverseselect' };
    if (LEG[t]) {
      const all = t === 'legendAllSelect' || t === 'legendInverseSelect';
      if (t === 'legendToggleSelect') {
        if (!hasOwn(L.selected, p.name)) L.selected[p.name] = true;
        (L.selected[p.name] ? legendUnSelect : legendSelect)(p.name);
      } else if (t === 'legendSelect') legendSelect(p.name);
      else if (t === 'legendUnSelect') legendUnSelect(p.name);
      else if (t === 'legendAllSelect') for (const d of L.data) L.selected[d] = true;
      else for (const d of L.data) { if (!hasOwn(L.selected, d)) L.selected[d] = true; L.selected[d] = !L.selected[d]; }
      const map = {};
      for (const d of L.data) map[d] = legendIsSelected(d);
      // legendAction.ts: every legend is then forced to the same statuses
      for (const d of Object.keys(map)) (map[d] ? legendSelect : legendUnSelect)(d);
      events.push({ type: LEG[t], payload: all ? { selected: map, legendIndex: [0], type: LEG[t] } : { name: p.name, selected: map, type: LEG[t] } });
      // the full update re-renders: elements are re-synced from the recording
      syncStructure(structureAfterUpdate);
      for (const n of nodes.values()) n.p.sel = isSelected(n.x, n.raw);
      rerendered = true;
      return;
    }
    throw new OracleError(c.id + ': the transcription has no action ' + t);
  }
  // ---- pointer (zrender Handler + echarts bindMouseEvent + LegendView) ----
  let hovered = null;
  const legendSeries = name => S.find(x => x.name === name);
  const legendPayload = (type, name) => {
    const sx = legendSeries(name);
    return { type, seriesName: sx ? sx.name : null, name: sx ? null : name, excludeSeriesId: S.filter(x => !x.hoverLink).map(x => x.id) };
  };
  function nodeOfHit(h) {
    if (!h || !h.hd || h.hd.legend != null) return null;
    return nodeAtInner(S[h.hd.s], h.hd.i);
  }
  function mouseout(h) {
    if (h.legend != null) dispatch(legendPayload('downplay', h.legend));
    if (h.hd) {
      allLeaveBlur();
      const n = nodeOfHit(h);
      if (n) hoverLeave(n);
    }
  }
  function mouseover(h) {
    if (h.legend != null) dispatch(legendPayload('highlight', h.legend));
    const n = nodeOfHit(h);
    if (n) {
      blurSeries(n.x.s, focusOf(n.x, n.raw), n.x.scope);
      hoverEnter(n);
    }
  }
  function click(h) {
    if (!h) return;
    if (h.legend != null) {
      if (R.legendClickDownplayFirst) {
        dispatch(legendPayload('downplay', h.legend));
        dispatch({ type: 'legendToggleSelect', name: h.legend });
      } else dispatch({ type: 'legendToggleSelect', name: h.legend });
      dispatch(legendPayload('highlight', h.legend));
    }
    if (h.dp) {
      const x = S[h.dp.s];
      const n = nodeAtInner(x, h.dp.i);
      const type = R.clickToggles && n && n.p.sel ? 'unselect' : 'select';
      const p = { type, dataType: h.dp.dt, dataIndexInside: h.dp.i, seriesIndex: h.dp.s, isFromClick: true };
      if (p.dataType === undefined) delete p.dataType;
      dispatch(p);
      const raw = inner(x)[h.dp.i];
      events.push({ type: 'click', payload: { componentType: 'series', seriesIndex: h.dp.s, dataIndex: raw, name: x.rawData[raw].name } });
    }
  }

  // ---- replay ----
  const out = [];
  let prevState = null;
  c.steps.forEach((st, k) => {
    events = [];
    rerendered = false;
    structureAfterUpdate = st.state;
    if (st.type === 'init') syncStructure(st.state);
    else if (st.type === 'action') dispatch(clone(st.payload));
    else {
      let last = hovered;
      if (st.refound !== undefined && R.refindRemovedHover) last = st.refound;
      const hit = st.hit;
      const sameEl = (a, b) => (a ? a.el : null) === (b ? b.el : null);
      if (last && !sameEl(last, hit)) mouseout(last);
      if (hit && !sameEl(last, hit)) mouseover(hit);
      hovered = hit;
      if (st.type === 'click') click(hit);
    }
    if (st.type === 'init') for (const n of nodes.values()) n.p.sel = isSelected(n.x, n.raw);
    out.push({ events, state: predictState(st, prevState, k === 0 || rerendered) });
    prevState = st.state;
  });
  return out;

  // ---- the predicted state after the frame ----
  function predictState(st, prev, rerender) {
    const res = { series: [] };
    const prevItem = new Map();
    if (prev) for (const rec of prev.series) for (const it of rec.items) if (it.el != null) prevItem.set(it.el, it);
    for (const rec of st.state.series) {
      const x = S[rec.s];
      const r = { s: rec.s, shown: shown(x), selectedMap: x.map == null ? null : clone(x.map), selectedIndices: shown(x) ? selectedIndices(x) : null, raws: shown(x) ? inner(x) : [], items: [] };
      for (const it of rec.items) {
        if (it.el == null) { r.items.push(null); continue; }
        const n = nodes.get(keyNode(rec.s, it.d));
        const list = [];
        if (n.p.sel) list.push('select');
        if (n.p.hs === 2) list.push('emphasis'); else if (n.p.hs === 1) list.push('blur');
        const pi = prevItem.get(it.el);
        r.items.push(predictItem(x, it, n, list, pi, rerender));
      }
      if (rec.poly) {
        const pp = prev && prev.series[rec.s].poly && prev.series[rec.s].poly.el === rec.poly.el ? prev.series[rec.s].poly : null;
        const hs = polyFlag.get(rec.s) || 0;
        const list = hs === 2 ? ['emphasis'] : hs === 1 ? ['blur'] : [];
        const el = simEl(rec.poly.rest, pp, rerender);
        const lifts = { path: true, normalFill: 'none', normalStroke: rec.poly.rest.stroke };
        const b = (name, e, l) => {
          if (name === 'emphasis') return proxied({ style: lineStyleOf(get(x.so, ['emphasis', 'lineStyle'])) }, name, e, l, R, lifts);
          if (name === 'blur') return proxied({ style: lineStyleOf(get(x.so, ['blur', 'lineStyle'])) }, name, e, l, R);
          return proxied({ style: {} }, name, e, l, R);
        };
        useStates(el, list, b, R);
        r.poly = { st: el.list, hs, stroke: el.cur.stroke, lineWidth: el.cur.lineWidth, opacity: el.cur.opacity, z2: el.cur.z2 };
      }
      res.series.push(r);
    }
    if (L) {
      const items = [];
      for (const name of L.data) {
        const sx = legendSeries(name);
        const px = sx ? null : S.find(y => y.type === 'pie' && y.rawData.some(d => d.name === name));
        if (!sx && !px) continue;
        const host = sx || px;
        const sel = legendIsSelected(name);
        // the series visual (rest of an item of the series / of the named slice)
        const rec = st.state.series[host.s];
        const vi = rec.items.find(it => it.el != null && (sx || it.name === name));
        const visual = { fill: vi ? vi.rest.fill : undefined, stroke: get(host.so, ['itemStyle', 'borderColor']),
          lineWidth: get(host.so, ['itemStyle', 'borderWidth']) != null ? get(host.so, ['itemStyle', 'borderWidth']) : host.type === 'pie' ? 1 : 0 };
        const icon = { fill: visual.fill, stroke: visual.stroke, lineWidth: visual.lineWidth > 0 ? 2 : 0 };
        const inactiveColor = legendOpt.inactiveColor || '#cfd2d7';
        if (!sel) {
          const bw = legendOpt.inactiveBorderWidth === undefined ? 'auto' : legendOpt.inactiveBorderWidth;
          if (bw === 'auto' || !R.legendInactiveWidthAutoOnly) icon.lineWidth = bw === 'auto' ? (visual.lineWidth > 0 && icon.stroke ? 2 : 0) : bw;
          icon.fill = inactiveColor;
          icon.stroke = legendOpt.inactiveBorderColor || '#cfd2d7';
        }
        items.push({ name, icon, text: { fill: sel ? (get(legendOpt, ['textStyle', 'color']) || '#54555a') : inactiveColor } });
      }
      res.legend = { selected: clone(L.selected), items };
    }
    return res;
  }
  function simEl(rest, prevRec, rerender) {
    const el = { rest: Object.assign({}, rest), proxy: true };
    if (prevRec && !rerender) {
      // no re-render: the element is exactly as the previous frame left it
      el.cur = Object.assign({}, rest);
      for (const f of ['z2', 'fill', 'stroke', 'lineWidth', 'opacity', 'x', 'y', 'r', 'sx', 'sy']) if (f in prevRec) el.cur[f] = prevRec[f];
      el.list = prevRec.st.slice();
    } else {
      el.cur = Object.assign({}, rest);
      el.list = [];
    }
    return el;
  }
  function predictItem(x, it, n, list, prevRec, rerender) {
    const so = x.so;
    const proxy = !(R.disabledHasNoProxy && x.disabled);
    const el = simEl(it.rest, prevRec, rerender);
    el.proxy = proxy;
    const lab = it.label ? { rest: Object.assign({}, it.label.rest), proxy } : null;
    if (lab) {
      if (prevRec && prevRec.label && !rerender) {
        lab.cur = Object.assign({}, lab.rest);
        for (const f of ['ignore', 'fill', 'opacity', 'z2', 'x', 'y']) lab.cur[f] = prevRec.label[f];
        lab.list = prevRec.label.st.slice();
      } else { lab.cur = Object.assign({}, lab.rest); lab.list = []; }
    }
    const reused = prevRec && rerender && R.rerenderRestoresPrevStates;
    // echarts updateStates after a re-render: useStates(prevStates) then the new list
    if (reused && prevRec.st.length) {
      const pre = prevRec.st.slice();
      useStates(el, pre, (nm, e, l) => itemState(nm, e, l), R);
      if (lab) useStates(lab, pre, (nm, e, l) => labelState(nm, e, l), R);
    }
    useStates(el, list, (nm, e, l) => itemState(nm, e, l), R);
    if (lab) useStates(lab, list, (nm, e, l) => labelState(nm, e, l), R);

    const out = { d: it.d, st: el.list, sel: n.p.sel, hs: n.p.hs, hbo: n.g.hbo, z2: el.cur.z2, fill: el.cur.fill, stroke: el.cur.stroke, lineWidth: el.cur.lineWidth, opacity: el.cur.opacity };
    if (x.type === 'pie') Object.assign(out, { x: el.cur.x, y: el.cur.y, r: el.cur.r });
    if (x.type === 'line' || x.type === 'scatter') Object.assign(out, { sx: el.cur.sx, sy: el.cur.sy, ghs: n.g.hs, phbo: n.p.hbo });
    if (lab) out.label = { st: lab.list, ignore: !!lab.cur.ignore, fill: lab.cur.fill, opacity: lab.cur.opacity, z2: lab.cur.z2, x: lab.cur.x, y: lab.cur.y };
    if (it.guide) { const off = pieOffset(); out.guide = { st: el.list, x: el.list.includes('select') ? off[0] : 0, y: el.list.includes('select') ? off[1] : 0 }; }
    return out;

    function pieOffset() {
      const mid = (it.a0 + it.a1) / 2;
      const off = so.selectedOffset != null ? so.selectedOffset : 10;
      return R.offsetCosSin ? [Math.cos(mid) * off, Math.sin(mid) * off] : [Math.sin(mid) * off, Math.cos(mid) * off];
    }
    function itemState(name, e, l) {
      const lifts = { path: true, normalFill: it.rest.fill, normalStroke: it.rest.stroke };
      const selBase = x.type === 'bar' ? { stroke: '#3c3c41', lineWidth: 2 }
        : ['scatter', 'funnel', 'heatmap', 'pictorialBar'].includes(x.type) ? { stroke: '#3c3c41' } : {};
      const selStyle = Object.assign(selBase, styleOf(get(so, ['select', 'itemStyle'])));
      lifts.selectFill = selStyle.fill || null;
      lifts.selectStroke = selStyle.stroke || null;
      if (name === 'select') {
        const raw = { style: selStyle };
        if (x.type === 'pie') { const off = pieOffset(); raw.x = off[0]; raw.y = off[1]; }
        return proxied(raw, name, e, l, R);
      }
      if (name === 'emphasis') {
        // a candlestick's emphasis border is 2 wide (CandlestickSeries.ts:130-134)
        const raw = { style: Object.assign(x.type === 'candlestick' && R.candleEmphasisWidth ? { lineWidth: 2 } : {}, styleOf(get(so, ['emphasis', 'itemStyle']))) };
        if (x.type === 'pie') {
          const scale = get(so, ['emphasis', 'scale']);
          const size = get(so, ['emphasis', 'scaleSize']);
          raw.r = it.rest.r + (scale === undefined || scale ? (size != null ? size : 5) : 0);
        }
        if (x.type === 'line' || x.type === 'scatter') {
          const hsc = get(so, ['emphasis', 'scale']);
          const ratio = hsc == null || hsc === true ? Math.max(1.1, 3 / it.rest.sy) : isFinite(hsc) && hsc > 0 ? +hsc : 1;
          raw.sx = it.rest.sx * ratio;
          raw.sy = it.rest.sy * ratio;
        }
        return proxied(raw, name, e, l, R, lifts);
      }
      // a sunburst's blur.itemStyle.opacity defaults to 0.2 (SunburstSeries.ts:274-279)
      return proxied({ style: Object.assign(x.type === 'sunburst' && R.sunburstBlurDefaults ? { opacity: 0.2 } : {}, styleOf(get(so, ['blur', 'itemStyle']))) }, name, e, l, R);
    }
    function labelState(name, e, l) {
      const normalShow = get(so, ['label', 'show']) != null ? !!get(so, ['label', 'show']) : ['pie', 'funnel', 'sunburst'].includes(x.type);
      // a funnel's emphasis label shows by default (FunnelSeries.ts:195-199)
      const stateShow = s => (get(so, [s, 'label', 'show']) != null ? get(so, [s, 'label', 'show']) : R.funnelEmphasisLabel && x.type === 'funnel' && s === 'emphasis' ? true : undefined);
      const shows = ['emphasis', 'blur', 'select'].map(stateShow);
      const created = normalShow || shows.some(v => v);
      let raw = null;
      if (created) {
        const stShow = stateShow(name) != null ? !!stateShow(name) : normalShow;
        raw = { style: {} };
        const col = get(so, [name, 'label', 'color']);
        if (col != null) raw.style.fill = col;
        const op = get(so, [name, 'label', 'opacity']) != null ? get(so, [name, 'label', 'opacity'])
          : x.type === 'sunburst' && name === 'blur' && R.sunburstBlurDefaults ? 0.1 : undefined;
        if (op != null) raw.style.opacity = op;
        if (stShow !== normalShow) raw.ignore = !stShow;
      }
      if (name === 'select' && x.type === 'pie') {
        raw = raw || {};
        const off = pieOffset();
        if (R.pieLabelFollowsOffset) { raw.x = it.label.rest.x + off[0]; raw.y = it.label.rest.y + off[1]; } else { raw.x = off[0]; raw.y = off[1]; }
      }
      if (!R.labelLiftNeedsState && !raw && name !== 'blur') raw = {};
      return proxied(raw, name, e, l, R);
    }
  }
}

// ---- comparison ----
const near = (a, b) => (typeof a === 'number' && typeof b === 'number' ? Math.abs(a - b) <= 1e-9 * Math.max(1, Math.abs(a)) : a === b);
function canon(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v === undefined ? null : v);
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  return '{' + Object.keys(v).filter(k => v[k] !== undefined).sort().map(k => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
}
function eventView(e) {
  const p = e.payload;
  if (e.type === 'selectchanged') return { type: e.type, selected: p.selected, isFromClick: p.isFromClick, fromAction: p.fromAction, fromActionPayload: p.fromActionPayload };
  return { type: e.type, payload: p };
}
function caseDiffs(c, R) {
  const pred = predictCase(c, R);
  const diffs = [];
  const diff = (k, what, got, want) => diffs.push({ step: k, what, got, want });
  c.steps.forEach((st, k) => {
    const P = pred[k];
    const ge = canon(st.events.map(eventView));
    const we = canon(P.events.map(eventView));
    if (ge !== we) diff(k, 'events', st.events.map(eventView), P.events.map(eventView));
    st.state.series.forEach((rec, s) => {
      const ps = P.state.series[s];
      if (rec.shown !== ps.shown) diff(k, 's' + s + '.shown', rec.shown, ps.shown);
      if (canon(rec.selectedMap) !== canon(ps.selectedMap)) diff(k, 's' + s + '.selectedMap', rec.selectedMap, ps.selectedMap);
      if (canon(rec.selectedIndices) !== canon(ps.selectedIndices)) diff(k, 's' + s + '.selectedIndices', rec.selectedIndices, ps.selectedIndices);
      if (canon(rec.items.map(it => it.d)) !== canon(ps.raws)) diff(k, 's' + s + '.raws', rec.items.map(it => it.d), ps.raws);
      rec.items.forEach((it, i) => {
        const pi = ps.items[i];
        if (!pi !== (it.el == null)) diff(k, 's' + s + ' d' + it.d + ' element', it.el, pi);
        if (!pi) return;
        if (!!it.label !== !!pi.label || !!it.guide !== !!pi.guide) diff(k, 's' + s + ' d' + it.d + ' label / guide presence', [!!it.label, !!it.guide], [!!pi.label, !!pi.guide]);
        for (const f of ['st', 'sel', 'hs', 'hbo', 'z2', 'fill', 'stroke', 'lineWidth', 'opacity', 'x', 'y', 'r', 'sx', 'sy', 'ghs', 'phbo']) {
          if (!(f in pi)) continue;
          const a = f === 'hbo' ? it.hbo : it[f];
          const ok = Array.isArray(a) ? canon(a) === canon(pi[f]) : near(a, pi[f]);
          if (!ok) diff(k, 's' + s + ' d' + it.d + ' ' + f, a, pi[f]);
        }
        if (it.label && pi.label) {
          for (const f of ['st', 'ignore', 'fill', 'opacity', 'z2', 'x', 'y']) {
            const a = it.label[f];
            const ok = Array.isArray(a) ? canon(a) === canon(pi.label[f]) : near(a, pi.label[f]);
            if (!ok) diff(k, 's' + s + ' d' + it.d + ' label.' + f, a, pi.label[f]);
          }
        }
        if (it.guide && pi.guide) for (const f of ['st', 'x', 'y']) {
          const a = it.guide[f];
          if (Array.isArray(a) ? canon(a) !== canon(pi.guide[f]) : !near(a, pi.guide[f])) diff(k, 's' + s + ' d' + it.d + ' guide.' + f, a, pi.guide[f]);
        }
      });
      if (!!rec.poly !== !!ps.poly) diff(k, 's' + s + ' poly presence', !!rec.poly, !!ps.poly);
      if (rec.poly && ps.poly) for (const f of ['st', 'hs', 'stroke', 'lineWidth', 'opacity', 'z2']) {
        const a = rec.poly[f];
        if (Array.isArray(a) ? canon(a) !== canon(ps.poly[f]) : !near(a, ps.poly[f])) diff(k, 's' + s + ' poly.' + f, a, ps.poly[f]);
      }
    });
    if (!!st.state.legend !== !!P.state.legend) diff(k, 'legend presence', !!st.state.legend, !!P.state.legend);
    if (st.state.legend) {
      const g = st.state.legend;
      const w = P.state.legend;
      if (canon(g.selected) !== canon(w.selected)) diff(k, 'legend.selected', g.selected, w.selected);
      const gi = g.items.map(i => ({ name: i.name, icon: i.icon === 'group' ? 'group' : { fill: i.icon.fill, stroke: i.icon.stroke, lineWidth: i.icon.lineWidth }, text: i.text }));
      if (canon(gi) !== canon(w.items)) diff(k, 'legend.items', gi, w.items);
    }
  });
  return diffs;
}

const GUARDS = [
  { id: 'G-single-keeps-last', mutation: "'single' keeps the FIRST of several indices", mut: { singleKeepsLast: false }, named: ['action-select-single'] },
  { id: 'G-series-unselect', mutation: "unselect in 'series' mode clears only the clicked name", mut: { seriesUnselectClears: false }, named: ['pie-series', 'bar-series'] },
  { id: 'G-click-toggles', mutation: 'a click always dispatches select', mut: { clickToggles: false }, named: ['pie-single', 'pie-multiple', 'bar-single'] },
  { id: 'G-selected-raw', mutation: 'selected indices are inner indices', mut: { selectedRaw: false }, named: ['legend-pie'] },
  { id: 'G-select-by-name', mutation: 'selection keyed by index, not by name', mut: { selectByName: false }, named: ['pie-dup-names'] },
  { id: 'G-offset-cos-sin', mutation: 'selectedOffset dx = sin, dy = cos', mut: { offsetCosSin: false }, named: ['pie-single', 'pie-offset'] },
  { id: 'G-z2-current', mutation: 'the z2 lift starts from the rest z2 (no creep)', mut: { z2FromCurrent: false }, named: ['pie-hover-creep', 'pie-single'] },
  { id: 'G-select-lift-10', mutation: 'select lifts z2 by 10', mut: { selectLift: 10 }, named: ['bar-single', 'action-select-bar'] },
  { id: 'G-emphasis-lift-9', mutation: 'emphasis lifts z2 by 9', mut: { emphasisLift: 9 }, named: ['highlight-bar', 'focus-pie-self'] },
  { id: 'G-blur-0.2', mutation: 'the default blur multiplies opacity by 0.2', mut: { blurFactor: 0.2 }, named: ['focus-series-coord', 'focus-pie-self'] },
  { id: 'G-scope-coordsys', mutation: 'blurScope coordinateSystem acts as global', mut: { scopeCoordSys: false }, named: ['focus-series-coord', 'focus-two-grids'] },
  { id: 'G-focus-series-own', mutation: "focus 'series' blurs its own series too", mut: { focusSeriesSparesOwn: false }, named: ['focus-series-coord', 'line-focus'] },
  { id: 'G-self-blurs-own', mutation: "focus 'self' spares its own series", mut: { selfBlursOwn: false }, named: ['focus-self-series-scope', 'focus-pie-self'] },
  { id: 'G-hover-hbo', mutation: 'hover overrides an action highlight', mut: { hoverRespectsHbo: false }, named: ['highlight-bar'] },
  { id: 'G-highlight-leaves-blur', mutation: 'a highlight / downplay does not first leave all blur', mut: { highlightLeavesBlur: false }, named: ['highlight-focus'] },
  { id: 'G-legend-single', mutation: "legend unSelect works in 'single' mode", mut: { legendSingleNoUnselect: false }, named: ['legend-single'] },
  { id: 'G-inactive-width', mutation: 'a numeric inactiveBorderWidth is applied', mut: { legendInactiveWidthAutoOnly: false }, named: ['legend-inactive-custom'] },
  { id: 'G-legend-click-order', mutation: 'a legend click does not downplay before toggling', mut: { legendClickDownplayFirst: false }, named: ['legend-bar-toggle', 'legend-pie'] },
  { id: 'G-lift-select-fill', mutation: 'emphasis lifts the NORMAL fill even when selected', mut: { liftFromSelectFill: false }, named: ['pie-select-style', 'bar-multiple-style'] },
  { id: 'G-select-disabled', mutation: 'select.disabled ignored', mut: { selectDisabledHonoured: false }, named: ['bar-multiple-style'] },
  { id: 'G-legacy-needs-selected', mutation: 'legacy pie events fire even when nothing of the pie is selected', mut: { legacyNeedsSelected: false }, named: ['pie-off', 'action-select-pie'] },
  { id: 'G-symbol-highlight-path', mutation: 'Symbol.highlight marks the group (hover can no longer clear it)', mut: { symbolHighlightOnPath: false }, named: ['highlight-line'] },
  { id: 'G-pie-label-offset', mutation: 'the pie label select state is the bare offset', mut: { pieLabelFollowsOffset: false }, named: ['pie-single', 'action-select-pie'] },
  { id: 'G-disabled-proxy', mutation: 'emphasis.disabled keeps the default state proxy (select z2 + 9)', mut: { disabledHasNoProxy: false }, named: ['emphasis-disabled'] },
  { id: 'G-rerender-prev-states', mutation: 'a re-render does not re-apply the previous states before the new ones', mut: { rerenderRestoresPrevStates: false }, named: ['legend-pie'] },
  { id: 'G-refound', mutation: 'a hovered element removed by a re-render is not re-found', mut: { refindRemovedHover: false }, named: ['legend-single'] },
  { id: 'G-label-lift-state', mutation: 'a label without an emphasis / select state object still lifts z2', mut: { labelLiftNeedsState: false }, named: ['focus-series-coord'] },
  { id: 'G-self-spares-held', mutation: "focus 'self' blurs an element held by an action too", mut: { selfSparesHeld: false }, named: ['focus-self-held'] },
  { id: 'G-truthy-focus', mutation: "a truthy focus that is neither 'self' nor 'series' blurs nothing", mut: { truthyFocusBlurs: false }, named: ['focus-truthy-other'] },
  { id: 'G-unknown-scope', mutation: "an unknown blurScope acts as 'coordinateSystem'", mut: { unknownScopeGlobal: false }, named: ['focus-truthy-other'] },
  { id: 'G-sunburst-descendant', mutation: "a sunburst has no default focus", mut: { sunburstDescendant: false }, named: ['focus-sunburst'] },
  { id: 'G-focus-indices', mutation: 'the focus indices do not leave the blur', mut: { focusIndicesLeaveBlur: false }, named: ['focus-sunburst', 'focus-sunburst-ancestor'] },
  { id: 'G-sunburst-blur', mutation: "a sunburst's blur opacities are the default tenth", mut: { sunburstBlurDefaults: false }, named: ['focus-sunburst'] },
  { id: 'G-candle-emphasis-width', mutation: 'a candlestick has no default emphasis border width', mut: { candleEmphasisWidth: false }, named: ['focus-candlestick'] },
];

let diffCases = 0;
function check(g) {
  let steps = 0;
  let evCount = 0;
  for (const c of g.cases) {
    const d = caseDiffs(c, RULES);
    if (d.length && process.env.ORACLE_DIFFS) { for (const x of d.slice(0, +process.env.ORACLE_DIFFS)) console.log(c.id + ' step ' + x.step + ' ' + x.what + '\n  got  ' + JSON.stringify(x.got) + '\n  want ' + JSON.stringify(x.want)); diffCases++; continue; }
    if (d.length) must(false, c.id + ': the transcription differs (' + d.length + ' diffs), first at step ' + d[0].step + ' ' + d[0].what + ':\n got  ' + JSON.stringify(d[0].got) + '\n want ' + JSON.stringify(d[0].want));
    steps += c.steps.length;
    for (const st of c.steps) evCount += st.events.length;
  }
  const guards = GUARDS.map(gd => {
    const R = Object.assign({}, RULES, gd.mut);
    const changed = g.cases.filter(c => caseDiffs(c, R).length).map(c => c.id);
    return { id: gd.id, mutation: gd.mutation, named: gd.named, changed, ok: gd.named.every(x => changed.includes(x)) };
  });
  must(!diffCases, diffCases + ' case diffs from the transcription (listed above)');
  expectations(g);
  return { guards, steps, events: evCount };
}

// explicit expectations read off the upstream source
function expectations(g) {
  const cs = id => { const c = g.cases.find(x => x.id === id); must(c, 'no case ' + id); return c; };
  const st = (id, k) => cs(id).steps[k];
  const types = (id, k) => st(id, k).events.map(e => e.type).join();
  const item = (id, k, s, d) => st(id, k).state.series[s].items.find(it => it.d === d);
  // a click on an item publishes select + selectchanged before the chart click
  must(types('pie-single', 2) === 'select,selectchanged,mapselectchanged,pieselectchanged,click', 'pie click order: ' + types('pie-single', 2));
  must(types('bar-off', 1) === 'select,selectchanged,click', 'selectedMode off still dispatches select');
  must(canon(st('bar-off', 1).events[1].payload.selected) === '[]', 'selectedMode off: selected []');
  // the select state of a pie slice: translation by selectedOffset along the mid angle
  const it = item('pie-offset', 0, 0, 3);
  must(it.st.join() === 'select' && near(it.x, Math.cos((it.a0 + it.a1) / 2) * 25) && near(it.y, Math.sin((it.a0 + it.a1) / 2) * 25), 'selectedOffset 25');
  // bar select default look
  const b = item('bar-single', 3, 0, 2);
  must(b.st.join() === 'select' && b.stroke === '#3c3c41' && b.lineWidth === 2 && b.z2 > b.rest.z2, 'bar select default look');
  // z2 creep
  const zs = [2, 3, 4, 5, 6].map(k => item('pie-hover-creep', k, 0, 1).z2);
  must(zs.join() === '21,31,40,50,59', 'z2 creep ' + zs.join());
  must(item('pie-hover-creep', 8, 0, 1).z2 === 2, 'z2 back to rest once no state is applied');
  // name-keyed selection
  must(item('pie-dup-names', 1, 0, 2).st.join() === 'select' && canon(st('pie-dup-names', 1).state.series[0].selectedIndices) === '[0]', 'duplicate names select together, indices list one');
  // select.disabled: in the map, in the indices, not in the state
  const md = st('bar-multiple-style', 2).state.series[0];
  must(md.selectedMap.Wed === true && md.selectedIndices.includes(2) && md.items[2].st.length === 1 && md.items[2].st[0] === 'emphasis', 'select.disabled');
  // legend click: downplay, legendselectchanged, highlight (after the hover's highlight)
  must(types('legend-bar-toggle', 1) === 'highlight,downplay,legendselectchanged,highlight', 'legend click order: ' + types('legend-bar-toggle', 1));
  must(st('legend-bar-toggle', 1).state.series[1].shown === false && st('legend-bar-toggle', 3).state.series[1].shown === true, 'legend toggles series visibility');
  must(cs('legend-mode-false').steps.every(s => !s.events.length), 'legend selectedMode false: no events at all');
  // raw indices after the pie filter
  const lp = st('legend-pie', 4).events.find(e => e.type === 'selectchanged');
  must(canon(lp.payload.selected) === canon([{ dataIndex: [2, 3], seriesIndex: 0 }]) && st('legend-pie', 4).hit.dp.i === 2, 'filtered pie: dispatch inner 2, report raw 3');
  // inactive legend: a numeric inactiveBorderWidth is ignored
  const li = st('legend-inactive-custom', 0).state.legend.items;
  must(li[0].icon.lineWidth === 2 && li[0].icon.fill === '#ff0000' && li[0].icon.stroke === '#00ff00' && li[0].text.fill === '#ff0000', 'inactive A');
  // blur scope
  const fc = st('focus-series-coord', 1).state.series;
  must(fc[1].items.every(i => i.st.join() === 'blur') && fc[2].poly.st.join() === 'blur' && fc[3].items.every(i => !i.st.length), 'coordinateSystem scope');
  const fg = st('focus-series-global', 1).state.series;
  must(fg[3].items.every(i => i.st.join() === 'blur'), 'global scope blurs the pie');
  must(st('emphasis-label', 1).state.series[1].items.every(i => i.opacity === 0.3), 'declared blur opacity');
  // emphasis.disabled: select without the z2 lift
  must(item('emphasis-disabled', 3, 0, 1).z2 === 1 && item('emphasis-disabled', 3, 0, 1).st.join() === 'select', 'disabled: no proxy');
}

// ============================================================================
// Output helpers (as mouse-events.js)
// ============================================================================
function sanitize(v) {
  if (typeof v === 'number') {
    if (Number.isNaN(v)) return null;
    if (v === Infinity) return 'Infinity';
    if (v === -Infinity) return '-Infinity';
    if (Object.is(v, -0)) return 0;
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
  if (ecKey === null) discoverECKey();
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

if (process.env.ORACLE_PROBE) {
  discoverECKey();
  const only = process.env.ORACLE_PROBE;
  console.log(JSON.stringify(CASES.filter(d => only === '*' || d.id === only).map(runCase)));
  process.exit(0);
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
      pointer: 'move = handler.mousemove; click = mousemove + mousedown + mouseup + click at one point, then one frame ({zrX, zrY, which: 1})',
      action: 'chart.dispatchAction(payload)',
      events: "chart.on(t, fn) for every published event type (brushselected excepted) + the legacy pie / map select events + 'click'",
    },
    notes: NOTES,
    cases: g1.cases,
    guards: chk.guards,
    checks: { steps: chk.steps, events: chk.events, fails: 0 },
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
const unexpected = logged.filter(l => !/DEPRECATED: event (pie|map)(selectchanged|selected|unselected) is deprecated/.test(l));
console.log(g1.cases.length + ' cases, ' + chk.steps + ' steps, ' + chk.events + ' events; transcription 0 fails; '
  + (chk.guards.length - bad.length) + '/' + chk.guards.length + ' guards; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; '
  + logged.length + ' console messages (' + unexpected.length + ' other than the legacy-event deprecation)' + (unexpected.length ? ': ' + Array.from(new Set(unexpected.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (!deterministic && process.env.ORACLE_DEBUG) {
  fs.writeFileSync(OUT + '.gen1', json1);
  fs.writeFileSync(OUT + '.gen2', json2);
}
if (bad.length || !deterministic || unexpected.length) {
  bad.forEach(gd => console.log('  ' + gd.id + ' named ' + gd.named.join(',') + ' changed ' + gd.changed.join(',')));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
