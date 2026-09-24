'use strict';
// What ECharts makes of a raw value written as a string, to the bit: the
// number numericToNumber reads from it (util/number.ts:774-780) and the
// tooltip cell addCommas prints for that number (util/format.ts:32-39) -- the
// answers tyControls' TyJsNumericToNumber and TyJsAddCommas(TyJsNumberToString)
// must give. makeValueReadable (format.ts:64-107) takes this path for every
// value that is not a time or an ordinal: a finite n is printed with commas,
// anything else falls back to the text itself.
//
//   node tools/advchart-oracle/raw-value.js
//
// writes tests/fixtures/advchart-raw-value.json (ORACLE_OUT overrides):
//   source    the ECharts version and node/V8 it ran under
//   curated   how many of the records come first and were chosen by hand
//   random    how many follow from the seeded generator, and its seed
//   records   [{in, nBits, nText, cell}], one per line:
//     in      the string handed to numericToNumber, exactly (JSON holds every
//             one of them; NBSP, U+FEFF and the other non-ASCII spaces go out
//             as raw UTF-8, tab and newline as JSON escapes)
//     nBits   n = echarts.number.numericToNumber(in) as the 16 hex digits of
//             its IEEE-754 bits, big-endian, lowercase; a NaN is written
//             7ff8000000000000 whatever its payload: compare NaN as NaN
//     nText   String(n) (so -0 is '0': nBits tells it apart)
//     cell    echarts.format.addCommas(n) when n is finite, else null (the
//             cell then falls back to the text, which is not this oracle's)
//
// The curated rows: every raw of the tooltip cell's recipe (wf49 audit 1.2
// step 3), each JS white space (StrWhiteSpaceChar: tab, VT, FF, space, NBSP,
// U+FEFF, the Zs block, LF, CR, U+2028/2029) and two that are not (U+180E,
// U+200B), signs, dots and exponents at their edges, hex/octal/binary in both
// cases (the ' 0x0 ' guard looks for a lowercase 'x' only), Infinity spelled
// every way, the extremes of the doubles, and text around a number. The
// random rows come from an xorshift generator over the alphabet 0-9 . e E + -
// x o b space tab NBSP 'Infinity' a: half of them shaped like a number (white
// space, a sign, digits, a dot, an exponent, a radix prefix, a stray token),
// half any sequence of tokens. Duplicates are drawn again.
//
// Self-checks (the run exits 1 and the fixture is not written on any
// failure):
//   1 every row's n is bit-equal to the recipe the Pascal port follows:
//     f = parseFloat(in); n = f when Number(in) === f and not (f is 0 and a
//     lowercase 'x' sits past the first character), else NaN;
//   2 every finite row's cell equals String(n) with a comma put before each
//     group of three digits counted from the end of every digit run in the
//     part before the first '.' -- a second transcription of addCommas;
//   3 the curated rows hold every input the audit names, and there are at
//     least 60 of them and exactly 500 random rows;
//   4 the rows bite: at least 20 where parseFloat alone gives a different
//     answer, at least 20 where Number alone does, at least 10 where n is
//     infinite, at least 50 finite, at least 50 NaN, at least one -0, at least
//     20 cells with a comma;
//   5 the whole fixture is generated twice in the process and the two JSON
//     texts are byte-identical.
// Outside the script: run twice and diff.
const fs = require('fs');
const path = require('path');

const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const OUT = process.env.ORACLE_OUT || path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-raw-value.json');

const fails = [];
const fail = msg => fails.push(msg);

const buf = Buffer.alloc(8);
function hex(x) {
  if (Number.isNaN(x)) return '7ff8000000000000';
  buf.writeDoubleBE(x);
  return buf.toString('hex');
}

// ---------- the curated rows ----------

const NBSP = '\u00a0';
const BOM = '\ufeff';
// every input the audit names (1.2 step 3, and the task's list)
const REQUIRED = ['0x10', ' 0x0 ', '0b0', 'Infinity', '1e400', '12px', NBSP + '12' + NBSP, '12.50', ' 5 ', '1e3',
  'abc', '-', '', ' ', '-0', '.', '5.', '+.5', '1_0', '0x0'];
const SPACES = ['\t', '\v', '\f', ' ', NBSP, BOM, '\u1680', '\u2000', '\u2001', '\u2002', '\u2003', '\u2004', '\u2005',
  '\u2006', '\u2007', '\u2008', '\u2009', '\u200a', '\u202f', '\u205f', '\u3000', '\n', '\r', '\u2028', '\u2029'];
// (a row listed twice is kept once, where it first appears)
const CURATED = Array.from(new Set([].concat(
  REQUIRED,
  SPACES.map(w => w + '12' + w),
  // not white space to JS
  ['\u180e12', '12\u200b', '\u200b'],
  // white space alone, and around a zero
  [NBSP, BOM, '\t\n', BOM + '0' + BOM, ' -0 ', '\t0x0'],
  // signs, dots, exponents
  ['+0', '0', '00', '007', '-.5', '.5', '+5', '--1', '+-1', '+', '1.2.3', '1 2', '0.0', '-0.0', '0e5', '1E3', '1e+3',
    '1e-3', '1e', '1e+', 'e3', '.e1', '5.e1', '1e3 ', '1e3x'],
  // radix prefixes: the guard is on a lowercase 'x' past the first character
  ['0X10', '0X0', '0x1g', '0x', '-0x10', '00x0', '0o17', '0O17', '0o0', '0b101', '0B101', '0b', '0b2', '1x', '10x',
    '0 x', '0x0 ', ' 0X0 '],
  // Infinity every way
  ['-Infinity', '+Infinity', ' Infinity ', NBSP + 'Infinity', 'infinity', 'Inf', 'NaN', 'Infinityx', '1e308',
    '1e309', '-1e400', '1e-400'],
  // the doubles' edges and the digits a double cannot hold
  ['4.9e-324', '5e-324', '2e-324', '2.4703282292062328e-324', '1.7976931348623157e308', '1.7976931348623158e308',
    '1.7976931348623159e308', '9007199254740993', '0.1', '0.30000000000000004', '1e21', '123456789012345680000',
    '1234567.891', '-1234.5', '-1234567', '1000', '999', '100000000000000000'],
  // text around a number
  ['5px', '1,000', 'true', 'null', '12 px', 'a1', '1a'])));

// ---------- the random rows ----------

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
  const seen = new Set(CURATED);
  const random = [];
  while (random.length < 500) {
    const t = below(2) ? shaped() : any();
    if (seen.has(t)) continue;
    seen.add(t);
    random.push(t);
  }
  return random;
}

function record(t) {
  const n = echarts.number.numericToNumber(t);
  return { in: t, nBits: hex(n), nText: String(n), cell: Number.isFinite(n) ? echarts.format.addCommas(n) : null };
}

function build() {
  const random = generate();
  const records = CURATED.map(record).concat(random.map(record));
  const head = {
    source: 'ECharts ' + echarts.version + ' echarts.number.numericToNumber, echarts.format.addCommas; node '
      + process.version + ' (V8 ' + process.versions.v8 + ')',
    curated: CURATED.length,
    random: random.length,
    seed: '0x' + SEED.toString(16),
  };
  const text = JSON.stringify(head, null, 1).replace(/\n}$/, ',\n "records": [\n')
    + records.map(r => '  ' + JSON.stringify(r)).join(',\n') + '\n ]\n}\n';
  return { records, random, text };
}

const first = build();
const { records } = first;
const nOf = r => Buffer.from(r.nBits, 'hex').readDoubleBE(0);

// ---------- self-check 1: the recipe ----------
const recipe = t => {
  const f = parseFloat(t);
  return Number(t) === f && !(f === 0 && t.indexOf('x') > 0) ? f : NaN;
};
for (const r of records) {
  if (hex(recipe(r.in)) !== r.nBits) fail('1 ' + JSON.stringify(r.in) + ': the recipe gives ' + hex(recipe(r.in)) + ', upstream ' + r.nBits);
}

// ---------- self-check 2: addCommas transcribed ----------
function commas(n) {
  const s = String(n);
  const dot = s.indexOf('.');
  const head = dot < 0 ? s : s.slice(0, dot);
  let out = '';
  let i = 0;
  while (i < head.length) {
    if (head[i] >= '0' && head[i] <= '9') {
      let j = i;
      while (j < head.length && head[j] >= '0' && head[j] <= '9') j++;
      const run = head.slice(i, j);
      for (let k = 0; k < run.length; k++) {
        if (k > 0 && (run.length - k) % 3 === 0) out += ',';
        out += run[k];
      }
      i = j;
    } else {
      out += head[i++];
    }
  }
  return out + (dot < 0 ? '' : s.slice(dot));
}
for (const r of records) {
  const n = nOf(r);
  const want = Number.isFinite(n) ? commas(n) : null;
  if (want !== r.cell) fail('2 ' + JSON.stringify(r.in) + ': the transcription gives ' + JSON.stringify(want) + ', upstream ' + JSON.stringify(r.cell));
  if (r.nText !== String(n)) fail('2 ' + JSON.stringify(r.in) + ': nText ' + r.nText + ' is not String(n)');
}

// ---------- self-check 3: coverage ----------
for (const t of REQUIRED) if (!records.some(r => r.in === t)) fail('3 no row for ' + JSON.stringify(t));
if (first.random.length !== 500) fail('3 ' + first.random.length + ' random rows');
if (CURATED.length < 60) fail('3 only ' + CURATED.length + ' curated rows');
if (new Set(records.map(r => r.in)).size !== records.length) fail('3 a duplicate row');

// ---------- self-check 4: the rows bite ----------
const tally = {
  'parseFloat alone differs': records.filter(r => hex(parseFloat(r.in)) !== r.nBits).length,
  'Number alone differs': records.filter(r => hex(Number(r.in)) !== r.nBits).length,
  infinite: records.filter(r => { const n = nOf(r); return n === Infinity || n === -Infinity; }).length,
  finite: records.filter(r => Number.isFinite(nOf(r))).length,
  NaN: records.filter(r => Number.isNaN(nOf(r))).length,
  '-0': records.filter(r => Object.is(nOf(r), -0)).length,
  'with a comma': records.filter(r => r.cell && r.cell.includes(',')).length,
};
const MIN = { 'parseFloat alone differs': 20, 'Number alone differs': 20, infinite: 10, finite: 50, NaN: 50, '-0': 1,
  'with a comma': 20 };
for (const k of Object.keys(MIN)) if (tally[k] < MIN[k]) fail('4 ' + k + ': ' + tally[k] + ' < ' + MIN[k]);

// ---------- self-check 5: determinism ----------
const second = build();
if (second.text !== first.text) fail('5 a second generation in the process differs');

if (fails.length) {
  fails.slice(0, 20).forEach(f => console.log('self-check failed: ' + f));
  console.log('FAILED: ' + fails.length + ' self-check failure(s); the fixture is not written');
  process.exit(1);
}
fs.writeFileSync(OUT, first.text);
console.log('self-checks 1-5 passed; ' + Object.keys(tally).map(k => k + ' ' + tally[k]).join(', '));
console.log(records.length + ' records (' + CURATED.length + ' curated + ' + first.random.length + ' random) ->', OUT);
