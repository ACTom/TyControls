// Shared plumbing for the whole-terminal oracle scripts (parser-cases.js is the one
// exception that drives the parser alone): build a headless xterm.js terminal from a
// fixture case, run its steps, and export the complete state the Pascal port is
// compared with. Upstream is loaded ONLY through lib-dump.js (pin, clean tree,
// fresh build, Buffer-pool fix).
//
// The fixture format -- the case shell, the options, the steps and the exported
// <state> / <buf> -- is written down in docs/superpowers/plans/
// 2026-09-28-terminal-phase-2.md, section "夹具格式"; this file implements it.
//
// THE RESPONDER. Headless xterm.js answers nothing that needs a theme or a focus:
// colour queries (OSC 4/10/11/12 "?"), the colour-scheme query (CSI ? 996 n), the
// unsolicited colour-scheme report of DECSET 2031, and the focus report that DECSET
// 1004 triggers. The Pascal core answers all of them itself, so every core case
// gets attachSynth(), copied from the browser layer:
//   src/browser/CoreBrowserTerminal.ts:204-258  _handleColorEvent (report/set/restore)
//   src/browser/CoreBrowserTerminal.ts:261-268  _reportColorScheme
//   src/browser/CoreBrowserTerminal.ts:305-331  focus / blur reports
//   src/browser/CoreBrowserTerminal.ts:523-531  2031: a report on every colour change
//   src/browser/CoreBrowserTerminal.ts:1124-1130 _reportFocus when 1004 is set
//   src/browser/services/ThemeService.ts:80-183 set, restore, a theme drops overrides
//   src/common/Color.ts:236-259                 relativeLuminance
//   src/common/input/XParseColor.ts:58-80       toRgbString
'use strict';
const L = require('./lib-dump.js');

// ---- small helpers -------------------------------------------------------------

const b64 = bytes => Buffer.from(bytes).toString('base64');
const unb64 = s => Buffer.from(s, 'base64');
const utf8 = s => Buffer.from(s, 'utf8');
const cps = str => { const out = []; for (const ch of str) out.push(ch.codePointAt(0)); return out; };

// 32-bit FNV-1a over code points (plan, "长串摘要"). The Pascal side has the same
// formula once, in tests/test.terminal.oracle.pas.
function digestCps(list) {
  let h = 0x811C9DC5;
  for (const cp of list) h = Math.imul(h ^ cp, 0x01000193) >>> 0;
  return h;
}

// A string or a code point array: kept as it is up to 256 code points, otherwise
// replaced by { n: code points, h: digest }. A string keeps being a string -- unless
// it holds U+0000, which fpjson drops from a JSON string: then it is written as its
// code point array (the Pascal side reads both shapes the same way).
function digestable(x) {
  const list = typeof x === 'string' ? cps(x) : Array.from(x);
  if (list.length <= 256) return typeof x === 'string' && x.includes('\u0000') ? list : x;
  return { n: list.length, h: digestCps(list) };
}

// mulberry32; the seed goes into the fixture.
function prng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---- options and palette ---------------------------------------------------------

const DEFAULT_OPTIONS = {
  scrollback: 1000, tabStopWidth: 8, convertEol: false, scrollOnUserInput: true,
  disableStdin: false, scrollOnEraseInDisplay: false, cursorStyle: 'block', cursorBlink: false,
  allowSetCursorBlink: false, unicodeVersion: '11', ambiguousWide: false, windowsPty: null,
  windowOptions: [], reflowCursorLine: false,
  vtExtensions: { kittyKeyboard: false, win32InputMode: false, kittySgrBoldFaintControl: true, colorSchemeQuery: true },
};

// 0-15: xterm.js's default theme (src/browser/Types.ts:183-203); 16-231 the 6x6x6
// cube; 232-255 greys; 256 foreground, 257 background, 258 cursor
// (ThemeService.ts:23-25).
const DEFAULT_PALETTE = (() => {
  const p = [0x2e3436, 0xcc0000, 0x4e9a06, 0xc4a000, 0x3465a4, 0x75507b, 0x06989a, 0xd3d7cf,
    0x555753, 0xef2929, 0x8ae234, 0xfce94f, 0x729fcf, 0xad7fa8, 0x34e2e2, 0xeeeeec];
  const v = [0x00, 0x5f, 0x87, 0xaf, 0xd7, 0xff];
  for (let i = 0; i < 216; i++) p.push((v[(i / 36) % 6 | 0] << 16) | (v[(i / 6) % 6 | 0] << 8) | v[i % 6]);
  for (let i = 0; i < 24; i++) { const c = 8 + i * 10; p.push((c << 16) | (c << 8) | c); }
  p.push(0xffffff, 0x000000, 0xffffff);
  return p;
})();

// Fill in the defaults for running; normalizeOptions() below writes the other shape.
function fullOptions(o) {
  const r = Object.assign({}, DEFAULT_OPTIONS, o || {});
  r.vtExtensions = Object.assign({}, DEFAULT_OPTIONS.vtExtensions, (o || {}).vtExtensions || {});
  return r;
}

// The case's options with only the keys that differ from DEFAULT_OPTIONS (fixture
// size); writes them back into the case and returns it.
function normalizeOptions(c) {
  const full = fullOptions(c.options);
  const out = {};
  for (const k of Object.keys(DEFAULT_OPTIONS)) {
    if (k === 'vtExtensions') {
      const d = {};
      for (const e of Object.keys(DEFAULT_OPTIONS.vtExtensions)) {
        if (full.vtExtensions[e] !== DEFAULT_OPTIONS.vtExtensions[e]) d[e] = full.vtExtensions[e];
      }
      if (Object.keys(d).length) out.vtExtensions = d;
    } else if (JSON.stringify(full[k]) !== JSON.stringify(DEFAULT_OPTIONS[k])) {
      out[k] = full[k];
    }
  }
  if (Object.keys(out).length) c.options = out; else delete c.options;
  return c;
}

function writeCoreFixture(name, kind, cases, generator) {
  return L.writeFixture(name, {
    upstream: L.upstreamInfo(),
    generator: 'tools/terminal-oracle/' + generator,
    kind,
    palette: DEFAULT_PALETTE,
    cases,
  });
}

// ---- building and driving a terminal ---------------------------------------------

function makeCaseTerminal(up, c) {
  const o = fullOptions(c.options);
  const windowOptions = {};
  for (const n of o.windowOptions) windowOptions[n] = true;
  const term = new up.Terminal({
    allowProposedApi: true, logLevel: 'off',
    cols: c.cols ?? 20, rows: c.rows ?? 6,
    scrollback: o.scrollback, tabStopWidth: o.tabStopWidth, convertEol: o.convertEol,
    scrollOnUserInput: o.scrollOnUserInput, disableStdin: o.disableStdin,
    scrollOnEraseInDisplay: o.scrollOnEraseInDisplay, cursorStyle: o.cursorStyle,
    cursorBlink: o.cursorBlink, windowsPty: o.windowsPty ?? {}, windowOptions, reflowCursorLine: o.reflowCursorLine,
    vtExtensions: o.vtExtensions, quirks: { allowSetCursorBlink: o.allowSetCursorBlink },
  });
  term.loadAddon(new up.Unicode11Addon());
  term.loadAddon(new up.UnicodeGraphemesAddon());
  L.useVariant(term, { version: o.unicodeVersion, ambiguousWide: o.ambiguousWide });
  return term;
}

function newRecord() {
  return { data: [], bells: 0, titles: [], renders: [], scrolls: [], lineFeeds: 0, cursorMoves: 0 };
}

// The listeners stay attached for the terminal's life; holder.cur is swapped for a
// fresh record when a case is run again after reset().
function attachRecorders(term) {
  const holder = { cur: newRecord() };
  term.onData(d => holder.cur.data.push(d));
  term.onBell(() => holder.cur.bells++);
  term.onTitleChange(t => holder.cur.titles.push(t));
  term.onRender(e => holder.cur.renders.push([e.start, e.end]));
  term.onScroll(p => holder.cur.scrolls.push(p));
  term.onLineFeed(() => holder.cur.lineFeeds++);
  term.onCursorMove(() => holder.cur.cursorMoves++);
  return holder;
}

function relativeLuminance(rgb) {
  const f = c => { const s = c / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
  return f((rgb >> 16) & 0xFF) * 0.2126 + f((rgb >> 8) & 0xFF) * 0.7152 + f(rgb & 0xFF) * 0.0722;
}

function rgbString(rgb) {
  const pad = n => { const s = n.toString(16); const s2 = s.length < 2 ? '0' + s : s; return s2 + s2; };
  return `rgb:${pad((rgb >> 16) & 255)}/${pad((rgb >> 8) & 255)}/${pad(rgb & 255)}`;
}

function attachSynth(term, palette, focused) {
  const core = term._core;
  const ih = core._inputHandler;
  const send = s => core.coreService.triggerDataEvent(s);
  const st = { base: palette.slice(), cur: palette.slice(), focused };
  const reportScheme = () => send(`\x1b[?997;${relativeLuminance(st.cur[257]) < relativeLuminance(st.cur[256]) ? 1 : 2}n`);
  const changed = () => { if (core.coreService.decPrivateModes.colorSchemeUpdates) reportScheme(); };
  ih.onColor(ev => {
    for (const req of ev) {
      const ident = req.index === 256 ? '10' : req.index === 257 ? '11' : req.index === 258 ? '12' : '4;' + req.index;
      if (req.type === 0) { // REPORT
        send(`\x1b]${ident};${rgbString(st.cur[req.index])}\x1b\\`);
      } else if (req.type === 1) { // SET
        st.cur[req.index] = ((req.color[0] & 255) << 16) | ((req.color[1] & 255) << 8) | (req.color[2] & 255);
        changed();
      } else { // RESTORE: no index = the 256 palette entries only (ThemeService.ts:156-161)
        if (req.index === undefined) { for (let i = 0; i < 256; i++) st.cur[i] = st.base[i]; } else st.cur[req.index] = st.base[req.index];
        changed();
      }
    }
  });
  ih.onRequestColorSchemeQuery(() => reportScheme());
  ih.onRequestSendFocus(() => send(st.focused ? '\x1b[I' : '\x1b[O'));
  return {
    focus(f) {
      st.focused = f;
      if (core.coreService.decPrivateModes.sendFocus) send(f ? '\x1b[I' : '\x1b[O');
    },
    theme(p) {
      st.base = p.slice();
      st.cur = p.slice();
      changed();
    },
  };
}

// A write step is one WriteBuffer chunk, parsed before the next step runs -- the
// same parse call term.write(data, callback) makes once its timer fires; writeSync
// makes it without waiting for a timer per chunk (thousands of them for a byte-by-
// byte variant). Phase 5 adds { marker: n }: term.registerMarker(n), a marker on the
// line n below the cursor's (ybase + y + n, headless/Terminal.ts:72-74) -- no handle
// is kept, the export reads the buffer's live markers.
async function runSteps(up, term, synthApi, steps) {
  for (const s of steps) {
    if (s.write !== undefined) {
      term._core.writeSync(unb64(s.write));
    } else if (s.writeRepeat) {
      const b = unb64(s.writeRepeat.b64);
      for (let k = 0; k < s.writeRepeat.times; k++) term._core.writeSync(b);
    } else if (s.resize) term.resize(s.resize[0], s.resize[1]);
    else if (s.input !== undefined) term.input(new TextDecoder().decode(unb64(s.input)), s.user);
    else if (s.reset) term.reset();
    else if (s.clear) term.clear();
    else if (s.scrollLines !== undefined) term.scrollLines(s.scrollLines);
    else if (s.scrollToTop) term.scrollToTop();
    else if (s.scrollToBottom) term.scrollToBottom();
    else if (s.setOption) {
      for (const [k, v] of Object.entries(s.setOption)) {
        if (k === 'windowsPty') term.options.windowsPty = v ?? {};
        else if (k === 'allowSetCursorBlink') term.options.quirks = { allowSetCursorBlink: v };
        else term.options[k] = v;
      }
    } else if (s.marker !== undefined) term.registerMarker(s.marker);
    else if (s.focus !== undefined) synthApi.focus(s.focus);
    else if (s.theme) synthApi.theme(s.theme);
    else throw new Error('unknown step ' + JSON.stringify(s));
  }
}

// ---- export ----------------------------------------------------------------------

const DEFAULT_CELL_CONTENT = 1 << 22; // NULL cell: code 0, width 1

// One line in the <buf>.lines shape. The text cache of the line is saved and
// restored around translateToString so the export cannot change later answers.
function dumpLineOnly(line, cols, keepDefault) {
  const d = line._data;
  const n = line.length;
  const c = [];
  let isDefault = n === cols && !line.isWrapped;
  const comb = {}, ext = {};
  let hasComb = false, hasExt = false;
  for (let i = 0; i < n; i++) {
    const content = d[i * 3] >>> 0, fg = d[i * 3 + 1] >>> 0, bg = d[i * 3 + 2] >>> 0;
    if (content !== DEFAULT_CELL_CONTENT || fg !== 0 || bg !== 0) isDefault = false;
    const last = c[c.length - 1];
    if (last && last[0] === content && last[1] === fg && last[2] === bg) last[3]++;
    else c.push([content, fg, bg, 1]);
    // A flag without its side-table entry is possible (copyFrom / clone with blank on
    // a line that had combined or extended cells): exported as null.
    if (content & 0x200000) {
      comb[i] = line._combined[i] === undefined ? null : cps(line._combined[i]);
      hasComb = true;
    }
    if (bg & 0x10000000) {
      const e = line._extendedAttrs[i];
      ext[i] = e ? [e.ext >>> 0, e.urlId, e.underlineColor >>> 0, e.underlineVariantOffset] : null;
      hasExt = true;
    }
  }
  if (hasComb || hasExt) isDefault = false;
  if (isDefault && !keepDefault) return null;
  const saved = [line._cacheValid, line._cache, line._cacheTrimmed];
  const t = line.translateToString(true);
  [line._cacheValid, line._cache, line._cacheTrimmed] = saved;
  const out = {};
  if (line.isWrapped) out.w = 1;
  if (n !== cols) out.len = n;
  out.t = digestable(t);
  out.c = c;
  if (hasComb) out.comb = comb;
  if (hasExt) out.ext = ext;
  return out;
}

// The first CHARSETS key (for...in order) whose table is the given object.
function charsetKey(up, cs) {
  if (cs === undefined) return null;
  const C = up.Charsets.CHARSETS;
  for (const k in C) if (C[k] === cs) return k;
  throw new Error('charset object not in CHARSETS');
}

function dumpBuffer(up, term, buf, keepDefault) {
  const cols = term._core._bufferService.cols;
  const lines = [];
  for (let i = 0; i < buf.lines.length; i++) {
    const line = buf.lines.get(i);
    if (!line) { lines.push({ i, missing: 1 }); continue; }
    const o = dumpLineOnly(line, cols, keepDefault);
    if (o) lines.push(Object.assign({ i }, o));
  }
  return {
    x: buf.x, y: buf.y, ybase: buf.ybase, ydisp: buf.ydisp, length: buf.lines.length,
    maxLength: buf.lines.maxLength, hasScrollback: buf.hasScrollback,
    scrollTop: buf.scrollTop, scrollBottom: buf.scrollBottom,
    tabs: Object.keys(buf.tabs).filter(k => buf.tabs[k]).map(Number).sort((a, b) => a - b),
    saved: {
      x: buf.savedX, y: buf.savedY, fg: buf.savedCurAttrData.fg >>> 0, bg: buf.savedCurAttrData.bg >>> 0,
      glevel: buf.savedGlevel, origin: buf.savedOriginMode, wrap: buf.savedWraparoundMode,
      charset: charsetKey(up, buf.savedCharset),
      charsets: Array.from({ length: buf.savedCharsets.length }, (_, k) => charsetKey(up, buf.savedCharsets[k])),
    },
    markers: buf.markers.filter(m => !m.isDisposed).map(m => m.line),
    lines,
  };
}

function dumpLinks(term) {
  const svc = term._core._oscLinkService;
  return [...svc._dataByLinkId.values()].sort((a, b) => a.id - b.id).map(e => ({
    linkId: e.id, id: e.data.id === undefined ? null : e.data.id, uri: e.data.uri, lines: e.lines.map(m => m.line),
  }));
}

const PROTOCOLS = { NONE: 'NONE', X10: 'X10', VT200: 'VT200', DRAG: 'DRAG', ANY: 'ANY' };

// An AttributeData as { fg, bg, ext: [ext, urlId, underlineColor, underlineVariantOffset] }
// -- the same four the line export gives an extended cell.
function dumpAttr(a) {
  const e = a.extended;
  return { fg: a.fg >>> 0, bg: a.bg >>> 0, ext: [e.ext >>> 0, e.urlId, e.underlineColor >>> 0, e.underlineVariantOffset] };
}

function dumpState(up, term, rec) {
  const core = term._core;
  const ih = core._inputHandler;
  const bs = core._bufferService;
  const dm = core.coreService.decPrivateModes;
  const kb = core.coreService.kittyKeyboard;
  const cs = core._charsetService;
  const data = Buffer.from(rec.data.join('').split('xterm.js(6.0.0)').join('\u0000VERSION\u0000'), 'utf8');
  return {
    active: bs.buffers.active === bs.buffers.alt ? 'alt' : 'normal',
    isUserScrolling: bs.isUserScrolling,
    buffers: { normal: dumpBuffer(up, term, bs.buffers.normal, false), alt: dumpBuffer(up, term, bs.buffers.alt, false) },
    modes: {
      applicationCursorKeys: dm.applicationCursorKeys, applicationKeypad: dm.applicationKeypad,
      bracketedPaste: dm.bracketedPasteMode, insert: core.coreService.modes.insertMode, origin: dm.origin,
      reverseWraparound: dm.reverseWraparound, sendFocus: dm.sendFocus, showCursor: !core.coreService.isCursorHidden,
      synchronizedOutput: dm.synchronizedOutput, win32Input: dm.win32InputMode, wraparound: dm.wraparound,
      colorSchemeUpdates: dm.colorSchemeUpdates, mouseProtocol: PROTOCOLS[core.mouseStateService.activeProtocol],
      mouseEncoding: core.mouseStateService.activeEncoding, cursorStyle: dm.cursorStyle ?? null,
      cursorBlink: dm.cursorBlink ?? null, kittyFlags: kb.flags,
      kittyStacks: [kb.mainFlags, kb.altFlags, kb.mainStack.slice(), kb.altStack.slice()],
      cursorInitialized: core.coreService.isCursorInitialized,
    },
    options: { convertEol: core.optionsService.rawOptions.convertEol, cursorBlink: core.optionsService.rawOptions.cursorBlink },
    charset: { glevel: cs.glevel, g: [0, 1, 2, 3].map(g => charsetKey(up, cs.charsets[g])) },
    // the attributes the next character and the next erase take
    curAttr: dumpAttr(ih._curAttrData), eraseAttr: dumpAttr(ih._eraseAttrDataInternal),
    title: digestable(ih._windowTitle), iconName: digestable(ih._iconName),
    titleStacks: [ih._windowTitleStack.map(digestable), ih._iconNameStack.map(digestable)],
    bells: rec.bells, lineFeeds: rec.lineFeeds, cursorMoves: rec.cursorMoves,
    titles: rec.titles.map(digestable), renders: rec.renders.map(r => r.slice()), scrolls: rec.scrolls.slice(),
    data: b64(data), links: dumpLinks(term),
    parserState: ih._parser.currentState, joinState: ih._parser.precedingJoinState,
  };
}

// ---- running a case --------------------------------------------------------------

// REP's fast-forward in the Pascal core (tyControls.Terminal.Core, DoPrint) skips
// whole periods of scrolls and sends no OnScroll for them. It can only skip once a
// REP's count passes 2 x ring + rows + 2 (the scrolls it prints for real first; a
// repetition scrolls at most once), so a case with such a REP gets "ignore":
// ["scrolls"] -- the rest of its state must still be equal. Watched through a CSI b
// handler that looks and passes on (returns false).
function watchRep(term) {
  const w = { fastForward: false };
  term._core._inputHandler._parser.registerCsiHandler({ final: 'b' }, params => {
    const count = params.params[0] || 1;
    const buf = term._core.buffer;
    if (count > 2 * buf.lines.maxLength + term.rows + 2) w.fastForward = true;
    return false;
  });
  return w;
}

function markIgnore(c, w) {
  if (!w.fastForward) return;
  const list = c.ignore || [];
  if (!list.includes('scrolls')) list.push('scrolls');
  c.ignore = list;
}

async function runCase(up, c, palette = DEFAULT_PALETTE) {
  const term = makeCaseTerminal(up, c);
  const holder = attachRecorders(term);
  const synth = attachSynth(term, (c.synth && c.synth.palette) || palette, c.synth && c.synth.focused !== undefined ? c.synth.focused : true);
  const rep = watchRep(term);
  await runSteps(up, term, synth, c.steps);
  markIgnore(c, rep);
  const expect = dumpState(up, term, holder.cur);
  term.reset();
  holder.cur = newRecord();
  await runSteps(up, term, synth, c.steps);
  const second = dumpState(up, term, holder.cur);
  term.dispose();
  return { expect, afterReset: JSON.stringify(second) === JSON.stringify(expect) ? 'same' : second };
}

// What a cut-up feed may change: onRender and onCursorMove fire once per parse call,
// so their count follows the number of pieces. Everything else must be identical.
function variantView(state) {
  const s = Object.assign({}, state);
  delete s.renders;
  delete s.cursorMoves;
  return JSON.stringify(s);
}

// Byte offsets -> pieces of BYTES ("each" = one byte per piece).
function cutPieces(bytes, cuts) {
  if (cuts === 'each') return Array.from(bytes, b => Buffer.from([b]));
  const out = [];
  let prev = 0;
  for (const k of cuts) { out.push(bytes.subarray(prev, k)); prev = k; }
  out.push(bytes.subarray(prev));
  return out;
}

// n sorted, distinct cut offsets inside 1..len-1 from rnd.
function randomCuts(rnd, len, n) {
  const set = new Set();
  if (len < 2) return [];
  for (let k = 0; k < n * 4 && set.size < n; k++) set.add(1 + Math.floor(rnd() * (len - 1)));
  return [...set].sort((a, b) => a - b);
}

// Only for a case whose steps are exactly one write: every variant, fed in pieces
// (one parse call per piece; writeSync, or term.write when SYNC is false), must give
// the same state as EXPECT apart from variantView's two fields.
async function checkVariants(up, c, expect, sync = true) {
  if (!c.variants) return;
  if (c.steps.length !== 1 || c.steps[0].write === undefined) throw new Error(c.id + ': variants need a single write');
  const bytes = unb64(c.steps[0].write);
  const want = variantView(expect);
  for (const v of c.variants) {
    const term = makeCaseTerminal(up, c);
    const holder = attachRecorders(term);
    attachSynth(term, (c.synth && c.synth.palette) || DEFAULT_PALETTE, c.synth && c.synth.focused !== undefined ? c.synth.focused : true);
    for (const p of cutPieces(bytes, v.cuts)) {
      if (sync) term._core.writeSync(p);
      else await new Promise(r => term.write(p, r));
    }
    const got = variantView(dumpState(up, term, holder.cur));
    term.dispose();
    if (got !== want) {
      let k = 0;
      while (k < got.length && got[k] === want[k]) k++;
      throw new Error(`${c.id}: variant ${JSON.stringify(v.cuts).slice(0, 60)} differs at ${k}:\n  want ...${want.slice(Math.max(0, k - 80), k + 80)}\n  got  ...${got.slice(Math.max(0, k - 80), k + 80)}`);
    }
  }
}

// Upstream with the extra modules the core scripts read directly.
function loadUpstream() {
  const up = L.loadUpstream();
  const path = require('path');
  up.Charsets = require(path.join(L.XTERM, L.OUT_DIR, 'common/data/Charsets.js'));
  return up;
}

module.exports = {
  L, b64, unb64, utf8, cps, digestCps, digestable, prng,
  DEFAULT_OPTIONS, DEFAULT_PALETTE, fullOptions, normalizeOptions, writeCoreFixture,
  loadUpstream, makeCaseTerminal, attachRecorders, newRecord, attachSynth, runSteps,
  dumpLineOnly, dumpBuffer, dumpLinks, dumpState, dumpAttr, charsetKey,
  runCase, checkVariants, variantView, cutPieces, randomCuts, relativeLuminance, rgbString,
};
