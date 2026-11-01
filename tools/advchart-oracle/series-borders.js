// Round 6 R6-D: the pens of a series' paths -- the stroke, its width, its
// dash and the dash's phase -- per series type: getItemStyle's borderColor /
// borderWidth / borderType / borderDashOffset and getLineStyle's color /
// width / type / dashOffset, an item's own over its series', and the views'
// own rules over them:
//   a radar's symbols take the item's visual style (useStyle(itemStyle)) and
//     then setColor -- an empty symbol strokes in the colour at 2, a 'line'
//     symbol strokes in the colour at the border's width;
//   a gauge's pointer takes the visual style and pointer.itemStyle over it,
//     its progress arc the visual style and progress.itemStyle over it;
//   a chord's ribbon takes its link's getLineStyle (stroke the colour word
//     as written: 'source' is a word the canvas does not take);
// and the states' styles over them: a radar symbol's state is
// clone(getItemStyle of [state, 'itemStyle']), a gauge pointer's and a
// chord ribbon's setStatesStylesFromModel.
//
// From the real ECharts 6.1 dist (SSR, svg renderer, chart._ssr = false):
// each case set at T0 and settled, an optional action dispatched at T1 and
// settled; then every path under the series' views (a part filter where a
// case names one) that strokes -- lineWidth above nought and a stroke that is
// not null nor 'none' -- as `stroke|width|dash|offset`: the stroke
// `#rrggbbaa` (zrender's color.parse), 'grad' a gradient, 'x:<word>' a word
// zrender's parse does not take; the dash normalizeLineDash'd against the
// width ('solid' none; 'ignored' one setLineDash does not take -- an entry
// that is no finite number of nought or more), the offset the style's (0
// where none), the ends the
// canvas' defaults (butt, miter, 10) where the style has none. `pens` is the
// sorted set of these, `n` how many stroked paths.
// Run: node tools/advchart-oracle/series-borders.js -> tests/fixtures/advchart-series-borders.json
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-series-borders.json');
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

const PAL = ['#5470c6', '#91cc75', '#fac858', '#ee6666'];
const IS = { borderColor: '#000', borderWidth: 3, borderType: 'dashed', borderDashOffset: 2 };
const LS = { color: '#333', width: 4, type: 'dotted', dashOffset: 1 };
const N = ['A', 'B', 'C'];
const GRAD = { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: '#f00' }, { offset: 1, color: '#00f' }] };
const cart = s => ({ animation: false, color: PAL, xAxis: { type: 'category', data: N }, yAxis: {}, series: [s] });
const solo = s => ({ animation: false, color: PAL, series: [s] });
const IND = [{ name: 'p', max: 10 }, { name: 'q', max: 10 }, { name: 'r', max: 10 }];
const radar = s => ({ animation: false, color: PAL, radar: { indicator: IND },
  series: [Object.assign({ type: 'radar', data: [{ value: [3, 5, 2] }] }, s)] });
const gauge = s => solo(Object.assign({ type: 'gauge', data: [{ value: 40 }] }, s));
const chord = s => solo(Object.assign({ type: 'chord', data: [{ name: 'a' }, { name: 'b' }],
  links: [{ source: 'a', target: 'b', value: 3 }] }, s));
const HL = { type: 'highlight', seriesIndex: 0, dataIndex: 0 };

// [id, option, part ('' every path, 'symbol' a radar's symbols, 'pointer',
//  'progress', 'ribbon' a chord's links), action]
function cases() {
  return [
    // ---- a radar's symbols ----
    ['radar.rest', radar({}), 'symbol'],
    ['radar.border', radar({ itemStyle: IS }), 'symbol'],
    ['radar.width-only', radar({ itemStyle: { borderColor: '#f00' } }), 'symbol'],
    ['radar.no-colour', radar({ itemStyle: { borderWidth: 4 } }), 'symbol'],
    ['radar.auto', radar({ itemStyle: { borderColor: 'auto', borderWidth: 2 } }), 'symbol'],
    ['radar.item-auto', radar({ itemStyle: { borderWidth: 2 }, data: [{ value: [3, 5, 2], itemStyle: { borderColor: 'auto' } }] }),
      'symbol'],
    ['radar.none', radar({ itemStyle: { borderColor: 'none', borderWidth: 2 } }), 'symbol'],
    ['radar.empty', radar({ symbol: 'emptyCircle', itemStyle: IS }), 'symbol'],
    ['radar.line', radar({ symbol: 'line', itemStyle: IS }), 'symbol'],
    ['radar.item', radar({ itemStyle: IS, data: [{ value: [3, 5, 2] },
      { value: [4, 2, 6], itemStyle: { borderWidth: 5, borderColor: '#0f0', borderType: [2, 1], borderDashOffset: 1 } }] }), 'symbol'],
    ['radar.line-rest', radar({ symbol: 'line' }), 'symbol'],
    ['radar.dash-only', radar({ itemStyle: { borderColor: '#000', borderType: 'dotted' } }), 'symbol'],
    ['radar.grad', radar({ itemStyle: { borderColor: GRAD, borderWidth: 2 } }), 'symbol'],
    ['radar.empty-grad', radar({ symbol: 'emptyCircle', itemStyle: { borderColor: GRAD, borderWidth: 3 } }), 'symbol'],
    ['radar.size', radar({ symbolSize: 20, itemStyle: { borderColor: '#000', borderWidth: 2 } }), 'symbol'],
    ['radar.array-row', radar({ itemStyle: IS, data: [[3, 5, 2]] }), 'symbol'],
    ['radar.emphasis', radar({ itemStyle: IS, emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f', borderType: 'solid' } } }),
      'symbol', HL],
    ['radar.emphasis-rest', radar({ emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f' } } }), 'symbol', HL],
    ['radar.select', radar({ selectedMode: 'single', itemStyle: IS, select: { itemStyle: { borderColor: '#f0f', borderWidth: 4 } } }),
      'symbol', { type: 'select', seriesIndex: 0, dataIndex: 0 }],
    ['radar.blur', radar({ itemStyle: IS, emphasis: { focus: 'self' }, blur: { itemStyle: { borderColor: '#0ff', borderWidth: 1 } },
      data: [{ value: [3, 5, 2] }, { value: [4, 2, 6] }] }), 'symbol', HL],
    // ---- a gauge's pointer and progress arc ----
    ['gauge.rest', gauge({}), 'pointer'],
    ['gauge.border', gauge({ itemStyle: IS }), 'pointer'],
    ['gauge.pointer', gauge({ itemStyle: IS, pointer: { itemStyle: { borderColor: '#f00', borderWidth: 1, borderType: 'solid' } } }),
      'pointer'],
    ['gauge.pointer-only', gauge({ pointer: { itemStyle: { borderColor: '#f00', borderWidth: 2 } } }), 'pointer'],
    ['gauge.auto', gauge({ itemStyle: { borderColor: 'auto', borderWidth: 2 } }), 'pointer'],
    ['gauge.item-auto', gauge({ itemStyle: { borderWidth: 2 }, data: [{ value: 40, itemStyle: { borderColor: 'auto' } }] }), 'pointer'],
    ['gauge.item', gauge({ itemStyle: IS, data: [{ value: 40, itemStyle: { borderColor: '#0f0' } },
      { value: 70, pointer: { itemStyle: { borderWidth: 5 } } }] }), 'pointer'],
    ['gauge.icon', gauge({ itemStyle: IS, pointer: { icon: 'rect' } }), 'pointer'],
    ['gauge.icon-empty', gauge({ itemStyle: IS, pointer: { icon: 'emptyCircle' } }), 'pointer'],
    ['gauge.icon-line', gauge({ itemStyle: { borderWidth: 3 }, pointer: { icon: 'line' } }), 'pointer'],
    ['gauge.width-word', gauge({ itemStyle: IS, pointer: { itemStyle: { borderWidth: 'x' } } }), 'pointer'],
    ['gauge.progress', gauge({ itemStyle: IS, progress: { show: true, itemStyle: { borderWidth: 4 } } }), 'progress'],
    ['gauge.progress-ends', gauge({ itemStyle: Object.assign({ borderJoin: 'round', borderCap: 'square' }, IS),
      progress: { show: true, itemStyle: { borderMiterLimit: 4, borderColor: '#f00' } } }), 'progress'],
    ['gauge.emphasis', gauge({ itemStyle: IS, emphasis: { itemStyle: { borderWidth: 6, borderColor: '#00f' } } }), 'pointer', HL],
    // ---- a chord's ribbons ----
    ['chord.rest', chord({}), 'ribbon'],
    ['chord.width', chord({ lineStyle: { width: 2 } }), 'ribbon'],
    ['chord.colour', chord({ lineStyle: { width: 2, color: '#000', type: 'dashed', dashOffset: 1 } }), 'ribbon'],
    ['chord.target', chord({ lineStyle: { width: 2, color: 'target' } }), 'ribbon'],
    ['chord.link', chord({ lineStyle: { width: 2, color: '#000' },
      links: [{ source: 'a', target: 'b', value: 3, lineStyle: { type: [3, 2], width: 4, dashOffset: 2 } }] }), 'ribbon'],
    ['chord.emphasis', chord({ lineStyle: { width: 2, color: '#000' },
      emphasis: { lineStyle: { width: 5, color: '#f00', type: 'dotted' } } }), 'ribbon',
      { type: 'highlight', seriesIndex: 0, dataType: 'edge', dataIndex: 0 }],
    // ---- every other series, every stroked path ----
    ['bar', cart({ type: 'bar', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['bar.zero-width-dash', cart({ type: 'bar', itemStyle: { borderColor: '#000', borderWidth: 0, borderType: [5, 3] },
      emphasis: { itemStyle: { borderWidth: 3 } }, data: [3] }), '', HL],
    ['line', cart({ type: 'line', symbol: 'circle', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.rest', cart({ type: 'line', symbol: 'circle', data: [3, 5, 2] }), ''],
    ['line.ls', cart({ type: 'line', symbol: 'circle', lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.is', cart({ type: 'line', symbol: 'circle', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['line.empty', cart({ type: 'line', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.line-symbol', cart({ type: 'line', symbol: 'line', itemStyle: IS, lineStyle: LS, data: [3, 5, 2] }), ''],
    ['line.line-rest', cart({ type: 'line', symbol: 'line', data: [3, 5, 2] }), ''],
    ['line.grad-symbol', cart({ type: 'line', symbol: 'circle', itemStyle: { borderColor: GRAD, borderWidth: 2 }, data: [3, 5, 2] }), ''],
    ['scatter', cart({ type: 'scatter', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['scatter.empty', cart({ type: 'scatter', symbol: 'emptyCircle', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['scatter.line-symbol', cart({ type: 'scatter', symbol: 'line', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['scatter.line-rest', cart({ type: 'scatter', symbol: 'line', data: [3, 5, 2] }), ''],
    ['scatter.line-item', cart({ type: 'scatter', symbol: 'line', data: [3, { value: 5, itemStyle: { borderWidth: 4 } }] }), ''],
    ['escatter', cart({ type: 'effectScatter', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['pie', solo({ type: 'pie', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['funnel', solo({ type: 'funnel', itemStyle: IS, data: [3, 5, 2] }), ''],
    ['candle', cart({ type: 'candlestick', itemStyle: Object.assign({ borderColor0: '#444' }, IS), data: [[2, 4, 1, 5], [3, 2, 1, 4]] }), ''],
    ['boxplot', cart({ type: 'boxplot', itemStyle: IS, data: [[1, 2, 3, 4, 5], [2, 3, 4, 5, 6]] }), ''],
    ['heatmap', { animation: false, color: PAL, xAxis: { type: 'category', data: N }, yAxis: { type: 'category', data: N },
      visualMap: { show: false, min: 0, max: 5 }, series: [{ type: 'heatmap', itemStyle: IS, data: [[0, 0, 1], [1, 1, 3]] }] }, ''],
    ['sunburst', solo({ type: 'sunburst', itemStyle: IS, data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }] }), ''],
    ['sunburst.join', solo({ type: 'sunburst', itemStyle: Object.assign({ borderJoin: 'round' }, IS),
      data: [{ name: 'a', value: 3, children: [{ name: 'b', value: 2 }] }] }), ''],
    ['pie.join', solo({ type: 'pie', itemStyle: Object.assign({ borderJoin: 'miter' }, IS), data: [3, 5, 2] }), ''],
    ['pie.zero-width-dash', solo({ type: 'pie', itemStyle: { borderColor: '#000', borderWidth: 0, borderType: [5, 3] },
      emphasis: { itemStyle: { borderWidth: 3 } }, data: [3] }), '', HL],
    ['treemap', solo({ type: 'treemap', breadcrumb: { show: false }, itemStyle: IS,
      data: [{ name: 'a', value: 3 }, { name: 'b', value: 2 }] }), ''],
    ['graph', solo({ type: 'graph', layout: 'none', itemStyle: IS, lineStyle: LS,
      data: [{ name: 'a', x: 0, y: 0 }, { name: 'b', x: 10, y: 10 }], links: [{ source: 'a', target: 'b' }] }), ''],
    ['tree', solo({ type: 'tree', itemStyle: Object.assign({ color: '#abc' }, IS), lineStyle: LS, data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.number-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: 4 },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.bad-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: [{}, 2] },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.negative-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: [-2, 3] },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['tree.string-dash', solo({ type: 'tree', itemStyle: { color: '#abc' }, lineStyle: { color: '#333', width: 2, type: ['4', '2'] },
      data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }), ''],
    ['sankey', solo({ type: 'sankey', itemStyle: IS, lineStyle: Object.assign({ opacity: 0.5 }, LS),
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] }), ''],
    ['sankey.band', solo({ type: 'sankey', lineStyle: { borderColor: '#000', borderWidth: 2, borderType: 'dashed', borderDashOffset: 1 },
      data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 3 }] }), ''],
    ['parallel', { animation: false, color: PAL, parallelAxis: [{ dim: 0 }, { dim: 1 }],
      series: [{ type: 'parallel', lineStyle: LS, data: [[1, 2], [3, 4]] }] }, ''],
    ['parallel.is-only', { animation: false, color: PAL, parallelAxis: [{ dim: 0 }, { dim: 1 }],
      series: [{ type: 'parallel', itemStyle: IS, data: [[1, 2], [3, 4]] }] }, ''],
    ['lines', { animation: false, color: PAL, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', lineStyle: LS, data: [{ coords: [[0, 0], [5, 5]] }] }] }, ''],
    ['lines.is-only', { animation: false, color: PAL, xAxis: { type: 'value' }, yAxis: { type: 'value' },
      series: [{ type: 'lines', coordinateSystem: 'cartesian2d', itemStyle: IS, data: [{ coords: [[0, 0], [5, 5]] }] }] }, ''],
    ['pict', cart({ type: 'pictorialBar', itemStyle: IS, symbol: 'rect', data: [3, 5, 2] }), ''],
    ['river', { animation: false, color: PAL, singleAxis: { type: 'time' }, series: [{ type: 'themeRiver', itemStyle: IS,
      data: [['2015/11/08', 3, 'a'], ['2015/11/09', 4, 'a']] }] }, ''],
    ['chord.nodes', chord({ itemStyle: IS }), ''],
    ['polarbar', { animation: false, color: PAL, polar: {}, angleAxis: { type: 'category', data: N }, radiusAxis: {},
      series: [{ type: 'bar', coordinateSystem: 'polar', itemStyle: IS, data: [3, 5, 2] }] }, ''],
  ];
}

function hex2(v) { return ('0' + Math.round(v).toString(16)).slice(-2); }
function colourOf(c) {
  if (c != null && typeof c === 'object') return 'grad';
  const p = echarts.color.parse(c);
  if (!p) return 'x:' + c;
  return '#' + hex2(p[0]) + hex2(p[1]) + hex2(p[2]) + hex2(p[3] * 255);
}
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  lineWidth = lineWidth || 1;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType]
        : Array.isArray(lineType) ? lineType : null;
}
// the part each path is: a radar item's symbols (its group's third child),
// a gauge's pointers (the items' graphic elements) and progress arcs
// (the view's _progressEls), a chord's ribbons (not its sectors)
function partsOf(chart, view) {
  const m = new Map();
  const model = chart.getModel().getSeriesByIndex(0);
  const data = model && model.getData();
  if (view.type === 'radar' && data) data.eachItemGraphicEl(g => g.childAt(2).eachChild(e => m.set(e, 'symbol')));
  if (view.type === 'gauge' && data) {
    data.each(i => { const e = data.getItemGraphicEl(i); if (e) m.set(e, 'pointer'); });
    (view._progressEls || []).forEach(e => e && m.set(e, 'progress'));
  }
  if (view.type === 'chord') view.group.traverse(e => { if (e instanceof Path && e.type !== 'sector') m.set(e, 'ribbon'); });
  return m;
}

function settle(chart, start) {
  const zr = chart.getZr();
  for (let t = 16; t <= 5000; t += 250) {
    NOW = start + t;
    zr.animation.update();
  }
  zr.storage.getDisplayList(true);
  let live = 0;
  for (let c = zr.animation._head; c; c = c.next) if (!c.loop) live++;
  must(live === 0, 'did not settle');
}

function run(id, option, part, action) {
  NOW = T_BASE;
  rngState = SEED;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  try {
    chart.setOption(JSON.parse(JSON.stringify(option)));
    settle(chart, T_BASE);
    if (action) {
      NOW = T_BASE + 10000;
      chart.dispatchAction(JSON.parse(JSON.stringify(action)));
      settle(chart, T_BASE + 10000);
    }
    const set = new Set();
    let n = 0;
    let seen = 0;
    (chart._chartsViews || []).forEach(v => { const parts = partsOf(chart, v); v.group.traverse(e => {
      if (!(e instanceof Path) || e.ignore || e.invisible) return;
      if (part && parts.get(e) !== part) return;
      seen++;
      const s = e.style;
      if (!(s.lineWidth > 0) || s.stroke == null || s.stroke === 'none') return;
      n++;
      const dash = normalizeLineDash(s.lineDash, s.lineWidth);
      // setLineDash ignores a dash with an entry that is no finite number of nought or more
      const bad = dash && dash.some(v => !(isFinite(Number(v)) && Number(v) >= 0));
      set.add([colourOf(s.stroke), String(s.lineWidth), bad ? 'ignored' : dash ? dash.map(Number).join(',') : 'solid',
        String(s.lineDashOffset == null ? 0 : s.lineDashOffset),
        [s.lineCap || 'butt', s.lineJoin || 'miter', String(s.miterLimit == null ? 10 : s.miterLimit)].join('/')].join('|'));
    }); });
    return { id, option, part, action: action || null, seen, n, pens: Array.from(set).sort() };
  }
  finally {
    chart.dispose();
  }
}

function generate() {
  const charts = cases().map(([id, o, part, act]) => run(id, o, part, act));
  const by = id => charts.find(c => c.id === id);
  const pens = id => by(id).pens.join(' ');
  // guards: what upstream does that the port did not
  must(by('radar.rest').seen === 3 && by('radar.rest').n === 0, 'radar.rest: ' + by('radar.rest').seen + ' ' + pens('radar.rest'));
  must(pens('radar.border') === '#000000ff|3|12,6|2|butt/miter/10', 'radar.border: ' + pens('radar.border'));
  must(pens('radar.width-only') === '#ff0000ff|1|solid|0|butt/miter/10', 'radar.width-only: ' + pens('radar.width-only'));
  must(pens('radar.auto') === '#5470c6ff|2|solid|0|butt/miter/10', 'radar.auto: ' + pens('radar.auto'));
  // setColor: an empty symbol's stroke is the colour at 2 -- the border's dash stays
  must(pens('radar.empty') === '#5470c6ff|2|8,4|2|butt/miter/10', 'radar.empty: ' + pens('radar.empty'));
  must(pens('radar.line') === '#5470c6ff|3|12,6|2|butt/miter/10', 'radar.line: ' + pens('radar.line'));
  must(pens('radar.emphasis') === '#0000ffff|6|solid|2|butt/miter/10', 'radar.emphasis: ' + pens('radar.emphasis'));
  must(pens('gauge.border') === '#000000ff|3|12,6|2|butt/miter/10', 'gauge.border: ' + pens('gauge.border'));
  must(pens('gauge.pointer') === '#ff0000ff|1|solid|2|butt/miter/10', 'gauge.pointer: ' + pens('gauge.pointer'));
  must(pens('gauge.progress') === '#000000ff|4|16,8|2|butt/miter/10', 'gauge.progress: ' + pens('gauge.progress'));
  must(pens('chord.colour') === '#000000ff|2|8,4|1|butt/miter/10', 'chord.colour: ' + pens('chord.colour'));
  must(pens('chord.width') === 'x:source|2|solid|0|butt/miter/10', 'chord.width: ' + pens('chord.width'));
  must(pens('chord.emphasis') === '#ff0000ff|5|5|0|butt/miter/10', 'chord.emphasis: ' + pens('chord.emphasis'));
  must(by('radar.select').seen > 0 && by('radar.blur').seen > 0, 'states seen');
  must(charts.every(c => c.seen > 0), 'a case has no path: ' + charts.filter(c => c.seen === 0).map(c => c.id));
  return { source: 'ECharts 6.1.0 dist (' + DIST.replace(/\\/g, '/') + '), node SSR (svg)',
    note: 'R6-D: each case settled (an action, where one, at T1 and settled), `pens` = the sorted set of stroke|width|dash|offset|ends '
      + 'of every stroked path under the series views (lineWidth > 0, a stroke not null nor none) -- of the part `part` names where '
      + 'one is (symbol: a radar item\'s symbols; pointer / progress: a gauge\'s; ribbon: a chord\'s links) -- the stroke #rrggbbaa '
      + '(color.parse), grad a gradient, x:<word> a word that does not parse; the dash normalizeLineDash\'d against the width (solid '
      + 'none, ignored one setLineDash does not take); the offset 0 where none; the ends cap/join/miterLimit, butt/miter/10 where none. `seen` the paths of that part, `n` the stroked ones.', W, H, charts };
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
