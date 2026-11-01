/*
Upstream's own answers for fix batch R5-F (spec section 243): a picture
casts its shadow. A symbol written 'image://...' is a zrender Image whose
style takes the item style's shadow keys (Symbol.ts: the symbol path's
useStyle of the visual style -- an Image's style is the same object), and
zrender's canvas Image draws with the context's shadow set (brushImage after
bindContextStyle): the shadow is cast from the picture's own alpha.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off). Every Image element in a series' view group (and in a
markPoint's) is read: its series, data index, its style's shadow keys and
its global bounding rect.

  node tools/advchart-oracle/image-shadow.js

writes tests/fixtures/advchart-image-shadow.json (ORACLE_OUT overrides);
generated twice in the process, byte-identical; ends with process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option,
        images[] {s, d (null where none), shadowBlur, shadowOffsetX,
                  shadowOffsetY, shadowColor (as the style holds them),
                  rect [4 hex]}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-image-shadow.json');
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

const PNG = 'image://data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC';
const cats = ['a', 'b', 'c', 'd'];
const CASES = [
  { id: 'scatter', note: "scatter image symbols: the series' itemStyle shadow, item 1 its own blur and colour",
    option: { animation: false, xAxis: {}, yAxis: {},
      series: [{ type: 'scatter', symbol: PNG, symbolSize: 20,
        itemStyle: { shadowBlur: 6, shadowOffsetX: 3, shadowOffsetY: 2, shadowColor: 'rgba(0,0,0,0.5)' },
        data: [[1, 2], { value: [3, 5], itemStyle: { shadowBlur: 12, shadowColor: '#ff0000' } }, [5, 1]] }] } },
  { id: 'line', note: 'line symbols drawn as pictures with a shadow',
    option: { animation: false, xAxis: { type: 'category', data: cats }, yAxis: {},
      series: [{ type: 'line', symbol: PNG, symbolSize: 14, itemStyle: { shadowBlur: 4, shadowOffsetY: 4, shadowColor: '#333' },
        data: [3, 5, 2, 4] }] } },
  { id: 'pictorial', note: "a pictorial bar of pictures: the itemStyle shadow on every glyph",
    option: { animation: false, xAxis: { type: 'category', data: cats }, yAxis: {},
      series: [{ type: 'pictorialBar', symbol: PNG, symbolRepeat: true, symbolSize: [16, 16],
        itemStyle: { shadowBlur: 5, shadowOffsetX: 2, shadowColor: '#0000ff' }, data: [30, 50, 20, 40] }] } },
  { id: 'none', note: 'pictures with no shadow written',
    option: { animation: false, xAxis: {}, yAxis: {},
      series: [{ type: 'scatter', symbol: PNG, symbolSize: 20, data: [[1, 2], [3, 5]] }] } },
];

function ecData(el) {
  const k = Object.keys(el).find(n => /^__ec_inner_\d+$/.test(n) && el[n] && 'dataIndex' in el[n]);
  return k ? el[k] : null;
}
const v = x => (x === undefined ? null : x);

function readImages(chart) {
  const out = [];
  chart.getModel().eachSeries(sm => {
    chart.getViewOfSeriesModel(sm).group.traverse(el => {
      if (el.type !== 'image') return;
      let d = null;
      for (let e = el; e && d === null; e = e.parent) {
        const ed = ecData(e);
        if (ed && ed.dataIndex != null) d = ed.dataIndex;
      }
      const r = el.getBoundingRect().clone();
      const m = el.getComputedTransform();
      if (m) r.applyTransform(m);
      const s = el.style;
      out.push({ s: sm.seriesIndex, d, shadowBlur: v(s.shadowBlur), shadowOffsetX: v(s.shadowOffsetX),
        shadowOffsetY: v(s.shadowOffsetY), shadowColor: s.shadowColor == null ? null : String(s.shadowColor),
        rect: [r.x, r.y, r.width, r.height].map(hex) });
    });
  });
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    chart.renderToSVGString();
    return { id: c.id, note: c.note, option: clone(c.option), images: readImages(chart) };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const guards = [
    { name: 'scatter: every picture casts, item 1 its own', ok: by('scatter').images.length === 3
      && by('scatter').images.every(i => i.shadowBlur > 0) && by('scatter').images.some(i => i.d === 1 && i.shadowBlur === 12 && i.shadowColor === '#ff0000') },
    { name: 'line: four pictures with a shadow', ok: by('line').images.length === 4 && by('line').images.every(i => i.shadowBlur === 4) },
    { name: 'pictorial: glyphs with a shadow', ok: by('pictorial').images.length > 4 && by('pictorial').images.every(i => i.shadowBlur === 5) },
    { name: 'none: no blur', ok: by('none').images.every(i => !i.shadowBlur) },
  ];
  for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: chart/helper/Symbol.ts, zrender canvas brushImage', W, H, cases, guards: guards.map(g => g.name) };
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
