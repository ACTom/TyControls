/*
Upstream's own answers for fix batch F4c (spec section 207): an axis' name
and its labels as tooltip targets. AxisBuilder gives both a tooltip config
(graphic.setTooltipConfig: the content is the text, the formatter params
{componentType, name, <mainType>Index} -- a label's also isTruncated, value
(its rawLabel) and tickIndex), and makes them silent unless the axis says
triggerEvent or tooltip.show (isLabelSilent); TooltipView shows them through
_showComponentItemTooltip: the axis' `tooltip` over a level whose formatter
is the content, over the global component, formatTpl with the item's $vars,
HTML-encoded.

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode with TooltipView running
(geo-interact.js' recipe: chart._ssr = false, echarts.env.node off, getDom
stubbed; Date replaced before the dist loads, setTimeout a no-op). Every
tooltip says hideDelay 0 and position [5, 5]. A case moves the pointer (via
zrender's own Handler) to the centre of the name's or a label's global
rect, and records the shown richText content.

  node tools/advchart-oracle/axis-tooltip.js

writes tests/fixtures/advchart-axis-tooltip.json (ORACLE_OUT overrides);
runs twice and the two must be byte-identical. Ends with process.exit().

Top level: source, W, H, measure {firstCode, ratio[] (hex)}, cases[]
{id, note, option, target ('name' | label index), axis ('xAxis' | 'yAxis'),
rect {x, y, width, height} (hex, the text's global bounding rect), point
[x, y], tip (null, or {text})}, guards[].
*/
'use strict';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const ZRENDER_SRC = 'D:/Projects/zrender/src/contain/text.ts';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-tooltip.json');

Math.random = function () { return 0; };

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

// ---------- zrender's width table ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
function decodeTable(literal, where) {
  const s = Function('"use strict"; return (' + literal + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, where + ': the width table is not 95 characters');
  return s;
}
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  return decodeTable(line.slice(line.indexOf('=') + 1).trim().replace(/;$/, ''), DIST);
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

// ---------- the chart ----------
(function enableTooltips() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk() {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
const zr = chart => chart.getZr();
function refresh(chart) { zr(chart).storage.getDisplayList(true); }
function zev(extra) { return Object.assign({ preventDefault() {}, stopPropagation() {}, which: 1 }, extra); }
function fire(chart, name, extra) {
  refresh(chart);
  zr(chart).handler[name](zev(extra));
  refresh(chart);
}
function tipNow(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  const view = m ? chart.getViewOfComponentModel(m) : null;
  if (!view) return null;
  const c = view._tooltipContent;
  if (!c || !c.el || !c._show) return null;
  return { text: String(c.el.style.text) };
}

// the axis' text element: its name (anid 'name'), or the label of a tick
function axisText(chart, mainType, target) {
  const am = chart.getModel().getComponent(mainType, 0);
  const view = chart.getViewOfComponentModel(am);
  let found = null;
  view.group.traverse(el => {
    if (found || el.type !== 'text') return;
    if (target === 'name' ? el.anid === 'name' : (el.anid && el.anid.startsWith('label_') && el.__f4cIndex === undefined)) {
      if (target === 'name') found = el;
    }
  });
  if (target !== 'name') {
    const labels = [];
    view.group.traverse(el => { if (el.type === 'text' && el.anid && el.anid.startsWith('label_')) labels.push(el); });
    found = labels[target] || null;
  }
  must(found, mainType + ': no ' + target);
  return found;
}

const TIP = { hideDelay: 0, position: [5, 5] };
const CAT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
function bar(x, y, root) {
  return Object.assign({
    animation: false,
    tooltip: Object.assign({}, TIP),
    xAxis: Object.assign({ type: 'category', data: CAT }, x || {}),
    yAxis: Object.assign({ type: 'value' }, y || {}),
    series: [{ type: 'bar', data: [3, 5, 2, 6, 4] }],
  }, root || {});
}

const CASES = [];
const add = (id, note, option, axis, target) => CASES.push({ id, note, option, axis, target });

add('name-trigger', "triggerEvent alone: the name answers the pointer, but the axis' tooltip defaults to show false",
  bar(null, { name: 'Value', triggerEvent: true }), 'yAxis', 'name');
add('name-show', "tooltip.show: the content is the name",
  bar(null, { name: 'Value', tooltip: { show: true } }), 'yAxis', 'name');
add('name-formatter', "the axis' own tooltip.show and a template: {a} is the name",
  bar(null, { name: 'Value', tooltip: { show: true, formatter: 'N:{a}' } }), 'yAxis', 'name');
add('name-encoded', 'the name HTML-encoded into the template',
  bar(null, { name: 'A<B', tooltip: { show: true, formatter: '[{a}]' } }), 'yAxis', 'name');
add('name-global-formatter', "the global formatter is never reached: the content's level has one",
  bar(null, { name: 'Value', tooltip: { show: true } }, { tooltip: Object.assign({ formatter: 'GLOBAL' }, TIP) }), 'yAxis', 'name');
add('name-silent', 'neither triggerEvent nor tooltip.show: the name is silent, no tooltip',
  bar(null, { name: 'Value' }), 'yAxis', 'name');
add('name-axis-silent', 'triggerEvent but silent: silent wins',
  bar(null, { name: 'Value', triggerEvent: true, silent: true }), 'yAxis', 'name');
add('name-no-component', 'triggerEvent and no tooltip component: no tooltip',
  Object.assign(bar(null, { name: 'Value', triggerEvent: true }), { tooltip: undefined }), 'yAxis', 'name');
add('name-show-false', "the axis' tooltip.show false with triggerEvent: the text answers, the box does not show",
  bar(null, { name: 'Value', triggerEvent: true, tooltip: { show: false } }), 'yAxis', 'name');
add('label-show', 'a category label under tooltip.show: its formatted text',
  bar({ tooltip: { show: true }, axisLabel: { formatter: '{value}!' } }), 'xAxis', 2);
add('label-template', "a label's {a} (the text), {c} (rawLabel) and {d} (tickIndex)",
  bar({ tooltip: { show: true, formatter: '{a}|{c}|{d}' }, axisLabel: { formatter: '<{value}>' } }), 'xAxis', 3);

function runCase(c) {
  const chart = mk();
  try {
    const opt = JSON.parse(JSON.stringify(c.option));
    chart.setOption(opt);
    refresh(chart);
    const el = axisText(chart, c.axis, c.target);
    el.updateTransform();
    const r = el.getBoundingRect().clone();
    r.applyTransform(el.getComputedTransform());
    const pt = [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
    fire(chart, 'mousemove', { zrX: pt[0], zrY: pt[1], offsetX: pt[0], offsetY: pt[1] });
    return {
      id: c.id, note: c.note, option: opt, axis: c.axis, target: c.target,
      rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
      point: pt, tip: tipNow(chart),
    };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const recs = CASES.map(runCase);
  const by = id => recs.find(r => r.id === id);
  const tipIs = (id, t) => { const x = by(id).tip; return t === null ? x === null : (x !== null && x.text === t); };
  const guards = [
    ['triggerEvent alone shows nothing', tipIs('name-trigger', null)],
    ['the name is the content', tipIs('name-show', 'Value')],
    ['a template', tipIs('name-formatter', 'N:Value')],
    ['encoded', tipIs('name-encoded', '[A&lt;B]')],
    ['the global formatter is not reached', tipIs('name-global-formatter', 'Value')],
    ['silent: none', tipIs('name-silent', null)],
    ['axis silent: none', tipIs('name-axis-silent', null)],
    ['no component: none', tipIs('name-no-component', null)],
    ['show false: none', tipIs('name-show-false', null)],
    ['a label', tipIs('label-show', 'Wed!')],
  ].map(([name, ok]) => ({ name, ok }));
  return {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    cases: recs, guards,
  };
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
out1.cases.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.tip) + ' at ' + c.point));
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
const same = json1 === json2;
console.log(out1.cases.length + ' cases; two runs ' + (same ? 'identical' : 'DIFFERENT'));
if (bad.length || !same || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
