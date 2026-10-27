/*
Upstream's own answers for fix batch R5-A (spec section 238): WHICH TEXTS ARE
DRAWN ITALIC. zrender builds every text's font as makeFont(style) =
[fontStyle, fontWeight, parseFontSize(fontSize), fontFamily || 'sans-serif']
.join(' ') (graphic/Text.ts), or takes style.font as written when none of
size / family / weight is set (a graphic text's `font: 'italic 14px serif'`);
a canvas then draws the face that font string names. ECharts hands a text its
fontStyle from the component's own text style, else the root textStyle
(label/labelStyle.ts setTokenTextStyle: each font part is the component's,
else the global one's), a rich token from its own style, else the block's.

Each case is one chart with `fontStyle: 'italic'` (or 'oblique') written at
one site. After an SSR render the display list is walked and every TSpan
(the drawn line or token of a Text) is recorded: its text and its font, and
`italic` -- the font's first word is 'italic' or 'oblique' (CSS font
shorthand: the style comes first). The texts of a case are recorded in
display-list order, duplicates kept.

Sites: series labels (bar, line end label, pie, funnel, gauge title / detail
/ axis labels, radar, sunburst, treemap, sankey, tree, graph, heatmap,
scatter on a calendar), rich tokens, markPoint / markLine labels, titles and
subtitles, legend items, axis labels and names (cartesian, polar, radar,
single, parallel), calendar day / month / year labels, the timeline's
labels, graphic texts (fontStyle and the font shorthand), visualMap texts
(continuous, piecewise), a map's labels, a matrix's
labels, an axisPointer's label (status 'show'), the loading text
(showLoading's fontStyle), slider dataZoom handle labels, a richText
tooltip's default content (textStyle and the root's: UPRIGHT -- tooltipMarkup's
rich styles name their own font and no style; these last cases run with a
stub dom and env.node off, as text-dash.js does), the root textStyle.

  node tools/advchart-oracle/font-style.js

writes tests/fixtures/advchart-font-style.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
Math.random = function () { return 0; };
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-font-style.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }

// a one-region map: a square
const SQUARE = {
  type: 'FeatureCollection',
  features: [{ type: 'Feature', properties: { name: 'Sq' },
    geometry: { type: 'Polygon', coordinates: [[[0, 0], [10, 0], [10, 10], [0, 10], [0, 0]]] } }],
};
echarts.registerMap('fsquare', SQUARE);

const IT = { fontStyle: 'italic' };
const CAT = ['Mon', 'Tue', 'Wed'];
const opt = o => Object.assign({ animation: false }, o);
const cart = (series, extra) => opt(Object.assign({
  xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' }, series,
}, extra || {}));
const bar = o => Object.assign({ type: 'bar', name: 'S', data: [3, 5, 4] }, o);

const CASES = [
  { id: 'bar-label', note: 'a bar label fontStyle italic',
    option: cart([bar({ label: Object.assign({ show: true, position: 'top' }, IT) })]) },
  { id: 'bar-label-oblique', note: "fontStyle 'oblique'",
    option: cart([bar({ label: { show: true, position: 'top', fontStyle: 'oblique' } })]) },
  { id: 'bar-label-normal-over-root', note: "root italic, the label 'normal'",
    option: cart([bar({ label: { show: true, position: 'top', fontStyle: 'normal' } })], { textStyle: IT }) },
  { id: 'rich-token', note: 'a rich token italic, its sibling not',
    option: cart([bar({ label: { show: true, position: 'top', formatter: '{a|Ab}{b|Cd}', rich: { a: IT, b: {} } } })]) },
  { id: 'rich-block', note: 'the block italic: tokens without their own take it',
    option: cart([bar({ label: { show: true, position: 'top', fontStyle: 'italic', formatter: '{a|Ab}{b|Cd}', rich: { a: {}, b: { fontStyle: 'normal' } } } })]) },
  { id: 'root', note: 'root textStyle italic: every text',
    option: cart([bar({ label: { show: true } })], { title: { text: 'Tt', subtext: 'Sub' }, legend: {}, textStyle: IT,
      xAxis: { type: 'category', data: CAT, name: 'Nx' } }) },
  { id: 'title', note: 'title textStyle italic, subtext not',
    option: cart([bar()], { title: { text: 'Tt', subtext: 'Sub', textStyle: IT } }) },
  { id: 'subtitle', note: 'subtextStyle italic',
    option: cart([bar()], { title: { text: 'Tt', subtext: 'Sub', subtextStyle: IT } }) },
  { id: 'legend', note: 'legend textStyle italic',
    option: cart([bar({ name: 'Aa' }), bar({ name: 'Bb' })], { legend: { textStyle: IT } }) },
  { id: 'legend-selector', note: 'legend selector labels italic, items not',
    option: cart([bar({ name: 'Aa' })], { legend: { selector: true, selectorLabel: IT } }) },
  { id: 'axis-label', note: 'x axisLabel italic, y name nameTextStyle italic',
    option: cart([bar()], { xAxis: { type: 'category', data: CAT, axisLabel: IT },
      yAxis: { type: 'value', name: 'Ny', nameTextStyle: IT } }) },
  { id: 'polar', note: 'angleAxis and radiusAxis labels italic',
    option: opt({ polar: {}, angleAxis: { type: 'category', data: CAT, axisLabel: IT },
      radiusAxis: { axisLabel: IT }, series: [{ type: 'bar', coordinateSystem: 'polar', data: [1, 2, 3] }] }) },
  { id: 'radar', note: 'radar axisName italic',
    option: opt({ radar: { indicator: [{ name: 'Ia', max: 5 }, { name: 'Ib', max: 5 }, { name: 'Ic', max: 5 }], axisName: IT },
      series: [{ type: 'radar', data: [{ value: [1, 2, 3] }] }] }) },
  { id: 'single', note: 'singleAxis axisLabel italic',
    option: opt({ singleAxis: { type: 'category', data: CAT, axisLabel: IT },
      series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [[0, 1], [1, 2]] }] }) },
  { id: 'parallel', note: 'parallelAxis axisLabel and name italic',
    option: opt({ parallelAxis: [{ dim: 0, name: 'Pa', axisLabel: IT, nameTextStyle: IT }, { dim: 1, name: 'Pb' }],
      series: [{ type: 'parallel', data: [[1, 2], [3, 4]] }] }) },
  { id: 'calendar', note: "calendar day, month and year labels italic (nameMap 'EN': the port's locale names are its own)",
    option: opt({ calendar: { range: '2024-01', dayLabel: Object.assign({ nameMap: 'EN' }, IT),
      monthLabel: Object.assign({ nameMap: 'EN' }, IT), yearLabel: IT },
      series: [{ type: 'scatter', coordinateSystem: 'calendar', data: [['2024-01-05', 1]] }] }) },
  { id: 'timeline', note: 'timeline label italic',
    option: { baseOption: { animation: false, timeline: { axisType: 'category', data: ['T1', 'T2'], label: IT, autoPlay: false },
      xAxis: { type: 'category', data: CAT }, yAxis: { type: 'value' }, series: [bar()] },
    options: [{ series: [{ data: [1, 2, 3] }] }, { series: [{ data: [3, 2, 1] }] }] } },
  { id: 'graphic', note: 'graphic texts: fontStyle italic, the font shorthand, and a plain one',
    option: opt({ graphic: [
      { type: 'text', left: 10, top: 10, style: { text: 'Ga', fontSize: 14, fontStyle: 'italic' } },
      { type: 'text', left: 10, top: 40, style: { text: 'Gb', font: 'italic 14px serif' } },
      { type: 'text', left: 10, top: 70, style: { text: 'Gc', fontSize: 14 } }] }) },
  { id: 'visualmap-continuous', note: 'continuous visualMap textStyle italic',
    option: cart([bar()], { visualMap: { type: 'continuous', min: 0, max: 10, text: ['Hi', 'Lo'], calculable: true, textStyle: IT } }) },
  { id: 'visualmap-piecewise', note: 'piecewise visualMap textStyle italic',
    option: cart([bar()], { visualMap: { type: 'piecewise', min: 0, max: 10, splitNumber: 2, textStyle: IT } }) },
  { id: 'gauge', note: 'gauge title, detail and axis labels italic',
    option: opt({ series: [{ type: 'gauge', data: [{ value: 40, name: 'Gn' }], title: IT, detail: Object.assign({ formatter: '{value}' }, IT), axisLabel: IT }] }) },
  { id: 'pie', note: 'pie labels italic',
    option: opt({ series: [{ type: 'pie', data: [{ name: 'Pa', value: 1 }, { name: 'Pb', value: 2 }], label: IT }] }) },
  { id: 'funnel', note: 'funnel labels italic',
    option: opt({ series: [{ type: 'funnel', data: [{ name: 'Fa', value: 1 }, { name: 'Fb', value: 2 }], label: IT }] }) },
  { id: 'line-endlabel', note: 'a line end label italic',
    option: cart([{ type: 'line', name: 'L', data: [1, 2, 3], endLabel: Object.assign({ show: true }, IT) }]) },
  { id: 'markers', note: 'markPoint and markLine labels italic',
    option: cart([bar({ markPoint: { data: [{ type: 'max', name: 'Mx' }], label: IT },
      markLine: { data: [{ type: 'average' }], label: IT } })]) },
  { id: 'sunburst', note: 'sunburst labels italic',
    option: opt({ series: [{ type: 'sunburst', data: [{ name: 'Sa', value: 2, children: [{ name: 'Sb', value: 1 }] }], label: IT }] }) },
  { id: 'treemap', note: 'treemap labels italic',
    option: opt({ series: [{ type: 'treemap', breadcrumb: { show: false }, data: [{ name: 'Ta', value: 2 }, { name: 'Tb', value: 1 }], label: IT }] }) },
  { id: 'sankey', note: 'sankey labels italic',
    option: opt({ series: [{ type: 'sankey', data: [{ name: 'Ka' }, { name: 'Kb' }], links: [{ source: 'Ka', target: 'Kb', value: 1 }], label: IT }] }) },
  { id: 'tree', note: 'tree labels italic',
    option: opt({ series: [{ type: 'tree', data: [{ name: 'Ra', children: [{ name: 'Rb' }] }], label: IT }] }) },
  { id: 'graph', note: 'graph labels italic',
    option: opt({ series: [{ type: 'graph', layout: 'none', data: [{ name: 'Na', x: 10, y: 10 }, { name: 'Nb', x: 50, y: 50 }], label: Object.assign({ show: true }, IT) }] }) },
  { id: 'heatmap', note: 'heatmap labels italic',
    option: opt({ xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'category', data: ['c', 'd'] },
      visualMap: { show: false, min: 0, max: 5 },
      series: [{ type: 'heatmap', data: [[0, 0, 1], [1, 1, 3]], label: Object.assign({ show: true }, IT) }] }) },
  { id: 'map', note: 'a map series label italic',
    option: opt({ series: [{ type: 'map', map: 'fsquare', label: Object.assign({ show: true }, IT), data: [{ name: 'Sq', value: 1 }] }] }) },
  { id: 'matrix', note: 'matrix header labels italic',
    option: opt({ matrix: { x: { data: ['Xa', 'Xb'], label: IT }, y: { data: ['Ya', 'Yb'], label: IT } } }) },
  { id: 'loading', note: "showLoading('default') with fontStyle italic: its text",
    option: cart([bar()]), loading: { text: 'Ld', fontStyle: 'italic', fontSize: 14 } },
  { id: 'datazoom', note: 'slider dataZoom handle labels (handleLabel.show) with textStyle italic',
    option: opt({ xAxis: { type: 'category', data: ['c1', 'c2', 'c3'], axisLabel: { show: false } }, yAxis: { type: 'value' },
      series: [bar()], dataZoom: [{ type: 'slider', handleLabel: { show: true }, textStyle: IT }] }) },
  { id: 'axispointer', note: 'an axisPointer shown by status, its label italic',
    option: cart([bar()], { xAxis: { type: 'category', data: CAT,
      axisPointer: { show: true, value: 'Tue', status: 'show', label: Object.assign({ show: true }, IT) } } }) },
  { id: 'radar-normal-over-root', note: "radar axisName 'normal' under the root italic: the name upright, the title italic",
    option: opt({ textStyle: IT, title: { text: 'Rt' }, radar: { indicator: [{ name: 'Ia', max: 5 }, { name: 'Ib', max: 5 }, { name: 'Ic', max: 5 }], axisName: { fontStyle: 'normal' } },
      series: [{ type: 'radar', data: [{ value: [1, 2, 3] }] }] }) },
  { id: 'axispointer-root', note: 'an axisPointer shown by status under the root textStyle italic: its label takes the root',
    option: cart([bar()], { textStyle: IT, xAxis: { type: 'category', data: CAT,
      axisPointer: { show: true, value: 'Tue', status: 'show', label: { show: true } } } }) },
];

function italicOf(font) {
  const first = String(font || '').trim().split(/\s+/)[0];
  return first === 'italic' || first === 'oblique';
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    if (c.loading) chart.showLoading('default', JSON.parse(JSON.stringify(c.loading)));
    chart.renderToSVGString();
    const list = chart.getZr().storage.getDisplayList(true);
    const texts = [];
    list.forEach(el => {
      if (el.type !== 'tspan' || el.invisible) return;
      const t = el.style.text;
      if (t == null || String(t).trim() === '') return;
      texts.push({ text: String(t), font: String(el.style.font || ''), italic: italicOf(el.style.font) });
    });
    return texts;
  } finally {
    chart.dispose();
  }
}

const records = CASES.map(c => Object.assign({ id: c.id, note: c.note, option: c.option },
  c.loading ? { loading: c.loading } : {}, { texts: runCase(c) }));

// THE TOOLTIP draws a zrender Text in richText mode; it needs a dom and a
// non-node environment (as text-dash.js and toolbox.js stub them), so these
// run last
(function enableEnv() {
  const probe = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 10, height: 10 });
  const proto = Object.getPrototypeOf(probe);
  probe.dispose();
  const dom = {};
  proto.getDom = function () { return dom; };
  echarts.env.node = false;
})();
const pieTip = (tip, root) => opt(Object.assign({ tooltip: Object.assign({ trigger: 'item', renderMode: 'richText' }, tip),
  series: [{ type: 'pie', name: 'Ser', label: { show: false }, data: [{ name: 'Pt', value: 123 }, { name: 'Qt', value: 77 }] }] }, root || {}));
const TIP_CASES = [
  { id: 'tooltip-textstyle', note: "a richText tooltip, textStyle italic: its default content", option: pieTip({ textStyle: IT }) },
  { id: 'tooltip-root', note: 'a richText tooltip under the root textStyle italic', option: pieTip({}, { textStyle: IT }) },
  { id: 'tooltip-normal-over-root', note: "the tooltip's textStyle 'normal' under a root italic", option: pieTip({ textStyle: { fontStyle: 'normal' } }, { textStyle: IT }) },
];
TIP_CASES.forEach(c => {
  c.showTip = { type: 'showTip', seriesIndex: 0, dataIndex: 0 };
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    chart.dispatchAction(c.showTip);
    chart.renderToSVGString();
    const texts = [];
    chart.getZr().storage.getDisplayList(true).forEach(el => {
      if (el.type !== 'tspan' || el.invisible) return;
      const t = el.style.text;
      if (t == null || String(t).trim() === '') return;
      texts.push({ text: String(t), font: String(el.style.font || ''), italic: italicOf(el.style.font) });
    });
    records.push({ id: c.id, note: c.note, option: c.option, showTip: c.showTip, texts });
  } finally {
    chart.dispose();
  }
});

// guards: what the source says, independently of the run
const failed = [];
const guard = (what, cond) => { if (!cond) failed.push(what); };
const byId = id => records.find(r => r.id === id);
const it = (id, text) => byId(id).texts.filter(t => t.text === text);
guard('every case but the tooltips drew at least one italic text',
  records.every(r => r.id.indexOf('tooltip-') === 0 || r.texts.some(t => t.italic)));
guard("bar-label-oblique: 'oblique' leads the three labels' font", byId('bar-label-oblique').texts.filter(t => /^oblique /.test(t.font)).length === 3);
guard("bar-label-normal-over-root: the label's 'normal' beats the root", byId('bar-label-normal-over-root').texts.slice(-3).every(t => !t.italic));
guard('bar-label-normal-over-root: the axis labels take the root', it('bar-label-normal-over-root', 'Mon').every(t => t.italic));
guard('rich-token: Ab italic, Cd not', it('rich-token', 'Ab').every(t => t.italic) && it('rich-token', 'Cd').every(t => !t.italic));
guard("rich-block: Ab takes the block's, Cd its own normal", it('rich-block', 'Ab').every(t => t.italic) && it('rich-block', 'Cd').every(t => !t.italic));
guard('root: every text italic', byId('root').texts.every(t => t.italic));
guard('title: Tt italic, Sub not', it('title', 'Tt').every(t => t.italic) && it('title', 'Sub').every(t => !t.italic));
guard('subtitle: Sub italic, Tt not', it('subtitle', 'Sub').every(t => t.italic) && it('subtitle', 'Tt').every(t => !t.italic));
guard('legend-selector: the items upright', it('legend-selector', 'Aa').every(t => !t.italic));
guard('axis-label: x labels italic, y labels not', it('axis-label', 'Mon').every(t => t.italic) && it('axis-label', '0').every(t => !t.italic));
guard('graphic: Ga and Gb italic, Gc not', it('graphic', 'Ga')[0].italic && it('graphic', 'Gb')[0].italic && !it('graphic', 'Gc')[0].italic);
records.forEach(r => guard(r.id + ': has texts', r.texts.length > 0));
guard('loading: Ld italic', it('loading', 'Ld').length === 1 && it('loading', 'Ld')[0].italic);
guard('datazoom: the handle labels italic', it('datazoom', 'c1').length > 0 && it('datazoom', 'c1').every(t => t.italic));
// tooltipMarkup's richText styles write their own font parts and no
// fontStyle; the content's makeFont is '400 14px sans-serif' whatever
// textStyle says -- upright
['tooltip-textstyle', 'tooltip-root', 'tooltip-normal-over-root'].forEach(id =>
  guard(id + ': the richText content upright', byId(id).texts.length === 3 && byId(id).texts.every(t => !t.italic)));
if (failed.length) {
  failed.forEach(f => console.log('guard failed: ' + f));
  process.exit(1);
}

const out = { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H,
  maps: { fsquare: JSON.stringify(SQUARE) }, cases: records };
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote', OUT, records.length + ' cases, ' + records.reduce((n, r) => n + r.texts.length, 0) + ' texts');
process.exit(0);
