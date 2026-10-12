/*
Upstream's own answers for DATASET TRANSFORMS -- roadmap D2, batch 133: the
transform registry (data/helper/transform.ts: registerExternalTransform,
applyDataTransform, applySingleDataTransform, createExternalSource), the
built-in 'filter' (component/transform/filterTransform.ts) with its
condition language (util/conditionalExpression.ts: and / or / not, the
relational operators and their aliases, `parser`), the built-in 'sort'
(component/transform/sortTransform.ts, SortOrderComparator), the value
rules both share (data/helper/dataValueHelper.ts: parseDataValue,
getRawValueParser, createFilterComparator), and the chain of datasets
(data/helper/sourceManager.ts: fromDatasetIndex / fromDatasetId, a piped
`transform`, several results, fromTransformResult and the getSource
fallback to the upstream).

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, 600 x 400,
`animation: false`, TZ=UTC, Math.random 0. Three transforms of the test's
own are registered through echarts.registerTransform, so the registry's
external path (no getRawDataItem, inherited headers, several results) is
held too; the Pascal suite registers the same three.

  node tools/advchart-oracle/dataset-transform.js

writes tests/fixtures/advchart-dataset-transform.json (ORACLE_OUT
overrides).

-----------------------------------------------------------------------------
Numbers are the 16 hex digits of the IEEE double (big-endian, lowercase);
counts, flags, strings and option values are plain JSON.

Top level: source, version, W, H, notes[], cases[], guards[].

A case: id, group, note, option (as run), deviation (absent, or the name of
  a rule the port does not follow -- 'reg'), and
  datasets[] one per dataset, in order, after prepareSource() was called on
    each in turn (dataset k's call prepares its upstream first):
      {k, error: the message upstream threw | null,
       results[]: SourceManager._sourceList, each
         {r, format ('arrayRows' | 'objectRows' | ...), clone (the source
          carries no metaRawOption -- a fromTransformResult copy),
          startIndex, dims (dimensionsDefine names, null for an unnamed
          one) | null (none defined), detected (dimensionsDetectedCount
          | null), rows}}
      A cell: a number its hex, a string 's:' + it, a boolean 'b:true' /
      'b:false', null null, anything else 'j:' + its JSON. A row: an array
      of cells, an object row {o: [[key, cell], ...]} in key order, null.
  optionError (an error case whose setOption itself threw): the message; no
    datasets then.
  render (cases with series; setOption threw -> {error}): rect (grid 0's
    [x, y, w, h] hex | null), axes[] {dim, index, categories (the ordinal
    meta's, in order) | null}, series[] {index, type, count (data.count()),
    items[] (bar: [x, y, w, h] of the item layout; line / scatter: the
    point dataToPoint gives the stored values; pie: [cx, cy, r0, r,
    startAngle, endAngle] of the item layout; null for no layout),
    labels[] {d, text} (every element of the series view carrying a text,
    in the view's traversal order)}.

Guards (any failure: nothing is written, exit 1): expectations read off
the source -- see guards(); and the whole fixture is generated twice
(byte-identical). process.exit() ends the run.
*/
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-dataset-transform.json');

const W = 600;
const H = 400;

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
Math.random = function () { return 0; };

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
function num(h) {
  bits.setUint32(0, parseInt(h.slice(0, 8), 16));
  bits.setUint32(4, parseInt(h.slice(8), 16));
  return bits.getFloat64(0);
}
const clone = v => (v === undefined ? undefined : JSON.parse(JSON.stringify(v)));

// ---------------------------------------------------------------------------
// the test's own transforms (the Pascal suite registers the same three)
// ---------------------------------------------------------------------------
// 'test:scale': every number of every row times config.k, read through
// retrieveValue (an external transform has no getRawDataItem); no
// `dimensions`, so result 0 inherits the upstream's header and names.
echarts.registerTransform({
  type: 'test:scale',
  transform(params) {
    const up = params.upstream;
    const k = params.config.k;
    const dims = up.cloneAllDimensionInfo();
    const data = [];
    for (let i = 0; i < up.count(); i++) {
      data.push(dims.map(d => {
        const v = up.retrieveValue(i, d.index);
        return typeof v === 'number' ? v * k : v;
      }));
    }
    return { data };
  },
});
// 'test:pairs': two results -- [name, value] rows of two named dimensions,
// and, unnamed, a line of two words and a line with the count (a copy of it
// guesses the words to be a header).
echarts.registerTransform({
  type: 'test:pairs',
  transform(params) {
    const up = params.upstream;
    const nameDim = up.getDimensionInfo(params.config.name).index;
    const valueDim = up.getDimensionInfo(params.config.value).index;
    const data = [];
    for (let i = 0; i < up.count(); i++) data.push([up.retrieveValue(i, nameDim), up.retrieveValue(i, valueDim)]);
    return [{ dimensions: ['name', 'value'], data }, { data: [['rows', 'of'], ['count', up.count()]] }];
  },
});
// 'test:raw' asks for a raw item, which only a built-in may.
echarts.registerTransform({
  type: 'test:raw',
  transform(params) {
    return { data: [params.upstream.getRawDataItem(0)] };
  },
});

// ---------------------------------------------------------------------------
// recording
// ---------------------------------------------------------------------------
function cellOut(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return hex(v);
  if (typeof v === 'string') return 's:' + v;
  if (typeof v === 'boolean') return 'b:' + v;
  return 'j:' + JSON.stringify(v);
}
function rowOut(row) {
  if (row === null || row === undefined) return null;
  if (Array.isArray(row)) return row.map(cellOut);
  if (typeof row === 'object') return { o: Object.keys(row).map(k => [k, cellOut(row[k])]) };
  return cellOut(row);
}
function sourceOut(src, r) {
  must(Array.isArray(src.data) || (src.data && typeof src.data === 'object'), 'a source with no data');
  return {
    r,
    format: src.sourceFormat,
    clone: src.metaRawOption === undefined,
    startIndex: src.startIndex,
    dims: src.dimensionsDefine ? src.dimensionsDefine.map(d => (d.name == null ? null : d.name)) : null,
    detected: src.dimensionsDetectedCount == null ? null : src.dimensionsDetectedCount,
    rows: Array.isArray(src.data) ? src.data.map(rowOut) : null,
  };
}
function datasetsOut(chart) {
  const out = [];
  const m = chart.getModel();
  let n = 0;
  m.eachComponent('dataset', () => { n++; });
  for (let k = 0; k < n; k++) {
    const mgr = m.getComponent('dataset', k).getSourceManager();
    const rec = { k, error: null, results: [] };
    try {
      mgr.prepareSource();
      const list = mgr._sourceList;
      for (let r = 0; r < list.length; r++) {
        if (list[r]) rec.results.push(sourceOut(list[r], r));
      }
    } catch (e) {
      rec.error = e instanceof RangeError ? 'RangeError' : String(e.message);
    }
    out.push(rec);
  }
  return out;
}

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
function dataIndexOf(el) {
  for (let e = el; e; e = e.parent) {
    const d = ecData(e);
    if (d && d.dataIndex != null) return d.dataIndex;
  }
  return null;
}

function seriesOut(chart, s) {
  const data = s.getData();
  const items = [];
  if (s.subType === 'line' || s.subType === 'scatter') {
    const cs = s.coordinateSystem;
    const dims = cs.dimensions.map(d => data.mapDimension(d));
    const store = data.getStore();
    for (let i = 0; i < data.count(); i++) {
      const p = cs.dataToPoint([store.get(data.getDimensionIndex(dims[0]), i),
        store.get(data.getDimensionIndex(dims[1]), i)], null, []);
      items.push([hex(p[0]), hex(p[1])]);
    }
  } else {
    for (let i = 0; i < data.count(); i++) {
      const l = data.getItemLayout(i);
      if (l == null) items.push(null);
      else if (s.subType === 'pie') items.push([l.cx, l.cy, l.r0, l.r, l.startAngle, l.endAngle].map(hex));
      else if (l.width != null) items.push([hex(l.x), hex(l.y), hex(l.width), hex(l.height)]);
      else items.push(null);
    }
  }
  const labels = [];
  const view = chart.getViewOfSeriesModel(s);
  view.group.traverse(el => {
    if (el.ignore) return true;
    const t = el.getTextContent && el.getTextContent();
    if (!t || t.ignore) return;
    labels.push({ d: dataIndexOf(el), text: String(t.style.text) });
  });
  return { index: s.seriesIndex, type: s.subType, count: data.count(), items, labels };
}
function renderOut(chart) {
  const m = chart.getModel();
  const g = m.getComponent('grid', 0);
  const rect = g && g.coordinateSystem ? g.coordinateSystem.getRect() : null;
  const out = { rect: rect ? [rect.x, rect.y, rect.width, rect.height].map(hex) : null, axes: [], series: [] };
  for (const dim of ['x', 'y']) {
    m.eachComponent(dim + 'Axis', (comp, index) => {
      const ax = comp.axis;
      const meta = ax && ax.scale.getOrdinalMeta ? ax.scale.getOrdinalMeta() : null;
      out.axes.push({ dim, index, categories: meta ? meta.categories.slice().map(String) : null });
    });
  }
  m.eachSeries(s => out.series.push(seriesOut(chart, s)));
  return out;
}

function runCase(c) {
  const option = clone(c.option);
  const rec = { id: c.id, group: c.group, note: c.note, option };
  if (c.deviation) rec.deviation = c.deviation;
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: W, height: H });
  try {
    let threw = null;
    try {
      chart.setOption(clone(option));
      chart.renderToSVGString();
    } catch (e) {
      threw = e instanceof RangeError ? 'RangeError' : String(e.message);
    }
    if (option.series) rec.render = threw ? { error: threw } : renderOut(chart);
    else if (threw) {
      // the option itself is refused (disableTransformOptionMerge cannot
      // mark a transform that is not an object): no model to ask
      must(c.group === 'error', c.id + ': setOption threw: ' + threw);
      rec.optionError = threw;
      return rec;
    }
    rec.datasets = datasetsOut(chart);
    return rec;
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// the tables
// ---------------------------------------------------------------------------
const HEAD = ['product', 'year', 'sales', 'price', 'tag'];
const ROWS = [
  ['Tofu', 2011, 41.1, '12', 'a'],
  ['Milk', 2012, 86.5, ' 30 ', 'b'],
  ['Cheese', 2013, 24.1, '7px', null],
  ['Walnut', 2012, 55.2, '-', 'a'],
  ['Matcha', 2014, 72.4, '0x10', 'c'],
  ['Biscuit', 2011, 53.9, 5, 'b'],
  ['Tea', '2013', 66, '1e2', 'a'],
  ['Coffee', 2015, null, '', 'B'],
  ['Juice', 2016, 33.3, 'Infinity', 'b'],
];
const TABLE = [HEAD].concat(ROWS);
const OBJ = ROWS.map(r => ({ product: r[0], year: r[1], sales: r[2], price: r[3], tag: r[4] }));
const ds = (extra) => Object.assign({ source: clone(TABLE) }, extra || {});
const filt = config => ({ type: 'filter', config });
const sort = config => ({ type: 'sort', config });
const two = (tr, root) => ({ dataset: [root || ds(), { transform: tr }] });

// a mixture for the comparator: numbers, numeric strings, words, nulls,
// booleans, infinities (as strings), deterministic
const WORDS = ['pear', 'Apple', 'fig', 'apple', '', 'zz', '\u00e9t\u00e9', '\ud83d\ude00'];
function mixture(n, seed) {
  let x = seed >>> 0;
  const rnd = () => { x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x; };
  const rows = [];
  for (let i = 0; i < n; i++) {
    const k = rnd() % 12;
    let v;
    if (k < 4) v = (rnd() % 21) - 10;
    else if (k === 4) v = String((rnd() % 9) - 4);
    else if (k === 5) v = WORDS[rnd() % WORDS.length];
    else if (k === 6) v = null;
    else if (k === 7) v = (rnd() % 2) === 0;
    else if (k === 8) v = (rnd() % 2) === 0 ? 'Infinity' : '-Infinity';
    else if (k === 9) v = (rnd() % 5) / 4;
    else if (k === 10) v = ' ' + ((rnd() % 7) - 3) + ' ';
    else v = WORDS[rnd() % 3] + (rnd() % 3);
    rows.push(['r' + i, v, rnd() % 4]);
  }
  return [['id', 'v', 'w']].concat(rows);
}
const TIMES = [
  ['when', 'n'],
  ['2012-03-04T05:00Z', 1],
  ['2013-01-01 00:00+08:00', 2],
  [1388534400000, 3],
  ['2014/02/03T00:00:00.5Z', 4],
  ['abc', 5],
  [null, 6],
  ['2016-12-31T23:59:59.999Z', 7],
  [true, 8],
  [1.4e12 + 0.5, 9],
];

const CASES = [];
function add(group, id, note, option, more) {
  CASES.push(Object.assign({ group, id, note, option: Object.assign({ animation: false }, option) }, more || {}));
}

// ---- filter: each operator, its aliases, the dimension by name and by index
add('filter', 'f-gt', 'gt on a number column; a null is NaN', two(filt({ dimension: 'sales', gt: 50 })));
add('filter', 'f-gte', 'gte 55.2 keeps the boundary', two(filt({ dimension: 'sales', gte: 55.2 })));
add('filter', 'f-lt', 'lt on numeric strings: numericToNumber', two(filt({ dimension: 'price', lt: 20 })));
add('filter', 'f-lte', 'lte, by index', two(filt({ dimension: 3, lte: 30 })));
add('filter', 'f-range', 'two operators in one condition', two(filt({ dimension: 'sales', '>': 30, '<=': 66 })));
add('filter', 'f-eq-num', 'eq 2013 meets the string 2013 (one side a number)', two(filt({ dimension: 'year', eq: 2013 })));
add('filter', 'f-eq-str', "eq '2012' meets the number 2012", two(filt({ dimension: 'year', '=': '2012' })));
add('filter', 'f-eq-strict', "eq 'a' is strict between strings", two(filt({ dimension: 'tag', value: 'a' })));
add('filter', 'f-eq-null', 'eq null meets null only', two(filt({ dimension: 'tag', eq: null })));
add('filter', 'f-eq-bool', 'eq true meets neither 1 nor "true"', two(filt({ dimension: 'year', eq: true })));
add('filter', 'f-eq-numstr', "eq 12 meets '12', ' 30 ' does not meet 30? (it does), '1e2' meets 100",
  two(filt({ or: [{ dimension: 'price', eq: 12 }, { dimension: 'price', eq: 30 }, { dimension: 'price', eq: 100 }, { dimension: 'price', eq: 16 }] })));
add('filter', 'f-ne', "ne 'a' keeps the null", two(filt({ dimension: 'tag', ne: 'a' })));
add('filter', 'f-ne-alias', "'!=' and '<>'", two(filt({ and: [{ dimension: 'tag', '!=': 'b' }, { dimension: 'tag', '<>': 'c' }] })));
add('filter', 'f-dim-numstr', "dimension '2' names no dimension: index 2", two(filt({ dimension: '2', gt: 50 })));
add('filter', 'f-dim-named', "a dimension NAMED '1': the string finds it, the number finds index 1",
  { dataset: [{ source: [['1', 'x', 'y'], [5, 10, 'p'], [6, 20, 'q'], [7, 30, 'r']] },
    { transform: filt({ dimension: '1', gt: 5 }) }, { transform: filt({ dimension: 1, gt: 15 }) }] });
add('filter', 'f-and-or-not', 'nesting',
  two(filt({ and: [{ or: [{ dimension: 'year', eq: 2011 }, { dimension: 'year', eq: 2013 }] }, { not: { dimension: 'tag', eq: 'a' } }] })));
add('filter', 'f-not-and', 'not over and',
  two(filt({ not: { and: [{ dimension: 'sales', gt: 40 }, { dimension: 'sales', lt: 70 }] } })));
add('filter', 'f-true', 'the whole condition true', two(filt(true)));
add('filter', 'f-false', 'the whole condition false', two(filt(false)));
add('filter', 'f-and-true', 'and [true], or [false, ...]',
  { dataset: [ds(), { transform: filt({ and: [true] }) }, { transform: filt({ or: [false, { dimension: 'tag', eq: 'c' }] }) }] });
add('filter', 'f-trim', "parser 'trim' on the cell and the value", two(filt({ dimension: 'price', parser: 'trim', eq: ' 30' })));
add('filter', 'f-trim2', "parser 'trim': '30' meets ' 30 '", two(filt({ dimension: 'price', parser: 'trim', eq: '30' })));
add('filter', 'f-number', "parser 'number' is parseFloat: '7px' is 7, '0x10' is 0", two(filt({ dimension: 'price', parser: 'number', gt: 6 })));
add('filter', 'f-number-eq', "parser 'number', eq '7em' is 7", two(filt({ dimension: 'price', parser: 'number', eq: '7em' })));
add('filter', 'f-unknown-parser', 'an unknown parser parses nothing', two(filt({ dimension: 'price', parser: 'xyz', eq: ' 30 ' })));
add('filter', 'f-time', "parser 'time' on both sides",
  { dataset: [{ source: clone(TIMES) }, { transform: filt({ dimension: 'when', parser: 'time', gte: '2013-01-01T00:00Z', lt: '2015-01-01T00:00:00Z' }) }] });
add('filter', 'f-time-num', "parser 'time' with a number: rounded",
  { dataset: [{ source: clone(TIMES) }, { transform: filt({ dimension: 0, parser: 'time', lte: 1400000000000.5 }) }] });
add('filter', 'f-time-eq', "parser 'time', eq a date string",
  { dataset: [{ source: clone(TIMES) }, { transform: filt({ dimension: 'when', parser: 'time', eq: '2012-03-04T13:00+08:00' }) }] });
add('filter', 'f-object-rows', 'object rows, by key', two(filt({ dimension: 'sales', gt: 50 }), { source: clone(OBJ) }));
add('filter', 'f-object-dims', 'object rows with declared dimensions (one renamed away)',
  two(filt({ dimension: 'price', gte: 5 }), { source: clone(OBJ), dimensions: ['product', 'year', 'sales', 'price'] }));
add('filter', 'f-declared', 'no header, declared dimensions: inherited as written',
  two(filt({ dimension: 'sales', lt: 50 }), { source: clone(ROWS), dimensions: ['product', { name: 'year', type: 'ordinal' }, 'sales', 'price', 'tag'] }));
add('filter', 'f-header-false', 'sourceHeader false: no names, the header line is data',
  two(filt({ dimension: 2, gt: 50 }), { source: clone(TABLE), sourceHeader: false }));
add('filter', 'f-header-2', 'sourceHeader 2: two lines carried, no names',
  two(filt({ dimension: 2, gt: 50 }), { source: clone(TABLE), sourceHeader: 2 }));
add('filter', 'f-header-word', "sourceHeader 'yes' is truthy: one header line",
  two(filt({ dimension: 'sales', gt: 50 }), { source: clone(TABLE), sourceHeader: 'yes' }));
add('filter', 'f-dup', "two dimensions called 'a': the second is 'a-1'",
  { dataset: [{ source: [['a', 'a', 'b'], [1, 2, 3], [4, 5, 6], [7, 8, 9]] }, { transform: filt({ dimension: 'a-1', gt: 4 }) }] });
add('filter', 'f-keyed', 'keyed columns: rows made of the columns, no names',
  { dataset: [{ source: { k: ['x', 'y', 'z', 'w'], v: [3, 9, 1, 7], u: [true, false, null, 'q'] } }, { transform: filt({ dimension: 'v', gte: 3 }) }] });
add('filter', 'f-null-row', 'a null row: every cell undefined',
  { dataset: [{ source: [['a', 'b'], [1, 2], null, [3, 4], [5]] }, { transform: filt({ dimension: 'b', ne: 2 }) }] });
add('filter', 'f-empty', 'an empty table', { dataset: [{ source: [] }, { transform: filt({ dimension: 0, gt: 1 }) }] });
add('filter', 'f-reg', 'reg: the port does not have it', two(filt({ dimension: 'tag', reg: '^[ab]$' })), { deviation: 'reg' });

// ---- sort
add('sort', 's-asc', 'asc: the null last (incomparable max)', two(sort({ dimension: 'sales', order: 'asc' })));
add('sort', 's-desc', 'desc: the null last (incomparable min)', two(sort({ dimension: 'sales', order: 'desc' })));
add('sort', 's-multi', 'year asc (the string 2013 numeric), then sales desc',
  two(sort([{ dimension: 'year', order: 'asc' }, { dimension: 'sales', order: 'desc' }])));
add('sort', 's-price-asc', 'numeric strings and words: words are incomparable (max), among themselves by code unit',
  two(sort({ dimension: 'price', order: 'asc' })));
add('sort', 's-price-min', "incomparable 'min' with asc", two(sort({ dimension: 'price', order: 'asc', incomparable: 'min' })));
add('sort', 's-price-max-desc', "incomparable 'max' with desc", two(sort({ dimension: 'price', order: 'desc', incomparable: 'max' })));
add('sort', 's-words', 'all words', two(sort({ dimension: 'product', order: 'desc' })));
add('sort', 's-tag', "words with a null and 'B'", two(sort({ dimension: 4, order: 'asc' })));
add('sort', 's-number', "parser 'number'", two(sort({ dimension: 'price', order: 'desc', parser: 'number' })));
add('sort', 's-trim', "parser 'trim'", two(sort({ dimension: 'price', order: 'asc', parser: 'trim' })));
add('sort', 's-time', "parser 'time'", { dataset: [{ source: clone(TIMES) }, { transform: sort({ dimension: 'when', order: 'desc', parser: 'time' }) }] });
add('sort', 's-object', 'object rows', two(sort({ dimension: 'sales', order: 'asc' }), { source: clone(OBJ) }));
add('sort', 's-mix-20', 'a mixture, 20 rows (one binary insertion)', { dataset: [{ source: mixture(20, 7) }, { transform: sort({ dimension: 'v', order: 'asc' }) }] });
add('sort', 's-mix-60', 'a mixture, 60 rows, desc, min', { dataset: [{ source: mixture(60, 11) }, { transform: sort({ dimension: 'v', order: 'desc', incomparable: 'min' }) }] });
add('sort', 's-mix-300', 'a mixture, 300 rows: runs, merges, galloping', { dataset: [{ source: mixture(300, 23) }, { transform: sort({ dimension: 'v', order: 'asc' }) }] });
add('sort', 's-mix-300-multi', '300 rows, two keys', { dataset: [{ source: mixture(300, 29) }, { transform: sort([{ dimension: 'w', order: 'desc' }, { dimension: 'v', order: 'asc', incomparable: 'min' }]) }] });
add('sort', 's-stable-200', '200 rows of few values: stable', {
  dataset: [{ source: [['i', 'v']].concat(Array.from({ length: 200 }, (_, i) => [i, (i * 7919) % 5])) },
    { transform: sort({ dimension: 'v', order: 'asc' }) }] });
add('sort', 's-runs-500', '500 rows in long runs: galloping merges', {
  dataset: [{ source: [['i', 'v']].concat(Array.from({ length: 500 }, (_, i) => [i, i < 250 ? i * 2 : (i - 250) * 2 + 1])) },
    { transform: sort({ dimension: 'v', order: 'asc' }) }] });
add('sort', 's-desc-run', 'a strictly descending start is reversed', {
  dataset: [{ source: [['v']].concat([9, 8, 7, 6, 5, 5, 4, 1, 3].map(v => [v])) }, { transform: sort({ dimension: 0, order: 'asc' }) }] });

// ---- pipes
add('pipe', 'p-filter-sort', 'filter, then sort',
  two([filt({ dimension: 'sales', gt: 30 }), sort({ dimension: 'sales', order: 'desc' })]));
add('pipe', 'p-three', 'sort, filter, sort',
  two([sort({ dimension: 'year', order: 'desc' }), filt({ dimension: 'tag', ne: 'b' }), sort({ dimension: 'product', order: 'asc' })]));
add('pipe', 'p-boxplot-filter', 'boxplot, then filter on its first result by the name it gave',
  { dataset: [{ source: [[1, 2, 3, 4, 50], [5, 6, 7, 8, 9], [2, 2, 2, 2, 2], [10, 20, 30, 40, 50]] },
    { transform: [{ type: 'boxplot' }, filt({ dimension: 'Q2', gte: 3 })] }] });
add('pipe', 'p-filter-boxplot', 'filter, then boxplot on the rows left',
  { dataset: [{ source: [[1, 2, 3, 4, 50], [5, 6, 7, 8, 9], [2, 2, 2, 2, 2], [10, 20, 30, 40, 50]] },
    { transform: [filt({ dimension: 0, gt: 1 }), { type: 'boxplot', config: { boundIQR: 'none' } }] }] });
add('pipe', 'p-single-list', 'a list of one', two([filt({ dimension: 'year', eq: 2012 })]));

// ---- chains
add('chain', 'c-index', 'fromDatasetIndex down a chain',
  { dataset: [ds(), { transform: filt({ dimension: 'sales', gt: 40 }) }, { fromDatasetIndex: 1, transform: sort({ dimension: 'sales', order: 'asc' }) }] });
add('chain', 'c-id', 'fromDatasetId',
  { dataset: [{ source: [[0, 0]] }, ds({ id: 'raw' }), { fromDatasetId: 'raw', transform: filt({ dimension: 'tag', eq: 'b' }) }] });
add('chain', 'c-id-number', 'a numeric id meets its string',
  { dataset: [{ source: [[0, 0]] }, ds({ id: 5 }), { fromDatasetId: '5', transform: filt({ dimension: 'tag', eq: 'c' }) }] });
add('chain', 'c-index-beats-id', 'index and id: the index',
  { dataset: [ds(), { id: 'other', source: [['a', 'sales'], ['q', 1000]] }, { fromDatasetIndex: 0, fromDatasetId: 'other', transform: filt({ dimension: 'sales', gt: 70 }) }] });
add('chain', 'c-index-list', 'two upstreams: the filter reads the first',
  { dataset: [ds(), { source: [['product', 'sales'], ['Z', 99]] }, { fromDatasetIndex: [1, 0], transform: filt({ dimension: 'sales', gt: 50 }) }] });
add('chain', 'c-missing-up', 'an upstream that is not there: a root, its own source',
  { dataset: [ds(), { fromDatasetIndex: 9, transform: filt({ dimension: 0, gt: 0 }), source: [['own', 1]] }] });
add('chain', 'c-default', 'no from: dataset 0',
  { dataset: [ds(), { source: [['x', 1]] }, { transform: filt({ dimension: 'year', lt: 2012 }) }] });
add('chain', 'c-test-scale', "a registered transform with no dimensions: result 0 inherits the header",
  two({ type: 'test:scale', config: { k: 2 } }));
add('chain', 'c-test-scale-declared', 'the same over declared dimensions',
  two({ type: 'test:scale', config: { k: 0.5 } }, { source: clone(ROWS), dimensions: HEAD.slice() }));
add('chain', 'c-test-pairs', 'a registered transform with two results',
  { dataset: [ds(), { transform: { type: 'test:pairs', config: { name: 'product', value: 'sales' } } },
    { fromDatasetIndex: 1, fromTransformResult: 1 }, { fromDatasetIndex: 1, transform: sort({ dimension: 'value', order: 'desc' }) }] });

// ---- several results
const SAMPLES = [[1, 2, 3, 4, 50], [5, 6, 7, 8, 9], [-30, 2, 2, 2, 2, 40], [10, 20, 30, 40, 50]];
add('multi', 'm-boxplot', 'boxplot results, a copy of result 1, and a filter over result 1',
  { dataset: [{ source: clone(SAMPLES) }, { transform: { type: 'boxplot' } },
    { fromDatasetIndex: 1, fromTransformResult: 1 },
    { fromDatasetIndex: 1, fromTransformResult: 1, transform: filt({ dimension: 1, gt: 0 }) }] });
add('multi', 'm-fallback', 'result 1 of a one-result dataset is its upstream\'s result 1',
  { dataset: [{ source: clone(SAMPLES) }, { transform: { type: 'boxplot' } },
    { fromDatasetIndex: 1, transform: filt({ dimension: 'Q2', gt: 3 }) },
    { fromDatasetIndex: 2, fromTransformResult: 1 }] });
add('multi', 'm-ftr0', 'fromTransformResult 0 with a transform',
  { dataset: [ds(), { transform: sort({ dimension: 'sales', order: 'desc' }) },
    { fromDatasetIndex: 1, fromTransformResult: 0, transform: filt({ dimension: 'sales', gt: 60 }) }] });
add('multi', 'm-ftr0-alone', 'fromTransformResult 0 alone is a root dataset', { dataset: [ds(), { fromTransformResult: 0, source: [['solo', 3]] }] });
add('multi', 'm-copy-of-sort', 'a copy of a sort result keeps its header',
  { dataset: [ds(), { transform: sort({ dimension: 'sales', order: 'desc' }) }, { fromDatasetIndex: 1, fromTransformResult: 0 }] });

// ---- errors (upstream throws; the port leaves the dataset without a table)
const E = (id, note, option) => add('error', id, note, option);
E('e-unknown', 'an unregistered type', two({ type: 'nope' }));
E('e-ns', "the namespaced name of a built-in is not its key", two({ type: 'echarts:filter', config: true }));
E('e-empty-pipe', 'an empty list', two([]));
E('e-not-object', 'a transform that is a number', two(5));
E('e-nested', 'a list inside the list', two([[filt(true)]]));
E('e-no-dim', 'a condition without a dimension', two(filt({ gt: 1 })));
E('e-dim-missing', 'a dimension that is not there', two(filt({ dimension: 'nope', gt: 1 })));
E('e-dim-null', 'dimension null', two(filt({ dimension: null, gt: 1 })));
E('e-no-op', 'no operator', two(filt({ dimension: 0 })));
E('e-bad-op', 'an operator that is not one', two(filt({ dimension: 0, like: 1 })));
E('e-lt-string', 'lt a string', two(filt({ dimension: 'sales', lt: 'x' })));
E('e-time-bad', "parser 'time' and a date that is none: NaN is a number, nothing passes -- not an error",
  two(filt({ dimension: 'sales', parser: 'time', lt: 'yesterday' })));
E('e-and-empty', 'and []', two(filt({ and: [] })));
E('e-and-object', 'and {}', two(filt({ and: { dimension: 0, gt: 1 } })));
E('e-not-true', 'not true', two(filt({ not: true })));
E('e-no-config', 'no config', two({ type: 'filter' }));
E('e-config-list', 'a list as the condition', two(filt([{ dimension: 0, gt: 1 }])));
E('e-length', "a condition with a numeric 'length' is array-like", two(filt({ dimension: 'sales', gt: 1, length: 2 })));
E('e-and-zero', 'and 0 is no and: an operator called and', two(filt({ dimension: 'sales', and: 0 })));
E('e-sort-empty', 'sort, config []', two(sort([])));
E('e-sort-none', 'sort, no config', two({ type: 'sort' }));
E('e-sort-no-dim', 'sort without a dimension', two(sort({ order: 'asc' })));
E('e-sort-order', 'sort without an order', two(sort({ dimension: 0 })));
E('e-sort-incomparable', "incomparable 'mid'", two(sort({ dimension: 0, order: 'asc', incomparable: 'mid' })));
E('e-sort-parser', 'an unknown parser', two(sort({ dimension: 0, order: 'asc', parser: 'xyz' })));
E('e-sort-dim', 'a dimension that is not there', two(sort({ dimension: 9, order: 'asc' })));
E('e-sort-keyed', 'keyed columns', { dataset: [{ source: { a: [3, 1, 2] } }, { transform: sort({ dimension: 'a', order: 'asc' }) }] });
E('e-row-layout', 'an upstream laid out by row', two(filt(true), ds({ seriesLayoutBy: 'row' })));
E('e-dup', "names 'a', 'a', 'a-1': the third collides with the second's new name",
  { dataset: [{ source: [[1, 2, 3]], dimensions: ['a', 'a', 'a-1'] }, { transform: filt(true) }] });
E('e-self', 'a dataset reading itself', { dataset: [ds(), { fromDatasetIndex: 1, transform: filt(true) }] });
E('e-no-result', 'result 1 of a root dataset', { dataset: [ds(), { fromDatasetIndex: 0, fromTransformResult: 1 }] });
E('e-copy-inherit', 'a filter over a copy: the copy has no meta to inherit',
  { dataset: [{ source: clone(SAMPLES) }, { transform: { type: 'boxplot' } }, { fromDatasetIndex: 1, fromTransformResult: 1 },
    { fromDatasetIndex: 2, transform: filt(true) }] });
E('e-no-source', 'an upstream with no source', { dataset: [{ id: 'x' }, { transform: filt(true) }] });
E('e-boxplot-objects', 'boxplot over object rows', two({ type: 'boxplot' }, { source: clone(OBJ) }));
E('e-raw-item', "an external transform asks for a raw item", two({ type: 'test:raw' }));
E('e-downstream', 'a dataset reading one that failed', { dataset: [ds(), { transform: { type: 'nope' } }, { fromDatasetIndex: 1, transform: filt(true) }] });

// ---- series over transformed datasets
const R = (id, note, option) => add('render', id, note, option);
R('r-bar-filter', 'bars over a filter, labels shown',
  { dataset: [ds(), { transform: filt({ dimension: 'sales', gt: 40 }) }], xAxis: { type: 'category' }, yAxis: {},
    series: [{ type: 'bar', datasetIndex: 1, encode: { x: 'product', y: 'sales' }, label: { show: true } }] });
R('r-line-sort', 'a line over a sort, desc',
  { dataset: [ds(), { transform: sort({ dimension: 'sales', order: 'desc' }) }], xAxis: { type: 'category' }, yAxis: {},
    series: [{ type: 'line', datasetIndex: 1, encode: { x: 0, y: 2 }, label: { show: true } }] });
R('r-scatter-object', 'a scatter over object rows filtered',
  { dataset: [{ source: clone(OBJ) }, { transform: filt({ dimension: 'year', gte: 2012 }) }], xAxis: {}, yAxis: {},
    series: [{ type: 'scatter', datasetIndex: 1, encode: { x: 'year', y: 'sales' } }] });
R('r-pie-sort', 'a pie over a sort, names as labels',
  { dataset: [ds(), { transform: [filt({ dimension: 'sales', gt: 0 }), sort({ dimension: 'sales', order: 'asc' })] }],
    series: [{ type: 'pie', datasetIndex: 1, encode: { itemName: 'product', value: 'sales' }, label: { formatter: '{b}' } }] });
R('r-two', 'two series over two transforms of one table: the categories in arrival order',
  { dataset: [ds(), { transform: filt({ dimension: 'tag', eq: 'a' }) }, { transform: sort({ dimension: 'sales', order: 'asc' }) }],
    xAxis: { type: 'category' }, yAxis: {},
    series: [{ type: 'bar', datasetIndex: 1, encode: { x: 'product', y: 'sales' } },
      { type: 'bar', datasetIndex: 2, encode: { x: 'product', y: 'year' }, label: { show: true } }] });
R('r-default-encode', 'the default encode over a filter with a header',
  { dataset: [{ source: [['k', 'a', 'b'], ['p', 1, 4], ['q', 2, 5], ['r', 3, 6], ['s', 0, 9]] }, { transform: filt({ dimension: 'b', lte: 6 }) }],
    xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'bar', datasetIndex: 1 }, { type: 'bar', datasetIndex: 1, label: { show: true } }] });
R('r-row-layout', "a series reading a filter result by row (the header carried makes it possible)",
  { dataset: [{ source: [['k', 'a', 'b', 'c'], ['p', 1, 4, 7], ['q', 2, 5, 8], ['r', 3, 6, 9]] }, { transform: filt({ dimension: 'k', ne: 'q' }) }],
    xAxis: { type: 'category' }, yAxis: {},
    series: [{ type: 'bar', datasetIndex: 1, seriesLayoutBy: 'row' }, { type: 'bar', datasetIndex: 1, seriesLayoutBy: 'row' }] });
R('r-copy', 'a series over a copy of result 1: the header guessed again',
  { dataset: [{ source: clone(SAMPLES) }, { transform: { type: 'boxplot' } }, { fromDatasetIndex: 1, fromTransformResult: 1 }],
    xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'scatter', datasetIndex: 2 }] });
R('r-copy-guess', "a series over a copy guesses the header again: the copy's line of words is a header to it",
  { dataset: [ds(), { transform: { type: 'test:pairs', config: { name: 'product', value: 'sales' } } },
    { fromDatasetIndex: 1, fromTransformResult: 1 }],
    xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'bar', datasetIndex: 2, label: { show: true } }] });
R('r-root-no-source', 'fromTransformResult 0 alone is a root dataset, and one with no source refuses the series',
  { dataset: [ds(), { transform: filt({ dimension: 'sales', gt: 50 }) }, { fromDatasetIndex: 1, fromTransformResult: 0 }],
    xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'bar', datasetIndex: 2 }] });
R('r-dataset-id', 'datasetId on a transformed dataset',
  { dataset: [ds(), { id: 'top', transform: [filt({ dimension: 'sales', gt: 50 }), sort({ dimension: 'sales', order: 'desc' })] }],
    xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'bar', datasetId: 'top', encode: { x: 'product', y: 'sales' }, label: { show: true } }] });
R('r-declared', 'declared dimensions inherited: encode by name',
  { dataset: [{ source: clone(ROWS), dimensions: HEAD.slice() }, { transform: filt({ dimension: 'year', gte: 2013 }) }],
    xAxis: { type: 'category' }, yAxis: {}, series: [{ type: 'line', datasetIndex: 1, encode: { x: 'product', y: 'sales' }, label: { show: true } }] });
R('r-pie-objects', 'a pie over sorted object rows',
  { dataset: [{ source: clone(OBJ).slice(0, 6) }, { transform: sort({ dimension: 'sales', order: 'desc' }) }],
    series: [{ type: 'pie', datasetIndex: 1, encode: { itemName: 'product', value: 'sales' } }] });
R('r-error', 'a series over a transform that throws: upstream refuses the option',
  { dataset: [ds(), { transform: { type: 'nope' } }], xAxis: { type: 'category' }, yAxis: {},
    series: [{ type: 'bar', datasetIndex: 1 }] });

// ---------------------------------------------------------------------------
// guards: expectations read off the source
// ---------------------------------------------------------------------------
function guards(o) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => o.cases.find(c => c.id === id);
  const res = (id, k, r) => cs(id).datasets[k].results.find(x => x.r === (r || 0));
  const col = (id, k, c, r) => res(id, k, r).rows.slice(res(id, k, r).startIndex).map(row => row[c]);
  const names = (id, k) => col(id, k, 0).map(s => (s ? s.slice(2) : s));
  const err = (id, k) => cs(id).datasets[k].error;
  guard('a filter result carries the header line', res('f-gt', 1).startIndex === 1 && res('f-gt', 1).rows[0][0] === 's:product');
  guard('gt 50 keeps four', JSON.stringify(names('f-gt', 1)) === JSON.stringify(['Milk', 'Walnut', 'Matcha', 'Biscuit', 'Tea']));
  guard('gte keeps the boundary', names('f-gte', 1).indexOf('Walnut') >= 0);
  guard("lt 20 on strings: '12', 5 and not ' 30 '", JSON.stringify(names('f-lt', 1)) === JSON.stringify(['Tofu', 'Biscuit']));
  guard("eq 2013 meets the string '2013'", names('f-eq-num', 1).indexOf('Tea') >= 0 && names('f-eq-num', 1).indexOf('Cheese') >= 0);
  guard("eq '2012' meets 2012", names('f-eq-str', 1).length === 2);
  guard('eq null meets the null tag only', JSON.stringify(names('f-eq-null', 1)) === JSON.stringify(['Cheese']));
  guard('eq true meets nothing', names('f-eq-bool', 1).length === 0);
  guard("eq 12 / 30 / 100: '12', ' 30 ', '1e2'; not '0x10' for 16", JSON.stringify(names('f-eq-numstr', 1)) === JSON.stringify(['Tofu', 'Milk', 'Tea']));
  guard('ne keeps the null', names('f-ne', 1).indexOf('Cheese') >= 0);
  guard("'2' is index 2", JSON.stringify(names('f-dim-numstr', 1)) === JSON.stringify(names('f-gt', 1)));
  guard("the name '1' wins over index 1 for the string", col('f-dim-named', 1, 0).length === 2 && col('f-dim-named', 2, 0).length === 2
    && col('f-dim-named', 2, 0)[0] === hex(6));
  guard('nesting: 2011 or 2013, tag not a', JSON.stringify(names('f-and-or-not', 1)) === JSON.stringify(['Cheese', 'Biscuit']));
  guard('false keeps the header only', res('f-false', 1).rows.length === 1);
  guard("trim: '30' meets ' 30 '", names('f-trim2', 1)[0] === 'Milk' && names('f-trim', 1)[0] === 'Milk');
  guard("number: '7px' passes gt 6", names('f-number', 1).indexOf('Cheese') >= 0 && names('f-number', 1).indexOf('Matcha') < 0);
  guard('an unknown parser leaves the cell as it is', JSON.stringify(names('f-unknown-parser', 1)) === JSON.stringify(['Milk']));
  guard('time: 2013-01-01 00:00+08:00 is before 2013-01-01Z', col('f-time', 1, 1).map(num).join() === '3,4,9');
  guard('object rows stay objects', res('f-object-rows', 1).format === 'objectRows' && res('f-object-rows', 1).rows.length === 5);
  guard('declared dimensions are inherited', JSON.stringify(res('f-declared', 1).dims) === JSON.stringify(HEAD));
  guard('sourceHeader 2: two lines carried', res('f-header-2', 1).startIndex === 2 && res('f-header-2', 1).dims === null);
  guard("the duplicate is 'a-1'", res('f-dup', 1).dims[1] === 'a-1' && res('f-dup', 1).rows.length === 3);
  guard('keyed columns: array rows out', res('f-keyed', 1).format === 'arrayRows' && res('f-keyed', 1).rows.length === 3);
  guard('a null row passes ne', res('f-null-row', 1).rows.some(r => r === null));
  guard('reg runs upstream', names('f-reg', 1).length === 6);
  const sales = id => col(id, 1, 2).map(h => (h === null ? null : num(h)));
  guard('asc: ascending, the null last', JSON.stringify(sales('s-asc')) === JSON.stringify([24.1, 33.3, 41.1, 53.9, 55.2, 66, 72.4, 86.5, null]));
  guard('desc: descending, the null last', sales('s-desc')[0] === 86.5 && sales('s-desc')[8] === null);
  guard("multi: the 2011s by sales desc", JSON.stringify(names('s-multi', 1).slice(0, 2)) === JSON.stringify(['Biscuit', 'Tofu']));
  guard("words: by code unit, 'Walnut' first in desc", names('s-words', 1)[0] === 'Walnut');
  guard('stable: equal values keep their order', (() => {
    const rows = res('s-stable-200', 1).rows.slice(1);
    for (let i = 1; i < rows.length; i++) {
      if (num(rows[i][1]) === num(rows[i - 1][1]) && num(rows[i][0]) < num(rows[i - 1][0])) return false;
    }
    return true;
  })());
  guard('500 rows in two runs: merged', res('s-runs-500', 1).rows.slice(1).every((r, i) => num(r[1]) === i));
  guard('pipe: filter then sort', sales('p-filter-sort')[0] === 86.5 && sales('p-filter-sort').length === 7);
  guard('boxplot then filter: by the name Q2, no header', res('p-boxplot-filter', 1).startIndex === 0
    && JSON.stringify(res('p-boxplot-filter', 1).dims) === JSON.stringify(['ItemName', 'Low', 'Q1', 'Q2', 'Q3', 'High']));
  guard('only the last step may have several results', cs('p-boxplot-filter').datasets[1].results.length === 1
    && cs('p-filter-boxplot').datasets[1].results.length === 2);
  guard('chain by index', sales('c-index').length === 6 && sales('c-index')[0] === 41.1);
  guard('by id', names('c-id', 2).length === 3);
  guard('a numeric id meets its string', names('c-id-number', 2).length === 1);
  guard('the index beats the id', names('c-index-beats-id', 2).length === 2);
  guard('two upstreams: the first', JSON.stringify(names('c-index-list', 2)) === JSON.stringify(['Z']));
  guard('an upstream not there: its own source', res('c-missing-up', 1).rows[0][0] === 's:own');
  guard('scale: the header inherited, numbers doubled', res('c-test-scale', 1).startIndex === 1 && num(res('c-test-scale', 1).rows[1][2]) === 82.2);
  guard('pairs: two results', cs('c-test-pairs').datasets[1].results.length === 2 && num(res('c-test-pairs', 2).rows[1][1]) === 9);
  guard('a copy of result 1 is flagged a copy', res('m-boxplot', 2).clone);
  guard('the fallback finds the upstream\'s result 1', JSON.stringify(res('m-fallback', 3).rows) === JSON.stringify(res('m-fallback', 1, 1).rows));
  guard('fromTransformResult 0 alone is a root', res('m-ftr0-alone', 1).rows[0][0] === 's:solo');
  const errs = ['e-unknown', 'e-ns', 'e-empty-pipe', 'e-not-object', 'e-nested', 'e-no-dim', 'e-dim-missing', 'e-dim-null', 'e-no-op',
    'e-bad-op', 'e-lt-string', 'e-and-empty', 'e-and-object', 'e-not-true', 'e-no-config', 'e-config-list', 'e-length', 'e-and-zero',
    'e-sort-empty', 'e-sort-none', 'e-sort-no-dim', 'e-sort-order', 'e-sort-incomparable', 'e-sort-parser', 'e-sort-dim', 'e-sort-keyed',
    'e-row-layout', 'e-dup', 'e-boxplot-objects', 'e-raw-item'];
  for (const id of errs) guard(id + ' throws', cs(id).optionError || (err(id, 1) && err(id, 0) === null));
  guard('e-time-bad does not throw', err('e-time-bad', 1) === null && res('e-time-bad', 1).rows.length === 1);
  guard('e-self overflows the stack', err('e-self', 1) === 'RangeError');
  guard('e-no-result throws', err('e-no-result', 1) !== null);
  guard('e-copy-inherit throws on the copy\'s missing meta', err('e-copy-inherit', 3) !== null && err('e-copy-inherit', 2) === null);
  guard('e-no-source throws', err('e-no-source', 1) !== null);
  guard('e-downstream: both throw', err('e-downstream', 1) !== null && err('e-downstream', 2) !== null);
  guard('render: the bars are the rows left', cs('r-bar-filter').render.series[0].count === 6);
  guard('render: categories in arrival order', JSON.stringify(cs('r-two').render.axes[0].categories)
    === JSON.stringify(['Tofu', 'Walnut', 'Tea', 'Cheese', 'Juice', 'Biscuit', 'Matcha', 'Milk', 'Coffee']));
  guard('render: the pie is sorted', cs('r-pie-sort').render.series[0].labels[0].text === 'Cheese');
  guard('render: a throwing transform refuses the option', !!cs('r-error').render.error);
  guard('render: the copy guessed a header: one bar', cs('r-copy-guess').render.series[0].count === 1);
  return g;
}

// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------
function generate() {
  ecKey = null;
  const out = {
    source: DIST, version: echarts.version, W, H,
    notes: [
      'animation: false throughout; TZ=UTC; Math.random 0.',
      'datasets: prepareSource() on each dataset in order, then SourceManager._sourceList; an error is the message thrown.',
      'render: setOption + renderToSVGString; an option that throws is recorded as {error}.',
      'the transforms test:scale, test:pairs and test:raw are registered by this script; the Pascal suite registers the same.',
    ],
    cases: CASES.map(runCase),
  };
  out.guards = guards(out);
  return out;
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(g => !g.ok);
out1.guards.forEach(g => console.log('guard ' + (g.ok ? 'ok  ' : 'FAIL') + ' ' + g.name));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (process.env.ORACLE_DUMP) console.log(json1);
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (json1.indexOf('\\u0000') >= 0) {
  console.log('FAILED: a NUL in the fixture (fpjson drops it)');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
