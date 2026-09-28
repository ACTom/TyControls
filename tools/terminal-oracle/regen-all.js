// Reruns every oracle generator and checks the working tree afterwards: only the
// files lib-dump.js lists in GENERATED may have changed, and with --expect-clean
// not even those (spec 4.2: a rerun against the same upstream must leave
// `git diff` empty). A generated file that a rerun deletes (a fixture that went
// from parts back to one file) counts as a generated change too.
//
// The tree must be clean before the run -- otherwise a change made by hand could
// not be told from one the generators made. Commit or stash first.
//
//   node tools/terminal-oracle/regen-all.js [--expect-clean]
'use strict';
const cp = require('child_process');
const fs = require('fs');
const path = require('path');
const L = require('./lib-dump.js');

// Paths git reports as changed, deleted or untracked, repo-relative with forward
// slashes. -z: no quoting of unusual names; a rename record carries its source as
// an extra NUL-terminated field, skipped here.
function changedFiles() {
  const fields = cp.execFileSync('git', ['-C', L.ROOT, 'status', '--porcelain', '-z', '--untracked-files=all'],
    { encoding: 'utf8' }).split('\0');
  const out = [];
  for (let k = 0; k < fields.length; k++) {
    const f = fields[k];
    if (!f) continue;
    out.push(f.slice(3));
    if (f[0] === 'R' || f[0] === 'C') k++;
  }
  return out;
}

const before = changedFiles();
if (before.length) {
  console.error('the tree is not clean before the run (commit or stash first):\n  ' + before.join('\n  '));
  process.exit(1);
}

// In dependency order. A script not written yet is skipped, so the list can name
// the whole phase while it is being built.
const SCRIPTS = ['gen-unicode-tables.js', 'unicode-cases.js', 'parser-cases.js', 'buffer-cases.js',
  'gen-terminal-charsets.js', 'core-cases.js', 'escape-files.js', 'fuzz.js', 'recordings.js'];
for (const s of SCRIPTS) {
  if (!fs.existsSync(path.join(__dirname, s))) {
    console.log(`skip ${s} (not written yet)`);
    continue;
  }
  console.log('==', s);
  cp.execFileSync(process.execPath, [path.join(__dirname, s)], { stdio: 'inherit' });
}
const changed = changedFiles();
const stray = changed.filter(f => !L.isGenerated(f));
if (stray.length) { console.error('changed but not a generated file:\n  ' + stray.join('\n  ')); process.exit(1); }
if (process.argv.includes('--expect-clean') && changed.length) {
  console.error('the rerun changed:\n  ' + changed.join('\n  ')); process.exit(1);
}
console.log(changed.length ? 'changed (generated only): ' + changed.join(', ') : 'clean');
