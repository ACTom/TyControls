// Upstream's own answers for an effectScatter whose showEffectOn is not
// 'render' (chart/helper/EffectSymbol.ts): no ripple until the symbol's
// hover state turns to 'emphasis' (onHoverStateChange -> startEffectAnimation:
// rippleNumber paths, each looping scale 0.5 -> rippleScale / 2 and opacity
// 1 -> 0 over the period, delayed -i / n * period + idx / count), and none
// again once it turns back to 'normal' (stopEffectAnimation). A `highlight`
// (or the pointer) starts them at the frame after it; a `downplay` removes
// them; another highlight starts them over from their first phase.
//
// The harness is animation-an4.js' own: the replaced Date before the dist,
// chart._ssr = false, env.node = false, the seeded Math.random, hand-stepped
// frames.
//
//   node tools/advchart-oracle/effect-hover.js
//
// writes tests/fixtures/advchart-effect-hover.json (ORACLE_OUT overrides).
//
// cases[]  id, note, W, H, option, steps[]: each {at (ms after T1), action
//          (a payload or null), ripples [{d, i, scaleX, scaleY, opacity}]
//          (hex; every ripple path in the series' view after the frame at
//          that time, symbols in data order, ripples in order), clips (the
//          animation's clip count)}
// Self-checks: anchors; two generations give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T_BASE = 1700000000000;
let NOW = T_BASE;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-effect-hover.json');

echarts.env.node = false;

const W = 400;
const H = 300;
const T1_OFFSET = 10000;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

function ecDataOf(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'dataIndex' in el[k]) return el[k];
  }
  return null;
}
function clipCount(zr) {
  let n = 0;
  for (let c = zr.animation._head; c; c = c.next) n++;
  return n;
}

function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
}

// every ripple of the series' EffectSymbols: the symbol group's second child
function ripples(chart) {
  const out = [];
  const s = chart.getModel().getSeriesByIndex(0);
  const data = s.getData();
  data.each(idx => {
    const g = data.getItemGraphicEl(idx);
    if (!g || !g.childAt) return;
    const rg = g.childAt(1);
    if (!rg) return;
    rg.childrenRef().forEach((p, i) => {
      out.push({ d: idx, i, scaleX: hex(p.scaleX), scaleY: hex(p.scaleY), opacity: hex(p.style.opacity) });
    });
  });
  return out;
}

const hl = d => ({ type: 'highlight', seriesIndex: 0, dataIndex: d });
const dp = d => ({ type: 'downplay', seriesIndex: 0, dataIndex: d });

function scatter(extra) {
  return Object.assign({
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [Object.assign({ type: 'effectScatter', showEffectOn: 'emphasis', symbolSize: 10,
      data: [[1, 2], [3, 4], [2, 1]] }, extra)],
  });
}

// at: ms after T1; an action is dispatched at that time, then the frame runs
const PLAY = [
  { at: 0, action: hl(1) },
  { at: 1 }, { at: 16 }, { at: 500 }, { at: 1000 }, { at: 2000 }, { at: 3999 }, { at: 4000 }, { at: 4016 }, { at: 6100 },
  { at: 6200, action: dp(1) },
  { at: 6216 },
  { at: 7000, action: hl(1) },
  { at: 7016 }, { at: 8000 },
  { at: 8100, action: hl(0) },
  { at: 8116 }, { at: 9000 },
  { at: 9100, action: dp(0) },
  { at: 9116 },
];

const CASES = [
  { id: 'emphasis', note: "showEffectOn 'emphasis': ripples while highlighted", option: scatter({}) },
  { id: 'emphasis.custom', note: 'period 2, scale 4, number 2, brushType stroke',
    option: scatter({ rippleEffect: { period: 2, scale: 4, number: 2, brushType: 'stroke' } }) },
  { id: 'other.word', note: "showEffectOn 'hover' (any word but 'render' is the hover mode)",
    option: scatter({ showEffectOn: 'hover' }) },
];

function runCase(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = newChart();
  try {
    chart.setOption(c.option);
    settle(chart, T_BASE);
    const zr = chart.getZr();
    const t1 = T_BASE + T1_OFFSET;
    const steps = [];
    for (const st of PLAY) {
      NOW = t1 + st.at;
      if (st.action) chart.dispatchAction(st.action);
      zr.animation.update();
      zr.storage.getDisplayList(true);
      steps.push({ at: st.at, action: st.action || null, ripples: ripples(chart), clips: clipCount(zr) });
    }
    return { id: c.id, note: c.note, W, H, option: c.option, steps };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const e = cases[0];
  // anchors: none before the highlight, n while it, none after the downplay
  must(e.steps[0].ripples.length === 3 && e.steps[0].ripples.every(r => r.d === 1), 'anchor: the highlight starts three ripples on its symbol');
  must(e.steps.find(s => s.at === 6216).ripples.length === 0, 'anchor: the downplay removes them');
  must(e.steps.find(s => s.at === 8116).ripples.some(r => r.d === 0) && e.steps.find(s => s.at === 8116).ripples.some(r => r.d === 1),
    'anchor: two highlighted symbols ripple');
  must(cases[1].steps[0].ripples.length === 2, 'anchor: number 2');
  return { source: 'ECharts 6.1 dist, chart/helper/EffectSymbol.ts, util/states.ts', T1: T1_OFFSET, cases };
}

let code = 0;
try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  console.log('wrote ' + OUT);
} catch (err) {
  console.error(err instanceof OracleError ? 'ORACLE: ' + err.message : err);
  code = 1;
}
process.exit(code);
