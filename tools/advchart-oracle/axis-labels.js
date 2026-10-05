// Upstream's own answers for the text a value or log axis puts on screen: the
// tick labels, IntervalScale.getLabel at a given precision, the axis pointer's
// label, and the header line of an axis-triggered tooltip.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode. Every one of these strings comes out
// of IntervalScale.getLabel (a log scale hands it to its interval stub): the
// precision is either given, 'auto' (the step's precision plus two) or read off
// the value itself, then toFixed and thousands commas. The port is held to these
// strings exactly.
//
//   ticks     axis.getViewLabels() on xAxis[0] or yAxis[0], in order: the
//             formattedLabel and the tick value behind it. drawnInNode says
//             whether the Text element built for that label (found by its anid,
//             'label_' + tick value) is left un-ignored. It is information only:
//             overlap hiding measures text, and node measures with an estimate,
//             not a font.
//   getLabel  axis.scale.getLabel({ value }, opt) called directly, opt left out
//             when the precision is null.
//   pointer   the tested axis' axisPointer shown at a fixed value. The text is
//             whatever Text element the pointer adds to the scene: the multiset
//             difference of every Text's style.text with and without the
//             pointer. A case that does not add exactly one string is reported
//             and left out. The value recorded is the one the option asks for;
//             upstream clamps it into the scale's extent before labelling it.
//   header    the tooltip never renders under node (TooltipView bails on
//             env.node or on a missing DOM), so for these cases env.node is
//             switched off and the chart prototype's getDom answers a bare
//             object. The ExtensionAPI binds getDom when the chart is built,
//             hence the prototype, before init. A richText tooltip with a
//             formatter callback then hands over params[0].axisValueLabel --
//             the header text -- and params[0].axisValue, which is checked
//             against the value the showtip event carried.
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside them, because the Pascal JSON reader
// misparses integer literals above 2^63. For the same reason a number of that
// size inside an option is written in exponent form (3e+20, not
// 300000000000000000000), which JSON allows and JSON.stringify never picks
// below 1e21. The readable twin of -0 is '-0'.
//
//   node tools/advchart-oracle/axis-labels.js
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
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-labels.json');

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));

function init(lib) {
  return lib.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
}

const clone = o => JSON.parse(JSON.stringify(o));

// The axis under test is xAxis[0] when c.axis is 'x', yAxis[0] otherwise. The
// other axis is a category axis over the values, so a line (or a bar lying
// down, when x is tested) puts each value on the tested axis. c.data replaces
// the series data outright and c.other the other axis, for the scatter cases.
function buildOption(c, tested) {
  const onX = c.axis === 'x';
  const type = c.series || (onX ? 'bar' : 'line');
  const cats = { type: 'category', data: c.values.map((_, i) => String.fromCharCode(97 + i)) };
  const other = c.other ? clone(c.other) : cats;
  const option = {
    animation: false,
    xAxis: onX ? tested : other,
    yAxis: onX ? other : tested,
    series: [{ type, data: c.data ? clone(c.data) : c.values.slice() }],
  };
  if (c.root) Object.assign(option, clone(c.root));
  return option;
}

function testedAxis(chart, c) {
  return chart.getModel().getComponent(c.axis === 'x' ? 'xAxis' : 'yAxis', 0);
}

// Every Text in the tree, with whether it or a group above it is ignored. A
// displayable's attached label (textContent) is not a child in the tree, so it
// is walked too.
function collectTexts(root, out, ignoredAbove) {
  const ignored = ignoredAbove || !!root.ignore;
  if (root.isGroup) {
    root.eachChild(ch => collectTexts(ch, out, ignored));
    return out;
  }
  if (root.type === 'text') out.push({ el: root, text: root.style.text, ignored });
  const tc = root.getTextContent && root.getTextContent();
  if (tc) collectTexts(tc, out, ignored);
  return out;
}

function sceneTexts(chart) {
  const out = [];
  chart.getZr().storage.getRoots().forEach(r => collectTexts(r, out, false));
  return out.map(t => t.text);
}

// ---------- ticks ----------

function runTicks(c, lib) {
  const chart = init(lib);
  try {
    const tested = Object.assign({ type: 'value' }, clone(c.tested));
    const option = buildOption(c, tested);
    chart.setOption(option);
    const axisModel = testedAxis(chart, c);
    const labels = axisModel.axis.getViewLabels();
    const els = collectTexts(chart.getViewOfComponentModel(axisModel).group, [], false);
    const drawn = labels.map(l => {
      const hit = els.find(t => t.el.anid === 'label_' + l.tick.value);
      if (!hit) throw new Error(c.name + ': no Text element for the label at ' + l.tick.value);
      if (hit.text !== l.formattedLabel) {
        throw new Error(c.name + ': the Text at ' + l.tick.value + ' says ' + JSON.stringify(hit.text));
      }
      return !hit.ignored;
    });
    return {
      name: c.name,
      option,
      axis: c.axis === 'x' ? 'x' : 'y',
      values: labels.map(l => hex(l.tick.value)),
      valuesText: labels.map(l => text(l.tick.value)),
      labels: labels.map(l => l.formattedLabel),
      drawnInNode: drawn,
    };
  } finally {
    chart.dispose();
  }
}

const ticks = [];
const tick = (name, values, tested, extra) => ticks.push(Object.assign({ name, values, tested: tested || {} }, extra || {}));

// thousands commas, both signs
tick('0..1234567', [0, 1234567]);
tick('-5000..5000', [-5000, 5000]);
tick('-2500000..100', [-2500000, 100]);
// decimals
tick('0.1..0.7', [0.1, 0.7]);
tick('-0.35..0.05', [-0.35, 0.05]);
tick('-2.5..-0.5', [-2.5, -0.5]);
tick('-0.0035..-0.0005', [-0.0035, -0.0005]);
// pinned ends carry their own precision, the steps between keep theirs
tick('min 1.2345 max 9.87', [3, 7], { min: 1.2345, max: 9.87 });
tick('min 3.7, 5..50', [5, 50], { min: 3.7 });
tick('dataMin on 1/3..2', [1 / 3, 2], { min: 'dataMin' });
tick('dataMin on 0.0007695205211639404..0.002', [0.0007695205211639404, 0.002], { min: 'dataMin' });
// tiny steps: toFixed keeps them out of exponent form
tick('0..7e-7', [0, 7e-7]);
tick('0..3.5e-8', [0, 3.5e-8]);
tick('-3e-9..0', [-3e-9, 0]);
// two neighbouring Doubles
tick('dataMin dataMax on 1e9..1000000000.0000002', [1e9, 1000000000.0000002], { min: 'dataMin', max: 'dataMax' });
// huge: toFixed turns to exponent form from 1e21 up
tick('0..3e20', [0, 3e20]);
tick('0..5e21', [0, 5e21]);
tick('0..5e27', [0, 5e27]);
// log: the step is in exponents, the labels are the powers
tick('log 1..1e5', [1, 1e5], { type: 'log' });
tick('log base 2, 1..1000', [1, 1000], { type: 'log', logBase: 2 });
tick('log dataMin dataMax 3.7..7777.7', [3.7, 7777.7], { type: 'log', min: 'dataMin', max: 'dataMax' });
tick('log 1e-7..1', [1e-7, 1], { type: 'log' });
tick('log 1..1e25', [1, 1e25], { type: 'log' });
// every decade, so the commas run up to 1e20 and exponent form starts at 1e21
tick('log 1..1e25 interval 1', [1, 1e25], { type: 'log', interval: 1 });
// value x axes
tick('x: hbar 0..1234567', [0, 1234567], {}, { axis: 'x' });
tick('x: scatter 0..1234567', [0, 1234567], {}, {
  axis: 'x', series: 'scatter', data: [[0, 1], [1234567, 2]], other: { type: 'value' },
});
// formatter templates: only the first '{value}' is replaced, the rest is kept
// as written ('$' patterns in the template are not special -- the template is
// the subject of the replace, not the replacement)
tick('template {value} kg', [0, 1234567], { axisLabel: { formatter: '{value} kg' } });
tick('template, first {value} only', [0, 1234567], { axisLabel: { formatter: '{value} kg / {value}' } });
tick('template empty', [0, 1234567], { axisLabel: { formatter: '' } });
tick('template with a line break', [0, 1234567], { axisLabel: { formatter: '{value}\nkg' } });
tick('template with dollar patterns', [0, 1234567], { axisLabel: { formatter: '$$ {value} $& $1' } });
tick('template, only the exact {value}', [0, 1234567], { axisLabel: { formatter: '{VALUE}|{ value }|{value}' } });
tick('log dataMin dataMax 3.7..7777.7, template', [3.7, 7777.7], {
  type: 'log', min: 'dataMin', max: 'dataMax', axisLabel: { formatter: '{value} ms' },
});
// a written step with its own precision
tick('interval 0.7 on 0..5', [0, 5], { interval: 0.7 });
tick('min 0 max 5 interval 0.7', [0, 5], { min: 0, max: 5, interval: 0.7 });
// decimals past the thousands
tick('scale 1000..1000.5', [1000, 1000.5], { scale: true });
tick('scale 1234567.5..1234568', [1234567.5, 1234568], { scale: true });

// ---------- getLabel ----------

// Each chart pins the step, and so the precision 'auto' stands for.
const charts = {
  'interval 1': { values: [0, 5], tested: { interval: 1 } },
  'interval 0.5': { values: [0, 5], tested: { interval: 0.5 } },
  'interval 0.05': { values: [0, 0.3], tested: { interval: 0.05 } },
  'interval 1e-7': { values: [0, 5e-7], tested: { interval: 1e-7 } },
  'log 1..1e4': { values: [1, 1e4], tested: { type: 'log' } },
  'log interval 0.5': { values: [1, 100], tested: { type: 'log', interval: 0.5 } },
};

function runGetLabel(c, lib) {
  const chart = init(lib);
  try {
    const ch = charts[c.chart];
    const tested = Object.assign({ type: 'value' }, clone(ch.tested));
    const option = buildOption({ values: ch.values }, tested);
    chart.setOption(option);
    const scale = testedAxis(chart, {}).axis.scale;
    const got = scale.getLabel({ value: c.value }, c.precision === null ? undefined : { precision: c.precision });
    return {
      name: c.chart + ': ' + JSON.stringify(c.precision) + ' ' + text(c.value),
      option,
      axis: 'y',
      value: hex(c.value),
      valueText: text(c.value),
      precision: c.precision,
      text: got,
    };
  } finally {
    chart.dispose();
  }
}

const getLabels = [];
const label = (chart, precision, values) => values.forEach(value => getLabels.push({ chart, precision, value }));
const allValues = [0, -0, 1.005, 2.5, -2.5, 0.125, 1e-7, 1.23456789e-7, 37.246964, 1234.4, 552941.17647,
  -0.0001, 1e21, 1.5e21, 3.3e25];

// the value's own precision; the chart does not matter
label('interval 1', null, allValues);
// the step's precision plus two
label('interval 1', 'auto', allValues);
label('interval 0.5', 'auto', [0, 2.5, 0.125, 37.246964, 1234.4, -0.0001]);
label('interval 0.05', 'auto', [1.005, 0.125, 37.246964, 552941.17647, -0.0001]);
label('interval 1e-7', 'auto', [0, 0.125, 1e-7, 1.23456789e-7]);
// given outright: clamped to 0..20, truncated by toFixed, NaN left unrounded
label('interval 1', 0, [-0, 2.5, -2.5, 0.125, -0.0001, 552941.17647, 1e21]);
label('interval 1', 1, [1.005, 0.125, -0.0001, 37.246964, 1.5e21]);
label('interval 1', 3, [1.005, 1234.4, 1.23456789e-7, 3.3e25]);
label('interval 1', 20, [1.005, 0.125, 1e-7, 1e21, 3.3e25]);
label('interval 1', 25, [1.005, 2.5, 1.23456789e-7]);
label('interval 1', -1, [2.5, 37.246964, 1234.4]);
label('interval 1', 2.7, [-2.5, 1.005, 37.246964]);
label('interval 1', '3', [1.005, 1234.4]);
label('interval 1', 'abc', [-0, 1.005, 1234.4, 1e21]);
// log: the stub's step is in exponents
label('log 1..1e4', null, [3.7, 12345.678]);
label('log 1..1e4', 'auto', [3.7, 12345.678, 1e4]);
label('log interval 0.5', 'auto', [3.7, 12345.678]);

// ---------- pointer ----------

function runPointer(c, lib) {
  const onX = c.axis === 'x';
  const texts = withPointer => {
    const chart = init(lib);
    try {
      const tested = Object.assign({ type: 'value' }, clone(c.tested));
      if (withPointer) {
        tested.axisPointer = { show: true, status: 'show', value: c.value, label: Object.assign({ show: true }, c.label) };
      }
      const option = buildOption(c, tested);
      chart.setOption(option);
      return { option, texts: sceneTexts(chart) };
    } finally {
      chart.dispose();
    }
  };
  const on = texts(true);
  const off = texts(false);
  const rest = off.texts.slice();
  const added = [];
  for (const t of on.texts) {
    const i = rest.indexOf(t);
    if (i >= 0) rest.splice(i, 1);
    else added.push(t);
  }
  if (added.length !== 1 || rest.length) {
    return { skipped: c.name + ': the pointer added ' + JSON.stringify(added) + ' and took away ' + JSON.stringify(rest) };
  }
  return {
    name: c.name,
    option: on.option,
    axis: onX ? 'x' : 'y',
    value: hex(c.value),
    valueText: text(c.value),
    text: added[0],
  };
}

const pointers = [];
const pointer = (name, values, tested, value, label, extra) =>
  pointers.push(Object.assign({ name, values, tested: tested || {}, value, label: label || {} }, extra || {}));

pointer('0..100, 37.246964', [0, 100], {}, 37.246964);
pointer('0..5, 3', [0, 5], {}, 3);
pointer('0..5000, 1234.4', [0, 5000], {}, 1234.4);
pointer('0..1234567, 552941.17647', [0, 1234567], {}, 552941.17647);
pointer('step 0.05 (0..0.3), 0.123', [0, 0.3], {}, 0.123);
pointer('step 1e-7 (0..5e-7), 1.23456789e-7', [0, 5e-7], {}, 1.23456789e-7);
pointer('log 1..1e4, 3.7', [1, 1e4], { type: 'log' }, 3.7);
// past the end: the axis view clamps the pointer's value into the scale's
// extent before anything is drawn (axisPointer modelHelper.fixValue), so this
// one reads 10,000
pointer('log 1..1e4, 12345.678', [1, 1e4], { type: 'log' }, 12345.678);
pointer('0..100, 150 past the max', [0, 100], {}, 150);
pointer('0..100, -5 under the min', [0, 100], {}, -5);
pointer('log interval 0.5, 3.7', [1, 100], { type: 'log', interval: 0.5 }, 3.7);
pointer('interval 0.7 (0..5), 1.23456', [0, 5], { interval: 0.7 }, 1.23456);
pointer('precision 0', [0, 100], {}, 37.246964, { precision: 0 });
pointer('precision 3', [0, 100], {}, 37.246964, { precision: 3 });
pointer('precision 25', [0, 100], {}, 37.246964, { precision: 25 });
pointer("precision 'abc'", [0, 100], {}, 37.246964, { precision: 'abc' });
pointer('formatter, first {value} only', [0, 100], {}, 37.246964, { formatter: 'v={value} {value}' });
pointer('formatter empty, ignored', [0, 100], {}, 37.246964, { formatter: '' });
// the axis' own null falls through to the tooltip's axisPointer, which only
// cascades onto the axis the tooltip triggers on: x, under a scatter
pointer('cascade: tooltip precision 1 under the axis null', [0, 100], {}, 37.246964, { precision: null }, {
  axis: 'x', series: 'scatter', data: [[0, 1], [100, 2]], other: { type: 'value' },
  root: { tooltip: { trigger: 'axis', axisPointer: { label: { precision: 1 } } } },
});
pointer('cascade: root axisPointer precision 3', [0, 100], {}, 37.246964, {}, {
  root: { axisPointer: { label: { precision: 3 } } },
});
pointer('0..5e21, 1e21', [0, 5e21], {}, 1e21);
pointer('-1..1, -0.0001', [-1, 1], {}, -0.0001);

// ---------- header ----------

// Makes one library render tooltips under node for the length of fn: env.node
// off, getDom answering on the prototype. Put back whatever happens.
function withTooltips(lib, fn) {
  const probe = init(lib);
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const getDom = proto.getDom;
  const wasNode = lib.env.node;
  const dom = {};
  proto.getDom = function () { return dom; };
  lib.env.node = false;
  try {
    return fn();
  } finally {
    proto.getDom = getDom;
    lib.env.node = wasNode;
  }
}

function runHeader(c, lib) {
  return withTooltips(lib, () => {
    const chart = init(lib);
    try {
      const captured = [];
      const shown = [];
      const tested = Object.assign({ type: 'value' }, clone(c.tested));
      const option = buildOption(Object.assign({ axis: 'x', series: 'scatter', other: { type: 'value' } }, c), tested);
      option.tooltip = Object.assign({}, clone(c.tooltip || {}), {
        trigger: 'axis',
        renderMode: 'richText',
        formatter: ps => {
          captured.push(ps.map(p => ({ label: p.axisValueLabel, value: p.axisValue })));
          return '';
        },
      });
      chart.on('showtip', e => {
        (e.dataByCoordSys || []).forEach(cs => cs.dataByAxis.forEach(a => shown.push(a.value)));
      });
      chart.setOption(option);
      const x = chart.convertToPixel({ xAxisIndex: 0 }, c.at);
      const rect = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
      const y = rect.y + rect.height / 2;
      chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x, y });
      if (captured.length !== 1 || !captured[0].length) {
        return { skipped: c.name + ': the formatter saw ' + JSON.stringify(captured) };
      }
      const got = captured[0][0];
      if (shown.length !== 1 || !Object.is(shown[0], got.value)) {
        return { skipped: c.name + ': showtip carried ' + JSON.stringify(shown) + ', the formatter ' + got.value };
      }
      return {
        name: c.name,
        option,
        axis: 'x',
        value: hex(got.value),
        valueText: text(got.value),
        text: got.label,
        noHeader: !String(got.label).trim(),
      };
    } finally {
      chart.dispose();
    }
  });
}

const headers = [];
const header = (name, tested, extra) => headers.push(Object.assign({
  name, values: [1, 3.25, 7], data: [[1, 5], [3.25, 6], [7, 2]], tested: Object.assign({ min: 0, max: 10 }, tested), at: 3.25,
}, extra || {}));

header('0..10, 3.25', {});
header('0..10 interval 0.5, 3.25', { interval: 0.5 });
header('xAxis formatter x={value}', { axisPointer: { label: { formatter: 'x={value}' } } });
header('tooltip formatter <{value}>', {}, { tooltip: { axisPointer: { label: { formatter: '<{value}>' } } } });
header('root formatter R{value}', {}, { root: { axisPointer: { label: { formatter: 'R{value}' } } } });
header('formatter of blanks, no header', { axisPointer: { label: { formatter: '   ' } } });
header('root precision 3', {}, { root: { axisPointer: { label: { precision: 3 } } } });
header('xAxis precision 0 over tooltip 1', { axisPointer: { label: { precision: 0 } } }, {
  tooltip: { axisPointer: { label: { precision: 1 } } },
});
header('xAxis precision null under tooltip 1', { axisPointer: { label: { precision: null } } }, {
  tooltip: { axisPointer: { label: { precision: 1 } } },
});
header('0..1234567, 552941.17647', { min: undefined, max: undefined }, {
  values: [0, 552941.17647, 1234567], data: [[0, 1], [552941.17647, 2], [1234567, 3]], at: 552941.17647,
});
header('log 1..1e4, 3.7', { type: 'log', min: undefined, max: undefined }, {
  values: [1, 3.7, 1e4], data: [[1, 1], [3.7, 2], [1e4, 3]], at: 3.7,
});

// ---------- run and write ----------

function runEither(run, c) {
  try {
    return run(c, echarts);
  } catch (e) {
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

const skipped = [];
function runAll(run, list) {
  const out = [];
  for (const c of list) {
    const r = runEither(run, c);
    if (r.skipped) skipped.push(r.skipped);
    else out.push(r);
  }
  return out;
}

const out = {
  source: 'ECharts ' + echarts.version,
  ticks: runAll(runTicks, ticks),
  getLabel: runAll(runGetLabel, getLabels),
  pointer: runAll(runPointer, pointers),
  header: runAll(runHeader, headers),
};

// A number JSON.stringify would write as an integer literal past 2^63 goes
// out in exponent form instead: marked in the replacer, unquoted afterwards.
const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

for (const s of ['ticks', 'getLabel', 'pointer', 'header']) {
  const prod = out[s].filter(c => c.productionBuild).map(c => c.name);
  if (prod.length) console.log(s + ' through the production build:', prod.join(', '));
}
for (const s of skipped) console.log('skipped', s);
fs.writeFileSync(OUT, json + '\n');
console.log('wrote', OUT, Object.keys(out).filter(k => k !== 'source').map(k => k + ' ' + out[k].length).join(', '));
process.exit(0);
