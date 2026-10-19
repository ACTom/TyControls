/*
Upstream's own answers for the STATES of the graph, tree and treemap series
on the shared state model (fix phase F2a, spec section 198): hover,
emphasis.focus (graph adjacency / self / series; tree ancestor / descendant /
relative; treemap ancestor / descendant), blurScope across series of other
types, emphasis.disabled, the declared emphasis / blur / select styles,
selectedMode with clicks and the select / unselect / toggleSelect actions
(the graph's edge data included), highlight / downplay (dataType 'edge'
included) and their events, the treemap's breadcrumb hover and its mouse
events, the treemap's label opacity, the graph node's itemStyle.opacity and
own label, and the graph's edgeLabel rotate / offset.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false` in every
case, process.env.TZ = 'UTC', Math.random = the port's xorshift32 reseeded
per chart. As select-legend.js: the chart is created with ssr: true, then
chart._ssr = false BEFORE setOption (the browser's model); pointer events go
straight to zrender's Handler with integer {zrX, zrY}; after EVERY step
chart._onframe() (the flags become state lists, as a browser frame) and
chart.renderToSVGString() (the display list the hit test walks). Every
record is read from the live elements after that frame.

  node tools/advchart-oracle/states-hier.js

writes tests/fixtures/advchart-states-hier.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Steps (case.steps[]):
  {type: 'move', x, y, aim, hit}   handler.mousemove
  {type: 'click', x, y, aim, hit}  mousemove, mousedown, mouseup, click at one
                                   point, then one frame
  {type: 'leave'}                  a mousemove at (-50, -50): zrender's own
                                   "the pointer left" (the port: MouseLeave)
  {type: 'action', payload}        chart.dispatchAction(payload)
  step 0 is {type: 'init'}: right after setOption and a frame.
  [R2-B] a step's aim may be a plain point ({xy: [x, y]}: the hit test's
  reach around a graph edge) or a breadcrumb item's point that something
  else covers ({crumbUnder: [s]}: a legend over it); a case with labelPlace
  also records a graph or tree node label's transform (label.m), where
  updateInnerText put it on the path as drawn (scaled under emphasis)
  hit (pointer steps, before the step): {hd: the OUTERMOST highDownDispatcher
    on the host / parent chain as {s, i, dt?} (series, INNER data index, data
    type) or {crumb: k} (a treemap breadcrumb item, k from the root) or null}
Per step:
  events[]  every published event in order {type, payload}: the action
            events (highlight, downplay, select, unselect, toggleselect,
            selectchanged, treemaprootttonode, ...) as plain data, and the
            mouse events (mouseover, mouseout, click) reduced to
            {componentType, seriesIndex, dataIndex, dataType, name, selfType,
            nodeData}
  state.series[]  one per series, by series index:
    {s, type, selectedMap, selectedIndices, ...}
    GRAPH  nodes[i] (inner node index) null | NODE, edges[i] (inner edge
           index) null | EDGE
      NODE = {raw, name, hs (the Symbol group's hoverState), hbo (the group's
        __highByOuter), path: EL (the symbol path) + {sx, sy} (its scale =
        the half size), label: TEXT | null}
      EDGE = {raw, name, hs, hbo (the Line group's), line: EL, arrows: [EL
        (fromSymbol), EL (toSymbol)] (null where absent), label: TEXT | null
        + {m: the label's transform [6]} }
    TREE   nodes[i] (data index; the virtual root 0 has none) null |
           {name, hs, hbo, path: EL + {sx, sy}, label: TEXT | null,
           edge: EL | null (symbolEl.__edge)}
    TREEMAP nodes[i] null | {name, leaf, hs, hbo (the DISPATCHER's: a leaf's
           node group, a parent's background), bg: EL + {label: TEXT|null} |
           null, content: EL + {label} | null}; crumbs[k] (from the root):
           EL + {text: TEXT}
    other series (the cross-series cases) items[i] = EL (the data item's
           element: a bar rect, a pie sector)
  EL   = {st (currentStates), hs (hoverState), sel (selected), px (has
         echarts' default state proxy), z2, fill, stroke, lineWidth, opacity,
         rest: {z2, fill, stroke, lineWidth, opacity}}
  TEXT = {st, ignore, opacity, z2, fill, rest: {opacity, z2, ignore}}
  Numbers: a double is [hex16 of its IEEE-754 bits, String(v)]; colours are
  upstream's strings ('#5070dd', a lift 'rgba(88,123,243,1)').

Self-checks (any failure: nothing is written, exit 1), recomputed at every
recorded step from the live records:
  R1 a label's state list equals its host's (a graph node's path, an edge's
     line, a tree node's path, a treemap rect), and a graph edge's arrows'
     lists equal the line's
  R2 an element in emphasis alone (no select) whose fill is a lifted
     'rgba(...)' holds liftColor of its rest fill (each channel * 1.1 | 0)
  R3 a tree node's edge differs from its node only where TreeView's
     onHoverStateChange left it: the node blurred (the edge was blurred by
     the traverse, never followed back) or the parent's symbol blurred
  R4 a treemap leaf's background and content carry one list
  R5 a key of the form 'a > b' (the graph's edge data's name) reaches the
     series' selectedMap only through an edge's selection
plus discriminating counts (each >= 1: a lift, a blurred and an emphasised
graph node, an action-held node, a selected node and edge, an edge key in
the map, a tree edge apart from its node, a treemap rect blurred under the
proxy, a label's and an upper label's opacity under itemStyle.opacity, a
breadcrumb emphasis and its events, a crumb's click dispatching, a series
of another type blurred by these), and two generations giving the same
bytes.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-states-hier.json');

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

const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));
const hasOwn = (o, k) => o != null && Object.prototype.hasOwnProperty.call(o, k);

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const num = v => (typeof v === 'number' ? [Number.isFinite(v) ? hex(v) : null, Object.is(v, -0) ? '-0' : String(v)] : null);

// ============================================================================
// Cases
// ============================================================================
const C = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df'];
// a graph whose view is the identity: the box is the data extent
const GN = () => [
  { name: 'a', x: 100, y: 100, itemStyle: { color: C[0] } },
  { name: 'b', x: 300, y: 100, itemStyle: { color: C[1] } },
  { name: 'c', x: 200, y: 250, itemStyle: { color: C[2] } },
  { name: 'd', x: 400, y: 250, itemStyle: { color: C[3] } },
  { name: 'e', x: 400, y: 130, itemStyle: { color: C[4] } },
];
const GL = () => [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd' }, { source: 'a', target: 'c' }];
const graphS = extra => Object.assign({
  type: 'graph', name: 'G', layout: 'none', symbolSize: 30, left: 100, top: 100, width: 300, height: 150,
  label: { show: true }, lineStyle: { color: '#888888', width: 2, opacity: 0.8 },
  data: GN(), links: GL(),
}, extra || {});
const TREE = () => [{ name: 'root', children: [
  { name: 'A', children: [{ name: 'A1' }, { name: 'A2' }] },
  { name: 'B', children: [{ name: 'B1', children: [{ name: 'B1x' }] }] },
] }];
const treeS = extra => Object.assign({
  type: 'tree', name: 'T', data: TREE(), left: 60, top: 40, bottom: 40, right: 160, symbolSize: 14,
  expandAndCollapse: false, initialTreeDepth: -1,
  label: { show: true, position: 'left' }, leaves: { label: { position: 'right' } },
  itemStyle: { color: C[0], borderColor: '#333333', borderWidth: 1 },
  lineStyle: { color: '#999999', width: 2 },
}, extra || {});
const TM = () => [
  { name: 'A', itemStyle: { color: C[0] }, children: [
    { name: 'a1', value: 6, itemStyle: { color: C[1] } },
    { name: 'a2', value: 4, itemStyle: { color: C[2] } },
  ] },
  { name: 'B', value: 8, itemStyle: { color: C[3] } },
];
const tmS = extra => Object.assign({
  type: 'treemap', name: 'M', data: TM(), left: 20, top: 20, width: 560, height: 320,
  roam: false, nodeClick: false, breadcrumb: { show: false },
  upperLabel: { show: true, height: 24 },
  itemStyle: { borderColor: '#ffffff', borderWidth: 3, gapWidth: 3 },
}, extra || {});
const CAT = ['Mon', 'Tue', 'Wed'];
const pieS = extra => Object.assign({ type: 'pie', name: 'P', center: [520, 330], radius: [0, 50],
  label: { show: false },
  data: [{ name: 'p0', value: 3, itemStyle: { color: C[0] } }, { name: 'p1', value: 5, itemStyle: { color: C[1] } }] }, extra || {});

const node = (s, i) => ({ node: [s, i] });
const edge = (s, i) => ({ edge: [s, i] });
const nlabel = (s, i) => ({ nlabel: [s, i] });
const tnode = (s, i) => ({ tnode: [s, i] });
const tmrect = (s, i, part) => ({ tm: [s, i, part] });
const crumb = (s, k) => ({ crumb: [s, k] });
const item = (s, i) => ({ item: [s, i] });
const empty = (x, y) => ({ empty: [x || 5, y || 5] });
const mv = at => ({ type: 'move', at });
const ck = at => ({ type: 'click', at });
const leave = () => ({ type: 'leave' });
const act = payload => ({ type: 'action', payload });

const CASES = [
  // ------------------------------------------------------------------ graph
  { id: 'g-adjacency', note: "graph focus 'adjacency': hover node b (its edges and their ends stay normal, the rest blurs, b emphasis: lift, scale, z2 + 10), the edge b-c, the label of a (the node's hover), leave",
    option: { animation: false, series: [graphS({ emphasis: { focus: 'adjacency' }, edgeSymbol: ['none', 'arrow'], edgeLabel: { show: true } })] },
    steps: [mv(node(0, 1)), mv(edge(0, 1)), mv(nlabel(0, 0)), leave()] },
  { id: 'g-cartesian-bar', note: "a graph on the cartesian of a bar series: the graph's hover (focus adjacency, blurScope coordinateSystem) blurs the bars too; a bar's (focus 'series') blurs the graph",
    option: { animation: false, xAxis: { type: 'value', min: 0, max: 6 }, yAxis: { type: 'value', min: 0, max: 6 },
      series: [
        { type: 'graph', name: 'G', coordinateSystem: 'cartesian2d', symbolSize: 24, emphasis: { focus: 'adjacency' },
          lineStyle: { color: '#888888', width: 2 },
          data: [{ name: 'a', value: [1, 4], itemStyle: { color: C[0] } }, { name: 'b', value: [3, 5], itemStyle: { color: C[1] } }, { name: 'c', value: [5, 4], itemStyle: { color: C[2] } }],
          links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] },
        { type: 'bar', name: 'B', data: [[1, 2], [3, 1], [5, 2]], barWidth: 20, itemStyle: { color: C[3] }, emphasis: { focus: 'series' } },
      ] },
    steps: [mv(node(0, 0)), leave(), mv(item(1, 1)), leave()] },
  { id: 'g-global-pie', note: "graph focus 'self' blurScope 'global' with a pie: hovering a node blurs the pie; the pie's slice (focus 'self', global) blurs the graph -- its labels and arrows too",
    option: { animation: false, series: [graphS({ emphasis: { focus: 'self', blurScope: 'global' }, edgeSymbol: ['circle', 'arrow'], edgeSymbolSize: 8 }),
      pieS({ emphasis: { focus: 'self', blurScope: 'global' } })] },
    steps: [mv(node(0, 2)), leave(), mv(item(1, 1)), leave()] },
  { id: 'g-actions', note: "highlight / downplay: a node by name (adjacency focus blurs), an edge by dataType 'edge', notBlur, highlightKey; hovering the highlighted node and leaving keeps it (hbo); downplay; a downplay of everything",
    option: { animation: false, series: [graphS({ emphasis: { focus: 'adjacency' } })] },
    steps: [act({ type: 'highlight', seriesIndex: 0, name: 'b' }), mv(node(0, 1)), leave(),
      act({ type: 'downplay', seriesIndex: 0, name: 'b' }),
      act({ type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 2 }),
      act({ type: 'downplay', seriesIndex: 0, dataType: 'edge', dataIndex: 2 }),
      act({ type: 'highlight', seriesIndex: 0, dataIndex: [0, 3], notBlur: true, highlightKey: 'k1' }),
      act({ type: 'downplay', seriesIndex: 0, dataIndex: 0, highlightKey: 'k1' }),
      act({ type: 'downplay', seriesIndex: 0 })] },
  { id: 'g-select', note: "graph selectedMode 'multiple': clicks select a node (default select border, the primary token) and an edge (the edge data's name 'a > b' in the same map); select / unselect / toggleSelect actions with dataType 'edge'; hovering a selected node lifts its fill",
    option: { animation: false, series: [graphS({ selectedMode: 'multiple', select: { lineStyle: { color: '#ff0000', width: 4 } } })] },
    steps: [ck(node(0, 0)), ck(edge(0, 0)), act({ type: 'select', seriesIndex: 0, dataType: 'edge', dataIndex: 2 }),
      act({ type: 'toggleSelect', seriesIndex: 0, dataType: 'edge', dataIndex: [0, 1] }),
      act({ type: 'unselect', seriesIndex: 0, name: 'a' }), mv(node(0, 3)), ck(node(0, 3)), leave()] },
  { id: 'g-select-legend', note: "a legend hides category k0 (node a): the edge data drops a-b and a-c (filterSelf), so an edge's data index is not its link's row; selectedMode 'single': click the edge b-c (edge data 0, link 1), then c-d, select by action the raw index 1 (b-c again: its link's row, edge data 0), hover c-d, leave",
    option: { animation: false, legend: { data: ['k0'], selected: { k0: false } },
      series: [graphS({ selectedMode: 'single', categories: [{ name: 'k0' }, { name: 'k1' }],
        data: GN().map((n, i) => Object.assign(n, { category: i === 0 ? 0 : 1 })) })] },
    steps: [ck(edge(0, 0)), ck(edge(0, 1)), act({ type: 'select', seriesIndex: 0, dataType: 'edge', dataIndex: 1 }),
      mv(edge(0, 1)), leave()] },
  { id: 'g-declared', note: 'declared emphasis / blur / select styles on nodes (item, category, series) and edges (link, series); a disabled node and a disabled edge: no hover at all, and under another hover only their declared blur opacity',
    option: { animation: false, series: [graphS({
      categories: [{ name: 'k0', emphasis: { itemStyle: { color: '#123456' } }, blur: { itemStyle: { opacity: 0.4 } } }],
      emphasis: { focus: 'self', itemStyle: { borderColor: '#000000', borderWidth: 3 }, lineStyle: { color: '#00aa00', width: 5 } },
      blur: { itemStyle: { opacity: 0.25 }, lineStyle: { opacity: 0.3 }, label: { opacity: 0.5 } },
      data: [
        { name: 'a', x: 100, y: 100, category: 0, itemStyle: { color: C[0] } },
        { name: 'b', x: 300, y: 100, itemStyle: { color: C[1] }, emphasis: { disabled: true } },
        { name: 'c', x: 200, y: 250, itemStyle: { color: C[2] }, emphasis: { itemStyle: { color: '#abcdef' }, scale: 1.5 } },
        { name: 'd', x: 400, y: 250, category: 0, itemStyle: { color: C[3] } },
        { name: 'e', x: 400, y: 130, itemStyle: { color: C[4] }, blur: { itemStyle: { opacity: 0.6 } } },
      ],
      links: [{ source: 'a', target: 'b', emphasis: { disabled: true } }, { source: 'b', target: 'c' }, { source: 'c', target: 'd', blur: { lineStyle: { opacity: 0.05 } } }, { source: 'a', target: 'c' }],
    })] },
    steps: [mv(node(0, 0)), mv(node(0, 1)), mv(node(0, 2)), mv(edge(0, 1)), mv(edge(0, 0)), leave()] },
  { id: 'g-node-style', note: "node itemStyle.opacity (series and item) under blur; a node's own label (show, color, position, formatter) and its category's; edgeLabel rotate / offset (series, and one link's own)",
    option: { animation: false, series: [graphS({
      categories: [{ name: 'k0', label: { color: '#ff0000' } }],
      itemStyle: { opacity: 0.7 }, emphasis: { focus: 'adjacency' },
      label: { show: true, position: 'top' },
      edgeLabel: { show: true, rotate: 30, offset: [6, -4], formatter: '{b}' },
      data: [
        { name: 'a', x: 100, y: 100, itemStyle: { color: C[0], opacity: 0.5 } },
        { name: 'b', x: 300, y: 100, itemStyle: { color: C[1] }, label: { show: false } },
        { name: 'c', x: 200, y: 250, category: 0, itemStyle: { color: C[2] } },
        { name: 'd', x: 400, y: 250, itemStyle: { color: C[3] }, label: { position: 'right', color: '#00ff00', formatter: 'N:{b}' } },
        { name: 'e', x: 400, y: 130, itemStyle: { color: C[4] } },
      ],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c', label: { rotate: -45, offset: [0, 10] } }, { source: 'c', target: 'd' }, { source: 'a', target: 'c', label: { show: false } }],
    })] },
    steps: [mv(node(0, 4)), leave(), mv(node(0, 1)), leave()] },
  // ------------------------------------------------------------------ tree
  { id: 't-descendant', note: "tree focus 'descendant': hover A (A and A1, A2 stay, the rest blurs; an edge leaves the blur only with a node whose parent is not blurred), hover B1, leave",
    option: { animation: false, series: [treeS({ emphasis: { focus: 'descendant' } })] },
    steps: [mv(tnode(0, 2)), mv(tnode(0, 6)), leave()] },
  { id: 't-ancestor-relative', note: "tree focus 'ancestor' on the series, 'relative' on B (item), 'self' on A2: hover A1, B, A2, leave",
    option: { animation: false, series: [treeS({ emphasis: { focus: 'ancestor' },
      data: [{ name: 'root', children: [
        { name: 'A', children: [{ name: 'A1' }, { name: 'A2', emphasis: { focus: 'self' } }] },
        { name: 'B', emphasis: { focus: 'relative' }, children: [{ name: 'B1', children: [{ name: 'B1x' }] }] }] }] })] },
    steps: [mv(tnode(0, 3)), mv(tnode(0, 5)), mv(tnode(0, 4)), leave()] },
  { id: 't-global-pie', note: "tree focus 'descendant' blurScope 'global' with a pie: the pie blurs under the tree's hover; the pie (focus series, global) blurs every tree node, edge and label",
    option: { animation: false, series: [treeS({ emphasis: { focus: 'descendant', blurScope: 'global' } }), pieS({ emphasis: { focus: 'series', blurScope: 'global' } })] },
    steps: [mv(tnode(0, 5)), leave(), mv(item(1, 0)), leave()] },
  { id: 't-actions-select', note: "tree highlight (descendant focus from the payload's element), downplay; selectedMode 'single' clicks with a declared select colour; select action by name; emphasis.disabled on a leaf (leaves model) and a declared emphasis colour / blur opacity / edge emphasis colour",
    option: { animation: false, series: [treeS({ selectedMode: 'single', emphasis: { focus: 'descendant', itemStyle: { color: '#aa0000' }, lineStyle: { color: '#00aa00' } },
      blur: { itemStyle: { opacity: 0.3 } }, select: { itemStyle: { color: '#000000' } },
      leaves: { label: { position: 'right' }, emphasis: { disabled: true } } })] },
    steps: [act({ type: 'highlight', seriesIndex: 0, dataIndex: 5 }), act({ type: 'downplay', seriesIndex: 0, dataIndex: 5 }),
      ck(tnode(0, 2)), ck(tnode(0, 5)), act({ type: 'select', seriesIndex: 0, name: 'A1' }),
      mv(tnode(0, 3)), mv(tnode(0, 1)), leave()] },
  { id: 't-held-ancestor', note: "tree focus 'ancestor': highlight A1 by action (blurs the rest, A1 held), then hover A1 itself -- blurSeries blurs the held node too and the ancestor indices (A1 among them) leave blur, the held node takes no hover: A1 ends normal; leave, downplay",
    option: { animation: false, series: [treeS({ emphasis: { focus: 'ancestor' } })] },
    steps: [act({ type: 'highlight', seriesIndex: 0, dataIndex: 3 }), mv(tnode(0, 3)), leave(),
      act({ type: 'downplay', seriesIndex: 0, dataIndex: 3 })] },
  // ------------------------------------------------------------------ treemap
  { id: 'm-descendant', note: "treemap focus 'descendant' with declared emphasis (color, strokeColor, strokeWidth, borderColor for the background) and blur colours; hover the parent A's header (its background is the dispatcher), the leaf a1 (its node group), B; leave. Labels and upper labels take itemStyle.opacity (series 0.8, a2 0.4)",
    option: { animation: false, series: [tmS({ emphasis: { focus: 'descendant', itemStyle: { color: '#123456', borderColor: '#654321', strokeColor: '#ff0000', strokeWidth: 2 } },
      blur: { itemStyle: { color: '#dddddd' } }, itemStyle: { borderColor: '#ffffff', borderWidth: 3, gapWidth: 3, opacity: 0.8 },
      data: [{ name: 'A', itemStyle: { color: C[0] }, children: [{ name: 'a1', value: 6, itemStyle: { color: C[1] } }, { name: 'a2', value: 4, itemStyle: { color: C[2], opacity: 0.4 } }] },
        { name: 'B', value: 8, itemStyle: { color: C[3] } }] })] },
    steps: [mv(tmrect(0, 1, 'bg')), mv(tmrect(0, 2, 'content')), mv(tmrect(0, 4, 'content')), leave()] },
  { id: 'm-ancestor-disabled', note: "treemap focus 'ancestor'; a2 emphasis.disabled (no dispatcher, but the default proxy stays: blurred to a tenth); hover a2 (nothing), a1, A, leave",
    option: { animation: false, series: [tmS({ emphasis: { focus: 'ancestor' },
      data: [{ name: 'A', itemStyle: { color: C[0] }, children: [{ name: 'a1', value: 6, itemStyle: { color: C[1] } }, { name: 'a2', value: 4, itemStyle: { color: C[2] }, emphasis: { disabled: true } }] },
        { name: 'B', value: 8, itemStyle: { color: C[3] } }] })] },
    steps: [mv(tmrect(0, 3, 'content')), mv(tmrect(0, 2, 'content')), mv(tmrect(0, 1, 'bg')), leave()] },
  { id: 'm-select-actions', note: "treemap selectedMode 'multiple' (declared select color / strokeColor): click a1, select A by action (its background only), highlight B and A by action (focus self), downplay; hover a selected leaf",
    option: { animation: false, series: [tmS({ selectedMode: 'multiple', emphasis: { focus: 'self' }, select: { itemStyle: { color: '#000000', strokeColor: '#ff0000', strokeWidth: 2 } } })] },
    steps: [ck(tmrect(0, 2, 'content')), act({ type: 'select', seriesIndex: 0, name: 'A' }),
      act({ type: 'highlight', seriesIndex: 0, dataIndex: [4, 1] }), act({ type: 'downplay', seriesIndex: 0, dataIndex: 4 }),
      act({ type: 'downplay', seriesIndex: 0, dataIndex: 1 }), mv(tmrect(0, 2, 'content')), leave()] },
  { id: 'm-global-pie', note: "a treemap and a pie, both blurScope 'global': the treemap's hover blurs the pie, the pie's every treemap rect and label",
    option: { animation: false, series: [tmS({ width: 440, emphasis: { focus: 'self', blurScope: 'global' } }), pieS({ emphasis: { focus: 'self', blurScope: 'global' } })] },
    steps: [mv(tmrect(0, 4, 'content')), leave(), mv(item(1, 0)), leave()] },
  { id: 'm-breadcrumb', note: "the breadcrumb: hover its items (emphasis colour, z2 + 10, the text's emphasis style), their mouse events (selfType 'breadcrumb', nodeData), a click on a crumb (treemapZoomToNode; the view is then 'animating' for good without a timer, so later crumb clicks would do nothing), leave",
    option: { animation: false, series: [tmS({ nodeClick: 'zoomToNode', breadcrumb: { show: true, bottom: 10, itemStyle: { color: '#eeeeee', textStyle: { color: '#333333' } },
      emphasis: { itemStyle: { color: '#cccccc', textStyle: { color: '#ff0000' } } } }, height: 300 })] },
    steps: [mv(crumb(0, 1)), mv(crumb(0, 0)), leave(), ck(crumb(0, 1)), leave()] },
  { id: 'm-breadcrumb-default', note: "the breadcrumb's own emphasis: no declared emphasis text colour (createTextStyle of an empty model), the default emphasis item colour; a leaf drilled into (rootToNode) gives three crumbs",
    option: { animation: false, series: [tmS({ nodeClick: 'zoomToNode', breadcrumb: { show: true, bottom: 10, itemStyle: { color: '#eeeeee', textStyle: { color: '#333333' } } }, height: 300 })] },
    steps: [act({ type: 'treemapRootToNode', seriesIndex: 0, targetNodeId: 'a1' }), mv(crumb(0, 2)), mv(crumb(0, 1)), leave()] },
  // ------------------------------------------------------------------ R2-B
  { id: 'g-label-follows', labelPlace: true, note: "[R2-B] a hovered node's label rides its scaled symbol (updateInnerText on the path as drawn): right (b), top (c), inside (d: stays), left (e, symbolSize 20: ratio max(1.1, 3 / 10))",
    option: { animation: false, series: [graphS({ label: { show: true, position: 'right' },
      data: [
        { name: 'a', x: 100, y: 100, itemStyle: { color: C[0] } },
        { name: 'b', x: 300, y: 100, itemStyle: { color: C[1] } },
        { name: 'c', x: 200, y: 250, itemStyle: { color: C[2] }, label: { position: 'top' } },
        { name: 'd', x: 400, y: 250, itemStyle: { color: C[3] }, label: { position: 'inside' } },
        { name: 'e', x: 400, y: 130, itemStyle: { color: C[4] }, symbolSize: 20, label: { position: 'left' } },
      ] })] },
    steps: [mv(node(0, 1)), mv(node(0, 2)), mv(node(0, 3)), mv(node(0, 4)), leave()] },
  { id: 't-label-follows', labelPlace: true, note: "[R2-B] a hovered tree node's label rides its scaled symbol: A (left), A1 (a leaf: right), B1x",
    option: { animation: false, series: [treeS()] },
    steps: [mv(tnode(0, 2)), mv(tnode(0, 3)), mv(tnode(0, 7)), leave()] },
  { id: 'g-edge-reach', note: "[R2-B] a graph edge takes the pointer within zrender's stroke threshold, max(lineWidth, 5) / 2 a side (Path.contain, no fill): a-b is 2 wide -- 3 px off it nothing, 2 px off it the edge; c-d is 12 wide -- 5 px off it the edge, 7 px off it nothing",
    option: { animation: false, series: [graphS({ label: { show: false },
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }, { source: 'c', target: 'd', lineStyle: { width: 12 } }, { source: 'a', target: 'c' }] })] },
    steps: [mv({ xy: [200, 103] }), mv({ xy: [200, 102] }), mv({ xy: [300, 255] }), mv({ xy: [300, 257] }), leave()] },
  { id: 'm-crumb-under-legend', note: "[R2-B] a legend (z 4) over the breadcrumb (the treemap's own group, z 2): the pointer on both is the legend's -- its hover highlights the pie -- not the crumb's; a crumb in the clear is its own",
    option: { animation: false, legend: { data: ['P'], bottom: 12, left: 'center', itemHeight: 16 },
      series: [tmS({ width: 440, height: 300, nodeClick: 'zoomToNode', breadcrumb: { show: true, bottom: 10, itemStyle: { color: '#eeeeee', textStyle: { color: '#333333' } } } }),
        pieS({ label: { show: false } })] },
    steps: [mv({ crumbUnder: [0] }), leave(), mv(crumb(0, 0)), leave()] },
  { id: 'm-node-click-payload', note: "[R2-B] a click on a leaf (nodeClick zoomToNode): the view's own dispatch, {type, from: its uid, seriesId, targetNode: the TreeNode}",
    option: { animation: false, series: [tmS({ nodeClick: 'zoomToNode' })] },
    steps: [ck(tmrect(0, 4, 'content'))] },
];

// ============================================================================
// Driving a case
// ============================================================================
const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

function newChart() {
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
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
function ecDataOf(el) {
  if (!el) return null;
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && ('dataIndex' in el[k] || 'eventData' in el[k])) return el[k];
  }
  return null;
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
function restOf(el) {
  const ns = el._normalState || {};
  const st = ns.style || el.style;
  const kv = k => (k in ns ? ns[k] : el[k]);
  return { ns, st, kv };
}
const colourOf = c => (c == null ? null : typeof c === 'string' ? c : '[gradient]');
function elRec(p) {
  if (!p) return null;
  const { st, kv } = restOf(p);
  return {
    st: (p.currentStates || []).join(','), hs: p.hoverState || 0, sel: !!p.selected, px: !!p.stateProxy,
    z2: p.z2, fill: colourOf(p.style.fill), stroke: colourOf(p.style.stroke), lineWidth: num(p.style.lineWidth), opacity: num(opac(p.style)),
    rest: { z2: kv('z2'), fill: colourOf(st.fill), stroke: colourOf(st.stroke), lineWidth: num(st.lineWidth), opacity: num(opac(st)) },
  };
}
function textRec(t) {
  if (!t) return null;
  const { st, kv } = restOf(t);
  return {
    st: (t.currentStates || []).join(','), ignore: !!t.ignore, opacity: num(opac(t.style)), z2: t.z2, fill: colourOf(t.style.fill),
    text: t.style.text == null ? null : String(t.style.text),
    rest: { opacity: num(opac(st)), z2: kv('z2'), ignore: !!kv('ignore') },
  };
}
const I6 = [1, 0, 0, 1, 0, 0];

// [R2-B] the case being run: a labelPlace case records node labels' transforms
let CUR_DEF = null;
function labelPlaced(rec, t) {
  if (rec && CUR_DEF && CUR_DEF.labelPlace) rec.m = Array.from(t.transform || I6).map(num);
  return rec;
}
function snapGraph(chart, sm) {
  const out = { nodes: [], edges: [] };
  const d = sm.getData();
  for (let i = 0; i < d.count(); i++) {
    const g = d.getItemGraphicEl(i);
    if (!g) { out.nodes.push(null); continue; }
    const p = g.childAt(0);
    const r = Object.assign({ raw: d.getRawIndex(i), name: d.getName(i), hs: g.hoverState || 0, hbo: g.__highByOuter || 0 },
      { path: Object.assign(elRec(p), { sx: num(p.scaleX), sy: num(p.scaleY), rsx: num(restOf(p).kv('scaleX')) }) });
    r.label = labelPlaced(textRec(p.getTextContent()), p.getTextContent());
    out.nodes.push(r);
  }
  const e = sm.getEdgeData();
  for (let i = 0; i < e.count(); i++) {
    const g = e.getItemGraphicEl(i);
    if (!g) { out.edges.push(null); continue; }
    const line = g.childOfName('line');
    const r = { raw: e.getRawIndex(i), name: e.getName(i), hs: g.hoverState || 0, hbo: g.__highByOuter || 0, line: elRec(line) };
    r.arrows = [elRec(g.childOfName('fromSymbol')), elRec(g.childOfName('toSymbol'))];
    const lab = g.getTextContent();
    r.label = textRec(lab);
    if (r.label) {
      r.label.m = Array.from(lab.transform || I6).map(num);
      r.label.align = lab.style.align || null;
      r.label.vAlign = lab.style.verticalAlign || null;
    }
    out.edges.push(r);
  }
  return out;
}
function snapTree(chart, sm) {
  const out = { nodes: [] };
  const d = sm.getData();
  for (let i = 0; i < d.count(); i++) {
    const g = d.getItemGraphicEl(i);
    if (!g) { out.nodes.push(null); continue; }
    const p = g.childAt(0);
    out.nodes.push({ name: d.getName(i), hs: g.hoverState || 0, hbo: g.__highByOuter || 0,
      path: Object.assign(elRec(p), { sx: num(p.scaleX), sy: num(p.scaleY), rsx: num(restOf(p).kv('scaleX')) }),
      label: labelPlaced(textRec(p.getTextContent()), p.getTextContent()), edge: g.__edge ? elRec(g.__edge) : null });
  }
  return out;
}
function snapTreemap(chart, sm) {
  const out = { nodes: [], crumbs: [] };
  const view = chart.getViewOfSeriesModel(sm);
  const stg = view._storage;
  const d = sm.getData();
  for (let i = 0; i < d.count(); i++) {
    const rawI = d.getRawIndex(i);
    const bg = stg.background[rawI];
    const ct = stg.content[rawI];
    const disp = d.getItemGraphicEl(i);
    if (!bg && !ct) { out.nodes.push(null); continue; }
    const live = el => el && el.__zr && !el.invisible;
    const rb = live(bg) ? Object.assign(elRec(bg), { label: textRec(bg.getTextContent()) }) : null;
    const rc = live(ct) ? Object.assign(elRec(ct), { label: textRec(ct.getTextContent()) }) : null;
    if (!rb && !rc) { out.nodes.push(null); continue; }
    out.nodes.push({ name: d.getName(i), leaf: !!rc, hs: disp ? disp.hoverState || 0 : null, hbo: disp ? disp.__highByOuter || 0 : null,
      disp: disp ? (disp === bg ? 'bg' : disp.isGroup ? 'group' : 'other') : null, bg: rb, content: rc });
  }
  const bc = view._breadcrumb;
  if (bc) {
    bc.group.eachChild(el => {
      out.crumbs.push(Object.assign(elRec(el), { text: textRec(el.getTextContent()), points: el.shape.points.map(p => [num(p[0]), num(p[1])]) }));
    });
  }
  return out;
}
function snapOther(chart, sm) {
  const d = sm.getData();
  const items = [];
  for (let i = 0; i < d.count(); i++) items.push(elRec(d.getItemGraphicEl(i)));
  return { items };
}
function snapshot(chart) {
  const out = { series: [] };
  chart.getModel().eachRawSeries(sm => {
    const r = { s: sm.seriesIndex, type: sm.subType,
      selectedMap: sm.option.selectedMap == null ? null : clone(sm.option.selectedMap),
      selectedIndices: sm.getSelectedDataIndices() };
    if (sm.subType === 'graph') Object.assign(r, snapGraph(chart, sm));
    else if (sm.subType === 'tree') Object.assign(r, snapTree(chart, sm));
    else if (sm.subType === 'treemap') Object.assign(r, snapTreemap(chart, sm));
    else Object.assign(r, snapOther(chart, sm));
    out.series.push(r);
  });
  return out;
}

const EVENT_TYPES = ['highlight', 'downplay', 'select', 'unselect', 'toggleselect', 'selectchanged',
  'treemapzoomtonode', 'treemaproottonode'];
const MOUSE_TYPES = ['mouseover', 'mouseout', 'click'];

function runCase(def) {
  CUR_DEF = def;
  const chart = newChart();
  const option = clone(def.option);
  const events = [];
  try {
    chart.setOption(clone(option));
    frame(chart);
    for (const t of EVENT_TYPES) chart.on(t, p => events.push({ type: t, payload: plain(p, 0) }));
    for (const t of MOUSE_TYPES) {
      chart.on(t, p => events.push({ type: t, payload: {
        componentType: p.componentType, seriesIndex: p.seriesIndex == null ? null : p.seriesIndex,
        dataIndex: p.dataIndex == null ? null : p.dataIndex, dataType: p.dataType == null ? null : p.dataType,
        name: p.name == null ? null : p.name, selfType: p.selfType == null ? null : p.selfType,
        nodeData: p.nodeData == null ? null : plain(p.nodeData, 0) } }));
    }
    const hd = () => chart.getZr().handler;
    const series = s => chart.getModel().getSeriesByIndex(s);
    const aimIn = (owner, rect, what) => {
      // the centre first, then outwards, every integer point of the rect
      const cx = Math.round(rect.x + rect.width / 2);
      const cy = Math.round(rect.y + rect.height / 2);
      const R = Math.ceil(Math.max(rect.width, rect.height) / 2) + 2;
      for (let r = 0; r <= R; r++) {
        for (let dy = -r; dy <= r; dy++) {
          for (let dx = -r; dx <= r; dx++) {
            if (Math.max(Math.abs(dx), Math.abs(dy)) !== r) continue;
            const t = hd().findHover(cx + dx, cy + dy).target;
            if (t && owns(owner, t)) return [cx + dx, cy + dy];
          }
        }
      }
      throw new OracleError(def.id + ': no point hits ' + what);
    };
    const resolve = at => {
      if (at.node || at.nlabel) {
        const [s, i] = at.node || at.nlabel;
        const g = series(s).getData().getItemGraphicEl(i);
        must(g, def.id + ': node ' + i + ' not drawn');
        if (at.nlabel) {
          const t = g.childAt(0).getTextContent();
          must(t && !t.ignore, def.id + ': node ' + i + ' has no label');
          const p = aimIn(t, globalRect(t), 'node label');
          return { x: p[0], y: p[1], aim: 'label of node s' + s + ' i' + i };
        }
        const p = aimIn(g.childAt(0), globalRect(g.childAt(0)), 'node');
        return { x: p[0], y: p[1], aim: 'node s' + s + ' i' + i };
      }
      if (at.edge) {
        const [s, i] = at.edge;
        const g = series(s).getEdgeData().getItemGraphicEl(i);
        must(g, def.id + ': edge ' + i + ' not drawn');
        const line = g.childOfName('line');
        const m = line.transform || I6;
        const q = line.pointAt(0.5);
        const gp = [m[0] * q[0] + m[2] * q[1] + m[4], m[1] * q[0] + m[3] * q[1] + m[5]];
        const p = aimIn(line, { x: gp[0] - 3, y: gp[1] - 3, width: 6, height: 6 }, 'edge');
        return { x: p[0], y: p[1], aim: 'edge s' + s + ' i' + i };
      }
      if (at.tnode) {
        const [s, i] = at.tnode;
        const g = series(s).getData().getItemGraphicEl(i);
        must(g, def.id + ': tree node ' + i + ' not drawn');
        const p = aimIn(g.childAt(0), globalRect(g.childAt(0)), 'tree node');
        return { x: p[0], y: p[1], aim: 'tree node s' + s + ' i' + i };
      }
      if (at.tm) {
        const [s, i, part] = at.tm;
        const view = chart.getViewOfSeriesModel(series(s));
        const d = series(s).getData();
        const el = view._storage[part === 'bg' ? 'background' : 'content'][d.getRawIndex(i)];
        must(el, def.id + ': treemap ' + part + ' ' + i + ' not drawn');
        const p = aimIn(el, globalRect(el), 'treemap ' + part);
        return { x: p[0], y: p[1], aim: 'treemap ' + part + ' s' + s + ' i' + i };
      }
      if (at.crumb) {
        const [s, k] = at.crumb;
        const view = chart.getViewOfSeriesModel(series(s));
        const el = view._breadcrumb.group.childAt(k);
        must(el, def.id + ': crumb ' + k + ' not drawn');
        const p = aimIn(el, globalRect(el), 'crumb');
        return { x: p[0], y: p[1], aim: 'crumb s' + s + ' k' + k };
      }
      if (at.item) {
        const [s, i] = at.item;
        const el = series(s).getData().getItemGraphicEl(i);
        must(el, def.id + ': item ' + i + ' not drawn');
        let r;
        if (el.type === 'sector') {
          const sh = el.shape;
          const a = (sh.startAngle + sh.endAngle) / 2;
          const rm = (sh.r0 + sh.r) / 2;
          r = { x: sh.cx + rm * Math.cos(a) - 2, y: sh.cy + rm * Math.sin(a) - 2, width: 4, height: 4 };
        } else r = globalRect(el);
        const p = aimIn(el, r, 'item');
        return { x: p[0], y: p[1], aim: 'item s' + s + ' i' + i };
      }
      if (at.xy) {
        return { x: at.xy[0], y: at.xy[1], aim: 'xy' };
      }
      if (at.crumbUnder) {
        // a point of a crumb's polygon where the hover is something else's
        const view = chart.getViewOfSeriesModel(series(at.crumbUnder[0]));
        const items = view._breadcrumb.group.childrenRef();
        for (let k = 0; k < items.length; k++) {
          const r = globalRect(items[k]);
          const cx = Math.round(r.x + r.width / 2);
          const cy = Math.round(r.y + r.height / 2);
          for (let d = 0; d <= Math.ceil(r.width / 2); d++) {
            for (const x of [cx - d, cx + d]) {
              const t = hd().findHover(x, cy).target;
              if (items[k].contain(x, cy) && t && !owns(items[k], t)) return { x, y: cy, aim: 'under crumb ' + k };
            }
          }
        }
        throw new OracleError(def.id + ': no crumb point is covered');
      }
      if (at.empty) {
        must(!hd().findHover(at.empty[0], at.empty[1]).target, def.id + ': the empty point hits an element');
        return { x: at.empty[0], y: at.empty[1], aim: 'empty' };
      }
      throw new OracleError(def.id + ': an unknown aim ' + JSON.stringify(at));
    };
    const hitAt = (x, y) => {
      const t = hd().findHover(x, y).target;
      if (!t) return { hd: null };
      let hdEl = null;
      for (let e = t; e; e = e.__hostTarget || e.parent) if (e.__highDownDispatcher) hdEl = e;
      if (!hdEl) return { hd: null };
      const ecd = ecDataOf(hdEl);
      // [R2-B] a dispatcher of no data (a legend item)
      if (!ecd) return { hd: { other: true } };
      if (ecd && ecd.eventData && ecd.eventData.selfType === 'breadcrumb') return { hd: { crumb: hdEl.parent.childrenRef().indexOf(hdEl) } };
      const o = { s: ecd.seriesIndex, i: ecd.dataIndex };
      if (ecd.dataType) o.dt = ecd.dataType;
      return { hd: o };
    };
    const steps = [{ type: 'init', events: [], state: snapshot(chart) }];
    for (const s0 of def.steps) {
      const st = { type: s0.type };
      events.length = 0;
      if (s0.type === 'action') {
        st.payload = clone(s0.payload);
        chart.dispatchAction(clone(s0.payload));
      } else if (s0.type === 'leave') {
        hd().mousemove(raw(-50, -50));
      } else {
        const r = resolve(s0.at);
        Object.assign(st, { x: r.x, y: r.y, aim: r.aim, hit: hitAt(r.x, r.y) });
        const h = hd();
        h.mousemove(raw(st.x, st.y));
        if (s0.type === 'click') {
          h.mousedown(raw(st.x, st.y));
          h.mouseup(raw(st.x, st.y));
          h.click(raw(st.x, st.y));
        }
      }
      frame(chart);
      st.events = events.splice(0);
      st.state = snapshot(chart);
      steps.push(st);
    }
    return { id: def.id, note: def.note, W, H, option, steps };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = [];
  for (const def of CASES) {
    if (process.env.ORACLE_ONLY && process.env.ORACLE_ONLY !== def.id) continue;
    cases.push(runCase(def));
  }
  return { source: 'ECharts ' + echarts.version, cases };
}

// ============================================================================
// Self-checks
// ============================================================================
// a tree node's parent (data index) from the case's option: the virtual root
// 0, then the written tree in pre-order
function treeParentOf(c, idx) {
  const ser = c.option.series.find(x => x.type === 'tree');
  const par = [-1];
  const walk = (nodes, p) => { for (const n of nodes) { par.push(p); const me = par.length - 1; if (n.children) walk(n.children, me); } };
  walk(ser.data, 0);
  return par[idx];
}

function checks(fx) {
  const fails = [];
  const fail = m => fails.push(m);
  const counts = {};
  const count = k => { counts[k] = (counts[k] || 0) + 1; };
  const lift = c => {
    const m = /^#([0-9a-f]{6})$/i.exec(c);
    if (!m) return null;
    const v = parseInt(m[1], 16);
    const ch = [(v >> 16) & 255, (v >> 8) & 255, v & 255].map(x => Math.min(255, x * 1.1 | 0));
    return 'rgba(' + ch.join(',') + ',1)';
  };
  const hexNum = p => (p == null ? null : Number(p[1]));
  for (const c of fx.cases) {
    c.steps.forEach((step, k) => {
      const where = c.id + ' step ' + k;
      for (const s of step.state.series) {
        if (s.type === 'graph') {
          s.nodes.forEach((n, i) => {
            if (!n) return;
            // R1
            if (n.label && n.label.st !== n.path.st) fail(where + ': graph node ' + i + ' label list ' + n.label.st + ' vs ' + n.path.st);
            // R2
            if (n.path.st === 'emphasis' && /^rgba/.test(n.path.fill || '') && lift(n.path.rest.fill) !== n.path.fill) fail(where + ': graph node ' + i + ' lift is not liftColor of its rest fill');
            if (/emphasis/.test(n.path.st) && /^rgba/.test(n.path.fill || '') && lift(n.path.rest.fill) === n.path.fill) count('graph lift');
            if (n.path.st === 'blur') count('graph node blurred');
            if (/emphasis/.test(n.path.st)) count('graph node emphasis');
            if (/select/.test(n.path.st)) count('graph node selected');
            if (n.hbo) count('graph hbo');
          });
          s.edges.forEach((e, i) => {
            if (!e) return;
            if (e.label && e.label.st !== e.line.st) fail(where + ': graph edge ' + i + ' label list');
            if (/select/.test(e.line.st)) count('graph edge selected');
            if (/emphasis/.test(e.line.st)) count('graph edge emphasis');
            for (const a of e.arrows) if (a && a.st !== e.line.st) fail(where + ': arrow list differs from its line');
          });
          if (s.selectedMap && Object.keys(s.selectedMap).some(key => / > /.test(key))) {
            count('graph edge key in map');
            // R5: an edge's key in the map came with an edge selected now or before
            if (!c.steps.slice(0, k + 1).some(stp => stp.state.series.some(x => x.edges && x.edges.some(e => e && /select/.test(e.line.st))))) fail(where + ': an edge key with no edge selected');
          }
        } else if (s.type === 'tree') {
          s.nodes.forEach((n, i) => {
            if (!n) return;
            if (n.label && n.label.st !== n.path.st) fail(where + ': tree node ' + i + ' label list');
            if (n.edge && n.edge.hs !== n.hs) {
              count('tree edge apart');
              // R3: the node blurred, or the parent's symbol blurred
              const par = s.nodes.findIndex((m, j) => m && j < i && treeParentOf(c, i) === j);
              const parHs = par >= 0 ? s.nodes[par].hs : 0;
              if (n.hs !== 1 && parHs !== 1 && n.edge.hs !== 1) fail(where + ': tree node ' + i + ' edge apart with no blurred parent');
            }
            if (n.path.st === 'blur') count('tree node blurred');
            if (/select/.test(n.path.st)) count('tree selected');
          });
        } else if (s.type === 'treemap') {
          s.nodes.forEach((n, i) => {
            if (!n) return;
            // R5
            if (n.bg && n.content && n.bg.st !== n.content.st) fail(where + ': treemap leaf ' + i + ' bg / content lists differ');
            for (const r of [n.bg, n.content]) {
              if (!r) continue;
              if (r.label && r.label.st !== r.st) fail(where + ': treemap ' + i + ' label list');
              if (r.st === 'blur' && r.px) count('treemap blurred');
              if (/emphasis/.test(r.st)) count('treemap emphasis');
              if (/select/.test(r.st)) count('treemap selected');
            }
            if (n.bg && n.bg.label && hexNum(n.bg.label.rest.opacity) !== 1) count('treemap upper label opacity');
            if (n.content && n.content.label && hexNum(n.content.label.rest.opacity) !== 1) count('treemap label opacity');
          });
          s.crumbs.forEach(cr => { if (/emphasis/.test(cr.st)) count('crumb emphasis'); });
        } else {
          s.items.forEach(it => { if (it && it.st === 'blur') count('other blurred by hier'); });
        }
      }
      for (const ev of step.events) if (ev.payload && ev.payload.selfType === 'breadcrumb') count('crumb event');
      if (step.type === 'click' && step.events.some(ev => /^treemap/.test(ev.type))) count('crumb action');
    });
  }
  const want = ['graph lift', 'graph node blurred', 'graph node emphasis', 'graph node selected', 'graph hbo', 'graph edge selected',
    'graph edge emphasis', 'graph edge key in map', 'tree edge apart', 'tree node blurred', 'tree selected', 'treemap blurred',
    'treemap emphasis', 'treemap selected', 'treemap upper label opacity', 'treemap label opacity', 'crumb emphasis', 'crumb event', 'crumb action',
    'other blurred by hier'];
  for (const k of want) if (!(counts[k] >= 1)) fail('discriminating count ' + k + ' is ' + (counts[k] || 0));
  return { fails, counts };
}

// ============================================================================
function main() {
  let fx1;
  try {
    fx1 = generate();
  } catch (e) {
    if (e instanceof OracleError) { console.log('FAILED: ' + e.message); process.exit(1); }
    throw e;
  }
  const json1 = JSON.stringify(fx1, null, 1);
  if (process.env.ORACLE_PROBE) {
    console.log(json1);
    process.exit(0);
  }
  const chk = checks(fx1);
  const json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1);
  if (chk.fails.length) {
    console.log('FAILED self-checks:\n  ' + chk.fails.slice(0, 40).join('\n  '));
    process.exit(1);
  }
  if (json1 !== json2) {
    console.log('FAILED: two generations differ');
    process.exit(1);
  }
  fs.writeFileSync(OUT, json1 + '\n');
  console.log('wrote ' + OUT + ': ' + fx1.cases.length + ' cases, ' + fx1.cases.reduce((a, c) => a + c.steps.length, 0) + ' steps; counts ' + JSON.stringify(chk.counts));
  process.exit(0);
}
main();
