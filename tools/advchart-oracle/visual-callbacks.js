/*
Upstream's own answers for round-2 batch R2-J3: THE PER-ITEM VISUAL
CALLBACKS ON EVERY SERIES. visual/symbol.ts' seriesSymbolTask calls a
series' symbol / symbolSize / symbolRotate / symbolOffset, when a function,
as cb(rawValue, getDataParams(idx)) for every item of every series that has
hasSymbolVisual (line, scatter, effectScatter, graph, radar, tree,
pictorialBar); dataSymbolTask then lays the item's own keys over them.
visual/style.ts' seriesStyleTask calls the series' colour -- the colour key
of its style path: itemStyle's fill, or the stroke of a series that draws
with it (lines and parallel read lineStyle.color, a boxplot
itemStyle.borderColor) -- as colorCallback(getDataParams(idx)) for every
item; the palette is the series' colour then, and a function at the other
key (a boxplot's itemStyle.color) is the palette's too. A markPoint's
symbol keys are its view's own (MarkPointView: symbol(rawValue, params) on
the marker's data).

The callbacks are written '@vsym', '@vsize', '@vrot', '@voff', '@vcol'
(the port registers visual handlers under those names) and answer, by the
item's dataIndex i:
  symbol        ['circle', 'rect', 'triangle', 'diamond'][i % 4]
  symbolSize    8 + 3 i
  symbolRotate  30 i
  symbolOffset  [2 i, -i]
  colour        ['#c23531', '#2f4554', '#61a0a8', '#d48265'][i % 4]
'@vnone' answers undefined (any key).

Per case: calls {key: [call...]} -- the distinct calls, each
  'v:<rawValue> i:<dataIndex> s:<seriesIndex> t:<dataType> n:<name> c:<color>'
(rawValue as String() prints it; color params.color as given) -- and items[]
{s, i, ...} what each item's element draws:
  a symbol (SymbolClz, a graph's or a tree's node; a radar's vertex k --
    its path at the vertex, no offset -- with 'k', and its line as k -1):
    sym (its symbolType), cx / cy (where the path's origin lands on the
    canvas: the group's place, the offset, a roam view's transform), gsx /
    gsy (its scale there), gx / gy (the group's place, a SymbolClz's), sx /
    sy (the path's own scale: half the size), rot (the path's rotation),
    ox / oy (the path's place: the offset), fill, stroke
  a pictorial bar: n (its glyphs), and the first glyph's symbolType
    (gsym), sx / sy / rot / fill
  anything else: fill and stroke of the element (its first path for a
    group)
  a markPoint's symbol: as a symbol, with 'mark' (s its host series, i its
    place in the marker's data)
-- numbers hex, colours as zrender holds them.

Runs the real ECharts 6.1 build (ECHARTS_DIST) in node's server-side mode as
gallery-callbacks.js does (SVG renderer, chart._ssr false, env.node off,
Math.random the port's xorshift32, zrender's width table), animation off,
600 x 400, upstream's default palette written as the option's colour.

  node tools/advchart-oracle/visual-callbacks.js

writes tests/fixtures/advchart-visual-callbacks.json (ORACLE_OUT overrides).
Top level: source, version, seed, W, H, measure {firstCode, ratio[]},
notes[], cases[] {id, note, option, calls, items[]}, guards[]. Ends with
process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

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

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-visual-callbacks.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const quiet = fn => {
  const w = console.warn;
  const e = console.error;
  console.warn = () => {};
  console.error = () => {};
  try { return fn(); } finally { console.warn = w; console.error = e; }
};

const FIRST_CODE = 32;
const LAST_CODE = 126;
const MAP_STR = (() => {
  const line = fs.readFileSync(DIST, 'utf8').split('\n').find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, DIST + ': no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
  return s;
})();
const RATIO = Array.from(MAP_STR, ch => (ch.charCodeAt(0) - 20) / 100);

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function deep(v) {
  if (typeof v === 'number') return hex(v);
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(deep);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) {
      if (v[k] === undefined) continue;
      o[k] = deep(v[k]);
    }
    return o;
  }
  return v === undefined ? null : v;
}

const SYMS = ['circle', 'rect', 'triangle', 'diamond'];
const COLS = ['#c23531', '#2f4554', '#61a0a8', '#d48265'];
const ANSWER = {
  vsym: i => SYMS[i % 4],
  vsize: i => 8 + 3 * i,
  vrot: i => 30 * i,
  voff: i => [2 * i, -i],
  vcol: i => COLS[i % 4],
  // [r2v] a callback that answers nothing (undefined) for every item
  vnone: () => undefined,
};

function callRepr(raw, p) {
  return 'v:' + String(raw) + ' i:' + p.dataIndex + ' s:' + p.seriesIndex
    + ' t:' + (p.dataType || '') + ' n:' + p.name + ' c:' + (p.color == null ? '' : String(p.color));
}

function materialize(v, log) {
  if (Array.isArray(v)) return v.map(x => materialize(x, log));
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      const s = v[k];
      if (typeof s === 'string' && s[0] === '@' && ANSWER[s.slice(1)]) {
        const key = s.slice(1);
        o[k] = key === 'vcol'
          ? function (p) {
            (log[key] = log[key] || new Set()).add(callRepr(p.value, p));
            return ANSWER[key](p.dataIndex);
          }
          : function (raw, p) {
            (log[key] = log[key] || new Set()).add(callRepr(raw, p));
            return ANSWER[key](p.dataIndex);
          };
      }
      else o[k] = materialize(s, log);
    }
    return o;
  }
  return v;
}

function col(c) {
  if (c == null) return null;
  if (typeof c === 'string') return c;
  return 'obj';
}
/* the symbol path drawn: where its origin lands on the canvas and its
   scale there (the group's and a roam view's included) */
function pathInfo(p, sym) {
  const m = p.getComputedTransform() || [1, 0, 0, 1, 0, 0];
  return {
    sym,
    cx: hex(m[4]), cy: hex(m[5]),
    gsx: hex(Math.hypot(m[0], m[1])), gsy: hex(Math.hypot(m[2], m[3])),
    sx: hex(p.scaleX), sy: hex(p.scaleY), rot: hex(p.rotation),
    ox: hex(p.x), oy: hex(p.y),
    fill: col(p.style.fill), stroke: col(p.style.stroke),
  };
}
function symInfo(el) {
  const p = el.getSymbolPath();
  return Object.assign({ gx: hex(el.x), gy: hex(el.y) },
    pathInfo(p, el.getSymbolType ? el.getSymbolType() : (p.symbolType || null)));
}
function plainInfo(el) {
  let e = el;
  if (e.isGroup) {
    let first = null;
    e.traverse(c => { if (!first && !c.isGroup && c.style) first = c; });
    e = first;
  }
  if (!e) return { none: true };
  return { type: e.type, fill: col(e.style.fill), stroke: col(e.style.stroke) };
}

function itemsOf(chart) {
  const out = [];
  chart.getModel().eachSeries((s, si) => {
    const data = s.getData();
    for (let i = 0; i < data.count(); i++) {
      const el = data.getItemGraphicEl(i);
      if (!el) { out.push({ s: si, i, none: true }); continue; }
      if (s.subType === 'pictorialBar') {
        const glyphs = [];
        el.__pictorialBundle && el.__pictorialBundle.eachChild(c => { if (c !== el.__pictorialBarRect) glyphs.push(c); });
        const g = glyphs[0];
        out.push({ s: si, i, n: glyphs.length, gsym: g && g.shape ? g.shape.symbolType || null : null,
          sx: g ? hex(g.scaleX) : null, sy: g ? hex(g.scaleY) : null, rot: g ? hex(g.rotation) : null,
          fill: g ? col(g.style.fill) : null });
        continue;
      }
      if (s.subType === 'radar') {
        // the radar's vertices: the symbol paths of the item group's third
        // child (RadarView: polyline, polygon, symbols)
        const group = el.childAt(2);
        group && group.eachChild((c, k) => out.push(Object.assign({ s: si, i, k },
          pathInfo(c, c.shape.symbolType))));
        out.push(Object.assign({ s: si, i, k: -1 }, plainInfo(el)));
        continue;
      }
      if (el.getSymbolPath) { out.push(Object.assign({ s: si, i }, symInfo(el))); continue; }
      out.push(Object.assign({ s: si, i }, plainInfo(el)));
    }
  });
  // a markPoint's symbols: its view's SymbolDraw, per host series ('mark')
  chart._componentsViews.filter(v => v.type === 'markPoint').forEach(v => {
    v.markerGroupMap.each((symbolDraw, seriesId) => {
      const sm = chart.getModel().getSeries().find(x => x.id === seriesId);
      const data = symbolDraw._data;
      if (!sm || !data) return;
      for (let i = 0; i < data.count(); i++) {
        const el = data.getItemGraphicEl(i);
        if (el && el.getSymbolPath) out.push(Object.assign({ mark: true, s: sm.seriesIndex, i }, symInfo(el)));
      }
    });
  });
  return out;
}

const cat = ['A', 'B', 'C', 'D'];
/* upstream's default palette written into every case: the control's theme
   has its own, which is not what is compared here */
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
const SYMKEYS = { symbol: '@vsym', symbolSize: '@vsize', symbolRotate: '@vrot', symbolOffset: '@voff' };
const COLOUR = { itemStyle: { color: '@vcol' } };

const CASES = [
  { id: 'line', note: 'a line: the four symbol callbacks and the colour callback; an item with its own symbolSize over the callback',
    option: { xAxis: { type: 'category', data: cat }, yAxis: {},
      series: [Object.assign({ type: 'line', data: [3, { value: 5, symbolSize: 20 }, 2, 6] }, SYMKEYS, COLOUR)] } },
  { id: 'scatter', note: 'scatter and effectScatter (done in R2-J2): the same keys',
    option: { xAxis: {}, yAxis: {},
      series: [Object.assign({ type: 'scatter', data: [[1, 3], [2, 5], [3, 2], [4, 6]] }, SYMKEYS, COLOUR),
        Object.assign({ type: 'effectScatter', data: [[1, 1], [2, 2]] }, SYMKEYS)] } },
  { id: 'graph', note: 'a graph without layout, zoomed (the symbols and their offsets under the view scale): node symbols by callback, the symbolRotate node d has over the callback; the colour callback on the nodes',
    option: { series: [Object.assign({ type: 'graph', layout: 'none', zoom: 2,
      data: [{ name: 'a', x: 10, y: 10, value: 1 }, { name: 'b', x: 100, y: 50, value: 2 }, { name: 'c', x: 50, y: 100, value: 3 }, { name: 'd', x: 150, y: 120, value: 4, symbolRotate: 45 }],
      links: [{ source: 'a', target: 'b' }, { source: 'b', target: 'c' }] }, SYMKEYS, COLOUR)] } },
  { id: 'radar', note: 'a radar of two items: symbolSize and symbol by callback, the colour callback',
    option: { radar: { indicator: [{ max: 10 }, { max: 10 }, { max: 10 }] },
      series: [Object.assign({ type: 'radar', data: [{ value: [3, 5, 7], name: 'p' }, { value: [6, 2, 4], name: 'q' }] },
        { symbol: '@vsym', symbolSize: '@vsize' }, COLOUR)] } },
  { id: 'tree', note: 'a tree: node symbolSize and symbol by callback; the colour callback, the symbols filled with it',
    option: { series: [{ type: 'tree', symbol: '@vsym', symbolSize: '@vsize', itemStyle: { color: '@vcol' },
      data: [{ name: 'r', value: 1, children: [{ name: 'a', value: 2 }, { name: 'b', value: 3 }] }] }] } },
  { id: 'pictorial', note: 'a pictorial bar: symbol, symbolSize and symbolRotate by callback; the colour callback',
    option: { xAxis: { type: 'category', data: ['a', 'b', 'c'] }, yAxis: { max: 10 },
      series: [Object.assign({ type: 'pictorialBar', data: [4, 6, 3] },
        { symbol: '@vsym', symbolSize: '@vsize', symbolRotate: '@vrot' }, COLOUR)] } },
  { id: 'bar-pie-funnel', note: 'the colour callback on a bar, a pie and a funnel',
    option: { xAxis: { type: 'category', data: cat }, yAxis: {},
      series: [Object.assign({ type: 'bar', data: [3, 5, 2, 6] }, COLOUR),
        Object.assign({ type: 'pie', center: ['80%', '30%'], radius: 40, data: [{ value: 3, name: 'p' }, { value: 5, name: 'q' }, { value: 2, name: 'r' }] }, COLOUR),
        Object.assign({ type: 'funnel', left: '70%', top: '60%', width: 100, height: 100, data: [{ value: 30, name: 'f' }, { value: 50, name: 'g' }] }, COLOUR)] } },
  { id: 'stroke-series', note: 'series that draw with the stroke: lines and parallel read lineStyle.color, a boxplot itemStyle.borderColor; a boxplot\'s itemStyle.color as a function is the palette\'s',
    option: { xAxis: [{ type: 'category', data: ['a', 'b'] }, { type: 'value', gridIndex: 1 }], yAxis: [{}, { type: 'value', gridIndex: 1 }],
      grid: [{ left: 40, top: 20, width: 200, height: 150 }, { left: 320, top: 20, width: 200, height: 150 }],
      parallel: { left: 40, top: 230, width: 500, height: 120 },
      parallelAxis: [{ dim: 0 }, { dim: 1 }, { dim: 2 }],
      series: [{ type: 'boxplot', itemStyle: { borderColor: '@vcol' }, data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] },
        { type: 'boxplot', itemStyle: { color: '@vcol' }, data: [[1, 2, 3, 4, 6], [2, 3, 4, 6, 7]] },
        { type: 'lines', coordinateSystem: 'cartesian2d', xAxisIndex: 1, yAxisIndex: 1, lineStyle: { color: '@vcol' },
          data: [{ coords: [[1, 1], [5, 5]] }, { coords: [[2, 6], [6, 2]] }] },
        { type: 'parallel', lineStyle: { color: '@vcol' }, data: [[1, 2, 3], [3, 2, 1], [2, 3, 1]] }] } },
  { id: 'markpoint', note: 'a markPoint whose symbolSize and symbol are callbacks (MarkPointView, on the marker\'s data)',
    option: { xAxis: { type: 'category', data: cat }, yAxis: {},
      series: [{ type: 'line', data: [3, 5, 2, 6], markPoint: { symbol: '@vsym', symbolSize: '@vsize', data: [{ type: 'max' }, { type: 'min' }] } }] } },
  { id: 'colour-under-visualmap', note: '[r2v] the colour callback (seriesStyleTask, stage 2000) under a piecewise visualMap (4000): the callback is still called, the items take the visualMap\'s colours',
    option: { xAxis: {}, yAxis: {},
      visualMap: { type: 'piecewise', show: false, dimension: 1, pieces: [{ lt: 4, color: '#00aa00' }, { gte: 4, color: '#aa00aa' }] },
      series: [Object.assign({ type: 'scatter', symbolSize: 12, data: [[1, 3], [2, 5], [3, 2], [4, 6]] }, COLOUR)] } },
  { id: 'root-under-callback', note: '[r2v] the root\'s symbol, symbolOffset and symbolRotate under a series whose keys are callbacks that answer undefined: the series\' own value is the function, so the root\'s never reaches it -- the default circle, no offset, no turn',
    option: { symbol: 'rect', symbolOffset: [10, 0], symbolRotate: 30, xAxis: {}, yAxis: {},
      series: [{ type: 'scatter', symbol: '@vnone', symbolOffset: '@vnone', symbolRotate: '@vnone', symbolSize: 12,
        data: [[1, 3], [2, 5]] },
        { type: 'line', symbol: '@vnone', symbolSize: 12, data: [[1, 1], [2, 2]] }] } },
  { id: 'pictorial-none', note: '[r2v] a pictorial bar whose symbol callback answers undefined: the glyph is the series default, not a symbol named after the callback',
    option: { xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { max: 10 },
      series: [{ type: 'pictorialBar', symbol: '@vnone', symbolSize: 20, symbolRepeat: true, data: [4, 6] }] } },
];

function runCase(c) {
  const log = {};
  c = Object.assign({}, c, { option: Object.assign({ color: PALETTE }, c.option) });
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  let items;
  try {
    quiet(() => chart.setOption(Object.assign({ animation: false }, materialize(c.option, log))));
    chart._onframe();
    items = itemsOf(chart);
  } finally {
    chart.dispose();
  }
  const calls = {};
  Object.keys(log).sort().forEach(k => { calls[k] = Array.from(log[k]).sort(); });
  return { id: c.id, note: c.note, option: c.option, calls, items };
}

function guards(out) {
  const g = [];
  const add = (name, ok) => g.push({ name, ok: !!ok });
  const c = id => out.cases.find(x => x.id === id);
  add('line: four symbol callbacks and the colour', ['vsym', 'vsize', 'vrot', 'voff', 'vcol'].every(k => (c('line').calls[k] || []).length === 4));
  add('line: the item\'s own symbolSize stands over the callback', c('line').items.find(x => x.i === 1).sx === hex(10));
  add('graph: symbols by callback', (c('graph').calls.vsize || []).length === 4);
  add('tree: symbols by callback', (c('tree').calls.vsize || []).length >= 3);
  add('stroke series: the lines\' and the parallel\'s colour callbacks', (c('stroke-series').calls.vcol || []).length >= 6);
  add('markpoint: the marker\'s symbol callbacks', (c('markpoint').calls.vsize || []).length === 2);
  add('colour under a visualMap: called, the visualMap\'s colours drawn', (c('colour-under-visualmap').calls.vcol || []).length === 4
    && c('colour-under-visualmap').items.every(x => x.fill === '#00aa00' || x.fill === '#aa00aa'));
  add('root under a callback: a circle (defaultSymbol, for a line too), no offset, no turn where the key is a callback, the root where it is not', c('root-under-callback').items.every(x => x.sym === 'circle'
    && (x.s === 0 ? x.ox === hex(0) && x.oy === hex(0) && x.rot === hex(0) : x.ox === hex(10) && x.rot !== hex(0))));
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version, seed: SEED, W, H,
    measure: { firstCode: FIRST_CODE, ratio: RATIO.map(hex) },
    notes: [
      'every chart: chart._ssr false, env.node off, ' + W + ' x ' + H + ', the root\'s animation false.',
      'calls: per callback, the distinct calls; items: what each item\'s element draws.',
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
  json2 = JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => { if (!q.ok || process.env.ORACLE_VERBOSE) console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name); });
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (json1 === json2 ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if ((bad.length && !process.env.ORACLE_FORCE) || json1 !== json2) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
