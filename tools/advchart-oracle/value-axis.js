// Upstream's own answers for a value axis: the extent it settles on, the step,
// every tick and minor tick, and whether the axis was turned round.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode over a scatter (or a bar) on yAxis[0]
// and reads the axis' scale back: getExtent(), getConfig().interval, getTicks()
// and getMinorTicks(). The port is held to these exactly -- the step and every
// tick are short decimals once rounded the way upstream rounds them, and a
// transcription that rounds the same way lands on the same Doubles.
//
//   node tools/advchart-oracle/value-axis.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// The development build asserts its own invariants and throws where the
// production build carries on; a case that trips one is run through the
// production build instead, which is what a page actually ships, and says so.
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-value-axis.json');

// `c.yAxis` holds the options of the axis under test, which is yAxis[0] --
// or xAxis[0] when `c.axis` is 'x': then a scatter's values go on x, and a
// bar lies down along it.
function run(c, lib) {
  const chart = (lib || echarts).init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
  try {
    const type = c.series || 'scatter';
    const onX = c.axis === 'x';
    const data = type === 'bar' ? c.values : c.values.map((v, i) => (onX ? [v, i] : [i, v]));
    const other = type === 'bar' ? { type: 'category', data: c.values.map((_, i) => 'c' + i) } : { type: 'value' };
    const tested = Object.assign({ type: 'value' }, c.yAxis);
    const option = {
      animation: false,
      xAxis: onX ? tested : other,
      yAxis: onX ? other : tested,
      series: [{ type, data }],
    };
    if (c.root) Object.assign(option, c.root);
    chart.setOption(option);
    const axis = chart.getModel().getComponent(onX ? 'xAxis' : 'yAxis', 0).axis;
    const sc = axis.scale;
    const isTime = c.yAxis.type === 'time';
    const cfg = isTime ? {} : sc.getConfig ? sc.getConfig() : (sc.intervalStub ? sc.intervalStub.getConfig() : {});
    const minorSplit = c.yAxis.minorTick && c.yAxis.minorTick.splitNumber;
    return {
      name: c.name,
      option,
      axis: onX ? 'x' : 'y',
      log: c.yAxis.type === 'log',
      blank: sc.isBlank(),
      extent: sc.getExtent(),
      interval: cfg.interval,
      ticks: sc.getTicks().map(t => t.value),
      minor: c.yAxis.minorTick ? sc.getMinorTicks(minorSplit || 5) : null,
      inverse: !!axis.inverse,
    };
  } finally {
    chart.dispose();
  }
}

const cases = [];
const add = (name, values, yAxis, extra) => cases.push(Object.assign({ name, values, yAxis: yAxis || {} }, extra || {}));

// ---------- the structured rows (after the batch-33 map's probe) ----------
add('5..7', [5, 7]);
add('0..5374', [0, 5374]);
add('393..5374', [393, 5374]);
add('0..100', [0, 100]);
add('0..7.5', [0, 7.5]);
add('0..11', [0, 11]);
add('0..12.5', [0, 12.5]);
add('0..17', [0, 17]);
add('0..34.9', [0, 34.9]);
add('-5..-2', [-5, -2]);
add('-37..82', [-37, 82]);
add('-1234..-56', [-1234, -56]);
add('-1.2e9..0', [-1.2e9, 0]);
add('0.1..0.37', [0.1, 0.37]);
add('0.001..0.0047', [0.001, 0.0047]);
add('0..1.2e9', [0, 1.2e9]);
add('single 42', [42]);
add('single 0', [0]);
add('single -42', [-42]);
add('5..7 scale', [5, 7], { scale: true });
add('393..5374 scale', [393, 5374], { scale: true });
add('0.1..0.3 scale', [0.1, 0.3], { scale: true });
add('0.7..0.9 scale', [0.7, 0.9], { scale: true });
add('3.2e8..1.2e9 scale', [3.2e8, 1.2e9], { scale: true });
add('1000..1000.5 scale', [1000, 1000.5], { scale: true });
add('single 42 scale', [42], { scale: true });
add('single 0 scale', [0], { scale: true });
add('single 0.001 scale', [0.001], { scale: true });
add('tiny values', [1e-25, 3e-25]);
add('tiny values, scale', [1.1e-19, 1.7e-19], { scale: true });
add('startValue 3.3, scale', [5, 7], { scale: true, startValue: 3.3 });
add('startValue -2, bars', [5, 7], { startValue: -2 }, { series: 'bar' });
add('one ulp apart', [1e9, 1000000000.0000001], { scale: true });
add('min 3 max 3.0000000000000004', [3], { min: 3, max: 3.0000000000000004 });
add('min 0 max 10', [5, 7], { min: 0, max: 10 });
add('min 4', [5, 7], { min: 4 });
add('min 3.3', [5, 7], { min: 3.3 });
add('max 9.3', [5, 7], { max: 9.3 });
add('max 3', [5, 7], { max: 3 });
add('max -1', [5, 7], { max: -1 });
add('min 10', [5, 7], { min: 10 });
add('min 8 max 2', [5, 7], { min: 8, max: 2 });
add('min 8 max 2, legacy', [5, 7], { min: 8, max: 2 }, { root: { legacyMinMaxDontInverseAxis: true } });
add('min = max = 100', [100], { min: 100, max: 100 });
add('100, scale, max 100', [100], { scale: true, max: 100 });
add('min as a string', [5, 7], { min: '4' });
add('dataMin', [5, 7], { min: 'dataMin' });
add('dataMin and dataMax', [393, 5374], { min: 'dataMin', max: 'dataMax' });
add('option dataMin', [5, 7], { dataMin: -10 });
add('option dataMax, scale', [5, 7], { scale: true, dataMax: 20 });
add('startValue 3, scale', [5, 7], { scale: true, startValue: 3 });
add('startValue 3', [5, 7], { startValue: 3 });
add('startValue 9.3, scale', [5, 7], { scale: true, startValue: 9.3 });
add('gap 10%', [2, 8], { boundaryGap: ['10%', '10%'] });
add('gap 10%, scale', [2, 8], { scale: true, boundaryGap: ['10%', '10%'] });
add('gap numbers, scale', [0, 100], { scale: true, boundaryGap: [0.1, 0.2] });
add('gap on a single value', [42], { scale: true, boundaryGap: ['20%', '20%'] });
add('gap scalar', [2, 8], { scale: true, boundaryGap: '10%' });
add('gap and a min', [2, 8], { scale: true, min: 1, boundaryGap: ['50%', '50%'] });
add('gap strings without %', [2, 8], { scale: true, boundaryGap: ['1', '0'] });
add('split 3', [0, 5374], { splitNumber: 3 });
add('split 10', [0, 5374], { splitNumber: 10 });
add('split 0', [0, 100], { splitNumber: 0 });
add('split 2.5', [0, 100], { splitNumber: 2.5 });
add('minInterval 1', [0, 3], { minInterval: 1 });
add('minInterval 1 on 0..0.5', [0, 0.5], { minInterval: 1 });
add('maxInterval 500', [0, 5374], { maxInterval: 500 });
add('maxInterval 7', [0, 100], { maxInterval: 7 });
add('interval 0.7', [5, 7], { interval: 0.7 });
add('interval 1000', [0, 5374], { interval: 1000 });
add('interval 30', [0, 97], { interval: 30 });
add('interval 7', [0, 97], { interval: 7 });
add('interval 30 min 3', [0, 97], { interval: 30, min: 3 });
add('interval 3, scale', [5, 7], { scale: true, interval: 3 });
add('no data', []);
add('no data, max 100', [], { max: 100 });
add('no data, min 0 max 100', [], { min: 0, max: 100 });
add('no data, dataMin -10, min dataMin', [], { dataMin: -10, min: 'dataMin', max: 100 });
add('log, no data', [], { type: 'log' });
add('log, only negatives', [-5, -3], { type: 'log' });
add('pinned min 3.7', [3.7, 91.2], { min: 3.7 });
add('pinned max 93', [0, 91.2], { max: 93 });
// minor ticks
add('minor 5', [0, 97], { minorTick: { show: true } });
add('minor with pinned ends', [3, 93], { min: 3, max: 93, minorTick: { show: true, splitNumber: 4 } });
add('minor on a step of 3', [0, 13.2], { minorTick: { show: true, splitNumber: 5 } });
add('minor thirds', [0, 97], { minorTick: { show: true, splitNumber: 3 } });
add('minor sevenths', [0, 0.97], { minorTick: { show: true, splitNumber: 7 } });
add('minor thirds, pinned', [-0.3, 1.7], { min: -0.37, max: 1.93, minorTick: { show: true, splitNumber: 3 } });
add('log minor thirds', [2, 30000], { type: 'log', minorTick: { show: true, splitNumber: 3 } });
// log
add('log 1..1e8', [1, 1e8], { type: 'log' });
add('log 1..100', [1, 100], { type: 'log' });
add('log 3..4700', [3, 4700], { type: 'log' });
add('log 0.02..300', [0.02, 300], { type: 'log' });
add('log pinned min 5', [7, 4700], { type: 'log', min: 5 });
add('log minors', [1, 1000], { type: 'log', minorTick: { show: true } });
add('log bars', [100, 1000, 4000], { type: 'log' }, { series: 'bar' });
add('log 3..20', [3, 20], { type: 'log' });
add('log split 1', [1, 1e6], { type: 'log', splitNumber: 1 });
add('log split 2, wide', [1e-3, 1e9], { type: 'log', splitNumber: 2 });
add('log base 2', [1, 1000], { type: 'log', logBase: 2 });
add('log base 2, minors', [3, 100], { type: 'log', logBase: 2, minorTick: { show: true, splitNumber: 4 } });
add('log min 0', [1, 100], { type: 'log', min: 0 });
add('log with a zero datum', [0, 10, 100], { type: 'log' });
add('log pinned max 3000', [2, 700], { type: 'log', max: 3000 });
add('log split 1, two decades', [1, 100], { type: 'log', splitNumber: 1 });
add('log max 0', [3, 700], { type: 'log', max: 0 });
add('log min 0 max 2', [3, 700], { type: 'log', min: 0, max: 2 });
// bars on a value axis
add('bars 5..7', [5, 7], {}, { series: 'bar' });
add('bars 5..7 scale', [5, 7], { scale: true }, { series: 'bar' });

// ---------- after batch 33's mutation run and audit ----------
// the log falls short of an exact power from 1e26 up, and toFixed keeps it
add('0..5e27, the log falls short of 1e27', [0, 5e27]);
// a written interval rounds at its own precision
add('interval 0.125, finer than the auto step', [5, 7], { interval: 0.125 });
add('interval 1, coarser than a pinned min', [0, 3], { min: 0.001, interval: 1 });
// a log end nicing did not move is read back as it came in, pinned or not
add('log pinned min 3', [7, 4700], { type: 'log', min: 3 });
add('log data min a hair over 10', [10.000000000000002, 5000], { type: 'log' });
add('log data max a hair over 100', [2, 100.00000000000001], { type: 'log' });
// both ends at or under zero on a log axis, no reversal
add('log min -5 max 0', [100, 700], { type: 'log', min: -5, max: 0 });
// value x axes: a bar lying down, a scatter's x
add('hbar 5, 7, 9', [5, 7, 9], {}, { series: 'bar', axis: 'x' });
add('hbar 5, 7, 9, scale', [5, 7, 9], { scale: true }, { series: 'bar', axis: 'x' });
add('x: 393..5374', [393, 5374], {}, { axis: 'x' });
add('x: -37..82, min 8 max 2', [-37, 82], { min: 8, max: 2 }, { axis: 'x' });
add('x: log 3..4700', [3, 4700], { type: 'log' }, { axis: 'x' });
add('x: no data', [], {}, { axis: 'x' });
// stacks: the axis sees the totals
const cats3 = { type: 'category', data: ['a', 'b', 'c'] };
add('stacked bars', [0], {}, { root: { xAxis: cats3, series: [
  { type: 'bar', stack: 's', data: [5, 7, 3] }, { type: 'bar', stack: 's', data: [3, 4, 9] }] } });
add('stacked bars, mixed signs', [0], {}, { root: { xAxis: cats3, series: [
  { type: 'bar', stack: 's', data: [5, -7, 3] }, { type: 'bar', stack: 's', data: [-3, 4, 9] }] } });
add('stacked lines, scale', [0], { scale: true }, { root: { xAxis: cats3, series: [
  { type: 'line', stack: 's', data: [50, 57, 53] }, { type: 'line', stack: 's', data: [3, 4, 9] }] } });
add('stacked bars lying down', [0], {}, { axis: 'x', root: { yAxis: cats3, series: [
  { type: 'bar', stack: 's', data: [5, 7, 3] }, { type: 'bar', stack: 's', data: [3, 4, 9] }] } });
// time axes, in this machine's own zone as both sides read it
const day = (y, m, d) => new Date(y, m - 1, d).getTime();
const twoWeeks = [day(2024, 3, 4), day(2024, 3, 18)];
add('time flat', [day(2024, 3, 4)], { type: 'time' }, { axis: 'x' });
add('time two weeks', twoWeeks, { type: 'time' }, { axis: 'x' });
add('time minInterval four days', twoWeeks, { type: 'time', minInterval: 4 * 864e5 }, { axis: 'x' });
add('time maxInterval a day', twoWeeks, { type: 'time', maxInterval: 864e5 }, { axis: 'x' });
add('time gap 10%', twoWeeks, { type: 'time', boundaryGap: ['10%', '10%'] }, { axis: 'x' });
add('time startValue', twoWeeks, { type: 'time', startValue: day(2024, 2, 1) }, { axis: 'x' });
add('time dataMax', twoWeeks, { type: 'time', dataMax: day(2024, 4, 1) }, { axis: 'x' });
add('bars on a time value axis', twoWeeks, { type: 'time' }, { series: 'bar' });

// ---------- random rows ----------
let s = 20260921;
function rnd() { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }
function pick(a) { return a[Math.floor(rnd() * a.length)]; }
function num() {
  const mag = Math.pow(10, Math.floor(rnd() * 12) - 4);
  return Math.round((rnd() * 2 - (rnd() < 0.3 ? 1 : 0)) * mag * 1000) / 1000;
}
for (let i = 0; i < 400; i++) {
  const n = 1 + Math.floor(rnd() * 5);
  const values = Array.from({ length: n }, num);
  const y = {};
  if (rnd() < 0.35) y.scale = true;
  if (rnd() < 0.15) y.min = rnd() < 0.3 ? 'dataMin' : num();
  if (rnd() < 0.15) y.max = rnd() < 0.3 ? 'dataMax' : num();
  if (rnd() < 0.15) y.splitNumber = pick([0, 1, 2, 2.5, 3, 4, 6, 7, 10]);
  if (rnd() < 0.1) y.boundaryGap = [pick(['10%', '0%', '25%', 0.05, '3']), pick(['10%', '50%', 0.2, 0])];
  if (rnd() < 0.08) y.minInterval = pick([1, 0.5, 10, 100]);
  if (rnd() < 0.08) y.maxInterval = pick([1, 5, 50, 1000]);
  if (rnd() < 0.06) y.interval = pick([0.5, 1, 3, 7, 25, 100]);
  if (rnd() < 0.05) y.startValue = num();
  if (rnd() < 0.05) y.dataMin = num();
  if (rnd() < 0.15) y.minorTick = { show: true, splitNumber: pick([2, 4, 5]) };
  add('random ' + i, values, y);
}

function runEither(c) {
  try {
    return run(c);
  } catch (e) {
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

const out = { source: 'ECharts ' + echarts.version, cases: cases.map(runEither) };
const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote', OUT, out.cases.length, 'cases');
process.exit(0);
