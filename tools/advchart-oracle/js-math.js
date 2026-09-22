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

const out = {
  source: 'node ' + process.version + ' (V8 ' + process.versions.v8 + ') Math',
  unary: unary.filter(x => !(Math.abs(x) > 823550)).map(x => [hex(x), hex(Math.sin(x)),
    hex(Math.cos(x)), hex(Math.atan(x)), String(x)]),
  // atan is good for any argument, sin and cos are only held so far
  atanOnly: unary.filter(x => Math.abs(x) > 823550).map(x => [hex(x), hex(Math.atan(x)), String(x)]),
  atan2: pairs.map(([y, x]) => [hex(y), hex(x), hex(Math.atan2(y, x)), String(y) + ', ' + String(x)]),
};
const file = path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-js-math.json');
fs.writeFileSync(file, JSON.stringify(out, null, 0) + '\n');
console.log(out.unary.length, 'unary,', out.atanOnly.length, 'atan only,', out.atan2.length, 'atan2 ->', file);
