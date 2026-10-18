/*
Upstream's own answers for fix batch F4c (spec section 207): a visualMap's
texts. A continuous view's end texts (ContinuousView._renderEndsText) take
the text style's own align and verticalAlign before the ones the bar's turn
gives, and a text with a line break is a block of lines; a piecewise view's
item labels and end texts; and every one of them is drawn -- the T1 harvest
found them missing from the port's headless pictures.

Runs the real ECharts 6.1 dist in node's SSR mode (zrender measures with its
width table). For each case records every Text of the visualMap view: its
string, its style x / y in the global frame, align, verticalAlign, and its
global bounding rect.

  node tools/advchart-oracle/visualmap-text.js

writes tests/fixtures/advchart-visualmap-text.json (ORACLE_OUT overrides);
two runs byte-identical; ends with process.exit().
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visualmap-text.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const W = 600;
const H = 400;

const FIRST_CODE = 32;
const LAST_CODE = 126;
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

function scatter(vm) {
  return {
    animation: false,
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    visualMap: vm,
    series: [{ type: 'scatter', data: [[1, 2, 3], [2, 3, 6], [3, 1, 9]] }],
  };
}
const CASES = [
  { id: 'c-lines', note: "a continuous view's end texts with a line break: a block of two lines",
    option: scatter({ min: 0, max: 10, dimension: 2, text: ['High\nValue', 'Low'] }) },
  { id: 'c-align', note: "the text style's align and verticalAlign before the bar's",
    option: scatter({ min: 0, max: 10, dimension: 2, text: ['High', 'Low'], textStyle: { align: 'left', verticalAlign: 'top' } }) },
  { id: 'c-horizontal', note: "horizontal: the text style's verticalAlign bottom, the align from the turn",
    option: scatter({ min: 0, max: 10, dimension: 2, orient: 'horizontal', left: 'center', text: ['High', 'Low'], textStyle: { verticalAlign: 'bottom' } }) },
  { id: 'c-usa', note: "map-usa's view on a scatter: left 'right', text ['High', 'Low'], calculable (the handle labels too)",
    option: scatter({ left: 'right', min: 0, max: 10, dimension: 2, text: ['High', 'Low'], calculable: true }) },
  { id: 'p-clustering', note: "scatter-clustering's piecewise view: the six item labels",
    option: scatter({ type: 'piecewise', top: 'middle', min: 0, max: 6, left: 10, splitNumber: 6, dimension: 2,
      pieces: [0, 1, 2, 3, 4, 5].map(v => ({ value: v, label: 'cluster ' + v })) }) },
  { id: 'p-ends', note: 'a piecewise view with end texts',
    option: scatter({ type: 'piecewise', min: 0, max: 9, dimension: 2, splitNumber: 3, text: ['High', 'Low'] }) },
];

function textsOf(chart) {
  const vm = chart.getModel().getComponent('visualMap', 0);
  const view = chart.getViewOfComponentModel(vm);
  const out = [];
  view.group.updateTransform();
  view.group.traverse(el => {
    if (el.type !== 'text' || el.ignore || el.invisible) return;
    el.updateTransform();
    const m = el.getComputedTransform() || [1, 0, 0, 1, 0, 0];
    const r = el.getBoundingRect().clone();
    r.applyTransform(m);
    out.push({
      string: String(el.style.text), align: el.style.align || null, verticalAlign: el.style.verticalAlign || null,
      x: hex(m[0] * (el.style.x || 0) + m[2] * (el.style.y || 0) + m[4]),
      y: hex(m[1] * (el.style.x || 0) + m[3] * (el.style.y || 0) + m[5]),
      rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height),
        text: [r.x, r.y, r.width, r.height].join(',') },
    });
  });
  return out;
}

function generate() {
  const recs = CASES.map(c => {
    const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
    try {
      chart.setOption(c.option);
      return { id: c.id, note: c.note, option: c.option, texts: textsOf(chart) };
    } finally {
      chart.dispose();
    }
  });
  const by = id => recs.find(r => r.id === id);
  const guards = [
    { name: 'c-lines: a two-line block', ok: by('c-lines').texts.some(t => t.string === 'High\nValue') },
    { name: 'c-align: left / top', ok: by('c-align').texts.every(t => t.align === 'left' && t.verticalAlign === 'top') },
    { name: 'c-horizontal: bottom', ok: by('c-horizontal').texts.every(t => t.verticalAlign === 'bottom') },
    { name: 'p-clustering: six labels', ok: by('p-clustering').texts.filter(t => t.string.startsWith('cluster')).length === 6 },
  ];
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) }, cases: recs, guards };
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
out1.cases.forEach(c => console.log(c.id + ': ' + c.texts.map(t => JSON.stringify(t.string) + '@' + t.rect.text + ' ' + t.align + '/' + t.verticalAlign).join('; ')));
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
