/*
Upstream's own answers for fix batch R6-A (spec section 248): a series
label's STATE textConfig -- emphasis.label / select.label / blur.label
`position`, `distance`, `offset` and `rotate`, the series' and a data
item's.

  - setLabelStyle (label/labelStyle.ts) gives the host element, for every
    special state, `states[state].textConfig = createTextConfig(stateModel,
    opt, true)`: only the keys the state's label model (the item's
    [state].label over the series') writes -- position when truthy
    ('outside' is the host's defaultOutsidePosition), distance, offset,
    rotate (in radians) -- plus outsideFill.
  - zrender's Element._applyStateObj sets the host's textConfig to the
    normal one extended by the merged states' (select first, then emphasis
    or blur: echarts.ts applyElementStates) AT ONCE (no transition), and
    updateInnerText lays the label out by it on the host's rect: the anchor,
    the alignment the position implies, the turn, the offset inside the
    turn, and the inside / outside ink (`position` containing 'inside').
  - The normal textConfig is the one LabelManager left: its position and
    rotation as the series wrote them and its offset [dx || 0, dy || 0]
    (updateLayoutConfig) -- the normal label.offset is dropped.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off unless the case says; chart._ssr = false before setOption and
chart._onframe() after every step, the browser's model, so the states
apply). Every label of series 0 is read off the live elements after the
render and after every step.

  node tools/advchart-oracle/label-state-textconfig.js

writes tests/fixtures/advchart-label-state-textconfig.json (ORACLE_OUT
overrides); generated twice in the process, byte-identical; ends with
process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option, steps[] (dispatchAction payloads), states[]:
        the labels at rest, then after each step:
          {d, ignore, text, x, y (hex: the computed transform's
           translation), m ([4 hex]: its linear part), align, verticalAlign
           (the style's, else the host's default), rect ([4 hex]: the global
           bounding rect), fill (the ink painted, the first span's), inside
           (updateInnerText's isInside on the host's textConfig), fontSize}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-state-textconfig.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const clone = o => JSON.parse(JSON.stringify(o));

const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const HL = d => ({ type: 'highlight', seriesIndex: 0, dataIndex: d });
const DP = d => ({ type: 'downplay', seriesIndex: 0, dataIndex: d });
const SEL = d => ({ type: 'select', seriesIndex: 0, dataIndex: d });

function bar(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: {},
    series: [Object.assign({ type: 'bar', data: [12, 30, 18, 25], label: { show: true, position: 'top' } }, series)] }, root || {});
}
function scatter(series, root) {
  return Object.assign({ animation: false, color: PALETTE, xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [Object.assign({ type: 'scatter', symbolSize: 20, data: [[1, 1], [2, 3], [3, 2]] }, series)] }, root || {});
}
function line(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: {},
    series: [Object.assign({ type: 'line', data: [12, 30, 18, 25], label: { show: true } }, series)] }, root || {});
}

const CASES = [
  // ---- the R5-L leftover: scatter-alias, modern spelling ----
  { id: 'scatter.alias', note: "backward-compat scatter-alias: no series label; emphasis.label shows it on the right at 15px",
    option: scatter({ itemStyle: { opacity: 0.5, color: '#3366cc' },
      emphasis: { scale: false, itemStyle: { opacity: 1, borderColor: '#000', borderWidth: 2 },
        label: { show: true, position: 'right', color: '#ff0000', fontSize: 15 } } }), steps: [HL(1)] },
  { id: 'scatter.top.bottom', note: 'labels on top; emphasis.label position bottom, distance 12',
    option: scatter({ label: { show: true, position: 'top' },
      emphasis: { scale: false, label: { position: 'bottom', distance: 12 } } }), steps: [HL(2)] },
  { id: 'scatter.scaled', note: 'emphasis scale (the default 1.1? no: symbolSize 20 scales); label right in emphasis, inside at rest',
    option: scatter({ label: { show: true, formatter: 'p{@[1]}' },
      emphasis: { label: { position: 'right' } } }), steps: [HL(0)] },
  // ---- a bar's ----
  { id: 'bar.insideTop', note: 'labels on top; emphasis.label position insideTop: inside ink on the hovered bar',
    option: bar({ emphasis: { label: { position: 'insideTop' } } }), steps: [HL(1)] },
  { id: 'bar.offset.rotate', note: 'emphasis.label offset [10, -5] and rotate 30 over the top position; label.offset [4, 4] at rest',
    option: bar({ label: { show: true, position: 'top', offset: [4, 4] }, emphasis: { label: { offset: [10, -5], rotate: 30 } } }), steps: [HL(2)] },
  { id: 'bar.distance', note: 'emphasis.label distance 20 alone (position top kept)',
    option: bar({ emphasis: { label: { distance: 20 } } }), steps: [HL(0)] },
  { id: 'bar.item', note: "an item's own emphasis.label position right over the series' emphasis position bottom",
    option: bar({ emphasis: { label: { position: 'bottom' } },
      data: [12, { value: 30, emphasis: { label: { position: 'right' } } }, 18, 25] }), steps: [HL(1), DP(1), HL(0)] },
  { id: 'bar.outside.neg', note: "emphasis.label position 'outside' on a negative bar: below it; labels inside at rest",
    option: bar({ data: [12, -30, 18, -25], label: { show: true, position: 'inside' }, emphasis: { label: { position: 'outside' } } }), steps: [HL(1)] },
  { id: 'bar.array', note: 'emphasis.label position [10, "50%"]',
    option: bar({ emphasis: { label: { position: [10, '50%'] } } }), steps: [HL(3)] },
  { id: 'bar.rich', note: 'a rich label; emphasis.label position insideBottom',
    option: bar({ label: { show: true, position: 'top', formatter: '{a|{c}}', rich: { a: { color: '#333333', padding: [2, 4] } } },
      emphasis: { label: { position: 'insideBottom' } } }), steps: [HL(2)] },
  // ---- the other states ----
  { id: 'bar.select', note: 'select.label position bottom (selectedMode single)',
    option: bar({ selectedMode: 'single', select: { label: { position: 'insideBottom' } } }), steps: [SEL(1)] },
  { id: 'bar.select.emph', note: 'select.label position bottom, emphasis.label distance 15: selected then hovered, the two merged',
    option: bar({ selectedMode: 'single', select: { label: { position: 'bottom' } }, emphasis: { label: { distance: 15 } } }),
    steps: [SEL(1), HL(1), DP(1)] },
  { id: 'bar.blur', note: "emphasis focus self: the others blur, blur.label position insideTop",
    option: bar({ emphasis: { focus: 'self' }, blur: { label: { position: 'insideTop' } } }), steps: [HL(0)] },
  // ---- the other series that lay their labels out on a host ----
  { id: 'pie.outer', note: 'pie outer labels; emphasis.label position inside',
    option: { animation: false, color: PALETTE, series: [{ type: 'pie', radius: '50%', data: [
      { value: 1548, name: 'CityE' }, { value: 735, name: 'CityC' }, { value: 510, name: 'CityD' }, { value: 434, name: 'CityB' }, { value: 335, name: 'CityA' }],
      emphasis: { label: { position: 'inside' } } }] }, steps: [HL(1)] },
  { id: 'pie.inner', note: 'pie inside labels; emphasis.label position top, rotate 20, offset [5, 5]',
    option: { animation: false, color: PALETTE, series: [{ type: 'pie', radius: '50%', label: { position: 'inside' }, data: [
      { value: 1548, name: 'CityE' }, { value: 735, name: 'CityC' }, { value: 510, name: 'CityD' }, { value: 434, name: 'CityB' }, { value: 335, name: 'CityA' }],
      emphasis: { label: { position: 'top', rotate: 20, offset: [5, 5] } } }] }, steps: [HL(0)] },
  { id: 'funnel.none', note: 'funnel: the label is a ZRText of its own (setLabelStyle on it): no state textConfig, emphasis.label position left changes nothing',
    option: { animation: false, color: PALETTE, series: [{ type: 'funnel', data: [
      { value: 60, name: 'Visit' }, { value: 40, name: 'Inquiry' }, { value: 20, name: 'Order' }],
      emphasis: { label: { position: 'left' } } }] }, steps: [HL(1)] },
  { id: 'heatmap', note: 'heatmap; emphasis.label position top',
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['x', 'y'] },
      visualMap: { show: false, min: 0, max: 10 },
      series: [{ type: 'heatmap', data: [[0, 0, 1], [0, 1, 5], [1, 0, 7], [1, 1, 9]], label: { show: true },
        emphasis: { label: { position: 'top' } } }] }, steps: [HL(2)] },
  { id: 'radar', note: 'radar point labels; emphasis.label position right',
    option: { animation: false, radar: { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }] },
      series: [{ type: 'radar', label: { show: true }, emphasis: { label: { position: 'right' } }, data: [{ value: [5, 7, 3] }] }] }, steps: [HL(0)] },
  { id: 'graph', note: 'graph none layout; labels right; emphasis.label position top',
    option: { animation: false, series: [{ type: 'graph', layout: 'none', symbolSize: 20, label: { show: true, position: 'right' },
      emphasis: { scale: false, label: { position: 'top' } },
      data: [{ name: 'n0', x: 100, y: 100 }, { name: 'n1', x: 300, y: 100 }, { name: 'n2', x: 200, y: 300 }], links: [{ source: 'n0', target: 'n1' }] }] }, steps: [HL(1)] },
  { id: 'tree', note: 'tree; emphasis.label position top',
    option: { animation: false, series: [{ type: 'tree', data: [{ name: 'root', children: [{ name: 'a' }, { name: 'b' }] }],
      emphasis: { label: { position: 'top' } } }] }, steps: [HL(1)] },
  { id: 'sankey', note: 'sankey; emphasis.label position left',
    option: { animation: false, series: [{ type: 'sankey', data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
      links: [{ source: 'a', target: 'b', value: 5 }, { source: 'a', target: 'c', value: 3 }],
      emphasis: { label: { position: 'left' } } }] }, steps: [HL(1)] },
  { id: 'river', note: 'themeRiver; emphasis.label position top',
    option: { animation: false, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', label: { fontSize: 12 }, emphasis: { label: { position: 'top' } },
      data: [['2015/11/08', 10, 'A'], ['2015/11/09', 15, 'A'], ['2015/11/08', 5, 'B'], ['2015/11/09', 8, 'B']] }] }, steps: [HL(0)] },
  { id: 'treemap', note: 'treemap; emphasis.label position insideBottomRight',
    option: { animation: false, series: [{ type: 'treemap', data: [{ name: 'a', value: 6 }, { name: 'b', value: 4 }],
      emphasis: { label: { position: 'insideBottomRight' } } }] }, steps: [HL(1)] },
  { id: 'pictorial', note: 'pictorialBar labels top; emphasis.label position insideBottom',
    option: { animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {},
      series: [{ type: 'pictorialBar', symbol: 'rect', data: [10, 20], label: { show: true, position: 'top' },
        emphasis: { label: { position: 'insideBottom' } } }] }, steps: [HL(1)] },
  { id: 'effect', note: 'effectScatter labels top; emphasis.label position bottom',
    option: { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'effectScatter', symbolSize: 20, data: [[1, 1], [2, 3]], label: { show: true, position: 'top' },
        emphasis: { scale: false, label: { position: 'bottom' } } }] }, steps: [HL(1)] },
  { id: 'polar', note: "polar bar labels middle (textConfig.inside); emphasis.label position end: the sector's own position, still inside",
    option: { animation: false, color: PALETTE, polar: {}, angleAxis: { type: 'category', data: ['a', 'b', 'c'] }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [3, 5, 4], label: { show: true, position: 'middle' },
        emphasis: { label: { position: 'end' } } }] }, steps: [HL(1)] },
  { id: 'bar.layout.dy', note: 'labelLayout dy -10; emphasis.label position bottom',
    option: bar({ labelLayout: { dy: -10 }, emphasis: { label: { position: 'bottom' } } }), steps: [HL(1)] },
  { id: 'bar.layout.hide', note: 'labelLayout hideOverlap; emphasis.label position bottom',
    option: bar({ labelLayout: { hideOverlap: true }, emphasis: { label: { position: 'bottom' } } }), steps: [HL(1)] },
  { id: 'bar.select.stroke', note: 'labels top; select border only: the label moves with the border',
    option: bar({ selectedMode: 'single' }), steps: [SEL(1)] },
  // ---- a line's symbols ----
  { id: 'line.right', note: 'line labels on top; emphasis.label position right, rotate -20',
    option: line({ emphasis: { scale: false, label: { position: 'right', rotate: -20 } } }), steps: [HL(1)] },
];

function runsOf(t) {
  const out = [];
  (t.childrenRef ? t.childrenRef() : []).forEach(k => {
    if (k.type === 'tspan') out.push(k);
  });
  return out;
}

function labelOf(el) {
  if (!el) return null;
  let t = el.getTextContent && el.getTextContent();
  if (t) return t;
  // a group (a symbol's, a pictorial bar's, a radar item's): the first
  // element under it that carries a text
  let found = null;
  if (el.traverse) el.traverse(k => { if (!found && k !== el && k.getTextContent && k.getTextContent()) found = k.getTextContent(); });
  return found;
}

// updateInnerText's isInside: textConfig.inside, else a position naming 'inside'
function insideOf(t) {
  const host = t.__hostTarget;
  const tc = (host && host.textConfig) || {};
  return tc.inside == null ? (typeof tc.position === 'string' && tc.position.indexOf('inside') >= 0) : !!tc.inside;
}

function readLabels(chart) {
  const sm = chart.getModel().getSeriesByIndex(0);
  const data = sm.getData();
  const labels = [];
  data.each(idx => {
    const t = labelOf(data.getItemGraphicEl(idx));
    if (!t) return;
    const m = t.getComputedTransform();
    const ds = t._defaultStyle || {};
    const r = t.getBoundingRect().clone();
    if (m) r.applyTransform(m);
    const runs = runsOf(t);
    labels.push({
      d: idx,
      ignore: !!t.ignore,
      text: t.style.text == null ? '' : String(t.style.text),
      x: hex(m ? m[4] : t.x), y: hex(m ? m[5] : t.y),
      m: (m ? [m[0], m[1], m[2], m[3]] : [1, 0, 0, 1]).map(hex),
      align: t.style.align || ds.align || 'left',
      verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
      rect: [r.x, r.y, r.width, r.height].map(hex),
      fill: runs.length ? String(runs[0].style.fill) : String(t.style.fill || ds.fill),
      inside: insideOf(t),
      fontSize: t.style.fontSize == null ? null : hex(+t.style.fontSize),
    });
  });
  return labels;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(clone(c.option));
    chart._onframe();
    chart.renderToSVGString();
    const rec = { id: c.id, note: c.note, option: clone(c.option), steps: clone(c.steps || []), states: [readLabels(chart)] };
    for (const s of (c.steps || [])) {
      chart.dispatchAction(clone(s));
      chart._onframe();
      chart.renderToSVGString();
      rec.states.push(readLabels(chart));
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const lab = (id, st, d) => by(id).states[st].find(l => l.d === d);
  const X = (id, st, d) => { bits.setBigUint64(0, BigInt('0x' + lab(id, st, d).x)); return bits.getFloat64(0); };
  const Y = (id, st, d) => { bits.setBigUint64(0, BigInt('0x' + lab(id, st, d).y)); return bits.getFloat64(0); };
  const guards = [
    { name: 'scatter.alias: hovered, the label is right of the symbol and its emphasis border (x 406)', ok: X('scatter.alias', 1, 1) === 406 },
    { name: 'scatter.top.bottom: hovered, the label is below the symbol at distance 12', ok: Y('scatter.top.bottom', 1, 2) === 150 + 10 + 12 },
    { name: 'scatter.scaled: hovered, right of the symbol scaled 1.1 (240 + 11 + 5)', ok: X('scatter.scaled', 1, 0) === 256 },
    { name: 'bar.insideTop: hovered, inside and inked for it', ok: lab('bar.insideTop', 1, 1).inside && lab('bar.insideTop', 1, 1).fill === '#eee' },
    { name: "bar.item: the item's position over the series', the series' on another bar, back at rest after downplay",
      ok: lab('bar.item', 1, 1).align === 'left' && lab('bar.item', 2, 1).y === lab('bar.item', 0, 1).y && lab('bar.item', 3, 0).verticalAlign === 'top' },
    { name: "bar.select.emph: select then hover, the distances merge over select's position", ok: Y('bar.select.emph', 2, 1) - Y('bar.select.emph', 1, 1) === 10 },
    { name: 'bar.blur: the blurred labels take blur.label.position', ok: [1, 2, 3].every(d => lab('bar.blur', 1, d).inside) && !lab('bar.blur', 1, 0).inside },
    { name: 'funnel.none: nothing moves', ok: JSON.stringify(by('funnel.none').states[0]) === JSON.stringify(by('funnel.none').states[1]) },
    { name: "pie.outer: hovered, the label at the hovered slice's rect centre, the layout's alignment kept",
      ok: lab('pie.outer', 1, 1).x !== lab('pie.outer', 0, 1).x && lab('pie.outer', 1, 1).align === lab('pie.outer', 0, 1).align },
    { name: "bar.select.stroke: the selected bar's border lifts its label by one", ok: Y('bar.select.stroke', 0, 1) - Y('bar.select.stroke', 1, 1) === 1 },
    { name: 'polar: hovered, still inside (#eee)', ok: lab('polar', 1, 1).inside && lab('polar', 1, 1).fill === '#eee' },
  ];
  if (!process.env.ORACLE_NOGUARD) for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: label/labelStyle.ts createTextConfig, zrender Element._applyStateObj / updateInnerText, label/LabelManager.ts',
    W, H, cases, guards: guards.map(g => g.name) };
}

let code = 0;
try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  console.log('wrote ' + OUT);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  code = 1;
}
process.exit(code);
