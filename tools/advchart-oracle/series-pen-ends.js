// Round 6 R6-C: the pen's ends of a series' paths -- getItemStyle's
// lineCap / lineJoin / miterLimit (borderCap, borderJoin, borderMiterLimit)
// and getLineStyle's (cap, join, miterLimit), per series type, with an item's
// own over its series', and the views' own overrides (a funnel's polygon
// joins round, a line's polyline bevels unless its lineStyle says otherwise;
// a sankey's bands, a treemap's rects, a radar's area take none).
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false), each
// case at rest: the set of (lineCap, lineJoin, miterLimit) of every stroked
// path under the series' views (a lineWidth above nought and a stroke that is
// not 'none'), the canvas' defaults where the style has none (butt, miter, 10);
// a gauge's pointer alone.
// Run: node tools/advchart-oracle/series-pen-ends.js -> tests/fixtures/advchart-series-pen-ends.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-series-pen-ends.json');
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
const W = 400;
const H = 300;
const Path = Object.getPrototypeOf(echarts.graphic.Rect.prototype).constructor;

const IS = { borderColor: '#000', borderWidth: 2, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 3 };
const LS = { width: 2, cap: 'square', join: 'round', miterLimit: 5 };
const N = ['A', 'B', 'C'];
const cart = s => ({ animation: false, xAxis: { type: 'category', data: N }, yAxis: {}, series: [s] });
const solo = s => ({ animation: false, series: [s] });
function cases() {
  return [
    ['bar', cart({ type: 'bar', itemStyle: IS, data: [3, 5, 2] })],
    ['bar.item', cart({ type: 'bar', itemStyle: IS, data: [3, { value: 5, itemStyle: { borderJoin: 'round', borderCap: 'square' } },
      { value: 2, itemStyle: { borderMiterLimit: 7 } }] })],
    ['line', cart({ type: 'line', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] })],
    ['line.default', cart({ type: 'line', lineStyle: { width: 3 }, symbol: 'none', data: [3, 5, 2] })],
    ['scatter', cart({ type: 'scatter', itemStyle: IS, data: [3, 5, 2] })],
    ['pie', solo({ type: 'pie', itemStyle: IS, data: [3, 5, 2] })],
    ['funnel', solo({ type: 'funnel', itemStyle: IS, data: [3, 5, 2] })],
    ['candle', cart({ type: 'candlestick', itemStyle: IS, data: [[2, 4, 1, 5], [3, 2, 1, 4], [1, 3, 0, 4]] })],
    ['boxplot', cart({ type: 'boxplot', itemStyle: IS, data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6], [1, 3, 4, 6, 7]] })],
    ['heatmap', { animation: false, xAxis: { type: 'category', data: N }, yAxis: { type: 'category', data: N },
      visualMap: { show: false, min: 0, max: 5 }, series: [{ type: 'heatmap', itemStyle: IS, data: [[0, 0, 1], [1, 1, 3]] }] }],
    ['radar', { animation: false, radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 }, { name: 'r', max: 10 }] },
      series: [{ type: 'radar', itemStyle: IS, lineStyle: LS, data: [{ value: [3, 5, 2] }] }] }],
    ['sunburst', solo({ type: 'sunburst', itemStyle: IS, data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }] })],
    ['graph', solo({ type: 'graph', layout: 'none', itemStyle: IS, lineStyle: LS,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 10, y: 10 }], links: [{ source: 'a', target: 'b' }] })],
    ['tree', solo({ type: 'tree', itemStyle: IS, lineStyle: LS, data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] })],
    ['sankey', solo({ type: 'sankey', itemStyle: IS, lineStyle: Object.assign({ opacity: 0.5 }, LS),
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] })],
    ['sankey.border', solo({ type: 'sankey', lineStyle: { borderColor: '#000', borderWidth: 2, borderCap: 'round',
      borderJoin: 'bevel', borderMiterLimit: 3, cap: 'square', join: 'round', miterLimit: 5 },
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] })],
    ['parallel', { animation: false, parallelAxis: [{ dim: 0 }, { dim: 1 }], series: [{ type: 'parallel', lineStyle: LS, data: [[1, 2], [3, 4]] }] }],
    ['lines', { animation: false, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: LS, data: [{ coords: [[0, 0], [5, 5]] }] }] }],
    ['gauge', solo({ type: 'gauge', itemStyle: IS, data: [{ value: 40 }] })],
    ['gauge.pointer', solo({ type: 'gauge', itemStyle: IS, pointer: { itemStyle: { borderJoin: 'round', borderMiterLimit: 6 } },
      data: [{ value: 40 }] })],
    ['pict', cart({ type: 'pictorialBar', itemStyle: IS, symbol: 'rect', data: [3, 5, 2] })],
    ['river', { animation: false, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', itemStyle: IS,
      data: [['2015/11/08', 3, 'a'], ['2015/11/09', 4, 'a']] }] }],
    ['chord', solo({ type: 'chord', itemStyle: IS, lineStyle: LS, data: [{ name: 'a' }, { name: 'b' }],
      links: [{ source: 'a', target: 'b', value: 3 }] })],
    ['escatter', cart({ type: 'effectScatter', itemStyle: IS, data: [3, 5, 2] })],
    ['polarbar', { animation: false, polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', itemStyle: IS, data: [3, 5, 2] }] }],
  ];
}

function run(id, option) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    chart.getZr().storage.getDisplayList(true);
    const set = new Set();
    let n = 0;
    (chart._chartsViews || []).forEach(v => v.group.traverse(e => {
      if (!(e instanceof Path) || e.ignore || e.invisible) return;
      const s = e.style;
      if (!(s.lineWidth > 0) || s.stroke == null || s.stroke === 'none') return;
      if ((id === 'gauge' || id === 'gauge.pointer') && e.type !== 'pointer') return;
      n++;
      set.add([s.lineCap || 'butt', s.lineJoin || 'miter', String(s.miterLimit == null ? 10 : s.miterLimit)].join('/'));
    }));
    return { id, option, stroked: n, ends: Array.from(set).sort() };
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(([id, o]) => run(id, o));
  const by = id => charts.find(c => c.id === id);
  // guards
  must(by('bar').ends.join() === 'round/bevel/3', 'bar: ' + by('bar').ends);
  must(by('bar.item').ends.length === 3, 'bar.item: ' + by('bar.item').ends);
  must(by('line').ends.indexOf('square/round/5') >= 0 && by('line').ends.indexOf('round/bevel/3') >= 0, 'line: ' + by('line').ends);
  must(by('line.default').ends.join() === 'butt/bevel/10', 'line.default: ' + by('line.default').ends);
  must(by('funnel').ends.join() === 'round/round/3', 'funnel: ' + by('funnel').ends);
  must(by('sankey').ends.join() === 'round/bevel/3', 'sankey: ' + by('sankey').ends);
  must(by('parallel').ends.join() === 'square/round/5', 'parallel: ' + by('parallel').ends);
  must(by('gauge').ends.join() === 'round/bevel/3', 'gauge: ' + by('gauge').ends);
  // a band speaks itemStyle's keys on its lineStyle (curve.useStyle(lineStyleModel.getItemStyle()))
  must(by('sankey.border').ends.join() === 'round/bevel/3', 'sankey.border: ' + by('sankey.border').ends);
  must(by('gauge.pointer').ends.join() === 'round/round/6', 'gauge.pointer: ' + by('gauge.pointer').ends);
  must(charts.every(c => c.stroked > 0), 'a case strokes nothing');
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R6-C: each case at rest, `ends` = the sorted set of lineCap/lineJoin/miterLimit of every stroked path under the '
      + 'series views (lineWidth > 0, a stroke not none), the canvas defaults butt / miter / 10 where the style has none; a '
      + 'gauge\'s pointer alone. `stroked` how many such paths.', W, H, charts };
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
