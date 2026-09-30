// Inputs for parser-cases.js (tools/terminal-oracle/parser-cases.js has the
// vocabulary). Only inputs here; every expected value comes from running xterm.js.
//
// utf8:       { id, chunks: [[byte...] ...] } -- one Utf8ToUtf32 per case, one decode()
//             call per chunk.
// traces:     { id, register: [...], feed: [...] }. A feed item is { s: "..." } (a JS
//             string, taken by code point), { cp: [...] }, { fill: [cp, n], times? }
//             (n copies of cp, parsed `times` times), { repeat: { s | cp, times } },
//             { reset: 1 } or { unregister: k }. Every item is one parse() call
//             (`times` calls for repeat / fill).
// cutSources: ids of single-item trace cases that are also fed cut in two at every
//             code point.
// longCases:  oversized input; each ends with ESC[1m ok OSC 2;t BEL to show the
//             parser still works afterwards.
// fuzz:       seeds and lengths for the random traces.
'use strict';

const E = '\x1b';
const ok = { s: E + '[1mok' + E + ']2;t\x07' };
const hex = s => s.split(/\s+/).filter(Boolean).map(h => parseInt(h, 16));
const chunks = spec => spec.split('|').map(hex);
const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);

const utf8 = [
  ['ascii-unrolled', '61 62 63 64 65 66 67 68 69'],
  ['ascii-short', '61 62 63'],
  ['two-three-four', 'C3 A9 E4 B8 AD F0 9F 98 80'],
  ['overlong-2', 'C0 80 C1 BF 61'],
  ['overlong-3', 'E0 80 80 61'],
  ['overlong-4', 'F0 80 80 80 61'],
  ['surrogates', 'ED A0 80 ED BF BF 61'],
  ['bom-whole', 'EF BB BF 61'],
  ['bom-split', 'EF | BB BF 61'],
  ['beyond-max', 'F4 90 80 80 F5 80 80 80 F8 61 FF 61'],
  ['bad-cont-2', 'C3 41'],
  ['bad-cont-3a', 'E4 41'],
  ['bad-cont-3b', 'E4 B8 41'],
  ['bad-cont-4a', 'F0 41'],
  ['bad-cont-4b', 'F0 9F 41'],
  ['bad-cont-4c', 'F0 9F 98 41'],
  ['lone-cont', '80 BF 61'],
  ['split-3', 'E4 | B8 | AD'],
  ['split-4', 'F0 | 9F | 98 | 80'],
  ['split-empty', 'E4 | | B8 AD'],
  ['split-bad-cont', 'E4 B8 | 41'],
  ['split-overlong-2', 'C1 | BF 61'],
  ['split-surrogate', 'ED | A0 80 61'],
  ['split-then-ascii-run', 'E4 B8 | AD 61 62 63 64 65'],
  ['split-bom-3', 'EF BB | BF 61 62'],
  ['split-4-beyond', 'F4 90 | 80 80 61'],
  ['split-4-bad-last', 'F0 9F 98 | 41 42'],
  ['split-trailing-lead', '61 62 63 64 65 66 C3'],
  ['split-trailing-2of3', '61 62 E4 B8'],
  ['split-trailing-3of4', '61 F0 9F 98'],
  ['split-2-then-bad', 'C3 | C3 A9'],
  ['empty-first', ' | 61'],
].map(([id, spec]) => ({ id, chunks: chunks(spec) }));

// ---- traces --------------------------------------------------------------------

const t = (id, feed, register = []) => ({ id, register, feed: feed.map(f => (typeof f === 'string' ? { s: f } : f)) });

const escFinals = range(0x30, 0x7e).filter(c => !'PX[]^_'.includes(String.fromCharCode(c)));

const traces = [
  // print
  t('print-ascii', ['hello world']),
  t('print-nonascii', ['a bÿc\u{1F600}d中']),
  t('print-del', ['ab\x7fcd']),
  t('print-long-run', ['x'.repeat(300)]),
  t('print-chunks', ['abc', 'def', 'é']),
  // execute
  t('exec-c0-all', [{ cp: range(0x00, 0x1f).filter(c => c !== 0x1b) }]),
  t('exec-c1-all', [{ cp: range(0x80, 0x9f).flatMap(c => [c, 0x61]) }]),
  t('exec-in-csi', [E + '[1\n2m']),
  t('exec-in-esc-intermediate', [E + '(\n0']),
  t('exec-in-osc', [E + ']2;a\x01b\x0ac\x1ed\x07']),
  t('exec-registered', ['a\x07b\x07'], [{ exec: 7 }]),
  t('exec-registered-high', ['a\x1cb', { cp: [0x84, 0x61] }], [{ exec: 0x1c }, { exec: 0x84 }]),
  // CSI
  t('csi-basic', [E + '[1;2H']),
  t('csi-zdm', [E + '[m']),
  t('csi-empty-params', [E + '[;;m']),
  t('csi-subparams', [E + '[1;2:3:4;5::6m']),
  t('csi-leading-colon', [E + '[:1m']),
  t('csi-prefix-each', [E + '[<1m' + E + '[=1m' + E + '[>1m' + E + '[?1m']),
  t('csi-prefix-late', [E + '[1?mx']),
  t('csi-intermediates', [E + '[1 !p' + E + '[ $p' + E + '[1$p']),
  t('csi-many-intermediates', [E + '[?1 !!!!p']),
  t('csi-param-overflow', [E + '[99999999999999999999m' + E + '[2147483647;2147483648m']),
  t('csi-33-params', [E + '[' + '1;'.repeat(32) + '5m']),
  t('csi-32-params-digit', [E + '[' + '1;'.repeat(31) + '15m']),
  t('csi-subparam-overflow', [E + '[1' + ':1'.repeat(33) + ';7m']),
  t('csi-subparam-after-reject', [E + '[' + '1;'.repeat(32) + '1:5m']),
  t('csi-nonascii-abort', [E + '[1é2mxyz']),
  t('csi-7f-inside', [E + '[\x7f1\x7f;\x7f2 \x7f!\x7fp' + E + '[1?\x7fm' + E + '[\x7f?1h']),
  t('csi-c1-introducer', [{ cp: [0x9b, 0x31, 0x3b, 0x32, 0x48, 0x61] }]),
  t('csi-ignore-long', [E + '[1;2 !!3;4m' + E + '[1 2mz']),
  // CSI fast path
  t('csi-fast-chunk-end', [E + '[', '1', 'm']),
  t('csi-fast-two', [E + '[', '1m']),
  t('csi-fast-exact', [E + '[1m']),
  t('csi-fast-after-print', ['ab', E + '[m', 'c']),
  t('csi-fast-after-print-end', ['ab' + E + '[m']),
  t('csi-fast-in-sospm', [E + 'Xab' + E + '[1mcd' + E + '\\']),
  t('csi-fast-prefix-at-end', [E + '[?', '1h']),
  t('csi-fast-interrupted', [E + '[1;2' + E + '[3m']),
  t('csi-fast-c0-mid', [E + '[1\x082m']),
  t('csi-fast-in-escape', [E + '(' + E + '[1m']),
  // ESC
  t('esc-basic', [E + '7' + E + 'c' + E + '=']),
  t('esc-intermediate', [E + '(0' + E + '#8' + E + '%G' + E + ' !F']),
  t('esc-st-swallowed', ['a' + E + '\\b']),
  t('esc-7f', [E + '\x7f7']),
  t('esc-final-ranges', [{ cp: escFinals.flatMap(c => [0x1b, c]) }]),
  t('esc-introducers', [E + 'P' + E + '\\' + E + 'Xz' + E + '\\' + E + '[m' + E + ']\x07' + E + '^z' + E + '\\' + E + '_' + E + '\\']),
  t('esc-nonascii', [E + 'éx' + E + '(éy']),
  t('esc-registered', [E + '7' + E + '(0' + E + '8'], [{ esc: { final: '7' }, ret: true }, { esc: { intermediates: '(', final: '0' }, ret: false }]),
  // OSC
  t('osc-bel', [E + ']2;title\x07']),
  t('osc-st', [E + ']2;title' + E + '\\x']),
  t('osc-c1-st', [{ cp: [0x1b, 0x5d, 0x32, 0x3b, 0x74, 0x9c, 0x61] }]),
  t('osc-c1-introducer', [{ cp: [0x9d, 0x32, 0x3b, 0x74, 0x07] }]),
  t('osc-can', [E + ']2;ti\x18x']),
  t('osc-sub', [E + ']2;ti\x1ax']),
  t('osc-no-payload', [E + ']2\x07']),
  t('osc-no-payload-registered', [E + ']2\x07'], [{ osc: 2, kind: 'raw', ret: true }]),
  t('osc-no-id', [E + '];x\x07']),
  t('osc-bad-id', [E + ']2a;x\x07']),
  t('osc-id-huge', [E + ']4294967300;1;?\x07'], [{ osc: 4, kind: 'raw', ret: true }]),
  t('osc-id-just-below', [E + ']2147483647;x\x07' + E + ']2147483648;x\x07']),
  t('osc-c0-inside', [E + ']2;a\x1cb\x1dc\x1ed\x1fe\x07']),
  t('osc-nonascii', [E + ']2;héllo\u{1F600}中\x07']),
  t('osc-split', [E + ']2;ab', 'cd', 'ef\x07']),
  t('osc-split-id', [E + ']1', '0', ';x\x07']),
  t('osc-registered', [E + ']2;x\x07' + E + ']2;' + E + '\\'], [{ osc: 2, kind: 'string', ret: true }]),
  t('osc-registered-can', [E + ']2;x\x18y'], [{ osc: 2, kind: 'string', ret: true }]),
  t('osc-chain-ftf', [E + ']5;x\x07'], [{ osc: 5, kind: 'string', ret: false }, { osc: 5, kind: 'string', ret: true }, { osc: 5, kind: 'string', ret: false }]),
  t('osc-chain-tff', [E + ']5;x\x07'], [{ osc: 5, kind: 'string', ret: true }, { osc: 5, kind: 'raw', ret: false }, { osc: 5, kind: 'string', ret: false }]),
  t('osc-chain-fft', [E + ']5;x\x07'], [{ osc: 5, kind: 'raw', ret: false }, { osc: 5, kind: 'raw', ret: false }, { osc: 5, kind: 'raw', ret: true }]),
  t('osc-restart', [E + ']2;a' + E + ']3;b\x07']),
  // DCS
  t('dcs-basic', [E + 'P1$qm' + E + '\\']),
  t('dcs-params', [E + 'P1;2:3q data' + E + '\\' + E + 'Pqx' + E + '\\' + E + 'P0;0qy' + E + '\\' + E + 'P5qz' + E + '\\'], [{ dcs: { final: 'q' }, kind: 'string', ret: true }]),
  t('dcs-ignore', [E + 'P1?q' + E + '\\' + E + 'P1;2 3q' + E + '\\x']),
  t('dcs-can', [E + 'P$qab\x18c']),
  t('dcs-c0-put', [E + 'P$qa\x01b\nc' + E + '\\']),
  t('dcs-7f', [E + 'P$qa\x7fb' + E + '\\']),
  t('dcs-c1', [{ cp: [0x90, 0x24, 0x71, 0x61, 0x85, 0x62, 0x9c, 0x63] }]),
  t('dcs-nonascii', [E + 'P$qé\u{1F600}' + E + '\\']),
  t('dcs-string-handler', [E + 'P$qm' + E + '\\' + E + 'P$q"q' + E + '\\' + E + 'P1$qr\x18'], [{ dcs: { intermediates: '$', final: 'q' }, kind: 'string', ret: true }]),
  t('dcs-chain', [E + 'P$qm' + E + '\\'], [{ dcs: { intermediates: '$', final: 'q' }, kind: 'raw', ret: false }, { dcs: { intermediates: '$', final: 'q' }, kind: 'raw', ret: true }, { dcs: { intermediates: '$', final: 'q' }, kind: 'string', ret: false }]),
  t('dcs-split', [E + 'P$', 'qab', 'cd' + E, '\\']),
  // APC
  t('apc-basic', [E + '_Ga=1' + E + '\\']),
  t('apc-intermediate', [E + '_!Gabc' + E + '\\']),
  t('apc-allowed-bytes', [E + '_Ga\x08b\x09c\x0dd\x01e\x0ef\x7fgéh' + E + '\\']),
  t('apc-can', [E + '_Gab\x18c']),
  t('apc-sub', [E + '_Gab\x1ac']),
  t('apc-c1', [{ cp: [0x9f, 0x47, 0x61, 0x9c, 0x62] }]),
  t('apc-string-handler', [E + '_Ga=1' + E + '\\' + E + '_Gb\x18'], [{ apc: { final: 'G' }, kind: 'string', ret: true }]),
  t('apc-raw-chain', [E + '_Gxy' + E + '\\'], [{ apc: { final: 'G' }, kind: 'raw', ret: false }, { apc: { prefix: '?', final: 'G' }, kind: 'raw', ret: true }]),
  // SOS / PM
  t('sos-pm', [E + 'Xhello' + E + '\\a', { cp: [0x98, 0x61, 0x62, 0x9c, 0x63, 0x9e, 0x64, 0x9c, 0x65] }, E + '^pm\x07z' + E + '\\']),
  // reset and unregister
  t('reset-mid-osc', [E + ']2;ab', { reset: 1 }, 'cd\x07e'], [{ osc: 2, kind: 'raw', ret: true }]),
  t('reset-mid-osc-id', [E + ']2', { reset: 1 }, ';cd\x07e'], [{ osc: 2, kind: 'raw', ret: true }]),
  t('reset-mid-dcs', [E + 'P$qab', { reset: 1 }, 'cd' + E + '\\'], [{ dcs: { intermediates: '$', final: 'q' }, kind: 'raw', ret: true }]),
  t('reset-mid-apc', [E + '_Gab', { reset: 1 }, 'cd' + E + '\\'], [{ apc: { final: 'G' }, kind: 'raw', ret: true }]),
  t('reset-mid-csi', [E + '[1;2', { reset: 1 }, '3m']),
  t('reset-after-print', ['ab', { reset: 1 }, 'c']),
  t('unregister-csi', [E + '[1m', { unregister: 0 }, E + '[2m'], [{ csi: { final: 'm' }, ret: true }]),
  t('unregister-twice', [E + '[1m', { unregister: 0 }, { unregister: 0 }, E + '[2m'], [{ csi: { final: 'm' }, ret: true }]),
  t('unregister-middle', [E + '[1m', { unregister: 1 }, E + '[2m'], [{ csi: { final: 'm' }, ret: false }, { csi: { final: 'm' }, ret: false }, { csi: { final: 'm' }, ret: false }]),
  t('unregister-osc-dcs-apc', [E + ']7;a\x07' + E + 'Pqb' + E + '\\' + E + '_Gc' + E + '\\', { unregister: 0 }, { unregister: 1 }, { unregister: 2 }, E + ']7;a\x07' + E + 'Pqb' + E + '\\' + E + '_Gc' + E + '\\'],
    [{ osc: 7, kind: 'string', ret: true }, { dcs: { final: 'q' }, kind: 'string', ret: true }, { apc: { final: 'G' }, kind: 'string', ret: true }]),
  t('unregister-esc', [E + '7', { unregister: 0 }, E + '7'], [{ esc: { final: '7' }, ret: true }]),
  t('csi-chain-ftf', [E + '[5m'], [{ csi: { final: 'm' }, ret: false }, { csi: { final: 'm' }, ret: true }, { csi: { final: 'm' }, ret: false }]),
  t('csi-chain-fff', [E + '[5;6m'], [{ csi: { final: 'm' }, ret: false }, { csi: { final: 'm' }, ret: false }]),
  t('csi-chain-prefix', [E + '[?5h' + E + '[5h', { cp: [0x9b, 0x3f, 0x35, 0x68] }], [{ csi: { prefix: '?', final: 'h' }, ret: true }, { csi: { final: 'h' }, ret: true }]),
  t('csi-registered-intermediate', [E + '[1 q' + E + '[2$p'], [{ csi: { intermediates: ' ', final: 'q' }, ret: true }, { csi: { prefix: '?', intermediates: '$', final: 'p' }, ret: true }]),
];

const cutSources = [
  'print-nonascii', 'exec-in-csi', 'csi-subparams', 'csi-prefix-each', 'csi-intermediates',
  'csi-fast-exact', 'csi-7f-inside', 'esc-intermediate', 'esc-st-swallowed', 'osc-st',
  'osc-nonascii', 'dcs-basic', 'dcs-c0-put', 'apc-allowed-bytes', 'sos-pm-plain',
];
traces.push(t('sos-pm-plain', ['a' + E + 'Xhi' + E + '\\b' + E + '^pém' + E + '\\c']));

// ---- long input ----------------------------------------------------------------

const CH = 65536;
// n copies of cp in parse calls of CH code points (one item per full chunk run plus
// the remainder).
function fillFeed(cp, n) {
  const out = [];
  const full = Math.floor(n / CH);
  if (full) out.push({ fill: [cp, CH], times: full });
  if (n % CH) out.push({ fill: [cp, n % CH] });
  return out;
}

const longCases = [
  t('long-params', [E + '[' + '1;'.repeat(1000) + '31m', ok]),
  t('long-digits', [E + '[' + '9'.repeat(20) + ';' + '1'.repeat(20) + 'H', ok]),
  t('long-subparams', [E + '[1' + ':12345'.repeat(400) + 'm', ok]),
  t('long-intermediates', [E + '[', ...fillFeed(0x21, 65536), 'p', ok]),
  t('long-osc-exact', [E + ']2;', ...fillFeed(0x61, 10000000), '\x07', ok], [{ osc: 2, kind: 'string', ret: true }]),
  t('long-osc-over', [E + ']2;', ...fillFeed(0x61, 10000001), '\x07', ok], [{ osc: 2, kind: 'string', ret: true }]),
  t('long-osc-astral', [E + ']2;', ...fillFeed(0x1F600, 5000001), '\x07', ok], [{ osc: 2, kind: 'string', ret: true }]),
  t('long-osc-astral-exact', [E + ']2;', ...fillFeed(0x1F600, 5000000), '\x07', ok], [{ osc: 2, kind: 'string', ret: true }]),
  t('long-dcs-over', [E + 'P$q', ...fillFeed(0x61, 10000001), E + '\\', ok], [{ dcs: { intermediates: '$', final: 'q' }, kind: 'string', ret: true }]),
  t('long-apc-over', [E + '_G', ...fillFeed(0x61, 10000000), E + '\\', ok], [{ apc: { final: 'G' }, kind: 'string', ret: true }]),
  t('long-sos', [E + 'X', ...fillFeed(0x61, 11000000), E + '\\', ok]),
  t('long-print', [...fillFeed(0x78, 1048576), ok]),
  t('long-osc-id', [E + ']' + '1'.repeat(5000) + ';x\x07', ok]),
  t('long-osc-fallback', [E + ']77;', ...fillFeed(0x62, 200000), '\x07', ok]),
];

const fuzz = { seeds: range(1, 100), length: [256, 2048] };

module.exports = { utf8, traces, cutSources, longCases, fuzz };
