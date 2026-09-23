'use strict';
// What V8's Math.pow and Math.log answer, to the bit -- the answers
// tyControls.AdvChart.JsMath's TyJsPow and TyJsLog must give. ECharts reaches
// them through mathPow / mathLog (util/number.ts:588-597): the log scale's
// ticks, normalize and pointToData (scale/helper.ts), nice(), quantity().
//
//   node tools/advchart-oracle/js-pow-log.js
//
// writes tests/fixtures/advchart-js-powlog.json (ORACLE_OUT overrides):
//   source   node and V8 versions, and how the rows were chosen
//   v8       process.versions.v8
//   pow      [[xhex, yhex, rhex, label]]: rhex = Math.pow(x, y)
//   log      [[xhex, rhex, label]]:       rhex = Math.log(x)
// Doubles are the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase). A NaN result is written 7ff8000000000000 whatever its payload:
// compare NaN as NaN. label is String(x) (and ', ' String(y)), -0 as '-0'.
//
// Rows come from a seeded generator, in categories, each thinned to a quota
// (every k-th of its draws, in draw order), plus EVERY draw on which netlib
// fdlibm 5.3's pow (the textbook r line) differs from V8's -- the rows that
// turn red if a port follows the textbook:
//   pow: the special values crossed (NaN, +-Inf, +-0, +-1, subnormals, the
//     largest and smallest normals, halves, integers); negative bases with
//     odd, even, huge and non-integer exponents; the sentinels 10^-4,
//     10^-307, 1.5^1025 (V8 != textbook) and 10^2.5, 2^27.5 (V8 == textbook,
//     both != correctly rounded); integer powers of ten; the log axis'
//     pow(10, k +- w/2); pow(10, u*320); pow(2, k + 0.5); pow(2, 27.5 +- tiny);
//     small bases; integer ^ integer; halves; subnormal x; subnormal results;
//     the overflow edge; x near 1 with |y| > 2^31; the branch edges of the
//     code (interval bounds of |x|, z = 1024 and z = -1075); positive x with
//     |y| <= 64; raw bit patterns.
//   log: the special values; the sentinels; Math.pow(10, k) for every k in
//     -323..308 and Number('1e' + k) where it differs; powers of two; integers;
//     (0, 1000); x near 1 (the |f| < 2^-20 branch); the branch edges of the
//     mantissa; subnormals; positive bit patterns.
//
// Self-checks (the run exits 1 on any failure):
//   1 every row is bit-equal to both Math.pow / Math.log (NaN as NaN) and the
//     transcription in fdlibm-powlog.js, which the Pascal port follows;
//   2 at least 300 pow rows differ under the textbook r line (powTextbook);
//   3 the sentinels: pow(10,-4) = 3f1a36e2eb1c432c, pow(10,-307) =
//     0031fa182c40c60e, pow(1.5,1025) = 656806d222b7eba6, each != textbook;
//     pow(10,2.5) and pow(2,27.5) == textbook (not discriminators);
//   4 the transcription's constants are V8's decimal literals, bit for bit;
//   5 a fresh seeded draw of 100,000 per shape (not written) agrees too.
// Outside the script: run twice and diff; run under node --jitless and diff.
const fs = require('fs');
const path = require('path');
const F = require('./fdlibm-powlog.js');

const OUT = process.env.ORACLE_OUT || path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-js-powlog.json');
const fails = [];
const fail = msg => fails.push(msg);

const buf = Buffer.alloc(8);
function hex(x) {
  if (Number.isNaN(x)) return '7ff8000000000000';
  buf.writeDoubleBE(x);
  return buf.toString('hex');
}
const fromWords = F.fromWords;
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const same = (a, b) => Object.is(a, b) || (Number.isNaN(a) && Number.isNaN(b));

let s = 0x9E3779B9;
function u32() { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s; }
function rnd() { return (u32() * 2097152 + (u32() >>> 11)) / 9007199254740992; }
function posFinite() { let x; do { x = Math.abs(fromWords(u32(), u32())); } while (!isFinite(x) || x === 0); return x; }

// ---------- self-check 4: constants ----------
{
  const W = F.fromWords;
  [[W(0x7E37E43C, 0x8800759C), 1.0e300], [W(0x01A56E1F, 0xC2F8F359), 1.0e-300], [W(0x3C971547, 0x652B82FE), 8.0085662595372944372e-17],
    [W(0x3FD55555, 0x55555555), 0.33333333333333333], [W(0x3FD55555, 0x55555555), 0.3333333333333333333333],
    [W(0x3FE62E42, 0xFEE00000), 6.93147180369123816490e-01], [W(0x3DEA39EF, 0x35793C76), 1.90821492927058770002e-10],
    [W(0x3FEEC709, 0xDC3A03FD), 9.61796693925975554329e-01], [W(0x3FF71547, 0x652B82FE), 1.44269504088896338700e+00],
    [W(0xBE205C61, 0x0CA86C39), -1.90465429995776804525e-09], [W(0x3C900000, 0), Math.pow(2, -54)]]
    .forEach(([a, b], i) => { if (!Object.is(a, b)) fail('constant ' + i + ': ' + hex(a) + ' is not the literal ' + hex(b)); });
}

// ---------- pow ----------
const powCands = [];
let cat = '';
const P = (x, y) => powCands.push({ x, y, cat });
// quotas per list: the pow and log lists share category names
const powQuotas = {};
const logQuotas = {};
let quotas = powQuotas;
const group = (name, quota) => { cat = name; quotas[name] = quota; };

const SPECIALS = [0, -0, 1, -1, 0.5, -0.5, 2, -2, 3, -3, 10, Infinity, -Infinity, NaN,
  5e-324, -5e-324, 2.2250738585072014e-308, Number.MAX_VALUE, 1 + Number.EPSILON, 1 - Number.EPSILON / 2,
  2147483648.5, 9007199254740991, 1e300, -1e20, 1024, -1075];
group('special', Infinity);
for (const x of SPECIALS) for (const y of SPECIALS) P(x, y);
group('sentinel', Infinity);
P(10, -4); P(10, -307); P(1.5, 1025); P(10, 2.5); P(2, 27.5);
group('negative base', Infinity);
for (const x of [-0.5, -1.5, -2, -3, -10, -7.25, -1e-310, -1e300, -(1 + Math.pow(2, -30)), -Math.E]) {
  for (const y of [-3, -2, -1, 1, 2, 3, 7, 0.5, -0.5, 2.5, 1e20, 9007199254740991, 4503599627370497, 1025, -1074, 0.3, 1 / 3]) P(x, y);
}
group('powers of ten', 220);
for (let k = -330; k <= 310; k++) P(10, k);
group('log axis 10^(k +- w/2)', 520);
for (let i = 0; i < 3000; i++) { const k = Math.floor(rnd() * 640) - 330; const w = Math.round(rnd() * 20) / 20; P(10, rnd() < 0.5 ? k + w / 2 : k - w / 2); }
group('10^(u*320)', 130);
for (let i = 0; i < 1000; i++) P(10, (rnd() * 2 - 1) * 320);
group('2^(k+0.5)', 120);
for (let k = -1080; k <= 1030; k += 3) P(2, k + 0.5);
group('2^(27.5 +- tiny)', 80);
for (let i = 0; i < 1000; i++) P(2, 27.5 + (rnd() * 2 - 1) * Math.pow(2, -Math.floor(rnd() * 50)));
group('small bases', 160);
for (let i = 0; i < 1000; i++) P([2, 3, Math.E, 5, 7, 16, 100, 0.1][u32() % 8], (rnd() * 2 - 1) * 60);
group('integer ^ integer', 160);
for (let i = 0; i < 1500; i++) P(Math.round(rnd() * 120) - 20, Math.round((rnd() * 2 - 1) * 200));
group('halves', 80);
for (let i = 0; i < 500; i++) P(Math.round(rnd() * 400) / 2 - 20, Math.round((rnd() * 2 - 1) * 200) / 2);
group('subnormal x', 80);
for (let i = 0; i < 500; i++) P(fromWords(u32() & 0x000fffff, u32()), (rnd() * 2 - 1) * 1.2);
group('subnormal result', 100);
for (let i = 0; i < 500; i++) P(2, -1022 - rnd() * 54);
group('overflow edge', 80);
for (let i = 0; i < 500; i++) P(2, 1023 + rnd() * 1.01);
group('x near 1, |y| > 2^31', 100);
for (let i = 0; i < 500; i++) { const x = 1 + (rnd() * 2 - 1) * Math.pow(2, -20 - Math.floor(rnd() * 32)); P(rnd() < 0.2 ? -x : x, (rnd() < 0.5 ? -1 : 1) * Math.pow(2, 31 + rnd() * 34)); }
group('branch edges', Infinity);
for (const hw of [0x3988E, 0x3988F, 0xBB679, 0xBB67A, 0x0, 0xFFFFF]) {
  for (let i = 0; i < 4; i++) P(fromWords(0x3ff00000 | hw, u32()), (rnd() * 2 - 1) * 9);
}
for (const d of [0, 1, 2, 40]) { P(2, 1024 - d * Math.pow(2, -42)); P(2, -1075 + d * Math.pow(2, -42)); P(2, -1074.5 - d * Math.pow(2, -40)); }
for (const y of [2147483647, 2147483648, 2147483649, 2147483648.5, 18446744073709552000, 36893488147419103000]) {
  P(1 + Math.pow(2, -21), y); P(1 - Math.pow(2, -22), y); P(-1 - Math.pow(2, -21), y); P(1.5, -y);
}
for (const y of [0.5, -0.5, 0.49999999999999994, 0.5000000000000001]) { P(2, y); P(2, -y); P(10, y); }
group('positive x, |y| <= 64', 130);
for (let i = 0; i < 1000; i++) P(posFinite(), (rnd() * 2 - 1) * 64);
group('bit patterns', 130);
for (let i = 0; i < 1000; i++) P(fromWords(u32(), u32()), fromWords(u32(), u32()));

// ---------- log ----------
const logCands = [];
const L = x => logCands.push({ x, cat });
quotas = logQuotas;
group('special', Infinity);
for (const x of SPECIALS) L(x);
for (const x of [-1, -Infinity, -1e-310, 4294967296, 1e20, 0.1, 1e-300]) L(x);
group('sentinel', Infinity);
for (const x of [3, 10, 2, Math.E, 0.1, 100, 1000]) L(x);
group('powers of ten', Infinity);
for (let k = -323; k <= 308; k++) { const p = Math.pow(10, k); L(p); const n = Number('1e' + k); if (!Object.is(n, p)) L(n); }
group('powers of two', 150);
for (let k = -1074; k <= 1023; k += 7) L(Math.pow(2, k));
group('integers', 300);
for (let i = 1; i <= 2000; i++) L(i);
group('(0, 1000)', 450);
for (let i = 0; i < 3000; i++) L(rnd() * 1000);
group('x near 1', 450);
for (let i = 0; i < 1000; i++) L(1 + (rnd() * 2 - 1) * Math.pow(2, -1 - Math.floor(rnd() * 52)));
group('kernel discriminators', Infinity);
// Arguments where skipping log's |f| < 2**-20 shortcut, or its i > 0 kernel,
// changes the answer -- found by search against the transcription; without
// them either branch could be dropped unnoticed.
for (const x of [1.0000008225715646, 1.4182594537734987, 11.243495464324951, 0.1758315697312355,
  0.0000013515547405251738, 0.17682583630084991, 0.005479316553100944, 44.76166458129883,
  0.005398500571027399, 0.6949296414852143, 0.3485856994986534, 177.29486389160158, 1.409659504890442]) L(x);
group('branch edges', Infinity);
// hx + 0x95f64 crossing 0x100000 (normalize x or x/2), and the i = hx - 0x6147a,
// j = 0x6b851 - hx signs that pick the polynomial's form
for (const hw of [0x6a09b, 0x6a09c, 0x6a09d, 0x61479, 0x6147a, 0x6147b, 0x6b850, 0x6b851, 0x6b852, 0xffffd, 0xffffe, 0x0, 0x1, 0x2]) {
  for (const e of [0x3ff00000, 0x40900000, 0x00100000]) for (let i = 0; i < 2; i++) L(fromWords(e | hw, u32()));
}
group('subnormal', 200);
for (let i = 0; i < 500; i++) L(fromWords(u32() & 0x000fffff, u32()));
group('bit patterns', 450);
for (let i = 0; i < 3000; i++) L(posFinite());

// ---------- choose the rows ----------
function choose(cands, quotas, key, differs) {
  const seen = new Set();
  const uniq = cands.filter(c => { const k = key(c); if (seen.has(k)) return false; seen.add(k); return true; });
  const byCat = new Map();
  uniq.forEach(c => { (byCat.get(c.cat) || byCat.set(c.cat, []).get(c.cat)).push(c); });
  byCat.forEach((list, name) => {
    const q = quotas[name];
    const step = q >= list.length ? 1 : list.length / q;
    for (let i = 0; i < q && Math.floor(i * step) < list.length; i++) list[Math.floor(i * step)].keep = true;
  });
  uniq.forEach(c => { if (differs(c)) c.keep = true; });
  return uniq.filter(c => c.keep);
}
const pows = choose(powCands, powQuotas, c => hex(c.x) + hex(c.y), c => !same(F.powTextbook(c.x, c.y), Math.pow(c.x, c.y)));
const logs = choose(logCands, logQuotas, c => hex(c.x), () => false);

// ---------- self-checks 1-3 ----------
let textbookDiffers = 0;
pows.forEach(c => {
  const r = Math.pow(c.x, c.y);
  const t = F.pow(c.x, c.y);
  if (!same(r, t)) fail('pow(' + text(c.x) + ', ' + text(c.y) + '): Math.pow ' + hex(r) + ', the transcription ' + hex(t));
  if (!same(F.powTextbook(c.x, c.y), r)) textbookDiffers++;
  c.r = r;
});
logs.forEach(c => {
  const r = Math.log(c.x);
  const t = F.log(c.x);
  if (!same(r, t)) fail('log(' + text(c.x) + '): Math.log ' + hex(r) + ', the transcription ' + hex(t));
  c.r = r;
});
if (textbookDiffers < 300) fail('only ' + textbookDiffers + ' pow rows differ under the textbook r line');
[[10, -4, '3f1a36e2eb1c432c', true], [10, -307, '0031fa182c40c60e', true], [1.5, 1025, '656806d222b7eba6', true],
  [10, 2.5, '4073c3a4edfa9758', false], [2, 27.5, '41a6a09e667f3bcc', false]].forEach(([x, y, want, disc]) => {
  const row = pows.find(c => Object.is(c.x, x) && Object.is(c.y, y));
  if (!row) fail('sentinel pow(' + x + ', ' + y + ') is not in the rows');
  if (hex(Math.pow(x, y)) !== want) fail('sentinel pow(' + x + ', ' + y + ') = ' + hex(Math.pow(x, y)) + ', not ' + want);
  if ((hex(F.powTextbook(x, y)) !== want) !== disc) fail('sentinel pow(' + x + ', ' + y + '): textbook ' + hex(F.powTextbook(x, y)));
});

// ---------- self-check 5: a fresh draw ----------
{
  const s0 = s;
  s = 0x2545F491;
  const bits = () => fromWords(u32(), u32());
  let n = 0;
  let miss = 0;
  const chk = (a, b, what) => { n++; if (!same(a, b)) { miss++; if (miss <= 5) fail('fresh draw: ' + what); } };
  for (let i = 0; i < 100000; i++) {
    const a = bits(); chk(F.log(a), Math.log(a), 'log(' + a + ')');
    const b = rnd() * 1e4; chk(F.log(b), Math.log(b), 'log(' + b + ')');
    const c = 1 + (rnd() - 0.5) * 1e-6; chk(F.log(c), Math.log(c), 'log(' + c + ')');
    const k = Math.floor(rnd() * 60) - 30; const w = rnd() - 0.5;
    chk(F.pow(10, k + w), Math.pow(10, k + w), 'pow(10, ' + (k + w) + ')');
    const x = [2, 3, Math.E, 5, 7, 16, 0.5, 1.5, 100][i % 9]; const y = (rnd() - 0.5) * 80;
    chk(F.pow(x, y), Math.pow(x, y), 'pow(' + x + ', ' + y + ')');
    const x2 = bits(); const y2 = bits(); chk(F.pow(x2, y2), Math.pow(x2, y2), 'pow(' + x2 + ', ' + y2 + ')');
    const x3 = rnd() * 1000; const y3 = (rnd() - 0.5) * 20; chk(F.pow(x3, y3), Math.pow(x3, y3), 'pow(' + x3 + ', ' + y3 + ')');
  }
  if (miss) fail('fresh draw: ' + miss + ' of ' + n + ' differ');
  s = s0;
}

// ---------- write ----------
const count = (list) => { const m = {}; list.forEach(c => { m[c.cat] = (m[c.cat] || 0) + 1; }); return m; };
const out = {
  source: 'node ' + process.version + ' (V8 ' + process.versions.v8 + ') Math.pow / Math.log; ' + pows.length + ' pow rows ('
    + textbookDiffers + ' where fdlibm 5.3 differs), ' + logs.length + ' log rows',
  v8: process.versions.v8,
  pow: pows.map(c => [hex(c.x), hex(c.y), hex(c.r), text(c.x) + ', ' + text(c.y)]),
  log: logs.map(c => [hex(c.x), hex(c.r), text(c.x)]),
};
// one row per line
const rows = a => '[\n' + a.map(r => JSON.stringify(r)).join(',\n') + '\n]';
const json = '{\n"source": ' + JSON.stringify(out.source) + ',\n"v8": ' + JSON.stringify(out.v8)
  + ',\n"pow": ' + rows(out.pow) + ',\n"log": ' + rows(out.log) + '\n}\n';
JSON.parse(json);
fs.writeFileSync(OUT, json);
console.log('pow rows by category:', JSON.stringify(count(pows)));
console.log('log rows by category:', JSON.stringify(count(logs)));
console.log(pows.length + ' pow (' + textbookDiffers + ' textbook differs), ' + logs.length + ' log -> ' + OUT);
fails.forEach(f => console.log('self-check failed: ' + f));
if (fails.length) {
  console.log('FAILED: ' + fails.length + ' self-check(s)');
  process.exit(1);
}
process.exit(0);
