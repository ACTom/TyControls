// Upstream's own answers for DECALS AND ARIA (C22, batch 131):
//
// DECALS. A decal is a pattern ECharts GENERATES: createOrUpdatePatternFromDecal
// (util/decal.ts) fills the decal object's missing keys with its defaults
// (rect, symbolSize 1, keepAspect, rgba(0, 0, 0, 0.2), no background, dash 5
// by 5, rotation 0, tiles of at most 512 x 512), normalises the dash arrays
// (Math.ceil, odd lengths doubled, a number n is [n, n]) and the symbol
// array, sizes the tile by the least common multiple of the x blocks times
// the symbols' repeat and the y block times the rows, and brushes a symbol
// into every dash of every second row -- rows from -blockY, columns to twice
// the width. The pattern repeats, turned by `rotation`. Under the SVG
// renderer (this script's SSR) every symbol goes through
// painter.renderOneToVNode, which is hooked here: each pattern's symbols are
// recorded as createSymbol made them (symbolType, x, y, width, height, the
// fill), in the brush loop's order, with the tile's svgWidth / svgHeight.
//
// WHO GETS ONE. seriesStyleTask takes the series' itemStyle.decal as the
// series' `decal` visual, dataStyleTask an item's own; the aria visual
// (aria.enabled and aria.decal.show) merges a palette decal under them --
// getDecalFromPalette over aria.decal.decals (globalDefault's six), by the
// series' NAME over ONE scope that lives as long as the GlobalModel (a merge
// keeps it, a notMerge makes a new model) for a series coloured by series,
// and by each raw row's name (or its index) over a scope PER SERIES TYPE,
// new every update, for one coloured by data (a pie). A series the legend
// filtered asks nothing; treemap and sunburst have their own. decalVisual
// then makes the patterns: every item with a visual of its own takes its
// item decal or, through getItemVisual's fallback, the series'.
// LegendView: an icon takes the legend's own itemStyle.decal, or with none
// (or 'inherit') the series' style decal.
//
// visualMap's `decal`: VisualMapping has a decal handler, but
// setItemVisualFromData knows no `decal` key -- a categories piecewise map
// writes nothing ("Unknown visual type decal"), and the pieces and the
// continuous maps have no `piecewise` / `linear` mapper for it: setOption
// throws. Both are recorded.
//
// ARIA. aria.ts' setLabel writes `aria-label` on the chart's dom -- which an
// SSR chart has not ("TODO: support for SSR"), so a fake dom (setAttribute /
// getAttribute) is put on the zr before every setOption and its attributes
// cleared, and what THAT update wrote is recorded. The locale is EN.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer) at 600 x 400.
// Every option has `animation: false`.
//
//   node tools/advchart-oracle/decal-aria.js
//
// writes tests/fixtures/advchart-decal-aria.json (ORACLE_OUT overrides).
//
// ---------------------------------------------------------------------------
// Conventions
//   hex   a double as the 16 hex digits of its IEEE-754 bits, big-endian,
//         lowercase.
//   val   a value of a decal object as written: a number is "x:<hex>", a
//         string, boolean or null is itself, an array is an array of vals.
//
// Top level: source, W, H, notes[], tiles[], scenarios[], guards[], anchors[]
// A tile case: id, decal (the option's decal object, raw JSON), resolved
//   (the decal object after the defaults: every decalKey and rotation, as
//   vals), tile {w, h (svgWidth / svgHeight, numbers), rotation hex,
//   scaleX, scaleY, repeat, symbols [{type, x, y, w, h hex, fill}]}
// A scenario: id, note, steps[] {option (raw JSON), merge (true: setOption
//   without notMerge), record}
// A record
//   error     null | the exception's message (nothing else is recorded)
//   aria      {role, label} what this update wrote (null where nothing)
//   patterns[] distinct patterns of this update: {resolved, tile}
//   series[]  per series MODEL, eachRawSeries: {index, type, name (the
//             model's), filtered, decal (the series visual's pattern index or
//             null), raws [the raw index of each view row], items [pattern
//             index or null per view row], drawn (per
//             view row: the pattern index on the item element's decal
//             element, null where the element has none, '-' where there is
//             no element), area (a line's area polygon: index, null, or '-')}
//   legend[]  per legend item in order: {name, decal (index or null)}
//   facts     the aria transcription's inputs: {seriesCount, title,
//             series [{index, type, name, rows [{name, values [hex]}]}]}
// ---------------------------------------------------------------------------
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-decal-aria.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

// ---------- numbers ----------
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function val(v) {
  if (typeof v === 'number') return 'x:' + hex(v);
  if (Array.isArray(v)) return v.map(val);
  if (v === undefined) return null;
  must(v === null || typeof v === 'string' || typeof v === 'boolean', 'odd decal value ' + JSON.stringify(v));
  return v;
}
const DECAL_KEYS = ['symbol', 'symbolSize', 'symbolKeepAspect', 'color', 'backgroundColor',
  'dashArrayX', 'dashArrayY', 'rotation', 'maxTileWidth', 'maxTileHeight'];

// ---------- the symbols renderOneToVNode was handed ----------
let vnodeEl = new WeakMap();
function hookPainter(chart) {
  const painter = chart.getZr().painter;
  const orig = painter.renderOneToVNode.bind(painter);
  painter.renderOneToVNode = function (el) {
    const vnode = orig(el);
    if (vnode) vnodeEl.set(vnode, el);
    return vnode;
  };
}
function tileOfPattern(p) {
  must(p.svgElement && Array.isArray(p.svgElement.children), 'a pattern without its svg element');
  const symbols = p.svgElement.children.map(vn => {
    const el = vnodeEl.get(vn);
    must(el, 'a decal vnode not made by renderOneToVNode');
    const sh = el.shape;
    must(sh && typeof sh.symbolType === 'string', 'a decal symbol that is no SymbolClz');
    return { type: sh.symbolType, x: hex(sh.x), y: hex(sh.y), w: hex(sh.width), h: hex(sh.height),
      fill: el.style.fill == null ? null : String(el.style.fill) };
  });
  return { w: p.svgWidth, h: p.svgHeight, rotation: hex(p.rotation), scaleX: p.scaleX, scaleY: p.scaleY,
    repeat: p.repeat, symbols };
}
function resolvedOf(decal) {
  const r = {};
  for (const k of DECAL_KEYS) r[k] = val(decal[k]);
  return r;
}

// ---------- a chart ----------
function makeChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  hookPainter(chart);
  return chart;
}
function fakeDom(chart) {
  const attrs = {};
  chart.getZr().dom = {
    setAttribute(k, v) { attrs[k] = String(v); },
    getAttribute(k) { return attrs[k]; },
  };
  return attrs;
}

function findView(chart, model) {
  return chart._chartsMap ? chart._chartsMap[model.__viewId] : null;
}

function record(chart, attrs) {
  chart.renderToSVGString();
  const patterns = [];
  const keyOf = new Map();
  function patIndex(pattern, decal) {
    if (!pattern) return null;
    if (keyOf.has(pattern)) return keyOf.get(pattern);
    const rec = { resolved: decal ? resolvedOf(decal) : null, tile: tileOfPattern(pattern) };
    const sig = JSON.stringify(rec);
    let k = patterns.findIndex(p => JSON.stringify(p) === sig);
    if (k < 0) {
      k = patterns.length;
      patterns.push(rec);
    }
    keyOf.set(pattern, k);
    return k;
  }
  const model = chart.getModel();
  const series = [];
  // pair the patterns with their decal objects first: series, then items
  model.eachRawSeries(s => {
    const data = s.getData();
    const st = data.getVisual('style');
    if (st && st.decal) patIndex(st.decal, data.getVisual('decal'));
    data.each(i => {
      const ist = data.getItemVisual(i, 'style');
      if (ist && ist.decal) patIndex(ist.decal, data.getItemVisual(i, 'decal'));
    });
  });
  model.eachRawSeries(s => {
    const data = s.getData();
    const st = data.getVisual('style');
    const rec = {
      index: s.seriesIndex, type: s.subType, name: String(s.name).replace(/\0/g, '<NUL>'),
      filtered: model.isSeriesFiltered(s),
      decal: st && st.decal ? patIndex(st.decal) : null,
      raws: [], items: [], drawn: [], area: '-',
    };
    data.each(i => {
      rec.raws.push(data.getRawIndex(i));
      const ist = data.getItemVisual(i, 'style');
      rec.items.push(ist && ist.decal ? patIndex(ist.decal) : null);
      const el = data.getItemGraphicEl(i);
      if (!el || !el.getDecalElement) rec.drawn.push('-');
      else {
        const de = el.getDecalElement();
        rec.drawn.push(de ? patIndex(de.style.fill) : null);
      }
    });
    const view = findView(chart, s);
    if (view && view._polygon) {
      const de = view._polygon.getDecalElement && view._polygon.getDecalElement();
      rec.area = de ? patIndex(de.style.fill) : null;
    }
    series.push(rec);
  });
  // the legend's icons
  const legend = [];
  const lgModel = model.getComponent('legend');
  if (lgModel) {
    const lgView = chart._componentsMap[lgModel.__viewId];
    const content = lgView && lgView.getContentGroup ? lgView.getContentGroup() : null;
    if (content) {
      const items = lgModel.getData();
      content.eachChild(g => {
        let pat = null;
        let name = null;
        g.traverse(el => {
          if (el.style && el.style.decal && pat === null) pat = el.style.decal;
          if (el.type === 'text' && name === null && el.style && typeof el.style.text === 'string') name = el.style.text;
        });
        // the legend's own decal object (its defaults filled in place), where
        // the item's itemStyle names one
        let own = null;
        for (const m of items) {
          if (m.get('name') === name) {
            const d = m.getModel('itemStyle').getShallow('decal');
            if (d && typeof d === 'object') own = d;
            break;
          }
        }
        legend.push({ name, decal: pat ? patIndex(pat, own) : null });
      });
    }
  }
  // the aria transcription's inputs
  const facts = { seriesCount: model.getSeriesCount(), title: null, series: [] };
  let title = model.get('title');
  if (title && title.length) title = title[0];
  facts.title = title && title.text != null ? title.text : null;
  model.eachSeries(s => {
    const data = s.getData();
    const rows = [];
    for (let i = 0; i < data.count(); i++) {
      rows.push({ name: data.getName(i), values: data.getValues(i).map(v => (typeof v === 'number' ? hex(v) : String(v))) });
    }
    facts.series.push({ index: s.seriesIndex, type: s.subType, name: s.get('name') == null ? null : s.get('name'), rows });
  });
  return {
    error: null,
    aria: { role: attrs.role == null ? null : attrs.role, label: attrs['aria-label'] == null ? null : attrs['aria-label'] },
    patterns, series, legend, facts,
  };
}

// ---------- the tile cases ----------
const PI = Math.PI;
const TILES = [
  ['default-0', { color: 'rgba(0, 0, 0, 0.2)', dashArrayX: [1, 0], dashArrayY: [2, 5], symbolSize: 1, rotation: PI / 6 }],
  ['default-1', { color: 'rgba(0, 0, 0, 0.2)', symbol: 'circle', dashArrayX: [[8, 8], [0, 8, 8, 0]], dashArrayY: [6, 0], symbolSize: 0.8 }],
  ['default-2', { color: 'rgba(0, 0, 0, 0.2)', dashArrayX: [1, 0], dashArrayY: [4, 3], rotation: -PI / 4 }],
  ['default-3', { color: 'rgba(0, 0, 0, 0.2)', dashArrayX: [[6, 6], [0, 6, 6, 0]], dashArrayY: [6, 0] }],
  ['default-4', { color: 'rgba(0, 0, 0, 0.2)', dashArrayX: [[1, 0], [1, 6]], dashArrayY: [1, 0, 6, 0], rotation: PI / 4 }],
  ['default-5', { color: 'rgba(0, 0, 0, 0.2)', symbol: 'triangle', dashArrayX: [[9, 9], [0, 9, 9, 0]], dashArrayY: [7, 2], symbolSize: 0.75 }],
  ['empty', {}],
  ['circle', { symbol: 'circle' }],
  ['triangle', { symbol: 'triangle', symbolSize: 0.5 }],
  ['diamond', { symbol: 'diamond', dashArrayX: [6, 2], dashArrayY: [6, 2] }],
  ['pin', { symbol: 'pin', dashArrayX: 8, dashArrayY: 8 }],
  ['arrow', { symbol: 'arrow', dashArrayX: [7, 3], dashArrayY: [7, 3] }],
  ['roundRect', { symbol: 'roundRect', symbolSize: 0.9, dashArrayX: [8, 4], dashArrayY: [6, 4] }],
  ['none-sym', { symbol: 'none' }],
  ['size-0', { symbolSize: 0 }],
  ['size-1.5', { symbol: 'circle', symbolSize: 1.5, dashArrayX: [4, 6], dashArrayY: [4, 6] }],
  ['sym-row', { symbol: ['circle', 'rect'], dashArrayX: [3, 2], dashArrayY: [3, 2] }],
  ['sym-rows', { symbol: [['circle', 'rect'], ['triangle']], dashArrayX: [3, 2], dashArrayY: [3, 2] }],
  ['sym-mixed', { symbol: ['circle', ['rect', 'diamond', 'pin']], dashArrayX: [4, 1], dashArrayY: [4, 1] }],
  ['dash-num', { dashArrayX: 3, dashArrayY: 4 }],
  ['dash-ceil', { dashArrayX: 2.2, dashArrayY: [1.5, 2.01] }],
  ['dash-odd', { dashArrayX: [4, 2, 1], dashArrayY: [3, 2, 1] }],
  ['dash-nested', { dashArrayX: [[3, 2], [2, 1]], dashArrayY: [2, 1] }],
  ['dash-mixed', { dashArrayX: [5, [2, 3]], dashArrayY: [3, 3] }],
  ['dash-x-empty', { dashArrayX: [] }],
  ['dash-x-zero', { dashArrayX: 0 }],
  ['dash-y-zero', { dashArrayY: [0, 0] }],
  ['dash-y-empty', { dashArrayY: [] }],
  ['dash-zero-row', { dashArrayX: [[0, 0], [2, 2]], dashArrayY: [2, 2] }],
  ['dash-odd-row', { dashArrayX: [[3, 1, 2], [2, 2]], dashArrayY: [2, 3] }],
  ['max-w', { dashArrayX: [[7, 3], [2, 9]], dashArrayY: [3, 4], symbol: ['circle', 'rect', 'triangle'], maxTileWidth: 40 }],
  ['max-h', { dashArrayY: [5, 6, 7], maxTileHeight: 13 }],
  ['big', { dashArrayX: [[7, 3], [2, 9], [4, 4]], dashArrayY: [3, 4], symbol: [['circle', 'rect', 'triangle'], ['diamond', 'rect']] }],
  ['rot-1', { rotation: 1, dashArrayX: [4, 4], dashArrayY: [2, 6] }],
  ['rot-neg', { rotation: -0.5 }],
  ['colour', { color: 'red', backgroundColor: 'yellow' }],
  ['colour-rgba', { color: 'rgba(10, 20, 30, 0.5)', backgroundColor: 'none' }],
  ['keep-false', { symbol: 'circle', symbolKeepAspect: false, dashArrayX: [6, 2], dashArrayY: [3, 2] }],
  ['null-keys', { symbol: null, symbolSize: null, dashArrayX: null, dashArrayY: null, rotation: null }],
];

function runTile(id, decal) {
  const chart = makeChart();
  try {
    chart.setOption({
      animation: false,
      xAxis: { data: ['a'] }, yAxis: {},
      series: [{ type: 'bar', itemStyle: { decal: JSON.parse(JSON.stringify(decal)) }, data: [1] }],
    });
    chart.renderToSVGString();
    const data = chart.getModel().getSeriesByIndex(0).getData();
    const pattern = data.getVisual('style').decal;
    must(pattern, 'tile ' + id + ': no pattern');
    return { id, decal, resolved: resolvedOf(data.getVisual('decal')), tile: tileOfPattern(pattern) };
  } finally {
    chart.dispose();
  }
}

// ---------- the scenarios ----------
const CAT = { xAxis: { data: ['a', 'b', 'c'] }, yAxis: {} };
function bars(n, extra) {
  const s = [];
  for (let i = 0; i < n; i++) s.push(Object.assign({ type: 'bar', data: [1 + i, 2, 3] }, extra ? extra(i) : {}));
  return s;
}
const SCENARIOS = [
  { id: 'aria-six', note: 'aria.decal.show over seven unnamed bars and a named pair: the six defaults in turn, the seventh wraps, one name one decal',
    steps: [{ option: Object.assign({ aria: { decal: { show: true } }, legend: {} }, CAT, {
      series: bars(7).concat([{ type: 'bar', name: 'twin', data: [1] }, { type: 'bar', name: 'twin', data: [2] }]) }) }] },
  { id: 'aria-mixed', note: 'bars, a line with an area, a scatter, two pies (one scope per type), a funnel, a bar coloured by data, own decals merged over the palette',
    steps: [{ option: Object.assign({ aria: { decal: { show: true } } }, CAT, {
      series: [
        { type: 'bar', data: [1, { value: 2, itemStyle: { color: 'red' } }, 3] },
        { type: 'bar', name: 'B', itemStyle: { decal: { symbol: 'circle', dashArrayX: 3 } }, data: [1, 2, 3] },
        { type: 'line', areaStyle: {}, data: [1, 2, 3] },
        { type: 'scatter', data: [1, 2, 3] },
        { type: 'pie', center: ['20%', '30%'], radius: 40, data: [{ name: 'a', value: 1 }, { name: 'b', value: 2, itemStyle: { decal: { symbol: 'pin' } } }, { value: 3 }] },
        { type: 'pie', center: ['50%', '30%'], radius: 40, data: [{ name: 'a', value: 1 }, { name: 'c', value: 2 }] },
        { type: 'funnel', left: '70%', data: [{ name: 'a', value: 1 }, { name: 'z', value: 2 }] },
        { type: 'bar', colorBy: 'data', data: [{ value: 1, name: 'a' }, 2, { value: 3, itemStyle: { decal: { rotation: 1 } } }] },
      ] }) }] },
  { id: 'legend-filter', note: 'a series the legend filtered asks nothing; shown again by a merge it asks then',
    steps: [
      { option: Object.assign({ aria: { decal: { show: true } }, legend: { selected: { A: false } } }, CAT, {
        series: [{ type: 'bar', name: 'A', data: [1, 2, 3] }, { type: 'bar', name: 'B', data: [1, 2, 3] }, { type: 'bar', name: 'C', data: [1, 2, 3] }] }) },
      { merge: true, option: { legend: { selected: { A: true } } } },
    ] },
  { id: 'scope', note: 'the series scope outlives a merge (a renamed series picks on), not a notMerge',
    steps: [
      { option: Object.assign({ aria: { decal: { show: true } } }, CAT, { series: [{ type: 'bar', name: 'A', data: [1] }, { type: 'bar', name: 'B', data: [1] }] }) },
      { merge: true, option: { series: [{ name: 'C' }, { name: 'B' }] } },
      { merge: true, option: { series: [{ name: 'A' }, { name: 'D' }] } },
      { option: Object.assign({ aria: { decal: { show: true } } }, CAT, { series: [{ type: 'bar', name: 'D', data: [1] }, { type: 'bar', name: 'A', data: [1] }] }) },
    ] },
  { id: 'own-list', note: 'aria.decal.decals of the author: a list, then a single object',
    steps: [
      { option: Object.assign({ aria: { decal: { show: true, decals: [{ symbol: 'circle' }, { color: 'red', dashArrayX: 2 }] } } }, CAT, { series: bars(3) }) },
      { option: Object.assign({ aria: { decal: { show: true, decals: { symbol: 'diamond', rotation: 0.5 } } } }, CAT, { series: bars(2) }) },
      { option: Object.assign({ aria: { decal: { show: true, decals: [] } } }, CAT, { series: bars(2) }) },
    ] },
  { id: 'no-aria', note: 'decals without aria: the series\' itemStyle.decal, an item\'s own over it, a pie\'s series decal on every slice, a line area',
    steps: [{ option: Object.assign({}, CAT, {
      series: [
        { type: 'bar', itemStyle: { decal: { symbol: 'circle' } }, data: [1, { value: 2, itemStyle: { color: 'red' } }, { value: 3, itemStyle: { decal: { symbol: 'rect', dashArrayY: 3 } } }] },
        { type: 'bar', data: [1, { value: 2, itemStyle: { decal: { symbol: 'triangle' } } }, 3] },
        { type: 'pie', radius: 40, center: ['80%', '30%'], itemStyle: { decal: {} }, data: [1, { value: 2, itemStyle: { decal: { color: 'blue' } } }] },
        { type: 'line', areaStyle: {}, itemStyle: { decal: { symbol: 'diamond' } }, data: [3, 1, 2] },
      ] }) }] },
  { id: 'aria-off', note: 'aria without decal.show, aria.enabled false, and the legacy aria.show',
    steps: [
      { option: Object.assign({ aria: {} }, CAT, { series: bars(2) }) },
      { option: Object.assign({ aria: { enabled: false, decal: { show: true } } }, CAT, { series: bars(2) }) },
      { option: Object.assign({ aria: { show: true, decal: { show: true } } }, CAT, { series: bars(2) }) },
      { option: Object.assign({ aria: { show: false, decal: { show: true } } }, CAT, { series: bars(2) }) },
      { option: Object.assign({ aria: { decal: { show: 1 } } }, CAT, { series: bars(2) }) },
    ] },
  { id: 'merge-enable', note: 'aria written only by a merge is not enabled (the detection is initBase\'s); enabled written by a merge is',
    steps: [
      { option: Object.assign({}, CAT, { series: bars(2) }) },
      { merge: true, option: { aria: { decal: { show: true } } } },
      { merge: true, option: { aria: { enabled: true } } },
    ] },
  { id: 'sunburst', note: 'a sunburst decides its own decals and takes nothing from the series scope',
    steps: [{ option: Object.assign({ aria: { decal: { show: true } } }, CAT, {
      series: [{ type: 'sunburst', center: ['80%', '50%'], radius: 50, data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }] }, { type: 'bar', data: [1, 2] }] }) }] },
  { id: 'legend-icons', note: 'legend icons: the series\' decal, the legend\'s own, inherit, none; a pie\'s per item',
    steps: [
      { option: Object.assign({ aria: { decal: { show: true } }, legend: { data: ['A', 'B', 'C'] } }, CAT, {
        series: [{ type: 'bar', name: 'A', data: [1] }, { type: 'bar', name: 'B', data: [1] }, { type: 'bar', name: 'C', data: [1] }] }) },
      { option: Object.assign({ aria: { decal: { show: true } }, legend: { itemStyle: { decal: { symbol: 'diamond' } }, data: ['A', { name: 'B', itemStyle: { decal: 'inherit' } }, { name: 'C', itemStyle: { decal: 'none' } }] } }, CAT, {
        series: [{ type: 'bar', name: 'A', data: [1] }, { type: 'bar', name: 'B', data: [1] }, { type: 'bar', name: 'C', data: [1] }] }) },
      { option: { aria: { decal: { show: true } }, legend: {}, series: [{ type: 'pie', radius: 50, data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }, { name: 'r', value: 3 }] }] } },
      { option: { aria: { decal: { show: true } }, legend: { selected: { q: false } }, series: [{ type: 'pie', radius: 50, data: [{ name: 'p', value: 1 }, { name: 'q', value: 2 }, { name: 'r', value: 3 }] }] } },
    ] },
  { id: 'errors', note: 'a decal written as a string: seriesStyleTask and dataStyleTask set `dirty` on it and throw',
    steps: [
      { option: Object.assign({}, CAT, { series: [{ type: 'bar', itemStyle: { decal: 'none' }, data: [1] }] }) },
      { option: Object.assign({}, CAT, { series: [{ type: 'bar', data: [1, { value: 2, itemStyle: { decal: 'none' } }] }] }) },
    ] },
  { id: 'visualmap', note: 'visualMap\'s decal: categories write nothing; pieces and continuous throw',
    steps: [
      { option: Object.assign({ visualMap: { type: 'piecewise', categories: ['a', 'b'], dimension: 0, inRange: { decal: [{ symbol: 'circle' }, { symbol: 'triangle' }] }, outOfRange: { decal: { symbol: 'diamond' } } } }, CAT, { series: [{ type: 'bar', data: [1, 2, 3] }] }) },
      { option: Object.assign({ visualMap: { type: 'piecewise', pieces: [{ lt: 2 }, { gte: 2 }], dimension: 1, inRange: { decal: [{ symbol: 'circle' }, { symbol: 'triangle' }] } } }, CAT, { series: [{ type: 'bar', data: [1, 2, 3] }] }) },
      { option: Object.assign({ visualMap: { type: 'continuous', min: 0, max: 3, dimension: 1, inRange: { decal: [{ symbol: 'circle' }, { symbol: 'triangle' }] } } }, CAT, { series: [{ type: 'bar', data: [1, 2, 3] }] }) },
      { option: Object.assign({ aria: { decal: { show: true } }, visualMap: { type: 'piecewise', categories: ['a', 'b'], dimension: 0, inRange: { color: ['red', 'blue'], decal: [{ symbol: 'circle' }] } } }, CAT, { series: [{ type: 'bar', data: [1, 2, 3] }] }) },
    ] },
  // ---------------- the description ----------------
  { id: 'label-single', note: 'one series, untitled then titled, named then not',
    steps: [
      { option: Object.assign({ aria: {} }, CAT, { series: [{ type: 'bar', name: 'Sales', data: [5, 20, 36] }] }) },
      { option: Object.assign({ aria: {}, title: { text: 'Monthly' } }, CAT, { series: [{ type: 'bar', data: [5, 20, 36] }] }) },
      { option: Object.assign({ aria: {}, title: [{ text: 'First' }, { text: 'Second' }] }, CAT, { series: [{ type: 'line', name: 'L', data: [1.5, null, '-'] }] }) },
      { option: Object.assign({ aria: {}, title: { text: '' } }, CAT, { series: [{ type: 'line', name: '', data: [1] }] }) },
    ] },
  { id: 'label-multiple', note: 'several series, named and not, stacked, a horizontal bar, a scatter, a time axis',
    steps: [
      { option: Object.assign({ aria: {}, title: { text: 'T' } }, CAT, { series: [{ type: 'bar', name: 's1', stack: 'k', data: [1, 2] }, { type: 'bar', stack: 'k', data: [3, '-'] }, { type: 'line', name: 7, data: [4, 5, 6] }] }) },
      { option: { aria: {}, yAxis: { data: ['p', 'q'] }, xAxis: {}, series: [{ type: 'bar', data: [1, 2] }, { type: 'bar', name: 'h', data: [3, 4] }] } },
      { option: { aria: {}, xAxis: { type: 'value' }, yAxis: {}, series: [{ type: 'scatter', data: [[1, 2, 3], [4, 5], [0.1, -2.5e-7]] }] } },
      { option: { aria: {}, xAxis: { type: 'time' }, yAxis: {}, series: [{ type: 'line', data: [['2020-01-01', 2], [1600000000000, 5.5]] }] } },
    ] },
  { id: 'label-types', note: 'pie, funnel, gauge, radar, and the names a pie item and a bar row take',
    steps: [
      { option: { aria: {}, series: [{ type: 'pie', name: 'P', data: [{ name: 'x', value: 1 }, { value: 2 }, { name: 'z', value: 3.25 }] }] } },
      { option: { aria: {}, series: [{ type: 'funnel', data: [{ name: 'a', value: 3 }, { name: 'b', value: 1 }] }, { type: 'gauge', data: [{ name: 'g', value: 40 }] }] } },
      { option: { aria: {}, radar: { indicator: [{ name: 'x', max: 10 }, { name: 'y', max: 10 }] }, series: [{ type: 'radar', data: [{ name: 'r', value: [1, 2] }, { value: [3, 4] }] }] } },
      { option: Object.assign({ aria: {} }, CAT, { series: [{ type: 'bar', data: [{ name: 'own', value: 1 }, 2, 3] }] }) },
    ] },
  { id: 'label-maxcount', note: 'data.maxCount and series.maxCount truncate; 0 is the default 10',
    steps: [
      { option: Object.assign({ aria: { label: { data: { maxCount: 2 } } } }, CAT, { series: [{ type: 'bar', data: [1, 2, 3] }, { type: 'bar', data: [4, 5] }] }) },
      { option: Object.assign({ aria: { label: { series: { maxCount: 2 } } } }, CAT, { series: bars(4) }) },
      { option: { aria: { label: { data: { maxCount: 0 } } }, xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'bar', data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] }] } },
      { option: { aria: {}, xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'bar', data: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }] } },
    ] },
  { id: 'label-filter', note: 'a series the legend filtered is not described but is counted; a pie item filtered is not described',
    steps: [
      { option: Object.assign({ aria: {}, legend: { selected: { s1: false } } }, CAT, { series: [{ type: 'bar', name: 's1', data: [1, 2] }, { type: 'bar', name: 's2', data: [1, 2] }] }) },
      { option: { aria: {}, legend: { selected: { p1: false } }, series: [{ type: 'pie', data: [{ name: 'p1', value: 1 }, { name: 'p2', value: 2 }] }] } },
      { option: Object.assign({ aria: {}, dataZoom: [{ type: 'inside', startValue: 1, endValue: 2 }] }, { xAxis: { data: ['a', 'b', 'c', 'd'] }, yAxis: {} }, { series: [{ type: 'bar', data: [1, 2, 3, 4] }] }) },
    ] },
  { id: 'label-custom', note: 'the description, label.enabled false, the author\'s templates (under label and at the top), excludeDimensionId, replacement patterns',
    steps: [
      { option: Object.assign({ aria: { description: 'Hand written.' } }, CAT, { series: bars(1) }) },
      { option: Object.assign({ aria: { label: { description: 'Under the label.' } } }, CAT, { series: bars(1) }) },
      { option: Object.assign({ aria: { label: { enabled: false } } }, CAT, { series: bars(1) }) },
      { option: Object.assign({ aria: { label: { general: { withTitle: 'Chart <{ title }>' }, series: { multiple: { prefix: ' [{seriesCount}]', separator: { middle: ' / ', end: ' |' } } }, data: { withName: '{name}={value}', separator: { middle: '; ', end: '.' } } } }, title: { text: 'X' } }, CAT, { series: bars(2, i => ({ name: 'n' + i })) }) },
      { option: Object.assign({ aria: { general: { withoutTitle: 'Top level.' }, data: { allData: ' Values: ' } } }, CAT, { series: bars(1) }) },
      { option: Object.assign({ aria: { label: { data: { excludeDimensionId: [0] } } } }, CAT, { series: bars(1) }) },
      { option: Object.assign({ aria: {}, title: { text: 'a$&b$$c$`d' } }, CAT, { series: [{ type: 'bar', name: 'x{seriesType}y', data: [1] }] }) },
    ] },
  { id: 'label-none', note: 'no series: role only; aria.enabled false: nothing; no aria at all: nothing',
    steps: [
      { option: { aria: {}, title: { text: 'Empty' } } },
      { option: Object.assign({ aria: { enabled: false } }, CAT, { series: bars(1) }) },
      { option: Object.assign({}, CAT, { series: bars(1) }) },
      { option: Object.assign({ aria: { show: true } }, CAT, { series: bars(1) }) },
    ] },
];

function runScenario(sc) {
  let chart = makeChart();
  const steps = [];
  try {
    for (let i = 0; i < sc.steps.length; i++) {
      const st = sc.steps[i];
      const attrs = fakeDom(chart);
      let rec;
      try {
        const opt = JSON.parse(JSON.stringify(st.option));
        if (!st.merge) opt.animation = false;
        chart.setOption(opt, st.merge ? false : true);
        rec = record(chart, attrs);
      } catch (e) {
        if (e instanceof OracleError) throw e;
        rec = { error: String(e && e.message || e) };
      }
      steps.push({ i, merge: !!st.merge, option: st.option, record: rec });
      // an update that threw leaves the chart broken: the next step (never
      // a merge) starts on a new one
      if (rec.error) {
        must(i + 1 >= sc.steps.length || !sc.steps[i + 1].merge, sc.id + ': a merge after a throw');
        chart.dispose();
        chart = makeChart();
      }
    }
  } finally {
    chart.dispose();
  }
  return { id: sc.id, note: sc.note, steps };
}

// ---------- the transcriptions ----------
function ceilAll(a, mut) { return a.map(n => (mut && mut.noCeil ? n : Math.ceil(n))); }
function normX(d, mut) {
  if (!d || d.length === 0) return [[0, 0]];
  if (typeof d === 'number') { const v = mut && mut.noCeil ? d : Math.ceil(d); return [[v, v]]; }
  if (d.every(x => typeof x === 'number')) return normX([d], mut);
  return d.map(x => {
    if (typeof x === 'number') { const v = mut && mut.noCeil ? x : Math.ceil(x); return [v, v]; }
    const c = ceilAll(x, mut);
    return (c.length % 2 === 1 && !(mut && mut.oddNotDoubled)) ? c.concat(c) : c;
  });
}
function normY(d, mut) {
  if (!d || (typeof d === 'object' && d.length === 0)) return [0, 0];
  if (typeof d === 'number') { const v = mut && mut.noCeil ? d : Math.ceil(d); return [v, v]; }
  const c = ceilAll(d, mut);
  return (d.length % 2 && !(mut && mut.oddNotDoubled)) ? c.concat(c) : c;
}
function normSym(s) {
  if (!s || s.length === 0) return [['rect']];
  if (typeof s === 'string') return [[s]];
  if (s.every(x => typeof x === 'string')) return normSym([s]);
  return s.map(x => (typeof x === 'string' ? [x] : x));
}
function blockY(d) {
  let b = 0;
  for (const v of d) b += v;
  return d.length % 2 === 1 ? b * 2 : b;
}
function gcd(a, b) { return b === 0 ? a : gcd(b, a % b); }
function lcm(a, b) { return a * b / gcd(a, b); }
function unval(v) {
  if (typeof v === 'string' && v.startsWith('x:')) {
    const h = v.slice(2);
    bits.setUint32(0, parseInt(h.slice(0, 8), 16));
    bits.setUint32(4, parseInt(h.slice(8), 16));
    return bits.getFloat64(0);
  }
  if (Array.isArray(v)) return v.map(unval);
  return v;
}
// the tile from a resolved decal, as util/decal.ts brushes it
function transcribeTile(resolved, mut) {
  mut = mut || {};
  const o = {};
  for (const k of DECAL_KEYS) o[k] = unval(resolved[k]);
  const dx = normX(o.dashArrayX, mut);
  const dy = normY(o.dashArrayY, mut);
  const sym = normSym(o.symbol);
  const bx = dx.map(l => blockY(l));
  const by = blockY(dy);
  let w = 1;
  for (const b of bx) w = lcm(w, b);
  let rep = 1;
  for (const r of sym) rep = lcm(rep, r.length);
  if (!mut.noSymbolRepeat) w *= rep;
  const h = by * bx.length * (mut.heightNoSymbols ? 1 : sym.length);
  const pw = Math.max(1, Math.min(w, o.maxTileWidth));
  const ph = Math.max(1, Math.min(h, o.maxTileHeight));
  const out = [];
  let ySum = 0;
  for (const v of dy) ySum += v;
  if (ySum > 0) {
    let y = mut.yFromZero ? 0 : -by;
    let yId = 0, yIdTotal = 0, xId0 = 0;
    while (y < ph) {
      if (yId % 2 === 0) {
        const symY = (yIdTotal / 2) % sym.length;
        let x = 0, xId1 = 0, xId1Total = 0;
        while (x < (mut.xToWidth ? pw : pw * 2)) {
          let xSum = 0;
          for (const v of dx[xId0]) xSum += v;
          if (xSum <= 0) break;
          if (xId1 % 2 === 0) {
            const size = (1 - o.symbolSize) * 0.5;
            const left = x + dx[xId0][xId1] * size;
            const top = y + dy[yId] * size;
            const ww = dx[xId0][xId1] * o.symbolSize;
            const hh = dy[yId] * o.symbolSize;
            const symX = (xId1Total / 2) % sym[symY].length;
            out.push({ type: sym[symY][symX], x: hex(left), y: hex(top), w: hex(ww), h: hex(hh) });
          }
          x += dx[xId0][xId1];
          ++xId1Total;
          ++xId1;
          if (xId1 === dx[xId0].length) xId1 = 0;
        }
        ++xId0;
        if (xId0 === dx.length) xId0 = 0;
      }
      y += dy[yId];
      ++yIdTotal;
      ++yId;
      if (yId === dy.length) yId = 0;
    }
  }
  return { w: pw, h: ph, symbols: out };
}
function sameTile(t, tile) {
  if (t.w !== tile.w || t.h !== tile.h || t.symbols.length !== tile.symbols.length) return false;
  for (let i = 0; i < t.symbols.length; i++) {
    const a = t.symbols[i], b = tile.symbols[i];
    if (a.type !== b.type || a.x !== b.x || a.y !== b.y || a.w !== b.w || a.h !== b.h) return false;
  }
  return true;
}

// the EN locale's aria strings
const EN = {
  withTitle: 'This is a chart about "{title}"', withoutTitle: 'This is a chart',
  singlePrefix: '', singleWithName: ' with type {seriesType} named {seriesName}.', singleWithoutName: ' with type {seriesType}.',
  multiPrefix: '. It consists of {seriesCount} series count.',
  multiWithName: ' The {seriesId} series is a {seriesType} representing {seriesName}.',
  multiWithoutName: ' The {seriesId} series is a {seriesType}.', sepMiddle: '', sepEnd: '',
  allData: 'The data is as follows: ', partialData: 'The first {displayCnt} items are: ',
  dataWithName: 'the data for {name} is {value}', dataWithoutName: '{value}', dataMiddle: ', ', dataEnd: '. ',
};
const TYPE_NAMES = { pie: 'Pie chart', bar: 'Bar chart', line: 'Line chart', scatter: 'Scatter plot',
  effectScatter: 'Ripple scatter plot', radar: 'Radar chart', funnel: 'Funnel chart', gauge: 'Gauge', sunburst: 'Sunburst' };
function rep(str, kv) {
  let r = str;
  for (const k of Object.keys(kv)) r = r.replace(new RegExp('\\{\\s*' + k + '\\s*\\}', 'g'), kv[k]);
  return r;
}
function num(hexs) {
  bits.setUint32(0, parseInt(hexs.slice(0, 8), 16));
  bits.setUint32(4, parseInt(hexs.slice(8), 16));
  return bits.getFloat64(0);
}
// the default-locale label from the facts (author templates not modelled)
function transcribeLabel(f, mut) {
  mut = mut || {};
  const seriesCnt = f.seriesCount;
  if (seriesCnt < 1) return null;
  const maxData = 10;
  const disp = Math.min(seriesCnt, 10);
  let s = f.title ? rep(EN.withTitle, { title: f.title }) : EN.withoutTitle;
  s += rep(seriesCnt > 1 ? EN.multiPrefix : EN.singlePrefix, { seriesCount: seriesCnt });
  const labels = [];
  for (const se of f.series) {
    if (se.index >= disp) continue;
    const named = mut.nameIsModelName ? true : !!se.name;
    let t = seriesCnt > 1 ? (named ? EN.multiWithName : EN.multiWithoutName) : (named ? EN.singleWithName : EN.singleWithoutName);
    t = rep(t, { seriesId: mut.idFromOne ? se.index + 1 : se.index, seriesName: se.name, seriesType: TYPE_NAMES[se.type] || 'Chart' });
    const cnt = se.rows.length;
    t += (mut.countGe ? cnt >= maxData : cnt > maxData) ? rep(EN.partialData, { displayCnt: maxData }) : EN.allData;
    const parts = [];
    for (let i = 0; i < cnt && i < maxData; i++) {
      const r = se.rows[i];
      const v = r.values.map(x => (/^[0-9a-f]{16}$/.test(x) ? String(num(x)) : x)).join(mut.valueSepComma ? ',' : EN.dataMiddle);
      parts.push(rep(r.name ? EN.dataWithName : EN.dataWithoutName, { name: r.name, value: v }));
    }
    t += parts.join(EN.dataMiddle) + EN.dataEnd;
    labels.push(t);
  }
  s += labels.join(EN.sepMiddle) + EN.sepEnd;
  return s;
}

// ---------- generation ----------
function generate() {
  vnodeEl = new WeakMap();
  const tiles = TILES.map(([id, d]) => runTile(id, d));
  const scenarios = SCENARIOS.map(runScenario);
  return { tiles, scenarios };
}

function checks(g) {
  let tileChecks = 0;
  // T1: every recorded tile is the transcription's
  function checkTile(where, rec) {
    const t = transcribeTile(rec.resolved);
    must(sameTile(t, rec.tile), where + ': the tile transcription disagrees');
    tileChecks++;
  }
  for (const t of g.tiles) checkTile('tile ' + t.id, t);
  for (const sc of g.scenarios)
    for (const st of sc.steps)
      if (!st.record.error) st.record.patterns.forEach((p, k) => p.resolved && checkTile(sc.id + '#' + st.i + ' pattern ' + k, p));
  // L1: the default-locale descriptions are the transcription's
  let labelChecks = 0;
  const defaultLabel = sc => !/^label-custom$/.test(sc.id);
  for (const sc of g.scenarios) {
    if (!defaultLabel(sc)) continue;
    for (const st of sc.steps) {
      const r = st.record;
      if (r.error || r.aria.label == null || !r.facts) continue;
      if (st.option.aria && (st.option.aria.label || st.option.aria.description)) continue;
      must(transcribeLabel(r.facts) === r.aria.label, sc.id + '#' + st.i + ': the label transcription disagrees:\n' + transcribeLabel(r.facts) + '\n' + r.aria.label);
      labelChecks++;
    }
  }
  // the guards: each mutation of a transcription must change a named case
  const guards = [];
  function tileGuard(name, mut, caseId) {
    const t = g.tiles.find(x => x.id === caseId);
    let ok;
    try {
      ok = !sameTile(transcribeTile(t.resolved, mut), t.tile);
    } catch (e) {
      ok = true; // a mutation that cannot even run changed the case
    }
    guards.push({ name, case: caseId, ok });
  }
  tileGuard('dash not ceiled', { noCeil: true }, 'dash-ceil');
  tileGuard('odd dash not doubled', { oddNotDoubled: true }, 'dash-odd');
  tileGuard('width without the symbols repeat', { noSymbolRepeat: true }, 'sym-row');
  tileGuard('height without the symbol rows', { heightNoSymbols: true }, 'sym-rows');
  tileGuard('rows from zero', { yFromZero: true }, 'default-0');
  tileGuard('columns to the width only', { xToWidth: true }, 'default-1');
  function labelGuard(name, mut, scId, stepI) {
    const st = g.scenarios.find(x => x.id === scId).steps[stepI];
    const ok = transcribeLabel(st.record.facts, mut) !== st.record.aria.label;
    guards.push({ name, case: scId + '#' + stepI, ok });
  }
  labelGuard('series id from one', { idFromOne: true }, 'label-multiple', 0);
  labelGuard('partial at >=', { countGe: true }, 'label-maxcount', 3);
  labelGuard('values joined without the space', { valueSepComma: true }, 'label-single', 0);
  labelGuard('the model name (series\\0n) counts as a name', { nameIsModelName: true }, 'label-multiple', 1);
  const bad = guards.filter(x => !x.ok);
  must(bad.length === 0, 'guards that change nothing: ' + bad.map(x => x.name).join(', '));
  // anchors
  const anchors = [];
  function anchor(name, cond) {
    anchors.push({ name, ok: !!cond });
    must(cond, 'anchor failed: ' + name);
  }
  const step = (id, i) => g.scenarios.find(x => x.id === id).steps[i].record;
  const six = step('aria-six', 0);
  anchor('aria-six: seven bars take six distinct patterns, the seventh the first\'s',
    six.series[6].decal === six.series[0].decal && new Set(six.series.slice(0, 6).map(s => s.decal)).size === 6);
  anchor('aria-six: two series of one name share one', six.series[7].decal === six.series[8].decal);
  anchor('errors: a string decal throws', step('errors', 0).error && /dirty/.test(step('errors', 0).error));
  anchor('visualmap: categories write no decal', step('visualmap', 0).series[0].items.every(x => x === null));
  anchor('visualmap: pieces throw', !!step('visualmap', 1).error);
  anchor('label-custom: the description is the label', step('label-custom', 0).aria.label === 'Hand written.');
  anchor('label-custom: enabled false writes nothing', step('label-custom', 2).aria.role === null && step('label-custom', 2).aria.label === null);
  anchor('label-none: no series, a role and no label', step('label-none', 0).aria.role === 'img' && step('label-none', 0).aria.label === null);
  anchor('merge-enable: aria from a merge is off', step('merge-enable', 1).series.every(s => s.decal === null));
  const resolvedOf0 = (r, k) => JSON.stringify(r.patterns[r.series[k].decal].resolved);
  anchor('scope: the renamed series picks on, the old name keeps its decal',
    resolvedOf0(step('scope', 1), 0) !== resolvedOf0(step('scope', 0), 0)
    && resolvedOf0(step('scope', 1), 0) !== resolvedOf0(step('scope', 0), 1)
    && resolvedOf0(step('scope', 2), 0) === resolvedOf0(step('scope', 0), 0));
  return { guards, anchors, tileChecks, labelChecks };
}

let g1, g2, c1;
try {
  g1 = generate();
  c1 = checks(g1);
  g2 = generate();
} catch (e) {
  console.log(e instanceof OracleError ? 'SELF-CHECK FAILED: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
function assemble(g, c) {
  return JSON.stringify({
    source: 'decal-aria.js: ECharts 6.1 dist, SSR svg, ' + W + ' x ' + H,
    W, H,
    notes: [
      'tiles: the tile of each decal object as the SVG painter received its symbols (svgWidth, svgHeight, x, y, width, height)',
      'scenarios: patterns per update, the decal visual of every series and view row, what was drawn, the legend icons, the aria label written',
    ],
    tiles: g.tiles, scenarios: g.scenarios, guards: c.guards, anchors: c.anchors,
  }, null, 1);
}
const json1 = assemble(g1, c1);
const json2 = assemble(g2, c1);
const deterministic = json1 === json2;
const nSteps = g1.scenarios.reduce((n, s) => n + s.steps.length, 0);
console.log(g1.tiles.length + ' tiles, ' + g1.scenarios.length + ' scenarios (' + nSteps + ' steps); '
  + c1.tileChecks + ' tile checks, ' + c1.labelChecks + ' label checks; ' + c1.guards.length + ' guards; '
  + c1.anchors.length + ' anchors; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (!deterministic || json1.indexOf('\\u0000') >= 0) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
JSON.parse(json1);
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
