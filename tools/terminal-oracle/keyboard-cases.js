// Writes the keyboard and paste fixtures for tests/test.terminal.keyboard.pas from
// xterm.js 6.0.0 (pin and loading in lib-dump.js). Inputs: cases/keyboard.js and the
// US_LAYOUT table below.
//
//   node tools/terminal-oracle/keyboard-cases.js
//
// tests/fixtures/terminal-keyboard.json
//   layout  US_LAYOUT as written here: [vk, key, shiftedKey, code]. The ONE source of
//           the table: the Pascal side's TyTerminalKeyEventFromLCL is held to it row
//           by row (TestLayoutMatchesTheFixture), so the sweep below and the port read
//           the same keys.
//   combos  [vk, mods, app, platform, type, cancel, keyB64 | null] for every layout row
//           x 16 modifier sets x application cursor off / on x platform, through
//           common/input/Keyboard.js evaluateKeyboardEvent. mods = shift | alt << 1 |
//           ctrl << 2 | meta << 3 (upstream's own `modifiers` bit order); platform 0 =
//           win (isMac false), 1 = mac, 2 = mac with macOptionIsMeta. The event's key
//           is the shiftedKey column when shift is in mods, the key column otherwise
//           (a browser's KeyboardEvent.key does not change under Ctrl or Alt).
//   hand    { id, ev, app, isMac, optMeta, type, cancel, key } for cases/keyboard.js's
//           hand events -- ones LCL cannot produce but the function has branches for
//           -- each with app off / on on the three platforms.
//   third   [vk, mods, altGraph, isMac, isWindows, optMeta, keypress, result] through
//           browser/CoreBrowserTerminal.js's _isThirdLevelShift, called on its
//           prototype with just the options it reads: every layout row x the 8
//           meta-less modifier sets x altGraph off x (win, mac, linux) x optMeta x
//           keydown / keypress, and cases/keyboard.js's altGraph keys with it on.
//           (CoreBrowserTerminal.js loads in node: nothing at its top level touches
//           the DOM.)
// tests/fixtures/terminal-paste.json
//   cases   [textB64, bracketed, outB64]: bracketTextForPaste(prepareTextForTerminal(
//           text), bracketed), the order browser/Clipboard.ts paste() calls them in.
//
// Strings are UTF-8 in base64. Reproducible: no time, fixed key order.
'use strict';
const path = require('path');
const L = require('./lib-dump.js');
const C = require('./cases/keyboard.js');

const up = L.loadUpstream();
const K = require(path.join(L.XTERM, L.OUT_DIR, 'common/input/Keyboard.js'));
const CB = require(path.join(L.XTERM, L.OUT_DIR, 'browser/Clipboard.js'));
const { CoreBrowserTerminal } = require(path.join(L.XTERM, L.OUT_DIR, 'browser/CoreBrowserTerminal.js'));

const b64 = s => Buffer.from(s, 'utf8').toString('base64');

// [vk, key, shiftedKey, code]; key / shiftedKey are browser KeyboardEvent.key values.
const US_LAYOUT = [
  [8, 'Backspace', 'Backspace', 'Backspace'],
  [9, 'Tab', 'Tab', 'Tab'],
  [13, 'Enter', 'Enter', 'Enter'],
  [16, 'Shift', 'Shift', 'ShiftLeft'],
  [17, 'Control', 'Control', 'ControlLeft'],
  [18, 'Alt', 'Alt', 'AltLeft'],
  [20, 'CapsLock', 'CapsLock', 'CapsLock'],
  [27, 'Escape', 'Escape', 'Escape'],
  [32, ' ', ' ', 'Space'],
  [33, 'PageUp', 'PageUp', 'PageUp'],
  [34, 'PageDown', 'PageDown', 'PageDown'],
  [35, 'End', 'End', 'End'],
  [36, 'Home', 'Home', 'Home'],
  [37, 'ArrowLeft', 'ArrowLeft', 'ArrowLeft'],
  [38, 'ArrowUp', 'ArrowUp', 'ArrowUp'],
  [39, 'ArrowRight', 'ArrowRight', 'ArrowRight'],
  [40, 'ArrowDown', 'ArrowDown', 'ArrowDown'],
  [45, 'Insert', 'Insert', 'Insert'],
  [46, 'Delete', 'Delete', 'Delete'],
  [48, '0', ')', 'Digit0'],
  [49, '1', '!', 'Digit1'],
  [50, '2', '@', 'Digit2'],
  [51, '3', '#', 'Digit3'],
  [52, '4', '$', 'Digit4'],
  [53, '5', '%', 'Digit5'],
  [54, '6', '^', 'Digit6'],
  [55, '7', '&', 'Digit7'],
  [56, '8', '*', 'Digit8'],
  [57, '9', '(', 'Digit9'],
  ...Array.from({ length: 26 }, (_, i) => {
    const lo = String.fromCharCode(97 + i), hi = String.fromCharCode(65 + i);
    return [65 + i, lo, hi, 'Key' + hi];
  }),
  [91, 'Meta', 'Meta', 'MetaLeft'],
  [93, 'ContextMenu', 'ContextMenu', 'ContextMenu'],
  ...Array.from({ length: 10 }, (_, i) => [96 + i, String(i), String(i), 'Numpad' + i]),
  [106, '*', '*', 'NumpadMultiply'],
  [107, '+', '+', 'NumpadAdd'],
  [109, '-', '-', 'NumpadSubtract'],
  [110, '.', '.', 'NumpadDecimal'],
  [111, '/', '/', 'NumpadDivide'],
  ...Array.from({ length: 12 }, (_, i) => [112 + i, 'F' + (i + 1), 'F' + (i + 1), 'F' + (i + 1)]),
  [144, 'NumLock', 'NumLock', 'NumLock'],
  [186, ';', ':', 'Semicolon'],
  [187, '=', '+', 'Equal'],
  [188, ',', '<', 'Comma'],
  [189, '-', '_', 'Minus'],
  [190, '.', '>', 'Period'],
  [191, '/', '?', 'Slash'],
  [192, '`', '~', 'Backquote'],
  [219, '[', '{', 'BracketLeft'],
  [220, '\\', '|', 'Backslash'],
  [221, ']', '}', 'BracketRight'],
  [222, '\'', '"', 'Quote'],
  [229, 'Process', 'Process', ''],
];

// ---- the table's own checks --------------------------------------------------------

const seen = new Set();
for (const [vk] of US_LAYOUT) {
  if (seen.has(vk)) throw new Error('VK ' + vk + ' twice in US_LAYOUT');
  seen.add(vk);
}
for (let k = 1; k < US_LAYOUT.length; k++) {
  if (US_LAYOUT[k][0] <= US_LAYOUT[k - 1][0]) throw new Error('US_LAYOUT not sorted at VK ' + US_LAYOUT[k][0]);
}
// The digit and symbol columns against upstream's KEYCODE_KEY_MAPPINGS, read out of
// the pinned source text (not copied by hand).
{
  const src = L.gitBlob('src/common/input/Keyboard.ts').toString('utf8');
  const block = src.match(/KEYCODE_KEY_MAPPINGS[^=]*=\s*\{([\s\S]*?)\n\};/);
  if (!block) throw new Error('KEYCODE_KEY_MAPPINGS not found in Keyboard.ts');
  const unq = s => s.slice(1, -1).replace(/\\(.)/g, '$1');
  const re = /(\d+):\s*\[('(?:\\.|[^'])*'),\s*('(?:\\.|[^'])*')\]/g;
  let m, n = 0;
  while ((m = re.exec(block[1])) !== null) {
    const vk = Number(m[1]);
    const row = US_LAYOUT.find(r => r[0] === vk);
    if (!row) throw new Error('KEYCODE_KEY_MAPPINGS has VK ' + vk + ', US_LAYOUT does not');
    if (row[1] !== unq(m[2]) || row[2] !== unq(m[3])) {
      throw new Error(`VK ${vk}: US_LAYOUT ${JSON.stringify([row[1], row[2]])}, upstream ${JSON.stringify([unq(m[2]), unq(m[3])])}`);
    }
    n++;
  }
  if (n !== 21) throw new Error('read ' + n + ' KEYCODE_KEY_MAPPINGS entries, expected 21');
}

// ---- evaluateKeyboardEvent -----------------------------------------------------------

const PLATFORMS = [{ isMac: false, optMeta: false }, { isMac: true, optMeta: false }, { isMac: true, optMeta: true }];

function evaluate(e, app, platform) {
  const r = K.evaluateKeyboardEvent({
    keyCode: e.keyCode, key: e.key, code: e.code,
    shiftKey: e.shift, altKey: e.alt, ctrlKey: e.ctrl, metaKey: e.meta, type: 'keydown',
  }, app, platform.isMac, platform.optMeta);
  if (![0, 1, 2, 3].includes(r.type)) throw new Error('result type ' + r.type);
  if (r.key !== undefined && typeof r.key !== 'string') throw new Error('result key ' + r.key);
  return r;
}

function layoutEvent(vk, mods) {
  const row = US_LAYOUT.find(r => r[0] === vk);
  const shift = (mods & 1) !== 0;
  return {
    keyCode: vk, key: row ? (shift ? row[2] : row[1]) : 'Unidentified', code: row ? row[3] : '',
    shift, alt: (mods & 2) !== 0, ctrl: (mods & 4) !== 0, meta: (mods & 8) !== 0,
  };
}

const combos = [];
for (const [vk] of US_LAYOUT) {
  for (let mods = 0; mods < 16; mods++) {
    for (const app of [false, true]) {
      PLATFORMS.forEach((p, pi) => {
        const r = evaluate(layoutEvent(vk, mods), app, p);
        combos.push([vk, mods, app ? 1 : 0, pi, r.type, r.cancel ? 1 : 0, r.key === undefined ? null : b64(r.key)]);
      });
    }
  }
}

const PLATFORM_NAMES = ['win', 'mac', 'macMeta'];
const hand = [];
for (const h of C.hand) {
  for (const app of [false, true]) {
    PLATFORMS.forEach((p, pi) => {
      const r = evaluate(h.ev, app, p);
      hand.push({ id: `${h.id}/app${app ? 1 : 0}/${PLATFORM_NAMES[pi]}`, ev: h.ev, app, isMac: p.isMac,
        optMeta: p.optMeta, type: r.type, cancel: r.cancel, key: r.key === undefined ? null : b64(r.key) });
    });
  }
}

// ---- _isThirdLevelShift --------------------------------------------------------------

const BROWSERS = [{ isMac: false, isWindows: true }, { isMac: true, isWindows: false }, { isMac: false, isWindows: false }];

function thirdLevel(e, altGraph, browser, optMeta, keypress) {
  const ev = {
    keyCode: e.keyCode, key: e.key, code: e.code,
    shiftKey: e.shift, altKey: e.alt, ctrlKey: e.ctrl, metaKey: e.meta,
    type: keypress ? 'keypress' : 'keydown',
    getModifierState: m => m === 'AltGraph' && altGraph,
  };
  const r = CoreBrowserTerminal.prototype._isThirdLevelShift.call({ options: { macOptionIsMeta: optMeta } }, browser, ev);
  // upstream returns the && / || chain's value: a boolean or a keyCode-ish falsy value
  return r ? 1 : 0;
}

function modsOf(s) {
  return (s.includes('S') ? 1 : 0) | (s.includes('A') ? 2 : 0) | (s.includes('C') ? 4 : 0) | (s.includes('M') ? 8 : 0);
}

const third = [];
function pushThird(vk, mods, altGraph) {
  for (const b of BROWSERS) {
    for (const optMeta of [false, true]) {
      for (const keypress of [false, true]) {
        third.push([vk, mods, altGraph ? 1 : 0, b.isMac ? 1 : 0, b.isWindows ? 1 : 0, optMeta ? 1 : 0, keypress ? 1 : 0,
          thirdLevel(layoutEvent(vk, mods), altGraph, b, optMeta, keypress)]);
      }
    }
  }
}
for (const [vk] of US_LAYOUT) for (let mods = 0; mods < 8; mods++) pushThird(vk, mods, false);
for (const [vk, m] of C.altGraph) pushThird(vk, modsOf(m), true);

// ---- paste ---------------------------------------------------------------------------

const paste = [];
for (const text of C.paste) {
  for (const bracketed of [false, true]) {
    paste.push([b64(text), bracketed ? 1 : 0, b64(CB.bracketTextForPaste(CB.prepareTextForTerminal(text), bracketed))]);
  }
}

const shell = kind => ({ upstream: up.info, generator: 'tools/terminal-oracle/keyboard-cases.js', kind });
L.writeFixture('terminal-keyboard.json', Object.assign(shell('keyboard'), { layout: US_LAYOUT, combos, hand, third }));
L.writeFixture('terminal-paste.json', Object.assign(shell('paste'), { cases: paste }));
const expectCombos = US_LAYOUT.length * 16 * 2 * 3;
if (combos.length !== expectCombos) throw new Error(`combos ${combos.length}, expected ${expectCombos}`);
console.log(`layout ${US_LAYOUT.length}, combos ${combos.length}, hand ${hand.length}, third ${third.length}, paste ${paste.length}`);
process.exit(0);
