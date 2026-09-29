// Inputs for reflow-cases.js -- only inputs; every expected state comes from running
// xterm.js 6.0.0 headless. A case is { id, cols?, rows?, options?, steps } as in
// cases/core-hand.js (defaults 20 x 6); a step { s: "..." } writes that string as
// UTF-8; { resize: [c, r] }, { marker: n }, { scrollLines: n }, { setOption: {...} }
// are lib-term.js's. One criterion per case (spec 13.5 #8); the groups follow the
// phase 5 plan (5a, Task 2 Step 4). The recordings and the seeded random mixes are
// made by reflow-cases.js itself.
'use strict';

const E = '\x1b';
const CSI = E + '[';
const OSC = E + ']';
const BEL = '\x07';
const W = s => ({ s });
const R = (c, r) => ({ resize: [c, r] });
const WPTY = { backend: 'conpty', buildNumber: 19044 };

// a line of N printable ASCII characters, different at every position
const run = (n, from = 0) => Array.from({ length: n }, (_, i) => String.fromCharCode(33 + ((from + i) % 94))).join('');
const long170 = run(170);
const cs = (id, steps, extra = {}) => Object.assign({ id, steps: steps.map(x => (typeof x === 'string' ? W(x) : x)) }, extra);
const osc8 = (uri, text, id) => OSC + '8;' + (id ? 'id=' + id : '') + ';' + uri + BEL + text + OSC + '8;;' + BEL;
const lines = (n, from = 0) => Array.from({ length: n }, (_, i) => `row ${from + i} ` + run(30, (from + i) * 7)).join('\r\n');

const CASES = [
  // ---- 1. back and forth ----------------------------------------------------------
  // the cursor sits on the prompt after the long line: the long line itself rewraps
  cs('width-80-40-13-80', [long170 + '\r\n$ ', R(40, 24), R(13, 24), R(80, 24)], { cols: 80, rows: 24 }),
  cs('width-80-79-81-2-80', [long170 + '\r\n$ ', R(79, 24), R(81, 24), R(2, 24), R(80, 24)], { cols: 80, rows: 24 }),
  cs('width-rows-only', [long170 + '\r\n$ ', R(80, 10), R(80, 30), R(80, 24)], { cols: 80, rows: 24 }),
  cs('width-several-long-lines', [long170 + '\r\n' + run(95, 3) + '\r\nshort\r\n' + run(300, 9) + '\r\n$ ', R(33, 12), R(120, 12), R(47, 12)],
    { cols: 80, rows: 12 }),
  cs('width-cursor-at-the-end-of-the-long-line', [long170, R(40, 24), R(80, 24)], { cols: 80, rows: 24 }),

  // ---- 2. wide characters across the cut --------------------------------------------
  // a CJK character right at the old right edge (80 columns: 79 + 1 wide wraps early)
  cs('wide-at-the-old-edge', ['x'.repeat(79) + '中文字宽表中文字宽表\r\n$ ', R(90, 6), R(79, 6), R(80, 6)], { cols: 80, rows: 6 }),
  // exactly at the new edge: 40 columns of CJK then more
  cs('wide-at-the-new-edge', ['中'.repeat(20) + '文'.repeat(20) + '\r\n$ ', R(40, 6), R(41, 6), R(80, 6)], { cols: 80, rows: 6 }),
  // an odd width puts a wide character across every cut
  cs('wide-odd-widths', ['a' + '中文'.repeat(15) + 'b\r\n$ ', R(7, 12), R(9, 12), R(11, 12), R(80, 12)], { cols: 80, rows: 12 }),
  // the blank cell a wide character leaves when it wraps early, then wider again
  cs('wide-early-wrap-blank', ['abcdefghi中文字\r\n$ ', R(13, 6), R(20, 6), R(9, 6), R(10, 6)], { cols: 10, rows: 6 }),
  cs('wide-at-two-columns', ['中文ab字\r\n$ ', R(2, 8), R(3, 8), R(2, 8), R(20, 8)], { cols: 20, rows: 8 }),
  cs('wide-emoji', ['\u{1F600}'.repeat(30) + '\r\n$ ', R(13, 10), R(60, 10)], { cols: 40, rows: 10 }),

  // ---- 3. combining characters ----------------------------------------------------
  cs('combining-at-the-cut', ['abcdefghiéjklmnopqrsétuvwxyz\r\n$ ', R(10, 6), R(9, 6), R(30, 6)], { cols: 30, rows: 6 }),
  cs('combining-zwj-across', ['abcdefg\u{1F468}‍\u{1F469}‍\u{1F467}hijk\r\n$ ', R(8, 6), R(7, 6), R(20, 6)],
    { cols: 20, rows: 6, options: { unicodeVersion: '15-graphemes' } }),
  cs('combining-at-a-row-start', ['abcdefghij' + 'é̂' + 'klmn\r\n$ ', R(10, 6), R(11, 6), R(20, 6)], { cols: 20, rows: 6 }),

  // ---- 4. markers -----------------------------------------------------------------
  cs('markers-inside-a-run', [long170, { marker: 0 }, '\r\n', { marker: -1 }, '$ ', { marker: 0 }, R(40, 24), R(120, 24)],
    { cols: 80, rows: 24 }),
  cs('markers-after-a-run', [long170 + '\r\nafter\r\n', { marker: -1 }, { marker: 0 }, '$ ', R(40, 24), R(160, 24)], { cols: 80, rows: 24 }),
  cs('markers-in-the-scrollback', [lines(20) + '\r\n' + long170 + '\r\n$ ', { marker: -3 }, { marker: -12 }, R(30, 6), R(90, 6)],
    { cols: 80, rows: 6, options: { scrollback: 50 } }),
  cs('markers-pushed-out', [lines(4) + '\r\n' + long170 + '\r\n$ ', { marker: -5 }, { marker: -2 }, R(20, 6)],
    { cols: 80, rows: 6, options: { scrollback: 2 } }),
  cs('markers-deleted-on-widen', [run(60) + '\r\n$ ', R(20, 6), { marker: -1 }, { marker: -2 }, { marker: -3 }, R(60, 6)],
    { cols: 60, rows: 6 }),

  // ---- 5. OSC 8 links -------------------------------------------------------------
  cs('osc8-three-rows', ['go ' + osc8('http://a.com/x', run(50)) + ' end\r\n$ ', R(30, 8), R(15, 8), R(80, 8)], { cols: 20, rows: 8 }),
  cs('osc8-same-id-two-parts', [osc8('http://a.com', run(25), 'k') + ' mid ' + osc8('http://a.com', run(25, 40), 'k') + '\r\n$ ',
    R(12, 10), R(60, 10)], { cols: 30, rows: 10 }),
  cs('osc8-trimmed-out', [osc8('http://a.com', run(40)) + '\r\n' + lines(3) + '\r\n$ ', R(8, 6)], { cols: 40, rows: 6, options: { scrollback: 3 } }),

  // ---- 6. the cursor --------------------------------------------------------------
  cs('cursor-in-the-run-kept', ['$ abcdefghijKLM', R(20, 6)], { cols: 10, rows: 6 }),
  cs('cursor-in-the-run-reflowed', ['$ abcdefghijKLM', R(20, 6), R(5, 6)], { cols: 10, rows: 6, options: { reflowCursorLine: true } }),
  cs('cursor-after-the-run', ['$ abcdefghijKLM\r\n$ ', R(20, 6), R(5, 6)], { cols: 10, rows: 6 }),
  cs('cursor-row-moves-up', [run(30) + '\r\n' + run(30, 5) + '\r\n$ ', R(30, 10)], { cols: 10, rows: 10 }),
  cs('saved-cursor', [run(40) + '\r\nx' + E + '7' + '\r\n$ ', R(10, 10), E + '8Z', R(40, 10), E + '8Y'], { cols: 20, rows: 10 }),

  // ---- 7. a full scrollback ---------------------------------------------------------
  cs('full-scrollback-5-narrow', [lines(12) + '\r\n$ ', R(12, 6)], { cols: 40, rows: 6, options: { scrollback: 5 } }),
  cs('full-scrollback-10-narrow', [lines(20) + '\r\n$ ', R(9, 6), R(40, 6)], { cols: 40, rows: 6, options: { scrollback: 10 } }),
  cs('scrolled-up-narrow', [lines(20) + '\r\n$ ', { scrollLines: -3 }, R(15, 6)], { cols: 40, rows: 6, options: { scrollback: 30 } }),
  cs('scrolled-up-widen', [lines(20) + '\r\n$ ', R(15, 6), { scrollLines: -3 }, R(40, 6)], { cols: 40, rows: 6, options: { scrollback: 30 } }),

  // ---- 8. the alternate screen ------------------------------------------------------
  cs('alt-screen', [long170 + '\r\n$ ' + CSI + '?1049h' + run(100, 7), R(40, 10), R(100, 10), CSI + '?1049l', R(60, 10)],
    { cols: 80, rows: 10 }),

  // ---- 9. every Windows PTY setting upstream tells apart -------------------------------
  ...[['none', null], ['conpty-21375', { backend: 'conpty', buildNumber: 21375 }],
    ['conpty-21376', { backend: 'conpty', buildNumber: 21376 }], ['conpty-no-build', { backend: 'conpty' }],
    ['winpty-30000', { backend: 'winpty', buildNumber: 30000 }], ['no-backend-30000', { buildNumber: 30000 }],
  ].flatMap(([name, wp]) => [
    cs('windowspty-' + name, [long170 + '\r\n$ ', R(40, 10), R(80, 10)], { cols: 80, rows: 10, options: { windowsPty: wp } }),
    // written narrow, then wider: joined back only where upstream reflows
    cs('windowspty-' + name + '-widen', [long170 + '\r\n$ ', R(80, 10)], { cols: 40, rows: 10, options: { windowsPty: wp } }),
  ]),
  cs('windowspty-no-scrollback', [long170 + '\r\n$ ', R(40, 10), R(80, 10)], { cols: 80, rows: 10, options: { scrollback: 0 } }),
  // an old ConPTY leaves the lines longer than the grid; then the option goes and a resize rewraps them
  cs('windowspty-switched-off', [long170 + '\r\n$ ', R(40, 10), { setOption: { windowsPty: null } }, R(30, 10), R(80, 10)],
    { cols: 80, rows: 10, options: { windowsPty: WPTY } }),

  // ---- 10. phase 2 core cases that ran under an old ConPTY, in the default setup -------
  cs('decset-3-winlines-reflow', ['abc' + CSI + '?3hdef' + CSI + '?3lg'], { options: { windowOptions: ['setWinLines'] } }),
  cs('resize-min-reflow', ['abc', R(1, 0), 'x']),
  cs('resize-cols-winpty-reflow', [lines(6), R(10, 6), 'x', R(30, 6), 'y']),
  cs('resize-saved-cursor-reflow', [CSI + '3;18H' + E + '7', R(10, 6), E + '8x']),
];

module.exports = { CASES, RECORDINGS: ['ls-color', 'cat-cjk-emoji', 'git-log-color', 'vim-edit'] };
