// Writes tests/fixtures/terminal-core-hooks.json (phase 7, spec 19.6) for
// tests/test.terminal.hooks.pas from xterm.js 6.0.0 headless (through lib-term.js;
// pin and loading in lib-dump.js). Inputs: cases/hooks.js (the step format is there).
//
//   node tools/terminal-oracle/hook-cases.js
//
// Every handler is registered through the public terminal.parser (ParserApi.ts), the
// layer the Pascal core's Register*Handler follows. Each handler logs its call --
// { tag, kind, params: JSON.stringify(params) or null, data: base64(utf8(data)) or
// null, returned } -- then answers its script. A case's "expect" is lib-term.js's
// whole <state> plus "calls"; then, as for every core case, term.reset() and the same
// steps again on the same terminal: "afterReset" is "same" or that second state.
//
// THE SECOND RUN. The handlers the first run registered stay (upstream keeps them over
// a reset) and are called too, each with its own call count. The call log, the
// inside-actions and the tag -> latest registration map are the RUN's: a handler of
// either run logs into the running one's log and looks its actions up there. The
// Pascal test (TTyTerminalHookOracleTests) keeps the same three per run.
// Every case runs with lib-term.js's responder, as the Pascal harness answers colour
// and focus queries itself.
'use strict';
const T = require('./lib-term.js');
const H = require('./cases/hooks.js');

const up = T.loadUpstream();

function convertStep(s) {
  if (s.s !== undefined) return { write: T.b64(T.utf8(s.s)) };
  return JSON.parse(JSON.stringify(s));
}

// ctx: { calls, actions, disposables } of the running run (see above)
function makeHandler(term, ctx, spec) {
  let n = 0; // this handler's calls so far
  let returned;
  const before = () => {
    returned = spec.returns[Math.min(n, spec.returns.length - 1)];
    n++;
    for (const a of ctx.actions.slice()) if (a.tag === spec.tag && a.onCall === n) doAction(term, ctx, a);
  };
  const log = (params, data) => {
    ctx.calls.push({ tag: spec.tag, kind: spec.kind, params: params === null ? null : JSON.stringify(params),
      data: data === null ? null : T.b64(T.utf8(data)), returned });
    return returned;
  };
  switch (spec.kind) {
    case 'csi': return params => { const p = params.slice(); before(); return log(p, null); };
    case 'esc': return () => { before(); return log(null, null); };
    case 'osc': return data => { before(); return log(null, data); };
    case 'dcs': return (data, params) => { const p = params.slice(); before(); return log(p, data); };
    case 'apc': return data => { before(); return log(null, data); };
  }
  throw new Error('kind ' + spec.kind);
}

function register(term, ctx, spec) {
  const p = term.parser;
  const h = makeHandler(term, ctx, spec);
  switch (spec.kind) {
    case 'csi': return p.registerCsiHandler(spec.id, h);
    case 'esc': return p.registerEscHandler(spec.id, h);
    case 'osc': return p.registerOscHandler(spec.ident, h);
    case 'dcs': return p.registerDcsHandler(spec.id, h);
    case 'apc': return p.registerApcHandler(spec.id, h);
  }
  throw new Error('kind ' + spec.kind);
}

function doAction(term, ctx, a) {
  if (a.register) ctx.disposables[a.register.tag] = register(term, ctx, a.register);
  else if (a.dispose) ctx.disposables[a.dispose].dispose();
}

// One run of the steps; its calls in ctx.calls afterwards.
function runHooks(term, ctx, steps) {
  ctx.calls = [];
  ctx.actions = [];
  ctx.disposables = {};
  for (const s of steps) {
    if (s.write !== undefined) term._core.writeSync(T.unb64(s.write));
    else if (s.register) {
      let err = null;
      try {
        ctx.disposables[s.register.tag] = register(term, ctx, s.register);
      } catch (e) {
        err = e.message;
      }
      // the message (or null) goes into the fixture the first time; a rerun must agree
      if (s.register.error !== undefined && s.register.error !== err) throw new Error(`${s.register.tag}: ${err} after ${s.register.error}`);
      s.register.error = err;
    } else if (s.dispose !== undefined) ctx.disposables[s.dispose].dispose();
    else if (s.inside) ctx.actions.push(s.inside);
    else if (s.reset) term.reset();
    else throw new Error('unknown step ' + JSON.stringify(s));
  }
}

function runCase(c) {
  const term = T.makeCaseTerminal(up, c);
  const holder = T.attachRecorders(term);
  T.attachSynth(term, T.DEFAULT_PALETTE, true);
  const ctx = {};
  runHooks(term, ctx, c.steps);
  // a copy: the first run's handlers keep logging into the second run's ctx.calls,
  // never into this one
  const expect = JSON.parse(JSON.stringify(Object.assign(T.dumpState(up, term, holder.cur), { calls: ctx.calls })));
  term.reset();
  holder.cur = T.newRecord();
  runHooks(term, ctx, c.steps);
  const second = JSON.parse(JSON.stringify(Object.assign(T.dumpState(up, term, holder.cur), { calls: ctx.calls })));
  term.dispose();
  return { expect, afterReset: JSON.stringify(second) === JSON.stringify(expect) ? 'same' : second };
}

const out = [];
for (const src of H.cases) {
  const c = { id: src.id, source: 'hooks' };
  if (src.cols !== undefined) c.cols = src.cols;
  if (src.rows !== undefined) c.rows = src.rows;
  T.normalizeOptions(c);
  c.steps = src.steps.map(convertStep);
  const r = runCase(c);
  c.expect = r.expect;
  c.afterReset = r.afterReset;
  out.push(c);
}
const files = T.writeCoreFixture('terminal-core-hooks.json', 'core-hooks', out, 'hook-cases.js');
const calls = out.reduce((n, c) => n + c.expect.calls.length, 0);
const errors = out.reduce((n, c) => n + c.steps.filter(s => s.register && s.register.error).length, 0);
console.log(`hooks ${out.length} cases, ${calls} calls, ${errors} refused ids; files ${files.join(', ')}`);
