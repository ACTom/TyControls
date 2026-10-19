/*
Upstream's own answers for fix batch R2-A b2 (spec section 218): a pie's
data items' own `label` and `labelLine`. pie/labelLayout.ts reads every
label option through the ITEM's model (data.getItemModel(idx)): position,
distanceToLabelLine, alignTo, edgeDistance, bleedMargin, rotate, and the
labelLine's length, length2, minTurnAngle, maxSurfaceAngle; PieView styles
the text and the line from the item's states models (formatter, ink, rich
block, labelLine.show, smooth). The position is
`labelModel.get('position') || itemModel.get(['emphasis', 'label', 'position'])`:
a falsy one written ('' or null on the series) falls to the emphasis
position. Whether a slice has a guide line at all is its label's position
WITHOUT that fallback (PieView: itemModel.get(['label', 'position']) is
'outer' / 'outside').

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off). Every slice's label is read off the live elements after a
render: its words, whether it is ignored, its computed transform, its turn,
the alignment drawn, its global bounding rect, the painted ink of its first
TSpan; its guide line's ignore and points.

  node tools/advchart-oracle/pie-item-label.js

writes tests/fixtures/advchart-pie-item-label.json (ORACLE_OUT overrides);
generated twice in the process, byte-identical; ends with process.exit().

Fixture
  source, W, H, cases[], guards[]
  case: id, note, option,
        labels[] {d, text, ignore, x, y (hex: the computed transform's
                  translation), rotation (hex), align, verticalAlign,
                  rect ([4 hex]: the global bounding rect), fill, stroke,
                  lineWidth (hex | null), guide: null | {ignore,
                  points [[hex, hex] ...]}}
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-pie-item-label.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const clone = o => JSON.parse(JSON.stringify(o));

const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
function pie(series, root) {
  return Object.assign({ animation: false, color: PALETTE,
    series: [Object.assign({ type: 'pie', radius: '50%' }, series)] }, root || {});
}
const DATA = () => [
  { value: 1548, name: 'CityE' }, { value: 735, name: 'CityC' }, { value: 510, name: 'CityD' },
  { value: 434, name: 'CityB' }, { value: 335, name: 'CityA' }];
function withItem(i, extra) {
  const d = DATA();
  d[i] = Object.assign(d[i], extra);
  return d;
}

// the gallery's pie-rich-text, its weather pictures as plain colours
const RICH_ITEM = {
  formatter: '{title|{b}}{abg|}\n  {weatherHead|Weather}{valueHead|Days}{rateHead|Percent}\n{hr|}\n  {Sunny|}{value|202}{rate|55.3%}\n  {Cloudy|}{value|142}{rate|38.9%}\n  {Showers|}{value|21}{rate|5.8%}',
  backgroundColor: '#eee', borderColor: '#777', borderWidth: 1, borderRadius: 4,
  rich: {
    title: { color: '#eee', align: 'center' },
    abg: { backgroundColor: '#333', width: '100%', align: 'right', height: 25, borderRadius: [4, 4, 0, 0] },
    Sunny: { height: 30, align: 'left', backgroundColor: '#fc0' },
    Cloudy: { height: 30, align: 'left', backgroundColor: '#999' },
    Showers: { height: 30, align: 'left', backgroundColor: '#39f' },
    weatherHead: { color: '#333', height: 24, align: 'left' },
    hr: { borderColor: '#777', width: '100%', borderWidth: 0.5, height: 0 },
    value: { width: 20, padding: [0, 20, 0, 30], align: 'left' },
    valueHead: { color: '#333', width: 20, padding: [0, 20, 0, 30], align: 'center' },
    rate: { width: 40, align: 'right', padding: [0, 10, 0, 0] },
    rateHead: { color: '#333', width: 40, align: 'center', padding: [0, 10, 0, 0] },
  },
};

const CASES = [
  { id: 'item.basics', note: 'one item its own formatter and colour, one hidden, one inside, one with no line',
    option: pie({ data: (() => {
      const d = DATA();
      d[0].label = { formatter: '{b}: {c} ({d}%)', color: '#ff0000' };
      d[1].label = { show: false };
      d[2].label = { position: 'inside' };
      d[3].labelLine = { show: false };
      return d;
    })() }) },
  { id: 'item.line', note: 'an item\'s labelLine length, length2 and smooth; another\'s distanceToLabelLine',
    option: pie({ data: (() => {
      const d = DATA();
      d[0].labelLine = { length: 30, length2: 5, smooth: 0.5 };
      d[2].label = { distanceToLabelLine: 15 };
      return d;
    })() }) },
  { id: 'item.edge', note: 'one item aligned to the edge, one turned radially (the solver off for all)',
    option: pie({ data: (() => {
      const d = DATA();
      d[1].label = { alignTo: 'edge', edgeDistance: '10%' };
      d[3].label = { rotate: 'radial' };
      return d;
    })() }) },
  { id: 'item.rich', note: 'the gallery\'s pie-rich-text: one item\'s rich block',
    option: pie({ radius: '65%', center: ['50%', '50%'], selectedMode: 'single', data: withItem(0, { label: RICH_ITEM }) }) },
  { id: 'item.state.only', note: 'the series hides the labels, an item\'s emphasis shows its own',
    option: pie({ label: { show: false }, data: withItem(2, { emphasis: { label: { show: true } } }) }) },
  { id: 'position.null.emphasis', note: 'series label.position null: the emphasis position (center) for all, no guide lines',
    option: pie({ radius: ['40%', '70%'], label: { position: null }, emphasis: { label: { position: 'center' } }, data: DATA() }) },
  { id: 'position.null.emphasis.outside', note: 'series label.position null, emphasis outside: placed outer, yet no guide lines (PieView reads the null)',
    option: pie({ label: { position: null }, emphasis: { label: { position: 'outside' } }, data: DATA() }) },
  { id: 'position.null', note: 'series label.position null and no emphasis one: placed outer, no guide lines',
    option: pie({ label: { position: null }, data: DATA() }) },
  { id: 'position.empty.item', note: 'an item\'s position \'\' falls to its emphasis position (inside)',
    option: pie({ data: withItem(0, { label: { position: '' }, emphasis: { label: { position: 'inside' } } }) }) },
  { id: 'position.null.item', note: 'an item\'s position null is unwritten: the series\' inner',
    option: pie({ label: { position: 'inner' }, data: withItem(1, { label: { position: null } }) }) },
  { id: 'item.inside.series', note: 'the series inside, an item outer with its line',
    option: pie({ label: { position: 'inside' }, data: withItem(4, { label: { position: 'outer' } }) }) },
];

function painted(t) {
  const kids = t.childrenRef ? t.childrenRef() : [];
  const sp = kids.find(k => k.type === 'tspan');
  const s = sp ? sp.style : t.style;
  return {
    fill: s.fill == null ? null : String(s.fill),
    stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: s.stroke == null || s.lineWidth == null ? null : hex(s.lineWidth),
  };
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    chart.renderToSVGString();
    const sm = chart.getModel().getSeriesByIndex(0);
    const data = sm.getData();
    const labels = [];
    data.each(idx => {
      const el = data.getItemGraphicEl(idx);
      if (!el) return;
      const t = el.getTextContent();
      if (!t) return;
      const m = t.getComputedTransform();
      const ds = t._defaultStyle || {};
      const r = t.getBoundingRect().clone();
      if (m) r.applyTransform(m);
      const g = el.getTextGuideLine();
      const p = painted(t);
      labels.push({
        d: idx,
        text: t.style.text == null ? '' : String(t.style.text),
        ignore: !!t.ignore,
        x: hex(m ? m[4] : t.x), y: hex(m ? m[5] : t.y),
        rotation: hex(t.rotation),
        align: t.style.align || ds.align || 'left',
        verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
        rect: [r.x, r.y, r.width, r.height].map(hex),
        fill: p.fill, stroke: p.stroke, lineWidth: p.lineWidth,
        guide: g ? { ignore: !!g.ignore, points: (g.shape.points || []).map(q => [hex(q[0]), hex(q[1])]) } : null,
      });
    });
    return { id: c.id, note: c.note, option: clone(c.option), labels };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = id => cases.find(c => c.id === id);
  const lab = (id, d) => by(id).labels.find(l => l.d === d);
  const guards = [
    { name: 'item.basics: the item formatter', ok: lab('item.basics', 0).text.indexOf('CityE: 1548') === 0 },
    { name: 'item.basics: item 1 hidden, no line shown', ok: lab('item.basics', 1).ignore && lab('item.basics', 1).guide.ignore },
    { name: 'item.basics: item 2 inside, no line', ok: lab('item.basics', 2).guide === null && lab('item.basics', 2).align === 'center' },
    { name: 'item.basics: item 3 line hidden', ok: lab('item.basics', 3).guide.ignore && !lab('item.basics', 3).ignore },
    { name: 'position.null.emphasis: every label at the centre, no lines',
      ok: by('position.null.emphasis').labels.every(l => l.guide === null && l.x === hex(300) && l.y === hex(200)) },
    { name: 'position.null.emphasis.outside: outer, no lines', ok: by('position.null.emphasis.outside').labels.every(l => l.guide === null && l.align !== 'center') },
    { name: 'position.null: no lines', ok: by('position.null').labels.every(l => l.guide === null) },
    { name: 'position.empty.item: item 0 inside', ok: lab('position.empty.item', 0).guide === null && lab('position.empty.item', 0).align === 'center' },
    { name: 'position.null.item: item 1 inner', ok: lab('position.null.item', 1).align === 'center' },
    { name: 'item.inside.series: item 4 outer with its line (the item\'s word)', ok: lab('item.inside.series', 4).guide !== null && lab('item.inside.series', 4).align !== 'center' },
    { name: 'item.state.only: item 2 built, ignored', ok: lab('item.state.only', 2) && lab('item.state.only', 2).ignore },
  ];
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H, cases, guards };
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
out1.cases.forEach(c => console.log(c.id + ': ' + c.labels.length + ' labels, ' + c.labels.filter(l => !l.ignore).length + ' shown'));
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log(json1 !== json2 ? 'FAILED: two generations differ' : 'FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
