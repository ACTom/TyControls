// Writes the three parser fixtures for tests/test.terminal.parser.pas by running
// xterm.js 6.0.0's own EscapeSequenceParser and Utf8ToUtf32 (no terminal around
// them). Upstream path and pin: lib-dump.js, through lib-term.js. Inputs:
// cases/parser.js.
//
//   node tools/terminal-oracle/parser-cases.js
//
// The shell of every fixture is the one in docs/superpowers/plans/
// 2026-09-28-terminal-phase-2.md, "夹具格式"; per file:
//
// tests/fixtures/terminal-parser-table.json
//   "table": VT500_TRANSITION_TABLE.table (4257 entries) as runs
//            [start0, value0, start1, value1, ...], each value holding up to the next
//            start.
//
// tests/fixtures/terminal-parser-utf8.json
//   cases: { id, source, chunks: [base64...], out: [[cp...] ...] } -- out[k] is what
//   the k-th decode() call of ONE Utf8ToUtf32 returned.
//
// tests/fixtures/terminal-parser-trace.json (split into -<n> parts when large)
//   cases: { id, source, cut?, register, feed, trace, finalState, finalJoinState }
//   source "hand" (cut = the code point offset for the cut-in-two copies), "long",
//   "fuzz". feed items: { cp: [...] } | { fill: [cp, n], times? } |
//   { repeat: { cp: [...], times } } | { reset: 1 } | { unregister: k } -- one
//   parse() call each (times calls for fill / repeat).
//
//   register items and the events their handlers record:
//     { csi: {prefix?, intermediates?, final}, ret }  ["h", k, "csi", paramsJson]
//     { esc: {...}, ret }                             ["h", k, "esc"]
//     { exec: code }                                  ["h", k, "exec"]
//     { osc: ident, kind: "string", ret }             ["h", k, "osc", payload]
//     { osc: ident, kind: "raw", ret }                ["h", k, "osc-start"],
//                                                     ["h", k, "osc-put", cps],
//                                                     ["h", k, "osc-end", success]
//     { dcs: {...}, kind: "string", ret }             ["h", k, "dcs", payload, paramsJson]
//     { dcs: {...}, kind: "raw", ret }                "dcs-hook" paramsJson, "dcs-put" cps,
//                                                     "dcs-unhook" success
//     { apc: {...}, kind: "string" | "raw", ret }     "apc" / "apc-start" / "apc-put" /
//                                                     "apc-end" (as OSC)
//   The print handler always records ["print", cps] and then sets precedingJoinState
//   to the segment's last code point (any non-zero value: it shows which later
//   actions clear it). The six fallbacks record ["exec", code], ["csi", ident,
//   paramsJson], ["esc", ident], ["osc", ident, action, payload|null, success|null],
//   ["dcs", ident, action, paramsJson (HOOK) | payload (PUT) | null, success|null],
//   ["apc", ...as osc]; the error handler ["error", code, state] and returns the state
//   unchanged. An OSC ident above 2147483647 is recorded as "big": upstream keeps it
//   as a float (Infinity after 309 digits), the port saturates, and all that can be
//   compared is that it matches no handler.
//   paramsJson = JSON.stringify(params.toArray()). Payloads and code point lists go
//   through lib-term.js digestable(): over 256 code points they become { n, h }.
'use strict';
const path = require('path');
const T = require('./lib-term.js');
const L = T.L;
const C = require('./cases/parser.js');

const up = L.loadUpstream();
const out = p => require(path.join(L.XTERM, L.OUT_DIR, p));
const EP = out('common/parser/EscapeSequenceParser.js');
const { OscHandler } = out('common/parser/OscParser.js');
const { DcsHandler } = out('common/parser/DcsParser.js');
const { ApcHandler } = out('common/parser/ApcParser.js');
const { Utf8ToUtf32 } = out('common/input/TextDecoder.js');
const shell = kind => ({ upstream: up.info, generator: 'tools/terminal-oracle/parser-cases.js', kind });

// ---- table ---------------------------------------------------------------------

const tab = EP.VT500_TRANSITION_TABLE.table;
if (tab.length !== 4257) throw new Error('transition table length ' + tab.length);
const runs = [];
for (let i = 0; i < tab.length; i++) if (i === 0 || tab[i] !== tab[i - 1]) runs.push(i, tab[i]);
L.writeFixture('terminal-parser-table.json', Object.assign(shell('parser-table'), { table: runs }));

// ---- UTF-8 ---------------------------------------------------------------------

function decodeCase(id, source, chunks) {
  const dec = new Utf8ToUtf32();
  const outs = chunks.map(ch => {
    const target = new Uint32Array(ch.length + 4);
    const n = dec.decode(Uint8Array.from(ch), target);
    return Array.from(target.subarray(0, n));
  });
  return { id, source, chunks: chunks.map(ch => T.b64(ch)), out: outs };
}

const utf8Cases = C.utf8.map(c => decodeCase(c.id, 'hand', c.chunks));
for (let i = 0; i < 50; i++) {
  const rnd = T.prng(1000 + i);
  const len = 16 + Math.floor(rnd() * 241);
  const bytes = [];
  for (let k = 0; k < len; k++) {
    const r = rnd();
    bytes.push(r < 0.6 ? 0x80 + Math.floor(rnd() * 0x80) : r < 0.8 ? 0xC2 + Math.floor(rnd() * (0xF5 - 0xC2)) : Math.floor(rnd() * 0x80));
  }
  const cuts = T.randomCuts(rnd, len, 1 + Math.floor(rnd() * 6));
  const chunks = [];
  let prev = 0;
  for (const k of cuts) { chunks.push(bytes.slice(prev, k)); prev = k; }
  chunks.push(bytes.slice(prev));
  utf8Cases.push(decodeCase('random-' + (1000 + i), 'fuzz', chunks));
}
L.writeFixture('terminal-parser-utf8.json', Object.assign(shell('parser-utf8'), { cases: utf8Cases }));

// ---- traces --------------------------------------------------------------------

const cpsOf = f => (f.s !== undefined ? T.cps(f.s) : f.cp);

function normalizeFeed(feed) {
  return feed.map(f => {
    if (f.s !== undefined || f.cp) return { cp: cpsOf(f) };
    if (f.repeat) return { repeat: { cp: cpsOf(f.repeat), times: f.repeat.times } };
    return f; // fill, reset, unregister
  });
}

function runTrace(c) {
  const parser = new EP.EscapeSequenceParser();
  const trace = [];
  const dg = s => T.digestable(s);
  const dgCps = (d, s, e) => T.digestable(Array.from(d.subarray(s, e)));
  const pj = p => JSON.stringify(p.toArray());
  const big = id => (id > 2147483647 ? 'big' : id);
  parser.setPrintHandler((data, start, end) => {
    trace.push(['print', dgCps(data, start, end)]);
    if (end > start) parser.precedingJoinState = data[end - 1];
  });
  parser.setExecuteHandlerFallback(code => trace.push(['exec', code]));
  parser.setCsiHandlerFallback((ident, params) => trace.push(['csi', ident, pj(params)]));
  parser.setEscHandlerFallback(ident => trace.push(['esc', ident]));
  parser.setOscHandlerFallback((ident, action, payload) => trace.push(['osc', big(ident), action,
    action === 'PUT' ? dg(payload) : null, action === 'END' ? payload : null]));
  parser.setDcsHandlerFallback((ident, action, payload) => trace.push(['dcs', ident, action,
    action === 'HOOK' ? pj(payload) : action === 'PUT' ? dg(payload) : null, action === 'UNHOOK' ? payload : null]));
  parser.setApcHandlerFallback((ident, action, payload) => trace.push(['apc', ident, action,
    action === 'PUT' ? dg(payload) : null, action === 'END' ? payload : null]));
  parser.setErrorHandler(state => { trace.push(['error', state.code, state.currentState]); return state; });

  const disp = [];
  c.register.forEach((r, k) => {
    if (r.csi) {
      disp.push(parser.registerCsiHandler(Object.assign({}, r.csi), p => { trace.push(['h', k, 'csi', pj(p)]); return r.ret; }));
    } else if (r.esc) {
      disp.push(parser.registerEscHandler(Object.assign({}, r.esc), () => { trace.push(['h', k, 'esc']); return r.ret; }));
    } else if (r.exec !== undefined) {
      parser.setExecuteHandler(String.fromCharCode(r.exec), () => { trace.push(['h', k, 'exec']); return true; });
      disp.push(null);
    } else if (r.osc !== undefined) {
      disp.push(parser.registerOscHandler(r.osc, r.kind === 'string'
        ? new OscHandler(d => { trace.push(['h', k, 'osc', dg(d)]); return r.ret; })
        : {
          start: () => trace.push(['h', k, 'osc-start']),
          put: (d, s, e) => trace.push(['h', k, 'osc-put', dgCps(d, s, e)]),
          end: ok => { trace.push(['h', k, 'osc-end', ok]); return r.ret; },
        }));
    } else if (r.dcs) {
      disp.push(parser.registerDcsHandler(Object.assign({}, r.dcs), r.kind === 'string'
        ? new DcsHandler((d, p) => { trace.push(['h', k, 'dcs', dg(d), pj(p)]); return r.ret; })
        : {
          hook: p => trace.push(['h', k, 'dcs-hook', pj(p)]),
          put: (d, s, e) => trace.push(['h', k, 'dcs-put', dgCps(d, s, e)]),
          unhook: ok => { trace.push(['h', k, 'dcs-unhook', ok]); return r.ret; },
        }));
    } else if (r.apc) {
      disp.push(parser.registerApcHandler(Object.assign({}, r.apc), r.kind === 'string'
        ? new ApcHandler(d => { trace.push(['h', k, 'apc', dg(d)]); return r.ret; })
        : {
          start: () => trace.push(['h', k, 'apc-start']),
          put: (d, s, e) => trace.push(['h', k, 'apc-put', dgCps(d, s, e)]),
          end: ok => { trace.push(['h', k, 'apc-end', ok]); return r.ret; },
        }));
    } else throw new Error(c.id + ': bad register item');
  });

  const feed = normalizeFeed(c.feed);
  const parse = arr => parser.parse(arr, arr.length);
  for (const f of feed) {
    if (f.cp) parse(Uint32Array.from(f.cp));
    else if (f.fill) { const a = new Uint32Array(f.fill[1]).fill(f.fill[0]); for (let k = 0; k < (f.times || 1); k++) parse(a); }
    else if (f.repeat) { const a = Uint32Array.from(f.repeat.cp); for (let k = 0; k < f.repeat.times; k++) parse(a); }
    else if (f.reset) parser.reset();
    else if (f.unregister !== undefined) { const d = disp[f.unregister]; if (!d) throw new Error(c.id + ': cannot unregister ' + f.unregister); d.dispose(); }
    else throw new Error(c.id + ': bad feed item ' + JSON.stringify(f));
  }
  return {
    id: c.id, source: c.source, ...(c.cut !== undefined ? { cut: c.cut } : {}), register: c.register, feed,
    trace, finalState: parser.currentState, finalJoinState: parser.precedingJoinState,
  };
}

const byId = new Map(C.traces.map(c => [c.id, c]));
const traceCases = [];
for (const c of C.traces) traceCases.push(runTrace(Object.assign({ source: 'hand' }, c)));
let cutCount = 0;
for (const id of C.cutSources) {
  const c = byId.get(id);
  if (!c || c.feed.length !== 1) throw new Error('cut source must be a single-item hand case: ' + id);
  const all = cpsOf(c.feed[0]);
  for (let k = 1; k < all.length; k++) {
    traceCases.push(runTrace({ id: `${id}@cut${k}`, source: 'hand', cut: k, register: c.register,
      feed: [{ cp: all.slice(0, k) }, { cp: all.slice(k) }] }));
    cutCount++;
  }
}
for (const c of C.longCases) traceCases.push(runTrace(Object.assign({ source: 'long' }, c)));

// Random code points biased towards escape syntax (weights in the plan, Task 2).
function fuzzCps(rnd, n) {
  const out = [];
  const pick = list => list[Math.floor(rnd() * list.length)];
  while (out.length < n) {
    const r = rnd() * 100;
    if (r < 15) out.push(0x1b);
    else if (r < 25) out.push(0x5b);
    else if (r < 28) out.push(0x5d);
    else if (r < 30) out.push(0x50);
    else if (r < 32) out.push(0x5f);
    else if (r < 40) out.push(0x3b);
    else if (r < 43) out.push(0x3a);
    else if (r < 63) { const d = 1 + Math.floor(rnd() * 6); for (let k = 0; k < d; k++) out.push(0x30 + Math.floor(rnd() * 10)); }
    else if (r < 78) out.push(0x40 + Math.floor(rnd() * 0x3f));
    else if (r < 86) out.push(Math.floor(rnd() * 0x20));
    else if (r < 89) out.push(0x80 + Math.floor(rnd() * 0x20));
    else if (r < 90) out.push(0x7f);
    else if (r < 93) out.push(0x3c + Math.floor(rnd() * 4));
    else if (r < 97) {
      const kind = pick([0, 1, 2]);
      let cp = kind === 0 ? 0xa0 + Math.floor(rnd() * 0x760) : kind === 1 ? 0x800 + Math.floor(rnd() * 0xF800) : 0x10000 + Math.floor(rnd() * 0x100000);
      if (cp >= 0xD800 && cp <= 0xDFFF) cp = 0x4e2d;
      out.push(cp);
    } else out.push(0x20 + Math.floor(rnd() * 0x10));
  }
  return out.slice(0, n);
}

for (const seed of C.fuzz.seeds) {
  const rnd = T.prng(seed);
  const [lo, hi] = C.fuzz.length;
  const all = fuzzCps(rnd, lo + Math.floor(rnd() * (hi - lo + 1)));
  const cuts = T.randomCuts(rnd, all.length, Math.floor(rnd() * 8));
  const feed = [];
  let prev = 0;
  for (const k of cuts) { feed.push({ cp: all.slice(prev, k) }); prev = k; }
  feed.push({ cp: all.slice(prev) });
  traceCases.push(runTrace({ id: 'fuzz-' + seed, source: 'fuzz', seed, register: [], feed }));
}

const written = L.writeFixture('terminal-parser-trace.json', Object.assign(shell('parser-trace'), { cases: traceCases }));
const count = s => traceCases.filter(c => c.source === s).length;
console.log(`table runs ${runs.length / 2}; utf8 ${utf8Cases.length} cases; traces: hand ${count('hand') - cutCount}, cut ${cutCount}, long ${count('long')}, fuzz ${count('fuzz')}; files ${written.join(', ')}`);
process.exit(0);
