// Writes tests/fixtures/terminal-view-palette.json from xterm.js 6.0.0 (pin and
// loading in lib-dump.js): DEFAULT_ANSI_COLORS of src/browser/Types.ts, the 16 Tango
// colours, the 6x6x6 cube and the 24 greys, as 0xRRGGBB numbers -- what the
// renderer's TyTermDefaultPaletteColor is held to.
//
//   node tools/terminal-oracle/view-cases.js
'use strict';
const path = require('path');
const L = require('./lib-dump.js');

const up = L.loadUpstream();
const { DEFAULT_ANSI_COLORS } = require(path.join(L.XTERM, L.OUT_DIR, 'browser/Types.js'));

if (DEFAULT_ANSI_COLORS.length !== 256) throw new Error('DEFAULT_ANSI_COLORS has ' + DEFAULT_ANSI_COLORS.length);
const ansi = DEFAULT_ANSI_COLORS.map(c => {
  if ((c.rgba & 0xFF) !== 0xFF) throw new Error('a translucent default colour: ' + c.css);
  return c.rgba >>> 8;
});
L.writeFixture('terminal-view-palette.json', {
  upstream: up.info, generator: 'tools/terminal-oracle/view-cases.js', kind: 'view-palette', ansi,
});
console.log(`palette ${ansi.length}`);
process.exit(0);
