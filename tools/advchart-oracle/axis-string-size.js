// [R7-L] Upstream's own answers for an AXIS LABEL whose width or height is
// written as a word ('50%') or a numeric string over a box: zrender lays the
// label's plate out at NaN (x + '50%0'), so Text.getBoundingRect's union is
// NaN on that axis. What that does downstream, per grid:
//   - fixMinMaxLabelShow and axisLabel.hideOverlap weigh the labels with
//     BoundingRect.intersect, whose comparisons with NaN are all false: two
//     labels meet when their other axis does, and an end label is hidden;
//   - under grid.outerBoundsMode 'auto' (the default) or 'same', the grid's
//     outer bounds shrink by every label's overflow (layOutGridByOuterBounds,
//     Math.max with NaN): the grid rect is NaN on that axis, and with it the
//     series, the axis lines and the names;
//   - under outerBoundsMode 'none' the grid is the raw one and the names keep
//     their places (resolveAxisNameOverlap moves a name only where its rect
//     meets a label's on the other axis).
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode (SVG renderer, 600 x 400,
// animation false, Math.random pinned to 0 before the library loads),
// measuring every string with zrender's width table as rich-text.js does.
//
// The fixture, top level:
//   source, ratios {firstCode, lastCode, fontSize, ratio[], ratioText[]}
//   cases[]  {name, note, W, H, option, grid, gridNaN, axes[]}
//     grid     [x, y, width, height] of grid 0's coordinateSystem.getRect(),
//              hex (NaN 7ff8000000000000) with a text twin
//     gridNaN  whether any of the four is NaN
//     axes[]   {axis ('xAxis0' / 'yAxis0'), labels[] {text, shown}, name
//              {text, placed} | null} -- labels in the order AxisBuilder
//              built them (their anid 'label_<i>'), shown = not ignored;
//              placed = the name's transform is finite
//
// Self-checks (nothing is written and the run exits 1 when one fails): the
// measure rule, a baseline case with no string size shows every label and
// both names on a finite grid, and two runs in one process give the same
// JSON. Outside the script: run it twice and diff the files.
//
//   node tools/advchart-oracle/axis-string-size.js
'use strict';
Math.random = function () { return 0; };

const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-string-size.json');
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
const text = v => (Object.is(v, -0) ? '-0' : String(v));

// ---------- the width table (as rich-text.js) ----------
const FIRST_CODE = 32;
const LAST_CODE = 126;
const DEFAULT_FONT_SIZE = 12;
const mapStr = (() => {
  const line = fs.readFileSync(DIST.replace(/echarts\.min\.js$/, 'echarts.js'), 'utf8').split('\n')
    .find(l => /\bdefaultWidthMapStr\s*=/.test(l));
  must(line, 'no defaultWidthMapStr');
  const s = Function('"use strict"; return (' + line.slice(line.indexOf('=') + 1).trim().replace(/;$/, '') + ');')();
  must(typeof s === 'string' && s.length === LAST_CODE - FIRST_CODE + 1, 'the width table is not 95 characters');
  return s;
})();
const RATIO = Array.from(mapStr, ch => (ch.charCodeAt(0) - 20) / 100);
RATIO.forEach((r, i) => {
  const w = new echarts.graphic.Text({ style: { text: String.fromCharCode(FIRST_CODE + i), font: '1px sans-serif' } })
    .getBoundingRect().width;
  must(Object.is(w, r), 'char code ' + (FIRST_CODE + i) + ': the table says ' + r + ', a 1px Text measures ' + w);
});

// ---------- the cases ----------
const opt = o => Object.assign({ animation: false }, o);
const CAT = ['a', 'b', 'c'];
const xCat = o => Object.assign({ type: 'category', data: CAT, name: 'XN' }, o);
const yVal = o => Object.assign({ type: 'value', name: 'YN' }, o);
const BAR = [{ type: 'bar', data: [1, 2, 3] }];
const WORD = { width: '50%', backgroundColor: '#eeeeee' };
const NONE = { outerBoundsMode: 'none' };
const cases = [
  { name: 'baseline', note: 'no string size: every label, both names, a finite grid',
    option: opt({ xAxis: xCat(), yAxis: yVal(), series: BAR }) },
  { name: 'x-word-none', note: "x axis labels width '50%' with a plate, outerBoundsMode 'none': the three meet on y, the ends are hidden; the grid and the names as ever",
    option: opt({ grid: NONE, xAxis: xCat({ axisLabel: WORD }), yAxis: yVal(), series: BAR }) },
  { name: 'x-word-none-showmin', note: "the same with showMinLabel true: the inner label is hidden instead of the first",
    option: opt({ grid: NONE, xAxis: xCat({ axisLabel: Object.assign({ showMinLabel: true }, WORD) }), yAxis: yVal(), series: BAR }) },
  { name: 'x-word-none-hide', note: "with hideOverlap: only the first is kept",
    option: opt({ grid: NONE, xAxis: xCat({ data: ['a', 'b', 'c', 'd', 'e'], axisLabel: Object.assign({ hideOverlap: true }, WORD) }), yAxis: yVal(), series: [{ type: 'bar', data: [1, 2, 3, 4, 5] }] }) },
  { name: 'x-height-none', note: "x axis labels height '50%' with a plate, outerBoundsMode 'none': NaN on y, they meet on x only where they overlap there",
    option: opt({ grid: NONE, xAxis: xCat({ axisLabel: { height: '50%', backgroundColor: '#eeeeee' } }), yAxis: yVal(), series: BAR }) },
  { name: 'y-word-none', note: "y axis labels width '50%' with a plate, outerBoundsMode 'none': NaN on x, the y labels apart on y keep",
    option: opt({ grid: NONE, xAxis: xCat(), yAxis: yVal({ axisLabel: WORD }), series: BAR }) },
  { name: 'x-word-nobox-none', note: "a word width with no plate: nothing at NaN",
    option: opt({ grid: NONE, xAxis: xCat({ axisLabel: { width: '50%' } }), yAxis: yVal(), series: BAR }) },
  { name: 'x-numstr-none', note: "a numeric string width '60' with a plate: the box runs to x + '600', every label meets the next",
    option: opt({ grid: NONE, xAxis: xCat({ axisLabel: { width: '60', backgroundColor: '#eeeeee' } }), yAxis: yVal(), series: BAR }) },
  { name: 'x-word-auto', note: "the default outerBoundsMode 'auto': the grid's outer bounds shrink by a NaN, the grid rect is NaN on x",
    option: opt({ xAxis: xCat({ axisLabel: WORD }), yAxis: yVal(), series: BAR }) },
  { name: 'y-word-auto', note: "y axis labels, the default outerBoundsMode: the grid rect NaN on x",
    option: opt({ xAxis: xCat(), yAxis: yVal({ axisLabel: WORD }), series: BAR }) },
];

function run(c) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    chart.setOption(JSON.parse(JSON.stringify(c.option)));
    chart.renderToSVGString();
    const r = chart.getModel().getComponent('grid', 0).coordinateSystem.getRect();
    const g = [r.x, r.y, r.width, r.height];
    const axes = [];
    chart._componentsViews.forEach(v => {
      if (!v || !v.__model || !/^[xy]Axis$/.test(v.__model.mainType)) return;
      const rec = { axis: v.__model.mainType + v.__model.componentIndex, labels: [], name: null };
      v.group.traverse(el => {
        if (el.type !== 'text') return;
        if (el.anid === 'name') {
          const m = el.transform;
          rec.name = { text: String(el.style.text), placed: !!m && Array.from(m).every(Number.isFinite) };
        } else if (typeof el.anid === 'string' && el.anid.indexOf('label_') === 0) {
          rec.labels.push({ text: String(el.style.text), shown: !el.ignore });
        }
      });
      axes.push(rec);
    });
    axes.sort((a, b) => (a.axis < b.axis ? -1 : a.axis > b.axis ? 1 : 0));
    return { grid: g.map(hex), gridText: g.map(text), gridNaN: g.some(Number.isNaN), axes };
  } finally {
    chart.dispose();
  }
}

function runAll() {
  return cases.map(c => Object.assign({ name: c.name, note: c.note, W, H, option: c.option }, run(c)));
}
const first = runAll();
const second = runAll();
must(JSON.stringify(first) === JSON.stringify(second), 'two runs in one process do not agree');

// guards
const base = first.find(r => r.name === 'baseline');
must(!base.gridNaN, 'baseline: the grid is NaN');
must(base.axes.every(a => a.labels.every(l => l.shown) && a.name && a.name.placed), 'baseline: a label hidden or a name not placed');
const none = first.find(r => r.name === 'x-word-none');
must(!none.gridNaN && none.axes.find(a => a.axis === 'xAxis0').labels.filter(l => l.shown).length === 1,
  'x-word-none: not one x label kept on a finite grid');
must(first.find(r => r.name === 'x-word-auto').gridNaN, 'x-word-auto: the grid is not NaN');

const out = {
  source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version,
  ratios: { firstCode: FIRST_CODE, lastCode: LAST_CODE, fontSize: DEFAULT_FONT_SIZE, ratio: RATIO.map(hex), ratioText: RATIO.map(text) },
  cases: first,
};
fs.writeFileSync(OUT, JSON.stringify(out, null, 1) + '\n');
console.log('wrote ' + OUT + ' ' + first.length + ' cases');
process.exit(0);
