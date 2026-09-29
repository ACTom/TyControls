// Inputs for buffer-cases.js -- only inputs; the vocabulary of targets, ops and
// snapshots is in buffer-cases.js's header. Every expected value comes from xterm.js.
'use strict';

const W = 1 << 22;                 // width 1, in a content word
const HAS_EXT = 0x10000000;        // BgFlags.HAS_EXTENDED
const PROT = 0x20000000;           // BgFlags.PROTECTED
const A0 = { fg: 0, bg: 0 };
const WIDE = new Set([...'中文字宽表']);

const cell = (cp, w = 1, fg = 0, bg = 0, ext) => Object.assign({ content: (cp | (w << 22)) >>> 0, fg, bg }, ext ? { ext } : {});
const nul = (fg = 0, bg = 0) => cell(0, 1, fg, bg);
const comb = (cps, w = 1, fg = 0, bg = 0) => ({ content: (0x200000 | (w << 22)) >>> 0, fg, bg, comb: cps });

// setCellFromCodepoint ops writing S from COL, wide characters taking two cells.
function txt(n, col, s, attr = A0) {
  const ops = [];
  for (const ch of s) {
    const cp = ch.codePointAt(0);
    if (WIDE.has(ch)) {
      ops.push(['setCellFromCodepoint', n, col, cp, 2, attr], ['setCellFromCodepoint', n, col + 1, 0, 0, attr]);
      col += 2;
    } else {
      ops.push(['setCellFromCodepoint', n, col, cp, 1, attr]);
      col++;
    }
  }
  return ops;
}
const probeAll = (n, cols) => Array.from({ length: cols }, (_, c) => ['probe', n, c]);

const line = (id, lines, ops) => ({ id, target: 'line', init: { lines }, ops });
const L1 = cols => ({ A: { cols } });

const lineCases = [
  line('line-insert-wide-left', L1(8), [...txt('A', 0, 'a中b中'), ['insertCells', 'A', 2, 1, nul()], ...probeAll('A', 8)]),
  line('line-insert-wide-end', L1(6), [...txt('A', 0, 'abcd中'), ['insertCells', 'A', 0, 1, nul(0, 0x1000001)],
    ...txt('A', 0, 'ab中c'), ['insertCells', 'A', 1, 1, nul()]]),
  line('line-insert-big', L1(8), [...txt('A', 0, 'abcdefgh'), ['insertCells', 'A', 2, 2147483647, nul(0, 0x1000002)],
    ...txt('A', 0, 'abcdefgh'), ['insertCells', 'A', 10, 3, nul()], ['insertCells', 'A', 7, 1, nul()]]),
  line('line-delete-wide', L1(9), [...txt('A', 0, 'a中b中c'), ['deleteCells', 'A', 2, 1, nul()],
    ...txt('A', 0, 'a中b中c'), ['deleteCells', 'A', 1, 3, nul()], ...txt('A', 0, 'ab中de中'), ['deleteCells', 'A', 0, 3, nul()]]),
  line('line-delete-big', L1(8), [...txt('A', 0, 'abcdefgh'), ['deleteCells', 'A', 3, 2147483647, nul(0, 0x1000003)],
    ...txt('A', 0, 'abcdefgh'), ['deleteCells', 'A', 9, 2, nul()]]),
  line('line-replace-wide-edges', L1(9), [...txt('A', 0, 'a中中中'), ['replaceCells', 'A', 2, 3, nul(), false],
    ...txt('A', 0, 'a中中中'), ['replaceCells', 'A', 0, 0, nul(), false], ['replaceCells', 'A', 4, 8, nul(0, 0x1000004), false]]),
  line('line-replace-protect', L1(10), [...txt('A', 0, 'ab'), ...txt('A', 2, 'cd', { fg: 0, bg: PROT }), ...txt('A', 4, '中', { fg: 0, bg: PROT }),
    ...txt('A', 6, '中'), ...txt('A', 8, 'ef'), ['replaceCells', 'A', 1, 7, nul(), true], ['replaceCells', 'A', 5, 9, nul(), true],
    ['replaceCells', 'A', 0, 10, nul(), true], ...probeAll('A', 10)]),
  // the end fix looks at the protection of the cell AT end: a wide lead and its stub
  // protected differently tell end from end - 1
  line('line-replace-protect-stub', L1(8), [...txt('A', 0, 'ab'), ['setCellFromCodepoint', 'A', 2, 0x4E2D, 2, { fg: 0, bg: PROT }],
    ['setCellFromCodepoint', 'A', 3, 0, 0, A0], ['replaceCells', 'A', 0, 3, nul(), true], ...probeAll('A', 4),
    ['setCellFromCodepoint', 'A', 4, 0x4E2D, 2, A0], ['setCellFromCodepoint', 'A', 5, 0, 0, { fg: 0, bg: PROT }],
    ['replaceCells', 'A', 0, 5, nul(), true], ...probeAll('A', 8)]),
  line('line-replace-end-beyond', L1(8), [...txt('A', 0, 'abcdefgh'), ['replaceCells', 'A', 3, 99999999999, nul(0, 0x1000005), false],
    ...txt('A', 0, 'abcdefgh'), ['replaceCells', 'A', 5, 2147483648, nul(), true]]),
  line('line-combine-empty', L1(6), [['addCodepointToCell', 'A', 1, 0x301, 0], ['addCodepointToCell', 'A', 2, 0x301, 2],
    ...probeAll('A', 3), ['load', 'A', 1]]),
  line('line-combine-twice', L1(6), [...txt('A', 0, 'e'), ['addCodepointToCell', 'A', 0, 0x301, 0], ['addCodepointToCell', 'A', 0, 0x1F600, 0],
    ['probe', 'A', 0], ['load', 'A', 0], ['translate', 'A', false, null, null]]),
  line('line-combine-width', L1(6), [...txt('A', 0, 'x'), ['addCodepointToCell', 'A', 0, 0xFE0F, 2], ['probe', 'A', 0],
    ...txt('A', 2, '☺'), ['addCodepointToCell', 'A', 2, 0xFE0F, 0], ['probe', 'A', 2]]),
  line('line-resize-shrink-combined', L1(8), [...txt('A', 0, 'abcde'), ['addCodepointToCell', 'A', 5, 0x301, 0],
    ['setCellFromCodepoint', 'A', 6, 0x78, 1, { fg: 0, bg: HAS_EXT, ext: { style: 3 } }],
    ['resize', 'A', 4, nul()], ['resize', 'A', 8, nul()], ...probeAll('A', 8), ['load', 'A', 6]]),
  line('line-resize-grow', L1(4), [...txt('A', 0, 'abcd'), ['resize', 'A', 7, cell(0x2e, 1, 0x1000001)], ['resize', 'A', 12, nul()],
    ['resize', 'A', 3, nul()], ['resize', 'A', 12, nul()], ['resize', 'A', 30, nul()]]),
  line('line-resize-same', L1(6), [['resize', 'A', 6, nul()], ['resize', 'A', 2, nul()], ['resize', 'A', 2, nul()],
    ['resize', 'A', 5, nul()], ['resize', 'A', 5, nul()]]),
  line('line-fill-protect', L1(6), [...txt('A', 0, 'ab'), ...txt('A', 2, 'cd', { fg: 0, bg: PROT }), ['addCodepointToCell', 'A', 0, 0x301, 0],
    ['fill', 'A', cell(0x2e, 1, 0x1000002), true], ['fill', 'A', nul(), false]]),
  line('line-copyfrom-lengths', { A: { cols: 6 }, B: { cols: 4 }, C: { cols: 6 } }, [...txt('A', 0, 'abc'), ['addCodepointToCell', 'A', 1, 0x301, 0],
    ['setCellFromCodepoint', 'A', 2, 0x7a, 1, { fg: 0, bg: HAS_EXT, ext: { urlId: 3 } }], ['setWrapped', 'A', true],
    ['copyFrom', 'B', 'A', false], ['copyFrom', 'C', 'A', false], ['copyFrom', 'C', 'B', true], ['resize', 'B', 9, nul()]]),
  line('line-clone-blank', { A: { cols: 5 } }, [...txt('A', 0, 'ab'), ['addCodepointToCell', 'A', 0, 0x301, 0], ['setWrapped', 'A', true],
    ['clone', 'B', 'A', false], ['clone', 'C', 'A', true], ['setCellFromCodepoint', 'A', 1, 0x71, 1, A0]]),
  line('line-copycells-reverse', { A: { cols: 8 }, B: { cols: 8 } }, [...txt('A', 0, 'abcdefgh'), ['addCodepointToCell', 'A', 2, 0x301, 0],
    ['copyCellsFrom', 'A', 'A', 1, 3, 4, true], ...txt('A', 0, 'abcdefgh'), ['copyCellsFrom', 'A', 'A', 1, 3, 4, false],
    ...txt('A', 0, 'abcdefgh'), ['copyCellsFrom', 'A', 'A', 3, 1, 4, false], ['copyCellsFrom', 'B', 'A', 0, 2, 3, false]]),
  line('line-translate', L1(10), [...txt('A', 0, 'a中'), ['addCodepointToCell', 'A', 3, 0x301, 0], ...txt('A', 3, 'e'),
    ['addCodepointToCell', 'A', 3, 0x301, 0], ['setCellFromCodepoint', 'A', 5, 0x20, 1, A0],
    ['translate', 'A', false, null, null], ['translate', 'A', true, null, null], ['translate', 'A', false, 2, null],
    ['translate', 'A', false, 1, 3], ['translate', 'A', true, 2, 9], ['translate', 'A', false, 0, 2], ['translate', 'A', true, 6, 10],
    ['translate', 'A', false, 12, 20]]),
  line('line-translate-cache', L1(6), [...txt('A', 0, 'ab'), ['setCellFromCodepoint', 'A', 2, 0x20, 1, A0], ['setCellFromCodepoint', 'A', 3, 0xa0, 1, A0],
    ['translate', 'A', false, null, null], ['translate', 'A', true, null, null], ['translate', 'A', true, 0, null],
    ['translate', 'A', true, null, null], ['setCellFromCodepoint', 'A', 4, 0x3000, 1, A0],
    ['translate', 'A', true, null, null], ['translate', 'A', false, null, null], ['translate', 'A', true, null, null]]),
  line('line-trimmed', L1(6), [['trimmed', 'A'], ...txt('A', 0, 'ab'), ['trimmed', 'A'], ...txt('A', 4, '中'), ['trimmed', 'A'],
    ['setCellFromCodepoint', 'A', 5, 0, 1, A0], ['trimmed', 'A'], ['noBgTrimmed', 'A']]),
  line('line-nobg-trimmed', L1(6), [['setCellFromCodepoint', 'A', 4, 0, 1, { fg: 0, bg: 0x1000004 }], ['noBgTrimmed', 'A'], ['trimmed', 'A'],
    ['setCellFromCodepoint', 'A', 5, 0, 1, { fg: 0x1000001, bg: 0 }], ['noBgTrimmed', 'A']]),
  line('line-ext-urlid', L1(4), [['setCellFromCodepoint', 'A', 0, 0x61, 1, { fg: 0, bg: HAS_EXT, ext: { urlId: 7 } }],
    ['setCellFromCodepoint', 'A', 1, 0x62, 1, { fg: 0, bg: HAS_EXT, ext: { style: 3, urlId: 7 } }],
    ['setCellFromCodepoint', 'A', 2, 0x63, 1, { fg: 0, bg: HAS_EXT, ext: { style: 2, color: 0x2000005 } }],
    ['load', 'A', 0], ['load', 'A', 1], ['load', 'A', 2], ['load', 'A', 3]]),
  line('line-ext-variant', L1(8), [1, 2, 3, 4, 5, 6, 7].map(v => ['setCellFromCodepoint', 'A', v, 0x61, 1, { fg: 0, bg: HAS_EXT, ext: { style: 3, variant: v } }])
    .concat([['load', 'A', 3], ['load', 'A', 4], ['load', 'A', 7]])),
  line('line-ext-sgr59', L1(4), [['setCellFromCodepoint', 'A', 0, 0x41, 1, { fg: 0, bg: HAS_EXT, ext: { style: 3, color: 0x2000009 } }],
    ['setCellFromCodepoint', 'A', 1, 0x42, 1, { fg: 0, bg: HAS_EXT, ext: { style: 3, color: -1 } }],
    ['setCellFromCodepoint', 'A', 2, 0x43, 1, { fg: 0, bg: HAS_EXT, ext: { raw: 0x0FFFFFFF, color: 0x1000002 } }], ['load', 'A', 1], ['load', 'A', 2]]),
  line('line-setcell', { A: { cols: 5, fill: cell(0x2e, 1, 0x1000001, 0x1000002) } }, [['setCell', 'A', 1, comb([0x61, 0x301], 1, 5, 6)],
    ['setCell', 'A', 2, cell(0x62, 1, 0, HAS_EXT, { style: 4, urlId: 2 })], ['setCell', 'A', 3, cell(0x4e2d, 2)], ['setCell', 'A', 4, cell(0, 0)],
    ...probeAll('A', 5), ['load', 'A', 1], ['load', 'A', 2], ['translate', 'A', false, null, null]]),
];

// ---- list ------------------------------------------------------------------------

const list = (id, max, ops) => ({ id, target: 'list', init: { max }, ops });
const pushes = (from, to) => Array.from({ length: to - from + 1 }, (_, i) => ['push', from + i]);

const listCases = [
  list('list-push-trim', 3, [...pushes(1, 5), ['get', 0], ['get', 2], ['get', 3]]),
  list('list-recycle', 3, [['recycle'], ...pushes(1, 3), ['recycle'], ['set', 2, 9], ['recycle'], ['get', 0]]),
  list('list-pop', 4, [...pushes(1, 3), ['pop'], ['pop'], ['push', 7], ['get', 1]]),
  list('list-splice-delete', 6, [...pushes(1, 6), ['splice', 1, 2, []], ['splice', 0, 1, []], ['splice', 2, 5, []]]),
  list('list-splice-insert-overflow', 5, [...pushes(1, 4), ['splice', 1, 0, [10, 11, 12]], ['splice', 4, 0, [20]]]),
  list('list-splice-both', 6, [...pushes(1, 6), ['splice', 2, 1, [30, 31]], ['splice', 0, 2, [40]]]),
  list('list-trimstart-over', 5, [...pushes(1, 3), ['trimStart', 2], ['trimStart', 9], ['push', 8], ['get', 0]]),
  list('list-shift-up-expand', 5, [...pushes(1, 4), ['shift', 1, 3, 1], ['shift', 2, 3, 2], ['shift', 0, 2, 4]]),
  list('list-shift-down', 6, [...pushes(1, 6), ['shift', 2, 3, -2], ['shift', 1, 0, -1], ['shift', 4, 2, -1]]),
  list('list-shift-errors', 4, [...pushes(1, 3), ['shift', 3, 1, 1], ['shift', -1, 1, 1], ['shift', 1, 2, -2], ['shift', 0, 1, -1]]),
  list('list-setmax-shrink', 5, [...pushes(1, 7), ['setMax', 3], ['get', 3], ['push', 9], ['setMax', 3]]),
  list('list-setmax-grow', 3, [...pushes(1, 5), ['setMax', 6], ['push', 8], ['push', 9], ['get', 4]]),
  list('list-setlength-grow', 4, [...pushes(1, 2), ['setLength', 4], ['setLength', 1], ['setLength', 3], ['get', 1]]),
  list('list-wrapped-start', 4, [...pushes(1, 6), ['splice', 1, 1, [7]], ['trimStart', 1], ['splice', 0, 0, [8, 9]], ['get', -1], ['shift', 0, 2, 1]]),
];

// ---- buffers ---------------------------------------------------------------------

const bufs = (id, cols, rows, options, ops) => ({ id, target: 'buffers', init: { cols, rows, options }, ops });
const scrolls = (n, attr = A0, wrapped = false) => Array.from({ length: n }, () => ['scroll', attr, wrapped]);
const WPTY = { backend: 'conpty', buildNumber: 19044 };

const bufferCases = [
  bufs('scroll-push', 6, 3, { scrollback: 4 }, [['text', 0, 0, 'top'], ['setXY', 2, 2], ...scrolls(2), ['text', 4, 0, 'b'], ...scrolls(1, { fg: 0, bg: 0x1000003 }, true)]),
  bufs('scroll-recycle', 6, 3, { scrollback: 2 }, [['text', 0, 0, 'l0'], ['setXY', 0, 2], ...scrolls(2), ['text', 4, 0, 'l4'], ...scrolls(3)]),
  bufs('scroll-splice', 6, 4, { scrollback: 3 }, [['text', 0, 0, 'a'], ['text', 3, 0, 'z'], ['setMargins', 0, 1], ...scrolls(2), ['setMargins', 0, 3], ...scrolls(1)]),
  bufs('scroll-region-shift', 6, 5, { scrollback: 3 }, [['text', 1, 0, 'r1'], ['text', 2, 0, 'r2'], ['text', 3, 0, 'r3'], ['setMargins', 1, 3], ...scrolls(2, { fg: 0, bg: 0x1000001 })]),
  bufs('scroll-user-scrolling', 6, 3, { scrollback: 3 }, [...scrolls(3), ['scrollLines', -2], ...scrolls(1), ['scrollLines', -5], ...scrolls(3), ['scrollLines', 9], ...scrolls(1)]),
  bufs('scroll-cached-blank', 6, 3, { scrollback: 6, windowsPty: WPTY }, [...scrolls(2, { fg: 0, bg: 0x1000002 }), ...scrolls(1, { fg: 0, bg: 0x1000002 }, true), ...scrolls(1, { fg: 0, bg: 0x1000004 }),
    ...scrolls(1, { fg: 0x1000001, bg: 0x1000004 }), ['resize', 7, 3], ...scrolls(1, { fg: 0x1000001, bg: 0x1000004 })]),
  bufs('lines-scroll', 6, 3, { scrollback: 5 }, [...scrolls(4), ['scrollLines', -1], ['scrollLines', -2], ['scrollLines', -9], ['scrollLines', 0], ['scrollLines', 2], ['scrollLines', 9], ['scrollLines', 1]]),
  bufs('rows-grow-scrollup', 6, 3, { scrollback: 5 }, [['text', 0, 0, 'l0'], ['setXY', 0, 2], ...scrolls(3), ['text', 5, 0, 'cur'], ['resize', 6, 5], ['resize', 6, 8]]),
  bufs('rows-grow-blank', 6, 3, { scrollback: 5 }, [['setXY', 0, 0], ...scrolls(2), ['setXY', 1, 0], ['resize', 6, 5]]),
  bufs('rows-shrink-pop', 6, 5, { scrollback: 5 }, [['text', 0, 0, 'top'], ['setXY', 1, 1], ['resize', 6, 3], ['resize', 6, 2]]),
  bufs('rows-shrink-cursor', 6, 5, { scrollback: 5 }, [['text', 4, 0, 'bot'], ['setXY', 2, 4], ['resize', 6, 3], ['resize', 6, 1]]),
  bufs('rows-grow-windowspty', 6, 3, { scrollback: 5, windowsPty: WPTY }, [['setXY', 0, 2], ...scrolls(3), ['resize', 6, 6]]),
  bufs('cols-change-windowspty', 8, 3, { scrollback: 3, windowsPty: WPTY }, [['text', 0, 0, 'abcdefgh'], ['text', 1, 0, 'xy'], ['resize', 5, 3], ['resize', 11, 3], ['setXY', 7, 1], ['resize', 4, 3]]),
  bufs('maxlength-trim', 6, 3, { scrollback: 6 }, [['text', 0, 0, 'l0'], ['addMarker', 0], ['addMarker', 2], ['addMarker', 5], ...scrolls(5), ['setYdisp', 2], ['saveY', 4],
    ['setOption', 'scrollback', 2], ['setOption', 'scrollback', 0], ['setOption', 'scrollback', 4]]),
  // columns change: only under an old ConPTY, where upstream does not reflow (phase 5)
  bufs('resize-cursor-clamp', 8, 4, { scrollback: 2, windowsPty: WPTY }, [['setXY', 7, 3], ['saveX', 6], ['setMargins', 1, 2], ['resize', 5, 2], ['resize', 3, 4]]),
  bufs('alt-activate', 6, 3, { scrollback: 3 }, [['setXY', 3, 1], ['activateAlt', { fg: 0, bg: 0x1000006 }], ['text', 0, 0, 'alt'], ['setXY', 4, 2]]),
  bufs('alt-activate-twice', 6, 3, {}, [['activateAlt', null], ['setXY', 2, 2], ['activateAlt', { fg: 0, bg: 0x1000001 }]]),
  bufs('alt-back', 6, 3, { scrollback: 2 }, [['activateAlt', null], ['addMarker', 1], ['text', 1, 0, 'x'], ['setXY', 5, 2], ['activateNormal'], ['activateNormal'], ['activateAlt', null]]),
  bufs('alt-no-scrollback', 6, 3, { scrollback: 4 }, [['activateAlt', null], ['text', 0, 0, 'a0'], ...scrolls(3), ['scrollLines', -1]]),
  bufs('alt-zero-scrollback', 6, 3, { scrollback: 0 }, [...scrolls(2), ['activateAlt', null], ...scrolls(1)]),
  bufs('reset-buffers', 6, 3, { scrollback: 3 }, [...scrolls(4), ['scrollLines', -1], ['addMarker', 2], ['activateAlt', null], ['reset']]),
  bufs('tabs-default', 12, 3, {}, [['nextStop', 0], ['nextStop', 8], ['prevStop', 11], ['prevStop', null]]),
  bufs('tabs-width-option', 12, 3, {}, [['tabSet', 3], ['setOption', 'tabStopWidth', 4], ['nextStop', 1], ['setOption', 'tabStopWidth', 4], ['setOption', 'tabStopWidth', 5]]),
  bufs('tabs-after-resize', 12, 3, { windowsPty: WPTY }, [['resize', 7, 3], ['resize', 20, 3], ['tabSet', 12], ['resize', 10, 3], ['tabClear', 16], ['resize', 21, 3], ['setupTabStops', 13], ['setupTabStops', null]]),
  bufs('tabs-beyond-cols', 10, 3, {}, [['setXY', 10, 0], ['tabSet', 10], ['nextStop', 9], ['prevStop', 12], ['tabClearAll'], ['nextStop', 0], ['prevStop', 5]]),
  bufs('tabs-next-prev-edges', 10, 3, {}, [...[-1, 0, 9, 10, 13].flatMap(x => [['nextStop', x], ['prevStop', x]]), ['setXY', 4, 0], ['nextStop', null]]),
  bufs('markers-trim', 6, 3, { scrollback: 2 }, [['addMarker', 0], ['addMarker', 1], ['addMarker', 2], ...scrolls(3), ['addMarker', 4]]),
  bufs('markers-insert-delete', 6, 5, { scrollback: 2 }, [['addMarker', 0], ['addMarker', 1], ['addMarker', 2], ['addMarker', 3], ['addMarker', 4], ['setMargins', 0, 2], ...scrolls(1),
    ['setMargins', 1, 3], ...scrolls(1), ['setMargins', 0, 4]]),
  bufs('markers-clear-line', 6, 3, {}, [['addMarker', 1], ['addMarker', 1], ['addMarker', 2], ['clearMarkers', 1], ['clearMarkers', 0]]),
  bufs('markers-clear-all', 6, 3, {}, [['addMarker', 0], ['addMarker', 2], ['clearAllMarkers'], ['addMarker', 1]]),
  bufs('markers-dispose-twice', 6, 3, {}, [['addMarker', 0], ['addMarker', 2], ['disposeMarker', 0], ['disposeMarker', 0], ['disposeMarker', 1]]),
  bufs('wrapped-range', 6, 6, {}, [['setWrapped', 1, true], ['setWrapped', 2, true], ['setWrapped', 4, true], ['setWrapped', 0, true], ['wrappedRange', 0], ['wrappedRange', 2],
    ['wrappedRange', 3], ['wrappedRange', 4], ['wrappedRange', 5], ['setWrapped', 5, true], ['wrappedRange', 5]]),
  bufs('fill-and-clear', 6, 3, { scrollback: 2 }, [['fillViewport', null], ['activateAlt', null], ['clear'], ['fillViewport', { fg: 0, bg: 0x1000002 }], ['fillViewport', null]]),
  bufs('link-no-id', 6, 3, {}, [['registerLink', null, 'http://a'], ['registerLink', null, 'http://a'], ['getLinkData', 1], ['getLinkData', 3]]),
  bufs('link-with-id-reuse', 6, 3, {}, [['registerLink', 'x', 'http://a'], ['setXY', 0, 2], ['registerLink', 'x', 'http://a'], ['registerLink', 'x', 'http://b'], ['registerLink', 'y', 'http://a'], ['getLinkData', 1]]),
  bufs('link-add-line-dup', 6, 3, {}, [['registerLink', null, 'u'], ['addLineToLink', 1, 0], ['addLineToLink', 1, 2], ['addLineToLink', 1, 2], ['addLineToLink', 9, 1]]),
  bufs('link-trimmed-out', 6, 2, { scrollback: 1 }, [['registerLink', 'i', 'u'], ['setXY', 0, 1], ['registerLink', null, 'v'], ...scrolls(1), ['getLinkData', 1], ...scrolls(1), ['getLinkData', 1], ['getLinkData', 2],
    ['registerLink', 'i', 'u']]),
  bufs('link-alt-switch', 6, 3, {}, [['activateAlt', null], ['registerLink', 'k', 'u'], ['registerLink', null, 'w'], ['activateNormal'], ['getLinkData', 1], ['getLinkData', 2], ['registerLink', 'k', 'u']]),
];

// ---- reflow (phase 5) ----------------------------------------------------------------
// The shapes of src/common/buffer/Buffer.test.ts:260-1140, one criterion per case, as
// buffer operations; every answer is upstream's own. The upstream tests start from an
// 80 x 24 buffer and resize it, so do these. (The upstream test's MockBufferService
// keeps 80 columns for the blank lines reflow inserts; the real service here has the
// new width -- the terminal's behaviour, which is what the port is held to.)

// [cp, width] cells for a string: CJK and the emoji plane two cells (the second [0, 0])
const cellsOf = s => [...s].flatMap(ch => {
  const cp = ch.codePointAt(0);
  return (cp >= 0x4E00 && cp <= 0x9FFF) || cp >= 0x1F300 ? [[cp, 2], [0, 0]] : [[cp, 1]];
});
const RS = (id, options, ops) => bufs('reflow-' + id, 80, 24, options, ops);
// the setups the upstream describe blocks share
const larger = [['resize', 2, 10], ['text', 0, 0, 'ab'], ['text', 1, 0, 'cd'], ['setWrapped', 1, true], ['text', 2, 0, 'ef'],
  ['text', 3, 0, 'gh'], ['setWrapped', 3, true], ['text', 4, 0, 'ij'], ['text', 5, 0, 'kl'], ['setWrapped', 5, true]];
const smaller = [['resize', 4, 10], ['text', 0, 0, 'abcd'], ['text', 1, 0, 'efgh'], ['text', 2, 0, 'ijkl']];
const tenBlank = [['insertBlank', 0, 10], ['setYbase', 10]];
const wideRows = [['resize', 12, 10], ['setXY', 0, 2], ['cells', 0, 0, cellsOf('汉语汉语汉语')], ['cells', 1, 0, cellsOf('汉语汉语汉语')],
  ['setWrapped', 1, true]];
const tabEnd = [['resize', 4, 10], ['setXY', 0, 2], ['text', 0, 0, 'ab'], ['text', 1, 0, 'cd'], ['setWrapped', 1, true]];

bufferCases.push(
  // phase 2 ran these under an old ConPTY to keep reflow out; the same in the default setup
  bufs('cols-change-windowspty-reflow', 8, 3, { scrollback: 3 }, [['text', 0, 0, 'abcdefgh'], ['text', 1, 0, 'xy'], ['resize', 5, 3], ['resize', 11, 3], ['setXY', 7, 1], ['resize', 4, 3]]),
  bufs('resize-cursor-clamp-reflow', 8, 4, { scrollback: 2 }, [['setXY', 7, 3], ['saveX', 6], ['setMargins', 1, 2], ['resize', 5, 2], ['resize', 3, 4]]),
  bufs('tabs-after-resize-reflow', 12, 3, {}, [['resize', 7, 3], ['resize', 20, 3], ['tabSet', 12], ['resize', 10, 3], ['tabClear', 16], ['resize', 21, 3], ['setupTabStops', 13], ['setupTabStops', null]]),
  // should not wrap empty lines / should shrink row length
  RS('empty-lines-stay', {}, [['resize', 75, 24]]),
  RS('rows-shrink-to-the-cols', {}, [['resize', 5, 10]]),
  // should wrap and unwrap lines (one column: no wide character, see BufferReflow.ts:175-177)
  RS('wrap-and-unwrap', {}, [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 1, 10], ['resize', 5, 10]]),
  // should gate reflow on ConPTY buildNumber 21376
  RS('conpty-21375-does-not-wrap', { windowsPty: { backend: 'conpty', buildNumber: 21375 } },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 1, 10]]),
  RS('conpty-21376-wraps', { windowsPty: { backend: 'conpty', buildNumber: 21376 } },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 1, 10], ['resize', 5, 10]]),
  // the other Windows settings upstream tells apart (Buffer.ts:310-316)
  RS('winpty-with-build-does-not-wrap', { windowsPty: { backend: 'winpty', buildNumber: 30000 } },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 2, 10], ['resize', 5, 10]]),
  RS('build-without-backend-does-not-wrap', { windowsPty: { buildNumber: 30000 } },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 2, 10], ['resize', 5, 10]]),
  RS('conpty-without-build-wraps', { windowsPty: { backend: 'conpty' } },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 2, 10], ['resize', 5, 10]]),
  RS('no-scrollback-wraps', { scrollback: 0 },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['setXY', 0, 1], ['resize', 2, 10], ['resize', 5, 10]]),
  // should (not) reflow wrapped lines containing the cursor
  RS('cursor-line-reflowed-when-asked', { reflowCursorLine: true },
    [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['resize', 1, 10], ['setXY', 0, 2], ['resize', 5, 10]]),
  RS('cursor-line-kept-by-default', {}, [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['resize', 1, 10], ['setXY', 0, 2], ['resize', 5, 10]]),
  RS('cursor-line-option-set-later', {}, [['resize', 5, 10], ['text', 0, 0, 'abcde'], ['resize', 1, 10], ['setXY', 0, 2],
    ['setOption', 'reflowCursorLine', true], ['resize', 5, 10]]),
  // should discard parts of wrapped lines that go out of the scrollback
  RS('scrollback-drops-the-top', {}, [['setOption', 'scrollback', 1], ['resize', 10, 5], ['text', 3, 0, 'abcdefghij'], ['setXY', 0, 4],
    ['resize', 2, 5], ['resize', 1, 5], ['resize', 10, 5]]),
  // should remove the correct amount of rows when reflowing larger
  RS('larger-removes-the-right-rows', {}, [['resize', 10, 10], ['setXY', 0, 2], ['text', 0, 0, 'abcdefghij'], ['text', 1, 0, '0123456789'],
    ['resize', 2, 10], ['resize', 10, 10]]),
  // should transfer combined char data over to reflowed lines
  RS('combined-data-moves', {}, [['resize', 4, 3], ['setXY', 0, 2], ['text', 0, 0, 'abc'], ['cells', 0, 3, [[0x1F601, 1]]], ['resize', 2, 3]]),
  RS('combining-mark-moves', {}, [['resize', 6, 5], ['setXY', 0, 3], ['text', 0, 0, 'abcde'], ['combine', 0, 4, 0x301], ['text', 1, 0, 'fg'],
    ['setWrapped', 1, true], ['resize', 3, 5], ['resize', 7, 5]]),
  // should adjust markers when reflowing
  RS('markers-follow', {}, [['resize', 10, 16], ['text', 0, 0, 'abcdefghij'], ['text', 1, 0, '0123456789'], ['text', 2, 0, 'klmnopqrst'],
    ['setXY', 0, 3], ['addMarker', 0], ['addMarker', 1], ['addMarker', 2], ['resize', 2, 16], ['resize', 10, 16]]),
  // should dispose markers whose rows are trimmed during a reflow
  RS('markers-trimmed-away', {}, [['setOption', 'scrollback', 1], ['resize', 10, 11], ['text', 0, 0, 'abcdefghij'], ['text', 1, 0, '0123456789'],
    ['text', 2, 0, 'klmnopqrst'], ['setXY', 0, 10], ['addMarker', 0], ['addMarker', 1], ['addMarker', 2], ['setXY', 0, 3],
    ['resize', 2, 11], ['resize', 10, 11]]),
  // should correctly reflow wrapped lines that end in 0 space (via tab char)
  RS('tab-end-larger', {}, [...tabEnd, ['resize', 5, 10], ['resize', 6, 10]]),
  RS('tab-end-smaller', {}, [...tabEnd, ['resize', 3, 10], ['resize', 2, 10]]),
  // should wrap wide characters correctly when reflowing larger / smaller
  RS('wide-larger', {}, [...wideRows, ['resize', 13, 10], ['resize', 14, 10]]),
  RS('wide-smaller', {}, [...wideRows, ['resize', 11, 10], ['resize', 10, 10], ['resize', 9, 10], ['resize', 8, 10], ['resize', 7, 10],
    ['resize', 6, 10]]),
  RS('wide-down-to-two', {}, [...wideRows, ['resize', 3, 10], ['resize', 2, 10], ['resize', 12, 10]]),
  // reflowLarger cases
  RS('larger-viewport-not-filled', {}, [...larger, ['setXY', 0, 6], ['resize', 4, 10]]),
  RS('larger-filled-ybase-0', {}, [...larger, ['setXY', 0, 9], ['resize', 4, 10]]),
  RS('larger-ydisp-at-ybase', {}, [...larger, ['setXY', 0, 9], ...tenBlank, ['setYdisp', 10], ['resize', 4, 10]]),
  RS('larger-ydisp-above-ybase', {}, [...larger, ['setXY', 0, 9], ...tenBlank, ['setYdisp', 5], ['resize', 4, 10]]),
  RS('larger-full-ydisp-at-ybase', {}, [...larger, ['setOption', 'scrollback', 10], ...tenBlank, ['setXY', 0, 9], ['setYdisp', 10],
    ['resize', 4, 10]]),
  RS('larger-full-ydisp-above-ybase', {}, [...larger, ['setOption', 'scrollback', 10], ...tenBlank, ['setXY', 0, 9], ['setYdisp', 5],
    ['resize', 4, 10]]),
  // reflowSmaller cases
  RS('smaller-viewport-not-filled', {}, [...smaller, ['setXY', 0, 3], ['resize', 2, 10]]),
  RS('smaller-filled-ybase-0', {}, [...smaller, ['setXY', 0, 9], ['resize', 2, 10]]),
  RS('smaller-ydisp-at-ybase', {}, [...smaller, ['setXY', 0, 9], ...tenBlank, ['setYdisp', 10], ['resize', 2, 10]]),
  RS('smaller-ydisp-above-ybase', {}, [...smaller, ['setXY', 0, 9], ...tenBlank, ['setYdisp', 5], ['resize', 2, 10]]),
  RS('smaller-full-ydisp-at-ybase', {}, [...smaller, ['setOption', 'scrollback', 10], ...tenBlank, ['setYdisp', 10], ['setXY', 0, 13],
    ['resize', 2, 10]]),
  RS('smaller-full-ydisp-above-ybase', {}, [...smaller, ['setOption', 'scrollback', 10], ...tenBlank, ['setYdisp', 5], ['setXY', 0, 13],
    ['resize', 2, 10]]),
  // the saved cursor row (savedY) on both ways
  RS('saved-y-follows', {}, [['resize', 4, 6], ['text', 0, 0, 'abcd'], ['text', 1, 0, 'efgh'], ['setWrapped', 1, true], ['text', 2, 0, 'ij'],
    ['setXY', 0, 4], ['saveY', 3], ['resize', 2, 6], ['resize', 8, 6]]),
  // the alternate buffer never reflows; the normal one does behind it
  bufs('reflow-alt-untouched', 6, 4, { scrollback: 5 }, [['text', 0, 0, 'abcdef'], ['text', 1, 0, 'gh'], ['setWrapped', 1, true], ['setXY', 0, 3],
    ['activateAlt', null], ['text', 0, 0, 'ABCDEF'], ['text', 1, 0, 'GH'], ['setWrapped', 1, true], ['resize', 3, 4], ['resize', 8, 4],
    ['activateNormal']]),
);

module.exports = { lineCases, listCases, bufferCases };
