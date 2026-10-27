/*
Upstream's own answers for fix batch R5-F (spec section 243): the temporary
symbol a line builds for a highlighted row that has none.

LineView.highlight with ONE data index (not an array) whose row has no
symbol element -- showSymbol false, or a symbol the category interval
thinned away (showAllSymbol 'auto') -- builds a SymbolClz for the row at its
point (data.getLayout('points')), unless the point is NaN or outside
_clipShapeForSymbol; it is z / zlevel the series', marked __temp, its scale
animation stopped, added to the view's group, set as the row's graphic
element and highlighted (Symbol.highlight: the emphasis state -- its scale,
emphasis.itemStyle). LineView.downplay of that index removes it again; a
highlight of an array goes the ChartView way and builds none.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off; chart._ssr = false and chart._onframe() after each step, the
browser's model, so the states apply). Per step it records every series-0
symbol element: its data index, whether it is temporary, its states, its
global bounding rect, fill, stroke, lineWidth, z, z2, and its label's text
and whether it is shown.

  node tools/advchart-oracle/line-temp-symbol.js

writes tests/fixtures/advchart-line-temp-symbol.json (ORACLE_OUT
overrides); generated twice in the process, byte-identical; ends with
process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option, steps[] {action (the payload dispatched, or null
        for the first render), symbols[] {d, temp, states, rect [4 hex],
        fill, stroke, lineWidth (hex | null), z, z2, label: null |
        {text, shown}}}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-line-temp-symbol.json');
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
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
function line(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    xAxis: { type: 'category', data: cats(6) }, yAxis: {},
    series: [Object.assign({ type: 'line', showSymbol: false, data: [12, 30, 18, 25, 9, 21] }, series)] }, root || {});
}
const HL = d => ({ type: 'highlight', seriesIndex: 0, dataIndex: d });
const DP = d => ({ type: 'downplay', seriesIndex: 0, dataIndex: d });

const CASES = [
  { id: 'basic', note: 'showSymbol false: highlight 2 builds the row\'s symbol in emphasis, downplay 2 takes it away',
    option: line({}), actions: [HL(2), DP(2)] },
  { id: 'move', note: 'highlight 1, then 4 (1 still highlighted), then downplay 1',
    option: line({}), actions: [HL(1), HL(4), DP(1)] },
  { id: 'array', note: 'a highlight of [3]: ChartView\'s, no temporary symbol', option: line({}), actions: [{ type: 'highlight', seriesIndex: 0, dataIndex: [3] }] },
  { id: 'styled', note: 'symbol rect 10, itemStyle colour, emphasis.itemStyle colour and borderWidth, emphasis.scale 2',
    option: line({ symbol: 'rect', symbolSize: 10, itemStyle: { color: '#336699' },
      emphasis: { scale: 2, itemStyle: { color: '#ff0000', borderColor: '#000000', borderWidth: 2 } } }),
    actions: [HL(3)] },
  { id: 'styled.shown', note: 'the same with its symbols shown: the own symbol of the row in the same emphasis',
    option: line({ showSymbol: true, symbol: 'rect', symbolSize: 10, itemStyle: { color: '#336699' },
      emphasis: { scale: 2, itemStyle: { color: '#ff0000', borderColor: '#000000', borderWidth: 2 } } }),
    actions: [HL(3)] },
  { id: 'clipped', note: 'yAxis max 20: the row of 30 is outside the clip and gets no symbol; 18 does',
    option: line({}, { yAxis: { max: 20 } }), actions: [HL(1), HL(2)] },
  { id: 'thinned', note: 'showSymbol true over 40 categories in a narrow grid: showAllSymbol auto thins them; a thinned row\'s highlight builds one',
    option: { animation: false, color: PALETTE, grid: { left: 40, right: 400 },
      xAxis: { type: 'category', data: cats(40) }, yAxis: {},
      series: [{ type: 'line', data: Array.from({ length: 40 }, (_, i) => (i * 7) % 13 + 1) }] },
    actions: [HL(1), DP(1), HL(2)] },
  { id: 'label', note: 'label.show true, showSymbol false: the temporary symbol carries its label',
    option: line({ label: { show: true } }), actions: [HL(5)] },
  { id: 'two', note: 'two lines without symbols, the second highlighted at 0 by series index 1',
    option: { animation: false, color: PALETTE, xAxis: { type: 'category', data: cats(6) }, yAxis: {},
      series: [{ type: 'line', showSymbol: false, data: [12, 30, 18, 25, 9, 21] },
        { type: 'line', showSymbol: false, symbolSize: 8, data: [5, 8, 3, 9, 4, 6] }] },
    actions: [{ type: 'highlight', seriesIndex: 1, dataIndex: 0 }, HL(0)], series: [0, 1] },
];

function ecData(el) {
  const k = Object.keys(el).find(n => /^__ec_inner_\d+$/.test(n) && el[n] && 'dataIndex' in el[n]);
  return k ? el[k] : null;
}

function readSymbols(chart, s) {
  const out = [];
  const sm = chart.getModel().getSeriesByIndex(s);
  const view = chart.getViewOfSeriesModel(sm);
  view.group.traverse(el => {
    if (typeof el.getSymbolPath !== 'function') return;
    const p = el.getSymbolPath();
    const d = ecData(p);
    const r = p.getBoundingRect().clone();
    const m = p.getComputedTransform();
    if (m) r.applyTransform(m);
    const t = p.getTextContent();
    out.push({
      s, d: d ? d.dataIndex : null, temp: !!el.__temp, states: (p.currentStates || []).join(','),
      ignore: !!(el.ignore || p.ignore || el.invisible || p.invisible),
      rect: [r.x, r.y, r.width, r.height].map(hex),
      fill: p.style.fill == null ? null : String(p.style.fill),
      stroke: p.style.stroke == null ? null : String(p.style.stroke),
      lineWidth: p.style.lineWidth == null ? null : hex(p.style.lineWidth),
      z: p.z, z2: p.z2,
      label: t ? { text: String(t.style.text), shown: !t.ignore && !t.invisible } : null,
    });
  });
  out.sort((a, b) => (a.d - b.d));
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(clone(c.option));
    chart._onframe();
    chart.renderToSVGString();
    const series = c.series || [0];
    const read = () => [].concat(...series.map(s => readSymbols(chart, s)));
    const steps = [{ action: null, symbols: read() }];
    for (const a of c.actions) {
      chart.dispatchAction(clone(a));
      chart._onframe();
      chart.renderToSVGString();
      steps.push({ action: clone(a), symbols: read() });
    }
    return { id: c.id, note: c.note, option: clone(c.option), steps };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const temps = (id, k) => by(id).steps[k].symbols.filter(x => x.temp);
  const guards = [
    { name: 'basic: none at rest, the temporary symbol of 2 in emphasis, none after the downplay',
      ok: by('basic').steps[0].symbols.length === 0 && temps('basic', 1).length === 1 && temps('basic', 1)[0].d === 2
        && temps('basic', 1)[0].states === 'emphasis' && by('basic').steps[2].symbols.length === 0 },
    { name: 'move: 1 and 4 both there, then only 4', ok: temps('move', 2).length === 2 && temps('move', 3).length === 1 && temps('move', 3)[0].d === 4 },
    { name: 'array: none', ok: by('array').steps[1].symbols.length === 0 },
    { name: 'styled: the emphasis colour', ok: temps('styled', 1)[0].fill === '#ff0000' },
    { name: 'clipped: none for 1, one for 2', ok: temps('clipped', 1).length === 0 && temps('clipped', 2).length === 1 },
    { name: 'thinned: some symbols thinned at rest; 1 is one of them', ok: by('thinned').steps[0].symbols.length < 40
      && !by('thinned').steps[0].symbols.some(x => x.d === 1) && temps('thinned', 1).length === 1 },
    { name: 'label: the temporary symbol\'s label shows', ok: temps('label', 1)[0].label && temps('label', 1)[0].label.shown },
    { name: 'two: series 1\'s own temporary symbol', ok: temps('two', 1).length === 1 && temps('two', 1)[0].s === 1 },
  ];
  for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: chart/line/LineView.ts highlight / downplay, chart/helper/Symbol.ts', W, H, cases,
    guards: guards.map(g => g.name) };
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
