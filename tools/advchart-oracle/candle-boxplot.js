/*
Upstream's own answers for the CANDLESTICK'S FINISH AND THE BOXPLOT -- roadmap
C1, batch 108: a candle's width (barWidth / barMaxWidth / barMinWidth in px and
in %, over a category band or a band measured from the data), the sub-pixel
snapping of its sides and its spine, the simple box, the clip, the layout on
either axis; the boxplot's layout (boxWidth bounds, several series sharing a
band, either orientation, a value base), its path, its style, its emphasis,
and the dataset transform 'boxplot' (prepareBoxplotData: quartiles, boundIQR,
itemNameFormatter, outliers); and the tooltip over both.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node, SVG renderer, 600 x 400, `animation: false`. Charts are
created with ssr: true and then chart._ssr = false. TooltipView refuses to run
under node, so env.node is switched off and getDom answers an empty object on
the chart prototype (the recipe of tooltip-finish.js); pointer events go
straight to zrender's Handler.

  node tools/advchart-oracle/candle-boxplot.js

writes tests/fixtures/advchart-candle-boxplot.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers are the 16 hex digits of the IEEE double (big-endian, lowercase);
counts, flags and option values are plain JSON.

Top level: source, version, W, H, notes[], cases[], guards[].

cases[]: id, note, option,
  grid      [x, y, w, h] hex: the cartesian's getArea() of series 0
  axes[]    {dim, type, effective [lo, hi] hex, mapping [lo, hi] hex | null}
  series[]  {seriesIndex, type, baseDim (getBaseAxis().dim), layout
            (getWhiskerBoxesLayout, whisker types only), candleWidth hex and
            simple (candlestick only), items[]}
    items[] one per data index of a candlestick or a boxplot:
            {i, has (data.hasValue), ends (the layout's points flattened, hex)
            | null, drawn (an element is in the group), clipped (it carries
            a clip path), clip (that path's [x, y, width, height] hex | null),
            sign (candlestick), style {fill, stroke, lineWidth, opacity} |
            null, z2}
            scatter series: items[] {i, drawn, xy [x, y] hex}
  sources[] (dataset cases) {dataset, result, startIndex, dims (names) |
            null, rows (cells: a number is its hex, a string 's:' + it, null
            null)}
  tooltip   (tip cases) {trigger, at [x, y], hit {seriesIndex, dataIndex} |
            null, lines[] ({marker 'item' | 'subItem' | null, name, value})}
  emphasis  (emph cases) after dispatchAction highlight: every element of
            series 0 {i, style {fill, stroke, lineWidth, opacity, shadowBlur,
            shadowColor, shadowOffsetX, shadowOffsetY}, z2, states}

Guards (any failure: nothing is written, exit 1): expectations read off the
source -- see guards(); and the whole fixture is generated twice
(byte-identical). process.exit() ends the run.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-candle-boxplot.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
Math.random = function () { return 0; };

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
const hexArr = a => (a ? Array.from(a).map(hex) : null);
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// ---------------------------------------------------------------------------
// charts with a live TooltipView
// ---------------------------------------------------------------------------
function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
(function enableTooltips() {
  const probe = newChart();
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

const raw = (x, y) => ({ zrX: x, zrY: y, which: 1, preventDefault() {}, stopPropagation() {} });

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
function dispatcherOf(el) {
  for (let e = el; e; e = e.__hostTarget || e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return d;
  }
  return null;
}
function tooltipView(chart) {
  const m = chart.getModel().getComponent('tooltip', 0);
  return m ? chart.getViewOfComponentModel(m) : null;
}
function contentOf(chart) {
  const v = tooltipView(chart);
  return v ? v._tooltipContent : null;
}
const visible = c => !!(c && c.el && !c.el.ignore && !c.el.invisible);
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function globalRect(el) {
  const r = el.getBoundingRect().clone();
  if (el.transform) r.applyTransform(el.transform);
  return r;
}
// an integer point whose hover dispatcher matches, searched outward from the
// element's centre, the four neighbours agreeing too
function pointOn(chart, match, where) {
  const els = chart.getZr().storage.getDisplayList(true);
  const h = chart.getZr().handler;
  for (const el of els) {
    const d = dispatcherOf(el);
    if (!d || !match(d)) continue;
    const r = globalRect(el);
    const cx = Math.round(r.x + r.width / 2);
    const cy = Math.round(r.y + r.height / 2);
    const R = Math.ceil(Math.max(r.width, r.height) / 2) + 1;
    for (let rad = 0; rad <= R; rad++) {
      for (let dx = -rad; dx <= rad; dx++) {
        for (let dy = -rad; dy <= rad; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== rad) continue;
          const x = cx + dx;
          const y = cy + dy;
          if (x < 1 || y < 1 || x > W - 2 || y > H - 2) continue;
          let ok = true;
          for (const [ox, oy] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const td = dispatcherOf(h.findHover(x + ox, y + oy).target);
            if (!td || !match(td)) { ok = false; break; }
          }
          if (ok) return [x, y];
        }
      }
    }
  }
  throw new OracleError(where + ': no point on the target');
}

const SEGMENT = /\{(__EC_aUTo_\d+)\|([^}]*)\}/g;
function parseLine(line, rich, where) {
  const row = { marker: null, name: null, value: null };
  let last = 0;
  let stage = 0;
  let afterMarker = false;
  const gap = s => { must(!s || (afterMarker && !s.trim()), where + ': text outside a segment ' + JSON.stringify(s)); };
  SEGMENT.lastIndex = 0;
  let m;
  while ((m = SEGMENT.exec(line))) {
    gap(line.slice(last, m.index));
    last = SEGMENT.lastIndex;
    const st = rich[m[1]];
    must(st, where + ': no rich style ' + m[1]);
    let kind;
    if (st.width != null) kind = 0;
    else if (String(st.fontWeight) === '400') kind = 1;
    else if (String(st.fontWeight) === '900') kind = 2;
    else throw new OracleError(where + ': a segment styled ' + JSON.stringify(st));
    must(kind >= stage, where + ': segments out of order');
    stage = kind + 1;
    afterMarker = kind === 0;
    if (kind === 0) row.marker = st.width === 10 ? 'item' : 'subItem';
    else if (kind === 1) row.name = m[2];
    else row.value = m[2];
  }
  gap(line.slice(last));
  return row;
}

// ---------------------------------------------------------------------------
// the fixtures
// ---------------------------------------------------------------------------
const GRID = { left: 60, right: 40, top: 40, bottom: 50, outerBoundsMode: 'none' };
const CATS5 = ['A', 'B', 'C', 'D', 'E'];
// up, down, up, down, and a doji after a close of 15 (<= 25: up)
const K5 = [[20, 34, 10, 38], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42], [25, 25, 20, 30]];
const DAY = 86400000;
const T0 = Date.UTC(2024, 0, 1);

function base(extra) {
  return Object.assign({ animation: false, grid: GRID }, extra);
}
function candle(data, more) {
  return Object.assign({ type: 'candlestick', name: 'K', data }, more || {});
}
function catK(more, extra) {
  return base(Object.assign({ xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle(K5, more)] }, extra || {}));
}
const repeat = (n, rows) => Array.from({ length: n }, (_, i) => rows[i % rows.length]);
const catsN = n => Array.from({ length: n }, (_, i) => 'c' + i);

// boxplot rows: [min, Q1, median, Q3, max]
const BX = [[10, 20, 25, 32, 45], [5, 18, 22, 30, 40], [15, 24, 30, 36, 52]];
const BX2 = [[12, 16, 20, 28, 38], [8, 14, 21, 26, 34], [20, 26, 33, 39, 48]];
const BX3 = [[2, 10, 14, 19, 25], [4, 9, 12, 17, 30], [6, 12, 18, 22, 28]];
function box(data, more) {
  return Object.assign({ type: 'boxplot', name: 'B', data }, more || {});
}
function catB(series, extra) {
  return base(Object.assign({ xAxis: { type: 'category', data: ['P', 'Q', 'R'] }, yAxis: { type: 'value', min: 0, max: 60 },
    series }, extra || {}));
}
// raw samples for the transform
const RAW = [
  [850, 740, 900, 1070, 930, 850, 950, 980, 980, 880, 1000, 980, 930, 650, 760, 810, 1000, 1000, 960, 960],
  [960, 940, 960, 940, 880, 800, 850, 880, 900, 840, 830, 790, 810, 880, 880, 830, 800, 790, 760, 800],
  [880, 880, 880, 860, 720, 720, 620, 860, 970, 950, 880, 910, 850, 870, 840, 840, 850, 840, 840, 840],
  [890, 810, 810, 820, 800, 770, 760, 740, 750, 760, 910, 920, 890, 860, 880, 720, 840, 850, 850, 780],
  [890, 840, 780, 810, 760, 810, 790, 810, 820, 850, 870, 870, 810, 740, 810, 940, 950, 800, 810, 870],
];
const RAW_ODD = [[5], [3, 9], [7, 1, 4, 10], [2, 8, 6, 4, 20], []];
function dsBox(config, more, extra) {
  const tr = { type: 'boxplot' };
  if (config !== undefined) tr.config = config;
  return base(Object.assign({
    dataset: [{ source: more && more.raw ? more.raw : RAW }, { transform: tr }, { fromDatasetIndex: 1, fromTransformResult: 1 }],
    xAxis: { type: 'category' }, yAxis: { type: 'value' },
    series: [{ type: 'boxplot', name: 'box', datasetIndex: 1 }, { type: 'scatter', name: 'out', datasetIndex: 2 }],
  }, extra || {}));
}

const CASES = [
  // ---- the candle's width ----
  { id: 'k-default', note: 'a category band: max(min(band / 2, band), 1)', option: catK() },
  { id: 'k-bw-px', note: 'barWidth 13 (odd): taken as is', option: catK({ barWidth: 13 }) },
  { id: 'k-bw-pct', note: "barWidth '33%' of the band", option: catK({ barWidth: '33%' }) },
  { id: 'k-bw-0', note: 'barWidth 0: a width of 0, the simple box', option: catK({ barWidth: 0 }) },
  { id: 'k-bmax-px', note: 'barMaxWidth 9 under half a band', option: catK({ barMaxWidth: 9 }) },
  { id: 'k-bmax-pct', note: "barMaxWidth '15%'", option: catK({ barMaxWidth: '15%' }) },
  { id: 'k-bmin-px', note: 'barMinWidth 11 over half a band of 40 categories', option: base({
    xAxis: { type: 'category', data: catsN(40) }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle(repeat(40, K5), { barMinWidth: 11 })] }) },
  { id: 'k-bmin-pct', note: "barMinWidth '70%' beats half a band", option: catK({ barMinWidth: '70%' }) },
  { id: 'k-bmax-bmin', note: 'barMaxWidth 6, barMinWidth 10: the floor is outermost', option: catK({ barMaxWidth: 6, barMinWidth: 10 }) },
  { id: 'k-simple', note: '300 categories: one pixel wide, the simple box (<= 1.3)', option: base({
    xAxis: { type: 'category', data: catsN(300) }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle(repeat(300, K5))] }) },
  // ---- sub-pixel ----
  { id: 'k-odd-band', note: 'a fractional band (7 categories over 503 px): the sides and the spine snap', option: base({
    grid: { left: 57, right: 40, top: 40, bottom: 50, outerBoundsMode: 'none' },
    xAxis: { type: 'category', data: catsN(7) }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle(repeat(7, K5))] }) },
  { id: 'k-odd-bw', note: 'barWidth 7.3 on the fractional band', option: base({
    grid: { left: 57, right: 40, top: 40, bottom: 50, outerBoundsMode: 'none' },
    xAxis: { type: 'category', data: catsN(7) }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle(repeat(7, K5), { barWidth: 7.3 })] }) },
  { id: 'k-boundary-false', note: 'boundaryGap false: containShape widens the category mapping', option: catK(undefined,
    { xAxis: { type: 'category', data: CATS5, boundaryGap: false } }) },
  // ---- on a value or a time base: the band from the data, containShape ----
  { id: 'k-value', note: 'a value base: the band from the smallest gap; the mapping widened by half', option: base({
    xAxis: { type: 'value' }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[1, 20, 34, 10, 38], [2, 40, 35, 30, 50], [4, 31, 38, 33, 44], [7, 38, 15, 5, 42]])] }) },
  { id: 'k-value-noshape', note: 'containShape false on the value base', option: base({
    xAxis: { type: 'value', containShape: false }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[1, 20, 34, 10, 38], [2, 40, 35, 30, 50], [4, 31, 38, 33, 44], [7, 38, 15, 5, 42]])] }) },
  { id: 'k-value-single', note: 'one candle on a value base: four fifths of the axis', option: base({
    xAxis: { type: 'value' }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[3, 20, 34, 10, 38]])] }) },
  { id: 'k-value-two', note: 'two candlestick series on one value base share the gap', option: base({
    xAxis: { type: 'value' }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[1, 20, 34, 10, 38], [3, 40, 35, 30, 50]]), candle([[2.5, 31, 38, 33, 44], [6, 38, 15, 5, 42]], { name: 'K2' })] }) },
  { id: 'k-time', note: 'a time base, a day apart', option: base({
    xAxis: { type: 'time' }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[T0, 20, 34, 10, 38], [T0 + DAY, 40, 35, 30, 50], [T0 + 3 * DAY, 31, 38, 33, 44]])] }) },
  // ---- the other orientation ----
  { id: 'k-horizontal', note: 'yAxis category: the candles lie on their side', option: base({
    yAxis: { type: 'category', data: CATS5 }, xAxis: { type: 'value', min: 0, max: 60 },
    series: [candle(K5)] }) },
  { id: 'k-layout-vertical', note: "layout 'vertical' on two value axes: y is the base, the first element of the row", option: base({
    xAxis: { type: 'value', min: 0, max: 60 }, yAxis: { type: 'value' },
    series: [candle([[1, 20, 34, 10, 38], [2, 40, 35, 30, 50], [4, 31, 38, 33, 44]], { layout: 'vertical' })] }) },
  { id: 'k-x-wins', note: "layout 'vertical' with a category x: the category x wins", option: catK({ layout: 'vertical' }) },
  // ---- the clip ----
  { id: 'k-clip', note: 'min 15 max 40: one candle inside, some partly out (clipped), one wholly out (dropped)', option: base({
    xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value', min: 15, max: 40 },
    series: [candle([[20, 34, 16, 38], [40, 35, 30, 50], [31, 38, 33, 44], [8, 5, 1, 10], [25, 25, 20, 30]])] }) },
  { id: 'k-clip-false', note: 'the same with clip: false', option: base({
    xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value', min: 15, max: 40 },
    series: [candle([[20, 34, 16, 38], [40, 35, 30, 50], [31, 38, 33, 44], [8, 5, 1, 10], [25, 25, 20, 30]], { clip: false })] }) },
  { id: 'k-gap', note: "a row with a '-' and a null: no value, nothing drawn", option: catK(undefined,
    { series: [candle([[20, 34, 10, 38], [40, '-', 30, 50], [31, 38, null, 44], [38, 15, 5, 42], [25, 25, 20, 30]])] }) },
  // the cases the mutation round asked for
  { id: 'k-tiny-gap', note: 'a value base with a gap of 0.001: a band under a pixel is one pixel; barMinWidth 0', option: base({
    xAxis: { type: 'value' }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[0, 20, 34, 10, 38], [0.001, 40, 35, 30, 50], [10, 31, 38, 33, 44]], { barMinWidth: 0 })] }) },
  { id: 'k-clip-edge', note: 'min 10 max 40: a candle touching both edges is inside, not clipped', option: base({
    xAxis: { type: 'category', data: ['A', 'B'] }, yAxis: { type: 'value', min: 10, max: 40 },
    series: [candle([[20, 30, 10, 40], [15, 35, 12, 38]])] }) },
  { id: 'k-clip-frac', note: 'a fractional plot left: the clip rect floors x and widens by a pixel', option: base({
    grid: { left: 57.5, right: 40, top: 40, bottom: 50, outerBoundsMode: 'none' },
    xAxis: { type: 'category', data: CATS5 }, yAxis: { type: 'value', min: 15, max: 40 },
    series: [candle([[20, 34, 16, 38], [40, 35, 30, 50], [31, 38, 33, 44], [8, 5, 1, 10], [25, 25, 20, 30]])] }) },
  { id: 'k-encode', note: 'encode names x: no row number in front, x is the first element', option: base({
    xAxis: { type: 'category', data: ['A', 'B', 'C'] }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [candle([[0, 20, 34, 10, 38], [1, 40, 35, 30, 50], [2, 31, 38, 33, 44]], { encode: { x: 0, y: [1, 2, 3, 4] } })] }) },
  { id: 'k-doji-after-gap', note: "a doji after a row whose close is '-': the comparison is false, it is down", option: catK(undefined,
    { series: [candle([[20, 30, 10, 38], [20, '-', 10, 38], [25, 25, 20, 30], [30, 30, 25, 35], [10, 20, 5, 25]])] }) },
  { id: 'k-doji-color', note: 'borderColorDoji: a doji is sign 0 and takes it', option: catK({ itemStyle: { borderColorDoji: '#0000ff' } }) },
  // ---- the tooltip ----
  { id: 'k-tip', note: 'an item tooltip over a candle', option: catK(undefined, { tooltip: { renderMode: 'richText' } }),
    tip: { trigger: 'item', series: 0, index: 1 } },
  { id: 'k-tip-wick', note: 'an item tooltip on a wick far from the body (borderWidth 4: the stroke answers within 2 px)',
    option: catK({ itemStyle: { borderWidth: 4 } }, { tooltip: { renderMode: 'richText' },
      series: [candle([[20, 22, 5, 58], [40, 35, 30, 50], [31, 38, 33, 44], [38, 15, 5, 42], [25, 25, 20, 30]], { itemStyle: { borderWidth: 4 } })] }),
    tip: { trigger: 'item', series: 0, index: 0 } },
  { id: 'k-tip-axis', note: 'an axis tooltip over a candle', option: catK(undefined, { tooltip: { renderMode: 'richText', trigger: 'axis' } }),
    tip: { trigger: 'axis', series: 0, index: 3 } },

  // ---- the boxplot's layout ----
  { id: 'b-default', note: 'one series on a category band: boxWidth [7, 50]', option: catB([box(BX)]) },
  { id: 'b-two', note: 'two series share the band: offsets and the 50 px cap', option: catB([box(BX), box(BX2, { name: 'B2' })]) },
  { id: 'b-three', note: 'three series', option: catB([box(BX), box(BX2, { name: 'B2' }), box(BX3, { name: 'B3' })]) },
  { id: 'b-bw-px', note: 'boxWidth [20, 30]', option: catB([box(BX, { boxWidth: [20, 30] })]) },
  { id: 'b-bw-pct', note: "boxWidth ['20%', '40%'] of the band", option: catB([box(BX, { boxWidth: ['20%', '40%'] })]) },
  { id: 'b-bw-scalar', note: 'boxWidth 15: both bounds', option: catB([box(BX, { boxWidth: 15 })]) },
  { id: 'b-bw-inverted', note: 'boxWidth [60, 20]: the floor first, then the cap -- the cap wins', option: catB([box(BX, { boxWidth: [60, 20] })]) },
  { id: 'b-clip-out', note: 'max 10: a box wholly above is not drawn', option: catB([box([[1, 2, 3, 4, 5], [20, 25, 30, 35, 40], [2, 3, 4, 5, 6]])],
    { yAxis: { type: 'value', min: 0, max: 10 } }) },
  { id: 'b-tip-whisker', note: 'an item tooltip on a whisker (borderWidth 4)', option: catB([box([[2, 40, 42, 44, 58], BX[1], BX[2]],
    { itemStyle: { borderWidth: 4 } })], { tooltip: { renderMode: 'richText' } }),
    tip: { trigger: 'item', series: 0, index: 0 } },
  { id: 'b-bw-floor', note: 'boxWidth [140, 150]: the floor over the auto width', option: catB([box(BX, { boxWidth: [140, 150] })]) },
  { id: 'b-narrow', note: '40 categories, two series: the floor 7 overlaps', option: base({
    xAxis: { type: 'category', data: catsN(40) }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [box(repeat(40, BX)), box(repeat(40, BX2), { name: 'B2' })] }) },
  { id: 'b-odd', note: 'a fractional band: no snapping', option: base({
    grid: { left: 57, right: 40, top: 40, bottom: 50, outerBoundsMode: 'none' },
    xAxis: { type: 'category', data: catsN(7) }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [box(repeat(7, BX))] }) },
  { id: 'b-horizontal', note: 'yAxis category', option: base({
    yAxis: { type: 'category', data: ['P', 'Q', 'R'] }, xAxis: { type: 'value', min: 0, max: 60 },
    series: [box(BX), box(BX2, { name: 'B2' })] }) },
  { id: 'b-value', note: 'a value base: [x, min, Q1, median, Q3, max], the band from the gap', option: base({
    xAxis: { type: 'value' }, yAxis: { type: 'value', min: 0, max: 60 },
    series: [box([[1].concat(BX[0]), [3].concat(BX[1]), [4].concat(BX[2])])] }) },
  { id: 'b-layout-vertical', note: "layout 'vertical' on two value axes", option: base({
    xAxis: { type: 'value', min: 0, max: 60 }, yAxis: { type: 'value' },
    series: [box([[1].concat(BX[0]), [2].concat(BX[1])], { layout: 'vertical' })] }) },
  { id: 'b-clip', note: 'max 40: whiskers past the plot are clipped', option: catB([box(BX)], { yAxis: { type: 'value', min: 0, max: 40 } }) },
  { id: 'b-style', note: 'itemStyle color, borderColor, borderWidth; one item its own', option: catB([box([BX[0],
    { value: BX[1], itemStyle: { borderColor: '#00aa00', color: '#eeeeee' } }, BX[2]],
  { itemStyle: { color: '#ffeedd', borderColor: '#aa0000', borderWidth: 2 } })]) },
  { id: 'b-gap', note: 'a row with a null: not drawn', option: catB([box([BX[0], [5, 18, null, 30, 40], BX[2]])]) },
  // ---- the transform ----
  { id: 'bt-default', note: "dataset transform 'boxplot' (boundIQR 1.5), outliers as a scatter", option: dsBox({ itemNameFormatter: 'expr {value}' }) },
  { id: 'bt-none', note: "boundIQR 'none': the extremes", option: dsBox({ boundIQR: 'none' }) },
  { id: 'bt-zero', note: 'boundIQR 0: the extremes too', option: dsBox({ boundIQR: 0 }) },
  { id: 'bt-half', note: 'boundIQR 0.5: more outliers', option: dsBox({ boundIQR: 0.5 }) },
  { id: 'bt-string', note: "boundIQR '1': coerced by the multiplication", option: dsBox({ boundIQR: '1' }) },
  { id: 'bt-noconfig', note: 'no config at all', option: dsBox(undefined) },
  { id: 'bt-fmt-twice', note: "itemNameFormatter '{value}/{value}': only the first replaced", option: dsBox({ itemNameFormatter: '{value}/{value}' }) },
  { id: 'bt-odd', note: 'lists of 1, 2, 4, 5 and 0 samples: the quantile interpolation and an empty row', option: dsBox({}, { raw: RAW_ODD }) },
  { id: 'bt-direct', note: 'the boxplot reads the transform dataset by datasetIndex, the outliers by fromTransformResult', option: dsBox({ boundIQR: 0.5 }, undefined,
    { yAxis: { type: 'value', min: 500, max: 1200 } }) },
  // ---- tooltip ----
  { id: 'b-tip', note: 'an item tooltip over a box', option: catB([box(BX)], { tooltip: { renderMode: 'richText' } }),
    tip: { trigger: 'item', series: 0, index: 1 } },
  { id: 'b-tip-axis', note: 'an axis tooltip over two boxplot series', option: catB([box(BX), box(BX2, { name: 'B2' })], { tooltip: { renderMode: 'richText', trigger: 'axis' } }),
    tip: { trigger: 'axis', series: 1, index: 2 } },
  { id: 'bt-tip', note: "an item tooltip over a transformed box: the transform's dimension names", option: dsBox({ itemNameFormatter: 'expr {value}' }, undefined, { tooltip: { renderMode: 'richText' } }),
    tip: { trigger: 'item', series: 0, index: 2 } },
  { id: 'bt-tip-outlier', note: 'an item tooltip over an outlier', option: dsBox({ itemNameFormatter: 'expr {value}' }, undefined, { tooltip: { renderMode: 'richText' } }),
    tip: { trigger: 'item', series: 1, index: 0 } },
  // ---- emphasis ----
  { id: 'b-emph', note: 'highlight one box: borderWidth 2, the shadow, the fill lifted, z2 + 10', option: catB([box(BX)]),
    emph: { series: 0, index: 1 } },
  { id: 'b-emph-declared', note: 'an emphasis itemStyle of its own', option: catB([box(BX, { emphasis: { itemStyle: { color: '#ffff00', borderColor: '#ff0000', borderWidth: 3 } } })]),
    emph: { series: 0, index: 0 } },
  { id: 'b-emph-focus', note: "focus 'self': the other boxes blur", option: catB([box(BX, { emphasis: { focus: 'self' } })]),
    emph: { series: 0, index: 2 } },
];

// ---------------------------------------------------------------------------
// recording
// ---------------------------------------------------------------------------
function styleOf(el) {
  if (!el) return null;
  const s = el.style;
  return { fill: s.fill == null ? null : String(s.fill), stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: s.lineWidth == null ? null : hex(s.lineWidth), opacity: s.opacity == null ? null : hex(s.opacity) };
}
function fullStyleOf(el) {
  const o = styleOf(el);
  const s = el.style;
  o.shadowBlur = s.shadowBlur == null ? null : hex(s.shadowBlur);
  o.shadowColor = s.shadowColor == null ? null : String(s.shadowColor);
  o.shadowOffsetX = s.shadowOffsetX == null ? null : hex(s.shadowOffsetX);
  o.shadowOffsetY = s.shadowOffsetY == null ? null : hex(s.shadowOffsetY);
  return o;
}
function cellOut(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  return 's:' + String(v);
}
function seriesOut(s) {
  const data = s.getData();
  const o = { seriesIndex: s.seriesIndex, type: s.subType, baseDim: s.getBaseAxis ? s.getBaseAxis().dim : null };
  const items = [];
  if (s.subType === 'candlestick' || s.subType === 'boxplot') {
    o.layout = s.getWhiskerBoxesLayout();
    if (s.subType === 'candlestick') {
      o.candleWidth = hex(data.getLayout('candleWidth'));
      o.simple = !!data.getLayout('isSimpleBox');
    }
    for (let i = 0; i < data.count(); i++) {
      const lay = data.getItemLayout(i);
      const el = data.getItemGraphicEl(i);
      const drawn = !!(el && el.parent);
      const it = {
        i, has: data.hasValue(i),
        ends: lay && lay.ends ? [].concat(...lay.ends).map(hex) : null,
        drawn, clipped: !!(drawn && el.getClipPath()),
        clip: drawn && el.getClipPath() ? ['x', 'y', 'width', 'height'].map(k => hex(el.getClipPath().shape[k])) : null,
        style: drawn ? styleOf(el) : null,
        z2: drawn ? el.z2 : null,
      };
      if (s.subType === 'candlestick') it.sign = lay ? lay.sign : null;
      if (drawn && s.subType === 'candlestick') it.simpleBox = !!el.__simpleBox;
      items.push(it);
    }
  } else if (s.subType === 'scatter') {
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      const lay = data.getItemLayout(i);
      items.push({ i, drawn: !!(el && el.parent), xy: lay ? [lay[0], lay[1]].map(hex) : null });
    }
  }
  o.items = items;
  return o;
}
function sourcesOut(chart) {
  const out = [];
  const m = chart.getModel();
  let n = 0;
  m.eachComponent('dataset', () => { n++; });
  for (let k = 0; k < n; k++) {
    const mgr = m.getComponent('dataset', k).getSourceManager();
    mgr.prepareSource();
    for (let r = 0; r < 2; r++) {
      const src = mgr._sourceList[r];
      if (!src) continue;
      must(Array.isArray(src.data), 'a source that is not an array');
      out.push({ dataset: k, result: r, startIndex: src.startIndex,
        dims: src.dimensionsDefine ? src.dimensionsDefine.map(d => d.name) : null,
        rows: src.data.map(row => (Array.isArray(row) ? row.map(cellOut) : cellOut(row))) });
    }
  }
  return out;
}
function axesOut(chart) {
  const out = [];
  for (const dim of ['x', 'y']) {
    const comp = chart.getModel().getComponent(dim + 'Axis', 0);
    const ax = comp.axis;
    const map = ax.scale.getExtentUnsafe(1, null);
    out.push({ dim, type: ax.type, effective: hexArr(ax.scale.getExtent()), mapping: map ? hexArr(map) : null });
  }
  return out;
}
function tipOut(chart, c) {
  const t = c.tip;
  const match = d => d.seriesIndex === t.series && d.dataIndex === t.index;
  const at = pointOn(chart, match, c.id);
  const d = dispatcherOf(chart.getZr().handler.findHover(at[0], at[1]).target);
  const content = contentOf(chart);
  const view = tooltipView(chart);
  let params = null;
  const show = view._showTooltipContent;
  view._showTooltipContent = function (tooltipModel, html, p) {
    params = p;
    return show.apply(this, arguments);
  };
  chart.getZr().handler.mousemove(raw(at[0], at[1]));
  frame(chart);
  must(visible(content), c.id + ': no box');
  must(params, c.id + ': no params');
  must(Array.isArray(params) === (t.trigger === 'axis'), c.id + ': the trigger');
  const text = String(content.el.style.text);
  const lines = text.split('\n').map(line => parseLine(line, content.el.style.rich || {}, c.id));
  return { trigger: t.trigger, at, hit: d ? { seriesIndex: d.seriesIndex, dataIndex: d.dataIndex } : null, lines };
}
function emphOut(chart, c) {
  const e = c.emph;
  chart.dispatchAction({ type: 'highlight', seriesIndex: e.series, dataIndex: e.index });
  frame(chart);
  const data = chart.getModel().getSeriesByIndex(e.series).getData();
  const out = [];
  for (let i = 0; i < data.count(); i++) {
    const el = data.getItemGraphicEl(i);
    if (!el) continue;
    out.push({ i, style: fullStyleOf(el), z2: el.z2, states: (el.currentStates || []).slice() });
  }
  return out;
}

function runCase(c) {
  const option = clone(c.option);
  const chart = newChart();
  try {
    chart.setOption(clone(option));
    frame(chart);
    const rec = { id: c.id, note: c.note, option };
    const s0 = chart.getModel().getSeriesByIndex(0);
    const area = s0.coordinateSystem.getArea();
    rec.grid = [area.x, area.y, area.width, area.height].map(hex);
    rec.axes = axesOut(chart);
    rec.series = [];
    chart.getModel().eachSeries(s => rec.series.push(seriesOut(s)));
    if (option.dataset) rec.sources = sourcesOut(chart);
    if (c.tip) rec.tooltip = tipOut(chart, c);
    if (c.emph) rec.emphasis = emphOut(chart, c);
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// guards: expectations read off the source
// ---------------------------------------------------------------------------
function guards(o) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => o.cases.find(c => c.id === id);
  const s0 = id => cs(id).series[0];
  const ends = (id, si, i) => cs(id).series[si].items[i].ends.map(num);
  const area = id => cs(id).grid.map(num);
  // candlestickLayout.calculateCandleWidth
  const band5 = area('k-default')[2] / 5;
  guard('the default candle is half a band', num(s0('k-default').candleWidth) === band5 / 2);
  guard('barWidth 13 is 13', num(s0('k-bw-px').candleWidth) === 13);
  guard("barWidth '33%' is a third of the band", num(s0('k-bw-pct').candleWidth) === band5 * 0.33);
  guard('barWidth 0 is 0 and the simple box', num(s0('k-bw-0').candleWidth) === 0 && s0('k-bw-0').simple);
  guard('barMaxWidth 9 caps', num(s0('k-bmax-px').candleWidth) === 9);
  guard('barMinWidth 10 beats barMaxWidth 6', num(s0('k-bmax-bmin').candleWidth) === 10);
  guard('barMinWidth 11 floors', num(s0('k-bmin-px').candleWidth) === 11);
  guard('300 categories: the simple box', s0('k-simple').simple && s0('k-simple').items[0].simpleBox);
  // subPixelOptimize on the sides (lineWidth 1: x.5) and the spine
  const e = ends('k-odd-band', 0, 0);
  guard('the snapped sides sit on half pixels', [0, 2, 4, 6, 8, 10, 12, 14].every(k => Math.abs(e[k] * 2 % 2) === 1));
  // containShape on a value base
  const mx = cs('k-value').axes[0];
  guard('a value base under a candlestick has a mapping extent', mx.mapping !== null);
  guard('containShape false: no mapping', cs('k-value-noshape').axes[0].mapping === null);
  // the clip
  const kc = s0('k-clip').items;
  guard('a candle wholly out is not drawn', !kc[3].drawn && kc[3].has);
  guard('a candle partly out is clipped', kc[1].drawn && kc[1].clipped);
  guard('a candle inside is not clipped', kc[0].drawn && !kc[0].clipped);
  guard('clip false draws them all, unclipped', s0('k-clip-false').items.every(it => it.drawn && !it.clipped));
  guard("a '-' and a null: not drawn", !s0('k-gap').items[1].drawn && !s0('k-gap').items[2].drawn);
  guard('borderColorDoji: sign 0', s0('k-doji-color').items[4].sign === 0);
  guard('the horizontal candlestick is laid out on y', s0('k-horizontal').baseDim === 'y' && s0('k-horizontal').layout === 'vertical');
  guard("layout 'vertical' on two value axes: y", s0('k-layout-vertical').baseDim === 'y');
  guard('a category x wins over layout', s0('k-x-wins').baseDim === 'x');
  // boxplotLayout
  const bw = (id, si) => { const p = ends(id, si, 0); return p[2] - p[0]; };
  const bandB = area('b-default')[2] / 3;
  guard('one box: min(max(0.8 band - 2, 7), 50)', bw('b-default', 0) === Math.min(Math.max(bandB * 0.8 - 2, 7), 50));
  guard('boxWidth [20, 30] caps at 30', bw('b-bw-px', 0) === 30);
  guard('boxWidth 15 is 15', bw('b-bw-scalar', 0) === 15);
  guard('the floor 140 wins', bw('b-bw-floor', 0) === 140);
  guard('a box path has 14 points', s0('b-default').items[0].ends.length === 28);
  guard("the boxplot draws in the series colour with a white fill", s0('b-default').items[0].style.fill === '#fff');
  guard('the boxplot on its side', s0('b-horizontal').baseDim === 'y');
  guard('max 40 clips a whisker', s0('b-clip').items[2].clipped);
  guard('a null row is not drawn', !s0('b-gap').items[1].drawn);
  guard('the cap after the floor', bw('b-bw-inverted', 0) === 20);
  guard('a box wholly out is not drawn', !s0('b-clip-out').items[1].drawn && s0('b-clip-out').items[0].drawn);
  guard('a candle on both edges is not clipped', s0('k-clip-edge').items.every(it => it.drawn && !it.clipped));
  const cf = s0('k-clip-frac').items.find(it => it.clipped).clip.map(num);
  guard('a fractional left: the clip floors x and widens by one', cf[0] === Math.floor(area('k-clip-frac')[0])
    && cf[2] === Math.ceil(area('k-clip-frac')[2]) + 1);
  guard('a band under a pixel is a pixel', num(s0('k-tiny-gap').candleWidth) === 0.5);
  guard('a doji after a NaN close is down', s0('k-doji-after-gap').items[2].sign === -1);
  guard('encode x: the first element is the base', s0('k-encode').items[1].has);
  // prepareBoxplotData
  const src = (id, d, r) => cs(id).sources.find(x => x.dataset === d && x.result === r);
  const t0 = src('bt-default', 1, 0);
  guard('the transform names its dimensions', JSON.stringify(t0.dims) === JSON.stringify(['ItemName', 'Low', 'Q1', 'Q2', 'Q3', 'High']));
  guard("itemNameFormatter 'expr {value}'", t0.rows[0][0] === 's:expr 0');
  guard('the outliers have no dimensions', src('bt-default', 1, 1).dims === null);
  guard('the outliers dataset is a clone of result 1', JSON.stringify(src('bt-default', 2, 0).rows) === JSON.stringify(src('bt-default', 1, 1).rows));
  guard("'{value}/{value}': the first replaced", src('bt-fmt-twice', 1, 0).rows[1][0] === 's:1/{value}');
  const tn = src('bt-none', 1, 0).rows[0];
  guard("boundIQR 'none': Low is the minimum", num(tn[1]) === Math.min(...RAW[0]));
  guard('boundIQR 0 is the same as none', JSON.stringify(src('bt-zero', 1, 0).rows) === JSON.stringify(src('bt-none', 1, 0).rows));
  const od = src('bt-odd', 1, 0).rows;
  guard('one sample: every quartile is it', od[0].slice(1).every(h => num(h) === 5));
  guard('an empty list: NaN throughout', od[4].slice(1).every(h => Number.isNaN(num(h))));
  guard('the empty row is not drawn', !cs('bt-odd').series[0].items[4].drawn);
  guard('no config: names are the index', src('bt-noconfig', 1, 0).rows[2][0] === 's:2');
  // tooltip
  guard('a candle tooltip has four sub-rows', cs('k-tip').tooltip.lines.filter(l => l.marker === null && l.value !== null).length >= 4
    || cs('k-tip').tooltip.lines.length >= 5);
  // emphasis
  const em = cs('b-emph').emphasis.find(x => x.i === 1);
  guard('emphasis: borderWidth 2', num(em.style.lineWidth) === 2);
  guard('emphasis: z2 110', em.z2 === 110);
  guard("focus 'self' blurs the others", cs('b-emph-focus').emphasis.filter(x => x.i !== 2).every(x => x.states.indexOf('blur') >= 0));
  return g;
}

// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------
function generate() {
  ecKey = null;
  const out = {
    source: DIST, version: echarts.version, W, H,
    notes: [
      'animation: false throughout; TooltipView under node with env.node off and getDom stubbed.',
      'ends: the item layout points (candlestick 8, boxplot 14), flattened x0 y0 x1 y1 ...',
      'drawn: data.getItemGraphicEl(i) is in the group; clipped: it carries a clip path (partly outside).',
      'sources: SourceManager._sourceList of every dataset, results 0 and 1.',
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
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
