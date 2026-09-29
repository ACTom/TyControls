// Shared plumbing for the terminal oracle scripts: every script in this directory
// loads xterm.js through here and writes through here.
//
// Upstream: xterm.js 6.0.0, a LOCAL checkout built once (spec 13.1):
//   cd D:/Projects/xterm.js && npm ci && npm run build
// (npm ci --ignore-scripts if node-pty fails to build; we never load it.)
// XTERM_ROOT overrides the checkout path; XTERM_OUT the output folder ('out' by
// default; 'out-esbuild' if the tsgo output ever stops loading in node).
//
// Pinned: package.json version 6.0.0 and HEAD c58ea36... A different checkout, a
// dirty one, or a build older than the sources we port, is refused -- the port and
// the oracle must be the same code.
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
// else changes. An entry is an exact path or a RegExp over the repo-relative path:
// the phase 2 fixtures are cut into numbered parts by writeFixture, so their exact
// names vary with their size.
const GENERATED = [
  'source/tyControls.Unicode.Width.Data.inc',
  'tests/fixtures/terminal-unicode-width.json',
  'tests/fixtures/terminal-unicode-join.json',
  'tests/fixtures/terminal-unicode-cases.json',
  'source/tyControls.Terminal.Charsets.inc',
  /^tests\/fixtures\/terminal-(parser|buffer|core)-[a-z0-9-]+\.json$/,
  // phase 3: keyboard and paste (keyboard-cases.js), the renderer's glyph table and
  // palette (gen-terminal-glyphs.js, view-cases.js)
  /^tests\/fixtures\/terminal-keyboard(-[0-9]+)?\.json$/,
  'tests/fixtures/terminal-paste.json',
  'source/tyControls.Terminal.CustomGlyphs.inc',
  'tests/fixtures/terminal-view-palette.json',
  // phase 4: selection (selection-cases.js), links (url-cases.js), OSC 52
  // (clipboard-cases.js), mouse event mapping and geometry (mouse-cases.js)
  /^tests\/fixtures\/terminal-selection(-[0-9]+)?\.json$/,
  /^tests\/fixtures\/terminal-links(-[0-9]+)?\.json$/,
  /^tests\/fixtures\/terminal-osc52(-[0-9]+)?\.json$/,
  /^tests\/fixtures\/terminal-mouse-events(-[0-9]+)?\.json$/,
  // phase 5: reflow (reflow-cases.js: the core-reflow fixture falls under the phase 2
  // pattern above, the pure functions' fixture is its own), contrast (contrast-cases.js)
  'tests/fixtures/terminal-reflow-units.json',
  'tests/fixtures/terminal-contrast.json',
  'source/tyControls.Terminal.Luminance.inc',
];

function isGenerated(rel) {
  return GENERATED.some(g => (typeof g === 'string' ? g === rel : g.test(rel)));
}

function git(args) {
  return cp.execFileSync('git', ['-C', XTERM, ...args], { encoding: 'utf8' }).trim();
}

// A file of the pinned commit as git stores it -- NOT the working tree: with
// core.autocrlf the checkout of test/fixtures/escape_sequence_files holds CRLF, so
// reading the file would make the fixtures depend on the machine's git settings.
// upstreamInfo() has already proved HEAD is the pinned commit and the tree clean.
function gitBlob(rel) {
  return cp.execFileSync('git', ['-C', XTERM, 'show', 'HEAD:' + rel], { maxBuffer: 64 * 1024 * 1024 });
}

function upstreamInfo() {
  const pkgFile = path.join(XTERM, 'package.json');
  if (!fs.existsSync(pkgFile)) {
    throw new Error(`no xterm.js checkout at ${XTERM} -- set XTERM_ROOT (on Windows a native path, D:/..., not Git Bash's /d/...)`);
  }
  const pkg = JSON.parse(fs.readFileSync(pkgFile, 'utf8'));
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

// The pin checks the SOURCE commit, but what runs is the build output. A build left
// over from another commit (checked out after `npm run build`) would pass the pin and
// answer for the wrong code, so every source we port must be older than its output.
// Git rewrites a file's mtime when a checkout changes it, which is what this catches.
const PORTED = [
  ['src/common/input/UnicodeV6.ts', `${OUT_DIR}/common/input/UnicodeV6.js`],
  ['src/common/services/UnicodeService.ts', `${OUT_DIR}/common/services/UnicodeService.js`],
  ['addons/addon-unicode11/src/UnicodeV11.ts', `addons/addon-unicode11/${OUT_DIR}/UnicodeV11.js`],
  ['addons/addon-unicode-graphemes/src/UnicodeGraphemeProvider.ts',
    `addons/addon-unicode-graphemes/${OUT_DIR}/UnicodeGraphemeProvider.js`],
  ['addons/addon-unicode-graphemes/src/third-party/UnicodeProperties.ts',
    `addons/addon-unicode-graphemes/${OUT_DIR}/third-party/UnicodeProperties.js`],
  // phase 2: parser, buffer, core (Color.ts for relativeLuminance, copied by the
  // colour-scheme responder in lib-term.js and by the core)
  ...['common/parser/EscapeSequenceParser', 'common/parser/Params', 'common/parser/OscParser',
    'common/parser/DcsParser', 'common/parser/ApcParser', 'common/parser/Constants',
    'common/StringBuilder', 'common/input/TextDecoder', 'common/input/WriteBuffer',
    'common/input/XParseColor', 'common/buffer/Buffer', 'common/buffer/BufferLine',
    'common/buffer/AttributeData', 'common/buffer/CellData', 'common/buffer/Constants',
    'common/buffer/BufferSet', 'common/buffer/Marker', 'common/CircularList',
    'common/InputHandler', 'common/CoreTerminal', 'common/WindowsMode', 'common/data/Charsets',
    'common/data/EscapeSequences',
    'common/services/BufferService', 'common/services/CoreService',
    'common/services/CharsetService', 'common/services/MouseStateService',
    'common/services/OscLinkService', 'common/Color', 'headless/Terminal', 'headless/public/Terminal',
    // phase 3: the keyboard, paste and the third-level shift test (CoreBrowserTerminal
    // loads in node: nothing at its top level touches the DOM), the default palette
    'common/input/Keyboard', 'browser/Clipboard', 'browser/Types', 'browser/CoreBrowserTerminal',
  ].map(m => [`src/${m}.ts`, `${OUT_DIR}/${m}.js`]),
  // phase 3: the box-drawing and block glyphs the WebGL addon draws itself
  ['addons/addon-webgl/src/customGlyphs/CustomGlyphDefinitions.ts',
    `addons/addon-webgl/${OUT_DIR}/customGlyphs/CustomGlyphDefinitions.js`],
  // phase 4: the selection, the mouse, links, OSC 52 (loadBrowserParts)
  ...['browser/services/SelectionService', 'browser/selection/SelectionModel', 'browser/input/Mouse',
    'browser/services/MouseService', 'browser/OscLinkProvider', 'browser/Linkifier',
    'browser/renderer/dom/DomRendererRowFactory', 'common/buffer/BufferRange',
  ].map(m => [`src/${m}.ts`, `${OUT_DIR}/${m}.js`]),
  ['addons/addon-web-links/src/WebLinkProvider.ts', `addons/addon-web-links/${OUT_DIR}/WebLinkProvider.js`],
  ['addons/addon-web-links/src/WebLinksAddon.ts', `addons/addon-web-links/${OUT_DIR}/WebLinksAddon.js`],
  ['addons/addon-clipboard/src/ClipboardAddon.ts', `addons/addon-clipboard/${OUT_DIR}/ClipboardAddon.js`],
  // phase 5: reflow; the contrast functions, the glyphs drawn as background and the
  // option's clamp
  ...['common/buffer/BufferReflow', 'browser/renderer/shared/RendererUtils', 'browser/ColorContrastCache',
    'common/services/OptionsService',
  ].map(m => [`src/${m}.ts`, `${OUT_DIR}/${m}.js`]),
];

function checkBuildFresh() {
  for (const [src, out] of PORTED) {
    const s = path.join(XTERM, src), o = path.join(XTERM, out);
    if (!fs.existsSync(o)) throw new Error(`missing ${o} -- run npm ci && npm run build in ${XTERM}`);
    if (fs.statSync(s).mtimeMs > fs.statSync(o).mtimeMs) {
      throw new Error(`${out} is older than ${src} -- the build is stale; rerun npm run build in ${XTERM}`);
    }
  }
}

function loadUpstream() {
  const info = upstreamInfo();
  checkBuildFresh();
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

// PHASE 4: THE BROWSER LAYER. The selection service, the mouse service's event
// mapping, the link providers, the Linkifier and the clipboard addon are browser-layer
// code, but none of the parts we port touches the DOM: they run in node on a headless
// terminal, called through their prototypes or constructed with the few fake objects
// fakeBrowser() makes. The fakes only hand back points and sizes -- no logic.
// Call after loadUpstream() (NODE_PATH must be set for the addons).
function loadBrowserParts() {
  const o = p => need(`${OUT_DIR}/${p}.js`);
  const wl = `addons/addon-web-links/${OUT_DIR}`;
  const { WebLinksAddon } = need(`${wl}/WebLinksAddon.js`);
  // strictUrlRegex is not exported: activate the addon on a fake terminal that only
  // records the provider it is given, and read the provider's _regex.
  let captured;
  new WebLinksAddon().activate({ registerLinkProvider: p => { captured = p; return { dispose() {} }; } });
  const strictUrlRegex = captured && captured._regex;
  if (!(strictUrlRegex instanceof RegExp)) throw new Error('WebLinksAddon did not hand its regex to registerLinkProvider');
  // the same text as the pinned source's line (a stale or edited build is refused)
  const src = gitBlob('addons/addon-web-links/src/WebLinksAddon.ts').toString('utf8');
  const m = src.match(/^const strictUrlRegex = \/(.*)\/;\r?$/m);
  if (!m) throw new Error('strictUrlRegex not found in WebLinksAddon.ts');
  if (m[1] !== strictUrlRegex.source || strictUrlRegex.flags !== '') {
    throw new Error(`strictUrlRegex: the build has /${strictUrlRegex.source}/${strictUrlRegex.flags}, the source /${m[1]}/`);
  }
  return {
    SelectionService: o('browser/services/SelectionService').SelectionService,
    DomRendererRowFactory: o('browser/renderer/dom/DomRendererRowFactory').DomRendererRowFactory,
    Linkifier: o('browser/Linkifier').Linkifier,
    OscLinkProvider: o('browser/OscLinkProvider').OscLinkProvider,
    MouseService: o('browser/services/MouseService').MouseService,
    getCoords: o('browser/input/Mouse').getCoords,
    LinkComputer: need(`${wl}/WebLinkProvider.js`).LinkComputer,
    strictUrlRegex,
    ClipboardAddon: need(`addons/addon-clipboard/${OUT_DIR}/ClipboardAddon.js`).ClipboardAddon,
  };
}

// The objects SelectionService's constructor and handlers read, for a terminal of
// ROWS rows whose cells are CELL_H CSS pixels high. state.point is the point the
// next getCoords answers (1-based, as getCoords answers), state.link the Linkifier's
// currentLink. Nothing here decides anything.
const CELL_H = 10;
function fakeBrowser(rows, state) {
  const doc = { addEventListener() {}, removeEventListener() {} };
  const screenElement = { ownerDocument: doc, getBoundingClientRect: () => ({ left: 0, top: 0 }) };
  const element = { ownerDocument: doc, getBoundingClientRect: () => ({ left: 0, top: 0 }) };
  const window = {
    requestAnimationFrame: () => 0, setInterval: () => 1, clearInterval() {},
    getComputedStyle: () => ({ getPropertyValue: () => '0' }),
  };
  return {
    element, screenElement, window,
    linkifier: { get currentLink() { return state.link; } },
    // a fresh array every call: the model keeps it and changes it in place
    mouseCoordsService: { getCoords: () => (state.point ? [state.point[0], state.point[1]] : undefined) },
    // ROWS may be a function: the terminal's rows now (a case may resize)
    renderService: { dimensions: { css: { canvas: { get height() { return (typeof rows === 'function' ? rows() : rows) * CELL_H; } } } } },
    coreBrowserService: { window, dpr: 1 },
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

// A file whose text is unchanged is left alone, line endings included: with
// core.autocrlf the checkout holds CRLF, and rewriting it as LF makes git status
// report it modified although `git diff` is empty -- regen-all.js would call a
// byte-identical rerun dirty.
function writeGenerated(rel, text) {
  if (!isGenerated(rel)) throw new Error(rel + ' is not listed in GENERATED');
  const f = path.join(ROOT, rel);
  if (fs.existsSync(f) && fs.readFileSync(f, 'utf8').replace(/\r\n/g, '\n') === text) {
    console.log('unchanged', rel, text.length, 'bytes');
    return;
  }
  fs.writeFileSync(f, text);
  console.log('wrote', rel, text.length, 'bytes');
}

const SPLIT_BYTES = 1800000; // a fixture with "cases" is cut above this (2 MB cap, margin)
const FIXTURE_DIR = path.join(ROOT, 'tests', 'fixtures');

// The files NAME may have been written as before -- the single file and the numbered
// parts name-<n>.json -- minus KEEP. Only files isGenerated() accepts are returned.
function otherShapes(name, keep) {
  const base = name.replace(/\.json$/, '');
  return fs.readdirSync(FIXTURE_DIR).filter(f => {
    if (keep.includes(f) || !isGenerated('tests/fixtures/' + f)) return false;
    if (f === name) return true;
    return f.startsWith(base + '-') && /^[0-9]+\.json$/.test(f.slice(base.length + 1));
  });
}

// NAME is a file name under tests/fixtures. An object with a "cases" array whose
// JSON exceeds SPLIT_BYTES is cut, in case order, into name-1.json, name-2.json ...
// each with the same shell and "part" / "parts" filled in; otherwise it is one file
// with part 1 of 1. What an earlier run left in the other shape (single <-> parts,
// fewer parts than last time) is deleted, so a stale part cannot survive. Objects
// without "cases" (the phase 1 fixtures) keep the plain 2 MB check.
function writeFixture(name, obj) {
  if (!Array.isArray(obj.cases)) {
    const text = JSON.stringify(obj) + '\n';
    if (Buffer.byteLength(text) > MAX_FIXTURE_BYTES) throw new Error(`${name}: ${Buffer.byteLength(text)} bytes, cap ${MAX_FIXTURE_BYTES}`);
    writeGenerated(`tests/fixtures/${name}`, text);
    return;
  }
  const shell = Object.assign({}, obj);
  delete shell.cases;
  const withParts = (part, parts, cases) => JSON.stringify(Object.assign({}, shell, { part, parts, cases })) + '\n';
  const whole = withParts(1, 1, obj.cases);
  const written = [];
  if (Buffer.byteLength(whole) <= SPLIT_BYTES) {
    writeGenerated(`tests/fixtures/${name}`, whole);
    written.push(name);
  } else {
    const shellBytes = Buffer.byteLength(withParts(999, 999, []));
    const groups = [];
    let cur = [], size = shellBytes;
    for (const c of obj.cases) {
      const n = Buffer.byteLength(JSON.stringify(c)) + 1;
      if (shellBytes + n > SPLIT_BYTES) throw new Error(`${name}: case ${c.id} alone is ${n} bytes -- split the case`);
      if (cur.length && size + n > SPLIT_BYTES) { groups.push(cur); cur = []; size = shellBytes; }
      cur.push(c);
      size += n;
    }
    if (cur.length) groups.push(cur);
    const base = name.replace(/\.json$/, '');
    groups.forEach((g, k) => {
      const f = `${base}-${k + 1}.json`;
      const text = withParts(k + 1, groups.length, g);
      if (Buffer.byteLength(text) > MAX_FIXTURE_BYTES) throw new Error(`${f}: ${Buffer.byteLength(text)} bytes, cap ${MAX_FIXTURE_BYTES}`);
      writeGenerated(`tests/fixtures/${f}`, text);
      written.push(f);
    });
  }
  for (const f of otherShapes(name, written)) {
    fs.unlinkSync(path.join(FIXTURE_DIR, f));
    console.log('removed', 'tests/fixtures/' + f);
  }
  return written;
}

module.exports = {
  XTERM, OUT_DIR, PIN, ROOT, GENERATED, VARIANTS,
  upstreamInfo, loadUpstream, makeTerminal, useVariant, runsOf, checkTrieDecode,
  writeGenerated, writeFixture, isGenerated, gitBlob,
  loadBrowserParts, fakeBrowser, CELL_H,
};
