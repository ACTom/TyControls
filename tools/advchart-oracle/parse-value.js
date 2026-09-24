'use strict';
// What ECharts stores for a raw data cell, to the bit, read back from the real
// store: the number a float dimension holds (parseDataValue,
// data/helper/dataValueHelper.ts:36-73: '' and null are NaN, anything else is
// Number(v)) and the number a time dimension holds (the same, after
// parseDate, util/number.ts:484-561, for every cell that is not a number, not
// null and not '-'). These are the answers tyControls' TyParseDataValue(cell,
// ddtFloat) and TyParseDataValue(cell, ddtTime) must give (wf53 D9).
//
//   node tools/advchart-oracle/parse-value.js
//
// writes tests/fixtures/advchart-parse-value.json (ORACLE_OUT overrides):
//   source    the ECharts version and node/V8 it ran under
//   curated   how many of the records come first and were chosen by hand
//   random    how many follow from the seeded generator, and its seed
//   records   [{in, float, time}], one per line:
//     in      the JSON cell exactly as the option held it: a string (NBSP,
//             U+FEFF and the other non-ASCII spaces go out as raw UTF-8, tab
//             and newline as JSON escapes), a number, true, false or null.
//             A number is always one JSON can write (no NaN, no Infinity, no
//             -0) and never an integer literal past 2^63.
//     float   the store's value on a bar's y dimension, one bar over a
//             category x axis c0..cN with data = every in, read with
//             data.getStore().getByRawIndex(yDim, i); as the 16 hex digits of
//             its IEEE-754 bits, big-endian, lowercase; a NaN is written
//             7ff8000000000000 whatever its payload: compare NaN as NaN
//     time    the store's value on a line's x dimension, one line over a time
//             x axis with data = [[in, 1] ...] and useUTC true (parseDate
//             ignores useUTC: the store is the same without it, which the run
//             checks), read the same way and written the same way; null for a
//             zone-local input -- a string TIME_REG matches with a year and no
//             zone suffix, which parseDate reads as local time -- because its
//             answer is this machine's zone's, not upstream's
//
// The curated rows: every cell audit53 section 0 and upstream53 section 2
// name (those of them JSON can hold; the array and object cells are left
// out), the JS white spaces around a number, radix literals every way,
// Infinity every way, time strings with a Z or +-hh:mm suffix (and their
// quirks: the offset's minutes are dropped, a year under 100 is 19xx, a
// fraction keeps its first three digits as they stand, fields overflow), the
// zone-local strings (time null), and numbers. The random rows come from
// raw-value.js's xorshift generator, unchanged, seeded the same: half shaped
// like a number, half any sequence of tokens. Duplicates are drawn again.
//
// Self-checks (the run exits 1 and the fixture is not written on any
// failure):
//   1 every row's float is bit-equal to (v == null || v === '') ? NaN :
//     Number(v); and the time store is bit-equal with useUTC false;
//   2 the curated rows hold every input the audits name, each once, and there
//     are exactly 500 random rows;
//   3 the rows bite: at least 10 infinite, 1 -0, 20 radix literals, 20 white
//     space only or padded, 50 NaN, 50 finite (float);
//   4 the whole fixture is generated twice in the process and the two JSON
//     texts are byte-identical.
// Outside the script: run twice and diff.
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const OUT = process.env.ORACLE_OUT || path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-parse-value.json');

const fails = [];
const fail = msg => fails.push(msg);

const buf = Buffer.alloc(8);
function hex(x) {
  if (Number.isNaN(x)) return '7ff8000000000000';
  buf.writeDoubleBE(x);
  return buf.toString('hex');
}
const bitsOf = h => Buffer.from(h, 'hex').readDoubleBE(0);
// a cell as the self-checks print it
const show = v => (typeof v === 'string' ? JSON.stringify(v) : String(v));
// one key per cell, telling 5 from '5' and true from 'true'
const keyOf = v => typeof v + ':' + String(v);

// ---------- the curated rows ----------

const NBSP = '\u00a0';
const BOM = '\ufeff';
// every cell audit53 section 0 and upstream53 section 2 name
const REQUIRED = [
  // audit53 section 0 (the store table, C4, LMT)
  '   ', '', '0x10', '0o17', '0b101', '-0x10', 'Infinity', '+Infinity', '-Infinity', 'Inf', 'NaN', '5e+',
  NBSP + '7', BOM + '8', '1e400', '-0', true, false, ' 2020', '2020 ', '1000',
  // upstream53 section 2 (and a1's store row)
  '0X10', '0b11', ' 12 ', '\t5\n', '+5', '1e3', '.5', '5.', '12px', '1,000', '1_000', 'abc', '-', '2020',
  '2020-01-02', '1700000000000', null, 1.7, -1.7,
  // the time rows audit53 step 4 lists, and upstream53 1.5's
  '0', '86400000', '2020-1-2', '2020/01/02', 1.5, 1577923200000.5,
];
const SPACES = ['\t', '\v', '\f', ' ', NBSP, BOM, '\u1680', '\u2000', '\u2001', '\u2002', '\u2003', '\u2004', '\u2005',
  '\u2006', '\u2007', '\u2008', '\u2009', '\u200a', '\u202f', '\u205f', '\u3000', '\n', '\r', '\u2028', '\u2029'];
const CURATED_ALL = [].concat(
  REQUIRED,
  // white space around a number, and alone
  SPACES.map(w => w + '7' + w),
  SPACES,
  ['\u180e7', '7\u200b', '\u200b', '\t\n', BOM + '0' + BOM, ' -0 ', '\t0x10 '],
  // signs, dots, exponents
  ['+0', '00', '007', '-.5', '+.5', '--1', '+-1', '+', '.', '1.2.3', '1 2', '0.0', '-0.0', '0e5', '1E3', '1e+3',
    '1e-3', '1e', 'e3', '.e1', '5.e1', '1e3x', '12.50', ' 5 '],
  // radix literals
  ['0x0', ' 0x0 ', '0X0', '0xff', '0XFF', '0x1g', '0x', '-0o17', '+0x10', '00x0', '0O17', '0o0', '0o8', '0B101',
    '0b', '0b2', '0b0', '1x', '0 x', '0x10 ', ' 0b11', NBSP + '0o17'],
  // Infinity every way
  [' Infinity ', NBSP + 'Infinity', 'infinity', 'INFINITY', 'Infinityx', '-1e400', '+1e400', '1e309',
    '1.7976931348623159e308', '1e-400', '-1e-400'],
  // the doubles' edges
  ['5e-324', '1.7976931348623157e308', '9007199254740993', '0.1', '0.30000000000000004', '1e21'],
  // text around a number
  ['5px', 'true', 'false', 'null', 'undefined', '12 px', 'a1', '1a'],
  // time strings that are not local: a Z or +-hh:mm after the hour
  ['2020-01-02T03:04:05Z', '2020-01-02T03:04:05.123Z', '2020-01-02 03:04:05Z', '2020-01-02T03Z',
    '2020-01-02T03:04+08:00', '2020-01-02T03:04:05+0800', '2020-01-02T03:04:05-05:00', '2020/1/2 3:4:5,678-0500',
    '2020-01-02T03:04+05:30', '2020-01-02T03:04:05.5Z', '2020-01-02T03:04:05.1234Z', '0050-01-01T00Z',
    '2020-13-40T25:61:61Z', '1000-01-01T00:00Z', '2020-01-02T03:04:05z', '2020-01-02T03:04:05+8', '2020Z',
    '2020-01-02Z', '2020-01-02T03:04:05Z ', ' 2020-01-02T03:04:05Z', '-2020-01-02T00Z', '20200-01-02T00Z'],
  // time strings read as local: time null
  ['2020-01-02T03:04:05', '2020-01', '0050', '2020-1-2 3:4', '9999'],
  // numbers
  [0, 5, -3, 1, 16, 1577808000000, 1e21, 1.5e300, 5e-324, 0.1, -1234.5, 12.5]);
// a row listed twice is kept once, where it first appears
const CURATED = [];
{
  const seen = new Set();
  for (const v of CURATED_ALL) {
    const k = keyOf(v);
    if (seen.has(k)) continue;
    seen.add(k);
    CURATED.push(v);
  }
}

// ---------- the random rows: raw-value.js's generator, unchanged ----------

const SEED = 0x2545F491;
function generate() {
  let s = SEED;
  function u32() { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s; }
  const below = n => u32() % n;
  const pick = arr => arr[below(arr.length)];
  const TOKENS = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', 'e', 'E', '+', '-', 'x', 'o', 'b', ' ', '\t',
    NBSP, 'Infinity', 'a'];
  const DIGITS = TOKENS.slice(0, 10);
  const WS = [' ', '\t', NBSP];
  const digits = n => { let t = ''; for (let i = 0; i < n; i++) t += pick(DIGITS); return t; };
  const maybe = (p, f) => (below(100) < p ? f() : '');
  const shaped = () => {
    let t = maybe(25, () => pick(WS)) + maybe(35, () => pick(['+', '-']));
    const r = below(100);
    if (r < 10) t += '0' + pick(['x', 'o', 'b']) + digits(below(4));
    else if (r < 16) t += 'Infinity';
    else {
      t += digits(below(8));
      t += maybe(45, () => '.' + digits(below(8)));
      t += maybe(35, () => pick(['e', 'E']) + maybe(50, () => pick(['+', '-'])) + digits(below(4)));
    }
    t += maybe(10, () => pick(TOKENS));
    return t + maybe(25, () => pick(WS));
  };
  const any = () => { let t = ''; const n = 1 + below(7); for (let i = 0; i < n; i++) t += pick(TOKENS); return t; };
  const seen = new Set(CURATED.filter(v => typeof v === 'string'));
  const random = [];
  while (random.length < 500) {
    const t = below(2) ? shaped() : any();
    if (seen.has(t)) continue;
    seen.add(t);
    random.push(t);
  }
  return random;
}

// ---------- the stores ----------

function withChart(option, fn) {
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
  try {
    option.animation = false;
    chart.setOption(option);
    return fn(chart);
  } finally {
    chart.dispose();
  }
}

// the values series 0's store holds on `dim`, one per raw index
function storeOf(chart, dim, n) {
  const data = chart.getModel().getSeriesByIndex(0).getData();
  const store = data.getStore();
  const di = data.getDimensionIndex(dim);
  if (store.count() !== n) throw new Error('the store holds ' + store.count() + ' rows, not ' + n);
  const out = [];
  for (let r = 0; r < n; r++) out.push(store.getByRawIndex(di, r));
  return out;
}

function floatStore(cells) {
  return withChart({
    xAxis: { type: 'category', data: cells.map((_, i) => 'c' + i) },
    yAxis: { type: 'value' },
    series: [{ type: 'bar', data: cells.slice() }],
  }, c => {
    const info = c.getModel().getSeriesByIndex(0).getData().getDimensionInfo('y');
    if (info.type !== 'float') throw new Error('the bar\'s y dimension is ' + info.type);
    return storeOf(c, 'y', cells.length);
  });
}

function timeStore(cells, useUTC) {
  return withChart({
    useUTC,
    xAxis: { type: 'time' },
    yAxis: { type: 'value' },
    series: [{ type: 'line', data: cells.map(v => [v, 1]) }],
  }, c => {
    const info = c.getModel().getSeriesByIndex(0).getData().getDimensionInfo('x');
    if (info.type !== 'time') throw new Error('the line\'s x dimension is ' + info.type);
    return storeOf(c, 'x', cells.length);
  });
}

// parseDate's TIME_REG (util/number.ts:484), verbatim
const TIME_REG = /^(?:(\d{4})(?:[-\/](\d{1,2})(?:[-\/](\d{1,2})(?:[T ](\d{1,2})(?::(\d{1,2})(?::(\d{1,2})(?:[.,](\d+))?)?)?(Z|[\+\-]\d\d:?\d\d)?)?)?)?)?$/; // eslint-disable-line
function zoneLocal(v) {
  if (typeof v !== 'string') return false;
  const m = TIME_REG.exec(v);
  return !!m && m[1] !== undefined && !m[8];
}

function build() {
  const random = generate();
  const cells = CURATED.concat(random);
  const f = floatStore(cells);
  const t = timeStore(cells, true);
  const records = cells.map((v, i) => ({ in: v, float: hex(f[i]), time: zoneLocal(v) ? null : hex(t[i]) }));
  const head = {
    source: 'ECharts ' + echarts.version + ' SeriesData store (bar y float, line x time); node '
      + process.version + ' (V8 ' + process.versions.v8 + ')',
    curated: CURATED.length,
    random: random.length,
    seed: '0x' + SEED.toString(16),
  };
  const text = JSON.stringify(head, null, 1).replace(/\n}$/, ',\n "records": [\n')
    + records.map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n ]\n}\n';
  return { cells, records, random, time: t, text };
}

const first = build();
const { records } = first;

// ---------- self-check 1: the recipe ----------
const recipe = v => ((v == null || v === '') ? NaN : Number(v));
for (const r of records) {
  if (hex(recipe(r.in)) !== r.float) fail('1 ' + show(r.in) + ': the recipe gives ' + hex(recipe(r.in)) + ', the store ' + r.float);
}
{
  const local = timeStore(first.cells, false);
  first.time.forEach((v, i) => {
    if (hex(v) !== hex(local[i])) fail('1 ' + show(first.cells[i]) + ': useUTC moves the time store');
  });
}

// ---------- self-check 2: coverage ----------
{
  const have = new Map();
  for (const r of records) have.set(keyOf(r.in), (have.get(keyOf(r.in)) || 0) + 1);
  for (const v of REQUIRED) if (!have.has(keyOf(v))) fail('2 no row for ' + show(v));
  for (const [k, n] of have) if (n > 1) fail('2 ' + k + ' is in ' + n + ' rows');
  if (first.random.length !== 500) fail('2 ' + first.random.length + ' random rows');
  for (const r of records) {
    if (typeof r.in === 'number') {
      const t = JSON.stringify(r.in);
      if (!Number.isFinite(r.in) || Object.is(r.in, -0) || (/^-?\d+$/.test(t) && Math.abs(r.in) >= 2 ** 63)) {
        fail('2 the number ' + t + ' does not go out as itself');
      }
    } else if (!(typeof r.in === 'string' || typeof r.in === 'boolean' || r.in === null)) {
      fail('2 a cell of type ' + typeof r.in);
    }
  }
}

// ---------- self-check 3: the rows bite ----------
const isStr = v => typeof v === 'string';
const tally = {
  infinite: records.filter(r => { const n = bitsOf(r.float); return n === Infinity || n === -Infinity; }).length,
  '-0': records.filter(r => Object.is(bitsOf(r.float), -0)).length,
  radix: records.filter(r => isStr(r.in) && /^[+-]?0[xob]/i.test(r.in.trim())).length,
  'white space only or padded': records.filter(r => isStr(r.in) && r.in !== '' && r.in.trim() !== r.in).length,
  NaN: records.filter(r => Number.isNaN(bitsOf(r.float))).length,
  finite: records.filter(r => Number.isFinite(bitsOf(r.float))).length,
};
const MIN = { infinite: 10, '-0': 1, radix: 20, 'white space only or padded': 20, NaN: 50, finite: 50 };
for (const k of Object.keys(MIN)) if (tally[k] < MIN[k]) fail('3 ' + k + ': ' + tally[k] + ' < ' + MIN[k]);

// ---------- self-check 4: determinism ----------
const second = build();
if (second.text !== first.text) fail('4 a second generation in the process differs');

if (fails.length) {
  fails.slice(0, 20).forEach(f => console.log('self-check failed: ' + f));
  console.log('FAILED: ' + fails.length + ' self-check failure(s); the fixture is not written');
  process.exit(1);
}
fs.writeFileSync(OUT, first.text);
const timeTally = {
  'time null (zone-local)': records.filter(r => r.time === null).length,
  'time NaN': records.filter(r => r.time === '7ff8000000000000').length,
  'time finite': records.filter(r => r.time !== null && Number.isFinite(bitsOf(r.time))).length,
};
console.log('self-checks 1-4 passed; ' + Object.keys(tally).map(k => k + ' ' + tally[k]).join(', ') + '; '
  + Object.keys(timeTally).map(k => k + ' ' + timeTally[k]).join(', '));
console.log(records.length + ' records (' + CURATED.length + ' curated + ' + first.random.length + ' random) ->', OUT);
