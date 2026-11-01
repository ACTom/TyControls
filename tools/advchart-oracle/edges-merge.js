/*
Upstream's own answers for fix batch R5-G (spec section 244), the merge side:
THE MARKER COMPONENTS' MODELS A SERIES' MARKERS MAKE. component/marker/
installMarkPoint.ts (and the markLine, markArea twins) register a
preprocessor `if (checkMarkerInSeries(opt.series, 'markPoint')) opt.markPoint
= opt.markPoint || {}`: every option that is preprocessed (the base option,
each timeline frame, each media unit with a query -- OptionManager's
parseRawOption -- with a series, a single object or a list, of which one item
writes a truthy marker) gets the root component, so the GlobalModel builds a
markPoint / markLine / markArea model for it ('\0' + name + '\0' + index ids,
as makeIdAndName gives a model nobody named). The port's keys hold the models
the preprocessors make (PreprocessorModels: grid, axisPointer); these three
were missing (spec 231a).

Each case runs its steps (setOption with notMerge or not, a timelineChange,
a resize for media) on a fresh chart and, after each, records every slot of
the three main types (and of grid and axisPointer, the other two
preprocessor models): null for a hole, else {id, name, sub}.

  node tools/advchart-oracle/edges-merge.js

writes tests/fixtures/advchart-edges-merge.json (ORACLE_OUT overrides).
Two generations byte-identical; ends with process.exit().
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

global.setTimeout = function () { return 0; };
global.clearTimeout = function () {};

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-edges-merge.json');

class OracleError extends Error {}
function must(c, msg) { if (!c) throw new OracleError(msg); }
const clone = v => JSON.parse(JSON.stringify(v));

const TYPES = ['markPoint', 'markLine', 'markArea', 'grid', 'axisPointer'];

function mk(W, H) {
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}
function models(chart) {
  const r = {};
  for (const mt of TYPES) {
    const arr = chart.getModel()._componentsMap.get(mt);
    r[mt] = arr ? arr.map(m => (m ? { id: m.id, name: m.name, sub: m.subType || '' } : null)) : [];
  }
  return r;
}

const X = { type: 'category', data: ['a', 'b', 'c'] };
const Y = { type: 'value' };
const MP = { data: [{ type: 'max' }] };
const ML = { data: [{ type: 'average' }] };
const MA = { data: [[{ xAxis: 'a' }, { xAxis: 'b' }]] };

const CASES = [
  {
    id: 'init',
    note: 'a line writes a markPoint, a bar a markLine: two root models; no markArea',
    steps: [{ set: { animation: false, xAxis: X, yAxis: Y,
      series: [{ type: 'line', data: [1, 3, 2], markPoint: MP }, { type: 'bar', data: [2, 1, 3], markLine: ML }] } }],
  },
  {
    id: 'root-written',
    note: "a root markPoint the author wrote is kept (truthy); a root markLine of null is `null || {}`; a markArea written as an empty list -- truthy -- is kept and makes no model",
    steps: [{ set: { animation: false, xAxis: X, yAxis: Y, markPoint: { label: { show: false } }, markLine: null, markArea: [],
      series: [{ type: 'line', data: [1, 3, 2], markPoint: MP, markLine: ML, markArea: MA }] } }],
  },
  {
    id: 'falsy',
    note: 'a series marker of null, false, 0 or an empty string makes no model; an empty object is truthy',
    steps: [{ set: { animation: false, xAxis: X, yAxis: Y,
      series: [{ type: 'line', data: [1, 3, 2], markPoint: null, markLine: false },
        { type: 'line', data: [1, 3, 2], markPoint: 0, markLine: '', markArea: {} }] } }],
  },
  {
    id: 'single-series',
    note: 'the series written as one object, not a list',
    steps: [{ set: { animation: false, xAxis: X, yAxis: Y, series: { type: 'bar', data: [1, 2, 3], markArea: MA } } }],
  },
  {
    id: 'merge',
    note: 'no markers first; a merge brings a series with a markLine (the model made then); a merge with no series keeps it; notMerge without markers drops every marker model',
    steps: [{ set: { animation: false, xAxis: X, yAxis: Y, series: [{ type: 'line', data: [1, 3, 2] }] } },
      { set: { series: [{ markLine: ML }] } },
      { set: { title: { text: 't' } } },
      { set: { animation: false, xAxis: X, yAxis: Y, series: [{ type: 'line', data: [1, 3, 2] }] }, notMerge: true }],
  },
  {
    id: 'frames',
    note: 'a timeline: the base option has no marker, the first frame a markPoint, the second a markArea -- every frame is preprocessed',
    steps: [{ set: { baseOption: { animation: false, timeline: { data: ['f0', 'f1'], show: false }, xAxis: X, yAxis: Y,
      series: [{ type: 'line', data: [1, 3, 2] }] },
    options: [{ series: [{ markPoint: MP }] }, { series: [{ markArea: MA }] }] } },
    { action: { type: 'timelineChange', currentIndex: 1 } }],
  },
  {
    id: 'media',
    note: 'media: a unit with a query that holds while the chart is narrow writes a markLine; the default unit (no query, never preprocessed) a markPoint',
    W: 400,
    steps: [{ set: { baseOption: { animation: false, xAxis: X, yAxis: Y, series: [{ type: 'line', data: [1, 3, 2] }] },
      media: [{ query: { maxWidth: 500 }, option: { series: [{ markLine: ML }] } }, { option: { series: [{ markPoint: MP }] } }] } }],
  },
];

function runCase(c) {
  const W = c.W || 600;
  const H = 400;
  const chart = mk(W, H);
  const states = [];
  try {
    for (const st of c.steps) {
      if (st.set) chart.setOption(clone(st.set), !!st.notMerge);
      else if (st.action) chart.dispatchAction(clone(st.action));
      else throw new OracleError(c.id + ': an unknown step');
      chart.getZr().storage.getDisplayList(true);
      states.push(models(chart));
    }
  } finally {
    chart.dispose();
  }
  return { id: c.id, note: c.note, W, H, steps: c.steps, states };
}

function guards(out) {
  const g = [];
  const C = id => out.find(c => c.id === id);
  const add = (id, ok, detail) => g.push({ id, ok: !!ok, detail });
  let s = C('init').states[0];
  add('init-two', s.markPoint.length === 1 && s.markLine.length === 1 && s.markArea.length === 0, 'a model per marker type a series writes');
  add('init-id', s.markPoint[0].id === s.grid[0].id && s.markPoint[0].name === s.grid[0].name,
    "the id and name makeIdAndName gives a preprocessor's model, the same as the grid preprocessor's");
  s = C('falsy').states[0];
  add('falsy', s.markPoint.length === 0 && s.markLine.length === 0 && s.markArea.length === 1, 'falsy markers make no model; {} does');
  s = C('merge').states;
  add('merge', s[0].markLine.length === 0 && s[1].markLine.length === 1 && s[2].markLine.length === 1 && s[3].markLine.length === 0,
    'made at the merge that brings it, kept, dropped by notMerge');
  s = C('frames').states;
  add('frames', s[0].markPoint.length === 1 && s[1].markArea.length === 1, 'every frame is preprocessed');
  s = C('media').states[0];
  add('media', s.markLine.length === 1, 'a media unit with a query is preprocessed');
  return g;
}

function generate() {
  const out = CASES.map(runCase);
  const g = guards(out);
  const doc = {
    source: 'tools/advchart-oracle/edges-merge.js against ' + path.basename(DIST) + ' (ECharts ' + echarts.version + ')',
    notes: ['A state per step: every slot of markPoint, markLine, markArea, grid and axisPointer (null a hole, else {id, name, sub}).'],
    cases: out,
    guards: g,
  };
  return { doc, bad: g.filter(x => !x.ok) };
}

try {
  const a = generate();
  if (a.bad.length) {
    for (const b of a.bad) console.error('GUARD FAILED: ' + b.id + ' -- ' + b.detail);
    process.exit(1);
  }
  const textA = JSON.stringify(a.doc, null, 1);
  const textB = JSON.stringify(generate().doc, null, 1);
  must(textA === textB, 'two generations differ');
  fs.writeFileSync(OUT, textA + '\n');
  console.log('wrote ' + OUT + ': ' + a.doc.cases.length + ' cases, ' + a.doc.guards.length + ' guards');
  process.exit(0);
} catch (e) {
  console.error(e instanceof OracleError ? 'ORACLE: ' + e.message : e.stack);
  process.exit(1);
}
