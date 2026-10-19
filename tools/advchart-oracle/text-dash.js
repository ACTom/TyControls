/*
Upstream's own answers for fix batch R2-F (spec section 223): A TEXT'S
DASHED STROKE AND ITS PHASE. zrender's Text hands a stroking TSpan its
style's lineDash and `lineDashOffset || 0` (Text.ts _updatePlainTexts; a rich
token's lineDash is retrieve2(the token's, the block's), the phase always the
block's), and brushText sets ctx.setLineDash(normalizeLineDash(lineDash,
lineWidth)) and ctx.lineDashOffset before strokeText. A graphic text writes
lineDash and lineDashOffset in its style as they are; a label writes
textBorderType and textBorderDashOffset (labelStyle.ts: the label's, else the
global textStyle's) -- label-halo.js holds those.

Two parts:
  static  graphic texts (plain and rich) and their TSpans as zrender holds
          them after a paint: text, stroke, lineWidth, the lineDash as
          written, the lineDashOffset, the pattern normalizeLineDash makes.
  anim    the gallery's graphic-stroke-animation (its option verbatim from
          examples/advchart/gallery): a looping keyframe animation of the
          text's style -- lineDash [0, 200] to [200, 0] and lineDashOffset 0
          to 200 by 70 %, then the fill -- sampled on the animation clock
          (the clock of keyframe-animation.js: the global Date replaced
          before the dist loads, chart._ssr false, env.node off), each
          sample the Text's style values and its TSpan's.

  node tools/advchart-oracle/text-dash.js

writes tests/fixtures/advchart-text-dash.json (ORACLE_OUT overrides). Two
generations byte-identical; ends with process.exit().

Numbers are the 16 lowercase hex digits of the IEEE double (big-endian);
an array of numbers is an array of them; strings plain.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

// ---------- the controlled clock (must precede loading the dist) ----------
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-text-dash.json');
const GALLERY = path.join(ROOT, 'examples', 'advchart', 'gallery', 'graphic-stroke-animation.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
function valRec(v) {
  if (v == null) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'boolean' || typeof v === 'string') return v;
  if (Array.isArray(v) || ArrayBuffer.isView(v)) return Array.from(v).map(valRec);
  return JSON.stringify(v);
}

// zrender canvas/dashStyle.ts, transcribed
function normalizeLineDash(lineType, lineWidth) {
  if (!lineType || lineType === 'solid' || !(lineWidth > 0)) return null;
  return lineType === 'dashed' ? [4 * lineWidth, 2 * lineWidth]
    : lineType === 'dotted' ? [lineWidth]
      : typeof lineType === 'number' ? [lineType] : Array.isArray(lineType) ? lineType : null;
}

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
function gInner(el) {
  for (const k of Object.keys(el)) {
    if (k.startsWith('__ec_inner_') && el[k] && typeof el[k] === 'object' && 'isNew' in el[k]) return el[k];
  }
  return null;
}
function graphicTexts(chart) {
  const view = (chart._componentsViews || []).find(v => v && v.type === 'graphic');
  must(view, 'no graphic view');
  const out = [];
  const walk = g => g.childrenRef().forEach(el => {
    if (el.type === 'text') out.push({ id: String(gInner(el).id), el });
    if (el.isGroup) walk(el);
  });
  walk(view.group);
  return out;
}
function spanOf(s) {
  const lw = s.lineWidth;
  const pat = normalizeLineDash(s.lineDash, lw);
  return {
    text: s.text == null ? null : String(s.text),
    stroke: s.stroke == null ? null : String(s.stroke),
    lineWidth: lw == null ? null : hex(lw),
    lineDash: s.lineDash == null ? null : valRec(s.lineDash),
    lineDashOffset: s.lineDashOffset == null ? null : hex(s.lineDashOffset),
    pattern: pat == null ? null : pat.map(hex),
  };
}
function spansOf(el) {
  const kids = el.childrenRef ? el.childrenRef() : [];
  return kids.filter(k => k.type === 'tspan').map(k => spanOf(k.style));
}

// ---------- static: graphic texts ----------
const g = (id, style) => ({ type: 'text', id, x: 40, y: 40, style: Object.assign({ fontSize: 20 }, style) });
const STATIC = [
  { id: 'plain', note: 'a graphic text with lineDash [4, 2] and lineDashOffset 3',
    option: { graphic: [g('t', { text: 'Abc', stroke: '#ff0000', lineWidth: 2, lineDash: [4, 2], lineDashOffset: 3 })] } },
  { id: 'words', note: "lineDash 'dashed' and 'dotted' on a graphic text (normalizeLineDash against lineWidth 3), no offset",
    option: { graphic: [g('a', { text: 'Ab', stroke: '#ff0000', lineWidth: 3, lineDash: 'dashed' }),
      g('b', { text: 'Cd', stroke: '#00ff00', lineWidth: 3, lineDash: 'dotted', y: 80 })] } },
  { id: 'zeros', note: 'lineDash [0, 200], the gallery start: a dash of no length',
    option: { graphic: [g('z', { text: 'Ab', stroke: '#000', lineWidth: 1, lineDash: [0, 200], lineDashOffset: 0 })] } },
  { id: 'no-stroke', note: 'lineDash with no stroke: the TSpan has no lineDash (Text.ts sets it only with a stroke)',
    option: { graphic: [g('n', { text: 'Ab', lineDash: [4, 2], lineDashOffset: 5 })] } },
  { id: 'negative', note: 'a negative lineDashOffset', option: { graphic: [g('m', { text: 'Ab', stroke: '#000', lineWidth: 2, lineDash: [6, 3], lineDashOffset: -4 })] } },
  { id: 'rich', note: "a rich graphic text: the block lineDash [5, 1] and offset 2, token a's own lineDash [1, 1] and offset 9 (the phase stays the block's), token b nothing",
    option: { graphic: [g('r', { text: '{a|Aa}{b|Bb}', stroke: '#0000ff', lineWidth: 2, lineDash: [5, 1], lineDashOffset: 2,
      rich: { a: { lineDash: [1, 1], lineDashOffset: 9 }, b: {} } })] } },
];

function runStatic(c) {
  const chart = mk(400, 300);
  try {
    chart.setOption(Object.assign({ animation: false }, c.option));
    chart.renderToSVGString();
    refresh(chart);
    const texts = graphicTexts(chart).map(t => ({ id: t.id, spans: spansOf(t.el) }));
    return { id: c.id, note: c.note, option: c.option, texts };
  } finally {
    chart.dispose();
  }
}

// ---------- anim: the gallery's stroke animation ----------
const ANIM_TIMES = [0, 1, 300, 1050, 1800, 2099, 2100, 2250, 2399, 2400, 2700, 2999, 3000, 3001, 3300, 4050];
function runAnim() {
  const option = JSON.parse(fs.readFileSync(GALLERY, 'utf8'));
  const chart = mk(800, 500);
  try {
    chart.setOption(option);
    const z = chart.getZr();
    const samples = ANIM_TIMES.map(t => {
      NOW = T0 + t;
      z.animation.update();
      refresh(chart);
      const ts = graphicTexts(chart);
      must(ts.length === 1, 'one text');
      const el = ts[0].el;
      return {
        t,
        style: { lineDash: valRec(el.style.lineDash), lineDashOffset: valRec(el.style.lineDashOffset),
          fill: valRec(el.style.fill), stroke: valRec(el.style.stroke) },
        spans: spansOf(el),
      };
    });
    return { gallery: 'graphic-stroke-animation', W: 800, H: 500, samples };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
    clock: { T0 },
    static: STATIC.map(runStatic),
    anim: runAnim(),
  };
  const st = id => out.static.find(c => c.id === id);
  const at = t => out.anim.samples.find(s => s.t === t);
  const arr = h => (h == null ? null : h.map(num));
  out.guards = [
    { name: 'plain: [4, 2] and 3', ok: JSON.stringify(arr(st('plain').texts[0].spans[0].pattern)) === '[4,2]'
      && num(st('plain').texts[0].spans[0].lineDashOffset) === 3 },
    { name: "words: 'dashed' against 3 is [12, 6]", ok: JSON.stringify(arr(st('words').texts[0].spans[0].pattern)) === '[12,6]' },
    { name: 'no stroke: no lineDash', ok: st('no-stroke').texts[0].spans[0].lineDash === null },
    { name: "rich: token a's own dash, the block's phase", ok: st('rich').texts[0].spans.some(s => s.text === 'Aa'
      && JSON.stringify(arr(s.pattern)) === '[1,1]' && num(s.lineDashOffset) === 2) },
    { name: 'anim: the dash grows', ok: num(at(1050).spans[0].pattern[0]) > 50 && num(at(1050).spans[0].pattern[0]) < 150 },
    { name: 'anim: the phase moves', ok: num(at(1050).spans[0].lineDashOffset) > 0 && num(at(2100).spans[0].lineDashOffset) === 200 },
    { name: 'anim: it loops', ok: num(at(3001).spans[0].lineDashOffset) < 1 },
  ];
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
out1.static.forEach(c => console.log(c.id + ': ' + JSON.stringify(c.texts.map(t => t.spans.map(s => [s.text, s.lineDash, s.pattern && s.pattern.map(num), s.lineDashOffset && num(s.lineDashOffset)])))));
out1.anim.samples.forEach(s => console.log('t ' + s.t + ': ' + JSON.stringify(s.spans.map(q => [q.pattern && q.pattern.map(num), q.lineDashOffset && num(q.lineDashOffset)])) + ' fill ' + s.style.fill));
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
if (bad.length || json1 !== json2 || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
