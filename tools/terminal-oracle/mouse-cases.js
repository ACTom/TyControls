// Writes tests/fixtures/terminal-mouse-events.json from xterm.js 6.0.0's mouse
// service, getCoords and the selection's drag-scroll speed (pin and loading in
// lib-dump.js loadBrowserParts).
//
//   node tools/terminal-oracle/mouse-cases.js
//
// send        MouseService._sendEvent (MouseService.ts:104-192), called on its
//             prototype with a service stand-in whose report coordinates are fixed,
//             mouse events active, mouseEventsRequireAlt off, and whose
//             _triggerMouseEvent records what it is given. Rows [type, button,
//             buttons, ctrl, alt, shift, out] with out = [button, action, ctrl, alt,
//             shift] or null (nothing passed on). type 0 mousedown, 1 mouseup, 2
//             mousemove; button / buttons as the DOM has them (buttons: 1 left,
//             2 right, 4 middle).
// coords      getCoords (input/Mouse.ts:40-58) for every device pixel from 3 outside
//             the grid to 3 past it, the pointer at the pixel's centre (px + 0.5):
//             rows [cw, ch, isSel, px, py, x, y] (x, y 1-based, as upstream answers).
//             10 x 5 cells, 7 x 14 and 9 x 19.
// dragAmount  SelectionService._getMouseEventScrollAmount (:417-430) with the canvas
//             140 and 190 pixels high: rows [H, py, amount], py from -120 to H + 120.
'use strict';
const T = require('./lib-term.js');
const L = T.L;

T.loadUpstream();
const B = L.loadBrowserParts();
const SelectionService = B.SelectionService;

// ---- send ---------------------------------------------------------------------------
const TYPES = ['mousedown', 'mouseup', 'mousemove'];
const send = [];
function sendOne(type, button, buttons, ctrl, alt, shift) {
  let out = null;
  const svc = {
    _mouseCoordsService: { getMouseReportCoords: () => ({ col: 3, row: 2, x: 30, y: 20 }) },
    _optionsService: { rawOptions: { mouseEventsRequireAlt: false } },
    _mouseStateService: { areMouseEventsActive: true, allowCustomWheelEvent: () => true },
    _triggerMouseEvent: e => { out = [e.button, e.action, e.ctrl, e.alt, e.shift]; return true; },
  };
  const ev = { type: TYPES[type], button, ctrlKey: ctrl, altKey: alt, shiftKey: shift };
  if (type === 2) ev.buttons = buttons;
  B.MouseService.prototype._sendEvent.call(svc, { target: {} }, ev);
  send.push([type, button, type === 2 ? buttons : 0, ctrl, alt, shift, out]);
}
const MODS = [];
for (let m = 0; m < 8; m++) MODS.push([!!(m & 1), !!(m & 2), !!(m & 4)]);
for (const type of [0, 1]) {
  for (let button = 0; button <= 4; button++) {
    const mods = type === 0 && button === 0 ? MODS : [MODS[0], MODS[7]];
    for (const [ctrl, alt, shift] of mods) sendOne(type, button, 0, ctrl, alt, shift);
  }
}
for (let buttons = 0; buttons <= 7; buttons++) {
  const mods = buttons === 1 ? MODS : [MODS[0], MODS[7]];
  for (const [ctrl, alt, shift] of mods) sendOne(2, 0, buttons, ctrl, alt, shift);
}

// ---- coords ------------------------------------------------------------------------
const win = { getComputedStyle: () => ({ getPropertyValue: () => '0' }) };
const el = { getBoundingClientRect: () => ({ left: 0, top: 0 }) };
const COLS = 10, ROWS = 5;
const coords = [];
for (const [cw, ch] of [[7, 14], [9, 19]]) {
  for (const isSel of [true, false]) {
    for (let px = -3; px <= COLS * cw + 3; px++) {
      for (let py = -3; py <= ROWS * ch + 3; py++) {
        const r = B.getCoords(win, { clientX: px + 0.5, clientY: py + 0.5 }, el, COLS, ROWS, true, cw, ch, isSel);
        coords.push([cw, ch, isSel ? 1 : 0, px, py, r[0], r[1]]);
      }
    }
  }
}

// ---- dragAmount --------------------------------------------------------------------
const dragAmount = [];
for (const H of [140, 190]) {
  const ctx = {
    _coreBrowserService: { window: win }, _screenElement: el,
    _renderService: { dimensions: { css: { canvas: { height: H } } } },
  };
  for (let py = -120; py <= H + 120; py++) {
    const a = SelectionService.prototype._getMouseEventScrollAmount.call(ctx, { clientX: 0, clientY: py + 0.5 });
    dragAmount.push([H, py, a === 0 ? 0 : a]); // -0 -> 0
  }
}

L.writeFixture('terminal-mouse-events.json', {
  upstream: L.upstreamInfo(), generator: 'tools/terminal-oracle/mouse-cases.js', kind: 'mouse-events',
  cols: COLS, rows: ROWS, send, coords, dragAmount,
});
console.log(`mouse-events: ${send.length} events, ${coords.length} coordinates, ${dragAmount.length} drag speeds`);
