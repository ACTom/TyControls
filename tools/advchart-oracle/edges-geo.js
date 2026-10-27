/*
Upstream's own answers for fix batch R5-G (spec section 244), the geo side:
WHAT `excludeComponents: ['geo']` HIDES IN AN EXPORT. echarts.ts getDataURL
sets group.ignore on the view of every model of each main type it names
(_componentsMap[model.__viewId]) -- a geo component's view is a GeoView, so
the geo regions and their labels go; a map series' own geo is its series
view's MapDraw and stays; the series on a geo are series views and stay.
Read with export-loading.js' recipe: SVG SSR, a stand-in canvas painter for
the one getDataURL call whose getRenderedCanvas snapshots every view while
the excluded ones are ignored.

  node tools/advchart-oracle/edges-geo.js

writes tests/fixtures/advchart-edges-geo.json (ORACLE_OUT overrides). Per
case: id, note, W, H, option, opts (null for none), present (the sorted main
types whose views drew and were not ignored; 'series' for any chart view),
excluded (the sorted main types whose views were ignored), counts ({mainType:
displayables drawn}). maps[] the GeoJSON registered first. Two generations
byte-identical; ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-geo.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const clone = v => JSON.parse(JSON.stringify(v));

function sq(x0, y0, x1, y1) { return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]; }
const MAPS = [{ name: 'r5gsq', text: JSON.stringify({ type: 'FeatureCollection', features: [
  { type: 'Feature', properties: { name: 'A' }, geometry: { type: 'Polygon', coordinates: [sq(0, 0, 10, 10)] } },
  { type: 'Feature', properties: { name: 'B' }, geometry: { type: 'Polygon', coordinates: [sq(10, 0, 20, 10)] } }] }) }];
for (const m of MAPS) echarts.registerMap(m.name, m.text);

function groupCount(g) {
  let n = 0;
  (function walk(e) {
    if (e.ignore) return;
    if (e.isGroup) { e.eachChild(walk); return; }
    n++;
  })(g);
  return n;
}
function viewsOf(chart) {
  const out = [];
  for (const v of chart._componentsViews) {
    const m = v.__model;
    out.push({ mainType: m ? m.mainType : null, count: groupCount(v.group), ignored: !!v.group.ignore });
  }
  for (const v of chart._chartsViews) out.push({ mainType: 'series', count: groupCount(v.group), ignored: !!v.group.ignore });
  return out;
}
const uniqSorted = a => Array.from(new Set(a)).sort();

const GEO = { map: 'r5gsq', label: { show: true } };
const CASES = [
  { id: 'geo-none', note: 'a geo with labels and a scatter on it: nothing excluded',
    option: { animation: false, geo: GEO, series: [{ type: 'scatter', coordinateSystem: 'geo', data: [[5, 5], [15, 5]] }] }, opts: null },
  { id: 'geo-geo', note: "excludeComponents ['geo']: the geo view goes, the scatter on it stays",
    option: { animation: false, geo: GEO, series: [{ type: 'scatter', coordinateSystem: 'geo', data: [[5, 5], [15, 5]] }] },
    opts: { excludeComponents: ['geo'] } },
  { id: 'geo-two', note: "two geos: both views go",
    option: { animation: false, title: { text: 't' }, geo: [Object.assign({ left: 10, width: 200 }, GEO), Object.assign({ right: 10, width: 200 }, GEO)] },
    opts: { excludeComponents: ['geo'] } },
  { id: 'map-series-geo', note: "a map series on its own geo: excluding 'geo' hides nothing of it (its MapDraw is the series view's)",
    option: { animation: false, series: [{ type: 'map', map: 'r5gsq', data: [{ name: 'A', value: 1 }] }] },
    opts: { excludeComponents: ['geo'] } },
  { id: 'map-on-geo', note: "a map series drawn by the geo component it names (geoIndex): excluding 'geo' hides the regions with the data",
    option: { animation: false, geo: { map: 'r5gsq' }, series: [{ type: 'map', geoIndex: 0, data: [{ name: 'A', value: 1 }] }] },
    opts: { excludeComponents: ['geo'] } },
];

function readExport(cs) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(cs.option));
    chart.getZr().storage.getDisplayList(true);
    const painter = chart.getZr().painter;
    let seen = null;
    painter.type = 'canvas';
    painter.getType = () => 'canvas';
    painter.getRenderedCanvas = o => {
      seen = viewsOf(chart);
      return { toDataURL: () => 'data:' };
    };
    chart.getDataURL(cs.opts === null ? undefined : clone(cs.opts));
    must(seen, cs.id + ': no export');
    const counts = {};
    for (const v of seen) if (!v.ignored) counts[v.mainType] = (counts[v.mainType] || 0) + v.count;
    return { id: cs.id, note: cs.note, W, H, option: cs.option, opts: cs.opts,
      present: uniqSorted(seen.filter(v => v.count > 0 && !v.ignored).map(v => v.mainType)),
      excluded: uniqSorted(seen.filter(v => v.ignored).map(v => v.mainType)),
      counts };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(readExport);
  const C = id => cases.find(c => c.id === id);
  const guards = [
    { id: 'geo-drawn', ok: C('geo-none').present.includes('geo') },
    { id: 'geo-hidden', ok: !C('geo-geo').present.includes('geo') && C('geo-geo').excluded.join() === 'geo'
      && C('geo-geo').present.includes('series') },
    { id: 'map-series-stays', ok: C('map-series-geo').present.join() === 'series' && C('map-series-geo').excluded.length === 0 },
    { id: 'map-on-geo-hidden', ok: !C('map-on-geo').present.includes('geo') },
  ];
  return { doc: { source: 'tools/advchart-oracle/edges-geo.js against ' + path.basename(DIST) + ' (ECharts ' + echarts.version + ')',
    maps: MAPS, exports: cases, guards }, bad: guards.filter(g => !g.ok) };
}

try {
  const a = generate();
  if (a.bad.length) {
    for (const b of a.bad) console.error('GUARD FAILED: ' + b.id);
    process.exit(1);
  }
  const textA = JSON.stringify(a.doc, null, 1);
  must(textA === JSON.stringify(generate().doc, null, 1), 'two generations differ');
  fs.writeFileSync(OUT, textA + '\n');
  console.log('wrote ' + OUT + ': ' + a.doc.exports.length + ' exports, ' + a.doc.guards.length + ' guards');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e.stack);
  process.exit(1);
}
