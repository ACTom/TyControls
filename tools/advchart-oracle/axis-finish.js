/*
Upstream's own answers for the AXIS'S FINISHING TOUCHES -- roadmap B6,
batch 101: the arrows at the ends of the axis line (axisLine.symbol,
symbolSize, symbolOffset), the name cut to nameTruncate.maxWidth, the split
lines' and split areas' colour lists and how a split area keeps its colours
from one render to the next, the category interval's hysteresis cache
(calculateCategoryInterval's lastAutoInterval / lastTickCount / axisExtent),
and the shadow an axis pointer draws on a value or time axis.

Runs the real ECharts 6.1 development build (D:/Projects/echarts, or
ECHARTS_DIST) in node's server-side mode, SVG renderer, `animation: false`,
measuring every string with zrender's width table (the TZrSsrMeasurer of the
Pascal tests). Every case is 600 x 400 with the default grid unless it says
otherwise.

  node tools/advchart-oracle/axis-finish.js

writes tests/fixtures/advchart-axis-finish.json (ORACLE_OUT overrides).

-----------------------------------------------------------------------------
Numbers that are positions are the 16 hex digits of the IEEE double
(big-endian, lowercase); a readable twin sits beside the ones a reader looks
at. Counts, flags, strings and option values are plain JSON.

Top level: source, version, notes[], cases[], guards[].

A case: id, group ('arrow' | 'truncate' | 'colour' | 'sequence' |
  'interval' | 'pointer'), note, W, H, option (as run, animation false),
  steps[] (sequence and interval cases: what is done after the first render,
  each {type 'zoom' (payload: a dataZoom action) | 'merge' (option: a
  setOption merge) | 'notMerge' (option: a whole option, notMerge) |
  'resize' (W, H)}), probes[] (pointer cases: [x, y] integer pixels
  dispatched as updateAxisPointer), renders[] (one after the first render and
  one after each step).

A render: rect (the grid rect, hex + rectText), axes[] (every axis of grid 0:
  x axes, then y axes, by component index):
    dim, index, type, inverse, shown (shouldAxisShow)
    frame {x, y, rotation} hex: the AxisBuilder's transform group, the frame
      the arrows are placed in; extent [2] hex: axis.getExtent() (local px)
    arrows[] (arrow and sequence cases): each symbol element of the axis
      line, in creation order: end (0 the start, 1 the end -- from the
      transcription), type (shape.symbolType), x, y, rotation hex, shape
      {x, y, width, height} hex, fill (the style's fill; the colour is the
      skin's in the port and is not compared), z2
    name (truncate cases): null or {lines[] (the TSpan texts drawn),
      truncated (Text.isTruncated), x, y, rotation hex (the element's own,
      after the moves), box {x, y, width, height} hex (Text.getBoundingRect,
      local)}
    splitLines[] (colour and sequence cases): {value (the tick value as
      upstream keys it: a string), stroke, ci (the colour list index the
      transcription gives)} in creation order
    splitAreas[]: {value, fill, ci, shape {x, y, width, height} hex}
    colours: {line: the splitLine.lineStyle.color the model holds (a string
      or a list), area: splitArea.areaStyle.color likewise}
    interval (interval cases, category axes): {count (scale.count()), raw
      (the interval calculateCategoryInterval computes on the final rect with
      no cache), used (the one the labels were built with), held (the cache
      answered), cache {last, count, e0, e1} (the axis model's store after the
      render; e0 / e1 hex), shown[] (the ordinals of the labels drawn)}
  pointer (pointer cases): per probe {x, y, axisDim (the axis the pointer
    element belongs to, or null), type 'rect' | 'line' | null, shape [4] hex
    (rect: x, y, width, height; line: x1, y1, x2, y2), series [indices of
    seriesDataIndices on that axis], band hex (the band width the
    transcription gives, rect only)}

Guards (each a transcription of upstream's recipe, compared with Object.is on
every record it covers, plus named facts):
  arrows      the AxisBuilder recipe: arrows[i] on 'none' / null skipped, a
              string for both ends, a number size for both sides,
              normalizeSymbolOffset (percent of symbolSize[0] for the start,
              symbolSize[1] for the end), rotation = r +- PI/2, the start at
              the smaller end of the local extent, x/y = pt + r * cos / sin.
  truncate    parsePlainText + truncateSingleLine over the name lines with
              width = nameTruncate.maxWidth and the model's ellipsis.
  colours     splitLine: lineCount over the drawn lines mod the list length;
              splitArea: the cache of the previous render
              ((cIndex + (len - 1) * i) % len from the first tick it knows),
              then +1 per band; len = the model value's .length.
  interval    calculateCategoryIntervalDealCache: the last interval kept iff
              |last - raw| <= 1, |lastCount - count| <= 1, last > raw and the
              extent unchanged; the store written only when it is not kept.
  pointer     calcAxisPointerShadowBandWidth: a category band max(1, w); on a
              number axis the largest positive min gap of the stat records
              holding a hovered series (any axis), pxSpan / span * gap, 0.8 of
              the axis for a lone value, else 1; ends clamped to the axis;
              makeRectShape across the other axis' raw global extent.
Two in-process runs must write the same bytes.
*/
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = process.env.ORACLE_OUT || path.join(ROOT, 'tests', 'fixtures', 'advchart-axis-finish.json');

class OracleError extends Error {}
function must(cond, msg) {
  if (!cond) throw new OracleError(msg);
}
const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new OracleError('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));
const clone = o => JSON.parse(JSON.stringify(o));
const hexRect = r => ({ x: hex(r.x), y: hex(r.y), width: hex(r.width), height: hex(r.height) });
const same = (a, b) => Object.is(a, b);

// ---------------------------------------------------------------------------
// the interval hook: every calculateCategoryInterval call, with the raw
// interval (the same axis asked again in the estimate kind, which neither
// reads nor writes the cache) and the store before and after
// ---------------------------------------------------------------------------
let RUN = null;
function storeOf(model) {
  for (const k of Object.keys(model)) {
    if (k.indexOf('__ec_inner') === 0 && model[k] && typeof model[k] === 'object' && 'lastAutoInterval' in model[k]) return model[k];
  }
  return null;
}
const snap = s => (s ? { last: s.lastAutoInterval, count: s.lastTickCount, e0: s.axisExtent0, e1: s.axisExtent1 } : null);
{
  const warm = echarts.init(null, null, { renderer: 'svg', ssr: true, width: 200, height: 200 });
  warm.setOption({ animation: false, xAxis: { type: 'category', data: ['a', 'b'] }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [1, 2] }] });
  warm.renderToSVGString();
  let proto = warm.getModel().getComponent('xAxis', 0).axis;
  while (proto && !Object.prototype.hasOwnProperty.call(proto, 'calculateCategoryInterval')) proto = Object.getPrototypeOf(proto);
  must(proto, 'no calculateCategoryInterval on the axis prototype chain');
  warm.dispose();
  const cci = proto.calculateCategoryInterval;
  proto.calculateCategoryInterval = function (ctx) {
    if (!RUN) return cci.apply(this, arguments);
    const before = snap(storeOf(this.model));
    const raw = cci.call(this, { kind: 1, out: { noPxChangeTryDetermine: [] } });
    const r = cci.apply(this, arguments);
    RUN.push({ axis: this, kind: ctx.kind, raw, r, before, after: snap(storeOf(this.model)),
      count: this.scale.count(), ext: this.getExtent().slice() });
    return r;
  };
}

function walk(e, f) {
  f(e);
  if (e.childrenRef) e.childrenRef().forEach(x => walk(x, f));
}

// ---------------------------------------------------------------------------
// the cases
// ---------------------------------------------------------------------------
const CATS = n => Array.from({ length: n }, (_, i) => 'Item ' + i);
const BAR = n => Array.from({ length: n }, (_, i) => (i * 7) % 23 + 1);
const C5 = ['a', 'b', 'c', 'd', 'e'];
const catBar = (x, y, extra) => Object.assign({ xAxis: Object.assign({ type: 'category', data: C5 }, x || {}),
  yAxis: Object.assign({ type: 'value' }, y || {}), series: [{ type: 'bar', data: [5, -3, 8, 2, 6] }] }, extra || {});

const CASES = [];
const add = (group, id, note, option, more) => CASES.push(Object.assign({ group, id, note, W: 600, H: 400, option }, more || {}));

// ---- arrows
add('arrow', 'arrow-x-both', 'a category x axis, symbol "arrow" for both ends at the default size',
  catBar({ axisLine: { symbol: 'arrow' } }, null, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-x-end-number-size', "['none', 'arrow'], symbolSize 20 (a number), symbolOffset 5",
  catBar({ axisLine: { symbol: ['none', 'arrow'], symbolSize: 20, symbolOffset: 5 } }, null, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-x-offset-pair', "symbolOffset [-5, '50%'] over symbolSize [8, 12]: the end's percent is of the height",
  catBar({ axisLine: { symbol: ['arrow', 'arrow'], symbolSize: [8, 12], symbolOffset: [-5, '50%'] } }, null, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-x-offset-percent', "symbolOffset '25%' alone over [12, 16]: 3 at the start, 4 at the end",
  catBar({ axisLine: { symbol: 'arrow', symbolSize: [12, 16], symbolOffset: '25%' } }, null, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-x-inverse', "an inverse category x axis, ['arrow', 'circle']: the start is still the left end",
  catBar({ inverse: true, axisLine: { symbol: ['arrow', 'circle'], symbolSize: [10, 14] } }, null, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-y-value', "a value y axis, axisLine.show true, symbol ['arrow', 'arrow']",
  catBar(null, { axisLine: { show: true, symbol: ['arrow', 'arrow'] } }, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-y-inverse', 'an inverse value y axis: the x axis sits on its zero at the top',
  catBar({ axisLine: { symbol: 'arrow' } }, { inverse: true, axisLine: { show: true, symbol: ['arrow', 'triangle'], symbolSize: 12 } }, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-y-right-offset', 'a value y axis on the right, offset 10, symbolOffset [3, -2]',
  catBar(null, { position: 'right', offset: 10, axisLine: { show: true, symbol: 'arrow', symbolOffset: [3, -2] } }, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-x-top', 'an x axis on top', catBar({ position: 'top', axisLine: { symbol: ['rect', 'arrow'], symbolSize: [6, 10] } }, null, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }));
add('arrow', 'arrow-x-onzero', 'negative data: the x axis on the zero of the y axis',
  catBar({ axisLine: { symbol: ['none', 'arrow'], symbolSize: [10, 18] } }));
add('arrow', 'arrow-none', "symbol 'none': no arrow at either end", catBar({ axisLine: { symbol: 'none' } }));
add('arrow', 'arrow-line-hidden', 'axisLine.show false: no arrows either', catBar({ axisLine: { show: false, symbol: 'arrow' } }));
add('arrow', 'arrow-axis-hidden', 'axis show false: nothing at all', catBar({ show: false, axisLine: { symbol: 'arrow' } }));
add('arrow', 'arrow-value-x', 'two value axes, arrows on both',
  { xAxis: { type: 'value', axisLine: { show: true, symbol: ['circle', 'arrow'], symbolSize: [9, 9], symbolOffset: ['10%', 0] } },
    yAxis: { type: 'value', axisLine: { show: true, symbol: 'arrow' } },
    series: [{ type: 'scatter', data: [[1, 2], [5, 7], [9, 4]] }] });

// ---- nameTruncate
const nameCase = (x, y) => catBar(x, y, { series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] });
add('truncate', 'name-end-x', "an end name on x cut to 50: 'A very ...'",
  nameCase({ name: 'A very long axis name here', nameTruncate: { maxWidth: 50 } }));
add('truncate', 'name-start-x', 'a start name cut to 30, ellipsis "~"',
  nameCase({ name: 'Starting name', nameLocation: 'start', nameTruncate: { maxWidth: 30, ellipsis: '~' } }));
add('truncate', 'name-middle-y', 'a middle name on y cut to 40, ellipsis "~", turned with the axis',
  nameCase(null, { name: 'Another long name', nameLocation: 'middle', nameTruncate: { maxWidth: 40, ellipsis: '~' } }));
add('truncate', 'name-middle-x-rotate', 'a middle name on x turned 30 degrees, cut to 60, clear of the labels (a turned name the labels push is moved by an OBB the port does not do -- section 72)',
  nameCase({ name: 'Middle rotated name', nameLocation: 'middle', nameGap: 60, nameRotate: 30, nameTruncate: { maxWidth: 60 } }));
add('truncate', 'name-end-y-rotate', 'an end name on y at nameRotate 0, cut to 25',
  nameCase(null, { name: 'Value axis name', nameRotate: 0, nameTruncate: { maxWidth: 25 } }));
add('truncate', 'name-end-y-rotate-90', 'an end name on y at nameRotate 90, cut to 35',
  nameCase(null, { name: 'Upright value name', nameRotate: 90, nameTruncate: { maxWidth: 35 } }));
add('truncate', 'name-multiline', 'two lines, each cut on its own to 40',
  nameCase({ name: 'First long line\nshort', nameLocation: 'middle', nameGap: 28, nameTruncate: { maxWidth: 40 } }));
add('truncate', 'name-zero-width', 'maxWidth 0: nothing left', nameCase({ name: 'Gone', nameTruncate: { maxWidth: 0 } }));
add('truncate', 'name-wide-enough', 'maxWidth wider than the name: not cut', nameCase({ name: 'Short', nameTruncate: { maxWidth: 200 } }));
add('truncate', 'name-empty-ellipsis', 'an empty ellipsis: a bare cut', nameCase({ name: 'Bare cut name', nameTruncate: { maxWidth: 40, ellipsis: '' } }));
add('truncate', 'name-no-maxwidth', 'nameTruncate without maxWidth: not cut', nameCase({ name: 'A whole long name stays', nameTruncate: { ellipsis: '!' } }));
add('truncate', 'name-block-padding', 'a name in a box (padding, a background): cut at the same width inside its block',
  nameCase({ name: 'Boxed axis name', nameTextStyle: { padding: [2, 4], backgroundColor: '#eeeeee' }, nameTruncate: { maxWidth: 50 } }));
add('truncate', 'name-wide-ellipsis', 'an ellipsis wider than the room is dropped', nameCase({ name: 'Ellipsis dropped', nameTruncate: { maxWidth: 12, ellipsis: '.....' } }));

// ---- colours, one render
add('colour', 'col-cat-lines', 'a category axis, three split line colours, showMinLine false: the count starts at the first drawn line',
  catBar({ splitLine: { show: true, showMinLine: false, lineStyle: { color: ['#f00', '#0f0', '#00f'] } } }));
add('colour', 'col-cat-areas', 'a category axis, three split area colours',
  catBar({ splitArea: { show: true, areaStyle: { color: ['#111', '#222', '#333'] } } }));
add('colour', 'col-value-both', 'a value y axis, two line colours, two area colours',
  catBar(null, { splitLine: { lineStyle: { color: ['#aa0000', '#00aa00'] } }, splitArea: { show: true, areaStyle: { color: ['rgba(1,2,3,0.5)', '#abcdef'] } } }));
add('colour', 'col-area-string', 'a single area colour as a string: every band in it',
  catBar(null, { splitArea: { show: true, areaStyle: { color: '#123456' } } }));
add('colour', 'col-line-string', 'a single line colour as a string',
  catBar(null, { splitLine: { lineStyle: { color: '#654321' } }, splitArea: { show: true } }));
add('colour', 'col-default-area', "the default split area colours, the skin's in the port: compared by index",
  catBar({ splitArea: { show: true } }, { splitArea: { show: true } }));
add('colour', 'col-cat-interval', 'split lines and areas on their own interval (1) on a category axis',
  { xAxis: { type: 'category', data: CATS(9), splitLine: { show: true, interval: 1, lineStyle: { color: ['#f00', '#0f0'] } },
    splitArea: { show: true, interval: 2, areaStyle: { color: ['#111', '#222', '#333'] } } },
  yAxis: { type: 'value' }, series: [{ type: 'bar', data: BAR(9) }] });
add('colour', 'col-max-line-off', 'showMaxLine false with two colours',
  catBar(null, { splitLine: { showMaxLine: false, lineStyle: { color: ['#f00', '#0f0'] } } }));

// ---- colours across renders
const zoomCat = (n, colours) => ({
  dataZoom: [{ type: 'inside', xAxisIndex: 0 }],
  xAxis: { type: 'category', data: CATS(n), splitArea: { show: true, areaStyle: { color: colours } },
    splitLine: { show: true, lineStyle: { color: ['#f00', '#0f0'] } } },
  yAxis: { type: 'value' }, series: [{ type: 'bar', data: BAR(n) }],
});
add('sequence', 'seq-cat-zoom', 'a category window narrowed and widened again: each band keeps its colour',
  zoomCat(12, ['#111', '#222', '#333']), { steps: [
    { type: 'zoom', payload: { type: 'dataZoom', start: 25, end: 100 } },
    { type: 'zoom', payload: { type: 'dataZoom', start: 50, end: 100 } },
    { type: 'zoom', payload: { type: 'dataZoom', start: 10, end: 90 } },
    { type: 'zoom', payload: { type: 'dataZoom', start: 0, end: 100 } }] });
add('sequence', 'seq-default-zoom', "the default colours through a zoom: compared by index",
  { dataZoom: [{ type: 'inside', xAxisIndex: 0 }], xAxis: { type: 'category', data: CATS(10), splitArea: { show: true } },
    yAxis: { type: 'value' }, series: [{ type: 'bar', data: BAR(10) }] },
  { steps: [{ type: 'zoom', payload: { type: 'dataZoom', start: 10, end: 100 } }, { type: 'zoom', payload: { type: 'dataZoom', start: 30, end: 100 } }] });
add('sequence', 'seq-value-zoom', 'a value y axis zoomed: the ticks change value and the colours follow them',
  { dataZoom: [{ type: 'inside', yAxisIndex: 0, filterMode: 'none' }], xAxis: { type: 'category', data: C5 },
    yAxis: { type: 'value', splitArea: { show: true, areaStyle: { color: ['#111', '#222', '#333'] } } },
    series: [{ type: 'bar', data: [10, 40, 25, 80, 60] }] },
  { steps: [{ type: 'zoom', payload: { type: 'dataZoom', start: 30, end: 100 } }, { type: 'zoom', payload: { type: 'dataZoom', start: 30, end: 70 } }] });
add('sequence', 'seq-merge-keeps', 'a merge keeps the view and its colours; a notMerge starts over',
  zoomCat(8, ['#111', '#222', '#333']), { steps: [
    { type: 'zoom', payload: { type: 'dataZoom', start: 30, end: 100 } },
    { type: 'merge', option: { yAxis: { name: 'v' } } },
    { type: 'notMerge', option: Object.assign(zoomCat(8, ['#111', '#222', '#333']), { dataZoom: [{ type: 'inside', xAxisIndex: 0, start: 30, end: 100 }] }) }] });
add('sequence', 'seq-resize', 'a resize keeps the colours',
  zoomCat(8, ['#111', '#222', '#333']), { steps: [
    { type: 'zoom', payload: { type: 'dataZoom', start: 30, end: 100 } },
    { type: 'resize', W: 500, H: 380 }] });
add('sequence', 'seq-colour-count-changes', 'a merge from three colours to two: the cache index taken mod the new length',
  zoomCat(8, ['#111', '#222', '#333']), { steps: [
    { type: 'zoom', payload: { type: 'dataZoom', start: 30, end: 100 } },
    { type: 'merge', option: { xAxis: { splitArea: { areaStyle: { color: ['#aaa', '#bbb'] } } } } }] });

// ---- the interval's hysteresis
const longCat = (n, extra) => Object.assign({ dataZoom: [{ type: 'inside', xAxisIndex: 0 }],
  xAxis: { type: 'category', data: CATS(n) }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: BAR(n) }] }, extra || {});
const zoomTo = s => ({ type: 'zoom', payload: { type: 'dataZoom', start: s, end: 100 } });
add('interval', 'iv-zoom-hold', 'sixty categories narrowed a step at a time: at 51 the raw interval drops to 5 and 6 is kept; at 50 it lets go',
  longCat(60), { steps: [zoomTo(13), zoomTo(14), zoomTo(15), zoomTo(16), zoomTo(17), zoomTo(18)] });
add('interval', 'iv-zoom-out', 'widening again: a rise is never held',
  longCat(60), { steps: [zoomTo(18), zoomTo(15), zoomTo(14), zoomTo(0)] });
add('interval', 'iv-merge-data', 'one category fewer by a merge holds the interval; two fewer does not',
  longCat(52, { dataZoom: [] }), { steps: [
    { type: 'merge', option: { xAxis: { data: CATS(51) }, series: [{ data: BAR(51) }] } },
    { type: 'merge', option: { xAxis: { data: CATS(50) }, series: [{ data: BAR(50) }] } }] });
add('interval', 'iv-resize', 'a resize that drops the interval is never held: the extent changed',
  longCat(52, { dataZoom: [] }), { steps: [{ type: 'resize', W: 620, H: 400 }, { type: 'resize', W: 600, H: 400 }] });
add('interval', 'iv-notmerge', 'a notMerge is a new axis model: no cache',
  longCat(52, { dataZoom: [] }), { steps: [{ type: 'notMerge', option: longCat(51, { dataZoom: [] }) }] });
add('interval', 'iv-rotated', 'labels turned 45 degrees narrowed past a step',
  longCat(80, { xAxis: { type: 'category', data: CATS(80), axisLabel: { rotate: 45 } } }), {
    steps: [zoomTo(5), zoomTo(10), zoomTo(15), zoomTo(20), zoomTo(25), zoomTo(30), zoomTo(35)] });
add('interval', 'iv-y-category', 'a category y axis narrowed',
  { dataZoom: [{ type: 'inside', yAxisIndex: 0 }], yAxis: { type: 'category', data: CATS(70) }, xAxis: { type: 'value' },
    series: [{ type: 'bar', data: BAR(70) }] }, { steps: [zoomTo(10), zoomTo(20), zoomTo(30), zoomTo(40), zoomTo(45), zoomTo(50)] });

// ---- the pointer's shadow
const SH = { tooltip: { trigger: 'axis', axisPointer: { type: 'shadow' } } };
add('pointer', 'ptr-value-bar', 'two value axes, a bar and a line: the bar hovered has its min gap, the line 1px',
  Object.assign(clone(SH), { xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [[1, 3], [3, 5], [4, 2]] }, { type: 'line', data: [[1, 2], [2, 3]] }] }),
  { probes: [[300, 200], [370, 200], [100, 200], [535, 200]] });
add('pointer', 'ptr-time-bar', 'bars on a time axis',
  Object.assign(clone(SH), { xAxis: { type: 'time' }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [[0, 3], [86400000, 5], [3 * 86400000, 2]] }] }), { probes: [[300, 200], [100, 200], [530, 200]] });
add('pointer', 'ptr-line-only', 'a line on a value axis: 1px',
  Object.assign(clone(SH), { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'line', data: [[1, 3], [3, 5], [4, 2]] }] }),
  { probes: [[300, 200], [95, 200]] });
add('pointer', 'ptr-y-of-x-bars', "the pointer on the y axis of two value axes: the bars' gap is measured on x and used on y",
  Object.assign({ tooltip: { trigger: 'axis', axisPointer: { type: 'shadow', axis: 'y' } } }, { xAxis: { type: 'value' }, yAxis: { type: 'value' },
    series: [{ type: 'bar', data: [[1, 3], [3, 5], [4, 2]] }] }), { probes: [[300, 200], [300, 100]] });
add('pointer', 'ptr-single-bar', 'one bar on a value axis: four fifths of the axis',
  Object.assign(clone(SH), { xAxis: { type: 'value' }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [[2, 3]] }] }),
  { probes: [[300, 200]] });
add('pointer', 'ptr-inverse-value', 'an inverse value x axis and an inverse y',
  Object.assign(clone(SH), { xAxis: { type: 'value', inverse: true }, yAxis: { type: 'value', inverse: true },
    series: [{ type: 'bar', data: [[1, 3], [2, 5], [4, 2]] }] }), { probes: [[300, 200], [520, 200]] });
add('pointer', 'ptr-category-ends', 'a category shadow at the first and last band: clamped to the axis',
  Object.assign(clone(SH), { xAxis: { type: 'category', data: C5 }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }),
  { probes: [[95, 200], [300, 200], [535, 200]] });
add('pointer', 'ptr-category-inverse-y', 'a category shadow against an inverse value axis: the rect starts at the top',
  Object.assign(clone(SH), { xAxis: { type: 'category', data: C5 }, yAxis: { type: 'value', inverse: true }, series: [{ type: 'bar', data: [5, 3, 8, 2, 6] }] }),
  { probes: [[300, 200]] });
add('pointer', 'ptr-category-narrow', 'nine hundred categories on 450px: a band under a pixel is drawn 1px wide (calcBandWidth min 1)',
  Object.assign(clone(SH), { xAxis: { type: 'category', data: CATS(900) }, yAxis: { type: 'value' }, series: [{ type: 'bar', data: BAR(900) }] }),
  { probes: [[300, 200], [91, 200]] });
add('pointer', 'ptr-horizontal-bars', 'horizontal bars, the pointer on the value x axis: no stat on the category base axis, 1px',
  Object.assign({ tooltip: { trigger: 'axis', axisPointer: { type: 'shadow', axis: 'x' } } }, { xAxis: { type: 'value' }, yAxis: { type: 'category', data: ['a', 'b', 'c'] },
    series: [{ type: 'bar', data: [3, 5, 2] }] }), { probes: [[300, 200]] });

// ---------------------------------------------------------------------------
// reading a render
// ---------------------------------------------------------------------------
function axesOf(chart) {
  const cs = chart.getModel().getComponent('grid', 0).coordinateSystem;
  const out = [];
  ['x', 'y'].forEach(dim => cs.getAxes().filter(a => a.dim === dim)
    .sort((a, b) => a.model.componentIndex - b.model.componentIndex).forEach(a => out.push(a)));
  return { cs, axes: out };
}

function sceneOf(chart, axis) {
  const view = chart.getViewOfComponentModel(axis.model);
  const out = { arrows: [], name: null, lines: [], areas: [], labels: [] };
  if (!view) return out;
  const bg = axis.axisBuilder && axis.axisBuilder.group;
  const under = (e, g) => { for (let p = e; p; p = p.parent) if (p === g) return true; return false; };
  walk(view.group, e => {
    const inB = bg && under(e, bg);
    if (inB && e.shape && e.shape.symbolType != null) out.arrows.push(e);
    if (inB && e.anid === 'name') out.name = e;
    let m;
    if (e.anid && inB && (m = /^label_(.*)$/.exec(e.anid)) && !e.ignore && e.style && e.style.text) out.labels.push(Number(m[1]));
    if (e.anid && !inB && (m = /^line_(.*)$/.exec(e.anid))) out.lines.push({ value: m[1], el: e });
    if (e.anid && !inB && (m = /^area_(.*)$/.exec(e.anid))) out.areas.push({ value: m[1], el: e });
  });
  return out;
}

// the arrow recipe (AxisBuilder.ts axisLine), from the frame and the option
function percent(v, all) {
  // numberUtil.parsePercent
  if (typeof v === 'string') {
    if (v.replace(/^\s+|\s+$/g, '').match(/%$/)) return parseFloat(v) / 100 * all;
    return parseFloat(v);
  }
  return v == null ? NaN : +v;
}
function arrowRecipe(axis) {
  const m = axis.model;
  let shown = m.get(['axisLine', 'show']);
  if (shown === 'auto') {
    shown = true;
    // cartesianAxisHelper's axisLineAutoShow: hidden beside a category or
    // time axis
    const raw = axis.axisBuilder._cfg.raw;
    if (raw.axisLineAutoShow != null) shown = !!raw.axisLineAutoShow;
  }
  if (!shown) return [];
  const tg = axis.axisBuilder._transformGroup;
  const ext = axis.getExtent();
  const M = tg.transform;
  const ap = (x, y) => (M ? [M[0] * x + M[2] * y + M[4], M[1] * x + M[3] * y + M[5]] : [x, y]);
  const pt1 = ap(ext[0], 0);
  const pt2 = ap(ext[1], 0);
  const inverse = ext[0] > ext[1];
  let arrows = m.get(['axisLine', 'symbol']);
  if (arrows == null) return [];
  let size = m.get(['axisLine', 'symbolSize']);
  if (typeof arrows === 'string') arrows = [arrows, arrows];
  if (typeof size === 'string' || typeof size === 'number') size = [size, size];
  let off = m.get(['axisLine', 'symbolOffset']) || 0;
  if (!Array.isArray(off)) off = [off, off];
  const o = [percent(off[0], size[0]) || 0, percent(off[1] != null ? off[1] : off[0], size[1]) || 0];
  const rot = tg.rotation;
  const pts = [{ rotate: rot + Math.PI / 2, offset: o[0], r: 0 },
    { rotate: rot - Math.PI / 2, offset: o[1], r: Math.sqrt((pt1[0] - pt2[0]) * (pt1[0] - pt2[0]) + (pt1[1] - pt2[1]) * (pt1[1] - pt2[1])) }];
  const out = [];
  pts.forEach((p, i) => {
    if (arrows[i] === 'none' || arrows[i] == null) return;
    const r = p.r + p.offset;
    const pt = inverse ? pt2 : pt1;
    out.push({ end: i, type: arrows[i], rotation: p.rotate, x: pt[0] + r * Math.cos(rot), y: pt[1] - r * Math.sin(rot),
      w: size[0], h: size[1] });
  });
  return out;
}

// parsePlainText + truncateSingleLine (zrender parseText.ts) for the name
function measureW(font, s) {
  if (s === '') return 0;
  return new echarts.graphic.Text({ style: { text: s, font } }).getBoundingRect().width;
}
function truncRecipe(name, font, maxWidth, ellipsis) {
  const lines = String(name).split('\n');
  if (maxWidth == null) return { lines, truncated: false };
  ellipsis = ellipsis == null ? '...' : ellipsis;
  let container = Math.max(0, maxWidth - 1);
  let content = container;
  let ellW = measureW(font, ellipsis);
  if (ellW > content) { ellipsis = ''; ellW = 0; }
  content = container - ellW;
  let truncated = false;
  const charW = c => measureW(font, c < 128 ? String.fromCharCode(c) : '\u56fd');
  const out = lines.map(line => {
    if (!container) return '';
    let lw = measureW(font, line);
    if (lw <= container) return line;
    for (let j = 0; ; j++) {
      if (lw <= content || j >= 2) { line += ellipsis; break; }
      let sub;
      if (j === 0) {
        let w = 0;
        let i = 0;
        for (const n = line.length; i < n && w < content; i++) w += charW(line.charCodeAt(i));
        sub = i;
      } else sub = lw > 0 ? Math.floor(line.length * content / lw) : 0;
      line = line.substr(0, sub);
      lw = measureW(font, line);
    }
    truncated = true;
    return line;
  });
  return { lines: out, truncated };
}

// the split colours (CartesianAxisView.ts, axisSplitHelper.ts), with this
// generator's own copy of the area cache per axis view
function lineRecipe(colours, count) {
  const list = Array.isArray(colours) ? colours : [colours];
  const out = [];
  for (let i = 0; i < count; i++) out.push(i % list.length);
  return out;
}
function areaRecipe(colours, values, last) {
  const len = colours.length;
  let ci = 0;
  if (last) {
    for (let i = 0; i < values.length; i++) {
      const c = last.get(String(values[i]));
      if (c != null) { ci = (c + (len - 1) * i) % len; break; }
    }
  }
  const next = new Map();
  const out = [];
  for (let i = 1; i < values.length; i++) {
    const v = values[i - 1];
    if (v != null) next.set(String(v), ci);
    out.push(ci);
    ci = (ci + 1) % len;
  }
  return { out, next };
}

// the interval cache recipe
function dealCache(before, raw, count, ext) {
  if (before && before.last != null && before.count != null && Math.abs(before.last - raw) <= 1
    && Math.abs(before.count - count) <= 1 && before.last > raw && before.e0 === ext[0] && before.e1 === ext[1]) {
    return { used: before.last, held: true, after: before };
  }
  return { used: raw, held: false, after: { last: raw, count, e0: ext[0], e1: ext[1] } };
}

// the axis statistics: the largest positive min gap over the stat records
// holding a hovered series -- bars, pictorial bars, candlesticks and boxplots
// on their base axis when it is not a category axis
const STAT_TYPES = ['bar', 'pictorialBar', 'candlestick', 'boxplot'];
function statsFor(ecModel, seriesIdx) {
  const recs = [];
  const seen = new Map();
  ecModel.eachSeries(s => {
    if (STAT_TYPES.indexOf(s.subType) < 0 || !s.coordinateSystem || s.coordinateSystem.type !== 'cartesian2d') return;
    const base = s.coordinateSystem.getBaseAxis();
    if (base.scale.type === 'ordinal') return;
    const key = s.subType + '|' + base.dim + base.index;
    if (!seen.has(key)) { seen.set(key, { axis: base, sers: [] }); recs.push(seen.get(key)); }
    seen.get(key).sers.push(s);
  });
  const res = [];
  recs.forEach(rec => {
    if (!rec.sers.some(s => seriesIdx.indexOf(s.seriesIndex) >= 0)) return;
    const vals = [];
    rec.sers.forEach(s => {
      const d = s.getData();
      const dim = d.mapDimension(rec.axis.dim);
      for (let i = 0; i < d.count(); i++) {
        let v = d.get(dim, i);
        if (rec.axis.scale.type === 'log') v = Math.log(v) / Math.log(rec.axis.scale.base || 10);
        if (isFinite(v)) vals.push(v);
      }
    });
    vals.sort((a, b) => a - b);
    let gap = Infinity;
    let n = 0;
    for (let i = 0; i < vals.length; i++) {
      if (i === 0 || vals[i] !== vals[i - 1]) n++;
      if (i > 0 && vals[i] > vals[i - 1]) gap = Math.min(gap, vals[i] - vals[i - 1]);
    }
    res.push(n === 1 ? 'single' : n === 0 ? null : gap);
  });
  return res;
}
function bandRecipe(axis, seriesIdx, ecModel) {
  const ext = axis.getExtent();
  const px = Math.abs(ext[1] - ext[0]);
  // the MAPPING extent where one is set (containShape widened it), else the
  // effective one: getScaleLinearSpanForMapping
  const se = axis.scale.getExtentUnsafe(1, null) || axis.scale.getExtent();
  let span = se[1] - se[0];
  if (axis.scale.type === 'ordinal') {
    let len = span + (axis.onBand ? 1 : 0);
    if (len === 0) len = 1;
    const w = px / len;
    return isFinite(w) ? Math.max(1, w) : 1;
  }
  if (axis.scale.type === 'log') {
    const b = axis.scale.base || 10;
    span = Math.log(se[1]) / Math.log(b) - Math.log(se[0]) / Math.log(b);
  }
  let only = false;
  let gap = -Infinity;
  statsFor(ecModel, seriesIdx).forEach(g => {
    if (g == null) return;
    if (g === 'single') only = true;
    else if (g > 0) { if (g > gap) gap = g; only = false; }
  });
  let w = NaN;
  if (isFinite(span) && span > 0 && isFinite(gap)) w = px / span * gap;
  else if (only) w = px * 0.8;
  return isFinite(w) ? Math.max(1, w) : 1;
}

function readRender(chart, c, prevAreas, fails) {
  const ecModel = chart.getModel();
  const { cs, axes } = axesOf(chart);
  const rect = cs.getRect();
  const rec = { rect: hexRect(rect), rectText: { x: text(rect.x), y: text(rect.y), width: text(rect.width), height: text(rect.height) }, axes: [] };
  axes.forEach(axis => {
    const m = axis.model;
    const key = axis.dim + m.componentIndex;
    const shown = !!m.get('show');
    const r = { dim: axis.dim, index: m.componentIndex, type: axis.type, inverse: !!axis.inverse, shown };
    rec.axes.push(r);
    if (!shown || !axis.axisBuilder) return;
    const tg = axis.axisBuilder._transformGroup;
    r.frame = { x: hex(tg.x), y: hex(tg.y), rotation: hex(tg.rotation) };
    r.extent = axis.getExtent().map(hex);
    const sc = sceneOf(chart, axis);
    if (c.group === 'arrow' || c.group === 'sequence') {
      const want = arrowRecipe(axis);
      if (want.length !== sc.arrows.length) fails.push(key + ': ' + sc.arrows.length + ' arrows, the recipe gives ' + want.length);
      r.arrows = sc.arrows.map((e, i) => {
        const w = want[i] || {};
        const ok = same(e.x, w.x) && same(e.y, w.y) && same(e.rotation, w.rotation) && e.shape.symbolType === w.type
          && same(e.shape.width, w.w) && same(e.shape.height, w.h) && same(e.shape.x, -w.w / 2) && same(e.shape.y, -w.h / 2);
        if (!ok) fails.push(key + ' arrow ' + i + ': ' + JSON.stringify([e.x, e.y, e.rotation, e.shape]) + ', the recipe gives ' + JSON.stringify(w));
        return { end: w.end, type: e.shape.symbolType, x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation),
          xText: text(e.x), yText: text(e.y),
          shape: { x: hex(e.shape.x), y: hex(e.shape.y), width: hex(e.shape.width), height: hex(e.shape.height) },
          fill: e.style.fill == null ? null : e.style.fill, z2: e.z2 };
      });
    }
    if (c.group === 'truncate') {
      const e = sc.name;
      if (!e) r.name = null;
      else {
        const spans = [];
        walk(e, x => { if (x !== e && x.style && typeof x.style.text === 'string' && x.type === 'tspan') spans.push(x.style.text); });
        const t = m.get('nameTruncate', true) || {};
        const want = truncRecipe(m.get('name'), e.style.font, t.maxWidth, t.ellipsis);
        const plain = want.lines.filter(s => s !== '');
        const got = spans.filter(s => s !== '');
        if (JSON.stringify(plain) !== JSON.stringify(got) || want.truncated !== !!e.isTruncated) {
          fails.push(key + ' name: ' + JSON.stringify(spans) + ' ' + e.isTruncated + ', the recipe gives ' + JSON.stringify(want));
        }
        const b = e.getBoundingRect();
        r.name = { lines: want.lines, truncated: !!e.isTruncated, x: hex(e.x), y: hex(e.y), rotation: hex(e.rotation),
          xText: text(e.x), yText: text(e.y), rotationText: text(e.rotation),
          box: hexRect(b), boxText: { x: text(b.x), y: text(b.y), width: text(b.width), height: text(b.height) } };
      }
    }
    if (c.group === 'colour' || c.group === 'sequence') {
      const lc = m.get(['splitLine', 'lineStyle', 'color']);
      const ac = m.get(['splitArea', 'areaStyle', 'color']);
      r.colours = { line: lc, area: ac };
      const lci = lineRecipe(lc, sc.lines.length);
      const llist = Array.isArray(lc) ? lc : [lc];
      r.splitLines = sc.lines.map((l, i) => {
        if (l.el.style.stroke !== llist[lci[i]]) fails.push(key + ' line ' + l.value + ': ' + l.el.style.stroke + ', the recipe gives ' + llist[lci[i]]);
        return { value: l.value, stroke: l.el.style.stroke, ci: lci[i] };
      });
      const prevKey = key;
      const values = sc.areas.map(a => a.value);
      // the area cache: the recipe sees the values of the ticks, which are
      // the areas' own values plus the closing tick the scene does not name
      const ticks = axis.getTicksCoords({ tickModel: m.getModel('splitArea'), breakTicks: 'none', pruneByBreak: 'preserve_extent_bound' })
        .map(t => t.tickValue);
      const ar = areaRecipe(ac, ticks, prevAreas.get(prevKey));
      if (m.get(['splitArea', 'show'])) prevAreas.set(prevKey, ar.next);
      const alist = Array.isArray(ac) ? ac : [ac];
      r.splitAreas = sc.areas.map((a, i) => {
        const fill = a.el.style.fill;
        const want = Array.isArray(ac) ? alist[ar.out[i]] : ac;
        if (fill !== want || String(ticks[i]) !== a.value) fails.push(key + ' area ' + a.value + ': ' + fill + ', the recipe gives ' + want + ' at ' + ticks[i]);
        const s = a.el.shape;
        return { value: a.value, fill, ci: ar.out[i], shape: hexRect(s) };
      });
      must(values.length === r.splitAreas.length, 'area count');
    }
    if (c.group === 'interval' && axis.type === 'category') {
      const calls = (RUN || []).filter(q => q.axis === axis);
      const store = snap(storeOf(m));
      const count = axis.scale.count();
      const ext = axis.getExtent();
      // the last call made in the determine kind is the answer; an estimate
      // reused whole made none
      const det = calls.filter(q => q.kind === 2);
      const est = calls.filter(q => q.kind === 1);
      const last = det.length ? det[det.length - 1] : est[est.length - 1];
      must(last, c.id + ': no interval call on ' + key);
      const raw = last.raw;
      // the recipe from the store as the render found it
      const first = calls[0];
      const want = dealCache(first.before, raw, count, ext);
      if (!same(want.used, last.r) && !(det.length === 0 && same(raw, last.r))) {
        fails.push(key + ': interval ' + last.r + ', the recipe gives ' + want.used + ' (raw ' + raw + ')');
      }
      const wa = want.after;
      if (!store || !same(store.last, wa.last) || !same(store.count, wa.count) || !same(store.e0, wa.e0) || !same(store.e1, wa.e1)) {
        fails.push(key + ': the store ' + JSON.stringify(store) + ', the recipe gives ' + JSON.stringify(wa));
      }
      r.interval = { count, raw, used: last.r, held: want.held,
        cache: store ? { last: store.last, count: store.count, e0: hex(store.e0), e1: hex(store.e1) } : null,
        shown: sc.labels.slice().sort((a, b) => a - b) };
    }
  });
  return rec;
}
function runCase(c) {
  const fails = [];
  const option = clone(c.option);
  option.animation = false;
  // what the case wrote: ECharts marks the objects it is handed
  const written = clone(option);
  const chart = echarts.init(null, null, { renderer: 'svg', ssr: true, width: c.W, height: c.H });
  const prevAreas = new Map();
  const renders = [];
  const once = fn => {
    RUN = [];
    try {
      fn();
      chart.renderToSVGString();
    } finally {
      const r = RUN;
      RUN = r;
    }
    renders.push(readRender(chart, c, prevAreas, fails));
    RUN = null;
  };
  try {
    once(() => chart.setOption(option));
    (c.steps || []).forEach(s => {
      if (s.type === 'zoom') once(() => chart.dispatchAction(clone(s.payload)));
      else if (s.type === 'merge') once(() => chart.setOption(clone(s.option)));
      else if (s.type === 'notMerge') {
        const o = clone(s.option);
        o.animation = false;
        // new views: no colours carried over
        prevAreas.clear();
        once(() => chart.setOption(o, true));
      } else if (s.type === 'resize') once(() => chart.resize({ width: s.W, height: s.H }));
      else throw new OracleError('step ' + s.type);
    });
    let pointer = null;
    if (c.probes) {
      const ecModel = chart.getModel();
      const zr = chart.getZr();
      pointer = c.probes.map(([x, y]) => {
        must(Number.isInteger(x) && Number.isInteger(y), c.id + ': a probe off the integer grid');
        chart.dispatchAction({ type: 'updateAxisPointer', currTrigger: 'mousemove', x, y });
        zr.refreshImmediately();
        const kind = el => String(el.type).toLowerCase();
        const els = zr.storage.getDisplayList(true).filter(el => el.z === 50 && (kind(el) === 'line' || kind(el) === 'rect') && !el.ignore && !el.invisible);
        must(els.length <= 1, c.id + ': ' + els.length + ' pointer elements');
        const el = els[0];
        if (!el) return { x, y, axisDim: null, type: null };
        // which axis: the one whose axisPointer model holds seriesDataIndices
        const { axes } = axesOf(chart);
        let owner = null;
        axes.forEach(a => {
          const info = ecModel.getComponent('axisPointer', 0).coordSysAxesInfo.axesInfo[a.dim + 'Axis' + a.model.componentIndex
            ] || Object.values(ecModel.getComponent('axisPointer', 0).coordSysAxesInfo.axesInfo).find(i => i.axis === a);
          if (info && info.axisPointerModel && info.axisPointerModel.get('status') === 'show') owner = owner || { a, info };
        });
        must(owner, c.id + ': no axis owns the pointer');
        const sdi = (owner.info.axisPointerModel.get('seriesDataIndices') || []).map(q => q.seriesIndex);
        const pr = { x, y, axisDim: owner.a.dim, type: kind(el), series: sdi };
        if (kind(el) === 'rect') {
          const s = el.shape;
          pr.shape = [hex(s.x), hex(s.y), hex(s.width), hex(s.height)];
          pr.shapeText = [s.x, s.y, s.width, s.height].map(text);
          const a = owner.a;
          const bw = bandRecipe(a, sdi, ecModel);
          pr.band = hex(bw);
          pr.bandText = text(bw);
          // the rect recipe from the band, the axis and the other axis
          const other = a.grid.getCartesian({ [a.dim + 'AxisIndex']: a.index }).getOtherAxis(a);
          const oe = other.getGlobalExtent();
          const te = a.getGlobalExtent();
          // CartesianAxisPointer.makeElOption: the value's pixel, clamped
          const value = owner.info.axisPointerModel.get('value');
          const pv = a.toGlobalCoord(a.dataToCoord(value, true));
          const lo = Math.max(Math.min(te[0], te[1]), pv - bw / 2);
          const hi = Math.min(pv + bw / 2, Math.max(te[0], te[1]));
          const want = a.dim === 'x' ? [lo, oe[0], hi - lo, oe[1] - oe[0]] : [oe[0], lo, oe[1] - oe[0], hi - lo];
          const got = [s.x, s.y, s.width, s.height];
          if (!want.every((v, i) => same(v, got[i]))) {
            fails.push(c.id + ' probe ' + x + ',' + y + ': rect ' + pr.shapeText + ', the recipe gives ' + want.map(text));
          }
          pr.pixel = hex(pv);
        } else {
          const s = el.shape;
          pr.shape = [hex(s.x1), hex(s.y1), hex(s.x2), hex(s.y2)];
        }
        return pr;
      });
    }
    return { id: c.id, group: c.group, note: c.note, W: c.W, H: c.H, option: written, steps: c.steps || [], probes: c.probes || [],
      renders, pointer, fails };
  } finally {
    chart.dispose();
  }
}

// ---------------------------------------------------------------------------
// named guards
// ---------------------------------------------------------------------------
function guards(out) {
  const g = [];
  const guard = (name, ok) => g.push({ name, ok: !!ok });
  const cs = id => out.cases.find(q => q.id === id);
  const ax = (id, r, dim) => cs(id).renders[r].axes.find(a => a.dim === dim);
  out.cases.forEach(q => guard(q.id + ': every record matches its recipe', q.fails.length === 0));
  guard("'none' draws no arrow", ax('arrow-none', 0, 'x').arrows.length === 0);
  guard('a hidden axis line draws no arrow', ax('arrow-line-hidden', 0, 'x').arrows.length === 0);
  guard('the end offset in percent is of the height', ax('arrow-x-offset-pair', 0, 'x').arrows.length === 2);
  guard('an inverse axis starts its arrows at the smaller end', ax('arrow-x-inverse', 0, 'x').arrows[0].end === 0);
  guard('a cut name ends in the ellipsis', ax('name-end-x', 0, 'x').name.lines[0].endsWith('...'));
  guard('maxWidth 0 leaves nothing', ax('name-zero-width', 0, 'x').name.lines[0] === '');
  guard('a name that fits is not cut', ax('name-wide-enough', 0, 'x').name.truncated === false);
  guard('the line colour count skips the denied min line', ax('col-cat-lines', 0, 'x').splitLines[0].ci === 0);
  const zr = cs('seq-cat-zoom').renders;
  const colourOf = (r, v) => { const a = ax('seq-cat-zoom', r, 'x').splitAreas.find(q => q.value === v); return a && a.fill; };
  guard('a band keeps its colour through a zoom', colourOf(0, '4') === colourOf(1, '4') && colourOf(0, '6') === colourOf(1, '6')
    && ax('seq-cat-zoom', 1, 'x').splitAreas[0].ci !== 0);
  void zr;
  const nm = cs('seq-merge-keeps').renders;
  guard('a merge keeps the colours, a notMerge starts them over', nm[3].axes[0].splitAreas[0].ci === 0
    && nm[2].axes[0].splitAreas[0].ci === nm[1].axes[0].splitAreas[0].ci && nm[2].axes[0].splitAreas[0].ci !== 0);
  const iv = cs('iv-zoom-hold').renders.map(r => r.axes.find(a => a.dim === 'x').interval);
  guard('the interval is held one step', iv.some(i => i.held));
  guard('a held interval is one more than the raw', iv.filter(i => i.held).every(i => i.used === i.raw + 1));
  const rs = cs('iv-resize').renders.map(r => r.axes.find(a => a.dim === 'x').interval);
  guard('a resize is never held', rs.every(i => !i.held) && rs.some((i, k) => k > 0 && i.raw !== rs[k - 1].raw));
  const md = cs('iv-merge-data').renders.map(r => r.axes.find(a => a.dim === 'x').interval);
  guard('one category fewer by a merge holds', md[1].held);
  guard('a notMerge holds nothing', cs('iv-notmerge').renders.every(r => !r.axes.find(a => a.dim === 'x').interval.held));
  const pv = cs('ptr-value-bar').pointer;
  guard('a hovered line on a value axis gets a 1px shadow', pv.some(p => p.type === 'rect' && p.bandText === '1'));
  guard('a hovered bar on a value axis gets its gap', pv.some(p => p.type === 'rect' && p.bandText !== '1'));
  guard("the y pointer takes the x axis' gap", cs('ptr-y-of-x-bars').pointer.some(p => p.type === 'rect' && p.bandText !== '1'));
  guard('a band under a pixel is drawn 1px wide', cs('ptr-category-narrow').pointer.every(p => p.type === 'rect' && p.bandText === '1'));
  guard('a lone bar takes four fifths of the axis', cs('ptr-single-bar').pointer[0].bandText === String(450 * 0.8));
  return g;
}

function generate() {
  const out = {
    source: DIST, version: echarts.version,
    notes: [
      'arrows: AxisBuilder.ts axisLine; the symbol element is in axisBuilder.group, global coordinates.',
      'name: the Text element after decomposeTransform (x, y, rotation global); lines = TSpan texts.',
      'colours: split lines/areas are the elements anid line_<v> / area_<v> outside the builder group.',
      'interval: the raw interval is the axis asked again in the estimate kind (no cache read or write).',
      'pointer: updateAxisPointer at integer pixels; the element at z 50.',
    ],
    cases: CASES.map(runCase),
  };
  out.guards = guards(out);
  return out;
}

let out1, json1, json2;
try {
  out1 = generate();
  json1 = JSON.stringify(out1, null, 1) + '\n';
  json2 = process.env.ORACLE_ONCE ? json1 : JSON.stringify(generate(), null, 1) + '\n';
} catch (e) {
  console.log(e instanceof OracleError ? 'oracle error: ' + e.message : e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
if (process.env.ORACLE_FORCE) fs.writeFileSync(OUT, json1);
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
out1.cases.forEach(q => q.fails.forEach(f => console.log('  ' + q.id + ': ' + f)));
const deterministic = json1 === json2;
console.log(out1.cases.length + ' cases; ' + (out1.guards.length - bad.length) + '/' + out1.guards.length
  + ' guards; two runs ' + (deterministic ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || !deterministic) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
