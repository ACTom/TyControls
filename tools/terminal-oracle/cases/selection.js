// Cases for selection-cases.js (the step format is in its header). One criterion per
// case (spec 13.5 #8); the groups follow the plan (phase 4a, Task 1 Step 2).
'use strict';

const NBSP = ' ';
// n lines "<prefix><k>" each ended by CR LF
const lines = (n, prefix = 'line-', from = 0) => {
  let s = '';
  for (let k = from; k < from + n; k++) s += prefix + k + '\r\n';
  return s;
};
const press = (x, vr, more) => ({ press: Object.assign({ at: [x, vr] }, more || {}) });
const move = (x, vr, py) => ({ move: { at: [x, vr], py } });
const REL = { release: true };
// a click (press + release) with the given detail
const click = (x, vr, detail, more) => [press(x, vr, Object.assign({ detail }, more || {})), REL];

const CASES = [];
const add = (id, cols, rows, scrollback, steps, extra) =>
  CASES.push(Object.assign({ id, cols, rows, scrollback }, extra || {}, { steps }));

// ---- 1. click and drag -----------------------------------------------------------
add('drag-row-forward', 20, 5, 10, [{ write: 'hello world foo' }, press(0, 0), move(5, 0, 5), REL]);
add('drag-row-backward', 20, 5, 10, [{ write: 'hello world foo' }, press(8, 0), move(2, 0, 5), REL]);
add('drag-across-rows', 20, 5, 10, [{ write: 'aaa\r\nbbb\r\nccc' }, press(1, 0), move(2, 2, 25), REL]);
add('drag-end-on-wide-second-half', 20, 5, 10, [{ write: 'a中文b' }, press(0, 0), move(2, 0, 5), REL]);
add('press-on-wide-second-half', 20, 5, 10, [{ write: 'a中文b' }, press(2, 0), move(5, 0, 5), REL]);
add('press-at-the-right-edge', 10, 5, 10, [{ write: 'abcdefghij' }, press(10, 0), move(3, 0, 5), REL]);
add('press-at-the-right-edge-short-line', 10, 5, 10, [{ write: 'abc' }, press(10, 0), move(3, 0, 5), REL]);
add('drag-in-the-scrollback', 20, 5, 20, [{ write: lines(12) + 'end' }, { scroll: -5 }, press(0, 1), move(4, 2, 25), REL]);
add('drag-back-to-the-start', 20, 5, 10, [{ write: 'hello world' }, press(3, 0), move(6, 0, 5), move(3, 0, 5), REL]);

// ---- 2. double click: words -------------------------------------------------------
add('word-ascii', 20, 5, 10, [{ write: 'foo bar baz' }, ...click(5, 0, 1), ...click(5, 0, 2)]);
add('word-path', 20, 5, 10, [{ write: 'cd a/b.c now' }, ...click(6, 0, 2)]);
const SEPS = [' ', '(', ')', '[', ']', '{', '}', '\'', ',', '"', '`'];
SEPS.forEach((sep, k) => {
  add(`word-separator-${k}-left`, 20, 5, 10, [{ write: 'ab' + sep + 'cd' }, ...click(0, 0, 2)]);
  add(`word-separator-${k}-right`, 20, 5, 10, [{ write: 'ab' + sep + 'cd' }, ...click(4, 0, 2)]);
});
add('word-not-a-separator', 20, 5, 10, [{ write: 'a;b:c-d.e' }, ...click(4, 0, 2)]);
add('word-whitespace-run', 20, 5, 10, [{ write: 'foo    bar' }, ...click(5, 0, 2)]);
add('word-unwritten-cells-default', 20, 5, 10, [{ write: 'foo' }, ...click(1, 0, 2)]);
add('word-unwritten-cells-click', 20, 5, 10, [{ write: 'foo' }, ...click(10, 0, 2)]);
add('word-unwritten-cells-are-separators', 20, 5, 10, [{ write: 'foo bar' }, ...click(1, 0, 2)], { wordSeparator: '()' });
add('word-erased-cells-are-separators', 20, 5, 10, [{ write: 'foo barbaz\x1b[4D\x1b[K' }, ...click(5, 0, 2)], { wordSeparator: '()' });
add('word-cjk', 20, 5, 10, [{ write: '中文字 abc' }, ...click(2, 0, 2)]);
add('word-cjk-second-half', 20, 5, 10, [{ write: '中文字 abc' }, ...click(3, 0, 2)]);
add('word-cjk-after-ascii', 20, 5, 10, [{ write: 'xy 中文z w' }, ...click(6, 0, 2)]);
add('word-emoji', 20, 5, 10, [{ write: 'a\u{1F600}b c' }, ...click(0, 0, 2)]);
add('word-emoji-right', 20, 5, 10, [{ write: 'x a\u{1F600}b c' }, ...click(5, 0, 2)]);
add('word-emoji-on-it', 20, 5, 10, [{ write: 'x a\u{1F600}b c' }, ...click(3, 0, 2)]);
add('word-combining', 20, 5, 10, [{ write: 'café x' }, ...click(0, 0, 2)]);
add('word-combining-after', 20, 5, 10, [{ write: 'x cafés y' }, ...click(6, 0, 2)]);
add('word-wrap-up', 10, 5, 10, [{ write: 'xxxxxxx abcdefghij' }, ...click(1, 1, 2)]);
add('word-wrap-down', 10, 5, 10, [{ write: 'xxxxxxx abcdefghij' }, ...click(8, 0, 2)]);
add('word-wrap-both', 10, 5, 10, [{ write: 'xxxxxxxx abcdefghijklmnopqrstu v' }, ...click(4, 1, 2)]);
add('word-wrap-stops-at-a-space', 10, 5, 10, [{ write: 'xxxxxxxxx abcdefghij' }, ...click(2, 1, 2)]);
add('word-custom-separators', 20, 5, 10, [{ write: 'a:b(c) d' }, ...click(2, 0, 2)], { wordSeparator: ' :' });
add('word-longer-than-a-row', 10, 5, 10, [{ write: 'abcdefghijklmnopqrstuvwxyz' }, ...click(4, 1, 2)]);
add('word-at-the-right-edge', 10, 5, 10, [{ write: 'abc' }, ...click(10, 0, 2)]);
add('word-in-the-scrollback', 20, 5, 20, [{ write: lines(12, 'w ') + 'end' }, { scroll: -4 }, ...click(3, 0, 2)]);

// ---- 3. double click, then drag (word mode) ------------------------------------------
add('word-drag-forward', 20, 5, 10, [{ write: 'foo bar baz qux' }, press(5, 0, { detail: 2 }), move(9, 0, 5), REL]);
add('word-drag-backward', 20, 5, 10, [{ write: 'foo bar baz qux' }, press(9, 0, { detail: 2 }), move(1, 0, 5), REL]);
add('word-drag-into-a-wrapped-word', 10, 5, 10, [{ write: 'ab cd xxx abcdefghij' }, press(1, 0, { detail: 2 }), move(2, 1, 15), REL]);
add('word-drag-back-into-a-wrapped-word', 10, 5, 10, [{ write: 'xxxxxxx abcdefghij kk' }, press(3, 2, { detail: 2 }), move(2, 1, 15), REL]);
add('word-drag-next-row', 20, 5, 10, [{ write: 'foo bar\r\nbaz qux' }, press(1, 0, { detail: 2 }), move(5, 1, 15), REL]);

// ---- 4. triple click: lines -------------------------------------------------------
add('line-plain', 20, 5, 10, [{ write: 'foo bar\r\nsecond' }, ...click(2, 0, 3)]);
add('line-wrapped-from-the-middle', 10, 5, 10, [{ write: 'abcdefghijklmnopqrstuvwxy\r\nnext' }, ...click(4, 1, 3)]);
add('line-drag-down', 20, 5, 10, [{ write: 'one\r\ntwo\r\nthree\r\nfour' }, press(1, 1, { detail: 3 }), move(1, 3, 35), REL]);
add('line-drag-up', 20, 5, 10, [{ write: 'one\r\ntwo\r\nthree\r\nfour' }, press(1, 2, { detail: 3 }), move(1, 0, 5), REL]);
add('line-empty-row', 20, 5, 10, [{ write: 'one\r\n\r\nthree' }, ...click(4, 1, 3)]);

// ---- 5. Shift+click ---------------------------------------------------------------
add('shift-click-extends', 20, 5, 10, [{ write: 'hello world' }, ...click(0, 0, 1), ...click(4, 0, 1, { shift: true })]);
add('shift-click-extends-backward', 20, 5, 10, [{ write: 'hello world' }, ...click(6, 0, 1), ...click(2, 0, 1, { shift: true })]);
add('shift-click-after-a-word', 20, 5, 10, [{ write: 'foo bar baz' }, ...click(5, 0, 2), ...click(9, 0, 1, { shift: true })]);
add('shift-click-forced-when-disabled', 20, 5, 10, [{ write: 'hello world' },
  press(2, 0, { enabled: false }), REL, press(4, 0, { enabled: false, shift: true }), move(7, 0, 5), REL]);
add('shift-click-without-a-start', 20, 5, 10, [{ write: 'hello world' }, ...click(3, 0, 1, { shift: true }), move(6, 0, 5), REL]);

// ---- 6. Alt: columns ----------------------------------------------------------------
add('column-ragged-rows', 20, 5, 10, [{ write: 'abcdef\r\nab\r\nabcdefgh' }, press(1, 0, { alt: true }), move(4, 2, 25), REL]);
add('column-x-reversed', 20, 5, 10, [{ write: 'abcdef\r\nab\r\nabcdefgh' }, press(4, 0, { alt: true }), move(1, 2, 25), REL]);
add('column-y-reversed', 20, 5, 10, [{ write: 'abcdef\r\nab\r\nabcdefgh' }, press(4, 2, { alt: true }), move(1, 0, 5), REL]);
add('column-zero-width', 20, 5, 10, [{ write: 'abcdef\r\nabcdef' }, press(2, 0, { alt: true }), move(2, 1, 15), REL]);
add('column-over-a-wrapped-line', 10, 5, 10, [{ write: 'abcdefghijklmno\r\nxyz' }, press(2, 0, { alt: true }), move(5, 2, 25), REL]);
add('column-wide-chars', 20, 5, 10, [{ write: '中文字\r\nabcdef' }, press(1, 0, { alt: true }), move(4, 1, 15), REL]);

// ---- 7. dragging past the edges -----------------------------------------------------
const edge = (id, pys, extra) => {
  const steps = [{ write: lines(30) + 'last' }, { scroll: -10 }, press(3, 2, extra)];
  for (const py of pys) steps.push(move(py < 0 ? 0 : 20, py < 0 ? 0 : 4, py));
  steps.push({ dragScroll: true }, { dragScroll: true }, { dragScroll: true }, REL);
  add(id, 20, 5, 50, steps);
};
edge('drag-above-1', [-1]);
edge('drag-above-25', [-25]);
edge('drag-above-60', [-60]);
edge('drag-below-1', [51]);
edge('drag-below-25', [75]);
edge('drag-below-60', [110]);
edge('drag-above-column', [-25], { alt: true });
edge('drag-below-column', [75], { alt: true });
edge('drag-above-then-back', [-25, 20]);
add('drag-scroll-without-a-drag', 20, 5, 50, [{ write: lines(30) }, { dragScroll: true }]);
add('drag-scroll-at-the-top', 20, 5, 50, [{ write: lines(30) }, { scroll: -100 }, press(3, 1), move(0, 0, -60),
  { dragScroll: true }, REL]);
add('drag-scroll-at-the-bottom', 20, 5, 50, [{ write: lines(30) }, press(3, 1), move(20, 4, 110), { dragScroll: true }, REL]);

// ---- 8. select all, select lines, set selection --------------------------------------
add('select-all', 10, 5, 10, [{ write: lines(8) }, { selectAll: true }]);
add('select-all-then-click', 10, 5, 10, [{ write: lines(3) }, { selectAll: true }, ...click(2, 0, 1)]);
add('select-lines', 20, 5, 10, [{ write: lines(4) }, { selectLines: [1, 2] }]);
add('select-lines-clamped', 20, 5, 10, [{ write: lines(12) }, { selectLines: [-3, 100] }]);
add('set-selection-one-row', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [2, 0, 5] }]);
add('set-selection-exact-rows', 10, 5, 10, [{ write: 'abcdefghijklmnopqrstuvwxyz' }, { setSelection: [3, 0, 17] }]);
add('set-selection-past-a-row', 10, 5, 10, [{ write: 'abcdefghijklmnopqrstuvwxyz' }, { setSelection: [3, 0, 15] }]);
add('set-selection-twice-the-same', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [2, 0, 5] }, { setSelection: [2, 0, 5] }]);

// ---- 9. trimmed off the top ---------------------------------------------------------
add('trim-moves-the-selection', 20, 5, 5, [{ write: lines(10) }, { selectLines: [4, 5] }, { write: lines(3, 'more-') }]);
add('trim-drops-the-selection', 20, 5, 5, [{ write: lines(10) }, { selectLines: [4, 5] }, { write: lines(3, 'more-') },
  { write: lines(10, 'again-') }]);
add('trim-only-the-start', 20, 5, 5, [{ write: lines(10) }, { selectLines: [1, 6] }, { write: lines(3, 'more-') }]);
add('trim-a-drag-in-the-scrollback', 20, 5, 5, [{ write: lines(10) }, { scroll: -5 }, press(2, 1), move(3, 3, 35), REL,
  { write: lines(2, 'x-') }]);

// ---- 10. when the selection goes ---------------------------------------------------
add('clear-on-user-input', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] }, { userInput: true }]);
add('clear-on-user-input-without-a-selection', 20, 5, 10, [{ write: 'hello world' }, { userInput: true }]);
add('keep-on-a-new-column-count', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] }, { resize: [25, 5] }]);
add('clear-on-a-new-row-count', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] }, { resize: [20, 6] }]);
// phase 5: the buffer rewraps on a new column count. Upstream keeps the coordinates
// (SelectionService.ts:158-162), so the selected text changes; a trim by the reflow
// moves the selection up (its onTrim listener).
add('reflow-narrow-keeps-coords', 20, 5, 10, [{ write: 'abcdefghijklmnopqrst0123456789\r\n$ ' }, { setSelection: [2, 0, 8] },
  { resize: [10, 5] }]);
add('reflow-trim-shifts', 20, 5, 2, [{ write: lines(5, 'long-line-number-') + '$ ' }, { selectLines: [3, 4] }, { resize: [10, 5] }]);
add('reflow-wider', 10, 5, 10, [{ write: 'abcdefghijklmnopqrstuvwxy\r\n$ ' }, { setSelection: [3, 1, 6] }, { resize: [20, 5] }]);
add('reflow-rows-too', 20, 5, 10, [{ write: 'abcdefghijklmnopqrst0123456789\r\n$ ' }, { setSelection: [2, 0, 8] }, { resize: [10, 6] }]);
add('clear-on-the-alternate-screen', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] }, { write: '\x1b[?1049h' },
  { write: 'alt' }, { setSelection: [0, 0, 2] }, { write: '\x1b[?1049l' }]);
add('clear-on-ris', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] }, { write: '\x1bc' }]);
add('clear-when-the-program-takes-the-mouse', 20, 5, 10, [{ write: 'hello world' }, ...click(0, 0, 1), move(4, 0, 5), REL,
  press(2, 0, { enabled: false })]);
add('clear-then-enable-again', 20, 5, 10, [{ write: 'hello world' }, press(2, 0, { enabled: false }), REL,
  press(1, 0, { enabled: true }), move(5, 0, 5), REL]);

// ---- 11. the selected text ----------------------------------------------------------
add('text-nbsp', 20, 5, 10, [{ write: 'a' + NBSP + 'b' + NBSP + NBSP + 'c' }, { setSelection: [0, 0, 6] }]);
add('text-trailing-spaces', 20, 5, 10, [{ write: 'abc   \r\ndef  \r\nghi' }, { selectLines: [0, 2] }]);
add('text-trailing-written-spaces-mid', 20, 5, 10, [{ write: 'abc   x' }, { setSelection: [0, 0, 5] }]);
add('text-wrapped-rows-joined', 10, 5, 10, [{ write: 'abcdefghijklmnopqrstuvwxy\r\nnext' }, { selectLines: [0, 3] }]);
add('text-half-first-and-last', 20, 5, 10, [{ write: 'first row\r\nsecond row\r\nthird row' }, press(6, 0), move(3, 2, 25), REL]);
add('text-wide-in-the-middle', 20, 5, 10, [{ write: 'ab中文cd\r\nx\u{1F600}y' }, press(1, 0), move(3, 1, 15), REL]);
add('text-to-the-end-of-a-row', 10, 5, 10, [{ write: 'abcdefghij\r\nklm' }, press(2, 0), move(10, 0, 5), REL]);
add('text-last-row-to-the-edge', 10, 5, 10, [{ write: 'abcdefghij\r\nklmnopqrst' }, press(2, 0), move(10, 1, 15), REL]);
add('text-combining-and-emoji', 20, 5, 10, [{ write: 'café \u{1F600}‍\u{1F600} z' }, { setSelection: [0, 0, 12] }]);
add('text-wrapped-last-row', 10, 5, 10, [{ write: 'abcdefghijklmn\r\nzz' }, press(3, 0), move(2, 1, 15), REL]);

// ---- 12. right button ------------------------------------------------------------------
add('right-press-keeps-a-selection', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] },
  press(8, 0, { button: 2 }), REL]);
add('right-press-without-a-selection', 20, 5, 10, [{ write: 'hello world' }, press(8, 0, { button: 2 }), REL]);
add('middle-press', 20, 5, 10, [{ write: 'hello world' }, { setSelection: [0, 0, 5] }, press(8, 0, { button: 1 }), REL]);
add('right-click-selects-a-word', 20, 5, 10, [{ write: 'foo bar baz' }, { rightClick: { at: [5, 0] } }]);
add('right-click-outside-a-selection', 20, 5, 10, [{ write: 'foo bar baz' }, { setSelection: [0, 0, 3] },
  { rightClick: { at: [9, 0] } }]);
add('right-click-inside-a-selection', 20, 5, 10, [{ write: 'foo bar baz' }, { setSelection: [0, 0, 7] },
  { rightClick: { at: [5, 0] } }]);
add('right-click-on-whitespace', 20, 5, 10, [{ write: 'foo    bar' }, { rightClick: { at: [5, 0] } }]);
add('right-click-on-a-link', 20, 5, 10, [{ write: 'see http://a.com/x ok' }, { link: [5, 1, 18, 1] },
  { rightClick: { at: [8, 0] } }]);

// ---- 13. links ----------------------------------------------------------------------
add('double-click-a-link', 30, 5, 10, [{ write: '(see http://a.com/x?y=1)' }, { link: [6, 1, 23, 1] }, ...click(20, 0, 2)]);
add('double-click-a-wrapped-link', 10, 5, 10, [{ write: 'see http://a.com/abcdef ok' }, { link: [5, 1, 3, 3] },
  ...click(2, 1, 2), { link: null }, ...click(2, 1, 2)]);
add('double-click-a-link-then-drag', 30, 5, 10, [{ write: 'go http://a.com/x now or never' }, { link: [4, 1, 17, 1] },
  press(8, 0, { detail: 2 }), { link: null }, move(24, 0, 5), REL]);

// ---- 14. how many change events ----------------------------------------------------
add('events-click-without-a-selection', 20, 5, 10, [{ write: 'hello' }, press(1, 0), REL]);
add('events-click-with-a-selection', 20, 5, 10, [{ write: 'hello' }, { setSelection: [0, 0, 3] }, press(1, 0), REL]);
add('events-release-changed', 20, 5, 10, [{ write: 'hello' }, press(1, 0), move(3, 0, 5), REL]);
add('events-release-unchanged', 20, 5, 10, [{ write: 'hello' }, press(1, 0), move(3, 0, 5), REL, { setSelection: [1, 0, 2] },
  { setSelection: [1, 0, 2] }]);
add('events-clear-without-a-selection', 20, 5, 10, [{ write: 'hello' }, { clear: true }]);
add('events-select-all-twice', 20, 5, 10, [{ write: 'hello' }, { selectAll: true }, { selectAll: true }, { clear: true }]);
add('events-repeated-drags', 20, 5, 10, [{ write: 'hello world' }, press(1, 0), move(3, 0, 5), REL, press(1, 0), move(3, 0, 5),
  REL, press(2, 0), REL]);

module.exports = { CASES };
