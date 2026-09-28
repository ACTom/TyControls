// Shared plumbing for the terminal oracle scripts: every script in this directory
// loads xterm.js through here and writes through here.
//
// Upstream: xterm.js 6.0.0, a LOCAL checkout built once (spec 13.1):
//   cd D:/Projects/xterm.js && npm ci && npm run build
// (npm ci --ignore-scripts if node-pty fails to build; we never load it.)
// XTERM_ROOT overrides the checkout path; XTERM_OUT the output folder ('out' by
// default; 'out-esbuild' if the tsgo output ever stops loading in node).
//
// Pinned: package.json version 6.0.0 and HEAD c58ea36... A different checkout, or a
// dirty one, is refused -- the port and the oracle must be the same code.
//
// THE BUFFER POOL. addon-unicode-graphemes decodes its trie with
// Buffer.from(base64) and then reads the header through new DataView(data.buffer),
// ignoring byteOffset. Node carves small Buffers out of a shared 8 KB pool, so the
// header is read from whatever else sits in the pool: every code point above the
// BMP comes back 0 and ~1.8 GB is allocated, differently from run to run. A browser
// takes the atob branch and gets it right. Buffer.poolSize = 0 before the addon is
// required makes node hand out an unpooled buffer (byteOffset 0), and
// checkTrieDecode() proves it by decoding the same bytes independently.
'use strict';
Buffer.poolSize = 0; // before ANY upstream module is required -- see above

const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const Module = require('module');

const XTERM = (process.env.XTERM_ROOT || 'D:/Projects/xterm.js').replace(/\\/g, '/');
const OUT_DIR = process.env.XTERM_OUT || 'out';
const PIN = { version: '6.0.0', commitPrefix: 'c58ea36' };
const ROOT = path.resolve(__dirname, '..', '..');
const MAX_FIXTURE_BYTES = 2 * 1024 * 1024; // spec 17.2 #8

// Every file a generator writes, repo-relative. regen-all.js fails when anything
// else changes.
const GENERATED = [
  'source/tyControls.Unicode.Width.Data.inc',
  'tests/fixtures/terminal-unicode-width.json',
  'tests/fixtures/terminal-unicode-join.json',
  'tests/fixtures/terminal-unicode-cases.json',
];

function git(args) {
  return cp.execFileSync('git', ['-C', XTERM, ...args], { encoding: 'utf8' }).trim();
}

function upstreamInfo() {
  const pkg = JSON.parse(fs.readFileSync(path.join(XTERM, 'package.json'), 'utf8'));
  const commit = git(['rev-parse', 'HEAD']);
  if (pkg.version !== PIN.version) throw new Error(`xterm.js at ${XTERM} is ${pkg.version}, pinned ${PIN.version}`);
  if (!commit.startsWith(PIN.commitPrefix)) throw new Error(`xterm.js HEAD ${commit}, pinned ${PIN.commitPrefix}`);
  const dirty = git(['status', '--porcelain', '--untracked-files=no']);
  if (dirty) throw new Error(`xterm.js checkout has local changes:\n${dirty}`);
  return { name: 'xterm.js', version: pkg.version, commit, commitDate: git(['log', '-1', '--format=%cs']) };
}

function need(rel) {
  const f = path.join(XTERM, rel);
  if (!fs.existsSync(f)) throw new Error(`missing ${f} -- run npm ci && npm run build in ${XTERM}`);
  return require(f);
}

function loadUpstream() {
  const info = upstreamInfo();
  process.env.NODE_PATH = path.join(XTERM, OUT_DIR);
  Module._initPaths(); // the addons require('common/...') through NODE_PATH
  require.resolve('common/services/UnicodeService'); // throws if the alias does not resolve
  const g = `addons/addon-unicode-graphemes/${OUT_DIR}`;
  return {
    info,
    Terminal: need(`${OUT_DIR}/headless/public/Terminal.js`).Terminal,
    Unicode11Addon: need(`addons/addon-unicode11/${OUT_DIR}/Unicode11Addon.js`).Unicode11Addon,
    UnicodeGraphemesAddon: need(`${g}/UnicodeGraphemesAddon.js`).UnicodeGraphemesAddon,
    UC: need(`${g}/third-party/UnicodeProperties.js`),
    UnicodeTrie: need(`${g}/third-party/unicode-trie.js`).default,
    propsSourceFile: path.join(XTERM, g, 'third-party', 'UnicodeProperties.js'),
  };
}

// A headless terminal with all four providers registered.
function makeTerminal(up) {
  const term = new up.Terminal({ allowProposedApi: true, cols: 80, rows: 24 });
  term.loadAddon(new up.Unicode11Addon());
  term.loadAddon(new up.UnicodeGraphemesAddon());
  const svc = term._core.unicodeService;
  const want = ['6', '11', '15', '15-graphemes'];
  if (svc.versions.join(',') !== want.join(',')) throw new Error('providers: ' + svc.versions.join(','));
  return term;
}

// The six variants every table and fixture is written for. 6 and 11 have no
// ambiguous data (spec 4.3), so they appear once.
const VARIANTS = [
  { id: '6', version: '6', ambiguousWide: false },
  { id: '11', version: '11', ambiguousWide: false },
  { id: '15', version: '15', ambiguousWide: false },
  { id: '15+amb', version: '15', ambiguousWide: true },
  { id: '15-graphemes', version: '15-graphemes', ambiguousWide: false },
  { id: '15-graphemes+amb', version: '15-graphemes', ambiguousWide: true },
];

// Make VARIANT active; returns the UnicodeService.
function useVariant(term, variant) {
  const svc = term._core.unicodeService;
  svc.activeVersion = variant.version;
  for (const v of ['15', '15-graphemes']) svc._providers[v].ambiguousCharsAreWide = variant.ambiguousWide;
  return svc;
}

// fn over 0..0x10FFFF as a flat run list [start0, value0, start1, value1, ...].
function runsOf(fn) {
  const out = [];
  let prev;
  for (let c = 0; c <= 0x10FFFF; c++) {
    const v = fn(c);
    if (!Number.isInteger(v) || v < 0 || v > 0x7FFFFFFF) throw new Error(`value ${v} at U+${c.toString(16)}`);
    if (c === 0 || v !== prev) { out.push(c, v); prev = v; }
  }
  return out;
}

// Decode the trie a second time from a fresh, unpooled copy of the same bytes and
// compare every code point with what the addon's own getInfo answers.
function checkTrieDecode(up) {
  const src = fs.readFileSync(up.propsSourceFile, 'utf8');
  const m = src.match(/trieRaw\s*=\s*"([A-Za-z0-9+/=]+)"/);
  if (!m) throw new Error('trieRaw not found in ' + up.propsSourceFile);
  const bytes = new Uint8Array(Buffer.from(m[1], 'base64')); // a copy: own ArrayBuffer, offset 0
  const trie = new up.UnicodeTrie(bytes);
  for (let c = 0; c <= 0x10FFFF; c++) {
    if (trie.get(c) !== up.UC.getInfo(c)) {
      throw new Error(`the addon's trie disagrees with a clean decode at U+${c.toString(16)} -- the Buffer pool fix is not in effect`);
    }
  }
  if (up.UC.getInfo(0x1F600) >> 4 !== 3) throw new Error('U+1F600 is not wide in the 15 table');
}

function writeGenerated(rel, text) {
  if (!GENERATED.includes(rel)) throw new Error(rel + ' is not listed in GENERATED');
  fs.writeFileSync(path.join(ROOT, rel), text);
  console.log('wrote', rel, text.length, 'bytes');
}

function writeFixture(name, obj) {
  const text = JSON.stringify(obj) + '\n';
  if (text.length > MAX_FIXTURE_BYTES) throw new Error(`${name}: ${text.length} bytes, cap ${MAX_FIXTURE_BYTES}`);
  writeGenerated(`tests/fixtures/${name}`, text);
}

module.exports = {
  XTERM, PIN, ROOT, GENERATED, VARIANTS,
  upstreamInfo, loadUpstream, makeTerminal, useVariant, runsOf, checkTrieDecode,
  writeGenerated, writeFixture,
};
