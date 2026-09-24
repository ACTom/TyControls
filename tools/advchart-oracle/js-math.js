'use strict';
// What V8's Math.sin, cos, atan and atan2 answer, to the bit -- the answers
// tyControls.AdvChart.JsMath must give.
//
//   node tools/advchart-oracle/js-math.js
//
// writes tests/fixtures/advchart-js-math.json. Arguments are drawn from a
// seeded generator over every size a chart meets (and some it does not),
// plus the ones a quarter turn produces: pi, pi/2, 3 pi/2 and the not-quite
// noughts they leave behind. Past 2^19 pi/2 the port falls back to the
// run-time library, so no argument goes that far.
//
// Rows, doubles as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase), text = String(x):
//   unary    [x, sin, cos, atan, text]
//   atanOnly [x, atan, text]             (|x| > 823550)
//   atan2    [y, x, atan2(y, x), 'y, x']
//   tan      [x, tan, text]              a separate array, so unary keeps its
//            positional shape: every unary x with |x| <= 823550, then the
//            arguments fdlibm's tan (s_tan.c, k_tan.c) branches on -- 2 pi and
//            its neighbours, +-pi/2 one and two ulps either side, k pi for
//            k = 1..8, 0.6744 and its neighbours and 0.67434 (__kernel_tan's
//            big-argument branch), 2^-28 and its neighbours -- and the skews
//            a rotated axis label's decompose leaves (bcb0..., bca0...,
//            bcc0..., bc91a62633145c07). No x twice.
const fs = require('fs');
const path = require('path');

const buf = Buffer.alloc(8);
function hex(x) { buf.writeDoubleBE(x); return buf.toString('hex'); }

let s = 0x9E3779B9;
function rnd() {
  s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0;
  return s / 4294967296;
}

const ranges = [1e-12, 1e-8, 1e-4, 0.1, 0.5, 0.8, 1, 1.6, 2.4, 3.2, 4, 5, 6.3, 7,
  10, 50, 100, 1000, 1e4, 1e5, 8e5];
const PER = 150;

const specials = [0, -0, Math.PI, -Math.PI, Math.PI / 2, -Math.PI / 2,
  3 * Math.PI / 2, -3 * Math.PI / 2, 2 * Math.PI, Math.PI / 4, 3 * Math.PI / 4,
  5 * Math.PI / 4, 7 * Math.PI / 4, Math.PI / 6, Math.PI / 3, 4.71238898038469,
  5.497787143782138, 0.5235987755982988, 1.5707963267948968,
  6.123233995736766e-17, -6.123233995736766e-17, 1.2246467991473532e-16,
  -1.2246467991473532e-16, 1, -1, 2, 1e-300, 3e-9, 0.4375, 0.6875, 1.1875,
  2.4375, 7.3786976294838206e19, 1e20, Infinity, -Infinity];

const unary = [];
for (const x of specials) unary.push(x);
for (const R of ranges) for (let i = 0; i < PER; i++) unary.push((rnd() * 2 - 1) * R);

const pairs = [];
const pairSpecials = [0, -0, 1, -1, 6.123233995736766e-17, -6.123233995736766e-17,
  1.2246467991473532e-16, -1.2246467991473532e-16, 5, -5, 1e-70, -1e-70, 1e70,
  Infinity, -Infinity];
for (const y of pairSpecials) for (const x of pairSpecials) pairs.push([y, x]);
for (let i = 0; i < 3000; i++) {
  const ry = ranges[(rnd() * ranges.length) | 0];
  const rx = ranges[(rnd() * ranges.length) | 0];
  pairs.push([(rnd() * 2 - 1) * ry, (rnd() * 2 - 1) * rx]);
}

// tan: the unary arguments sin and cos are held to, then fdlibm's branch points
function fromHex(h) { return Buffer.from(h, 'hex').readDoubleBE(0); }
// n doubles up (d = +1, towards +Infinity) or down (d = -1); x finite, not 0
function step(x, d, n) {
  buf.writeDoubleBE(x);
  const b = buf.readBigInt64BE(0);
  buf.writeBigInt64BE(b + BigInt((x > 0 ? d : -d) * n));
  return buf.readDoubleBE(0);
}
const tanArgs = unary.filter(x => !(Math.abs(x) > 823550));
const TWO_PI = 2 * Math.PI;
tanArgs.push(TWO_PI, step(TWO_PI, -1, 1), step(TWO_PI, 1, 1));
for (const h of [Math.PI / 2, -Math.PI / 2]) {
  for (const n of [1, 2]) tanArgs.push(step(h, -1, n), step(h, 1, n));
}
for (let k = 1; k <= 8; k++) tanArgs.push(k * Math.PI);
tanArgs.push(0.6744, step(0.6744, -1, 1), step(0.6744, 1, 1), 0.67434);
tanArgs.push(Math.pow(2, -28), step(Math.pow(2, -28), -1, 1), step(Math.pow(2, -28), 1, 1));
for (const h of ['bcb0000000000000', 'bca0000000000000', 'bcc0000000000000', 'bc91a62633145c07']) tanArgs.push(fromHex(h));
// Every coefficient of __kernel_tan pulls on some bit only now and then, so
// a dense sweep of the kernel's own range [-pi/4, pi/4] -- half of it in the
// big-argument branch past 0.6744 -- and of whole turns, from a generator of
// its own, so the arrays above keep their rows.
let ts = 0x2545F491;
function trnd() {
  ts ^= ts << 13; ts >>>= 0; ts ^= ts >>> 17; ts ^= ts << 5; ts >>>= 0;
  return ts / 4294967296;
}
for (let i = 0; i < 8000; i++) tanArgs.push((trnd() * 2 - 1) * Math.PI / 4);
for (let i = 0; i < 8000; i++) tanArgs.push((trnd() < 0.5 ? -1 : 1) * (0.6744 + trnd() * (Math.PI / 4 - 0.6744)));
for (let i = 0; i < 4000; i++) tanArgs.push((trnd() * 2 - 1) * 20);
const tanSeen = new Set();
const tan = [];
for (const x of tanArgs) {
  const k = hex(x);
  if (tanSeen.has(k)) continue;
  tanSeen.add(k);
  tan.push([k, hex(Math.tan(x)), String(x)]);
}
// self-checks: the array is there, and every x reads back as the argument
// it was written from (and inside what sin and cos are held to)
if (tan.length === 0) throw new Error('js-math: no tan rows');
for (const [hx, ht, t] of tan) {
  const x = fromHex(hx);
  if (hex(x) !== hx || !(Math.abs(x) <= 823550) || hex(Math.tan(x)) !== ht || String(x) !== t) {
    throw new Error('js-math: tan row ' + hx + ' does not round-trip');
  }
}
// the neighbours are neighbours: one step apart, in order
for (const x of [TWO_PI, Math.PI / 2, -Math.PI / 2, 0.6744, Math.pow(2, -28)]) {
  const lo = step(x, -1, 1), hi = step(x, 1, 1);
  if (!(lo < x && x < hi) || step(lo, 1, 1) !== x || step(hi, -1, 1) !== x || !(step(x, -1, 2) < lo) || !(step(x, 1, 2) > hi)) {
    throw new Error('js-math: the neighbours of ' + x + ' are not');
  }
}
if (hex(TWO_PI) !== '401921fb54442d18') throw new Error('js-math: 2 pi is not 401921fb54442d18');

const out = {
  source: 'node ' + process.version + ' (V8 ' + process.versions.v8 + ') Math',
  unary: unary.filter(x => !(Math.abs(x) > 823550)).map(x => [hex(x), hex(Math.sin(x)),
    hex(Math.cos(x)), hex(Math.atan(x)), String(x)]),
  // atan is good for any argument, sin and cos are only held so far
  atanOnly: unary.filter(x => Math.abs(x) > 823550).map(x => [hex(x), hex(Math.atan(x)), String(x)]),
  atan2: pairs.map(([y, x]) => [hex(y), hex(x), hex(Math.atan2(y, x)), String(y) + ', ' + String(x)]),
  tan,
};
const file = path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-js-math.json');
fs.writeFileSync(file, JSON.stringify(out, null, 0) + '\n');
console.log(out.unary.length, 'unary,', out.atanOnly.length, 'atan only,', out.atan2.length, 'atan2,', out.tan.length, 'tan ->', file);
