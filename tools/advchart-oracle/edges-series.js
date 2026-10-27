/*
Upstream's own answers for fix batch R5-G, the series part (spec section 244):
edge cases of several series the port drew differently.

  pictorial-outside   a pictorialBar's `label.position: 'outside'` is past the
                      end its bounding length runs to (PictorialBarView's
                      barPositionOutside = posDesc[+(boundingLength > 0)]):
                      per item the label's anchor (innerTransformable x, y)
                      and the alignment the host's inner text style was given
  pictorial-mirror    a path:// glyph on a bar that points the other way is
                      reflected (the scale along the value axis times
                      (isHorizontal ? -1 : 1) * pxSign): per glyph the mean of
                      its outline's vertices, through the glyph's global
                      transform -- a triangle's, which is its centroid
  radar-line-colour   a radar ring's pen is lineStyle.color, an item's own over
                      the series' (RadarView: defaults(getLineStyle(),
                      {stroke: color})); its polygon keeps the row's colour
  graph-item-offset   a graph node's own symbolOffset (dataSymbolTask's
                      getShallow) over the series' and its symbol's centre
                      through the Symbol group: per node the global point
  boxplot-sort        the boxplot transform's asc(): Array.prototype.sort with
                      (a, b) => a - b over rows holding words (NaN): the boxes
  river-sort          a themeRiver layer of 80 rows whose times are partly not
                      numbers: getLayerSeries' indices, sorted by V8
  legend-icons        a legend item's icon paths per series type, with the
                      type's own defaults: stroke, lineWidth, fill
  pie-delay           a pie with negative values: the indices animationDelay
                      is called with (the filtered data's), in call order

  node tools/advchart-oracle/edges-series.js

writes tests/fixtures/advchart-edges-series.json (ORACLE_OUT overrides). Doubles
as the 16 hex digits of their IEEE bits with a readable twin. Guards: each
group's discriminating fact (a negative item's outside label below its bar, a
mirrored glyph's centroid on the far side of its anchor from an unmirrored
one, a ring stroked in a colour no row has, an item offset moving its node, a
V8 order that a stable merge sort or a linear insertion sort would not give,
a candlestick icon with a 2 px pen, a delay index past a filtered row); two
in-process generations byte-identical. Ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const T0 = 1700000000000;
let NOW = T0;
class ClockDate extends RealDate {
  constructor(...a) {
    if (a.length === 0) super(NOW); else super(...a);
  }
  static now() { return NOW; }
}
global.Date = ClockDate;
global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-series.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const clone = o => JSON.parse(JSON.stringify(o));
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const txt = v => (Object.is(v, -0) ? '-0' : String(v));
function put(o, k, v) { o[k] = hex(v); o[k + 'Text'] = txt(v); return o; }

(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();

function mk(W, H) {
  NOW = T0;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function refresh(chart) { chart.getZr().storage.getDisplayList(true); }
function applyM(m, x, y) { return m ? [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]] : [x, y]; }

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const cases = [];
function add(group, id, note, option, extra) {
  cases.push(Object.assign({ group, id, note, W: 600, H: 400, option }, extra || {}));
}
const CAT = ['a', 'b', 'c', 'd'];

// ---- pictorial-outside ----
const pict = (horizontal, series, axisExtra) => {
  const cat = { type: 'category', data: CAT };
  const val = Object.assign({ type: 'value' }, axisExtra || {});
  return {
    animation: false,
    xAxis: horizontal ? val : cat,
    yAxis: horizontal ? cat : val,
    series: [Object.assign({ type: 'pictorialBar', symbol: 'rect', symbolSize: ['60%', '100%'],
      label: { show: true, position: 'outside' } }, series)]
  };
};
add('pictorial-outside', 'po-v', 'vertical bars up and down: outside is top for a positive value, bottom for a negative one',
  pict(false, { data: [5, -3, 0, 2] }));
add('pictorial-outside', 'po-h', 'bars lying down: right for a positive value, left for a negative one',
  pict(true, { data: [5, -3, 0, 2] }));
add('pictorial-outside', 'po-inverse', 'an inverse value axis turns the pixel length round',
  pict(false, { data: [5, -3, 2] }, { inverse: true }));
add('pictorial-outside', 'po-bound', 'symbolBoundingData sets the bounding length: a negative bound under positive data',
  pict(false, { data: [5, 3], symbolRepeat: true, symbolBoundingData: -4, symbolSize: [20, 10] }, { min: -6, max: 6 }));
add('pictorial-outside', 'po-repeat-zero', 'a repeat on a zero bar: no glyph, the label still past the end',
  pict(false, { data: [4, 0, -4], symbolRepeat: true, symbolSize: [16, 8] }));
add('pictorial-outside', 'po-distance', 'the distance moves the label past the end',
  pict(false, { data: [4, -4], label: { show: true, position: 'outside', distance: 12 } }));

// ---- pictorial-mirror ----
const TRI = 'path://M0,0L10,0L5,14Z';
add('pictorial-mirror', 'pm-v', 'a triangle on bars up and down: reflected along the value axis on the negative one',
  pict(false, { data: [5, -3], symbol: TRI, symbolSize: [24, 24], symbolPosition: 'end', label: { show: false } }));
add('pictorial-mirror', 'pm-h', 'bars lying down: reflected across',
  pict(true, { data: [5, -3], symbol: TRI, symbolSize: [24, 24], symbolPosition: 'end', label: { show: false } }));
add('pictorial-mirror', 'pm-rotate', 'a turned triangle: the turn and the reflection compose',
  pict(false, { data: [5, -3], symbol: TRI, symbolSize: [24, 24], symbolRotate: 30, symbolPosition: 'end', label: { show: false } }));
add('pictorial-mirror', 'pm-repeat', 'a repeated triangle on a negative bar',
  pict(false, { data: [6, -6], symbol: TRI, symbolSize: [16, 16], symbolRepeat: true, label: { show: false } }));

// ---- radar-line-colour ----
const radar = (series) => ({
  animation: false,
  color: ['#5070dd', '#b6d634', '#505372'],
  radar: { indicator: [{ name: 'p', max: 10 }, { name: 'q', max: 10 }, { name: 'r', max: 10 }, { name: 's', max: 10 }] },
  series: [Object.assign({ type: 'radar' }, series)]
});
add('radar-line-colour', 'rl-series', "the series' lineStyle.color strokes every ring; the areas keep the rows' colours",
  radar({ lineStyle: { color: '#ff0000', width: 2 }, areaStyle: {}, data: [{ value: [4, 5, 6, 7] }, { value: [8, 2, 3, 4] }] }));
add('radar-line-colour', 'rl-item', "an item's own lineStyle.color over the series'",
  radar({ lineStyle: { color: '#ff0000' }, data: [{ value: [4, 5, 6, 7], lineStyle: { color: '#00aa00' } },
    { value: [8, 2, 3, 4] }, { value: [1, 9, 2, 5], lineStyle: { width: 3 } }] }));
add('radar-line-colour', 'rl-none', "an item's 'none' and an item's own with no series colour",
  radar({ data: [{ value: [4, 5, 6, 7], lineStyle: { color: 'none' } }, { value: [8, 2, 3, 4], lineStyle: { color: '#123456' } }] }));

// ---- graph-item-offset ----
add('graph-item-offset', 'go-own', "a node's own symbolOffset over the series' -- a number pair, a percentage, a null that falls through",
  { animation: false,
    series: [{ type: 'graph', layout: 'none', symbolSize: 20, symbolOffset: [5, 0], roam: false,
      data: [{ name: 'A', x: 0, y: 0 }, { name: 'B', x: 100, y: 0, symbolOffset: [0, '50%'] },
        { name: 'C', x: 0, y: 100, symbolOffset: null }, { name: 'D', x: 100, y: 100, symbolOffset: [-8, 6] }],
      links: [] }] });
add('graph-item-offset', 'go-nodes', "the same through `nodes` and a size pair",
  { animation: false,
    series: [{ type: 'graph', layout: 'none', symbolSize: [30, 10],
      nodes: [{ name: 'A', x: 0, y: 0, symbolOffset: ['10%', '-50%'] }, { name: 'B', x: 50, y: 30 }],
      links: [{ source: 'A', target: 'B' }] }] });

// ---- boxplot-sort ----
const boxRows = [
  [3, 1, 'x', 2, 9, 4],
  [5, 'a', 2, 'b', 1, 7, 3],
  ['q', 8, 6, 4, 2, 0],
  [2, 2, 'n', 1, 1, 3, 'm', 0, 5],
  [9, 1, 'x', 5, 3, 2, 8]
];
add('boxplot-sort', 'bs-words', 'rows with words in them: asc() sorts with NaN comparisons',
  { animation: false,
    dataset: [{ source: boxRows }, { transform: { type: 'boxplot' } }],
    xAxis: { type: 'category' }, yAxis: { type: 'value' },
    series: [{ type: 'boxplot', datasetIndex: 1 }] }, { rows: boxRows });

// ---- river-sort ----
function riverData() {
  const out = [];
  let s = 12345;
  const rnd = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; };
  for (let i = 0; i < 80; i++) {
    const t = rnd() < 0.15 ? 'n/a' : Math.floor(rnd() * 200);
    out.push([t, Math.floor(rnd() * 10) + 1, 'L']);
  }
  return out;
}
add('river-sort', 'rs-80', 'one layer of 80 rows, some times words: V8 sorts the indices with ties for NaN',
  { animation: false, singleAxis: { type: 'value', bottom: 30 },
    series: [{ type: 'themeRiver', data: riverData() }] });

// ---- legend-icons ----
const legendOf = (series, extra) => Object.assign({ animation: false, legend: { top: 4 }, series }, extra || {});
add('legend-icons', 'li-candle', "a candlestick's icon: its borderWidth 1 makes the 'auto' pen 2 wide, in the border colour",
  legendOf([{ type: 'candlestick', name: 'K', data: [[2, 4, 1, 5], [4, 3, 2, 6]] }],
    { xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' } }));
add('legend-icons', 'li-candle-colour', "a candlestick that wrote its colours",
  legendOf([{ type: 'candlestick', name: 'K', itemStyle: { color: '#ff0000', borderColor: '#00ff00' }, data: [[2, 4, 1, 5]] }],
    { xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value' } }));
add('legend-icons', 'li-candle-noborder', "a candlestick with borderWidth 0: no pen",
  legendOf([{ type: 'candlestick', name: 'K', itemStyle: { borderWidth: 0 }, data: [[2, 4, 1, 5]] }],
    { xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value' } }));
add('legend-icons', 'li-boxplot', "a boxplot's icon",
  legendOf([{ type: 'boxplot', name: 'B', itemStyle: { borderColor: '#0000ff', color: '#ffffff' }, data: [[1, 2, 3, 4, 5]] }],
    { xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value' } }));
add('legend-icons', 'li-others', "bar, scatter, effectScatter and line icons with their defaults",
  legendOf([{ type: 'bar', name: 'Bar', itemStyle: { color: '#ff0000' }, data: [1] },
    { type: 'scatter', name: 'Sc', itemStyle: { color: '#00ff00' }, data: [2] },
    { type: 'effectScatter', name: 'Ef', itemStyle: { color: '#0000ff' }, data: [3] },
    { type: 'line', name: 'Ln', itemStyle: { color: '#ff00ff' }, lineStyle: { color: '#ff00ff' }, data: [4] }],
    { xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value' } }));
add('legend-icons', 'li-graph', "a graph's icon",
  legendOf([{ type: 'graph', name: 'G', layout: 'none', itemStyle: { color: '#ff0000' }, data: [{ name: 'n', x: 1, y: 1 }], links: [] }]));
add('legend-icons', 'li-pictorial', "a pictorialBar's icon",
  legendOf([{ type: 'pictorialBar', name: 'P', symbol: 'rect', itemStyle: { color: '#ff0000' }, data: [2] }],
    { xAxis: { type: 'category', data: ['a'] }, yAxis: { type: 'value' } }));

// ---- pie-delay ----
add('pie-delay', 'pd-neg', 'a pie with negative values: the delay callback is called with the filtered indices',
  { animation: true, animationDelay: '@delayLog',
    series: [{ type: 'pie', data: [3, -1, 4, -2, 5] }] });

// ---------------------------------------------------------------------------
// the readers
// ---------------------------------------------------------------------------
function eachSeries(chart, type, fn) {
  chart.getModel().eachSeries(sm => { if (sm.subType === type) fn(sm, sm.getData(), chart.getViewOfSeriesModel(sm)); });
}
function labelRec(host) {
  const tc = host.getTextContent && host.getTextContent();
  must(tc, 'a pictorial rect with no label');
  const it = tc.innerTransformable;
  const ds = host._innerTextDefaultStyle;
  must(ds, 'no inner text style');
  const o = { word: host.textConfig && host.textConfig.position != null ? host.textConfig.position : null,
    align: ds.align == null ? null : ds.align, verticalAlign: ds.verticalAlign == null ? null : ds.verticalAlign,
    drawn: !tc.ignore && !tc.invisible };
  put(o, 'x', it.x);
  put(o, 'y', it.y);
  return o;
}
// a path's vertex points (M and L), global
function vertices(el) {
  const p = el.path;
  must(p && p.data, 'a glyph with no path');
  const d = p.data;
  const m = el.getComputedTransform();
  const out = [];
  for (let i = 0; i < p.len();) {
    const cmd = d[i++];
    if (cmd === 1 || cmd === 2) { out.push(applyM(m, d[i], d[i + 1])); i += 2; }
    else if (cmd === 6) { /* Z */ }
    else throw new OracleError('a glyph command ' + cmd);
  }
  return out;
}

const READ = {
  'pictorial-outside': (chart, c) => {
    const items = [];
    eachSeries(chart, 'pictorialBar', (sm, d) => {
      d.each(i => {
        const el = d.getItemGraphicEl(i);
        if (!el) return;
        items.push(Object.assign({ s: sm.seriesIndex, i, raw: d.getRawIndex(i) }, labelRec(el.__pictorialBarRect)));
      });
    });
    return { items };
  },
  'pictorial-mirror': (chart, c) => {
    const glyphs = [];
    eachSeries(chart, 'pictorialBar', (sm, d) => {
      d.each(i => {
        const el = d.getItemGraphicEl(i);
        if (!el) return;
        el.__pictorialBundle.eachChild((g, k) => {
          refresh(chart);
          const v = vertices(g);
          must(v.length === 3, 'a triangle of ' + v.length);
          const o = { s: sm.seriesIndex, i, raw: d.getRawIndex(i), k };
          // the mean of the three vertices: the triangle's centroid
          put(o, 'cx', (v[0][0] + v[1][0] + v[2][0]) / 3);
          put(o, 'cy', (v[0][1] + v[1][1] + v[2][1]) / 3);
          o.scaleSign = Math.sign(g.scaleX * g.scaleY);
          glyphs.push(o);
        });
      });
    });
    return { glyphs };
  },
  'radar-line-colour': (chart, c) => {
    const rows = [];
    eachSeries(chart, 'radar', (sm, d) => {
      d.each(i => {
        const g = d.getItemGraphicEl(i);
        const line = g.childAt(0), poly = g.childAt(1);
        rows.push({ s: sm.seriesIndex, i, raw: d.getRawIndex(i), rowColour: d.getItemVisual(i, 'style').fill,
          stroke: line.style.stroke == null ? null : String(line.style.stroke),
          area: poly.ignore ? null : String(poly.style.fill) });
      });
    });
    return { rows };
  },
  'graph-item-offset': (chart, c) => {
    const nodes = [];
    eachSeries(chart, 'graph', (sm, d) => {
      d.each(i => {
        const el = d.getItemGraphicEl(i);
        const sym = el.childAt(0);
        const m = el.getComputedTransform();
        const p = applyM(m, sym.x, sym.y);
        const o = { s: sm.seriesIndex, i, raw: d.getRawIndex(i),
          offset: JSON.stringify(d.getItemVisual(i, 'symbolOffset') == null ? null : d.getItemVisual(i, 'symbolOffset')) };
        const lay = d.getItemLayout(i);
        const a = applyM(el.parent.getComputedTransform(), lay[0], lay[1]);
        put(o, 'ax', a[0]); put(o, 'ay', a[1]);
        put(o, 'x', p[0]); put(o, 'y', p[1]);
        nodes.push(o);
      });
    });
    return { nodes };
  },
  'boxplot-sort': (chart, c) => {
    const ds = chart.getModel().getComponent('dataset', 1);
    const src = ds.getSourceManager().getSource();
    const boxes = src.data.map(r => r.map(v => (typeof v === 'number' ? put({}, 'v', v) : { s: String(v) })));
    return { boxes };
  },
  'river-sort': (chart, c) => {
    const layers = [];
    eachSeries(chart, 'themeRiver', (sm, d) => {
      sm.getLayerSeries().forEach(l => layers.push({ name: l.name, indices: l.indices.slice() }));
    });
    return { layers };
  },
  'legend-icons': (chart, c) => {
    const lm = chart.getModel().getComponent('legend', 0);
    const view = chart.getViewOfComponentModel(lm);
    const names = lm.getData().map(m => m.get('name'));
    const kids = view.getContentGroup().children();
    must(kids.length === names.length, 'one item group per name');
    const items = [];
    kids.forEach((g, i) => {
      const rec = { name: names[i], icons: [] };
      g.traverse(e => {
        if (e.type === 'text' || e.type === 'tspan' || e.type === 'group' || !e.style) return;
        if (e.style.fill === 'transparent' && !e.style.stroke) return;
        const st = e.style;
        rec.icons.push({ type: e.type, fill: st.fill == null ? null : String(st.fill),
          stroke: st.stroke == null ? null : String(st.stroke),
          lineWidth: st.lineWidth == null ? 1 : st.lineWidth });
      });
      items.push(rec);
    });
    return { items };
  },
  'pie-delay': (chart, c) => ({ calls: c._calls })
};

function run(c) {
  const chart = mk(c.W, c.H);
  try {
    const option = clone(c.option);
    c._calls = [];
    if (option.animationDelay === '@delayLog') {
      option.animationDelay = function (idx) { c._calls.push(idx == null ? null : idx); return 0; };
    }
    chart.setOption(option);
    chart.renderToSVGString();
    refresh(chart);
    const rec = READ[c.group](chart, c);
    const out = { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: c.option };
    if (c.rows) out.rows = c.rows;
    return Object.assign(out, rec);
  } finally {
    chart.dispose();
    delete c._calls;
  }
}

// ---------------------------------------------------------------------------
// the guards
// ---------------------------------------------------------------------------
function v8Order(keys, idx) {
  const a = idx.slice();
  a.sort((x, y) => keys[x] - keys[y]);
  return a;
}
function mergeOrder(keys, idx) {
  const cmp = (x, y) => { const d = keys[x] - keys[y]; return Number.isNaN(d) ? 0 : d; };
  const ms = a => {
    if (a.length < 2) return a;
    const m = a.length >> 1, l = ms(a.slice(0, m)), r = ms(a.slice(m)), o = [];
    let i = 0, j = 0;
    while (i < l.length && j < r.length) { if (cmp(r[j], l[i]) < 0) o.push(r[j++]); else o.push(l[i++]); }
    return o.concat(l.slice(i), r.slice(j));
  };
  return ms(idx.slice());
}
function insertionAsc(vals) {
  const a = vals.slice();
  for (let i = 1; i < a.length; i++) {
    const t = a[i]; let j = i - 1;
    while (j >= 0) { const d = a[j] - t; if (Number.isNaN(d) || !(d > 0)) break; a[j + 1] = a[j]; j--; }
    a[j + 1] = t;
  }
  return a;
}

function guards(out) {
  const g = [];
  const guard = (name, ok) => { must(ok, 'guard failed: ' + name); g.push(name); };
  const byId = id => out.cases.find(c => c.id === id);
  const N = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  const pv = byId('po-v').items;
  guard('a negative bar hangs its outside label below it', pv[1].verticalAlign === 'top' && pv[0].verticalAlign === 'bottom');
  const ph = byId('po-h').items;
  guard('a negative bar lying down hangs it on the left', ph[1].align === 'right' && ph[0].align === 'left');
  const pb = byId('po-bound').items;
  guard('a negative bound puts a positive bar\'s outside label below', pb[0].verticalAlign === 'top');
  const pz = pv[2];
  guard('a zero bar is outside on top', pz.verticalAlign === 'bottom' && pz.drawn);
  guard('a zero repeated bar keeps its label', byId('po-repeat-zero').items[1].drawn);
  const pm = byId('pm-v').glyphs;
  guard('the up glyph and the down glyph are reflections', pm[0].scaleSign !== pm[1].scaleSign);
  const rl = byId('rl-series').rows;
  guard('the ring strokes the series line colour, the area the row\'s', rl.every(r => r.stroke === '#ff0000' && r.area === r.rowColour));
  const ri = byId('rl-item').rows;
  guard('an item\'s own line colour', ri[0].stroke === '#00aa00' && ri[1].stroke === '#ff0000' && ri[2].stroke === '#ff0000');
  guard('a none pen', byId('rl-none').rows[0].stroke === 'none');
  const go = byId('go-own').nodes;
  guard('an item offset moves its node, a null falls through', go[1].offset !== go[0].offset && go[2].offset === go[0].offset);
  const bs = byId('bs-words');
  guard('V8 sorts a row with words differently from an insertion sort', bs.rows.some(r => {
    const q = r.map(v => (typeof v === 'number' ? v : NaN));
    const v8 = r.slice().sort((a, b) => a - b).map(v => (typeof v === 'number' ? v : NaN));
    return JSON.stringify(insertionAsc(q)) !== JSON.stringify(v8);
  }));
  const rs = byId('rs-80');
  const rd = rs.option.series[0].data;
  const keys = rd.map(r => (typeof r[0] === 'number' ? r[0] : NaN));
  const idx = rd.map((r, i) => i);
  guard('the layer is V8\'s order of its rows', JSON.stringify(rs.layers[0].indices) === JSON.stringify(v8Order(keys, idx)));
  guard('which a stable merge sort would not give', JSON.stringify(v8Order(keys, idx)) !== JSON.stringify(mergeOrder(keys, idx)));
  const lc = byId('li-candle').items[0].icons;
  guard('a candlestick icon has a 2 px pen', lc.some(ic => ic.lineWidth === 2 && ic.stroke));
  const pdc = byId('pd-neg').calls;
  guard('the pie delay is called with the filtered indices only', pdc.length > 0 && Math.max(...pdc) === 2);
  return g;
}

function generate() {
  const out = { source: 'echarts ' + echarts.version + ' (' + path.basename(DIST) + ')', cases: [] };
  for (const c of cases) out.cases.push(run(c));
  out.guards = guards(out);
  return JSON.stringify(out, null, 1) + '\n';
}

try {
  const a = generate();
  const b = generate();
  must(a === b, 'two generations differ');
  must(a.indexOf('\\u0000') < 0, 'a NUL in the output');
  JSON.parse(a);
  fs.writeFileSync(OUT, a);
  console.log('wrote', OUT, cases.length, 'cases');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message + e.stack : e);
  process.exit(1);
}
