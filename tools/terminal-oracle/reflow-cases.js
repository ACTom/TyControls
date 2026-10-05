// Writes the reflow fixtures for tests/test.terminal.reflow.pas and the core oracle
// (phase 5, Task 2), from xterm.js 6.0.0 (pin and loading in lib-dump.js, through
// lib-term.js). Inputs: cases/reflow.js.
//
//   node tools/terminal-oracle/reflow-cases.js
//
// tests/fixtures/terminal-core-reflow.json   kind "core-reflow", source "reflow": whole
//   terminals resized back and forth (the core fixture format, afterReset included):
//   the hand cases of cases/reflow.js; four recordings written whole at their size,
//   then resized to width - 7, - 23, + 13 and back; and 120 seeded random mixes (seed
//   k + 1, k = 0..119: random writes of 200-2000 bytes -- ASCII, CJK, emoji,
//   combining marks, SGR, CR / LF, Tab, DECAWM off and on -- alternating with random
//   resizes, 2-60 columns by 1-12 rows, scrollback 0-20). A hand case or a recording
//   is also written cut after each of its resizes but the last (id@n): the fixture
//   holds the last state only. The random cases run in a
//   worker thread with a 5 second watchdog per case: a case upstream throws on or
//   does not finish is left out and named on the console (there should be none).
// tests/fixtures/terminal-reflow-units.json  kind "reflow-units": BufferReflow.ts's
//   functions called directly on BufferLines built in node --
//     newLineLengths  reflowSmallerGetNewLineLengths(lines, oldCols, newCols)
//     trimmedLength   getWrappedLineTrimmedLength(lines, i, cols)
//     linesToRemove   reflowLargerGetLinesToRemove(list, oldCols, newCols, absY,
//                     NULL_CELL, reflowCursorLine), with the lines as the call leaves them
//     newLayout       reflowLargerCreateNewLayout(list, toRemove) on the lines the
//                     previous call left: layout, countRemoved and the onDelete events
//   A line is { cols, wrapped, cells: [[cp, width] ...] } from column 0: [0, 1] an empty
//   cell (NULL_CELL), [0, 0] the second half of a wide character; the columns after
//   the listed ones are empty cells. "after" lines list every column.
'use strict';
const fs = require('fs');
const path = require('path');
const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');
const T = require('./lib-term.js');

const RANDOM_CASES = 120;
const WATCHDOG_MS = 5000;

function convertStep(s) {
  if (s.s !== undefined) return { write: T.b64(T.utf8(s.s)) };
  return s;
}

async function buildCase(up, src) {
  const c = { id: src.id, source: 'reflow' };
  if (src.cols !== undefined) c.cols = src.cols;
  if (src.rows !== undefined) c.rows = src.rows;
  if (src.options) c.options = src.options;
  T.normalizeOptions(c);
  if (src.seed !== undefined) c.seed = src.seed;
  c.steps = src.steps.map(convertStep);
  const r = await T.runCase(up, c);
  c.expect = r.expect;
  c.afterReset = r.afterReset;
  return c;
}

// ---- the seeded random mixes ---------------------------------------------------------

function randomSource(seed) {
  const rnd = T.prng(seed);
  const int = (a, b) => a + Math.floor(rnd() * (b - a + 1));
  const pick = a => a[Math.floor(rnd() * a.length)];
  const PIECES = [
    () => 'abcdefghijklmnopqrstuvwxyz0123456789 '.charAt(int(0, 36)).repeat(int(1, 12)),
    () => String.fromCodePoint(0x4E00 + int(0, 400)),
    () => String.fromCodePoint(0x1F600 + int(0, 0x4F)),
    () => 'é',
    () => '\x1b[' + pick(['0', '1', '31', '42', '7', '38;5;' + int(0, 255), '48;2;1;2;3']) + 'm',
    () => pick(['\r\n', '\r\n', '\n', '\r']),
    () => '\t',
    () => pick(['\x1b[?7l', '\x1b[?7h']),
  ];
  const steps = [];
  const n = int(6, 12);
  for (let k = 0; k < n; k++) {
    if (k % 2 === 0) {
      let s = '';
      const target = int(200, 2000);
      while (Buffer.byteLength(s) < target) s += pick(PIECES)();
      steps.push({ s });
    } else {
      steps.push({ resize: [int(2, 60), int(1, 12)] });
    }
  }
  return { id: 'random-' + seed, seed, cols: int(2, 60), rows: int(1, 12), options: { scrollback: int(0, 20) }, steps };
}

if (!isMainThread) {
  // the worker: the random cases from workerData.from on, one message per case
  const up = T.loadUpstream();
  (async () => {
    for (let seed = workerData.from; seed <= RANDOM_CASES; seed++) {
      parentPort.postMessage({ seed, started: true });
      let c;
      try {
        c = await buildCase(up, randomSource(seed));
      } catch (e) {
        parentPort.postMessage({ seed, error: String(e && e.message || e) });
        continue;
      }
      parentPort.postMessage({ seed, c });
    }
    parentPort.postMessage({ done: true });
  })();
  return;
}

function runRandom() {
  return new Promise(resolve => {
    const got = new Map();
    const dropped = [];
    const start = from => {
      const w = new Worker(__filename, { workerData: { from } });
      let timer = null;
      let current = from;
      const arm = () => {
        clearTimeout(timer);
        timer = setTimeout(() => {
          dropped.push(`random-${current}: no answer in ${WATCHDOG_MS} ms`);
          w.terminate();
          if (current < RANDOM_CASES) start(current + 1); else resolve({ got, dropped });
        }, WATCHDOG_MS);
      };
      w.on('message', m => {
        if (m.done) { clearTimeout(timer); w.terminate(); resolve({ got, dropped }); return; }
        if (m.started) { current = m.seed; arm(); return; }
        if (m.error) dropped.push(`random-${m.seed}: upstream threw: ${m.error}`);
        else got.set(m.seed, m.c);
      });
      w.on('error', e => { clearTimeout(timer); throw e; });
    };
    start(1);
  });
}

// ---- the pure functions ---------------------------------------------------------------

function unitsFixture(up) {
  const out = p => require(path.join(T.L.XTERM, T.L.OUT_DIR, p));
  const { BufferLine, DEFAULT_ATTR_DATA } = out('common/buffer/BufferLine.js');
  const { CellData } = out('common/buffer/CellData.js');
  const { CircularList } = out('common/CircularList.js');
  const R = out('common/buffer/BufferReflow.js');
  const nullCell = CellData.fromCharData([0, '', 1, 0]);

  const make = spec => {
    const l = new BufferLine(spec.cols, undefined, !!spec.wrapped);
    spec.cells.forEach(([cp, w], x) => { if (!(cp === 0 && w === 1)) l.setCellFromCodepoint(x, cp, w, DEFAULT_ATTR_DATA); });
    return l;
  };
  const dump = l => {
    const cells = [];
    for (let x = 0; x < l.length; x++) cells.push([l.getCodePoint(x), l.getWidth(x)]);
    return { cols: l.length, wrapped: l.isWrapped, cells };
  };
  // a line spec from text: CJK two cells
  const L = (cols, s, wrapped = false) => {
    const cells = [];
    for (const ch of s) {
      const cp = ch.codePointAt(0);
      if (ch === '.') cells.push([0, 1]);
      else if ((cp >= 0x4E00 && cp <= 0x9FFF) || cp >= 0x1F300) cells.push([cp, 2], [0, 0]);
      else cells.push([cp, 1]);
    }
    return { cols, wrapped, cells };
  };
  const listOf = specs => {
    const list = new CircularList(Math.max(specs.length, 1));
    for (const s of specs) list.push(make(s));
    return list;
  };

  // reflowSmallerGetNewLineLengths: BufferReflow.test.ts's five, then ours
  const HAN = '汉语汉语汉语';
  const NL = [
    { lines: [L(4, '汉语')], oldCols: 4, newCols: 3 },
    { lines: [L(4, '汉语')], oldCols: 4, newCols: 2 },
    ...[11, 10, 9, 8, 7, 6, 5, 4, 3, 2].map(n => ({ lines: [L(12, HAN)], oldCols: 12, newCols: n })),
    ...[5, 4, 3, 2].map(n => ({ lines: [L(6, 'a汉语b')], oldCols: 6, newCols: n })),
    ...[5, 4, 3, 2].map(n => ({ lines: [L(6, 'a汉语b'), L(6, 'a汉语b', true)], oldCols: 6, newCols: n })),
    { lines: [L(5, '汉语.')], oldCols: 4, newCols: 3 },
    { lines: [L(5, '汉语.')], oldCols: 4, newCols: 2 },
    // ours: wide characters across several cuts; trailing blanks on the last line; two columns
    { lines: [L(10, 'a汉语汉语b'), L(10, '汉语汉语汉', true), L(10, 'x汉语', true)], oldCols: 10, newCols: 3 },
    { lines: [L(10, 'a汉语汉语b'), L(10, '汉语汉语汉', true), L(10, 'x汉语', true)], oldCols: 10, newCols: 7 },
    { lines: [L(8, 'abcdefgh'), L(8, 'ij......', true)], oldCols: 8, newCols: 3 },
    { lines: [L(6, '汉ab语'), L(6, '汉语c', true)], oldCols: 6, newCols: 2 },
    { lines: [L(9, 'abcdefgh.'), L(9, '汉语xyz', true)], oldCols: 9, newCols: 4 },
  ].map(t => ({ lines: t.lines, oldCols: t.oldCols, newCols: t.newCols,
    result: R.reflowSmallerGetNewLineLengths(t.lines.map(make), t.oldCols, t.newCols) }));

  // getWrappedLineTrimmedLength
  const TL = [
    { lines: [L(6, 'abc'), L(6, 'de', true)], i: 1, cols: 6 },                     // the last line
    { lines: [L(6, 'abc'), L(6, 'de', true)], i: 0, cols: 6 },                     // not the last
    { lines: [L(6, 'abcde.'), L(6, '汉ab', true)], i: 0, cols: 6 },                // blank cell + wide next
    { lines: [L(6, 'abcdef'), L(6, '汉ab', true)], i: 0, cols: 6 },                // content + wide next
    { lines: [L(6, 'abcde.'), L(6, 'xab', true)], i: 0, cols: 6 },                 // blank cell + narrow next
    { lines: [L(6, 'abcd汉'), L(6, '汉ab', true)], i: 0, cols: 6 },                // wide at the end + wide next
    { lines: [L(6, 'abcde.'), L(6, '汉ab', true), L(6, 'q', true)], i: 1, cols: 6 },
  ].map(t => ({ lines: t.lines, i: t.i, cols: t.cols, result: R.getWrappedLineTrimmedLength(t.lines.map(make), t.i, t.cols) }));

  // reflowLargerGetLinesToRemove, then reflowLargerCreateNewLayout on what it left
  const oneCol = s => [...s].map((ch, i) => ({ cols: 1, wrapped: i > 0, cells: [[ch.codePointAt(0), 1]] }));
  const LR = [
    { lines: oneCol('abcde'), oldCols: 1, newCols: 5, absY: 2, rcl: false },       // BufferReflow.test.ts
    { lines: oneCol('abcde'), oldCols: 1, newCols: 5, absY: 2, rcl: true },
    { lines: oneCol('abcde'), oldCols: 1, newCols: 5, absY: 10, rcl: false },
    { lines: [L(4, 'abcd'), L(4, 'efgh', true), L(4, 'ij', true), L(4, 'next'), L(4, 'wxyz'), L(4, 'q', true)],
      oldCols: 4, newCols: 9, absY: 5, rcl: false },                                // two runs, the cursor in the second
    { lines: [L(4, 'abcd'), L(4, 'efgh', true), L(4, 'ij', true), L(4, 'next'), L(4, 'wxyz'), L(4, 'q', true)],
      oldCols: 4, newCols: 9, absY: 3, rcl: false },                                // both runs
    { lines: [L(4, 'abcd'), L(4, '....', true), L(4, '....', true), L(4, 'z')],
      oldCols: 4, newCols: 6, absY: 3, rcl: false },                                // a run ending in blank rows
    { lines: [L(5, 'abcd汉'), L(5, '语xyz', true), L(5, 'end')], oldCols: 5, newCols: 7, absY: 2, rcl: false },  // a wide char at the new edge
    { lines: [L(4, 'abcd'), L(4, 'efgh', true), L(4, 'ijkl', true), L(4, 'mn', true), L(4, '')], oldCols: 4, newCols: 5, absY: 4, rcl: false },
  ].map(t => {
    const list = listOf(t.lines);
    const toRemove = R.reflowLargerGetLinesToRemove(list, t.oldCols, t.newCols, t.absY, nullCell, t.rcl);
    const after = [];
    for (let i = 0; i < list.length; i++) after.push(dump(list.get(i)));
    const events = [];
    list.onDelete(e => events.push([e.index, e.amount]));
    const layout = R.reflowLargerCreateNewLayout(list, toRemove);
    return { lines: t.lines, oldCols: t.oldCols, newCols: t.newCols, absY: t.absY, reflowCursorLine: t.rcl,
      result: toRemove, after, layout: layout.layout, countRemoved: layout.countRemoved, events };
  });

  return { upstream: up.info, generator: 'tools/terminal-oracle/reflow-cases.js', kind: 'reflow-units',
    newLineLengths: NL, trimmedLength: TL, linesToRemove: LR };
}

// ---- main -----------------------------------------------------------------------------

(async () => {
  const up = T.loadUpstream();
  const C = require('./cases/reflow.js');
  const seen = new Set();
  const cases = [];
  // A fixture holds the state after the LAST step only, and a width that comes back
  // often gives the same state reflowed or not: every hand case and recording is also
  // written cut after each of its resizes but the last (id@n, n = resizes kept), so the
  // state at every width is compared.
  const withPrefixes = src => {
    const out = [];
    let resizes = 0;
    src.steps.forEach((s, j) => {
      if (!s.resize) return;
      resizes++;
      if (j < src.steps.length - 1) out.push(Object.assign({}, src, { id: `${src.id}@${resizes}`, steps: src.steps.slice(0, j + 1) }));
    });
    out.push(src);
    return out;
  };
  let hand = 0;
  for (const whole of C.CASES) {
    for (const src of withPrefixes(whole)) {
      if (seen.has(src.id)) throw new Error('duplicate case id ' + src.id);
      seen.add(src.id);
      cases.push(await buildCase(up, src));
      hand++;
    }
  }
  // the recordings, as recordings.js reads them
  const DIR = path.join(__dirname, 'recordings');
  for (const name of C.RECORDINGS) {
    const text = fs.readFileSync(path.join(DIR, name + '.cast'), 'utf8').replace(/\r\n/g, '\n');
    const rows = text.split('\n').filter(Boolean).map(l => JSON.parse(l));
    const head = rows.shift();
    const steps = rows.filter(r => r[1] === 'o').map(r => ({ s: r[2] }));
    const w = head.width;
    for (const nw of [w - 7, w - 23, w + 13, w]) steps.push({ resize: [nw, head.height] });
    for (const src of withPrefixes({ id: 'recording-' + name, cols: w, rows: head.height,
      options: { scrollback: 200, unicodeVersion: '11' }, steps })) cases.push(await buildCase(up, src));
  }
  const nRec = cases.length - hand;
  const { got, dropped } = await runRandom();
  for (let seed = 1; seed <= RANDOM_CASES; seed++) if (got.has(seed)) cases.push(got.get(seed));
  const files = T.writeCoreFixture('terminal-core-reflow.json', 'core-reflow', cases, 'reflow-cases.js');
  T.L.writeFixture('terminal-reflow-units.json', unitsFixture(up));
  console.log(`core-reflow: ${cases.length} cases (${hand} by hand with their cuts, ${nRec} from ${C.RECORDINGS.length} recordings, ${got.size} random); files ${files.join(', ')}`);
  console.log(dropped.length ? 'random cases left out:\n  ' + dropped.join('\n  ') : 'random cases left out: none');
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
