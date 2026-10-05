// Writes tests/fixtures/terminal-selection.json for tests/test.terminal.selection.pas
// from xterm.js 6.0.0's SelectionService and SelectionModel (pin and loading in
// lib-dump.js; the fake browser objects in lib-dump.js fakeBrowser()). Inputs:
// cases/selection.js.
//
//   node tools/terminal-oracle/selection-cases.js
//
// A case is { id, cols, rows, scrollback, wordSeparator?, steps }. The terminal is
// the core scripts' headless terminal (Unicode 11) with the case's size and
// scrollback; the SelectionService is built on its own buffer, core, options and
// mouse-state services. Steps (the fixture keeps them; the Pascal side does the same
// thing for each field):
//   { write: b64 }              term._core.writeSync(bytes)
//   { resize: [c, r] }          term.resize(c, r)
//   { scroll: n }               term.scrollLines(n)
//   { press: { at: [x, vr], detail, button, shift, alt, enabled } }
//                               enable() / disable() first when `enabled` changed
//                               (disable clears), then handleMouseDown; the fake
//                               getCoords answers [x + 1, vr + 1] (x a boundary 0..cols,
//                               vr a viewport row)
//   { move: { at: [x, vr], py } }   _handleMouseMove; clientY = py + 0.5 (py device
//                               pixels from the grid's top, CELL_H = 10 per row)
//   { dragScroll: true }        _dragScroll(); its onRequestScrollLines scrolls the
//                               terminal (CoreBrowserTerminal.ts:599)
//   { release: true }           _handleMouseUp without Alt
//   { rightClick: { at } }      rightClickSelect (the macOS right click)
//   { link: [sx, sy, ex, ey] | null }   the Linkifier's currentLink for the next press
//   { selectAll }, { selectLines: [a, b] }, { setSelection: [c, r, len] }, { clear }
//   { userInput: true }         coreService.triggerDataEvent('x', true)
// After every step: start / end (finalSelectionStart / End, null = undefined), raw
// (the model's selectionStart, selectionEnd, selectionStartLength,
// isSelectAllActive), mode (0 normal, 1 word, 2 line, 3 column), has, text (the
// selection text, UTF-8 in base64, rows joined with \n: node is not Windows), changes
// (onSelectionChange this step), dragAmount, ydisp, ybase, trimmed (the lines the
// active buffer's list trimmed this step -- what the selection's onTrim listener
// saw), spans (per viewport row, the [from, to) columns
// DomRendererRowFactory._isCellInSelection answers, or null).
// rerun: the same selection service after the case: resized back if it was resized,
// term.reset(), then the first three steps again -- the `after` of each (the reuse
// path: a used service keeps its mode, its last drag amount and what it last
// reported, so the answers need not equal a new one's).
//
// Reproducible: no time, fixed key order.
'use strict';
const T = require('./lib-term.js');
const L = T.L;
const C = require('./cases/selection.js');

const up = T.loadUpstream();
const B = L.loadBrowserParts();
const b64 = s => Buffer.from(s, 'utf8').toString('base64');

function pt(p) { return p ? [p[0], p[1]] : null; }

function runCase(c) {
  const term = T.makeCaseTerminal(up, { cols: c.cols, rows: c.rows, options: { scrollback: c.scrollback } });
  if (c.wordSeparator !== undefined) term.options.wordSeparator = c.wordSeparator;
  const core = term._core;
  const state = { point: null, link: undefined };
  const fb = L.fakeBrowser(() => term.rows, state);
  const sel = new B.SelectionService(fb.element, fb.screenElement, fb.linkifier, core._bufferService,
    core.coreService, fb.mouseCoordsService, core.optionsService, core.mouseStateService,
    fb.renderService, fb.coreBrowserService);
  let changes = 0;
  sel.onSelectionChange(() => changes++);
  sel.onRequestScrollLines(e => term.scrollLines(e.amount));
  // the trims the selection hears: the active buffer's list, re-hooked on a switch
  let trimmed = 0;
  let trimHook = null;
  const hook = () => {
    if (trimHook) trimHook.dispose();
    trimHook = core._bufferService.buffer.lines.onTrim(n => { trimmed += n; });
  };
  hook();
  core._bufferService.buffers.onBufferActivate(() => hook());
  let enabled = true;
  const doStep = s => {
    changes = 0;
    trimmed = 0;
    const o = {};
    if (s.write !== undefined) {
      o.write = b64(s.write);
      core.writeSync(Buffer.from(s.write, 'utf8'));
    } else if (s.resize) {
      o.resize = s.resize;
      term.resize(s.resize[0], s.resize[1]);
    } else if (s.scroll !== undefined) {
      o.scroll = s.scroll;
      term.scrollLines(s.scroll);
    } else if (s.press) {
      const p = Object.assign({ detail: 1, button: 0, shift: false, alt: false, enabled: true }, s.press);
      o.press = p;
      if (p.enabled !== enabled) {
        if (p.enabled) sel.enable(); else sel.disable();
        enabled = p.enabled;
      }
      state.point = [p.at[0] + 1, p.at[1] + 1];
      sel.handleMouseDown({ button: p.button, detail: p.detail, shiftKey: p.shift, altKey: p.alt, timeStamp: 0,
        preventDefault() {}, stopPropagation() {} });
    } else if (s.move) {
      o.move = s.move;
      state.point = [s.move.at[0] + 1, s.move.at[1] + 1];
      sel._handleMouseMove({ clientX: 0, clientY: s.move.py + 0.5, stopImmediatePropagation() {} });
    } else if (s.dragScroll) {
      o.dragScroll = true;
      sel._dragScroll();
    } else if (s.release) {
      o.release = true;
      sel._handleMouseUp({ timeStamp: 1000, altKey: false });
    } else if (s.rightClick) {
      o.rightClick = s.rightClick;
      state.point = [s.rightClick.at[0] + 1, s.rightClick.at[1] + 1];
      sel.rightClickSelect({ clientX: 0, clientY: 0 });
    } else if (s.link !== undefined) {
      o.link = s.link;
      state.link = s.link
        ? { link: { range: { start: { x: s.link[0], y: s.link[1] }, end: { x: s.link[2], y: s.link[3] } } } }
        : undefined;
    } else if (s.selectAll) {
      o.selectAll = true;
      sel.selectAll();
    } else if (s.selectLines) {
      o.selectLines = s.selectLines;
      sel.selectLines(s.selectLines[0], s.selectLines[1]);
    } else if (s.setSelection) {
      o.setSelection = s.setSelection;
      sel.setSelection(s.setSelection[0], s.setSelection[1], s.setSelection[2]);
    } else if (s.clear) {
      o.clear = true;
      sel.clearSelection();
    } else if (s.userInput) {
      o.userInput = true;
      core.coreService.triggerDataEvent('x', true);
    } else {
      throw new Error(`${c.id}: unknown step ${JSON.stringify(s)}`);
    }
    o.after = snapshot();
    return o;
  };
  const snapshot = () => {
    const start = sel._model.finalSelectionStart;
    const end = sel._model.finalSelectionEnd;
    const mode = sel._activeSelectionMode;
    const buf = core._bufferService.buffer;
    const spans = [];
    for (let r = 0; r < term.rows; r++) {
      const y = buf.ydisp + r;
      let from = -1, to = -1;
      for (let x = 0; x < term.cols; x++) {
        const hit = B.DomRendererRowFactory.prototype._isCellInSelection.call(
          { _selectionStart: start, _selectionEnd: end, _columnSelectMode: mode === 3 }, x, y);
        if (hit) {
          if (from === -1) from = x;
          else if (to !== x) throw new Error(`${c.id}: selected columns of row ${y} are not contiguous`);
          to = x + 1;
        }
      }
      spans.push(from === -1 ? null : [from, to]);
    }
    const m = sel._model;
    return {
      start: pt(start), end: pt(end),
      raw: [pt(m.selectionStart), pt(m.selectionEnd), m.selectionStartLength, m.isSelectAllActive],
      mode, has: sel.hasSelection, text: b64(sel.selectionText), changes,
      dragAmount: sel._dragScrollAmount, ydisp: buf.ydisp, ybase: buf.ybase, trimmed, spans,
    };
  };
  const outSteps = c.steps.map(doStep);
  // THE SAME SERVICE AGAIN: back to the case's size, term.reset(), the first three
  // steps once more (the harness state -- the program's mouse, the link -- carries on,
  // as it would for a control that is reset).
  if (term.cols !== c.cols || term.rows !== c.rows) term.resize(c.cols, c.rows);
  term.reset();
  const rerun = c.steps.slice(0, 3).map(s => doStep(s).after);
  const out = { id: c.id, cols: c.cols, rows: c.rows, scrollback: c.scrollback };
  if (c.wordSeparator !== undefined) out.wordSeparator = c.wordSeparator;
  out.steps = outSteps;
  out.rerun = rerun;
  term.dispose();
  return out;
}

const seen = new Set();
const cases = C.CASES.map(c => {
  if (seen.has(c.id)) throw new Error('duplicate case id ' + c.id);
  seen.add(c.id);
  return runCase(c);
});
L.writeFixture('terminal-selection.json', {
  upstream: L.upstreamInfo(), generator: 'tools/terminal-oracle/selection-cases.js', kind: 'selection',
  cellHeight: L.CELL_H, dragThreshold: 50, cases,
});
let steps = 0;
for (const c of cases) steps += c.steps.length;
console.log(`selection: ${cases.length} cases, ${steps} steps`);
