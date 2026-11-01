// Round 6 R6-C: a sankey's view group in a setOption that changes its zoom /
// center. SankeyView._updateViewCoordSys: applyViewCoordSysTransToElement
// on the series' view group with the series model past its first render --
// updateProps, at the series' update timing.
//
// From the real ECharts 6.1 dist under the hand-driven clock (animation.js'
// harness: the replaced Date before the dist, chart._ssr = false, env.node =
// false, frames stepped by hand, the display list built after each): a
// sankey at rest, then a merge that changes its zoom / center (or its data
// and its zoom), recorded at each sample: the view group's x / y / scaleX /
// scaleY, every node rect's path box (no stroke) through its computed
// transform and every band's.
// Run: node tools/advchart-oracle/sankey-roam-tween.js -> tests/fixtures/advchart-sankey-roam-tween.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-sankey-roam-tween.json');
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
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const W = 400;
const H = 300;
const SAMPLES = [0, 16, 100, 250, 400, 500, 750, 999, 1000, 1001, 1500];
const T_GAP = 10000;
const Rect = echarts.graphic.Rect;

// the path's own box (no stroke), through its computed transform
function globalBox(el) {
  const r = el.getUpdatedPathProxy().getBoundingRect().clone();
  const m = el.getComputedTransform();
  if (m) r.applyTransform(m);
  return [r.x, r.y, r.width, r.height].map(hex);
}
function step(zr, t) {
  NOW = t;
  zr.animation.update();
  zr.storage.getDisplayList(true);
}
const NODES = ['A', 'B', 'C', 'D'].map(n => ({ name: n }));
const LINKS = [{ source: 'A', target: 'C', value: 5 }, { source: 'B', target: 'D', value: 3 }, { source: 'A', target: 'D', value: 2 }];
const sk = extra => Object.assign({ type: 'sankey', id: 'sk', data: NODES, links: LINKS }, extra || {});
function cases() {
  return [
    { id: 'zoom', note: 'roam on at zoom 1, then a merge to zoom 1.5 and center 40% / 50%',
      steps: [{ series: [sk({ roam: true })] }, { series: [{ id: 'sk', zoom: 1.5, center: ['40%', '50%'] }] }] },
    { id: 'center', note: 'a merge that moves the center alone', steps: [{ series: [sk({ roam: true, zoom: 1.2 })] },
      { series: [{ id: 'sk', center: ['60%', '40%'] }] }] },
    { id: 'zoom-out', note: 'zoom 2 to 1 (the update timing written: 600 ms, linear)', steps: [
      { series: [sk({ roam: true, zoom: 2, animationDurationUpdate: 600, animationEasingUpdate: 'linear' })] },
      { series: [{ id: 'sk', zoom: 1 }] }] },
    { id: 'same', note: 'a merge that changes nothing of the view', steps: [{ series: [sk({ roam: true, zoom: 1.5 })] },
      { series: [{ id: 'sk', nodeGap: 12 }] }] },
  ];
}

function run(c) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    const zr = chart.getZr();
    chart.setOption(JSON.parse(JSON.stringify(c.steps[0])));
    for (let k = 16; k <= 5000; k += 250) step(zr, T_BASE + k);
    const t = T_BASE + T_GAP;
    NOW = t;
    chart.setOption(JSON.parse(JSON.stringify(c.steps[1])), { notMerge: false });
    const out = [];
    SAMPLES.forEach((s, i) => {
      if (i > 0) step(zr, t + s);
      else zr.storage.getDisplayList(true);
      const view = chart._chartsViews[0];
      const g = view.group;
      const nodes = [];
      const bands = [];
      g.traverse(e => {
        if (e instanceof Rect) nodes.push(globalBox(e));
        else if (e.type === 'sankeyPath' || e.type === 'path') bands.push(globalBox(e));
      });
      out.push({ t: s, group: [g.x, g.y, g.scaleX, g.scaleY].map(hex), nodes, bands });
    });
    return Object.assign({}, c, { samples: out });
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(run);
  const by = id => charts.find(x => x.id === id);
  const moves = c => c.samples.some((s, i) => i > 0 && s.group.join() !== c.samples[0].group.join());
  must(moves(by('zoom')) && moves(by('center')) && moves(by('zoom-out')), 'a view group does not tween');
  must(!moves(by('same')), 'same: the view group moves');
  must(by('zoom').samples.every(s => s.nodes.length === 4 && s.bands.length === 3), 'zoom: not four nodes and three bands');
  // in flight between its ends
  const z = by('zoom').samples;
  must(z[3].group[2] !== z[0].group[2] && z[3].group[2] !== z[z.length - 1].group[2], 'zoom: not in flight at 250 ms');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg), controlled clock',
    note: 'R6-C: a sankey at rest (T0, run out), then a merge at T0 + 10000 recorded at that T + samples: group = the '
      + 'series view group\'s x, y, scaleX, scaleY; nodes = every node rect\'s path box (no stroke) through its computed transform (x, y, w, h), bands = every '
      + 'band\'s, in traverse order. Every number is the hex of its double.', W, H,
    clock: { T0: T_BASE, gap: T_GAP }, charts };
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
