/*
Upstream's own answers for fix batch R5-F (spec section 243): the author's
font on the labels a series places itself, at rest and in the emphasis
state.

  - A pie's and a funnel's label take label.fontSize / fontWeight like any
    label: PieView and FunnelView style the text through setLabelStyle ->
    createTextStyle on the label model (the item's over the series' over the
    root textStyle); pie/labelLayout.ts and funnelLayout measure the label
    with that font, so the places and the boxes follow it.
  - The emphasis state's label style is createTextStyle of emphasis.label
    (the item's over the series'), only the keys written: zrender's Text
    merges it over the normal style when the state is entered, so a written
    fontSize / fontWeight / rich lays the hovered text out again in that
    font -- the gallery's doughnut, whose hidden centre label shows at 40px
    bold on hover. x / y and the alignment stay where the layout put them.
  - A data item's own emphasis.label.rich cascades over the series' (the
    item's emphasis model).

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off; chart._ssr = false before setOption and chart._onframe()
after every step, the browser's model, so the states apply). Every label of series 0 is read off the live elements after
a render; a case with `hl` then dispatches highlight {seriesIndex: 0,
dataIndex: hl}, renders again and reads them again.

  node tools/advchart-oracle/label-font-states.js

writes tests/fixtures/advchart-label-font-states.json (ORACLE_OUT
overrides); generated twice in the process, byte-identical; ends with
process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option, hl (null | the highlighted data index),
        labels[], labelsHl[] (when hl):
          {d, ignore, text, x, y (hex: the computed transform's translation),
           align, verticalAlign, rect ([4 hex]: the global bounding rect),
           fontSize (hex | null) and fontWeight (string | null) of the style
           as it stands, runs [{text, font}]: the painted spans in order,
           each with zrender's font string}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-font-states.json');
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
const DATA = () => [
  { value: 1548, name: 'CityE' }, { value: 735, name: 'CityC' }, { value: 510, name: 'CityD' },
  { value: 434, name: 'CityB' }, { value: 335, name: 'CityA' }];
function withItem(i, extra) {
  const d = DATA();
  d[i] = Object.assign(d[i], extra);
  return d;
}
function pie(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    series: [Object.assign({ type: 'pie', radius: '50%', data: DATA() }, series)] }, root || {});
}
function funnel(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    series: [Object.assign({ type: 'funnel', left: '10%', width: '60%', data: [
      { value: 60, name: 'Visit' }, { value: 40, name: 'Inquiry' }, { value: 20, name: 'Order' },
      { value: 80, name: 'Click' }, { value: 100, name: 'Show' }] }, series)] }, root || {});
}
function bar(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: {},
    series: [Object.assign({ type: 'bar', data: [12, 30, 18, 25], label: { show: true, position: 'top' } }, series)] }, root || {});
}

const CASES = [
  // ---- a pie's own font ----
  { id: 'pie.font', note: 'series label fontSize 20 and bold: the outer labels measured and placed in that font',
    option: pie({ label: { fontSize: 20, fontWeight: 'bold' } }) },
  { id: 'pie.font.item', note: 'one item fontSize 24, another fontWeight 600, the rest the default',
    option: pie({ data: (() => { const d = DATA(); d[1].label = { fontSize: 24 }; d[3].label = { fontWeight: 600 }; return d; })() }) },
  { id: 'pie.font.inside', note: 'inside labels at fontSize 16',
    option: pie({ label: { position: 'inside', fontSize: 16 } }) },
  { id: 'pie.font.root', note: "the root textStyle's fontSize 15 under no label font",
    option: pie({}, { textStyle: { fontSize: 15 } }) },
  { id: 'pie.font.over.root', note: 'the root textStyle bold, the label fontSize 18 over it',
    option: pie({ label: { fontSize: 18 } }, { textStyle: { fontWeight: 'bold' } }) },
  // ---- the hover ----
  { id: 'pie.doughnut', note: "the gallery's doughnut: the centre label hidden, shown at 40px bold on hover",
    option: pie({ radius: ['40%', '70%'], avoidLabelOverlap: false, label: { show: false, position: 'center' },
      emphasis: { label: { show: true, fontSize: 40, fontWeight: 'bold' } }, labelLine: { show: false } }), hl: 1 },
  { id: 'pie.emph.outer', note: 'outer labels; emphasis.label fontSize 18: the hovered one larger, where the layout put it',
    option: pie({ emphasis: { label: { fontSize: 18 } } }), hl: 0 },
  { id: 'pie.emph.item', note: "an item's own emphasis.label fontSize 22 and colour",
    option: pie({ data: withItem(2, { emphasis: { label: { fontSize: 22, color: '#ff0000' } } }) }), hl: 2 },
  { id: 'pie.emph.item.rich', note: "an item's emphasis.label.rich over the series' rich",
    option: pie({ label: { formatter: '{a|{b}} {c|{c}}', rich: { a: { color: '#333333', fontSize: 12 }, c: { color: '#999999' } } },
      data: withItem(1, { emphasis: { label: { rich: { a: { fontSize: 20, fontWeight: 'bold' } } } } }) }), hl: 1 },
  // ---- a funnel's ----
  { id: 'funnel.font', note: 'inside funnel labels at fontSize 16 bold',
    option: funnel({ label: { fontSize: 16, fontWeight: 'bold' } }) },
  { id: 'funnel.font.outer', note: 'funnel labels on the right at fontSize 14 under a root weight 600',
    option: funnel({ label: { position: 'right', fontSize: 14 } }, { textStyle: { fontWeight: 600 } }) },
  { id: 'funnel.emph', note: "the gallery's funnel: emphasis.label fontSize 20 on the hovered layer",
    option: funnel({ label: { show: true, position: 'inside' }, emphasis: { label: { fontSize: 20 } } }), hl: 2 },
  // ---- a bar's (series labels the label manager places) ----
  { id: 'bar.emph.font', note: 'bar labels on top; emphasis.label fontSize 20 bold on the hovered bar',
    option: bar({ emphasis: { label: { fontSize: 20, fontWeight: 'bold' } } }), hl: 1 },
  { id: 'bar.emph.item.rich', note: "a bar item's own emphasis.label.rich (the series' rich under it)",
    option: bar({ label: { show: true, position: 'top', formatter: '{a|{c}}', rich: { a: { color: '#333333' } } },
      data: [12, { value: 30, emphasis: { label: { rich: { a: { fontSize: 18, color: '#ff0000' } } } } }, 18, 25] }), hl: 1 },
  // ---- a label the label layout re-aligned and re-sized, then hovered ----
  { id: 'bar.layout.emph', note: 'labelLayout align left and fontSize 16; emphasis.label bold: the hovered text bold at 16, aligned left',
    option: bar({ labelLayout: { align: 'left', fontSize: 16 }, emphasis: { label: { fontWeight: 'bold' } } }), hl: 2 },
  { id: 'bar.layout.emph.size', note: 'labelLayout fontSize 16; emphasis.label fontSize 22 over it',
    option: bar({ labelLayout: { fontSize: 16 }, emphasis: { label: { fontSize: 22 } } }), hl: 0 },
  // ---- [R5-L] a label only the emphasis writes: the series has no label (no
  // position: the emphasis state's textConfig is a known difference) ----
  { id: 'bar.emph.only', note: 'no series label; emphasis.label shows it (inside, the default) at fontSize 20 bold',
    option: bar({ label: undefined, emphasis: { label: { show: true, fontSize: 20, fontWeight: 'bold' } } }), hl: 1 },
  { id: 'scatter.emph.only', note: 'a scatter with no label; emphasis.label shows it at fontSize 15 (backward-compat scatter-alias, modern spelling)',
    option: { animation: false, color: PALETTE, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'scatter', symbolSize: 20, data: [[1, 1], [2, 3], [3, 2]],
        emphasis: { scale: false, label: { show: true, color: '#ff0000', fontSize: 15 } } }] }, hl: 1 },
];

function runsOf(t) {
  const out = [];
  (t.childrenRef ? t.childrenRef() : []).forEach(k => {
    if (k.type === 'tspan') out.push({ text: String(k.style.text), font: String(k.style.font) });
  });
  return out;
}

function readLabels(chart) {
  const sm = chart.getModel().getSeriesByIndex(0);
  const data = sm.getData();
  const labels = [];
  data.each(idx => {
    const el = data.getItemGraphicEl(idx);
    if (!el) return;
    let t = el.getTextContent();
    // a scatter's symbol is a group: the label hangs off its path [R5-L]
    if (!t && el.childAt && el.childAt(0) && el.childAt(0).getTextContent) t = el.childAt(0).getTextContent();
    if (!t) return;
    const m = t.getComputedTransform();
    const ds = t._defaultStyle || {};
    const r = t.getBoundingRect().clone();
    if (m) r.applyTransform(m);
    labels.push({
      d: idx,
      ignore: !!t.ignore,
      text: t.style.text == null ? '' : String(t.style.text),
      x: hex(m ? m[4] : t.x), y: hex(m ? m[5] : t.y),
      align: t.style.align || ds.align || 'left',
      verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
      rect: [r.x, r.y, r.width, r.height].map(hex),
      fontSize: t.style.fontSize == null ? null : hex(+t.style.fontSize),
      fontWeight: t.style.fontWeight == null ? null : String(t.style.fontWeight),
      runs: runsOf(t),
    });
  });
  return labels;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  // the browser's model (select-legend.js): states apply on a frame
  chart._ssr = false;
  try {
    chart.setOption(clone(c.option));
    chart._onframe();
    chart.renderToSVGString();
    const rec = { id: c.id, note: c.note, option: clone(c.option), hl: c.hl == null ? null : c.hl, labels: readLabels(chart) };
    if (c.hl != null) {
      chart.dispatchAction({ type: 'highlight', seriesIndex: 0, dataIndex: c.hl });
      chart._onframe();
      chart.renderToSVGString();
      rec.labelsHl = readLabels(chart);
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const lab = (id, d, hl) => (hl ? by(id).labelsHl : by(id).labels).find(l => l.d === d);
  const font = (id, d, hl) => lab(id, d, hl).runs.map(r => r.font).join('|');
  const guards = [
    { name: 'pie.font: the labels in 20px bold', ok: by('pie.font').labels.every(l => /bold 20px/.test(l.runs[0].font)) },
    { name: 'pie.font.item: item 1 at 24px, item 3 weight 600, item 0 at 12px',
      ok: /24px/.test(font('pie.font.item', 1)) && /600/.test(font('pie.font.item', 3)) && /12px/.test(font('pie.font.item', 0)) },
    { name: 'pie.font.root: 15px', ok: /15px/.test(font('pie.font.root', 0)) },
    { name: 'pie.doughnut: hidden at rest, shown at 40px bold when hovered',
      ok: lab('pie.doughnut', 1).ignore && !lab('pie.doughnut', 1, true).ignore && /bold 40px/.test(font('pie.doughnut', 1, true)) },
    { name: 'pie.doughnut: the hovered label stays at the centre', ok: lab('pie.doughnut', 1, true).x === hex(300) && lab('pie.doughnut', 1, true).y === hex(200) },
    { name: 'pie.emph.outer: the hovered label is wider, the others as they were',
      ok: lab('pie.emph.outer', 0, true).rect[2] !== lab('pie.emph.outer', 0).rect[2] && lab('pie.emph.outer', 1, true).rect[2] === lab('pie.emph.outer', 1).rect[2] },
    { name: 'pie.emph.outer: the anchor is the layout\'s', ok: lab('pie.emph.outer', 0, true).x === lab('pie.emph.outer', 0).x },
    { name: 'pie.emph.item.rich: the item\'s token at 20px bold when hovered', ok: /bold 20px/.test(font('pie.emph.item.rich', 1, true)) },
    { name: 'funnel.font: 16px bold', ok: /bold 16px/.test(font('funnel.font', 0)) },
    { name: 'funnel.emph: the hovered layer at 20px', ok: /20px/.test(font('funnel.emph', 2, true)) && /12px/.test(font('funnel.emph', 2)) },
    { name: 'bar.emph.font: bold 20px when hovered', ok: /bold 20px/.test(font('bar.emph.font', 1, true)) },
    { name: 'bar.emph.item.rich: the item\'s token at 18px when hovered', ok: /18px/.test(font('bar.emph.item.rich', 1, true)) },
    { name: 'bar.layout.emph: bold 16px, aligned left, when hovered', ok: /bold 16px/.test(font('bar.layout.emph', 2, true)) && lab('bar.layout.emph', 2, true).align === 'left' },
    { name: 'bar.layout.emph.size: 22px over the layout\'s 16', ok: /22px/.test(font('bar.layout.emph.size', 0, true)) && /16px/.test(font('bar.layout.emph.size', 0)) },
    { name: 'bar.emph.only: hidden at rest, bold 20px when hovered',
      ok: lab('bar.emph.only', 1).ignore && /bold 20px/.test(font('bar.emph.only', 1, true)) },
    { name: 'scatter.emph.only: 15px when hovered', ok: /15px/.test(font('scatter.emph.only', 1, true)) },
  ];
  if (!process.env.ORACLE_NOGUARD) for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: chart/pie/PieView.ts, pie/labelLayout.ts, chart/funnel, label/labelStyle.ts, zrender Text states',
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
