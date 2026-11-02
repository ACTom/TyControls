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

[R7-I] The other axes that build a text through setTooltipConfig: a single
axis (AxisBuilder; its model's tooltip shows by default), a polar's radius
axis (AxisBuilder) and angle axis (AngleAxisView's labels; it draws no
name), a parallel axis (AxisBuilder) and a radar's indicators (an
AxisBuilder each, on a model with no parent whose mainType is 'radar': only
triggerEvent -- or an indicator's own tooltip.show -- wakes them, and the
tooltip cascade asks the radar model's `tooltip`, then the global one).
Their cases also carry axisIndex (the component's index; absent is 0) and,
where the box's place is compared, box [x, y] -- what TooltipView handed
the content's moveTo. A target 'name:k' is the k-th name in the view (a
radar's indicators), a number the k-th label: a text whose anid starts
'label_' in an AxisBuilder, any text of the view on an angle axis.
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
function axisText(chart, mainType, target, index) {
  if (mainType !== 'xAxis' && mainType !== 'yAxis') return axisText2(chart, mainType, target, index || 0);
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

// [R7-I] the other views: names 'name' / 'name:k', labels by index
function axisText2(chart, mainType, target, index) {
  const am = chart.getModel().getComponent(mainType, index);
  must(am, 'no ' + mainType + ' ' + index);
  const view = chart.getViewOfComponentModel(am);
  const names = [];
  const labels = [];
  view.group.traverse(el => {
    if (el.type !== 'text') return;
    if (el.anid === 'name') names.push(el);
    else if (mainType === 'angleAxis' || (el.anid && el.anid.startsWith('label_'))) labels.push(el);
  });
  let found;
  if (typeof target === 'string') found = names[target === 'name' ? 0 : +target.slice(5)];
  else found = labels[target];
  must(found, mainType + ' ' + index + ': no ' + target);
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

// ---------- [R7-I] the other axes ----------
const TIPF = { hideDelay: 0 };
function single(ax, root) {
  return Object.assign({
    animation: false,
    tooltip: Object.assign({}, TIP),
    singleAxis: Object.assign({ type: 'category', data: CAT, top: 60, height: 120, name: 'Days' }, ax || {}),
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [[0, 3], [2, 5], [4, 2]] }],
  }, root || {});
}
function polar(radius, angle, root) {
  return Object.assign({
    animation: false,
    tooltip: Object.assign({}, TIP),
    polar: { radius: [20, 140] },
    angleAxis: Object.assign({ type: 'category', data: CAT }, angle || {}),
    radiusAxis: Object.assign({ name: 'Load', max: 20000 }, radius || {}),
    series: [{ type: 'bar', coordinateSystem: 'polar', data: [3000, 5000, 2000, 6000, 4000] }],
  }, root || {});
}
function parallel(a0, a1, root) {
  return Object.assign({
    animation: false,
    tooltip: Object.assign({}, TIP),
    parallelAxis: [
      Object.assign({ dim: 0, name: 'Price', max: 20000 }, a0 || {}),
      Object.assign({ dim: 1, name: 'Grade', type: 'category', data: ['low', 'mid', 'high'] }, a1 || {}),
    ],
    series: [{ type: 'parallel', data: [[3000, 'low'], [12000, 'high']] }],
  }, root || {});
}
function radar(r, root) {
  return Object.assign({
    animation: false,
    tooltip: Object.assign({}, TIP),
    radar: Object.assign({
      indicator: [{ name: 'Speed', max: 20000 }, { name: 'Power', max: 20000 }, { name: 'Range', max: 20000 }],
      axisLabel: { show: true },
    }, r || {}),
    series: [{ type: 'radar', data: [{ value: [5000, 12000, 8000] }] }],
  }, root || {});
}
const add2 = (id, note, option, axis, target, more) => CASES.push(Object.assign({ id, note, option, axis, target }, more || {}));

add2('single.label', "a single axis' label: its model's tooltip shows by default",
  single(), 'singleAxis', 2);
add2('single.name', "a single axis' name, the same default",
  single(), 'singleAxis', 'name');
add2('single.off', "tooltip.show false on the single axis: the label is silent, no tooltip",
  single({ tooltip: { show: false } }), 'singleAxis', 1);
add2('single.trigger-off', "triggerEvent and tooltip.show false: the label answers, no box",
  single({ triggerEvent: true, tooltip: { show: false } }), 'singleAxis', 1);
add2('single.template', "the single axis' template: {a} the text, {c} rawLabel, {d} tickIndex",
  single({ tooltip: { formatter: '{a}|{c}|{d}' }, axisLabel: { formatter: '<{value}>' } }), 'singleAxis', 3);
add2('single.value', "a value single axis: the rawLabel grouped (getLabel's addCommas) under a formatter",
  single({ type: 'value', data: undefined, max: 20000, tooltip: { formatter: '{a}|{c}' }, axisLabel: { formatter: 'v{value}' } }, {
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [3000, 12000] }] }), 'singleAxis', 2);
add2('single.no-component', 'no tooltip component: nothing',
  Object.assign(single(), { tooltip: undefined }), 'singleAxis', 2);
add2('single.place', "the box where TooltipView puts it with no position written",
  single(null, { tooltip: Object.assign({}, TIPF) }), 'singleAxis', 2, { box: true });
add2('single.silent', "silent beats the default show",
  single({ silent: true }), 'singleAxis', 2);
add2('single.second', "the second single axis",
  Object.assign(single(), { singleAxis: [{ type: 'category', data: CAT, top: 20, height: 80, tooltip: { show: false } },
    { type: 'category', data: ['p', 'q', 'r'], top: 220, height: 80, name: 'Two' }],
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [[0, 3]] },
      { type: 'scatter', coordinateSystem: 'singleAxis', singleAxisIndex: 1, data: [[1, 3]] }] }),
  'singleAxis', 1, { axisIndex: 1 });

add2('polar.radius-label', "a radius axis' label under tooltip.show: the formatted text",
  polar({ tooltip: { show: true } }), 'radiusAxis', 2);
add2('polar.radius-template', "a radius axis' template: {c} the grouped rawLabel",
  polar({ tooltip: { show: true, formatter: '{a}|{c}|{d}' }, axisLabel: { formatter: '{value} kW' } }), 'radiusAxis', 3);
add2('polar.radius-name', "a radius axis' name",
  polar({ tooltip: { show: true } }), 'radiusAxis', 'name');
add2('polar.radius-default', "a radius axis that says nothing: silent",
  polar(), 'radiusAxis', 2);
add2('polar.angle-label', "an angle axis' label (AngleAxisView's own setTooltipConfig)",
  polar(null, { tooltip: { show: true } }), 'angleAxis', 1);
add2('polar.angle-template', "an angle axis' template: {a} formattedLabel, {c} rawLabel, {d} its index",
  polar(null, { tooltip: { show: true, formatter: '{a}|{c}|{d}' }, axisLabel: { formatter: '[{value}]' } }), 'angleAxis', 3);
add2('polar.angle-trigger', "an angle axis' triggerEvent alone: its tooltip defaults to show false",
  polar(null, { triggerEvent: true }), 'angleAxis', 1);
add2('polar.angle-place', "an angle axis' box with no position written",
  polar(null, { tooltip: { show: true } }, { tooltip: Object.assign({}, TIPF) }), 'angleAxis', 0, { box: true });
add2('polar.radius-place', "a radius axis' box with no position written",
  polar({ tooltip: { show: true } }, null, { tooltip: Object.assign({}, TIPF) }), 'radiusAxis', 1, { box: true });

add2('parallel.label', "a parallel axis' label under tooltip.show",
  parallel(null, { tooltip: { show: true } }), 'parallelAxis', 1, { axisIndex: 1 });
add2('parallel.name', "a parallel axis' name",
  parallel({ tooltip: { show: true } }), 'parallelAxis', 'name');
add2('parallel.template', "a parallel value axis' template: the grouped rawLabel",
  parallel({ tooltip: { show: true, formatter: '{a}|{c}|{d}' } }), 'parallelAxis', 2);
add2('parallel.default', "a parallel axis that says nothing: silent",
  parallel(), 'parallelAxis', 1);
add2('parallel.place', "a parallel axis' box with no position written",
  parallel({ tooltip: { show: true } }, null, { tooltip: Object.assign({}, TIPF) }), 'parallelAxis', 'name', { box: true });

add2('radar.name-trigger', "a radar's indicator name under triggerEvent: the radar model has no tooltip, the global's show stands",
  radar({ triggerEvent: true }), 'radar', 'name:1');
add2('radar.label-trigger', "a radar's scale label under triggerEvent: the formatted text",
  radar({ triggerEvent: true }), 'radar', 2);
add2('radar.template', "a radar's own tooltip formatter: {c} the grouped rawLabel",
  radar({ triggerEvent: true, tooltip: { formatter: '{a}|{c}|{d}' }, axisLabel: { show: true, formatter: '{value}!' } }), 'radar', 3);
add2('radar.default', "no triggerEvent: silent",
  radar(), 'radar', 'name:0');
add2('radar.tooltip-show', "the radar's tooltip.show without triggerEvent: the indicator model never sees it, silent",
  radar({ tooltip: { show: true } }), 'radar', 'name:0');
add2('radar.indicator-show', "an indicator's own tooltip.show: its model is not silent",
  radar({ indicator: [{ name: 'Speed', max: 20000, tooltip: { show: true } }, { name: 'Power', max: 20000 }, { name: 'Range', max: 20000 }] }), 'radar', 'name:0');
add2('radar.trigger-off', "triggerEvent and the radar's tooltip.show false: no box",
  radar({ triggerEvent: true, tooltip: { show: false } }), 'radar', 'name:2');
add2('radar.name-formatter', "an indicator name through axisName.formatter: the content is the formatted name (richText: not encoded)",
  radar({ triggerEvent: true, axisName: { formatter: '<{value}>' } }, { tooltip: Object.assign({ renderMode: 'richText' }, TIP) }),
  'radar', 'name:0');
add2('radar.place', "a radar name's box with no position written",
  radar({ triggerEvent: true }, { tooltip: Object.assign({}, TIPF) }), 'radar', 'name:1', { box: true });

function watchMove(chart) {
  const w = { box: null };
  const m = chart.getModel().getComponent('tooltip', 0);
  const view = m ? chart.getViewOfComponentModel(m) : null;
  if (!view || !view._tooltipContent) return w;
  const content = view._tooltipContent;
  const mv = content.moveTo;
  content.moveTo = function (x, y) {
    w.box = [x, y];
    return mv.apply(this, arguments);
  };
  return w;
}

function runCase(c) {
  const chart = mk();
  try {
    const opt = JSON.parse(JSON.stringify(c.option));
    chart.setOption(opt);
    refresh(chart);
    const w = c.box ? watchMove(chart) : null;
    const el = axisText(chart, c.axis, c.target, c.axisIndex);
    el.updateTransform();
    const r = el.getBoundingRect().clone();
    r.applyTransform(el.getComputedTransform());
    const pt = [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
    fire(chart, 'mousemove', { zrX: pt[0], zrY: pt[1], offsetX: pt[0], offsetY: pt[1] });
    const rec = {
      id: c.id, note: c.note, option: opt, axis: c.axis, target: c.target,
      rect: { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) },
      point: pt, tip: tipNow(chart),
    };
    if (c.axisIndex !== undefined) rec.axisIndex = c.axisIndex;
    if (w) {
      must(rec.tip && w.box, c.id + ': no box placed');
      rec.box = w.box.map(hex);
    }
    return rec;
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
    ['a single axis shows by default', tipIs('single.label', 'Wed')],
    ['a single axis off', tipIs('single.off', null) && tipIs('single.trigger-off', null)],
    ['a single value axis groups', tipIs('single.value', 'v10,000|10,000')],
    ['a radius label', tipIs('polar.radius-label', '10,000')],
    ['an angle label', tipIs('polar.angle-label', 'Tue')],
    ['an angle trigger alone', tipIs('polar.angle-trigger', null)],
    ['a parallel label', tipIs('parallel.label', 'mid')],
    ['a parallel default', tipIs('parallel.default', null)],
    ['a radar name under triggerEvent', tipIs('radar.name-trigger', 'Power')],
    ['a radar default', tipIs('radar.default', null) && tipIs('radar.tooltip-show', null)],
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
