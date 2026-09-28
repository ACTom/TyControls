// Writes tests/fixtures/terminal-core-recording.json (split into parts): real
// program sessions replayed through xterm.js 6.0.0 headless. Upstream pin and
// loading: lib-dump.js, through lib-term.js.
//
//   node tools/terminal-oracle/recordings.js
//
// The inputs are recordings/*.cast (asciicast v2), made in WSL through tmux with a
// scrubbed environment by wsl-record.sh from the recordings/*.keys next to them: vim,
// less, htop, git log, ls, a Python REPL, nested tmux and a CJK and emoji file.
// Each "o" event becomes one write step, UTF-8 encoded -- the event boundaries are
// where the program's output was cut, so they are the chunk boundaries too. The size
// comes from the header; scrollback 200, Unicode 11.
'use strict';
const fs = require('fs');
const path = require('path');
const T = require('./lib-term.js');

const up = T.loadUpstream();
const DIR = path.join(__dirname, 'recordings');
const MAX_CAST = 256 * 1024;   // spec 17.2 #8

(async () => {
  const names = fs.readdirSync(DIR).filter(f => f.endsWith('.cast')).sort();
  const cases = [];
  for (const name of names) {
    const text = fs.readFileSync(path.join(DIR, name), 'utf8').replace(/\r\n/g, '\n');
    if (Buffer.byteLength(text) > MAX_CAST) throw new Error(`${name} is over 256 KB`);
    const rows = text.split('\n').filter(Boolean).map(l => JSON.parse(l));
    const head = rows.shift();
    const steps = rows.filter(r => r[1] === 'o').map(r => ({ write: T.b64(T.utf8(r[2])) }));
    const c = { id: name.replace(/\.cast$/, ''), source: 'recording', cols: head.width, rows: head.height,
      options: { scrollback: 200, unicodeVersion: '11' }, steps };
    T.normalizeOptions(c);
    const r = await T.runCase(up, c);
    c.expect = r.expect;
    c.afterReset = r.afterReset;
    cases.push(c);
  }
  const files = T.writeCoreFixture('terminal-core-recording.json', 'core-recording', cases, 'recordings.js');
  console.log(`${cases.length} recordings; files ${files.join(', ')}`);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
