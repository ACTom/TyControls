/*
Upstream's own answers for fix batch R5-F (spec section 243): a label line's
style in a state.

labelGuideHelper.setLabelLineStyle gives each state of the line the state
model's whole lineStyle (setLabelLineState: `stateObj.style =
stateModel.getModel('lineStyle').getLineStyle()`) -- stroke, lineWidth,
opacity, lineDash (type), lineDashOffset (dashOffset), lineCap (cap),
lineJoin (join), miterLimit and the shadow, only the keys written -- and
zrender merges it over the normal style when the line enters the state with
its host.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off; chart._ssr = false and chart._onframe() after each step, so
the states apply). After the first render and after each action, every label
line of series 0 is read: its data index, whether it is ignored, and its
style as it stands.

  node tools/advchart-oracle/label-line-states.js

writes tests/fixtures/advchart-label-line-states.json (ORACLE_OUT
overrides); generated twice in the process, byte-identical; ends with
process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option, steps[] {action (null for the first render),
        lines[] {d, ignore, stroke, lineWidth, opacity, lineDash (hex[] |
        null), lineDashOffset, lineCap, lineJoin, miterLimit (each hex or
        string or null as the style holds it)}}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-line-states.json');
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
function pie(series) {
  return { animation: false, color: PALETTE, series: [Object.assign({ type: 'pie', radius: '50%', data: DATA() }, series)] };
}
const FULL = { color: '#ff0000', width: 3, opacity: 0.5, type: 'dashed', dashOffset: 2, cap: 'round', join: 'bevel', miterLimit: 3 };
const HL = d => ({ type: 'highlight', seriesIndex: 0, dataIndex: d });
const DP = d => ({ type: 'downplay', seriesIndex: 0, dataIndex: d });

const CASES = [
  { id: 'pie.emph.full', note: "a pie's emphasis.labelLine.lineStyle with every key: the hovered line takes them, the others keep theirs",
    option: pie({ emphasis: { labelLine: { lineStyle: FULL } } }), actions: [HL(1), DP(1)] },
  { id: 'pie.emph.partial', note: 'the normal line dotted and 2 wide, the emphasis only its colour and dash offset: the rest kept',
    option: pie({ labelLine: { lineStyle: { type: 'dotted', width: 2 } }, emphasis: { labelLine: { lineStyle: { color: '#00aa00', dashOffset: 4 } } } }),
    actions: [HL(0)] },
  { id: 'pie.emph.solid', note: 'the normal line dashed, the emphasis one solid with a dash array',
    option: pie({ labelLine: { lineStyle: { type: 'dashed' } }, emphasis: { labelLine: { lineStyle: { type: [6, 2] } } } }),
    actions: [HL(2)] },
  { id: 'pie.select', note: 'select.labelLine.lineStyle: cap and join on the selected slice',
    option: pie({ selectedMode: 'single', select: { labelLine: { lineStyle: { cap: 'square', join: 'round', width: 2 } } } }),
    actions: [{ type: 'select', seriesIndex: 0, dataIndex: 3 }] },
  { id: 'scatter.emph', note: "a scatter's label line (the label manager's) with emphasis.labelLine.lineStyle",
    option: { animation: false, color: PALETTE, xAxis: {}, yAxis: {},
      series: [{ type: 'scatter', symbolSize: 10, data: [[1, 2], [3, 5], [6, 1]],
        label: { show: true, position: 'right', distance: 20 }, labelLine: { show: true },
        labelLayout: { dx: 30, dy: -20 },
        emphasis: { labelLine: { lineStyle: { type: 'dotted', opacity: 0.4, cap: 'round', width: 2 } } } }] },
    actions: [HL(1)] },
];

function arr(v) { return v == null ? null : (Array.isArray(v) ? v.map(hex) : String(v)); }
function val(v) { return v == null ? null : (typeof v === 'number' ? hex(v) : String(v)); }

function ecData(el) {
  const k = Object.keys(el).find(n => /^__ec_inner_\d+$/.test(n) && el[n] && 'dataIndex' in el[n]);
  return k ? el[k] : null;
}

function readLines(chart) {
  const out = [];
  const sm = chart.getModel().getSeriesByIndex(0);
  chart.getViewOfSeriesModel(sm).group.traverse(el => {
    const g = el.getTextGuideLine && el.getTextGuideLine();
    if (!g) return;
    const d = ecData(el);
    const s = g.style;
    out.push({ d: d ? d.dataIndex : null, ignore: !!g.ignore, stroke: val(s.stroke), lineWidth: val(s.lineWidth),
      opacity: val(s.opacity), lineDash: arr(s.lineDash), lineDashOffset: val(s.lineDashOffset),
      lineCap: val(s.lineCap), lineJoin: val(s.lineJoin), miterLimit: val(s.miterLimit) });
  });
  out.sort((a, b) => a.d - b.d);
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(clone(c.option));
    chart._onframe();
    chart.renderToSVGString();
    const steps = [{ action: null, lines: readLines(chart) }];
    for (const a of c.actions) {
      chart.dispatchAction(clone(a));
      chart._onframe();
      chart.renderToSVGString();
      steps.push({ action: clone(a), lines: readLines(chart) });
    }
    return { id: c.id, note: c.note, option: clone(c.option), steps };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const line = (id, k, d) => by(id).steps[k].lines.find(l => l.d === d);
  const guards = [
    { name: 'pie.emph.full: the hovered line in every key', ok: line('pie.emph.full', 1, 1).lineCap === 'round'
      && line('pie.emph.full', 1, 1).lineJoin === 'bevel' && line('pie.emph.full', 1, 1).opacity === hex(0.5)
      && line('pie.emph.full', 1, 1).lineDash !== null && line('pie.emph.full', 1, 1).stroke === '#ff0000' },
    { name: 'pie.emph.full: another line untouched', ok: line('pie.emph.full', 1, 0).lineCap === null || line('pie.emph.full', 1, 0).lineCap === 'butt' },
    { name: 'pie.emph.full: back after the downplay', ok: JSON.stringify(line('pie.emph.full', 2, 1)) === JSON.stringify(line('pie.emph.full', 0, 1)) },
    { name: 'pie.emph.partial: the normal dash kept, the offset the emphasis one',
      ok: JSON.stringify(line('pie.emph.partial', 1, 0).lineDash) === JSON.stringify(line('pie.emph.partial', 0, 0).lineDash)
        && line('pie.emph.partial', 1, 0).lineDashOffset === hex(4) },
    { name: 'pie.select: square caps on the selected line', ok: line('pie.select', 1, 3).lineCap === 'square' },
    { name: 'scatter.emph: the hovered line dotted', ok: line('scatter.emph', 1, 1).lineDash !== null && line('scatter.emph', 1, 1).lineCap === 'round' },
  ];
  for (const g of guards) must(g.ok, 'guard failed: ' + g.name);
  return { source: 'ECharts 6.1 dist: label/labelGuideHelper.ts setLabelLineStyle, zrender Displayable states', W, H, cases,
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
