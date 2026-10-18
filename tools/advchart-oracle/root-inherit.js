/*
Upstream's own answers for fix batch F4c (spec section 207): the option ROOT
reaching the component and series models through their parent chain, and the
grid's box as getLayoutRect lays it out.

Every component and series model is created with the GlobalModel as its
parent (GlobalModel._mergeOption: new ComponentModelClass(option, this, this)),
so Model.getShallow / Model.get read the option root for a key a model's
option -- its defaults merged under it -- holds as null or not at all. This
script records, on the real ECharts 6.1 dist in node's SSR mode:

  box      getBoxLayoutParams() of a component or series (util/layout.ts:173,
           getShallow without ignoreParent) for an option whose root writes
           box keys: the six values raw ('<undef>' for undefined), and where
           the model lays itself out by them, its rect: a grid's and a single
           axis' coordinateSystem.getRect(), a parallel's, a tree / treemap /
           sankey series' layoutInfo, a title's group and frame.
  grid     a grid's rect (getRect, outerBoundsMode 'none', axes hidden) for
           the getLayoutRect keywords ('right', 'center', 'bottom' on either
           edge), BoundingRect's flip of a negative size, mergeLayoutParam's
           box branch, and root keys reaching the default grid.
  silent   the series view group's `silent` (core/echarts.ts:2508
           `!!seriesModel.get('silent')`) and a markLine group's
           (MarkLineView.ts:437), with the root's `silent` under them; the
           bar's rect, to hit-test at its centre.
  prog     getProgressive(), getProgressiveThreshold() and
           get('progressiveChunkMode') of a series with the root's
           progressive keys under it.
  diag     no record: the option texts the port's diagnostics must accept.

Numbers are 16 lowercase hex digits of the IEEE double (big-endian) with a
readable twin. Runs twice; the two outputs must be byte-identical. Ends with
process.exit().

  node tools/advchart-oracle/root-inherit.js
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-root-inherit.json');

const W = 600;
const H = 400;
const KEYS = ['left', 'top', 'right', 'bottom', 'width', 'height'];

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
function rawRec(v) {
  if (v === undefined) return '<undef>';
  if (v === null) return null;
  if (typeof v === 'number') return { n: hex(v), t: text(v) };
  return v;
}
function rectRec(r) {
  return { x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height),
    text: [r.x, r.y, r.width, r.height].map(text).join(',') };
}

function newChart() {
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}

const HIDDEN_AXES = { xAxis: { type: 'value', show: false }, yAxis: { type: 'value', show: false } };

// ---------- the cases ----------
const CASES = [];
function add(group, id, note, option, read) {
  CASES.push({ group, id, note, option, read });
}

// -- grid: the keywords, the flip, the merge, the root --
const gridCase = (id, note, grid, root) => add('grid', id, note,
  Object.assign({ animation: false }, HIDDEN_AXES, root || {},
    grid === undefined ? {} : { grid: Object.assign({ outerBoundsMode: 'none' }, grid) }),
  ['grid']);
gridCase('g-left-right', "left: 'right' with a width: the switch puts it at the right edge", { left: 'right', width: 200 });
gridCase('g-left-center', "left: 'center' with a width", { left: 'center', width: 200 });
gridCase('g-top-bottom', "top: 'bottom' with a height", { top: 'bottom', height: 100 });
gridCase('g-right-right', "right: 'right' alone: the default left goes, the word is right's", { right: 'right', width: 150 });
gridCase('g-bottom-middle', "bottom: 'middle' with a height", { bottom: 'middle', height: 120 });
gridCase('g-left-left', "left: 'left' is 0%, top: 'top' 0%", { left: 'left', top: 'top' });
gridCase('g-flip-v', 'top 300 and bottom 300 on 400: the height is -200 and BoundingRect flips it', { top: 300, bottom: 300 });
gridCase('g-flip-h', 'left 400 and right 400 on 600: the width flips', { left: 400, right: 400 });
gridCase('g-three', 'left, width and right all written: the merge keeps the three, the width wins', { left: 10, width: 100, right: 30 });
gridCase('g-auto-left', "left: 'auto' with a right: the merge keeps the default left out, auto is NaN", { left: 'auto', right: 50 });
gridCase('g-root-default', 'no grid component: the default grid, its width and height the root\'s', undefined,
  { left: 50, top: 40, width: 300, height: 200 });
gridCase('g-root-null', 'a grid right written null reads the root right', { right: null }, { right: 20 });
gridCase('g-root-middle', "a grid top written null reads the root's 'middle', its height the root's", { top: null }, { top: 'middle', height: 100 });

// -- single axis --
add('single', 's-keywords', "a single axis with left 'center' and top 'bottom'",
  { animation: false, singleAxis: { type: 'value', left: 'center', width: 200, top: 'bottom', height: 30 },
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 2, 3] }] }, ['single']);
add('single', 's-root', 'a single axis with the root height under it',
  { animation: false, height: 50, singleAxis: { type: 'value' },
    series: [{ type: 'scatter', coordinateSystem: 'singleAxis', data: [1, 2, 3] }] }, ['single']);

// -- components and series reading getBoxLayoutParams --
add('box', 'b-title', "a title whose left is null: the root's 'right'",
  { animation: false, left: 'right', title: { text: 'Title', left: null } }, ['title']);
add('box', 'b-title-top', "a title with the root top 'bottom' (its own top a default, the merge nulls nothing)",
  { animation: false, top: 'bottom', title: { text: 'Title', top: null } }, ['title']);
add('box', 'b-legend', 'a legend whose left is null: both edges read the root, right 10',
  { animation: false, right: 10, legend: { left: null, data: ['a'] }, series: [{ type: 'pie', name: 'p', data: [{ name: 'a', value: 1 }] }] },
  ['legend', 'pie']);
add('box', 'b-pie', 'a pie with no width: the root width 300 boxes it',
  { animation: false, width: 300, series: [{ type: 'pie', data: [1, 2, 3] }] }, ['pie']);
add('box', 'b-funnel', 'a funnel with the root width and a top written null',
  { animation: false, width: 200, top: 30, series: [{ type: 'funnel', top: null, data: [{ value: 3 }, { value: 2 }] }] }, ['funnel']);
add('box', 'b-tree', 'a tree whose width the root gives',
  { animation: false, width: 250, series: [{ type: 'tree', data: [{ name: 'r', children: [{ name: 'a' }, { name: 'b' }] }] }] },
  ['tree']);
add('box', 'b-treemap', 'a treemap with the root height and top null',
  { animation: false, height: 150, top: 20, series: [{ type: 'treemap', top: null, data: [{ value: 3 }, { value: 1 }] }] },
  ['treemap']);
add('box', 'b-sankey', 'a sankey with the root width',
  { animation: false, width: 300, series: [{ type: 'sankey', data: [{ name: 'a' }, { name: 'b' }], links: [{ source: 'a', target: 'b', value: 1 }] }] },
  ['sankey']);
add('box', 'b-calendar', 'a calendar with the root width and its top null',
  { animation: false, width: 400, top: 120, calendar: { range: '2017-01', top: null } }, ['calendar']);
add('box', 'b-parallel', 'a parallel with the root width and height',
  { animation: false, width: 300, height: 200, parallelAxis: [{ dim: 0 }, { dim: 1 }], series: [{ type: 'parallel', data: [[1, 2]] }] },
  ['parallel']);

// -- silent --
// the grid not moved by the labels: the bar's rect does not depend on a font
const BAR = { grid: { outerBoundsMode: 'none' }, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' } };
add('silent', 'sil-root', "the root's silent: true makes the bar series silent",
  Object.assign({ animation: false, silent: true }, BAR, { series: [{ type: 'bar', data: [3, 5] }] }), ['silent']);
add('silent', 'sil-own-false', "the series' own silent: false wins over the root's true",
  Object.assign({ animation: false, silent: true }, BAR, { series: [{ type: 'bar', silent: false, data: [3, 5] }] }), ['silent']);
add('silent', 'sil-own-null', "a series silent written null reads the root's",
  Object.assign({ animation: false, silent: true }, BAR, { series: [{ type: 'bar', silent: null, data: [3, 5] }] }), ['silent']);
add('silent', 'sil-root-1', "the root's silent 1 is truthy (`!!`)",
  Object.assign({ animation: false, silent: 1 }, BAR, { series: [{ type: 'bar', data: [3, 5] }] }), ['silent']);
add('silent', 'sil-marker', "a markLine with the root's silent: true, on a series that says false",
  Object.assign({ animation: false, silent: true }, BAR, { series: [{ type: 'bar', silent: false, data: [3, 5],
    markLine: { data: [{ yAxis: 4 }] } }] }), ['silent']);

// -- progressive --
const progCase = (id, note, root, series) => add('prog', id, note,
  Object.assign({ animation: false }, root, { xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: series }), ['prog']);
progCase('p-scatter', "a scatter has no progressive of its own: the root's 1000 and threshold 500", { progressive: 1000, progressiveThreshold: 500 },
  [{ type: 'scatter', data: [[1, 2]] }]);
progCase('p-scatter-default', "a scatter with nothing written: the global defaults 400 / 3000", {},
  [{ type: 'scatter', data: [[1, 2]] }]);
progCase('p-scatter-large', "a large scatter: 5e3 / 1e4 whatever the root says", { progressive: 1000, progressiveThreshold: 500 },
  [{ type: 'scatter', large: true, data: [[1, 2]] }]);
progCase('p-line', "a line's own 0 keeps the root's out", { progressive: 1000 }, [{ type: 'line', data: [[1, 2]] }]);
progCase('p-line-null', "a line's progressive written null reads the root's", { progressive: 1000 },
  [{ type: 'line', progressive: null, data: [[1, 2]] }]);
progCase('p-bar-large', "a large bar's own 3000; its threshold the root's", { progressive: 1000, progressiveThreshold: 700 },
  [{ type: 'bar', large: true, data: [[1, 2]] }]);
progCase('p-candle', "a candlestick's own threshold 1e4 and chunk mode 'mod'", { progressiveThreshold: 700, progressiveChunkMode: 'sequential' },
  [{ type: 'candlestick', data: [[1, 2, 3, 4]] }]);
progCase('p-scatter-chunk', "a scatter's chunk mode is the root's", { progressiveChunkMode: 'mod' }, [{ type: 'scatter', data: [[1, 2]] }]);
progCase('p-root-null', "a root progressive written null: getShallow's end, null", { progressive: null }, [{ type: 'scatter', data: [[1, 2]] }]);

// ---------- reading ----------
function boxOf(model) {
  const p = model.getBoxLayoutParams();
  const r = {};
  for (const k of KEYS) r[k] = rawRec(p[k]);
  return r;
}

function readCase(c) {
  const chart = newChart();
  try {
    chart.setOption(c.option);
    const ec = chart.getModel();
    const rec = { group: c.group, id: c.id, note: c.note, W, H, option: c.option };
    for (const what of c.read) {
      if (what === 'grid') {
        const g = ec.getComponent('grid', 0);
        rec.gridBox = boxOf(g);
        rec.grid = rectRec(g.coordinateSystem.getRect());
      } else if (what === 'single') {
        const s = ec.getComponent('singleAxis', 0);
        rec.singleBox = boxOf(s);
        rec.single = rectRec(s.coordinateSystem.getRect());
      } else if (what === 'title') {
        const t = ec.getComponent('title', 0);
        rec.titleBox = boxOf(t);
        const g = chart.getViewOfComponentModel(t).group;
        const kids = g.children();
        const textEl = kids[0];
        const bgEl = kids[kids.length - 1];
        must(bgEl.type === 'rect', c.id + ': the title frame is not the last child');
        rec.title = { x: hex(g.x), y: hex(g.y), text: text(g.x) + ',' + text(g.y),
          align: textEl.style.align, verticalAlign: textEl.style.verticalAlign,
          measured: { width: hex(textEl.getBoundingRect().width), height: hex(textEl.getBoundingRect().height) },
          bg: rectRec({ x: g.x + bgEl.shape.x, y: g.y + bgEl.shape.y, width: bgEl.shape.width, height: bgEl.shape.height }) };
      } else if (what === 'legend') {
        rec.legendBox = boxOf(ec.getComponent('legend', 0));
      } else if (what === 'calendar') {
        const m = ec.getComponent('calendar', 0);
        rec.calendarBox = boxOf(m);
        rec.calendar = rectRec(m.coordinateSystem.getRect());
      } else if (what === 'parallel') {
        const m = ec.getComponent('parallel', 0);
        rec.parallelBox = boxOf(m);
        rec.parallel = rectRec(m.coordinateSystem.getRect());
      } else if (['pie', 'funnel', 'tree', 'treemap', 'sankey'].includes(what)) {
        const sm = ec.getSeriesByType(what)[0];
        rec[what + 'Box'] = boxOf(sm);
        if (sm.layoutInfo) rec[what] = rectRec(sm.layoutInfo);
        if (what === 'pie') {
          const l = sm.getData().getItemLayout(0);
          rec.pie = { cx: hex(l.cx), cy: hex(l.cy), r: hex(l.r), text: [l.cx, l.cy, l.r].map(text).join(',') };
        }
      } else if (what === 'silent') {
        const sm = ec.getSeriesByIndex(0);
        const view = chart.getViewOfSeriesModel(sm);
        rec.seriesSilent = !!view.group.silent;
        const el = sm.getData().getItemGraphicEl(1);
        rec.bar = rectRec(el.shape);
        if (sm.option.markLine) {
          // the marker model of the series and its view's group
          let mlView = null;
          chart._componentsViews.forEach(v => { if (v.type === 'markLine') mlView = v; });
          must(mlView, c.id + ': no markLine view');
          const groups = [];
          mlView.markerGroupMap.each(lineDraw => groups.push(lineDraw.group));
          rec.markerSilent = !!groups[0].silent;
          // the marker line's own shape, to hit-test at its middle
          const line = groups[0].childAt(0).childOfName('line');
          const s = line.shape;
          rec.markLine = { x1: hex(s.x1), y1: hex(s.y1), x2: hex(s.x2), y2: hex(s.y2),
            text: [s.x1, s.y1, s.x2, s.y2].map(text).join(',') };
        }
      } else if (what === 'prog') {
        rec.prog = ec.getSeries().map(sm => {
          const p = sm.getProgressive();
          const t = sm.getProgressiveThreshold();
          const m = sm.get('progressiveChunkMode');
          return { type: sm.subType, progressive: rawRec(p === false ? false : p), threshold: rawRec(t),
            chunkMode: rawRec(m) };
        });
      }
    }
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------- guards: the facts each case is there for ----------
function guards(recs) {
  const g = [];
  const by = id => recs.find(r => r.id === id);
  const num = o => (o && typeof o === 'object' && o.t !== undefined ? Number(o.t) : o);
  const check = (name, ok) => { g.push({ name, ok }); };
  check("g-left-right: the switch puts x at W - width", Number(by('g-left-right').grid.text.split(',')[0]) === W - 200);
  check('g-flip-v: the flipped height is positive', Number(by('g-flip-v').grid.text.split(',')[3]) === 200);
  check('g-flip-h: the flipped width is positive', Number(by('g-flip-h').grid.text.split(',')[2]) === 200);
  check("g-root-default: the root's width reaches the default grid", num(by('g-root-default').gridBox.width) === 300);
  check("g-root-null: the root's right replaces a null", num(by('g-root-null').gridBox.right) === 20);
  check("s-root: the root's height reaches a single axis", num(by('s-root').singleBox.height) === 50);
  check("b-title: the root's left reaches the title", by('b-title').titleBox.left === 'right' && by('b-title').title.align === 'right');
  check("b-pie: the root's width reaches the pie", num(by('b-pie').pieBox.width) === 300);
  check('sil-root: silent', by('sil-root').seriesSilent === true);
  check('sil-own-false: not silent', by('sil-own-false').seriesSilent === false);
  check('sil-own-null: silent', by('sil-own-null').seriesSilent === true);
  check('sil-marker: the marker silent through the root', by('sil-marker').markerSilent === true);
  check("p-scatter: the root's progressive", num(by('p-scatter').prog[0].progressive) === 1000);
  check("p-line: the line's own 0", num(by('p-line').prog[0].progressive) === 0);
  check("p-line-null: a null climbs", num(by('p-line-null').prog[0].progressive) === 1000);
  check("p-candle: the candlestick's own chunk mode", by('p-candle').prog[0].chunkMode === 'mod');
  return g;
}

function generate() {
  const recs = CASES.map(readCase);
  return { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version, W, H, cases: recs, guards: guards(recs) };
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
const bad = out1.guards.filter(x => !x.ok);
out1.guards.forEach(x => console.log('guard ' + (x.ok ? 'ok  ' : 'FAIL') + ' ' + x.name));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic || json1.includes('\\u0000')) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
