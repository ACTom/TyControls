// Upstream's own answers for labelLayout's `width` and `height`
// (label/LabelManager.ts updateLayoutConfig: LABEL_OPTION_TO_STYLE_KEYS sets
// them on the label's style, the label's own where the layout says nothing).
// zrender's Text reads them as the text block's size (parsePlainText /
// parseRichText): an overflow ('truncate', 'break', 'breakAll') cuts or wraps
// at the width, a lineOverflow 'truncate' drops lines past the height, a
// background or a border is drawn at that size -- and the bounding rect the
// layout's hideOverlap and moveOverlap weigh is the box's where one is drawn.
//
// Runs the real ECharts 6.1 build in node's server-side mode (SVG renderer),
// renders once to an SVG string and reads every series label off the live
// elements.
//
//   node tools/advchart-oracle/label-layout-size.js
//
// writes tests/fixtures/advchart-label-layout-size.json (ORACLE_OUT overrides).
//
// cases[]  id, note, W, H, option
//   labels[]  every label of a series element, series in order, each view's
//             group in traverse order: s, d, ignore, texts (the drawn lines,
//             TSpans in order), rect ([x, y, w, h] in hex: getBoundingRect
//             through getComputedTransform -- axis aligned, nothing here
//             turns), styleWidth / styleHeight (hex | null)
// Self-checks: anchors; two generations give the same bytes.
'use strict';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-label-layout-size.json');
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

// ---------- the handlers ----------
const HANDLERS = {
  '@LS_W': p => ({ width: 20 + (p.dataIndex % 3) * 15 }),
};
function bind(o) {
  if (Array.isArray(o)) return o.map(bind);
  if (o && typeof o === 'object') {
    const r = {};
    for (const k of Object.keys(o)) r[k] = bind(o[k]);
    return r;
  }
  if (typeof o === 'string' && Object.prototype.hasOwnProperty.call(HANDLERS, o)) return HANDLERS[o];
  return o;
}

// ---------- the cases ----------
const pts = (n, a, b) => Array.from({ length: n }, (_, i) => [(i * a) % 23, (i * b) % 17 + (i % 3) * 0.5]);
const cats = n => Array.from({ length: n }, (_, i) => 'c' + i);
function scatter(s, extra) {
  return Object.assign({ animation: false, xAxis: {}, yAxis: {},
    series: [Object.assign({ type: 'scatter', symbolSize: 10, data: pts(10, 7, 13) }, s)] }, extra || {});
}
const BG = { show: true, backgroundColor: '#eee', borderColor: '#999', borderWidth: 1, padding: 2 };
const PIE = () => [{ name: 'Search Engine', value: 1048 }, { name: 'Direct', value: 735 }, { name: 'Email', value: 580 },
  { name: 'Union Ads', value: 484 }, { name: 'Video Ads', value: 300 }];

const CASES = [
  { id: 'bg.size', note: 'a boxed label, labelLayout width 50 and height 24: the box at that size',
    option: scatter({ label: BG, labelLayout: { width: 50, height: 24 } }) },
  { id: 'bg.width.hide', note: 'boxed labels widened to 60 with hideOverlap: the wider boxes hide more',
    option: scatter({ data: pts(30, 7, 13), label: BG, labelLayout: { width: 60, hideOverlap: true } }) },
  { id: 'bg.nowidth.hide', note: 'the same without the width', option: scatter({ data: pts(30, 7, 13), label: BG, labelLayout: { hideOverlap: true } }) },
  { id: 'truncate', note: "overflow 'truncate', labelLayout width 30", option: scatter({ label: { show: true, overflow: 'truncate', formatter: 'point {b}{c}' }, labelLayout: { width: 30 } }) },
  { id: 'truncate.ellipsis', note: "overflow 'truncate' with an ellipsis of its own, width 40",
    option: scatter({ label: { show: true, overflow: 'truncate', ellipsis: '~', formatter: 'value of {c}' }, labelLayout: { width: 40 } }) },
  { id: 'break', note: "overflow 'break', width 25: wrapped", option: scatter({ label: { show: true, overflow: 'break', formatter: 'aa bb cc dd' }, labelLayout: { width: 25 } }) },
  { id: 'lineoverflow', note: "lineOverflow 'truncate', height 14: lines past it dropped",
    option: scatter({ label: { show: true, lineOverflow: 'truncate', formatter: 'one\ntwo\nthree' }, labelLayout: { height: 14 } }) },
  { id: 'plain.width', note: 'a plain label given a width and nothing to overflow: unchanged', option: scatter({ label: { show: true }, labelLayout: { width: 80 } }) },
  { id: 'rich.width', note: 'a rich label in a box, width 70',
    option: scatter({ label: { show: true, formatter: '{a|{c}}', backgroundColor: '#ddd', rich: { a: { color: '#333' } } }, labelLayout: { width: 70 } }) },
  { id: 'fn.width', note: 'a function giving each a width, overflow truncate',
    option: scatter({ label: { show: true, overflow: 'truncate', formatter: 'label {c}' }, labelLayout: '@LS_W' }) },
  { id: 'bar.bg', note: 'bar labels in a box widened to 44',
    option: { animation: false, xAxis: { type: 'category', data: cats(6) }, yAxis: {},
      series: [{ type: 'bar', data: [5, 9, 3, 7, 4, 8], label: Object.assign({ position: 'top' }, BG), labelLayout: { width: 44 } }] } },
  // ---- draggable: Draggable's drift on the label, then its 'drag' handler ----
  { id: 'drag.pie', note: 'pie labels draggable: a drift moves the label, the drag handler routes its line from the anchor',
    option: { animation: false, series: [{ type: 'pie', radius: '40%', data: [{ name: 'a', value: 3 }, { name: 'b', value: 5 }, { name: 'c', value: 2 }],
      labelLayout: { draggable: true } }] },
    drift: [{ d: 0, dx: 40, dy: 25 }, { d: 1, dx: -30, dy: 12 }] },
  { id: 'drag.free', note: 'scatter labels placed at x / y and draggable: moved, their lines routed again',
    option: scatter({ label: { show: true }, labelLine: { show: true }, labelLayout: { draggable: true, x: 300, y: 50 }, data: pts(3, 7, 13) }),
    drift: [{ d: 1, dx: 35, dy: 40 }] },
  { id: 'drag.attached', note: 'labels on their host (dx / dy) and draggable: the position puts them back, the line as it was',
    option: scatter({ label: { show: true }, labelLine: { show: true }, labelLayout: { draggable: true, dx: 20, dy: -20 }, data: pts(3, 7, 13) }),
    drift: [{ d: 0, dx: 30, dy: 15 }] },
  // ---- [R5-F] a pie's labels: the layout's width / height on their style too ----
  { id: 'pie.width', note: "pie labels under labelLayout width 30: the pie's default overflow 'truncate' cuts them",
    option: { animation: false, series: [{ type: 'pie', radius: '40%', data: PIE(), labelLayout: { width: 30 } }] } },
  { id: 'pie.width.box', note: 'boxed pie labels sized 70 x 24 by the layout',
    option: { animation: false, series: [{ type: 'pie', radius: '40%', data: PIE(), label: BG, labelLayout: { width: 70, height: 24 } }] } },
  { id: 'pie.width.rich', note: 'rich pie labels under labelLayout width 45',
    option: { animation: false, series: [{ type: 'pie', radius: '40%', data: PIE(),
      label: { formatter: '{a|{b}} {c|{c}}', rich: { a: { color: '#333' }, c: { color: '#999' } } }, labelLayout: { width: 45 } }] } },
  { id: 'pie.height', note: "three-line pie labels, lineOverflow 'truncate' under labelLayout height 14",
    option: { animation: false, series: [{ type: 'pie', radius: '40%', data: PIE(),
      label: { formatter: '{b}\n{c}\n{d}%', lineOverflow: 'truncate' }, labelLayout: { height: 14 } }] } },
];

function guideRecs(chart) {
  const out = [];
  chart.getModel().eachSeries(s => {
    chart.getViewOfSeriesModel(s).group.traverse(el => {
      const g = el.getTextGuideLine && el.getTextGuideLine();
      if (!g) return;
      const d = ecData(el);
      out.push({ s: s.seriesIndex, d: d && d.dataIndex != null ? d.dataIndex : null, ignore: !!g.ignore,
        points: g.shape.points.map(q => [hex(q[0]), hex(q[1])]) });
    });
  });
  return out;
}

function labelRec(s, el, label) {
  const d = ecData(el);
  const r = label.getBoundingRect().clone();
  const m = label.getComputedTransform();
  if (m) r.applyTransform(m);
  const texts = [];
  (label.childrenRef ? label.childrenRef() : []).forEach(c => {
    if (c.type === 'tspan' || (c.style && typeof c.style.text === 'string' && c.type !== 'rect')) texts.push(String(c.style.text));
  });
  return {
    s: s.seriesIndex,
    d: d && d.dataIndex != null ? d.dataIndex : null,
    ignore: !!label.ignore,
    texts,
    rect: [hex(r.x), hex(r.y), hex(r.width), hex(r.height)],
    styleWidth: hexOrNull(label.style.width),
    styleHeight: hexOrNull(label.style.height),
    draggable: !!label.draggable,
    cursor: label.cursor == null ? null : String(label.cursor),
  };
}

function runCase(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(bind(c.option));
    chart.renderToSVGString();
    const read = () => {
      const labels = [];
      chart.getModel().eachSeries(s => {
        chart.getViewOfSeriesModel(s).group.traverse(el => {
          const label = el.getTextContent && el.getTextContent();
          if (label) labels.push(labelRec(s, el, label));
        });
      });
      return labels;
    };
    const labels = read();
    const rec = { id: c.id, note: c.note, W, H, option: JSON.parse(JSON.stringify(c.option)), labels };
    if (c.drift) {
      rec.guides = guideRecs(chart);
      // zrender's Draggable: drift(dx, dy) on the label, then its 'drag'
      const s0 = chart.getModel().getSeriesByIndex(0);
      const data = s0.getData();
      for (const m of c.drift) {
        const g = data.getItemGraphicEl(m.d);
        let label = g.getTextContent && g.getTextContent();
        if (!label && g.traverse) g.traverse(c => { if (!label && c.getTextContent && c.getTextContent()) label = c.getTextContent(); });
        must(label.draggable, 'the label is draggable');
        label.drift(m.dx, m.dy);
        label.trigger('drag');
      }
      chart.renderToSVGString();
      rec.drift = c.drift;
      rec.labelsAfter = read();
      rec.guidesAfter = guideRecs(chart);
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

function generate() {
  const cases = CASES.map(runCase);
  const by = {};
  for (const c of cases) by[c.id] = c;
  const fh = h => { for (let i = 0; i < 8; i++) bits.setUint8(i, parseInt(h.substr(i * 2, 2), 16)); return bits.getFloat64(0); };
  must(by['bg.size'].labels.every(l => fh(l.rect[2]) >= 50), 'anchor: a boxed label is as wide as the layout says');
  must(by['bg.width.hide'].labels.filter(l => l.ignore).length > by['bg.nowidth.hide'].labels.filter(l => l.ignore).length,
    'anchor: wider boxes hide more');
  must(by['truncate'].labels.some(l => l.texts.join('').indexOf('...') >= 0), 'anchor: truncated');
  must(by['break'].labels.some(l => l.texts.length > 1), 'anchor: wrapped');
  must(by['lineoverflow'].labels.every(l => l.texts.length === 1), 'anchor: lines dropped');
  must(by['drag.pie'].labelsAfter[0].rect[0] !== by['drag.pie'].labels[0].rect[0], 'anchor: a dragged pie label moves');
  must(by['drag.pie'].guidesAfter[0].points[2][0] !== by['drag.pie'].guides[0].points[2][0], 'anchor: its line follows');
  must(by['drag.free'].labelsAfter[1].rect[0] !== by['drag.free'].labels[1].rect[0], 'anchor: a free label moves');
  must(by['drag.attached'].labelsAfter[0].rect[0] === by['drag.attached'].labels[0].rect[0], 'anchor: an attached label stays');
  must(by['drag.pie'].labels.every(l => l.cursor === 'move'), 'anchor: the cursor is move');
  must(by['pie.width'].labels.some(l => l.texts.join('').indexOf('...') >= 0), 'anchor: a pie label cut at the layout width');
  must(by['pie.width.box'].labels.every(l => fh(l.rect[2]) >= 70), 'anchor: a boxed pie label as wide as the layout says');
  must(by['pie.height'].labels.every(l => l.texts.length === 1), 'anchor: a pie label lost the lines past the height');
  return { source: 'ECharts 6.1 dist, label/LabelManager.ts, zrender graphic/Text.ts, graphic/helper/parseText.ts', W, H, cases };
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
