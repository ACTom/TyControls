// Upstream's own answers for where a cartesian bar lies along its value axis:
// the base it grows from, the end it reaches, what clipping keeps of it, and
// where its label lands.
//
// Runs the real ECharts 6.1 build (D:/Projects/echarts by default, or
// ECHARTS_DIST) in node's server-side mode, renders once to an SVG string so
// zrender lays the labels out, and reads what zrender is handed to draw. For
// every raw data item of every series:
//
//   class       'drawn'  the item has a graphic element (data.getItemGraphicEl)
//                        and it is not ignored;
//               'hidden' the element exists but is ignored: clipped away whole
//                        (BarView.ts:313). Nothing is painted, no label, no hover;
//               'none'   no element at all: a NaN or non-finite layout
//                        (BarView.ts:253-255).
//   layout      data.getItemLayout(k): unclipped, signed, barMinHeight already
//               applied. Written only when all four numbers are finite (layout
//               null otherwise); layoutText always says what it was, 'NaN' and
//               'Infinity' included.
//   shape       el.shape: after clip (and after the border inset, which the
//               compared cases never trigger), signed as zrender draws it.
//   box         shape normalized the way ctx.rect paints it: l = w < 0 ? x + w
//               : x, r = w < 0 ? x : x + w, and the same for t and b.
//   zeroLength  the shape's extent along the value axis is 0 (-0 counts): the
//               height when the base axis is x, the width when it is y.
//   label       drawn: the class is 'drawn' and the label (getTextContent)
//               exists and is neither ignored nor invisible. word:
//               el.textConfig.position, which is where 'outside' has already
//               been resolved per bar from the clipped rect (BarView.ts
//               1017-1041, 1274-1290). x, y: the label's innerTransformable,
//               align and verticalAlign: el._innerTextDefaultStyle -- all four
//               only when the label is drawn, because zrender never lays out
//               the label of an ignored element (it reads 0, 0 there).
//
// A pictorialBar item's element is a group with no shape of its own. Its shape
// is the transparent rect the view keeps for the label (__pictorialBarRect),
// and floor is the layout's edge on the value axis (layout.y for upright bars,
// layout.x for bars lying down) -- the one number the port's pictorial rect is
// compared on.
//
// Per case: the grid rect (the grid's coordinateSystem.getRect()), the
// cartesian's getArea(), which axis is the base (the same for every series, or
// the run fails), and for each value or log axis its type, whether it is
// inverse, scale.getExtent(), the mapping extent (getExtentUnsafe(MAPPING):
// containShape's widening, null when there is none) and
// rawExtentInfo.makeRenderInfo().startValue (null when nothing asked the axis
// for one). A category axis records only its
// type and inverse. A case with showBackground also records the background
// strips (view._backgroundEls) per item.
//
// A case marked deferred depends on something the port does not do yet (the
// border inset, background strips on gap rows, barMinWidth 0's floor of 1).
// Its upstream answer is recorded all the same, so a later batch only has to
// take the flag off. The compared cases keep the default label text, have no
// borderColor or borderWidth and no showBackground.
//
// Doubles are written as the 16 hex digits of their IEEE-754 bits (big-endian,
// lowercase) with a readable twin beside them (xText beside x, shapeText beside
// shape, ...), because the Pascal JSON reader misparses integer literals above
// 2^63. The readable twin of -0 is '-0'. The option each case ran is written out
// as given; a number in it that JSON.stringify would write as an integer
// literal past 2^63 goes out in exponent form instead.
//
//   node tools/advchart-oracle/bar-geometry.js
'use strict';
const fs = require('fs');
const path = require('path');
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);
// The development build asserts its own invariants and throws where the
// production build carries on; a case that trips one is run through the
// production build instead, which is what a page actually ships, and says so.
const PROD = require(DIST.replace(/echarts\.js$/, 'echarts.min.js'));
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'advchart-bar-geometry.json');

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (typeof v !== 'number') throw new Error('not a number: ' + JSON.stringify(v));
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}
const text = v => (Object.is(v, -0) ? '-0' : String(v));

// An object of Doubles as hex, and its readable twin.
function hexOf(o, keys) {
  const r = {};
  keys.forEach(k => { r[k] = hex(o[k]); });
  return r;
}
function textOf(o, keys) {
  const r = {};
  keys.forEach(k => { r[k] = text(o[k]); });
  return r;
}
const RECT = ['x', 'y', 'width', 'height'];
const BOX = ['l', 't', 'r', 'b'];
const finiteRect = o => RECT.every(k => typeof o[k] === 'number' && Number.isFinite(o[k]));

function init(lib) {
  return lib.init(null, null, { renderer: 'svg', ssr: true, width: 600, height: 400 });
}

const clone = o => JSON.parse(JSON.stringify(o));

function boxOf(s) {
  return {
    l: s.width < 0 ? s.x + s.width : s.x,
    r: s.width < 0 ? s.x : s.x + s.width,
    t: s.height < 0 ? s.y + s.height : s.y,
    b: s.height < 0 ? s.y : s.y + s.height,
  };
}

function axisRecord(axis) {
  const rec = { type: axis.type, inverse: !!axis.inverse };
  if (axis.type === 'category') return rec;
  const extent = axis.scale.getExtent();
  rec.extent = extent.map(hex);
  rec.extentText = extent.map(text);
  // the mapping extent (containShape), what dataToCoord normalizes over; null
  // when the scale has none
  const mapping = axis.scale.getExtentUnsafe(1, null);
  rec.mapping = mapping ? mapping.map(hex) : null;
  rec.mappingText = mapping ? mapping.map(text) : null;
  const info = axis.scale.rawExtentInfo;
  const sv = info ? info.makeRenderInfo().startValue : null;
  if (sv == null) {
    rec.startValue = null;
    rec.startValueText = null;
  } else {
    rec.startValue = hex(sv);
    rec.startValueText = text(sv);
  }
  return rec;
}

function labelRecord(el, host, drawnHost, where) {
  const none = { drawn: false, word: null, x: null, y: null, xText: null, yText: null, align: null, verticalAlign: null };
  if (!host) return none;
  const tc = host.getTextContent && host.getTextContent();
  if (!tc) return none;
  const rec = Object.assign({}, none);
  rec.word = host.textConfig && host.textConfig.position != null ? host.textConfig.position : null;
  rec.drawn = drawnHost && !tc.ignore && !tc.invisible;
  if (rec.drawn) {
    const it = tc.innerTransformable;
    const ds = host._innerTextDefaultStyle;
    if (!ds) throw new Error(where + ': a drawn label with no inner text style');
    if (!Number.isFinite(it.x) || !Number.isFinite(it.y)) throw new Error(where + ': a drawn label at a non-finite point');
    rec.x = hex(it.x);
    rec.y = hex(it.y);
    rec.xText = text(it.x);
    rec.yText = text(it.y);
    rec.align = ds.align == null ? null : ds.align;
    rec.verticalAlign = ds.verticalAlign == null ? null : ds.verticalAlign;
  }
  return rec;
}

function run(c, lib) {
  const chart = init(lib);
  try {
    const option = clone(c.option);
    option.animation = false;
    const written = clone(option);
    chart.setOption(option);
    chart.renderToSVGString();
    const ecModel = chart.getModel();
    const grid = ecModel.getComponent('grid', 0);
    const cs = grid.coordinateSystem;
    const cart = cs.getCartesians()[0];
    const rect = cs.getRect();
    const area = cart.getArea();
    const record = { name: c.name, option: written };
    if (c.deferred) record.deferred = true;
    record.grid = hexOf(rect, RECT);
    record.gridText = textOf(rect, RECT);
    record.area = hexOf(area, RECT);
    record.areaText = textOf(area, RECT);
    let baseDim = null;
    let pictorial = false;
    const items = [];
    const backgrounds = [];
    ecModel.eachSeries(s => {
      const dim = s.getBaseAxis().dim;
      if (baseDim === null) baseDim = dim;
      else if (baseDim !== dim) throw new Error(c.name + ': the series disagree on the base axis');
      const isPictorial = s.subType === 'pictorialBar';
      if (s.subType !== 'bar' && !isPictorial) throw new Error(c.name + ': a ' + s.subType + ' series');
      pictorial = pictorial || isPictorial;
      const valueWH = dim === 'x' ? 'height' : 'width';
      const valueXY = dim === 'x' ? 'y' : 'x';
      const data = s.getData();
      const view = chart.getViewOfSeriesModel(s);
      const count = s.getRawData().count();
      for (let r = 0; r < count; r++) {
        const where = c.name + ' s' + s.seriesIndex + '[' + r + ']';
        const k = data.indexOfRawIndex(r);
        const el = k >= 0 ? data.getItemGraphicEl(k) : null;
        const L = k >= 0 ? data.getItemLayout(k) : null;
        const item = { seriesIndex: s.seriesIndex, dataIndex: r };
        item.class = !el ? 'none' : el.ignore ? 'hidden' : 'drawn';
        item.layout = L && finiteRect(L) ? hexOf(L, RECT) : null;
        item.layoutText = L ? textOf(L, RECT) : null;
        // the element that carries the shape and the label
        const host = !el ? null : isPictorial ? el.__pictorialBarRect : el;
        if (el && (!host || !host.shape || host.shape.width === undefined)) {
          throw new Error(where + ': an element with no rect shape');
        }
        const shape = host ? host.shape : null;
        if (shape && item.class === 'drawn' && !finiteRect(shape)) throw new Error(where + ': a drawn bar with a non-finite shape');
        if (shape && finiteRect(shape)) {
          item.shape = hexOf(shape, RECT);
          item.shapeText = textOf(shape, RECT);
          const box = boxOf(shape);
          item.box = hexOf(box, BOX);
          item.boxText = textOf(box, BOX);
          item.zeroLength = shape[valueWH] === 0;
        } else {
          item.shape = null;
          item.shapeText = shape ? textOf(shape, RECT) : null;
          item.box = null;
          item.boxText = null;
          item.zeroLength = null;
        }
        if (isPictorial) {
          if (L && Number.isFinite(L[valueXY])) {
            item.floor = hex(L[valueXY]);
            item.floorText = text(L[valueXY]);
          } else {
            item.floor = null;
            item.floorText = L ? text(L[valueXY]) : null;
          }
        }
        item.label = labelRecord(el, host, item.class === 'drawn', where);
        items.push(item);
        const bgEls = view && view._backgroundEls;
        if (bgEls && bgEls.length) {
          const bg = k >= 0 ? bgEls[k] : null;
          backgrounds.push({
            seriesIndex: s.seriesIndex,
            dataIndex: r,
            shape: bg && finiteRect(bg.shape) ? hexOf(bg.shape, RECT) : null,
            shapeText: bg ? textOf(bg.shape, RECT) : null,
          });
        }
      }
    });
    record.baseAxis = baseDim;
    record.axes = { x: axisRecord(cart.getAxis('x')), y: axisRecord(cart.getAxis('y')) };
    if (pictorial) record.pictorial = true;
    record.items = items;
    if (backgrounds.length) record.backgrounds = backgrounds;
    return record;
  } finally {
    chart.dispose();
  }
}

// ---------- cases ----------

const cases = [];
// Every case pins its grid with outerBoundsMode 'none': the grid's rect IS the
// plot, so the bars are measured in a plot both sides agree on. Where the
// labels push the plot under the default 'auto' is a question of its own
// (the outer-bounds oracle), not one this file asks.
const add = (name, option, extra) => cases.push(Object.assign({ name,
  option: Object.assign({ grid: { outerBoundsMode: 'none' } }, option) }, extra || {}));
const deferred = { deferred: true };
const cats = n => ['a', 'b', 'c', 'd', 'e', 'f'].slice(0, n);
const shown = { show: true };

// One bar series upright over categories (V) or lying down (H). `axis` is merged
// into the value axis, `series` into the series; the label is shown unless the
// series says otherwise.
function V(data, axis, series, n) {
  return {
    xAxis: { type: 'category', data: cats(n || data.length) },
    yAxis: Object.assign({ type: 'value' }, axis || {}),
    series: [Object.assign({ type: 'bar', data, label: shown }, series || {})],
  };
}
function H(data, axis, series, n) {
  return {
    yAxis: { type: 'category', data: cats(n || data.length) },
    xAxis: Object.assign({ type: 'value' }, axis || {}),
    series: [Object.assign({ type: 'bar', data, label: shown }, series || {})],
  };
}
// A stack 't' of bar series, one per row of `rows`.
function stackV(rows, axis, series) {
  return {
    xAxis: { type: 'category', data: cats(rows[0].length) },
    yAxis: Object.assign({ type: 'value' }, axis || {}),
    series: rows.map(d => Object.assign({ type: 'bar', stack: 't', data: d, label: shown }, series || {})),
  };
}
// Bar series side by side (no stack), one per row of `rows`.
function multiV(rows, axis, series) {
  return {
    xAxis: { type: 'category', data: cats(rows[0].length) },
    yAxis: Object.assign({ type: 'value' }, axis || {}),
    series: rows.map(d => Object.assign({ type: 'bar', data: d, label: shown }, series || {})),
  };
}
function stackH(rows, axis, series) {
  return {
    yAxis: { type: 'category', data: cats(rows[0].length) },
    xAxis: Object.assign({ type: 'value' }, axis || {}),
    series: rows.map(d => Object.assign({ type: 'bar', stack: 't', data: d, label: shown }, series || {})),
  };
}

const D = [5, -3, 0, 1e-9];
const outside = { label: { show: true, position: 'outside' } };

// R1: the value-axis start
add('V [5,-3,0,1e-9]', V(D));
add('H [5,-3,0,1e-9]', H(D));
add('V startValue 2 [5,-3,0,1e-9]', V(D, { startValue: 2 }));
add('H startValue 2 [5,-3,0,1e-9]', H(D, { startValue: 2 }));
add('V all negative [-5,-3,-8]', V([-5, -3, -8]));
add('V scale:true all negative [-5,-3,-8]', V([-5, -3, -8], { scale: true }));
add('V scale:true [5,8,9], no startValue', V([5, 8, 9], { scale: true }));
add('V scale:true startValue 2 [5,8,9]', V([5, 8, 9], { scale: true, startValue: 2 }));
add('V startValue 20 [5,8,9]', V([5, 8, 9], { startValue: 20 }));
add('V startValue -5 [5,8,9]', V([5, 8, 9], { startValue: -5 }));
add('V startValue 3 [5,1,3]', V([5, 1, 3], { startValue: 3 }));
add('V startValue -2 [5,7]', V([5, 7], { startValue: -2 }));
add("V startValue 'abc' is no start value [5,-3]", V([5, -3], { startValue: 'abc' }));
add('V min 2 [2,1,8]', V([2, 1, 8], { min: 2 }));
add('V min 2 [2,1,8] clip:false', V([2, 1, 8], { min: 2 }, { clip: false }));
add('V log [1,10,100]', V([1, 10, 100], { type: 'log' }));
add('V log [0.5,100,1000]', V([0.5, 100, 1000], { type: 'log' }));
add('V log [5,50,500]', V([5, 50, 500], { type: 'log' }));
add('V log [0,-1,10]: no bar for 0 or -1', V([0, -1, 10], { type: 'log' }));
add('V log min 10 [1,10,100]', V([1, 10, 100], { type: 'log', min: 10 }));
add('V log startValue 0.5 [1,10,100]', V([1, 10, 100], { type: 'log', startValue: 0.5 }));
add('V log startValue 0 [1,10,100]: no bars', V([1, 10, 100], { type: 'log', startValue: 0 }));
add('V inverse [5,-3,0,1e-9]', V(D, { inverse: true }));
add('H inverse [5,-3,0,1e-9]', H(D, { inverse: true }));
// bars on a VALUE base axis take their width from the smallest gap in the data
// and widen the axis' mapping extent to fit (containShape: x maps [-0.5, 4.5]
// while its effective extent stays [0, 4]; contain-shape.js asks that question
// in full). Their value-axis start is this file's rule.
add('value base axis [[1,5],[2,-3],[4,2]]', {
  xAxis: { type: 'value' }, yAxis: { type: 'value' },
  series: [{ type: 'bar', data: [[1, 5], [2, -3], [4, 2]], label: shown }],
});
// R4: a bar of no length keeps its element and its label
add('V [0,5]: the 0 bar has no length', V([0, 5]));
add('V scale:true [100,120,130]: the 100 bar has no length', V([100, 120, 130], { scale: true }));

// R2: the stacked base
add('stack mixed 3 series x 5', stackV([[5, -3, 4, -2, 0], [3, -4, -2, 1, 2], [1, 2, -1, -1, -3]]));
add('stack startValue 2', stackV([[5, -3, 4], [3, -4, -2]], { startValue: 2 }));
add('stack NaN inside', stackV([[5, '-', 4], [3, 2, '-'], [1, 1, 1]]));
add('stack min 10 max 100, bottom 40', stackV([[40, 50], [20, 30]], { min: 10, max: 100 }));
add('stack min 10 max 100, bottom 40, clip:false', stackV([[40, 50], [20, 30]], { min: 10, max: 100 }, { clip: false }));
add('H stack startValue 2', stackH([[5, -3, 4], [3, -4, -2]], { startValue: 2 }));
// an upper member grows from the one below it, not from the start: 3 on 5
// with the start at 20 still runs right, and its outside label is right of it
add('H stack startValue 20 outside s1=[5] s2=[3]',
  stackH([[5], [3]], { startValue: 20 }, { label: { show: true, position: 'outside' } }));
add('H stack barMinHeight 10 s1=[5] s2=[0.001]', stackH([[5], [0.001]], null, { barMinHeight: 10 }));
add('log stack, upper member over a NaN', stackV([['-'], [10]], { type: 'log' }));
add('log stack s1=[10,100] s2=[10,10]', stackV([[10, 100], [10, 10]], { type: 'log' }));

// R3: barMinHeight from each member's own base
const minH = { barMinHeight: 10 };
add('V barMinHeight 10 [0,0.001,-0.001,5,-]', V([0, 0.001, -0.001, 5, '-'], null, minH));
add('H barMinHeight 10 [0,0.001,-0.001,5,-]', H([0, 0.001, -0.001, 5, '-'], null, minH));
add('V inverse barMinHeight 10 [0,0.001,-0.001,5]', V([0, 0.001, -0.001, 5], { inverse: true }, minH));
add('H inverse barMinHeight 10 [0,0.001,-0.001,5]', H([0, 0.001, -0.001, 5], { inverse: true }, minH));
add('V barMinHeight 10 startValue 2 [2,2.001,1.999]', V([2, 2.001, 1.999], { startValue: 2 }, minH));
add('V barMinHeight -10 does nothing [0,5]', V([0, 5], null, { barMinHeight: -10 }));
add('stack barMinHeight 10 s1=[0,5,0.001] s2=[0,0,0.001] s3=[3,0.001,0.001]',
  stackV([[0, 5, 0.001], [0, 0, 0.001], [3, 0.001, 0.001]], null, minH));
add('stack barMinHeight 10 s1=[5] s2=[0.001]', stackV([[5], [0.001]], null, minH));
add('stack barMinHeight 10 startValue 5 s1=[3] s2=[2]', stackV([[3], [2]], { startValue: 5 }, minH));
add('V barMinHeight 10 [0,-0.001] outside: clipped back to no length',
  V([0, -0.001], null, Object.assign({}, minH, outside)));
// a 0 the minimum lengthens is 10 px long and runs right: outside is right
add('H barMinHeight 10 [0,5] outside', H([0, 5], null, { barMinHeight: 10, label: { show: true, position: 'outside' } }));
add('H barMinHeight 10 [0,-0.001] outside: clipped back to no length',
  H([0, -0.001], null, Object.assign({}, minH, outside)));
add('V barMinHeight 10 min 50 [30,80,120,50]', V([30, 80, 120, 50], { min: 50 }, minH));

// R5: clip
add('V min 50 [30,80,120,50]', V([30, 80, 120, 50], { min: 50 }));
add('V min 50 max 100 [30,80,120] outside', V([30, 80, 120], { min: 50, max: 100 }, outside));
add('V min 50 max 100 [30,80,120] clip:false top',
  V([30, 80, 120], { min: 50, max: 100 }, { clip: false, label: { show: true, position: 'top' } }));
add('H min 50 max 100 [30,80,120]', H([30, 80, 120], { min: 50, max: 100 }));
add('V far side: min 50 max 100 startValue 120 [150]', V([150], { min: 50, max: 100, startValue: 120 }));
add('V 4 data on 3 categories', V([1, 2, 3, 4], null, null, 3));
add('V min -10 max 10 [5,-3,20,-20,0] outside', V([5, -3, 20, -20, 0], { min: -10, max: 10 }, outside));

// R6: 'outside' resolved per bar, other words never flipped
add('V outside [5,-3,0,1e-9]', V(D, null, outside));
add('H outside [5,-3,0,1e-9]', H(D, null, outside));
add('V inverse outside [5,-3,0,1e-9]', V(D, { inverse: true }, outside));
add('H inverse outside [5,-3,0,1e-9]', H(D, { inverse: true }, outside));
for (const p of ['top', 'insideTop', 'bottom']) {
  const label = { label: { show: true, position: p } };
  add('V ' + p + ' [5,-3,0,1e-9]', V(D, null, label));
  add('H ' + p + ' [5,-3,0,1e-9]', H(D, null, label));
}
add('V outside startValue 2 [5,-3,0,2]', V([5, -3, 0, 2], { startValue: 2 }, outside));
add('V outside scale:true [-5,-3,-8]: -3 clipped to no length', V([-5, -3, -8], { scale: true }, outside));
add('V outside inverse min 50 [80,50]: 50 has no length', V([80, 50], { min: 50, inverse: true }, outside));
add('H outside min 50 [80,50]: 50 has no length', H([80, 50], { min: 50 }, outside));
add('V outside min 50 [30,80,120,50]', V([30, 80, 120, 50], { min: 50 }, outside));

// pictorialBar: only the floor edge is compared
add('pictorial V [5,-3] rect', {
  xAxis: { type: 'category', data: cats(2) }, yAxis: { type: 'value' },
  series: [{ type: 'pictorialBar', symbol: 'rect', data: [5, -3] }],
});
add('pictorial H [5,-3] rect', {
  yAxis: { type: 'category', data: cats(2) }, xAxis: { type: 'value' },
  series: [{ type: 'pictorialBar', symbol: 'rect', data: [5, -3] }],
});

// Parse parity (D9, wf53 G1..G8): a raw string is Number(s) ('   ' is 0,
// '0x10' is 16, 'Infinity' is +Inf); a series whose extent has a non-finite
// end adds nothing to the axis (util/model.ts:1258-1264), so alone it leaves
// the axis blank at [0,1] and its finite bars overrun and are clipped; a log
// axis filters +Inf out instead (Log.ts:236-238); a stack's calculated column
// carries the Inf into the member above it.
add("G1 V ['   ','0x10',5]", V(['   ', '0x10', 5]));
add("G2 V ['Infinity',5,3]: blank axis", V(['Infinity', 5, 3]));
add("G3 [5,10,1]+['Infinity',3,2]: the Inf series adds nothing", multiV([[5, 10, 1], ['Infinity', 3, 2]]));
add("G4 V ['Infinity',5,3] min 0 max 20", V(['Infinity', 5, 3], { min: 0, max: 20 }));
add("G5 V ['Infinity',5,3] max 20: still blank", V(['Infinity', 5, 3], { max: 20 }));
add("G6 V log ['Infinity',5,3]", V(['Infinity', 5, 3], { type: 'log' }));
add("G7 stack ['Infinity',5,3]+[2,2,2]", stackV([['Infinity', 5, 3], [2, 2, 2]]));
add("G8 stack [2,2,2]+['Infinity',5,3]", stackV([[2, 2, 2], ['Infinity', 5, 3]]));

// deferred: the border inset (D6), background strips on gap rows (D5),
// barMinWidth 0 still floors the width at 1 (D7)
add('V borderWidth 2 [5,-3,0,1e-9]', V(D, null, { itemStyle: { borderColor: '#000', borderWidth: 2 } }), deferred);
add('V showBackground [5,-,null,3]', V([5, '-', null, 3], null, { showBackground: true }), deferred);
add('H showBackground [5,-,null,3]', H([5, '-', null, 3], null, { showBackground: true }), deferred);
add('V barCategoryGap 100% barMinWidth 0 [5,3]', V([5, 3], null, { barCategoryGap: '100%', barMinWidth: 0 }), deferred);

// ---------- run and write ----------

{
  const names = new Set();
  for (const c of cases) {
    if (names.has(c.name)) throw new Error('two cases named ' + c.name);
    names.add(c.name);
  }
}

function runEither(c) {
  try {
    return run(c, echarts);
  } catch (e) {
    console.log(c.name + ': the development build threw (' + e.message + ')');
    return Object.assign(run(c, PROD), { productionBuild: true });
  }
}

const out = { source: 'ECharts ' + echarts.version, cases: cases.map(runEither) };

// A number JSON.stringify would write as an integer literal past 2^63 goes
// out in exponent form instead: marked in the replacer, unquoted afterwards.
const BIG = 9223372036854775808;
const json = JSON.stringify(out, (k, v) => (typeof v === 'number' && Number.isFinite(v)
  && Math.abs(v) >= BIG && Math.abs(v) < 1e21 ? '@@num:' + v.toExponential() + '@@' : v), 1)
  .replace(/"@@num:([^"@]+)@@"/g, '$1');

const prod = out.cases.filter(c => c.productionBuild).map(c => c.name);
if (prod.length) console.log('through the production build:', prod.join(', '));
const tally = {};
out.cases.forEach(c => c.items.forEach(it => { tally[it.class] = (tally[it.class] || 0) + 1; }));
fs.writeFileSync(OUT, json + '\n');
const d = out.cases.filter(c => c.deferred).length;
console.log('wrote', OUT, (out.cases.length - d) + ' cases + ' + d + ' deferred, items',
  Object.keys(tally).map(k => k + ' ' + tally[k]).join(', '));
process.exit(0);
