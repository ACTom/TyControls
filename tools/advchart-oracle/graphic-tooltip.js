/*
Upstream's own answers for spec section 242: a graphic element as a tooltip
target. GraphicView calls graphic.setTooltipConfig on every element it
updates -- the content is the element's name, the formatter params
{componentType 'graphic', name, graphicIndex} with $vars ['name'], the item
option the element's `tooltip` (a string a formatter) -- so every element
answers the pointer with a tooltip when there is a tooltip component; an
element with no name shows an empty box. TooltipView shows it through
_showComponentItemTooltip: the element's tooltip over the graphic
component's, over a level whose formatter is the content, over the global
component; formatTpl with the $vars ({a} the name), HTML-encoded. A label
(textContent) is its host's; a group's child is its own (the first
dispatcher with a tooltip config, climbing).

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node's server-side mode with TooltipView running
(axis-tooltip.js' recipe: chart._ssr = false, echarts.env.node off, getDom
stubbed; Date replaced before the dist loads, setTimeout a no-op). Every
tooltip says hideDelay 0 and position [5, 5]. A case moves the pointer (via
zrender's own Handler) to the centre of an element's global rect (or a
point it gives), and records the shown richText content.

  node tools/advchart-oracle/graphic-tooltip.js

writes tests/fixtures/advchart-graphic-tooltip.json (ORACLE_OUT overrides);
runs twice and the two must be byte-identical. Ends with process.exit().

Top level: source, W, H, measure {firstCode, ratio[] (hex)}, cases[]
{id, note, option, target (an element id, or null with a point), point
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
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-graphic-tooltip.json');

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
function elementOf(chart, id) {
  const gm = chart.getModel().getComponent('graphic', 0);
  const view = chart.getViewOfComponentModel(gm);
  const el = view._elMap.get(id);
  must(el, 'no element ' + id);
  return el;
}

const TIP = { hideDelay: 0, position: [5, 5] };
const R = (id, x, y, more) => Object.assign({ type: 'rect', id, shape: { x, y, width: 80, height: 50 }, style: { fill: '#5070dd' } }, more || {});

const CASES = [];
const add = (id, note, option, target, point) => CASES.push({ id, note, option: Object.assign({ animation: false }, option), target, point: point || null });
add('named', "a named element: the content is its name", { tooltip: TIP, graphic: [R('a', 20, 20, { name: 'Alpha' })] }, 'a');
add('unnamed', "no name: an empty box", { tooltip: TIP, graphic: [R('a', 20, 20)] }, 'a');
add('formatter', "the element's formatter: {a} is the name, {b} is no variable", { tooltip: TIP, graphic: [R('a', 20, 20, { name: 'Alpha', tooltip: { formatter: 'I am {b} ({a})' } })] }, 'a');
add('string', 'a string tooltip is the formatter', { tooltip: TIP, graphic: [R('a', 20, 20, { name: 'Alpha', tooltip: 'plain words' })] }, 'a');
add('show-false', "the element's show false: none", { tooltip: TIP, graphic: [R('a', 20, 20, { name: 'Alpha', tooltip: { show: false } })] }, 'a');
add('no-component', 'no tooltip component: none', { graphic: [R('a', 20, 20, { name: 'Alpha', tooltip: { show: true } })] }, 'a');
add('global-show-false', "the global show false, the element's true: shown", { tooltip: Object.assign({ show: false }, TIP), graphic: [R('a', 20, 20, { name: 'Alpha', tooltip: { show: true } })] }, 'a');
add('component', "the graphic component's own tooltip under the element's", { tooltip: TIP, graphic: { tooltip: { formatter: 'cmp {a}' }, elements: [R('a', 20, 20, { name: 'Alpha' })] } }, 'a');
add('group-child', "a group's child: its own config (the first dispatcher), not the group's", { tooltip: TIP, graphic: [{ type: 'group', id: 'g', name: 'grp', tooltip: { formatter: 'group!' }, children: [R('k', 20, 20, { name: 'kid' })] }] }, 'k');
add('encoded', 'the name HTML-encoded into the template', { tooltip: TIP, graphic: [R('a', 20, 20, { name: 'A<B', tooltip: { formatter: '[{a}]' } })] }, 'a');
add('global-formatter', 'the global formatter is never reached: the content level has one', { tooltip: Object.assign({ formatter: 'global {a}' }, TIP), graphic: [R('a', 20, 20, { name: 'Alpha' })] }, 'a');
add('text', 'a text element: its name', { tooltip: TIP, graphic: [{ type: 'text', id: 't', name: 'Tee', x: 100, y: 100, style: { text: 'Hello there', fontSize: 20 } }] }, 't');
add('label', "a host's textContent: the host's tooltip", { tooltip: TIP, graphic: [R('h', 200, 200, { name: 'Host', textContent: { style: { text: 'label text', fontSize: 14 } }, textConfig: { position: 'bottom' } })] }, null, [240, 262]);
add('silent', 'a silent element answers nothing', { tooltip: TIP, graphic: [R('a', 20, 20, { name: 'Alpha', silent: true })] }, 'a');
add('click', "triggerOn 'click': a move shows nothing", { tooltip: Object.assign({ triggerOn: 'click' }, TIP), graphic: [R('a', 20, 20, { name: 'Alpha' })] }, 'a');
add('number-name', 'a numeric name', { tooltip: TIP, graphic: [R('a', 20, 20, { name: 42 })] }, 'a');

function runCase(c) {
  const chart = mk();
  try {
    const opt = JSON.parse(JSON.stringify(c.option));
    chart.setOption(opt);
    refresh(chart);
    let pt = c.point;
    if (!pt) {
      const el = elementOf(chart, c.target);
      el.updateTransform();
      const r = el.getBoundingRect().clone();
      const m = el.getComputedTransform();
      if (m) r.applyTransform(m);
      pt = [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
    }
    fire(chart, 'mousemove', { zrX: pt[0], zrY: pt[1], offsetX: pt[0], offsetY: pt[1] });
    return { id: c.id, note: c.note, option: opt, target: c.target, point: pt, tip: tipNow(chart) };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const recs = CASES.map(runCase);
  const by = id => recs.find(r => r.id === id);
  const tipIs = (id, t) => { const x = by(id).tip; return t === null ? x === null : (x !== null && x.text === t); };
  const guards = [
    ['the name is the content', tipIs('named', 'Alpha')],
    ['no name: an empty box', tipIs('unnamed', '')],
    ['{a} is the name', tipIs('formatter', 'I am {b} (Alpha)')],
    ['a string is the formatter', tipIs('string', 'plain words')],
    ['show false: none', tipIs('show-false', null)],
    ['no component: none', tipIs('no-component', null)],
    ['the component level', tipIs('component', 'cmp Alpha')],
    ["a group's child is its own", tipIs('group-child', 'kid')],
    ['encoded', tipIs('encoded', '[A&lt;B]')],
    ['the global formatter is not reached', tipIs('global-formatter', 'Alpha')],
    ["a label is its host's", tipIs('label', 'Host')],
    ['silent: none', tipIs('silent', null)],
    ["triggerOn 'click': none on a move", tipIs('click', null)],
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
