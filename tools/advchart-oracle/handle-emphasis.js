// Upstream's own answers for round-5 batch R5-D (2026-10-27): the hover
// style of a slider dataZoom's handles and move handle and of a continuous
// visualMap's thumbs -- their `emphasis` states:
//   SliderZoomView._renderHandle: path.ensureState('emphasis').style =
//     emphasis.handleStyle's getItemStyle() (the model's default writes
//     borderColor), enableHoverEmphasis; the move handle's emphasis style is
//     emphasis.moveHandleStyle's (default opacity 0.8), entered when the
//     move zone is hovered
//   ContinuousView._createHandle: handleThumb.ensureState('emphasis').style
//     = emphasis.handleStyle's getItemStyle() (no default), its normal
//     lineWidth doubled (the emphasis one is not)
// A state's style is merged over the normal one: what the hover shows is the
// normal style with the state's keys written over it; a dataZoom handle has
// the default state proxy as well (enableHoverEmphasis): no emphasis fill
// written, the normal fill lifted (liftColor). A hovered handle puts the
// move handle in emphasis too (_onOverDataInfoTriggerArea).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node, SVG renderer, ssr then chart._ssr = false, env.node
// off, the pointer through zrender's Handler, animation off.
//
//   node tools/advchart-oracle/handle-emphasis.js
//
// writes tests/fixtures/advchart-handle-emphasis.json (ORACLE_OUT overrides).
//
// Per case: id, note, option, steps [{at, record}]: record {handles [{states,
// fill, stroke, lineWidth, opacity, centre [x, y]} the two handles' paths (a
// dataZoom's) or thumbs (a visualMap's) as drawn now], move {states, fill,
// stroke, opacity} | null (the move handle)}. Colours as the element's style
// holds them; centre the element's global bounding-rect centre, rounded.
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
let NOW = 1700000000000;
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-handle-emphasis.json');
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
const val = v => (v === undefined ? null : v);
function globalCentre(el) {
  const r = el.getBoundingRect().clone();
  el.updateTransform();
  if (el.transform) r.applyTransform(el.transform);
  return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)];
}
let SHADOW_CASE = false;
function styleOf(el) {
  if (!el) return null;
  const s = el.style;
  const r = { states: (el.currentStates || []).slice(), fill: val(s.fill), stroke: val(s.stroke), lineWidth: val(s.lineWidth),
    opacity: val(s.opacity), centre: globalCentre(el) };
  // [R5-F] the shadow keys, for the cases that ask
  if (SHADOW_CASE) {
    r.shadowBlur = val(s.shadowBlur);
    r.shadowOffsetX = val(s.shadowOffsetX);
    r.shadowOffsetY = val(s.shadowOffsetY);
    r.shadowColor = val(s.shadowColor);
  }
  return r;
}
function record(chart, kind) {
  const m = chart.getModel().getComponent(kind, 0);
  const v = chart.getViewOfComponentModel(m);
  if (kind === 'dataZoom') {
    const d = v._displayables;
    return { handles: d.handles.map(styleOf), move: d.moveHandle ? styleOf(d.moveHandle) : null };
  }
  const sh = v._shapes;
  return { handles: sh.handleThumbs.map(styleOf), move: null };
}
const BASE = { animation: false, xAxis: { type: 'category', data: ['a', 'b', 'c', 'd', 'e'] }, yAxis: {},
  series: [{ type: 'bar', data: [3, 5, 2, 6, 4] }] };
const CASES = [
  {
    id: 'dz-written', kind: 'dataZoom', note: 'a slider whose emphasis.handleStyle writes a colour, a border and a width, and whose '
      + 'emphasis.moveHandleStyle writes a colour and an opacity: the hover shows them over the normal style',
    option: Object.assign({ dataZoom: [{ type: 'slider', start: 20, end: 80, handleStyle: { color: '#00ff00', borderColor: '#0000ff' },
      moveHandleStyle: { color: '#00ffff' },
      emphasis: { handleStyle: { color: '#ff0000', borderColor: '#ffff00', borderWidth: 3 }, moveHandleStyle: { color: '#ff00ff', opacity: 1 } } }] }, BASE),
    hovers: ['handle0', 'none', 'move', 'none'],
  },
  {
    id: 'dz-default', kind: 'dataZoom', note: 'no emphasis colour written: the default state proxy lifts the normal colour '
      + '(enableHoverEmphasis), the border is the model default, the move handle at opacity 0.8',
    option: Object.assign({ dataZoom: [{ type: 'slider', start: 20, end: 80, handleStyle: { color: '#00ff00' }, moveHandleStyle: { color: '#00ffff' } }] }, BASE),
    hovers: ['handle1', 'none', 'move', 'none'],
  },
  {
    id: 'vm-written', kind: 'visualMap', note: 'a calculable continuous visualMap with emphasis.handleStyle: the hovered thumb takes '
      + 'its colour, border and width (the width not doubled)',
    option: Object.assign({ visualMap: { type: 'continuous', min: 0, max: 10, calculable: true, right: 10, bottom: 20,
      handleStyle: { borderColor: '#0000ff', borderWidth: 1 },
      emphasis: { handleStyle: { color: '#ff0000', borderColor: '#00ff00', borderWidth: 4 } } } }, BASE),
    hovers: ['handle0', 'none'],
  },
  {
    id: 'dz-lift', kind: 'dataZoom', note: 'a mid colour written, no emphasis colour: the hovered handle is the lifted colour '
      + '(liftColor; pure green lifts to itself)',
    option: Object.assign({ dataZoom: [{ type: 'slider', start: 20, end: 80, handleStyle: { color: '#3366cc' } }] }, BASE),
    hovers: ['handle0', 'none'],
  },
  // [R5-F] the hover's shadow keys over the normal style's, key by key
  {
    id: 'dz-shadow', kind: 'dataZoom', shadow: true, note: 'handleStyle casts a shadow (blur 4 at (1, 1)); emphasis.handleStyle '
      + 'writes another blur and colour: the hovered handle takes them, the offsets kept; the move handle\'s emphasis a shadow of its own',
    option: Object.assign({ dataZoom: [{ type: 'slider', start: 20, end: 80,
      handleStyle: { color: '#00ff00', shadowBlur: 4, shadowOffsetX: 1, shadowOffsetY: 1, shadowColor: 'rgba(0,0,0,0.3)' },
      moveHandleStyle: { color: '#00ffff' },
      emphasis: { handleStyle: { shadowBlur: 10, shadowColor: '#ff0000' }, moveHandleStyle: { shadowBlur: 6, shadowOffsetY: 2, shadowColor: '#0000ff' } } }] }, BASE),
    hovers: ['handle0', 'none', 'move', 'none'],
  },
  {
    id: 'vm-shadow', kind: 'visualMap', shadow: true, note: 'a visualMap thumb: emphasis.handleStyle shadow over handleStyle\'s',
    option: Object.assign({ visualMap: { type: 'continuous', min: 0, max: 10, calculable: true, right: 10, bottom: 20,
      handleStyle: { borderColor: '#0000ff', borderWidth: 1, shadowBlur: 3, shadowOffsetX: 2, shadowColor: '#00ff00' },
      emphasis: { handleStyle: { shadowBlur: 8, shadowOffsetY: 4 } } } }, BASE),
    hovers: ['handle0', 'none'],
  },
];
function hoverPoint(chart, def, rec, what) {
  if (what === 'none') return [5, 5];
  if (what === 'move') {
    const m = chart.getModel().getComponent('dataZoom', 0);
    const v = chart.getViewOfComponentModel(m);
    return globalCentre(v._displayables.moveHandle);
  }
  return rec.handles[what === 'handle0' ? 0 : 1].centre;
}
function runCase(def) {
  SHADOW_CASE = !!def.shadow;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    chart._onframe();
    chart.renderToSVGString();
    const steps = [];
    let rec = record(chart, def.kind);
    steps.push({ op: 'start', at: null, record: rec });
    for (const h of def.hovers) {
      const at = hoverPoint(chart, def, rec, h);
      chart.getZr().handler.mousemove(rawEvent('mousemove', at[0], at[1]));
      chart._onframe();
      chart.renderToSVGString();
      rec = record(chart, def.kind);
      steps.push({ op: h, at, record: rec });
    }
    return { id: def.id, kind: def.kind, note: def.note, option: def.option, steps };
  } finally {
    chart.dispose();
  }
}
let cases;
let json1;
try {
  cases = CASES.map(runCase);
  const w = cases[0];
  must(w.steps[1].record.handles[0].fill === '#ff0000' && w.steps[1].record.handles[0].stroke === '#ffff00'
    && w.steps[1].record.handles[0].lineWidth === 3, 'dz: the written emphasis');
  must(w.steps[2].record.handles[0].fill === '#00ff00', 'dz: back to the normal style');
  must(w.steps[3].record.move.fill === '#ff00ff' && w.steps[3].record.move.opacity === 1, 'dz: the move handle');
  const d = cases[1];
  must(d.steps[1].record.handles[1].fill === 'rgba(0,255,0,1)' && d.steps[1].record.handles[1].states.indexOf('emphasis') >= 0, 'dz default: the default proxy lifts the normal colour');
  must(d.steps[3].record.move.opacity === 0.8, 'dz default: opacity 0.8');
  const v = cases[2];
  must(v.steps[1].record.handles[0].stroke === '#00ff00' && v.steps[1].record.handles[0].lineWidth === 4, 'vm: the written emphasis');
  const l = cases[3];
  must(l.steps[1].record.handles[0].fill !== '#3366cc' && l.steps[1].record.handles[0].states.indexOf('emphasis') >= 0, 'dz lift: lifted');
  json1 = JSON.stringify({ source: 'ECharts ' + echarts.version, W, H, cases }, null, 1) + '\n';
  const json2 = JSON.stringify({ source: 'ECharts ' + echarts.version, W, H, cases: CASES.map(runCase) }, null, 1) + '\n';
  must(json1 === json2, 'two generations differ');
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  if (cases) console.log(JSON.stringify(cases.map(c => c.steps.map(s => [s.op, s.record.handles.map(h => h && [h.states, h.fill, h.stroke, h.lineWidth, h.opacity]), s.record.move && [s.record.move.states, s.record.move.fill, s.record.move.opacity]]))));
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log(cases.length + ' cases; ' + json1.length + ' bytes; wrote', OUT);
process.exit(0);
