// Reruns every oracle generator and checks the working tree afterwards: only the
// files lib-dump.js lists in GENERATED may have changed, and with --expect-clean
// not even those (spec 4.2: a rerun against the same upstream must leave
// `git diff` empty).
//
//   node tools/terminal-oracle/regen-all.js [--expect-clean]
'use strict';
const cp = require('child_process');
const path = require('path');
const L = require('./lib-dump.js');

const SCRIPTS = ['gen-unicode-tables.js', 'unicode-cases.js'];
for (const s of SCRIPTS) {
  console.log('==', s);
  cp.execFileSync(process.execPath, [path.join(__dirname, s)], { stdio: 'inherit' });
}
const changed = cp.execFileSync('git', ['-C', L.ROOT, 'status', '--porcelain'], { encoding: 'utf8' })
  .split(/\r?\n/).filter(Boolean).map(l => l.slice(3).replace(/\\/g, '/'));
const stray = changed.filter(f => !L.GENERATED.includes(f));
if (stray.length) { console.error('changed but not a generated file:\n  ' + stray.join('\n  ')); process.exit(1); }
if (process.argv.includes('--expect-clean') && changed.length) {
  console.error('the rerun changed:\n  ' + changed.join('\n  ')); process.exit(1);
}
console.log(changed.length ? 'changed (generated only): ' + changed.join(', ') : 'clean');
