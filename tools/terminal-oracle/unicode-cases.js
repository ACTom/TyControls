// Writes the three Unicode oracle fixtures for tests/test.unicode.width.pas, asking
// xterm.js 6.0.0's own UnicodeService (term._core.unicodeService, spec 4.5) -- never a
// provider directly -- under each of the six variants in lib-dump.js VARIANTS.
// Upstream path, pin and the Buffer-pool fix: lib-dump.js. Inputs: cases/unicode.js.
//
//   node tools/terminal-oracle/unicode-cases.js
//
// Every fixture starts with "upstream" (name, version, commit, commitDate),
// "generator" and "variants" (id, version, ambiguousWide). A run list is flat:
// [start0, value0, start1, value1, ...], each value holding up to the next start
// (the last one to U+10FFFF).
//
// tests/fixtures/terminal-unicode-width.json
//   "wcwidth":    variant id -> run list of svc.wcwidth over 0..0x10FFFF
//   "outOfRange": "codepoints" (three beyond U+10FFFF), and per variant id
//                 "wcwidth" [3] and "props0" [3] = charProperties(cp, 0)
//
// tests/fixtures/terminal-unicode-join.json
//   "preceding":  nine packed preceding states: 0, 2, 4, 8, then charProperties(x, 0)
//                 under 15-graphemes (ambiguous narrow) for x = 200D 1F1E6 600 1100
//                 1F600. The same nine numbers go to every variant -- any packed
//                 value is a legal input.
//   "props":      variant id -> nine run lists, charProperties(cp, preceding[k])
//
// tests/fixtures/terminal-unicode-cases.json
//   "sequences":  id, source "hand", codepoints, and "props": variant id -> the
//                 packed value after each step (preceding 0, then the last result)
//   "reps":       representative code points: the smallest one for each distinct
//                 15-table value, plus cases/unicode.js extraReps; ascending
//   "pairs":      variant id -> for (i, j) over reps in lexicographic order, the two
//                 step values, flattened
//   "triples":    '15-graphemes' variants only -> (i, j, k), three step values each
//   "strings":    id, source "hand", UTF-16 units, "width": variant id ->
//                 getStringCellWidth
'use strict';
const L = require('./lib-dump.js');
const C = require('./cases/unicode.js');

const up = L.loadUpstream();
L.checkTrieDecode(up);
const term = L.makeTerminal(up);
const head = { upstream: up.info, generator: 'tools/terminal-oracle/unicode-cases.js', variants: L.VARIANTS };

// The nine preceding states, computed once under 15-graphemes (ambiguous narrow).
const G = L.VARIANTS.find(v => v.id === '15-graphemes');
let svc = L.useVariant(term, G);
const P = x => svc.charProperties(x, 0);
const preceding = [0, 2, 4, 8, P(0x200D), P(0x1F1E6), P(0x600), P(0x1100), P(0x1F600)];
const EXPECT_P = [0x52, 0x9a, 0xa, 0x1ac, 0x1dc]; // measured when the plan was written
if (preceding.slice(4).join() !== EXPECT_P.join()) {
  throw new Error(`preceding states moved: ${preceding.slice(4).map(x => x.toString(16))} -- the 15 table or the loading changed`);
}

// Representative code points.
const firstOf = new Map();
for (let c = 0; c <= 0x10FFFF; c++) {
  const v = up.UC.getInfo(c);
  if (!firstOf.has(v)) firstOf.set(v, c);
}
const reps = [...new Set([...firstOf.values(), ...C.extraReps])].sort((a, b) => a - b);

function steps(s, cps) {
  const out = [];
  let prev = 0;
  for (const c of cps) { prev = s.charProperties(c, prev); out.push(prev); }
  return out;
}

const OOR = [0x110000, 0x1FFFFF, 0x7FFFFFFF];
const width = { ...head, wcwidth: {}, outOfRange: { codepoints: OOR, wcwidth: {}, props0: {} } };
const join = { ...head, preceding, props: {} };
const cases = {
  ...head,
  sequences: C.sequences.map(q => ({ id: q.id, source: 'hand', codepoints: q.codepoints, props: {} })),
  reps,
  pairs: {},
  triples: {},
  strings: C.strings.map(q => ({ id: q.id, source: 'hand', units: q.units, width: {} })),
};

let nPairs = 0, nTriples = 0;
for (const v of L.VARIANTS) {
  svc = L.useVariant(term, v);
  width.wcwidth[v.id] = L.runsOf(c => svc.wcwidth(c));
  width.outOfRange.wcwidth[v.id] = OOR.map(c => svc.wcwidth(c));
  width.outOfRange.props0[v.id] = OOR.map(c => svc.charProperties(c, 0));
  join.props[v.id] = preceding.map(p => L.runsOf(c => svc.charProperties(c, p)));
  cases.sequences.forEach((q, k) => { q.props[v.id] = steps(svc, C.sequences[k].codepoints); });
  const pairs = [];
  for (const a of reps) for (const b of reps) { pairs.push(...steps(svc, [a, b])); nPairs++; }
  cases.pairs[v.id] = pairs;
  if (v.version === '15-graphemes') {
    const triples = [];
    for (const a of reps) for (const b of reps) for (const c of reps) { triples.push(...steps(svc, [a, b, c])); nTriples++; }
    cases.triples[v.id] = triples;
  }
  cases.strings.forEach((q, k) => { q.width[v.id] = svc.getStringCellWidth(String.fromCharCode(...C.strings[k].units)); });
}

L.writeFixture('terminal-unicode-width.json', width);
L.writeFixture('terminal-unicode-join.json', join);
L.writeFixture('terminal-unicode-cases.json', cases);
console.log('reps', reps.length, 'pairs', nPairs, 'triples', nTriples,
  'sequences', cases.sequences.length, 'strings', cases.strings.length);
term.dispose();
process.exit(0);
