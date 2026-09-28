// Writes four whole-terminal fixtures for tests/test.terminal.core.pas from
// xterm.js 6.0.0 headless (through lib-term.js; pin and loading in lib-dump.js).
// Inputs: cases/core-hand.js.
//
//   node tools/terminal-oracle/core-cases.js
//
// tests/fixtures/terminal-core-hand.json      source "hand": vttest-style cases
// tests/fixtures/terminal-core-long.json      source "long": oversized input
// tests/fixtures/terminal-core-synth.json     source "synthesized": colour, colour
//                                             scheme and focus replies
// tests/fixtures/terminal-core-mouse.json     mouse restriction and encoding
// (each may be split into -<n> parts). The case and <state> formats are the plan's
// "夹具格式"; every core case runs with lib-term.js's responder attached, because
// the Pascal core always answers those queries -- "synthesized" only marks the
// cases that are about them.
//
// A hand case whose steps are one write also gets two variants -- fed one byte per
// write, and cut in three random places (prng seeded by the case's position) -- and
// checkVariants proves upstream reaches the same state that way (all but the
// renders and cursorMoves counts, which follow the number of parse calls).
//
// Mouse: for each protocol and encoding, mouseStateService.restrictMouseEvent on a
// copy of each event, then encodeMouseEvent if it passed; eventAfter is the event
// after restrict (X10 clears the modifiers), encoded the report as bytes (one per
// UTF-16 unit -- CSI M carries codes above 127 -- base64), null when restricted.
'use strict';
const T = require('./lib-term.js');
const C = require('./cases/core-hand.js');

const up = T.loadUpstream();

function convertStep(s) {
  if (s.s !== undefined) return { write: T.b64(T.utf8(s.s)) };
  if (s.writeRepeat && s.writeRepeat.s !== undefined) return { writeRepeat: { b64: T.b64(T.utf8(s.writeRepeat.s)), times: s.writeRepeat.times } };
  if (s.input !== undefined && typeof s.input === 'string') return { input: T.b64(T.utf8(s.input)), user: s.user };
  return s;
}

async function build(list, source, withVariants) {
  const out = [];
  for (let k = 0; k < list.length; k++) {
    const src = list[k];
    const c = { id: src.id, source };
    if (src.cols !== undefined) c.cols = src.cols;
    if (src.rows !== undefined) c.rows = src.rows;
    if (src.options) c.options = src.options;
    T.normalizeOptions(c);
    if (src.synth) c.synth = src.synth;
    c.steps = src.steps.map(convertStep);
    if (withVariants && c.steps.length === 1 && c.steps[0].write !== undefined) {
      const len = T.unb64(c.steps[0].write).length;
      if (len > 1) c.variants = [{ cuts: 'each' }, { cuts: T.randomCuts(T.prng(k + 1), len, 3) }];
    }
    const t0 = Date.now();
    const r = await T.runCase(up, c);
    await T.checkVariants(up, c, r.expect);
    c.expect = r.expect;
    c.afterReset = r.afterReset;
    out.push(c);
    if (process.env.TY_ORACLE_PROGRESS) process.stderr.write(`${c.id} ${Date.now() - t0} ms\n`);
  }
  return out;
}

const BUTTON = { LEFT: 0, MIDDLE: 1, RIGHT: 2, NONE: 3, WHEEL: 4 };
const ACTION = { UP: 0, DOWN: 1, LEFT: 2, RIGHT: 3, MOVE: 32 };
const BUTTON_NAME = Object.fromEntries(Object.entries(BUTTON).map(([k, v]) => [v, k]));
const ACTION_NAME = Object.fromEntries(Object.entries(ACTION).map(([k, v]) => [v, k]));

function buildMouse() {
  const term = T.makeCaseTerminal(up, { cols: 80, rows: 24 });
  const svc = term._core.mouseStateService;
  const out = [];
  for (const protocol of C.mouse.protocols) {
    for (const encoding of C.mouse.encodings) {
      svc.activeProtocol = protocol;
      svc.activeEncoding = encoding;
      C.mouse.events.forEach((ev, n) => {
        const e = Object.assign({}, ev, { button: BUTTON[ev.button], action: ACTION[ev.action] });
        const ok = svc.restrictMouseEvent(e);
        const s = ok ? svc.encodeMouseEvent(e) : null;
        const after = Object.assign({}, e, { button: BUTTON_NAME[e.button], action: ACTION_NAME[e.action] });
        out.push({ id: `${protocol}-${encoding}-${n}`, protocol, encoding, event: ev, restrict: ok, eventAfter: after,
          encoded: s === null ? null : T.b64(Buffer.from(s, 'latin1')) });
      });
    }
  }
  term.dispose();
  return out;
}

(async () => {
  const hand = await build(C.hand, 'hand', true);
  const long = await build(C.long, 'long', false);
  const synth = await build(C.synth, 'synthesized', true);
  const mouse = buildMouse();
  const files = [];
  files.push(...T.writeCoreFixture('terminal-core-hand.json', 'core-hand', hand, 'core-cases.js'));
  files.push(...T.writeCoreFixture('terminal-core-long.json', 'core-long', long, 'core-cases.js'));
  files.push(...T.writeCoreFixture('terminal-core-synth.json', 'core-synth', synth, 'core-cases.js'));
  files.push(...T.writeCoreFixture('terminal-core-mouse.json', 'core-mouse', mouse, 'core-cases.js'));
  const variants = [...hand, ...synth].filter(c => c.variants).length;
  console.log(`hand ${hand.length} (${variants} with cut variants), long ${long.length}, synth ${synth.length}, mouse ${mouse.length}; files ${files.join(', ')}`);
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
