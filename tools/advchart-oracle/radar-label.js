/*
Upstream's own answers for fix batch R2-A b1 (spec section 218): a radar
series' data labels. RadarView hangs one label on every point's symbol
(setLabelStyle on the symbol path with labelDimIndex = the spoke): the
symbol is built in the unit box (-1, -1, 2, 2), scaled by half its size and
turned, so the label sits off that box through updateInnerText --
`series.label` (position 'top' by default) under `data[].label`; the words
are the spoke's stored value (nothing for NaN) unless a formatter says
otherwise, `{c}` being the spoke's raw value. No symbol ('none'), no label.
A missing value is a point at the centre (radarLayout's
getValueMissingPoint), and its label hangs there. The labels go through the
LabelManager: labelLayout, and a fade-in on every render (the symbols are
rebuilt each time).

Runs the real ECharts 6.1 dist in node's SSR mode (SVG renderer, 600 x 400,
animation off except the `fade` records, which run with a controlled clock
as animation.js does). Every label is read off the live elements after a
render: its computed transform, the alignment drawn (style, else the host's
default), and its first TSpan's painted style; the host symbol's position;
each row's polyline points. A case with `hover` dispatches it, runs one
frame and reads the labels again.

  node tools/advchart-oracle/radar-label.js

writes tests/fixtures/advchart-radar-label.json (ORACLE_OUT overrides);
generated twice in the process, byte-identical; ends with process.exit().

Fixture
  source, W, H, cases[], fade, guards[]
  case: id, note, option, rows[] {d, points [[hex, hex] ...]},
        labels[] {d, dim, text, ignore, x, y, mat ([6 hex], null when none),
                  rotation (hex: the turn its host's textConfig gave it),
                  align, verticalAlign, fill, stroke, lineWidth (hex | null),
                  opacity (hex), hostX, hostY (hex), z2,
                  guide: null | {ignore, points [[hex, hex] ...]}},
        hover: null | {payload, labels[] {d, dim, ignore, fill, stroke,
                  lineWidth}}
  fade: {option, samples[] {t, opacity [hex per label], x, y}} -- the
        enter (t from setOption) and an update at 5000 (t from it)
*/
'use strict';
const fs = require('fs');
const path = require('path');

// ---- the clock (animation.js): new Date() / Date.now() read NOW ----
let NOW = 1700000000000;
const RealDate = Date;
class ClockDate extends RealDate {
  constructor(...a) { if (a.length === 0) super(NOW); else super(...a); }
  static now() { return NOW; }
}
global.Date = ClockDate;

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-radar-label.json');
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

const IND5 = [{ name: 'a', max: 100 }, { name: 'b', max: 100 }, { name: 'c', max: 100 }, { name: 'd', max: 100 },
  { name: 'e', max: 100 }];
// upstream's own palette, written: the port's theme has its own, and a
// label's inherited or inside ink comes from it
const PALETTE = ['#5070dd', '#b6d634', '#505372', '#ff994d', '#0ca8df', '#ffd10a', '#fb628b', '#785db0', '#3fbe95'];
function radar(series, root) {
  return Object.assign({ animation: false, color: PALETTE, radar: { indicator: IND5 }, series }, root || {});
}
const P = { value: [60, 70, 80, 50, 40], name: 'p' };
const Q = { value: [30, 90, 40, 70, 60], name: 'q' };

const CASES = [
  { id: 'series.top', note: 'series.label.show: every point labelled, top by default, its value',
    option: radar([{ type: 'radar', label: { show: true }, data: [P, Q] }]) },
  { id: 'item.only', note: 'one item shows its labels (radar-custom): a rect of 12, dashed line',
    option: radar([{ type: 'radar', data: [P, Object.assign({}, Q, { symbol: 'rect', symbolSize: 12, lineStyle: { type: 'dashed' }, label: { show: true } })] }]) },
  { id: 'item.hides', note: 'the series shows them, an item hides its own',
    option: radar([{ type: 'radar', label: { show: true }, data: [P, Object.assign({}, Q, { label: { show: false } })] }]) },
  { id: 'formatter', note: 'a series formatter and an item formatter: {c} the spoke\'s raw value, {b} the name, {a} the series',
    option: radar([{ type: 'radar', name: 'S', label: { show: true, formatter: '{a}/{b}/{c}' },
      data: [P, Object.assign({}, Q, { label: { formatter: '{c}%' } })] }]) },
  { id: 'raw.values', note: 'raw values as written: a numeric string, a decimal, \'-\', null',
    option: radar([{ type: 'radar', label: { show: true, formatter: '[{c}]' },
      data: [{ value: ['12.50', 0.1 + 0.2, '-', null, 7], name: 'r' }] },
    { type: 'radar', label: { show: true }, data: [{ value: ['12.50', 0.1 + 0.2, '-', null, 7], name: 'r2' }] }]) },
  { id: 'positions', note: 'per item: right with distance 10, inside, bottom offset and turned',
    option: radar([{ type: 'radar', label: { show: true, position: 'right', distance: 10 },
      data: [P, Object.assign({}, Q, { symbolSize: 20, label: { position: 'inside' } }),
        { value: [10, 20, 30, 40, 50], name: 's', label: { position: 'bottom', offset: [3, -2], rotate: 30 } }] }]) },
  { id: 'missing', note: 'a missing value is a point at the centre; its label hangs there',
    option: radar([{ type: 'radar', label: { show: true, formatter: '{b}:{c}' },
      data: [{ value: [60, '-', 80, null, 40], name: 'm' }] },
    { type: 'radar', label: { show: true }, data: [{ value: ['-', 70, 80, 50, 40], name: 'n' }] }]) },
  { id: 'symbol.none', note: 'no symbol, no label',
    option: radar([{ type: 'radar', symbol: 'none', label: { show: true }, data: [P] }]) },
  { id: 'symbol.empty', note: 'an empty circle: its stroke grows the box the label hangs off',
    option: radar([{ type: 'radar', symbol: 'emptyCircle', symbolSize: 10, label: { show: true, position: 'left' }, data: [P] }]) },
  { id: 'symbol.turned', note: 'a turned triangle: the label hangs off the turned box',
    option: radar([{ type: 'radar', symbol: 'triangle', symbolSize: [14, 8], symbolRotate: 45, label: { show: true }, data: [P] }]) },
  { id: 'colours', note: 'label colour inherit and a literal, a border',
    option: radar([{ type: 'radar', label: { show: true, color: 'inherit' },
      data: [P, Object.assign({}, Q, { label: { color: '#ff0000', textBorderColor: '#00ff00', textBorderWidth: 3 } })] }]) },
  { id: 'state.only', note: 'only the emphasis shows the labels: ignored at rest, shown hovered',
    option: radar([{ type: 'radar', label: { show: false }, emphasis: { label: { show: true, color: '#0000ff' } }, data: [P, Q] }]),
    hover: { type: 'highlight', seriesIndex: 0, dataIndex: 1 } },
  { id: 'emphasis.ink', note: 'labels shown; the hovered item\'s in the emphasis colour and border',
    option: radar([{ type: 'radar', label: { show: true }, emphasis: { label: { color: '#ff00ff', textBorderColor: '#000000', textBorderWidth: 1 } }, data: [P, Q] }]),
    hover: { type: 'highlight', seriesIndex: 0, dataIndex: 0 } },
  { id: 'hideOverlap', note: 'labelLayout.hideOverlap: two near rings, the later labels hidden where they overlap',
    option: radar([{ type: 'radar', label: { show: true, formatter: 'value {c}' }, labelLayout: { hideOverlap: true },
      data: [P, { value: [62, 71, 79, 52, 41], name: 'p2' }] }]) },
  { id: 'labelLine', note: 'labelLine.show with labelLayout dx / dy: each point label\'s line routed from its symbol',
    option: radar([{ type: 'radar', label: { show: true }, labelLine: { show: true }, labelLayout: { dx: 24, dy: -16 }, data: [P] }]) },
  { id: 'fontSize', note: 'a written font size and weight',
    option: radar([{ type: 'radar', label: { show: true, fontSize: 18, fontWeight: 'bold', position: 'top' }, data: [P] }]) },
  // [r2v] createSymbol reads no symbolOffset: the symbol and its label stay on the point
  { id: 'symbol.offset', note: 'a series and an item symbolOffset: not read, the symbols and labels on their points',
    option: radar([{ type: 'radar', symbolOffset: [9, 6], label: { show: true },
      data: [P, Object.assign({}, Q, { symbol: 'rect', symbolSize: 10, symbolOffset: [-7, 5] })] }]) },
];

function ringPoints(data, idx) {
  const g = data.getItemGraphicEl(idx);
  if (!g) return null;
  const pl = g.childAt(0);
  return (pl.shape.points || []).map(p => [hex(p[0]), hex(p[1])]);
}

// the painted style: the first TSpan's (Text builds them when updated)
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

function eachLabel(chart, fn) {
  chart.getModel().eachSeries(sm => {
    if (sm.subType !== 'radar') return;
    const data = sm.getData();
    data.each(idx => {
      const g = data.getItemGraphicEl(idx);
      if (!g) return;
      const sg = g.childAt(2);
      sg.eachChild(sym => {
        const t = sym.getTextContent();
        if (!t) return;
        fn(sm.seriesIndex, idx, sym, t);
      });
    });
  });
}

function readLabels(chart) {
  const out = [];
  eachLabel(chart, (s, d, sym, t) => {
    const m = t.getComputedTransform();
    const ds = t._defaultStyle || {};
    const p = painted(t);
    out.push({
      s, d, dim: sym.__dimIdx,
      text: t.style.text == null ? '' : String(t.style.text),
      ignore: !!t.ignore,
      x: hex(m ? m[4] : t.x), y: hex(m ? m[5] : t.y),
      mat: m ? Array.from(m).map(hex) : null,
      rotation: hex(t.innerTransformable ? t.innerTransformable.rotation : t.rotation),
      align: t.style.align || ds.align || 'left',
      verticalAlign: t.style.verticalAlign || ds.verticalAlign || 'top',
      fill: p.fill, stroke: p.stroke, lineWidth: p.lineWidth,
      opacity: hex(t.style.opacity == null ? 1 : t.style.opacity),
      hostX: hex(sym.x), hostY: hex(sym.y),
      z2: t.z2,
      guide: (g => (g ? { ignore: !!g.ignore, points: (g.shape.points || []).map(q => [hex(q[0]), hex(q[1])]) } : null))(sym.getTextGuideLine()),
    });
  });
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(clone(c.option));
    chart.renderToSVGString();
    const rows = [];
    chart.getModel().eachSeries(sm => {
      const data = sm.getData();
      data.each(idx => rows.push({ s: sm.seriesIndex, d: idx, points: ringPoints(data, idx) }));
    });
    const labels = readLabels(chart);
    let hover = null;
    if (c.hover) {
      chart.dispatchAction(c.hover);
      chart._onframe();
      chart.getZr().storage.getDisplayList(true);
      const hl = [];
      eachLabel(chart, (s, d, sym, t) => {
        const p = painted(t);
        hl.push({ s, d, dim: sym.__dimIdx, ignore: !!t.ignore, fill: p.fill, stroke: p.stroke, lineWidth: p.lineWidth });
      });
      hover = { payload: c.hover, labels: hl };
    }
    return { id: c.id, note: c.note, option: clone(c.option), rows, labels, hover };
  } finally {
    chart.dispose();
  }
}

// ---- the fade: the enter, then an update ----
const FADE_OPTION = {
  color: PALETTE,
  radar: { indicator: [{ name: 'a', max: 100 }, { name: 'b', max: 100 }, { name: 'c', max: 100 }] },
  series: [{ type: 'radar', label: { show: true }, data: [{ value: [60, 70, 80], name: 'p' }, { value: [20, 30, 40], name: 'q' }] }],
};
const FADE_UPDATE = { series: [{ type: 'radar', data: [{ value: [30, 20, 50], name: 'p' }, { value: [20, 30, 40], name: 'q' }] }] };
const FADE_T = [0, 100, 300, 500, 800, 1000, 1200];
function runFade() {
  const wasNode = echarts.env.node;
  echarts.env.node = false;
  const T0 = NOW = 1700000000000;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  const zr = chart.getZr();
  const sample = (t, phase) => {
    zr.storage.getDisplayList(true);
    const labels = readLabels(chart);
    return { phase, t, opacity: labels.map(l => l.opacity), x: labels.map(l => l.x), y: labels.map(l => l.y),
      hostX: labels.map(l => l.hostX), hostY: labels.map(l => l.hostY) };
  };
  try {
    const samples = [];
    chart.setOption(clone(FADE_OPTION));
    for (const t of FADE_T) {
      if (t > 0) { NOW = T0 + t; zr.animation.update(); }
      samples.push(sample(t, 'enter'));
    }
    NOW = T0 + 5000;
    zr.animation.update();
    chart.setOption(clone(FADE_UPDATE));
    for (const t of FADE_T) {
      if (t > 0) { NOW = T0 + 5000 + t; zr.animation.update(); }
      samples.push(sample(t, 'update'));
    }
    return { option: clone(FADE_OPTION), update: clone(FADE_UPDATE), samples };
  } finally {
    chart.dispose();
    echarts.env.node = wasNode;
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const fade = runFade();
  const by = id => cases.find(c => c.id === id);
  const num = h => { bits.setUint32(0, parseInt(h.slice(0, 8), 16)); bits.setUint32(4, parseInt(h.slice(8), 16)); return bits.getFloat64(0); };
  const guards = [
    { name: 'series.top: ten labels, top, centre / bottom',
      ok: by('series.top').labels.length === 10 && by('series.top').labels.every(l => l.align === 'center' && l.verticalAlign === 'bottom') },
    { name: 'item.only: only q\'s five labels shown',
      ok: by('item.only').labels.filter(l => !l.ignore).length === 5 && by('item.only').labels.every(l => l.d === 1) },
    { name: 'missing: the centre point and its label there',
      ok: (() => { const r = by('missing').rows[0].points; return r[1][0] === hex(300) && r[1][1] === hex(200); })() },
    { name: 'missing: \'{b}:{c}\' prints - and null',
      ok: by('missing').labels.some(l => l.text === 'm:-') && by('missing').labels.some(l => l.text === 'm:null') },
    { name: 'labelLine: five lines shown', ok: by('labelLine').labels.filter(l => l.guide && !l.guide.ignore).length === 5 },
    { name: 'symbol.none: no labels', ok: by('symbol.none').labels.length === 0 },
    { name: 'state.only: ignored at rest, the hovered item shown',
      ok: by('state.only').labels.every(l => l.ignore) && by('state.only').hover.labels.some(l => !l.ignore) },
    { name: 'hideOverlap hides some', ok: by('hideOverlap').labels.some(l => l.ignore) && by('hideOverlap').labels.some(l => !l.ignore) },
    { name: 'fade: the enter starts at 0 and ends at 1, the symbols still',
      ok: fade.samples[0].opacity.every(o => num(o) === 0) && fade.samples[5].opacity.every(o => num(o) === 1)
        && fade.samples[0].hostY.join() === fade.samples[5].hostY.join() },
    { name: 'fade: an update fades the labels in again, the symbols moving',
      ok: fade.samples[7].opacity.every(o => num(o) === 0) && fade.samples[12].opacity.every(o => num(o) === 1)
        && fade.samples[8].hostY[0] !== fade.samples[12].hostY[0] },
    { name: 'symbol.offset: every symbol on its ring point (no offset)',
      ok: (() => { const c = by('symbol.offset'); return c.labels.length === 10 && c.labels.every(l => {
        const r = c.rows.find(q => q.d === l.d).points[l.dim]; return r[0] === l.hostX && r[1] === l.hostY; }); })() },
  ];
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H, cases, fade, guards };
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
