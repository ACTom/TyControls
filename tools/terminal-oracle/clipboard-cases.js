// Writes tests/fixtures/terminal-osc52.json for tests/test.terminal.selection.pas
// (TestOsc52Oracle) from xterm.js 6.0.0's clipboard addon (pin and loading in
// lib-dump.js loadBrowserParts).
//
//   node tools/terminal-oracle/clipboard-cases.js
//
// The addon is activated on a fake terminal that only records the OSC 52 handler it
// registers and what it sends back through input(); its clipboard provider answers
// READ_TEXT to every read and records every write. Each case calls the handler with
// `data` (the OSC payload after "52;").
//   cases  { data, writes: [[pc, b64 of the UTF-8 text]], replies: [[b64 of the
//          reply's UTF-8, wasUserInput]] }
//          A data too long for the fixture is { dataLength, dataSha1, seed, writes:
//          [[pc, { length, sha1 }]] } -- the Pascal side rebuilds the data from the
//          seed (mulberry32 bytes, base64) and hashes what it decodes.
// Decoding goes through atob + TextDecoder: node 22 has no Uint8Array.fromBase64,
// which the addon would prefer (ClipboardAddon.ts:104-120). The script refuses to run
// if that changes -- the fixture would then describe the other path.
'use strict';
const crypto = require('crypto');
const T = require('./lib-term.js');
const L = T.L;

if (typeof Uint8Array.fromBase64 !== 'undefined') {
  throw new Error('this node has Uint8Array.fromBase64: the addon would decode another way -- re-check the port');
}

T.loadUpstream();
const B = L.loadBrowserParts();
const b64 = s => Buffer.from(s, 'utf8').toString('base64');
const sha1 = s => crypto.createHash('sha1').update(Buffer.from(s, 'utf8')).digest('hex');

const READ_TEXT = '读到的 text\n';

function run(data) {
  let handler = null;
  const replies = [], writes = [];
  const fakeTerm = {
    parser: { registerOscHandler: (id, h) => { if (id !== 52) throw new Error('id ' + id); handler = h; return { dispose() {} }; } },
    input: (s, user) => replies.push([s, user]),
  };
  const provider = { readText: () => READ_TEXT, writeText: (pc, t) => { writes.push([pc, t]); } };
  new B.ClipboardAddon(undefined, provider).activate(fakeTerm);
  const r = handler(data);
  if (r !== true) throw new Error('handler answered ' + r);
  return { writes, replies };
}

// mulberry32 bytes, base64 -- the Pascal side makes the same (TyTermPrngBytes)
function bigData(seed, n) {
  const rnd = T.prng(seed);
  const bytes = Buffer.alloc(n);
  for (let i = 0; i < n; i++) bytes[i] = Math.floor(rnd() * 256);
  return bytes.toString('base64');
}

const DATA = [
  'c;aGVsbG8=', 'c;?', 'p;?', ';aGk=', 'c', '', 'c;aGVsbG8=;x', ' c;aGVs bG8= ', 'c;aGVsbG8', 'c;aGV$',
  'c;aGVsb', 'c;77u/QQ==', 'c;/w==', 'c;8J+Y', 'c;7aCA', 'c;AA==', 'c;5Lit5paH',
  // ours: more of the forgiving-base64 and TextDecoder rules
  'c;', ';', 'c;?;x', 'c;??', 'c; ?', 'c;aGk', 'c;aGk==', 'c;aGk===', 'c;aG=k', 'c;aGk=\t\n\f\r ', 'c;a Gk=',
  'c;aGVsbG8=aGk=', 'c;====', 'c;A', 'c;AB', 'c;ABC', 'c;ABCD', 'c;-_8=', 'c;77u/77u/QQ==', 'c;QUJD77u/',
  'c;wIA=', 'c;4ICA', 'c;8ICAgA==', 'c;9JCAgA==', 'c;7b+/', 'c;7p+/', 'c;wA==', 'c;4oI=', 'c;8J+YgA==',
  'c;8J+Y8J+YgA==', 'c;gA==', 'c;/v8=', 'c;QYBC', 'c;4oKsQQ==', 'c;4oJB', 'c;8JCAQQ==', 'c;+A==', 'c;+ICAgIA=',
  'c;7aC97b+/', 's0;aGk=', 'clipboard;aGk=', 'c;aGk=;', ';?',
];

const cases = DATA.map(data => {
  const { writes, replies } = run(data);
  return { data, writes: writes.map(([pc, t]) => [pc, b64(t)]), replies: replies.map(([s, u]) => [b64(s), u]) };
});
// the long one
{
  const seed = 52, n = 786432;
  const data = 'c;' + bigData(seed, n);
  const { writes, replies } = run(data);
  if (replies.length) throw new Error('the long write answered');
  cases.push({
    dataLength: data.length, dataSha1: sha1(data), seed, bytes: n,
    writes: writes.map(([pc, t]) => [pc, { length: Buffer.byteLength(t, 'utf8'), sha1: sha1(t) }]), replies: [],
  });
}

L.writeFixture('terminal-osc52.json', {
  upstream: L.upstreamInfo(), generator: 'tools/terminal-oracle/clipboard-cases.js', kind: 'osc52',
  readText: b64(READ_TEXT), cases,
});
console.log(`osc52: ${cases.length} cases`);
