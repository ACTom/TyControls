// Upstream's own answers for a timeline's tick labels beyond timeline.js:
// a formatter function (makeLabelFormatter: the category name or the value
// and the index -- the port's '@Name' handler), `rich` text and `overflow`
// at a `width` (component/timeline/SliderTimelineView.ts _renderAxisLabel,
// label/labelStyle.ts createTextStyle, zrender Text).
//
// Runs the real ECharts 6.1 build in node's server-side mode (SVG renderer),
// renders once and reads every label of the timeline view's label group.
//
//   node tools/advchart-oracle/timeline-labels.js
//
// writes tests/fixtures/advchart-timeline-labels.json (ORACLE_OUT overrides).
//
// handlers {name: what it returns}; cases[]  id, note, W, H, option (as fed,
// a formatter function written '@name')
//   labels[]  the label group's texts in order: text (style.text), texts
//             (the drawn lines / tokens), rect ([x, y, w, h] hex: the
//             bounding rect through the computed transform)
// Self-checks: anchors; two generations give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-timeline-labels.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

const HANDLER_NOTES = {
  '@TL_FMT': "(value, index) => '#' + index + ' ' + value",
};
const HANDLERS = {
  '@TL_FMT': (value, index) => '#' + index + ' ' + value,
};
function bind(o) {
  if (Array.isArray(o)) return o.map(bind);
  if (o && typeof o === 'object') {
    const r = {};
    for (const k of Object.keys(o)) r[k] = bind(o[k]);
    return r;
  }
  if (typeof o === 'string' && Object.prototype.hasOwnProperty.call(HANDLERS, o)) return HANDLERS[o];
  return o;
}

const LETTERS = ['Alpha', 'Bravo', 'Charlie', 'Delta'];
function tl(t) {
  return {
    animation: false,
    timeline: Object.assign({ axisType: 'category', data: LETTERS }, t),
    xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: {},
    series: [{ type: 'bar', data: [1, 2] }],
    options: LETTERS.map((_, i) => ({ series: [{ data: [i, 2] }] })),
  };
}

const CASES = [
  { id: 'fn', note: 'a formatter function: the name and the index', option: tl({ label: { formatter: '@TL_FMT' } }) },
  { id: 'fn.value', note: 'a formatter function on a value timeline: the value and the index',
    option: tl({ axisType: 'value', data: [0, 10, 25, 40], label: { formatter: '@TL_FMT' } }) },
  { id: 'rich', note: 'rich labels: a styled token and the rest',
    option: tl({ label: { formatter: '{a|{value}}!', rich: { a: { color: '#c23531', fontSize: 15 } } } }) },
  { id: 'overflow', note: "overflow 'truncate' at width 30", option: tl({ label: { width: 30, overflow: 'truncate' } }) },
  { id: 'break', note: "overflow 'break' at width 20", option: tl({ data: ['Aa Bb', 'Cc Dd', 'Ee Ff', 'Gg Hh'], label: { width: 20, overflow: 'break' } }) },
];

function labelsOf(chart) {
  const v = chart._componentsViews.find(x => x.__model && x.__model.mainType === 'timeline');
  must(v, 'no timeline view');
  const out = [];
  v.group.traverse(el => {
    if (el.type !== 'text') return;
    // the labels only: the label group's
    if (!el.parent || el.parent !== v._labelGroup) return;
    const r = el.getBoundingRect().clone();
    const m = el.getComputedTransform();
    if (m) r.applyTransform(m);
    const texts = [];
    el.childrenRef().forEach(c => { if (c.type === 'tspan') texts.push(String(c.style.text)); });
    out.push({ text: String(el.style.text), texts, rect: [hex(r.x), hex(r.y), hex(r.width), hex(r.height)] });
  });
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(bind(c.option));
    chart.renderToSVGString();
    return { id: c.id, note: c.note, W, H, option: c.option, labels: labelsOf(chart) };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = {};
  for (const c of cases) by[c.id] = c;
  must(by.fn.labels.length === 4 && by.fn.labels[1].text === '#1 Bravo', 'anchor: the function words the label');
  must(by.rich.labels.every(l => l.texts.length === 2), 'anchor: a token and the rest');
  must(by.overflow.labels.some(l => l.texts[0].indexOf('...') >= 0), 'anchor: truncated');
  must(by.break.labels.every(l => l.texts.length === 2), 'anchor: wrapped');
  return { source: 'ECharts 6.1 dist, component/timeline/SliderTimelineView.ts, label/labelStyle.ts',
    handlers: HANDLER_NOTES, cases };
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
