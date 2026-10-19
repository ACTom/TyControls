/*
Upstream's own answers for fix batch R2-A a1 (spec section 218): a label of
several lines, turned or not -- a series label and an axis label. zrender's
Text lays a plain block out in its own frame (_updatePlainTexts): the
lines one line height apart (getLineHeight: the width of a CJK character,
the font size under SSR), the block aligned vertically as a whole
(adjustTextY over the content height), every line a TSpan at the anchor's
x, its textAlign the block's, its textBaseline 'middle', y the line's
middle; the Text's transform turns the whole frame about the anchor.

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off). Every text of several lines -- a series label off its host
(getTextContent), an axis label off the axis' group -- is read after a
render: its computed transform, its turn, the alignment drawn, and every
TSpan's words and (x, y) in the text's frame.

  node tools/advchart-oracle/multiline-label.js

writes tests/fixtures/advchart-multiline-label.json (ORACLE_OUT overrides);
generated twice in the process, byte-identical; ends with process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option,
        texts[] {kind: 'series' | 'axis', s (series index or null),
                 d (data index or null), text, mat [6 hex], rotation (hex),
                 align, verticalAlign, lineHeight (hex: the second TSpan's y
                 less the first's), spans[] {text, x, y (hex, the text's
                 frame)}}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-multiline-label.json');
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

const CATS = ['Mon', 'Tue', 'Wed', 'Thu'];
const bar = (label, root) => Object.assign({
  animation: false,
  xAxis: { type: 'category', data: CATS }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [120, 200, 150, 80], label: Object.assign({ show: true }, label) }],
}, root || {});

const CASES = [
  { id: 'bar.turned.two', note: 'a bar label of two lines turned 45 degrees, top',
    option: bar({ position: 'top', rotate: 45, formatter: '{b}\n{c}' }) },
  { id: 'bar.turned.three', note: 'three lines turned -30, insideTop, centred on the middle',
    option: bar({ position: 'insideTop', rotate: -30, verticalAlign: 'middle', formatter: '{b}\nx\n{c}' }) },
  { id: 'bar.turned.bottom', note: 'two lines turned 90, aligned right and bottom',
    option: bar({ position: 'insideBottom', rotate: 90, align: 'right', verticalAlign: 'bottom', formatter: '{c}\n{b}' }) },
  { id: 'bar.level', note: 'two lines, level',
    option: bar({ position: 'top', formatter: '{b}\n{c}' }) },
  { id: 'axis.turned', note: 'a category axis\' labels of three lines turned 40 degrees',
    option: bar({ show: false }, { xAxis: { type: 'category', data: CATS, axisLabel: { rotate: 40, formatter: '{value}\nday\nend' } } }) },
  { id: 'axis.turned.value', note: 'a value axis\' labels of two lines turned -20 degrees',
    option: bar({ show: false }, { yAxis: { type: 'value', axisLabel: { rotate: -20, formatter: '{value}\nunits' } } }) },
  // [R2-I2] the polar, single and parallel axes (AxisBuilder's labels, as
  // the cartesian ones)
  { id: 'polar.radius.turned', note: 'a polar category radius axis\' labels of two lines turned 30 degrees',
    option: { animation: false, polar: {}, angleAxis: { type: 'value', axisLabel: { show: false } },
      radiusAxis: { type: 'category', data: CATS, axisLabel: { rotate: 30, formatter: '{value}\nday' } },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [1, 2, 3, 4] }] } },
  { id: 'polar.radius.level', note: 'the same, level, three lines',
    option: { animation: false, polar: {}, angleAxis: { type: 'value', axisLabel: { show: false } },
      radiusAxis: { type: 'category', data: CATS, axisLabel: { formatter: '{value}\nday\nend' } },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [1, 2, 3, 4] }] } },
  { id: 'polar.angle', note: 'a polar category angle axis\' labels of two lines',
    option: { animation: false, polar: {}, radiusAxis: { type: 'value', axisLabel: { show: false } },
      angleAxis: { type: 'category', data: CATS, axisLabel: { formatter: '{value}\nday' } },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [1, 2, 3, 4] }] } },
  { id: 'polar.angle.turned', note: 'the angle axis\' labels of two lines turned 20 degrees',
    option: { animation: false, polar: {}, radiusAxis: { type: 'value', axisLabel: { show: false } },
      angleAxis: { type: 'category', data: CATS, axisLabel: { rotate: 20, formatter: '{value}\nday' } },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [1, 2, 3, 4] }] } },
  { id: 'single.turned', note: 'a single category axis\' labels of two lines turned 30 degrees',
    option: { animation: false, singleAxis: { type: 'category', data: CATS, top: 100, height: 100, axisLabel: { rotate: 30, formatter: '{value}\nday' } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [0, 1, 2, 3] }] } },
  { id: 'single.level', note: 'a single value axis\' labels of three lines, level',
    option: { animation: false, singleAxis: { type: 'value', top: 100, height: 100, axisLabel: { formatter: '{value}\nx\ny' } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 5, 9] }] } },
  { id: 'parallel.turned', note: 'parallel axes: a category axis\' labels of two lines turned 30, a value axis\' turned -20',
    option: { animation: false, parallelAxis: [{ dim: 0, type: 'category', data: CATS, axisLabel: { rotate: 30, formatter: '{value}\nday' } },
      { dim: 1, axisLabel: { rotate: -20, formatter: '{value}\nu' } }],
      series: [{ type: 'parallel', data: [['Mon', 3], ['Wed', 8]] }] } },
  { id: 'parallel.level', note: 'a vertical parallel layout: the labels of two lines, level',
    option: { animation: false, parallel: { layout: 'vertical' }, parallelAxis: [{ dim: 0, type: 'category', data: CATS, axisLabel: { formatter: '{value}\nday' } },
      { dim: 1, axisLabel: { formatter: '{value}\nu' } }],
      series: [{ type: 'parallel', data: [['Mon', 3], ['Wed', 8]] }] } },
  { id: 'axis.level', note: 'a value axis\' labels of lines of different lengths, level (right-aligned: each line on its own)',
    option: bar({ show: false }, { yAxis: { type: 'value', axisLabel: { formatter: '{value}\nunits wide' } } }) },
];

function record(t, kind, s, d) {
  // [R2-I2] no transform anywhere up its parents: the identity
  const m = t.getComputedTransform() || [1, 0, 0, 1, 0, 0];
  const ds = t._defaultStyle || {};
  const kids = (t.childrenRef ? t.childrenRef() : []).filter(k => k.type === 'tspan');
  must(kids.length >= 2, 'a text of several lines with ' + kids.length + ' spans: ' + JSON.stringify(t.style.text));
  return {
    kind, s, d,
    text: String(t.style.text),
    mat: Array.from(m).map(hex),
    rotation: hex(t.innerTransformable && t.innerTransformable !== t ? t.innerTransformable.rotation : t.rotation),
    align: t.style.align || ds.align || 'left',
    verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
    lineHeight: hex(kids[1].style.y - kids[0].style.y),
    spans: kids.map(k => ({ text: String(k.style.text), x: hex(k.style.x), y: hex(k.style.y),
      baseline: k.style.textBaseline || null, align: k.style.textAlign || null })),
  };
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    chart.renderToSVGString();
    const texts = [];
    chart.getModel().eachSeries(sm => {
      const data = sm.getData();
      data.each(idx => {
        const el = data.getItemGraphicEl(idx);
        const t = el && el.getTextContent && el.getTextContent();
        if (t && !t.ignore && String(t.style.text).indexOf('\n') >= 0) texts.push(record(t, 'series', sm.seriesIndex, idx));
      });
    });
    for (const mainType of ['xAxis', 'yAxis', 'angleAxis', 'radiusAxis', 'singleAxis', 'parallelAxis']) {
      chart.getModel().eachComponent(mainType, (am) => {
        const view = chart.getViewOfComponentModel(am);
        view.group.traverse(el => {
          if (el.type === 'text' && !el.ignore && String(el.style.text).indexOf('\n') >= 0) texts.push(record(el, 'axis', null, null));
        });
      });
    }
    return { id: c.id, note: c.note, option: clone(c.option), texts };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const num = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  const guards = [
    { name: 'every series case has four texts', ok: ['bar.turned.two', 'bar.turned.three', 'bar.turned.bottom', 'bar.level'].every(id => by(id).texts.length === 4) },
    { name: 'the axis cases have their labels', ok: by('axis.turned').texts.length === 4 && by('axis.turned.value').texts.length >= 4 },
    { name: 'a line height of 12 (the font size)', ok: cases.every(c => c.texts.every(t => num(t.lineHeight) === 12)) },
    { name: 'spans middle-based', ok: cases.every(c => c.texts.every(t => t.spans.every(s => s.baseline === 'middle'))) },
    { name: 'the turned ones are turned', ok: by('bar.turned.two').texts.every(t => num(t.mat[1]) !== 0) },
    { name: 'the other axes have their labels', ok: ['polar.radius.turned', 'polar.radius.level', 'polar.angle', 'polar.angle.turned',
      'single.turned', 'parallel.turned', 'parallel.level'].every(id => by(id).texts.length >= 4) && by('single.level').texts.length >= 3 },
  ];
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H, cases, guards };
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
out1.cases.forEach(c => console.log(c.id + ': ' + c.texts.length + ' texts'));
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log(json1 !== json2 ? 'FAILED: two generations differ' : 'FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
