/*
Upstream's own answers for fix batch R5-F (spec section 243): what a legend
item reads of its own beyond its colours (LegendView._createItem, the item
model's parent the legend model):

  - symbolRotate ('inherit' by default): getDefaultLegendIcon turns the
    icon only when the icon word is 'inherit' and the series has a symbol
    visual (its symbolRotate visual then, or the number written); a line's
    own icon (LineSeries.getLegendIcon) turns its marker by the series'
    symbolRotate under 'inherit', else by the number -- about the box's
    centre (setOrigin [itemWidth / 2, itemHeight / 2]);
  - symbolKeepAspect: the item's over the legend's (createSymbol's
    keepAspect for a path or an image icon);
  - textStyle: createTextStyle of the item's textStyle model -- its rich
    styles (each name the item's over the legend's), its box -- the item's
    group bounding rect, which the box layout lays out and the hit rect
    covers, growing with it.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off). For legend 0 every item group is read: its icon's paths
(each with its rotation and global bounding rect), the text's painted spans
(text, font, fill) and its global rect, and the hit rect (the group's
bounding rect, global).

  node tools/advchart-oracle/legend-item-own.js

writes tests/fixtures/advchart-legend-item-own.json (ORACLE_OUT overrides);
generated twice in the process, byte-identical; ends with process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option,
        items[] {name, hit [4 hex], icons [{rotation (hex), rect [4 hex]}],
                 text {rect [4 hex], runs [{text, font, fill}]}}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-legend-item-own.json');
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
const cats = ['a', 'b', 'c', 'd'];
function chart(series, legend) {
  return { animation: false, color: PALETTE, legend: Object.assign({ top: 10 }, legend || {}),
    xAxis: { type: 'category', data: cats }, yAxis: {}, series };
}
const L = (name, extra) => Object.assign({ type: 'line', name, data: [3, 5, 2, 4] }, extra || {});
const B = (name, extra) => Object.assign({ type: 'bar', name, data: [3, 5, 2, 4] }, extra || {});
const S = (name, extra) => Object.assign({ type: 'scatter', name, data: [3, 5, 2, 4] }, extra || {});
const PATH = 'path://M0,0L10,0L10,30L0,30Z';

const CASES = [
  { id: 'rotate.line.inherit', note: "a line's own icon: its marker turned by the series' symbolRotate under the default 'inherit'",
    option: chart([L('A', { symbol: 'triangle', symbolRotate: 30 }), L('B', { symbol: 'rect' })]) },
  { id: 'rotate.legend', note: 'legend symbolRotate 45: a line marker turned by it',
    option: chart([L('A', { symbol: 'triangle', symbolRotate: 30 }), L('B', { symbol: 'diamond' })], { symbolRotate: 45 }) },
  { id: 'rotate.item', note: "an item's own symbolRotate 90 over the legend's 20",
    option: chart([L('A', { symbol: 'triangle' }), L('B', { symbol: 'triangle' })],
      { symbolRotate: 20, data: [{ name: 'A', symbolRotate: 90 }, 'B'] }) },
  { id: 'rotate.bar', note: "a bar's default icon is not turned, whatever the legend says",
    option: chart([B('A'), B('B')], { symbolRotate: 45 }) },
  { id: 'rotate.scatter.inherit', note: "icon 'inherit' on a scatter: the default icon policy turns it by the series' symbolRotate",
    option: chart([S('A', { symbol: 'rect', symbolRotate: 20 }), S('B', { symbol: 'triangle', symbolRotate: -30 })], { icon: 'inherit' }) },
  { id: 'rotate.scatter.item', note: "an item's symbolRotate 60 with icon 'inherit' on a scatter",
    option: chart([S('A', { symbol: 'triangle', symbolRotate: 20 }), S('B', { symbol: 'triangle' })],
      { icon: 'inherit', data: [{ name: 'A', symbolRotate: 60 }, 'B'] }) },
  { id: 'keep.item', note: "a path icon: the legend keeps the aspect, an item does not",
    option: chart([B('A'), B('B')], { icon: PATH, data: [{ name: 'A', symbolKeepAspect: false }, 'B'] }) },
  { id: 'rich.item', note: "legend formatter '{x|{name}} !', an item's own textStyle.rich x",
    option: chart([B('Alpha'), B('Beta')], { formatter: '{x|{name}} !',
      data: [{ name: 'Alpha', textStyle: { rich: { x: { color: '#ff0000', fontSize: 18, fontWeight: 'bold' } } } }, 'Beta'] }) },
  { id: 'rich.item.over', note: "the legend's rich x, an item's x over it (its size only)",
    option: chart([B('Alpha'), B('Beta')], { formatter: '{x|{name}}', textStyle: { rich: { x: { color: '#0000ff', fontSize: 14 } } },
      data: [{ name: 'Alpha', textStyle: { rich: { x: { fontSize: 20 } } } }, 'Beta'] }) },
  { id: 'box.item', note: "an item's textStyle box (backgroundColor, padding, borderRadius)",
    option: chart([B('Alpha'), B('Beta'), B('Gamma')], {
      data: ['Alpha', { name: 'Beta', textStyle: { backgroundColor: '#eeeeee', padding: [4, 8], borderRadius: 3, borderColor: '#999999', borderWidth: 1 } }, 'Gamma'] }) },
];

function globalRect(el) {
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return r;
}
const rect4 = r => [r.x, r.y, r.width, r.height].map(hex);

function readItems(chart) {
  const lm = chart.getModel().getComponent('legend', 0);
  const view = chart.getViewOfComponentModel(lm);
  const group = view.getContentGroup();
  const data = lm.getData();
  const out = [];
  group.eachChild((g, i) => {
    const kids = g.childrenRef();
    const icons = [];
    let text = null;
    kids.forEach((k, j) => {
      if (k.type === 'text') {
        const runs = [];
        (k.childrenRef ? k.childrenRef() : []).forEach(t => {
          if (t.type === 'tspan') runs.push({ text: String(t.style.text), font: String(t.style.font), fill: t.style.fill == null ? null : String(t.style.fill) });
        });
        text = { rect: rect4(globalRect(k)), runs };
        return;
      }
      if (j === kids.length - 1) return; // the hit rect
      const paths = [];
      if (k.isGroup) k.traverse(c => { if (!c.isGroup) paths.push(c); });
      else paths.push(k);
      paths.forEach(p => icons.push({ rotation: hex(p.rotation || 0), rect: rect4(globalRect(p)) }));
    });
    const hit = kids[kids.length - 1];
    out.push({ name: data[i] ? data[i].get('name') : null, hit: rect4(globalRect(hit)), icons, text });
  });
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    chart.renderToSVGString();
    return { id: c.id, note: c.note, option: clone(c.option), items: readItems(chart) };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const fh = h => { for (let i = 0; i < 8; i++) bits.setUint8(i, parseInt(h.substr(i * 2, 2), 16)); return bits.getFloat64(0); };
  const rot = (id, k, j) => fh(by(id).items[k].icons[j].rotation) * 180 / Math.PI;
  const close = (a, b) => Math.abs(a - b) < 1e-9;
  const guards = [
    { name: 'rotate.line.inherit: the marker at 30, the rule level', ok: close(rot('rotate.line.inherit', 0, 1), 30) && close(rot('rotate.line.inherit', 0, 0), 0) },
    { name: 'rotate.legend: 45 for both', ok: close(rot('rotate.legend', 0, 1), 45) && close(rot('rotate.legend', 1, 1), 45) },
    { name: 'rotate.item: 90 for A, 20 for B', ok: close(rot('rotate.item', 0, 1), 90) && close(rot('rotate.item', 1, 1), 20) },
    { name: 'rotate.bar: not turned', ok: close(rot('rotate.bar', 0, 0), 0) },
    { name: 'rotate.scatter.inherit: 20 and -30', ok: close(rot('rotate.scatter.inherit', 0, 0), 20) && close(rot('rotate.scatter.inherit', 1, 0), -30) },
    { name: 'rotate.scatter.item: 60 for A', ok: close(rot('rotate.scatter.item', 0, 0), 60) },
    { name: 'keep.item: the two icons differ', ok: by('keep.item').items[0].icons[0].rect[2] !== by('keep.item').items[1].icons[0].rect[2] },
    { name: 'rich.item: Alpha in 18px bold red', ok: by('rich.item').items[0].text.runs.some(r => /bold 18px/.test(r.font) && r.fill === '#ff0000') },
    { name: 'rich.item.over: Alpha at 20, Beta at 14, both blue', ok: /20px/.test(by('rich.item.over').items[0].text.runs[0].font)
      && /14px/.test(by('rich.item.over').items[1].text.runs[0].font) && by('rich.item.over').items[0].text.runs[0].fill === '#0000ff' },
    { name: 'box.item: Beta\'s hit rect taller than Alpha\'s', ok: fh(by('box.item').items[1].hit[3]) > fh(by('box.item').items[0].hit[3]) },
  ];
  for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: component/legend/LegendView.ts _createItem, chart/line/LineSeries.ts getLegendIcon',
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
