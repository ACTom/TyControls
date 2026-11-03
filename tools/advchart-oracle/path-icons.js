// Round 7 R7-S: A COMPONENT'S path:// ICON, as upstream fits it into its box.
// createSymbol(type, x, y, w, h, color, keepAspect) makes a path:// one with
// makePath(path, {}, rect, keepAspect ? 'center' : 'cover'): 'cover' stretches
// the path's own bounding rect over the whole box, 'center' fits it to its
// own aspect in the box, centred. graphic.createIcon is always 'center'.
//   legend          getDefaultLegendIcon: the legend's symbolKeepAspect
//                   (true by default); a line series' own icon
//                   (LineSeries.getLegendIcon) none -- its marker a square of
//                   0.8 of itemHeight, covered (a map series' own icon
//                   takes the legendIcon visual, never a path: a map has
//                   no symbol visual)
//   gauge           pointer.icon and anchor.icon: their own keepAspect (false
//                   by default)
//   visualMap       a piecewise one's item symbols: none (covered); a
//                   continuous one's handle and indicator: true
//   axisLine        the arrows: true
//   markLine        the end symbols (Line.createSymbol): the data's
//                   symbolKeepAspect, none by default
//   markPoint       Symbol.ts' unit box: the data's symbolKeepAspect
//   dataZoom        the handle: true
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false,
// animation off): per case, for each colour the case gives its icons, the
// union of the global bounding rects (the path's own rect through its
// global transform, the four corners' box) of the display list's paths
// filled with it -- [x, y, w, h] in hex (nothing of no size; where the case
// says `within`, only what lies inside that rect: the reader takes the
// pixels there, the axis' own line, stroked in the same colour, mostly out).
// Run: node tools/advchart-oracle/path-icons.js -> tests/fixtures/advchart-path-icons.json
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-path-icons.json');
echarts.env.node = false;
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
const TALL = 'path://M0 0L10 0L10 40L0 40Z';
const WIDE = 'path://M0 0L40 0L40 10L0 10Z';
const SQ = 'path://M0 0L10 0L10 10L0 10Z';
const MG = '#ff00ff';
const CY = '#00ffff';
const OFF = { xAxis: { show: false }, yAxis: { show: false } };
// a legend's icons: the legend's corner of the chart
const LEG = { c: MG, within: [0, 0, 200, 100] };

function cases() {
  return [
    ['legend-cover', { animation: false, legend: { left: 20, top: 20, icon: TALL, symbolKeepAspect: false,
      itemWidth: 40, itemHeight: 24 }, color: [MG], series: [{ type: 'pie', name: 'p', data: [{ name: 'a', value: 1 }],
      radius: 0, label: { show: false }, labelLine: { show: false } }] }, [LEG]],
    ['legend-keep', { animation: false, legend: { left: 20, top: 20, icon: TALL, symbolKeepAspect: true,
      itemWidth: 40, itemHeight: 24 }, color: [MG], series: [{ type: 'pie', name: 'p', data: [{ name: 'a', value: 1 }],
      radius: 0, label: { show: false }, labelLine: { show: false } }] }, [LEG]],
    // a line series' own icon whatever its legendIcon: LineSeries.getLegendIcon's square marker, covered
    ['legend-line-own', Object.assign({ animation: false, legend: { left: 20, top: 20, itemWidth: 40, itemHeight: 24 },
      xAxis: { type: 'category', data: ['a'], show: false }, yAxis: { show: false },
      series: [{ type: 'line', name: 'l', symbol: WIDE, color: MG, data: [] }] })
      // the rule, stroked in the same colour, crosses the marker: the band of the marker's width
      , [{ c: MG, within: [36, 0, 56, 100] }]],
    ['gauge-cover', { animation: false, series: [{ type: 'gauge', min: 0, max: 100, radius: 120, center: [200, 160],
      axisLine: { lineStyle: { width: 4, color: [[1, '#888888']] } }, axisTick: { show: false }, splitLine: { show: false },
      axisLabel: { show: false }, detail: { show: false }, title: { show: false },
      pointer: { icon: SQ, width: 30, length: 90, itemStyle: { color: MG } },
      // under the pointer: each one's edges stay in sight
      anchor: { show: true, icon: WIDE, size: 40, itemStyle: { color: CY }, showAbove: false },
      data: [{ value: 50 }] }] }, [MG, CY]],
    ['gauge-keep', { animation: false, series: [{ type: 'gauge', min: 0, max: 100, radius: 120, center: [200, 160],
      axisLine: { lineStyle: { width: 4, color: [[1, '#888888']] } }, axisTick: { show: false }, splitLine: { show: false },
      axisLabel: { show: false }, detail: { show: false }, title: { show: false },
      pointer: { icon: SQ, width: 30, length: 90, keepAspect: true, itemStyle: { color: MG } },
      anchor: { show: true, icon: WIDE, size: 40, keepAspect: true, itemStyle: { color: CY }, showAbove: true },
      data: [{ value: 50 }] }] }, [MG, CY]],
    ['vm-piecewise', Object.assign({ animation: false, visualMap: { type: 'piecewise', left: 20, top: 20, itemWidth: 40,
      itemHeight: 24, pieces: [{ min: 0, max: 10 }], inRange: { symbol: TALL, color: MG }, textStyle: { color: '#000' } },
      series: [{ type: 'scatter', data: [] }] }, OFF), [MG]],
    ['axis-arrow', { animation: false, grid: { left: 40, right: 60, top: 40, bottom: 40 },
      xAxis: { type: 'value', min: 0, max: 10, axisLabel: { show: false }, axisTick: { show: false }, splitLine: { show: false },
        axisLine: { symbol: ['none', SQ], symbolSize: [30, 14], lineStyle: { color: MG, width: 1 } } },
      yAxis: { type: 'value', show: false }, series: [] }, [{ c: MG, within: [332.5, 245, 400, 275] }]],
    ['markline-ends', { animation: false, xAxis: { type: 'value', min: 0, max: 10, show: false },
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      series: [{ type: 'line', data: [], markLine: { symbol: [SQ, SQ], symbolSize: [30, 12], label: { show: false },
        lineStyle: { color: MG, width: 1, type: 'solid' }, data: [[{ coord: [2, 5] }, { coord: [8, 5] }],
        // the ends' own symbolKeepAspect: fitted
        [{ coord: [2, 8], symbolKeepAspect: true, lineStyle: { color: CY } }, { coord: [8, 8], symbolKeepAspect: true }]] } }] },
    [{ c: MG, within: [0, 110, 400, 300] }, { c: CY, within: [0, 0, 400, 110] }]],
    // a markPoint's symbol (SymbolDraw: Symbol.ts' unit box, scaled): covered without symbolKeepAspect
    ['markpoint-oblong', { animation: false, xAxis: { type: 'value', min: 0, max: 10, show: false },
      yAxis: { type: 'value', min: 0, max: 10, show: false },
      series: [{ type: 'line', data: [], markPoint: { symbol: TALL, symbolSize: [40, 16], label: { show: false },
        itemStyle: { color: MG }, data: [{ coord: [3, 5] }, { coord: [7, 5], symbolKeepAspect: true, itemStyle: { color: CY } }] } }] },
    [MG, CY]],
    ['datazoom-handle', { animation: false, xAxis: { type: 'value', min: 0, max: 10, show: false }, yAxis: { show: false },
      dataZoom: [{ type: 'slider', handleIcon: WIDE, handleSize: '100%', handleStyle: { color: MG, borderWidth: 0 },
        showDataShadow: false, showDetail: false, brushSelect: false }], series: [{ type: 'line', data: [[1, 1], [9, 2]] }] },
    [MG]],
  ];
}

// a fill as the canvas takes it: '#ff00ff' and 'rgba(255,0,255,1)' alike
function sameColour(a, b) {
  if (typeof a !== 'string') return false;
  const p = echarts.color.parse(a), q = echarts.color.parse(b);
  return !!p && !!q && p.join(',') === q.join(',');
}
function bboxOf(el) {
  el.updateTransform && el.updateTransform();
  el.getBoundingRect();
  const r = el.path.getBoundingRect();
  const m = el.getComputedTransform ? el.getComputedTransform() : el.transform;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (const p of [[r.x, r.y], [r.x + r.width, r.y], [r.x, r.y + r.height], [r.x + r.width, r.y + r.height]]) {
    const x = m ? m[0] * p[0] + m[2] * p[1] + m[4] : p[0];
    const y = m ? m[1] * p[0] + m[3] * p[1] + m[5] : p[1];
    x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y);
  }
  return [x0, y0, x1, y1];
}

function run(id, option, colours) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    const list = chart.getZr().storage.getDisplayList(true);
    const icons = colours.map(spec => {
      const col = typeof spec === 'string' ? spec : spec.c;
      const within = typeof spec === 'string' ? null : spec.within;
      let u = null;
      let n = 0;
      list.forEach(el => {
        if (!el.path && typeof el.buildPath !== 'function') return;
        if (el.ignore || el.invisible || !sameColour(el.style.fill, col)) return;
        const b = bboxOf(el);
        // nothing of no size, nothing outside the part of the chart asked
        if (!(b[2] > b[0]) && !(b[3] > b[1])) return;
        if (within && !(b[0] >= within[0] && b[1] >= within[1] && b[2] <= within[2] && b[3] <= within[3])) return;
        n++;
        u = u ? [Math.min(u[0], b[0]), Math.min(u[1], b[1]), Math.max(u[2], b[2]), Math.max(u[3], b[3])] : b;
      });
      must(u, id + ': nothing filled ' + col);
      const r = { colour: col, count: n, box: [u[0], u[1], u[2] - u[0], u[3] - u[1]].map(hex) };
      if (within) r.within = within;
      return r;
    });
    return { id, option, icons };
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(([id, o, cols]) => run(id, o, cols));
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R7-S: per case and colour, the union of the global bounding rects (the path\'s own rect through its global '
      + 'transform: the box of its four corners) of the paths filled with that colour, [x, y, w, h] hex; count how many.',
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
