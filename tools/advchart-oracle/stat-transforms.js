/*
Upstream's own answers for ECSTAT'S TRANSFORMS -- roadmap D3, batch 134:
the three dataset transforms echarts-stat ships (ecStat.transform.regression,
.histogram and .clustering), registered the way every gallery example does,
echarts.registerTransform(ecStat.transform.xxx):

  'ecStat:regression'  linear, linearThroughOrigin, exponential,
                       logarithmic, polynomial (order; Gaussian
                       elimination), the points sorted by x, the formula
                       text in column 2 (formulaOn start / end / all /
                       none) and the dimensions it hands on
  'ecStat:histogram'   squareRoot, scott, freedmanDiaconis, sturges; the
                       nice step, the ticks, the bins, the two results
  'ecStat:clustering'  hierarchical (bisecting) k-means: the random initial
                       centroids drawn from Math.random, the stopping rule,
                       clusterCount, outputClusterIndexDimension,
                       outputCentroidDimensions, dimensions; the centroid
                       table as result 1

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) and the built echarts-stat in its test folder
(D:/Projects/echarts/test/lib/ecStat.min.js, or ECSTAT_DIST) in node's
server-side mode, SVG renderer, 600 x 400, `animation: false`, TZ=UTC,
measuring nothing the port measures differently. Math.random is the port's
xorshift32 (TyJitterSeed, 2463534242), RESET BEFORE EVERY CHART; every draw
is counted.

  node tools/advchart-oracle/stat-transforms.js

writes tests/fixtures/advchart-stat-transforms.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers are the 16 hex digits of the IEEE double (big-endian, lowercase);
counts, flags, strings and option values are plain JSON.

Top level: source, ecStat, version, W, H, seed, notes[], cases[], guards[].

A case: id, group, note, option (as run), deviation (absent, or the name of
  a rule the port does not follow), draws (Math.random calls in the whole
  run: setOption, render and the dataset dump), and
  datasets[] one per dataset, in order, after prepareSource() was called on
    each in turn (a series reading one prepared it in setOption already):
      {k, error: the message upstream threw ('RangeError' for one) | null,
       results[]: SourceManager._sourceList, each
         {r, format, clone, startIndex, dims (names, null for an unnamed
          one or a hole) | null, detected | null, rows}}
      A cell: a number its hex, a string 's:' + it, a boolean 'b:true' /
      'b:false', null or undefined (a hole) null, anything else 'j:' + its
      JSON. A row: an array of cells, an object row {o: [[key, cell]...]}.
  render (cases with series; setOption threw -> {error}): rect (grid 0),
    axes[] {dim, index, categories | null}, series[] {index, type, count,
    items[] (bar [x, y, w, h]; line / scatter the dataToPoint of the stored
    values), fills[] (a scatter a visualMap colours: [r, g, b, a] of each
    item's visual fill -- the palette elsewhere is the port's skin's),
    labels[] {d, text} (every element of the view carrying a NON-EMPTY text,
    in traversal order -- the regression line's other points carry '')}.

Guards (any failure: nothing is written, exit 1): expectations worked out
by hand from the source -- see guards(); and the whole fixture is generated
twice (byte-identical). process.exit() ends the run.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const STAT = process.env.ECSTAT_DIST || 'D:/Projects/echarts/test/lib/ecStat.min.js';
const echarts = require(DIST);
const ecStat = require(STAT);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-stat-transforms.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
must(new Date(0).getTimezoneOffset() === 0, 'TZ is not UTC');

echarts.registerTransform(ecStat.transform.regression);
echarts.registerTransform(ecStat.transform.histogram);
echarts.registerTransform(ecStat.transform.clustering);

// ---------- the random numbers: the port's xorshift32 ----------
const SEED = 2463534242;
let rngState = SEED;
let DRAWS = 0;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  DRAWS++;
  return x / 4294967296;
};

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// ---------------------------------------------------------------------------
// recording
// ---------------------------------------------------------------------------
function cellOut(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'string') return 's:' + v;
  if (typeof v === 'boolean') return 'b:' + v;
  return 'j:' + JSON.stringify(v);
}
function rowOut(row) {
  if (row === null || row === undefined) return null;
  if (Array.isArray(row)) {
    const out = [];
    for (let i = 0; i < row.length; i++) out.push(cellOut(row[i]));
    return out;
  }
  if (typeof row === 'object') return { o: Object.keys(row).map(k => [k, cellOut(row[k])]) };
  return cellOut(row);
}
function sourceOut(src, r) {
  must(Array.isArray(src.data) || (src.data && typeof src.data === 'object'), 'a source with no data');
  let dims = null;
  if (src.dimensionsDefine) {
    dims = [];
    for (let i = 0; i < src.dimensionsDefine.length; i++) {
      const d = src.dimensionsDefine[i];
      dims.push(d == null || d.name == null ? null : d.name);
    }
  }
  return {
    r,
    format: src.sourceFormat,
    clone: src.metaRawOption === undefined,
    startIndex: src.startIndex,
    dims,
    detected: src.dimensionsDetectedCount == null ? null : src.dimensionsDetectedCount,
    rows: Array.isArray(src.data) ? src.data.map(rowOut) : null,
  };
}
function errText(e) {
  return e instanceof RangeError ? 'RangeError' : String(e.message);
}
function datasetsOut(chart) {
  const out = [];
  const m = chart.getModel();
  let n = 0;
  m.eachComponent('dataset', () => { n++; });
  for (let k = 0; k < n; k++) {
    const mgr = m.getComponent('dataset', k).getSourceManager();
    const rec = { k, error: null, results: [] };
    const dsOpt = m.getComponent('dataset', k).option;
    // a root table is its own source: its rows are not written out
    const root = !dsOpt.transform && !dsOpt.fromTransformResult;
    try {
      mgr.prepareSource();
      const list = mgr._sourceList;
      for (let r = 0; r < list.length; r++) {
        if (!list[r]) continue;
        const so = sourceOut(list[r], r);
        if (root) so.rows = null;
        rec.results.push(so);
      }
    } catch (e) {
      rec.error = errText(e);
    }
    out.push(rec);
  }
  return out;
}

let ecKey = null;
function ecData(el) {
  if (!el) return null;
  if (ecKey === null) {
    for (const k of Object.getOwnPropertyNames(el)) {
      const v = el[k];
      if (k.indexOf('__ec_inner_') === 0 && v && typeof v === 'object'
        && ('dataIndex' in v || 'componentMainType' in v) && 'seriesIndex' in v) {
        ecKey = k;
        break;
      }
    }
    if (ecKey === null) return null;
  }
  return el[ecKey] || null;
}
function dataIndexOf(el) {
  for (let e = el; e; e = e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return d.dataIndex;
  }
  return null;
}

function seriesOut(chart, s) {
  const data = s.getData();
  const items = [];
  const fills = [];
  // a fill is recorded where a visualMap decides it (the palette is the
  // port's skin's)
  let byVisualMap = false;
  chart.getModel().eachComponent('visualMap', vm => { if (vm.isTargetSeries(s)) byVisualMap = true; });
  if (s.subType === 'line' || s.subType === 'scatter') {
    const cs = s.coordinateSystem;
    const dims = cs.dimensions.map(d => data.mapDimension(d));
    const store = data.getStore();
    for (let i = 0; i < data.count(); i++) {
      const p = cs.dataToPoint([store.get(data.getDimensionIndex(dims[0]), i),
        store.get(data.getDimensionIndex(dims[1]), i)], null, []);
      items.push([hex(p[0]), hex(p[1])]);
      if (s.subType === 'scatter' && byVisualMap) {
        const st = data.getItemVisual(i, 'style') || {};
        const c = typeof st.fill === 'string' ? echarts.color.parse(st.fill) : null;
        fills.push(c ? [c[0], c[1], c[2], hex(c[3])] : null);
      }
    }
  } else {
    for (let i = 0; i < data.count(); i++) {
      const l = data.getItemLayout(i);
      if (l == null) items.push(null);
      else if (l.width != null) items.push([hex(l.x), hex(l.y), hex(l.width), hex(l.height)]);
      else items.push(null);
    }
  }
  const labels = [];
  const view = chart.getViewOfSeriesModel(s);
  view.group.traverse(el => {
    if (el.ignore) return true;
    const t = el.getTextContent && el.getTextContent();
    if (!t || t.ignore) return;
    const text = String(t.style.text);
    if (text === '') return;
    labels.push({ d: dataIndexOf(el), text });
  });
  const rec = { index: s.seriesIndex, type: s.subType, count: data.count(), items, labels };
  if (s.subType === 'scatter' && byVisualMap) rec.fills = fills;
  return rec;
}
function renderOut(chart) {
  const m = chart.getModel();
  const g = m.getComponent('grid', 0);
  const rect = g && g.coordinateSystem ? g.coordinateSystem.getRect() : null;
  const out = { rect: rect ? [rect.x, rect.y, rect.width, rect.height].map(hex) : null, axes: [], series: [] };
  for (const dim of ['x', 'y']) {
    m.eachComponent(dim + 'Axis', (comp, index) => {
      const ax = comp.axis;
      const meta = ax && ax.scale.getOrdinalMeta ? ax.scale.getOrdinalMeta() : null;
      out.axes.push({ dim, index, categories: meta ? meta.categories.slice().map(String) : null });
    });
  }
  m.eachSeries(s => out.series.push(seriesOut(chart, s)));
  return out;
}

function runCase(c) {
  const option = clone(c.option);
  const rec = { id: c.id, group: c.group, note: c.note, option };
  if (c.deviation) rec.deviation = c.deviation;
  rngState = SEED;
  DRAWS = 0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    let threw = null;
    try {
      chart.setOption(clone(option));
      chart.renderToSVGString();
    } catch (e) {
      threw = errText(e);
    }
    if (option.series) rec.render = threw ? { error: threw } : renderOut(chart);
    else must(!threw, c.id + ': setOption threw without a series: ' + threw);
    rec.datasets = datasetsOut(chart);
    rec.draws = DRAWS;
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// the tables
// ---------------------------------------------------------------------------
// a generator of its own, so the tables do not touch Math.random
function gen(seed) {
  let x = seed >>> 0;
  return () => { x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x / 4294967296; };
}
const round3 = v => Math.round(v * 1000) / 1000;

// scatter-linear-regression.ts (the first 60 points)
const LINEAR = [[0.067732, 3.176513], [0.42781, 3.816464], [0.995731, 4.550095], [0.738336, 4.256571], [0.981083, 4.560815],
  [0.526171, 3.929515], [0.378887, 3.52617], [0.033859, 3.156393], [0.132791, 3.110301], [0.138306, 3.149813],
  [0.247809, 3.476346], [0.64827, 4.119688], [0.731209, 4.282233], [0.236833, 3.486582], [0.969788, 4.655492],
  [0.607492, 3.965162], [0.358622, 3.5149], [0.147846, 3.125947], [0.63782, 4.094115], [0.230372, 3.476039],
  [0.070237, 3.21061], [0.067154, 3.190612], [0.925577, 4.631504], [0.717733, 4.29589], [0.015371, 3.085028],
  [0.33507, 3.44808], [0.040486, 3.16744], [0.212575, 3.364266], [0.617218, 3.993482], [0.541196, 3.891471],
  [0.045353, 3.143259], [0.126762, 3.114204], [0.556486, 3.851484], [0.901144, 4.621899], [0.958476, 4.580768],
  [0.274561, 3.620992], [0.394396, 3.580501], [0.87248, 4.618706], [0.409932, 3.676867], [0.908969, 4.641845],
  [0.166819, 3.175939], [0.665016, 4.26498], [0.263727, 3.558448], [0.231214, 3.436632], [0.552928, 3.831052],
  [0.047744, 3.182853], [0.365746, 3.498906], [0.495002, 3.946833], [0.493466, 3.900583], [0.792101, 4.238522],
  [0.76966, 4.23308], [0.251821, 3.521557], [0.181951, 3.203344], [0.808177, 4.278105], [0.334116, 3.555705],
  [0.33863, 3.502661], [0.452584, 3.859776], [0.69477, 4.275956], [0.590902, 3.916191], [0.307928, 3.587961]];
// data-transform-ecStat.html / scatter-exponential-regression.ts
const GDP = [[1, 4862.4], [2, 5294.7], [3, 5934.5], [4, 7171.0], [5, 8964.4], [6, 10202.2], [7, 11962.5], [8, 14928.3],
  [9, 16909.2], [10, 18547.9], [11, 21617.8], [12, 26638.1], [13, 34634.4], [14, 46759.4], [15, 58478.1],
  [16, 67884.6], [17, 74462.6], [18, 79395.7]];
// scatter-polynomial-regression.ts
const PROFIT = [[96.24, 11.35], [33.09, 85.11], [57.6, 36.61], [36.77, 27.26], [20.1, 6.72], [45.53, 36.37],
  [110.07, 80.13], [72.05, 20.88], [39.82, 37.15], [48.05, 70.5], [0.85, 2.57], [51.66, 63.7], [61.07, 127.13],
  [64.54, 33.59], [35.5, 25.01], [226.55, 664.02], [188.6, 175.31], [81.31, 108.68]];
// scatter-logarithmic-regression.ts
const LIFE = [[28604, 77, 17096869, 'Australia', 1990], [31163, 77.4, 27662440, 'Canada', 1990],
  [1516, 68, 1154605773, 'China', 1990], [13670, 74.7, 10582082, 'Cuba', 1990], [28599, 75, 4986705, 'Finland', 1990],
  [29476, 77.1, 56943299, 'France', 1990], [31476, 75.4, 78958237, 'Germany', 1990], [28666, 78.1, 254830, 'Iceland', 1990],
  [1777, 57.7, 870601776, 'India', 1990], [29550, 79.1, 122249285, 'Japan', 1990], [2076, 67.9, 20194354, 'North Korea', 1990],
  [12087, 72, 42972254, 'South Korea', 1990], [24021, 75.4, 3397534, 'New Zealand', 1990], [43296, 76.8, 4240375, 'Norway', 1990],
  [10088, 70.8, 38195258, 'Poland', 1990], [19349, 69.6, 147568552, 'Russia', 1990], [10670, 67.3, 53994605, 'Turkey', 1990],
  [26424, 75.7, 57110117, 'United Kingdom', 1990], [37062, 75.4, 252847810, 'United States', 1990],
  [44056, 81.8, 23968973, 'Australia', 2015], [43294, 81.7, 35939927, 'Canada', 2015], [13334, 76.9, 1376048943, 'China', 2015],
  [21291, 78.5, 11389562, 'Cuba', 2015], [38923, 80.8, 5503457, 'Finland', 2015], [37599, 81.9, 64395345, 'France', 2015],
  [44053, 81.1, 80688545, 'Germany', 2015], [42182, 82.8, 329425, 'Iceland', 2015], [5903, 66.8, 1311050527, 'India', 2015],
  [36162, 83.5, 126573481, 'Japan', 2015], [1390, 71.4, 25155317, 'North Korea', 2015], [34644, 80.7, 50293439, 'South Korea', 2015],
  [34186, 80.6, 4528526, 'New Zealand', 2015], [64304, 81.6, 5210967, 'Norway', 2015], [24787, 77.3, 38611794, 'Poland', 2015],
  [23038, 73.13, 143456918, 'Russia', 2015], [19360, 76.5, 78665830, 'Turkey', 2015], [38225, 81.4, 64715810, 'United Kingdom', 2015],
  [53354, 79.1, 321773631, 'United States', 2015]];
// bar-histogram.ts
const GIRTH = [[8.3, 143], [8.6, 214], [8.8, 251], [10.5, 26], [10.7, 86], [10.8, 93], [11.0, 176], [11.0, 39], [11.1, 221],
  [11.2, 188], [11.3, 57], [11.4, 91], [11.4, 191], [11.7, 8], [12.0, 196], [12.9, 177], [12.9, 153], [13.3, 201],
  [13.7, 199], [13.8, 47], [14.0, 81], [14.2, 98], [14.5, 121], [16.0, 37], [16.3, 12], [17.3, 105], [17.5, 168],
  [17.9, 84], [18.0, 197], [18.0, 155], [20.6, 125]];
// scatter-clustering.ts
const CLUSTER = [[3.275154, 2.957587], [-3.344465, 2.603513], [0.355083, -3.376585], [1.852435, 3.547351], [-2.078973, 2.552013],
  [-0.993756, -0.884433], [2.682252, 4.007573], [-3.087776, 2.878713], [-1.565978, -1.256985], [2.441611, 0.444826],
  [-0.659487, 3.111284], [-0.459601, -2.618005], [2.17768, 2.387793], [-2.920969, 2.917485], [-0.028814, -4.168078],
  [3.625746, 2.119041], [-3.912363, 1.325108], [-0.551694, -2.814223], [2.855808, 3.483301], [-3.594448, 2.856651],
  [0.421993, -2.372646], [1.650821, 3.407572], [-2.082902, 3.384412], [-0.718809, -2.492514], [4.513623, 3.841029],
  [-4.822011, 4.607049], [-0.656297, -1.449872], [1.919901, 4.439368], [-3.287749, 3.918836], [-1.576936, -2.977622],
  [3.598143, 1.97597], [-3.977329, 4.900932], [-1.79108, -2.184517], [3.914654, 3.559303], [-1.910108, 4.166946],
  [-1.226597, -3.317889], [1.148946, 3.345138], [-2.113864, 3.548172], [0.845762, -3.589788], [2.629062, 3.535831],
  [-1.640717, 2.990517], [-1.881012, -2.485405], [4.606999, 3.510312], [-4.366462, 4.023316], [0.765015, -3.00127],
  [3.121904, 2.173988], [-4.025139, 4.65231], [-0.559558, -3.840539], [4.376754, 4.863579], [-1.874308, 4.032237],
  [-0.089337, -3.026809], [3.997787, 2.518662], [-3.082978, 2.884822], [0.845235, -3.454465], [1.327224, 3.358778],
  [-2.889949, 3.596178], [-0.966018, -2.839827], [2.960769, 3.079555], [-3.275518, 1.577068], [0.639276, -3.41284]];

// distributions for the bins
function uniform(n, seed, lo, hi) {
  const r = gen(seed);
  return Array.from({ length: n }, () => [round3(lo + (hi - lo) * r())]);
}
function normal(n, seed, mu, sd) {
  const r = gen(seed);
  return Array.from({ length: n }, () => [round3(mu + sd * (r() + r() + r() + r() - 2) * 1.7)]);
}
function skewed(n, seed) {
  const r = gen(seed);
  return Array.from({ length: n }, () => [round3(-Math.log(1 - r()) * 40)]);
}
function ints(n, seed, k) {
  const r = gen(seed);
  return Array.from({ length: n }, () => [Math.floor(r() * k)]);
}
function tiny(n, seed) {
  const r = gen(seed);
  return Array.from({ length: n }, () => [Math.round(r() * 1e6) / 1e9]);
}
// points around k centres
function blobs(n, seed, centres, spread, dims) {
  const r = gen(seed);
  const out = [];
  for (let i = 0; i < n; i++) {
    const c = centres[i % centres.length];
    const row = [];
    for (let d = 0; d < dims; d++) row.push(round3(c[d] + (r() - 0.5) * spread));
    out.push(row);
  }
  return out;
}
function noisyLine(n, seed, a, b, noise) {
  const r = gen(seed);
  return Array.from({ length: n }, (_, i) => {
    const x = round3(r() * 50 - 10);
    return [x, round3(a * x + b + (r() - 0.5) * noise)];
  });
}

const CASES = [];
function add(group, id, note, option, more) {
  CASES.push(Object.assign({ group, id, note, option: Object.assign({ animation: false }, option) }, more || {}));
}
const reg = config => (config === undefined ? { type: 'ecStat:regression' } : { type: 'ecStat:regression', config });
const hist = config => (config === undefined ? { type: 'ecStat:histogram' } : { type: 'ecStat:histogram', config });
const clu = config => (config === undefined ? { type: 'ecStat:clustering' } : { type: 'ecStat:clustering', config });
const two = (source, tr, extra) => ({ dataset: [Object.assign({ source: clone(source) }, extra || {}), { transform: tr }] });

// ---- regression
const G = 'regression';
add(G, 'r-linear', 'linear by default, formula at the end', two(LINEAR, reg()));
add(G, 'r-linear-exact', 'three points on y = 2x + 1, unsorted', two([[3, 7], [1, 3], [2, 5]], reg({ method: 'linear' })));
add(G, 'r-linear-start', "formulaOn 'start', a header with names", two([['x', 'y']].concat(LINEAR.slice(0, 20)), reg({ formulaOn: 'start' })));
add(G, 'r-linear-all', "formulaOn 'all'", two(LINEAR.slice(0, 12), reg({ formulaOn: 'all' })));
add(G, 'r-linear-none', "formulaOn 'none': no dimensions, the header and its names inherited",
  two([['x', 'y']].concat(LINEAR.slice(0, 15)), reg({ formulaOn: 'none' })));
add(G, 'r-linear-none-declared', "formulaOn 'none' over declared dimensions",
  two(LINEAR.slice(0, 15), reg({ formulaOn: 'none' }), { dimensions: ['u', 'v'] }));
add(G, 'r-linear-other', "formulaOn 'middle': every point an empty string", two(LINEAR.slice(0, 10), reg({ formulaOn: 'middle' })));
add(G, 'r-linear-wide', 'four columns by name: column 2 is the formula, the others kept',
  two([['a', 'b', 'c', 'd']].concat(noisyLine(25, 5, 1.5, -4, 6).map((p, i) => [i, p[0], 'w' + i, p[1]])),
    reg({ dimensions: ['b', 'd'] })));
add(G, 'r-linear-dims-index', 'dimensions by index, reversed', two(noisyLine(30, 9, -0.7, 12, 3), reg({ dimensions: [1, 0] })));
add(G, 'r-linear-one-dim', 'dimensions a single name: x only, y undefined -- NaN', two([['p', 'q']].concat(LINEAR.slice(0, 8)), reg({ dimensions: 'q' })));
add(G, 'r-linear-three-dims', 'three dimensions: the third checked, not used',
  two([[1, 2, 5], [2, 4, null], [3, 7, 1], [4, 8, 2], [5, 11, 'x']], reg({ dimensions: [0, 1, 2] })));
add(G, 'r-linear-negative', 'negative slope and intercept: "x + -"', two([[0, -1], [1, -3.5], [2, -6.2], [3, -8.4], [4, -11.1]], reg()));
add(G, 'r-linear-big', '200 noisy points, unsorted', two(noisyLine(200, 77, 3.3, 101.5, 40), reg()));
add(G, 'r-origin', 'linearThroughOrigin', two(noisyLine(40, 13, 2.25, 0, 5), reg({ method: 'linearThroughOrigin' })));
add(G, 'r-origin-header', 'linearThroughOrigin, header, formulaOn all', two([['m', 'n']].concat(noisyLine(10, 14, -1.1, 0, 2)), reg({ method: 'linearThroughOrigin', formulaOn: 'all' })));
add(G, 'r-exp', 'exponential (the GDP table)', two(GDP, reg({ method: 'exponential' })));
add(G, 'r-exp-start', 'exponential, formula at the start', two(GDP.slice(0, 10), reg({ method: 'exponential', formulaOn: 'start' })));
add(G, 'r-exp-neg', 'exponential over a negative and a nought: log of them', two([[1, 2], [2, 0], [3, -4], [4, 9]], reg({ method: 'exponential' })));
add(G, 'r-exp-decay', 'exponential decay', two([[0, 100], [1, 61], [2, 37], [3, 22.4], [4, 13.6], [5, 8.1], [6, 5.1]], reg({ method: 'exponential' })));
add(G, 'r-log', 'logarithmic over the life table (strings in column 3 kept)', two(LIFE, reg({ method: 'logarithmic' })));
add(G, 'r-log-neg', 'logarithmic with x at nought and below', two([[0, 1], [1, 2], [-2, 3], [4, 5]], reg({ method: 'logarithmic' })));
add(G, 'r-log-small', 'logarithmic, four points', two([[1, 0.5], [2, 1.2], [4, 2.1], [8, 2.9]], reg({ method: 'logarithmic', formulaOn: 'all' })));
add(G, 'r-poly', 'polynomial, the default order 2', two(PROFIT, reg({ method: 'polynomial' })));
add(G, 'r-poly-3', 'polynomial order 3 (the gallery)', two(PROFIT, reg({ method: 'polynomial', order: 3 })));
add(G, 'r-poly-1', 'polynomial order 1', two(LINEAR.slice(0, 30), reg({ method: 'polynomial', order: 1 })));
add(G, 'r-poly-0', 'polynomial order 0: the mean', two(LINEAR.slice(0, 30), reg({ method: 'polynomial', order: 0 })));
add(G, 'r-poly-5', 'polynomial order 5', two(noisyLine(60, 21, 0.4, -3, 30), reg({ method: 'polynomial', order: 5 })));
add(G, 'r-poly-8', 'polynomial order 8 over few points: an ill-conditioned system', two(GDP, reg({ method: 'polynomial', order: 8 })));
add(G, 'r-poly-neg1', 'polynomial order -1: no terms, y = 0, "y = "', two(PROFIT.slice(0, 6), reg({ method: 'polynomial', order: -1 })));
add(G, 'r-poly-null', 'polynomial order null: 2', two(PROFIT.slice(0, 9), reg({ method: 'polynomial', order: null })));
add(G, 'r-poly-exact', 'polynomial over y = x^2 - 3x + 2', two([[0, 2], [1, 0], [2, 0], [3, 2], [4, 6], [5, 12]], reg({ method: 'polynomial', formulaOn: 'all' })));
add(G, 'r-method-empty', "method '' is linear", two(LINEAR.slice(0, 6), reg({ method: '' })));
add(G, 'r-one', 'one point: 0 / 0', two([[2, 3]], reg()));
add(G, 'r-one-poly', 'one point, polynomial', two([[2, 3]], reg({ method: 'polynomial' })));
add(G, 'r-vertical', 'all x equal: a vertical line', two([[2, 1], [2, 5], [2, 9]], reg()));
add(G, 'r-vertical-poly', 'all x equal, polynomial', two([[2, 1], [2, 5], [2, 9]], reg({ method: 'polynomial' })));
add(G, 'r-equal', 'all points equal', two([[4, 4], [4, 4], [4, 4], [4, 4]], reg()));
add(G, 'r-equal-exp', 'all points equal, exponential', two([[4, 4], [4, 4], [4, 4]], reg({ method: 'exponential' })));
add(G, 'r-dupx', 'duplicate x: the sort is stable (column 3 tells the rows apart)', two([[3, 1, 0, 'a'], [1, 9, 0, 'b'], [3, 2, 0, 'c'], [1, 8, 0, 'd'], [2, 5, 0, 'e'], [3, 3, 0, 'f']], reg({ formulaOn: 'all' })));
add(G, 'r-nulls', 'null, a word, a short row, a long row: dropped or kept',
  two([[1, 2], [2, null], ['a', 5], [3], [4, 8, 'extra', 9], [5, 9.5], [null, null], [6, 'x7'], [7, 13.9]], reg({ formulaOn: 'all' })));
add(G, 'r-numstr', "a numeric string: upstream lets '7' through and adds it as a string", two([[1, 2], [2, 4.5], [6, '7'], [7, 13.9]], reg()), { deviation: 'numeric-string' });
add(G, 'r-objects', 'object rows: nothing is a row of numbers', two([{ x: 1, y: 2 }, { x: 2, y: 4 }], reg()));
add(G, 'r-empty', 'an empty table', { dataset: [{ source: [] }, { transform: reg() }] });
add(G, 'r-header-only', 'a header and nothing else', two([['x', 'y']], reg({ formulaOn: 'start' })));
add(G, 'r-one-name', 'one declared dimension: the dimension list of the formula has a hole -- throws', two(LINEAR.slice(0, 5), reg(), { dimensions: ['only'] }));
add(G, 'r-one-name-none', "one declared dimension, formulaOn 'none': no list, no hole", two(LINEAR.slice(0, 5), reg({ formulaOn: 'none' }), { dimensions: ['only'] }));

// ---- histogram
const HG = 'histogram';
add(HG, 'h-girth', 'the gallery: dimension 0, no method (squareRoot)', two(GIRTH, hist({})));
add(HG, 'h-girth-1', 'the gallery: dimensions [1]', two(GIRTH, hist({ dimensions: [1] })));
add(HG, 'h-no-config', 'no config at all', two(GIRTH, hist()));
for (const m of ['squareRoot', 'scott', 'freedmanDiaconis', 'sturges']) {
  add(HG, 'h-' + m + '-uniform', m + ', 100 uniform', two(uniform(100, 3, 0, 50), hist({ method: m })));
  add(HG, 'h-' + m + '-normal', m + ', 500 normal', two(normal(500, 4, 20, 6), hist({ method: m })));
  add(HG, 'h-' + m + '-skewed', m + ', 300 skewed', two(skewed(300, 5), hist({ method: m })));
  add(HG, 'h-' + m + '-ints', m + ', 80 small integers (ties on ticks)', two(ints(80, 6, 12), hist({ method: m })));
  add(HG, 'h-' + m + '-tiny', m + ', 60 values under a thousandth', two(tiny(60, 7), hist({ method: m })));
  add(HG, 'h-' + m + '-neg', m + ', 40 negatives and positives', two(uniform(40, 8, -125, 75), hist({ method: m })));
  add(HG, 'h-' + m + '-big', m + ', 50 values in the millions', two(uniform(50, 9, 1e6, 9e6), hist({ method: m })));
  add(HG, 'h-' + m + '-three', m + ', three values', two([[1], [2], [10]], hist({ method: m })));
}
add(HG, 'h-sqrt-cap', 'squareRoot past 2500 values: 50 bins at most', two(uniform(2600, 10, 0, 1000), hist({ method: 'squareRoot' })));
// [milestone D1-D4] over 0..1000 the cap and ceil(sqrt(2600)) = 51 both
// give a step of 20; over a span of about 160 the 50 gives 5 and 51 gives 2
add(HG, 'h-sqrt-cap-step', 'squareRoot past 2500 values over a span near 160: the cap of 50 makes the step 5 (51 would make it 2)',
  two(uniform(2600, 11, 0, 160), hist({ method: 'squareRoot' })));
add(HG, 'h-equal', 'all values equal, squareRoot', two([[5], [5], [5], [5]], hist({})));
add(HG, 'h-equal-scott', 'all values equal, scott: no deviation, NaN bins -- the range throws', two([[5], [5], [5]], hist({ method: 'scott' })));
add(HG, 'h-equal-fd', 'all values equal, freedmanDiaconis: Infinity bins, step 1', two([[5], [5], [5]], hist({ method: 'freedmanDiaconis' })));
add(HG, 'h-fd-zero-iqr', 'freedmanDiaconis with a nought interquartile range', two([[0], [0], [0], [0], [0], [0], [0], [10]], hist({ method: 'freedmanDiaconis' })));
add(HG, 'h-one', 'one value', two([[3.7]], hist({})));
add(HG, 'h-scott-two', 'scott over two values: the ticks come out empty, one bin of NaN edges holds both', two([[1.03], [8.96]], hist({ method: 'scott' })));
add(HG, 'h-one-sturges', 'one value, sturges', two([[3.7]], hist({ method: 'sturges' })));
add(HG, 'h-empty', 'no value: the range throws', { dataset: [{ source: [] }, { transform: hist({}) }] });
add(HG, 'h-dim-name', 'dimensions by name, a header', two([['a', 'b']].concat(GIRTH), hist({ dimensions: ['b'], method: 'sturges' })));
add(HG, 'h-dim-single', 'dimensions a single index (not a list)', two(GIRTH, hist({ dimensions: 1, method: 'scott' })));
add(HG, 'h-nulls-all', 'no dimensions: every column must be a number', two([[1, 2], [2, null], [3, 4], ['x', 5], [5, 6], [9, 1]], hist({})));
add(HG, 'h-nulls-dim', 'dimensions [0]: only column 0 checked', two([[1, 2], [2, null], [3, 4], ['x', 5], [5, 6], [9, 1]], hist({ dimensions: [0] })));
add(HG, 'h-objects', 'object rows: no value -- throws', two([{ v: 1 }, { v: 2 }], hist({})));
add(HG, 'h-customdata', "result 1 (customData) read by a copy",
  { dataset: [{ source: clone(GIRTH) }, { transform: hist({ method: 'sturges' }) }, { fromDatasetIndex: 1, fromTransformResult: 1 }] });

// ---- clustering
const KG = 'clustering';
const ci = 2;
for (const k of [2, 3, 4, 6]) {
  add(KG, 'k-gallery-' + k, k + ' clusters over the gallery\'s points', two(CLUSTER, clu({ clusterCount: k, outputType: 'single', outputClusterIndexDimension: ci })));
}
add(KG, 'k-blobs-3d', 'three dimensions, four blobs', two(blobs(80, 31, [[0, 0, 0], [10, 0, 5], [0, 10, -5], [10, 10, 10]], 4, 3), clu({ clusterCount: 4, outputClusterIndexDimension: 3 })));
add(KG, 'k-blobs-1d', 'one dimension of two', two(blobs(40, 32, [[0, 100], [20, 0], [40, 50]], 6, 2), clu({ clusterCount: 3, dimensions: [0], outputClusterIndexDimension: 2 })));
add(KG, 'k-names', 'dimensions by name, the cluster index and the centroids named (the gallery archive)',
  two([['NAME', 'COUNT', 'PRICE']].concat(blobs(45, 33, [[1, 10, 200], [2, 60, 900], [3, 30, 500]], 30, 3).map((r, i) => ['n' + i, r[1], r[2]])),
    clu({ clusterCount: 3, dimensions: ['COUNT', 'PRICE'], outputClusterIndexDimension: { index: 3, name: 'CLUSTER_IDX' },
      outputCentroidDimensions: [{ index: 4, name: 'CENTER_COUNT' }, { index: 5, name: 'CENTER_PRICE' }] })));
add(KG, 'k-centroid-plain', 'centroid dimensions as plain indices', two(CLUSTER.slice(0, 30), clu({ clusterCount: 3, outputClusterIndexDimension: 2, outputCentroidDimensions: [3, 4] })));
add(KG, 'k-centroid-single', 'centroid dimensions a single index: nothing written', two(CLUSTER.slice(0, 30), clu({ clusterCount: 3, outputClusterIndexDimension: 2, outputCentroidDimensions: 3 })));
add(KG, 'k-centroid-short', 'one centroid dimension for two clustered', two(CLUSTER.slice(0, 20), clu({ clusterCount: 2, outputClusterIndexDimension: 2, outputCentroidDimensions: [{ index: 5, name: 'cx' }] })));
add(KG, 'k-index-far', 'the cluster index past the row, under a header of four names', two([['a', 'b', 'c', 'd']].concat(CLUSTER.slice(0, 12)), clu({ clusterCount: 2, dimensions: [0, 1], outputClusterIndexDimension: { index: 3, name: 'k' } })));
add(KG, 'k-index-over', 'the cluster index over column 0', two(CLUSTER.slice(0, 16), clu({ clusterCount: 3, outputClusterIndexDimension: 0 })));
add(KG, 'k-multiple', "outputType 'multiple' is ignored: the transform asks for single", two(CLUSTER.slice(0, 24), clu({ clusterCount: 3, outputType: 'multiple', outputClusterIndexDimension: 2 })));
add(KG, 'k-count-str', "clusterCount '3' reads as 3", two(CLUSTER.slice(0, 24), clu({ clusterCount: '3', outputClusterIndexDimension: 2 })));
add(KG, 'k-count-frac', 'clusterCount 2.5: three clusters', two(CLUSTER.slice(0, 24), clu({ clusterCount: 2.5, outputClusterIndexDimension: 2 })));
add(KG, 'k-few', 'fewer points than clusters', two([[1, 1], [5, 5], [9, 1]], clu({ clusterCount: 5, outputClusterIndexDimension: 2 })));
add(KG, 'k-dups', 'all points the same', two([[2, 2], [2, 2], [2, 2], [2, 2]], clu({ clusterCount: 2, outputClusterIndexDimension: 2 })));
add(KG, 'k-dups-two', 'two stacks of duplicates', two([[0, 0], [0, 0], [0, 0], [8, 8], [8, 8], [8, 8]], clu({ clusterCount: 2, outputClusterIndexDimension: 2 })));
add(KG, 'k-dups-three', 'two stacks of duplicates, three clusters', two([[0, 0], [0, 0], [0, 0], [8, 8], [8, 8], [8, 8]], clu({ clusterCount: 3, outputClusterIndexDimension: 2, outputCentroidDimensions: [3, 4] })));
add(KG, 'k-nulls', 'a null cell and a word: dropped, but the extents read the null as nought',
  two([[5, 6], [6, 7], [null, 9], [7, 6], ['w', 1], [20, 21], [21, 20], [22, 22]], clu({ clusterCount: 2, outputClusterIndexDimension: 2 })));
add(KG, 'k-null-extent', 'a null widens the extent of column 0 to nought: the split goes another way than with a word there',
  two([[13.1, 1.6], [12.6, 1.8], [10.7, 3.1], [14, 3.4], [12.2, 2], [10.7, 0.5], [11.2, 0.1], [12.7, 1.2], [null, 2]], clu({ clusterCount: 2, outputClusterIndexDimension: 2 })));
add(KG, 'k-word-extent', 'the same with a word in place of the null', two([[13.1, 1.6], [12.6, 1.8], [10.7, 3.1], [14, 3.4], [12.2, 2], [10.7, 0.5], [11.2, 0.1], [12.7, 1.2], ['w', 2]], clu({ clusterCount: 2, outputClusterIndexDimension: 2 })));
add(KG, 'k-header', 'a header line: dropped from the points, the names kept',
  two([['x', 'y']].concat(CLUSTER.slice(0, 20)), clu({ clusterCount: 2, outputClusterIndexDimension: { index: 2, name: 'c' } })));
add(KG, 'k-objects', 'object rows: no point at all', two([{ x: 1, y: 2 }, { x: 3, y: 4 }], clu({ clusterCount: 2, outputClusterIndexDimension: 2 })));
add(KG, 'k-many', '200 points, 8 clusters', two(blobs(200, 34, [[0, 0], [30, 0], [0, 30], [30, 30], [15, 15], [45, 15], [15, 45], [-15, 15]], 12, 2),
  clu({ clusterCount: 8, outputClusterIndexDimension: 2, outputCentroidDimensions: [3, 4] })));
add(KG, 'k-two-datasets', 'two clusterings in one chart: the second draws after the first',
  { dataset: [{ source: clone(CLUSTER) }, { transform: clu({ clusterCount: 3, outputClusterIndexDimension: 2 }) },
    { fromDatasetIndex: 0, transform: clu({ clusterCount: 4, outputClusterIndexDimension: 2 }) }] });
add(KG, 'k-centroids-copy', 'result 1, the centroids, read by a copy',
  { dataset: [{ source: clone(CLUSTER) }, { transform: clu({ clusterCount: 4, outputClusterIndexDimension: 2 }) },
    { fromDatasetIndex: 1, fromTransformResult: 1 }] });

// ---- pipes with D2's filter and sort
const PG = 'pipe';
add(PG, 'p-filter-reg', 'filter, then a regression (the life table, 2015)',
  two(LIFE, [{ type: 'filter', config: { dimension: 4, eq: 2015 } }, reg({ method: 'logarithmic' })]));
add(PG, 'p-reg-sort', 'a regression, then sorted by y desc',
  two(noisyLine(20, 41, 2, 1, 8), [reg({ formulaOn: 'all' }), { type: 'sort', config: { dimension: 1, order: 'desc' } }]));
add(PG, 'p-reg-none-sort', "formulaOn 'none' then sort: the header inherited, sorted by name",
  two([['x', 'y']].concat(noisyLine(15, 42, -1, 3, 4)), [reg({ formulaOn: 'none' }), { type: 'sort', config: { dimension: 'y', order: 'asc' } }]));
add(PG, 'p-clu-sort', 'clustering, then sorted by the cluster index',
  two(CLUSTER.slice(0, 30), [clu({ clusterCount: 3, outputClusterIndexDimension: { index: 2, name: 'cluster' } }),
    { type: 'sort', config: [{ dimension: 'cluster', order: 'asc' }, { dimension: 0, order: 'asc' }] }]));
add(PG, 'p-clu-filter', 'clustering, then only cluster 1',
  two(CLUSTER, [clu({ clusterCount: 3, outputClusterIndexDimension: 2 }), { type: 'filter', config: { dimension: 2, eq: 1 } }]));
add(PG, 'p-filter-clu', 'filter, then clustering',
  two(CLUSTER, [{ type: 'filter', config: { dimension: 1, gt: 0 } }, clu({ clusterCount: 2, outputClusterIndexDimension: 2 })]));
add(PG, 'p-sort-hist', 'sort, then a histogram', two(GIRTH, [{ type: 'sort', config: { dimension: 1, order: 'desc' } }, hist({ dimensions: [1], method: 'sturges' })]));
add(PG, 'p-hist-filter', 'a histogram, then the bins with a count over 2',
  two(normal(200, 43, 0, 3), [hist({ method: 'scott' }), { type: 'filter', config: { dimension: 'VCount', gt: 2 } }]));
add(PG, 'p-chain', 'filter in one dataset, clustering in the next, regression over the clusters',
  { dataset: [{ source: clone(CLUSTER) }, { transform: { type: 'filter', config: { dimension: 0, gt: -2 } } },
    { fromDatasetIndex: 1, transform: clu({ clusterCount: 2, outputClusterIndexDimension: 2 }) },
    { fromDatasetIndex: 2, transform: reg({ formulaOn: 'start' }) }] });

// ---- errors: upstream throws out of setOption (or out of prepareSource)
const E = (id, note, option) => add('error', id, note, option);
E('e-reg-method', 'an unknown method', two(LINEAR.slice(0, 5), reg({ method: 'quadratic' })));
E('e-reg-proto', "a method named after Object.prototype ('toString')", two(LINEAR.slice(0, 5), reg({ method: 'toString' })));
E('e-reg-dim', 'a dimension that is not there', two(LINEAR.slice(0, 5), reg({ dimensions: ['nope', 1] })));
E('e-reg-null-row', 'a null row: cloneRawData slices it', two([[1, 2], null, [3, 4]], reg()));
E('e-reg-keyed', 'a table of columns: cloneRawData refuses it', { dataset: [{ source: { x: [1, 2, 3], y: [2, 4, 7] } }, { transform: reg() }] });
E('e-poly-frac', 'polynomial order 2.5: an array of 3.5', two(PROFIT.slice(0, 6), reg({ method: 'polynomial', order: 2.5 })));
E('e-poly-neg2', 'polynomial order -2: an array of -1', two(PROFIT.slice(0, 6), reg({ method: 'polynomial', order: -2 })));
E('e-hist-method', 'an unknown binning method', two(GIRTH, hist({ method: 'rice' })));
E('e-hist-dims-empty', 'dimensions []: every value undefined', two(GIRTH, hist({ dimensions: [] })));
E('e-hist-dim', 'a dimension that is not there', two(GIRTH, hist({ dimensions: ['nope'] })));
E('e-clu-count-missing', 'no clusterCount', two(CLUSTER, clu({ outputClusterIndexDimension: 2 })));
E('e-clu-count-zero', 'clusterCount 0', two(CLUSTER, clu({ clusterCount: 0, outputClusterIndexDimension: 2 })));
E('e-clu-count-one', 'clusterCount 1: a first result with no data', two(CLUSTER, clu({ clusterCount: 1, outputClusterIndexDimension: 2 })));
E('e-clu-count-frac', 'clusterCount 1.5: under two, no result', two(CLUSTER, clu({ clusterCount: 1.5, outputClusterIndexDimension: 2 })));
E('e-clu-count-word', "clusterCount 'many'", two(CLUSTER, clu({ clusterCount: 'many', outputClusterIndexDimension: 2 })));
E('e-clu-no-index', 'no outputClusterIndexDimension', two(CLUSTER, clu({ clusterCount: 3 })));
E('e-clu-index-word', "outputClusterIndexDimension 'x'", two(CLUSTER, clu({ clusterCount: 3, outputClusterIndexDimension: 'x' })));
E('e-clu-index-obj', 'outputClusterIndexDimension without an index', two(CLUSTER, clu({ clusterCount: 3, outputClusterIndexDimension: { name: 'c' } })));
E('e-clu-dim', 'a dimension that is not there', two(CLUSTER, clu({ clusterCount: 3, dimensions: [0, 'nope'], outputClusterIndexDimension: 2 })));
E('e-clu-no-config', 'no config', two(CLUSTER, clu()));
E('e-clu-centroid-bad', 'a centroid dimension that is no dimension config', two(CLUSTER, clu({ clusterCount: 2, outputClusterIndexDimension: 2, outputCentroidDimensions: ['a'] })));
E('e-clu-index-far', 'the cluster index two past the names: a hole in the dimensions', two(CLUSTER.slice(0, 12), clu({ clusterCount: 2, outputClusterIndexDimension: 4 })));
E('e-downstream', 'a dataset reading a clustering that threw', { dataset: [{ source: clone(CLUSTER) }, { transform: clu({ clusterCount: 0 }) },
  { fromDatasetIndex: 1, transform: reg() }] });

// ---- charts over the transforms (the gallery's)
const R = (id, note, option) => add('render', id, note, option);
R('rr-linear', 'scatter-linear-regression: the scatter and the line with its formula label',
  { dataset: [{ source: clone(LINEAR) }, { transform: reg() }], xAxis: {}, yAxis: {},
    series: [{ name: 'scatter', type: 'scatter' },
      { name: 'line', type: 'line', datasetIndex: 1, symbolSize: 0.1, symbol: 'circle', label: { show: true, fontSize: 16 }, encode: { label: 2, tooltip: 1 } }] });
R('rr-exp', 'data-transform-ecStat.html: exponential on a category axis',
  { dataset: [{ source: clone(GDP) }, { transform: reg({ method: 'exponential' }) }], xAxis: { type: 'category' }, yAxis: {},
    series: [{ name: 'scatter', type: 'scatter', datasetIndex: 0 },
      { name: 'regression', type: 'line', symbolSize: 0.1, symbol: 'circle', datasetIndex: 1, label: { show: true, fontSize: 16 }, encode: { label: 2, tooltip: 1 } }] });
R('rr-log', 'scatter-logarithmic-regression: two filtered scatters and the curve over dataset 0',
  { dataset: [{ source: clone(LIFE) }, { transform: { type: 'filter', config: { dimension: 4, eq: 1990 } } },
    { transform: { type: 'filter', config: { dimension: 4, eq: 2015 } } }, { transform: reg({ method: 'logarithmic' }) }],
    xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ name: '1990', type: 'scatter', datasetIndex: 1 }, { name: '2015', type: 'scatter', datasetIndex: 2 },
      { name: 'line', type: 'line', datasetIndex: 3, symbolSize: 0.1, symbol: 'circle', label: { show: true, fontSize: 16 }, encode: { label: 2, tooltip: 1 } }] });
R('rr-poly', 'scatter-polynomial-regression: order 3, yAxis min -40',
  { dataset: [{ source: clone(PROFIT) }, { transform: reg({ method: 'polynomial', order: 3 }) }],
    xAxis: { splitNumber: 20 }, yAxis: { min: -40 },
    series: [{ name: 'scatter', type: 'scatter' },
      { name: 'line', type: 'line', datasetIndex: 1, symbolSize: 0.1, symbol: 'circle', label: { show: true, fontSize: 16 }, encode: { label: 2, tooltip: 1 } }] });
R('rr-hist', 'bar-histogram: the scatter and the two histograms on three grids',
  { dataset: [{ source: clone(GIRTH) }, { transform: hist({}) }, { transform: hist({ dimensions: [1] }) }],
    grid: [{ top: '50%', right: '50%' }, { bottom: '52%', right: '50%' }, { top: '50%', left: '52%' }],
    xAxis: [{ scale: true, gridIndex: 0 }, { type: 'category', scale: true, axisTick: { show: false }, axisLabel: { show: false }, axisLine: { show: false }, gridIndex: 1 },
      { scale: true, gridIndex: 2 }],
    yAxis: [{ gridIndex: 0 }, { gridIndex: 1 }, { type: 'category', axisTick: { show: false }, axisLabel: { show: false }, axisLine: { show: false }, gridIndex: 2 }],
    series: [{ name: 'origianl scatter', type: 'scatter', xAxisIndex: 0, yAxisIndex: 0, encode: { tooltip: [0, 1] }, datasetIndex: 0 },
      { name: 'histogram', type: 'bar', xAxisIndex: 1, yAxisIndex: 1, barWidth: '99.3%', label: { show: true, position: 'top' }, encode: { x: 0, y: 1, itemName: 4 }, datasetIndex: 1 },
      { name: 'histogram', type: 'bar', xAxisIndex: 2, yAxisIndex: 2, barWidth: '99.3%', label: { show: true, position: 'right' }, encode: { x: 1, y: 0, itemName: 4 }, datasetIndex: 2 }] });
R('rr-hist-names', 'a histogram on a category axis named by DisplayableName',
  { dataset: [{ source: clone(normal(150, 44, 50, 10)) }, { transform: hist({ method: 'sturges' }) }],
    xAxis: { type: 'category' }, yAxis: {},
    series: [{ type: 'bar', datasetIndex: 1, barWidth: '99.3%', encode: { x: 'DisplayableName', y: 'VCount' }, label: { show: true } }] });
const PIECES = [];
const COLOURS = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
for (let i = 0; i < 6; i++) PIECES.push({ value: i, label: 'cluster ' + i, color: COLOURS[i] });
R('rr-cluster', 'scatter-clustering: six clusters coloured by visualMap pieces',
  { dataset: [{ source: clone(CLUSTER) }, { transform: clu({ clusterCount: 6, outputType: 'single', outputClusterIndexDimension: 2 }) }],
    visualMap: { type: 'piecewise', top: 'middle', min: 0, max: 6, left: 10, splitNumber: 6, dimension: 2, pieces: clone(PIECES) },
    grid: { left: 120 }, xAxis: {}, yAxis: {},
    series: { type: 'scatter', encode: { tooltip: [0, 1] }, symbolSize: 15, itemStyle: { borderColor: '#555' }, datasetIndex: 1 } });
R('rr-cluster-centroids', 'clustered points and their centroids (result 1) as a second scatter',
  { dataset: [{ source: clone(CLUSTER) }, { transform: clu({ clusterCount: 3, outputClusterIndexDimension: 2 }) },
    { fromDatasetIndex: 1, fromTransformResult: 1 }],
    visualMap: { type: 'piecewise', show: false, dimension: 2, seriesIndex: 0, pieces: clone(PIECES.slice(0, 3)) },
    xAxis: {}, yAxis: {},
    series: [{ type: 'scatter', datasetIndex: 1, symbolSize: 8 }, { type: 'scatter', datasetIndex: 2, symbolSize: 20, label: { show: true, formatter: 'c' } }] });
R('rr-error', 'a series over a regression that throws: upstream refuses the option',
  { dataset: [{ source: clone(LINEAR) }, { transform: reg({ method: 'nope' }) }], xAxis: {}, yAxis: {},
    series: [{ type: 'line', datasetIndex: 1 }] });

// ---------------------------------------------------------------------------
// guards: expectations worked out by hand
// ---------------------------------------------------------------------------
function guards(o) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => {
    const c = o.cases.find(x => x.id === id);
    must(c, 'no case ' + id);
    return c;
  };
  const res = (id, k, r) => {
    const ds = cs(id).datasets[k];
    must(ds && !ds.error, id + ': dataset ' + k + ' threw: ' + (ds && ds.error));
    return ds.results.find(x => x.r === (r || 0));
  };
  const err = (id, k) => cs(id).datasets[k].error;
  const rows = (id, k, r) => res(id, k, r).rows;
  const str = c => (c && c.slice(0, 2) === 's:' ? c.slice(2) : null);
  const formula = (id, k) => rows(id, k || 1).map(r => str(r[2])).filter(s => s);

  guard('y = 2x + 1 exactly, sorted by x', JSON.stringify(formula('r-linear-exact')) === JSON.stringify(['y = 2x + 1'])
    && rows('r-linear-exact', 1).map(r => num(r[0])).join() === '1,2,3' && rows('r-linear-exact', 1).map(r => num(r[1])).join() === '3,5,7');
  guard('the formula on the last point only', str(rows('r-linear', 1).slice(-1)[0][2]) !== null
    && rows('r-linear', 1).slice(0, -1).every(r => str(r[2]) === ''));
  guard('start: on the first point only', str(rows('r-linear-start', 1)[0][2]).indexOf('y = ') === 0
    && rows('r-linear-start', 1).slice(1).every(r => str(r[2]) === ''));
  guard('start: the header is not a point, the names come through', rows('r-linear-start', 1).length === 20
    && JSON.stringify(res('r-linear-start', 1).dims) === JSON.stringify(['x', 'y', null]));
  guard('all: on every point', rows('r-linear-all', 1).every(r => str(r[2]).indexOf('y = ') === 0));
  guard("none: the header line comes first, two columns", res('r-linear-none', 1).startIndex === 1
    && str(rows('r-linear-none', 1)[0][0]) === 'x' && rows('r-linear-none', 1)[1].length === 2);
  guard("none over declared names: inherited", JSON.stringify(res('r-linear-none-declared', 1).dims) === JSON.stringify(['u', 'v']));
  guard("an unknown formulaOn: empty strings everywhere", rows('r-linear-other', 1).every(r => str(r[2]) === ''));
  guard('wide: column 2 replaced by the formula, column 0 kept', rows('r-linear-wide', 1).every(r => typeof r[0] === 'string' && r[0].slice(0, 2) !== 's:')
    && JSON.stringify(res('r-linear-wide', 1).dims) === JSON.stringify(['a', 'b', null, 'd']));
  guard('one dimension: NaN in the formula', formula('r-linear-one-dim')[0] === 'y = NaNx + NaN');
  guard('three dimensions: the rows with a null or a word in column 2 dropped', rows('r-linear-three-dims', 1).length === 3);
  guard('negative intercept prints "+ -"', formula('r-linear-negative')[0].indexOf('x + -') > 0);
  guard('through the origin: "y = kx"', /^y = -?[0-9.]+x$/.test(formula('r-origin')[0]));
  guard('exponential: "e^("', formula('r-exp')[0].indexOf('e^(') > 0);
  guard('exponential over a nought: NaN', formula('r-exp-neg')[0].indexOf('NaN') > 0);
  guard('logarithmic: "ln(x)", strings in column 3 kept', formula('r-log')[0].indexOf('ln(x)') > 0
    && rows('r-log', 1).every(r => str(r[3]) !== null));
  guard('polynomial exact: y = 1x^2 + -3x + 2', formula('r-poly-exact')[0] === 'y = 1x^2 + -3x + 2');
  guard('order -1: "y = " and y nought', JSON.stringify(formula('r-poly-neg1')) === JSON.stringify(['y = ']) && str(rows('r-poly-neg1', 1).slice(-1)[0][2]) === 'y = '
    && rows('r-poly-neg1', 1).every(r => num(r[1]) === 0));
  guard('order null is 2', JSON.stringify(formula('r-poly-null')) === JSON.stringify(formula('r-poly-null')) && /x\^2 \+/.test(formula('r-poly-null')[0]));
  guard('one point: NaN', formula('r-one')[0] === 'y = NaNx + NaN');
  guard('duplicate x: stable', rows('r-dupx', 1).map(r => str(r[3])).join('') === 'bdeacf');
  guard('nulls: four rows kept', rows('r-nulls', 1).length === 4);
  guard('object rows: no point', rows('r-objects', 1).length === 0);
  guard('one declared dimension: a hole throws, none does not', err('r-one-name', 1) !== null && err('r-one-name-none', 1) === null);
  guard('the histogram names', JSON.stringify(res('h-girth', 1).dims) === JSON.stringify(['MeanOfV0V1', 'VCount', 'V0', 'V1', 'DisplayableName']));
  const total = id => rows(id, 1).reduce((s, r) => s + num(r[1]), 0);
  guard('the gallery bins hold every value', total('h-girth') === 31 && total('h-girth-1') === 31);
  guard('the bins are contiguous', ['h-girth', 'h-scott-normal', 'h-freedmanDiaconis-skewed', 'h-sturges-tiny'].every(id =>
    rows(id, 1).every((r, i, a) => i === 0 || num(r[2]) === num(a[i - 1][3]))));
  guard('squareRoot caps at 50 bins', rows('h-sqrt-cap', 1).length <= 52);
  guard('the cap decides the step', rows('h-sqrt-cap-step', 1).length <= 40);
  guard('scott over equal values throws', err('h-equal-scott', 1) === 'RangeError');
  guard('scott over two values: one bin, NaN edges, both counted', rows('h-scott-two', 1).length === 1
    && num(rows('h-scott-two', 1)[0][1]) === 2 && isNaN(num(rows('h-scott-two', 1)[0][2])) && str(rows('h-scott-two', 1)[0][4]) === 'NaN - NaN');
  guard('no value throws', err('h-empty', 1) === 'RangeError' && err('h-objects', 1) === 'RangeError');
  guard('no dimensions: rows with a null dropped', total('h-nulls-all') === 4 && total('h-nulls-dim') === 5);
  guard('customData: [x0, x1, count]', rows('h-customdata', 2).length === rows('h-customdata', 1).length && res('h-customdata', 2).clone);
  for (const k of [2, 3, 4, 6]) {
    const id = 'k-gallery-' + k;
    const idx = rows(id, 1).map(r => num(r[2]));
    guard(id + ': every point in a cluster below ' + k, idx.length === 60 && idx.every(v => v >= 0 && v < k && v === Math.floor(v))
      && new Set(idx).size === k);
    guard(id + ': ' + k + ' centroids', rows(id, 1, 1).length === k);
    guard(id + ': k (k - 1) x dims draws', cs(id).draws === k * (k - 1) * 2);
  }
  guard('3-D blobs: 4 x 3 x 3 draws', cs('k-blobs-3d').draws === 4 * 3 * 3);
  guard('named: the cluster and centroid names', JSON.stringify(res('k-names', 1).dims) === JSON.stringify(['NAME', 'COUNT', 'PRICE', 'CLUSTER_IDX', 'CENTER_COUNT', 'CENTER_PRICE']));
  guard('centroid dimensions single: two columns and the index', rows('k-centroid-single', 1)[0].length === 3);
  guard('index past the row: a hole in the row', rows('k-index-far', 1)[0].length === 4 && rows('k-index-far', 1)[0][2] === null);
  guard("clusterCount '3' and 2.5 make three", rows('k-count-str', 1, 1).length === 3 && rows('k-count-frac', 1, 1).length === 3);
  guard('two clusterings draw one after the other', cs('k-two-datasets').draws === 3 * 2 * 2 + 4 * 3 * 2);
  guard('object rows: no point', rows('k-objects', 1).length === 0);
  guard('a null in the extents changes the split', JSON.stringify(rows('k-null-extent', 1)) !== JSON.stringify(rows('k-word-extent', 1)));
  guard('the chain runs three steps', rows('p-chain', 3).length === rows('p-chain', 2).length);
  const errs = ['e-reg-method', 'e-reg-proto', 'e-reg-dim', 'e-reg-null-row', 'e-reg-keyed', 'e-poly-frac', 'e-poly-neg2', 'e-hist-method',
    'e-hist-dims-empty', 'e-hist-dim', 'e-clu-count-missing', 'e-clu-count-zero', 'e-clu-count-one', 'e-clu-count-frac', 'e-clu-count-word',
    'e-clu-no-index', 'e-clu-index-word', 'e-clu-index-far', 'e-clu-index-obj', 'e-clu-dim', 'e-clu-no-config', 'e-clu-centroid-bad'];
  for (const id of errs) guard(id + ' throws', err(id, 1) !== null && err(id, 0) === null);
  guard('e-downstream: both throw', err('e-downstream', 1) !== null && err('e-downstream', 2) !== null);
  guard('render: the line carries one formula label', cs('rr-linear').render.series[1].labels.length === 1
    && cs('rr-linear').render.series[1].labels[0].text.indexOf('y = ') === 0);
  guard('render: the histogram bars', cs('rr-hist').render.series[1].count === rows('h-girth', 1).length);
  guard('render: six colours for six clusters', new Set(cs('rr-cluster').render.series[0].fills.map(f => f.join())).size === 6);
  guard('render: a throwing regression refuses the option', !!cs('rr-error').render.error);
  guard('a rendered case runs one clustering at most', o.cases.filter(c => c.render).every(c =>
    JSON.stringify(c.option.dataset).split('ecStat:clustering').length <= 2));
  return g;
}

// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------
function generate() {
  ecKey = null;
  const out = {
    source: DIST, ecStat: STAT, version: echarts.version, W, H, seed: SEED,
    notes: [
      'animation: false throughout; TZ=UTC.',
      'Math.random is the port\'s xorshift32 from ' + SEED + ', reset before every chart; draws counts every call of the case.',
      'the three transforms are ecStat.transform.regression / histogram / clustering, registered by this script.',
      'datasets: prepareSource() on each dataset in order (after setOption), then SourceManager._sourceList; an error is the message thrown.',
      'render: setOption + renderToSVGString; an option that throws is recorded as {error}; labels with an empty text are left out.',
    ],
    cases: CASES.map(runCase),
  };
  out.guards = guards(out);
  return out;
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (process.env.ORACLE_DUMP) console.log(json1);
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (json1.indexOf('\\u0000') >= 0) {
  console.log('FAILED: a NUL in the fixture (fpjson drops it)');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
