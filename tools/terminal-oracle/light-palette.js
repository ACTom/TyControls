// The terminal's light-ground 16 colours: xterm.js 6.0.0's own contrast routine
// (src/common/Color.ts rgba.ensureContrastRatio) applied to its Tango defaults
// (src/browser/Types.ts DEFAULT_ANSI_COLORS) against white, 4.5:1. Upstream pin and
// loading: lib-dump.js.
//
//   node tools/terminal-oracle/light-palette.js [--check]
//
// 1-6 and 9-14 are darkened (ensureContrastRatio scales the RGB by 0.9 per step until
// the ratio holds, hue kept); 0 / 7 / 8 / 15 stay Tango -- black and white and their
// bright forms are left alone (plan, question one #3). The same function is what phase
// 5's MinimumContrastRatio ports; it is used here first.
//
// Prints i, Tango, the light-ground value and its contrast on white. --check reads
// themes/light.tycss and exits 1 unless every --terminal-ansi-<i> is written as
// on(var(--terminal-bg), <light-ground value>, <Tango>) with exactly these values.
'use strict';
const fs = require('fs');
const path = require('path');
const L = require('./lib-dump.js');

L.loadUpstream();
const C = require(path.join(L.XTERM, L.OUT_DIR, 'common/Color.js'));
const { DEFAULT_ANSI_COLORS } = require(path.join(L.XTERM, L.OUT_DIR, 'browser/Types.js'));

const WHITE = 0xFFFFFFFF;
const KEEP = new Set([0, 7, 8, 15]);
const hex = rgba => '#' + ((rgba >>> 8) & 0xFFFFFF).toString(16).padStart(6, '0');
const ratioOnWhite = rgba => C.contrastRatio(C.rgb.relativeLuminance(0xFFFFFF), C.rgb.relativeLuminance(rgba >>> 8));

const rows = [];
for (let i = 0; i < 16; i++) {
  const tango = DEFAULT_ANSI_COLORS[i].rgba >>> 0;
  let light = tango;
  if (!KEEP.has(i)) {
    const r = C.rgba.ensureContrastRatio(WHITE, tango, 4.5);
    if (r !== undefined) light = r >>> 0;
  }
  rows.push({ i, tango: hex(tango), light: hex(light), ratio: ratioOnWhite(light) });
}

for (const r of rows) {
  console.log(`${String(r.i).padStart(2)}  ${r.tango}  ->  ${r.light}  ${r.ratio.toFixed(2)}:1`);
}

if (process.argv.includes('--check')) {
  const css = fs.readFileSync(path.join(L.ROOT, 'themes', 'light.tycss'), 'utf8');
  let bad = 0;
  for (const r of rows) {
    const re = new RegExp(`--terminal-ansi-${r.i}\\s*:\\s*on\\(\\s*var\\(--terminal-bg\\)\\s*,\\s*(#[0-9a-fA-F]{6})\\s*,\\s*(#[0-9a-fA-F]{6})\\s*\\)\\s*;`);
    const m = css.match(re);
    if (!m) {
      console.error(`--terminal-ansi-${r.i}: not written as on(var(--terminal-bg), #light, #dark) in light.tycss`);
      bad++;
      continue;
    }
    if (m[1].toLowerCase() !== r.light || m[2].toLowerCase() !== r.tango) {
      console.error(`--terminal-ansi-${r.i}: light.tycss has ${m[1]}, ${m[2]}; computed ${r.light}, ${r.tango}`);
      bad++;
    }
  }
  if (bad) process.exit(1);
  console.log('light.tycss matches');
}
process.exit(0);
