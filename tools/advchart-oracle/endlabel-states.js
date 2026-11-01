// Upstream's own answers for a line's endLabel under its polyline's states
// (chart/line/LineView.ts _initOrUpdateEndLabel: anyStateShowEndLabel builds
// the label where any state shows it, setLabelStyle with the endLabel's
// state models -- a state's show, else the normal one -- and its colour).
//
// Runs the real ECharts 6.1 build in node's server-side mode (SVG renderer),
// renders once, then dispatches each payload, runs a frame and reads the
// end label (the polyline's text content) again.
//
//   node tools/advchart-oracle/endlabel-states.js
//
// writes tests/fixtures/advchart-endlabel-states.json (ORACLE_OUT overrides).
//
// cases[]  id, note, W, H, option, rest {exists, ignore, fill}, steps[]
//          {payload, ignore, fill} (fill: the label's style.fill as a string)
// Self-checks: anchors; two generations give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-endlabel-states.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const CATS = ['A', 'B', 'C', 'D', 'E'];
function line(s) {
  return { animation: false, xAxis: { type: 'category', data: CATS }, yAxis: {},
    series: [Object.assign({ type: 'line', data: [5, 9, 3, 7, 4] }, s)] };
}
const HL = { type: 'highlight', seriesIndex: 0 };
const DP = { type: 'downplay', seriesIndex: 0 };
const HLI = { type: 'highlight', seriesIndex: 0, dataIndex: 2 };
const DPI = { type: 'downplay', seriesIndex: 0, dataIndex: 2 };

const CASES = [
  { id: 'emph.only', note: 'endLabel shown under emphasis only, in its own colour',
    option: line({ endLabel: { show: false }, emphasis: { endLabel: { show: true, color: '#ff0000' } } }),
    steps: [HL, DP, HLI, DPI] },
  { id: 'emph.hide', note: 'endLabel shown at rest, hidden under emphasis',
    option: line({ endLabel: { show: true }, emphasis: { endLabel: { show: false } } }),
    steps: [HL, DP] },
  { id: 'emph.inherit', note: 'endLabel shown at rest, emphasis writes a colour only: shown, recoloured',
    option: line({ endLabel: { show: true }, emphasis: { endLabel: { color: '#00aa00' } } }),
    steps: [HL, DP] },
  { id: 'none', note: 'no state shows it: no label', option: line({ endLabel: { show: false } }), steps: [HL] },
];

function endLabelOf(chart) {
  const view = chart.getViewOfSeriesModel(chart.getModel().getSeriesByIndex(0));
  return view._endLabel || null;
}
function rec(l) {
  return l ? { exists: true, ignore: !!l.ignore, fill: l.style.fill == null ? null : String(l.style.fill) }
    : { exists: false, ignore: true, fill: null };
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(c.option);
    chart.renderToSVGString();
    const rest = rec(endLabelOf(chart));
    const steps = [];
    for (const p of c.steps) {
      chart.dispatchAction(p);
      chart._onframe();
      const r = rec(endLabelOf(chart));
      steps.push({ payload: p, ignore: r.ignore, fill: r.fill });
    }
    return { id: c.id, note: c.note, W, H, option: c.option, rest, steps };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = {};
  for (const c of cases) by[c.id] = c;
  must(by['emph.only'].rest.exists && by['emph.only'].rest.ignore, 'anchor: an emphasis-only end label is there, hidden');
  must(!by['emph.only'].steps[0].ignore, 'anchor: the series highlight shows it');
  must(by['emph.only'].steps[1].ignore, 'anchor: the downplay hides it');
  must(!by['emph.inherit'].steps[0].ignore, 'anchor: a state without show keeps the normal one');
  must(!by['none'].rest.exists, 'anchor: no state, no label');
  return { source: 'ECharts 6.1 dist, chart/line/LineView.ts, label/labelStyle.ts', cases };
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
