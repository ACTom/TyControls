// Upstream's own answers for a geo region's label beyond its words and font
// (component/helper/MapDraw.ts resetLabelForRegion: setLabelStyle with the
// region's label states and textConfig.position the region's centre as
// percentages): `rich`, a text box (backgroundColor, borderColor /
// borderWidth / borderRadius, padding), textBorderColor / textBorderWidth,
// `distance` (a percentage position never reads it), and a state's own
// `position` under highlight.
//
// Runs the real ECharts 6.1 build in node's server-side mode (SVG renderer),
// registers a small map, renders once and reads every region label off the
// geo view's group; cases with `hover` dispatch each payload, run a frame and
// read the labels again.
//
//   node tools/advchart-oracle/geo-labels.js
//
// writes tests/fixtures/advchart-geo-labels.json (ORACLE_OUT overrides).
//
// map {name, text}; cases[]  id, note, W, H, option
//   labels[]  every region label, in the view's order: ignore, texts (the
//             drawn lines / tokens, in order), rect ([x, y, w, h] hex: the
//             bounding rect through the computed transform), box (a
//             background or border rect is drawn), stroke / lineWidth (the
//             text's own: textBorder*; null where none)
//   hover[]   {payload, labels[]}
// Self-checks: anchors; two generations give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-geo-labels.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  must(typeof v === 'number', 'not a number: ' + JSON.stringify(v));
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const hexOrNull = v => (v == null ? null : hex(v));

const box = (x0, y0, x1, y1) => [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]];
const MAP = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: 'Alpha' }, geometry: { type: 'Polygon', coordinates: box(0, 0, 10, 8) } },
    { type: 'Feature', properties: { name: 'Beta' }, geometry: { type: 'Polygon', coordinates: box(12, 0, 20, 10) } },
    { type: 'Feature', properties: { name: 'Gamma' }, geometry: { type: 'Polygon', coordinates: box(0, 10, 9, 18) } },
  ],
};
const MAP_TEXT = JSON.stringify(MAP);
const MAP_NAME = 'r5cGeoLabels';
echarts.registerMap(MAP_NAME, MAP_TEXT);

function geo(label, extra) {
  return { animation: false, geo: Object.assign({ map: MAP_NAME, label }, extra || {}) };
}
const HL = name => ({ type: 'highlight', geoIndex: 0, name });

const CASES = [
  { id: 'plain', note: 'the words alone (the reference)', option: geo({ show: true }) },
  { id: 'border', note: 'textBorderColor and textBorderWidth: the text\'s own stroke',
    option: geo({ show: true, textBorderColor: '#ffffff', textBorderWidth: 3 }) },
  { id: 'box', note: 'a text box: background, border, radius, padding',
    option: geo({ show: true, backgroundColor: '#eeeeee', borderColor: '#333333', borderWidth: 1, borderRadius: 3, padding: [2, 4] }) },
  { id: 'rich', note: 'rich text: a formatter with a styled token',
    option: geo({ show: true, formatter: '{a|{a}}!', rich: { a: { color: '#c23531', fontSize: 16 } } }) },
  { id: 'distance', note: 'distance 20: the percentage position never reads it',
    option: geo({ show: true, distance: 20 }) },
  { id: 'emph.position', note: 'emphasis.label.position top: a hovered region\'s label moves above it', hover: [HL('Alpha')],
    option: geo({ show: true }, { emphasis: { label: { position: 'top', distance: 6 } } }) },
];

function labelsOf(chart) {
  const out = [];
  const gv = chart._componentsViews.find(v => v.__model && v.__model.mainType === 'geo');
  must(gv, 'no geo view');
  gv.group.traverse(el => {
    const label = el.getTextContent && el.getTextContent();
    if (!label) return;
    const r = label.getBoundingRect().clone();
    const m = label.getComputedTransform();
    if (m) r.applyTransform(m);
    const texts = [];
    let boxDrawn = false;
    (label.childrenRef ? label.childrenRef() : []).forEach(c => {
      if (c.type === 'tspan') texts.push(String(c.style.text));
      else if (c.type === 'rect') boxDrawn = true;
    });
    out.push({
      ignore: !!label.ignore,
      texts,
      rect: [hex(r.x), hex(r.y), hex(r.width), hex(r.height)],
      box: boxDrawn,
      stroke: label.style.stroke == null ? null : String(label.style.stroke),
      lineWidth: hexOrNull(label.style.lineWidth),
    });
  });
  return out;
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(c.option);
    chart.renderToSVGString();
    const labels = labelsOf(chart);
    const hover = [];
    for (const p of c.hover || []) {
      chart.dispatchAction(p);
      chart._onframe();
      chart.renderToSVGString();
      hover.push({ payload: p, labels: labelsOf(chart) });
    }
    return { id: c.id, note: c.note, W, H, option: c.option, labels, hover };
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = {};
  for (const c of cases) by[c.id] = c;
  must(by.plain.labels.length === 3, 'anchor: three labels');
  must(by.border.labels.every(l => l.stroke === '#ffffff' && l.lineWidth === hex(3)), 'anchor: the text border');
  must(by.box.labels.every(l => l.box), 'anchor: the box is drawn');
  must(by.rich.labels.every(l => l.texts.length === 2), 'anchor: a token and the rest');
  must(JSON.stringify(by.distance.labels) === JSON.stringify(by.plain.labels), 'anchor: distance changes nothing');
  const moved = by['emph.position'].hover[0].labels[0];
  const rest = by['emph.position'].labels[0];
  must(moved && rest && moved.rect[1] !== rest.rect[1], 'anchor: the hovered label moves');
  return { source: 'ECharts 6.1 dist, component/helper/MapDraw.ts, label/labelStyle.ts, zrender Element.updateInnerText',
    map: { name: MAP_NAME, text: MAP_TEXT }, cases };
}

let code = 0;
try {
  const a = JSON.stringify(generate(), null, 1);
  const b = JSON.stringify(generate(), null, 1);
  must(a === b, 'two generations differ');
  fs.writeFileSync(OUT, a + '\n');
  console.log('wrote ' + OUT);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e);
  code = 1;
}
process.exit(code);
