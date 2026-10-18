/*
Upstream's own answers for fix batch F4c (spec section 207): a label's halo
dashes. labelStyle.ts sets a text style's lineDash from textBorderType (the
style's own, else the global textStyle's) and its lineDashOffset from
textBorderDashOffset; zrender strokes the text (strokeText) with
normalizeLineDash(lineDash, lineWidth): 'dashed' [4w, 2w], 'dotted' [w], a
number [n], an array as it is, 'solid' none.

Runs the real ECharts 6.1 dist in node's SSR mode. Each case is a bar chart
with one labelled bar; records the label's text element (for a rich label,
every text piece) as zrender holds it: the stroke, lineWidth, lineDash as
written, lineDashOffset, and the pattern normalizeLineDash makes of them.

  node tools/advchart-oracle/label-halo.js

writes tests/fixtures/advchart-label-halo.json (ORACLE_OUT overrides); two
runs byte-identical; ends with process.exit().
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-halo.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

// zrender canvas/dashStyle.ts, transcribed
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : Array.isArray(lineType) ? lineType : null;
}

function bar(label, root) {
  return Object.assign({
    animation: false,
    xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [5], label: Object.assign({ show: true, position: 'top', textBorderColor: '#ff0000', textBorderWidth: 3 }, label) }],
  }, root || {});
}
const CASES = [
  { id: 'dashed', option: bar({ textBorderType: 'dashed' }) },
  { id: 'dotted', option: bar({ textBorderType: 'dotted', textBorderWidth: 2 }) },
  { id: 'number', option: bar({ textBorderType: 5 }) },
  { id: 'array', option: bar({ textBorderType: [2, 3] }) },
  { id: 'solid', option: bar({ textBorderType: 'solid' }) },
  { id: 'none', option: bar({}) },
  { id: 'offset', option: bar({ textBorderType: 'dashed', textBorderDashOffset: 4 }) },
  { id: 'global', option: bar({}, { textStyle: { textBorderType: 'dotted' } }) },
  { id: 'rich', option: bar({ formatter: '{a|A}{b|B}', rich: { a: { textBorderType: 'dashed' }, b: {} } }) },
];

function textsOf(chart) {
  const sm = chart.getModel().getSeriesByIndex(0);
  const el = sm.getData().getItemGraphicEl(0);
  const t = el.getTextContent();
  must(t, 'no label');
  t.updateTransform && t.updateTransform();
  const list = [];
  const visit = s => ({
    text: s.text == null ? null : String(s.text),
    stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: s.lineWidth == null ? null : hex(s.lineWidth),
    lineDash: s.lineDash == null ? null : s.lineDash,
    lineDashOffset: s.lineDashOffset == null ? null : hex(s.lineDashOffset),
  });
  const kids = t.childrenRef ? t.childrenRef() : [];
  if (kids.length) kids.forEach(k => { if (k.type === 'tspan') list.push(visit(k.style)); });
  else list.push(visit(t.style));
  return list.map(r => {
    const lw = r.lineWidth == null ? 0 : (() => { bits.setUint32(0, parseInt(r.lineWidth.slice(0, 8), 16)); bits.setUint32(4, parseInt(r.lineWidth.slice(8), 16)); return bits.getFloat64(0); })();
    const pat = normalizeLineDash(r.lineDash, lw);
    return Object.assign(r, { pattern: pat == null ? null : pat.map(hex) });
  });
}

function generate() {
  const recs = CASES.map(c => {
    const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 400, height: 300 });
    try {
      chart.setOption(c.option);
      // a paint: a rich text's pieces are made when it is drawn
      chart.renderToSVGString();
      return { id: c.id, option: c.option, texts: textsOf(chart) };
    } finally {
      chart.dispose();
    }
  });
  const by = id => recs.find(r => r.id === id);
  const guards = [
    { name: 'dashed [12, 6]', ok: JSON.stringify(by('dashed').texts[0].pattern) === JSON.stringify([12, 6].map(hex)) },
    { name: 'solid none', ok: by('solid').texts[0].pattern === null },
    { name: 'global dotted', ok: by('global').texts[0].lineDash === 'dotted' },
    { name: 'rich: the token a dashed, b not', ok: by('rich').texts.some(t => t.text === 'A' && t.lineDash === 'dashed') && by('rich').texts.some(t => t.text === 'B' && t.lineDash == null) },
  ];
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, cases: recs, guards };
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
out1.cases.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.texts.map(t => [t.text, t.lineDash, t.pattern]))));
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
