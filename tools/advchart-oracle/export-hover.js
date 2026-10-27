// Upstream's own answers for round-5 batch R5-D (2026-10-27): what
// getDataURL exports of the pointer's state. The picture is the zrender
// storage as it stands (canvas Painter.getRenderedCanvas draws every layer's
// display list, the hover layer too; the SVG painter renders the same list),
// so an axis pointer's elements and an item's emphasis state -- a hover's,
// the axis' highlight -- are in it; an html tooltip is a DOM node and is not.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node, SVG renderer, ssr then chart._ssr = false, env.node
// off (the pointer's global listeners run), the pointer through zrender's
// Handler; getDataURL() is the SVG painter's string.
//
//   node tools/advchart-oracle/export-hover.js
//
// writes tests/fixtures/advchart-export-hover.json (ORACLE_OUT overrides).
//
// Per case: id, note, option, at (the point hovered), before / after:
// {pointer (the exported SVG holds the shadow band's fill: an element of
// z 50 or more, the axis pointer's), emphasis [the data indices of series
// 0 whose element is in emphasis], fills [their fills as the SVG writes
// them, in data order], exported [each of those fills is in the export]}.
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const CLOCK0 = 1700000000000;
let NOW = CLOCK0;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-export-hover.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
(function enable() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();
function rawEvent(type, x, y) {
  return { type, zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} };
}
// a fill as the SVG painter writes it: rgb() and a fill-opacity apart
function svgFill(c) {
  const m = /^rgba?\(([^)]*)\)$/.exec(String(c).replace(/\s+/g, ''));
  if (!m) return 'fill="' + c + '"';
  const p = m[1].split(',');
  const rgb = 'fill="rgb(' + p.slice(0, 3).join(',') + ')"';
  return p.length > 3 && +p[3] !== 1 ? rgb + ' fill-opacity="' + p[3] + '"' : rgb;
}
function record(chart) {
  chart._onframe();
  chart.renderToSVGString();
  const svg = decodeURIComponent(chart.getDataURL().replace(/^data:image\/svg\+xml;charset=UTF-8,/, ''));
  const data = chart.getModel().getSeriesByIndex(0).getData();
  const emphasis = [];
  const fills = [];
  for (let i = 0; i < data.count(); i++) {
    const el = data.getItemGraphicEl(i);
    if (el && (el.currentStates || []).indexOf('emphasis') >= 0) emphasis.push(i);
    fills.push(el ? svgFill(el.style.fill) : null);
  }
  // the axis pointer: an element of the axisPointer view's group, drawn
  let pointer = false;
  const list = chart.getZr().storage.getDisplayList(true);
  for (const el of list) {
    let g = el;
    while (g && !(g.__ecComponentInfo && g.__ecComponentInfo.mainType === 'axisPointer')) g = g.parent;
    if (!g && el.z >= 50 && el.style && el.style.fill && svg.indexOf(svgFill(el.style.fill)) >= 0) pointer = true;
  }
  return { pointer, emphasis, fills, exported: fills.map(f => f && svg.indexOf(f) >= 0) };
}
const CASES = [
  {
    id: 'axis-shadow', note: 'an axis tooltip with a shadow pointer, its box no content: the pointer and the highlighted bar are in the '
      + 'export',
    option: { animation: false, tooltip: { trigger: 'axis', showContent: false, axisPointer: { type: 'shadow' } },
      xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { max: 10 }, series: [{ type: 'bar', data: [3, 5, 2] }] },
    at: [300, 300],
  },
  {
    id: 'item', note: 'an item hover: the hovered bar in emphasis is in the export',
    option: { animation: false, tooltip: { trigger: 'item', showContent: false },
      xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { max: 10 }, series: [{ type: 'bar', data: [3, 5, 2] }] },
    at: [300, 300],
  },
];
function runCase(def) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    chart._onframe();
    chart.renderToSVGString();
    const before = record(chart);
    chart.getZr().handler.mousemove(rawEvent('mousemove', def.at[0], def.at[1]));
    chart.renderToSVGString();
    const after = record(chart);
    return { id: def.id, note: def.note, option: def.option, at: def.at, before, after };
  } finally {
    chart.dispose();
  }
}
let cases;
let json1;
let json2;
try {
  cases = CASES.map(runCase);
  const c0 = cases[0];
  must(!c0.before.pointer && c0.after.pointer, 'the pointer is exported');
  must(c0.after.emphasis.length === 1 && c0.after.fills[1] !== c0.before.fills[1] && c0.after.exported[1], 'the highlighted bar is exported in its emphasis');
  const c1 = cases[1];
  must(c1.after.emphasis.length === 1 && c1.after.fills[1] !== c1.before.fills[1] && c1.after.exported[1], 'the hovered bar too');
  json1 = JSON.stringify({ source: 'ECharts ' + echarts.version, W, H, cases }, null, 1) + '\n';
  json2 = JSON.stringify({ source: 'ECharts ' + echarts.version, W, H, cases: CASES.map(runCase) }, null, 1) + '\n';
  must(json1 === json2, 'two generations differ');
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log(cases.length + ' cases; ' + json1.length + ' bytes; wrote', OUT);
process.exit(0);
