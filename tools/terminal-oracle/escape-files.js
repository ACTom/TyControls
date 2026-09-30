// Writes tests/fixtures/terminal-core-escape.json (split into parts): every escape
// sequence file of xterm.js's own test fixtures run through xterm.js 6.0.0 headless.
// Upstream pin and loading: lib-dump.js, through lib-term.js.
//
//   node tools/terminal-oracle/escape-files.js
//
// SOURCE. The input bytes are xterm.js's test/fixtures/escape_sequence_files/*.in
// (and the three parked *.in_: t0031-HPB, t0200-SGR, t0220-SGR_inverse), MIT like
// the rest of xterm.js. 48 of the 76 .in files have namesakes in the test/ directory
// of MarkLodato/vt100-parser (MIT, Copyright (c) 2010 Mark Lodato), where they
// first come from; all are taken (THIRD-PARTY-NOTICES.md credits both). EXCLUDED is
// empty for that reason.
//
// NOTHING IS SKIPPED. Upstream's own test skips five of them
// (src/browser/Terminal2.test.ts:21-27): t0055-EL, t0084-CBT, t0101-NLM,
// t0103-reverse_wrap and t0504-vim, each because xterm.js's output differs from real
// xterm's .text there. The port is held to xterm.js, not to xterm, so that reason
// does not apply here, and these five are compared like the others.
//
// READ FROM GIT OBJECTS. With core.autocrlf the checkout holds these files with CRLF
// (git ls-files --eol: i/lf w/crlf); reading the working tree would make the
// fixture depend on the machine. lib-dump.js gitBlob() reads HEAD's blob instead.
//
// convertEol: true -- the files were captured to be shown through a terminal whose
// ONLCR turns LF into CR LF (upstream's test feeds them through a real PTY). 80 x 25.
//
// Each file is one case of one write, also fed one byte per parse call and cut in
// four random places (prng seeded by 5000 + the file's position); checkVariants
// proves upstream reaches the same state that way.
'use strict';
const cp = require('child_process');
const T = require('./lib-term.js');
const L = T.L;

const DIR = 'test/fixtures/escape_sequence_files/';
const EXCLUDED = [];

const up = T.loadUpstream();
const names = cp.execFileSync('git', ['-C', L.XTERM, 'ls-tree', '--name-only', 'HEAD', DIR], { encoding: 'utf8' })
  .split('\n').map(s => s.trim()).filter(s => /\.in_?$/.test(s)).map(s => s.slice(DIR.length))
  .filter(n => !EXCLUDED.includes(n)).sort();

(async () => {
  const cases = [];
  for (let k = 0; k < names.length; k++) {
    const bytes = L.gitBlob(DIR + names[k]);
    const c = {
      id: names[k], source: 'escape-file', cols: 80, rows: 25, options: { convertEol: true },
      steps: [{ write: T.b64(bytes) }],
      variants: [{ cuts: 'each' }, { cuts: T.randomCuts(T.prng(k + 5000), bytes.length, 4) }],
    };
    T.normalizeOptions(c);
    const r = await T.runCase(up, c);
    await T.checkVariants(up, c, r.expect);
    c.expect = r.expect;
    c.afterReset = r.afterReset;
    cases.push(c);
  }
  const files = T.writeCoreFixture('terminal-core-escape.json', 'core-escape', cases, 'escape-files.js');
  const total = cases.reduce((n, c) => n + T.unb64(c.steps[0].write).length, 0);
  console.log(`${cases.length} files, ${total} input bytes; fixture ${files.join(', ')}`);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
