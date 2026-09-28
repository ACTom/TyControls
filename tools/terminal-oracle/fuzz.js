// Writes tests/fixtures/terminal-core-fuzz.json (split into parts): seeded random
// byte streams biased towards escape syntax, broken UTF-8 and control codes, run
// through xterm.js 6.0.0 headless with the final state as the expectation.
// Upstream pin and loading: lib-dump.js, through lib-term.js.
//
//   node tools/terminal-oracle/fuzz.js
//
// Seeds 1..300; 40 x 12, scrollback 50; the Unicode version turns with the seed
// (6, 11, 15, 15-graphemes). Runs of digits are at most four long, so no case asks
// upstream for billions of loop iterations (IL, DL, REP loop per repeat -- plan,
// verification notes 5 and 6). A seed upstream throws on has no answer (spec 13.5
// #6): it is dropped and listed in SKIPPED, here and in the output. Every fifth case
// is also fed cut in six random places.
'use strict';
const T = require('./lib-term.js');

const up = T.loadUpstream();
const VERSIONS = ['6', '11', '15', '15-graphemes'];
// Filled in by hand from the output when a seed is dropped: [seed, message].
const SKIPPED = [];

function utf8Of(cp) { return [...Buffer.from(String.fromCodePoint(cp), 'utf8')]; }

function fuzzBytes(rnd, n) {
  const out = [];
  const pick = list => list[Math.floor(rnd() * list.length)];
  while (out.length < n) {
    const r = rnd() * 100;
    if (r < 12) out.push(0x1b);
    else if (r < 22) out.push(0x5b);
    else if (r < 24) out.push(0x5d);
    else if (r < 25) out.push(0x50);
    else if (r < 26) out.push(0x5f);
    else if (r < 34) out.push(0x3b);
    else if (r < 36) out.push(0x3a);
    else if (r < 54) { const d = 1 + Math.floor(rnd() * 4); for (let k = 0; k < d; k++) out.push(0x30 + Math.floor(rnd() * 10)); }
    else if (r < 68) out.push(0x40 + Math.floor(rnd() * 0x3f));
    else if (r < 75) out.push(Math.floor(rnd() * 0x20));
    else if (r < 83) {
      const kind = Math.floor(rnd() * 3);
      let cp = pick([0xa0 + Math.floor(rnd() * 0x760), 0x800 + Math.floor(rnd() * 0xF800), 0x10000 + Math.floor(rnd() * 0x100000)]);
      if (cp >= 0xD800 && cp <= 0xDFFF) cp = 0x4e2d;
      const bytes = utf8Of(cp);
      if (kind === 0) out.push(...bytes);
      else if (kind === 1) out.push(...bytes.slice(0, Math.max(1, bytes.length - 1)));
      else out.push(pick([0x80, 0xbf, 0xc0, 0xc1, 0xf5, 0xf8, 0xfe, 0xff]));
    } else if (r < 86) out.push(0x3c + Math.floor(rnd() * 4));
    else if (r < 98) out.push(0x20 + Math.floor(rnd() * 0x5f));
    else out.push(0x7f + Math.floor(rnd() * 0x21));
  }
  return out.slice(0, n);
}

(async () => {
  const cases = [];
  const skipped = [];
  for (let seed = 1; seed <= 300; seed++) {
    const rnd = T.prng(seed);
    const bytes = Buffer.from(fuzzBytes(rnd, 512 + Math.floor(rnd() * (4096 - 512 + 1))));
    const c = { id: 'fuzz-' + seed, source: 'fuzz', seed, cols: 40, rows: 12,
      options: { scrollback: 50, unicodeVersion: VERSIONS[seed % 4] }, steps: [{ write: T.b64(bytes) }] };
    if (seed % 5 === 0) c.variants = [{ cuts: T.randomCuts(rnd, bytes.length, 6) }];
    T.normalizeOptions(c);
    try {
      const r = await T.runCase(up, c);
      await T.checkVariants(up, c, r.expect);
      c.expect = r.expect;
      c.afterReset = r.afterReset;
      cases.push(c);
    } catch (e) {
      skipped.push([seed, e.message]);
      console.log(`skip seed ${seed}: ${e.message}`);
    }
  }
  const files = T.writeCoreFixture('terminal-core-fuzz.json', 'core-fuzz', cases, 'fuzz.js');
  console.log(`${cases.length} cases, ${skipped.length} skipped (listed in SKIPPED: ${SKIPPED.length}); files ${files.join(', ')}`);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
