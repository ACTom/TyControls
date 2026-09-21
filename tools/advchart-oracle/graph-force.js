// Upstream's own answers for the graph series' layouts, for the port to be held to.
//
// Runs the real ECharts 6.1 build (a sibling checkout, D:/Projects/echarts by
// default, or ECHARTS_DIST) in node's server-side mode and writes what it laid
// out -- every node's position in the view's data space and in pixels, and every
// edge's control point -- to tests/fixtures/advchart-graph-force.json.
//
// Math.random IS REPLACED by the same xorshift32 the port uses, seeded the same
// way, so the force layout's random start is not random here: the port and
// upstream draw the same numbers in the same order, and a transcription that
// does the arithmetic in the same order lands on the same Doubles. Every draw
// is checked to come from the force solver and nowhere else.
//
//   node tools/advchart-oracle/graph-force.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-graph-force.json');

const SEED = 2463534242; // TyGraphForceSeed(0)
let rngState = SEED;
let draws = [];
function rnd() {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  draws.push((new Error().stack.split('\n')[2] || '').trim());
  return x / 4294967296;
}
Math.random = rnd;

function num(v) { return (typeof v === 'number' && isFinite(v)) ? v : null; }

function capture(chart) {
  const s = chart.getModel().getSeriesByIndex(0);
  const cs = s.coordinateSystem;
  const d = s.getData();
  const nodes = [];
  for (let i = 0; i < d.count(); i++) {
    const p = d.getItemLayout(i);
    if (!p || num(p[0]) === null || num(p[1]) === null) { nodes.push(null); continue; }
    const q = cs.dataToPoint(p);
    nodes.push([p[0], p[1], q[0], q[1]]);
  }
  const e = s.getEdgeData();
  const edges = [];
  for (let i = 0; i < e.count(); i++) {
    const pts = e.getItemLayout(i);
    const cp = pts && pts[2];
    if (!cp || num(cp[0]) === null || num(cp[1]) === null) { edges.push(null); continue; }
    const q = cs.dataToPoint(cp);
    edges.push([cp[0], cp[1], q[0], q[1]]);
  }
  const r = cs.getBoundingRect();
  return { dataRect: [r.x, r.y, r.width, r.height], nodes, edges };
}

function run(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.width, height: c.height });
  const phases = [];
  try {
    rngState = SEED; draws = [];
    chart.setOption(c.option);
    // The solver draws in two places: forceLayout() for the random start, and
    // its own step() for a pair of nodes on one point.
    const bad = draws.filter(o => !/^at (forceLayout|Object\.step) \(/.test(o));
    if (bad.length) throw new Error(c.name + ': a random draw outside the force solver: ' + bad[0]);
    phases.push(Object.assign({ width: c.width, height: c.height, draws: draws.length }, capture(chart)));
    if (c.resize) {
      rngState = SEED; draws = [];
      chart.resize({ width: c.resize[0], height: c.resize[1] });
      phases.push(Object.assign({ width: c.resize[0], height: c.resize[1], draws: draws.length }, capture(chart)));
    }
  } finally {
    chart.dispose();
  }
  // EXACT unless a ring is involved: cos and sin are not correctly rounded in
  // either runtime, and everything else is the same operations in the same
  // order, so the data-space answers are the same Doubles.
  const s0 = Array.isArray(c.option.series) ? c.option.series[0] : c.option.series;
  const exact = !(s0.layout === 'circular' || (s0.force && s0.force.initLayout === 'circular'));
  return { name: c.name, exact, option: c.option, phases };
}

// ---------- the fixtures ----------
function graph(extra) {
  return { animation: false, series: [Object.assign({ type: 'graph', layout: 'force' }, extra)] };
}
function force(extra) { return Object.assign({ layoutAnimation: false }, extra || {}); }
const ring = (n) => Array.from({ length: n }, (_, i) => ({ source: i, target: (i + 1) % n }));

const cases = [];
cases.push({ name: 'defaults, nothing placed', width: 600, height: 400, resize: [500, 300],
  option: graph({ force: force(),
    data: [1, 2, 3, 4, 5, 6].map(v => ({ name: 'n' + v, value: v })),
    links: ring(6).concat([{ source: 0, target: 3 }]) }) });
cases.push({ name: 'every node placed, so the force runs in data space', width: 600, height: 400,
  option: graph({ force: force({ repulsion: 100, edgeLength: [10, 50], gravity: 0.2 }),
    data: [[0, 0], [100, 20], [60, 90], [-40, 70], [-80, -10], [20, -60], [90, -50]]
      .map(([x, y], i) => ({ name: 'p' + i, x, y, value: i * 3 })),
    links: ring(7).map((l, i) => Object.assign(l, { value: i })) }) });
cases.push({ name: 'some placed, one pinned, one edge ignored', width: 500, height: 500,
  option: graph({ force: force({ repulsion: [10, 80], edgeLength: 40 }),
    data: [{ name: 'a', x: 250, y: 250, fixed: true, value: 1 }, { name: 'b', x: 100, y: 120, value: 5 },
      { name: 'c', value: 2 }, { name: 'd', value: 9 }, { name: 'e', value: 4 }],
    links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' },
      { source: 'c', target: 'd', ignoreForceLayout: true },
      { source: 'd', target: 'e' }, { source: 'e', target: 'a' }] }) });
cases.push({ name: 'a ring to start from', width: 640, height: 360,
  option: graph({ force: force({ initLayout: 'circular' }),
    data: [3, 1, 4, 1, 5, 9, 2, 6].map((v, i) => ({ name: 'r' + i, value: v })), links: ring(8) }) });
cases.push({ name: 'a ring with a node of no value', width: 640, height: 360,
  option: graph({ force: force({ initLayout: 'circular' }),
    data: [3, 1, null, 1, 5].map((v, i) => (v === null ? { name: 'q' + i } : { name: 'q' + i, value: v })),
    links: ring(5) }) });
cases.push({ name: 'four nodes on one point', width: 400, height: 400,
  option: graph({ force: force(), data: [0, 1, 2, 3].map(i => ({ name: 'c' + i, x: 10, y: 10 })),
    links: [{ source: 0, target: 1 }] }) });
cases.push({ name: 'pinned with nowhere to be', width: 400, height: 300,
  option: graph({ force: force(), data: [{ name: 'f', fixed: true }, { name: 'g' }, { name: 'h' }],
    links: [{ source: 0, target: 1 }] }) });
cases.push({ name: 'no friction at all', width: 400, height: 300,
  option: graph({ force: force({ friction: 0 }), data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
    links: ring(3) }) });
cases.push({ name: 'no repulsion at all', width: 400, height: 300,
  option: graph({ force: force({ repulsion: 0 }),
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }], links: ring(4) }) });
cases.push({ name: 'a one-element edge length', width: 400, height: 300,
  option: graph({ force: force({ edgeLength: [30] }), data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
    links: [{ source: 0, target: 1 }] }) });
cases.push({ name: 'an init layout nobody knows', width: 400, height: 300,
  option: graph({ force: force({ initLayout: 'grid' }),
    data: [{ name: 'a', x: 1, y: 2 }, { name: 'b', x: 5, y: 1 }, { name: 'c', x: 3, y: 7 }], links: ring(3) }) });
cases.push({ name: 'pinned by its category, and a series that pins nothing', width: 500, height: 400,
  option: graph({ force: force(), fixed: false, categories: [{ name: 'held', fixed: true }, { name: 'loose' }],
    data: [{ name: 'a', x: 0, y: 0, category: 0 }, { name: 'b', x: 10, y: 0, category: 1 },
      { name: 'c', x: 5, y: 8, category: 0, fixed: false }, { name: 'd', x: 2, y: 3 }],
    links: ring(4) }) });
cases.push({ name: 'a series that pins everything', width: 500, height: 400,
  option: graph({ force: force(), fixed: true,
    data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 10, y: 4 }, { name: 'c', x: 5, y: 8, fixed: false }],
    links: ring(3) }) });
cases.push({ name: 'auto curveness under force', width: 500, height: 400,
  option: graph({ force: force(), autoCurveness: true,
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }],
    links: [{ source: 0, target: 1 }, { source: 0, target: 1 }, { source: 1, target: 0 },
      { source: 1, target: 2 }, { source: 2, target: 1 }, { source: 2, target: 0 }] }) });

// ---------- what the audit found: values, chains, keys and the box ----------
const tri = [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 5, y: 2 }, { name: 'c', x: 1, y: 9 }];
cases.push({ name: 'edge values as a string, a list and a boolean', width: 500, height: 400,
  option: graph({ force: force({ edgeLength: [10, 60] }),
    data: [{ name: 'a' }, { name: 'b' }, { name: 'c' }, { name: 'd' }],
    links: [{ source: 0, target: 1, value: '4' }, { source: 1, target: 2, value: [9] },
      { source: 2, target: 3, value: true }, { source: 3, target: 0, value: 2 }] }) });
cases.push({ name: 'a fixed at the root of the option', width: 400, height: 300,
  option: Object.assign({ fixed: true }, graph({ force: force(), data: tri, links: ring(3) })) });
cases.push({ name: 'an ignoreForceLayout at the root of the option', width: 400, height: 300,
  option: Object.assign({ ignoreForceLayout: true }, graph({ force: force(), data: tri, links: ring(3) })) });
cases.push({ name: 'a category written as a string index', width: 400, height: 300,
  option: graph({ force: force(), categories: [{ name: 'held', fixed: true }],
    data: [{ name: 'a', x: 0, y: 0, category: '0' }, { name: 'b', x: 5, y: 2 }, { name: 'c', x: 1, y: 9 }],
    links: ring(3) }) });
cases.push({ name: 'an id hides the name it would have been reached by', width: 400, height: 300,
  option: graph({ force: force(),
    data: [{ name: 'A', id: 'x' }, { name: 'B' }, { name: 'C', id: 'z' }],
    links: [{ source: 'A', target: 'B' }, { source: 'x', target: 'z' }, { source: 'B', target: 'C' }] }) });
cases.push({ name: 'a node with no name is reached by its position as a string', width: 400, height: 300,
  option: graph({ force: force(), data: [{ value: 1 }, { value: 2 }, { value: 3 }],
    links: [{ source: '0', target: '1' }, { source: '1', target: '2' }] }) });
cases.push({ name: 'edges are read before links', width: 400, height: 400,
  option: { animation: false, series: [{ type: 'graph', layout: 'none', lineStyle: { curveness: 0.2 },
    data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 30 }, { name: 'c', x: 40, y: 90 }],
    links: [{ source: 0, target: 1 }], edges: [{ source: 1, target: 2 }, { source: 2, target: 0 }] }] } });
cases.push({ name: 'an empty edges list still beats links', width: 400, height: 400,
  option: { animation: false, series: [{ type: 'graph', layout: 'none', lineStyle: { curveness: 0.2 },
    data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 30 }],
    links: [{ source: 0, target: 1 }], edges: [] }] } });
cases.push({ name: 'the node list under its other name', width: 400, height: 300,
  option: { animation: false, series: [{ type: 'graph', layout: 'none',
    nodes: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }], links: [{ source: 0, target: 1 }] }] } });
const boxes = {
  'left null': { left: null }, 'left empty': { left: '' }, 'left auto': { left: 'auto' },
  'left false': { left: false }, 'left Center': { left: 'Center' }, 'left centre': { left: 'centre' },
  'left padded': { left: '  40  ' }, 'left percent with a tail': { left: '10%x' },
  'left percent with a trailing space': { left: '25% ', width: 100 },
  // (`width: false` is a zero-width box, which upstream's view cannot invert: it
  // throws, so there is no answer to hold anything to.)
  'left true': { left: true, width: 100 },
  'left right': { left: 'right', width: 100 }, 'top bottom': { top: 'bottom', height: 80 },
  'left zero hands over to right': { left: 0, right: 'center', width: 120 },
  'top null with a bottom': { top: null, bottom: 30, height: 100 },
  'a width in pixels and a percent height': { width: 150, height: '50%' },
  'contain': { left: 0, top: 0, width: '100%', height: '100%', preserveAspect: true },
  'cover': { left: 0, top: 0, width: '100%', height: '100%', preserveAspect: 'cover' },
  'contain, left': { left: 0, top: 0, width: '100%', height: '100%', preserveAspect: true, preserveAspectAlign: 'left' },
  'contain, right': { left: 0, top: 0, width: '100%', height: '100%', preserveAspect: true, preserveAspectAlign: 'right' },
  'contain, top': { left: 0, top: 0, width: 200, height: '100%', preserveAspect: 'contain', preserveAspectVerticalAlign: 'top' },
  'contain, bottom': { left: 0, top: 0, width: 200, height: '100%', preserveAspect: 'contain', preserveAspectVerticalAlign: 'bottom' },
  'cover, bottom': { left: 30, top: 20, width: 200, height: 300, preserveAspect: 'cover', preserveAspectVerticalAlign: 'bottom' },
};
for (const [bn, bv] of Object.entries(boxes)) {
  cases.push({ name: 'the box: ' + bn, width: 600, height: 400,
    option: { animation: false, series: [Object.assign({ type: 'graph', layout: 'none',
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }, { name: 'c', x: 30, y: 80 }],
      links: [{ source: 0, target: 1 }] }, bv)] } });
}
cases.push({ name: 'the box: a width at the root of the option', width: 600, height: 400,
  option: { width: 200, animation: false, series: [{ type: 'graph', layout: 'none',
    data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 50 }], links: [{ source: 0, target: 1 }] }] } });

// ---------- curveness, laid out where the author put the nodes ----------
const pairs = {
  'one': [[0, 1]], 'two': [[0, 1], [0, 1]], 'there and back': [[0, 1], [1, 0]],
  'two and back': [[0, 1], [0, 1], [1, 0]], 'there, back, there': [[0, 1], [1, 0], [0, 1]],
  'there and back twice': [[0, 1], [1, 0], [1, 0]],
  'three and two back': [[0, 1], [0, 1], [1, 0], [0, 1], [1, 0]],
  'a loop': [[1, 1]], 'two loops': [[1, 1], [1, 1]], 'three loops': [[1, 1], [1, 1], [1, 1]],
};
const autos = { 'true': true, 'five': 5, 'a pair': [0.3, -0.3], 'led by zero': [0, 0.2, -0.2, 0.4],
  'with a hole': [0.1, 'x', 0.3, -0.3], 'led by a hole': ['x', 0.2, -0.2, 0.4] };
for (const layout of ['none', 'circular']) {
  for (const [pn, pl] of Object.entries(pairs)) {
    for (const [an, av] of Object.entries(autos)) {
      cases.push({ name: 'curveness: ' + layout + ', ' + pn + ', ' + an, width: 400, height: 400,
        option: { animation: false, series: [{ type: 'graph', layout, autoCurveness: av,
          data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 100, y: 30 }, { name: 'c', x: 40, y: 90 }],
          links: pl.map(([s, t]) => ({ source: s, target: t })) }] } });
    }
  }
}

// ---------- the gallery's own force chart, end to end ----------
const gal = path.join(ROOT, 'examples', 'advchart', 'gallery', 'graph-force.json');
if (fs.existsSync(gal)) {
  const opt = JSON.parse(fs.readFileSync(gal, 'utf8'));
  const s = Array.isArray(opt.series) ? opt.series[0] : opt.series;
  s.force = Object.assign({}, s.force, { layoutAnimation: false });
  opt.animation = false;
  cases.push({ name: 'the gallery\'s Les Miserables, under force', width: 900, height: 700, option: opt });
}

const out = { source: 'ECharts ' + echarts.version, seed: SEED, cases: cases.map(run) };
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote', OUT, out.cases.length, 'cases');
process.exit(0);
