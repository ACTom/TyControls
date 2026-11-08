// Upstream's own answers for round-5 batch R5-D (2026-10-27): a brush
// cover's line style beyond fill / stroke / lineWidth / opacity, and its z.
//
//   * BrushModel's generateBrushOption: brushStyle is
//     new Model(option.brushStyle).getItemStyle() -- ITEM_STYLE_KEY_MAP, so
//     borderType becomes lineDash, borderDashOffset lineDashOffset,
//     borderCap lineCap, borderJoin lineJoin, borderMiterLimit miterLimit
//     (each only where it is not null); an area's own brushStyle (zrender
//     keys) merges over it (zrUtil.merge, overwrite)
//   * BrushController makeStyle: defaults({strokeNoScale: true}, brushStyle)
//     -- the dash is against the cover's own width
//   * updateZ: every element of a cover gets z = brushOption.z (COVER_Z
//     10000 when null) and z2 the same, so a small z puts the cover under
//     the series
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
// ECHARTS_DIST) in node, SVG renderer, ssr then chart._ssr = false, the
// clock of brush-cover.js (Date and setTimeout replaced). A cover is laid
// down by the `brush` action (pixel ranges, the global panel) or drawn by a
// drag after takeGlobalCursor.
//
//   node tools/advchart-oracle/brush-style.js
//
// writes tests/fixtures/advchart-brush-style.json (ORACLE_OUT overrides).
//
// Per case: id, note, option, steps[] {op ('action' | 'drag'), payload |
// points, record}: record {covers [{style {fill, stroke, lineWidth, opacity,
// lineDash, lineDashOffset, lineCap, lineJoin, miterLimit} (as the main
// shape's style holds them; absent keys null), strokeNoScale, z, z2,
// below (how many series data elements come after it in the display list:
// 0 when it is on top)}], events [the brush events' areas' brushStyle],
// option (getOption().brush[0].brushStyle)}.
'use strict';
const fs = require('fs');
const path = require('path');

const RealDate = Date;
const CLOCK0 = 1700000000000;
let NOW = CLOCK0;
class FakeDate extends RealDate {
  constructor(...a) {
    if (a.length) super(...a);
    else super(NOW);
  }
  static now() { return NOW; }
}
global.Date = FakeDate;
let TIMERS = [];
let timerSeq = 0;
global.setTimeout = function (fn, ms) {
  const id = ++timerSeq;
  TIMERS.push({ id, due: NOW + (+ms || 0), fn });
  return id;
};
global.clearTimeout = function (id) {
  TIMERS = TIMERS.filter(t => t.id !== id);
};
function advanceClock(to) {
  for (;;) {
    let best = null;
    for (const t of TIMERS) if (t.due <= to && (!best || t.due < best.due || (t.due === best.due && t.id < best.id))) best = t;
    if (!best) break;
    TIMERS = TIMERS.filter(t => t !== best);
    if (best.due > NOW) NOW = best.due;
    best.fn();
  }
  NOW = to;
}

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-brush-style.json');
const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const clone = v => JSON.parse(JSON.stringify(v));
const val = v => (v === undefined ? null : v);

function newChart() {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  chart._ssr = false;
  return chart;
}
function frame(chart) {
  chart._onframe();
  chart.renderToSVGString();
}
function rawEvent(type, x, y) {
  return {
    type, zrX: x, zrY: y, which: 1, shiftKey: false, ctrlKey: false, altKey: false, cancelBubble: false,
    preventDefault() {}, stopPropagation() {},
  };
}
function brushController(chart) {
  const m = chart.getModel().getComponent('brush', 0);
  const v = m && chart.getViewOfComponentModel(m);
  return v && v._brushController;
}
function isSeriesEl(el) {
  for (let e = el; e; e = e.parent) {
    const k = Object.keys(e).find(n => /^__ec_inner_\d+$/.test(n) && e[n] && 'dataIndex' in e[n]);
    if (k && e[k].dataIndex != null) return true;
  }
  return false;
}
function record(chart, events) {
  const bc = brushController(chart);
  const list = chart.getZr().storage.getDisplayList(true);
  const covers = (bc ? bc._covers : []).map(cover => {
    const main = cover.childOfName('main');
    const s = main.style;
    const at = list.indexOf(main);
    let below = 0;
    for (let i = at + 1; i < list.length; i++) if (isSeriesEl(list[i])) below++;
    return {
      style: {
        fill: val(s.fill), stroke: val(s.stroke), lineWidth: val(s.lineWidth), opacity: val(s.opacity),
        lineDash: val(s.lineDash), lineDashOffset: val(s.lineDashOffset), lineCap: val(s.lineCap),
        lineJoin: val(s.lineJoin), miterLimit: val(s.miterLimit),
      },
      strokeNoScale: !!s.strokeNoScale, z: main.z, z2: main.z2, below,
    };
  });
  const bo = chart.getOption().brush;
  return { covers, events: events.slice(), option: bo && bo[0] ? clone(bo[0].brushStyle) : null };
}

const BAR = { animation: false, xAxis: { type: 'category', data: ['a', 'b', 'c', 'd'] }, yAxis: { max: 10 },
  series: [{ type: 'bar', data: [3, 9, 6, 8], barWidth: '60%' }] };
const CASES = [
  {
    id: 'words', note: 'borderType dashed with an offset, a round cap, a bevel join and a miter limit on the component; a cover laid '
      + 'down by the action; a second area with a dotted word of its own (zrender keys) over it',
    option: Object.assign({}, BAR, { brush: { brushStyle: { borderWidth: 2, borderColor: '#cc0000', color: 'rgba(0,0,255,0.2)',
      borderType: 'dashed', borderDashOffset: 3, borderCap: 'round', borderJoin: 'bevel', borderMiterLimit: 4 } } }),
    steps: [
      { op: 'action', payload: { type: 'brush', areas: [{ brushType: 'rect', range: [[120, 260], [80, 200]] },
        { brushType: 'rect', range: [[300, 420], [150, 300]], brushStyle: { lineDash: 'dotted', lineWidth: 3 } }] } },
    ],
  },
  {
    id: 'lists', note: 'borderType a list and a number; the area-level lineDash a list over the component\'s word',
    option: Object.assign({}, BAR, { brush: { brushStyle: { borderWidth: 1, borderType: [6, 3] } } }),
    steps: [
      { op: 'action', payload: { type: 'brush', areas: [{ brushType: 'rect', range: [[120, 260], [80, 200]] },
        { brushType: 'polygon', range: [[300, 150], [420, 150], [360, 300]], brushStyle: { lineDash: 5, lineDashOffset: 2 } }] } },
    ],
  },
  {
    id: 'solid', note: 'borderType solid and a null: nothing to dash',
    option: Object.assign({}, BAR, { brush: { brushStyle: { borderWidth: 2, borderType: 'solid', borderCap: null } } }),
    steps: [
      { op: 'action', payload: { type: 'brush', areas: [{ brushType: 'lineX', range: [150, 300] }] } },
    ],
  },
  {
    id: 'drag', note: 'a cover drawn by a drag after takeGlobalCursor takes the style of the component',
    option: Object.assign({}, BAR, { brush: { brushStyle: { borderType: 'dashed', borderJoin: 'round' } } }),
    steps: [
      { op: 'action', payload: { type: 'takeGlobalCursor', key: 'brush', brushOption: { brushType: 'rect', brushMode: 'single' } } },
      { op: 'drag', points: [[150, 100], [250, 180], [320, 250]] },
    ],
  },
  {
    id: 'z-low', note: 'brush z 1: the cover is under the bars (z 2); z2 follows z',
    option: Object.assign({}, BAR, { brush: { z: 1 } }),
    steps: [
      { op: 'action', payload: { type: 'brush', areas: [{ brushType: 'rect', range: [[100, 500], [60, 330]] }] } },
    ],
  },
  {
    id: 'z-area', note: 'an area\'s own z over the component\'s',
    option: Object.assign({}, BAR, { brush: {} }),
    steps: [
      { op: 'action', payload: { type: 'brush', areas: [{ brushType: 'rect', range: [[100, 500], [60, 330]], z: 1 },
        { brushType: 'rect', range: [[150, 450], [100, 300]] }] } },
    ],
  },
  {
    // [R7-AC] new Model(option.brushStyle) has no parent: the root's brushStyle (and its top-level
    // border keys) reach no cover
    id: 'root-none', note: 'the option root\'s brushStyle and its top-level border keys: a cover takes none of them',
    option: Object.assign({}, BAR, { brushStyle: { borderType: 'dotted', borderCap: 'square', borderJoin: 'round',
      borderMiterLimit: 3, borderDashOffset: 2, borderWidth: 5, opacity: 0.5 }, borderType: 'dashed', borderCap: 'round',
      brush: { brushStyle: { borderWidth: 1, borderColor: '#00aa00' } } }),
    steps: [
      { op: 'action', payload: { type: 'brush', areas: [{ brushType: 'rect', range: [[120, 260], [80, 200]] }] } },
    ],
  },
];

function runCase(def) {
  NOW = CLOCK0;
  TIMERS = [];
  const chart = newChart();
  const events = [];
  try {
    chart.setOption(clone(def.option));
    frame(chart);
    chart.on('brush', e => events.push((e.areas || []).map(a => clone(a.brushStyle === undefined ? null : a.brushStyle))));
    const steps = [];
    for (const st of def.steps) {
      events.length = 0;
      const rec = { op: st.op };
      if (st.op === 'action') {
        rec.payload = st.payload;
        chart.dispatchAction(clone(st.payload));
      } else if (st.op === 'drag') {
        rec.points = st.points;
        const hd = chart.getZr().handler;
        const p = st.points;
        advanceClock(NOW + 200);
        hd.mousemove(rawEvent('mousemove', p[0][0], p[0][1]));
        hd.mousedown(rawEvent('mousedown', p[0][0], p[0][1]));
        for (let k = 1; k < p.length; k++) {
          advanceClock(NOW + 200);
          hd.mousemove(rawEvent('mousemove', p[k][0], p[k][1]));
        }
        advanceClock(NOW + 200);
        hd.mouseup(rawEvent('mouseup', p[p.length - 1][0], p[p.length - 1][1]));
      } else throw new OracleError('op ' + st.op);
      advanceClock(NOW + 1000);
      frame(chart);
      rec.record = record(chart, events);
      steps.push(rec);
    }
    return { id: def.id, note: def.note, option: def.option, steps };
  } finally {
    chart.dispose();
  }
}

function anchors(cases) {
  const guards = [];
  const guard = (id, ok, what) => guards.push({ id, ok: !!ok, what });
  const cs = id => cases.find(c => c.id === id);
  const cov = (id, k, i) => cs(id).steps[k].record.covers[i];
  guard('words-dash', cov('words', 0, 0).style.lineDash === 'dashed' && cov('words', 0, 0).style.lineDashOffset === 3
    && cov('words', 0, 0).style.lineCap === 'round' && cov('words', 0, 0).style.lineJoin === 'bevel' && cov('words', 0, 0).style.miterLimit === 4,
  'getItemStyle maps the border keys');
  guard('words-area', cov('words', 0, 1).style.lineDash === 'dotted' && cov('words', 0, 1).style.lineWidth === 3, 'the area\'s own keys win');
  guard('no-scale', cov('words', 0, 0).strokeNoScale, 'strokeNoScale');
  guard('lists', Array.isArray(cov('lists', 0, 0).style.lineDash) && cov('lists', 0, 1).style.lineDash === 5, 'a list and a number');
  guard('solid', cov('solid', 0, 0).style.lineDash === 'solid' && cov('solid', 0, 0).style.lineCap === 'butt', 'solid as written, a null left out (the default butt)');
  guard('drag', cov('drag', 1, 0).style.lineDash === 'dashed' && cov('drag', 1, 0).style.lineJoin === 'round', 'a drawn cover takes the style');
  guard('z-low', cov('z-low', 0, 0).z === 1 && cov('z-low', 0, 0).z2 === 1 && cov('z-low', 0, 0).below > 0, 'under the bars');
  guard('z-area', cov('z-area', 0, 0).z === 1 && cov('z-area', 0, 1).z === 10000 && cov('z-area', 0, 1).below === 0, 'an area\'s z');
  return guards;
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));
let g1;
let json1;
let json2;
let guards;
try {
  g1 = CASES.map(runCase);
  guards = anchors(g1);
  const out = { source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version, W, H, cases: g1, guards };
  json1 = JSON.stringify(out, null, 1) + '\n';
  must(json1.indexOf('\\u0000') < 0, 'a NUL');
  JSON.parse(json1);
  const g2 = CASES.map(runCase);
  json2 = JSON.stringify(Object.assign({}, out, { cases: g2, guards: anchors(g2) }), null, 1) + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
if (process.env.ORACLE_DUMP) fs.writeFileSync(process.env.ORACLE_DUMP, json1);
const bad = guards.filter(gd => !gd.ok);
guards.forEach(gd => console.log('guard ' + (gd.ok ? 'ok  ' : 'FAIL') + ' ' + gd.id + ': ' + gd.what));
const deterministic = json1 === json2;
console.log(g1.length + ' cases; ' + (guards.length - bad.length) + '/' + guards.length + ' guards; two generations '
  + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes; ' + logged.length + ' console messages'
  + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
