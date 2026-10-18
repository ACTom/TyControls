/*
Upstream's own answers for the fix phase's P2: WHICH NAMES ARE THE SAME NAME.

Upstream keys names by JavaScript string identity -- a plain object or a
HashMap whose keys are the UTF-16 code units. SeriesData.makeIdFromName
counts a name's repeats in `_nameRepeatCount = {}` (the second 'x' is
'x__ec__2'); OrdinalMeta.parseAndCollect interns a category in a
createHashMap. Two names that differ in any code unit are two names, however
alike a locale's collation finds them: U+00C5 (A with ring above) and U+212B
(the Angstrom sign) are canonically equivalent, U+FEFF and U+00AD are
ignorable -- and the Windows locale compare the port's sorted string lists
used took each pair as equal from the first code point they differed in,
whatever came after it.

Two kinds of case:
  hier      a treemap or a sunburst; every row's data.getId(i) (the tree's
            pre-order, the root first, named after the series)
  category  a category axis that collects its categories from the series'
            data; the axis' ordinal meta categories in order, and every
            series' x ordinal per row (data.get(dim, i))

Runs the real ECharts 6.1 build (D:/Projects/echarts/dist/echarts.js, or
ECHARTS_DIST) in node, SVG renderer, ssr: true, 600 x 400, animation off,
Math.random the port's xorshift32 reseeded per chart.

  node tools/advchart-oracle/string-identity.js

writes tests/fixtures/advchart-string-identity.json (ORACLE_OUT overrides).
Ends with process.exit().

-----------------------------------------------------------------------------
Fixture:
  source, W, H, seed, notes[]
  cases[]:
    id, kind ('hier' | 'category'), note, option
    hier:      seriesType, ids[] (strings, by data index)
    category:  categories[] (strings), ordinals[][] (per series, per row)
  checks: self-checks (any failure: nothing is written, exit 1): the pairs
  the notes promise are kept apart; the fixture generated twice
  byte-identical.
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
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-string-identity.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}

const SEED = 2463534242;
let rngState = SEED;
Math.random = function () {
  let x = rngState;
  x ^= x << 13; x >>>= 0;
  x ^= x >>> 17;
  x ^= x << 5; x >>>= 0;
  rngState = x;
  return x / 4294967296;
};

function newChart() {
  rngState = SEED;
  return echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
}

// the names: pairs a locale compare takes as one
const A_RING = '\u00C5';     // LATIN CAPITAL LETTER A WITH RING ABOVE
const ANGSTROM = '\u212B';   // ANGSTROM SIGN, canonically the same letter
const BOM = '\uFEFF';        // ZERO WIDTH NO-BREAK SPACE, ignorable
const SHY = '\u00AD';        // SOFT HYPHEN, ignorable
const E_ACUTE = '\u00E9';
const E_COMB = 'e\u0301';

const HIER_DATA = [
  { name: A_RING + 'a', value: 6 },
  { name: ANGSTROM + 'b', value: 5 },
  { name: ANGSTROM + 'b', value: 4 },
  { name: BOM + 'x', value: 3, children: [{ name: SHY + 'y', value: 2 }, { name: SHY + 'y', value: 1 }] },
  { name: SHY + 'y', value: 3 },
  { name: E_ACUTE, value: 2 },
  { name: E_COMB, value: 2 },
  { name: A_RING + 'a', value: 1 },
];

function defs() {
  const d = [];
  d.push({ id: 'treemap-lookalikes', kind: 'hier', note: 'a treemap whose names a locale compare finds equal from their first differing code point: A-ring / Angstrom, BOM / soft hyphen, precomposed / combining e-acute; each is its own name, the real repeats count among their own',
    option: { animation: false, series: [{ type: 'treemap', name: 'tm', data: HIER_DATA }] } });
  d.push({ id: 'sunburst-lookalikes', kind: 'hier', note: 'the same names in a sunburst',
    option: { animation: false, series: [{ type: 'sunburst', name: 'sb', data: HIER_DATA }] } });
  d.push({ id: 'treemap-root-named-alike', kind: 'hier', note: "the series named A-ring 'a', a child named Angstrom 'a' and one named A-ring 'a': the root's name counts too (the child named as the root is its second)",
    option: { animation: false, series: [{ type: 'treemap', name: A_RING + 'a', data: [{ name: ANGSTROM + 'a', value: 2 }, { name: A_RING + 'a', value: 1 }] }] } });
  d.push({ id: 'category-lookalikes', kind: 'category', note: 'a collecting category axis: the names each their own category, in the order the data brings them',
    option: { animation: false, xAxis: { type: 'category' }, yAxis: {}, series: [
      { type: 'bar', data: [[A_RING + 'a', 3], [ANGSTROM + 'b', 5], [BOM + 'x', 2], [SHY + 'y', 4], [E_ACUTE, 1], [E_COMB, 6]] },
      { type: 'line', data: [[SHY + 'y', 1], [ANGSTROM + 'b', 2], [A_RING + 'a', 3], ['q', 4]] }] } });
  return d;
}

function runHier(def) {
  const chart = newChart();
  try {
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    const sm = chart.getModel().getSeriesByIndex(0);
    const data = sm.getData();
    const ids = [];
    for (let i = 0; i < data.count(); i++) ids.push(data.getId(i));
    return { id: def.id, kind: def.kind, note: def.note, option: def.option, seriesType: sm.subType, ids };
  } finally {
    chart.dispose();
  }
}

function runCategory(def) {
  const chart = newChart();
  try {
    chart.setOption(JSON.parse(JSON.stringify(def.option)));
    const axis = chart.getModel().getComponent('xAxis', 0).axis;
    const categories = axis.scale.getOrdinalMeta().categories.slice();
    const ordinals = [];
    chart.getModel().eachSeries(sm => {
      const data = sm.getData();
      const dim = data.mapDimension('x');
      const row = [];
      for (let i = 0; i < data.count(); i++) row.push(data.get(dim, i));
      ordinals.push(row);
    });
    return { id: def.id, kind: def.kind, note: def.note, option: def.option, categories, ordinals };
  } finally {
    chart.dispose();
  }
}

function generate() {
  return defs().map(def => (def.kind === 'hier' ? runHier(def) : runCategory(def)));
}

function check(cases) {
  let n = 0;
  const C = id => cases.find(c => c.id === id);
  for (const id of ['treemap-lookalikes', 'sunburst-lookalikes']) {
    const ids = C(id).ids;
    must(ids.length === 11, id + ': 11 rows');
    must(new Set(ids).size === ids.length, id + ': every id its own');
    must(ids.includes(A_RING + 'a') && ids.includes(ANGSTROM + 'b') && ids.includes(ANGSTROM + 'b__ec__2'), id + ': A-ring and Angstrom apart');
    must(ids.includes(A_RING + 'a__ec__2'), id + ": the second A-ring 'a' counts among its own");
    must(ids.includes(BOM + 'x') && ids.includes(SHY + 'y') && ids.includes(SHY + 'y__ec__3'), id + ': BOM and soft hyphen apart');
    must(ids.includes(E_ACUTE) && ids.includes(E_COMB), id + ': precomposed and combining apart');
    n += 6;
  }
  const r = C('treemap-root-named-alike').ids;
  must(r.join('|') === [A_RING + 'a', ANGSTROM + 'a', A_RING + 'a__ec__2'].join('|'), 'root-named-alike: ' + r.join('|'));
  n++;
  const cat = C('category-lookalikes');
  must(cat.categories.length === 7, 'category: seven categories, got ' + cat.categories.length);
  must(cat.ordinals[0].join() === '0,1,2,3,4,5' && cat.ordinals[1].join() === '3,1,0,6', 'category: the ordinals ' + JSON.stringify(cat.ordinals));
  n += 2;
  return n;
}

function oneLine(v) { return JSON.stringify(v); }
function fmt(v, ind) {
  if (Array.isArray(v)) {
    if (v.every(x => x === null || typeof x !== 'object' || (Array.isArray(x) && x.every(y => typeof y !== 'object')))) return oneLine(v);
    return '[\n' + v.map(x => ind + '  ' + fmt(x, ind + '  ')).join(',\n') + '\n' + ind + ']';
  }
  if (v && typeof v === 'object') {
    const ks = Object.keys(v);
    if (ks.length === 0) return '{}';
    if (ks.every(k => v[k] === null || typeof v[k] !== 'object')) return oneLine(v);
    return '{\n' + ks.map(k => ind + '  ' + JSON.stringify(k) + ': ' + (k === 'option' ? oneLine(v[k]) : fmt(v[k], ind + '  '))).join(',\n') + '\n' + ind + '}';
  }
  return JSON.stringify(v);
}

const quiet = { error: console.error, warn: console.warn };
const logged = [];
console.error = (...a) => logged.push(a.join(' '));
console.warn = (...a) => logged.push(a.join(' '));

let json1;
let json2;
let checked = 0;
let cases1;
try {
  cases1 = generate();
  checked = check(cases1);
  const out = {
    source: 'ECharts ' + echarts.version + ', zrender ' + echarts.zrender.version + '; node ' + process.version,
    W, H, seed: SEED,
    notes: [
      'Names are JavaScript strings: two names are one only when every UTF-16 code unit agrees. SeriesData.makeIdFromName counts repeats in a plain object (`_nameRepeatCount[name] = (... || 0) + 1`, the second is name + \'__ec__2\'); OrdinalMeta.parseAndCollect interns categories in a createHashMap.',
      'The JSON escapes every non-ASCII code unit (\\uXXXX), so the fixture reads back the same code units on any platform.',
    ],
    cases: cases1,
    checks: { expectations: checked },
  };
  json1 = fmt(out, '') + '\n';
  must(JSON.stringify(JSON.parse(json1)) === JSON.stringify(out), 'the written JSON does not parse back');
  const cases2 = generate();
  check(cases2);
  json2 = fmt(Object.assign({}, out, { cases: cases2 }), '') + '\n';
} catch (e) {
  console.error = quiet.error;
  console.warn = quiet.warn;
  console.log(e instanceof OracleError ? 'self-check failed: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
console.error = quiet.error;
console.warn = quiet.warn;
// every non-ASCII code unit escaped: the file is ASCII
json1 = json1.replace(/[\u0080-\uffff]/g, ch => '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
json2 = json2.replace(/[\u0080-\uffff]/g, ch => '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
const deterministic = json1 === json2;
console.log(cases1.length + ' cases; ' + checked + ' expectations; two generations ' + (deterministic ? 'identical' : 'DIFFERENT') + '; '
  + json1.length + ' bytes; ' + logged.length + ' console messages' + (logged.length ? ': ' + Array.from(new Set(logged.map(l => l.split('\n')[0]))).slice(0, 5).join(' | ') : ''));
if (!deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
