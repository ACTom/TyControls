// Round 7 R7-I: the eventData an axis' part carries, as the real ECharts 6.1
// dist builds it -- AxisBuilder's name (targetType 'axisName', name: the
// name as the builder took it, before truncation) and labels (targetType
// 'axisLabel', value: the label's rawLabel -- scale.getLabel(tick), not
// the formatted text drawn --, tickIndex: its index in the axis' labels,
// dataIndex on a category axis), AngleAxisView's labels (value: rawLabel,
// no tickIndex), a radar's indicators (an AxisBuilder each on a model whose
// mainType is 'radar': the name as axisName.formatter made it; triggerEvent
// the indicator's own over the radar's), each with componentType,
// componentIndex and <mainType>Index (makeAxisEventDataBase).
//
// Per case: every text a view of an axis kind draws that is not silent,
// probed at the centre of its global bounding rect (rounded) where
// findHover finds that very text -- and a tenth of a pixel round it too (a
// tie the rounding decides is dropped) --, at most four per view and target
// type; each probe its point and the eventData, keys sorted (null: a text
// that answers the pointer -- tooltip.show -- and carries none).
//
// SSR svg, chart._ssr = false, animation off, a fixed clock and seed. Two
// generations must be byte-identical.
//   node tools/advchart-oracle/axis-events.js -> tests/fixtures/advchart-axis-events.json
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
global.Date = ClockDate;
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-events.json');
echarts.env.node = false;
const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};
class OracleError extends Error {}
function must(c, m) { if (!c) throw new OracleError(m); }
const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const W = 400;
const H = 300;
const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666'];
const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

let ecKey = null;
function ecDataOf(el) {
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (v && typeof v === 'object' && !Array.isArray(v) && hasOwn(v, 'seriesIndex') && hasOwn(v, 'dataIndex')) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
function sorted(o) {
  const r = {};
  Object.keys(o).sort().forEach(k => {
    const v = o[k];
    r[k] = v && typeof v === 'object' && !Array.isArray(v) ? sorted(v) : v;
  });
  return r;
}
function globalRect(el) {
  el.updateTransform && el.updateTransform();
  const r = el.getBoundingRect().clone();
  const m = el.getComputedTransform ? el.getComputedTransform() : el.transform;
  if (m) r.applyTransform(m);
  return r;
}

const cart = (xa, ya, more) => Object.assign({ animation: false, color: PAL,
  xAxis: Object.assign({ type: 'category', data: DAYS, triggerEvent: true }, xa || {}),
  yAxis: Object.assign({ type: 'value', triggerEvent: true }, ya || {}),
  series: [{ type: 'bar', data: [3000, 12000, 7000, 9000, 15000, 4000] }] }, more || {});
const RAD_IND = [{ name: 'Speed', max: 20000 }, { name: 'Power', max: 20000 }, { name: 'Range', max: 20000 },
  { name: 'Grip', max: 20000 }];
function cases() {
  return [
    ['cart.formatted', cart({ name: 'Day', axisLabel: { formatter: '<{value}>' } },
      { name: 'Revenue', max: 20000, axisLabel: { formatter: '{value} $' } })],
    ['cart.interval', cart({ axisLabel: { interval: 1, formatter: '{value}!' } }, { max: 20000 })],
    ['cart.truncated', cart({ name: 'A very long axis name indeed', nameLocation: 'middle', nameGap: 30,
      nameTruncate: { maxWidth: 60 } }, { name: 'Revenue in dollars per day', nameTruncate: { maxWidth: 40 } })],
    ['cart.time', { animation: false, color: PAL,
      xAxis: { type: 'time', triggerEvent: true, min: 1700000000000, max: 1700000000000 + 4 * 86400000,
        axisLabel: { formatter: '{MM}-{dd}!' } },
      yAxis: { type: 'log', triggerEvent: true, min: 1, max: 100000 },
      series: [{ type: 'line', data: [[1700000000000, 10], [1700000000000 + 2 * 86400000, 3000]] }] }],
    ['single.value', { animation: false, color: PAL, singleAxis: { type: 'value', max: 20000, triggerEvent: true,
      name: 'Load', top: 80, height: 100, axisLabel: { formatter: '{value} kW' } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [3000, 12000] }] }],
    ['single.category', { animation: false, color: PAL, singleAxis: { type: 'category', data: DAYS, triggerEvent: true,
      top: 80, height: 100, axisLabel: { formatter: '[{value}]' } },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [[0, 3], [2, 5]] }] }],
    ['polar.formatted', { animation: false, color: PAL, polar: { radius: [20, 120] },
      angleAxis: { type: 'category', data: DAYS, triggerEvent: true, axisLabel: { formatter: '<{value}>' } },
      radiusAxis: { max: 20000, name: 'Load', triggerEvent: true, axisLabel: { formatter: '{value} kW' } },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [3000, 12000, 7000, 9000, 15000, 4000] }] }],
    ['polar.value-angle', { animation: false, color: PAL, polar: { radius: [20, 120] },
      angleAxis: { type: 'value', max: 20000, triggerEvent: true, axisLabel: { formatter: '{value}°' } },
      radiusAxis: { type: 'category', data: ['a', 'b'] },
      series: [{ type: 'bar', coordinateSystem: 'polar', data: [3000, 12000] }] }],
    ['parallel.formatted', { animation: false, color: PAL,
      parallelAxis: [{ dim: 0, name: 'Price', max: 20000, triggerEvent: true, axisLabel: { formatter: '{value} $' } },
        { dim: 1, name: 'Grade', type: 'category', data: ['low', 'mid', 'high'], triggerEvent: true,
          axisLabel: { formatter: '<{value}>' } }],
      series: [{ type: 'parallel', data: [[3000, 'low'], [12000, 'high']] }] }],
    ['radar.formatted', { animation: false, color: PAL, radar: { indicator: RAD_IND, triggerEvent: true, radius: 90,
      axisName: { formatter: '<{value}>' }, axisLabel: { show: true, formatter: '{value}%' } },
      series: [{ type: 'radar', data: [{ value: [5000, 12000, 8000, 15000] }] }] }],
    ['radar.plain', { animation: false, color: PAL, radar: { indicator: RAD_IND, triggerEvent: true, radius: 90,
      axisLabel: { show: true } }, series: [{ type: 'radar', data: [{ value: [5000, 12000, 8000, 15000] }] }] }],
    // texts that answer the pointer and carry no eventData: a single axis' by
    // default, an indicator's own tooltip.show, a grid axis' tooltip.show
    ['quiet.single', { animation: false, color: PAL, singleAxis: { type: 'category', data: DAYS, top: 80, height: 100,
      name: 'Days' }, series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [[0, 3], [2, 5]] }] }],
    ['quiet.radar-indicator', { animation: false, color: PAL, radar: { indicator: [{ name: 'Speed', max: 10,
      tooltip: { show: true } }, { name: 'Power', max: 10, triggerEvent: true }, { name: 'Range', max: 10,
      silent: true, triggerEvent: true }], radius: 80 }, series: [{ type: 'radar', data: [{ value: [5, 6, 7] }] }] }],
    ['quiet.cart', cart({ triggerEvent: false, tooltip: { show: true } }, { triggerEvent: false, max: 20000,
      tooltip: { show: true }, name: 'Revenue' })],
    ['radar.indicator-trigger', { animation: false, color: PAL, radar: [{ indicator: [{ name: 'Speed', max: 10 },
      { name: 'Power', max: 10, triggerEvent: true }, { name: 'Range', max: 10 }], radius: 60, center: ['30%', '50%'] },
    { indicator: [{ name: 'a', max: 10 }, { name: 'b', max: 10 }, { name: 'c', max: 10 }], radius: 60,
      center: ['72%', '50%'], triggerEvent: true }],
    series: [{ type: 'radar', data: [{ value: [5, 6, 7] }] }, { type: 'radar', radarIndex: 1, data: [{ value: [5, 6, 7] }] }] }],
  ];
}

const AXIS_TYPES = ['xAxis', 'yAxis', 'singleAxis', 'angleAxis', 'radiusAxis', 'parallelAxis', 'radar'];
function run(id, option) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    // the ECData key is found on a series' element (an axis text's store has no series fields)
    chart.getZr().storage.getDisplayList(true).forEach(el => { if (ecKey === null) ecDataOf(el); });
    must(ecKey !== null, id + ': no ECData key');
    const handler = chart.getZr().handler;
    const probes = [];
    let ties = 0;
    const perKind = new Map();
    chart._componentsViews.forEach(v => {
      const m = v.__model;
      if (!m || AXIS_TYPES.indexOf(m.mainType) < 0) return;
      const own = m.mainType + m.componentIndex;
      v.group.traverse(el => {
        if (el.type !== 'text' || el.silent) return;
        const d = ecDataOf(el);
        const ev = d && d.eventData ? d.eventData : null;
        const kind = own + ' ' + (ev ? ev.targetType : (el.anid === 'name' ? 'name' : 'label'));
        const n = (perKind.get(kind) || 0) + 1;
        if (n > 4) return;
        const r = globalRect(el);
        const x = Math.round(r.x + r.width / 2);
        const y = Math.round(r.y + r.height / 2);
        if (x < 0 || y < 0 || x >= W || y >= H) return;
        const found = (px, py) => {
          // zrender's Text draws through its TSpan children
          const t = handler.findHover(px, py).target;
          return !!t && (t === el || t.parent === el);
        };
        if (![[0, 0], [-0.1, -0.1], [0.1, -0.1], [-0.1, 0.1], [0.1, 0.1]].every(o => found(x + o[0], y + o[1]))) {
          ties++;
          return;
        }
        perKind.set(kind, n);
        probes.push({ own, x, y, ev: ev ? sorted(ev) : null });
      });
    });
    return { id, option, probes, ties };
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(([id, o]) => run(id, o));
  const by = id => charts.find(c => c.id === id);
  charts.forEach(c => must(c.probes.length > 0, c.id + ': no probe'));
  // the label's value is its rawLabel, not the text drawn
  const lbl = (id, own) => by(id).probes.filter(p => p.own === own && p.ev && p.ev.targetType === 'axisLabel');
  must(lbl('cart.formatted', 'yAxis0').some(p => p.ev.value === '5,000'), 'cart.formatted: no 5,000');
  must(lbl('radar.formatted', 'radar0').some(p => p.ev.value === '4,000'), 'radar.formatted: no 4,000');
  // an angle axis' label carries no tickIndex
  must(lbl('polar.formatted', 'angleAxis0').every(p => !hasOwn(p.ev, 'tickIndex')), 'polar.formatted: a tickIndex');
  // the indicator's own triggerEvent wakes only its own texts on the first radar
  must(by('radar.indicator-trigger').probes.filter(p => p.own === 'radar0').every(p =>
    p.ev && (p.ev.targetType !== 'axisName' || p.ev.name === 'Power')), 'radar.indicator-trigger: another name');
  // the quiet texts carry none
  must(by('quiet.single').probes.length > 0 && by('quiet.single').probes.every(p => p.ev === null), 'quiet.single');
  must(by('quiet.cart').probes.every(p => p.ev === null), 'quiet.cart');
  must(by('quiet.radar-indicator').probes.some(p => p.ev === null)
    && by('quiet.radar-indicator').probes.some(p => p.ev && p.ev.name === 'Power')
    && !by('quiet.radar-indicator').probes.some(p => p.ev && p.ev.name === 'Range'), 'quiet.radar-indicator');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-I: per case, every axis text with an eventData at its rect\'s centre where findHover finds it '
      + '(a tenth of a pixel round too), at most four per view and target type: the point and the eventData.',
    W, H, charts };
}

let j1, j2;
try {
  j1 = JSON.stringify(generate(), null, 1) + '\n';
  j2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (j1 !== j2) { console.log('FAILED: two generations differ'); process.exit(1); }
fs.writeFileSync(OUT, j1);
console.log('wrote', OUT, j1.length, 'bytes');
process.exit(0);
