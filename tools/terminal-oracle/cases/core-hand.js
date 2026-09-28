// Inputs for core-cases.js -- only inputs; every expected state comes from running
// xterm.js 6.0.0 headless. A case is { id, cols?, rows?, options?, synth?, steps }
// (defaults 20 x 6, options as lib-term.js DEFAULT_OPTIONS); a step { s: "..." } is a
// write of that JS string as UTF-8, the other steps are the plan's ("夹具格式").
// The comment on each group names the upstream lines it holds (InputHandler.ts unless
// said otherwise).
'use strict';

const E = '\x1b';
const CSI = E + '[';
const OSC = E + ']';
const DCS = E + 'P';
const ST = E + '\\';
const BEL = '\x07';
const W = s => ({ s });
const WPTY = { backend: 'conpty', buildNumber: 19044 };
const digits20 = '99999999999999999999';

// ROWS lines of text, CR LF between them
const lines = (n, from = 0) => Array.from({ length: n }, (_, i) => `line ${from + i} ${String.fromCharCode(97 + ((from + i) % 26)).repeat(4)}`).join('\r\n');
const fill = (rows = 6) => lines(rows);
const c1 = (id, s, extra = {}) => Object.assign({ id, steps: [W(s)] }, extra);
const cs = (id, steps, extra = {}) => Object.assign({ id, steps: steps.map(x => (typeof x === 'string' ? W(x) : x)) }, extra);

const CHARSET_KEYS = ['0', '4', '5', '6', '7', 'A', 'B', 'C', 'R', 'Q', 'K', 'Y', 'E', 'Z', 'H', '='];
const printable = Array.from({ length: 95 }, (_, i) => String.fromCharCode(0x20 + i)).join('');
const UNI = [['6', '6', false], ['11', '11', false], ['15', '15', false], ['15-amb', '15', true],
  ['15-graphemes', '15-graphemes', false], ['15-graphemes-amb', '15-graphemes', true]];
const uniText = 'é|é|中|\u{1F600}|\u{1F1E8}\u{1F1F3}|\u{1F468}‍\u{1F469}‍\u{1F467}|…|☺️';

const DECSET = [1, 6, 7, 12, 25, 45, 66, 1004, 2004, 2026, 2031, 9001];
const DECRQM_PRIVATE = [1, 3, 6, 7, 8, 9, 12, 25, 45, 47, 66, 67, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016, 1047, 1048, 1049, 2004, 2026, 9001, 9999];

const hand = [
  // ---- printing: print :517-661 ----
  c1('print-ascii', 'Hello, world'),
  c1('print-wrap-pending', 'abcdefghij', { cols: 10 }),
  c1('print-wrap-next', 'abcdefghijk', { cols: 10 }),
  c1('print-nowrap', CSI + '?7labcdefghijklm', { cols: 10 }),
  c1('print-wide-edge', 'abcdefghi中x', { cols: 10 }),                  // :582-617 wrap before a wide char
  c1('print-wide-nowrap', CSI + '?7labcdefghi中x', { cols: 10 }),     // :611-617 skipped
  c1('print-over-wide-half', '中文' + CSI + '1;2Hx', { cols: 10 }), // :537-539
  c1('print-wide-right-reset', '中文' + CSI + 'Hx', { cols: 10 }), // :652-655
  c1('combine-at-line-start', '́ab\ŕc'),                        // shouldJoin at x = 0
  c1('combine-after-wide', '中́x'),
  c1('combine-across-wrap', 'abcde☺️z', { cols: 6, options: { unicodeVersion: '15-graphemes' } }), // :596-601
  c1('combine-width-grow', 'a☺️b', { options: { unicodeVersion: '15-graphemes' } }),           // :627-629
  c1('soft-hyphen', 'a­b­'),                                     // :546-548
  c1('insert-mode', 'abcdefghij' + CSI + 'H' + CSI + '4hXY' + CSI + '1;9H中', { cols: 10 }), // :632-642
  c1('insert-mode-reset', CSI + '4hab' + CSI + '4l' + CSI + 'HZ'),
  // ---- charsets :3323-3360, :1939-1945, :2994-3029 ----
  c1('charset-dec-graphics', E + '(0lqkxjm' + E + '(Blq'),
  ...CHARSET_KEYS.map(k => c1('charset-each-' + (k === '=' ? 'eq' : k), E + '(' + k + printable, { cols: 20, rows: 6 })),
  c1('charset-so-si', E + ')0\x0eq\x0fq'),
  c1('charset-ls2-ls3', E + '*0' + E + 'nq' + E + '+A' + E + 'o#' + E + '|#' + E + '}q' + E + '~q'),
  c1('charset-slash', E + '/A#' + E + '-0' + E + '.A\x0eq'),
  c1('charset-default', E + '(0q' + E + '%Gq' + E + '(0' + E + '%@q'),
  c1('charset-decset2', E + '(0' + E + ')0' + CSI + '?2hq\x0eq'),
  c1('charset-saved', E + ')0\x0e' + E + '7\x0f' + E + '(A' + E + '8q#'),
  c1('charset-unknown-key', E + '(0' + E + '(!q' + E + '(Xq'),
  ...UNI.map(([id, v, amb]) => c1('unicode-' + id, uniText, { cols: 8, options: { unicodeVersion: v, ambiguousWide: amb } })),
  // ---- controls ----
  c1('bel-count', '\x07\x07a\x07'),                                        // :727-730
  c1('bs-basic', 'abc\x08\x08X'),                                          // :793-806
  c1('bs-at-0', '\x08\x08X'),
  c1('bs-pending-wrap', 'abcdefghij\x08X', { cols: 10 }),
  c1('bs-reverse-wrap', CSI + '?45habcdefghi中\r\x08\x08Xabcdefghijk\r\x08Y', { cols: 10 }), // :822-843
  c1('bs-reverse-not-wrapped', CSI + '?45habc\r\n\x08X'),
  c1('bs-reverse-at-top-margin', CSI + '?45h' + CSI + '2;4r' + CSI + '2;1Habcdefghijkl' + CSI + '2;1H\x08X' + CSI + '3;1H\x08Y', { cols: 10 }),
  c1('ht-default', 'a\tb\tc'),                                             // :850-860
  c1('ht-at-end', 'abcdefghij\tX', { cols: 10 }),
  c1('ht-after-tbc', CSI + '3g\tX' + CSI + '1;5H' + E + 'H' + CSI + 'H\tY'),
  c1('lf-basic', 'a\nb\r\nc'),                                             // :742-771
  c1('lf-clears-wrapped', 'abcdefghijkl' + CSI + 'H\n', { cols: 10 }),
  c1('lf-pending-wrap', 'abcdefghij\nX', { cols: 10 }),
  c1('vt-ff', 'a\x0bb\x0cc'),
  c1('lf-converteol', 'ab\ncd\n', { options: { convertEol: true } }),
  c1('lnm', 'a\nb' + CSI + '20hc\nd' + CSI + '20le\nf'),                 // :1804-1816
  c1('cr', 'abc\rX'),
  c1('c1-ind-nel-hts', 'ab\u0084c\u0085d\u0088' + CSI + 'H\tz'),        // :3287-3395
  // ---- cursor :930-1097 ----
  c1('cuu-cud-cuf-cub', CSI + '3;5H' + CSI + 'Aa' + CSI + '0Ab' + CSI + '2Bc' + CSI + '99Cd' + CSI + '2De' + CSI + '99Af'),
  c1('cuu-stop-at-margin', CSI + '2;5r' + CSI + '4;1H' + CSI + '9Aa' + CSI + '1;1H' + CSI + '9Ab' + CSI + '6;1H' + CSI + '9Ac' + CSI + '3;1H' + CSI + '9Bd' + CSI + '6;1H' + CSI + '9Be'),
  c1('cnl-cpl', CSI + '3;4H' + CSI + '2Ex' + CSI + 'Fy' + CSI + '9Ez'),
  c1('cha-hpa', CSI + '5Gx' + CSI + '3`y' + CSI + '99Gz' + CSI + 'Gw'),
  c1('cup', CSI + 'Ha' + CSI + '3Hb' + CSI + '2;4Hc' + CSI + '99;99Hd' + CSI + ';5He' + CSI + '0;0Hf'),
  c1('hvp', CSI + '2;3fx' + CSI + 'fy'),
  c1('vpa-vpr-hpr', CSI + '4dx' + CSI + '2ey' + CSI + '3az' + CSI + '99ew'),
  c1('cursor-huge-params', ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'd', 'e', 'a', '`', 'f'].map(f => CSI + '3;3H' + CSI + digits20 + f + 'x').join('')
    + CSI + digits20 + ';' + digits20 + 'Hy'),
  // one relative move each: x or y plus 2^31 - 1 must not wrap (a later absolute move
  // in cursor-huge-params lands on the same cell and hides it)
  c1('cursor-huge-cuf', CSI + '3;3H' + CSI + digits20 + 'Cx'),
  c1('cursor-huge-hpr', CSI + '3;3H' + CSI + digits20 + 'ax'),
  c1('cursor-huge-vpr', CSI + '3;3H' + CSI + digits20 + 'ex'),
  c1('origin-mode', CSI + '3;5r' + CSI + '?6h' + CSI + '2;3Hx' + CSI + '9;9Hy' + CSI + 'Az' + CSI + '?6lw'),  // :889-921, :1972-1975
  c1('decsc-decrc', CSI + '1;31m' + CSI + '2;3H' + E + '7' + CSI + '0m' + CSI + '?7l' + CSI + 'Ha' + E + '8b' + CSI + '?6h' + CSI + 's' + CSI + '?6l' + CSI + '5;5Hc' + CSI + 'ud'),
  cs('decrc-without-save', [lines(10), CSI + '3;3H' + E + '8x']),
  // ---- erase, insert/delete, scroll :1229-1678 ----
  cs('ed-0', [fill(), CSI + '3;5H' + CSI + 'J']),
  cs('ed-1', [fill(), CSI + '3;5H' + CSI + '1J']),
  cs('ed-2', [fill(), CSI + '2J']),
  cs('ed-3', [lines(12), CSI + '3J']),
  cs('ed-2-scroll-on-erase', [lines(4), CSI + '2J', lines(12), CSI + '2J'], { options: { scrollOnEraseInDisplay: true } }),  // :1260-1272
  cs('ed-3-scrollback', [lines(12), { scrollLines: -2 }, CSI + '3J']),
  c1('ed-pending-wrap', 'abcdefghij' + CSI + 'J', { cols: 10 }),
  c1('ed-1-wraps', 'abcdefghijklmnop' + CSI + '1;10H' + CSI + '1J', { cols: 10 }),  // :1247-1253
  cs('ed-1-wraps-scrolled', [lines(8), '\r\nabcdefghijklmnop' + CSI + '5;10H' + CSI + '1J'], { cols: 10 }),
  c1('el-0', 'abcdefghij' + CSI + '1;5H' + CSI + 'K'),
  c1('el-1', 'abcdefghij' + CSI + '1;5H' + CSI + '1K'),
  c1('el-2', 'abcdefghij' + CSI + '1;5H' + CSI + '2K'),
  c1('el-clears-wrapped', 'abcdefghijklmnopqrstuvw' + CSI + '2;1H' + CSI + 'K' + CSI + '3;4H' + CSI + '2K', { cols: 10 }),  // :1324-1340
  c1('decsca-decsel-decsed', 'ab' + CSI + '1"qcd' + CSI + '0"qef\r\ngh' + CSI + '1"qij' + CSI + '2"qkl' + CSI + '1;1H' + CSI + '?K' + CSI + '2;3H' + CSI + '?J' + CSI + 'K'),  // :1158-1163
  c1('ech', 'abcdefghij' + CSI + '1;3H' + CSI + 'X' + CSI + '1;5H' + CSI + '3X' + CSI + '1;3H' + CSI + digits20 + 'X'),  // :1614-1626
  c1('bce', CSI + '44mabc' + CSI + '1;2H' + CSI + 'K' + CSI + '2;1H' + CSI + '2X' + CSI + 'L' + CSI + '@' + CSI + 'J'),  // :3441-3445
  c1('ich-dch', 'a中b中c' + CSI + '1;3H' + CSI + '@' + CSI + '1;2H' + CSI + 'P' + CSI + '1;5H' + CSI + '2P'),
  cs('il-dl', [fill(), CSI + '2;4r' + CSI + '3;1H' + CSI + 'L' + CSI + '2M' + CSI + '6;1H' + CSI + 'L' + CSI + '1;1H' + CSI + 'M']),
  cs('il-dl-1000', [fill(), CSI + '2;5r' + CSI + '3;1H' + CSI + '1000L' + CSI + '4;1Hx' + CSI + '1000M']),
  cs('su-sd', [fill(), CSI + '2S' + CSI + 'T' + CSI + '2;4r' + CSI + 'S' + CSI + '2T']),
  cs('su-sd-1000', [fill(), CSI + '2;4r' + CSI + '1000S' + CSI + '1000T' + CSI + 'r' + CSI + '1000S' + CSI + '1000^']),
  cs('sd-default-attr', [fill(), CSI + '44m' + CSI + '2T' + CSI + '2S']),   // :1489
  cs('sd-default-attr-alone', [fill(), CSI + '44m' + CSI + '2T']),           // the SU above scrolls SD's lines away
  cs('sl-sr', [fill(), CSI + '2 @' + CSI + '2 A' + CSI + '2;3r' + CSI + '5;1H' + CSI + ' @' + CSI + '2;1H' + CSI + '3 A']),
  cs('decic-decdc', [fill(), CSI + '1;3H' + CSI + "2'}" + CSI + "2'~" + CSI + '2;4r' + CSI + '6;1H' + CSI + "'}"]),
  c1('cht-cbt', CSI + 'Ia' + CSI + '3Ib' + CSI + '1000Ic' + CSI + 'Zd' + CSI + '3Z' + CSI + '1000Ze', { cols: 40 }),  // :1125-1150
  c1('cht-at-end', 'abcdefghij' + CSI + 'Ix' + CSI + 'Zy', { cols: 10 }),
  c1('rep-ascii', 'a' + CSI + '3b'),                                       // :1654-1678
  c1('rep-wide', '中' + CSI + '2b'),
  c1('rep-grapheme', '\u{1F468}‍\u{1F469}‍\u{1F467}' + CSI + '2b', { options: { unicodeVersion: '15-graphemes' } }),
  c1('rep-combined', 'é' + CSI + '2b', { options: { unicodeVersion: '15-graphemes' } }),
  c1('rep-after-control', 'a\r' + CSI + '3b'),
  c1('rep-zero', 'a' + CSI + '0b'),
  c1('rep-wrap', 'abcdefghx' + CSI + '5b', { cols: 10 }),
  c1('rep-nowrap-wide', CSI + '?7l中' + CSI + '9b', { cols: 10 }),
  c1('decaln', 'abcdefghijklmnop' + CSI + '31;44m' + CSI + '3;3H' + E + '#8' + CSI + '0mx', { cols: 10 }),  // :3470-3494
  cs('ri-top-margin', [fill(), CSI + '2;5r' + CSI + '2;1H' + E + 'M' + E + 'M']),  // :3366-3419
  cs('ri-mid', [fill(), CSI + '4;1H' + E + 'Mx' + CSI + '1;1H' + E + 'My']),
  cs('ind-bottom', [fill(), CSI + '6;1H' + E + 'D' + E + 'Dz' + CSI + '2;4r' + CSI + '4;1H' + E + 'D']),
  c1('nel', 'ab' + E + 'Ec' + E + 'E'),
  // ---- scroll region :2890-2905 and scrollback ----
  c1('decstbm-valid', 'abc' + CSI + '2;4rx'),
  c1('decstbm-invalid', 'abc' + CSI + '3;99rx' + CSI + '3;0ry' + CSI + '4;4rz' + CSI + '5;3rw' + CSI + 'rv'),
  c1('lf-in-region', CSI + '2;4r' + CSI + '4;1Ha\nb\nc'),
  c1('lf-region-top-0', CSI + '1;4r' + CSI + '4;1Ha\nb\nc'),
  c1('scrollback-full', lines(20), { options: { scrollback: 3 } }),
  cs('user-scrolled-output', [lines(12), { scrollLines: -2 }, '\r\n' + lines(3, 20)]),
  cs('user-scrolled-full', [lines(12), { scrollLines: -2 }, '\r\n' + lines(2, 20)], { options: { scrollback: 3 } }),
  cs('scroll-steps', [lines(20), { scrollLines: -3 }, { scrollToTop: 1 }, { scrollLines: 2 }, { scrollToBottom: 1 }, { scrollLines: -1 }]),
  cs('input-scrolls-to-bottom', [lines(20), { scrollLines: -5 }, { input: 'x', user: false }, { input: 'y', user: true }]),
  cs('input-no-scroll-option', [lines(20), { scrollLines: -5 }, { input: 'y', user: true }], { options: { scrollOnUserInput: false } }),
  cs('input-disabled', [{ input: 'x', user: true }, 'a'], { options: { disableStdin: true } }),
  cs('input-utf8', [{ input: '中\u{1F600}', user: true }]),
  cs('clear-step', [lines(20) + '\r\nprompt', { clear: 1 }, 'x']),
  // ---- tabs :1109-1119, :3389-3392 ----
  c1('tbc-0-3', '\tX' + CSI + '1;9H' + CSI + '0g' + CSI + 'H\tY' + CSI + '3g' + CSI + 'H\tZ'),
  c1('hts', CSI + '1;4H' + E + 'H' + CSI + 'H\tX\tY'),
  c1('hts-pending-wrap', 'abcdefghij' + E + 'H', { cols: 10 }),
  cs('tabs-width-4', [{ setOption: { tabStopWidth: 4 } }, '\tx\ty']),
  // ---- modes and reports :1932-2396 ----
  ...DECSET.map(m => c1('decset-' + m, CSI + '?' + m + 'hx')),
  ...DECSET.map(m => c1('decrst-' + m, CSI + '?' + m + 'h' + CSI + '?' + m + 'lx')),
  c1('decset-many', CSI + '?1;6;7;45;2004h' + CSI + '?1;2004l'),
  c1('decset-12-quirk', CSI + '?12h', { options: { allowSetCursorBlink: true } }),   // :1963-1967
  c1('decset-12-quirk-off', CSI + '?12h' + CSI + '?12l', { options: { allowSetCursorBlink: true, cursorBlink: true } }),
  c1('decset-2031-disabled', CSI + '?2031h', { options: { vtExtensions: { colorSchemeQuery: false } } }),
  c1('decset-9001-enabled', CSI + '?9001h', { options: { vtExtensions: { win32InputMode: true } } }),
  c1('decset-3-no-winlines', 'abc' + CSI + '?3hx'),
  c1('decset-3-winlines', 'abc' + CSI + '?3hdef' + CSI + '?3lg', { options: { windowOptions: ['setWinLines'], windowsPty: WPTY } }),  // :1945-1955
  c1('alt-47', 'main' + CSI + '2;3H' + CSI + '?47halt' + CSI + '?47lx'),
  c1('alt-1047', 'main' + CSI + '2;3H' + CSI + '?1047halt' + CSI + '?1047lx'),
  c1('alt-1049', CSI + '1;32mmain' + CSI + '2;3H' + CSI + '?1049halt' + CSI + '5;5H' + CSI + '?1049lx'),
  c1('alt-1048', CSI + '2;3H' + CSI + '?1048h' + CSI + 'H' + CSI + '?1048lx'),
  cs('alt-ed3', [lines(12), { scrollLines: -2 }, CSI + '?1049h' + lines(10) + CSI + '3J']),
  c1('alt-twice', CSI + '?1049h' + CSI + '?1049hx' + CSI + '?1049l' + CSI + '?1049ly'),
  c1('mouse-x10', CSI + '?9h'),
  c1('mouse-1002-1006', CSI + '?1000h' + CSI + '?1002h' + CSI + '?1006h'),
  c1('mouse-1003-1016', CSI + '?1003h' + CSI + '?1016h'),
  c1('mouse-1005-1015', CSI + '?1000h' + CSI + '?1005h' + CSI + '?1015h'),
  c1('mouse-off', CSI + '?1003h' + CSI + '?1006h' + CSI + '?1000l' + CSI + '?1016l'),
  c1('decrqm-ansi', [2, 4, 12, 20, 99].map(m => CSI + m + '$p').join('') + CSI + '4h' + CSI + '20h' + CSI + '4$p' + CSI + '20$p'),  // :2336-2396
  c1('decrqm-private', DECRQM_PRIVATE.map(m => CSI + '?' + m + '$p').join('') + CSI + '?1;6;9;25;45;66;1004;1006;2004;2026h' + CSI + '?1049h'
    + DECRQM_PRIVATE.map(m => CSI + '?' + m + '$p').join('')),
  c1('decrqm-mouse', CSI + '?1003h' + CSI + '?1016h' + CSI + '?1003$p' + CSI + '?1016$p' + CSI + '?1002$p'),
  c1('decrqm-winlines', CSI + '?3$p', { options: { windowOptions: ['setWinLines'] } }),
  c1('decrqm-9001', CSI + '?9001h' + CSI + '?9001$p', { options: { vtExtensions: { win32InputMode: true } } }),
  c1('kitty-off', CSI + '=1u' + CSI + '?u' + CSI + '>1u' + CSI + '<u'),     // :3552-3651
  c1('kitty-on', CSI + '=5u' + CSI + '?u' + CSI + '=2;2u' + CSI + '?u' + CSI + '=1;3u' + CSI + '?u' + CSI + '=9;7u' + CSI + '?u'
    + Array.from({ length: 17 }, (_, i) => CSI + '>' + (i + 1) + 'u').join('') + CSI + '?u' + CSI + '<3u' + CSI + '?u'
    + CSI + '?1049h' + CSI + '>9u' + CSI + '?u' + CSI + '?1049l' + CSI + '?u' + CSI + '<99u' + CSI + '?u', { options: { vtExtensions: { kittyKeyboard: true } } }),
  // ---- SGR :2416-2725 ----
  c1('sgr-flags', [1, 2, 3, 4, 5, 7, 8, 9, 21, 22, 23, 24, 25, 27, 28, 29, 53, 55].map(p => CSI + p + 'mx').join(''), { cols: 40 }),
  c1('sgr-16', [30, 37, 40, 47, 90, 97, 100, 107, 39, 49, 31, 41].map(p => CSI + p + 'mx').join('')),
  c1('sgr-zero-fast', CSI + '1ma' + CSI + 'mb' + CSI + '1m' + CSI + '0mc' + CSI + '1m' + CSI + '0;0md'),
  c1('sgr-bold-faint-kitty', CSI + '1;2m' + CSI + '221ma' + CSI + '1;2m' + CSI + '222mb'),
  c1('sgr-bold-faint-kitty-off', CSI + '1;2m' + CSI + '221ma' + CSI + '1;2m' + CSI + '222mb', { options: { vtExtensions: { kittySgrBoldFaintControl: false } } }),
  c1('sgr-256-semicolon', CSI + '38;5;196ma' + CSI + '48;5;21mb' + CSI + '58;5;9m' + CSI + '4mc'),
  c1('sgr-256-colon', CSI + '38:5:196ma' + CSI + '48:5:21mb' + CSI + '58:5:9m' + CSI + '4mc'),
  c1('sgr-rgb-semicolon', CSI + '38;2;1;2;3ma' + CSI + '48;2;255;128;0mb' + CSI + '58;2;9;8;7m' + CSI + '4mc'),
  c1('sgr-rgb-colon', CSI + '38:2::1:2:3ma' + CSI + '38:2:1:2:3mb' + CSI + '48:2:0:10:20:30mc' + CSI + '38:2:1:2:3:4:5md' + CSI + '38;2:1:2:3me'),
  c1('sgr-color-truncated', CSI + '38;5ma' + CSI + '38;2;1;2mb' + CSI + '38:2mc' + CSI + '38md' + CSI + '48:5me'),
  c1('sgr-color-then-more', CSI + '38;5;1;1ma' + CSI + '0;38;2;1;2;3;4mb' + CSI + '0;38:5:3;4mc' + CSI + '38;5;' + digits20 + 'md'),
  c1('sgr-underline-styles', ['4:0', '4:1', '4:2', '4:3', '4:4', '4:5', '4:9', '4:', '21', '24', '4:3;58:5:9', '59', '4', '58;2;1;2;3', '0'].map((p, i) => CSI + p + 'm' + String.fromCharCode(65 + i)).join(''), { cols: 20 }),
  // 6, 7 and 13 fit the 3-bit style field unchanged or as 5; 9 happens to store as 1
  c1('sgr-underline-out-of-range', ['4:6', '4:7', '4:13'].map((p, i) => CSI + p + 'm' + String.fromCharCode(65 + i)).join('')),
  c1('sgr-underline-with-link', OSC + '8;;http://x' + BEL + CSI + '4:3ma' + CSI + '4:1mb' + OSC + '8;;' + BEL + 'c' + CSI + '0md'),
  c1('sgr-33-params', CSI + Array.from({ length: 34 }, (_, i) => (i < 31 ? '0' : i === 31 ? '1' : '3')).join(';') + 'mx'),
  // ---- replies :1706-1777, :2743-2795, :3519-3537, :2936-2983 ----
  c1('da1', CSI + 'c' + CSI + '0c' + CSI + '1c'),
  c1('da2', CSI + '>c' + CSI + '>0c' + CSI + '>1c'),
  c1('xtversion', CSI + '>q' + CSI + '>1q'),
  c1('dsr', CSI + '5n' + CSI + '3;4H' + CSI + '6n' + CSI + '?6n' + CSI + '?15n' + CSI + '?25n' + CSI + '?26n' + CSI + '?53n' + CSI + '7n'),
  c1('decrqss', ['"q', '"p', 'r', 'm', ' q', 'x'].map(s => DCS + '$q' + s + ST).join('')),
  c1('decrqss-bar-blink', ['"q', '"p', 'r', 'm', ' q', 'x'].map(s => DCS + '$q' + s + ST).join(''), { options: { cursorStyle: 'bar', cursorBlink: true } }),
  c1('decrqss-underline', CSI + '5 q' + DCS + '$q q' + ST, { options: { cursorStyle: 'underline' } }),
  c1('decrqss-protected', CSI + '1"q' + DCS + '$q"q' + ST + CSI + '2;4r' + DCS + '$qr' + ST),
  c1('decrqss-params-ignored', DCS + '1$qm' + ST),
  c1('decscusr', CSI + '3 q' + CSI + '6 q' + CSI + 'q' + CSI + '0 q' + CSI + '2 q'),
  c1('xtwinops-off', CSI + '18t' + CSI + '22t' + CSI + '23t' + CSI + '14t'),
  c1('xtwinops-18', CSI + '18t', { options: { windowOptions: ['getWinSizeChars'] } }),
  c1('xtwinops-title-stack', OSC + '0;t0' + BEL + Array.from({ length: 12 }, (_, i) => CSI + '22t' + OSC + '2;t' + (i + 1) + BEL).join('')
    + CSI + '23t' + CSI + '23t' + OSC + '1;icon' + BEL + CSI + '22;1t' + OSC + '1;icon2' + BEL + CSI + '22;2t' + CSI + '23;1t' + CSI + '23;2t'
    + Array.from({ length: 12 }, () => CSI + '23t').join(''), { options: { windowOptions: ['pushTitle', 'popTitle'] } }),
  c1('replies-disabled', CSI + 'c' + CSI + '5n' + CSI + '?1$p' + CSI + '>q', { options: { disableStdin: true } }),
  // ---- OSC :286-325, :3042-3150 ----
  c1('osc-titles', OSC + '0;zero' + BEL + OSC + '1;one' + ST + OSC + '2;two' + BEL + OSC + '2;' + BEL + OSC + '0;' + ST),
  c1('osc-unknown', OSC + '7;file:///x' + BEL + OSC + '133;A' + ST + OSC + '1337;foo' + BEL + 'x'),
  c1('osc8-basic', OSC + '8;;http://a' + BEL + 'link' + OSC + '8;;' + BEL + 'no'),
  c1('osc8-id', OSC + '8;id=x:foo=bar;http://a' + BEL + 'ab' + OSC + '8;;' + BEL + OSC + '8;id=;http://b' + BEL + 'c' + OSC + '8;;' + BEL),
  c1('osc8-reopen', OSC + '8;;u1' + BEL + 'a' + OSC + '8;;u2' + BEL + 'b' + OSC + '8;;' + BEL + 'c'),
  c1('osc8-malformed', OSC + '8' + BEL + OSC + '8abc' + BEL + OSC + '8;x' + BEL + 'a'),
  c1('osc8-id-no-uri', OSC + '8;;u' + BEL + 'a' + OSC + '8;id=x;' + BEL + 'b' + OSC + '8; ;' + BEL + 'c'),
  c1('osc8-trim', OSC + '8; id=x ;http://a' + BEL + 'a' + OSC + '8;;' + BEL + OSC + '8;id=x;http://a' + BEL + 'b'),
  c1('osc8-wrap', OSC + '8;;u' + BEL + 'abcdefghijklmn' + OSC + '8;;' + BEL, { cols: 10 }),
  c1('osc8-reuse', OSC + '8;id=q;u' + BEL + 'a' + OSC + '8;;' + BEL + '\r\n' + OSC + '8;id=q;u' + BEL + 'b' + OSC + '8;;' + BEL + 'c'),
  c1('osc8-same-id-other-uri', OSC + '8;id=q;u' + BEL + 'a' + OSC + '8;;' + BEL + OSC + '8;id=q;v' + BEL + 'b' + OSC + '8;;' + BEL),
  c1('osc8-scrolled-out', OSC + '8;;u' + BEL + 'a' + OSC + '8;id=k;v' + BEL + 'b' + OSC + '8;;' + BEL + '\r\n'.repeat(10) + OSC + '8;id=k;v' + BEL + 'c', { options: { scrollback: 2 } }),
  c1('osc8-semicolon-uri', OSC + '8;;http://a;b;c' + BEL + 'x' + OSC + '8;;' + BEL),
  // ---- resets :2816-2835, :3427-3438, headless Terminal.ts:122-132 ----
  cs('decstr', [lines(8), CSI + '?25l' + CSI + '2;4r' + CSI + '1;31m' + CSI + '4h' + E + '(0' + E + ')0\x0e' + E + '7' + CSI + '?6h' + OSC + '2;title' + BEL + E + 'H' + CSI + '?1h' + CSI + '!px']),
  cs('ris', [lines(8), CSI + '?25l' + CSI + '2;4r' + CSI + '1;31m' + CSI + '4h' + E + '(0' + E + '7' + CSI + '?6h' + OSC + '2;title' + BEL + CSI + '?1049h' + CSI + '?1h' + OSC + '8;;u' + BEL + E + 'cx']),
  c1('ris-then-text', 'abc' + E + 'cdef'),
  cs('reset-step', ['ab' + CSI + '1;', { reset: 1 }, '5Hx']),
  // ---- Windows heuristics, WindowsMode.ts, CoreTerminal.ts:279-306 ----
  c1('winpty-heuristic-lf', 'abcdefghij\r\nabcdefghi \r\nabc\r\n', { cols: 10, options: { windowsPty: WPTY } }),
  c1('winpty-heuristic-cup', 'abcdefghij' + CSI + '2;1Hxyz\r\nabcdefghij' + CSI + 'H' + CSI + '4;1H', { cols: 10, options: { windowsPty: WPTY } }),
  c1('winpty-new-build', 'abcdefghij\r\nabcdefghij\r\n', { cols: 10, options: { windowsPty: { backend: 'conpty', buildNumber: 21376 } } }),
  c1('winpty-last-old-build', 'abcdefghij\r\nabcdefghij\r\n', { cols: 10, options: { windowsPty: { backend: 'conpty', buildNumber: 21375 } } }),
  c1('winpty-winpty', 'abcdefghij\r\nabcdefghij\r\n', { cols: 10, options: { windowsPty: { backend: 'winpty', buildNumber: 19044 } } }),
  cs('winpty-option-change', ['abcdefghij\r\n', { setOption: { windowsPty: WPTY } }, 'abcdefghij\r\n', { setOption: { windowsPty: null } }, 'abcdefghij\r\n'], { cols: 10 }),
  cs('winpty-scrolled-top', ['abcdefghij\r\n'.repeat(12) + CSI + 'H'], { cols: 10, options: { scrollback: 0, windowsPty: WPTY } }),
  // ---- resize: CoreTerminal.ts:187-200, headless :90-96, Buffer.resize ----
  cs('resize-rows', [lines(10) + CSI + '4;3H', { resize: [20, 3] }, 'x', { resize: [20, 8] }, 'y', { resize: [20, 2] }, CSI + 'Hz', { resize: [20, 9] }]),
  cs('resize-rows-no-scrollback', [lines(4), { resize: [20, 3] }, { resize: [20, 7] }, 'q'], { options: { scrollback: 0 } }),
  // the column count changes: an old ConPTY, where upstream does not reflow (phase 5)
  cs('resize-min', ['abc', { resize: [1, 0] }, 'x'], { options: { windowsPty: WPTY } }),
  cs('resize-same', ['abc', { resize: [20, 6] }, 'x']),
  cs('resize-in-alt', [lines(3) + CSI + '?1049hx', { resize: [20, 4] }, 'y', { resize: [20, 8] }, CSI + '?1049lz']),
  cs('resize-cols-winpty', [lines(6), { resize: [10, 6] }, 'x', { resize: [30, 6] }, 'y'], { options: { windowsPty: WPTY } }),
  cs('resize-saved-cursor', [CSI + '3;18H' + E + '7', { resize: [10, 6] }, E + '8x'], { options: { windowsPty: WPTY } }),
  cs('scrollback-option', [lines(3) + OSC + '8;;u' + BEL + 'link' + OSC + '8;;' + BEL + '\r\n' + lines(8), { setOption: { scrollback: 2 } }, 'x', { setOption: { scrollback: 5 } }, '\r\n' + lines(4)]),
  // ---- refresh ranges :474-484, CoreTerminal.ts:153-156 ----
  c1('renders-multi', 'a\r\nb\r\nc'),
  c1('renders-scroll', lines(10)),
  c1('renders-full', CSI + '?1049h'),
  cs('renders-scrolled-away', [lines(30), { scrollLines: -20 }, 'x', '\r\ny']),
  cs('renders-region', [fill(), CSI + '2;4r' + CSI + '4;1H\n\n' + CSI + 'r']),
];

// ---- oversized input; each ends with ESC[H ESC[2J ok ----

const tail = W(CSI + 'H' + CSI + '2Jok');
const rep = (s, times) => ({ writeRepeat: { s, times } });
function many(ch, n, chunk = 65536) {
  const out = [];
  const full = Math.floor(n / chunk);
  if (full) out.push(rep(ch.repeat(chunk), full));
  if (n % chunk) out.push(W(ch.repeat(n % chunk)));
  return out;
}
const long = [
  cs('long-sgr-1000', [CSI + '1;'.repeat(1000) + '31mx', tail]),
  cs('long-param-digits', [CSI + digits20 + ';' + digits20 + 'Ha' + CSI + '1;3H' + CSI + digits20 + 'X' + CSI + digits20 + '@' + CSI + '1;1H' + CSI + digits20 + 'P'
    + CSI + '38;5;' + digits20 + 'mb' + CSI + '48;2;' + digits20 + ';1;' + digits20 + 'mc', tail]),
  cs('long-intermediates', [CSI, ...many('!', 65536, 4096), 'p', tail]),
  cs('long-osc-title-over', [OSC + '2;', ...many('a', 10000001), BEL, tail]),
  cs('long-osc-title-exact', [OSC + '2;', ...many('a', 10000000), BEL, tail]),
  cs('long-dcs-over', [DCS + '$q', ...many('a', 10000001), ST, tail]),
  cs('long-apc-over', [E + '_G', ...many('a', 10000001), ST, tail]),
  cs('long-sos', [E + 'X', ...many('a', 11000000), ST, tail]),
  cs('long-print', [...many('x', 1048576), tail], { cols: 80, rows: 25, options: { scrollback: 100 } }),
  cs('long-rep-cap', ['a' + CSI + '1048576b', tail], { cols: 40, rows: 6, options: { scrollback: 20 } }),
  // (no 2^31-count IL / DL / SU / SD: upstream loops that many times and never
  // returns; il-dl-1000 and su-sd-1000 show the clamp is equivalent)
  cs('long-osc-fallback', [OSC + '777;', ...many('b', 300000), BEL, tail]),
];

// ---- synthesized replies: CoreBrowserTerminal.ts / ThemeService.ts ----

const LIGHT = (() => { const p = require('../lib-term.js').DEFAULT_PALETTE.slice(); p[256] = 0x202020; p[257] = 0xf0f0f0; return p; })();
const EVEN = (() => { const p = require('../lib-term.js').DEFAULT_PALETTE.slice(); p[256] = 0x808080; p[257] = 0x808080; return p; })();
const synth = [
  c1('osc4-query', OSC + '4;1;?' + BEL + OSC + '4;1;?;2;?' + ST + OSC + '4;256;?' + BEL + OSC + '4;x;?' + BEL + OSC + '4;255;?' + BEL + OSC + '4;' + digits20 + ';?' + BEL),  // :3066-3090
  c1('osc4-set-query', OSC + '4;1;rgb:12/34/56' + BEL + OSC + '4;1;?' + BEL + OSC + '4;2;#abc;3;#123456' + BEL + OSC + '4;2;?;3;?' + BEL),
  c1('osc4-bad-spec', OSC + '4;1;nope;2;rgb:1/22/333' + BEL + OSC + '4;1;?;2;?' + BEL + OSC + '4;3' + BEL),
  c1('osc10-11-12', OSC + '10;?' + BEL + OSC + '11;?' + ST + OSC + '12;?' + BEL + OSC + '10;#ff0000' + BEL + OSC + '10;?;?' + BEL + OSC + '11;#00ff00;?;?' + BEL + OSC + '12;?' + BEL),  // :3159-3276
  c1('osc104', OSC + '4;1;#111111;2;#222222;3;#333333' + BEL + OSC + '104;1;x;999' + BEL + OSC + '4;1;?;2;?;3;?' + BEL + OSC + '104' + BEL + OSC + '4;2;?;3;?' + BEL),
  c1('osc110-111-112', OSC + '10;#101010' + BEL + OSC + '11;#202020' + BEL + OSC + '12;#303030' + BEL + OSC + '110' + BEL + OSC + '10;?' + BEL + OSC + '11;?' + BEL
    + OSC + '111;junk' + BEL + OSC + '11;?' + BEL + OSC + '112' + BEL + OSC + '12;?' + BEL + OSC + '104' + BEL + OSC + '10;?' + BEL),
  c1('color-formats', ['rgb:f/0/8', 'rgb:ff/00/80', 'rgb:fff/000/888', 'rgb:ffff/0000/8888', '#f08', '#ff0088', '#fff000888', '#ffff00008888',
    'RGB:FF/00/80', '#FF0088', 'rgb:1/22/333', '#12345', 'red', ''].map((spec, i) => OSC + '4;' + (i + 1) + ';' + spec + BEL + OSC + '4;' + (i + 1) + ';?' + BEL).join(''),
  { cols: 40 }),  // XParseColor.ts:23-56
  c1('scheme-query', CSI + '?996n'),
  c1('scheme-query-light', CSI + '?996n', { synth: { palette: LIGHT } }),
  c1('scheme-query-even', CSI + '?996n', { synth: { palette: EVEN } }),
  c1('scheme-notify', CSI + '?2031h' + OSC + '4;1;#f00;2;#0f0' + BEL + OSC + '11;#ffffff' + BEL + OSC + '10;#000000' + BEL + OSC + '104;1' + BEL + OSC + '111' + BEL + OSC + '4;1;?' + BEL),  // :524-531
  cs('scheme-theme', [OSC + '4;1;#123456' + BEL + CSI + '?2031h', { theme: LIGHT }, OSC + '4;1;?' + BEL + CSI + '?2031l', { theme: EVEN }, CSI + '?996n']),
  c1('scheme-disabled', CSI + '?996n' + CSI + '?2031h' + OSC + '4;1;#f00' + BEL, { options: { vtExtensions: { colorSchemeQuery: false } } }),
  cs('focus-1004', [CSI + '?1004h', { focus: false }, { focus: false }, { focus: true }, CSI + '?1004l', { focus: false }, CSI + '?1004h']),   // :1124-1130, :305-331
  cs('focus-1004-unfocused', [CSI + '?1004h'], { synth: { focused: false } }),
  c1('ris-keeps-colors', OSC + '4;1;#abcdef' + BEL + OSC + '10;#010203' + BEL + E + 'c' + OSC + '4;1;?' + BEL + OSC + '10;?' + BEL),  // :1099-1119
  c1('synth-read-only', OSC + '4;1;?' + BEL + CSI + '?996n' + CSI + '?1004h', { options: { disableStdin: true } }),
];

// ---- mouse: 5 protocols x 3 encodings x the events upstream can produce ----

const BUTTONS = ['LEFT', 'MIDDLE', 'RIGHT', 'NONE', 'WHEEL'];
const ACTIONS = ['UP', 'DOWN', 'LEFT', 'RIGHT', 'MOVE'];
const MODS = [{}, { shift: true }, { alt: true }, { ctrl: true }, { shift: true, alt: true, ctrl: true }];
const POS = [[0, 0], [94, 10], [222, 5], [223, 5], [300, 40]];
const mouseEvents = [];
for (const button of BUTTONS) {
  for (const action of ACTIONS) {
    const ok = button === 'WHEEL' ? ['UP', 'DOWN', 'LEFT', 'RIGHT'].includes(action) : ['UP', 'DOWN', 'MOVE'].includes(action);
    if (!ok) continue;
    for (const m of MODS) {
      for (const [col, row] of POS) {
        mouseEvents.push({ col, row, x: col * 9 + 4, y: row * 17 + 8, button, action, ctrl: !!m.ctrl, alt: !!m.alt, shift: !!m.shift });
      }
    }
  }
}
const mouse = { protocols: ['NONE', 'X10', 'VT200', 'DRAG', 'ANY'], encodings: ['DEFAULT', 'SGR', 'SGR_PIXELS'], events: mouseEvents };

module.exports = { hand, long, synth, mouse };
