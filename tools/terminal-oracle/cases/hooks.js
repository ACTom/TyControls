// Inputs for hook-cases.js (phase 7, spec 19.6) -- only inputs; what the handlers are
// called with and the state they leave come from xterm.js 6.0.0 headless through
// terminal.parser.register* (ParserApi.ts).
//
// A case is { id, cols?, rows?, steps }. Steps:
//   { s: "..." }                  a write of the JS string as UTF-8 (one parse call)
//   { register: { tag, kind, id | ident, returns } }
//                                 kind 'csi' | 'esc' | 'osc' | 'dcs' | 'apc'; id is an
//                                 IFunctionIdentifier { prefix?, intermediates?, final },
//                                 ident an OSC number; the handler's n-th call (from 0)
//                                 answers returns[min(n, returns.length - 1)]. An id
//                                 upstream refuses: the step records the message.
//   { dispose: tag }              the latest registration under that tag
//   { inside: { tag, onCall, register | dispose } }
//                                 from now on, when a handler registered under tag makes
//                                 its onCall-th call (from 1), it first does this
//   { reset: true }               term.reset()
'use strict';

const E = '\x1b';
const CSI = E + '[';
const OSC = E + ']';
const DCS = E + 'P';
const APC = E + '_';
const ST = E + '\\';
const BEL = '\x07';
const W = s => ({ s });
const reg = (tag, kind, idOrIdent, returns) => ({
  register: Object.assign({ tag, kind, returns },
    kind === 'osc' ? { ident: idOrIdent } : { id: idOrIdent }),
});
const M = { final: 'm' };

const cases = [
  // 1. CSI m: true stops the chain (the built-in SGR never runs), false lets it run
  { id: 'csi-m-true', steps: [reg('a', 'csi', M, [true]), W(CSI + '31mX')] },
  { id: 'csi-m-false', steps: [reg('a', 'csi', M, [false]), W(CSI + '31mX')] },
  // 2. two on one identifier: the later one first; false tries the earlier one
  {
    id: 'csi-chain', steps: [reg('a', 'csi', M, [true]), reg('b', 'csi', M, [false]), W(CSI + '31mX'),
      { dispose: 'b' }, W(CSI + '32mY'), { dispose: 'a' }, W(CSI + '33mZ')],
  },
  // 3. sub-parameters as upstream's toArray gives them
  { id: 'csi-subparams', steps: [reg('a', 'csi', M, [false]), W(CSI + '38:2::10:20:30mA' + CSI + '4:3mB' + CSI + ';;5mC' + CSI + 'mD')] },
  { id: 'csi-prefixed', steps: [reg('a', 'csi', { prefix: '?', final: 'h' }, [false]), reg('b', 'csi', { intermediates: ' ', final: 'q' }, [true]),
    W(CSI + '?25l' + CSI + '?25h' + CSI + '5 q' + 'x')] },
  // 4. ESC # 8 (DECALN)
  { id: 'esc-decaln-true', steps: [reg('a', 'esc', { intermediates: '#', final: '8' }, [true]), W('ab' + E + '#8')] },
  { id: 'esc-decaln-false', steps: [reg('a', 'esc', { intermediates: '#', final: '8' }, [false]), W('ab' + E + '#8')] },
  { id: 'esc-save-restore', steps: [reg('a', 'esc', { final: '7' }, [true, false]), W('ab' + E + '7cd' + E + '8x' + E + '7ef' + E + '8y')] },
  // 5. OSC: a number with no built-in, a built-in's number, split across writes
  { id: 'osc-1337', steps: [reg('a', 'osc', 1337, [true]), W(OSC + '1337;File=名字;a=b' + BEL + 'x')] },
  { id: 'osc-0-false', steps: [reg('a', 'osc', 0, [false]), W(OSC + '0;hello' + BEL)] },
  { id: 'osc-0-true', steps: [reg('a', 'osc', 0, [true]), W(OSC + '0;hello' + BEL)] },
  { id: 'osc-split', steps: [reg('a', 'osc', 1337, [true]), W(OSC + '1337;ab'), W('c;d'), W('e' + ST + 'z')] },
  { id: 'osc-aborted', steps: [reg('a', 'osc', 1337, [true]), W(OSC + '1337;ab\x18' + 'q' + OSC + '1337;ok' + BEL)] },
  // 6. DCS $ q (DECRQSS): true takes the reply away
  { id: 'dcs-decrqss-true', steps: [reg('a', 'dcs', { intermediates: '$', final: 'q' }, [true]), W(DCS + '$qm' + ST)] },
  { id: 'dcs-decrqss-false', steps: [reg('a', 'dcs', { intermediates: '$', final: 'q' }, [false]), W(DCS + '$qm' + ST)] },
  { id: 'dcs-params', steps: [reg('a', 'dcs', { final: 'p' }, [true]), W(DCS + '1;2:3p' + 'payload' + ST + 'x')] },
  // 7. APC
  { id: 'apc-g', steps: [reg('a', 'apc', { final: 'G' }, [true]), W(APC + 'Gf=100;AAAA' + ST + 'x'), { dispose: 'a' }, W(APC + 'Gagain' + ST + 'y')] },
  // 8. registering and disposing while the chain is being dispatched
  {
    id: 'inside-register', steps: [reg('a', 'csi', M, [false]),
      { inside: { tag: 'a', onCall: 1, register: { tag: 'c', kind: 'csi', id: M, returns: [true] } } },
      W(CSI + '31mX' + CSI + '32mY')],
  },
  {
    id: 'inside-dispose-earlier', steps: [reg('a', 'csi', M, [false]), reg('b', 'csi', M, [false]),
      { inside: { tag: 'b', onCall: 1, dispose: 'a' } },
      W(CSI + '31mX' + CSI + '32mY')],
  },
  {
    id: 'inside-dispose-self', steps: [reg('a', 'csi', M, [false]), reg('b', 'csi', M, [false]),
      { inside: { tag: 'b', onCall: 1, dispose: 'b' } },
      W(CSI + '31mX' + CSI + '32mY')],
  },
  {
    id: 'inside-osc', steps: [reg('a', 'osc', 1337, [false]),
      { inside: { tag: 'a', onCall: 1, register: { tag: 'c', kind: 'osc', ident: 1337, returns: [true] } } },
      W(OSC + '1337;one' + BEL + OSC + '1337;two' + BEL)],
  },
  // 9. reset() keeps what the host registered
  { id: 'reset-keeps', steps: [reg('a', 'csi', M, [true]), W(CSI + '31mX'), { reset: true }, W(CSI + '32mY')] },
  // 10. identifiers upstream refuses
  {
    id: 'bad-ids', steps: [
      reg('e1', 'csi', { prefix: '!', final: 'm' }, [true]),
      reg('e2', 'csi', { intermediates: '!!!', final: 'm' }, [true]),
      reg('e3', 'csi', { final: '0' }, [true]),
      reg('e4', 'csi', { prefix: '??', final: 'm' }, [true]),
      reg('e5', 'esc', { intermediates: '\x7f', final: '8' }, [true]),
      reg('e6', 'dcs', { final: '\x3f' }, [true]),
      reg('e7', 'apc', { final: '\x2f' }, [true]),
      W('ok')],
  },
];

module.exports = { cases };
